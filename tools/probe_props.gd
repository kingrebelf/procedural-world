extends SceneTree
class_name ProbeProps
## How well props sit on what is under them, no GPU needed.
##   godot --headless --path . --script res://tools/probe_props.gd -- [--seed=4242] [--r=2] [--old]
## Ground: generates the chunks of the settlements within r cells of the origin (and a
## ring of wild chunks), and for every chest, wagon, barrel stack, stall and cart measures
## its base against the ground at nine points under its footprint: how deep the deepest
## point is buried and how high the highest floats. --old measures the transform props
## had before PropSettle (level, sunk 0.15 m at their middle).
## Floors: every piece of furniture in the rooms (KitHouse, Interiors) and the caches
## stocked into them, against the floor it stands on.
func _init() -> void:
	var seed := 4242
	var R := 2
	var old := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = int(a.get_slice("=", 1))
		elif a.begins_with("--r="):
			R = int(a.get_slice("=", 1))
		elif a == "--old":
			old = true
	var g := survey(seed, R, old)
	for l in g["lines"]:
		print(l)
	for l in floors()["lines"]:
		print(l)
	quit()

## Props on the ground: {"lines", "worst_bury", "worst_float", "n"}.
static func survey(seed: int, R: int, old: bool) -> Dictionary:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION # a new world's land
	var gen := ChunkGenerator.new(seed, true)
	var keys := {}
	for sz in range(-R, R + 1):
		for sx in range(-R, R + 1):
			var s := gen.settlement_at(sx, sz)
			if s.is_empty():
				continue
			var c: Vector2 = s["center"]
			var rad := float(s["inner"]) + 24.0
			for kz in range(int(floor((c.y - rad) / 64.0)), int(floor((c.y + rad) / 64.0)) + 1):
				for kx in range(int(floor((c.x - rad) / 64.0)), int(floor((c.x + rad) / 64.0)) + 1):
					keys[Vector2i(kx, kz)] = true
	for kz in range(-3, 4):
		for kx in range(-3, 4):
			keys[Vector2i(kx, kz)] = true
	var per := {} # type -> [n, sum bury, max bury, max float, bad]
	var rooms := {} # room type -> [n, max ground over floor, rooms with ground over floor]
	var worst_b := 0.0
	var worst_f := 0.0
	var n := 0
	for k in keys:
		var chunk: Dictionary = gen.generate(k.x, k.y)
		for o in chunk["objects"]:
			var rk := ObjectLibrary.mesh_key(o).get_slice(Stronghold.VAR, 0)
			if (KitHouse.has(rk) or Interiors.has(rk)) and not o["st"].get("gone", false):
				var over := ground_over_floor(chunk, o, rk)
				if not rooms.has(rk):
					rooms[rk] = [0, 0.0, 0]
				rooms[rk][0] += 1
				rooms[rk][1] = maxf(rooms[rk][1], over)
				if over > 0.0:
					rooms[rk][2] += 1
			if not PropSettle.settles(o["t"]):
				continue
			var m := measure(chunk, o, old)
			if m.is_empty():
				continue # not on the ground (in a cave, a room)
			if not per.has(o["t"]):
				per[o["t"]] = [0, 0.0, 0.0, 0.0, 0]
			var e: Array = per[o["t"]]
			e[0] += 1
			e[1] += m["bury"]
			e[2] = maxf(e[2], m["bury"])
			e[3] = maxf(e[3], m["float"])
			if m["bury"] > 0.12 or m["float"] > 0.03:
				e[4] += 1
			worst_b = maxf(worst_b, m["bury"])
			worst_f = maxf(worst_f, m["float"])
			n += 1
	var lines := ["Props on the ground (%s), seed %d, %d chunks:" % ["old" if old else "settled", seed, keys.size()],
		"  type            n   mean bury  max bury  max float  bad (bury>12cm or float>3cm)"]
	for t in per:
		var e: Array = per[t]
		lines.append("  %-14s %3d   %6.3f    %6.3f    %6.3f    %d" % [t, e[0], e[1] / e[0], e[2], e[3], e[4]])
	lines.append("Ground over room floors (the land showing through the floor):")
	lines.append("  type            n   max over  rooms with ground over floor")
	var worst_room := 0.0
	for t in rooms:
		lines.append("  %-14s %3d   %6.3f    %d" % [t, rooms[t][0], rooms[t][1], rooms[t][2]])
		worst_room = maxf(worst_room, rooms[t][1])
	return {"lines": lines, "worst_room": worst_room, "worst_bury": worst_b, "worst_float": worst_f, "n": n}

