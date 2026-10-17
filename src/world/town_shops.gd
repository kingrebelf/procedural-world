class_name TownShops
## Shops, guild halls and the land office in settlements: some of the houses you can walk
## into are run by a shopkeeper who stands behind a counter inside, sells the goods of
## their trade (armour, weapons, potions, supplies, food and drink) and has a painted
## sign over the door. Bigger places have guild halls you can join and someone who sells
## houses: the lord's steward, the grove elder, the colony's land registry, whoever fits
## the place. Which building is which follows from the settlement's layout alone, so old
## saves get shops too; the people who run them are hired once and saved with the rest of
## the settlement (data["shops_v"], rec["shop_kind"], rec["shop_i"]).

const SHOPS_V := 1

## Shops in every era. label / job / names / goods are per era [medieval, fantasy, sci-fi].
## icon: the item whose picture goes on the sign.
const KINDS := {
	"armourer": {
		"label": ["Armourer", "Armourer", "Armour Depot"],
		"job": ["armourer", "wardweaver", "armour tech"],
		"names": [["The Iron Shell", "Steel & Mail", "The Gilded Gauntlet", "Hearthguard Armoury"],
			["The Silver Bark", "Moonmail", "The Thornward", "Leafsteel"],
			["Hardshell Supply", "Plate & Visor", "Bulwark Armour Co.", "Exo Outfitters"]],
		"goods": [["helm_iron", "mail_iron", "greaves_iron", "boots_leather", "gloves_leather", "shield_wood", "helm_elven",
				"tunic_padded", "cap_hide", "vest_hide", "leggings_hide", "boots_hide", "helm_studded", "jerkin_studded",
				"gloves_studded", "pants_studded", "boots_studded", "shield_kite", "helm_bronze", "cuirass_bronze", "greaves_bronze",
				"shield_bronze", "buckler_wood"],
			["helm_elven", "plate_mythril", "guards_mythril", "boots_elven", "bracers_rune", "shield_crystal", "mail_iron"],
			["helm_visor", "exo_chest", "exo_legs", "mag_boots", "gauntlets_power", "shield_emitter", "boots_leather",
				"hat_cowboy", "duster", "gloves_riding", "chaps", "boots_riding", "hardhat_lamp", "overalls", "gloves_work",
				"trousers_canvas", "boots_steeltoe", "welding_mask", "vest_plated", "gauntlets_heavy", "legplates_riveted",
				"boots_iron", "shield_riot", "gasmask", "trenchcoat", "gloves_rubber", "trousers_wool_heavy", "boots_hobnail",
				"helm_recon", "suit_recon", "gloves_tactical", "pants_recon", "boots_tactical", "pack_recon", "helm_combat",
				"armor_combat", "gloves_combat", "legs_combat", "boots_combat", "shield_ballistic", "helm_eva", "suit_eva",
				"gloves_eva", "legs_eva", "boots_eva", "oxygen_pack", "helm_stealth", "boots_stealth"]],
		"icon": ["helm_iron", "helm_elven", "helm_visor"],
	},
	"weaponsmith": {
		"label": ["Weaponsmith", "Bladewright", "Armory"],
		"job": ["weaponsmith", "bladewright", "armorer"],
		"names": [["The Keen Edge", "Sword & Sorrow", "The Black Anvil", "Fletcher & Forge"],
			["The Singing Blade", "Runeforge", "The Thorn & Bow", "Starsteel"],
			["Pulse Arms", "Hot Barrel", "Kinetic Solutions", "Frontier Firearms"]],
		"goods": [["sword_iron", "battle_axe", "war_hammer", "mace", "spear", "dagger", "longbow", "crossbow", "arrow", "bolt",
				"bronze_sword", "bronze_axe", "falchion", "morning_star", "warpick", "glaive", "shortbow", "composite_bow",
				"broadhead_arrows", "javelin", "throwing_knives", "hand_axe", "hunting_spear", "arrow_barbed", "arrow_steel",
				"arrow_fire", "fire_pot", "bolt_steel", "quiver"],
			["sword_runic", "crossbow_runic", "longbow", "spear", "dagger", "arrow", "bolt"],
			["pulse_pistol", "pulse_smg", "pulse_rifle", "rail_rifle", "arc_launcher", "scrap_pistol", "rounds",
				"flintlock_pistol", "musket", "blunderbuss", "revolver_six", "lever_rifle", "double_shotgun", "bolt_rifle",
				"derringer", "flare_gun", "harpoon_gun", "sabre", "machete", "tomahawk", "bowie_knife", "bayonet", "sledgehammer",
				"dynamite", "frag_grenade", "fire_bottle", "bear_trap", "tripwire", "black_powder", "musket_balls",
				"shotgun_shells", "rifle_cartridges", "ammo_belt", "gun_oil", "laser_pistol", "smart_pistol", "needle_gun",
				"carbine_combat", "auto_shotgun", "plasma_rifle", "gauss_rifle", "grenade_launcher", "vibro_knife", "stun_baton",
				"combat_machete", "chain_axe", "smart_rounds", "energy_cell", "shells_12g", "plasma_canister", "gauss_slugs",
				"frag_grenade_mk2", "smoke_grenade"], "rounds_hollow", "rounds_ap", "slug_shells", "speed_loader", "rifle_clip", "rounds_box", "bolt_explosive"],
		"icon": ["sword_iron", "sword_runic", "pulse_rifle"],
	},
	"apothecary": {
		"label": ["Apothecary", "Alchemist", "Med Bay"],
		"job": ["apothecary", "alchemist", "medic"],
		"names": [["The Bitter Root", "Mother's Remedies", "The Green Bottle", "Physick & Tonic"],
			["The Bubbling Cauldron", "Dewdrop Draughts", "The Moonlit Vial", "Elixirs of the Fen"],
			["StimLab", "Patch & Pill", "Triage Station", "BioCare"]],
		"goods": [["health_potion", "stamina_potion", "wild_berries", "potion_health_minor", "antidote", "tonic_warmth",
				"tonic_cooling", "elixir_nightsight", "salve", "bandage_linen", "herbal_poultice", "smelling_salts", "herb_red",
				"herb_blue", "herb_yellow", "herb_mint", "herb_root", "empty_vial", "mortar_pestle", "honey"],
			["health_potion", "stamina_potion", "glowberry", "moonpearl"],
			["health_potion", "stamina_potion", "ration_pack", "medkit_frontier", "bandage_roll", "splint", "tonic_bottle",
				"iodine", "syringe_glass", "tea_tin", "painkillers", "bio_gel", "stimpack", "trauma_kit", "medkit_mil",
				"antirad", "cryo_vial", "splint_mech", "eye_drops", "oxygen_mask", "o2_canister"]],
		"icon": ["health_potion", "health_potion", "health_potion"],
	},
	"general": {
		"label": ["General Goods", "Wayfarer's Goods", "Supply Exchange"],
		"job": ["shopkeeper", "provisioner", "quartermaster"],
		"names": [["The Copper Kettle", "Odds & Ends", "Crossroads Provisions", "The Full Sack"],
			["The Wandering Basket", "Rootcellar", "Mossy Hollow Goods", "The Lantern Nook"],
			["Depot 9", "Colony Stores", "Salvage & Supply", "The Cargo Bay"]],
		"goods": [["bread", "torch", "planks", "wood", "pickaxe_iron", "axe_iron", "hammer", "binoculars", "fiber", "cooked_meat", "iron_ingot",
				"rope", "cloth", "candle", "lamp_oil", "hand_lantern", "tinderbox", "flint", "waterskin", "bucket", "shovel", "sickle",
				"saw", "fishing_rod", "bedroll", "salt", "flour", "charcoal", "iron_nails", "wool", "firewood", "peat", "coal_briquettes"],
			["glowberry", "glowroot", "torch", "axe_mythril", "pickaxe_mythril", "binoculars", "fiber", "mythril_ingot", "aether_crystal"],
			["ration_pack", "power_cell", "flashlight", "circuitry", "alloy_plate", "pickaxe_plasma", "jet_fuel", "binoculars", "alloy_scrap",
				"wrench", "crowbar", "hand_drill", "pickaxe_miner", "axe_lumber", "lamp_kerosene", "gears", "springs",
				"pipe_section", "valve", "pressure_gauge", "piston", "coal_sack", "oil_barrel", "rubber", "steel_sheet",
				"copper_wire", "glass_pane", "compass", "backpack_canvas", "satchel", "water_canteen", "coffee_beans",
				"beans_can", "jerky", "biscuit_hard", "apple_dried", "multitool", "survival_knife", "scanner", "flare_chem",
				"rope_synth", "beacon_nav", "binoculars_digital", "toolbox_tech", "battery_small", "titanium_ingot", "polymer",
				"circuit_board", "wiring_loom", "microchip", "servo", "optic_lens", "coolant", "magnet", "antenna", "solar_panel",
				"hull_patch", "ration_bar", "water_pouch", "hydro_greens"], "kerosene_can", "diesel_jerrycan", "power_cell_small",
				"power_cell_large", "charger_dock", "hydrogen_cell", "rocket_fuel", "plasma_fuel", "fusion_pellets", "battery_pack_rifle",
				"capacitor_bank"],
		"icon": ["pickaxe_iron", "glowberry", "power_cell"],
	},
	"tavern": {
		"label": ["Tavern", "Mead Hall", "Cantina"],
		"job": ["innkeeper", "meadwarden", "bartender"],
		"names": [["The Prancing Pig", "The Drunken Duck", "The Crown & Tankard", "The Weary Wanderer"],
			["The Glowing Goblet", "The Hollow Oak", "Fireflies' Rest", "The Laughing Sprite"],
			["The Rusty Airlock", "Zero-G Lounge", "Last Light Cantina", "The Docking Bay"]],
		"goods": [["bread", "cooked_meat", "wild_berries", "health_potion", "apple", "ham", "sausage", "stew", "porridge",
				"pie_meat", "pie_berry", "soup_veg", "travel_bread", "milk", "wine", "mead", "fish_cooked", "dice", "pear", "grapes"],
			["glowberry", "cooked_meat", "bread", "stamina_potion"],
			["ration_pack", "cooked_meat", "stamina_potion", "steak", "chili", "cornbread", "coffee_pot", "whiskey",
				"sarsaparilla", "pickles", "cheese_wheel_small", "egg_fried", "pancakes", "stew_tin", "cards_deck", "harmonica",
				"synth_steak", "noodles", "freeze_meal", "protein_pack", "nutri_paste", "fruit_cube", "algae_bar",
				"space_coffee", "energy_drink", "chess_set", "music_player"]],
		"icon": ["cooked_meat", "glowberry", "ration_pack"],
	},
	"land": {
		"label": ["Lord's Manor", "Elder's Bower", "Land Registry"],
		"job": ["steward", "grove elder", "registry clerk"],
		"names": [["Houses and land for sale", "Deeds and holdings", "Houses for sale", "Land and lodgings"],
			["Grove-rights granted", "Homes beneath the boughs", "Burrows and bowers", "Hollows for settlers"],
			["Hab leases available", "Plots and permits", "Colonial housing office", "Habitation leases"]],
		"goods": [[], [], []],
		"icon": ["silver_chalice", "rune_tablet", "data_core"],
	},
}

