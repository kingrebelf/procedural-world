class_name Recipes

## "at" names the crafting station that must be within reach (BuildCatalog.STATION_RANGE);
## "tools" are items that must be in the pack and are not used up (a saw, a mortar).
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
	{"out": "lockpick", "qty": 4, "in": {"iron_ingot": 1}},
	{"out": "lockpick", "qty": 4, "in": {"alloy_scrap": 1}},
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
	{"out": "wall_door_stone", "qty": 1, "in": {"stone": 6, "planks": 1}, "at": "workbench"},
	{"out": "door_wood", "qty": 1, "in": {"planks": 6, "iron_ingot": 1}, "at": "workbench"},
	{"out": "door_iron", "qty": 1, "in": {"planks": 6, "iron_ingot": 4}, "at": "anvil"},
	{"out": "stairs_wood", "qty": 1, "in": {"planks": 8}, "at": "workbench"},
	{"out": "roof_small", "qty": 1, "in": {"planks": 6, "stone": 4}, "at": "workbench"},
	{"out": "roof_large", "qty": 1, "in": {"planks": 12, "stone": 8}, "at": "workbench"},
	{"out": "fence", "qty": 2, "in": {"planks": 2}, "at": "workbench"},
	{"out": "platform", "qty": 1, "in": {"alloy_plate": 2}, "at": "fabricator"},
	{"out": "wall_scifi", "qty": 1, "in": {"alloy_plate": 3, "circuitry": 1}, "at": "fabricator"},
	{"out": "wall_scifi_window", "qty": 1, "in": {"alloy_plate": 3, "aether_crystal": 1}, "at": "fabricator"},
	{"out": "door_scifi", "qty": 1, "in": {"alloy_plate": 4, "circuitry": 2}, "at": "fabricator"},
	{"out": "door_bulkhead", "qty": 1, "in": {"alloy_plate": 6, "circuitry": 3, "power_cell": 1}, "at": "fabricator"},
	{"out": "stairs_scifi", "qty": 1, "in": {"alloy_plate": 6}, "at": "fabricator"},

	# --- The medieval age (pack A) ---------------------------------------------------------
	# Materials: rope and cloth, smelting, fuel and earthenware.
	{"out": "rope", "qty": 1, "in": {"fiber": 3}},
	{"out": "rope", "qty": 2, "in": {"flax": 3}},
	{"out": "cloth", "qty": 1, "in": {"flax": 3}, "at": "workbench"},
	{"out": "cloth", "qty": 1, "in": {"wool": 2}, "at": "workbench"},
	{"out": "planks", "qty": 4, "in": {"wood": 1}, "tools": ["saw"]},
	{"out": "charcoal", "qty": 2, "in": {"wood": 3}, "at": "campfire"},
	{"out": "lamp_oil", "qty": 1, "in": {"animal_fat": 2}, "at": "campfire"},
	{"out": "lamp_oil", "qty": 1, "in": {"resin": 2, "beeswax": 1}, "at": "campfire"},
	{"out": "brick", "qty": 2, "in": {"clay": 2}, "at": "forge"},
	{"out": "empty_vial", "qty": 2, "in": {"clay": 1}, "at": "forge"},
	{"out": "empty_bottle", "qty": 1, "in": {"clay": 2}, "at": "forge"},
	{"out": "copper_ingot", "qty": 1, "in": {"copper_ore": 2}, "at": "forge"},
	{"out": "bronze_ingot", "qty": 2, "in": {"copper_ore": 3, "tin_ore": 1}, "at": "forge"},
	{"out": "bronze_ingot", "qty": 1, "in": {"copper_ingot": 1, "tin_ore": 1}, "at": "forge"},
	{"out": "iron_ingot", "qty": 2, "in": {"iron_ore": 3, "charcoal": 1}, "at": "forge"},
	{"out": "iron_ingot", "qty": 2, "in": {"iron_ore": 3, "coal": 1}, "at": "forge"},
	{"out": "steel_ingot", "qty": 1, "in": {"iron_ingot": 2, "coal": 2}, "at": "forge", "tools": ["tongs"]},
	{"out": "steel_ingot", "qty": 1, "in": {"iron_ingot": 2, "charcoal": 3}, "at": "forge", "tools": ["tongs"]},
	{"out": "silver_ingot", "qty": 1, "in": {"silver_ore": 2, "charcoal": 1}, "at": "forge"},
	{"out": "gold_ingot", "qty": 1, "in": {"gold_ore": 2, "charcoal": 1}, "at": "forge"},
	{"out": "iron_nails", "qty": 12, "in": {"iron_ingot": 1}, "at": "anvil"},
	{"out": "salt", "qty": 3, "in": {"salt_crystal": 1}, "tools": ["mortar_pestle"]},
	{"out": "forge", "qty": 1, "in": {"brick": 10, "iron_ore": 2, "wood": 2}, "at": "workbench"},
	# Tools.
	{"out": "pickaxe_stone", "qty": 1, "in": {"wood": 1, "flint": 2, "fiber": 2}},
	{"out": "axe_stone", "qty": 1, "in": {"wood": 1, "flint": 2, "fiber": 2}},
	{"out": "pickaxe_bronze", "qty": 1, "in": {"bronze_ingot": 2, "planks": 2}, "at": "forge"},
	{"out": "pickaxe_steel", "qty": 1, "in": {"steel_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "axe_steel", "qty": 1, "in": {"steel_ingot": 2, "planks": 2}, "at": "anvil"},
	{"out": "shovel", "qty": 1, "in": {"planks": 2, "iron_ingot": 1}, "at": "workbench"},
	{"out": "hoe", "qty": 1, "in": {"wood": 2, "flint": 1, "fiber": 1}},
	{"out": "sickle", "qty": 1, "in": {"iron_ingot": 1, "wood": 1}, "at": "workbench"},
	{"out": "fishing_rod", "qty": 1, "in": {"wood": 2, "fiber": 3, "bone": 1}},
	{"out": "fishing_rod", "qty": 1, "in": {"wood": 2, "rope": 1}},
	{"out": "saw", "qty": 1, "in": {"iron_ingot": 1, "planks": 1}, "at": "workbench"},
	{"out": "tongs", "qty": 1, "in": {"iron_ingot": 2}, "at": "forge"},
	{"out": "bucket", "qty": 1, "in": {"planks": 3, "rope": 1}, "at": "workbench"},
	{"out": "waterskin", "qty": 1, "in": {"leather": 1, "fiber": 2}, "at": "workbench"},
	{"out": "waterskin", "qty": 1, "in": {"hide": 2, "fiber": 2}, "at": "workbench"},
	{"out": "mortar_pestle", "qty": 1, "in": {"stone": 3}, "at": "workbench"},
	{"out": "quill_ink", "qty": 1, "in": {"charcoal": 1, "empty_vial": 1, "fiber": 1}, "at": "workbench"},
	{"out": "cauldron_small", "qty": 1, "in": {"iron_ingot": 3}, "at": "forge"},
	{"out": "tinderbox", "qty": 1, "in": {"flint": 1, "iron_ingot": 1, "fiber": 2}, "at": "workbench"},
	{"out": "hand_lantern", "qty": 1, "in": {"iron_ingot": 2, "cloth": 1}, "at": "workbench"},
	{"out": "candle", "qty": 3, "in": {"beeswax": 1, "fiber": 1}, "tools": ["tinderbox"]},
	{"out": "candle", "qty": 2, "in": {"animal_fat": 1, "fiber": 1}},
	{"out": "torch", "qty": 4, "in": {"wood": 1, "resin": 1}, "tools": ["tinderbox"]},
	{"out": "torch", "qty": 4, "in": {"wood": 2, "lamp_oil": 1}},
	{"out": "bedroll", "qty": 1, "in": {"cloth": 2, "hide": 1, "rope": 1}, "at": "workbench"},
	{"out": "tent_kit", "qty": 1, "in": {"cloth": 6, "rope": 2, "wood": 4}, "at": "workbench"},
	{"out": "scroll_plain", "qty": 2, "in": {"flax": 2}, "at": "workbench"},
	# Weapons.
	{"out": "wooden_club", "qty": 1, "in": {"wood": 2}},
	{"out": "quarterstaff", "qty": 1, "in": {"wood": 2, "fiber": 1}},
	{"out": "stone_knife", "qty": 1, "in": {"flint": 2, "wood": 1, "fiber": 1}},
	{"out": "hunting_spear", "qty": 1, "in": {"wood": 2, "flint": 1, "fiber": 1}},
	{"out": "hand_axe", "qty": 1, "in": {"flint": 2, "wood": 1, "fiber": 2}},
	{"out": "sling", "qty": 1, "in": {"rope": 1, "hide": 1}},
	{"out": "javelin", "qty": 3, "in": {"wood": 2, "flint": 1}},
	{"out": "shortbow", "qty": 1, "in": {"wood": 2, "rope": 1}, "at": "workbench"},
	{"out": "bronze_sword", "qty": 1, "in": {"bronze_ingot": 3, "planks": 1}, "at": "forge"},
	{"out": "bronze_spear", "qty": 1, "in": {"bronze_ingot": 1, "wood": 2}, "at": "forge"},
	{"out": "bronze_axe", "qty": 1, "in": {"bronze_ingot": 2, "planks": 1}, "at": "forge"},
	{"out": "cudgel", "qty": 1, "in": {"wood": 2, "iron_ingot": 1}, "at": "workbench"},
	{"out": "throwing_knives", "qty": 6, "in": {"iron_ingot": 1}, "at": "anvil"},
	{"out": "falchion", "qty": 1, "in": {"iron_ingot": 3, "leather": 1}, "at": "anvil"},
	{"out": "warpick", "qty": 1, "in": {"iron_ingot": 3, "planks": 1}, "at": "anvil"},
	{"out": "morning_star", "qty": 1, "in": {"iron_ingot": 4, "planks": 1, "iron_nails": 8}, "at": "anvil"},
	{"out": "flail", "qty": 1, "in": {"iron_ingot": 4, "planks": 1}, "at": "anvil"},
	{"out": "glaive", "qty": 1, "in": {"iron_ingot": 3, "wood": 3}, "at": "anvil"},
	{"out": "composite_bow", "qty": 1, "in": {"wood": 2, "antler": 1, "leather": 1, "rope": 1}, "at": "workbench"},
	{"out": "steel_sword", "qty": 1, "in": {"steel_ingot": 3, "leather": 1}, "at": "anvil"},
	{"out": "rapier", "qty": 1, "in": {"steel_ingot": 2, "leather": 1}, "at": "anvil"},
	{"out": "halberd", "qty": 1, "in": {"steel_ingot": 3, "wood": 3}, "at": "anvil"},
	{"out": "zweihander", "qty": 1, "in": {"steel_ingot": 5, "leather": 2}, "at": "anvil"},
	{"out": "heavy_crossbow", "qty": 1, "in": {"steel_ingot": 2, "planks": 3, "rope": 2}, "at": "anvil"},
	{"out": "knight_sword", "qty": 1, "in": {"steel_ingot": 4, "silver_ingot": 1, "gold_ingot": 1, "leather": 1}, "at": "anvil"},
	{"out": "executioner_axe", "qty": 1, "in": {"steel_ingot": 6, "planks": 2}, "at": "anvil"},
	{"out": "royal_bow", "qty": 1, "in": {"wood": 3, "antler": 2, "gold_ingot": 1, "silver_ingot": 1, "rope": 2}, "at": "workbench"},
	{"out": "broadhead_arrows", "qty": 12, "in": {"wood": 1, "iron_ingot": 1, "fiber": 1}, "at": "workbench"},
	# Armour.
	{"out": "cap_cloth", "qty": 1, "in": {"cloth": 1}, "at": "workbench"},
	{"out": "tunic_padded", "qty": 1, "in": {"cloth": 4, "fiber": 2}, "at": "workbench"},
	{"out": "wraps_cloth", "qty": 1, "in": {"cloth": 1}, "at": "workbench"},
	{"out": "trousers_wool", "qty": 1, "in": {"cloth": 2, "wool": 1}, "at": "workbench"},
	{"out": "shoes_cloth", "qty": 1, "in": {"cloth": 1, "hide": 1}, "at": "workbench"},
	{"out": "buckler_wood", "qty": 1, "in": {"planks": 3}, "at": "workbench"},
	{"out": "cap_hide", "qty": 1, "in": {"hide": 2}, "at": "workbench"},
	{"out": "vest_hide", "qty": 1, "in": {"hide": 4, "fiber": 2}, "at": "workbench"},
	{"out": "gloves_hide", "qty": 1, "in": {"hide": 1, "fiber": 1}, "at": "workbench"},
	{"out": "leggings_hide", "qty": 1, "in": {"hide": 3}, "at": "workbench"},
	{"out": "boots_hide", "qty": 1, "in": {"hide": 2}, "at": "workbench"},
	{"out": "shield_hide", "qty": 1, "in": {"wood": 2, "hide": 2}, "at": "workbench"},
	{"out": "helm_studded", "qty": 1, "in": {"leather": 2, "iron_nails": 6}, "at": "workbench"},
	{"out": "jerkin_studded", "qty": 1, "in": {"leather": 4, "iron_nails": 12}, "at": "workbench"},
	{"out": "gloves_studded", "qty": 1, "in": {"leather": 1, "iron_nails": 4}, "at": "workbench"},
	{"out": "pants_studded", "qty": 1, "in": {"leather": 3, "iron_nails": 8}, "at": "workbench"},
	{"out": "boots_studded", "qty": 1, "in": {"leather": 2, "iron_nails": 4}, "at": "workbench"},
	{"out": "shield_kite", "qty": 1, "in": {"planks": 4, "iron_ingot": 2, "leather": 1}, "at": "anvil"},
	{"out": "helm_bronze", "qty": 1, "in": {"bronze_ingot": 2, "hide": 1}, "at": "forge"},
	{"out": "cuirass_bronze", "qty": 1, "in": {"bronze_ingot": 5, "hide": 1}, "at": "forge"},
	{"out": "bracers_bronze", "qty": 1, "in": {"bronze_ingot": 1, "leather": 1}, "at": "forge"},
	{"out": "greaves_bronze", "qty": 1, "in": {"bronze_ingot": 3}, "at": "forge"},
	{"out": "sandals_bronze", "qty": 1, "in": {"bronze_ingot": 1, "leather": 1}, "at": "forge"},
	{"out": "shield_bronze", "qty": 1, "in": {"bronze_ingot": 2, "planks": 2}, "at": "forge"},
	{"out": "helm_steel", "qty": 1, "in": {"steel_ingot": 3, "leather": 1}, "at": "anvil"},
	{"out": "plate_steel", "qty": 1, "in": {"steel_ingot": 7, "leather": 2}, "at": "anvil"},
	{"out": "gauntlets_steel", "qty": 1, "in": {"steel_ingot": 2, "leather": 1}, "at": "anvil"},
	{"out": "cuisses_steel", "qty": 1, "in": {"steel_ingot": 4, "leather": 1}, "at": "anvil"},
	{"out": "sabatons_steel", "qty": 1, "in": {"steel_ingot": 2, "leather": 1}, "at": "anvil"},
	{"out": "shield_tower", "qty": 1, "in": {"steel_ingot": 3, "planks": 4}, "at": "anvil"},
	# Trinkets.
	{"out": "amulet_bone", "qty": 1, "in": {"bone": 3, "fiber": 2}},
	{"out": "ring_copper", "qty": 1, "in": {"copper_ingot": 1}, "at": "forge"},
	{"out": "ring_silver", "qty": 1, "in": {"silver_ingot": 1}, "at": "anvil"},
	{"out": "amulet_silver", "qty": 1, "in": {"silver_ingot": 1, "rope": 1}, "at": "anvil"},
	# Food and drink.
	{"out": "flour", "qty": 1, "in": {"wheat": 2}, "tools": ["mortar_pestle"]},
	{"out": "bread", "qty": 2, "in": {"flour": 2}, "at": "campfire"},
	{"out": "fish_cooked", "qty": 1, "in": {"fish_raw": 1, "wood": 1}, "at": "campfire"},
	{"out": "chicken_roast", "qty": 1, "in": {"raw_meat": 2, "onion": 1}, "at": "campfire"},
	{"out": "sausage", "qty": 3, "in": {"raw_meat": 2, "salt": 1, "animal_fat": 1}, "at": "campfire"},
	{"out": "salted_meat", "qty": 1, "in": {"raw_meat": 1, "salt": 1}},
	{"out": "stew", "qty": 2, "in": {"raw_meat": 1, "potato": 1, "carrot": 1, "onion": 1}, "at": "campfire", "tools": ["bucket"]},
	{"out": "soup_veg", "qty": 2, "in": {"potato": 1, "carrot": 1, "cabbage": 1, "onion": 1}, "at": "campfire", "tools": ["bucket"]},
	{"out": "porridge", "qty": 2, "in": {"wheat": 2, "milk": 1}, "at": "campfire"},
	{"out": "pie_meat", "qty": 2, "in": {"flour": 2, "raw_meat": 2, "egg": 1}, "at": "campfire"},
	{"out": "pie_berry", "qty": 2, "in": {"flour": 2, "wild_berries": 4, "egg": 1}, "at": "campfire"},
	{"out": "travel_bread", "qty": 3, "in": {"flour": 2, "honey": 1, "salt": 1}, "at": "campfire"},
	{"out": "jam", "qty": 2, "in": {"wild_berries": 4, "honey": 1}, "at": "campfire"},
	{"out": "wine", "qty": 1, "in": {"grapes": 4, "empty_bottle": 1}, "at": "workbench"},
	{"out": "mead", "qty": 1, "in": {"honey": 2, "empty_bottle": 1}, "at": "workbench"},
	# Medicine: herbs ground in a mortar, the stronger brews in a pot.
	{"out": "potion_health_minor", "qty": 1, "in": {"herb_red": 2, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle"]},
	{"out": "potion_health_greater", "qty": 1, "in": {"herb_red": 3, "herb_root": 1, "honey": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle", "cauldron_small"]},
	{"out": "potion_stamina_greater", "qty": 1, "in": {"herb_mint": 2, "herb_yellow": 2, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle", "cauldron_small"]},
	{"out": "antidote", "qty": 1, "in": {"herb_blue": 1, "herb_mint": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle"]},
	{"out": "tonic_warmth", "qty": 1, "in": {"herb_root": 1, "honey": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle"]},
	{"out": "tonic_cooling", "qty": 1, "in": {"herb_mint": 2, "herb_blue": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle"]},
	{"out": "elixir_strength", "qty": 1, "in": {"herb_root": 2, "herb_red": 1, "bone": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle", "cauldron_small"]},
	{"out": "elixir_swiftness", "qty": 1, "in": {"herb_yellow": 2, "herb_mint": 1, "honey": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle", "cauldron_small"]},
	{"out": "elixir_nightsight", "qty": 1, "in": {"herb_nightshade": 1, "herb_blue": 1, "empty_vial": 1}, "at": "campfire", "tools": ["mortar_pestle"]},
	{"out": "salve", "qty": 1, "in": {"herb_red": 1, "animal_fat": 1}, "tools": ["mortar_pestle"]},
	{"out": "bandage_linen", "qty": 2, "in": {"cloth": 1}},
	{"out": "herbal_poultice", "qty": 1, "in": {"herb_red": 1, "herb_mint": 1, "cloth": 1}, "tools": ["mortar_pestle"]},
	{"out": "smelling_salts", "qty": 2, "in": {"salt": 1, "herb_mint": 1}, "tools": ["mortar_pestle"]},
	# Scrolls.
	{"out": "scroll_red", "qty": 1, "in": {"scroll_plain": 1, "herb_red": 1}, "tools": ["quill_ink"]},
	{"out": "scroll_blue", "qty": 1, "in": {"scroll_plain": 1, "herb_blue": 1}, "tools": ["quill_ink"]},
	{"out": "scroll_green", "qty": 1, "in": {"scroll_plain": 1, "herb_yellow": 2, "silver_ingot": 1}, "tools": ["quill_ink"]},
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

## The tools the recipe needs that are not in the pack.
static func missing_tools(inv: Inventory, recipe: Dictionary) -> Array:
	return recipe.get("tools", []).filter(func(t): return inv.count(t) <= 0)


static func can_craft(inv: Inventory, recipe: Dictionary) -> bool:
	return max_crafts(inv, recipe) > 0

## How many times the recipe can be made from what is in the pack (and still fit).
static func max_crafts(inv: Inventory, recipe: Dictionary) -> int:
	if not missing_tools(inv, recipe).is_empty():
		return 0
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
