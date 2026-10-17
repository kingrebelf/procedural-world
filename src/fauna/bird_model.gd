class_name BirdModel
## Procedural fliers (no free bird models fit the asset rule): smooth lathed bodies with
## a beak, eyes and a fanned tail, and wings laid up from coverts and long primary and
## secondary feathers, all in feathered plumage (feather.gdshader). Fantasy moths get broad patterned wings with glowing eye spots,
## sci-fi skies get drifting jellies and scout drones. Facing +z, about 0.5 m long at
## scale 1; build() returns the body, the right wing (mirror it for the left) and the
## shoulder the wing hinges on. Meshes are cached per species.

static var _cache := {}

static func build(p: Dictionary, era: int) -> Dictionary:
	var key := "%s|%s|%s|%s" % [p["name"], p["col"].to_html(), p["glow"], p["has_glow"]]
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary
	match String(p["name"]):
		"Glowmoth": out = _moth(p)
		"Drift Jelly": out = _jelly(p)
		"Scout Drone": out = _drone(p)
		_: out = _bird(p, era)
	_cache[key] = out
	return out

static var _plumage: Shader

## Plumage (feather.gdshader). mode 0: body contour feathers, 1: flight and tail
## feathers, 2: wing coverts.
static func _feather(a: Color, b: Color, glow := 0.0, gcol := Color.WHITE, mode := 0, name := "") -> ShaderMaterial:
	if _plumage == null:
		_plumage = load("res://src/fauna/shaders/feather.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _plumage
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col_a", a)
	m.set_shader_parameter("col_b", b)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("glow_col", gcol)
	var dark := (a.get_luminance() + b.get_luminance()) * 0.5 < 0.12
	m.set_shader_parameter("fringe", -0.25 if dark else 0.3)
	m.set_shader_parameter("sheen", 1.0 if dark else 0.0)
	m.set_shader_parameter("bars", 0.45 if name == "Kestrel" and mode == 1 else 0.0)
	return m

## The profile through its points on a Catmull-Rom curve, `k` steps a span, so the
## lathed body is smooth rather than ringed with facets.
static func _smooth_profile(p: PackedVector2Array, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := p.size()
	for i in n - 1:
		var p0 := p[maxi(i - 1, 0)]
		var p1 := p[i]
		var p2 := p[i + 1]
		var p3 := p[mini(i + 2, n - 1)]
		for j in k:
			var t := float(j) / k
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)
			q.x = maxf(q.x, 0.0)
			out.append(q)
	out.append(p[n - 1])
	return out

## Natural colours for the real birds; the rest take the species' own.
static func _palette(p: Dictionary) -> Array:
	match String(p["name"]):
		"Crow": return [Color(0.05, 0.05, 0.06), Color(0.13, 0.13, 0.17), Color(0.03, 0.03, 0.04), Color(0.12, 0.11, 0.1)]
		"Kestrel": return [Color(0.52, 0.53, 0.56), Color(0.62, 0.34, 0.17), Color(0.5, 0.28, 0.14), Color(0.85, 0.7, 0.25)]
		"Swallow": return [Color(0.08, 0.1, 0.25), Color(0.1, 0.13, 0.3), Color(0.05, 0.06, 0.15), Color(0.1, 0.09, 0.08)]
	var c: Color = p["col"]
	var c2: Color = p["col2"]
	return [c2, c, c.darkened(0.35), Color(0.85, 0.7, 0.3)]

static func _bird(p: Dictionary, era: int) -> Dictionary:
	var pal := _palette(p)
	var gcol := Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0)
	var glows: bool = p["has_glow"] and era != Eras.MEDIEVAL
	var name := String(p["name"])
	var swallow := name == "Swallow"
	var finch := name == "Wisp Finch"
	var g := HiFlora.Geo.new()
	g.add_mat("body", _feather(pal[0], pal[1], 0.15 if glows else 0.0, gcol, 0, name))
	g.add_mat("dark", _feather(pal[2], pal[2].lightened(0.15), 0.0, Color.WHITE, 1, name))
	g.add_mat("beak", HiFlora.organic(pal[3].darkened(0.2), pal[3], {"streaks": 0.0, "sss": 0.1, "rough": 0.45}))
	g.add_mat("eye", HiFlora.organic(Color(0.02, 0.02, 0.02), Color(0.05, 0.04, 0.03), {"streaks": 0.0, "sss": 0.0, "rough": 0.1}))
	if glows:
		g.add_mat("glow", HiFlora.organic(gcol.darkened(0.3), gcol, {"glow": 1.4, "glow_col": gcol, "streaks": 0.2, "sss": 0.9, "rough": 0.4}))
	var fat := 1.18 if finch else 1.0
	# Head to tail along +z -> -z, lathed round the body axis.
	var prof := PackedVector2Array([Vector2(0.0, 0.25), Vector2(0.035, 0.245), Vector2(0.058, 0.225), Vector2(0.064, 0.2),
		Vector2(0.057, 0.172), Vector2(0.074 * fat, 0.13), Vector2(0.095 * fat, 0.06), Vector2(0.097 * fat, -0.01),
		Vector2(0.082 * fat, -0.08), Vector2(0.052, -0.14), Vector2(0.026, -0.18), Vector2(0.0, -0.195)])
	prof = _smooth_profile(prof, 4)
	var axis := Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis().scaled(Vector3(0.9, 1.0, 1.0)), Vector3.ZERO)
	g.lathe("body", prof, 24, axis, Vector2(0.0, -0.035))
	# Beak, eyes.
	var bl := 0.045 if finch else (0.075 if name == "Crow" else 0.055)
	g.prism("beak", Vector3(0, 0.034, 0.238), Vector3(0, -0.22 if name == "Kestrel" else -0.1, 1.0), 0.02 if not finch else 0.024, bl, 5, 0.75)
	for s in [-1.0, 1.0]:
		g.lathe("eye", HiFlora._ellipse(0.013, 0.013, 6), 8, Transform3D(Basis(), Vector3(s * 0.05, 0.058, 0.205)))
	# Tail fan, forked on swallows, with glowing streamers on wisp finches.
	var n := 7
	for i in n:
		var t := (float(i) / (n - 1)) * 2.0 - 1.0
		var tl := 0.17 + (absf(t) * 0.16 if swallow else 0.02 * (1.0 - absf(t)))
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for j in 5:
			var u := float(j) / 4.0
			pts.append(Vector3(t * (0.012 + u * (0.07 if not swallow else 0.05)), 0.02 - u * 0.012, -0.16 - u * tl))
			ws.append(lerpf(0.016, 0.022 if not swallow else 0.008, u))
		g.ribbon("dark", pts, ws, Vector3.RIGHT)
	if finch and glows:
		for s in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			var ws := PackedFloat32Array()
			for j in 8:
				var u := float(j) / 7.0
				pts.append(Vector3(s * (0.02 + u * 0.05), 0.015 - u * 0.04 + sin(u * 5.0) * 0.02, -0.17 - u * 0.4))
				ws.append(lerpf(0.012, 0.004, u))
			g.ribbon("glow", pts, ws, Vector3.RIGHT)
	var body := g.commit()
	var wing := _wing(pal, glows, gcol, name)
	return {"body": body, "wing": wing, "wing_at": Vector3(0.055, 0.045, 0.06)}

