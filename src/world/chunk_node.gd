class_name ChunkNode
extends Node3D
## Scene representation of one chunk snapshot. Heavy array work happens on worker
## threads via the static build_* functions; this node only uploads the results.

const SIZE := ChunkGenerator.SIZE
const RES := ChunkGenerator.RES

static var terrain_material: ShaderMaterial
static var grass_material: ShaderMaterial
static var grass_mesh: ArrayMesh

var data: Dictionary
var key: Vector2i
var lod := 1
var near := false

var _terrain: MeshInstance3D
var _body: StaticBody3D
var _height_shape: CollisionShape3D
var _mm: Dictionary = {} ## type -> MultiMeshInstance3D
var _obj_bodies: Dictionary = {} ## object index -> StaticBody3D
var _grass: MultiMeshInstance3D
var _clutter: Array = []

static func ensure_shared() -> void:
	if terrain_material == null:
		terrain_material = ShaderMaterial.new()
		terrain_material.shader = load("res://src/world/terrain.gdshader")
		grass_material = ShaderMaterial.new()
		grass_material.shader = load("res://src/world/grass.gdshader")
		grass_mesh = _make_blade()

static func _make_blade() -> ArrayMesh:
	# A clump of 9 tapered, curved blades: far more blades per instance for the cost.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for b in 9:
		var off := Vector3(r.randf_range(-0.28, 0.28), 0, r.randf_range(-0.28, 0.28))
		var yaw := r.randf() * TAU
		var h := r.randf_range(0.28, 0.6)
		var lean := r.randf_range(0.05, 0.22)
		var basis := Basis(Vector3.UP, yaw)
		var pts: Array = []
		for i in 4:
			var t := i / 3.0
			var w := 0.032 * (1.0 - t * 0.9)
			var c := off + basis * Vector3(0, t * h, t * t * lean)
			pts.append([c + basis * Vector3(-w, 0, 0), c + basis * Vector3(w, 0, 0), t])
		var n := basis * Vector3(0, 0.4, -1).normalized()
		for i in 3:
			var a: Array = pts[i]
			var bb: Array = pts[i + 1]
			for v in [[a[0], a[2]], [bb[0], bb[2]], [a[1], a[2]], [a[1], a[2]], [bb[0], bb[2]], [bb[1], bb[2]]]:
				st.set_normal(n)
				st.set_uv(Vector2(0.5, v[1]))
				st.add_vertex(v[0])
	return st.commit()

# --- Worker-thread builders ---------------------------------------------------

## Terrain arrays at a given LOD step (1, 2 or 4). Far LODs get skirts to hide cracks.
static func build_terrain_arrays(chunk: Dictionary, step: int) -> Array:
	var hs: PackedFloat32Array = chunk["heights"]
	var wb: PackedByteArray = chunk["weights"]
	var n := SIZE / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var gi := i * step
			var gj := j * step
			var k := gj * RES + gi
			var v := j * n + i
			verts[v] = Vector3(gi, hs[k], gj)
			var hl := hs[gj * RES + maxi(gi - 1, 0)]
			var hr := hs[gj * RES + mini(gi + 1, RES - 1)]
			var hd := hs[maxi(gj - 1, 0) * RES + gi]
			var hu := hs[mini(gj + 1, RES - 1) * RES + gi]
			var dx := float(mini(gi + 1, RES - 1) - maxi(gi - 1, 0))
			var dz := float(mini(gj + 1, RES - 1) - maxi(gj - 1, 0))
			norms[v] = Vector3(-(hr - hl) / dx, 1.0, -(hu - hd) / dz).normalized()
			var wk := k * Eras.COUNT
			cols[v] = Color(wb[wk] / 255.0, wb[wk + 1] / 255.0, wb[wk + 2] / 255.0)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Clockwise from above (Godot front faces).
			idx.append_array([a, b, d, a, d, c])
	if step > 1:
		_add_skirts(n, verts, norms, cols, idx, 3.0 * step)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

static func _add_skirts(n: int, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, depth: float) -> void:
	var edges := []
	var e0 := []
	var e1 := []
	var e2 := []
	var e3 := []
	for i in n:
		e0.append(i)                   # z = 0
		e1.append((n - 1) * n + i)     # z = max
		e2.append(i * n)               # x = 0
		e3.append(i * n + n - 1)       # x = max
	edges = [e0, e1, e2, e3]
	for e in edges:
		var base := verts.size()
		for v in e:
			verts.append(verts[v] - Vector3(0, depth, 0))
			norms.append(norms[v])
			cols.append(cols[v])
		for i in e.size() - 1:
			var a: int = e[i]
			var b: int = e[i + 1]
			var c: int = base + i
			var d: int = base + i + 1
			# Double-sided so orientation does not matter.
			idx.append_array([a, b, d, a, d, c, a, d, b, a, c, d])

