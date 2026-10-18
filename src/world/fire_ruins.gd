class_name FireRuins
extends RefCounted
## What a fire leaves of what it burnt down (FireSim.RUIN objects): a bed of ash and
## charcoal over the old floor, charred beams fallen in across it, some leaning on the
## others, the burnt stumps of posts still standing, and for a brick or plaster house
## its walls broken down to ragged stubs with rubble spilt round them. Each ruin is sized
## to the footprint of what stood there and laid out from its own seed, all packed in
## the object's species number (encode/decode), so it is the same ruin after a reload.

const TIMBER := 0
const MASONRY := 1
const HEAP := 2 ## a small thing (a cart, a stall, a built piece): a heap of ash and boards

## sp for a ruin w x d metres (its local x and z) laid out from `seed`.
static func encode(w: float, d: float, seed: int) -> int:
	var wq := clampi(roundi(w * 2.0), 1, 255)
	var dq := clampi(roundi(d * 2.0), 1, 255)
	return wq * 65536 + dq * 256 + (seed & 255)

## [width, depth, seed] from a ruin's sp.
static func decode(sp: int) -> Array:
	return [float((sp >> 16) & 255) * 0.5, float((sp >> 8) & 255) * 0.5, sp & 255]

static func kind_for(leaves: String) -> int:
	match leaves:
		"masonry":
			return MASONRY
		"timber":
			return TIMBER
	return HEAP

const ASH := Color(0.2, 0.19, 0.18)
const CHAR := Color(0.11, 0.095, 0.085)
const EMBER_WOOD := Color(0.2, 0.15, 0.12)

static func build(sp: int, v: int) -> ArrayMesh:
	var wd := decode(sp)
	var w: float = wd[0]
	var d: float = wd[1]
	var k := MeshKit.new((sp * 37 + v) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = sp * 7919 + v * 31 + 11
	var small := v == HEAP
	var hx := w * 0.5
	var hz := d * 0.5
	# The ash bed: overlapping low slabs over the floor, thickest in the middle where the
	# roof came down, thinning out past the old walls.
	var beds := clampi(int(w * d / 5.0), 3, 18)
	for i in beds:
		var c := Vector3(r.randf_range(-hx, hx) * 0.8, 0.0, r.randf_range(-hz, hz) * 0.8)
		var s := Vector3(r.randf_range(0.35, 0.7) * w, 0.0, r.randf_range(0.35, 0.7) * d)
		var mid := 1.0 - clampf(Vector2(c.x / maxf(hx, 0.1), c.z / maxf(hz, 0.1)).length(), 0.0, 1.0)
		s.y = (0.06 + 0.22 * mid * r.randf()) * (0.5 if small else 1.0)
		c.y = s.y * 0.35 - 0.04
		var tone := ASH.lerp(CHAR, r.randf() * 0.6)
		k.box("stone_dark", Transform3D(Basis(Vector3.UP, r.randf() * TAU), c), s, tone)
	# Mounds where it came down heaviest.
	for i in clampi(int(w * d / 14.0), 1, 6):
		var c := Vector3(r.randf_range(-hx, hx) * 0.6, -0.1, r.randf_range(-hz, hz) * 0.6)
		var rad := r.randf_range(0.5, 1.4) * (0.5 if small else 1.0)
		k.cylinder("stone_dark", Transform3D(Basis(), c), rad, rad * 0.35, r.randf_range(0.3, 0.7) * (0.6 if small else 1.0), 9, true, 0.12, 2, ASH)
	# Beams fallen in, across one another, a few with an end propped up on the heap.
	var beams := clampi(int(w * d / 6.0), 3, 18) if not small else clampi(int(w * d * 0.8), 2, 6)
	var span := maxf(w, d)
	for i in beams:
		var len := r.randf_range(0.35, 0.95) * span * (0.6 if small else 1.0) + 0.4
		var th := r.randf_range(0.14, 0.24) * (0.6 if small else 1.0)
		var yaw := r.randf() * TAU
		var lift := r.randf_range(0.0, 0.9) if r.randf() < 0.45 else 0.0
		var tilt := asin(clampf(lift / len, 0.0, 0.8))
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		var c := Vector3(r.randf_range(-hx, hx) * 0.85, th * 0.5 + lift * 0.5 + 0.05, r.randf_range(-hz, hz) * 0.85)
		var tone := CHAR.lerp(EMBER_WOOD, r.randf() * 0.5)
		k.box("timber", Transform3D(b, c), Vector3(th, th * 1.2, len), tone)
	if not small:
		# Burnt stumps of the posts, at the corners and along the walls.
		for i in clampi(int((w + d) / 3.0), 3, 10):
			var side := r.randi() % 4
			var u := r.randf_range(-1.0, 1.0)
			var at := Vector3(u * hx if side < 2 else (hx if side == 2 else -hx), 0.0, u * hz if side >= 2 else (hz if side == 0 else -hz))
			if i < 4:
				at = Vector3(hx if i % 2 == 0 else -hx, 0.0, hz if i < 2 else -hz) * 0.95
			var hgt := r.randf_range(0.4, 2.6) if v == TIMBER else r.randf_range(0.3, 1.4)
			var th := r.randf_range(0.18, 0.26)
			var lean := Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(0.0, 0.18))
			k.box("timber", Transform3D(lean, at + Vector3(0, hgt * 0.5 - 0.1, 0)), Vector3(th, hgt, th), CHAR)
	if v == MASONRY:
		_walls(k, r, hx, hz)
	return k.commit(Materials.get_mat)

