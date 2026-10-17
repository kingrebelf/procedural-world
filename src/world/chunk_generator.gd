class_name ChunkGenerator
extends RefCounted
## Turns (seed, cx, cz) into a complete chunk snapshot. Pure and deterministic: no
## globals, no clock (except the `created` stamp). Safe to run on worker threads as long
## as each thread uses its own generator instance.

const GEN_VERSION := 9 ## 2: per-region biomes and parametric species. 3: rivers (new worlds). 4: highlands and mesas. 5: sci-fi outpost grids. 6: walled towns. 7: landforms. 8: roads meet towns at their flattened level. 9: human and alien world themes (Eras.theme), eras by distance, world portals.
const FORMAT := 1
const SIZE := 64
const RES := SIZE + 1
const SETTLEMENT_CELL := 256.0
const SETTLEMENT_CHANCE := 0.35
const FLAT_INNER := 30.0
const FLAT_OUTER := 54.0
const WATER_LEVEL := 0.0 ## Must match Water.LEVEL.
## Landform look (WorldField.look_bytes) per point of a 4 m grid, LOOK_N points a side.
const LOOK_BYTES := 12
const LOOK_STEP := 4
const LOOK_N := SIZE / LOOK_STEP + 1

var field: WorldField
var seed: int
## Rivers are carved only in worlds created with them, so chunks generated later in an
## older world still meet the ones already saved.
var rivers := false
## v4 worlds: settlements come in sizes (hamlet, village, town) joined by roads.
var towns := false
## v5: sci-fi outposts on a street grid.
var outposts := false
## v6: the biggest medieval towns are walled.
var walls := false
## v7: regions have landforms (WorldField.shape).
var landforms := false
var _site_cache := {}
var _fort_cache := {}
var _road_cache := {}
var _chunk_sites := {} ## chunk key -> [settlements, settlements + forts] its terrain uses

## Flat radii [inner, outer] for hamlets, villages and towns (v4 worlds).
const SITE_RADII := [[30.0, 54.0], [42.0, 66.0], [56.0, 80.0]]
const MAX_OUTER := 80.0
const ROAD_HALF := 2.4 ## half-width of the beaten surface
const ROAD_STEP := 4.0 ## spacing of road centreline points
const ROAD_REACH := 18.0 ## furthest the land eases toward a road
## v5 roads: chosen among several routes for the gentlest climb, laid at a limited grade,
## and carried on viaducts where the ground falls away beneath them.
const ROAD_GRADE := 0.12 ## steepest climb, rise per metre
const ROAD_CUT := 5.0 ## deepest the road cuts into a hill before it climbs harder
const ROAD_FILL := 3.5 ## higher than this above the ground and it goes on a viaduct
var road_reach := ROAD_REACH
static var _profiles := {}
static var _profile_lock := Mutex.new()

func _init(world_seed: int, with_rivers := false) -> void:
	seed = world_seed & WHash.MASK
	field = WorldField.new(seed)
	rivers = with_rivers
	towns = WorldField.terrain_v >= 4
	outposts = WorldField.terrain_v >= 5
	walls = WorldField.terrain_v >= 6
	landforms = WorldField.terrain_v >= 7
	if outposts:
		road_reach = 26.0

# --- Settlements -------------------------------------------------------------

## Returns { center: Vector2, era: int, target_h: float, sx, sz, size, inner, outer } or {}
## if no settlement.
func settlement_at(sx: int, sz: int) -> Dictionary:
	var key := Vector2i(sx, sz)
	if not _site_cache.has(key):
		_site_cache[key] = _settlement_at(sx, sz)
	return _site_cache[key]

func _settlement_at(sx: int, sz: int) -> Dictionary:
	if WHash.unit2(seed, sx, sz, 201) >= SETTLEMENT_CHANCE:
		return {}
	var c := Vector2((sx + 0.3 + 0.4 * WHash.unit2(seed, sx, sz, 202)) * SETTLEMENT_CELL,
		(sz + 0.3 + 0.4 * WHash.unit2(seed, sx, sz, 203)) * SETTLEMENT_CELL)
	var w := field.era_weights(c.x, c.y)
	var era := WorldField.dominant(w)
	if w[era] < 0.92:
		return {}
	var th := field.shape(c.x, c.y, w).x
	if th < WATER_LEVEL + 1.5:
		return {}
	var size := 0
	if towns:
		var r := WHash.unit2(seed, sx, sz, 204)
		size = 2 if r < 0.15 else (1 if r < 0.5 else 0)
	var out := {"center": c, "era": era, "target_h": th, "sx": sx, "sz": sz,
		"size": size, "inner": SITE_RADII[size][0], "outer": SITE_RADII[size][1]}
	if walls and size == 2 and era == Eras.MEDIEVAL:
		out["walled"] = true
	return out

func settlements_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out: Array = []
	var m := (MAX_OUTER if towns else FLAT_OUTER) + 4.0
	for sz in range(int(floor((z0 - m) / SETTLEMENT_CELL)), int(floor((z1 + m) / SETTLEMENT_CELL)) + 1):
		for sx in range(int(floor((x0 - m) / SETTLEMENT_CELL)), int(floor((x1 + m) / SETTLEMENT_CELL)) + 1):
			var s := settlement_at(sx, sz)
			if s.is_empty():
				continue
			var c: Vector2 = s["center"]
			m = float(s["outer"]) + 4.0
			if c.x + m >= x0 and c.x - m <= x1 and c.y + m >= z0 and c.y - m <= z1:
				out.append(s)
	return out

## Final terrain height including settlement flattening.
func sample_height(x: float, z: float, w: PackedFloat32Array, sites: Array) -> float:
	return _flatten(x, z, field.height(x, z, w), sites)

func _flatten(x: float, z: float, h: float, sites: Array) -> float:
	for s in sites:
		var d := Vector2(x, z).distance_to(s["center"])
		if d < s["outer"]:
			h = lerpf(h, s["target_h"], 1.0 - smoothstep(s["inner"], s["outer"], d))
	return h

# --- Roads -------------------------------------------------------------------
## Each settlement owns the roads to its east and south neighbours; one with neither
## links to the nearest site a little further off, so few places are left unconnected.
func owned_roads(s: Dictionary) -> Array:
	var out: Array = []
	var sx: int = s["sx"]
	var sz: int = s["sz"]
	for o in [Vector2i(1, 0), Vector2i(0, 1)]:
		var t := settlement_at(sx + o.x, sz + o.y)
		if not t.is_empty():
			out.append(t)
	if out.is_empty():
		var best := {}
		var bd := INF
		for o in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(2, 0), Vector2i(0, 2)]:
			var t := settlement_at(sx + o.x, sz + o.y)
			if not t.is_empty():
				var d: float = (t["center"] as Vector2).distance_to(s["center"])
				if d < bd:
					bd = d
					best = t
		if not best.is_empty():
			out.append(best)
	return out

## The road between two settlements: a gently bowed, meandering line of points
## ROAD_STEP apart, from square to square.
func road_points(a: Dictionary, b: Dictionary) -> PackedVector2Array:
	if outposts:
		return road_profile(a, b)["pts"]
	var key := Vector4i(a["sx"], a["sz"], b["sx"], b["sz"])
	if _road_cache.has(key):
		return _road_cache[key]
	var bend := (WHash.unit2(seed, a["sx"] * 7 + b["sx"], a["sz"] * 7 + b["sz"], 205) - 0.5) * 0.36
	var pts := _road_line(a, b, bend)
	_road_cache[key] = pts
	return pts

## A bowed, meandering line of points ROAD_STEP apart; `bend` is the bow as a fraction
## of the length.
func _road_line(a: Dictionary, b: Dictionary, bend: float) -> PackedVector2Array:
	var pa: Vector2 = a["center"]
	var pb: Vector2 = b["center"]
	var length := pa.distance_to(pb)
	var n := maxi(2, int(ceil(length / ROAD_STEP)))
	var perp := (pb - pa).orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var p := pa.lerp(pb, t) + perp * sin(PI * t) * bend * length
		p += perp * field._rwarp.get_noise_2d(p.x * 1.7, p.y * 1.7) * 16.0 * sin(PI * t)
		pts.append(p)
	return pts

