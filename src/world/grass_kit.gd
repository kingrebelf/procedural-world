class_name GrassKit
## The grass species, each an instanced clump of curved, tapering blades:
##   turf     short fine blades, thick underfoot (drawn only near the player)
##   meadow   the knee-high field grass
##   tall     wild grass with seed heads on stalks, in rough and lush ground
##   flowers_N  wildflowers among a few blades: daisy, buttercup, cornflower, poppy
##   weed     long ribbons of waterweed on lake beds, swaying in the current
## Every vertex carries its blade's own shade (COLOR.rgb, a multiplier on the instance's
## tint; COLOR.a 0 marks seed heads and petals, which keep their own colour), its height up
## the blade (UV.y, which drives the wind), and the distance over which the species
## thins out (UV2: start, end), read by grass.gdshader.

const SPECIES := ["turf", "meadow", "tall", "flowers_0", "flowers_1", "flowers_2", "flowers_3", "weed", "weed_1", "weed_2", "weed_3"]
## [thinning starts, all gone] in metres from the camera.
const RANGE := {"turf": Vector2(18.0, 48.0), "meadow": Vector2(40.0, 110.0), "tall": Vector2(45.0, 115.0), "flowers": Vector2(30.0, 85.0), "weed": Vector2(30.0, 75.0)}
## Petal and centre colours (sRGB) of the wildflowers.
const PETALS := [[Color(0.93, 0.93, 0.88), Color(0.95, 0.75, 0.15)], [Color(0.96, 0.8, 0.16), Color(0.85, 0.62, 0.1)],
	[Color(0.42, 0.48, 0.86), Color(0.3, 0.28, 0.5)], [Color(0.82, 0.16, 0.1), Color(0.12, 0.1, 0.08)]]

## Blade shades go up to about 1.4 times the tint; vertex colours stop at 1, so they are
## stored scaled by this (grass.gdshader undoes it).
const SHADE_SCALE := 0.7

static var _meshes: Dictionary = {}
static var _lock := Mutex.new()

static func range_of(species: String) -> Vector2:
	if species.begins_with("flowers"):
		return RANGE["flowers"]
	return RANGE["weed" if species.begins_with("weed") else species]

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
		"turf":
			for b in 18:
				var off := _spot(r, 0.24)
				_blade(st, r, rg, off, r.randf_range(0.09, 0.26), r.randf_range(0.011, 0.018), r.randf_range(0.02, 0.1), 2)
		"meadow":
			for b in 12:
				var off := _spot(r, 0.3)
				_blade(st, r, rg, off, r.randf_range(0.26, 0.62), r.randf_range(0.016, 0.028), r.randf_range(0.06, 0.24), 3)
		"tall":
			for b in 7:
				var off := _spot(r, 0.26)
				_blade(st, r, rg, off, r.randf_range(0.5, 0.95), r.randf_range(0.015, 0.022), r.randf_range(0.12, 0.34), 4)
			for b in 3:
				# A seed stalk: a thin stem leaning out, an oat-like head at the top.
				var off := _spot(r, 0.15)
				var h := r.randf_range(0.75, 1.15)
				var tip := _blade(st, r, rg, off, h, 0.006, r.randf_range(0.08, 0.2), 4, false)
				_seed_head(st, r, rg, tip, r.randf_range(0.07, 0.12))
		"weed":
			# Ribbons that keep their width most of the way up, leaning every way.
			for b in 11:
				var off := _spot(r, 0.24)
				_blade(st, r, rg, off, r.randf_range(0.45, 1.4), r.randf_range(0.03, 0.05), r.randf_range(0.1, 0.45), 6, false)
		"weed_1":
			# Pondweed: a few tall, lanky strands reaching for the light.
			for b in 6:
				var off := _spot(r, 0.3)
				_blade(st, r, rg, off, r.randf_range(1.0, 2.2), r.randf_range(0.025, 0.04), r.randf_range(0.3, 0.8), 8, false)
		"weed_2":
			# Eelgrass: a dense low tuft of narrow blades, some bent right over.
			for b in 20:
				var off := _spot(r, 0.2)
				_blade(st, r, rg, off, r.randf_range(0.2, 0.75), r.randf_range(0.012, 0.022), r.randf_range(0.05, 0.5), 5, false)
		"weed_3":
			# Broad, crinkled fronds in a loose spray.
			for b in 7:
				var off := _spot(r, 0.28)
				_blade(st, r, rg, off, r.randf_range(0.35, 0.9), r.randf_range(0.05, 0.08), r.randf_range(0.2, 0.6), 6, false)
		_:
			var pc: Array = PETALS[int(species.substr(8)) % PETALS.size()]
			for b in 6:
				var off := _spot(r, 0.22)
				_blade(st, r, rg, off, r.randf_range(0.12, 0.3), r.randf_range(0.014, 0.022), r.randf_range(0.04, 0.12), 2)
			for b in 3:
				var off := _spot(r, 0.16)
				var tip := _blade(st, r, rg, off, r.randf_range(0.22, 0.42), 0.005, r.randf_range(0.02, 0.08), 3, false)
				_bloom(st, r, rg, tip, r.randf_range(0.022, 0.038), pc[0], pc[1])
	st.index()
	return st.commit()

