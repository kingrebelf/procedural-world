class_name KeepsakeModels
## Paper, keys, keepsakes and instruments of the human ages: scrolls with seals, letters, maps, books, keys, dice, cards, bone, salt, lockpicks, the lute, flute, banjo and harmonica, frontier curios, packs and bags.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.

const BUILD := {
	"silver_chalice": "_chalice", "moonpearl": "_moonpearl", "gold_coin": "_coins",
	"rune_tablet": "_rune_tablet", "dungeon_key": "_dungeon_key", "gold_idol": "_gold_idol",
	"void_gem": "_void_gem", "lockpick": "_lockpick",
	"bedroll": "_bedroll", "tent_kit": "_tent_kit", "dice": "_dice", "lute": "_lute",
	"flute": "_flute", "book_leather": "_book", "treasure_map": "_treasure_map",
	"scroll_plain": "_scroll", "scroll_red": "_scroll", "scroll_blue": "_scroll",
	"scroll_green": "_scroll", "deed_scroll": "_scroll", "letter_sealed": "_letter",
	"sextant": "_sextant", "camera_box": "_camera_box", "telegraph_key": "_telegraph_key",
	"gramophone_record": "_record", "railway_spike": "_railway_spike", "safe_key": "_safe_key",
	"cards_deck": "_cards", "harmonica": "_harmonica", "banjo": "_banjo",
	"cigar_box": "_cigar_box", "photo_frame": "_tintype", "family_photo": "_holo_photo",
	"toy_robot": "_toy_robot", "music_player": "_music_player", "chess_set": "_chess_set",
	"writ": "_scroll", "watch_keys": "_key_ring", "grappling_hook": "_grapnel", "watch_tabard": "_tabard",
}

const GOLD := Color(0.9, 0.6, 0.2)
const SILVER := Color(0.86, 0.87, 0.89)
const BRASS := Color(0.8, 0.58, 0.27)
const PARCH := Color(0.78, 0.6, 0.38)
const IRON := Color(0.3, 0.3, 0.31)
const STRAP := Color(0.42, 0.22, 0.1)

static var _mats := {}
static var _lock := Mutex.new()
## +Y turned to face +Z: a disc, coin or lathe built round +Y shown face on.
static var FRONT := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

# --- Materials ---------------------------------------------------------------------------

## This family's own materials: parchment with a mottled grain, glossy shellac, a pearl's
## sheen, dark screen glass; the rest borrowed from Provisions (wood, leather, wax, canvas,
## tin paint) at the scale of a thing held in the hand.
static func mat(name: String) -> Material:
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_lock.unlock()
	return m

static func _make(name: String) -> Material:
	match name:
		"paper":
			return Provisions._std(0.9, 0.0, "parchment", 0.16, 9.0, 0.35)
		"wax": return Provisions._mat("pv_wax")
		"wood":
			var s := Provisions._std(0.45, 0.0, "woodgrain", 0.08, 10.0, 0.4)
			s.clearcoat_enabled = true
			s.clearcoat = 0.3
			return s
		"board": return Provisions._mat("pv_board")
		"wood_dull": return Provisions._mat("pv_wood")
		"leather": return Provisions._mat("pv_leather")
		"canvas": return Provisions._mat("pv_cloth")
		"paint":
			var s := Provisions._std(0.4, 0.35, "paint", 0.12, 12.0, 0.15)
			return s
		"plastic": return Provisions._mat("pv_plastic")
		"rubber": return Provisions._mat("pv_rubber")
		"vinyl":
			# Shellac: black and glassy, the grooves catching rings of light.
			var s := Provisions._std(0.18)
			s.clearcoat_enabled = true
			s.clearcoat = 0.8
			s.anisotropy_enabled = true
			s.anisotropy = 0.6
			return s
		"pearl":
			var s := Provisions._std(0.12)
			s.clearcoat_enabled = true
			s.clearcoat = 1.0
			s.rim_enabled = true
			s.rim = 0.5
			s.rim_tint = 0.9
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			return s
		"screen":
			var s := Provisions._std(0.05, 0.2)
			s.clearcoat_enabled = true
			s.clearcoat = 1.0
			return s
		"inlay":
			return Provisions._std(0.35, 0.1)
		"satin":
			var s := Provisions._std(0.42, 0.0, "cloth", 0.2, 24.0, 0.3)
			s.clearcoat_enabled = true
			s.clearcoat = 0.2
			return s
		"ivory":
			var s := Provisions._std(0.35, 0.0, "cap", 0.06, 25.0, 0.3)
			s.subsurf_scatter_enabled = true
			s.subsurf_scatter_strength = 0.3
			return s
	return ItemModels.mat("im:" + name)

# --- Shared parts ------------------------------------------------------------------------

static func _at(x: float, y: float, z: float, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, Vector3(x, y, z))

## A lathe through Catmull-Rom control points (a repeated point is a crease).
static func _lathe(k: MeshKit, m: String, xf: Transform3D, pts: Array, col: Variant, segs := 24, shape: Variant = null, steps := 3) -> void:
	Provisions.lathe(k, m, xf, Provisions._curve(pts, steps), segs, col, shape)

## A colour mottled by noise: parchment, worn paint, old wood.
static func _mottle(base: Color, f := 120.0, amount := 0.1) -> Callable:
	return func(p: Vector3, _a: float, _t: float) -> Color:
		return base.darkened(amount * (Provisions._nz(p, f) + 0.4))

## A flat stroke from a to b (in the xf's XY plane, raised to z): runes, map dashes, frets.
static func _stroke(k: MeshKit, m: String, xf: Transform3D, a: Vector2, b: Vector2, w: float, h: float, z: float, col: Color) -> void:
	var d := b - a
	var c := (a + b) * 0.5
	k.box(m, xf * Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), Vector3(c.x, c.y, z)), Vector3(d.length() + w * 0.5, w, h), col)

## The rolled-up end of a sheet: the spiral of its layers, in the XZ plane at height y,
## facing up (dir 1) or down (dir -1), with the rolled core behind it.
static func _spiral(k: MeshKit, m: String, xf: Transform3D, rad: float, y: float, dir: float, col: Color, inner: Color, turns := 4, wire := 0.0009) -> void:
	var segs := 16 * turns
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for s in segs + 1:
		var t := float(s) / segs
		var rr := lerpf(rad * 0.2, rad * 0.98, t)
		var a := t * TAU * turns
		path.append(Vector3(cos(a) * rr, y + dir * 0.0004, sin(a) * rr))
		radii.append(wire)
	ItemModels._tube(k, m, xf, path, radii, 4, col)
	ItemModels._disc(k, m, xf, Vector3(0, y - dir * 0.002, 0), Vector3(0, dir, 0), rad * 0.99, 24, inner)
	ItemModels._disc(k, m, xf, Vector3(0, y - dir * 0.0015, 0), Vector3(0, dir, 0), rad * 0.2, 12, inner.darkened(0.45))

## A wax seal round +Y (xf turns +Y outward): an uneven puddle of wax with the stamp's
## raised ring and its device in the middle.
static func _seal(k: MeshKit, xf: Transform3D, r: float, col: Color, motif: String) -> void:
	var top := r * 0.3
	_lathe(k, "own:wax", xf, [Vector2(r * 0.9, -r * 0.1), Vector2(r, 0.0), Vector2(r * 0.97, top * 0.4), Vector2(r * 0.8, top * 0.85), Vector2(r * 0.55, top), Vector2(0, top)],
		func(p: Vector3, _a: float, _t: float) -> Color: return col.darkened(0.12 * (Provisions._nz(p, 300.0) + 0.3)),
		28, func(a: float, _t: float, _p: Vector3) -> float: return 1.0 + 0.07 * sin(a * 5.0 + 1.3) + 0.04 * sin(a * 9.0))
	ItemModels._torus(k, "own:wax", xf * _at(0, top, 0), r * 0.7, r * 0.07, 28, 5, col.lightened(0.08))
	var dev := col.lightened(0.1)
	match motif:
		"lion":
			# A rampant beast: body, raised head and forepaws, a curling tail.
			k.sphere("own:wax", xf * _at(0, top, 0), r * 0.22, 6, 10, 0.3, 0.35, dev)
			k.sphere("own:wax", xf * _at(-r * 0.12, top, -r * 0.25), r * 0.13, 5, 8, 0.2, 0.4, dev)
			for q: Vector2 in [Vector2(0.18, -0.3), Vector2(0.15, 0.32), Vector2(-0.2, 0.3)]:
				ItemModels._tube(k, "own:wax", xf, PackedVector3Array([Vector3(0, top, 0), Vector3(q.x * r, top, q.y * r)]), PackedFloat32Array([r * 0.06, r * 0.04]), 5, dev)
		"knot":
			# A triquetra: three interlaced rings.
			for i in 3:
				var a := TAU * i / 3.0
				ItemModels._torus(k, "own:wax", xf * _at(cos(a) * r * 0.17, top, sin(a) * r * 0.17), r * 0.2, r * 0.045, 18, 4, dev)
		"tree":
			# An oak: trunk, spreading crown, roots.
			k.box("own:wax", xf * _at(0, top, r * 0.15), Vector3(r * 0.1, r * 0.06, r * 0.35), dev)
			k.sphere("own:wax", xf * _at(0, top, -r * 0.12), r * 0.3, 6, 12, 0.35, 0.3, dev)
			for s: float in [-1.0, 1.0]:
				ItemModels._tube(k, "own:wax", xf, PackedVector3Array([Vector3(0, top, r * 0.3), Vector3(s * r * 0.2, top, r * 0.42)]), PackedFloat32Array([r * 0.04, r * 0.025]), 4, dev)

## A buckle on a strap: a dark iron frame and its prong, the strap's tongue beyond it.
## Built facing +Z, the strap running along Y.
static func _buckle(k: MeshKit, xf: Transform3D, w: float, col := Color(0.24, 0.23, 0.21)) -> void:
	var h := w * 1.1
	var t := w * 0.12
	for s: float in [-1.0, 1.0]:
		k.box("im:metal@0.5", xf * _at(s * (w * 0.5 + t * 0.5), 0, t * 0.5), Vector3(t, h + t * 2.0, t), col)
		k.box("im:metal@0.5", xf * _at(0, s * h * 0.5 + s * t * 0.5, t * 0.5), Vector3(w + t * 2.0, t, t), col)
	k.box("im:metal@0.5", xf * _at(0, 0, t * 0.7), Vector3(t * 0.7, h, t * 0.6), col.lightened(0.1))
	k.box("own:leather", xf * _at(0, -h * 0.9, 0.0015), Vector3(w * 0.85, h * 1.3, 0.003), STRAP.lightened(0.05))

## A strap round a roll: a band of leather on a cylinder about +Y of radius `rad`.
static func _band(k: MeshKit, xf: Transform3D, rad: float, w: float, col := STRAP) -> void:
	k.cylinder("own:leather", xf * _at(0, -w * 0.5, 0), rad, rad, w, 28, false, 0.0, 1, col)
	ItemModels._torus(k, "own:leather", xf * _at(0, -w * 0.5, 0), rad, 0.0012, 28, 3, col.darkened(0.2))
	ItemModels._torus(k, "own:leather", xf * _at(0, w * 0.5, 0), rad, 0.0012, 28, 3, col.darkened(0.2))

# --- Treasure ----------------------------------------------------------------------------

