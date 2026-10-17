class_name AnimalSkin
## Makes the low-poly kit animals (AnimalModel) look alive. Their meshes are welded and
## smoothed (two rounds of Loop subdivision over the coat, horns, hooves and eyes kept
## crisp), muscle laid on the bones (shoulders, forearms, haunches, gaskins, neck and
## chest), and the flat colours swapped for the fur shader (fur.gdshader): hair in
## strands and locks with a sheen, bare muzzles, ridged horn, glossy eyes, and markings
## that differ from one animal to the next (patches, dapples, socks, a blaze, a darker
## back or a paler belly) from each animal's seed. The coarser subdivision levels are
## kept as mesh LODs, so far animals cost about what they did before. Meshes are built
## once per kit model, on a worker thread when warm() has been called.

const SHADER := "res://src/fauna/shaders/fur.gdshader"
enum { FUR, HAIR, SKIN, HORN, EYE }
const LEVELS := 2
## The name of the hanging-lock surfaces refine() adds to manes and tails.
const LOCKS := "locks"
const LOCK_SHADER := "res://src/fauna/shaders/hair_lock.gdshader"

## Per-kind look: hair spacing and lock size (metres), how much the hair shows, muscle,
## where the legs meet the body and the back's top (0..1 of the height), and the chances
## and colours of each marking. Missing keys take the defaults in fur.gdshader.
const LOOKS := {
	"Deer": {"vary": 0.24, "strand": 0.003, "clump": 0.016, "fur": 0.8, "muscle": 1.0, "legs_y": 0.42, "back_y": 0.62,
		"belly": 0.4, "dorsal": 0.2, "spots": 0.25, "spot_col": Color(0.82, 0.74, 0.62), "spot_size": 0.035},
	"Stag": {"vary": 0.24, "strand": 0.0035, "clump": 0.02, "fur": 0.85, "muscle": 1.2, "legs_y": 0.42, "back_y": 0.6,
		"belly": 0.4, "dorsal": 0.25},
	"Cow": {"vary": 0.18, "strand": 0.003, "clump": 0.024, "fur": 0.55, "muscle": 0.6, "legs_y": 0.36, "back_y": 0.66,
		"belly": 0.15, "dorsal": 0.08, "patches": 0.55, "patch_col": Color(0.74, 0.72, 0.67), "socks": 0.3, "sock_col": Color(0.68, 0.65, 0.6), "blaze": 0.35},
	"Bull": {"vary": 0.22, "strand": 0.003, "clump": 0.022, "fur": 0.55, "muscle": 1.4, "legs_y": 0.34, "back_y": 0.7,
		"belly": 0.08, "dorsal": 0.1, "patches": 0.2, "patch_col": Color(0.3, 0.2, 0.12), "blaze": 0.2},
	"Horse": {"vary": 0.2, "dapple": 0.35, "strand": 0.002, "clump": 0.014, "fur": 0.45, "muscle": 1.3, "legs_y": 0.42, "back_y": 0.66,
		"belly": 0.1, "dorsal": 0.1, "socks": 0.45, "sock_col": Color(0.66, 0.63, 0.58), "blaze": 0.5, "spots": 0.15, "spot_col": Color(0.5, 0.36, 0.24), "spot_size": 0.06},
	"Horse_White": {"strand": 0.002, "clump": 0.014, "fur": 0.45, "muscle": 1.3, "legs_y": 0.42, "back_y": 0.66,
		"belly": 0.05, "dorsal": 0.05, "spots": 0.7, "spot_col": Color(0.3, 0.3, 0.3), "spot_size": 0.07},
	"Donkey": {"vary": 0.18, "strand": 0.003, "clump": 0.02, "fur": 0.75, "muscle": 0.8, "legs_y": 0.4, "back_y": 0.66,
		"belly": 0.5, "dorsal": 0.1, "stripe": 0.7, "socks": 0.15, "sock_col": Color(0.12, 0.1, 0.09)},
	"Alpaca": {"vary": 0.24, "strand": 0.006, "clump": 0.045, "fur": 1.4, "coarse": 0.3, "muscle": 0.15, "legs_y": 0.32, "back_y": 0.52,
		"belly": 0.15, "dorsal": 0.0, "patches": 0.35, "patch_col": Color(0.86, 0.82, 0.74)},
	"Wolf": {"vary": 0.32, "strand": 0.004, "clump": 0.022, "fur": 1.15, "muscle": 0.6, "legs_y": 0.4, "back_y": 0.68,
		"belly": 0.35, "dorsal": 0.5, "stripe": 0.25, "grizzle": 0.7, "phases": 0.6},
	"Fox": {"vary": 0.24, "strand": 0.003, "clump": 0.016, "fur": 1.0, "muscle": 0.4, "legs_y": 0.34, "back_y": 0.62,
		"belly": 0.25, "dorsal": 0.15, "grizzle": 0.25},
	"Husky": {"phases": 0.4, "strand": 0.004, "clump": 0.022, "fur": 1.15, "muscle": 0.4, "legs_y": 0.38, "back_y": 0.66,
		"belly": 0.1, "dorsal": 0.15, "grizzle": 0.3, "socks": 0.2},
	"ShibaInu": {"strand": 0.0035, "clump": 0.018, "fur": 1.05, "muscle": 0.3, "legs_y": 0.38, "back_y": 0.66,
		"belly": 0.2, "dorsal": 0.12, "grizzle": 0.15},
	"Boar": {"vary": 0.24, "strand": 0.007, "clump": 0.03, "fur": 1.2, "coarse": 1.0, "muscle": 0.7, "legs_y": 0.34, "back_y": 0.74,
		"belly": 0.05, "dorsal": 0.25, "stripe": 0.35, "grizzle": 0.6},
	"Hare": {"vary": 0.2, "strand": 0.0025, "clump": 0.012, "fur": 1.0, "muscle": 0.3, "legs_y": 0.3, "back_y": 0.62,
		"belly": 0.45, "dorsal": 0.15, "grizzle": 0.8},
}

