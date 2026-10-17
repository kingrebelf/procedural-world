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

## A settlement's people the first time it is seen: a town's (settlement_at sites) or a
## boat's crew (Boats sites, which carry "boat").
static func create(gen: ChunkGenerator, site: Dictionary) -> Dictionary:
	if Boats.is_boat(site):
		return Boats.crew(gen.seed, site)
	return generate(gen.seed, gen, site, gen.settlement_layout(site))

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
		elif ObjectLibrary.kind(it["t"]) == "structure" and not ObjectLibrary.TOWN_PROPS.has(it["t"]) and it["t"] != "bridge" and not KitBase.YARDS.has(it["t"]) and not Stronghold.has(it["t"]):
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
	_children(world_seed, era, sx, sz, homes, npcs)
	for p in npcs:
		var h2: Vector2 = p["home"]
		p["pos"] = Vector3(h2.x, gen.field.height(h2.x, h2.y), h2.y)
	var name := gen.field.region_name_at(c.x, c.y)
	return {
		"format": SETTLEMENT_FORMAT, "sx": sx, "sz": sz, "era": era, "center": c,
		"name": name, "npcs": npcs, "rumors": [], "sim_day": -1.0,
	}

## Households: some homes have children (4 to 17), who take after a grown-up living
## there. Rolled from their own random stream, so the grown-ups of every settlement are
## the same as before children existed. A child has rec["child"] = true and job "child":
## no trade, no shop, and nobody the player can hurt (NPCManager).
static func _children(world_seed: int, era: int, sx: int, sz: int, homes: Array, npcs: Array) -> void:
	if Eras.theme == "alien":
		return
	var r := WHash.rng(world_seed, sx, sz, 502)
	var grown := npcs.size()
	for h in homes:
		if h["t"] == "camp" or r.randf() > 0.35:
			continue
		var parent: Dictionary = {}
		for i in grown:
			if (npcs[i]["home"] as Vector2).distance_to(h["p"]) < 0.5:
				parent = npcs[i]
				break
		for k in (1 if r.randf() < 0.75 else 2):
			var c := _person(r, era, npcs.size(), sx, sz)
			c["child"] = true
			c["job"] = "child"
			c["age"] = r.randi_range(4, 17)
			if not parent.is_empty():
				# Their family's look and name.
				var pb: Dictionary = parent["body"]
				c["body"]["skin"] = pb["skin"]
				if r.randf() < 0.7:
					c["body"]["hair"] = pb["hair"]
				var fam := String(parent["name"]).split(" ", true, 1)
				if fam.size() == 2:
					c["name"] = "%s %s" % [String(c["name"]).split(" ")[0], fam[1]]
			c["home"] = h["p"]
			var ang := r.randf() * TAU
			# They play about near home.
			c["work"] = (h["p"] as Vector2) + Vector2(cos(ang), sin(ang)) * r.randf_range(2.0, 6.0)
			c["work_yaw"] = r.randf() * TAU
			npcs.append(c)

## A new person of the settlement (shops hire newcomers when nobody fits).
static func person(r: RandomNumberGenerator, era: int, idx: int, sx: int, sz: int) -> Dictionary:
	return _person(r, era, idx, sx, sz)

## Alien worlds' people (Eras.theme "alien"): the Sylvari of the fey wilds and the
## Vex of the xeno tech cities, tall and slight, with skin and hair no human has.
const ALIEN_SKIN := [Color(0.42, 0.6, 0.78), Color(0.55, 0.42, 0.72), Color(0.38, 0.62, 0.5), Color(0.68, 0.7, 0.76), Color(0.3, 0.42, 0.62), Color(0.62, 0.5, 0.4)]
const ALIEN_HAIR := [Color(0.92, 0.94, 0.98), Color(0.3, 0.75, 0.75), Color(0.55, 0.3, 0.75), Color(0.12, 0.14, 0.3), Color(0.85, 0.55, 0.25)]
const ALIEN_FIRST := ["Zhar", "Vexil", "Quorra", "Ixa", "Thessk", "Oru", "Nyx", "Kael", "Sorrin", "Yevra", "Tzal", "Iruun", "Xelia", "Vorn", "Ashka", "Pell"]
const ALIEN_LAST := ["of Hive Ruun", "Kh'tal", "Seventh-Spire", "Vael'ox", "Driftborn", "Nul-Arax", "of the Lattice", "Ossk"]
const RACES := ["Sylvari", "Vex"]

static func _person(r: RandomNumberGenerator, era: int, idx: int, sx: int, sz: int) -> Dictionary:
	var alien := Eras.theme == "alien"
	var first: String = FIRST[era][r.randi() % FIRST[era].size()]
	var last: String = LAST[era][r.randi() % LAST[era].size()]
	if alien and era == Eras.SCIFI:
		first = ALIEN_FIRST[r.randi() % ALIEN_FIRST.size()]
		last = ALIEN_LAST[r.randi() % ALIEN_LAST.size()]
	var cloth: Array = CLOTH[era]
	var body := {
		"height": r.randf_range(0.9, 1.08), "build": r.randf_range(0.85, 1.2), "female": r.randf() < 0.5,
		"skin": SKIN[r.randi() % SKIN.size()], "hair": HAIR[r.randi() % HAIR.size()],
		"hair_style": r.randi() % 4, "cloth": cloth[r.randi() % cloth.size()], "cloth2": cloth[r.randi() % cloth.size()],
	}
	if alien:
		# Drawn after the human rolls, so the rest of the person matches a human world's.
		body["skin"] = ALIEN_SKIN[r.randi() % ALIEN_SKIN.size()]
		body["hair"] = ALIEN_HAIR[r.randi() % ALIEN_HAIR.size()]
		body["height"] = float(body["height"]) * 1.08
		body["build"] = float(body["build"]) * 0.88
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
		"speech": SPEECH[era] + (", not quite human in turn of phrase" if alien else ""),
		"race": (RACES[1] if era == Eras.SCIFI else RACES[0]) if alien else "Human",
		"age": r.randi_range(18, 70),
		"hp": 100.0, "dead": false,
		"rel": 0, "met": 0, "mem": [], "goal": "", "mood": "calm",
		"pos": Vector3.ZERO, "yaw": r.randf() * TAU,
		"energy": r.randf_range(0.6, 1.0), "social": r.randf_range(0.3, 0.9),
	}

## One-line description used by both the built-in dialogue and the LLM prompt.
static func describe(p: Dictionary) -> String:
	var race := String(p.get("race", "Human"))
	if race != "Human":
		return "%s, a %d-year-old %s %s" % [p["name"], p["age"], race, p["job"]]
	return "%s, a %d-year-old %s %s" % [p["name"], p["age"], Eras.NAMES[p["era"]].to_lower(), p["job"]]
