class_name ItemDB
## Static item definitions. `era` is the culture an item comes from (-1 = universal);
## traders pay a premium for goods foreign to their own era.

const ANY := -1

const ITEMS := {
	# Raw resources
	"wood": {"name": "Oak Wood", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.55, 0.38, 0.22)},
	"glowroot": {"name": "Glowroot Timber", "era": Eras.FANTASY, "value": 6, "stack": true, "kind": "resource", "color": Color(0.3, 0.8, 0.7)},
	"circuitry": {"name": "Salvaged Circuitry", "era": Eras.SCIFI, "value": 9, "stack": true, "kind": "resource", "color": Color(0.2, 0.6, 0.3)},
	"stone": {"name": "Stone", "era": ANY, "value": 1, "stack": true, "kind": "resource", "color": Color(0.5, 0.5, 0.5)},
	"iron_ore": {"name": "Iron Ore", "era": Eras.MEDIEVAL, "value": 5, "stack": true, "kind": "resource", "color": Color(0.5, 0.35, 0.3)},
	"aether_crystal": {"name": "Aether Crystal", "era": Eras.FANTASY, "value": 12, "stack": true, "kind": "resource", "color": Color(0.5, 0.8, 1.0)},
	"alloy_scrap": {"name": "Alloy Scrap", "era": Eras.SCIFI, "value": 8, "stack": true, "kind": "resource", "color": Color(0.7, 0.72, 0.75)},
	# Refined
	"planks": {"name": "Planks", "era": ANY, "value": 2, "stack": true, "kind": "resource", "color": Color(0.7, 0.55, 0.35)},
	"iron_ingot": {"name": "Iron Ingot", "era": Eras.MEDIEVAL, "value": 14, "stack": true, "kind": "resource", "color": Color(0.6, 0.6, 0.62)},
	"mythril_ingot": {"name": "Mythril Ingot", "era": Eras.FANTASY, "value": 34, "stack": true, "kind": "resource", "color": Color(0.7, 0.9, 1.0)},
	"alloy_plate": {"name": "Alloy Plate", "era": Eras.SCIFI, "value": 30, "stack": true, "kind": "resource", "color": Color(0.8, 0.82, 0.86)},
	"power_cell": {"name": "Power Cell", "era": Eras.SCIFI, "value": 40, "stack": true, "kind": "resource", "color": Color(0.3, 0.9, 1.0)},
	# Treasure and trade goods
	"silver_chalice": {"name": "Silver Chalice", "era": Eras.MEDIEVAL, "value": 60, "stack": true, "kind": "treasure", "color": Color(0.85, 0.85, 0.9)},
	"moonpearl": {"name": "Moonpearl", "era": Eras.FANTASY, "value": 85, "stack": true, "kind": "treasure", "color": Color(0.9, 0.9, 1.0)},
	"data_core": {"name": "Encrypted Data Core", "era": Eras.SCIFI, "value": 110, "stack": true, "kind": "treasure", "color": Color(0.2, 1.0, 0.8)},
	# Treasure maps: picking one up buries a chest somewhere out there (see Treasure).
	"treasure_map": {"name": "Treasure Map", "era": Eras.MEDIEVAL, "value": 25, "stack": false, "kind": "map", "color": Color(0.86, 0.76, 0.54)},
	"treasure_chip": {"name": "Cache Data Chip", "era": Eras.SCIFI, "value": 40, "stack": false, "kind": "map", "color": Color(0.32, 0.36, 0.42)},
	# Food
	"bread": {"name": "Bread", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "food", "heal": 25, "color": Color(0.8, 0.6, 0.3)},
	"glowberry": {"name": "Glowberries", "era": Eras.FANTASY, "value": 6, "stack": true, "kind": "food", "heal": 35, "color": Color(0.6, 0.3, 1.0)},
	"raw_meat": {"name": "Raw Meat", "era": ANY, "value": 3, "stack": true, "kind": "food", "heal": 8, "color": Color(0.75, 0.3, 0.3)},
	"cooked_meat": {"name": "Cooked Meat", "era": ANY, "value": 7, "stack": true, "kind": "food", "heal": 40, "color": Color(0.55, 0.32, 0.18)},
	"fiber": {"name": "Plant Fiber", "era": ANY, "value": 1, "stack": true, "kind": "resource", "color": Color(0.55, 0.62, 0.3)},
	"wild_berries": {"name": "Wild Berries", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "heal": 15, "color": Color(0.7, 0.12, 0.25)},
	"hide": {"name": "Hide", "era": ANY, "value": 5, "stack": true, "kind": "resource", "color": Color(0.6, 0.45, 0.3)},
	# From butchering (see CorpseLoot).
	"bone": {"name": "Bone", "era": ANY, "value": 2, "stack": true, "kind": "resource", "color": Color(0.9, 0.87, 0.78)},
	"animal_fat": {"name": "Animal Fat", "era": ANY, "value": 4, "stack": true, "kind": "resource", "color": Color(0.95, 0.9, 0.7)},
	"antler": {"name": "Antler", "era": ANY, "value": 18, "stack": true, "kind": "resource", "color": Color(0.78, 0.66, 0.5)},
	"fur_pelt": {"name": "Fur Pelt", "era": ANY, "value": 14, "stack": true, "kind": "resource", "color": Color(0.5, 0.45, 0.4)},
	"leather": {"name": "Leather", "era": ANY, "value": 12, "stack": true, "kind": "resource", "color": Color(0.5, 0.33, 0.2)},
	"ration_pack": {"name": "Ration Pack", "era": Eras.SCIFI, "value": 8, "stack": true, "kind": "food", "heal": 50, "color": Color(0.8, 0.8, 0.5)},
	# Tools
	"pickaxe_iron": {"name": "Iron Pickaxe", "era": Eras.MEDIEVAL, "value": 45, "stack": false, "kind": "tool", "mine": 1.0, "chop": 0.3, "damage": 8, "range": 3.0, "dig": 0.6},
	"pickaxe_mythril": {"name": "Mythril Pickaxe", "era": Eras.FANTASY, "value": 140, "stack": false, "kind": "tool", "mine": 2.0, "chop": 0.4, "damage": 12, "range": 3.0, "dig": 1.0},
	"pickaxe_plasma": {"name": "Plasma Drill", "era": Eras.SCIFI, "value": 260, "stack": false, "kind": "tool", "mine": 3.5, "chop": 0.6, "damage": 10, "range": 3.5, "dig": 1.6, "beam": true, "beam_dps": 45.0, "beam_range": 10.0, "beam_mine": 4.0},
	"axe_iron": {"name": "Iron Axe", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "tool", "mine": 0.3, "chop": 1.0, "damage": 12, "range": 3.0},
	"lockpick": {"name": "Lockpick", "era": ANY, "value": 4, "stack": true, "kind": "resource", "cat": "Tools", "color": Color(0.72, 0.74, 0.78)},
	"torch": {"name": "Torch", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "light", "color": Color(0.85, 0.5, 0.2)},
	"flashlight": {"name": "Flashlight", "era": Eras.SCIFI, "value": 60, "stack": false, "kind": "light", "color": Color(0.3, 0.32, 0.36)},
	"flashlight_dead": {"name": "Flashlight (dead battery)", "era": Eras.SCIFI, "value": 20, "stack": false, "kind": "light", "color": Color(0.22, 0.22, 0.24)},
	"binoculars": {"name": "Binoculars", "era": ANY, "value": 55, "stack": false, "kind": "tool", "zoom": true, "damage": 1, "range": 2.0, "color": Color(0.25, 0.27, 0.3)},
	"hammer": {"name": "Builder's Hammer", "era": ANY, "value": 30, "stack": false, "kind": "tool", "mine": 0.2, "chop": 0.25, "damage": 6, "range": 3.0, "build": true},
	"axe_mythril": {"name": "Mythril Axe", "era": Eras.FANTASY, "value": 130, "stack": false, "kind": "tool", "mine": 0.4, "chop": 2.0, "damage": 16, "range": 3.0},
	# Weapons
	"sword_iron": {"name": "Iron Sword", "era": Eras.MEDIEVAL, "value": 70, "stack": false, "kind": "weapon", "damage": 25, "range": 3.0},
	"sword_runic": {"name": "Runic Blade", "era": Eras.FANTASY, "value": 220, "stack": false, "kind": "weapon", "damage": 45, "range": 3.2},
	"pulse_pistol": {"name": "Pulse Pistol", "era": Eras.SCIFI, "value": 300, "stack": false, "kind": "weapon", "damage": 35, "range": 80.0, "ranged": true, "ammo": "power_cell", "shots_per_ammo": 12},
	# Ranged weapons, from the first crossbow to sci-fi rifles. "auto" fires while Use is
	# held; the rest fire once per pull. "tracer" colours the shot, "splash" is a blast radius.
	"crossbow": {"name": "Crossbow", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "weapon", "damage": 32, "range": 70.0, "ranged": true, "ammo": "bolt", "shots_per_ammo": 1, "cooldown": 0.9, "tracer": "bolt"},
	"crossbow_runic": {"name": "Runic Repeater", "era": Eras.FANTASY, "value": 240, "stack": false, "kind": "weapon", "damage": 42, "range": 90.0, "ranged": true, "ammo": "bolt", "shots_per_ammo": 1, "cooldown": 0.45, "tracer": "glow_violet"},
	"scrap_pistol": {"name": "Scrap Revolver", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "weapon", "damage": 24, "range": 60.0, "ranged": true, "ammo": "rounds", "shots_per_ammo": 1, "cooldown": 0.35, "tracer": "glow_warm"},
	"pulse_smg": {"name": "Pulse SMG", "era": Eras.SCIFI, "value": 420, "stack": false, "kind": "weapon", "damage": 11, "range": 70.0, "ranged": true, "ammo": "power_cell", "shots_per_ammo": 45, "cooldown": 0.08, "auto": true},
	"pulse_rifle": {"name": "Pulse Rifle", "era": Eras.SCIFI, "value": 560, "stack": false, "kind": "weapon", "damage": 20, "range": 140.0, "ranged": true, "ammo": "power_cell", "shots_per_ammo": 30, "cooldown": 0.13, "auto": true},
	"rail_rifle": {"name": "Rail Rifle", "era": Eras.SCIFI, "value": 800, "stack": false, "kind": "weapon", "damage": 95, "range": 320.0, "ranged": true, "ammo": "power_cell", "shots_per_ammo": 6, "cooldown": 1.2, "tracer": "glow_white"},
	"arc_launcher": {"name": "Arc Launcher", "era": Eras.SCIFI, "value": 900, "stack": false, "kind": "weapon", "damage": 70, "range": 90.0, "ranged": true, "ammo": "power_cell", "shots_per_ammo": 4, "cooldown": 1.0, "splash": 4.5, "tracer": "glow_violet"},
	# Armour: use it to put it on (see Game.equip). "armor" adds up across the four slots.
	"helm_iron": {"name": "Iron Helm", "era": Eras.MEDIEVAL, "value": 50, "stack": false, "kind": "armor", "slot": "head", "armor": 8, "color": Color(0.55, 0.56, 0.6)},
	"mail_iron": {"name": "Chainmail Hauberk", "era": Eras.MEDIEVAL, "value": 90, "stack": false, "kind": "armor", "slot": "chest", "armor": 16, "color": Color(0.5, 0.52, 0.56)},
	"greaves_iron": {"name": "Iron Greaves", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "armor", "slot": "legs", "armor": 10, "color": Color(0.5, 0.5, 0.54)},
	"boots_leather": {"name": "Leather Boots", "era": Eras.MEDIEVAL, "value": 25, "stack": false, "kind": "armor", "slot": "feet", "armor": 4, "color": Color(0.45, 0.3, 0.2)},
	"helm_elven": {"name": "Elven Leaf Helm", "era": Eras.FANTASY, "value": 150, "stack": false, "kind": "armor", "slot": "head", "armor": 13, "color": Color(0.4, 0.8, 0.75)},
	"plate_mythril": {"name": "Mythril Breastplate", "era": Eras.FANTASY, "value": 280, "stack": false, "kind": "armor", "slot": "chest", "armor": 26, "color": Color(0.7, 0.85, 1.0)},
	"guards_mythril": {"name": "Mythril Leg Guards", "era": Eras.FANTASY, "value": 180, "stack": false, "kind": "armor", "slot": "legs", "armor": 16, "color": Color(0.68, 0.82, 0.95)},
	"boots_elven": {"name": "Elven Boots", "era": Eras.FANTASY, "value": 90, "stack": false, "kind": "armor", "slot": "feet", "armor": 7, "color": Color(0.3, 0.55, 0.35)},
	"helm_visor": {"name": "Visor Helmet", "era": Eras.SCIFI, "value": 260, "stack": false, "kind": "armor", "slot": "head", "armor": 18, "color": Color(0.8, 0.82, 0.86)},
	"exo_chest": {"name": "Exo-Suit Chest", "era": Eras.SCIFI, "value": 520, "stack": false, "kind": "armor", "slot": "chest", "armor": 36, "color": Color(0.75, 0.77, 0.8)},
	"exo_legs": {"name": "Exo-Suit Legs", "era": Eras.SCIFI, "value": 340, "stack": false, "kind": "armor", "slot": "legs", "armor": 22, "color": Color(0.72, 0.74, 0.78)},
	"mag_boots": {"name": "Mag Boots", "era": Eras.SCIFI, "value": 160, "stack": false, "kind": "armor", "slot": "feet", "armor": 9, "color": Color(0.4, 0.42, 0.46)},
	"gloves_leather": {"name": "Leather Gloves", "era": Eras.MEDIEVAL, "value": 20, "stack": false, "kind": "armor", "slot": "hands", "armor": 3, "color": Color(0.4, 0.28, 0.2)},
	"shield_wood": {"name": "Round Shield", "era": Eras.MEDIEVAL, "value": 45, "stack": false, "kind": "armor", "slot": "shield", "armor": 10, "color": Color(0.55, 0.4, 0.25)},
	"bracers_rune": {"name": "Rune Bracers", "era": Eras.FANTASY, "value": 110, "stack": false, "kind": "armor", "slot": "hands", "armor": 6, "color": Color(0.7, 0.8, 0.9)},
	"shield_crystal": {"name": "Crescent Ward", "era": Eras.FANTASY, "value": 200, "stack": false, "kind": "armor", "slot": "shield", "armor": 16, "color": Color(0.6, 0.85, 1.0)},
	"gauntlets_power": {"name": "Power Gauntlets", "era": Eras.SCIFI, "value": 240, "stack": false, "kind": "armor", "slot": "hands", "armor": 9, "color": Color(0.45, 0.46, 0.5)},
	"shield_emitter": {"name": "Hex Shield Emitter", "era": Eras.SCIFI, "value": 380, "stack": false, "kind": "armor", "slot": "shield", "armor": 22, "color": Color(0.5, 0.85, 1.0)},
	# Jetpack: worn on the back; fire it in the air with Jump (see Jetpack). Burns Jet Fuel.
	"jetpack": {"name": "Jetpack", "era": ANY, "value": 450, "stack": false, "kind": "armor", "slot": "back", "armor": 2, "color": Color(0.62, 0.64, 0.68)},
	"jet_fuel": {"name": "Jet Fuel", "era": ANY, "value": 12, "stack": true, "kind": "resource", "cat": "Fuel", "color": Color(0.95, 0.55, 0.15)},
	# Heavier weapons; "swing" scales the time between swings.
	"battle_axe": {"name": "Battle Axe", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "weapon", "damage": 36, "range": 3.2, "swing": 1.3, "chop": 0.8},
	"war_hammer": {"name": "War Hammer", "era": Eras.MEDIEVAL, "value": 120, "stack": false, "kind": "weapon", "damage": 40, "range": 3.0, "swing": 1.45, "mine": 0.6},
	"mace": {"name": "Flanged Mace", "era": Eras.MEDIEVAL, "value": 90, "stack": false, "kind": "weapon", "damage": 30, "range": 2.8, "swing": 1.1},
	"spear": {"name": "Iron Spear", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "weapon", "damage": 24, "range": 4.4, "swing": 1.0},
	"dagger": {"name": "Curved Dagger", "era": ANY, "value": 50, "stack": false, "kind": "weapon", "damage": 15, "range": 2.4, "swing": 0.55, "skin": 1.0},
	# "skin": how well it butchers a carcass (CorpseLoot.blade_of).
	"skinning_knife": {"name": "Skinning Knife", "era": ANY, "value": 20, "stack": false, "kind": "tool", "damage": 9, "range": 2.4, "swing": 0.6, "skin": 1.5, "color": Color(0.7, 0.68, 0.62)},
	"longbow": {"name": "Longbow", "era": Eras.MEDIEVAL, "value": 80, "stack": false, "kind": "weapon", "damage": 30, "range": 95.0, "ranged": true, "ammo": "arrow", "shots_per_ammo": 1, "cooldown": 0.75, "tracer": "bolt"},
	"arrow": {"name": "Arrows", "era": ANY, "value": 1, "stack": true, "kind": "ammo", "color": Color(0.55, 0.42, 0.28)},
	# Dungeon treasure and potions.
	"rune_tablet": {"name": "Rune Tablet", "era": Eras.FANTASY, "value": 150, "stack": true, "kind": "treasure", "color": Color(0.6, 0.4, 1.0)},
	"gold_idol": {"name": "Golden Skull Idol", "era": Eras.MEDIEVAL, "value": 200, "stack": true, "kind": "treasure", "color": Color(1.0, 0.8, 0.3)},
	"void_gem": {"name": "Void Gem", "era": Eras.SCIFI, "value": 240, "stack": true, "kind": "treasure", "color": Color(0.7, 0.35, 1.0)},
	"dungeon_key": {"name": "Ornate Key", "era": ANY, "value": 40, "stack": true, "kind": "treasure", "color": Color(0.8, 0.65, 0.3)},
	"health_potion": {"name": "Health Potion", "era": ANY, "value": 30, "stack": true, "kind": "food", "cat": "Medicine", "heal": 80, "color": Color(0.9, 0.15, 0.15)},
	"stamina_potion": {"name": "Stamina Potion", "era": ANY, "value": 25, "stack": true, "kind": "food", "cat": "Medicine", "heal": 0, "stamina": true, "color": Color(0.3, 0.9, 0.35)},
	"bolt": {"name": "Crossbow Bolts", "era": ANY, "value": 1, "stack": true, "kind": "ammo", "color": Color(0.6, 0.45, 0.3)},
	"rounds": {"name": "Revolver Rounds", "era": ANY, "value": 2, "stack": true, "kind": "ammo", "color": Color(0.8, 0.65, 0.3)},
	# Vehicles: use one to set it down in the world, then ride it (see Vehicle).
	"speeder": {"name": "Hover Speeder", "era": Eras.SCIFI, "value": 420, "stack": false, "kind": "vehicle", "color": Color(1.0, 0.65, 0.15)},
	"rover": {"name": "Survey Rover", "era": Eras.SCIFI, "value": 380, "stack": false, "kind": "vehicle", "color": Color(0.85, 0.85, 0.9)},
	"ship": {"name": "Starship", "era": Eras.SCIFI, "value": 1600, "stack": false, "kind": "vehicle", "color": Color(0.95, 0.7, 0.25)},
	"horse": {"name": "Riding Horse", "era": Eras.MEDIEVAL, "value": 180, "stack": false, "kind": "vehicle", "color": Color(0.55, 0.38, 0.25)},

	# --- The medieval age (icon sheets items4-9) ----------------------------------------
	# Raw and worked materials. "fuel": seconds it burns (lanterns, smelting); see Effects
	# for what food, potions, scrolls and trinkets do.
	"flint": {"name": "Flint", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "resource", "color": Color(0.35, 0.34, 0.33)},
	"clay": {"name": "Clay", "era": Eras.MEDIEVAL, "value": 1, "stack": true, "kind": "resource", "color": Color(0.66, 0.46, 0.34)},
	"brick": {"name": "Brick", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.66, 0.32, 0.22)},
	"rope": {"name": "Rope", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "resource", "color": Color(0.72, 0.6, 0.4)},
	"cloth": {"name": "Cloth", "era": Eras.MEDIEVAL, "value": 5, "stack": true, "kind": "resource", "color": Color(0.82, 0.78, 0.68)},
	"wool": {"name": "Wool", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.92, 0.9, 0.85)},
	"flax": {"name": "Flax", "era": Eras.MEDIEVAL, "value": 1, "stack": true, "kind": "resource", "color": Color(0.7, 0.68, 0.42)},
	"resin": {"name": "Resin", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "fuel": 300.0, "color": Color(0.85, 0.55, 0.15)},
	"charcoal": {"name": "Charcoal", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "fuel": 600.0, "color": Color(0.15, 0.15, 0.16)},
	"salt": {"name": "Salt", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "cat": "Food", "color": Color(0.95, 0.95, 0.93)},
	"beeswax": {"name": "Beeswax", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "resource", "fuel": 450.0, "color": Color(0.92, 0.78, 0.35)},
	"lamp_oil": {"name": "Lamp Oil", "era": Eras.MEDIEVAL, "value": 6, "stack": true, "kind": "resource", "cat": "Fuel", "fuel": 1800.0, "color": Color(0.85, 0.7, 0.3)},
	"copper_ore": {"name": "Copper Ore", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "resource", "color": Color(0.6, 0.4, 0.3)},
	"tin_ore": {"name": "Tin Ore", "era": Eras.MEDIEVAL, "value": 5, "stack": true, "kind": "resource", "color": Color(0.55, 0.55, 0.52)},
	"coal": {"name": "Coal", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "fuel": 900.0, "color": Color(0.1, 0.1, 0.11)},
	"silver_ore": {"name": "Silver Ore", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "resource", "color": Color(0.7, 0.72, 0.74)},
	"gold_ore": {"name": "Gold Ore", "era": Eras.MEDIEVAL, "value": 22, "stack": true, "kind": "resource", "color": Color(0.8, 0.65, 0.3)},
	"salt_crystal": {"name": "Rock Salt", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.9, 0.82, 0.8)},
	"copper_ingot": {"name": "Copper Ingot", "era": Eras.MEDIEVAL, "value": 10, "stack": true, "kind": "resource", "color": Color(0.78, 0.45, 0.28)},
	"bronze_ingot": {"name": "Bronze Ingot", "era": Eras.MEDIEVAL, "value": 16, "stack": true, "kind": "resource", "color": Color(0.75, 0.55, 0.3)},
	"steel_ingot": {"name": "Steel Ingot", "era": Eras.MEDIEVAL, "value": 26, "stack": true, "kind": "resource", "color": Color(0.7, 0.72, 0.76)},
	"silver_ingot": {"name": "Silver Ingot", "era": Eras.MEDIEVAL, "value": 30, "stack": true, "kind": "resource", "color": Color(0.85, 0.86, 0.9)},
	"gold_ingot": {"name": "Gold Ingot", "era": Eras.MEDIEVAL, "value": 55, "stack": true, "kind": "resource", "color": Color(0.95, 0.75, 0.3)},
	"iron_nails": {"name": "Iron Nails", "era": Eras.MEDIEVAL, "value": 1, "stack": true, "kind": "resource", "color": Color(0.45, 0.45, 0.47)},
	# Weapons, from a club and a flint knife to a knight's sword. "thrown": the stack is
	# its own ammunition (Gunplay).
	"wooden_club": {"name": "Wooden Club", "era": Eras.MEDIEVAL, "value": 8, "stack": false, "kind": "weapon", "damage": 12, "range": 2.8, "swing": 0.95},
	"stone_knife": {"name": "Stone Knife", "era": Eras.MEDIEVAL, "value": 6, "stack": false, "kind": "weapon", "damage": 9, "range": 2.3, "swing": 0.55, "skin": 1.1},
	"sling": {"name": "Sling", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "weapon", "damage": 14, "range": 40.0, "ranged": true, "ammo": "stone", "shots_per_ammo": 1, "cooldown": 0.7, "tracer": "bolt"},
	"shortbow": {"name": "Shortbow", "era": Eras.MEDIEVAL, "value": 30, "stack": false, "kind": "weapon", "damage": 20, "range": 65.0, "ranged": true, "ammo": "arrow", "shots_per_ammo": 1, "cooldown": 0.6, "tracer": "bolt"},
	"hunting_spear": {"name": "Hunting Spear", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "weapon", "damage": 16, "range": 4.2, "swing": 1.0},
	"hand_axe": {"name": "Hand Axe", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "weapon", "damage": 14, "range": 2.8, "swing": 0.85, "chop": 0.6},
	"bronze_sword": {"name": "Bronze Sword", "era": Eras.MEDIEVAL, "value": 45, "stack": false, "kind": "weapon", "damage": 20, "range": 3.0, "swing": 0.95},
	"bronze_spear": {"name": "Bronze Spear", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "weapon", "damage": 21, "range": 4.4, "swing": 1.0},
	"bronze_axe": {"name": "Bronze Axe", "era": Eras.MEDIEVAL, "value": 48, "stack": false, "kind": "weapon", "damage": 26, "range": 3.0, "swing": 1.15, "chop": 0.7},
	"cudgel": {"name": "Iron-shod Cudgel", "era": Eras.MEDIEVAL, "value": 30, "stack": false, "kind": "weapon", "damage": 24, "range": 2.8, "swing": 1.0},
	"throwing_knives": {"name": "Throwing Knives", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "weapon", "damage": 16, "range": 30.0, "ranged": true, "thrown": true, "ammo": "throwing_knives", "shots_per_ammo": 1, "cooldown": 0.5, "tracer": "bolt"},
	"javelin": {"name": "Javelins", "era": Eras.MEDIEVAL, "value": 6, "stack": true, "kind": "weapon", "damage": 24, "range": 45.0, "ranged": true, "thrown": true, "ammo": "javelin", "shots_per_ammo": 1, "cooldown": 0.8, "tracer": "bolt"},
	"steel_sword": {"name": "Steel Longsword", "era": Eras.MEDIEVAL, "value": 130, "stack": false, "kind": "weapon", "damage": 33, "range": 3.1, "swing": 1.0},
	"falchion": {"name": "Falchion", "era": Eras.MEDIEVAL, "value": 90, "stack": false, "kind": "weapon", "damage": 27, "range": 2.9, "swing": 0.9},
	"rapier": {"name": "Rapier", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "weapon", "damage": 24, "range": 3.3, "swing": 0.6},
	"zweihander": {"name": "Greatsword", "era": Eras.MEDIEVAL, "value": 190, "stack": false, "kind": "weapon", "damage": 50, "range": 3.6, "swing": 1.55},
	"halberd": {"name": "Halberd", "era": Eras.MEDIEVAL, "value": 140, "stack": false, "kind": "weapon", "damage": 38, "range": 4.6, "swing": 1.35, "chop": 0.5},
	"morning_star": {"name": "Morning Star", "era": Eras.MEDIEVAL, "value": 100, "stack": false, "kind": "weapon", "damage": 33, "range": 2.9, "swing": 1.15},
	"flail": {"name": "Flail", "era": Eras.MEDIEVAL, "value": 105, "stack": false, "kind": "weapon", "damage": 35, "range": 3.0, "swing": 1.25},
	"warpick": {"name": "War Pick", "era": Eras.MEDIEVAL, "value": 95, "stack": false, "kind": "weapon", "damage": 30, "range": 2.9, "swing": 1.1, "mine": 0.7},
	"glaive": {"name": "Glaive", "era": Eras.MEDIEVAL, "value": 100, "stack": false, "kind": "weapon", "damage": 30, "range": 4.6, "swing": 1.2},
	"composite_bow": {"name": "Composite Bow", "era": Eras.MEDIEVAL, "value": 120, "stack": false, "kind": "weapon", "damage": 34, "range": 105.0, "ranged": true, "ammo": "arrow", "shots_per_ammo": 1, "cooldown": 0.7, "tracer": "bolt"},
	"heavy_crossbow": {"name": "Heavy Crossbow", "era": Eras.MEDIEVAL, "value": 160, "stack": false, "kind": "weapon", "damage": 48, "range": 90.0, "ranged": true, "ammo": "bolt", "shots_per_ammo": 1, "cooldown": 1.5, "tracer": "bolt"},
	"quarterstaff": {"name": "Quarterstaff", "era": Eras.MEDIEVAL, "value": 8, "stack": false, "kind": "weapon", "damage": 14, "range": 3.4, "swing": 0.85},
	"knight_sword": {"name": "Knight's Sword", "era": Eras.MEDIEVAL, "value": 320, "stack": false, "kind": "weapon", "damage": 42, "range": 3.2, "swing": 1.0},
	"executioner_axe": {"name": "Executioner's Axe", "era": Eras.MEDIEVAL, "value": 360, "stack": false, "kind": "weapon", "damage": 58, "range": 3.3, "swing": 1.6, "chop": 1.0},
	"royal_bow": {"name": "Royal Longbow", "era": Eras.MEDIEVAL, "value": 380, "stack": false, "kind": "weapon", "damage": 42, "range": 120.0, "ranged": true, "ammo": "arrow", "shots_per_ammo": 1, "cooldown": 0.65, "tracer": "bolt"},
	"dragonbone_dagger": {"name": "Dragonbone Dagger", "era": Eras.MEDIEVAL, "value": 600, "stack": false, "kind": "weapon", "damage": 30, "range": 2.5, "swing": 0.5, "skin": 2.0},
	"kings_mace": {"name": "King's Mace", "era": Eras.MEDIEVAL, "value": 650, "stack": false, "kind": "weapon", "damage": 46, "range": 2.9, "swing": 1.1},
	# Bows fire these before plain arrows, for 30% more damage.
	"broadhead_arrows": {"name": "Broadhead Arrows", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "ammo", "color": Color(0.5, 0.45, 0.4)},
	# Armour sets: cloth, hide, studded leather, bronze and steel. "look" picks how it is
	# drawn on the body (Outfit.look_of).
	"cap_cloth": {"name": "Cloth Cap", "era": Eras.MEDIEVAL, "value": 6, "stack": false, "kind": "armor", "slot": "head", "armor": 2, "look": "cloth", "color": Color(0.62, 0.55, 0.42)},
	"tunic_padded": {"name": "Padded Gambeson", "era": Eras.MEDIEVAL, "value": 18, "stack": false, "kind": "armor", "slot": "chest", "armor": 6, "look": "cloth", "color": Color(0.7, 0.62, 0.48)},
	"wraps_cloth": {"name": "Cloth Hand Wraps", "era": Eras.MEDIEVAL, "value": 4, "stack": false, "kind": "armor", "slot": "hands", "armor": 1, "look": "cloth", "color": Color(0.78, 0.74, 0.64)},
	"trousers_wool": {"name": "Wool Trousers", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "armor", "slot": "legs", "armor": 3, "look": "cloth", "color": Color(0.42, 0.4, 0.36)},
	"shoes_cloth": {"name": "Cloth Shoes", "era": Eras.MEDIEVAL, "value": 5, "stack": false, "kind": "armor", "slot": "feet", "armor": 1, "look": "cloth", "color": Color(0.5, 0.42, 0.32)},
	"buckler_wood": {"name": "Wooden Buckler", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "armor", "slot": "shield", "armor": 5, "color": Color(0.6, 0.45, 0.28)},
	"cap_hide": {"name": "Hide Cap", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "armor", "slot": "head", "armor": 4, "look": "leather", "color": Color(0.55, 0.4, 0.27)},
	"vest_hide": {"name": "Hide Vest", "era": Eras.MEDIEVAL, "value": 25, "stack": false, "kind": "armor", "slot": "chest", "armor": 8, "look": "leather", "color": Color(0.55, 0.4, 0.27)},
	"gloves_hide": {"name": "Hide Gloves", "era": Eras.MEDIEVAL, "value": 8, "stack": false, "kind": "armor", "slot": "hands", "armor": 2, "look": "leather", "color": Color(0.52, 0.38, 0.26)},
	"leggings_hide": {"name": "Hide Leggings", "era": Eras.MEDIEVAL, "value": 16, "stack": false, "kind": "armor", "slot": "legs", "armor": 5, "look": "leather", "color": Color(0.5, 0.37, 0.25)},
	"boots_hide": {"name": "Hide Boots", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "armor", "slot": "feet", "armor": 2, "look": "leather", "color": Color(0.48, 0.35, 0.24)},
	"shield_hide": {"name": "Hide Shield", "era": Eras.MEDIEVAL, "value": 18, "stack": false, "kind": "armor", "slot": "shield", "armor": 7, "color": Color(0.58, 0.44, 0.3)},
	"helm_studded": {"name": "Studded Leather Hood", "era": Eras.MEDIEVAL, "value": 30, "stack": false, "kind": "armor", "slot": "head", "armor": 6, "look": "leather", "color": Color(0.38, 0.26, 0.17)},
	"jerkin_studded": {"name": "Studded Jerkin", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "armor", "slot": "chest", "armor": 12, "look": "leather", "color": Color(0.38, 0.26, 0.17)},
	"gloves_studded": {"name": "Studded Gloves", "era": Eras.MEDIEVAL, "value": 22, "stack": false, "kind": "armor", "slot": "hands", "armor": 4, "look": "leather", "color": Color(0.36, 0.25, 0.16)},
	"pants_studded": {"name": "Studded Leggings", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "armor", "slot": "legs", "armor": 7, "look": "leather", "color": Color(0.36, 0.25, 0.16)},
	"boots_studded": {"name": "Studded Boots", "era": Eras.MEDIEVAL, "value": 26, "stack": false, "kind": "armor", "slot": "feet", "armor": 5, "look": "leather", "color": Color(0.34, 0.24, 0.16)},
	"shield_kite": {"name": "Kite Shield", "era": Eras.MEDIEVAL, "value": 55, "stack": false, "kind": "armor", "slot": "shield", "armor": 13, "color": Color(0.55, 0.2, 0.18)},
	"helm_bronze": {"name": "Bronze Helm", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "armor", "slot": "head", "armor": 7, "look": "plate", "color": Color(0.72, 0.52, 0.3)},
	"cuirass_bronze": {"name": "Bronze Cuirass", "era": Eras.MEDIEVAL, "value": 80, "stack": false, "kind": "armor", "slot": "chest", "armor": 14, "look": "plate", "color": Color(0.72, 0.52, 0.3)},
	"bracers_bronze": {"name": "Bronze Bracers", "era": Eras.MEDIEVAL, "value": 28, "stack": false, "kind": "armor", "slot": "hands", "armor": 4, "look": "plate", "color": Color(0.7, 0.5, 0.29)},
	"greaves_bronze": {"name": "Bronze Greaves", "era": Eras.MEDIEVAL, "value": 55, "stack": false, "kind": "armor", "slot": "legs", "armor": 9, "look": "plate", "color": Color(0.7, 0.5, 0.29)},
	"sandals_bronze": {"name": "Bronze-shod Sandals", "era": Eras.MEDIEVAL, "value": 20, "stack": false, "kind": "armor", "slot": "feet", "armor": 3, "look": "leather", "color": Color(0.5, 0.36, 0.22)},
	"shield_bronze": {"name": "Bronze Round Shield", "era": Eras.MEDIEVAL, "value": 45, "stack": false, "kind": "armor", "slot": "shield", "armor": 11, "look": "plate", "color": Color(0.74, 0.54, 0.3)},
	"helm_steel": {"name": "Steel Great Helm", "era": Eras.MEDIEVAL, "value": 140, "stack": false, "kind": "armor", "slot": "head", "armor": 11, "look": "plate", "color": Color(0.68, 0.7, 0.74)},
	"plate_steel": {"name": "Steel Breastplate", "era": Eras.MEDIEVAL, "value": 260, "stack": false, "kind": "armor", "slot": "chest", "armor": 22, "look": "plate", "color": Color(0.68, 0.7, 0.74)},
	"gauntlets_steel": {"name": "Steel Gauntlets", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "armor", "slot": "hands", "armor": 6, "look": "plate", "color": Color(0.66, 0.68, 0.72)},
	"cuisses_steel": {"name": "Steel Leg Plates", "era": Eras.MEDIEVAL, "value": 170, "stack": false, "kind": "armor", "slot": "legs", "armor": 14, "look": "plate", "color": Color(0.66, 0.68, 0.72)},
	"sabatons_steel": {"name": "Steel Sabatons", "era": Eras.MEDIEVAL, "value": 100, "stack": false, "kind": "armor", "slot": "feet", "armor": 6, "look": "plate", "color": Color(0.64, 0.66, 0.7)},
	"shield_tower": {"name": "Tower Shield", "era": Eras.MEDIEVAL, "value": 150, "stack": false, "kind": "armor", "slot": "shield", "armor": 18, "look": "plate", "color": Color(0.62, 0.64, 0.68)},
	# Tools. "dig": shovels move earth; "reap": more from each plant you pick; "fish": casts
	# a line into water. "need" tools sit in the pack for recipes (Recipes "tools").
	"pickaxe_stone": {"name": "Stone Pickaxe", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "tool", "mine": 0.55, "chop": 0.2, "damage": 6, "range": 3.0, "dig": 0.35},
	"axe_stone": {"name": "Stone Axe", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "tool", "mine": 0.15, "chop": 0.55, "damage": 8, "range": 3.0},
	"pickaxe_bronze": {"name": "Bronze Pickaxe", "era": Eras.MEDIEVAL, "value": 32, "stack": false, "kind": "tool", "mine": 0.8, "chop": 0.25, "damage": 7, "range": 3.0, "dig": 0.5},
	"pickaxe_steel": {"name": "Steel Pickaxe", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "tool", "mine": 1.4, "chop": 0.35, "damage": 10, "range": 3.0, "dig": 0.8},
	"axe_steel": {"name": "Steel Axe", "era": Eras.MEDIEVAL, "value": 100, "stack": false, "kind": "tool", "mine": 0.35, "chop": 1.4, "damage": 15, "range": 3.0},
	"shovel": {"name": "Shovel", "era": Eras.MEDIEVAL, "value": 20, "stack": false, "kind": "tool", "mine": 0.2, "chop": 0.1, "damage": 7, "range": 3.0, "dig": 1.4},
	"hoe": {"name": "Hoe", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "tool", "damage": 6, "range": 3.0, "dig": 0.7, "reap": 1.5},
	"sickle": {"name": "Sickle", "era": Eras.MEDIEVAL, "value": 18, "stack": false, "kind": "tool", "chop": 0.35, "damage": 10, "range": 2.6, "swing": 0.7, "reap": 2.0},
	"fishing_rod": {"name": "Fishing Rod", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "tool", "damage": 1, "range": 2.0, "fish": 1.0},
	"saw": {"name": "Hand Saw", "era": Eras.MEDIEVAL, "value": 22, "stack": false, "kind": "tool", "chop": 0.5, "damage": 5, "range": 2.6, "need": true},
	"tongs": {"name": "Smith's Tongs", "era": Eras.MEDIEVAL, "value": 18, "stack": false, "kind": "tool", "damage": 4, "range": 2.4, "need": true},
	"bucket": {"name": "Bucket", "era": Eras.MEDIEVAL, "value": 10, "stack": false, "kind": "tool", "damage": 3, "range": 2.4, "need": true},
	"waterskin": {"name": "Waterskin", "era": Eras.MEDIEVAL, "value": 14, "stack": false, "kind": "food", "cat": "Food", "drink": true, "keep": true, "stamina_add": 35, "color": Color(0.5, 0.36, 0.22)},
	"hand_lantern": {"name": "Lantern", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "light", "color": Color(0.45, 0.42, 0.38)},
	"candle": {"name": "Candle", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "light", "fuel": 600.0, "color": Color(0.95, 0.9, 0.75)},
	"tinderbox": {"name": "Tinderbox", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "tool", "cat": "Fuel", "damage": 2, "range": 2.0, "need": true},
	"bedroll": {"name": "Bedroll", "era": Eras.MEDIEVAL, "value": 20, "stack": false, "kind": "camp", "sleep": 1.0, "color": Color(0.55, 0.4, 0.3)},
	"tent_kit": {"name": "Tent Kit", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "camp", "sleep": 2.0, "color": Color(0.72, 0.65, 0.5)},
	# Trinkets: worn on a finger or round the neck. "bonus" adds to your stats (Effects).
	"ring_copper": {"name": "Copper Ring", "era": Eras.MEDIEVAL, "value": 20, "stack": false, "kind": "armor", "slot": "ring", "armor": 1, "bonus": {"stamina": 10.0}, "color": Color(0.78, 0.45, 0.28)},
	"ring_silver": {"name": "Silver Ring", "era": Eras.MEDIEVAL, "value": 70, "stack": false, "kind": "armor", "slot": "ring", "armor": 1, "bonus": {"stamina": 20.0}, "color": Color(0.85, 0.86, 0.9)},
	"ring_ruby": {"name": "Ruby Ring", "era": Eras.MEDIEVAL, "value": 300, "stack": false, "kind": "armor", "slot": "ring", "armor": 2, "bonus": {"damage": 0.1}, "color": Color(0.85, 0.15, 0.2)},
	"amulet_bone": {"name": "Bone Charm", "era": Eras.MEDIEVAL, "value": 15, "stack": false, "kind": "armor", "slot": "neck", "armor": 0, "bonus": {"carry": 60.0}, "color": Color(0.9, 0.87, 0.78)},
	"amulet_silver": {"name": "Silver Locket", "era": Eras.MEDIEVAL, "value": 80, "stack": false, "kind": "armor", "slot": "neck", "armor": 1, "bonus": {"health": 15.0}, "color": Color(0.85, 0.86, 0.9)},
	"amulet_saint": {"name": "Saint's Medallion", "era": Eras.MEDIEVAL, "value": 320, "stack": false, "kind": "armor", "slot": "neck", "armor": 4, "bonus": {"regen": 0.3}, "color": Color(0.95, 0.78, 0.35)},
	"lucky_coin": {"name": "Lucky Coin", "era": Eras.MEDIEVAL, "value": 50, "stack": false, "kind": "armor", "slot": "neck", "armor": 0, "bonus": {"xp": 0.1}, "color": Color(0.95, 0.75, 0.3)},
	"dice": {"name": "Bone Dice", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "treasure", "color": Color(0.92, 0.88, 0.78)},
	# Played (Use) for a short spell of inspiration; read for experience.
	"lute": {"name": "Lute", "era": Eras.MEDIEVAL, "value": 80, "stack": false, "kind": "instrument", "play": "inspired", "color": Color(0.65, 0.42, 0.22)},
	"flute": {"name": "Wooden Flute", "era": Eras.MEDIEVAL, "value": 25, "stack": false, "kind": "instrument", "play": "inspired", "color": Color(0.7, 0.55, 0.35)},
	"book_leather": {"name": "Old Book", "era": Eras.MEDIEVAL, "value": 35, "stack": true, "kind": "scroll", "read": "book", "color": Color(0.45, 0.28, 0.18)},
	# Food and drink. "heal" at once, "regen" over time, "buff" for a while (Effects).
	"apple": {"name": "Apple", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 12, "color": Color(0.8, 0.2, 0.15)},
	"pear": {"name": "Pear", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 12, "color": Color(0.75, 0.75, 0.3)},
	"carrot": {"name": "Carrot", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 10, "color": Color(0.95, 0.5, 0.15)},
	"potato": {"name": "Potato", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 6, "color": Color(0.7, 0.55, 0.35)},
	"onion": {"name": "Onion", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 5, "color": Color(0.8, 0.6, 0.45)},
	"cabbage": {"name": "Cabbage", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "heal": 10, "color": Color(0.5, 0.75, 0.35)},
	"wheat": {"name": "Wheat", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "crop", "color": Color(0.88, 0.75, 0.4)},
	"flour": {"name": "Flour", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "ingredient", "color": Color(0.95, 0.93, 0.88)},
	"egg": {"name": "Eggs", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "ingredient", "color": Color(0.95, 0.9, 0.8)},
	"milk": {"name": "Milk", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "drink": true, "heal": 8, "stamina_add": 20, "color": Color(0.97, 0.97, 0.95)},
	"honey": {"name": "Honey", "era": Eras.MEDIEVAL, "value": 5, "stack": true, "kind": "food", "heal": 10, "stamina_add": 15, "color": Color(0.95, 0.7, 0.2)},
	"mushroom": {"name": "Mushrooms", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 8, "color": Color(0.7, 0.6, 0.5)},
	"fish_raw": {"name": "Raw Fish", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "heal": 6, "sicken": 0.2, "color": Color(0.6, 0.65, 0.7)},
	"fish_cooked": {"name": "Grilled Fish", "era": Eras.MEDIEVAL, "value": 7, "stack": true, "kind": "food", "heal": 35, "color": Color(0.8, 0.6, 0.35)},
	"chicken_roast": {"name": "Roast Chicken", "era": Eras.MEDIEVAL, "value": 14, "stack": true, "kind": "food", "heal": 50, "regen": 20, "color": Color(0.75, 0.5, 0.25)},
	"ham": {"name": "Ham", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "food", "heal": 45, "color": Color(0.8, 0.45, 0.4)},
	"sausage": {"name": "Sausages", "era": Eras.MEDIEVAL, "value": 6, "stack": true, "kind": "food", "heal": 30, "color": Color(0.6, 0.3, 0.2)},
	"salted_meat": {"name": "Salted Meat", "era": Eras.MEDIEVAL, "value": 6, "stack": true, "kind": "food", "heal": 30, "color": Color(0.65, 0.35, 0.3)},
	"stew": {"name": "Stew", "era": Eras.MEDIEVAL, "value": 16, "stack": true, "kind": "food", "heal": 60, "regen": 30, "color": Color(0.55, 0.35, 0.2)},
	"porridge": {"name": "Porridge", "era": Eras.MEDIEVAL, "value": 8, "stack": true, "kind": "food", "heal": 30, "stamina_add": 30, "color": Color(0.85, 0.8, 0.65)},
	"pie_meat": {"name": "Meat Pie", "era": Eras.MEDIEVAL, "value": 18, "stack": true, "kind": "food", "heal": 65, "regen": 25, "color": Color(0.75, 0.5, 0.25)},
	"pie_berry": {"name": "Berry Pie", "era": Eras.MEDIEVAL, "value": 14, "stack": true, "kind": "food", "heal": 40, "stamina_add": 40, "color": Color(0.6, 0.2, 0.3)},
	"soup_veg": {"name": "Vegetable Soup", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "food", "heal": 45, "regen": 25, "color": Color(0.7, 0.55, 0.25)},
	"travel_bread": {"name": "Travel Loaf", "era": Eras.MEDIEVAL, "value": 8, "stack": true, "kind": "food", "heal": 35, "color": Color(0.7, 0.5, 0.28)},
	"pumpkin": {"name": "Pumpkin", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "food", "heal": 15, "color": Color(0.95, 0.55, 0.15)},
	"corn": {"name": "Corn", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "food", "heal": 10, "color": Color(0.95, 0.85, 0.3)},
	"grapes": {"name": "Grapes", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "heal": 12, "color": Color(0.45, 0.2, 0.5)},
	"wine": {"name": "Wine", "era": Eras.MEDIEVAL, "value": 14, "stack": true, "kind": "food", "drink": true, "heal": 10, "buff": ["courage", 120.0], "color": Color(0.55, 0.1, 0.18)},
	"mead": {"name": "Mead", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "food", "drink": true, "heal": 12, "buff": ["courage", 180.0], "color": Color(0.9, 0.65, 0.25)},
	"jam": {"name": "Berry Jam", "era": Eras.MEDIEVAL, "value": 8, "stack": true, "kind": "food", "heal": 25, "stamina_add": 20, "color": Color(0.65, 0.12, 0.25)},
	# Potions, medicine and herbs.
	"potion_health_minor": {"name": "Minor Health Draught", "era": Eras.MEDIEVAL, "value": 15, "stack": true, "kind": "food", "cat": "Medicine", "heal": 40, "color": Color(0.85, 0.2, 0.2)},
	"potion_health_greater": {"name": "Greater Health Draught", "era": Eras.MEDIEVAL, "value": 60, "stack": true, "kind": "food", "cat": "Medicine", "heal": 120, "regen": 40, "color": Color(0.95, 0.1, 0.15)},
	"potion_stamina_greater": {"name": "Greater Stamina Draught", "era": Eras.MEDIEVAL, "value": 50, "stack": true, "kind": "food", "cat": "Medicine", "stamina": true, "buff": ["vigor", 180.0], "color": Color(0.25, 0.85, 0.3)},
	"antidote": {"name": "Antidote", "era": Eras.MEDIEVAL, "value": 20, "stack": true, "kind": "food", "cat": "Medicine", "cure": true, "buff": ["immune", 300.0], "color": Color(0.45, 0.75, 0.6)},
	"tonic_warmth": {"name": "Warming Tonic", "era": Eras.MEDIEVAL, "value": 20, "stack": true, "kind": "food", "cat": "Medicine", "buff": ["hardy", 300.0], "color": Color(0.9, 0.45, 0.2)},
	"tonic_cooling": {"name": "Cooling Tonic", "era": Eras.MEDIEVAL, "value": 20, "stack": true, "kind": "food", "cat": "Medicine", "buff": ["refreshed", 300.0], "color": Color(0.4, 0.7, 0.9)},
	"elixir_strength": {"name": "Elixir of Strength", "era": Eras.MEDIEVAL, "value": 90, "stack": true, "kind": "food", "cat": "Medicine", "buff": ["strength", 180.0], "color": Color(0.8, 0.25, 0.15)},
	"elixir_swiftness": {"name": "Elixir of Swiftness", "era": Eras.MEDIEVAL, "value": 90, "stack": true, "kind": "food", "cat": "Medicine", "buff": ["swift", 180.0], "color": Color(0.4, 0.85, 0.75)},
	"elixir_nightsight": {"name": "Night-eye Drops", "era": Eras.MEDIEVAL, "value": 25, "stack": true, "kind": "food", "cat": "Medicine", "buff": ["nightsight", 600.0], "color": Color(0.35, 0.4, 0.6)},
	"salve": {"name": "Healing Salve", "era": Eras.MEDIEVAL, "value": 12, "stack": true, "kind": "food", "cat": "Medicine", "heal": 20, "regen": 40, "color": Color(0.7, 0.75, 0.5)},
	"bandage_linen": {"name": "Linen Bandage", "era": Eras.MEDIEVAL, "value": 6, "stack": true, "kind": "food", "cat": "Medicine", "heal": 10, "regen": 30, "color": Color(0.92, 0.9, 0.85)},
	"herbal_poultice": {"name": "Herbal Poultice", "era": Eras.MEDIEVAL, "value": 14, "stack": true, "kind": "food", "cat": "Medicine", "regen": 50, "cure": true, "color": Color(0.45, 0.6, 0.3)},
	"herb_red": {"name": "Bloodwort", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "herb", "color": Color(0.75, 0.15, 0.2)},
	"herb_blue": {"name": "Frostleaf", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "herb", "color": Color(0.4, 0.55, 0.85)},
	"herb_yellow": {"name": "Sunpetal", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "herb", "color": Color(0.95, 0.8, 0.2)},
	"herb_root": {"name": "Ironroot", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "herb", "color": Color(0.55, 0.4, 0.3)},
	"herb_mint": {"name": "Wild Mint", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "herb", "color": Color(0.45, 0.8, 0.45)},
	"herb_nightshade": {"name": "Nightshade", "era": Eras.MEDIEVAL, "value": 5, "stack": true, "kind": "herb", "color": Color(0.35, 0.2, 0.45)},
	# Scrolls: read one (Use) for its effect.
	"scroll_plain": {"name": "Blank Scroll", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.9, 0.85, 0.7)},
	"scroll_red": {"name": "Scroll of Courage", "era": Eras.MEDIEVAL, "value": 35, "stack": true, "kind": "scroll", "read": "courage", "color": Color(0.8, 0.25, 0.2)},
	"scroll_blue": {"name": "Scroll of Warding", "era": Eras.MEDIEVAL, "value": 35, "stack": true, "kind": "scroll", "read": "warded", "color": Color(0.3, 0.45, 0.8)},
	"scroll_green": {"name": "Scroll of Return", "era": Eras.MEDIEVAL, "value": 60, "stack": true, "kind": "scroll", "read": "return", "color": Color(0.3, 0.7, 0.35)},
	"letter_sealed": {"name": "Sealed Letter", "era": Eras.MEDIEVAL, "value": 30, "stack": true, "kind": "treasure", "color": Color(0.88, 0.82, 0.68)},
	"quill_ink": {"name": "Quill and Ink", "era": Eras.MEDIEVAL, "value": 15, "stack": false, "kind": "tool", "damage": 1, "range": 2.0, "need": true},
	"mortar_pestle": {"name": "Mortar and Pestle", "era": Eras.MEDIEVAL, "value": 12, "stack": false, "kind": "tool", "damage": 3, "range": 2.0, "need": true},
	"empty_vial": {"name": "Empty Vial", "era": Eras.MEDIEVAL, "value": 2, "stack": true, "kind": "resource", "color": Color(0.75, 0.6, 0.45)},
	"empty_bottle": {"name": "Empty Bottle", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "resource", "color": Color(0.6, 0.45, 0.3)},
	"cauldron_small": {"name": "Brewing Pot", "era": Eras.MEDIEVAL, "value": 30, "stack": false, "kind": "tool", "damage": 4, "range": 2.0, "need": true},
	"holy_water": {"name": "Holy Water", "era": Eras.MEDIEVAL, "value": 40, "stack": true, "kind": "food", "cat": "Medicine", "drink": true, "heal": 30, "cure": true, "buff": ["warded", 120.0], "color": Color(0.75, 0.85, 0.95)},
	"smelling_salts": {"name": "Smelling Salts", "era": Eras.MEDIEVAL, "value": 10, "stack": true, "kind": "food", "cat": "Medicine", "stamina": true, "color": Color(0.9, 0.9, 0.85)},
}

