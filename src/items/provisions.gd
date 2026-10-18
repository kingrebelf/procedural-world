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
static var _liquid_shader: Shader

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
const CLEAR := Color(0.88, 0.94, 0.93, 0.04)
const GREEN := Color(0.14, 0.4, 0.18, 0.42)
const OLIVE := Color(0.1, 0.2, 0.07, 0.72)
const AMBER := Color(0.45, 0.2, 0.04, 0.55)
const BROWN_GLASS := Color(0.25, 0.1, 0.03, 0.72)
const AQUA := Color(0.62, 0.86, 0.84, 0.05)
# Liquids, alpha as how cloudy or deep they look.
const WINE := Color(0.3, 0.0, 0.02, 0.96)
const BLOOD_RED := Color(0.45, 0.01, 0.03, 0.94)
const LEAF_GREEN := Color(0.04, 0.36, 0.1, 0.9)
const GOLDEN := Color(0.7, 0.42, 0.04, 0.9)
const WATER := Color(0.82, 0.92, 0.96, 0.03)
const WHISKY := Color(0.46, 0.17, 0.01, 0.96)
const HONEY := Color(0.68, 0.33, 0.0, 0.96)
const COLA := Color(0.13, 0.04, 0.02, 0.96)
const VIOLET := Color(0.38, 0.08, 0.6, 0.86)
const CHARTREUSE := Color(0.4, 0.44, 0.07, 0.9)
const AMBER_DRINK := Color(0.55, 0.2, 0.02, 0.92)
const ICE_BLUE := Color(0.42, 0.68, 0.64, 0.5)
const OIL := Color(0.42, 0.28, 0.04, 0.95)
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
## midrib and curled back at the tip. `teeth` saws its edge into that many teeth.
static func leaf(k: MeshKit, xf: Transform3D, length: float, width: float, col: Color, curl := 0.3, segs := 6, teeth := 0, mat := "pv_leaf") -> void:
	var st := k._tool(mat)
	var nb := xf.basis.inverse().transposed()
	var rows: Array = []
	if teeth > 0:
		segs = maxi(segs, teeth * 2)
	for i in segs + 1:
		var t := float(i) / segs
		var w := sin(PI * pow(t, 0.8)) * width * 0.5
		if teeth > 0:
			w *= 1.0 - 0.3 * fposmod(t * teeth, 1.0) * smoothstep(0.05, 0.2, t)
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

