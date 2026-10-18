class_name AlienMatter
## Alien materials and ammunition: chitin, gels, living metal, crystal thread, organs and
## glands, seeds, the cells and shards alien weapons fire. Only alien matter may glow, faintly.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.

const BUILD := {
	"void_cell": "_void_cell", "bio_ammo": "_bio_ammo", "star_shards": "_star_shards",
	"psi_crystal": "_psi_crystal", "chitin_spikes": "_chitin_spikes", "ion_core": "_ion_core",
	"chitin_plate": "_chitin_plate", "bio_gel_alien": "_bio_gel", "crystal_thread": "_crystal_thread",
	"living_metal": "_living_metal", "dark_matter": "_dark_matter", "light_essence": "_light_essence",
	"alien_circuit": "_alien_circuit", "grav_core": "_grav_core", "warp_coil": "_warp_coil",
	"ai_shard": "_ai_shard", "bio_battery": "_bio_battery", "phase_lens": "_phase_lens",
	"eye_xeno": "_eye_xeno", "spore_sac": "_spore_sac", "venom_gland": "_venom_gland",
	"scale_dragon": "_scale_dragon", "seed_glow": "_seed_glow",
}

const GUNMETAL := Color(0.2, 0.2, 0.23)
const BRONZE := Color(0.74, 0.55, 0.3)
const GOLD := Color(0.86, 0.66, 0.32)

## The faint light each glowing material gives off.
const HUE := {
	"violet": Color(0.5, 0.25, 1.0), "purple": Color(0.75, 0.3, 1.0), "blue": Color(0.3, 0.5, 1.0),
	"cyan": Color(0.3, 0.85, 1.0), "teal": Color(0.2, 0.9, 0.75), "gold": Color(1.0, 0.6, 0.1),
	"green": Color(0.65, 0.9, 0.2),
}

static var _mats: Dictionary = {}
static var _lock := Mutex.new()

# --- Shared shapes ----------------------------------------------------------------------

## A faceted solid about +Y: `prof` is (radius, height) bottom to top, each ring a polygon
## of `sides`, flat faces between (crystals, gem tips, cut caps). sx/sz squash it.
static func _facet(k: MeshKit, m: String, xf: Transform3D, prof: Array, sides: int, col: Color, sx := 1.0, sz := 1.0, rot := 0.0) -> void:
	var rings: Array = []
	var y0: float = (prof[0] as Vector2).y
	var y1: float = (prof[prof.size() - 1] as Vector2).y
	var mid := Vector3(0, (y0 + y1) * 0.5, 0)
	for p: Vector2 in prof:
		var ring := PackedVector3Array()
		for s in sides:
			var a := rot + TAU * s / sides
			ring.append(Vector3(cos(a) * p.x * sx, p.y, sin(a) * p.x * sz))
		rings.append(ring)
	for i in prof.size() - 1:
		var lo: PackedVector3Array = rings[i]
		var hi: PackedVector3Array = rings[i + 1]
		for s in sides:
			var s2 := (s + 1) % sides
			var face := (lo[s] + lo[s2] + hi[s] + hi[s2]) * 0.25
			ItemModels._quad(k, m, xf, lo[s], lo[s2], hi[s2], hi[s], face - mid, col)

## A round lump coloured in mottled patches of `a` and `b` (pods, spores).
static func _blob(k: MeshKit, m: String, xf: Transform3D, r: float, a: Color, b: Color, freq: float, squash := 1.0) -> void:
	Provisions.lathe(k, m, xf, Provisions._sphere(r, 12, squash), 18, func(p: Vector3, _a: float, _t: float) -> Color:
		return a.lerp(b, clampf(0.5 + Provisions._nz(p, freq) * 1.4, 0.0, 1.0)))

## Raised veins running up a lathe body (profile `prof` under `xf`) at the given angles,
## wandering a little, from t0 to t1 of the way up.
static func _veins(k: MeshKit, m: String, xf: Transform3D, prof: PackedVector2Array, angles: Array, col: Color, rad: float, wander: float, t0 := 0.08, t1 := 0.92) -> void:
	var n := prof.size()
	for a0: float in angles:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var i0 := int(t0 * (n - 1))
		var i1 := int(t1 * (n - 1))
		for i in range(i0, i1 + 1):
			var p := prof[i]
			var a := a0 + wander * sin(p.y * 160.0 + a0 * 3.0)
			path.append(xf * Vector3(cos(a) * (p.x + rad * 0.6), p.y, sin(a) * (p.x + rad * 0.6)))
			var e := float(i - i0) / maxf(i1 - i0, 1)
			radii.append(rad * (0.5 + 0.5 * sin(PI * e)))
		ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 5, col)