## Small villages' land seller: a reeve rather than the lord, by era.
const LAND_SMALL := [["Reeve's House", "reeve"], ["Elder's Bower", "grove elder"], ["Land Registry", "registry clerk"]]

## Guild halls, by era. Membership is the traveller's (Game.guilds) and counts in every
## hall of that guild. fee: Marks to join. favours: shops where members pay less.
## sells: the hall's own goods, for members only.
const GUILDS := {
	"fighters_guild": {"era": 0, "label": "Fighters' Guild", "job": "guildmaster", "fee": 150,
		"names": ["The Iron Brotherhood", "Hall of Shields", "The Red Banner"], "favours": ["armourer", "weaponsmith"],
		"goods": ["battle_axe", "war_hammer", "mail_iron", "greaves_iron", "shield_wood", "helm_iron", "health_potion",
			"steel_sword", "halberd", "zweihander", "helm_steel", "plate_steel", "gauntlets_steel", "cuisses_steel", "sabatons_steel",
			"shield_tower", "steel_ingot"], "icon": "battle_axe",
		"perk": "Members pay less at armourers and weaponsmiths."},
	"mages_guild": {"era": 0, "label": "Mages' Guild", "job": "archmage", "fee": 250,
		"names": ["The Circle of the Eye", "Tower of Lore", "The Azure Order"], "favours": ["apothecary"],
		"goods": ["aether_crystal", "rune_tablet", "stamina_potion", "health_potion", "moonpearl", "sword_runic",
			"potion_health_greater", "potion_stamina_greater", "elixir_strength", "elixir_swiftness", "scroll_red", "scroll_blue",
			"scroll_green", "scroll_plain", "quill_ink", "cauldron_small", "book_leather"], "icon": "rune_tablet",
		"perk": "Members pay less for potions and buy arcane goods."},
	"thieves_guild": {"era": 0, "label": "Thieves' Guild", "job": "fence", "fee": 120,
		"names": ["The Quiet Hand", "Rats' Cellar", "The Velvet Mask"], "favours": [], "fence": true,
		"goods": ["dagger", "crossbow", "bolt", "dungeon_key", "gold_idol", "lockpick", "rapier", "throwing_knives", "lucky_coin",
			"elixir_nightsight", "letter_sealed"], "icon": "dagger",
		"perk": "Members can fence treasure here at a much better price."},
	"merchants_guild": {"era": 0, "label": "Merchants' Guild", "job": "guild factor", "fee": 300,
		"names": ["The Golden Scales", "Company of the Road", "The Coin & Ledger"], "favours": ["*"],
		"goods": ["silver_chalice", "gold_idol", "iron_ingot", "horse", "binoculars", "silver_ingot", "gold_ingot", "ring_silver",
			"amulet_silver", "tent_kit", "lute", "wine"], "icon": "silver_chalice",
		"perk": "Members get better prices in every shop."},
	"rangers_lodge": {"era": 1, "label": "Rangers' Lodge", "job": "ranger captain", "fee": 160,
		"names": ["The Green Watch", "Lodge of the Long Bow", "Wardens of the Wild"], "favours": ["armourer", "weaponsmith"],
		"goods": ["longbow", "arrow", "boots_elven", "spear", "helm_elven", "guards_mythril"], "icon": "longbow",
		"perk": "Members pay less at armourers and bladewrights."},
	"arcane_conclave": {"era": 1, "label": "Arcane Conclave", "job": "archmage", "fee": 260,
		"names": ["The Starlit Conclave", "Circle of the Mere", "The Moonspire Order"], "favours": ["apothecary"],
		"goods": ["aether_crystal", "rune_tablet", "moonpearl", "sword_runic", "crossbow_runic", "stamina_potion"], "icon": "aether_crystal",
		"perk": "Members pay less for draughts and buy arcane goods."},
	"shadow_court": {"era": 1, "label": "Shadow Court", "job": "fence", "fee": 130,
		"names": ["The Night Moths", "Court of Whispers", "The Hollow Crown"], "favours": [], "fence": true,
		"goods": ["dagger", "dungeon_key", "moonpearl", "crossbow_runic"], "icon": "moonpearl",
		"perk": "Members can fence treasure here at a much better price."},
	"druid_circle": {"era": 1, "label": "Druid Circle", "job": "archdruid", "fee": 200,
		"names": ["The Old Oak Circle", "Keepers of the Root", "The Verdant Ring"], "favours": ["*"],
		"goods": ["glowroot", "glowberry", "health_potion", "stamina_potion", "axe_mythril"], "icon": "glowroot",
		"perk": "Members get better prices in every shop."},
	"mercenary_guild": {"era": 2, "label": "Mercenary Guild", "job": "contract broker", "fee": 220,
		"names": ["Iron Wolves", "The Free Company", "Blackstar Contractors"], "favours": ["armourer", "weaponsmith"],
		"goods": ["pulse_rifle", "rail_rifle", "exo_chest", "exo_legs", "rounds", "shield_emitter", "health_potion",
			"bolt_rifle", "lever_rifle", "rifle_cartridges", "vest_plated", "shield_riot", "frag_grenade", "sheriff_star",
			"rocket_launcher", "rocket", "minigun", "flamethrower", "fuel_canister", "breach_charge", "proximity_mine",
			"emp_grenade", "turret_deploy", "dog_tags", "medal"], "icon": "rail_rifle",
		"perk": "Members pay less at armour depots and armories."},
	"engineers_guild": {"era": 2, "label": "Engineers' Guild", "job": "chief engineer", "fee": 240,
		"names": ["The Gearwrights", "Union of Builders", "The Torque Society"], "favours": ["general"],
		"goods": ["power_cell", "circuitry", "alloy_plate", "pickaxe_plasma", "jet_fuel", "jetpack", "pocket_watch",
			"pressure_gauge", "piston", "valve", "dynamite", "powder_keg", "welding_mask", "gauntlets_heavy",
			"laser_cutter", "welder", "mining_laser", "repair_kit", "graphene", "carbon_fiber", "nanotube_spool", "processor",
			"sensor_module", "gyroscope", "thruster_part", "superconductor", "fusion_core", "shield_gen", "drone_scout"], "icon": "power_cell",
		"perk": "Members pay less for supplies and buy jetpacks."},
	"smugglers_syndicate": {"era": 2, "label": "Smugglers' Syndicate", "job": "fence", "fee": 140,
		"names": ["The Back Channel", "Dark Dock", "The Grey Market"], "favours": [], "fence": true,
		"goods": ["void_gem", "data_core", "scrap_pistol", "dungeon_key", "safe_key", "derringer", "cigar_box", "whiskey",
			"gold_nugget", "hack_tablet", "keycard_red", "keycard_blue", "suit_stealth", "gloves_stealth", "legs_stealth",
			"credit_chip", "holo_projector"], "icon": "void_gem",
		"perk": "Members can fence treasure here at a much better price."},
	"pilots_guild": {"era": 2, "label": "Pilots' Guild", "job": "flight master", "fee": 280,
		"names": ["Wings of the Frontier", "The Long Haul Club", "Skyward Union"], "favours": ["*"],
		"goods": ["jet_fuel", "jetpack", "flashlight", "mag_boots", "speeder", "compass", "spectacles", "banjo",
			"bandana", "grapple", "headset", "motion_tracker", "magboots_kit", "jetpack_military", "lucky_charm_dice", "hydrogen_cell", "rocket_fuel"], "icon": "jetpack",
		"perk": "Members get better prices in every shop."},
}

