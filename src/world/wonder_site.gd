class_name WonderSite
## Wonders of the world: very rare places, far rarer than strongholds, that hold the best
## loot in the game and the hardest fights. At most one per CELL x CELL chunks, and only
## where the ground allows, so many cells have none:
##
##   Titan's Throne      (medieval)  a colossal stone king on a stepped dais
##   The Worldroot       (fantasy)   a tree the size of a tower, lanterns in its crown
##   Fallen Dreadnought  (sci-fi)    a warship that came down and never left
##   Starfall Gate       (any era)   a ring of rune stones round a door to elsewhere
##
## Each stands in a cleared plaza ringed by eight pillars, with a beam of light over it
## that can be seen from far off. Elite guards walk the plaza and a boss keeps the vault;
## the vault stays sealed until the boss is dead. A wonder sits wholly inside one chunk,
## so it is either generated with that chunk or not at all (no half wonders in old saves).

const CELL := 14 ## chunks per side of a wonder cell (about 900 m)
const CHANCE := 0.5 ## of a cell trying to hold one; the ground often says no
const GATE_CHANCE := 0.2 ## alien and older worlds; human worlds have no gates
const PLAZA := 19.0 ## level ground radius
const EDGE := 25.0 ## where the levelled ground meets the land again
const RING := 15.5 ## pillar ring radius
const CLEAR := 27.0 ## nothing else grows or stands this close

const TYPES := ["w_throne", "w_worldroot", "w_dreadnought", "w_gate"]
const NAMES := {"w_throne": "Titan's Throne", "w_worldroot": "The Worldroot", "w_dreadnought": "Fallen Dreadnought", "w_gate": "Starfall Gate"}
const BY_ERA := ["w_throne", "w_worldroot", "w_dreadnought"]
## How far in front of each centrepiece its vault stands (the boss a little further out).
const FRONT := {"w_throne": 8.2, "w_worldroot": 6.5, "w_dreadnought": 11.0, "w_gate": 4.0}
const PILLAR := {"w_throne": "w_column", "w_worldroot": "w_crystal", "w_dreadnought": "w_pylon", "w_gate": "w_obelisk"}
const LABELS := {
	"w_throne": "Titan's Throne", "w_worldroot": "The Worldroot", "w_dreadnought": "Fallen Dreadnought", "w_gate": "Starfall Gate",
	"w_column": "Titan's Column", "w_crystal": "Root Crystal", "w_pylon": "Dreadnought Pylon", "w_obelisk": "Star Obelisk",
}
const LORE := {
	"w_throne": "A king of the old giants, still keeping court",
	"w_worldroot": "Older than every forest it seeded",
	"w_dreadnought": "Its reactor still hums somewhere inside",
	"w_gate": "The stars on the far side are not ours",
	"w_column": "Carved by hands three times the size of yours",
	"w_crystal": "The Worldroot's sap, set hard as glass",
	"w_pylon": "Still trying to raise a shield",
	"w_obelisk": "Its runes turn as you watch",
}
## Light over each wonder, also its colour on the map.
const COLORS := {"w_throne": Color(1.0, 0.78, 0.38), "w_worldroot": Color(0.4, 1.0, 0.85),
	"w_dreadnought": Color(1.0, 0.35, 0.28), "w_gate": Color(0.78, 0.5, 1.0)}

## The boss of each wonder: [name, kit model, scale, tint, glow, drops].
const BOSSES := {
	"w_throne": ["The Throne Warden", "Bull", 2.5, Color(0.3, 0.24, 0.18), false, [["gold_idol", 3], ["silver_chalice", 2], ["hide", 6]]],
	"w_worldroot": ["The Elder Hart", "Stag", 2.2, Color(0.2, 0.55, 0.5), true, [["moonpearl", 3], ["aether_crystal", 8], ["rune_tablet", 2]]],
	"w_dreadnought": ["Hive Matriarch", "Alien_Scolitex", 3.0, Color(0.6, 0.12, 0.1), true, [["data_core", 3], ["void_gem", 2], ["power_cell", 6]]],
	"w_gate": ["The Gatekeeper", "Alien_Cyclop", 2.8, Color(0.45, 0.2, 0.7), true, [["void_gem", 3], ["moonpearl", 2], ["aether_crystal", 6]]],
}
## A boss's health and bite at zone level 1; like every guard it grows with its zone
## (Creature._zone_scale), so a level 40 wonder's boss has about 2700 hp.
const BOSS_HP := 480.0
const BOSS_BITE := 2.2 ## bite multiplier
const BOSS_ABOVE := 5 ## levels a boss stands above its zone
const LEGACY_BOSS_HP := 1500.0 ## older worlds (no zones): fixed
const LEGACY_BOSS_BITE := 3.6

static func has(t: String) -> bool:
	return LABELS.has(t)

static func is_centre(t: String) -> bool:
	return NAMES.has(t)

static func label(t: String) -> String:
	return LABELS.get(t, t)

static func lore(t: String) -> String:
	return LORE.get(t, "")

# --- Placement ------------------------------------------------------------------------

## The chunk of a cell that may hold a wonder, and the roll that decides it, or [] if the
## cell holds none.
static func cell_pick(seed: int, wx: int, wz: int) -> Array:
	if WHash.unit2(seed, wx, wz, 950) > CHANCE:
		return []
	var r := WHash.rng(seed, wx, wz, 951)
	r.randf() # a fresh WHash.rng's first draw is always near 0
	var k := Vector2i(wx * CELL + r.randi_range(2, CELL - 3), wz * CELL + r.randi_range(2, CELL - 3))
	return [k, r]