## Player level that unlocks making (and placing) a thing, on themed worlds: the starting
## era's basics from level 1, its sturdier work over the first levels, and anything of
## the advanced era from Eras.UNLOCK_LEVEL, its best pieces later still (a starship at
## 35). Older worlds lock nothing.
const SHIP_LEVEL := 35
const UNLOCK := {
	# Medieval building and stations.
	"wall_stone": 3, "roof_small": 2, "roof_large": 4, "stairs_wood": 2, "foundation": 2,
	"forge": 3, "anvil": 5, "stable": 6, "storage_chest": 2, "bed": 2, "lantern": 2,
	"metal_crate": 3, "cage": 4, "weapon_stand": 4, "market_stall": 5, "cart": 5, "horse": 7,
	"binoculars": 3, "waystone": 8, "cauldron": 10, "jetpack": 12, "jet_fuel": 12,
	# Gunpowder is the first step out of the medieval age.
	"scrap_pistol": 10, "rounds": 10,
	# Advanced gear: tech, vehicles, teleporters and starships.
	"fabricator": 10, "flashlight": 10, "pulse_pistol": 10, "pulse_smg": 12, "pulse_rifle": 14,
	"rail_rifle": 18, "arc_launcher": 22, "pickaxe_plasma": 12, "crossbow_runic": 12,
	"helm_visor": 11, "exo_chest": 13, "exo_legs": 12, "mag_boots": 11, "gauntlets_power": 11,
	"shield_emitter": 14, "vehicle_bay": 14, "speeder": 15, "rover": 15, "teleporter": 18,
	"storage_crate": 11, "launch_pad": 30, "ship": SHIP_LEVEL,
	# The medieval age, step by step: stone and hide, then bronze (forge), iron and
	# studded leather (anvil), then steel, and the finest work last.
	"shortbow": 2, "javelin": 2, "sickle": 2, "saw": 2, "shovel": 2, "lamp_oil": 2, "quill_ink": 2, "antidote": 2,
	"herbal_poultice": 2, "smelling_salts": 2, "cap_hide": 2, "vest_hide": 2, "gloves_hide": 2, "leggings_hide": 2,
	"boots_hide": 2, "shield_hide": 2, "brick": 3, "copper_ingot": 3, "bronze_ingot": 3, "tongs": 3, "empty_vial": 3,
	"empty_bottle": 3, "cauldron_small": 3, "hand_lantern": 3, "ring_copper": 3, "bronze_sword": 3, "bronze_spear": 3,
	"cudgel": 3, "pickaxe_bronze": 3, "tonic_warmth": 3, "tonic_cooling": 3, "elixir_nightsight": 3, "wine": 3, "mead": 3,
	"bronze_axe": 4, "broadhead_arrows": 4, "tent_kit": 4, "helm_bronze": 4, "cuirass_bronze": 4, "bracers_bronze": 4,
	"greaves_bronze": 4, "sandals_bronze": 4, "shield_bronze": 4, "helm_studded": 5, "jerkin_studded": 5,
	"gloves_studded": 5, "pants_studded": 5, "boots_studded": 5, "scroll_red": 4, "scroll_blue": 4,
	"iron_nails": 5, "throwing_knives": 5, "falchion": 5, "warpick": 5, "shield_kite": 5, "ring_silver": 5,
	"amulet_silver": 5, "silver_ingot": 5, "gold_ingot": 6, "morning_star": 6, "flail": 6, "glaive": 6, "composite_bow": 6,
	"scroll_green": 6, "steel_ingot": 7, "steel_sword": 7, "rapier": 7, "halberd": 7, "pickaxe_steel": 7, "axe_steel": 7,
	"potion_stamina_greater": 7, "zweihander": 8, "heavy_crossbow": 8, "helm_steel": 8, "gauntlets_steel": 8,
	"cuisses_steel": 8, "sabatons_steel": 8, "potion_health_greater": 8, "elixir_strength": 8, "elixir_swiftness": 8,
	"plate_steel": 9, "shield_tower": 9, "knight_sword": 9, "executioner_axe": 9, "royal_bow": 9, "ring_ruby": 9,
	"amulet_saint": 9, "dragonbone_dagger": 10, "kings_mace": 10,
}
static func unlock_level(out: String) -> int:
	if not Eras.themed():
		return 1
	var lv: int = UNLOCK.get(out, 1)
	if Eras.tier(int(def(out).get("era", ANY))) > 0:
		lv = maxi(lv, Eras.UNLOCK_LEVEL)
	return lv

