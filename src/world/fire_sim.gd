class_name FireSim
extends RefCounted
## How things burn (plans/fire-system.md): what catches and how readily, how long it
## burns, how heat grows and dies, how a fire throws itself at its neighbours (downwind
## much further), and how rain, water, beating and oil change it. Pure functions on an
## object's persisted `st`, so the Fire system, tests and a chunk catching up on time it
## was away all share them.
##
## State in `st` (all optional):
##   fire: {h: heat 0..1, f: fuel seconds left, w: wall-clock seconds of the last write,
##          by: 1 when the player's hand is behind it (spreads with it)}
##   fl:   fuel left after a fire was put out (a half-burnt house burns for less)
##   char: 0..1 how scorched it is; never goes back
##   soak: [amount 0..1, wall time]: wet from a bucket (dries over minutes)
##   oil:  seconds of oil or pitch poured on it (catches fast, burns hot)

## type -> [how readily it catches 0..1, fuel in seconds at full heat, what it leaves].
## Leaves: "timber" (falls in: charred beams and ash), "masonry" (walls fall to rubble
## over burnt beams), "tree" (a charred trunk), "ash" (a small heap), "" (nothing: it
## only scorches).
const PROFILES := {
	"longhouse": [0.85, 420.0, "timber"],
	"cottage": [0.45, 320.0, "masonry"],
	"townhouse": [0.45, 460.0, "masonry"],
	"watchtower": [0.3, 200.0, "masonry"],
	"market_stall": [0.9, 120.0, "ash"],
	"fruit_cart": [0.9, 90.0, "ash"],
	"wagon": [0.85, 140.0, "ash"],
	"barrels": [0.8, 110.0, "ash"],
	"signpost": [0.75, 45.0, "ash"],
	"border_sign": [0.75, 45.0, "ash"],
	"chest": [0.7, 60.0, "ash"],
	"trader": [0.9, 140.0, "ash"],
	"crash_trunk": [0.2, 90.0, ""],
	"mushroom_house": [0.25, 200.0, "ash"],
	"glowcap": [0.2, 70.0, "ash"],
	# Live wood: hard to light, but a crown well alight throws flame a long way.
	"pine": [0.18, 110.0, "tree"],
	"oak": [0.1, 130.0, "tree"],
}

## The burnt-out ground a building leaves (Fire.ruin_mesh): its own mesh per size.
const RUIN := "fire_ruin"

static func profile(t: String) -> Dictionary:
	if BuildCatalog.is_built(t):
		var d := BuildCatalog.def(BuildCatalog.id_of(t))
		if String(d.get("mat", "wood")) != "wood":
			return {"catch": 0.0, "fuel": 0.0, "leaves": ""}
		return {"catch": 0.85, "fuel": clampf(float(d.get("hp", 10.0)) * 6.0, 40.0, 240.0), "leaves": "ash"}
	var p: Array = PROFILES.get(t, [])
	if p.is_empty():
		return {"catch": 0.0, "fuel": 0.0, "leaves": ""}
	return {"catch": float(p[0]), "fuel": float(p[1]), "leaves": String(p[2])}

static func burns(t: String) -> bool:
	return profile(t)["catch"] > 0.0

static func burning(st: Dictionary) -> bool:
	return st.has("fire")

static func heat(st: Dictionary) -> float:
	return float((st["fire"] as Dictionary).get("h", 0.0)) if st.has("fire") else 0.0

## How wet it still is from a bucket, at wall time `now`.
static func soak(st: Dictionary, now: float) -> float:
	var s = st.get("soak")
	if not (s is Array) or s.size() < 2:
		return 0.0
	return clampf(float(s[0]) - (now - float(s[1])) * DRY_RATE, 0.0, 1.0)

const DRY_RATE := 1.0 / 240.0 ## a soaked wall dries out over about four minutes

static func _set_soak(st: Dictionary, v: float, now: float) -> void:
	if v <= 0.001:
		st.erase("soak")
	else:
		st["soak"] = [snappedf(clampf(v, 0.0, 1.0), 0.001), snappedf(now, 0.1)]

## The weather a fire burns in: {rain 0..1 (falling now), snow 0..1, wet 0..1 (the
## ground and walls), wind 0..1, wind_dir Vector2}.
static func calm() -> Dictionary:
	return {"rain": 0.0, "snow": 0.0, "wet": 0.0, "wind": 0.3, "wind_dir": Vector2(0.8, 0.6)}