## The right wing, from the shoulder at the origin out along +x: coverts over the
## inner wing, secondaries along its trailing edge, primaries fanned at the hand.
static func _wing(pal: Array, glows: bool, gcol: Color, name: String) -> ArrayMesh:
	var g := HiFlora.Geo.new()
	var pointed := name == "Kestrel" or name == "Swallow"
	var span := 0.62 if pointed else 0.52
	g.add_mat("cov", _feather(pal[1], pal[1].lerp(pal[2], 0.4), 0.0, Color.WHITE, 2, name))
	g.add_mat("flight", _feather(pal[2].lightened(0.08), pal[2], 0.6 if glows else 0.0, gcol, 1, name))
	# Coverts: one broad, gently cambered strip from shoulder to wrist.
	var cov := PackedVector3Array()
	var cw := PackedFloat32Array()
	for i in 7:
		var u := float(i) / 6.0
		cov.append(Vector3(u * span * 0.62, 0.008 * sin(u * PI), -0.03 - u * 0.02))
		cw.append(lerpf(0.075, 0.04, u))
	g.ribbon("cov", cov, cw, Vector3(0, 0, 1), Color.WHITE, 0.15)
	# Secondaries: short feathers raked back along the inner trailing edge.
	for i in 6:
		var u := (float(i) + 0.5) / 6.0
		var root := Vector3(u * span * 0.58, 0.0, -0.06 - u * 0.015)
		var pts := PackedVector3Array([root, root + Vector3(0.008, -0.002, -0.05), root + Vector3(0.016, -0.004, -0.095)])
		g.ribbon("flight", pts, PackedFloat32Array([0.022, 0.024, 0.015]), Vector3.RIGHT)
	# Primaries: long feathers from the hand, sweeping out and back to the tip.
	var np := 7
	for i in np:
		var u := float(i) / (np - 1)
		var root := Vector3(span * (0.5 + 0.12 * u), 0.004, -0.04 - 0.02 * u)
		var sweep := lerpf(-0.55, 0.15, u) if pointed else lerpf(-0.7, 0.35, u)
		var length := span * (0.42 + 0.18 * (1.0 - absf(u - 0.75) * 1.4)) * (1.15 if pointed else 1.0)
		var dir := Vector3(cos(sweep * 0.6), 0, -absf(sin(sweep)) * 0.9 - 0.15).normalized()
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for j in 5:
			var t := float(j) / 4.0
			pts.append(root + dir * length * t + Vector3(0, -0.012 * t * t, 0))
			ws.append(lerpf(0.02, 0.01 if pointed else 0.016, t))
		g.ribbon("flight", pts, ws, Vector3(0, 0, 1), Color.WHITE, 0.1)
	return g.commit()