## A silver chalice: a wide foot, a stem with a knop, a deep bowl whose lower half is
## embossed with a band of leaf arches, the inside hollow; tarnish darkens the hollows.
static func _chalice(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var arch := func(a: float, y: float) -> float:
		# How far the embossed leaf band stands out at angle a and height y.
		var u := fposmod(a * 8.0 / TAU, 1.0)
		var top := 0.112 + 0.03 * pow(sin(PI * u), 0.6)
		if y < 0.108 or y > 0.146:
			return 0.0
		if y > 0.14:
			return 0.05
		return 0.06 if y < top and y > 0.112 else 0.0
	var outer := [Vector2(0, 0), Vector2(0.044, 0), Vector2(0.044, 0), Vector2(0.046, 0.005), Vector2(0.04, 0.012), Vector2(0.022, 0.02), Vector2(0.011, 0.034),
		Vector2(0.008, 0.058), Vector2(0.016, 0.07), Vector2(0.016, 0.075), Vector2(0.008, 0.087), Vector2(0.012, 0.1), Vector2(0.03, 0.108), Vector2(0.042, 0.12),
		Vector2(0.046, 0.14), Vector2(0.049, 0.165), Vector2(0.052, 0.19), Vector2(0.052, 0.19), Vector2(0.048, 0.191)]
	var cup := Transform3D(Basis.from_scale(Vector3(1.12, 0.92, 1.12)), Vector3.ZERO)
	_lathe(k, "im:metal@0.42", cup, outer,
		func(p: Vector3, a: float, _t2: float) -> Color:
			var e: float = arch.call(a, p.y)
			var c := SILVER.darkened(0.06 * (Provisions._nz(p, 60.0) + 0.5))
			if p.y > 0.108 and p.y < 0.146 and e <= 0.0:
				c = c.darkened(0.18)
			return c,
		48, func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + float(arch.call(a, p.y)))
	_lathe(k, "im:metal@0.42", cup, [Vector2(0.048, 0.191), Vector2(0.046, 0.165), Vector2(0.042, 0.14), Vector2(0.032, 0.122), Vector2(0, 0.116)], SILVER.darkened(0.25), 40)
	return Vector3(0, 0.06, 0)

## A moonpearl: a perfect sphere with a pearl's lustre, its white shot with soft rainbow
## colours (pink, aqua, lilac) as the light moves round it.
static func _moonpearl(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	Provisions.lathe(k, "own:pearl", _at(0, 0.014, 0), Provisions._sphere(0.014, 18), 32,
		func(p: Vector3, a: float, t: float) -> Color:
			var h := fposmod(a / TAU * 1.5 + t * 0.9 + 0.2 * Provisions._nz(p, 90.0), 1.0)
			return Color.from_hsv(h, 0.28, 0.9).lerp(Color(0.78, 0.8, 0.88), 0.3).darkened(0.25 * (1.0 - t)))
	return Vector3(0, 0.014, 0)

## One gold coin round +Y: a milled rim standing proud, a sunk field and a struck device.
static func _coin(k: MeshKit, xf: Transform3D, r: float, th: float, col: Color) -> void:
	var prof := PackedVector2Array([Vector2(0, 0), Vector2(r * 0.96, 0), Vector2(r, th * 0.2), Vector2(r, th * 0.8), Vector2(r * 0.95, th * 1.08), Vector2(r * 0.85, th * 1.08), Vector2(r * 0.8, th * 0.82), Vector2(0, th * 0.82)])
	Provisions.lathe(k, "im:metal@0.38", xf, prof, 28, func(p: Vector3, _a: float, _t: float) -> Color:
		var rr := Vector2(p.x, p.z).length()
		return col.darkened(0.18) if rr < r * 0.82 and rr > r * 0.7 else col)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var s := i / 8.0
		path.append(Vector3(sin(s * TAU) * r * 0.22, th * 0.86, (s - 0.5) * r * 0.9))
		radii.append(th * 0.22)
	ItemModels._tube(k, "im:metal@0.38", xf, path, radii, 4, col.lightened(0.05))

## A pile of gold coins: two short stacks with coins leaning on them and a few lying
## loose in front, warm polished gold with each rim catching the light.
static func _coins(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var cr := 0.0125
	var th := 0.0034
	for st: Array in [[Vector3(-0.007, 0, -0.012), 6], [Vector3(0.017, 0, -0.006), 3]]:
		for i in int(st[1]):
			var p: Vector3 = st[0] + Vector3(r.randf_range(-0.0012, 0.0012), i * th * 1.05, r.randf_range(-0.0012, 0.0012))
			_coin(k, Transform3D(Basis(Vector3.UP, r.randf() * TAU).rotated(Vector3.RIGHT, r.randf_range(-0.05, 0.05)), p), cr, th, GOLD.darkened(r.randf_range(0.0, 0.1)))
	for c: Array in [[Vector3(-0.026, 0.004, -0.002), Vector3.BACK, 0.9], [Vector3(-0.004, 0.008, 0.004), Vector3.RIGHT, 1.0], [Vector3(0.026, 0.006, 0.006), Vector3.RIGHT, 0.8],
			[Vector3(-0.024, 0.002, 0.018), Vector3.RIGHT, 0.5], [Vector3(0.006, 0.0, 0.03), Vector3.RIGHT, 0.35], [Vector3(0.034, 0, -0.02), Vector3.BACK, 0.1], [Vector3(0.012, 0.016, -0.014), Vector3.RIGHT, 0.6]]:
		_coin(k, Transform3D(Basis(c[1], c[2]), c[0]), cr, th, GOLD.darkened(r.randf_range(0.0, 0.08)))
	return Vector3(0, 0.01, 0)

## A rune tablet: a slab of dark slate with rounded, uneven edges, a great rune and small
## marks cut into its face and filled with violet paint; its bevel tinged violet too.
static func _rune_tablet(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var W := Transform3D(Basis(Vector3.BACK, -0.18), Vector3.ZERO)
	var ring := func(y: float, inset: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in 28:
			var a := TAU * i / 28.0
			var c := cos(a)
			var s := sin(a)
			var m := 1.0 / pow(pow(absf(c), 3.0) + pow(absf(s), 3.0), 1.0 / 3.0)
			var j := 1.0 + 0.05 * Provisions._nz(Vector3(c, s, 0.3), 2.0)
			out.append(Vector3(c * m * (0.056 * j - inset), y, s * m * (0.076 * j - inset)))
		return out
	var slab := W * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	var stone := Color(0.2, 0.19, 0.24)
	ItemModels._loft(k, "im:stone", slab, [ring.call(-0.012, 0.004), ring.call(-0.009, 0.0), ring.call(0.008, 0.0), ring.call(0.012, 0.005)], Color(0.3, 0.22, 0.42), "im:stone", stone)
	var ink := Color(0.62, 0.38, 0.95)
	var z := 0.0125
	# The great rune: a stave with a bowl and a kicked leg.
	var strokes := [[Vector2(-0.016, -0.04), Vector2(-0.016, 0.042)], [Vector2(-0.016, 0.042), Vector2(0.016, 0.026)], [Vector2(0.016, 0.026), Vector2(-0.014, 0.008)],
		[Vector2(-0.014, 0.008), Vector2(0.02, -0.04)],
		# Small marks round it.
		[Vector2(0.026, 0.052), Vector2(0.034, 0.042)], [Vector2(0.034, 0.042), Vector2(0.026, 0.034)], [Vector2(0.036, 0.056), Vector2(0.036, 0.036)],
		[Vector2(-0.036, -0.044), Vector2(-0.03, -0.054)], [Vector2(-0.03, -0.054), Vector2(-0.036, -0.062)],
		[Vector2(0.02, -0.058), Vector2(0.03, -0.05)], [Vector2(0.025, -0.062), Vector2(0.025, -0.046)]]
	for s: Array in strokes:
		var w := 0.0055 if strokes.find(s) < 4 else 0.0028
		_stroke(k, "own:inlay", W, s[0], s[1], w, 0.0012, z, ink)
	return Vector3(0, -0.04, 0)

## A key along +Y: the bit at the bottom, the shaft with its collars, the bow at the top.
## `bow` "ornate" is a ring with scrolled lobes and a curl inside; "double" a heavy
## two-holed bow. Returns where the fingers hold it (the bow).
static func _key(k: MeshKit, length: float, rad: float, col: Color, bow: String, bit: Array) -> Vector3:
	var m := "im:metal@0.4"
	var top := length * 0.7
	k.cylinder(m, _at(0, 0, 0), rad, rad, top, 12, true, 0.0, 1, col)
	k.sphere(m, _at(0, 0, 0), rad * 1.05, 5, 10, 0.0, 1.0, col)
	for y: float in [top - rad * 1.5, top - rad * 3.6, length * 0.3]:
		ItemModels._torus(k, m, _at(0, y, 0), rad * 1.15, rad * 0.5, 14, 6, col.lightened(0.05))
	# The bit: a plate off one side with its wards cut.
	for b: Array in bit:
		k.box(m, _at(rad + float(b[0]) * 0.5, float(b[1]), 0), Vector3(float(b[0]), float(b[2]), rad * 1.3), col.darkened(0.08))
	var cy := top + length * 0.14
	var R := length * 0.11
	match bow:
		"ornate":
			ItemModels._torus(k, m, _at(0, cy, 0, FRONT), R, rad * 0.75, 28, 7, col)
			for i in 5:
				var a := PI * 0.25 * i
				var c := Vector3(cos(a) * R * 1.3, cy + sin(a) * R * 1.3, 0)
				ItemModels._torus(k, m, Transform3D(FRONT, c), R * 0.5, rad * 0.6, 18, 5, col.lightened(0.04))
				var path2 := PackedVector3Array()
				var radii2 := PackedFloat32Array()
				for s in 13:
					var t := s / 12.0
					var b := a + t * TAU * 0.9
					path2.append(c + Vector3(cos(b), sin(b), 0) * R * 0.32 * (1.0 - t * 0.7))
					radii2.append(rad * 0.4)
				ItemModels._tube(k, m, Transform3D.IDENTITY, path2, radii2, 4, col.darkened(0.05))
			# The scroll inside the ring.
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for s in 25:
				var t := s / 24.0
				var a := t * TAU * 1.6
				path.append(Vector3(cos(a) * R * 0.75 * (1.0 - t * 0.8), cy + sin(a) * R * 0.75 * (1.0 - t * 0.8), 0))
				radii.append(rad * 0.45)
			ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 5, col.darkened(0.05))
			k.cylinder(m, _at(0, top - rad, 0), rad * 1.4, rad * 1.1, cy - R - top + rad * 1.5, 10, true, 0.0, 1, col)
		"double":
			R *= 1.35
			cy += R * 0.25
			for s: float in [-1.0, 1.0]:
				ItemModels._torus(k, m, _at(s * R * 0.72, cy, 0, FRONT), R * 0.8, rad * 1.1, 24, 8, col)
			k.cylinder(m, _at(0, top - rad, 0), rad * 1.5, rad * 1.3, cy - R * 0.6 - top + rad, 12, true, 0.0, 1, col)
	return Vector3(0, cy, 0)

## The watch's keys: four blackened iron keys of different lengths and bows on a heavy
## iron ring, fanned out below it. Held by the ring.
static func _key_ring(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var iron := Color(0.4, 0.35, 0.31)
	var m := "im:metal@0.6"
	var c := Vector3(0, 0.2, 0)
	var R := 0.042
	ItemModels._torus(k, m, Transform3D(FRONT, c), R, 0.0065, 36, 8, Color(0.3, 0.27, 0.25))
	# [angle off straight down, length, bow radius, bow turned about the shaft]
	for kd: Array in [[-0.62, 0.13, 0.016, 1.2], [-0.2, 0.155, 0.019, -1.1], [0.22, 0.14, 0.015, 1.0], [0.6, 0.12, 0.017, -1.3]]:
		var a := float(kd[0])
		var L := float(kd[1])
		var br := float(kd[2])
		var col := iron.lightened(0.06 * absf(a))
		# Hanging from the ring's lower arc, the bow threaded through it, the shaft pointing
		# away from the ring's centre.
		var xf := Transform3D(Basis(Vector3.BACK, a), c + Vector3(sin(a), -cos(a), 0) * R)
		ItemModels._torus(k, m, xf * Transform3D(Basis(Vector3.UP, float(kd[3])) * FRONT, Vector3(0, -br * 0.55, 0)), br, 0.0038, 20, 6, col)
		var top := -br * 1.5
		k.cylinder(m, xf * _at(0, top - L * 0.85, 0), 0.0045, 0.0045, L * 0.85, 10, true, 0.0, 1, col)
		ItemModels._torus(k, m, xf * _at(0, top - 0.008, 0), 0.0056, 0.0022, 12, 5, col)
		# The bit: a plate off one side, its wards cut in steps.
		var tip := top - L * 0.85
		for b: Array in [[0.018, 0.006, 0.014], [0.011, 0.016, 0.007], [0.019, 0.025, 0.006]]:
			k.box(m, xf * _at(0.0045 + float(b[0]) * 0.5, tip + float(b[1]), 0), Vector3(float(b[0]), float(b[2]), 0.0045), col.darkened(0.08))
	return c + Vector3(0, R, 0)

## A grappling hook: a forged iron shank with an eye at the top, three barbed prongs
## curling up from its foot, and a coil of hemp rope tied through the eye and looped
## round the shank. Held by the shank.
static func _grapnel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var iron := Color(0.27, 0.25, 0.24)
	var m := "im:metal@0.55"
	var L := 0.26
	k.cylinder(m, _at(0, 0.02, 0), 0.015, 0.012, L - 0.02, 12, true, 0.0, 1, iron)
	k.sphere(m, _at(0, 0.025, 0), 0.022, 6, 10, 0.0, 0.8, iron.darkened(0.1))
	ItemModels._torus(k, m, Transform3D(FRONT, Vector3(0, L + 0.024, 0)), 0.024, 0.0075, 24, 7, iron)
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var d := Vector3(cos(a), 0, sin(a))
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		# Out from the foot, down round a broad curve and back up to a point, like an anchor's arm.
		for s in 17:
			var t := s / 16.0
			var ang := deg_to_rad(lerpf(200.0, 405.0, t))
			var q := Vector2(0.068, 0.07) + Vector2(cos(ang), sin(ang)) * 0.062
			path.append(d * q.x + Vector3(0, q.y, 0))
			radii.append(lerpf(0.012, 0.003, t * t))
		ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 8, iron.lightened(0.04))
		# The barb, a short spur back off the point.
		var tip := path[path.size() - 1]
		ItemModels._tube(k, m, Transform3D.IDENTITY, PackedVector3Array([tip - Vector3(0, 0.02, 0) + d * 0.008, tip - Vector3(0, 0.036, 0) - d * 0.01]), PackedFloat32Array([0.005, 0.0015]), 6, iron)
	# The rope: knotted through the eye and down to a coil of loops hung beside the shank.
	var rope := Color(0.36, 0.25, 0.15)
	var rad := 0.0095
	var cb := Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, 0.25)
	var cc := Vector3(0.09, L - 0.04, 0.02)
	var rp := PackedVector3Array([Vector3(0, L + 0.046, 0), Vector3(0.022, L + 0.035, 0.012), Vector3(0.045, L + 0.012, 0.02)])
	var rr := PackedFloat32Array([rad, rad, rad])
	for s in 100:
		var t := s / 99.0
		var ang := PI * 0.6 - t * TAU * 5.0
		# Loose loops, each hanging a little differently, not wound tight like a spool.
		var R := 0.068 + 0.01 * sin(t * 23.0)
		var sag := Vector3(0.012 * sin(t * 17.0), -0.014 * pow(sin(t * PI * 5.0), 2.0), 0)
		rp.append(cc + cb * (Vector3(cos(ang) * R, sin(ang) * R, (t - 0.5) * 0.06) + sag))
		rr.append(rad)
	ItemModels._tube(k, "im:rope", Transform3D.IDENTITY, rp, rr, 7, rope)
	ItemModels._torus(k, "im:rope", Transform3D(FRONT, Vector3(0, L + 0.04, 0.0)), 0.011, 0.0075, 12, 5, rope.darkened(0.1))
	return Vector3(0, L * 0.45, 0)

## A town watch tabard laid flat: a sleeveless coat of wool quartered red and yellow, a
## yellow tower on the red and a red tower on the yellow, its neck dipped, its hem ragged
## from wear. Held by a shoulder.
static func _tabard(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var red := Color(0.42, 0.07, 0.05)
	var gold := Color(0.62, 0.41, 0.1)
	var H := 0.72
	var shape := func(u: float, v: float) -> Vector3:
		var x := u - 0.5
		# Shoulders narrower than the body, cut in under the arms, then a slight flare.
		var arm := smoothstep(0.62, 0.8, v)
		var half := lerpf(0.24, 0.215, v) - 0.06 * arm + 0.012 * smoothstep(0.92, 1.0, v)
		var top := H - 0.075 * maxf(0.0, 1.0 - absf(x) / 0.17)
		# The ragged hem: notches cut into it, uneven like worn wool.
		var bottom := 0.035 * absf(sin(u * PI * 7.0)) + 0.02 * Provisions._nz(Vector3(u * 6.0, 0.3, 0.7), 2.0)
		return Vector3(x * 2.0 * half, lerpf(bottom, top, v), 0.008 * sin(u * 9.0 + v * 4.0) + 0.01 * sin(u * PI))
	var quarter := func(p: Vector3, _u: float, _v: float) -> Color:
		var col := red if (p.x < 0.0) == (p.y > H * 0.5) else gold
		return col.darkened(0.14 * (Provisions._nz(p, 80.0) + 0.4))
	Provisions.sheet(k, "im:linen", _at(0, 0, 0.004), 48, 48, shape, quarter, Vector3.BACK)
	Provisions.sheet(k, "im:linen", _at(0, 0, -0.004), 12, 12, shape, func(p: Vector3, _u: float, _v: float) -> Color: return red.darkened(0.35) if p.x < 0.0 else gold.darkened(0.35), Vector3.FORWARD)
	# A dark bound edge round the neck.
	var neck := PackedVector3Array()
	var nr := PackedFloat32Array()
	for s in 13:
		var x := lerpf(-0.17, 0.17, s / 12.0)
		neck.append(Vector3(x, H - 0.075 * maxf(0.0, 1.0 - absf(x) / 0.17), 0.012 + 0.01 * sin((x / 0.48 + 0.5) * PI)))
		nr.append(0.006)
	ItemModels._tube(k, "im:linen", Transform3D.IDENTITY, neck, nr, 5, Color(0.25, 0.16, 0.1))
	# The badge: a shield in the middle, halved gold and red, a gold tower on it.
	var sh := func(u: float, v: float) -> Vector3:
		var w := 0.085 * (1.0 - pow(1.0 - v, 2.2))
		return Vector3((u - 0.5) * 2.0 * w, lerpf(-0.12, 0.08, v), 0.0)
	var cy := H * 0.55
	Provisions.sheet(k, "im:linen", _at(0, cy, 0.034), 10, 10, sh, func(p: Vector3, _u: float, _v: float) -> Color: return red.darkened(0.1) if p.x > 0.0 else gold.darkened(0.05), Vector3.BACK)
	var tc := gold.lightened(0.05)
	k.box("im:linen", _at(0, cy - 0.015, 0.037), Vector3(0.05, 0.09, 0.003), tc)
	for mx: float in [-0.019, 0.0, 0.019]:
		k.box("im:linen", _at(mx, cy + 0.037, 0.037), Vector3(0.011, 0.016, 0.003), tc)
	k.box("im:linen", _at(0, cy - 0.043, 0.0388), Vector3(0.016, 0.032, 0.001), red.darkened(0.5))
	return Vector3(-0.17, H - 0.02, 0)

## The ornate dungeon key: old gilded bronze, a filigree bow of a ring and three scrolled
## lobes round a curl, collared shaft and a bit cut with cross-shaped wards.
static func _dungeon_key(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var col := Color(0.58, 0.42, 0.22)
	return _key(k, 0.11, 0.0032, col, "ornate", [[0.012, 0.016, 0.004], [0.004, 0.009, 0.014], [0.012, 0.004, 0.006], [0.008, 0.01, 0.003]])

## The safe key: dark oiled bronze, a heavy figure-eight bow, thick collared shank and a
## bit stepped into square teeth.
static func _safe_key(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var col := Color(0.42, 0.27, 0.2)
	return _key(k, 0.1, 0.0055, col, "double", [[0.013, 0.012, 0.022], [0.007, 0.006, 0.008], [0.014, 0.004, 0.008]])

## The golden skull idol: a cast-gold skull, the dome broad over a narrower jaw, deep
## dark eye sockets and nose, brow and cheekbones standing out, the teeth in two rows,
## its dome chased with scrolling lines.
static func _gold_idol(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.36"
	var g := Color(0.92, 0.64, 0.22)
	var dark := Color(0.16, 0.09, 0.02)
	# Face tipped up a little toward whoever holds it.
	var xf := Transform3D(Basis(Vector3.RIGHT, -0.25) * Basis(Vector3.UP, 0.25), Vector3(0, 0.056, 0))
	var eyes := [Vector3(0.46, 0.06, 0.89).normalized(), Vector3(-0.46, 0.06, 0.89).normalized()]
	var nose := Vector3(0, -0.24, 0.97).normalized()
	var brow := Vector3(0, 0.32, 0.95).normalized()
	var cheeks := [Vector3(0.64, -0.22, 0.74).normalized(), Vector3(-0.64, -0.22, 0.74).normalized()]
	var dirf := func(u: float, v: float) -> Vector3:
		var th := u * TAU
		var ph := lerpf(0.004, 0.996, v) * PI
		return Vector3(sin(ph) * sin(th), -cos(ph), sin(ph) * cos(th))
	# How deep a point is sunk (sockets, nose, gaps between the teeth), as 0..1.
	var hollow := func(d: Vector3) -> float:
		var h := 0.0
		for e: Vector3 in eyes:
			h = maxf(h, smoothstep(0.93, 0.975, d.dot(e)))
		h = maxf(h, smoothstep(0.98, 0.995, d.dot(nose)) * (1.0 if d.y < nose.y + 0.05 else 0.0))
		if d.z > 0.5 and d.y < -0.42 and d.y > -0.68:
			if fposmod(atan2(d.x, d.z) * 5.5 + 0.5, 1.0) < 0.16 or absf(d.y + 0.54) < 0.022:
				h = maxf(h, 0.6)
		return h
	var surf := func(d: Vector3) -> Vector3:
		var jaw := smoothstep(-0.12, -0.85, d.y)
		var p := Vector3(d.x * 0.043 * (1.0 - 0.34 * jaw), d.y * 0.054, d.z * (0.05 * (1.0 - 0.5 * jaw) if d.z < 0.0 else 0.052 * (1.0 + 0.1 * jaw)))
		var bump := 0.003 * smoothstep(0.86, 0.96, d.dot(brow))
		for c: Vector3 in cheeks:
			bump += 0.004 * smoothstep(0.9, 0.98, d.dot(c))
		if d.z > 0.5 and d.y < -0.42 and d.y > -0.68:
			bump += 0.003
		return p + d * (bump - 0.014 * float(hollow.call(d)))
	Provisions.sheet(k, m, xf, 96, 72, func(u: float, v: float) -> Vector3: return surf.call(dirf.call(u, v)),
		func(_p: Vector3, u: float, v: float) -> Color:
			var d: Vector3 = dirf.call(u, v)
			return g.lerp(dark, clampf(float(hollow.call(d)) * 1.6 - 0.2, 0.0, 1.0)))
	k.sphere(m, xf * _at(0, 0.054, 0), 0.0025, 4, 6, 0.0, 1.0, g)
	# Chased scrolls on the dome.
	for sc: Array in [[0.0, 0.62, 1.0], [0.8, 0.4, 0.8], [-0.8, 0.4, -0.8], [1.4, 0.15, 1.0], [-1.4, 0.15, -1.0], [0.0, 1.0, 1.0], [2.3, 0.4, 1.0], [-2.3, 0.4, -1.0]]:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for s in 22:
			var t := s / 21.0
			var ang := t * TAU * 1.3 * float(sc[2])
			var th := float(sc[0]) + cos(ang) * 0.3 * (1.0 - t * 0.7)
			var ph := float(sc[1]) + sin(ang) * 0.26 * (1.0 - t * 0.7)
			var d := Vector3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))
			path.append(surf.call(d) + d * 0.0008)
			radii.append(0.0011)
		ItemModels._tube(k, m, xf, path, radii, 4, g.darkened(0.3))
	return Vector3(0, 0.04, 0)

## The void gem: a brilliant-cut violet stone, flat table on top, crown facets down to
## the girdle and a pavilion tapering to a point; each facet a slightly different shade.
static func _void_gem(k: MeshKit, r: RandomNumberGenerator, t: String):
	var m := "im:crystal:" + t
	var base := Color(0.42, 0.12, 0.78, 0.92)
	var R := 0.017
	var girdle_y := 0.02
	var tab := PackedVector3Array()
	var gir := PackedVector3Array()
	var gir2 := PackedVector3Array()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		tab.append(Vector3(cos(a) * R * 0.56, girdle_y + 0.0065, sin(a) * R * 0.56))
	for i in 16:
		var a := TAU * i / 16.0
		gir.append(Vector3(cos(a) * R, girdle_y + 0.0008, sin(a) * R))
		gir2.append(Vector3(cos(a) * R, girdle_y - 0.0008, sin(a) * R))
	var facet := func(a: Vector3, b: Vector3, c: Vector3, light: float) -> void:
		var n := (b - a).cross(c - a).normalized()
		var mid := (a + b + c) / 3.0
		if n.dot(mid - Vector3(0, girdle_y, 0)) < 0.0:
			n = -n
		var col := base.lightened(light) if light >= 0.0 else base.darkened(-light)
		ItemModels._tri(k, m, Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3.ZERO), a, b, c, n, n, n, col)
	var top := Vector3(0, girdle_y + 0.0065, 0)
	for i in 8:
		facet.call(top, tab[i], tab[(i + 1) % 8], 0.25)
		var g0 := gir[(2 * i) % 16]
		var g1 := gir[(2 * i + 1) % 16]
		var g2 := gir[(2 * i + 2) % 16]
		facet.call(tab[i], g0, g1, r.randf_range(0.0, 0.35))
		facet.call(tab[i], g1, tab[(i + 1) % 8], r.randf_range(0.1, 0.45))
		facet.call(tab[(i + 1) % 8], g1, g2, r.randf_range(0.0, 0.35))
	var culet := Vector3(0, 0, 0)
	for i in 16:
		var j := (i + 1) % 16
		facet.call(gir[i], gir2[i], gir2[j], -0.1)
		facet.call(gir[i], gir2[j], gir[j], -0.1)
		facet.call(gir2[i], culet, gir2[j], r.randf_range(-0.3, 0.05))
	return Vector3(0, 0.012, 0)

## A lockpick: a thin rod of dark forged iron with a ring at the end for the finger, the
## grip bound with cord, and a fine hook at the tip.
static func _lockpick(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.55"
	ItemModels._torus(k, m, _at(0, -0.009, 0, FRONT), 0.007, 0.0019, 20, 6, IRON)
	k.cylinder(m, _at(0, -0.0015, 0), 0.0024, 0.0018, 0.12, 8, false, 0.0, 1, IRON)
	k.cylinder(m, _at(0, 0.012, 0), 0.0032, 0.0032, 0.05, 8, true, 0.0, 1, IRON)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for s in 121:
		var a := s / 120.0 * TAU * 14.0
		path.append(Vector3(cos(a) * 0.0042, 0.022 + s / 120.0 * 0.03, sin(a) * 0.0042))
		radii.append(0.0012)
	ItemModels._tube(k, "im:rope", Transform3D.IDENTITY, path, radii, 4, Color(0.36, 0.23, 0.13))
	ItemModels._tube(k, m, Transform3D.IDENTITY, PackedVector3Array([Vector3(0, 0.117, 0), Vector3(0, 0.124, 0), Vector3(0.0015, 0.128, 0), Vector3(0.004, 0.129, 0), Vector3(0.006, 0.126, 0)]),
		PackedFloat32Array([0.0018, 0.0017, 0.0015, 0.0013, 0.0011]), 6, IRON)
	return Vector3(0, 0.035, 0)

# --- Camp --------------------------------------------------------------------------------

## A bedroll: khaki canvas rolled tight, the spiral of its layers at the ends and the
## outer edge lying along it, cinched by two leather straps with dark iron buckles.
static func _bedroll(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var L := 0.52
	var rad := 0.125
	var canvas := Color(0.45, 0.38, 0.26)
	# Turned so one rolled end faces the viewer, as in the icon.
	var W := Transform3D(Basis(Vector3.UP, -0.42), Vector3.ZERO)
	var R := W * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(L * 0.5, rad, 0))
	k.cylinder("own:canvas", R, rad, rad, L, 32, false, 0.035, 10, canvas)
	_spiral(k, "own:canvas", R, rad, 0.0, -1.0, canvas.darkened(0.35), canvas.darkened(0.12), 5, 0.004)
	_spiral(k, "own:canvas", R, rad, L, 1.0, canvas.darkened(0.35), canvas.darkened(0.12), 5, 0.004)
	# The outer edge of the cloth, along the top.
	k.box("own:canvas", W * _at(0, rad + sin(1.1) * rad, cos(1.1) * rad), Vector3(L * 0.98, 0.006, 0.004), canvas.darkened(0.25))
	for x: float in [-0.14, 0.14]:
		_band(k, W * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, rad, 0)), rad + 0.005, 0.042)
		var al := 0.5
		_buckle(k, W * Transform3D(Basis(Vector3.RIGHT, -al), Vector3(x, rad + sin(al) * (rad + 0.007), cos(al) * (rad + 0.007))), 0.034, Color(0.14, 0.13, 0.12))

## A tent kit: a bundle of folded pale canvas with the tent poles laid along its top,
## lashed together by two leather straps buckled at the front.
static func _tent_kit(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var canvas := Color(0.55, 0.49, 0.38)
	Provisions.rounded_box(k, "own:canvas", Transform3D.IDENTITY, Vector3(0.5, 0.2, 0.24), 0.09, canvas, 3.0,
		func(a: float, t: float, p: Vector3) -> float: return 1.0 + 0.06 * Provisions._nz(p * Vector3(1.0, 30.0, 1.0), 6.0) + 0.03 * sin(a * 6.0 + t * 9.0))
	# Folds in the cloth.
	for i in 4:
		var x := lerpf(-0.18, 0.18, i / 3.0) + r.randf_range(-0.02, 0.02)
		k.box("own:canvas", Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(x, 0.1, 0.122)), Vector3(0.008, 0.12, 0.01), canvas.darkened(0.2))
	var wood := Color(0.62, 0.42, 0.22)
	for p: Vector2 in [Vector2(-0.06, 0.212), Vector2(-0.02, 0.21), Vector2(0.02, 0.212), Vector2(0.06, 0.21), Vector2(-0.04, 0.24), Vector2(0.0, 0.242), Vector2(0.04, 0.24)]:
		var l := 0.56 + r.randf_range(-0.03, 0.03)
		var xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(l * 0.5 + r.randf_range(-0.01, 0.01), p.y, p.x))
		k.cylinder("own:wood", xf, 0.016, 0.016, l, 10, true, 0.0, 1, wood.darkened(r.randf_range(0.0, 0.15)))
	for x: float in [-0.15, 0.15]:
		# The strap round bundle and poles: front, top, back, bottom.
		k.box("own:leather", _at(x, 0.13, 0.124), Vector3(0.036, 0.25, 0.005), STRAP)
		k.box("own:leather", _at(x, 0.26, 0.0), Vector3(0.036, 0.005, 0.24), STRAP)
		k.box("own:leather", _at(x, 0.13, -0.124), Vector3(0.036, 0.25, 0.005), STRAP)
		k.box("own:leather", _at(x, -0.001, 0.0), Vector3(0.036, 0.004, 0.24), STRAP)
		_buckle(k, _at(x, 0.15, 0.127), 0.032, Color(0.14, 0.13, 0.12))

# --- Games and music ----------------------------------------------------------------------

## A die of bone: rounded ivory cube, black pips sunk in its faces (opposite faces add
## to seven).
static func _die(k: MeshKit, xf: Transform3D, s: float, col: Color) -> void:
	k.bevel_box("own:ivory", xf, Vector3(s, s, s), s * 0.16, col)
	var faces := [[Vector3.UP, 4], [Vector3.DOWN, 3], [Vector3.BACK, 5], [Vector3.FORWARD, 2], [Vector3.RIGHT, 6], [Vector3.LEFT, 1]]
	var layouts := {1: [Vector2(0, 0)], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)], 5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]}
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
		var v := n.cross(u)
		for q: Vector2 in layouts[int(f[1])]:
			var c := n * (s * 0.5 + 0.0002) + (u * q.x + v * q.y) * s * 0.27
			ItemModels._disc(k, "own:ivory", xf, c, n, s * 0.1, 10, Color(0.06, 0.05, 0.04))

