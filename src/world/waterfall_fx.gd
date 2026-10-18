class_name WaterfallFx
extends Node3D
## One drop of a waterfall (Waterfalls), as a chunk shows it: the water pouring over the
## lip in a curved sheet that breaks into white strands as it falls, the churned foam
## where it lands in the plunge pool, a drift of mist and spray carried off on the wind,
## and the roar. Built from the drop the chunk keeps (Waterfalls.chunk_drops).

const G := 9.8
const SPEED := 1.6 ## how fast the river comes over the lip, m/s
const ROWS := 14
const MIST_RANGE := 320.0 ## mist is drawn this close (it fades out before)

static var _sheet_mat: ShaderMaterial
static var _foam_mat: ShaderMaterial
static var _mist_process: ShaderMaterial
static var _mist_draw: ShaderMaterial
static var _roar: AudioStream

## Adds the chunk's falls to its node.
static func add_all(chunk_node: Node3D, chunk: Dictionary) -> void:
	for d in chunk["falls"]:
		var fx := WaterfallFx.new()
		fx.name = "Waterfall"
		chunk_node.add_child(fx)
		fx.build(d, chunk)

static func _shared() -> void:
	if _sheet_mat != null:
		return
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = load("res://src/env/waterfall.gdshader")
	_foam_mat = ShaderMaterial.new()
	_foam_mat.shader = load("res://src/env/waterfall_foam.gdshader")
	_mist_process = ShaderMaterial.new()
	_mist_process.shader = load("res://src/env/waterfall_mist.gdshader")
	_mist_draw = ShaderMaterial.new()
	_mist_draw.shader = load("res://src/env/waterfall_mist_draw.gdshader")
	_roar = load("res://assets/audio/ambience/waterfall.ogg") as AudioStream

## Where the water is, `u` of the way down (0 at the lip, 1 at the pool) a drop of h:
## (metres out from the lip, metres below it). It leaves the lip at SPEED and falls freely.
static func arc(u: float, h: float) -> Vector2:
	var y := u * h
	return Vector2(SPEED * sqrt(2.0 * y / G), y)

## The sheet: [vertices, normals, uv (metres across, metres fallen), uv2 (u, across 0..1),
## colours (r: which of the two layers)], as mesh arrays. `edge` runs across the lip.
static func sheet_arrays(edge: PackedVector3Array, dir: Vector2, h: float) -> Array:
	var out3 := Vector3(dir.x, 0.0, dir.y)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var tans := PackedFloat32Array()
	var idx := PackedInt32Array()
	var n := edge.size()
	var across := PackedFloat32Array()
	across.resize(n)
	for e in range(1, n):
		across[e] = across[e - 1] + edge[e].distance_to(edge[e - 1])
	var width := maxf(across[n - 1], 0.01)
	var mid := (edge[0] + edge[n - 1]) * 0.5
	for layer in 2:
		var base := verts.size()
		# Rows: two on the river just above the lip (the tongue), then down the fall, more
		# closely where it bends over, and on below the pool's surface.
		var rows := ROWS + 3
		for r in rows:
			var u := 0.0
			var back := 0.0
			if r == 0:
				back = 1.6
			elif r == 1:
				back = 0.5
			else:
				u = pow(float(r - 2) / (rows - 3), 1.6)
			var a := arc(u, h)
			# The outer layer is the spray coming off the sheet: it billows out as it falls.
			var off := a.x + (0.15 + u * 0.9 if layer == 1 else 0.0)
			var y := -a.y + (0.03 if r < 2 else 0.0)
			if r == rows - 1:
				y -= 0.6
			for e in n:
				var p := edge[e]
				# The sheet spreads a little as it falls.
				p += (p - mid) * Vector3(1, 0, 1) * (u * 0.08 + layer * u * 0.05)
				p += out3 * (off - back) + Vector3(0.0, y, 0.0)
				verts.append(p)
				# Facing out and a little up where it bends over the lip.
				var slope := -SPEED / maxf(sqrt(2.0 * G * maxf(a.y, 0.05)), 0.001)
				norms.append((out3 + Vector3.UP * (1.0 / maxf(-slope, 0.2)) * 0.3).normalized() if r >= 2 else Vector3.UP)
				uvs.append(Vector2(across[e], a.y - back))
				uv2s.append(Vector2(u if r >= 2 else -back / 1.6, across[e] / width))
				cols.append(Color(float(layer), h / 30.0, 0.0, 1.0))
				var t := (edge[mini(e + 1, n - 1)] - edge[maxi(e - 1, 0)]).normalized()
				tans.append_array([t.x, t.y, t.z, 1.0])
		for r in rows - 1:
			for e in n - 1:
				var a0 := base + r * n + e
				var b0 := a0 + n
				idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