const GUILD_DISCOUNT := 0.85 ## what members pay at the shops their guild favours
const ALL_DISCOUNT := 0.92 ## and everywhere, in the merchants' sort of guild
const FENCE_BONUS := 1.35 ## what a fence pays members for treasure, over the usual

## Houses that can be shops or sold: [base price, size rank].
const ROOMS := {
	"cottage": [600, 1], "longhouse": [800, 2], "townhouse": [1100, 3], "mushroom_house": [700, 1],
	"hab_dome": [900, 2], "hab_block": [1200, 2], "lab_block": [1600, 3], "ops_tower": [1500, 3],
}

## Shops wanted by settlement size, in the order they claim buildings (nearest the
## square first). Guilds are added on top for villages and towns.
const WANTED := [
	["general", "land", "apothecary"],
	["general", "land", "weaponsmith", "armourer", "apothecary", "tavern"],
	["general", "land", "weaponsmith", "armourer", "apothecary", "tavern"],
]
const GUILD_COUNT := [0, 1, 3]

static var _plans: Dictionary = {}
static var _layouts: Dictionary = {}

static func is_guild(kind: String) -> bool:
	return GUILDS.has(kind)

static func era_guilds(era: int) -> Array:
	var out: Array = []
	for g in GUILDS:
		if int(GUILDS[g]["era"]) == era:
			out.append(g)
	return out