## v5: the road between two settlements with its surface level at every point and
## where it rides a viaduct. Shared by every generator of the world (they are made per
## chunk job), since choosing the route samples the land all along it.
func road_profile(a: Dictionary, b: Dictionary) -> Dictionary:
	var key := [seed, a["sx"], a["sz"], b["sx"], b["sz"]]
	_profile_lock.lock()
	var have = _profiles.get(key)
	_profile_lock.unlock()
	if have != null:
		return have
	var base := (WHash.unit2(seed, a["sx"] * 7 + b["sx"], a["sz"] * 7 + b["sz"], 205) - 0.5) * 0.36
	var best := {}
	var best_cost := INF
	for bend in [base, -0.42, -0.26, -0.1, 0.1, 0.26, 0.42]:
		var pts := _road_line(a, b, bend)
		# The road is laid on the land without its rough relief (it cuts through tors
		# and towers, see WorldField.shape) but the route avoids them where it can.
		var raw := PackedFloat32Array()
		var full := PackedFloat32Array()
		for p in pts:
			var sh := field.shape(p.x, p.y)
			if WorldField.terrain_v >= 8:
				# v8: the towns at either end flatten their ground after the road is laid,
				# so plan on that ground; otherwise the road rides a viaduct over a dip the
				# town then fills, and its deck stands on the town's ground.
				raw.append(_flatten(p.x, p.y, sh.x + sh.y, [a, b]))
				full.append(_flatten(p.x, p.y, sh.x + sh.y + sh.z, [a, b]))
			else:
				raw.append(sh.x + sh.y)
				full.append(sh.x + sh.y + sh.z)
		# Climbing costs, climbing steeper than the road may costs far more, and so do
		# lakes; a longer way round costs its length.
		var cost := 0.0
		for i in pts.size() - 1:
			var dh := absf(full[i + 1] - full[i])
			cost += ROAD_STEP * 0.15 + dh + 6.0 * maxf(0.0, dh - ROAD_STEP * ROAD_GRADE)
			if raw[i] < WATER_LEVEL + 0.5:
				cost += 25.0
		if cost < best_cost:
			best_cost = cost
			best = {"pts": pts, "raw": raw, "full": full}
	var pts: PackedVector2Array = best["pts"]
	var raw: PackedFloat32Array = best["raw"]
	var full: PackedFloat32Array = best["full"]
	var n := pts.size()
	var level := PackedFloat32Array()
	level.resize(n)
	for i in n:
		var sum := 0.0
		for o in range(-3, 4):
			sum += raw[clampi(i + o, 0, n - 1)]
		level[i] = sum / 7.0
	# Limit the grade both ways, then don't let it dig a slot through a hill: where the
	# cut would be deeper than ROAD_CUT the road rides higher. Then where that leaves it
	# climbing steeply, raise it ahead of the climb (on an embankment or a viaduct) so it
	# never rises faster than the steepest grade.
	var g := ROAD_GRADE * ROAD_STEP
	for i in range(1, n):
		level[i] = clampf(level[i], level[i - 1] - g, level[i - 1] + g)
	for i in range(n - 2, -1, -1):
		level[i] = clampf(level[i], level[i + 1] - g, level[i + 1] + g)
	for i in n:
		level[i] = maxf(level[i], raw[i] - ROAD_CUT)
	g *= 1.8
	for i in range(1, n):
		level[i] = maxf(level[i], level[i - 1] - g)
	for i in range(n - 2, -1, -1):
		level[i] = maxf(level[i], level[i + 1] - g)
	var air := PackedByteArray()
	air.resize(n)
	var v8 := WorldField.terrain_v >= 8
	for i in n:
		# v8: tors and towers left standing under a viaduct would bury its deck, so the
		# road only takes to the air above the land with its relief.
		var land := maxf(raw[i], full[i]) if v8 else raw[i]
		air[i] = 1 if level[i] - land > ROAD_FILL and i > 2 and i < n - 3 else 0
	# Fill single-point gaps so a viaduct is not broken by one high spot.
	for i in range(1, n - 1):
		if air[i] == 0 and air[i - 1] == 1 and air[i + 1] == 1:
			air[i] = 1
	# v8: a lone point in the air is a dip the embankment either side fills; a viaduct
	# that short would be buried in it.
	if v8:
		for i in range(1, n - 1):
			if air[i] == 1 and air[i - 1] == 0 and air[i + 1] == 0:
				air[i] = 0
	var out := {"pts": pts, "level": level, "air": air}
	_profile_lock.lock()
	if _profiles.size() > 4000:
		_profiles.clear()
	_profiles[key] = out
	_profile_lock.unlock()
	return out

## Every road whose verge reaches the rectangle.
func roads_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out: Array = []
	if not towns:
		return out
	var m := 2.0 * SETTLEMENT_CELL + 150.0
	var area := Rect2(x0 - road_reach - 1.0, z0 - road_reach - 1.0, x1 - x0 + 2.0 * road_reach + 2.0, z1 - z0 + 2.0 * road_reach + 2.0)
	for sz in range(int(floor((z0 - m) / SETTLEMENT_CELL)), int(floor(z1 / SETTLEMENT_CELL)) + 1):
		for sx in range(int(floor((x0 - m) / SETTLEMENT_CELL)), int(floor(x1 / SETTLEMENT_CELL)) + 1):
			var s := settlement_at(sx, sz)
			if s.is_empty():
				continue
			for t in owned_roads(s):
				var c0: Vector2 = s["center"]
				var c1: Vector2 = t["center"]
				var box := Rect2(c0, Vector2.ZERO).expand(c1).grow(0.18 * c0.distance_to(c1) + 20.0)
				if box.intersects(area):
					var pts := road_points(s, t)
					var bb := Rect2(pts[0], Vector2.ZERO)
					for p in pts:
						bb = bb.expand(p)
					if bb.intersects(area):
						out.append(road_profile(s, t) if outposts else {"pts": pts})
	return out

## The centreline of a road from roads_near.
static func road_pts(rd: Dictionary) -> PackedVector2Array:
	return rd["pts"]

## Smoothed land height along a road at point i (the level its surface is laid at).
func _road_level(pts: PackedVector2Array, i: int, raw: Dictionary) -> float:
	var sum := 0.0
	for o in range(-3, 4):
		var j := clampi(i + o, 0, pts.size() - 1)
		if not raw.has(j):
			raw[j] = field.height(pts[j].x, pts[j].y)
		sum += raw[j]
	return sum / 7.0

## For every vertex of the chunk near a road: [distance to the centreline, road level,
## 1 where the road is on a viaduct there].
func _road_field(x0: float, z0: float, roads: Array) -> Array:
	var dist := PackedFloat32Array()
	var level := PackedFloat32Array()
	var air := PackedByteArray()
	dist.resize(RES * RES)
	dist.fill(INF)
	level.resize(RES * RES)
	air.resize(RES * RES)
	var rr := road_reach
	var area := Rect2(x0 - rr, z0 - rr, SIZE + 2.0 * rr, SIZE + 2.0 * rr)
	for rd in roads:
		var pts: PackedVector2Array = rd["pts"]
		var lv: PackedFloat32Array = rd.get("level", PackedFloat32Array())
		var ar: PackedByteArray = rd.get("air", PackedByteArray())
		var raw := {}
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not Rect2(a, Vector2.ZERO).expand(b).intersects(area):
				continue
			var ha := lv[i] if not lv.is_empty() else _road_level(pts, i, raw)
			var hb := lv[i + 1] if not lv.is_empty() else _road_level(pts, i + 1, raw)
			var up := 1 if not ar.is_empty() and ar[i] == 1 and ar[i + 1] == 1 else 0
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.0001)
			var i0 := clampi(int(floor(minf(a.x, b.x) - rr - x0)), 0, RES - 1)
			var i1 := clampi(int(ceil(maxf(a.x, b.x) + rr - x0)), 0, RES - 1)
			var j0 := clampi(int(floor(minf(a.y, b.y) - rr - z0)), 0, RES - 1)
			var j1 := clampi(int(ceil(maxf(a.y, b.y) + rr - z0)), 0, RES - 1)
			for j in range(j0, j1 + 1):
				for ii in range(i0, i1 + 1):
					var q := Vector2(x0 + ii, z0 + j)
					var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
					var d := q.distance_to(a + ab * t)
					var k := j * RES + ii
					if d < dist[k]:
						dist[k] = d
						level[k] = lerpf(ha, hb, t)
						air[k] = up
	return [dist, level, air]

