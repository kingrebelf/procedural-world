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
## Grid rows built per worker task, so the chunks streaming in round you never wait long.
const STRIP := 16

var streamer: ChunkStreamer
var target: Node3D
var _mat: ShaderMaterial
var _center := Vector2(INF, INF)
var _task := -1
## The build in progress: 0 none, 1 strips of rows, 2 putting the mesh together.
var _phase := 0
var _job: Dictionary = {}
var _rows: Array = []
var _row := 0
var _strip: Dictionary = {}
var _held := 0.0
var _arrays: Array = []
var _built_at := Vector2.ZERO
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
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _phase == 1:
			_rows.append(_strip)
			_strip = {}
			_row += STRIP
		elif _phase == 2:
			_show()
			_phase = 0
	if _task < 0:
		_step(delta)
	_update_mask()
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync_material()

## Starts a build once you have gone far enough (and the ground under you is in), then
## feeds it to the workers a strip at a time, between the chunk jobs.
func _step(delta: float) -> void:
	if _phase == 0:
		var p := Vector2(target.global_position.x, target.global_position.z)
		if p.distance_to(_center) <= REBUILD or not streamer.is_ready_at(target.global_position):
			return
		_center = p.snapped(Vector2.ONE * ChunkGenerator.SIZE)
		_job = _job_inputs(_center - Vector2.ONE * SPAN * 0.5)
		_rows = []
		_row = 0
		_held = 0.0
		_phase = 1
	if _phase == 1 and _row < grid_n():
		if streamer.busy() >= 2 and _held < 2.0:
			_held += delta
			return
		_held = 0.0
		_task = WorkerThreadPool.add_task(_build_strip.bind(_row), false, "distant land")
	elif _phase == 1:
		_phase = 2
		_task = WorkerThreadPool.add_task(_finish, false, "distant land")

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

## What the workers need, read on the main thread (the world's seed and its settings).
func _job_inputs(origin: Vector2) -> Dictionary:
	return {"origin": origin, "seed": Game.seed, "terrain_v": WorldField.terrain_v,
		"human": Eras.theme == "human", "snow_line": Planets.snow_line,
		"field": WorldField.new(Game.seed)}

## On a worker, one at a time: the main thread reads the results once each task is done.
func _build_strip(j0: int) -> void:
	_strip = build_rows(_job, j0, mini(j0 + STRIP, grid_n()))

func _finish() -> void:
	_arrays = finish_arrays(_job, _rows)

func _show() -> void:
	if _arrays.is_empty():
		return
	_built_at = _job["origin"]
	_job = {}
	_rows = []
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays, [], {}, ChunkNode.LOOK_FORMAT | ChunkNode.COVER_FORMAT)
	mesh = am
	_arrays = []
	var m := _mask_img.get_width()
	_mat.set_shader_parameter("near_rect", Vector4(_built_at.x, _built_at.y, 1.0 / (m * ChunkGenerator.SIZE), 1.0 / (m * ChunkGenerator.SIZE)))
	_mask_sum = -1

static func grid_n() -> int:
	return int(SPAN / CELL) + 1

## The distant land's mesh arrays: heights, normals, era weights and landform looks like
## a chunk's terrain (ChunkNode.build_terrain_arrays), and snow on the high ground.
static func build_arrays(job: Dictionary) -> Array:
	return finish_arrays(job, [build_rows(job, 0, grid_n())])

