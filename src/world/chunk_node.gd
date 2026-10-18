class_name ChunkNode
extends Node3D
## Scene representation of one chunk snapshot. Heavy array work happens on worker
## threads via the static build_* functions; this node only uploads the results.

const SIZE := ChunkGenerator.SIZE
const RES := ChunkGenerator.RES

static var terrain_material: ShaderMaterial
static var grass_material: ShaderMaterial
static var river_material: ShaderMaterial

var data: Dictionary
var key: Vector2i
var lod := 1
var near := false

var _terrain: MeshInstance3D
var _old_terrain: MeshInstance3D ## the mesh of the detail it is leaving, while it dissolves
var _swap_t := 1.0
var _body: StaticBody3D
var _height_shape: CollisionShape3D
var _mm: Dictionary = {} ## type -> MultiMeshInstance3D (or a node of rooms, _add_rooms)
var _obj_bodies: Dictionary = {} ## object index -> StaticBody3D
var _doors: Dictionary = {} ## object index -> DoorNode (doors move, so they aren't in a MultiMesh)
var _power: Dictionary = {} ## object index -> PowerNode (a powered piece's moving and lit parts)
var _grass: Array = [] ## MultiMeshInstance3D per grass species and quarter
var _clutter: Array = []
var _stones := PackedFloat32Array() ## stones to stand on (see _scatter_stones)
var _stone_body: StaticBody3D
var _crags: Array = []
var _crag_solid := PackedFloat32Array() ## crags' colliders (see build_crag_buffers)
## The chunk's GroundCover grid (for footsteps), from its last terrain build.
var cover := PackedByteArray()
var _cave: MeshInstance3D
var _cave_faces := PackedVector3Array()
var _cave_shape: CollisionShape3D

const TERRAIN_TEXTURES := ["grass", "dirt", "glowmoss", "darksoil", "regolith", "rock", "mud", "snow", "scree", "gravel", "litter", "cliff"]

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
		terrain_material.set_shader_parameter("paved_roads", Eras.theme == "human")
		terrain_material.set_shader_parameter("zone_rings", ZoneBorder.road_rings())
		grass_material = ShaderMaterial.new()
		grass_material.shader = load("res://src/world/grass.gdshader")
		grass_material.set_shader_parameter("detail", detail_mult)
		AquaKit.get_material().set_shader_parameter("detail", detail_mult)
		river_material = ShaderMaterial.new()
		river_material.shader = load("res://src/env/river.gdshader")

# --- Worker-thread builders ---------------------------------------------------

## Terrain arrays at a given LOD step (1, 2 or 4). Far LODs get skirts to hide cracks.
## `cover` is the chunk's GroundCover grid (worked out here when not given).
static func build_terrain_arrays(chunk: Dictionary, step: int, cover := PackedByteArray()) -> Array:
	if cover.is_empty():
		cover = GroundCover.build(chunk)
	var hs: PackedFloat32Array = chunk["heights"]
	var wb: PackedByteArray = chunk["weights"]
	var rb: PackedByteArray = chunk.get("road", PackedByteArray())
	var worn: PackedByteArray = chunk.get("worn", PackedByteArray())
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	var n := SIZE / step + 1
	# Packed arrays held in an Array are copied on access, so the three look streams
	# are separate locals (passed to helpers by reference).
	var has_look := not lb.is_empty()
	# Up close, how far each point near a road is from its middle (for the wheel ruts), as
	# the vertex UV: (metres to one side or the other, 1), (0, 0) away from roads.
	var mid: PackedByteArray = chunk.get("road_mid", PackedByteArray()) if step == 1 else PackedByteArray()
	var uvs := PackedVector2Array()
	if not mid.is_empty():
		uvs.resize(n * n)
	# The climate on the ground (v18), as the vertex UV2: (how dry, how lush or cold), from
	# the chunk's grid of regions and how far into the band between two each point is.
	var clim := _climate_grid(chunk)
	var uv2s := PackedVector2Array()
	if not clim.is_empty():
		uv2s.resize(n * n)
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
	var cv := PackedByteArray()
	cv.resize(n * n * 4)
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
			norms[v] = _normal_at(hs, gi, gj, step)
			var wk := k * Eras.COUNT
			# Alpha: 1 minus how much road surface shows (roads and village squares).
			# Human worlds dress their sci-fi land as the medieval wilds (Eras.look).
			# There blue is only how paved the road is (the tech era's streets and roads).
			var rd := rb[k] / 255.0 if not rb.is_empty() else 0.0
			var ws := wb[wk + 2] / 255.0 * (1.0 if rd > 0.0 else 0.0) if human else wb[wk + 2] / 255.0
			# Village paths, gardens and fields wear the ground bare too (never paved).
			if not worn.is_empty():
				rd = maxf(rd, worn[k] / 255.0)
			cols[v] = Color((wb[wk] + (wb[wk + 2] if human else 0)) / 255.0, wb[wk + 1] / 255.0, ws, 1.0 - rd)
			if has_look:
				_look_at(lb, gi, gj, l0, l1, l2, v * 4)
			if not mid.is_empty() and mid[k] > 0:
				uvs[v] = Vector2((mid[k] - 128) / 20.0, 1.0)
			for b in 4:
				cv[v * 4 + b] = cover[k * 4 + b]
			if not clim.is_empty():
				uv2s[v] = _climate_at(clim, gi, gj)
	# Up close, a cave mouth is an opening in the ground (far off the hole is too small to
	# see, and the cave walls are not drawn).
	var hole := PackedByteArray()
	if step == 1 and chunk.has("hole"):
		hole = chunk["hole"]
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			if not hole.is_empty() and (hole[a] != 0 or hole[b] != 0 or hole[c] != 0 or hole[d] != 0):
				continue
			# Clockwise from above (Godot front faces). Each square is split along the
			# diagonal whose corners are closer in height, so the edges follow terrace
			# risers, banks and ridges instead of zigzagging across them.
			if absf(verts[a].y - verts[d].y) <= absf(verts[b].y - verts[c].y):
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	if step > 1:
		_add_skirts(n, verts, norms, cols, idx, 3.0 * step, uv2s)
		if has_look:
			_skirt_looks(n, l0, l1, l2)
		_skirt_looks(n, cv, PackedByteArray(), PackedByteArray())
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	if not uvs.is_empty():
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if not uv2s.is_empty():
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	if not l0.is_empty():
		arr[Mesh.ARRAY_CUSTOM0] = l0
		arr[Mesh.ARRAY_CUSTOM1] = l1
		arr[Mesh.ARRAY_CUSTOM2] = l2
	arr[Mesh.ARRAY_CUSTOM3] = cv
	return arr

## The ground's normal at grid point (gi, gj), from its slope across the mesh's own cell
## size (`step` metres) and smoothed over the neighbouring rows (a Sobel filter). A bank
## or cliff running slantwise across the grid steps from cell to cell; differences over
## one metre in one row only made each step lean another way, which drew evenly spaced
## light and dark stripes down the face, like a palisade, from a few hundred metres off.
static func _normal_at(hs: PackedFloat32Array, gi: int, gj: int, step: int) -> Vector3:
	var x0 := maxi(gi - step, 0)
	var x1 := mini(gi + step, RES - 1)
	var z0 := maxi(gj - step, 0)
	var z1 := mini(gj + step, RES - 1)
	var r0 := z0 * RES
	var r1 := gj * RES
	var r2 := z1 * RES
	var gx := (hs[r0 + x1] + 2.0 * hs[r1 + x1] + hs[r2 + x1] - hs[r0 + x0] - 2.0 * hs[r1 + x0] - hs[r2 + x0]) / (4.0 * (x1 - x0))
	var gz := (hs[r2 + x0] + 2.0 * hs[r2 + gi] + hs[r2 + x1] - hs[r0 + x0] - 2.0 * hs[r0 + gi] - hs[r0 + x1]) / (4.0 * (z1 - z0))
	return Vector3(-gx, 1.0, -gz).normalized()

## Vertex format flags for terrain arrays that carry a landform look, and for the ground
## cover every terrain mesh carries.
const LOOK_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
const COVER_FORMAT := Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT

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

## A chunk's climate look (WorldField.ground_look) on its MIX_N grid, or empty in chunks
## made before climates.
static func _climate_grid(chunk: Dictionary) -> PackedVector2Array:
	var mix: PackedByteArray = chunk.get("biome_mix", PackedByteArray())
	var out := PackedVector2Array()
	if mix.is_empty():
		return out
	var hs: Array = chunk["biomes"]
	var looks: Array = []
	var any := false
	for h in hs:
		var g := WorldField.ground_look(h)
		looks.append(g)
		any = any or g != Vector2.ZERO
	if not any:
		return out
	var m := ChunkGenerator.MIX_N
	out.resize(m * m)
	for k in m * m:
		out[k] = (looks[mix[k * 3]] as Vector2).lerp(looks[mix[k * 3 + 1]], mix[k * 3 + 2] / 510.0)
	return out

