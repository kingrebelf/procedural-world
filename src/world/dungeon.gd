class_name Dungeon
## The dungeon under a stronghold: levels of rooms joined by corridors (some levels a
## maze of passages), stairs between them, and sealed doors that simple puzzles open,
## each with a note beside it saying what to do. A castle's undercroft, a crypt's
## catacombs or a bunker's sublevels; the higher the stronghold's tier and the zone
## level, the more levels and the bigger each one, so the deep ones lie further out.
##
## The plan follows from the world seed (plan()), so it needs no saving. Chests and
## guards go into the chunks they lie under (stock(), new and old chunks alike, like
## Interiors.stock), the stair's mouth is an opening in the courtyard's ground, and what
## you have done down there (seals opened, levers pulled, rooms seen) is kept in the
## centre chunk's "dgn" entry, saved and shared like any other chunk edit. DungeonNode
## builds it near you; Dungeons runs the nodes.
##
## Plan space: x right and z toward the gate (+z), as Stronghold.layout's, metres from
## the stronghold's middle; y is the world's. A level is an n by n grid of CELL cells.

const VERSION := 1
const CELL := 4.0
const DEPTH := 9.0 ## the first level's floor under the courtyard (below tower footings)
const LEVEL_H := 5.0
const ROOM_H := 3.4
const HALL_H := 4.4 ## rooms three cells or more each way
const CORR_H := 3.0
const CORR_HALF := 1.2 ## a passage is 2.4 m wide
const WALL := 0.5
const DOOR_HALF := 1.0
const DOOR_H := 2.6
const RUN := 3 ## cells a stair runs
const COVER := 1.6 ## earth kept over a ceiling, or the cell is not dug
const STAIR_W := 2.4

## Cell kinds.
const ROCK := 0
const ROOM := 1
const CORR := 2
const STAIR := 3 ## a flight down from this level
const UNDER := 4 ## the lower end of a flight from the level above runs through here
const ENTRY := 5 ## the flight down from the courtyard

## Edge bits 1, 2, 4, 8 for these.
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

const NAMES := ["Castle Undercroft", "Crypt Catacombs", "Bunker Sublevels"]
const KINDS := [
	["guard", "store", "cells", "armory", "library", "crypt", "store", "guard"],
	["ossuary", "chapel", "cells", "library", "store", "crypt", "ossuary"],
	["barracks", "control", "store", "lab", "armory", "barracks", "store"],
]
const ROOM_NAMES := {"entry": "stair hall", "landing": "landing", "vault": "treasury", "hall": "great hall",
	"guard": "guard room", "store": "storeroom", "cells": "cells", "armory": "armoury", "library": "library",
	"crypt": "crypt", "ossuary": "ossuary", "chapel": "chapel", "barracks": "barracks", "control": "control room",
	"lab": "laboratory"}
const ORDINALS := ["first", "second", "third", "fourth"]
## [the sealed door, a lever, a key, plates, a brazier] by era.
const WORDS := [
	["iron gate", "lever", "iron key", "worn flagstones", "brazier"],
	["rusted gate", "lever", "bone key", "worn flagstones", "brazier"],
	["blast door", "breaker switch", "keycard", "pressure pads", "power coupling"],
]
const PUZZLES := ["lever", "key", "plates", "braziers"]

# --- Plan space --------------------------------------------------------------------

static func floor_y(pl: Dictionary, lv: int) -> float:
	return float(pl["y0"]) - DEPTH - lv * LEVEL_H

static func centre(pl: Dictionary, cell: Vector2i) -> Vector2:
	var half: int = int(pl["n"]) >> 1
	return Vector2((cell.x - half + 0.5) * CELL, (cell.y - half + 0.5) * CELL)

static func cell_at(pl: Dictionary, q: Vector2) -> Vector2i:
	var half: int = int(pl["n"]) >> 1
	return Vector2i(floori(q.x / CELL) + half, floori(q.y / CELL) + half)

static func to_world(pl: Dictionary, q: Vector3) -> Vector3:
	var v: Vector2 = Vector2(q.x, q.z).rotated(-float(pl["yaw"])) + (pl["c"] as Vector2)
	return Vector3(v.x, q.y, v.y)

static func to_plan(pl: Dictionary, p: Vector3) -> Vector3:
	var v := (Vector2(p.x, p.z) - (pl["c"] as Vector2)).rotated(float(pl["yaw"]))
	return Vector3(v.x, p.y, v.y)

