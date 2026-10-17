class_name EasterEggs
## Hidden finds (v11 worlds): small secrets the generator tucks into the land, at most one
## per CELL x CELL chunks and only where the ground suits one, so most cells have none.
##
##   Sword in the Stone   a blade sunk in a boulder on a hilltop; only a strong arm draws it
##   Gnome Ring           a ring of mushrooms round a stone gnome, deep in the woods; it
##                        wakes after dark
##   Message in a Bottle  washed up on a beach; the letter inside is a treasure map
##   Lost Explorer's Camp a cold camp far from any town; the journal tells of another secret
##   Tiny Door            a little round door set into a steep hillside; knock and see
##
## The plan for a cell is worked out from the world field alone (no chunk needed), so a
## journal can tell of a secret in land nobody has walked yet. The chunk that holds the
## planned spot fits it to its own ground. What each has given is kept in the object's
## state in the chunk snapshot (and so, in multiplayer, for everyone). Nothing here
## glows: these belong to human worlds. Alien worlds only get the explorer's camp.
## Effects live in EggEffects (it needs the Game autoload; this file must not).

const CELL := 6 ## chunks per side of an egg cell (about 384 m)
const CHANCE := 0.3 ## of a cell holding one, if its ground suits
const TRIES := 10 ## spots a cell tries
const SWORD_STR := 5 ## Strength points it takes to draw the sword

const TYPES := ["sword_stone", "gnome_ring", "msg_bottle", "lost_camp", "tiny_door"]
## How often each comes first in a cell's wish list: steep banks and empty flats are
## everywhere, hilltops, deep woods and beaches are not.
const WEIGHT := {"sword_stone": 4.0, "gnome_ring": 3.0, "msg_bottle": 4.0, "lost_camp": 1.5, "tiny_door": 1.0}
const LABELS := {
	"sword_stone": "Sword in the Stone", "gnome_ring": "Gnome Ring", "msg_bottle": "Message in a Bottle",
	"lost_camp": "Lost Explorer's Camp", "tiny_door": "Tiny Door",
}
## Where each is found, in words (for the explorer's journal).
const WHERE := {
	"sword_stone": "a sword stuck fast in a stone on a hilltop", "gnome_ring": "a ring of mushrooms round a little stone man, deep in the woods",
	"msg_bottle": "a bottle the tide keeps bringing back to the same beach", "lost_camp": "a camp nobody came back to",
	"tiny_door": "a door no higher than your knee, set into a steep hillside",
}
## Collision boxes (the meshes stand on y = 0).
const SIZE := {
	"sword_stone": Vector3(2.0, 1.3, 1.7), "gnome_ring": Vector3(0.8, 1.2, 0.8), "msg_bottle": Vector3(0.7, 0.3, 0.5),
	"lost_camp": Vector3(1.7, 1.3, 2.3), "tiny_door": Vector3(1.3, 1.0, 0.7),
}
## How high the prompt floats.
const PROMPT_H := {"sword_stone": 2.3, "gnome_ring": 1.4, "msg_bottle": 0.6, "lost_camp": 1.6, "tiny_door": 1.1}
## The icon in the look panel.
const ICON := {"sword_stone": "sword_iron", "gnome_ring": "mushroom", "msg_bottle": "scroll_plain", "lost_camp": "book_leather", "tiny_door": "door_wood"}
const XP := {"sword_stone": 150.0, "gnome_ring": 90.0, "msg_bottle": 50.0, "lost_camp": 70.0, "tiny_door": 60.0}

static var _plans := {}
static var _lock := Mutex.new()

static func has(t: String) -> bool:
	return LABELS.has(t)

static func label(t: String) -> String:
	return LABELS.get(t, t)

# --- Using them ---------------------------------------------------------------------