## The climate look at metre (gi, gj) of a chunk, between the grid's points.
static func _climate_at(grid: PackedVector2Array, gi: int, gj: int) -> Vector2:
	var m := ChunkGenerator.MIX_N
	var step := SIZE / float(m - 1)
	var fx := clampf(gi / step, 0.0, m - 1.001)
	var fz := clampf(gj / step, 0.0, m - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	fx -= ix
	fz -= iz
	var a := grid[iz * m + ix].lerp(grid[iz * m + ix + 1], fx)
	var b := grid[(iz + 1) * m + ix].lerp(grid[(iz + 1) * m + ix + 1], fx)
	return a.lerp(b, fz)

static func _add_skirts(n: int, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, depth: float, uv2s := PackedVector2Array()) -> void:
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
			if not uv2s.is_empty():
				uv2s.append(uv2s[v])
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
## Trees drawn by RealTree have all become the merged far mesh by this distance.
const TREE_NEAR := 320.0
## Where near trees dissolve into the far mesh (metres from the eye, ending at TREE_NEAR),
## and how far from a multimesh's middle its trees can stand, which their draw ranges
## add (a chunk's corner is 45 m from its middle).
const TREE_FADE := Vector2(TREE_NEAR - 40.0, TREE_NEAR)
const FADE_REACH := 50.0
## Trees and buildings are drawn as far as their chunk is in (more rings come in when you
## are high up, ChunkStreamer.reach).
const FAR_RANGE := 1400.0
## Suffix of the multimesh group for scorched objects (drawn with soot_material()).
const SOOT := "~soot"

static var _soot: ShaderMaterial

## The overlay that blackens scorched objects (soot.gdshader).
static func soot_material() -> ShaderMaterial:
	if _soot == null:
		_soot = ShaderMaterial.new()
		_soot.shader = load("res://src/world/soot.gdshader")
	return _soot

## Instance buffers per mesh key, plus "~far": the far versions of every RealTree tree in
## the chunk merged into one mesh's surface arrays (one surface per material), so a
## distant forest costs a couple of draw calls per chunk. `far` false skips that merge
## (a tree felled up close: the far mesh is out of sight and is rebuilt later).
static func build_object_buffers(chunk: Dictionary, far := true) -> Dictionary:
	var by_key := {}
	var far_bufs := {} # surface key -> [verts, normals, uvs, colours, indices]
	var seed: int = int(chunk.get("seed", 0)) ^ (int(chunk["cx"]) * 73856093) ^ (int(chunk["cz"]) * 19349663)
	for o in chunk["objects"]:
		if o["st"].get("gone", false) or Doors.is_door(o["t"]):
			continue
		var key := ObjectLibrary.mesh_key(o)
		var real := RealTree.handles(o["t"]) and int(o.get("sp", 0)) != 0
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
		if real:
			# No two trees alike: a crown a little broader one way than the other, and a
			# lean (most trees stand nearly straight, a few lean well over; spires less).
			var u3 := WHash.to_unit(WHash.h32(h ^ 0x5bd1e995))
			var u4 := WHash.to_unit(WHash.h32(h ^ 0x27d4eb2f))
			b = Basis(Vector3.UP, o["r"]).scaled(Vector3(s * lerpf(0.9, 1.12, u3), sy, s * lerpf(0.9, 1.12, u4)))
			var tilt := u3 * u3 * u3 * deg_to_rad(3.0 if o["t"] == "pine" else 7.0)
			b = Basis(Vector3(cos(u4 * TAU), 0.0, sin(u4 * TAU)), tilt) * b
		var p: Vector3 = o["p"]
		# Sink slightly so bases never float on slopes.
		if not built and not EasterEggs.floats(o["t"]):
			p.y -= 0.15 * s
		# Chests, wagons, stalls and barrels lie with the ground under them (PropSettle).
		var settled = PropSettle.transform(chunk, o)
		if settled != null:
			b = (settled as Transform3D).basis
			p = (settled as Transform3D).origin
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
			# Moss on its top (StoneKit's material reads alpha): in green lands, not on sand.
			var w := Eras.look(ChunkGenerator.weights_at(chunk, p.x, p.z))
			tint.a = w[Eras.MEDIEVAL] * lerpf(0.2, 0.9, u2) * ChunkGenerator.cover_at(chunk, p.x, p.z)
		if built:
			# How far it has weathered since it was built (the kit shader reads alpha).
			tint.a = ClimateWear.maturity(float(o["st"].get("day", -1.0)), Game.day)
		# Scorched by fire (FireSim): a tree's own tint darkens (leaves and bark alike);
		# anything else goes in its own group drawn with the soot overlay, how burnt in
		# the row's alpha. Stepped, so a fire rebuilds the chunk's meshes only a few times.
		var rk := key.get_slice(Stronghold.VAR, 0) # a castle tower's build shares its rooms
		var burnt := FireSim.char_step(o["st"])
		if burnt > 0.0 and o["t"] != FireSim.RUIN:
			if k == "tree":
				tint = Color(tint.r * (1.0 - burnt * 0.82), tint.g * (1.0 - burnt * 0.86), tint.b * (1.0 - burnt * 0.86), tint.a)
			else:
				key += SOOT
				if not by_key.has(key):
					by_key[key] = PackedFloat32Array()
				tint.a = 1.0 - burnt
		var row := [b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a]
		if far and real:
			var look := RealTree.plant_look(float(chunk["cx"]) * SIZE + p.x, float(chunk["cz"]) * SIZE + p.z)
			_add_far(far_bufs, RealTree.far_parts(o["t"], int(o["sp"]), int(o.get("v", 0))), Transform3D(b, p), tint, look)
		var buf: PackedFloat32Array = by_key[key]
		buf.append_array(row)
		by_key[key] = buf
		# A room you can walk into brings its furniture (drawn up close) and any lamplit
		# windows (from further off) as their own meshes.
		if KitHouse.has(rk) or Interiors.has(rk):
			for extra in [rk + "~in", rk + "~glow"] if KitHouse.has(rk) or Interiors.glows(rk) else [rk + "~in"]:
				var eb: PackedFloat32Array = by_key.get(extra, PackedFloat32Array())
				eb.append_array(row)
				by_key[extra] = eb
	if not far_bufs.is_empty():
		var surfs := {}
		for sk in far_bufs:
			var fb: Array = far_bufs[sk]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = fb[0]
			arr[Mesh.ARRAY_NORMAL] = fb[1]
			arr[Mesh.ARRAY_TEX_UV] = fb[2]
			arr[Mesh.ARRAY_COLOR] = fb[3]
			arr[Mesh.ARRAY_INDEX] = fb[4]
			surfs[sk] = arr
		by_key["~far"] = surfs
	return by_key

## Appends one tree's far parts, moved by `xf` and tinted, to the chunk's far buffers,
## with its own look (RealTree.plant_look) baked into the leaves: the shade and dry sprays
## it has up close, and the same thin side.
static func _add_far(bufs: Dictionary, parts: Dictionary, xf: Transform3D, tint: Color, plant := Vector4.ZERO) -> void:
	if parts.is_empty():
		return
	var look: Array = parts["look"]
	for part in ["bark", "leaf"]:
		var a: Array = parts[part]
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if pv.is_empty():
			continue
		var sk: String = part + ":" + String(look[1] if part == "bark" else look[0])
		if not bufs.has(sk):
			bufs[sk] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		var fb: Array = bufs[sk]
		var vs: PackedVector3Array = fb[0]
		var ns: PackedVector3Array = fb[1]
		var uvs: PackedVector2Array = fb[2]
		var cs: PackedColorArray = fb[3]
		var ix: PackedInt32Array = fb[4]
		var base := vs.size()
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pc: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var nb := xf.basis.orthonormalized()
		var pu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var pix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		if part == "leaf":
			# Leaves are cards: four vertices and six indices each, in order.
			for q in pv.size() / 4:
				var v0 := q * 4
				var card := pc[v0].a
				if RealTree.plant_gap((pv[v0] + pv[v0 + 1] + pv[v0 + 2] + pv[v0 + 3]) * 0.25, plant, card):
					continue
				var vb := vs.size()
				for j in range(v0, v0 + 4):
					vs.append(xf * pv[j])
					ns.append(nb * pn[j])
					cs.append(RealTree.plant_leaf(pc[j], plant) * tint)
					uvs.append(pu[j])
				for k in range(q * 6, q * 6 + 6):
					ix.append(vb + pix[k] - v0)
		else:
			for j in pv.size():
				vs.append(xf * pv[j])
				ns.append(nb * pn[j])
				cs.append(pc[j] * tint)
			uvs.append_array(pu)
			for q in pix:
				ix.append(base + q)
		# Packed arrays inside an Array are copies: store them back.
		bufs[sk] = [vs, ns, uvs, cs, ix]

## Grass for a chunk, as instance buffers (transform, tint and glow) keyed
## "<species>@<quarter>" (GrassKit species; quarters of the chunk so each can be culled on
## its own). Clumped, with bare gaps; turf, meadow grass, wild tall grass and wildflowers
## mixed by how lush and wild the ground is; thin on stony ground and under trees, none in
## thick snow. Deterministic per chunk, regenerated freely (never gameplay state).
static func build_grass_buffers(chunk: Dictionary, density: float, cover := PackedByteArray()) -> Dictionary:
	var out := {}
	if density <= 0.0:
		return out
	if cover.is_empty():
		cover = GroundCover.build(chunk)
	var base_density := density
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 901)
	var biome_tint := Color(0, 0, 0, 0)
	var biome_era: int = Eras.nature(chunk.get("era", 0))
	var lumen := 0.0
	var lush := 0.0
	if chunk.has("biome"):
		var bp := Biome.params(chunk["biome"], biome_era)
		lumen = bp["lumen"]
		lush = float(bp.get("lush", 0.0))
		biome_tint = bp["grass_tint"]
		biome_tint.a = 1.0
		density *= float(bp["grass_density"])
	# v18: the grass's colour, lushness and thickness run smoothly from one region's into
	# the next across the band where they meet (rows: tint rgb, lush, density).
	var blend := ChunkGenerator.biome_mix_grid(chunk, biome_era, ["grass_tint", "lush", "grass_density"])
	var thickest := 1.0
	if not blend.is_empty():
		var top := 0.0
		for row in blend:
			top = maxf(top, row[4])
		thickest = top
		density *= top / float(Biome.params(chunk["biome"], biome_era)["grass_density"])
	var seed := int(chunk.get("seed", 0))
	var clump := FastNoiseLite.new()
	clump.seed = seed ^ 0x6A55
	clump.frequency = 0.2
	clump.fractal_octaves = 2
	var wild := FastNoiseLite.new()
	wild.seed = seed ^ 0x77D
	wild.frequency = 0.035
	wild.fractal_octaves = 2
	var bloom := FastNoiseLite.new()
	bloom.seed = seed ^ 0xF10
	bloom.frequency = 0.06
	bloom.fractal_octaves = 1
	var x0 := float(chunk["cx"]) * SIZE
	var z0 := float(chunk["cz"]) * SIZE
	var count := int(16000 * density)
	var has_cave := false
	for o in chunk["objects"]:
		if o["t"] == "cave":
			has_cave = true
	has_cave = has_cave or chunk.has("hole")
	var plans := ChunkGenerator.keep_out(chunk)
	var looks := ChunkGenerator.look_grid(chunk)
	for n in count:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var yaw := r.randf() * TAU
		var pick := r.randf()
		var roll := r.randf()
		var size := r.randf()
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var dens := w[0] * Eras.GRASS_DENSITY[0] + w[1] * Eras.GRASS_DENSITY[1] + w[2] * Eras.GRASS_DENSITY[2]
		if not blend.is_empty():
			dens *= ChunkGenerator.mix_sample(blend, lx, lz, 4) / thickest
			lush = ChunkGenerator.mix_sample(blend, lx, lz, 3)
			biome_tint = Color(ChunkGenerator.mix_sample(blend, lx, lz, 0), ChunkGenerator.mix_sample(blend, lx, lz, 1), ChunkGenerator.mix_sample(blend, lx, lz, 2), 1.0)
		if pick > dens:
			continue
		# Thinning out up a steep bank (smaller clumps hold on longest), not a hard line.
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.4 + 0.15 * (1.0 - size):
			continue
		if pick > dens * looks[ChunkGenerator.look_cell(lx, lz)]:
			continue
		# Grass gives way to snow, stones and gravel, and thins under the trees.
		var cv := GroundCover.at(cover, lx, lz)
		if roll < cv.a * 1.5 or roll < cv.r * 0.92 or roll < cv.g * 0.95 or roll < cv.b * 0.55:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		# Clumps with gaps of shorter ground between them (narrow ones: wide bare gaps made
		# a meadow look like a lawn with tufts on it).
		if roll > smoothstep(-0.9, -0.1, clump.get_noise_2d(wx, wz)):
			continue
		if ChunkGenerator.kept_out(plans, lx, lz, 0.2):
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.15 or ChunkGenerator.under_river(chunk, lx, lz):
			continue
		var on_road := ChunkGenerator.road_at(chunk, lx, lz)
		var worn := TownLife.wear_at(chunk, lx, lz)
		# A verge of uncut grass right up to the wheel-worn edge of a road, not a mown
		# strip; trodden yards and paths thin it out gradually.
		if on_road > 0.5 or (on_road > 0.3 and r.randf() < (on_road - 0.3) * 5.0) or worn > 0.5 or (worn > 0.0 and r.randf() < worn * 1.6):
			continue
		if has_cave and ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		# Which species: wild, lush ground grows tall grass and flowers; worn and dry
		# ground short turf. Flowers and seed heads only in green lands.
		var wl := clampf(wild.get_noise_2d(wx, wz) * 0.9 + 0.5 + lush * 0.15, 0.0, 1.0)
		var green := w[Eras.MEDIEVAL]
		var u := r.randf()
		var sp := "meadow"
		var sc := lerpf(0.7, 1.35, size) * (1.0 + lush * 0.12)
		if green > 0.5 and u < 0.055 * green * (0.3 + wl * 1.4):
			sp = "flowers_%d" % clampi(int((bloom.get_noise_2d(wx, wz) * 0.7 + 0.5) * 4.0), 0, 3)
			sc = lerpf(0.8, 1.2, size)
		elif green > 0.3 and u < 0.06 + 0.3 * smoothstep(0.5, 0.85, wl):
			sp = "tall"
			sc = lerpf(0.75, 1.25, size)
		elif on_road > 0.0 and u < 0.65:
			sp = "tall"
			sc = lerpf(0.7, 1.15, size)
		elif u < 0.62 - 0.4 * wl:
			sp = "turf"
			sc = lerpf(0.8, 1.35, size)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.8, 1.2), sc))
		var tint := Color(0.33, 0.50, 0.16) * w[0] + Color(0.12, 0.55, 0.5) * w[1] + Color(0.35, 0.38, 0.3) * w[2]
		# Lush hollows deep green, wild and dry swathes olive and straw.
		tint = tint.lerp(Color(0.24, 0.42, 0.13), clampf(0.5 - wl, 0.0, 0.5) * w[0] * 0.6)
		tint = tint.lerp(Color(0.55, 0.52, 0.25), (r.randf() * 0.2 + clampf(wl - 0.55, 0.0, 0.45) * 0.6 - lush * 0.1) * w[0])
		if biome_tint.a > 0.0:
			tint = tint.lerp(biome_tint, w[biome_era] * 0.7)
		var key := "%s@%d" % [sp, (1 if lx >= SIZE * 0.5 else 0) + (2 if lz >= SIZE * 0.5 else 0)]
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
			tint.r, tint.g, tint.b, w[biome_era] * lumen])
		out[key] = buf
	# Crops in rows in the fields and gardens of villages (TownLife).
	TownLife.crops(chunk, out, density, plans)
	# Waterweed on lake and sea beds, in beds of its own, thickest a couple of metres
	# down and thinning out where the light fades. (Its own draws, so the grass above
	# stays as it was.)
	var rw := WHash.rng(seed, chunk["cx"], chunk["cz"], 905)
	for n in int(6000 * density):
		var lx := rw.randf() * SIZE
		var lz := rw.randf() * SIZE
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		var roll := rw.randf()
		var yaw := rw.randf() * TAU
		var size := rw.randf()
		if y > -0.7 or y < -14.0:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		var depth := smoothstep(-0.7, -2.2, y) * (1.0 - smoothstep(-9.0, -14.0, y))
		if roll > depth * smoothstep(-0.35, 0.25, wild.get_noise_2d(wx * 1.7 + 300.0, wz * 1.7)):
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.5 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.kept_out(plans, lx, lz, 0.3):
			continue
		if has_cave and ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var sc := lerpf(0.55, 1.6, size * size)
		# Each clump its own kind and its own lean, so a bed never reads as rows of one card.
		var kind := ["weed", "weed_1", "weed_2", "weed_3"][int(rw.randf() * 3.999)] as String
		if kind == "weed_1" and y > -2.5:
			kind = "weed_2" # the tall strands only where they stay under the surface
		sc = minf(sc, maxf(-y / 1.6, 0.55))
		var tilt := Basis(Vector3(cos(yaw * 1.7), 0, sin(yaw * 1.7)), rw.randf_range(0.0, 0.3))
		var b := (tilt * Basis(Vector3.UP, yaw)).scaled(Vector3(sc, sc * rw.randf_range(0.7, 1.4), sc))
		var tint := Color(0.34, 0.46, 0.15) * w[0] + Color(0.14, 0.46, 0.38) * w[1] + Color(0.4, 0.36, 0.2) * w[2]
		tint = tint.lerp(Color(0.46, 0.4, 0.17), rw.randf() * 0.35)
		var key := "%s@%d" % [kind, (1 if lx >= SIZE * 0.5 else 0) + (2 if lz >= SIZE * 0.5 else 0)]
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
			tint.r, tint.g, tint.b, -1.0])
		out[key] = buf
	# Lily pads, reeds, kelp and coral reefs (their own keys, "aq_...@0").
	AquaFlora.build(chunk, base_density, out)
	return out