## Puts a wonder in `chunk` if this is the chosen chunk of its cell and the ground allows.
## Levels the plaza (inside the chunk only, so neighbours still meet it) and returns a
## site dictionary for the generator to keep everything else clear, or {}.
static func place(g: ChunkGenerator, chunk: Dictionary, sites: Array) -> Dictionary:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var pick := cell_pick(g.seed, int(floor(float(cx) / CELL)), int(floor(float(cz) / CELL)))
	if pick.is_empty() or pick[0] != Vector2i(cx, cz):
		return {}
	var r: RandomNumberGenerator = pick[1]
	const S := ChunkGenerator.SIZE
	var c := Vector2(S * 0.5 + r.randf_range(-3.0, 3.0), S * 0.5 + r.randf_range(-3.0, 3.0))
	var x0 := float(cx * S)
	var z0 := float(cz * S)
	# Dry, fairly level ground with no river, road or settlement on it.
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var n := 0
	for ring in [0.0, PLAZA * 0.5, PLAZA, EDGE - 1.0]:
		var steps := 1 if ring == 0.0 else 12
		for a in steps:
			var q: Vector2 = c + Vector2.from_angle(a * TAU / steps) * ring
			var h := ChunkGenerator.height_at(chunk, q.x, q.y)
			if ChunkGenerator.by_river(chunk, q.x, q.y) or ChunkGenerator.road_at(chunk, q.x, q.y) > 0.0:
				return {}
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if ring <= PLAZA:
				sum += h
				n += 1
	if hi - lo > 14.0 or lo < ChunkGenerator.WATER_LEVEL + 1.0:
		return {}
	var wc := Vector2(x0, z0) + c
	for s in sites:
		if wc.distance_to(s["center"]) < float(s.get("outer", s["inner"])) + CLEAR + 10.0:
			return {}
	var w := ChunkGenerator.weights_at(chunk, c.x, c.y)
	var era := WorldField.dominant(w)
	var gate := r.randf() < GATE_CHANCE and Eras.theme != "human"
	var t: String = "w_gate" if gate else BY_ERA[era]
	var yaw := r.randf() * TAU
	# v16: the Fallen Dreadnought lies at the end of the trench it ploughed, turned so the
	# trench runs clear of roads, rivers, water and towns (the old small wreck if no way is).
	var crash := {}
	if t == "w_dreadnought" and WorldField.terrain_v >= 16:
		crash = _plan_crash(g, wc, yaw, sum / n + 0.2)
		if not crash.is_empty():
			yaw = crash["yaw"]
	# (A crash site is no plaza: churned ground, no paving and no ring of pillars.)
	_level(g, chunk, c, sum / n + 0.2, crash.is_empty())
	if not crash.is_empty():
		scar(g, chunk, crash)
	var put := func(type: String, q: Vector2, face: float, st := {}) -> void:
		var p: Vector2 = c + q.rotated(-yaw)
		g._add(chunk, type, era, p.x, p.y, yaw + face, 1.0, st)
	put.call(t, Vector2.ZERO, 0.0, {"crash": true} if not crash.is_empty() else {})
	for i in 8:
		var a := (i + 0.5) * TAU / 8.0
		var q := Vector2.from_angle(a) * RING
		if not crash.is_empty():
			break
		put.call(PILLAR[t], q, -a + PI * 0.5)
	# The vault in front of the centrepiece, sealed by its boss; three lesser hoards.
	var boss_id := "%d_%d_wboss" % [cx, cz]
	var origin := {"chunk": Vector2i(cx, cz), "era": era, "how": "found"}
	var vault_loot := ItemDB.roll_loot(era, r, origin, 1.0)
	vault_loot.append_array(treasure(era, r, origin, Rarity.LEGENDARY, 2))
	vault_loot.append(treasure(era, r, origin, Rarity.EPIC, 1)[0])
	vault_loot.append({"type": "_marks", "qty": r.randi_range(1500, 3000)})
	var front: float = FRONT[t]
	put.call(Eras.CACHE_TYPES[era], Vector2(0, front), PI, {"loot": vault_loot, "opened": false, "wonder": t, "seal": boss_id})
	for i in 3:
		var a := PI * 0.5 + (i - 1) * 2.1 + r.randf_range(-0.2, 0.2)
		var q := Vector2.from_angle(a) * (RING - 3.0)
		var tumble := 0.0
		if not crash.is_empty():
			# Thrown out of the hull as it broke up: lying askew by the trench, each half
			# buried in the wreckage that came with it. (Their own draws, so the rolls after
			# stay as they were.)
			var rc := WHash.rng(g.seed, cx, cz, 964 + i)
			q = Vector2((1.0 if i % 2 == 0 else -1.0) * (CRASH_HALF + rc.randf_range(3.0, 8.0)), rc.randf_range(-18.0, 5.0))
			tumble = rc.randf_range(-0.9, 0.9)
			for dn in 3:
				var dq := q + Vector2.from_angle(rc.randf() * TAU) * rc.randf_range(1.2, 2.6)
				var dp: Vector2 = c + dq.rotated(-yaw)
				if dp.x < 0.5 or dp.y < 0.5 or dp.x > S - 0.5 or dp.y > S - 0.5:
					continue
				g._add(chunk, DEBRIS, Eras.SCIFI, dp.x, dp.y, rc.randf() * TAU, 1.0, {}, 1 + rc.randi() % 6, rc.randi() % 2)
		var loot := ItemDB.roll_loot(era, r, origin, 0.9)
		loot.append_array(treasure(era, r, origin, Rarity.EPIC, 1))
		put.call(Eras.CACHE_TYPES[era] if r.randf() < 0.7 else Eras.CACHE_TYPES[r.randi() % Eras.COUNT], q, r.randf() * TAU + tumble, {"loot": loot, "opened": false, "wonder": t})
	# Elite guards round the ring and the boss before the vault.
	if not chunk.has("guards"):
		chunk["guards"] = []
	var guards := 4 + r.randi_range(0, 2)
	for i in guards:
		var a := i * TAU / guards + r.randf_range(-0.2, 0.2)
		if not crash.is_empty():
			a = (i + 0.5) * PI / guards # on the open half of the plaza, not in the hull
		var p := c + (Vector2.from_angle(a) * r.randf_range(9.0, 12.0)).rotated(-yaw)
		chunk["guards"].append({"id": "%d_%d_w%d" % [cx, cz, i], "lx": p.x, "lz": p.y, "tier": 4 + int(r.randf() < 0.4), "era": era})
	var bp := c + Vector2(0, front + 3.0).rotated(-yaw)
	chunk["guards"].append({"id": boss_id, "lx": bp.x, "lz": bp.y, "tier": 100 + TYPES.find(t), "era": era})
	chunk["wonder"] = {"t": t, "lx": c.x, "lz": c.y, "era": era, "boss": boss_id}
	if not crash.is_empty():
		chunk["wonder"]["crash"] = crash
		strew(g, chunk, crash)
	return {"center": wc, "inner": CLEAR, "outer": CLEAR, "wonder": t}

## Flattens the plaza to `h`, easing back into the land by EDGE, and paves it if `paved`.
static func _level(g: ChunkGenerator, chunk: Dictionary, c: Vector2, h: float, paved := true) -> void:
	const R := ChunkGenerator.RES
	var hs: PackedFloat32Array = chunk["heights"]
	for j in range(maxi(1, int(c.y - EDGE) - 1), mini(R - 1, int(c.y + EDGE) + 2)):
		for i in range(maxi(1, int(c.x - EDGE) - 1), mini(R - 1, int(c.x + EDGE) + 2)):
			var d := Vector2(i, j).distance_to(c)
			if d < EDGE:
				var k := j * R + i
				hs[k] = lerpf(hs[k], h, 1.0 - smoothstep(PLAZA, EDGE, d))
	chunk["heights"] = hs
	if not paved:
		return
	# The plaza is paved (v4 worlds keep a road surface mask).
	if g.towns and not chunk.has("road"):
		var empty := PackedByteArray()
		empty.resize(R * R)
		chunk["road"] = empty
	if chunk.has("road"):
		var rb: PackedByteArray = chunk["road"]
		for j in R:
			for i in R:
				var d := Vector2(i, j).distance_to(c)
				if d < PLAZA:
					rb[j * R + i] = maxi(rb[j * R + i], int(255.0 * (1.0 - smoothstep(PLAZA - 6.0, PLAZA - 1.0, d))))
		chunk["road"] = rb

## `n` pieces of gear of at least rank `floor`, from everything the era has.
static func treasure(era: int, r: RandomNumberGenerator, origin: Dictionary, floor_rank: int, n: int) -> Array:
	var out: Array = []
	# Wonders keep only gear worth the trip: no cloth caps or stone axes.
	var pool: Array = ItemDB.GEAR_LOOT[era].filter(func(t): return int(ItemDB.def(t).get("value", 0)) >= 40)
	for i in n:
		var it := ItemDB.make(pool[r.randi() % pool.size()], 1, r.randf_range(1.2, 1.5), origin)
		var rank := maxi(floor_rank, Rarity.roll(r, 1.0))
		if floor_rank >= Rarity.LEGENDARY and r.randf() < 0.3:
			rank = Rarity.MYTHIC
		Rarity.apply(it, rank, r)
		out.append(it)
	return out

## True while the boss that seals this vault still lives.
static func sealed(chunk: Dictionary, o: Dictionary) -> bool:
	var id := String(o["st"].get("seal", ""))
	return id != "" and not chunk.get("fauna_dead", {}).has(id)

## What the map knows of a chunk's wonder: {t, x, z, era, cleared} in world space, or {}.
static func of_chunk(chunk: Dictionary) -> Dictionary:
	if not chunk.has("wonder"):
		return {}
	var w: Dictionary = chunk["wonder"]
	var cleared: bool = chunk.get("fauna_dead", {}).has(w["boss"])
	if cleared:
		for o in chunk["objects"]:
			if String(o["st"].get("seal", "")) != "" and not o["st"].get("opened", false):
				cleared = false
	return {"t": w["t"], "x": chunk["cx"] * ChunkGenerator.SIZE + float(w["lx"]), "z": chunk["cz"] * ChunkGenerator.SIZE + float(w["lz"]),
		"era": w["era"], "cleared": cleared}

# --- The Fallen Dreadnought's crash site (v16) -----------------------------------------
## The warship came in low along its local -z, touched down up to CRASH_LEN metres back
## and ploughed a trench to where it lies, nose by the vault. The scar reaches into the
## chunks round the wonder's: each carves the same trench (crash_ground is a function of
## the world alone, so the chunks meet), scorches the same sand and strews the wreckage
## that landed in it.

const CRASH_LEN := 160.0 ## longest trench, touchdown to the plaza's middle
const CRASH_MIN := 64.0 ## shorter than this and the old wreck lies there instead
const CRASH_HALF := 14.0 ## half-width of the trench floor by the hull
const CRASH_NOSE := 4.0 ## where the trench ends, a little past the plaza's middle
const CRASH_REACH := 3 ## chunks from the wonder's chunk the scar can reach
const CRASH_HULL := 66.0 ## how far back from the nose the hull lies
const DEBRIS := "crash_debris"
const TRUNK := "crash_trunk" ## a tree the crash snapped and scorched, lying where it fell