## What using it does right now, for the floating prompt: {"verb", "h"}, or {} when it has
## nothing more to give.
static func use_of(o: Dictionary, day: float) -> Dictionary:
	var st: Dictionary = o["st"]
	var t := String(o["t"])
	var h: float = PROMPT_H.get(t, 1.0)
	match t:
		"sword_stone":
			if not st.get("drawn", false):
				return {"verb": "Pull the sword from the stone", "h": h}
		"gnome_ring":
			if not st.get("used", false):
				return {"verb": "Step into the ring", "h": h}
		"msg_bottle":
			if not st.get("used", false):
				return {"verb": "Open the bottle", "h": h}
		"lost_camp":
			if not st.get("used", false):
				return {"verb": "Read the explorer's journal", "h": h}
		"tiny_door":
			if not st.get("used", false) or int(st.get("day", -1)) < int(floor(day)):
				return {"verb": "Knock on the tiny door", "h": h}
	return {}

## A line for the look panel.
static func describe(o: Dictionary, day: float) -> String:
	var st: Dictionary = o["st"]
	var by := String(st.get("by_name", ""))
	var who := (" (found by %s)" % by) if by != "" else ""
	match String(o["t"]):
		"sword_stone":
			return "Sunk to the hilt in solid rock" if not st.get("drawn", false) else "An empty slot where a sword once stood" + who
		"gnome_ring":
			return "The gnome's painted eyes seem to follow you" if not st.get("used", false) else "Just mushrooms now" + who
		"msg_bottle":
			return "Something rolled up inside" if not st.get("used", false) else "Empty" + who
		"lost_camp":
			return "Long cold. A journal lies on the log" if not st.get("used", false) else "Long cold. You have read the journal" + who
		"tiny_door":
			if not st.get("used", false):
				return "A wisp of smoke from a chimney the size of your thumb"
			return "Someone tiny lives here" if int(st.get("day", -1)) < int(floor(day)) else "Nobody answers again today"
	return ""

## Its mesh, which changes once the sword is drawn, and the sci-fi camp.
static func mesh_key(o: Dictionary) -> String:
	var t := String(o["t"])
	if t == "sword_stone" and o["st"].get("drawn", false):
		return t + "~drawn"
	if t == "lost_camp" and int(o["e"]) == Eras.SCIFI:
		return t + "~s"
	return t

## Small things that would vanish if sunk into the ground like a boulder is.
static func floats(t: String) -> bool:
	return t == "gnome_ring" or t == "msg_bottle" or t == "lost_camp"

static func owns_key(key: String) -> bool:
	return has(key.get_slice("~", 0))

# --- Planning -----------------------------------------------------------------------

## The cell a chunk belongs to.
static func cell_of(cx: int, cz: int) -> Vector2i:
	return Vector2i(int(floor(float(cx) / CELL)), int(floor(float(cz) / CELL)))

## What cell (wx, wz) hides and where: {"t", "p" (world xz), "era"}, or {} for nothing.
## Pure in the seed and the world field, cached.
static func plan(g: ChunkGenerator, wx: int, wz: int) -> Dictionary:
	var key := "%d:%d:%d:%s:%d" % [g.seed, wx, wz, Eras.theme, WorldField.allowed_eras.size()]
	_lock.lock()
	var have = _plans.get(key)
	_lock.unlock()
	if have != null:
		return have
	var out := _plan(g, wx, wz)
	_lock.lock()
	if _plans.size() > 4096:
		_plans.clear()
	_plans[key] = out
	_lock.unlock()
	return out

static func _plan(g: ChunkGenerator, wx: int, wz: int) -> Dictionary:
	if WHash.unit2(g.seed, wx, wz, 1201) > CHANCE:
		return {}
	var r := WHash.rng(g.seed, wx, wz, 1202)
	r.randf() # a fresh WHash.rng's first draw is always near 0
	# A weighted shuffle: each kind keyed by u^(1/weight), highest first.
	var order: Array = TYPES.duplicate()
	var keys := {}
	for t in order:
		keys[t] = pow(maxf(r.randf(), 0.0001), 1.0 / float(WEIGHT[t]))
	order.sort_custom(func(a, b): return keys[a] > keys[b])
	const S := ChunkGenerator.SIZE
	var spots: Array = []
	for n in TRIES:
		var cx := wx * CELL + r.randi_range(0, CELL - 1)
		var cz := wz * CELL + r.randi_range(0, CELL - 1)
		spots.append(Vector2(cx * S + r.randf_range(14.0, S - 14.0), cz * S + r.randf_range(14.0, S - 14.0)))
	var fits: Array = []
	for i in spots.size():
		# A spot on a hillside climbs to the hilltop above it, if that stays in the cell.
		var top := _climb(g, spots[i])
		if cell_of(int(floor(top.x / S)), int(floor(top.y / S))) == Vector2i(wx, wz) and top.distance_to(spots[i]) > 1.0:
			spots.append(top)
	for p in spots:
		fits.append(_fits(g, p))
	for t in order:
		for i in spots.size():
			if t in fits[i]:
				var p: Vector2 = spots[i]
				return {"t": t, "p": p, "era": WorldField.dominant(g.field.era_weights(p.x, p.y))}
	return {}