## A flat paper label `w` by `h` centred at `at`, facing `n`, its picture the right way up.
static func decal(k: MeshKit, mat: String, xf: Transform3D, at: Vector3, n: Vector3, w: float, h: float, up := Vector3.UP) -> void:
	var z := n.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var c := [at - x * w * 0.5 - y * h * 0.5, at + x * w * 0.5 - y * h * 0.5, at - x * w * 0.5 + y * h * 0.5, at + x * w * 0.5 + y * h * 0.5]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
	var st := k._tool(mat)
	var nb := xf.basis.inverse().transposed()
	_tri(st, xf, nb, [c[0], c[1], c[2]], [z, z, z], [Color.WHITE, Color.WHITE, Color.WHITE], [uv[0], uv[1], uv[2]])
	_tri(st, xf, nb, [c[1], c[3], c[2]], [z, z, z], [Color.WHITE, Color.WHITE, Color.WHITE], [uv[1], uv[3], uv[2]])

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
	if priority == 0:
		# The liquid writes depth, so the glass drawn after it (the far wall, the floor of
		# the bottle) stays behind it instead of veiling it in white.
		if _liquid_shader == null:
			_liquid_shader = Shader.new()
			_liquid_shader.code = _glass_shader.code.replace("depth_draw_opaque", "depth_draw_always")
		m.shader = _liquid_shader
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
		# Crinkled foil: bright, but every crease catches the light differently.
		"pv_foil": m = _std(0.38, 0.7, "crinkle", 0.6, 24.0, 1.2, true)
		"pv_alu":
			# Printed aluminium: the paint has a lacquer shine over the metal.
			var s := _std(0.22, 0.75, "paint", 0.12, 12.0, 0.05)
			s.clearcoat_enabled = true
			s.clearcoat = 0.6
			m = s
		"pv_burlap":
			var s := _std(0.98, 0.0, "burlap", 0.5, 30.0, 1.0)
			if Materials.photo("fabric_linen", "detail") != null:
				s.albedo_texture = Materials.photo("fabric_linen", "detail")
				s.uv1_scale = Vector3.ONE * 8.0
			m = s
		"pv_coal": m = _std(0.55, 0.1, "coal", 0.5, 30.0, 1.0, true)
		"pv_leaf":
			var s := _std(0.55)
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			s.backlight_enabled = true
			s.backlight = Color(0.25, 0.35, 0.1)
			m = s
		"pv_petal":
			# Petals: thin and two-sided like a leaf, but no green light through them.
			var s := _std(0.9)
			s.metallic_specular = 0.15
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			var s := _std(0.32, 0.0, "fibre", 0.25, 26.0, 1.4)
			s.albedo_texture = _ramp_tex("marble", 0.04, [[0.0, Color(0.32, 0.03, 0.04)], [0.55, Color(0.5, 0.06, 0.07)], [0.78, Color(0.55, 0.1, 0.1)], [0.86, Color(0.9, 0.78, 0.72)], [1.0, Color(0.96, 0.9, 0.84)]], true)
			s.uv1_scale = Vector3.ONE * 9.0
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			m = s
		"pv_steak":
			# A raw steak's face: bold lobes of red lean parted by seams of white fat.
			var s := _std(0.34, 0.0, "fibre", 0.25, 26.0, 0.8)
			s.albedo_texture = _ramp_tex("steak", 0.012, [[0.0, Color(0.46, 0.05, 0.06)], [0.4, Color(0.6, 0.1, 0.1)], [0.47, Color(0.62, 0.12, 0.12)], [0.5, Color(0.92, 0.72, 0.68)], [0.53, Color(0.62, 0.12, 0.12)], [0.62, Color(0.58, 0.09, 0.1)], [0.68, Color(0.9, 0.7, 0.66)], [0.71, Color(0.56, 0.08, 0.09)], [1.0, Color(0.48, 0.06, 0.07)]], false)
			s.uv1_scale = Vector3.ONE * 2.5
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			m = s
		"pv_meat_synth":
			# Lab-grown: an even pink-red with faint growth lines.
			var s := _std(0.35, 0.0, "fibre", 0.2, 22.0, 0.3)
			s.albedo_texture = _ramp_tex("synth", 0.08, [[0.0, Color(0.42, 0.1, 0.11)], [1.0, Color(0.56, 0.17, 0.17)]], false)
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
			var s := _std(0.58, 0.0, "roast", 0.3, 16.0, 1.2, true)
			s.clearcoat_enabled = true
			s.clearcoat = 0.12
			s.clearcoat_roughness = 0.65
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
		"pv_board":
			# Sawn boards: the planks photo in grey under each board's own tint.
			var s := _std(0.78, 0.0, "woodgrain", 0.08, 10.0, 0.5)
			if Materials.photo("planks", "detail") != null:
				s.albedo_texture = Materials.photo("planks", "detail")
				s.uv1_scale = Vector3.ONE * 0.6
				if Materials.photo("planks", "normal") != null:
					s.normal_texture = Materials.photo("planks", "normal")
					s.normal_scale = 0.7
			m = s
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
	var crumple := func(a: float, t2: float, p: Vector3) -> float: return 1.0 + 0.05 * _nz(p, 70.0) + 0.03 * sin(a * 5.0 + t2 * 11.0)
	lathe(k, "pv_label_parch", scroll, _curve([Vector2(0.02, 0.0), Vector2(0.021, 0.05), Vector2(0.0205, 0.1), Vector2(0.0195, 0.15)], 4), 24, Color.WHITE, crumple)
	lathe(k, "pv_label_parch", scroll, _curve([Vector2(0.0195, 0.15), Vector2(0.0205, 0.1), Vector2(0.021, 0.05), Vector2(0.02, 0.0)], 4), 24, Color(0.85, 0.82, 0.75), crumple)
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
	# A blob of red sealing wax pressed over the ribbon on the upper side (-X).
	lathe(k, "pv_wax", scroll * Transform3D(_facing(Vector3.LEFT), Vector3(-0.0218, 0.079, 0.002)), _curve([Vector2(0.009, 0.0), Vector2(0.0088, 0.0024), Vector2(0.0072, 0.0038), Vector2(0.0055, 0.0032), Vector2(0, 0.0034)], 2), 16, Color(0.34, 0.03, 0.03), func(a2: float, _t: float, p: Vector3) -> float: return 1.0 + 0.12 * sin(a2 * 3.0 + 1.0) + 0.06 * _nz(p, 600.0))
	# Barnacles on the upper glass: little white volcanoes.
	for i in 11:
		var a := PI + r.randf_range(-0.8, 0.8)
		var y := r.randf_range(0.03, 0.16)
		var rr := 0.0445
		var at := Vector3(cos(a) * rr, y, sin(a) * rr)
		var out := Vector3(cos(a), 0, sin(a))
		var size := r.randf_range(0.0022, 0.0046)
		var shell := Color(0.8, 0.76, 0.66).darkened(r.randf_range(0.0, 0.2))
		# Pale ribbed plates round a dark slot at the top.
		var bc := func(_p: Vector3, _a: float, t2: float) -> Color: return shell if t2 < 0.62 else shell.darkened(0.75)
		lathe(k, "pv_shell", lie * Transform3D(_facing(out), at), PackedVector2Array([Vector2(size, 0.0), Vector2(size * 0.85, size * 0.18), Vector2(size * 0.55, size * 0.36), Vector2(size * 0.42, size * 0.4), Vector2(size * 0.42, size * 0.4), Vector2(size * 0.3, size * 0.28), Vector2(0, size * 0.24)]), 10, bc, func(a2: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.12 * absf(sin(a2 * 3.0)))
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
			# A plain bottle of clear glass full of deep red wine: straight sides, round
			# shoulders, a short neck with a rolled lip, and a cork pushed in proud.
			var outer := [Vector2(0, 0.01), Vector2(0.02, 0.004), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.0395, 0.007), Vector2(0.04, 0.12), Vector2(0.038, 0.142), Vector2(0.026, 0.158), Vector2(0.0145, 0.168), Vector2(0.0135, 0.2), Vector2(0.0135, 0.2), Vector2(0.0162, 0.203), Vector2(0.0162, 0.212), Vector2(0.0162, 0.212), Vector2(0.014, 0.214)]
			vessel(k, I, outer, 0.003, CLEAR, WINE, 0.17, 30)
			cork(k, I, 0.0108, 0.214, 0.018, 0.024)
			return Vector3(0, 0.08, 0)
		"empty_bottle":
			# A squat, thick-walled apothecary bottle of clear glass, wide in the body with a
			# short, wide neck and a heavy rolled lip, unstoppered: its cork lies beside it.
			var outer := [Vector2(0, 0.006), Vector2(0.03, 0.001), Vector2(0.03, 0.001), Vector2(0.039, 0.008), Vector2(0.04, 0.07), Vector2(0.036, 0.085), Vector2(0.024, 0.094), Vector2(0.018, 0.1), Vector2(0.018, 0.112), Vector2(0.018, 0.112), Vector2(0.0215, 0.115), Vector2(0.0215, 0.124), Vector2(0.0215, 0.124), Vector2(0.0185, 0.126)]
			vessel(k, I, outer, 0.0034, Color(0.88, 0.94, 0.93, 0.07), Color(0, 0, 0, 0), 0.0, 32)
			cork(k, Transform3D(Basis.IDENTITY, Vector3(0.065, -0.002, 0.02)), 0.0145, 0.024, 0.0, 0.024)
			return Vector3(0, 0.05, 0)
		"fire_bottle":
			# A green bottle of lamp oil with a rag stuffed in the neck.
			var outer := [Vector2(0, 0.012), Vector2(0.02, 0.004), Vector2(0.029, 0.0), Vector2(0.029, 0.0), Vector2(0.033, 0.006), Vector2(0.034, 0.12), Vector2(0.03, 0.15), Vector2(0.016, 0.172), Vector2(0.013, 0.19), Vector2(0.013, 0.215), Vector2(0.013, 0.215), Vector2(0.0152, 0.218), Vector2(0.0152, 0.226), Vector2(0.0152, 0.226), Vector2(0.013, 0.228)]
			vessel(k, I, outer, 0.003, GREEN, OIL, 0.12, 28)
			var rag := Color(0.78, 0.72, 0.6)
			tube(k, "pv_cloth", I, PackedVector3Array([Vector3(0, 0.19, 0), Vector3(0, 0.228, 0), Vector3(0.004, 0.245, 0.002), Vector3(0.015, 0.262, 0.006), Vector3(0.03, 0.27, 0.004), Vector3(0.045, 0.262, -0.002)]), PackedFloat32Array([0.009, 0.01, 0.012, 0.011, 0.008, 0.005]), 8, func(p: Vector3, _a: float, t2: float) -> Color: return rag.darkened(0.15 + 0.5 * t2 * t2 + 0.1 * _nz(p, 200.0)))
			return Vector3(0, 0.08, 0)
		"whiskey":
			# A flat-sided spirit flask of clear glass, its broad face to the front, full to
			# the square shoulders with deep amber whisky; a short neck and a cork.
			var square := func(a: float, _t: float, _p: Vector3) -> float:
				return 1.0 / pow(pow(absf(cos(a)), 6.0) + pow(absf(sin(a)) * 1.7, 6.0), 1.0 / 6.0)
			var outer := [Vector2(0, 0.004), Vector2(0.04, 0.0), Vector2(0.04, 0.0), Vector2(0.045, 0.006), Vector2(0.045, 0.14), Vector2(0.04, 0.155), Vector2(0.02, 0.166), Vector2(0.0125, 0.172), Vector2(0.0125, 0.192), Vector2(0.0125, 0.192), Vector2(0.015, 0.195), Vector2(0.015, 0.203), Vector2(0.015, 0.203), Vector2(0.013, 0.205)]
			vessel(k, I, outer, 0.003, CLEAR, WHISKY, 0.15, 40, square)
			cork(k, I, 0.0098, 0.205, 0.018)
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
			# A square bottle of clear glass, moulded with a pattern on its faces, full of
			# golden-brown oil, closed with a ribbed brass screw cap.
			var square := func(a: float, _t: float, p: Vector3) -> float:
				var sq := 1.0 / pow(pow(absf(cos(a)), 8.0) + pow(absf(sin(a)), 8.0), 1.0 / 8.0)
				# The moulded scrollwork stands a hair proud of the flat faces.
				return sq * (1.0 + 0.012 * clampf(_nz(p, 160.0) * 2.0, 0.0, 1.0) * (1.0 if p.y > 0.006 and p.y < 0.072 else 0.0))
			var outer := [Vector2(0, 0.003), Vector2(0.024, 0.0), Vector2(0.024, 0.0), Vector2(0.027, 0.004), Vector2(0.027, 0.074), Vector2(0.023, 0.082), Vector2(0.013, 0.087), Vector2(0.0105, 0.09), Vector2(0.0105, 0.1), Vector2(0.0105, 0.1)]
			vessel(k, I, outer, 0.0025, CLEAR, OIL, 0.08, 40, square)
			var brass := Color(0.55, 0.42, 0.22)
			lathe(k, "pv_tin", I, _curve([Vector2(0.0125, 0.091), Vector2(0.0128, 0.093), Vector2(0.0128, 0.109), Vector2(0.0128, 0.109), Vector2(0.0118, 0.111), Vector2(0, 0.1115)], 2), 40, func(p: Vector3, _a: float, _t: float) -> Color: return brass.darkened(0.3 * clampf(_nz(p, 200.0), 0.0, 1.0)), func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + (0.035 * pow(absf(sin(a * 18.0)), 3.0) if t2 < 0.8 else 0.0))
			return Vector3(0, 0.04, 0)
		# Potions ---------------------------------------------------------------------
		"health_potion", "potion_health_minor", "potion_health_greater", "holy_water", "elixir_swiftness":
			# A round-bottomed flask: a ball of glass, a narrow neck, a cork.
			var liquid := BLOOD_RED
			var r := 0.04
			var neck := 0.0095
			var neck_len := 0.045
			match t:
				"potion_health_minor":
					neck = 0.0085
				"potion_health_greater":
					r = 0.044
					neck_len = 0.04
				"holy_water":
					liquid = WATER
					r = 0.038
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
			var glass := CLEAR
			var fill := r * 1.25
			if t == "potion_health_minor":
				# A squat apothecary bottle: flat base, sloping shoulders, short neck, in
				# faintly green glass with a thinner, rosier draught.
				liquid = Color(0.5, 0.02, 0.04, 0.94)
				glass = Color(0.8, 0.92, 0.84, 0.03)
				top = 0.072
				outer = [Vector2(0, 0.004), Vector2(0.016, 0.0), Vector2(0.016, 0.0), Vector2(0.022, 0.003), Vector2(0.024, 0.01), Vector2(0.024, 0.032), Vector2(0.021, 0.042), Vector2(0.012, 0.05), Vector2(neck, 0.054), Vector2(neck, top - 0.004), Vector2(neck, top - 0.004), Vector2(neck + 0.0022, top - 0.002), Vector2(neck + 0.0022, top), Vector2(neck + 0.0022, top), Vector2(neck + 0.0005, top + 0.001)]
				fill = 0.043
				r = 0.024
			vessel(k, I, outer, 0.0026, glass, liquid, fill, 30)
			if t == "holy_water":
				# A silver stopper topped with a small cross.
				lathe(k, "metal", I, _curve([Vector2(0, top - 0.015), Vector2(neck - 0.0024, top - 0.015), Vector2(neck - 0.0024, top), Vector2(neck + 0.003, top + 0.002), Vector2(neck + 0.003, top + 0.006), Vector2(0.004, top + 0.012), Vector2(0, top + 0.013)], 2), 16, Color(0.85, 0.85, 0.88))
				k.box("metal", I.translated(Vector3(0, top + 0.026, 0)), Vector3(0.004, 0.028, 0.004), Color(0.85, 0.85, 0.88))
				k.box("metal", I.translated(Vector3(0, top + 0.031, 0)), Vector3(0.016, 0.004, 0.004), Color(0.85, 0.85, 0.88))
			else:
				cork(k, I, neck - 0.0026, top + 0.001, 0.013)
			if t == "potion_health_greater":
				# Gilt work: a collar of leaves round the neck, a point hanging down over the
				# glass at the front, a ring for the flask to stand on; a sprig of herbs tied on.
				var gilt := Color(0.95, 0.74, 0.36)
				lathe(k, "gold", I, _curve([Vector2(neck + 0.0005, 2.0 * r - 0.008), Vector2(neck + 0.006, 2.0 * r - 0.002), Vector2(neck + 0.004, 2.0 * r + 0.008), Vector2(neck + 0.0025, 2.0 * r + 0.014), Vector2(neck + 0.0025, 2.0 * r + 0.014), Vector2(neck + 0.0005, 2.0 * r + 0.015)], 2), 24, gilt, func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + 0.12 * pow(absf(sin(a * 4.0)), 3.0) * (1.0 - t2))
				lathe(k, "gold", Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 2.0 * r - 0.009, r * 0.62)), _curve([Vector2(0, -0.016), Vector2(0.005, -0.006), Vector2(0.007, 0.002), Vector2(0.004, 0.008), Vector2(0, 0.01)], 2), 4, gilt.lightened(0.05))
				lathe(k, "gold", I, _curve([Vector2(r * 0.42, -0.004), Vector2(r * 0.62, -0.004), Vector2(r * 0.62, -0.004), Vector2(r * 0.6, 0.004), Vector2(r * 0.5, 0.006), Vector2(r * 0.5, 0.006), Vector2(r * 0.42, 0.0)], 1), 32, gilt.darkened(0.1), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.03 * sin(a * 16.0))
				for i in 5:
					leaf(k, Transform3D(Basis(Vector3.FORWARD, 0.6 + 0.3 * i) * Basis(Vector3.UP, 0.3 * i - 0.6), Vector3(neck + 0.004, 2.0 * r + 0.004, 0.004)), 0.062 - 0.006 * i, 0.018, Color(0.12, 0.27, 0.08).lightened(0.03 * i), 0.2, 8, 8)
			if t == "elixir_swiftness":
				# A leather thong bound round the neck holds a long brown feather to the side.
				twine(k, I, neck, 2.0 * r + 0.006, 4, Color(0.4, 0.24, 0.12))
				var quill := Transform3D(Basis(Vector3.FORWARD, -0.35), Vector3(neck + 0.004, 2.0 * r + 0.012, 0.006))
				tube(k, "pv_bone", quill, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.002, -0.05, 0), Vector3(0.006, -0.1, 0)]), PackedFloat32Array([0.0012, 0.001, 0.0005]), 5, Color(0.85, 0.8, 0.7))
				leaf(k, quill * Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0.0, -0.02, 0.0005)), 0.085, 0.022, Color(0.28, 0.18, 0.1), 0.05, 8, 14)
			if t == "potion_health_minor":
				return Vector3(0, 0.062, 0)
			# Held by the neck, so the hand hides as little of the glass as it can.
			return Vector3(0, 2.0 * r + neck_len * 0.45, 0)
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
			var neck_r := r * 0.68
			if t == "tonic_cooling":
				# A tall bottle: sloping shoulders up into a long, narrow neck.
				neck_r = 0.0075
				outer = [Vector2(0, 0.0), Vector2(r * 0.7, 0.0008), Vector2(r, 0.004), Vector2(r, h * 0.55), Vector2(r * 0.8, h * 0.66), Vector2(neck_r, h * 0.76), Vector2(neck_r, h - 0.003), Vector2(neck_r, h - 0.003), Vector2(neck_r + 0.0018, h - 0.0015), Vector2(neck_r + 0.0018, h), Vector2(neck_r + 0.0018, h), Vector2(neck_r, h + 0.0008)]
			var glass := CLEAR
			if t == "tonic_cooling":
				glass = AQUA
			elif t == "stamina_potion":
				glass = Color(0.5, 0.85, 0.55, 0.08)
			var fill: float = {"stamina_potion": 0.86, "antidote": 0.8, "tonic_cooling": 0.62}.get(t, 0.68)
			vessel(k, I, outer, 0.0016 if r < 0.015 else 0.0022, glass, liquid, h * fill, 22)
			if t == "cryo_vial":
				# Steel end caps on a sealed sample tube.
				for e in [[-0.004, 0.012], [h - 0.006, 0.014]]:
					lathe(k, "pv_tin", I, _curve([Vector2(0, e[0]), Vector2(r + 0.0025, e[0]), Vector2(r + 0.0025, e[0]), Vector2(r + 0.0025, e[0] + e[1]), Vector2(r + 0.0025, e[0] + e[1]), Vector2(0, e[0] + e[1])], 1), 20, Color(0.7, 0.72, 0.75))
			else:
				cork(k, I, neck_r - 0.0016, h + 0.0008, 0.01, 0.016)
			if t == "tonic_cooling":
				# Twine at the neck holding a sprig of mint and a clear crystal.
				twine(k, I, neck_r, h * 0.8, 3, Color(0.5, 0.36, 0.22))
				for i in 3:
					leaf(k, Transform3D(Basis(Vector3.FORWARD, 0.5 + 0.45 * i) * Basis(Vector3.UP, 0.4 * i - 0.4), Vector3(neck_r + 0.002, h * 0.8, 0.004)), 0.038 - 0.004 * i, 0.022, Color(0.12, 0.32, 0.12).lightened(0.04 * i), 0.15, 8, 7)
				k.crystal("pv_glossy", Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(r + 0.006, h * 0.28, 0.008)), 0.007, 0.024, 6, 0.4, Color(0.82, 0.88, 0.92))
			if t == "antidote":
				# A paper tag on a string round the neck.
				twine(k, I, r * 0.7, h * 0.86, 1)
				for nz in [1.0, -1.0]:
					decal(k, "pv_label_parch", I, Vector3(r + 0.016, h * 0.62, 0.004 + nz * 0.0003), Vector3(0, 0, nz), 0.02, 0.03, Vector3(0.45, 1, 0))
			return Vector3(0, h * 0.4, 0)
		"elixir_strength", "potion_stamina_greater":
			# A heavy faceted flask: few, flat sides catch the light.
			# The elixir is cut glass, eight flat sides, full of a dark red-brown draught
			# under a pewter cap, a pewter medallion hung round its neck on a red cord. The
			# greater stamina draught is a round-bellied flask of orange-amber in a cage of
			# old silver scrollwork.
			var strong := t == "elixir_strength"
			var liquid := Color(0.26, 0.04, 0.0, 0.97) if strong else Color(0.76, 0.38, 0.0, 0.93)
			var segs := 8 if strong else 28
			var outer := [Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.044, 0.016), Vector2(0.048, 0.034), Vector2(0.04, 0.056), Vector2(0.016, 0.07), Vector2(0.011, 0.075), Vector2(0.011, 0.09), Vector2(0.011, 0.09), Vector2(0.0135, 0.092), Vector2(0.0135, 0.097), Vector2(0.0135, 0.097), Vector2(0.0115, 0.098)]
			if not strong:
				outer = [Vector2(0, 0.0), Vector2(0.02, 0.001), Vector2(0.02, 0.001), Vector2(0.033, 0.01), Vector2(0.04, 0.03), Vector2(0.038, 0.05), Vector2(0.026, 0.066), Vector2(0.012, 0.075), Vector2(0.011, 0.09), Vector2(0.011, 0.09), Vector2(0.0135, 0.092), Vector2(0.0135, 0.097), Vector2(0.0135, 0.097), Vector2(0.0115, 0.098)]
			vessel(k, I, outer, 0.0028, CLEAR, liquid, 0.062 if strong else 0.064, segs)
			var prof := _curve(outer, 3)
			if not strong:
				var silver := Color(0.6, 0.56, 0.5)
				var tarnish := func(p: Vector3, _a: float, _t: float) -> Color: return silver.darkened(0.35 * clampf(_nz(p, 150.0) + 0.3, 0.0, 1.0))
				# Bands round the belly and shoulder, and scrolled ribs up between them.
				for y in [0.008, 0.03, 0.056]:
					var rr := _radius_at(prof, y) + 0.0014
					var pts := PackedVector3Array()
					var rad := PackedFloat32Array()
					for s2 in 49:
						var a := TAU * s2 / 48.0
						pts.append(Vector3(cos(a) * rr, y + 0.0025 * sin(a * 8.0), sin(a) * rr))
						rad.append(0.0024)
					tube(k, "metal", I, pts, rad, 6, tarnish, false)
				for i in 8:
					var a0 := TAU * i / 8.0
					var pts := PackedVector3Array()
					var rad := PackedFloat32Array()
					for s2 in 13:
						var f := s2 / 12.0
						var y := lerpf(0.004, 0.07, f)
						var a := a0 + 0.22 * sin(f * TAU * 1.5)
						var rr := _radius_at(prof, y) + 0.0016
						pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
						rad.append(0.0021)
					tube(k, "metal", I, pts, rad, 5, tarnish, false)
				lathe(k, "metal", I, _curve([Vector2(0.0118, 0.074), Vector2(0.015, 0.078), Vector2(0.0142, 0.09), Vector2(0.0142, 0.09), Vector2(0.0118, 0.091)], 2), 20, tarnish, func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.05 * sin(a * 12.0))
				cork(k, I, 0.0087, 0.098, 0.013)
			else:
				# The pewter cap: a collar and a domed top with a ring.
				var pewter := Color(0.5, 0.5, 0.52)
				lathe(k, "metal", I, _curve([Vector2(0.0125, 0.074), Vector2(0.0145, 0.078), Vector2(0.0145, 0.1), Vector2(0.0145, 0.1), Vector2(0.012, 0.104), Vector2(0.006, 0.11), Vector2(0.006, 0.11), Vector2(0, 0.111)], 2), 16, func(p: Vector3, _a: float, _t: float) -> Color: return pewter.darkened(0.3 * clampf(_nz(p, 200.0), 0.0, 1.0)))
				ItemModels._torus(k, "metal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.114, 0)), 0.005, 0.0013, 12, 6, pewter)
				# The red cord round the neck and down to the medallion.
				twine(k, I, 0.0125, 0.076, 2, Color(0.55, 0.06, 0.05))
				for sx in [-1.0, 1.0]:
					tube(k, "pv_twine", I, PackedVector3Array([Vector3(sx * 0.013, 0.077, 0.004), Vector3(sx * 0.03, 0.062, 0.03), Vector3(sx * 0.008, 0.044, 0.047)]), PackedFloat32Array([0.0021, 0.0021, 0.0021]), 5, Color(0.55, 0.06, 0.05), false)
				k.cylinder("pv_paint", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.032, 0.0485)), 0.012, 0.012, 0.003, 18, true, 0.0, 1, Color(0.7, 0.7, 0.7))
				k.cylinder("pv_paint", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.032, 0.0505)), 0.009, 0.0085, 0.0015, 18, true, 0.0, 1, Color(0.55, 0.55, 0.56))
			return Vector3(0, 0.035, 0)
		"tonic_warmth":
			# A squat, square-shouldered bottle of amber glass full of an orange spiced
			# draught, the cork bound down with twine, and tied on at the side a bundle of
			# cinnamon sticks and a dried slice of orange.
			var square := func(a: float, _t: float, _p: Vector3) -> float:
				return 1.0 / pow(pow(absf(cos(a)), 5.0) + pow(absf(sin(a)) * 1.5, 5.0), 1.0 / 5.0)
			var outer := [Vector2(0, 0.004), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.04, 0.006), Vector2(0.041, 0.058), Vector2(0.036, 0.07), Vector2(0.018, 0.078), Vector2(0.012, 0.082), Vector2(0.012, 0.098), Vector2(0.012, 0.098), Vector2(0.0145, 0.1), Vector2(0.0145, 0.106), Vector2(0.0145, 0.106), Vector2(0.0125, 0.107)]
			vessel(k, I, outer, 0.003, Color(0.6, 0.32, 0.08, 0.1), Color(0.5, 0.2, 0.02, 0.9), 0.068, 36, square)
			cork(k, I, 0.0094, 0.107, 0.016)
			twine(k, I, 0.0125, 0.086, 4)
			for sx in [-1.0, 1.0]:
				tube(k, "pv_twine", I, PackedVector3Array([Vector3(0.0125, 0.09, 0.0), Vector3(0.03, 0.08 + sx * 0.002, 0.018), Vector3(0.042, 0.055, 0.024)]), PackedFloat32Array([0.0015, 0.0015, 0.0015]), 5, Color(0.72, 0.6, 0.42), false)
			# Cinnamon: bark rolled into quills, rough and red-brown.
			var bark := Color(0.48, 0.24, 0.1)
			for i in 2:
				var at := Transform3D(Basis(Vector3.FORWARD, -0.32 - 0.12 * i), Vector3(0.042 + 0.006 * i, 0.012, 0.022 + 0.006 * i))
				lathe(k, "pv_crust", at, _curve([Vector2(0, 0.0), Vector2(0.0055, 0.0), Vector2(0.0055, 0.0), Vector2(0.0058, 0.04), Vector2(0.0055, 0.085), Vector2(0.0055, 0.085), Vector2(0, 0.085)], 1), 10, func(p: Vector3, _a: float, _t: float) -> Color: return bark.darkened(0.25 * _nz(p, 120.0)), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.08 * absf(sin(a * 2.5)))
			# The orange slice: rind round segments of dried flesh.
			var slice := Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.2) * Basis(Vector3.UP, 0.4), Vector3(0.046, 0.064, 0.03))
			var flesh := func(p: Vector3, a: float, t2: float) -> Color:
				if t2 < 0.2:
					return Color(0.72, 0.28, 0.03)
				if t2 < 0.26:
					return Color(0.9, 0.62, 0.3)
				var seg := pow(absf(cos(a * 5.0)), 24.0)
				return Color(0.82, 0.36, 0.03).lerp(Color(0.92, 0.66, 0.32), seg).darkened(0.12 * _nz(p, 300.0))
			lathe(k, "pv_glossy", slice, _curve([Vector2(0.017, -0.002), Vector2(0.017, 0.002), Vector2(0.017, 0.002), Vector2(0.012, 0.0025), Vector2(0, 0.0028)], 2), 30, flesh)
			lathe(k, "pv_glossy", slice, PackedVector2Array([Vector2(0, -0.0025), Vector2(0.017, -0.002)]), 30, Color(0.72, 0.3, 0.04))
			return Vector3(0, 0.04, 0)
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
			# An earthenware pitcher under a glossy amber-brown glaze: a round belly, a
			# narrow waist with an incised band of zigzags, a flared mouth pinched to a
			# spout, a strap handle, and golden mead showing at the mouth.
			var spout := func(a2: float, t2: float, _p: Vector3) -> float:
				return 1.0 + 0.3 * smoothstep(0.82, 1.0, t2) * pow(maxf(0.0, -cos(a2)), 6.0)
			var glaze := Color(0.5, 0.22, 0.08)
			var col := func(p: Vector3, a2: float, t2: float) -> Color:
				var c := glaze.lerp(Color(0.72, 0.38, 0.12), 0.5 * smoothstep(0.1, 0.4, t2) * (1.0 - smoothstep(0.45, 0.6, t2)))
				c = c.darkened(0.18 * _nz(p, 40.0))
				# The incised band round the neck: a zigzag in dark slip.
				var y := p.y
				if y > 0.112 and y < 0.128:
					var zz := absf(fposmod(a2 * 12.0 / PI, 2.0) - 1.0)
					if absf((y - 0.112) / 0.016 - zz) < 0.22:
						c = c.darkened(0.55)
				if absf(y - 0.11) < 0.0015 or absf(y - 0.13) < 0.0015:
					c = c.darkened(0.45)
				return c.darkened(0.3 if t2 > 0.97 else 0.0)
			var prof := _curve([Vector2(0, 0.0), Vector2(0.036, 0.0), Vector2(0.036, 0.0), Vector2(0.04, 0.008), Vector2(0.054, 0.04), Vector2(0.056, 0.065), Vector2(0.046, 0.095), Vector2(0.033, 0.112), Vector2(0.031, 0.13), Vector2(0.036, 0.148), Vector2(0.04, 0.156), Vector2(0.04, 0.156), Vector2(0.036, 0.157), Vector2(0.032, 0.148), Vector2(0.027, 0.13), Vector2(0.029, 0.11), Vector2(0, 0.105)], 3)
			lathe(k, "pv_glaze", I, prof, 40, col, spout)
			lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0.028, 0.14), Vector2(0, 0.14)]), 24, Color(0.82, 0.5, 0.08))
			var handle := PackedVector3Array([Vector3(0.034, 0.145, 0), Vector3(0.058, 0.148, 0), Vector3(0.072, 0.125, 0), Vector3(0.07, 0.09, 0), Vector3(0.056, 0.06, 0), Vector3(0.05, 0.05, 0)])
			tube(k, "pv_glaze", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.6)), Vector3.ZERO), handle, PackedFloat32Array([0.0055, 0.006, 0.006, 0.006, 0.0058, 0.0055]), 10, glaze.darkened(0.1))
			return Vector3(0.07, 0.1, 0)
		"honey", "jam", "pickles":
			# A glass jar, filled: honey in a round-bellied jar with a honey dipper resting
			# across it, jam to the brim of a straight one, both mouths tied over with
			# burlap under twine; pickles packed in brine under a gold screw lid.
			var fill_col := HONEY
			var cloth_col := Color(0.6, 0.48, 0.32)
			var outer := [Vector2(0, 0.003), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.038, 0.005), Vector2(0.039, 0.065), Vector2(0.035, 0.075), Vector2(0.032, 0.08), Vector2(0.032, 0.088), Vector2(0.032, 0.088), Vector2(0.034, 0.09), Vector2(0.034, 0.094), Vector2(0.034, 0.094), Vector2(0.032, 0.095)]
			var fill := 0.08
			if t == "honey":
				outer = [Vector2(0, 0.004), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.042, 0.008), Vector2(0.05, 0.03), Vector2(0.049, 0.052), Vector2(0.04, 0.068), Vector2(0.034, 0.074), Vector2(0.034, 0.082), Vector2(0.034, 0.082), Vector2(0.036, 0.084), Vector2(0.036, 0.088), Vector2(0.036, 0.088), Vector2(0.034, 0.089)]
				fill = 0.07
			elif t == "jam":
				fill_col = Color(0.26, 0.02, 0.08, 0.98)
				fill = 0.084
			elif t == "pickles":
				fill_col = Color(0.4, 0.36, 0.04, 0.36)
			vessel(k, I, outer, 0.0028, CLEAR, fill_col, fill, 36)
			var top_y: float = (outer[outer.size() - 1] as Vector2).y
			var mouth: float = (outer[outer.size() - 3] as Vector2).x
			if t == "jam":
				# Fruit and seeds suspended in the jam, just inside the glass.
				var rj := RandomNumberGenerator.new()
				rj.seed = 23
				for i in 60:
					var a := rj.randf() * TAU
					var y := rj.randf_range(0.008, 0.08)
					var rr := _radius_at(_curve(outer, 3), y) - 0.0042
					lathe(k, "pv_glossy", Transform3D(Basis.IDENTITY, Vector3(cos(a) * rr, y, sin(a) * rr)), _sphere(rj.randf_range(0.0018, 0.003), 4), 6, Color(0.36, 0.04, 0.12).lightened(rj.randf_range(0.0, 0.15)))
			if t == "pickles":
				# Gherkins packed upright in the brine, warty and dark green.
				for i in 9:
					var a := TAU * i / 9.0 + 0.3
					var rr := 0.022 if i % 3 != 0 else 0.01
					var gx := Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), 0.15 + 0.1 * (i % 2)), Vector3(cos(a) * rr, 0.04, sin(a) * rr))
					lathe(k, "pv_skin", gx, _sphere(0.0125, 10, 2.8), 12, func(p: Vector3, _a2: float, _t2: float) -> Color: return Color(0.12, 0.16, 0.02).darkened(0.35 * absf(_nz(p, 300.0))).lerp(Color(0.32, 0.34, 0.06), 0.5 if _nz(p, 700.0) > 0.5 else 0.0), func(a2: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.08 * _nz(p * 3.0 + Vector3(a2, 0, 0), 200.0))
				var gold := Color(0.62, 0.5, 0.26)
				lathe(k, "pv_tin", I, _curve([Vector2(0.0355, 0.086), Vector2(0.0355, 0.098), Vector2(0.0355, 0.098), Vector2(0.033, 0.1), Vector2(0, 0.1)], 2), 40, func(p: Vector3, _a: float, _t: float) -> Color: return gold.darkened(0.3 * clampf(_nz(p, 120.0), 0.0, 1.0)), func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + (0.012 * pow(absf(sin(a * 30.0)), 2.0) if t2 < 0.4 else 0.0))
			else:
				# Burlap over the mouth, gathered under twine, the skirt hanging in folds.
				var skirt := func(a: float, t2: float, _p: Vector3) -> float:
					return 1.0 + (0.1 * (1.0 - t2) * (0.5 + 0.5 * sin(a * 9.0 + 1.3 * sin(a * 4.0)))) if t2 < 0.6 else 1.0
				var m := mouth + 0.0025
				lathe(k, "pv_burlap", I, _curve([Vector2(m + 0.011, top_y - 0.028), Vector2(m + 0.007, top_y - 0.016), Vector2(m + 0.0005, top_y - 0.009), Vector2(m + 0.0015, top_y - 0.002), Vector2(m, top_y + 0.004), Vector2(m * 0.75, top_y + 0.009), Vector2(0, top_y + 0.0095)], 3), 40, func(p: Vector3, _a: float, _t: float) -> Color: return cloth_col.darkened(0.15 * _nz(p, 40.0)), skirt)
				twine(k, I, m + 0.0005, top_y - 0.011, 3)
				# A bow of twine at the front.
				for sx in [-1.0, 1.0]:
					var loop := PackedVector3Array()
					var lr := PackedFloat32Array()
					for s2 in 9:
						var f := s2 / 8.0
						loop.append(Vector3(sx * (0.009 * sin(f * PI) + 0.002 * f), top_y - 0.008 + 0.006 * sin(f * TAU), m + 0.003 + 0.002 * sin(f * PI)))
						lr.append(0.0014)
					tube(k, "pv_twine", I, loop, lr, 5, Color(0.72, 0.6, 0.42), false)
					tube(k, "pv_twine", I, PackedVector3Array([Vector3(0, top_y - 0.009, m + 0.003), Vector3(sx * 0.006, top_y - 0.022, m + 0.006)]), PackedFloat32Array([0.0013, 0.0011]), 5, Color(0.72, 0.6, 0.42))
			if t == "honey":
				# A honey dipper resting across the jar: a turned wooden handle and a head
				# of ridges, honey clinging to it.
				var dip := Transform3D(Basis(Vector3.FORWARD, 1.05) * Basis(Vector3.RIGHT, 0.15), Vector3(0.0, top_y + 0.016, 0.014))
				var wood := Color(0.55, 0.32, 0.14)
				lathe(k, "pv_wood", dip, _curve([Vector2(0, 0.0), Vector2(0.0035, 0.0), Vector2(0.0035, 0.0), Vector2(0.0038, 0.05), Vector2(0.0045, 0.09), Vector2(0.004, 0.1), Vector2(0, 0.101)], 2), 12, wood)
				lathe(k, "pv_wood", dip, _curve([Vector2(0, -0.042), Vector2(0.009, -0.041), Vector2(0.0125, -0.032), Vector2(0.013, -0.02), Vector2(0.012, -0.008), Vector2(0.006, 0.0), Vector2(0.0035, 0.002)], 3), 18, wood.darkened(0.08), func(_a: float, t2: float, _p: Vector3) -> float: return 1.0 - 0.18 * pow(absf(sin(t2 * PI * 5.0)), 2.0))
			return Vector3(0, 0.045, 0)
		"beans_can", "stew_tin":
			# A tinplate can: rolled rims top and bottom, ribs round the body, a paper label.
			var ribs := func(_a: float, t2: float, _p: Vector3) -> float:
				return 1.0 - (0.012 * pow(absf(sin(t2 * PI * 9.0)), 6.0) if t2 > 0.12 and t2 < 0.88 else 0.0)
			var r := 0.05
			var h := 0.07 if t == "beans_can" else 0.075
			var tin := Color(0.72, 0.72, 0.7)
			var rust_amt := 0.95 if t == "beans_can" else 0.7
			var rusty := func(p: Vector3, _a: float, _t: float) -> Color: return tin.lerp(Color(0.5, 0.3, 0.15), clampf(_nz(p, 60.0) * 1.6 + (0.25 if t == "beans_can" else -0.25), 0.0, rust_amt))
			var top_y := h if t == "stew_tin" else h - 0.002
			lathe(k, "pv_paint" if t == "beans_can" else "pv_tin", I, _curve([Vector2(0, 0.003), Vector2(r - 0.002, 0.003), Vector2(r - 0.002, 0.003), Vector2(r + 0.0015, 0.0), Vector2(r + 0.0015, 0.0), Vector2(r + 0.0018, 0.004), Vector2(r, 0.006), Vector2(r, h - 0.006), Vector2(r + 0.0018, h - 0.004), Vector2(r + 0.0015, h), Vector2(r + 0.0015, h), Vector2(r - 0.002, h - 0.002), Vector2(r - 0.002, h - 0.002), Vector2(r - 0.003, top_y - 0.003)] + ([Vector2(0, top_y - 0.003)] if t == "stew_tin" else [Vector2(r - 0.003, h * 0.75), Vector2(r - 0.003, h * 0.75), Vector2(0, h * 0.75)]), 2), 36, rusty, ribs)
			if t == "beans_can":
				# Opened: beans in sauce, and the lid bent back on its hinge.
				lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0, h - 0.012), Vector2(r - 0.003, h - 0.011)]), 32, Color(0.55, 0.2, 0.08))
				var rb := RandomNumberGenerator.new()
				rb.seed = 11
				for i in 24:
					var a := rb.randf() * TAU
					var d := sqrt(rb.randf()) * (r - 0.008)
					lathe(k, "pv_glossy", Transform3D(Basis(Vector3.UP, rb.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(cos(a) * d, h - 0.0115, sin(a) * d)), _sphere(0.004, 5, 1.6), 8, Color(0.62, 0.26, 0.1))
				lathe(k, "pv_tin", Transform3D(Basis(Vector3.FORWARD, -1.55), Vector3(-r + 0.0015, h - 0.001, 0)) * Transform3D(Basis.IDENTITY, Vector3(r - 0.002, 0, 0)), PackedVector2Array([Vector2(0, 0.0), Vector2(r - 0.002, 0.0), Vector2(r - 0.002, 0.0), Vector2(r - 0.001, 0.0015)]), 32, tin, func(a: float, _t2: float, _p: Vector3) -> float: return 1.0 + 0.04 * sin(a * 7.0))
			else:
				label(k, I, r, 0.01, h - 0.01, "red", 0.75, 0.25)
			return Vector3(0, h * 0.5, 0)
		"energy_drink":
			# A slim aluminium can: bare metal at the ends, the body painted black with a
			# teal flash slanting round it, a necked top and a ring pull.
			var r := 0.0265
			var paint := func(p: Vector3, a: float, _t: float) -> Color:
				if p.y < 0.012 or p.y > 0.14:
					return Color(0.8, 0.82, 0.84)
				var band := p.y - 0.075 - 0.025 * sin(a)
				if absf(band) < 0.012:
					return Color(0.1, 0.66, 0.62)
				if absf(band - 0.018) < 0.003:
					return Color(0.85, 0.86, 0.88)
				return Color(0.07, 0.075, 0.08)
			lathe(k, "pv_alu", I, _curve([Vector2(0, 0.006), Vector2(0.018, 0.0015), Vector2(0.022, 0.0), Vector2(0.022, 0.0), Vector2(r, 0.008), Vector2(r, 0.138), Vector2(0.022, 0.15), Vector2(0.0215, 0.153), Vector2(0.0215, 0.153), Vector2(0.0205, 0.151), Vector2(0, 0.151)], 3), 40, paint)
			k.box("pv_tin", Transform3D(Basis.IDENTITY, Vector3(0.004, 0.1515, 0)), Vector3(0.016, 0.001, 0.008), Color(0.8, 0.8, 0.82))
			return Vector3(0, 0.07, 0)
		"tea_tin":
			# A small square tin of loose tea, old and rusting: rolled edges, the hinged lid
			# standing open at the back, the box heaped with dark curled leaves.
			var rusty := func(p: Vector3, _a: float, _t: float) -> Color:
				var c := Color(0.62, 0.52, 0.36).lerp(Color(0.5, 0.3, 0.12), clampf(_nz(p, 70.0) * 1.5 + 0.35, 0.0, 1.0))
				return c.lerp(Color(0.7, 0.62, 0.48), 0.4 * clampf(_nz(p + Vector3(3, 0, 0), 150.0) - 0.3, 0.0, 1.0))
			var w := 0.06
			var h := 0.05
			var d := 0.045
			var wall := 0.0015
			# Walls and floor of the open box, and a rolled rim round the top.
			k.box("pv_paint", I.translated(Vector3(0, 0.001, 0)), Vector3(w, 0.002, d), Color(0.4, 0.28, 0.16))
			for e in [[Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, wall)], [Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, wall)], [Vector3(w * 0.5, h * 0.5, 0), Vector3(wall, h, d)], [Vector3(-w * 0.5, h * 0.5, 0), Vector3(wall, h, d)]]:
				k.box("pv_paint", I.translated(e[0]), e[1], rusty.call(e[0] * 3.0, 0.0, 0.0))
			for e in [[Vector3(0, h, d * 0.5), Vector3(w + 0.003, 0.003, 0.003)], [Vector3(0, h, -d * 0.5), Vector3(w + 0.003, 0.003, 0.003)], [Vector3(w * 0.5, h, 0), Vector3(0.003, 0.003, d + 0.003)], [Vector3(-w * 0.5, h, 0), Vector3(0.003, 0.003, d + 0.003)], [Vector3(0, 0.002, d * 0.5), Vector3(w + 0.003, 0.004, 0.003)], [Vector3(w * 0.5, 0.002, 0), Vector3(0.003, 0.004, d + 0.003)]]:
				k.box("pv_paint", I.translated(e[0]), e[1], Color(0.46, 0.32, 0.18))
			# The tea: a heap of dark curled leaf.
			lathe(k, "pv_crumb", Transform3D(Basis.from_scale(Vector3(w * 0.5 - wall, 1.0, d * 0.5 - wall)), Vector3.ZERO), _curve([Vector2(1.0, h - 0.004), Vector2(0.7, h - 0.001), Vector2(0.3, h + 0.002), Vector2(0, h + 0.003)], 2), 32, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.16, 0.11, 0.07).lerp(Color(0.32, 0.22, 0.12), clampf(_nz(p * Vector3(1, 1, 1), 800.0) + 0.3, 0.0, 1.0)), func(a: float, _t: float, p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)), 8.0) + pow(absf(sin(a)), 8.0), 1.0 / 8.0) * (1.0 + 0.04 * _nz(p, 600.0)))
			# The lid, hinged at the back and standing open, leaning back a little.
			var lid := Transform3D(Basis(Vector3.RIGHT, -1.75), Vector3(0, h + 0.001, -d * 0.5))
			k.box("pv_paint", lid * Transform3D.IDENTITY.translated(Vector3(0, 0.0, d * 0.5 + 0.001)), Vector3(w + 0.004, 0.002, d + 0.004), Color(0.44, 0.3, 0.16))
			for e in [[Vector3(0, -0.005, d + 0.003), Vector3(w + 0.004, 0.012, 0.002)], [Vector3(w * 0.5 + 0.002, -0.005, d * 0.5 + 0.001), Vector3(0.002, 0.012, d + 0.004)], [Vector3(-w * 0.5 - 0.002, -0.005, d * 0.5 + 0.001), Vector3(0.002, 0.012, d + 0.004)]]:
				k.box("pv_paint", lid * Transform3D.IDENTITY.translated(e[0]), e[1], rusty.call(e[0] * 3.0 + Vector3(1, 0, 0), 0.0, 0.0))
			return Vector3(0, 0.025, 0)
		"antirad":
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
			# A bota bag: two pear-shaped pieces of brown leather sewn edge to edge with a
			# thick laced thong all round, plump with water, so it is flat-sided and round-
			# bellied. The neck is bound with cord and stopped with a cork, and a leather
			# strap loops from the neck down to the bottom of the bag.
			var bag := Transform3D(Basis(Vector3.FORWARD, 0.5), Vector3.ZERO)
			var body := bag * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.5)), Vector3.ZERO)
			var hide := Color(0.42, 0.22, 0.1)
			var leather := func(p: Vector3, _a: float, t2: float) -> Color:
				# Worn paler on the belly, darker into the neck.
				return hide.darkened(0.18 * _nz(p, 30.0) + 0.2 * smoothstep(0.6, 0.95, t2)).lightened(0.1 * clampf(_nz(p, 8.0), 0.0, 1.0))
			var prof := _curve([Vector2(0, 0.0), Vector2(0.045, 0.006), Vector2(0.078, 0.035), Vector2(0.082, 0.065), Vector2(0.066, 0.105), Vector2(0.035, 0.14), Vector2(0.017, 0.165), Vector2(0.014, 0.18), Vector2(0, 0.181)], 4)
			lathe(k, "pv_leather", body, prof, 40, leather, func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.04 * _nz(p, 25.0))
			# The laced seam round the edge: a cord with the lacing crossing over it.
			var lace := Color(0.44, 0.25, 0.11)
			var seam := PackedVector3Array()
			var sr := PackedFloat32Array()
			for i in 49:
				var f := float(i) / 48.0
				var y := lerpf(0.004, 0.16, f)
				var side := -1.0
				seam.append(Vector3(side * (_radius_at(prof, y) + 0.001), y, 0))
				sr.append(0.0048)
			for side in [-1.0, 1.0]:
				var pts := PackedVector3Array()
				for p in seam:
					pts.append(Vector3(p.x * -side, p.y, 0))
				tube(k, "pv_leather", bag, pts, sr, 8, lace.darkened(0.15), false)
				for i in range(1, 48, 2):
					var at := pts[i]
					var dir := (pts[i + 1] - pts[i - 1]).normalized()
					var stitch := Basis(dir.cross(Vector3.BACK).normalized(), dir, Vector3.BACK).orthonormalized()
					k.box("pv_leather", bag * Transform3D(stitch * Basis(Vector3.BACK, 0.6), at + Vector3(0, 0, 0.0)), Vector3(0.012, 0.0042, 0.012), lace.lightened(0.05))
			# The bottom of the seam, under the belly.
			var under := PackedVector3Array()
			var ur := PackedFloat32Array()
			for i in 9:
				var a := PI + PI * i / 8.0
				under.append(Vector3(cos(a) * 0.045, 0.006 + sin(a) * 0.004, 0))
				ur.append(0.0038)
			tube(k, "pv_leather", bag, under, ur, 8, lace.darkened(0.15), false)
			# The neck: cord wound round, then the cork.
			twine(k, bag, 0.0145, 0.158, 4, Color(0.52, 0.34, 0.18))
			cork(k, bag, 0.011, 0.181, 0.016, 0.02)
			# The carrying strap, from the neck round in a loop to the bag's bottom edge.
			var strap := PackedVector3Array([Vector3(0.016, 0.16, 0), Vector3(0.04, 0.15, 0.004), Vector3(0.07, 0.11, 0.006), Vector3(0.09, 0.06, 0.006), Vector3(0.09, 0.02, 0.004), Vector3(0.075, -0.005, 0.0), Vector3(0.055, 0.004, 0)])
			tube(k, "pv_leather", bag, strap, PackedFloat32Array([0.0028, 0.003, 0.003, 0.003, 0.003, 0.003, 0.0028]), 6, lace.darkened(0.25))
			return bag * Vector3(0, 0.15, 0)
		"coffee_pot":
			# A trail coffee pot of grey enamel over steel, chipped and rusting at the
			# rims and seams: wide base, tapered body, spout, handle, lid knob.
			var enamel := Color(0.34, 0.36, 0.38)
			var worn := func(p: Vector3, _a: float, t2: float) -> Color:
				var c := enamel.lightened(0.5) if _nz(p, 700.0) > 0.45 else enamel.darkened(0.12 * _nz(p, 40.0))
				var rim := 1.0 - smoothstep(0.0, 0.08, t2) + smoothstep(0.55, 0.62, t2) * (1.0 - smoothstep(0.62, 0.7, t2))
				var rust := clampf(_nz(p, 25.0) * 1.8 - 0.35 + rim * 0.8, 0.0, 1.0)
				return c.lerp(Color(0.4, 0.22, 0.1), rust)
			lathe(k, "pv_tin", I, _curve([Vector2(0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.058, 0.006), Vector2(0.054, 0.04), Vector2(0.042, 0.11), Vector2(0.038, 0.135), Vector2(0.038, 0.135), Vector2(0.035, 0.14), Vector2(0.025, 0.152), Vector2(0.008, 0.156), Vector2(0.008, 0.156), Vector2(0.01, 0.164), Vector2(0.006, 0.17), Vector2(0, 0.171)], 3), 36, worn)
			tube(k, "pv_tin", I, PackedVector3Array([Vector3(0.048, 0.035, 0), Vector3(0.065, 0.06, 0), Vector3(0.078, 0.095, 0), Vector3(0.088, 0.12, 0)]), PackedFloat32Array([0.011, 0.008, 0.006, 0.005]), 10, worn)
			tube(k, "pv_tin", I, PackedVector3Array([Vector3(-0.04, 0.125, 0), Vector3(-0.07, 0.12, 0), Vector3(-0.08, 0.085, 0), Vector3(-0.065, 0.05, 0), Vector3(-0.05, 0.04, 0)]), PackedFloat32Array([0.005, 0.0055, 0.0055, 0.005, 0.005]), 8, worn)
			return Vector3(-0.077, 0.085, 0)
	return _food(k, t)

