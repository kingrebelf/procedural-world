class_name TechModels
## Human sci-fi parts and kit: chips, boards, servos, lenses, coils, cells, keycards, datapads, drones, scanners, masks, packs.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.
##
## Human made, so nothing glows: the cyan and blue light strips of the paintings are
## tinted glass or paint, dark screens are dark glass.

const BUILD := {
	"circuitry": "_circuitry", "alloy_scrap": "_alloy_scrap", "power_cell": "_power_cell",
	"data_core": "_data_core", "scanner": "_scanner", "drone_scout": "_drone_scout",
	"turret_deploy": "_turret_deploy", "shield_gen": "_shield_gen", "beacon_nav": "_beacon_nav",
	"battery_small": "_battery_small", "fusion_core": "_fusion_core", "keycard_red": "_keycard_red",
	"keycard_blue": "_keycard_blue", "keycard_gold": "_keycard_gold", "datapad": "_datapad",
	"holo_projector": "_holo_projector", "credit_chip": "_credit_chip", "magboots_kit": "_magboots_kit",
	"o2_canister": "_o2_canister", "carbon_fiber": "_carbon_fiber", "polymer": "_polymer",
	"graphene": "_graphene", "ceramic_plate": "_ceramic_plate", "nanotube_spool": "_nanotube_spool",
	"microchip": "_microchip", "servo": "_servo", "optic_lens": "_optic_lens",
	"wiring_loom": "_wiring_loom", "coolant": "_coolant", "superconductor": "_superconductor",
	"fuel_rod": "_fuel_rod", "circuit_board": "_circuit_board", "processor": "_processor",
	"hull_patch": "_hull_patch", "sensor_module": "_sensor_module", "gyroscope": "_gyroscope",
	"thruster_part": "_thruster_part", "antenna": "_antenna", "solar_panel": "_solar_panel",
	"magnet": "_magnet", "nanopaste": "_nanopaste", "quantum_chip": "_quantum_chip",
	"splint_mech": "_splint_mech", "oxygen_mask": "_oxygen_mask", "defibrillator": "_defibrillator",
}

const STEEL := Color(0.66, 0.67, 0.69)
const GUN := Color(0.24, 0.25, 0.27) ## gunmetal housings
const BLACK := Color(0.07, 0.07, 0.08)
const ORANGE := Color(0.95, 0.52, 0.1)
const GOLD := Color(0.92, 0.7, 0.3)
const PCB := Color(0.14, 0.4, 0.17)
const Z := Vector3(0, 0, 1)
const FLAT := Basis(Vector3(1, 0, 0), -PI * 0.5 + 0.5) ## lays a +Z face up, propped toward the viewer as painted

# --- Shared shapes ----------------------------------------------------------------------

static func _at(x: float, y: float, z: float, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, Vector3(x, y, z))

## A basis whose +Y runs along `dir`.
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))

## A cylinder (or cone) from point a to point b.
static func _cyl(k: MeshKit, m: String, xf: Transform3D, a: Vector3, b: Vector3, ra: float, rb: float, segs: int, col: Color, caps := true) -> void:
	k.cylinder(m, xf * Transform3D(_along(b - a), a), ra, rb, a.distance_to(b), segs, caps, 0.0, 1, col)

## Revolved profile (r, y) about xf's +Y; a closed profile run counter-clockwise faces out.
static func _lathe(k: MeshKit, m: String, xf: Transform3D, prof: Array, segs: int, col: Variant, arc := Vector2(0.0, 1.0)) -> void:
	var p := PackedVector2Array()
	for v: Vector2 in prof:
		p.append(v)
	Provisions.lathe(k, m, xf, p, segs, col, null, arc)

## A band of a cylinder's skin (radius r, from y0 to y1) over part of a turn, centred on
## angle `mid` (radians, 0 = +X, PI/2 = +Z), `half` either side: windows and panels on
## round bodies.
static func _arc_panel(k: MeshKit, m: String, xf: Transform3D, r: float, y0: float, y1: float, mid: float, half: float, col: Color) -> void:
	var a := Vector2((mid - half) / TAU, (mid + half) / TAU)
	_lathe(k, m, xf, [Vector2(r, y0), Vector2(r, y1)], maxi(3, int(half * 24.0)), col, a)

## A flat strip of boxes along a path (straps, bent bars); `up` is the strip's face.
static func _strip(k: MeshKit, m: String, xf: Transform3D, pts: PackedVector3Array, w: float, th: float, col: Color, up := Z) -> void:
	for i in pts.size() - 1:
		var d := pts[i + 1] - pts[i]
		var l := d.length()
		if l < 1e-5:
			continue
		var y := d / l
		var x := up.cross(y)
		if x.length() < 1e-4:
			x = Vector3.RIGHT.cross(y)
		x = x.normalized()
		var b := Basis(x, y, x.cross(y))
		k.box(m, xf * Transform3D(b, (pts[i] + pts[i + 1]) * 0.5), Vector3(w, l * 1.04, th), col)

## Signed area: positive when the outline runs counter-clockwise (x right, y up).
static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

## A rounded rectangle outline, counter-clockwise.
static func _rrect(w: float, h: float, r: float, c := Vector2.ZERO, seg := 4) -> PackedVector2Array:
	var p := PackedVector2Array()
	var rr := clampf(r, 0.0002, minf(w, h) * 0.5 - 0.0001)
	var cs := [Vector2(w * 0.5 - rr, h * 0.5 - rr), Vector2(-w * 0.5 + rr, h * 0.5 - rr), Vector2(-w * 0.5 + rr, -h * 0.5 + rr), Vector2(w * 0.5 - rr, -h * 0.5 + rr)]
	for q in 4:
		for s in seg + 1:
			var a := PI * 0.5 * q + PI * 0.5 * s / seg
			p.append(c + (cs[q] as Vector2) + Vector2(cos(a), sin(a)) * rr)
	return p

## An outline (in xf's XY plane) made solid `th` thick about z = 0, with holes cut through.
static func _ext(k: MeshKit, m: String, xf: Transform3D, outer: PackedVector2Array, holes: Array, th: float, col: Color, side_col: Variant = null) -> void:
	var o := outer.duplicate()
	if _area(o) < 0.0:
		o.reverse()
	var loops: Array = [o]
	var poly := o.duplicate()
	for h0 in holes:
		var h: PackedVector2Array = (h0 as PackedVector2Array).duplicate()
		if _area(h) > 0.0:
			h.reverse()
		loops.append(h)
		var bi := 0
		var bj := 0
		var bd := INF
		for i in poly.size():
			for j in h.size():
				var d := poly[i].distance_squared_to(h[j])
				if d < bd:
					bd = d
					bi = i
					bj = j
		var np := PackedVector2Array()
		for i in bi + 1:
			np.append(poly[i])
		for j in h.size() + 1:
			np.append(h[(bj + j) % h.size()])
		for i in range(bi, poly.size()):
			np.append(poly[i])
		poly = np
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		poly = o
		tris = Geometry2D.triangulate_polygon(o)
	var hz := th * 0.5
	for t in range(0, tris.size(), 3):
		var a := poly[tris[t]]
		var b := poly[tris[t + 1]]
		var c := poly[tris[t + 2]]
		ItemModels._tri(k, m, xf, Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(c.x, c.y, hz), Z, Z, Z, col)
		ItemModels._tri(k, m, xf, Vector3(a.x, a.y, -hz), Vector3(b.x, b.y, -hz), Vector3(c.x, c.y, -hz), -Z, -Z, -Z, col)
	var sc: Color = col if side_col == null else side_col
	for lp in loops:
		var l: PackedVector2Array = lp
		for i in l.size():
			var p0 := l[i]
			var p1 := l[(i + 1) % l.size()]
			var d := p1 - p0
			if d.length() < 1e-6:
				continue
			var n := Vector3(d.y, -d.x, 0).normalized()
			ItemModels._quad(k, m, xf, Vector3(p0.x, p0.y, -hz), Vector3(p1.x, p1.y, -hz), Vector3(p1.x, p1.y, hz), Vector3(p0.x, p0.y, hz), n, sc)

## An outline made solid with its front and back edges chamfered (a core at full
## thickness, inset by `bevel`, over a rim a little thinner).
static func _ext_bevel(k: MeshKit, m: String, xf: Transform3D, outer: PackedVector2Array, holes: Array, th: float, bevel: float, col: Color) -> void:
	var inner: Array = Geometry2D.offset_polygon(outer, -bevel)
	var grown: Array = []
	for h: PackedVector2Array in holes:
		var g: Array = Geometry2D.offset_polygon(h, bevel)
		grown.append(g[0] if not g.is_empty() else h)
	_ext(k, m, xf, outer, holes, th - bevel * 1.2, col.darkened(0.08))
	if not inner.is_empty():
		_ext(k, m, xf, inner[0], grown, th, col)

## A thin flat line of copper on a board (z just above its face).
static func _trace(k: MeshKit, xf: Transform3D, pts: PackedVector2Array, w: float, col: Color, z := 0.00012) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * w * 0.5
		a -= d * w * 0.5
		b += d * w * 0.5
		ItemModels._quad(k, "own:pcb", xf, Vector3(a.x - n.x, a.y - n.y, z), Vector3(b.x - n.x, b.y - n.y, z), Vector3(b.x + n.x, b.y + n.y, z), Vector3(a.x + n.x, a.y + n.y, z), Z, col)

## A bare board (its face at z = 0, facing +Z) with plated mounting holes at the corners
## and a scatter of copper tracks.
static func _board(k: MeshKit, r: RandomNumberGenerator, xf: Transform3D, w: float, h: float, col: Color, tracks: int) -> void:
	var th := 0.0016
	k.bevel_box("own:pcb", xf * _at(0, 0, -th * 0.5), Vector3(w, h, th), 0.0005, col)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c := Vector3(sx * (w * 0.5 - 0.005), sy * (h * 0.5 - 0.005), 0.00015)
			ItemModels._disc(k, "im:metal@0.3", xf, c, Z, 0.0032, 14, GOLD, 0.0016)
			ItemModels._disc(k, "own:pcb", xf, c, Z, 0.0016, 10, Color(0.05, 0.06, 0.05))
	var tc := col.lightened(0.22)
	for i in tracks:
		var p := Vector2(r.randf_range(-w * 0.42, w * 0.42), r.randf_range(-h * 0.42, h * 0.42))
		var pts := PackedVector2Array([p])
		for s in 3:
			var horiz := (s + i) % 2 == 0
			var step := r.randf_range(-0.025, 0.025)
			p += Vector2(step, 0) if horiz else Vector2(0, step)
			if s == 1:
				p += Vector2(signf(step) * 0.004, signf(step) * 0.004)
			p = Vector2(clampf(p.x, -w * 0.46, w * 0.46), clampf(p.y, -h * 0.46, h * 0.46))
			pts.append(p)
		_trace(k, xf, pts, 0.0007, tc)

## A square chip package on a face at z = 0: plastic body w across, n gull-wing legs a
## side bent down to the board.
static func _qfp(k: MeshKit, xf: Transform3D, w: float, th: float, body: Color, n: int, legs: Color, leg_l := 0.0) -> void:
	k.bevel_box("own:plastic", xf * _at(0, 0, th * 0.5), Vector3(w, w, th), th * 0.25, body)
	var ll := leg_l if leg_l > 0.0 else w * 0.09
	var pitch := w * 0.84 / n
	for side in 4:
		var b := Basis(Z, side * PI * 0.5)
		for i in n:
			var off := (i - (n - 1) * 0.5) * pitch
			k.box("im:metal@0.25", xf * Transform3D(b, b * Vector3(off, w * 0.5 + ll * 0.35, th * 0.45)), Vector3(pitch * 0.5, ll * 0.7, th * 0.16), legs)
			k.box("im:metal@0.25", xf * Transform3D(b, b * Vector3(off, w * 0.5 + ll * 0.72, th * 0.24)), Vector3(pitch * 0.5, th * 0.16, th * 0.5), legs)
			k.box("im:metal@0.25", xf * Transform3D(b, b * Vector3(off, w * 0.5 + ll * 0.9, th * 0.04)), Vector3(pitch * 0.5, ll * 0.4, th * 0.12), legs)

## A narrow chip (legs on its two long sides).
static func _soic(k: MeshKit, xf: Transform3D, w: float, l: float, n: int) -> void:
	var th := 0.0016
	k.bevel_box("own:plastic", xf * _at(0, 0, th * 0.5), Vector3(w, l, th), 0.0004, BLACK)
	var pitch := l * 0.85 / n
	for sx: float in [-1.0, 1.0]:
		for i in n:
			var y := (i - (n - 1) * 0.5) * pitch
			k.box("im:metal@0.3", xf * _at(sx * (w * 0.5 + 0.0007), y, th * 0.3), Vector3(0.0016, pitch * 0.5, 0.0005), Color(0.78, 0.78, 0.8))

## Small surface parts (resistors and capacitors) scattered on a board.
static func _smd(k: MeshKit, r: RandomNumberGenerator, xf: Transform3D, w: float, h: float, n: int, avoid: Array) -> void:
	var cols := [Color(0.82, 0.72, 0.52), Color(0.45, 0.3, 0.18), Color(0.12, 0.12, 0.12), Color(0.7, 0.62, 0.45)]
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 12:
		tries += 1
		var p := Vector2(r.randf_range(-w * 0.44, w * 0.44), r.randf_range(-h * 0.44, h * 0.44))
		var ok := true
		for a: Rect2 in avoid:
			if a.grow(0.002).has_point(p):
				ok = false
		if not ok:
			continue
		placed += 1
		var big := r.randf() < 0.35
		var s := Vector3(0.004, 0.0024, 0.0016) if big else Vector3(0.0026, 0.0014, 0.0009)
		var b := Basis.IDENTITY if r.randf() < 0.5 else Basis(Z, PI * 0.5)
		var c: Color = cols[r.randi() % cols.size()]
		k.box("own:plastic", xf * Transform3D(b, Vector3(p.x, p.y, s.z * 0.5)), s, c)
		for e: float in [-1.0, 1.0]:
			k.box("im:metal@0.3", xf * Transform3D(b, b * Vector3(e * s.x * 0.42, 0, 0) + Vector3(p.x, p.y, s.z * 0.5)), Vector3(s.x * 0.18, s.y * 1.02, s.z * 1.04), Color(0.8, 0.8, 0.82))

