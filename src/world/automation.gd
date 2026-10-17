class_name Automation
## Automation (stage 4 of the power system): conveyor belts, hoppers, robot arms and the
## powered machines that fill and empty them: an auto-miner on an ore vein, a quarry
## drill, an electric furnace, a powered sawmill, an assembler. They are powered pieces
## (Power) whose "auto" spec says what they do:
##   belt:      {speed (m/s)}: carries items one by one along its local +z
##   hopper:    {}: a box that tips out of its +z side whatever is put in it
##   arm:       {every}: takes from what is behind it (-z) and puts in what is in front (+z)
##   miner:     {every, reach}: drills the ore vein or rock it stands by, forever, slowly
##   quarry:    {every}: digs stone (and what is in it) out of the ground under it
##   smelter / sawmill / assembler: {every}: runs a recipe on what is put in it
## Everything with a store ("storage" slots in its BuildCatalog def: chests, crates and
## the machines) can be fed by a belt or an arm; a machine pushes what it makes out of its
## +z side, onto a belt or into whatever stands there. Items move one at a time.
## State, saved with the chunk: items (the store, as Storage keeps it), q (a belt's items:
## [[item, how far along 0..1], ...]), flt (an arm's filter item type), rc (an assembler's
## recipe index), mt (a machine's work so far, s), pt (Game.day it last ran).
## Machines and belts only run on the game that runs their chunk's animals, so an item
## moves once; they catch up on time away when they load again, capped by their room.

const GAP := 0.34 ## the least a belt keeps between two items, of its length
const PUSH_EVERY := 0.5 ## s between a machine's pushes onto a belt
const CATCH_UP_MAX := 1200 ## at most this many work cycles made up for time away

static func spec(o: Dictionary) -> Dictionary:
	return Power.spec(o).get("auto", {})

static func kind(o: Dictionary) -> String:
	return String(spec(o).get("kind", ""))

static func is_auto(o: Dictionary) -> bool:
	return not spec(o).is_empty()

## A piece items can be put in or taken from: a belt, or anything with a store.
static func is_container(t: String) -> bool:
	if not BuildCatalog.is_built(t):
		return false
	var d := BuildCatalog.def(BuildCatalog.id_of(t))
	return int(d.get("storage", 0)) > 0 or String(d.get("power", {}).get("auto", {}).get("kind", "")) == "belt"

## Its out side, in world space: a point `ahead` metres along its local +z.
static func ahead_of(o: Dictionary, origin: Vector3, ahead: float) -> Vector3:
	return origin + o["p"] + Basis(Vector3.UP, float(o["r"])) * Vector3(0, 0, ahead)

static func forward(o: Dictionary) -> Vector3:
	return Basis(Vector3.UP, float(o["r"])) * Vector3(0, 0, 1)

## How far out of its middle its sides are (for which piece stands at a point).
static func reach(o: Dictionary) -> float:
	if kind(o) == "belt":
		return 0.5
	return float(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("foot", 0.7))

# --- Putting in, taking out -------------------------------------------------------

## Puts one item (a stack of 1) into `o`: onto a belt's start, or into its store. Returns
## true when it went in. A machine only takes what it can work (an assembler anything).
static func put(o: Dictionary, item: Dictionary) -> bool:
	if kind(o) == "belt":
		var q: Array = o["st"].get("q", [])
		if not q.is_empty() and float(q[-1][1]) < GAP:
			return false
		q.append([item, 0.0])
		o["st"]["q"] = q
		return true
	if Storage.capacity(o) <= 0 or not takes(o, String(item["type"])):
		return false
	var inv := Storage.open(o)
	if inv.add(item.duplicate()) > 0:
		return false
	Storage.save(o, inv)
	return true

## Whether a machine takes this item in (chests, hoppers and assemblers take anything).
static func takes(o: Dictionary, type: String) -> bool:
	match kind(o):
		"miner", "quarry":
			return false
		"smelter", "sawmill":
			for r in recipes(o):
				if (r["in"] as Dictionary).has(type):
					return true
			return false
	return true

## Takes one item out of `o` (matching `filter` when it isn't ""): a belt's front item,
## a machine's made goods, anything from a chest or hopper. {} when there is none.
static func take(o: Dictionary, filter := "") -> Dictionary:
	if kind(o) == "belt":
		var q: Array = o["st"].get("q", [])
		for n in q.size():
			if float(q[n][1]) > 0.6 and (filter == "" or q[n][0]["type"] == filter):
				var it: Dictionary = q[n][0]
				q.remove_at(n)
				return it
		return {}
	if Storage.capacity(o) <= 0:
		return {}
	var inv := Storage.open(o)
	for i in inv.capacity:
		var s = inv.get_slot(i)
		if s == null or (filter != "" and s["type"] != filter) or not gives(o, String(s["type"])):
			continue
		var it := inv.remove_at(i, 1)
		Storage.save(o, inv)
		return it
	return {}

## What a machine lets go of: what it makes, not what it was given to work.
static func gives(o: Dictionary, type: String) -> bool:
	match kind(o):
		"smelter", "sawmill":
			for r in recipes(o):
				if (r["in"] as Dictionary).has(type):
					return false
		"assembler":
			var r := recipe(o)
			return r.is_empty() or String(r["out"]) == type
	return true

# --- Work -------------------------------------------------------------------------

## The recipes a machine runs: an electric furnace smelts what the forge smelts (ore to
## ingots and plate), a sawmill saws logs into planks (twice what a hand saw gets), an
## assembler makes what a workbench or anvil makes.
static func recipes(o: Dictionary) -> Array:
	match kind(o):
		"smelter":
			return smelting()
		"sawmill":
			return [{"out": "planks", "qty": 6, "in": {"wood": 1}}]
		"assembler":
			return assembling()
	return []

