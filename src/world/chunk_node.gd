class_name ChunkNode
extends Node3D
## Scene representation of one chunk snapshot. Heavy array work happens on worker
## threads via the static build_* functions; this node only uploads the results.

const SIZE := ChunkGenerator.SIZE
const RES := ChunkGenerator.RES

static var terrain_material: ShaderMaterial
static var grass_material: ShaderMaterial
static var grass_mesh: ArrayMesh
static var river_material: ShaderMaterial

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

const TERRAIN_TEXTURES := ["grass", "dirt", "glowmoss", "darksoil", "regolith", "rock", "mud", "snow"]

static func ensure_shared() -> void:
	if terrain_material == null:
		terrain_material = ShaderMaterial.new()
		terrain_material.shader = load("res://src/world/terrain.gdshader")
		var all := true
		for t in TERRAIN_TEXTURES:
			var a := Materials.photo(t, "albedo")
			var n := Materials.photo(t, "normal")
			all = all and a != null and n != null
			terrain_material.set_shader_parameter(t + "_tex", a)
			terrain_material.set_shader_parameter(t + "_nrm", n)
		terrain_material.set_shader_parameter("use_textures", all)
		terrain_material.set_shader_parameter("snow_line", Planets.snow_line)
		grass_material = ShaderMaterial.new()
		grass_material.shader = load("res://src/world/grass.gdshader")
		grass_mesh = _make_blade()
		river_material = ShaderMaterial.new()
		river_material.shader = load("res://src/env/river.gdshader")

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
	var rb: PackedByteArray = chunk.get("road", PackedByteArray())
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	var n := SIZE / step + 1
	# Packed arrays held in an Array are copied on access, so the three look streams
	# are separate locals (passed to helpers by reference).
	var has_look := not lb.is_empty()
	var human := Eras.theme == "human"
	var l0 := PackedByteArray()
	var l1 := PackedByteArray()
	var l2 := PackedByteArray()
	if has_look:
		l0.resize(n * n * 4)
		l1.resize(n * n * 4)
		l2.resize(n * n * 4)
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
			# Alpha: 1 minus how much road surface shows (roads and village squares).
			# Human worlds dress their sci-fi land as the medieval wilds (Eras.look).
			var ws := 0.0 if human else wb[wk + 2] / 255.0
			cols[v] = Color((wb[wk] + (wb[wk + 2] if human else 0)) / 255.0, wb[wk + 1] / 255.0, ws, 1.0 - (rb[k] / 255.0 if not rb.is_empty() else 0.0))
			if has_look:
				_look_at(lb, gi, gj, l0, l1, l2, v * 4)
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
		if has_look:
			_skirt_looks(n, l0, l1, l2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	if has_look:
		arr[Mesh.ARRAY_CUSTOM0] = l0
		arr[Mesh.ARRAY_CUSTOM1] = l1
		arr[Mesh.ARRAY_CUSTOM2] = l2
	return arr

## Vertex format flags for terrain arrays that carry a landform look.
const LOOK_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)

## The landform look at grid point (gi, gj), interpolated from the chunk's 4 m grid into
## the three custom arrays at byte `at`.
static func _look_at(lb: PackedByteArray, gi: int, gj: int, l0: PackedByteArray, l1: PackedByteArray, l2: PackedByteArray, at: int) -> void:
	const N := ChunkGenerator.LOOK_N
	var ci := mini(gi / ChunkGenerator.LOOK_STEP, N - 2)
	var cj := mini(gj / ChunkGenerator.LOOK_STEP, N - 2)
	var fx := (gi - ci * ChunkGenerator.LOOK_STEP) / float(ChunkGenerator.LOOK_STEP)
	var fz := (gj - cj * ChunkGenerator.LOOK_STEP) / float(ChunkGenerator.LOOK_STEP)
	var k00 := (cj * N + ci) * ChunkGenerator.LOOK_BYTES
	var k10 := k00 + ChunkGenerator.LOOK_BYTES
	var k01 := k00 + N * ChunkGenerator.LOOK_BYTES
	var k11 := k01 + ChunkGenerator.LOOK_BYTES
	for b in 4:
		l0[at + b] = int(round(lerpf(lerpf(lb[k00 + b], lb[k10 + b], fx), lerpf(lb[k01 + b], lb[k11 + b], fx), fz)))
		l1[at + b] = int(round(lerpf(lerpf(lb[k00 + b + 4], lb[k10 + b + 4], fx), lerpf(lb[k01 + b + 4], lb[k11 + b + 4], fx), fz)))
		l2[at + b] = int(round(lerpf(lerpf(lb[k00 + b + 8], lb[k10 + b + 8], fx), lerpf(lb[k01 + b + 8], lb[k11 + b + 8], fx), fz)))