## Per-mesh MultiMesh buffers (transform + tint) for all objects still present. Each
## instance gets its own slight tint and proportions, so even two of the same variant
## never look identical.
static func build_object_buffers(chunk: Dictionary) -> Dictionary:
	var by_key := {}
	var seed: int = int(chunk.get("seed", 0)) ^ (int(chunk["cx"]) * 73856093) ^ (int(chunk["cz"]) * 19349663)
	for o in chunk["objects"]:
		if o["st"].get("gone", false):
			continue
		var key := ObjectLibrary.mesh_key(o)
		if not by_key.has(key):
			by_key[key] = PackedFloat32Array()
		var h := WHash.combine(seed, int(o["i"]))
		var u1 := WHash.to_unit(h)
		var u2 := WHash.to_unit(WHash.h32(h))
		var s: float = o["s"]
		var k := ObjectLibrary.kind(o["t"])
		var organic := k == "tree" or k == "rock" or k == "ore"
		var sy := s * (lerpf(0.88, 1.15, u1) if organic else 1.0)
		var b := Basis(Vector3.UP, o["r"]).scaled(Vector3(s, sy, s))
		var p: Vector3 = o["p"]
		# Sink slightly so bases never float on slopes.
		p.y -= 0.15 * s
		var tint := Color(1, 1, 1)
		if organic:
			var v := lerpf(0.86, 1.1, u2)
			tint = Color(v * lerpf(0.96, 1.04, u1), v, v * lerpf(0.96, 1.04, 1.0 - u1))
		var buf: PackedFloat32Array = by_key[key]
		buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, 1.0])
		by_key[key] = buf
	return by_key

static func build_grass_buffer(chunk: Dictionary, density: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	if density <= 0.0:
		return buf
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 901)
	var biome_tint := Color(0, 0, 0, 0)
	var biome_era: int = chunk.get("era", 0)
	if chunk.has("biome"):
		var bp := Biome.params(chunk["biome"], biome_era)
		biome_tint = bp["grass_tint"]
		biome_tint.a = 1.0
		density *= float(bp["grass_density"])
	var count := int(9000 * density)
	var blocked: Array = []
	for o in chunk["objects"]:
		var k: String = ObjectLibrary.kind(o["t"])
		if k == "structure" or k == "trader":
			blocked.append(Vector2(o["p"].x, o["p"].z))
	for n in count:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.6, 1.5)
		var pick := r.randf()
		var w := ChunkGenerator.weights_at(chunk, lx, lz)
		var dens := w[0] * Eras.GRASS_DENSITY[0] + w[1] * Eras.GRASS_DENSITY[1] + w[2] * Eras.GRASS_DENSITY[2]
		if pick > dens:
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.55:
			continue
		var skip := false
		for b in blocked:
			if b.distance_squared_to(Vector2(lx, lz)) < 20.0:
				skip = true
				break
		if skip:
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.15:
			continue
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.7, 1.4), sc))
		var tint := Color(0.33, 0.50, 0.16) * w[0] + Color(0.12, 0.55, 0.5) * w[1] + Color(0.35, 0.38, 0.3) * w[2]
		tint = tint.lerp(Color(0.55, 0.52, 0.25), r.randf() * 0.25 * w[0])
		if biome_tint.a > 0.0:
			tint = tint.lerp(biome_tint, w[biome_era] * 0.7)
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
			tint.r, tint.g, tint.b, w[1] * 0.8])
	return buf

## Ground clutter (stones and flowers, tiny glowing mushrooms, alloy debris), keyed by
## clutter mesh name. Deterministic per chunk, regenerated freely (never gameplay state).
static func build_clutter_buffers(chunk: Dictionary, density: float) -> Dictionary:
	var out := {}
	if density <= 0.0:
		return out
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 902)
	for n in int(900 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var pick := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.7, 1.4)
		var w := ChunkGenerator.weights_at(chunk, lx, lz)
		var acc := 0.0
		var era := 0
		for e in Eras.COUNT:
			acc += w[e]
			if pick <= acc:
				era = e
				break
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.6:
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.2:
			continue
		var key := "clutter_%d" % era
		if not out.has(key):
			out[key] = PackedFloat32Array()
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
		var buf: PackedFloat32Array = out[key]
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
		out[key] = buf
	return out

# --- Main-thread upload ---------------------------------------------------------

func setup(chunk: Dictionary, terrain_arrays: Array, step: int, obj_buffers: Dictionary) -> void:
	ensure_shared()
	data = chunk
	key = Vector2i(chunk["cx"], chunk["cz"])
	name = "Chunk_%d_%d" % [key.x, key.y]
	position = Vector3(key.x * SIZE, 0, key.y * SIZE)
	_terrain = MeshInstance3D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	set_terrain(terrain_arrays, step)
	set_objects(obj_buffers)

