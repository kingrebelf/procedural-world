class_name FishKit
## Fish and crab meshes for AquaticLife, one metre long (an instance's scale is its length).
## Fish lie along +Z, nose forward:
##   slim   torpedo-shaped (trout, sardine, mackerel, minnow)
##   deep   deep-bodied (perch, carp, bream, reef damsels)
##   disc   tall and flat (surgeonfish)
##   long   long and low with its fins set far back (pike)
## Fish vertices carry UV.x (0 at the tail to 1 at the snout) and UV.y (-1 along the belly
## to 1 along the back, fins beyond), which fish.gdshader paints the markings by;
## COLOR.r marks fins (1) and COLOR.g the paired fins that flutter.
## Crabs and crayfish face +Z too; their legs are COLOR.a 1, COLOR.r the leg's own step
## phase and UV.y how far out along the leg (crab.gdshader walks them).

const KINDS := ["slim", "deep", "disc", "long", "crab", "crayfish"]
## Body [height, width] as a share of the length; [dorsal fin height, anal fin height].
const SHAPE := {"slim": [0.21, 0.13, 0.09, 0.05], "deep": [0.34, 0.13, 0.12, 0.08], "disc": [0.62, 0.1, 0.16, 0.14], "long": [0.15, 0.12, 0.08, 0.06]}

static var _meshes: Dictionary = {}
static var _lock := Mutex.new()

static func mesh(kind: String) -> ArrayMesh:
	_lock.lock()
	var m: ArrayMesh = _meshes.get(kind)
	if m == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if kind == "crab":
			_crab(st)
		elif kind == "crayfish":
			_crayfish(st)
		else:
			_fish(st, kind)
		st.index()
		m = st.commit()
		_meshes[kind] = m
	_lock.unlock()
	return m

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	_v(st, a, n, ua, col)
	_v(st, b, n, ub, col)
	_v(st, c, n, uc, col)

# --- Fish ---------------------------------------------------------------------------

## Body height at t (0 the tail root .. 1 the snout), as a share of the deepest part.
static func _profile(t: float, kind: String) -> float:
	var peak := 0.62 if kind != "long" else 0.45
	var x := pow(t, log(0.5) / log(peak)) # moves the deepest point to `peak`
	var h := pow(sin(PI * x), 0.75 if kind == "disc" else 0.9)
	return maxf(h, 0.0) * (1.0 - 0.75 * pow(1.0 - t, 6.0)) + 0.16 * (1.0 - t) * (1.0 - t)

static func _fish(st: SurfaceTool, kind: String) -> void:
	var sh: Array = SHAPE[kind]
	var hh: float = sh[0] * 0.5
	var hw: float = sh[1] * 0.5
	var z0 := -0.32 # tail root (the tail fin runs on behind it)
	var z1 := 0.5
	var rings := 14
	var sides := 12
	var body := Color(0, 0, 0, 1)
	var pts: Array = []
	for j in rings + 1:
		var t := j / float(rings)
		var z := lerpf(z0, z1, t)
		var p := _profile(t, kind)
		var row: Array = []
		for i in sides + 1:
			var a := TAU * i / sides
			# A little flatter below than above, as most fish are.
			var y := sin(a) * hh * p * (1.0 if sin(a) > 0.0 else 0.85)
			var x := cos(a) * hw * p * (0.85 + 0.15 * cos(a) * cos(a))
			row.append([Vector3(x, y, z), Vector3(cos(a) / maxf(hw, 0.01), sin(a) / maxf(hh, 0.01), 0.0).normalized(), Vector2(t, sin(a))])
		pts.append(row)
	for j in rings:
		for i in sides:
			var a: Array = pts[j][i]
			var b: Array = pts[j][i + 1]
			var c: Array = pts[j + 1][i + 1]
			var d: Array = pts[j + 1][i]
			# Clockwise seen from outside (Godot's front face).
			for q in [a, c, b, a, d, c]:
				_v(st, q[0], q[1], q[2], body)
	# Fins: thin double-sided sheets (the shader draws both faces).
	var fin := Color(1, 0, 0, 1)
	var pair := Color(1, 1, 0, 1)
	var tail_h := hh * (1.6 if kind == "slim" or kind == "long" else (1.3 if kind == "deep" else 1.0))
	var fork := 0.07 if kind == "slim" else (0.03 if kind == "deep" else 0.0)
	var ty := hh * _profile(0.0, kind)
	var tl := -0.5
	var tm := tl + fork
	var root_t := Vector3(0, ty, z0 + 0.01)
	var root_b := Vector3(0, -ty, z0 + 0.01)
	var up := Vector3(0, tail_h, tl)
	var lo := Vector3(0, -tail_h, tl)
	var mid := Vector3(0, 0, tm)
	_tri(st, root_t, up, mid, Vector2(0.0, 0.2), Vector2(-0.25, 1.0), Vector2(-0.15, 0.0), fin)
	_tri(st, root_t, mid, root_b, Vector2(0.0, 0.2), Vector2(-0.15, 0.0), Vector2(0.0, -0.2), fin)
	_tri(st, root_b, mid, lo, Vector2(0.0, -0.2), Vector2(-0.15, 0.0), Vector2(-0.25, -1.0), fin)
	# Dorsal fin along the back, and the anal fin under the tail.
	var d0 := 0.32 if kind != "long" else 0.12
	var d1 := 0.62 if kind != "long" else 0.3
	_back_fin(st, kind, d0, d1, sh[2], 1.0, hh, z0, z1, fin)
	_back_fin(st, kind, 0.1 if kind != "long" else 0.1, 0.35 if kind != "disc" else 0.55, sh[3], -1.0, hh, z0, z1, fin)
	# Pectoral fins behind the gills, and the pelvic pair under the belly.
	for s in [-1.0, 1.0]:
		var t := 0.74
		var z := lerpf(z0, z1, t)
		var p := _profile(t, kind)
		var root := Vector3(s * hw * p * 0.9, -hh * p * 0.25, z)
		var ln := 0.12 + hh * 0.2
		_tri(st, root, root + Vector3(s * ln * 0.55, -ln * 0.35, -ln * 0.75), root + Vector3(0, -ln * 0.1, -ln * 0.3),
			Vector2(t, 0.0), Vector2(t - 0.1, -0.2), Vector2(t - 0.05, -0.1), pair)
		var tp := 0.52
		var zp := lerpf(z0, z1, tp)
		var pp := _profile(tp, kind)
		var rp := Vector3(s * hw * pp * 0.4, -hh * pp * 0.92, zp)
		_tri(st, rp, rp + Vector3(s * 0.03, -0.06, -0.08), rp + Vector3(0, -0.01, -0.06), Vector2(tp, -1.0), Vector2(tp - 0.08, -1.2), Vector2(tp - 0.06, -1.0), pair)