static func inside(pl: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(pl["n"]) and c.y < int(pl["n"])

static func kind(pl: Dictionary, lv: int, c: Vector2i) -> int:
	if lv < 0 or lv >= pl["levels"].size() or not inside(pl, c):
		return ROCK
	return int(pl["levels"][lv]["k"][c.y * int(pl["n"]) + c.x])

static func room_of(pl: Dictionary, lv: int, c: Vector2i) -> int:
	if lv < 0 or lv >= pl["levels"].size() or not inside(pl, c):
		return -1
	return int(pl["levels"][lv]["room"][c.y * int(pl["n"]) + c.x])

static func is_open(pl: Dictionary, lv: int, c: Vector2i, d: int) -> bool:
	if lv < 0 or lv >= pl["levels"].size() or not inside(pl, c):
		return false
	return int(pl["levels"][lv]["open"][c.y * int(pl["n"]) + c.x]) & (1 << d) != 0

static func door_at(pl: Dictionary, lv: int, c: Vector2i, d: int) -> int:
	return int(pl["door_at"].get("%d:%d:%d:%d" % [lv, c.x, c.y, d], -1))

## The stair's descent direction at one of its cells, or -1.
static func stair_dir(pl: Dictionary, lv: int, c: Vector2i) -> int:
	return int(pl["levels"][lv]["sdir"].get(c, -1)) if lv >= 0 and lv < pl["levels"].size() else -1

## Where the entrance stair's mouth opens in the courtyard (plan x, z of its top step).
static func mouth(pl: Dictionary) -> Vector2:
	var top: Vector2i = pl["entry"]["top"]
	return centre(pl, top) + Vector2(0, CELL * 0.5)

## Height of a flight's tread at plan point q in one of its cells: from `hi` at its top
## edge down to `lo` at its foot, RUN cells on.
static func stair_height(pl: Dictionary, lv: int, c: Vector2i, q: Vector2) -> float:
	var d := stair_dir(pl, lv, c)
	var top := _stair_top(pl, lv, c, d)
	var dv := Vector2(DIRS[d])
	var along := clampf((q - (centre(pl, top) - dv * CELL * 0.5)).dot(dv) / (RUN * CELL), 0.0, 1.0)
	var hi := floor_y(pl, lv) if kind(pl, lv, c) == STAIR else float(pl["y0"])
	var lo := floor_y(pl, lv + 1) if kind(pl, lv, c) == STAIR else floor_y(pl, 0)
	return lerpf(hi, lo, along)

## The first cell of the flight that `c` is part of.
static func _stair_top(pl: Dictionary, lv: int, c: Vector2i, d: int) -> Vector2i:
	var k := kind(pl, lv, c)
	var t := c
	while kind(pl, lv, t - DIRS[d]) == k and stair_dir(pl, lv, t - DIRS[d]) == d:
		t -= DIRS[d]
	return t

# --- Planning ----------------------------------------------------------------------

static var _cache := {}
static var _lock := Mutex.new()

## The dungeon under stronghold `f` (Stronghold.at_cell). Cached; safe from any thread.
static func plan(g: ChunkGenerator, f: Dictionary) -> Dictionary:
	var key := "%d:%d:%d:%d" % [g.seed, f["cx"], f["cz"], 1 if g.rivers else 0]
	_lock.lock()
	var have = _cache.get(key)
	_lock.unlock()
	if have != null:
		return have
	var pl := _make(g, f)
	_lock.lock()
	if _cache.size() > 24:
		_cache.clear()
	_cache[key] = pl
	_lock.unlock()
	return pl

static func _ground(g: ChunkGenerator, f: Dictionary, p: Vector2) -> float:
	var h := g.field.height(p.x, p.y, g.field.era_weights(p.x, p.y))
	var d := p.distance_to(f["center"])
	if d < float(f["outer"]):
		h = lerpf(h, float(f["target_h"]), 1.0 - smoothstep(float(f["inner"]), float(f["outer"]), d))
	if g.rivers and g.field.river_t(p.x, p.y) < WorldField.RIVER_REACH + 8.0:
		h -= 8.0 # a river's bed is cut below the land
	return h

static func _make(g: ChunkGenerator, f: Dictionary) -> Dictionary:
	var r := WHash.rng(g.seed, f["cx"], f["cz"], 950)
	var c: Vector2 = f["center"]
	var tier: int = f["tier"]
	var era: int = f["era"]
	var zone := Eras.zone_level(c.x, c.y)
	var n := clampi(10 + tier * 2 + 2 * int(zone / 20.0), 12, 18)
	var nlv := clampi(tier + (1 if zone >= 25 else 0), 1, 3)
	var half := n >> 1
	var pl := {"id": "%d_%d" % [f["cx"], f["cz"]], "c": c, "yaw": float(f["yaw"]), "era": era, "tier": tier, "zone": zone,
		"n": n, "y0": float(f["target_h"]), "name": NAMES[era], "levels": [], "rooms": [], "doors": [], "door_at": {},
		"stairs": [], "locks": [], "parts": [], "notes": [], "loot": [], "guards": [], "lights": [],
		"chunk": Vector2i(floori(c.x / ChunkGenerator.SIZE), floori(c.y / ChunkGenerator.SIZE))}
	# Which cells have earth enough over them, level by level.
	var hc := PackedFloat32Array()
	hc.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var w := c + Vector2((i - half) * CELL, (j - half) * CELL).rotated(-float(f["yaw"]))
			hc[j * (n + 1) + i] = _ground(g, f, w)
	for lv in nlv:
		var lev := {"k": [], "room": [], "open": [], "ok": [], "maze": false, "sdir": {}}
		var top := floor_y(pl, lv) + HALL_H + 0.3 + COVER
		for j in n:
			for i in n:
				var lo := minf(minf(hc[j * (n + 1) + i], hc[j * (n + 1) + i + 1]), minf(hc[(j + 1) * (n + 1) + i], hc[(j + 1) * (n + 1) + i + 1]))
				lev["k"].append(ROCK)
				lev["room"].append(-1)
				lev["open"].append(0)
				lev["ok"].append(lo >= top)
		pl["levels"].append(lev)
	# The flight down from the courtyard, beside the keep, into the stair hall.
	var ei := half + 2
	for k in RUN:
		var q := Vector2i(ei, half - 1 - k)
		_setk(pl, 0, q, ENTRY)
		pl["levels"][0]["sdir"][q] = 3
		_open(pl, 0, q, 3)
	var land := Vector2i(ei, half - 1 - RUN)
	pl["entry"] = {"top": Vector2i(ei, half - 1), "land": land}
	_add_room(pl, 0, Rect2i(ei - 1, land.y - 2, 3, 3), "entry", true)
	_add_door(pl, 0, land, 1, true)
	# The flights between levels, each starting far from where you came down.
	var start := land
	for lv in nlv - 1:
		var best := {}
		var best_s := -INF
		for t in 80:
			var s0 := Vector2i(r.randi_range(1, n - 2), r.randi_range(1, n - 2))
			var d := r.randi() % 4
			if not _stair_fits(pl, lv, s0, d):
				continue
			var sc := Vector2(s0 - start).length() + r.randf() * 3.0
			if sc > best_s:
				best_s = sc
				best = {"s0": s0, "d": d}
		if best.is_empty():
			pl["levels"].resize(lv + 1)
			break
		var s0: Vector2i = best["s0"]
		var d: int = best["d"]
		_setk(pl, lv, s0, CORR)
		_open(pl, lv, s0, d)
		for k in range(1, RUN + 1):
			var q: Vector2i = s0 + DIRS[d] * k
			_setk(pl, lv, q, STAIR)
			_setk(pl, lv + 1, q, UNDER)
			pl["levels"][lv]["sdir"][q] = d
			if k < RUN:
				_open(pl, lv, q, d)
		var s3: Vector2i = s0 + DIRS[d] * RUN
		var s4: Vector2i = s0 + DIRS[d] * (RUN + 1)
		_set_bit(pl, lv, s3, d)
		_set_bit(pl, lv + 1, s4, (d + 2) % 4)
		var lr := _landing_rect(pl, lv + 1, s4, d)
		if lr.size != Vector2i.ZERO:
			_add_room(pl, lv + 1, lr, "landing")
			_add_door(pl, lv + 1, s4, (d + 2) % 4, true)
		else:
			_setk(pl, lv + 1, s4, CORR)
		var head := _add_door(pl, lv, s0, d, true)
		pl["stairs"].append({"lv": lv, "s0": s0, "d": d, "land": s4, "door": head})
		start = s4
	nlv = pl["levels"].size()
	# Rooms.
	for lv in nlv:
		var want := int(n * n / 16.0) + 2
		var hall := true
		for t in 320:
			if want <= 0:
				break
			var w := r.randi_range(2, 4)
			var dd := r.randi_range(2, 4)
			if hall and t < 40:
				w = r.randi_range(4, 5)
				dd = r.randi_range(3, 4)
			if r.randf() < 0.5:
				var sw := w
				w = dd
				dd = sw
			var rc := Rect2i(r.randi_range(0, n - w), r.randi_range(0, n - dd), w, dd)
			if _room_fits(pl, lv, rc):
				_add_room(pl, lv, rc, "hall" if hall and t < 40 else "")
				hall = false
				want -= 1
		if hall:
			pass # no hall fitted: the biggest room becomes one below
	# Corridors: the rooms (and the stair head) of each level joined by a spanning tree,
	# a few loops added, and on maze levels passages winding through all the rock left.
	var noise: Array = []
	for i in n * n:
		noise.append(r.randf())
	for lv in nlv:
		var nodes: Array = []
		for ri in pl["rooms"].size():
			var rm: Dictionary = pl["rooms"][ri]
			if rm["lv"] == lv:
				nodes.append({"cells": _cells(rm), "room": ri, "c": Vector2(rm["x"] + rm["w"] * 0.5, rm["z"] + rm["d"] * 0.5)})
		if lv < pl["stairs"].size():
			var s0: Vector2i = pl["stairs"][lv]["s0"]
			nodes.append({"cells": [s0], "room": -1, "c": Vector2(s0) + Vector2(0.5, 0.5)})
		var edges := _tree(nodes)
		var deg: Array = []
		deg.resize(nodes.size())
		deg.fill(0)
		for e in edges:
			deg[e[0]] += 1
			deg[e[1]] += 1
		# A dead end room becomes the level's treasury.
		var vault := -1
		var far := -1.0
		for i in nodes.size():
			var ri: int = nodes[i]["room"]
			if ri < 0 or deg[i] != 1 or pl["rooms"][ri]["kind"] != "":
				continue
			var from: Vector2i = pl["stairs"][lv - 1]["land"] if lv > 0 else land
			var dist := (nodes[i]["c"] as Vector2).distance_to(Vector2(from)) + r.randf() * 4.0
			if dist > far:
				far = dist
				vault = i
		if vault >= 0 and (nodes.size() >= 3 or lv > 0):
			pl["rooms"][nodes[vault]["room"]]["kind"] = "vault"
		else:
			vault = -1
		var maze: bool = era == Eras.FANTASY or (lv >= 1 and r.randf() < 0.5) or (lv == 0 and tier >= 2 and r.randf() < 0.3)
		pl["levels"][lv]["maze"] = maze
		var loops := 1 + tier + (0 if maze else 1)
		for t in loops * 6:
			if loops <= 0 or nodes.size() < 4:
				break
			var a := r.randi() % nodes.size()
			var b := r.randi() % nodes.size()
			if a == b or a == vault or b == vault or (nodes[a]["c"] as Vector2).distance_to(nodes[b]["c"]) > n * 0.55:
				continue
			var dup := false
			for e in edges:
				if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
					dup = true
			if not dup:
				edges.append([a, b])
				loops -= 1
		for e in edges:
			_carve(pl, lv, nodes[e[0]], nodes[e[1]], noise)
		if maze:
			_maze(pl, lv, r, vault, nodes)
	_prune(pl)
	_name_rooms(pl, r)
	_seal(pl, r)
	_furnish(pl, r)
	return pl

static func _setk(pl: Dictionary, lv: int, c: Vector2i, k: int) -> void:
	pl["levels"][lv]["k"][c.y * int(pl["n"]) + c.x] = k

static func _ok(pl: Dictionary, lv: int, c: Vector2i) -> bool:
	return inside(pl, c) and bool(pl["levels"][lv]["ok"][c.y * int(pl["n"]) + c.x])

static func _set_bit(pl: Dictionary, lv: int, c: Vector2i, d: int) -> void:
	var i := c.y * int(pl["n"]) + c.x
	pl["levels"][lv]["open"][i] = int(pl["levels"][lv]["open"][i]) | (1 << d)

## Opens the edge from c toward d, on both sides.
static func _open(pl: Dictionary, lv: int, c: Vector2i, d: int) -> void:
	_set_bit(pl, lv, c, d)
	if inside(pl, c + DIRS[d]):
		_set_bit(pl, lv, c + DIRS[d], (d + 2) % 4)

static func _add_door(pl: Dictionary, lv: int, a: Vector2i, d: int, stair := false) -> int:
	var key := "%d:%d:%d:%d" % [lv, a.x, a.y, d]
	if pl["door_at"].has(key):
		return int(pl["door_at"][key])
	var i: int = pl["doors"].size()
	pl["doors"].append({"lv": lv, "a": a, "d": d, "stair": stair, "lock": -1})
	pl["door_at"][key] = i
	var b: Vector2i = a + DIRS[d]
	pl["door_at"]["%d:%d:%d:%d" % [lv, b.x, b.y, (d + 2) % 4]] = i
	var ri := room_of(pl, lv, a)
	if ri >= 0:
		pl["rooms"][ri]["doors"].append(i)
	var rb := room_of(pl, lv, b)
	if rb >= 0 and rb != ri:
		pl["rooms"][rb]["doors"].append(i)
	return i

static func _add_room(pl: Dictionary, lv: int, rc: Rect2i, k: String, force := false) -> int:
	var ri: int = pl["rooms"].size()
	pl["rooms"].append({"lv": lv, "x": rc.position.x, "z": rc.position.y, "w": rc.size.x, "d": rc.size.y, "kind": k,
		"h": HALL_H if rc.size.x >= 3 and rc.size.y >= 3 else ROOM_H, "doors": [], "used": {}})
	for j in range(rc.position.y, rc.end.y):
		for i in range(rc.position.x, rc.end.x):
			var q := Vector2i(i, j)
			if force and not inside(pl, q):
				continue
			_setk(pl, lv, q, ROOM)
			pl["levels"][lv]["room"][j * int(pl["n"]) + i] = ri
			if i + 1 < rc.end.x:
				_open(pl, lv, q, 0)
			if j + 1 < rc.end.y:
				_open(pl, lv, q, 1)
	return ri

static func _cells(rm: Dictionary) -> Array:
	var out: Array = []
	for j in range(int(rm["z"]), int(rm["z"]) + int(rm["d"])):
		for i in range(int(rm["x"]), int(rm["x"]) + int(rm["w"])):
			out.append(Vector2i(i, j))
	return out

## Room for a flight from s0 heading d: its head free on this level, its cells free here
## and below, and the cell it lands in free below.
static func _stair_fits(pl: Dictionary, lv: int, s0: Vector2i, d: int) -> bool:
	for k in RUN + 2:
		var q: Vector2i = s0 + DIRS[d] * k
		if not inside(pl, q):
			return false
		if k <= RUN and (kind(pl, lv, q) != ROCK or not _ok(pl, lv, q)):
			return false
		if k >= 1 and (kind(pl, lv + 1, q) != ROCK or not _ok(pl, lv + 1, q)):
			return false
	return true

## A landing room on the far side of s4 (the flight came in heading d), or a zero rect.
static func _landing_rect(pl: Dictionary, lv: int, s4: Vector2i, d: int) -> Rect2i:
	var dv: Vector2i = DIRS[d]
	var side := Vector2i(absi(dv.y), absi(dv.x))
	for size in [[3, 3], [2, 3], [2, 2]]:
		var along: int = size[0]
		var across: int = size[1]
		for shift in range(0, across):
			var a := s4 - side * shift
			var b := s4 + dv * (along - 1) + side * (across - 1 - shift)
			var rc := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(b.x - a.x) + 1, absi(b.y - a.y) + 1))
			if _room_fits(pl, lv, rc):
				return rc
	return Rect2i()

