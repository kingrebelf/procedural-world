class_name Caves
## Cave networks under the hills (v10 worlds). Each 320 m cell may hold one: a narrow
## mouth in a steep hillside, an entry passage that dips into the hill, then tunnels that
## branch out to chambers and the odd great cavern, tens of metres under the ground.
##
## The network is planned once per cell from the world seed as a list of primitives
## (tunnels, chamber blobs, rock spikes). Each chunk keeps the primitives that reach it in
## its snapshot ("cave"), plus which terrain vertices open onto the cave ("hole"); the
## rock walls are a signed distance field meshed per chunk with surface nets, so a
## network crosses chunk borders without seams.

const CELL := 320.0
const CHANCE := 0.55
const BORDER := 70.0 ## a network may spread this far past its cell
const VOX := 1.0 ## mesh grid step, metres
const N := int(ChunkGenerator.SIZE / VOX)
const LIP := 0.7 ## walls rise this far above the ground around the mouth
const MIN_FLOOR := ChunkGenerator.WATER_LEVEL + 2.0 ## caves never reach the water table
const COVER := 6.0 ## least rock between a chamber's roof and the ground
const STRIDE := 12 ## floats per primitive
const AIR_K := 2.2 ## smooth union of air spaces
const AMP := 1.1 ## wall roughness
const BIG := 1000.0

enum { TUNNEL, BLOB, SPIKE }

static var _nets := {}
static var _mesh_cache := {}
static var _lock := Mutex.new()
static var _noise: FastNoiseLite
static var _floor_noise: FastNoiseLite
static var _material: ShaderMaterial

static func _ensure_noise() -> void:
	if _noise != null:
		return
	_lock.lock()
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 7331
		n.frequency = 0.11
		n.fractal_octaves = 3
		var f := FastNoiseLite.new()
		f.seed = 9113
		f.frequency = 0.2
		f.fractal_octaves = 2
		_floor_noise = f
		_noise = n
	_lock.unlock()

# --- Planning ----------------------------------------------------------------------

