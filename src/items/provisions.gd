class_name Provisions
## Food, drink, potions and the bottles, jars, tins and flasks they come in, modelled to
## look like the real thing: glass you can see the liquid through, corks, wax and paper
## labels, fruit with blush and stems, bread with a scored crust, meat with marbling.
## Each model stands along +Y at real size, and says where a hand closes round it (the
## mesh's "grip" meta: a bottle's neck, a fruit's middle). Viewmodel.prop_for shows them
## in the hand in place of the item's icon.

static var _models: Dictionary = {}
static var _mats: Dictionary = {}
static var _tex: Dictionary = {}
static var _noise: FastNoiseLite
static var _glass_shader: Shader

## The model for item `t`, or null when it is not food, drink or a container.
static func model(t: String) -> ArrayMesh:
	if _models.has(t):
		return _models[t]
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var grip = _build(k, t)
	var out: ArrayMesh = null
	if grip is Vector3:
		out = k.commit(_mat)
		out.set_meta("grip", grip)
	_models[t] = out
	return out

static func has(t: String) -> bool:
	return model(t) != null

# --- Colours ---------------------------------------------------------------------------
# Glass: the tint, and in alpha how much it shows face on (clear glass hardly at all).
const CLEAR := Color(0.88, 0.94, 0.93, 0.08)
const GREEN := Color(0.14, 0.4, 0.18, 0.42)
const OLIVE := Color(0.1, 0.2, 0.07, 0.72)
const AMBER := Color(0.45, 0.2, 0.04, 0.55)
const BROWN_GLASS := Color(0.25, 0.1, 0.03, 0.72)
const AQUA := Color(0.62, 0.86, 0.84, 0.16)
# Liquids, alpha as how cloudy or deep they look.
const WINE := Color(0.32, 0.02, 0.05, 0.93)
const BLOOD_RED := Color(0.62, 0.02, 0.05, 0.88)
const LEAF_GREEN := Color(0.28, 0.85, 0.28, 0.7)
const GOLDEN := Color(0.96, 0.66, 0.12, 0.72)
const WATER := Color(0.82, 0.92, 0.96, 0.1)
const WHISKY := Color(0.58, 0.24, 0.03, 0.86)
const HONEY := Color(0.92, 0.55, 0.08, 0.82)
const COLA := Color(0.13, 0.04, 0.02, 0.96)
const VIOLET := Color(0.38, 0.08, 0.6, 0.86)
const CHARTREUSE := Color(0.78, 0.86, 0.36, 0.62)
const AMBER_DRINK := Color(0.86, 0.42, 0.08, 0.76)
const ICE_BLUE := Color(0.58, 0.9, 0.86, 0.34)
const OIL := Color(0.78, 0.56, 0.16, 0.7)
const IODINE := Color(0.35, 0.08, 0.02, 0.95)

# --- Building blocks --------------------------------------------------------------------

static func _nz(p: Vector3, f := 1.0) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 7177
		_noise.frequency = 1.0
		_noise.fractal_octaves = 3
	return _noise.get_noise_3dv(p * f)

## Catmull-Rom through the control points, `steps` pieces per span. A repeated point is
## a crease (a glass lip, the edge of a base) and stays repeated.
static func _curve(pts: Array, steps := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		if p1.is_equal_approx(p2):
			out.append(p1)
			continue
		var p0: Vector2 = pts[i - 1] if i > 0 and not (pts[i - 1] as Vector2).is_equal_approx(p1) else p1
		var p3: Vector2 = pts[i + 2] if i + 2 < n and not (pts[i + 2] as Vector2).is_equal_approx(p2) else p2
		for s in steps:
			var u := float(s) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	out.append(pts[n - 1])
	return out

## Sphere as a lathe profile, bottom pole to top pole.
static func _sphere(r: float, rings := 12, squash := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in rings + 1:
		var phi := PI * i / rings
		out.append(Vector2(sin(phi) * r, -cos(phi) * r * squash))
	return out

## One vertex. Triangles are given in any order: _tri turns them to face their normals.
static func _tri(st: SurfaceTool, xf: Transform3D, nb: Basis, p: Array, n: Array, c: Array, uv: Array) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var d: Vector3 = p[2]
	var face := (b - a).cross(d - a)
	if face.length_squared() < 1e-14:
		return
	# Godot's front faces wind clockwise.
	var order := [0, 2, 1] if face.dot(n[0] + n[1] + n[2]) > 0.0 else [0, 1, 2]
	for i in order:
		st.set_normal((nb * (n[i] as Vector3)).normalized())
		st.set_color(c[i])
		st.set_uv(uv[i])
		st.add_vertex(xf * (p[i] as Vector3))

static func _colour(col, p: Vector3, a: float, t: float) -> Color:
	return col.call(p, a, t) if col is Callable else col

## Surface of revolution about +Y. `prof` runs bottom to top as (radius, height); a
## repeated point is a crease. `shape(angle, t, p)` scales the radius (ribs, lumps,
## dimples) and `col` is a colour or `col(p, angle, t)`; t runs 0..1 along the profile.
## `arc` limits the sweep to part of a turn (a label, a cut wheel of cheese).
static func lathe(k: MeshKit, mat: String, xf: Transform3D, prof: PackedVector2Array, segs := 24, col: Variant = Color.WHITE, shape: Variant = null, arc := Vector2(0.0, 1.0)) -> void:
	var total := 0.0
	var ts := PackedFloat32Array([0.0])
	for i in range(1, prof.size()):
		total += prof[i].distance_to(prof[i - 1])
		ts.append(total)
	for i in ts.size():
		ts[i] /= maxf(total, 0.000001)
	var start := 0
	for i in range(1, prof.size() + 1):
		if i == prof.size() or prof[i].is_equal_approx(prof[i - 1]):
			_lathe_part(k, mat, xf, prof.slice(start, i), ts.slice(start, i), segs, col, shape, arc)
			start = i
	return

static func _lathe_part(k: MeshKit, mat: String, xf: Transform3D, prof: PackedVector2Array, ts: PackedFloat32Array, segs: int, col: Variant, shape: Variant, arc: Vector2) -> void:
	var n := prof.size()
	if n < 2:
		return
	var full := is_equal_approx(arc.y - arc.x, 1.0)
	var cols := segs + 1
	var P := PackedVector3Array()
	P.resize(n * cols)
	var A := PackedFloat32Array()
	A.resize(cols)
	for j in cols:
		A[j] = TAU * lerpf(arc.x, arc.y, float(j) / segs)
	for i in n:
		for j in cols:
			var a := A[j]
			var r := prof[i].x
			var p0 := Vector3(cos(a) * r, prof[i].y, sin(a) * r)
			if shape is Callable and r > 0.0:
				r *= shape.call(a, ts[i], p0)
			P[i * cols + j] = Vector3(cos(a) * r, prof[i].y, sin(a) * r)
	var N := PackedVector3Array()
	N.resize(n * cols)
	for i in n:
		var d := prof[mini(i + 1, n - 1)] - prof[maxi(i - 1, 0)]
		for j in cols:
			var up := P[mini(i + 1, n - 1) * cols + j] - P[maxi(i - 1, 0) * cols + j]
			var jn := j + 1
			var jp := j - 1
			if full:
				jn = (j % segs) + 1
				jp = (j + segs - 1) % segs
			else:
				jn = mini(jn, segs)
				jp = maxi(jp, 0)
			var around := P[i * cols + jn] - P[i * cols + jp]
			var nrm := up.cross(around)
			if nrm.length_squared() < 1e-16:
				# On the axis: straight up or down, the way the profile turns.
				nrm = Vector3(0, -d.x if absf(d.x) > 1e-7 else d.y, 0)
			N[i * cols + j] = nrm.normalized()
	var st := k._tool(mat)
	var nb := xf.basis.inverse().transposed()
	var C := PackedColorArray()
	C.resize(n * cols)
	for i in n:
		for j in cols:
			C[i * cols + j] = _colour(col, P[i * cols + j], A[j], ts[i])
	for i in n - 1:
		for j in segs:
			var q := [i * cols + j, (i + 1) * cols + j, i * cols + j + 1, (i + 1) * cols + j + 1]
			var uv := [Vector2(float(j) / segs, 1.0 - ts[i]), Vector2(float(j) / segs, 1.0 - ts[i + 1]), Vector2(float(j + 1) / segs, 1.0 - ts[i]), Vector2(float(j + 1) / segs, 1.0 - ts[i + 1])]
			for tri in [[0, 1, 2], [1, 3, 2]]:
				_tri(st, xf, nb, [P[q[tri[0]]], P[q[tri[1]]], P[q[tri[2]]]], [N[q[tri[0]]], N[q[tri[1]]], N[q[tri[2]]]], [C[q[tri[0]]], C[q[tri[1]]], C[q[tri[2]]]], [uv[tri[0]], uv[tri[1]], uv[tri[2]]])

## A tube along `pts` (stems, handles, sausages, bones); `radii` per point.
static func tube(k: MeshKit, mat: String, xf: Transform3D, pts: PackedVector3Array, radii: PackedFloat32Array, sides := 10, col: Variant = Color.WHITE, caps := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var st := k._tool(mat)
	var nb := xf.basis.inverse().transposed()
	var rings: Array = []
	var norms: Array = []
	var t0 := (pts[1] - pts[0]).normalized()
	var side := t0.cross(Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT).normalized()
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		# Carry the side vector along the bend so the tube doesn't twist.
		side = (side - t * side.dot(t)).normalized()
		var up := t.cross(side)
		var ring := PackedVector3Array()
		var rn := PackedVector3Array()
		for s in sides + 1:
			var a := TAU * s / sides
			var dir := side * cos(a) + up * sin(a)
			ring.append(pts[i] + dir * radii[i])
			rn.append(dir)
		rings.append(ring)
		norms.append(rn)
	for i in n - 1:
		var c0 := _colour(col, pts[i], 0.0, float(i) / (n - 1))
		var c1 := _colour(col, pts[i + 1], 0.0, float(i + 1) / (n - 1))
		for s in sides:
			var a: PackedVector3Array = rings[i]
			var b: PackedVector3Array = rings[i + 1]
			var na: PackedVector3Array = norms[i]
			var nb2: PackedVector3Array = norms[i + 1]
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			_tri(st, xf, nb, [a[s], b[s], a[s + 1]], [na[s], nb2[s], na[s + 1]], [c0, c1, c0], [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 0)])
			_tri(st, xf, nb, [b[s], b[s + 1], a[s + 1]], [nb2[s], nb2[s + 1], na[s + 1]], [c1, c1, c0], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)])
	if caps:
		for e in [[0, -1.0], [n - 1, 1.0]]:
			var i: int = e[0]
			var t: Vector3 = ((pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()) * e[1]
			var ring: PackedVector3Array = rings[i]
			var c := _colour(col, pts[i], 0.0, float(i) / (n - 1))
			for s in sides:
				_tri(st, xf, nb, [pts[i], ring[s], ring[s + 1]], [t, t, t], [c, c, c], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)])