static var _crash_lock := Mutex.new()
static var _crashes := {}

## The way in for a dreadnought at wc on a plaza at height hb: the first of twelve
## headings (from yaw0) whose trench runs CRASH_LEN on dry land, clear of rivers, roads,
## towns and steep ground, else the one that runs furthest. {} if none runs CRASH_MIN.
static func _plan_crash(g: ChunkGenerator, wc: Vector2, yaw0: float, hb: float) -> Dictionary:
	var box := Rect2(wc, Vector2.ZERO).grow(CRASH_LEN + 40.0)
	var roads := g.roads_near(box.position.x, box.position.y, box.end.x, box.end.y)
	var towns: Array = g.settlements_near(box.position.x, box.position.y, box.end.x, box.end.y)
	towns.append_array(g.forts_near(box.position.x, box.position.y, box.end.x, box.end.y))
	var best := 0.0
	var best_yaw := yaw0
	for i in 12:
		var yw := yaw0 + i * TAU / 12.0
		var run := 0.0
		var v := -8.0
		while v >= -CRASH_LEN:
			var ok := true
			for u in [-CRASH_HALF - 8.0, 0.0, CRASH_HALF + 8.0]:
				var p: Vector2 = wc + Vector2(u, v).rotated(-yw)
				var h := g.field.height(p.x, p.y)
				ok = ok and h > ChunkGenerator.WATER_LEVEL + 1.0 and absf(h - hb) < 16.0
				ok = ok and not (g.rivers and g.field.river_t(p.x, p.y) < WorldField.RIVER_REACH + 2.0)
				for st in towns:
					ok = ok and p.distance_to(st["center"]) > float(st.get("outer", st.get("inner", 40.0))) + 12.0
				for rd in roads:
					ok = ok and _road_gap(rd, p) > ChunkGenerator.ROAD_HALF + 10.0
			if not ok:
				break
			run = -v
			v -= 8.0
		if run > best + 0.5:
			best = run
			best_yaw = yw
		if best >= CRASH_LEN:
			break
	if best < CRASH_MIN:
		return {}
	var tp := wc + Vector2(0, -best).rotated(-best_yaw)
	return {"x": wc.x, "z": wc.y, "yaw": wrapf(best_yaw, 0.0, TAU), "hb": hb, "len": best,
		"gl": g.field.height(tp.x, tp.y), "ph": fposmod(wc.x * 0.0137 + wc.y * 0.0191, TAU)}

static func _road_gap(rd: Dictionary, p: Vector2) -> float:
	var pts := ChunkGenerator.road_pts(rd)
	var seg := ChunkGenerator._road_seg(pts, p)
	var i := int(seg.x)
	return p.distance_to(pts[i].lerp(pts[mini(i + 1, pts.size() - 1)], seg.y))

## (across, along) of world point (x, z) in the crash's frame: along runs from the
## touchdown (-len) to the plaza's middle (0).
static func _crash_q(cr: Dictionary, x: float, z: float) -> Vector2:
	return (Vector2(x, z) - Vector2(cr["x"], cr["z"])).rotated(cr["yaw"])

## Ground height h at world (x, z) once the dreadnought has ploughed through: a graded
## trench with a flat floor and steep sides, widening and deepening toward the hull, and
## the spoil it threw heaped along both lips. The same in every chunk.
static func crash_ground(cr: Dictionary, x: float, z: float, h: float) -> float:
	var q := _crash_q(cr, x, z)
	var L: float = cr["len"]
	if q.y < -L - 6.0 or q.y > CRASH_NOSE + 16.0 or absf(q.x) > CRASH_HALF + 50.0:
		return h
	var t := clampf((q.y + L) / L, 0.0, 1.0)
	var dig := smoothstep(0.0, 0.2, t)
	# It skidded in on a slight curve, straightening as it slowed.
	var u := absf(q.x - sin(q.y * 0.045 + float(cr["ph"])) * 3.0 * (1.0 - t))
	var wb := lerpf(2.5, CRASH_HALF, sqrt(t))
	var fl := lerpf(float(cr["gl"]), float(cr["hb"]), t) - (1.0 + 4.0 * t) * dig + (1.0 - dig) * 3.0
	if q.y > CRASH_NOSE:
		fl += (q.y - CRASH_NOSE) * 1.3
	var cut := fl + maxf(0.0, u - wb) * 1.1
	if h > cut:
		return cut
	var lip := wb + maxf(0.0, h - fl) / 1.1
	var bank := (0.6 + 3.4 * t) * dig * (1.0 - smoothstep(CRASH_NOSE, CRASH_NOSE + 10.0, q.y))
	var d := u - lip
	# Lumpy, as thrown earth is.
	var lump := 0.75 + 0.5 * sin(q.y * 0.31 + u * 0.7 + float(cr["ph"]) * 3.0) * sin(q.y * 0.17 - u * 0.4)
	return h + bank * lump * smoothstep(0.0, 2.0, d) * exp(-pow((d - 3.0) / (4.0 + 4.0 * t), 2.0))

## How scorched the ground is at world (x, z), 0..1: the trench and its banks, worst by
## the hull, and a burn round where it came to rest (the shader glasses the worst of it).
static func scorch(cr: Dictionary, x: float, z: float) -> float:
	var q := _crash_q(cr, x, z)
	var L: float = cr["len"]
	if q.y < -L - 6.0 or q.y > CRASH_NOSE + 60.0 or absf(q.x) > CRASH_HALF + 60.0:
		return 0.0
	var t := clampf((q.y + L) / L, 0.0, 1.0)
	# A ragged edge: tongues of soot licking out into the grass and bays left unburnt.
	var wob := (sin(x * 0.11 + 1.7 * sin(z * 0.07)) + sin(z * 0.13 + 1.3 * sin(x * 0.09 + 2.0)) + 0.6 * sin((x + z) * 0.31)) * 0.4
	var wb := lerpf(2.5, CRASH_HALF, sqrt(t))
	var trench := (1.0 - smoothstep(wb + 2.0, wb + 9.0 + 8.0 * t, absf(q.x) + wob * 6.0)) * smoothstep(0.02, 0.25, t)
	trench *= lerpf(0.5, 1.0, t) * (1.0 - smoothstep(CRASH_NOSE, CRASH_NOSE + 8.0, q.y + wob * 5.0))
	var burn := 1.0 - smoothstep(14.0, 50.0, Vector2(q.x * 0.75, q.y + 26.0).length() + wob * 12.0)
	return clampf(maxf(trench, burn * 0.9), 0.0, 1.0)

## The crash's mark on a chunk: the trench and its banks in the heights, scorched ground in
## the look (byte 10), the paving gone where the trench cuts the plaza, and the whole scar
## kept clear of trees, boulders and the rest.
static func scar(g: ChunkGenerator, chunk: Dictionary, cr: Dictionary) -> void:
	const R := ChunkGenerator.RES
	const S := ChunkGenerator.SIZE
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	var hs: PackedFloat32Array = chunk["heights"]
	var rb: PackedByteArray = chunk.get("road", PackedByteArray())
	for j in R:
		for i in R:
			var k := j * R + i
			var h1 := crash_ground(cr, x0 + i, z0 + j, hs[k])
			if h1 < hs[k] - 0.3 and not rb.is_empty():
				rb[k] = 0
			hs[k] = h1
	chunk["heights"] = hs
	if not rb.is_empty():
		chunk["road"] = rb
	const N := ChunkGenerator.LOOK_N
	const B := ChunkGenerator.LOOK_BYTES
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	for j in N:
		for i in N:
			var a := scorch(cr, x0 + i * ChunkGenerator.LOOK_STEP, z0 + j * ChunkGenerator.LOOK_STEP)
			if a <= 0.004:
				continue
			if lb.is_empty():
				lb.resize(N * N * B)
			var at := (j * N + i) * B + 10
			lb[at] = maxi(lb[at], int(round(a * 255.0)))
	if not lb.is_empty():
		chunk["look"] = lb
	var ko: PackedFloat32Array = chunk.get("keep_out", PackedFloat32Array())
	ko.append_array([float(cr["x"]) - x0, float(cr["z"]) - z0, float(cr["yaw"]),
		-CRASH_HALF - 14.0, -float(cr["len"]) - 4.0, CRASH_HALF + 14.0, CRASH_NOSE + 6.0])
	chunk["keep_out"] = ko