## Surfaces that are not coat, by kit model: bare skin, horn and hoof, eyes. Names not
## listed here or matched below are fur.
const ROLES := {
	"Wolf": {"Nose": SKIN},
	"Fox": {"Black": SKIN},
	"ShibaInu": {"Black": SKIN},
	"Husky": {"phases": 0.4, "Material.006": SKIN, "Material.002": EYE, "Material.003": EYE},
	"Stag": {"Material.001": HORN, "Material.010": SKIN, "Material.011": EYE},
	"Deer": {"Main_Dark": SKIN},
}

## Off draws the kits' original flat-coloured meshes (for comparisons).
static var enabled := true
static var _shader: Shader
static var _meshes := {} ## kit|mesh -> ArrayMesh
static var _pending := {} ## kit|mesh -> WorkerThreadPool task id
static var _mats := {}
static var _lock := Mutex.new()
static var _mat_lock := Mutex.new()

static func role_of(kind: String, mat_name: String) -> int:
	var r: Dictionary = ROLES.get(kind, {})
	if r.has(mat_name):
		return r[mat_name]
	if mat_name.contains("Eye"):
		return EYE
	if mat_name.contains("Hoove") or mat_name.contains("Horn"):
		return HORN
	if mat_name.contains("Muzzle") or mat_name.contains("Nose"):
		return SKIN
	if mat_name == "Hair":
		return HAIR
	return FUR

## Builds every kit model's refined meshes in the background, so the first sight of an
## animal does not stall a frame. The kit meshes are read here, on the calling thread
## (reading a mesh back from the renderer off the main thread can stall); only the
## arithmetic runs on worker threads.
static func warm(kinds: Array) -> void:
	for k in kinds:
		# Variants (a boar, a hare) share their base kit's mesh.
		if not AnimalModel.available(k) or String(k).begins_with("Alien_") or AnimalModel.VARIANTS.has(k):
			continue
		var s: Node3D = (load(AnimalModel.path_of(k)) as PackedScene).instantiate()
		var sks := s.find_children("*", "Skeleton3D", true, false)
		for mi in s.find_children("*", "MeshInstance3D", true, false):
			var src := (mi as MeshInstance3D).mesh as ArrayMesh
			var key := _key(k, src)
			_lock.lock()
			if not _meshes.has(key) and not _pending.has(key):
				var data := _snapshot(k, src, sks[0] if not sks.is_empty() else null)
				_pending[key] = WorkerThreadPool.add_task(_build.bind(key, data), false, "AnimalSkin " + key)
			_lock.unlock()
		s.free()

static func _build(key: String, data: Dictionary) -> void:
	var m := refine(data)
	_lock.lock()
	_meshes[key] = m
	_lock.unlock()

static func _key(kit: String, src: ArrayMesh) -> String:
	return "%s|%s|%d" % [kit, src.resource_name, src.get_surface_count()]

