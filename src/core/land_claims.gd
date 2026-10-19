class_name LandClaims
extends RefCounted
## Land you have claimed: one generated tile each (a 64 m chunk, ChunkGenerator.SIZE),
## kept by paying its upkeep to the nearest town or stronghold every in-game day. The
## upkeep comes out of your purse at the turn of each day (and, for days you were away,
## when you come back); more than GRACE days behind and the land is no longer yours.
## Each day's upkeep paid to a town counts a little to your standing there.
##
## Online the server keeps everyone's claims (ServerClaims), so no tile has two owners,
## and only the owner and their alliance may build on a claimed tile.
##
## Tiles are keyed by planet and chunk coords (tile_key). A finite globe world (plans/
## globe-world.md) keeps the same coords and only wraps them, so claims follow it.

const GRACE := 2 ## days behind before a claim lapses
const DEED_DAYS := 3 ## the deed costs this many days' upkeep, on top of the first day's
const MAX := 4 ## claims you may hold (a server sets its own: claim_limit)
const PREPAY_MAX := 30 ## days ahead you may pay
const SEAT_REACH := 1600.0 ## furthest a town or stronghold collects from (metres)

## key -> {planet, cx, cz, seat (a town's sid or "fort:cx_cz"), seat_name, seat_kind
## ("town"/"fort"), sx, sz (where it is), rate (Marks a day), paid (the last day paid
## for), since (day claimed), total (Marks paid)}
var list: Dictionary = {}
## Online: everyone's claims as the server has them, key -> [pid, name] (not saved).
var others: Dictionary = {}
## Online: claims asked of the server and not answered yet, key -> the record to keep.
var pending: Dictionary = {}

## The tile a world point is on.
static func tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / ChunkGenerator.SIZE), floori(z / ChunkGenerator.SIZE))

static func tile_key(planet: int, t: Vector2i) -> String:
	return "%d:%d:%d" % [planet, t.x, t.y]

## The middle of a tile, in world x, z.
static func tile_center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * ChunkGenerator.SIZE

static func tile_rect(t: Vector2i) -> Rect2:
	return Rect2(Vector2(t) * ChunkGenerator.SIZE, Vector2.ONE * ChunkGenerator.SIZE)

static func today(day: float) -> int:
	return floori(day)

# --- Who holds a tile ---------------------------------------------------------------------

func mine(planet: int, t: Vector2i) -> Dictionary:
	return list.get(tile_key(planet, t), {})

## Who holds a tile: [pid, name] ("you" for your own), or [] when nobody does.
func owner_of(planet: int, t: Vector2i, my_id := "solo") -> Array:
	var k := tile_key(planet, t)
	if list.has(k):
		return [my_id, "you"]
	var o = others.get(k)
	return o if o is Array and String(o[0]) != my_id else []

func count() -> int:
	return list.size()

func on_planet(planet: int) -> Array:
	return list.values().filter(func(c): return int(c["planet"]) == planet)

# --- Making a claim -----------------------------------------------------------------------

## Who would collect a tile's upkeep: the nearest town or stronghold within SEAT_REACH,
## as {seat, seat_name, seat_kind, sx, sz, dist}, or {} when there is none.
static func seat_for(gen: ChunkGenerator, planet: int, t: Vector2i) -> Dictionary:
	var c := tile_center(t)
	var best := {}
	var bd := SEAT_REACH
	var r := SEAT_REACH
	for s in gen.settlements_near(c.x - r, c.y - r, c.x + r, c.y + r):
		var d := c.distance_to(s["center"])
		if d < bd:
			bd = d
			var sc: Vector2 = s["center"]
			best = {"seat": "%d:%s" % [planet, NPCGen.settlement_id(int(s["sx"]), int(s["sz"]))],
				"seat_name": gen.field.region_name_at(sc.x, sc.y), "seat_kind": "town", "sx": sc.x, "sz": sc.y, "dist": d}
	# Strongholds nearer than any town (looked for closer in: they are costlier to find).
	r = minf(bd, 900.0)
	for f in gen.forts_near(c.x - r, c.y - r, c.x + r, c.y + r):
		var d := c.distance_to(f["center"])
		if d < bd:
			bd = d
			var fc: Vector2 = f["center"]
			best = {"seat": "fort:%d_%d" % [int(f["cx"]), int(f["cz"])],
				"seat_name": "%s of %s" % [Stronghold.NAMES[clampi(int(f["era"]), 0, 2)], gen.field.region_name_at(fc.x, fc.y)],
				"seat_kind": "fort", "sx": fc.x, "sz": fc.y, "dist": d}
	return best

## A tile's upkeep in Marks a day: dearer in higher-level land and close to its seat.
static func rate_for(t: Vector2i, seat_dist: float, mult := 1.0) -> int:
	var c := tile_center(t)
	var lv := ZoneInfo.level_at(c.x, c.y)
	var near := 1.5 if seat_dist < 300.0 else (1.2 if seat_dist < 700.0 else 1.0)
	return maxi(1, roundi((4.0 + lv * 0.5) * near * mult))

## What claiming a tile costs now: the deed and the first day's upkeep.
static func cost_of(rate: int) -> int:
	return rate * (DEED_DAYS + 1)