## All its cells dug-able rock, and no other room touching it.
static func _room_fits(pl: Dictionary, lv: int, rc: Rect2i) -> bool:
	for j in range(rc.position.y - 1, rc.end.y + 1):
		for i in range(rc.position.x - 1, rc.end.x + 1):
			var q := Vector2i(i, j)
			var in_rc := rc.has_point(q)
			if in_rc and (kind(pl, lv, q) != ROCK or not _ok(pl, lv, q)):
				return false
			if not in_rc and inside(pl, q) and kind(pl, lv, q) == ROOM:
				return false
	return true

## Prim's spanning tree over the nodes' middles: [[a, b], ...].
static func _tree(nodes: Array) -> Array:
	var edges: Array = []
	if nodes.size() < 2:
		return edges
	var inside_t := {0: true}
	while inside_t.size() < nodes.size():
		var best := INF
		var pair := [-1, -1]
		for a in inside_t:
			for b in nodes.size():
				if inside_t.has(b):
					continue
				var dd := (nodes[a]["c"] as Vector2).distance_to(nodes[b]["c"])
				if dd < best:
					best = dd
					pair = [a, b]
		edges.append(pair)
		inside_t[pair[1]] = true
	return edges

static func _passable(pl: Dictionary, lv: int, q: Vector2i) -> bool:
	var k := kind(pl, lv, q)
	return inside(pl, q) and _ok(pl, lv, q) and (k == ROCK or k == CORR)

