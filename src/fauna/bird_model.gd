class_name BirdModel
## Procedural fliers (no free bird models fit the asset rule): smooth bodies with a crown,
## neck and deep breast, a beak, eyes and a fanned tail, and wings laid up like real ones
## from coverts and overlapping flight feathers, all in plumage (feather.gdshader). Fantasy
## moths get broad patterned wings with glowing eye spots,
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

## Natural colours for the real birds; the rest take the species' own.
static func _palette(p: Dictionary) -> Array:
	match String(p["name"]):
		"Crow": return [Color(0.05, 0.05, 0.06), Color(0.13, 0.13, 0.17), Color(0.03, 0.03, 0.04), Color(0.12, 0.11, 0.1)]
		"Kestrel": return [Color(0.52, 0.53, 0.56), Color(0.62, 0.34, 0.17), Color(0.5, 0.28, 0.14), Color(0.85, 0.7, 0.25)]
		"Swallow": return [Color(0.08, 0.1, 0.25), Color(0.1, 0.13, 0.3), Color(0.05, 0.06, 0.15), Color(0.1, 0.09, 0.08)]
	var c: Color = p["col"]
	var c2: Color = p["col2"]
	return [c2, c, c.darkened(0.35), Color(0.85, 0.7, 0.3)]

## Body cross-sections, head to tail: [z, centre height, half width, height above and
## below the centre]. A rounded crown and a short neck, a deep breast that bulges below
## the line of the back, a flat back, tapering to the vent under the tail.
const BODY := [
	[0.25, 0.034, 0.0, 0.0, 0.0],
	[0.243, 0.038, 0.026, 0.024, 0.02],
	[0.228, 0.044, 0.044, 0.04, 0.032],
	[0.205, 0.048, 0.052, 0.047, 0.038],
	[0.18, 0.044, 0.049, 0.043, 0.04],
	[0.155, 0.034, 0.046, 0.04, 0.045],
	[0.12, 0.02, 0.06, 0.048, 0.062],
	[0.07, 0.008, 0.077, 0.058, 0.08],
	[0.02, 0.004, 0.082, 0.062, 0.082],
	[-0.04, 0.006, 0.075, 0.056, 0.07],
	[-0.1, 0.01, 0.056, 0.042, 0.046],
	[-0.15, 0.015, 0.034, 0.026, 0.024],
	[-0.19, 0.02, 0.0, 0.0, 0.0],
]

