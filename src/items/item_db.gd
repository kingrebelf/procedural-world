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
	# Food
	"bread": {"name": "Bread", "era": Eras.MEDIEVAL, "value": 4, "stack": true, "kind": "food", "heal": 25, "color": Color(0.8, 0.6, 0.3)},
	"glowberry": {"name": "Glowberries", "era": Eras.FANTASY, "value": 6, "stack": true, "kind": "food", "heal": 35, "color": Color(0.6, 0.3, 1.0)},
	"raw_meat": {"name": "Raw Meat", "era": ANY, "value": 3, "stack": true, "kind": "food", "heal": 8, "color": Color(0.75, 0.3, 0.3)},
	"cooked_meat": {"name": "Cooked Meat", "era": ANY, "value": 7, "stack": true, "kind": "food", "heal": 40, "color": Color(0.55, 0.32, 0.18)},
	"fiber": {"name": "Plant Fiber", "era": ANY, "value": 1, "stack": true, "kind": "resource", "color": Color(0.55, 0.62, 0.3)},
	"wild_berries": {"name": "Wild Berries", "era": Eras.MEDIEVAL, "value": 3, "stack": true, "kind": "food", "heal": 15, "color": Color(0.7, 0.12, 0.25)},
	"hide": {"name": "Hide", "era": ANY, "value": 5, "stack": true, "kind": "resource", "color": Color(0.6, 0.45, 0.3)},
	"ration_pack": {"name": "Ration Pack", "era": Eras.SCIFI, "value": 8, "stack": true, "kind": "food", "heal": 50, "color": Color(0.8, 0.8, 0.5)},
	# Tools
	"pickaxe_iron": {"name": "Iron Pickaxe", "era": Eras.MEDIEVAL, "value": 45, "stack": false, "kind": "tool", "mine": 1.0, "chop": 0.3, "damage": 8, "range": 3.0, "dig": 0.6},
	"pickaxe_mythril": {"name": "Mythril Pickaxe", "era": Eras.FANTASY, "value": 140, "stack": false, "kind": "tool", "mine": 2.0, "chop": 0.4, "damage": 12, "range": 3.0, "dig": 1.0},
	"pickaxe_plasma": {"name": "Plasma Drill", "era": Eras.SCIFI, "value": 260, "stack": false, "kind": "tool", "mine": 3.5, "chop": 0.6, "damage": 10, "range": 3.5, "dig": 1.6},
	"axe_iron": {"name": "Iron Axe", "era": Eras.MEDIEVAL, "value": 40, "stack": false, "kind": "tool", "mine": 0.3, "chop": 1.0, "damage": 12, "range": 3.0},
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
	# Heavier weapons; "swing" scales the time between swings.
	"battle_axe": {"name": "Battle Axe", "era": Eras.MEDIEVAL, "value": 110, "stack": false, "kind": "weapon", "damage": 36, "range": 3.2, "swing": 1.3, "chop": 0.8},
	"war_hammer": {"name": "War Hammer", "era": Eras.MEDIEVAL, "value": 120, "stack": false, "kind": "weapon", "damage": 40, "range": 3.0, "swing": 1.45, "mine": 0.6},
	"mace": {"name": "Flanged Mace", "era": Eras.MEDIEVAL, "value": 90, "stack": false, "kind": "weapon", "damage": 30, "range": 2.8, "swing": 1.1},
	"spear": {"name": "Iron Spear", "era": Eras.MEDIEVAL, "value": 60, "stack": false, "kind": "weapon", "damage": 24, "range": 4.4, "swing": 1.0},
	"dagger": {"name": "Curved Dagger", "era": ANY, "value": 50, "stack": false, "kind": "weapon", "damage": 15, "range": 2.4, "swing": 0.55},
	"longbow": {"name": "Longbow", "era": Eras.MEDIEVAL, "value": 80, "stack": false, "kind": "weapon", "damage": 30, "range": 95.0, "ranged": true, "ammo": "arrow", "shots_per_ammo": 1, "cooldown": 0.75, "tracer": "bolt"},
	"arrow": {"name": "Arrows", "era": ANY, "value": 1, "stack": true, "kind": "ammo", "color": Color(0.55, 0.42, 0.28)},
	# Dungeon treasure and potions.
	"rune_tablet": {"name": "Rune Tablet", "era": Eras.FANTASY, "value": 150, "stack": true, "kind": "treasure", "color": Color(0.6, 0.4, 1.0)},
	"gold_idol": {"name": "Golden Skull Idol", "era": Eras.MEDIEVAL, "value": 200, "stack": true, "kind": "treasure", "color": Color(1.0, 0.8, 0.3)},
	"void_gem": {"name": "Void Gem", "era": Eras.SCIFI, "value": 240, "stack": true, "kind": "treasure", "color": Color(0.7, 0.35, 1.0)},
	"dungeon_key": {"name": "Ornate Key", "era": ANY, "value": 40, "stack": true, "kind": "treasure", "color": Color(0.8, 0.65, 0.3)},
	"health_potion": {"name": "Health Potion", "era": ANY, "value": 30, "stack": true, "kind": "food", "heal": 80, "color": Color(0.9, 0.15, 0.15)},
	"stamina_potion": {"name": "Stamina Potion", "era": ANY, "value": 25, "stack": true, "kind": "food", "heal": 0, "stamina": true, "color": Color(0.3, 0.9, 0.35)},
	"bolt": {"name": "Crossbow Bolts", "era": ANY, "value": 1, "stack": true, "kind": "ammo", "color": Color(0.6, 0.45, 0.3)},
	"rounds": {"name": "Revolver Rounds", "era": ANY, "value": 2, "stack": true, "kind": "ammo", "color": Color(0.8, 0.65, 0.3)},
	# Vehicles: use one to set it down in the world, then ride it (see Vehicle).
	"speeder": {"name": "Hover Speeder", "era": Eras.SCIFI, "value": 420, "stack": false, "kind": "vehicle", "color": Color(1.0, 0.65, 0.15)},
	"rover": {"name": "Survey Rover", "era": Eras.SCIFI, "value": 380, "stack": false, "kind": "vehicle", "color": Color(0.85, 0.85, 0.9)},
	"ship": {"name": "Starship", "era": Eras.SCIFI, "value": 1600, "stack": false, "kind": "vehicle", "color": Color(0.95, 0.7, 0.25)},
	"horse": {"name": "Riding Horse", "era": Eras.MEDIEVAL, "value": 180, "stack": false, "kind": "vehicle", "color": Color(0.55, 0.38, 0.25)},
}