## Digs the cheapest passage from node A to node B (reusing passages already dug), with
## a doorway where it meets a room. False if the rock between can't be dug.
static func _carve(pl: Dictionary, lv: int, A: Dictionary, B: Dictionary, noise: Array) -> bool:
	var n: int = pl["n"]
	var in_a := {}
	for q in A["cells"]:
		in_a[q] = true
	var in_b := {}
	for q in B["cells"]:
		in_b[q] = true
	for a in A["cells"]:
		for d in 4:
			if in_b.has(a + DIRS[d]):
				_join(pl, lv, a, d)
				return true
	var dist := {}
	var prev := {}
	var done := {}
	var frontier: Array = []
	for a in A["cells"]:
		for d in 4:
			var o: Vector2i = a + DIRS[d]
			if in_a.has(o) or in_b.has(o) or not _passable(pl, lv, o):
				continue
			var cst := _step_cost(pl, lv, o, noise)
			if cst < float(dist.get(o, INF)):
				dist[o] = cst
				prev[o] = [a, d]
				frontier.append(o)
	while not frontier.is_empty():
		var bi := 0
		for i in frontier.size():
			if float(dist[frontier[i]]) < float(dist[frontier[bi]]):
				bi = i
		var u: Vector2i = frontier[bi]
		frontier.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		for d in 4:
			if in_b.has(u + DIRS[d]):
				# Found: dig back to A.
				_join(pl, lv, u, d)
				var at := u
				while true:
					var pv: Array = prev[at]
					var from: Vector2i = pv[0]
					var fd: int = pv[1]
					if kind(pl, lv, at) == ROCK:
						_setk(pl, lv, at, CORR)
					_join(pl, lv, from, fd)
					if in_a.has(from):
						break
					at = from
				return true
		for d in 4:
			var v: Vector2i = u + DIRS[d]
			if done.has(v) or in_a.has(v) or in_b.has(v) or not _passable(pl, lv, v):
				continue
			var nd := float(dist[u]) + _step_cost(pl, lv, v, noise)
			if nd < float(dist.get(v, INF)):
				dist[v] = nd
				prev[v] = [u, d]
				frontier.append(v)
	return false

static func _step_cost(pl: Dictionary, lv: int, q: Vector2i, noise: Array) -> float:
	if kind(pl, lv, q) == CORR:
		return 1.0
	return 2.0 + float(noise[q.y * int(pl["n"]) + q.x]) * 1.5

## Opens the edge from a toward d, with a doorway if a room is on either side.
static func _join(pl: Dictionary, lv: int, a: Vector2i, d: int) -> void:
	var b: Vector2i = a + DIRS[d]
	if kind(pl, lv, a) == ROCK:
		_setk(pl, lv, a, CORR)
	if kind(pl, lv, b) == ROCK:
		_setk(pl, lv, b, CORR)
	_open(pl, lv, a, d)
	if kind(pl, lv, a) == ROOM:
		_add_door(pl, lv, a, d)
	elif kind(pl, lv, b) == ROOM:
		_add_door(pl, lv, b, (d + 2) % 4)

## Passages winding off through the rock that is left: a growing-tree maze from the
## passages already dug, mostly following its newest end, so it makes long winding runs
## with side branches and dead ends. Then a few extra ways into rooms it passes.
static func _maze(pl: Dictionary, lv: int, r: RandomNumberGenerator, vault: int, nodes: Array) -> void:
	var n: int = pl["n"]
	var free := 0
	for j in n:
		for i in n:
			if _passable(pl, lv, Vector2i(i, j)) and kind(pl, lv, Vector2i(i, j)) == ROCK:
				free += 1
	var budget := int(free * 0.7)
	var live: Array = []
	for j in n:
		for i in n:
			if kind(pl, lv, Vector2i(i, j)) == CORR:
				live.append(Vector2i(i, j))
	while budget > 0 and not live.is_empty():
		var li := live.size() - 1 if r.randf() < 0.75 else r.randi() % live.size()
		var u: Vector2i = live[li]
		var opts: Array = []
		for d in 4:
			var v: Vector2i = u + DIRS[d]
			if inside(pl, v) and kind(pl, lv, v) == ROCK and _ok(pl, lv, v):
				opts.append(d)
		if opts.is_empty():
			live.remove_at(li)
			continue
		var d: int = opts[r.randi() % opts.size()]
		var v: Vector2i = u + DIRS[d]
		_setk(pl, lv, v, CORR)
		_open(pl, lv, u, d)
		live.append(v)
		budget -= 1
	var vault_room: int = nodes[vault]["room"] if vault >= 0 else -1
	var extra := 2 + r.randi() % 3
	for t in 60:
		if extra <= 0:
			break
		var q := Vector2i(r.randi() % n, r.randi() % n)
		var ri := room_of(pl, lv, q)
		if ri < 0 or ri == vault_room or pl["rooms"][ri]["kind"] in ["entry", "landing"]:
			continue
		var d := r.randi() % 4
		var o: Vector2i = q + DIRS[d]
		if kind(pl, lv, o) != CORR or is_open(pl, lv, q, d):
			continue
		var near := false
		for di in pl["rooms"][ri]["doors"]:
			var dr: Dictionary = pl["doors"][di]
			if (Vector2(dr["a"]) - Vector2(q)).length() < 1.5:
				near = true
		if near:
			continue
		_join(pl, lv, q, d)
		extra -= 1

## Rooms no passage reached are filled back in; a level whose stair head can't be reached
## is the last.
static func _prune(pl: Dictionary) -> void:
	var seen := _reach(pl, func(_li: int) -> bool: return true)
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		var any := false
		for q in _cells(rm):
			if seen.has(_key(rm["lv"], q)):
				any = true
		if not any:
			rm["kind"] = "gone"
			for q in _cells(rm):
				_setk(pl, rm["lv"], q, ROCK)
				pl["levels"][rm["lv"]]["room"][q.y * int(pl["n"]) + q.x] = -1
				pl["levels"][rm["lv"]]["open"][q.y * int(pl["n"]) + q.x] = 0
	for si in pl["stairs"].size():
		var s: Dictionary = pl["stairs"][si]
		if not seen.has(_key(s["lv"], s["s0"])):
			pl["stairs"].resize(si)
			pl["levels"].resize(si + 1)
			break
	for ri in pl["rooms"].size():
		if int(pl["rooms"][ri]["lv"]) >= pl["levels"].size():
			pl["rooms"][ri]["kind"] = "gone"

static func _key(lv: int, q: Vector2i) -> String:
	return "%d:%d:%d" % [lv, q.x, q.y]