## Walks uphill from p in 5 m steps to the top (or gives up after a while).
static func _climb(g: ChunkGenerator, p: Vector2) -> Vector2:
	var f := g.field
	var h := f.height(p.x, p.y)
	if h < ChunkGenerator.WATER_LEVEL + 6.0:
		return p
	for n in 14:
		var best := p
		var bh := h
		for a in 8:
			var q := p + Vector2.from_angle(a * TAU / 8.0) * 5.0
			var qh := f.height(q.x, q.y)
			if qh > bh:
				bh = qh
				best = q
		if best == p:
			break
		p = best
		h = bh
	return p

## Which finds the ground at world point p suits.
static func _fits(g: ChunkGenerator, p: Vector2) -> Array:
	var f := g.field
	var h := f.height(p.x, p.y)
	if g.rivers and f.river_t(p.x, p.y) < 4.0:
		return []
	for s in g.settlements_near(p.x - 160.0, p.y - 160.0, p.x + 160.0, p.y + 160.0):
		if p.distance_to(s["center"]) < float(s["outer"]) + 40.0:
			return []
	for fo in g.forts_near(p.x - 1.0, p.y - 1.0, p.x + 1.0, p.y + 1.0):
		if p.distance_to(fo["center"]) < Stronghold.OUTER + 20.0:
			return []
	var slope := maxf(absf(f.height(p.x + 2.0, p.y) - f.height(p.x - 2.0, p.y)), absf(f.height(p.x, p.y + 2.0) - f.height(p.x, p.y - 2.0))) / 4.0
	var era := WorldField.dominant(f.era_weights(p.x, p.y))
	var alien := Eras.theme != "" and Eras.theme != "human"
	var old_world := era != Eras.SCIFI and not alien
	var out: Array = []
	# A beach: just above the water with open water a few metres out.
	if h > ChunkGenerator.WATER_LEVEL + 0.25 and h < ChunkGenerator.WATER_LEVEL + 1.6 and slope < 0.3 and not alien:
		for a in 8:
			var q := p + Vector2.from_angle(a * TAU / 8.0) * 9.0
			if f.height(q.x, q.y) < ChunkGenerator.WATER_LEVEL - 0.4:
				out.append("msg_bottle")
				break
	if h < ChunkGenerator.WATER_LEVEL + 1.5:
		return out
	# A hilltop: higher than all the land around it.
	if old_world and h > ChunkGenerator.WATER_LEVEL + 8.0 and slope < 0.45:
		var top := true
		for a in 8:
			var q := p + Vector2.from_angle(a * TAU / 8.0) * 22.0
			if f.height(q.x, q.y) > h - 1.5:
				top = false
				break
		if top:
			out.append("sword_stone")
	# Deep woods, on level ground.
	if old_world and slope < 0.22:
		var forest := clampf((f._moss.get_noise_2d(p.x * 0.15, p.y * 0.15) + 0.35) * 1.5, 0.0, 1.0)
		var dense := float(Biome.params(f.region_hash_at(p.x, p.y), era)["tree_density"])
		if g.landforms:
			dense *= WorldField.LANDFORM_TREES[f.landform_at(p.x, p.y)]
		if forest > 0.72 and dense > 0.6:
			out.append("gnome_ring")
	# A steep bank to dig a door into.
	if old_world and slope > 0.55 and slope < 1.1 and h > ChunkGenerator.WATER_LEVEL + 3.0:
		out.append("tiny_door")
	# Flat, dry and far from anyone: somewhere you might get lost.
	if slope < 0.2 and g.settlements_near(p.x - 150.0, p.y - 150.0, p.x + 150.0, p.y + 150.0).is_empty():
		out.append("lost_camp")
	return out

