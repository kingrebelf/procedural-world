class_name ChunkGenerator
extends RefCounted
## Turns (seed, cx, cz) into a complete chunk snapshot. Pure and deterministic: no
## globals, no clock (except the `created` stamp). Safe to run on worker threads as long
## as each thread uses its own generator instance.

const GEN_VERSION := 4 ## 2: per-region biomes and parametric species. 3: rivers (new worlds). 4: highlands and mesas.
const FORMAT := 1
const SIZE := 64
const RES := SIZE + 1
const SETTLEMENT_CELL := 256.0
const SETTLEMENT_CHANCE := 0.35
const FLAT_INNER := 30.0
const FLAT_OUTER := 54.0
const WATER_LEVEL := 0.0 ## Must match Water.LEVEL.

var field: WorldField
var seed: int
## Rivers are carved only in worlds created with them, so chunks generated later in an
## older world still meet the ones already saved.
var rivers := false
## v4 worlds: settlements come in sizes (hamlet, village, town) joined by roads.
var towns := false
var _site_cache := {}
var _road_cache := {}

## Flat radii [inner, outer] for hamlets, villages and towns (v4 worlds).
const SITE_RADII := [[30.0, 54.0], [42.0, 66.0], [56.0, 80.0]]
const MAX_OUTER := 80.0
const ROAD_HALF := 2.4 ## half-width of the beaten surface
const ROAD_STEP := 4.0 ## spacing of road centreline points
const ROAD_REACH := 18.0 ## furthest the land eases toward a road

func _init(world_seed: int, with_rivers := false) -> void:
	seed = world_seed & WHash.MASK
	field = WorldField.new(seed)
	rivers = with_rivers
	towns = WorldField.terrain_v >= 4

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
	var th := field.height(c.x, c.y, w)
	if th < WATER_LEVEL + 1.5:
		return {}
	var size := 0
	if towns:
		var r := WHash.unit2(seed, sx, sz, 204)
		size = 2 if r < 0.15 else (1 if r < 0.5 else 0)
	return {"center": c, "era": era, "target_h": th, "sx": sx, "sz": sz,
		"size": size, "inner": SITE_RADII[size][0], "outer": SITE_RADII[size][1]}

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
	var key := Vector4i(a["sx"], a["sz"], b["sx"], b["sz"])
	if _road_cache.has(key):
		return _road_cache[key]
	var pa: Vector2 = a["center"]
	var pb: Vector2 = b["center"]
	var length := pa.distance_to(pb)
	var n := maxi(2, int(ceil(length / ROAD_STEP)))
	var perp := (pb - pa).orthogonal().normalized()
	var bend := (WHash.unit2(seed, a["sx"] * 7 + b["sx"], a["sz"] * 7 + b["sz"], 205) - 0.5) * 0.36 * length
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var p := pa.lerp(pb, t) + perp * sin(PI * t) * bend
		p += perp * field._rwarp.get_noise_2d(p.x * 1.7, p.y * 1.7) * 16.0 * sin(PI * t)
		pts.append(p)
	_road_cache[key] = pts
	return pts

## Every road whose verge reaches the rectangle.
func roads_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out: Array = []
	if not towns:
		return out
	var m := 2.0 * SETTLEMENT_CELL + 150.0
	var area := Rect2(x0 - ROAD_REACH - 1.0, z0 - ROAD_REACH - 1.0, x1 - x0 + 2.0 * ROAD_REACH + 2.0, z1 - z0 + 2.0 * ROAD_REACH + 2.0)
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
						out.append(pts)
	return out

## Smoothed land height along a road at point i (the level its surface is laid at).
func _road_level(pts: PackedVector2Array, i: int, raw: Dictionary) -> float:
	var sum := 0.0
	for o in range(-3, 4):
		var j := clampi(i + o, 0, pts.size() - 1)
		if not raw.has(j):
			raw[j] = field.height(pts[j].x, pts[j].y)
		sum += raw[j]
	return sum / 7.0

