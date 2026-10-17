class_name Crime
extends RefCounted
## Your bounty in each settlement, and the wanted level (stars) it comes to. Crimes only
## count when someone sees them: stealing from the chests and shops of a town, picking
## pockets and getting caught, breaking in, hurting or killing its people. Guards make you
## pay up or come after you; the bounty cools off a little each day you stay out of
## trouble. Pure data, saved with the player.

## Bounty (Marks) at which each star is reached: 1 star for anything, 3 stars and guards
## attack on sight, 5 stars and even brave townsfolk join in.
const STARS := [1, 60, 200, 500, 1200]
const MAX_STARS := 5
## Bounty for each kind of crime on top of what was taken.
const FINES := {"theft": 15, "pickpocket": 25, "lockpick": 10, "trespass": 5, "assault": 40, "vandalism": 20, "arson": 150, "murder": 600}
## A day after your last crime there, the bounty halves every in-game day.
const COOL_AFTER := 1.0

var bounty: Dictionary = {} ## settlement id -> {b: int, name: String, day: float (last crime)}

## Adds a bounty in a settlement. Returns the new bounty there.
func add(sid: String, town: String, amount: int, day: float) -> int:
	if amount <= 0:
		return owed(sid, day)
	var b := owed(sid, day)
	bounty[sid] = {"b": b + amount, "name": town, "day": day}
	return b + amount

## What you owe a settlement now, after cooling off.
func owed(sid: String, day: float) -> int:
	if not bounty.has(sid):
		return 0
	var e: Dictionary = bounty[sid]
	var idle := maxf(0.0, day - float(e["day"]) - COOL_AFTER)
	var b := int(floor(float(e["b"]) * pow(0.5, idle)))
	return b if b > 0 else 0

## Stars for a bounty.
static func stars_for(b: int) -> int:
	var n := 0
	for i in STARS.size():
		if b >= STARS[i]:
			n = i + 1
	return n

func stars(sid: String, day: float) -> int:
	return stars_for(owed(sid, day))

## Pays off (or forgives) a settlement's bounty.
func clear(sid: String) -> void:
	bounty.erase(sid)

## The settlement you are most wanted in: {sid, name, b, stars}, or {} when you are not wanted anywhere.
func worst(day: float) -> Dictionary:
	var best := {}
	for sid in bounty:
		var b := owed(sid, day)
		if b > int(best.get("b", 0)):
			best = {"sid": sid, "name": bounty[sid]["name"], "b": b, "stars": stars_for(b)}
	return best

## Drops bounties that have cooled to nothing.
func prune(day: float) -> void:
	for sid in bounty.keys():
		if owed(sid, day) <= 0:
			bounty.erase(sid)

func to_data() -> Dictionary:
	return {"bounty": bounty.duplicate(true)}

static func from_data(d) -> Crime:
	var c := Crime.new()
	if d is Dictionary and d.get("bounty") is Dictionary:
		for sid in d["bounty"]:
			var e = d["bounty"][sid]
			if e is Dictionary:
				c.bounty[String(sid)] = {"b": maxi(0, int(e.get("b", 0))), "name": String(e.get("name", "")), "day": float(e.get("day", 0.0))}
	return c
