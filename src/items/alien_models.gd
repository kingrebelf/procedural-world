class_name AlienModels
## Alien relics, materials, implants, ammunition and shields: the endgame's carved, organic and crystal things. Only alien matter may glow, faintly.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.
##
## The relics share a look: ornate gold and bronze filigree, dark carved metal, and purple
## and blue crystal or nebula glass that glows a little ("own:nebula", "own:gem",
## "own:core": swirled clouds of colour with a pale hot heart and pin-prick stars). Shared
## parts: _wire/_cage (the filigree frame), _gem and _shard (the crystal), _key (the five
## alien keys' shaft and bit; each key adds its own bow).

const BUILD := {
	"stasis_mine": "_stasis_mine",
	"relic_eye": "_relic_eye", "relic_heart": "_relic_heart", "relic_cube": "_relic_cube",
	"relic_seed": "_relic_seed", "relic_skull": "_relic_skull", "relic_idol": "_relic_idol",
	"orb_memory": "_orb_memory", "tablet_star": "_tablet_star", "key_gate": "_key_gate",
	"shard_god": "_shard_god", "egg_alien": "_egg_alien", "crown_hive": "_crown_hive",
	"chalice_star": "_chalice_star", "mirror_void": "_mirror_void", "bell_astral": "_bell_astral",
	"lantern_spirit": "_lantern_spirit", "hourglass_time": "_hourglass_time",
	"map_galaxy": "_map_galaxy", "beacon_ancient": "_beacon_ancient", "codex_alien": "_codex_alien",
	"core_titan": "_core_titan", "feather_phoenix": "_feather_phoenix", "coin_alien": "_coin_alien",
	"implant_eye": "_implant_eye", "implant_spine": "_implant_spine", "implant_heart": "_implant_heart",
	"implant_arm": "_implant_arm", "implant_brain": "_implant_brain", "symbiote": "_symbiote",
	"teleport_shard": "_teleport_shard", "shield_charm": "_shield_charm",
	"revive_feather": "_revive_feather", "summon_orb": "_summon_orb", "time_shard": "_time_shard",
	"key_hive": "_key_hive", "key_void": "_key_void", "key_star": "_key_star",
	"key_precursor": "_key_precursor", "keystone": "_keystone", "sigil_stone": "_sigil_stone",
}

const GOLD := Color(0.86, 0.64, 0.3)
const BRONZE := Color(0.56, 0.42, 0.25)
const DARK := Color(0.2, 0.19, 0.22)
const IVORY := Color(0.56, 0.53, 0.46)
const BLACK := Color(0.05, 0.05, 0.07)
const G := "im:metal@0.28"
const DM := "im:metal@0.42"
const NEB := "own:nebula"
const GEM := "own:gem"

# --- Shared parts -----------------------------------------------------------------------

static func _at(p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, p)

## A basis whose +Y runs along `d`.
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var a := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := a.cross(y).normalized()
	return Basis(x, y, x.cross(y))

## Faces +Z instead of +Y (for lathes and tori that should face the viewer).
static func _front() -> Basis:
	return Basis(Vector3.RIGHT, PI * 0.5)

## A smooth path through control points (Catmull-Rom).
static func _smooth(pts: Array, steps := 5) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		for s in steps:
			var u := float(s) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	out.append(pts[n - 1])
	return out

## Filigree: a wire through `pts`, full in the middle and drawn fine at the ends (`taper`
## 1 keeps it even).
static func _wire(k: MeshKit, pts: Array, r: float, col := GOLD, m := G, taper := 0.4, segs := 6) -> void:
	var path := _smooth(pts)
	var radii := PackedFloat32Array()
	for i in path.size():
		var t := float(i) / (path.size() - 1)
		radii.append(r * lerpf(taper, 1.0, sin(PI * t)))
	ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, segs, col)

## A closed ring of wire through `pts`.
static func _loop(k: MeshKit, pts: Array, r: float, col := GOLD, m := G) -> void:
	var p := pts.duplicate()
	p.push_front(pts[pts.size() - 1])
	p.append(pts[0])
	p.append(pts[1])
	var path := _smooth(p)
	path = path.slice(5, path.size() - 5)
	var radii := PackedFloat32Array()
	radii.resize(path.size())
	radii.fill(r)
	ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 6, col, false)

## A horn, claw or thorn: from `base` along `dir`, curling by `bend`, tapered to a point.
static func _horn(k: MeshKit, base: Vector3, dir: Vector3, bend: Vector3, length: float, r: float, col := GOLD, m := G) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var t := i / 8.0
		path.append(base + dir.normalized() * length * t + bend * length * t * t)
		radii.append(r * (1.0 - t) + 0.0002)
	ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 6, col)

## The filigree cage: `ribs` bands from pole to pole over an ellipsoid (radii `e`) about
## `c` between latitudes lat (radians up from the bottom pole), each twisted by `twist`,
## and a ring at each latitude in `bands`.
static func _cage(k: MeshKit, c: Vector3, e: Vector3, ribs: int, r: float, col := GOLD, m := G, lat := Vector2(0.2, PI - 0.2), bands: Array = [], twist := 0.0, phase := 0.0) -> void:
	for i in ribs:
		var a0 := phase + TAU * i / ribs
		var pts: Array = []
		for j in 11:
			var phi := lerpf(lat.x, lat.y, j / 10.0)
			var a := a0 + twist * (j / 10.0 - 0.5)
			pts.append(c + Vector3(sin(phi) * cos(a) * e.x, -cos(phi) * e.y, sin(phi) * sin(a) * e.z))
		_wire(k, pts, r, col, m, 0.6)
	for b: float in bands:
		var ring: Array = []
		for j in 16:
			var a := TAU * j / 16.0
			ring.append(c + Vector3(sin(b) * cos(a) * e.x, -cos(b) * e.y, sin(b) * sin(a) * e.z))
		_loop(k, ring, r, col, m)

## A cut stone domed out along `n` in a gold bezel: the glowing eye of most relics.
static func _gem(k: MeshKit, c: Vector3, n: Vector3, rad: float, col: Color, bezel := GOLD, dome := 0.6) -> void:
	var b := _along(n)
	k.sphere(GEM, Transform3D(b, c), rad, 8, 14, 0.0, dome, col, true)
	if bezel.a > 0.0:
		ItemModels._torus(k, G, Transform3D(b, c), rad * 1.03, rad * 0.17, 18, 6, bezel)

## A faceted crystal pointed both ways (long axis along xf's Y, girdle at y = 0).
static func _shard(k: MeshKit, m: String, xf: Transform3D, rad: float, up: float, down: float, col: Color, sides := 6) -> void:
	k.crystal(m, xf, rad, up, sides, 0.45, col)
	k.crystal(m, xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO), rad, down, sides, 0.6, col)

## A slab cut to the outline `poly` (x, y on the face; convex or star-shaped about its
## middle) and `depth` thick, facing +Z; `prof` lists [z fraction -0.5..0.5, outline
## scale] back to front, so the slab can bevel, dome or swell.
static func _slab(k: MeshKit, m: String, xf: Transform3D, poly: PackedVector2Array, depth: float, col: Color, prof: Array = [[-0.5, 0.9], [-0.35, 1.0], [0.35, 1.0], [0.5, 0.9]]) -> void:
	var rings: Array = []
	for p: Array in prof:
		var ring := PackedVector3Array()
		for v in poly:
			ring.append(Vector3(v.x * p[1], p[0] * depth, -v.y * p[1]))
		rings.append(ring)
	ItemModels._loft(k, m, xf * Transform3D(_front(), Vector3.ZERO), rings, col)

