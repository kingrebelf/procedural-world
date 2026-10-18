class_name FireRuins
extends RefCounted
## What a fire leaves of what it burnt down (FireSim.RUIN objects): a bed of ash and
## charcoal over the old floor, charred beams fallen in across it, some leaning on the
## others, the burnt stumps of posts still standing, and for a brick or plaster house
## its walls broken down to ragged stubs with rubble spilt round them. A stone town house
## or tower leaves a shell: its walls still standing to the eaves, gables up, the window
## holes black with soot, no roof or floors left inside. Each ruin is sized to the
## footprint of what stood there and laid out from its own seed, all packed in the
## object's species number (encode/decode), so it is the same ruin after a reload; a
## shell's wall height rides in its variant (variant()).

const TIMBER := 0
const MASONRY := 1
const HEAP := 2 ## a small thing (a cart, a stall, a built piece): a heap of ash and boards
const SHELL := 3 ## stone walls left standing, roofless: wall height in half metres is v / 16

## sp for a ruin w x d metres (its local x and z) laid out from `seed`.
static func encode(w: float, d: float, seed: int) -> int:
	var wq := clampi(roundi(w * 2.0), 1, 255)
	var dq := clampi(roundi(d * 2.0), 1, 255)
	return wq * 65536 + dq * 256 + (seed & 255)

## [width, depth, seed] from a ruin's sp.
static func decode(sp: int) -> Array:
	return [float((sp >> 16) & 255) * 0.5, float((sp >> 8) & 255) * 0.5, sp & 255]

## The variant for what burnt down: its kind, and for a shell how tall the walls stand
## (from the height of the building, roof and all).
static func variant(leaves: String, height: float) -> int:
	var v := kind_for(leaves)
	if v == SHELL:
		v += 16 * clampi(roundi(height * 0.62 * 2.0), 5, 24)
	return v

static func kind_for(leaves: String) -> int:
	match leaves:
		"shell":
			return SHELL
		"masonry":
			return MASONRY
		"timber":
			return TIMBER
	return HEAP

const ASH := Color(0.2, 0.19, 0.18)
const CHAR := Color(0.11, 0.095, 0.085)
const EMBER_WOOD := Color(0.2, 0.15, 0.12)

static func build(sp: int, vv: int) -> ArrayMesh:
	var v := vv % 16
	var wall_h := float(vv >> 4) * 0.5
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
		if v == SHELL:
			# Inside the standing walls: shorter, and kept off them.
			len = minf(len, minf(w, d) - 1.2)
			var reach := (Basis(Vector3.UP, yaw) * Vector3(0, 0, len * 0.5)).abs()
			c.x = clampf(c.x, -hx + 0.5 + reach.x, hx - 0.5 - reach.x)
			c.z = clampf(c.z, -hz + 0.5 + reach.z, hz - 0.5 - reach.z)
		var tone := CHAR.lerp(EMBER_WOOD, r.randf() * 0.5)
		k.box("timber", Transform3D(b, c), Vector3(th, th * 1.2, len), tone)
	if not small and v != SHELL:
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
	elif v == SHELL:
		_shell(k, r, hx, hz, maxf(wall_h, 2.5))
	return k.commit(Materials.get_mat)

const STONE := Color(0.5, 0.47, 0.43)
const SOOT := Color(0.09, 0.085, 0.08)
const STOREY := 2.9
const WIN_W := 0.9
const WIN_H := 1.25
const DOOR_W := 1.3
const DOOR_H := 2.2