## A stone bridge wherever a road crosses running river water inside this chunk. Each
## crossing is found the same way from any chunk, so exactly one chunk owns it.
func _place_bridges(chunk: Dictionary, roads: Array) -> void:
	var x0 := float(int(chunk["cx"]) * SIZE)
	var z0 := float(int(chunk["cz"]) * SIZE)
	for rd in roads:
		var pts: PackedVector2Array = rd["pts"]
		var carried := PackedByteArray()
		carried.resize(pts.size())
		if rd.has("air"):
			for run in _viaduct_runs(rd):
				for q in range(run.x, run.y + 1):
					carried[q] = 1
		for i in range(1, pts.size() - 1):
			if carried[i] == 1:
				continue # a viaduct already carries the road over
			var p: Vector2 = pts[i]
			if p.x < x0 - ROAD_STEP or p.x > x0 + SIZE + ROAD_STEP or p.y < z0 - ROAD_STEP or p.y > z0 + SIZE + ROAD_STEP:
				continue
			var t := field.river_t(p.x, p.y)
			if t > 1.2 or t > field.river_t(pts[i - 1].x, pts[i - 1].y) or t >= field.river_t(pts[i + 1].x, pts[i + 1].y):
				continue
			# Refine to the deepest point along the road, then measure the wet span.
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i + 1]
			var best := p
			var bt := t
			for k in 17:
				var q := a.lerp(b, k / 16.0)
				var tq := field.river_t(q.x, q.y)
				if tq < bt:
					bt = tq
					best = q
			if best.x < x0 or best.x >= x0 + SIZE or best.y < z0 or best.y >= z0 + SIZE:
				continue
			var lx := best.x - x0
			var lz := best.y - z0
			var level := river_surface(chunk, lx, lz)
			if is_nan(level):
				continue
			var dir := (b - a).normalized()
			var back := 0.0
			while back < 40.0 and field.river_t(best.x - dir.x * back, best.y - dir.y * back) < 1.5:
				back += 1.0
			var ahead := 0.0
			while ahead < 40.0 and field.river_t(best.x + dir.x * ahead, best.y + dir.y * ahead) < 1.5:
				ahead += 1.0
			var wet := back + ahead
			if wet > 50.0:
				continue # the road runs along the river here, not across it
			# Centre the bridge on the water, not on its deepest point.
			var c := best + dir * (ahead - back) * 0.5
			if c.x >= x0 and c.x < x0 + SIZE and c.y >= z0 and c.y < z0 + SIZE:
				lx = c.x - x0
				lz = c.y - z0
			else:
				c = best
			var span := wet + 2.0
			# The banks just beyond the span's ends.
			var ga := _road_ground(rd, c - dir * (span * 0.5 + 1.5))
			var gb := _road_ground(rd, c + dir * (span * 0.5 + 1.5))
			var yaw := atan2(dir.x, dir.y)
			var era := WorldField.dominant(weights_at(chunk, lx, lz))
			var base := height_at(chunk, lx, lz)
			if absf(ga - gb) > 2.0:
				# Banks at different heights: a sloping span from one to the other, its ends
				# on the ground where it meets them.
				var ea := _road_ground(rd, c - dir * (span * 0.5 + 0.5))
				var eb := _road_ground(rd, c + dir * (span * 0.5 + 0.5))
				var clear := INF
				for q in [0.25, 0.5, 0.75]:
					clear = minf(clear, lerpf(ea, eb, q) - _land_at(c + dir * span * (q - 0.5)))
				if clear > 0.3:
					_add(chunk, "bridge", era, lx, lz, yaw, 1.0, {}, Bridge.pack_viaduct(span, (ea + eb) * 0.5 + 0.05 - base, eb - ea), 0)
					continue
				continue # no span fits both banks: the road fords the river here
			# The deck clears the water and stands a little above the higher bank, so its
			# approaches run down into both (it used to sit a step below the banks).
			var top := maxf(level + 1.7, maxf(ga, gb) + 0.3)
			_add(chunk, "bridge", era, lx, lz, yaw, 1.0, {}, Bridge.pack(span, top - base), 0)

## The ground on a road's centreline at p once rivers have cut their vales through it
## and towns have flattened theirs: what a bridge's ends have to meet. Follows the
## terrain pass in generate(), on the road itself (where the land is the road's level).
func _road_ground(rd: Dictionary, p: Vector2) -> float:
	return _road_cut(p, _road_height(rd, p))

## The ground under a road at p: laid at the road's level (then cut by rivers), or the
## bare land where the road is up on a viaduct and nothing was laid.
func _under_road(rd: Dictionary, p: Vector2) -> float:
	var ar: PackedByteArray = rd.get("air", PackedByteArray())
	var q := int(_road_seg(rd["pts"], p).x)
	if not ar.is_empty() and ar[q] == 1 and ar[q + 1] == 1:
		return _land_at(p)
	return _road_ground(rd, p)

