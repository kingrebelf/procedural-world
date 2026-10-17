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
var _body: StaticBody3D
var _height_shape: CollisionShape3D
var _mm: Dictionary = {} ## type -> MultiMeshInstance3D (or a node of rooms, _add_rooms)
var _obj_bodies: Dictionary = {} ## object index -> StaticBody3D
var _doors: Dictionary = {} ## object index -> DoorNode (doors move, so they aren't in a MultiMesh)
var _grass: Array = [] ## MultiMeshInstance3D per grass species and quarter
var _clutter: Array = []
var _stones := PackedFloat32Array() ## stones to stand on (see _scatter_stones)
var _stone_body: StaticBody3D
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
		grass_material = ShaderMaterial.new()
		grass_material.shader = load("res://src/world/grass.gdshader")
		grass_material.set_shader_parameter("detail", detail_mult)
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
			# There blue is only how paved the road is (the tech era's streets and roads).
			var rd := rb[k] / 255.0 if not rb.is_empty() else 0.0
			var ws := wb[wk + 2] / 255.0 * (1.0 if rd > 0.0 else 0.0) if human else wb[wk + 2] / 255.0
			# Village paths, gardens and fields wear the ground bare too (never paved).
			if not worn.is_empty():
				rd = maxf(rd, worn[k] / 255.0)
			cols[v] = Color((wb[wk] + (wb[wk + 2] if human else 0)) / 255.0, wb[wk + 1] / 255.0, ws, 1.0 - rd)
			if has_look:
				_look_at(lb, gi, gj, l0, l1, l2, v * 4)
			for b in 4:
				cv[v * 4 + b] = cover[k * 4 + b]
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
		_add_skirts(n, verts, norms, cols, idx, 3.0 * step)
		if has_look:
			_skirt_looks(n, l0, l1, l2)
		_skirt_looks(n, cv, PackedByteArray(), PackedByteArray())
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
	arr[Mesh.ARRAY_CUSTOM3] = cv
	return arr

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
## Trees drawn by RealTree switch to the merged far mesh beyond this distance (from the
## middle of the chunk).
const TREE_NEAR := 320.0

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
		var p: Vector3 = o["p"]
		# Sink slightly so bases never float on slopes.
		if not built and not EasterEggs.floats(o["t"]):
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
			# Moss on its top (StoneKit's material reads alpha): in green lands, not on sand.
			var w := Eras.look(ChunkGenerator.weights_at(chunk, p.x, p.z))
			tint.a = w[Eras.MEDIEVAL] * lerpf(0.2, 0.9, u2) * ChunkGenerator.cover_at(chunk, p.x, p.z)
		var row := [b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a]
		if far and real:
			_add_far(far_bufs, RealTree.far_parts(o["t"], int(o["sp"]), int(o.get("v", 0))), Transform3D(b, p), tint)
		var buf: PackedFloat32Array = by_key[key]
		buf.append_array(row)
		by_key[key] = buf
		# A room you can walk into brings its furniture (drawn up close) and any lamplit
		# windows (from further off) as their own meshes.
		var rk := key.get_slice(Stronghold.VAR, 0) # a castle tower's build shares its rooms
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