## Gear that turns up in caches and dungeons, per era.
const GEAR_LOOT := [["sword_iron", "axe_iron", "crossbow", "scrap_pistol", "helm_iron", "mail_iron", "greaves_iron", "boots_leather",
		"gloves_leather", "shield_wood", "battle_axe", "war_hammer", "mace", "spear", "dagger", "longbow"],
	["sword_runic", "crossbow_runic", "axe_mythril", "helm_elven", "plate_mythril", "guards_mythril", "boots_elven", "bracers_rune", "shield_crystal", "dagger"],
	["pulse_pistol", "pulse_smg", "pulse_rifle", "rail_rifle", "helm_visor", "exo_chest", "exo_legs", "mag_boots", "gauntlets_power", "shield_emitter"]]
## Treasure only strongholds and caves give up.
const DUNGEON_LOOT := [["gold_idol", "dungeon_key", "health_potion", "stamina_potion", "arrow"],
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
	"hide": 1.0, "silver_chalice": 0.6, "moonpearl": 0.1, "data_core": 0.3, "binoculars": 0.8, "torch": 0.5, "crossbow": 3.0, "crossbow_runic": 3.2, "scrap_pistol": 1.4, "pulse_smg": 2.6, "pulse_rifle": 3.6,
	"rail_rifle": 5.0, "arc_launcher": 5.5, "bolt": 0.05, "rounds": 0.02, "flashlight": 0.6, "flashlight_dead": 0.6, "hammer": 1.5,
	"pickaxe_iron": 4.0, "pickaxe_mythril": 3.0, "pickaxe_plasma": 5.0, "axe_iron": 3.0, "axe_mythril": 2.2,
	"sword_iron": 3.5, "sword_runic": 2.5, "pulse_pistol": 1.6, "foundation": 8.0, "floor_wood": 4.0, "wall_stone": 8.0,
	"workbench": 15.0, "forge": 20.0, "anvil": 25.0}
const KIND_WEIGHT := {"decor": 3.0, "resource": 1.0, "treasure": 0.5, "food": 0.3, "tool": 2.5, "weapon": 3.0, "vehicle": 0.0, "armor": 4.0,
	"placeable": 4.0, "station": 12.0}

static var _piece_defs := {}

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
		[["wood", 2, 6], ["iron_ore", 2, 5], ["iron_ingot", 1, 3], ["bread", 1, 3], ["silver_chalice", 1, 1]],
		[["glowroot", 2, 5], ["aether_crystal", 1, 4], ["glowberry", 1, 4], ["mythril_ingot", 1, 2], ["moonpearl", 1, 1]],
		[["alloy_scrap", 2, 6], ["circuitry", 1, 4], ["power_cell", 1, 2], ["ration_pack", 1, 3], ["data_core", 1, 1]],
	]
	var rare_tools := [["sword_iron", "axe_iron"], ["sword_runic", "pickaxe_mythril"], ["pulse_pistol", "pickaxe_plasma"]]
	var n := rng.randi_range(2, 4)
	var pool: Array = pools[era]
	for i in n:
		var idx := rng.randi_range(0, pool.size() - 1)
		if idx == pool.size() - 1 and rng.randf() > 0.4:
			idx = 0
		var e: Array = pool[idx]
		loot.append(make(e[0], rng.randi_range(e[1], e[2]), rng.randf_range(0.8, 1.2), origin))
	if rng.randf() < 0.12 + luck * 0.7:
		var t: Array = rare_tools[era] + GEAR_LOOT[era]
		loot.append(make(t[rng.randi() % t.size()], 1, rng.randf_range(0.9, 1.45), origin, rng, luck))
	if luck > 0.0:
		var extra: Array = DUNGEON_LOOT[era]
		for i in rng.randi_range(1, 1 + int(luck * 3.0)):
			var t: String = extra[rng.randi() % extra.size()]
			loot.append(make(t, rng.randi_range(1, 3) if t != "arrow" else rng.randi_range(8, 20), rng.randf_range(0.9, 1.2), origin))
	loot.append({"type": "_marks", "qty": int(rng.randi_range(5, 40) * (1.0 + luck * 4.0))})
	return loot