## The wreckage strewn along the trench and flung round the hull, as
## {q (across, along), sp, v, yaw}: the same list for every chunk.
static func wreckage(seed: int, cr: Dictionary) -> Array:
	var r := WHash.rng(seed, int(floor(float(cr["x"]))), int(floor(float(cr["z"]))), 961)
	r.randf()
	var L: float = cr["len"]
	var out: Array = []
	for i in 56:
		var v := -lerpf(10.0, L, pow(r.randf(), 1.4))
		var t := (v + L) / L
		var wb := lerpf(2.5, CRASH_HALF, sqrt(t))
		var u := (1.0 if r.randf() < 0.5 else -1.0) * r.randf_range(0.0, wb + 20.0)
		var sp := 1 + r.randi() % 6
		var size := r.randi() % 3
		var yaw := r.randf() * TAU
		# Not inside the hull itself.
		if absf(u) < CRASH_HALF and v > -CRASH_HULL - 4.0:
			continue
		out.append({"q": Vector2(u, v), "sp": sp, "v": size, "yaw": yaw})
	for i in 10:
		var a := r.randf_range(0.2, PI - 0.2)
		var q := Vector2.from_angle(a) * r.randf_range(30.0, 58.0)
		out.append({"q": q, "sp": 5 + r.randi() % 2, "v": r.randi() % 2, "yaw": r.randf() * TAU})
	return out

## Puts the wreckage of crash `cr` that lies in this chunk.
static func strew(g: ChunkGenerator, chunk: Dictionary, cr: Dictionary) -> void:
	const S := ChunkGenerator.SIZE
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	var c := Vector2(cr["x"], cr["z"])
	for w in wreckage(g.seed, cr):
		var p: Vector2 = c + (w["q"] as Vector2).rotated(-float(cr["yaw"]))
		if not ChunkGenerator._inside(p, x0, z0):
			continue
		var lx := p.x - x0
		var lz := p.y - z0
		if ChunkGenerator.height_at(chunk, lx, lz) < ChunkGenerator.WATER_LEVEL + 0.3 or ChunkGenerator.road_at(chunk, lx, lz) > 0.0 or ChunkGenerator.by_river(chunk, lx, lz):
			continue
		g._add(chunk, DEBRIS, Eras.SCIFI, lx, lz, float(w["yaw"]), 1.0, {}, int(w["sp"]), int(w["v"]))

## How hard the crash hit the land at world (x, z), 0..1: the blast along both sides of
## the trench and round where the hull came to rest, past the scar itself (trees there
## were snapped and scorched).
static func blast(cr: Dictionary, x: float, z: float) -> float:
	var q := _crash_q(cr, x, z)
	var L: float = cr["len"]
	if q.y < -L - 12.0 or q.y > CRASH_NOSE + 50.0 or absf(q.x) > CRASH_HALF + 50.0:
		return 0.0
	var t := clampf((q.y + L) / L, 0.0, 1.0)
	var wob := (sin(x * 0.17 + 1.3 * sin(z * 0.11)) + sin(z * 0.19 + 1.1 * sin(x * 0.13 + 1.0))) * 0.5
	var wb := lerpf(2.5, CRASH_HALF, sqrt(t))
	var side := (1.0 - smoothstep(wb + 6.0, wb + 16.0 + 10.0 * t, absf(q.x) + wob * 5.0)) * smoothstep(0.0, 0.2, t)
	side *= 1.0 - smoothstep(CRASH_NOSE + 6.0, CRASH_NOSE + 24.0, q.y)
	var rest := 1.0 - smoothstep(28.0, 46.0, Vector2(q.x * 0.8, q.y + 24.0).length() + wob * 8.0)
	return clampf(maxf(side, rest), 0.0, 1.0)

## Knocks down the trees of this chunk the crash blast reached: each becomes a scorched
## trunk lying blown outward and onward from the trench, its stump beside it.
static func fell(g: ChunkGenerator, chunk: Dictionary, crashes: Array) -> void:
	if crashes.is_empty():
		return
	const S := ChunkGenerator.SIZE
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) != "tree":
			continue
		var p: Vector3 = o["p"]
		var wx := x0 + p.x
		var wz := z0 + p.z
		for cr in crashes:
			var b := blast(cr, wx, wz)
			var roll := WHash.unit2(g.seed, int(floor(wx * 4.0)), int(floor(wz * 4.0)), 963)
			if b <= 0.0 or roll > b * 1.4:
				continue
			var q := _crash_q(cr, wx, wz)
			var dq := Vector2(signf(q.x) if absf(q.x) > 0.5 else 1.0, 0.8 + roll).normalized()
			var d := dq.rotated(-float(cr["yaw"]))
			o["v"] = 1 if o["t"] == "pine" else 0
			o["t"] = TRUNK
			o["e"] = Eras.MEDIEVAL
			o["r"] = atan2(d.x, d.y) + (roll - 0.5) * 0.6
			o["st"] = {}
			o["sp"] = 1 + int(roll * 997.0)
			break

## Crashes of nearby chunks whose scar can reach chunk (cx, cz) (not its own).
static func crashes_near(g: ChunkGenerator, cx: int, cz: int) -> Array:
	var out: Array = []
	if WorldField.terrain_v < 16:
		return out
	for wz in range(floori(float(cz - CRASH_REACH) / CELL), floori(float(cz + CRASH_REACH) / CELL) + 1):
		for wx in range(floori(float(cx - CRASH_REACH) / CELL), floori(float(cx + CRASH_REACH) / CELL) + 1):
			var pick := cell_pick(g.seed, wx, wz)
			if pick.is_empty():
				continue
			var k: Vector2i = pick[0]
			if k == Vector2i(cx, cz) or maxi(absi(k.x - cx), absi(k.y - cz)) > CRASH_REACH:
				continue
			var cr := crash_of(g, k)
			if not cr.is_empty():
				out.append(cr)
	return out

## The crash in chunk k, or {} if its wonder is none or not a crashed dreadnought. Found
## by generating that chunk (once per world; a dreadnought only stands in sci-fi land).
static func crash_of(g: ChunkGenerator, k: Vector2i) -> Dictionary:
	var key := "%d:%d:%d:%d:%s:%d" % [g.seed, k.x, k.y, WorldField.terrain_v, Eras.theme, int(g.rivers)]
	_crash_lock.lock()
	var have = _crashes.get(key)
	_crash_lock.unlock()
	if have != null:
		return have
	var cr := {}
	const S := ChunkGenerator.SIZE
	if g.field.era_weights((k.x + 0.5) * S, (k.y + 0.5) * S)[Eras.SCIFI] > 0.25:
		var ch := g.generate(k.x, k.y)
		cr = ch.get("wonder", {}).get("crash", {})
	_crash_lock.lock()
	if _crashes.size() > 512:
		_crashes.clear()
	_crashes[key] = cr
	_crash_lock.unlock()
	return cr

# --- Meshes ---------------------------------------------------------------------------

static var _beams := {}
## Mesh key suffix for a wonder built for a human world: glowing glyphs, shards and inlays
## become carved stone, gold and plain glinting glass (Ben: nothing glows on human worlds).
const CALM := "@calm"
const CALM_MATS := {"titan_glow": "titan_stone", "starfall_glass": "starfall_glass_dull",
	"void_stone": "void_stone_dull", "glow_violet": "gold", "glow_red": "gold", "glow_teal": "gold",
	"glow_warm": "gold", "glow_cyan": "panel", "crystal": "glass", "crystal_violet": "glass"}
static var _portal: Material

## Mesh key suffix for a Fallen Dreadnought lying at the end of its trench (v16).
const CRASH := "@crash"

## The mesh key of a placed wonder piece: crashed or not, calm on human worlds.
static func mesh_key(o: Dictionary) -> String:
	var key: String = o["t"]
	if o.get("st", {}).get("crash", false):
		key += CRASH
	# On human worlds a wonder wears carved and inlaid stone, nothing that glows.
	if Eras.theme == "human":
		key += CALM
	return key

## The key of the mesh a wonder piece collides with (no light, any material).
static func solid_key(o: Dictionary) -> String:
	return String(o["t"]) + (CRASH if o.get("st", {}).get("crash", false) else "") + "~solid"

