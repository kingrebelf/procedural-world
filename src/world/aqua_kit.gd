class_name AquaKit
## Water plants and reef life, each an instanced clump drawn with aquatic.gdshader:
##   aq_pad_N   a colony of lily pads floating on a still lake (N 0: white water lilies,
##              1: pink ones, 2: pads and closed buds only)
##   aq_reed    reeds and bulrushes (cattails) standing in the shallows of a lake shore
##   aq_kelp    a kelp plant one unit tall (scaled to reach up toward the surface)
##   aq_coral_branch, aq_coral_brain, aq_coral_table, aq_coral_fan   reef-building corals
##   aq_sponge  a cluster of tube sponges
##   aq_anemone a sea anemone, its tentacles waving
##   aq_star, aq_urchin   a starfish and a sea urchin on the sea bed
## Vertex COLOR: rgb the part's own shade times SHADE_SCALE (a multiplier on the instance's
## tint), or with a = 0 a fixed colour (petals, cattail heads, eyes of the reef). UV.y is how
## far up the plant a vertex is (what sways), UV2 the distance over which it thins out.
## Every mesh is about one metre across, so an instance's scale is its size in metres.

const SPECIES := ["aq_pad_0", "aq_pad_1", "aq_pad_2", "aq_reed", "aq_kelp", "aq_coral_branch", "aq_coral_brain",
	"aq_coral_table", "aq_coral_fan", "aq_sponge", "aq_anemone", "aq_star", "aq_urchin"]
## [thinning starts, all gone] in metres from the camera.
const RANGE := {"aq_pad": Vector2(70.0, 150.0), "aq_reed": Vector2(55.0, 125.0), "aq_kelp": Vector2(55.0, 105.0),
	"aq_coral": Vector2(45.0, 95.0), "aq_sponge": Vector2(40.0, 85.0), "aq_anemone": Vector2(25.0, 55.0),
	"aq_star": Vector2(18.0, 40.0), "aq_urchin": Vector2(18.0, 40.0)}
## How an instance moves (INSTANCE_CUSTOM.a, whole part; the fraction is its glow):
## in the wind, in the current, or still (floating pads bob with the water).
enum { SWAY_WIND, SWAY_CURRENT, STILL }
const SWAY := {"aq_pad": STILL, "aq_reed": SWAY_WIND, "aq_kelp": SWAY_CURRENT, "aq_coral": STILL,
	"aq_coral_fan": SWAY_CURRENT, "aq_sponge": STILL, "aq_anemone": SWAY_CURRENT, "aq_star": STILL, "aq_urchin": STILL}
const SHADE_SCALE := 0.7

static var _meshes: Dictionary = {}
static var _lock := Mutex.new()
static var material: ShaderMaterial

static func is_aqua(species: String) -> bool:
	return species.begins_with("aq_")

static func _family(species: String) -> String:
	if species.begins_with("aq_pad"):
		return "aq_pad"
	if species.begins_with("aq_coral"):
		return "aq_coral"
	return species

static func range_of(species: String) -> Vector2:
	return RANGE[_family(species)]

static func sway_of(species: String) -> int:
	return SWAY.get(species, SWAY[_family(species)])

## The shared material (made on the main thread, by ChunkNode, before any chunk is built).
static func get_material() -> ShaderMaterial:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = load("res://src/world/aquatic.gdshader")
	return material

static func mesh(species: String) -> ArrayMesh:
	_lock.lock()
	var m: ArrayMesh = _meshes.get(species)
	if m == null:
		m = _build(species)
		_meshes[species] = m
	_lock.unlock()
	return m

