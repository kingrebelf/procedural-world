class_name NPCGen
## Creates the people of a settlement, once. Deterministic per (seed, settlement), so a
## settlement generated twice is identical, but like chunks it is generated only the
## first time and then saved; from then on its people live their own persistent lives.

const SETTLEMENT_FORMAT := 1

const FIRST := [
	["Aldwin", "Bryony", "Cedric", "Edith", "Godric", "Hilda", "Jory", "Maud", "Osbert", "Rowena", "Tamsin", "Wat", "Agnes", "Hugh", "Isolde", "Piers"],
	["Aelith", "Brisk", "Corwen", "Elowen", "Fennick", "Isra", "Lirael", "Mossen", "Nimue", "Quill", "Seren", "Thaddeus", "Wren", "Yarrow", "Oleander", "Faelan"],
	["Ada", "Boone", "Cass", "Dex", "Imani", "Juno", "Kai", "Lena", "Mako", "Nova", "Orrin", "Priya", "Rook", "Sable", "Tycho", "Vesna"],
]
const LAST := [
	["Thatcher", "of the Mill", "Cooper", "Ashdown", "Fletcher", "Brewer", "Holt", "Marsh"],
	["Thornwhistle", "of the Glade", "Moonbrook", "Greenmantle", "Ashveil", "Starling", "Dewfall", "Brackenroot"],
	["Okoye", "Vance", "Reyes", "Tanaka", "Haldane", "Mbeki", "Sorensen", "Varga"],
]
const JOBS := [
	["farmer", "smith", "guard", "innkeeper", "hunter", "priest", "weaver", "miller"],
	["herbalist", "warden", "runecarver", "bard", "mystic", "beekeeper", "lamplighter", "scribe"],
	["engineer", "medic", "scavenger", "pilot", "security officer", "data broker", "hydroponics tech", "courier"],
]
const GUARD_JOBS := ["guard", "warden", "security officer"]
const LIKES := [
	["good ale", "harvest festivals", "a fair price", "old songs", "honest work", "the king's peace"],
	["moonlight", "the old stories", "glowberries", "quiet groves", "riddles", "the spirits of the mere"],
	["clean code", "fresh rations", "salvage runs", "the signal from the array", "a good engine", "the long haul"],
]
const WORRIES := [
	["bandits on the road", "the harvest failing", "the strange lights to the east", "taxes"],
	["the wild magic thinning", "iron-folk cutting the wood", "the spire singing at night", "lost travellers"],
	["power shortages", "raiders in the dead zones", "the old-world ruins", "supply drops running late"],
]
const SPEECH := [
	"plain and earthy, a little old-fashioned",
	"lyrical and mysterious, fond of metaphor",
	"clipped, practical and technical, with frontier slang",
]
const SKIN := [Color(0.95, 0.80, 0.68), Color(0.87, 0.68, 0.52), Color(0.72, 0.53, 0.38), Color(0.55, 0.38, 0.26), Color(0.38, 0.26, 0.18)]
const HAIR := [Color(0.1, 0.08, 0.06), Color(0.3, 0.2, 0.12), Color(0.55, 0.38, 0.2), Color(0.8, 0.65, 0.4), Color(0.6, 0.6, 0.6), Color(0.65, 0.25, 0.12)]
const CLOTH := [
	[Color(0.45, 0.32, 0.2), Color(0.32, 0.38, 0.22), Color(0.55, 0.15, 0.12), Color(0.25, 0.3, 0.45), Color(0.6, 0.55, 0.45)],
	[Color(0.2, 0.42, 0.38), Color(0.35, 0.25, 0.5), Color(0.55, 0.6, 0.35), Color(0.15, 0.3, 0.45), Color(0.6, 0.45, 0.6)],
	[Color(0.25, 0.27, 0.3), Color(0.5, 0.35, 0.15), Color(0.2, 0.3, 0.38), Color(0.6, 0.6, 0.62), Color(0.35, 0.15, 0.15)],
]

static func settlement_id(sx: int, sz: int) -> String:
	return "%d_%d" % [sx, sz]