## Ground clutter (stones, tiny glowing mushrooms, alloy debris, undergrowth), keyed by
## clutter mesh name. Deterministic per chunk, regenerated freely (never gameplay state).
static func build_clutter_buffers(chunk: Dictionary, density: float, cover := PackedByteArray()) -> Dictionary:
	var out := {}
	if density <= 0.0:
		return out
	if cover.is_empty():
		cover = GroundCover.build(chunk)
	_scatter_stones(chunk, density, cover, out)
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 902)
	# Nothing grows up through a floor.
	var plans := ChunkGenerator.keep_out(chunk)
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
		# Green lands' stones are scattered on their own (_scatter_stones).
		if era == Eras.MEDIEVAL or ChunkGenerator.slope_at(chunk, lx, lz) > 0.6:
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.2 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.3 or ChunkGenerator.kept_out(plans, lx, lz, 0.3):
			continue
		var key := "clutter_%d" % era
		if not out.has(key):
			out[key] = PackedFloat32Array()
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
		var buf: PackedFloat32Array = out[key]
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
		out[key] = buf
	_scatter_floor(chunk, density, cover, plans, out)
	# Undergrowth: the region's own ferns, bushes, flowers and stranger things.
	if chunk.has("biome"):
		var era: int = Eras.nature(chunk.get("era", 0))
		var bp := Biome.params(chunk["biome"], era)
		var unders: Array = bp["under"]
		# Clumps and thickets where a slow noise of the land is high, scattered singles
		# between (world space, so clumps run on across chunk edges).
		var thicket := FastNoiseLite.new()
		thicket.seed = int(chunk.get("seed", 0)) ^ 0x7B15
		thicket.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		thicket.frequency = 0.045
		thicket.fractal_octaves = 3
		var looks := ChunkGenerator.look_grid(chunk)
		var top := _top(chunk)
		var ux0 := float(chunk["cx"]) * SIZE
		var uz0 := float(chunk["cz"]) * SIZE
		# v18: near a region's edge, now and then the neighbour's plants (as its trees).
		var mixed := chunk.has("biome_mix")
		var thickest := float(bp["under_density"])
		if mixed:
			for h in chunk["biomes"]:
				thickest = maxf(thickest, float(Biome.params(h, era)["under_density"]))
		for n in int(580 * density * thickest * (0.6 if era == Eras.SCIFI else 1.0)):
			var lx := r.randf() * SIZE
			var lz := r.randf() * SIZE
			var pick := r.randi()
			var yaw := r.randf() * TAU
			var sc := r.randf_range(0.6, 1.5)
			# Clumps: undergrowth gathers where a low-frequency mask is high.
			var mask := thicket.get_noise_2d(ux0 + lx, uz0 + lz)
			if r.randf() > 0.06 + 0.94 * smoothstep(0.0, 0.45, mask):
				continue
			var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
			if w[era] < 0.5 or ChunkGenerator.slope_at(chunk, lx, lz) > 0.6:
				continue
			# Bare sand and dust grow little (the size roll doubles as the chance).
			if (sc - 0.6) / 0.9 > looks[ChunkGenerator.look_cell(lx, lz)]:
				continue
			var y := ChunkGenerator.height_at(chunk, lx, lz)
			if y < 0.3 or ChunkGenerator.under_river(chunk, lx, lz) or Flora.was_cleared(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.05 or ChunkGenerator.in_cave(chunk, lx, lz) or ChunkGenerator.kept_out(plans, lx, lz, 0.5):
				continue
			var own := unders
			if mixed:
				var rp := Biome.params(ChunkGenerator.biome_pick(chunk, lx, lz, ((pick >> 20) & 0xFF) / 256.0), era)
				if float((pick * 2654435761) & 0xFFFF) / 65536.0 * thickest >= float(rp["under_density"]):
					continue
				own = rp["under"]
			# Each plant where its kind grows: the region's first species (from the roll)
			# that suits this spot, or none.
			var sp := _under_for(chunk, cover, own, pick, era, lx, lz, y, (sc - 0.6) / 0.9, top)
			if sp < 0:
				continue
			# Wild flowers come in drifts, not dotted one by one across the grass, and even
			# in a drift there is more green than bloom (a solid mat reads as alien).
			if era == Eras.MEDIEVAL and (mask < 0.2 or (pick >> 12) & 1 == 1) and Flora.under_form(sp, era) == "flowers":
				continue
			var key := "under#%d#%d" % [sp, era]
			if not out.has(key):
				out[key] = PackedFloat32Array()
			# No two alike: each stretched, squat or tall, and leaning a little.
			var b := Basis.from_euler(Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12))) * Basis(Vector3.UP, yaw)
			b = b.scaled_local(Vector3(sc * r.randf_range(0.8, 1.25), sc * r.randf_range(0.75, 1.3), sc * r.randf_range(0.8, 1.25)))
			var buf: PackedFloat32Array = out[key]
			buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
			out[key] = buf
	return out