## Appends one tree's far parts, moved by `xf` and tinted, to the chunk's far buffers.
static func _add_far(bufs: Dictionary, parts: Dictionary, xf: Transform3D, tint: Color) -> void:
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
		for j in pv.size():
			vs.append(xf * pv[j])
			ns.append(nb * pn[j])
			cs.append(pc[j] * tint)
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		for q in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
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
	for n in count:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var yaw := r.randf() * TAU
		var pick := r.randf()
		var roll := r.randf()
		var size := r.randf()
		var w := Eras.look(ChunkGenerator.weights_at(chunk, lx, lz))
		var dens := w[0] * Eras.GRASS_DENSITY[0] + w[1] * Eras.GRASS_DENSITY[1] + w[2] * Eras.GRASS_DENSITY[2]
		if pick > dens:
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.55:
			continue
		if pick > dens * ChunkGenerator.cover_at(chunk, lx, lz):
			continue
		# Grass gives way to snow, stones and gravel, and thins under the trees.
		var cv := GroundCover.at(cover, lx, lz)
		if roll < cv.a * 1.5 or roll < cv.r * 0.92 or roll < cv.g * 0.95 or roll < cv.b * 0.55:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		# Clumps with gaps of shorter ground between them (narrow ones: wide bare gaps made
		# a meadow look like a lawn with tufts on it).
		if roll > smoothstep(-0.8, 0.0, clump.get_noise_2d(wx, wz)):
			continue
		if ChunkGenerator.kept_out(plans, lx, lz, 0.2):
			continue
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y < 0.15 or ChunkGenerator.under_river(chunk, lx, lz):
			continue
		var on_road := maxf(ChunkGenerator.road_at(chunk, lx, lz), TownLife.wear_at(chunk, lx, lz))
		if on_road > 0.5 or (on_road > 0.0 and r.randf() < on_road * 1.6):
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
		var sc := lerpf(0.7, 1.4, size)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * rw.randf_range(0.8, 1.3), sc))
		var tint := Color(0.34, 0.46, 0.15) * w[0] + Color(0.14, 0.46, 0.38) * w[1] + Color(0.4, 0.36, 0.2) * w[2]
		tint = tint.lerp(Color(0.46, 0.4, 0.17), rw.randf() * 0.35)
		var key := "weed@%d" % [(1 if lx >= SIZE * 0.5 else 0) + (2 if lz >= SIZE * 0.5 else 0)]
		var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
		buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
			tint.r, tint.g, tint.b, -1.0])
		out[key] = buf
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
			if y < 0.3 or ChunkGenerator.under_river(chunk, lx, lz) or Flora.was_cleared(chunk, lx, lz) or ChunkGenerator.road_at(chunk, lx, lz) > 0.05 or ChunkGenerator.in_cave(chunk, lx, lz) or ChunkGenerator.kept_out(plans, lx, lz, 0.5):
				continue
			var key := "under#%d#%d" % [unders[pick % unders.size()], era]
			if not out.has(key):
				out[key] = PackedFloat32Array()
			var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
			var buf: PackedFloat32Array = out[key]
			buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz])
			out[key] = buf
	return out

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
	for n in int(28000 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var cv := GroundCover.at(cover, lx, lz)
		var stony := maxf(cv.r, cv.g)
		if r.randf() > 0.012 + stony * stony * 0.9 or cv.a > 0.6:
			continue
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
			size = 0.05 + 0.4 * pow(a, 4.0)
		var kind := "pebble"
		if size >= 0.5:
			kind = "rock_a" if r.randf() < 0.5 else "rock_b"
		elif size >= 0.16:
			kind = "stone_b" if gravelly or r.randf() < 0.3 else "stone_a"
		var flat := r.randf_range(0.5, 0.95) if not gravelly else r.randf_range(0.6, 1.0)
		# Lying on the slope, turned and tipped a little, partly sunk.
		var nrm := Vector3(ChunkGenerator.height_at(chunk, lx - 0.5, lz) - ChunkGenerator.height_at(chunk, lx + 0.5, lz), 1.0,
			ChunkGenerator.height_at(chunk, lx, lz - 0.5) - ChunkGenerator.height_at(chunk, lx, lz + 0.5)).normalized()
		var b := Basis(Quaternion(Vector3.UP, nrm)) * Basis(Vector3.UP, r.randf() * TAU) * Basis.from_euler(Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2)))
		b = b.scaled_local(Vector3(size, size * flat, size))
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
	if not solid.is_empty():
		out["~stones"] = solid

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
		if k == "tree" and RealTree.handles(t.get_slice("#", 0)) and buffers.has("~far"):
			# Up close only; the merged far mesh takes over beyond.
			mmi.visibility_range_end = TREE_NEAR
			mmi.visibility_range_end_margin = 12.0
		elif k == "structure" or k == "tree" or k == "built":
			mmi.visibility_range_end = 900.0
		else:
			_set_range(mmi, 260.0)
		add_child(mmi)
		_mm[t] = mmi
	_sync_doors()

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
		m.surface_set_material(m.get_surface_count() - 1, RealTree.bark_material(kind) if String(sk).begins_with("bark") else RealTree.leaf_material(kind))
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = "TreesFar"
	mi.visibility_range_begin = TREE_NEAR
	mi.visibility_range_begin_margin = 12.0
	mi.visibility_range_end = 900.0
	add_child(mi)
	_mm["~far"] = mi

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
		mm.mesh = GrassKit.mesh(sp)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = grass_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A quarter's middle can be 23 m from its corner; the shader thins it out before.
		_set_range(mmi, GrassKit.range_of(sp).y + 24.0)
		mmi.name = "Grass_" + key.replace("@", "_")
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
			_add_stones(t, buf)
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
		add_child(mmi)
		_clutter.append(mmi)