## A Catmull-Rom curve through `v`, `k` steps a span.
static func _smooth(v: PackedFloat32Array, k: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := v.size()
	for i in n - 1:
		var p0 := v[maxi(i - 1, 0)]
		var p1 := v[i]
		var p2 := v[i + 1]
		var p3 := v[mini(i + 2, n - 1)]
		for j in k:
			var t := float(j) / k
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(v[n - 1])
	return out

## The body through BODY's sections (smoothed, `segs` round), widths times `fat`,
## crown and back heights times `head` and `back`. UV: x round the body, y head to tail.
## Returns the rings, for placing the eyes.
static func _body(g: HiFlora.Geo, key: String, segs: int, fat: float, head: float) -> Array:
	var cols: Array = []
	for c in 5:
		var v := PackedFloat32Array()
		for row in BODY:
			v.append(float(row[c]))
		cols.append(_smooth(v, 4))
	var zs: PackedFloat32Array = cols[0]
	var n := zs.size()
	var rings: Array = []
	for i in n:
		var z := zs[i]
		var hd := smoothstep(0.15, 0.2, z) # the head's share of this ring
		var rx := maxf((cols[2] as PackedFloat32Array)[i], 0.0) * lerpf(fat, 1.0, hd)
		var cy := (cols[1] as PackedFloat32Array)[i]
		var rt := maxf((cols[3] as PackedFloat32Array)[i], 0.0) * lerpf(1.0, head, hd)
		var rb := maxf((cols[4] as PackedFloat32Array)[i], 0.0) * lerpf(fat, 1.0, hd)
		var ring := PackedVector3Array()
		for j in segs + 1:
			var a := TAU * j / segs
			var sa := sin(a)
			# A flatter back and a fuller breast than a plain ellipse.
			var y := cy + (rt * pow(absf(sa), 0.85) if sa > 0.0 else -rb * absf(sa))
			ring.append(Vector3(rx * cos(a), y, z))
		rings.append(ring)
	for i in n - 1:
		for j in segs:
			var q: Array = []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var ii: int = c[0]
				var jj: int = c[1]
				var pt: Vector3 = rings[ii][jj]
				var along: Vector3 = (rings[mini(ii + 1, n - 1)] as PackedVector3Array)[jj] - (rings[maxi(ii - 1, 0)] as PackedVector3Array)[jj]
				var round: Vector3 = (rings[ii] as PackedVector3Array)[(jj + 1) % segs] - (rings[ii] as PackedVector3Array)[(jj + segs - 1) % segs]
				var nn := round.cross(along)
				var mid := Vector3(0.0, (cols[1] as PackedFloat32Array)[ii], zs[ii])
				if nn.length_squared() < 1e-12:
					nn = Vector3(0, 0, 1) if ii == 0 else Vector3(0, 0, -1)
				elif nn.dot(pt - mid) < 0.0:
					nn = -nn
				q.append([pt, nn.normalized(), Vector2(float(jj) / segs, float(ii) / (n - 1))])
			g.tri(key, q[0][0], q[1][0], q[2][0], q[0][1], q[1][1], q[2][1], q[0][2], q[1][2], q[2][2])
			g.tri(key, q[0][0], q[2][0], q[3][0], q[0][1], q[2][1], q[3][1], q[0][2], q[2][2], q[3][2])
	return rings

## One feather: a tapered strip from `root` toward `dir`, drooping a little at the tip,
## `hw` its half width at the root and widest, tip rounded off by the plumage shader.
static func _quill(g: HiFlora.Geo, key: String, root: Vector3, dir: Vector3, length: float, hw: float, tip_w := -1.0, droop := 0.006) -> void:
	var pts := PackedVector3Array()
	var ws := PackedFloat32Array()
	dir = dir.normalized()
	if tip_w < 0.0:
		tip_w = hw
	for j in 5:
		var t := float(j) / 4.0
		pts.append(root + dir * length * t + Vector3(0, -droop * t * t, 0))
		ws.append(lerpf(hw * 0.55, tip_w, smoothstep(0.0, 0.6, t)))
	g.ribbon(key, pts, ws, Vector3.RIGHT if absf(dir.x) < 0.7 else Vector3(0, 0, 1))

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
	# Eyes: a dark pupil in a coloured iris, wet and glossy.
	var iris := Color(0.35, 0.2, 0.06) if name == "Kestrel" else (Color(0.28, 0.2, 0.1) if name == "Crow" else Color(0.18, 0.11, 0.06))
	g.add_mat("eye", HiFlora.organic(Color(0.01, 0.01, 0.01), iris, {"streaks": 0.0, "sss": 0.0, "rough": 0.03}))
	if glows:
		g.add_mat("glow", HiFlora.organic(gcol.darkened(0.3), gcol, {"glow": 1.4, "glow_col": gcol, "streaks": 0.2, "sss": 0.9, "rough": 0.4}))
	var fat := 1.18 if finch else (0.88 if swallow else 1.0)
	var head := 0.85 if name == "Kestrel" else (1.06 if name == "Crow" else 1.0)
	var segs := 24
	var rings := _body(g, "body", segs, fat, head)
	# Eyes sit in the side of the head, a little forward and up, mostly sunk in.
	var er := 0.0085
	for ring in rings:
		var rp: PackedVector3Array = ring
		if absf(rp[0].z - 0.21) < 0.004:
			var e: Vector3 = rp[segs / 12] # about 30 degrees above the side
			for sd in [-1.0, 1.0]:
				g.lathe("eye", HiFlora._ellipse(er, er, 6), 10, Transform3D(Basis(), Vector3(sd * (absf(e.x) - er * 0.45), e.y, e.z)))
			break
	# Beak: a tapered horn from the face, hooked on kestrels, heavy on crows.
	var bl := 0.04 if finch else (0.07 if name == "Crow" else (0.035 if swallow else 0.05))
	var br := 0.018 if finch else (0.017 if name == "Crow" else 0.014)
	var hook := 0.5 if name == "Kestrel" else (0.15 if name == "Crow" else 0.06)
	var bpts := PackedVector3Array()
	var brs := PackedFloat32Array()
	for k in 5:
		var t := float(k) / 4.0
		bpts.append(Vector3(0, 0.034 - hook * bl * t * t, 0.236 + bl * t))
		brs.append(lerpf(br, 0.0015, pow(t, 0.8)))
	g.sweep("beak", bpts, brs, 7)
	# Tail: overlapping feathers in a fan, the middle pair on top; forked on swallows.
	var n := 9
	for i in n:
		var t := (float(i) / (n - 1)) * 2.0 - 1.0
		var tl := 0.16 + (absf(t) * 0.17 if swallow else 0.025 * (1.0 - absf(t)))
		var fan := t * (0.22 if swallow else 0.32)
		var root := Vector3(t * 0.014, 0.02 + (1.0 - absf(t)) * 0.004, -0.15)
		_quill(g, "dark", root, Vector3(sin(fan), -0.07, -cos(fan)), tl, 0.017, 0.006 if swallow and absf(t) > 0.7 else 0.019, 0.01)
	if finch and glows:
		for sd in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			var ws := PackedFloat32Array()
			for j in 8:
				var u := float(j) / 7.0
				pts.append(Vector3(sd * (0.02 + u * 0.05), 0.015 - u * 0.04 + sin(u * 5.0) * 0.02, -0.17 - u * 0.4))
				ws.append(lerpf(0.012, 0.004, u))
			g.ribbon("glow", pts, ws, Vector3.RIGHT)
	var body := g.commit()
	var wing := _wing(pal, glows, gcol, name)
	return {"body": body, "wing": wing, "wing_at": Vector3(0.06, 0.04, 0.06)}

## Where the wing's leading edge runs (z) at `u` of the way from shoulder to wrist and
## hand: forward over the arm, swept back toward the tip.
static func _le(u: float, pointed: bool) -> float:
	return 0.012 + 0.012 * sin(u * PI) - (0.07 if pointed else 0.035) * pow(maxf(u - 0.5, 0.0) / 0.5, 1.5)

## The right wing, from the shoulder at the origin out along +x, laid up like a real
## one: a rounded leading edge, small coverts over it, a row of greater coverts, then
## overlapping secondaries along the arm and primaries fanned from the hand, each row
## shingled over the next so the trailing edge is closed rather than a comb.
static func _wing(pal: Array, glows: bool, gcol: Color, name: String) -> ArrayMesh:
	var g := HiFlora.Geo.new()
	var pointed := name == "Kestrel" or name == "Swallow"
	var crow := name == "Crow"
	var span := 0.56 if pointed else 0.5
	g.add_mat("cov", _feather(pal[1], pal[1].lerp(pal[2], 0.4), 0.0, Color.WHITE, 2, name))
	var covf := _feather(pal[1].lerp(pal[2], 0.1), pal[1].lerp(pal[2], 0.3), 0.0, Color.WHITE, 1, "")
	covf.set_shader_parameter("tip_dark", 0.06)
	covf.set_shader_parameter("tip_round", 0.45)
	g.add_mat("covf", covf)
	g.add_mat("flight", _feather(pal[2].lightened(0.08), pal[2], 0.6 if glows else 0.0, gcol, 1, name))
	var sec_len := 0.085 if pointed else 0.1
	# Secondaries along the arm, inner ones on top.
	var ns := 10
	for i in ns:
		var u := 0.03 + float(i) / (ns - 1) * 0.5
		var root := Vector3(u * span, -0.001 * i * 0.6, _le(u, pointed) - 0.022)
		_quill(g, "flight", root, Vector3(0.12, -0.03, -1.0), sec_len * lerpf(0.9, 1.0, float(i) / ns), 0.021)
	# Primaries from the hand, fanning from back to out toward the tip.
	var np := 10
	for i in np:
		var t := float(i) / (np - 1)
		var u := 0.56 + 0.2 * t
		var root := Vector3(u * span, -0.005 - 0.0007 * i, _le(u, pointed) - 0.016)
		var ang := lerpf(-PI * 0.5 + 0.2, -0.3 if pointed else -0.12, pow(t, 0.85))
		var length := lerpf(sec_len * 1.1, span * (0.5 if pointed else 0.4), pow(t, 0.6))
		if not pointed and i == np - 1:
			length *= 0.9 # the outermost a little short: a rounded tip
		var tw := 0.011 if crow and t > 0.6 else (0.012 if pointed and t > 0.7 else 0.018)
		_quill(g, "flight", root, Vector3(cos(ang), -0.04, sin(ang)), length, 0.016, tw, 0.012)
	# Greater coverts over the secondaries' roots, and primary coverts over the hand.
	for i in ns:
		var u := 0.02 + float(i) / (ns - 1) * 0.52
		_quill(g, "covf", Vector3(u * span, 0.004 - 0.0004 * i, _le(u, pointed) - 0.01), Vector3(0.1, -0.03, -1.0), 0.055, 0.019)
	for i in 6:
		var t := float(i) / 5.0
		var u := 0.56 + 0.18 * t
		var ang := lerpf(-PI * 0.5 + 0.25, -0.5 if pointed else -0.35, t)
		_quill(g, "covf", Vector3(u * span, 0.002 - 0.0005 * i, _le(u, pointed) - 0.008), Vector3(cos(ang), -0.03, sin(ang)), 0.05, 0.016)
	# Small coverts in scalloped rows along the leading edge, and its rounded edge.
	var cov := PackedVector3Array()
	var cw := PackedFloat32Array()
	var edge := PackedVector3Array()
	var er := PackedFloat32Array()
	for i in 9:
		var u := float(i) / 8.0 * 0.8
		cov.append(Vector3(u * span, 0.007, _le(u, pointed) - 0.014))
		cw.append(lerpf(0.032, 0.014, u / 0.8))
		edge.append(Vector3(u * span, 0.003, _le(u, pointed) + 0.001))
		er.append(lerpf(0.007, 0.003, u / 0.8))
	g.ribbon("cov", cov, cw, Vector3(0, 0, 1), Color.WHITE, 0.25)
	g.sweep("cov", edge, er, 6)
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