static func _build(species: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(species)
	var rg := range_of(species)
	match species:
		"aq_pad_0", "aq_pad_1", "aq_pad_2":
			_pads(st, r, rg, int(species.substr(7)))
		"aq_reed":
			_reeds(st, r, rg)
		"aq_kelp":
			_kelp(st, r, rg)
		"aq_coral_branch":
			_staghorn(st, r, rg)
		"aq_coral_brain":
			_brain(st, r, rg)
		"aq_coral_table":
			_table(st, r, rg)
		"aq_coral_fan":
			_fan(st, r, rg)
		"aq_sponge":
			_sponges(st, r, rg)
		"aq_anemone":
			_anemone(st, r, rg)
		"aq_star":
			_star(st, r, rg)
		"aq_urchin":
			_urchin(st, r, rg)
	st.index()
	return st.commit()

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, u: float, t: float, col: Color, rg: Vector2) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(Vector2(u, t))
	st.set_uv2(rg)
	st.add_vertex(p)

## A shade multiplier for tinted parts (stored scaled, as vertex colours stop at 1).
static func _shade(v: float, warm := 1.0) -> Color:
	return Color(v * SHADE_SCALE, v * SHADE_SCALE, v * warm * SHADE_SCALE, 1.0)

## A fixed colour (not tinted by the instance).
static func _own(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.0)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, ta: float, tb: float, tc: float, td: float, rg: Vector2) -> void:
	_v(st, a, na, 0.0, ta, ca, rg)
	_v(st, b, nb, 1.0, tb, cb, rg)
	_v(st, c, nc, 1.0, tc, cc, rg)
	_v(st, a, na, 0.0, ta, ca, rg)
	_v(st, c, nc, 1.0, tc, cc, rg)
	_v(st, d, nd, 0.0, td, cd, rg)

## A tapering tube along `pts` (radii `rads`), `sides` around, shaded from `c0` at its
## root to `c1` at its tip; `t0`, `t1` its sway height at each end. Closed at the tip.
static func _tube(st: SurfaceTool, pts: Array, rads: Array, sides: int, c0: Color, c1: Color, t0: float, t1: float, rg: Vector2) -> void:
	var n := pts.size()
	var rings: Array = []
	for i in n:
		var p: Vector3 = pts[i]
		var fwd: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := fwd.cross(Vector3(0.31, 0.0, 0.95) if absf(fwd.y) > 0.9 else Vector3.UP).normalized()
		var up := side.cross(fwd).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var d := side * cos(a) + up * sin(a)
			ring.append([p + d * float(rads[i]), d])
		rings.append(ring)
	for i in n - 1:
		var fa := float(i) / (n - 1)
		var fb := float(i + 1) / (n - 1)
		var ca := c0.lerp(c1, fa)
		var cb := c0.lerp(c1, fb)
		for k in sides:
			var k2 := (k + 1) % sides
			var a0: Array = rings[i][k]
			var a1: Array = rings[i][k2]
			var b0: Array = rings[i + 1][k]
			var b1: Array = rings[i + 1][k2]
			_quad(st, a0[0], a1[0], b1[0], b0[0], a0[1], a1[1], b1[1], b0[1], ca, ca, cb, cb,
				lerpf(t0, t1, fa), lerpf(t0, t1, fa), lerpf(t0, t1, fb), lerpf(t0, t1, fb), rg)
	var tip: Vector3 = pts[n - 1]
	var tn: Vector3 = (tip - (pts[n - 2] as Vector3)).normalized()
	for k in sides:
		var a0: Array = rings[n - 1][k]
		var a1: Array = rings[n - 1][(k + 1) % sides]
		_v(st, a0[0], a0[1], 0.0, t1, c1, rg)
		_v(st, a1[0], a1[1], 1.0, t1, c1, rg)
		_v(st, tip + tn * float(rads[n - 1]) * 0.6, tn, 0.5, t1, c1, rg)

