class_name TownLife
extends Node3D
## What makes a medieval village look lived in: dirt paths worn from each door to the
## square and between neighbours, a fenced vegetable garden behind a house, woodpiles
## against the walls, washing lines, benches and barrels by the doors, haystacks and carts
## by the longhouses, fields of wheat and vegetables and an orchard outside town, smoke
## from the chimneys and lanterns and torches that burn after dark.
##
## All of it follows from the world seed and the town's layout, and nothing is saved, so
## towns in existing worlds get it too. The plan (static, cached, safe on worker threads)
## is shared by the chunk builders, which wear the ground bare under paths, gardens and
## fields (annotate) and grow the crops in rows among the grass (crops); this node builds
## the props, smoke and lights while you are near.

const HOUSE_T := ["cottage", "townhouse", "longhouse"]
## Rough reach of the other things in a town, for keeping yards and paths clear of them.
const ROUND := {"watchtower": 3.6, "well": 1.9, "market_stall": 2.0, "fruit_cart": 2.0, "wagon": 2.4,
	"barrels": 1.5, "signpost": 0.7, "trader": 2.4, "chest": 0.8}
## Crop kinds: [grass species list, row spacing, spacing along the row, ground wear].
## crop: [species, row gap, plant gap, soil wear, rows per strip, furrow between strips]
const CROPS := {
	"wheat": [["wheat"], 0.42, 0.34, 0.7, 6, 1.6],
	"veg": [["cabbage", "leek"], 0.75, 0.42, 0.72],
	"fallow": [[], 1.0, 1.0, 0.82],
	"garden": [["cabbage", "leek", "cabbage"], 0.6, 0.38, 0.85],
}
const PROP_RANGE := 170.0
const LIT_FROM := 18.4 ## lamps are lit from dusk...
const LIT_TO := 6.2 ## ...until dawn

static var _plans: Dictionary = {}
static var _lock := Mutex.new()

## Whether a settlement gets village life (medieval villages and towns).
static func applies(gen: ChunkGenerator, s: Dictionary) -> bool:
	return gen.towns and int(s["era"]) == Eras.MEDIEVAL

## The town's plan, in world coordinates: {houses, paths, soil, fields, orchards, pieces,
## lamps}. Pure function of the seed and the site; cached.
static func plan(gen: ChunkGenerator, s: Dictionary) -> Dictionary:
	var key := "%d:%d:%d" % [gen.seed, int(s["sx"]), int(s["sz"])]
	_lock.lock()
	var have = _plans.get(key)
	_lock.unlock()
	if have != null:
		return have
	var p := _make(gen, s)
	_lock.lock()
	if _plans.size() > 48:
		_plans.clear()
	_plans[key] = p
	_lock.unlock()
	return p

# --- Geometry helpers ------------------------------------------------------------------

## Local (x, z) in a frame at p turned by yaw (Basis(UP, yaw): local +z points along
## (sin yaw, cos yaw)) to world.
static func frame_to_world(p: Vector2, yaw: float, l: Vector2) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return p + Vector2(l.x * c + l.y * s, -l.x * s + l.y * c)

static func world_to_frame(p: Vector2, yaw: float, w: Vector2) -> Vector2:
	var d := w - p
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(d.x * c - d.y * s, d.x * s + d.y * c)