## Draw distances of stones by size.
const STONE_RANGE := {"pebble": 60.0, "stone_a": 95.0, "stone_b": 95.0, "rock_a": 170.0, "rock_b": 170.0}

func _add_stones(t: String, buf: PackedFloat32Array) -> void:
	var kind := t.substr(6).get_slice("@", 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = StoneKit.mesh(kind)
	mm.instance_count = buf.size() / 16
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Stones_" + t.substr(6).replace("@", "_")
	mmi.set_meta("key", t)
	# Only the big ones are worth their shadow.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind.begins_with("rock") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_range(mmi, STONE_RANGE.get(kind, 90.0))
	mmi.visibility_range_end_margin = 10.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	_clutter.append(mmi)

## Colliders for the stones big enough to stand on, while the chunk is near.
func _add_stone_shapes() -> void:
	if _stone_body != null:
		_stone_body.queue_free()
		_stone_body = null
	if not near or _stones.is_empty():
		return
	_stone_body = StaticBody3D.new()
	_stone_body.name = "Stones"
	_stone_body.collision_layer = 1
	_stone_body.set_meta("stones", true)
	for i in range(0, _stones.size(), 13):
		var kind: String = StoneKit.KINDS[int(_stones[i])]
		var b := Basis(Vector3(_stones[i + 1], _stones[i + 5], _stones[i + 9]), Vector3(_stones[i + 2], _stones[i + 6], _stones[i + 10]),
			Vector3(_stones[i + 3], _stones[i + 7], _stones[i + 11]))
		# Hull points baked with the stone's own (squashed) scale: scaled collision shapes
		# are best kept uniform.
		var pts := PackedVector3Array()
		for v in StoneKit.hull(kind):
			pts.append(b * v)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(_stones[i + 4], _stones[i + 8], _stones[i + 12])
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
		_cast_shadows(hl)
		hl.distance_fade_enabled = true
		hl.distance_fade_begin = 40.0
		hl.distance_fade_length = 15.0
		hl.position = l[0]
		b.add_child(hl)
	var beams := SunBeams.node(o["t"])
	if beams != null:
		b.add_child(beams)
	for f in Interiors.fires(o["t"]):
		var fl := FireFx.flame(f[1])
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
		# A candle stand you build burns at its wicks.
		for f in FireFx.prop_flames(bd.get("models", [])):
			var pf := FireFx.flame(f[1])
			pf.position = f[0]
			b.add_child(pf)
		var lc = bd.get("light")
		if lc != null:
			var l: OmniLight3D = FlickerLight.new() if bd.has("fire") else OmniLight3D.new()
			l.light_color = lc
			l.light_energy = 1.6
			l.omni_range = 7.0
			l.position = Vector3(0, 1.0, 0)
			_cast_shadows(l)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 40.0
			l.distance_fade_length = 15.0
			b.add_child(l)
	b.position = o["p"]
	b.rotation.y = o["r"]
	var s: float = o["s"]
	b.scale = Vector3(s, s, s)
	add_child(b)
	_obj_bodies[o["i"]] = b

## Room lights, fires and lamps cast shadows near you: furniture and beams throw them, and
## the light stays inside its walls instead of shining out through them.
static func _cast_shadows(l: OmniLight3D) -> void:
	l.shadow_enabled = true
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
func add_object(t: String, lp: Vector3, yaw: float, era: int, st: Dictionary) -> Dictionary:
	var o := {"i": data["objects"].size(), "t": t, "p": lp, "r": yaw, "s": 1.0, "e": era, "st": st}
	data["objects"].append(o)
	set_objects(build_object_buffers(data, false), true)
	refresh_far()
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
	set_objects(build_object_buffers(data, false), true)
	if ObjectLibrary.kind(o["t"]) == "tree":
		refresh_far()
	Game.mark_chunk_dirty(data)
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
