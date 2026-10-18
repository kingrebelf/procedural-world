class_name Furnish
## Room furniture as it really stands. The furnishing lists (KitHouse.FURNISH,
## Interiors.FURNISH) give each piece by hand, but a model's pivot isn't always its foot,
## and a piece turned a little reaches further than it did square on: crates sat into the
## walls and into each other, and pieces meant for the floor went into it. settled() takes
## each list once and, measuring every piece by its real bounds:
## - stands what was meant for the floor (its foot within a few centimetres of it, above
##   or below) exactly on the floor;
## - moves such a solid piece out of a solid piece already standing beside it (their
##   turned footprints, not just their boxes, overlap);
## - brings it, or a piece stacked on another, back inside the walls where it reached
##   into them (to the plaster less any skirting or plinth; the round walls and dome of
##   the huts and the hab dome at the height of the piece's top).
## Pieces on tables and shelves, stacked or hung on a wall keep the height they were
## given. Every user of the lists (the room meshes, their collision, lights, readable
## spots, shop counters) takes them from here, so they all agree.

## A piece's foot this far over the floor, or under it, is meant to stand on it.
const OVER := 0.15
const UNDER := 0.3
## Clearance kept from walls and between solid pieces moved apart.
const GAP := 0.01

static var _cache: Dictionary = {}
static var _lock := Mutex.new()

## The room type's furniture, settled: [model or "@piece", yaw (degrees), position, solid].
static func settled(t: String) -> Array:
	_lock.lock()
	var have = _cache.get(t)
	_lock.unlock()
	if have != null:
		return have
	var raw: Array = KitHouse.FURNISH.get(t, Interiors.FURNISH.get(t, []))
	var out := settle(raw, room(t))
	_lock.lock()
	_cache[t] = out
	_lock.unlock()
	return out

## The room a type's furniture stands in: {floor, half (Vector2, straight walls) or
## wall: Callable(y) -> radius (round walls)}.
static func room(t: String) -> Dictionary:
	if KitHouse.has(t):
		# To the plaster, less the skirting along its foot.
		var dm := KitHouse._dims(t)
		var sk: float = (Trim.SKIRT[-1] as Vector2).x
		return {"floor": KitHouse.FLOOR, "half": Vector2(dm.x / 2 - Trim.KIT_PLASTER - sk, dm.z / 2 - Trim.KIT_PLASTER - sk)}
	if Interiors.BOX.has(t):
		# Stone halls have a plinth course round their foot.
		var b: Array = Interiors.BOX[t]
		var pl: float = (Trim.PLINTH[-1] as Vector2).x if t.begins_with("castle") or t.begins_with("crypt") else 0.0
		return {"floor": float(b[1]), "half": (b[0] as Vector2) - Vector2(pl, pl)}
	if Interiors.ROUND.has(t):
		var r: Array = Interiors.ROUND[t]
		# The wall leans in from its foot to its top; its inner face, at height y.
		var wall := func(y: float) -> float:
			var f := clampf((y - float(r[3])) / (float(r[4]) - float(r[3])), 0.0, 1.0)
			return lerpf(float(r[0]), float(r[1]), f) - float(r[2])
		return {"floor": float(r[5]), "wall": wall}
	if t == "hab_dome":
		var d: Array = Interiors.DOME
		var fl: float = d[3]
		var wall := func(y: float) -> float:
			var rin: float = float(d[0]) - float(d[1])
			var u := clampf((y - fl) / (rin * float(d[2])), 0.0, 1.0)
			return rin * sqrt(1.0 - u * u)
		return {"floor": fl, "wall": wall}
	return {"floor": Interiors.SHRINE_FLOOR}

## A piece's bounds in the room at transform xf.
static func box_of(name: String, xf: Transform3D) -> AABB:
	if name.begins_with("@"):
		var sz: Vector3 = Interiors.PIECES.get(name, Vector3(1, 1, 1))
		var a := xf * Vector3(-sz.x / 2, 0, -sz.z / 2)
		var out := AABB(a, Vector3.ZERO)
		for i in 8:
			out = out.expand(xf * Vector3(sz.x * (0.5 if i & 1 else -0.5), sz.y if i & 2 else 0.0, sz.z * (0.5 if i & 4 else -0.5)))
		return out
	return KitHouse._model_box(name, xf)