## Everything that can be a shop or a house for sale in the settlement, with the shops
## assigned: [{i, t, p, yaw, kind ("" for a plain house), label, title, era, size, sid}].
## Deterministic per settlement.
static func plan(gen: ChunkGenerator, s: Dictionary) -> Array:
	var sid := NPCGen.settlement_id(s["sx"], s["sz"])
	if _plans.has(sid):
		return _plans[sid]
	var c: Vector2 = s["center"]
	var era: int = s["era"]
	var size := int(s.get("size", 0))
	var cands: Array = []
	for it in gen.settlement_layout(s):
		if ROOMS.has(it["t"]):
			cands.append({"t": it["t"], "p": it["p"], "yaw": float(it["yaw"]), "d": (it["p"] as Vector2).distance_to(c)})
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	var r := WHash.rng(gen.seed, s["sx"], s["sz"], 611)
	var wanted: Array = WANTED[size].duplicate()
	var guilds := era_guilds(era)
	for n in GUILD_COUNT[size]:
		var g: String = guilds[(r.randi() % guilds.size())]
		while wanted.has(g):
			g = guilds[(guilds.find(g) + 1) % guilds.size()]
		wanted.append(g)
	# Keep a house or two for sale (and for people to live in); no land seller where
	# there would be nothing to sell.
	var spare := 0 if cands.size() < 2 else maxi(1, cands.size() / 4)
	if cands.size() < 3:
		wanted.erase("land")
	var shops := mini(wanted.size(), cands.size() - spare)
	var out: Array = []
	for i in cands.size():
		var e: Dictionary = cands[i]
		out.append({"i": i, "t": e["t"], "p": e["p"], "yaw": e["yaw"], "kind": "", "label": "", "title": "",
			"era": era, "size": size, "sid": sid})
	var taken := {}
	for n in shops:
		var kind: String = wanted[n]
		var pick := -1
		if kind == "land":
			# The grandest house among the nearer half.
			var best := -1
			for i in mini(out.size(), maxi(3, out.size() / 2)):
				if taken.has(i):
					continue
				var rank: int = ROOMS[out[i]["t"]][1]
				if rank > best:
					best = rank
					pick = i
		else:
			for i in out.size():
				if not taken.has(i):
					pick = i
					break
		if pick < 0 or taken.has(pick):
			for i in out.size():
				if not taken.has(i):
					pick = i
					break
		if pick < 0:
			break
		taken[pick] = true
		var sh: Dictionary = out[pick]
		sh["kind"] = kind
		sh["label"] = label_of(kind, era, size)
		var names: Array = GUILDS[kind]["names"] if is_guild(kind) else KINDS[kind]["names"][era]
		sh["title"] = names[r.randi() % names.size()]
	_plans[sid] = out
	return out

static func shops_of(gen: ChunkGenerator, s: Dictionary) -> Array:
	return plan(gen, s).filter(func(h): return h["kind"] != "")

static func label_of(kind: String, era: int, size := 2) -> String:
	if is_guild(kind):
		return GUILDS[kind]["label"]
	if kind == "land" and size == 0:
		return LAND_SMALL[era][0]
	return KINDS[kind]["label"][era]

static func job_of(kind: String, era: int, size := 2) -> String:
	if is_guild(kind):
		return GUILDS[kind]["job"]
	if kind == "land" and size == 0:
		return LAND_SMALL[era][1]
	return KINDS[kind]["job"][era]

static func icon_of(kind: String, era: int) -> String:
	if is_guild(kind):
		return GUILDS[kind]["icon"]
	return KINDS[kind]["icon"][era]

## The keeper's wares within reach of the town's zone (themed worlds): a frontier store
## at level 12 has no power armour on the shelf; out past level 40 it does.
static func pool_for(rec: Dictionary) -> Array:
	var all := goods_of(String(rec["shop_kind"]), int(rec["era"]))
	if not Eras.themed() or not rec.get("pos") is Vector3:
		return all
	var p: Vector3 = rec["pos"]
	var cap := Eras.zone_level(p.x, p.z) + 5
	return all.filter(func(t): return int(ItemDB.UNLOCK.get(t, 1)) <= cap)

