class_name ClothFx
extends RefCounted
## Cloth that moves in the wind (cloth.gdshader): the kits' banner cloth (market stall
## awnings and drapes, hanging banners) and flags on poles.
##
## Kit cloth: BuildCatalog hands every "MI_Banner" surface through prepare(), which cuts
## it finer (so it can bend smoothly) and works out, for each point, how far below its
## hold it hangs (a drape swings and ripples) or how far in from its frame it lies (a
## stretched canopy breathes); kit_material() swaps the kit's material for the moving one
## with the same textures. Indoors (shelter) only a draught stirs it.
## Flags: add_flag() puts one on a pole in a mesh; it streams downwind, droops in a calm.

## Kit cloth is cut until no edge is longer than this (metres).
const MAX_EDGE := 0.14
## A kit cloth surface's normal tipped further than this from level lies flat (a canopy).
const FLAT := 0.55
## Columns of the grid that finds what a drape hangs from (metres).
const CELL := 0.2

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)

static var _mats := {}
static var _lock := Mutex.new()

## Whether a kit material is cloth that should move.
static func is_cloth(m: Material) -> bool:
	return m != null and m.resource_name == "MI_Banner"

## The moving version of a kit's cloth material (its own textures), out in the wind or
## (indoor) sheltered.
static func kit_material(src: Material, indoor := false) -> ShaderMaterial:
	_lock.lock()
	var key := [src, indoor]
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.resource_name = "MI_Banner" if not indoor else "MI_Banner_Indoor"
		m.shader = load("res://src/world/cloth.gdshader")
		var b := src as BaseMaterial3D
		if b != null:
			m.set_shader_parameter("albedo", b.albedo_color)
			if b.albedo_texture != null:
				m.set_shader_parameter("albedo_tex", b.albedo_texture)
				m.set_shader_parameter("has_albedo", true)
			if b.normal_enabled and b.normal_texture != null:
				m.set_shader_parameter("normal_tex", b.normal_texture)
				m.set_shader_parameter("has_normal", true)
				m.set_shader_parameter("normal_depth", b.normal_scale)
			if b.roughness_texture != null:
				m.set_shader_parameter("orm_tex", b.roughness_texture)
				m.set_shader_parameter("has_orm", true)
			m.set_shader_parameter("roughness", b.roughness)
		m.set_shader_parameter("shelter", 1.0 if indoor else 0.0)
		_mats[key] = m
	_lock.unlock()
	return m