## What refine() needs from a kit mesh, read out on the calling thread.
static func _snapshot(kit: String, src: ArrayMesh, sk: Skeleton3D) -> Dictionary:
	var roles := PackedInt32Array()
	var arrays := []
	var mats := []
	var names := []
	for s in src.get_surface_count():
		var m := src.surface_get_material(s)
		roles.append(role_of(kit, String(m.resource_name) if m else ""))
		arrays.append(src.surface_get_arrays(s))
		mats.append(m)
		names.append(src.surface_get_name(s))
	var bones := {}
	if sk:
		for b in sk.get_bone_count():
			bones[sk.get_bone_name(b)] = sk.get_bone_global_rest(b).origin
	return {"name": src.resource_name, "aabb": src.get_aabb(), "arrays": arrays, "mats": mats, "names": names,
		"roles": roles, "bones": bones, "muscle": float(LOOKS.get(kit, {}).get("muscle", 0.5))}

## The refined mesh for kit model `kit` (cached; waits for warm()'s job if one runs).
static func mesh_for(kit: String, src: ArrayMesh, sk: Skeleton3D) -> ArrayMesh:
	var key := _key(kit, src)
	_lock.lock()
	var job: int = _pending.get(key, -1)
	_lock.unlock()
	if job >= 0:
		WorkerThreadPool.wait_for_task_completion(job)
		_lock.lock()
		_pending.erase(key)
		_lock.unlock()
	_lock.lock()
	if not _meshes.has(key):
		_meshes[key] = refine(_snapshot(kit, src, sk))
	var out: ArrayMesh = _meshes[key]
	_lock.unlock()
	return out

## The skin for one of the kit's surfaces. `col` is its colour (the kit's or the
## species' tint), `glow` an emission colour or null.
static func material(kind: String, mat_name: String, col: Color, glow, box: AABB, unit: float, other = null) -> ShaderMaterial:
	var kit := String(AnimalModel.VARIANTS[kind]["base"]) if AnimalModel.VARIANTS.has(kind) else kind
	var role := role_of(kit, mat_name)
	var key := "%s|%s|%s|%s|%s|%s" % [kind, mat_name, col.to_html(), glow, snappedf(unit, 0.001), other]
	_mat_lock.lock()
	if _shader == null:
		_shader = load(SHADER)
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("role", role)
		m.set_shader_parameter("base", col)
		m.set_shader_parameter("lo", box.position)
		m.set_shader_parameter("hi", box.end)
		m.set_shader_parameter("unit", unit)
		var look: Dictionary = LOOKS.get(kind, {})
		for k in look:
			if k != "muscle":
				m.set_shader_parameter(k, look[k])
		if other != null:
			m.set_shader_parameter("other", other)
			m.set_shader_parameter("blend", 1.0)
		if glow != null:
			m.set_shader_parameter("emit", glow)
			m.set_shader_parameter("emit_e", 1.6)
		_mats[key] = m
	_mat_lock.unlock()
	return m

## The hanging locks of a mane or tail (refine()'s LOCKS surfaces), in colour `col`.
static func lock_material(kind: String, col: Color) -> ShaderMaterial:
	var key := "locks|%s|%s" % [kind, col.to_html()]
	_mat_lock.lock()
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = load(LOCK_SHADER)
		m.set_shader_parameter("base", col)
		var look: Dictionary = LOOKS.get(kind, {})
		for k in ["vary", "phases"]:
			if look.has(k):
				m.set_shader_parameter(k, look[k])
		_mats[key] = m
	_mat_lock.unlock()
	return m

# --- Mesh refinement -------------------------------------------------------------