## The deepest buried and highest floating points of a prop's base, over nine points of
## its footprint ({} when it does not stand on the ground).
static func measure(chunk: Dictionary, o: Dictionary, old := false) -> Dictionary:
	var xf: Transform3D
	if old:
		var s: float = o["s"]
		xf = Transform3D(Basis(Vector3.UP, o["r"]).scaled(Vector3(s, s, s)), (o["p"] as Vector3) - Vector3(0, 0.15 * s, 0))
		if not PropSettle.on_ground(chunk, o):
			return {}
	else:
		var st = PropSettle.transform(chunk, o)
		if st == null:
			return {}
		xf = st
	var box := ObjectLibrary.get_mesh(ObjectLibrary.mesh_key(o)).get_aabb()
	var bury := -INF
	var flt := -INF
	for i in 3:
		for j in 3:
			var q := Vector3(box.position.x + box.size.x * (0.05 + 0.45 * i), box.position.y, box.position.z + box.size.z * (0.05 + 0.45 * j))
			var w := xf * q
			var gy := ChunkGenerator.height_at(chunk, clampf(w.x, 0.0, ChunkGenerator.SIZE - 0.01), clampf(w.z, 0.0, ChunkGenerator.SIZE - 0.01))
			bury = maxf(bury, gy - w.y)
			flt = maxf(flt, w.y - gy)
	return {"bury": maxf(bury, 0.0), "float": maxf(flt, 0.0)}

## Furniture against the floors of the rooms: {"lines", "bad"}. A piece meant to stand on
## the floor whose lowest point is more than 5 cm under it (sunk out of sight), or more
## than 1 cm over it (a gap you see).
static func floors() -> Dictionary:
	var lines := ["Furniture on floors (lowest point minus floor; - is sunk in):"]
	var bad := 0
	var rooms := {}
	for t in KitHouse.FURNISH:
		rooms[t] = [KitHouse.FURNISH[t], KitHouse.FLOOR]
	for t in Interiors.FURNISH:
		rooms[t] = [Interiors.FURNISH[t], floor_of(t)]
	for t in rooms:
		var fl: float = rooms[t][1]
		for f in rooms[t][0]:
			var name: String = f[0]
			if name.begins_with("@"):
				continue
			var p: Vector3 = f[2]
			if absf(p.y - fl) > 0.001:
				continue # on a table or shelf, hung up
			var box := KitHouse._model_box(name, Transform3D(Basis(Vector3.UP, deg_to_rad(float(f[1]))), p))
			var d := box.position.y - fl
			if d < -0.05 or d > 0.01:
				bad += 1
			if absf(d) > 0.01:
				lines.append("  %-14s %-28s %+.3f" % [t, name, d])
	for t in Interiors.LOOT:
		var fl := floor_of(t)
		for spot in Interiors.LOOT[t]:
			var q: Vector3 = spot[0]
			if absf(q.y - fl) > 0.001:
				continue
			for c in Eras.CACHE_TYPES:
				var box := ObjectLibrary.get_mesh(c).get_aabb()
				var d := q.y + box.position.y - fl
				if d < -0.05 or d > 0.01:
					bad += 1
				if absf(d) > 0.01:
					lines.append("  %-14s %-28s %+.3f" % [t, c + " (loot)", d])
	lines.append("  %d pieces off their floor" % bad)
	return {"lines": lines, "bad": bad}

## The floor height of a room type, in its own space (before the room sinks).
static func floor_of(t: String) -> float:
	if KitHouse.has(t):
		return KitHouse.FLOOR
	if Interiors.BOX.has(t):
		return float(Interiors.BOX[t][1])
	if Interiors.ROUND.has(t):
		return float(Interiors.ROUND[t][5])
	if t == "hab_dome":
		return float(Interiors.DOME[3])
	return Interiors.SHRINE_FLOOR

## How far the ground rises above a room's floor anywhere inside it (0 when it doesn't).
static func ground_over_floor(chunk: Dictionary, o: Dictionary, t: String) -> float:
	var s: float = o["s"]
	var fl: float = (o["p"] as Vector3).y + (floor_of(t) - Interiors.SINK) * s
	var half := inner_half(t) * s
	var b := Basis(Vector3.UP, o["r"])
	var worst := 0.0
	for i in 5:
		for j in 5:
			var q := b * Vector3(half.x * (i / 2.0 - 1.0), 0, half.y * (j / 2.0 - 1.0))
			var w := (o["p"] as Vector3) + q
			var gy := ChunkGenerator.height_at(chunk, w.x, w.z)
			worst = maxf(worst, gy - fl)
	return worst

## The half size of a room's floor (x, z), a little in from the walls.
static func inner_half(t: String) -> Vector2:
	if KitHouse.has(t):
		var dm := KitHouse._dims(t)
		return Vector2(dm.x * 0.5 - KitHouse.WALL_IN - 0.1, dm.z * 0.5 - KitHouse.WALL_IN - 0.1)
	if Interiors.BOX.has(t):
		return (Interiors.BOX[t][0] as Vector2) - Vector2(0.1, 0.1)
	if Interiors.ROUND.has(t):
		var r: float = (float(Interiors.ROUND[t][0]) - float(Interiors.ROUND[t][2])) * 0.68
		return Vector2(r, r)
	if t == "hab_dome":
		return Vector2(2.8, 2.8)
	return Vector2(1.5, 1.5)