static func _base_key(key: String) -> String:
	return key.trim_suffix("~solid").trim_suffix(CALM).trim_suffix(CRASH)

static func owns_key(key: String) -> bool:
	return has(_base_key(key))

static func build_key(key: String) -> ArrayMesh:
	var solid := key.ends_with("~solid")
	var k := key.trim_suffix("~solid")
	var calm := k.ends_with(CALM)
	k = k.trim_suffix(CALM)
	var crash := k.ends_with(CRASH)
	return build(k.trim_suffix(CRASH), solid, calm, crash)

## The mesh of a wonder piece. `solid` leaves out the light (for collision); `crash` is
## the v16 Fallen Dreadnought, full size in its trench.
static func build(t: String, solid := false, calm := false, crash := false) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(t)
	var I := Transform3D.IDENTITY
	var out: ArrayMesh = null
	match t:
		"w_throne": _throne(k, r)
		"w_worldroot": _worldroot(k, r)
		"w_dreadnought": out = _crashed(k, r, calm or solid) if crash else _dreadnought(k, r)
		"w_gate": _gate(k, r, solid)
		"w_column":
			k.box("titan_glow", I.translated(Vector3(0, 0.3, 0)), Vector3(2.0, 0.6, 2.0))
			k.box("titan_stone", I.translated(Vector3(0, -1.5, 0)), Vector3(2.0, 3.0, 2.0))
			k.cylinder("titan_stone", I.translated(Vector3(0, 0.6, 0)), 0.62, 0.52, 6.2, 10, false, 0.03, 3)
			k.cylinder("gold", I.translated(Vector3(0, 2.4, 0)), 0.66, 0.66, 0.18, 10, false)
			k.box("titan_stone", I.translated(Vector3(0, 6.95, 0)), Vector3(1.6, 0.5, 1.6))
			k.cylinder("iron", I.translated(Vector3(0, 7.2, 0)), 0.5, 0.65, 0.5, 8)
			k.sphere("glow_warm", I.translated(Vector3(0, 7.75, 0)), 0.36, 5, 8, 0.25)
			k.sphere("moss", I.translated(Vector3(0.5, 0.65, 0.4)), 0.5, 4, 7, 0.25, 0.4)
		"w_crystal":
			k.sphere("root_bark", I.translated(Vector3(0, 0.1, 0)), 1.3, 5, 9, 0.3, 0.45)
			k.crystal("crystal_violet", I, 0.6, 5.0, 6, 0.3)
			for i in 4:
				var a := i * TAU / 4.0 + 0.4
				var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.45)
				k.crystal("crystal", Transform3D(b, Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.7)), 0.28, r.randf_range(1.6, 2.6))
			k.sphere("glow_teal", I.translated(Vector3(0, 0.5, 0)), 0.32, 4, 6)
		"w_pylon":
			k.box("starfall_glass", I.translated(Vector3(0, -1.0, 0)), Vector3(2.2, 2.6, 2.2))
			k.box("panel", I.translated(Vector3(0, 0.3, 0)), Vector3(2.0, 0.6, 2.0))
			k.box("metal_dark", I.translated(Vector3(0, 3.6, 0)), Vector3(1.0, 6.0, 1.0))
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				k.box("glow_cyan", Transform3D(b, b * Vector3(0, 3.6, 0.51)), Vector3(0.12, 5.0, 0.03))
			k.box("panel", I.translated(Vector3(0, 6.75, 0)), Vector3(1.6, 0.3, 1.6))
			k.sphere("glow_red", I.translated(Vector3(0, 7.15, 0)), 0.22, 4, 6)
		"w_obelisk":
			k.box("void_stone", I.translated(Vector3(0, -1.0, 0)), Vector3(1.8, 2.4, 1.8))
			k.box("rune_stone", I.translated(Vector3(0, 0.25, 0)), Vector3(1.6, 0.5, 1.6))
			k.cylinder("void_stone", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.5, 0)), 0.8, 0.45, 6.0, 4, false)
			k.cylinder("void_stone", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 6.5, 0)), 0.45, 0.0, 1.0, 4, false)
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				for row in 4:
					k.box("glow_violet", Transform3D(b, b * Vector3(0, 1.3 + row * 1.25, 0.58 - row * 0.045)), Vector3(0.3, 0.5, 0.03))
	if is_centre(t):
		_vault_floor(k, FRONT[t])
	# The beam of light marks a wonder from afar on alien worlds; on human worlds nothing
	# glows, so it is found by its stone and gold (and the map).
	if not solid and is_centre(t) and not calm:
		_beam(k, t)
	return k.commit(_calm_mat if calm else _mat, out)

static func _calm_mat(name: String) -> Material:
	return _mat(CALM_MATS.get(name, name))

static func _mat(name: String) -> Material:
	if name.begins_with("beam_"):
		return _beam_mat(name.trim_prefix("beam_"))
	if name == "portal":
		return _portal_mat()
	return Materials.get_mat(name)

## The void-stone floor the vault and its keeper stand on, ringed with light.
static func _vault_floor(k: MeshKit, front: float) -> void:
	var at := Transform3D.IDENTITY.translated(Vector3(0, -0.4, front + 1.5))
	k.cylinder("void_stone", at, 4.4, 4.2, 0.5, 24)
	k.cylinder("glow_violet", at.translated(Vector3(0, 0.5, 0)), 4.22, 4.22, 0.03, 24)
	k.cylinder("void_stone", at.translated(Vector3(0, 0.5, 0)), 4.0, 4.0, 0.04, 24)

## A tall, soft column of light, brightest low down, so the wonder can be found from afar.
static func _beam(k: MeshKit, t: String) -> void:
	var I := Transform3D.IDENTITY
	var top: float = {"w_throne": 14.0, "w_worldroot": 30.0, "w_dreadnought": 10.0, "w_gate": 16.0}[t]
	k.cylinder("beam_" + t, I.translated(Vector3(0, top, 0)), 1.1, 0.5, 220.0, 10, false)
	k.cylinder("beam_" + t, I.translated(Vector3(0, top, 0)), 2.4, 1.4, 60.0, 12, false)

static func _beam_mat(t: String) -> Material:
	if _beams.has(t):
		return _beams[t]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	var c: Color = COLORS.get(t, Color.WHITE)
	m.albedo_color = Color(c.r, c.g, c.b, 0.16)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 6.0
	m.distance_fade_max_distance = 30.0
	_beams[t] = m
	return m