## Welds the kit mesh, smooths it with Loop subdivision (`LEVELS` rounds) where it is
## soft (fur, hair, skin), lays muscle on it, and writes each vertex's rest position
## into UV / UV2.x for the shader. The coarser rounds become the mesh's LODs.
static func refine(data: Dictionary) -> ArrayMesh:
	var aabb: AABB = data["aabb"]
	var roles: PackedInt32Array = data["roles"]
	var bones: Dictionary = data["bones"]
	var muscle: float = data["muscle"]
	var snap := maxf(aabb.get_longest_axis_size(), 0.001) * 1e-5
	var pos := PackedVector3Array()
	var bon := PackedInt32Array()
	var wei := PackedFloat32Array()
	var col := PackedColorArray()
	var tris := PackedInt32Array()
	var tsurf := PackedInt32Array()
	var weld := {}
	var sc: int = (data["arrays"] as Array).size()
	var has_col := false
	for s in sc:
		var a: Array = data["arrays"][s]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var c: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		has_col = has_col or not c.is_empty()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		var stride := b.size() / maxi(v.size(), 1)
		var remap := PackedInt32Array()
		remap.resize(v.size())
		for i in v.size():
			var k := Vector3i(roundi(v[i].x / snap), roundi(v[i].y / snap), roundi(v[i].z / snap))
			var g: int = weld.get(k, -1)
			if g < 0:
				g = pos.size()
				weld[k] = g
				pos.append(v[i])
				var tot := 0.0
				for j in 4:
					var wj := w[i * stride + j] if stride > 0 else (1.0 if j == 0 else 0.0)
					bon.append(b[i * stride + j] if stride > 0 else 0)
					wei.append(wj)
					tot += wj
				if tot > 0.0 and absf(tot - 1.0) > 1e-4:
					for j in 4:
						wei[g * 4 + j] /= tot
				col.append(c[i] if not c.is_empty() else Color.WHITE)
			remap[i] = g
		for t in range(0, idx.size() - 2, 3):
			var i0 := remap[idx[t]]
			var i1 := remap[idx[t + 1]]
			var i2 := remap[idx[t + 2]]
			if i0 == i1 or i1 == i2 or i0 == i2:
				continue
			tris.append_array([i0, i1, i2])
			tsurf.append(s)
	var soft := PackedByteArray()
	soft.resize(sc)
	var any_soft := false
	for s in sc:
		soft[s] = 1 if roles[s] <= SKIN else 0
		any_soft = any_soft or soft[s] == 1
	var levels := LEVELS if any_soft else 0
	var level_tris: Array = [tris]
	var level_n := PackedInt32Array([pos.size()])
	var parents: Array = [] # per level: PackedInt32Array of edge endpoint pairs
	for l in levels:
		var r := _subdivide(pos, bon, wei, col, tris, tsurf, soft)
		pos = r["pos"]
		bon = r["bon"]
		wei = r["wei"]
		col = r["col"]
		tris = r["tris"]
		tsurf = r["tsurf"]
		parents.append(r["par"])
		level_tris.append(tris)
		level_n.append(pos.size())
	var nrm := _normals(pos, tris)
	if muscle > 0.0 and not bones.is_empty():
		_muscles(pos, nrm, tris, tsurf, roles, bones, aabb.size.y, muscle)
		nrm = _normals(pos, tris)
	# Each coarser level's error: how far the next level's new points stand off its faces.
	var errs := PackedFloat32Array()
	for l in levels:
		var par: PackedInt32Array = parents[l]
		var sum := 0.0
		var mx := 0.0
		for e in par.size() / 2:
			var d := pos[level_n[l] + e].distance_to((pos[par[e * 2]] + pos[par[e * 2 + 1]]) * 0.5)
			sum += d
			mx = maxf(mx, d)
		errs.append(maxf(mx * 0.5 + sum / maxf(par.size() / 2.0, 1.0), 1e-5))
	# Level l's LOD shows once the levels above it would be about a pixel of change.
	var lod_err := PackedFloat32Array()
	lod_err.resize(levels)
	var acc := 0.0
	for l in range(levels - 1, -1, -1):
		acc += errs[l]
		lod_err[l] = acc
	var blend := _seams(pos, tris, tsurf, roles, aabb.size.y * 0.06)
	var out := ArrayMesh.new()
	out.resource_name = data["name"]
	out.set_meta("blend_with", blend["with"])
	for s in sc:
		var local := {}
		var lv := PackedVector3Array()
		var ln := PackedVector3Array()
		var lb := PackedInt32Array()
		var lw := PackedFloat32Array()
		var lc := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var lidx: Array = []
		for l in range(levels, -1, -1):
			var lt: PackedInt32Array = level_tris[l]
			var ls: PackedInt32Array = tsurf if l == levels else _surf_of(level_tris, l, tsurf, levels)
			var ix := PackedInt32Array()
			for t in ls.size():
				if ls[t] != s:
					continue
				for k in 3:
					var g := lt[t * 3 + k]
					var li: int = local.get(g, -1)
					if li < 0:
						li = lv.size()
						local[g] = li
						lv.append(pos[g])
						ln.append(nrm[g])
						for j in 4:
							lb.append(bon[g * 4 + j])
							lw.append(wei[g * 4 + j])
						lc.append(col[g])
						uv.append(Vector2(pos[g].x, pos[g].y))
						uv2.append(Vector2(pos[g].z, (blend["dist"] as PackedFloat32Array)[g]))
					ix.append(li)
			lidx.append(ix)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = lv
		arr[Mesh.ARRAY_NORMAL] = ln
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		if has_col:
			arr[Mesh.ARRAY_COLOR] = lc
		arr[Mesh.ARRAY_BONES] = lb
		arr[Mesh.ARRAY_WEIGHTS] = lw
		arr[Mesh.ARRAY_INDEX] = lidx[0]
		var lods := {}
		for l in levels:
			lods[lod_err[l]] = lidx[levels - l]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods)
		out.surface_set_material(s, data["mats"][s])
		out.surface_set_name(s, data["names"][s])
	# Manes and tails get loose locks hanging off them, so they part into strands at the
	# edges instead of ending in a smooth solid crest.
	for s in sc:
		if roles[s] != HAIR:
			continue
		var lk := _locks(pos, nrm, bon, wei, tris, tsurf, s, aabb, String(data["name"]).hash())
		if lk.is_empty():
			continue
		var lods := {}
		for l in levels:
			lods[lod_err[l]] = lk["lods"][levels - 1 - l]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lk["arrays"], [], lods)
		out.surface_set_material(out.get_surface_count() - 1, data["mats"][s])
		out.surface_set_name(out.get_surface_count() - 1, LOCKS)
	return out

