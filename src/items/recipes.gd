class_name Recipes

## "at" names the crafting station that must be within reach (BuildCatalog.STATION_RANGE).
const LIST := [
	{"out": "planks", "qty": 2, "in": {"wood": 1}},
	{"out": "planks", "qty": 3, "in": {"glowroot": 1}},
	# Stations. A workbench and a campfire can be made anywhere; the rest need a workbench.
	{"out": "workbench", "qty": 1, "in": {"planks": 6, "wood": 2}},
	{"out": "campfire", "qty": 1, "in": {"wood": 3, "stone": 4}},
	{"out": "forge", "qty": 1, "in": {"stone": 14, "iron_ore": 2, "wood": 2}, "at": "workbench"},
	{"out": "anvil", "qty": 1, "in": {"iron_ingot": 5, "wood": 2}, "at": "workbench"},
	{"out": "cauldron", "qty": 1, "in": {"iron_ingot": 3, "aether_crystal": 2}, "at": "workbench"},
	{"out": "fabricator", "qty": 1, "in": {"alloy_scrap": 6, "circuitry": 4, "iron_ingot": 2}, "at": "workbench"},
	{"out": "hammer", "qty": 1, "in": {"planks": 2, "iron_ingot": 1}, "at": "workbench"},
	# Materials.
	{"out": "cooked_meat", "qty": 1, "in": {"raw_meat": 1, "wood": 1}, "at": "campfire"},
	{"out": "iron_ingot", "qty": 1, "in": {"iron_ore": 2}, "at": "forge"},
	{"out": "alloy_plate", "qty": 1, "in": {"alloy_scrap": 3}, "at": "forge"},
	{"out": "mythril_ingot", "qty": 1, "in": {"iron_ingot": 1, "aether_crystal": 2}, "at": "cauldron"},
	{"out": "power_cell", "qty": 1, "in": {"aether_crystal": 1, "circuitry": 2}, "at": "fabricator"},
	# Tools and weapons.
	{"out": "pickaxe_iron", "qty": 1, "in": {"iron_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "axe_iron", "qty": 1, "in": {"iron_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "sword_iron", "qty": 1, "in": {"iron_ingot": 3, "planks": 1}, "at": "anvil"},
	{"out": "pickaxe_mythril", "qty": 1, "in": {"mythril_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "axe_mythril", "qty": 1, "in": {"mythril_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "sword_runic", "qty": 1, "in": {"mythril_ingot": 3, "aether_crystal": 2}, "at": "anvil"},
	{"out": "pickaxe_plasma", "qty": 1, "in": {"alloy_plate": 2, "power_cell": 1, "mythril_ingot": 1}, "at": "fabricator"},
	{"out": "pulse_pistol", "qty": 1, "in": {"alloy_plate": 2, "circuitry": 2, "power_cell": 1}, "at": "fabricator"},
	# Building pieces.
	{"out": "foundation", "qty": 1, "in": {"stone": 6}, "at": "workbench"},
	{"out": "floor_wood", "qty": 1, "in": {"planks": 3}, "at": "workbench"},
	{"out": "wall_plaster", "qty": 1, "in": {"planks": 3, "stone": 2}, "at": "workbench"},
	{"out": "wall_stone", "qty": 1, "in": {"stone": 6, "planks": 1}, "at": "workbench"},
	{"out": "wall_window", "qty": 1, "in": {"planks": 3, "stone": 2}, "at": "workbench"},
	{"out": "wall_door", "qty": 1, "in": {"planks": 4, "stone": 1}, "at": "workbench"},
	{"out": "stairs_wood", "qty": 1, "in": {"planks": 8}, "at": "workbench"},
	{"out": "roof_small", "qty": 1, "in": {"planks": 6, "stone": 4}, "at": "workbench"},
	{"out": "roof_large", "qty": 1, "in": {"planks": 12, "stone": 8}, "at": "workbench"},
	{"out": "fence", "qty": 2, "in": {"planks": 2}, "at": "workbench"},
	{"out": "platform", "qty": 1, "in": {"alloy_plate": 2}, "at": "fabricator"},
	{"out": "wall_scifi", "qty": 1, "in": {"alloy_plate": 3, "circuitry": 1}, "at": "fabricator"},
	{"out": "wall_scifi_window", "qty": 1, "in": {"alloy_plate": 3, "aether_crystal": 1}, "at": "fabricator"},
	{"out": "door_scifi", "qty": 1, "in": {"alloy_plate": 4, "circuitry": 2}, "at": "fabricator"},
	{"out": "stairs_scifi", "qty": 1, "in": {"alloy_plate": 6}, "at": "fabricator"},
]

const STATION_NAMES := {"workbench": "Workbench", "campfire": "Campfire", "forge": "Forge", "anvil": "Anvil",
	"cauldron": "Arcane Cauldron", "fabricator": "Fabricator"}

## True when the recipe needs no station or one is in `stations` (BuildCatalog.stations_near).
static func station_ok(recipe: Dictionary, stations: Dictionary) -> bool:
	return not recipe.has("at") or stations.has(recipe["at"])


static func can_craft(inv: Inventory, recipe: Dictionary) -> bool:
	return max_crafts(inv, recipe) > 0

## How many times the recipe can be made from what is in the pack (and still fit).
static func max_crafts(inv: Inventory, recipe: Dictionary) -> int:
	var n := 1 << 30
	for t in recipe["in"]:
		n = mini(n, inv.count(t) / int(recipe["in"][t]))
	if n <= 0:
		return 0
	if not ItemDB.is_stackable(recipe["out"]):
		# Each tool needs its own slot; consuming inputs may free some.
		n = mini(n, inv.free_slots() + _slots_freed(inv, recipe, n))
	elif inv.count(recipe["out"]) == 0 and inv.free_slots() + _slots_freed(inv, recipe, n) <= 0:
		return 0
	return maxi(n, 0)

static func _slots_freed(inv: Inventory, recipe: Dictionary, times: int) -> int:
	var freed := 0
	for t in recipe["in"]:
		if inv.count(t) == recipe["in"][t] * times:
			freed += inv.slots_of(t)
	return freed

## Consumes inputs and adds the output. Output quality is the average input quality.
static func craft(inv: Inventory, recipe: Dictionary, origin: Dictionary) -> bool:
	return craft_many(inv, recipe, origin, 1) == 1

## Crafts up to `times` in one go (-1 = as many as possible); returns how many were made.
## `skill` scales output quality (the crafter's Intellect).
static func craft_many(inv: Inventory, recipe: Dictionary, origin: Dictionary, times: int, skill := 1.0) -> int:
	var most := max_crafts(inv, recipe)
	var n := most if times < 0 else mini(times, most)
	if n <= 0:
		return 0
	var q_sum := 0.0
	var q_n := 0
	for t in recipe["in"]:
		q_sum += inv.average_quality(t) * recipe["in"][t]
		q_n += recipe["in"][t]
	for t in recipe["in"]:
		inv.remove_type(t, recipe["in"][t] * n)
	var o := origin.duplicate()
	o["how"] = "crafted"
	var q := q_sum / maxf(1, q_n) * skill
	if ItemDB.is_stackable(recipe["out"]):
		inv.add(ItemDB.make(recipe["out"], recipe["qty"] * n, q, o))
	else:
		for k in n * int(recipe["qty"]):
			inv.add(ItemDB.make(recipe["out"], 1, q, o))
	return n