## A sheet with thickness over a grid: `f(u, v)` the mid-surface, `col(u, v)` its colour
## (the underside a shade darker), smooth shaded, the cut rim round it.
static func _grid(k: MeshKit, m: String, xf: Transform3D, f: Callable, nu: int, nv: int, thick: float, col: Callable) -> void:
	var P: Array = []
	for i in nu + 1:
		var row := PackedVector3Array()
		for j in nv + 1:
			row.append(f.call(float(i) / nu, float(j) / nv))
		P.append(row)
	var N: Array = []
	for i in nu + 1:
		var row := PackedVector3Array()
		for j in nv + 1:
			var du: Vector3 = (P[mini(i + 1, nu)] as PackedVector3Array)[j] - (P[maxi(i - 1, 0)] as PackedVector3Array)[j]
			var dv: Vector3 = (P[i] as PackedVector3Array)[mini(j + 1, nv)] - (P[i] as PackedVector3Array)[maxi(j - 1, 0)]
			row.append(du.cross(dv).normalized())
		N.append(row)
	var C: Array = []
	for i in nu + 1:
		var row := PackedColorArray()
		for j in nv + 1:
			row.append(col.call(float(i) / nu, float(j) / nv))
		C.append(row)
	var st := k._tool(m)
	var nb := xf.basis.inverse().transposed()
	var h := thick * 0.5
	var pt := func(i: int, j: int, side: float) -> Vector3:
		return (P[i] as PackedVector3Array)[j] + (N[i] as PackedVector3Array)[j] * h * side
	for side: float in [1.0, -1.0]:
		for i in nu:
			for j in nv:
				var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				var ps: Array = []
				var ns: Array = []
				var cs: Array = []
				for c in q:
					ps.append(pt.call(c[0], c[1], side))
					ns.append((N[c[0]] as PackedVector3Array)[c[1]] * side)
					var cc: Color = (C[c[0]] as PackedColorArray)[c[1]]
					cs.append(cc if side > 0.0 else cc.darkened(0.3))
				for tri in [[0, 1, 2], [0, 2, 3]]:
					Provisions._tri(st, xf, nb, [ps[tri[0]], ps[tri[1]], ps[tri[2]]], [ns[tri[0]], ns[tri[1]], ns[tri[2]]], [cs[tri[0]], cs[tri[1]], cs[tri[2]]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var edge: Array = []
	for i in nu:
		edge.append([i, 0])
	for j in nv:
		edge.append([nu, j])
	for i in range(nu, 0, -1):
		edge.append([i, nv])
	for j in range(nv, 0, -1):
		edge.append([0, j])
	var mid: Vector3 = (P[nu / 2] as PackedVector3Array)[nv / 2]
	for e in edge.size():
		var c0: Array = edge[e]
		var c1: Array = edge[(e + 1) % edge.size()]
		var a: Vector3 = pt.call(c0[0], c0[1], -1.0)
		var b: Vector3 = pt.call(c1[0], c1[1], -1.0)
		var c: Vector3 = pt.call(c1[0], c1[1], 1.0)
		var d: Vector3 = pt.call(c0[0], c0[1], 1.0)
		var out := ((a + b) * 0.5 - mid).normalized()
		var rc: Color = ((C[c0[0]] as PackedColorArray)[c0[1]] as Color).darkened(0.15)
		ItemModels._quad(k, m, xf, a, b, c, d, out, rc)

## A closed loop of `segs` points round an ellipse in the XZ plane.
static func _ring_path(c: Vector3, rx: float, rz: float, segs: int) -> PackedVector3Array:
	var path := PackedVector3Array()
	for i in segs + 1:
		var a := TAU * i / segs
		path.append(c + Vector3(cos(a) * rx, 0, sin(a) * rz))
	return path

static func _radii(n: int, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(r)
	return out

# --- Ammunition (items19) ---------------------------------------------------------------

## Void cell: a slim dark-gunmetal cage, pointed below, its struts framing a violet core
## that shows between them and pokes out above as a crystal tip.
static func _void_cell(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var I := Transform3D.IDENTITY
	_facet(k, "own:glow:violet", I, [Vector2(0, 0.012), Vector2(0.0125, 0.012), Vector2(0.0125, 0.082), Vector2(0, 0.104)], 6, Color(0.26, 0.12, 0.7, 0.96), 1.0, 1.0, PI / 6.0)
	_facet(k, "im:crystal:void_cell", I, [Vector2(0, 0.02), Vector2(0.006, 0.03), Vector2(0.006, 0.08), Vector2(0, 0.09)], 6, Color(0.7, 0.55, 1.0, 0.5))
	var metal := "im:metal@0.35"
	_facet(k, metal, I, [Vector2(0, -0.008), Vector2(0.011, 0.0), Vector2(0.0175, 0.008), Vector2(0.0175, 0.019), Vector2(0.0135, 0.023), Vector2(0, 0.023)], 8, GUNMETAL, 1.0, 1.0, PI / 8.0)
	_facet(k, metal, I, [Vector2(0.0125, 0.074), Vector2(0.0175, 0.077), Vector2(0.0175, 0.086), Vector2(0.0128, 0.09)], 8, GUNMETAL, 1.0, 1.0, PI / 8.0)
	for i in 4:
		var a := TAU * i / 4.0
		var dir := Vector3(sin(a), 0, cos(a))
		var b := Basis(Vector3.UP, a)
		k.bevel_box(metal, Transform3D(b, dir * 0.0148 + Vector3(0, 0.049, 0)), Vector3(0.0048, 0.056, 0.0042), 0.001, GUNMETAL.lightened(0.05))
		# An arrow-shaped boss on each strut, as in the painting.
		k.bevel_box(metal, Transform3D(b * Basis(Vector3.BACK, PI * 0.25), dir * 0.0172 + Vector3(0, 0.058, 0)), Vector3(0.0062, 0.0062, 0.003), 0.0008, Color(0.36, 0.33, 0.3))
		k.bevel_box(metal, Transform3D(b * Basis(Vector3.BACK, PI * 0.25), dir * 0.0172 + Vector3(0, 0.032, 0)), Vector3(0.005, 0.005, 0.003), 0.0008, Color(0.36, 0.33, 0.3))
	return Vector3(0, 0.03, 0)

## Bio ammo: five mottled green spore pods packed in a clear, wet membrane bag knotted at
## two necks with brown twisted ends, a fine net over it all.
static func _bio_ammo(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	for p: Vector3 in [Vector3(-0.026, 0.077, -0.006), Vector3(0.027, 0.079, -0.008), Vector3(-0.033, 0.047, 0.01), Vector3(0.031, 0.046, 0.012), Vector3(0.0, 0.026, 0.014)]:
		var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU), p)
		_blob(k, "own:wet", xf, 0.021, Color(0.12, 0.18, 0.03), Color(0.34, 0.4, 0.09), 140.0)
	var prof := Provisions._curve([Vector2(0, 0.0), Vector2(0.032, 0.003), Vector2(0.05, 0.03), Vector2(0.05, 0.07), Vector2(0.035, 0.098), Vector2(0.012, 0.114), Vector2(0.004, 0.12)], 4)
	for sx: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.82)), Vector3(sx * 0.019, 0, 0))
		Provisions.lathe(k, "own:film", xf, prof, 24, Color(0.8, 0.8, 0.7, 0.12))
		# The net: threads spiralling both ways over the bag make a diamond mesh.
		for i in 6:
			for dirn: float in [-1.0, 1.0]:
				var path := PackedVector3Array()
				for j in prof.size():
					var a := TAU * i / 6.0 + dirn * prof[j].y * 18.0
					path.append(xf * Vector3(cos(a) * (prof[j].x + 0.0008), prof[j].y, sin(a) * (prof[j].x + 0.0008)))
				ItemModels._tube(k, "im:rope", Transform3D.IDENTITY, path, _radii(path.size(), 0.0004), 3, Color(0.6, 0.56, 0.44), false)
		# The knot: the bag's gathered end twisted into stiff brown points.
		var top := Vector3(sx * 0.019, 0.12, 0)
		k.sphere("im:hide", Transform3D(Basis.IDENTITY, top), 0.0045, 6, 8, 0.2, 1.0, Color(0.4, 0.28, 0.14))
		for j in 6:
			var a := TAU * j / 6.0 + r.randf() * 0.4
			var lean := r.randf_range(0.5, 1.1)
			var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -lean)
			k.cylinder("im:hide", Transform3D(b, top), 0.0022, 0.0, r.randf_range(0.01, 0.017), 5, false, 0.0, 1, Color(0.46, 0.33, 0.17))

