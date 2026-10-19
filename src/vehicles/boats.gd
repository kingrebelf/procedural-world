class_name Boats
extends RefCounted
## Boats out on the water and the people who crew them. Each CELL of the world rolls once
## for a boat: wide open water (the sea, big lakes) often has one, a middling lake now and
## then, a pond never. What kind it is follows the land's era: rowboats, fishing boats and
## cogs off medieval shores, motor launches and research vessels with walk-in decks out on
## the human sci-fi frontier, and the odd castaway on a raft anywhere. Everything here is
## worked out from the world seed, so every player (and the server) agrees on where each
## boat is and who is aboard; the crew's records persist like a settlement's people.

const CELL := 640.0
## Settlement keys for crews: far outside any real settlement's cell, so crew records sit
## beside the towns' (people/<sx>_<sz>.dat, Net "t" keys) without ever meeting one.
const KEY_BASE := 1 << 24
const SPAWNED_BASE := 1 << 26 ## boats put in the water at runtime (Boats.spawn), not saved

## len: hull length (m). open: open water needed around the anchor (m radius).
## moves: m/s along its loop (0 = lies at anchor). rest: share of the time she lies at
## anchor between passages (rafts just drift). crew: [min, max] people.
## jobs: the crew's jobs, first is the skipper. walk_in: has decks and a cabin to go into.
const KINDS := {
	"raft": {"name": "Raft", "era": Eras.MEDIEVAL, "len": 3.4, "open": 40.0, "moves": 0.25, "crew": [1, 1], "jobs": ["castaway"]},
	# Small boats people build and paddle themselves (Sailing): not rolled for the lakes.
	"canoe": {"name": "Canoe", "era": Eras.MEDIEVAL, "len": 4.8, "open": 30.0, "moves": 0.0, "crew": [1, 2], "jobs": ["fisher", "fisher"]},
	"kayak": {"name": "Kayak", "era": Eras.MEDIEVAL, "len": 4.0, "open": 30.0, "moves": 0.0, "crew": [1, 1], "jobs": ["fisher"]},
	"sloop": {"name": "Sloop", "era": Eras.MEDIEVAL, "len": 9.0, "open": 60.0, "moves": 0.0, "crew": [1, 2], "jobs": ["sailor", "sailor"]},
	"rowboat": {"name": "Rowboat", "era": Eras.MEDIEVAL, "len": 4.4, "open": 40.0, "moves": 1.3, "rest": 0.35, "crew": [1, 2], "jobs": ["fisher", "fisher"]},
	"fishing_boat": {"name": "Fishing Boat", "era": Eras.MEDIEVAL, "len": 8.0, "open": 80.0, "moves": 2.6, "rest": 0.4, "crew": [2, 3], "jobs": ["fisher", "fisher", "deckhand"]},
	"cog": {"name": "Cog", "era": Eras.MEDIEVAL, "len": 20.0, "open": 130.0, "moves": 2.6, "rest": 0.3, "crew": [4, 6], "walk_in": true,
		"jobs": ["captain", "sailor", "sailor", "ship's cook", "deckhand", "lookout"]},
	"life_raft": {"name": "Life Raft", "era": Eras.SCIFI, "len": 3.0, "open": 60.0, "moves": 0.2, "crew": [1, 2], "jobs": ["castaway", "castaway"]},
	"launch": {"name": "Motor Launch", "era": Eras.SCIFI, "len": 7.5, "open": 80.0, "moves": 5.0, "rest": 0.3, "crew": [1, 2], "jobs": ["boat pilot", "fisher"]},
	"research_vessel": {"name": "Research Vessel", "era": Eras.SCIFI, "len": 26.0, "open": 150.0, "moves": 3.2, "rest": 0.45, "crew": [4, 6], "walk_in": true,
		"jobs": ["captain", "marine biologist", "ship engineer", "deckhand", "medic", "deckhand"]},
}
const SHIP_NAMES := [
	["Merry Wren", "Saint Brenna", "Grey Gull", "Cormorant", "Fair Maud", "Kingfisher", "Old Tom", "Heron's Luck",
		"Saltmarsh", "Willow", "Bonny Kate", "Wanderer", "Swan of Dunmere", "Second Chance", "Plover", "Ashford Lass"],
	["Moonwake", "Silverfin", "Mistral", "Thornbark", "Glimmer", "Elder Oak", "Starling", "Dawnrunner"],
	["Halcyon", "Meridian", "Tycho's Reach", "Calypso", "Nautilus", "Kepler Deep", "Blue Petrel", "Orca Two",
		"Cygnus Tide", "Lantern Fish", "Vega Drift", "Anemone", "Helix Station", "Deep Sounder", "Albatross", "Sea Lark"],
]
## Surveying a lake: a flood fill over a GRID metre lattice, up to SURVEY_MAX cells.
const GRID := 24.0
const SURVEY_MAX := 1600
const WET := -1.2 ## deeper than this (below sea level) counts as open water
## Lake sizes (m²): big waters (the biggest few lakes in any 10 km) nearly always have a
## boat, middling lakes now and then, small ones seldom, ponds never.
const BIG := 90000.0
const MID := 45000.0
const SMALL := 15000.0

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

