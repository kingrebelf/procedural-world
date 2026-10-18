class_name FarLand
extends MeshInstance3D
## The land beyond the streamed chunks, out to the horizon: hills, coasts and mountains
## on a coarse grid with the terrain's own look (far_land.gdshader), so from a hilltop
## the world runs on into the haze instead of stopping at a square edge. Built on a
## worker thread around you and rebuilt when you have gone far enough; wherever a real
## chunk is drawn the distant land leaves itself out (a mask, one texel per chunk).

## Reach (metres, a whole number of chunks) and grid spacing: FINE apart out to
## FINE_REACH from where it was built, then wider and wider towards the horizon, where
## a cell covers only a few pixels.
const SPAN := 8192.0
const FINE := 16.0
const FINE_REACH := 1440.0
const COARSE := 48.0
## Rebuilt around you once you are this far from where it was last built (so the distant
## trees, out to 900 m from you, stay inside the fine grid and its forest data).
const REBUILD := 512.0
## Grid rows built per worker task, so the chunks streaming in round you never wait long.
const STRIP := 16
## Strips built at once, each on its own worker with its own generator (their caches
## aren't shared between threads).
const LANES := 3

var streamer: ChunkStreamer
var target: Node3D
var _mat: ShaderMaterial
var _center := Vector2(INF, INF)
var _task := -1 ## the finishing task
var _lanes: Array = [] ## per lane: [task id or -1, first row of its strip]
var _lane_out: Array = [] ## per lane: the rows it built (under _out_lock)
var _out_lock := Mutex.new()
var _done: Dictionary = {} ## first row of a strip -> its rows, built but not yet in order
## The build in progress: 0 none, 1 strips of rows, 2 putting the mesh together.
var _phase := 0
var _job: Dictionary = {}
var _rows: Array = []
var _row := 0 ## the next strip to hand out
var _arrays: Array = []
var _forest: Array = []
var _built_at := Vector2.ZERO
var _mask_img: Image
var _mask_tex: ImageTexture
var _mask_sum := -1
var _sync_t := 0.0
var _trees: FarTrees

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
	_trees = FarTrees.new()
	add_child(_trees)
	_trees.mat.set_shader_parameter("near_mask", _mask_tex)
	_sync_material()

func _exit_tree() -> void:
	for l in _lanes:
		if l[0] >= 0:
			WorkerThreadPool.wait_for_task_completion(l[0])
			l[0] = -1
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _process(delta: float) -> void:
	if target == null or streamer == null:
		return
	for i in _lanes.size():
		var l: Array = _lanes[i]
		if l[0] >= 0 and WorkerThreadPool.is_task_completed(l[0]):
			WorkerThreadPool.wait_for_task_completion(l[0])
			l[0] = -1
			_out_lock.lock()
			_done[l[1]] = _lane_out[i]
			_out_lock.unlock()
	# Strips go into the grid in order, whichever lane finishes first.
	while _done.has(_rows.size() * STRIP):
		var j0 := _rows.size() * STRIP
		_rows.append(_done[j0])
		_done.erase(j0)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_show()
		_phase = 0
	if _task < 0:
		_step()
	_update_mask()
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync_material()

## Starts a build once you have gone far enough (and the ground under you is in), then
## feeds it to the workers a strip at a time, LANES at once. The strips go in as
## high-priority tasks:
## the chunk jobs run as low-priority ones, on threads of their own, so the distant land
## never holds up the ground streaming in round you.
func _step() -> void:
	if _phase == 0:
		var p := Vector2(target.global_position.x, target.global_position.z)
		if p.distance_to(_center) <= REBUILD or not streamer.is_ready_at(target.global_position):
			return
		_center = p.snapped(Vector2.ONE * ChunkGenerator.SIZE)
		_job = _job_inputs(_center)
		_rows = []
		_row = 0
		_done.clear()
		_phase = 1
		if _lanes.is_empty():
			for i in LANES:
				_lanes.append([-1, 0])
				_lane_out.append({})
	if _phase != 1:
		return
	var n := int(_job["n"])
	for i in LANES:
		if _row >= n:
			break
		if _lanes[i][0] < 0:
			_lanes[i] = [WorkerThreadPool.add_task(_build_strip.bind(_row, i), true, "distant land"), _row]
			_row += STRIP
	if _rows.size() * STRIP >= n:
		_phase = 2
		_task = WorkerThreadPool.add_task(_finish, true, "distant land")