## One flat, curved leaf or ribbon from `root` (like a grass blade, wider). Returns its tip.
static func _ribbon(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, root: Vector3, h: float, w: float, lean: float, segs: int,
		col: Color, wavy := 0.0, t_scale := 1.0, pointed := true) -> Vector3:
	var basis := Basis(Vector3.UP, r.randf() * TAU)
	var twist := r.randf_range(-0.5, 0.5)
	var pts: Array = []
	for i in segs + 1:
		var t := i / float(segs)
		var c := root + basis * Vector3(sin(t * twist) * lean * 0.3, t * h, t * t * lean)
		var hw := w * (1.0 - pow(t, 2.2)) if pointed else w * (0.55 + 0.45 * sin(t * PI))
		hw *= 1.0 + sin(t * 23.0 + root.x * 40.0) * wavy
		var side := basis * Vector3(cos(t * twist), 0, -sin(t * twist))
		var shade := col * lerpf(0.8, 1.1, t)
		shade.a = col.a
		pts.append([c - side * hw, c + side * hw, t * t_scale, shade])
	var n := basis * Vector3(0, 0.3, -1).normalized()
	for i in segs:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		_quad(st, a[0], a[1], b[1], b[0], n, n, n, n, a[3], a[3], b[3], b[3], a[2], a[2], b[2], b[2], rg)
	var top: Array = pts[segs]
	return (top[0] + top[1]) * 0.5

# --- Lily pads and reeds -------------------------------------------------------

## A colony of floating pads, a little apart, some overlapping; flowers of `kind`.
static func _pads(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, kind: int) -> void:
	var placed: Array = []
	for i in 9:
		var rad := r.randf_range(0.11, 0.27)
		var at := Vector3.ZERO
		for tries in 12:
			var a := r.randf() * TAU
			var d := sqrt(r.randf()) * 0.55
			at = Vector3(cos(a) * d, 0.0, sin(a) * d)
			var ok := true
			for p in placed:
				if Vector2(at.x - p[0].x, at.z - p[0].z).length() < (rad + float(p[1])) * 0.75:
					ok = false
					break
			if ok:
				break
		# Overlapping pads stack a hair apart, so they never flicker.
		at.y = 0.004 * placed.size()
		placed.append([at, rad])
		_pad(st, r, rg, at, rad)
	var petals: Array = [[Color(0.95, 0.94, 0.9), Color(0.96, 0.78, 0.2)], [Color(0.93, 0.62, 0.72), Color(0.95, 0.74, 0.22)]]
	if kind < 2:
		for i in r.randi_range(1, 3):
			var p: Array = placed[r.randi() % placed.size()]
			var at: Vector3 = p[0] + Vector3(r.randf_range(-0.05, 0.05), 0.04, r.randf_range(-0.05, 0.05))
			_lily(st, r, rg, at, r.randf_range(0.08, 0.11), petals[kind][0], petals[kind][1], 0.0)
	for i in r.randi_range(1, 2):
		# A closed bud on its stalk, just clear of the water.
		var p: Array = placed[r.randi() % placed.size()]
		var at: Vector3 = p[0] + Vector3(float(p[1]) * 0.6, 0.0, 0.0)
		var bud := _own(Color(0.42, 0.5, 0.22) if kind == 2 else (petals[kind][0] as Color).lerp(Color(0.4, 0.5, 0.2), 0.45))
		_tube(st, [at, at + Vector3(0.0, 0.05, 0.0), at + Vector3(0.0, 0.09, 0.008)], [0.018, 0.024, 0.004], 6, bud, bud, 0.0, 0.0, rg)

## One pad: a slightly cupped disc with the notch to its middle; veins and a paler,
## sometimes yellowing rim come from the shades.
static func _pad(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, rad: float) -> void:
	var notch := r.randf() * TAU
	var seg := 22
	var gap := 0.22
	var old := r.randf() < 0.25
	var mid := _shade(r.randf_range(0.85, 1.05))
	for i in seg:
		var a0 := notch + gap * 0.5 + (TAU - gap) * i / seg
		var a1 := notch + gap * 0.5 + (TAU - gap) * (i + 1) / seg
		# The rim curls up a little; veins are a faint darker line every few segments.
		var vein := 0.9 if i % 3 == 0 else 1.0
		var rim := _shade(r.randf_range(0.9, 1.15) * vein, 0.85 if old else 1.0)
		if old:
			rim = Color(rim.r * 1.25, rim.g * 1.1, rim.b * 0.6, 1.0)
		var p0 := at + Vector3(cos(a0) * rad, 0.012, sin(a0) * rad)
		var p1 := at + Vector3(cos(a1) * rad, 0.012, sin(a1) * rad)
		var m0 := at + Vector3(cos(a0) * rad * 0.55, 0.002, sin(a0) * rad * 0.55)
		var m1 := at + Vector3(cos(a1) * rad * 0.55, 0.002, sin(a1) * rad * 0.55)
		_v(st, at, Vector3.UP, 0.5, 0.0, mid, rg)
		_v(st, m0, Vector3.UP, 0.5, 0.0, mid, rg)
		_v(st, m1, Vector3.UP, 0.5, 0.0, mid, rg)
		_quad(st, m0, p0, p1, m1, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, mid, rim, rim, mid, 0.0, 0.0, 0.0, 0.0, rg)

