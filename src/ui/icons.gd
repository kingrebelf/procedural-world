class_name Icons
## Procedurally drawn item icons (64x64), cached per item type. Used by the pickup feed,
## the hotbar, the inventory and the look-at panel.

const S := 64
static var _cache: Dictionary = {}

## Cell order of the painted icon sheet (6 columns x 5 rows) at SHEET_PATH. When the
## sheet exists its icons replace the procedural ones below.
const SHEET_PATH := "res://assets/icons/items.png"
const SHEET_COLS := 6
const SHEET_ORDER := [
	"wood", "glowroot", "circuitry", "stone", "iron_ore", "aether_crystal",
	"alloy_scrap", "planks", "iron_ingot", "mythril_ingot", "alloy_plate", "power_cell",
	"silver_chalice", "moonpearl", "data_core", "bread", "glowberry", "ration_pack",
	"pickaxe_iron", "pickaxe_mythril", "pickaxe_plasma", "axe_iron", "axe_mythril", "sword_iron",
	"sword_runic", "pulse_pistol", "gold_coin", "raw_meat", "hide", "cooked_meat",
]
## The second sheet: armour, weapons and dungeon loot (tools/slice_icons.py --grid).
const SHEET2_PATH := "res://assets/icons/items2.png"
const SHEET2_ORDER := [
	"helm_iron", "mail_iron", "greaves_iron", "boots_leather", "shield_wood", "gloves_leather",
	"helm_elven", "plate_mythril", "guards_mythril", "boots_elven", "shield_crystal", "bracers_rune",
	"helm_visor", "exo_chest", "exo_legs", "mag_boots", "shield_emitter", "gauntlets_power",
	"battle_axe", "war_hammer", "longbow", "spear", "dagger", "mace",
	"rune_tablet", "dungeon_key", "health_potion", "stamina_potion", "gold_idol", "void_gem",
]
## Later sheets, each a 6x5 grid in the same layout: tools and ammo (items3; "" marks a
## painted cell with no item yet), then the medieval age (pack A, items4-9), the frontier
## (pack B, items10-13), the human sci-fi age (pack C, items14-18) the alien endgame (pack D,
## items19-23), and ammunition variants and fuels (pack E, items24).
const MORE_SHEETS := [
	["res://assets/icons/items3.png", [
		"fiber", "wild_berries", "torch", "flashlight", "flashlight_dead", "binoculars",
		"hammer", "jetpack", "jet_fuel", "arrow", "bolt", "rounds",
		"", "", "", "", "", "",
		"", "", "", "", "", "",
		"", "", "", "", "", "",
	]],
	["res://assets/icons/items4.png", [
		"bone", "animal_fat", "antler", "fur_pelt", "leather", "lockpick",
		"skinning_knife", "flint", "clay", "brick", "rope", "cloth",
		"wool", "flax", "resin", "charcoal", "salt", "beeswax",
		"copper_ore", "tin_ore", "coal", "silver_ore", "gold_ore", "salt_crystal",
		"copper_ingot", "bronze_ingot", "steel_ingot", "silver_ingot", "gold_ingot", "iron_nails",
	]],
	["res://assets/icons/items5.png", [
		"wooden_club", "stone_knife", "sling", "shortbow", "hunting_spear", "hand_axe",
		"bronze_sword", "bronze_spear", "bronze_axe", "cudgel", "throwing_knives", "javelin",
		"steel_sword", "falchion", "rapier", "zweihander", "halberd", "morning_star",
		"flail", "warpick", "glaive", "composite_bow", "heavy_crossbow", "quarterstaff",
		"knight_sword", "executioner_axe", "royal_bow", "dragonbone_dagger", "kings_mace", "broadhead_arrows",
	]],
	["res://assets/icons/items6.png", [
		"cap_cloth", "tunic_padded", "wraps_cloth", "trousers_wool", "shoes_cloth", "buckler_wood",
		"cap_hide", "vest_hide", "gloves_hide", "leggings_hide", "boots_hide", "shield_hide",
		"helm_studded", "jerkin_studded", "gloves_studded", "pants_studded", "boots_studded", "shield_kite",
		"helm_bronze", "cuirass_bronze", "bracers_bronze", "greaves_bronze", "sandals_bronze", "shield_bronze",
		"helm_steel", "plate_steel", "gauntlets_steel", "cuisses_steel", "sabatons_steel", "shield_tower",
	]],
	["res://assets/icons/items7.png", [
		"pickaxe_stone", "axe_stone", "pickaxe_bronze", "pickaxe_steel", "axe_steel", "shovel",
		"hoe", "sickle", "fishing_rod", "saw", "tongs", "bucket",
		"waterskin", "hand_lantern", "candle", "tinderbox", "bedroll", "tent_kit",
		"ring_copper", "ring_silver", "ring_ruby", "amulet_bone", "amulet_silver", "amulet_saint",
		"lucky_coin", "dice", "lute", "flute", "book_leather", "treasure_map",
	]],
	["res://assets/icons/items8.png", [
		"apple", "pear", "carrot", "potato", "onion", "cabbage",
		"wheat", "flour", "egg", "milk", "honey", "mushroom",
		"fish_raw", "fish_cooked", "chicken_roast", "ham", "sausage", "salted_meat",
		"stew", "porridge", "pie_meat", "pie_berry", "soup_veg", "travel_bread",
		"pumpkin", "corn", "grapes", "wine", "mead", "jam",
	]],
	["res://assets/icons/items9.png", [
		"potion_health_minor", "potion_health_greater", "potion_stamina_greater", "antidote", "tonic_warmth", "tonic_cooling",
		"elixir_strength", "elixir_swiftness", "elixir_nightsight", "salve", "bandage_linen", "herbal_poultice",
		"herb_red", "herb_blue", "herb_yellow", "herb_root", "herb_mint", "herb_nightshade",
		"scroll_plain", "scroll_red", "scroll_blue", "scroll_green", "letter_sealed", "quill_ink",
		"mortar_pestle", "empty_vial", "empty_bottle", "cauldron_small", "holy_water", "smelling_salts",
	]],
	["res://assets/icons/items10.png", [
		"flintlock_pistol", "musket", "blunderbuss", "revolver_six", "lever_rifle", "double_shotgun",
		"bolt_rifle", "derringer", "flare_gun", "harpoon_gun", "gatling", "elephant_gun",
		"sabre", "machete", "tomahawk", "bowie_knife", "bayonet", "sledgehammer",
		"dynamite", "frag_grenade", "powder_keg", "fire_bottle", "bear_trap", "tripwire",
		"black_powder", "musket_balls", "shotgun_shells", "rifle_cartridges", "ammo_belt", "gun_oil",
	]],
	["res://assets/icons/items11.png", [
		"hat_cowboy", "duster", "gloves_riding", "chaps", "boots_riding", "bandana",
		"hardhat_lamp", "overalls", "gloves_work", "trousers_canvas", "boots_steeltoe", "backpack_canvas",
		"welding_mask", "vest_plated", "gauntlets_heavy", "legplates_riveted", "boots_iron", "shield_riot",
		"gasmask", "trenchcoat", "gloves_rubber", "trousers_wool_heavy", "boots_hobnail", "satchel",
		"helm_brass", "plate_steam", "gauntlets_piston", "legs_steam", "boots_steam", "pack_boiler",
	]],
	["res://assets/icons/items12.png", [
		"wrench", "crowbar", "hand_drill", "pickaxe_miner", "axe_lumber", "lamp_kerosene",
		"gears", "springs", "pipe_section", "valve", "pressure_gauge", "piston",
		"coal_sack", "oil_barrel", "rubber", "steel_sheet", "copper_wire", "glass_pane",
		"pocket_watch", "compass", "sextant", "camera_box", "telegraph_key", "gramophone_record",
		"gold_nugget", "silver_bar", "sheriff_star", "deed_scroll", "railway_spike", "safe_key",
	]],
	["res://assets/icons/items13.png", [
		"beans_can", "jerky", "biscuit_hard", "cornbread", "steak", "chili",
		"coffee_pot", "coffee_beans", "whiskey", "sarsaparilla", "water_canteen", "tea_tin",
		"apple_dried", "pickles", "cheese_wheel_small", "egg_fried", "pancakes", "stew_tin",
		"medkit_frontier", "bandage_roll", "splint", "tonic_bottle", "iodine", "syringe_glass",
		"cards_deck", "harmonica", "banjo", "cigar_box", "spectacles", "photo_frame",
	]],
	["res://assets/icons/items14.png", [
		"laser_pistol", "plasma_rifle", "gauss_rifle", "smart_pistol", "auto_shotgun", "sniper_rail",
		"minigun", "flamethrower", "rocket_launcher", "grenade_launcher", "needle_gun", "carbine_combat",
		"vibro_knife", "stun_baton", "mono_katana", "power_hammer", "chain_axe", "combat_machete",
		"frag_grenade_mk2", "emp_grenade", "smoke_grenade", "proximity_mine", "breach_charge", "rocket",
		"energy_cell", "plasma_canister", "gauss_slugs", "smart_rounds", "fuel_canister", "shells_12g",
	]],
	["res://assets/icons/items15.png", [
		"helm_recon", "suit_recon", "gloves_tactical", "pants_recon", "boots_tactical", "pack_recon",
		"helm_combat", "armor_combat", "gloves_combat", "legs_combat", "boots_combat", "shield_ballistic",
		"helm_eva", "suit_eva", "gloves_eva", "legs_eva", "boots_eva", "oxygen_pack",
		"helm_stealth", "suit_stealth", "gloves_stealth", "legs_stealth", "boots_stealth", "cloak_optic",
		"helm_power", "chest_power", "fists_power", "legs_power", "boots_power", "jetpack_military",
	]],
	["res://assets/icons/items16.png", [
		"multitool", "scanner", "hack_tablet", "laser_cutter", "welder", "mining_laser",
		"drone_scout", "turret_deploy", "shield_gen", "beacon_nav", "grapple", "motion_tracker",
		"repair_kit", "battery_small", "fusion_core", "keycard_red", "keycard_blue", "keycard_gold",
		"datapad", "holo_projector", "credit_chip", "dog_tags", "headset", "binoculars_digital",
		"toolbox_tech", "magboots_kit", "o2_canister", "flare_chem", "rope_synth", "survival_knife",
	]],
	["res://assets/icons/items17.png", [
		"titanium_ore", "uranium_ore", "lithium_ore", "cobalt_ore", "silicon_crystal", "rare_earth",
		"titanium_ingot", "carbon_fiber", "polymer", "graphene", "ceramic_plate", "nanotube_spool",
		"microchip", "servo", "optic_lens", "wiring_loom", "coolant", "superconductor",
		"fuel_rod", "circuit_board", "processor", "hull_patch", "sensor_module", "gyroscope",
		"thruster_part", "antenna", "solar_panel", "magnet", "nanopaste", "quantum_chip",
	]],
	["res://assets/icons/items18.png", [
		"ration_bar", "protein_pack", "nutri_paste", "freeze_meal", "hydro_greens", "space_coffee",
		"energy_drink", "water_pouch", "synth_steak", "noodles", "fruit_cube", "algae_bar",
		"medkit_mil", "stimpack", "trauma_kit", "antirad", "cryo_vial", "nanite_injector",
		"painkillers", "bio_gel", "splint_mech", "eye_drops", "oxygen_mask", "defibrillator",
		"family_photo", "medal", "toy_robot", "music_player", "lucky_charm_dice", "chess_set",
	]],
	["res://assets/icons/items19.png", [
		"void_lance", "bio_rifle", "star_pistol", "crystal_bow", "hive_cannon", "grav_hammer",
		"psi_blade", "chitin_sword", "singularity_orb", "plasma_whip", "spore_launcher", "shard_gauntlet",
		"precursor_rifle", "ion_scythe", "worldbreaker", "nova_staff", "eclipse_bow", "phase_daggers",
		"void_grenade", "acid_pod", "stasis_mine", "swarm_hive", "star_charge", "gravity_well",
		"void_cell", "bio_ammo", "star_shards", "psi_crystal", "chitin_spikes", "ion_core",
	]],
	["res://assets/icons/items20.png", [
		"helm_chitin", "carapace_chitin", "claws_chitin", "legs_chitin", "feet_chitin", "wings_chitin",
		"helm_void", "plate_void", "gauntlets_void", "legs_void", "boots_void", "shield_void",
		"helm_star", "plate_star", "gauntlets_star", "legs_star", "boots_star", "halo_pack",
		"helm_crystal", "robe_crystal", "gloves_crystal", "legs_crystal", "boots_crystal", "shield_prism",
		"helm_precursor", "chest_precursor", "hands_precursor", "legs_precursor", "feet_precursor", "cape_precursor",
	]],
	["res://assets/icons/items21.png", [
		"relic_eye", "relic_heart", "relic_cube", "relic_seed", "relic_skull", "relic_idol",
		"orb_memory", "tablet_star", "key_gate", "shard_god", "egg_alien", "compass_void",
		"crown_hive", "chalice_star", "mirror_void", "bell_astral", "lantern_spirit", "hourglass_time",
		"ring_void", "ring_star", "amulet_hive", "amulet_precursor", "bracelet_crystal", "earring_nebula",
		"map_galaxy", "beacon_ancient", "codex_alien", "core_titan", "feather_phoenix", "coin_alien",
	]],
	["res://assets/icons/items22.png", [
		"voidstone_ore", "starsteel_ore", "chitin_plate", "bio_gel_alien", "psi_crystal_large", "neutronium",
		"voidsteel_ingot", "starsteel_ingot", "crystal_thread", "living_metal", "dark_matter", "light_essence",
		"alien_circuit", "grav_core", "warp_coil", "ai_shard", "bio_battery", "phase_lens",
		"hide_xeno", "fang_xeno", "eye_xeno", "spore_sac", "venom_gland", "scale_dragon",
		"seed_glow", "fruit_alien", "fungus_alien", "egg_alien_food", "nectar_alien", "meat_xeno",
	]],
	["res://assets/icons/items23.png", [
		"elixir_void", "elixir_star", "serum_hive", "nanite_swarm", "regen_pod", "mutagen",
		"implant_eye", "implant_spine", "implant_heart", "implant_arm", "implant_brain", "symbiote",
		"food_star", "food_hive", "food_void", "food_crystal", "food_bio", "drink_nebula",
		"teleport_shard", "shield_charm", "revive_feather", "summon_orb", "time_shard", "invis_cloak_vial",
		"key_hive", "key_void", "key_star", "key_precursor", "keystone", "sigil_stone",
	]],
	["res://assets/icons/items24.png", [
		"arrow_fire", "arrow_barbed", "arrow_steel", "bolt_steel", "bolt_explosive", "quiver",
		"rounds_hollow", "rounds_ap", "rounds_box", "speed_loader", "rifle_clip", "slug_shells",
		"power_cell_small", "power_cell_large", "power_cell_spent", "battery_pack_rifle", "capacitor_bank", "charger_dock",
		"firewood", "coal_briquettes", "peat", "lamp_oil", "kerosene_can", "diesel_jerrycan",
		"hydrogen_cell", "fusion_pellets", "rocket_fuel", "plasma_fuel", "void_fuel", "star_fuel",
	]],
	# Fire (tools/place_icon.py, one item per cell): the fire pot, and the incendiary
	# grenade ahead of its item; then power pieces and the town watch's things
	# (plans/icon-prompts-2026-10-18.md, art/icons/v3 in project files). Cells 15-17 hold
	# the field cannon, cannon_ball and hot_shot, named when fire stage 3 brings the items.
	["res://assets/icons/items25.png", [
		"fire_pot", "incendiary_grenade", "lamp_ceiling", "lamp_wall", "floodlight", "street_lamp",
		"searchlight", "light_bulb", "knife_switch", "lever", "push_button", "pressure_plate",
		"motion_sensor", "daylight_sensor", "flame_trap", "", "", "",
		"treasure_chip", "watch_tabard", "grappling_hook", "writ", "watch_keys", "logic_timer",
		"logic_clock", "logic_gate", "logic_latch", "logic_counter", "logic_delay", "relay",
	]],
	["res://assets/icons/items26.png", [
		"charge_sensor", "door_motor", "electric_motor", "multimeter", "alarm_bell", "gen_woodgas",
		"gen_diesel", "windmill", "solar_array", "steam_engine", "water_wheel", "battery_bank",
		"battery_cell", "power_pole", "junction_box", "signal_wire", "insulator", "conveyor_belt",
		"hopper", "robot_arm", "auto_miner", "quarry_drill", "electric_furnace", "power_sawmill",
		"assembler", "auto_turret", "heavy_turret", "fence_post", "spike_trap", "",
	]],
]
## type -> [sheet path, its order], built on first use.
static var _sheet_of: Dictionary = {}
const BUILD_DIR := "res://assets/icons/build/"
static var _sheets: Dictionary = {}

