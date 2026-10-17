class_name NPCSocial
## Money, gifts, loans, gear and personal trade between people and the traveller.
## Everyone carries a purse and a few goods from their trade, wears what they own (guards
## start in their era's armour) and puts on armour you give them. How generous, greedy or
## touchy they are comes from their personality and how they feel about you.
##
## All of it lives in the person's persisted record:
##   purse: int, debt: int (what you owe them), debt_due: float (day), gear: {slot: item},
##   held: item or null, gift_day: int, shop: an Economy trader state for their goods.

## What each trade has to sell.
const JOB_GOODS := {
	"farmer": ["bread", "wild_berries", "fiber", "apple", "potato", "carrot", "onion", "cabbage", "wheat", "egg", "milk", "pumpkin", "corn", "pear", "grapes"],
	"smith": ["iron_ingot", "lockpick", "sword_iron", "pickaxe_iron", "hammer", "helm_iron", "iron_nails", "coal", "tongs", "bronze_ingot", "steel_ingot"],
	"guard": ["sword_iron", "shield_wood", "crossbow", "bolt", "bandage_linen", "falchion", "shield_kite"], "innkeeper": ["bread", "cooked_meat", "health_potion", "mead", "wine", "ham", "sausage"],
	"hunter": ["hide", "raw_meat", "longbow", "arrow", "dagger", "fur_pelt", "shortbow", "broadhead_arrows", "skinning_knife", "salted_meat"],
	"priest": ["health_potion", "silver_chalice", "holy_water", "candle", "amulet_saint", "book_leather"],
	"weaver": ["fiber", "boots_leather", "gloves_leather", "cloth", "wool", "flax", "rope", "tunic_padded", "trousers_wool"],
	"miller": ["bread", "planks", "flour", "wheat"],
	"herbalist": ["glowberry", "glowroot", "health_potion", "stamina_potion", "herb_red", "herb_blue", "herb_yellow", "herb_mint", "salve", "potion_health_minor"], "warden": ["longbow", "arrow", "boots_elven", "spear"],
	"runecarver": ["rune_tablet", "bracers_rune", "aether_crystal"], "bard": ["glowberry", "moonpearl", "lute", "flute", "wine", "dice"],
	"mystic": ["aether_crystal", "moonpearl", "stamina_potion"], "beekeeper": ["glowberry", "wild_berries", "honey", "beeswax", "candle", "mead"],
	"lamplighter": ["torch", "glowroot", "lamp_oil", "candle", "hand_lantern", "tinderbox"],
	"scribe": ["rune_tablet", "binoculars", "scroll_plain", "quill_ink", "book_leather", "letter_sealed"],
	"engineer": ["circuitry", "lockpick", "power_cell", "alloy_plate"], "medic": ["health_potion", "ration_pack", "stamina_potion"],
	"scavenger": ["alloy_scrap", "lockpick", "scrap_pistol", "data_core"], "pilot": ["power_cell", "flashlight", "ration_pack"],
	"security officer": ["pulse_pistol", "rounds", "helm_visor"], "data broker": ["data_core", "circuitry"],
	"hydroponics tech": ["ration_pack", "fiber"], "courier": ["ration_pack", "power_cell", "binoculars"],
}

## What guards wear on duty, by era.
const GUARD_GEAR := [
	{"head": "helm_iron", "chest": "mail_iron", "feet": "boots_leather", "shield": "shield_wood"},
	{"head": "helm_elven", "chest": "plate_mythril", "feet": "boots_elven"},
	{"head": "helm_visor", "chest": "exo_chest", "legs": "exo_legs", "feet": "mag_boots"},
]

static func _rng(rec: Dictionary, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(rec["id"])) ^ (salt * 7919)
	return r