## Hanging locks for hair surface `s`: tapered strips rooted on it, each falling to the
## animal's side and down, bound to the bones of the hair where it grows. UV runs across
## (x) and root to tip (y); UV2.x is the lock's own random number. "lods" holds every
## second and every fourth lock, for the coarser LODs.
static func _locks(pos: PackedVector3Array, nrm: PackedVector3Array, bon: PackedInt32Array, wei: PackedFloat32Array,
		tris: PackedInt32Array, tsurf: PackedInt32Array, s: int, aabb: AABB, seed: int) -> Dictionary:
	var ht := aabb.size.y
	var cx := aabb.get_center().x
	var cz := aabb.get_center().z
	var ids := PackedInt32Array()
	var cdf := PackedFloat32Array()
	var area := 0.0
	for t in tsurf.size():
		if tsurf[t] != s:
			continue
		var a := pos[tris[t * 3]]
		area += (pos[tris[t * 3 + 1]] - a).cross(pos[tris[t * 3 + 2]] - a).length() * 0.5
		ids.append(t)
		cdf.append(area)
	if ids.is_empty() or area <= 0.0:
		return {}
	var w := ht * 0.011
	var count := clampi(int(area / (w * w * 4.0)), 40, 540)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var rows := 6
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var lb := PackedInt32Array()
	var lw := PackedFloat32Array()
	var i0 := PackedInt32Array()
	var i1 := PackedInt32Array()
	var i2 := PackedInt32Array()
	for i in count:
		var k := cdf.bsearch(r.randf() * area)
		var t := ids[mini(k, ids.size() - 1)]
		var b1 := r.randf()
		var b2 := r.randf()
		if b1 + b2 > 1.0:
			b1 = 1.0 - b1
			b2 = 1.0 - b2
		var bc := [1.0 - b1 - b2, b1, b2]
		var p := Vector3.ZERO
		var sn := Vector3.ZERO
		var near := 0
		for c in 3:
			var g := tris[t * 3 + c]
			p += pos[g] * float(bc[c])
			sn += nrm[g] * float(bc[c])
			if float(bc[c]) > float(bc[near]):
				near = c
		sn = sn.normalized()
		var g0 := tris[t * 3 + near]
		# A tail (behind the body's middle) hangs long; a mane falls short to one side.
		var tail := p.z < cz
		var length := ht * (r.randf_range(0.09, 0.17) if tail else r.randf_range(0.05, 0.09))
		var side := signf(p.x - cx) if absf(p.x - cx) > w * 0.5 else (1.0 if r.randf() < 0.5 else -1.0)
		var d0 := (sn * (0.08 if tail else 0.55) + Vector3(0, -0.8, 0) + Vector3(side * (0.03 if tail else 0.35), 0, -0.12)).normalized()
		var hang := Vector3(side * (0.0 if tail else 0.05), -1.0, -0.12).normalized()
		var wave := r.randf() * TAU
		var lw0 := w * r.randf_range(0.6, 1.1) * (1.1 if tail else 1.0)
		var lid := r.randf()
		var q := p - sn * w * (0.6 if tail else 0.3)
		var base := v.size()
		var dir := d0
		for j in rows:
			var u := float(j) / (rows - 1)
			if j > 0:
				dir = d0.slerp(hang, u * u)
				q += dir * length / (rows - 1)
			var across := dir.cross(sn)
			if across.length_squared() < 1e-6:
				across = Vector3.RIGHT
			across = across.normalized()
			var c := q + across * sin(u * 3.0 + wave) * lw0 * 0.25
			var hw := lw0 * (1.0 - 0.55 * u)
			for e in 2:
				v.append(c + across * hw * (1.0 if e == 1 else -1.0))
				n.append(sn)
				# The tangent runs down the lock, for lighting it as hair (hair_lock.gdshader).
				tg.append_array(PackedFloat32Array([dir.x, dir.y, dir.z, 1.0]))
				uv.append(Vector2(float(e), u))
				uv2.append(Vector2(lid, 0.0))
				for m in 4:
					lb.append(bon[g0 * 4 + m])
					lw.append(wei[g0 * 4 + m])
		for j in rows - 1:
			var a := base + j * 2
			var quad := PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
			i0.append_array(quad)
			if i % 2 == 0:
				i1.append_array(quad)
			if i % 4 == 0:
				i2.append_array(quad)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = tg
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_BONES] = lb
	arr[Mesh.ARRAY_WEIGHTS] = lw
	arr[Mesh.ARRAY_INDEX] = i0
	return {"arrays": arr, "lods": [i1, i2]}