## The road stretch nearest p: [index of its first point, how far along it (0..1)].
static func _road_seg(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var bi := 0
	var bt := 0.0
	var bd := INF
	for q in pts.size() - 1:
		var ab := pts[q + 1] - pts[q]
		var t := clampf((p - pts[q]).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_squared_to(pts[q] + ab * t)
		if d < bd:
			bd = d
			bi = q
			bt = t
	return Vector2(bi, bt)

## The road's own level at p, along its nearest stretch.
func _road_height(rd: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = rd["pts"]
	var lv: PackedFloat32Array = rd.get("level", PackedFloat32Array())
	var seg := _road_seg(pts, p)
	var bi := int(seg.x)
	var bt := seg.y
	var raw := {}
	var ha := lv[bi] if not lv.is_empty() else _road_level(pts, bi, raw)
	var hb := lv[bi + 1] if not lv.is_empty() else _road_level(pts, bi + 1, raw)
	return lerpf(ha, hb, bt)

## Height h on the road at p after a river's vale and the towns' flattening, with the
## same towns the terrain of p's own chunk sees (so every chunk gets the same answer).
func _road_cut(p: Vector2, h: float, towns_too := true, rough := 0.0) -> float:
	var near := _sites_for(p)
	if rivers:
		var t := field.river_t(p.x, p.y)
		if t < WorldField.RIVER_REACH:
			var rl := field.river_level(p.x, p.y, {})
			var m := WorldField.river_strength(h - rough, rl)
			for st in near[0]:
				m *= smoothstep(st["outer"], st["outer"] + 30.0, p.distance_to(st["center"]))
			h = WorldField.carve_river(h, t, rl, m)
	return _flatten(p.x, p.y, h, near[1]) if towns_too else h

## [settlements, settlements + forts] that the terrain of p's chunk is shaped by.
func _sites_for(p: Vector2) -> Array:
	var key := Vector2i(int(floor(p.x / SIZE)), int(floor(p.y / SIZE)))
	if not _chunk_sites.has(key):
		if _chunk_sites.size() > 256:
			_chunk_sites.clear()
		var x0 := float(key.x * SIZE)
		var z0 := float(key.y * SIZE)
		var near := settlements_near(x0, z0, x0 + SIZE, z0 + SIZE)
		_chunk_sites[key] = [near, near + forts_near(x0, z0, x0 + SIZE, z0 + SIZE)]
	return _chunk_sites[key]

## The stretches of a road a viaduct carries, as point ranges [a, b] that start and end
## on the ground. A river's vale right at either end is taken in too: it would cut the
## bank out from under the end of the deck.
func _viaduct_runs(rd: Dictionary) -> Array:
	var pts: PackedVector2Array = rd["pts"]
	var ar: PackedByteArray = rd["air"]
	var out: Array = []
	var i := 0
	while i < pts.size():
		if ar[i] == 0:
			i += 1
			continue
		var j := i
		while j + 1 < pts.size() and ar[j + 1] == 1:
			j += 1
		var a := maxi(i - 1, 0)
		var b := mini(j + 1, pts.size() - 1)
		if rivers:
			var lv: PackedFloat32Array = rd["level"]
			var n := 0
			while a > 1 and n < 12 and lv[a] - _road_cut(pts[a], lv[a], false) > 0.5:
				a -= 1
				n += 1
			n = 0
			while b < pts.size() - 2 and n < 12 and lv[b] - _road_cut(pts[b], lv[b], false) > 0.5:
				b += 1
				n += 1
		# A vale between two viaducts joins them into one.
		if not out.is_empty() and a <= out[-1].y + 1:
			out[-1] = Vector2i(out[-1].x, maxi(out[-1].y, b))
		else:
			out.append(Vector2i(a, b))
		i = maxi(j, b - 1) + 1
	return out

## v5: viaducts where a road runs high above the ground, in spans of at most 40 m. Each
## span belongs to the chunk holding its middle. A span is left out where the land
## already carries the road (a town's flattened ground fills the dip, or the embankments
## either side do), and its neighbours come down to the ground there instead. Every
## chunk works this out the same way, so the spans meet.
func _place_viaducts(chunk: Dictionary, roads: Array) -> void:
	var x0 := float(int(chunk["cx"]) * SIZE)
	var z0 := float(int(chunk["cz"]) * SIZE)
	for rd in roads:
		var pts: PackedVector2Array = rd["pts"]
		var lv: PackedFloat32Array = rd["level"]
		for run in _viaduct_runs(rd):
			# The deck runs from a to b, cut into spans.
			var a: int = run.x
			var b: int = run.y
			var pieces := maxi(1, int(ceil((b - a) * ROAD_STEP / 40.0)))
			var cut: Array = []
			for s in pieces + 1:
				cut.append(a + int(round(float(b - a) * s / pieces)))
			# Where the viaduct comes down: the run's ends, on the ground beyond any river.
			var end_h := func(q: int) -> float: return _road_ground(rd, pts[q])
			var keep: Array = []
			for s in pieces:
				var mid := (pts[cut[s]] + pts[cut[s + 1]]) * 0.5
				var ha: float = end_h.call(cut[s]) if s == 0 else lv[cut[s]]
				var hb: float = end_h.call(cut[s + 1]) if s == pieces - 1 else lv[cut[s + 1]]
				keep.append(_town_hold(mid) <= 0.5 and (ha + hb) * 0.5 - _under_road(rd, mid) >= 1.5)
			for s in pieces:
				if not keep[s]:
					continue
				var pa: int = cut[s]
				var pb: int = cut[s + 1]
				var mid := (pts[pa] + pts[pb]) * 0.5
				if mid.x < x0 or mid.x >= x0 + SIZE or mid.y < z0 or mid.y >= z0 + SIZE:
					continue
				var lx := mid.x - x0
				var lz := mid.y - z0
				var dir := (pts[pb] - pts[pa]).normalized()
				# The deck's top sits on the road's level where spans join, and on the
				# ground where the viaduct comes down.
				var ha: float = end_h.call(pa) if s == 0 else (_under_road(rd, pts[pa]) if not keep[s - 1] else lv[pa])
				var hb: float = end_h.call(pb) if s == pieces - 1 else (_under_road(rd, pts[pb]) if not keep[s + 1] else lv[pb])
				var deck := (ha + hb) * 0.5 + 0.05 - height_at(chunk, lx, lz)
				var span := pts[pa].distance_to(pts[pb])
				_add(chunk, "bridge", WorldField.dominant(weights_at(chunk, lx, lz)), lx, lz, atan2(dir.x, dir.y), 1.0, {}, Bridge.pack_viaduct(span, deck, hb - ha), 0)

## How much a town's flattening has replaced the land at p (0 none, 1 all of it).
func _town_hold(p: Vector2) -> float:
	var w := 0.0
	for st in _sites_for(p)[0]:
		w = maxf(w, 1.0 - smoothstep(st["inner"], st["outer"], p.distance_to(st["center"])))
	return w

## The land at p as generate() leaves it away from roads: rivers, towns and all.
func _land_at(p: Vector2) -> float:
	var h: float
	var rough := 0.0
	var rt := field.river_t(p.x, p.y) if rivers else INF
	if landforms:
		var sh := field.shape(p.x, p.y)
		rough = sh.z
		h = sh.x + sh.y * smoothstep(WorldField.RIVER_REACH, WorldField.RIVER_REACH + 4.0, rt) + rough
	else:
		h = field.height(p.x, p.y)
	return _road_cut(p, h, true, rough)

## A cave in rocky hillsides now and then: its mouth faces downhill, with ore seams
## inside and sometimes a cache at the back.
func _place_cave(chunk: Dictionary, sites: Array) -> void:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var r := WHash.rng(seed, cx, cz, 307)
	if r.randf() >= 0.09:
		return
	var lx := r.randf_range(16.0, SIZE - 16.0)
	var lz := r.randf_range(16.0, SIZE - 16.0)
	var sp := (r.randi() & 0x7FFFFFF) | 1
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var h := height_at(chunk, lx, lz)
	var sl := slope_at(chunk, lx, lz)
	if sl < 0.06 or sl > 0.32 or h < WATER_LEVEL + 2.0 or by_river(chunk, lx, lz) or road_at(chunk, lx, lz) > 0.0 or _near_settlement(x0 + lx, z0 + lz, sites, 30.0):
		return
	var d := Cave.dims(sp)
	# Nothing that would leave the shell floating: the ground under its rim stays within reach.
	for a in 8:
		var q := Vector2(lx, lz) + Vector2.from_angle(a * TAU / 8.0) * d.x
		if height_at(chunk, q.x, q.y) < h - d.y * 0.38 or by_river(chunk, q.x, q.y):
			return
	# Dig a level floor inside the shell (the hill behind would otherwise fill it).
	var hs: PackedFloat32Array = chunk["heights"]
	for j in range(int(lz - d.x) - 1, int(lz + d.x) + 2):
		for i in range(int(lx - d.x) - 1, int(lx + d.x) + 2):
			if i < 1 or j < 1 or i >= RES - 1 or j >= RES - 1:
				continue
			var dd := Vector2(i - lx, j - lz).length() / d.x
			if dd < 0.95:
				var k := j * RES + i
				hs[k] = lerpf(hs[k], minf(hs[k], h + 0.15), 1.0 - smoothstep(0.75, 0.95, dd))
	chunk["heights"] = hs
	# Face downhill.
	var down := Vector2(height_at(chunk, lx - 1.0, lz) - height_at(chunk, lx + 1.0, lz), height_at(chunk, lx, lz - 1.0) - height_at(chunk, lx, lz + 1.0))
	var yaw := atan2(down.x, down.y)
	var w := weights_at(chunk, lx, lz)
	var era := WorldField.dominant(w)
	_add(chunk, "cave", era, lx, lz, yaw, 1.0, {}, sp, 0)
	var bp := Biome.params(field.region_hash_at(x0 + lx, z0 + lz), era)
	var basis := Basis(Vector3.UP, yaw)
	for n in r.randi_range(2, 4):
		var a := r.randf_range(PI * 0.55, PI * 1.45) # toward the back walls
		var off := basis * (Vector3(sin(a), 0, cos(a)) * d.x * r.randf_range(0.45, 0.62))
		_add(chunk, Eras.ORE_TYPES[era], era, lx + off.x, lz + off.z, r.randf() * TAU, r.randf_range(0.7, 1.1), {"left": r.randi_range(5, 9), "progress": 0.0}, bp["ore_species"], r.randi() % Flora.VARIANTS)
	if r.randf() < 0.6:
		var back := basis * Vector3(r.randf_range(-1.5, 1.5), 0, -d.x * 0.45)
		var o := {"chunk": Vector2i(cx, cz), "era": era, "how": "found"}
		_add(chunk, Eras.CACHE_TYPES[era], era, lx + back.x, lz + back.z, yaw, 1.0, {"loot": ItemDB.roll_loot(era, r, o, 0.3), "opened": false})

## Inside a cave of this chunk (nothing grows there).
static func in_cave(chunk: Dictionary, lx: float, lz: float) -> bool:
	for o in chunk["objects"]:
		if o["t"] == "cave" and not o["st"].get("gone", false):
			if Vector2(o["p"].x - lx, o["p"].z - lz).length() < Cave.dims(int(o["sp"])).x + 1.5:
				return true
	return false

## How much of the road surface shows at this point of the chunk (0..1).
static func road_at(chunk: Dictionary, lx: float, lz: float) -> float:
	if not chunk.has("road"):
		return 0.0
	var rb: PackedByteArray = chunk["road"]
	return rb[clampi(int(round(lz)), 0, RES - 1) * RES + clampi(int(round(lx)), 0, RES - 1)] / 255.0

# --- Chunk -------------------------------------------------------------------

func generate(cx: int, cz: int) -> Dictionary:
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var sites := settlements_near(x0, z0, x0 + SIZE, z0 + SIZE)
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	var weights := PackedByteArray()
	weights.resize(RES * RES * Eras.COUNT)
	# Era weights vary over tens of metres, so sample them every 4 m and interpolate.
	var coarse: Array = []
	const STEP := 4
	const CN := SIZE / STEP + 1
	var coarse_lf: Array = []
	for j in CN:
		for i in CN:
			coarse.append(field.era_weights(x0 + i * STEP, z0 + j * STEP))
			if landforms:
				coarse_lf.append(field.landform_weights(x0 + i * STEP, z0 + j * STEP))
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
	var lw := PackedFloat32Array()
	lw.resize(WorldField.LF_COUNT)
	# Rivers: only chunks a river comes near pay for them.
	var has_river := false
	if rivers:
		for j in range(0, CN):
			for i in range(0, CN):
				if field.river_t(x0 + i * STEP, z0 + j * STEP) < WorldField.RIVER_REACH + 1.5:
					has_river = true
	var roads := roads_near(x0, z0, x0 + SIZE, z0 + SIZE)
	var rf: Array = _road_field(x0, z0, roads) if not roads.is_empty() else []
	var road_mask := PackedByteArray()
	var any_road := false
	if towns:
		road_mask.resize(RES * RES)
	var forts := forts_near(x0, z0, x0 + SIZE, z0 + SIZE)
	var flat: Array = sites + forts
	var street_ang: Array = []
	for st in sites:
		street_ang.append(outpost_angle(st) if outposts and int(st["era"]) == Eras.SCIFI else NAN)
	var level_cache := {}
	var river := PackedFloat32Array()
	if has_river:
		river.resize(RIVER_N * RIVER_N * 3)
	for j in RES:
		for i in RES:
			var x := x0 + i
			var z := z0 + j
			var gi := mini(i / STEP, CN - 2)
			var gj := mini(j / STEP, CN - 2)
			var fx := (i - gi * STEP) / float(STEP)
			var fz := (j - gj * STEP) / float(STEP)
			var w00: PackedFloat32Array = coarse[gj * CN + gi]
			var w10: PackedFloat32Array = coarse[gj * CN + gi + 1]
			var w01: PackedFloat32Array = coarse[(gj + 1) * CN + gi]
			var w11: PackedFloat32Array = coarse[(gj + 1) * CN + gi + 1]
			for e in Eras.COUNT:
				w[e] = lerpf(lerpf(w00[e], w10[e], fx), lerpf(w01[e], w11[e], fx), fz)
			var k := j * RES + i
			var h: float
			var rough := 0.0
			var rt := INF
			if has_river:
				rt = field.river_t(x, z)
			if landforms:
				var l00: PackedFloat32Array = coarse_lf[gj * CN + gi]
				var l10: PackedFloat32Array = coarse_lf[gj * CN + gi + 1]
				var l01: PackedFloat32Array = coarse_lf[(gj + 1) * CN + gi]
				var l11: PackedFloat32Array = coarse_lf[(gj + 1) * CN + gi + 1]
				for e in WorldField.LF_COUNT:
					lw[e] = lerpf(lerpf(l00[e], l10[e], fx), lerpf(l01[e], l11[e], fx), fz)
				var sh := field.shape(x, z, w, lw)
				# A river fills the holes it runs over rather than plunging into them.
				var holes := sh.y * smoothstep(WorldField.RIVER_REACH, WorldField.RIVER_REACH + 4.0, rt)
				rough = sh.z
				h = sh.x + holes + rough
			else:
				h = field.height(x, z, w)
			var on_road := 0.0
			if not rf.is_empty() and rf[0][k] < road_reach and rf[2][k] == 0:
				var d: float = rf[0][k]
				var lv: float = rf[1][k]
				# Not across lakes or the sea; the land eases down (or up) to the road's
				# level over a verge that widens with the height it has to make up (more
				# gently in v5 worlds, so cuttings have banks rather than walls).
				var dry := smoothstep(WATER_LEVEL + 0.2, WATER_LEVEL + 1.2, lv)
				var verge := ROAD_HALF + 2.0 + minf(absf(h - lv) * (1.7 if outposts else 0.9), road_reach - ROAD_HALF - 2.0)
				h = lerpf(h, lv, (1.0 - smoothstep(ROAD_HALF, verge, d)) * dry)
				on_road = (1.0 - smoothstep(ROAD_HALF - 0.8, ROAD_HALF + 1.0, d)) * dry
			if towns:
				for si in sites.size():
					var st: Dictionary = sites[si]
					var dc := Vector2(x, z).distance_to(st["center"])
					on_road = maxf(on_road, 1.0 - smoothstep(7.0 + st["size"] * 3.0, 11.0 + st["size"] * 4.0, dc))
					if not is_nan(street_ang[si]):
						var sd := outpost_street_d(st, street_ang[si], Vector2(x, z))
						on_road = maxf(on_road, 1.0 - smoothstep(ROAD_HALF - 0.5, ROAD_HALF + 1.2, sd))
				# A stronghold's courtyard is paved.
				for f in forts:
					var q := (Vector2(x, z) - f["center"] as Vector2).rotated(float(f["yaw"]))
					on_road = maxf(on_road, 1.0 - smoothstep(10.5, 12.5, maxf(absf(q.x), absf(q.y))))
					if q.y > 0.0 and q.y < Stronghold.HALF + 10.0:
						on_road = maxf(on_road, 1.0 - smoothstep(1.6, 2.6, absf(q.x)))
				if on_road > 0.0:
					road_mask[k] = int(round(on_road * 255.0))
					any_road = true
			if has_river:
				var t := rt
				var lv := field.river_level(x, z, level_cache)
				# Towers and tors don't stop a river; it cuts its way past them.
				var m := WorldField.river_strength(h - rough, lv)
				for st in sites:
					m *= smoothstep(st["outer"], st["outer"] + 30.0, Vector2(x, z).distance_to(st["center"]))
				h = WorldField.carve_river(h, t, lv, m)
				if i % 2 == 0 and j % 2 == 0:
					var rk := ((j / 2) * RIVER_N + i / 2) * 3
					river[rk] = lv
					river[rk + 1] = t
					river[rk + 2] = m
			heights[k] = _flatten(x, z, h, flat)
			for e in Eras.COUNT:
				weights[k * Eras.COUNT + e] = int(round(w[e] * 255.0))
	var center_w := field.era_weights(x0 + SIZE * 0.5, z0 + SIZE * 0.5)
	# v7: what the landforms do to the colour of rock and ground, on the 4 m grid.
	var look := PackedByteArray()
	if landforms:
		var any := false
		look.resize(CN * CN * LOOK_BYTES)
		for c in CN * CN:
			WorldField.look_bytes(coarse_lf[c], look, c * LOOK_BYTES)
			any = any or look[c * LOOK_BYTES + 3] > 0 or look[c * LOOK_BYTES + 7] > 0 or look[c * LOOK_BYTES + 9] > 0
		if not any:
			look = PackedByteArray()
	var chunk := {
		"format": FORMAT, "gen_version": GEN_VERSION, "seed": seed,
		"cx": cx, "cz": cz,
		"heights": heights, "weights": weights,
		"era": WorldField.dominant(center_w),
		"region": field.region_name_at(x0 + SIZE * 0.5, z0 + SIZE * 0.5),
		"objects": [],
		"biome": field.region_hash_at(x0 + SIZE * 0.5, z0 + SIZE * 0.5),
	}
	if has_river:
		chunk["river"] = river
	if not look.is_empty():
		chunk["look"] = look
	if any_road:
		chunk["road"] = road_mask
	if has_river and not roads.is_empty():
		_place_bridges(chunk, roads)
	if outposts and not roads.is_empty():
		_place_viaducts(chunk, roads)
	_place_objects(chunk, sites)
	return chunk

static func _crowds_tree(chunk: Dictionary, lx: float, lz: float, gap: float) -> bool:
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) == "tree" and Vector2(o["p"].x - lx, o["p"].z - lz).length() < gap:
			return true
	return false

## The landform's rock colour at a point of the chunk (rgb) and how much it shows (a);
## transparent where no landform colours the rock.
static func stone_at(chunk: Dictionary, lx: float, lz: float) -> Color:
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	if lb.is_empty():
		return Color(0, 0, 0, 0)
	var i := clampi(int(round(lx / LOOK_STEP)), 0, LOOK_N - 1)
	var j := clampi(int(round(lz / LOOK_STEP)), 0, LOOK_N - 1)
	var k := (j * LOOK_N + i) * LOOK_BYTES
	return Color(lb[k] / 255.0, lb[k + 1] / 255.0, lb[k + 2] / 255.0, lb[k + 3] / 255.0)

## How much grass and undergrowth a landform's ground allows here (0 on sand dunes,
## less on dust and clay, 1 elsewhere).
static func cover_at(chunk: Dictionary, lx: float, lz: float) -> float:
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	if lb.is_empty():
		return 1.0
	var i := clampi(int(round(lx / LOOK_STEP)), 0, LOOK_N - 1)
	var j := clampi(int(round(lz / LOOK_STEP)), 0, LOOK_N - 1)
	var k := (j * LOOK_N + i) * LOOK_BYTES
	return 1.0 - maxf(lb[k + 8] / 255.0, lb[k + 7] / 255.0 * 0.7)

static func height_at(chunk: Dictionary, lx: float, lz: float) -> float:
	var hs: PackedFloat32Array = chunk["heights"]
	lx = clampf(lx, 0.0, SIZE - 0.001)
	lz = clampf(lz, 0.0, SIZE - 0.001)
	var i := int(lx)
	var j := int(lz)
	var fx := lx - i
	var fz := lz - j
	var h00 := hs[j * RES + i]
	var h10 := hs[j * RES + i + 1]
	var h01 := hs[(j + 1) * RES + i]
	var h11 := hs[(j + 1) * RES + i + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

## River samples every 2 m: [water level, distance from centre in half-widths, strength].
const RIVER_N := SIZE / 2 + 1

## The river's water surface at a point in this chunk, or NAN where there is no river water.
static func river_surface(chunk: Dictionary, lx: float, lz: float) -> float:
	if not chunk.has("river"):
		return NAN
	var rv: PackedFloat32Array = chunk["river"]
	var i := clampi(int(round(lx * 0.5)), 0, RIVER_N - 1)
	var j := clampi(int(round(lz * 0.5)), 0, RIVER_N - 1)
	var k := (j * RIVER_N + i) * 3
	if rv[k + 1] > 1.05 or rv[k + 2] < 0.3 or rv[k] <= WATER_LEVEL + 0.2:
		return NAN
	return rv[k]

static func under_river(chunk: Dictionary, lx: float, lz: float) -> bool:
	return not is_nan(river_surface(chunk, lx, lz))

## In the river or on its immediate banks (nothing is placed there).
static func by_river(chunk: Dictionary, lx: float, lz: float) -> bool:
	if not chunk.has("river"):
		return false
	var rv: PackedFloat32Array = chunk["river"]
	var k := (clampi(int(round(lz * 0.5)), 0, RIVER_N - 1) * RIVER_N + clampi(int(round(lx * 0.5)), 0, RIVER_N - 1)) * 3
	return rv[k + 1] < 1.5 and rv[k + 2] > 0.2

static func slope_at(chunk: Dictionary, lx: float, lz: float) -> float:
	var dx := height_at(chunk, lx + 1.0, lz) - height_at(chunk, lx - 1.0, lz)
	var dz := height_at(chunk, lx, lz + 1.0) - height_at(chunk, lx, lz - 1.0)
	return Vector2(dx, dz).length() * 0.5

static func weights_at(chunk: Dictionary, lx: float, lz: float) -> PackedFloat32Array:
	var i := clampi(int(round(lx)), 0, RES - 1)
	var j := clampi(int(round(lz)), 0, RES - 1)
	var k := (j * RES + i) * Eras.COUNT
	var wb: PackedByteArray = chunk["weights"]
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
	for e in Eras.COUNT:
		w[e] = wb[k + e] / 255.0
	return w

func _pick_era(w: PackedFloat32Array, r: float) -> int:
	var acc := 0.0
	for e in Eras.COUNT:
		acc += w[e]
		if r <= acc:
			return e
	return Eras.COUNT - 1

func _add(chunk: Dictionary, type: String, era: int, lx: float, lz: float, yaw: float, scale: float, st: Dictionary = {}, sp: int = 0, v: int = 0) -> void:
	var objs: Array = chunk["objects"]
	var o := {
		"i": objs.size(), "t": type, "e": era,
		"p": Vector3(lx, height_at(chunk, lx, lz), lz),
		"r": yaw, "s": scale, "st": st,
	}
	if sp != 0:
		o["sp"] = sp
		o["v"] = v
	objs.append(o)

## Within `extra` metres of a settlement's flat ground.
func _near_settlement(x: float, z: float, sites: Array, extra: float) -> bool:
	for s in sites:
		# A town wall stands just outside the flat ground; keep the wilds off it too.
		if Vector2(x, z).distance_to(s["center"]) < float(s["inner"]) + extra + (8.0 if s.get("walled", false) else 0.0):
			return true
	return false

func _place_objects(chunk: Dictionary, sites: Array) -> void:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var origin := {"chunk": Vector2i(cx, cz)}

	# Settlements first so they claim their space, then strongholds.
	for s in sites:
		_place_settlement(chunk, s, x0, z0)
	var forts := forts_near(x0, z0, x0 + SIZE, z0 + SIZE)
	for f in forts:
		_place_fort(chunk, f, x0, z0)
	sites = sites + forts
	# A wonder, very rarely; everything after keeps clear of its plaza.
	var wonder := WonderSite.place(self, chunk, sites)
	if not wonder.is_empty():
		sites = sites + [wonder]
	# A portal to other worlds, rarer still and only far out in the high zones.
	var portal := WorldPortal.place(self, chunk)
	if not portal.is_empty():
		sites = sites + [portal]

	if towns:
		_place_cave(chunk, sites)

	# Vegetation: jittered candidates, era picked by sampling local weights so
	# transition bands get a natural, dithered mix of both sides. Each region's biome
	# decides which species grow and how densely.
	var r := WHash.rng(seed, cx, cz, 301)
	var candidates := 64
	for n in candidates:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var era := _pick_era(w, r.randf())
		var forest := clampf((field._moss.get_noise_2d((x0 + lx) * 0.15, (z0 + lz) * 0.15) + 0.35) * 1.5, 0.0, 1.0)
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.7, 1.4)
		var hp := r.randi_range(3, 5)
		var yield_ := r.randi_range(3, 6)
		var variant := r.randi() % Flora.VARIANTS
		var pick := r.randf()
		var bp := Biome.params(field.region_hash_at(x0 + lx, z0 + lz), era)
		var p: float = Eras.TREE_DENSITY[era] / candidates * (0.25 + forest * 1.6) * float(bp["tree_density"])
		if landforms:
			p *= WorldField.LANDFORM_TREES[field.landform_at(x0 + lx, z0 + lz)]
		if roll >= p or slope_at(chunk, lx, lz) > 0.75 or height_at(chunk, lx, lz) < WATER_LEVEL + 0.4 or by_river(chunk, lx, lz) or _near_settlement(x0 + lx, z0 + lz, sites, 6.0) or road_at(chunk, lx, lz) > 0.15 or in_cave(chunk, lx, lz):
			continue
		var f := Biome.pick_flora(bp, pick)
		_add(chunk, f["t"], era, lx, lz, yaw, sc, {"hp": hp, "yield": yield_}, f["sp"], variant)

	# v4: old-growth forests in the densest regions, close enough to darken the floor.
	if towns:
		r = WHash.rng(seed, cx, cz, 306)
		for n in 96:
			var lx := r.randf() * SIZE
			var lz := r.randf() * SIZE
			var w := weights_at(chunk, lx, lz)
			var era := _pick_era(w, r.randf())
			var roll := r.randf()
			var yaw := r.randf() * TAU
			var sc := r.randf_range(0.8, 1.5)
			var hp := r.randi_range(4, 6)
			var yield_ := r.randi_range(4, 7)
			var variant := r.randi() % Flora.VARIANTS
			var pick := r.randf()
			var bp := Biome.params(field.region_hash_at(x0 + lx, z0 + lz), era)
			var dense := smoothstep(1.3, 2.2, float(bp["tree_density"])) * (1.0 if era != Eras.SCIFI else 0.3)
			if landforms:
				dense *= minf(1.0, WorldField.LANDFORM_TREES[field.landform_at(x0 + lx, z0 + lz)])
			if roll >= dense * 0.85 or slope_at(chunk, lx, lz) > 0.7 or height_at(chunk, lx, lz) < WATER_LEVEL + 0.6 or by_river(chunk, lx, lz) or _near_settlement(x0 + lx, z0 + lz, sites, 6.0) or road_at(chunk, lx, lz) > 0.05 or in_cave(chunk, lx, lz) or _crowds_tree(chunk, lx, lz, 2.2):
				continue
			var f := Biome.pick_flora(bp, pick)
			_add(chunk, f["t"], era, lx, lz, yaw, sc, {"hp": hp, "yield": yield_}, f["sp"], variant)

	# Rocks and ore, shaped by the region's geology.
	r = WHash.rng(seed, cx, cz, 302)
	for n in 16:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var era := _pick_era(w, r.randf())
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.6, 1.8)
		var left := r.randi_range(3, 7)
		var variant := r.randi() % Flora.VARIANTS
		var pick := r.randi()
		if _near_settlement(x0 + lx, z0 + lz, sites, 0.0) or road_at(chunk, lx, lz) > 0.15 or in_cave(chunk, lx, lz) or height_at(chunk, lx, lz) < WATER_LEVEL - 1.5 or by_river(chunk, lx, lz):
			continue
		var bp := Biome.params(field.region_hash_at(x0 + lx, z0 + lz), era)
		var rd: float = Eras.ROCK_DENSITY[era] * float(bp["rock_density"])
		if landforms:
			rd *= WorldField.LANDFORM_ROCKS[field.landform_at(x0 + lx, z0 + lz)]
		var rocks: Array = bp["rocks"]
		if _crowds_tree(chunk, lx, lz, 1.2 * sc + 0.8):
			# A boulder grown into a trunk makes chopping and mining ambiguous.
			continue
		if roll < rd / 16.0:
			_add(chunk, "rock", era, lx, lz, yaw, sc, {"left": left, "progress": 0.0}, rocks[pick % rocks.size()], variant)
		elif roll < (rd + Eras.ORE_DENSITY[era]) / 16.0:
			_add(chunk, Eras.ORE_TYPES[era], era, lx, lz, yaw, sc * 0.8, {"left": left + 2, "progress": 0.0}, bp["ore_species"], variant)

	# Alien ruins: rare, strange, very tough. Anywhere outside settlements.
	r = WHash.rng(seed, cx, cz, 305)
	if r.randf() < 0.035 and Eras.theme != "human":
		var lx := r.randf_range(10, SIZE - 10)
		var lz := r.randf_range(10, SIZE - 10)
		var sp := r.randi() & 0x7FFFFFFF
		var yaw := r.randf() * TAU
		var ok := not _near_settlement(x0 + lx, z0 + lz, sites, 34.0) or road_at(chunk, lx, lz) > 0.0 and height_at(chunk, lx, lz) > WATER_LEVEL + 0.5 and not by_river(chunk, lx, lz) and slope_at(chunk, lx, lz) < 0.4
		if outposts:
			# v5: away from settlements and roads, on dry, fairly level ground.
			ok = not _near_settlement(x0 + lx, z0 + lz, sites, 34.0) and road_at(chunk, lx, lz) <= 0.0 and height_at(chunk, lx, lz) > WATER_LEVEL + 0.5 and not by_river(chunk, lx, lz) and slope_at(chunk, lx, lz) < 0.4
		if ok:
			var era := WorldField.dominant(weights_at(chunk, lx, lz))
			_add(chunk, "alien_ruin", era, lx, lz, yaw, 1.0, {}, sp, 0)

	# Caches: rare, contents rolled now and frozen forever.
	r = WHash.rng(seed, cx, cz, 303)
	if r.randf() < 0.22:
		var lx := r.randf_range(4, SIZE - 4)
		var lz := r.randf_range(4, SIZE - 4)
		var era := WorldField.dominant(weights_at(chunk, lx, lz))
		var o := origin.duplicate()
		o["era"] = era
		o["how"] = "found"
		var loot := ItemDB.roll_loot(era, r, o)
		_add(chunk, Eras.CACHE_TYPES[era], era, lx, lz, r.randf() * TAU, 1.0, {"loot": loot, "opened": false})

	if landforms:
		_place_landmark(chunk, sites, origin)

	# Threshold markers inside transition bands make crossings read as intentional.
	r = WHash.rng(seed, cx, cz, 304)
	for n in 10:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var top := w[WorldField.dominant(w)]
		var era := _pick_era(w, r.randf())
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.8, 1.4)
		if top < 0.72 and r.randf() < 0.55 and slope_at(chunk, lx, lz) < 0.5:
			_add(chunk, Eras.MARKER_TYPES[era], era, lx, lz, yaw, sc)