static func goods_of(kind: String, era: int) -> Array:
	if is_guild(kind):
		return GUILDS[kind]["goods"]
	return KINDS[kind]["goods"][era]

# --- Rooms --------------------------------------------------------------------------------

## A walk-in room's shape in its own space (door on +z): {half: inner half size (x, z),
## door_x, door_z: the outer face of the front wall, floor: floor height, sign: [centre,
## size, "wall" | "post"]}.
static func room(t: String) -> Dictionary:
	if KitHouse.has(t):
		var p: Array = KitHouse.PLANS[t]
		var w := float(p[0]) * 2.0
		var d := float(p[1]) * 2.0
		var dz := d / 2 + KitHouse.WALL_OUT
		return {"half": Vector2(w / 2 - KitHouse.WALL_IN, d / 2 - KitHouse.WALL_IN), "door_x": -w / 2 + 1 + 2.0 * int(int(p[0]) / 2),
			"door_z": dz, "floor": KitHouse.FLOOR, "sign": [Vector3(0, 2.78, dz + 0.04), Vector2(2.1, 0.62), "wall"]}
	if Interiors.BOX.has(t):
		var b: Array = Interiors.BOX[t]
		var dz: float = (b[3] as Vector2).y
		var door: Array = b[5]
		return {"half": b[0], "door_x": float(door[0]), "door_z": dz, "floor": float(b[1]),
			"sign": [Vector3(float(door[0]), float(door[2]) + 0.42, dz + 0.04), Vector2(2.6, 0.62), "wall"]}
	if t == "mushroom_house":
		var rd: Array = Interiors.ROUND[t]
		return {"half": Vector2(1.75, 1.75), "door_x": 0.0, "door_z": float(rd[0]), "floor": float(rd[5]),
			"sign": [Vector3(0, 2.72, 2.55), Vector2(1.4, 0.48), "wall"],
			"round": float(rd[0]) - float(rd[2]) - 0.15}
	if t == "hab_dome":
		return {"half": Vector2(2.7, 2.7), "door_x": 0.0, "door_z": Interiors.RAMP[2], "floor": float(Interiors.DOME[3]),
			"sign": [Vector3(2.1, 2.3, 5.2), Vector2(1.7, 0.6), "post"]}
	return {}

## Room-space point to world (x, z) for a building at p turned by yaw.
static func to_world(p: Vector2, yaw: float, l: Vector2) -> Vector2:
	return p + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))

static func to_local(p: Vector2, yaw: float, w: Vector2) -> Vector2:
	var d := w - p
	return Vector2(d.x * cos(yaw) - d.y * sin(yaw), d.x * sin(yaw) + d.y * cos(yaw))

## Where you stand outside the door, in world (x, z).
static func door_point(h: Dictionary) -> Vector2:
	var rm := room(h["t"])
	return to_world(h["p"], h["yaw"], Vector2(rm["door_x"], rm["door_z"] + 1.0))

## The room's furniture footprints (room space), the hearth, the loot chest and the
## doorway: everywhere a counter must not go.
static func _obstacles(t: String) -> Array:
	var rm := room(t)
	var out: Array = []
	var furn: Array = KitHouse.FURNISH[t] if KitHouse.has(t) else Interiors.FURNISH.get(t, [])
	var floor_y: float = rm["floor"]
	for f in furn:
		var name: String = f[0]
		var pos: Vector3 = f[2]
		if pos.y > floor_y + 1.2:
			continue # on a shelf or the wall, above head height of a counter
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(f[1]))), pos)
		var box: AABB
		if name.begins_with("@"):
			var sz: Vector3 = Interiors.PIECES.get(name, Vector3(1, 1, 1))
			box = _xf_box(xf, AABB(Vector3(-sz.x / 2, 0, -sz.z / 2), sz))
		else:
			box = KitHouse._model_box(name, xf)
		if box.size.x < 0.25 and box.size.z < 0.25:
			continue # a mug or a candle
		out.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.08))
	if KitHouse.has(t):
		var hx := KitHouse.hearth_x(t)
		var back: float = -(rm["half"] as Vector2).y
		out.append(Rect2(hx - 1.0, back, 2.0, 1.1))
	for spot in Interiors.LOOT.get(t, []):
		var q: Vector3 = spot[0]
		out.append(Rect2(q.x - 0.65, q.z - 0.65, 1.3, 1.3))
	var hz: float = (rm["half"] as Vector2).y
	out.append(Rect2(float(rm["door_x"]) - 0.8, hz - 1.6, 1.6, 1.7))
	if t == "hab_dome":
		out.append(Rect2(-0.9, -0.9, 1.8, 1.8)) # the holo table
	return out

static func _xf_box(xf: Transform3D, b: AABB) -> AABB:
	var out := AABB(xf * b.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xf * b.get_endpoint(i))
	return out

static func _clear(r: Rect2, obs: Array, half: Vector2) -> bool:
	if r.position.x < -half.x or r.position.y < -half.y or r.end.x > half.x or r.end.y > half.y:
		return false
	for o in obs:
		if (o as Rect2).intersects(r):
			return false
	return true

static var _fits: Dictionary = {}