## The nearest planned find to world point p within `reach` metres other than the one at
## `skip`: {"t", "p", "era"} or {}.
static func nearest(g: ChunkGenerator, p: Vector2, reach: float, skip: Vector2) -> Dictionary:
	var S := float(ChunkGenerator.SIZE * CELL)
	var best := {}
	var bd := reach
	var c := Vector2i(int(floor(p.x / S)), int(floor(p.y / S)))
	var n := int(ceil(reach / S))
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var e := plan(g, c.x + i, c.y + j)
			if e.is_empty():
				continue
			var q: Vector2 = e["p"]
			var d := q.distance_to(p)
			if d < bd and q.distance_to(skip) > 30.0:
				bd = d
				best = e
	return best

# --- Placing ------------------------------------------------------------------------

## Puts this chunk's find, if its cell planned one here and the ground still allows once
## the chunk's roads, buildings and caves are in. Called before the wilds grow, so trees
## keep off it.
static func place(g: ChunkGenerator, chunk: Dictionary) -> void:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	const S := ChunkGenerator.SIZE
	var c := cell_of(cx, cz)
	var e := plan(g, c.x, c.y)
	if e.is_empty():
		return
	var wp: Vector2 = e["p"]
	var lp := wp - Vector2(cx * S, cz * S)
	if lp.x < 0.0 or lp.y < 0.0 or lp.x >= S or lp.y >= S:
		return
	var t: String = e["t"]
	var plans := ChunkGenerator.keep_out(chunk)
	var rad := Vector2(SIZE[t].x, SIZE[t].z).length() * 0.5 + (2.5 if t == "lost_camp" else 0.8)
	var best := Vector2.INF
	var score := INF
	for ring in [0.0, 3.0, 6.0, 9.0]:
		var steps := 1 if ring == 0.0 else 8
		for a in steps:
			var q: Vector2 = lp + Vector2.from_angle(a * TAU / steps) * ring
			if q.x < rad or q.y < rad or q.x > S - rad or q.y > S - rad:
				continue
			var h := ChunkGenerator.height_at(chunk, q.x, q.y)
			var sl := ChunkGenerator.slope_at(chunk, q.x, q.y)
			if ChunkGenerator.road_at(chunk, q.x, q.y) > 0.0 or ChunkGenerator.by_river(chunk, q.x, q.y) or ChunkGenerator.in_cave(chunk, q.x, q.y) \
					or ChunkGenerator.kept_out(plans, q.x, q.y, rad):
				continue
			var sc: float = ring * 0.1
			match t:
				"msg_bottle":
					if h < ChunkGenerator.WATER_LEVEL + 0.15 or h > ChunkGenerator.WATER_LEVEL + 1.8:
						continue
					sc += h * 2.0
				"sword_stone":
					sc += -h + sl * 3.0
				"tiny_door":
					if sl < 0.4:
						continue
					sc += absf(sl - 0.8)
				_:
					if h < ChunkGenerator.WATER_LEVEL + 1.0:
						continue
					sc += sl * 6.0
			if sc < score:
				score = sc
				best = q
	if best == Vector2.INF:
		return
	var r := WHash.rng(g.seed, cx, cz, 1203)
	r.randf()
	var yaw := r.randf() * TAU
	if t == "tiny_door":
		# The door looks out downhill (its front is +z).
		var dx := ChunkGenerator.height_at(chunk, best.x + 1.0, best.y) - ChunkGenerator.height_at(chunk, best.x - 1.0, best.y)
		var dz := ChunkGenerator.height_at(chunk, best.x, best.y + 1.0) - ChunkGenerator.height_at(chunk, best.x, best.y - 1.0)
		yaw = atan2(-dx, -dz)
	var era := WorldField.dominant(ChunkGenerator.weights_at(chunk, best.x, best.y))
	g._add(chunk, t, era, best.x, best.y, yaw, 1.0, {})
	if t == "tiny_door":
		# Sit it into the bank rather than on the slope in front of it.
		var o: Dictionary = chunk["objects"][-1]
		o["p"].y -= 0.12