## Gear that turns up in caches and dungeons, per era.
const GEAR_LOOT := [["sword_iron", "axe_iron", "crossbow", "scrap_pistol", "helm_iron", "mail_iron", "greaves_iron", "boots_leather",
		"gloves_leather", "shield_wood", "battle_axe", "war_hammer", "mace", "spear", "dagger", "longbow",
		# The medieval age (pack A): roll_loot keeps each to zones near its level.
		"wooden_club", "stone_knife", "sling", "shortbow", "hunting_spear", "hand_axe", "quarterstaff", "bronze_sword",
		"bronze_spear", "bronze_axe", "cudgel", "steel_sword", "falchion", "rapier", "zweihander", "halberd", "morning_star",
		"flail", "warpick", "glaive", "composite_bow", "heavy_crossbow", "knight_sword", "executioner_axe", "royal_bow",
		"dragonbone_dagger", "kings_mace", "cap_cloth", "tunic_padded", "wraps_cloth", "trousers_wool", "shoes_cloth",
		"buckler_wood", "cap_hide", "vest_hide", "gloves_hide", "leggings_hide", "boots_hide", "shield_hide", "helm_studded",
		"jerkin_studded", "gloves_studded", "pants_studded", "boots_studded", "shield_kite", "helm_bronze", "cuirass_bronze",
		"bracers_bronze", "greaves_bronze", "sandals_bronze", "shield_bronze", "helm_steel", "plate_steel", "gauntlets_steel",
		"cuisses_steel", "sabatons_steel", "shield_tower", "pickaxe_stone", "axe_stone", "pickaxe_bronze", "pickaxe_steel",
		"axe_steel", "shovel", "sickle", "fishing_rod", "ring_copper", "ring_silver", "ring_ruby", "amulet_bone",
		"amulet_silver", "amulet_saint", "lucky_coin"],
	["sword_runic", "crossbow_runic", "axe_mythril", "helm_elven", "plate_mythril", "guards_mythril", "boots_elven", "bracers_rune", "shield_crystal", "dagger"],
	["pulse_pistol", "pulse_smg", "pulse_rifle", "rail_rifle", "helm_visor", "exo_chest", "exo_legs", "mag_boots", "gauntlets_power", "shield_emitter"]]
