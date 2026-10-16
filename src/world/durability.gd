class_name Durability
## Everything in the world can be broken down and harvested, but nothing breaks instantly.
## Each object type has a material, a health pool (huge for metal and buildings) and a
## yield table. Every hit adds damage; each time damage crosses the next share of the
## health pool, one item drops into the pack, so you are paid as you work, not only at
## the end. State lives in the object's persisted `st` dict: dmg (float), taken (int).

## type -> [material, base hp, [[item, count], ...]]
const TABLE := {
	"oak": ["wood", 6.0, [["wood", -1]]],
	"pine": ["wood", 7.0, [["wood", -1]]],
	"glowcap": ["fungus", 5.0, [["glowberry", -1], ["glowroot", 1]]],
	"crystal_tree": ["crystal", 8.0, [["glowroot", -1], ["aether_crystal", 1]]],
	"solar_mast": ["metal", 30.0, [["circuitry", -1], ["alloy_scrap", 2]]],
	"rock": ["stone", 5.0, [["stone", -1]]],
	"iron_vein": ["ore", 8.0, [["iron_ore", -1], ["stone", 2]]],
	"aether_crystal": ["crystal", 9.0, [["aether_crystal", -1]]],
	"alloy_scrap": ["metal", 18.0, [["alloy_scrap", -1], ["circuitry", 1]]],
	"chest": ["wood", 6.0, [["planks", 3]]],
	"rune_coffer": ["stone", 14.0, [["stone", 4], ["aether_crystal", 1]]],
	"supply_pod": ["metal", 40.0, [["alloy_plate", 2], ["circuitry", 2]]],
	"standing_stone": ["stone", 30.0, [["stone", 10]]],
	"crystal_shard": ["crystal", 24.0, [["aether_crystal", 5]]],
	"beacon": ["metal", 60.0, [["circuitry", 3], ["power_cell", 1], ["alloy_scrap", 3]]],
	"cottage": ["wood", 90.0, [["planks", 14], ["wood", 8], ["stone", 6]]],
	"watchtower": ["stone", 160.0, [["stone", 24], ["planks", 8]]],
	"well": ["stone", 70.0, [["stone", 14]]],
	"shrine": ["stone", 120.0, [["stone", 12], ["aether_crystal", 3]]],
	"mushroom_house": ["fungus", 80.0, [["glowroot", 10], ["glowberry", 6]]],
	"spire": ["crystal", 260.0, [["aether_crystal", 16], ["mythril_ingot", 1]]],
	"hab_dome": ["metal", 420.0, [["alloy_plate", 10], ["circuitry", 8], ["power_cell", 2]]],
	"comms_spire": ["metal", 380.0, [["alloy_plate", 6], ["circuitry", 12], ["data_core", 1]]],
	"cargo_stack": ["metal", 300.0, [["alloy_plate", 8], ["alloy_scrap", 10], ["ration_pack", 4]]],
	"trader": ["wood", 50.0, [["planks", 8], ["wood", 4]]],
}

const MATERIAL_NAMES := {"wood": "Wood", "fungus": "Fungus", "crystal": "Crystal", "metal": "Metal", "stone": "Stone", "ore": "Ore"}
const BEST_TOOL := {"wood": "Axe", "fungus": "Axe", "crystal": "Pickaxe", "metal": "Plasma Drill", "stone": "Pickaxe", "ore": "Pickaxe"}

const FIST := {"mine": 0.15, "chop": 0.2, "damage": 2}

static func entry(t: String) -> Array:
	return TABLE.get(t, ["stone", 20.0, [["stone", 3]]])

static func material(t: String) -> String:
	return entry(t)[0]

## Total health of a placed object.
static func max_hp(o: Dictionary) -> float:
	var s: float = o.get("s", 1.0)
	var base: float = entry(o["t"])[1]
	var k := ObjectLibrary.kind(o["t"])
	if k == "tree" or k == "rock" or k == "ore":
		return base * (0.6 + 0.4 * s)
	return base

## How many units of each yield this object gives in total.
static func yields(o: Dictionary) -> Array:
	var out: Array = []
	var st: Dictionary = o["st"]
	for y in entry(o["t"])[2]:
		var n: int = y[1]
		if n < 0:
			# The primary yield's amount was rolled when the object was generated.
			n = int(st.get("yield", st.get("left", 4)))
		out.append([y[0], n])
	return out

static func total_items(o: Dictionary) -> int:
	var n := 0
	for y in yields(o):
		n += y[1]
	return n

## Damage one hit with this tool definition does to this material.
static func power(tool_def: Dictionary, mat: String) -> float:
	var mine: float = tool_def.get("mine", 0.0)
	var chop: float = tool_def.get("chop", 0.0)
	var dmg: float = tool_def.get("damage", 2.0)
	var p := 0.0
	match mat:
		"wood": p = chop
		"fungus": p = chop * 1.3
		"stone", "ore": p = mine
		"crystal": p = mine * 0.8
		"metal": p = mine * 0.45
	# Anything can be battered with anything, just slowly.
	return maxf(p, dmg * 0.012 + 0.05)

static func health_left(o: Dictionary) -> float:
	return maxf(0.0, max_hp(o) - float(o["st"].get("dmg", 0.0)))

## Applies one hit. Returns {items: [[type, qty]], destroyed: bool}. The caller gives the
## items (with provenance) and removes the object if destroyed.
static func hit(o: Dictionary, amount: float) -> Dictionary:
	var st: Dictionary = o["st"]
	var hp := max_hp(o)
	var dmg: float = minf(hp, float(st.get("dmg", 0.0)) + amount)
	st["dmg"] = dmg
	var total := total_items(o)
	var due := int(floor(dmg / hp * total + 0.0001))
	var taken: int = st.get("taken", 0)
	var items: Array = []
	if due > taken:
		# Hand out yields in table order, one share per crossing.
		var order: Array = []
		for y in yields(o):
			for i in y[1]:
				order.append(y[0])
		# _spread interleaves so rarer extras arrive along the way, not all at the end.
		var counts := {}
		for i in range(taken, mini(due, order.size())):
			var t: String = order[_spread(i, order.size())]
			counts[t] = counts.get(t, 0) + 1
		for t in counts:
			items.append([t, counts[t]])
		st["taken"] = due
	return {"items": items, "destroyed": dmg >= hp - 0.0001}

## Deterministic spread of index i over n so mixed yields alternate.
static func _spread(i: int, n: int) -> int:
	return (i * 7919) % n if n > 1 else 0

static func describe_yields(o: Dictionary) -> String:
	var parts: Array = []
	for y in yields(o):
		parts.append("%s x%d" % [ItemDB.def(y[0]).get("name", y[0]), y[1]])
	return ", ".join(parts)