## A helix of wire wound round a spine (coiled cords): `per_m` turns a metre.
static func _coil(k: MeshKit, m: String, xf: Transform3D, spine: PackedVector3Array, per_m: float, rad: float, wire: float, col: Color) -> void:
	var dense := PackedVector3Array()
	var steps := 10
	for i in spine.size() - 1:
		for s in steps:
			dense.append(spine[i].lerp(spine[i + 1], float(s) / steps))
	dense.append(spine[spine.size() - 1])
	# Resample by length so the turns are even.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var along := 0.0
	var side := Vector3.ZERO
	for i in dense.size():
		var t := (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		if i > 0:
			along += dense[i].distance_to(dense[i - 1])
		if side == Vector3.ZERO:
			side = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		side = (side - t * side.dot(t)).normalized()
		var up := t.cross(side)
		var sub := 6
		for q in sub:
			if i == dense.size() - 1 and q > 0:
				break
			var a := TAU * (along + (dense[mini(i + 1, dense.size() - 1)].distance_to(dense[i]) * q / sub)) * per_m
			var c := dense[i].lerp(dense[mini(i + 1, dense.size() - 1)], float(q) / sub)
			path.append(c + (side * cos(a) + up * sin(a)) * rad)
			radii.append(wire)
	ItemModels._tube(k, m, xf, path, radii, 5, col)

## A wire with a bend: a smooth curve through `pts` (Catmull-Rom).
static func _curve(pts: PackedVector3Array, per := 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for s in per:
			var t := float(s) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out

static func _wire(k: MeshKit, xf: Transform3D, pts: PackedVector3Array, rad: float, col: Color, m := "own:plastic") -> void:
	var c := _curve(pts)
	var radii := PackedFloat32Array()
	radii.resize(c.size())
	radii.fill(rad)
	ItemModels._tube(k, m, xf, c, radii, 6, col)

## A lens: a domed glass coloured from its middle out (coatings shift blue to violet) in a
## dark barrel; faces +Y of xf.
static func _lens(k: MeshKit, xf: Transform3D, rad: float, dome: float, mid: Color, rim: Color) -> void:
	var prof: Array = []
	for i in 9:
		var t := float(i) / 8.0
		prof.append(Vector2(rad * (1.0 - t), dome * sqrt(1.0 - (1.0 - t) * (1.0 - t))))
	var col := func(p: Vector3, _a: float, _t: float) -> Color:
		return mid.lerp(rim, pow(clampf(Vector2(p.x, p.z).length() / rad, 0.0, 1.0), 2.5))
	_lathe(k, "own:lens", xf, prof, 28, col)

## A painted metal canister body and dome: `prof` (r, y) bottom to top, coloured by height.
static func _vessel(k: MeshKit, m: String, xf: Transform3D, prof: Array, col: Callable, segs := 28) -> void:
	_lathe(k, m, xf, prof, segs, func(p: Vector3, _a: float, _t: float) -> Color: return col.call(p.y))

## A small round screw head.
static func _screw(k: MeshKit, xf: Transform3D, p: Vector3, n: Vector3, rad: float, col: Color) -> void:
	_cyl(k, "im:metal@0.35", xf, p - n * 0.0004, p + n * rad * 0.5, rad, rad * 0.8, 8, col)

# --- Boards and chips -------------------------------------------------------------------

## Salvaged circuitry: a scuffed green board pulled from a machine, a big chip in the
## middle (its die window painted green), headers and loose wires torn out at two corners.
static func _circuitry(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.5) * FLAT, Vector3(0, 0.0016, 0))
	_board(k, r, xf, 0.11, 0.085, Color(0.14, 0.3, 0.13), 22)
	_qfp(k, xf * _at(0.004, 0.0, 0), 0.03, 0.003, BLACK, 9, Color(0.75, 0.75, 0.75))
	k.box("own:plastic", xf * _at(0.004, 0.0, 0.0031), Vector3(0.015, 0.015, 0.0004), Color(0.3, 0.55, 0.2))
	_soic(k, xf * _at(0.03, 0.01, 0), 0.008, 0.013, 4)
	_soic(k, xf * Transform3D(Basis(Z, PI * 0.5), Vector3(0.012, -0.027, 0)), 0.008, 0.012, 4)
	# Two white pin headers, the wires still in them.
	for h: Array in [[Vector3(0.01, 0.034, 0), 0.0], [Vector3(-0.024, -0.03, 0), 0.0]]:
		var p: Vector3 = h[0]
		k.bevel_box("own:plastic", xf * _at(p.x, p.y, 0.003), Vector3(0.022, 0.006, 0.006), 0.0006, Color(0.88, 0.86, 0.8))
		for i in 6:
			ItemModels._disc(k, "own:plastic", xf, Vector3(p.x - 0.009 + i * 0.0036, p.y, 0.0061), Z, 0.0009, 6, BLACK)
	k.box("own:plastic", xf * _at(-0.032, 0.026, 0.002), Vector3(0.008, 0.006, 0.004), Color(0.25, 0.45, 0.85))
	_smd(k, r, xf, 0.11, 0.085, 22, [Rect2(-0.012, -0.016, 0.034, 0.032), Rect2(0.026, 0.002, 0.009, 0.016), Rect2(-0.004, 0.03, 0.03, 0.01), Rect2(-0.036, -0.034, 0.026, 0.01)])
	var wc := [Color(0.75, 0.15, 0.1), Color(0.2, 0.35, 0.8), Color(0.85, 0.85, 0.85)]
	for i in 3:
		var o := i * 0.0036
		_wire(k, xf, PackedVector3Array([Vector3(0.004 + o, 0.035, 0.006), Vector3(0.006 + o, 0.045, 0.012), Vector3(0.016 + o * 2.0, 0.058, 0.01), Vector3(0.026 + o * 3.0, 0.064, 0.004)]), 0.0011, wc[i])
		_wire(k, xf, PackedVector3Array([Vector3(-0.03 + o, -0.031, 0.006), Vector3(-0.034 + o, -0.042, 0.01), Vector3(-0.05 + o, -0.05, 0.008), Vector3(-0.062 + o, -0.052 + o * 2.0, 0.003)]), 0.0011, wc[(i + 1) % 3])

## A loose square chip: black epoxy body, rows of gold gull-wing legs on all four sides,
## the pin-one dimple in a corner.
static func _microchip(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.6) * FLAT, Vector3.ZERO)
	_qfp(k, xf, 0.036, 0.004, Color(0.09, 0.09, 0.1), 12, GOLD, 0.004)
	ItemModels._disc(k, "own:plastic", xf, Vector3(-0.013, 0.013, 0.00405), Z, 0.0015, 10, Color(0.03, 0.03, 0.03))
	ItemModels._disc(k, "own:plastic", xf, Vector3(0.012, -0.012, 0.00405), Z, 0.001, 10, Color(0.04, 0.04, 0.04))

## A quantum chip: a black package with gold legs and a gold-framed window of violet glass
## over a gold lattice (tinted glass, not light).
static func _quantum_chip(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.6) * FLAT, Vector3.ZERO)
	var w := 0.042
	var th := 0.0045
	_qfp(k, xf, w, th, Color(0.08, 0.08, 0.09), 14, GOLD, 0.0045)
	var fr := w * 0.62
	var hole := _rrect(fr - 0.004, fr - 0.004, 0.0008)
	_ext(k, "im:metal@0.3", xf * _at(0, 0, th + 0.0004), _rrect(fr, fr, 0.0012), [hole], 0.0008, GOLD)
	k.box("own:plastic", xf * _at(0, 0, th + 0.0001), Vector3(fr - 0.004, fr - 0.004, 0.0002), Color(0.2, 0.08, 0.38))
	var g := fr * 0.5 - 0.002
	for i in 5:
		var o := (i - 2) * g * 0.4
		for d: float in [1.0, -1.0]:
			_trace(k, xf * _at(0, 0, th + 0.0002, Basis(Z, PI * 0.25 * d)), PackedVector2Array([Vector2(-g * 1.35 + absf(o), o), Vector2(g * 1.35 - absf(o), o)]), 0.0004, Color(0.75, 0.55, 0.95))
	_trace(k, xf * _at(0, 0, th + 0.00025), PackedVector2Array([Vector2(-g, 0), Vector2(g, 0)]), 0.0005, Color(0.85, 0.7, 1.0))
	_trace(k, xf * _at(0, 0, th + 0.00025), PackedVector2Array([Vector2(0, -g), Vector2(0, g)]), 0.0005, Color(0.85, 0.7, 1.0))
	k.box("own:tint", xf * _at(0, 0, th + 0.0006), Vector3(fr - 0.004, fr - 0.004, 0.0006), Color(0.5, 0.3, 0.95, 0.55))

## A processor: a green fibre substrate edged with gold pads, the brushed steel heat
## spreader stepped up in the middle.
static func _processor(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.6) * FLAT, Vector3.ZERO)
	var w := 0.045
	k.bevel_box("own:pcb", xf * _at(0, 0, 0.0008), Vector3(w, w, 0.0016), 0.0004, Color(0.12, 0.3, 0.16))
	for side in 4:
		var b := Basis(Z, side * PI * 0.5)
		for i in 22:
			var o := (i - 10.5) * w * 0.042
			k.box("im:metal@0.3", xf * Transform3D(b, b * Vector3(o, w * 0.5 - 0.0018, 0.0017)), Vector3(0.0009, 0.0026, 0.0002), GOLD)
	k.bevel_box("im:metal@0.3", xf * _at(0, 0, 0.0021), Vector3(0.035, 0.035, 0.001), 0.0004, Color(0.6, 0.6, 0.6))
	k.bevel_box("im:metal_rolled", xf * _at(0, 0, 0.0034), Vector3(0.032, 0.032, 0.0026), 0.0011, Color(0.78, 0.77, 0.74))
	for i in 6:
		var p := Vector2(r.randf_range(-0.019, 0.019), -0.0195 if i % 2 == 0 else 0.0195)
		k.box("own:plastic", xf * _at(p.x, p.y, 0.0019), Vector3(0.0016, 0.0009, 0.0007), Color(0.6, 0.5, 0.35))

## A circuit board: a clean green board with two black chips, a row of parts, a dark edge
## connector, a round can capacitor and plated mounting holes.
static func _circuit_board(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.5) * FLAT, Vector3(0, 0.0016, 0))
	var w := 0.1
	var h := 0.08
	_board(k, r, xf, w, h, Color(0.08, 0.27, 0.12), 34)
	_qfp(k, xf * _at(0.006, 0.014, 0), 0.016, 0.0022, BLACK, 6, Color(0.8, 0.8, 0.82))
	_qfp(k, xf * _at(0.004, -0.016, 0), 0.016, 0.0022, BLACK, 6, Color(0.8, 0.8, 0.82))
	k.box("own:plastic", xf * _at(-0.044, 0.004, 0.0014), Vector3(0.004, 0.05, 0.0028), Color(0.1, 0.1, 0.1))
	_cyl(k, "im:metal@0.35", xf, Vector3(-0.022, -0.028, 0), Vector3(-0.022, -0.028, 0.006), 0.0035, 0.0035, 12, Color(0.75, 0.76, 0.78))
	ItemModels._disc(k, "own:plastic", xf, Vector3(-0.022, -0.028, 0.0061), Z, 0.0025, 10, Color(0.55, 0.55, 0.58))
	_smd(k, r, xf, w, h, 30, [Rect2(-0.006, 0.002, 0.026, 0.026), Rect2(-0.008, -0.028, 0.026, 0.026), Rect2(-0.048, -0.022, 0.008, 0.052), Rect2(-0.028, -0.034, 0.012, 0.012)])

# --- Cards ------------------------------------------------------------------------------

## A keycard: a stiff rounded card with a lanyard slot at the top, scuffed along its edges
## where it rides in a pocket.
static func _card(k: MeshKit, r: RandomNumberGenerator, m: String, col: Color) -> Vector3:
	var w := 0.054
	var h := 0.086
	var th := 0.0028
	var slot := _rrect(0.016, 0.0042, 0.0021, Vector2(0, h * 0.5 - 0.0075), 4)
	_ext_bevel(k, m, _at(0, h * 0.5, 0), _rrect(w, h, 0.0045, Vector2.ZERO, 5), [slot], th, 0.0007, col)
	for i in 7:
		var a := Vector2(r.randf_range(-w * 0.4, w * 0.4), r.randf_range(-h * 0.4, h * 0.35))
		var d := Vector2.from_angle(r.randf_range(-0.9, 0.9) + PI * 0.25) * r.randf_range(0.006, 0.02)
		_trace(k, _at(0, h * 0.5, th * 0.5), PackedVector2Array([a, a + d]), 0.00025, col.lightened(0.18), 0.00005)
	return Vector3(0, 0.02, 0)