# --- Meshes -------------------------------------------------------------------------

static func build(key: String) -> ArrayMesh:
	var t := key.get_slice("~", 0)
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(key)
	var names: Array = []
	var xfs: Array = []
	match t:
		"sword_stone":
			# A weathered boulder, mossy on its north side, and an old bronze sword in it.
			k.sphere("stone", Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 0.5, 0)), 1.0, 9, 14, 0.28, 0.78)
			k.sphere("stone", I.translated(Vector3(0.75, 0.25, 0.45)), 0.55, 7, 10, 0.35, 0.7)
			k.sphere("stone", I.translated(Vector3(-0.6, 0.2, -0.55)), 0.45, 6, 9, 0.35, 0.65)
			k.sphere("moss", I.translated(Vector3(-0.25, 1.05, -0.45)), 0.5, 5, 8, 0.25, 0.25)
			k.sphere("moss", I.translated(Vector3(-0.85, 0.35, -0.3)), 0.35, 4, 7, 0.3, 0.35)
			for i in 6:
				var a := r.randf() * TAU
				k.sphere("stone_dark", I.translated(Vector3(cos(a), 0.0, sin(a)) * r.randf_range(1.2, 1.8)), r.randf_range(0.08, 0.18), 4, 6, 0.3, 0.6)
			if key.ends_with("~drawn"):
				k.box("stone_dark", Transform3D(Basis(Vector3.FORWARD, 0.08), Vector3(0, 1.27, 0)), Vector3(0.09, 0.04, 0.035))
			else:
				# Point down, a little off true, buried to half the blade.
				names.append("props/Sword_Bronze")
				xfs.append(Transform3D(Basis(Vector3.FORWARD, 0.08) * Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3.ONE * 1.6), Vector3(0.0, 1.95, 0.0)))
		"gnome_ring":
			# A fairy ring of toadstools, and in the middle a painted stone gnome.
			var count := 15
			for i in count:
				var a := i * TAU / count + r.randf_range(-0.12, 0.12)
				var d := 2.3 + r.randf_range(-0.2, 0.2)
				var s := r.randf_range(0.8, 1.4)
				names.append("nature/Mushroom_Common")
				xfs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), Vector3(cos(a) * d, 0.0, sin(a) * d)))
			# Half again life size: a garden gnome that reads from across the clearing.
			var G := Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3.ZERO)
			k.cylinder("stone", G, 0.24, 0.22, 0.08, 10)
			for x in [-0.07, 0.07]:
				k.sphere("leather", G * Transform3D(Basis.from_scale(Vector3(0.8, 0.6, 1.2)), Vector3(x, 0.12, 0.03)), 0.06, 5, 7)
			k.cylinder("plaster", G * I.translated(Vector3(0, 0.1, 0)), 0.13, 0.09, 0.26, 10, true, 0.0, 1, Color(0.25, 0.4, 0.75))
			k.cylinder("leather", G * I.translated(Vector3(0, 0.22, 0)), 0.115, 0.112, 0.03, 10)
			k.sphere("gold", G * I.translated(Vector3(0, 0.235, 0.112)), 0.018, 3, 5)
			for x in [-1.0, 1.0]:
				k.cylinder("plaster", G * Transform3D(Basis(Vector3.FORWARD, x * (PI - 0.35)), Vector3(x * 0.11, 0.33, 0)), 0.035, 0.03, 0.14, 6, true, 0.0, 1, Color(0.25, 0.4, 0.75))
			k.sphere("plaster", G * I.translated(Vector3(0, 0.42, 0)), 0.085, 7, 10, 0.0, 1.0, Color(0.95, 0.75, 0.62))
			k.sphere("plaster", G * I.translated(Vector3(0, 0.42, 0.08)), 0.025, 4, 6, 0.0, 1.0, Color(0.95, 0.6, 0.5))
			k.cylinder("plaster", G * Transform3D(Basis(Vector3.RIGHT, PI - 0.25), Vector3(0, 0.42, 0.055)), 0.075, 0.01, 0.2, 9, true, 0.0, 1, Color(0.97, 0.96, 0.92))
			k.cylinder("plaster", G * Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.47, 0)), 0.095, 0.006, 0.3, 10, true, 0.0, 1, Color(0.75, 0.12, 0.1))
		"msg_bottle":
			# A green glass bottle on its side, half in the sand, corked, a scroll tied with a
			# red ribbon inside; a bleached stick of driftwood and some shells.
			var lie := Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, PI * 0.5) ## +y along the bottle
			var at := func(along: float) -> Vector3: return Vector3(0.0, 0.065, 0.0) + lie * Vector3(0, along, 0)
			k.cylinder("bottle_glass", Transform3D(lie, at.call(-0.17)), 0.09, 0.09, 0.26, 16)
			k.cylinder("bottle_glass", Transform3D(lie, at.call(0.09)), 0.09, 0.032, 0.07, 16, false)
			k.cylinder("bottle_glass", Transform3D(lie, at.call(0.16)), 0.03, 0.03, 0.08, 12)
			k.cylinder("timber", Transform3D(lie, at.call(0.235)), 0.027, 0.03, 0.04, 10, true, 0.0, 1, Color(0.95, 0.8, 0.6))
			k.cylinder("plaster", Transform3D(lie, at.call(-0.14)), 0.045, 0.045, 0.2, 12, true, 0.0, 1, Color(1.0, 0.93, 0.74))
			k.cylinder("cloth", Transform3D(lie, at.call(-0.045)), 0.048, 0.048, 0.015, 12)
			k.cylinder("bone", Transform3D(Basis(Vector3.UP, 1.9) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.55, 0.05, -0.45)), 0.06, 0.04, 0.8, 7, true, 0.2, 3, Color(0.78, 0.74, 0.66))
			for i in 6:
				var a := r.randf() * TAU
				k.sphere("bone", I.translated(Vector3(cos(a), 0.0, sin(a)) * r.randf_range(0.35, 0.8)), r.randf_range(0.03, 0.05), 4, 7, 0.0, 0.45, Color(1.0, 0.88, 0.82))
		"lost_camp":
			_camp(k, r, key.ends_with("~s"), names, xfs)
		"tiny_door":
			# A round green door in a ring of stones, set into the bank, with a step and a pot.
			k.sphere("stone", Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.7)), Vector3(0, 0.15, -0.45)), 0.8, 7, 11, 0.3, 1.0)
			k.cylinder("planks", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.42, 0.04)), 0.34, 0.34, 0.06, 18, true, 0.0, 1, Color(0.45, 0.75, 0.42))
			k.sphere("gold", I.translated(Vector3(0, 0.42, 0.08)), 0.03, 4, 6)
			k.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.62, 0.065)), 0.012, 0.012, 0.03, 6)
			for i in 12:
				var a := i * TAU / 12.0
				var q := Vector3(cos(a) * 0.42, 0.42 + sin(a) * 0.42, 0.06)
				if q.y < 0.02:
					continue
				k.box("stone", Transform3D(Basis(Vector3.BACK, a), q), Vector3(0.11, 0.17, 0.16))
			k.box("stone", I.translated(Vector3(0, 0.03, 0.24)), Vector3(0.6, 0.06, 0.3))
			k.cylinder("stone", I.translated(Vector3(0.12, 0.75, -0.35)), 0.05, 0.045, 0.5, 6)
			names.append("props/Pot_1")
			xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.45), Vector3(0.42, 0.0, 0.28)))
			for i in 4:
				k.sphere("leaf", I.translated(Vector3(0.42 + r.randf_range(-0.05, 0.05), 0.12, 0.28 + r.randf_range(-0.05, 0.05))), 0.05, 4, 6)
	var out: ArrayMesh = Landmark._merge(names, xfs) if not names.is_empty() else null
	return k.commit(Materials.get_mat, out)

