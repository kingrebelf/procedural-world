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
	{"out": "vehicle_bay", "qty": 1, "in": {"alloy_plate": 8, "circuitry": 6, "power_cell": 2}, "at": "fabricator"},
	{"out": "launch_pad", "qty": 1, "in": {"alloy_plate": 14, "circuitry": 8, "power_cell": 3}, "at": "vehicle_bay"},
	{"out": "stable", "qty": 1, "in": {"planks": 16, "wood": 6, "iron_ingot": 2}, "at": "workbench"},
	{"out": "storage_chest", "qty": 1, "in": {"planks": 8, "iron_ingot": 1}, "at": "workbench"},
	{"out": "storage_crate", "qty": 1, "in": {"alloy_plate": 4, "iron_ingot": 2}, "at": "fabricator"},
	{"out": "waystone", "qty": 1, "in": {"stone": 20, "aether_crystal": 6, "mythril_ingot": 1}, "at": "cauldron"},
	{"out": "waystone", "qty": 1, "in": {"stone": 30, "aether_crystal": 4, "iron_ingot": 4}, "at": "workbench"},
	{"out": "teleporter", "qty": 1, "in": {"alloy_plate": 6, "power_cell": 3, "circuitry": 4}, "at": "fabricator"},
	# Furniture and decor.
	{"out": "bed", "qty": 1, "in": {"planks": 6, "hide": 2, "fiber": 4}, "at": "workbench"},
	{"out": "bench", "qty": 1, "in": {"planks": 4}, "at": "workbench"},
	{"out": "bookcase", "qty": 1, "in": {"planks": 8}, "at": "workbench"},
	{"out": "cabinet", "qty": 1, "in": {"planks": 6, "iron_ingot": 1}, "at": "workbench"},
	{"out": "chair", "qty": 1, "in": {"planks": 2}, "at": "workbench"},
	{"out": "table", "qty": 1, "in": {"planks": 6}, "at": "workbench"},
	{"out": "stool", "qty": 1, "in": {"planks": 1}, "at": "workbench"},
	{"out": "nightstand", "qty": 1, "in": {"planks": 3}, "at": "workbench"},
	{"out": "shelf", "qty": 1, "in": {"planks": 3}, "at": "workbench"},
	{"out": "shelf_arch", "qty": 1, "in": {"planks": 5}, "at": "workbench"},
	{"out": "candle_stand", "qty": 1, "in": {"iron_ingot": 1, "fiber": 1}, "at": "workbench"},
	{"out": "lantern", "qty": 1, "in": {"iron_ingot": 1, "wood": 1}, "at": "workbench"},
	{"out": "banner_red", "qty": 1, "in": {"planks": 1, "fiber": 4}, "at": "workbench"},
	{"out": "banner_blue", "qty": 1, "in": {"planks": 1, "fiber": 4}, "at": "workbench"},
	{"out": "weapon_stand", "qty": 1, "in": {"planks": 4, "iron_ingot": 1}, "at": "workbench"},
	{"out": "dummy", "qty": 1, "in": {"wood": 3, "fiber": 6}, "at": "workbench"},
	{"out": "market_stall", "qty": 1, "in": {"planks": 10, "fiber": 6}, "at": "workbench"},
	{"out": "cart", "qty": 1, "in": {"planks": 8, "iron_ingot": 1}, "at": "workbench"},
	{"out": "apple_crate", "qty": 1, "in": {"planks": 2, "wild_berries": 4}, "at": "workbench"},
	{"out": "apple_barrel", "qty": 1, "in": {"planks": 3, "wild_berries": 6}, "at": "workbench"},
	{"out": "metal_crate", "qty": 1, "in": {"planks": 3, "iron_ingot": 2}, "at": "workbench"},
	{"out": "vase", "qty": 1, "in": {"iron_ingot": 1}, "at": "workbench"},
	{"out": "pot", "qty": 1, "in": {"stone": 2}, "at": "workbench"},
	{"out": "book_stand", "qty": 1, "in": {"planks": 2}, "at": "workbench"},
	{"out": "peg_rack", "qty": 1, "in": {"planks": 2}, "at": "workbench"},
	{"out": "cage", "qty": 1, "in": {"iron_ingot": 2}, "at": "workbench"},
	{"out": "hammer", "qty": 1, "in": {"planks": 2, "iron_ingot": 1}, "at": "workbench"},
	{"out": "torch", "qty": 1, "in": {"wood": 1, "fiber": 2}},
	{"out": "flashlight", "qty": 1, "in": {"iron_ingot": 1, "circuitry": 1, "power_cell": 1}, "at": "workbench"},
	{"out": "flashlight", "qty": 1, "in": {"flashlight_dead": 1, "power_cell": 1}, "at": "workbench"},
	# Jetpack and its fuel: rendered from wood and plant oil at a forge, or brewed from
	# aether, or refined from power cells.
	{"out": "jetpack", "qty": 1, "in": {"iron_ingot": 6, "alloy_plate": 2, "circuitry": 2, "hide": 2}, "at": "fabricator"},
	{"out": "jetpack", "qty": 1, "in": {"iron_ingot": 8, "mythril_ingot": 2, "aether_crystal": 3, "hide": 2}, "at": "cauldron"},
	{"out": "jet_fuel", "qty": 1, "in": {"wood": 4, "fiber": 4}, "at": "forge"},
	{"out": "jet_fuel", "qty": 2, "in": {"aether_crystal": 1, "fiber": 2}, "at": "cauldron"},
	{"out": "jet_fuel", "qty": 3, "in": {"power_cell": 1, "alloy_scrap": 1}, "at": "fabricator"},
	{"out": "binoculars", "qty": 1, "in": {"iron_ingot": 2, "stone": 2, "hide": 1}, "at": "workbench"},
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
	{"out": "helm_iron", "qty": 1, "in": {"iron_ingot": 3, "hide": 1}, "at": "anvil"},
	{"out": "mail_iron", "qty": 1, "in": {"iron_ingot": 6, "hide": 2}, "at": "anvil"},
	{"out": "greaves_iron", "qty": 1, "in": {"iron_ingot": 4, "hide": 1}, "at": "anvil"},
	{"out": "boots_leather", "qty": 1, "in": {"hide": 3, "fiber": 2}, "at": "workbench"},
	{"out": "helm_elven", "qty": 1, "in": {"mythril_ingot": 2, "glowroot": 2, "aether_crystal": 1}, "at": "anvil"},
	{"out": "plate_mythril", "qty": 1, "in": {"mythril_ingot": 5, "aether_crystal": 2}, "at": "anvil"},
	{"out": "guards_mythril", "qty": 1, "in": {"mythril_ingot": 3, "hide": 1}, "at": "anvil"},
	{"out": "boots_elven", "qty": 1, "in": {"hide": 2, "glowroot": 2, "fiber": 2}, "at": "workbench"},
	{"out": "crossbow", "qty": 1, "in": {"planks": 3, "iron_ingot": 1, "fiber": 4}, "at": "workbench"},
	{"out": "bolt", "qty": 8, "in": {"wood": 1, "stone": 1}},
	{"out": "arrow", "qty": 8, "in": {"wood": 1, "stone": 1, "fiber": 1}},
	# From the hunt: tanned leather, bone-tipped arrows, tallow torches and a knife to skin with.
	{"out": "skinning_knife", "qty": 1, "in": {"stone": 2, "wood": 1, "bone": 1}, "at": "workbench"},
	{"out": "skinning_knife", "qty": 1, "in": {"stone": 2, "wood": 1, "fiber": 2}, "at": "workbench"},
	{"out": "leather", "qty": 2, "in": {"hide": 2, "animal_fat": 1}, "at": "workbench"},
	{"out": "leather", "qty": 2, "in": {"fur_pelt": 1, "animal_fat": 1}, "at": "workbench"},
	{"out": "arrow", "qty": 10, "in": {"wood": 1, "bone": 1, "fiber": 1}},
	{"out": "torch", "qty": 3, "in": {"wood": 1, "animal_fat": 1}},
	{"out": "boots_leather", "qty": 1, "in": {"leather": 2, "fiber": 1}, "at": "workbench"},
	{"out": "gloves_leather", "qty": 1, "in": {"leather": 1, "fiber": 1}, "at": "workbench"},
	{"out": "longbow", "qty": 1, "in": {"wood": 3, "fiber": 4}, "at": "workbench"},
	{"out": "spear", "qty": 1, "in": {"wood": 2, "iron_ingot": 1}, "at": "workbench"},
	{"out": "dagger", "qty": 1, "in": {"iron_ingot": 1, "hide": 1}, "at": "anvil"},
	{"out": "mace", "qty": 1, "in": {"iron_ingot": 3, "planks": 1}, "at": "anvil"},
	{"out": "battle_axe", "qty": 1, "in": {"iron_ingot": 4, "planks": 2}, "at": "anvil"},
	{"out": "war_hammer", "qty": 1, "in": {"iron_ingot": 5, "planks": 2}, "at": "anvil"},
	{"out": "gloves_leather", "qty": 1, "in": {"hide": 2, "fiber": 1}, "at": "workbench"},
	{"out": "shield_wood", "qty": 1, "in": {"planks": 4, "iron_ingot": 1}, "at": "workbench"},
	{"out": "bracers_rune", "qty": 1, "in": {"mythril_ingot": 1, "aether_crystal": 1}, "at": "anvil"},
	{"out": "shield_crystal", "qty": 1, "in": {"mythril_ingot": 2, "aether_crystal": 4}, "at": "anvil"},
	{"out": "health_potion", "qty": 1, "in": {"glowberry": 2, "wild_berries": 2}, "at": "campfire"},
	{"out": "stamina_potion", "qty": 1, "in": {"wild_berries": 3, "fiber": 1}, "at": "campfire"},
	{"out": "bolt", "qty": 20, "in": {"planks": 1, "iron_ingot": 1}, "at": "workbench"},
	{"out": "scrap_pistol", "qty": 1, "in": {"iron_ingot": 4, "planks": 1}, "at": "anvil"},
	{"out": "rounds", "qty": 12, "in": {"iron_ingot": 1, "stone": 1}, "at": "anvil"},
	{"out": "crossbow_runic", "qty": 1, "in": {"mythril_ingot": 2, "planks": 2, "aether_crystal": 2}, "at": "cauldron"},
	{"out": "pulse_smg", "qty": 1, "in": {"alloy_plate": 3, "circuitry": 3, "power_cell": 1}, "at": "fabricator"},
	{"out": "pulse_rifle", "qty": 1, "in": {"alloy_plate": 4, "circuitry": 4, "power_cell": 2}, "at": "fabricator"},
	{"out": "rail_rifle", "qty": 1, "in": {"alloy_plate": 6, "circuitry": 5, "power_cell": 3, "mythril_ingot": 1}, "at": "fabricator"},
	{"out": "arc_launcher", "qty": 1, "in": {"alloy_plate": 6, "circuitry": 6, "power_cell": 4, "aether_crystal": 3}, "at": "fabricator"},
	{"out": "pickaxe_plasma", "qty": 1, "in": {"alloy_plate": 2, "power_cell": 1, "mythril_ingot": 1}, "at": "fabricator"},
	{"out": "pulse_pistol", "qty": 1, "in": {"alloy_plate": 2, "circuitry": 2, "power_cell": 1}, "at": "fabricator"},
	{"out": "helm_visor", "qty": 1, "in": {"alloy_plate": 3, "circuitry": 2}, "at": "fabricator"},
	{"out": "exo_chest", "qty": 1, "in": {"alloy_plate": 6, "circuitry": 3, "power_cell": 1}, "at": "fabricator"},
	{"out": "exo_legs", "qty": 1, "in": {"alloy_plate": 4, "circuitry": 2}, "at": "fabricator"},
	{"out": "mag_boots", "qty": 1, "in": {"alloy_plate": 2, "power_cell": 1}, "at": "fabricator"},
	{"out": "gauntlets_power", "qty": 1, "in": {"alloy_plate": 2, "circuitry": 2}, "at": "fabricator"},
	{"out": "shield_emitter", "qty": 1, "in": {"alloy_plate": 3, "power_cell": 2, "circuitry": 2}, "at": "fabricator"},
	# Vehicles.
	{"out": "speeder", "qty": 1, "in": {"alloy_plate": 6, "power_cell": 2, "circuitry": 4}, "at": "vehicle_bay"},
	{"out": "rover", "qty": 1, "in": {"alloy_plate": 8, "power_cell": 2, "iron_ingot": 4, "circuitry": 2}, "at": "vehicle_bay"},
	{"out": "ship", "qty": 1, "in": {"alloy_plate": 20, "power_cell": 6, "circuitry": 10, "data_core": 1}, "at": "launch_pad"},
	{"out": "horse", "qty": 1, "in": {"hide": 6, "planks": 4, "iron_ingot": 1, "bread": 4}, "at": "stable"},
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
	"cauldron": "Arcane Cauldron", "fabricator": "Fabricator", "vehicle_bay": "Vehicle Bay", "stable": "Stable", "launch_pad": "Launch Pad"}

## Player level that unlocks making (and placing) a thing (ItemDB.unlock_level).
const SHIP_LEVEL := ItemDB.SHIP_LEVEL

static func unlock_level(out: String) -> int:
	return ItemDB.unlock_level(out)

## True when the player's level has unlocked the recipe.
static func level_ok(recipe: Dictionary, level: int) -> bool:
	return level >= unlock_level(recipe["out"])

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
		# Crafted gear rolls a rank too; skilled hands do a little better.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for k in n * int(recipe["qty"]):
			inv.add(ItemDB.make(recipe["out"], 1, q, o, rng, clampf((skill - 1.0) * 1.5, 0.0, 0.3)))
	return n