## Where the counter goes in a room type, found by searching the floor for a place clear
## of the furniture: {counter: centre (room space x, z), face: direction the counter faces
## (towards the customer), width, keeper: where the keeper stands, display: a free spot
## beside the keeper for a stand of wares, or Vector2.INF}. Empty when nothing fits.
## Needs kit model arrays: call on the main thread.
static func fit(t: String) -> Dictionary:
	if _fits.has(t):
		return _fits[t]
	var rm := room(t)
	var out := {}
	if rm.is_empty():
		_fits[t] = out
		return out
	var half: Vector2 = rm["half"]
	var obs := _obstacles(t)
	var door_x: float = rm["door_x"]
	var best := INF
	for width: float in [1.5, 1.2, 0.9, 0.7]:
		for face: Vector2 in [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]:
			var side := Vector2(face.y, -face.x).abs()
			var x := -half.x
			while x <= half.x:
				var z := -half.y
				while z <= half.y:
					var cpos := Vector2(x, z)
					var ext := side * width * 0.5 + face.abs() * 0.27
					var counter := Rect2(cpos - ext, ext * 2.0)
					var kp := cpos - face * 0.62
					var keeper := Rect2(kp - Vector2(0.35, 0.35), Vector2(0.7, 0.7))
					var cp := cpos + face * 0.85
					var cust := Rect2(cp - Vector2(0.45, 0.45), Vector2(0.9, 0.9))
					if _clear(counter, obs, half) and _clear(keeper, obs, half) and _clear(cust, obs, half + Vector2(0.4, 0.4)):
						var sc := absf(x - door_x) * 0.35 + absf(z + half.y * 0.25) * 0.25 + (0.0 if face.y > 0.5 else 0.9) + (1.5 - width)
						if sc < best:
							best = sc
							out = {"counter": cpos, "face": face, "width": width, "keeper": kp}
					z += 0.1
				x += 0.1
		if not out.is_empty():
			break
	if out.is_empty():
		# Too small for a counter: somewhere clear for the keeper to stand, facing the door.
		var x := -half.x
		while x <= half.x:
			var z := -half.y
			while z <= half.y:
				var kp := Vector2(x, z)
				if _clear(Rect2(kp - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), obs, half):
					var sc := kp.distance_to(Vector2(door_x, -half.y * 0.3))
					if sc < best:
						best = sc
						out = {"keeper": kp, "face": Vector2(0, 1)}
				z += 0.1
			x += 0.1
		if not out.is_empty():
			out["props"] = _prop_spots(out["keeper"], obs, half, rm)
		_fits[t] = out
		return out
	if not out.is_empty():
		# A stand of wares beside the keeper, if there is room.
		var face: Vector2 = out["face"]
		var side := Vector2(face.y, -face.x)
		var ext := side.abs() * float(out["width"]) * 0.5 + face.abs() * 0.27
		obs.append(Rect2((out["counter"] as Vector2) - ext, ext * 2.0))
		out["display"] = Vector2.INF
		for sgn: float in [1.0, -1.0]:
			for off: float in [1.15, 1.35, 1.6]:
				var dp: Vector2 = out["keeper"] + side * sgn * (float(out["width"]) * 0.5 + off - 0.75) - face * 0.05
				if _clear(Rect2(dp - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), obs, half):
					out["display"] = dp
					break
			if out["display"] != Vector2.INF:
				break
	_fits[t] = out
	return out

## A room too small for a counter still looks like a shop: up to three clear spots for
## the trade's stand and a crate or two of wares, against the walls, not on the keeper and
## not in the way in from the door.
static func _prop_spots(keeper: Vector2, obs: Array, half: Vector2, rm: Dictionary) -> Array:
	var out: Array = []
	var taken := obs.duplicate()
	taken.append(Rect2(keeper - Vector2(0.45, 0.45), Vector2(0.9, 0.9)))
	var door_x: float = rm["door_x"]
	taken.append(Rect2(Vector2(door_x - 0.6, half.y - 1.5), Vector2(1.2, 1.6)))
	for n in 3:
		var best := INF
		var at := Vector2.INF
		var x := -half.x
		while x <= half.x:
			var z := -half.y
			while z <= half.y:
				var sp := Vector2(x, z)
				var wall := minf(half.x - absf(x), half.y - absf(z)) - 0.33
				if rm.has("round"):
					wall = float(rm["round"]) - sp.length() - 0.47
				if wall >= 0.0 and _clear(Rect2(sp - Vector2(0.33, 0.33), Vector2(0.66, 0.66)), taken, half):
					var sc := wall + sp.distance_to(keeper) * 0.25
					if sc < best:
						best = sc
						at = sp
				z += 0.1
			x += 0.1
		if at == Vector2.INF:
			break
		out.append(at)
		taken.append(Rect2(at - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))
	return out

## Door-aware walking for someone whose work is inside a room: the waypoint to head for
## from p on the way to goal. room: rec["room"] = {c, yaw, half, door_x, door_z}.
static func route(rm: Dictionary, p: Vector2, goal: Vector2) -> Vector2:
	if goal == Vector2.INF:
		return goal
	var c: Vector2 = rm["c"]
	var yaw: float = rm["yaw"]
	var half: Vector2 = rm["half"]
	var dx: float = rm["door_x"]
	var dz: float = rm["door_z"]
	var lp := to_local(c, yaw, p)
	var lg := to_local(c, yaw, goal)
	var in_p := absf(lp.x) < half.x + 0.1 and absf(lp.y) < half.y + 0.1
	var in_g := absf(lg.x) < half.x and absf(lg.y) < half.y
	if in_p == in_g:
		return goal
	var lane := absf(lp.x - dx) < 0.75
	if in_g:
		if lane and lp.y > half.y - 0.4 and lp.y < dz + 1.8:
			return to_world(c, yaw, Vector2(dx, half.y - 1.0))
		return to_world(c, yaw, Vector2(dx, dz + 1.0))
	if lane and lp.y > half.y - 1.75:
		return to_world(c, yaw, Vector2(dx, dz + 1.0))
	return to_world(c, yaw, Vector2(dx, half.y - 1.0))

## The room record for a person who works in shop h.
static func room_rec(h: Dictionary) -> Dictionary:
	var rm := room(h["t"])
	return {"c": h["p"], "yaw": h["yaw"], "half": rm["half"], "door_x": rm["door_x"], "door_z": rm["door_z"]}

# --- Staff ---------------------------------------------------------------------------------

## Jobs that already fit a shop: whoever has one is hired first.
const FITS := {
	"armourer": ["smith", "runecarver", "engineer"], "weaponsmith": ["smith", "hunter", "warden", "security officer"],
	"apothecary": ["herbalist", "priest", "medic", "mystic"], "general": ["miller", "farmer", "beekeeper", "courier", "scavenger", "hydroponics tech"],
	"tavern": ["innkeeper", "bard"], "land": ["scribe", "data broker", "priest"],
}