static func _keycard_red(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Vector3:
	return _card(k, r, "im:paint", Color(0.5, 0.06, 0.05))

static func _keycard_blue(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Vector3:
	return _card(k, r, "im:paint", Color(0.05, 0.11, 0.34))

static func _keycard_gold(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Vector3:
	return _card(k, r, "im:metal@0.4", Color(0.9, 0.66, 0.28))

## A credit chip: a thick square tablet of brushed steel, chamfered, with gold contact
## inlays laid in angular bands and a dark triangular key.
static func _credit_chip(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var w := 0.055
	var th := 0.004
	var xf := Transform3D(Basis(Vector3.UP, 0.75) * FLAT, Vector3(0, 0.002, 0))
	_ext_bevel(k, "im:metal_rolled", xf, _rrect(w, w, 0.004), [], th, 0.0012, Color(0.6, 0.61, 0.63))
	var f := xf * _at(0, 0, th * 0.5 + 0.0002)
	var gold := Color(0.85, 0.62, 0.26)
	var shapes := [
		[Vector2(-0.022, 0.016), Vector2(-0.004, 0.016), Vector2(-0.008, 0.011), Vector2(-0.022, 0.011)],
		[Vector2(-0.022, 0.008), Vector2(-0.01, 0.008), Vector2(-0.014, 0.003), Vector2(-0.022, 0.003)],
		[Vector2(0.0, 0.022), Vector2(0.012, 0.022), Vector2(0.004, 0.006), Vector2(-0.006, 0.006)],
		[Vector2(0.014, 0.022), Vector2(0.022, 0.022), Vector2(0.022, -0.012), Vector2(0.008, 0.004)],
		[Vector2(-0.022, -0.006), Vector2(-0.008, -0.006), Vector2(-0.008, -0.01), Vector2(-0.022, -0.01)],
		[Vector2(-0.022, -0.014), Vector2(0.02, -0.014), Vector2(0.02, -0.018), Vector2(-0.022, -0.018)],
	]
	for s: Array in shapes:
		_ext(k, "im:metal@0.35", f, PackedVector2Array(s), [], 0.0004, gold)
	_ext(k, "im:metal@0.6", f, PackedVector2Array([Vector2(-0.006, 0.002), Vector2(0.006, 0.002), Vector2(0.0, -0.009)]), [], 0.0003, Color(0.18, 0.18, 0.2))
	for i in 4:
		_trace(k, f, PackedVector2Array([Vector2(-0.02 + i * 0.008, -0.0215), Vector2(-0.016 + i * 0.008, -0.0215)]), 0.0012, gold)

# --- Power ------------------------------------------------------------------------------

## A power cell: a steel cylinder with dark grooved end caps and a terminal nub, a
## framed cyan glass window down one side above a row of gauge cells.
static func _power_cell(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var R := 0.028
	var L := 0.12
	var xf := _at(0, 0, 0)
	var dark := Color(0.34, 0.36, 0.4)
	var col := func(y: float) -> Color:
		return dark if y < 0.022 or y > L - 0.022 else Color(0.72, 0.74, 0.77)
	_vessel(k, "im:metal@0.3", xf, [Vector2(0, 0), Vector2(R - 0.005, 0), Vector2(R, 0.005), Vector2(R, 0.02), Vector2(R - 0.0015, 0.0215), Vector2(R - 0.0015, 0.0235), Vector2(R, 0.025),
		Vector2(R, L - 0.025), Vector2(R - 0.0015, L - 0.0235), Vector2(R - 0.0015, L - 0.0215), Vector2(R, L - 0.02), Vector2(R, L - 0.005), Vector2(R - 0.005, L), Vector2(0, L)], col)
	_cyl(k, "im:metal@0.25", xf, Vector3(0, L - 0.001, 0), Vector3(0, L + 0.006, 0), 0.011, 0.01, 18, Color(0.6, 0.62, 0.65))
	ItemModels._torus(k, "im:metal@0.4", _at(0, L - 0.0001, 0), 0.018, 0.0012, 24, 4, dark.darkened(0.3))
	ItemModels._torus(k, "im:metal@0.4", _at(0, 0.0001, 0), 0.016, 0.0012, 24, 4, dark.darkened(0.3))
	for mid: float in [PI * 0.5, PI * 1.5, 0.0, PI]:
		_arc_panel(k, "im:metal@0.35", xf, R + 0.0016, 0.03, 0.092, mid, 0.42, dark)
		_arc_panel(k, "own:tint", xf, R + 0.0024, 0.054, 0.088, mid, 0.24, Color(0.2, 0.75, 0.82, 0.9))
		for i in 7:
			var yy := 0.034 + i * 0.0026
			_arc_panel(k, "own:tint", xf, R + 0.0024, yy, yy + 0.0018, mid, 0.2, Color(0.15, 0.65, 0.75, 0.92))
	return Vector3(0, L * 0.5, 0)

## A data core: a cyan crystal prism held in a dark steel cage of four clamped bars
## between a heavy base and a ring collar, a faint glass sleeve round it.
static func _data_core(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var dark := Color(0.42, 0.48, 0.52)
	var xf := _at(0, 0, 0)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0), Vector2(0.04, 0), Vector2(0.046, 0.006), Vector2(0.046, 0.016), Vector2(0.04, 0.022), Vector2(0.03, 0.024), Vector2(0, 0.024)], func(_y: float) -> Color: return dark)
	_lathe(k, "im:metal@0.35", xf, [Vector2(0.026, 0.13), Vector2(0.038, 0.13), Vector2(0.041, 0.135), Vector2(0.041, 0.148), Vector2(0.036, 0.152), Vector2(0.026, 0.152), Vector2(0.026, 0.13)], 28, dark)
	ItemModels._torus(k, "im:metal@0.3", _at(0, 0.141, 0), 0.0415, 0.0018, 28, 5, Color(0.6, 0.66, 0.7))
	var cc := Color(0.15, 0.75, 0.85, 0.92)
	k.crystal("im:crystal:data_core", _at(0, 0.077, 0), 0.022, 0.055, 6, 0.3, cc)
	k.crystal("im:crystal:data_core", _at(0, 0.077, 0, Basis(Vector3.RIGHT, PI)), 0.022, 0.05, 6, 0.3, cc)
	_arc_panel(k, "im:metal@0.5", xf, 0.034, 0.024, 0.13, -PI * 0.5, PI * 0.5, Color(0.05, 0.14, 0.18))
	for i in 4:
		var a := PI * 0.5 + i * PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		var b := Basis(Vector3.UP, -a + PI * 0.5)
		k.bevel_box("im:metal@0.35", Transform3D(b, d * 0.038 + Vector3(0, 0.077, 0)), Vector3(0.014, 0.11, 0.008), 0.002, dark)
		k.bevel_box("im:metal@0.35", Transform3D(b, d * 0.041 + Vector3(0, 0.077, 0)), Vector3(0.016, 0.014, 0.006), 0.0015, dark.lightened(0.15))
		k.box("im:metal@0.35", Transform3D(b, d * 0.0405 + Vector3(0, 0.1, 0)), Vector3(0.005, 0.03, 0.004), Color(0.55, 0.62, 0.66))

## A small battery pack: a ribbed charcoal case with orange corner guards and an orange
## carry handle across the top.
static func _battery_small(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var w := 0.14
	var h := 0.11
	var d := 0.08
	var body := Color(0.2, 0.21, 0.22)
	k.bevel_box("im:composite", _at(0, h * 0.5, 0), Vector3(w, h, d), 0.006, body)
	k.bevel_box("im:composite", _at(0, h - 0.004, 0), Vector3(w + 0.004, 0.012, d + 0.004), 0.003, body.darkened(0.2))
	for i in 6:
		var x := -0.05 + i * 0.02
		for s: float in [1.0, -1.0]:
			k.bevel_box("im:composite", _at(x, h * 0.48, s * (d * 0.5 + 0.002)), Vector3(0.008, h * 0.7, 0.005), 0.0015, body.lightened(0.06))
	for sx: float in [-1.0, 1.0]:
		k.bevel_box("im:composite", _at(sx * (w * 0.5 + 0.002), h * 0.48, 0), Vector3(0.005, h * 0.7, 0.05), 0.0015, body.lightened(0.06))
		for sy: float in [0.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := Vector3(sx * (w * 0.5 - 0.008), 0.009 + sy * (h - 0.02), sz * (d * 0.5 - 0.008))
				k.bevel_box("im:paint", _at(c.x, c.y, c.z), Vector3(0.022, 0.024, 0.022), 0.004, ORANGE)
				ItemModels._disc(k, "im:metal@0.4", _at(0, 0, 0), c + Vector3(0, 0, sz * 0.0112), Vector3(0, 0, sz), 0.003, 8, Color(0.3, 0.3, 0.32))
	for sx: float in [-1.0, 1.0]:
		k.bevel_box("im:paint", _at(sx * 0.035, h + 0.01, 0), Vector3(0.012, 0.022, 0.018), 0.003, ORANGE)
	k.bevel_box("im:paint", _at(0, h + 0.022, 0), Vector3(0.082, 0.01, 0.018), 0.004, ORANGE)
	k.bevel_box("im:rubber", _at(0, h + 0.0225, 0), Vector3(0.05, 0.011, 0.019), 0.004, Color(0.12, 0.12, 0.12))
	return Vector3(0, h + 0.02, 0)

## A fusion core: a glass capsule round a steel core rod, capped and banded in brass,
## a ring eye at the top to lift it by.
static func _fusion_core(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var brass := Color(0.7, 0.52, 0.24)
	var xf := _at(0, 0, 0)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0), Vector2(0.026, 0), Vector2(0.031, 0.004), Vector2(0.031, 0.014), Vector2(0.034, 0.016), Vector2(0.034, 0.03), Vector2(0.03, 0.034), Vector2(0, 0.034)],
		func(y: float) -> Color: return Color(0.6, 0.6, 0.62) if y < 0.014 else brass)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0.116), Vector2(0.03, 0.116), Vector2(0.034, 0.12), Vector2(0.034, 0.134), Vector2(0.029, 0.142), Vector2(0.02, 0.146), Vector2(0.02, 0.152), Vector2(0, 0.152)],
		func(y: float) -> Color: return brass if y < 0.142 else brass.darkened(0.15))
	ItemModels._torus(k, "im:metal@0.3", _at(0, 0.155, 0), 0.012, 0.0035, 20, 6, brass)
	ItemModels._disc(k, "im:metal@0.6", xf, Vector3(0, 0.1522, 0), Vector3.UP, 0.009, 14, Color(0.15, 0.13, 0.1))
	_cyl(k, "im:glass", xf, Vector3(0, 0.034, 0), Vector3(0, 0.116, 0), 0.029, 0.029, 28, Color(0.9, 0.95, 1.0, 0.18), false)
	_vessel(k, "im:metal@0.25", xf, [Vector2(0, 0.034), Vector2(0.014, 0.034), Vector2(0.014, 0.116), Vector2(0, 0.116)], func(y: float) -> Color: return Color(0.72, 0.73, 0.75) if int(y * 160.0) % 3 else Color(0.5, 0.5, 0.52))
	ItemModels._torus(k, "im:metal@0.3", _at(0, 0.075, 0), 0.03, 0.003, 28, 6, brass)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var b := Basis(Vector3.UP, -a + PI * 0.5)
		for y: float in [0.04, 0.075, 0.11]:
			k.bevel_box("im:metal@0.35", Transform3D(b, Vector3(cos(a), 0, sin(a)) * 0.034 + Vector3(0, y, 0)), Vector3(0.014, 0.018, 0.007), 0.0015, brass.darkened(0.1))
	return Vector3(0, 0.075, 0)

## A fuel rod: a long capsule of yellow-green glass round a stack of fuel pellets, steel
## end caps and bands, steel guide bars down its length.
static func _fuel_rod(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var L := 0.28
	var R := 0.032
	var steel := Color(0.68, 0.69, 0.71)
	var xf := _at(0, 0, 0)
	for e: float in [0.0, 1.0]:
		var b := Basis.IDENTITY if e == 0.0 else Basis(Vector3.RIGHT, PI)
		var o := Transform3D(b, Vector3(0, L * e, 0))
		_vessel(k, "im:metal@0.3", o, [Vector2(0, 0), Vector2(R - 0.004, 0), Vector2(R, 0.004), Vector2(R, 0.03), Vector2(R + 0.002, 0.032), Vector2(R + 0.002, 0.04), Vector2(R - 0.002, 0.042), Vector2(0, 0.042)], func(_y: float) -> Color: return steel)
		ItemModels._disc(k, "im:metal@0.6", o, Vector3(0, -0.0002, 0), Vector3.DOWN, 0.004, 10, Color(0.1, 0.1, 0.1))
		ItemModels._torus(k, "im:metal@0.5", o, 0.012, 0.0008, 18, 4, steel.darkened(0.3))
	_cyl(k, "im:glass", xf, Vector3(0, 0.042, 0), Vector3(0, L - 0.042, 0), R - 0.001, R - 0.001, 24, Color(0.55, 0.6, 0.2, 0.5), false)
	for i in 9:
		var y := 0.045 + i * 0.0235
		_cyl(k, "own:tint", xf, Vector3(0, y, 0), Vector3(0, y + 0.022, 0), R - 0.006, R - 0.006, 18, Color(0.48, 0.5, 0.12, 0.96))
	for y: float in [0.11, 0.19]:
		_cyl(k, "im:metal@0.3", xf, Vector3(0, y - 0.004, 0), Vector3(0, y + 0.004, 0), R + 0.0015, R + 0.0015, 24, steel)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var d := Vector3(cos(a), 0, sin(a)) * (R + 0.002)
		_cyl(k, "im:metal@0.3", xf, d + Vector3(0, 0.04, 0), d + Vector3(0, L - 0.04, 0), 0.0022, 0.0022, 6, steel)
	return Vector3(0, L * 0.5, 0)

## A coolant canister: blue coolant behind a glass cylinder between a dark ribbed steel
## base and cap, guard bars outside and a pipe looping off the top.
static func _coolant(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Vector3:
	var dark := Color(0.26, 0.27, 0.3)
	var xf := _at(0, 0, 0)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0), Vector2(0.046, 0), Vector2(0.05, 0.004), Vector2(0.05, 0.012), Vector2(0.054, 0.014), Vector2(0.054, 0.024), Vector2(0.05, 0.026), Vector2(0.05, 0.036), Vector2(0, 0.036)], func(_y: float) -> Color: return dark)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0.15), Vector2(0.05, 0.15), Vector2(0.05, 0.16), Vector2(0.054, 0.162), Vector2(0.054, 0.172), Vector2(0.046, 0.18), Vector2(0.03, 0.184), Vector2(0.02, 0.19), Vector2(0, 0.19)], func(_y: float) -> Color: return dark)
	_cyl(k, "own:tint", xf, Vector3(0, 0.036, 0), Vector3(0, 0.15, 0), 0.04, 0.04, 28, Color(0.08, 0.4, 0.95, 0.96))
	_cyl(k, "im:glass", xf, Vector3(0, 0.036, 0), Vector3(0, 0.15, 0), 0.045, 0.045, 28, Color(0.75, 0.88, 1.0, 0.2), false)
	for i in 14:
		var a := r.randf() * PI + PI * 0.1
		var p := Vector3(cos(a) * 0.041, r.randf_range(0.05, 0.14), sin(a) * 0.041)
		k.sphere("im:glass", _at(p.x, p.y, p.z), r.randf_range(0.0015, 0.003), 4, 6, 0.0, 1.0, Color(0.7, 0.9, 1.0, 0.5))
	for a: float in [PI * 0.5 - PI * 0.62, PI * 0.5 + PI * 0.62, PI * 1.5]:
		var d := Vector3(cos(a), 0, sin(a)) * 0.05
		k.bevel_box("im:metal@0.35", Transform3D(Basis(Vector3.UP, -a), d + Vector3(0, 0.093, 0)), Vector3(0.008, 0.12, 0.012), 0.002, dark.darkened(0.15))
	_cyl(k, "im:metal@0.3", xf, Vector3(0, 0.188, 0), Vector3(0, 0.198, 0), 0.008, 0.008, 12, dark)
	var pipe := _curve(PackedVector3Array([Vector3(0, 0.195, 0), Vector3(0, 0.215, 0), Vector3(0.025, 0.222, 0), Vector3(0.05, 0.21, 0), Vector3(0.056, 0.185, 0), Vector3(0.056, 0.17, 0)]))
	var radii := PackedFloat32Array()
	radii.resize(pipe.size())
	radii.fill(0.0045)
	ItemModels._tube(k, "im:metal@0.35", xf, pipe, radii, 8, dark.lightened(0.1))
	return Vector3(0, 0.09, 0)

# --- Gadgets ----------------------------------------------------------------------------