static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _line_d(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in range(1, pts.size()):
		best = minf(best, _seg_d(p, pts[i - 1], pts[i]))
	return best

## Whether a disc of radius rad at p is clear of the town's buildings (but `own`), the
## roads, the square, the wall and everything placed so far.
static func _free(ctx: Dictionary, p: Vector2, rad: float, own := -1, inside := true) -> bool:
	var c: Vector2 = ctx["c"]
	var d := p.distance_to(c)
	if d < float(ctx["square"]) + rad:
		return false
	if inside and bool(ctx["walled"]) and d + rad > float(ctx["inner"]) + 0.3:
		return false
	for pts: PackedVector2Array in ctx["roads"]:
		if _line_d(p, pts) < ChunkGenerator.ROAD_HALF + rad + 0.5:
			return false
	for o: Array in ctx["obs"]:
		if int(o[0]) == own:
			continue
		var q := world_to_frame(o[1], float(o[2]), p)
		var he: Vector2 = o[3]
		if he.y < 0.0:
			if q.length() < he.x + rad:
				return false
		elif absf(q.x) < he.x + rad and absf(q.y) < he.y + rad:
			return false
	for t: Array in ctx["taken"]:
		if p.distance_to(t[0]) < rad + float(t[1]):
			return false
	return true

## Every point of a list clear (see _free).
static func _all_free(ctx: Dictionary, pts: Array, rad: float, own := -1, inside := true) -> bool:
	for p in pts:
		if not _free(ctx, p, rad, own, inside):
			return false
	return true

static func _take(ctx: Dictionary, pts: Array, rad: float) -> void:
	for p in pts:
		ctx["taken"].append([p, rad])

## Points over a rectangle (centre p, yaw, half sizes) for testing it: corners, edges and
## the middle.
static func _rect_pts(p: Vector2, yaw: float, hx: float, hz: float, n := 2) -> Array:
	var out: Array = []
	for i in n + 1:
		for j in n + 1:
			out.append(frame_to_world(p, yaw, Vector2(lerpf(-hx, hx, float(i) / n), lerpf(-hz, hz, float(j) / n))))
	return out

# --- The plan ----------------------------------------------------------------------------

static func _make(gen: ChunkGenerator, s: Dictionary) -> Dictionary:
	var out := {"houses": [], "paths": [], "soil": [], "fields": [], "orchards": [], "pieces": [], "lamps": [], "smoke": []}
	if not applies(gen, s):
		return out
	var c: Vector2 = s["center"]
	var size := int(s["size"])
	var inner := float(s["inner"])
	var outer := float(s["outer"])
	var r := WHash.rng(gen.seed, s["sx"], s["sz"], 471)
	var layout := gen.settlement_layout(s)
	var obs: Array = [] ## [owner, centre, yaw, half extents (x < 0: a disc of radius x)]
	var houses: Array = []
	for i in layout.size():
		var it: Dictionary = layout[i]
		var t: String = it["t"]
		var p: Vector2 = it["p"]
		var yaw := float(it["yaw"])
		if KitHouse.PLANS.has(t):
			var dm := KitHouse._dims(t)
			obs.append([i, p, yaw, Vector2(dm.x * 0.5 + 0.45, dm.z * 0.5 + 0.45)])
			# Keep the way to the door open.
			obs.append([-2, frame_to_world(p, yaw, Vector2(0, dm.z * 0.5 + 1.3)), yaw, Vector2(0.8, 1.0)])
			houses.append({"t": t, "p": p, "yaw": yaw, "w": dm.x, "d": dm.z, "storeys": int(KitHouse.PLANS[t][2]), "i": i})
		elif Stronghold.has(t):
			obs.append([i, p, yaw, Vector2(5.0, -1.0)])
		else:
			obs.append([i, p, yaw, Vector2(float(ROUND.get(t, 2.5)), -1.0)])
	var roads: Array = []
	var reach := outer + 60.0
	for rd in gen.roads_near(c.x - reach, c.y - reach, c.x + reach, c.y + reach):
		roads.append(ChunkGenerator.road_pts(rd))
	var ctx := {"c": c, "obs": obs, "roads": roads, "square": 6.5 + size * 2.0, "inner": inner,
		"walled": bool(s.get("walled", false)), "taken": []}
	out["houses"] = houses
	_paths(ctx, houses, r, out)
	for h in houses:
		_yard(ctx, h, r, out)
	_lamps(ctx, layout, r, out)
	_farms(gen, ctx, s, r, out)
	return out

## Paths worn from each door toward the square (stopping where they meet a road), and
## between some neighbours' doors.
static func _paths(ctx: Dictionary, houses: Array, r: RandomNumberGenerator, out: Dictionary) -> void:
	var c: Vector2 = ctx["c"]
	for h in houses:
		var door := frame_to_world(h["p"], h["yaw"], Vector2(0, float(h["d"]) * 0.5 + 0.35))
		h["door"] = door
		var hw := r.randf_range(0.5, 0.7)
		var cur := door
		var dir: Vector2 = (frame_to_world(h["p"], h["yaw"], Vector2(0, 10)) - (h["p"] as Vector2)).normalized()
		var wob := r.randf_range(-0.6, 0.6)
		for step in 40:
			var to_c := (c - cur).normalized()
			dir = dir.lerp(to_c, 0.35).normalized().rotated(sin(step * 0.7 + wob * 5.0) * 0.12 * wob)
			var nxt: Vector2 = cur + dir * 1.6
			var dc: float = nxt.distance_to(c)
			var blocked := false
			for o: Array in ctx["obs"]:
				if int(o[0]) == int(h["i"]) or int(o[0]) == -2:
					continue
				var q := world_to_frame(o[1], float(o[2]), nxt)
				var he: Vector2 = o[3]
				if (he.y < 0.0 and q.length() < he.x) or (he.y >= 0.0 and absf(q.x) < he.x and absf(q.y) < he.y):
					blocked = true
			if blocked:
				break
			out["paths"].append([cur, nxt, hw, 0.8 if step == 0 else 0.68])
			cur = nxt
			if dc < float(ctx["square"]) - 1.0:
				break
			var on_road := false
			for pts: PackedVector2Array in ctx["roads"]:
				if _line_d(cur, pts) < ChunkGenerator.ROAD_HALF:
					on_road = true
			if on_road:
				break
		# The trodden patch outside the door.
		out["soil"].append({"p": door, "yaw": float(h["yaw"]), "hx": 1.3, "hz": 0.9, "wear": 0.62})
		var dpts: Array = []
		for k in 4:
			dpts.append(door.lerp(cur, k / 3.0))
		_take(ctx, dpts, hw + 0.3)
	# Neighbours: doors at about the same distance from the square, a short walk apart.
	var order := houses.duplicate()
	order.sort_custom(func(a, b): return (a["p"] - c).angle() < (b["p"] - c).angle())
	for k in order.size():
		var a: Dictionary = order[k]
		var b: Dictionary = order[(k + 1) % order.size()]
		if a == b:
			continue
		var da: Vector2 = a["door"]
		var db: Vector2 = b["door"]
		if da.distance_to(db) > 15.0 or absf(da.distance_to(c) - db.distance_to(c)) > 4.0 or r.randf() < 0.4:
			continue
		var mid := (da + db) * 0.5 + (da + db - c * 2.0).normalized() * -0.8
		var ok := true
		for p in [da.lerp(mid, 0.5), mid, mid.lerp(db, 0.5)]:
			for o: Array in ctx["obs"]:
				if int(o[0]) < 0:
					continue
				var q := world_to_frame(o[1], float(o[2]), p)
				var he: Vector2 = o[3]
				if (he.y < 0.0 and q.length() < he.x) or (he.y >= 0.0 and absf(q.x) < he.x and absf(q.y) < he.y):
					ok = false
		if ok:
			out["paths"].append([da, mid, 0.45, 0.55])
			out["paths"].append([mid, db, 0.45, 0.55])
			_take(ctx, [da.lerp(mid, 0.5), mid, mid.lerp(db, 0.5)], 0.7)

## A house's yard: what stands round it, each piece only where it fits.
static func _yard(ctx: Dictionary, h: Dictionary, r: RandomNumberGenerator, out: Dictionary) -> void:
	var p: Vector2 = h["p"]
	var yaw: float = h["yaw"]
	var w: float = h["w"]
	var d: float = h["d"]
	var own: int = h["i"]
	var t: String = h["t"]
	var side := 1.0 if r.randf() < 0.5 else -1.0
	var add := func(kind: String, l: Vector2, ly: float, extra: Dictionary) -> void:
		var e := {"k": kind, "p": frame_to_world(p, yaw, l), "yaw": yaw + ly, "house": own}
		e.merge(extra)
		out["pieces"].append(e)
	var add_fence := func(a: Vector2, b: Vector2) -> void:
		out["pieces"].append({"k": "fence", "a": frame_to_world(p, yaw, a), "b": frame_to_world(p, yaw, b), "house": own, "wattle": true})
	# Smoke from the chimney when the hearth is lit (most homes).
	if r.randf() < 0.8:
		var top := float(h["storeys"]) * 3.0 + 0.9 + (3.18 if int(h["storeys"]) > 1 else 3.0)
		out["smoke"].append({"house": own, "l": Vector3(w * 0.5 - 1.6, top + 0.15, -d * 0.5 + 1.4), "p": p, "yaw": yaw})
	# A woodpile against a side wall, with the chopping block.
	if r.randf() < 0.85:
		var len := r.randf_range(1.6, 2.4)
		var z0 := r.randf_range(-d * 0.5 + len * 0.5 + 0.3, d * 0.5 - len * 0.5 - 0.8)
		var lc := Vector2(side * (w * 0.5 + 0.62), z0)
		var pts := [frame_to_world(p, yaw, lc + Vector2(0, -len * 0.4)), frame_to_world(p, yaw, lc), frame_to_world(p, yaw, lc + Vector2(0, len * 0.4))]
		var block := lc + Vector2(side * 1.1, r.randf_range(-0.6, 0.6))
		if _all_free(ctx, pts, 0.35, own) and _free(ctx, frame_to_world(p, yaw, block), 0.4, own):
			add.call("woodpile", lc, PI * 0.5 * side, {"len": len, "roof": r.randf() < 0.45, "seed": r.randi()})
			add.call("chopping", block, r.randf() * TAU, {"seed": r.randi()})
			_take(ctx, pts + [frame_to_world(p, yaw, block)], 0.45)
	# A fenced vegetable garden behind.
	if r.randf() < (0.5 if t == "townhouse" else 0.8):
		var gw := r.randf_range(1.7, 2.8)
		var gd := r.randf_range(1.3, 2.1)
		var lc := Vector2(r.randf_range(-w * 0.2, w * 0.2), -(d * 0.5 + 0.9 + gd))
		var gp := frame_to_world(p, yaw, lc)
		var pts := _rect_pts(gp, yaw, gw + 0.2, gd + 0.2)
		if _all_free(ctx, pts, 0.2, own):
			add.call("garden", lc, 0.0, {"hx": gw, "hz": gd, "seed": r.randi()})
			out["soil"].append({"p": gp, "yaw": yaw, "hx": gw - 0.25, "hz": gd - 0.25, "wear": 0.85, "crop": "garden",
				"rows": 0 if r.randf() < 0.5 else 1, "seed": r.randi()})
			_take(ctx, pts, 0.4)
	# A washing line along the other side.
	if r.randf() < 0.5:
		var len := minf(d - 0.8, r.randf_range(3.2, 4.6))
		var lc := Vector2(-side * (w * 0.5 + r.randf_range(1.6, 2.2)), r.randf_range(-0.4, 0.2))
		var pts := [frame_to_world(p, yaw, lc + Vector2(0, -len * 0.5)), frame_to_world(p, yaw, lc), frame_to_world(p, yaw, lc + Vector2(0, len * 0.5))]
		if _all_free(ctx, pts, 0.45, own):
			add.call("washing", lc, 0.0, {"len": len, "seed": r.randi()})
			_take(ctx, pts, 0.5)
	# By the door: a bench on one side, barrels and a bucket on the other.
	var bs := 1.0 if r.randf() < 0.5 else -1.0
	if r.randf() < 0.55:
		var lc := Vector2(bs * 1.75, d * 0.5 + 0.42)
		if _free(ctx, frame_to_world(p, yaw, lc), 0.5, own):
			add.call("bench", lc, 0.0, {"front": true})
			_take(ctx, [frame_to_world(p, yaw, lc)], 0.6)
	if r.randf() < 0.55:
		var lc := Vector2(-bs * 1.7, d * 0.5 + 0.5)
		if _free(ctx, frame_to_world(p, yaw, lc), 0.55, own):
			add.call("barrels", lc, r.randf_range(-0.4, 0.4), {"front": true, "seed": r.randi()})
			_take(ctx, [frame_to_world(p, yaw, lc)], 0.6)
	# A lantern on the wall by the door.
	if r.randf() < 0.65:
		add.call("lantern", Vector2(-bs * 0.98, d * 0.5 + 0.1), 0.0, {"front": true, "y": 2.0})
	# A course of rough footing stones where the walls meet the ground, a doorstep slab,
	# and the ground before the door trodden bare.
	var door_x := 0.0
	if KitHouse.PLANS.has(t):
		door_x = -w * 0.5 + 1.0 + 2.0 * int(int(KitHouse.PLANS[t][0]) / 2)
	add.call("plinth", Vector2.ZERO, 0.0, {"w": w, "d": d, "door": door_x, "seed": r.randi()})
	out["soil"].append({"p": frame_to_world(p, yaw, Vector2(door_x + r.randf_range(-0.2, 0.2), d * 0.5 + 1.3)), "yaw": yaw + r.randf_range(-0.15, 0.15),
		"hx": 1.1 + r.randf_range(0.0, 0.5), "hz": 1.25, "wear": 0.95})
	# A wattle fence round the back yard, open at the front; each side only where it fits,
	# with a gap in the back for a gate.
	if t != "townhouse" and r.randf() < 0.6:
		var fx := w * 0.5 + 3.2
		var fb := -(d * 0.5 + 5.6)
		var ff := d * 0.5 - 0.6
		var gx := r.randf_range(-fx * 0.5, fx * 0.5)
		for seg: Array in [[Vector2(-fx, ff), Vector2(-fx, fb)], [Vector2(-fx, fb), Vector2(gx - 0.7, fb)],
				[Vector2(gx + 0.7, fb), Vector2(fx, fb)], [Vector2(fx, fb), Vector2(fx, ff)]]:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var n := maxi(2, int(a.distance_to(b) / 1.2))
			var pts: Array = []
			for k in n + 1:
				pts.append(frame_to_world(p, yaw, a.lerp(b, float(k) / n)))
			if _all_free(ctx, pts, 0.3, own):
				add_fence.call(a, b)
				_take(ctx, pts, 0.35)
	# Longhouses farm: a haystack and a cart beside them.
	if t == "longhouse":
		var lc := Vector2(side * (w * 0.5 + 2.4), r.randf_range(-d * 0.3, d * 0.2))
		if _free(ctx, frame_to_world(p, yaw, lc), 1.5, own):
			add.call("haystack", lc, r.randf() * TAU, {"seed": r.randi()})
			_take(ctx, [frame_to_world(p, yaw, lc)], 1.6)
		var cc := Vector2(-side * (w * 0.5 + 2.2), r.randf_range(-d * 0.2, d * 0.3))
		var cpts := [frame_to_world(p, yaw, cc + Vector2(0, -1.7)), frame_to_world(p, yaw, cc), frame_to_world(p, yaw, cc + Vector2(0, 1.7))]
		if r.randf() < 0.7 and _all_free(ctx, cpts, 1.1, own):
			add.call("cart", cc, r.randf_range(-0.3, 0.3), {"hay": r.randf() < 0.6, "seed": r.randi()})
			_take(ctx, cpts, 1.2)

## Torches on posts round the square and at the town's gates (signposts).
static func _lamps(ctx: Dictionary, layout: Array, r: RandomNumberGenerator, out: Dictionary) -> void:
	var c: Vector2 = ctx["c"]
	var sq := float(ctx["square"])
	var n := 4 + r.randi_range(0, 2)
	var a0 := r.randf() * TAU
	var keep: float = ctx["square"]
	ctx["square"] = 0.0
	for k in n:
		var a := a0 + TAU * k / n
		var p := c + Vector2.from_angle(a) * (sq + 0.6)
		if _free(ctx, p, 0.4, -1, true):
			out["lamps"].append({"k": "post", "p": p, "yaw": atan2(c.x - p.x, c.y - p.y)})
			_take(ctx, [p], 0.5)
	for it in layout:
		if it["t"] == "signpost":
			var p: Vector2 = it["p"]
			var to_c := (c - p).normalized()
			var lp := p + to_c.orthogonal() * 1.3
			if _free(ctx, lp, 0.3, -1, true):
				out["lamps"].append({"k": "post", "p": lp, "yaw": atan2(to_c.x, to_c.y)})
				_take(ctx, [lp], 0.4)
	ctx["square"] = keep

## Fields and orchards outside town, clear of the roads and the neighbours.
static func _farms(gen: ChunkGenerator, ctx: Dictionary, s: Dictionary, r: RandomNumberGenerator, out: Dictionary) -> void:
	var c: Vector2 = s["center"]
	var size := int(s["size"])
	var inner := float(s["inner"])
	var outer := float(s["outer"])
	var r0 := inner + (7.0 if bool(s.get("walled", false)) else 5.0)
	var r1 := outer + 30.0
	var sites := gen.settlements_near(c.x - r1 - 40, c.y - r1 - 40, c.x + r1 + 40, c.y + r1 + 40)
	var forts := gen.forts_near(c.x - r1, c.y - r1, c.x + r1, c.y + r1)
	var placed: Array = [] ## [centre, radius]
	var want_fields := 3 + size * 3 + r.randi_range(0, 2)
	var want_orchards := 0 if size == 0 and r.randf() < 0.5 else 1 + (1 if size == 2 else 0)
	var crops := ["wheat", "wheat", "wheat", "wheat", "veg", "veg", "fallow"]
	# Candidate plots all round, scored by how level they lie; the levellest are farmed
	# first (orchards take the steeper ones too, as on a real hillside).
	var cands: Array = []
	for attempt in 140:
		var hx := r.randf_range(5.0, 11.0)
		var hz := r.randf_range(4.0, 9.0)
		var ang := r.randf() * TAU
		var dist := r.randf_range(r0 + hz, r1 - hz)
		var p := c + Vector2.from_angle(ang) * dist
		var outward := Vector2.from_angle(ang)
		var yaw := atan2(outward.x, outward.y) + r.randf_range(-0.3, 0.3)
		var rad := Vector2(hx, hz).length()
		var ok := true
		for o in sites:
			if o["sx"] != s["sx"] or o["sz"] != s["sz"]:
				if p.distance_to(o["center"]) < float(o["outer"]) + rad + 4.0:
					ok = false
		for f in forts:
			if p.distance_to(f["center"]) < Stronghold.OUTER + rad + 4.0:
				ok = false
		var pts := _rect_pts(p, yaw, hx, hz, 3)
		if ok:
			for q in pts:
				for pl: PackedVector2Array in ctx["roads"]:
					if _line_d(q, pl) < ChunkGenerator.ROAD_HALF + 2.0:
						ok = false
				if q.distance_to(c) < r0:
					ok = false
		if not ok:
			continue
		var lo := INF
		var hi := -INF
		for q in pts:
			var hh := gen.sample_height(q.x, q.y, PackedFloat32Array(), sites)
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
		if lo < ChunkGenerator.WATER_LEVEL + 0.8:
			continue
		cands.append({"p": p, "yaw": yaw, "hx": hx, "hz": hz, "rad": rad, "score": (hi - lo) / (rad * 2.0), "n": attempt})
	cands.sort_custom(func(x, y): return float(x["score"]) < float(y["score"]) or (float(x["score"]) == float(y["score"]) and int(x["n"]) < int(y["n"])))
	# Hill towns farm the steeper slopes too, rather than going without.
	var steep := 0.28
	if cands.filter(func(x): return float(x["score"]) < steep).size() < want_fields * 2:
		steep = 0.48
	for cd in cands:
		var orchard: bool = (out["orchards"] as Array).size() < want_orchards and float(cd["rad"]) > 9.0 and float(cd["score"]) < steep + 0.12
		if not orchard and ((out["fields"] as Array).size() >= want_fields or float(cd["score"]) > steep):
			continue
		var p: Vector2 = cd["p"]
		var yaw: float = cd["yaw"]
		var hx: float = cd["hx"]
		var hz: float = cd["hz"]
		var rad: float = cd["rad"]
		var ok := true
		for q in placed:
			if p.distance_to(q[0]) < rad + float(q[1]) * 0.85 + 1.5:
				ok = false
		if not ok:
			continue
		placed.append([p, rad])
		if orchard:
			var trees: Array = []
			var sp := _orchard_species(r.randi())
			var nx := int(hx * 2.0 / 5.5)
			var nz := int(hz * 2.0 / 5.5)
			for i in nx + 1:
				for j in nz + 1:
					var l := Vector2(lerpf(-hx + 1.5, hx - 1.5, float(i) / maxf(nx, 1)), lerpf(-hz + 1.5, hz - 1.5, float(j) / maxf(nz, 1)))
					l += Vector2(r.randf_range(-0.5, 0.5), r.randf_range(-0.5, 0.5))
					if r.randf() < 0.08:
						continue # a gap where one died
					trees.append({"p": frame_to_world(p, yaw, l), "v": r.randi() % Flora.VARIANTS, "s": r.randf_range(0.85, 1.12), "yaw": r.randf() * TAU})
			out["orchards"].append({"p": p, "yaw": yaw, "hx": hx, "hz": hz, "sp": sp, "trees": trees})
			continue
		var crop: String = crops[r.randi() % crops.size()]
		var ripe := r.randf()
		var tint := Color(0.42, 0.52, 0.2).lerp(Color(0.8, 0.64, 0.32), ripe) if crop == "wheat" else Color(0.36, 0.5, 0.3)
		var f := {"p": p, "yaw": yaw, "hx": hx, "hz": hz, "crop": crop, "rows": r.randi() % 2, "tint": tint,
			"wear": float(CROPS[crop][3]), "seed": r.randi()}
		out["fields"].append(f)
		out["soil"].append(f)
		# A cart track from the field's near edge back toward town, ending at a road or
		# outside the wall.
		var gate_x := r.randf_range(-hx, hx) * 0.5
		var cur := frame_to_world(p, yaw, Vector2(gate_x, -hz - 0.6))
		var stop := inner + (5.5 if bool(s.get("walled", false)) else -2.0)
		for step in 40:
			var on_road := false
			for pl: PackedVector2Array in ctx["roads"]:
				if _line_d(cur, pl) < ChunkGenerator.ROAD_HALF:
					on_road = true
			if on_road or cur.distance_to(c) < stop:
				break
			var nxt := cur + (c - cur).normalized().rotated(sin(step * 0.5 + yaw) * 0.15) * 2.0
			out["paths"].append([cur, nxt, 1.05, 0.85])
			cur = nxt
		# A fence right round the field, with a gate where the cart track leaves it (now
		# and then a field is left open); a haystack or two by a ripe field, a scarecrow
		# among the crops, now and then a cart at the edge.
		if r.randf() < 0.8:
			var ex := hx + 0.5
			var ez := hz + 0.5
			var corners := [Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(ex, ez), Vector2(-ex, ez)]
			for si in 4:
				var a: Vector2 = corners[si]
				var b: Vector2 = corners[(si + 1) % 4]
				if si == 0: # the near side, toward town: the gate
					out["pieces"].append({"k": "fence", "a": frame_to_world(p, yaw, a), "b": frame_to_world(p, yaw, Vector2(gate_x - 1.3, -ez)), "house": -1})
					out["pieces"].append({"k": "fence", "a": frame_to_world(p, yaw, Vector2(gate_x + 1.3, -ez)), "b": frame_to_world(p, yaw, b), "house": -1})
				else:
					out["pieces"].append({"k": "fence", "a": frame_to_world(p, yaw, a), "b": frame_to_world(p, yaw, b), "house": -1})
		if crop == "wheat" and ripe > 0.6:
			for n in r.randi_range(1, 2):
				var l := Vector2(r.randf_range(-hx, hx), hz + 2.2)
				out["pieces"].append({"k": "haystack", "p": frame_to_world(p, yaw, l), "yaw": r.randf() * TAU, "house": -1, "seed": r.randi()})
		if crop != "fallow" and r.randf() < 0.45:
			out["pieces"].append({"k": "scarecrow", "p": frame_to_world(p, yaw, Vector2(r.randf_range(-hx, hx) * 0.6, r.randf_range(-hz, hz) * 0.5)),
				"yaw": yaw + r.randf_range(-0.6, 0.6), "house": -1, "seed": r.randi()})
		if r.randf() < 0.25:
			out["pieces"].append({"k": "cart", "p": frame_to_world(p, yaw, Vector2(hx + 2.4, r.randf_range(-hz, hz) * 0.5)),
				"yaw": yaw + r.randf_range(-0.3, 0.3), "house": -1, "hay": crop == "wheat", "seed": r.randi()})

## A small, round-crowned broadleaf for fruit trees (scaled down where it stands).
static func _orchard_species(start: int) -> int:
	var sp := (start & 0xFFFFF) | 1
	for i in 64:
		var p := Flora.species("oak", sp)
		var hsv := (p["leaf"] as Color).h
		if String(p["form"]) in ["round", "oval", "spreading"] and hsv > 0.16 and hsv < 0.33:
			return sp
		sp += 7
	return sp

# --- Worker-thread side: worn ground and crops ------------------------------------------

## Marks the chunk's ground worn under paths, gardens and fields ("worn", RES*RES bytes)
## and lists the crop beds over it ("crops", in chunk coordinates). Both follow from the
## seed and are recomputed on every load (never relied on from a save).
static func annotate(gen: ChunkGenerator, chunk: Dictionary) -> void:
	chunk.erase("worn")
	chunk.erase("crops")
	if not gen.towns:
		return
	const S := ChunkGenerator.SIZE
	const RES := ChunkGenerator.RES
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	var area := Rect2(x0 - 2.0, z0 - 2.0, S + 4.0, S + 4.0)
	var worn := PackedByteArray()
	var crops: Array = []
	for s in gen.settlements_near(x0 - 45.0, z0 - 45.0, x0 + S + 45.0, z0 + S + 45.0):
		if not applies(gen, s):
			continue
		var pl := plan(gen, s)
		for e: Array in pl["paths"]:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var hw: float = e[2]
			var bb := Rect2(a, Vector2.ZERO).expand(b).grow(hw + 1.0)
			if not bb.intersects(area):
				continue
			if worn.is_empty():
				worn.resize(RES * RES)
			_wear(worn, bb, x0, z0, func(q: Vector2) -> float:
				# Ragged edges: trodden wider here, grassed over there.
				var rag := 0.45 * sin(q.x * 1.37 + q.y * 0.61) * sin(q.y * 1.13 - q.x * 0.47) + 0.2 * sin(q.x * 3.1 - q.y * 2.7)
				return float(e[3]) * (1.0 - smoothstep(hw * 0.35, hw + 1.1, _seg_d(q, a, b) + rag)))
		for f: Dictionary in pl["soil"]:
			var p: Vector2 = f["p"]
			var hx: float = f["hx"]
			var hz: float = f["hz"]
			var bb := Rect2(p, Vector2.ZERO).grow(Vector2(hx, hz).length() + 1.0)
			if not bb.intersects(area):
				continue
			if worn.is_empty():
				worn.resize(RES * RES)
			var yaw: float = f["yaw"]
			var wv: float = f["wear"]
			_wear(worn, bb, x0, z0, func(q: Vector2) -> float:
				var l := world_to_frame(p, yaw, q)
				var ex := minf(hx - absf(l.x), hz - absf(l.y))
				return wv * smoothstep(-0.6, 0.6, ex))
			if f.has("crop") and not (CROPS[f["crop"]][0] as Array).is_empty():
				crops.append({"p": p - Vector2(x0, z0), "yaw": yaw, "hx": hx, "hz": hz, "crop": f["crop"], "rows": int(f.get("rows", 0)),
					"tint": f.get("tint", Color(0.36, 0.5, 0.3)), "seed": int(f.get("seed", 0))})
		_clear_fields(chunk, pl, x0, z0)
	if not worn.is_empty():
		chunk["worn"] = worn
	if not crops.is_empty():
		chunk["crops"] = crops

## Wild trees and boulders standing in a field or orchard (or on its fence line) were
## cleared when it was broken: they are marked gone, as if felled long ago.
static func _clear_fields(chunk: Dictionary, pl: Dictionary, x0: float, z0: float) -> void:
	var areas: Array = []
	for f: Dictionary in pl["fields"]:
		areas.append([f["p"], f["yaw"], float(f["hx"]) + 1.6, float(f["hz"]) + 1.6])
	for f: Dictionary in pl["orchards"]:
		areas.append([f["p"], f["yaw"], float(f["hx"]) + 1.2, float(f["hz"]) + 1.2])
	if areas.is_empty():
		return
	for o in chunk["objects"]:
		var k := ObjectLibrary.kind(o["t"])
		if (k != "tree" and k != "rock") or o["st"].get("gone", false):
			continue
		var q := Vector2(x0 + o["p"].x, z0 + o["p"].z)
		for ar: Array in areas:
			var l := world_to_frame(ar[0], ar[1], q)
			if absf(l.x) < float(ar[2]) and absf(l.y) < float(ar[3]):
				o["st"]["gone"] = true
				break

static func _wear(worn: PackedByteArray, bb: Rect2, x0: float, z0: float, f: Callable) -> void:
	const RES := ChunkGenerator.RES
	for j in range(maxi(0, int(floor(bb.position.y - z0))), mini(RES - 1, int(ceil(bb.end.y - z0))) + 1):
		for i in range(maxi(0, int(floor(bb.position.x - x0))), mini(RES - 1, int(ceil(bb.end.x - x0))) + 1):
			var v := clampf(float(f.call(Vector2(x0 + i, z0 + j))), 0.0, 1.0)
			var k := j * RES + i
			worn[k] = maxi(worn[k], int(v * 255.0))

## How worn the ground is at a point of the chunk (0..1).
static func wear_at(chunk: Dictionary, lx: float, lz: float) -> float:
	if not chunk.has("worn"):
		return 0.0
	const RES := ChunkGenerator.RES
	var wb: PackedByteArray = chunk["worn"]
	return wb[clampi(int(round(lz)), 0, RES - 1) * RES + clampi(int(round(lx)), 0, RES - 1)] / 255.0

## Crop plants in rows over the chunk's beds, as grass instances into `out` (keys
## "<species>@<quarter>", the grass buffer layout).
static func crops(chunk: Dictionary, out: Dictionary, density: float, plans: Array) -> void:
	if not chunk.has("crops"):
		return
	const S := float(ChunkGenerator.SIZE)
	# Things standing in the field: the crop gives way round them.
	var standing: Array = []
	for o in chunk["objects"]:
		if o["st"].get("gone", false):
			continue
		var k := ObjectLibrary.kind(o["t"])
		if k == "tree" or k == "rock" or k == "ore":
			standing.append(Vector2(o["p"].x, o["p"].z))
	var thin := 1.0 / sqrt(clampf(density, 0.35, 1.0))
	for bed: Dictionary in chunk["crops"]:
		var cp: Array = CROPS[bed["crop"]]
		var species: Array = cp[0]
		var row_gap: float = cp[1]
		var gap := float(cp[2]) * thin
		var p: Vector2 = bed["p"]
		var yaw: float = bed["yaw"]
		var hx: float = bed["hx"]
		var hz: float = bed["hz"]
		var rows_x := int(bed["rows"]) == 0
		var r := RandomNumberGenerator.new()
		r.seed = WHash.combine(int(bed["seed"]), int(chunk["cx"]) * 7919 + int(chunk["cz"]))
		var tint: Color = bed["tint"]
		var a_len := hx if rows_x else hz
		var b_len := hz if rows_x else hx
		# Rows sown in strips with a bare furrow between them (strip farming), each strip a
		# little riper or greener than the next, so a field reads as rows from the road.
		var strip := int(cp[4]) if cp.size() > 4 else 0
		var furrow: float = cp[5] if cp.size() > 5 else 0.0
		var offs: Array[float] = []
		var shade: Array[float] = []
		var bo0 := -b_len + 0.25
		var si := 0
		var tone := 1.0
		while bo0 <= b_len - 0.25:
			offs.append(bo0)
			shade.append(tone)
			bo0 += row_gap
			si += 1
			if strip > 0 and si % strip == 0:
				bo0 += furrow
				tone = r.randf_range(0.74, 1.16)
		var na := int(a_len * 2.0 / gap)
		for bi in offs.size():
			var bo: float = offs[bi]
			var sp: String = species[bi % species.size()]
			for ai in na + 1:
				var ao := -a_len + 0.2 + (a_len * 2.0 - 0.4) * ai / maxf(na, 1) + r.randf_range(-0.1, 0.1) * gap
				var l := Vector2(ao, bo + r.randf_range(-0.06, 0.06)) if rows_x else Vector2(bo + r.randf_range(-0.06, 0.06), ao)
				var q := frame_to_world(p, yaw, l)
				var roll := r.randf()
				var yr := r.randf() * TAU
				var sc := r.randf_range(0.85, 1.15)
				if q.x < 0.0 or q.y < 0.0 or q.x >= S or q.y >= S:
					continue
				if roll < 0.04:
					continue # gaps in the rows
				if ChunkGenerator.slope_at(chunk, q.x, q.y) > 0.6 or ChunkGenerator.road_at(chunk, q.x, q.y) > 0.05:
					continue
				var y := ChunkGenerator.height_at(chunk, q.x, q.y)
				if y < 0.3 or ChunkGenerator.by_river(chunk, q.x, q.y) or ChunkGenerator.kept_out(plans, q.x, q.y, 0.4):
					continue
				var clear := true
				for t: Vector2 in standing:
					if t.distance_squared_to(q) < 2.6:
						clear = false
						break
				if not clear:
					continue
				var b := Basis(Vector3.UP, yr).scaled(Vector3(sc, sc * r.randf_range(0.88, 1.12), sc))
				var tc := tint * (shade[bi] * r.randf_range(0.92, 1.06))
				var key := "%s@%d" % [sp, (1 if q.x >= S * 0.5 else 0) + (2 if q.y >= S * 0.5 else 0)]
				var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
				buf.append_array([b.x.x, b.y.x, b.z.x, q.x, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, q.y,
					tc.r, tc.g, tc.b, 0.0])
				out[key] = buf

# --- The node: props, smoke and lamps ---------------------------------------------------

var gen: ChunkGenerator
var streamer: Node ## ChunkStreamer (untyped: the tests load this script without the Game autoload)
var site: Dictionary
var _pending: Array = [] ## groups waiting for their ground: {pieces: [...], house: int}
var _flames: Array = [] ## lamp flames and lights, lit after dark
var _lit := -1
var _t := 0.0
var _hour_t := 0.0
var _shops: Dictionary = {} ## layout index of a shop's house -> true

static var _smoke_mat: StandardMaterial3D
static var _smoke_pm: ParticleProcessMaterial

func setup(g: ChunkGenerator, s: Node, st: Dictionary) -> void:
	gen = g
	streamer = s
	site = st
	name = "Life_" + NPCGen.settlement_id(st["sx"], st["sz"])
	if not applies(gen, site):
		set_process(false)
		return
	var pl := plan(gen, site)
	for h in TownShops.plan(gen, site):
		if h["kind"] != "":
			for hh in pl["houses"]:
				if (hh["p"] as Vector2).distance_to(h["p"]) < 0.6:
					_shops[int(hh["i"])] = true
	# One group per house (its yard, smoke and lantern), and the farm pieces by chunk.
	var by_house := {}
	var farm := {}
	for e in pl["pieces"]:
		var hi := int(e["house"])
		if hi >= 0:
			if e.get("front", false) and _shops.has(hi) and e["k"] != "lantern":
				continue # a shop's sign and door stay clear
			if not by_house.has(hi):
				by_house[hi] = []
			by_house[hi].append(e)
		else:
			var at: Vector2 = e["p"] if e.has("p") else e["a"]
			var k := _chunk_of(Vector3(at.x, 0, at.y))
			if not farm.has(k):
				farm[k] = []
			farm[k].append(e)
	for e in pl["smoke"]:
		var hi := int(e["house"])
		if not by_house.has(hi):
			by_house[hi] = []
		by_house[hi].append({"k": "smoke", "l": e["l"], "p": e["p"], "yaw": e["yaw"]})
	for hi in by_house:
		_pending.append({"pieces": by_house[hi], "house": hi})
	for k in farm:
		_pending.append({"pieces": farm[k], "house": -1})
	for o in pl["orchards"]:
		var by := {}
		for t in o["trees"]:
			var k := _chunk_of(Vector3(t["p"].x, 0, t["p"].y))
			if not by.has(k):
				by[k] = []
			by[k].append({"k": "tree", "p": t["p"], "yaw": t["yaw"], "sp": o["sp"], "v": t["v"], "s": t["s"]})
		for k in by:
			_pending.append({"pieces": by[k], "house": -1})
	for l in pl["lamps"]:
		_pending.append({"pieces": [{"k": "torch_post", "p": l["p"], "yaw": l["yaw"]}], "house": -1})

static func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))

