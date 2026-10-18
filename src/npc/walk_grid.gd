class_name WalkGrid
extends RefCounted
## Where people and animals can walk: the loaded land on a 2 m grid, each cell keeping how
## steep it is (its steepest grade, rise per metre), whether a road runs through it and
## whether it is under the sea. Routes keep to gentle ground and roads and go round cliffs
## instead of straight up them. A chunk's cells are worked out the first time anyone looks
## there; a route is only searched when the straight way is too steep, on a small grid
## round the trip, with a few searches a frame at most.

const CELL := 2.0
const N := 32 ## cells along a chunk (ChunkGenerator.SIZE / CELL)
const Q := 40.0 ## grade steps per unit of rise per metre in a cell's byte
const WET := 127 ## a cell under the sea: nobody walks there
const ROAD := 128 ## bit set where a road runs through the cell
const PENDING := -2 ## a loaded chunk whose cells wait for a later frame
## Steepest a person walks up or down (35 degrees): a cliff, a crag's face or a mesa's
## side is more, the steepest hill tracks less.
const PERSON := 0.7
## Short of any other way, a person scrambles up a bank this steep (50 degrees), never a
## cliff or a crag's face.
const SCRAMBLE := 1.2
## Animals are surer-footed: they take a steep bank a person goes round, not a cliff.
const ANIMAL := 0.95
const REFRESH_MSEC := 30000 ## look at a chunk's ground again after this long (digging)
const BUILD_PER_FRAME := 2 ## chunks worked out per frame at most (the rest wait a frame)
const SEARCH_USEC := 2500 ## time a frame's route searches may take
const MAX_SPAN := 200 ## cells across the search grid at most (400 m)
const ROAD_COST := 0.6 ## walking a road costs this much of the same ground off it

## Vector2i chunk -> [chunk data (Dictionary), cells (PackedByteArray), built at (msec)]
var _chunks: Dictionary = {}
var _chunk_data: Callable ## Vector2i -> the chunk's data, or {} where it isn't loaded
var _astar := AStarGrid2D.new()
var _frame := -1
var _built := 0
var _spent := 0
var _waits := false ## the last chunk _cells came back empty for is loaded, but waits a frame
var searches := 0
var build_per_frame := BUILD_PER_FRAME ## (tests raise these: they run in one frame)
var search_usec := SEARCH_USEC ## how many routes have been searched (tests and the benchmark read it)

func _init(chunk_data: Callable) -> void:
	_chunk_data = chunk_data
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

static func centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL

## How steep the ground is at (x, z), as rise per metre: INF under the sea, NAN where the
## ground isn't loaded (or this frame has worked out its share of chunks already).
func grade(x: float, z: float) -> float:
	var v := _cell(cell_of(Vector2(x, z)))
	if v < 0:
		return NAN
	return INF if v & 127 == WET else float(v & 127) / Q

func on_road(x: float, z: float) -> bool:
	var v := _cell(cell_of(Vector2(x, z)))
	return v >= 0 and v & ROAD != 0

## True when nothing on the straight way from a to b is steeper than `limit` (where the
## ground is known). The cell they stand in doesn't count: someone pushed onto a slope
## may walk off it.
func clear(a: Vector2, b: Vector2, limit: float) -> bool:
	var lq := int(limit * Q)
	var c := cell_of(a)
	if _cell(c) == PENDING:
		return false
	var end := cell_of(b)
	# Every cell the line passes through, in order (a grid walk, so it never cuts a
	# corner of one it doesn't check).
	var d := b - a
	var sx := 1 if d.x > 0.0 else -1
	var sz := 1 if d.y > 0.0 else -1
	var tdx := absf(CELL / d.x) if d.x != 0.0 else INF
	var tdz := absf(CELL / d.y) if d.y != 0.0 else INF
	var nx := (float(c.x + (1 if sx > 0 else 0)) * CELL - a.x) / d.x if d.x != 0.0 else INF
	var nz := (float(c.y + (1 if sz > 0 else 0)) * CELL - a.y) / d.y if d.y != 0.0 else INF
	var steps := absi(end.x - c.x) + absi(end.y - c.y)
	for i in steps:
		if nx < nz:
			c.x += sx
			nx += tdx
		elif nz < nx:
			c.y += sz
			nz += tdz
		else:
			# Straight through a corner: the two cells beside it both steep is a wall.
			if _over(Vector2i(c.x + sx, c.y), lq) and _over(Vector2i(c.x, c.y + sz), lq):
				return false
			c += Vector2i(sx, sz)
			nx += tdx
			nz += tdz
		if _over(c, lq):
			return false
		if c == end:
			break
	return true