## Skirt vertices (added in _add_skirts' edge order) copy their edge vertex's look.
static func _skirt_looks(n: int, l0: PackedByteArray, l1: PackedByteArray, l2: PackedByteArray) -> void:
	var edges: Array = [[], [], [], []]
	for i in n:
		edges[0].append(i)
		edges[1].append((n - 1) * n + i)
		edges[2].append(i * n)
		edges[3].append(i * n + n - 1)
	for e in edges:
		for v in e:
			l0.append_array(l0.slice(v * 4, v * 4 + 4))
			l1.append_array(l1.slice(v * 4, v * 4 + 4))
			l2.append_array(l2.slice(v * 4, v * 4 + 4))

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
		var built := k == "built"
		var sy := s * (lerpf(0.88, 1.15, u1) if organic else 1.0)
		var b := Basis(Vector3.UP, o["r"]).scaled(Vector3(s, sy, s))
		var p: Vector3 = o["p"]
		# Sink slightly so bases never float on slopes.
		if not built:
			p.y -= 0.15 * s
		var tint := Color(1, 1, 1)
		if organic:
			var v := lerpf(0.86, 1.1, u2)
			tint = Color(v * lerpf(0.96, 1.04, u1), v, v * lerpf(0.96, 1.04, 1.0 - u1))
		if k == "rock":
			# Boulders are made of the landform's own stone (pale limestone among karst
			# towers, black basalt under the needles).
			var st := ChunkGenerator.stone_at(chunk, p.x, p.z)
			if st.a > 0.0:
				var to := Color(clampf(st.r / 0.5, 0.45, 1.5), clampf(st.g / 0.5, 0.45, 1.5), clampf(st.b / 0.5, 0.45, 1.5))
				tint = tint * Color(1, 1, 1).lerp(to, st.a * 0.85)
		var row := [b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, 1.0]
		var buf: PackedFloat32Array = by_key[key]
		buf.append_array(row)
		by_key[key] = buf
		# A room you can walk into brings its furniture (drawn up close) and any lamplit
		# windows (from further off) as their own meshes.
		if KitHouse.has(key) or Interiors.has(key):
			for extra in [key + "~in", key + "~glow"] if KitHouse.has(key) or Interiors.glows(key) else [key + "~in"]:
				var eb: PackedFloat32Array = by_key.get(extra, PackedFloat32Array())
				eb.append_array(row)
				by_key[extra] = eb
	return by_key

static func build_grass_buffer(chunk: Dictionary, density: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	if density <= 0.0:
		return buf
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 901)
	var biome_tint := Color(0, 0, 0, 0)
	var biome_era: int = Eras.nature(chunk.get("era", 0))
	var lumen := 0.0
	if chunk.has("biome"):
		var bp := Biome.params(chunk["biome"], biome_era)
		lumen = bp["lumen"]
		biome_tint = bp["grass_tint"]
		biome_tint.a = 1.0
		density *= float(bp["grass_density"])
	var count := int(9000 * density)
	var has_cave := false
	for o in chunk["objects"]:
		if o["t"] == "cave":
			has_cave = true
	var blocked: Array = []
	for o in chunk["objects"]:
		var k: String = ObjectLibrary.kind(o["t"])
		if (k == "structure" or k == "trader" or k == "built") and not o["st"].get("gone", false):
			blocked.append(Vector2(o["p"].x, o["p"].z))
	for n in count:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.6, 1.5)
		var pick := r.randf()
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var dens := w[0] * Eras.GRASS_DENSITY[0] + w[1] * Eras.GRASS_DENSITY[1] + w[2] * Eras.GRASS_DENSITY[2]
		if pick > dens:
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.55:
			continue
		if pick > dens * ChunkGenerator.cover_at(chunk, lx, lz):
			continue
		var skip := false
		for b in blocked:
			if b.distance_squared_to(Vector2(lx, lz)) < 20.0:
				skip = true
				break
		if skip:
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.15 or ChunkGenerator.under_river(chunk, lx, lz):
			continue
		var on_road := ChunkGenerator.road_at(chunk, lx, lz)
		if on_road > 0.5 or (on_road > 0.0 and r.randf() < on_road * 1.6):
			continue
		if has_cave and ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.7, 1.4), sc))
		var tint := Color(0.33, 0.50, 0.16) * w[0] + Color(0.12, 0.55, 0.5) * w[1] + Color(0.35, 0.38, 0.3) * w[2]
		tint = tint.lerp(Color(0.55, 0.52, 0.25), r.randf() * 0.25 * w[0])
		if biome_tint.a > 0.0:
			tint = tint.lerp(biome_tint, w[biome_era] * 0.7)
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
			tint.r, tint.g, tint.b, w[biome_era] * lumen])
	return buf