## The chance (0..1) a flame of `strength` (0..1: a torch ~0.5, a fire bottle 1) sets
## this alight, in this weather. 0 for what does not burn or is already burning.
static func catch_chance(t: String, st: Dictionary, strength: float, env: Dictionary, now: float) -> float:
	var p := profile(t)
	if p["catch"] <= 0.0 or st.has("fire") or st.get("gone", false):
		return 0.0
	if st.has("fl") and float(st["fl"]) <= 1.0:
		return 0.0 # nothing left in it to burn
	var c: float = p["catch"] * clampf(strength, 0.0, 1.5)
	if float(st.get("oil", 0.0)) > 0.0:
		c = maxf(c, 0.95) # oil-soaked: anything goes up
	c *= 1.0 - soak(st, now) * 0.95
	c *= 1.0 - clampf(float(env.get("wet", 0.0)) * 0.6 + float(env.get("rain", 0.0)) * 0.5, 0.0, 0.9)
	return clampf(c, 0.0, 1.0)

## Sets it alight: a small flame that grows (step). Returns false for what will not burn.
static func ignite(t: String, st: Dictionary, strength: float, now: float, by_player := false) -> bool:
	var p := profile(t)
	if p["catch"] <= 0.0 or st.has("fire") or st.get("gone", false):
		return false
	var fuel: float = float(st.get("fl", p["fuel"]))
	if fuel <= 1.0:
		return false
	st.erase("fl")
	var h := 0.06 + clampf(strength, 0.0, 1.0) * 0.18 + (0.15 if float(st.get("oil", 0.0)) > 0.0 else 0.0)
	st["fire"] = {"h": snappedf(h, 0.001), "f": snappedf(fuel, 0.1), "w": snappedf(now, 0.1)}
	if by_player:
		st["fire"]["by"] = 1
	return true

## How scorched it looks: char in quarter steps (any scorch shows), so a fire redraws its
## chunk only a few times as it blackens.
static func char_step(st: Dictionary) -> float:
	return ceilf(clampf(float(st.get("char", 0.0)), 0.0, 1.0) * 4.0 - 0.001) / 4.0

## Scorches what will not burn (a fire bottle on a stone wall).
static func scorch(st: Dictionary, amount: float) -> void:
	st["char"] = snappedf(clampf(float(st.get("char", 0.0)) + amount, 0.0, 1.0), 0.001)

## How hot a fire with this much fuel left can burn: a fire low on fuel dies down.
static func _ceiling(fuel_left: float, fuel0: float) -> float:
	return clampf(fuel_left / maxf(fuel0 * 0.12, 1.0), 0.0, 1.0)

const GROW := 0.045 ## how fast heat climbs towards what the fuel can feed, per second
const DIE := 0.07 ## how fast it falls away once the fuel runs low
const OUT := 0.02 ## below this it is out

## Advances one burning object by dt seconds. Returns "" (still burning), "out" (it went
## out with fuel left: put out or drowned) or "burnt" (nothing left to burn).
static func step(t: String, st: Dictionary, dt: float, env: Dictionary, now: float) -> String:
	if not st.has("fire"):
		return ""
	var fire: Dictionary = st["fire"]
	var p := profile(t)
	var fuel0: float = maxf(float(p["fuel"]), 1.0)
	var h: float = fire.get("h", 0.0)
	var f: float = fire.get("f", fuel0)
	var oil: float = float(st.get("oil", 0.0))
	var top := _ceiling(f, fuel0)
	if oil > 0.0:
		top = minf(1.0, top + 0.25)
		oil = maxf(0.0, oil - dt)
		if oil <= 0.0:
			st.erase("oil")
		else:
			st["oil"] = snappedf(oil, 0.01)
	var rate: float = GROW * (0.5 + float(p["catch"])) * (3.0 if oil > 0.0 else 1.0)
	# Wind fans it.
	rate *= 1.0 + float(env.get("wind", 0.3)) * 0.8
	if h < top:
		h = minf(top, h + (top - h + 0.05) * rate * dt)
	else:
		h = maxf(top, h - (h - top) * DIE * dt * 4.0)
	# Rain beats it down, a small fire more than a big one; snow less than rain.
	var rain := float(env.get("rain", 0.0)) * (1.0 - float(env.get("snow", 0.0)) * 0.6)
	h -= rain * 0.045 * dt * (1.3 - h * 0.7)
	var wet := soak(st, now)
	if wet > 0.0:
		h -= wet * 0.04 * dt
	h = clampf(h, 0.0, 1.0)
	f = maxf(0.0, f - dt * (0.2 + 0.8 * h))
	scorch(st, dt * h * 0.012)
	fire["h"] = snappedf(h, 0.0001)
	fire["f"] = snappedf(f, 0.01)
	if h <= OUT:
		if int(fire.get("by", 0)) == 1:
			st["lit_by"] = 1 # who to blame for what is left
		st.erase("fire")
		if f <= fuel0 * 0.03:
			return "burnt"
		st["fl"] = snappedf(f, 0.1)
		return "out"
	return ""