## Rows j0..j1-1 of the grid: heights, era weights and landform looks.
static func build_rows(job: Dictionary, j0: int, j1: int) -> Dictionary:
	var origin: Vector2 = job["origin"]
	var field: WorldField = job["field"] if job.has("field") else WorldField.new(int(job["seed"]))
	var human: bool = job["human"]
	var n := grid_n()
	var c := (j1 - j0) * n
	var hs := PackedFloat32Array()
	hs.resize(c)
	var cols := PackedColorArray()
	cols.resize(c)
	var l0 := PackedByteArray()
	l0.resize(c * 4)
	var l1 := PackedByteArray()
	l1.resize(c * 4)
	var l2 := PackedByteArray()
	l2.resize(c * 4)
	var cc := PackedByteArray()
	cc.resize(c * 4)
	var look := PackedByteArray()
	look.resize(12)
	var tv := int(job["terrain_v"])
	var regions := {}
	for j in range(j0, j1):
		for i in n:
			var x := origin.x + i * CELL
			var z := origin.y + j * CELL
			var v := (j - j0) * n + i
			var w := field.era_weights(x, z)
			var lw := field.landform_weights(x, z)
			hs[v] = field.height(x, z, w, lw)
			# As a chunk paints them: human worlds dress their sci-fi land as the wilds.
			cols[v] = Color(w[Eras.MEDIEVAL] + (w[Eras.SCIFI] if human else 0.0), w[Eras.FANTASY], 0.0 if human else w[Eras.SCIFI], 1.0)
			if tv >= 7:
				WorldField.look_bytes(lw, look, 0)
				for b in 4:
					l0[v * 4 + b] = look[b]
					l1[v * 4 + b] = look[4 + b]
					l2[v * 4 + b] = look[8 + b]
			# The forest as the chunks grow it (ChunkGenerator's trees), as a canopy: how
			# many trees stand here and the colour of their crowns.
			var forest := clampf((field._moss.get_noise_2d(x * 0.15, z * 0.15) + 0.35) * 1.5, 0.0, 1.0)
			var lt := 1.0
			if tv >= 7:
				lt = 0.0
				for f in WorldField.LF_COUNT:
					lt += lw[f] * WorldField.LANDFORM_TREES[f]
			var rh := field.region_hash_at(x, z)
			var trees := 0.0
			var tint := Color(0, 0, 0)
			for e in 3:
				if w[e] < 0.05:
					continue
				var key := (rh & 0xFFFFFFF) * 4 + e
				if not regions.has(key):
					var bp := Biome.params(rh, e)
					regions[key] = [float(bp["tree_density"]), canopy_colour(bp)]
				var dens: float = regions[key][0]
				var t := minf(Eras.TREE_DENSITY[e] * (0.25 + forest * 1.6) * dens * lt, 64.0)
				if tv >= 4:
					t += 40.0 * smoothstep(1.3, 2.2, dens) * (1.0 if e != Eras.SCIFI else 0.3) * minf(1.0, lt)
				trees += t * w[e]
				tint += (regions[key][1] as Color) * t * w[e]
			if trees > 0.01:
				tint /= trees
			l2[v * 4 + 2] = int(clampf(1.0 - exp(-trees * 0.011), 0.0, 1.0) * 255.0)
			cc[v * 4] = int(clampf(tint.r, 0.0, 1.0) * 255.0)
			cc[v * 4 + 1] = int(clampf(tint.g, 0.0, 1.0) * 255.0)
			cc[v * 4 + 2] = int(clampf(tint.b, 0.0, 1.0) * 255.0)
	return {"hs": hs, "cols": cols, "l0": l0, "l1": l1, "l2": l2, "cc": cc}

## The colour a region's trees give the canopy seen from afar (sRGB), each species by
## how common it is there.
static func canopy_colour(bp: Dictionary) -> Color:
	var sum := Color(0, 0, 0)
	var wt := 0.0
	for f in bp["flora"]:
		var p := Flora.species(f["t"], f["sp"])
		var c := Color(0.3, 0.32, 0.25)
		if p.has("leaf"):
			var leaf: Color = p["leaf"]
			if f["t"] == "pine":
				c = Color.from_hsv(leaf.h, clampf(leaf.s * 0.85, 0.3, 0.65), clampf(leaf.v * 1.9, 0.38, 0.62) * 0.7)
			elif leaf.h < 0.13 or leaf.h > 0.92:
				c = Color(0.62, 0.3, 0.12)
			else:
				c = Color.from_hsv(leaf.h, clampf(leaf.s * 0.75, 0.25, 0.7), clampf(leaf.v, 0.35, 0.6))
			if p.get("form", "") in ["dead", "snag"]:
				c = Color(0.35, 0.3, 0.26)
		elif p.has("cap_col"):
			c = p["cap_col"]
		elif p.has("paint"):
			c = p["paint"]
		elif p.has("bark"):
			c = p["bark"]
		sum += c * float(f["w"])
		wt += float(f["w"])
	return sum / wt if wt > 0.0 else Color(0.3, 0.35, 0.2)

## The whole grid from its strips of rows (in order): normals, snow and triangles.
static func finish_arrays(job: Dictionary, rows: Array) -> Array:
	var origin: Vector2 = job["origin"]
	var snow_line: float = job["snow_line"]
	var n := grid_n()
	var hs := PackedFloat32Array()
	var cols := PackedColorArray()
	var l0 := PackedByteArray()
	var l1 := PackedByteArray()
	var l2 := PackedByteArray()
	var cc := PackedByteArray()
	for r in rows:
		hs.append_array(r["hs"])
		cols.append_array(r["cols"])
		l0.append_array(r["l0"])
		l1.append_array(r["l1"])
		l2.append_array(r["l2"])
		cc.append_array(r["cc"])
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	var cv := PackedByteArray()
	cv.resize(n * n * 4)
	for j in n:
		for i in n:
			var v := j * n + i
			verts[v] = Vector3(origin.x + i * CELL, hs[v], origin.y + j * CELL)
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
			# The canopy (CUSTOM3.rgb its colour, CUSTOM2.z how dense): no trees in the
			# water or on cliffs.
			for b in 3:
				cv[v * 4 + b] = cc[v * 4 + b]
			var dry := smoothstep(ChunkGenerator.WATER_LEVEL + 0.2, ChunkGenerator.WATER_LEVEL + 1.5, hs[v])
			l2[v * 4 + 2] = int(float(l2[v * 4 + 2]) * dry * (1.0 - smoothstep(0.6, 0.9, Vector2(dx, dz).length())))
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