## Where you can walk on from (lv, c): [[lv, cell], ...]. `opened` says whether seal li
## is open.
static func links(pl: Dictionary, lv: int, c: Vector2i, opened: Callable) -> Array:
	var out: Array = []
	var k := kind(pl, lv, c)
	for d in 4:
		if not is_open(pl, lv, c, d):
			continue
		var di := door_at(pl, lv, c, d)
		if di >= 0:
			var li: int = pl["doors"][di]["lock"]
			if li >= 0 and not opened.call(li):
				continue
		var nb: Vector2i = c + DIRS[d]
		if k == STAIR and d == stair_dir(pl, lv, c) and kind(pl, lv, nb) != STAIR:
			out.append([lv + 1, nb]) # off the foot of the flight
		elif kind(pl, lv, nb) == UNDER:
			out.append([lv - 1, nb]) # onto a flight from its foot
		elif inside(pl, nb):
			out.append([lv, nb])
	return out

## Every cell you can reach from the stair hall: key -> steps.
static func _reach(pl: Dictionary, opened: Callable) -> Dictionary:
	var land: Vector2i = pl["entry"]["land"]
	var seen := {_key(0, land): 0}
	var q: Array = [[0, land]]
	var h := 0
	while h < q.size():
		var cur: Array = q[h]
		h += 1
		var s: int = seen[_key(cur[0], cur[1])]
		for nx in links(pl, cur[0], cur[1], opened):
			var k := _key(nx[0], nx[1])
			if not seen.has(k):
				seen[k] = s + 1
				q.append(nx)
	return seen

static func _name_rooms(pl: Dictionary, r: RandomNumberGenerator) -> void:
	var list: Array = KINDS[pl["era"]].duplicate()
	var deepest: int = pl["levels"].size() - 1
	var halls := 0
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["kind"] == "hall":
			halls += 1
	if halls == 0:
		# The biggest room on the deepest level becomes the great hall.
		var best := -1
		for ri in pl["rooms"].size():
			var rm: Dictionary = pl["rooms"][ri]
			if rm["kind"] == "" and rm["lv"] == deepest and (best < 0 or rm["w"] * rm["d"] > pl["rooms"][best]["w"] * pl["rooms"][best]["d"]):
				best = ri
		if best >= 0 and pl["rooms"][best]["w"] * pl["rooms"][best]["d"] >= 6:
			pl["rooms"][best]["kind"] = "hall"
	var k := r.randi() % list.size()
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["kind"] == "":
			rm["kind"] = list[k % list.size()]
			k += 1 + (r.randi() % 2)

## A name for a room in a hint: "the guard room on the second level".
static func room_phrase(pl: Dictionary, ri: int, from_lv := -1) -> String:
	var rm: Dictionary = pl["rooms"][ri]
	var name: String = ROOM_NAMES.get(rm["kind"], String(rm["kind"]))
	if from_lv == int(rm["lv"]):
		return "the %s on this level" % name
	return "the %s on the %s level" % [name, ORDINALS[mini(int(rm["lv"]), 3)]]

# --- Seals -------------------------------------------------------------------------