## Treasure only strongholds and caves give up.
const DUNGEON_LOOT := [["gold_idol", "dungeon_key", "health_potion", "stamina_potion", "arrow", "potion_health_minor",
		"potion_health_greater", "potion_stamina_greater", "antidote", "elixir_strength", "elixir_swiftness", "elixir_nightsight",
		"scroll_red", "scroll_blue", "scroll_green", "holy_water", "broadhead_arrows", "throwing_knives", "javelin", "dice",
		"letter_sealed", "book_leather", "silver_ingot", "gold_ingot", "gold_ore", "salve", "candle"],
	["rune_tablet", "dungeon_key", "health_potion", "stamina_potion"], ["void_gem", "dungeon_key", "health_potion", "stamina_potion"]]

const NAME_PARTS := ["Varn", "Esk", "Thal", "Orrin", "Myr", "Kael", "Sorr", "Ilsa", "Brand", "Quill", "Hale", "Nyx"]

## Value of each building piece and station as an item, in Marks.
const PIECE_VALUE := {"foundation": 8, "floor_wood": 6, "wall_plaster": 9, "wall_stone": 10, "wall_window": 9, "wall_door": 9,
	"stairs_wood": 16, "roof_small": 20, "roof_large": 40, "fence": 4, "platform": 50, "wall_scifi": 75, "wall_scifi_window": 75,
	"door_scifi": 90, "stairs_scifi": 110, "workbench": 25, "waystone": 300, "teleporter": 450, "storage_chest": 30, "storage_crate": 120, "campfire": 8, "forge": 40, "anvil": 80, "cauldron": 95, "fabricator": 160,
	"vehicle_bay": 260, "stable": 90, "launch_pad": 420}

