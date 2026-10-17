class_name MarketCrowd
## Folk in from the farms and hamlets round about: market-goers who browse the stalls and
## shop doors, and idlers who stand about the square in twos and threes passing the time.
## They come in by the roads through the morning, are thickest around midday, a few linger
## into the evening by the tavern, and by nightfall they have all gone home. They are not
## townsfolk: nothing about them is saved, and the same people come on the same day
## (seeded by the town and the day), so every player in a game sees the same crowd.
##
## Their day out is a duty like any trade's (NPCRoles "browse", "loiter", "tavern_night",
## "head_home"), so the decision engine, fear, the player and conversation all work on
## them as on anyone else.

const BASE := [7, 10, 14] ## visitors per day, by town size
const NEAR := 130.0 ## they only come while you are this close to the town (they cost frames)
const LEAVE := 0.35 ## hours before the end of their visit they set off for the road

## The day's visitors to a town: person recs, each with "visit": [from hour, to hour,
## duty] and a gate they came by (their "home").
static func roster(site: Dictionary, era: int, day: int, gates: Array) -> Array:
	var out: Array = []
	if gates.is_empty():
		return out
	var sx := int(site["sx"])
	var sz := int(site["sz"])
	var r := RandomNumberGenerator.new()
	r.seed = hash([sx, sz, day, "crowd"])
	r.randf()
	var n: int = BASE[clampi(int(site.get("size", 0)), 0, BASE.size() - 1)] + r.randi_range(-1, 2)
	for i in n:
		var p := NPCGen.person(r, era, i, sx, sz)
		for _try in 8: # children come with their families, not alone
			if not p.get("child", false):
				break
			p = NPCGen.person(r, era, i, sx, sz)
		p["id"] = "v%d_%d_%d_%d" % [sx, sz, day, i]
		var kind := r.randf()
		var from: float
		var to: float
		var duty: String
		if kind < 0.55:
			# Market-goers: in through the morning, a good few hours at the stalls.
			from = r.randf_range(7.5, 12.0)
			to = minf(from + r.randf_range(2.5, 5.5), 18.5)
			duty = "browse"
			p["job"] = "market-goer" if era != Eras.SCIFI else "trader from the outlying habs"
		elif kind < 0.85:
			# Idlers: the middle of the day in the square.
			from = r.randf_range(9.5, 13.0)
			to = minf(from + r.randf_range(3.0, 6.5), 19.5)
			duty = "loiter"
			p["job"] = "visitor" if era != Eras.SCIFI else "drifter"
		else:
			# Evening company for the tavern.
			from = r.randf_range(17.0, 19.0)
			to = r.randf_range(20.5, 22.0)
			duty = "tavern_night"
			p["job"] = "visitor" if era != Eras.SCIFI else "drifter"
		p["visit"] = [snappedf(from, 0.01), snappedf(to, 0.01), duty]
		var g: Vector2 = gates[r.randi() % gates.size()]
		p["home"] = g
		p["work"] = g
		p["pos"] = Vector3(g.x, 0.0, g.y)
		p["rel"] = 0
		p["traits"]["friendly"] = snappedf(0.35 + r.randf() * 0.6, 0.01)
		out.append(p)
	return out

## Whether a visitor is in town (or on their way out) at `hour`.
static func here(rec: Dictionary, hour: float) -> bool:
	var v: Array = rec["visit"]
	return hour >= float(v[0]) and hour < float(v[1]) + 0.5

## The duty block a visitor is in at `hour` (NPCRoles.block), or [].
static func block(rec: Dictionary, hour: float) -> Array:
	var v: Array = rec["visit"]
	var to := float(v[1])
	if hour >= float(v[0]) and hour < to - LEAVE:
		return [float(v[0]), to - LEAVE, String(v[2])]
	if hour >= to - LEAVE and hour < to + 0.5:
		return [to - LEAVE, to + 0.5, "head_home"]
	return []

## Where the idlers stand about: a few spots round the square, each a little knot of
## people (stable per town).
static func knots(places: Dictionary) -> Array:
	var c: Vector2 = places["center"]
	var inner := float(places.get("inner", 30.0))
	var out: Array = []
	var a0 := float(absi(hash(c)) % 628) / 100.0
	var avoid: Array = (places.get("market", []) as Array) + (places.get("stall", []) as Array) + (places.get("wells", []) as Array)
	for k in 5:
		var a := a0 + TAU * float(k) / 5.0
		var p := c + Vector2.from_angle(a) * clampf(inner * (0.18 + 0.07 * float(k % 3)), 4.5, 11.0)
		# Not in a stall's way, nor on a chest or a well.
		for q in avoid:
			if p.distance_to(q) < 3.0:
				p += (p - (q as Vector2)).normalized() * (3.0 - p.distance_to(q))
		out.append(NPCRoles.clear_spot(places, p, 1.6))
	return out

## Where market-goers browse: stalls, carts, and the doors of the shops.
static func browse_spots(places: Dictionary) -> Array:
	var out: Array = (places.get("market", []) as Array) + (places.get("stall", []) as Array)
	for y in (places.get("shop_yards", {}) as Dictionary).values():
		out.append(y[0])
	return out