## A handheld scanner: a pistol grip under a gunmetal body that swells to a big square
## sensor head, its face dark glass in a rubber bezel, orange trigger and trim.
static func _scanner(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var T := Transform3D(Basis(Vector3.UP, -0.9), Vector3.ZERO) ## the sensor face turned to the left, as painted
	var gm := Color(0.27, 0.28, 0.3)
	var silver := Color(0.62, 0.63, 0.65)
	# Sensor head, its face on +Z.
	k.bevel_box("im:composite", T * _at(0, 0.12, -0.025), Vector3(0.1, 0.09, 0.05), 0.01, gm)
	_ext_bevel(k, "im:rubber", T * _at(0, 0.12, 0.002), _rrect(0.1, 0.09, 0.016), [], 0.008, 0.002, Color(0.09, 0.09, 0.1))
	_ext(k, "im:visor", T * _at(0, 0.12, 0.0062), _rrect(0.08, 0.07, 0.01), [], 0.002, Color(0.04, 0.05, 0.06))
	# Body behind, its top in silver panels.
	k.bevel_box("im:composite", T * _at(0, 0.122, -0.09), Vector3(0.062, 0.062, 0.09), 0.01, gm)
	k.bevel_box("im:metal@0.35", T * _at(0, 0.152, -0.085), Vector3(0.05, 0.006, 0.075), 0.002, silver)
	for s: float in [-1.0, 1.0]:
		k.bevel_box("im:metal@0.35", T * _at(s * 0.0315, 0.125, -0.092), Vector3(0.004, 0.034, 0.06), 0.0015, silver)
		k.box("im:metal@0.5", T * _at(s * 0.034, 0.127, -0.095), Vector3(0.002, 0.012, 0.035), Color(0.2, 0.2, 0.2))
		k.bevel_box("im:paint", T * _at(s * 0.0505, 0.12, -0.012), Vector3(0.004, 0.06, 0.008), 0.0015, ORANGE)
	_cyl(k, "im:composite", T * _at(0, 0, 0), Vector3(0, 0.122, -0.134), Vector3(0, 0.122, -0.15), 0.026, 0.022, 20, gm.darkened(0.2))
	ItemModels._torus(k, "im:paint", T * _at(0, 0.122, -0.137, Basis(Vector3.RIGHT, PI * 0.5)), 0.026, 0.002, 20, 4, ORANGE)
	# Grip raked back, finger grooves, the trigger in front.
	var gb := Basis(Vector3.RIGHT, -0.25)
	k.bevel_box("im:composite", T * Transform3D(gb, Vector3(0, 0.05, -0.07)), Vector3(0.036, 0.1, 0.042), 0.01, gm)
	k.bevel_box("im:rubber", T * Transform3D(gb, Vector3(0, 0.048, -0.0905)), Vector3(0.03, 0.08, 0.008), 0.003, Color(0.12, 0.12, 0.13))
	for i in 3:
		k.box("im:rubber", T * Transform3D(gb, gb * Vector3(0, -0.02 + i * 0.02, 0.021) + Vector3(0, 0.05, -0.07)), Vector3(0.034, 0.004, 0.004), Color(0.1, 0.1, 0.1))
	k.bevel_box("im:paint", T * _at(0, 0.082, -0.038, Basis(Vector3.RIGHT, 0.3)), Vector3(0.012, 0.022, 0.01), 0.003, ORANGE)
	return T * Vector3(0, 0.05, -0.07)

## A scout drone: a white and dark body with a camera eye under its nose, four ducted
## rotors on arms, each duct banded orange, three-bladed props and a whip antenna.
static func _drone_scout(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var white := Color(0.64, 0.65, 0.67)
	var dark := Color(0.16, 0.16, 0.17)
	k.bevel_box("im:composite", _at(0, 0.045, 0), Vector3(0.1, 0.045, 0.13), 0.012, dark)
	k.bevel_box("im:composite", _at(0, 0.07, -0.005), Vector3(0.09, 0.02, 0.115), 0.007, white)
	k.bevel_box("im:composite", _at(0, 0.06, 0.055), Vector3(0.065, 0.032, 0.035), 0.006, white)
	for s: float in [-1.0, 1.0]:
		_ext(k, "im:visor", _at(s * 0.015, 0.063, 0.0732), _rrect(0.014, 0.01, 0.003), [], 0.002, Color(0.04, 0.04, 0.05))
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0.03, 0.04), Vector3(0, 0.03, 0.07), 0.02, 0.019, 20, Color(0.1, 0.1, 0.11))
	ItemModels._torus(k, "im:paint", _at(0, 0.03, 0.07, Basis(Vector3.RIGHT, PI * 0.5)), 0.018, 0.0018, 20, 4, Color(0.7, 0.12, 0.08))
	_lens(k, _at(0, 0.03, 0.07, Basis(Vector3.RIGHT, PI * 0.5)), 0.015, 0.005, Color(0.2, 0.28, 0.4, 0.85), Color(0.05, 0.06, 0.1, 0.9))
	_cyl(k, "im:rubber", _at(0, 0, 0), Vector3(0, 0.08, -0.03), Vector3(0, 0.14, -0.034), 0.0018, 0.0012, 6, BLACK)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * 0.11, 0.05, sz * 0.08)
			_cyl(k, "im:composite", _at(0, 0, 0), Vector3(sx * 0.035, 0.05, sz * 0.035), c - Vector3(sx, 0, sz * 0.7).normalized() * 0.05, 0.009, 0.008, 10, dark)
			var ro := _at(c.x, c.y - 0.011, c.z)
			_lathe(k, "im:composite", ro, [Vector2(0.046, 0.0), Vector2(0.052, 0.0), Vector2(0.054, 0.004), Vector2(0.054, 0.018), Vector2(0.052, 0.022), Vector2(0.046, 0.022), Vector2(0.046, 0.0)], 32, dark)
			for q in 4:
				_arc_panel(k, "im:paint", ro, 0.0545, 0.006, 0.016, q * PI * 0.5 + PI * 0.25, 0.32, ORANGE)
			_cyl(k, "im:metal@0.35", ro, Vector3(0, 0.004, 0), Vector3(0, 0.016, 0), 0.007, 0.006, 12, Color(0.4, 0.4, 0.42))
			for q in 2:
				var b := Basis(Vector3.UP, q * PI * 0.5)
				k.box("im:composite", ro * Transform3D(b, Vector3(0, 0.006, 0)), Vector3(0.094, 0.003, 0.004), dark.darkened(0.2))
			for q in 3:
				var b := Basis(Vector3.UP, q * TAU / 3.0 + 0.4) * Basis(Vector3.RIGHT, 0.25)
				k.box("own:plastic", ro * Transform3D(b, b * Vector3(0.022, 0, 0) + Vector3(0, 0.018, 0)), Vector3(0.04, 0.0015, 0.009), Color(0.1, 0.1, 0.1))
			_cyl(k, "im:metal@0.3", ro, Vector3(0, 0.016, 0), Vector3(0, 0.021, 0), 0.004, 0.003, 10, GOLD)

## A deployable turret: a gun head of grey plate and dark rails with a glass sight in its
## muzzle, on a pan unit atop a folding tripod with jointed legs and pads.
static func _turret_deploy(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var silver := Color(0.6, 0.61, 0.63)
	var dark := Color(0.17, 0.17, 0.18)
	var hub := Vector3(0, 0.2, 0)
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0.08, 0), hub, 0.012, 0.012, 12, dark)
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0.05, 0), Vector3(0, 0.08, 0), 0.014, 0.012, 12, dark.lightened(0.1))
	k.bevel_box("im:metal@0.4", _at(hub.x, hub.y, hub.z), Vector3(0.05, 0.03, 0.05), 0.006, dark)
	for i in 3:
		var a := PI * 0.5 + i * TAU / 3.0 + PI / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		var knee := hub + d * 0.075 + Vector3(0, -0.075, 0)
		var foot := d * 0.13 + Vector3(0, 0.008, 0)
		_cyl(k, "im:metal@0.4", _at(0, 0, 0), hub + d * 0.02, knee, 0.016, 0.014, 8, dark)
		k.bevel_box("im:metal@0.4", Transform3D(_along(knee - hub), knee), Vector3(0.03, 0.034, 0.03), 0.005, dark.lightened(0.12))
		_cyl(k, "im:metal@0.4", _at(0, 0, 0), knee, foot, 0.012, 0.01, 8, dark.lightened(0.05))
		k.bevel_box("im:rubber", _at(foot.x, 0.004, foot.z, Basis(Vector3.UP, -a)), Vector3(0.03, 0.008, 0.022), 0.003, BLACK)
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), Vector3(0, 0.215, 0), Vector3(0, 0.245, 0), 0.032, 0.03, 20, dark.lightened(0.1))
	var h := _at(0, 0.285, 0.01)
	k.bevel_box("im:metal@0.35", h, Vector3(0.1, 0.085, 0.19), 0.012, silver)
	k.bevel_box("im:metal@0.4", h * _at(0, -0.032, 0), Vector3(0.104, 0.024, 0.18), 0.004, dark)
	k.bevel_box("im:metal@0.4", h * _at(0, 0.047, -0.01), Vector3(0.03, 0.014, 0.14), 0.003, dark)
	for s: float in [-1.0, 1.0]:
		k.box("im:metal@0.5", h * _at(s * 0.0505, 0.008, 0.0), Vector3(0.002, 0.024, 0.12), dark)
	_cyl(k, "im:metal@0.4", h, Vector3(0, 0.002, 0.09), Vector3(0, 0.002, 0.105), 0.03, 0.03, 22, dark)
	_lens(k, h * _at(0, 0.002, 0.105, Basis(Vector3.RIGHT, PI * 0.5)), 0.025, 0.006, Color(0.25, 0.35, 0.45, 0.85), Color(0.05, 0.07, 0.1, 0.9))
	return Vector3(0, 0.15, 0)