## The walls of a brick or plaster house, broken down: ragged runs of wall, the corners
## standing tallest, sooted near the top; rubble from them spilt on both sides.
static func _walls(k: MeshKit, r: RandomNumberGenerator, hx: float, hz: float) -> void:
	var th := 0.42
	var brick := Color(0.5, 0.36, 0.3)
	for side in 4:
		var along_x := side < 2
		var half := hx if along_x else hz
		var at := hz if side == 0 else (-hz if side == 1 else (hx if side == 2 else -hx))
		var x := -half
		while x < half:
			var seg := minf(r.randf_range(0.7, 1.8), half - x)
			var corner := minf(absf(x + seg * 0.5 + half), absf(half - x - seg * 0.5)) < 1.2
			var hgt := r.randf_range(1.2, 3.4) if corner else (r.randf_range(0.2, 2.2) if r.randf() < 0.8 else 0.0)
			if hgt > 0.05:
				var mid := x + seg * 0.5
				var c := Vector3(mid, hgt * 0.5 - 0.1, at) if along_x else Vector3(at, hgt * 0.5 - 0.1, mid)
				var s := Vector3(seg, hgt, th) if along_x else Vector3(th, hgt, seg)
				var tone := brick.lerp(Color(0.32, 0.3, 0.29), r.randf() * 0.5)
				k.box("stone", Transform3D(Basis(Vector3.UP, r.randf_range(-0.03, 0.03)), c), s, tone)
				# The broken top: a stepped, sooted course.
				var top := Vector3(c.x, hgt - 0.08, c.z) + (Vector3(r.randf_range(-0.2, 0.2) * seg, 0, 0) if along_x else Vector3(0, 0, r.randf_range(-0.2, 0.2) * seg))
				var ts := Vector3(seg * 0.5, 0.24, th * 0.95) if along_x else Vector3(th * 0.95, 0.24, seg * 0.5)
				k.box("stone", Transform3D(Basis(), top + Vector3(0, 0.12, 0)), ts, tone.darkened(0.55))
			x += seg
	# Rubble.
	for i in clampi(int((hx + hz) * 3.0), 8, 40):
		var side := r.randi() % 4
		var u := r.randf_range(-1.0, 1.0)
		var off := r.randf_range(-1.2, 1.4)
		var at := Vector3(u * hx, 0.0, hz + off) if side == 0 else (Vector3(u * hx, 0.0, -hz - off) if side == 1 else (Vector3(hx + off, 0.0, u * hz) if side == 2 else Vector3(-hx - off, 0.0, u * hz)))
		var s := Vector3(r.randf_range(0.18, 0.5), r.randf_range(0.1, 0.3), r.randf_range(0.18, 0.45))
		at.y = s.y * 0.3
		k.box("stone", Transform3D(Basis.from_euler(Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))), at), s,
			brick.lerp(Color(0.3, 0.29, 0.28), r.randf()))