## Star shards: a fan of pale blue crystal blades, faintly lit, held in brown horny
## sheaths that splay out with them from one root.
static func _star_shards(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var crystals := [[Vector3(0.0, 0.0, 0.0), -0.12, 0.1, 0.012], [Vector3(-0.012, 0.004, -0.006), 0.32, 0.086, 0.011],
		[Vector3(0.016, 0.004, -0.004), -0.42, 0.072, 0.009], [Vector3(-0.018, 0.0, 0.008), 0.95, 0.058, 0.009],
		[Vector3(0.024, 0.0, 0.004), -0.85, 0.045, 0.007]]
	for c: Array in crystals:
		var h: float = c[2]
		var rad: float = c[3]
		var xf := Transform3D(Basis(Vector3.BACK, c[1]) * Basis(Vector3.RIGHT, -0.12), c[0])
		_facet(k, "own:glow:blue", xf, [Vector2(0, 0), Vector2(rad * 0.85, h * 0.08), Vector2(rad, h * 0.72), Vector2(0, h)], 5, Color(0.3, 0.45, 0.95, 0.95), 1.0, 0.55, 0.3)
		_facet(k, "im:crystal:star_shards", xf, [Vector2(0, h * 0.1), Vector2(rad * 0.4, h * 0.2), Vector2(rad * 0.4, h * 0.6), Vector2(0, h * 0.8)], 5, Color(0.7, 0.8, 1.0, 0.5), 1.0, 0.5)
	var sheaths := [[Vector3(-0.02, -0.004, 0.016), 0.72, 0.07, 0.009], [Vector3(0.008, -0.004, 0.014), -0.25, 0.072, 0.009],
		[Vector3(0.024, -0.004, 0.01), -0.62, 0.052, 0.008], [Vector3(-0.004, -0.004, -0.012), 0.1, 0.06, 0.008]]
	for s: Array in sheaths:
		var h: float = s[2]
		var rad: float = s[3]
		var xf := Transform3D(Basis(Vector3.BACK, s[1]) * Basis(Vector3.RIGHT, 0.08), s[0])
		_facet(k, "own:chitin", xf, [Vector2(0, 0), Vector2(rad, h * 0.25), Vector2(rad * 0.8, h * 0.7), Vector2(0, h)], 4, Color(0.4, 0.27, 0.16), 1.0, 0.28)
		# The pale horn edge down each blade.
		_facet(k, "own:chitin", xf.translated_local(Vector3(0, 0, rad * 0.05)), [Vector2(0, h * 0.02), Vector2(rad * 1.06, h * 0.25), Vector2(rad * 0.86, h * 0.7), Vector2(0, h * 0.98)], 4, Color(0.72, 0.58, 0.36), 1.0, 0.12)

## Psi crystal: one long violet crystal pointed at both ends, six-sided and a little
## flattened, its paler core lit faintly from within.
static func _psi_crystal(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var I := Transform3D.IDENTITY
	_facet(k, "own:glow:violet", I, [Vector2(0, 0), Vector2(0.011, 0.016), Vector2(0.0135, 0.046), Vector2(0.0105, 0.061), Vector2(0, 0.086)], 6, Color(0.42, 0.14, 0.82, 0.96), 1.0, 0.72, 0.2)
	_facet(k, "im:crystal:psi_crystal", I, [Vector2(0, 0.012), Vector2(0.005, 0.022), Vector2(0.006, 0.05), Vector2(0, 0.07)], 6, Color(0.85, 0.7, 1.0, 0.5), 1.0, 0.7)

## Chitin spikes: six long horn spikes, pale at both points and streaked red-brown along
## their length, bound in a bundle by a few turns of dark cord.
static func _chitin_spikes(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Vector3:
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var l := r.randf_range(0.165, 0.19)
		var base := Vector3(cos(a) * 0.0105, r.randf_range(-0.012, 0.006), sin(a) * 0.0105)
		var b := Basis(Vector3.BACK, -cos(a) * 0.09) * Basis(Vector3.RIGHT, sin(a) * 0.07)
		var prof := Provisions._curve([Vector2(0, 0), Vector2(0.005, 0.012), Vector2(0.0092, 0.05), Vector2(0.009, 0.095), Vector2(0.0058, l * 0.8), Vector2(0, l)], 4)
		var seed := float(i) * 13.0
		Provisions.lathe(k, "own:chitin", Transform3D(b, base), prof, 10, func(p: Vector3, _a: float, t: float) -> Color:
			var streak := Provisions._nz(Vector3(p.x * 1.0 + seed, p.y * 0.06, p.z * 1.0), 420.0)
			var body := Color(0.36, 0.14, 0.1).lerp(Color(0.62, 0.42, 0.3), clampf(0.5 + streak * 1.8, 0.0, 1.0))
			var tip := clampf(maxf(1.0 - t / 0.12, (t - 0.8) / 0.12), 0.0, 1.0)
			return body.lerp(Color(0.86, 0.76, 0.6), tip))
	for j in 4:
		var y := 0.074 + j * 0.0045
		ItemModels._tube(k, "im:rope", Transform3D(Basis(Vector3.BACK, 0.06 * (j - 1.5)), Vector3.ZERO), _ring_path(Vector3(0, y, 0), 0.021, 0.021, 20), _radii(21, 0.0022), 6, Color(0.24, 0.15, 0.1), false)
	return Vector3(0, 0.08, 0)

## Ion core: a glass cylinder full of blue light with a brighter swirl wound through it,
## capped in bronze with dark bands and held in a bronze cage.
static func _ion_core(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("own:gel:blue", Transform3D(Basis.IDENTITY, Vector3(0, 0.016, 0)), 0.0165, 0.0165, 0.068, 20, false, 0.0, 1, Color(0.1, 0.25, 0.85, 0.96))
	for s in 3:
		var path := PackedVector3Array()
		for i in 49:
			var e := i / 48.0
			var a := e * TAU * 2.2 + s * TAU / 3.0
			var rr := 0.008 + 0.006 * sin(e * PI * 3.0 + s)
			path.append(Vector3(cos(a) * rr, 0.02 + e * 0.06, sin(a) * rr))
		ItemModels._tube(k, "own:glow:cyan", I, path, _radii(49, 0.0009), 4, Color(0.8, 0.93, 1.0, 0.9))
	k.cylinder("own:glass", Transform3D(Basis.IDENTITY, Vector3(0, 0.016, 0)), 0.0195, 0.0195, 0.068, 24, false, 0.0, 1, Color(0.6, 0.7, 1.0, 0.06))
	var m := "im:metal@0.3"
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(0, 0), Vector2(0.021, 0), Vector2(0.024, 0.003), Vector2(0.024, 0.015), Vector2(0.021, 0.019), Vector2(0.019, 0.019)], 2), 24, BRONZE)
	k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.006, 0)), 0.0245, 0.0245, 0.005, 24, false, 0.0, 1, Color(0.32, 0.16, 0.12))
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(0.019, 0.081), Vector2(0.022, 0.081), Vector2(0.0235, 0.084), Vector2(0.0235, 0.091), Vector2(0.018, 0.094), Vector2(0.013, 0.099), Vector2(0, 0.1)], 2), 24, BRONZE)
	k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.085, 0)), 0.024, 0.024, 0.0035, 24, false, 0.0, 1, GUNMETAL)
	ItemModels._torus(k, m, Transform3D(Basis.IDENTITY, Vector3(0, 0.026, 0)), 0.0205, 0.0016, 24, 6, BRONZE)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var dir := Vector3(sin(a), 0, cos(a))
		k.bevel_box(m, Transform3D(Basis(Vector3.UP, a), dir * 0.0205 + Vector3(0, 0.05, 0)), Vector3(0.004, 0.064, 0.003), 0.0008, BRONZE.darkened(0.15))