static var _smelt: Array = []
static var _assemble: Array = []

static func smelting() -> Array:
	if _smelt.is_empty():
		for r in Recipes.LIST:
			var out := String(r["out"])
			if String(r.get("at", "")) == "forge" and not r.has("tools") and (out.ends_with("_ingot") or out.ends_with("_plate")):
				_smelt.append(r)
	return _smelt

static func assembling() -> Array:
	if _assemble.is_empty():
		for r in Recipes.LIST:
			if String(r.get("at", "")) in ["workbench", "anvil"] and not r.has("tools") and ItemDB.is_stackable(String(r["out"])):
				_assemble.append(r)
	return _assemble

## An assembler's chosen recipe, or {} before one is set.
static func recipe(o: Dictionary) -> Dictionary:
	var rc := int(o["st"].get("rc", -1))
	var list := assembling()
	return list[rc] if rc >= 0 and rc < list.size() else {}

## Sets an assembler to the next recipe it has everything for in its store (after the
## one it is on). Returns its name in words, or "" when its store has nothing to make.
static func next_recipe(o: Dictionary) -> String:
	var inv := Storage.open(o)
	var list := assembling()
	var from := int(o["st"].get("rc", -1))
	for k in list.size():
		var n := (from + 1 + k) % list.size()
		if Recipes.max_crafts(inv, list[n]) > 0:
			o["st"]["rc"] = n
			return String(ItemDB.def(list[n]["out"]).get("name", list[n]["out"]))
	return ""

## One work cycle of a machine: what it makes goes in its store. Returns false when it
## couldn't (nothing to work, no room, no vein).
static func work(o: Dictionary, vein: String, zone: int, origin: Dictionary, rng: RandomNumberGenerator) -> bool:
	var inv := Storage.open(o)
	var done := false
	match kind(o):
		"miner", "quarry":
			var src := vein if kind(o) == "miner" else "rock"
			if src == "" or not Durability.TABLE.has(src):
				return false
			var it := ItemDB.make(main_yield(src), 1, randf_range(0.85, 1.0), origin)
			if inv.add(it) > 0:
				return false
			for y in Byproducts.of_object(src, 1, zone, rng):
				inv.add(ItemDB.make(y[0], y[1], 0.9, origin))
			done = true
		"smelter", "sawmill", "assembler":
			var list: Array = [recipe(o)] if kind(o) == "assembler" else recipes(o)
			for r in list:
				if r.is_empty() or Recipes.max_crafts(inv, r) <= 0:
					continue
				if inv.free_slots() == 0 and inv.count(String(r["out"])) == 0:
					continue
				done = Recipes.craft_many(inv, r, origin, 1) > 0
				if done:
					break
	if done:
		Storage.save(o, inv)
	return done

## What drilling an object type gives first: iron ore from an iron vein, stone from rock.
static func main_yield(t: String) -> String:
	var row: Array = Durability.TABLE.get(t, [])
	if row.size() < 3 or (row[2] as Array).is_empty():
		return "stone"
	return String(row[2][0][0])

## The ore vein (or rock) nearest a world point in `chunk`, within `r`: its type, or "".
static func vein_near(chunk: ChunkNode, at: Vector3, r: float) -> String:
	var best := ""
	var best_d := r
	for o in chunk.data["objects"]:
		var k := ObjectLibrary.kind(o["t"])
		if (k != "ore" and k != "rock") or o["st"].get("gone", false):
			continue
		var d := Vector2(chunk.position.x + o["p"].x - at.x, chunk.position.z + o["p"].z - at.z).length()
		if d < best_d:
			best_d = d
			best = String(o["t"])
	return best

## Moves a belt's items on by dt; returns true when the front one has reached the end.
static func roll(o: Dictionary, dt: float) -> bool:
	var q: Array = o["st"].get("q", [])
	var v := float(spec(o).get("speed", 1.5)) * dt
	var ahead := INF
	for n in q.size():
		var t := float(q[n][1])
		t = minf(t + v, minf(1.0, ahead - GAP))
		q[n][1] = maxf(t, float(q[n][1]))
		ahead = float(q[n][1])
	return not q.is_empty() and float(q[0][1]) >= 1.0

## The look-at lines of an automation piece.
static func lines(o: Dictionary) -> Array:
	var out: Array = []
	match kind(o):
		"belt":
			var q: Array = o["st"].get("q", [])
			out.append("Carrying %d item%s" % [q.size(), "" if q.size() == 1 else "s"])
		"arm":
			var f := String(o["st"].get("flt", ""))
			out.append("Moves %s from behind it to in front" % ("everything" if f == "" else String(ItemDB.def(f).get("name", f))))
		"miner":
			out.append("Drills the vein beside it, slowly, for ever")
		"quarry":
			out.append("Digs stone out of the ground under it")
		"smelter":
			out.append("Smelts ore put in it into ingots, no fuel needed")
		"sawmill":
			out.append("Saws logs put in it into planks")
		"assembler":
			var r := recipe(o)
			out.append("Making: %s" % ("nothing yet (crouch and Interact with the ingredients in it)" if r.is_empty() else String(ItemDB.def(r["out"]).get("name", r["out"]))))
	if Storage.capacity(o) > 0:
		var inv := Storage.open(o)
		var n := 0
		for i in inv.capacity:
			if inv.get_slot(i) != null:
				n += 1
		out.append("Store: %d of %d slots used" % [n, inv.capacity])
	return out