## Primitives of every network that may reach the rectangle, in a fixed global order.
static func prims_near(gen: ChunkGenerator, x0: float, z0: float, x1: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var m := BORDER + 40.0
	for sz in range(int(floor((z0 - m) / CELL)), int(floor((z1 + m) / CELL)) + 1):
		for sx in range(int(floor((x0 - m) / CELL)), int(floor((x1 + m) / CELL)) + 1):
			var net := network(gen, sx, sz)
			if net.is_empty():
				continue
			var ps: PackedFloat32Array = net["prims"]
			for i in ps.size() / STRIDE:
				var bb := _aabb(ps, i * STRIDE)
				if bb.position.x <= x1 and bb.end.x >= x0 and bb.position.z <= z1 and bb.end.z >= z0:
					out.append_array(ps.slice(i * STRIDE, (i + 1) * STRIDE))
	return out

## The network planned for cell (sx, sz), or {}: {prims, mouth, dir, chambers}.
static func network(gen: ChunkGenerator, sx: int, sz: int) -> Dictionary:
	# Rivers and the terrain version reshape the land the plan is made on.
	var key := [gen.seed, sx, sz, WorldField.terrain_v, gen.rivers, Eras.theme]
	_lock.lock()
	var have = _nets.get(key)
	_lock.unlock()
	if have != null:
		return have
	var net := _plan(gen, sx, sz)
	_lock.lock()
	if _nets.size() > 256:
		_nets.clear()
	_nets[key] = net
	_lock.unlock()
	return net

static func _land(gen: ChunkGenerator, p: Vector2) -> float:
	return gen._land_at(p)

## Keeps clear of towns, strongholds and rivers, whose ground is reshaped after planning.
static func _clear(gen: ChunkGenerator, p: Vector2, sites: Array, pad: float) -> bool:
	for s in sites:
		if p.distance_to(s["center"]) < float(s.get("outer", Stronghold.OUTER)) + pad:
			return false
	if gen.rivers and gen.field.river_t(p.x, p.y) < WorldField.RIVER_REACH + 10.0:
		return false
	return true

static func _plan(gen: ChunkGenerator, sx: int, sz: int) -> Dictionary:
	var r := WHash.rng(gen.seed, sx, sz, 811)
	if r.randf() >= CHANCE:
		return {}
	var c0 := Vector2(sx * CELL, sz * CELL)
	var lo := c0 - Vector2(BORDER, BORDER)
	var hi := c0 + Vector2(CELL + BORDER, CELL + BORDER)
	var sites: Array = gen.settlements_near(lo.x, lo.y, hi.x, hi.y) + gen.forts_near(lo.x, lo.y, hi.x, hi.y)
	# The mouth: on a steep hillside with plenty of hill behind it.
	var best := {}
	var best_score := -INF
	for t in 48:
		var p := c0 + Vector2(r.randf_range(50.0, CELL - 50.0), r.randf_range(50.0, CELL - 50.0))
		var h := _land(gen, p)
		if h < MIN_FLOOR + 10.0:
			continue
		var g := Vector2(_land(gen, p + Vector2(1.5, 0)) - _land(gen, p - Vector2(1.5, 0)), _land(gen, p + Vector2(0, 1.5)) - _land(gen, p - Vector2(0, 1.5))) / 3.0
		var s := g.length()
		if s < 0.32 or s > 1.6 or not _clear(gen, p, sites, 40.0):
			continue
		var up := g / s
		var rise := _land(gen, p + up * 16.0) - h
		if rise < 6.0:
			continue
		var score := rise + s * 4.0 + r.randf() * 3.0
		if score > best_score:
			best_score = score
			best = {"p": p, "h": h, "up": up}
	if best.is_empty():
		return {}
	var prims := PackedFloat32Array()
	var mouth: Vector2 = best["p"]
	var dir: Vector2 = best["up"]
	# Entry passage: narrow at the mouth, dipping into the hill until it is well covered.
	var re := r.randf_range(1.9, 2.4)
	var floor0: float = float(best["h"]) - 0.35
	var a := Vector3(mouth.x - dir.x * 2.5, floor0 + 0.55 * re + 0.7, mouth.y - dir.y * 2.5)
	var fa := floor0 + 0.7
	var cur := Vector3(mouth.x, floor0 + 0.55 * re, mouth.y)
	_tunnel(prims, a, cur, re, re, fa, floor0)
	var cur_floor := floor0
	var rad := re
	for step in 10:
		var d2 := dir.rotated(r.randf_range(-0.3, 0.3))
		var q2 := Vector2(cur.x, cur.z) + d2 * 8.0
		var nr := minf(rad + 0.3, 3.0)
		var nf := maxf(cur_floor - 8.0 * r.randf_range(0.25, 0.36), MIN_FLOOR)
		var q := Vector3(q2.x, nf + 0.55 * nr, q2.y)
		_tunnel(prims, cur, q, rad, nr, cur_floor, nf)
		cur = q
		cur_floor = nf
		rad = nr
		dir = d2
		if _land(gen, q2) - (q.y + nr) > 10.0 and step >= 2:
			break
	# Branching tunnels out to chambers.
	var chambers: Array = []
	var nodes: Array = [{"p": cur, "f": cur_floor, "r": rad, "dir": dir}]
	var want := r.randi_range(5, 10)
	var great := r.randf() < 0.6
	for attempt in 70:
		if chambers.size() >= want:
			break
		var from: Dictionary = nodes[r.randi() % nodes.size()] if r.randf() < 0.4 else nodes[-1]
		var dv: Vector2 = (from["dir"] as Vector2).rotated(r.randf_range(-1.3, 1.3))
		var length := r.randf_range(18.0, 42.0)
		var fp: Vector3 = from["p"]
		var q2 := Vector2(fp.x, fp.z) + dv * length
		if q2.x < lo.x or q2.y < lo.y or q2.x > hi.x or q2.y > hi.y or not _clear(gen, q2, sites, 30.0):
			continue
		var land := _land(gen, q2)
		var mid := _land(gen, (Vector2(fp.x, fp.z) + q2) * 0.5)
		var tr := r.randf_range(1.8, 3.2)
		var big := great and chambers.size() >= 2 and r.randf() < 0.35
		var rx := r.randf_range(15.0, 22.0) if big else r.randf_range(5.5, 12.0)
		var ry := r.randf_range(8.0, 11.0) if big else r.randf_range(3.5, 6.5)
		var has_room := r.randf() < 0.7 or big
		var top := ry if has_room else tr
		var depth := r.randf_range(12.0, 30.0)
		var ff: float = from["f"]
		# Floors climb or fall at a walkable grade.
		var nf := clampf(land - depth - top, ff - length * 0.36, ff + length * 0.36)
		if nf < MIN_FLOOR:
			nf = MIN_FLOOR
		if absf(nf - ff) > length * 0.38:
			continue
		var roof := nf + (ry * 1.6 if has_room else tr * 1.6)
		if land - roof < COVER or not _tunnel_covered(gen, fp, Vector3(q2.x, nf, q2.y), ff, tr):
			continue
		if has_room and not _room_covered(gen, q2, nf, rx, ry):
			continue
		var crowd := false
		for ch in chambers:
			if Vector2((ch["p"] as Vector3).x, (ch["p"] as Vector3).z).distance_to(q2) < float(ch["rx"]) + rx + 4.0:
				crowd = true
		if crowd and has_room:
			continue
		var q := Vector3(q2.x, nf + 0.55 * tr, q2.y)
		_tunnel(prims, fp, q, float(from["r"]), tr, ff, nf)
		if has_room:
			var cc := Vector3(q2.x, nf + ry * 0.6, q2.y)
			_chamber(prims, r, cc, rx, ry, nf)
			if big:
				great = false
			chambers.append({"p": cc, "rx": rx, "ry": ry, "f": nf, "big": big, "loot": big or r.randf() < 0.35})
		nodes.append({"p": q, "f": nf, "r": tr, "dir": dv})
	if chambers.is_empty():
		return {}
	return {"prims": prims, "mouth": Vector3(mouth.x, floor0, mouth.y), "dir": best["up"], "chambers": chambers}

## Rock all along a tunnel's roof, so it never opens out of a hillside.
static func _tunnel_covered(gen: ChunkGenerator, a: Vector3, b: Vector3, fa: float, r: float) -> bool:
	var steps := maxi(2, int(Vector2(b.x - a.x, b.z - a.z).length() / 5.0))
	for i in range(1, steps):
		var t := float(i) / steps
		var p := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
		if _land(gen, p) - (lerpf(fa, b.y, t) + r * 1.7 + AMP) < COVER * 0.7:
			return false
	return true

## A chamber is wide, and hills fall away: its walls must be under the ground all round,
## or it would open onto the sky.
static func _room_covered(gen: ChunkGenerator, c: Vector2, fl: float, rx: float, ry: float) -> bool:
	var cy := fl + ry * 0.6
	for a in 10:
		var dir := Vector2.from_angle(a * TAU / 10.0)
		for u in [0.5, 0.85, 1.25]:
			var top := cy + ry * sqrt(maxf(0.0, 1.0 - u * u)) + AMP + 1.0
			if _land(gen, c + dir * rx * u) - top < COVER * (0.8 if u < 1.0 else 0.6):
				return false
	return true

static func _tunnel(ps: PackedFloat32Array, a: Vector3, b: Vector3, ra: float, rb: float, fa: float, fb: float) -> void:
	ps.append_array([TUNNEL, a.x, a.y, a.z, b.x, b.y, b.z, ra, rb, fa, fb, 0.0])

## A chamber of a few overlapping blobs on one floor, hung with stalactites and grown
## with stalagmites.
static func _chamber(ps: PackedFloat32Array, r: RandomNumberGenerator, c: Vector3, rx: float, ry: float, fl: float) -> void:
	var rz := rx * r.randf_range(0.65, 1.0)
	var yaw := r.randf() * TAU
	var bs := Basis(Vector3.UP, yaw)
	ps.append_array([BLOB, c.x, c.y, c.z, rx, ry, rz, yaw, 0.0, fl, 0.0, 0.0])
	for n in r.randi_range(1, 3):
		var off := bs * Vector3(r.randf_range(-0.6, 0.6) * rx, 0, r.randf_range(-0.6, 0.6) * rz)
		var s := r.randf_range(0.45, 0.7)
		var bc := c + off
		bc.y = fl + ry * s * 0.6
		ps.append_array([BLOB, bc.x, bc.y, bc.z, rx * s, ry * s, rz * s, yaw + r.randf(), 0.0, fl, 0.0, 0.0])
	var height := ry * 1.6
	for n in r.randi_range(3, 9):
		var u := Vector2(r.randf_range(-0.7, 0.7), r.randf_range(-0.7, 0.7))
		if u.length() > 0.75:
			continue
		var p := c + bs * Vector3(u.x * rx, 0, u.y * rz)
		var roof := c.y + ry * sqrt(maxf(0.0, 1.0 - u.length_squared())) - 0.4
		var floor_here := fl
		if r.randf() < 0.55:
			var length := minf(r.randf_range(1.5, 4.5), (roof - floor_here) * 0.45)
			var br := r.randf_range(0.7, 1.4)
			ps.append_array([SPIKE, p.x, roof + 1.5, p.z, p.x, roof - length, p.z, br, 0.12, 0.0, 0.0, 0.0])
		else:
			var length := minf(r.randf_range(1.0, 3.2), height * 0.35)
			var br := r.randf_range(0.7, 1.3)
			ps.append_array([SPIKE, p.x, floor_here - 1.0, p.z, p.x, floor_here + length, p.z, br, 0.15, 0.0, 0.0, 0.0])

static func _aabb(ps: PackedFloat32Array, o: int) -> AABB:
	var k := int(ps[o])
	var a := Vector3(ps[o + 1], ps[o + 2], ps[o + 3])
	var b := Vector3(ps[o + 4], ps[o + 5], ps[o + 6])
	var pad := AMP + AIR_K
	if k == BLOB:
		var m := maxf(b.x, b.z) + pad
		return AABB(a - Vector3(m, b.y + pad, m), Vector3(m, b.y + pad, m) * 2.0)
	var rr := maxf(ps[o + 7], ps[o + 8]) + (pad if k == TUNNEL else 0.5)
	var mn := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3(rr, rr, rr)
	var mx := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3(rr, rr, rr)
	return AABB(mn, mx - mn)

# --- Distance field ------------------------------------------------------------------

static func _smin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25

## Signed distance of one primitive at world point p: negative in its air (TUNNEL, BLOB)
## or inside its rock (SPIKE). `nz` is the wall noise at p.
static func _prim(ps: PackedFloat32Array, o: int, p: Vector3, nz: float) -> float:
	var k := int(ps[o])
	var a := Vector3(ps[o + 1], ps[o + 2], ps[o + 3])
	var b := Vector3(ps[o + 4], ps[o + 5], ps[o + 6])
	if k == BLOB:
		var q := (p - a).rotated(Vector3.UP, -ps[o + 7])
		var e := Vector3(q.x / b.x, q.y / b.y, q.z / b.z)
		var d := (e.length() - 1.0) * minf(b.x, minf(b.y, b.z))
		return maxf(d + nz * AMP, ps[o + 9] + _floor_bump(p) - p.y)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var rr := lerpf(ps[o + 7], ps[o + 8], t)
	var d := p.distance_to(a + ab * t) - rr
	if k == SPIKE:
		return d + nz * 0.25
	return maxf(d + nz * AMP, lerpf(ps[o + 9], ps[o + 10], t) + _floor_bump(p) - p.y)

static func _floor_bump(p: Vector3) -> float:
	return _floor_noise.get_noise_2d(p.x, p.z) * 0.3

## Cave distance at world point p (negative in the air), from a chunk's primitives.
static func sdf(ps: PackedFloat32Array, p: Vector3) -> float:
	_ensure_noise()
	var nz := _noise.get_noise_3dv(p)
	var d := BIG
	var count := ps.size() / STRIDE
	for i in count:
		var o := i * STRIDE
		if int(ps[o]) == SPIKE:
			continue
		if not _aabb(ps, o).has_point(p):
			continue
		d = _smin(d, _prim(ps, o, p, nz), AIR_K)
	for i in count:
		var o := i * STRIDE
		if int(ps[o]) != SPIKE or not _aabb(ps, o).has_point(p):
			continue
		d = maxf(d, -_prim(ps, o, p, nz))
	return d

# --- Chunk data (generation) -------------------------------------------------------

## Terrain vertices of the chunk that open into a cave: 1 per vertex, or empty if none.
static func hole_mask(ps: PackedFloat32Array, x0: float, z0: float, heights: PackedFloat32Array) -> PackedByteArray:
	const RES := ChunkGenerator.RES
	var out := PackedByteArray()
	var boxes: Array = []
	for i in ps.size() / STRIDE:
		if int(ps[i * STRIDE]) != SPIKE:
			boxes.append(_aabb(ps, i * STRIDE))
	var any := false
	for j in RES:
		for i in RES:
			var p := Vector3(x0 + i, heights[j * RES + i], z0 + j)
			var near := false
			for bb in boxes:
				if (bb as AABB).has_point(p):
					near = true
					break
			if not near or sdf(ps, p) > -0.6:
				continue
			if out.is_empty():
				out.resize(RES * RES)
			out[j * RES + i] = 1
			any = true
	return out if any else PackedByteArray()

static func is_hole(chunk: Dictionary, i: int, j: int) -> bool:
	if not chunk.has("hole"):
		return false
	var hb: PackedByteArray = chunk["hole"]
	return hb[clampi(j, 0, ChunkGenerator.RES - 1) * ChunkGenerator.RES + clampi(i, 0, ChunkGenerator.RES - 1)] != 0

## Near a cave mouth (within `pad` metres of an open vertex).
static func near_hole(chunk: Dictionary, lx: float, lz: float, pad: float) -> bool:
	if not chunk.has("hole"):
		return false
	var ci := int(round(lx))
	var cj := int(round(lz))
	var m := int(ceil(pad))
	for j in range(cj - m, cj + m + 1):
		for i in range(ci - m, ci + m + 1):
			if i >= 0 and j >= 0 and i < ChunkGenerator.RES and j < ChunkGenerator.RES and is_hole(chunk, i, j):
				return true
	return false

## The cave floor under world point p (searching down from p), or NAN.
static func floor_below(ps: PackedFloat32Array, p: Vector3, reach: float) -> float:
	if sdf(ps, p) > 0.0:
		return NAN
	var y := p.y
	while y > p.y - reach:
		y -= 0.15
		if sdf(ps, Vector3(p.x, y, p.z)) >= 0.0:
			return y + 0.1
	return NAN

## Ore, glowing crystals and loot on the floors of the chambers centred in this chunk,
## and boulders and brush that half hide the mouth. Called by the generator.
static func place(gen: ChunkGenerator, chunk: Dictionary) -> void:
	var ps: PackedFloat32Array = chunk["cave"]
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var x0 := float(cx * ChunkGenerator.SIZE)
	var z0 := float(cz * ChunkGenerator.SIZE)
	var x1 := x0 + ChunkGenerator.SIZE
	var z1 := z0 + ChunkGenerator.SIZE
	var r := WHash.rng(gen.seed, cx, cz, 812)
	var m := BORDER + 40.0
	for sz in range(int(floor((z0 - m) / CELL)), int(floor((z1 + m) / CELL)) + 1):
		for sx in range(int(floor((x0 - m) / CELL)), int(floor((x1 + m) / CELL)) + 1):
			var net := network(gen, sx, sz)
			if net.is_empty():
				continue
			var mo: Vector3 = net["mouth"]
			if mo.x >= x0 and mo.x < x1 and mo.z >= z0 and mo.z < z1:
				_hide_mouth(gen, chunk, r, mo - Vector3(x0, 0, z0), net["dir"])
			for ch in net["chambers"]:
				var cc: Vector3 = ch["p"]
				if cc.x >= x0 and cc.x < x1 and cc.z >= z0 and cc.z < z1:
					_furnish(gen, chunk, ps, r, ch, x0, z0)

static func _put(chunk: Dictionary, t: String, era: int, p: Vector3, yaw: float, s: float, st: Dictionary, sp := 0, v := 0) -> void:
	var objs: Array = chunk["objects"]
	var o := {"i": objs.size(), "t": t, "e": era, "p": p, "r": yaw, "s": s, "st": st}
	if sp != 0:
		o["sp"] = sp
		o["v"] = v
	objs.append(o)

static func _furnish(gen: ChunkGenerator, chunk: Dictionary, ps: PackedFloat32Array, r: RandomNumberGenerator, ch: Dictionary, x0: float, z0: float) -> void:
	var cc: Vector3 = ch["p"]
	var rx: float = ch["rx"]
	var fl: float = ch["f"]
	var lc := Vector3(cc.x - x0, 0, cc.z - z0)
	var era := WorldField.dominant(ChunkGenerator.weights_at(chunk, lc.x, lc.z))
	var bp := Biome.params(gen.field.region_hash_at(cc.x, cc.z), era)
	var spots := func(lo: float, hi: float) -> Vector3:
		for t in 8:
			var a := r.randf() * TAU
			var q := Vector3(cc.x + cos(a) * rx * r.randf_range(lo, hi), fl + 1.6, cc.z + sin(a) * rx * r.randf_range(lo, hi))
			if q.x < x0 or q.z < z0 or q.x > x0 + ChunkGenerator.SIZE or q.z > z0 + ChunkGenerator.SIZE:
				continue
			var y := floor_below(ps, q, 4.0)
			if not is_nan(y):
				return Vector3(q.x - x0, y, q.z - z0)
		return Vector3(NAN, NAN, NAN)
	# Richer ore than on the surface, along the walls.
	for n in r.randi_range(2, 5) + (3 if ch["big"] else 0):
		var p: Vector3 = spots.call(0.45, 0.75)
		if not is_nan(p.y):
			_put(chunk, Eras.ORE_TYPES[era], era, p, r.randf() * TAU, r.randf_range(0.8, 1.3), {"left": r.randi_range(7, 12), "progress": 0.0}, bp["ore_species"], r.randi() % Flora.VARIANTS)
	for n in r.randi_range(1, 3) + (3 if ch["big"] else 0):
		var p: Vector3 = spots.call(0.3, 0.7)
		if not is_nan(p.y):
			# Only alien worlds glow; on human worlds the crystals just catch your torchlight.
			_put(chunk, "cave_glow" if Eras.theme == "alien" else "cave_crystal", era, p, r.randf() * TAU, r.randf_range(0.7, 1.3), {}, r.randi_range(1, 12), era)
	# Something lives down here: more of them, and tougher, in the great caverns.
	var dwellers := r.randi_range(0, 2) + (2 if ch["big"] else 0)
	var tier := 1 + (1 if ch["big"] else 0) + (1 if r.randf() < 0.2 else 0)
	var guards: Array = chunk.get("guards", [])
	for n in dwellers:
		var p: Vector3 = spots.call(0.0, 0.5)
		if not is_nan(p.y):
			guards.append({"id": "cave_%d_%d_%d" % [chunk["cx"], chunk["cz"], guards.size()], "tier": tier, "era": era, "lx": p.x, "lz": p.z, "ly": p.y})
	if not guards.is_empty():
		chunk["guards"] = guards
	if ch["loot"]:
		var p: Vector3 = spots.call(0.1, 0.4)
		if not is_nan(p.y):
			var o := {"chunk": Vector2i(chunk["cx"], chunk["cz"]), "era": era, "how": "found"}
			_put(chunk, Eras.CACHE_TYPES[era], era, p, r.randf() * TAU, 1.0, {"loot": ItemDB.roll_loot(era, r, o, 0.6 if ch["big"] else 0.35), "opened": false})

## Boulders either side of the mouth and one just downhill, so it reads as a cleft
## among rocks rather than a hole you can spot from afar.
static func _hide_mouth(gen: ChunkGenerator, chunk: Dictionary, r: RandomNumberGenerator, lm: Vector3, up: Vector2) -> void:
	var era := WorldField.dominant(ChunkGenerator.weights_at(chunk, lm.x, lm.z))
	var bp := Biome.params(gen.field.region_hash_at(lm.x + chunk["cx"] * ChunkGenerator.SIZE, lm.z + chunk["cz"] * ChunkGenerator.SIZE), era)
	var rocks: Array = bp["rocks"]
	var side := Vector2(-up.y, up.x)
	var at := [side * 4.2 - up * 0.5, -side * 4.4 - up * 0.3, -up * 5.5 + side * r.randf_range(-1.5, 1.5), side * 3.0 + up * 3.5, -side * 3.2 + up * 3.0]
	for k in at.size():
		var q: Vector2 = Vector2(lm.x, lm.z) + at[k]
		if q.x < 1.0 or q.y < 1.0 or q.x > ChunkGenerator.SIZE - 1.0 or q.y > ChunkGenerator.SIZE - 1.0 or near_hole(chunk, q.x, q.y, 1.0):
			continue
		var sc := r.randf_range(1.3, 2.1) if k < 3 else r.randf_range(0.9, 1.4)
		_put(chunk, "rock", era, Vector3(q.x, ChunkGenerator.height_at(chunk, q.x, q.y), q.y), r.randf() * TAU, sc, {"left": r.randi_range(3, 7), "progress": 0.0}, rocks[r.randi() % rocks.size()], r.randi() % Flora.VARIANTS)

# --- Meshing (worker threads) ------------------------------------------------------

## Mesh arrays and collision faces for the chunk's cave walls (chunk-local), cached.
## {} when the chunk has no cave.
static func build(chunk: Dictionary) -> Dictionary:
	if not chunk.has("cave"):
		return {}
	var key := [int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], hash(chunk["cave"]), hash(chunk["heights"])]
	_lock.lock()
	var have = _mesh_cache.get(key)
	_lock.unlock()
	if have != null:
		return have
	var res := _mesh(chunk)
	_lock.lock()
	if _mesh_cache.size() > 24:
		_mesh_cache.clear()
	_mesh_cache[key] = res
	_lock.unlock()
	return res