## site: from ChunkGenerator.settlement_at; layout: ChunkGenerator.settlement_layout(site).
static func generate(world_seed: int, gen: ChunkGenerator, site: Dictionary, layout: Array) -> Dictionary:
	var sx: int = site["sx"]
	var sz: int = site["sz"]
	var era: int = site["era"]
	var c: Vector2 = site["center"]
	var r := WHash.rng(world_seed, sx, sz, 501)
	var homes: Array = []
	var stall: Dictionary = {}
	for it in layout:
		if it["t"] == "trader":
			stall = it
		elif ObjectLibrary.kind(it["t"]) == "structure":
			# The door is on the side facing the square.
			var p: Vector2 = it["p"]
			homes.append({"p": p + (c - p).normalized() * 4.2, "t": it["t"]})
	if homes.is_empty():
		homes.append({"p": c + Vector2(8, 0), "t": "camp"})
	var npcs: Array = []
	# The trader keeps the stall.
	var st: Dictionary = stall.get("st", {})
	var yaw: float = stall.get("yaw", 0.0)
	var behind := Vector2(sin(yaw), cos(yaw)) * -0.6
	var keeper := _person(r, era, npcs.size(), sx, sz)
	keeper["name"] = st.get("name", keeper["name"])
	keeper["job"] = "trader"
	keeper["work"] = (stall.get("p", c) as Vector2) + behind
	keeper["work_yaw"] = yaw
	keeper["home"] = homes[0]["p"]
	keeper["stall"] = stall.get("p", c)
	npcs.append(keeper)
	var count := clampi(homes.size() + r.randi_range(0, 2), 3, 8 + 6 * int(site.get("size", 0)))
	var jobs: Array = JOBS[era].duplicate()
	for n in count:
		var p := _person(r, era, npcs.size(), sx, sz)
		var j: String = jobs[r.randi() % jobs.size()]
		if n == 0:
			j = GUARD_JOBS[era]
		p["job"] = j
		var home: Dictionary = homes[(n + 1) % homes.size()]
		p["home"] = home["p"]
		var ang := r.randf() * TAU
		p["work"] = c + Vector2(cos(ang), sin(ang)) * r.randf_range(5.0, 12.0)
		p["work_yaw"] = r.randf() * TAU
		npcs.append(p)
	for p in npcs:
		var h2: Vector2 = p["home"]
		p["pos"] = Vector3(h2.x, gen.field.height(h2.x, h2.y), h2.y)
	var name := gen.field.region_name_at(c.x, c.y)
	return {
		"format": SETTLEMENT_FORMAT, "sx": sx, "sz": sz, "era": era, "center": c,
		"name": name, "npcs": npcs, "rumors": [], "sim_day": -1.0,
	}

static func _person(r: RandomNumberGenerator, era: int, idx: int, sx: int, sz: int) -> Dictionary:
	var first: String = FIRST[era][r.randi() % FIRST[era].size()]
	var last: String = LAST[era][r.randi() % LAST[era].size()]
	var cloth: Array = CLOTH[era]
	var body := {
		"height": r.randf_range(0.9, 1.08), "build": r.randf_range(0.85, 1.2), "female": r.randf() < 0.5,
		"skin": SKIN[r.randi() % SKIN.size()], "hair": HAIR[r.randi() % HAIR.size()],
		"hair_style": r.randi() % 4, "cloth": cloth[r.randi() % cloth.size()], "cloth2": cloth[r.randi() % cloth.size()],
	}
	return {
		"id": "%d_%d_%d" % [sx, sz, idx],
		"name": "%s %s" % [first, last], "era": era, "body": body,
		"traits": {
			"friendly": snappedf(r.randf(), 0.01), "brave": snappedf(r.randf(), 0.01),
			"curious": snappedf(r.randf(), 0.01), "diligent": snappedf(r.randf(), 0.01),
			"greedy": snappedf(r.randf(), 0.01),
		},
		"likes": LIKES[era][r.randi() % LIKES[era].size()],
		"worry": WORRIES[era][r.randi() % WORRIES[era].size()],
		"speech": SPEECH[era],
		"age": r.randi_range(18, 70),
		"hp": 100.0, "dead": false,
		"rel": 0, "met": 0, "mem": [], "goal": "", "mood": "calm",
		"pos": Vector3.ZERO, "yaw": r.randf() * TAU,
		"energy": r.randf_range(0.6, 1.0), "social": r.randf_range(0.3, 0.9),
	}

## One-line description used by both the built-in dialogue and the LLM prompt.
static func describe(p: Dictionary) -> String:
	return "%s, a %d-year-old %s %s" % [p["name"], p["age"], Eras.NAMES[p["era"]].to_lower(), p["job"]]