## Glowmoth: a furry body, feathered antennae, broad fore and hind wings with
## glowing eye spots.
static func _moth(p: Dictionary) -> Dictionary:
	var c: Color = p["col"]
	var gcol := Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0)
	var g := HiFlora.Geo.new()
	g.add_mat("fur", HiFlora.organic(c.darkened(0.3), c.lightened(0.2), {"streaks": 0.9, "sss": 0.5, "rough": 0.9}))
	g.add_mat("eye", HiFlora.organic(Color(0.02, 0.02, 0.02), gcol.darkened(0.6), {"streaks": 0.0, "glow": 0.5, "glow_col": gcol}))
	var axis := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	g.lathe("fur", PackedVector2Array([Vector2(0, 0.12), Vector2(0.04, 0.11), Vector2(0.05, 0.08), Vector2(0.045, 0.05), Vector2(0.06, 0.0),
		Vector2(0.055, -0.08), Vector2(0.035, -0.16), Vector2(0.0, -0.19)]), 12, axis, Vector2.ZERO, Color.WHITE, 0.08, 3)
	for s in [-1.0, 1.0]:
		g.lathe("eye", HiFlora._ellipse(0.018, 0.018, 6), 8, Transform3D(Basis(), Vector3(s * 0.035, 0.02, 0.1)))
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for j in 6:
			var u := float(j) / 5.0
			pts.append(Vector3(s * (0.02 + u * 0.09), 0.03 + u * 0.08, 0.11 + u * 0.1 - u * u * 0.05))
			ws.append(lerpf(0.004, 0.02, sin(u * PI)))
		g.ribbon("fur", pts, ws, Vector3(0, 1, 0))
	var body := g.commit()
	var w := HiFlora.Geo.new()
	w.add_mat("wing", HiFlora.organic(c.darkened(0.15), c.lerp(gcol, 0.35), {"streaks": 0.25, "sss": 1.0, "rough": 0.6,
		"spot_amt": 0.8, "spot_col": gcol, "spot_glow": 1.6, "spot_scale": 9.0, "glow_col": gcol, "glow": 0.15}))
	for f in [[Vector3(0.02, 0, 0.05), 0.55, 0.42, 0.2], [Vector3(0.02, 0, -0.04), 0.4, 0.34, -0.55]]:
		var root: Vector3 = f[0]
		var length: float = f[1]
		var width: float = f[2]
		var ang: float = f[3]
		var dir := Vector3(cos(ang), 0, sin(ang))
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for j in 8:
			var u := float(j) / 7.0
			pts.append(root + dir * length * u)
			ws.append(width * 0.5 * pow(sin(PI * (0.12 + u * 0.88)), 0.7) + 0.01)
		w.ribbon("wing", pts, ws, Vector3(-dir.z, 0, dir.x), Color.WHITE, 0.05)
	return {"body": body, "wing": w.commit(), "wing_at": Vector3(0.04, 0.03, 0.02)}