## Swaps every outdoor kit cloth surface of a mesh for the sheltered one (rooms).
static func shelter(mesh: ArrayMesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is ShaderMaterial and m.resource_name == "MI_Banner":
			for src in _mats:
				if _mats[src] == m:
					mesh.surface_set_material(i, kit_material(src[0], true))
					break

static var _flag_mat: ShaderMaterial

## Woollen bunting, dyed by vertex colour.
static func flag_material() -> ShaderMaterial:
	_lock.lock()
	if _flag_mat == null:
		_flag_mat = ShaderMaterial.new()
		_flag_mat.shader = load("res://src/world/cloth.gdshader")
		var wool := Materials.photo("fabric_wool", "detail")
		if wool != null:
			_flag_mat.set_shader_parameter("albedo_tex", wool)
			_flag_mat.set_shader_parameter("has_albedo", true)
			# The weave averages about 0.72: lift it back to the dye's own shade.
			_flag_mat.set_shader_parameter("albedo", Color(1.35, 1.35, 1.35))
		_flag_mat.set_shader_parameter("vertex_dye", true)
		_flag_mat.set_shader_parameter("uv_scale", Vector2(9.0, 5.0))
		_flag_mat.set_shader_parameter("translucency", 0.45)
	_lock.unlock()
	return _flag_mat

static var _prepared := {}

## prepare() of surface `k` of a kit model (its arrays as BuildCatalog.model_parts lists
## them), worked out once and shared.
static func prepared(model: String, k: int, arrays: Array) -> Array:
	var key := "%s:%d" % [model, k]
	_lock.lock()
	var have = _prepared.get(key)
	_lock.unlock()
	if have != null:
		return have
	var out := prepare(arrays)
	_lock.lock()
	_prepared[key] = out
	_lock.unlock()
	return out

## A kit cloth surface's arrays, cut finer and carrying how each point hangs (CUSTOM0;
## see cloth.gdshader). Use with FORMAT.
static func prepare(arrays: Array) -> Array:
	var a := _subdivide(arrays, MAX_EDGE)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	# The top of the cloth over each patch of ground: what a drape there hangs from.
	var top := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in v.size():
		var c := Vector2i(floori(v[i].x / CELL), floori(v[i].z / CELL))
		top[c] = maxf(top.get(c, -INF), v[i].y)
		if absf(n[i].y) > FLAT:
			lo = Vector2(minf(lo.x, v[i].x), minf(lo.y, v[i].z))
			hi = Vector2(maxf(hi.x, v[i].x), maxf(hi.y, v[i].z))
	var custom := PackedFloat32Array()
	custom.resize(v.size() * 4)
	for i in v.size():
		var p := v[i]
		if absf(n[i].y) > FLAT:
			# A stretched canopy, held at its frame all round.
			custom[i * 4 + 1] = maxf(minf(minf(p.x - lo.x, hi.x - p.x), minf(p.z - lo.y, hi.y - p.z)), 0.0)
		else:
			var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
			var t := p.y
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					t = maxf(t, top.get(c + Vector2i(dx, dz), -INF))
			custom[i * 4] = t - p.y
	a[Mesh.ARRAY_CUSTOM0] = custom
	var c1 := PackedFloat32Array()
	c1.resize(v.size() * 4)
	a[Mesh.ARRAY_CUSTOM1] = c1
	return a

## Splits every edge longer than `max_len` at its middle (the same edges on both sides of
## a seam, so the cloth never tears) until none is left, keeping the triangles' winding.
static func _subdivide(arrays: Array, max_len: float) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var n: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tg: PackedFloat32Array = (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate() if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uv: PackedVector2Array = (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate() if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var col: PackedColorArray = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate() if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	else:
		for i in v.size():
			idx.append(i)
	var has_n := n.size() == v.size()
	var has_t := tg.size() == v.size() * 4
	var has_uv := uv.size() == v.size()
	var has_c := col.size() == v.size()
	var lim := max_len * max_len
	for _pass in 8:
		var mids := {}
		var out := PackedInt32Array()
		var split_any := false
		for t in range(0, idx.size(), 3):
			var tri := [idx[t], idx[t + 1], idx[t + 2]]
			var m := [-1, -1, -1] # the middle of edge k (from corner k to k+1), if split
			var count := 0
			for k in 3:
				var i0: int = tri[k]
				var i1: int = tri[(k + 1) % 3]
				if v[i0].distance_squared_to(v[i1]) > lim:
					var key := Vector2i(mini(i0, i1), maxi(i0, i1))
					if not mids.has(key):
						mids[key] = v.size()
						v.append((v[i0] + v[i1]) * 0.5)
						if has_n:
							n.append((n[i0] + n[i1]).normalized() if (n[i0] + n[i1]).length_squared() > 1e-8 else n[i0])
						if has_t:
							var t3 := Vector3(tg[i0 * 4] + tg[i1 * 4], tg[i0 * 4 + 1] + tg[i1 * 4 + 1], tg[i0 * 4 + 2] + tg[i1 * 4 + 2]).normalized()
							tg.append_array([t3.x, t3.y, t3.z, tg[i0 * 4 + 3]])
						if has_uv:
							uv.append((uv[i0] + uv[i1]) * 0.5)
						if has_c:
							col.append(col[i0].lerp(col[i1], 0.5))
					m[k] = mids[key]
					count += 1
			if count == 0:
				out.append_array(PackedInt32Array(tri))
				continue
			split_any = true
			if count == 3:
				out.append_array(PackedInt32Array([tri[0], m[0], m[2], m[0], tri[1], m[1], m[2], m[1], tri[2], m[0], m[1], m[2]]))
				continue
			# Turn the corners so the first split edge starts at corner 0.
			var r := 0
			while m[r] < 0 or (count == 2 and m[(r + 2) % 3] >= 0):
				r += 1
			var a: int = tri[r]
			var b: int = tri[(r + 1) % 3]
			var c: int = tri[(r + 2) % 3]
			var mab: int = m[r]
			if count == 1:
				out.append_array(PackedInt32Array([a, mab, c, mab, b, c]))
			else:
				var mbc: int = m[(r + 1) % 3]
				out.append_array(PackedInt32Array([mab, b, mbc, a, mab, mbc, a, mbc, c]))
		idx = out
		if not split_any:
			break
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	res[Mesh.ARRAY_VERTEX] = v
	if has_n:
		res[Mesh.ARRAY_NORMAL] = n
	if has_t:
		res[Mesh.ARRAY_TANGENT] = tg
	if has_uv:
		res[Mesh.ARRAY_TEX_UV] = uv
	if has_c:
		res[Mesh.ARRAY_COLOR] = col
	res[Mesh.ARRAY_INDEX] = idx
	return res

## A flag `w` wide and `h` deep flying from a pole, as a surface of `mesh`: xf places its
## top corner at the pole, the flag running along xf's +X (only a turn about the vertical
## and a move, so the pole stays upright). It streams downwind of its pole.
static func add_flag(mesh: ArrayMesh, xf: Transform3D, w: float, h: float, dye: Color) -> void:
	var nu := clampi(int(ceil(w / 0.08)), 6, 24)
	var nv := clampi(int(ceil(h / 0.1)), 3, 12)
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var pole := xf.origin
	var fly := xf.basis.x
	var ang := atan2(fly.z, fly.x)
	var normal := (xf.basis.z).normalized()
	for j in nv + 1:
		for i in nu + 1:
			var u := float(i) / nu
			var s := float(j) / nv
			v.append(xf * Vector3(u * w, -s * h, 0.0))
			nm.append(normal)
			uv.append(Vector2(u, s))
			# Sun-faded at the fly end, where it wears.
			col.append(dye.lerp(Color(0.85, 0.82, 0.76), 0.12 * u * u))
			c0.append_array([0.0, 0.0, u * w, 1.0])
			c1.append_array([pole.x, pole.z, ang, w])
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			idx.append_array([a, a + 1, a + nu + 1, a + 1, a + nu + 2, a + nu + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, FORMAT)
	mesh.surface_set_material(mesh.get_surface_count() - 1, flag_material())
	mesh.surface_set_name(mesh.get_surface_count() - 1, "flag")
