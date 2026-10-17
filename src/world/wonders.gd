class_name Wonders
## Relics and wayside marvels you use rather than break: wake a xenolith circle at its
## core, light a navigation beacon, read a standing stone's runes, draw on a crystal or
## drink from a well. What each has done is kept in the object's state (in the chunk
## snapshot), so a woken relic stays woken. The effects live in WonderEffects.

## These can't be broken; their gifts come from using them.
const UNBREAKABLE := {"alien_ruin": true, "beacon": true, "standing_stone": true, "crystal_shard": true}
const TYPES := {"alien_ruin": true, "beacon": true, "standing_stone": true, "crystal_shard": true, "well": true}

static func has(t: String) -> bool:
	return TYPES.has(t)

static func unbreakable(t: String) -> bool:
	return UNBREAKABLE.has(t)

## What using it does right now, for the floating prompt: {"verb", "h"} (h: how high the
## prompt floats), or {} when it has nothing more to give today.
static func use_of(o: Dictionary, day: float) -> Dictionary:
	var st: Dictionary = o["st"]
	var fresh := int(st.get("day", -1)) < int(floor(day))
	match String(o["t"]):
		"alien_ruin":
			var noun := ObjectLibrary.label_of(o)
			if not st.get("woke", false):
				return {"verb": "Wake the %s" % noun, "h": 2.2}
			if fresh:
				return {"verb": "Draw strength from the %s" % noun, "h": 2.2}
		"beacon":
			if not st.get("lit", false):
				return {"verb": "Light the beacon", "h": 3.0}
			if fresh:
				return {"verb": "Listen to the beacon", "h": 3.0}
		"standing_stone":
			if not st.get("read", false):
				return {"verb": "Read the runes", "h": 1.8}
		"crystal_shard":
			if fresh:
				return {"verb": "Draw on the crystal", "h": 1.4}
		"well":
			return {"verb": "Drink from the well", "h": 1.4}
	return {}

## A line for the look panel saying what it has done or will do.
static func describe(o: Dictionary, day: float) -> String:
	var st: Dictionary = o["st"]
	var fresh := int(st.get("day", -1)) < int(floor(day))
	match String(o["t"]):
		"alien_ruin":
			if not st.get("woke", false):
				return "Something sleeps in its core"
			return "Awake. Its core restores you once a day" if fresh else "Its core is dim until tomorrow"
		"beacon":
			if not st.get("lit", false):
				return "Dark. Lighting it calls down a supply pod"
			return "Lit. It points you to the next settlement once a day" if fresh else "Lit. Nothing new on it until tomorrow"
		"standing_stone":
			return "Runes cover it" if not st.get("read", false) else "You have read its runes"
		"crystal_shard":
			return "It hums with stored power" if fresh else "Drained until tomorrow"
		"well":
			return "Fresh water"
	return ""

## A compass word for the way from `from` to `to` (north is -z, east +x).
static func compass(from: Vector2, to: Vector2) -> String:
	var d := to - from
	var deg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	return ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][int(round(deg / 45.0)) % 8]