# --- Materials (items22) ----------------------------------------------------------------

## Chitin plate: a curved shell plate tapering from a broad base to a point, built of
## overlapping bands, its surface shimmering purple, blue and gold like a beetle's.
static func _chitin_plate(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var L := 0.16
	var f := func(u: float, v: float) -> Vector3:
		var band := fposmod(u * 6.0, 1.0)
		var R := lerpf(0.07, 0.042, pow(u, 1.6)) * (1.0 + 0.07 * band)
		var th := lerpf(-1.15, 1.15, v)
		var c := Vector3(0.012 * sin(u * PI), u * L, -0.09 * u * u)
		return c + Vector3(sin(th) * R, 0, cos(th) * R - R)
	var col := func(u: float, v: float) -> Color:
		var band := fposmod(u * 6.0, 1.0)
		var h := fposmod(u * 1.3 + v * 0.9 + Provisions._nz(Vector3(u, v, 0.0), 3.0) * 0.4, 1.0)
		var stops := [Color(0.52, 0.42, 0.86), Color(0.38, 0.58, 0.95), Color(0.62, 0.8, 0.82), Color(0.88, 0.76, 0.46), Color(0.52, 0.42, 0.86)]
		var q := h * 4.0
		var c: Color = (stops[int(q)] as Color).lerp(stops[mini(int(q) + 1, 4)], q - int(q))
		return c.darkened(0.35 * clampf(1.0 - band * 6.0, 0.0, 1.0))
	_grid(k, "own:shell", Transform3D(Basis(Vector3.BACK, -0.55), Vector3.ZERO), f, 56, 18, 0.003, col)

## Xeno gel: a flat, glossy puddle of teal jelly in a kidney shape with two drops beside
## it, see-through and lit faintly from inside.
static func _bio_gel(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var prof := Provisions._curve([Vector2(0, 0), Vector2(0.036, 0.001), Vector2(0.046, 0.01), Vector2(0.042, 0.026), Vector2(0.024, 0.038), Vector2(0, 0.041)], 4)
	var shape := func(a: float, _t2: float, _p: Vector3) -> float:
		return 1.0 + 0.22 * cos(2.0 * a) - 0.16 * sin(a - 0.6) + 0.1 * cos(3.0 * a + 1.0)
	var col := func(_p: Vector3, _a: float, t: float) -> Color:
		return Color(0.0, 0.2, 0.22, 0.95).lerp(Color(0.04, 0.55, 0.5, 0.93), t * t)
	Provisions.lathe(k, "own:gel:teal", Transform3D(Basis.from_scale(Vector3(1.25, 1.0, 1.0)), Vector3.ZERO), prof, 40, col, shape)
	for d: Array in [[Vector3(-0.042, 0, 0.04), 0.0085], [Vector3(-0.022, 0, 0.052), 0.0062]]:
		Provisions.lathe(k, "own:gel:teal", Transform3D(Basis.IDENTITY, d[0]), Provisions._curve([Vector2(0, 0), Vector2(d[1] * 0.9, 0.0005), Vector2(d[1], d[1] * 0.4), Vector2(d[1] * 0.6, d[1] * 0.8), Vector2(0, d[1] * 0.9)], 3), 16, col)

## Crystal thread: a loose hank of shimmering cord, lavender and ice-blue strands twisted
## together, coiled in loops with its end trailing off.
static func _crystal_thread(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var cols := [Color(0.48, 0.38, 0.82), Color(0.4, 0.62, 0.9), Color(0.7, 0.6, 0.92)]
	var loops: Array = []
	for l in 11:
		var c := Vector3(r.randf_range(-0.006, 0.006), l * 0.0034, r.randf_range(-0.004, 0.004))
		var path := PackedVector3Array()
		var rx := 0.05 + r.randf_range(-0.004, 0.004)
		var rz := 0.036 + r.randf_range(-0.003, 0.003)
		var ph := r.randf() * TAU
		for i in 73:
			var a := TAU * i / 72.0
			path.append(c + Vector3(cos(a) * rx, 0.003 * sin(a * 2.0 + ph), sin(a) * rz))
		loops.append(path)
	# The loose end leaves the hank and trails off to the front right.
	var tail := PackedVector3Array()
	for i in 25:
		var e := i / 24.0
		tail.append(Vector3(0.05 + e * 0.03 + 0.008 * sin(e * 5.0), 0.016 - e * 0.016, e * 0.065))
	loops.append(tail)
	for path: PackedVector3Array in loops:
		_twisted(k, path, cols, 0.0026)

## Strands twisted round a path into a cord.
static func _twisted(k: MeshKit, path: PackedVector3Array, cols: Array, rad: float) -> void:
	var n := path.size()
	for s in cols.size():
		var p2 := PackedVector3Array()
		for i in n:
			var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
			var side := t.cross(Vector3.UP).normalized()
			var up := side.cross(t)
			var tw := i * 1.1 + s * TAU / cols.size()
			p2.append(path[i] + (side * cos(tw) + up * sin(tw)) * rad * 0.8)
		ItemModels._tube(k, "own:silk", Transform3D.IDENTITY, p2, _radii(n, rad * 0.75), 5, cols[s])

## Living metal: liquid-bright chrome drawn into a thick tube and tied in a knot of four
## loops, swelling and thinning a little as if it still flows.
static func _living_metal(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 240
	for i in n + 1:
		var t := TAU * i / n
		var rr := 0.027 + 0.015 * cos(4.0 * t)
		path.append(Vector3(rr * cos(3.0 * t), rr * sin(3.0 * t) + 0.045, -0.016 * sin(4.0 * t)))
		radii.append(0.0082 * (1.0 + 0.12 * sin(t * 7.0)))
	ItemModels._tube(k, "own:chrome", Transform3D.IDENTITY, path, radii, 14, Color(0.8, 0.82, 0.86), false)

## A round-bellied flask (profile `prof`) of clear glass filled to `fill_y` with
## `fill_m`, standing on y = 0.
static func _flask(k: MeshKit, xf: Transform3D, prof: PackedVector2Array, glass: Color, fill_m: String, fill: Variant, fill_y: float) -> void:
	var inner := PackedVector2Array()
	for p in prof:
		if p.y > fill_y:
			break
		inner.append(Vector2(p.x * 0.9, p.y + 0.0015))
	var rf := Provisions._radius_at(prof, fill_y) * 0.9
	inner.append(Vector2(rf, fill_y))
	inner.append(Vector2(0, fill_y))
	Provisions.lathe(k, fill_m, xf, inner, 28, fill)
	Provisions.lathe(k, "own:glass", xf, prof, 28, glass)

## Dark matter: a round glass flask held in gold filigree, a violet galaxy turning in the
## black inside, violet stones set at its sides and in its stopper.
static func _dark_matter(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var I := Transform3D.IDENTITY
	var cy := 0.046
	var R := 0.034
	var prof := Provisions._curve([Vector2(0, 0.012), Vector2(0.02, 0.014), Vector2(0.032, 0.03), Vector2(R, cy), Vector2(0.03, 0.064), Vector2(0.016, 0.076), Vector2(0.0095, 0.08), Vector2(0.009, 0.092)], 4)
	_flask(k, I, prof, Color(0.55, 0.45, 0.75, 0.06), "own:gel:dark", func(p: Vector3, _a: float, _t2: float) -> Color:
		return Color(0.04, 0.02, 0.1, 0.98).lerp(Color(0.24, 0.08, 0.42, 0.98), clampf(0.5 + Provisions._nz(p, 90.0), 0.0, 1.0)), 0.074)
	# The galaxy: two bright arms spiralling out from a core, just inside the front glass.
	for arm in 2:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 30:
			var e := i / 29.0
			var a := arm * PI + e * 4.2
			var rr := 0.002 + e * 0.022
			var x := cos(a) * rr
			var y := sin(a) * rr * 0.9
			path.append(Vector3(x, cy + y, sqrt(maxf(R * R * 0.88 - x * x - y * y, 0.0))))
			radii.append(lerpf(0.0028, 0.0008, e))
		ItemModels._tube(k, "own:glow:purple", I, path, radii, 5, Color(0.82, 0.62, 1.0, 0.9))
	k.sphere("own:glow:purple", Transform3D(Basis.IDENTITY, Vector3(0, cy, R * 0.92)), 0.0045, 6, 8, 0.0, 1.0, Color(0.95, 0.85, 1.0, 0.9))
	_gilt(k, prof, cy, R, 0.092)
	# Violet stones at the sides and in the stopper.
	for sx: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis(Vector3.BACK, sx * PI * 0.5), Vector3(sx * (R + 0.003), cy, 0))
		k.cylinder("im:metal@0.3", xf.translated_local(Vector3(0, -0.002, 0)), 0.0055, 0.0055, 0.003, 10, true, 0.0, 1, GOLD)
		_facet(k, "own:glow:violet", xf, [Vector2(0, 0), Vector2(0.0048, 0.001), Vector2(0, 0.005)], 8, Color(0.45, 0.15, 0.75, 0.9))
	_facet(k, "own:glow:violet", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), [Vector2(0, 0), Vector2(0.008, 0.006), Vector2(0.0075, 0.009), Vector2(0, 0.017)], 8, Color(0.45, 0.16, 0.75, 0.9))
	return Vector3(0, 0.085, 0)

## Gold work on a flask: a footed base, ribs up the body, a band at the shoulder and a
## collar and cup round the neck.
static func _gilt(k: MeshKit, prof: PackedVector2Array, cy: float, R: float, neck: float) -> void:
	var m := "im:metal@0.28"
	var I := Transform3D.IDENTITY
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(0, 0), Vector2(0.022, 0), Vector2(0.024, 0.004), Vector2(0.017, 0.009), Vector2(0.021, 0.0135), Vector2(0, 0.0135)], 2), 24, GOLD)
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for p in prof:
			if p.y < 0.012 or p.y > neck - 0.006:
				continue
			var w := a + 0.12 * sin(p.y * 220.0)
			path.append(Vector3(cos(w) * (p.x + 0.0012), p.y, sin(w) * (p.x + 0.0012)))
			radii.append(0.0013)
		ItemModels._tube(k, m, I, path, radii, 5, GOLD)
	var ys := Provisions._radius_at(prof, cy + R * 0.62)
	ItemModels._torus(k, m, Transform3D(Basis.IDENTITY, Vector3(0, cy + R * 0.62, 0)), ys + 0.0012, 0.0014, 28, 5, GOLD)
	var rn := Provisions._radius_at(prof, neck - 0.004)
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(rn + 0.0005, neck - 0.014), Vector2(rn + 0.003, neck - 0.012), Vector2(rn + 0.0025, neck - 0.006), Vector2(rn + 0.0045, neck - 0.002), Vector2(rn + 0.004, neck + 0.004), Vector2(rn + 0.001, neck + 0.008), Vector2(0, neck + 0.0085)], 2), 20, GOLD)

