class_name Stats
extends RefCounted
## The player's level, experience and attributes. Every level grants points to spend on
## five attributes, and the attributes shape the body: health, stamina, strength of
## blows and how much you can carry, speed, breath and how fast you learn. Skills
## (sneaking, pickpocketing, lockpicking) take the same points and also grow with practice,
## the way thieves' skills do in other open-world games. Pure data so it can be saved and tested.

const MAX_LEVEL := 100
const POINTS_PER_LEVEL := 3
const ATTRS := ["str", "end", "agi", "oxy", "int"]
const NAMES := {"str": "Strength", "end": "Endurance", "agi": "Agility", "oxy": "Oxygen", "int": "Intellect"}
const BLURBS := {
	"str": "+6% damage and harvesting, +50 kg carry weight per point",
	"end": "+10 health and +8 stamina per point",
	"agi": "+3% move speed and +3% swing speed per point",
	"oxy": "+5 seconds of breath underwater per point",
	"int": "+5% experience and +1% crafted quality per point",
}
const BASE_HEALTH := 100.0
const BASE_STAMINA := 100.0
const BASE_CARRY := 600.0 ## kg you can carry before you slow down
const CARRY_PER_STR := 50.0 ## extra kg per point of strength
const BASE_BREATH := 30.0 ## seconds underwater

## Skills: points raise them one level each, and doing the thing earns practice that
## raises them too. They top out at SKILL_MAX.
const SKILLS := ["sneak", "pick", "lock"]
const SKILL_NAMES := {"sneak": "Sneaking", "pick": "Pickpocketing", "lock": "Lockpicking"}
const SKILL_BLURBS := {
	"sneak": "Crouch [crouch] to sneak: people notice you 1.5% less per level",
	"pick": "Crouch behind someone and [interact] to pick their pockets: +1.5% chance per level",
	"lock": "Pick the locks on chests in town: the sweet spot is 3% wider and picks last longer per level",
}
const SKILL_MAX := 50

var level := 1
var xp := 0 ## progress inside the current level
var points := 0
var attrs := {"str": 0, "end": 0, "agi": 0, "oxy": 0, "int": 0}
var skills := {"sneak": 0, "pick": 0, "lock": 0}
var skill_xp := {"sneak": 0.0, "pick": 0.0, "lock": 0.0} ## practice toward the next level

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

## Spends a point on a skill (one level).
func spend_skill(sk: String) -> bool:
	if points <= 0 or not skills.has(sk) or skills[sk] >= SKILL_MAX:
		return false
	skills[sk] += 1
	skill_xp[sk] = 0.0
	points -= 1
	return true

## Practice needed to raise a skill from level n.
static func practice_to_next(n: int) -> float:
	return 12.0 + 6.0 * float(n)

## Practice from doing the thing. Returns how many levels the skill gained.
func practice(sk: String, amount: float) -> int:
	if not skills.has(sk) or amount <= 0.0 or skills[sk] >= SKILL_MAX:
		return 0
	skill_xp[sk] = float(skill_xp[sk]) + amount * xp_mult()
	var gained := 0
	while skills[sk] < SKILL_MAX and float(skill_xp[sk]) >= practice_to_next(skills[sk]):
		skill_xp[sk] = float(skill_xp[sk]) - practice_to_next(skills[sk])
		skills[sk] += 1
		gained += 1
	if skills[sk] >= SKILL_MAX:
		skill_xp[sk] = 0.0
	return gained

## How easily people notice you (1 = standing in the open). Crouching more than halves
## it, and every level of Sneaking takes a little more off.
func notice_mult(crouched: bool) -> float:
	return (0.45 if crouched else 1.0) * (1.0 - 0.015 * skills["sneak"])

## Chance to lift something from a pocket. `worth` is its value in Marks; `behind`
## when they face away from you; `aware` 0..1 how alert they already are.
func pickpocket_chance(worth: float, behind: bool, aware: float) -> float:
	var c: float = 0.45 + 0.015 * skills["pick"] + (0.15 if behind else -0.15) - 0.25 * aware - clampf(worth / 160.0, 0.0, 0.4)
	return clampf(c, 0.05, 0.95)

## What worn trinkets and timed effects add (Effects.bonus); set by Game, not saved.
var bonus := {}

func _b(k: String) -> float:
	return float(bonus.get(k, 0.0))

func max_health() -> float:
	return BASE_HEALTH + 10.0 * attrs["end"] + _b("health")

func max_stamina() -> float:
	return BASE_STAMINA + 8.0 * attrs["end"] + _b("stamina")

func damage_mult() -> float:
	return 1.0 + 0.06 * attrs["str"] + _b("damage")

func speed_mult() -> float:
	return 1.0 + 0.03 * attrs["agi"] + _b("speed")

## Swings come round faster: the cooldown between them is divided by this.
func swing_mult() -> float:
	return 1.0 + 0.03 * attrs["agi"] + _b("swing")

func carry_capacity() -> float:
	return BASE_CARRY + CARRY_PER_STR * attrs["str"] + _b("carry")

## How fast stamina refills (1 = normal).
func stamina_regen_mult() -> float:
	return 1.0 + _b("stamina_regen")

func max_breath() -> float:
	return BASE_BREATH + 5.0 * attrs["oxy"]

func xp_mult() -> float:
	return 1.0 + 0.05 * attrs["int"] + _b("xp")

func craft_quality_mult() -> float:
	return 1.0 + 0.01 * attrs["int"]

func to_data() -> Dictionary:
	return {"level": level, "xp": xp, "points": points, "attrs": attrs.duplicate(), "skills": skills.duplicate(), "skill_xp": skill_xp.duplicate()}

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
		var sk = d.get("skills", {})
		var sx = d.get("skill_xp", {})
		for k in SKILLS:
			s.skills[k] = clampi(int(sk.get(k, 0)) if sk is Dictionary else 0, 0, SKILL_MAX)
			s.skill_xp[k] = maxf(0.0, float(sx.get(k, 0.0)) if sx is Dictionary else 0.0)
	return s