## Which of a region's undergrowth species `unders` grows at (lx, lz), starting from the
## one `pick` chose, or -1 for none. Nothing grows through snow or on the bare heights
## near the snow line; reeds and rushes only at the water's edge; ferns in the shade and
## litter of woods, not out on open meadow. (Fantasy and alien forms grow where they
## like.) `u` is a spare uniform roll.
static func _under_for(chunk: Dictionary, cover: PackedByteArray, unders: Array, pick: int, era: int, lx: float, lz: float, y: float, u: float, top: float) -> int:
	var cv := GroundCover.at(cover, lx, lz)
	if cv.a > 0.12 or y > WorldField.snow_line - 4.0 - 8.0 * u:
		return -1
	var wet := -1.0
	for n in unders.size():
		# Half the time a plant that doesn't suit the spot leaves it bare rather than
		# giving way to the next kind (or one kind would carpet the place).
		if n == 1 and (pick >> 9) & 1 == 0:
			return -1
		var sp: int = unders[(pick + n) % unders.size()]
		match Flora.under_form(sp, era):
			"reeds":
				if era == Eras.MEDIEVAL:
					if wet < 0.0:
						wet = ChunkGenerator.wet_at(chunk, lx, lz)
					if u > wet:
						continue
			"fern":
				# Woodland ferns: in the litter under trees, never out on a beach, a gravel
				# bar or the wet ground at the water's edge (that is sedge and rush country),
				# nor in the cold of high ground or a valley under snowy peaks.
				if era == Eras.MEDIEVAL:
					if u > cv.b * 2.5 or cv.g > 0.25 or ChunkGenerator.sand_at(chunk, lx, lz) > 0.2:
						continue
					if wet < 0.0:
						wet = ChunkGenerator.wet_at(chunk, lx, lz)
					if wet > 0.2 or u < _chill(top, y):
						continue
			"flowers":
				# Wild flowers want light: few under the trees.
				if u < cv.b * 0.8:
					continue
		return sp
	return -1

## The floor of a wood (ForestFloor): fallen branches, cones under conifers, cushions of
## moss and drifts of needles, gathered under the oaks and pines, so the ground there
## is not smooth bare soil. Keys "floor:<kind>".
static func _scatter_floor(chunk: Dictionary, density: float, cover: PackedByteArray, plans: Array, out: Dictionary) -> void:
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 905)
	for o in chunk["objects"]:
		var t: String = o["t"]
		if (t != "pine" and t != "oak") or o["st"].get("gone", false):
			continue
		var p: Vector3 = o["p"]
		var reach := 2.0 + 1.8 * float(o["s"])
		for n in int(r.randi_range(2, 6) * density):
			var a := r.randf() * TAU
			var d := sqrt(r.randf()) * reach
			var lx := p.x + cos(a) * d
			var lz := p.z + sin(a) * d
			var roll := r.randf()
			var yaw := r.randf() * TAU
			var sc := r.randf_range(0.7, 1.3)
			if lx < 0.0 or lz < 0.0 or lx >= SIZE or lz >= SIZE:
				continue
			var cv := GroundCover.at(cover, lx, lz)
			if cv.a > 0.3 or cv.b < 0.15 or ChunkGenerator.slope_at(chunk, lx, lz) > 0.7 \
					or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.05 \
					or ChunkGenerator.kept_out(plans, lx, lz, 0.5):
				continue
			var kind := "duff"
			if roll < 0.22:
				kind = "branch"
			elif roll < 0.55:
				kind = "cones" if t == "pine" else "duff"
			elif roll < 0.75:
				kind = "moss"
			var key := "floor:" + kind
			if not out.has(key):
				out[key] = PackedFloat32Array()
			var y := ChunkGenerator.height_at(chunk, lx, lz)
			# Lie with the ground, not level across a slope.
			var nrm := Vector3(ChunkGenerator.height_at(chunk, lx - 0.5, lz) - ChunkGenerator.height_at(chunk, lx + 0.5, lz), 1.0,
				ChunkGenerator.height_at(chunk, lx, lz - 0.5) - ChunkGenerator.height_at(chunk, lx, lz + 0.5)).normalized()
			var b := Basis(Vector3.UP, yaw)
			var ax := Vector3.UP.cross(nrm)
			if ax.length() > 0.001:
				b = Basis(ax.normalized(), Vector3.UP.angle_to(nrm)) * b
			b = b.scaled_local(Vector3(sc, sc * r.randf_range(0.8, 1.2), sc))
			var buf: PackedFloat32Array = out[key]
			buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
			out[key] = buf

## How cold the spot at height y feels to a plant, 0 (lowland) to 1: high up near the snow
## line, or low down in a chunk whose ground climbs toward it (a lake under snowy peaks).
## `top` is the chunk's highest ground (_top).
static func _chill(top: float, y: float) -> float:
	var sl := WorldField.snow_line
	return maxf(smoothstep(sl - 34.0, sl - 12.0, y), 0.8 * smoothstep(sl - 40.0, sl - 8.0, top))

static func _top(chunk: Dictionary) -> float:
	var top := -INF
	var hs: PackedFloat32Array = chunk["heights"]
	for k in range(0, hs.size(), 7):
		top = maxf(top, hs[k])
	return top

## Loose stones (StoneKit) into `out`: a few in the grass, thick on scree and gravel so
## the ground there is more stone than soil. Keys "stone:<kind>" (pebbles per quarter of
## the chunk, "stone:pebble@<q>") hold transform + colour (alpha: moss); "~stones" holds
## the ones big enough to stand on, as [kind index, transform] for their colliders.
static func _scatter_stones(chunk: Dictionary, density: float, cover: PackedByteArray, out: Dictionary) -> void:
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 903)
	var plans := ChunkGenerator.keep_out(chunk)
	var has_cave := chunk.has("hole")
	var solid := PackedFloat32Array()
	var greys := [Color(0.56, 0.54, 0.5), Color(0.5, 0.47, 0.42), Color(0.62, 0.6, 0.57), Color(0.47, 0.46, 0.45)]
	# Stones lie in bunches (where frost heaved them up, a bank slumped, someone cleared a
	# field into a heap) with bare stretches between, not one every few strides: a slow
	# noise gathers the field stones, a quicker one breaks up the scree.
	var x0 := float(chunk["cx"]) * SIZE
	var z0 := float(chunk["cz"]) * SIZE
	var heap := FastNoiseLite.new()
	heap.seed = int(chunk.get("seed", 0)) ^ 0x57A9
	heap.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	heap.frequency = 0.09
	heap.fractal_octaves = 2
	var grit := FastNoiseLite.new()
	grit.seed = int(chunk.get("seed", 0)) ^ 0x6217
	grit.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grit.frequency = 0.3
	grit.fractal_octaves = 1
	# Both worked out once a metre (thousands of stones ask), with the sand.
	var bunches := PackedFloat32Array()
	bunches.resize(RES * RES)
	var grits := PackedFloat32Array()
	grits.resize(RES * RES)
	for j in RES:
		for i in RES:
			bunches[j * RES + i] = smoothstep(0.15, 0.65, heap.get_noise_2d(x0 + i, z0 + j))
			grits[j * RES + i] = grit.get_noise_2d(x0 + i, z0 + j) * 0.5 + 0.5
	var looks := ChunkGenerator.look_grid(chunk)
	for n in int(28000 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		# Whether a stone lies here, from the nearest metre's cover (cheap: most of
		# these thousands of tries come to nothing); the stone itself reads it finely.
		var lk := ChunkGenerator.look_cell(lx, lz)
		var ck := lk * 2
		var stony := maxf(cover[ck], cover[ck + 1]) / 255.0 if not cover.is_empty() else 0.0
		var bunch := bunches[lk / 2]
		var odds := 0.003 + 0.04 * bunch * bunch + stony * stony * 0.9 * (0.45 + 0.8 * grits[lk / 2])
		if r.randf() > odds * (1.0 - looks[lk + 1]) or (not cover.is_empty() and cover[ck + 3] > 153):
			continue
		var cv := GroundCover.at(cover, lx, lz)
		stony = maxf(cv.r, cv.g)
		var slope := ChunkGenerator.slope_at(chunk, lx, lz)
		if slope > 0.75:
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < -0.6 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.3 or ChunkGenerator.kept_out(plans, lx, lz, 0.3):
			continue
		if has_cave and ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		var gravelly := cv.g > cv.r
		var a := r.randf()
		var size: float
		if gravelly:
			size = lerpf(0.05, 0.17, a * a) if a < 0.97 else 0.3
		elif stony > 0.3:
			size = 0.05 + 0.85 * pow(a, 7.0)
		else:
			# Mostly small, a few big ones at the heart of a bunch.
			size = 0.04 + (0.16 + 0.5 * bunch) * pow(a, 3.0)
		var kind := "pebble"
		if size >= 0.5:
			kind = "rock_a" if r.randf() < 0.5 else "rock_b"
		elif size >= 0.16:
			# Water rounds stones; field and scree stones stay angular.
			kind = "stone_b" if gravelly or r.randf() < 0.12 else "stone_a"
		var flat := r.randf_range(0.35, 0.95) if not gravelly else r.randf_range(0.5, 1.0)
		var long := r.randf_range(0.65, 1.45)
		# Lying on the slope, turned and tipped a little, partly sunk.
		var nrm := Vector3(ChunkGenerator.height_at(chunk, lx - 0.5, lz) - ChunkGenerator.height_at(chunk, lx + 0.5, lz), 1.0,
			ChunkGenerator.height_at(chunk, lx, lz - 0.5) - ChunkGenerator.height_at(chunk, lx, lz + 0.5)).normalized()
		var b := Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, r.randf() * TAU) * Basis.from_euler(Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2)))
		b = b.scaled_local(Vector3(size * long, size * flat, size / long))
		var p := Vector3(lx, y - size * flat * 0.12, lz)
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var tint: Color = greys[r.randi() % greys.size()]
		tint = tint * w[Eras.MEDIEVAL] + Eras.GROUND[Eras.FANTASY][2] * w[Eras.FANTASY] + Eras.GROUND[Eras.SCIFI][2] * w[Eras.SCIFI]
		var st := ChunkGenerator.stone_at(chunk, lx, lz)
		if st.a > 0.0:
			tint = tint.lerp(Color(st.r, st.g, st.b), st.a * 0.8)
		var v := r.randf_range(0.8, 1.12) * (1.08 if gravelly else 1.0)
		tint = Color(tint.r * v * r.randf_range(0.96, 1.04), tint.g * v, tint.b * v * r.randf_range(0.95, 1.05),
			w[Eras.MEDIEVAL] * r.randf() * (0.0 if gravelly else (0.25 if stony > 0.3 else 0.7)))
		var key := "stone:" + kind
		if kind == "pebble":
			key += "@%d" % [(1 if lx >= SIZE * 0.5 else 0) + (2 if lz >= SIZE * 0.5 else 0)]
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a])
		out[key] = buf
		if size * flat >= 0.25:
			solid.append_array([StoneKit.KINDS.find(kind), b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z])
	# Stones on lake and sea beds, scattered and in drifts, furred green with algae.
	# (Their own draws, so the stones on land stay where they were.)
	var rs := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 906)
	for n in int(2200 * density):
		var lx := rs.randf() * SIZE
		var lz := rs.randf() * SIZE
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		var roll := rs.randf()
		var a := rs.randf()
		var flat := rs.randf_range(0.55, 0.95)
		var turn := rs.randf() * TAU
		var tip := Vector2(rs.randf_range(-0.25, 0.25), rs.randf_range(-0.25, 0.25))
		var grey: Color = greys[rs.randi() % greys.size()]
		var v := rs.randf_range(0.75, 1.1)
		var algae := rs.randf()
		if y > -0.6 or y < -14.0 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.kept_out(plans, lx, lz, 0.3):
			continue
		# Drifts where a slow noise of the bed is high, a few loose ones anywhere.
		var drift := 0.5 + 0.5 * sin(lx * 0.21 + float(chunk["cx"]) * 3.1) * cos(lz * 0.17 + float(chunk["cz"]) * 2.3)
		if roll > 0.04 + 0.3 * drift * drift:
			continue
		var size := 0.08 + 0.85 * pow(a, 3.0)
		var kind := "pebble"
		if size >= 0.5:
			kind = "rock_a" if a > 0.96 else "rock_b"
		elif size >= 0.16:
			kind = "stone_a" if a > 0.8 else "stone_b"
		var nrm := Vector3(ChunkGenerator.height_at(chunk, lx - 0.5, lz) - ChunkGenerator.height_at(chunk, lx + 0.5, lz), 1.0,
			ChunkGenerator.height_at(chunk, lx, lz - 0.5) - ChunkGenerator.height_at(chunk, lx, lz + 0.5)).normalized()
		var b := Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, turn) * Basis.from_euler(Vector3(tip.x, 0, tip.y))
		b = b.scaled_local(Vector3(size, size * flat, size))
		var p := Vector3(lx, y - size * flat * 0.15, lz)
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var tint := grey * w[Eras.MEDIEVAL] + Eras.GROUND[Eras.FANTASY][2] * w[Eras.FANTASY] + Eras.GROUND[Eras.SCIFI][2] * w[Eras.SCIFI]
		tint = Color(tint.r * v * 0.9, tint.g * v * 0.95, tint.b * v * 0.85, 0.35 + 0.6 * algae)
		var key := "stone:" + kind
		if kind == "pebble":
			key += "@%d" % [(1 if lx >= SIZE * 0.5 else 0) + (2 if lz >= SIZE * 0.5 else 0)]
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a])
		out[key] = buf
		if size * flat >= 0.25:
			solid.append_array([StoneKit.KINDS.find(kind), b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z])
	_river_rocks(chunk, density, greys, out, solid)
	# The rock mounds coral reefs grow on (AquaFlora lays the coral over them).
	AquaFlora.reef_rocks(chunk, out, solid)
	if not solid.is_empty():
		out["~stones"] = solid