## Light essence: a round-shouldered glass bottle brimming with golden light, a bright
## heart glowing in it, caged in gold wire with a gold ball for a stopper.
static func _light_essence(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var xf := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.8)), Vector3.ZERO)
	var prof := Provisions._curve([Vector2(0, 0.012), Vector2(0.024, 0.013), Vector2(0.03, 0.022), Vector2(0.031, 0.05), Vector2(0.027, 0.068), Vector2(0.014, 0.078), Vector2(0.0095, 0.081), Vector2(0.009, 0.092)], 4)
	_flask(k, xf, prof, Color(0.95, 0.9, 0.75, 0.06), "own:gel:gold", func(p: Vector3, _a: float, _t2: float) -> Color:
		var d := Vector2(p.x, p.y - 0.045).length() / 0.03
		return Color(0.95, 0.66, 0.16, 0.96).lerp(Color(0.65, 0.3, 0.02, 0.96), clampf(d, 0.0, 1.0)), 0.07)
	k.sphere("own:glow:gold", Transform3D(Basis.IDENTITY, Vector3(0, 0.045, 0)), 0.011, 8, 10, 0.25, 1.0, Color(1.0, 0.96, 0.8, 0.95))
	_gilt(k, prof, 0.042, 0.031, 0.092)
	k.sphere("im:metal@0.25", Transform3D(Basis.IDENTITY, Vector3(0, 0.108, 0)), 0.0085, 10, 14, 0.0, 1.0, GOLD)
	return Vector3(0, 0.085, 0)

## Xeno circuit: dark teal traces branching like coral from one stem, each ending in a lit
## node, rings set along them, a bright line glowing down the middle of every trace.
static func _alien_circuit(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var S := 0.12 / 256.0
	var to3 := func(p: Vector2) -> Vector3:
		return Vector3((p.x - 128.0) * S, (256.0 - p.y) * S, 0.0)
	var lines := [
		[Vector2(63, 16), Vector2(63, 58), Vector2(92, 92), Vector2(108, 140), Vector2(140, 190), Vector2(168, 236)],
		[Vector2(143, 16), Vector2(138, 60), Vector2(130, 110), Vector2(140, 190)],
		[Vector2(193, 39), Vector2(186, 80), Vector2(166, 120), Vector2(150, 160)],
		[Vector2(228, 66), Vector2(214, 110), Vector2(190, 150), Vector2(175, 192), Vector2(168, 236)],
		[Vector2(40, 166), Vector2(78, 168), Vector2(110, 180), Vector2(140, 200)],
		[Vector2(172, 164), Vector2(158, 176)],
		[Vector2(203, 189), Vector2(184, 200), Vector2(172, 212)],
	]
	var ends := [Vector2(63, 16), Vector2(143, 16), Vector2(193, 39), Vector2(228, 66), Vector2(40, 166), Vector2(172, 164)]
	var rings := [Vector2(140, 94), Vector2(203, 189), Vector2(168, 238)]
	for ln: Array in lines:
		var pts: Array = []
		for p: Vector2 in ln:
			pts.append(p)
		var path := PackedVector3Array()
		for p in Provisions._curve(pts, 4):
			path.append(to3.call(p))
		ItemModels._tube(k, "own:trace", Transform3D.IDENTITY, path, _radii(path.size(), 0.0048), 6, Color(0.04, 0.22, 0.21))
		var glow := PackedVector3Array()
		for p in path:
			glow.append(p + Vector3(0, 0, 0.0039))
		ItemModels._tube(k, "own:glow:teal", Transform3D.IDENTITY, glow, _radii(glow.size(), 0.001), 4, Color(0.2, 0.75, 0.66, 0.97))
	for e: Vector2 in ends:
		var c: Vector3 = to3.call(e)
		k.sphere("own:trace", Transform3D(Basis.IDENTITY, c), 0.008, 8, 10, 0.0, 1.0, Color(0.04, 0.22, 0.21))
		k.sphere("own:glow:teal", Transform3D(Basis.IDENTITY, c + Vector3(0, 0, 0.0025)), 0.0065, 8, 10, 0.0, 1.0, Color(0.25, 0.85, 0.75, 0.97))
	for rp: Vector2 in rings:
		var c: Vector3 = to3.call(rp)
		ItemModels._torus(k, "own:trace", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c), 0.0055, 0.002, 16, 6, Color(0.06, 0.3, 0.28))