## A thin leaf, both sides shown: along +Y from the origin, folded a little at the
## midrib and curled back at the tip.
static func leaf(k: MeshKit, xf: Transform3D, length: float, width: float, col: Color, curl := 0.3, segs := 6) -> void:
	var st := k._tool("pv_leaf")
	var nb := xf.basis.inverse().transposed()
	var rows: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var w := sin(PI * pow(t, 0.8)) * width * 0.5
		var y := t * length
		var z := curl * length * t * t
		var fold := w * 0.25
		rows.append([Vector3(-w, y, z + fold), Vector3(0, y, z), Vector3(w, y, z + fold)])
	var vein := col.lightened(0.25)
	for i in segs:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for s in 2:
			var n: Vector3 = (b[s + 1] - a[s]).cross(a[s + 1] - b[s]).normalized()
			if n.z < 0.0:
				n = -n
			var cs := [col, vein, col]
			_tri(st, xf, nb, [a[s], b[s], a[s + 1]], [n, n, n], [cs[s], cs[s], cs[s + 1]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			_tri(st, xf, nb, [b[s], b[s + 1], a[s + 1]], [n, n, n], [cs[s], cs[s + 1], cs[s + 1]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

## The profile `d` in from `prof` (each point moved along its inward normal), floored at
## `floor_y`, top to bottom: the inside of a glass or a bowl.
static func _inset(prof: PackedVector2Array, d: float, floor_y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := prof.size()
	for i in n:
		var t := prof[mini(i + 1, n - 1)] - prof[maxi(i - 1, 0)]
		if t.length_squared() < 1e-12:
			t = prof[mini(i + 2, n - 1)] - prof[maxi(i - 2, 0)]
		var inward := Vector2(-t.y, t.x).normalized()
		var p := prof[i] + inward * d
		p.x = maxf(p.x, 0.0)
		p.y = maxf(p.y, floor_y)
		out.append(p)
	out.reverse()
	return out

## Radius of `prof` at height `y` (the widest crossing).
static func _radius_at(prof: PackedVector2Array, y: float) -> float:
	var r := 0.0
	for i in prof.size() - 1:
		var a := prof[i]
		var b := prof[i + 1]
		if (a.y - y) * (b.y - y) <= 0.0 and absf(b.y - a.y) > 1e-7:
			r = maxf(r, lerpf(a.x, b.x, (y - a.y) / (b.y - a.y)))
	return r

## A glass vessel: `outer` from the centre of the base round to the top of the lip, walls
## `wall` thick (the base three times that), filled with `liquid` up to `fill_y`.
static func vessel(k: MeshKit, xf: Transform3D, outer: Array, wall: float, glass: Color, liquid: Color, fill_y: float, segs := 28, shape: Variant = null) -> PackedVector2Array:
	var prof := _curve(outer, 3)
	var base := prof[0].y
	var inner := _inset(prof, wall, base + wall * 3.0)
	# Close the lip: the outer rim, flat across, then down the inside.
	var shell := PackedVector2Array(prof)
	shell.append(prof[prof.size() - 1])
	shell.append(inner[0])
	shell.append(inner[0])
	shell.append_array(inner.slice(1))
	if shell[shell.size() - 1].x > 0.0:
		shell.append(Vector2(0.0, shell[shell.size() - 1].y))
	lathe(k, "pv_glass", xf, shell, segs, glass, shape)
	if liquid.a > 0.0 and fill_y > base:
		# The liquid fills the inside up to fill_y, a hair in from the glass.
		var up := PackedVector2Array(inner)
		up.reverse()
		var fluid := PackedVector2Array()
		for p in up:
			if p.y >= fill_y:
				break
			fluid.append(Vector2(p.x * 0.97, p.y + 0.0005))
		var r := _radius_at(up, fill_y) * 0.97
		fluid.append(Vector2(r, fill_y))
		fluid.append(Vector2(r, fill_y))
		# The meniscus: the surface creeps up the glass at the edge.
		fluid.append(Vector2(r * 0.85, fill_y - 0.0012))
		fluid.append(Vector2(0.0, fill_y - 0.0015))
		if fluid[0].x > 0.0:
			fluid.insert(0, Vector2(0.0, fluid[0].y))
		lathe(k, "pv_liquid", xf, fluid, segs, liquid, shape)
	return prof

## A cork pushed into a neck of inner radius `r` whose lip is at `top`.
static func cork(k: MeshKit, xf: Transform3D, r: float, top: float, proud := 0.012, depth := 0.022) -> void:
	var c := Color(0.78, 0.6, 0.4)
	var prof := _curve([Vector2(0, top - depth), Vector2(r * 0.96, top - depth), Vector2(r * 0.96, top - depth), Vector2(r, top), Vector2(r * 1.12, top + proud * 0.9), Vector2(r * 1.12, top + proud * 0.9), Vector2(r * 0.95, top + proud), Vector2(0, top + proud)], 2)
	lathe(k, "pv_cork", xf, prof, 14, func(p: Vector3, _a: float, _t: float) -> Color: return c.darkened(0.25 * maxf(0.0, _nz(p, 300.0))))

## Sealing wax over a cork and down the neck in drips. `r` is the lip's outer radius.
static func wax(k: MeshKit, xf: Transform3D, r: float, top: float, col: Color, length := 0.03) -> void:
	var prof := _curve([Vector2(0, top + 0.016), Vector2(r * 0.9, top + 0.014), Vector2(r + 0.002, top + 0.004), Vector2(r + 0.0018, top - length), Vector2(r + 0.0018, top - length), Vector2(r - 0.0005, top - length - 0.002)], 3)
	lathe(k, "pv_wax", xf, prof, 24, func(p: Vector3, _a: float, _t: float) -> Color: return col.darkened(0.15 * _nz(p, 120.0)))
	# A few drips run further down.
	for i in 4:
		var a := TAU * (i * 0.27 + 0.1)
		var l := length + 0.006 + 0.012 * absf(sin(i * 2.3))
		var d := Vector3(cos(a), 0, sin(a))
		var end := d * (r + 0.0006) + Vector3(0, top - l, 0)
		tube(k, "pv_wax", xf, PackedVector3Array([d * (r + 0.0012) + Vector3(0, top - length + 0.004, 0), end]), PackedFloat32Array([0.0019, 0.0015]), 8, col, false)
		lathe(k, "pv_wax", xf * Transform3D(Basis.IDENTITY, end), _sphere(0.0019, 5, 1.2), 8, col)

## A paper label round part of a body of radius `r`, from `y0` to `y1`.
static func label(k: MeshKit, xf: Transform3D, r: float, y0: float, y1: float, style: String, arc := 0.42, at := 0.25) -> void:
	var prof := PackedVector2Array([Vector2(r + 0.0006, y0), Vector2(r + 0.0006, y1)])
	lathe(k, "pv_label_" + style, xf, prof, 20, Color.WHITE, null, Vector2(at - arc * 0.5, at + arc * 0.5))

## Twine wound round a neck: a few turns of thin cord.
static func twine(k: MeshKit, xf: Transform3D, r: float, y: float, turns := 3, col := Color(0.72, 0.6, 0.42)) -> void:
	for i in turns:
		var pts := PackedVector3Array()
		var rad := PackedFloat32Array()
		for s in 25:
			var a := TAU * s / 24.0
			pts.append(Vector3(cos(a) * (r + 0.0015), y + i * 0.0032 + 0.0012 * sin(a * 2.0 + i), sin(a) * (r + 0.0015)))
			rad.append(0.0016)
		tube(k, "pv_twine", xf, pts, rad, 5, col, false)

# --- Materials --------------------------------------------------------------------------

static func _std(rough: float, metal := 0.0, tex := "", freq := 0.1, scale := 12.0, bump := 0.6, cellular := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = Materials._noise_tex(tex, freq, false, 4, cellular)
		m.normal_enabled = true
		m.normal_texture = Materials._noise_tex(tex, freq, true, 4, cellular)
		m.normal_scale = bump
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func _glassy(rough: float, edge: float, through: float, priority: int, spec := 0.5) -> ShaderMaterial:
	if _glass_shader == null:
		_glass_shader = load("res://src/items/glass.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _glass_shader
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("edge_alpha", edge)
	m.set_shader_parameter("through", through)
	m.set_shader_parameter("spec", spec)
	# The liquid draws before the glass that holds it.
	m.render_priority = priority
	return m

static func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"pv_glass": m = _glassy(0.03, 0.9, 0.0, 1)
		# The liquid behind the glass: the glass does the reflecting.
		"pv_liquid": m = _glassy(0.3, 0.85, 0.6, 0, 0.08)
		"pv_cork": m = _std(0.92, 0.0, "cork", 0.35, 40.0, 1.2, true)
		"pv_wax":
			var s := _std(0.3, 0.0, "wax", 0.08, 30.0, 0.25)
			s.albedo_texture = null
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.25
			m = s
		"pv_twine": m = _std(0.95, 0.0, "twine", 0.3, 60.0, 0.8)
		"pv_skin":
			# Fruit skin: waxy, a soft sheen over fine pores.
			var s := _std(0.42, 0.0, "pores", 0.5, 30.0, 0.15)
			s.albedo_texture = null
			s.clearcoat_enabled = true
			s.clearcoat = 0.35
			s.clearcoat_roughness = 0.35
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.15
			m = s
		"pv_veg": m = _std(0.72, 0.0, "veg", 0.25, 18.0, 0.6)
		"pv_sand": m = _std(0.95, 0.0, "sandgrain", 0.9, 40.0, 0.6)
		"pv_leaf":
			var s := _std(0.55)
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			s.backlight_enabled = true
			s.backlight = Color(0.25, 0.35, 0.1)
			m = s
		"pv_crust": m = _std(0.78, 0.0, "crust", 0.3, 14.0, 1.0, true)
		"pv_crumb": m = _std(0.9, 0.0, "crumb", 0.6, 30.0, 1.4, true)
		"pv_meat":
			var s := _std(0.38, 0.0, "fibre", 0.2, 22.0, 0.5)
			s.albedo_texture = null
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			m = s
		"pv_marbled":
			# Beef: deep red, threaded with thin white fat.
			var s := _std(0.38, 0.0, "fibre", 0.2, 22.0, 0.4)
			s.albedo_texture = _ramp_tex("marble", 0.04, [[0.0, Color(0.32, 0.03, 0.04)], [0.55, Color(0.5, 0.06, 0.07)], [0.78, Color(0.55, 0.1, 0.1)], [0.86, Color(0.9, 0.78, 0.72)], [1.0, Color(0.96, 0.9, 0.84)]], true)
			s.uv1_scale = Vector3.ONE * 9.0
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			m = s
		"pv_meat_synth":
			# Lab-grown: an even pink-red with faint growth lines.
			var s := _std(0.35, 0.0, "fibre", 0.2, 22.0, 0.3)
			s.albedo_texture = _ramp_tex("synth", 0.08, [[0.0, Color(0.6, 0.12, 0.14)], [1.0, Color(0.72, 0.22, 0.24)]], false)
			s.uv1_scale = Vector3.ONE * 6.0
			m = s
		"pv_fat":
			var s := _std(0.45, 0.0, "fibre", 0.2, 22.0, 0.3)
			s.albedo_texture = null
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.4
			m = s
		"pv_roast":
			# Browned and glistening with fat.
			var s := _std(0.42, 0.0, "roast", 0.3, 16.0, 1.0, true)
			s.clearcoat_enabled = true
			s.clearcoat = 0.4
			s.clearcoat_roughness = 0.4
			m = s
		"pv_bone": m = _std(0.7, 0.0, "bonegrain", 0.3, 20.0, 0.3)
		"pv_fish":
			# Wet scales: a pearly sheen.
			var s := _std(0.28, 0.25, "scales", 0.6, 60.0, 0.5, true)
			s.albedo_texture = null
			m = s
		"pv_shell": m = _std(0.55, 0.0, "eggshell", 0.4, 40.0, 0.15)
		"pv_glossy":
			# Sauce, broth, jam, syrup: wet and shiny.
			var s := _std(0.12)
			s.clearcoat_enabled = true
			s.clearcoat = 0.6
			m = s
		"pv_soft": m = _std(0.6, 0.0, "soft", 0.3, 24.0, 0.3)
		"pv_wood": m = _std(0.62, 0.0, "woodgrain", 0.08, 10.0, 0.5)
		"pv_clay": m = _std(0.9, 0.0, "clay", 0.25, 16.0, 0.6)
		"pv_glaze":
			var s := _std(0.22, 0.0, "clay", 0.25, 16.0, 0.2)
			s.clearcoat_enabled = true
			s.clearcoat = 0.7
			m = s
		"pv_tin": m = _std(0.3, 0.9, "tin", 0.12, 12.0, 0.25)
		"pv_paint": m = _std(0.35, 0.4, "paint", 0.12, 12.0, 0.1)
		"pv_rubber": m = _std(0.75)
		"pv_plastic": m = _std(0.35)
		"pv_cloth":
			var s := _std(0.95, 0.0, "linen", 0.3, 40.0, 0.7)
			if Materials.photo("fabric_linen", "detail") != null:
				s.albedo_texture = Materials.photo("fabric_linen", "detail")
				s.uv1_scale = Vector3.ONE * 18.0
			m = s
		"pv_leather":
			var s := _std(0.62, 0.0, "hidegrain", 0.4, 30.0, 0.6)
			if Materials.photo("leather_worn", "detail") != null:
				s.albedo_texture = Materials.photo("leather_worn", "detail")
				s.uv1_scale = Vector3.ONE * 9.0
			m = s
		_:
			if name.begins_with("pv_label_"):
				var s := StandardMaterial3D.new()
				s.albedo_texture = _label_tex(name.substr(9))
				s.roughness = 0.85
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				m = s
			else:
				m = Materials.get_mat(name)
	_mats[name] = m
	return m

## A noise texture coloured by `stops` ([offset, colour] pairs); `ridged` folds the
## noise into thin veins at the top of the range (marbling).
static func _ramp_tex(key: String, freq: float, stops: Array, ridged: bool) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = WHash.str_hash(key) & 0xFFFF
	n.frequency = freq
	n.fractal_octaves = 4
	if ridged:
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(e): return e[0]))
	g.colors = PackedColorArray(stops.map(func(e): return e[1]))
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	t.generate_mipmaps = true
	_tex[key] = t
	return t

## Labels, drawn once: aged paper with a ruled border and lines of handwriting, or a
## printed frontier label in bands of colour.
static func _label_tex(style: String) -> Texture2D:
	if _tex.has(style):
		return _tex[style]
	var W := 256
	var H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(style)
	var paper := Color(0.86, 0.78, 0.6)
	var ink := Color(0.16, 0.1, 0.06)
	var band := Color(0, 0, 0, 0)
	match style:
		"white":
			paper = Color(0.93, 0.9, 0.82)
			ink = Color(0.12, 0.1, 0.1)
		"red":
			paper = Color(0.9, 0.86, 0.76)
			band = Color(0.62, 0.1, 0.08)
		"beans":
			paper = Color(0.88, 0.82, 0.66)
			band = Color(0.55, 0.16, 0.1)
		"green":
			paper = Color(0.86, 0.82, 0.68)
			band = Color(0.18, 0.36, 0.2)
		"blue":
			paper = Color(0.9, 0.88, 0.8)
			band = Color(0.12, 0.24, 0.48)
	for y in H:
		for x in W:
			var v := _nz(Vector3(x, y, 0.0), 0.04) * 0.06 + _nz(Vector3(x, y, 9.0), 0.25) * 0.025
			# Paper yellows and darkens towards its edges.
			var edge := minf(minf(x, W - 1 - x), minf(y, H - 1 - y)) / 18.0
			var c := paper.darkened(clampf(0.12 - edge * 0.12, 0.0, 0.12) + v)
			if band.a > 0.0 and (y < 30 or y > H - 22):
				c = band.darkened(v)
			img.set_pixel(x, y, c)
	var line_col := band if band.a > 0.0 else ink
	# A ruled border.
	for x in range(8, W - 8):
		for y in [10, 11, H - 12, H - 11]:
			if band.a == 0.0:
				img.set_pixel(x, y, ink.lerp(paper, 0.35))
	# Lines of writing: strokes of varying height along each line.
	var lines := [[46, 7], [66, 4], [84, 4], [100, 3]] if band.a > 0.0 else [[34, 6], [58, 4], [78, 4], [96, 4]]
	for li in lines.size():
		var y0: int = lines[li][0]
		var hgt: int = lines[li][1]
		var x := 24 + r.randi_range(0, 30) if li > 0 else 40
		var x_end := W - 24 - r.randi_range(0, 60) if li > 0 else W - 40
		while x < x_end:
			var word := r.randi_range(10, 34)
			for wx in word:
				var h := hgt + r.randi_range(-1, 2)
				var wob := int(round(sin((x + wx) * 0.9) * 1.2))
				for dy in h:
					var px := x + wx
					var py := y0 - dy + wob
					if px < W and py >= 0 and py < H and r.randf() < 0.55:
						img.set_pixel(px, py, (ink if li > 0 or band.a == 0.0 else line_col).lerp(paper, r.randf_range(0.0, 0.35)))
			x += word + r.randi_range(5, 9)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[style] = t
	return t

# --- The message in a bottle -------------------------------------------------------------

## The message-in-a-bottle Easter egg (EasterEggs "msg_bottle"): an old hand-blown bottle
## of green glass washed up on its side, half sunk in wet sand with a little sand inside,
## stopped with a cork tied down with twine, a letter rolled up inside and tied with red
## ribbon. Barnacles have grown on the glass and a strand of weed wraps the neck.
static func msg_bottle(k: MeshKit, r: RandomNumberGenerator) -> void:
	# +Y along the bottle, lying on its side, a little nose-down into the sand.
	var lie := Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, PI * 0.5 + 0.06), Vector3(0.13, 0.03, -0.05))
	var outer := [Vector2(0, 0.012), Vector2(0.022, 0.004), Vector2(0.036, 0.0), Vector2(0.036, 0.0), Vector2(0.043, 0.007), Vector2(0.045, 0.06), Vector2(0.0445, 0.15), Vector2(0.04, 0.18), Vector2(0.024, 0.205), Vector2(0.0155, 0.225), Vector2(0.0148, 0.26), Vector2(0.0148, 0.26), Vector2(0.0175, 0.263), Vector2(0.0178, 0.272), Vector2(0.0178, 0.272), Vector2(0.0155, 0.275)]
	# Hand-blown: a little lopsided, never quite round.
	var lop := func(a: float, t: float, p: Vector3) -> float: return 1.0 + 0.025 * sin(a + t * 3.0) + 0.012 * _nz(p, 40.0)
	vessel(k, lie, outer, 0.0032, Color(0.16, 0.36, 0.2, 0.32), Color(0, 0, 0, 0), 0.0, 32, lop)
	cork(k, lie, 0.0118, 0.275, 0.015, 0.024)
	twine(k, lie, 0.0178, 0.262, 3)
	# A drift of sand on the lowest side inside (local +X faces down once it lies).
	lathe(k, "pv_sand", lie, PackedVector2Array([Vector2(0.034, 0.012), Vector2(0.04, 0.05), Vector2(0.039, 0.12), Vector2(0.034, 0.16)]), 10, Color(0.78, 0.68, 0.5), null, Vector2(-0.07, 0.07))
	# The letter: a rolled sheet of handwriting tied round the middle with red ribbon.
	var scroll := lie * Transform3D(Basis(Vector3.FORWARD, 0.04), Vector3(0.012, 0.03, 0))
	lathe(k, "pv_label_parch", scroll, PackedVector2Array([Vector2(0.021, 0.0), Vector2(0.021, 0.15)]), 24, Color.WHITE)
	lathe(k, "pv_label_parch", scroll, PackedVector2Array([Vector2(0.021, 0.15), Vector2(0.021, 0.0)]), 24, Color(0.85, 0.82, 0.75))
	for y in [0.0, 0.15]:
		# The rolled ends: a spiral of paper edges.
		var spiral := PackedVector3Array()
		var rad := PackedFloat32Array()
		for s in 61:
			var a := s * TAU * 3.0 / 60.0
			var rr := 0.004 + 0.017 * s / 60.0
			spiral.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			rad.append(0.0007)
		tube(k, "pv_soft", scroll, spiral, rad, 4, Color(0.8, 0.72, 0.55), false)
	lathe(k, "pv_cloth", scroll, PackedVector2Array([Vector2(0.0222, 0.068), Vector2(0.0225, 0.075), Vector2(0.0222, 0.082)]), 20, Color(0.62, 0.06, 0.06))
	# Barnacles on the upper glass: little white volcanoes.
	for i in 14:
		var a := PI + r.randf_range(-0.9, 0.9)
		var y := r.randf_range(0.02, 0.17)
		var rr := 0.0448
		var at := Vector3(cos(a) * rr, y, sin(a) * rr)
		var out := Vector3(cos(a), 0, sin(a))
		var size := r.randf_range(0.003, 0.0065)
		lathe(k, "pv_shell", lie * Transform3D(_facing(out), at), _curve([Vector2(size, 0.0), Vector2(size * 0.8, size * 0.35), Vector2(size * 0.4, size * 0.55), Vector2(size * 0.25, size * 0.4), Vector2(0, size * 0.32)], 2), 8, Color(0.72, 0.7, 0.64).darkened(r.randf_range(0.0, 0.25)), func(a2: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.15 * sin(a2 * 6.0))
	# A strand of dark weed draped over the neck and trailing on the sand.
	var weed := PackedVector3Array()
	var wr := PackedFloat32Array()
	for s in 14:
		var f := s / 13.0
		var a := PI + f * 4.0
		weed.append(Vector3(cos(a) * 0.019, 0.2 + f * 0.045, sin(a) * 0.019) if f < 0.6 else Vector3(0.015 + (f - 0.6) * 0.15, 0.24 + (f - 0.6) * 0.1, 0.02 * sin(f * 9.0)))
		wr.append(0.0022)
	tube(k, "pv_leaf", lie, weed, wr, 5, Color(0.2, 0.22, 0.08), false)
	# Wet sand heaped against the downhill side.
	lathe(k, "pv_sand", Transform3D(Basis.from_scale(Vector3(1.6, 1.0, 0.8)), Vector3(0.05, -0.012, 0.02)), _curve([Vector2(0, 0.032), Vector2(0.06, 0.026), Vector2(0.12, 0.01), Vector2(0.16, 0.0)], 3), 24, Color(0.66, 0.56, 0.4), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.15 * _nz(p, 12.0))

## A basis turning +Y to face `dir`.
static func _facing(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))

# --- The items --------------------------------------------------------------------------

## Builds item `t` into `k` and returns where the hand grips it, or null.
static func _build(k: MeshKit, t: String) -> Variant:
	var I := Transform3D.IDENTITY
	match t:
		# Bottles ---------------------------------------------------------------------
		"wine":
			# A Bordeaux bottle in dark olive glass: punt in the base, long neck, cork under
			# red wax, a hand-written label.
			var outer := [Vector2(0, 0.016), Vector2(0.02, 0.008), Vector2(0.033, 0.001), Vector2(0.033, 0.001), Vector2(0.0372, 0.008), Vector2(0.0375, 0.1), Vector2(0.0372, 0.188), Vector2(0.03, 0.214), Vector2(0.018, 0.232), Vector2(0.0145, 0.25), Vector2(0.0145, 0.282), Vector2(0.0145, 0.282), Vector2(0.0168, 0.285), Vector2(0.0168, 0.296), Vector2(0.0168, 0.296), Vector2(0.015, 0.3)]
			vessel(k, I, outer, 0.0035, OLIVE, WINE, 0.215, 30)
			cork(k, I, 0.0105, 0.3, 0.004)
			wax(k, I, 0.0168, 0.3, Color(0.5, 0.06, 0.06), 0.032)
			label(k, I, 0.0375, 0.07, 0.15, "parch", 0.4)
			return Vector3(0, 0.09, 0)
		"empty_bottle":
			# Clear glass, unstoppered.
			var outer := [Vector2(0, 0.006), Vector2(0.025, 0.001), Vector2(0.025, 0.001), Vector2(0.031, 0.006), Vector2(0.032, 0.09), Vector2(0.03, 0.12), Vector2(0.015, 0.142), Vector2(0.012, 0.16), Vector2(0.012, 0.18), Vector2(0.012, 0.18), Vector2(0.0145, 0.183), Vector2(0.0145, 0.19), Vector2(0.0145, 0.19), Vector2(0.0125, 0.192)]
			vessel(k, I, outer, 0.0028, CLEAR, Color(0, 0, 0, 0), 0.0, 28)
			return Vector3(0, 0.06, 0)
		"fire_bottle":
			# A green bottle of lamp oil with a rag stuffed in the neck.
			var outer := [Vector2(0, 0.012), Vector2(0.02, 0.004), Vector2(0.029, 0.0), Vector2(0.029, 0.0), Vector2(0.033, 0.006), Vector2(0.034, 0.12), Vector2(0.03, 0.15), Vector2(0.016, 0.172), Vector2(0.013, 0.19), Vector2(0.013, 0.215), Vector2(0.013, 0.215), Vector2(0.0152, 0.218), Vector2(0.0152, 0.226), Vector2(0.0152, 0.226), Vector2(0.013, 0.228)]
			vessel(k, I, outer, 0.003, GREEN, OIL, 0.12, 28)
			var rag := Color(0.78, 0.72, 0.6)
			tube(k, "pv_cloth", I, PackedVector3Array([Vector3(0, 0.19, 0), Vector3(0, 0.228, 0), Vector3(0.004, 0.245, 0.002), Vector3(0.015, 0.262, 0.006), Vector3(0.03, 0.27, 0.004), Vector3(0.045, 0.262, -0.002)]), PackedFloat32Array([0.009, 0.01, 0.012, 0.011, 0.008, 0.005]), 8, func(p: Vector3, _a: float, t2: float) -> Color: return rag.darkened(0.15 + 0.5 * t2 * t2 + 0.1 * _nz(p, 200.0)))
			return Vector3(0, 0.08, 0)
		"whiskey":
			# A flat-sided spirit bottle: amber whisky through clear glass, a short neck,
			# cork, and a white label.
			var square := func(a: float, _t: float, _p: Vector3) -> float:
				return 1.0 / pow(pow(absf(cos(a)) * 1.55, 6.0) + pow(absf(sin(a)), 6.0), 1.0 / 6.0)
			var outer := [Vector2(0, 0.004), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.038, 0.006), Vector2(0.038, 0.15), Vector2(0.034, 0.168), Vector2(0.018, 0.178), Vector2(0.0125, 0.188), Vector2(0.0125, 0.21), Vector2(0.0125, 0.21), Vector2(0.015, 0.213), Vector2(0.015, 0.222), Vector2(0.015, 0.222), Vector2(0.013, 0.224)]
			vessel(k, I, outer, 0.003, CLEAR, WHISKY, 0.15, 40, square)
			cork(k, I, 0.0098, 0.224, 0.016)
			k.box("pv_label_white", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.085, 0.0381)), Vector3(0.036, 0.06, 0.0008))
			return Vector3(0, 0.07, 0)
		"sarsaparilla":
			# A brown glass soda bottle with a crown cap and a red-banded label.
			var outer := [Vector2(0, 0.006), Vector2(0.022, 0.001), Vector2(0.022, 0.001), Vector2(0.0275, 0.006), Vector2(0.0285, 0.11), Vector2(0.025, 0.14), Vector2(0.014, 0.17), Vector2(0.011, 0.2), Vector2(0.011, 0.215), Vector2(0.011, 0.215), Vector2(0.0135, 0.218), Vector2(0.0135, 0.224), Vector2(0.0135, 0.224), Vector2(0.0115, 0.226)]
			vessel(k, I, outer, 0.0028, BROWN_GLASS, COLA, 0.19, 28)
			# Crown cap: a fluted steel cap crimped over the lip.
			lathe(k, "pv_tin", I, _curve([Vector2(0.0145, 0.217), Vector2(0.0148, 0.224), Vector2(0.0148, 0.224), Vector2(0.013, 0.2275), Vector2(0, 0.2278)], 2), 42, Color(0.7, 0.68, 0.62), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.06 * pow(absf(sin(a * 10.5)), 3.0))
			label(k, I, 0.0285, 0.05, 0.1, "red", 0.45)
			return Vector3(0, 0.07, 0)
		"tonic_bottle":
			# An amber apothecary bottle with a cork and a handwritten label.
			var outer := [Vector2(0, 0.004), Vector2(0.026, 0.0), Vector2(0.026, 0.0), Vector2(0.03, 0.005), Vector2(0.03, 0.09), Vector2(0.026, 0.105), Vector2(0.014, 0.113), Vector2(0.011, 0.12), Vector2(0.011, 0.132), Vector2(0.011, 0.132), Vector2(0.0135, 0.135), Vector2(0.0135, 0.14), Vector2(0.0135, 0.14), Vector2(0.0115, 0.142)]
			vessel(k, I, outer, 0.0028, AMBER, AMBER_DRINK, 0.09, 28)
			cork(k, I, 0.0088, 0.142, 0.014)
			label(k, I, 0.03, 0.03, 0.075, "parch", 0.38)
			return Vector3(0, 0.06, 0)
		"iodine", "elixir_nightsight", "eye_drops":
			# A dropper bottle: a squat bottle, a screw collar and a rubber bulb.
			var glass := AMBER
			var liquid := IODINE
			if t == "elixir_nightsight":
				glass = Color(0.12, 0.08, 0.2, 0.55)
				liquid = VIOLET
			elif t == "eye_drops":
				glass = Color(0.92, 0.94, 0.95, 0.2)
				liquid = WATER
			var outer := [Vector2(0, 0.003), Vector2(0.018, 0.0), Vector2(0.018, 0.0), Vector2(0.021, 0.004), Vector2(0.021, 0.055), Vector2(0.017, 0.065), Vector2(0.009, 0.069), Vector2(0.009, 0.074)]
			vessel(k, I, outer, 0.0022, glass, liquid, 0.05, 24)
			if t == "eye_drops":
				lathe(k, "pv_plastic", I, _curve([Vector2(0.011, 0.068), Vector2(0.011, 0.084), Vector2(0.011, 0.084), Vector2(0.006, 0.09), Vector2(0.0025, 0.108), Vector2(0, 0.11)], 3), 20, Color(0.95, 0.95, 0.93))
			else:
				lathe(k, "pv_rubber" if t == "iodine" else "pv_tin", I, PackedVector2Array([Vector2(0.011, 0.066), Vector2(0.011, 0.079), Vector2(0.011, 0.079), Vector2(0, 0.079)]), 20, Color(0.1, 0.1, 0.1) if t == "iodine" else Color(0.75, 0.6, 0.3), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.04 * pow(absf(sin(a * 14.0)), 4.0))
				lathe(k, "pv_rubber", I, _curve([Vector2(0.006, 0.079), Vector2(0.0075, 0.088), Vector2(0.0072, 0.1), Vector2(0.004, 0.106), Vector2(0, 0.107)], 3), 16, Color(0.08, 0.07, 0.07))
			label(k, I, 0.021, 0.015, 0.045, "white" if t == "eye_drops" else "parch", 0.4)
			return Vector3(0, 0.035, 0)
		"gun_oil":
			# A square clear bottle of golden oil.
			var square := func(a: float, _t: float, _p: Vector3) -> float:
				return 1.0 / pow(pow(absf(cos(a)), 8.0) + pow(absf(sin(a)), 8.0), 1.0 / 8.0)
			var outer := [Vector2(0, 0.003), Vector2(0.022, 0.0), Vector2(0.022, 0.0), Vector2(0.025, 0.004), Vector2(0.025, 0.07), Vector2(0.021, 0.079), Vector2(0.011, 0.083), Vector2(0.009, 0.088), Vector2(0.009, 0.096), Vector2(0.009, 0.096), Vector2(0.011, 0.098), Vector2(0.011, 0.103), Vector2(0.011, 0.103), Vector2(0.0095, 0.104)]
			vessel(k, I, outer, 0.0025, CLEAR, OIL, 0.062, 40, square)
			cork(k, I, 0.0068, 0.104, 0.012)
			k.box("pv_label_parch", Transform3D(Basis.IDENTITY, Vector3(0, 0.035, 0.0256)), Vector3(0.034, 0.036, 0.0008))
			return Vector3(0, 0.04, 0)
		# Potions ---------------------------------------------------------------------
		"health_potion", "potion_health_minor", "potion_health_greater", "holy_water", "tonic_warmth", "elixir_swiftness":
			# A round-bottomed flask: a ball of glass, a narrow neck, a cork.
			var liquid := BLOOD_RED
			var r := 0.04
			var neck := 0.0095
			var neck_len := 0.045
			match t:
				"potion_health_minor":
					r = 0.036
				"potion_health_greater":
					r = 0.044
					neck_len = 0.04
				"holy_water":
					liquid = WATER
					r = 0.038
				"tonic_warmth":
					liquid = AMBER_DRINK
					r = 0.042
					neck = 0.011
					neck_len = 0.03
				"elixir_swiftness":
					liquid = GOLDEN
					r = 0.034
					neck = 0.009
					neck_len = 0.055
			var outer: Array = [Vector2(0, 0.0), Vector2(r * 0.5, 0.0015), Vector2(r * 0.5, 0.0015)]
			for i in range(1, 10):
				var phi := lerpf(0.55, PI - 0.25, i / 9.0)
				outer.append(Vector2(sin(phi) * r, r - cos(phi) * r))
			var top := 2.0 * r - r * 0.04 + neck_len
			outer.append_array([Vector2(neck, 2.0 * r - r * 0.06), Vector2(neck, top - 0.004), Vector2(neck, top - 0.004), Vector2(neck + 0.0022, top - 0.002), Vector2(neck + 0.0022, top), Vector2(neck + 0.0022, top), Vector2(neck + 0.0005, top + 0.001)])
			vessel(k, I, outer, 0.0026, CLEAR, liquid, r * 1.25, 30)
			if t == "holy_water":
				# A silver stopper topped with a small cross.
				lathe(k, "metal", I, _curve([Vector2(0, top - 0.015), Vector2(neck - 0.0024, top - 0.015), Vector2(neck - 0.0024, top), Vector2(neck + 0.003, top + 0.002), Vector2(neck + 0.003, top + 0.006), Vector2(0.004, top + 0.012), Vector2(0, top + 0.013)], 2), 16, Color(0.85, 0.85, 0.88))
				k.box("metal", I.translated(Vector3(0, top + 0.026, 0)), Vector3(0.004, 0.028, 0.004), Color(0.85, 0.85, 0.88))
				k.box("metal", I.translated(Vector3(0, top + 0.031, 0)), Vector3(0.016, 0.004, 0.004), Color(0.85, 0.85, 0.88))
			else:
				cork(k, I, neck - 0.0026, top + 0.001, 0.013)
			if t == "potion_health_greater":
				# A brass collar at the neck.
				lathe(k, "gold", I, _curve([Vector2(neck + 0.0005, 2.0 * r - 0.004), Vector2(neck + 0.004, 2.0 * r + 0.001), Vector2(neck + 0.0025, 2.0 * r + 0.008), Vector2(neck + 0.0025, 2.0 * r + 0.008), Vector2(neck + 0.0005, 2.0 * r + 0.009)], 2), 20, Color(0.9, 0.7, 0.35))
			if t == "tonic_warmth" or t == "potion_health_minor":
				twine(k, I, neck, 2.0 * r + 0.004, 3)
			# Held round the bulb, the neck standing up out of the hand.
			return Vector3(0, r, 0)
		"stamina_potion", "empty_vial", "antidote", "tonic_cooling", "cryo_vial":
			# A slim vial or tall bottle, corked.
			var liquid := LEAF_GREEN
			var r := 0.0115
			var h := 0.085
			match t:
				"empty_vial":
					liquid = Color(0, 0, 0, 0)
					r = 0.013
					h = 0.07
				"antidote":
					liquid = CHARTREUSE
					r = 0.018
					h = 0.075
				"tonic_cooling":
					liquid = ICE_BLUE
					r = 0.016
					h = 0.1
				"cryo_vial":
					liquid = Color(0.3, 0.6, 0.95, 0.75)
					r = 0.014
					h = 0.075
			var outer := [Vector2(0, 0.0), Vector2(r * 0.7, 0.0008), Vector2(r, 0.004), Vector2(r, h * 0.82), Vector2(r * 0.72, h * 0.9), Vector2(r * 0.68, h - 0.003), Vector2(r * 0.68, h - 0.003), Vector2(r * 0.68 + 0.0018, h - 0.0015), Vector2(r * 0.68 + 0.0018, h), Vector2(r * 0.68 + 0.0018, h), Vector2(r * 0.68, h + 0.0008)]
			vessel(k, I, outer, 0.0016 if r < 0.015 else 0.0022, CLEAR if t != "tonic_cooling" else AQUA, liquid, h * 0.68, 22)
			if t == "cryo_vial":
				# Steel end caps on a sealed sample tube.
				for e in [[-0.004, 0.012], [h - 0.006, 0.014]]:
					lathe(k, "pv_tin", I, _curve([Vector2(0, e[0]), Vector2(r + 0.0025, e[0]), Vector2(r + 0.0025, e[0]), Vector2(r + 0.0025, e[0] + e[1]), Vector2(r + 0.0025, e[0] + e[1]), Vector2(0, e[0] + e[1])], 1), 20, Color(0.7, 0.72, 0.75))
			else:
				cork(k, I, r * 0.68 - 0.0016, h + 0.0008, 0.01, 0.016)
			if t == "antidote":
				# A paper tag on a string round the neck.
				twine(k, I, r * 0.7, h * 0.86, 1)
				k.box("pv_label_parch", Transform3D(Basis(Vector3.FORWARD, -0.5), Vector3(r + 0.016, h * 0.62, 0.004)), Vector3(0.02, 0.03, 0.0006))
			return Vector3(0, h * 0.4, 0)
		"elixir_strength", "potion_stamina_greater":
			# A heavy faceted flask: few, flat sides catch the light.
			var liquid := Color(0.6, 0.12, 0.05, 0.85) if t == "elixir_strength" else GOLDEN
			var segs := 8 if t == "elixir_strength" else 28
			var outer := [Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.044, 0.016), Vector2(0.048, 0.034), Vector2(0.04, 0.056), Vector2(0.016, 0.07), Vector2(0.011, 0.075), Vector2(0.011, 0.09), Vector2(0.011, 0.09), Vector2(0.0135, 0.092), Vector2(0.0135, 0.097), Vector2(0.0135, 0.097), Vector2(0.0115, 0.098)]
			vessel(k, I, outer, 0.0028, CLEAR, liquid, 0.05, segs)
			if t == "potion_stamina_greater":
				# Brass filigree bands over the glass.
				for y in [0.02, 0.048]:
					var rr := _radius_at(_curve(outer, 3), y) + 0.0012
					var pts := PackedVector3Array()
					var rad := PackedFloat32Array()
					for s in 33:
						var a := TAU * s / 32.0
						pts.append(Vector3(cos(a) * rr, y + 0.002 * sin(a * 6.0), sin(a) * rr))
						rad.append(0.0016)
					tube(k, "gold", I, pts, rad, 6, Color(0.85, 0.65, 0.3), false)
				lathe(k, "gold", I, _curve([Vector2(0, 0.096), Vector2(0.0085, 0.096), Vector2(0.0085, 0.096), Vector2(0.015, 0.1), Vector2(0.01, 0.112), Vector2(0.004, 0.118), Vector2(0, 0.12)], 2), 16, Color(0.85, 0.65, 0.3))
			else:
				cork(k, I, 0.0087, 0.098, 0.012)
				# A pewter medallion hung on the front.
				k.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.0465)), 0.011, 0.011, 0.003, 16, true, 0.0, 1, Color(0.7, 0.7, 0.72))
			return Vector3(0, 0.035, 0)
		# Jugs, jars, tins -------------------------------------------------------------
		"milk":
			# A glazed earthenware jug with a pinched spout and a strap handle, milk inside.
			var spout := func(a: float, t2: float, _p: Vector3) -> float:
				return 1.0 + 0.32 * smoothstep(0.8, 1.0, t2) * pow(maxf(0.0, cos(a)), 6.0)
			var prof := _curve([Vector2(0, 0.0), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.04, 0.012), Vector2(0.046, 0.05), Vector2(0.04, 0.09), Vector2(0.031, 0.115), Vector2(0.034, 0.135), Vector2(0.034, 0.135), Vector2(0.03, 0.136), Vector2(0.028, 0.13), Vector2(0.03, 0.11), Vector2(0.036, 0.08), Vector2(0.034, 0.02), Vector2(0, 0.012)], 3)
			var glaze := Color(0.5, 0.28, 0.16)
			lathe(k, "pv_glaze", I, prof, 32, func(p: Vector3, _a: float, t2: float) -> Color: return glaze.darkened(0.2 * _nz(p, 40.0) + (0.25 if t2 < 0.05 else 0.0)), spout)
			lathe(k, "pv_soft", I, PackedVector2Array([Vector2(0, 0.112), Vector2(0.031, 0.112)]), 24, Color(0.96, 0.95, 0.9))
			tube(k, "pv_glaze", I, PackedVector3Array([Vector3(-0.033, 0.122, 0), Vector3(-0.055, 0.12, 0), Vector3(-0.064, 0.095, 0), Vector3(-0.058, 0.06, 0), Vector3(-0.043, 0.04, 0)]), PackedFloat32Array([0.006, 0.0065, 0.0065, 0.006, 0.0055]), 8, glaze)
			return Vector3(-0.06, 0.085, 0)
		"mead":
			# A glass jug of golden mead with a loop handle and a cork.
			var outer := [Vector2(0, 0.008), Vector2(0.03, 0.002), Vector2(0.03, 0.002), Vector2(0.045, 0.012), Vector2(0.05, 0.04), Vector2(0.046, 0.075), Vector2(0.026, 0.1), Vector2(0.017, 0.112), Vector2(0.017, 0.125), Vector2(0.017, 0.125), Vector2(0.02, 0.128), Vector2(0.02, 0.134), Vector2(0.02, 0.134), Vector2(0.0175, 0.136)]
			vessel(k, I, outer, 0.0032, Color(0.55, 0.42, 0.25, 0.14), HONEY, 0.08, 32)
			cork(k, I, 0.0135, 0.136, 0.012)
			tube(k, "pv_glass", I, PackedVector3Array([Vector3(-0.017, 0.12, 0), Vector3(-0.035, 0.122, 0), Vector3(-0.05, 0.105, 0), Vector3(-0.052, 0.08, 0), Vector3(-0.046, 0.065, 0)]), PackedFloat32Array([0.005, 0.0055, 0.0055, 0.005, 0.0045]), 10, Color(0.6, 0.5, 0.3, 0.25))
			return Vector3(0, 0.05, 0)
		"honey", "jam", "pickles":
			# A wide glass jar, filled, its mouth tied over with cloth (or a tin lid).
			var fill_col := HONEY
			var cloth_col := Color(0.86, 0.78, 0.62)
			if t == "jam":
				fill_col = Color(0.42, 0.04, 0.12, 0.96)
				cloth_col = Color(0.8, 0.72, 0.58)
			elif t == "pickles":
				fill_col = Color(0.72, 0.74, 0.35, 0.35)
			var outer := [Vector2(0, 0.003), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.038, 0.005), Vector2(0.039, 0.065), Vector2(0.035, 0.075), Vector2(0.032, 0.08), Vector2(0.032, 0.088), Vector2(0.032, 0.088), Vector2(0.034, 0.09), Vector2(0.034, 0.094), Vector2(0.034, 0.094), Vector2(0.032, 0.095)]
			vessel(k, I, outer, 0.0028, CLEAR, fill_col, 0.078 if t != "jam" else 0.072, 32)
			if t == "pickles":
				# Gherkins standing in brine, behind the glass.
				for i in 7:
					var a := TAU * i / 7.0 + 0.3
					var rr := 0.02 if i % 2 == 0 else 0.012
					var gx := Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), 0.12), Vector3(cos(a) * rr, 0.036, sin(a) * rr))
					lathe(k, "pv_skin", gx, _sphere(0.009, 8, 3.2), 10, func(p: Vector3, _a2: float, _t2: float) -> Color: return Color(0.32, 0.4, 0.12).darkened(0.25 * absf(_nz(p, 300.0))), func(a2: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.1 * _nz(p * 3.0 + Vector3(a2, 0, 0), 200.0))
				lathe(k, "pv_tin", I, _curve([Vector2(0.0355, 0.086), Vector2(0.0355, 0.098), Vector2(0.0355, 0.098), Vector2(0.033, 0.1), Vector2(0, 0.1)], 2), 32, Color(0.72, 0.62, 0.38), func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + (0.012 * pow(absf(sin(a * 30.0)), 2.0) if t2 < 0.4 else 0.0))
			else:
				# Cloth over the mouth, gathered under twine, the skirt hanging in folds.
				var skirt := func(a: float, t2: float, _p: Vector3) -> float:
					return 1.0 + (0.08 * (1.0 - t2) * (0.5 + 0.5 * sin(a * 9.0 + 1.3 * sin(a * 4.0)))) if t2 < 0.6 else 1.0
				lathe(k, "pv_cloth", I, _curve([Vector2(0.043, 0.066), Vector2(0.04, 0.078), Vector2(0.0345, 0.085), Vector2(0.0355, 0.092), Vector2(0.034, 0.098), Vector2(0.026, 0.1035), Vector2(0, 0.104)], 3), 40, cloth_col, skirt)
				twine(k, I, 0.0345, 0.083, 2)
			if t == "honey":
				# A wooden dipper resting in the jar.
				tube(k, "pv_wood", I, PackedVector3Array([Vector3(0.0, 0.07, 0.0), Vector3(0.012, 0.14, 0.004)]), PackedFloat32Array([0.003, 0.0035]), 8, Color(0.6, 0.42, 0.24))
			return Vector3(0, 0.045, 0)
		"beans_can", "stew_tin":
			# A tinplate can: rolled rims top and bottom, ribs round the body, a paper label.
			var ribs := func(_a: float, t2: float, _p: Vector3) -> float:
				return 1.0 - (0.012 * pow(absf(sin(t2 * PI * 9.0)), 6.0) if t2 > 0.12 and t2 < 0.88 else 0.0)
			var r := 0.037
			var h := 0.11 if t == "beans_can" else 0.075
			if t == "stew_tin":
				r = 0.05
			var tin := Color(0.72, 0.72, 0.7)
			var rusty := func(p: Vector3, _a: float, _t: float) -> Color: return tin.lerp(Color(0.45, 0.28, 0.16), clampf(_nz(p, 60.0) * 1.4 - 0.25, 0.0, 0.7))
			var top_y := h if t == "stew_tin" else h - 0.002
			lathe(k, "pv_tin", I, _curve([Vector2(0, 0.003), Vector2(r - 0.002, 0.003), Vector2(r - 0.002, 0.003), Vector2(r + 0.0015, 0.0), Vector2(r + 0.0015, 0.0), Vector2(r + 0.0018, 0.004), Vector2(r, 0.006), Vector2(r, h - 0.006), Vector2(r + 0.0018, h - 0.004), Vector2(r + 0.0015, h), Vector2(r + 0.0015, h), Vector2(r - 0.002, h - 0.002), Vector2(r - 0.002, h - 0.002), Vector2(r - 0.003, top_y - 0.003)] + ([Vector2(0, top_y - 0.003)] if t == "stew_tin" else [Vector2(r - 0.003, h * 0.75), Vector2(r - 0.003, h * 0.75), Vector2(0, h * 0.75)]), 2), 36, rusty, ribs)
			if t == "beans_can":
				# Opened: beans in sauce, and the lid bent back on its hinge.
				lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0, h - 0.012), Vector2(r - 0.003, h - 0.011)]), 32, Color(0.55, 0.2, 0.08))
				var rb := RandomNumberGenerator.new()
				rb.seed = 11
				for i in 24:
					var a := rb.randf() * TAU
					var d := sqrt(rb.randf()) * (r - 0.008)
					lathe(k, "pv_glossy", Transform3D(Basis(Vector3.UP, rb.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(cos(a) * d, h - 0.0115, sin(a) * d)), _sphere(0.004, 5, 1.6), 8, Color(0.62, 0.26, 0.1))
				lathe(k, "pv_tin", Transform3D(Basis(Vector3.FORWARD, -1.9), Vector3(-r, h, 0)) * Transform3D(Basis.IDENTITY, Vector3(r, 0, 0)), PackedVector2Array([Vector2(0, 0.0), Vector2(r - 0.002, 0.0), Vector2(r - 0.002, 0.0), Vector2(r - 0.001, 0.0015)]), 32, tin, func(a: float, _t2: float, _p: Vector3) -> float: return 1.0 + 0.04 * sin(a * 7.0))
				label(k, I, r, 0.012, h - 0.012, "beans", 1.0, 0.5)
			else:
				label(k, I, r, 0.01, h - 0.01, "red", 0.75, 0.25)
			return Vector3(0, h * 0.5, 0)
		"energy_drink":
			# A slim aluminium can, painted, with a necked top and a ring pull.
			var r := 0.0265
			var paint := func(p: Vector3, a: float, _t: float) -> Color:
				if p.y < 0.012 or p.y > 0.14:
					return Color(0.78, 0.8, 0.82)
				return Color(0.1, 0.62, 0.6) if fposmod(a / TAU + p.y * 5.0, 1.0) < 0.16 else Color(0.08, 0.085, 0.09)
			lathe(k, "pv_paint", I, _curve([Vector2(0, 0.006), Vector2(0.018, 0.0015), Vector2(0.022, 0.0), Vector2(0.022, 0.0), Vector2(r, 0.008), Vector2(r, 0.138), Vector2(0.022, 0.15), Vector2(0.0215, 0.153), Vector2(0.0215, 0.153), Vector2(0.0205, 0.151), Vector2(0, 0.151)], 3), 36, paint)
			k.box("pv_tin", Transform3D(Basis.IDENTITY, Vector3(0.004, 0.1515, 0)), Vector3(0.016, 0.001, 0.008), Color(0.8, 0.8, 0.82))
			return Vector3(0, 0.07, 0)
		"tea_tin":
			# A square tea caddy with a lid, its paint worn through to tin at the edges.
			var square := func(a: float, _t: float, _p: Vector3) -> float:
				return 1.0 / pow(pow(absf(cos(a)), 10.0) + pow(absf(sin(a)), 10.0), 0.1)
			var paint := Color(0.42, 0.33, 0.22)
			var worn := func(p: Vector3, a: float, _t: float) -> Color: return paint.lerp(Color(0.7, 0.68, 0.62), clampf(pow(absf(sin(a * 2.0)), 18.0) * 2.0 + _nz(p, 80.0) - 0.3, 0.0, 1.0))
			lathe(k, "pv_paint", I, PackedVector2Array([Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.075), Vector2(0.03, 0.075), Vector2(0, 0.075)]), 48, worn, square)
			lathe(k, "pv_paint", I, PackedVector2Array([Vector2(0.0312, 0.065), Vector2(0.0312, 0.082), Vector2(0.0312, 0.082), Vector2(0.026, 0.084), Vector2(0, 0.084)]), 48, worn, square)
			return Vector3(0, 0.04, 0)
		"antirad", "painkillers":
			# An amber pill bottle with a white child-proof cap.
			var outer := [Vector2(0, 0.002), Vector2(0.02, 0.0), Vector2(0.02, 0.0), Vector2(0.021, 0.004), Vector2(0.021, 0.065), Vector2(0.019, 0.068), Vector2(0.019, 0.07)]
			vessel(k, I, outer, 0.0015, Color(0.62, 0.3, 0.05, 0.5), Color(0, 0, 0, 0), 0.0, 28)
			var rp := RandomNumberGenerator.new()
			rp.seed = 3
			for i in 16:
				var a := rp.randf() * TAU
				var d := sqrt(rp.randf()) * 0.012
				lathe(k, "pv_plastic", Transform3D(Basis(Vector3(rp.randf(), 0, rp.randf()).normalized(), rp.randf() * PI), Vector3(cos(a) * d, 0.006 + i * 0.0022, sin(a) * d)), _sphere(0.0045, 6, 0.5), 10, Color(0.93, 0.9, 0.82))
			lathe(k, "pv_plastic", I, _curve([Vector2(0.0215, 0.064), Vector2(0.0225, 0.066), Vector2(0.0225, 0.08), Vector2(0.0225, 0.08), Vector2(0.021, 0.082), Vector2(0, 0.082)], 2), 40, Color(0.95, 0.95, 0.93), func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + (0.025 * pow(absf(sin(a * 24.0)), 3.0) if t2 < 0.75 else 0.0))
			label(k, I, 0.021, 0.012, 0.05, "white", 0.7)
			return Vector3(0, 0.035, 0)
		"water_canteen":
			# A round, flat canteen in a felt cover, a steel neck and screw cap, strap loops.
			var body := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.55)), Vector3(0, 0.07, 0))
			var felt := Color(0.55, 0.5, 0.38)
			lathe(k, "pv_cloth", body, _curve([Vector2(0, -0.06), Vector2(0.05, -0.052), Vector2(0.07, -0.025), Vector2(0.074, 0.0), Vector2(0.07, 0.025), Vector2(0.05, 0.052), Vector2(0, 0.06)], 3), 32, func(p: Vector3, _a: float, _t: float) -> Color: return felt.darkened(0.15 * _nz(p, 50.0)))
			# The seam where the cover is stitched round the rim.
			var seam := PackedVector3Array()
			var sr := PackedFloat32Array()
			for s in 41:
				var a := TAU * s / 40.0
				seam.append(Vector3(cos(a) * 0.0745, 0.07 + sin(a) * 0.0745, 0))
				sr.append(0.0028)
			tube(k, "pv_leather", I, seam, sr, 6, Color(0.36, 0.24, 0.14), false)
			lathe(k, "pv_tin", I, _curve([Vector2(0.011, 0.14), Vector2(0.011, 0.152), Vector2(0.011, 0.152), Vector2(0.0135, 0.153), Vector2(0.0135, 0.165), Vector2(0.0135, 0.165), Vector2(0, 0.166)], 2), 24, Color(0.6, 0.6, 0.58), func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + (0.04 * pow(absf(sin(a * 12.0)), 3.0) if t2 > 0.4 else 0.0))
			for sx in [-1.0, 1.0]:
				var loop := PackedVector3Array()
				var lr := PackedFloat32Array()
				for s in 9:
					var a := PI * s / 8.0
					loop.append(Vector3(sx * (0.05 + 0.011 * sin(a)), 0.128 + 0.011 * cos(a), 0))
					lr.append(0.0022)
				tube(k, "pv_tin", I, loop, lr, 6, Color(0.55, 0.55, 0.52))
			return Vector3(0, 0.15, 0)
		"waterskin":
			# A stitched leather bag, plump with water, a horn neck stopped with a cork.
			var plump := func(a: float, t2: float, p: Vector3) -> float:
				return (1.0 + 0.06 * _nz(p, 30.0)) * (1.0 - 0.35 * pow(absf(sin(a)), 2.0) * smoothstep(0.3, 0.9, t2))
			var hide := Color(0.4, 0.24, 0.12)
			var bag := Transform3D(Basis(Vector3.FORWARD, 0.35), Vector3(0, 0.0, 0))
			lathe(k, "pv_leather", bag, _curve([Vector2(0, 0.0), Vector2(0.05, 0.01), Vector2(0.075, 0.05), Vector2(0.07, 0.1), Vector2(0.04, 0.14), Vector2(0.018, 0.16), Vector2(0.016, 0.172), Vector2(0, 0.172)], 4), 30, func(p: Vector3, _a: float, _t: float) -> Color: return hide.darkened(0.2 * _nz(p, 25.0)), plump)
			lathe(k, "pv_bone", bag, PackedVector2Array([Vector2(0.015, 0.165), Vector2(0.015, 0.19), Vector2(0.015, 0.19), Vector2(0.0105, 0.19)]), 16, Color(0.82, 0.75, 0.6))
			cork(k, bag, 0.0105, 0.19, 0.014)
			return bag * Vector3(0, 0.12, 0)
		"coffee_pot":
			# A speckled enamel coffee pot: wide base, tapered body, spout, handle, lid knob.
			var enamel := Color(0.36, 0.38, 0.4)
			var speck := func(p: Vector3, _a: float, _t: float) -> Color: return enamel.lightened(0.6) if _nz(p, 700.0) > 0.42 else enamel.darkened(0.1 * _nz(p, 40.0))
			lathe(k, "pv_glaze", I, _curve([Vector2(0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.058, 0.006), Vector2(0.054, 0.04), Vector2(0.042, 0.11), Vector2(0.038, 0.135), Vector2(0.038, 0.135), Vector2(0.035, 0.14), Vector2(0.025, 0.152), Vector2(0.008, 0.156), Vector2(0.008, 0.156), Vector2(0.01, 0.164), Vector2(0.006, 0.17), Vector2(0, 0.171)], 3), 32, speck)
			tube(k, "pv_glaze", I, PackedVector3Array([Vector3(0.048, 0.035, 0), Vector3(0.065, 0.06, 0), Vector3(0.078, 0.095, 0), Vector3(0.088, 0.12, 0)]), PackedFloat32Array([0.011, 0.008, 0.006, 0.005]), 10, enamel)
			tube(k, "pv_glaze", I, PackedVector3Array([Vector3(-0.04, 0.125, 0), Vector3(-0.07, 0.12, 0), Vector3(-0.08, 0.085, 0), Vector3(-0.065, 0.05, 0), Vector3(-0.05, 0.04, 0)]), PackedFloat32Array([0.005, 0.0055, 0.0055, 0.005, 0.005]), 8, enamel)
			return Vector3(-0.077, 0.085, 0)
	return _food(k, t)