## `chunk` (the one the drop belongs to) sets the boulders on its ground.
func build(d: Dictionary, chunk := {}) -> void:
	_shared()
	var edge: PackedVector3Array = d["edge"]
	var dir: Vector2 = d["dir"]
	var h: float = d["drop"]
	var pool: Vector3 = d["pool"]
	var rad: float = d["radius"]
	var out3 := Vector3(dir.x, 0.0, dir.y)
	var width := edge[0].distance_to(edge[edge.size() - 1])
	var mid := (edge[0] + edge[edge.size() - 1]) * 0.5
	var foot := arc(1.0, h).x
	# The falling sheet.
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sheet_arrays(edge, dir, h))
	m.surface_set_material(0, _sheet_mat)
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = m
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	# Churned white water where it lands, spreading out over the pool.
	var foam := MeshInstance3D.new()
	foam.name = "Foam"
	var q := PlaneMesh.new()
	var reach := rad * 1.8 + foot
	q.size = Vector2(width + rad * 1.2, reach)
	q.subdivide_width = 0
	q.subdivide_depth = 0
	foam.mesh = q
	foam.material_override = _foam_mat
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foam)
	var fwd := out3
	var side := Vector3(-dir.y, 0.0, dir.x)
	var c := Vector3(mid.x, pool.y + 0.05, mid.z) + fwd * (reach * 0.5 - 0.6)
	foam.transform = Transform3D(Basis(side, Vector3.UP, fwd), c)
	foam.set_instance_shader_parameter("size", q.size)
	foam.set_instance_shader_parameter("foot", foot + 0.6)
	foam.set_instance_shader_parameter("power", clampf(h / 18.0, 0.35, 1.0))
	# Mist and spray rising off the foot of the fall and drifting off on the wind.
	var mist := GPUParticles3D.new()
	mist.name = "Mist"
	mist.amount = clampi(int(h * 2.0 + width * 0.8), 16, 64)
	mist.lifetime = 4.5
	mist.preprocess = 4.5
	mist.fixed_fps = 30
	var pm := _mist_process.duplicate() as ShaderMaterial
	pm.set_shader_parameter("spread", Vector3(width * 0.5, h, rad))
	mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mist_draw
	mist.draw_pass_1 = quad
	mist.local_coords = false
	mist.transform = Transform3D(Basis(side, Vector3.UP, fwd), Vector3(mid.x, pool.y, mid.z) + fwd * foot)
	mist.visibility_aabb = AABB(Vector3(-width - 30.0, -2.0, -30.0), Vector3(width * 2.0 + 60.0, h + 30.0, 60.0))
	mist.visibility_range_end = MIST_RANGE
	mist.visibility_range_end_margin = 60.0
	mist.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)
	# The roar: louder and carrying further the higher the fall.
	if _roar != null:
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Roar"
		snd.stream = _roar
		snd.bus = "Ambience"
		snd.unit_size = 5.0 + h * 0.5 + width * 0.15
		snd.max_distance = 140.0 + h * 5.0
		snd.volume_db = -4.0 + clampf(h * 0.25, 0.0, 5.0)
		snd.attenuation_filter_cutoff_hz = 3000.0
		snd.position = Vector3(mid.x, pool.y + h * 0.3, mid.z) + fwd * foot
		snd.autoplay = true
		add_child(snd)
	if not chunk.is_empty():
		_boulders(d, chunk)

## Boulders the falls have torn from the cliff: tumbled round the pool against the foot of
## the cliff and at either end of the lip, half in the water (the river foams round them).
## You can climb on them. Laid the same every time from the drop's own place.
func _boulders(d: Dictionary, chunk: Dictionary) -> void:
	var edge: PackedVector3Array = d["edge"]
	var dir: Vector2 = d["dir"]
	var h: float = d["drop"]
	var pool: Vector3 = d["pool"]
	var rad: float = d["radius"]
	var side := Vector2(-dir.y, dir.x)
	var r := WHash.rng(int(chunk.get("seed", 0)), int(round(pool.x * 4.0)) + int(chunk["cx"]) * 997, int(round(pool.z * 4.0)) + int(chunk["cz"]) * 991, 1520)
	var spots: Array = []
	# Round the back of the pool, either side of the sheet.
	for k in 4 + int(h / 6.0):
		var a := r.randf_range(0.45, 1.25) * PI * (1.0 if r.randf() < 0.5 else -1.0)
		var q := Vector2(pool.x, pool.z) - dir * cos(a) * rad * r.randf_range(0.8, 1.05) + side * sin(a) * rad * r.randf_range(0.8, 1.05)
		spots.append([q, r.randf_range(1.0, 2.2) + h * 0.03])
	# At the ends of the lip, where the water parts round the rock.
	for e in [edge[0], edge[edge.size() - 1]]:
		var out := (Vector2(e.x, e.z) - Vector2(pool.x, pool.z)).dot(side)
		var q := Vector2(e.x, e.z) + side * signf(out) * r.randf_range(0.2, 1.2) - dir * r.randf_range(0.0, 1.0)
		spots.append([q, r.randf_range(1.0, 1.8)])
	var bufs := {}
	var body := StaticBody3D.new()
	body.name = "Boulders"
	for sp in spots:
		var q: Vector2 = sp[0]
		var size: float = sp[1]
		var lx := clampf(q.x, 0.0, ChunkGenerator.SIZE)
		var lz := clampf(q.y, 0.0, ChunkGenerator.SIZE)
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		var kind := "rock_a" if r.randf() < 0.5 else "rock_b"
		var b := Basis(Vector3.UP, r.randf() * TAU).rotated(Vector3.RIGHT, r.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3(size, size * r.randf_range(0.55, 0.85), size * r.randf_range(0.8, 1.1)))
		var t := Transform3D(b, Vector3(q.x, y - size * 0.2, q.y))
		if not bufs.has(kind):
			bufs[kind] = []
		bufs[kind].append(t)
		var cs := CollisionShape3D.new()
		cs.shape = StoneKit.shape(kind)
		cs.transform = t
		body.add_child(cs)
	add_child(body)
	for kind in bufs:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = StoneKit.mesh(kind)
		mm.instance_count = bufs[kind].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, bufs[kind][i])
			# Darker than dry stone: wet with spray.
			mm.set_instance_color(i, Color(0.36, 0.35, 0.33))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Rocks_" + kind
		mmi.multimesh = mm
		add_child(mmi)
