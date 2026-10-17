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
	"solar_mast": ["fungus", 12.0, [["circuitry", -1], ["alloy_scrap", 2]]],
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
	"cottage": ["stone", 110.0, [["stone", 14], ["planks", 8], ["wood", 4]]],
	"townhouse": ["stone", 160.0, [["stone", 16], ["planks", 14], ["wood", 6]]],
	"bridge": ["stone", 900.0, [["stone", 60]]],
	"cave": ["stone", 600.0, [["stone", 90]]],
	"signpost": ["wood", 8.0, [["planks", 2], ["wood", 1]]],
	"market_stall": ["wood", 30.0, [["planks", 4], ["wood", 2], ["wild_berries", 3]]],
	"fruit_cart": ["wood", 30.0, [["planks", 4], ["wood", 3], ["wild_berries", 2]]],
	"wagon": ["wood", 40.0, [["planks", 6], ["wood", 4]]],
	"barrels": ["wood", 24.0, [["planks", 4], ["wild_berries", 2]]],
	"longhouse": ["wood", 120.0, [["planks", 18], ["wood", 10], ["stone", 4]]],
	"watchtower": ["stone", 160.0, [["stone", 24], ["planks", 8]]],
	"well": ["stone", 70.0, [["stone", 14]]],
	"shrine": ["stone", 120.0, [["stone", 12], ["aether_crystal", 3]]],
	"mushroom_house": ["fungus", 80.0, [["glowroot", 10], ["glowberry", 6]]],
	"spire": ["crystal", 260.0, [["aether_crystal", 16], ["mythril_ingot", 1]]],
	"hab_dome": ["metal", 420.0, [["alloy_plate", 10], ["circuitry", 8], ["power_cell", 2]]],
	"comms_spire": ["metal", 380.0, [["alloy_plate", 6], ["circuitry", 12], ["data_core", 1]]],
	"cargo_stack": ["metal", 300.0, [["alloy_plate", 8], ["alloy_scrap", 10], ["ration_pack", 4]]],
	"hab_block": ["metal", 480.0, [["alloy_plate", 12], ["circuitry", 8], ["power_cell", 2]]],
	"lab_block": ["metal", 560.0, [["alloy_plate", 14], ["circuitry", 12], ["data_core", 1]]],
	"ops_tower": ["metal", 720.0, [["alloy_plate", 18], ["circuitry", 14], ["data_core", 1]]],
	"solar_farm": ["metal", 400.0, [["alloy_plate", 8], ["circuitry", 10], ["power_cell", 4]]],
	"depot": ["metal", 420.0, [["alloy_plate", 10], ["alloy_scrap", 12], ["ration_pack", 4]]],
	"outpost_light": ["metal", 90.0, [["alloy_plate", 2], ["circuitry", 2]]],
	"castle_wall": ["stone", 1600.0, [["stone", 30]]],
	"castle_tower": ["stone", 2400.0, [["stone", 30]]],
	"castle_gate": ["stone", 1400.0, [["stone", 30]]],
	"castle_keep": ["stone", 2000.0, [["stone", 30]]],
	"crypt_wall": ["stone", 1600.0, [["stone", 30]]],
	"crypt_tower": ["stone", 2400.0, [["stone", 30]]],
	"crypt_gate": ["stone", 1400.0, [["stone", 30]]],
	"crypt_keep": ["stone", 2000.0, [["stone", 30]]],
	"bunker_wall": ["metal", 1600.0, [["alloy_plate", 12], ["alloy_scrap", 20]]],
	"bunker_tower": ["metal", 2400.0, [["alloy_plate", 12], ["alloy_scrap", 20]]],
	"bunker_gate": ["metal", 1400.0, [["alloy_plate", 12], ["alloy_scrap", 20]]],
	"bunker_keep": ["metal", 2000.0, [["alloy_plate", 12], ["alloy_scrap", 20]]],
	"alien_ruin": ["metal", 600.0, [["alloy_plate", 8], ["data_core", 2], ["power_cell", 3], ["aether_crystal", 6]]],
	"trader": ["wood", 50.0, [["planks", 8], ["wood", 4]]],
}

const MATERIAL_NAMES := {"wood": "Wood", "fungus": "Fungus", "crystal": "Crystal", "metal": "Metal", "stone": "Stone", "ore": "Ore"}
const BEST_TOOL := {"wood": "Axe", "fungus": "Axe", "crystal": "Pickaxe", "metal": "Plasma Drill", "stone": "Pickaxe", "ore": "Pickaxe"}

const FIST := {"mine": 0.15, "chop": 0.2, "damage": 2}

static func entry(t: String) -> Array:
	if BuildCatalog.is_built(t):
		# Taking down something you built hands the piece back.
		var d := BuildCatalog.def(BuildCatalog.id_of(t))
		return [d.get("mat", "wood"), float(d.get("hp", 10.0)), [[BuildCatalog.id_of(t), 1]]]
	if ShipPad.has(t):
		return ShipPad.SALVAGE
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
## The main yield (the one rolled per object) is paid out as you work. Fixed extras, like
## the crystal at the heart of a crystal tree or the loose stone round an iron vein, come
## only when the thing finally breaks, so a tree never hands you a rock halfway through.
## Objects with no main yield (caches, buildings) pay everything out along the way.
static func hit(o: Dictionary, amount: float) -> Dictionary:
	var st: Dictionary = o["st"]
	var hp := max_hp(o)
	var dmg: float = minf(hp, float(st.get("dmg", 0.0)) + amount)
	st["dmg"] = dmg
	var destroyed := dmg >= hp - 0.0001
	var main: Array = []
	var extra: Array = []
	var ys := yields(o)
	var tab: Array = entry(o["t"])[2]
	for i in ys.size():
		for n in ys[i][1]:
			(main if tab[i][1] < 0 else extra).append(ys[i][0])
	var order: Array = main + extra if not main.is_empty() else extra
	var paced: int = main.size() if not main.is_empty() else extra.size()
	var due := order.size() if destroyed else mini(paced, int(floor(dmg / hp * paced + 0.0001)))
	var taken: int = st.get("taken", 0)
	var items: Array = []
	if due > taken:
		var counts := {}
		var keys: Array = []
		for i in range(taken, mini(due, order.size())):
			# Without a main yield, _spread interleaves mixed loot so it alternates.
			var t: String = order[i] if not main.is_empty() else order[_spread(i, order.size())]
			if not counts.has(t):
				keys.append(t)
			counts[t] = counts.get(t, 0) + 1
		for t in keys:
			items.append([t, counts[t]])
		st["taken"] = due
	return {"items": items, "destroyed": destroyed}

## Deterministic spread of index i over n so mixed yields alternate.
static func _spread(i: int, n: int) -> int:
	return (i * 7919) % n if n > 1 else 0

static func describe_yields(o: Dictionary) -> String:
	var parts: Array = []
	for y in yields(o):
		parts.append("%s x%d" % [ItemDB.def(y[0]).get("name", y[0]), y[1]])
	return ", ".join(parts)