## A pair of bone dice: ivory cubes with rounded edges and black pips, one turned
## against the other.
static func _dice(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var s := 0.018
	var col := Color(0.86, 0.72, 0.5)
	_die(k, _at(-0.011, s * 0.5, 0.0, Basis(Vector3.UP, 0.45)), s, col)
	_die(k, _at(0.012, s * 0.5, 0.004, Basis(Vector3.UP, -0.35) * Basis(Vector3.RIGHT, PI * 0.5)), s, col.darkened(0.04))
	return Vector3(0, 0.009, 0)

## A lute: the vaulted pear-shaped back of glued ribs, a pale spruce soundboard with a
## dark binding and a carved rose, the bridge, a dark fingerboard with frets, eight gut
## strings, and the pegbox bent sharply back with its pegs.
static func _lute(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var light := Color(0.74, 0.43, 0.17)
	var rib := Color(0.45, 0.22, 0.08)
	var dark := Color(0.28, 0.14, 0.06)
	var y0 := -0.46
	# Turned a little on its long axis, so the dark vaulted back shows along one edge.
	var W := Transform3D(Basis(Vector3.UP, 0.45), Vector3.ZERO)
	var w := func(t: float) -> float: return 0.17 * pow(sin(PI * pow(t, 0.72)), 0.62) + 0.022 * smoothstep(0.65, 1.0, t)
	var body := W * Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0))
	Provisions.sheet(k, "own:wood", body, 66, 30, func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ww: float = w.call(v)
		return Vector3(ww * cos(th), y0 + v * 0.46 + 0.25, -ww * 0.9 * sin(th)),
		func(_p: Vector3, u: float, _v: float) -> Color: return rib.darkened(0.45) if fposmod(u * 11.0, 1.0) < 0.17 else rib)
	# The soundboard: a fan from its middle out to the outline.
	var ol := PackedVector3Array()
	for i in 41:
		var t := i / 40.0
		ol.append(Vector3(w.call(t), y0 + t * 0.46, 0.003))
	for i in range(40, -1, -1):
		var t := i / 40.0
		ol.append(Vector3(-w.call(t), y0 + t * 0.46, 0.003))
	var c := Vector3(0, -0.25, 0.003)
	for i in ol.size() - 1:
		ItemModels._tri(k, "own:wood", W, c, ol[i], ol[i + 1], Vector3.BACK, Vector3.BACK, Vector3.BACK, light)
	var rad := PackedFloat32Array()
	for i in ol.size():
		ol[i] = ol[i] - Vector3(0, 0, 0.0015)
		rad.append(0.0055)
	ItemModels._tube(k, "own:wood", W, ol, rad, 6, dark)
	# The rose: a dark sound hole with a carved lattice.
	ItemModels._disc(k, "own:wood", W, Vector3(0, -0.17, 0.0034), Vector3.BACK, 0.042, 24, Color(0.08, 0.05, 0.03))
	ItemModels._torus(k, "own:wood", W * _at(0, -0.17, 0.0036, FRONT), 0.042, 0.003, 28, 4, light.darkened(0.15))
	for i in 4:
		var a := PI * i / 4.0
		_stroke(k, "own:wood", W, Vector2(cos(a), sin(a) - 4.05) * 0.042, Vector2(-cos(a), -sin(a) - 4.05) * 0.042, 0.003, 0.002, 0.0037, light.darkened(0.2))
	ItemModels._torus(k, "own:wood", W * _at(0, -0.17, 0.0037, FRONT), 0.02, 0.0025, 20, 4, light.darkened(0.2))
	# Bridge.
	k.bevel_box("own:wood", W * _at(0, -0.37, 0.007), Vector3(0.1, 0.012, 0.008), 0.002, dark)
	# Neck and fingerboard.
	k.bevel_box("own:wood", W * _at(0, 0.13, -0.014), Vector3(0.048, 0.28, 0.028), 0.008, rib)
	k.box("own:wood", W * _at(0, 0.12, 0.003), Vector3(0.05, 0.3, 0.006), dark)
	for i in 8:
		k.box("im:metal@0.4", W * _at(0, 0.26 - i * 0.03, 0.0065), Vector3(0.05, 0.0012, 0.0012), Color(0.75, 0.7, 0.6))
	k.box("own:ivory", W * _at(0, 0.27, 0.007), Vector3(0.05, 0.004, 0.004), Color(0.9, 0.86, 0.75))
	# The pegbox, bent back, and its pegs.
	var pb := W * Transform3D(Basis(Vector3.RIGHT, -1.15), Vector3(0, 0.27, 0.0))
	k.bevel_box("own:wood", pb * _at(0, 0.065, -0.006), Vector3(0.042, 0.13, 0.024), 0.005, rib.darkened(0.1))
	for i in 4:
		for s: float in [-1.0, 1.0]:
			var p := pb * Vector3(s * 0.03, 0.03 + i * 0.026 + (0.013 if s > 0 else 0.0), -0.006)
			k.cylinder("own:wood", Transform3D(Basis(Vector3.BACK, PI * 0.5 * s), p - Vector3(s * 0.012, 0, 0)), 0.0035, 0.004, 0.024, 8, true, 0.0, 1, dark)
			k.sphere("own:wood", Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 1.0)), p + Vector3(s * 0.012, 0, 0)), 0.007, 5, 8, 0.0, 1.0, dark)
	# Strings, bridge to nut.
	for i in 8:
		var x0 := lerpf(-0.034, 0.034, i / 7.0)
		var x1 := lerpf(-0.02, 0.02, i / 7.0)
		ItemModels._tube(k, "im:rope", W, PackedVector3Array([Vector3(x0, -0.37, 0.0115), Vector3(x1, 0.272, 0.0095)]), PackedFloat32Array([0.0006, 0.0006]), 3, Color(0.9, 0.86, 0.75), false)
	return Vector3(0, 0.12, 0)