## Boulders and stones in a river's bed, breaking the surface: thick where the water
## falls steeply (the rapids, whose white water needs something to break on), a few
## anywhere along the channel and toward its banks, where the current drops what it
## carries. From the chunk's 2 m river grid, with their own draws (the other stones keep their
## places).
static func _river_rocks(chunk: Dictionary, density: float, greys: Array, out: Dictionary, solid: PackedFloat32Array) -> void:
	if not chunk.has("river"):
		return
	var rv: PackedFloat32Array = chunk["river"]
	var N := ChunkGenerator.RIVER_N
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 908)
	var wet := func(i: int, j: int) -> bool:
		var k := (j * N + i) * 3
		return rv[k + 1] < 1.0 and rv[k + 2] > 0.25 and rv[k] > ChunkGenerator.WATER_LEVEL + 0.2
	for j in N:
		for i in N:
			var k := (j * N + i) * 3
			var roll := r.randf()
			if not wet.call(i, j):
				continue
			# The water's own fall per 4 m, between wet neighbours (its level climbs the
			# banks, which is no rapid).
			var fall := 0.0
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(mini(i + d.x, N - 1), mini(j + d.y, N - 1))
				var b := Vector2i(maxi(i - d.x, 0), maxi(j - d.y, 0))
				if wet.call(a.x, a.y) and wet.call(b.x, b.y):
					fall = maxf(fall, absf(rv[(a.y * N + a.x) * 3] - rv[(b.y * N + b.x) * 3]))
			var rapid := smoothstep(0.12, 0.35, fall)
			var bank := smoothstep(0.45, 0.9, rv[k + 1])
			var count := 0
			if roll < (0.025 + 0.06 * bank + 0.5 * rapid) * density:
				count = 1 + int(r.randf() * (1.0 + 2.0 * rapid))
			for c in count:
				var lx := clampf(i * 2.0 + r.randf_range(-1.0, 1.0), 0.0, SIZE - 0.01)
				var lz := clampf(j * 2.0 + r.randf_range(-1.0, 1.0), 0.0, SIZE - 0.01)
				var bed := ChunkGenerator.height_at(chunk, lx, lz)
				var depth := rv[k] - bed
				if depth > 0.9 or depth < 0.05:
					continue
				var flat := r.randf_range(0.8, 1.05)
				var a := r.randf()
				# Most just break the surface; a few lie under it, a few stand well out.
				var top := depth + lerpf(-0.15, 0.45, a) * (0.6 + 0.6 * rapid)
				# (The kit rocks stand about 0.66 of their width, 0.12 of it sunk in the bed.)
				var size := clampf(top / (flat * 0.54), 0.25, 1.6)
				var kind := "rock_a" if r.randf() < 0.5 else "rock_b"
				var long := r.randf_range(0.75, 1.35)
				var b := Basis(Vector3.UP, r.randf() * TAU) * Basis.from_euler(Vector3(r.randf_range(-0.15, 0.15), 0, r.randf_range(-0.15, 0.15)))
				b = b.scaled_local(Vector3(size * long, size * flat, size / long))
				var p := Vector3(lx, bed - size * flat * 0.12, lz)
				var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
				var grey: Color = greys[r.randi() % greys.size()]
				var tint := grey * w[Eras.MEDIEVAL] + Eras.GROUND[Eras.FANTASY][2] * w[Eras.FANTASY] + Eras.GROUND[Eras.SCIFI][2] * w[Eras.SCIFI]
				var st := ChunkGenerator.stone_at(chunk, lx, lz)
				if st.a > 0.0:
					tint = tint.lerp(Color(st.r, st.g, st.b), st.a * 0.8)
				# Water-dark, with a little green weed low down in slack water.
				var v := r.randf_range(0.72, 0.95)
				tint = Color(tint.r * v, tint.g * v, tint.b * v, w[Eras.MEDIEVAL] * r.randf_range(0.05, 0.3) * (1.0 - rapid))
				var key := "stone:" + kind
				var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
				buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a])
				out[key] = buf
				if size * flat >= 0.4:
					solid.append_array([StoneKit.KINDS.find(kind), b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z])

## Crags: big rocks set into steep faces, standing out of them and up past their rims,
## so a cliff reads as broken rock with a ragged skyline instead of one smooth draped
## sheet. Keys "stone:rock_a" and "stone:rock_b" hold transform + colour as the stones
## do; "~crags" their colliders. Built with the terrain at any distance (cliffs are seen
## from far off), from the chunk's own heights, so the same every time.
static func build_crag_buffers(chunk: Dictionary) -> Dictionary:
	var out := {}
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 907)
	var plans := ChunkGenerator.keep_out(chunk)
	var has_cave := chunk.has("hole")
	var solid := PackedFloat32Array()
	var greys := [Color(0.56, 0.54, 0.5), Color(0.5, 0.47, 0.42), Color(0.62, 0.6, 0.57), Color(0.47, 0.46, 0.45)]
	for n in 1200:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var roll := r.randf()
		var a := r.randf()
		var flat := r.randf_range(0.45, 0.8)
		var turn := r.randf() * TAU
		var tip := Vector2(r.randf_range(-0.2, 0.2), r.randf_range(-0.2, 0.2))
		var grey: Color = greys[r.randi() % greys.size()]
		var v := r.randf_range(0.82, 1.1)
		var moss := r.randf()
		var kind := "rock_a" if r.randf() < 0.5 else "rock_b"
		var slope := ChunkGenerator.slope_at(chunk, lx, lz)
		if slope < 0.9:
			continue
		var nrm := Vector3(ChunkGenerator.height_at(chunk, lx - 1.0, lz) - ChunkGenerator.height_at(chunk, lx + 1.0, lz), 2.0,
			ChunkGenerator.height_at(chunk, lx, lz - 1.0) - ChunkGenerator.height_at(chunk, lx, lz + 1.0)).normalized()
		# At a rim (the ground a few metres up the face levels off) they stand up past
		# it and break the skyline; down the face they come in bands, like bedding.
		var upx := Vector2(-nrm.x, -nrm.z).normalized() * 4.0
		var rim := 1.0 - smoothstep(0.3, 0.8, ChunkGenerator.slope_at(chunk, clampf(lx + upx.x, 0.0, SIZE), clampf(lz + upx.y, 0.0, SIZE)))
		var wy := ChunkGenerator.height_at(chunk, lx, lz)
		var band := smoothstep(0.2, 0.8, sin(wy * 0.9 + sin(float(chunk["cx"]) * 64.0 + lx) * 0.08) * 0.5 + 0.5)
		if roll > smoothstep(0.9, 1.8, slope) * (0.035 + 0.06 * band + 0.25 * rim):
			continue
		var y := wy
		if y < 0.3 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.0 \
				or ChunkGenerator.kept_out(plans, lx, lz, 2.0):
			continue
		if has_cave and ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		var size := lerpf(2.5, 7.0, a * a) * (1.0 + 0.3 * rim)
		# Ledges: flattish slabs lying level out of the face, a fifth sunk into it; at
		# a rim, upright blocks.
		var up := nrm.lerp(Vector3.UP, 0.65 - 0.4 * rim).normalized()
		var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, turn) * Basis.from_euler(Vector3(tip.x, 0, tip.y))
		b = b.scaled_local(Vector3(size, size * lerpf(flat, 1.0, rim), size * 0.8))
		var p := Vector3(lx, y, lz) - nrm * size * lerpf(0.2, 0.12, rim)
		# Never stuck on in mid-air: where the face falls away under it (an upright block
		# at a rim stood out over the drop, a big slab off a sheer face) it goes further
		# into the hill until most of its base is on rock and a good part of it is inside;
		# failing that, it isn't there.
		var inward := Vector3(-nrm.x, 0.0, -nrm.z).normalized()
		var tries := 0
		while _crag_loose(chunk, kind, b, p, size) and tries < 5:
			p += inward * size * 0.1
			tries += 1
		if tries == 5 and _crag_loose(chunk, kind, b, p, size):
			continue
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var tint := grey * w[Eras.MEDIEVAL] + Eras.GROUND[Eras.FANTASY][2] * w[Eras.FANTASY] + Eras.GROUND[Eras.SCIFI][2] * w[Eras.SCIFI]
		# The landform's own rock (red sandstone, pale limestone...), as the face shows it.
		var st := ChunkGenerator.stone_at(chunk, lx, lz)
		if st.a > 0.0:
			tint = tint.lerp(Color(st.r, st.g, st.b), st.a * 0.85)
		tint = Color(tint.r * v, tint.g * v, tint.b * v, w[Eras.MEDIEVAL] * moss * 0.3)
		var key := "stone:" + kind
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a])
		out[key] = buf
		solid.append_array([StoneKit.KINDS.find(kind), b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z])
	if not solid.is_empty():
		out["~crags"] = solid
	return out