## A personal shield generator: a thick armoured ring of grey plates with orange-capped
## emitter blocks round its rim, stood on a splayed cradle.
static func _shield_gen(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var gm := Color(0.4, 0.41, 0.43)
	var c := Vector3(0, 0.15, 0)
	var ring := _at(c.x, c.y, c.z, Basis(Vector3.RIGHT, PI * 0.5))
	var ri := 0.07
	var ro := 0.108
	_lathe(k, "im:metal@0.4", ring * _at(0, -0.024, 0), [Vector2(ri, 0), Vector2(ro, 0), Vector2(ro + 0.004, 0.006), Vector2(ro + 0.004, 0.042), Vector2(ro, 0.048), Vector2(ri, 0.048), Vector2(ri - 0.003, 0.042), Vector2(ri - 0.003, 0.006), Vector2(ri, 0)], 48, gm)
	_lathe(k, "im:metal@0.3", ring * _at(0, -0.026, 0), [Vector2(ri - 0.002, 0.0), Vector2(ri - 0.002, 0.052)], 48, Color(0.66, 0.67, 0.7))
	for i in 8:
		var a := i * TAU / 8.0 + PI / 8.0
		var mid := Vector2(cos(a), sin(a)) * (ri + ro) * 0.5
		var b := Basis(Z, a)
		k.bevel_box("im:metal@0.35", Transform3D(Basis.IDENTITY, c) * Transform3D(b, Vector3(mid.x, mid.y, 0.026)), Vector3(0.03, 0.04, 0.008), 0.002, Color(0.66, 0.67, 0.69) if i % 2 else ORANGE)
	for i in 6:
		var a := i * TAU / 6.0
		var b := Basis(Z, a)
		var o := Transform3D(Basis.IDENTITY, c) * Transform3D(b, b * Vector3(ro + 0.008, 0, 0))
		k.bevel_box("im:metal@0.4", o, Vector3(0.016, 0.03, 0.05), 0.004, gm.darkened(0.2))
		k.bevel_box("im:paint", o * _at(0.004, 0, 0.018), Vector3(0.014, 0.022, 0.016), 0.003, ORANGE)
	# The cradle: a block under the ring and three splayed feet.
	k.bevel_box("im:metal@0.4", _at(0, 0.03, 0), Vector3(0.07, 0.03, 0.06), 0.006, gm)
	for a: float in [0.6, PI - 0.6, -PI * 0.5]:
		var d := Vector3(cos(a), 0, sin(a))
		var foot := d * 0.09 + Vector3(0, 0.012, 0)
		k.bevel_box("im:metal@0.4", Transform3D(_along(foot - Vector3(0, 0.04, 0)).rotated(Vector3.UP, 0.0), (foot + Vector3(0, 0.035, 0)) * 0.5 + d * 0.0), Vector3(0.026, 0.09, 0.02), 0.004, gm)
		k.bevel_box("im:rubber", _at(foot.x, 0.008, foot.z, Basis(Vector3.UP, -a)), Vector3(0.04, 0.016, 0.03), 0.004, BLACK)
		k.bevel_box("im:paint", _at(foot.x * 0.75, 0.03, foot.z * 0.75, Basis(Vector3.UP, -a)), Vector3(0.012, 0.012, 0.024), 0.002, ORANGE)
	return Vector3(0, 0.03, 0)

## A navigation beacon: an olive steel drum on a black footed base, banded, a black cap
## with an orange collar and a tall rubber whip antenna, an orange grab bar at the side.
static func _beacon_nav(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var olive := Color(0.48, 0.48, 0.38)
	var xf := _at(0, 0, 0)
	_vessel(k, "im:metal@0.4", xf, [Vector2(0, 0.0), Vector2(0.04, 0.0), Vector2(0.042, 0.004), Vector2(0.042, 0.02), Vector2(0.037, 0.022), Vector2(0.0, 0.022)], func(_y: float) -> Color: return Color(0.13, 0.13, 0.14))
	for i in 6:
		var a := i * TAU / 6.0
		k.bevel_box("im:rubber", _at(cos(a) * 0.04, 0.006, sin(a) * 0.04, Basis(Vector3.UP, -a)), Vector3(0.012, 0.012, 0.016), 0.002, BLACK)
	_vessel(k, "im:metal@0.5", xf, [Vector2(0, 0.022), Vector2(0.036, 0.022), Vector2(0.036, 0.122), Vector2(0, 0.122)],
		func(y: float) -> Color: return olive.darkened(0.25) if fmod(y - 0.022, 0.025) < 0.003 else olive)
	_vessel(k, "im:paint", xf, [Vector2(0, 0.122), Vector2(0.037, 0.122), Vector2(0.037, 0.127), Vector2(0, 0.127)], func(_y: float) -> Color: return ORANGE)
	_vessel(k, "im:metal@0.4", xf, [Vector2(0, 0.127), Vector2(0.036, 0.127), Vector2(0.036, 0.137), Vector2(0.03, 0.142), Vector2(0, 0.142)], func(_y: float) -> Color: return Color(0.14, 0.14, 0.15))
	_cyl(k, "im:rubber", xf, Vector3(-0.012, 0.142, -0.006), Vector3(-0.012, 0.16, -0.006), 0.006, 0.005, 10, BLACK)
	_cyl(k, "im:rubber", xf, Vector3(-0.012, 0.16, -0.006), Vector3(-0.012, 0.3, -0.006), 0.003, 0.002, 8, BLACK)
	k.bevel_box("im:metal@0.6", _at(0, 0.035, 0.035), Vector3(0.03, 0.01, 0.004), 0.001, Color(0.75, 0.74, 0.7))
	var bx := Basis(Vector3.UP, -PI * 0.2)
	for y: float in [0.05, 0.11]:
		k.box("im:metal@0.4", Transform3D(bx, bx * Vector3(0.04, y, 0)), Vector3(0.01, 0.006, 0.01), Color(0.3, 0.3, 0.3))
	k.bevel_box("im:paint", Transform3D(bx, bx * Vector3(0.046, 0.08, 0)), Vector3(0.008, 0.07, 0.012), 0.003, ORANGE)
	return Vector3(0, 0.07, 0)

## A rugged datapad: a dark glass screen in a gunmetal case with thick rubber corner
## bumpers, a pale inner frame, orange buttons down the left side and corner screws.
static func _datapad(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var w := 0.2
	var h := 0.14
	var case_ := Color(0.25, 0.26, 0.28)
	var xf := _at(0, h * 0.5, 0)
	_ext_bevel(k, "im:composite", xf, _rrect(w, h, 0.012), [], 0.016, 0.003, case_)
	_ext(k, "im:metal@0.4", xf * _at(0, 0, 0.0082), _rrect(0.17, 0.112, 0.006), [_rrect(0.162, 0.104, 0.004)], 0.0012, Color(0.45, 0.46, 0.48))
	_ext(k, "im:visor", xf * _at(0, 0, 0.0082), _rrect(0.162, 0.104, 0.004), [], 0.001, Color(0.03, 0.035, 0.045))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c := Vector2(sx * (w * 0.5 - 0.011), sy * (h * 0.5 - 0.011))
			var o := xf * _at(c.x, c.y, 0)
			k.bevel_box("im:rubber", o * _at(-sx * 0.002, 0, 0), Vector3(0.028, 0.012, 0.02), 0.004, Color(0.12, 0.12, 0.13))
			k.bevel_box("im:rubber", o * _at(0, -sy * 0.002, 0), Vector3(0.012, 0.028, 0.02), 0.004, Color(0.12, 0.12, 0.13))
			_screw(k, o, Vector3(sx * 0.0005, sy * 0.0005, 0.01), Z, 0.0022, Color(0.55, 0.55, 0.57))
	for i in 3:
		k.bevel_box("im:paint", xf * _at(-w * 0.5 - 0.0005, 0.012 - i * 0.012, 0.0), Vector3(0.004, 0.008, 0.008), 0.0015, ORANGE)
	k.box("im:metal@0.4", xf * _at(0, -h * 0.5 + 0.007, 0.0082), Vector3(0.06, 0.003, 0.001), Color(0.4, 0.4, 0.42))
	return Vector3(0, 0.01, 0)

## A holo projector: a squat steel puck with a dark blue glass lens domed on top, chunky
## side blocks, a vent grille in front with two small orange lamps (paint, unlit).
static func _holo_projector(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.56, 0.57, 0.59)
	var xf := _at(0, 0, 0)
	_vessel(k, "im:metal@0.35", xf, [Vector2(0, 0), Vector2(0.06, 0), Vector2(0.066, 0.006), Vector2(0.066, 0.034), Vector2(0.062, 0.04), Vector2(0.05, 0.05), Vector2(0.044, 0.052), Vector2(0.044, 0.058), Vector2(0, 0.058)],
		func(y: float) -> Color: return steel.darkened(0.25) if absf(y - 0.02) < 0.002 else steel)
	ItemModels._torus(k, "im:metal@0.4", _at(0, 0.058, 0), 0.04, 0.004, 32, 6, Color(0.22, 0.22, 0.24))
	_lens(k, _at(0, 0.058, 0), 0.034, 0.01, Color(0.2, 0.36, 0.55, 0.9), Color(0.05, 0.07, 0.12, 0.95))
	ItemModels._disc(k, "im:visor", xf, Vector3(0, 0.0585, 0), Vector3.UP, 0.036, 28, Color(0.03, 0.04, 0.06))
	for s: float in [-1.0, 1.0]:
		var o := _at(s * 0.066, 0.02, 0.0)
		k.bevel_box("im:metal@0.4", o, Vector3(0.026, 0.03, 0.04), 0.005, Color(0.3, 0.3, 0.32))
		k.bevel_box("im:metal@0.4", o * _at(s * 0.012, -0.004, 0), Vector3(0.012, 0.026, 0.03), 0.004, Color(0.36, 0.36, 0.38))
	k.bevel_box("im:metal@0.5", _at(0, 0.024, 0.06), Vector3(0.04, 0.026, 0.012), 0.002, Color(0.15, 0.15, 0.16))
	for i in 5:
		k.box("im:metal@0.4", _at(0, 0.016 + i * 0.004, 0.0665), Vector3(0.034, 0.0014, 0.002), Color(0.35, 0.35, 0.37))
	for s: float in [-1.0, 1.0]:
		k.bevel_box("im:paint", _at(s * 0.026, 0.024, 0.06), Vector3(0.004, 0.012, 0.006), 0.001, ORANGE)

## Magnetic boots, a pair: thick grey soles with round mag pods, steel toe and heel cups,
## open frames up the ankle and black straps with steel buckles.
static func _magboots_kit(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	_mech_boot(k, _at(-0.062, 0, -0.03, Basis(Vector3.UP, 0.06)))
	_mech_boot(k, _at(0.062, 0, 0.0, Basis(Vector3.UP, -0.04)))

static func _mech_boot(k: MeshKit, xf: Transform3D) -> void:
	var grey := Color(0.28, 0.29, 0.31)
	var dark := Color(0.12, 0.12, 0.13)
	var steel := Color(0.34, 0.35, 0.37)
	k.bevel_box("im:metal@0.45", xf * _at(0, 0.016, 0), Vector3(0.1, 0.032, 0.25), 0.008, grey)
	k.bevel_box("im:rubber", xf * _at(0, 0.004, 0), Vector3(0.096, 0.008, 0.244), 0.003, dark)
	for z: float in [0.07, -0.08]:
		for s: float in [-1.0, 1.0]:
			_cyl(k, "im:metal@0.35", xf, Vector3(s * 0.05, 0.018, z), Vector3(s * 0.058, 0.018, z), 0.016, 0.014, 18, steel)
			ItemModels._disc(k, "im:metal@0.5", xf, Vector3(s * 0.0582, 0.018, z), Vector3(s, 0, 0), 0.008, 14, dark)
	# Toe cap over the front, heel cup behind, side frames and a back plate up the ankle.
	k.sphere("im:metal@0.4", xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.15)), Vector3(0, 0.03, 0.068)), 0.048, 10, 16, 0.0, 0.85, steel.darkened(0.1), true)
	k.bevel_box("im:rubber", xf * _at(0, 0.06, 0.02), Vector3(0.082, 0.05, 0.06), 0.012, dark)
	k.bevel_box("im:metal@0.4", xf * _at(0, 0.06, -0.09), Vector3(0.098, 0.06, 0.06), 0.014, steel)
	for s: float in [-1.0, 1.0]:
		k.bevel_box("im:metal@0.4", xf * _at(s * 0.046, 0.115, -0.06, Basis(Vector3.RIGHT, 0.15)), Vector3(0.008, 0.11, 0.07), 0.003, grey)
		k.bevel_box("im:metal@0.4", xf * _at(s * 0.05, 0.075, -0.035), Vector3(0.006, 0.022, 0.022), 0.003, steel)
		_screw(k, xf, Vector3(s * 0.053, 0.075, -0.035), Vector3(s, 0, 0), 0.004, Color(0.5, 0.42, 0.25))
	k.bevel_box("im:metal@0.4", xf * _at(0, 0.125, -0.1, Basis(Vector3.RIGHT, 0.15)), Vector3(0.09, 0.11, 0.01), 0.003, grey)
	k.bevel_box("im:rubber", xf * _at(0, 0.1, -0.08), Vector3(0.08, 0.06, 0.04), 0.01, dark.darkened(0.3))
	for y: float in [0.095, 0.15]:
		k.bevel_box("im:rubber", xf * _at(0, y, -0.035 - (y - 0.095) * 0.3), Vector3(0.104, 0.012, 0.02), 0.003, dark)
		k.bevel_box("im:metal@0.3", xf * _at(0.052, y, -0.035 - (y - 0.095) * 0.3), Vector3(0.006, 0.016, 0.022), 0.002, steel)
	k.bevel_box("im:rubber", xf * _at(0, 0.075, 0.03), Vector3(0.1, 0.01, 0.018), 0.003, dark)

## An oxygen canister: a scuffed white steel bottle with a green shoulder, black carry
## straps with orange buckles, a valve with a pressure gauge and a black hose.
static func _o2_canister(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var R := 0.045
	var white := Color(0.82, 0.82, 0.8)
	var green := Color(0.18, 0.45, 0.3)
	var prof: Array = [Vector2(0, 0), Vector2(R - 0.012, 0.0), Vector2(R - 0.003, 0.004), Vector2(R, 0.014)]
	prof.append(Vector2(R, 0.2))
	for i in 7:
		var a := PI * 0.5 * (i + 1) / 7.0
		prof.append(Vector2(0.011 + (R - 0.011) * cos(a), 0.2 + 0.04 * sin(a)))
	prof.append(Vector2(0.011, 0.25))
	prof.append(Vector2(0, 0.25))
	_vessel(k, "im:metal@0.45", _at(0, 0, 0), prof, func(y: float) -> Color: return white if y < 0.198 else green)
	for y: float in [0.06, 0.16]:
		_lathe(k, "im:rubber", _at(0, 0, 0), [Vector2(R + 0.002, y - 0.009), Vector2(R + 0.003, y - 0.008), Vector2(R + 0.003, y + 0.008), Vector2(R + 0.002, y + 0.009)], 30, BLACK)
		k.bevel_box("im:paint", _at(0.032, y, 0.035, Basis(Vector3.UP, -PI * 0.25)), Vector3(0.016, 0.022, 0.006), 0.002, ORANGE)
		k.bevel_box("im:metal@0.4", _at(0.0335, y, 0.0365, Basis(Vector3.UP, -PI * 0.25)), Vector3(0.008, 0.012, 0.004), 0.001, Color(0.2, 0.2, 0.2))
	_lathe(k, "im:rubber", _at(0, 0, 0), [Vector2(R + 0.0015, 0.06), Vector2(R + 0.0025, 0.06), Vector2(R + 0.0025, 0.16), Vector2(R + 0.0015, 0.16)], 30, BLACK, Vector2(0.9, 1.0))
	var brass := Color(0.62, 0.58, 0.5)
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), Vector3(0, 0.25, 0), Vector3(0, 0.27, 0), 0.01, 0.01, 12, brass)
	k.bevel_box("im:metal@0.35", _at(0, 0.278, 0), Vector3(0.03, 0.018, 0.018), 0.003, Color(0.25, 0.25, 0.27))
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), Vector3(0, 0.287, 0), Vector3(0, 0.297, 0), 0.006, 0.006, 10, Color(0.2, 0.2, 0.2))
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), Vector3(0.012, 0.28, 0), Vector3(0.032, 0.284, 0), 0.004, 0.004, 8, brass)
	# Gauge: a steel case, white dial, black needle, glass.
	var g := _at(0.044, 0.285, 0.004, Basis(Vector3.RIGHT, PI * 0.5))
	k.cylinder("im:metal@0.3", g * _at(0, -0.006, 0), 0.016, 0.016, 0.01, 20, true, 0.0, 1, Color(0.6, 0.6, 0.62))
	ItemModels._disc(k, "im:dial", g, Vector3(0, 0.0042, 0), Vector3.UP, 0.0135, 20, Color(0.94, 0.93, 0.9))
	k.box("im:dial", g * _at(0.003, 0.0046, 0.002, Basis(Vector3.UP, 0.6)), Vector3(0.011, 0.0004, 0.0012), Color(0.1, 0.05, 0.05))
	ItemModels._torus(k, "im:paint", g * _at(0, 0.004, 0), 0.0155, 0.0018, 20, 4, ORANGE)
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), Vector3(0.044, 0.268, 0.004), Vector3(0.044, 0.28, 0.004), 0.004, 0.004, 8, brass)
	_wire(k, _at(0, 0, 0), PackedVector3Array([Vector3(0.044, 0.27, 0.0), Vector3(0.062, 0.245, -0.004), Vector3(0.07, 0.17, 0.0), Vector3(0.068, 0.07, 0.01), Vector3(0.056, 0.03, 0.02), Vector3(0.05, 0.03, 0.04)]), 0.0042, Color(0.08, 0.08, 0.09), "im:rubber")
	return Vector3(0, 0.12, 0)

## Mech splint: a padded black boot brace, steel side struts hinged at the ankle with a
## round joint, black straps round the shin and over the foot with steel buckles.
static func _splint_mech(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var pad := Color(0.13, 0.13, 0.14)
	var steel := Color(0.72, 0.73, 0.75)
	var xf := _at(0, 0, 0)
	k.bevel_box("im:leather_armour", _at(0, 0.035, 0.03), Vector3(0.09, 0.07, 0.19), 0.025, pad)
	k.sphere("im:leather_armour", _at(0, 0.03, 0.115), 0.045, 8, 14, 0.0, 0.7, pad)
	k.bevel_box("im:rubber", _at(0, 0.006, 0.035), Vector3(0.094, 0.012, 0.21), 0.004, Color(0.08, 0.08, 0.08))
	_vessel(k, "im:leather_armour", xf * _at(0, 0, -0.04), [Vector2(0, 0.03), Vector2(0.05, 0.03), Vector2(0.052, 0.08), Vector2(0.048, 0.2), Vector2(0.05, 0.28), Vector2(0.044, 0.29), Vector2(0, 0.29)], func(_y: float) -> Color: return pad)
	for y: float in [0.13, 0.22]:
		_lathe(k, "im:leather_armour", _at(0, 0, -0.04), [Vector2(0.051, y - 0.014), Vector2(0.054, y - 0.012), Vector2(0.054, y + 0.012), Vector2(0.051, y + 0.014)], 24, Color(0.08, 0.08, 0.09))
		_ext(k, "im:metal@0.3", _at(0.0, y, 0.016), _rrect(0.024, 0.03, 0.004), [_rrect(0.014, 0.02, 0.002)], 0.004, steel)
	k.bevel_box("im:leather_armour", _at(0, 0.072, 0.07, Basis(Vector3.RIGHT, -0.35)), Vector3(0.098, 0.014, 0.04), 0.004, Color(0.08, 0.08, 0.09))
	_ext(k, "im:metal@0.3", _at(0.05, 0.072, 0.07, Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -0.35)), _rrect(0.024, 0.02, 0.003), [_rrect(0.014, 0.01, 0.002)], 0.004, steel)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.056
		k.bevel_box("im:metal@0.3", _at(x, 0.17, -0.04), Vector3(0.006, 0.18, 0.016), 0.002, steel)
		k.bevel_box("im:metal@0.3", _at(x, 0.04, 0.02, Basis(Vector3.RIGHT, 0.2)), Vector3(0.006, 0.014, 0.12), 0.002, steel)
		_cyl(k, "im:metal@0.3", xf, Vector3(x, 0.075, -0.04), Vector3(x + s * 0.008, 0.075, -0.04), 0.02, 0.019, 22, steel)
		_cyl(k, "im:metal@0.3", xf, Vector3(x + s * 0.008, 0.075, -0.04), Vector3(x + s * 0.012, 0.075, -0.04), 0.012, 0.009, 18, steel.lightened(0.1))
		ItemModels._torus(k, "im:metal@0.5", _at(x + s * 0.0082, 0.075, -0.04, Basis(Z, PI * 0.5)), 0.015, 0.0012, 22, 4, steel.darkened(0.4))
	return Vector3(0, 0.18, -0.04)