## Why a tile can't be claimed ("" when it can), and its offer: the record a claim would
## keep (in `out`, when given).
func check(gen: ChunkGenerator, planet: int, t: Vector2i, day: float, limit := MAX, mult := 1.0, my_id := "solo", out := {}) -> String:
	var k := tile_key(planet, t)
	if list.has(k):
		return "This land is already yours"
	var o := owner_of(planet, t, my_id)
	if not o.is_empty():
		return "This land is claimed by %s" % o[1]
	if pending.has(k):
		return "Your claim is being registered"
	if list.size() + pending.size() >= limit:
		return "You hold as much land as you may (%d tiles)" % limit
	var rect := tile_rect(t)
	var c := tile_center(t)
	for s in gen.settlements_near(rect.position.x, rect.position.y, rect.end.x, rect.end.y):
		if _rect_dist(rect, s["center"]) < float(s["outer"]):
			var sc: Vector2 = s["center"]
			return "This is %s's own ground: its land office sells houses" % gen.field.region_name_at(sc.x, sc.y)
	for f in gen.forts_near(rect.position.x, rect.position.y, rect.end.x, rect.end.y):
		if _rect_dist(rect, f["center"]) < float(f["outer"]):
			return "A stronghold's ground can't be claimed"
	var wet := 0
	for p in [c, rect.position + Vector2(4, 4), rect.position + Vector2(60, 4), rect.position + Vector2(4, 60), rect.end - Vector2(4, 4)]:
		if gen.field.height(p.x, p.y, gen.field.era_weights(p.x, p.y)) < ChunkGenerator.WATER_LEVEL:
			wet += 1
	if wet >= 4:
		return "Open water can't be claimed"
	var seat := seat_for(gen, planet, t)
	if seat.is_empty():
		return "No town or stronghold is near enough to register a claim"
	var rate := rate_for(t, float(seat["dist"]), mult)
	out.merge({"planet": planet, "cx": t.x, "cz": t.y, "seat": seat["seat"], "seat_name": seat["seat_name"],
		"seat_kind": seat["seat_kind"], "sx": seat["sx"], "sz": seat["sz"], "rate": rate,
		"paid": today(day), "since": snappedf(day, 0.01), "total": cost_of(rate)}, true)
	return ""

static func _rect_dist(r: Rect2, p: Vector2) -> float:
	return p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))

## Keeps a claim (its cost already paid).
func add(rec: Dictionary) -> void:
	var k := tile_key(int(rec["planet"]), Vector2i(int(rec["cx"]), int(rec["cz"])))
	pending.erase(k)
	list[k] = rec

func remove(k: String) -> void:
	list.erase(k)
	pending.erase(k)

# --- Upkeep -------------------------------------------------------------------------------

## Days a claim is paid ahead (+) or behind (-) of `day`.
static func standing_days(rec: Dictionary, day: float) -> int:
	return int(rec["paid"]) - today(day)

## Pays up to `days` more of a claim's upkeep from `purse`; returns what it cost.
static func prepay(rec: Dictionary, days: int, purse: int, day: float) -> int:
	var room := today(day) + PREPAY_MAX - int(rec["paid"])
	var n := mini(mini(days, room), purse / maxi(1, int(rec["rate"])))
	if n <= 0:
		return 0
	rec["paid"] = int(rec["paid"]) + n
	rec["total"] = int(rec.get("total", 0)) + n * int(rec["rate"])
	return n * int(rec["rate"])

## Settles every claim's upkeep for the days up to `day` from `purse`, oldest day first.
## Returns {spent, paid: [[key, days]], behind: [[key, days]], lapsed: [records]}.
## Lapsed claims are taken off the list.
func settle(day: float, purse: int) -> Dictionary:
	var out := {"spent": 0, "paid": [], "behind": [], "lapsed": []}
	var now := today(day)
	var keys := list.keys()
	keys.sort_custom(func(a, b): return int(list[a]["paid"]) < int(list[b]["paid"]))
	for k in keys:
		var rec: Dictionary = list[k]
		var rate := maxi(1, int(rec["rate"]))
		var days := 0
		while int(rec["paid"]) < now and purse - out["spent"] >= rate:
			rec["paid"] = int(rec["paid"]) + 1
			rec["total"] = int(rec.get("total", 0)) + rate
			out["spent"] += rate
			days += 1
		if days > 0:
			out["paid"].append([k, days])
		var behind := now - int(rec["paid"])
		if behind > GRACE:
			out["lapsed"].append(rec)
			list.erase(k)
		elif behind > 0:
			out["behind"].append([k, behind])
	return out

# --- Saving -------------------------------------------------------------------------------

func to_data() -> Array:
	return list.values().duplicate(true)

static func from_data(d) -> LandClaims:
	var c := LandClaims.new()
	if d is Array:
		for e in d:
			if e is Dictionary and e.has("cx") and e.has("cz") and e.has("rate") and e.has("paid"):
				var rec: Dictionary = e.duplicate(true)
				for f in ["planet", "cx", "cz", "rate", "paid", "total"]:
					rec[f] = int(rec.get(f, 0))
				c.list[tile_key(rec["planet"], Vector2i(rec["cx"], rec["cz"]))] = rec
	return c
