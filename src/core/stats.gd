class_name Stats
extends RefCounted
## The player's level, experience and attributes. Every level grants points to spend on
## four attributes, and the attributes shape the body: health, stamina, strength of
## blows, speed and how fast you learn. Pure data so it can be saved and tested.

const MAX_LEVEL := 100
const POINTS_PER_LEVEL := 3
const ATTRS := ["str", "end", "agi", "int"]
const NAMES := {"str": "Strength", "end": "Endurance", "agi": "Agility", "int": "Intellect"}
const BLURBS := {
	"str": "+6% damage and harvesting speed per point",
	"end": "+10 health and +8 stamina per point",
	"agi": "+2% move speed and -3% stamina use per point",
	"int": "+5% experience and +1% crafted quality per point",
}
const BASE_HEALTH := 100.0
const BASE_STAMINA := 100.0

var level := 1
var xp := 0 ## progress inside the current level
var points := 0
var attrs := {"str": 0, "end": 0, "agi": 0, "int": 0}

## Experience needed to go from level n to n + 1.
static func xp_to_next(n: int) -> int:
	return int(round(80.0 * pow(float(n), 1.45)))

## Adds experience (scaled by Intellect). Returns how many levels were gained.
func add_xp(amount: float) -> int:
	if level >= MAX_LEVEL or amount <= 0.0:
		return 0
	xp += maxi(1, int(round(amount * xp_mult())))
	var gained := 0
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		points += POINTS_PER_LEVEL
		gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	return gained

func spend(attr: String) -> bool:
	if points <= 0 or not attrs.has(attr):
		return false
	attrs[attr] += 1
	points -= 1
	return true

func max_health() -> float:
	return BASE_HEALTH + 10.0 * attrs["end"]

func max_stamina() -> float:
	return BASE_STAMINA + 8.0 * attrs["end"]

func damage_mult() -> float:
	return 1.0 + 0.06 * attrs["str"]

func speed_mult() -> float:
	return 1.0 + 0.02 * attrs["agi"]

func stamina_cost_mult() -> float:
	return maxf(0.35, 1.0 - 0.03 * attrs["agi"])

func xp_mult() -> float:
	return 1.0 + 0.05 * attrs["int"]

func craft_quality_mult() -> float:
	return 1.0 + 0.01 * attrs["int"]

func to_data() -> Dictionary:
	return {"level": level, "xp": xp, "points": points, "attrs": attrs.duplicate()}

static func from_data(d) -> Stats:
	var s := Stats.new()
	if d is Dictionary:
		s.level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
		s.xp = maxi(0, int(d.get("xp", 0)))
		s.points = maxi(0, int(d.get("points", 0)))
		var a = d.get("attrs", {})
		if a is Dictionary:
			for k in ATTRS:
				s.attrs[k] = maxi(0, int(a.get(k, 0)))
	return s