## Water thrown on it (a bucket: 0.5): knocks heat off, a small fire most, and soaks it
## so it is hard to light again. Works on what is not burning too (wetting a wall).
## Returns "out" if that put it out.
static func quench(st: Dictionary, amount: float, now: float) -> String:
	_set_soak(st, soak(st, now) + amount * 0.9, now)
	st.erase("oil")
	if not st.has("fire"):
		return ""
	var fire: Dictionary = st["fire"]
	var h: float = fire.get("h", 0.0)
	h -= amount * (1.0 - h * 0.45)
	fire["h"] = snappedf(maxf(h, 0.0), 0.0001)
	if h <= OUT * 2.0:
		st.erase("fire")
		st["fl"] = snappedf(float(fire.get("f", 0.0)), 0.1)
		return "out"
	return ""

## A blow with a tool or a sack beating at the flames (power ~ the tool's damage / 10).
## Puts out a small fire in a few blows; barely dents a house well alight.
static func beat(st: Dictionary, power: float, now: float) -> String:
	if not st.has("fire"):
		return ""
	var h := heat(st)
	var take := clampf(power, 0.1, 2.0) * 0.14 / (0.25 + h * h * 3.0)
	var r := quench(st, take, now)
	# Beating does not soak it.
	_set_soak(st, soak(st, now) - take * 0.9, now)
	return r

## Oil or pitch poured on it (seconds of extra burning, ~60 for a flask). On a fire it
## flares up.
static func feed(st: Dictionary, oil_secs: float) -> void:
	st["oil"] = snappedf(minf(float(st.get("oil", 0.0)) + oil_secs, 180.0), 0.01)
	st.erase("soak")
	if st.has("fire"):
		var fire: Dictionary = st["fire"]
		fire["h"] = snappedf(minf(1.0, float(fire.get("h", 0.0)) + 0.25), 0.0001)
		fire["f"] = snappedf(float(fire.get("f", 0.0)) + oil_secs * 0.5, 0.01)

## The chance per second that a fire of heat `h` throws flame onto a neighbour.
## `gap`: metres between their boxes; `along`: the unit direction from the fire to it
## (flat); `src_size`: the fire's height in metres (a tall blaze reaches further).
static func spread_rate(h: float, gap: float, along: Vector2, src_size: float, dst_t: String, dst_st: Dictionary, env: Dictionary, now: float) -> float:
	var c := catch_chance(dst_t, dst_st, 1.0, env, now)
	if c <= 0.0 or h < 0.35:
		return 0.0
	var wind: float = env.get("wind", 0.3)
	var wd: Vector2 = env.get("wind_dir", Vector2(0.8, 0.6))
	var down := along.dot(wd.normalized()) * wind if along != Vector2.ZERO else 0.0
	var reach := (0.8 + 3.2 * h) * clampf(src_size / 5.0, 0.6, 2.0)
	reach *= 1.0 + 2.2 * maxf(down, 0.0)
	reach *= 1.0 - 0.6 * maxf(-down, 0.0)
	if gap >= reach:
		return 0.0
	var near := 1.0 - maxf(gap, 0.0) / reach
	return c * h * h * near * sqrt(near) * 0.3

## Where the fire's own clock stands for catching up: a chunk left alone for `elapsed`
## seconds burns that long (in coarse steps, no spreading). Returns the last step result.
static func catch_up(t: String, st: Dictionary, elapsed: float, env: Dictionary, now: float) -> String:
	var left := minf(elapsed, 3600.0)
	var r := ""
	while left > 0.0 and st.has("fire"):
		var dt := minf(left, 2.0)
		r = step(t, st, dt, env, now - left)
		left -= dt
	return r