static func _mesh(chunk: Dictionary) -> Dictionary:
	_ensure_noise()
	var ps: PackedFloat32Array = chunk["cave"]
	var hs: PackedFloat32Array = chunk["heights"]
	var x0 := float(int(chunk["cx"]) * ChunkGenerator.SIZE)
	var z0 := float(int(chunk["cz"]) * ChunkGenerator.SIZE)
	var top := -INF
	for h in hs:
		top = maxf(top, h)
	var ylo := INF
	var yhi := -INF
	var count := ps.size() / STRIDE
	for i in count:
		var bb := _aabb(ps, i * STRIDE)
		ylo = minf(ylo, bb.position.y)
		yhi = maxf(yhi, bb.end.y)
	yhi = minf(yhi, top + LIP + 2.0)
	if yhi <= ylo:
		return {}
	# Grid points -1..N+1 across, y0..y0+NY up.
	var y0 := floorf(ylo / VOX) * VOX - VOX
	var ny := int(ceil((yhi - y0) / VOX)) + 2
	var nx := N + 3
	var g := PackedFloat32Array()
	g.resize(nx * nx * ny)
	g.fill(BIG)
	var nz := PackedFloat32Array()
	nz.resize(nx * nx * ny)
	nz.fill(NAN)
	for pass_ in 2:
		for i in count:
			var o := i * STRIDE
			var spike := int(ps[o]) == SPIKE
			if spike != (pass_ == 1):
				continue
			var bb := _aabb(ps, o)
			var ia := clampi(int(floor((bb.position.x - x0) / VOX)) + 1, 0, nx - 1)
			var ib := clampi(int(ceil((bb.end.x - x0) / VOX)) + 1, 0, nx - 1)
			var ka := clampi(int(floor((bb.position.z - z0) / VOX)) + 1, 0, nx - 1)
			var kb := clampi(int(ceil((bb.end.z - z0) / VOX)) + 1, 0, nx - 1)
			var ja := clampi(int(floor((bb.position.y - y0) / VOX)), 0, ny - 1)
			var jb := clampi(int(ceil((bb.end.y - y0) / VOX)), 0, ny - 1)
			for k in range(ka, kb + 1):
				for j in range(ja, jb + 1):
					for ii in range(ia, ib + 1):
						var gi := (k * ny + j) * nx + ii
						var p := Vector3(x0 + (ii - 1) * VOX, y0 + j * VOX, z0 + (k - 1) * VOX)
						var n := nz[gi]
						if is_nan(n):
							n = _noise.get_noise_3dv(p)
							nz[gi] = n
						var d := _prim(ps, o, p, n)
						g[gi] = maxf(g[gi], -d) if spike else _smin(g[gi], d, AIR_K)
	return _surface_nets(g, nx, ny, y0, hs)