## Strongholds whose flat ground reaches into this rectangle (v5 worlds).
func forts_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out: Array = []
	if not outposts:
		return out
	var span := float(Stronghold.CELL * SIZE)
	for cz in range(int(floor((z0 - Stronghold.OUTER) / span)), int(floor((z1 + Stronghold.OUTER) / span)) + 1):
		for cx in range(int(floor((x0 - Stronghold.OUTER) / span)), int(floor((x1 + Stronghold.OUTER) / span)) + 1):
			var key := Vector2i(cx, cz)
			if not _fort_cache.has(key):
				_fort_cache[key] = Stronghold.at_cell(self, cx, cz)
			var f: Dictionary = _fort_cache[key]
			if f.is_empty():
				continue
			var c: Vector2 = f["center"]
			if c.x + Stronghold.OUTER >= x0 and c.x - Stronghold.OUTER <= x1 and c.y + Stronghold.OUTER >= z0 and c.y - Stronghold.OUTER <= z1:
				out.append(f)
	return out

func _place_fort(chunk: Dictionary, f: Dictionary, x0: float, z0: float) -> void:
	var era: int = f["era"]
	for it in Stronghold.layout(self, f):
		var p: Vector2 = it["p"]
		if p.x >= x0 and p.x < x0 + SIZE and p.y >= z0 and p.y < z0 + SIZE:
			_add(chunk, it["t"], era, p.x - x0, p.y - z0, it["yaw"], 1.0, it["st"])
	for g in Stronghold.guards(f):
		var p: Vector2 = g["p"]
		if p.x >= x0 and p.x < x0 + SIZE and p.y >= z0 and p.y < z0 + SIZE:
			if not chunk.has("guards"):
				chunk["guards"] = []
			chunk["guards"].append({"id": g["id"], "lx": p.x - x0, "lz": p.y - z0, "tier": g["tier"], "era": era})