## A stone house burnt out: the four walls standing to the eaves, gables on the short
## ends, window and door holes, soot licking up the stone above each one where the flames
## came out, the beam ends of the lost floors charred in their sockets, the tops ragged
## where the wall-plate burnt out and stones fell.
static func _shell(k: MeshKit, r: RandomNumberGenerator, hx: float, hz: float, h: float) -> void:
	var th := 0.5
	var floors := maxi(1, int(h / STOREY))
	var ridge_x := hx >= hz # the ridge runs along the longer side; gables on the short ends
	var front := r.randi() % 4 # the side with the door
	for side in 4:
		var along_x := side < 2
		# Long walls along x run past the corners; the end walls fit between them.
		var half := (hx + th * 0.5) if along_x else (hz - th * 0.5)
		var at := (hz if side == 0 else -hz) if along_x else (hx if side == 2 else -hx)
		var out := Vector3(0, 0, signf(at)) if along_x else Vector3(signf(at), 0, 0)
		var gable := (along_x != ridge_x) and r.randf() < 0.85
		var span: float = hz if ridge_x else hx # half the gable's width
		# Where the windows go: evenly along the wall, clear of the corners.
		var n := maxi(0, int((half * 2.0 - 1.6) / 2.6))
		var holes: Array = []
		for i in n:
			holes.append(-half + 0.8 + (half * 2.0 - 1.6) * (i + 0.5) / n)
		var door_x := INF
		if side == front:
			if holes.is_empty():
				holes.append(0.0)
			door_x = float(holes[holes.size() >> 1])
		# Each storey: piers between the holes, a sill and a lintel band at each hole.
		for f in floors:
			var y0 := f * STOREY
			var y1 := h if f == floors - 1 else (f + 1) * STOREY
			var x := -half
			for hc: float in holes + [INF]:
				var hw: float = (DOOR_W if f == 0 and hc == door_x else WIN_W) * 0.5
				var right: float = (hc - hw) if hc != INF else half
				if right - x > 0.02:
					_piece(k, along_x, at, (x + right) * 0.5, y0, y1, right - x, th, r)
				if hc == INF:
					break
				var bot: float = y0 if (f == 0 and hc == door_x) else y0 + 0.9
				var top: float = y0 + (DOOR_H if (f == 0 and hc == door_x) else 0.9 + WIN_H)
				if bot > y0 + 0.01:
					_piece(k, along_x, at, hc, y0, bot, hw * 2.0, th, r)
				if y1 - top > 0.02:
					_piece(k, along_x, at, hc, top, y1, hw * 2.0, th, r)
				# Soot up the face above the hole, where the flames poured out.
				var sp: Vector3 = (Vector3(hc, 0, at) if along_x else Vector3(at, 0, hc)) + out * (th * 0.5 + 0.012)
				var sh := minf(r.randf_range(1.2, 2.4), h - top + 0.2)
				if sh > 0.2:
					# A plume: wide at the lintel, narrowing as it climbs.
					for q in 2:
						var qh := sh * (0.55 if q == 0 else 1.0)
						var qw := hw * 2.0 + (0.25 if q == 0 else -0.2)
						var ss := Vector3(qw, qh, 0.02 + q * 0.006) if along_x else Vector3(0.02 + q * 0.006, qh, qw)
						k.box("stone_dark", Transform3D(Basis(), sp + out * (q * 0.004) + Vector3(0, top + qh * 0.5 - 0.05, 0)), ss, SOOT.lerp(STONE, 0.18 * q))
				x = hc + hw
			# Beam ends of the burnt floor above, charred in their sockets on the inside face.
			if f < floors - 1:
				var bx := -half + 0.6
				while bx < half - 0.4:
					if r.randf() < 0.6:
						var bl := r.randf_range(0.15, 0.6)
						var bp := (Vector3(bx, y1 - 0.15, at) if along_x else Vector3(at, y1 - 0.15, bx)) - out * (th * 0.5 + bl * 0.5)
						var bs := Vector3(0.2, 0.24, bl) if along_x else Vector3(bl, 0.24, 0.2)
						k.box("timber", Transform3D(Basis(), bp), bs, CHAR)
					bx += r.randf_range(0.7, 1.1)
		# The gable: stepped courses narrowing to the ridge, the top often fallen.
		if gable:
			var rise := span * 0.75
			var lost := r.randf_range(0.0, 0.45) * rise if r.randf() < 0.6 else 0.0
			var courses := maxi(3, int(rise / 0.45))
			for c in courses:
				var y := h + c * rise / courses
				if y > h + rise - lost:
					break
				var cw := (half * 2.0) * (1.0 - float(c) / courses)
				var hgt := rise / courses
				_piece(k, along_x, at, r.randf_range(-0.15, 0.15) * float(c) / courses, y, y + hgt, cw, th, r, c * 2 > courses)
		else:
			# A ragged top: the last course broken into steps.
			var x := -half
			while x < half:
				var seg := minf(r.randf_range(0.6, 1.6), half - x)
				var up := r.randf_range(-0.1, 0.45)
				if up > 0.05:
					_piece(k, along_x, at, x + seg * 0.5, h, h + up, seg, th * 0.9, r, true)
				x += seg

## One block of shell wall: centred `c` along it, from y0 to y1, `w` long.
static func _piece(k: MeshKit, along_x: bool, at: float, c: float, y0: float, y1: float, w: float, th: float, r: RandomNumberGenerator, sooted := false) -> void:
	var p := Vector3(c, (y0 + y1) * 0.5 - 0.05, at) if along_x else Vector3(at, (y0 + y1) * 0.5 - 0.05, c)
	var s := Vector3(w, y1 - y0 + 0.1, th) if along_x else Vector3(th, y1 - y0 + 0.1, w)
	# Higher up, nearer the burnt roof, the stone is darker with soot.
	var tone := STONE.lerp(Color(0.38, 0.36, 0.34), r.randf() * 0.6).lerp(SOOT, clampf((y1 - 2.5) / 9.0, 0.0, 0.5) + (0.3 if sooted else 0.0))
	k.box("stone", Transform3D(Basis(), p), s, tone)

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