## A wooden flute: a turned tube of honey-coloured wood with six finger holes and the
## mouth hole along its front, dark horn bands and a brass ferrule at the ends.
static func _flute(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var wood := Color(0.6, 0.34, 0.14)
	var L := 0.36
	var rr := 0.016
	_lathe(k, "own:wood", Transform3D.IDENTITY, [Vector2(0, 0.0), Vector2(rr * 1.1, 0.0), Vector2(rr * 1.1, 0.0), Vector2(rr * 1.1, 0.025), Vector2(rr, 0.03), Vector2(rr * 0.97, L * 0.5), Vector2(rr, L - 0.03), Vector2(rr * 1.12, L - 0.022), Vector2(rr * 1.12, L), Vector2(rr * 1.12, L), Vector2(0, L)],
		func(p: Vector3, _a: float, _t2: float) -> Color: return wood.darkened(0.12 * (Provisions._nz(p * Vector3(8.0, 0.3, 8.0), 60.0) + 0.3)), 18)
	for b: Array in [[0.006, 0.006, Color(0.12, 0.08, 0.05)], [0.016, 0.006, BRASS.darkened(0.25)], [L - 0.012, 0.006, Color(0.12, 0.08, 0.05)]]:
		var m := "im:metal@0.4" if (b[2] as Color).r > 0.3 else "own:wood"
		k.cylinder(m, _at(0, float(b[0]) - float(b[1]) * 0.5, 0), rr * 1.14, rr * 1.14, float(b[1]), 18, false, 0.0, 1, b[2])
	ItemModels._disc(k, "own:wood", Transform3D.IDENTITY, Vector3(0, L + 0.0003, 0), Vector3.UP, rr * 0.6, 12, Color(0.08, 0.05, 0.03))
	ItemModels._disc(k, "own:wood", Transform3D.IDENTITY, Vector3(0, -0.0003, 0), Vector3.DOWN, rr * 0.6, 12, Color(0.08, 0.05, 0.03))
	for i in 7:
		var y := 0.08 + i * 0.03 if i < 6 else 0.3
		var hr := 0.0045 if i < 6 else 0.0055
		ItemModels._disc(k, "own:wood", Transform3D.IDENTITY, Vector3(0, y, rr * 0.985 + 0.0004), Vector3.BACK, hr, 10, Color(0.08, 0.05, 0.03))
	return Vector3(0, 0.14, 0)

## A banjo: a round drum with a pale skin head held by a metal hoop and a ring of
## brackets round its wooden shell, a long dark neck with frets, a headstock with four
## ivory pegs and the fifth-string peg on the neck, five strings over the bridge.
static func _banjo(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var wood := Color(0.45, 0.24, 0.11)
	var dark := Color(0.24, 0.12, 0.06)
	var metal := Color(0.72, 0.66, 0.52)
	var pc := Vector3(0, -0.27, 0)
	k.cylinder("own:wood", Transform3D(FRONT, pc + Vector3(0, 0, -0.06)), 0.138, 0.138, 0.064, 40, false, 0.0, 1, wood)
	ItemModels._disc(k, "own:wood", Transform3D.IDENTITY, pc + Vector3(0, 0, -0.06), Vector3.FORWARD, 0.138, 40, wood.darkened(0.2))
	ItemModels._disc(k, "own:paper", Transform3D.IDENTITY, pc + Vector3(0, 0, 0.0065), Vector3.BACK, 0.134, 40, Color(0.9, 0.86, 0.76))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(FRONT, pc + Vector3(0, 0, 0.006)), 0.138, 0.0055, 48, 6, metal)
	ItemModels._torus(k, "im:metal@0.3", Transform3D(FRONT, pc + Vector3(0, 0, -0.045)), 0.14, 0.003, 48, 4, metal.darkened(0.15))
	for i in 24:
		var a := TAU * i / 24.0
		var d := Vector3(cos(a), sin(a), 0)
		k.box("im:metal@0.35", Transform3D(Basis(Vector3.BACK, a), pc + d * 0.142 + Vector3(0, 0, -0.018)), Vector3(0.006, 0.006, 0.042), metal.darkened(0.1))
	# Bridge and tailpiece on the head.
	k.box("own:wood", _at(0, -0.31, 0.01), Vector3(0.05, 0.004, 0.008), Color(0.8, 0.66, 0.45))
	k.box("im:metal@0.35", _at(0, -0.392, 0.012), Vector3(0.03, 0.03, 0.006), metal)
	# Neck, fingerboard, frets.
	k.bevel_box("own:wood", _at(0, 0.12, -0.012), Vector3(0.04, 0.52, 0.024), 0.008, wood.darkened(0.1))
	k.box("own:wood", _at(0, 0.12, 0.003), Vector3(0.042, 0.52, 0.006), dark.darkened(0.3))
	for i in 16:
		var y := 0.37 - 0.42 * (1.0 - pow(0.94, i * 1.6))
		k.box("im:metal@0.3", _at(0, y, 0.0065), Vector3(0.042, 0.0012, 0.0012), metal.lightened(0.2))
	# Headstock and pegs.
	k.bevel_box("own:wood", _at(0, 0.43, -0.004), Vector3(0.062, 0.12, 0.016), 0.01, wood)
	for p: Vector2 in [Vector2(-1, 0.41), Vector2(-1, 0.46), Vector2(1, 0.41), Vector2(1, 0.46)]:
		k.cylinder("im:metal@0.35", Transform3D(Basis(Vector3.BACK, -PI * 0.5 * p.x), Vector3(p.x * 0.028, p.y, -0.004)), 0.003, 0.003, 0.016, 6, true, 0.0, 1, metal)
		k.sphere("own:ivory", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.6)), Vector3(p.x * 0.05, p.y, -0.004)), 0.008, 6, 10, 0.0, 1.0, Color(0.92, 0.88, 0.78))
	k.cylinder("im:metal@0.35", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.018, 0.12, -0.006)), 0.0025, 0.0025, 0.014, 6, true, 0.0, 1, metal)
	k.sphere("own:ivory", _at(-0.034, 0.12, -0.006), 0.006, 5, 8, 0.0, 1.0, Color(0.92, 0.88, 0.78))
	for i in 5:
		var x0 := lerpf(-0.012, 0.012, i / 4.0)
		var top := 0.375 if i > 0 else 0.12
		ItemModels._tube(k, "im:metal@0.25", Transform3D.IDENTITY, PackedVector3Array([Vector3(x0, -0.38, 0.0155), Vector3(lerpf(-0.015, 0.015, i / 4.0), top, 0.0085)]), PackedFloat32Array([0.0005, 0.0005]), 3, Color(0.85, 0.85, 0.85), false)
	return Vector3(0, 0.1, 0)