## A ridge tent, a cold fire, a log to sit on with the journal and a pack. The sci-fi
## camp keeps survey crates instead of a pack and a cook pot.
static func _camp(k: MeshKit, r: RandomNumberGenerator, scifi: bool, names: Array, xfs: Array) -> void:
	var I := Transform3D.IDENTITY
	var canvas := Color(0.78, 0.72, 0.58) if not scifi else Color(0.55, 0.6, 0.55)
	for side in [-1.0, 1.0]:
		k.box("plaster", Transform3D(Basis(Vector3.BACK, side * 0.72), Vector3(side * 0.42, 0.6, 0)), Vector3(0.05, 1.45, 2.2), canvas)
	k.cylinder("timber", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.18, -1.15)), 0.03, 0.03, 2.3, 6)
	for z in [-1.12, 1.12]:
		k.cylinder("timber", I.translated(Vector3(0, 0, z)), 0.03, 0.03, 1.2, 6)
	# Guy ropes pegged into the ground.
	for z in [-1.12, 1.12]:
		for side in [-1.0, 1.0]:
			var a := Vector3(0, 1.15, z)
			var b := Vector3(side * 0.4, 0.0, z + signf(z) * 0.7)
			var d := b - a
			k.cylinder("plaster", Transform3D(Basis(Vector3.UP.cross(d.normalized()).normalized(), Vector3.UP.angle_to(d.normalized())), a), 0.006, 0.006, d.length(), 4, false, 0.0, 1, Color(0.9, 0.85, 0.7))
	k.cylinder("leather", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.1, 0.12, -0.9)), 0.12, 0.12, 1.6, 10)
	# The fire, cold for a long time.
	var fire := Vector3(0, 0, 2.3)
	for i in 9:
		var a := i * TAU / 9.0
		k.sphere("stone", I.translated(fire + Vector3(cos(a), 0.05, sin(a)) * 0.45), r.randf_range(0.1, 0.14), 5, 7, 0.3, 0.7)
	k.cylinder("ash", I.translated(fire), 0.38, 0.38, 0.03, 12)
	for i in 3:
		var a := i * TAU / 3.0 + 0.3
		var d := Vector3(cos(a), 0.0, sin(a))
		k.cylinder("char", Transform3D(Basis(Vector3.UP.cross(Vector3(d.x, 0.35, d.z).normalized()).normalized(), Vector3.UP.angle_to(Vector3(d.x, 0.35, d.z).normalized())), fire - d * 0.3 + Vector3(0, 0.03, 0)), 0.045, 0.035, 0.55, 6)
	# A log seat with the journal open on it.
	var seat := Transform3D(Basis(Vector3.UP, 0.25) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.65, 0.18, 3.25))
	k.cylinder("bark", seat.translated_local(Vector3(0, -0.65, 0)), 0.18, 0.17, 1.3, 10)
	names.append("props/Book_5")
	xfs.append(Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.5, 0.37, 3.2)))
	if scifi:
		names.append_array(["scifi/Prop_Crate3", "scifi/Prop_Crate4"])
		xfs.append(Transform3D(Basis(Vector3.UP, 0.2) * Basis.from_scale(Vector3.ONE * 0.6), Vector3(1.0, 0, 0.4)))
		xfs.append(Transform3D(Basis(Vector3.UP, -0.3) * Basis.from_scale(Vector3.ONE * 0.6), Vector3(-1.05, 0, 0.6)))
	else:
		names.append_array(["props/Bag", "props/Pot_1", "props/Rope_1"])
		xfs.append(Transform3D(Basis(Vector3.UP, 0.5) * Basis.from_scale(Vector3.ONE * 0.8), Vector3(0.95, 0, 0.9)))
		xfs.append(Transform3D(Basis(Vector3.UP, 1.2), fire + Vector3(0.15, 0.06, -0.05)))
		xfs.append(Transform3D(Basis(Vector3.UP, 2.0), Vector3(-0.9, 0.0, 1.4)))