static func settle(raw: Array, rm: Dictionary) -> Array:
	var fl: float = rm["floor"]
	var out: Array = []
	var boxes: Array = [] # settled bounds, by index into out
	var feet: Array = [] # settled footprints (four corners, x z), by index into out
	for e in raw:
		var name: String = e[0]
		var p: Vector3 = e[2]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e[1]))), p)
		var box := box_of(name, xf)
		var foot := footprint(name, xf)
		var move := Vector3.ZERO
		# On the floor. What stands there also keeps out of the walls and of its
		# neighbours; what hangs on a wall or stands on a table keeps its place.
		var fy := box.position.y
		var floored := fy - fl <= OVER and fl - fy <= UNDER
		if floored:
			move.y = fl - fy
			box.position.y += move.y
			if e[3]:
				for i in out.size():
					if not out[i][3] or not _overlap(foot, feet[i]):
						continue
					var o: AABB = boxes[i]
					var ov := box.intersection(o)
					if ov.size.y < 0.05:
						continue # one stands on the other
					var d := box.get_center() - o.get_center()
					var step := Vector3.ZERO
					if ov.size.x < ov.size.z:
						step.x = (ov.size.x + GAP) * (1.0 if d.x >= 0.0 else -1.0)
					else:
						step.z = (ov.size.z + GAP) * (1.0 if d.z >= 0.0 else -1.0)
					box.position += step
					move += step
					foot = _moved(foot, step)
		# Inside the walls: what stands on the floor, and what is stacked on a piece below
		# it (a crate on a crate), not what hangs on the wall.
		var stacked := false
		for i in out.size():
			if absf(fy - (boxes[i] as AABB).end.y) < 0.05 and _overlap(foot, feet[i]):
				stacked = true
		if floored or stacked:
			var wall := _into_room(box, rm)
			box.position += wall
			move += wall
			foot = _moved(foot, wall)
		var q: Array = (e as Array).duplicate()
		q[2] = p + move
		out.append(q)
		boxes.append(box)
		feet.append(foot)
	return out

## A piece's footprint at xf: the four corners of its own bounds, turned with it (x z).
static func footprint(name: String, xf: Transform3D) -> PackedVector2Array:
	var b: AABB
	if name.begins_with("@"):
		var sz: Vector3 = Interiors.PIECES.get(name, Vector3(1, 1, 1))
		b = AABB(Vector3(-sz.x / 2, 0, -sz.z / 2), sz)
	else:
		b = KitHouse._model_box(name, Transform3D.IDENTITY)
	var out := PackedVector2Array()
	for c in [Vector3(b.position.x, 0, b.position.z), Vector3(b.end.x, 0, b.position.z), Vector3(b.end.x, 0, b.end.z), Vector3(b.position.x, 0, b.end.z)]:
		var w: Vector3 = xf * c
		out.append(Vector2(w.x, w.z))
	return out

static func _moved(f: PackedVector2Array, m: Vector3) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in f:
		out.append(c + Vector2(m.x, m.z))
	return out

## Whether two footprints overlap by more than GAP (separating axes).
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		for i in 4:
			var edge: Vector2 = poly[(i + 1) % 4] - poly[i]
			var ax := Vector2(-edge.y, edge.x).normalized()
			var lo_a := INF
			var hi_a := -INF
			var lo_b := INF
			var hi_b := -INF
			for c in a:
				lo_a = minf(lo_a, ax.dot(c))
				hi_a = maxf(hi_a, ax.dot(c))
			for c in b:
				lo_b = minf(lo_b, ax.dot(c))
				hi_b = maxf(hi_b, ax.dot(c))
			if hi_a <= lo_b + GAP or hi_b <= lo_a + GAP:
				return false
	return true

## How far to move bounds `b` so they stand inside the room's walls (zero if they do).
static func _into_room(b: AABB, rm: Dictionary) -> Vector3:
	if rm.has("half"):
		var h: Vector2 = rm["half"]
		var m := Vector3.ZERO
		if b.end.x > h.x - GAP:
			m.x = h.x - GAP - b.end.x
		elif b.position.x < -h.x + GAP:
			m.x = -h.x + GAP - b.position.x
		if b.end.z > h.y - GAP:
			m.z = h.y - GAP - b.end.z
		elif b.position.z < -h.y + GAP:
			m.z = -h.y + GAP - b.position.z
		return m
	if rm.has("wall"):
		# The corner furthest out, at the piece's top (the wall leans in above).
		var r: float = (rm["wall"] as Callable).call(b.end.y) - GAP
		var far := Vector2.ZERO
		for i in 4:
			var c := Vector2(b.end.x if i & 1 else b.position.x, b.end.z if i & 2 else b.position.z)
			if c.length() > far.length():
				far = c
		if far.length() > r and far.length() > 0.001:
			var back := far.normalized() * (far.length() - r)
			return Vector3(-back.x, 0, -back.y)
	return Vector3.ZERO