static func _sheet_image(path: String) -> Image:
	if not _sheets.has(path):
		_sheets[path] = null
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex:
				_sheets[path] = tex.get_image()
	return _sheets[path]

static func _from_sheet(type: String) -> Texture2D:
	if _sheet_of.is_empty():
		for sh in MORE_SHEETS:
			for t in sh[1]:
				if t != "":
					_sheet_of[t] = sh
	var order: Array = SHEET_ORDER
	var path := SHEET_PATH
	if SHEET2_ORDER.has(type):
		order = SHEET2_ORDER
		path = SHEET2_PATH
	elif _sheet_of.has(type):
		order = _sheet_of[type][1]
		path = _sheet_of[type][0]
	var idx := order.find(type)
	var sheet := _sheet_image(path) if idx >= 0 else null
	if sheet == null:
		return null
	var rows := ceili(order.size() / float(SHEET_COLS))
	var cw := sheet.get_width() / SHEET_COLS
	var ch := sheet.get_height() / rows
	var cell := sheet.get_region(Rect2i((idx % SHEET_COLS) * cw, (idx / SHEET_COLS) * ch, cw, ch))
	cell.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(cell)

static func get_icon(type: String) -> Texture2D:
	if _cache.has(type):
		return _cache[type]
	var painted := _from_sheet(type)
	if painted == null and ResourceLoader.exists(BUILD_DIR + type + ".png"):
		# Building pieces and stations: rendered from their models by tools/render_build_icons.gd.
		painted = load(BUILD_DIR + type + ".png")
	if painted:
		_cache[type] = painted
		return painted
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var d := ItemDB.def(type)
	var c: Color = d.get("color", Color(0.7, 0.7, 0.7))
	match type:
		"stone":
			_poly(img, [Vector2(14, 40), Vector2(20, 22), Vector2(36, 16), Vector2(50, 26), Vector2(52, 42), Vector2(38, 50), Vector2(22, 50)], c)
			_poly(img, [Vector2(24, 26), Vector2(36, 20), Vector2(44, 28), Vector2(30, 32)], c.lightened(0.25))
		"iron_ore", "alloy_scrap":
			_poly(img, [Vector2(12, 42), Vector2(18, 20), Vector2(38, 12), Vector2(54, 28), Vector2(48, 48), Vector2(26, 54)], Color(0.38, 0.36, 0.36))
			var fleck := c.lightened(0.2) if type == "iron_ore" else Color(0.85, 0.87, 0.9)
			for p in [Vector2(26, 28), Vector2(38, 36), Vector2(30, 44), Vector2(42, 22)]:
				_circle(img, p, 4.0, fleck)
		"wood", "glowroot":
			_rect(img, Rect2(10, 22, 40, 20), c)
			_circle(img, Vector2(50, 32), 10.0, c.lightened(0.3))
			_circle(img, Vector2(50, 32), 5.0, c.lightened(0.1))
			for x in [18, 28, 38]:
				_rect(img, Rect2(x, 24, 2, 16), c.darkened(0.25))
		"aether_crystal":
			_poly(img, [Vector2(32, 6), Vector2(48, 26), Vector2(40, 56), Vector2(24, 56), Vector2(16, 26)], c)
			_poly(img, [Vector2(32, 6), Vector2(40, 26), Vector2(32, 56), Vector2(24, 26)], c.lightened(0.35))
		"circuitry":
			_rect(img, Rect2(16, 16, 32, 32), Color(0.1, 0.35, 0.18))
			_rect(img, Rect2(24, 24, 16, 16), Color(0.15, 0.15, 0.17))
			for i in 4:
				_rect(img, Rect2(18 + i * 8, 10, 3, 6), Color(0.85, 0.75, 0.3))
				_rect(img, Rect2(18 + i * 8, 48, 3, 6), Color(0.85, 0.75, 0.3))
		"planks":
			for i in 3:
				_rect(img, Rect2(8, 16 + i * 11, 48, 9), c.darkened(i * 0.08))
		"iron_ingot", "mythril_ingot":
			_poly(img, [Vector2(10, 46), Vector2(18, 24), Vector2(46, 24), Vector2(54, 46)], c)
			_poly(img, [Vector2(18, 24), Vector2(46, 24), Vector2(42, 30), Vector2(22, 30)], c.lightened(0.3))
		"alloy_plate":
			_rect(img, Rect2(10, 14, 44, 36), c)
			for p in [Vector2(15, 19), Vector2(49, 19), Vector2(15, 45), Vector2(49, 45)]:
				_circle(img, p, 2.5, c.darkened(0.4))
		"power_cell":
			_rect(img, Rect2(20, 12, 24, 42), Color(0.2, 0.22, 0.25))
			_rect(img, Rect2(27, 7, 10, 6), Color(0.6, 0.6, 0.62))
			_rect(img, Rect2(24, 28, 16, 22), c)
		"fire_pot":
			# A round clay pot, a rag tied over its mouth, a tongue of flame from the rag.
			_ellipse(img, Vector2(32, 40), Vector2(19, 17), c)
			_ellipse(img, Vector2(28, 36), Vector2(8, 7), c.lightened(0.2))
			_rect(img, Rect2(25, 20, 14, 6), c.darkened(0.2))
			_ellipse(img, Vector2(32, 19), Vector2(9, 4), Color(0.75, 0.68, 0.55))
			_poly(img, [Vector2(30, 16), Vector2(34, 4), Vector2(38, 15)], Color(1.0, 0.62, 0.2))
			_poly(img, [Vector2(32, 16), Vector2(34, 9), Vector2(36, 16)], Color(1.0, 0.9, 0.5))
		"cannon_ball", "hot_shot":
			# Three iron balls in a pile; hot shot glowing red from the forge.
			var hot := type == "hot_shot"
			for b in [Vector2(21, 42), Vector2(43, 42), Vector2(32, 24)]:
				_circle(img, b, 12.0, Color(0.1, 0.1, 0.11) if not hot else Color(0.55, 0.12, 0.03))
				_circle(img, b, 10.0, c if not hot else Color(0.85, 0.3, 0.06))
				_circle(img, b + Vector2(-3, -3), 4.0, c.lightened(0.35) if not hot else Color(1.0, 0.75, 0.3))
		"bread":
			_ellipse(img, Vector2(32, 36), Vector2(24, 14), c)
			for x in [22, 32, 42]:
				_rect(img, Rect2(x, 28, 3, 8), c.darkened(0.3))
		"lockpick":
			_line(img, Vector2(14, 52), Vector2(44, 16), 3.0, c)
			_line(img, Vector2(44, 16), Vector2(50, 18), 2.5, c)
			_line(img, Vector2(20, 54), Vector2(50, 40), 3.0, c.darkened(0.15))
			_line(img, Vector2(50, 40), Vector2(50, 32), 3.0, c.darkened(0.15))
			_rect(img, Rect2(10, 48, 10, 10), Color(0.4, 0.28, 0.16))
		"torch":
			_poly(img, [Vector2(29, 58), Vector2(35, 58), Vector2(37, 26), Vector2(27, 26)], Color(0.5, 0.33, 0.18))
			_rect(img, Rect2(25, 22, 14, 8), Color(0.35, 0.28, 0.2))
			_circle(img, Vector2(32, 15), 9.0, Color(1.0, 0.55, 0.15))
			_circle(img, Vector2(32, 17), 5.0, Color(1.0, 0.88, 0.45))
		"flashlight", "flashlight_dead":
			_poly(img, [Vector2(10, 40), Vector2(40, 30), Vector2(43, 38), Vector2(13, 48)], c)
			_poly(img, [Vector2(40, 26), Vector2(52, 22), Vector2(56, 38), Vector2(44, 42)], c.lightened(0.25))
			_circle(img, Vector2(54, 30), 5.0, Color(1.0, 0.95, 0.7) if type == "flashlight" else Color(0.3, 0.3, 0.32))
		"binoculars":
			for x in [20.0, 44.0]:
				_circle(img, Vector2(x, 38), 11.0, c)
				_circle(img, Vector2(x, 38), 6.0, Color(0.35, 0.55, 0.75))
				_circle(img, Vector2(x - 2, 36), 2.0, Color(0.85, 0.92, 1.0))
			_rect(img, Rect2(27, 22, 10, 14), c.lightened(0.15))
		"fiber":
			for i in 5:
				var x := 18.0 + i * 7.0
				_poly(img, [Vector2(x, 54), Vector2(x + 4, 54), Vector2(x + 10 - i * 2, 10 + i * 3), Vector2(x + 8 - i * 2, 10 + i * 3)], c.lightened(0.08 * i))
		"wild_berries", "glowberry":
			for p in [Vector2(24, 38), Vector2(40, 38), Vector2(32, 26)]:
				_circle(img, p, 10.0, c)
				_circle(img, p + Vector2(-3, -3), 3.0, c.lightened(0.5))
		"ration_pack":
			_rect(img, Rect2(12, 18, 40, 30), c)
			_rect(img, Rect2(12, 28, 40, 6), c.darkened(0.35))
		"silver_chalice":
			_poly(img, [Vector2(16, 12), Vector2(48, 12), Vector2(40, 30), Vector2(24, 30)], c)
			_rect(img, Rect2(30, 30, 4, 14), c)
			_rect(img, Rect2(20, 44, 24, 6), c)
		"gold_coin":
			_circle(img, Vector2(32, 32), 18.0, Color(0.95, 0.75, 0.3))
			_circle(img, Vector2(32, 32), 12.0, Color(1.0, 0.85, 0.45))
		"raw_meat", "cooked_meat":
			_ellipse(img, Vector2(30, 34), Vector2(20, 14), c)
			_ellipse(img, Vector2(26, 31), Vector2(9, 6), c.lightened(0.25))
			_line(img, Vector2(46, 40), Vector2(56, 50), 5, Color(0.92, 0.9, 0.84))
		"hide":
			_poly(img, [Vector2(12, 16), Vector2(52, 14), Vector2(56, 34), Vector2(48, 52), Vector2(16, 50), Vector2(8, 32)], c)
			_poly(img, [Vector2(18, 22), Vector2(46, 20), Vector2(48, 30), Vector2(20, 32)], c.lightened(0.15))
		"bone":
			_line(img, Vector2(18, 46), Vector2(46, 18), 7, c)
			for e in [Vector2(16, 48), Vector2(48, 16)]:
				_circle(img, e + Vector2(-4, -2), 5.0, c)
				_circle(img, e + Vector2(2, 4), 5.0, c)
		"animal_fat":
			_ellipse(img, Vector2(32, 38), Vector2(20, 13), c)
			_ellipse(img, Vector2(28, 33), Vector2(10, 6), c.lightened(0.2))
		"antler":
			_line(img, Vector2(20, 56), Vector2(30, 14), 5, c)
			_line(img, Vector2(26, 34), Vector2(46, 22), 4, c)
			_line(img, Vector2(28, 24), Vector2(44, 10), 4, c)
			_line(img, Vector2(24, 44), Vector2(12, 30), 4, c)
		"fur_pelt", "leather":
			_poly(img, [Vector2(12, 16), Vector2(52, 14), Vector2(56, 34), Vector2(48, 52), Vector2(16, 50), Vector2(8, 32)], c)
			if type == "fur_pelt":
				for i in 7:
					_line(img, Vector2(16 + i * 5, 22), Vector2(14 + i * 5, 44), 2, c.lightened(0.18))
			else:
				_rect(img, Rect2(14, 22, 36, 4), c.lightened(0.2))
				_rect(img, Rect2(14, 38, 36, 4), c.darkened(0.2))
		"skinning_knife":
			_line(img, Vector2(14, 52), Vector2(26, 40), 6, Color(0.5, 0.34, 0.2))
			_poly(img, [Vector2(26, 40), Vector2(52, 12), Vector2(46, 30), Vector2(30, 44)], c)
		"hammer":
			_line(img, Vector2(18, 54), Vector2(40, 22), 6, Color(0.55, 0.38, 0.22))
			_line(img, Vector2(18, 54), Vector2(40, 22), 2, Color(0.66, 0.48, 0.3))
			_poly(img, [Vector2(28, 12), Vector2(50, 26), Vector2(44, 36), Vector2(22, 22)], Color(0.48, 0.5, 0.54))
			_poly(img, [Vector2(28, 12), Vector2(50, 26), Vector2(48, 29), Vector2(26, 15)], Color(0.7, 0.72, 0.76))
		"treasure_map":
			# A rolled-open parchment with a dotted trail to a red X.
			_poly(img, [Vector2(8, 14), Vector2(56, 10), Vector2(54, 52), Vector2(10, 56)], c)
			_rect(img, Rect2(6, 10, 6, 46), c.darkened(0.25))
			_rect(img, Rect2(52, 8, 6, 46), c.darkened(0.25))
			for i in 5:
				_circle(img, Vector2(18 + i * 5, 46 - i * 5), 1.6, Color(0.35, 0.25, 0.15))
			_line(img, Vector2(38, 18), Vector2(48, 28), 3, Color(0.75, 0.12, 0.1))
			_line(img, Vector2(48, 18), Vector2(38, 28), 3, Color(0.75, 0.12, 0.1))
		"treasure_chip":
			_rect(img, Rect2(14, 12, 36, 40), c)
			_rect(img, Rect2(20, 18, 24, 18), Color(0.12, 0.14, 0.16))
			_line(img, Vector2(26, 23), Vector2(38, 31), 2, Color(0.95, 0.75, 0.3))
			_line(img, Vector2(38, 23), Vector2(26, 31), 2, Color(0.95, 0.75, 0.3))
			for i in 5:
				_rect(img, Rect2(18 + i * 6, 44, 3, 8), Color(0.85, 0.7, 0.3))
		"moonpearl", "data_core":
			_circle(img, Vector2(32, 32), 18.0, c)
			_circle(img, Vector2(26, 26), 6.0, c.lightened(0.6))
		_:
			var kind: String = d.get("kind", "")
			var metal := Color(0.75, 0.76, 0.8) if d.get("era", 0) != Eras.FANTASY else Color(0.6, 0.85, 1.0)
			if type.begins_with("pickaxe"):
				_line(img, Vector2(18, 54), Vector2(42, 18), 4, Color(0.45, 0.3, 0.18))
				_line(img, Vector2(22, 12), Vector2(56, 26), 5, metal)
			elif type.begins_with("axe"):
				_line(img, Vector2(18, 56), Vector2(40, 12), 4, Color(0.45, 0.3, 0.18))
				_poly(img, [Vector2(36, 10), Vector2(54, 14), Vector2(50, 32), Vector2(34, 22)], metal)
			elif type.begins_with("sword"):
				_line(img, Vector2(16, 48), Vector2(50, 14), 5, metal)
				_line(img, Vector2(12, 40), Vector2(24, 52), 4, Color(0.6, 0.45, 0.2))
				_line(img, Vector2(10, 54), Vector2(16, 48), 4, Color(0.4, 0.25, 0.15))
			elif type == "pulse_pistol":
				_rect(img, Rect2(12, 22, 38, 12), Color(0.3, 0.32, 0.36))
				_rect(img, Rect2(16, 34, 10, 18), Color(0.25, 0.26, 0.3))
				_rect(img, Rect2(34, 25, 14, 3), Color(0.3, 0.9, 1.0))
			elif type == "jet_fuel":
				# A jerry can.
				_rect(img, Rect2(16, 18, 32, 38), c)
				_rect(img, Rect2(22, 10, 14, 8), c.darkened(0.25))
				_rect(img, Rect2(38, 12, 6, 8), Color(0.25, 0.25, 0.27))
				_line(img, Vector2(20, 24), Vector2(44, 50), 3, c.darkened(0.3))
				_line(img, Vector2(44, 24), Vector2(20, 50), 3, c.darkened(0.3))
			elif kind == "armor":
				var hi := c.lightened(0.3)
				match String(d.get("slot", "")):
					"back":
						# Twin-tank jetpack with nozzles and flames.
						for x in [22, 42]:
							_rect(img, Rect2(x - 8, 14, 16, 32), c)
							_ellipse(img, Vector2(x, 14), Vector2(8, 5), hi)
							_rect(img, Rect2(x - 5, 46, 10, 5), c.darkened(0.45))
							_poly(img, [Vector2(x - 5, 51), Vector2(x + 5, 51), Vector2(x, 62)], Color(1.0, 0.6, 0.2))
						_rect(img, Rect2(28, 22, 8, 16), c.darkened(0.35))
					"head":
						_ellipse(img, Vector2(32, 30), Vector2(17, 18), c)
						_rect(img, Rect2(15, 30, 34, 18), c)
						_rect(img, Rect2(20, 30, 24, 5), Color(0.08, 0.09, 0.1) if d.get("era", 0) != Eras.SCIFI else Color(0.3, 0.9, 1.0))
						_ellipse(img, Vector2(26, 20), Vector2(5, 4), hi)
					"chest":
						_poly(img, [Vector2(12, 16), Vector2(24, 10), Vector2(32, 16), Vector2(40, 10), Vector2(52, 16), Vector2(48, 30), Vector2(46, 54), Vector2(18, 54), Vector2(16, 30)], c)
						_line(img, Vector2(32, 18), Vector2(32, 50), 2, c.darkened(0.3))
						_poly(img, [Vector2(20, 18), Vector2(28, 20), Vector2(26, 30), Vector2(20, 28)], hi)
					"legs":
						_poly(img, [Vector2(18, 10), Vector2(46, 10), Vector2(46, 56), Vector2(36, 56), Vector2(32, 24), Vector2(28, 56), Vector2(18, 56)], c)
						_rect(img, Rect2(18, 10, 28, 6), c.darkened(0.3))
						_rect(img, Rect2(20, 30, 6, 6), hi)
					_:
						_poly(img, [Vector2(20, 12), Vector2(34, 12), Vector2(34, 40), Vector2(52, 46), Vector2(52, 54), Vector2(18, 54)], c)
						_rect(img, Rect2(18, 50, 34, 4), c.darkened(0.4))
						_rect(img, Rect2(22, 14, 8, 4), hi)
			elif kind == "food":
				_circle(img, Vector2(32, 32), 16.0, c)
			else:
				_circle(img, Vector2(32, 32), 16.0, c)
	_outline(img)
	var t := ImageTexture.create_from_image(img)
	_cache[type] = t
	return t

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)