## Gravity core: a dark blue sphere speckled with stars like a piece of night sky, caught
## in a gimbal of thin silver and bronze rings at odd tilts.
static func _grav_core(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var c := Vector3(0, 0.04, 0)
	Provisions.lathe(k, "own:gel:blue", Transform3D(Basis.IDENTITY, c - Vector3(0, 0, 0)), Provisions._sphere(0.024, 28), 48, func(p: Vector3, _a: float, _t2: float) -> Color:
		var base := Color(0.02, 0.03, 0.12).lerp(Color(0.16, 0.22, 0.6), clampf(0.4 + Provisions._nz(p, 70.0) * 1.5, 0.0, 1.0))
		return Color(base.r, base.g, base.b, 0.97).lerp(Color(0.95, 0.95, 1.0), clampf((Provisions._nz(p, 900.0) - 0.36) * 6.0, 0.0, 1.0)))
	var rings := [[0.031, Basis(Vector3.RIGHT, 1.25), Color(0.68, 0.66, 0.64)], [0.034, Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.35), BRONZE],
		[0.037, Basis(Vector3.RIGHT, 0.4) * Basis(Vector3.BACK, -0.25), Color(0.6, 0.58, 0.56)], [0.029, Basis(Vector3.BACK, -0.75) * Basis(Vector3.RIGHT, 1.45), Color(0.55, 0.53, 0.52)], [0.039, Basis(Vector3.BACK, 0.3) * Basis(Vector3.RIGHT, 1.0), BRONZE.darkened(0.2)]]
	for rg: Array in rings:
		var b: Basis = rg[1]
		ItemModels._torus(k, "im:metal@0.22", Transform3D(b * Basis.from_scale(Vector3(1, 1.8, 1)), c), rg[0], 0.0021, 40, 6, rg[2])

## Warp coil: a long violet crystal core wound with a bronze coil, held between ornate
## bronze end caps, the crystal's point standing out above.
static func _warp_coil(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Vector3:
	var I := Transform3D.IDENTITY
	_facet(k, "own:glow:violet", I, [Vector2(0, 0.004), Vector2(0.012, 0.018), Vector2(0.0158, 0.03), Vector2(0.0158, 0.08), Vector2(0.012, 0.094), Vector2(0, 0.118)], 6, Color(0.42, 0.2, 0.92, 0.96))
	_facet(k, "im:crystal:warp_coil", I, [Vector2(0, 0.02), Vector2(0.005, 0.03), Vector2(0.005, 0.085), Vector2(0, 0.1)], 6, Color(0.85, 0.75, 1.0, 0.5))
	var path := PackedVector3Array()
	for i in 161:
		var e := i / 160.0
		var a := e * TAU * 4.0
		path.append(Vector3(cos(a) * 0.0185, 0.026 + e * 0.058, sin(a) * 0.0165))
	ItemModels._tube(k, "im:metal@0.25", I, path, _radii(161, 0.0024), 8, BRONZE)
	var m := "im:metal@0.28"
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(0, -0.002), Vector2(0.007, -0.001), Vector2(0.013, 0.006), Vector2(0.01, 0.013), Vector2(0.014, 0.019), Vector2(0.0115, 0.025), Vector2(0.0105, 0.025)], 2), 16, BRONZE)
	Provisions.lathe(k, m, I, Provisions._curve([Vector2(0.0105, 0.085), Vector2(0.0125, 0.085), Vector2(0.015, 0.09), Vector2(0.011, 0.095), Vector2(0.012, 0.1), Vector2(0.0085, 0.104), Vector2(0.007, 0.104)], 2), 16, BRONZE)
	_facet(k, "own:glow:violet", Transform3D(Basis.IDENTITY, Vector3(0, -0.002, 0)), [Vector2(0, -0.008), Vector2(0.004, -0.001), Vector2(0, 0.0)], 6, Color(0.5, 0.25, 0.9, 0.9))
	return Vector3(0, 0.05, 0)

## AI shard: one flat, clear cyan crystal leaning to the side, lit faintly blue, a paler
## cloud of flaws inside it.
static func _ai_shard(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, -0.45) * Basis(Vector3.UP, 0.25), Vector3.ZERO)
	_facet(k, "own:glow:cyan", xf, [Vector2(0, 0), Vector2(0.015, 0.014), Vector2(0.02, 0.05), Vector2(0.015, 0.072), Vector2(0, 0.092)], 6, Color(0.04, 0.45, 0.72, 0.95), 1.0, 0.5, 0.3)
	_facet(k, "im:crystal:ai_shard", xf, [Vector2(0, 0.012), Vector2(0.007, 0.022), Vector2(0.008, 0.05), Vector2(0, 0.075)], 6, Color(0.85, 0.97, 1.0, 0.45), 1.0, 0.4, 0.3)