## The surface of each triangle at a coarser level: each subdivision splits a triangle
## into four in order, so level l's triangle t is level l+1's 4t..4t+3.
static func _surf_of(level_tris: Array, l: int, top: PackedInt32Array, levels: int) -> PackedInt32Array:
	var step := 1 << (2 * (levels - l))
	var n := (level_tris[l] as PackedInt32Array).size() / 3
	var out := PackedInt32Array()
	out.resize(n)
	for t in n:
		out[t] = top[t * step]
	return out

## One round of Loop subdivision. Soft surfaces' vertices and inner edges move to the
## smooth surface; anything touching a hard surface (horn, hoof, eye), an open edge or a
## non-manifold edge is split straight, so those parts keep their shape.
static func _subdivide(pos: PackedVector3Array, bon: PackedInt32Array, wei: PackedFloat32Array, col: PackedColorArray,
		tris: PackedInt32Array, tsurf: PackedInt32Array, soft: PackedByteArray) -> Dictionary:
	var n := pos.size()
	var nt := tsurf.size()
	var edge := {}
	var ea := PackedInt32Array()
	var eb := PackedInt32Array()
	var eo := PackedInt32Array() # up to two opposite corners
	var ecount := PackedInt32Array()
	var esoft := PackedByteArray()
	var tedge := PackedInt32Array()
	tedge.resize(nt * 3)
	var vhard := PackedByteArray()
	vhard.resize(n)
	for t in nt:
		var hard := soft[tsurf[t]] == 0
		for k in 3:
			var a := tris[t * 3 + k]
			var b := tris[t * 3 + (k + 1) % 3]
			var o := tris[t * 3 + (k + 2) % 3]
			if hard:
				vhard[a] = 1
			var key := mini(a, b) * 16777216 + maxi(a, b)
			var e: int = edge.get(key, -1)
			if e < 0:
				e = ea.size()
				edge[key] = e
				ea.append(mini(a, b))
				eb.append(maxi(a, b))
				eo.append_array([o, -1])
				ecount.append(0)
				esoft.append(1)
			if ecount[e] < 2:
				eo[e * 2 + ecount[e]] = o
			ecount[e] += 1
			if hard:
				esoft[e] = 0
			tedge[t * 3 + k] = e
	var ne := ea.size()
	# Neighbour sums for the vertex rule; vertices on open or odd edges stay put.
	var nsum := PackedVector3Array()
	nsum.resize(n)
	var val := PackedInt32Array()
	val.resize(n)
	for e in ne:
		var a := ea[e]
		var b := eb[e]
		nsum[a] += pos[b]
		nsum[b] += pos[a]
		val[a] += 1
		val[b] += 1
		if ecount[e] != 2:
			vhard[a] = 1
			vhard[b] = 1
	var np := PackedVector3Array()
	np.resize(n + ne)
	for v in n:
		var k := val[v]
		if vhard[v] == 1 or k < 3:
			np[v] = pos[v]
		else:
			var beta := 3.0 / 16.0 if k == 3 else 3.0 / (8.0 * k)
			np[v] = pos[v] * (1.0 - k * beta) + nsum[v] * beta
	var nb := bon.duplicate()
	var nw := wei.duplicate()
	var nc := col.duplicate()
	nb.resize((n + ne) * 4)
	nw.resize((n + ne) * 4)
	nc.resize(n + ne)
	var par := PackedInt32Array()
	par.resize(ne * 2)
	for e in ne:
		var a := ea[e]
		var b := eb[e]
		par[e * 2] = a
		par[e * 2 + 1] = b
		if ecount[e] == 2 and esoft[e] == 1:
			np[n + e] = (pos[a] + pos[b]) * 0.375 + (pos[eo[e * 2]] + pos[eo[e * 2 + 1]]) * 0.125
		else:
			np[n + e] = (pos[a] + pos[b]) * 0.5
		nc[n + e] = col[a].lerp(col[b], 0.5)
		_mix_weights(bon, wei, a, b, nb, nw, n + e)
	var nt2 := PackedInt32Array()
	nt2.resize(nt * 12)
	var ns := PackedInt32Array()
	ns.resize(nt * 4)
	for t in nt:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var mab := n + tedge[t * 3]
		var mbc := n + tedge[t * 3 + 1]
		var mca := n + tedge[t * 3 + 2]
		var o := t * 12
		nt2[o] = a; nt2[o + 1] = mab; nt2[o + 2] = mca
		nt2[o + 3] = b; nt2[o + 4] = mbc; nt2[o + 5] = mab
		nt2[o + 6] = c; nt2[o + 7] = mca; nt2[o + 8] = mbc
		nt2[o + 9] = mab; nt2[o + 10] = mbc; nt2[o + 11] = mca
		for k in 4:
			ns[t * 4 + k] = tsurf[t]
	return {"pos": np, "bon": nb, "wei": nw, "col": nc, "tris": nt2, "tsurf": ns, "par": par}