## Fills in anything an older save is missing. Safe to call every time.
static func ensure(rec: Dictionary) -> void:
	# Trading spends from the shop's copy of the purse; take it back.
	if rec.has("shop") and rec["shop"].has("purse"):
		rec["purse"] = int(rec["shop"]["purse"])
	if not rec.has("purse"):
		var r := _rng(rec, 1)
		var rich := 1.0 + float(rec["traits"]["greedy"]) * 1.5 + (2.0 if rec["job"] == "trader" else 0.0)
		rec["purse"] = int(r.randi_range(8, 60) * rich)
	if not rec.has("debt"):
		rec["debt"] = 0
		rec["debt_due"] = 0.0
	if not rec.has("gear"):
		var gear := {}
		if NPCGen.GUARD_JOBS.has(rec["job"]):
			var g: Dictionary = GUARD_GEAR[clampi(int(rec["era"]), 0, 2)]
			for slot in g:
				gear[slot] = {"type": g[slot], "qty": 1, "quality": 1.0}
		rec["gear"] = gear
	if not rec.has("level") and rec.get("pos", Vector3.ZERO) is Vector3 and rec.get("pos", Vector3.ZERO) != Vector3.ZERO:
		rec["level"] = level_for(rec)
		# Health grows with the level; keep how hurt they already were.
		rec["hp"] = float(rec.get("hp", 100.0)) / 100.0 * max_hp(rec)

# --- Level -------------------------------------------------------------------------------------

## A person's level: the zone level where they live (Eras.zone_level, one more every 150 m
## out on themed worlds), townsfolk a little under it, guards a few above the townsfolk
## around them, and tradesfolk who fight for a living (smiths, hunters) a touch above.
static func level_for(rec: Dictionary) -> int:
	var p: Vector3 = rec["pos"]
	var zone := Eras.zone_level(p.x, p.z)
	var h := absi(hash(String(rec["id"]) + "level"))
	var lv := zone - 2 + h % 3
	if NPCGen.GUARD_JOBS.has(rec["job"]):
		lv = zone + 3 + h % 3
	elif rec["job"] in ["smith", "hunter", "scavenger", "engineer"]:
		lv += 1
	return clampi(lv, 1, 99)

static func level(rec: Dictionary) -> int:
	return int(rec.get("level", 1))

## Full health at their level: 100 at level 1, +12% a level (as for wild animals).
static func max_hp(rec: Dictionary) -> float:
	return 100.0 * (1.0 + 0.12 * (level(rec) - 1))

## How hard they hit compared with a level 1 person: +4% a level (as for wild animals).
static func hit_mult(rec: Dictionary) -> float:
	return 1.0 + 0.04 * (level(rec) - 1)

static func _set_purse(rec: Dictionary, v: int) -> void:
	rec["purse"] = v
	if rec.has("shop"):
		rec["shop"]["purse"] = v

static func day() -> int:
	return NPCMind.day_num()

# --- Money -----------------------------------------------------------------------------------

## How much this person would hand over when asked: "beg" (a gift) or "lend" (a loan).
## 0 means no. `asked` <= 0 lets them choose.
static func will_give(rec: Dictionary, kind: String, asked: int = 0) -> int:
	ensure(rec)
	var t: Dictionary = rec["traits"]
	var rel := float(rec.get("rel", 0))
	var purse := int(rec["purse"])
	if purse <= 0 or rel < -10.0:
		return 0
	if kind == "lend" and int(rec["debt"]) > 0:
		return 0 # not until you pay back what you owe
	var warmth := float(t["friendly"]) * 0.6 + rel / 100.0 - float(t["greedy"]) * 0.7
	if kind == "lend":
		warmth += 0.25 + float(t["greedy"]) * 0.3 # a loan pays back
	if rec.get("mood", "") in ["happy"]:
		warmth += 0.15
	elif rec.get("mood", "") in ["angry", "wary"]:
		warmth -= 0.3
	if warmth < 0.15:
		return 0
	var share := clampf(warmth, 0.0, 1.0) * (0.15 if kind == "beg" else 0.6)
	var most := maxi(1, int(purse * share))
	return mini(most, asked) if asked > 0 else most