## Fruit, vegetables, bread, meat and cooked dishes.
static func _food(k: MeshKit, t: String) -> Variant:
	var I := Transform3D.IDENTITY
	match t:
		"apple":
			return _apple(k, 32, 4, true)
		"pear":
			# A ripe pear: a full bottom tapering up a long neck to a curved stalk, ochre-
			# yellow skin shaded green, a russet blush on one cheek, freckled all over.
			var col := func(p: Vector3, a: float, t2: float) -> Color:
				var c := Color(0.62, 0.5, 0.08).lerp(Color(0.5, 0.5, 0.1), 0.5 + 0.5 * sin(a + 2.0))
				c = c.lerp(Color(0.6, 0.32, 0.06), 0.35 * smoothstep(0.2, 0.8, sin(a + 1.0)) * (1.0 - t2))
				# Russet freckles, and a russet patch round the stalk.
				c = c.lerp(Color(0.4, 0.26, 0.08), 0.6 if _nz(p, 900.0) > 0.3 else 0.0)
				return c.lerp(Color(0.42, 0.28, 0.1), smoothstep(0.85, 1.0, t2) * 0.6)
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.006), Vector2(0.02, 0.001), Vector2(0.037, 0.012), Vector2(0.044, 0.034), Vector2(0.039, 0.056), Vector2(0.027, 0.074), Vector2(0.019, 0.092), Vector2(0.014, 0.108), Vector2(0.006, 0.116), Vector2(0, 0.117)], 4), 32, col, func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.03 * _nz(p, 30.0) + 0.02 * sin(a * 3.0))
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.113, 0), Vector3(0.003, 0.126, 0), Vector3(0.01, 0.137, 0.002)]), PackedFloat32Array([0.0026, 0.0021, 0.0018]), 6, Color(0.3, 0.2, 0.1))
			leaf(k, Transform3D(Basis(Vector3.FORWARD, -0.9), Vector3(0.006, 0.13, 0)), 0.048, 0.024, Color(0.1, 0.24, 0.05), 0.3)
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
			# A round brown onion: squat and full, papery copper skin streaked with fine
			# veins from the root to a twisted neck, a tuft of dry roots underneath.
			var col := func(p: Vector3, a: float, t2: float) -> Color:
				var vein := absf(sin(a * 22.0 + _nz(p, 20.0) * 3.0))
				return Color(0.58, 0.28, 0.07).lerp(Color(0.76, 0.46, 0.18), vein * 0.5).darkened(0.25 * smoothstep(0.85, 1.0, t2) + 0.1 * _nz(p, 40.0))
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.004), Vector2(0.014, 0.004), Vector2(0.036, 0.016), Vector2(0.044, 0.036), Vector2(0.04, 0.056), Vector2(0.024, 0.072), Vector2(0.008, 0.082), Vector2(0.004, 0.096), Vector2(0, 0.1)], 4), 30, col, func(a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.025 * sin(a * 3.0) + 0.02 * _nz(p, 30.0))
			# Dry papery wisps at the neck.
			for i in 3:
				var a := TAU * i / 3.0
				tube(k, "pv_veg", I, PackedVector3Array([Vector3(0, 0.094, 0), Vector3(cos(a) * 0.004, 0.104, sin(a) * 0.004), Vector3(cos(a) * 0.01, 0.11, sin(a) * 0.01)]), PackedFloat32Array([0.0018, 0.0012, 0.0006]), 4, Color(0.62, 0.36, 0.14), false)
			for i in 9:
				var a := TAU * i / 9.0
				tube(k, "pv_veg", I, PackedVector3Array([Vector3(cos(a) * 0.004, 0.003, sin(a) * 0.004), Vector3(cos(a) * 0.01, -0.004, sin(a) * 0.01), Vector3(cos(a + 0.4) * 0.016, -0.007, sin(a + 0.4) * 0.016)]), PackedFloat32Array([0.0009, 0.0007, 0.0004]), 4, Color(0.82, 0.74, 0.6), false)
			return Vector3(0, 0.04, 0)
		"cabbage":
			# A firm head wrapped in layers of thick, crinkled, veined leaves, the outer
			# ones loose and curling back, darker than the pale heart.
			var veined := func(green: Color) -> Callable:
				return func(p: Vector3, a2: float, t2: float) -> Color:
					var vein := pow(absf(sin(a2 * 9.0 + t2 * 2.0)), 40.0) + 0.5 * pow(absf(sin(a2 * 27.0 + t2 * 5.0)), 60.0)
					return green.lerp(Color(0.82, 0.88, 0.68), clampf(vein, 0.0, 1.0) * 0.8).darkened(0.1 * _nz(p, 90.0))
			var crinkle := func(a2: float, t2: float, p: Vector3) -> float: return 1.0 + 0.05 * _nz(p, 70.0) + 0.04 * sin(a2 * 40.0) * t2 * t2
			lathe(k, "pv_veg", I, _sphere(0.05, 16, 0.9), 40, veined.call(Color(0.68, 0.78, 0.5)), crinkle)
			for i in 9:
				var a := TAU * i / 9.0 * 1.618
				var outer := i >= 5
				var tilt := (0.35 + 0.1 * (i % 2)) if outer else 0.05
				var lx := Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, tilt), Vector3(0, -0.046, 0))
				var s := 1.0 + 0.06 * i
				lathe(k, "pv_veg", lx, _curve([Vector2(0.006, 0.0), Vector2(0.04 * s, 0.012), Vector2(0.056 * s, 0.045), Vector2(0.054 * s, 0.075 + (0.01 if outer else 0.0)), Vector2(0.04 * s + (0.025 if outer else 0.0), 0.095 + (0.0 if outer else 0.005))], 3), 14, veined.call(Color(0.3, 0.46, 0.2) if outer else Color(0.5, 0.64, 0.34)), crinkle, Vector2(0.0, 0.36))
				lathe(k, "pv_veg", lx, _curve([Vector2(0.04 * s + (0.025 if outer else 0.0), 0.095 + (0.0 if outer else 0.005)), Vector2(0.054 * s - 0.003, 0.075), Vector2(0.056 * s - 0.003, 0.045), Vector2(0.04 * s - 0.003, 0.014), Vector2(0.006, 0.003)], 3), 14, Color(0.62, 0.72, 0.46), crinkle, Vector2(0.0, 0.36))
			return Vector3(0, 0.0, 0)
		"pumpkin":
			# A deep orange pumpkin, round and a little taller than squat, cut into deep
			# lobes by its ribs, with a thick, ridged, curving stalk.
			var ribbed := func(a: float, _t: float, _p: Vector3) -> float: return 0.86 + 0.14 * pow(absf(sin(a * 5.0)), 0.5)
			var col := func(p: Vector3, a: float, _t: float) -> Color: return Color(0.82, 0.32, 0.03).darkened(0.35 * (1.0 - pow(absf(sin(a * 5.0)), 0.4)) + 0.1 * _nz(p, 30.0))
			lathe(k, "pv_skin", I, _curve([Vector2(0, 0.016), Vector2(0.04, 0.0), Vector2(0.08, 0.025), Vector2(0.092, 0.065), Vector2(0.08, 0.11), Vector2(0.035, 0.132), Vector2(0, 0.12)], 4), 60, col, ribbed)
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.115, 0), Vector3(0.002, 0.135, 0), Vector3(0.01, 0.152, 0.002), Vector3(0.024, 0.162, 0.004)]), PackedFloat32Array([0.01, 0.008, 0.0065, 0.0055]), 8, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.42, 0.34, 0.16).darkened(0.2 * _nz(p, 300.0) + 0.15 * t2))
			return Vector3(0, 0.06, 0)
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
		"wild_berries":
			# A hanging bunch of wild berries like huckleberries: glossy, dark crimson-
			# purple, each with the dark star of its old flower at the tip, on a woody
			# branching stalk with a pair of toothed leaves at the top.
			var rw := RandomNumberGenerator.new()
			rw.seed = 41
			var stem := Color(0.36, 0.28, 0.16)
			tube(k, "pv_wood", I, PackedVector3Array([Vector3(0.0, 0.0, 0), Vector3(0.004, 0.02, 0), Vector3(0.016, 0.034, 0)]), PackedFloat32Array([0.0018, 0.0016, 0.0013]), 6, stem)
			for sd in [-1.0, 1.0]:
				leaf(k, Transform3D(Basis(Vector3.FORWARD, sd * 1.1) * Basis(Vector3.UP, sd * 0.3), Vector3(0.003, 0.004, -0.004)), 0.045, 0.026, Color(0.1, 0.24, 0.06), 0.2, 8, 7)
			for i in 14:
				var f := i / 13.0
				var depth := 0.012 + f * 0.06
				var spread := (1.0 - f * 0.55) * 0.026
				var a := i * 2.4
				var at := Vector3(cos(a) * spread, -depth, sin(a) * spread * 0.7 + 0.004)
				tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, -depth * 0.6, 0), at]), PackedFloat32Array([0.0008, 0.0006]), 4, stem, false)
				var br := rw.randf_range(0.0085, 0.0105)
				var out := (at + Vector3(0, 0.0, 0.03)).normalized()
				var c := Color(0.42, 0.1, 0.18).lightened(rw.randf_range(-0.08, 0.1))
				lathe(k, "pv_skin", Transform3D(_facing(out), at), _sphere(br, 10, 0.92), 14, func(p: Vector3, _a: float, t2: float) -> Color: return c.darkened(0.12 * _nz(p, 300.0)).darkened(0.6 if t2 > 0.93 else (0.0 if t2 < 0.86 else -0.3)))
			return Vector3(0, 0.01, 0)
		"glowberry":
			# A spray of big round berries on a dark, forking stalk: deep violet-blue and
			# almost see-through, a paler heart and fine pale specks inside the skin.
			var rg := RandomNumberGenerator.new()
			rg.seed = 77
			var stem := Color(0.3, 0.26, 0.32)
			var main := PackedVector3Array([Vector3(0.03, 0.05, 0), Vector3(0.016, 0.03, 0), Vector3(0.0, 0.01, 0), Vector3(-0.012, -0.012, 0)])
			tube(k, "pv_wood", I, main, PackedFloat32Array([0.002, 0.0022, 0.002, 0.0016]), 6, stem)
			var spots := [Vector3(-0.036, 0.004, 0.006), Vector3(-0.028, -0.03, 0.01), Vector3(0.006, -0.036, 0.012), Vector3(0.03, -0.008, 0.006), Vector3(0.034, 0.024, -0.002), Vector3(-0.004, 0.026, 0.004)]
			for i in spots.size():
				var at: Vector3 = spots[i]
				var on: Vector3 = main[mini(i % 3 + 1, 3)]
				tube(k, "pv_wood", I, PackedVector3Array([on, on.lerp(at, 0.5) + Vector3(0, 0.006, 0), at + (on - at).normalized() * 0.011]), PackedFloat32Array([0.0013, 0.0011, 0.0009]), 5, stem, false)
				var br := rg.randf_range(0.0115, 0.0135)
				var c := Color(0.3, 0.24, 0.78).lightened(rg.randf_range(-0.05, 0.08))
				var skin := func(p: Vector3, _a: float, t2: float) -> Color:
					var heart := 1.0 - absf(t2 - 0.6) * 2.5
					return c.lerp(Color(0.62, 0.5, 0.95), clampf(heart, 0.0, 0.5)).lerp(Color(0.85, 0.82, 1.0), 0.7 if _nz(p, 1400.0) > 0.62 else 0.0)
				lathe(k, "pv_glossy", Transform3D(_facing(Vector3(0.2, 0.3, 1.0)), at), _sphere(br, 10), 16, skin)
			return Vector3(0.03, 0.05, 0)
		"grapes":
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
		"mushroom":
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
		"raw_meat":
			# A thick raw beef steak, cut across the grain: its broad face turned up to the
			# eye shows bright red lean in lobes parted by seams of white fat, a pink-white
			# cap of fat runs all round the edge, and a round of bone sits near the top.
			var flat := Transform3D(Basis(Vector3.RIGHT, 0.95), Vector3.ZERO)
			var outline := func(a: float, _t: float, p: Vector3) -> float:
				return 1.0 + 0.1 * sin(a * 2.0 + 0.6) + 0.05 * sin(a * 3.0 + 2.0) + 0.03 * _nz(p, 6.0)
			var sx := Basis.from_scale(Vector3(1.0, 1.0, 0.78))
			var h := 0.024
			var r := 0.07
			# The slab: fat all round the sides, rounded over at top and bottom.
			var fat := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.86, 0.62, 0.6).darkened(0.1 * _nz(p, 60.0))
			lathe(k, "pv_fat", flat * Transform3D(sx, Vector3.ZERO), _curve([Vector2(0, -h * 0.5), Vector2(r * 0.9, -h * 0.5), Vector2(r, -h * 0.25), Vector2(r * 1.01, h * 0.1), Vector2(r * 0.97, h * 0.42), Vector2(r * 0.86, h * 0.5), Vector2(0, h * 0.5)], 3), 56, fat, outline)
			# The cut face of lean, just proud of the fat inside the rim.
			lathe(k, "pv_steak", flat * Transform3D(sx, Vector3.ZERO), _curve([Vector2(r * 0.84, h * 0.5 + 0.0006), Vector2(r * 0.5, h * 0.5 + 0.0012), Vector2(0, h * 0.5 + 0.0014)], 3), 56, Color.WHITE, outline)
			# The bone: a white ring round pink marrow.
			var bone_at := flat * Transform3D(Basis.IDENTITY, Vector3(0.006, h * 0.5 + 0.0015, -0.03))
			lathe(k, "pv_bone", bone_at, _curve([Vector2(0.0085, -0.002), Vector2(0.0085, 0.0005), Vector2(0.0085, 0.0005), Vector2(0.0055, 0.0008), Vector2(0.0055, 0.0008), Vector2(0, 0.0006)], 1), 20, func(_p: Vector3, _a: float, t2: float) -> Color: return Color(0.95, 0.9, 0.84) if t2 < 0.7 else Color(0.82, 0.55, 0.5))
			return Vector3.ZERO
		"steak", "synth_steak", "meat_xeno":
			# A thick steak, uneven and fibrous. Raw: deep red, finely marbled, a cap of fat
			# down one side. The steak is seared: a dark crust, grill bars and juices.
			var synth := t == "synth_steak"
			var seared := t == "steak"
			var outline := func(a: float, _t: float, p: Vector3) -> float:
				if synth:
					return (1.0 / pow(pow(absf(cos(a)), 10.0) + pow(absf(sin(a)), 10.0), 0.1)) * (1.0 + 0.02 * _nz(p, 8.0))
				return 1.0 + 0.12 * sin(a * 2.0 + 0.5) + 0.06 * _nz(p, 2.5) + 0.02 * _nz(p, 14.0)
			var prof := PackedVector2Array()
			for v in _sphere(1.0, 22):
				prof.append(Vector2(v.x, clampf(v.y, -0.7 if synth else -0.55, 0.7 if synth else 0.55) + (0.0 if synth else 0.06 * _nz(Vector3(v.x, v.y, 0.0), 3.0))))
			var xf := Transform3D(Basis.from_scale(Vector3(0.075, 0.022 if synth else 0.03, 0.05 if synth else 0.055)), Vector3.ZERO)
			var tint := Color.WHITE if t != "meat_xeno" else Color(0.8, 0.6, 1.0)
			if seared:
				var crust := func(p: Vector3, _a: float, t2: float) -> Color:
					var c := Color(0.4, 0.2, 0.1).darkened(0.15 * clampf(_nz(p, 2.0) + 0.3, 0.0, 1.0))
					# Pinker at the cut edge.
					return c.lerp(Color(0.55, 0.2, 0.15), smoothstep(0.4, 0.5, t2) * (1.0 - smoothstep(0.5, 0.6, t2)) * 0.6)
				lathe(k, "pv_roast", xf, prof, 48, crust, outline)
			else:
				# Darker where the cut edge has dried in the air.
				var raw := func(p: Vector3, _a: float, t2: float) -> Color: return tint.darkened(0.12 * _nz(p, 3.0) + (0.12 * pow(absf(sin(p.z * 60.0 + 0.4 * _nz(p, 4.0))), 6.0) if synth else 0.0) + (0.0 if synth else 0.22 * (1.0 - absf(t2 - 0.5) * 2.0) * smoothstep(0.3, 0.5, t2) * (1.0 - smoothstep(0.5, 0.7, t2))))
				lathe(k, "pv_meat_synth" if synth else "pv_marbled", xf, prof, 48, raw, outline)
			if not synth:
				# The fat: a band round part of the edge, just proud of the meat.
				var band := PackedVector2Array()
				for v in _sphere(1.03, 18):
					if absf(v.y) < 0.5:
						band.append(Vector2(v.x, v.y))
				var fat := Color(0.94, 0.88, 0.76) if not seared else Color(0.78, 0.55, 0.3)
				lathe(k, "pv_fat", xf, band, 20, func(p: Vector3, _a: float, _t: float) -> Color: return fat.darkened(0.12 * _nz(p, 20.0)), outline, Vector2(0.28, 0.5))
			return Vector3.ZERO
		"cooked_meat":
			# A roast leg joint: a fat, glossy, deep-browned ham swelling from a bare knuckle
			# bone, sawn off square at the wide end so the cut face shows pink meat ringed
			# with white fat round the marrow bone. Lies corner to corner, bone down-left,
			# the cut face turned up towards the eye.
			var leg := Transform3D(Basis(Vector3.FORWARD, 0.85) * Basis(Vector3.RIGHT, 0.05), Vector3.ZERO)
			var col := func(p: Vector3, _a: float, t2: float) -> Color:
				var c := Color(0.5, 0.24, 0.1).lerp(Color(0.3, 0.12, 0.05), clampf(_nz(p, 30.0) * 1.4 + 0.3, 0.0, 1.0))
				# Crackling catches the light in paler streaks; the shank end is darker.
				c = c.lerp(Color(0.72, 0.42, 0.2), 0.45 * clampf(_nz(p + Vector3(7, 0, 0), 90.0) - 0.1, 0.0, 1.0))
				return c.darkened(0.2 * (1.0 - smoothstep(0.0, 0.3, t2)))
			var plump := func(a: float, t2: float, p: Vector3) -> float: return (1.0 + 0.06 * _nz(p, 18.0) + 0.03 * sin(a * 3.0 + t2 * 5.0)) * (1.0 - 0.12 * pow(absf(sin(a)), 2.0))
			var prof := _curve([Vector2(0.012, 0.0), Vector2(0.018, 0.02), Vector2(0.036, 0.05), Vector2(0.06, 0.09), Vector2(0.076, 0.125), Vector2(0.078, 0.15), Vector2(0.073, 0.168)], 4)
			lathe(k, "pv_roast", leg, prof, 36, col, plump)
			# The cut face: a disc of pink meat with a darker grain, a rim of fat, the bone.
			var face := func(p: Vector3, a: float, t2: float) -> Color:
				var d := Vector2(p.x, p.z).length()
				if d < 0.0065:
					return Color(0.72, 0.5, 0.42)
				if d < 0.011:
					return Color(0.95, 0.9, 0.8)
				var c := Color(0.55, 0.13, 0.13).darkened(0.1 * _nz(p, 70.0) + 0.12 * pow(absf(sin(a * 4.0 + d * 90.0)), 12.0))
				return c.lerp(Color(0.9, 0.78, 0.7), 1.0 - smoothstep(0.03, 0.08, t2))
			lathe(k, "pv_soft", leg, _curve([Vector2(0.073, 0.168), Vector2(0.05, 0.1695), Vector2(0.02, 0.1705), Vector2(0, 0.171)], 3), 36, face, plump)
			# The bare bone: a shaft out of the shank ending in a double knuckle.
			var bone := Color(0.9, 0.86, 0.76)
			tube(k, "pv_bone", leg, PackedVector3Array([Vector3(0, 0.02, 0), Vector3(0, -0.03, 0), Vector3(0, -0.06, 0)]), PackedFloat32Array([0.0085, 0.0075, 0.0085]), 12, bone)
			for sx in [-1.0, 1.0]:
				lathe(k, "pv_bone", leg * Transform3D(Basis.IDENTITY, Vector3(sx * 0.0075, -0.066, 0)), _sphere(0.0105, 8, 0.85), 14, bone.lightened(0.05))
			return leg * Vector3(0, 0.0, 0)
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
			var col := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.7, 0.45, 0.2).lerp(Color(0.42, 0.22, 0.08), clampf(_nz(p, 35.0) * 1.2 + 0.25, 0.0, 1.0)).lerp(Color(0.85, 0.66, 0.38), 0.3 * clampf(_nz(p + Vector3(5, 0, 0), 90.0), 0.0, 1.0))
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
			# A rough-cut slab of salt pork: lean and fat in uneven bands on the cut face,
			# a leathery brown rind on top, coarse salt caught in the creases.
			var slab := func(a: float, _t: float, p: Vector3) -> float:
				return (1.0 / pow(pow(absf(cos(a)), 6.0) + pow(absf(sin(a)), 6.0), 1.0 / 6.0)) * (1.0 + 0.05 * _nz(p, 18.0))
			var layers := func(p: Vector3, _a: float, t2: float) -> Color:
				var y := p.y + 0.08 * _nz(p, 3.0)
				var band := fposmod(y * 4.2 + 0.25 * _nz(p, 2.0), 1.0)
				var c := Color(0.5, 0.15, 0.13) if band < 0.72 else Color(0.8, 0.66, 0.56)
				if p.y > 0.93:
					c = Color(0.5, 0.32, 0.18)
				return c.darkened(0.1 * _nz(p, 6.0))
			var prof := _curve([Vector2(0, 0.0), Vector2(0.9, 0.0), Vector2(0.98, 0.08), Vector2(1.0, 0.5), Vector2(0.96, 0.9), Vector2(0.88, 0.98), Vector2(0.5, 1.0), Vector2(0, 1.01)], 3)
			lathe(k, "pv_meat", Transform3D(Basis.from_scale(Vector3(0.052, 0.042, 0.034)) * Basis(Vector3.UP, 0.0), Vector3.ZERO), prof, 40, layers, slab)
			var rs := RandomNumberGenerator.new()
			rs.seed = 5
			for i in 12:
				var at := Vector3(rs.randf_range(-0.04, 0.04), 0.042, rs.randf_range(-0.025, 0.025))
				k.box("pv_soft", Transform3D(Basis(Vector3(rs.randf(), rs.randf(), rs.randf()).normalized(), rs.randf() * PI), at), Vector3.ONE * rs.randf_range(0.0018, 0.0032), Color(0.93, 0.92, 0.88))
			return Vector3(0, 0.02, 0)
		"jerky":
			# Strips of dried meat lying across each other: thin and flat, twisted as they
			# dried, ragged along the edges, almost black with a ruddy tint where thin.
			var rj := RandomNumberGenerator.new()
			rj.seed = 9
			var dry := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.26, 0.1, 0.05).lerp(Color(0.5, 0.25, 0.12), clampf(_nz(p, 70.0) + 0.2, 0.0, 1.0))
			for i in 4:
				var yaw := rj.randf_range(-0.5, 0.5) + i * 0.35
				var lift := 0.003 + i * 0.0028
				var len := rj.randf_range(0.1, 0.13)
				var wid := rj.randf_range(0.018, 0.026)
				var seed_off := Vector3(i * 3.1, 0, 0)
				var strip := func(u: float, v: float) -> Vector3:
					var x := (u - 0.5) * len
					var edge := 1.0 + 0.18 * _nz(Vector3(x * 40.0, 0, v) + seed_off, 1.0)
					var z := (v - 0.5) * wid * edge
					var twist := 0.35 * sin(u * 3.0 + i)
					return Vector3(x, lift + 0.004 * sin(u * 6.0 + i) + z * sin(twist) + 0.0015 * _nz(Vector3(x, 0, z) * 60.0 + seed_off, 1.0), z * cos(twist))
				for side in [1.0, -1.0]:
					var thick := func(u: float, v: float) -> Vector3: return strip.call(u, v) + Vector3(0, side * 0.0012, 0)
					sheet(k, "pv_roast", Transform3D(Basis(Vector3.UP, yaw), Vector3((i - 1.5) * 0.008, 0, (i - 1.5) * 0.018)), 14, 3, thick, dry, Vector3(0, side, 0))
			return Vector3(0, 0.01, 0)
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
		"stew", "porridge", "soup_veg", "chili":
			# A bowl filled near the brim: a glazed clay bowl of stew, a wooden one of
			# porridge, a clay one of soup, a tin one of chili. The surface wets the bowl's
			# side in a meniscus and has a sheen; chunks break through it.
			var bowl: String = {"stew": "pv_glaze", "porridge": "pv_wood", "soup_veg": "pv_glaze", "chili": "pv_tin"}[t]
			var bowl_col: Color = {"stew": Color(0.42, 0.24, 0.14), "porridge": Color(0.55, 0.36, 0.2), "soup_veg": Color(0.44, 0.24, 0.12), "chili": Color(0.42, 0.42, 0.44)}[t]
			var thin := t == "chili"
			var outer := _curve([Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.033, 0.004), Vector2(0.055, 0.02), Vector2(0.068, 0.045), Vector2(0.07, 0.05), Vector2(0.07, 0.05)], 3)
			var inner := _inset(outer, 0.0018 if thin else 0.005, 0.008)
			var shell := PackedVector2Array(outer)
			shell.append(Vector2(0.0685 if thin else 0.065, 0.05))
			shell.append_array(inner)
			shell.append(Vector2(0, 0.008))
			lathe(k, bowl, I, shell, 40, func(p: Vector3, _a: float, _t: float) -> Color: return bowl_col.darkened(0.12 * _nz(p, 30.0)))
			var fill: Color = {"stew": Color(0.36, 0.17, 0.07), "porridge": Color(0.78, 0.66, 0.46), "soup_veg": Color(0.48, 0.26, 0.04), "chili": Color(0.4, 0.1, 0.04)}[t]
			var surf := 0.042
			var r_s := _radius_at(inner, surf)
			var thick := t == "porridge"
			var top := func(_a: float, _t: float, p: Vector3) -> float: return 1.0
			lathe(k, "pv_crumb" if thick else "pv_glossy", I, _curve([Vector2(r_s - 0.0005, surf + 0.002), Vector2(r_s - 0.003, surf), Vector2(r_s * 0.5, surf - 0.0005 + (0.004 if thick else 0.0)), Vector2(0, surf + (0.006 if thick else -0.0006))], 3), 40, func(p: Vector3, _a: float, _t: float) -> Color: return fill.darkened(0.15 * _nz(p, 60.0)).lerp(fill.lightened(0.25), 0.5 if thick and _nz(p, 500.0) > 0.4 else 0.0), top)
			var bits: Dictionary = {"stew": [Color(0.75, 0.42, 0.12), Color(0.92, 0.82, 0.48), Color(0.33, 0.14, 0.07), Color(0.32, 0.45, 0.16)], "soup_veg": [Color(0.9, 0.4, 0.06), Color(0.86, 0.68, 0.3), Color(0.22, 0.45, 0.12), Color(0.9, 0.42, 0.08)], "chili": [Color(0.42, 0.13, 0.07), Color(0.52, 0.18, 0.09)], "porridge": [Color(0.42, 0.06, 0.12)]}
			var rc := RandomNumberGenerator.new()
			rc.seed = WHash.str_hash(t)
			var cs: Array = bits[t]
			var n := {"stew": 16, "soup_veg": 18, "chili": 40, "porridge": 6}[t] as int
			for i in n:
				var a := rc.randf() * TAU
				var d := sqrt(rc.randf()) * (r_s - 0.012)
				var c: Color = cs[i % cs.size()]
				var at := Vector3(cos(a) * d, surf - 0.001, sin(a) * d)
				var lump := func(_a2: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.2 * _nz(p + Vector3(i, 0, 0), 300.0)
				if t == "chili":
					# Kidney beans, half sunk.
					lathe(k, "pv_glossy", Transform3D(Basis(Vector3.UP, rc.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5), at), _sphere(0.0045, 6, 1.7), 10, c)
				elif t == "porridge":
					# A few berries dropped on top.
					lathe(k, "pv_skin", Transform3D(Basis.IDENTITY, at + Vector3(0, 0.006, 0)), _sphere(0.004, 6), 10, c)
				else:
					var sz := rc.randf_range(0.006, 0.011)
					lathe(k, "pv_soft", Transform3D(Basis(Vector3(rc.randf(), rc.randf(), rc.randf()).normalized(), rc.randf() * 2.0), at + Vector3(0, sz * 0.2, 0)), _sphere(sz, 6, 0.8), 10, c, lump)
			return Vector3(0, 0.025, 0)
		"pie_meat", "pie_berry":
			# A pie in its fluted crust: the meat pie domed, glazed and vented; the berry
			# pie open under a lattice.
			var crimp := func(a: float, t2: float, _p: Vector3) -> float: return 1.0 + 0.035 * sin(a * 28.0) * smoothstep(0.55, 0.8, t2)
			var crust := Color(0.76, 0.48, 0.2) if t == "pie_berry" else Color(0.82, 0.58, 0.28)
			var bake := func(p: Vector3, _a: float, t2: float) -> Color: return crust.darkened(0.3 * clampf(_nz(p, 30.0) + 0.3 * t2, 0.0, 1.0))
			lathe(k, "pv_crust", I, _curve([Vector2(0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.0), Vector2(0.068, 0.032), Vector2(0.076, 0.038), Vector2(0.074, 0.044), Vector2(0.066, 0.04)], 3), 56, bake, crimp)
			if t == "pie_berry":
				# The filling heaped to the rim, lumpy with whole berries.
				lathe(k, "pv_glossy", I, _curve([Vector2(0.066, 0.038), Vector2(0.045, 0.0415), Vector2(0, 0.0425)], 2), 40, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.24, 0.04, 0.12).lightened(0.12 * _nz(p, 120.0)), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.04 * _nz(p, 200.0))
				var rb := RandomNumberGenerator.new()
				rb.seed = 31
				for i in 26:
					var a := rb.randf() * TAU
					var d := sqrt(rb.randf()) * 0.058
					lathe(k, "pv_glossy", Transform3D(Basis.IDENTITY, Vector3(cos(a) * d, 0.0415, sin(a) * d)), _sphere(0.0045, 5), 8, Color(0.2, 0.05, 0.16).lightened(rb.randf_range(0.0, 0.12)))
				for i in 4:
					var o := (i - 1.5) * 0.03
					for dir in [0.0, PI * 0.5]:
						var len := 2.0 * sqrt(maxf(0.0, 0.066 * 0.066 - o * o))
						k.box("pv_crust", Transform3D(Basis(Vector3.UP, dir), Vector3(o, 0.0455 + (0.002 if (i + int(dir > 0.0)) % 2 == 0 else 0.0), 0).rotated(Vector3.UP, dir)), Vector3(0.012, 0.004, len), crust.lightened(0.06))
			else:
				var top := Color(0.78, 0.5, 0.2) if t == "pie_meat" else Color(0.85, 0.62, 0.25)
				lathe(k, "pv_crust", I, _curve([Vector2(0.068, 0.04), Vector2(0.05, 0.058), Vector2(0.025, 0.066), Vector2(0, 0.068)], 3), 40, func(p: Vector3, _a: float, _t: float) -> Color: return top.darkened(0.25 * clampf(_nz(p, 25.0) + 0.2, 0.0, 1.0)), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.03 * _nz(p, 20.0))
				for i in 4:
					var a := TAU * i / 4.0 + 0.4
					var vx := Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, -0.18), Vector3(cos(a) * 0.016, 0.0655, sin(a) * 0.016))
					# The dark slit, gravy-stained, and the crust lifted either side of it.
					k.box("pv_glossy", vx, Vector3(0.0045, 0.0025, 0.018), Color(0.2, 0.08, 0.03))
					for sx in [-1.0, 1.0]:
						tube(k, "pv_crust", vx, PackedVector3Array([Vector3(sx * 0.0034, 0.0, -0.01), Vector3(sx * 0.0042, 0.0014, 0.0), Vector3(sx * 0.0034, 0.0, 0.01)]), PackedFloat32Array([0.0008, 0.002, 0.0008]), 5, top.darkened(0.05))
			return Vector3(0, 0.02, 0)
		"cornbread":
			# A thick square of cornbread cut from the pan: golden crumb on the cut sides,
			# a domed, cracked, browned top and a darker base where it sat in the iron.
			var col := func(p: Vector3, _a: float, _t: float) -> Color:
				var c := Color(0.86, 0.7, 0.36)
				var crust := smoothstep(0.86, 0.97, p.y)
				c = c.lerp(Color(0.7, 0.44, 0.16), crust)
				return c.lerp(Color(0.5, 0.3, 0.12), smoothstep(0.08, 0.0, p.y))
			rounded_box(k, "pv_crumb", I, Vector3(0.075, 0.042, 0.075), 0.004, col, 10.0)
			return Vector3(0, 0.02, 0)
		"cheese_wheel_small":
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
	return _packed(k, t)