## Surface nets over the grid: one vertex per cell the surface passes through, one quad
## per crossed grid edge owned by this chunk (base point inside [0, N) across).
static func _surface_nets(g: PackedFloat32Array, nx: int, ny: int, y0: float, hs: PackedFloat32Array) -> Dictionary:
	var ncell := nx - 1
	var cell_v := PackedInt32Array()
	cell_v.resize(ncell * ncell * (ny - 1))
	cell_v.fill(-1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var grads: Array[Vector3] = []
	const CORNERS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var val := PackedFloat32Array()
	val.resize(8)
	for k in ncell:
		for j in ny - 1:
			for i in ncell:
				var neg := 0
				for c in 8:
					var cv: Vector3i = CORNERS[c]
					var v := g[((k + cv.z) * ny + j + cv.y) * nx + i + cv.x]
					val[c] = v
					if v < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var acc := Vector3.ZERO
				var cnt := 0
				for e in EDGES:
					var va := val[e[0]]
					var vb := val[e[1]]
					if (va < 0.0) == (vb < 0.0):
						continue
					var t := va / (va - vb)
					acc += Vector3(CORNERS[e[0]]).lerp(Vector3(CORNERS[e[1]]), t)
					cnt += 1
				var lp := acc / cnt
				var gx := (val[1] + val[3] + val[5] + val[7]) - (val[0] + val[2] + val[4] + val[6])
				var gy := (val[2] + val[3] + val[6] + val[7]) - (val[0] + val[1] + val[4] + val[5])
				var gz := (val[4] + val[5] + val[6] + val[7]) - (val[0] + val[1] + val[2] + val[3])
				cell_v[(k * (ny - 1) + j) * ncell + i] = verts.size()
				verts.append(Vector3((i - 1) * VOX, y0 + j * VOX, (k - 1) * VOX) + lp * VOX)
				var gr := Vector3(gx, gy, gz).normalized()
				norms.append(-gr) # toward the air
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for v in verts.size():
		cols[v] = Color(1, 1, 1)
	# Each axis: for an edge from grid point (i,j,k) along it, the four cells around it.
	for axis in 3:
		for k in range(1, nx - 1):
			for j in range(1, ny - 1):
				for i in range(1, nx - 1):
					if axis != 0 and (i < 1 or i > N):
						continue
					if axis != 2 and (k < 1 or k > N):
						continue
					if axis == 0 and i > N:
						continue
					if axis == 2 and k > N:
						continue
					if axis == 1 and j >= ny - 1:
						continue
					var a := g[(k * ny + j) * nx + i]
					var bi := i + (1 if axis == 0 else 0)
					var bj := j + (1 if axis == 1 else 0)
					var bk := k + (1 if axis == 2 else 0)
					if bi >= nx or bj >= ny or bk >= nx:
						continue
					var b := g[(bk * ny + bj) * nx + bi]
					if (a < 0.0) == (b < 0.0):
						continue
					# Only edges whose base point is inside this chunk: index 1..N.
					if i - 1 >= N or k - 1 >= N:
						continue
					var cs: Array = []
					match axis:
						0:
							cs = [[i, j - 1, k - 1], [i, j, k - 1], [i, j, k], [i, j - 1, k]]
						1:
							cs = [[i - 1, j, k - 1], [i, j, k - 1], [i, j, k], [i - 1, j, k]]
						_:
							cs = [[i - 1, j - 1, k], [i, j - 1, k], [i, j, k], [i - 1, j, k]]
					var q := PackedInt32Array()
					var ok := true
					for c in cs:
						if c[0] < 0 or c[1] < 0 or c[2] < 0 or c[0] >= ncell or c[1] >= ny - 1 or c[2] >= ncell:
							ok = false
							break
						var vi := cell_v[(c[2] * (ny - 1) + c[1]) * ncell + c[0]]
						if vi < 0:
							ok = false
							break
						q.append(vi)
					if not ok:
						continue
					var cen := (verts[q[0]] + verts[q[1]] + verts[q[2]] + verts[q[3]]) * 0.25
					if cen.y > _ground(hs, cen.x, cen.z) + LIP:
						continue
					# Front faces must face the air: their winding normal points into rock.
					var rock := Vector3(1 if axis == 0 else 0, 1 if axis == 1 else 0, 1 if axis == 2 else 0) * (1.0 if b >= 0.0 else -1.0)
					var tri := [q[0], q[1], q[2], q[0], q[2], q[3]]
					var cr := (verts[q[1]] - verts[q[0]]).cross(verts[q[2]] - verts[q[0]])
					if cr.dot(rock) < 0.0:
						tri = [q[0], q[2], q[1], q[0], q[3], q[2]]
					for t in tri:
						idx.append(t)
						faces.append(verts[t])
	if idx.is_empty():
		return {}
	# Hollows and crevices are darker: occlusion from how open the space is around a vertex.
	for v in verts.size():
		var p := verts[v]
		var nn := norms[v]
		var gi := _grid_at(g, nx, ny, y0, p + nn * 1.6)
		cols[v] = Color(1, 1, 1) * clampf(0.35 + (-gi) / 2.2, 0.35, 1.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arr, "faces": faces}

static func _grid_at(g: PackedFloat32Array, nx: int, ny: int, y0: float, p: Vector3) -> float:
	var i := clampi(int(round(p.x / VOX)) + 1, 0, nx - 1)
	var k := clampi(int(round(p.z / VOX)) + 1, 0, nx - 1)
	var j := clampi(int(round((p.y - y0) / VOX)), 0, ny - 1)
	return minf(g[(k * ny + j) * nx + i], 2.0)

static func _ground(hs: PackedFloat32Array, lx: float, lz: float) -> float:
	const RES := ChunkGenerator.RES
	lx = clampf(lx, 0.0, ChunkGenerator.SIZE - 0.001)
	lz = clampf(lz, 0.0, ChunkGenerator.SIZE - 0.001)
	var i := int(lx)
	var j := int(lz)
	var fx := lx - i
	var fz := lz - j
	return lerpf(lerpf(hs[j * RES + i], hs[j * RES + i + 1], fx), lerpf(hs[(j + 1) * RES + i], hs[(j + 1) * RES + i + 1], fx), fz)

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://src/world/shaders/cave.gdshader")
		_material.set_shader_parameter("rock_tex", Materials.photo("rock", "albedo"))
		_material.set_shader_parameter("floor_tex", Materials.photo("mud", "albedo"))
	return _material

# --- Glowing crystals ----------------------------------------------------------------

const GLOW := [Color(0.45, 0.75, 1.0), Color(0.55, 1.0, 0.75), Color(0.9, 0.45, 1.0)]

## A cluster of pale crystals, tinted by era (`v`): lit from within when `glow` (alien
## worlds), otherwise clear stone that only glints.
static func build_glow(sp: int, era: int, glow := true) -> ArrayMesh:
	var r := WHash.rng(sp, era, 0, 5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in r.randi_range(4, 8):
		var base := Vector3(r.randf_range(-0.5, 0.5), -0.1, r.randf_range(-0.5, 0.5))
		var tilt := Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(0.0, 0.55))
		var h := r.randf_range(0.5, 1.6) * (1.6 if n == 0 else 1.0)
		var w := r.randf_range(0.08, 0.2) * (1.4 if n == 0 else 1.0)
		var ring: Array = []
		for s in 6:
			ring.append(tilt * Vector3(cos(s * TAU / 6.0) * w, 0, sin(s * TAU / 6.0) * w))
		var tip := tilt * Vector3(0, h, 0)
		var mid := tilt * Vector3(0, h * 0.78, 0)
		for s in 6:
			var a: Vector3 = ring[s]
			var b: Vector3 = ring[(s + 1) % 6]
			for tri in [[base + a, base + mid + b, base + b], [base + a, base + mid + a, base + mid + b], [base + mid + a, base + tip, base + mid + b]]:
				var nn: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				for v in tri:
					st.set_normal(nn)
					st.add_vertex(v)
	var m := StandardMaterial3D.new()
	var c: Color = GLOW[clampi(era, 0, 2)]
	if glow:
		m.albedo_color = c.lerp(Color(1, 1, 1), 0.3)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.2
	else:
		m.albedo_color = c.lerp(Color(0.8, 0.82, 0.85), 0.6).darkened(0.25)
		m.metallic = 0.3
	m.roughness = 0.15
	m.metallic_specular = 0.8
	var out := st.commit()
	out.surface_set_material(0, m)
	return out

## Lights for a cave object's body (chunk-local offsets): [[pos, colour, energy, range]].
static func lights(o: Dictionary) -> Array:
	if o["t"] != "cave_glow":
		return []
	return [[Vector3(0, 1.0, 0), GLOW[clampi(int(o.get("v", 0)), 0, 2)], 1.4, 9.0]]