## Whether the distant land is built round `at` and not rebuilding (the capture tool
## waits for it).
func settled_at(at: Vector3) -> bool:
	return _phase == 0 and Vector2(at.x, at.z).distance_to(_center) <= REBUILD

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

## What the workers need, read on the main thread: the world's seed and settings, from
## the streamer's own world when it has one (the title screen's fly-over).
func _job_inputs(center: Vector2) -> Dictionary:
	var st: WorldStore = streamer.store if streamer.store else Game.store
	var sd: int = streamer.seed if streamer.store else Game.seed
	return {"center": center, "seed": sd, "terrain_v": WorldField.terrain_v,
		"human": Eras.theme == "human", "snow_line": Planets.snow_line,
		"rivers": st.has_rivers() if st else true,
		"gens": range(LANES).map(func(_i): return ChunkGenerator.new(sd, st.has_rivers() if st else true)),
		"n": grid_n()}

## On a worker, in its lane (with the lane's own generator): the main thread takes the
## rows once the task is done.
func _build_strip(j0: int, lane: int) -> void:
	var rows := build_rows(_job, j0, mini(j0 + STRIP, int(_job["n"])), _job["gens"][lane])
	_out_lock.lock()
	_lane_out[lane] = rows
	_out_lock.unlock()

func _finish() -> void:
	_arrays = finish_arrays(_job, _rows)
	_forest = forest_data(_job, _arrays)

func _show() -> void:
	if _arrays.is_empty():
		return
	_built_at = (_job["center"] as Vector2) - Vector2.ONE * SPAN * 0.5
	_job = {}
	_rows = []
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays, [], {}, ChunkNode.LOOK_FORMAT | ChunkNode.COVER_FORMAT)
	mesh = am
	_arrays = []
	var m := _mask_img.get_width()
	var forest: Array = _forest
	_forest = []
	for mt in [_mat, _trees.mat]:
		mt.set_shader_parameter("near_rect", Vector4(_built_at.x, _built_at.y, 1.0 / (m * ChunkGenerator.SIZE), 1.0 / (m * ChunkGenerator.SIZE)))
		if not forest.is_empty():
			mt.set_shader_parameter("forest_tex", ImageTexture.create_from_image(forest[0]))
			mt.set_shader_parameter("forest_hgt", ImageTexture.create_from_image(forest[1]))
			mt.set_shader_parameter("forest_rect", forest[2])
	_mask_sum = -1

static func grid_n() -> int:
	return axis().size()

## The grid lines' offsets from the centre, along x and along z alike.
static func axis() -> PackedFloat32Array:
	var half := PackedFloat32Array([0.0])
	var x := 0.0
	var step := FINE
	while x < SPAN * 0.5:
		if x >= FINE_REACH:
			step = minf(step * 1.06, COARSE)
		x = minf(x + step, SPAN * 0.5)
		half.append(x)
	var out := PackedFloat32Array()
	for k in range(half.size() - 1, 0, -1):
		out.append(-half[k])
	out.append_array(half)
	return out

## The distant land's mesh arrays: heights, normals, era weights and landform looks like
## a chunk's terrain (ChunkNode.build_terrain_arrays), and snow on the high ground.
static func build_arrays(job: Dictionary) -> Array:
	return finish_arrays(job, [build_rows(job, 0, grid_n())])