## Seals: each treasury's door, and the stair heads of deeper strongholds. Each has a
## simple puzzle whose parts lie where you can already get to, and a note at the door.
static func _seal(pl: Dictionary, r: RandomNumberGenerator) -> void:
	var order: Array = []
	for lv in pl["levels"].size():
		for ri in pl["rooms"].size():
			var rm: Dictionary = pl["rooms"][ri]
			if rm["lv"] == lv and rm["kind"] == "vault" and rm["doors"].size() == 1:
				order.append({"door": rm["doors"][0], "what": "vault", "lv": lv, "room": ri})
		if lv < pl["stairs"].size() and (int(pl["tier"]) >= 2 or lv >= 1 or r.randf() < 0.5):
			order.append({"door": pl["stairs"][lv]["door"], "what": "stair", "lv": lv})
	var kinds := PUZZLES.duplicate()
	for i in range(kinds.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	for i in order.size():
		var lk: Dictionary = order[i]
		lk["kind"] = kinds[i % kinds.size()]
		pl["doors"][lk["door"]]["lock"] = i
		pl["locks"].append(lk)
	for i in pl["locks"].size():
		_place_parts(pl, i, r)

## The door's cell on the side you come from, and the way from it to the door.
static func front_of(pl: Dictionary, li: int) -> Array:
	var lk: Dictionary = pl["locks"][li]
	var dr: Dictionary = pl["doors"][lk["door"]]
	if lk["what"] == "vault":
		return [dr["a"] + DIRS[dr["d"]], (int(dr["d"]) + 2) % 4]
	return [dr["a"], int(dr["d"])]

static func _place_parts(pl: Dictionary, li: int, r: RandomNumberGenerator) -> void:
	var lk: Dictionary = pl["locks"][li]
	var lv: int = lk["lv"]
	var seen := _reach(pl, func(x: int) -> bool: return x < li)
	var fr := front_of(pl, li)
	var front: Vector2i = fr[0]
	var fd: int = fr[1]
	var front_room := room_of(pl, lv, front)
	var era: int = pl["era"]
	# Rooms you can already reach, nearest level first, not the one at the door.
	var cands: Array = []
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["kind"] in ["vault", "gone"] or ri == front_room:
			continue
		var steps := -1
		for q in _cells(rm):
			var k := _key(rm["lv"], q)
			if seen.has(k):
				steps = int(seen[k])
		if steps < 0:
			continue
		cands.append([ri, steps + absi(int(rm["lv"]) - lv) * 40 + r.randi() % 6])
	cands.sort_custom(func(a, b): return a[1] < b[1])
	var pick := -1
	if not cands.is_empty():
		# Not the nearest room (that's no puzzle) unless it's the only one.
		pick = cands[mini(1 + r.randi() % 2, cands.size() - 1)][0]
		if lk["kind"] == "plates":
			pick = cands[mini(r.randi() % 2, cands.size() - 1)][0]
	if pick < 0 and lk["kind"] in ["lever", "key", "plates"]:
		lk["kind"] = "braziers"
	lk["room"] = pick
	var w: Array = WORDS[era]
	var gate: String = w[0]
	var what := "the treasury" if lk["what"] == "vault" else "the stair down"
	var where := room_phrase(pl, pick, lv) if pick >= 0 else ""
	var parts: Array = []
	match lk["kind"]:
		"lever":
			var s := _take_slot(pl, pick, "lever", r)
			parts.append({"kind": "lever", "p": s["w"], "yaw": s["yaw"], "lv": pl["rooms"][pick]["lv"], "room": pick})
			lk["hint"] = "The %s to %s is worked by a %s in %s. Pull it and the %s will rise." % [gate, what, w[1], where, gate]
			lk["sealed"] = "Sealed. A %s in %s works it" % [w[1], where]
		"key":
			var cs := _room_spots(pl, pick)
			var at: Vector2 = cs[r.randi() % cs.size()]
			parts.append({"kind": "key", "p": Vector3(at.x, floor_y(pl, pl["rooms"][pick]["lv"]), at.y), "yaw": r.randf() * TAU,
				"lv": pl["rooms"][pick]["lv"], "room": pick})
			lk["hint"] = "The %s to %s is locked. Its %s was left in %s." % [gate, what, w[2], where]
			lk["sealed"] = "Locked. Its %s is in %s" % [w[2], where]
		"plates":
			var cs := _room_spots(pl, pick)
			for k in mini(3, cs.size()):
				var j := r.randi() % cs.size()
				var at: Vector2 = cs[j]
				cs.remove_at(j)
				parts.append({"kind": "plate", "p": Vector3(at.x, floor_y(pl, pl["rooms"][pick]["lv"]), at.y), "yaw": 0.0,
					"lv": pl["rooms"][pick]["lv"], "room": pick})
			lk["hint"] = "The %s to %s answers to the %s in %s. Step on every one of them and it will open." % [gate, what, w[3], where]
			lk["sealed"] = "Sealed. Step on the %s in %s" % [w[3], where]
		"braziers":
			var c := centre(pl, front)
			var dv := Vector2(DIRS[fd])
			var side := Vector2(-dv.y, dv.x)
			var room_side := kind(pl, lv, front) == ROOM
			for sgn: float in [-1.0, 1.0]:
				var at := c + dv * (1.2 if room_side else 0.55) + side * sgn * (1.5 if room_side else 0.82)
				parts.append({"kind": "brazier", "p": Vector3(at.x, floor_y(pl, lv), at.y), "yaw": 0.0, "lv": lv, "room": front_room})
			if pick >= 0:
				var s := _take_slot(pl, pick, "brazier", r)
				parts.append({"kind": "brazier", "p": s["p"], "yaw": s["yaw"], "lv": pl["rooms"][pick]["lv"], "room": pick})
				lk["hint"] = "Light the two %ss before the %s, and the third in %s, and the way to %s will open." % [w[4], gate, where, what]
				lk["sealed"] = "Sealed. Light both %ss here and the third in %s" % [w[4], where]
			else:
				lk["hint"] = "Light the two %ss before the %s and the way to %s will open." % [w[4], gate, what]
				lk["sealed"] = "Sealed. Light the %ss beside it" % w[4]
	lk["parts"] = []
	for p in parts:
		p["lock"] = li
		lk["parts"].append(pl["parts"].size())
		pl["parts"].append(p)
	# The note at the door, on the side you come from.
	var c := centre(pl, front)
	var dv := Vector2(DIRS[fd])
	var side := Vector2(-dv.y, dv.x)
	var p: Vector2
	var yaw: float
	if kind(pl, lv, front) == ROOM:
		p = c + dv * (CELL * 0.5 - WALL * 0.5 - 0.03) + side * 1.65
		yaw = atan2(-dv.x, -dv.y)
	else:
		p = c + dv * 1.7 + side * (CORR_HALF - 0.03)
		yaw = atan2(-side.x, -side.y)
	pl["notes"].append({"lock": li, "p": Vector3(p.x, floor_y(pl, lv) + 1.5, p.y), "yaw": yaw, "lv": lv,
		"title": "Warden's notice" if era != Eras.SCIFI else "Access notice", "text": lk["hint"]})

## Floor spots in a room's open middle (away from its walls), one per cell.
static func _room_spots(pl: Dictionary, ri: int) -> Array:
	var out: Array = []
	for q in _cells(pl["rooms"][ri]):
		out.append(centre(pl, q))
	return out

## Spots along a room's walls: {p: on the floor, 0.5 m out from the wall, w: on the
## wall's face, yaw: facing into the room, side}. Not in front of doorways.
static func slots(pl: Dictionary, ri: int) -> Array:
	var rm: Dictionary = pl["rooms"][ri]
	if rm.has("slots"):
		return rm["slots"]
	var lo := centre(pl, Vector2i(rm["x"], rm["z"])) - Vector2.ONE * (CELL * 0.5 - WALL * 0.5)
	var hi := centre(pl, Vector2i(int(rm["x"]) + int(rm["w"]) - 1, int(rm["z"]) + int(rm["d"]) - 1)) + Vector2.ONE * (CELL * 0.5 - WALL * 0.5)
	var y := floor_y(pl, rm["lv"])
	var out: Array = []
	for side in 4:
		var dv := Vector2(DIRS[side])
		var along := Vector2(-dv.y, dv.x).abs()
		var wall_at := hi if side < 2 else lo
		var a0 := lo.dot(along) + 1.0
		var a1 := hi.dot(along) - 1.0
		var t := a0
		while t <= a1 + 0.01:
			var wpt := along * t + dv.abs() * wall_at.dot(dv.abs())
			var blocked := false
			for di in rm["doors"]:
				var dr: Dictionary = pl["doors"][di]
				if int(dr["lv"]) != int(rm["lv"]):
					continue
				var dside: int = dr["d"] if room_of(pl, dr["lv"], dr["a"]) == ri else (int(dr["d"]) + 2) % 4
				if dside != side:
					continue
				var dc := centre(pl, dr["a"] if room_of(pl, dr["lv"], dr["a"]) == ri else dr["a"] + DIRS[dr["d"]])
				if absf(dc.dot(along) - t) < DOOR_HALF + 0.85:
					blocked = true
			if not blocked:
				var p := wpt - dv * 0.5
				out.append({"p": Vector3(p.x, y, p.y), "w": Vector3(wpt.x, y, wpt.y), "yaw": atan2(-dv.x, -dv.y), "side": side})
			t += 1.6
	rm["slots"] = out
	return out

## A free wall spot of room ri, now taken for `what`.
static func _take_slot(pl: Dictionary, ri: int, what: String, r: RandomNumberGenerator) -> Dictionary:
	var ss := slots(pl, ri)
	var used: Dictionary = pl["rooms"][ri]["used"]
	var free: Array = []
	for i in ss.size():
		if not used.has(i):
			free.append(i)
	if free.is_empty():
		var c := centre(pl, Vector2i(pl["rooms"][ri]["x"], pl["rooms"][ri]["z"]))
		var y := floor_y(pl, pl["rooms"][ri]["lv"])
		return {"p": Vector3(c.x, y, c.y), "w": Vector3(c.x, y, c.y), "yaw": 0.0, "side": -1}
	var i: int = free[r.randi() % free.size()]
	used[i] = what
	return ss[i]

# --- Loot, guards, light ------------------------------------------------------------

static func _furnish(pl: Dictionary, r: RandomNumberGenerator) -> void:
	var tier: int = pl["tier"]
	var deepest: int = pl["levels"].size() - 1
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		var k: String = rm["kind"]
		if k == "gone":
			continue
		var lv: int = rm["lv"]
		var cells := int(rm["w"]) * int(rm["d"])
		var chests := 0
		var luck := 0.25 + 0.12 * tier + 0.1 * lv
		match k:
			"vault":
				chests = 2 + (1 if tier >= 2 else 0)
				luck = 0.55 + 0.2 * tier + 0.1 * lv
			"store", "armory", "library", "lab", "control", "chapel":
				chests = 1 if r.randf() < 0.6 else 0
			"hall":
				chests = 1
				luck += 0.2
			"entry", "landing":
				chests = 0
			_:
				chests = 1 if r.randf() < 0.3 else 0
		for i in chests:
			var s := _take_slot(pl, ri, "chest", r)
			pl["loot"].append({"p": s["p"], "yaw": s["yaw"], "luck": luck, "lv": lv, "room": ri})
		# Who keeps it: guard rooms and barracks most, the great hall its warden.
		var guards := 0
		match k:
			"guard", "barracks", "ossuary":
				guards = 1 + (1 if r.randf() < 0.5 + 0.2 * tier else 0)
			"hall":
				guards = 2
			"vault", "entry":
				guards = 0
			"landing":
				guards = 1 if r.randf() < 0.25 else 0
			_:
				guards = 1 if r.randf() < 0.25 else 0
		var spots := _room_spots(pl, ri)
		for i in guards:
			if spots.is_empty():
				break
			var at: Vector2 = spots[r.randi() % spots.size()] + Vector2(r.randf_range(-0.8, 0.8), r.randf_range(-0.8, 0.8))
			var gt := clampi(tier + (1 if lv >= 1 and r.randf() < 0.35 else 0), 1, 3)
			if k == "hall" and lv == deepest and i == 0:
				gt = mini(tier + 1, 4) # the warden
			pl["guards"].append({"p": Vector3(at.x, floor_y(pl, lv), at.y), "tier": gt, "lv": lv, "room": ri})
		# Torches on the walls (lamps in a bunker's ceiling), one per few cells.
		var lamps := clampi(int(ceil(cells / 4.0)), 1, 3)
		for i in lamps:
			var s := _take_slot(pl, ri, "torch", r)
			pl["lights"].append({"p": s["w"], "yaw": s["yaw"], "lv": lv, "room": ri})
	# Not a crowd: a few more on every level, the warden kept.
	var cap: int = 3 + tier * 3 + pl["levels"].size() * 2
	while pl["guards"].size() > cap:
		pl["guards"].remove_at(1 + r.randi() % (pl["guards"].size() - 1))
	# A notice in the stair hall says what lies below and how it is kept.
	var entry := -1
	for ri in pl["rooms"].size():
		if pl["rooms"][ri]["kind"] == "entry":
			entry = ri
	if entry >= 0:
		var s := _take_slot(pl, entry, "note", r)
		var nl: int = pl["levels"].size()
		var vaults := 0
		for lk in pl["locks"]:
			if lk["what"] == "vault":
				vaults += 1
		var era: int = pl["era"]
		var text := "These halls run %s deep. " % (["one level", "two levels", "three levels"][nl - 1])
		text += "Each holds a treasury behind a sealed %s" % WORDS[era][0] if vaults > 1 else ("A treasury lies behind a sealed %s" % WORDS[era][0] if vaults == 1 else "There is no treasury left")
		text += (", and the stairs down are sealed too. " if pl["locks"].size() > vaults else ". ")
		text += "Every seal has a notice beside it saying how it is opened. Mind the hounds; they know these passages better than you." if era != Eras.SCIFI \
			else "Every seal has a notice beside it saying how it is opened. Security units still patrol the corridors."
		pl["notes"].append({"lock": -1, "p": s["w"] + Vector3(0, 1.5, 0), "yaw": s["yaw"], "lv": 0,
			"title": pl["name"], "text": text})
	# Passages: a torch every few cells where a wall closes them, and now and then a
	# small chest at a maze's dead end.
	var n: int = pl["n"]
	for lv in pl["levels"].size():
		for j in n:
			for i in n:
				var q := Vector2i(i, j)
				if kind(pl, lv, q) != CORR:
					continue
				var ends := 0
				var shut := -1
				for d in 4:
					if is_open(pl, lv, q, d):
						ends += 1
					elif shut < 0 or r.randf() < 0.5:
						shut = d
				var c := centre(pl, q)
				if ends == 1 and pl["levels"][lv]["maze"] and r.randf() < 0.22:
					var od := 0
					for d in 4:
						if is_open(pl, lv, q, d):
							od = d
					var back := Vector2(DIRS[(od + 2) % 4])
					var at := c + back * (CORR_HALF - 0.5)
					pl["loot"].append({"p": Vector3(at.x, floor_y(pl, lv), at.y), "yaw": atan2(-back.x, -back.y), "luck": 0.2 + 0.1 * tier, "lv": lv, "room": -1})
				elif shut >= 0 and (i * 7 + j * 3 + lv) % 5 == 0:
					var dv := Vector2(DIRS[shut])
					var at := c + dv * CORR_HALF
					pl["lights"].append({"p": Vector3(at.x, floor_y(pl, lv), at.y), "yaw": atan2(-dv.x, -dv.y), "lv": lv, "room": -1})

# --- Old and new chunks --------------------------------------------------------------

## Puts the chests and guards of every dungeon under this chunk into it, opens the
## entrance's mouth in its ground and keeps the gatehouse's floor clear of grass. Once
## per chunk (flag "dg_v"), so saved worlds get their dungeons when next loaded.
static func stock(gen: ChunkGenerator, chunk: Dictionary) -> bool:
	if gen == null or not gen.outposts or int(chunk.get("dg_v", 0)) >= VERSION:
		return false
	chunk["dg_v"] = VERSION
	var x0 := float(int(chunk["cx"]) * ChunkGenerator.SIZE)
	var z0 := float(int(chunk["cz"]) * ChunkGenerator.SIZE)
	for f in gen.forts_near(x0, z0, x0 + ChunkGenerator.SIZE, z0 + ChunkGenerator.SIZE):
		_stock_one(plan(gen, f), chunk, x0, z0, gen.seed)
	return true

static func _in_chunk(w: Vector3, x0: float, z0: float) -> bool:
	return w.x >= x0 and w.z >= z0 and w.x < x0 + ChunkGenerator.SIZE and w.z < z0 + ChunkGenerator.SIZE

static func _stock_one(pl: Dictionary, chunk: Dictionary, x0: float, z0: float, seed: int) -> void:
	var era: int = pl["era"]
	var objs: Array = chunk["objects"]
	for li in pl["loot"].size():
		var it: Dictionary = pl["loot"][li]
		var w := to_world(pl, it["p"])
		if not _in_chunk(w, x0, z0):
			continue
		var r := WHash.rng(seed, li, WHash.str_hash(pl["id"]), 952)
		var origin := {"chunk": Vector2i(chunk["cx"], chunk["cz"]), "era": era, "how": "found"}
		objs.append({"i": objs.size(), "t": Eras.CACHE_TYPES[era], "e": era, "p": Vector3(w.x - x0, w.y + Interiors.SINK, w.z - z0),
			"r": float(pl["yaw"]) + float(it["yaw"]), "s": 1.0, "st": {"loot": ItemDB.roll_loot(era, r, origin, it["luck"]), "opened": false, "dg": pl["id"], "dgi": li}})
	var guards: Array = chunk.get("guards", [])
	for gi in pl["guards"].size():
		var gd: Dictionary = pl["guards"][gi]
		var w := to_world(pl, gd["p"])
		if _in_chunk(w, x0, z0):
			guards.append({"id": "dg%s_%d" % [pl["id"], gi], "lx": w.x - x0, "lz": w.z - z0, "ly": w.y, "tier": gd["tier"], "era": era, "dg": pl["id"]})
	if not guards.is_empty():
		chunk["guards"] = guards
	if Vector2i(chunk["cx"], chunk["cz"]) == pl["chunk"] and not chunk.has("dgn"):
		chunk["dgn"] = {"id": pl["id"]}
	# The mouth: ground vertices over the open top of the flight (the gatehouse's walls
	# hide the ragged edge, its floor the rest).
	var m := mouth(pl)
	var hole: PackedByteArray = chunk.get("hole", PackedByteArray())
	var any := false
	const RES := ChunkGenerator.RES
	for j in RES:
		for i in RES:
			var q := to_plan(pl, Vector3(x0 + i, 0, z0 + j))
			if absf(q.x - m.x) <= STAIR_W * 0.5 + 0.2 and q.z <= m.y + 0.4 and q.z >= m.y - 4.6:
				if hole.is_empty():
					hole.resize(RES * RES)
				hole[j * RES + i] = 1
				any = true
	if any:
		chunk["hole"] = hole
	var gc := gatehouse(pl)
	var gw := to_world(pl, Vector3(gc.position.x + gc.size.x * 0.5, 0, gc.position.y + gc.size.y * 0.5))
	var lx := gw.x - x0
	var lz := gw.z - z0
	if lx > -12.0 and lz > -12.0 and lx < ChunkGenerator.SIZE + 12.0 and lz < ChunkGenerator.SIZE + 12.0:
		var ko: PackedFloat32Array = chunk.get("keep_out", PackedFloat32Array())
		ko.append_array([lx, lz, float(pl["yaw"]), -gc.size.x * 0.5, -gc.size.y * 0.5, gc.size.x * 0.5, gc.size.y * 0.5])
		chunk["keep_out"] = ko

## The gatehouse over the mouth, in plan x, z.
static func gatehouse(pl: Dictionary) -> Rect2:
	var m := mouth(pl)
	return Rect2(m.x - 3.2, m.y - 6.6, 6.4, 8.8)

# --- While you are down there ----------------------------------------------------

## Dungeons built near you: id -> {"pl": plan, "node": DungeonNode}. Main thread.
static var active := {}

## The level a point at height y is on (or between, on a flight).
static func level_near(pl: Dictionary, y: float) -> int:
	return clampi(roundi((floor_y(pl, 0) - y + 0.8) / LEVEL_H), 0, pl["levels"].size() - 1)

## Over a built dungeon's ground plan: no sea down there, whatever the depth (the water
## sheet is one plane at sea level, and a dungeon can reach below it).
static func covers(x: float, z: float) -> bool:
	for id in active:
		var pl: Dictionary = active[id]["pl"]
		var q := to_plan(pl, Vector3(x, 0, z))
		var ext := float(pl["n"]) * CELL * 0.5 + 1.0
		if absf(q.x) <= ext and absf(q.z) <= ext:
			return true
	return false

## The dungeon around world point p, or {}.
static func around(p: Vector3) -> Dictionary:
	for id in active:
		var pl: Dictionary = active[id]["pl"]
		var q := to_plan(pl, p)
		var ext := float(pl["n"]) * CELL * 0.5
		if absf(q.x) <= ext and absf(q.z) <= ext and q.y < float(pl["y0"]) - 0.4 and q.y > floor_y(pl, pl["levels"].size() - 1) - 3.0:
			return active[id]
	return {}

## Where something walking in a dungeon stands at p, coming from `from`: the floor's
## height, NAN in rock, behind a wall or a shut seal; null when p is not in a dungeon.
static func walk_floor(p: Vector3, from: Vector3) -> Variant:
	var a := around(p)
	if a.is_empty():
		return null
	var pl: Dictionary = a["pl"]
	var node = a["node"]
	var q := to_plan(pl, p)
	var lv := level_near(pl, q.y)
	var c := cell_at(pl, Vector2(q.x, q.z))
	var at := _walk_cell(pl, lv, c)
	if at.is_empty():
		return NAN
	lv = at[0]
	var o := Vector2(q.x, q.z) - centre(pl, c)
	var k := kind(pl, lv, c)
	var lim := CELL * 0.5 - WALL * 0.5 - 0.35
	if k == CORR:
		var arm := CORR_HALF - 0.3
		var ok := absf(o.x) <= arm and absf(o.y) <= arm
		for d in 4:
			if is_open(pl, lv, c, d):
				var dv := Vector2(DIRS[d])
				ok = ok or (o.dot(dv) > 0.0 and absf(o.dot(Vector2(-dv.y, dv.x))) <= arm)
		if not ok:
			return NAN
	elif k == STAIR or k == ENTRY:
		var d := stair_dir(pl, lv, c)
		var dv := Vector2(DIRS[d])
		if absf(o.dot(Vector2(-dv.y, dv.x))) > STAIR_W * 0.5 - 0.3:
			return NAN
	else:
		# A room: up to its walls, and through a doorway only within its width.
		for ax in 2:
			var off := o.x if ax == 0 else o.y
			if absf(off) <= lim:
				continue
			var d := (0 if off > 0.0 else 2) if ax == 0 else (1 if off > 0.0 else 3)
			if not is_open(pl, lv, c, d):
				return NAN
			var across := o.y if ax == 0 else o.x
			if room_of(pl, lv, c + DIRS[d]) != room_of(pl, lv, c) and absf(across) > DOOR_HALF - 0.3:
				return NAN
	# Into another cell: only through an open way, not a shut seal.
	var fq := to_plan(pl, from)
	var fc := cell_at(pl, Vector2(fq.x, fq.z))
	if fc != c and (fc - c).length_squared() == 1:
		var d := DIRS.find(c - fc)
		var flv := level_near(pl, fq.y)
		var fat := _walk_cell(pl, flv, fc)
		if not fat.is_empty():
			flv = fat[0]
		if not is_open(pl, flv, fc, d):
			return NAN
		var di := door_at(pl, flv, fc, d)
		if di >= 0 and int(pl["doors"][di]["lock"]) >= 0 and node != null and not node.seal_open(int(pl["doors"][di]["lock"])):
			return NAN
	if k == STAIR or k == ENTRY:
		return stair_height(pl, lv, c, Vector2(q.x, q.z))
	return floor_y(pl, lv)

## The level whose cell c you'd be walking in near level lv: [lv] if it's open ground
## there, [lv - 1] if a flight from above runs through it, else [].
static func _walk_cell(pl: Dictionary, lv: int, c: Vector2i) -> Array:
	var k := kind(pl, lv, c)
	if k == ROOM or k == CORR or k == STAIR or k == ENTRY:
		return [lv]
	if k == UNDER:
		return [lv - 1]
	if kind(pl, lv - 1, c) == STAIR:
		return [lv - 1]
	return []

## Steps from every cell to the cell at (lv, c), over open ways: key -> steps.
static func flow(pl: Dictionary, lv: int, c: Vector2i, opened: Callable) -> Dictionary:
	var seen := {_key(lv, c): 0}
	var q: Array = [[lv, c]]
	var h := 0
	while h < q.size() and q.size() < 2000:
		var cur: Array = q[h]
		h += 1
		var s: int = seen[_key(cur[0], cur[1])]
		for nx in links(pl, cur[0], cur[1], opened):
			var k := _key(nx[0], nx[1])
			if not seen.has(k):
				seen[k] = s + 1
				q.append(nx)
	return seen

## How far along you are: rooms seen, seals opened, chests emptied, of how many.
static func room_count(pl: Dictionary) -> int:
	var n := 0
	for rm in pl["rooms"]:
		if rm["kind"] != "gone":
			n += 1
	return n