static func _circle(r: float, n: int, rng: RandomNumberGenerator = null, wob := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var rr := r * (1.0 + (rng.randf_range(-wob, wob) if rng != null else 0.0))
		out.append(Vector2(cos(a), sin(a)) * rr)
	return out

static func _heart(s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		out.append(Vector2(16.0 * pow(sin(t), 3.0), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) * s)
	return out

static func _almond(w: float, h: float, n := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(Vector2(cos(a) * w, sin(a) * h * pow(absf(sin(a)), 0.15) * (1.0 - 0.15 * cos(a) * cos(a))))
	return out

## A straight bar from a to b (box `th` square).
static func _bar(k: MeshKit, m: String, a: Vector3, b: Vector3, th: Vector2, col: Color) -> void:
	ItemModels._block(k, m, Transform3D(_along(b - a), (a + b) * 0.5), Vector3(th.x, a.distance_to(b), th.y), minf(th.x, th.y) * 0.25, col)

## A turned part: Provisions.lathe about +Y at `at`.
static func _turn(k: MeshKit, m: String, at: Vector3, prof: Array, col: Variant, segs := 28, shape: Variant = null, arc := Vector2(0.0, 1.0)) -> void:
	Provisions.lathe(k, m, _at(at), PackedVector2Array(prof), segs, col, shape, arc)

## The alien key's shaft and bit: a shaft up +Y from the bit at y = 0 to the bow at `top`.
## `bit`: "teeth" (stepped wards), "cross", "ball" (a spiked ball) or "blocks" (stepped
## cubes); `thorns` thorns up the shaft. Returns the grip (where the bow starts).
static func _key(k: MeshKit, m: String, col: Color, top: float, sr: float, bit: String, square := false, thorns := 0) -> Vector3:
	if square:
		ItemModels._block(k, m, _at(Vector3(0, top * 0.5, 0)), Vector3(sr * 2.0, top, sr * 2.0), sr * 0.3, col)
	else:
		k.cylinder(m, _at(Vector3.ZERO), sr, sr * 1.15, top, 12, true, 0.0, 1, col)
	for y: float in [top * 0.62, top * 0.9]:
		if square:
			ItemModels._block(k, m, _at(Vector3(0, y, 0)), Vector3(sr * 3.2, sr * 1.6, sr * 3.2), sr * 0.3, col)
		else:
			ItemModels._torus(k, m, _at(Vector3(0, y, 0)), sr * 1.2, sr * 0.65, 14, 6, col)
	match bit:
		"teeth":
			for i in 3:
				var w: float = [0.016, 0.011, 0.014][i]
				ItemModels._block(k, m, _at(Vector3(w * 0.5, 0.004 + i * 0.0065, 0)), Vector3(w, 0.0045, sr * 1.6), 0.0008, col)
		"cross":
			ItemModels._block(k, m, _at(Vector3(0, 0.005, 0)), Vector3(0.024, 0.005, sr * 1.6), 0.0008, col)
			ItemModels._block(k, m, _at(Vector3(0.004, 0.014, 0)), Vector3(0.016, 0.004, sr * 1.6), 0.0008, col)
			ItemModels._block(k, m, _at(Vector3(0.011, 0.009, 0)), Vector3(0.004, 0.014, sr * 1.6), 0.0008, col)
		"ball":
			k.sphere(m, _at(Vector3(0, -0.002, 0)), 0.0075, 8, 12, 0.0, 1.0, col)
			for i in 14:
				var d := Vector3(cos(i * 2.4) * sin(0.4 + i * 0.19), cos(0.4 + i * 0.19), sin(i * 2.4) * sin(0.4 + i * 0.19))
				d.y = -absf(d.y) if i % 2 == 0 else d.y * 0.5
				_horn(k, Vector3(0, -0.002, 0) + d.normalized() * 0.006, d, Vector3.ZERO, 0.012, 0.0022, col, m)
		"blocks":
			for i in 3:
				var w: float = [0.018, 0.012, 0.016][i]
				ItemModels._block(k, m, _at(Vector3(w * 0.5, 0.005 + i * 0.008, 0)), Vector3(w, 0.0065, sr * 2.0), 0.0008, col)
	for i in thorns:
		var y := top * (0.15 + 0.75 * i / maxf(thorns - 1, 1))
		var sx := 1.0 if i % 2 == 0 else -1.0
		_horn(k, Vector3(sx * sr * 0.8, y, 0), Vector3(sx, 0.7, 0), Vector3(0, 0.5, 0), 0.011, sr * 0.7, col, m)
	return Vector3(0, top, 0)

# --- Relics -----------------------------------------------------------------------------

## A squat dark disc of segmented armour plates, gold claws round the rim each set with a
## blue stone, and a blue-glowing emitter ring in the middle: the icon's stasis mine.
static func _stasis_mine(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var plate := Color(0.42, 0.42, 0.45)
	var m := "im:metal@0.5"
	_turn(k, m, Vector3.ZERO, [Vector2(0, 0), Vector2(0.07, 0), Vector2(0.08, 0.006), Vector2(0.082, 0.024), Vector2(0.074, 0.032), Vector2(0.04, 0.04), Vector2(0.03, 0.04), Vector2(0.03, 0.04), Vector2(0.026, 0.034), Vector2(0, 0.034)], plate.darkened(0.3), 48)
	# Armour plates: a ring of raised segments on the top and round the side wall.
	for i in 14:
		var a := TAU * (i + 0.5) / 14.0
		var d := Vector3(cos(a), 0, sin(a))
		var b := _facing(d) * Basis(Vector3.RIGHT, -1.25)
		k.bevel_box(m, Transform3D(b, d * 0.056 + Vector3(0, 0.037, 0)), Vector3(0.021, 0.026, 0.006), 0.0015, plate)
		k.bevel_box(m, Transform3D(_facing(d), d * 0.08 + Vector3(0, 0.015, 0)), Vector3(0.03, 0.02, 0.006), 0.0015, plate.darkened(0.15))
	ItemModels._torus(k, G, _at(Vector3(0, 0.03, 0)), 0.078, 0.0018, 48, 6, GOLD)
	ItemModels._torus(k, G, _at(Vector3(0, 0.04, 0)), 0.031, 0.002, 32, 6, GOLD)
	ItemModels._torus(k, m, _at(Vector3(0, 0.044, 0)), 0.026, 0.004, 32, 6, plate)
	# Gold claws on the side wall, pointing up, a blue stone in each.
	for i in 6:
		var a := TAU * (i + 0.25) / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		var p := d * 0.084 + Vector3(0, 0.016, 0)
		_slab(k, G, Transform3D(_facing(d) * Basis(Vector3.RIGHT, -0.25), p), PackedVector2Array([Vector2(0, 0.024), Vector2(0.012, -0.012), Vector2(0, -0.006), Vector2(-0.012, -0.012)]), 0.005, GOLD)
		_gem(k, p + d * 0.004 + Vector3(0, 0.001, 0), d + Vector3(0, 0.3, 0), 0.003, Color(0.3, 0.45, 1.0))
	# The emitter: a glowing ring and a dome in the middle.
	ItemModels._torus(k, GEM, _at(Vector3(0, 0.046, 0)), 0.018, 0.003, 32, 8, Color(0.4, 0.6, 1.0))
	_gem(k, Vector3(0, 0.045, 0), Vector3.UP, 0.01, Color(0.45, 0.6, 1.0), DARK, 0.7)
	_shard(k, GEM, _at(Vector3(0, 0.05, 0)), 0.003, 0.016, 0.002, Color(0.6, 0.75, 1.0), 4)
	return null

## A basis facing horizontal direction d (+Z along d, +Y up).
static func _facing(d: Vector3) -> Basis:
	return Basis(Vector3.UP.cross(d).normalized(), Vector3.UP, d.normalized())

## An almond eye of violet-blue nebula glass with a black slit pupil, in a frame of dark
## carved metal bristling with thorns above and below, as the icon's watching eye.
static func _relic_eye(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	var frame := Color(0.24, 0.22, 0.26)
	k.sphere(NEB, Transform3D(Basis.from_scale(Vector3(1.75, 0.95, 0.65)), Vector3.ZERO), 0.024, 12, 20, 0.0, 1.0, Color(0.5, 0.3, 0.95))
	k.sphere("im:metal@0.15", Transform3D(Basis.from_scale(Vector3(0.12, 0.9, 0.3)), Vector3(0, 0, 0.011)), 0.022, 8, 10, 0.0, 1.0, BLACK)
	var lid: Array = []
	for v in _almond(0.046, 0.024, 20):
		lid.append(Vector3(v.x, v.y, 0.006 - absf(v.x) * 0.12))
	_loop(k, lid, 0.005, frame, DM)
	var lid2: Array = []
	for v in _almond(0.054, 0.031, 20):
		lid2.append(Vector3(v.x, v.y, -0.002))
	_loop(k, lid2, 0.004, frame.darkened(0.2), DM)
	# Thorns: a crest fanning up over the eye, fewer below, long ones at the corners.
	for i in 15:
		var u := (i - 7) / 7.0
		var base := Vector3(u * 0.045, 0.026 * (1.0 - u * u * 0.6), -0.003 - 0.003 * float(i % 2))
		_horn(k, base, Vector3(u * 1.1, 1.0, -0.2), Vector3(u * 0.6, 0, 0), r.randf_range(0.016, 0.03) * (1.25 - absf(u) * 0.45), 0.0065, frame.lightened(0.05 * float(i % 3)), DM)
	for i in 10:
		var u := (i - 4.5) / 4.5
		var base := Vector3(u * 0.04, -0.024 * (1.0 - u * u * 0.6), -0.003)
		_horn(k, base, Vector3(u * 0.9, -1.0, -0.2), Vector3(u * 0.4, 0, 0), r.randf_range(0.012, 0.024), 0.0055, frame, DM)
	for sx: float in [-1.0, 1.0]:
		_horn(k, Vector3(sx * 0.05, 0, -0.002), Vector3(sx, 0.08, 0), Vector3(0, 0.2, 0), 0.026, 0.007, frame, DM)
	return null

## A heart of blue-violet nebula crystal, swelled like a cut stone, framed in gold with a
## spiked gold crest rising from the notch and small stones in the lobes.
static func _relic_heart(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var hp := _heart(0.0027)
	_slab(k, NEB, Transform3D.IDENTITY, hp, 0.032, Color(0.45, 0.38, 1.0), [[-0.5, 0.55], [-0.3, 0.92], [0.0, 1.0], [0.3, 0.92], [0.5, 0.55]])
	var rim: Array = []
	for v in _heart(0.00285):
		rim.append(Vector3(v.x, v.y, 0.0))
	_loop(k, rim, 0.0035, GOLD)
	var rim2: Array = []
	for v in _heart(0.0021):
		rim2.append(Vector3(v.x, v.y, 0.0125))
	_loop(k, rim2, 0.0012, GOLD)
	# Thorned flourishes along the frame.
	for i in 10:
		var v: Vector2 = _heart(0.003)[(i * 4 + 2) % 40]
		var d := Vector3(v.x, v.y - 0.004, 0).normalized()
		_horn(k, Vector3(v.x, v.y, 0), d, Vector3(0, 0.3, 0), 0.008, 0.0028, GOLD)
	# The crest: a tall spike with two curling side horns over the notch, a stone at its foot.
	_horn(k, Vector3(0, 0.02, 0), Vector3.UP, Vector3.ZERO, 0.032, 0.0045, GOLD)
	for sx: float in [-1.0, 1.0]:
		_horn(k, Vector3(sx * 0.004, 0.022, 0), Vector3(sx * 0.6, 1.0, 0), Vector3(-sx * 0.5, 0, 0), 0.025, 0.004, GOLD)
	_gem(k, Vector3(0, 0.026, 0.004), Vector3(0, 0, 1), 0.0035, Color(0.4, 0.8, 0.9))
	for sx: float in [-1.0, 1.0]:
		_gem(k, Vector3(sx * 0.024, 0.02, 0.006), Vector3(sx * 0.3, 0.3, 1), 0.003, Color(0.85, 0.45, 0.9))
	return null

## A cube cage of dark blue metal edges braced by gold diagonals, a blue nebula core
## floating in the middle with a bright star at its heart.
static func _relic_cube(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var h := 0.042
	var navy := Color(0.14, 0.16, 0.32)
	var c := Vector3(0, h, 0)
	for ax in 3:
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				a[ax] = -h
				b[ax] = h
				a[(ax + 1) % 3] = s1 * h
				b[(ax + 1) % 3] = s1 * h
				a[(ax + 2) % 3] = s2 * h
				b[(ax + 2) % 3] = s2 * h
				_bar(k, "im:metal@0.35", c + a * 1.04, c + b * 1.04, Vector2(0.0095, 0.0095), navy)
	# A gold diagonal and corner brackets on each face.
	for ax in 3:
		for s: float in [-1.0, 1.0]:
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			a[ax] = s * h
			b[ax] = s * h
			a[(ax + 1) % 3] = -h
			b[(ax + 1) % 3] = h
			a[(ax + 2) % 3] = -h * s
			b[(ax + 2) % 3] = h * s
			_bar(k, G, c + a * 0.98, c + b * 0.98, Vector2(0.0035, 0.0035), GOLD)
			# A gold chevron from the diagonal's middle out to a third corner.
			var e := Vector3.ZERO
			e[ax] = s * h * 0.98
			e[(ax + 1) % 3] = h * 0.98
			e[(ax + 2) % 3] = h * s * 0.98 * -1.0
			_bar(k, G, c + (a + b) * 0.49, c + e, Vector2(0.003, 0.003), GOLD)
	k.sphere(NEB, _at(c), 0.024, 12, 16, 0.0, 1.0, Color(0.25, 0.4, 1.0))
	_shard(k, GEM, _at(c + Vector3(0, 0, 0.02)), 0.004, 0.009, 0.009, Color(0.85, 0.9, 1.0), 4)
	_shard(k, GEM, _at(c + Vector3(0, 0, 0.02), Basis(Vector3(0, 0, 1), PI * 0.5)), 0.004, 0.009, 0.009, Color(0.85, 0.9, 1.0), 4)
	return null

## The egg-shaped radius at height fraction t (0 bottom .. 1 top), for eggs and shells.
static func _egg_r(t: float, rad: float) -> float:
	return rad * pow(maxf(sin(PI * pow(clampf(t, 0.0, 1.0), 0.85)), 0.0), 0.62)

static func _egg_prof(rad: float, h: float, t1 := 1.0, n := 16) -> Array:
	var out: Array = []
	for i in n + 1:
		var t := t1 * i / n
		out.append(Vector2(_egg_r(t, rad), t * h))
	return out

## A little world (blue seas, green and brown land, white cloud) sitting in a bronze egg of
## scales broken open at the front, as the icon's star seed.
static func _relic_seed(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var rad := 0.044
	var h := 0.112
	k.sphere("own:globe", _at(Vector3(0, 0.05, 0.004)), 0.036, 16, 24, 0.0, 1.0, Color.WHITE)
	var scales := func(a: float, t: float, _p: Vector3) -> float:
		var row := floorf(t * 14.0)
		var u := fposmod(a * 22.0 / TAU + row * 0.5, 1.0)
		return 1.0 + 0.07 * sin(u * PI) * fposmod(t * 14.0, 1.0) - 0.03
	var outer := _egg_prof(rad, h, 0.9)
	var shellc := func(_p: Vector3, a: float, t: float) -> Color:
		return BRONZE.darkened(0.35).lerp(GOLD, 0.45 * fposmod(t * 14.0, 1.0)).lerp(Color(0.4, 0.35, 0.45), 0.3 * absf(sin(a * 11.0 + t * 30.0)))
	_turn(k, "im:metal@0.55", Vector3.ZERO, outer, shellc, 132, scales, Vector2(0.3, 1.06))
	var inner: Array = []
	for i in range(outer.size() - 1, -1, -1):
		var v: Vector2 = outer[i]
		inner.append(Vector2(v.x * 0.9, v.y + 0.003))
	_turn(k, "im:metal@0.6", Vector3.ZERO, inner, BRONZE.darkened(0.5), 36, null, Vector2(0.3, 1.06))
	# Gold lips along the broken edges and round the top.
	for a: float in [0.3, 1.06]:
		var edge: Array = []
		for v: Vector2 in outer:
			var aa := TAU * a
			edge.append(Vector3(cos(aa) * v.x * 0.97, v.y, sin(aa) * v.x * 0.97))
		_wire(k, edge.slice(1), 0.0025, GOLD, G, 0.5)
	var top_lip: Array = []
	var tv: Vector2 = outer[outer.size() - 1]
	for j in 13:
		var aa := TAU * lerpf(0.3, 1.06, j / 12.0)
		top_lip.append(Vector3(cos(aa) * tv.x * 0.96, tv.y, sin(aa) * tv.x * 0.96))
	_wire(k, top_lip, 0.0022, GOLD, G, 0.7)
	return null

## An elongated alien skull of old dark bone: tall swept-back cranium carved with grooves,
## huge dark eye sockets, small nose pits and a row of teeth.
static func _relic_skull(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var bone := Color(0.46, 0.42, 0.35)
	var cran := Transform3D(Basis(Vector3.RIGHT, -0.5) * Basis.from_scale(Vector3(0.95, 1.15, 1.1)), Vector3(0, 0.07, -0.012))
	k.sphere("im:metal@0.6", cran, 0.037, 14, 20, 0.04, 1.0, bone)
	k.sphere("im:metal@0.6", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.85)), Vector3(0, 0.04, 0.012)), 0.034, 12, 16, 0.03, 1.0, bone)
	_wire(k, [Vector3(-0.03, 0.05, 0.022), Vector3(-0.016, 0.062, 0.034), Vector3(0, 0.058, 0.038), Vector3(0.016, 0.062, 0.034), Vector3(0.03, 0.05, 0.022)], 0.0035, bone, "im:metal@0.6", 0.5)
	for sx: float in [-1.0, 1.0]:
		k.sphere("im:metal@0.6", Transform3D(Basis.from_scale(Vector3(0.7, 0.5, 0.8)), Vector3(sx * 0.024, 0.032, 0.024)), 0.012, 6, 10, 0.0, 1.0, bone)
	k.sphere("im:metal@0.6", Transform3D(Basis.from_scale(Vector3(0.6, 0.55, 0.8)), Vector3(0, 0.01, 0.018)), 0.025, 10, 14, 0.0, 1.0, bone.darkened(0.08))
	# Eye sockets, slanted.
	for sx: float in [-1.0, 1.0]:
		var b := Basis(Vector3(0, 0, 1), sx * 0.45) * Basis.from_scale(Vector3(1.3, 0.85, 0.55))
		k.sphere("im:metal@0.7", Transform3D(b, Vector3(sx * 0.0155, 0.047, 0.033)), 0.0135, 8, 12, 0.0, 1.0, Color(0.05, 0.04, 0.035))
	for sx: float in [-1.0, 1.0]:
		k.sphere("im:metal@0.7", Transform3D(Basis.from_scale(Vector3(0.5, 1.0, 0.5)), Vector3(sx * 0.003, 0.026, 0.041)), 0.005, 6, 8, 0.0, 1.0, Color(0.06, 0.05, 0.04))
	for i in 8:
		var a := lerpf(-0.75, 0.75, i / 7.0)
		k.bevel_box("im:bone", Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 0.02, 0.013, 0.012 + cos(a) * 0.02)), Vector3(0.004, 0.008, 0.004), 0.001, Color(0.72, 0.66, 0.55))
	# Carved grooves sweeping back over the dome.
	for i in 11:
		var u := (i - 5) / 5.0 * 1.6
		var pts: Array = []
		for j in 7:
			var phi := lerpf(0.5, 2.9, j / 6.0)
			var p := Vector3(u * 0.55, sin(phi), cos(phi))
			pts.append(cran * (p.normalized() * 0.038))
		_wire(k, pts, 0.0026, bone.lightened(0.2), "im:metal@0.6", 0.5)
	return null

## A totem of dark carved metal: a stepped plinth, crossed blades in two tiers like an X,
## and a pronged diamond head holding a dark violet orb.
static func _relic_idol(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var m := "im:metal@0.35"
	var c := Color(0.15, 0.14, 0.17)
	ItemModels._block(k, m, _at(Vector3(0, 0.006, 0)), Vector3(0.096, 0.014, 0.044), 0.002, c)
	ItemModels._block(k, m, _at(Vector3(0, 0.016, 0)), Vector3(0.05, 0.009, 0.03), 0.002, c.lightened(0.05))
	for tier in 2:
		var y0 := 0.02 + tier * 0.045
		var w := 0.03 - tier * 0.007
		for sx: float in [-1.0, 1.0]:
			_bar(k, m, Vector3(-sx * w, y0, 0), Vector3(sx * w, y0 + 0.05, 0), Vector2(0.011, 0.012), c)
			_horn(k, Vector3(sx * w * 1.1, y0 + 0.052, 0), Vector3(sx * 0.4, 1, 0), Vector3.ZERO, 0.01, 0.003, c.lightened(0.1), m)
	# The head: two prongs bowing round the orb and meeting above it.
	var cy := 0.13
	for sx: float in [-1.0, 1.0]:
		_wire(k, [Vector3(0, cy - 0.024, 0), Vector3(sx * 0.02, cy - 0.006, 0), Vector3(sx * 0.016, cy + 0.014, 0), Vector3(sx * 0.004, cy + 0.032, 0)], 0.006, c, m, 0.5)
		_horn(k, Vector3(sx * 0.018, cy + 0.008, 0), Vector3(sx, 0.5, 0), Vector3.ZERO, 0.02, 0.0045, c, m)
	k.sphere(GEM, _at(Vector3(0, cy, 0)), 0.0085, 10, 14, 0.0, 1.0, Color(0.22, 0.12, 0.35))
	_bar(k, m, Vector3(0, 0.1, 0), Vector3(0, cy - 0.02, 0), Vector2(0.006, 0.006), c)
	return null

## A great crystal ball full of a dreamt city under a violet-blue sky, cupped from below
## by curling gold claws on a gold ring.
static func _orb_memory(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0, 0.05, 0)
	k.sphere(NEB, _at(c), 0.042, 18, 28, 0.0, 1.0, Color(0.4, 0.5, 1.0))
	ItemModels._torus(k, G, _at(Vector3(0, 0.016, 0)), 0.03, 0.0035, 32, 6, GOLD)
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		var d := Vector3(cos(a), 0, sin(a))
		_wire(k, [d * 0.026 + Vector3(0, 0.008, 0), d * 0.036 + Vector3(0, 0.018, 0), d * 0.045 + Vector3(0, 0.036, 0), d * 0.043 + Vector3(0, 0.052, 0)], 0.0035, GOLD, G, 0.3)
	_turn(k, G, Vector3.ZERO, [Vector2(0, 0), Vector2(0.024, 0), Vector2(0.028, 0.006), Vector2(0.02, 0.012), Vector2(0, 0.012)], BRONZE, 24)
	return null

## A worn slab of dark slate inlaid with a gold star chart: rings, rays and star points
## about a bright star in the middle.
static func _tablet_star(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	var poly := PackedVector2Array()
	var corners := [Vector2(0.055, 0.065), Vector2(-0.055, 0.065), Vector2(-0.055, -0.065), Vector2(0.055, -0.065)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for j in 6:
			var p := a.lerp(b, j / 6.0)
			poly.append(p * (1.0 + r.randf_range(-0.04, 0.02)))
	_slab(k, "im:stone", Transform3D.IDENTITY, poly, 0.016, Color(0.2, 0.21, 0.24), [[-0.5, 0.95], [-0.3, 1.0], [0.3, 1.0], [0.5, 0.94]])
	var z := 0.0082
	for rr: float in [0.014, 0.028, 0.044]:
		ItemModels._torus(k, G, _at(Vector3(0, 0, z), _front()), rr, 0.0007, 40, 4, GOLD)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		_bar(k, G, Vector3(cos(a) * 0.004, sin(a) * 0.004, z), Vector3(cos(a) * 0.05, sin(a) * 0.05, z), Vector2(0.0012, 0.0012), GOLD)
	for i in 14:
		var a := r.randf() * TAU
		var rr: float = [0.014, 0.028, 0.044][i % 3]
		k.sphere(G, _at(Vector3(cos(a) * rr, sin(a) * rr, z + 0.0005)), 0.0016, 4, 6, 0.0, 1.0, GOLD.lightened(0.2))
	_gem(k, Vector3(0, 0, z), Vector3(0, 0, 1), 0.004, Color(1.0, 0.92, 0.75), GOLD)
	for i in 4:
		var a := TAU * i / 4.0
		_horn(k, Vector3(0, 0, z + 0.001), Vector3(cos(a), sin(a), 0), Vector3.ZERO, 0.012, 0.0016, GOLD.lightened(0.3))
	return null

## The gate key: a gold key with crossed wards, the bow a ring round a blue star stone in
## a dark socket, scrolled with gold curls and a spike on top.
static func _key_gate(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var grip := _key(k, G, GOLD, 0.078, 0.0034, "cross")
	var c := grip + Vector3(0, 0.019, 0)
	k.cylinder(DM, _at(c + Vector3(0, 0, -0.004), _front()), 0.012, 0.012, 0.008, 20, true, 0.0, 1, DARK)
	_gem(k, c + Vector3(0, 0, 0.004), Vector3(0, 0, 1), 0.0095, Color(0.3, 0.4, 1.0), GOLD, 0.55)
	ItemModels._torus(k, G, _at(c, _front()), 0.0145, 0.0028, 28, 6, GOLD)
	for sx: float in [-1.0, 1.0]:
		var curl: Array = []
		for j in 9:
			var a := lerpf(-PI * 0.6, PI * 1.1, j / 8.0)
			var rr := lerpf(0.011, 0.004, j / 8.0)
			curl.append(c + Vector3(sx * (0.021 + cos(a) * rr), sin(a) * rr - 0.002, 0))
		_wire(k, curl, 0.0022, GOLD, G, 0.5)
		_horn(k, c + Vector3(sx * 0.01, 0.011, 0), Vector3(sx, 1.0, 0), Vector3(sx * 0.4, 0, 0), 0.012, 0.0022, GOLD)
	_horn(k, c + Vector3(0, 0.014, 0), Vector3.UP, Vector3.ZERO, 0.013, 0.003, GOLD)
	_gem(k, c + Vector3(0, 0.019, 0.002), Vector3(0, 0, 1), 0.0026, Color(0.35, 0.5, 1.0))
	return grip

## A spray of glowing pink, violet and gold crystal points bursting from a gold claw.
static func _shard_god(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	var cols := [Color(0.95, 0.5, 0.85), Color(0.55, 0.35, 1.0), Color(1.0, 0.7, 0.35), Color(0.8, 0.4, 0.95)]
	_shard(k, GEM, _at(Vector3(0, 0.03, 0)), 0.016, 0.085, 0.02, cols[0], 6)
	for i in 6:
		var a := TAU * i / 6.0 + r.randf() * 0.4
		var tilt := Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.35)
		_shard(k, GEM, Transform3D(_along(tilt), Vector3(cos(a) * 0.01, 0.026, sin(a) * 0.008)), r.randf_range(0.007, 0.011), r.randf_range(0.035, 0.06), 0.01, cols[(i + 1) % 4], 6)
	_turn(k, G, Vector3.ZERO, [Vector2(0, 0), Vector2(0.012, 0), Vector2(0.018, 0.012), Vector2(0.022, 0.026), Vector2(0, 0.026)], GOLD, 24)
	# The claw: gold leaves curling up the left side.
	for i in 3:
		var y := 0.01 + i * 0.012
		_wire(k, [Vector3(-0.015, y, 0.004), Vector3(-0.028, y + 0.015, 0.006), Vector3(-0.026, y + 0.035, 0.004), Vector3(-0.014, y + 0.05, 0.0)], 0.004 - i * 0.0007, GOLD, G, 0.25)
	_horn(k, Vector3(0.016, 0.02, 0.003), Vector3(0.5, 1, 0.1), Vector3(-0.3, 0, 0), 0.03, 0.0035, GOLD)
	return null

## An egg of iridescent teal and violet scale-glass webbed with black branching veins.
static func _egg_alien(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var rad := 0.046
	var h := 0.12
	var col := func(_p: Vector3, a: float, t: float) -> Color:
		return Color(0.25, 0.6, 0.6).lerp(Color(0.58, 0.35, 0.75), 0.5 + 0.5 * sin(a * 2.0 + t * 4.0))
	_turn(k, NEB, Vector3.ZERO, _egg_prof(rad, h, 1.0, 20), col, 40)
	for i in 7:
		var a0 := TAU * i / 7.0
		var vein: Array = []
		for j in 11:
			var t := 0.04 + 0.92 * j / 10.0
			var a := a0 + 0.35 * sin(t * 6.0 + i)
			var rr := _egg_r(t, rad) + 0.0012
			vein.append(Vector3(cos(a) * rr, t * h, sin(a) * rr))
		_wire(k, vein, 0.0022, BLACK, "im:metal@0.3", 0.5)
		for b in 3:
			var t0 := 0.25 + b * 0.22
			var a1 := a0 + 0.35 * sin(t0 * 6.0 + i)
			var branch: Array = []
			for j in 4:
				var t := t0 + j * 0.05
				var a := a1 + (0.12 if b % 2 == 0 else -0.12) * j
				var rr := _egg_r(t, rad) + 0.0012
				branch.append(Vector3(cos(a) * rr, t * h, sin(a) * rr))
			_wire(k, branch, 0.0015, BLACK, "im:metal@0.3", 0.3)
	return null

## A crown of dark bronze: a band rising into a tall scaled central spike and curved claws
## that sweep outward, violet crystal glinting between them.
static func _crown_hive(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var br := Color(0.48, 0.4, 0.3)
	var m := "im:metal@0.38"
	var R := 0.06
	_turn(k, m, Vector3.ZERO, [Vector2(R - 0.004, 0), Vector2(R + 0.003, 0), Vector2(R + 0.003, 0), Vector2(R + 0.005, 0.03), Vector2(R + 0.005, 0.03), Vector2(R - 0.004, 0.03), Vector2(R - 0.004, 0.03), Vector2(R - 0.004, 0)], br, 48)
	ItemModels._torus(k, m, _at(Vector3(0, 0.004, 0)), R + 0.004, 0.003, 48, 6, br.lightened(0.1))
	for i in 13:
		var a := PI * 0.5 + TAU * (i - 6) / 13.0
		var d := Vector3(cos(a), 0, sin(a))
		var front := absi(i - 6)
		var length := 0.12 if front == 0 else (0.085 if front % 2 == 1 else 0.055)
		var flare := 0.1 + front * 0.06
		_horn(k, d * (R + 0.002) + Vector3(0, 0.022, 0), Vector3.UP + d * flare, d * 0.3 * (front / 6.0), length, 0.013 if front == 0 else 0.009, br, m)
		_horn(k, d * (R + 0.006) + Vector3(0, 0.03, 0), Vector3.UP + d * (flare + 0.5), d * 0.3, length * 0.35, 0.004, br.lightened(0.1), m)
		if front > 0 and front % 2 == 0:
			_shard(k, NEB, Transform3D(_along(Vector3.UP + d * 0.4), d * (R - 0.003) + Vector3(0, 0.026, 0)), 0.008, 0.05, 0.004, Color(0.55, 0.2, 0.75), 5)
	# Scales up the front spike.
	for j in 4:
		var y := 0.036 + j * 0.016
		ItemModels._torus(k, m, Transform3D(Basis.from_scale(Vector3(1, 0.4, 1)), Vector3(0, y, R + 0.003 + (y - 0.022) * 0.15)), 0.011 - j * 0.002, 0.0015, 12, 4, br.lightened(0.15))
	return null

static func _cup_r(y: float) -> float:
	return lerpf(0.011, 0.045, pow(clampf((y - 0.078) / 0.09, 0.0, 1.0), 0.55))

## A gold goblet: a flared ribbed foot, a knopped stem set with blue stones, and a cup of
## glowing blue glass panels caged in gold leaves under a gold lip.
static func _chalice_star(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	_turn(k, G, Vector3.ZERO, [Vector2(0, 0), Vector2(0.036, 0), Vector2(0.036, 0.004), Vector2(0.026, 0.01), Vector2(0.012, 0.02), Vector2(0.007, 0.03), Vector2(0.011, 0.045), Vector2(0.006, 0.058), Vector2(0.007, 0.07), Vector2(0.012, 0.078), Vector2(0, 0.078)], GOLD, 32)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		_gem(k, Vector3(cos(a) * 0.011, 0.045, sin(a) * 0.011), Vector3(cos(a), 0, sin(a)), 0.003, Color(0.35, 0.5, 1.0))
	var prof: Array = []
	for i in 13:
		var y := 0.078 + 0.09 * i / 12.0
		prof.append(Vector2(_cup_r(y), y))
	_turn(k, NEB, Vector3.ZERO, prof, Color(0.4, 0.5, 1.0), 36)
	k.cylinder(NEB, _at(Vector3(0, 0.16, 0)), 0.043, 0.043, 0.001, 32, true, 0.0, 1, Color(0.2, 0.25, 0.6))
	ItemModels._torus(k, G, _at(Vector3(0, 0.168, 0)), 0.045, 0.003, 40, 6, GOLD)
	ItemModels._torus(k, G, _at(Vector3(0, 0.11, 0)), _cup_r(0.11) + 0.001, 0.0018, 36, 6, GOLD)
	for i in 8:
		var a := TAU * i / 8.0
		var rib: Array = []
		for j in 7:
			var y := 0.08 + 0.088 * j / 6.0
			var w := 0.12 * sin(PI * j / 6.0) * (1.0 if i % 2 == 0 else -1.0)
			var rr := _cup_r(y) + 0.0015
			rib.append(Vector3(cos(a + w) * rr, y, sin(a + w) * rr))
		_wire(k, rib, 0.0022, GOLD, G, 0.6)
	return null

## A round void of black-violet glass in a gold ring frame licked with gold flames and
## set with violet stones, held up on curving gold arms over a round plinth.
static func _mirror_void(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0, 0.1, 0)
	_turn(k, DM, Vector3.ZERO, [Vector2(0, 0), Vector2(0.046, 0), Vector2(0.048, 0.006), Vector2(0.04, 0.012), Vector2(0.012, 0.016), Vector2(0, 0.016)], BRONZE.darkened(0.3), 32)
	ItemModels._torus(k, G, _at(Vector3(0, 0.006, 0)), 0.047, 0.0025, 40, 6, GOLD)
	_slab(k, NEB, _at(c), _circle(0.044, 32), 0.006, Color(0.12, 0.06, 0.2))
	ItemModels._torus(k, G, _at(c, _front()), 0.047, 0.0055, 48, 8, GOLD)
	ItemModels._torus(k, G, _at(c + Vector3(0, 0, 0.003), _front()), 0.042, 0.0018, 48, 6, GOLD.darkened(0.15))
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(cos(a), sin(a), 0)
		if d.y < -0.6:
			continue
		_horn(k, c + d * 0.05, d + Vector3(0, 0.3, 0), Vector3(0, 0.3, 0), 0.012 + 0.008 * float(i % 2), 0.0035, GOLD)
	for d: Vector3 in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		_gem(k, c + d * 0.05 + Vector3(0, 0, 0.006), Vector3(0, 0, 1), 0.0045, Color(0.6, 0.3, 0.95))
	for sx: float in [-1.0, 1.0]:
		_wire(k, [Vector3(sx * 0.01, 0.014, 0), Vector3(sx * 0.03, 0.03, 0), Vector3(sx * 0.052, 0.06, 0), Vector3(sx * 0.05, 0.09, 0)], 0.004, GOLD, G, 0.6)
	_bar(k, G, Vector3(0, 0.014, 0), Vector3(0, 0.05, 0), Vector2(0.006, 0.006), GOLD)
	return null

## A bell of green-bronze engraved with bands and almond eyes, a loop on top and a
## round clapper showing under the lip.
static func _bell_astral(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var bz := Color(0.42, 0.42, 0.34)
	var m := "im:metal@0.5"
	var outer := [Vector2(0.06, 0.0), Vector2(0.058, 0.006), Vector2(0.05, 0.016), Vector2(0.042, 0.035), Vector2(0.036, 0.06), Vector2(0.034, 0.08), Vector2(0.03, 0.095), Vector2(0.018, 0.104), Vector2(0, 0.107)]
	_turn(k, m, Vector3.ZERO, outer, bz, 40)
	var inner: Array = []
	for i in range(outer.size() - 1, -1, -1):
		var v: Vector2 = outer[i]
		inner.append(Vector2(maxf(v.x - 0.004, 0.0), v.y - 0.004 if i < outer.size() - 1 else v.y - 0.008))
	_turn(k, m, Vector3.ZERO, inner, bz.darkened(0.55), 40)
	ItemModels._torus(k, m, _at(Vector3(0, 0.001, 0)), 0.059, 0.0025, 48, 6, bz.lightened(0.1))
	for y: float in [0.018, 0.07, 0.09]:
		var rr := 0.0
		for i in outer.size() - 1:
			var a: Vector2 = outer[i]
			var b: Vector2 = outer[i + 1]
			if y >= a.y and y <= b.y:
				rr = lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
		ItemModels._torus(k, G, _at(Vector3(0, y, 0)), rr + 0.0005, 0.0012, 40, 4, Color(0.62, 0.55, 0.35))
	# Almond eyes round the waist.
	for i in 6:
		var a := TAU * i / 6.0 + PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		var p := d * 0.041 + Vector3(0, 0.044, 0)
		var b := _along(d + Vector3(0, 0.25, 0)) * Basis.from_scale(Vector3(1.0, 1.0, 0.45))
		ItemModels._torus(k, G, Transform3D(b, p), 0.008, 0.0012, 18, 4, Color(0.62, 0.55, 0.35))
		k.sphere(G, Transform3D(_along(d), p), 0.0025, 4, 8, 0.0, 0.5, Color(0.62, 0.55, 0.35), true)
	ItemModels._torus(k, m, _at(Vector3(0, 0.117, 0), Basis(Vector3(0, 0, 1), PI * 0.5)), 0.009, 0.0028, 20, 6, bz)
	k.sphere(m, _at(Vector3(0, -0.006, 0)), 0.01, 8, 12, 0.0, 1.0, bz.lightened(0.15))
	return null

## A six-sided lantern of dark bronze: domed cap with a ring, latticed frame, and a
## teal spirit-glass core that glows faintly.
static func _lantern_spirit(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var br := Color(0.32, 0.3, 0.28)
	var m := "im:metal@0.38"
	_turn(k, m, Vector3.ZERO, [Vector2(0, 0), Vector2(0.05, 0), Vector2(0.053, 0.008), Vector2(0.045, 0.016), Vector2(0, 0.016)], br, 6)
	_turn(k, m, Vector3.ZERO, [Vector2(0, 0.112), Vector2(0.05, 0.112), Vector2(0.053, 0.12), Vector2(0.036, 0.132), Vector2(0.02, 0.142), Vector2(0, 0.145)], br, 6)
	_turn(k, NEB, Vector3.ZERO, [Vector2(0, 0.016), Vector2(0.04, 0.016), Vector2(0.042, 0.064), Vector2(0.04, 0.112), Vector2(0, 0.112)], Color(0.25, 0.8, 0.85), 6)
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		_wire(k, [d * 0.048 + Vector3(0, 0.02, 0), d * 0.052 + Vector3(0, 0.064, 0), d * 0.048 + Vector3(0, 0.114, 0)], 0.005, GOLD.lerp(br, 0.5), G, 1.0)
		_horn(k, d * 0.05 + Vector3(0, 0.12, 0), d + Vector3(0, 0.8, 0), Vector3.ZERO, 0.01, 0.0025, br, m)
		# Lattice across the panel.
		var a2 := a + TAU / 6.0
		var e := Vector3(cos(a2), 0, sin(a2))
		var p0 := d * 0.042
		var p1 := e * 0.042
		for j in 2:
			var y0 := 0.02 + j * 0.046
			_bar(k, m, p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0 + 0.046, 0), Vector2(0.0018, 0.0018), br)
			_bar(k, m, p1 + Vector3(0, y0, 0), p0 + Vector3(0, y0 + 0.046, 0), Vector2(0.0018, 0.0018), br)
	ItemModels._torus(k, m, _at(Vector3(0, 0.162, 0), Basis(Vector3(0, 0, 1), PI * 0.5)), 0.018, 0.0032, 24, 6, br)
	return null

## An hourglass: gold-bronze ends on four turned pillars, glass bulbs holding violet-gold
## star sand running from the top into a mound below.
static func _hourglass_time(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var br := BRONZE.lerp(GOLD, 0.2)
	for y: float in [0.0, 0.135]:
		_turn(k, G, Vector3(0, y, 0), [Vector2(0, 0), Vector2(0.044, 0), Vector2(0.046, 0.004), Vector2(0.046, 0.009), Vector2(0.04, 0.015), Vector2(0, 0.015)], br, 32)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var p := Vector3(cos(a), 0, sin(a)) * 0.037
		_turn(k, DM, p + Vector3(0, 0.015, 0), [Vector2(0, 0), Vector2(0.004, 0), Vector2(0.004, 0.006), Vector2(0.0025, 0.012), Vector2(0.0025, 0.05), Vector2(0.0045, 0.06), Vector2(0.0025, 0.07), Vector2(0.0025, 0.108), Vector2(0.004, 0.114), Vector2(0.004, 0.12), Vector2(0, 0.12)], BRONZE.darkened(0.3), 10)
	var glass := [Vector2(0.004, 0.015), Vector2(0.026, 0.02), Vector2(0.031, 0.035), Vector2(0.024, 0.058), Vector2(0.004, 0.075), Vector2(0.024, 0.092), Vector2(0.031, 0.115), Vector2(0.026, 0.13), Vector2(0.004, 0.135)]
	_turn(k, "im:glass", Vector3.ZERO, glass, Color(0.85, 0.8, 1.0, 0.1), 28)
	var sand := Color(0.6, 0.4, 0.85)
	_turn(k, NEB, Vector3.ZERO, [Vector2(0, 0.017), Vector2(0.027, 0.02), Vector2(0.029, 0.03), Vector2(0.018, 0.04), Vector2(0, 0.048)], sand, 24)
	_turn(k, NEB, Vector3.ZERO, [Vector2(0, 0.077), Vector2(0.012, 0.085), Vector2(0.022, 0.095), Vector2(0, 0.096)], sand.lightened(0.2), 24)
	k.cylinder(NEB, _at(Vector3(0, 0.044, 0)), 0.001, 0.001, 0.034, 6, false, 0.0, 1, sand.lightened(0.3))
	return null

## A star chart: a sheet of old parchment painted with a blue-violet spiral galaxy, rolled
## at top and bottom on dark rods with spiked, turned end caps.
static func _map_galaxy(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var w := 0.2
	var h := 0.13
	var parch := Color(0.6, 0.5, 0.34)
	var paint := func(p: Vector3, _u: float, _v: float) -> Color:
		var edge := minf(w * 0.5 - absf(p.x), h * 0.5 - absf(p.y))
		var q := Vector2(p.x, p.y * 1.25)
		var rn := q.length() / 0.04
		var ang := atan2(q.y, q.x)
		var arm := pow(0.5 + 0.5 * cos(2.0 * ang - rn * 5.5), 3.0)
		var bright := clampf(exp(-rn * 2.5) * 1.3 + arm * exp(-rn * 1.2) * 0.9, 0.0, 1.0)
		var sky := Color(0.07, 0.09, 0.22).lerp(Color(0.4, 0.3, 0.62), clampf(arm * exp(-rn * 0.8) * 1.1, 0.0, 1.0))
		sky = sky.lerp(Color(1.0, 0.85, 0.7), clampf(exp(-rn * 3.0) * 1.4, 0.0, 1.0) * bright)
		var spark := Provisions._nz(p, 900.0)
		if spark > 0.55:
			sky = sky.lerp(Color(0.95, 0.85, 0.6), 0.7)
		var ragged := 0.022 + 0.008 * Provisions._nz(p, 120.0)
		return parch.lerp(sky, smoothstep(ragged - 0.004, ragged + 0.004, edge))
	var f := func(u: float, v: float) -> Vector3:
		var x := (u - 0.5) * w
		var y := (v - 0.5) * h
		return Vector3(x, y, 0.003 * sin(u * 7.0) + 0.002 * sin(v * 5.0 + 1.0))
	Provisions.sheet(k, "im:linen", Transform3D.IDENTITY, 90, 60, f, paint, Vector3(0, 0, 1))
	Provisions.sheet(k, "im:linen", _at(Vector3(0, 0, -0.0008)), 8, 6, f, parch.darkened(0.1), Vector3(0, 0, -1))
	for sy: float in [-1.0, 1.0]:
		var y := sy * (h * 0.5 + 0.004)
		var rod := _at(Vector3(-0.12, y, 0), Basis(Vector3(0, 0, 1), -PI * 0.5))
		k.cylinder("im:linen", _at(Vector3(-w * 0.5, y, 0.0), Basis(Vector3(0, 0, 1), -PI * 0.5)), 0.009, 0.009, w, 20, true, 0.0, 1, parch.darkened(0.3))
		k.cylinder(DM, rod, 0.0055, 0.0055, 0.24, 12, true, 0.0, 1, DARK)
		for sx: float in [-1.0, 1.0]:
			var e := Vector3(sx * 0.108, y, 0)
			Provisions.lathe(k, G, _at(e, Basis(Vector3(0, 0, 1), -sx * PI * 0.5)), PackedVector2Array([Vector2(0, 0), Vector2(0.011, 0), Vector2(0.012, 0.004), Vector2(0.009, 0.008), Vector2(0.011, 0.012), Vector2(0.007, 0.016), Vector2(0.002, 0.026), Vector2(0, 0.027)]), 16, BRONZE.lerp(GOLD, 0.3))
	return null

## An ancient beacon: a tiered bronze base ringed with violet light, a gold cup holding a
## tall glowing blue crystal, gold claws curving up around it.
static func _beacon_ancient(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var br := Color(0.26, 0.23, 0.22)
	_turn(k, DM, Vector3.ZERO, [Vector2(0, 0), Vector2(0.052, 0), Vector2(0.054, 0.006), Vector2(0.052, 0.014), Vector2(0.044, 0.016), Vector2(0.044, 0.024), Vector2(0.034, 0.028), Vector2(0.03, 0.034), Vector2(0, 0.034)], br, 40)
	ItemModels._torus(k, G, _at(Vector3(0, 0.014, 0)), 0.053, 0.002, 48, 6, GOLD)
	ItemModels._torus(k, GEM, _at(Vector3(0, 0.022, 0)), 0.045, 0.0035, 48, 6, Color(0.6, 0.3, 0.95))
	for i in 12:
		var a := TAU * i / 12.0
		k.box(G, _at(Vector3(cos(a) * 0.053, 0.007, sin(a) * 0.053), Basis(Vector3.UP, -a)), Vector3(0.003, 0.01, 0.006), GOLD.darkened(0.2))
	_turn(k, G, Vector3(0, 0.034, 0), [Vector2(0.008, 0), Vector2(0.012, 0.006), Vector2(0.018, 0.016), Vector2(0.02, 0.024), Vector2(0.017, 0.026), Vector2(0, 0.026)], GOLD, 24)
	_shard(k, GEM, _at(Vector3(0, 0.06, 0)), 0.012, 0.075, 0.01, Color(0.4, 0.55, 1.0), 6)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		_wire(k, [d * 0.03 + Vector3(0, 0.03, 0), d * 0.036 + Vector3(0, 0.06, 0), d * 0.03 + Vector3(0, 0.1, 0), d * 0.018 + Vector3(0, 0.125, 0)], 0.0045, GOLD, G, 0.3)
	return null

## A codex bound in dark scaled metal: a gold-framed cover with a violet almond stone in
## a gold eye-shaped setting, pale page edges, a gold clasp.
static func _codex_alien(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var cov := Color(0.42, 0.4, 0.44)
	var m := "im:metal@0.45"
	var W := 0.13
	var H := 0.17
	for z: float in [0.0145, -0.0145]:
		ItemModels._block(k, m, _at(Vector3(0, 0, z), _front()), Vector3(W, 0.006, H), 0.0015, cov)
	ItemModels._block(k, "im:linen", _at(Vector3(0.003, 0, 0), _front()), Vector3(W - 0.008, 0.024, H - 0.008), 0.001, Color(0.74, 0.7, 0.6))
	k.cylinder(m, _at(Vector3(-W * 0.5, -H * 0.5, 0)), 0.0175, 0.0175, H, 16, true, 0.0, 1, cov.darkened(0.15))
	var z := 0.018
	# Scales over the cover.
	for i in 9:
		for j in 13:
			var x := -0.05 + i * 0.0125 + (0.006 if j % 2 == 1 else 0.0)
			var y := -0.072 + j * 0.012
			if absf(x) < 0.016 and absf(y) < 0.034 or absf(x) > 0.054:
				continue
			k.sphere(m, Transform3D(_front() * Basis.from_scale(Vector3(1.0, 0.18, 1.3)), Vector3(x, y, z - 0.0006)), 0.0065, 4, 8, 0.0, 1.0, cov.lightened(0.12), true)
	# Gold frame and corner pieces.
	var fx := W * 0.5 - 0.006
	var fy := H * 0.5 - 0.006
	for e: Array in [[Vector3(-fx, -fy, z), Vector3(fx, -fy, z)], [Vector3(fx, -fy, z), Vector3(fx, fy, z)], [Vector3(fx, fy, z), Vector3(-fx, fy, z)], [Vector3(-fx, fy, z), Vector3(-fx, -fy, z)]]:
		_bar(k, G, e[0], e[1], Vector2(0.004, 0.0025), GOLD)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_slab(k, G, _at(Vector3(sx * fx, sy * fy, z)), PackedVector2Array([Vector2(0, 0), Vector2(-sx * 0.018, 0), Vector2(0, -sy * 0.018)]) , 0.003, GOLD)
	# The eye: a violet almond stone in a gold setting, with gold rays above and below.
	_slab(k, GEM, _at(Vector3(0, 0, z + 0.002)), _almond(0.009, 0.02), 0.006, Color(0.55, 0.32, 0.95), [[-0.5, 1.0], [0.0, 1.0], [0.5, 0.55]])
	var eye: Array = []
	for v in _almond(0.012, 0.025, 20):
		eye.append(Vector3(v.x, v.y, z + 0.002))
	_loop(k, eye, 0.0018, GOLD)
	for sy: float in [-1.0, 1.0]:
		_bar(k, G, Vector3(0, sy * 0.027, z), Vector3(0, sy * 0.06, z), Vector2(0.003, 0.002), GOLD)
	_block_clasp(k, Vector3(W * 0.5 + 0.002, 0, 0))
	return null

static func _block_clasp(k: MeshKit, at: Vector3) -> void:
	ItemModels._block(k, G, _at(at), Vector3(0.006, 0.02, 0.036), 0.0015, GOLD)

## A titan core: a sphere of hot pink-violet light caged in twisting gold bands, great gold
## crescent blades round it and spikes at the poles.
static func _core_titan(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0, 0.07, 0)
	k.sphere("own:core", _at(c), 0.04, 16, 24, 0.0, 1.0, Color(0.5, 0.35, 1.0))
	k.sphere("own:gem", _at(c + Vector3(0, 0, 0.03)), 0.012, 8, 12, 0.0, 0.5, Color(1.0, 0.75, 0.95))
	_cage(k, c, Vector3.ONE * 0.042, 6, 0.0028, GOLD, G, Vector2(0.25, PI - 0.25), [PI * 0.5], 1.2)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var pts: Array = []
		for j in 7:
			var phi := lerpf(0.35, PI - 0.35, j / 6.0)
			var rr := 0.049 + 0.01 * sin(PI * j / 6.0)
			pts.append(c + Vector3(sin(phi) * cos(a) * rr, -cos(phi) * rr * 1.05, sin(phi) * sin(a) * rr))
		_wire(k, pts, 0.0055, GOLD, G, 0.25)
		_horn(k, c + Vector3(cos(a) * 0.058, 0.0, sin(a) * 0.058), Vector3(cos(a), 0, sin(a)), Vector3.ZERO, 0.012, 0.003, GOLD)
	for sy: float in [-1.0, 1.0]:
		k.cylinder(G, _at(c + Vector3(0, sy * 0.04, 0), Basis(Vector3.RIGHT, 0.0 if sy > 0 else PI)), 0.008, 0.0, 0.028, 8, true, 0.0, 1, GOLD)
		ItemModels._torus(k, G, _at(c + Vector3(0, sy * 0.039, 0)), 0.01, 0.003, 16, 6, GOLD)
	return null

## A feather: a fine shaft along +Y and two soft vanes, combed into barbs at the edge,
## coloured `base` at the quill to `tip`; `glint` lightens the vane near the shaft.
static func _feather(k: MeshKit, length: float, width: float, base: Color, tip: Color, glint: Color, shaft: Color, curl: float) -> void:
	var bend := func(t: float) -> Vector3:
		return Vector3(curl * length * t * t, t * length, 0.004 * sin(t * PI))
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 13:
		var t := i / 12.0
		path.append(bend.call(t))
		radii.append(lerpf(0.0022, 0.0004, t))
	ItemModels._tube(k, G, Transform3D.IDENTITY, path, radii, 6, shaft)
	for side: float in [-1.0, 1.0]:
		var f := func(u: float, v: float) -> Vector3:
			var t := lerpf(0.14, 1.0, v)
			var wv := width * pow(sin(PI * pow((t - 0.14) / 0.86, 0.75)), 0.7) * (1.0 if side > 0 else 0.85)
			var comb := 1.0 - 0.35 * pow(absf(sin(v * 40.0)), 4.0) * u
			var back := u * u * 0.18 * length * (1.0 - t * 0.5)
			var p: Vector3 = bend.call(t - back / length)
			return p + Vector3(side * u * wv * comb, 0, -0.006 * u * u)
		var col := func(_p: Vector3, u: float, v: float) -> Color:
			var c := base.lerp(tip, v)
			return c.lerp(glint, (1.0 - u) * 0.45 * sin(v * PI))
		Provisions.sheet(k, "own:sheen", Transform3D.IDENTITY, 6, 80, f, col, Vector3(0, 0, 1))

## A long iridescent feather, blue-teal at the quill shading into violet and pink, on a
## pale gold shaft.
static func _feather_phoenix(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	_feather(k, 0.27, 0.04, Color(0.05, 0.25, 0.55), Color(0.35, 0.08, 0.5), Color(0.1, 0.55, 0.6), GOLD.lightened(0.2), 0.12)
	return Vector3(0, 0.02, 0)

## A heavy bronze coin with a raised rim, struck with a three-armed swirl and three
## ringed dots.
static func _coin_alien(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var bz := Color(0.36, 0.28, 0.18)
	var m := "im:metal@0.5"
	Provisions.lathe(k, m, _at(Vector3(0, 0, -0.0025), _front()), PackedVector2Array([Vector2(0, 0), Vector2(0.025, 0), Vector2(0.026, 0.001), Vector2(0.026, 0.004), Vector2(0.025, 0.005), Vector2(0.022, 0.0052), Vector2(0.021, 0.004), Vector2(0, 0.004)]), 40, bz)
	var z := 0.0018
	for i in 3:
		var a0 := TAU * i / 3.0 + 0.5
		var pts: Array = []
		for j in 7:
			var t := j / 6.0
			var a := a0 + t * 1.9
			pts.append(Vector3(cos(a) * t * 0.02, sin(a) * t * 0.02, z + 0.0008 * (1.0 - t)))
		_wire(k, pts, 0.0028, bz.lightened(0.08), m, 0.15)
		var a2 := a0 + PI * 0.6
		var p := Vector3(cos(a2) * 0.013, sin(a2) * 0.013, z)
		ItemModels._torus(k, m, _at(p, _front()), 0.003, 0.0009, 14, 4, bz)
		k.sphere(m, Transform3D(_front(), p), 0.0016, 4, 8, 0.0, 0.6, bz.lightened(0.1), true)
	return null

# --- Implants -----------------------------------------------------------------------------

## An ocular implant: an eyeball of plated ivory with a gold-rimmed violet lens, a small
## blue stone, a black fin over the top and black cable tails coiling out behind.
static func _implant_eye(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(-0.01, 0.0, 0)
	k.sphere("own:pearl", _at(c), 0.03, 14, 20, 0.0, 1.0, IVORY)
	_cage(k, c, Vector3.ONE * 0.0302, 6, 0.0009, IVORY.darkened(0.35), "own:pearl", Vector2(0.4, PI - 0.4), [PI * 0.5])
	var lens := c + Vector3(0, 0, 0.026)
	ItemModels._torus(k, G, _at(lens, _front()), 0.017, 0.0032, 28, 8, GOLD)
	k.sphere(NEB, Transform3D(_front(), lens - Vector3(0, 0, 0.002)), 0.016, 8, 16, 0.0, 0.45, Color(0.5, 0.3, 0.9), true)
	k.sphere("im:metal@0.15", Transform3D(_front(), lens + Vector3(0, 0, 0.004)), 0.005, 6, 10, 0.0, 0.5, BLACK, true)
	_gem(k, c + Vector3(0.024, -0.012, 0.012), Vector3(0.7, -0.3, 0.6), 0.004, Color(0.35, 0.45, 1.0))
	var tube := "im:metal@0.25"
	_wire(k, [c + Vector3(-0.02, 0.022, -0.005), c + Vector3(0.01, 0.038, -0.004), c + Vector3(0.045, 0.036, -0.002), c + Vector3(0.07, 0.022, 0.0)], 0.005, BLACK, tube, 0.2)
	for i in 4:
		var a := -0.3 - i * 0.45
		var d := Vector3(cos(a), sin(a), 0)
		var p0 := c + d * 0.024 + Vector3(0, 0, -0.012)
		_wire(k, [p0, p0 + d * 0.02 + Vector3(0.01, 0, -0.004), p0 + d * 0.035 + Vector3(0.02, -0.01, 0), p0 + d * 0.04 + Vector3(0.03, -0.005, 0.004), p0 + d * 0.036 + Vector3(0.036, 0.006, 0.004)], 0.0035, BLACK, tube, 0.3)
	return null

## A spinal implant: a curving chain of glossy blue-black vertebrae capped with ivory
## plates, black spines splaying from each side.
static func _implant_spine(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var n := 12
	var vert := Color(0.1, 0.1, 0.17)
	var tm := "im:metal@0.25"
	for i in n:
		var t := float(i) / (n - 1)
		var p := Vector3(0.016 * sin(t * PI * 1.6), t * 0.23, 0)
		var tan := Vector3(0.016 * PI * 1.6 * cos(t * PI * 1.6), 0.23, 0).normalized()
		var b := _along(tan)
		var s := lerpf(0.8, 1.2, sin(t * PI))
		k.sphere(tm, Transform3D(b * Basis.from_scale(Vector3(1.3, 0.85, 1.0)), p), 0.017 * s, 8, 12, 0.0, 1.0, vert)
		ItemModels._torus(k, tm, Transform3D(b, p - tan * 0.008 * s), 0.011 * s, 0.002, 14, 4, vert.lightened(0.15))
		k.bevel_box("own:pearl", Transform3D(b * Basis(Vector3.RIGHT, -0.35), p + b.y * 0.002 + b.z * 0.015 * s), Vector3(0.022, 0.014, 0.01) * s, 0.003, IVORY)
		for sx: float in [-1.0, 1.0]:
			_horn(k, p + b.x * sx * 0.017 * s, b.x * sx - tan * 0.5 + Vector3(0, 0, -0.25), -tan * 0.5, 0.04 * s, 0.0045, BLACK, tm)
	return Vector3(0, 0.12, 0)

## A cardiac implant: a heart of ivory armour plates opened at the front on a glowing red
## crystalline core latticed in black, dark pipes rising from the top.
static func _implant_heart(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var prof := [Vector2(0, -0.055), Vector2(0.014, -0.042), Vector2(0.03, -0.02), Vector2(0.04, 0.005), Vector2(0.038, 0.026), Vector2(0.026, 0.04), Vector2(0, 0.045)]
	var tilt := Basis(Vector3(0, 0, 1), 0.25)
	Provisions.lathe(k, "own:ember", Transform3D(tilt, Vector3.ZERO), PackedVector2Array(prof), 28, Color(0.75, 0.12, 0.08))
	var shell: Array = []
	for v: Vector2 in prof:
		shell.append(Vector2(v.x * 1.08, v.y * 1.04))
	var plates := func(a: float, t: float, _p: Vector3) -> float:
		return 1.0 + 0.025 * absf(sin(a * 5.0 + floor(t * 6.0) * 0.9))
	Provisions.lathe(k, "own:pearl", Transform3D(tilt, Vector3.ZERO), PackedVector2Array(shell), 32, IVORY, plates, Vector2(0.3, 1.06))
	for a: float in [0.34, 1.16]:
		var edge: Array = []
		for v: Vector2 in shell:
			edge.append(tilt * Vector3(cos(TAU * a) * v.x, v.y, sin(TAU * a) * v.x))
		_wire(k, edge.slice(1, edge.size() - 1), 0.0022, IVORY.darkened(0.2), "own:pearl", 0.6)
	# Black lattice over the window.
	for i in 4:
		var y := -0.03 + i * 0.016
		_wire(k, [tilt * Vector3(-0.022, y, 0.034), tilt * Vector3(0, y + 0.006, 0.041), tilt * Vector3(0.022, y, 0.034)], 0.0012, BLACK, "im:metal@0.3", 1.0)
	var pipe := Color(0.3, 0.3, 0.33)
	for i in 3:
		var x := -0.016 + i * 0.014
		var base := tilt * Vector3(x, 0.035, -0.004)
		k.cylinder("im:metal@0.35", _at(base, Basis(Vector3(0, 0, 1), 0.25 - i * 0.1)), 0.0065, 0.0065, 0.03 + i * 0.004, 12, true, 0.0, 1, pipe)
		ItemModels._torus(k, "im:metal@0.35", _at(base + (Basis(Vector3(0, 0, 1), 0.25 - i * 0.1) * Vector3(0, 0.03 + i * 0.004, 0))), 0.0068, 0.0015, 12, 4, pipe.lightened(0.2))
	_wire(k, [tilt * Vector3(0.02, 0.03, -0.01), tilt * Vector3(0.03, 0.06, -0.01), tilt * Vector3(0.048, 0.062, -0.008), tilt * Vector3(0.05, 0.045, -0.004)], 0.004, BLACK, "im:metal@0.25", 0.7)
	return null

## An arm implant: an ivory-plated forearm wrapped round a black core, a blue stone at the
## elbow and a black skeletal claw of a hand.
static func _implant_arm(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var tube := "im:metal@0.25"
	_wire(k, [Vector3(0, 0.07, 0), Vector3(0.003, 0.15, 0), Vector3(0, 0.25, 0)], 0.019, BLACK, tube, 1.0)
	for i in 2:
		var ph := PI * i
		var pts: Array = []
		for j in 8:
			var t := j / 7.0
			var a := ph + t * 2.2
			pts.append(Vector3(cos(a) * 0.017, 0.075 + t * 0.175, sin(a) * 0.017))
		var radii := PackedFloat32Array()
		var path := _smooth(pts)
		for j in path.size():
			radii.append(lerpf(0.011, 0.019, float(j) / path.size()))
		ItemModels._tube(k, "own:pearl", Transform3D.IDENTITY, path, radii, 10, IVORY)
	# Gold-trimmed cuffs and seams between the plates.
	for y: float in [0.11, 0.16, 0.21]:
		ItemModels._torus(k, G, _at(Vector3(0, y, 0)), 0.024, 0.0014, 20, 4, GOLD.darkened(0.2))
	k.sphere("own:pearl", _at(Vector3(0, 0.25, 0)), 0.026, 10, 14, 0.0, 1.0, IVORY)
	_gem(k, Vector3(0, 0.252, 0.024), Vector3(0, 0, 1), 0.008, Color(0.3, 0.45, 1.0))
	for y: float in [0.068, 0.08]:
		ItemModels._torus(k, tube, _at(Vector3(0, y, 0)), 0.013, 0.003, 16, 6, BLACK)
	# The hand: a palm and four jointed claws spread downward, a thumb to one side.
	ItemModels._block(k, tube, _at(Vector3(0, 0.052, 0)), Vector3(0.032, 0.028, 0.011), 0.003, BLACK)
	for i in 4:
		var x := -0.012 + i * 0.008
		var sp := (i - 1.5) * 0.14
		_wire(k, [Vector3(x, 0.04, 0), Vector3(x + sp * 0.05, 0.022, 0.003), Vector3(x + sp * 0.09, 0.006, 0.006), Vector3(x + sp * 0.11, -0.008, 0.002)], 0.0028, BLACK, tube, 0.4)
		for j in 2:
			k.sphere(tube, _at(Vector3(x + sp * (0.05 + 0.04 * j), 0.022 - 0.016 * j, 0.003 + 0.003 * j)), 0.0034, 4, 6, 0.0, 1.0, BLACK.lightened(0.15))
	_wire(k, [Vector3(0.016, 0.055, 0), Vector3(0.028, 0.043, 0.005), Vector3(0.032, 0.026, 0.005)], 0.0028, BLACK, tube, 0.4)
	return Vector3(0, 0.15, 0)

## A neural implant: a faceted violet crystal pod in a gold frame, two antennae tipped
## with blue beads, dark wire legs dangling.
static func _implant_brain(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0, 0.055, 0)
	_shard(k, GEM, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), c), 0.028, 0.04, 0.05, Color(0.55, 0.35, 1.0), 8)
	for i in 8:
		var a := TAU * i / 8.0
		var rim := c + Vector3(cos(a) * 0.0285, 0, sin(a) * 0.0285 * 0.7)
		_wire(k, [c + Vector3(0, 0.04, 0), rim.lerp(c + Vector3(0, 0.04, 0), 0.0) * 0.0 + (c + Vector3(cos(a) * 0.0243, 0.0175, sin(a) * 0.0243 * 0.7)), rim, c + Vector3(cos(a) * 0.012, -0.03, sin(a) * 0.012 * 0.7), c + Vector3(0, -0.05, 0)], 0.0011 if i % 2 == 1 else 0.0016, GOLD, G, 0.7)
	ItemModels._torus(k, G, Transform3D(Basis.from_scale(Vector3(1, 1, 0.7)), c), 0.029, 0.0022, 32, 6, GOLD)
	for sx: float in [-1.0, 1.0]:
		var p := c + Vector3(sx * 0.024, 0.008, 0)
		_wire(k, [p, p + Vector3(sx * 0.008, 0.025, 0), p + Vector3(sx * 0.01, 0.045, 0)], 0.0012, DARK, DM, 1.0)
		_gem(k, p + Vector3(sx * 0.01, 0.045, 0), Vector3.UP, 0.0035, Color(0.4, 0.5, 1.0), Color(0, 0, 0, 0), 1.0)
		k.sphere(GEM, _at(p + Vector3(sx * 0.009, 0.03, 0)), 0.0025, 6, 8, 0.0, 1.0, Color(0.4, 0.5, 1.0))
		for j in 2:
			var q := c + Vector3(sx * 0.02, -0.01 - j * 0.012, 0.004)
			_wire(k, [q, q + Vector3(sx * 0.014, -0.012, 0.002), q + Vector3(sx * 0.018, -0.03, 0), q + Vector3(sx * 0.012, -0.04, -0.002)], 0.0011, DARK, DM, 0.6)
	return null

## A symbiote: a pearly ivory-violet bell of a body tipped to one side, trailing many
## glossy purple-black tentacles that curl at the ends.
static func _symbiote(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0.012, 0.11, 0)
	var tilt := Basis(Vector3(0, 0, 1), -0.5)
	k.sphere(NEB, Transform3D(tilt * Basis.from_scale(Vector3(1.15, 0.8, 0.9)), c), 0.04, 12, 18, 0.03, 1.0, Color(0.72, 0.55, 0.78), true)
	k.sphere("own:sheen", Transform3D(tilt * Basis.from_scale(Vector3(1.05, 0.25, 0.85)), c), 0.04, 8, 16, 0.0, 1.0, Color(0.45, 0.25, 0.5))
	_slab(k, "im:metal@0.15", Transform3D(tilt, c + tilt * Vector3(0.012, 0.017, 0.03)), _almond(0.009, 0.003), 0.003, BLACK)
	for i in 14:
		var a := TAU * i / 14.0 + r.randf() * 0.3
		var p0 := c + tilt * Vector3(cos(a) * 0.028, -0.006, sin(a) * 0.024)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var length := r.randf_range(0.085, 0.12)
		var ph := r.randf() * TAU
		for j in 18:
			var t := j / 17.0
			var curl := pow(t, 3.0)
			pts.append(p0 + Vector3(cos(a) * 0.02 * t + 0.01 * sin(t * 7.0 + ph) + curl * 0.02 * cos(ph + t * 6.0), -t * length + curl * 0.015, sin(a) * 0.012 * t + curl * 0.015 * sin(ph + t * 6.0)))
			radii.append(lerpf(0.0045, 0.0008, t))
		var col := func(_p: Vector3, _a: float, t: float) -> Color:
			return Color(0.08, 0.05, 0.1).lerp(Color(0.55, 0.22, 0.65), t)
		Provisions.tube(k, "im:metal@0.25", Transform3D.IDENTITY, pts, radii, 7, col)
	return null

## A recall shard: a long violet crystal point with a nebula swirling in it, chips of
## crystal breaking off its side.
static func _teleport_shard(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	var b := Basis.from_scale(Vector3(1.0, 1.0, 0.55))
	_shard(k, NEB, Transform3D(b, Vector3(0, 0.07, 0)), 0.03, 0.08, 0.07, Color(0.5, 0.28, 0.95), 6)
	for i in 5:
		var a := r.randf_range(-0.8, 0.8)
		var p := Vector3(0.03 + r.randf() * 0.01, 0.06 + i * 0.016, r.randf_range(-0.005, 0.005))
		if i % 2 == 1:
			p.x = -p.x * 0.9
		_shard(k, NEB, Transform3D(Basis(Vector3(0, 0, 1), a), p), 0.003, 0.009, 0.006, Color(0.6, 0.35, 1.0), 4)
	return null

## A shield charm: a smooth grey stone egg banded with inlaid gold, an opal-like stone set
## in a gold ring at its middle.
static func _shield_charm(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var rad := 0.04
	var h := 0.1
	_turn(k, "im:stone", Vector3.ZERO, _egg_prof(rad, h, 1.0, 16), Color(0.4, 0.36, 0.31), 32)
	var on := func(t: float, a: float) -> Vector3:
		var rr := _egg_r(t, rad) + 0.0008
		return Vector3(cos(a) * rr, t * h, sin(a) * rr)
	for a0: float in [PI * 0.5 - 0.5, PI * 0.5 + 0.5]:
		var pts: Array = []
		for j in 9:
			var t := 0.06 + 0.88 * j / 8.0
			pts.append(on.call(t, a0 + (0.3 if a0 < PI * 0.5 else -0.3) * sin(t * PI)))
		_wire(k, pts, 0.0026, GOLD, G, 0.6)
	var band: Array = []
	for j in 16:
		band.append(on.call(0.42 + 0.05 * sin(TAU * j / 16.0 * 2.0), TAU * j / 16.0))
	_loop(k, band, 0.0024, GOLD)
	var gp: Vector3 = on.call(0.48, PI * 0.5)
	_gem(k, gp, Vector3(0, 0.15, 1), 0.009, Color(0.85, 0.85, 0.95), GOLD, 0.6)
	ItemModels._torus(k, G, Transform3D(_along(Vector3(0, 0.15, 1)), gp), 0.014, 0.0016, 24, 6, GOLD)
	_wire(k, [gp + Vector3(0, -0.014, 0), on.call(0.3, PI * 0.5), on.call(0.12, PI * 0.5)], 0.0018, GOLD, G, 0.6)
	return null

## A rebirth feather: a broad flame-orange feather shading to deep amber, curling at the
## tip, on a gold shaft.
static func _revive_feather(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	_feather(k, 0.25, 0.045, Color(0.7, 0.3, 0.02), Color(0.5, 0.12, 0.01), Color(0.9, 0.55, 0.08), GOLD, 0.16)
	return Vector3(0, 0.02, 0)

## A guardian orb: a violet glass sphere with a dark many-armed guardian floating in it,
## set in a gold crown of spikes.
static func _summon_orb(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var c := Vector3(0, 0.06, 0)
	k.sphere(NEB, _at(c), 0.041, 16, 24, 0.0, 1.0, Color(0.5, 0.38, 1.0))
	k.sphere("im:glass", _at(c), 0.0435, 16, 24, 0.0, 1.0, Color(0.9, 0.85, 1.0, 0.12))
	var oct := Color(0.1, 0.08, 0.2)
	var head := c + Vector3(0.006, 0.014, 0.032)
	k.sphere("own:pearl", Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 0.75)), head), 0.016, 10, 14, 0.0, 1.0, oct)
	for i in 8:
		var a := lerpf(-PI * 0.97, -PI * 0.03, i / 7.0)
		var d := Vector3(cos(a), sin(a), 0)
		var pts: Array = []
		for j in 5:
			var t := j / 4.0
			var q := Vector3(0.006 + d.x * (0.006 + t * 0.034) + signf(d.x + 0.001) * 0.01 * t * t, -0.008 + d.y * t * 0.034 + 0.012 * t * t, 0)
			var rr := q + c + Vector3(0, 0.012, 0) - c
			var z := sqrt(maxf(0.041 * 0.041 - rr.x * rr.x - rr.y * rr.y, 0.0)) + 0.0005
			pts.append(c + Vector3(rr.x, rr.y, z))
		_wire(k, pts, 0.0038, oct, "own:pearl", 0.3)
	_turn(k, DM, Vector3.ZERO, [Vector2(0, 0), Vector2(0.034, 0), Vector2(0.04, 0.006), Vector2(0.038, 0.016), Vector2(0.03, 0.022), Vector2(0, 0.022)], Color(0.25, 0.22, 0.2), 32)
	ItemModels._torus(k, G, _at(Vector3(0, 0.02, 0)), 0.032, 0.003, 32, 6, GOLD)
	ItemModels._torus(k, G, _at(Vector3(0, 0.006, 0)), 0.04, 0.0025, 32, 6, GOLD)
	for i in 12:
		var a := TAU * i / 12.0 + PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		_horn(k, d * 0.036 + Vector3(0, 0.016, 0), d * 0.5 + Vector3(0, 1, 0), -d * 0.4, 0.03 if i % 2 == 0 else 0.018, 0.0045, GOLD if i % 2 == 0 else DARK, G)
	_horn(k, Vector3(0, 0.01, 0.04), Vector3(0, -1, 0.15), Vector3.ZERO, 0.014, 0.005, GOLD)
	_gem(k, Vector3(0, 0.014, 0.04), Vector3(0, 0, 1), 0.004, Color(0.4, 0.5, 1.0))
	return null

## A time shard: a flat blue crystal point carrying gold clock-rings with an opal heart,
## crystal chips breaking off around it.
static func _time_shard(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	_shard(k, NEB, Transform3D(Basis(Vector3(0, 0, 1), -0.15) * Basis.from_scale(Vector3(1.0, 1.0, 0.45)), Vector3(0, 0.065, 0)), 0.03, 0.07, 0.06, Color(0.38, 0.42, 0.95), 6)
	var z := 0.014
	for p: Vector3 in [Vector3(0.002, 0.055, z), Vector3(-0.004, 0.09, z * 0.8)]:
		var big := p.y < 0.07
		ItemModels._torus(k, G, _at(p, _front()), 0.014 if big else 0.008, 0.0016, 28, 6, GOLD)
		_gem(k, p, Vector3(0, 0, 1), 0.006 if big else 0.0038, Color(0.85, 0.85, 0.98), GOLD)
		for i in 4:
			var a := TAU * i / 4.0 + PI * 0.25
			_bar(k, G, p + Vector3(cos(a), sin(a), 0) * 0.006, p + Vector3(cos(a), sin(a), 0) * (0.018 if big else 0.011), Vector2(0.0015, 0.0012), GOLD)
	_bar(k, G, Vector3(0.0, 0.07, z), Vector3(-0.003, 0.082, z * 0.85), Vector2(0.0018, 0.0014), GOLD)
	for i in 4:
		var p := Vector3(r.randf_range(0.03, 0.04) * (1.0 if i % 2 == 0 else -1.0), 0.03 + i * 0.022, 0)
		_shard(k, NEB, Transform3D(Basis(Vector3(0, 0, 1), r.randf_range(-1, 1)), p), 0.003, 0.01, 0.006, Color(0.5, 0.5, 1.0), 4)
	return null

# --- Keys and stones -------------------------------------------------------------------------

## The hive key: an amber-brown thorned key, its bow a glowing amber stone in a claw of
## curling thorns.
static func _key_hive(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var am := Color(0.55, 0.32, 0.1)
	var m := "im:metal@0.35"
	var grip := _key(k, m, am, 0.08, 0.0042, "teeth", false, 12)
	var c := grip + Vector3(0, 0.016, 0)
	k.sphere(GEM, _at(c), 0.014, 10, 14, 0.0, 1.0, Color(1.0, 0.5, 0.08))
	ItemModels._torus(k, m, _at(c, _front()), 0.015, 0.0032, 20, 6, am)
	for sx: float in [-1.0, 1.0]:
		_horn(k, c + Vector3(sx * 0.012, -0.006, 0), Vector3(sx * 0.7, 0.5, 0), Vector3(-sx * 0.4, 0.8, 0), 0.03, 0.0055, am, m)
		_horn(k, c + Vector3(sx * 0.008, 0.008, 0), Vector3(sx * 0.5, 1, 0), Vector3(sx * 0.6, 0, 0), 0.022, 0.0035, am, m)
		for j in 3:
			_horn(k, c + Vector3(sx * (0.018 + j * 0.003), -0.002 + j * 0.008, 0), Vector3(sx, 0.6, 0), Vector3.ZERO, 0.009, 0.0024, am.lightened(0.1), m)
	return grip

## The void key: a black-violet glass key, thorned along the shaft, its bow a crescent axe
## blade pierced with a round hole.
static func _key_void(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var ob := Color(0.24, 0.17, 0.3)
	var m := "own:obsidian"
	var grip := _key(k, m, ob, 0.07, 0.0042, "teeth", false, 8)
	var c := grip + Vector3(0, 0.022, 0)
	# The bow: a round boss with a crescent axe blade sweeping up on one side.
	_slab(k, m, _at(c), _circle(0.018, 24), 0.008, ob)
	var blade := PackedVector2Array()
	for i in 13:
		var a := lerpf(-0.9, 2.0, i / 12.0)
		blade.append(Vector2(cos(a), sin(a)) * (0.036 + 0.004 * sin(a * 3.0)))
	for i in 13:
		var a := lerpf(2.0, -0.9, i / 12.0)
		blade.append(Vector2(cos(a), sin(a)) * 0.019 + Vector2(0.006, 0.002))
	_slab_strip(k, m, _at(c), blade, 0.005, ob)
	k.cylinder("im:metal@0.6", _at(c + Vector3(-0.002, 0, -0.0045), _front()), 0.0065, 0.0065, 0.009, 16, true, 0.0, 1, BLACK)
	ItemModels._torus(k, m, _at(c + Vector3(-0.002, 0, 0.0038), _front()), 0.0068, 0.0013, 16, 4, ob.lightened(0.15))
	for a: float in [-0.9, 2.0]:
		_horn(k, c + Vector3(cos(a), sin(a), 0) * 0.03, Vector3(cos(a + 0.6), sin(a + 0.6), 0) * (1.0 if a > 0 else -1.0), Vector3.ZERO, 0.01, 0.003, ob, m)
	return grip

## A crescent strip: `poly` gives the outer edge then the inner edge back, as a band of
## quads (not star-shaped, so not a _slab), `depth` thick facing +Z.
static func _slab_strip(k: MeshKit, m: String, xf: Transform3D, poly: PackedVector2Array, depth: float, col: Color) -> void:
	var n := poly.size() / 2
	var h := depth * 0.5
	for i in n - 1:
		var o0 := poly[i]
		var o1 := poly[i + 1]
		var i0 := poly[poly.size() - 1 - i]
		var i1 := poly[poly.size() - 2 - i]
		for z: float in [h, -h]:
			ItemModels._quad(k, m, xf, Vector3(o0.x, o0.y, z), Vector3(o1.x, o1.y, z), Vector3(i1.x, i1.y, z), Vector3(i0.x, i0.y, z), Vector3(0, 0, signf(z)), col)
		for e: Array in [[o0, o1, 1.0], [i0, i1, -1.0]]:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var mid := (a + b) * 0.5
			var out := Vector3(mid.x, mid.y, 0) * float(e[2])
			ItemModels._quad(k, m, xf, Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h), out, col)
	for e: Array in [[poly[0], poly[poly.size() - 1]], [poly[n - 1], poly[n]]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var d := (b - a)
		var out := Vector3(-d.y, d.x, 0)
		ItemModels._quad(k, m, xf, Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h), out, col)

## The star key: a silver key whose bow is a ring burst through by a four-pointed star
## around an opal, its bit a spiked ball.
static func _key_star(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var sv := Color(0.75, 0.75, 0.78)
	var m := "im:metal@0.22"
	var grip := _key(k, m, sv, 0.08, 0.0042, "ball")
	var c := grip + Vector3(0, 0.026, 0)
	ItemModels._torus(k, m, _at(c, _front()), 0.024, 0.0042, 32, 8, sv)
	for i in 8:
		var a := TAU * i / 8.0 + PI * 0.5
		var d := Vector3(cos(a), sin(a), 0)
		var long := i % 2 == 0
		_horn(k, c + d * 0.004, d, Vector3.ZERO, 0.04 if long else 0.022, 0.006 if long else 0.0035, sv.lightened(0.05), m)
	_gem(k, c + Vector3(0, 0, 0.004), Vector3(0, 0, 1), 0.008, Color(0.85, 0.85, 0.98), sv)
	return grip

## The precursor key: a gold key built of blocks, its bow a square frame of studded gold
## bars round a glowing pale orb.
static func _key_precursor(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var gd := Color(0.78, 0.6, 0.26)
	var grip := _key(k, G, gd, 0.065, 0.005, "blocks", true)
	var c := grip + Vector3(0, 0.026, 0)
	var s := 0.023
	# A cube frame: front and back squares joined at the corners, studded with little blocks.
	for z: float in [0.009, -0.009]:
		for e: Array in [[Vector3(-s, -s, 0), Vector3(s, -s, 0)], [Vector3(s, -s, 0), Vector3(s, s, 0)], [Vector3(s, s, 0), Vector3(-s, s, 0)], [Vector3(-s, s, 0), Vector3(-s, -s, 0)]]:
			_bar(k, G, c + e[0] + Vector3(0, 0, z), c + e[1] + Vector3(0, 0, z), Vector2(0.007, 0.007), gd)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_bar(k, G, c + Vector3(sx * s, sy * s, -0.009), c + Vector3(sx * s, sy * s, 0.009), Vector2(0.007, 0.007), gd)
	for i in 4:
		var a := TAU * i / 4.0
		var d := Vector3(cos(a), sin(a), 0)
		var e := Vector3(-sin(a), cos(a), 0)
		for j in 4:
			k.box(G, _at(c + d * s + e * (j - 1.5) * 0.011 + Vector3(0, 0, 0.0125)), Vector3(0.004, 0.004, 0.002), gd.lightened(0.12))
	k.sphere(GEM, _at(c), 0.01, 10, 14, 0.0, 1.0, Color(0.95, 0.88, 0.7))
	for y: float in [0.012, 0.024, 0.036, 0.048]:
		k.box(G, _at(Vector3(0, y, 0.0055)), Vector3(0.008, 0.004, 0.002), gd.lightened(0.1))
	return grip

## A keystone: a diamond of dark faceted stone, its faces outlined in inlaid gold, a dark
## pearl orb in a gold setting at its heart.
static func _keystone(k: MeshKit, _r: RandomNumberGenerator, _t: String) -> Variant:
	var poly := PackedVector2Array()
	for i in 4:
		var a := TAU * i / 4.0
		var d := Vector2(cos(a), sin(a))
		var e := Vector2(-sin(a), cos(a))
		poly.append(d * 0.05)
		poly.append(d * 0.03 + e * 0.022)
	var st := Color(0.2, 0.2, 0.24)
	_slab(k, "im:stone", Transform3D.IDENTITY, poly, 0.036, st, [[-0.5, 0.55], [-0.15, 1.0], [0.15, 1.0], [0.5, 0.55]])
	var z := 0.018
	var outline: Array = []
	for v in poly:
		outline.append(Vector3(v.x * 0.55, v.y * 0.55, z + 0.0005))
	_loop(k, outline, 0.0016, GOLD)
	for v in poly:
		_bar(k, G, Vector3(v.x * 0.56, v.y * 0.56, z), Vector3(v.x * 1.0, v.y * 1.0, 0.0), Vector2(0.0014, 0.0014), GOLD)
	var mid: Array = []
	for v in poly:
		mid.append(Vector3(v.x, v.y, 0.0) * 1.005)
	_loop(k, mid, 0.0013, GOLD)
	_gem(k, Vector3(0, 0, z - 0.001), Vector3(0, 0, 1), 0.012, Color(0.2, 0.2, 0.26), GOLD, 0.9)
	return null

## A sigil stone: a rounded grey river stone inlaid with a pale blue-white disc engraved
## in gold with rings, a spiral and four notches.
static func _sigil_stone(k: MeshKit, r: RandomNumberGenerator, _t: String) -> Variant:
	_slab(k, "im:stone", Transform3D.IDENTITY, _circle(0.045, 24, r, 0.06), 0.024, Color(0.3, 0.29, 0.31), [[-0.5, 0.6], [-0.3, 0.92], [0.0, 1.0], [0.3, 0.92], [0.5, 0.65]])
	var z := 0.012
	k.cylinder("own:pearl", _at(Vector3(0, 0, z - 0.002), _front()), 0.026, 0.026, 0.0024, 32, true, 0.0, 1, Color(0.5, 0.6, 0.72))
	for rr: float in [0.027, 0.019]:
		ItemModels._torus(k, G, _at(Vector3(0, 0, z + 0.0004), _front()), rr, 0.0013, 36, 5, GOLD)
	var sp: Array = []
	for j in 14:
		var t := j / 13.0
		var a := t * TAU * 1.3
		sp.append(Vector3(cos(a) * (0.003 + t * 0.012), sin(a) * (0.003 + t * 0.012), z + 0.0004))
	_wire(k, sp, 0.0013, GOLD, G, 0.7)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		_bar(k, G, Vector3(cos(a) * 0.018, sin(a) * 0.018, z + 0.0004), Vector3(cos(a) * 0.033, sin(a) * 0.033, z - 0.0015), Vector2(0.0018, 0.0014), GOLD)
	return null

# --- Materials -------------------------------------------------------------------------------

static var _mats: Dictionary = {}
static var _lock := Mutex.new()
static var _shader: Shader

## Nebula glass: clouds of the vertex colour swirled with a pale hot tint and pricked with
## stars, glossy under a clear coat; `glow` lets it shine a little of its own light.
const NEBULA_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform float freq = 150.0;
uniform vec3 hot : source_color = vec3(1.0, 0.6, 0.95);
uniform float glow = 0.3;
uniform float stars = 1.0;
uniform float rough = 0.12;
uniform int mode = 0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * n3(p); p *= 2.03; a *= 0.5; } return s; }
void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 p = lp * freq;
	vec3 c;
	if (mode == 1) {
		float land = fbm(p);
		float cloud = fbm(p * 2.3 + 7.0);
		c = mix(vec3(0.01, 0.06, 0.25), vec3(0.04, 0.2, 0.5), fbm(p * 3.0));
		c = mix(c, mix(vec3(0.08, 0.3, 0.06), vec3(0.4, 0.33, 0.16), fbm(p * 4.0 + 3.0)), smoothstep(0.45, 0.48, land));
		c = mix(c, vec3(0.85), smoothstep(0.55, 0.7, cloud) * 0.85);
	} else {
		float w = fbm(p + 2.0 * vec3(fbm(p * 0.6), fbm(p * 0.6 + 3.1), fbm(p * 0.6 + 5.7)));
		float w2 = fbm(p * 2.7 + 11.0);
		c = mix(base * 0.08, base * 0.7, smoothstep(0.32, 0.6, w));
		c = mix(c, base * 1.1, smoothstep(0.55, 0.75, w2) * 0.6);
		c = mix(c, mix(base, hot, 0.55), smoothstep(0.66, 0.85, w) * 0.8);
		c += vec3(step(0.985, h3(floor(lp * freq * 7.0)))) * stars * 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	CLEARCOAT = 0.4;
	CLEARCOAT_ROUGHNESS = 0.1;
	EMISSION = c * glow;
}
"""

static func mat(name: String) -> Material:
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_lock.unlock()
	return m

static func _make(n: String) -> Material:
	if n == "pearl":
		# Pearly bio-armour plating: smooth, satin, a soft clear coat.
		var q := StandardMaterial3D.new()
		q.vertex_color_use_as_albedo = true
		q.vertex_color_is_srgb = true
		q.roughness = 0.4
		q.metallic = 0.15
		q.clearcoat_enabled = true
		q.clearcoat = 0.5
		return q
	if n == "sheen":
		# Feathers and soft pearly flesh: satin, a lustre at the rim, both sides shown.
		var s := StandardMaterial3D.new()
		s.vertex_color_use_as_albedo = true
		s.vertex_color_is_srgb = true
		s.roughness = 0.5
		s.metallic = 0.1
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		return s
	if _shader == null:
		_shader = Shader.new()
		_shader.code = NEBULA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	match n:
		"gem":
			sm.set_shader_parameter("freq", 260.0)
			sm.set_shader_parameter("hot", Color(0.95, 0.9, 1.0))
			sm.set_shader_parameter("glow", 0.4)
			sm.set_shader_parameter("stars", 0.0)
			sm.set_shader_parameter("rough", 0.06)
		"core":
			sm.set_shader_parameter("freq", 120.0)
			sm.set_shader_parameter("hot", Color(1.0, 0.85, 0.95))
			sm.set_shader_parameter("glow", 0.5)
		"ember":
			sm.set_shader_parameter("freq", 180.0)
			sm.set_shader_parameter("hot", Color(1.0, 0.55, 0.2))
			sm.set_shader_parameter("glow", 0.35)
			sm.set_shader_parameter("stars", 0.0)
		"obsidian":
			sm.set_shader_parameter("freq", 220.0)
			sm.set_shader_parameter("hot", Color(0.6, 0.3, 0.9))
			sm.set_shader_parameter("glow", 0.05)
			sm.set_shader_parameter("rough", 0.2)
		"globe":
			sm.set_shader_parameter("freq", 28.0)
			sm.set_shader_parameter("mode", 1)
			sm.set_shader_parameter("glow", 0.15)
			sm.set_shader_parameter("rough", 0.35)
	return sm