## The traveller is given `amount` Marks. Debts are settled first. Returns
## {repaid, rel, line} (line: a fitting thing to say).
static func receive_marks(rec: Dictionary, amount: int) -> Dictionary:
	ensure(rec)
	var repaid := mini(amount, int(rec["debt"]))
	rec["debt"] = int(rec["debt"]) - repaid
	_set_purse(rec, int(rec["purse"]) + amount)
	var gift := amount - repaid
	var rel := 0
	if gift > 0:
		var worth := float(gift) / (10.0 + float(rec["purse"]) * 0.2)
		rel = clampi(int(round(worth * (8.0 + float(rec["traits"]["greedy"]) * 8.0))) + 1, 1, 15)
	NPCMind.change_rel(rec, rel)
	var line := ""
	if repaid > 0 and int(rec["debt"]) == 0:
		line = "That settles what you owed me. Thank you."
		NPCMind.remember(rec, "The traveller paid back their debt of %d Marks." % repaid)
		NPCMind.change_rel(rec, 3)
	elif repaid > 0:
		line = "That's %d back. You still owe me %d." % [repaid, rec["debt"]]
	if gift > 0:
		NPCMind.remember(rec, "The traveller gave me %d Marks." % gift)
		line += (" " if line != "" else "") + (["For me? You're too kind!", "Well! That's generous of you.", "I won't say no to that."][int(rec["purse"]) % 3] if rel >= 3 else "Oh. Thank you, I suppose.")
	return {"repaid": repaid, "rel": rel, "line": line}

## This person hands the traveller `amount` (already decided). kind: "beg" or "lend".
static func hand_over(rec: Dictionary, amount: int, kind: String) -> int:
	ensure(rec)
	amount = clampi(amount, 0, int(rec["purse"]))
	if amount <= 0:
		return 0
	_set_purse(rec, int(rec["purse"]) - amount)
	if kind == "lend":
		rec["debt"] = int(rec["debt"]) + amount
		rec["debt_due"] = NPCMind.game_day() + 3.0
		NPCMind.remember(rec, "Lent the traveller %d Marks; they promised to repay within three days." % amount)
	else:
		NPCMind.remember(rec, "Gave the traveller %d Marks." % amount)
	return amount

## True once a loan is overdue.
static func overdue(rec: Dictionary) -> bool:
	return int(rec.get("debt", 0)) > 0 and NPCMind.game_day() > float(rec.get("debt_due", 0.0))

# --- Items -------------------------------------------------------------------------------------

## The traveller gives this person an item. Returns {use: "wear"|"hold"|"eat"|"keep",
## slot, rel, line}. Armour goes on (and shows); a weapon or tool goes in hand; food
## gets eaten.
static func receive_item(rec: Dictionary, item: Dictionary) -> Dictionary:
	ensure(rec)
	var d := ItemDB.def(item["type"])
	var kind: String = d.get("kind", "")
	var value := float(d.get("value", 1)) * float(item.get("qty", 1))
	var likes := String(rec.get("likes", "")).to_lower()
	var name := ItemDB.display_name(item)
	var out := {"use": "keep", "slot": "", "rel": 0, "line": ""}
	var rel := clampi(int(round(sqrt(value) * (0.6 + float(rec["traits"]["greedy"]) * 0.6))) + 1, 1, 20)
	for w in name.to_lower().split(" "):
		if w.length() > 3 and likes.contains(w):
			rel += 6
	out["rel"] = rel
	NPCMind.change_rel(rec, rel)
	NPCMind.remember(rec, "The traveller gave me %s." % name)
	if kind == "armor":
		var slot: String = d.get("slot", "chest")
		var gear: Dictionary = rec["gear"]
		gear[slot] = item.duplicate(true)
		out["use"] = "wear"
		out["slot"] = slot
		out["line"] = ["Let me put it on. How do I look?", "It fits! I'll wear it proudly.", "Armour? I feel safer already."][hash(name) % 3]
	elif kind in ["weapon", "tool"]:
		rec["held"] = item.duplicate(true)
		out["use"] = "hold"
		out["line"] = "A fine %s. I'll keep it close." % name.to_lower()
	elif kind == "food" or String(item["type"]).ends_with("potion"):
		out["use"] = "eat"
		out["line"] = ["Don't mind if I do.", "Mm, thank you.", "I was getting hungry."][hash(name) % 3]
	else:
		out["line"] = "%s? Thank you, I'll treasure it." % name
	return out