## An oxygen mask: a clear teardrop shell with a soft rim, blue straps and clips, a grey
## corrugated hose curling off its nose to a dark connector.
static func _oxygen_mask(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var T := Transform3D(Basis(Vector3.UP, -0.6), Vector3.ZERO) ## turned to show its profile, as painted
	var shell := T * Transform3D(Basis.from_scale(Vector3(1.3, 1.7, 1.3)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, 0))
	var outer: Array = []
	var inner: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var rr := 0.05 * cos(t * PI * 0.45) + 0.0005
		outer.append(Vector2(maxf(rr, 0.012), 0.055 * sin(t * PI * 0.5)))
	for i in range(8, -1, -1):
		var v: Vector2 = outer[i]
		inner.append(Vector2(v.x - 0.002, v.y - 0.002))
	_lathe(k, "im:glass", shell, outer + inner + [outer[0]], 32, Color(0.85, 0.92, 0.96, 0.28))
	ItemModels._torus(k, "im:glass", shell, 0.05, 0.004, 32, 6, Color(0.8, 0.85, 0.88, 0.6))
	var blue := Color(0.12, 0.35, 0.6)
	var nose := Vector3(0, 0.15, 0.071)
	_cyl(k, "own:plastic", T * _at(0, 0, 0), nose - Vector3(0, 0, 0.004), nose + Vector3(0, 0, 0.02), 0.014, 0.012, 16, Color(0.72, 0.74, 0.76))
	for s: float in [-1.0, 1.0]:
		k.bevel_box("own:plastic", T * _at(s * 0.066, 0.15, 0.008), Vector3(0.012, 0.022, 0.016), 0.003, blue)
		_strip(k, "im:linen", T * _at(0, 0, 0), _curve(PackedVector3Array([Vector3(s * 0.07, 0.15, 0.004), Vector3(s * 0.09, 0.16, -0.02), Vector3(s * 0.098, 0.17, -0.06), Vector3(s * 0.09, 0.18, -0.09)])), 0.016, 0.002, blue, Vector3(s, 0, 0))
		k.bevel_box("own:plastic", T * _at(s * 0.018, 0.142, 0.083), Vector3(0.008, 0.018, 0.012), 0.002, blue)
	_strip(k, "im:linen", T * _at(0, 0, 0), _curve(PackedVector3Array([Vector3(0, 0.235, 0.01), Vector3(0, 0.25, -0.02), Vector3(0, 0.255, -0.06)])), 0.016, 0.002, blue, Vector3.UP)
	var hose := _curve(PackedVector3Array([nose + Vector3(0, 0, 0.018), Vector3(0, 0.12, 0.105), Vector3(-0.02, 0.07, 0.1), Vector3(-0.05, 0.035, 0.06), Vector3(-0.035, 0.012, 0.03), Vector3(0.01, 0.014, 0.035), Vector3(0.04, 0.03, 0.06), Vector3(0.05, 0.06, 0.08)]), 12)
	var radii := PackedFloat32Array()
	for i in hose.size():
		radii.append(0.0135 if i % 2 == 0 else 0.011)
	ItemModels._tube(k, "im:metal@0.4", T * _at(0, 0, 0), hose, radii, 10, Color(0.55, 0.57, 0.6))
	var e := hose[hose.size() - 1]
	var d := (e - hose[hose.size() - 2]).normalized()
	_cyl(k, "own:plastic", T * _at(0, 0, 0), e, e + d * 0.022, 0.013, 0.013, 14, Color(0.2, 0.21, 0.22))
	return T * Vector3(0, 0.15, 0)

## Defibrillator paddles: two dark grey paddles with polished steel contact plates, grip
## handles with red buttons, joined by a black coiled cord.
static func _defibrillator(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var body := Color(0.26, 0.27, 0.29)
	var ends: Array = []
	for i in 2:
		var o := _at(-0.045 + i * 0.09, 0.06 + i * 0.02, -i * 0.05, Basis(Vector3.UP, -0.1))
		k.bevel_box("im:composite", o, Vector3(0.072, 0.078, 0.034), 0.01, body)
		k.bevel_box("im:metal@0.25", o * _at(0, 0, 0.019), Vector3(0.064, 0.07, 0.006), 0.006, Color(0.9, 0.9, 0.92))
		k.bevel_box("im:composite", o * _at(0, 0.0, -0.022), Vector3(0.05, 0.06, 0.012), 0.006, body.darkened(0.2))
		for s: float in [-1.0, 1.0]:
			k.bevel_box("im:composite", o * _at(s * 0.016, 0.052, -0.012), Vector3(0.01, 0.03, 0.014), 0.003, body.darkened(0.1))
		k.bevel_box("im:composite", o * _at(0, 0.068, -0.012), Vector3(0.05, 0.012, 0.016), 0.004, body.darkened(0.1))
		for s: float in [-1.0, 1.0]:
			k.bevel_box("im:paint", o * _at(s * 0.009, 0.0755, -0.012), Vector3(0.012, 0.004, 0.009), 0.0012, Color(0.8, 0.12, 0.1))
		ends.append(o * Vector3(0, -0.04, -0.008))
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	var spine := _curve(PackedVector3Array([a, a + Vector3(0.0, -0.025, 0.0), (a + b) * 0.5 + Vector3(0.02, -0.04, 0.03), b + Vector3(0.025, -0.03, 0.0), b + Vector3(0, -0.005, 0)]), 6)
	_coil(k, "im:rubber", _at(0, 0, 0), spine, 90.0, 0.009, 0.003, Color(0.08, 0.08, 0.09))
	return Vector3(-0.045, 0.1, 0)

# --- Materials and parts ----------------------------------------------------------------

## Scrap alloy: a heap of torn plate, bent strip and rod, mostly grey steel, a few pieces
## rust-stained.
static func _alloy_scrap(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var rust := Color(0.48, 0.27, 0.14)
	for i in 30:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.085
		var p := Vector3(cos(a) * d, 0.012 + (1.0 - d / 0.085) * 0.06 + r.randf() * 0.01, sin(a) * d * 0.8)
		var b := Basis.from_euler(Vector3(r.randf_range(-0.9, 0.9), r.randf() * TAU, r.randf_range(-0.9, 0.9)))
		var s := Vector3(r.randf_range(0.045, 0.085), r.randf_range(0.035, 0.065), r.randf_range(0.003, 0.007))
		var c := STEEL.darkened(r.randf_range(0.15, 0.45))
		k.bevel_box("im:metal@0.4", Transform3D(b, p), s, 0.002, c)
		if r.randf() < 0.45:
			k.box("im:metal@0.85", Transform3D(b, p + b.z * (s.z * 0.5 + 0.0002) + b.x * s.x * 0.15), Vector3(s.x * 0.45, s.y * 0.4, 0.0004), rust)
	for i in 10:
		var a := r.randf() * TAU
		var c0 := Vector3(cos(a) * 0.06, 0.02 + r.randf() * 0.04, sin(a) * 0.05)
		var dir := Vector3(cos(a), r.randf_range(0.3, 1.0), sin(a)).normalized()
		var pts := PackedVector3Array()
		var side := dir.cross(Vector3.UP).normalized()
		for s in 6:
			var t := float(s) / 5.0
			pts.append(c0 + dir * t * 0.07 + side * sin(t * 2.5) * 0.02 * (1.0 if i % 2 else -1.0))
		if i < 7:
			_strip(k, "im:metal@0.4", _at(0, 0, 0), pts, 0.008, 0.003, STEEL.darkened(r.randf() * 0.2), side.cross(dir))
		else:
			var c := _curve(pts, 3)
			ItemModels._tube(k, "im:metal@0.4", _at(0, 0, 0), c, _fill(c.size(), 0.0035), 6, STEEL.darkened(0.15))

static func _fill(n: int, v: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a

## Carbon fibre: a roll of black twill-woven cloth, its spiral end showing, a length of it
## unrolled flat in front.
static func _carbon_fiber(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var R := 0.04
	var L := 0.2
	var col := Color(0.16, 0.16, 0.17)
	var Y := Transform3D(Basis(Vector3.UP, 0.7), Vector3.ZERO)
	var ax := Y * _at(-L * 0.5, R, 0, Basis(Z, -PI * 0.5))
	k.cylinder("own:carbon", ax, R, R, L, 32, false, 0.0, 1, col)
	for e: float in [0.0, L]:
		var n := Vector3.DOWN if e == 0.0 else Vector3.UP
		ItemModels._disc(k, "own:carbon", ax, Vector3(0, e, 0), n, R, 32, col.darkened(0.3))
		for q in 7:
			ItemModels._torus(k, "own:carbon", ax * _at(0, e, 0), 0.008 + q * 0.0045, 0.0007, 28, 3, col.lightened(0.15))
		ItemModels._disc(k, "own:carbon", ax, Vector3(0, e + (0.0003 if e > 0.0 else -0.0003), 0), n, 0.007, 16, Color(0.03, 0.03, 0.03))
	var f := func(u: float, v: float) -> Vector3:
		var z := v * 0.13
		return Vector3((u - 0.5) * L * 0.98, 0.0015 + sin(v * PI * 1.5) * 0.002 * v, z + 0.002)
	ItemModels._sheet(k, "own:carbon", Y, f, 6, 10, 0.0015, col, col.darkened(0.2))

## Polymer pellets: a heap of small translucent milky cylinders.
static func _polymer(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	for i in 110:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.06
		var y := 0.007 + (1.0 - d / 0.06) * 0.045 + r.randf() * 0.006
		var b := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU))
		var c := Color(0.85, 0.85, 0.83, 0.8).darkened(r.randf() * 0.08)
		k.cylinder("own:frost", Transform3D(b, Vector3(cos(a) * d, y, sin(a) * d)) * _at(0, -0.0055, 0), 0.0078, 0.0078, 0.011, 12, true, 0.0, 1, c)

## Graphene: a stack of thin dark grey sheets, each a fine honeycomb, slightly wavy and
## offset like leaves in a pile.
static func _graphene(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	for i in 4:
		var o := _at(r.randf_range(-0.008, 0.008), 0.004 + i * 0.012, r.randf_range(-0.008, 0.008), Basis(Vector3.UP, r.randf_range(-0.15, 0.15)))
		var ph := r.randf() * TAU
		var f := func(u: float, v: float) -> Vector3:
			return Vector3((u - 0.5) * 0.12, sin(u * 5.0 + ph) * 0.0015 + sin(v * 4.0 + ph) * 0.0012, (v - 0.5) * 0.1)
		ItemModels._sheet(k, "own:hex", o, f, 10, 8, 0.0012, Color(0.45, 0.47, 0.53), Color(0.3, 0.31, 0.35))

## Ceramic plate: three thick matte white tiles stacked a little askew, edges eased.
static func _ceramic_plate(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	for i in 3:
		var o := _at(r.randf_range(-0.01, 0.01), 0.007 + i * 0.0145, r.randf_range(-0.01, 0.01), Basis(Vector3.UP, r.randf_range(-0.1, 0.1)))
		k.bevel_box("own:ceramic", o, Vector3(0.13, 0.013, 0.11), 0.0025, Color(0.74, 0.75, 0.76))

## A nanotube spool: thread-fine black mesh wound on a turned steel reel.
static func _nanotube_spool(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.6, 0.61, 0.63)
	var xf := _at(0, 0, 0)
	for y0: float in [0.0, 0.1]:
		_lathe(k, "im:metal@0.3", xf * _at(0, y0, 0), [Vector2(0.024, 0), Vector2(0.048, 0), Vector2(0.052, 0.003), Vector2(0.052, 0.01), Vector2(0.048, 0.013), Vector2(0.024, 0.013), Vector2(0.024, 0.0)], 40, steel)
		ItemModels._torus(k, "im:metal@0.5", xf * _at(0, y0 + 0.0132, 0), 0.036, 0.0012, 36, 4, steel.darkened(0.35))
	_cyl(k, "im:metal@0.4", xf, Vector3(0, 0.0, 0), Vector3(0, 0.113, 0), 0.024, 0.024, 24, steel.darkened(0.3), false)
	_cyl(k, "im:metal@0.6", xf, Vector3(0, 0.112, 0), Vector3(0, 0.0005, 0), 0.0225, 0.0225, 24, Color(0.08, 0.08, 0.08), false)
	_cyl(k, "own:lattice", xf, Vector3(0, 0.013, 0), Vector3(0, 0.1, 0), 0.042, 0.042, 40, Color(0.4, 0.41, 0.45))

## A servo: a stepper motor, its square black laminated body between steel end plates, a
## brass bearing ring and shaft out the front, red and black leads from the back.
static func _servo(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.66, 0.67, 0.69)
	var xf := _at(0, 0.035, 0, Basis(Vector3.UP, -0.5))
	k.bevel_box("im:metal@0.35", xf * _at(0, 0, 0.032), Vector3(0.068, 0.068, 0.012), 0.006, steel)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			ItemModels._disc(k, "im:metal@0.6", xf, Vector3(sx * 0.025, sy * 0.025, 0.0381), Z, 0.0035, 10, Color(0.08, 0.08, 0.08))
	for i in 7:
		k.bevel_box("im:metal@0.5", xf * _at(0, 0, 0.022 - i * 0.0068), Vector3(0.062, 0.062, 0.006), 0.004, Color(0.13, 0.13, 0.14) if i % 2 else Color(0.18, 0.18, 0.19))
	k.bevel_box("im:metal@0.35", xf * _at(0, 0, -0.03), Vector3(0.064, 0.064, 0.01), 0.005, steel)
	_cyl(k, "im:metal@0.3", xf, Vector3(0, 0, 0.038), Vector3(0, 0, 0.042), 0.018, 0.017, 28, Color(0.82, 0.62, 0.3))
	_cyl(k, "im:metal@0.3", xf, Vector3(0, 0, 0.042), Vector3(0, 0, 0.045), 0.011, 0.01, 20, steel.darkened(0.2))
	_cyl(k, "im:metal@0.25", xf, Vector3(0, 0, 0.044), Vector3(0, 0, 0.068), 0.005, 0.005, 14, steel.lightened(0.1))
	k.bevel_box("own:plastic", xf * _at(0.012, 0.036, -0.022), Vector3(0.024, 0.01, 0.014), 0.002, Color(0.1, 0.1, 0.1))
	var cols := [Color(0.75, 0.12, 0.08), Color(0.08, 0.08, 0.08), Color(0.75, 0.12, 0.08), Color(0.08, 0.08, 0.08)]
	for i in 4:
		var x := 0.004 + i * 0.0055
		_wire(k, xf, PackedVector3Array([Vector3(x, 0.04, -0.026), Vector3(x, 0.046, -0.034), Vector3(x + 0.006, 0.03, -0.046), Vector3(x + 0.01, 0.012, -0.05)]), 0.0016, cols[i])

## An optic lens: a thick glass element coated blue shading to violet at its rim, set in
## a stepped black steel barrel.
static func _optic_lens(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var b := _at(0, 0.045, 0, Basis(Vector3.RIGHT, PI * 0.5))
	var dark := Color(0.17, 0.18, 0.2)
	_lathe(k, "im:metal@0.3", b * _at(0, -0.012, 0), [Vector2(0.036, 0.0), Vector2(0.043, 0.0), Vector2(0.046, 0.003), Vector2(0.046, 0.016), Vector2(0.044, 0.02), Vector2(0.04, 0.022), Vector2(0.037, 0.02), Vector2(0.036, 0.0)], 40, dark)
	ItemModels._torus(k, "im:metal@0.25", b * _at(0, 0.004, 0), 0.0465, 0.0015, 40, 4, Color(0.5, 0.52, 0.56))
	_lens(k, b * _at(0, 0.006, 0), 0.037, 0.012, Color(0.15, 0.5, 1.0, 0.65), Color(0.5, 0.22, 0.85, 0.85))
	_lens(k, b * _at(0, -0.006, 0, Basis(Vector3.RIGHT, PI)), 0.037, 0.008, Color(0.25, 0.5, 0.95, 0.6), Color(0.45, 0.25, 0.8, 0.8))
	ItemModels._torus(k, "im:metal@0.4", b * _at(0, -0.004, 0), 0.03, 0.0012, 36, 4, Color(0.08, 0.08, 0.1))

## A wiring loom: a coil of red, yellow, blue and black wires gathered in black braided
## sleeves, tied with black clips, ending in a moulded connector.
static func _wiring_loom(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := _at(0, 0.05, 0, Basis(Vector3.RIGHT, 1.0))
	var cols := [Color(0.75, 0.1, 0.08), Color(0.95, 0.75, 0.1), Color(0.15, 0.3, 0.75), Color(0.85, 0.35, 0.08), Color(0.1, 0.1, 0.1), Color(0.75, 0.1, 0.08)]
	var R := 0.068
	for w in cols.size():
		var off := Vector2.from_angle(w * TAU / cols.size()) * 0.009
		var path := PackedVector3Array()
		for i in 73:
			var a := TAU * i / 72.0 * 0.92 + 0.3
			var rr := R + off.x + sin(a * 3.0 + w) * 0.002
			path.append(Vector3(cos(a) * rr, off.y + sin(a * 2.0 + w * 0.7) * 0.0015, sin(a) * rr))
		ItemModels._tube(k, "own:plastic", xf, path, _fill(path.size(), 0.0046), 6, cols[w])
	for q: Vector2 in [Vector2(0.5, 1.6), Vector2(2.6, 3.6), Vector2(4.4, 5.2)]:
		var path := PackedVector3Array()
		for i in 25:
			var a := lerpf(q.x, q.y, i / 24.0)
			path.append(Vector3(cos(a) * R, 0, sin(a) * R))
		ItemModels._tube(k, "own:carbon", xf, path, _fill(path.size(), 0.0155), 10, Color(0.1, 0.1, 0.11))
	for a: float in [0.45, 1.65, 2.55, 3.65, 4.35]:
		var p := Vector3(cos(a) * R, 0, sin(a) * R)
		var t := Vector3(-sin(a), 0, cos(a))
		_cyl(k, "own:plastic", xf, p - t * 0.008, p + t * 0.008, 0.0185, 0.0185, 12, Color(0.06, 0.06, 0.06))
	# The connector where the loom ends.
	var a0 := 0.3
	var e := Vector3(cos(a0) * R, 0, sin(a0) * R)
	var t0 := Vector3(-sin(a0), 0, cos(a0))
	var cb := Basis(t0.cross(Vector3.UP), Vector3.UP, t0)
	k.bevel_box("own:plastic", xf * Transform3D(cb, e - t0 * 0.02), Vector3(0.03, 0.022, 0.032), 0.003, Color(0.08, 0.08, 0.09))
	k.bevel_box("own:plastic", xf * Transform3D(cb, e - t0 * 0.039), Vector3(0.024, 0.016, 0.008), 0.002, Color(0.12, 0.12, 0.13))
	for i in 4:
		k.box("im:metal@0.3", xf * Transform3D(cb, e - t0 * 0.0435 + cb.x * (i - 1.5) * 0.005), Vector3(0.002, 0.008, 0.001), GOLD)

## A superconductor coil: a fat ring of bright wound wire on a dark base with blue paint
## marks, held by bronze clamps at six points.
static func _superconductor(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var wire := Color(0.56, 0.58, 0.62)
	var xf := _at(0, 0, 0)
	_lathe(k, "im:metal@0.4", xf, [Vector2(0.03, 0), Vector2(0.078, 0), Vector2(0.08, 0.003), Vector2(0.08, 0.012), Vector2(0.03, 0.012), Vector2(0.03, 0.0)], 48, Color(0.2, 0.2, 0.22))
	_lathe(k, "im:metal@0.35", xf, [Vector2(0.036, 0.012), Vector2(0.07, 0.012), Vector2(0.07, 0.056), Vector2(0.036, 0.056), Vector2(0.036, 0.012)], 48, wire.darkened(0.25))
	for i in 12:
		var y := 0.014 + i * 0.0036
		ItemModels._torus(k, "im:metal@0.25", _at(0, y, 0), 0.0702, 0.0018, 48, 4, wire)
		ItemModels._torus(k, "im:metal@0.25", _at(0, y, 0), 0.0358, 0.0018, 32, 4, wire)
	for i in 10:
		ItemModels._torus(k, "im:metal@0.25", _at(0, 0.0565, 0), 0.0378 + i * 0.0036, 0.0018, 48, 4, wire)
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		var b := Basis(Vector3.UP, -a)
		var bronze := Color(0.72, 0.48, 0.24)
		var o := Transform3D(b, Vector3.ZERO)
		k.bevel_box("im:metal@0.4", o * _at(0.075, 0.034, 0), Vector3(0.008, 0.05, 0.016), 0.002, bronze)
		k.bevel_box("im:metal@0.4", o * _at(0.054, 0.061, 0), Vector3(0.05, 0.007, 0.014), 0.002, bronze)
		k.bevel_box("im:metal@0.4", o * _at(0.032, 0.05, 0), Vector3(0.006, 0.024, 0.012), 0.002, bronze)
		_screw(k, o, Vector3(0.054, 0.0646, 0), Vector3.UP, 0.0025, bronze.darkened(0.2))
		k.box("im:paint", Transform3D(Basis(Vector3.UP, -a - PI / 6.0), Vector3.ZERO) * _at(0.0802, 0.0065, 0), Vector3(0.0012, 0.004, 0.014), Color(0.15, 0.45, 0.85))

## A hull patch: two sandwich panels, a diamond-tread steel skin over an aluminium
## honeycomb core, the top one notched at a corner, the second lying under it askew.
static func _hull_patch(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	var outline := PackedVector2Array([Vector2(-0.09, -0.08), Vector2(0.02, -0.08), Vector2(0.02, -0.062), Vector2(0.04, -0.062), Vector2(0.04, -0.08), Vector2(0.09, -0.08), Vector2(0.09, 0.08), Vector2(-0.09, 0.08)])
	for i in 2:
		var o := Transform3D(Basis(Vector3.UP, -0.12 + i * 0.25) * flat, Vector3(-0.02 * i, 0.028 - i * 0.02, -0.03 * i))
		var line := outline if i == 0 else _rrect(0.18, 0.16, 0.003)
		_ext(k, "own:tread", o * _at(0, 0, 0.0115), line, [], 0.004, Color(0.62, 0.63, 0.65))
		_ext(k, "own:hex", o * _at(0, 0, 0.003), Geometry2D.offset_polygon(line, -0.001)[0], [], 0.013, Color(0.38, 0.39, 0.41))
		_ext(k, "im:metal@0.4", o * _at(0, 0, -0.0055), line, [], 0.003, Color(0.55, 0.56, 0.58))

## A sensor module: a steel ball with a big violet-blue lens in a black barrel, two small
## lenses and a pin lens beside it, a box on its flank and red indicator studs.
static func _sensor_module(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.64, 0.65, 0.67)
	var c := Vector3(0, 0.05, 0)
	k.sphere("im:metal@0.3", _at(c.x, c.y, c.z), 0.046, 14, 24, 0.0, 1.0, steel)
	ItemModels._torus(k, "im:metal@0.5", _at(c.x, c.y, c.z), 0.0462, 0.0008, 40, 3, steel.darkened(0.4))
	ItemModels._torus(k, "im:metal@0.5", _at(c.x, c.y, c.z, Basis(Z, PI * 0.5)), 0.0462, 0.0008, 40, 3, steel.darkened(0.4))
	var mains: Array = [[Vector3(0.008, 0.004, 1.0), 0.022, 0.02], [Vector3(-0.55, -0.35, 0.75), 0.011, 0.01], [Vector3(0.35, -0.6, 0.72), 0.011, 0.01], [Vector3(0.05, 0.75, 0.65), 0.007, 0.006]]
	for m: Array in mains:
		var d: Vector3 = (m[0] as Vector3).normalized()
		var rad: float = m[1]
		var b := _along(d)
		var base := c + d * 0.036
		var tip := c + d * (0.046 + float(m[2]))
		_cyl(k, "im:metal@0.35", _at(0, 0, 0), base, tip, rad + 0.004, rad + 0.003, 24, Color(0.12, 0.12, 0.13))
		ItemModels._torus(k, "im:metal@0.3", Transform3D(b, tip), rad + 0.0025, 0.0012, 24, 4, steel)
		_lens(k, Transform3D(b, tip), rad, rad * 0.4, Color(0.35, 0.45, 0.95, 0.75), Color(0.6, 0.2, 0.75, 0.9))
	for i in 2:
		var d := Vector3(0.62, 0.12 - i * 0.22, 0.77).normalized()
		k.sphere("im:paint", Transform3D(Basis.IDENTITY, c + d * 0.046), 0.0035, 5, 8, 0.0, 1.0, Color(0.75, 0.1, 0.08))
	var bx := _at(0.047, 0.055, -0.004)
	k.bevel_box("im:metal@0.35", bx, Vector3(0.022, 0.05, 0.036), 0.004, steel.darkened(0.15))
	k.bevel_box("im:metal@0.5", bx * _at(0.011, 0, 0), Vector3(0.004, 0.04, 0.026), 0.002, Color(0.14, 0.14, 0.15))
	_cyl(k, "im:metal@0.35", _at(0, 0, 0), c + Vector3(-0.04, 0, -0.01), c + Vector3(-0.056, 0, -0.01), 0.016, 0.015, 18, steel.darkened(0.1))

## A gyroscope: three polished steel gimbal bands crossing round a brass rotor on a steel
## axle with a brass cap.
static func _gyroscope(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.62, 0.63, 0.65)
	var c := Vector3(0, 0.065, 0)
	var rings: Array = [[Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, 0.0), 0.06], [Basis(Z, PI * 0.5).rotated(Vector3.UP, 0.7), 0.052], [Basis(Vector3.RIGHT, 1.1).rotated(Vector3.UP, -0.5), 0.044]]
	for rg: Array in rings:
		var R: float = rg[1]
		var o := Transform3D(rg[0] as Basis, c)
		_lathe(k, "im:metal@0.2", o * _at(0, -0.008, 0), [Vector2(R - 0.004, 0), Vector2(R, 0), Vector2(R, 0.016), Vector2(R - 0.004, 0.016), Vector2(R - 0.004, 0)], 48, steel)
	var brass := Color(0.85, 0.65, 0.3)
	_lathe(k, "im:metal@0.25", _at(c.x, c.y - 0.006, c.z), [Vector2(0, 0), Vector2(0.026, 0), Vector2(0.028, 0.002), Vector2(0.028, 0.01), Vector2(0.026, 0.012), Vector2(0.01, 0.012), Vector2(0.008, 0.016), Vector2(0, 0.016)], 36, brass)
	_cyl(k, "im:metal@0.2", _at(0, 0, 0), c + Vector3(0, -0.062, 0), c + Vector3(0, 0.068, 0), 0.003, 0.003, 10, steel)
	_cyl(k, "im:metal@0.25", _at(0, 0, 0), c + Vector3(0, 0.06, 0), c + Vector3(0, 0.07, 0), 0.006, 0.005, 12, brass)
	_cyl(k, "im:metal@0.25", _at(0, 0, 0), c + Vector3(0, -0.066, 0), c + Vector3(0, -0.06, 0), 0.005, 0.006, 12, steel)

## A thruster nozzle: a steel bell flaring to a wide mouth, copper inside, on a ringed
## throat with bolted flanges.
static func _thruster_part(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.44, 0.45, 0.48)
	var copper := Color(0.75, 0.42, 0.24)
	var xf := Transform3D(Basis(Z, -0.45) * Basis(Vector3.RIGHT, -1.05), Vector3(0, 0.11, 0))
	var outer: Array = []
	var inner: Array = []
	for i in 13:
		var t := float(i) / 12.0
		var y := -0.08 + t * 0.13
		var rr := 0.034 + 0.056 * pow(1.0 - t, 1.8)
		outer.append(Vector2(rr, y))
		inner.append(Vector2(rr - 0.003, y))
	inner.reverse()
	var col := func(p: Vector3, _a: float, _tt: float) -> Color:
		return steel
	_lathe(k, "im:metal@0.3", xf, outer, 40, col)
	_lathe(k, "im:metal@0.35", xf, inner, 40, copper)
	ItemModels._torus(k, "im:metal@0.3", xf * _at(0, -0.08, 0), 0.0885, 0.0018, 40, 5, steel.lightened(0.1))
	var stack := [[0.05, 0.062, 0.042], [0.062, 0.068, 0.056], [0.068, 0.08, 0.044], [0.08, 0.088, 0.06], [0.088, 0.1, 0.046], [0.1, 0.108, 0.058]]
	for s: Array in stack:
		_cyl(k, "im:metal@0.35", xf, Vector3(0, s[0], 0), Vector3(0, s[1], 0), s[2], s[2], 32, steel.darkened(0.1 if float(s[2]) < 0.05 else 0.0))
	for y: float in [0.062, 0.08, 0.1]:
		for i in 10:
			var a := i * TAU / 10.0
			_cyl(k, "im:metal@0.35", xf, Vector3(cos(a) * 0.052, y, sin(a) * 0.052), Vector3(cos(a) * 0.052, y + 0.009, sin(a) * 0.052), 0.0028, 0.0028, 6, steel.lightened(0.15))
	ItemModels._disc(k, "im:metal@0.5", xf, Vector3(0, 0.1081, 0), Vector3.UP, 0.04, 28, steel.darkened(0.3))

## An antenna: a pale steel dish with radial ribs, a feed horn held on three struts, on a
## yoke and a geared turntable base.
static func _antenna(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var pale := Color(0.72, 0.73, 0.75)
	var steel := Color(0.58, 0.59, 0.61)
	var dish := Transform3D(Basis(Vector3.RIGHT, 0.35) * Basis(Z, 0.85), Vector3(0, 0.15, 0.0))
	var R := 0.1
	var depth := 0.032
	var front: Array = []
	var back: Array = []
	for i in 11:
		var rr := R * i / 10.0
		front.append(Vector2(rr, depth * (rr / R) * (rr / R)))
		back.append(Vector2(rr, depth * (rr / R) * (rr / R) - 0.003))
	front.reverse()
	_lathe(k, "im:metal@0.4", dish, back + front, 40, pale)
	for i in 12:
		var a := i * TAU / 12.0
		var pts := PackedVector3Array()
		for q in 6:
			var rr := 0.012 + (R - 0.014) * q / 5.0
			pts.append(Vector3(cos(a) * rr, depth * pow(rr / R, 2.0) + 0.0007, sin(a) * rr))
		_strip(k, "im:metal@0.4", dish, pts, 0.002, 0.0008, pale.darkened(0.15), Vector3.UP)
	ItemModels._torus(k, "im:metal@0.35", dish * _at(0, depth - 0.0015, 0), R, 0.002, 40, 4, pale.darkened(0.1))
	var feed := Vector3(0, 0.075, 0)
	for i in 3:
		var a := i * TAU / 3.0 + PI * 0.5
		_cyl(k, "im:metal@0.35", dish, Vector3(cos(a) * R * 0.9, depth * 0.81, sin(a) * R * 0.9), feed, 0.0016, 0.0016, 6, steel)
	_cyl(k, "im:metal@0.35", dish, feed - Vector3(0, 0.008, 0), feed + Vector3(0, 0.014, 0), 0.007, 0.005, 12, steel)
	_cyl(k, "im:metal@0.35", dish, Vector3(0, 0.0, 0), Vector3(0, 0.012, 0), 0.012, 0.01, 14, steel.darkened(0.2))
	_cyl(k, "im:metal@0.35", dish, Vector3(0, -0.003, 0), Vector3(0, -0.02, 0), 0.016, 0.014, 14, steel.darkened(0.25))
	# Yoke and turntable.
	var yk := dish * Vector3(0, -0.02, 0)
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0.02, 0), yk, 0.01, 0.009, 12, steel.darkened(0.2))
	k.bevel_box("im:metal@0.4", _at(yk.x, yk.y, yk.z), Vector3(0.03, 0.02, 0.02), 0.004, steel.darkened(0.25))
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0.014, 0), 0.04, 0.037, 32, steel.darkened(0.15))
	for i in 10:
		var a := i * TAU / 10.0
		k.bevel_box("im:metal@0.4", _at(cos(a) * 0.042, 0.005, sin(a) * 0.042, Basis(Vector3.UP, -a)), Vector3(0.01, 0.01, 0.012), 0.002, steel.darkened(0.25))
	_cyl(k, "im:metal@0.4", _at(0, 0, 0), Vector3(0, 0.014, 0), Vector3(0, 0.024, 0), 0.026, 0.02, 24, steel)

## A solar panel: four blocks of dark blue cells parted by bright grid lines in a bronze
## frame with black corner brackets, leaning back on a fold-out stand.
static func _solar_panel(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var w := 0.26
	var h := 0.22
	var tilt := Basis(Vector3.RIGHT, -0.55)
	var p := Transform3D(tilt, Vector3(0, 0.0, 0)) * _at(0, h * 0.5 + 0.006, 0)
	var bronze := Color(0.62, 0.48, 0.3)
	k.box("im:metal@0.35", p * _at(0, 0, -0.002), Vector3(w, h, 0.004), Color(0.32, 0.33, 0.36))
	var cells := 5
	var gap := 0.0015
	var qw := (w - 0.02) * 0.5
	var qh := (h - 0.02) * 0.5
	for qx in 2:
		for qy in 2:
			var ox := -w * 0.5 + 0.006 + qx * (qw + 0.008)
			var oy := -h * 0.5 + 0.006 + qy * (qh + 0.008)
			for cx in cells:
				for cy in cells:
					var cw := qw / cells
					var ch := qh / cells
					k.box("own:solar", p * _at(ox + (cx + 0.5) * cw, oy + (cy + 0.5) * ch, 0.0005), Vector3(cw - gap, ch - gap, 0.001), Color(0.1, 0.14, 0.36))
	for s: float in [-1.0, 1.0]:
		k.bevel_box("im:metal@0.4", p * _at(s * (w * 0.5 + 0.003), 0, 0), Vector3(0.008, h + 0.014, 0.01), 0.002, bronze)
		k.bevel_box("im:metal@0.4", p * _at(0, s * (h * 0.5 + 0.003), 0), Vector3(w + 0.014, 0.008, 0.01), 0.002, bronze)
		k.box("im:metal@0.4", p * _at(0, 0, 0.0006), Vector3(0.006, h, 0.0012), Color(0.62, 0.63, 0.66)) if s > 0.0 else k.box("im:metal@0.4", p * _at(0, 0, 0.0006), Vector3(w, 0.006, 0.0012), Color(0.62, 0.63, 0.66))
	for sx: float in [-1.0, 0.0, 1.0]:
		for sy: float in [-1.0, 0.0, 1.0]:
			if sx == 0.0 and sy == 0.0:
				continue
			if sx != 0.0 and sy != 0.0 or sy == 0.0:
				k.bevel_box("im:metal@0.5", p * _at(sx * (w * 0.5 + 0.003), sy * (h * 0.5 + 0.003), 0.004), Vector3(0.014, 0.014, 0.008), 0.003, Color(0.1, 0.1, 0.1))
			elif sx == 0.0:
				k.bevel_box("im:metal@0.5", p * _at(0, sy * (h * 0.5 + 0.003), 0.004), Vector3(0.014, 0.014, 0.008), 0.003, Color(0.1, 0.1, 0.1))
	var top := p * Vector3(0, h * 0.35, -0.005)
	for s: float in [-1.0, 1.0]:
		var a := top + Vector3(s * w * 0.42, 0, 0)
		_cyl(k, "im:metal@0.4", _at(0, 0, 0), a, Vector3(s * w * 0.42, 0.004, -0.02), 0.0035, 0.0035, 8, bronze)
		k.bevel_box("im:metal@0.5", _at(s * w * 0.42, 0.004, -0.02), Vector3(0.016, 0.008, 0.012), 0.002, Color(0.1, 0.1, 0.1))

## An electromagnet: a ring core wound thick with copper wire, held by four steel clamp
## blocks at its quarters.
static func _magnet(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var c := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.075, 0))
	var R := 0.05
	var rt := 0.021
	var copper := Color(0.78, 0.42, 0.2)
	ItemModels._torus(k, "im:metal@0.4", c, R, rt, 48, 12, copper.darkened(0.35))
	var path := PackedVector3Array()
	var turns := 90.0
	var n := int(turns * 10.0)
	for i in n + 1:
		var s := float(i) / n
		var th := TAU * s
		var ph := TAU * s * turns
		var rad := Vector3(cos(th), 0, sin(th))
		path.append(rad * R + (rad * cos(ph) + Vector3.UP * sin(ph)) * (rt + 0.0012))
	ItemModels._tube(k, "im:metal@0.3", c, path, _fill(path.size(), 0.0014), 4, copper, false)
	for i in 4:
		var a := i * PI * 0.5 + PI * 0.5
		var b := Basis(Vector3.UP, -a)
		var o := c * Transform3D(b, b * Vector3(R, 0, 0))
		k.bevel_box("im:metal@0.35", o, Vector3(0.054, 0.054, 0.024), 0.005, Color(0.6, 0.61, 0.63))
		k.box("im:metal@0.5", o, Vector3(0.056, 0.002, 0.026), Color(0.2, 0.2, 0.22))
		k.box("im:metal@0.5", o * _at(0, 0, 0.0), Vector3(0.002, 0.056, 0.026), Color(0.2, 0.2, 0.22))

## Nanopaste: an open steel tin brimming with glossy grey paste whipped to a peak, two
## small blue windows on its side.
static func _nanopaste(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var steel := Color(0.5, 0.51, 0.53)
	var R := 0.046
	var H := 0.05
	_lathe(k, "im:metal@0.35", _at(0, 0, 0), [Vector2(0, 0), Vector2(R - 0.003, 0), Vector2(R, 0.003), Vector2(R, H - 0.006), Vector2(R + 0.002, H - 0.004), Vector2(R + 0.002, H), Vector2(R - 0.002, H), Vector2(R - 0.002, H - 0.012)], 40, steel)
	ItemModels._torus(k, "im:metal@0.5", _at(0, 0.012, 0), R + 0.0002, 0.0009, 40, 4, steel.darkened(0.35))
	var prof: Array = []
	for i in 13:
		var t := float(i) / 12.0
		var rr := (R - 0.002) * (1.0 - t)
		var y := H - 0.006 + 0.008 * smoothstep(0.0, 0.3, t) + 0.022 * pow(t, 3.0)
		prof.append(Vector2(rr, y))
	var col := func(p: Vector3, _a: float, _t: float) -> Color:
		return Color(0.3, 0.32, 0.38)
	Provisions.lathe(k, "own:gloss", _at(0, 0, 0), PackedVector2Array(prof), 40, col, func(a: float, t: float, _p: Vector3) -> float: return 1.0 + 0.16 * sin(a * 2.0 + t * 12.0) * t)
	# A whipped swirl of paste coiling up to the peak.
	var sw := PackedVector3Array()
	var sr := PackedFloat32Array()
	for i in 41:
		var t := float(i) / 40.0
		var a := t * TAU * 2.2
		var rr := 0.03 * (1.0 - t)
		sw.append(Vector3(cos(a) * rr, H - 0.003 + 0.022 * pow(t, 1.4), sin(a) * rr))
		sr.append(lerpf(0.008, 0.002, t))
	ItemModels._tube(k, "own:gloss", _at(0, 0, 0), sw, sr, 10, Color(0.33, 0.35, 0.41))
	for s: float in [-1.0, 1.0]:
		var a := PI * 0.5 + s * 0.55
		k.bevel_box("im:paint", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * R, 0.012, sin(a) * R)), Vector3(0.008, 0.004, 0.003), 0.001, Color(0.2, 0.5, 0.95))

# --- Materials ----------------------------------------------------------------------------

static var _mats := {}
static var _mlock := Mutex.new()

static func mat(name: String) -> Material:
	_mlock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_mlock.unlock()
	return m

static func _std(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func _make(n: String) -> Material:
	match n:
		"pcb":
			# Solder mask: a thin glossy lacquer over the board.
			var m := _std(0.3, 0.0)
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			return m
		"plastic":
			return _std(0.42, 0.0)
		"gloss":
			var m := _std(0.32, 0.0)
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			return m
		"ceramic":
			return _std(0.6, 0.0)
		"tint", "lens":
			# Coloured glass and filled windows: see-through a little, glossy, unlit.
			var m := _std(0.05, 0.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.metallic_specular = 0.9
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			if n == "lens":
				m.rim_enabled = true
				m.rim = 0.3
			return m
		"frost":
			var m := _std(0.35, 0.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			return m
		"solar":
			# Cells under anti-reflective glass: they stay dark blue facing the sky.
			var m := _std(0.55, 0.0)
			m.metallic_specular = 0.08
			return m
		"carbon":
			return _patterned(n, 0.35, 0.1, 22.0, true)
		"hex":
			return _patterned(n, 0.35, 0.6, 16.0, false)
		"lattice":
			return _patterned(n, 0.35, 0.5, 9.0, false)
		"tread":
			return _patterned(n, 0.35, 0.85, 22.0, false)
	return _std(0.5, 0.0)

static func _patterned(n: String, rough: float, metal: float, scale: float, coat: bool) -> StandardMaterial3D:
	var m := _std(rough, metal)
	var tex := _pattern(n)
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 1.0
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	if coat:
		m.clearcoat_enabled = true
		m.clearcoat = 0.25
	return m

## A tiling height pattern as [albedo, normal map]: twill weave, honeycomb, diamond mesh,
## diamond tread plate.
static func _pattern(n: String) -> Array:
	var s := 128
	var hi := Image.create(s, s, false, Image.FORMAT_RGB8)
	var al := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var h := _height(n, float(x) / s, float(y) / s)
			hi.set_pixel(x, y, Color(h, h, h))
			var a := lerpf(0.5, 1.0, h) if n != "lattice" else lerpf(0.25, 1.0, h)
			al.set_pixel(x, y, Color(a, a, a))
	hi.bump_map_to_normal_map(4.0 if n != "tread" else 6.0)
	hi.generate_mipmaps()
	al.generate_mipmaps()
	return [ImageTexture.create_from_image(al), ImageTexture.create_from_image(hi)]

static func _height(n: String, u: float, v: float) -> float:
	match n:
		"carbon":
			# 2/2 twill: tows of 8 across a tile, each over two and under two, stepped.
			var cx := int(u * 8.0)
			var cy := int(v * 8.0)
			var fx := u * 8.0 - cx
			var fy := v * 8.0 - cy
			var warp := posmod(cx + cy, 4) < 2
			var f := fx if warp else fy
			var g := fy if warp else fx
			return 0.25 + 0.6 * sin(f * PI) + 0.08 * sin(g * PI * 6.0 + f * 3.0)
		"hex":
			# Seven cells across and eight rows down tile nearly square.
			var X := u * 7.0 * sqrt(3.0)
			var Y := v * 12.0
			var d1 := INF
			var d2 := INF
			var j0 := int(floor(Y / 1.5))
			for j in range(j0 - 1, j0 + 3):
				var shift := 0.0 if posmod(j, 2) == 0 else sqrt(3.0) * 0.5
				var i0 := int(floor((X - shift) / sqrt(3.0)))
				for i in range(i0 - 1, i0 + 3):
					var d := Vector2(X, Y).distance_to(Vector2(i * sqrt(3.0) + shift, j * 1.5))
					if d < d1:
						d2 = d1
						d1 = d
					elif d < d2:
						d2 = d
			return smoothstep(0.06, 0.22, d2 - d1)
		"lattice":
			var a := absf(fmod(u * 10.0 + v * 10.0, 1.0) - 0.5)
			var b := absf(fmod(u * 10.0 - v * 10.0 + 10.0, 1.0) - 0.5)
			return maxf(smoothstep(0.32, 0.46, a), smoothstep(0.32, 0.46, b)) * 0.85 + 0.1
		"tread":
			var cx := int(u * 4.0)
			var cy := int(v * 4.0)
			var p := Vector2(u * 4.0 - cx - 0.5, v * 4.0 - cy - 0.5)
			var ang := PI * 0.25 if posmod(cx + cy, 2) == 0 else -PI * 0.25
			var q := p.rotated(ang)
			var l := maxf(absf(q.x) - 0.26, 0.0)
			var d := Vector2(l, q.y).length()
			return 0.3 + 0.7 * (1.0 - smoothstep(0.05, 0.1, d))
	return 0.5