static func _portal_mat() -> Material:
	if _portal != null:
		return _portal
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.7, 0.45, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + r * 9.0 - TIME * 1.6) * 0.5 + 0.5;
	float rim = smoothstep(0.75, 1.0, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float core = (1.0 - r) * 0.5;
	float v = (swirl * 0.45 + core) * (1.0 - smoothstep(0.96, 1.0, r)) + rim * 1.5;
	ALBEDO = tint.rgb * v * 1.6;
	ALPHA = clamp(v, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_portal = m
	return m

## A cylinder from a to b (MeshKit cylinders run up local y).
static func _limb(k: MeshKit, mat: String, a: Vector3, b: Vector3, ra: float, rb: float, segs := 8) -> void:
	var d := b - a
	var up := d.normalized()
	var basis := Basis.IDENTITY
	if absf(up.y) < 0.999:
		basis = Basis(Vector3.UP.cross(up).normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	k.cylinder(mat, Transform3D(basis, a), ra, rb, d.length(), segs, true)

static func _throne(k: MeshKit, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	# The dais: three broad steps on a deep footing.
	k.box("void_stone", I.translated(Vector3(0, -2.0, 0)), Vector3(13.0, 4.0, 13.0))
	k.box("titan_stone", I.translated(Vector3(0, 0.3, 0)), Vector3(12.6, 0.6, 12.6))
	k.box("titan_stone", I.translated(Vector3(0, 0.9, -0.6)), Vector3(10.4, 0.6, 10.4))
	k.box("titan_glow", I.translated(Vector3(0, 1.5, -1.2)), Vector3(8.4, 0.6, 8.2))
	# The throne itself.
	k.box("titan_stone", I.translated(Vector3(0, 3.0, -1.8)), Vector3(6.4, 2.4, 4.0))
	k.box("titan_glow", I.translated(Vector3(0, 7.6, -4.2)), Vector3(7.0, 11.0, 1.4))
	k.cylinder("gold", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 12.0, -3.45)), 1.4, 1.4, 0.2, 16)
	for x in [-3.6, 3.6]:
		k.box("titan_stone", I.translated(Vector3(x, 4.8, -1.8)), Vector3(1.2, 1.2, 4.2))
		k.box("titan_stone", I.translated(Vector3(x, 3.0, -0.2)), Vector3(1.2, 2.4, 1.0))
		k.sphere("gold", I.translated(Vector3(x, 5.6, 0.2)), 0.45, 5, 8)
		k.cylinder("titan_stone", I.translated(Vector3(x * 0.95, 13.1, -4.2)), 0.55, 0.0, 2.0, 6)
	# The king: legs, a broad body, arms on a sword planted before him.
	for s in [-1.0, 1.0]:
		_limb(k, "titan_stone", Vector3(s * 1.2, 4.6, -2.2), Vector3(s * 1.25, 4.6, 1.2), 0.95, 0.85)
		_limb(k, "titan_stone", Vector3(s * 1.25, 4.4, 1.3), Vector3(s * 1.3, 1.8, 1.6), 0.8, 0.7)
		k.box("titan_stone", I.translated(Vector3(s * 1.3, 2.15, 2.2)), Vector3(1.3, 0.7, 2.2))
	k.box("titan_stone", I.translated(Vector3(0, 7.4, -2.4)), Vector3(4.6, 5.2, 2.6))
	k.box("cloth", I.translated(Vector3(0, 6.4, -1.05)), Vector3(4.2, 3.4, 0.08))
	k.box("gold", I.translated(Vector3(0, 5.0, -1.05)), Vector3(4.7, 0.4, 2.8))
	for s in [-1.0, 1.0]:
		k.sphere("titan_stone", I.translated(Vector3(s * 2.75, 9.6, -2.4)), 1.25, 6, 9)
		_limb(k, "titan_stone", Vector3(s * 2.9, 9.4, -2.2), Vector3(s * 2.4, 7.0, 0.4), 0.7, 0.6)
		_limb(k, "titan_stone", Vector3(s * 2.4, 7.0, 0.4), Vector3(s * 0.6, 8.0, 2.9), 0.6, 0.5)
		k.sphere("titan_stone", I.translated(Vector3(s * 0.55, 8.0, 3.0)), 0.55, 5, 7)
	k.cylinder("titan_stone", I.translated(Vector3(0, 9.9, -2.4)), 0.8, 0.75, 0.9, 10)
	k.sphere("titan_stone", I.translated(Vector3(0, 11.6, -2.3)), 1.35, 8, 10, 0.04, 1.1)
	k.box("titan_stone", Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 10.6, -1.25)), Vector3(1.3, 1.5, 0.6))
	k.cylinder("gold", I.translated(Vector3(0, 12.55, -2.3)), 1.15, 1.25, 0.6, 12, false)
	for i in 8:
		var a := i * TAU / 8.0
		k.cylinder("gold", I.translated(Vector3(cos(a) * 1.2, 13.1, -2.3 + sin(a) * 1.2)), 0.16, 0.0, 0.7, 4)
	k.sphere("glow_red", I.translated(Vector3(0, 12.9, -1.1)), 0.18, 4, 6)
	# The sword, point in the dais.
	k.box("iron", I.translated(Vector3(0, 4.9, 3.0)), Vector3(0.7, 6.2, 0.16))
	k.box("gold", I.translated(Vector3(0, 8.1, 3.0)), Vector3(2.8, 0.35, 0.45))
	k.cylinder("timber", I.translated(Vector3(0, 8.25, 3.0)), 0.18, 0.18, 1.3, 8)
	k.sphere("gold", I.translated(Vector3(0, 9.7, 3.0)), 0.32, 5, 8)
	# Braziers and moss of ages.
	for x in [-5.2, 5.2]:
		k.cylinder("iron", I.translated(Vector3(x, 0.6, 4.6)), 0.18, 0.18, 2.0, 6)
		k.cylinder("iron", I.translated(Vector3(x, 2.6, 4.6)), 0.3, 0.75, 0.5, 10)
		k.sphere("glow_warm", I.translated(Vector3(x, 3.15, 4.6)), 0.55, 5, 8, 0.3)
	for i in 9:
		var p := Vector3(r.randf_range(-3.5, 3.5), r.randf_range(2.0, 11.0), r.randf_range(-4.8, -1.5))
		k.sphere("moss", I.translated(p), r.randf_range(0.3, 0.7), 4, 7, 0.3, 0.35)

static func _worldroot(k: MeshKit, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("root_bark", I.translated(Vector3(0, -3.0, 0)), 3.8, 3.4, 3.0, 16, false, 0.12, 2)
	k.cylinder("root_bark", I, 3.4, 1.5, 26.0, 16, false, 0.18, 8)
	# Buttress roots arch out and dive into the plaza.
	for i in 9:
		var a := i * TAU / 9.0 + r.randf_range(-0.15, 0.15)
		var d := Vector3(cos(a), 0, sin(a))
		var reach := r.randf_range(7.5, 10.0)
		var prev := d * 2.6 + Vector3(0, 3.2, 0)
		for s in 6:
			var u := (s + 1) / 6.0
			var q := d * (2.6 + u * reach) + Vector3(0, 3.2 * (1.0 - u) + sin(u * PI) * 1.4 - u * 0.8, 0)
			_limb(k, "root_bark", prev, q, 1.1 - u * 0.5, 1.0 - u * 0.55, 7)
			prev = q
		k.sphere("glow_violet", I.translated(d * (3.5 + reach * 0.5) + Vector3(r.randf_range(-0.8, 0.8), 0.15, r.randf_range(-0.8, 0.8))), 0.25, 4, 6)
		k.sphere("cap_violet", I.translated(d * (3.2 + reach * 0.4) + Vector3(0.6, 0.3, 0.6)), 0.55, 5, 8, 0.1, 0.4, Color.WHITE, true)
	# Boughs and the crown, hung with lantern fruit.
	var crowns: Array = []
	for i in 7:
		var a := i * TAU / 7.0 + 0.3
		var y := 17.0 + (i % 3) * 3.0
		var end := Vector3(cos(a) * 9.5, y + 4.5, sin(a) * 9.5)
		_limb(k, "root_bark", Vector3(cos(a) * 1.2, y, sin(a) * 1.2), end, 1.0, 0.45, 7)
		crowns.append(end)
	crowns.append(Vector3(0, 29.0, 0))
	for c in crowns:
		var rad := r.randf_range(5.0, 6.5)
		k.sphere("leaf", I.translated(c), rad * 0.75, 6, 10, 0.35, 0.7, Color(0.55, 0.75, 0.7))
		ObjectLibrary._leaf_cards(k, "leaf_card", c, rad, 40, r, 2.4)
		for n in 4:
			var p: Vector3 = c + Vector3(r.randf_range(-rad, rad) * 0.7, -rad * 0.55 - r.randf_range(0.5, 2.0), r.randf_range(-rad, rad) * 0.7)
			k.cylinder("stem", I.translated(p), 0.03, 0.03, c.y - p.y - rad * 0.4, 4, false)
			k.sphere("glow_teal", I.translated(p), 0.35, 5, 7)
	for i in 6:
		var a := r.randf() * TAU
		k.crystal("crystal_violet", Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.4), Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)), 0.4, r.randf_range(1.8, 3.2))
	k.box("glow_teal", Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 3.35)), Vector3(1.4, 2.6, 0.05))