## Rows j0..j1-1 of the grid: heights, era weights and landform looks.
static func build_rows(job: Dictionary, j0: int, j1: int, gen: ChunkGenerator = null) -> Dictionary:
	var center: Vector2 = job["center"]
	var ax := axis()
	if gen == null:
		if not job.has("gen"):
			job["gen"] = ChunkGenerator.new(int(job["seed"]), job.get("rivers", false))
		gen = job["gen"]
	var field: WorldField = gen.field
	var human: bool = job["human"]
	var n := ax.size()
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
	var sp := PackedByteArray()
	sp.resize(c * 4)
	var look := PackedByteArray()
	look.resize(12)
	var tv := int(job["terrain_v"])
	# The climate on the ground, as the chunks lay it (UV2, WorldField.ground_look).
	var cl := PackedVector2Array()
	if tv >= WorldField.CLIMATE_V:
		cl.resize(c)
	var rivers: bool = job.get("rivers", false)
	var regions := {}
	for j in range(j0, j1):
		for i in n:
			var x := center.x + ax[i]
			var z := center.y + ax[j]
			var v := (j - j0) * n + i
			var w := field.era_weights(x, z)
			var lw := field.landform_weights(x, z)
			var sh := field.shape(x, z, w, lw)
			# Rivers cut their vales as the chunks carve them (ChunkGenerator), and where
			# the water shows the shader lays it on (CUSTOM2.w, the distance from the
			# river's centre in half-widths, over six).
			var rt := field.river_t(x, z) if rivers else INF
			var h := sh.x + sh.y * smoothstep(WorldField.RIVER_REACH, WorldField.RIVER_REACH + 4.0, rt) + sh.z
			var wet := 1.0
			if rt < WorldField.RIVER_REACH:
				var lv := river_level(field, x, z)
				var m := WorldField.river_strength(h - sh.z, lv)
				if gen.falls_on:
					lv = Waterfalls.level(Waterfalls.near(gen, x, z, x, z), x, z, lv)
				h = WorldField.carve_river(h, rt, lv, m)
				if m > 0.25 and lv > ChunkGenerator.WATER_LEVEL + 0.2:
					wet = rt / WorldField.RIVER_REACH
			hs[v] = h
			var blend: Array = field.region_blend(x, z) if not cl.is_empty() else []
			if not cl.is_empty():
				cl[v] = field.ground_look_at(x, z, blend)
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
			var rh := field.region_hash_mixed(x, z, blend)
			var trees := 0.0
			var tint := Color(0, 0, 0)
			var era_t := [0.0, 0.0, 0.0]
			var era_key := [0, 0, 0]
			for e in 3:
				if w[e] < 0.05:
					continue
				var key := (rh & 0xFFFFFFF) * 4 + e
				if not regions.has(key):
					var bp := Biome.params(rh, e)
					regions[key] = [float(bp["tree_density"]), canopy_colour(bp), species_mix(bp)]
				var dens: float = regions[key][0]
				var t := minf(Eras.TREE_DENSITY[e] * (0.25 + forest * 1.6) * dens * lt, 64.0)
				if tv >= 4:
					t += 40.0 * smoothstep(1.3, 2.2, dens) * (1.0 if e != Eras.SCIFI else 0.3) * minf(1.0, lt)
				trees += t * w[e]
				tint += (regions[key][1] as Color) * t * w[e]
				era_t[e] = t * w[e]
				era_key[e] = key
			# Each grid point grows one species, picked by how common each is there (by a
			# hash of the point, so every rebuild picks the same): the distant trees round
			# it take its colour and form, so a mixed wood shows its mix.
			var pick := [Color(0.3, 0.35, 0.2), FORM_BROADLEAF]
			if trees > 0.01:
				tint /= trees
				var hv := hash(Vector2(x, z))
				var r1 := float(hv & 0xFFFF) / 65536.0 * trees
				var r2 := float((hv >> 16) & 0xFFFF) / 65536.0
				for e in 3:
					if era_t[e] <= 0.0:
						continue
					r1 -= era_t[e]
					pick = pick_species(regions[era_key[e]][2], r2)
					if r1 <= 0.0:
						break
			# No trees in the river or on its edge, nor in a settlement.
			trees *= smoothstep(1.2 / WorldField.RIVER_REACH, 2.5 / WorldField.RIVER_REACH, wet)
			if trees > 0.0:
				trees *= 1.0 - in_settlement(gen, x, z)
			l2[v * 4 + 2] = int(clampf(1.0 - exp(-trees * 0.011), 0.0, 1.0) * 255.0)
			l2[v * 4 + 3] = int(clampf(wet, 0.0, 1.0) * 255.0)
			cc[v * 4] = int(clampf(tint.r, 0.0, 1.0) * 255.0)
			cc[v * 4 + 1] = int(clampf(tint.g, 0.0, 1.0) * 255.0)
			cc[v * 4 + 2] = int(clampf(tint.b, 0.0, 1.0) * 255.0)
			var pc: Color = pick[0]
			sp[v * 4] = int(clampf(pc.r, 0.0, 1.0) * 255.0)
			sp[v * 4 + 1] = int(clampf(pc.g, 0.0, 1.0) * 255.0)
			sp[v * 4 + 2] = int(clampf(pc.b, 0.0, 1.0) * 255.0)
			sp[v * 4 + 3] = pick[1]
	return {"hs": hs, "cols": cols, "l0": l0, "l1": l1, "l2": l2, "cc": cc, "sp": sp, "cl": cl}