static func _spot(r: RandomNumberGenerator, rad: float) -> Vector3:
	var a := r.randf() * TAU
	var d := sqrt(r.randf()) * rad
	return Vector3(cos(a) * d, 0, sin(a) * d)

## One curved blade from `root`, `segs` segments tapering to a point. Returns its tip.
## A blade's own shade: most a little lighter or darker, some yellowing at the tips.
static func _blade(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, root: Vector3, h: float, w: float, lean: float, segs: int, leaf := true) -> Vector3:
	var basis := Basis(Vector3.UP, r.randf() * TAU)
	var twist := r.randf_range(-0.4, 0.4)
	var v := r.randf_range(0.82, 1.14)
	var shade := Color(v, v, v * r.randf_range(0.9, 1.05))
	var dry := r.randf() < 0.18
	var pts: Array = []
	for i in segs + 1:
		var t := i / float(segs)
		var c := root + basis * Vector3(sin(t * twist) * lean * 0.3, t * h, t * t * lean)
		var hw := w * (1.0 - pow(t, 1.4)) if leaf else w * (1.0 - t * 0.5)
		var side := basis * Vector3(cos(t * twist), 0, -sin(t * twist))
		var col := shade
		if dry:
			col = shade.lerp(Color(1.35, 1.2, 0.62), t * t)
		# Vertex colours are 8-bit, so blade shades are stored at SHADE_SCALE.
		col = Color(col.r * SHADE_SCALE, col.g * SHADE_SCALE, col.b * SHADE_SCALE, 1.0)
		pts.append([c - side * hw, c + side * hw, t, col])
	var n := basis * Vector3(0, 0.35, -1).normalized()
	for i in segs:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		_v(st, a[0], n, 0.0, a[2], a[3], rg)
		_v(st, b[0], n, 0.0, b[2], b[3], rg)
		_v(st, a[1], n, 1.0, a[2], a[3], rg)
		_v(st, a[1], n, 1.0, a[2], a[3], rg)
		_v(st, b[0], n, 0.0, b[2], b[3], rg)
		_v(st, b[1], n, 1.0, b[2], b[3], rg)
	var top: Array = pts[segs]
	return (top[0] + top[1]) * 0.5

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, u: float, t: float, col: Color, rg: Vector2) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(Vector2(u, t))
	st.set_uv2(rg)
	st.add_vertex(p)

## An oat-like seed head: two crossed narrow diamonds of straw, drooping a little.
static func _seed_head(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, size_m: float) -> void:
	var col := Color(0.74, 0.64, 0.4).lerp(Color(0.58, 0.55, 0.36), r.randf())
	col.a = 0.0
	var droop := Basis(Vector3(1, 0, 0), r.randf_range(0.2, 0.5)).rotated(Vector3.UP, r.randf() * TAU)
	for k in 2:
		var side := droop * (Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)) * size_m * 0.16
		var up := droop * Vector3(0, size_m, 0)
		var n := droop * (Vector3(0, 0, 1) if k == 0 else Vector3(1, 0, 0))
		var mid := at + up * 0.45
		for tri in [[at, mid - side, mid + side], [mid - side, at + up, mid + side]]:
			for p in tri:
				_v(st, p, n, 0.5, 1.0, col, rg)

## A small upturned bloom: a ring of petals around a raised centre.
static func _bloom(st: SurfaceTool, r: RandomNumberGenerator, rg: Vector2, at: Vector3, rad: float, petal: Color, centre: Color) -> void:
	var tilt := Basis(Vector3(1, 0, 0), r.randf_range(-0.4, 0.4)).rotated(Vector3.UP, r.randf() * TAU)
	var n := tilt * Vector3.UP
	var pc := petal
	pc.a = 0.0
	var cc := centre
	cc.a = 0.0
	var ring := 12
	for i in ring:
		var a0 := TAU * i / ring
		var a1 := TAU * (i + 1) / ring
		var r0 := rad * (1.0 if i % 2 == 0 else 0.55)
		var r1 := rad * (1.0 if (i + 1) % 2 == 0 else 0.55)
		var p0 := at + tilt * Vector3(cos(a0) * r0, 0.012 * (r0 / rad), sin(a0) * r0)
		var p1 := at + tilt * Vector3(cos(a1) * r1, 0.012 * (r1 / rad), sin(a1) * r1)
		_v(st, at, n, 0.5, 1.0, pc, rg)
		_v(st, p0, n, 0.5, 1.0, pc, rg)
		_v(st, p1, n, 0.5, 1.0, pc, rg)
	var top := at + n * 0.006
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		_v(st, top + n * 0.004, n, 0.5, 1.0, cc, rg)
		_v(st, top + tilt * Vector3(cos(a0), 0, sin(a0)) * rad * 0.3, n, 0.5, 1.0, cc, rg)
		_v(st, top + tilt * Vector3(cos(a1), 0, sin(a1)) * rad * 0.3, n, 0.5, 1.0, cc, rg)