static func _dreadnought(k: MeshKit, r: RandomNumberGenerator) -> ArrayMesh:
	var I := Transform3D.IDENTITY
	var hull := Transform3D(Basis.from_euler(Vector3(0.18, 0.0, 0.22)).scaled(Vector3.ONE * 3.4), Vector3(0, 1.0, -1.0))
	var out := Landmark._merge(["ships/Striker"], [hull])
	# The furrow it ploughed, scattered plating, fires and a broken mast.
	for i in 10:
		var a := r.randf() * TAU
		var d := r.randf_range(7.0, 14.0)
		k.sphere("starfall_glass", I.translated(Vector3(cos(a) * d, -0.4, sin(a) * d)), r.randf_range(1.2, 2.4), 5, 8, 0.3, 0.4)
	for i in 14:
		var a := r.randf() * TAU
		var d := r.randf_range(6.0, 14.0)
		var b := Basis.from_euler(Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5)))
		k.box("metal_dark" if i % 3 else "rust", Transform3D(b, Vector3(cos(a) * d, 0.2, sin(a) * d)), Vector3(r.randf_range(1.0, 3.0), 0.1, r.randf_range(0.8, 2.0)))
	for i in 5:
		var p := Vector3(r.randf_range(-6, 6), 0.3, r.randf_range(-10, 8))
		k.sphere("glow_red", I.translated(p), r.randf_range(0.3, 0.6), 4, 6, 0.4)
		k.sphere("glow_warm", I.translated(p + Vector3(0, 0.4, 0)), 0.25, 4, 6, 0.4)
	_limb(k, "metal_dark", Vector3(2.5, 0.0, 6.0), Vector3(6.5, 9.0, 4.0), 0.25, 0.15)
	k.sphere("glow_red", I.translated(Vector3(6.5, 9.2, 4.0)), 0.3, 4, 6)
	k.box("glow_cyan", Transform3D(Basis.from_euler(Vector3(0.18, 0.0, 0.22)), Vector3(0, 2.6, 6.5)), Vector3(3.0, 0.4, 0.05))
	return out

## The v16 Fallen Dreadnought: a warship of the Imperial make at capital-ship size (about
## 67 m long and 28 across), lying nose by the vault (+z) at the end of its trench, rolled
## onto one flank and sunk to the belly in the floor it dug. Plating torn off along its
## sides, ribs bared where its back broke, a mast snapped over it. `calm` (human worlds)
## leaves out the fires.
static func _crashed(k: MeshKit, r: RandomNumberGenerator, calm: bool) -> ArrayMesh:
	var I := Transform3D.IDENTITY
	const SC := 3.6
	var roll := Basis.from_euler(Vector3(0.06, 0.04, 0.24))
	var hull := Transform3D(roll.scaled(Vector3.ONE * SC), Vector3(0, -0.4, CRASH_NOSE - 2.0 - 11.88 * SC))
	var out := Landmark._merge(["ships/Imperial"], [hull])
	# The high flank (+x rolls up): a breach in the back with ribs standing out of it.
	for j in 7:
		var z := -46.0 + j * 2.6
		var prev := roll * Vector3(4.0, 5.5, z)
		for s in 5:
			var a := (s + 1) / 5.0 * PI * 0.55
			var q := roll * Vector3(4.0 + sin(a) * 7.0, 5.5 + cos(a) * 3.5 - s * 0.2, z + r.randf_range(-0.2, 0.2))
			_limb(k, "metal_dark", prev, q, 0.32, 0.26, 6)
			prev = q
	for j in 5:
		k.box("scrap_plate", Transform3D(roll * Basis.from_euler(Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(0.3, 1.1))),
			roll * Vector3(r.randf_range(6.0, 10.0), 6.0, -45.0 + j * 3.4)), Vector3(r.randf_range(3.0, 5.0), 0.2, r.randf_range(2.0, 3.5)))
	# Armour torn off along both flanks, half buried in the trench floor.
	for i in 18:
		var side := 1.0 if i % 2 == 0 else -1.0
		var z := r.randf_range(-62.0, -4.0)
		var b := Basis.from_euler(Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, side * r.randf_range(0.4, 1.2)))
		k.box("scrap_plate" if i % 3 else "metal_dark", Transform3D(b, Vector3(side * r.randf_range(13.0, 17.5), r.randf_range(-2.4, -1.2), z)),
			Vector3(r.randf_range(2.5, 6.0), 0.22, r.randf_range(1.5, 3.5)))
	# The mast snapped off at its foot: a jagged stump on the hull, the rest lying in the
	# trench beside it with its dish.
	_limb(k, "metal_dark", roll * Vector3(-1.0, 4.5, -22.0), roll * Vector3(-1.4, 9.0, -21.0), 0.75, 0.6)
	_limb(k, "metal_dark", Vector3(-17.0, -1.6, -34.0), Vector3(-19.5, -0.6, -16.0), 0.6, 0.4)
	k.box("panel", Transform3D(Basis.from_euler(Vector3(0.3, 0.5, -1.1)), Vector3(-19.0, 0.2, -14.6)), Vector3(3.2, 0.3, 1.6))
	# Gun turrets still on the hull's back, barrels at all angles.
	for i in 3:
		var at := roll * Vector3(r.randf_range(-2.5, 2.5), 5.0, -14.0 - i * 13.0)
		k.cylinder("metal_dark", Transform3D(roll, at), 2.2, 1.9, 1.3, 14)
		for x in [-0.6, 0.6]:
			var b := roll * Basis.from_euler(Vector3(PI * 0.5 - r.randf_range(0.1, 0.9), r.randf_range(-0.8, 0.8), 0))
			k.cylinder("metal_dark", Transform3D(b, at + roll * Vector3(x, 0.9, 0.8)), 0.28, 0.22, 7.0, 8)
	# Fires still burning in the wreck, and the reactor's red glow through a rent in the
	# hull (alien worlds only: nothing glows on a human one).
	if not calm:
		for i in 6:
			var p := roll * Vector3(r.randf_range(-8.0, 8.0), r.randf_range(4.0, 7.0), r.randf_range(-58.0, -6.0))
			k.sphere("glow_red", I.translated(p), r.randf_range(0.5, 1.0), 4, 6, 0.4)
			k.sphere("glow_warm", I.translated(p + Vector3(0, 0.6, 0)), 0.45, 4, 6, 0.4)
		k.box("glow_red", Transform3D(roll, roll * Vector3(6.5, 5.0, -38.0)), Vector3(0.3, 2.5, 7.0))
	return out

## A tree the crash knocked down (v 1: a conifer): its splintered stump, and the trunk
## lying along local +z, bark scorched black on the side that faced the blast, the crown
## burnt off to a few broken limbs. Nothing glows: the fire is long out.
static func trunk(sp: int, v: int) -> ArrayMesh:
	var k := MeshKit.new((sp * 53 + v * 11) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = sp * 613 + v * 17 + 3
	var conifer := v == 1
	var bark := "bark_pine" if conifer else "bark"
	var char_ := Color(0.16, 0.14, 0.13)
	var g := r.randf_range(0.22, 0.36) * (0.85 if conifer else 1.0)
	var stump := r.randf_range(0.5, 1.3)
	# The stump, snapped off ragged: splinters standing up from the break.
	k.cylinder(bark, Transform3D(Basis(), Vector3(0, -0.3, 0)), g * 1.25, g * 1.05, stump + 0.3, 9, true, 0.06, 2, Color(0.55, 0.5, 0.46))
	for n in 6:
		var a := n * TAU / 6.0 + r.randf_range(-0.3, 0.3)
		var hgt := r.randf_range(0.15, 0.55)
		var tip := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), r.randf_range(-0.25, 0.25))
		k.box("timber", Transform3D(tip, Vector3(cos(a) * g * 0.6, stump + hgt * 0.5, sin(a) * g * 0.6)), Vector3(g * 0.35, hgt, g * 0.22), Color(0.72, 0.62, 0.5))
	# The trunk, thrown down beside it, its butt end resting on the ground.
	var len := r.randf_range(6.0, 10.0) * (1.15 if conifer else 1.0)
	var lie := Basis(Vector3.RIGHT, PI * 0.5 - r.randf_range(0.02, 0.08)) * Basis(Vector3.UP, r.randf() * TAU)
	var butt := Vector3(r.randf_range(-0.3, 0.3), g * 0.8, g * 1.4 + 0.2)
	k.cylinder(bark, Transform3D(lie, butt), g * 1.0, g * 0.45, len, 9, true, 0.05, 4, Color(0.5, 0.45, 0.4))
	var axis := lie * Vector3.UP
	# Soot along the blast side, in long scorched strips.
	for n in 3:
		var zt := len * (0.15 + n * 0.28)
		var rad := g * (1.0 - 0.55 * zt / len)
		var at := butt + axis * zt + Vector3(0, rad * 0.7, 0)
		k.box(bark, Transform3D(lie * Basis(Vector3.UP, r.randf_range(-0.4, 0.4)), at), Vector3(rad * 1.3, len * 0.22, rad * 0.4), char_)
	# Broken limbs, burnt short.
	for n in (5 if conifer else 4):
		var z := len * r.randf_range(0.35, 0.95)
		var a := r.randf_range(-PI, PI)
		var dir := Vector3(cos(a), absf(sin(a)) * 0.6 + 0.2, r.randf_range(-0.3, 0.3)).normalized()
		var from := butt + axis * z + Vector3(0, g * 0.3, 0)
		var l2 := r.randf_range(0.6, 1.8)
		k.cylinder(bark, Transform3D(Basis(Quaternion(Vector3.UP, dir)), from), g * 0.32, g * 0.08, l2, 5, true, 0.0, 1, char_ * 1.6)
	return k.commit(Materials.get_mat)