## Bio battery: a teal pod pointed at both ends, a dark spine down its face with curved
## dark ribs branching off it like a fishbone, the cells between them glowing softly.
static func _bio_battery(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var prof := Provisions._curve([Vector2(0, 0), Vector2(0.012, 0.008), Vector2(0.03, 0.035), Vector2(0.034, 0.055), Vector2(0.028, 0.08), Vector2(0.012, 0.097), Vector2(0, 0.104)], 7)
	var rib := func(a: float, t: float) -> float:
		var d := absf(wrapf(a - PI * 0.5, -PI, PI))
		return fposmod(t * 9.0 + d * 1.1, 1.0)
	var col := func(_p: Vector3, a: float, t: float) -> Color:
		var d := absf(wrapf(a - PI * 0.5, -PI, PI))
		var f: float = rib.call(a, t)
		var spine := d < 0.07 or absf(d - PI * 0.62) < 0.06
		if spine or f < 0.2:
			return Color(0.02, 0.05, 0.07)
		return Color(0.02, 0.15, 0.19).lerp(Color(0.08, 0.48, 0.48), sin(PI * (f - 0.2) / 0.8))
	var shape := func(a: float, t: float, _p: Vector3) -> float:
		return 1.0 - 0.035 * float(rib.call(a, t) < 0.2)
	var xf := Transform3D(Basis(Vector3.BACK, -0.2) * Basis.from_scale(Vector3(1.0, 1.0, 0.85)), Vector3.ZERO)
	Provisions.lathe(k, "own:skin:teal", xf, prof, 56, col, shape)

## Phase lens: an oval lens swirling with rainbow colour like oil on water, ground thick
## in the middle, set in a polished gold rim.
static func _phase_lens(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, 0.5) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.22, 1.0, 1.0)), Vector3(0, 0.04, 0))
	var prof := Provisions._curve([Vector2(0, -0.006), Vector2(0.02, -0.0048), Vector2(0.034, -0.0018), Vector2(0.036, 0.0), Vector2(0.034, 0.0018), Vector2(0.02, 0.0048), Vector2(0, 0.006)], 4)
	Provisions.lathe(k, "own:irid", xf, prof, 48, func(p: Vector3, a: float, _t2: float) -> Color:
		var rr := Vector2(p.x, p.z).length() / 0.036
		var h := fposmod(0.62 + rr * 0.7 + a * 0.16 + Provisions._nz(p, 60.0) * 0.5, 1.0)
		return Color.from_hsv(h, 0.75, 0.95, 0.94))
	ItemModels._torus(k, "im:metal@0.22", xf, 0.0368, 0.0026, 48, 8, GOLD)

## Xeno eye: a glossy round eye, the amber iris fired orange at the heart and streaked
## out to olive green, split by a black slit pupil.
static func _eye_xeno(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var R := 0.026
	var xf := Transform3D(Provisions._facing(Vector3(0.2, 0.3, 1.0)), Vector3(0, R, 0))
	Provisions.lathe(k, "own:wet", xf, Provisions._sphere(R, 40), 72, func(p: Vector3, a: float, _t2: float) -> Color:
		var rho := Vector2(p.x, p.z).length() / R
		if p.y < 0.0:
			return Color(0.08, 0.1, 0.04)
		var slit := 0.0042 * sqrt(maxf(0.0, 1.0 - pow(p.x / (R * 0.8), 2.0)))
		if absf(p.z) < slit:
			return Color(0.03, 0.02, 0.02)
		var streak := 0.85 + 0.3 * Provisions._nz(Vector3(cos(a) * 6.0, sin(a) * 6.0, rho * 3.0), 3.0)
		var c: Color
		if rho < 0.3:
			c = Color(0.95, 0.42, 0.04).lerp(Color(0.85, 0.6, 0.12), rho / 0.3)
		elif rho < 0.8:
			c = Color(0.85, 0.6, 0.12).lerp(Color(0.36, 0.42, 0.14), (rho - 0.3) / 0.5)
		else:
			c = Color(0.36, 0.42, 0.14).lerp(Color(0.08, 0.1, 0.04), clampf((rho - 0.8) / 0.2, 0.0, 1.0))
		return Color(c.r * streak, c.g * streak, c.b * streak))

## Spore sac: a plump purple membrane pod, clear enough to show the cluster of glowing
## violet spores packed inside, fine pale veins over its skin.
static func _spore_sac(k: MeshKit, r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, 0.35) * Basis.from_scale(Vector3(1.0, 1.0, 0.85)), Vector3.ZERO)
	var prof := Provisions._curve([Vector2(0, 0), Vector2(0.015, 0.004), Vector2(0.036, 0.026), Vector2(0.041, 0.05), Vector2(0.035, 0.074), Vector2(0.018, 0.09), Vector2(0, 0.094)], 4)
	var placed: Array = []
	var tries := 0
	while placed.size() < 22 and tries < 400:
		tries += 1
		var y := r.randf_range(0.012, 0.084)
		var rad := r.randf_range(0.0075, 0.012)
		var lim := Provisions._radius_at(prof, y) - rad - 0.002
		if lim <= 0.0:
			continue
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * lim
		var p := Vector3(cos(a) * d, y, sin(a) * d)
		var ok := true
		for q: Array in placed:
			if (q[0] as Vector3).distance_to(p) < (rad + float(q[1])) * 0.8:
				ok = false
				break
		if ok:
			placed.append([p, rad])
	for q: Array in placed:
		k.sphere("own:gel:purple", xf * Transform3D(Basis.IDENTITY, q[0]), q[1], 8, 10, 0.0, 1.0, Color(0.38, 0.07, 0.62, 0.97))
	Provisions.lathe(k, "own:membrane", xf, prof, 28, Color(0.45, 0.18, 0.62, 0.35))
	_veins(k, "own:wet", xf, prof, [0.3, 1.2, 1.9, 2.7, 3.6, 4.5, 5.4], Color(0.75, 0.6, 0.85), 0.0009, 0.15)

## Venom gland: a glossy yellow-green sac drawn to a point below, where a drop of venom
## hangs, gold veins running down it from a puckered dark stub on top.
static func _venom_gland(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, -0.3) * Basis.from_scale(Vector3(1.32, 1.0, 1.0)), Vector3(0, 0.014, 0))
	var prof := Provisions._curve([Vector2(0, 0), Vector2(0.006, 0.008), Vector2(0.02, 0.03), Vector2(0.03, 0.062), Vector2(0.027, 0.086), Vector2(0.017, 0.103), Vector2(0.006, 0.11), Vector2(0.0045, 0.115)], 4)
	Provisions.lathe(k, "own:skin:green", xf, prof, 32, func(p: Vector3, a: float, t: float) -> Color:
		var front := 0.5 + 0.5 * sin(a)
		var c := Color(0.14, 0.2, 0.02).lerp(Color(0.5, 0.62, 0.04), front * sin(PI * clampf(t * 1.2, 0.0, 1.0)))
		return c.darkened(0.12 * Provisions._nz(p, 200.0)))
	_veins(k, "im:metal@0.35", xf, prof, [0.4, 1.1, 1.6, 2.1, 2.8, 3.6, 4.6, 5.5], Color(0.82, 0.62, 0.25), 0.0014, 0.2, 0.05, 0.95)
	# The drop at the point.
	Provisions.lathe(k, "own:gel:green", xf, Provisions._curve([Vector2(0, -0.014), Vector2(0.0034, -0.011), Vector2(0.003, -0.005), Vector2(0.0012, -0.001), Vector2(0, 0.001)], 3), 12, Color(0.85, 0.82, 0.2, 0.88))
	k.cylinder("own:wet", xf * Transform3D(Basis(Vector3.BACK, 0.25), Vector3(0, 0.112, 0)), 0.005, 0.0028, 0.01, 8, true, 0.3, 2, Color(0.3, 0.3, 0.1))