## The boat of cell (cx, cz), or {} if it has none: {boat: kind, sx, sz, center (anchor),
## era, area, clear, loop (radius m), phase, name, faction, seed}. Safe on worker threads
## (it samples the terrain a lot: BoatManager runs it off the main thread and caches it).
static func plan(field: WorldField, cx: int, cz: int) -> Dictionary:
	if Eras.theme == "alien":
		return {} # no human boats out on the alien worlds' seas (yet)
	var seed := field.seed
	var r := WHash.rng(seed, cx, cz, 733)
	# The first deep spot on a coarse lattice over the cell, from a hashed corner.
	var start := Vector2.INF
	var off := r.randi() % 25
	for n in 25:
		var k := (n + off) % 25
		var p := Vector2((cx + (float(k % 5) + 0.5) / 5.0) * CELL, (cz + (float(k / 5) + 0.5) / 5.0) * CELL)
		if field.height(p.x, p.y) < -3.0:
			start = p
			break
	if start == Vector2.INF:
		return {}
	var sv := survey(field, start.x, start.y)
	var area: float = sv["area"]
	var anchor: Vector2 = sv["anchor"]
	# A lake spread over several cells is the boat of the cell its middle lies in.
	if area < SMALL or cell_of(anchor.x, anchor.y) != Vector2i(cx, cz):
		return {}
	var chance := 0.8 if area >= BIG else (0.45 if area >= MID else 0.12)
	if r.randf() >= chance:
		return {}
	var clear: float = sv["clear"]
	var era := WorldField.dominant(field.era_weights(anchor.x, anchor.y))
	var kind := _pick(r, era, area, clear)
	if kind == "":
		return {}
	var d: Dictionary = KINDS[kind]
	var ne: int = clampi(int(d["era"]), 0, 2)
	var names: Array = SHIP_NAMES[1 if era == Eras.FANTASY and ne == Eras.MEDIEVAL else ne]
	# Loops stay well clear of the shore (pose_at's wobble widens them by up to a tenth).
	var loop := 0.0
	if float(d["moves"]) > 0.0:
		loop = clampf(clear * 0.68 - float(d["len"]) * 0.5, 0.0, 200.0)
	return {"boat": kind, "sx": KEY_BASE + cx, "sz": KEY_BASE + cz, "cx": cx, "cz": cz, "center": anchor, "era": int(d["era"]),
		"land_era": era, "area": area, "clear": clear, "loop": loop, "phase": r.randf() * TAU, "dir": 1.0 if r.randf() < 0.5 else -1.0,
		"yaw": r.randf() * TAU, "name": names[r.randi() % names.size()], "faction": "folk", "seed": r.randi(),
		"outer": float(d["len"]) * 0.6 + 4.0}