## Hires a keeper for every shop that has none: someone whose work fits, else anyone who
## is not a guard or the stall trader, else a newcomer. Safe to call on every load.
## Returns true if it changed the settlement.
static func staff(gen: ChunkGenerator, site: Dictionary, data: Dictionary) -> bool:
	if int(data.get("shops_v", 0)) >= SHOPS_V:
		return false
	var shops := plan(gen, site)
	var era: int = site["era"]
	var npcs: Array = data["npcs"]
	var r := WHash.rng(gen.seed, site["sx"], site["sz"], 612)
	var guards := 0
	for p in npcs:
		if NPCGen.GUARD_JOBS.has(p["job"]):
			guards += 1
	for h in shops:
		if h["kind"] == "":
			continue
		var kind: String = h["kind"]
		var fits: Array = FITS.get(kind, [])
		var pick: Dictionary = {}
		for p in npcs:
			if not p.get("dead", false) and not p.has("shop_kind") and fits.has(p["job"]):
				pick = p
				break
		if pick.is_empty():
			for p in npcs:
				if p.get("dead", false) or p.has("shop_kind") or p["job"] == "trader":
					continue
				if NPCGen.GUARD_JOBS.has(p["job"]) and guards <= 1:
					continue
				pick = p
				break
		if pick.is_empty():
			pick = NPCGen.person(r, era, npcs.size(), site["sx"], site["sz"])
			npcs.append(pick)
		elif NPCGen.GUARD_JOBS.has(pick["job"]):
			guards -= 1
		hire(pick, h)
		var door := door_point(h)
		pick["pos"] = Vector3(door.x, gen.field.height(door.x, door.y), door.y)
	data["shops_v"] = SHOPS_V
	return true

## Makes rec the keeper of shop h: their job, their spot behind the counter, their room.
static func hire(rec: Dictionary, h: Dictionary) -> void:
	var kind: String = h["kind"]
	rec["shop_kind"] = kind
	rec["shop_i"] = int(h["i"])
	rec["shop_title"] = h["title"]
	rec["shop_label"] = h["label"]
	rec["job"] = job_of(kind, int(h["era"]), int(h["size"]))
	NPCSocial.ensure(rec)
	rec.erase("shop")
	var ft := fit(h["t"])
	var keeper: Vector2 = ft.get("keeper", Vector2(0, -0.5))
	var face: Vector2 = ft.get("face", Vector2(0, 1))
	rec["work"] = to_world(h["p"], h["yaw"], keeper)
	rec["work_yaw"] = float(h["yaw"]) + atan2(face.x, face.y)
	rec["room"] = room_rec(h)
	rec["home"] = door_point(h)
	NPCSocial.ensure(rec)
	rec["purse"] = maxi(int(rec["purse"]), 250 + int(float(rec["traits"]["greedy"]) * 400.0) + int(h["size"]) * 150)

## The shop record of the keeper rec, from the plan.
static func shop_of(gen: ChunkGenerator, site: Dictionary, rec: Dictionary) -> Dictionary:
	if not rec.has("shop_kind"):
		return {}
	var shops := plan(gen, site)
	var i := int(rec.get("shop_i", -1))
	if i < 0 or i >= shops.size():
		return {}
	return shops[i]

## The keeper's wares as an Economy trader state. guilds: the traveller's memberships.
## Prices lean on the keeper's greed and mood (NPCSocial.shop) and the traveller's guilds.
static func trade_state(rec: Dictionary, h: Dictionary, guilds: Dictionary) -> Dictionary:
	NPCSocial.ensure(rec)
	var kind: String = rec["shop_kind"]
	var era := int(rec["era"])
	if not rec.has("shop"):
		var r := RandomNumberGenerator.new()
		r.seed = hash(String(rec["id"])) ^ 0x5409
		var title: String = h.get("title", rec["name"])
		var st := {"era": era, "name": "%s · %s" % [title, rec["name"]], "foreign": 1.3 + r.randf() * 0.5,
			"stock": {}, "demand": {}, "last_day": 0.0, "restock_seed": r.randi(), "pool": pool_for(rec)}
		Economy._restock(st, 0)
		_fill(st)
		rec["shop"] = st
	var s: Dictionary = rec["shop"]
	# Wares added since the shop first opened (older saves) come in with the next restock.
	s["pool"] = pool_for(rec)
	var day := NPCMind.game_day()
	var cycle := int(floor(float(s["last_day"]) / Economy.RESTOCK_DAYS))
	Economy.tick(s, day)
	if int(floor(day / Economy.RESTOCK_DAYS)) != cycle:
		_fill(s)
	var t: Dictionary = rec["traits"]
	var rel := float(rec.get("rel", 0)) / 100.0
	s["purse"] = int(rec["purse"])
	var charge := clampf(1.0 + float(t["greedy"]) * 0.25 - rel * 0.2, 0.7, 1.4)
	var pay := clampf(0.85 - float(t["greedy"]) * 0.2 + rel * 0.15, 0.5, 1.0)
	for g in guilds:
		if not GUILDS.has(g):
			continue
		var fav: Array = GUILDS[g]["favours"]
		if fav.has("*"):
			charge *= ALL_DISCOUNT
			pay /= ALL_DISCOUNT
		elif fav.has(kind) or g == kind:
			charge *= GUILD_DISCOUNT
			pay /= GUILD_DISCOUNT
		if g == kind and GUILDS[g].get("fence", false):
			pay *= FENCE_BONUS
	s["charge_mult"] = charge
	s["pay_mult"] = pay
	return s

## Shops keep everything of their trade on the shelf: whatever the restock missed comes
## back too, a little short.
static func _fill(st: Dictionary) -> void:
	var stock: Dictionary = st["stock"]
	for t in st["pool"]:
		if ItemDB.def(t).is_empty():
			continue
		if not stock.has(t):
			stock[t] = 1 if not ItemDB.is_stackable(t) else 6
		elif ItemDB.is_stackable(t):
			stock[t] = maxi(int(stock[t]), 10)