## Weight of one item in kg, where it differs from the default for its kind.
const WEIGHT := {"wood": 2.0, "glowroot": 1.6, "stone": 2.5, "iron_ore": 3.0, "aether_crystal": 0.8, "alloy_scrap": 1.5,
	"planks": 1.0, "iron_ingot": 2.0, "mythril_ingot": 1.2, "alloy_plate": 1.5, "power_cell": 0.4, "fiber": 0.1,
	"hide": 1.0, "fur_pelt": 1.2, "leather": 0.8, "bone": 0.4, "animal_fat": 0.4, "antler": 1.0, "skinning_knife": 0.3, "silver_chalice": 0.6, "moonpearl": 0.1, "data_core": 0.3, "binoculars": 0.8, "torch": 0.5, "crossbow": 3.0, "crossbow_runic": 3.2, "scrap_pistol": 1.4, "pulse_smg": 2.6, "pulse_rifle": 3.6,
	"rail_rifle": 5.0, "arc_launcher": 5.5, "bolt": 0.05, "rounds": 0.02, "flashlight": 0.6, "flashlight_dead": 0.6, "hammer": 1.5,
	"pickaxe_iron": 4.0, "pickaxe_mythril": 3.0, "pickaxe_plasma": 5.0, "axe_iron": 3.0, "axe_mythril": 2.2,
	"sword_iron": 3.5, "sword_runic": 2.5, "pulse_pistol": 1.6, "foundation": 8.0, "floor_wood": 4.0, "wall_stone": 8.0,
	"workbench": 15.0, "forge": 20.0, "anvil": 25.0, "jetpack": 7.0, "jet_fuel": 1.2,
	"treasure_map": 0.05, "treasure_chip": 0.05,
	# The medieval age.
	"flint": 0.3, "clay": 1.0, "brick": 1.5, "rope": 0.4, "cloth": 0.3, "wool": 0.2, "flax": 0.1, "resin": 0.2,
	"charcoal": 0.3, "salt": 0.1, "beeswax": 0.2, "lamp_oil": 0.5, "copper_ore": 2.5, "tin_ore": 2.5, "coal": 1.0,
	"silver_ore": 2.5, "gold_ore": 3.0, "salt_crystal": 1.0, "copper_ingot": 2.0, "bronze_ingot": 2.0, "steel_ingot": 2.0,
	"silver_ingot": 1.5, "gold_ingot": 2.5, "iron_nails": 0.02, "wooden_club": 2.0, "stone_knife": 0.4, "sling": 0.2,
	"shortbow": 1.0, "hunting_spear": 2.0, "hand_axe": 1.2, "bronze_sword": 2.8, "bronze_spear": 2.4, "bronze_axe": 2.6,
	"cudgel": 2.6, "throwing_knives": 0.25, "javelin": 1.2, "steel_sword": 3.2, "falchion": 2.8, "rapier": 1.6,
	"zweihander": 6.0, "halberd": 5.0, "morning_star": 3.5, "flail": 3.6, "warpick": 3.0, "glaive": 4.0,
	"composite_bow": 1.4, "heavy_crossbow": 5.0, "quarterstaff": 1.8, "knight_sword": 3.2, "executioner_axe": 7.0,
	"royal_bow": 1.3, "dragonbone_dagger": 0.5, "kings_mace": 3.4, "broadhead_arrows": 0.06,
	"cap_cloth": 0.3, "tunic_padded": 2.0, "wraps_cloth": 0.2, "trousers_wool": 0.8, "shoes_cloth": 0.4, "buckler_wood": 2.0,
	"cap_hide": 0.8, "vest_hide": 3.0, "gloves_hide": 0.5, "leggings_hide": 2.0, "boots_hide": 1.0, "shield_hide": 3.0,
	"helm_studded": 1.2, "jerkin_studded": 5.0, "gloves_studded": 0.8, "pants_studded": 3.0, "boots_studded": 1.5, "shield_kite": 6.0,
	"helm_bronze": 2.5, "cuirass_bronze": 8.0, "bracers_bronze": 1.2, "greaves_bronze": 4.0, "sandals_bronze": 1.0, "shield_bronze": 5.0,
	"helm_steel": 3.0, "plate_steel": 11.0, "gauntlets_steel": 1.5, "cuisses_steel": 6.0, "sabatons_steel": 2.5, "shield_tower": 9.0,
	"pickaxe_stone": 3.0, "axe_stone": 2.5, "pickaxe_bronze": 3.5, "pickaxe_steel": 3.8, "axe_steel": 2.8, "shovel": 2.5,
	"hoe": 2.0, "sickle": 0.8, "fishing_rod": 1.0, "saw": 1.0, "tongs": 1.0, "bucket": 1.5, "waterskin": 0.6,
	"hand_lantern": 1.2, "candle": 0.1, "tinderbox": 0.2, "bedroll": 2.5, "tent_kit": 6.0, "ring_copper": 0.02,
	"ring_silver": 0.02, "ring_ruby": 0.02, "amulet_bone": 0.05, "amulet_silver": 0.05, "amulet_saint": 0.1,
	"lucky_coin": 0.01, "dice": 0.02, "lute": 2.0, "flute": 0.3, "book_leather": 0.8, "pumpkin": 3.0, "cabbage": 1.0,
	"milk": 1.0, "wine": 1.0, "mead": 1.0, "stew": 0.8, "soup_veg": 0.8, "travel_bread": 0.2, "wheat": 0.3, "flour": 0.5,
	"herb_red": 0.05, "herb_blue": 0.05, "herb_yellow": 0.05, "herb_root": 0.1, "herb_mint": 0.05, "herb_nightshade": 0.05,
	"scroll_plain": 0.05, "scroll_red": 0.05, "scroll_blue": 0.05, "scroll_green": 0.05, "letter_sealed": 0.05,
	"quill_ink": 0.2, "mortar_pestle": 1.5, "empty_vial": 0.1, "empty_bottle": 0.3, "cauldron_small": 3.0, "smelling_salts": 0.05,
	"potion_health_minor": 0.2, "potion_health_greater": 0.2, "potion_stamina_greater": 0.2, "antidote": 0.2,
	"tonic_warmth": 0.2, "tonic_cooling": 0.2, "elixir_strength": 0.2, "elixir_swiftness": 0.2, "elixir_nightsight": 0.1,
	"salve": 0.1, "bandage_linen": 0.05, "herbal_poultice": 0.1, "holy_water": 0.3}