## How far (x, z) is inside a settlement (1 in its streets, 0 out in the wilds), where
## the chunks grow no trees.
static func in_settlement(gen: ChunkGenerator, x: float, z: float) -> float:
	var sx := int(floor(x / ChunkGenerator.SETTLEMENT_CELL))
	var sz := int(floor(z / ChunkGenerator.SETTLEMENT_CELL))
	var out := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var s := gen.settlement_at(sx + dx, sz + dz)
			if s.is_empty():
				continue
			var r := float(s["inner"]) + 6.0 + (8.0 if s.get("walled", false) else 0.0)
			out = maxf(out, 1.0 - smoothstep(r, r + 16.0, Vector2(x, z).distance_to(s["center"])))
	return out

## A river's water level near (x, z): just below the lowest ground round about, as
## WorldField.river_level finds it on its grid (more coarsely: this is seen from afar).
static func river_level(field: WorldField, x: float, z: float) -> float:
	var lo := field.shape(x, z).x
	for o in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
		lo = minf(lo, field.shape(x + o.x, z + o.y).x)
	return lo - 0.4

## A region's trees to pick one from at random: [cumulative share, crown colour (sRGB),
## form (FORM_*)] for each species, by how common it is there.
static func species_mix(bp: Dictionary) -> Array:
	var wt := 0.0
	for f in bp["flora"]:
		wt += float(f["w"])
	var out := []
	var acc := 0.0
	for f in bp["flora"]:
		acc += float(f["w"]) / maxf(wt, 0.0001)
		var form: int = FORMS.get(f["t"], FORM_BROADLEAF)
		if Flora.species(f["t"], f["sp"]).get("form", "") in ["dead", "snag"]:
			form = FORM_BARE
		out.append([acc, species_colour(f), form])
	return out

## The species of a mix (species_mix) at r (0..1): [crown colour, form].
static func pick_species(mix: Array, r: float) -> Array:
	for s in mix:
		if r <= float(s[0]):
			return [s[1], s[2]]
	return [mix[-1][1], mix[-1][2]] if not mix.is_empty() else [Color(0.3, 0.35, 0.2), FORM_BROADLEAF]

## The forest over the fine grid's square, for the distant trees and the ground under
## them (forest.gdshaderinc): the crown colour of the species growing at each grid point
## and how densely trees stand, and the ground's height and that species' form (FORM_*),
## one texel per point; and the square's rect for the shaders.
static func forest_data(job: Dictionary, arr: Array) -> Array:
	var ax := axis()
	var n := ax.size()
	var k0 := (n - 1) / 2 - int(FINE_REACH / FINE)
	var t := int(FINE_REACH / FINE) * 2 + 1
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var l2: PackedByteArray = arr[Mesh.ARRAY_CUSTOM2]
	var cv: PackedByteArray = arr[Mesh.ARRAY_CUSTOM3]
	var sp: PackedByteArray = job["species"]
	var a := PackedByteArray()
	a.resize(t * t * 4)
	var b := PackedFloat32Array()
	b.resize(t * t * 2)
	var half := t / 2
	for tj in t:
		for ti in t:
			var v := (k0 + tj) * n + k0 + ti
			var o := tj * t + ti
			# Towards the square's edge each point's species fades to the mean colour the
			# land beyond it paints.
			var f := smoothstep(half * 0.75, float(half), float(maxi(absi(ti - half), absi(tj - half))))
			for k in 3:
				a[o * 4 + k] = int(lerpf(sp[v * 4 + k], cv[v * 4 + k], f))
			a[o * 4 + 3] = l2[v * 4 + 2]
			b[o * 2] = verts[v].y
			b[o * 2 + 1] = sp[v * 4 + 3] / 255.0
	var origin: Vector2 = (job["center"] as Vector2) + Vector2.ONE * ax[k0]
	return [Image.create_from_data(t, t, false, Image.FORMAT_RGBA8, a),
		Image.create_from_data(t, t, false, Image.FORMAT_RGF, b.to_byte_array()),
		Vector4(origin.x, origin.y, 1.0 / FINE, 1.0 / t)]

