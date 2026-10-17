class_name FarLand
extends MeshInstance3D
## The land beyond the streamed chunks, out to the horizon: hills, coasts and mountains
## on a coarse grid with the terrain's own look (far_land.gdshader), so from a hilltop
## the world runs on into the haze instead of stopping at a square edge. Built on a
## worker thread around you and rebuilt when you have gone far enough; wherever a real
## chunk is drawn the distant land leaves itself out (a mask, one texel per chunk).

## Grid spacing and reach (metres). The span is a whole number of chunks.
const CELL := 32.0
const SPAN := 8192.0
## Rebuilt around you once you are this far from where it was last built.
const REBUILD := 1024.0

var streamer: ChunkStreamer
var target: Node3D
var _mat: ShaderMaterial
var _center := Vector2(INF, INF)
var _task := -1
var _arrays: Array = []
var _built_at := Vector2.ZERO
var _next_at := Vector2.ZERO
var _mask_img: Image
var _mask_tex: ImageTexture
var _mask_sum := -1
var _sync_t := 0.0

func _ready() -> void:
	ChunkNode.ensure_shared()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/world/far_land.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its vertices are in world space and it reaches kilometres round: never cull it.
	extra_cull_margin = 16384.0
	var m := int(SPAN / ChunkGenerator.SIZE)
	_mask_img = Image.create(m, m, false, Image.FORMAT_R8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	_mat.set_shader_parameter("near_mask", _mask_tex)
	_sync_material()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _process(delta: float) -> void:
	if target == null or streamer == null:
		return
	var p := Vector2(target.global_position.x, target.global_position.z)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_show()
	if _task < 0 and p.distance_to(_center) > REBUILD:
		_center = p.snapped(Vector2.ONE * ChunkGenerator.SIZE)
		var origin := _center - Vector2.ONE * SPAN * 0.5
		var job := _job_inputs(origin)
		_task = WorkerThreadPool.add_task(_build.bind(job))
	_update_mask()
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync_material()

## The streamed terrain's settings (textures, snow line, paved roads) on the far look too.
func _sync_material() -> void:
	var src := ChunkNode.terrain_material
	if src == null:
		return
	for u in src.shader.get_shader_uniform_list():
		var n: String = u["name"]
		var v = src.get_shader_parameter(n)
		if v != null:
			_mat.set_shader_parameter(n, v)

## Which chunks are drawn near you, as the mask the shader leaves out.
func _update_mask() -> void:
	var sum := 0
	for k in streamer.chunks:
		sum = (sum + (k.x * 73856093) ^ (k.y * 19349663)) & 0x3FFFFFFF
	sum = (sum + streamer.chunks.size()) & 0x3FFFFFFF
	if sum == _mask_sum:
		return
	_mask_sum = sum
	_mask_img.fill(Color(0, 0, 0))
	var m := _mask_img.get_width()
	var c0 := Vector2i(int(floor(_built_at.x / ChunkGenerator.SIZE)), int(floor(_built_at.y / ChunkGenerator.SIZE)))
	for k in streamer.chunks:
		var i: int = k.x - c0.x
		var j: int = k.y - c0.y
		if i >= 0 and j >= 0 and i < m and j < m:
			_mask_img.set_pixel(i, j, Color(1, 0, 0))
	_mask_tex.update(_mask_img)

## What the worker needs, read on the main thread (the world's seed and its settings).
func _job_inputs(origin: Vector2) -> Dictionary:
	return {"origin": origin, "seed": Game.seed, "terrain_v": WorldField.terrain_v,
		"human": Eras.theme == "human", "snow_line": Planets.snow_line}

## On the worker: the main thread reads these once the task is done.
func _build(job: Dictionary) -> void:
	_arrays = build_arrays(job)
	_next_at = job["origin"]

func _show() -> void:
	if _arrays.is_empty():
		return
	_built_at = _next_at
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays, [], {}, ChunkNode.LOOK_FORMAT | ChunkNode.COVER_FORMAT)
	mesh = am
	_arrays = []
	var m := _mask_img.get_width()
	_mat.set_shader_parameter("near_rect", Vector4(_built_at.x, _built_at.y, 1.0 / (m * ChunkGenerator.SIZE), 1.0 / (m * ChunkGenerator.SIZE)))
	_mask_sum = -1

## The distant land's mesh arrays: heights, normals, era weights and landform looks like
## a chunk's terrain (ChunkNode.build_terrain_arrays), and snow on the high ground.
static func build_arrays(job: Dictionary) -> Array:
	var origin: Vector2 = job["origin"]
	var field := WorldField.new(int(job["seed"]))
	var human: bool = job["human"]
	var snow_line: float = job["snow_line"]
	var n := int(SPAN / CELL) + 1
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	var cols := PackedColorArray()
	cols.resize(n * n)
	var l0 := PackedByteArray()
	l0.resize(n * n * 4)
	var l1 := PackedByteArray()
	l1.resize(n * n * 4)
	var l2 := PackedByteArray()
	l2.resize(n * n * 4)
	var cv := PackedByteArray()
	cv.resize(n * n * 4)
	var look := PackedByteArray()
	look.resize(12)
	for j in n:
		for i in n:
			var x := origin.x + i * CELL
			var z := origin.y + j * CELL
			var v := j * n + i
			var w := field.era_weights(x, z)
			var lw := field.landform_weights(x, z)
			var h := field.height(x, z, w, lw)
			hs[v] = h
			verts[v] = Vector3(x, h, z)
			# As a chunk paints them: human worlds dress their sci-fi land as the wilds.
			cols[v] = Color(w[Eras.MEDIEVAL] + (w[Eras.SCIFI] if human else 0.0), w[Eras.FANTASY], 0.0 if human else w[Eras.SCIFI], 1.0)
			if int(job["terrain_v"]) >= 7:
				WorldField.look_bytes(lw, look, 0)
				for b in 4:
					l0[v * 4 + b] = look[b]
					l1[v * 4 + b] = look[4 + b]
					l2[v * 4 + b] = look[8 + b]
	for j in n:
		for i in n:
			var v := j * n + i
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			var dx := (hr - hl) / (CELL * float(mini(i + 1, n - 1) - maxi(i - 1, 0)))
			var dz := (hu - hd) / (CELL * float(mini(j + 1, n - 1) - maxi(j - 1, 0)))
			norms[v] = Vector3(-dx, 1.0, -dz).normalized()
			# Snow lies on high ground and slides off steep faces (GroundCover, coarsely).
			var steep := smoothstep(0.7, 1.25, Vector2(dx, dz).length())
			var snow := smoothstep(snow_line - 6.0, snow_line + 8.0, hs[v]) * (1.0 - smoothstep(0.55, 0.9, steep * 0.9))
			cv[v * 4 + 3] = int(clampf(snow, 0.0, 1.0) * 255.0)
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var q := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Clockwise from above, along the flatter diagonal (as the chunks).
			if absf(hs[a] - hs[d]) <= absf(hs[b] - hs[c]):
				idx[q] = a; idx[q + 1] = b; idx[q + 2] = d; idx[q + 3] = a; idx[q + 4] = d; idx[q + 5] = c
			else:
				idx[q] = a; idx[q + 1] = b; idx[q + 2] = c; idx[q + 3] = b; idx[q + 4] = d; idx[q + 5] = c
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_CUSTOM0] = l0
	arr[Mesh.ARRAY_CUSTOM1] = l1
	arr[Mesh.ARRAY_CUSTOM2] = l2
	arr[Mesh.ARRAY_CUSTOM3] = cv
	return arr