## Half of each endpoint's skin weights, the four strongest kept.
static func _mix_weights(bon: PackedInt32Array, wei: PackedFloat32Array, a: int, b: int, nb: PackedInt32Array, nw: PackedFloat32Array, at: int) -> void:
	var ids := PackedInt32Array()
	var ws := PackedFloat32Array()
	for v in [a, b]:
		for j in 4:
			var w := wei[v * 4 + j] * 0.5
			if w <= 0.0:
				continue
			var bi := bon[v * 4 + j]
			var f := ids.find(bi)
			if f < 0:
				ids.append(bi)
				ws.append(w)
			else:
				ws[f] += w
	var tot := 0.0
	for j in 4:
		var best := -1
		for i in ws.size():
			if ws[i] > 0.0 and (best < 0 or ws[i] > ws[best]):
				best = i
		if best < 0:
			nb[at * 4 + j] = 0
			nw[at * 4 + j] = 0.0
		else:
			nb[at * 4 + j] = ids[best]
			nw[at * 4 + j] = ws[best]
			tot += ws[best]
			ws[best] = 0.0
	if tot > 0.0:
		for j in 4:
			nw[at * 4 + j] /= tot

static func _normals(pos: PackedVector3Array, tris: PackedInt32Array) -> PackedVector3Array:
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		# Godot's front faces wind clockwise.
		var f := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		nrm[a] += f
		nrm[b] += f
		nrm[c] += f
	for i in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 0.0 else Vector3.UP
	return nrm

## Muscle under the coat: soft swellings over the shoulder, forearm, haunch, hamstring,
## gaskin, neck and chest, each centred under the skin on the bones at rest.
## [from bone, to bone, along, radius and lift (body heights), outward, strength]
const MUSCLE := [
	["FrontUpperLeg", "FrontLowerLeg", 0.12, 0.11, 0.6, 1.0],
	["FrontUpperLeg", "FrontLowerLeg", 0.5, 0.055, 0.5, 0.5],
	["BackLeg", "BackUpperLeg", 0.45, 0.13, 0.6, 1.2],
	["BackLeg", "BackUpperLeg", 0.7, 0.08, 0.3, 0.7],
	["BackUpperLeg", "BackLowerLeg", 0.28, 0.055, 0.4, 0.6],
]