func set_terrain(arrays: Array, step: int) -> void:
	lod = step
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	_terrain.mesh = mesh
	if _height_shape != null:
		_update_height_shape()

func set_objects(buffers: Dictionary) -> void:
	for t in _mm:
		_mm[t].queue_free()
	_mm.clear()
	for t in buffers:
		var buf: PackedFloat32Array = buffers[t]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = ObjectLibrary.get_mesh(t)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + t.replace("#", "_")
		var k := ObjectLibrary.kind(t.get_slice("#", 0))
		if k == "structure" or k == "tree":
			mmi.visibility_range_end = 900.0
		else:
			mmi.visibility_range_end = 260.0
		add_child(mmi)
		_mm[t] = mmi

func set_grass(buf: PackedFloat32Array) -> void:
	if _grass != null:
		_grass.queue_free()
		_grass = null
	if buf.is_empty():
		set_clutter({})
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = grass_mesh
	mm.instance_count = buf.size() / 16
	mm.buffer = buf
	_grass = MultiMeshInstance3D.new()
	_grass.multimesh = mm
	_grass.material_override = grass_material
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass.visibility_range_end = 110.0
	_grass.visibility_range_end_margin = 20.0
	_grass.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_grass.name = "Grass"
	add_child(_grass)

func set_clutter(buffers: Dictionary) -> void:
	for c in _clutter:
		c.queue_free()
	_clutter.clear()
	for t in buffers:
		var buf: PackedFloat32Array = buffers[t]
		if buf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ObjectLibrary.get_mesh(t)
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 70.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.visibility_range_end_margin = 10.0
		add_child(mmi)
		_clutter.append(mmi)

func has_grass() -> bool:
	return _grass != null

## Collision and interactive bodies only exist near the player.
func set_near(on: bool) -> void:
	if on == near:
		return
	near = on
	if on:
		_body = StaticBody3D.new()
		_body.name = "Ground"
		_body.set_meta("chunk", self)
		_body.collision_layer = 1
		_height_shape = CollisionShape3D.new()
		_body.add_child(_height_shape)
		add_child(_body)
		_update_height_shape()
		for o in data["objects"]:
			if not o["st"].get("gone", false):
				_add_obj_body(o)
	else:
		if _body:
			_body.queue_free()
		_body = null
		_height_shape = null
		for i in _obj_bodies:
			_obj_bodies[i].queue_free()
		_obj_bodies.clear()

func _update_height_shape() -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = RES
	hm.map_depth = RES
	hm.map_data = data["heights"]
	_height_shape.shape = hm
	_height_shape.position = Vector3(SIZE * 0.5, 0, SIZE * 0.5)

func _add_obj_body(o: Dictionary) -> void:
	var sh: Array = ObjectLibrary.get_shape(o["t"])
	var b := StaticBody3D.new()
	b.collision_layer = 2
	b.set_meta("chunk", self)
	b.set_meta("obj", o["i"])
	var cs := CollisionShape3D.new()
	cs.shape = sh[0]
	cs.position = sh[1]
	b.add_child(cs)
	b.position = o["p"]
	b.rotation.y = o["r"]
	var s: float = o["s"]
	b.scale = Vector3(s, s, s)
	add_child(b)
	_obj_bodies[o["i"]] = b

func get_object(i: int) -> Dictionary:
	return data["objects"][i]

## Permanently removes an object (felled, mined out). Its record stays with gone=true.
func remove_object(i: int) -> void:
	var o: Dictionary = data["objects"][i]
	o["st"]["gone"] = true
	if _obj_bodies.has(i):
		_obj_bodies[i].queue_free()
		_obj_bodies.erase(i)
	set_objects(build_object_buffers(data))
	Game.mark_chunk_dirty(data)

## Lowers terrain in a smooth crater around local point (lx, lz). Returns true if changed.
func dig(lx: float, lz: float, radius: float, depth: float) -> bool:
	var hs: PackedFloat32Array = data["heights"]
	var changed := false
	for j in range(maxi(0, int(lz - radius)), mini(RES - 1, int(lz + radius) + 1) + 1):
		for i in range(maxi(0, int(lx - radius)), mini(RES - 1, int(lx + radius) + 1) + 1):
			var d := Vector2(i - lx, j - lz).length() / radius
			if d >= 1.0:
				continue
			var f := (1.0 - d * d)
			hs[j * RES + i] -= depth * f * f
			changed = true
	if changed:
		data["heights"] = hs
		Game.mark_chunk_dirty(data)
	return changed