# --- Packets, kits, sacks, barrels, herbs and alien fare -----------------------------------

## A surface over a grid: `f(u, v)` gives each point (u, v in 0..1); normals face along
## `out` (or away from the middle when `out` is zero).
static func sheet(k: MeshKit, mat: String, xf: Transform3D, nu: int, nv: int, f: Callable, col: Variant = Color.WHITE, out := Vector3.ZERO) -> void:
	var P := []
	for j in nv + 1:
		var row := PackedVector3Array()
		for i in nu + 1:
			row.append(f.call(float(i) / nu, float(j) / nv))
		P.append(row)
	var st := k._tool(mat)
	var nb := xf.basis.inverse().transposed()
	var N := []
	for j in nv + 1:
		var row := PackedVector3Array()
		for i in nu + 1:
			var du: Vector3 = (P[j] as PackedVector3Array)[mini(i + 1, nu)] - (P[j] as PackedVector3Array)[maxi(i - 1, 0)]
			var dv: Vector3 = (P[mini(j + 1, nv)] as PackedVector3Array)[i] - (P[maxi(j - 1, 0)] as PackedVector3Array)[i]
			var n := du.cross(dv).normalized()
			var p: Vector3 = (P[j] as PackedVector3Array)[i]
			var want := out if out != Vector3.ZERO else p
			if n.dot(want) < 0.0:
				n = -n
			row.append(n)
		N.append(row)
	for j in nv:
		for i in nu:
			var q := [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]
			var ps := []
			var ns := []
			var cs := []
			var uvs := []
			for e in q:
				var p: Vector3 = (P[e[1]] as PackedVector3Array)[e[0]]
				ps.append(p)
				ns.append((N[e[1]] as PackedVector3Array)[e[0]])
				cs.append(_colour(col, p, float(e[0]) / nu, float(e[1]) / nv))
				uvs.append(Vector2(float(e[0]) / nu, 1.0 - float(e[1]) / nv))
			for tri in [[0, 1, 2], [1, 3, 2]]:
				_tri(st, xf, nb, [ps[tri[0]], ps[tri[1]], ps[tri[2]]], [ns[tri[0]], ns[tri[1]], ns[tri[2]]], [cs[tri[0]], cs[tri[1]], cs[tri[2]]], [uvs[tri[0]], uvs[tri[1]], uvs[tri[2]]])