## Everything a settlement contains, in world coordinates. Deterministic per site, so
## the NPC system can find homes and the stall without loading every chunk.
func settlement_layout(s: Dictionary) -> Array:
	var c: Vector2 = s["center"]
	var era: int = s["era"]
	var r := WHash.rng(seed, s["sx"], s["sz"], 401)
	var items: Array = []
	items.append({"t": "trader", "p": c + Vector2(r.randf_range(-3, 3), r.randf_range(-3, 3)), "yaw": r.randf() * TAU,
		"st": Economy.new_trader(era, r)})
	var kit: Array = Eras.TOWN_TYPES[era] if towns else Eras.STRUCTURE_TYPES[era]
	if outposts and era == Eras.SCIFI:
		_outpost_grid(s, r, items)
	elif towns:
		_town_rings(s, r, kit, items)
		if era == Eras.MEDIEVAL:
			_market(s, items)
		if s.get("walled", false):
			Stronghold.town_wall(self, s, items)
		# A signpost where each road leaves the village.
		for w in road_angles(s):
			var at: Vector2 = c + Vector2.from_angle(w) * (float(s["inner"]) - 4.0) + Vector2.from_angle(w + PI / 2) * (ROAD_HALF + 1.4)
			var dir := Vector2.from_angle(w)
			items.append({"t": "signpost", "p": at, "yaw": atan2(-dir.x, -dir.y), "st": {}})
	else:
		var count := r.randi_range(3, 7)
		var a0 := r.randf() * TAU
		for k in count:
			var ang := a0 + TAU * k / count + r.randf_range(-0.25, 0.25)
			var rad := r.randf_range(14.0, 26.0)
			var p := c + Vector2(cos(ang), sin(ang)) * rad
			var t: String = kit[r.randi() % kit.size()]
			# Face the square.
			items.append({"t": t, "p": p, "yaw": atan2(c.x - p.x, c.y - p.y), "st": {}})
	if r.randf() < 0.6:
		var cx := int(floor(c.x / SIZE))
		var cz := int(floor(c.y / SIZE))
		var o := {"chunk": Vector2i(cx, cz), "era": era, "how": "found"}
		items.append({"t": Eras.CACHE_TYPES[era], "p": c + Vector2(r.randf_range(-9, 9), r.randf_range(-9, 9)),
			"yaw": r.randf() * TAU, "st": {"loot": ItemDB.roll_loot(era, r, o), "opened": false}})
	return items