## How many of eight points round a crag's base (basis `b` at `p`) stand clear of the
## ground by more than a few percent of its size.
static func _crag_hangs(chunk: Dictionary, b: Basis, p: Vector3, size: float) -> int:
	var n := 0
	for d in 8:
		var a := TAU * d / 8.0
		var w := p + b * (Vector3(cos(a), 0.06, sin(a)) * 0.42)
		if w.y - ChunkGenerator.height_at(chunk, clampf(w.x, 0.0, SIZE - 0.01), clampf(w.z, 0.0, SIZE - 0.01)) > 0.15 * size:
			n += 1
	return n

## How much of a crag (StoneKit `kind`, basis `b` at `p`) is inside the hill: the share
## of its hull's corners under the ground (a sample of them).
static func _crag_inside(chunk: Dictionary, kind: String, b: Basis, p: Vector3) -> float:
	var hull := StoneKit.hull(kind)
	if hull.is_empty():
		return 1.0
	var every := maxi(1, hull.size() / 64)
	var n := 0
	var under := 0
	for i in range(0, hull.size(), every):
		var w := p + b * hull[i]
		n += 1
		if w.y < ChunkGenerator.height_at(chunk, clampf(w.x, 0.0, SIZE - 0.01), clampf(w.z, 0.0, SIZE - 0.01)):
			under += 1
	return float(under) / float(n)

## Most air allowed under a crag's lower half (_crag_air): a third of its size, and never
## more than a metre and a half under the biggest.
const AIR_SHARE := 0.33
const AIR_MAX := 1.5

## The most air under a crag, in metres: over its hull's lower half (a sample of the
## corners below its middle), how far the highest stands above the ground straight under
## it. A crag standing well into a slope can still jut out over the fall of it, with
## daylight under its outer side, and from across a crater or valley it hangs there.
static func _crag_air(chunk: Dictionary, kind: String, b: Basis, p: Vector3) -> float:
	var hull := StoneKit.hull(kind)
	if hull.is_empty():
		return 0.0
	var mid := (p + b * Vector3(0.0, 0.5, 0.0)).y
	var every := maxi(1, hull.size() / 64)
	var most := 0.0
	for i in range(0, hull.size(), every):
		var w := p + b * hull[i]
		if w.y < mid:
			most = maxf(most, w.y - ChunkGenerator.height_at(chunk, clampf(w.x, 0.0, SIZE - 0.01), clampf(w.z, 0.0, SIZE - 0.01)))
	return most

## True when a crag would read as stuck on in mid-air: its base half over a drop, too
## little of it inside the hill, or daylight under its lower side.
static func _crag_loose(chunk: Dictionary, kind: String, b: Basis, p: Vector3, size: float) -> bool:
	return _crag_hangs(chunk, b, p, size) >= 3 or _crag_inside(chunk, kind, b, p) < 0.38 \
		or _crag_air(chunk, kind, b, p) > minf(AIR_SHARE * size, AIR_MAX)

## Harvests the undergrowth plant nearest the segment from..to (world space) within
## `reach` of it: hides it, remembers it in the chunk (it does not grow back), and
## returns {"key": mesh key, "pos": world position}, or {} when nothing is there.
func harvest_under(from: Vector3, to: Vector3, reach: float) -> Dictionary:
	var best := find_under(from, to, reach)
	if best.is_empty():
		return {}
	clear_under(best)
	return {"key": best["key"], "pos": best["pos"]}

## The undergrowth plant nearest the segment from..to within `reach`, left standing:
## {"key", "pos" (world), "mm", "i", "local", "d"} or {}. clear_under() picks it.
func find_under(from: Vector3, to: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for mmi in _clutter:
		var k: String = mmi.get_meta("key", "")
		if not k.begins_with("under"):
			continue
		var buf: PackedFloat32Array = mmi.get_meta("buf", PackedFloat32Array())
		for i in buf.size() / 12:
			var o := i * 12
			var sc := Vector3(buf[o + 1], buf[o + 5], buf[o + 9]).length()
			if sc < 0.01:
				continue
			var local := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
			var at := position + local
			var c := at + Vector3(0, 0.45 * sc, 0)
			var d := Geometry3D.get_closest_point_to_segment(c, from, to).distance_to(c) - 0.3 * sc
			if d < best_d:
				best_d = d
				best = {"key": k, "pos": at, "mm": mmi.multimesh, "mmi": mmi, "i": i, "local": local, "d": d}
	return best

## Hides a plant find_under() found and remembers it in the chunk (it does not grow back).
func clear_under(best: Dictionary) -> void:
	var mm: MultiMesh = best["mm"]
	var o: Vector3 = best["local"]
	mm.set_instance_transform(best["i"], Transform3D(Basis.from_scale(Vector3.ZERO), o))
	var mmi: MultiMeshInstance3D = best["mmi"]
	var buf: PackedFloat32Array = mmi.get_meta("buf")
	for j in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
		buf[int(best["i"]) * 12 + j] = 0.0
	mmi.set_meta("buf", buf)
	var cl: PackedFloat32Array = data.get("cleared", PackedFloat32Array())
	cl.append_array([o.x, o.z])
	data["cleared"] = cl
	Game.mark_chunk_dirty(data)

var _river: MeshInstance3D

func set_river(arrays: Array) -> void:
	if data.has("falls"):
		WaterfallFx.add_all(self, data)
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

## `fade` dissolves the old mesh into the new one (a change of detail as you move) rather
## than swapping it in one frame.
func set_terrain(arrays: Array, step: int, fade := false) -> void:
	lod = step
	if fade and appear >= 1.0 and not going and _terrain.mesh != null:
		if _old_terrain != null:
			_old_terrain.queue_free()
		_old_terrain = _terrain
		_terrain = MeshInstance3D.new()
		_terrain.name = "Terrain"
		_terrain.set_instance_shader_parameter("appear", 0.0)
		add_child(_terrain)
		_swap_t = 0.0
		set_process(true)
	var mesh := ArrayMesh.new()
	var fmt := LOOK_FORMAT if arrays[Mesh.ARRAY_CUSTOM0] != null else 0
	if arrays[Mesh.ARRAY_CUSTOM3] != null:
		fmt |= COVER_FORMAT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	mesh.surface_set_material(0, terrain_material)
	_terrain.mesh = mesh
	if _height_shape != null:
		_update_height_shape()

## The cave walls under this chunk (Caves.build), or {} to drop them.
func set_cave(res: Dictionary) -> void:
	if _cave != null:
		_cave.queue_free()
		_cave = null
	if _cave_shape != null:
		_cave_shape.queue_free()
		_cave_shape = null
	_cave_faces = PackedVector3Array()
	if res.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["arrays"])
	mesh.surface_set_material(0, Caves.material())
	_cave = MeshInstance3D.new()
	_cave.name = "Cave"
	_cave.mesh = mesh
	add_child(_cave)
	_cave_faces = res["faces"]
	if _body != null:
		_add_cave_shape()

func _add_cave_shape() -> void:
	if _cave_faces.is_empty():
		return
	var cs := ConcavePolygonShape3D.new()
	cs.backface_collision = true
	cs.set_faces(_cave_faces)
	_cave_shape = CollisionShape3D.new()
	_cave_shape.shape = cs
	_body.add_child(_cave_shape)

## `keep_far` keeps the current far tree mesh when `buffers` has none (see refresh_far).
func set_objects(buffers: Dictionary, keep_far := false) -> void:
	var old_far = _mm.get("~far") if keep_far and not buffers.has("~far") else null
	for t in _mm:
		if _mm[t] != old_far:
			_mm[t].queue_free()
	_mm.clear()
	if old_far != null:
		_mm["~far"] = old_far
		buffers = buffers.duplicate()
		buffers["~far"] = {} # near trees still hand over to it
	for t in buffers:
		if t == "~far":
			if old_far == null:
				_add_far_mesh(buffers[t])
			continue
		var buf: PackedFloat32Array = buffers[t]
		if t.ends_with("~in") or t.ends_with("~glow"):
			_add_rooms(t, buf)
			continue
		var sooty: bool = String(t).ends_with(SOOT)
		var mt: String = String(t).trim_suffix(SOOT)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = ObjectLibrary.get_mesh(mt)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + t.replace("#", "_")
		if sooty:
			mmi.material_overlay = soot_material()
		var k := ObjectLibrary.kind(mt.get_slice("#", 0))
		if k == "tree" and RealTree.handles(mt.get_slice("#", 0)) and buffers.has("~far"):
			# Up close only; the merged far mesh takes over beyond, tree by tree through
			# TREE_FADE (lod_fade.gdshaderinc). The range only has to cover the band from
			# the multimesh's middle, somewhere in the chunk.
			mmi.set_instance_shader_parameter("lod_band", Vector3(TREE_FADE.x, TREE_FADE.y, 1.0))
			mmi.visibility_range_end = TREE_FADE.y + FADE_REACH
			mmi.set_meta("dither", true)
		elif k == "structure" or k == "tree" or k == "built":
			mmi.visibility_range_end = FAR_RANGE
			# A small lamp or candle stand casts no shadow of its own (its own light sits
			# inside it, and would throw its arms across the room).
			var bd := BuildCatalog.def(BuildCatalog.id_of(mt.get_slice("#", 0))) if k == "built" else {}
			if bd.get("decor", false) and bd.has("light"):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_set_range(mmi, 260.0)
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if k == "tree" and RealTree.handles(mt.get_slice("#", 0)):
			mmi.set_meta("dither", true)
		add_child(mmi)
		_mm[t] = mmi
	_sync_doors()
	_sync_power()