## Wreckage of the Fallen Dreadnought, lying out along its trench. Kind 1-6: a torn hull
## plate, a section of bared ribs, an engine pod, a turret thrown off its ring, a heap of
## armour slabs, twisted scrap; size 0-2.
static func debris(sp: int, v: int) -> ArrayMesh:
	var k := MeshKit.new((sp * 31 + v * 7) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = sp * 977 + v * 13 + 5
	var I := Transform3D.IDENTITY
	var z: float = [0.7, 1.0, 1.5][clampi(v, 0, 2)]
	match (sp - 1) % 6:
		0:
			# A hull plate bent over on itself, one edge dug into the ground.
			for i in 3:
				var b := Basis.from_euler(Vector3(0.2 + i * 0.22, 0, r.randf_range(-0.12, 0.12)))
				k.box("scrap_plate", Transform3D(b, Vector3(0, 0.2 + i * 0.5, i * 1.15) * z), Vector3(4.6, 0.18, 1.3) * z)
			k.box("metal_dark", Transform3D(Basis.from_euler(Vector3(0.42, 0, 0)), Vector3(0, 0.75, 1.1) * z), Vector3(4.4, 0.32, 0.22) * z)
			k.box("metal_dark", Transform3D(Basis.from_euler(Vector3(0.42, 0, 0)), Vector3(1.6, 0.75, 1.1) * z), Vector3(0.22, 0.32, 3.2) * z)
		1:
			# Bared ribs: curved frames and a stringer standing out of the sand.
			for j in 4:
				var zz := (j - 1.5) * 1.7 * z
				var prev := Vector3(-3.0 * z, -0.4, zz)
				for s in 6:
					var a := (s + 1) / 6.0 * PI * 0.85
					var q := Vector3(-cos(a) * 3.0 * z, sin(a) * 2.8 * z - 0.4 - s * 0.05, zz + r.randf_range(-0.1, 0.1))
					_limb(k, "metal_dark", prev, q, 0.17 * z, 0.15 * z, 5)
					prev = q
			_limb(k, "rust", Vector3(-1.4, 2.2, -3.2) * z, Vector3(-1.2, 2.3, 3.2) * z, 0.12 * z, 0.12 * z, 5)
			k.box("scrap_plate", Transform3D(Basis.from_euler(Vector3(0, 0, 0.55)), Vector3(-2.1, 1.2, 0.6) * z), Vector3(2.4, 0.12, 4.0) * z)
		2:
			# An engine pod torn off and half sunk, its nozzle bell blown open.
			var along := Basis(Vector3.RIGHT, PI * 0.5 + 0.07)
			k.cylinder("metal_dark", Transform3D(along, Vector3(0, 0.5, -3.6) * z), 1.6 * z, 1.4 * z, 7.0 * z, 16)
			k.cylinder("rust", Transform3D(along, Vector3(0, 0.5 + 0.49, 3.4) * z), 1.35 * z, 1.9 * z, 1.8 * z, 16, false)
			k.cylinder("stone_dark", Transform3D(along, Vector3(0, 0.5 + 0.49, 3.3) * z), 1.15 * z, 1.15 * z, 0.1 * z, 16)
			for f in 3:
				var b := Basis(Vector3.BACK, f * TAU / 3.0 + 0.3)
				k.box("panel", Transform3D(b, b * Vector3(0, 1.9, 0) * z + Vector3(0, 0.5, -1.0) * z), Vector3(0.18, 1.4, 3.0) * z, Color(0.55, 0.56, 0.58))
		3:
			# A turret thrown off its ring, tipped on its side, barrels askew.
			var tip := Basis.from_euler(Vector3(0.35, 0, 0.5))
			k.cylinder("panel", Transform3D(tip, Vector3(0, -0.3, 0)), 2.1 * z, 1.8 * z, 1.6 * z, 16, true, 0.0, 1, Color(0.5, 0.52, 0.55))
			k.cylinder("metal_dark", Transform3D(tip, Vector3(0, -0.6, 0)), 1.6 * z, 1.6 * z, 0.5 * z, 16)
			for x in [-0.6, 0.6]:
				var b := tip * Basis.from_euler(Vector3(PI * 0.5 - r.randf_range(-0.3, 0.4), r.randf_range(-0.4, 0.4), 0))
				k.cylinder("metal_dark", Transform3D(b, tip * Vector3(x, 1.0, 1.0) * z), 0.3 * z, 0.24 * z, 6.0 * z, 8)
		4:
			# Armour slabs fallen in a heap.
			for i in 6:
				var b := Basis.from_euler(Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5)))
				k.box("scrap_plate" if i % 2 else "metal_dark", Transform3D(b, Vector3(r.randf_range(-1.5, 1.5), 0.2 + i * 0.35, r.randf_range(-1.5, 1.5)) * z),
					Vector3(r.randf_range(2.0, 3.6), 0.35, r.randf_range(1.2, 2.4)) * z)
		_:
			# Twisted scrap: buckled panels and snapped conduit.
			for i in 7:
				var b := Basis.from_euler(Vector3(r.randf_range(-0.9, 0.9), r.randf() * TAU, r.randf_range(-0.9, 0.9)))
				k.box("scrap_plate" if i % 3 else "rust", Transform3D(b, Vector3(r.randf_range(-1.6, 1.6), 0.15, r.randf_range(-1.6, 1.6)) * z),
					Vector3(r.randf_range(0.6, 1.8), 0.06, r.randf_range(0.4, 1.2)) * z)
			for i in 3:
				var a := Vector3(r.randf_range(-1.5, 1.5), -0.2, r.randf_range(-1.5, 1.5)) * z
				_limb(k, "metal_dark", a, a + Vector3(r.randf_range(-1.5, 1.5), r.randf_range(0.6, 1.6), r.randf_range(-1.5, 1.5)) * z, 0.09 * z, 0.07 * z, 5)
	return k.commit(Materials.get_mat)

static func _gate(k: MeshKit, r: RandomNumberGenerator, solid: bool) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("flagstone", I.translated(Vector3(0, -3.0, 0)), 9.2, 9.0, 3.6, 24)
	k.cylinder("void_stone", I.translated(Vector3(0, 0.6, 0)), 7.5, 7.0, 0.4, 24)
	for x in [-5.8, 5.8]:
		k.box("gate_metal", I.translated(Vector3(x, 1.5, 0)), Vector3(2.6, 3.0, 3.0))
	# The ring: twenty rune stones on a circle standing across z, the keystone in gold.
	const RAD := 7.0
	const CY := 8.2
	for i in 20:
		var a := i * TAU / 20.0
		var p := Vector3(cos(a) * RAD, CY + sin(a) * RAD, 0)
		var b := Basis(Vector3.BACK, a)
		k.box("gold" if i == 5 else "gate_metal", Transform3D(b, p), Vector3(1.5, 2.5, 1.8))
		k.box("glow_violet", Transform3D(b, p + Vector3(0, 0, 0.92)), Vector3(0.3, 1.2, 0.04))
		k.box("glow_violet", Transform3D(b, p - Vector3(0, 0, 0.92)), Vector3(0.3, 1.2, 0.04))
	if not solid:
		k.card("portal", I, Vector3(0, CY, 0), Basis.IDENTITY, 12.6, 12.6)
	for i in 6:
		var a := r.randf() * TAU
		k.crystal("crystal_violet", Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.5), Vector3(cos(a) * 8.5, 0.6, sin(a) * 8.5)), 0.35, r.randf_range(1.2, 2.4))
	for i in 5:
		var p := Vector3(r.randf_range(-6, 6), CY + RAD + r.randf_range(2.0, 5.0), r.randf_range(-3, 3))
		k.sphere("stone_dark", Transform3D(Basis.from_euler(Vector3(r.randf(), r.randf(), r.randf())), p), r.randf_range(0.4, 0.9), 4, 6, 0.4)
