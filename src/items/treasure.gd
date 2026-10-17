class_name Treasure
## Treasure maps and the chests they lead to. A map is a rare find in caches and on the
## dead; picking it up chooses a spot MIN_DIST..MAX_DIST away on open, dry land and buries
## a chest there, DEPTH under the ground, holding LOOT_ROLLS caches' worth of that zone's
## loot. The hunt (where, what's in it, found or not) is kept with the player
## (Game.treasure); the chest, the mound of turned soil over it and any digging live in
## the chunk's snapshot like every other edit, so a chunk made long ago gets its chest too.
## Pure functions (no scene or autoload), so tests can call them.

## Parchment in the old kingdoms, a data chip out on the sci-fi frontier.
const MAPS := ["treasure_map", "treasure_chip"]
const MIN_DIST := 300.0
const MAX_DIST := 1000.0
## Odds a cache holds a map (rolled when it is first opened, so old saves get them too),
## and that a person carries one.
const CACHE_CHANCE := 0.06
const PERSON_CHANCE := 0.04
## How many ordinary caches' worth is in a buried chest, and how good each of them is.
const LOOT_ROLLS := [5, 6]
const LUCK := 0.3
## From the ground down to the chest's floor; it opens once the ground over its middle
## has been dug to within OPEN_AT of that floor.
const DEPTH := 1.5
const OPEN_AT := 0.6
## The heap of turned soil over the spot: radius and height in metres.
const MOUND_R := 1.9
const MOUND_H := 0.2
## The chest is kept this far inside its chunk, so the mound and the dig stay in one chunk.
const EDGE := 5.0
const XP := 120.0

static func is_map(type) -> bool:
	return type is String and MAPS.has(type)

static func map_for(era: int) -> String:
	return MAPS[1] if era == Eras.SCIFI else MAPS[0]

static func make_map(era: int, origin: Dictionary) -> Dictionary:
	return ItemDB.make(map_for(era), 1, 1.0, origin)