## A DoorNode for every door still standing, none for those taken down.
func _sync_doors() -> void:
	var have := {}
	for o in data["objects"]:
		if o["st"].get("gone", false) or not Doors.is_door(o["t"]):
			continue
		var i: int = o["i"]
		have[i] = true
		if not _doors.has(i):
			var dn := DoorNode.new()
			dn.setup(self, o)
			add_child(dn)
			dn.set_near(near)
			_doors[i] = dn
	for i in _doors.keys():
		if not have.has(i):
			_doors[i].queue_free()
			_doors.erase(i)

## A PowerNode for every powered piece still standing, none for those taken down.
func _sync_power() -> void:
	var have := {}
	for o in data["objects"]:
		if o["st"].get("gone", false) or not Power.is_power(o["t"]):
			continue
		var i: int = o["i"]
		have[i] = true
		if not _power.has(i):
			var pn := PowerNode.new()
			pn.setup(self, o)
			add_child(pn)
			_power[i] = pn
	for i in _power.keys():
		if not have.has(i):
			_power[i].queue_free()
			_power.erase(i)

## The PowerNode of object i, or null.
func power_node(i: int) -> PowerNode:
	return _power.get(i)

## A door's state changed (opened, shut, locked): move it and save the chunk.
func door_changed(i: int) -> void:
	if _doors.has(i):
		_doors[i].refresh()
	Game.mark_chunk_dirty(data)

## The chunk's distant trees as one mesh (see build_object_buffers), drawn from where the
## near multimeshes stop.
func _add_far_mesh(surfs: Dictionary) -> void:
	if _mm.has("~far"):
		_mm["~far"].queue_free()
		_mm.erase("~far")
	if surfs.is_empty():
		return
	var m := ArrayMesh.new()
	for sk in surfs:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfs[sk])
		var kind := String(sk).get_slice(":", 1)
		m.surface_set_material(m.get_surface_count() - 1, RealTree.bark_material(kind, true) if String(sk).begins_with("bark") else RealTree.leaf_material(kind, true))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "TreesFar"
	mi.set_instance_shader_parameter("lod_band", Vector3(TREE_FADE.x, TREE_FADE.y, -1.0))
	mi.visibility_range_begin = maxf(TREE_FADE.x - FADE_REACH, 0.0)
	mi.visibility_range_end = FAR_RANGE
	mi.set_meta("dither", true)
	add_child(mi)
	_mm["~far"] = mi
	_apply_appear()

## Furniture inside rooms (drawn only when you could see in) and their lamplit windows
## (only from further off), one node per room: a visibility range measures from the
## middle of what it draws, and a multimesh's middle is somewhere in the chunk, so the
## furniture of a house far from it faded out while you stood inside.
func _add_rooms(t: String, buf: PackedFloat32Array) -> void:
	var holder := Node3D.new()
	holder.name = "Rooms_" + t.replace("#", "_").replace("~", "_")
	var mesh := ObjectLibrary.get_mesh(t)
	for i in buf.size() / 16:
		var o := i * 16
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
			Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if t.ends_with("~in"):
			mi.visibility_range_end = 60.0
			var rt := t.trim_suffix("~in")
			if Interiors.glows(rt) or rt == "hab_dome":
				# Its screens carry the site's name in their headers (ScreenLook).
				ScreenLook.set_title(mi, Lore.site_name(rt, position + mi.transform.origin))
		else:
			mi.visibility_range_begin = 52.0
			mi.visibility_range_begin_margin = 8.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.visibility_range_end = 900.0
		holder.add_child(mi)
	add_child(holder)
	_mm[t] = holder