## A sealed packet: two sheets puffed out by what's inside and crinkled, crimped seals
## top and bottom. Stands along +Y from y = 0, `w` wide.
static func pouch(k: MeshKit, mat: String, xf: Transform3D, w: float, h: float, bulge: float, col: Variant, seal := 0.012, crinkle := 0.25) -> void:
	for side in [1.0, -1.0]:
		var f := func(u: float, v: float) -> Vector3:
			var y := v * h
			var inner := clampf((y - seal) / maxf(h - 2.0 * seal, 0.001), 0.0, 1.0)
			var puff := pow(sin(PI * u) * sin(PI * inner), 0.6)
			var p := Vector3((u - 0.5) * w * (1.0 - 0.06 * puff), y, 0.0)
			p.z = side * bulge * puff * (1.0 + crinkle * _nz(p, 90.0))
			return p
		sheet(k, mat, xf, 16, 20, f, col, Vector3(0, 0, side))
	# The crimped seals: fine ridges across each end.
	for y in [seal * 0.5, h - seal * 0.5]:
		for i in 8:
			k.box(mat, xf * Transform3D(Basis.IDENTITY, Vector3(0, y - seal * 0.4 + seal * 0.8 * i / 7.0, 0)), Vector3(w, seal * 0.06, 0.0012), _colour(col, Vector3(0, y, 0), 0.5, y / h))

## A box with rounded edges standing on y = 0: a lathe squared off by a superellipse.
static func rounded_box(k: MeshKit, mat: String, xf: Transform3D, size: Vector3, round_r: float, col: Variant, sharp := 8.0, shape_extra: Variant = null) -> void:
	var rr := clampf(round_r / maxf(size.y, 0.001), 0.0, 0.45)
	var prof := _curve([Vector2(0, 0.0), Vector2(1.0 - rr * 1.2, 0.0), Vector2(1.0 - rr * 0.3, rr * 0.3), Vector2(1.0, rr), Vector2(1.0, 1.0 - rr), Vector2(1.0 - rr * 0.3, 1.0 - rr * 0.3), Vector2(1.0 - rr * 1.2, 1.0), Vector2(0, 1.0)], 2)
	var sq := func(a: float, t: float, p: Vector3) -> float:
		var m := 1.0 / pow(pow(absf(cos(a)), sharp) + pow(absf(sin(a)), sharp), 1.0 / sharp)
		return m * (shape_extra.call(a, t, p) if shape_extra is Callable else 1.0)
	lathe(k, mat, xf * Transform3D(Basis.from_scale(Vector3(size.x * 0.5, size.y, size.z * 0.5)), Vector3.ZERO), prof, 40, col, sq)

## A white cross on a medical kit, on the face whose normal is `n`.
static func _cross(k: MeshKit, xf: Transform3D, at: Vector3, n: Vector3, s: float, col := Color(0.95, 0.95, 0.93)) -> void:
	var b := _facing(n)
	k.box("pv_plastic", xf * Transform3D(b, at), Vector3(s, 0.002, s * 0.32), col)
	k.box("pv_plastic", xf * Transform3D(b, at), Vector3(s * 0.32, 0.002, s), col)

## A wooden barrel of `staves` staves bound with iron hoops, `h` tall.
## With `floor_y` at or above 0 it is open: no top head, the staves' inner faces showing
## down to a floor at that height.
static func barrel(k: MeshKit, xf: Transform3D, r: float, h: float, staves := 18, wood := Color(0.48, 0.3, 0.16), floor_y := -1.0) -> void:
	var bulge := func(a: float, _t: float, _p: Vector3) -> float:
		# A groove between each stave.
		return 1.0 - 0.012 * pow(absf(cos(a * staves * 0.5)), 30.0)
	var col := func(p: Vector3, a: float, _t: float) -> Color:
		var stave := floorf(a / TAU * staves)
		return wood.darkened(0.18 * fposmod(stave * 0.618, 1.0) + 0.12 * _nz(p * Vector3(1, 0.15, 1), 60.0))
	var prof := _curve([Vector2(r * 0.86, 0.0), Vector2(r * 0.97, h * 0.25), Vector2(r, h * 0.5), Vector2(r * 0.97, h * 0.75), Vector2(r * 0.86, h)], 4)
	lathe(k, "pv_wood", xf, prof, staves * 3, col, bulge)
	var wall := maxf(0.006, r * 0.07)
	if floor_y >= 0.0:
		# The inside: staves seen from within, a rim across their ends, the floor.
		var inner := PackedVector2Array()
		for i in range(prof.size() - 1, -1, -1):
			if prof[i].y >= floor_y - 0.001:
				inner.append(Vector2(prof[i].x - wall, prof[i].y))
		inner.append(Vector2(_radius_at(prof, floor_y) - wall, floor_y))
		lathe(k, "pv_wood", xf, inner, staves * 3, func(p: Vector3, a: float, t2: float) -> Color: return (col.call(p, a, t2) as Color).darkened(0.35 * t2), bulge)
		lathe(k, "pv_wood", xf, PackedVector2Array([Vector2(prof[prof.size() - 1].x, h), Vector2(prof[prof.size() - 1].x - wall, h)]), staves * 3, col)
		lathe(k, "pv_wood", xf, PackedVector2Array([Vector2(_radius_at(prof, floor_y) - wall, floor_y), Vector2(0, floor_y)]), 24, wood.darkened(0.45))
	for y in ([0.0] if floor_y >= 0.0 else [0.0, h]):
		# The heads, sunk a little inside the chime.
		var hy: float = y + (0.012 if y == 0.0 else -0.012)
		lathe(k, "pv_wood", xf, PackedVector2Array([Vector2(0, hy), Vector2(r * 0.86, hy)]) if y > 0.0 else PackedVector2Array([Vector2(r * 0.86, hy), Vector2(0, hy)]), 24, func(p: Vector3, _a: float, _t: float) -> Color: return wood.darkened(0.25 * fposmod(floorf(p.x * 18.0 / r) * 0.618, 1.0)))
	for f in [0.06, 0.2, 0.8, 0.94]:
		var y: float = h * f
		var rr := _radius_at(prof, y) + 0.0015
		var hw := minf(0.012, h * 0.025)
		lathe(k, "iron", xf, PackedVector2Array([Vector2(rr, y - hw), Vector2(rr + hw * 0.17, y), Vector2(rr, y + hw)]), staves * 3, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.42, 0.4, 0.38).lerp(Color(0.45, 0.25, 0.12), clampf(_nz(p, 50.0), 0.0, 0.7)))

## A sprig: a stem with leaves in pairs up it, and maybe flowers or berries at the top.
static func sprig(k: MeshKit, xf: Transform3D, h: float, leaf_col: Color, leaf_len: float, pairs := 4, flower := Color(0, 0, 0, 0), berry := Color(0, 0, 0, 0)) -> void:
	var stem := PackedVector3Array()
	for i in 6:
		var f := i / 5.0
		stem.append(Vector3(0.01 * sin(f * 3.0), f * h, 0.006 * sin(f * 5.0)))
	tube(k, "pv_leaf", xf, stem, PackedFloat32Array([0.0022, 0.002, 0.0018, 0.0015, 0.0012, 0.001]), 5, leaf_col.darkened(0.2), false)
	for i in pairs:
		var f := 0.25 + 0.6 * i / maxf(1.0, pairs - 1.0)
		var at := Vector3(0.01 * sin(f * 3.0), f * h, 0.006 * sin(f * 5.0))
		var l := leaf_len * (1.0 - 0.4 * f)
		for sd in [-1.0, 1.0]:
			leaf(k, xf * Transform3D(Basis(Vector3.UP, i * 1.57 + (0.0 if sd > 0.0 else PI)) * Basis(Vector3.FORWARD, -sd * 1.0), at), l, l * 0.45, leaf_col.lightened(0.05 * sd), 0.25, 5)
	var top := stem[5]
	if flower.a > 0.0:
		for i in 6:
			var a := TAU * i / 6.0
			leaf(k, xf * Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 1.2), top), 0.014, 0.009, flower, -0.2, 3)
		lathe(k, "pv_skin", xf * Transform3D(Basis.IDENTITY, top), _sphere(0.0035, 5), 8, flower.darkened(0.4))
	if berry.a > 0.0:
		for i in 5:
			var a := TAU * i / 5.0
			lathe(k, "pv_skin", xf * Transform3D(Basis.IDENTITY, top + Vector3(cos(a) * 0.012, -0.012 - 0.004 * (i % 2), sin(a) * 0.012)), _sphere(0.0055, 7), 10, berry)

## A burlap sack, plump at the bottom, its neck gathered and tied (or rolled open).
static func sack(k: MeshKit, xf: Transform3D, r: float, h: float, open: bool, col := Color(0.66, 0.55, 0.38)) -> PackedVector2Array:
	var lumpy := func(a: float, t: float, p: Vector3) -> float: return 1.0 + 0.08 * _nz(p, 14.0) + 0.04 * sin(a * 7.0) * t
	var prof: PackedVector2Array
	if open:
		prof = _curve([Vector2(0, 0.0), Vector2(r * 0.8, 0.004), Vector2(r, h * 0.2), Vector2(r * 1.02, h * 0.6), Vector2(r * 0.95, h * 0.85), Vector2(r * 1.05, h * 0.9), Vector2(r * 1.08, h * 0.95), Vector2(r * 0.98, h), Vector2(r * 0.9, h * 0.94)], 3)
	else:
		prof = _curve([Vector2(0, 0.0), Vector2(r * 0.8, 0.004), Vector2(r, h * 0.2), Vector2(r * 1.02, h * 0.5), Vector2(r * 0.7, h * 0.75), Vector2(r * 0.18, h * 0.84), Vector2(r * 0.2, h * 0.9), Vector2(r * 0.45, h), Vector2(r * 0.1, h * 0.97), Vector2(0, h * 0.93)], 3)
	lathe(k, "pv_burlap", xf, prof, 36, func(p: Vector3, _a: float, _t: float) -> Color: return col.darkened(0.15 * _nz(p, 20.0)), lumpy)
	if not open:
		twine(k, xf, r * 0.19, h * 0.84, 3)
	return prof

## A hypodermic or auto-injector along +Y: a glass barrel showing its dose, a plunger
## or cap at the back, a fine needle at the front (+Y).
static func injector(k: MeshKit, xf: Transform3D, r: float, length: float, dose: Color, cap_col: Color, glass_syringe := false) -> void:
	var outer := [Vector2(0, 0.0), Vector2(r, 0.0), Vector2(r, 0.0), Vector2(r, length), Vector2(r, length), Vector2(r * 0.4, length + 0.006)]
	vessel(k, xf, outer, 0.0012, CLEAR, dose, length * 0.75, 18)
	k.cylinder("metal", xf * Transform3D(Basis.IDENTITY, Vector3(0, length + 0.005, 0)), 0.0006, 0.0003, length * 0.45, 6, true, 0.0, 1, Color(0.85, 0.85, 0.88))
	if glass_syringe:
		# Finger flanges and the plunger with its thumb ring.
		k.box("metal", xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0)), Vector3(r * 5.0, 0.003, r * 1.6), Color(0.75, 0.72, 0.66))
		k.cylinder("metal", xf * Transform3D(Basis.IDENTITY, Vector3(0, -length * 0.45, 0)), r * 0.25, r * 0.25, length * 0.5, 6, true, 0.0, 1, Color(0.75, 0.72, 0.66))
		var ring := PackedVector3Array()
		var rr := PackedFloat32Array()
		for s in 17:
			var a := TAU * s / 16.0
			ring.append(Vector3(cos(a) * r * 1.4, -length * 0.45 - r * 1.4 + sin(a) * r * 1.4, 0))
			rr.append(r * 0.25)
		tube(k, "metal", xf, ring, rr, 6, Color(0.75, 0.72, 0.66), false)
	else:
		lathe(k, "pv_plastic", xf, _curve([Vector2(0, -length * 0.5), Vector2(r * 1.1, -length * 0.48), Vector2(r * 1.25, -length * 0.3), Vector2(r * 1.25, 0.0), Vector2(r * 1.25, 0.0), Vector2(r * 0.9, 0.004)], 2), 20, cap_col)
		lathe(k, "pv_plastic", xf, PackedVector2Array([Vector2(r * 1.15, length - 0.008), Vector2(r * 1.15, length + 0.004), Vector2(r * 1.15, length + 0.004), Vector2(r * 0.5, length + 0.008)]), 20, cap_col.darkened(0.3))