## A deck of cards: the squared deck lying back-up (a dark patterned back in a cream
## border, the cream edges of the cards), and a hand fanned out behind it showing spades.
static func _cards(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var W := 0.063
	var H := 0.088
	var cream := Color(0.74, 0.66, 0.5)
	var navy := Color(0.15, 0.16, 0.19)
	var tilt := Basis(Vector3.RIGHT, -0.25)
	# The fan: five cards round a pivot at their foot, each a little behind the last.
	for i in 5:
		var a := lerpf(0.15, -0.75, i / 4.0)
		var xf := Transform3D(tilt * Basis(Vector3.BACK, a), Vector3(0.012, 0.004, -0.012 - i * 0.0015)) * _at(0, H * 0.5, 0)
		k.box("own:paper", xf, Vector3(W, H, 0.0006), cream)
		var pip := Color(0.06, 0.06, 0.07)
		for q: Vector3 in [Vector3(0.0, 0.0, 1.0), Vector3(W * 0.36, H * 0.4, 0.35), Vector3(W * 0.2, -H * 0.25, 0.6), Vector3(-W * 0.2, H * 0.25, 0.6)]:
			# A spade: a point and two lobes over a little stem.
			var sz := 0.009 * q.z
			var c := Vector3(q.x, q.y, 0.0004)
			k.sphere("own:paper", xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.1)), c + Vector3(-sz * 0.35, 0, 0)), sz * 0.42, 4, 8, 0.0, 1.0, pip)
			k.sphere("own:paper", xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.1)), c + Vector3(sz * 0.35, 0, 0)), sz * 0.42, 4, 8, 0.0, 1.0, pip)
			ItemModels._tri(k, "own:paper", xf, c + Vector3(-sz * 0.75, -sz * 0.05, 0.0002), c + Vector3(sz * 0.75, -sz * 0.05, 0.0002), c + Vector3(0, sz * 0.9, 0.0002), Vector3.BACK, Vector3.BACK, Vector3.BACK, pip)
			k.box("own:paper", xf * Transform3D(Basis.IDENTITY, c + Vector3(0, -sz * 0.5, 0)), Vector3(sz * 0.18, sz * 0.6, 0.0005), pip)
	# The deck in front: cream block, the patterned back on top.
	var deck := Transform3D(tilt * Basis(Vector3.BACK, 0.12), Vector3(-0.022, 0.0, 0.01)) * _at(0, H * 0.5, 0)
	k.bevel_box("own:paper", deck * _at(0, 0, -0.008), Vector3(W, H, 0.016), 0.002, cream.darkened(0.1))
	for i in 7:
		k.box("own:paper", deck * _at(W * 0.5 + 0.0002, 0, -0.015 + i * 0.002), Vector3(0.0004, H * 0.97, 0.0004), cream.darkened(0.3))
	k.box("own:paper", deck * _at(0, 0, 0.0002), Vector3(W * 0.98, H * 0.98, 0.0008), cream)
	Provisions.sheet(k, "own:paper", deck, 22, 30, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * W * 0.84, (v - 0.5) * H * 0.88, 0.0008),
		func(_p: Vector3, u: float, v: float) -> Color:
			var d := absf(sin(u * 18.0 + v * 26.0)) * absf(sin(u * 18.0 - v * 26.0))
			return navy.lerp(Color(0.42, 0.44, 0.48), 0.5 * d), Vector3.BACK)
	return Vector3(0, 0.04, 0)

## A harmonica: polished nickel cover plates top and bottom over a wooden comb whose ten
## square holes line the front, brass end plates.
static func _harmonica(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var nickel := Color(0.4, 0.4, 0.42)
	var comb := Color(0.4, 0.22, 0.1)
	var L := 0.102
	k.box("own:wood", _at(0, 0, 0), Vector3(L * 0.96, 0.011, 0.026), comb)
	for s: float in [-1.0, 1.0]:
		Provisions.rounded_box(k, "own:paint", Transform3D(Basis.from_scale(Vector3(1.0, s, 1.0)), Vector3(0, s * 0.0055, 0)), Vector3(L, 0.0065, 0.028), 0.003, nickel, 10.0)
		k.box("im:metal@0.35", _at(s * L * 0.49, 0, 0), Vector3(0.003, 0.019, 0.029), BRASS)
	for i in 10:
		k.box("own:wood", _at(lerpf(-0.04, 0.04, i / 9.0), 0, 0.01305), Vector3(0.005, 0.006, 0.0005), Color(0.04, 0.03, 0.02))
	for x: float in [-0.044, 0.044]:
		for s: float in [-1.0, 1.0]:
			k.sphere("im:metal@0.3", _at(x, s * 0.012, 0.008), 0.0012, 4, 6, 0.0, 1.0, nickel.darkened(0.2))
	return Vector3(0, 0, 0)

## A travel chess set: a leather case open on its hinge, the lid's lining showing, the
## inlaid board of light and dark squares with pieces standing on it and two more beside
## the case; brass clasps and corners.
static func _chess_set(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var leather := Color(0.33, 0.18, 0.09)
	var light := Color(0.86, 0.72, 0.5)
	var dk := Color(0.3, 0.17, 0.09)
	var W := 0.21
	var D := 0.18
	k.bevel_box("own:leather", _at(0, 0.02, 0), Vector3(W, 0.04, D), 0.006, leather)
	k.box("own:wood", _at(0, 0.0405, 0), Vector3(W - 0.02, 0.001, D - 0.02), dk.darkened(0.2))
	var tile := 0.02
	for i in 8:
		for j in 8:
			k.box("own:wood", _at((i - 3.5) * tile, 0.041, (j - 3.5) * tile), Vector3(tile, 0.0012, tile), light if (i + j) % 2 == 0 else dk)
	# The lid, hinged at the back and fallen open past upright.
	var lid := Transform3D(Basis(Vector3.RIGHT, -1.95), Vector3(0, 0.04, -D * 0.5))
	k.bevel_box("own:leather", lid * _at(0, 0.015, D * 0.5), Vector3(W, 0.03, D), 0.006, leather)
	k.box("own:leather", lid * _at(0, -0.0005, D * 0.5), Vector3(W - 0.016, 0.001, D - 0.016), leather.darkened(0.45))
	for x: float in [-0.06, 0.06]:
		k.box("im:metal@0.35", _at(x, 0.03, D * 0.5 + 0.002), Vector3(0.016, 0.02, 0.004), BRASS)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			k.box("im:metal@0.35", _at(x * (W * 0.5 - 0.004), 0.02, z * (D * 0.5 - 0.004)), Vector3(0.011, 0.042, 0.011), BRASS.darkened(0.1))
	var pieces := [["pawn", 0, 1, light], ["pawn", 2, 2, light], ["king", 3, 4, light], ["pawn", 5, 3, light], ["pawn", 1, 5, dk], ["king", 4, 6, dk], ["pawn", 6, 5, dk], ["pawn", 3, 6, dk]]
	for p: Array in pieces:
		_chessman(k, _at((int(p[1]) - 3.5) * tile, 0.042, (3.5 - int(p[2])) * tile * -1.0), String(p[0]), 1.25, p[3])
	_chessman(k, _at(0.07, 0, D * 0.5 + 0.035), "king", 1.5, light)
	_chessman(k, _at(0.105, 0, D * 0.5 + 0.025), "pawn", 1.5, dk)
	return Vector3(0, 0.02, 0)

## A turned chessman standing on y = 0: a pawn's ball or a king's tall body and cross.
static func _chessman(k: MeshKit, xf: Transform3D, kind: String, s: float, col: Color) -> void:
	var pts: Array
	if kind == "pawn":
		pts = [Vector2(0, 0), Vector2(0.008, 0), Vector2(0.008, 0.003), Vector2(0.006, 0.005), Vector2(0.0035, 0.013), Vector2(0.0055, 0.015), Vector2(0.003, 0.017),
			Vector2(0.0048, 0.019), Vector2(0.005, 0.022), Vector2(0.003, 0.026), Vector2(0, 0.027)]
	else:
		pts = [Vector2(0, 0), Vector2(0.01, 0), Vector2(0.01, 0.004), Vector2(0.007, 0.007), Vector2(0.0045, 0.025), Vector2(0.0075, 0.028), Vector2(0.004, 0.03),
			Vector2(0.0065, 0.038), Vector2(0.004, 0.041), Vector2(0, 0.042)]
	_lathe(k, "own:wood", xf * Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO), pts, col, 16, null, 2)
	if kind == "king":
		k.box("own:wood", xf * _at(0, 0.046 * s, 0), Vector3(0.0025, 0.009, 0.0025) * s, col)
		k.box("own:wood", xf * _at(0, 0.047 * s, 0), Vector3(0.007, 0.0025, 0.0025) * s, col)

# --- Paper -------------------------------------------------------------------------------

## A rolled scroll along +Y: a roll of mottled parchment flared at the ends to show the
## spiral of its sheets, the outer edge lying along it, tied with a cord (or, for the
## land deed, a red ribbon bow), and sealed with coloured wax stamped with a device.
static func _scroll(k: MeshKit, r: RandomNumberGenerator, t: String):
	var L := 0.24
	var R := 0.035
	var paper := PARCH
	var deed := t == "deed_scroll" or t == "writ"
	# Tipped so the open lower end, with its spiral, turns toward the viewer.
	var W := Transform3D.IDENTITY
	var fl := 1.22 if deed else 1.14
	_lathe(k, "own:paper", W, [Vector2(R * fl, -L * 0.5), Vector2(R * 1.03, -L * 0.5 + 0.022), Vector2(R, -L * 0.3), Vector2(R, L * 0.3), Vector2(R * 1.02, L * 0.5 - 0.018), Vector2(R * 1.08, L * 0.5)],
		_mottle(paper, 90.0, 0.14), 32, func(a: float, _t2: float, p: Vector3) -> float: return 1.0 + (0.06 if deed else 0.03) * Provisions._nz(p * Vector3(1.0, 0.3, 1.0), 60.0))
	_spiral(k, "own:paper", W, R * fl * 0.97, -L * 0.5, -1.0, paper.darkened(0.4), paper.darkened(0.15), 5, 0.0011)
	_spiral(k, "own:paper", W, R * 1.05, L * 0.5, 1.0, paper.darkened(0.4), paper.darkened(0.15), 5, 0.0011)
	# The outer sheet's free edge, lying along the roll.
	var ea := -0.5
	k.box("own:paper", W * Transform3D(Basis(Vector3.UP, -ea), Vector3(cos(ea) * R * 1.02, 0, -sin(ea) * R * 1.02)), Vector3(0.0022, L * 0.9, 0.005), paper.darkened(0.3))
	if deed:
		# A red silk ribbon round the middle, tied in a bow with long trailing ends.
		var red := Color(0.58, 0.08, 0.06)
		k.cylinder("own:satin", W * _at(0, 0.002, 0), R * 1.06, R * 1.06, 0.02, 32, false, 0.0, 1, red)
		for s: float in [-1.0, 1.0]:
			ItemModels._torus(k, "own:satin", W * Transform3D(Basis(Vector3.BACK, s * 0.6) * Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 0.4, 1.0)), Vector3(s * 0.017, 0.018, R + 0.008)), 0.016, 0.005, 16, 5, red.lightened(0.05))
			ItemModels._tube(k, "own:satin", W, PackedVector3Array([Vector3(0, 0.012, R + 0.007), Vector3(s * 0.006 + 0.004, -0.006, R + 0.016), Vector3(s * 0.012 + 0.024, -0.03, R + 0.012), Vector3(s * 0.01 + 0.046, -0.05, R + 0.004)]),
				PackedFloat32Array([0.0045, 0.005, 0.005, 0.0045]), 6, red)
		if t == "writ":
			# A writ of passage is sealed over the knot with the town's red wax.
			_seal(k, W * Transform3D(FRONT, Vector3(0, 0.012, R + 0.012)), 0.028, Color(0.62, 0.05, 0.05), "lion")
		else:
			k.sphere("own:satin", W * _at(0, 0.013, R + 0.008), 0.0075, 6, 8, 0.1, 1.0, red.darkened(0.1))
		return Vector3.ZERO
	# The cord: two turns round the middle, the loose ends hanging.
	var cord := Color(0.42, 0.28, 0.16)
	for y: float in [0.003, 0.011]:
		ItemModels._torus(k, "im:rope", W * _at(0, y, 0), R * 1.02 + 0.0024, 0.0025, 28, 5, cord)
	for e: float in [0.0, 1.0]:
		ItemModels._tube(k, "im:rope", W, PackedVector3Array([Vector3(0.006, 0.007, R + 0.003), Vector3(0.014 + e * 0.006, -0.006, R + 0.01), Vector3(0.026 + e * 0.012, -0.024, R + 0.008), Vector3(0.042 + e * 0.014, -0.036 - e * 0.01, R + 0.002)]),
			PackedFloat32Array([0.0025, 0.0025, 0.0025, 0.0022]), 5, cord)
	var seals := {"scroll_red": [Color(0.62, 0.05, 0.05), "lion"], "scroll_blue": [Color(0.07, 0.2, 0.55), "knot"], "scroll_green": [Color(0.12, 0.4, 0.1), "tree"]}
	if seals.has(t):
		_seal(k, W * Transform3D(FRONT, Vector3(0, 0.007, R + 0.003)), 0.027, seals[t][0], seals[t][1])
	return Vector3.ZERO