## Too steep, or not worked out yet (so not known to be safe).
func _over(c: Vector2i, lq: int) -> bool:
	var v := _cell(c)
	return v == PENDING or v >= 0 and (v & 127) > lq

## A way from a to b that keeps to ground no steeper than `limit`, preferring gentle
## ground and roads: {"pts": waypoints after a (the last is b, or the nearest place to it
## that can be got to), "reached": whether it gets to b}. Empty when this frame has spent
## its searching time: ask again next frame.
func route(a: Vector2, b: Vector2, limit: float) -> Dictionary:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_built = 0
		_spent = 0
	if _spent >= search_usec:
		return {}
	var t0 := Time.get_ticks_usec()
	var out := _search(a, b, limit)
	_spent += Time.get_ticks_usec() - t0
	searches += 1
	return out

func _search(a: Vector2, b: Vector2, limit: float) -> Dictionary:
	var ca := cell_of(a)
	var cb := cell_of(b)
	var span := maxi(absi(ca.x - cb.x), absi(ca.y - cb.y))
	# Room round the trip to go the long way round a hill.
	var m := clampi(span / 2 + 10, 10, 48)
	var r := Rect2i(mini(ca.x, cb.x) - m, mini(ca.y, cb.y) - m, absi(ca.x - cb.x) + 2 * m + 1, absi(ca.y - cb.y) + 2 * m + 1)
	if r.size.x > MAX_SPAN or r.size.y > MAX_SPAN:
		# Too far to plan at once: head that way and plan again when nearer.
		var mid := a + (b - a).normalized() * float(MAX_SPAN / 3) * CELL
		var part := _search(a, mid, limit)
		part["reached"] = true # not there yet, but nothing in the way so far
		return part
	_astar.region = r
	_astar.update()
	if not _fill(r, int(limit * Q)):
		return {}
	_astar.set_point_solid(ca, false)
	_astar.set_point_solid(cb, false)
	var ids := _astar.get_id_path(ca, cb, true)
	var reached := not ids.is_empty() and ids[ids.size() - 1] == cb
	var pts := PackedVector2Array()
	if ids.size() < 2:
		pts.append(b if reached else a)
		return {"pts": pts, "reached": reached}
	# Pull the path tight: keep only the points where the grid path turns, then from each
	# go straight to the furthest one still in clear sight, so people walk lines and
	# gentle bends, not grid steps.
	var turns: Array[Vector2] = []
	var end := ids.size() - 1
	for i in range(1, end):
		if ids[i + 1] - ids[i] != ids[i] - ids[i - 1]:
			turns.append(centre(ids[i]))
	turns.append(b if reached else centre(ids[end]))
	var at := a
	var i := 0
	while i < turns.size():
		var j := i
		while j + 1 < turns.size() and clear(at, turns[j + 1], limit):
			j += 1
		at = turns[j]
		pts.append(at)
		i = j + 1
	return {"pts": pts, "reached": reached}