## Wyrm scale: a long leaf-shaped scale of deep teal, its saw-toothed edge curling, cut
## finely with overlapping scale marks and ribbed with raised gold veins.
static func _scale_dragon(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var L := 0.16
	var wid := func(u: float) -> float:
		return 0.043 * pow(sin(PI * pow(u, 0.72)), 0.85) * (1.0 - 0.1 * fposmod(u * 10.0, 1.0))
	var f := func(u: float, v: float) -> Vector3:
		var s := lerpf(-1.0, 1.0, v)
		var w: float = wid.call(u)
		return Vector3(s * w + 0.008 * sin(u * PI * 1.3), u * L, 0.009 * (1.0 - s * s) - 0.02 * u * u + 0.006 * s * s * s)
	var col := func(u: float, v: float) -> Color:
		var s := absf(lerpf(-1.0, 1.0, v))
		var mark := fposmod(u * 34.0 + s * 3.0, 1.0)
		return Color(0.06, 0.26, 0.29).lerp(Color(0.2, 0.5, 0.52), smoothstep(0.55, 0.95, mark) * (0.5 + 0.5 * s))
	_grid(k, "own:shell", Transform3D.IDENTITY, f, 40, 14, 0.0022, col)
	var lift := Vector3(0, 0, 0.0018)
	var rib := PackedVector3Array()
	for i in 21:
		rib.append(f.call(0.02 + i * 0.047, 0.5) + lift)
	var rr := PackedFloat32Array()
	for i in 21:
		rr.append(lerpf(0.0016, 0.0005, i / 20.0))
	ItemModels._tube(k, "im:metal@0.3", Transform3D.IDENTITY, rib, rr, 6, GOLD)
	for i in 6:
		var u0 := 0.12 + i * 0.13
		for side: float in [0.0, 1.0]:
			var vein := PackedVector3Array()
			for j in 7:
				var e := j / 6.0
				var v := lerpf(0.5, side, e * 0.85)
				vein.append(f.call(minf(u0 + e * 0.16, 0.98), v) + lift)
			ItemModels._tube(k, "im:metal@0.3", Transform3D.IDENTITY, vein, _radii(7, 0.0008), 5, GOLD)

## Glowseed: a glowing cyan bulb with a bead of light at its tip, cupped in pointed
## bronze-green bracts that close up round its lower half.
static func _seed_glow(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> void:
	var prof := Provisions._curve([Vector2(0, 0.006), Vector2(0.014, 0.01), Vector2(0.022, 0.028), Vector2(0.0205, 0.045), Vector2(0.012, 0.056), Vector2(0.004, 0.06), Vector2(0, 0.061)], 4)
	Provisions.lathe(k, "own:gel:cyan", Transform3D.IDENTITY, prof, 24, func(_p: Vector3, _a: float, t: float) -> Color:
		return Color(0.0, 0.3, 0.36, 0.96).lerp(Color(0.12, 0.7, 0.72, 0.95), t))
	k.cylinder("own:gel:cyan", Transform3D(Basis.IDENTITY, Vector3(0, 0.059, 0)), 0.0022, 0.0016, 0.007, 8, false, 0.0, 1, Color(0.4, 0.9, 0.85, 0.9))
	k.sphere("own:glow:cyan", Transform3D(Basis.IDENTITY, Vector3(0, 0.069, 0)), 0.0042, 8, 10, 0.0, 1.0, Color(0.6, 1.0, 0.95, 0.9))
	k.sphere("own:wet", Transform3D(Basis.IDENTITY, Vector3(0, 0.006, 0)), 0.01, 8, 10, 0.1, 0.7, Color(0.24, 0.22, 0.12))
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		var len := 0.054 + 0.008 * sin(i * 2.1)
		var b := Basis(Vector3.UP, -a)
		var f := func(u: float, v: float) -> Vector3:
			var s := lerpf(-1.0, 1.0, v)
			var w := 0.015 * pow(sin(PI * pow(u, 0.6)), 0.9)
			var rad := 0.009 + 0.016 * sin(u * PI * 0.75) - 0.004 * absf(s) + 0.012 * u * u * u
			return b * Vector3(rad, 0.003 + u * len, s * w)
		var col := func(u: float, v: float) -> Color:
			var s := absf(lerpf(-1.0, 1.0, v))
			return Color(0.36, 0.3, 0.14).lerp(Color(0.08, 0.2, 0.14), s * 0.9).lerp(Color(0.62, 0.48, 0.24), smoothstep(0.85, 1.0, s) * 0.5)
		_grid(k, "own:leaf", Transform3D.IDENTITY, f, 10, 6, 0.0015, col)

# --- Materials --------------------------------------------------------------------------

static func mat(name: String) -> Material:
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_lock.unlock()
	return m

## A vertex-coloured material. Under an even sky a glossy dark surface turns milky if it
## reflects much, so these keep the specular low (`spec`) and let a little metal tint
## what they reflect; `coat` is a thin clearcoat for the wet glint.
static func _std(rough: float, metal := 0.0, spec := 0.5, coat := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = spec
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.1
	return m

static func _make(n: String) -> Material:
	var hue := n.get_slice(":", 1)
	match n.get_slice(":", 0):
		"glow":
			# Clear crystal with a faint light of its own.
			var m := _std(0.06, 0.35, 0.3, 0.2)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.emission_enabled = HUE.has(hue)
			m.emission = HUE.get(hue, Color.BLACK)
			m.emission_energy_multiplier = 0.12
			return m
		"gel":
			# Jelly and liquid light: glossy, half clear, softly lit.
			var m := _std(0.1, 0.3, 0.3, 0.2)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.emission_enabled = HUE.has(hue)
			m.emission = HUE.get(hue, Color.BLACK)
			m.emission_energy_multiplier = 0.3 if hue == "gold" else 0.1
			return m
		"skin":
			# Wet living skin with a faint light under it.
			var m := _std(0.18, 0.2, 0.25, 0.2)
			m.emission_enabled = true
			m.emission = HUE.get(hue, Color.WHITE)
			m.emission_energy_multiplier = 0.04
			return m
		"wet":
			return _std(0.18, 0.15, 0.25, 0.25)
		"membrane", "film":
			var m := _std(0.12, 0.0, 0.3, 0.2)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"shell":
			# Chitin and scale: hard, lacquer-bright, a metallic sheen like a beetle's back.
			return _std(0.22, 0.45, 0.5, 0.5)
		"chitin":
			return _std(0.38, 0.0, 0.3, 0.2)
		"silk":
			return _std(0.3, 0.35, 0.4, 0.3)
		"trace":
			return _std(0.35, 0.25, 0.3)
		"chrome":
			return _std(0.06, 1.0)
		"leaf":
			return _std(0.35, 0.2, 0.3, 0.3)
		"irid":
			var m := _std(0.04, 0.3, 0.5, 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			return m
		"glass":
			# Thin clear glass: a gloss over what it holds, little colour of its own.
			var m := _std(0.04, 0.0, 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.render_priority = 1
			return m
	return ItemModels.mat("im:paint")
