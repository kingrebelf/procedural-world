class_name WalkGrid
extends RefCounted
## Where people and animals can walk: the loaded land on a 2 m grid, each cell keeping how
## steep it is (its steepest grade, rise per metre), whether a road runs through it and
## whether it is under the sea. Routes keep to gentle ground and roads and go round cliffs
## instead of straight up them. A chunk's cells are worked out the first time anyone looks
## there; a route is only searched when the straight way is too steep, on a small grid
## round the trip, with a few searches a frame at most.
##
## It also knows the solid things standing about (market stalls, carts, wagons, wells,
## barrels, woodpiles): the straight way is not clear through one, people step round its
## corners (detour) and nobody is ever let inside one (push_out).

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
## A solid's footprint: [x, z of its middle, ux, uz (its length, a unit vector), half
## length, half width], or a disc: [x, z, 0, 0, radius, -1].
const BODY := 0.35 ## how far a person's middle keeps off a solid's side
const BODY_MAX := 1.0 ## the broadest animal's (push_out may be asked with up to this)
const ROUND_BY := 0.3 ## the room a person leaves going round a solid's corner
const BUCKET := 8.0 ## solids are looked up in squares this wide
## Chunk objects people and animals go round (as their colliders stand).
const SOLID_TYPES := {"market_stall": true, "fruit_cart": true, "wagon": true, "barrels": true,
	"well": true, "trader": true, "chest": true, "rune_coffer": true, "supply_pod": true}

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
var _solids: Dictionary = {} ## who stood them there (a chunk, a town's yard) -> footprints
var _buckets: Dictionary = {} ## Vector2i square -> footprints reaching into it
var _stale := false ## _buckets wait to be made again from _solids
var _solid_n := 0

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
## ground is known) and no solid stands across it. The cell they stand in doesn't count:
## someone pushed onto a slope may walk off it (nor a solid they stand in or head into).
func clear(a: Vector2, b: Vector2, limit: float) -> bool:
	return clear_ground(a, b, limit) and first_solid(a, b).is_empty()

## clear(), minding only the ground.
func clear_ground(a: Vector2, b: Vector2, limit: float) -> bool:
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
	# Solids: a cell it reaches well into is shut (grown by half a cell, so even a thin
	# one shuts an unbroken band and no route slips between two cells' middles).
	const STAMP := CELL * 0.5 + 0.05
	for fps: Array in _solids.values():
		for f: PackedFloat32Array in fps:
			var e := _reach(f) + STAMP
			var c0 := cell_of(Vector2(f[0] - e, f[1] - e))
			var c1 := cell_of(Vector2(f[0] + e, f[1] + e))
			for cz in range(maxi(c0.y, r.position.y), mini(c1.y, r.end.y - 1) + 1):
				for cx in range(maxi(c0.x, r.position.x), mini(c1.x, r.end.x - 1) + 1):
					var id := Vector2i(cx, cz)
					if _inside(f, centre(id), STAMP):
						_astar.set_point_solid(id, true)
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
			set_solids(k, [])
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
	set_solids(k, object_solids(data))
	if _chunks.size() > 256:
		_forget_far(k)
	return cells

func _forget_far(k: Vector2i) -> void:
	for o in _chunks.keys():
		if maxi(absi(o.x - k.x), absi(o.y - k.y)) > 8:
			_chunks.erase(o)
			set_solids(o, [])

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

# --- Solids ---------------------------------------------------------------------------

## Stands `fps` (footprints) where people and animals go round them, in place of what
## `owner` stood before (none: takes them all away).
func set_solids(owner: Variant, fps: Array) -> void:
	if fps.is_empty():
		if _solids.erase(owner):
			_stale = true
		return
	if _solids.get(owner) == fps:
		return
	_solids[owner] = fps
	_stale = true

## A chunk's solid objects (stalls, carts, wells...) as their colliders stand.
static func object_solids(data: Dictionary) -> Array:
	var out: Array = []
	var objs: Array = data.get("objects", [])
	if objs.is_empty():
		return out
	var base := Vector3(float(data.get("cx", 0)) * ChunkGenerator.SIZE, 0.0, float(data.get("cz", 0)) * ChunkGenerator.SIZE)
	for o in objs:
		if not SOLID_TYPES.has(o["t"]):
			continue
		var st: Dictionary = o.get("st", {})
		if st.get("gone", false) or st.get("inside", "") != "":
			continue
		var sh: Array = ObjectLibrary.shape_of(o)
		var s := float(o.get("s", 1.0))
		var xf := Transform3D(Basis(Vector3.UP, float(o.get("r", 0.0))).scaled(Vector3(s, s, s)), base + (o["p"] as Vector3))
		xf *= Transform3D(sh[2] if sh.size() > 2 else Basis.IDENTITY, sh[1])
		var f := footprint(sh[0], xf)
		if not f.is_empty():
			out.append(f)
	return out