## Kinds that fit a lake of `area` m² whose middle is `clear` m from any shore.
static func _pick(r: RandomNumberGenerator, era: int, area: float, clear: float) -> String:
	var tech := era == Eras.SCIFI
	var opts: Array = [] # [kind, weight]
	if area >= BIG:
		opts = [["research_vessel", 4.0], ["launch", 4.0], ["life_raft", 1.0]] if tech else [["cog", 4.0], ["fishing_boat", 4.0], ["raft", 1.0]]
	elif area >= MID:
		opts = [["launch", 6.0], ["life_raft", 1.0]] if tech else [["fishing_boat", 4.0], ["rowboat", 4.0], ["raft", 1.0]]
	else:
		opts = [["launch", 3.0], ["life_raft", 1.0]] if tech else [["rowboat", 5.0], ["raft", 1.0]]
	var fits: Array = opts.filter(func(o): return clear >= float(KINDS[o[0]]["len"]) * 0.5 + 10.0)
	if fits.is_empty():
		return ""
	var total := 0.0
	for o in fits:
		total += float(o[1])
	var x := r.randf() * total
	for o in fits:
		x -= float(o[1])
		if x <= 0.0:
			return o[0]
	return fits[-1][0]

## The lake at (x, z): {area (m², capped by SURVEY_MAX cells), anchor (its most open
## point), clear (m from there to the nearest shore)}. A flood fill on the GRID lattice,
## then a distance-from-shore pass.
static func survey(field: WorldField, x: float, z: float) -> Dictionary:
	var i0 := Vector2i(roundi(x / GRID), roundi(z / GRID))
	var wet := {} # cell -> true (water) / false (land)
	var is_wet := func(c: Vector2i) -> bool:
		if not wet.has(c):
			wet[c] = field.height(c.x * GRID, c.y * GRID) < WET
		return wet[c]
	if not is_wet.call(i0):
		return {"area": 0.0, "anchor": Vector2(x, z), "clear": 0.0}
	var water: Array = []
	var queue: Array = [i0]
	var seen := {i0: true}
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size() and water.size() < SURVEY_MAX:
		var c: Vector2i = queue[head]
		head += 1
		water.append(c)
		for d in dirs:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			seen[n] = true
			if is_wet.call(n):
				queue.append(n)
	# Distance from shore, breadth-first in from every water cell that touches land (past
	# the cap the unvisited cells aren't known, so a huge lake's cut edge isn't a shore).
	var in_lake := {}
	for c in water:
		in_lake[c] = true
	var dist := {}
	var front: Array = []
	for c in water:
		for d in dirs:
			var n: Vector2i = c + d
			if wet.has(n) and not wet[n]:
				dist[c] = 1
				front.append(c)
				break
	var fi := 0
	while fi < front.size():
		var c: Vector2i = front[fi]
		fi += 1
		for d in dirs:
			var n: Vector2i = c + d
			if in_lake.has(n) and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				front.append(n)
	var best: Vector2i = i0
	var bd := 0
	for c in water:
		var dv: int = dist.get(c, 0)
		if dv > bd or dv == bd and (c.x < best.x or c.x == best.x and c.y < best.y):
			bd = dv
			best = c
	if front.is_empty():
		bd = int(sqrt(float(water.size())) * 0.5) # no shore found: open water past the cap
	return {"area": float(water.size()) * GRID * GRID, "anchor": Vector2(best.x * GRID, best.y * GRID), "clear": (float(bd) - 0.5) * GRID}