const KIND_WEIGHT := {"decor": 3.0, "resource": 1.0, "treasure": 0.5, "food": 0.3, "tool": 2.5, "weapon": 3.0, "vehicle": 0.0, "armor": 4.0,
	"placeable": 4.0, "station": 12.0}

static var _piece_defs := {}

## Crafting window tabs, in order ("All" comes first in the window). Each item sits in one
## tab: its "cat" when the definition has one (one of these names), otherwise the tab its
## "kind" maps to in KIND_TAB, otherwise Materials. A few also show in a second tab: what
## any ranged weapon fires (its "ammo") under Ammo, anything with a "fuel" key under Fuel,
## and furniture that gives light under Lights. New items need nothing more than a kind.
const CRAFT_TABS := ["Materials", "Tools", "Weapons", "Ammo", "Armour", "Fuel", "Food", "Medicine", "Lights",
	"Vehicles", "Stations", "Building", "Furniture"]
const KIND_TAB := {"resource": "Materials", "material": "Materials", "ore": "Materials", "ingot": "Materials",
	"component": "Materials", "treasure": "Materials", "valuable": "Materials", "relic": "Materials",
	"tool": "Tools", "gadget": "Tools", "instrument": "Tools", "key": "Tools", "scroll": "Tools",
	"weapon": "Weapons", "explosive": "Weapons", "trap": "Weapons", "ammo": "Ammo",
	"armor": "Armour", "trinket": "Armour", "implant": "Armour", "fuel": "Fuel",
	"food": "Food", "drink": "Food", "ingredient": "Food", "crop": "Food",
	"medicine": "Medicine", "potion": "Medicine", "herb": "Medicine", "consumable": "Medicine",
	"light": "Lights", "vehicle": "Vehicles", "station": "Stations", "placeable": "Building", "camp": "Building",
	"decor": "Furniture"}