## Fruit, vegetables, bread, meat and cooked dishes.
static func _food(k: MeshKit, t: String) -> Variant:
	var I := Transform3D.IDENTITY
	match t:
		"apple":
			var red := Color(0.62, 0.05, 0.06)
			var gold := Color(0.86, 0.66, 0.2)
			var col := func(p: Vector3, a: float, t2: float) -> Color:
				# Red streaked over yellow, yellower round the base, a darker flush on top.
				var streak := _nz(Vector3(cos(a) * 3.0, t2 * 0.6, sin(a) * 3.0), 2.5) * 0.5 + 0.5
				var c := gold.lerp(red, clampf(streak * 1.3 + t2 * 0.4 - 0.2, 0.0, 1.0))
				return c.darkened(0.15 * smoothstep(0.7, 1.0, t2)).lerp(Color(0.95, 0.85, 0.55), 0.6 if _nz(p, 900.0) > 0.55 else 0.0)
			var lumpy := func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.03 * sin(a * 5.0 + 0.7) + 0.025 * _nz(p, 40.0)
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.009), Vector2(0.008, 0.004), Vector2(0.02, 0.001), Vector2(0.034, 0.008), Vector2(0.0405, 0.026), Vector2(0.041, 0.043), Vector2(0.036, 0.062), Vector2(0.022, 0.072), Vector2(0.01, 0.07), Vector2(0, 0.063)], 4), 32, col, lumpy)
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.062, 0), Vector3(0.001, 0.074, 0), Vector3(0.004, 0.085, 0.001)]), PackedFloat32Array([0.0022, 0.0018, 0.0016]), 6, Color(0.32, 0.22, 0.12))
			leaf(k, Transform3D(Basis(Vector3.FORWARD, -1.0) * Basis(Vector3.UP, 0.4), Vector3(0.003, 0.078, 0)), 0.05, 0.024, Color(0.2, 0.42, 0.1), 0.25)
			return Vector3(0, 0.035, 0)
		"pear":
			var col := func(p: Vector3, a: float, t2: float) -> Color:
				var c := Color(0.72, 0.72, 0.24).lerp(Color(0.85, 0.75, 0.3), 0.5 + 0.5 * sin(a))
				c = c.lerp(Color(0.76, 0.38, 0.16), 0.3 * smoothstep(0.2, 0.8, sin(a + 1.0)) * (1.0 - t2))
				# Russet freckles.
				return c.lerp(Color(0.45, 0.32, 0.16), 0.7 if _nz(p, 800.0) > 0.45 else 0.0)
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.006), Vector2(0.018, 0.001), Vector2(0.034, 0.01), Vector2(0.042, 0.03), Vector2(0.038, 0.05), Vector2(0.026, 0.068), Vector2(0.019, 0.083), Vector2(0.013, 0.096), Vector2(0, 0.101)], 4), 32, col, func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.03 * _nz(p, 30.0) + 0.02 * sin(a * 3.0))
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.098, 0), Vector3(0.003, 0.11, 0), Vector3(0.009, 0.12, 0.002)]), PackedFloat32Array([0.0024, 0.002, 0.0017]), 6, Color(0.3, 0.2, 0.1))
			leaf(k, Transform3D(Basis(Vector3.FORWARD, -0.9), Vector3(0.006, 0.115, 0)), 0.045, 0.022, Color(0.22, 0.44, 0.12), 0.3)
			return Vector3(0, 0.04, 0)
		"carrot":
			var col := func(p: Vector3, _a: float, t2: float) -> Color:
				var ring := pow(absf(sin(t2 * 70.0 + _nz(p, 30.0) * 2.0)), 20.0)
				return Color(0.93, 0.45, 0.08).darkened(0.35 * ring + 0.1 * _nz(p, 60.0))
			lathe(k, "pv_veg", I, _curve([Vector2(0, 0.0), Vector2(0.004, 0.02), Vector2(0.009, 0.06), Vector2(0.014, 0.11), Vector2(0.0165, 0.15), Vector2(0.015, 0.168), Vector2(0.008, 0.174), Vector2(0, 0.175)], 4), 20, col, func(_a: float, t2: float, p: Vector3) -> float: return 1.0 + 0.05 * _nz(p, 50.0) - 0.04 * pow(absf(sin(t2 * 70.0)), 20.0))
			for i in 6:
				var a := TAU * i / 6.0
				var lean := Vector3(cos(a), 0, sin(a)) * (0.012 + 0.006 * (i % 2))
				var stem := PackedVector3Array([Vector3(0, 0.172, 0), Vector3(0, 0.2, 0) + lean, Vector3(0, 0.23, 0) + lean * 2.5])
				tube(k, "pv_leaf", I, stem, PackedFloat32Array([0.0018, 0.0013, 0.0008]), 5, Color(0.28, 0.5, 0.15), false)
				for j in 3:
					var at: Vector3 = stem[1].lerp(stem[2], j / 3.0)
					leaf(k, Transform3D(Basis(Vector3.UP, a + j) * Basis(Vector3.FORWARD, 0.9), at), 0.022, 0.012, Color(0.25, 0.5, 0.14), 0.4, 4)
			return Vector3(0, 0.12, 0)
		"potato":
			var col := func(p: Vector3, _a: float, _t: float) -> Color:
				var c := Color(0.68, 0.52, 0.32).darkened(0.15 * _nz(p, 60.0))
				return c.darkened(0.4) if _nz(p + Vector3(5, 0, 0), 90.0) > 0.5 else c
			var lumps := func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.12 * _nz(p, 18.0) - 0.04 * smoothstep(0.45, 0.55, _nz(p + Vector3(5, 0, 0), 90.0))
			lathe(k, "pv_veg", Transform3D(Basis.from_scale(Vector3(1.0, 1.35, 0.82)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.035, 0)), _sphere(0.035, 14), 24, col, lumps)
			return Vector3(0, 0.035, 0)
		"onion":
			var col := func(p: Vector3, a: float, t2: float) -> Color:
				var vein := absf(sin(a * 22.0 + _nz(p, 20.0) * 3.0))
				return Color(0.72, 0.42, 0.14).lerp(Color(0.85, 0.6, 0.3), vein * 0.5).darkened(0.25 * smoothstep(0.85, 1.0, t2))
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.002), Vector2(0.012, 0.004), Vector2(0.032, 0.02), Vector2(0.038, 0.036), Vector2(0.032, 0.056), Vector2(0.016, 0.072), Vector2(0.005, 0.086), Vector2(0.0025, 0.1), Vector2(0, 0.104)], 4), 30, col, func(a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.025 * sin(a * 3.0) + 0.02 * _nz(p, 30.0))
			for i in 9:
				var a := TAU * i / 9.0
				tube(k, "pv_veg", I, PackedVector3Array([Vector3(cos(a) * 0.004, 0.003, sin(a) * 0.004), Vector3(cos(a) * 0.01, -0.004, sin(a) * 0.01), Vector3(cos(a + 0.4) * 0.016, -0.007, sin(a + 0.4) * 0.016)]), PackedFloat32Array([0.0009, 0.0007, 0.0004]), 4, Color(0.82, 0.74, 0.6), false)
			return Vector3(0, 0.04, 0)
		"cabbage":
			var green := Color(0.3, 0.44, 0.22)
			lathe(k, "pv_veg", I, _sphere(0.055, 12, 0.92), 24, Color(0.55, 0.68, 0.38), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.04 * _nz(p, 20.0))
			# Outer leaves cupped round the head, veined and loose at their edges.
			var veined := func(_p: Vector3, a2: float, t2: float) -> Color:
				var vein := pow(absf(sin(a2 * 18.0)), 30.0)
				return green.lerp(Color(0.78, 0.86, 0.62), vein * 0.7 + t2 * 0.1)
			var frilly := func(a2: float, t2: float, _p: Vector3) -> float: return 1.0 + 0.06 * sin(a2 * 30.0) * t2
			for i in 7:
				var a := TAU * i / 7.0 + 0.4 * (i % 2)
				var tilt := 0.1 + 0.1 * (i % 3)
				var lx := Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, tilt), Vector3(0, -0.045, 0))
				lathe(k, "pv_leaf", lx, _curve([Vector2(0.004, 0.0), Vector2(0.04, 0.012), Vector2(0.062, 0.045), Vector2(0.064, 0.075), Vector2(0.05, 0.1)], 3), 10, veined, frilly, Vector2(0.0, 0.32))
			return Vector3(0, 0.0, 0)
		"pumpkin":
			var ribbed := func(a: float, _t: float, _p: Vector3) -> float: return 0.9 + 0.1 * pow(absf(sin(a * 5.0)), 0.6)
			var col := func(p: Vector3, a: float, _t: float) -> Color: return Color(0.92, 0.45, 0.07).darkened(0.3 * (1.0 - pow(absf(sin(a * 5.0)), 0.4)) + 0.08 * _nz(p, 30.0))
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.012), Vector2(0.04, 0.0), Vector2(0.085, 0.025), Vector2(0.095, 0.06), Vector2(0.08, 0.1), Vector2(0.03, 0.115), Vector2(0, 0.105)], 4), 60, col, ribbed)
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0.002, 0.118, 0), Vector3(0.01, 0.132, 0.003)]), PackedFloat32Array([0.009, 0.007, 0.006]), 7, Color(0.4, 0.36, 0.18))
			return Vector3(0, 0.055, 0)
		"corn":
			var kernels := func(a: float, t2: float, _p: Vector3) -> float:
				return 1.0 + 0.1 * pow(absf(sin(a * 8.0)) * absf(sin(t2 * PI * 26.0 + floor(a * 16.0 / PI) * 0.8)), 0.6)
			var col := func(_p: Vector3, a: float, t2: float) -> Color:
				var k2 := pow(absf(sin(a * 8.0)) * absf(sin(t2 * PI * 26.0 + floor(a * 16.0 / PI) * 0.8)), 0.6)
				return Color(0.62, 0.42, 0.08).lerp(Color(0.98, 0.8, 0.18), k2)
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.0), Vector2(0.02, 0.006), Vector2(0.022, 0.05), Vector2(0.02, 0.14), Vector2(0.012, 0.17), Vector2(0, 0.176)], 4), 64, col, kernels)
			# Husk leaves peeled back from the base.
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				leaf(k, Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, -0.32), Vector3(cos(a) * 0.012, 0.0, sin(a) * 0.012)), 0.17, 0.05, Color(0.62, 0.68, 0.36), -0.15, 7)
			tube(k, "pv_veg", I, PackedVector3Array([Vector3(0, 0.005, 0), Vector3(0, -0.03, 0)]), PackedFloat32Array([0.011, 0.009]), 8, Color(0.6, 0.6, 0.38))
			return Vector3(0, -0.015, 0)
		"grapes", "wild_berries", "glowberry":
			# A bunch of berries on a branching stem; grapes with a dusty bloom.
			var big := t == "grapes"
			var rr := 0.0095 if big else 0.0065
			var berry := Color(0.25, 0.1, 0.3) if big else Color(0.3, 0.06, 0.18)
			if t == "glowberry":
				berry = Color(0.42, 0.2, 0.7)
			var count := 26 if big else 12
			var rb := RandomNumberGenerator.new()
			rb.seed = WHash.str_hash(t)
			var stem := Color(0.42, 0.36, 0.18)
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.002, 0.02, 0), Vector3(0.006, 0.035, 0)]), PackedFloat32Array([0.002, 0.0018, 0.0015]), 5, stem)
			for i in count:
				var f := float(i) / count
				var depth := f * (0.1 if big else 0.06)
				var spread := (1.0 - f * 0.7) * (0.028 if big else 0.024)
				var a := rb.randf() * TAU
				var at := Vector3(cos(a) * spread * sqrt(rb.randf()), -depth - rr, sin(a) * spread * sqrt(rb.randf()))
				tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, -depth * 0.8, 0), at + Vector3(0, rr, 0)]), PackedFloat32Array([0.0008, 0.0006]), 4, stem, false)
				var c := berry.lightened(rb.randf_range(-0.05, 0.12))
				lathe(k, "pv_skin", Transform3D(Basis(Vector3.UP, rb.randf() * TAU), at), _sphere(rr * rb.randf_range(0.9, 1.1), 8, 1.1 if big else 1.0), 12, func(p: Vector3, _a: float, t2: float) -> Color: return c.lerp(Color(0.6, 0.58, 0.72), 0.25 * clampf(_nz(p, 500.0) + 0.3, 0.0, 1.0) if big else 0.0).darkened(0.2 * (1.0 - t2)))
			leaf(k, Transform3D(Basis(Vector3.FORWARD, -1.2), Vector3(0.004, 0.025, 0)), 0.07 if big else 0.04, 0.06 if big else 0.022, Color(0.25, 0.45, 0.12), 0.2)
			return Vector3(0, 0.01, 0)
		"mushroom", "fungus_alien":
			# A pair of ceps: fat pale stems, brown caps paler underneath.
			for e in [[Vector3(0, 0, 0), 1.0, 0.0], [Vector3(0.035, 0, 0.01), 0.7, 0.3]]:
				var s: float = e[1]
				var at := Transform3D(Basis(Vector3.FORWARD, e[2]).scaled(Vector3.ONE * s), e[0])
				lathe(k, "pv_veg", at, _curve([Vector2(0, 0.0), Vector2(0.016, 0.002), Vector2(0.022, 0.02), Vector2(0.016, 0.05), Vector2(0.012, 0.065), Vector2(0, 0.066)], 3), 18, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.9, 0.86, 0.75).darkened(0.12 * _nz(p, 120.0) + 0.1 * (1.0 - t2)))
				lathe(k, "pv_skin", at, _curve([Vector2(0, 0.058), Vector2(0.03, 0.058), Vector2(0.036, 0.064), Vector2(0.034, 0.075), Vector2(0.02, 0.088), Vector2(0, 0.092)], 4), 26, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.86, 0.76, 0.5) if t2 < 0.18 else Color(0.45, 0.26, 0.13).darkened(0.15 * _nz(p, 40.0)), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.05 * _nz(p, 20.0))
			return Vector3(0, 0.03, 0)
		"egg":
			for e in [[Vector3(0, 0, 0), 0.2], [Vector3(0.045, 0, 0.01), -0.4]]:
				var xf := Transform3D(Basis(Vector3.FORWARD, e[1]), e[0])
				lathe(k, "pv_shell", xf, _curve([Vector2(0, 0.0), Vector2(0.016, 0.004), Vector2(0.021, 0.02), Vector2(0.019, 0.04), Vector2(0.011, 0.054), Vector2(0, 0.058)], 4), 24, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.76, 0.52, 0.34).darkened(0.25 if _nz(p, 1200.0) > 0.5 else 0.06 * _nz(p, 80.0)))
			return Vector3(0.02, 0.028, 0)
		"bread":
			# A crusty loaf lying along X: domed, flat underneath, slashed across the top
			# where the crust burst paler in the oven, browned on its ridges, floured.
			var cut := func(a: float, p: Vector3) -> float:
				# Local +X is the underside; the slashes run slantwise over the top.
				var top := smoothstep(-0.2, -0.75, cos(a))
				var u := p.y * 1.25 + (a - PI) * 0.3
				return exp(-pow((fposmod(u * 1.6, 1.0) - 0.5) / 0.11, 2.0)) * top * (1.0 - smoothstep(0.7, 0.86, absf(p.y)))
			var col := func(p: Vector3, a: float, _t: float) -> Color:
				var g: float = cut.call(a, p)
				var c := Color(0.68, 0.4, 0.15).darkened(0.3 * smoothstep(-0.3, -0.9, cos(a)) * (0.6 + 0.4 * _nz(p, 5.0)))
				# The ear along each slash bakes darkest; inside it the crumb shows pale.
				c = c.darkened(0.3 * smoothstep(0.05, 0.3, g) * (1.0 - smoothstep(0.4, 0.7, g)))
				c = c.lerp(Color(0.9, 0.74, 0.46), smoothstep(0.55, 0.9, g))
				return c.lerp(Color(0.9, 0.85, 0.76), clampf(_nz(p, 3.0) * 1.2 - 0.1, 0.0, 0.45) * smoothstep(-0.1, -0.8, cos(a)))
			var shape := func(a: float, _t: float, p: Vector3) -> float:
				return (1.0 - 0.2 * cut.call(a, p) + 0.02 * _nz(p, 6.0)) * (1.0 - 0.32 * smoothstep(0.25, 0.95, cos(a)))
			var prof := PackedVector2Array()
			for v in _sphere(1.0, 30):
				prof.append(Vector2(pow(v.x, 0.6), v.y))
			lathe(k, "pv_crust", Transform3D(Basis.from_scale(Vector3(0.13, 0.06, 0.06)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.045, 0)), prof, 56, col, shape)
			return Vector3(0, 0.045, 0)
		"travel_bread":
			# A round dark rye loaf, its floury crust cracked all over as it rose.
			var crack := func(p: Vector3) -> float: return smoothstep(0.82, 0.95, 1.0 - absf(_nz(p, 3.5))) * smoothstep(-0.2, 0.4, p.y)
			var col := func(p: Vector3, _a: float, _t: float) -> Color:
				var c := Color(0.36, 0.21, 0.11).darkened(0.2 * _nz(p, 6.0))
				c = c.lerp(Color(0.8, 0.72, 0.6), clampf(_nz(p, 5.0) * 1.2, 0.0, 0.5) * smoothstep(0.2, 0.8, p.y))
				return c.lerp(Color(0.62, 0.46, 0.3), crack.call(p))
			var prof := PackedVector2Array()
			for v in _sphere(1.0, 26):
				prof.append(Vector2(v.x, maxf(v.y, -0.45)))
			lathe(k, "pv_crust", Transform3D(Basis.from_scale(Vector3(0.08, 0.06, 0.08)), Vector3(0, 0.027, 0)), prof, 48, col, func(_a: float, _t: float, p: Vector3) -> float: return 1.0 - 0.05 * crack.call(p) + 0.03 * _nz(p, 4.0))
			return Vector3(0, 0.03, 0)
		"raw_meat", "steak", "synth_steak", "meat_xeno":
			# A thick steak: deep red muscle finely marbled, a cap of fat along one side.
			var synth := t == "synth_steak"
			var outline := func(a: float, _t: float, p: Vector3) -> float:
				if synth:
					return 1.0 / pow(pow(absf(cos(a)), 6.0) + pow(absf(sin(a)), 6.0), 1.0 / 6.0)
				return 1.0 + 0.12 * sin(a * 2.0 + 0.5) + 0.06 * _nz(p, 2.5)
			var prof := PackedVector2Array()
			for v in _sphere(1.0, 18):
				prof.append(Vector2(v.x, clampf(v.y, -0.55, 0.55)))
			var xf := Transform3D(Basis.from_scale(Vector3(0.075, 0.03, 0.055)), Vector3.ZERO)
			var tint := Color.WHITE if t != "meat_xeno" else Color(0.8, 0.6, 1.0)
			lathe(k, "pv_meat_synth" if synth else "pv_marbled", xf, prof, 48, func(p: Vector3, _a: float, _t: float) -> Color: return tint.darkened(0.12 * _nz(p, 3.0)), outline)
			if not synth:
				# The fat: a band round part of the edge, just proud of the meat.
				var band := PackedVector2Array()
				for v in _sphere(1.03, 18):
					if absf(v.y) < 0.5:
						band.append(Vector2(v.x, v.y))
				lathe(k, "pv_fat", xf, band, 20, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.94, 0.88, 0.76).darkened(0.1 * _nz(p, 20.0)), outline, Vector2(0.28, 0.5))
			return Vector3.ZERO
		"cooked_meat":
			# A roast leg: a browned, glistening joint on a bone.
			var col := func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.5, 0.26, 0.1).darkened(0.35 * clampf(_nz(p, 40.0) + 0.2, 0.0, 1.0)).lerp(Color(0.75, 0.48, 0.22), 0.3 * t2)
			lathe(k, "pv_roast", Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), _curve([Vector2(0, 0.0), Vector2(0.03, 0.01), Vector2(0.045, 0.04), Vector2(0.04, 0.075), Vector2(0.022, 0.1), Vector2(0.012, 0.11), Vector2(0, 0.112)], 4), 28, col, func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.08 * _nz(p, 25.0))
			tube(k, "pv_bone", I, PackedVector3Array([Vector3(0, 0.155, 0), Vector3(0, 0.0, 0)]), PackedFloat32Array([0.008, 0.007]), 10, Color(0.92, 0.88, 0.78))
			lathe(k, "pv_bone", Transform3D(Basis.IDENTITY, Vector3(0, -0.012, 0)), _sphere(0.012, 8, 0.8), 12, Color(0.92, 0.88, 0.78), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.2 * cos(a * 2.0))
			return Vector3(0, 0.01, 0)
		"ham":
			# A cured ham lying on its side: a smoked, glossy leg narrowing to the shank
			# bone, and at the wide end a cut face of pink meat ringed with fat.
			var lie := Transform3D(Basis(Vector3.FORWARD, PI * 0.5 - 0.25), Vector3(0.09, 0.07, 0))
			var col := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.48, 0.24, 0.1).darkened(0.3 * clampf(_nz(p, 30.0) + 0.3, 0.0, 1.0))
			var leg := func(a: float, _t: float, p: Vector3) -> float: return (1.0 + 0.06 * _nz(p, 15.0)) * (1.0 - 0.2 * pow(absf(sin(a)), 2.0))
			lathe(k, "pv_roast", lie, _curve([Vector2(0.011, 0.0), Vector2(0.03, 0.03), Vector2(0.06, 0.1), Vector2(0.075, 0.15), Vector2(0.07, 0.185)], 4), 32, col, leg)
			var face := func(p: Vector3, _a: float, t2: float) -> Color:
				if Vector2(p.x, p.z).length() < 0.009:
					return Color(0.93, 0.88, 0.76)
				return Color(0.86, 0.42, 0.4).darkened(0.12 * _nz(p, 50.0)).lerp(Color(0.97, 0.93, 0.85), 1.0 - smoothstep(0.06, 0.16, t2))
			lathe(k, "pv_meat", lie, PackedVector2Array([Vector2(0.07, 0.185), Vector2(0.035, 0.1852), Vector2(0, 0.1855)]), 32, face, leg)
			tube(k, "pv_bone", lie, PackedVector3Array([Vector3(0, 0.03, 0), Vector3(0, -0.03, 0)]), PackedFloat32Array([0.009, 0.008]), 10, Color(0.9, 0.85, 0.72))
			return lie * Vector3(0, -0.01, 0)
		"chicken_roast":
			var col := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.78, 0.48, 0.18).darkened(0.35 * clampf(_nz(p, 35.0) + 0.15, 0.0, 1.0))
			lathe(k, "pv_roast", Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.3)), Vector3(0, 0.05, 0)), _sphere(0.06, 14), 28, col, func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.05 * _nz(p, 20.0))
			for sx in [-1.0, 1.0]:
				var leg := Transform3D(Basis(Vector3.RIGHT, -1.1) * Basis(Vector3.FORWARD, sx * 0.35), Vector3(sx * 0.04, 0.035, 0.04))
				lathe(k, "pv_roast", leg, _curve([Vector2(0, 0.0), Vector2(0.022, 0.01), Vector2(0.026, 0.03), Vector2(0.016, 0.06), Vector2(0.007, 0.075), Vector2(0, 0.078)], 3), 16, col)
				lathe(k, "pv_bone", leg, PackedVector2Array([Vector2(0.004, 0.07), Vector2(0.004, 0.09), Vector2(0.006, 0.094), Vector2(0, 0.097)]), 8, Color(0.9, 0.85, 0.72))
				lathe(k, "pv_roast", Transform3D(Basis(Vector3.FORWARD, sx * 1.9), Vector3(sx * 0.05, 0.07, -0.03)), _sphere(0.016, 6, 2.0), 10, col)
			return Vector3(0, 0.05, 0)
		"sausage":
			# A string of three links, glossy and browned, pinched where they're twisted.
			var pts := PackedVector3Array()
			var rad := PackedFloat32Array()
			for i in 49:
				var f := i / 48.0
				var a := f * 2.6 - 1.3
				pts.append(Vector3(sin(a) * 0.09, 0.0, cos(a) * 0.09 - 0.09))
				var link := fposmod(f * 3.0, 1.0)
				rad.append(0.013 * pow(sin(PI * link), 0.25) + 0.002)
			tube(k, "pv_roast", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), pts, rad, 12, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.48, 0.2, 0.1).darkened(0.25 * _nz(p, 60.0)))
			return Vector3.ZERO
		"salted_meat":
			# A slab of salt pork: layers of lean and fat, coarse salt crusted on top.
			var y := 0.0
			var rs := RandomNumberGenerator.new()
			rs.seed = 5
			for i in 5:
				var h := [0.012, 0.006, 0.01, 0.005, 0.012][i] as float
				var fat := i % 2 == 1 or i == 4
				var c := Color(0.8, 0.7, 0.58) if fat else Color(0.48, 0.13, 0.11)
				k.box("pv_fat" if fat else "pv_meat", Transform3D(Basis(Vector3.UP, rs.randf_range(-0.03, 0.03)), Vector3(rs.randf_range(-0.002, 0.002), y + h * 0.5, 0)), Vector3(0.1, h, 0.065), c.darkened(rs.randf_range(0.0, 0.1)))
				y += h
			for i in 26:
				k.box("pv_soft", Transform3D(Basis(Vector3(rs.randf(), rs.randf(), rs.randf()).normalized(), rs.randf() * PI), Vector3(rs.randf_range(-0.045, 0.045), y, rs.randf_range(-0.03, 0.03))), Vector3.ONE * rs.randf_range(0.003, 0.006), Color(0.97, 0.97, 0.95))
			return Vector3(0, 0.02, 0)
		"jerky":
			var rj := RandomNumberGenerator.new()
			rj.seed = 9
			for i in 4:
				var pts := PackedVector3Array()
				var rad := PackedFloat32Array()
				var x := (i - 1.5) * 0.016
				for s in 9:
					var f := s / 8.0
					pts.append(Vector3(x + 0.006 * sin(f * 7.0 + i), f * 0.13, 0.004 * cos(f * 5.0 + i * 2.0)))
					rad.append(0.006 + 0.002 * sin(f * 9.0 + i))
				tube(k, "pv_roast", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.35)) * Basis(Vector3.FORWARD, rj.randf_range(-0.2, 0.2)), Vector3.ZERO), pts, rad, 6, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.32, 0.08, 0.05).lerp(Color(0.5, 0.22, 0.12), clampf(_nz(p, 80.0), 0.0, 1.0)))
			return Vector3(0, 0.04, 0)
		"fish_raw", "fish_cooked":
			# A whole fish on its side: dark back, silver belly, fins and a glassy eye;
			# grilled, it is browned with char lines across it.
			var cooked := t == "fish_cooked"
			var col := func(p: Vector3, a: float, _t: float) -> Color:
				var c: Color
				if cooked:
					c = Color(0.62, 0.42, 0.2).darkened(0.25 * _nz(p, 40.0))
					if absf(fposmod(p.y * 40.0 + p.z * 25.0, 1.0) - 0.5) < 0.05 and cos(a) < 0.3:
						c = Color(0.15, 0.08, 0.04)
				else:
					# Local +X is the belly.
					c = Color(0.22, 0.3, 0.34).lerp(Color(0.84, 0.86, 0.84), smoothstep(-0.35, 0.25, cos(a)))
					c = c.darkened(0.35 * smoothstep(0.4, 0.75, _nz(p, 120.0)) * smoothstep(0.1, -0.5, cos(a)))
				return c
			var prof := _curve([Vector2(0, 0.0), Vector2(0.012, 0.006), Vector2(0.026, 0.035), Vector2(0.032, 0.08), Vector2(0.026, 0.13), Vector2(0.01, 0.17), Vector2(0.006, 0.18), Vector2(0, 0.182)], 4)
			lathe(k, "pv_fish", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.42)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.09, 0, 0)), prof, 28, col)
			# Tail and fins: thin, ribbed, a little translucent at the edges.
			var fin := Color(0.4, 0.42, 0.4) if not cooked else Color(0.35, 0.2, 0.1)
			for e in [[Vector3(0.082, 0, 0), PI * 0.5, 0.05, 0.055], [Vector3(-0.03, 0.026, 0), 0.9, 0.05, 0.022], [Vector3(0.03, -0.018, 0), PI - 0.6, 0.025, 0.014]]:
				leaf(k, Transform3D(Basis(Vector3.FORWARD, e[1]), e[0]), e[2], e[3], fin, 0.0, 4)
			for sz in [-1.0, 1.0]:
				lathe(k, "pv_glossy", Transform3D(Basis(Vector3.RIGHT, sz * PI * 0.5), Vector3(-0.07, 0.006, sz * 0.0105)), _sphere(0.0045, 6, 0.6), 10, Color(0.05, 0.05, 0.05) if not cooked else Color(0.85, 0.82, 0.75))
			return Vector3(0.05, 0, 0)
		"stew", "porridge", "soup_veg", "chili", "food_bio", "food_void":
			# A turned wooden bowl (a tin one for chili), filled.
			var tin := t == "chili"
			var outer := _curve([Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.033, 0.004), Vector2(0.055, 0.02), Vector2(0.068, 0.045), Vector2(0.07, 0.05), Vector2(0.07, 0.05)], 3)
			var inner := _inset(outer, 0.005 if not tin else 0.0015, 0.008)
			var shell := PackedVector2Array(outer)
			shell.append(Vector2(0.065 if not tin else 0.0685, 0.05))
			shell.append_array(inner)
			shell.append(Vector2(0, 0.008))
			var wood := Color(0.55, 0.36, 0.2)
			lathe(k, "pv_tin" if tin else "pv_wood", I, shell, 36, Color(0.42, 0.42, 0.44) if tin else wood)
			var fill := {"stew": Color(0.42, 0.2, 0.08), "porridge": Color(0.74, 0.6, 0.4), "soup_veg": Color(0.66, 0.52, 0.16), "chili": Color(0.45, 0.12, 0.05), "food_bio": Color(0.3, 0.45, 0.2), "food_void": Color(0.18, 0.12, 0.25)}[t] as Color
			var surf := 0.04
			var r_s := _radius_at(inner, surf) - 0.001
			lathe(k, "pv_crumb" if t == "porridge" else "pv_glossy", I, PackedVector2Array([Vector2(r_s, surf), Vector2(0, surf + (0.004 if t == "porridge" else 0.0))]), 32, func(p: Vector3, _a: float, _t: float) -> Color: return fill.darkened(0.12 * _nz(p, 80.0)))
			var bits := {"stew": [Color(0.72, 0.38, 0.1), Color(0.9, 0.75, 0.35), Color(0.35, 0.15, 0.08)], "soup_veg": [Color(0.9, 0.45, 0.1), Color(0.3, 0.6, 0.2), Color(0.95, 0.85, 0.5)], "chili": [Color(0.5, 0.15, 0.08), Color(0.6, 0.2, 0.1)], "food_bio": [Color(0.5, 0.7, 0.3)], "food_void": [Color(0.4, 0.3, 0.5)]}
			if bits.has(t):
				var rc := RandomNumberGenerator.new()
				rc.seed = WHash.str_hash(t)
				var cs: Array = bits[t]
				for i in 14:
					var a := rc.randf() * TAU
					var d := sqrt(rc.randf()) * (r_s - 0.008)
					var c: Color = cs[i % cs.size()]
					var s := rc.randf_range(0.005, 0.009)
					if t == "chili":
						lathe(k, "pv_glossy", Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(cos(a) * d, surf, sin(a) * d)), _sphere(0.0045, 5, 1.6), 8, c)
					else:
						k.box("pv_soft", Transform3D(Basis(Vector3(rc.randf(), rc.randf(), rc.randf()).normalized(), rc.randf() * 1.5), Vector3(cos(a) * d, surf, sin(a) * d)), Vector3.ONE * s, c)
			return Vector3(0, 0.025, 0)
		"pie_meat", "pie_berry", "food_hive":
			# A pie in its fluted crust: the meat pie domed, glazed and vented; the berry
			# pie open under a lattice.
			var crimp := func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + 0.035 * sin(a * 28.0) * smoothstep(0.55, 0.8, t2)
			var crust := Color(0.82, 0.58, 0.28)
			var bake := func(p: Vector3, _a: float, t2: float) -> Color: return crust.darkened(0.3 * clampf(_nz(p, 30.0) + 0.3 * t2, 0.0, 1.0))
			lathe(k, "pv_crust", I, _curve([Vector2(0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.068, 0.032), Vector2(0.076, 0.038), Vector2(0.074, 0.044), Vector2(0.066, 0.04)], 3), 56, bake, crimp)
			if t == "pie_berry":
				lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0.066, 0.037), Vector2(0, 0.04)]), 32, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.3, 0.04, 0.12).lightened(0.15 * _nz(p, 120.0)))
				for i in 5:
					var o := (i - 2) * 0.024
					for dir in [0.0, PI * 0.5]:
						var len := 2.0 * sqrt(maxf(0.0, 0.066 * 0.066 - o * o))
						k.box("pv_crust", Transform3D(Basis(Vector3.UP, dir), Vector3(o, 0.043 + (0.002 if (i + int(dir > 0.0)) % 2 == 0 else 0.0), 0).rotated(Vector3.UP, dir)), Vector3(0.011, 0.004, len), crust.darkened(0.08))
			else:
				var top := Color(0.78, 0.5, 0.2) if t == "pie_meat" else Color(0.85, 0.62, 0.25)
				lathe(k, "pv_crust", I, _curve([Vector2(0.068, 0.04), Vector2(0.05, 0.058), Vector2(0.025, 0.066), Vector2(0, 0.068)], 3), 40, func(p: Vector3, _a: float, _t: float) -> Color: return top.darkened(0.25 * clampf(_nz(p, 25.0) + 0.2, 0.0, 1.0)), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.03 * _nz(p, 20.0))
				for i in 3:
					var a := TAU * i / 3.0
					k.box("pv_soft", Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.014, 0.067, sin(a) * 0.014)), Vector3(0.012, 0.0015, 0.0025), Color(0.3, 0.14, 0.06))
			return Vector3(0, 0.02, 0)
		"cheese_wheel_small", "cornbread":
			# A wheel with a wedge cut out (or a wedge cut from a round): rind outside,
			# the pale paste on the cut faces.
			var cheese := t == "cheese_wheel_small"
			var r := 0.075 if cheese else 0.09
			var h := 0.05 if cheese else 0.038
			var keep := Vector2(0.0, 0.85) if cheese else Vector2(0.0, 0.14)
			var rind := Color(0.85, 0.55, 0.15) if cheese else Color(0.66, 0.4, 0.13)
			var inside := Color(0.97, 0.8, 0.38) if cheese else Color(0.96, 0.78, 0.32)
			var prof := _curve([Vector2(0, 0.0), Vector2(r - 0.006, 0.0), Vector2(r, 0.006), Vector2(r + 0.002, h * 0.5), Vector2(r, h - 0.006), Vector2(r - 0.006, h), Vector2(0, h)], 3)
			lathe(k, "pv_crust" if not cheese else "pv_soft", I, prof, 48, func(p: Vector3, _a: float, t2: float) -> Color: return rind.darkened(0.15 * _nz(p, 40.0) + (0.15 if not cheese and t2 > 0.7 else 0.0)), null, keep)
			# The cut faces.
			for e in [keep.x, keep.y]:
				var a: float = TAU * e
				var d := Vector3(cos(a), 0, sin(a))
				var st := k._tool("pv_crumb")
				var nrm := Vector3(0, 1, 0).cross(d) * (1.0 if e == keep.x else -1.0)
				for i in prof.size() - 1:
					var p0 := Vector3(0, prof[i].y, 0)
					var q0 := d * prof[i].x + Vector3(0, prof[i].y, 0)
					var q1 := d * prof[i + 1].x + Vector3(0, prof[i + 1].y, 0)
					var p1 := Vector3(0, prof[i + 1].y, 0)
					var c := inside.darkened(0.06 * _nz(q0, 60.0))
					_tri(st, I, Basis.IDENTITY, [p0, q0, q1], [nrm, nrm, nrm], [c, c, c], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
					_tri(st, I, Basis.IDENTITY, [p0, q1, p1], [nrm, nrm, nrm], [c, c, c], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			return Vector3(0, h * 0.5, 0)
		"biscuit_hard":
			# Three square crackers stacked, pricked with docking holes, darker at the edges.
			var square := func(a: float, _t: float, _p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)), 12.0) + pow(absf(sin(a)), 12.0), 1.0 / 12.0)
			for i in 3:
				var xf := Transform3D(Basis(Vector3.UP, 0.15 * (i - 1)), Vector3(0.003 * i, i * 0.0105, -0.002 * i))
				lathe(k, "pv_crust", xf, _curve([Vector2(0, 0.0), Vector2(0.034, 0.0), Vector2(0.036, 0.004), Vector2(0.034, 0.009), Vector2(0, 0.0095)], 2), 48, func(p: Vector3, a: float, t2: float) -> Color: return Color(0.86, 0.7, 0.46).darkened(0.25 * smoothstep(0.25, 0.4, t2) * (1.0 - smoothstep(0.6, 0.75, t2)) + 0.08 * _nz(p, 90.0)), square)
				if i == 2:
					for gx in 4:
						for gz in 4:
							k.cylinder("pv_soft", xf * Transform3D.IDENTITY.translated(Vector3(-0.021 + gx * 0.014, 0.0093, -0.021 + gz * 0.014)), 0.0014, 0.0014, 0.0005, 6, true, 0.0, 1, Color(0.45, 0.32, 0.18))
			return Vector3(0, 0.015, 0)
		"pancakes":
			# A stack of flapjacks, golden on top, a pat of butter melting into syrup.
			var golden := func(p: Vector3, _a: float, t2: float) -> Color:
				var edge := smoothstep(0.3, 0.45, t2) * (1.0 - smoothstep(0.55, 0.7, t2))
				return Color(0.62, 0.36, 0.14).lerp(Color(0.95, 0.8, 0.5), edge).darkened(0.1 * _nz(p, 60.0))
			var wobbly := func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.03 * _nz(p, 20.0)
			for i in 5:
				var y := i * 0.009
				lathe(k, "pv_crust", Transform3D(Basis(Vector3.UP, i), Vector3(0.002 * sin(i * 2.0), y, 0.002 * cos(i * 3.0))), _curve([Vector2(0, 0.0), Vector2(0.056, 0.0005), Vector2(0.06, 0.0045), Vector2(0.056, 0.0088), Vector2(0, 0.009)], 2), 36, golden, wobbly)
			lathe(k, "pv_glossy", I, _curve([Vector2(0.058, 0.044), Vector2(0.05, 0.0462), Vector2(0, 0.0464)], 2), 36, Color(0.5, 0.22, 0.05), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.05 * sin(a * 5.0))
			k.box("pv_soft", Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 0.052, 0)), Vector3(0.018, 0.01, 0.018), Color(0.98, 0.88, 0.5))
			return Vector3(0, 0.02, 0)
		"egg_fried":
			for e in [[Vector3(0, 0, 0), 1.0], [Vector3(0.06, 0, 0.02), 0.85]]:
				var xf := Transform3D(Basis.from_scale(Vector3.ONE * e[1]), e[0])
				lathe(k, "pv_glossy", xf, _curve([Vector2(0, 0.0), Vector2(0.04, 0.0), Vector2(0.045, 0.002), Vector2(0.03, 0.004), Vector2(0, 0.005)], 2), 32, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.98, 0.97, 0.94).lerp(Color(0.8, 0.55, 0.25), 0.7 * smoothstep(0.3, 0.45, t2) * (1.0 - smoothstep(0.45, 0.6, t2)) * clampf(_nz(p, 60.0) + 0.5, 0.0, 1.0)), func(a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.15 * sin(a * 3.0 + e[1] * 5.0) + 0.1 * _nz(p, 15.0))
				lathe(k, "pv_glossy", xf * Transform3D.IDENTITY.translated(Vector3(-0.005, 0.004, 0.003)), _sphere(0.012, 8, 0.55), 18, Color(0.98, 0.58, 0.05))
			return Vector3(0.03, 0.0, 0)
		"apple_dried":
			for i in 3:
				var ring := PackedVector2Array()
				for s in 13:
					var a := TAU * s / 12.0
					ring.append(Vector2(0.024 + cos(a) * 0.012, sin(a) * 0.004))
				lathe(k, "pv_crumb", Transform3D(Basis(Vector3.RIGHT, 0.2 * i - 0.2), Vector3(i * 0.02, i * 0.006, -i * 0.01)), ring, 28, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.8, 0.62, 0.38).lerp(Color(0.5, 0.12, 0.08), smoothstep(0.35, 0.42, t2) * (1.0 - smoothstep(0.58, 0.65, t2))).darkened(0.1 * _nz(p, 80.0)), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.07 * sin(a * 4.0 + i))
			return Vector3(0.02, 0.005, 0)
	return null