## The footprint of a box or an upright cylinder at `xf` (world), or empty for any other shape.
static func footprint(shape: Shape3D, xf: Transform3D) -> PackedFloat32Array:
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
	var sx := ax.length()
	if sx < 0.001:
		return PackedFloat32Array()
	var u := ax / sx
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		var sz := Vector2(xf.basis.z.x, xf.basis.z.z).length()
		return PackedFloat32Array([xf.origin.x, xf.origin.z, u.x, u.y, size.x * 0.5 * sx, size.z * 0.5 * sz])
	if shape is CylinderShape3D:
		return PackedFloat32Array([xf.origin.x, xf.origin.z, 0.0, 0.0, (shape as CylinderShape3D).radius * sx, -1.0])
	return PackedFloat32Array()

## Whether someone `r` broad standing at p would be inside a solid.
func solid_at(p: Vector2, r := BODY) -> bool:
	for f: PackedFloat32Array in _near(p):
		if _inside(f, p, r):
			return true
	return false

## The nearest place to p that someone `r` broad (up to BODY_MAX) can stand, out of any
## solid: p itself unless it is inside one, else just outside the nearest side.
func push_out(p: Vector2, r := BODY) -> Vector2:
	for f: PackedFloat32Array in _near(p):
		p = _out_of(f, p, r)
	return p

## The first solid across the straight way from a to b: [how far along (0..1), its
## footprint], or [] if there is none. Solids a or b are inside don't count.
func first_solid(a: Vector2, b: Vector2) -> Array:
	if _stale:
		_index()
	if _solid_n == 0:
		return []
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var q0 := Vector2i(floori(lo.x / BUCKET), floori(lo.y / BUCKET))
	var q1 := Vector2i(floori(hi.x / BUCKET), floori(hi.y / BUCKET))
	var best := INF
	var hit := PackedFloat32Array()
	if (q1.x - q0.x + 1) * (q1.y - q0.y + 1) > _solid_n:
		# A long way: fewer to look at one by one than squares it crosses.
		for fps: Array in _solids.values():
			for f: PackedFloat32Array in fps:
				var t := _cross(f, a, b)
				if t < best:
					best = t
					hit = f
	else:
		for qz in range(q0.y, q1.y + 1):
			for qx in range(q0.x, q1.x + 1):
				for f: PackedFloat32Array in _buckets.get(Vector2i(qx, qz), []):
					var t := _cross(f, a, b)
					if t < best:
						best = t
						hit = f
	return [] if best == INF else [best, hit]

## A way from a to b round the solids in it, corner to corner (no further than a few
## corners, each in clear sight of the last over ground no steeper than `limit`): the
## waypoints after a, ending with b, or empty when there is none (search a route).
func detour(a: Vector2, b: Vector2, limit: float) -> PackedVector2Array:
	var at := a
	var pts := PackedVector2Array()
	for _leg in 5:
		var hit := first_solid(at, b)
		if hit.is_empty():
			if not clear_ground(at, b, limit):
				break
			pts.append(b)
			return pts
		var best := Vector2.INF
		var cost := INF
		for c: Vector2 in _corners(hit[1]):
			if c.distance_squared_to(at) < 0.01 or solid_at(c):
				continue
			var k := at.distance_to(c) + c.distance_to(b)
			if k < cost and clear(at, c, limit):
				cost = k
				best = c
		if best == Vector2.INF:
			break
		pts.append(best)
		at = best
	return PackedVector2Array()

func _near(p: Vector2) -> Array:
	if _stale:
		_index()
	return _buckets.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)), [])