static func _packed(k: MeshKit, t: String) -> Variant:
	var I := Transform3D.IDENTITY
	match t:
		# Space-age packets -----------------------------------------------------------
		"ration_pack", "protein_pack", "space_coffee", "freeze_meal":
			var foil := Color(0.72, 0.73, 0.75)
			var w := 0.11
			var h := 0.15
			match t:
				"space_coffee":
					foil = Color(0.24, 0.17, 0.12)
					w = 0.09
					h = 0.12
				"protein_pack":
					w = 0.1
					h = 0.13
			pouch(k, "pv_foil", I, w, h, 0.016 if t != "freeze_meal" else 0.024, foil, 0.012, 0.3)
			match t:
				"ration_pack":
					decal(k, "pv_label_white", I, Vector3(0, 0.075, 0.0185), Vector3.BACK, 0.07, 0.05)
				"protein_pack":
					decal(k, "pv_label_white", I, Vector3(0, 0.06, 0.0185), Vector3.BACK, 0.06, 0.035)
				"space_coffee":
					# The one-way valve on a coffee bag.
					k.cylinder("pv_plastic", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.085, 0.017)), 0.007, 0.007, 0.0015, 14, true, 0.0, 1, Color(0.1, 0.08, 0.07))
				"freeze_meal":
					# Torn open: the meal shows inside the top.
					lathe(k, "pv_crumb", I, PackedVector2Array([Vector2(0.045, 0.14), Vector2(0, 0.145)]), 20, func(p: Vector3, _a: float, _t: float) -> Color: return [Color(0.8, 0.6, 0.3), Color(0.5, 0.65, 0.2), Color(0.8, 0.3, 0.15)][int(absf(_nz(p, 300.0)) * 6.0) % 3], func(a: float, _t: float, _p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)), 4.0) + pow(absf(sin(a)) * 2.4, 4.0), 0.25))
			return Vector3(0, h * 0.5, 0)
		"water_pouch", "fruit_cube", "bio_gel":
			# Clear plastic: what's inside shows through.
			var w := 0.1 if t != "bio_gel" else 0.07
			var h := 0.13 if t != "bio_gel" else 0.07
			var fill := WATER if t == "water_pouch" else (Color(0.2, 0.75, 0.68, 0.7) if t == "bio_gel" else Color(0, 0, 0, 0))
			pouch(k, "pv_glass", I, w, h, 0.018 if t != "bio_gel" else 0.007, Color(0.9, 0.94, 0.96, 0.12), 0.01, 0.1)
			if fill.a > 0.0:
				pouch(k, "pv_liquid", Transform3D(Basis.from_scale(Vector3(0.94, 0.9, 0.85)), Vector3(0, 0.004, 0)), w, h * (0.8 if t == "water_pouch" else 1.0), 0.016 if t != "bio_gel" else 0.006, fill, 0.012, 0.0)
			if t == "water_pouch":
				lathe(k, "pv_plastic", I, PackedVector2Array([Vector2(0.008, h - 0.004), Vector2(0.008, h + 0.012), Vector2(0.008, h + 0.012), Vector2(0.011, h + 0.013), Vector2(0.011, h + 0.024), Vector2(0.011, h + 0.024), Vector2(0, h + 0.025)]), 16, Color(0.92, 0.92, 0.9))
			elif t == "fruit_cube":
				var rf := RandomNumberGenerator.new()
				rf.seed = 4
				var cs := [Color(0.9, 0.2, 0.3), Color(0.95, 0.65, 0.15), Color(0.95, 0.85, 0.2), Color(0.5, 0.2, 0.55), Color(0.85, 0.35, 0.15)]
				for i in 18:
					k.box("pv_glossy", Transform3D(Basis(Vector3(rf.randf(), rf.randf(), rf.randf()).normalized(), rf.randf()), Vector3(rf.randf_range(-0.035, 0.035), rf.randf_range(0.02, 0.09), rf.randf_range(-0.008, 0.008))), Vector3.ONE * 0.016, cs[i % cs.size()])
			return Vector3(0, h * 0.5, 0)
		"ration_bar", "algae_bar":
			# A dense bar; the ration bar half out of its torn foil wrapper.
			var bar := Color(0.45, 0.3, 0.16) if t == "ration_bar" else Color(0.22, 0.32, 0.12)
			var lumpy := func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.04 * _nz(p, 300.0)
			rounded_box(k, "pv_crumb", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.06, 0.012, 0)), Vector3(0.024, 0.12, 0.036), 0.004, func(p: Vector3, _a: float, _t: float) -> Color: return bar.darkened(0.25 * _nz(p, 400.0)), 8.0, lumpy)
			if t == "ration_bar":
				rounded_box(k, "pv_foil", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.062, 0.012, 0)), Vector3(0.028, 0.08, 0.04), 0.004, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.2, 0.45, 0.75) if absf(p.y - 0.5) < 0.18 else Color(0.75, 0.76, 0.78))
				# The crimped end, and the torn edge where it was opened.
				for i in 6:
					k.box("pv_foil", Transform3D(Basis.IDENTITY, Vector3(0.066 + 0.0015 * i, 0.012, 0)), Vector3(0.0008, 0.026, 0.042), Color(0.75, 0.76, 0.78))
			return Vector3(0.03, 0.012, 0)
		"nutri_paste":
			# A squeeze tube: round at the cap, crimped flat at the far end.
			var flat := func(a: float, t2: float, _p: Vector3) -> float: return lerpf(1.0, absf(cos(a)) * 1.25 + 0.06, smoothstep(0.2, 0.95, t2))
			lathe(k, "pv_paint", I, _curve([Vector2(0.008, 0.0), Vector2(0.016, 0.006), Vector2(0.017, 0.03), Vector2(0.017, 0.1), Vector2(0.017, 0.135)], 3), 28, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.15, 0.4, 0.7) if absf(p.y - 0.07) < 0.012 else Color(0.85, 0.86, 0.86), flat)
			k.box("pv_paint", Transform3D(Basis.IDENTITY, Vector3(0, 0.138, 0)), Vector3(0.045, 0.008, 0.002), Color(0.8, 0.81, 0.82))
			lathe(k, "pv_plastic", I, _curve([Vector2(0.007, 0.002), Vector2(0.007, -0.016), Vector2(0.007, -0.016), Vector2(0, -0.017)], 2), 16, Color(0.95, 0.95, 0.94), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.05 * pow(absf(sin(a * 10.0)), 3.0))
			return Vector3(0, 0.06, 0)
		"noodles":
			# A paper cup of instant noodles, lid peeled back.
			var cup := _curve([Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.032, 0.004), Vector2(0.045, 0.1), Vector2(0.045, 0.1), Vector2(0.047, 0.102), Vector2(0.046, 0.104), Vector2(0.046, 0.104), Vector2(0.043, 0.1), Vector2(0.03, 0.006), Vector2(0, 0.006)], 2)
			lathe(k, "pv_soft", I, cup, 36, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.78, 0.12, 0.1) if p.y > 0.04 and p.y < 0.06 else Color(0.95, 0.94, 0.9))
			lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0.042, 0.088), Vector2(0, 0.09)]), 28, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.86, 0.66, 0.32).darkened(0.25 * absf(sin(p.x * 900.0 + sin(p.z * 700.0) * 3.0))).lerp(Color(0.3, 0.6, 0.2), 0.8 if _nz(p, 700.0) > 0.55 else 0.0))
			sheet(k, "pv_foil", I, 8, 8, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * 0.09, 0.104 + v * 0.06 * v, -0.045 + v * 0.03 - 0.02 * sin(u * PI) * v), Color(0.8, 0.8, 0.82), Vector3(0, 0, 1))
			return Vector3(0, 0.05, 0)
		"hydro_greens":
			# A steel grow tray of lettuce.
			var tray := _curve([Vector2(0, 0.0), Vector2(0.9, 0.0), Vector2(0.9, 0.0), Vector2(1.0, 1.0), Vector2(1.0, 1.0), Vector2(0.94, 1.0), Vector2(0.86, 0.15), Vector2(0, 0.15)], 1)
			lathe(k, "pv_tin", Transform3D(Basis.from_scale(Vector3(0.07, 0.04, 0.045)), Vector3.ZERO), tray, 40, Color(0.7, 0.72, 0.74), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)), 10.0) + pow(absf(sin(a)), 10.0), 0.1))
			var rl := RandomNumberGenerator.new()
			rl.seed = 8
			for i in 22:
				var at := Vector3(rl.randf_range(-0.05, 0.05), 0.012, rl.randf_range(-0.03, 0.03))
				leaf(k, Transform3D(Basis(Vector3.UP, rl.randf() * TAU) * Basis(Vector3.RIGHT, rl.randf_range(0.3, 0.9)), at), rl.randf_range(0.035, 0.055), 0.03, Color(0.25, 0.5, 0.15).lightened(rl.randf_range(-0.1, 0.15)), 0.35, 5)
			return Vector3(0, 0.02, 0)
		# Medicine ---------------------------------------------------------------------
		"medkit_frontier":
			# A leather doctor's bag: a fat body on a hinged metal frame, a handle, a clasp.
			var hide := Color(0.32, 0.18, 0.1)
			rounded_box(k, "pv_leather", I, Vector3(0.24, 0.13, 0.11), 0.03, func(p: Vector3, _a: float, _t: float) -> Color: return hide.darkened(0.2 * _nz(p, 6.0)), 4.0, func(_a: float, t2: float, _p: Vector3) -> float: return 1.0 - 0.25 * smoothstep(0.6, 1.0, t2))
			k.box("metal", I.translated(Vector3(0, 0.131, 0)), Vector3(0.2, 0.006, 0.02), Color(0.7, 0.6, 0.4))
			k.box("gold", I.translated(Vector3(0, 0.12, 0.04)), Vector3(0.016, 0.014, 0.004), Color(0.8, 0.65, 0.35))
			var handle := PackedVector3Array()
			var hr := PackedFloat32Array()
			for s in 11:
				var a := PI * s / 10.0
				handle.append(Vector3(cos(a) * 0.05, 0.135 + sin(a) * 0.035, 0))
				hr.append(0.007)
			tube(k, "pv_leather", I, handle, hr, 8, hide.darkened(0.2))
			_cross(k, I, Vector3(0, 0.06, 0.0535), Vector3.BACK, 0.035)
			return Vector3(0, 0.16, 0)
		"medkit_mil", "trauma_kit":
			# A hard olive case with latches, or an orange soft pack with straps.
			var mil := t == "medkit_mil"
			var body := Color(0.3, 0.36, 0.22) if mil else Color(0.9, 0.38, 0.1)
			rounded_box(k, "pv_paint" if mil else "pv_cloth", I, Vector3(0.24, 0.15, 0.09), 0.015 if mil else 0.035, func(p: Vector3, _a: float, _t: float) -> Color: return body.darkened(0.12 * _nz(p, 20.0)), 10.0 if mil else 4.0)
			if mil:
				for sx in [-0.07, 0.07]:
					k.box("metal_dark", I.translated(Vector3(sx, 0.1, 0.046)), Vector3(0.025, 0.03, 0.006))
				k.box("metal_dark", I.translated(Vector3(0, 0.075, 0.0)), Vector3(0.242, 0.006, 0.092))
			else:
				for sx in [-0.07, 0.07]:
					k.box("pv_rubber", I.translated(Vector3(sx, 0.075, 0.0)), Vector3(0.02, 0.152, 0.094), Color(0.1, 0.1, 0.1))
				var zip := PackedVector3Array()
				var zr := PackedFloat32Array()
				for s in 21:
					var a := TAU * s / 20.0
					zip.append(Vector3(cos(a) * 0.119, 0.13, sin(a) * 0.044))
					zr.append(0.002)
				tube(k, "metal_dark", I, zip, zr, 4, Color(0.15, 0.15, 0.15), false)
			var handle := PackedVector3Array()
			var hr := PackedFloat32Array()
			for s in 9:
				var a := PI * s / 8.0
				handle.append(Vector3(cos(a) * 0.04, 0.15 + sin(a) * 0.02, 0))
				hr.append(0.006)
			tube(k, "pv_rubber", I, handle, hr, 8, Color(0.1, 0.1, 0.1))
			_cross(k, I, Vector3(0, 0.075, 0.046 if mil else 0.05), Vector3.BACK, 0.05, Color(0.95, 0.95, 0.93) if mil else Color(0.97, 0.97, 0.97))
			return Vector3(0, 0.17, 0)
		"stimpack":
			injector(k, I, 0.008, 0.1, Color(0.8, 0.1, 0.12, 0.85), Color(0.15, 0.3, 0.6))
			return Vector3(0, 0.0, 0)
		"nanite_injector":
			injector(k, I, 0.008, 0.11, Color(0.55, 0.58, 0.62, 0.9), Color(0.2, 0.2, 0.22))
			for y in [0.02, 0.05, 0.08]:
				lathe(k, "gold", I, PackedVector2Array([Vector2(0.0092, y - 0.002), Vector2(0.0095, y), Vector2(0.0092, y + 0.002)]), 16, Color(0.85, 0.65, 0.3))
			return Vector3(0, 0.0, 0)
		"syringe_glass":
			injector(k, I, 0.0065, 0.07, Color(0.85, 0.8, 0.6, 0.35), Color.WHITE, true)
			return Vector3(0, 0.0, 0)
		"painkillers":
			# A blister pack: a foil card, a row of clear domes with white pills.
			k.box("pv_foil", I.translated(Vector3(0, 0.001, 0)), Vector3(0.1, 0.002, 0.05), Color(0.78, 0.78, 0.8))
			for i in 10:
				var at := Vector3(-0.036 + (i % 5) * 0.018, 0.002, -0.011 + (i / 5) * 0.022)
				lathe(k, "pv_glass", I.translated(at), _sphere(0.0075, 6, 0.6).slice(6), 14, Color(0.9, 0.92, 0.94, 0.15))
				lathe(k, "pv_plastic", I.translated(at + Vector3(0, 0.002, 0)), _sphere(0.0055, 6, 0.45), 14, Color(0.95, 0.94, 0.92))
			return Vector3(0, 0.0, 0)
		"bandage_roll", "bandage_linen":
			# A rolled bandage, its loose end hanging.
			var cloth := Color(0.9, 0.86, 0.76) if t == "bandage_linen" else Color(0.86, 0.84, 0.78)
			var ring := _curve([Vector2(0.012, 0.0), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.036, 0.004), Vector2(0.036, 0.066), Vector2(0.034, 0.07), Vector2(0.034, 0.07), Vector2(0.012, 0.07), Vector2(0.012, 0.07), Vector2(0.012, 0.0)], 2)
			lathe(k, "pv_cloth", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.035, 0.036, 0)), ring, 32, func(p: Vector3, _a: float, _t: float) -> Color: return cloth.darkened(0.25 * pow(absf(sin(Vector2(p.x, p.z).length() * 700.0)), 6.0) + 0.05 * _nz(p, 40.0)))
			sheet(k, "pv_cloth", I, 4, 10, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * 0.068, 0.0012, 0.004 + v * 0.1) + Vector3(0, 0.006 * sin(v * 9.0), 0) * v, cloth, Vector3.UP)
			return Vector3(0, 0.036, 0)
		"splint":
			# Three wooden slats bound with strips of cloth.
			for i in 3:
				k.box("pv_wood", Transform3D(Basis(Vector3.UP, 0.04 * (i - 1)), Vector3(0, 0.007 + i * 0.011, 0.002 * i)), Vector3(0.2, 0.01, 0.025), Color(0.55, 0.4, 0.24).darkened(0.08 * i))
			for x in [-0.06, 0.06]:
				lathe(k, "pv_cloth", Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.0)), Vector3(x, 0.018, 0)), PackedVector2Array([Vector2(0.024, -0.012), Vector2(0.025, 0.0), Vector2(0.024, 0.012)]), 20, Color(0.88, 0.85, 0.78), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)) * 1.0, 4.0) + pow(absf(sin(a)) * 1.25, 4.0), 0.25))
			return Vector3(0, 0.02, 0)
		"salve", "smelling_salts":
			# A shallow round tin, lid off and propped beside it, the contents showing.
			var salve := t == "salve"
			var case := Color(0.48, 0.32, 0.18) if salve else Color(0.7, 0.7, 0.68)
			var pot := _curve([Vector2(0, 0.0), Vector2(0.034, 0.0), Vector2(0.034, 0.0), Vector2(0.036, 0.003), Vector2(0.036, 0.03), Vector2(0.036, 0.03), Vector2(0.032, 0.03), Vector2(0.032, 0.006), Vector2(0, 0.006)], 2)
			lathe(k, "pv_wood" if salve else "pv_tin", I, pot, 32, case)
			lathe(k, "pv_glossy" if salve else "pv_crumb", I, PackedVector2Array([Vector2(0.031, 0.024), Vector2(0, 0.026)]), 28, Color(0.42, 0.55, 0.22) if salve else Color(0.95, 0.95, 0.93))
			var lid := Transform3D(Basis(Vector3.RIGHT, -1.25), Vector3(0, 0.022, -0.05))
			lathe(k, "pv_wood" if salve else "pv_tin", lid, _curve([Vector2(0, 0.0), Vector2(0.038, 0.0), Vector2(0.038, 0.0), Vector2(0.038, 0.012), Vector2(0.038, 0.012), Vector2(0.035, 0.012), Vector2(0.035, 0.002), Vector2(0, 0.002)], 2), 32, case.darkened(0.1))
			if not salve:
				# A folded cloth to hold under the nose.
				k.box("pv_cloth", Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.05, 0.004, 0.03)), Vector3(0.05, 0.006, 0.035), Color(0.92, 0.9, 0.85))
			return Vector3(0, 0.015, 0)
		"herbal_poultice":
			# Herbs bundled in a square of coarse undyed linen, the corners gathered up into
			# a tuft and bound with twine, set on a bed of big dark green leaves that fan
			# out from under it either side.
			for i in 7:
				var a := -1.5 + 3.0 * i / 6.0
				leaf(k, Transform3D(Basis(Vector3.FORWARD, a * 1.2) * Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.03, 0.008)), 0.064 - 0.006 * absf(a), 0.032, Color(0.07, 0.2, 0.05).lightened(0.04 * (i % 2)), 0.2, 8, 6)
			sack(k, I, 0.034, 0.09, false, Color(0.66, 0.58, 0.42))
			# The gathered corners above the tie, crumpled into folds.
			for i in 5:
				var a := TAU * i / 5.0 + 0.3
				var tip := Vector3(cos(a) * 0.009, 0.104 + 0.004 * (i % 2), sin(a) * 0.009)
				tube(k, "pv_burlap", I, PackedVector3Array([Vector3(cos(a) * 0.004, 0.08, sin(a) * 0.004), Vector3(cos(a) * 0.008, 0.092, sin(a) * 0.008), tip]), PackedFloat32Array([0.006, 0.0055, 0.002]), 6, Color(0.62, 0.54, 0.38))
			return Vector3(0, 0.03, 0)
		# Sacks, sheaves and herbs ------------------------------------------------------
		"flour", "coal_sack":
			var flour := t == "flour"
			var prof := sack(k, I, 0.07 if flour else 0.1, 0.17 if flour else 0.24, true, Color(0.7, 0.6, 0.42) if flour else Color(0.5, 0.4, 0.28))
			var top_y := prof[prof.size() - 1].y - 0.01
			if flour:
				lathe(k, "pv_crumb", I, _curve([Vector2(0.066, top_y - 0.01), Vector2(0.04, top_y + 0.004), Vector2(0, top_y + 0.012)], 3), 28, Color(0.95, 0.93, 0.88), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.06 * _nz(p, 40.0))
			else:
				var rc := RandomNumberGenerator.new()
				rc.seed = 21
				lathe(k, "pv_coal", I, PackedVector2Array([Vector2(0.09, top_y - 0.02), Vector2(0, top_y)]), 20, Color(0.12, 0.12, 0.12))
				for i in 16:
					var a := rc.randf() * TAU
					var d := sqrt(rc.randf()) * 0.075
					k.crystal("pv_coal", Transform3D(Basis(Vector3(rc.randf(), rc.randf(), rc.randf()).normalized(), rc.randf() * PI), Vector3(cos(a) * d, top_y - 0.005, sin(a) * d)), rc.randf_range(0.012, 0.02), rc.randf_range(0.02, 0.035), 5, 0.3, Color(0.13, 0.13, 0.14))
			return Vector3(0, 0.08, 0)
		"coffee_beans":
			# A heap of roasted beans, each split down its flat side.
			var rb := RandomNumberGenerator.new()
			rb.seed = 13
			for i in 40:
				var a := rb.randf() * TAU
				var d := sqrt(rb.randf()) * 0.045
				var y := (0.045 - d) * 0.5 + rb.randf_range(0.0, 0.004)
				var b := Basis(Vector3(rb.randf_range(-1, 1), rb.randf_range(-1, 1), rb.randf_range(-1, 1)).normalized(), rb.randf() * PI)
				lathe(k, "pv_roast", Transform3D(b * Basis.from_scale(Vector3(1.0, 0.65, 1.4)), Vector3(cos(a) * d, y + 0.004, sin(a) * d)), _sphere(0.0055, 6), 10, Color(0.32, 0.18, 0.09).darkened(rb.randf_range(0.0, 0.25)), func(a2: float, _t: float, _p: Vector3) -> float: return 1.0 - 0.3 * pow(absf(cos(a2)), 40.0))
			return Vector3(0, 0.012, 0)
		"wheat":
			# A sheaf of wheat tied round the middle.
			var rw := RandomNumberGenerator.new()
			rw.seed = 17
			var gold := Color(0.85, 0.68, 0.32)
			for i in 30:
				var a := rw.randf() * TAU
				var d := sqrt(rw.randf()) * 0.018
				var base := Vector3(cos(a) * d * 1.6, 0.0, sin(a) * d * 1.6)
				var top := Vector3(cos(a) * d * 2.8, 0.3 + rw.randf_range(-0.02, 0.02), sin(a) * d * 2.8)
				var mid := Vector3(cos(a) * d * 0.6, 0.13, sin(a) * d * 0.6)
				tube(k, "pv_leaf", I, PackedVector3Array([base, mid, top]), PackedFloat32Array([0.0016, 0.0014, 0.0011]), 4, gold.darkened(rw.randf_range(0.0, 0.15)), false)
				var ear := (top - mid).normalized()
				lathe(k, "pv_crumb", Transform3D(_facing(ear), top), _curve([Vector2(0, 0.0), Vector2(0.0035, 0.008), Vector2(0.004, 0.03), Vector2(0, 0.045)], 3), 6, gold.darkened(rw.randf_range(0.0, 0.1)), func(a2: float, t2: float, _p: Vector3) -> float: return 1.0 + 0.25 * absf(sin(t2 * 40.0 + a2 * 2.0)))
			twine(k, I, 0.012, 0.125, 3)
			return Vector3(0, 0.12, 0)
		"herb_blue":
			# A cut stem of a blue-leaved herb: big, deeply toothed, pointed leaves fanned
			# out from it, dark blue-green with pale veins, greyer on the young ones.
			var stem := PackedVector3Array([Vector3(-0.04, -0.045, 0), Vector3(-0.02, -0.022, 0.002), Vector3(0.0, 0.0, 0.003), Vector3(0.02, 0.024, 0.002)])
			tube(k, "pv_leaf", I, stem, PackedFloat32Array([0.0022, 0.002, 0.0018, 0.0014]), 6, Color(0.24, 0.34, 0.26), false)
			var fan := [[1, 2.2, 0.058], [1, -0.4, 0.06], [2, 1.5, 0.066], [2, -0.9, 0.064], [2, 0.6, 0.072], [3, 1.1, 0.06], [3, -0.2, 0.062], [3, 0.45, 0.056], [1, 0.8, 0.05]]
			for i in fan.size():
				var e: Array = fan[i]
				var at: Vector3 = stem[e[0]]
				var c := Color(0.07, 0.19, 0.19).lerp(Color(0.22, 0.32, 0.36), 0.15 * (i % 3))
				leaf(k, Transform3D(Basis(Vector3.FORWARD, -float(e[1]) + 0.8) * Basis(Vector3.UP, 0.25 * sin(i * 2.0)), at + Vector3(0, 0, 0.001 * i)), float(e[2]) * 1.35, float(e[2]) * 0.55, c, 0.12, 10, 9)
			return Vector3(-0.03, -0.035, 0)
		"herb_yellow":
			# A flowering herb: one big golden flower like a marigold, a ring of long
			# toothed petals round a dark orange heart, buds on short stalks beside it, and
			# a clump of deep green leaves round the base of the stem.
			var stem := PackedVector3Array([Vector3(0, -0.06, 0), Vector3(0.002, -0.03, 0), Vector3(0.0, 0.0, 0.002), Vector3(0.0, 0.012, 0.004)])
			tube(k, "pv_leaf", I, stem, PackedFloat32Array([0.0025, 0.0022, 0.002, 0.002]), 6, Color(0.22, 0.36, 0.1), false)
			var head := Transform3D(_facing(Vector3(0.0, 0.35, 1.0)), Vector3(0.0, 0.014, 0.006))
			var gold := Color(0.72, 0.4, 0.0)
			for i in 14:
				var a := TAU * i / 14.0
				leaf(k, head * Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 0.001, 0)), 0.044, 0.014, gold.lerp(Color(0.78, 0.46, 0.0), 0.5 * (i % 2)), -0.1, 5, 0, "pv_petal")
			lathe(k, "pv_crumb", head, _curve([Vector2(0.009, 0.0), Vector2(0.008, 0.004), Vector2(0.004, 0.0065), Vector2(0, 0.007)], 2), 16, func(p: Vector3, _a: float, t2: float) -> Color: return Color(0.62, 0.3, 0.04).darkened(0.25 * _nz(p, 500.0) + 0.2 * t2))
			# Buds, and leaves round the foot.
			for e in [[Vector3(-0.034, 0.002, -0.004), 0.5], [Vector3(0.036, -0.004, -0.004), -0.6], [Vector3(0.026, 0.03, -0.006), -0.3]]:
				var at: Vector3 = e[0]
				tube(k, "pv_leaf", I, PackedVector3Array([Vector3(0.0, -0.03, 0), at * 0.5 + Vector3(0, -0.012, 0), at]), PackedFloat32Array([0.0014, 0.0013, 0.0012]), 5, Color(0.22, 0.36, 0.1), false)
				lathe(k, "pv_skin", Transform3D(Basis(Vector3.FORWARD, e[1]), at), _sphere(0.006, 6, 1.4), 10, func(_p: Vector3, _a: float, t2: float) -> Color: return Color(0.16, 0.26, 0.05) if t2 < 0.4 else Color(0.86, 0.45, 0.02))
			for i in 8:
				var a := -1.4 + 2.8 * i / 7.0
				leaf(k, Transform3D(Basis(Vector3.FORWARD, a) * Basis(Vector3.RIGHT, -0.35), Vector3(0, -0.05, 0.002 * i - 0.006)), 0.05 - 0.008 * absf(a), 0.022, Color(0.08, 0.2, 0.04).lightened(0.04 * (i % 2)), 0.25, 8, 6)
			return Vector3(0, -0.045, 0)
		"herb_mint":
			# A bunch of mint: broad, wrinkled, bright green leaves with toothed edges in
			# pairs up the stems, and spikes of tiny white flowers rising out of them.
			var rm := RandomNumberGenerator.new()
			rm.seed = 13
			for sidx in 3:
				var lean := (sidx - 1) * 0.45
				var b := Basis(Vector3.FORWARD, lean)
				var top := b * Vector3(0, 0.065, 0)
				tube(k, "pv_leaf", I, PackedVector3Array([Vector3(0, -0.04, 0), b * Vector3(0, 0.0, 0), top]), PackedFloat32Array([0.002, 0.0018, 0.0014]), 5, Color(0.2, 0.32, 0.1), false)
				for j in 4:
					var at := b * Vector3(0, -0.035 + j * 0.022, 0.002 * sidx)
					for sd in [-1.0, 1.0]:
						leaf(k, Transform3D(Basis(Vector3.FORWARD, lean - sd * (1.15 - 0.12 * j)) * Basis(Vector3.UP, sd * 0.25), at), 0.044 - 0.006 * j, 0.03 - 0.004 * j, Color(0.05, 0.18, 0.03).lightened(rm.randf_range(-0.02, 0.04)), 0.18, 8, 7)
				# The flower spike: tiers of tiny white florets.
				if sidx != 1:
					for f in 14:
						var y := 0.052 + f * 0.0018
						var a := f * 2.4
						lathe(k, "pv_soft", Transform3D(Basis.IDENTITY, b * Vector3(0, 0, 0) + top * (y / 0.065) + Vector3(cos(a) * 0.004, 0, sin(a) * 0.004 + 0.004)), _sphere(0.0024, 4), 6, Color(0.95, 0.94, 0.9).darkened(0.12 * (f % 3)))
			lathe(k, "pv_soft", Transform3D(Basis.IDENTITY, Vector3(0.006, 0.05, 0.012)), _sphere(0.003, 4), 6, Color(0.95, 0.94, 0.9))
			return Vector3(0, -0.03, 0)
		"herb_red", "herb_nightshade":
			var leafc: Color = {"herb_red": Color(0.48, 0.12, 0.1), "herb_nightshade": Color(0.18, 0.3, 0.12)}[t]
			var flower: Color = {"herb_red": Color(0.75, 0.08, 0.1), "herb_nightshade": Color(0.42, 0.2, 0.62)}.get(t, Color(0, 0, 0, 0))
			for i in 3:
				sprig(k, Transform3D(Basis(Vector3.FORWARD, (i - 1) * 0.3) * Basis(Vector3.UP, i * 2.0), Vector3(0, 0, 0)), 0.11 - 0.015 * i, leafc, 0.035, 4, flower if i == 0 else Color(0, 0, 0, 0), Color(0.05, 0.04, 0.06) if t == "herb_nightshade" and i == 1 else Color(0, 0, 0, 0))
			return Vector3(0, 0.02, 0)
		"herb_root":
			# A gnarled root with a tuft of leaves.
			var rr := RandomNumberGenerator.new()
			rr.seed = 19
			tube(k, "pv_veg", I, PackedVector3Array([Vector3(0, 0.0, 0), Vector3(0.01, 0.03, 0.004), Vector3(-0.004, 0.06, 0.0), Vector3(0.006, 0.09, -0.004), Vector3(0.0, 0.1, 0)]), PackedFloat32Array([0.006, 0.012, 0.013, 0.01, 0.006]), 10, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.5, 0.35, 0.2).darkened(0.25 * _nz(p, 120.0)))
			for i in 6:
				var a := rr.randf() * TAU
				var y := rr.randf_range(0.0, 0.07)
				tube(k, "pv_veg", I, PackedVector3Array([Vector3(0, y, 0), Vector3(cos(a) * 0.02, y - 0.015, sin(a) * 0.02), Vector3(cos(a) * 0.035, y - 0.04, sin(a) * 0.035)]), PackedFloat32Array([0.004, 0.0025, 0.001]), 6, Color(0.48, 0.34, 0.2))
			for i in 4:
				leaf(k, Transform3D(Basis(Vector3.UP, i * 1.6) * Basis(Vector3.FORWARD, 0.5), Vector3(0, 0.1, 0)), 0.04, 0.02, Color(0.26, 0.42, 0.14), 0.3)
			return Vector3(0, 0.05, 0)
		# Barrels and fuel cans ---------------------------------------------------------
		"oil_barrel", "powder_keg":
			barrel(k, I, 0.2 if t == "oil_barrel" else 0.14, 0.55 if t == "oil_barrel" else 0.32, 20 if t == "oil_barrel" else 16)
			if t == "powder_keg":
				# A fuse plugged into the bung.
				tube(k, "pv_twine", I, PackedVector3Array([Vector3(0.05, 0.31, 0), Vector3(0.055, 0.34, 0.01), Vector3(0.07, 0.36, 0.02)]), PackedFloat32Array([0.003, 0.0025, 0.002]), 5, Color(0.25, 0.22, 0.18), true)
			else:
				k.cylinder("pv_wood", I.translated(Vector3(0.0, 0.25, 0.198)).rotated_local(Vector3.RIGHT, PI * 0.5), 0.016, 0.014, 0.01, 10, true, 0.0, 1, Color(0.3, 0.2, 0.12))
			return Vector3(0, 0.3 if t == "oil_barrel" else 0.18, 0)
		"kerosene_can", "diesel_jerrycan":
			var jerry := t == "diesel_jerrycan"
			var paint := Color(0.62, 0.1, 0.08) if not jerry else Color(0.28, 0.33, 0.2)
			var scuffed := func(p: Vector3, _a: float, _t: float) -> Color: return paint.lerp(Color(0.45, 0.42, 0.38), clampf(_nz(p, 30.0) * 1.6 - 0.6, 0.0, 0.8))
			var size := Vector3(0.17, 0.26, 0.1) if jerry else Vector3(0.14, 0.2, 0.09)
			rounded_box(k, "pv_paint", I, size, 0.014, scuffed, 14.0)
			if jerry:
				# The pressed X on each face and three handles on top.
				for sz in [-1.0, 1.0]:
					for d in [0.7, -0.7]:
						k.box("pv_paint", Transform3D(Basis(Vector3.BACK, d), Vector3(0, 0.12, sz * 0.05)), Vector3(0.012, 0.22, 0.004), paint.darkened(0.15))
				for x in [-0.045, 0.0, 0.045]:
					k.box("pv_paint", I.translated(Vector3(x, 0.275, 0)), Vector3(0.012, 0.03, 0.03), paint)
				k.box("pv_paint", I.translated(Vector3(0, 0.29, 0)), Vector3(0.11, 0.01, 0.03), paint)
				lathe(k, "metal_dark", Transform3D(Basis(Vector3.BACK, 0.6), Vector3(0.07, 0.26, 0)), PackedVector2Array([Vector2(0.016, 0.0), Vector2(0.016, 0.02), Vector2(0.016, 0.02), Vector2(0, 0.022)]), 14, Color(0.2, 0.2, 0.2))
			else:
				# A spout with its cap, and a carrying handle.
				tube(k, "pv_paint", I, PackedVector3Array([Vector3(0.045, 0.19, 0), Vector3(0.05, 0.22, 0), Vector3(0.06, 0.24, 0)]), PackedFloat32Array([0.011, 0.009, 0.009]), 10, paint)
				lathe(k, "pv_paint", Transform3D(Basis(Vector3.BACK, -0.45), Vector3(0.06, 0.238, 0)), PackedVector2Array([Vector2(0.011, 0.0), Vector2(0.011, 0.014), Vector2(0.011, 0.014), Vector2(0, 0.015)]), 12, Color(0.8, 0.65, 0.2))
				var handle := PackedVector3Array()
				var hr := PackedFloat32Array()
				for s in 9:
					var a := PI * s / 8.0
					handle.append(Vector3(-0.02 + cos(a) * 0.035, 0.195 + sin(a) * 0.03, 0))
					hr.append(0.005)
				tube(k, "pv_paint", I, handle, hr, 8, paint.darkened(0.2))
			return Vector3(0, size.y + 0.02, 0)
		# Alien fare -------------------------------------------------------------------
		"fruit_alien":
			# A star fruit the size of a fist: five ridges, waxy magenta skin, gold at the tips.
			var star := func(a: float, _t: float, _p: Vector3) -> float: return 0.55 + 0.45 * pow(absf(cos(a * 2.5)), 3.0)
			lathe(k, "pv_skin", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.05, 0.035, 0)), _curve([Vector2(0, 0.0), Vector2(0.03, 0.015), Vector2(0.04, 0.05), Vector2(0.03, 0.085), Vector2(0, 0.1)], 4), 60, func(_p: Vector3, a: float, _t: float) -> Color: return Color(0.75, 0.1, 0.35).lerp(Color(0.95, 0.75, 0.25), pow(absf(cos(a * 2.5)), 8.0)), star)
			return Vector3(0, 0.035, 0)
		"egg_alien_food":
			var re := RandomNumberGenerator.new()
			re.seed = 23
			for i in 9:
				var at := Vector3(re.randf_range(-0.03, 0.03), 0.014 + re.randf_range(0.0, 0.02), re.randf_range(-0.03, 0.03))
				lathe(k, "pv_glossy", I.translated(at), _sphere(0.014, 8), 14, Color(0.95, 0.5, 0.08))
			sheet(k, "pv_leaf", I, 10, 10, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * 0.09, 0.014 - 0.012 * sin(u * PI) * sin(v * PI) + 0.003 * _nz(Vector3(u, v, 0), 6.0), (v - 0.5) * 0.09), func(p: Vector3, _u: float, _v: float) -> Color: return Color(0.85, 0.72, 0.5, 1.0).darkened(0.2 * absf(_nz(p, 300.0))), Vector3.UP)
			return Vector3(0, 0.02, 0)
		"nectar_alien", "drink_nebula", "elixir_void", "elixir_star", "invis_cloak_vial":
			# Teardrop flasks in silver filigree.
			var liquid: Color = {"nectar_alien": Color(0.45, 0.12, 0.7, 0.85), "drink_nebula": Color(0.55, 0.2, 0.75, 0.75), "elixir_void": Color(0.1, 0.05, 0.25, 0.92), "elixir_star": Color(0.85, 0.85, 0.95, 0.35), "invis_cloak_vial": Color(0.5, 0.52, 0.55, 0.3)}[t]
			var outer := [Vector2(0, 0.0), Vector2(0.02, 0.002), Vector2(0.036, 0.02), Vector2(0.038, 0.04), Vector2(0.026, 0.07), Vector2(0.012, 0.09), Vector2(0.008, 0.1), Vector2(0.008, 0.11), Vector2(0.008, 0.11), Vector2(0.0095, 0.112), Vector2(0.0095, 0.116), Vector2(0.0095, 0.116), Vector2(0.008, 0.117)]
			vessel(k, I, outer, 0.0024, CLEAR, liquid, 0.06, 28)
			lathe(k, "metal", I, _curve([Vector2(0, 0.112), Vector2(0.011, 0.113), Vector2(0.011, 0.113), Vector2(0.01, 0.125), Vector2(0.004, 0.14), Vector2(0, 0.145)], 2), 12, Color(0.75, 0.75, 0.8))
			for i in 3:
				var pts := PackedVector3Array()
				var rr := PackedFloat32Array()
				for s in 13:
					var f := s / 12.0
					var y := 0.005 + f * 0.09
					var r := _radius_at(_curve(outer, 3), y) + 0.0012
					var a := TAU * i / 3.0 + f * 2.0
					pts.append(Vector3(cos(a) * r, y, sin(a) * r))
					rr.append(0.0014)
				tube(k, "metal", I, pts, rr, 5, Color(0.75, 0.75, 0.8), false)
			return Vector3(0, 0.035, 0)
		"serum_hive", "nanite_swarm", "regen_pod", "mutagen":
			# A capsule cradled in a cage of ribs.
			var fill: Color = {"serum_hive": Color(0.9, 0.6, 0.1, 0.8), "nanite_swarm": Color(0.7, 0.72, 0.78, 0.55), "regen_pod": Color(0.85, 0.4, 0.45, 0.85), "mutagen": Color(0.4, 0.7, 0.75, 0.75)}[t]
			var cage: String = "metal" if t == "nanite_swarm" else ("gold" if t == "regen_pod" else "pv_roast")
			var cage_col := Color(0.7, 0.72, 0.75) if t == "nanite_swarm" else (Color(0.85, 0.65, 0.3) if t == "regen_pod" else Color(0.3, 0.22, 0.12))
			var is_round := t == "mutagen"
			var outer := [Vector2(0, 0.0), Vector2(0.018, 0.004), Vector2(0.024, 0.02), Vector2(0.024, 0.07), Vector2(0.018, 0.086), Vector2(0, 0.09)] if not is_round else [Vector2(0, 0.0), Vector2(0.026, 0.01), Vector2(0.034, 0.035), Vector2(0.026, 0.06), Vector2(0, 0.07)]
			var prof := _curve(outer, 3)
			lathe(k, "pv_glass", I, prof, 24, Color(0.9, 0.92, 0.94, 0.03))
			var inner := PackedVector2Array()
			for p in prof:
				inner.append(Vector2(p.x * 0.9, lerpf(prof[0].y, prof[prof.size() - 1].y, 0.5) + (p.y - lerpf(prof[0].y, prof[prof.size() - 1].y, 0.5)) * 0.92))
			lathe(k, "pv_liquid", I, inner, 24, fill)
			for i in 6:
				var a := TAU * i / 6.0
				var pts := PackedVector3Array()
				var rr := PackedFloat32Array()
				for s in 9:
					var y := lerpf(prof[0].y - 0.006, prof[prof.size() - 1].y + 0.006, s / 8.0)
					var r := _radius_at(prof, clampf(y, prof[0].y + 0.001, prof[prof.size() - 1].y - 0.001)) + 0.003
					pts.append(Vector3(cos(a + s * 0.12) * r, y, sin(a + s * 0.12) * r))
					rr.append(0.0022)
				tube(k, cage, I, pts, rr, 5, cage_col)
			if t == "mutagen":
				# Feelers curling off it.
				for i in 4:
					var a := TAU * i / 4.0
					var pts := PackedVector3Array()
					var rr := PackedFloat32Array()
					for s in 10:
						var f := s / 9.0
						pts.append(Vector3(cos(a) * (0.03 + f * 0.03), 0.06 + f * 0.04 - f * f * 0.05, sin(a) * (0.03 + f * 0.03)) + Vector3(cos(a + 1.6), 0, sin(a + 1.6)) * 0.015 * sin(f * 6.0))
						rr.append(0.003 * (1.0 - f) + 0.0006)
					tube(k, "pv_meat", I, pts, rr, 6, Color(0.35, 0.55, 0.6))
			return Vector3(0, 0.04, 0)
		"food_star":
			# A violet cake under a crust of gold stars.
			lathe(k, "pv_crumb", I, _curve([Vector2(0, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.0), Vector2(0.072, 0.03), Vector2(0.068, 0.045), Vector2(0, 0.048)], 3), 40, func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.3, 0.16, 0.45).lerp(Color(0.85, 0.75, 0.95), 0.8 if _nz(p, 500.0) > 0.55 else 0.0))
			for i in 8:
				var a := TAU * i / 8.0
				k.crystal("gold", Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.045, 0.046, sin(a) * 0.045)), 0.008, 0.012, 4, 0.8, Color(0.9, 0.72, 0.3))
			k.crystal("gold", I.translated(Vector3(0, 0.047, 0)), 0.012, 0.025, 4, 0.8, Color(0.9, 0.72, 0.3))
			return Vector3(0, 0.024, 0)
		"food_crystal":
			var rc := RandomNumberGenerator.new()
			rc.seed = 29
			var cs := [Color(0.95, 0.4, 0.55, 0.6), Color(0.4, 0.8, 0.95, 0.6), Color(0.6, 0.95, 0.6, 0.6), Color(0.9, 0.5, 0.95, 0.6)]
			for i in 5:
				var c: Color = cs[i % cs.size()]
				k.crystal("pv_glass", Transform3D(Basis(Vector3(rc.randf(), rc.randf(), rc.randf()).normalized(), rc.randf() * 0.8), Vector3(rc.randf_range(-0.03, 0.03), 0.0, rc.randf_range(-0.03, 0.03))), rc.randf_range(0.015, 0.022), rc.randf_range(0.03, 0.045), 6, 0.4, c)
			return Vector3(0, 0.015, 0)
		"food_hive":
			# A footed gold bowl brimming with honey.
			lathe(k, "gold", I, _curve([Vector2(0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.0), Vector2(0.018, 0.012), Vector2(0.012, 0.02), Vector2(0.03, 0.03), Vector2(0.055, 0.055), Vector2(0.06, 0.07), Vector2(0.06, 0.07), Vector2(0.056, 0.07), Vector2(0.05, 0.056), Vector2(0.02, 0.034), Vector2(0, 0.032)], 3), 36, Color(0.85, 0.65, 0.3))
			lathe(k, "pv_glossy", I, _curve([Vector2(0.056, 0.066), Vector2(0.03, 0.072), Vector2(0, 0.074)], 3), 32, Color(0.95, 0.6, 0.08), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.04 * _nz(p, 60.0))
			return Vector3(0, 0.015, 0)
		"food_bio":
			# A parcel of food wrapped in broad leaves and bound with a vine.
			rounded_box(k, "pv_leaf", I, Vector3(0.1, 0.05, 0.07), 0.02, func(p: Vector3, a: float, _t: float) -> Color: return Color(0.25, 0.42, 0.15).lerp(Color(0.5, 0.6, 0.25), pow(absf(sin(a * 7.0 + p.y * 30.0)), 20.0)), 3.0, func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.06 * _nz(p, 10.0))
			lathe(k, "pv_wood", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.025, 0)), PackedVector2Array([Vector2(0.03, -0.003), Vector2(0.032, 0.0), Vector2(0.03, 0.003)]), 20, Color(0.4, 0.35, 0.15), func(a: float, _t: float, _p: Vector3) -> float: return 1.0 / pow(pow(absf(cos(a)) * 1.15, 4.0) + pow(absf(sin(a)) * 0.82, 4.0), 0.25))
			return Vector3(0, 0.025, 0)
		"food_void":
			# A dark loaf flecked with violet, a slice cut from it.
			var col := func(p: Vector3, _a: float, _t: float) -> Color: return Color(0.12, 0.08, 0.16).lerp(Color(0.6, 0.35, 0.85), 0.9 if _nz(p, 300.0) > 0.6 else 0.0)
			var prof := PackedVector2Array()
			for v in _sphere(1.0, 20):
				prof.append(Vector2(pow(v.x, 0.6), v.y))
			lathe(k, "pv_crust", Transform3D(Basis.from_scale(Vector3(0.1, 0.05, 0.055)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.04, 0)), prof, 40, col, func(a: float, _t: float, _p: Vector3) -> float: return 1.0 - 0.3 * smoothstep(0.25, 0.95, cos(a)))
			return Vector3(0, 0.04, 0)
		"fungus_alien":
			# A pale, translucent bell-capped mushroom.
			lathe(k, "pv_glass", I, _curve([Vector2(0, 0.0), Vector2(0.012, 0.0), Vector2(0.009, 0.04), Vector2(0.008, 0.07), Vector2(0, 0.072)], 3), 16, Color(0.75, 0.92, 0.95, 0.75))
			lathe(k, "pv_glass", I, _curve([Vector2(0, 0.06), Vector2(0.045, 0.058), Vector2(0.05, 0.062), Vector2(0.042, 0.085), Vector2(0.022, 0.1), Vector2(0, 0.104)], 4), 32, Color(0.55, 0.88, 0.95, 0.6))
			return Vector3(0, 0.03, 0)
	return null