# --- Guilds ---------------------------------------------------------------------------------

static func fee(kind: String, rec: Dictionary) -> int:
	var base := int(GUILDS[kind]["fee"])
	var rel := float(rec.get("rel", 0)) / 100.0
	return maxi(10, int(round(base * (1.0 - clampf(rel, 0.0, 0.6) * 0.5))))

# --- Houses for sale ------------------------------------------------------------------------

## Houses the land seller can sell: everything not a shop and not already yours.
## estates: the traveller's (Game.estates).
static func for_sale(gen: ChunkGenerator, site: Dictionary, estates: Array) -> Array:
	var out: Array = []
	for h in plan(gen, site):
		if h["kind"] != "" or owned(h, estates):
			continue
		out.append(h)
	return out

static func owned(h: Dictionary, estates: Array) -> bool:
	var p: Vector2 = h["p"]
	for e in estates:
		if String(e.get("sid", "")) == String(h["sid"]) and Vector2(e["x"], e["z"]).distance_to(p) < 0.5:
			return true
	return false

## What a house costs from a seller rec.
static func price(h: Dictionary, rec: Dictionary) -> int:
	var base: float = ROOMS[h["t"]][0]
	var mult: float = [0.7, 1.0, 1.4][int(h["size"])]
	var greed := float(rec.get("traits", {}).get("greedy", 0.5))
	var rel := float(rec.get("rel", 0)) / 100.0
	return int(round(base * mult * (0.9 + greed * 0.3 - clampf(rel, 0.0, 0.5) * 0.2) / 10.0)) * 10

## Which way a house lies from the square, in words.
static func where(h: Dictionary, c: Vector2) -> String:
	var d: Vector2 = (h["p"] as Vector2) - c
	var dirs := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var a := fposmod(d.angle(), TAU)
	return "%s, %d m %s of the square" % [String(h["t"]).capitalize(), int(d.length()), dirs[int(round(a / (TAU / 8.0))) % 8]]

## The estate record for a bought house.
static func estate(h: Dictionary, town: String, planet: int) -> Dictionary:
	var door := door_point(h)
	return {"sid": h["sid"], "x": (h["p"] as Vector2).x, "z": (h["p"] as Vector2).y, "t": h["t"], "town": town,
		"planet": planet, "dx": door.x, "dz": door.y}

## Moves anyone who lived in a house you bought into another house of the settlement.
static func rehome(gen: ChunkGenerator, site: Dictionary, data: Dictionary, estates: Array) -> void:
	var houses := plan(gen, site)
	var mine: Array = []
	var free: Array = []
	for h in houses:
		if owned(h, estates):
			mine.append(door_point(h))
		else:
			free.append(door_point(h))
	if mine.is_empty():
		return
	var c: Vector2 = site["center"]
	var n := 0
	for p in data["npcs"]:
		var home: Vector2 = p["home"]
		for d in mine:
			if home.distance_to(d) < 3.0:
				p["home"] = free[n % free.size()] if not free.is_empty() else c + Vector2(6, 0)
				n += 1
				break
	# Old homes (from NPCGen) sit 4.2 m out from the house centre towards the square.
	for p in data["npcs"]:
		var home: Vector2 = p["home"]
		for h in houses:
			if owned(h, estates):
				var hp: Vector2 = h["p"]
				if home.distance_to(hp + (c - hp).normalized() * 4.2) < 1.0:
					p["home"] = free[n % free.size()] if not free.is_empty() else c + Vector2(6, 0)
					n += 1

# --- Talk -----------------------------------------------------------------------------------

## What a keeper says when you walk up.
static func greeting(rec: Dictionary, h: Dictionary) -> String:
	var kind: String = rec["shop_kind"]
	var title: String = h.get("title", "")
	var e := int(rec["era"])
	var hsh := absi(hash(String(rec["id"])))
	if is_guild(kind):
		return ["Welcome to %s. Members are always welcome; others may join.", "This is the hall of %s. Looking to sign up?", "%s. Speak your business."][hsh % 3] % title
	if kind == "land":
		return [["Looking to settle? I handle the deeds for houses hereabouts.", "Houses for sale, traveller. Fair prices, sound roofs."],
			["The grove has room for one more. I can grant you a home.", "Seeking a place to put down roots? Literally, I mean."],
			["Need a hab? I've leases on vacant units.", "Registry's open. Looking to buy property?"]][e][hsh % 2]
	return ["Welcome to %s! Have a look around.", "%s, at your service. What can I get you?", "Come in, come in. Best wares in town, here at %s."][hsh % 3] % title

## The language model's line about the keeper's work.
static func prompt_line(rec: Dictionary) -> String:
	var kind: String = rec["shop_kind"]
	var era := int(rec["era"])
	var title: String = rec.get("shop_title", "")
	var label: String = rec.get("shop_label", "")
	if kind == "land":
		return "You are the %s at %s and sell houses in town to settlers. If the traveller wants a house, land or a home, use action \"buy_house\" to show them what is for sale." % [rec["job"], label]
	var names: PackedStringArray = []
	for t in goods_of(kind, era):
		if not ItemDB.def(t).is_empty():
			names.append(ItemDB.def(t)["name"])
	if is_guild(kind):
		var g: Dictionary = GUILDS[kind]
		return "You are the %s of %s, a hall of the %s. Joining costs %d Marks; %s Members can buy the guild's goods (%s). If the traveller wants to join, use action \"join_guild\"; if they want to buy, use \"trade\"." % [rec["job"], title, label, int(g["fee"]), g["perk"], ", ".join(names)]
	return "You keep %s, the %s in town, and gladly trade: you sell %s." % [title, label.to_lower(), ", ".join(names)]

## What a guild's keeper says about joining.
static func pitch(rec: Dictionary) -> String:
	var g: Dictionary = GUILDS[rec["shop_kind"]]
	return "The %s takes anyone who can pay the %d Marks. %s" % [g["label"], fee(rec["shop_kind"], rec), g["perk"]]