## Ground clutter (stones and flowers, tiny glowing mushrooms, alloy debris), keyed by
## clutter mesh name. Deterministic per chunk, regenerated freely (never gameplay state).
static func build_clutter_buffers(chunk: Dictionary, density: float) -> Dictionary:
	var out := {}
	if density <= 0.0:
		return out
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 902)
	# Kit patches are heavier than the old procedural ones, so fewer of them.
	for n in int(600 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var pick := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.7, 1.4)
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
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
		if y < 0.2 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.3:
			continue
		var key := "clutter_%d" % era
		if not out.has(key):
			out[key] = PackedFloat32Array()
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
		var buf: PackedFloat32Array = out[key]
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
		out[key] = buf
	# Undergrowth: the region's own ferns, bushes, flowers and stranger things.
	if chunk.has("biome"):
		var era: int = Eras.nature(chunk.get("era", 0))
		var bp := Biome.params(chunk["biome"], era)
		var unders: Array = bp["under"]
		for n in int(420 * density * float(bp["under_density"]) * (0.6 if era == Eras.SCIFI else 1.0)):
			var lx := r.randf() * SIZE
			var lz := r.randf() * SIZE
			var pick := r.randi()
			var yaw := r.randf() * TAU
			var sc := r.randf_range(0.6, 1.5)
			# Clumps: undergrowth gathers where a low-frequency mask is high.
			var mask := sin(lx * 0.11 + float(chunk["cx"]) * 7.0) * cos(lz * 0.09 + float(chunk["cz"]) * 5.0)
			if mask < -0.2 + r.randf() * 0.4:
				continue
			var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
			if w[era] < 0.5 or ChunkGenerator.slope_at(chunk, lx, lz) > 0.6:
				continue
			# Bare sand and dust grow little (the size roll doubles as the chance).
			if (sc - 0.6) / 0.9 > ChunkGenerator.cover_at(chunk, lx, lz):
				continue
			var y := ChunkGenerator.height_at(chunk, lx, lz)
			if y < 0.3 or ChunkGenerator.under_river(chunk, lx, lz) or Flora.was_cleared(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.05 or ChunkGenerator.in_cave(chunk, lx, lz):
				continue
			var key := "under#%d#%d" % [unders[pick % unders.size()], era]
			if not out.has(key):
				out[key] = PackedFloat32Array()
			var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
			var buf: PackedFloat32Array = out[key]
			buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
			out[key] = buf
	return out

## Harvests the undergrowth plant nearest the segment from..to (world space) within
## `reach` of it: hides it, remembers it in the chunk (it does not grow back), and
## returns {"key": mesh key, "pos": world position}, or {} when nothing is there.
func harvest_under(from: Vector3, to: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for mmi in _clutter:
		var k: String = mmi.get_meta("key", "")
		if not k.begins_with("under"):
			continue
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			var sc := t.basis.get_scale().y
			if sc < 0.01:
				continue
			var at := position + t.origin
			var c := at + Vector3(0, 0.45 * sc, 0)
			var d := Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) - 0.3 * sc
			if d < best_d:
				best_d = d
				best = {"key": k, "pos": at, "mm": mm, "i": i, "local": t.origin}
	if best.is_empty():
		return {}
	var mm: MultiMesh = best["mm"]
	var o: Vector3 = best["local"]
	mm.set_instance_transform(best["i"], Transform3D(Basis.from_scale(Vector3.ZERO), o))
	var cl: PackedFloat32Array = data.get("cleared", PackedFloat32Array())
	cl.append_array([o.x, o.z])
	data["cleared"] = cl
	Game.mark_chunk_dirty(data)
	return {"key": best["key"], "pos": best["pos"]}

var _river: MeshInstance3D

func set_river(arrays: Array) -> void:
	if arrays.is_empty():
		return
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, river_material)
	_river = MeshInstance3D.new()
	_river.name = "River"
	_river.mesh = m
	_river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_river)

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
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, LOOK_FORMAT if arrays[Mesh.ARRAY_CUSTOM0] != null else 0)
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
		if t.ends_with("~in"):
			# Furniture inside houses: only when you could see in.
			mmi.visibility_range_end = 60.0
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif t.ends_with("~glow"):
			mmi.visibility_range_begin = 52.0
			mmi.visibility_range_begin_margin = 8.0
			mmi.visibility_range_end = 900.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif k == "structure" or k == "tree" or k == "built":
			mmi.visibility_range_end = 900.0
		else:
			_set_range(mmi, 260.0)
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
	_set_range(_grass, 110.0)
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
		mmi.set_meta("key", t)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_range(mmi, 110.0 if t.begins_with("under") else 70.0)
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.visibility_range_end_margin = 10.0
		add_child(mmi)
		_clutter.append(mmi)

