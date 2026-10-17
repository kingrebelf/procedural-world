class_name Rarity
## Ranks for gear (tools, weapons, armour): Common to Mythic. Higher ranks hit harder
## and carry special abilities (affixes), each with its own glow on the model and icon.

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHIC }
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const COLORS := [Color(0.62, 0.62, 0.62), Color(0.35, 0.85, 0.3), Color(0.3, 0.6, 1.0),
	Color(1.0, 0.58, 0.15), Color(1.0, 0.22, 0.2), Color(0.72, 0.35, 1.0)]
## Chance weights of each rank before luck.
const WEIGHTS := [60.0, 25.0, 10.0, 3.5, 1.2, 0.3]

## Abilities. "kinds" says which gear can carry it: melee, ranged, tool, armor.
const AFFIXES := {
	"keen": {"name": "Keen", "desc": "20% chance to strike critically for double damage", "kinds": ["melee", "ranged"], "color": Color(1.0, 0.9, 0.6)},
	"vampiric": {"name": "Vampiric", "desc": "Heals you for 8% of the damage dealt", "kinds": ["melee", "ranged"], "color": Color(0.85, 0.1, 0.2)},
	"shock": {"name": "Storm", "desc": "Hits arc to everything within 3 m", "kinds": ["melee", "ranged"], "color": Color(0.4, 0.75, 1.0)},
	"swift": {"name": "Swift", "desc": "Swings and fires 25% faster", "kinds": ["melee", "ranged", "tool"], "color": Color(0.5, 1.0, 0.75)},
	"brutal": {"name": "Brutal", "desc": "+30% damage", "kinds": ["melee", "ranged"], "color": Color(1.0, 0.45, 0.15)},
	"reach": {"name": "Far-reaching", "desc": "+40% range", "kinds": ["melee", "ranged", "tool"], "color": Color(0.8, 0.8, 1.0)},
	"prospector": {"name": "Prospector's", "desc": "Mines and chops 50% faster", "kinds": ["tool"], "color": Color(1.0, 0.8, 0.3)},
	"bountiful": {"name": "Bountiful", "desc": "25% chance of double yields", "kinds": ["tool"], "color": Color(0.5, 0.95, 0.4)},
	"featherweight": {"name": "Featherweight", "desc": "Weighs almost nothing", "kinds": ["melee", "ranged", "tool", "armor"], "color": Color(0.9, 0.95, 1.0)},
	"warding": {"name": "Warding", "desc": "+15% armour", "kinds": ["armor"], "color": Color(0.6, 0.8, 1.0)},
	"thorns": {"name": "Thorned", "desc": "Attackers take 25% of the damage back", "kinds": ["armor"], "color": Color(0.5, 0.75, 0.25)},
	"mending": {"name": "Mending", "desc": "Slowly restores health", "kinds": ["armor"], "color": Color(0.95, 0.4, 0.6)},
}

## Gear can roll a rank; resources and food cannot.
static func is_gear(type: String) -> bool:
	var k: String = ItemDB.def(type).get("kind", "")
	return k == "tool" or k == "weapon" or k == "armor"

## What abilities this type of gear can carry.
static func gear_kind(type: String) -> String:
	var d := ItemDB.def(type)
	match String(d.get("kind", "")):
		"weapon": return "ranged" if d.get("ranged", false) else "melee"
		"armor": return "armor"
	return "tool"

## The item's rank. Items from before ranks existed take one from their quality.
static func of(item: Dictionary) -> int:
	if item.has("rarity"):
		return int(item["rarity"])
	if not is_gear(String(item.get("type", ""))):
		return COMMON
	var q: float = item.get("quality", 1.0)
	return RARE if q >= 1.4 else (UNCOMMON if q >= 1.25 else COMMON)

static func color(item: Dictionary) -> Color:
	return COLORS[of(item)]

## Rolls a rank; `luck` from 0 (a roadside chest) to 1 (the depths of a dungeon) moves
## the odds towards the top ranks.
static func roll(rng: RandomNumberGenerator, luck := 0.0) -> int:
	var w: Array = []
	var total := 0.0
	for i in WEIGHTS.size():
		var x: float = WEIGHTS[i] * pow(1.0 + 3.0 * luck, i * 0.9) * (1.0 - 0.6 * luck if i == 0 else 1.0)
		w.append(x)
		total += x
	var pick := rng.randf() * total
	for i in w.size():
		pick -= w[i]
		if pick <= 0.0:
			return i
	return MYTHIC

## Gives a gear item its rank, abilities and name. Rare gets one ability, each rank
## above adds one more.
static func apply(item: Dictionary, rank: int, rng: RandomNumberGenerator) -> void:
	var t: String = item["type"]
	if not is_gear(t):
		return
	item["rarity"] = rank
	var pool: Array = []
	var gk := gear_kind(t)
	for id in AFFIXES:
		if gk in AFFIXES[id]["kinds"]:
			pool.append(id)
	var picks: Array = []
	for n in maxi(0, rank - 1):
		if pool.is_empty():
			break
		var id: String = pool[rng.randi() % pool.size()]
		pool.erase(id)
		picks.append(id)
	item["affixes"] = picks
	var base: String = ItemDB.def(t)["name"]
	if rank >= EPIC and not picks.is_empty():
		item["name"] = "%s %s of %s" % [AFFIXES[picks[0]]["name"], base, ItemDB.NAME_PARTS[rng.randi() % ItemDB.NAME_PARTS.size()]]
	elif rank >= RARE and not picks.is_empty():
		item["name"] = "%s %s" % [AFFIXES[picks[0]]["name"], base]
	else:
		item["name"] = ""

static func has_affix(item, id: String) -> bool:
	return item is Dictionary and id in item.get("affixes", [])

## Damage multiplier from the rank alone.
static func power(item: Dictionary) -> float:
	return 1.0 + 0.12 * of(item)

## The colour the item's ability glows with: its first ability, else its rank's colour.
static func glow(item: Dictionary) -> Color:
	var a: Array = item.get("affixes", [])
	if not a.is_empty() and AFFIXES.has(a[0]):
		return AFFIXES[a[0]]["color"]
	return color(item)

## Lines for the tooltip.
static func describe(item: Dictionary) -> Array:
	var out: Array = []
	for id in item.get("affixes", []):
		if AFFIXES.has(id):
			out.append("%s: %s" % [AFFIXES[id]["name"], AFFIXES[id]["desc"]])
	return out