## A water lily in bloom: two rings of pointed petals opening from a golden heart.
static func _lily(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, rad: float, petal: Color, heart: Color, t: float) -> void:
	var turn := r.randf() * TAU
	for ring in 2:
		var count := 9 if ring == 0 else 7
		var open := 1.05 if ring == 0 else 0.6 # how far the petals fall open (radians from upright)
		var ln := rad * (1.0 if ring == 0 else 0.8)
		for i in count:
			var a := turn + TAU * (i + ring * 0.5) / count
			var out := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-sin(a), 0.0, cos(a))
			var dir := (out * sin(open) + Vector3.UP * cos(open)).normalized()
			var tip := at + dir * ln
			var m := at + dir * ln * 0.45
			var w := ln * 0.24
			var n := dir.cross(side).normalized()
			if n.y < 0.0:
				n = -n
			var pc := _own(petal.lerp(Color(1, 1, 1), 0.15 * ring))
			var base := _own(petal.lerp(heart, 0.25))
			_v(st, at, n, 0.5, t, base, rg)
			_v(st, m - side * w, n, 0.0, t, pc, rg)
			_v(st, m + side * w, n, 1.0, t, pc, rg)
			_v(st, m - side * w, n, 0.0, t, pc, rg)
			_v(st, tip, n, 0.5, t, pc, rg)
			_v(st, m + side * w, n, 1.0, t, pc, rg)
	var hc := _own(heart)
	_tube(st, [at, at + Vector3(0.0, rad * 0.32, 0.0)], [rad * 0.24, rad * 0.2], 8, hc, hc, t, t, rg)