## Rings of buildings per size: [min count, max count, min radius, max radius].
const TOWN_RINGS := [
	[[3, 7, 14.0, 26.0]],
	[[5, 7, 15.0, 21.0], [7, 10, 29.0, 36.0]],
	[[6, 8, 16.0, 22.0], [9, 12, 30.0, 37.0], [12, 15, 44.0, 50.0]],
]

## Buildings in rings around the square, leaving the roads into town clear.
func _town_rings(s: Dictionary, r: RandomNumberGenerator, kit: Array, items: Array) -> void:
	var c: Vector2 = s["center"]
	var ways := road_angles(s)
	for ring in TOWN_RINGS[int(s["size"])]:
		var count := r.randi_range(ring[0], ring[1])
		var a0 := r.randf() * TAU
		for k in count:
			var ang := a0 + TAU * k / count + r.randf_range(-0.12, 0.12)
			var rad := r.randf_range(ring[2], ring[3])
			var t: String = kit[r.randi() % kit.size()]
			var clear := (ROAD_HALF + 5.0) / rad
			var blocked := false
			for w in ways:
				if absf(angle_difference(ang, w)) < clear:
					blocked = true
			if blocked:
				continue
			var p := c + Vector2(cos(ang), sin(ang)) * rad
			items.append({"t": t, "p": p, "yaw": atan2(c.x - p.x, c.y - p.y), "st": {}})

## Sci-fi outposts sit on a street grid: a main street carrying the first road through
## town and a cross street, buildings on square lots facing the nearer street, fenced
## solar farms and depots on the outer lots, floodlights along the streets.
const LOT := 16.0

func outpost_angle(s: Dictionary) -> float:
	var ways := road_angles(s)
	if not ways.is_empty():
		return ways[0]
	return WHash.rng(seed, s["sx"], s["sz"], 403).randf() * TAU

## Distance from p to the outpost's two streets (inside the town only).
func outpost_street_d(s: Dictionary, ang: float, p: Vector2) -> float:
	var q := (p - s["center"] as Vector2).rotated(-ang)
	if q.length() > float(s["inner"]) - 2.0:
		return INF
	return minf(absf(q.x), absf(q.y))

func _outpost_grid(s: Dictionary, r: RandomNumberGenerator, items: Array) -> void:
	var c: Vector2 = s["center"]
	var size := int(s["size"])
	var inner := float(s["inner"])
	var ang := outpost_angle(s)
	var ways := road_angles(s)
	var lots: Array = []
	for i in range(-3, 4):
		for j in range(-3, 4):
			if i == 0 or j == 0:
				continue
			var q := Vector2((absi(i) - 0.5) * LOT + 3.0, (absi(j) - 0.5) * LOT + 3.0) * Vector2(signi(i), signi(j))
			if q.length() + 5.0 > inner + 2.0:
				continue
			var p := c + q.rotated(ang)
			# Keep other roads into town clear.
			var blocked := false
			for w in ways.slice(1):
				var dir := Vector2.from_angle(w)
				var t := (p - c).dot(dir)
				if t > 0.0 and absf((p - c).cross(dir)) < ROAD_HALF + 8.0:
					blocked = true
			if not blocked:
				lots.append(q)
	lots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	var outer: Array = []
	if size >= 1:
		outer.append("solar_farm")
		outer.append("depot")
		outer.append(ShipPad.pick(r))
	if size >= 2:
		outer.append("solar_farm")
	for n in lots.size():
		var q: Vector2 = lots[n]
		var t: String
		if n == 0:
			t = "ops_tower"
		elif n == 1 and size >= 1:
			t = "comms_spire"
		elif lots.size() - n <= outer.size():
			t = outer[lots.size() - n - 1]
		else:
			t = "hab_block" if r.randf() < 0.6 else "lab_block"
		# Face the nearer street.
		var face := Vector2(0, -signf(q.y)) if absf(q.y) <= absf(q.x) else Vector2(-signf(q.x), 0)
		var dir := face.rotated(ang)
		items.append({"t": t, "p": c + q.rotated(ang), "yaw": atan2(dir.x, dir.y), "st": {}})
	# Floodlights down both sides of each street, alternating.
	for k in 4:
		var along := Vector2.from_angle(ang + k * PI / 2)
		var side := along.rotated(PI / 2)
		var m := 0
		var d := 9.0
		while d < inner - 4.0:
			var sgn := 1.0 if m % 2 == 0 else -1.0
			var p := c + along * d + side * sgn * (ROAD_HALF + 1.6)
			var to := -side * sgn
			items.append({"t": "outpost_light", "p": p, "yaw": atan2(to.x, to.y), "st": {}})
			d += 12.0
			m += 1