## A sealed letter: a folded envelope of cream paper, its flap a triangle down to the
## middle with the fold lines of the sides beneath, closed with a red wax seal.
static func _letter(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var W := 0.16
	var H := 0.105
	var paper := Color(0.78, 0.6, 0.38)
	var xf := Transform3D(Basis(Vector3.RIGHT, -0.35) * Basis(Vector3.BACK, -0.08), Vector3(0, H * 0.5, 0))
	Provisions.sheet(k, "own:paper", xf, 16, 12, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * W, (v - 0.5) * H, 0.0025 + 0.0012 * Provisions._nz(Vector3(u, v, 0), 5.0)), _mottle(paper, 60.0, 0.1), Vector3.BACK)
	Provisions.sheet(k, "own:paper", xf, 4, 4, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * W, (v - 0.5) * H, -0.0025), paper.darkened(0.1), Vector3.FORWARD)
	for e: Array in [[Vector2(-0.5, 0.5), Vector2(0.5, 0.5)], [Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		k.box("own:paper", xf * _at(0, a.y * H, 0), Vector3(W, 0.0015, 0.005), paper.darkened(0.15))
	for s: float in [-0.5, 0.5]:
		k.box("own:paper", xf * _at(s * W, 0, 0), Vector3(0.0015, H, 0.005), paper.darkened(0.15))
	# The flap and the side folds.
	var tip := Vector2(0, -0.012)
	for f: Array in [[Vector2(-W * 0.5, H * 0.5), tip, 0.004], [Vector2(W * 0.5, H * 0.5), tip, 0.004], [Vector2(-W * 0.5, -H * 0.5), Vector2(-0.01, 0.0), 0.0034], [Vector2(W * 0.5, -H * 0.5), Vector2(0.01, 0.0), 0.0034]]:
		_stroke(k, "own:paper", xf, f[0], f[1], 0.0016, 0.0008, float(f[2]), paper.darkened(0.3))
	ItemModels._tri(k, "own:paper", xf, Vector3(-W * 0.5, H * 0.5, 0.0036), Vector3(W * 0.5, H * 0.5, 0.0036), Vector3(tip.x, tip.y, 0.0036), Vector3.BACK, Vector3.BACK, Vector3.BACK, paper.lightened(0.04))
	_seal(k, xf * Transform3D(FRONT, Vector3(0, -0.008, 0.0038)), 0.02, Color(0.62, 0.05, 0.05), "lion")
	return Vector3(0, H * 0.5, 0)

## A treasure map: a ragged sheet of old parchment, browned and burnt at the edges, a
## grey-green island painted on it, a dashed trail across it to a red cross.
static func _treasure_map(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var W := 0.3
	var H := 0.27
	var xf := Transform3D(Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.BACK, -0.06), Vector3(0, H * 0.5, 0))
	var surf := func(u: float, v: float) -> Vector3:
		var p := Vector3((u - 0.5) * W, (v - 0.5) * H, 0.0)
		if u <= 0.0 or u >= 1.0:
			p.x -= signf(u - 0.5) * (0.006 + 0.006 * Provisions._nz(Vector3(v * 9.0, u, 1.0), 2.0))
		if v <= 0.0 or v >= 1.0:
			p.y -= signf(v - 0.5) * (0.006 + 0.006 * Provisions._nz(Vector3(u * 9.0, v, 2.0), 2.0))
		p.z = 0.004 * sin(u * 7.0) * sin(v * 5.0 + 1.0) + 0.002 * Provisions._nz(Vector3(u, v, 0), 4.0) - 0.003 * absf(u - 0.5) * 0.0
		return p
	var land := func(u: float, v: float) -> float:
		var d := Vector2((u - 0.48) / 0.36, (v - 0.52) / 0.33).length()
		return 1.0 - d + 0.35 * Provisions._nz(Vector3(u * 3.0, v * 3.0, 0.5), 1.6)
	var paper := Color(0.72, 0.52, 0.3)
	var sea := Color(0.58, 0.58, 0.44)
	Provisions.sheet(k, "own:paper", xf, 60, 54, surf, func(p: Vector3, u: float, v: float) -> Color:
		var e := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
		var l: float = land.call(u, v)
		var c := paper
		if l > 0.0:
			c = sea.lerp(Color(0.66, 0.62, 0.46), clampf(l * 3.0 - 0.3, 0.0, 0.7))
		elif l > -0.05:
			c = paper.lightened(0.15)
		if absf(u - 0.5) < 0.012 or absf(v - 0.5) < 0.012:
			c = c.darkened(0.12)
		c = c.darkened(0.08 * (Provisions._nz(p, 60.0) + 0.3))
		return c.darkened(0.12 * (1.0 - smoothstep(0.0, 0.25, e)) + 0.55 * (1.0 - smoothstep(0.0, 0.06, e))), Vector3.BACK)
	Provisions.sheet(k, "own:paper", xf * _at(0, 0, -0.0012), 30, 27, surf, paper.darkened(0.2), Vector3.FORWARD)
	# The trail, dash by dash, to the cross.
	var ink := Color(0.12, 0.08, 0.05)
	var trail := func(s: float) -> Vector2: return Vector2(lerpf(0.3, 0.72, s), 0.5 - 0.12 * s + 0.08 * sin(s * 6.0))
	for i in 14:
		var a: Vector2 = trail.call(i / 14.0)
		var b: Vector2 = trail.call((i + 0.5) / 14.0)
		var za: Vector3 = surf.call(a.x, a.y)
		_stroke(k, "own:paper", xf, Vector2(za.x, za.y), Vector2((b.x - 0.5) * W, (b.y - 0.5) * H), 0.0028, 0.0008, za.z + 0.0006, ink)
	var x: Vector3 = surf.call(0.76, 0.38)
	for s: float in [-1.0, 1.0]:
		_stroke(k, "own:paper", xf, Vector2(x.x - 0.009, x.y - 0.009 * s), Vector2(x.x + 0.009, x.y + 0.009 * s), 0.0035, 0.0008, x.z + 0.0007, Color(0.6, 0.1, 0.06))
	return Vector3(0, H * 0.5, 0)

## An old book: boards covered in worn brown leather with a tooled border, a rounded
## spine with raised bands, and the cream block of pages showing at the edges.
static func _book(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var W := 0.18
	var H := 0.24
	var T := 0.055
	var lea := Color(0.36, 0.19, 0.09)
	# Turned so the spine with its bands shows beside the cover, as in the icon.
	var Y := Transform3D(Basis(Vector3.UP, 0.7), Vector3.ZERO)
	var bt := 0.005
	for s: float in [-1.0, 1.0]:
		k.bevel_box("own:leather", Y * _at(0.002, 0, s * (T * 0.5 - bt * 0.5)), Vector3(W, H, bt), 0.002, lea.darkened(0.05 if s > 0 else 0.15))
	k.cylinder("own:leather", Y * Transform3D(Basis.from_scale(Vector3(0.45, 1.0, 1.0)), Vector3(-W * 0.5 + 0.004, -H * 0.5, 0)), T * 0.5, T * 0.5, H, 20, true, 0.0, 1, lea.darkened(0.1))
	for y: float in [-0.075, -0.025, 0.025, 0.075]:
		k.cylinder("own:leather", Y * Transform3D(Basis.from_scale(Vector3(0.5, 1.0, 1.0)), Vector3(-W * 0.5 + 0.004, y - 0.004, 0)), T * 0.5 + 0.003, T * 0.5 + 0.003, 0.008, 20, true, 0.0, 1, lea.darkened(0.2))
		k.box("own:leather", Y * _at(-W * 0.5 + 0.02, y, T * 0.5 + 0.0005), Vector3(0.022, 0.007, 0.002), lea.darkened(0.12))
	k.box("own:paper", Y * _at(0.0, 0, 0), Vector3(W - 0.01, H - 0.012, T - bt * 2.0 + 0.0004), Color(0.9, 0.83, 0.66))
	for i in 6:
		var z := lerpf(-T * 0.35, T * 0.35, i / 5.0)
		k.box("own:paper", Y * _at(W * 0.5 - 0.005 + 0.0002, 0, z), Vector3(0.0004, H - 0.016, 0.0005), Color(0.72, 0.62, 0.45))
	# The tooled border on the front board.
	var b := lea.lightened(0.08)
	var z0 := T * 0.5 + 0.0004
	for s: float in [-1.0, 1.0]:
		k.box("own:leather", Y * _at(0.01, s * (H * 0.5 - 0.016), z0), Vector3(W - 0.05, 0.003, 0.001), b)
		k.box("own:leather", Y * _at(0.01 + s * (W * 0.5 - 0.025), 0, z0), Vector3(0.003, H - 0.032, 0.001), b)
	return Vector3(-W * 0.3, 0, 0)

# --- Frontier ----------------------------------------------------------------------------

## A brass sextant: the frame of struts down to the graduated arc, the index arm swung
## across it from the pivot, the mirror and horizon glass, the telescope across the
## front and the wooden handle behind.
static func _sextant(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.35"
	var piv := Vector3(0, 0.1, 0)
	var arc_r := 0.17
	var arc := func(phi: float, rr: float) -> Vector3: return piv + Vector3(sin(phi) * rr, -cos(phi) * rr, 0)
	var n := 16
	for i in n:
		var p0: Vector3 = arc.call(lerpf(-0.62, 0.62, float(i) / n), arc_r)
		var p1: Vector3 = arc.call(lerpf(-0.62, 0.62, float(i + 1) / n), arc_r)
		var c := (p0 + p1) * 0.5
		k.box(m, Transform3D(Basis(Vector3.BACK, atan2(p1.y - p0.y, p1.x - p0.x)), c), Vector3(p0.distance_to(p1) * 1.04, 0.022, 0.005), BRASS)
	for i in 25:
		var phi := lerpf(-0.58, 0.58, i / 24.0)
		var a: Vector3 = arc.call(phi, arc_r - 0.009)
		var b: Vector3 = arc.call(phi, arc_r - (0.003 if i % 5 else 0.0))
		_stroke(k, m, Transform3D.IDENTITY, Vector2(a.x, a.y), Vector2(b.x, b.y), 0.0012, 0.001, 0.003, BRASS.lightened(0.3))
	for phi: float in [-0.6, 0.6]:
		var e: Vector3 = arc.call(phi, arc_r - 0.01)
		_stroke(k, m, Transform3D.IDENTITY, Vector2(piv.x, piv.y), Vector2(e.x, e.y), 0.016, 0.006, 0.0, BRASS.darkened(0.08))
	var ma: Vector3 = arc.call(-0.3, arc_r * 0.55)
	var mb: Vector3 = arc.call(0.3, arc_r * 0.55)
	_stroke(k, m, Transform3D.IDENTITY, Vector2(ma.x, ma.y), Vector2(mb.x, mb.y), 0.01, 0.005, 0.0, BRASS.darkened(0.08))
	# Index arm with its vernier at the arc.
	var ie: Vector3 = arc.call(0.15, arc_r + 0.008)
	_stroke(k, m, Transform3D.IDENTITY, Vector2(piv.x, piv.y), Vector2(ie.x, ie.y), 0.01, 0.004, 0.006, BRASS.lightened(0.05))
	k.box(m, Transform3D(Basis(Vector3.BACK, 0.15), ie + Vector3(0, 0.004, 0.008)), Vector3(0.026, 0.014, 0.005), BRASS)
	k.cylinder(m, _at(piv.x, piv.y, -0.004), 0.01, 0.01, 0.016, 14, true, 0.0, 1, BRASS.darkened(0.1))
	k.cylinder(m, Transform3D(FRONT, piv + Vector3(0, 0, -0.004)), 0.012, 0.012, 0.014, 16, true, 0.0, 1, BRASS)
	# The index mirror over the pivot and the horizon glass in its ring.
	k.box(m, _at(0.0, 0.122, 0.012), Vector3(0.024, 0.03, 0.004), BRASS.darkened(0.1))
	k.box("own:screen", _at(0.0, 0.122, 0.0145), Vector3(0.02, 0.026, 0.001), Color(0.55, 0.62, 0.66))
	ItemModels._torus(k, m, _at(-0.05, 0.095, 0.01, FRONT), 0.013, 0.0028, 20, 5, BRASS)
	ItemModels._disc(k, "own:screen", Transform3D.IDENTITY, Vector3(-0.05, 0.095, 0.01), Vector3.BACK, 0.012, 16, Color(0.6, 0.7, 0.72))
	k.box(m, _at(-0.05, 0.075, 0.006), Vector3(0.006, 0.02, 0.006), BRASS)
	# The telescope across the front.
	var tel := Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-0.02, 0.055, 0.024))
	k.cylinder(m, tel, 0.011, 0.011, 0.1, 16, true, 0.0, 1, BRASS)
	k.cylinder(m, tel * _at(0, 0.072, 0), 0.0145, 0.0145, 0.036, 16, true, 0.0, 1, BRASS.lightened(0.05))
	k.cylinder(m, tel * _at(0, -0.01, 0), 0.007, 0.007, 0.012, 12, true, 0.0, 1, BRASS.darkened(0.15))
	for y: float in [0.02, 0.07]:
		ItemModels._torus(k, m, tel * _at(0, y, 0), 0.0095, 0.0018, 16, 4, BRASS.darkened(0.1))
	k.box(m, _at(0.01, 0.055, 0.012), Vector3(0.008, 0.012, 0.02), BRASS)
	# The handle behind.
	k.cylinder("own:wood", _at(0.02, 0.0, -0.03), 0.008, 0.008, 0.07, 12, true, 0.0, 1, Color(0.3, 0.16, 0.08))
	for y: float in [0.0, 0.07]:
		k.box(m, _at(0.02, y, -0.014), Vector3(0.008, 0.006, 0.03), BRASS)
	return Vector3(0.02, 0.035, -0.03)

## A box camera: a mahogany body with brass corner plates at the back, black pleated
## bellows reaching forward to the front standard on its rails, and a brass lens with
## its glass at the front.
static func _camera_box(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var B := Transform3D(Basis(Vector3.UP, 0.9), Vector3.ZERO)
	var wood := Color(0.45, 0.2, 0.1)
	var m := "im:metal@0.35"
	k.bevel_box("own:wood", B * _at(0, 0.085, -0.085), Vector3(0.17, 0.17, 0.06), 0.006, wood)
	k.bevel_box("own:wood", B * _at(0, 0.085, -0.05), Vector3(0.15, 0.15, 0.012), 0.004, wood.darkened(0.12))
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			k.box(m, B * _at(x * 0.08, 0.085 + y * 0.08, -0.084), Vector3(0.014, 0.014, 0.064), BRASS.darkened(0.1))
	k.box(m, B * _at(0.087, 0.085, -0.085), Vector3(0.003, 0.11, 0.008), BRASS)
	# The bellows: square frames, alternately wide and narrow, from back to front.
	var rings: Array = []
	for i in 15:
		var t := i / 14.0
		var s := lerpf(0.066, 0.052, t) * (1.0 if i % 2 == 0 else 0.9)
		rings.append(ItemModels._rect(s, s, -0.044 + t * 0.09, 0.002))
	ItemModels._loft(k, "own:leather", B * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.085, 0)), rings, Color(0.07, 0.07, 0.08))
	# The front standard on the bed.
	k.box("own:wood", B * _at(0, 0.006, 0.0), Vector3(0.13, 0.012, 0.13), wood.darkened(0.1))
	for x: float in [-0.05, 0.05]:
		k.box(m, B * _at(x, 0.0135, 0.0), Vector3(0.006, 0.003, 0.13), BRASS)
	k.bevel_box("own:wood", B * _at(0, 0.075, 0.055), Vector3(0.12, 0.13, 0.014), 0.004, wood)
	for x: float in [-0.055, 0.055]:
		k.box(m, B * _at(x, 0.04, 0.055), Vector3(0.006, 0.06, 0.016), BRASS)
	# The lens.
	var lens := B * Transform3D(FRONT, Vector3(0, 0.08, 0.06))
	Provisions.lathe(k, m, lens, Provisions._curve([Vector2(0.034, 0), Vector2(0.034, 0.008), Vector2(0.027, 0.012), Vector2(0.027, 0.034), Vector2(0.031, 0.038), Vector2(0.031, 0.046), Vector2(0.025, 0.046), Vector2(0.022, 0.04)], 1), 28, BRASS)
	ItemModels._torus(k, m, lens * _at(0, 0.02, 0), 0.028, 0.0025, 24, 4, BRASS.darkened(0.15))
	Provisions.lathe(k, "own:screen", lens, PackedVector2Array([Vector2(0.022, 0.04), Vector2(0.012, 0.043), Vector2(0, 0.044)]), 24, Color(0.18, 0.2, 0.22))
	return Vector3(0, 0.05, -0.05)

## A telegraph key: a polished wooden base with brass binding posts, the brass lever on
## its pivot between two pillars, the spring and adjusting screw behind and a round
## knob at the front end.
static func _telegraph_key(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.3"
	var wood := Color(0.28, 0.13, 0.06)
	k.bevel_box("own:wood_dull", _at(0, 0.014, 0), Vector3(0.16, 0.03, 0.08), 0.004, wood)
	k.box(m, _at(-0.005, 0.03, 0), Vector3(0.11, 0.004, 0.02), BRASS.darkened(0.1))
	for z: float in [-0.014, 0.014]:
		k.box(m, _at(-0.012, 0.04, z), Vector3(0.012, 0.018, 0.006), BRASS)
		k.cylinder(m, Transform3D(FRONT, Vector3(-0.012, 0.046, z - 0.004)), 0.004, 0.004, 0.008, 10, true, 0.0, 1, BRASS.lightened(0.05))
	# The lever, its knob, the screw and spring.
	k.box(m, Transform3D(Basis(Vector3.BACK, -0.04), Vector3(0.012, 0.05, 0)), Vector3(0.1, 0.008, 0.012), BRASS)
	k.cylinder(m, _at(0.058, 0.044, 0), 0.0035, 0.0035, 0.016, 8, true, 0.0, 1, BRASS)
	_lathe(k, m, _at(0.058, 0.058, 0), [Vector2(0, 0), Vector2(0.013, 0), Vector2(0.014, 0.004), Vector2(0.013, 0.009), Vector2(0, 0.011)], BRASS.lightened(0.05), 20, null, 2)
	for x: float in [-0.045, 0.025]:
		k.cylinder(m, _at(x, 0.03, 0), 0.0035, 0.0035, 0.032, 8, true, 0.0, 1, BRASS)
		k.cylinder(m, _at(x, 0.056, 0), 0.007, 0.007, 0.008, 14, true, 0.0, 1, BRASS.lightened(0.1))
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for s in 40:
		var a := s / 39.0 * TAU * 6.0
		path.append(Vector3(0.01 + cos(a) * 0.004, 0.032 + s / 39.0 * 0.014, sin(a) * 0.004))
		radii.append(0.0008)
	ItemModels._tube(k, m, Transform3D.IDENTITY, path, radii, 4, BRASS.darkened(0.2))
	for p: Vector2 in [Vector2(-0.065, -0.024), Vector2(-0.065, 0.024), Vector2(0.066, 0.025)]:
		k.cylinder(m, _at(p.x, 0.028, p.y), 0.0055, 0.0055, 0.012, 12, true, 0.0, 1, BRASS)
		k.cylinder(m, _at(p.x, 0.04, p.y), 0.008, 0.008, 0.006, 14, true, 0.0, 1, BRASS.lightened(0.1))
	return Vector3(0, 0.014, 0)

## A shellac record: a thin glossy black disc, its grooves rings of faint sheen, a red
## paper label with a darker ring and the spindle hole.
static func _record(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.125
	var th := 0.0018
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var steps := 60
	for i in steps + 1:
		var rr := lerpf(0.0036, R, float(i) / steps)
		top.append(Vector2(rr, th))
	var prof := PackedVector2Array([Vector2(0.0036, 0.0)])
	var rim := PackedVector2Array([Vector2(R, 0.0), Vector2(R + 0.0006, th * 0.5), Vector2(R, th)])
	prof.append_array(rim)
	top.reverse()
	prof.append_array(top)
	prof.append(Vector2(0.0036, 0.0))
	var col := func(p: Vector3, _a: float, _t: float) -> Color:
		var rr := Vector2(p.x, p.z).length()
		if rr < 0.045:
			var c := Color(0.48, 0.15, 0.11)
			if rr > 0.04 or (rr > 0.012 and rr < 0.014):
				c = c.darkened(0.35)
			return c
		if rr < 0.05 or rr > R - 0.004:
			return Color(0.03, 0.03, 0.03)
		return Color(0.035, 0.035, 0.037).lightened(0.05 * (0.5 + 0.5 * sin(rr * 1400.0)))
	Provisions.lathe(k, "own:vinyl", Transform3D(Basis(Vector3.UP, 0.42) * Basis(Vector3.RIGHT, -0.5) * FRONT, Vector3(0, R, 0)), prof, 64, col)
	return Vector3(0, R * 0.2, 0)

## The golden spike: a square shank of hammered gold tapering to a chisel point, with a
## heavy rounded head overhanging to one side.
static func _railway_spike(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.38"
	var g := Color(0.82, 0.52, 0.16)
	ItemModels._loft(k, m, Transform3D.IDENTITY, [ItemModels._rect(0.01, 0.0015, -0.075, 0.0008), ItemModels._rect(0.0135, 0.009, -0.045, 0.0025),
		ItemModels._rect(0.0145, 0.0145, 0.0, 0.003), ItemModels._rect(0.015, 0.015, 0.075, 0.0032)], g)
	k.sphere(m, Transform3D(Basis.from_scale(Vector3(1.4, 0.5, 1.0)), Vector3(0.009, 0.082, 0)), 0.026, 8, 14, 0.04, 1.0, g.lightened(0.05))
	k.bevel_box(m, _at(0.005, 0.077, 0), Vector3(0.044, 0.01, 0.034), 0.004, g)
	return Vector3(0, 0.0, 0)

## A cigar box: a dark mahogany box, its lid a shade proud of the sides, brass caps on
## every corner and a brass clasp at the front.
static func _cigar_box(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var wood := Color(0.32, 0.15, 0.07)
	var W := 0.2
	var D := 0.14
	k.bevel_box("own:wood", _at(0, 0.038, 0), Vector3(W, 0.076, D), 0.003, wood)
	k.bevel_box("own:wood", _at(0, 0.09, 0), Vector3(W + 0.004, 0.028, D + 0.004), 0.003, wood.lightened(0.05))
	k.box("own:wood", _at(0, 0.0765, 0), Vector3(W + 0.002, 0.002, D + 0.002), wood.darkened(0.4))
	# The figure of the mahogany: darker streaks along the boards.
	for i in 14:
		var y := 0.006 + i * 0.0052
		var x0 := r.randf_range(-0.1, -0.02)
		k.box("own:wood", _at(x0 + 0.05, y, D * 0.5 + 0.0004), Vector3(r.randf_range(0.06, 0.14), 0.0012, 0.0004), wood.darkened(r.randf_range(0.2, 0.4)))
	for i in 18:
		var z := lerpf(-D * 0.48, D * 0.48, i / 17.0) + r.randf_range(-0.002, 0.002)
		k.box("own:wood", _at(r.randf_range(-0.04, 0.04), 0.1042, z), Vector3(r.randf_range(0.08, 0.18), 0.0004, 0.0012), wood.darkened(r.randf_range(0.15, 0.35)))
	var m := "im:metal@0.35"
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			for y: float in [0.007, 0.097]:
				k.bevel_box(m, _at(x * (W * 0.5 - 0.006), y, z * (D * 0.5 - 0.006)), Vector3(0.017, 0.016, 0.017), 0.002, BRASS)
	k.box(m, _at(0, 0.084, D * 0.5 + 0.0025), Vector3(0.022, 0.016, 0.003), BRASS)
	k.box(m, _at(0, 0.071, D * 0.5 + 0.004), Vector3(0.012, 0.012, 0.004), BRASS.lightened(0.05))
	ItemModels._torus(k, m, Transform3D(FRONT, Vector3(0, 0.066, D * 0.5 + 0.006)), 0.003, 0.001, 10, 4, BRASS)
	return Vector3(0, 0.05, 0)

# --- Pictures ----------------------------------------------------------------------------

## A picture on a plate `w` by `h` facing +Z from xf: `paint(u, v)` colours it (u across,
## v up), as fine as the grid `nu` by `nv`; the plate is `depth` thick, edged `edge`.
static func _picture(k: MeshKit, xf: Transform3D, w: float, h: float, depth: float, m_pic: String, paint: Callable, nu: int, nv: int, m_edge: String, edge: Color) -> void:
	Provisions.sheet(k, m_pic, xf, nu, nv, func(u: float, v: float) -> Vector3: return Vector3((u - 0.5) * w, (v - 0.5) * h, depth * 0.5 + 0.0002),
		func(_p: Vector3, u: float, v: float) -> Color: return paint.call(u, v), Vector3.BACK)
	k.box(m_edge, xf, Vector3(w, h, depth), edge)

## A tintype portrait: a thin dark iron plate, edges chipped brown, carrying a sepia
## picture of a frontiersman: wide-brimmed hat, pale face, neckerchief, dark coat,
## against a lighter ground that darkens to the corners.
static func _tintype(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var W := 0.09
	var H := 0.12
	var paint := func(u: float, v: float) -> Color:
		var bg := Color(0.62, 0.52, 0.38).lerp(Color(0.42, 0.34, 0.24), 1.0 - v)
		var c := bg
		var x := u - 0.5
		# Coat: shoulders widening down from the neck.
		var coat_w := 0.18 + (0.42 - v) * 0.9
		if v < 0.42 and absf(x) < coat_w:
			c = Color(0.2, 0.15, 0.1)
			if absf(x) < 0.08 * (v / 0.42) + 0.01 and v > 0.18:
				c = Color(0.55, 0.47, 0.36)
		if v > 0.33 and v < 0.43 and absf(x) < 0.09:
			c = Color(0.6, 0.52, 0.4)
		if Vector2(x / 0.13, (v - 0.55) / 0.15).length() < 1.0:
			c = Color(0.68, 0.56, 0.42)
			if v < 0.5 and absf(x) < 0.1:
				c = Color(0.36, 0.28, 0.2)
		if v > 0.56 and v < 0.6 and absf(absf(x) - 0.045) < 0.018:
			c = Color(0.2, 0.15, 0.1)
		if v > 0.47 and v < 0.52 and absf(x) < 0.06:
			c = Color(0.25, 0.19, 0.13)
		if v > 0.64 and v < 0.69 and absf(x) < 0.3:
			c = Color(0.18, 0.13, 0.09)
		if v >= 0.69 and v < 0.84 and absf(x) < 0.15 - (v - 0.69) * 0.3:
			c = Color(0.2, 0.15, 0.1)
		var e := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
		c = c.darkened(0.6 * (1.0 - smoothstep(0.0, 0.18, e)))
		if e < 0.025 + 0.015 * Provisions._nz(Vector3(u * 7.0, v * 7.0, 3.0), 1.0):
			c = Color(0.5, 0.34, 0.2)
		return c.darkened(0.08 * (Provisions._nz(Vector3(u, v, 0.0), 30.0) + 0.3))
	_picture(k, Transform3D(Basis(Vector3.RIGHT, -0.25) * Basis(Vector3.BACK, -0.1), Vector3(0, H * 0.5, 0)), W, H, 0.0012, "own:paper", paint, 64, 86, "im:metal@0.6", Color(0.28, 0.2, 0.14))
	return Vector3(0, H * 0.5, 0)

## A holo photo in a standing frame: a brushed steel bezel round a glossy picture of a
## family of three against a blue-violet sky (painted, not lit), a kickstand behind.
static func _holo_photo(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var W := 0.18
	var H := 0.14
	var lean := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, H * 0.5 + 0.004, 0))
	var people := [[0.34, 0.68, 0.11, Color(0.26, 0.32, 0.52), Color(0.16, 0.12, 0.14)], [0.67, 0.62, 0.105, Color(0.55, 0.3, 0.48), Color(0.3, 0.12, 0.12)], [0.5, 0.4, 0.095, Color(0.3, 0.42, 0.62), Color(0.18, 0.13, 0.12)]]
	var paint := func(u: float, v: float) -> Color:
		var c := Color(0.35, 0.42, 0.75).lerp(Color(0.68, 0.52, 0.82), clampf(u + 0.3 * Provisions._nz(Vector3(u * 3.0, v * 3.0, 0.0), 1.0), 0.0, 1.0))
		for p: Array in people:
			var px: float = p[0]
			var py: float = p[1]
			var hr: float = p[2]
			var x := (u - px) / (hr * 0.78)
			var y := (v - py) / hr
			if y < -0.9 and absf(u - px) < hr * 1.4 + (py - hr - v) * 0.6:
				c = p[3]
			if Vector2(x, y).length() < 1.0:
				c = Color(0.72, 0.55, 0.52)
			if Vector2(x, (v - py - hr * 0.3) / hr).length() < 1.05 and y > 0.35:
				c = p[4]
		return c
	_picture(k, lean, W - 0.022, H - 0.022, 0.004, "own:screen", paint, 72, 56, "im:metal@0.4", Color(0.2, 0.2, 0.22))
	for s: float in [-1.0, 1.0]:
		k.bevel_box("im:metal@0.4", lean * _at(0, s * (H * 0.5 - 0.006), 0.002), Vector3(W, 0.012, 0.011), 0.004, Color(0.66, 0.67, 0.7))
		k.bevel_box("im:metal@0.4", lean * _at(s * (W * 0.5 - 0.006), 0, 0.002), Vector3(0.012, H, 0.011), 0.004, Color(0.66, 0.67, 0.7))
	k.box("im:metal@0.4", lean * _at(-W * 0.3, -H * 0.5 + 0.004, 0.0052), Vector3(0.02, 0.002, 0.001), Color(0.3, 0.3, 0.32))
	var top := lean * Vector3(0, H * 0.15, -0.004)
	var foot := Vector3(0, 0.003, -0.07)
	_stroke(k, "im:metal@0.4", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), Vector2(-top.z, top.y), Vector2(-foot.z, foot.y), 0.008, 0.012, 0.0, Color(0.35, 0.35, 0.37))
	return Vector3(0, H * 0.5, 0)

# --- Toys and devices ---------------------------------------------------------------------

## A tin toy robot sitting down: a blue-grey lithographed body with a coloured chest
## panel, a square head with big round eyes, red ear discs and antennae, red shoulder
## joints, claw hands and big red feet; rust spots where the paint has chipped.
static func _toy_robot(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var m := "own:paint"
	var tin := Color(0.42, 0.48, 0.52)
	var red := Color(0.66, 0.14, 0.1)
	var rust := Color(0.5, 0.26, 0.12)
	k.bevel_box(m, _at(0, 0.08, 0), Vector3(0.07, 0.07, 0.05), 0.008, tin)
	k.box(m, _at(0, 0.082, 0.0255), Vector3(0.036, 0.03, 0.002), Color(0.15, 0.2, 0.22))
	for i in 3:
		k.box(m, _at(-0.011 + i * 0.011, 0.082, 0.027), Vector3(0.008, 0.024, 0.0015), [Color(0.3, 0.65, 0.62), Color(0.85, 0.5, 0.15), Color(0.3, 0.65, 0.62)][i])
	k.cylinder(m, _at(0, 0.115, 0), 0.012, 0.012, 0.008, 12, true, 0.0, 1, tin.darkened(0.2))
	# Head, eyes, ears, antennae.
	k.bevel_box(m, _at(0, 0.143, 0), Vector3(0.056, 0.046, 0.046), 0.007, tin.lightened(0.05))
	for s: float in [-1.0, 1.0]:
		k.cylinder(m, Transform3D(FRONT, Vector3(s * 0.013, 0.147, 0.022)), 0.0105, 0.0105, 0.003, 16, true, 0.0, 1, Color(0.62, 0.64, 0.66))
		ItemModels._disc(k, m, Transform3D.IDENTITY, Vector3(s * 0.013, 0.147, 0.0252), Vector3.BACK, 0.0075, 16, Color(0.9, 0.9, 0.86))
		ItemModels._disc(k, m, Transform3D.IDENTITY, Vector3(s * 0.013, 0.147, 0.0254), Vector3.BACK, 0.0035, 12, Color(0.08, 0.08, 0.1))
		k.cylinder(m, Transform3D(Basis(Vector3.BACK, -s * PI * 0.5), Vector3(s * 0.028, 0.145, 0)), 0.011, 0.011, 0.006, 16, true, 0.0, 1, red)
		k.cylinder(m, _at(s * 0.012, 0.166, 0), 0.0015, 0.0015, 0.012, 6, true, 0.0, 1, tin.darkened(0.3))
		k.box(m, _at(s * 0.012, 0.179, 0), Vector3(0.012, 0.003, 0.003), red)
	k.box(m, _at(0, 0.131, 0.0235), Vector3(0.016, 0.004, 0.002), Color(0.1, 0.1, 0.12))
	# Arms: red shoulder, tin arm, claw.
	for s: float in [-1.0, 1.0]:
		k.sphere(m, _at(s * 0.04, 0.1, 0), 0.011, 7, 10, 0.0, 1.0, red)
		ItemModels._tube(k, m, Transform3D.IDENTITY, PackedVector3Array([Vector3(s * 0.045, 0.097, 0), Vector3(s * 0.05, 0.075, 0.01), Vector3(s * 0.05, 0.06, 0.02)]), PackedFloat32Array([0.008, 0.0075, 0.007]), 10, tin)
		for c: float in [-1.0, 1.0]:
			k.box(m, Transform3D(Basis(Vector3.BACK, c * 0.3), Vector3(s * 0.05 + c * 0.004, 0.05, 0.022)), Vector3(0.004, 0.014, 0.008), tin.darkened(0.15))
	# Legs stretched forward and the big red feet.
	for s: float in [-1.0, 1.0]:
		k.bevel_box(m, _at(s * 0.019, 0.03, 0.03), Vector3(0.026, 0.024, 0.05), 0.005, tin.darkened(0.08))
		k.bevel_box(m, _at(s * 0.02, 0.022, 0.07), Vector3(0.032, 0.044, 0.034), 0.008, red)
		for i in 3:
			k.box(m, _at(s * 0.02, 0.008 + i * 0.013, 0.0875), Vector3(0.03, 0.003, 0.002), red.darkened(0.35))
	# Rust where the paint has worn.
	for i in 44:
		var p := Vector3(r.randf_range(-0.03, 0.03), r.randf_range(0.05, 0.16), 0.0)
		var n := Vector3.BACK
		if r.randf() < 0.35:
			n = Vector3.RIGHT if r.randf() < 0.5 else Vector3.LEFT
			p.x = n.x * (0.035 if p.y < 0.118 else 0.028)
			p.z = r.randf_range(-0.02, 0.02)
		else:
			p.z = 0.0252 if p.y < 0.118 else 0.0232
		if absf(p.x) < 0.02 and p.y > 0.065 and p.y < 0.1:
			continue
		ItemModels._disc(k, m, Transform3D.IDENTITY, p + n * 0.0003, n, r.randf_range(0.002, 0.006), 7, rust.darkened(r.randf_range(0.0, 0.3)))
	return Vector3(0, 0.08, 0)

## A rugged music player: a gunmetal case with armoured corners and screws, a black
## glass screen, three round buttons beneath, and a pair of earbuds with blue rims on
## their cord coiled beside it.
static func _music_player(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var m := "im:metal@0.5"
	var gun := Color(0.27, 0.28, 0.29)
	var B := Transform3D(Basis(Vector3.BACK, 0.12), Vector3(-0.012, 0.055, 0))
	k.bevel_box(m, B, Vector3(0.064, 0.1, 0.015), 0.004, gun)
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			k.bevel_box(m, B * _at(x * 0.029, y * 0.046, 0), Vector3(0.012, 0.014, 0.018), 0.003, gun.lightened(0.15))
			ItemModels._disc(k, m, B, Vector3(x * 0.029, y * 0.046, 0.0091), Vector3.BACK, 0.0018, 8, Color(0.5, 0.5, 0.5))
	k.bevel_box(m, B * _at(0, 0.012, 0.0072), Vector3(0.05, 0.056, 0.002), 0.001, Color(0.12, 0.12, 0.13))
	k.box("own:screen", B * _at(0, 0.012, 0.0083), Vector3(0.045, 0.051, 0.0008), Color(0.03, 0.035, 0.04))
	for i in 3:
		k.cylinder(m, B * Transform3D(FRONT, Vector3(-0.016 + i * 0.016, -0.031, 0.007)), 0.0058, 0.0055, 0.003, 16, true, 0.0, 1, Color(0.15, 0.15, 0.16))
		ItemModels._torus(k, m, B * _at(-0.016 + i * 0.016, -0.031, 0.0072, FRONT), 0.006, 0.0008, 16, 4, Color(0.4, 0.4, 0.42))
	# Cord from the jack at the top, round to the two buds.
	var jack := B * Vector3(0.022, 0.05, 0)
	var buds := [Vector3(0.034, 0.008, 0.014), Vector3(0.052, 0.022, 0.002)]
	for i in 2:
		var bp: Vector3 = buds[i]
		var path := PackedVector3Array([jack, jack + Vector3(0.01, 0.008, 0.0), jack + Vector3(0.022 + i * 0.01, -0.012, -0.004), bp + Vector3(0.006, 0.022, -0.006), bp + Vector3(0.0, 0.008, -0.006)])
		var radii := PackedFloat32Array([0.0018, 0.0018, 0.0018, 0.0018, 0.0018])
		ItemModels._tube(k, "own:rubber", Transform3D.IDENTITY, path, radii, 5, Color(0.05, 0.05, 0.05))
		k.sphere("own:rubber", _at(bp.x, bp.y, bp.z - 0.002), 0.011, 7, 10, 0.0, 1.0, Color(0.09, 0.09, 0.1))
		ItemModels._torus(k, "im:metal@0.3", Transform3D(FRONT, bp + Vector3(0, 0, 0.006)), 0.0082, 0.0019, 16, 5, Color(0.12, 0.38, 0.75))
		ItemModels._disc(k, "own:rubber", Transform3D.IDENTITY, bp + Vector3(0, 0, 0.0075), Vector3.BACK, 0.0075, 14, Color(0.05, 0.05, 0.06))
	return Vector3(0, 0.05, 0)