static var _ammo_types := {}

## The crafting tab an item belongs in (see CRAFT_TABS).
static func craft_tab(type: String) -> String:
	var d := def(type)
	if d.has("cat"):
		return d["cat"]
	return KIND_TAB.get(String(d.get("kind", "")), "Materials")

## Every crafting tab an item shows under: its own tab, then any second one.
static func craft_tabs(type: String) -> Array:
	if _ammo_types.is_empty():
		for t in ITEMS:
			if ITEMS[t].has("ammo"):
				_ammo_types[ITEMS[t]["ammo"]] = true
	var tabs := [craft_tab(type)]
	var extra := []
	if _ammo_types.has(type):
		extra.append("Ammo")
	if def(type).has("fuel"):
		extra.append("Fuel")
	if craft_tab(type) == "Furniture" and BuildCatalog.def(type).has("light"):
		extra.append("Lights")
	for t in extra:
		if not tabs.has(t):
			tabs.append(t)
	return tabs


## Weight of one item of this type, in kg. Vehicles are carried as their keys.
static func weight(type: String) -> float:
	if WEIGHT.has(type):
		return WEIGHT[type]
	return KIND_WEIGHT.get(String(def(type).get("kind", "")), 1.0)

static func has(type: String) -> bool:
	return ITEMS.has(type) or BuildCatalog.is_piece_item(type)