## Grass instance buffers from build_grass_buffers ({} clears the grass and clutter).
func set_grass(bufs: Dictionary) -> void:
	for g in _grass:
		g.queue_free()
	_grass.clear()
	if bufs.is_empty():
		set_clutter({})
		return
	for key in bufs:
		var buf: PackedFloat32Array = bufs[key]
		var sp: String = key.get_slice("@", 0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var aqua := AquaKit.is_aqua(sp)
		mm.mesh = AquaKit.mesh(sp) if aqua else GrassKit.mesh(sp)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = AquaKit.get_material() if aqua else grass_material
		# Reefs and kelp are big enough to shade the sand under them.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sp == "aq_kelp" or sp == "aq_coral_table" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A quarter's middle can be 23 m from its corner (aquatic clumps span the whole
		# chunk: 46 m); the shader thins it out before.
		_set_range(mmi, AquaKit.range_of(sp).y + 46.0 if aqua else GrassKit.range_of(sp).y + 24.0)
		mmi.name = "Grass_" + key.replace("@", "_")
		mmi.layers = Weather.LOW_LAYER # rain falls through it (Weather's rain catch skips it)
		add_child(mmi)
		_grass.append(mmi)

func set_clutter(buffers: Dictionary) -> void:
	for c in _clutter:
		c.queue_free()
	_clutter.clear()
	_stones = buffers.get("~stones", PackedFloat32Array())
	_add_stone_shapes()
	for t in buffers:
		var buf: PackedFloat32Array = buffers[t]
		if buf.is_empty() or t.begins_with("~"):
			continue
		if t.begins_with("stone:"):
			_clutter.append(_add_stones(t, buf))
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ObjectLibrary.get_mesh(t)
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta("key", t)
		# Kept on the CPU: reading transforms back from the renderer stalls (and headless
		# servers have none to give).
		mmi.set_meta("buf", buf)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_range(mmi, 110.0 if t.begins_with("under") else 70.0)
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.visibility_range_end_margin = 10.0
		mmi.layers = Weather.LOW_LAYER
		add_child(mmi)
		_clutter.append(mmi)

## Draw distances of stones by size.
const STONE_RANGE := {"pebble": 60.0, "stone_a": 95.0, "stone_b": 95.0, "rock_a": 170.0, "rock_b": 170.0}

func _add_stones(t: String, buf: PackedFloat32Array, reach := 0.0, label := "Stones_") -> MultiMeshInstance3D:
	var kind := t.substr(6).get_slice("@", 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = StoneKit.mesh(kind)
	mm.instance_count = buf.size() / 16
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = label + t.substr(6).replace("@", "_")
	mmi.set_meta("key", t)
	# Only the big ones are worth their shadow.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind.begins_with("rock") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_range(mmi, reach if reach > 0.0 else STONE_RANGE.get(kind, 90.0))
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return mmi

## Crags from build_crag_buffers ({} clears them), drawn well out: a cliff is seen from
## far off.
func set_crags(bufs: Dictionary) -> void:
	for c in _crags:
		c.queue_free()
	_crags.clear()
	_crag_solid = bufs.get("~crags", PackedFloat32Array())
	for t in bufs:
		if not t.begins_with("~"):
			_crags.append(_add_stones(t, bufs[t], CRAG_RANGE, "Crags_"))
	_add_stone_shapes()

const CRAG_RANGE := 420.0

## Colliders for the stones big enough to stand on, while the chunk is near.
func _add_stone_shapes() -> void:
	if _stone_body != null:
		_stone_body.queue_free()
		_stone_body = null
	if not near or (_stones.is_empty() and _crag_solid.is_empty()):
		return
	_stone_body = StaticBody3D.new()
	_stone_body.name = "Stones"
	_stone_body.collision_layer = 1
	_stone_body.set_meta("stones", true)
	for st: PackedFloat32Array in [_stones, _crag_solid]:
		for i in range(0, st.size(), 13):
			var kind: String = StoneKit.KINDS[int(st[i])]
			var b := Basis(Vector3(st[i + 1], st[i + 5], st[i + 9]), Vector3(st[i + 2], st[i + 6], st[i + 10]),
				Vector3(st[i + 3], st[i + 7], st[i + 11]))
			# The kind's shared hull, turned and squashed (scaled_local: no shear, which Jolt
			# can scale exactly).
			var cs := CollisionShape3D.new()
			cs.shape = StoneKit.shape(kind)
			cs.transform = Transform3D(b, Vector3(st[i + 4], st[i + 8], st[i + 12]))
			_stone_body.add_child(cs)
	add_child(_stone_body)

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
	return not _grass.is_empty()

## The streamer has grown this chunk's grass (which may be none at all, on rock or water).
var grass_built := false

# --- Fading in and out --------------------------------------------------------------

## How much of the chunk is drawn: it fades up from 0 when it loads out where you can see
## it, and back down when it is let go (`going`), then frees itself. The distant land
## draws the rest (FarLand's mask carries the same share), so the two cross-fade.
var appear := 1.0
var going := false
const FADE_TIME := 0.8

func fade_in() -> void:
	going = false
	if appear >= 1.0:
		appear = 0.0
	_apply_appear()
	set_process(true)

func fade_out() -> void:
	going = true
	set_process(true)

## Back from going (you turned round before it was gone).
func come_back() -> void:
	going = false
	set_process(true)

func _ready() -> void:
	set_process(appear < 1.0 or going or _old_terrain != null)

func _process(delta: float) -> void:
	if going:
		appear = maxf(appear - delta / FADE_TIME, 0.0)
		if appear <= 0.0:
			queue_free()
			return
	elif appear < 1.0:
		appear = minf(appear + delta / FADE_TIME, 1.0)
	if _old_terrain != null:
		_swap_t = minf(_swap_t + delta / FADE_TIME, 1.0)
		var a := share(_swap_t)
		_terrain.set_instance_shader_parameter("appear", a)
		_old_terrain.set_instance_shader_parameter("appear", -1.0 - a)
		if _swap_t >= 1.0:
			_old_terrain.queue_free()
			_old_terrain = null
	_apply_appear()
	if appear >= 1.0 and not going and _old_terrain == null:
		set_process(false)

## A share as the shaders and FarLand's 8-bit mask both see it, so they meet exactly.
static func share(a: float) -> float:
	return roundf(clampf(a, 0.0, 1.0) * 255.0) / 255.0

## Terrain and trees dissolve (lod_fade.gdshaderinc); the rest, whatever its material,
## fades through its transparency.
func _apply_appear() -> void:
	var a := share(appear)
	for c in get_children():
		if not c is GeometryInstance3D or c == _old_terrain:
			continue
		if c == _terrain or c.has_meta("dither"):
			if c != _terrain or _old_terrain == null:
				c.set_instance_shader_parameter("appear", a)
		else:
			c.transparency = 1.0 - a

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
		_add_cave_shape()
		for o in data["objects"]:
			if not o["st"].get("gone", false):
				_add_obj_body(o)
		_add_stone_shapes()
		for i in _doors:
			_doors[i].set_near(true)
	else:
		_add_stone_shapes()
		if _body:
			_body.queue_free()
		_body = null
		_height_shape = null
		_cave_shape = null
		for i in _obj_bodies:
			_obj_bodies[i].queue_free()
		_obj_bodies.clear()
		for i in _doors:
			_doors[i].set_near(false)

func _update_height_shape() -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = RES
	hm.map_depth = RES
	var hs: PackedFloat32Array = data["heights"]
	if data.has("hole"):
		# Jolt leaves out every cell touching a NaN height: the mouth is open to walk in.
		hs = hs.duplicate()
		var hb: PackedByteArray = data["hole"]
		for k in hb.size():
			if hb[k] != 0:
				hs[k] = NAN
	hm.map_data = hs
	_height_shape.shape = hm
	_height_shape.position = Vector3(SIZE * 0.5, 0, SIZE * 0.5)

func _add_obj_body(o: Dictionary) -> void:
	if Doors.is_door(o["t"]):
		return # its DoorNode has its own, moving with the leaves
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
	# A hearth, lamps or screens light the room inside; crystals light a cave.
	for l in Interiors.lights(o["t"]) + Caves.lights(o):
		# A hearth's light wavers with its fire.
		var hl: OmniLight3D = FlickerLight.new() if KitHouse.has(o["t"]) else OmniLight3D.new()
		hl.light_color = l[1]
		hl.light_energy = l[2]
		hl.omni_range = l[3]
		hl.omni_attenuation = 1.4
		# A hearth's fire bed is broad, a lamp's flame small.
		_cast_shadows(hl, 0.3 if KitHouse.has(o["t"]) else 0.1, false)
		hl.distance_fade_enabled = true
		hl.distance_fade_begin = 40.0
		hl.distance_fade_length = 15.0
		hl.position = l[0]
		b.add_child(hl)
	var beams := SunBeams.node(o["t"])
	if beams != null:
		b.add_child(beams)
	for w in Interiors.sun_windows(o["t"]):
		b.add_child(WindowLight.make(w[0], w[1]))
	for f in Interiors.fires(o["t"]):
		# Indoors only a draught stirs them.
		var fl := FireFx.flame(f[1], Color(1, 1, 1, 1), "fire", false, 0.12)
		fl.position = f[0]
		if f[1] >= 0.3:
			# Sparks fly from a hearth or a wall torch; the smoke goes up the chimney.
			fl.add_child(FireFx.embers(f[1], false))
		b.add_child(fl)
	if o["t"] == WorldPortal.TYPE:
		# The door of light, just proud of the glowing disc on both faces.
		for z in [-0.05, 0.05]:
			var sw := FireFx.swirl(WorldPortal.DOOR * 2.0)
			sw.position = Vector3(0, WorldPortal.DOOR_Y, z)
			b.add_child(sw)
	if built:
		var bd := BuildCatalog.def(BuildCatalog.id_of(o["t"]))
		if bd.has("fire"):
			var cf := FireFx.flame(float(bd["fire"]))
			cf.add_child(FireFx.embers(float(bd["fire"])))
			b.add_child(cf)
		# A candle stand you build burns at its wicks, a lantern behind its glass.
		var flames := FireFx.prop_flames(bd.get("models", []))
		var wicks := Vector3.ZERO
		for f in flames:
			b.add_child(FireFx.prop_flame(f))
			wicks += (f[0] as Vector3) + Vector3(0, float(f[1]) * 0.6, 0)
		var lc = bd.get("light")
		if lc != null:
			# Firelight wavers with its flame and shines from it.
			var l: OmniLight3D = FlickerLight.new() if bd.has("fire") or not flames.is_empty() else OmniLight3D.new()
			l.light_color = lc
			l.light_energy = 1.6
			l.omni_range = 7.0
			# The light is where the flames are: from lower down the stand's own arms threw
			# black blots over the ceiling.
			l.position = wicks / flames.size() if not flames.is_empty() else Vector3(0, 1.0, 0)
			# Several candles light from a spread, not a point: the arms' shadows on the
			# ceiling blur into a soft dapple instead of hard black blots.
			var spread := 0.0
			for f in flames:
				spread = maxf(spread, ((f[0] as Vector3) - l.position).length())
			_cast_shadows(l, clampf(spread * 1.5 + 0.03, 0.04, 0.45), false)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 40.0
			l.distance_fade_length = 15.0
			b.add_child(l)
			# Light thrown back off the walls and ceiling, so the side of a room away from
			# the lamp is dim rather than black.
			var fill := OmniLight3D.new()
			fill.light_color = (lc as Color).lerp(Color(1.0, 0.9, 0.8), 0.4)
			fill.light_energy = 0.35
			fill.omni_range = 7.5
			fill.omni_attenuation = 0.8
			fill.light_specular = 0.0
			fill.shadow_enabled = false
			fill.distance_fade_enabled = true
			fill.distance_fade_begin = 30.0
			fill.distance_fade_length = 10.0
			fill.position = l.position
			b.add_child(fill)
	var settled = PropSettle.transform(data, o)
	if settled != null:
		b.transform = settled # collides where it is drawn, lying with the ground
	else:
		b.position = o["p"]
		b.rotation.y = o["r"]
		var s: float = o["s"]
		b.scale = Vector3(s, s, s)
	add_child(b)
	_obj_bodies[o["i"]] = b

## Room lights, fires and lamps cast shadows near you: furniture and beams throw them, and
## the light stays inside its walls instead of shining out through them.
## `size` is the flame's (or fire's) breadth in metres: shadows soften with distance from
## what casts them, as under a real flame.
## `movers`: whether people and animals further off (Movers) are lit by it too. Indoors
## they are walled off anyway, and leaving them out spares re-rendering its shadows
## every time someone walks by.
static func _cast_shadows(l: OmniLight3D, size := 0.12, movers := true) -> void:
	l.shadow_enabled = true
	if not movers:
		# Your own first-person body (Player.SELF_LAYER) neither: its idling is a move.
		l.light_cull_mask = 0xFFFFF & ~(Movers.LAYER | Player.SELF_LAYER)
	l.light_size = size
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.2
	l.shadow_blur = 1.5
	l.distance_fade_shadow = 24.0

## Adds something the player built. It becomes an ordinary object of this chunk, saved
## in its snapshot. `lp` is the chunk-local position.
func add_built(id: String, lp: Vector3, yaw: float, st: Dictionary) -> Dictionary:
	return add_object(BuildCatalog.PREFIX + id, lp, yaw, int(BuildCatalog.def(id).get("era", -1)), st)

## Adds an object at local point lp after generation (a piece you built, a supply pod a
## beacon called down) and keeps it in the snapshot.
## `more` sets other fields of the record (a species "sp", a variant "v", a scale "s").
func add_object(t: String, lp: Vector3, yaw: float, era: int, st: Dictionary, more := {}) -> Dictionary:
	var o := {"i": data["objects"].size(), "t": t, "p": lp, "r": yaw, "s": 1.0, "e": era, "st": st}
	o.merge(more, true)
	data["objects"].append(o)
	set_objects(build_object_buffers(data, false), true)
	refresh_far()
	if near:
		_add_obj_body(o)
	_regrow_if_kept_out(t)
	Game.mark_chunk_dirty(data)
	if Power.is_power(t) or Automation.is_container(t):
		PowerGrid.changed(self)
	if BuildCatalog.is_built(t):
		TownLife.note_built(Vector2(key.x * ChunkGenerator.SIZE + lp.x, key.y * ChunkGenerator.SIZE + lp.z))
	return o

## Regrows the grass after something that keeps it out (a floor, a house) came or went,
## so none grows through a floor and the ground under a dismantled one greens again.
func _regrow_if_kept_out(t: String) -> void:
	var s := get_parent() as ChunkStreamer
	if s != null and ObjectLibrary.keeps_out(t):
		s.refresh_grass(key)

func get_object(i: int) -> Dictionary:
	return data["objects"][i]

## Permanently removes an object (felled, mined out). Its record stays with gone=true.
func remove_object(i: int) -> void:
	var o: Dictionary = data["objects"][i]
	o["st"]["gone"] = true
	if _obj_bodies.has(i):
		_obj_bodies[i].queue_free()
		_obj_bodies.erase(i)
	set_objects(build_object_buffers(data, false), true)
	if ObjectLibrary.kind(o["t"]) == "tree":
		refresh_far()
	_regrow_if_kept_out(o["t"])
	Game.mark_chunk_dirty(data)
	if Power.is_power(o["t"]) or Automation.is_container(o["t"]):
		PowerGrid.changed(self)
	if BuildCatalog.is_built(o["t"]):
		var lp: Vector3 = o["p"]
		TownLife.note_built(Vector2(key.x * ChunkGenerator.SIZE + lp.x, key.y * ChunkGenerator.SIZE + lp.z))
	if ObjectLibrary.kind(o["t"]) == "ore":
		Game.map.note_chunk(data) # the atlas forgets a mined-out vein

## Rebuilds the far tree mesh on a worker thread after a tree was felled or something
## built: merging every tree of the chunk is too slow to do in the frame you swing the axe,
## and the far mesh is out of sight while you stand that close anyway.
func refresh_far() -> void:
	var snap := data.duplicate(false)
	snap["objects"] = (data["objects"] as Array).duplicate()
	var me: WeakRef = weakref(self)
	_wait_far()
	_far_task = WorkerThreadPool.add_task(func():
		var surfs: Dictionary = build_object_buffers(snap).get("~far", {})
		var apply := func():
			var n = me.get_ref()
			if n != null and is_instance_valid(n) and n.is_inside_tree():
				n._add_far_mesh(surfs)
		apply.call_deferred())

var _far_task := -1

func _wait_far() -> void:
	if _far_task != -1:
		WorkerThreadPool.wait_for_task_completion(_far_task)
		_far_task = -1

func _exit_tree() -> void:
	# Never leave a merge running against a chunk that is going away (or a closing game).
	_wait_far()

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