## A small present this person might give someone they're fond of: {marks} or {item}.
static func gift_for(rec: Dictionary) -> Dictionary:
	ensure(rec)
	var goods: Array = JOB_GOODS.get(rec["job"], [])
	var r := _rng(rec, day())
	if not goods.is_empty() and r.randf() < 0.6:
		return {"item": ItemDB.make(goods[r.randi() % goods.size()], 1, 1.0, {})}
	return {"marks": maxi(1, mini(int(rec["purse"]) / 4, r.randi_range(3, 15)))}

# --- Pockets --------------------------------------------------------------------------------

## Small things anyone might carry, by era, besides the goods of their trade.
const POCKET_BITS := [["bread", "wild_berries", "torch", "dungeon_key", "silver_chalice", "health_potion", "lockpick", "apple",
		"candle", "dice", "bandage_linen", "letter_sealed", "sausage"],
	["glowberry", "bread", "moonpearl", "rune_tablet", "health_potion", "aether_crystal"],
	["ration_pack", "power_cell", "data_core", "stamina_potion", "circuitry", "health_potion", "lockpick"]]
const POCKETS_EVERY := 3 ## days before their pockets fill again

## What this person carries that a quick hand could lift (not their purse, not worn gear).
## Fills again every few days.
static func pockets(rec: Dictionary) -> Array:
	ensure(rec)
	var cycle := day() / POCKETS_EVERY
	if int(rec.get("pockets_cycle", -1)) != cycle or not rec.get("pockets") is Array:
		var r := _rng(rec, 31 + cycle)
		var out: Array = []
		var goods: Array = JOB_GOODS.get(rec["job"], [])
		var bits: Array = POCKET_BITS[clampi(int(rec["era"]), 0, 2)]
		for i in r.randi_range(1, 3):
			var t: String = goods[r.randi() % goods.size()] if not goods.is_empty() and r.randf() < 0.55 else bits[r.randi() % bits.size()]
			if not ItemDB.has(t) or ItemDB.def(t).get("kind", "") in ["armor", "vehicle"]:
				continue
			var stack := ItemDB.is_stackable(t)
			out.append(ItemDB.make(t, r.randi_range(1, 4) if stack else 1, 1.0, {"how": "stolen", "era": int(rec["era"])}))
		rec["pockets"] = out
		rec["pockets_cycle"] = cycle
	return rec["pockets"]

## Takes Marks out of someone's purse without asking. Returns what was taken.
static func lift_marks(rec: Dictionary, amount: int) -> int:
	ensure(rec)
	amount = clampi(amount, 0, int(rec["purse"]))
	_set_purse(rec, int(rec["purse"]) - amount)
	return amount

# --- Trading ----------------------------------------------------------------------------------

## The person's goods as a trader state for Economy and the trade window. Prices lean
## on greed and how they feel about you; they can only pay out of their own purse.
static func shop(rec: Dictionary) -> Dictionary:
	ensure(rec)
	if not rec.has("shop"):
		var r := _rng(rec, 2)
		var st := {"era": int(rec["era"]), "name": rec["name"], "foreign": 1.4 + r.randf() * 0.6,
			"stock": {}, "demand": {}, "last_day": 0.0, "restock_seed": r.randi(), "pool": JOB_GOODS.get(rec["job"], [])}
		Economy._restock(st, 0)
		rec["shop"] = st
	var s: Dictionary = rec["shop"]
	Economy.tick(s, NPCMind.game_day())
	var t: Dictionary = rec["traits"]
	var rel := float(rec.get("rel", 0)) / 100.0
	s["purse"] = int(rec["purse"])
	s["charge_mult"] = clampf(1.0 + float(t["greedy"]) * 0.35 - rel * 0.3, 0.6, 1.6)
	s["pay_mult"] = clampf(0.75 - float(t["greedy"]) * 0.25 + rel * 0.25, 0.35, 1.0)
	return s
