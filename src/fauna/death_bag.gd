class_name DeathBag
## The bag you drop when you die: everything you carried, wore and had in your purse,
## left where you fell (on the nearest dry ground if that was in water). It lies in its
## chunk's snapshot with the bodies (Corpses, kind "bag"), so it outlasts the chunk
## unloading and the game closing, and anyone who finds it can open it. Your map marks
## each bag of yours until it is emptied or found gone.
##
## Record (on top of what Corpses keeps for every body: p, day, yaw): kind "bag", owner
## (the dead player's id, Game.my_id), owner_name ("" offline), items (Inventory
## data), worn (armour slot -> the uid of the piece worn there, to put it back on),
## purse (Marks), unix (real time of death). Things you drop on purpose to lighten your
## pack lie in the same kind of bag with "dropped": true (Corpses.drop_items).
##
## Pure functions and two hooks for a multiplayer server: `lifetime_s` (0 = bags never
## go away) and `may_take` (who may open a bag; everyone, by default: Ben wants other
## players able to steal it). The server option "death_penalty" ("keep") turns bags off.

## Room for a starting-size pack plus every piece of armour; a bigger pack makes a bigger
## bag (make), and Corpses.slots_of opens it at the size it was saved.
const SLOTS := Inventory.SIZE + 10
## Furthest a bag is moved to find dry ground when you die in the water.
const DRY_SEARCH := 160.0
## Height above the water a spot must be to count as dry.
const DRY_MARGIN := 0.35

## Real seconds a bag lasts before it is gone; 0 keeps it until someone empties it.
static var lifetime_s := 0.0
## Server hook: func(rec: Dictionary, taker: String) -> bool, whether `taker` may open
## this bag. Unset, anyone may.
static var may_take: Callable

## A bag holding everything in `inv`, the armour in `equipment` (slot -> item) and
## `money` Marks, dropped by player `owner` (named `name`).
static func make(owner: String, name: String, inv: Inventory, equipment: Dictionary, money: int, unix: float) -> Dictionary:
	var bag := Inventory.new(maxi(SLOTS, inv.capacity + 10))
	var worn := {}
	for slot in equipment:
		var it = equipment[slot]
		if not it is Dictionary:
			continue
		if bag.add(it) == 0:
			worn[slot] = int(_last_uid(bag, it))
	for i in inv.capacity:
		var it = inv.get_slot(i)
		if it is Dictionary:
			bag.add(it)
	return {"kind": "bag", "owner": owner, "owner_name": name, "items": bag.to_data(), "worn": worn,
		"purse": maxi(money, 0), "unix": unix}

## The uid the bag gave the piece just added (it keeps the one it had, if any).
static func _last_uid(bag: Inventory, it: Dictionary) -> int:
	if int(it.get("uid", 0)) != 0:
		return int(it["uid"])
	for i in range(bag.capacity - 1, -1, -1):
		var s = bag.get_slot(i)
		if s is Dictionary and s["type"] == it["type"]:
			return int(s["uid"])
	return 0

static func is_bag(c: Dictionary) -> bool:
	return c.get("kind", "") == "bag"

static func is_mine(c: Dictionary, me: String) -> bool:
	return is_bag(c) and String(c.get("owner", "")) == me

## Whether `taker` may open this bag (always, unless a server says otherwise).
static func can_take(c: Dictionary, taker: String) -> bool:
	return not may_take.is_valid() or bool(may_take.call(c, taker))

## True once the bag has outlived `lifetime_s` (never, while that is 0).
static func expired(c: Dictionary, now_unix: float) -> bool:
	return lifetime_s > 0.0 and now_unix - float(c.get("unix", now_unix)) >= lifetime_s

## What it is called: "Your bag", "Ada's bag".
static func title(c: Dictionary, me: String) -> String:
	if is_mine(c, me):
		return "Your dropped things" if c.get("dropped", false) else "Your bag"
	var n := String(c.get("owner_name", "")).strip_edges()
	return ("%s's bag" % n.split(" ")[0]) if n != "" else "Someone's bag"

## Where a bag dropped at `at` comes to rest: there, if that is above the water, else
## the nearest dry ground within DRY_SEARCH. `ground(x, z)` is the terrain height (NAN
## where unknown) and `water(x, z)` the water level there (NAN or below the ground where
## it is dry). Falls back to the water's surface when there is no dry land in reach.
static func rest_spot(at: Vector3, ground: Callable, water: Callable) -> Vector3:
	var lv: float = water.call(at.x, at.z)
	if is_nan(lv) or at.y >= lv + DRY_MARGIN:
		return at
	var r := 3.0
	while r <= DRY_SEARCH:
		var best := Vector3.INF
		var n := maxi(8, int(TAU * r / 4.0))
		for i in n:
			var a := TAU * float(i) / float(n)
			var x := at.x + cos(a) * r
			var z := at.z + sin(a) * r
			var g: float = ground.call(x, z)
			if is_nan(g):
				continue
			var w: float = water.call(x, z)
			if not is_nan(w) and g < w + DRY_MARGIN:
				continue
			# Of the dry spots this far out, the one lowest down (the shore, not a cliff top).
			if best == Vector3.INF or g < best.y:
				best = Vector3(x, g, z)
		if best != Vector3.INF:
			return best
		r += 3.0 if r < 30.0 else 8.0
	return Vector3(at.x, lv, at.z)