## Ground height at a world point, or NAN while its chunk isn't loaded.
func _ground(x: float, z: float) -> float:
	var k := _chunk_of(Vector3(x, 0, z))
	var ch = streamer.get_chunk(k)
	if ch == null or ch.data.is_empty():
		return NAN
	return ChunkGenerator.height_at(ch.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE)

## The house's chunk object as {y, gone}, or {} while its chunk isn't loaded.
func _house(i: int) -> Dictionary:
	var h: Dictionary = plan(gen, site)["houses"].filter(func(x): return int(x["i"]) == i)[0]
	var p: Vector2 = h["p"]
	var k := _chunk_of(Vector3(p.x, 0, p.y))
	var c = streamer.get_chunk(k)
	if c == null or c.data.is_empty():
		return {}
	for o in c.data["objects"]:
		if o["t"] != h["t"]:
			continue
		var wp := Vector2(o["p"].x + k.x * ChunkGenerator.SIZE, o["p"].z + k.y * ChunkGenerator.SIZE)
		if wp.distance_to(p) < 0.6:
			return {"y": float(o["p"].y), "s": float(o["s"]), "gone": o["st"].get("gone", false)}
	return {"gone": true}

func _process(delta: float) -> void:
	_hour_t -= delta
	if _hour_t <= 0.0:
		_hour_t = 2.0
		var hr := NPCMind.hour_now()
		var lit := 1 if hr >= LIT_FROM or hr < LIT_TO else 0
		if lit != _lit:
			_lit = lit
			for f in _flames:
				if is_instance_valid(f):
					f.visible = lit == 1
	_t -= delta
	if _t > 0.0 or _pending.is_empty():
		return
	_t = 0.25
	# A group or two a tick, so arriving in town doesn't hitch.
	var built := 0
	for g in _pending.duplicate():
		if built >= 2:
			break
		var base := NAN
		if int(g["house"]) >= 0:
			var ho := _house(int(g["house"]))
			if ho.is_empty():
				continue
			if ho.get("gone", false):
				_pending.erase(g)
				continue
			base = float(ho["y"]) - Interiors.SINK * float(ho["s"])
		var ready := true
		for e in g["pieces"]:
			for q in _spots(e):
				if is_nan(_ground(q.x, q.y)):
					ready = false
		if not ready:
			continue
		_pending.erase(g)
		_build(g["pieces"], base)
		built += 1