## Item definition. Building pieces are items too ("placeable"), described by BuildCatalog.
static func def(type: String) -> Dictionary:
	if ITEMS.has(type):
		return ITEMS[type]
	if BuildCatalog.is_piece_item(type):
		if not _piece_defs.has(type):
			var b := BuildCatalog.def(type)
			var c := Color(0.62, 0.5, 0.36)
			match String(b.get("mat", "wood")):
				"stone": c = Color(0.55, 0.55, 0.55)
				"metal": c = Color(0.7, 0.72, 0.76)
			_piece_defs[type] = {"name": b["name"], "era": int(b.get("era", ANY)), "value": PIECE_VALUE.get(type, 10), "stack": true,
				"kind": "station" if b.has("station") or b.has("storage") or b.has("teleporter") else ("decor" if b.has("decor") else "placeable"), "color": c, "place": true}
		return _piece_defs[type]
	return {}

static func display_name(item: Dictionary) -> String:
	if item.get("name", "") != "":
		return item["name"]
	return def(item["type"]).get("name", item["type"])

static func is_stackable(type: String) -> bool:
	return def(type).get("stack", false)

static func era_of(type: String) -> int:
	return def(type).get("era", ANY)

## Builds a fully specified item instance. `uid` is assigned by the inventory.
## Gear made with an `rng` rolls a rank (see Rarity); `luck` raises the odds.
static func make(type: String, qty: int, quality: float, origin: Dictionary, rng: RandomNumberGenerator = null, luck := 0.0) -> Dictionary:
	var item := {"uid": 0, "type": type, "qty": qty, "quality": snappedf(quality, 0.05), "name": "", "origin": origin}
	if rng != null and Rarity.is_gear(type):
		Rarity.apply(item, Rarity.roll(rng, luck + clampf((quality - 1.0) * 1.5, 0.0, 0.5)), rng)
	return item

## The item's working stats: its definition with rank and abilities applied.
static func stats(item) -> Dictionary:
	if not item is Dictionary:
		return {}
	var d: Dictionary = def(item["type"]).duplicate()
	if not Rarity.is_gear(item["type"]):
		return d
	var p := Rarity.power(item)
	if Rarity.has_affix(item, "brutal"):
		p *= 1.3
	if d.has("damage"):
		d["damage"] = float(d["damage"]) * p
	if Rarity.has_affix(item, "swift"):
		d["cooldown"] = float(d.get("cooldown", 0.55)) * 0.75
		d["swift"] = true
	if Rarity.has_affix(item, "reach") and d.has("range"):
		d["range"] = float(d["range"]) * 1.4
	if Rarity.has_affix(item, "prospector"):
		for k in ["mine", "chop", "dig"]:
			if d.has(k):
				d[k] = float(d[k]) * 1.5
	if d.has("armor"):
		d["armor"] = float(d["armor"]) * (1.0 + 0.1 * Rarity.of(item)) * (1.15 if Rarity.has_affix(item, "warding") else 1.0)
	return d

## Deterministic loot for a cache. Called once at generation; the result is snapshotted.
## `luck` (0 to 1) is how dangerous the place was: more and better gear.
static func roll_loot(era: int, rng: RandomNumberGenerator, origin: Dictionary, luck := 0.0) -> Array:
	var loot: Array = []
	var pools := [
		[["wood", 2, 6], ["iron_ore", 2, 5], ["iron_ingot", 1, 3], ["bread", 1, 3], ["copper_ore", 1, 4], ["tin_ore", 1, 3],
			["coal", 1, 4], ["flint", 1, 3], ["rope", 1, 3], ["cloth", 1, 3], ["wool", 1, 4], ["candle", 1, 3], ["apple", 1, 4],
			["potato", 1, 4], ["salted_meat", 1, 2], ["iron_nails", 4, 12], ["herb_red", 1, 3], ["bandage_linen", 1, 2],
			["empty_vial", 1, 2], ["mead", 1, 1], ["silver_chalice", 1, 1]],
		[["glowroot", 2, 5], ["aether_crystal", 1, 4], ["glowberry", 1, 4], ["mythril_ingot", 1, 2], ["moonpearl", 1, 1]],
		[["alloy_scrap", 2, 6], ["circuitry", 1, 4], ["power_cell", 1, 2], ["ration_pack", 1, 3], ["data_core", 1, 1]],
	]
	var rare_tools := [["sword_iron", "axe_iron"], ["sword_runic", "pickaxe_mythril"], ["pulse_pistol", "pickaxe_plasma"]]
	# Out in higher zones (themed worlds) the gear is better and the purses fuller.
	var zl := 0.0
	if origin.get("chunk") is Vector2i:
		var ck: Vector2i = origin["chunk"]
		zl = Eras.zone_luck(ck.x * 64.0 + 32.0, ck.y * 64.0 + 32.0)
	var n := rng.randi_range(2, 4)
	var pool: Array = pools[era]
	for i in n:
		var idx := rng.randi_range(0, pool.size() - 1)
		if idx == pool.size() - 1 and rng.randf() > 0.4:
			idx = 0
		var e: Array = pool[idx]
		loot.append(make(e[0], rng.randi_range(e[1], e[2]), rng.randf_range(0.8, 1.2), origin))
	if rng.randf() < 0.12 + (luck + zl) * 0.7:
		var t: Array = rare_tools[era] + GEAR_LOOT[era]
		if Eras.themed() and zl * 160.0 + 1.0 < Eras.UNLOCK_LEVEL:
			# The first zones only hold their own era's blades and bows, and only what a
			# traveller of about the zone's level could make (a few levels' grace in a dungeon).
			var lv := zl * 160.0 + 3.0 + luck * 4.0
			var near: Array = t.filter(func(x): return unlock_level(x) < Eras.UNLOCK_LEVEL and unlock_level(x) <= lv)
			t = near if not near.is_empty() else t.filter(func(x): return unlock_level(x) < Eras.UNLOCK_LEVEL)
		# Some eras have nothing that low (the filter can empty the list).
		if not t.is_empty():
			loot.append(make(t[rng.randi() % t.size()], 1, rng.randf_range(0.9, 1.45), origin, rng, minf(luck + zl, 1.0)))
	if luck > 0.0:
		var extra: Array = DUNGEON_LOOT[era]
		for i in rng.randi_range(1, 1 + int(luck * 3.0)):
			var t: String = extra[rng.randi() % extra.size()]
			var many: bool = def(t).get("kind", "") == "ammo" or def(t).get("thrown", false)
			loot.append(make(t, rng.randi_range(8, 20) if many else rng.randi_range(1, 3), rng.randf_range(0.9, 1.2), origin))
	loot.append({"type": "_marks", "qty": int(rng.randi_range(5, 40) * (1.0 + (luck + zl) * 4.0))})
	return loot
