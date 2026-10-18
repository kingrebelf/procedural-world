class_name PropSettle
## Props rest on the ground under them. A chest, a wagon or a stack of barrels used to
## stand level at the height of the ground under its middle, sunk 0.15 m: on a slope its
## uphill side went into the hill and its downhill side hung in the air, and on the flat
## a low chest lost a quarter of its height to the ground. Now each one takes the lie of
## the ground under its footprint (a plane fitted to nine points of it, tipped no more than
## MAX_TILT) and is set down until no corner floats, just bedded in by SINK.
##
## Worked out from the chunk's heights when the chunk is drawn, so props in saved worlds
## settle too, and nothing in the snapshot changes. Props not standing on the ground (in
## a cave, a room, a dungeon) keep their place.

## Types that settle onto the ground.
const TYPES := {"chest": true, "rune_coffer": true, "supply_pod": true,
	"wagon": true, "barrels": true, "market_stall": true, "fruit_cart": true}
## Steepest lean (radians, about 35 degrees): a chest on a hillside lies with the hill;
## on steeper ground its uphill edge beds into the slope.
const MAX_TILT := 0.61
## How far the lowest corner is bedded into the ground, so no seam of light shows.
const SINK := 0.03
## The most a resting prop's corner may stand over a dip or a ledge before it is lowered.
const OVERHANG := 0.08
## A prop more than this off the ground under its middle was put somewhere else.
const ON_GROUND := 0.05

static func settles(t: String) -> bool:
	return TYPES.has(t)

## Whether the object stands on the chunk's ground (not in a cave, a room or up high).
static func on_ground(chunk: Dictionary, o: Dictionary) -> bool:
	var p: Vector3 = o["p"]
	return absf(p.y - ChunkGenerator.height_at(chunk, p.x, p.z)) < ON_GROUND

## The settled transform of a placed object (chunk space), or null when it keeps the old
## one: not a settling type, or not on the ground.
static func transform(chunk: Dictionary, o: Dictionary) -> Variant:
	if not settles(o["t"]) or o["st"].get("inside", "") != "" or not on_ground(chunk, o):
		return null
	var ground := func(x: float, z: float) -> float:
		return ChunkGenerator.height_at(chunk, x, z)
	var box := ObjectLibrary.get_mesh(ObjectLibrary.mesh_key(o)).get_aabb()
	return fit(ground, o["p"], float(o["r"]), float(o["s"]), box)

## Sets a model with bounds `box` (its own space) down on the ground at `at` (x, z),
## turned by `yaw` and scaled by `s`, the way a box comes to rest: on the plane through
## three high points of the ground under its footprint that has none of the ground above
## it and hugs the rest closest. On a bump it rests on top (a corner may stand over a
## dip, never more than OVERHANG); on steeper ground than `max_tilt` it leans that far
## and is lowered until nothing floats. Then it is bedded in by `sink`. `ground` maps (x, z) to the ground height.
static func fit(ground: Callable, at: Vector3, yaw: float, s: float, box: AABB, max_tilt := MAX_TILT, sink := SINK) -> Transform3D:
	var yb := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	var pts: Array = [] # footprint points, own space, on the base
	var gp: Array = [] # the ground under them (offsets from `at`, ground height)
	for i in 3:
		for j in 3:
			var q := Vector3(box.position.x + box.size.x * 0.5 * i, box.position.y, box.position.z + box.size.z * 0.5 * j)
			pts.append(q)
			var d: Vector3 = yb * q
			gp.append(Vector3(d.x, float(ground.call(at.x + d.x, at.z + d.z)), d.z))
	var min_up := cos(max_tilt)
	var best_up := Vector3.ZERO
	var best_gap := INF
	var n := gp.size()
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				var pa: Vector3 = gp[a]
				var up := ((gp[b] as Vector3) - pa).cross((gp[c] as Vector3) - pa)
				if up.length_squared() < 1e-8:
					continue
				up = up.normalized()
				if up.y < 0.0:
					up = -up
				if up.y < min_up:
					continue
				# No ground above the plane; the gap under it, summed, as small as it goes.
				var gap := 0.0
				for k in n:
					var e: float = up.dot(pa - (gp[k] as Vector3)) / up.y
					if e < -0.005:
						gap = INF
						break
					gap += e
				if gap < best_gap:
					best_gap = gap
					best_up = up
	var tilt := Basis.IDENTITY
	if best_up == Vector3.ZERO:
		# Too steep to rest on: lean as far as allowed down the fall line.
		var fall := Vector3.ZERO
		for k in n:
			fall += (gp[k] as Vector3) * Vector3(1, 0, 1) * ((gp[k] as Vector3).y - (gp[4] as Vector3).y)
		if fall.length_squared() > 1e-8:
			tilt = Basis(fall.normalized().cross(Vector3.UP).normalized(), max_tilt)
	elif best_up.y < 0.99999:
		tilt = Basis(Vector3.UP.cross(best_up).normalized(), Vector3.UP.angle_to(best_up))
	var bs := tilt * yb
	# Resting: up until nothing is buried (it stands on its high points), but over a ledge
	# it hangs no more than OVERHANG in the air and goes into the lip instead. Too steep:
	# down until nothing floats (its uphill edge goes into the slope). Then bedded in.
	var hi := -INF
	var lo := INF
	for q in pts:
		var w: Vector3 = bs * q
		var e := float(ground.call(at.x + w.x, at.z + w.z)) - w.y
		hi = maxf(hi, e)
		lo = minf(lo, e)
	var y := minf(hi, lo + OVERHANG) if best_up != Vector3.ZERO else lo
	return Transform3D(bs, Vector3(at.x, y - sink, at.z))

## How badly a model with bounds `box` sits on the ground at `at` once fitted (yaw 0, scale
## 1): the deepest any of its base is buried more than SINK, or the highest it floats,
## over a 5 x 5 grid of its footprint. 0 on ground it rests on flush.
static func misfit(ground: Callable, at: Vector3, box: AABB) -> float:
	var xf := fit(ground, at, 0.0, 1.0, box)
	var worst := 0.0
	for i in 5:
		for j in 5:
			var w := xf * Vector3(box.position.x + box.size.x * 0.25 * i, box.position.y, box.position.z + box.size.z * 0.25 * j)
			var e: float = float(ground.call(w.x, w.z)) - w.y
			worst = maxf(worst, maxf(e - SINK, -e))
	return worst