## Where a piece touches the ground (all must be loaded before it is built).
func _spots(e: Dictionary) -> Array:
	match e["k"]:
		"fence":
			return [e["a"], e["b"]]
		"smoke", "lantern":
			return []
	return [e["p"]]

## Builds a group of pieces into one mesh (with its colliders, flames and smoke).
func _build(pieces: Array, base: float) -> void:
	var first: Dictionary = pieces[0]
	var o2: Vector2 = first["p"] if first.has("p") else first["a"]
	var oy := base if not is_nan(base) else _ground(o2.x, o2.y)
	var root := Node3D.new()
	root.position = Vector3(o2.x, oy, o2.y)
	add_child(root)
	var k := MeshKit.new(WHash.str_hash(str(o2)) & 0xFFFF)
	var models: Array = []
	var body := StaticBody3D.new()
	for e in pieces:
		var r := RandomNumberGenerator.new()
		r.seed = int(e.get("seed", WHash.str_hash(str(e.get("p", e.get("a", Vector2.ZERO))))))
		var p2: Vector2 = e["p"] if e.has("p") else e["a"]
		var gy := _ground(p2.x, p2.y) if e["k"] != "smoke" and e["k"] != "lantern" and e["k"] != "plinth" else oy
		# Yard pieces on the house's flattened ground sit no lower than its plinth top.
		var at := Vector3(p2.x - o2.x, gy - oy, p2.y - o2.y)
		var xf := Transform3D(Basis(Vector3.UP, float(e.get("yaw", 0.0))), at)
		match e["k"]:
			"woodpile": _woodpile(k, models, xf, float(e["len"]), bool(e["roof"]), r, body)
			"chopping": _chopping(k, models, xf, r, body)
			"garden": _garden(k, models, root, xf, float(e["hx"]), float(e["hz"]), r, body, o2, oy)
			"washing": _washing(k, xf, float(e["len"]), r)
			"bench": models.append(["props/Bench", rad_to_deg(float(e["yaw"])), at, 1.0])
			"barrels": _barrels(models, xf, r, body)
			"lantern": _lantern(models, root, e, o2, oy)
			"haystack": _haystack(k, xf, r, body)
			"cart": _cart(k, models, xf, bool(e.get("hay", false)), r, body)
			"fence":
				if e.get("wattle", false):
					_wattle(k, e["a"], e["b"], o2, oy, r, body)
				else:
					_fence(models, e["a"], e["b"], o2, oy, body)
			"scarecrow": _scarecrow(k, xf, r)
			"plinth": _plinth(k, xf, float(e["w"]), float(e["d"]), float(e["door"]), r, body)
			"tree": _tree(root, e, at)
			"torch_post": _torch_post(k, models, root, xf, body)
			"smoke": _smoke(root, e, o2, oy)
	var mesh := BuildCatalog.merge_models(models) if not models.is_empty() else ArrayMesh.new()
	k.commit(Materials.get_mat, mesh)
	if mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = PROP_RANGE
		mi.visibility_range_end_margin = 15.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	if body.get_child_count() > 0:
		root.add_child(body)
	else:
		body.free()