## For every vertex of the chunk near a road: [distance to the centreline, road level].
func _road_field(x0: float, z0: float, roads: Array) -> Array:
	var dist := PackedFloat32Array()
	var level := PackedFloat32Array()
	dist.resize(RES * RES)
	dist.fill(INF)
	level.resize(RES * RES)
	var area := Rect2(x0 - ROAD_REACH, z0 - ROAD_REACH, SIZE + 2.0 * ROAD_REACH, SIZE + 2.0 * ROAD_REACH)
	for pts in roads:
		var raw := {}
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not Rect2(a, Vector2.ZERO).expand(b).intersects(area):
				continue
			var ha := _road_level(pts, i, raw)
			var hb := _road_level(pts, i + 1, raw)
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.0001)
			var i0 := clampi(int(floor(minf(a.x, b.x) - ROAD_REACH - x0)), 0, RES - 1)
			var i1 := clampi(int(ceil(maxf(a.x, b.x) + ROAD_REACH - x0)), 0, RES - 1)
			var j0 := clampi(int(floor(minf(a.y, b.y) - ROAD_REACH - z0)), 0, RES - 1)
			var j1 := clampi(int(ceil(maxf(a.y, b.y) + ROAD_REACH - z0)), 0, RES - 1)
			for j in range(j0, j1 + 1):
				for ii in range(i0, i1 + 1):
					var q := Vector2(x0 + ii, z0 + j)
					var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
					var d := q.distance_to(a + ab * t)
					var k := j * RES + ii
					if d < dist[k]:
						dist[k] = d
						level[k] = lerpf(ha, hb, t)
	return [dist, level]

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
	for j in CN:
		for i in CN:
			coarse.append(field.era_weights(x0 + i * STEP, z0 + j * STEP))
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
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
			var h := field.height(x, z, w)
			var on_road := 0.0
			if not rf.is_empty() and rf[0][k] < ROAD_REACH:
				var d: float = rf[0][k]
				var lv: float = rf[1][k]
				# Not across lakes or the sea; the land eases down (or up) to the road's
				# level over a verge that widens with the height it has to make up.
				var dry := smoothstep(WATER_LEVEL + 0.2, WATER_LEVEL + 1.2, lv)
				var verge := ROAD_HALF + 2.0 + minf(absf(h - lv) * 0.9, ROAD_REACH - ROAD_HALF - 2.0)
				h = lerpf(h, lv, (1.0 - smoothstep(ROAD_HALF, verge, d)) * dry)
				on_road = (1.0 - smoothstep(ROAD_HALF - 0.8, ROAD_HALF + 1.0, d)) * dry
			if towns:
				for st in sites:
					var dc := Vector2(x, z).distance_to(st["center"])
					on_road = maxf(on_road, 1.0 - smoothstep(7.0 + st["size"] * 3.0, 11.0 + st["size"] * 4.0, dc))
				if on_road > 0.0:
					road_mask[k] = int(round(on_road * 255.0))
					any_road = true
			if has_river:
				var t := field.river_t(x, z)
				var lv := field.river_level(x, z, level_cache)
				var m := WorldField.river_strength(h, lv)
				for st in sites:
					m *= smoothstep(st["outer"], st["outer"] + 30.0, Vector2(x, z).distance_to(st["center"]))
				h = WorldField.carve_river(h, t, lv, m)
				if i % 2 == 0 and j % 2 == 0:
					var rk := ((j / 2) * RIVER_N + i / 2) * 3
					river[rk] = lv
					river[rk + 1] = t
					river[rk + 2] = m
			heights[k] = _flatten(x, z, h, sites)
			for e in Eras.COUNT:
				weights[k * Eras.COUNT + e] = int(round(w[e] * 255.0))
	var center_w := field.era_weights(x0 + SIZE * 0.5, z0 + SIZE * 0.5)
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
	if any_road:
		chunk["road"] = road_mask
	_place_objects(chunk, sites)
	return chunk

static func _crowds_tree(chunk: Dictionary, lx: float, lz: float, gap: float) -> bool:
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) == "tree" and Vector2(o["p"].x - lx, o["p"].z - lz).length() < gap:
			return true
	return false

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
		if Vector2(x, z).distance_to(s["center"]) < float(s["inner"]) + extra:
			return true
	return false

func _place_objects(chunk: Dictionary, sites: Array) -> void:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var origin := {"chunk": Vector2i(cx, cz)}

	# Settlements first so they claim their space.
	for s in sites:
		_place_settlement(chunk, s, x0, z0)

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
		if roll >= p or slope_at(chunk, lx, lz) > 0.75 or height_at(chunk, lx, lz) < WATER_LEVEL + 0.4 or by_river(chunk, lx, lz) or _near_settlement(x0 + lx, z0 + lz, sites, 6.0) or road_at(chunk, lx, lz) > 0.15:
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
		if _near_settlement(x0 + lx, z0 + lz, sites, 0.0) or road_at(chunk, lx, lz) > 0.15 or height_at(chunk, lx, lz) < WATER_LEVEL - 1.5 or by_river(chunk, lx, lz):
			continue
		var bp := Biome.params(field.region_hash_at(x0 + lx, z0 + lz), era)
		var rd: float = Eras.ROCK_DENSITY[era] * float(bp["rock_density"])
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
	if r.randf() < 0.035:
		var lx := r.randf_range(10, SIZE - 10)
		var lz := r.randf_range(10, SIZE - 10)
		var sp := r.randi() & 0x7FFFFFFF
		var yaw := r.randf() * TAU
		if not _near_settlement(x0 + lx, z0 + lz, sites, 34.0) or road_at(chunk, lx, lz) > 0.0 and height_at(chunk, lx, lz) > WATER_LEVEL + 0.5 and not by_river(chunk, lx, lz) and slope_at(chunk, lx, lz) < 0.4:
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
	if towns:
		_town_rings(s, r, kit, items)
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

## Directions (radians, as Vector2.angle) in which roads leave a settlement's square.
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