static func _muscles(pos: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array, tsurf: PackedInt32Array,
		roles: PackedInt32Array, bones: Dictionary, height: float, amount: float) -> void:
	var centres := []
	for m in MUSCLE:
		for sd in [".L", ".R"]:
			var a = bones.get(m[0] + sd)
			var b = bones.get(m[1] + sd)
			if a == null or b == null:
				continue
			var c: Vector3 = (a as Vector3).lerp(b, m[2])
			c.x += signf(c.x) * height * 0.05 * m[4]
			centres.append([c, height * float(m[3]), float(m[5])])
	for pair in [["Neck1", "Neck2", 0.5, 0.1, 0.5], ["Torso3", "Neck1", 0.2, 0.1, 0.5]]:
		var a = bones.get(pair[0])
		var b = bones.get(pair[1])
		if a != null and b != null:
			var c: Vector3 = (a as Vector3).lerp(b, pair[2])
			if pair[0] == "Torso3":
				c += Vector3(0, -height * 0.12, height * 0.06)
			centres.append([c, height * float(pair[3]), float(pair[4])])
	if centres.is_empty():
		return
	var fur := PackedByteArray()
	fur.resize(pos.size())
	for t in tsurf.size():
		if roles[tsurf[t]] == FUR:
			for k in 3:
				fur[tris[t * 3 + k]] = 1
	for t in tsurf.size():
		if roles[tsurf[t]] != FUR:
			for k in 3:
				fur[tris[t * 3 + k]] = 0
	var amp := height * 0.011 * amount
	for i in pos.size():
		if fur[i] == 0:
			continue
		var d := 0.0
		for c in centres:
			var r: float = c[1]
			var q: float = pos[i].distance_squared_to(c[0]) / (r * r)
			if q < 9.0:
				d += exp(-q) * float(c[2])
		pos[i] += nrm[i] * amp * minf(d, 1.6)

## Where two coats meet (a pale rump on a brown body, a mane on a neck) the kit's colour
## changes along a polygon edge. For each vertex: how far it is from such a seam, 0..1
## of `reach` (1 beyond), so the shader can blend the two colours across it; and for
## each surface, the coat it borders most (-1 for none).
static func _seams(pos: PackedVector3Array, tris: PackedInt32Array, tsurf: PackedInt32Array, roles: PackedInt32Array, reach: float) -> Dictionary:
	var n := pos.size()
	var sc := roles.size()
	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var seam := PackedByteArray()
	seam.resize(n)
	# Only coat meets coat: a mane or tail stays its own colour to the edge.
	var coat := func(sf: int) -> bool: return roles[sf] == FUR
	for t in tsurf.size():
		var sf := tsurf[t]
		if not coat.call(sf):
			continue
		for k in 3:
			var v := tris[t * 3 + k]
			if owner[v] < 0:
				owner[v] = sf
			elif owner[v] != sf:
				seam[v] = 1
	# Which coat each surface borders most.
	var count := {}
	for t in tsurf.size():
		var sf := tsurf[t]
		if not coat.call(sf):
			continue
		for k in 3:
			var v := tris[t * 3 + k]
			if seam[v] == 1 and owner[v] != sf:
				var key := sf * 1024 + owner[v]
				count[key] = int(count.get(key, 0)) + 1
	var with := PackedInt32Array()
	with.resize(sc)
	with.fill(-1)
	var best := PackedInt32Array()
	best.resize(sc)
	for key in count:
		var a: int = key / 1024
		var b: int = key % 1024
		if count[key] > best[a]:
			best[a] = count[key]
			with[a] = b
			if with[b] < 0:
				with[b] = a
	# Distance from the nearest seam along the surface, by relaxing over edges.
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(reach)
	var queue: Array[int] = []
	for v in n:
		if seam[v] == 1:
			dist[v] = 0.0
			queue.append(v)
	var nb := []
	nb.resize(n)
	for i in n:
		nb[i] = []
	for t in range(0, tris.size(), 3):
		for k in 3:
			var a := tris[t + k]
			var b := tris[t + (k + 1) % 3]
			(nb[a] as Array).append(b)
	var head := 0
	while head < queue.size():
		var v := queue[head]
		head += 1
		for w in nb[v]:
			var d := dist[v] + pos[v].distance_to(pos[w])
			if d < dist[w]:
				dist[w] = d
				queue.append(w)
	for v in n:
		dist[v] = clampf(dist[v] / reach, 0.0, 1.0)
	return {"dist": dist, "with": with}
