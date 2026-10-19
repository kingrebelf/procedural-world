class_name Standing
extends RefCounted
## How each town thinks of you: your standing there, from Outcast to Honoured (and Citizen
## once you own a house there). It comes from what you have done there (deeds: crimes,
## fines paid, trade, joining a guild, buying a house, ridding its roads of outlaws), how
## its people feel about you (the mean of each resident's own regard, kept from your last
## visit) and what word has reached it from towns nearby. Any bounty there counts hard
## against you. Passes into walled towns (a toll paid, a friend who vouched) are kept here
## too. Pure data, saved with the player, so every player has their own.

## Tiers by score, lowest first: [from score, name].
const TIERS := [[-100, "Outcast"], [-59, "Distrusted"], [-24, "Stranger"], [10, "Known"], [35, "Respected"], [65, "Honoured"]]
const CITIZEN := "Citizen"
## Standing lost per wanted star there.
const PER_STAR := 20
## How much of the people's mean regard (-100..100) counts.
const FOLK := 0.5
## Word of a deed reaches towns this close (metres) at this share.
const WORD_REACH := 1500.0
const WORD_SHARE := 0.35
## Deeds fade toward nothing: bad ones halve every this many days, good ones slower.
const FADE_BAD := 12.0
const FADE_GOOD := 30.0
## Deeds for things you do (on top of crimes, which count from their fine).
const DEEDS := {"paid_bounty": 6, "guild": 8, "house": 25, "outlaw": 6, "trade": 1, "toll": 1, "bribe_refused": -10, "betrayal": -20, "trespass": -6, "tax": 1, "tax_default": -8}

var towns: Dictionary = {} ## sid -> {d: deeds, day: of the last deed, name, x, z, folk, pass: day it runs out, how, by}

## Remembers a town you have come to (its name and where it is), so word can reach it
## and its people's regard is kept while you are away. Word of what you did in towns
## near it gets there before you the first time.
func note(sid: String, town: String, center: Vector2, day: float) -> void:
	if towns.has(sid):
		var e: Dictionary = towns[sid]
		e["name"] = town
		e["x"] = center.x
		e["z"] = center.y
		return
	var heard := 0.0
	for o in towns:
		if _same_world(o, sid):
			var f := _near(towns[o], center)
			if f > 0.0:
				heard += deeds(o, day) * WORD_SHARE * f
	towns[sid] = {"d": heard, "day": day, "name": town, "x": center.x, "z": center.y, "folk": 0.0, "pass": -1.0, "how": "", "by": ""}

## Something you did in a town (`amount` + or -). Word gets to the towns near it.
## Returns the deeds there now.
func deed(sid: String, town: String, center: Vector2, amount: float, day: float) -> float:
	note(sid, town, center, day)
	_add(sid, amount, day)
	for o in towns:
		if o != sid and _same_world(o, sid):
			var f := _near(towns[o], center)
			if f > 0.0:
				_add(o, amount * WORD_SHARE * f, day)
	return deeds(sid, day)

func _add(sid: String, amount: float, day: float) -> void:
	var e: Dictionary = towns[sid]
	e["d"] = clampf(deeds(sid, day) + amount, -150.0, 150.0)
	e["day"] = day

## 1 close by, falling to 0 at WORD_REACH; 0 for towns not yet placed.
static func _near(e: Dictionary, center: Vector2) -> float:
	var d := Vector2(float(e.get("x", 0.0)), float(e.get("z", 0.0))).distance_to(center)
	return clampf(1.0 - d / WORD_REACH, 0.0, 1.0)

## Same planet (sids are "planet:sx_sz"): word doesn't cross space.
static func _same_world(a: String, b: String) -> bool:
	return a.get_slice(":", 0) == b.get_slice(":", 0)

## Your deeds in a town now, faded with time.
func deeds(sid: String, day: float) -> float:
	if not towns.has(sid):
		return 0.0
	var e: Dictionary = towns[sid]
	var d := float(e["d"])
	var idle := maxf(0.0, day - float(e["day"]))
	return d * pow(0.5, idle / (FADE_BAD if d < 0.0 else FADE_GOOD))

## The townsfolk's mean regard for you (each resident's own `rel`), kept for when
## you're away.
func set_folk(sid: String, mean_rel: float) -> void:
	if towns.has(sid):
		towns[sid]["folk"] = clampf(mean_rel, -100.0, 100.0)

## Your standing in a town, -100..100: deeds, its people's regard, less any wanted stars.
func score(sid: String, day: float, stars := 0) -> int:
	var folk := float(towns[sid].get("folk", 0.0)) if towns.has(sid) else 0.0
	return clampi(int(round(deeds(sid, day) + folk * FOLK)) - stars * PER_STAR, -100, 100)

static func tier_of(s: int) -> String:
	var name: String = TIERS[0][1]
	for t in TIERS:
		if s >= int(t[0]):
			name = t[1]
	return name

## The colour a tier is shown in.
static func tier_color(t: String) -> Color:
	match t:
		"Outcast": return Color(0.9, 0.3, 0.28)
		"Distrusted": return Color(0.92, 0.55, 0.35)
		"Stranger": return Color(0.75, 0.75, 0.72)
		"Known": return Color(0.7, 0.85, 0.6)
		"Respected": return Color(0.5, 0.85, 0.55)
		"Honoured", CITIZEN: return Color(0.95, 0.82, 0.4)
	return Color.WHITE

# --- Passes into walled towns -----------------------------------------------------------

## Leave to come and go through a town's gates until `until` (a game day): bought
## ("toll"), bribed ("bribe") or vouched for ("vouched", by a resident's id).
func give_pass(sid: String, until: float, how: String, by := "") -> void:
	if towns.has(sid):
		var e: Dictionary = towns[sid]
		e["pass"] = until
		e["how"] = how
		e["by"] = by

func has_pass(sid: String, day: float) -> bool:
	return towns.has(sid) and float(towns[sid].get("pass", -1.0)) > day

## The pass, as {how, by, until}, or {} when you have none there now.
func pass_of(sid: String, day: float) -> Dictionary:
	if not has_pass(sid, day):
		return {}
	var e: Dictionary = towns[sid]
	return {"how": String(e.get("how", "")), "by": String(e.get("by", "")), "until": float(e["pass"])}

## A crime or a refused bribe: any pass there is torn up.
func revoke(sid: String) -> void:
	if towns.has(sid):
		towns[sid]["pass"] = -1.0

# --- Saving ---------------------------------------------------------------------------

func to_data() -> Dictionary:
	return {"towns": towns.duplicate(true)}

static func from_data(d) -> Standing:
	var s := Standing.new()
	if d is Dictionary and d.get("towns") is Dictionary:
		for sid in d["towns"]:
			var e = d["towns"][sid]
			if e is Dictionary:
				s.towns[String(sid)] = {"d": float(e.get("d", 0.0)), "day": float(e.get("day", 0.0)), "name": String(e.get("name", "")),
					"x": float(e.get("x", 0.0)), "z": float(e.get("z", 0.0)), "folk": float(e.get("folk", 0.0)),
					"pass": float(e.get("pass", -1.0)), "how": String(e.get("how", "")), "by": String(e.get("by", ""))}
	return s
