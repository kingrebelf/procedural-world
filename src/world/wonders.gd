class_name Wonders
## Relics and wayside marvels you use rather than break: wake a xenolith circle at its
## core, light a navigation beacon, read a standing stone's runes, draw on a crystal or
## drink from a well, pray at a summit shrine, salvage a wrecked starship. What each has
## done is kept in the object's state (in the chunk snapshot), so a woken relic stays
## woken. The effects live in WonderEffects.

## These can't be broken; their gifts come from using them.
const UNBREAKABLE := {"alien_ruin": true, "beacon": true, "standing_stone": true, "crystal_shard": true}
const TYPES := {"alien_ruin": true, "beacon": true, "standing_stone": true, "crystal_shard": true, "well": true}

## The hidden landmarks: what using one is called, whether it gives again each day (else
## only once), how high its prompt floats, and what it says once it has given.
const LANDMARKS := {
	"summit_shrine": {"verb": "Pray at the shrine", "daily": true, "h": 1.6, "spent": "The shrine is quiet until tomorrow"},
	"eyrie": {"verb": "Search the giant's nest", "daily": false, "h": 1.2, "spent": "You have picked the nest clean"},
	"sunken_altar": {"verb": "Lay a hand on the altar", "daily": true, "h": 1.2, "spent": "The altar is cold until tomorrow"},
	"fallen_star": {"verb": "Chip at the fallen star", "daily": true, "h": 1.6, "spent": "The star's glow is spent until tomorrow"},
	"star_wreck": {"verb": "Salvage the wreck", "daily": true, "h": 2.0, "spent": "Nothing more to strip from it today"},
	"titan_bones": {"verb": "Study the titan's bones", "daily": false, "h": 1.6, "spent": "You have learned what the bones can tell"},
	"dolmen": {"verb": "Rest beneath the dolmen", "daily": true, "h": 1.4, "spent": "You have rested here today"},
}

static func has(t: String) -> bool:
	return TYPES.has(t) or LANDMARKS.has(t)

static func unbreakable(t: String) -> bool:
	return UNBREAKABLE.has(t) or LANDMARKS.has(t) or WonderSite.has(t)

## What using it does right now, for the floating prompt: {"verb", "h"} (h: how high the
## prompt floats), or {} when it has nothing more to give today.
static func use_of(o: Dictionary, day: float) -> Dictionary:
	var st: Dictionary = o["st"]
	var fresh := int(st.get("day", -1)) < int(floor(day))
	var lm: Dictionary = LANDMARKS.get(String(o["t"]), {})
	if not lm.is_empty():
		if not st.get("used", false) or (lm["daily"] and fresh):
			return {"verb": lm["verb"], "h": lm["h"]}
		return {}
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
	var lm: Dictionary = LANDMARKS.get(String(o["t"]), {})
	if not lm.is_empty():
		return "Something here is worth a closer look" if use_of(o, day).size() > 0 else lm["spent"]
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