## Draw distance of grass, clutter and small props scales with this (graphics setting
## "detail_distance"); trees and buildings keep their full range.
static var detail_mult := 1.0

func _set_range(gi: GeometryInstance3D, base: float) -> void:
	gi.set_meta("range", base)
	gi.visibility_range_end = base * detail_mult

## Re-applies detail_mult to everything already built in this chunk.
func apply_detail() -> void:
	for c in get_children():
		if c is GeometryInstance3D and c.has_meta("range"):
			c.visibility_range_end = float(c.get_meta("range")) * detail_mult

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
	var built := BuildCatalog.is_built(o["t"])
	var sh: Array = BuildCatalog.shape(o["t"]) if built else ObjectLibrary.shape_of(o)
	var b := StaticBody3D.new()
	b.collision_layer = 2
	b.set_meta("chunk", self)
	b.set_meta("obj", o["i"])
	var cs := CollisionShape3D.new()
	cs.shape = sh[0]
	cs.position = sh[1]
	if sh.size() > 2:
		cs.basis = sh[2]
	b.add_child(cs)
	# A hearth, lamps or screens light the room inside.
	for l in Interiors.lights(o["t"]):
		var hl := OmniLight3D.new()
		hl.light_color = l[1]
		hl.light_energy = l[2]
		hl.omni_range = l[3]
		hl.omni_attenuation = 1.4
		hl.shadow_enabled = false
		hl.distance_fade_enabled = true
		hl.distance_fade_begin = 40.0
		hl.distance_fade_length = 15.0
		hl.position = l[0]
		b.add_child(hl)
	if built:
		var lc = BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("light")
		if lc != null:
			var l := OmniLight3D.new()
			l.light_color = lc
			l.light_energy = 1.6
			l.omni_range = 7.0
			l.position = Vector3(0, 1.0, 0)
			l.shadow_enabled = false
			b.add_child(l)
	b.position = o["p"]
	b.rotation.y = o["r"]
	var s: float = o["s"]
	b.scale = Vector3(s, s, s)
	add_child(b)
	_obj_bodies[o["i"]] = b

## Adds something the player built. It becomes an ordinary object of this chunk, saved
## in its snapshot. `lp` is the chunk-local position.
func add_built(id: String, lp: Vector3, yaw: float, st: Dictionary) -> Dictionary:
	return add_object(BuildCatalog.PREFIX + id, lp, yaw, int(BuildCatalog.def(id).get("era", -1)), st)

## Adds an object at local point lp after generation (a piece you built, a supply pod a
## beacon called down) and keeps it in the snapshot.
func add_object(t: String, lp: Vector3, yaw: float, era: int, st: Dictionary) -> Dictionary:
	var o := {"i": data["objects"].size(), "t": t, "p": lp, "r": yaw, "s": 1.0, "e": era, "st": st}
	data["objects"].append(o)
	set_objects(build_object_buffers(data))
	if near:
		_add_obj_body(o)
	Game.mark_chunk_dirty(data)
	return o

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