# --- World props ------------------------------------------------------------------------
# Kit props that are containers or drink (shop wares, cellar barrels, chests) are built
# here instead, so the bottle on a tavern shelf is the same glass as the one in the hand.

static var _kits: Dictionary = {}

## Stand-ins for kit model `name` (as BuildCatalog.model_parts knows it): [mesh, transform]
## pairs at the kit model's own size, or empty if it keeps its kit model.
static func kit(name: String) -> Array:
	if _kits.has(name):
		return _kits[name]
	var I := Transform3D.IDENTITY
	var out: Array = []
	match name:
		"props/Bottle_1":
			out = [[model("wine"), Transform3D(Basis.from_scale(Vector3.ONE * 1.55), Vector3.ZERO)]]
		"props/Potion_1":
			out = [[model("health_potion"), Transform3D(Basis.from_scale(Vector3.ONE * 1.2), Vector3.ZERO)]]
		"props/Potion_2":
			out = [[model("potion_health_greater"), Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3.ZERO)]]
		# Food left out on the tables of the houses you walk into (KitHouse): a loaf, a
		# cheese with a wedge gone, a few apples. No kit model; these are the whole thing.
		"props/Food_Bread":
			out = [[model("bread"), Transform3D(Basis(Vector3.UP, 0.4), Vector3.ZERO)]]
		"props/Food_Cheese":
			out = [[model("cheese_wheel_small"), I]]
		"props/Food_Apples":
			out = _apples(name)
		"props/Mug", "props/Barrel", "props/Chest_Wood", "props/Crate_Wooden", "props/Bag", "props/Barrel_Apples", "props/FarmCrate_Apple", "props/FarmCrate_Empty":
			out = [[_prop(name), I]]
			if name == "props/Barrel_Apples" or name == "props/FarmCrate_Apple":
				out.append_array(_apples(name))
	_kits[name] = out
	return out

