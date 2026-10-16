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
	# Vehicles: use one to set it down in the world, then ride it (see Vehicle).
	"speeder": {"name": "Hover Speeder", "era": Eras.SCIFI, "value": 420, "stack": false, "kind": "vehicle", "color": Color(1.0, 0.65, 0.15)},
	"rover": {"name": "Survey Rover", "era": Eras.SCIFI, "value": 380, "stack": false, "kind": "vehicle", "color": Color(0.85, 0.85, 0.9)},
	"ship": {"name": "Starship", "era": Eras.SCIFI, "value": 1600, "stack": false, "kind": "vehicle", "color": Color(0.95, 0.7, 0.25)},
	"horse": {"name": "Riding Horse", "era": Eras.MEDIEVAL, "value": 180, "stack": false, "kind": "vehicle", "color": Color(0.55, 0.38, 0.25)},
}

const NAME_PARTS := ["Varn", "Esk", "Thal", "Orrin", "Myr", "Kael", "Sorr", "Ilsa", "Brand", "Quill", "Hale", "Nyx"]

## Value of each building piece and station as an item, in Marks.
const PIECE_VALUE := {"foundation": 8, "floor_wood": 6, "wall_plaster": 9, "wall_stone": 10, "wall_window": 9, "wall_door": 9,
	"stairs_wood": 16, "roof_small": 20, "roof_large": 40, "fence": 4, "platform": 50, "wall_scifi": 75, "wall_scifi_window": 75,
	"door_scifi": 90, "stairs_scifi": 110, "workbench": 25, "waystone": 300, "teleporter": 450, "storage_chest": 30, "storage_crate": 120, "campfire": 8, "forge": 40, "anvil": 80, "cauldron": 95, "fabricator": 160,
	"vehicle_bay": 260, "stable": 90, "launch_pad": 420}

## Weight of one item in kg, where it differs from the default for its kind.
const WEIGHT := {"wood": 2.0, "glowroot": 1.6, "stone": 2.5, "iron_ore": 3.0, "aether_crystal": 0.8, "alloy_scrap": 1.5,
	"planks": 1.0, "iron_ingot": 2.0, "mythril_ingot": 1.2, "alloy_plate": 1.5, "power_cell": 0.4, "fiber": 0.1,
	"hide": 1.0, "silver_chalice": 0.6, "moonpearl": 0.1, "data_core": 0.3, "binoculars": 0.8, "torch": 0.5, "flashlight": 0.6, "flashlight_dead": 0.6, "hammer": 1.5,
	"pickaxe_iron": 4.0, "pickaxe_mythril": 3.0, "pickaxe_plasma": 5.0, "axe_iron": 3.0, "axe_mythril": 2.2,
	"sword_iron": 3.5, "sword_runic": 2.5, "pulse_pistol": 1.6, "foundation": 8.0, "floor_wood": 4.0, "wall_stone": 8.0,
	"workbench": 15.0, "forge": 20.0, "anvil": 25.0}
const KIND_WEIGHT := {"resource": 1.0, "treasure": 0.5, "food": 0.3, "tool": 2.5, "weapon": 3.0, "vehicle": 0.0,
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
				"kind": "station" if b.has("station") or b.has("storage") or b.has("teleporter") else "placeable", "color": c, "place": true}
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
static func make(type: String, qty: int, quality: float, origin: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var item := {"uid": 0, "type": type, "qty": qty, "quality": snappedf(quality, 0.05), "name": "", "origin": origin}
	if not is_stackable(type) and rng != null and quality >= 1.25:
		item["name"] = "%s of %s" % [def(type)["name"], NAME_PARTS[rng.randi() % NAME_PARTS.size()]]
	return item

## Deterministic loot for a cache. Called once at generation; the result is snapshotted.
static func roll_loot(era: int, rng: RandomNumberGenerator, origin: Dictionary) -> Array:
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
	if rng.randf() < 0.12:
		var t: Array = rare_tools[era]
		loot.append(make(t[rng.randi() % t.size()], 1, rng.randf_range(0.9, 1.45), origin, rng))
	loot.append({"type": "_marks", "qty": rng.randi_range(5, 40)})
	return loot
