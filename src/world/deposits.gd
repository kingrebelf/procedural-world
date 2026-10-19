class_name Deposits
## Ore under the ground, per tile (one 64 m chunk), Dual Universe style: every tile holds a
## few hidden deposits an auto-miner standing on it pulls out, until they run dry. They are
## a pure function of the planet seed, its kind and the tile, so every game sees the same
## ones; only what has been mined is saved, in the chunk's data as dep: {ore: units mined}.
## Plan: plans/tile-minerals-factories.md.

## The ores by tier: [ore, tier, least zone level]. An ore also never shows below its own
## unlock level (ItemDB.unlock_level).
const ORES := [
	["iron_ore", 1, 1], ["copper_ore", 1, 1], ["coal", 1, 1], ["tin_ore", 1, 1], ["salt_crystal", 1, 1],
	["silver_ore", 2, 3], ["gold_ore", 2, 5],
	["titanium_ore", 3, 25], ["silicon_crystal", 3, 25], ["cobalt_ore", 3, 28],
	["lithium_ore", 4, 30], ["rare_earth", 4, 30], ["uranium_ore", 4, 36],
	["voidstone_ore", 5, 55], ["starsteel_ore", 5, 58], ["neutronium", 5, 66],
]
const TIER_NAMES := ["", "Common", "Uncommon", "Rare", "Exotic", "Alien"]
## Per tier: [chance a tile has one, least units, most units]. Tier 1 always has one.
const TIERS := {1: [1.0, 3000, 9000], 2: [0.4, 1500, 4000], 3: [0.25, 800, 2400], 4: [0.12, 400, 1200], 5: [0.08, 150, 600]}
const SECOND_T1 := 0.5 ## the odds of a second common deposit
const LODE := 1.5 ## how much bigger a planet's own mother-lode ore runs
## Planet kinds' leanings: ore -> how much likelier and bigger it is there.
const LEAN := {
	"verdant": {"copper_ore": 2.0, "tin_ore": 2.0, "gold_ore": 2.0, "uranium_ore": 0.5},
	"frozen": {"silver_ore": 2.0, "lithium_ore": 2.0, "salt_crystal": 2.0, "coal": 0.5},
	"rust": {"iron_ore": 2.0, "titanium_ore": 2.0, "cobalt_ore": 2.0},
	"fey": {"voidstone_ore": 2.0},
	"xeno": {"starsteel_ore": 2.0, "neutronium": 2.0},
}

## The deposits of tile (cx, cz) on a planet: [{ore, tier, total}], richest tier first.
## `zone`: the tile's zone level; `kind`: the planet kind; `alien`: an alien world.
static func roll(seed: int, cx: int, cz: int, zone: int, kind := "", alien := false) -> Array:
	var lean: Dictionary = LEAN.get(kind, {})
	var lode := mother_lode(seed, alien)
	var out: Array = []
	var salt := 0
	for tier in [5, 4, 3, 2, 1]:
		var t: Array = TIERS[tier]
		var picks := 1
		if tier == 1:
			picks = 2 if WHash.unit2(seed, cx, cz, 9100) < SECOND_T1 else 1
		for p in picks:
			salt += 1
			var ores := ores_for(tier, zone, alien)
			if ores.is_empty():
				break
			# Odds (and which ore) weighed by the planet's leanings.
			var w: Array = []
			var sum := 0.0
			for o in ores:
				var f := float(lean.get(o, 1.0))
				w.append(f)
				sum += f
			var odds := float(t[0]) * (sum / ores.size() if tier > 1 else 1.0)
			if WHash.unit2(seed, cx, cz, 9110 + salt) >= odds:
				continue
			var r := WHash.unit2(seed, cx, cz, 9130 + salt) * sum
			var ore: String = ores[-1]
			for i in ores.size():
				r -= float(w[i])
				if r < 0.0:
					ore = ores[i]
					break
			if out.any(func(d): return d["ore"] == ore):
				continue
			var size := lerpf(float(t[1]), float(t[2]), WHash.unit2(seed, cx, cz, 9150 + salt))
			size *= sqrt(float(lean.get(ore, 1.0)))
			if ore == lode:
				size *= LODE
			out.append({"ore": ore, "tier": tier, "total": int(size)})
	return out