## An apple, `segs` round and `steps` per span of its profile. The ones heaped in a crate
## or barrel are built coarser and without their leaf: their facets stay under a pixel
## from the nearest a customer leans over a stall, and a stall holds about ninety of them.
static func _apple(k: MeshKit, segs: int, steps: int, with_leaf: bool) -> Vector3:
	var I := Transform3D.IDENTITY
	var red := Color(0.62, 0.05, 0.06)
	var gold := Color(0.86, 0.66, 0.2)
	var col := func(p: Vector3, a: float, t2: float) -> Color:
		# Red streaked over yellow, yellower round the base, a darker flush on top.
		var streak := _nz(Vector3(cos(a) * 3.0, t2 * 0.6, sin(a) * 3.0), 2.5) * 0.5 + 0.5
		var c := gold.lerp(red, clampf(streak * 1.3 + t2 * 0.4 - 0.2, 0.0, 1.0))
		return c.darkened(0.15 * smoothstep(0.7, 1.0, t2)).lerp(Color(0.95, 0.85, 0.55), 0.6 if _nz(p, 900.0) > 0.55 else 0.0)
	var lumpy := func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + 0.03 * sin(a * 5.0 + 0.7) + 0.025 * _nz(p, 40.0)
	lathe(k, "pv_skin", I, _curve([Vector2(0, 0.009), Vector2(0.008, 0.004), Vector2(0.02, 0.001), Vector2(0.034, 0.008), Vector2(0.0405, 0.026), Vector2(0.041, 0.043), Vector2(0.036, 0.062), Vector2(0.022, 0.072), Vector2(0.01, 0.07), Vector2(0, 0.063)], steps), segs, col, lumpy)
	tube(k, "pv_wood", I, PackedVector3Array([Vector3(0, 0.062, 0), Vector3(0.001, 0.074, 0), Vector3(0.004, 0.085, 0.001)]), PackedFloat32Array([0.0022, 0.0018, 0.0016]), 6, Color(0.32, 0.22, 0.12))
	if with_leaf:
		leaf(k, Transform3D(Basis(Vector3.FORWARD, -1.0) * Basis(Vector3.UP, 0.4), Vector3(0.003, 0.078, 0)), 0.05, 0.024, Color(0.2, 0.42, 0.1), 0.25)
	return Vector3(0, 0.035, 0)

## Apples heaped in an open barrel or laid in a farm crate, as [mesh, transform] pairs.
static func _apples(name: String) -> Array:
	var bare: ArrayMesh = _models.get("kit:apple")
	if bare == null:
		# The apple without its leaf: thirty leaves in a crate look like a salad.
		var k := MeshKit.new(WHash.str_hash("apple") & 0xFFFF)
		_apple(k, 24, 2, false)
		bare = k.commit(_mat)
		_models["kit:apple"] = bare
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(name)
	var out: Array = []
	var spots: Array = []
	if name == "props/Barrel_Apples":
		# Two loose rings and a crown, heaped above the barrel's false floor.
		for e in [[0.0, 1, 0.84], [0.09, 6, 0.81], [0.2, 12, 0.775], [0.05, 4, 0.875], [0.14, 8, 0.83]]:
			for i in e[1]:
				var a: float = TAU * (float(i) + r.randf() * 0.4) / float(e[1]) + float(e[0]) * 7.0
				spots.append(Vector3(cos(a) * float(e[0]), float(e[2]), sin(a) * float(e[0])))
	elif name == "props/Food_Apples":
		# Three on the table and one on top of them.
		spots = [Vector3(-0.042, 0.0, 0.0), Vector3(0.04, 0.0, 0.022), Vector3(-0.004, 0.0, 0.07), Vector3(0.0, 0.05, 0.03)]
	else:
		for ix in 8:
			for iz in 4:
				spots.append(Vector3(-0.29 + ix * 0.083 + r.randf_range(-0.008, 0.008), 0.15 + r.randf_range(0.0, 0.012), -0.12 + iz * 0.08 + r.randf_range(-0.008, 0.008)))
	for at in spots:
		var b := Basis(Vector3(r.randf() - 0.5, r.randf() * 0.3, r.randf() - 0.5).normalized(), r.randf_range(0.3, 1.6)) * Basis.from_scale(Vector3.ONE * r.randf_range(0.92, 1.08))
		out.append([bare, Transform3D(b, at)])
	return out

static func _prop(name: String) -> ArrayMesh:
	var key := "kit:" + name
	if _models.has(key):
		return _models[key]
	var k := MeshKit.new(WHash.str_hash(name) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(name)
	var I := Transform3D.IDENTITY
	match name:
		"props/Mug":
			# A staved wooden tankard bound in iron, a handle, a head of foam on the ale.
			barrel(k, I, 0.062, 0.165, 12, Color(0.5, 0.33, 0.18), 0.012)
			lathe(k, "pv_glossy", I, PackedVector2Array([Vector2(0.052, 0.138), Vector2(0, 0.138)]), 20, Color(0.45, 0.24, 0.05))
			lathe(k, "pv_soft", I, _curve([Vector2(0.0525, 0.139), Vector2(0.05, 0.146), Vector2(0.03, 0.152), Vector2(0, 0.154)], 3), 24, Color(0.95, 0.92, 0.82), func(_a: float, _t: float, p: Vector3) -> float: return 1.0 + 0.06 * _nz(p, 120.0))
			var h := PackedVector3Array()
			var hr := PackedFloat32Array()
			for i in 9:
				var a := lerpf(-1.4, 1.4, i / 8.0)
				h.append(Vector3(0.06 + 0.045 * cos(a), 0.085 + 0.05 * sin(a), 0))
				hr.append(0.009)
			tube(k, "pv_wood", Transform3D(Basis.from_scale(Vector3(1, 1, 0.6)), Vector3.ZERO), h, hr, 8, Color(0.46, 0.3, 0.16))
		"props/Barrel":
			barrel(k, I, 0.33, 0.88, 22)
		"props/Barrel_Apples":
			barrel(k, I, 0.33, 0.88, 22, Color(0.48, 0.3, 0.16), 0.76)
		"props/Bag":
			sack(k, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.82)), Vector3.ZERO), 0.29, 0.78, false)
		"props/Chest_Wood":
			chest(k, I, Vector3(1.2, 0.7, 0.72), r)
		"props/Crate_Wooden":
			crate(k, I, Vector3(0.82, 0.86, 0.86), r)
		"props/FarmCrate_Apple", "props/FarmCrate_Empty":
			farm_crate(k, I, Vector3(0.7, 0.24, 0.4), r)
	var out := k.commit(_mat)
	_models[key] = out
	return out

## A run of boards along local X, stacked up Y from y = 0 with hairline gaps, each its
## own shade, sat a hair off true.
static func _boards(k: MeshKit, xf: Transform3D, w: float, h: float, thick: float, n: int, col: Color, r: RandomNumberGenerator, gap := 0.005) -> void:
	var bh := h / n
	for i in n:
		var c := col.darkened(r.randf_range(0.0, 0.2)).lightened(r.randf_range(0.0, 0.06))
		k.box("pv_board", xf * Transform3D(Basis(Vector3.FORWARD, r.randf_range(-0.004, 0.004)), Vector3(r.randf_range(-0.003, 0.003), bh * (i + 0.5), r.randf_range(-0.0015, 0.0015))), Vector3(w, bh - gap, thick), c)

## A round nail head (or rivet) on a face whose normal is `n`.
static func _nail(k: MeshKit, xf: Transform3D, at: Vector3, n: Vector3, rad := 0.007, col := Color(0.2, 0.19, 0.18)) -> void:
	lathe(k, "iron", xf * Transform3D(_facing(n), at), _curve([Vector2(rad, 0.0), Vector2(rad * 0.8, rad * 0.35), Vector2(0, rad * 0.45)], 2), 8, col)

## A shipping crate: planked walls and lid, framed with battens round every face, a
## diagonal brace across each side, nailed at the joints.
static func crate(k: MeshKit, xf: Transform3D, size: Vector3, r: RandomNumberGenerator, col := Color(0.62, 0.48, 0.32)) -> void:
	var t := 0.02
	var bat := Vector2(0.07, 0.022)
	var n := 5
	for sd in [1.0, -1.0]:
		# Front and back, boards running across; the sides fit between them.
		_boards(k, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, sd * (size.z * 0.5 - t * 0.5))), size.x, size.y, t, n, col, r)
		_boards(k, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sd * (size.x * 0.5 - t * 0.5), 0, 0)), size.z - 2.0 * t, size.y, t, n, col, r)
	# The lid: boards running along X laid side by side.
	_boards(k, xf * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, size.y - t * 0.5, size.z * 0.5)), size.x, size.z, t, n, col, r)
	var frame := col.darkened(0.12)
	# Battens round each of the four walls, and a brace corner to corner.
	for face in 4:
		var yaw := face * PI * 0.5
		var w := size.x if face % 2 == 0 else size.z
		var d := (size.z if face % 2 == 0 else size.x) * 0.5 + bat.y * 0.5
		var fb := xf * Transform3D(Basis(Vector3.UP, yaw), Vector3(0, 0, d).rotated(Vector3.UP, yaw))
		for sx in [-1.0, 1.0]:
			k.box("pv_wood", fb * Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - bat.x * 0.5), size.y * 0.5, 0)), Vector3(bat.x, size.y, bat.y), frame.darkened(r.randf_range(0.0, 0.1)))
		for sy in [0.0, 1.0]:
			k.box("pv_wood", fb * Transform3D(Basis.IDENTITY, Vector3(0, bat.x * 0.5 + sy * (size.y - bat.x), 0)), Vector3(w - 2.0 * bat.x, bat.x, bat.y), frame.darkened(r.randf_range(0.0, 0.1)))
		var span := Vector2(w - 2.0 * bat.x, size.y - 2.0 * bat.x)
		var ang := atan2(span.y, span.x) * (1.0 if face % 2 == 0 else -1.0)
		k.box("pv_wood", fb * Transform3D(Basis(Vector3.BACK, ang), Vector3(0, size.y * 0.5, -0.002)), Vector3(span.length() - bat.x * 0.6, bat.x * 0.9, bat.y * 0.9), frame.darkened(r.randf_range(0.0, 0.12)))
		for sx in [-1.0, 1.0]:
			for sy in [0.0, 1.0]:
				var at := Vector3(sx * (w * 0.5 - bat.x * 0.5), bat.x * 0.5 + sy * (size.y - bat.x), bat.y * 0.5)
				_nail(k, fb, at + Vector3(-0.015, 0, 0), Vector3.BACK, 0.005)
				_nail(k, fb, at + Vector3(0.015, 0, 0), Vector3.BACK, 0.005)

## A travelling chest: a planked box with a barrel-vaulted lid, iron straps over the top
## and down the front, iron corners, a hasp and padlock, and drop handles at the ends.
static func chest(k: MeshKit, xf: Transform3D, size: Vector3, r: RandomNumberGenerator, col := Color(0.5, 0.32, 0.18)) -> void:
	var t := 0.024
	var hb := size.y * 0.62
	var hl := size.y - hb
	var d := size.z
	var iron := Color(0.2, 0.19, 0.18)
	var rusty := func(p: Vector3, _a: float, _t: float) -> Color: return iron.lerp(Color(0.38, 0.2, 0.1), clampf(_nz(p, 18.0) * 1.2, 0.0, 0.8))
	var feet := 0.03
	for sd in [1.0, -1.0]:
		_boards(k, xf * Transform3D(Basis.IDENTITY, Vector3(0, feet, sd * (d * 0.5 - t * 0.5))), size.x, hb - feet, t, 3, col, r)
		_boards(k, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sd * (size.x * 0.5 - t * 0.5), feet, 0)), d - 2.0 * t, hb - feet, t, 3, col, r)
	k.box("pv_board", xf * Transform3D(Basis.IDENTITY, Vector3(0, feet + 0.01, 0)), Vector3(size.x - 0.01, 0.02, d - 0.01), col.darkened(0.2))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box("pv_wood", xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 - 0.05), feet * 0.5, sz * (d * 0.5 - 0.05))), Vector3(0.09, feet, 0.09), col.darkened(0.3))
	# The vaulted lid: planks running along X round a half-ellipse, closed at the ends.
	var planks := 7
	var lid_col := func(p: Vector3, _u: float, v: float) -> Color:
		var i := floorf(v * planks)
		var edge := absf(fposmod(v * planks, 1.0) - 0.5) * 2.0
		return col.darkened(0.16 * fposmod(i * 0.618, 1.0) + 0.35 * smoothstep(0.88, 1.0, edge) + 0.06 * _nz(p, 25.0))
	var arc := func(v: float, grow: float) -> Vector3:
		var ph := v * PI
		return Vector3(0, hb + sin(ph) * (hl + grow), -cos(ph) * (d * 0.5 + grow))
	var vault := func(u: float, v: float) -> Vector3: return arc.call(v, 0.0) + Vector3((u - 0.5) * size.x, 0, 0)
	sheet(k, "pv_board", xf, 4, 28, vault, lid_col, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		var cap := func(u: float, v: float) -> Vector3:
			var e: Vector3 = arc.call(v, 0.0)
			return Vector3(sx * size.x * 0.5, hb + (e.y - hb) * u, e.z * u)
		sheet(k, "pv_board", xf, 3, 20, cap, lid_col, Vector3(sx, 0, 0))
	# Iron straps: over the lid and down front and back, a little proud.
	for sx in [-0.3, 0.3]:
		var x: float = sx * size.x
		var strap := func(u: float, v: float) -> Vector3: return arc.call(v, 0.006) + Vector3(x + (u - 0.5) * 0.06, 0, 0)
		sheet(k, "iron", xf, 1, 24, strap, rusty, Vector3.ZERO)
		for sd in [1.0, -1.0]:
			k.box("iron", xf * Transform3D(Basis.IDENTITY, Vector3(x, feet + (hb - feet) * 0.5, sd * (d * 0.5 + 0.003))), Vector3(0.06, hb - feet, 0.005), iron)
			for y in [0.12, 0.3, 0.5]:
				_nail(k, xf, Vector3(x, feet + y * hb, sd * (d * 0.5 + 0.006)), Vector3(0, 0, sd), 0.008)
	# Iron corner plates on the box.
	for sx in [-1.0, 1.0]:
		for sd in [1.0, -1.0]:
			for y in [feet + 0.05, hb - 0.05]:
				k.box("iron", xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 - 0.045), y, sd * (d * 0.5 + 0.003))), Vector3(0.1, 0.1, 0.005), iron)
				k.box("iron", xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 + 0.003), y, sd * (d * 0.5 - 0.045))), Vector3(0.005, 0.1, 0.1), iron)
	# The hasp hanging from the lid over a staple, and a padlock through it.
	var front := d * 0.5 + 0.006
	k.box("iron", xf * Transform3D(Basis.IDENTITY, Vector3(0, hb - 0.01, front)), Vector3(0.06, 0.12, 0.006), iron)
	lathe(k, "iron", xf * Transform3D(Basis.IDENTITY, Vector3(0, hb - 0.13, front + 0.02)), _curve([Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.036, 0.02), Vector2(0.034, 0.05), Vector2(0.028, 0.06), Vector2(0, 0.06)], 2), 16, rusty, func(a: float, _t: float, _p: Vector3) -> float: return 1.0 - 0.45 * pow(absf(sin(a)), 2.0))
	var shackle := PackedVector3Array()
	var sr := PackedFloat32Array()
	for i in 11:
		var a := PI * i / 10.0
		shackle.append(Vector3(cos(a) * 0.018, hb - 0.075 + sin(a) * 0.026, front + 0.02))
		sr.append(0.0045)
	tube(k, "iron", xf, shackle, sr, 6, Color(0.4, 0.38, 0.36))
	# Drop handles at the ends.
	for sx in [-1.0, 1.0]:
		var hd := PackedVector3Array()
		var hr := PackedFloat32Array()
		for i in 9:
			var a := PI * i / 8.0
			hd.append(Vector3(sx * (size.x * 0.5 + 0.02), hb * 0.68 - sin(a) * 0.045, cos(a) * 0.07))
			hr.append(0.007)
		tube(k, "iron", xf, hd, hr, 6, iron)
		for sz in [-1.0, 1.0]:
			k.box("iron", xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 + 0.004), hb * 0.68, sz * 0.07)), Vector3(0.008, 0.04, 0.03), iron)

## An open farm crate: solid end boards, two slats along each side with a gap between,
## slatted bottom.
static func farm_crate(k: MeshKit, xf: Transform3D, size: Vector3, r: RandomNumberGenerator, col := Color(0.7, 0.56, 0.38)) -> void:
	var t := 0.016
	for sx in [-1.0, 1.0]:
		k.box("pv_board", xf * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 - 0.012), size.y * 0.5, 0)), Vector3(0.024, size.y, size.z), col.darkened(r.randf_range(0.05, 0.15)))
	for sd in [1.0, -1.0]:
		for i in 2:
			var y := 0.03 + i * (size.y * 0.5)
			k.box("pv_board", xf * Transform3D(Basis(Vector3.FORWARD, r.randf_range(-0.005, 0.005)), Vector3(0, y + size.y * 0.18, sd * (size.z * 0.5 - t * 0.5))), Vector3(size.x - 0.004, size.y * 0.36, t), col.darkened(r.randf_range(0.0, 0.2)))
	for i in 4:
		var z := (i - 1.5) * size.z * 0.24
		k.box("pv_board", xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.006, z)), Vector3(size.x - 0.04, 0.012, size.z * 0.18), col.darkened(r.randf_range(0.1, 0.25)))
	# A false floor the apples rest on (hidden under them).
	k.box("pv_board", xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), Vector3(size.x - 0.05, 0.01, size.z - 0.03), col.darkened(0.45))
	for sx in [-1.0, 1.0]:
		for sd in [1.0, -1.0]:
			for i in 2:
				_nail(k, xf, Vector3(sx * (size.x * 0.5 - 0.012), 0.03 + i * (size.y * 0.5) + size.y * 0.18, sd * (size.z * 0.5 + 0.001)), Vector3(0, 0, sd), 0.004)