## The colour a region's trees give the canopy seen from afar (sRGB), each species by
## how common it is there.
static func canopy_colour(bp: Dictionary) -> Color:
	var sum := Color(0, 0, 0)
	var wt := 0.0
	for f in bp["flora"]:
		sum += species_colour(f) * float(f["w"])
		wt += float(f["w"])
	return sum / wt if wt > 0.0 else Color(0.3, 0.35, 0.2)

## A distant tree's form, as forest_hgt.g holds it (form * 255 / 6; FORM_* in
## forest.gdshaderinc): a round crown, a mushroom cap, bare (dead) limbs, a crystal spike,
## a mast, a conifer's spire or a palm's star of fronds on its bare stem.
const FORM_BROADLEAF := 0
const FORM_CAP := 43
const FORM_BARE := 85
const FORM_CRYSTAL := 128
const FORM_MAST := 170
const FORM_CONIFER := 213
const FORM_PALM := 255
const FORMS := {"oak": FORM_BROADLEAF, "pine": FORM_CONIFER, "palm": FORM_PALM, "tropic": FORM_BROADLEAF,
	"glowcap": FORM_CAP, "crystal_tree": FORM_CRYSTAL, "solar_mast": FORM_MAST}

## The mean colour of RealTree's leaf photos (sRGB, over their opaque texels).
const LEAF_MEAN := {"oak": Color(0.353, 0.49, 0.224), "autumn": Color(0.812, 0.373, 0.184), "needle": Color(0.627, 0.722, 0.565)}

## The colour a species' crown shows from afar (sRGB): for the trees RealTree draws, its
## leaf photo under the species' tint, as a near tree's leaves are, so a distant tree
## matches it.
static func species_colour(f: Dictionary) -> Color:
	var p := Flora.species(f["t"], f["sp"])
	var c := Color(0.3, 0.32, 0.25)
	if p.has("leaf"):
		var leaf: Color = p["leaf"]
		if RealTree.handles(f["t"]):
			var look := ["needle", RealTree._needle_tint(p)] if f["t"] == "pine" else RealTree._leaf_look(p)
			var m: Color = LEAF_MEAN[look[0]]
			var tint: Color = look[1]
			c = Color(m.srgb_to_linear().r * tint.srgb_to_linear().r, m.srgb_to_linear().g * tint.srgb_to_linear().g,
				m.srgb_to_linear().b * tint.srgb_to_linear().b).linear_to_srgb()
		elif f["t"] == "pine":
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
	return c

## The whole grid from its strips of rows (in order): normals, snow and triangles.
static func finish_arrays(job: Dictionary, rows: Array) -> Array:
	var center: Vector2 = job["center"]
	var ax := axis()
	var snow_line: float = job["snow_line"]
	var n := ax.size()
	var hs := PackedFloat32Array()
	var cols := PackedColorArray()
	var l0 := PackedByteArray()
	var l1 := PackedByteArray()
	var l2 := PackedByteArray()
	var cc := PackedByteArray()
	var cl := PackedVector2Array()
	for r in rows:
		hs.append_array(r["hs"])
		cols.append_array(r["cols"])
		l0.append_array(r["l0"])
		l1.append_array(r["l1"])
		l2.append_array(r["l2"])
		cc.append_array(r["cc"])
		cl.append_array(r.get("cl", PackedVector2Array()))
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	var cv := PackedByteArray()
	cv.resize(n * n * 4)
	var sp := PackedByteArray()
	for r in rows:
		sp.append_array(r["sp"])
	for j in n:
		for i in n:
			var v := j * n + i
			verts[v] = Vector3(center.x + ax[i], hs[v], center.y + ax[j])
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			var dx := (hr - hl) / (ax[mini(i + 1, n - 1)] - ax[maxi(i - 1, 0)])
			var dz := (hu - hd) / (ax[mini(j + 1, n - 1)] - ax[maxi(j - 1, 0)])
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
	if cl.size() == n * n:
		arr[Mesh.ARRAY_TEX_UV2] = cl
	job["species"] = sp
	return arr