static func _box_shape(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)

# --- Pieces (in the group's space; xf places the piece, +z its front) -------------------

## Split logs stacked against a wall, ends outward, sometimes under a little roof.
static func _woodpile(k: MeshKit, models: Array, xf: Transform3D, len: float, roof: bool, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var I := Transform3D.IDENTITY
	var rows := r.randi_range(5, 8)
	var dia := 0.15
	var depth := 0.5
	# Two rails on the ground keep the bottom row off the wet.
	for sx in [-0.16, 0.16]:
		k.box("timber", xf * I.translated(Vector3(0, 0.04, sx)), Vector3(len, 0.08, 0.08))
	for row in rows:
		var n := int(len / dia) - (row % 2)
		var y := 0.08 + dia * 0.5 + row * dia * 0.86
		for i in n:
			var x := -len * 0.5 + dia * 0.5 + i * dia + (dia * 0.5 if row % 2 == 1 else 0.0) + r.randf_range(-0.012, 0.012)
			var d := dia * r.randf_range(0.8, 1.05)
			var out := r.randf_range(-0.04, 0.04)
			var lx := xf * I.translated(Vector3(x, y, out)) * Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5).rotated(Vector3.UP, r.randf_range(-0.05, 0.05)), Vector3.ZERO)
			# A split log: bark round the outside, pale cut faces at the ends.
			k.cylinder("bark", lx * I.translated(Vector3(0, -depth * 0.5, 0)), d * 0.5, d * 0.5, depth, 6, false)
			var pale := Color(1.25, 1.15, 0.95) * r.randf_range(0.85, 1.05)
			k.cylinder("planks", lx * I.translated(Vector3(0, depth * 0.5 - 0.002, 0)), d * 0.48, d * 0.48, 0.006, 6, true, 0.0, 1, pale)
			k.cylinder("planks", lx * I.translated(Vector3(0, -depth * 0.5 - 0.004, 0)), d * 0.48, d * 0.48, 0.006, 6, true, 0.0, 1, pale)
	var h := 0.08 + rows * dia * 0.86 + dia * 0.3
	if roof:
		for sx in [-1.0, 1.0]:
			k.box("timber", xf * I.translated(Vector3(sx * (len * 0.5 + 0.06), (h + 0.35) * 0.5, depth * 0.35)), Vector3(0.08, h + 0.35, 0.08))
		var slope := Transform3D(Basis(Vector3(1, 0, 0), -0.32), Vector3(0, h + 0.3, 0.05))
		k.box("planks", xf * slope, Vector3(len + 0.4, 0.04, depth + 0.5), Color(0.8, 0.75, 0.7))
	_box_shape(body, xf * I.translated(Vector3(0, h * 0.5, 0)), Vector3(len, h, depth))