## How far open water reaches round (x, z) in metres, roughly the distance to the
## nearest shore (0 on land or in the shallows). Quick: for picking a spot, not planning.
static func open_radius(field: WorldField, x: float, z: float) -> float:
	if field.height(x, z) > WET:
		return 0.0
	for rad in [20.0, 40.0, 70.0, 100.0, 140.0, 200.0, 280.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			if field.height(x + cos(a) * rad, z + sin(a) * rad) > WET:
				return rad * 0.8
	return 280.0

## Where the boat is at world time `t` (seconds) along its loop: [Vector2 position, yaw].
## Boats sail a passage round their loop, slowing to a stop, lie at anchor a while
## (swinging on the cable), then get under way again. Anchored boats only swing.
static func pose_at(site: Dictionary, t: float) -> Array:
	var d: Dictionary = KINDS[site["boat"]]
	var c: Vector2 = site["center"]
	var v := float(d["moves"])
	var loop := float(site.get("loop", 0.0))
	var ph := float(site["phase"])
	if v <= 0.0 or loop <= 0.0:
		var sw := sin(t * 0.021 + ph) * 0.18
		return [c, float(site["yaw"]) + sw]
	var dist := v * t
	var swing := 0.0
	var rf := float(d.get("rest", 0.0))
	if rf > 0.0:
		# Each cycle: S seconds sailing (speeding up and slowing down over T), R at anchor.
		var S := 180.0 + 120.0 * fposmod(ph * 7.3, 1.0)
		var R := S * rf / (1.0 - rf)
		var T := minf(clampf(float(d["len"]) * 1.2, 6.0, 30.0), S / 3.0)
		var n := floorf(t / (S + R))
		var r := t - n * (S + R)
		dist = n * v * (S - T)
		if r < T:
			dist += v * r * r / (2.0 * T)
		elif r < S - T:
			dist += v * (r - T * 0.5)
		elif r < S:
			dist += v * (S - T) - v * (S - r) * (S - r) / (2.0 * T)
		else:
			dist += v * (S - T)
			swing = sin(PI * (r - S) / R) * 0.2
	# An ellipse (wider one way) with a slow wobble, so the course isn't a perfect ring.
	var dir := float(site.get("dir", 1.0))
	var e := 0.65
	var a := ph + dir * dist / (loop * 0.83) # 0.83: the ellipse's mean radius
	var w := 1.0 + 0.1 * sin(2.0 * a + ph * 3.0)
	var dw := 0.2 * cos(2.0 * a + ph * 3.0)
	var p := c + Vector2(cos(a) * w, sin(a) * w * e).rotated(float(site["yaw"])) * loop
	var tan := Vector2(-sin(a) * w + cos(a) * dw, e * (cos(a) * w + sin(a) * dw)).rotated(float(site["yaw"])) * dir
	# Boats face -z: yaw is the heading's angle from -z.
	return [p, atan2(-tan.x, -tan.y) + swing]

## World seconds the boats run on: the in-game clock, so everyone online agrees.
static func world_time(day: float, day_seconds: float) -> float:
	return DayClock.world_seconds(fmod(day, 64.0), day_seconds)

## The boat's crew as a settlement record (NPCManager loads it like a town's people).
static func crew(world_seed: int, site: Dictionary) -> Dictionary:
	var kind: String = site["boat"]
	var d: Dictionary = KINDS[kind]
	var r := WHash.rng(world_seed, int(site["sx"]), int(site["sz"]), 734)
	var era: int = int(d["era"])
	var c: Vector2 = site["center"]
	var stations: Array = BoatModel.stations(kind)
	var cr: Array = d["crew"]
	var n := mini(r.randi_range(int(cr[0]), int(cr[1])), stations.size())
	var jobs: Array = d["jobs"]
	var npcs: Array = []
	var hostile := String(site.get("faction", "folk")) == "pirate"
	for i in n:
		var p := NPCGen.person(r, era, i, int(site["sx"]), int(site["sz"]))
		# Crews are grown-ups: if the generator ever hands back a child, draw again.
		for tries in 8:
			if not bool(p.get("child", false)):
				break
			p = NPCGen.person(r, era, i, int(site["sx"]), int(site["sz"]))
		p["job"] = "pirate" if hostile else String(jobs[i % jobs.size()])
		p["boat"] = kind
		p["station"] = i
		p["faction"] = site.get("faction", "folk")
		p["home"] = c
		p["work"] = c
		p["pos"] = Vector3(c.x, 0.0, c.y)
		if hostile:
			p["rel"] = -60
		npcs.append(p)
	var title := "the %s %s" % [String(d["name"]).to_lower(), site["name"]]
	match kind:
		"raft":
			title = "a castaway's raft"
		"life_raft":
			title = "a life raft from the %s" % site["name"]
	return {"format": NPCGen.SETTLEMENT_FORMAT, "sx": int(site["sx"]), "sz": int(site["sz"]), "era": era, "center": c,
		"name": title, "npcs": npcs, "rumors": [], "sim_day": -1.0, "boat": kind}

## People and towns the same: a settlement's record, generated the first time it's seen.
static func is_boat(site: Dictionary) -> bool:
	return site.has("boat")