## The ores of a tier that can lie in a tile of zone level `zone`.
static func ores_for(tier: int, zone: int, alien: bool) -> Array:
	var out: Array = []
	for e in ORES:
		if int(e[1]) != tier or zone < maxi(int(e[2]), ItemDB.unlock_level(e[0])):
			continue
		if tier == 5 and not alien:
			continue
		out.append(e[0])
	return out

## The one ore a planet is unusually rich in, from what its land can hold.
static func mother_lode(seed: int, alien: bool) -> String:
	var all: Array = []
	for tier in range(1, 6):
		all.append_array(ores_for(tier, 99, alien))
	return all[WHash.hash2(seed, 0, 0, 9199) % all.size()] if not all.is_empty() else ""

static func tier_of(ore: String) -> int:
	for e in ORES:
		if e[0] == ore:
			return int(e[1])
	return 0

# --- In the running game ------------------------------------------------------------

## The deposits under a chunk of the current planet, with what is left of each:
## [{ore, tier, total, left}]. Cached per planet seed and tile.
static var _cache := {}

static func of_chunk(data: Dictionary) -> Array:
	var cx := int(data.get("cx", 0))
	var cz := int(data.get("cz", 0))
	# The Game autoload, looked up at run time so this class also loads in tests.
	var game = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	var seed: int = game.seed if game != null else 0
	var key := Vector3i(seed, cx, cz)
	if not _cache.has(key):
		if _cache.size() > 4096:
			_cache.clear()
		var p: Dictionary = game.planet_info() if game != null and game.store != null else {}
		var c := Vector2((cx + 0.5) * ChunkGenerator.SIZE, (cz + 0.5) * ChunkGenerator.SIZE)
		var zone := Eras.zone_level(c.x, c.y) if Eras.themed() else 99
		_cache[key] = roll(seed, cx, cz, zone, String(p.get("kind", "")), String(p.get("theme", "")) == "alien")
	var mined: Dictionary = data.get("dep", {})
	var out: Array = []
	for d in _cache[key]:
		var e: Dictionary = d.duplicate()
		e["left"] = maxi(0, int(d["total"]) - int(mined.get(d["ore"], 0)))
		out.append(e)
	return out

## How much of `ore` is left under the chunk (0 when it has none).
static func left(data: Dictionary, ore: String) -> int:
	for d in of_chunk(data):
		if d["ore"] == ore:
			return int(d["left"])
	return 0

## Takes `n` units of `ore` out of the chunk's deposit; returns how many came out.
static func take(data: Dictionary, ore: String, n := 1) -> int:
	var got := mini(n, left(data, ore))
	if got > 0:
		var mined: Dictionary = data.get("dep", {})
		mined[ore] = int(mined.get(ore, 0)) + got
		data["dep"] = mined
	return got

## What a miner on this chunk drills: the ore it was set to while any is left, else the
## richest deposit (deepest tier first, then most left). "" when the tile is dry.
static func target(data: Dictionary, chosen: String) -> String:
	var best := ""
	var best_tier := 0
	var best_left := 0
	for d in of_chunk(data):
		var l := int(d["left"])
		if l <= 0:
			continue
		if d["ore"] == chosen:
			return chosen
		if int(d["tier"]) > best_tier or (int(d["tier"]) == best_tier and l > best_left):
			best = d["ore"]
			best_tier = int(d["tier"])
			best_left = l
	return best

## The deposit after `chosen` that still has ore in it (for crouch + Interact), or "".
static func next_target(data: Dictionary, chosen: String) -> String:
	var live: Array = []
	for d in of_chunk(data):
		if int(d["left"]) > 0:
			live.append(d["ore"])
	if live.is_empty():
		return ""
	return live[(live.find(chosen) + 1) % live.size()]

## Look-at lines: the tile's deposits and what is left of each.
static func lines(data: Dictionary, chosen: String) -> Array:
	var out: Array = []
	var deps := of_chunk(data)
	if deps.is_empty():
		return ["No ore under this tile"]
	var on := target(data, chosen)
	for d in deps:
		var nm := String(ItemDB.def(d["ore"]).get("name", d["ore"]))
		var left_s := "dry" if int(d["left"]) <= 0 else "%s of %s left" % [_n(int(d["left"])), _n(int(d["total"]))]
		out.append("%s%s (T%d %s): %s" % ["> " if d["ore"] == on else "", nm, int(d["tier"]), TIER_NAMES[int(d["tier"])], left_s])
	return out

static func _n(v: int) -> String:
	var s := str(v)
	return s if v < 1000 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]