## Stalls, carts and barrels around a medieval square, clear of the roads.
func _market(s: Dictionary, items: Array) -> void:
	var r := WHash.rng(seed, s["sx"], s["sz"], 402)
	var c: Vector2 = s["center"]
	var ways := road_angles(s)
	var props := ["market_stall", "market_stall", "fruit_cart", "barrels", "wagon"]
	var count := 1 + int(s["size"]) * 2 + r.randi_range(0, 2)
	var a0 := r.randf() * TAU
	for k in count:
		var ang := a0 + TAU * k / count + r.randf_range(-0.2, 0.2)
		var rad := r.randf_range(8.5, 11.0) + float(s["size"]) * 2.0
		var blocked := false
		for w in ways:
			if absf(angle_difference(ang, w)) < 4.5 / rad:
				blocked = true
		if blocked:
			continue
		var p := c + Vector2(cos(ang), sin(ang)) * rad
		items.append({"t": props[r.randi() % props.size()], "p": p, "yaw": atan2(c.x - p.x, c.y - p.y), "st": {}})

## Directions (radians, as Vector2.angle) in which roads leave a settlement's square.
## Where each road of a settlement crosses the circle of radius `rad` round its centre,
## as angles.
func road_crossings(s: Dictionary, rad: float) -> Array:
	var c: Vector2 = s["center"]
	var lines: Array = []
	for t in owned_roads(s):
		lines.append(road_points(s, t))
	var sx: int = s["sx"]
	var sz: int = s["sz"]
	for o in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(-2, 0), Vector2i(0, -2)]:
		var n := settlement_at(sx + o.x, sz + o.y)
		if n.is_empty():
			continue
		for t in owned_roads(n):
			if t["sx"] == sx and t["sz"] == sz:
				var pts := road_points(n, t)
				var rev := PackedVector2Array()
				for i in range(pts.size() - 1, -1, -1):
					rev.append(pts[i])
				lines.append(rev)
	var out: Array = []
	for pts in lines:
		for i in range(1, pts.size()):
			var d0: float = (pts[i - 1] as Vector2).distance_to(c)
			var d1: float = (pts[i] as Vector2).distance_to(c)
			if d0 < rad and d1 >= rad:
				var p: Vector2 = (pts[i - 1] as Vector2).lerp(pts[i], (rad - d0) / maxf(d1 - d0, 0.001))
				out.append((p - c).angle())
				break
	return out

func road_angles(s: Dictionary) -> Array:
	var out: Array = []
	for t in owned_roads(s):
		var pts := road_points(s, t)
		out.append((pts[mini(4, pts.size() - 1)] - pts[0]).angle())
	var sx: int = s["sx"]
	var sz: int = s["sz"]
	for o in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(-2, 0), Vector2i(0, -2)]:
		var n := settlement_at(sx + o.x, sz + o.y)
		if n.is_empty():
			continue
		for t in owned_roads(n):
			if t["sx"] == sx and t["sz"] == sz:
				var pts := road_points(n, t)
				var e := pts.size() - 1
				out.append((pts[maxi(e - 4, 0)] - pts[e]).angle())
	return out

## v7: the hidden landmark at the heart of a landform region (see Landmark), placed by
## the chunk that holds the region's site: on the highest point near it for towers and
## isles, the lowest for craters, sinkholes and gorges, else the flattest, with a cache
## of rich loot beside it.
func _place_landmark(chunk: Dictionary, sites: Array, origin: Dictionary) -> void:
	var x0 := float(chunk["cx"] * SIZE)
	var z0 := float(chunk["cz"] * SIZE)
	var ix := int(floor(x0 / WorldField.ERA_CELL))
	var iz := int(floor(z0 / WorldField.ERA_CELL))
	var site := field.site_pos(ix, iz)
	if site.x < x0 or site.x >= x0 + SIZE or site.y < z0 or site.y >= z0 + SIZE:
		return
	var lf := field.site_landform(ix, iz)
	if not Landmark.BY_LANDFORM.has(lf) or field.landform_weights(site.x, site.y)[lf] < 0.9:
		return
	var what: Array = Landmark.BY_LANDFORM[lf]
	var t: String = what[0]
	var mode: String = what[1]
	var margin := 12.0 if t == "dolmen" or t == "star_wreck" or t == "titan_bones" or t == "caravan" else 5.0
	var best := Vector2.INF
	var score := INF
	var sl := site - Vector2(x0, z0)
	for j in range(int(margin), int(SIZE - margin) + 1, 2):
		for i in range(int(margin), int(SIZE - margin) + 1, 2):
			var p := Vector2(i, j)
			# (A lake isle can be anywhere in the chunk; the rest stay near the heart.)
			if p.distance_to(sl) > (90.0 if t == "watchtower" else 30.0):
				continue
			var h := height_at(chunk, i, j)
			if h < WATER_LEVEL + 0.4 or road_at(chunk, i, j) > 0.0 or by_river(chunk, i, j) or _near_settlement(x0 + i, z0 + j, sites, 30.0):
				continue
			var sc: float
			match mode:
				"high": sc = -h + slope_at(chunk, i, j) * 4.0
				"low": sc = h + slope_at(chunk, i, j) * 4.0
				_: sc = slope_at(chunk, i, j) * 20.0 + p.distance_to(sl) * 0.05
			if sc < score:
				score = sc
				best = p
	if best == Vector2.INF:
		return
	var r := WHash.rng(seed, chunk["cx"], chunk["cz"], 307)
	var yaw := r.randf() * TAU
	var era := WorldField.dominant(weights_at(chunk, best.x, best.y))
	match t:
		"caravan":
			_add(chunk, "wagon", era, best.x, best.y, yaw, 1.0)
			var bp := best + Vector2(3.2, 0).rotated(-yaw)
			_add(chunk, "barrels", era, bp.x, bp.y, yaw + 0.6, 1.0)
		"dolmen":
			_add(chunk, t, era, best.x, best.y, yaw, 1.0)
			for n in 7:
				var sp := best + Vector2(7.0, 0).rotated(yaw + n * TAU / 7.0)
				_add(chunk, "standing_stone", era, sp.x, sp.y, r.randf() * TAU, r.randf_range(0.8, 1.1), {}, r.randi() & 0x7FFFFFFF, 0)
		"fallen_star":
			_add(chunk, t, era, best.x, best.y, yaw, 1.0)
			var op := best + Vector2(3.6, 0).rotated(-yaw + 2.0)
			if Eras.theme == "human":
				# A human world's fallen star leaves plain meteoric iron, not living crystal.
				_add(chunk, "iron_vein", Eras.MEDIEVAL, op.x, op.y, r.randf() * TAU, 1.6, {"left": 14, "progress": 0.0}, r.randi() & 0x7FFFFFFF, 0)
			else:
				_add(chunk, "aether_crystal", Eras.FANTASY, op.x, op.y, r.randf() * TAU, 1.6, {"left": 14, "progress": 0.0}, r.randi() & 0x7FFFFFFF, 0)
		_:
			_add(chunk, t, era, best.x, best.y, yaw, 1.0)
	# The prize: deep-dungeon odds, waiting beside (or on) the landmark.
	var off: Vector2 = {"summit_shrine": Vector2(0, 0.9), "eyrie": Vector2(0.6, 0), "sunken_altar": Vector2(0, 1.4),
		"star_wreck": Vector2(4.8, 0), "titan_bones": Vector2(2.6, 1.0), "watchtower": Vector2(3.6, 0)}.get(t, Vector2(0, 2.6))
	var cp := best + off.rotated(-yaw)
	cp = cp.clamp(Vector2(1, 1), Vector2(SIZE - 1, SIZE - 1))
	var o := origin.duplicate()
	o["era"] = era
	o["how"] = "found"
	_add(chunk, Eras.CACHE_TYPES[era], era, cp.x, cp.y, yaw, 1.0, {"loot": ItemDB.roll_loot(era, r, o, 0.75), "opened": false, "landmark": t})

func _place_settlement(chunk: Dictionary, s: Dictionary, x0: float, z0: float) -> void:
	var era: int = s["era"]
	for it in settlement_layout(s):
		var p: Vector2 = it["p"]
		if p.x >= x0 and p.x < x0 + SIZE and p.y >= z0 and p.y < z0 + SIZE:
			if it["t"] == Eras.CACHE_TYPES[era]:
				for l in it["st"]["loot"]:
					if l.get("origin") is Dictionary:
						l["origin"]["chunk"] = Vector2i(int(chunk["cx"]), int(chunk["cz"]))
			_add(chunk, it["t"], era, p.x - x0, p.y - z0, it["yaw"], 1.0, it["st"])