## A chopping block: a stump of a log with an axe in it and chips about.
static func _chopping(k: MeshKit, models: Array, xf: Transform3D, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var I := Transform3D.IDENTITY
	var h := r.randf_range(0.42, 0.55)
	k.cylinder("bark", xf, 0.24, 0.27, h, 9, false, 0.02)
	k.cylinder("planks", xf * I.translated(Vector3(0, h - 0.004, 0)), 0.235, 0.235, 0.008, 9, true, 0.0, 1, Color(1.2, 1.1, 0.9))
	if r.randf() < 0.75:
		# The kit axe lies along x, blade at -x: stood up and bitten into the block.
		var ax := xf * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(r.randf_range(55, 75))).rotated(Vector3.UP, r.randf() * TAU), Vector3(0, h + 0.03, 0))
		models.append(["props/Axe_Bronze", 0.0, Vector3.ZERO, 1.0, {}, ax])
	for i in r.randi_range(3, 6):
		var a := r.randf() * TAU
		var d := r.randf_range(0.35, 0.8)
		k.box("planks", xf * Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(cos(a) * d, 0.012, sin(a) * d)),
			Vector3(r.randf_range(0.06, 0.14), 0.02, r.randf_range(0.03, 0.06)), Color(1.15, 1.05, 0.85))
	_box_shape(body, xf * I.translated(Vector3(0, h * 0.5, 0)), Vector3(0.5, h, 0.5))

## A fence round a vegetable bed with a gap for the gate (the -z side faces away from the
## house, the +z side touches its back). The crops themselves grow as grass (crops()).
func _garden(k: MeshKit, models: Array, root: Node3D, xf: Transform3D, hx: float, hz: float, r: RandomNumberGenerator, body: StaticBody3D, o2: Vector2, oy: float) -> void:
	var c := xf.origin
	var b := xf.basis
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var gate := r.randi() % 4
	for i in 4:
		var a: Vector3 = corners[i]
		var e: Vector3 = corners[(i + 1) % 4]
		var wa := c + b * a
		var we := c + b * e
		var pa := Vector2(wa.x + o2.x, wa.z + o2.y)
		var pe := Vector2(we.x + o2.x, we.z + o2.y)
		if i == gate:
			var mid := pa.lerp(pe, 0.5)
			var dir := (pe - pa).normalized()
			_fence(models, pa, mid - dir * 0.5, o2, oy, body)
			_fence(models, mid + dir * 0.5, pe, o2, oy, body)
		else:
			_fence(models, pa, pe, o2, oy, body)
	# A bucket, a basket and a hoe leant against the fence.
	var I := Transform3D.IDENTITY
	models.append(["props/Bucket_Wooden_1", r.randf_range(0, 360), c + b * Vector3(hx - 0.35, 0, hz - 0.3), 1.0])
	if r.randf() < 0.6:
		models.append(["props/FarmCrate_Carrot" if r.randf() < 0.5 else "props/FarmCrate_Empty", rad_to_deg(xf.basis.get_euler().y) + r.randf_range(-20, 20), c + b * Vector3(-hx + 0.5, 0, hz - 0.35), 1.0])
	var hoe := xf * Transform3D(Basis(Vector3(1, 0, 0), -0.28), Vector3(r.randf_range(-hx, hx) * 0.6, 0, -hz + 0.12))
	k.cylinder("timber", hoe, 0.017, 0.017, 1.45, 5)
	k.box("iron", hoe * I.translated(Vector3(0, 1.45, 0.06)), Vector3(0.16, 0.03, 0.12))

## A line strung between two posts with the washing pegged out.
static func _washing(k: MeshKit, xf: Transform3D, len: float, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var top := r.randf_range(1.75, 1.95)
	for sz in [-1.0, 1.0]:
		k.cylinder("timber", xf * I.translated(Vector3(0, 0, sz * len * 0.5)), 0.05, 0.045, top + 0.1, 6, true, 0.01)
		k.box("timber", xf * I.translated(Vector3(0, top - 0.02, sz * len * 0.5)), Vector3(0.5, 0.05, 0.05))
	var sag := r.randf_range(0.12, 0.2)
	for lane in [-0.2, 0.2]:
		var segs := 8
		for i in segs:
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var p0 := Vector3(lane, top - sag * 4.0 * t0 * (1.0 - t0), lerpf(-len * 0.5, len * 0.5, t0))
			var p1 := Vector3(lane, top - sag * 4.0 * t1 * (1.0 - t1), lerpf(-len * 0.5, len * 0.5, t1))
			var d := p1 - p0
			var seg := Transform3D(Basis.looking_at(d.normalized(), Vector3(1, 0, 0)) * Basis(Vector3(1, 0, 0), -PI * 0.5), p0)
			k.cylinder("linen", xf * seg, 0.006, 0.006, d.length(), 4, false, 0.0, 1, Color(0.75, 0.7, 0.6))
	# Sheets, shirts and smalls, in the plain dyes of homespun cloth.
	var dyes := [Color(0.95, 0.93, 0.86), Color(0.92, 0.9, 0.82), Color(0.62, 0.5, 0.36), Color(0.45, 0.52, 0.62),
		Color(0.7, 0.42, 0.3), Color(0.55, 0.58, 0.42), Color(0.85, 0.8, 0.66)]
	var z := -len * 0.5 + 0.3
	while z < len * 0.5 - 0.4:
		var lane := -0.2 if r.randf() < 0.5 else 0.2
		var wdt := r.randf_range(0.35, 0.95)
		var hgt := r.randf_range(0.4, 0.95) if wdt > 0.6 else r.randf_range(0.3, 0.6)
		var zc := z + wdt * 0.5
		var t := (zc + len * 0.5) / len
		var y := top - sag * 4.0 * t * (1.0 - t)
		var sway := r.randf_range(-0.12, 0.12)
		var cxf := xf * Transform3D(Basis(Vector3(0, 0, 1), sway), Vector3(lane, y - hgt * 0.5, zc))
		k.box("linen", cxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), Vector3(wdt, hgt, 0.008), dyes[r.randi() % dyes.size()])
		z += wdt + r.randf_range(0.08, 0.3)

