class_name Effects
## What food, potions, scrolls, instruments and trinkets do to you. Timed effects (buffs)
## are {id: seconds left} in Game.buffs; worn trinkets carry a "bonus" in ItemDB. Both
## add up into Stats.bonus. Pure functions (no autoloads), so tests can call them.

## Timed effects. "bonus" keys: health, stamina (max), damage, speed, swing, xp (added to
## the multiplier), carry (kg), armor, regen (health per second), stamina_regen (added to
## the refill multiplier). "dot": health lost per second. "bad": a harm, not a blessing.
const BUFFS := {
	"courage": {"name": "Courage", "desc": "+15% damage", "bonus": {"damage": 0.15}},
	"strength": {"name": "Strength", "desc": "+25% damage, +100 kg carry", "bonus": {"damage": 0.25, "carry": 100.0}},
	"swift": {"name": "Swiftness", "desc": "+15% speed and swing", "bonus": {"speed": 0.15, "swing": 0.15}},
	"warded": {"name": "Warded", "desc": "+15 armour", "bonus": {"armor": 15.0}},
	"vigor": {"name": "Vigour", "desc": "Stamina refills twice as fast", "bonus": {"stamina_regen": 1.0}},
	"hardy": {"name": "Warmed", "desc": "+30 max stamina", "bonus": {"stamina": 30.0}},
	"refreshed": {"name": "Refreshed", "desc": "Stamina refills 60% faster", "bonus": {"stamina_regen": 0.6}},
	"nightsight": {"name": "Night-eye", "desc": "See in the dark", "bonus": {}},
	"immune": {"name": "Purged", "desc": "Immune to poison", "bonus": {}},
	"inspired": {"name": "Inspired", "desc": "+15% experience", "bonus": {"xp": 0.15}},
	"rested": {"name": "Well rested", "desc": "+10% experience, stamina refills faster", "bonus": {"xp": 0.1, "stamina_regen": 0.25}},
	"quenched": {"name": "Quenched", "desc": "Not thirsty", "bonus": {}, "hidden": true},
	"poison": {"name": "Poisoned", "desc": "Losing health", "bonus": {}, "dot": 1.0, "bad": true},
}
## Health a "regen" pool gives back per second.
const REGEN_RATE := 2.0
## Seconds of poison from a bad meal.
const SICK_SECS := 15.0

## Everything adding to your stats: worn trinkets and armour bonuses, then timed effects.
static func bonus(equipment: Dictionary, buffs: Dictionary) -> Dictionary:
	var out := {}
	for k in equipment:
		var it = equipment[k]
		if it is Dictionary:
			_add(out, ItemDB.def(String(it.get("type", ""))).get("bonus", {}))
	for id in buffs:
		if BUFFS.has(id):
			_add(out, BUFFS[id]["bonus"])
	return out

static func _add(out: Dictionary, b: Dictionary) -> void:
	for k in b:
		out[k] = float(out.get(k, 0.0)) + float(b[k])

## One second's worth of timed effects passing: returns the ids that ran out.
static func tick(buffs: Dictionary, delta: float) -> Array:
	var gone: Array = []
	for id in buffs.keys():
		buffs[id] = float(buffs[id]) - delta
		if buffs[id] <= 0.0:
			buffs.erase(id)
			gone.append(id)
	return gone

## Health lost per second to harmful effects.
static func damage_per_sec(buffs: Dictionary) -> float:
	var d := 0.0
	for id in buffs:
		d += float(BUFFS.get(id, {}).get("dot", 0.0))
	return d

## True when eating or drinking this would do something for you right now.
static func useful(d: Dictionary, health: float, max_health: float, stamina: float, max_stamina: float, buffs: Dictionary) -> bool:
	if d.has("buff") or d.get("cure", false) and buffs.has("poison"):
		return true
	if (d.get("stamina", false) or d.has("stamina_add")) and stamina < max_stamina:
		return true
	if (d.has("heal") and int(d["heal"]) > 0 or d.has("regen")) and health < max_health:
		return true
	return false

## A clock for the HUD: 2:05, or 45s.
static func clock(secs: float) -> String:
	var s := int(ceil(secs))
	return "%d:%02d" % [s / 60, s % 60] if s >= 60 else "%ds" % s

## Lines for an item's tooltip: what it does when used, worn or burnt.
static func describe(d: Dictionary) -> Array:
	var out: Array = []
	if int(d.get("heal", 0)) > 0:
		out.append("Restores %d health" % int(d["heal"]))
	if d.has("regen"):
		out.append("Heals %d more over %ds" % [int(d["regen"]), int(ceil(float(d["regen"]) / REGEN_RATE))])
	if d.get("stamina", false):
		out.append("Fully restores stamina")
	if d.has("stamina_add"):
		out.append("Restores %d stamina" % int(d["stamina_add"]))
	if d.get("cure", false):
		out.append("Cures poison")
	if d.has("buff"):
		var b: Dictionary = BUFFS.get(d["buff"][0], {})
		out.append("%s for %s: %s" % [b.get("name", ""), clock(float(d["buff"][1])), b.get("desc", "")])
	if float(d.get("sicken", 0.0)) > 0.0:
		out.append("Eaten raw it may make you sick")
	if d.get("keep", false):
		out.append("Refill it at any stream; drink again when thirsty")
	match String(d.get("read", "")):
		"courage", "warded":
			var b: Dictionary = BUFFS[d["read"]]
			out.append("Read it: %s for 5:00 (%s)" % [b["name"], b["desc"]])
		"return":
			out.append("Read it to return to your house, or where you first arrived")
		"book":
			out.append("Read it to learn something (experience)")
	if d.has("play"):
		out.append("Play it: %s (%s)" % [BUFFS[d["play"]]["name"], BUFFS[d["play"]]["desc"]])
	if d.has("sleep"):
		out.append("Use it at night to sleep until morning")
	if d.has("fish"):
		out.append("Use it facing water to fish")
	if d.has("reap"):
		out.append("Picks %d%% more from plants" % int((float(d["reap"]) - 1.0) * 100.0))
	if d.has("fuel"):
		out.append("Fuel: burns %s" % clock(float(d["fuel"])))
	var bon: Dictionary = d.get("bonus", {})
	for k in bon:
		out.append(_bonus_line(k, float(bon[k])))
	return out

static func _bonus_line(k: String, v: float) -> String:
	match k:
		"health": return "+%d max health" % int(v)
		"stamina": return "+%d max stamina" % int(v)
		"carry": return "+%d kg carry" % int(v)
		"armor": return "+%d armour" % int(v)
		"regen": return "Restores %.1f health a second" % v
		"stamina_regen": return "Stamina refills %d%% faster" % int(v * 100.0)
	return "+%d%% %s" % [int(v * 100.0), k]