## A fin along the back (side 1) or the belly (side -1) between t0 and t1.
static func _back_fin(st: SurfaceTool, kind: String, t0: float, t1: float, height: float, side: float, hh: float, z0: float, z1: float, col: Color) -> void:
	var steps := 6
	for k in steps:
		var ta := lerpf(t0, t1, k / float(steps))
		var tb := lerpf(t0, t1, (k + 1) / float(steps))
		var ya := hh * _profile(ta, kind) * (1.0 if side > 0.0 else 0.85) * 0.96
		var yb := hh * _profile(tb, kind) * (1.0 if side > 0.0 else 0.85) * 0.96
		# Tallest at its leading edge, sloping back (spiny perch fins run more even).
		var fa := height * sin(PI * (0.15 + 0.85 * (1.0 - k / float(steps)))) * (1.0 if kind != "deep" else 0.8 + 0.2 * k / steps)
		var fb := height * sin(PI * (0.15 + 0.85 * (1.0 - (k + 1) / float(steps)))) * (1.0 if kind != "deep" else 0.8 + 0.2 * (k + 1) / steps)
		var a := Vector3(0, ya * side, lerpf(z0, z1, ta))
		var b := Vector3(0, yb * side, lerpf(z0, z1, tb))
		var c := Vector3(0, (yb + fb) * side, lerpf(z0, z1, tb) - fb * 0.4)
		var d := Vector3(0, (ya + fa) * side, lerpf(z0, z1, ta) - fa * 0.4)
		_tri(st, a, b, c, Vector2(ta, side), Vector2(tb, side), Vector2(tb, side * 1.5), col)
		_tri(st, a, c, d, Vector2(ta, side), Vector2(tb, side * 1.5), Vector2(ta, side * 1.5), col)

# --- Crabs and crayfish --------------------------------------------------------------