## Drift jelly: a glowing bell with frilled fins and trailing tendrils.
static func _jelly(p: Dictionary) -> Dictionary:
	var gcol := Color.from_hsv(float(p["glow"]) / 12.0, 0.6, 1.0)
	var g := HiFlora.Geo.new()
	g.add_mat("bell", HiFlora.crystal(gcol.lerp(Color.WHITE, 0.3), gcol, 0.7, 0.9))
	g.add_mat("tendril", HiFlora.organic(gcol.darkened(0.3), gcol.lightened(0.3), {"glow": 1.0, "glow_col": gcol, "sss": 1.0, "streaks": 0.0}))
	g.lathe("bell", PackedVector2Array([Vector2(0, 0.32), Vector2(0.12, 0.3), Vector2(0.22, 0.22), Vector2(0.27, 0.1), Vector2(0.29, 0.0), Vector2(0.24, -0.02), Vector2(0.14, 0.04), Vector2(0.0, 0.05)]), 16, Transform3D.IDENTITY, Vector2.ZERO, Color.WHITE, 0.05, 1)
	for i in 10:
		var a := TAU * i / 10.0
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for j in 8:
			var u := float(j) / 7.0
			var r := 0.22 * (1.0 - u * 0.25)
			pts.append(Vector3(cos(a) * r + sin(u * 7.0 + a) * 0.03, -u * 0.9, sin(a) * r + cos(u * 6.0 + a) * 0.03))
			ws.append(lerpf(0.012, 0.003, u))
		g.sweep("tendril", pts, ws, 4)
	var w := HiFlora.Geo.new()
	w.add_mat("fin", HiFlora.organic(gcol.darkened(0.2), gcol.lightened(0.2), {"glow": 0.8, "glow_col": gcol, "sss": 1.0, "streaks": 0.4}))
	var pts := PackedVector3Array()
	var ws := PackedFloat32Array()
	for j in 6:
		var u := float(j) / 5.0
		pts.append(Vector3(u * 0.3, 0.0, 0.0))
		ws.append(0.12 * sin(PI * (0.15 + u * 0.85)) + 0.01)
	w.ribbon("fin", pts, ws, Vector3(0, 0, 1), Color.WHITE, 0.2)
	return {"body": g.commit(), "wing": w.commit(), "wing_at": Vector3(0.25, 0.08, 0.0)}

## Scout drone: a sensor pod with a glowing eye, and rotor arms (they wobble as it
## flies).
static func _drone(p: Dictionary) -> Dictionary:
	var gcol := Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0)
	var k := MeshKit.new(7)
	var I := Transform3D.IDENTITY
	k.sphere("metal_dark", I, 0.16, 8, 12)
	k.cylinder("metal", I.translated(Vector3(0, -0.04, 0)), 0.2, 0.2, 0.06, 16)
	k.sphere("glow_cyan" if gcol.h > 0.4 and gcol.h < 0.7 else "glow_red", I.translated(Vector3(0, 0.0, 0.14)), 0.05, 5, 8)
	k.box("metal_dark", I.translated(Vector3(0, -0.16, 0)), Vector3(0.04, 0.1, 0.04))
	var body := k.commit(Materials.get_mat)
	var w := MeshKit.new(8)
	w.box("metal", I.translated(Vector3(0.16, 0, 0)), Vector3(0.32, 0.03, 0.05))
	w.cylinder("metal_dark", I.translated(Vector3(0.33, -0.02, 0)), 0.03, 0.03, 0.06, 8)
	w.cylinder("glass", I.translated(Vector3(0.33, 0.04, 0)), 0.14, 0.14, 0.008, 18)
	return {"body": body, "wing": w.commit(Materials.get_mat), "wing_at": Vector3(0.12, 0.0, 0.0)}