func _index() -> void:
	_stale = false
	_buckets.clear()
	_solid_n = 0
	for fps: Array in _solids.values():
		for f: PackedFloat32Array in fps:
			_solid_n += 1
			var e := _reach(f) + BODY_MAX
			for qz in range(floori((f[1] - e) / BUCKET), floori((f[1] + e) / BUCKET) + 1):
				for qx in range(floori((f[0] - e) / BUCKET), floori((f[0] + e) / BUCKET) + 1):
					var q := Vector2i(qx, qz)
					if not _buckets.has(q):
						_buckets[q] = []
					_buckets[q].append(f)

## How far a solid reaches from its middle.
static func _reach(f: PackedFloat32Array) -> float:
	return f[4] if f[5] < 0.0 else sqrt(f[4] * f[4] + f[5] * f[5])

## p in the solid's own frame: along its length, across it.
static func _local(f: PackedFloat32Array, p: Vector2) -> Vector2:
	var dx := p.x - f[0]
	var dz := p.y - f[1]
	return Vector2(dx * f[2] + dz * f[3], dz * f[2] - dx * f[3])

static func _world(f: PackedFloat32Array, l: Vector2) -> Vector2:
	return Vector2(f[0] + l.x * f[2] - l.y * f[3], f[1] + l.x * f[3] + l.y * f[2])

static func _inside(f: PackedFloat32Array, p: Vector2, r: float) -> bool:
	if f[5] < 0.0:
		return p.distance_squared_to(Vector2(f[0], f[1])) < (f[4] + r) * (f[4] + r)
	var l := _local(f, p)
	return absf(l.x) < f[4] + r and absf(l.y) < f[5] + r

static func _out_of(f: PackedFloat32Array, p: Vector2, r: float) -> Vector2:
	if f[5] < 0.0:
		var c := Vector2(f[0], f[1])
		var rr := f[4] + r
		var d := p.distance_to(c)
		if d >= rr:
			return p
		return c + ((p - c) / d if d > 0.001 else Vector2(1, 0)) * (rr + 0.001)
	var l := _local(f, p)
	var ex := f[4] + r
	var ez := f[5] + r
	var ox := ex - absf(l.x)
	var oz := ez - absf(l.y)
	if ox <= 0.0 or oz <= 0.0:
		return p
	# Out by the nearest side.
	if ox < oz:
		l.x = (ex + 0.001) * (1.0 if l.x >= 0.0 else -1.0)
	else:
		l.y = (ez + 0.001) * (1.0 if l.y >= 0.0 else -1.0)
	return _world(f, l)

## How far along a -> b (0..1) it first comes within BODY of the solid, or INF if it
## never does (or starts or ends inside it).
static func _cross(f: PackedFloat32Array, a: Vector2, b: Vector2) -> float:
	if _inside(f, a, BODY) or _inside(f, b, BODY):
		return INF
	if f[5] < 0.0:
		var c := Vector2(f[0], f[1])
		var d := b - a
		var dd := d.length_squared()
		if dd < 1e-8:
			return INF
		var t := clampf((c - a).dot(d) / dd, 0.0, 1.0)
		var rr := f[4] + BODY
		var m := a + d * t - c
		if m.length_squared() >= rr * rr:
			return INF
		return t - sqrt(rr * rr - m.length_squared()) / sqrt(dd)
	# The way in the box's frame, cut by its four sides (grown by a body).
	var la := _local(f, a)
	var lb := _local(f, b)
	var d := lb - la
	var t0 := 0.0
	var t1 := 1.0
	var ext := [f[4] + BODY, f[5] + BODY]
	for i in 2:
		var o := la[i]
		var v := d[i]
		var e: float = ext[i]
		if absf(v) < 1e-9:
			if absf(o) >= e:
				return INF
			continue
		var ta := (-e - o) / v
		var tb := (e - o) / v
		if ta > tb:
			var sw := ta
			ta = tb
			tb = sw
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 >= t1:
			return INF
	return t0

## Where to go round a solid: just off its corners (a disc's as if it were square).
static func _corners(f: PackedFloat32Array) -> Array:
	var g := BODY + ROUND_BY
	if f[5] < 0.0:
		var e := f[4] + g
		var c := Vector2(f[0], f[1])
		return [c + Vector2(e, e), c + Vector2(-e, e), c + Vector2(e, -e), c + Vector2(-e, -e)]
	var ex := f[4] + g
	var ez := f[5] + g
	return [_world(f, Vector2(ex, ez)), _world(f, Vector2(-ex, ez)), _world(f, Vector2(ex, -ez)), _world(f, Vector2(-ex, -ez))]