## A tube between points (for legs, claws and bodies).
static func _limb(st: SurfaceTool, pts: Array, rads: Array, col: Color, sides := 5, flat := 1.0) -> void:
	var n := pts.size()
	var rings: Array = []
	for i in n:
		var p: Vector3 = pts[i]
		var fwd: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := fwd.cross(Vector3.UP if absf(fwd.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(fwd).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var d := side * cos(a) + up * sin(a) * flat
			ring.append([p + d * float(rads[i]), (side * cos(a) + up * sin(a)).normalized(), float(i) / (n - 1)])
		rings.append(ring)
	for i in n - 1:
		for k in sides:
			var a: Array = rings[i][k]
			var b: Array = rings[i][(k + 1) % sides]
			var c: Array = rings[i + 1][(k + 1) % sides]
			var d: Array = rings[i + 1][k]
			for q in [a, b, c, a, c, d]:
				_v(st, q[0], q[1], Vector2(0.5, q[2]), col)
	var tip: Vector3 = pts[n - 1]
	var tn: Vector3 = (tip - (pts[n - 2] as Vector3)).normalized()
	for k in sides:
		var a: Array = rings[n - 1][k]
		var b: Array = rings[n - 1][(k + 1) % sides]
		_v(st, a[0], a[1], Vector2(0.5, 1.0), col)
		_v(st, b[0], b[1], Vector2(0.5, 1.0), col)
		_v(st, tip + tn * float(rads[n - 1]), tn, Vector2(0.5, 1.0), col)

## A dome (half an ellipsoid) for a shell.
static func _dome(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, notch := 0.0) -> void:
	var rings := 6
	var seg := 14
	for j in rings:
		for i in seg:
			var q: Array = []
			for o in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var ph: float = (PI * 0.5) * (j + o[1]) / rings
				var th: float = TAU * (i + o[0]) / seg
				# A shore crab's shell is broader in front, with a ridged front edge.
				var front := 1.0 + notch * maxf(sin(th), 0.0) * (0.12 + 0.05 * sin(th * 9.0))
				var d := Vector3(cos(th) * cos(ph) * front, sin(ph), sin(th) * cos(ph) * front)
				q.append([c + d * r, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()])
			for k in [0, 1, 2, 0, 2, 3]:
				_v(st, q[k][0], q[k][1], Vector2(0.5, 0.0), col)

## A shore crab: broad shell, four legs a side, two claws held forward.
static func _crab(st: SurfaceTool) -> void:
	var body := Color(1, 1, 1, 0)
	_dome(st, Vector3(0, 0.1, 0), Vector3(0.36, 0.13, 0.28), body, 1.0)
	_dome(st, Vector3(0, 0.1, 0), Vector3(0.34, -0.06, 0.26), body)
	for s in [-1.0, 1.0]:
		for i in 4:
			var z := 0.12 - i * 0.09
			var root := Vector3(s * 0.3, 0.08, z)
			var knee := Vector3(s * 0.52, 0.2, z - 0.03 * i)
			var foot := Vector3(s * 0.7, 0.0, z - 0.06 * i - 0.04)
			# Alternate legs step together (one side's 1st and 3rd with the other's 2nd and 4th).
			var ph := float((i + (1 if s > 0.0 else 0)) % 2) * 0.5
			_limb(st, [root, knee, foot], [0.03, 0.025, 0.01], Color(ph, 0, 0, 1), 4)
		# The claw: an arm forward, then a heavy pincer.
		var sh := Vector3(s * 0.22, 0.1, 0.22)
		var el := Vector3(s * 0.36, 0.14, 0.38)
		var wr := Vector3(s * 0.22, 0.12, 0.5)
		_limb(st, [sh, el, wr], [0.04, 0.045, 0.05], body, 5)
		_limb(st, [wr, wr + Vector3(-s * 0.06, 0.02, 0.12), wr + Vector3(-s * 0.1, 0.0, 0.2)], [0.065, 0.05, 0.012], body, 6, 0.7)
		_limb(st, [wr + Vector3(0, -0.02, 0.02), wr + Vector3(-s * 0.08, -0.05, 0.14)], [0.03, 0.01], body, 4)
		# Eyes on short stalks.
		_limb(st, [Vector3(s * 0.07, 0.18, 0.24), Vector3(s * 0.09, 0.26, 0.28)], [0.02, 0.025], Color(0.05, 0.05, 0.05, 0), 4)

## A crayfish: a long jointed body and fanned tail, big claws reaching forward.
static func _crayfish(st: SurfaceTool) -> void:
	var body := Color(1, 1, 1, 0)
	# Head and thorax shell, then the tail segments tapering back to the fan.
	_limb(st, [Vector3(0, 0.08, 0.32), Vector3(0, 0.1, 0.18), Vector3(0, 0.1, 0.0), Vector3(0, 0.09, -0.08)], [0.03, 0.085, 0.095, 0.08], body, 8, 0.85)
	_limb(st, [Vector3(0, 0.09, -0.08), Vector3(0, 0.08, -0.2), Vector3(0, 0.06, -0.32), Vector3(0, 0.05, -0.4)], [0.08, 0.07, 0.055, 0.04], body, 8, 0.75)
	for k in 5:
		var a := (k - 2) * 0.32
		var tip := Vector3(sin(a) * 0.13, 0.04, -0.4 - cos(a) * 0.13)
		_limb(st, [Vector3(0, 0.05, -0.4), tip], [0.03, 0.035], body, 4, 0.3)
	for s in [-1.0, 1.0]:
		for i in 4:
			var z := 0.1 - i * 0.06
			var ph := float((i + (1 if s > 0.0 else 0)) % 2) * 0.5
			_limb(st, [Vector3(s * 0.06, 0.06, z), Vector3(s * 0.17, 0.11, z - 0.02), Vector3(s * 0.25, 0.0, z - 0.04)], [0.015, 0.012, 0.006], Color(ph, 0, 0, 1), 4)
		_limb(st, [Vector3(s * 0.07, 0.08, 0.2), Vector3(s * 0.16, 0.1, 0.32), Vector3(s * 0.14, 0.08, 0.45)], [0.025, 0.03, 0.035], body, 5)
		_limb(st, [Vector3(s * 0.14, 0.08, 0.45), Vector3(s * 0.12, 0.08, 0.58), Vector3(s * 0.09, 0.07, 0.66)], [0.05, 0.04, 0.01], body, 6, 0.6)
		# Long antennae sweeping back.
		_limb(st, [Vector3(s * 0.02, 0.1, 0.33), Vector3(s * 0.12, 0.14, 0.5), Vector3(s * 0.3, 0.12, 0.6)], [0.006, 0.004, 0.002], body, 3)