static func _circle(img: Image, p: Vector2, r: float, c: Color) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			if Vector2(x, y).distance_to(p) <= r:
				_put(img, x, y, c)

static func _ellipse(img: Image, p: Vector2, r: Vector2, c: Color) -> void:
	for y in range(int(p.y - r.y), int(p.y + r.y) + 1):
		for x in range(int(p.x - r.x), int(p.x + r.x) + 1):
			var d := Vector2((x - p.x) / r.x, (y - p.y) / r.y)
			if d.length_squared() <= 1.0:
				_put(img, x, y, c)

static func _rect(img: Image, r: Rect2, c: Color) -> void:
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			_put(img, x, y, c)

static func _poly(img: Image, pts: Array, c: Color) -> void:
	var poly := PackedVector2Array(pts)
	var b := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		b = b.expand(p)
	for y in range(int(b.position.y), int(b.end.y) + 1):
		for x in range(int(b.position.x), int(b.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				_put(img, x, y, c)

static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n := int(a.distance_to(b))
	for i in n + 1:
		_circle(img, a.lerp(b, float(i) / maxf(n, 1)), w * 0.5, c)

## Dark outline around every opaque pixel so icons read on any background.
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < S and q.y < S and src.get_pixel(q.x, q.y).a > 0.0:
					img.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.9))
					break