static func _barrels(models: Array, xf: Transform3D, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var yd := rad_to_deg(xf.basis.get_euler().y)
	models.append(["props/Barrel", yd + r.randf_range(0, 90), xf * Vector3(-0.2, 0, 0), 1.0])
	if r.randf() < 0.6:
		models.append(["props/Barrel", yd + r.randf_range(0, 90), xf * Vector3(0.5, 0, -0.15), 0.9])
	models.append(["props/Bucket_Wooden_1", yd + r.randf_range(0, 360), xf * Vector3(0.25, 0, 0.45), 1.0])
	if r.randf() < 0.4:
		models.append(["props/Crate_Wooden", yd + r.randf_range(-15, 15), xf * Vector3(-0.85, 0, 0.05), 0.75])
	_box_shape(body, Transform3D(xf.basis, xf * Vector3(0.1, 0.45, 0)), Vector3(1.3, 0.9, 0.8))

## A wall lantern by the door; its flame is lit after dark.
func _lantern(models: Array, root: Node3D, e: Dictionary, o2: Vector2, oy: float) -> void:
	var p2: Vector2 = e["p"]
	var at := Vector3(p2.x - o2.x, float(e["y"]), p2.y - o2.y)
	models.append(["props/Lantern_Wall", rad_to_deg(float(e["yaw"])), at, 1.0])
	var b := Basis(Vector3.UP, float(e["yaw"]))
	_flame(root, at + b * Vector3(0, 0.26, 0.75), 0.13, 1.1, 6.5)

## A real flame with its firelight, both only lit after dark.
func _flame(root: Node3D, at: Vector3, size: float, energy: float, reach: float) -> void:
	var fl := FireFx.flame(size)
	fl.position = at
	root.add_child(fl)
	var l := FlickerLight.new()
	l.light_color = Color(1.0, 0.66, 0.34)
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.3
	l.position = at + Vector3(0, size * 0.5, 0)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 55.0
	l.distance_fade_length = 20.0
	root.add_child(l)
	var lit := _lit == 1
	fl.visible = lit
	l.visible = lit
	_flames.append(fl)
	_flames.append(l)

## A haystack: a squat dome of hay with a pointed cap, wisps round the foot.
static func _haystack(k: MeshKit, xf: Transform3D, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var I := Transform3D.IDENTITY
	var rad := r.randf_range(1.1, 1.5)
	var h := r.randf_range(1.8, 2.5)
	var tone := Color(1, 1, 1) * r.randf_range(0.85, 1.05)
	var waist := h * 0.42
	k.cylinder("thatch", xf * I.translated(Vector3(0, -0.15, 0)), rad * 0.96, rad, waist + 0.17, 16, false, 0.05, 2, tone)
	k.sphere("thatch", xf * I.translated(Vector3(0, waist, 0)), rad, 10, 16, 0.06, (h - waist) / rad, tone, true)
	k.cylinder("timber", xf * I.translated(Vector3(0, h - 0.15, 0)), 0.035, 0.02, 0.5, 5)
	# Loose hay pulled out round the foot.
	for i in 12:
		var a := r.randf() * TAU
		var d := rad + r.randf_range(-0.1, 0.45)
		k.sphere("thatch", xf * Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(cos(a) * d, 0.0, sin(a) * d)),
			r.randf_range(0.18, 0.35), 4, 7, 0.2, 0.35, tone * 0.92, true)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = rad
	cy.height = h
	cs.shape = cy
	cs.transform = xf * I.translated(Vector3(0, h * 0.5, 0))
	body.add_child(cs)

## The kit wagon, sometimes loaded with hay.
static func _cart(k: MeshKit, models: Array, xf: Transform3D, hay: bool, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var I := Transform3D.IDENTITY
	# The kit wagon's middle is 1.15 m behind its origin.
	models.append(["village/Prop_Wagon", rad_to_deg(xf.basis.get_euler().y), xf * Vector3(0, 0, 1.15), 1.0])
	if hay:
		var tone := Color(1, 1, 1) * r.randf_range(0.85, 1.05)
		k.sphere("thatch", xf * I.translated(Vector3(0, 0.9, 0)), 0.85, 6, 12, 0.08, 0.55, tone)
		k.box("thatch", xf * I.translated(Vector3(0, 0.95, 0)), Vector3(1.5, 0.35, 2.6), tone)
	_box_shape(body, xf * I.translated(Vector3(0, 0.75, 0)), Vector3(1.9, 1.5, 4.0))

## A run of the kit's fence panels from a to b (world), each following the ground.
func _fence(models: Array, a: Vector2, b: Vector2, o2: Vector2, oy: float, body: StaticBody3D) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var n := maxi(1, int(round(len / 2.06)))
	var dir := (b - a) / len
	var yaw := atan2(dir.y, dir.x) # the panel runs along its x
	for i in n:
		var p0 := a + dir * (len * i / n)
		var p1 := a + dir * (len * (i + 1) / n)
		var y0 := _ground(p0.x, p0.y)
		var y1 := _ground(p1.x, p1.y)
		if is_nan(y0) or is_nan(y1):
			continue
		var mid := (p0 + p1) * 0.5
		var seg := len / n
		var tilt := atan2(y1 - y0, seg)
		var basis := Basis(Vector3.UP, -yaw) * Basis(Vector3(0, 0, 1), tilt) * Basis.from_scale(Vector3(seg / 2.06, 1, 1))
		var xf := Transform3D(basis, Vector3(mid.x - o2.x, (y0 + y1) * 0.5 - oy - 0.04, mid.y - o2.y))
		models.append(["village/Prop_WoodenFence_Single", 0.0, Vector3.ZERO, 1.0, {}, xf])
		_box_shape(body, xf * Transform3D.IDENTITY.translated(Vector3(0, 0.45, 0)), Vector3(2.0, 0.9, 0.12))

## A wattle fence: stakes about a metre apart with hazel rods woven between them, each
## panel following the ground and leaning a little on its own.
func _wattle(k: MeshKit, a: Vector2, b: Vector2, o2: Vector2, oy: float, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var n := maxi(1, int(round(len / 1.05)))
	var dir := (b - a) / len
	var yaw := atan2(dir.y, dir.x)
	var h := r.randf_range(0.85, 1.05)
	var rod := Color(0.56, 0.47, 0.36) * r.randf_range(0.85, 1.08)
	for i in n + 1:
		var q := a + dir * (len * i / n)
		var y := _ground(q.x, q.y)
		if is_nan(y):
			continue
		var lean := Basis(Vector3(dir.x, 0, dir.y).cross(Vector3.UP).normalized(), r.randf_range(-0.06, 0.06))
		k.cylinder("bark_w", Transform3D(lean, Vector3(q.x - o2.x, y - oy - 0.1, q.y - o2.y)), 0.035, 0.03, h + 0.18, 5, true, 0.1, 1, rod * 0.8)
		if i == n:
			break
		var q1 := a + dir * (len * (i + 1) / n)
		var y1 := _ground(q1.x, q1.y)
		if is_nan(y1):
			continue
		var seg := len / n
		var tilt := atan2(y1 - y, seg)
		var mid := (q + q1) * 0.5
		var pb := Basis(Vector3.UP, -yaw) * Basis(Vector3(0, 0, 1), tilt) * lean
		var px := Transform3D(pb, Vector3(mid.x - o2.x, (y + y1) * 0.5 - oy, mid.y - o2.y))
		# Rods over and under the stakes in turn: alternate rows sit to either side.
		var rows := int((h - 0.06) / 0.068)
		for j in rows:
			var off := 0.03 * (1.0 if (i + j) % 2 == 0 else -1.0)
			var bend := Basis(Vector3.UP, r.randf_range(-0.03, 0.03))
			k.box("bark_w", px * Transform3D(bend, Vector3(0, 0.08 + j * (h - 0.08) / rows, off)),
				Vector3(seg + 0.06, 0.062, 0.04), rod * r.randf_range(0.78, 1.12))
		_box_shape(body, px * Transform3D.IDENTITY.translated(Vector3(0, h * 0.5, 0)), Vector3(seg, h, 0.1))

## A house's footing: rough stones in a course round the foot of the walls (in the
## house's own frame, its origin), open at the doorway, with a worn slab for a doorstep.
static func _plinth(k: MeshKit, xf: Transform3D, w: float, d: float, door_x: float, r: RandomNumberGenerator, body: StaticBody3D) -> void:
	var face := KitHouse.WALL_OUT + 0.06
	var top := r.randf_range(0.5, 0.62) # above the house's origin (0.15 under the ground)
	var base_tone := Color(0.78, 0.74, 0.68) * r.randf_range(0.85, 1.05)
	# Each side runs corner to corner round the outside of the walls.
	var sides := [[Vector3(-w * 0.5 - face, 0, d * 0.5 + face), Vector3(w * 0.5 + face, 0, d * 0.5 + face)],
		[Vector3(w * 0.5 + face, 0, d * 0.5 + face), Vector3(w * 0.5 + face, 0, -d * 0.5 - face)],
		[Vector3(w * 0.5 + face, 0, -d * 0.5 - face), Vector3(-w * 0.5 - face, 0, -d * 0.5 - face)],
		[Vector3(-w * 0.5 - face, 0, -d * 0.5 - face), Vector3(-w * 0.5 - face, 0, d * 0.5 + face)]]
	for si in 4:
		var a: Vector3 = sides[si][0]
		var b: Vector3 = sides[si][1]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var yaw := atan2(-dir.z, dir.x)
		var u := 0.0
		while u < len - 0.05:
			var sl := minf(r.randf_range(0.45, 0.95), len - u)
			var mid := a + dir * (u + sl * 0.5)
			var front := si == 0 and absf(mid.x - door_x) < 0.68 + sl * 0.5
			if not front:
				var h := top + r.randf_range(-0.06, 0.05)
				var dep := r.randf_range(0.22, 0.3)
				var bs := Basis(Vector3.UP, yaw + r.randf_range(-0.04, 0.04))
				# (bs.z points out of the house on every side: they run round it clockwise.)
				k.box("stone", xf * Transform3D(bs, mid + Vector3(0, (h - 0.45) * 0.5, 0) + bs.z * (dep * 0.5 - 0.12)),
					Vector3(sl - 0.03, h + 0.45, dep), base_tone * r.randf_range(0.82, 1.12))
			u += sl
	# The doorstep: a slab before the doorway, its top just under the floor.
	var step := xf * Transform3D(Basis(Vector3.UP, r.randf_range(-0.04, 0.04)), Vector3(door_x, 0.06, d * 0.5 + face + 0.32))
	k.box("stone", step, Vector3(1.5, 0.24, 0.62), base_tone * 0.92)
	_box_shape(body, step, Vector3(1.5, 0.24, 0.62))

## A scarecrow: a post and crossbar in an old shirt, a sack head and a straw hat.
static func _scarecrow(k: MeshKit, xf: Transform3D, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var lean := xf * Transform3D(Basis(Vector3(0, 0, 1), r.randf_range(-0.08, 0.08)), Vector3.ZERO)
	k.cylinder("timber", lean, 0.04, 0.035, 2.0, 6)
	k.box("timber", lean * I.translated(Vector3(0, 1.45, 0)), Vector3(1.3, 0.05, 0.05))
	var shirt: Color = [Color(0.55, 0.45, 0.32), Color(0.42, 0.45, 0.55), Color(0.6, 0.38, 0.3)][r.randi() % 3]
	k.box("linen", lean * I.translated(Vector3(0, 1.22, 0)), Vector3(0.48, 0.6, 0.2), shirt)
	k.box("linen", lean * I.translated(Vector3(0, 1.43, 0)), Vector3(1.15, 0.16, 0.16), shirt)
	k.box("linen", lean * Transform3D(Basis(Vector3(0, 0, 1), 0.1), Vector3(0.12, 0.75, 0)), Vector3(0.2, 0.45, 0.14), shirt * 0.8)
	k.sphere("linen", lean * I.translated(Vector3(0, 1.72, 0)), 0.15, 6, 8, 0.02, 1.1, Color(0.72, 0.62, 0.44))
	k.cylinder("thatch", lean * I.translated(Vector3(0, 1.82, 0)), 0.3, 0.29, 0.03, 12)
	k.cylinder("thatch", lean * I.translated(Vector3(0, 1.84, 0)), 0.14, 0.11, 0.14, 10)
	for sx in [-1.0, 1.0]:
		k.box("thatch", lean * Transform3D(Basis(Vector3(0, 0, 1), sx * 0.5), Vector3(sx * 0.62, 1.4, 0)), Vector3(0.14, 0.05, 0.08))

## A fruit tree of the orchard (a small broadleaf, scaled to its height).
func _tree(root: Node3D, e: Dictionary, at: Vector3) -> void:
	var key := "oak#%d#%d" % [int(e["sp"]), int(e["v"])]
	var p := Flora.species("oak", int(e["sp"]))
	var sc := clampf(4.6 / float(p["height"]), 0.35, 0.85) * float(e["s"])
	var mi := MeshInstance3D.new()
	mi.mesh = ObjectLibrary.get_mesh(key)
	mi.transform = Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3.ONE * sc), at - Vector3(0, 0.05, 0))
	mi.visibility_range_end = 260.0
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = maxf(0.12, float(p["girth"]) * sc * 0.8)
	cy.height = 2.4
	cs.shape = cy
	cs.position = at + Vector3(0, 1.2, 0)
	body.add_child(cs)
	root.add_child(body)

## A torch in an iron cup on a post, lit after dark.
func _torch_post(k: MeshKit, models: Array, root: Node3D, xf: Transform3D, body: StaticBody3D) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("timber", xf, 0.08, 0.065, 2.35, 8, true, 0.01)
	k.box("iron", xf * I.translated(Vector3(0, 2.0, 0.07)), Vector3(0.1, 0.04, 0.12))
	var torch := xf * I.translated(Vector3(0, 1.85, 0.02))
	models.append(["props/Torch_Metal", rad_to_deg(xf.basis.get_euler().y), torch.origin, 1.0])
	_flame(root, torch * Vector3(0, 0.34, 0.27), 0.42, 1.8, 10.0)
	var fl: Node3D = _flames[_flames.size() - 2]
	fl.add_child(FireFx.embers(0.42, false))
	_box_shape(body, xf * I.translated(Vector3(0, 1.1, 0)), Vector3(0.18, 2.2, 0.18))

## Chimney smoke: soft puffs that rise, spread and drift off on the wind.
func _smoke(root: Node3D, e: Dictionary, o2: Vector2, oy: float) -> void:
	var p2: Vector2 = e["p"]
	var l: Vector3 = e["l"]
	var b := Basis(Vector3.UP, float(e["yaw"]))
	var at := Vector3(p2.x - o2.x, 0, p2.y - o2.y) + b * l
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.particles_anim_h_frames = 4
		_smoke_mat.particles_anim_v_frames = 4
		_smoke_mat.particles_anim_loop = false
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_texture = load("res://assets/textures/fx/smoke_flipbook.png")
		_smoke_mat.roughness = 1.0
		# Smoke scatters light through itself, so the side away from the sun stays pale
		# rather than going sooty.
		_smoke_mat.backlight_enabled = true
		_smoke_mat.backlight = Color(0.55, 0.56, 0.6)
		_smoke_mat.disable_receive_shadows = true
		_smoke_pm = ParticleProcessMaterial.new()
		_smoke_pm.direction = Vector3(0, 1, 0)
		_smoke_pm.spread = 8.0
		_smoke_pm.initial_velocity_min = 0.5
		_smoke_pm.initial_velocity_max = 0.9
		# Up and away downwind, slowing as it cools.
		_smoke_pm.gravity = Vector3(0.32, 0.12, 0.14)
		_smoke_pm.damping_min = 0.05
		_smoke_pm.damping_max = 0.12
		_smoke_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_smoke_pm.emission_sphere_radius = 0.12
		_smoke_pm.angle_min = -180.0
		_smoke_pm.angle_max = 180.0
		_smoke_pm.angular_velocity_min = -8.0
		_smoke_pm.angular_velocity_max = 8.0
		_smoke_pm.scale_min = 0.7
		_smoke_pm.scale_max = 1.1
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.3))
		sc.add_point(Vector2(0.5, 1.0))
		sc.add_point(Vector2(1, 1.0))
		var st := CurveTexture.new()
		st.curve = sc
		_smoke_pm.scale_curve = st
		var g := Gradient.new()
		# Wood smoke: pale grey-blue from the chimney, thinning to near white.
		g.set_color(0, Color(0.76, 0.78, 0.82, 0.0))
		g.add_point(0.1, Color(0.76, 0.78, 0.82, 0.62))
		g.add_point(0.55, Color(0.84, 0.85, 0.88, 0.36))
		g.set_color(g.get_point_count() - 1, Color(0.9, 0.9, 0.92, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		_smoke_pm.color_ramp = gt
		_smoke_pm.anim_speed_min = 0.0
		_smoke_pm.anim_speed_max = 0.0
		_smoke_pm.anim_offset_min = 0.2
		_smoke_pm.anim_offset_max = 0.45
	var ps := GPUParticles3D.new()
	ps.amount = 26
	ps.lifetime = 12.0
	ps.preprocess = 12.0
	ps.randomness = 0.4
	ps.local_coords = false
	ps.process_material = _smoke_pm
	var q := QuadMesh.new()
	q.size = Vector2(3.6, 3.6) # (the scale curve takes a puff from 1 m to its full size)
	q.material = _smoke_mat
	ps.draw_pass_1 = q
	ps.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(20, 18, 14))
	ps.visibility_range_end = 450.0
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.position = at
	root.add_child(ps)