## Puts the cells in rect r into the search grid: too steep (or under the sea) is solid,
## the rest cost more the steeper they are and less on a road. Unloaded ground is left
## open at the plain cost. False if some of it isn't worked out yet (search next frame).
func _fill(r: Rect2i, lq: int) -> bool:
	var k0 := Vector2i(r.position.x >> 5, r.position.y >> 5)
	var k1 := Vector2i((r.end.x - 1) >> 5, (r.end.y - 1) >> 5)
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var k := Vector2i(kx, kz)
			var cells := _cells(k)
			if cells.is_empty():
				if _waits:
					return false
				continue
			var bx := kx * N
			var bz := kz * N
			var i0 := maxi(r.position.x - bx, 0)
			var i1 := mini(r.end.x - bx, N)
			var j0 := maxi(r.position.y - bz, 0)
			var j1 := mini(r.end.y - bz, N)
			for j in range(j0, j1):
				var row := j * N
				for i in range(i0, i1):
					var v := cells[row + i]
					if v == 0:
						continue
					var q := v & 127
					var id := Vector2i(bx + i, bz + j)
					if q > lq:
						_astar.set_point_solid(id, true)
					else:
						# A slope near the limit is a hard climb: twice the cost and more.
						var w := 1.0 + 2.5 * float(q) / Q
						if v & ROAD:
							w *= ROAD_COST
						_astar.set_point_weight_scale(id, w)
	return true

## The cell's byte, -1 where the ground isn't loaded, PENDING where it is but this
## frame has worked out its share of chunks already.
func _cell(c: Vector2i) -> int:
	var k := Vector2i(c.x >> 5, c.y >> 5)
	var cells := _cells(k)
	if cells.is_empty():
		return PENDING if _waits else -1
	return cells[(c.y & 31) * N + (c.x & 31)]

func _cells(k: Vector2i) -> PackedByteArray:
	var e: Array = _chunks.get(k, [])
	var data: Dictionary = _chunk_data.call(k)
	if data.is_empty() or not data.has("heights"):
		if not e.is_empty():
			_chunks.erase(k)
		_waits = false
		return PackedByteArray()
	var now := Time.get_ticks_msec()
	if not e.is_empty() and is_same(e[0], data) and now - int(e[2]) < REFRESH_MSEC:
		return e[1]
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_built = 0
		_spent = 0
	if _built >= build_per_frame:
		# Out of time this frame: the old cells if they were there, else not known yet.
		if not e.is_empty():
			return e[1]
		_waits = true
		return PackedByteArray()
	_built += 1
	var cells := build(data)
	_chunks[k] = [data, cells, now]
	if _chunks.size() > 256:
		_forget_far(k)
	return cells

func _forget_far(k: Vector2i) -> void:
	for o in _chunks.keys():
		if maxi(absi(o.x - k.x), absi(o.y - k.y)) > 8:
			_chunks.erase(o)

## A chunk's cells from its heights (sampled every metre): each cell's steepest grade
## between its corners, a road bit and the sea.
static func build(data: Dictionary) -> PackedByteArray:
	var hs: PackedFloat32Array = data["heights"]
	var rb: PackedByteArray = data.get("road", PackedByteArray())
	var res := ChunkGenerator.RES
	var out := PackedByteArray()
	out.resize(N * N)
	const DIAG := 1.0 / (2.0 * 1.41421356)
	const WET_BELOW := ChunkGenerator.WATER_LEVEL - 0.5
	for j in N:
		var r0 := 2 * j * res
		var r1 := r0 + 2 * res
		for i in N:
			var x := 2 * i
			var h00 := hs[r0 + x]
			var h10 := hs[r0 + x + 2]
			var h01 := hs[r1 + x]
			var h11 := hs[r1 + x + 2]
			var g := maxf(maxf(absf(h10 - h00), absf(h11 - h01)), maxf(absf(h01 - h00), absf(h11 - h10))) * 0.5
			g = maxf(g, maxf(absf(h11 - h00), absf(h10 - h01)) * DIAG)
			# The middle of the cell too: a sharp crest or gully between the corners.
			var hm := hs[r0 + res + x + 1]
			g = maxf(g, absf(hm - (h00 + h10 + h01 + h11) * 0.25))
			var v := mini(int(g * Q), WET - 1)
			if hm < WET_BELOW:
				v = WET
			if not rb.is_empty() and rb[r0 + res + x + 1] > 100:
				v |= ROAD
			out[j * N + i] = v
	return out