## A dry, open spot MIN_DIST..MAX_DIST from `from`: above the water, off rivers and away
## from towns and strongholds. The last try if none is found.
static func pick_spot(gen: ChunkGenerator, from: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var p := from
	for i in 48:
		p = from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(MIN_DIST, MAX_DIST)
		if open_land(gen, p):
			return p
	return p

static func open_land(gen: ChunkGenerator, p: Vector2) -> bool:
	if gen.field.height(p.x, p.y) < ChunkGenerator.WATER_LEVEL + 2.0:
		return false
	if gen.rivers and gen.field.river_t(p.x, p.y) < 2.5:
		return false
	for s in gen.settlements_near(p.x - 1.0, p.y - 1.0, p.x + 1.0, p.y + 1.0):
		if p.distance_to(s["center"]) < float(s["outer"]) + 25.0:
			return false
	for f in gen.forts_near(p.x - 1.0, p.y - 1.0, p.x + 1.0, p.y + 1.0):
		if p.distance_to(f["center"]) < Stronghold.OUTER + 10.0:
			return false
	return true

## Five or six caches' worth of loot from the land the chest lies in, stacks merged.
static func roll_loot(era: int, rng: RandomNumberGenerator, chunk: Vector2i) -> Array:
	var origin := {"chunk": chunk, "era": era, "how": "found"}
	var out: Array = []
	var marks := 0
	for n in rng.randi_range(LOOT_ROLLS[0], LOOT_ROLLS[1]):
		for it in ItemDB.roll_loot(era, rng, origin, LUCK):
			if it["type"] == "_marks":
				marks += int(it["qty"])
				continue
			var merged := false
			if ItemDB.is_stackable(it["type"]):
				for o in out:
					if o["type"] == it["type"]:
						o["qty"] = int(o["qty"]) + int(it["qty"])
						merged = true
						break
			if not merged:
				out.append(it)
	out.append({"type": "_marks", "qty": marks})
	return out

## A new hunt `id` from a map picked up at `from` on `planet`: where it lies, the era of
## that land and what the chest holds.
static func new_hunt(id: int, gen: ChunkGenerator, from: Vector2, planet: int, rng: RandomNumberGenerator) -> Dictionary:
	var p := pick_spot(gen, from, rng)
	var era := WorldField.dominant(gen.field.era_weights(p.x, p.y))
	var ck := Vector2i(floori(p.x / ChunkGenerator.SIZE), floori(p.y / ChunkGenerator.SIZE))
	return {"id": id, "planet": planet, "x": p.x, "z": p.y, "era": era, "level": Eras.zone_level(p.x, p.y),
		"loot": roll_loot(era, rng, ck), "found": false}

static func chunk_of(h: Dictionary) -> Vector2i:
	return Vector2i(floori(float(h["x"]) / ChunkGenerator.SIZE), floori(float(h["z"]) / ChunkGenerator.SIZE))

## The chest of hunt `id` in this chunk, or {}.
static func chest_in(chunk: Dictionary, id: int) -> Dictionary:
	for o in chunk["objects"]:
		if int(o["st"].get("treasure", -1)) == id:
			return o
	return {}

## Where in the chunk the chest goes (chunk-local, its floor DEPTH under the ground): the
## hunt's spot if the ground there is open, else the nearest open ground around it.
static func burial(chunk: Dictionary, h: Dictionary) -> Vector3:
	var x0 := float(chunk["cx"]) * ChunkGenerator.SIZE
	var z0 := float(chunk["cz"]) * ChunkGenerator.SIZE
	var lo := EDGE
	var hi := ChunkGenerator.SIZE - EDGE
	var c := Vector2(clampf(float(h["x"]) - x0, lo, hi), clampf(float(h["z"]) - z0, lo, hi))
	var best := c
	var found := false
	for ring in 9:
		var n := 1 if ring == 0 else ring * 6
		for k in n:
			var q := c + Vector2.from_angle(TAU * k / n + ring) * ring * 3.0
			if q.x < lo or q.x > hi or q.y < lo or q.y > hi:
				continue
			if _clear(chunk, q):
				best = q
				found = true
				break
		if found:
			break
	return Vector3(best.x, ChunkGenerator.height_at(chunk, best.x, best.y) - DEPTH, best.y)

static func _clear(chunk: Dictionary, q: Vector2) -> bool:
	if ChunkGenerator.height_at(chunk, q.x, q.y) < ChunkGenerator.WATER_LEVEL + 1.5:
		return false
	if ChunkGenerator.slope_at(chunk, q.x, q.y) > 0.45 or ChunkGenerator.by_river(chunk, q.x, q.y):
		return false
	if ChunkGenerator.road_at(chunk, q.x, q.y) > 0.05 or ChunkGenerator.in_cave(chunk, q.x, q.y):
		return false
	if ChunkGenerator.kept_out(ChunkGenerator.keep_out(chunk), q.x, q.y, 2.0):
		return false
	for o in chunk["objects"]:
		if o["st"].get("gone", false):
			continue
		var op: Vector3 = o["p"]
		if Vector2(op.x, op.z).distance_to(q) < 3.0 + 2.0 * float(o.get("s", 1.0)):
			return false
	return true

## Turns the soil over the chest: a low heap, bare earth showing through the grass.
static func dress(chunk: Dictionary, lp: Vector3) -> void:
	var R := ChunkGenerator.RES
	var hs: PackedFloat32Array = chunk["heights"]
	var rb: PackedByteArray = chunk.get("road", PackedByteArray())
	if rb.size() != R * R:
		rb = PackedByteArray()
		rb.resize(R * R)
	var r := MOUND_R + 0.6
	for j in range(maxi(0, int(lp.z - r)), mini(R - 1, int(lp.z + r) + 1) + 1):
		for i in range(maxi(0, int(lp.x - r)), mini(R - 1, int(lp.x + r) + 1) + 1):
			var d := Vector2(i - lp.x, j - lp.z).length()
			if d < MOUND_R:
				var f := 1.0 - (d * d) / (MOUND_R * MOUND_R)
				hs[j * R + i] += MOUND_H * f * f
			var soil := 1.0 - smoothstep(MOUND_R * 0.6, r, d)
			rb[j * R + i] = maxi(rb[j * R + i], int(soil * 210.0))
	chunk["heights"] = hs
	chunk["road"] = rb

## True while the chest is still under the ground (not dug down to yet).
static func covered(chunk: Dictionary, o: Dictionary) -> bool:
	if not o["st"].has("treasure"):
		return false
	var p: Vector3 = o["p"]
	return ChunkGenerator.height_at(chunk, p.x, p.z) > p.y + OPEN_AT

## What the map says, read from `from`: how far and which way, and what to look for.
static func hint(h: Dictionary, from: Vector3) -> String:
	if h.get("found", false):
		return "Whatever this map led to has been dug up."
	var to := Vector2(float(h["x"]) - from.x, float(h["z"]) - from.z)
	if to.length() < 12.0:
		return "It's here. Look for turned soil and dig with a pickaxe."
	return "The X lies about %d m %s (zone level %d). Look for turned soil and dig." % [snappedi(int(to.length()), 10), compass(to), int(h.get("level", 1))]

## "north", "south-west"... for a direction on the ground (north is -z).
static func compass(d: Vector2) -> String:
	const NAMES := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return NAMES[posmod(int(round(d.angle() / (PI / 4.0))), 8)]

## The map's own name for the place, by era.
static func marker_name(h: Dictionary) -> String:
	return "Cache signal" if int(h.get("era", 0)) == Eras.SCIFI else "Buried treasure"