## Reeds: tall leaves leaning every way, and a few bulrush stalks with their brown heads.
static func _reeds(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	for i in 16:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.32
		var root := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var col := _shade(r.randf_range(0.8, 1.12))
		if r.randf() < 0.2:
			col = Color(col.r * 1.3, col.g * 1.15, col.b * 0.55, 1.0) # dry, straw-tipped
		_ribbon(st, r, rg, root, r.randf_range(0.8, 1.7), r.randf_range(0.012, 0.022), r.randf_range(0.1, 0.45), 6, col)
	for i in r.randi_range(3, 5):
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 0.22
		var root := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var h := r.randf_range(1.2, 1.75)
		var lean := Vector3(r.randf_range(-0.08, 0.08), 0.0, r.randf_range(-0.08, 0.08))
		var stem := _shade(0.95)
		var top := root + Vector3(0, h, 0) + lean
		_tube(st, [root, root + Vector3(0, h * 0.5, 0) + lean * 0.3, top], [0.008, 0.007, 0.005], 5, stem, stem, 0.0, 1.0, rg)
		# The velvety brown head a little below the tip, then a bare spike.
		var hs := h * 0.82
		var head := _own(Color(0.33, 0.21, 0.12).lerp(Color(0.42, 0.29, 0.17), r.randf()))
		var h0 := root + Vector3(0, hs, 0) + lean * pow(hs / h, 2.0)
		var h1 := root + Vector3(0, hs + 0.17, 0) + lean * pow((hs + 0.17) / h, 2.0)
		_tube(st, [h0, h0.lerp(h1, 0.15), h0.lerp(h1, 0.85), h1], [0.012, 0.024, 0.024, 0.012], 7, head, head, hs / h, (hs + 0.17) / h, rg)

# --- Sea plants and reef ---------------------------------------------------------

## Kelp: a few stipes rising from one holdfast, long wavy blades along them, all one
## unit tall (an instance is scaled to the depth).
static func _kelp(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	for i in 4:
		var a := r.randf() * TAU
		var root := Vector3(cos(a) * 0.08, 0.0, sin(a) * 0.08)
		var col := _shade(r.randf_range(0.85, 1.1))
		var lean := r.randf_range(0.05, 0.18)
		var top := _ribbon(st, r, rg, root, r.randf_range(0.75, 1.0), 0.012, lean, 12, col, 0.0, 1.0, false)
		# Blades off the stipe, each on its own lean.
		for k in 7:
			var t := r.randf_range(0.2, 0.95)
			var at := root.lerp(top, t)
			_ribbon(st, r, rg, at, r.randf_range(0.12, 0.22), r.randf_range(0.03, 0.05), r.randf_range(0.04, 0.1), 5,
				_shade(r.randf_range(0.8, 1.15), 0.9), 0.25, t + 0.15, false)

## Staghorn coral: thick antler branches forking up and out, paler at the growing tips.
static func _staghorn(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	for i in 7:
		var a := TAU * i / 7.0 + r.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6).normalized()
		_branch(st, r, rg, Vector3(cos(a) * 0.06, 0.0, sin(a) * 0.06), dir, 0.36, 0.075, 2)

static func _branch(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, dir: Vector3, ln: float, rad: float, depth: int) -> void:
	var end := at + dir * ln
	var mid := at + dir * ln * 0.5 + Vector3(r.randf_range(-0.02, 0.02), 0.0, r.randf_range(-0.02, 0.02))
	var tip_col := _shade(1.3, 0.95) if depth == 0 else _shade(1.0)
	_tube(st, [at, mid, end], [rad, rad * 0.85, rad * 0.7], 5, _shade(0.8), tip_col, 0.0, 0.0, rg)
	if depth == 0:
		return
	for k in 2:
		var out := Vector3(r.randf_range(-1, 1), r.randf_range(0.4, 1.1), r.randf_range(-1, 1)).normalized()
		_branch(st, r, rg, end, (dir + out * 0.6).normalized(), ln * r.randf_range(0.6, 0.85), rad * 0.7, depth - 1)

## Brain coral: a squat dome ridged with winding grooves.
static func _brain(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	var rings := 12
	var seg := 28
	var off := r.randf() * 10.0
	var pts: Array = []
	for j in rings + 1:
		var ph := (PI * 0.5) * j / rings
		var row: Array = []
		for i in seg + 1:
			var th := TAU * i / seg
			var d := Vector3(cos(th) * cos(ph), sin(ph) * 0.75, sin(th) * cos(ph))
			var g := sin(th * 9.0 + sin(ph * 6.0 + off) * 2.5) * cos(ph * 10.0 + cos(th * 4.0) * 1.5)
			var groove := smoothstep(0.2, 0.9, absf(g))
			row.append([d * 0.5 * (1.0 - groove * 0.05), d.normalized(), _shade(lerpf(1.08, 0.62, groove))])
		pts.append(row)
	for j in rings:
		for i in seg:
			var a: Array = pts[j][i]
			var b: Array = pts[j][i + 1]
			var c: Array = pts[j + 1][i + 1]
			var d: Array = pts[j + 1][i]
			_quad(st, a[0], b[0], c[0], d[0], a[1], b[1], c[1], d[1], a[2], b[2], c[2], d[2], 0.0, 0.0, 0.0, 0.0, rg)

## Table coral: a short stalk under a wide, flat plate with a ragged edge.
static func _table(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	_tube(st, [Vector3.ZERO, Vector3(0, 0.12, 0), Vector3(0, 0.22, 0)], [0.09, 0.07, 0.11], 7, _shade(0.75), _shade(0.9), 0.0, 0.0, rg)
	var seg := 26
	var y := 0.24
	var rads: Array = []
	for i in seg:
		rads.append(0.5 * (0.8 + 0.2 * sin(i * 1.7) + r.randf_range(-0.08, 0.08)))
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r0: float = rads[i]
		var r1: float = rads[(i + 1) % seg]
		var p0 := Vector3(cos(a0) * r0, y + 0.03, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r1, y + 0.03, sin(a1) * r1)
		var c := Vector3(0, y + 0.01, 0)
		var edge := _shade(1.2, 0.95)
		_v(st, c, Vector3.UP, 0.5, 0.0, _shade(0.95), rg)
		_v(st, p0, Vector3.UP, 0.5, 0.0, edge, rg)
		_v(st, p1, Vector3.UP, 0.5, 0.0, edge, rg)
		# The underside, darker.
		var u0 := p0 - Vector3(0, 0.035, 0)
		var u1 := p1 - Vector3(0, 0.035, 0)
		_v(st, c - Vector3(0, 0.03, 0), Vector3.DOWN, 0.5, 0.0, _shade(0.55), rg)
		_v(st, u1, Vector3.DOWN, 0.5, 0.0, _shade(0.6), rg)
		_v(st, u0, Vector3.DOWN, 0.5, 0.0, _shade(0.6), rg)
		var out := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_quad(st, u0, u1, p1, p0, out, out, out, out, edge, edge, edge, edge, 0.0, 0.0, 0.0, 0.0, rg)

## Sea fan: a flat lattice of fine branches in one plane, facing the current.
static func _fan(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	# Two trunks from one foot, fanning into a dense net of twigs.
	_fan_branch(st, r, rg, Vector3.ZERO, Vector3(-0.25, 1, 0).normalized(), 0.26, 0.03, 6)
	_fan_branch(st, r, rg, Vector3.ZERO, Vector3(0.25, 1, 0).normalized(), 0.26, 0.03, 6)

static func _fan_branch(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, dir: Vector3, ln: float, w: float, depth: int) -> void:
	var end := at + dir * ln
	var n := Vector3(0, 0, 1)
	var side := dir.cross(n).normalized() * w
	var col := _shade(lerpf(1.15, 0.85, depth / 5.0))
	_quad(st, at - side, at + side, end + side * 0.75, end - side * 0.75, n, n, n, n, col, col, col, col,
		at.y, at.y, end.y, end.y, rg)
	if depth == 0:
		return
	for k in 2:
		var turn := r.randf_range(0.25, 0.6) * (1.0 if k == 0 else -1.0)
		var nd := dir.rotated(n, turn)
		if nd.y < 0.3:
			nd = dir.rotated(n, -turn * 0.4)
		# Keep the fan rounded: branches leaning far out stay short.
		_fan_branch(st, r, rg, end, nd, ln * r.randf_range(0.65, 0.85), w * 0.75, depth - 1)

## Tube sponges: open-topped tubes in a cluster, dark inside.
static func _sponges(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	for i in r.randi_range(4, 6):
		var a := r.randf() * TAU
		var d := r.randf_range(0.0, 0.2)
		var root := Vector3(cos(a) * d, 0.0, sin(a) * d)
		var h := r.randf_range(0.25, 0.7)
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.1)
		var rad := r.randf_range(0.05, 0.08)
		var sides := 9
		var top := root + Vector3(0, h, 0) + lean
		var mid := root + Vector3(0, h * 0.5, 0) + lean * 0.3
		# The outside, then the inside (a tube of the same rings, facing in, dark).
		var outer := [root, mid, top]
		var rads := [rad * 0.8, rad, rad * 1.1]
		_open_tube(st, outer, rads, sides, _shade(0.85), _shade(1.1), false, rg)
		_open_tube(st, outer, [rad * 0.6, rad * 0.8, rad * 0.95], sides, _shade(0.2), _shade(0.35), true, rg)
		# The lip joining them.
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var o0 := top + Vector3(cos(a0), 0, sin(a0)) * rad * 1.1
			var o1 := top + Vector3(cos(a1), 0, sin(a1)) * rad * 1.1
			var i0 := top + Vector3(cos(a0), 0, sin(a0)) * rad * 0.95
			var i1 := top + Vector3(cos(a1), 0, sin(a1)) * rad * 0.95
			var lip := _shade(1.15)
			_quad(st, o0, o1, i1, i0, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, lip, lip, lip, lip, 0.0, 0.0, 0.0, 0.0, rg)

static func _open_tube(st: SurfaceTool, pts: Array, rads: Array, sides: int, c0: Color, c1: Color, inward: bool, rg: Vector2) -> void:
	for i in pts.size() - 1:
		var pa: Vector3 = pts[i]
		var pb: Vector3 = pts[i + 1]
		var ca := c0.lerp(c1, float(i) / (pts.size() - 1))
		var cb := c0.lerp(c1, float(i + 1) / (pts.size() - 1))
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var s := -1.0 if inward else 1.0
			var q := [pa + d0 * float(rads[i]), pa + d1 * float(rads[i]), pb + d1 * float(rads[i + 1]), pb + d0 * float(rads[i + 1])]
			if inward:
				_quad(st, q[1], q[0], q[3], q[2], d1 * s, d0 * s, d0 * s, d1 * s, ca, ca, cb, cb, 0.0, 0.0, 0.0, 0.0, rg)
			else:
				_quad(st, q[0], q[1], q[2], q[3], d0, d1, d1, d0, ca, ca, cb, cb, 0.0, 0.0, 0.0, 0.0, rg)

## A sea anemone: a stout column crowned with a ring of tapering tentacles.
static func _anemone(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	var col_h := 0.14
	_tube(st, [Vector3.ZERO, Vector3(0, col_h * 0.6, 0), Vector3(0, col_h, 0)], [0.1, 0.08, 0.1], 10, _shade(0.6), _shade(0.75), 0.0, 0.0, rg)
	for i in 34:
		var a := TAU * i / 34.0 + r.randf_range(-0.05, 0.05)
		var d := r.randf_range(0.03, 0.095)
		var root := Vector3(cos(a) * d, col_h, sin(a) * d)
		var out := Vector3(cos(a), 0, sin(a))
		var ln := r.randf_range(0.14, 0.24)
		var mid := root + (out * 0.5 + Vector3.UP).normalized() * ln * 0.5
		var tip := mid + (out * 0.9 + Vector3.UP * 0.6).normalized() * ln * 0.5
		# Tips a paler shade of the body, as real ones are.
		_tube(st, [root, mid, tip], [0.012, 0.009, 0.004], 4, _shade(0.95), _shade(1.35, 0.9), 0.1, 1.0, rg)

## A five-armed starfish lying flat, its arms a little curled.
static func _star(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	for i in 5:
		var a := TAU * i / 5.0 + r.randf_range(-0.12, 0.12)
		var out := Vector3(cos(a), 0, sin(a))
		var curl := r.randf_range(-0.3, 0.3)
		var pts := [Vector3(0, 0.05, 0), out * 0.22 + Vector3(0, 0.04, 0), out.rotated(Vector3.UP, curl * 0.5) * 0.4 + Vector3(0, 0.025, 0),
			out.rotated(Vector3.UP, curl) * 0.5 + Vector3(0, 0.015, 0)]
		_tube(st, pts, [0.08, 0.055, 0.035, 0.012], 6, _shade(0.9), _shade(1.1), 0.0, 0.0, rg)

## A sea urchin: a dark ball bristling with long spines.
static func _urchin(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2) -> void:
	var c := Vector3(0, 0.12, 0)
	for i in 60:
		var y := r.randf_range(-0.2, 1.0)
		var a := r.randf() * TAU
		var d := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
		var root := c + d * 0.12
		_tube(st, [root, root + d * r.randf_range(0.14, 0.22)], [0.008, 0.0015], 3, _shade(0.8), _shade(1.0), 0.0, 0.0, rg)
	var body: Array = []
	var rads: Array = []
	for j in 7:
		var t := j / 6.0
		body.append(c + Vector3(0, -0.12 + t * 0.24, 0))
		rads.append(0.13 * sin(PI * (0.08 + t * 0.84)))
	_tube(st, body, rads, 10, _shade(0.7), _shade(0.85), 0.0, 0.0, rg)
