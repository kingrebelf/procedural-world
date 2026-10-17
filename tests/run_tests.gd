extends SceneTree
## Headless test suite. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.

var _failures := 0
var _passes := 0
var _current := ""

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	# TEST_ONLY=part runs just the tests whose names contain it.
	var only := OS.get_environment("TEST_ONLY")
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and (only == "" or n.contains(only)):
			_current = n
			call(n)
	print("\n%d checks passed, %d failed (%d ms)" % [_passes, _failures, Time.get_ticks_msec() - t0])
	quit(1 if _failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, msg])

func _tmp_store(name: String) -> WorldStore:
	var dir := "user://test_worlds/%s_%d" % [name, Time.get_ticks_usec()]
	var s := WorldStore.new(dir)
	s.meta = {"seed": 1234}
	return s

# --- Determinism ---------------------------------------------------------------

func test_hash_is_stable() -> void:
	# Pinned values: if these change, every existing world would change.
	check(WHash.h32(0) == 0, "h32(0)")
	check(WHash.h32(1) == WHash.h32(1), "h32 deterministic")
	var a := WHash.hash2(42, 3, -7, 1)
	check(a == WHash.hash2(42, 3, -7, 1), "hash2 deterministic")
	check(a != WHash.hash2(42, -7, 3, 1), "hash2 is order sensitive")
	check(a >= 0 and a <= WHash.MASK, "hash2 in 32-bit range")
	check(WHash.str_hash("hello") == 0x4F9F2CAB, "FNV-1a pinned value, got %x" % WHash.str_hash("hello"))
	var buckets := [0, 0, 0, 0]
	for i in 4000:
		buckets[WHash.hash2(9, i, 0) % 4] += 1
	for b in buckets:
		check(b > 850 and b < 1150, "hash distribution bucket %d" % b)

func test_memory_store_never_touches_disk() -> void:
	var s := WorldStore.memory()
	var g := ChunkGenerator.new(77)
	var c := s.get_or_create_chunk(g, 4, -2)
	check(s.has_chunk(4, -2) and s.load_chunk(4, -2) == c, "memory store keeps chunks")
	check(not DirAccess.dir_exists_absolute("chunks") and not FileAccess.file_exists(s.chunk_path(4, -2)), "memory store writes nothing")
	for i in WorldStore.MEM_LIMIT + 5:
		s.save_chunk({"cx": 1000 + i, "cz": 0})
	check(not s.has_chunk(4, -2) and s.has_chunk(1000 + WorldStore.MEM_LIMIT + 4, 0), "memory store drops the oldest chunks")

func test_rivers() -> void:
	var g := ChunkGenerator.new(4242, true)
	# Find a chunk a river runs through, with its water above the sea.
	var found := {}
	for r in 40:
		for cz in range(-r, r + 1):
			for cx in [-r, r]:
				if found.is_empty() and g.field.river_t(cx * 64.0 + 32.0, cz * 64.0 + 32.0) < 0.6:
					var t0 := Time.get_ticks_msec()
					var c := g.generate(cx, cz)
					var ms := Time.get_ticks_msec() - t0
					if c.has("river") and RiverMesh.build_river_arrays(c).size() > 0:
						found = c
						found["ms"] = ms
		if not found.is_empty():
			break
	check(not found.is_empty(), "a river runs somewhere near spawn")
	if found.is_empty():
		return
	print("    river chunk %d,%d generated in %d ms" % [found["cx"], found["cz"], found["ms"]])
	var wet := 0
	var dry_bed := 0
	var trees := 0
	for lz in range(0, 64, 2):
		for lx in range(0, 64, 2):
			var s := ChunkGenerator.river_surface(found, lx, lz)
			if is_nan(s):
				continue
			wet += 1
			if ChunkGenerator.height_at(found, lx, lz) > s - 0.2:
				dry_bed += 1
	for o in found["objects"]:
		if ObjectLibrary.kind(o["t"]) in ["tree", "rock"] and ChunkGenerator.under_river(found, o["p"].x, o["p"].z):
			trees += 1
	check(wet > 10, "river chunk has water (%d cells)" % wet)
	check(dry_bed <= wet / 10, "river bed lies under the water (%d of %d cells shallow)" % [dry_bed, wet])
	check(trees == 0, "no trees or rocks stand in the river")
	var again := ChunkGenerator.new(4242, true).generate(found["cx"], found["cz"])
	check(again["river"] == found["river"] and again["heights"] == found["heights"], "rivers are deterministic")
	var old := ChunkGenerator.new(4242).generate(found["cx"], found["cz"])
	check(not old.has("river"), "worlds made before rivers get none")

func test_same_seed_same_chunk() -> void:
	var g1 := ChunkGenerator.new(777)
	var g2 := ChunkGenerator.new(777)
	for c in [Vector2i(0, 0), Vector2i(-3, 5), Vector2i(12, -9)]:
		var a := g1.generate(c.x, c.y)
		var b := g2.generate(c.x, c.y)
		check(var_to_bytes(a) == var_to_bytes(b), "chunk %s identical across generator instances" % c)
	var other := ChunkGenerator.new(778).generate(0, 0)
	check(var_to_bytes(other["heights"]) != var_to_bytes(g1.generate(0, 0)["heights"]), "different seed differs")

func test_chunk_edges_are_seamless() -> void:
	var g := ChunkGenerator.new(31337)
	var R := ChunkGenerator.RES
	var a := g.generate(0, 0)
	var b := g.generate(1, 0)
	var c := g.generate(0, 1)
	var maxd := 0.0
	for k in R:
		maxd = maxf(maxd, absf(a["heights"][k * R + R - 1] - b["heights"][k * R]))
		maxd = maxf(maxd, absf(a["heights"][(R - 1) * R + k] - c["heights"][k]))
	check(maxd < 0.0001, "shared edges match (max diff %f)" % maxd)

# --- Eras and transitions --------------------------------------------------------

func test_era_weights_continuous_and_normalised() -> void:
	var f := WorldField.new(2024)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var worst := 0.0
	for n in 3000:
		var x := r.randf_range(-5000, 5000)
		var z := r.randf_range(-5000, 5000)
		var w1 := f.era_weights(x, z)
		var w2 := f.era_weights(x + 0.5, z)
		var sum := 0.0
		for e in Eras.COUNT:
			sum += w1[e]
			worst = maxf(worst, absf(w1[e] - w2[e]))
		check(absf(sum - 1.0) < 0.0001, "weights sum to 1")
	check(worst < 0.08, "era weights change smoothly (worst step over 0.5 m: %f)" % worst)

func test_terrain_versions() -> void:
	# Older worlds keep their terrain; new ones get highlands and mesas.
	var f := WorldField.new(2024)
	var old_h := PackedFloat32Array()
	var new_h := PackedFloat32Array()
	var tallest := -INF
	WorldField.terrain_v = 3
	for i in 400:
		old_h.append(f.height(i * 53.0 - 9000.0, i * 31.0 - 4000.0))
	WorldField.terrain_v = 4
	for i in 400:
		new_h.append(f.height(i * 53.0 - 9000.0, i * 31.0 - 4000.0))
	for i in 4000:
		tallest = maxf(tallest, f.height(i * 17.0 - 30000.0, sin(i * 0.003) * 6000.0))
	check(old_h != new_h, "v4 terrain differs from v3")
	check(tallest > 55.0, "v4 has highlands above the snow line (tallest %f)" % tallest)
	var st := WorldStore.memory()
	st.meta = {}
	check(st.terrain_version() == 1, "worlds saved before versions use the oldest terrain")
	check(WorldStore.memory().terrain_version() == ChunkGenerator.GEN_VERSION, "new worlds use the newest terrain")

func test_terrain_has_no_cliffs_from_blending() -> void:
	var f := WorldField.new(2024)
	var worst := 0.0
	var worst_blend := 0.0
	var blend_samples := 0
	for i in 20000:
		var x := -10000.0 + i * 1.0
		var z := 300.0 + sin(i * 0.01) * 400.0
		var w := f.era_weights(x, z)
		var d := absf(f.height(x + 1.0, z) - f.height(x, z, w))
		worst = maxf(worst, d)
		if w[WorldField.dominant(w)] < 0.7:
			blend_samples += 1
			worst_blend = maxf(worst_blend, d)
	# Fantasy spire faces are steep by design, but nothing is a vertical tear,
	# and transition bands are gentler than any pure era.
	check(worst < 6.0, "max height step per metre %f" % worst)
	check(blend_samples > 200, "walk sampled transition bands (%d)" % blend_samples)
	check(worst_blend < 3.0, "transition bands stay walkable-ish (worst %f)" % worst_blend)

func test_landforms() -> void:
	WorldField.terrain_v = 6
	var f6 := WorldField.new(2024)
	var flat := true
	for i in 300:
		var sh := f6.shape(i * 37.0 - 5000.0, i * 13.0)
		flat = flat and sh.y == 0.0 and sh.z == 0.0 and f6.landform_weights(i * 37.0, 0.0)[WorldField.LF_KARST] == 0.0
	check(flat, "v6 worlds have no landforms")
	WorldField.terrain_v = 7
	var f := WorldField.new(2024)
	# Every landform turns up, each in the eras that have it.
	var deep := {}
	var seen := {}
	for iz in range(-25, 25):
		for ix in range(-25, 25):
			var lf := f.site_landform(ix, iz)
			seen[lf] = true
			var era := f.site_era(ix, iz)
			var ok := false
			for o in WorldField.LANDFORM_ODDS[era]:
				ok = ok or o[0] == lf
			if not ok:
				check(false, "landform %d is not one of era %d's" % [lf, era])
			var p := f.site_pos(ix, iz)
			if not deep.has(lf) and f.landform_weights(p.x, p.y)[lf] > 0.97:
				deep[lf] = p
	check(seen.size() == WorldField.LF_COUNT, "all %d landforms appear (%d)" % [WorldField.LF_COUNT, seen.size()])
	# Deep inside each, the land has that landform's character.
	for lf in deep:
		var c: Vector2 = deep[lf]
		var hi := -INF
		var lo := INF
		var rough_hi := 0.0
		var hole_lo := 0.0
		var wet := 0
		var n := 0
		for j in 40:
			for i in 40:
				var x := c.x + (i - 20) * 4.0
				var z := c.y + (j - 20) * 4.0
				if f.landform_weights(x, z)[lf] < 0.9:
					continue
				var sh := f.shape(x, z)
				var h := sh.x + sh.y + sh.z
				hi = maxf(hi, h)
				lo = minf(lo, h)
				rough_hi = maxf(rough_hi, sh.z)
				hole_lo = minf(hole_lo, sh.y)
				wet += 1 if h < ChunkGenerator.WATER_LEVEL else 0
				n += 1
		var name: String = WorldField.LANDFORM_NAMES[lf]
		print("  %-12s samples %4d  height %6.1f..%6.1f  rough %5.1f  holes %6.1f  wet %3d%%" % [name, n, lo, hi, rough_hi, hole_lo, 100 * wet / maxi(n, 1)])
		match lf:
			WorldField.LF_KARST:
				check(rough_hi > 30.0, "karst has towers (%.1f)" % rough_hi)
			WorldField.LF_NEEDLES:
				check(rough_hi > 25.0, "needles rise high (%.1f)" % rough_hi)
			WorldField.LF_SINKHOLES:
				check(hole_lo < -10.0, "sinkholes are deep (%.1f)" % hole_lo)
			WorldField.LF_CRATERS:
				check(hole_lo < -3.0 and rough_hi > 1.0, "craters have bowls and rims (%.1f, %.1f)" % [hole_lo, rough_hi])
			WorldField.LF_GORGE:
				check(hole_lo < -15.0, "gorges are deep (%.1f)" % hole_lo)
			WorldField.LF_LAKES:
				check(wet * 100 > n * 15 and wet * 100 < n * 85, "lake country is part water (%d of %d)" % [wet, n])
			WorldField.LF_DUNES:
				check(rough_hi > 2.0 and rough_hi < 12.0, "dunes are dune-sized (%.1f)" % rough_hi)
			WorldField.LF_BADLANDS, WorldField.LF_CRAGS:
				check(rough_hi > 6.0, "%s are rugged (%.1f)" % [name, rough_hi])
	check(deep.size() >= WorldField.LF_COUNT - 2, "found the heart of most landforms (%d)" % deep.size())
	# The smooth base that roads and rivers plan on has no tears between regions.
	var worst := 0.0
	for i in 20000:
		var x := -10000.0 + i * 1.0
		var z := 300.0 + sin(i * 0.01) * 400.0
		worst = maxf(worst, absf(f.shape(x + 1.0, z).x - f.shape(x, z).x))
	check(worst < 3.0, "landform bases blend smoothly (worst step %.2f m)" % worst)
	# Chunks generate with them, the towers included, in reasonable time.
	if deep.has(WorldField.LF_KARST):
		var g := ChunkGenerator.new(2024)
		var k: Vector2 = deep[WorldField.LF_KARST]
		var t0 := Time.get_ticks_msec()
		var top := -INF
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var ch := g.generate(int(floor(k.x / 64.0)) + o.x, int(floor(k.y / 64.0)) + o.y)
			for h in ch["heights"]:
				top = maxf(top, h)
		print("  karst chunks: %d ms each, top %.1f m" % [(Time.get_ticks_msec() - t0) / 3, top])
		check(top > f.shape(k.x, k.y).x + 15.0, "karst chunks hold towers (%.1f)" % top)
		var ch := g.generate(int(floor(k.x / 64.0)), int(floor(k.y / 64.0)))
		check(ch.has("look") and (ch["look"] as PackedByteArray).size() == ChunkGenerator.LOOK_N * ChunkGenerator.LOOK_N * ChunkGenerator.LOOK_BYTES, "karst chunks carry their look")
		check(String(ch["region"]).ends_with("Pillars"), "the region is named for its landform (%s)" % ch["region"])
		# (The terrain mesh built from it is checked in the integration test: ChunkNode
		# needs the Game autoload.)
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

func test_house_interiors() -> void:
	for t in KitHouse.PLANS:
		var dm := KitHouse._dims(t)
		var room := ObjectLibrary.get_mesh(t + "~in")
		check(room.get_surface_count() >= 4, "%s has a furnished room (%d surfaces)" % [t, room.get_surface_count()])
		var glow := ObjectLibrary.get_mesh(t + "~glow")
		check(glow.get_surface_count() == 1 and glow.get_aabb().size.x > 2.0, "%s has lamplit windows" % t)
		# Every piece of furniture loads and stands inside the walls, clear of the way in.
		var hx := dm.x / 2 - KitHouse.WALL_IN + 0.05
		var hz := dm.z / 2 - KitHouse.WALL_IN + 0.05
		var lane := AABB(Vector3(-0.6, KitHouse.FLOOR + 0.05, dm.z / 2 - 1.8), Vector3(1.2, 1.8, 1.8))
		for e in KitHouse.FURNISH[t]:
			var bx := KitHouse._model_box(e[0], Transform3D(Basis(Vector3.UP, deg_to_rad(float(e[1]))), e[2]))
			var fits: bool = bx.size.length() > 0.01 and bx.position.x > -hx and bx.end.x < hx and bx.position.z > -hz and bx.end.z < hz and bx.end.y < dm.y
			check(fits, "%s: %s stands inside the walls (%s)" % [t, e[0], bx])
			check(not bx.intersects(lane), "%s: %s leaves the doorway clear" % [t, e[0]])
		# Collision: the doorway is open to a capsule's width at every height a player has;
		# the walls, floor and roof are closed.
		var faces: PackedVector3Array = (KitHouse.shape(t)[0] as ConcavePolygonShape3D).get_faces()
		var open := true
		for y in [0.3, 1.0, 1.9]:
			for x in [-0.36, 0.0, 0.36]:
				open = open and _ray_hit(faces, Vector3(x, KitHouse.FLOOR + y, dm.z / 2 + 2.0), Vector3(x, KitHouse.FLOOR + y, dm.z / 2 - 1.2)) == INF
		check(open, "%s: the doorway is open" % t)
		var c := Vector3(0, KitHouse.FLOOR + 1.2, 0.8)
		var shut: bool = _ray_hit(faces, Vector3(1.6, 1.2, dm.z / 2 + 2.0), Vector3(1.6, 1.2, 0)) < INF
		for to in [Vector3(dm.x, 1.2, 0.8), Vector3(-dm.x, 1.2, 0.8), Vector3(-0.2, 2.6, -dm.z), Vector3(0, dm.y + 9.0, 0.8), Vector3(0, -2.0, 0.8)]:
			shut = shut and _ray_hit(faces, c, to) < INF
		check(shut, "%s: walls, roof and floor are closed" % t)
		var inside := Vector3(0, KitHouse.FLOOR + 1.2, dm.z / 2 - 1.0)
		var floor_at := inside.y - _ray_hit(faces, inside, Vector3(0, -2.0, inside.z))
		check(absf(floor_at - KitHouse.FLOOR) < 0.01, "%s: the floor collides where it is drawn (%.2f)" % [t, floor_at])

func test_room_interiors() -> void:
	for t in Interiors.FURNISH:
		var shell := ObjectLibrary.get_mesh(t)
		check(shell != null and shell.get_surface_count() >= 2, "%s builds" % t)
		var room := ObjectLibrary.get_mesh(t + "~in")
		check(room.get_surface_count() >= 2, "%s has a furnished room (%d surfaces)" % [t, room.get_surface_count()])
		if Interiors.glows(t):
			check(ObjectLibrary.get_mesh(t + "~glow").get_surface_count() == 1, "%s has lamplit windows" % t)
		check(not Interiors.lights(t).is_empty() and Interiors.LOOT.has(t), "%s is lit and has loot" % t)
		var faces: PackedVector3Array = (ObjectLibrary.shape_of({"t": t, "st": {}})[0] as ConcavePolygonShape3D).get_faces()
		# Where the doorway is, how high the floor is, and a point in the middle of the room.
		var door_x := 0.0
		var outside := 0.0
		var past := 0.0
		var fl := Interiors.SHRINE_FLOOR
		var mid := Vector3.ZERO
		if Interiors.BOX.has(t):
			var b: Array = Interiors.BOX[t]
			fl = b[1]
			door_x = b[5][0]
			outside = (b[3] as Vector2).y + 2.0
			past = (b[0] as Vector2).y - 0.6
			mid = Vector3(door_x, fl + 1.2, (b[0] as Vector2).y - 1.2)
		elif Interiors.ROUND.has(t):
			var p: Array = Interiors.ROUND[t]
			fl = p[5]
			outside = float(p[0]) + 2.0
			past = float(p[0]) - float(p[2]) - 0.5
			mid = Vector3(0, fl + 1.2, past - 0.3)
		elif t == "hab_dome":
			fl = Interiors.DOME[3]
			outside = 6.5
			past = 2.2
			mid = Vector3(0, fl + 1.2, 1.4)
		else:
			outside = 4.0
			past = 0.6
			mid = Vector3(0, fl + 1.2, 1.2)
		var open := true
		for y in [0.4, 1.0, 1.8]:
			for x in [-0.32, 0.0, 0.32]:
				open = open and _ray_hit(faces, Vector3(door_x + x, fl + y, outside), Vector3(door_x + x, fl + y, past)) == INF
		check(open, "%s: the doorway is open" % t)
		var floor_at := mid.y - _ray_hit(faces, mid, mid + Vector3(0, -3.0, 0))
		check(absf(floor_at - fl) < 0.02, "%s: the floor collides where it is drawn (%.2f, drawn %.2f)" % [t, floor_at, fl])
		if t != "shrine":
			var shut := true
			for to in [Vector3(-20, 0, 0), Vector3(20, 0, 0), Vector3(0, 0, -20), Vector3(0, 20, 0)]:
				shut = shut and _ray_hit(faces, mid, mid + to) < INF
			check(shut, "%s: walls and ceiling are closed" % t)
		# The loot goes on the floor, clear of the furniture you bump into.
		for spot in Interiors.LOOT[t]:
			var q: Vector3 = spot[0]
			# A tower's loot waits on its roof.
			var on: float = Interiors.BOX[t][4] if Interiors.TOWER.has(t) else fl
			check(absf(q.y - on) < 0.01, "%s: loot sits on the floor" % t)
			var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(spot[1]))), q)
			var cb := xf * AABB(Vector3(-0.6, 0.05, -0.4), Vector3(1.2, 0.8, 0.8))
			var clear := true
			for e in Interiors.FURNISH[t]:
				if e[3]:
					var ex := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e[1]))), e[2])
					var bx: AABB
					if String(e[0]).begins_with("@"):
						var sz: Vector3 = Interiors.PIECES[e[0]]
						bx = ex * AABB(Vector3(-sz.x * 0.5, 0, -sz.z * 0.5), sz)
					else:
						bx = KitHouse._model_box(e[0], ex)
					if bx.intersects(cb):
						clear = false
						printerr("  %s: loot overlaps %s" % [t, e[0]])
			check(clear, "%s: the loot spot is clear" % t)
			check(_ray_hit(faces, xf * Vector3(0, 0.6, 1.0), xf * Vector3(0, 0.4, 0)) == INF, "%s: the loot can be reached from in front" % t)

## Tower stairs: each flight a walkable slope from one landing to the next, room for
## your head all the way up, and the last flight out through the hatch onto the roof.
func test_tower_stair() -> void:
	for t in Interiors.TOWER:
		var faces: PackedVector3Array = (ObjectLibrary.shape_of({"t": t, "st": {}})[0] as ConcavePolygonShape3D).get_faces()
		var fs := Interiors.flights(t)
		var ls := Interiors.landings(t)
		var top: float = Interiors.BOX[t][4]
		check(fs.size() == 4 and ls.size() == 3, "%s: four flights and three landings" % t)
		var ok := true
		var steep := 0.0
		for i in fs.size():
			var fo: Vector3 = fs[i][0]
			var hd: Vector3 = fs[i][1]
			steep = maxf(steep, rad_to_deg(atan2(hd.y - fo.y, Vector2(hd.x - fo.x, hd.z - fo.z).length())))
			if i < 3:
				var l: Vector3 = ls[i][0]
				var nx: Vector3 = fs[i + 1][0]
				ok = ok and absf(l.y - hd.y) < 0.001 and absf(nx.y - hd.y) < 0.001
				ok = ok and Vector2(l.x - hd.x, l.z - hd.z).length() < Interiors.STAIR_W * 0.51
				ok = ok and Vector2(l.x - nx.x, l.z - nx.z).length() < Interiors.STAIR_W * 0.51
		check(ok, "%s: each flight leads onto a landing and on up the next" % t)
		check(steep < 40.0, "%s: flights are walkable (%.0f degrees)" % [t, steep])
		check(absf((fs[3][1] as Vector3).y - top) < 0.001, "%s: the stair comes out at the roof" % t)
		# Stand on the stair: there's a tread under you and nothing over your head.
		var under := true
		var head := true
		for i in fs.size():
			var fo: Vector3 = fs[i][0]
			var hd: Vector3 = fs[i][1]
			for n in 12:
				var p: Vector3 = fo.lerp(hd, (n + 0.5) / 12.0)
				under = under and absf(0.5 - _ray_hit(faces, p + Vector3(0, 0.5, 0), p + Vector3(0, -0.5, 0))) < 0.05
				for d in [Vector3.ZERO, fs[i][2] * 0.6, -fs[i][2] * 0.6]:
					var hit := _ray_hit(faces, p + d + Vector3(0, 0.1, 0), p + d + Vector3(0, 1.9, 0))
					if hit < INF:
						head = false
						printerr("  %s: flight %d hits your head at %s" % [t, i + 1, p + d])
		check(under, "%s: the treads are where the stair is drawn" % t)
		check(head, "%s: headroom all the way up" % t)
		# Past the stair head, in the corner, you turn and walk out onto the roof.
		var c: float = (Interiors.BOX[t][0] as Vector2).x - Interiors.STAIR_W * 0.5
		var corner := Vector3(-c, top + 0.5, c)
		var out := corner + Vector3(0, 0, -2.5)
		check(absf(0.5 - _ray_hit(faces, out, out - Vector3(0, 1.0, 0))) < 0.02, "%s: the roof is there to step onto" % t)
		check(_ray_hit(faces, fs[3][1] + Vector3(0, 0.5, 0), corner) == INF and _ray_hit(faces, corner, out) == INF, "%s: nothing between the stair head and the roof" % t)
		check(_ray_hit(faces, Vector3(0, top + 0.5, 0), Vector3(0, top + 0.5, 6.0)) < INF, "%s: a parapet round the roof" % t)

func test_rooms_get_stocked() -> void:
	var chunk := {"cx": 3, "cz": -2, "seed": 77, "objects": [
		{"i": 0, "t": "castle_keep", "e": 0, "p": Vector3(10, 5, 12), "r": 0.7, "s": 1.0, "st": {"tier": 3}},
		{"i": 1, "t": "cottage", "e": 0, "p": Vector3(30, 4, 30), "r": -1.2, "s": 1.0, "st": {}},
		{"i": 2, "t": "hab_dome", "e": 2, "p": Vector3(50, 6, 8), "r": 2.0, "s": 1.0, "st": {}},
		{"i": 3, "t": "crypt_keep", "e": 1, "p": Vector3(5, 5, 50), "r": 0.0, "s": 1.0, "st": {"gone": true}},
		{"i": 4, "t": "oak", "e": 0, "p": Vector3(20, 4, 20), "r": 0.0, "s": 1.0, "st": {}},
	]}
	check(Interiors.stock(chunk), "rooms are stocked")
	var objs: Array = chunk["objects"]
	check(objs.size() == 8, "one cache per loot spot, none in a ruin (%d objects)" % objs.size())
	var kinds := []
	for i in range(5, objs.size()):
		var c: Dictionary = objs[i]
		kinds.append(c["t"])
		check(c["i"] == i and not (c["st"]["loot"] as Array).is_empty() and not c["st"]["opened"], "cache %d is indexed and full" % i)
		var host: Dictionary = objs[0] if c["st"]["inside"] == "castle_keep" else (objs[1] if c["st"]["inside"] == "cottage" else objs[2])
		var local: Vector3 = (Basis(Vector3.UP, host["r"]).inverse() * ((c["p"] as Vector3) - (host["p"] as Vector3)))
		var spot: Vector3 = Interiors.LOOT[c["st"]["inside"]][0][0]
		check(Vector2(local.x - spot.x, local.z - spot.z).length() < 0.01, "cache %d stands at its spot" % i)
		check(absf((c["p"] as Vector3).y - (host["p"] as Vector3).y - spot.y) < 0.01, "cache %d stands on the floor (%.2f)" % [i, (c["p"] as Vector3).y - (host["p"] as Vector3).y])
	check(kinds == ["chest", "chest", "supply_pod"], "each era's cache (%s)" % [kinds])
	check(objs[0]["st"]["stocked"] and not objs[3]["st"].has("stocked") and not objs[4]["st"].has("stocked"), "only standing rooms are marked")
	var before := var_to_bytes(objs)
	check(not Interiors.stock(chunk) and var_to_bytes(chunk["objects"]) == before, "stocking twice changes nothing")
	# The same chunk always rolls the same loot.
	var again := {"cx": 3, "cz": -2, "seed": 77, "objects": [chunk["objects"][0].duplicate(true)]}
	again["objects"][0]["st"].erase("stocked")
	Interiors.stock(again)
	check(var_to_bytes(again["objects"][1]["st"]["loot"]) == var_to_bytes(objs[5]["st"]["loot"]), "loot is deterministic")
	# Chunks saved before rooms had loot get it when next loaded.
	var s := _tmp_store("rooms")
	var old := {"cx": 0, "cz": 0, "seed": 5, "heights": PackedFloat32Array(), "objects": [
		{"i": 0, "t": "townhouse", "e": 0, "p": Vector3(20, 3, 20), "r": 0.0, "s": 1.0, "st": {}}]}
	s.save_chunk(old)
	var loaded := s.get_or_create_chunk(ChunkGenerator.new(5), 0, 0)
	check(loaded["objects"].size() == 2 and loaded["objects"][1]["t"] == "chest", "an old chunk's house gets its chest")
	check((s.load_chunk(0, 0) as Dictionary)["objects"].size() == 2, "and keeps it saved")

static func _ray_hit(faces: PackedVector3Array, a: Vector3, b: Vector3) -> float:
	var best := INF
	for i in range(0, faces.size(), 3):
		var hit = Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			best = minf(best, a.distance_to(hit))
	return best

func test_landmarks() -> void:
	# Each landmark mesh builds, about the size of its collision box.
	for t in Landmark.LABELS:
		var m := ObjectLibrary.get_mesh(t)
		var bb := m.get_aabb()
		var sz: Vector3 = Landmark.SIZE[t]
		check(m.get_surface_count() >= 2 and bb.size.x < sz.x * 2.0 + 1.0 and bb.size.z < sz.z * 2.0 + 1.0 and bb.size.y > 0.5,
			"%s builds (%d surfaces, %s)" % [t, m.get_surface_count(), bb.size])
		check(ObjectLibrary.kind(t) == "structure" and ObjectLibrary.label(t) == Landmark.LABELS[t], "%s is a labelled structure" % t)
	# The heart of a landform region holds its landmark and a rich cache.
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(2024)
	var found := {}
	for iz in range(-25, 25):
		for ix in range(-25, 25):
			var lf := g.field.site_landform(ix, iz)
			if not Landmark.BY_LANDFORM.has(lf) or found.has(lf):
				continue
			var p := g.field.site_pos(ix, iz)
			if g.field.landform_weights(p.x, p.y)[lf] < 0.9 or not g.settlements_near(p.x - 40, p.y - 40, p.x + 40, p.y + 40).is_empty():
				continue
			var ch := g.generate(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))
			var want: String = Landmark.BY_LANDFORM[lf][0]
			var mark := {}
			var cache := {}
			for o in ch["objects"]:
				if o["t"] == want or (want == "caravan" and o["t"] == "wagon"):
					mark = o
				if o["st"].has("landmark"):
					cache = o
			found[lf] = true
			check(not mark.is_empty(), "%s region holds its %s" % [WorldField.LANDFORM_NAMES[lf], want])
			check(not cache.is_empty() and (cache["st"]["loot"] as Array).size() >= 4, "%s's cache is rich (%s)" % [want, cache.get("st", {}).get("loot", []).size()])
			if not mark.is_empty() and Landmark.BY_LANDFORM[lf][1] == "high":
				var h: float = mark["p"].y
				check(h >= ChunkGenerator.height_at(ch, 32.0, 32.0) - 0.5 or h > g.field.shape(p.x, p.y).x + 5.0, "%s stands up high (%.1f)" % [want, h])
	check(found.size() >= 8, "landmarks found in %d landforms" % found.size())

func test_all_eras_appear_with_transitions() -> void:
	var f := WorldField.new(99)
	var seen := [0, 0, 0]
	var transitions := 0
	var last := -1
	for i in 2000:
		var w := f.era_weights(i * 10.0, 0.0)
		var d := WorldField.dominant(w)
		seen[d] += 1
		if last != -1 and d != last:
			transitions += 1
		last = d
	for e in Eras.COUNT:
		check(seen[e] > 0, "era %s appears on a 20 km walk" % Eras.NAMES[e])
	check(transitions >= 10, "walk crosses era borders (%d)" % transitions)

func test_objects_are_valid() -> void:
	var g := ChunkGenerator.new(4242)
	var total := 0
	var settlement_found := false
	for cz in range(-6, 6):
		for cx in range(-6, 6):
			var c := g.generate(cx, cz)
			for o in c["objects"]:
				total += 1
				var p: Vector3 = o["p"]
				check(p.x >= 0 and p.x <= 64 and p.z >= 0 and p.z <= 64, "object inside chunk")
				if o["t"] == "trader":
					settlement_found = true
					check(o["st"]["stock"] is Dictionary, "trader has stock")
			for k in c["objects"].size():
				check(c["objects"][k]["i"] == k, "object ids are sequential")
	check(total > 300, "plenty of objects (%d)" % total)
	check(settlement_found, "at least one settlement in 768 m square")

# --- Persistence ----------------------------------------------------------------

func test_first_sight_snapshot_is_permanent() -> void:
	var s := _tmp_store("snapshot")
	var g := ChunkGenerator.new(1234)
	check(not s.has_chunk(2, 3), "chunk absent before visit")
	var c := s.get_or_create_chunk(g, 2, 3)
	check(s.has_chunk(2, 3), "chunk saved on first generation")
	# The player changes the world.
	var obj: Dictionary = c["objects"][0]
	obj["st"]["gone"] = true
	c["heights"][100] -= 2.5
	var dug: float = c["heights"][100]
	s.save_chunk(c)
	# Even a completely different generator (a future game version) must not alter it.
	var other_gen := ChunkGenerator.new(999999)
	var again := s.get_or_create_chunk(other_gen, 2, 3)
	check(again["objects"][0]["st"].get("gone", false), "removed object stays removed")
	check(absf(again["heights"][100] - dug) < 0.0001, "dug terrain stays dug")
	check(again["objects"].size() == c["objects"].size(), "object identities preserved")
	check(var_to_bytes(again["objects"][1]) == var_to_bytes(c["objects"][1]), "untouched objects identical")

func test_cache_loot_is_frozen() -> void:
	var s := _tmp_store("loot")
	var g := ChunkGenerator.new(55)
	var found := {}
	for cz in range(0, 12):
		for cx in range(0, 12):
			var c := s.get_or_create_chunk(g, cx, cz)
			for o in c["objects"]:
				if o["st"].has("loot"):
					found = {"cx": cx, "cz": cz, "i": o["i"], "loot": o["st"]["loot"]}
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	check(not found.is_empty(), "found a cache")
	if found.is_empty():
		return
	var reloaded = s.load_chunk(found["cx"], found["cz"])
	check(var_to_bytes(reloaded["objects"][found["i"]]["st"]["loot"]) == var_to_bytes(found["loot"]), "loot identical on reload")

func test_atomic_write_and_text_roundtrip() -> void:
	var s := _tmp_store("atomic")
	var data := {"pos": Vector3(1.5, 2.0, -3.25), "money": 42, "chunk": Vector2i(-1, 7), "list": [1, "a", 2.5]}
	check(WorldStore.write_var(s.root.path_join("p.dat"), data), "write ok")
	check(not FileAccess.file_exists(s.root.path_join("p.dat.tmp")), "no temp file left behind")
	var back = WorldStore.read_var(s.root.path_join("p.dat"))
	check(back is Dictionary and back["pos"] == data["pos"] and back["chunk"] == data["chunk"] and back["money"] is int, "variant types survive")

func test_edge_stitching_prefers_existing_neighbour() -> void:
	var s := _tmp_store("stitch")
	var g := ChunkGenerator.new(8)
	var a := s.get_or_create_chunk(g, 0, 0)
	var R := ChunkGenerator.RES
	for k in R:
		a["heights"][k * R + R - 1] += 5.0 # player dug/raised the east edge
	s.save_chunk(a)
	var b := s.get_or_create_chunk(g, 1, 0)
	var ok := true
	for k in R:
		if absf(b["heights"][k * R] - a["heights"][k * R + R - 1]) > 0.0001:
			ok = false
	check(ok, "new chunk adopts neighbour's edited edge")

# --- Items and economy ------------------------------------------------------------

func test_inventory_stacks_and_provenance() -> void:
	var inv := Inventory.new()
	var o := {"how": "mined", "era": 0, "chunk": Vector2i(4, 2)}
	inv.add(ItemDB.make("iron_ore", 3, 1.0, o))
	inv.add(ItemDB.make("iron_ore", 2, 1.02, o))
	check(inv.count("iron_ore") == 5, "stacks merge")
	inv.add(ItemDB.make("pickaxe_iron", 1, 1.0, o))
	inv.add(ItemDB.make("pickaxe_iron", 1, 1.0, o))
	var uids := {}
	for sl in inv.slots:
		if sl != null:
			uids[sl["uid"]] = true
	check(uids.size() == 3, "unique uids")
	var restored := Inventory.new()
	restored.from_data(str_to_var(var_to_str(inv.to_data())))
	check(restored.count("iron_ore") == 5 and restored.count("pickaxe_iron") == 2, "inventory round-trips through save text")
	check(restored.slots[0]["origin"]["chunk"] == Vector2i(4, 2), "provenance survives")
	check(restored.next_uid == inv.next_uid, "uid counter persists")

func test_crafting() -> void:
	var inv := Inventory.new()
	var o := {"how": "mined", "era": 0}
	inv.add(ItemDB.make("iron_ore", 4, 1.0, o))
	var ingot: Dictionary = Recipes.LIST.filter(func(r): return r["out"] == "iron_ingot")[0]
	check(Recipes.craft(inv, ingot, o), "craft ingot")
	check(Recipes.craft(inv, ingot, o), "craft second ingot")
	check(not Recipes.craft(inv, ingot, o), "out of ore")
	check(inv.count("iron_ingot") == 2 and inv.count("iron_ore") == 0, "inputs consumed")

func test_stacks_merge_across_quality_and_keep_sources() -> void:
	var inv := Inventory.new()
	var a := {"how": "chopped", "era": 0, "chunk": Vector2i(1, 1)}
	var b := {"how": "bought", "era": 1, "chunk": Vector2i(7, -2)}
	inv.add(ItemDB.make("wood", 4, 0.8, a))
	inv.add(ItemDB.make("wood", 6, 1.3, b))
	check(inv.slots_of("wood") == 1 and inv.count("wood") == 10, "different qualities share one stack")
	var st: Dictionary = inv.slots[0]
	check(absf(st["quality"] - 1.1) < 0.02, "stack quality is weighted (%.2f)" % st["quality"])
	check(Inventory.sources_of(st).size() == 2, "stack remembers both sources")
	var part := inv.remove_at(0, 5)
	check(part["qty"] == 5 and part["sources"][0][0]["how"] == "bought", "split takes newest source")
	check(Inventory.sources_of(inv.slots[0]).size() == 2 and inv.count("wood") == 5, "rest keeps older sources")
	# Old saves with one stack per quality merge on load.
	var old := {"slots": [ItemDB.make("wood", 2, 0.9, a), ItemDB.make("wood", 3, 1.2, b)], "next_uid": 3}
	var r := Inventory.new()
	r.from_data(old)
	check(r.slots_of("wood") == 1 and r.count("wood") == 5, "old split stacks merge on load")
	# Swapping onto a same-type stack merges.
	var m := Inventory.new()
	m.slots[0] = ItemDB.make("stone", 2, 1.0, a)
	m.slots[3] = ItemDB.make("stone", 4, 1.0, b)
	m.swap(0, 3)
	check(m.slots[0] == null and m.slots[3]["qty"] == 6, "dropping a stack on its twin merges")

func test_batch_crafting() -> void:
	var inv := Inventory.new()
	var o := {"how": "chopped", "era": 0}
	inv.add(ItemDB.make("wood", 37, 1.0, o))
	var planks: Dictionary = Recipes.LIST.filter(func(r): return r["out"] == "planks" and r["in"].has("wood"))[0]
	check(Recipes.max_crafts(inv, planks) == 37, "max crafts")
	check(Recipes.craft_many(inv, planks, o, 10) == 10 and inv.count("planks") == 20, "craft x10")
	check(Recipes.craft_many(inv, planks, o, 100) == 27 and inv.count("wood") == 0, "x100 clamps to what you have")
	check(inv.count("planks") == 74 and inv.slots_of("planks") == 1, "batch output is one stack")
	inv.add(ItemDB.make("iron_ingot", 20, 1.0, o))
	var pick: Dictionary = Recipes.LIST.filter(func(r): return r["out"] == "pickaxe_iron")[0]
	check(Recipes.craft_many(inv, pick, o, -1) == 10 and inv.count("pickaxe_iron") == 10, "craft all tools, one slot each")

func test_craft_tabs() -> void:
	for r in Recipes.LIST:
		var tabs := ItemDB.craft_tabs(r["out"])
		check(not tabs.is_empty() and tabs.all(func(t): return ItemDB.CRAFT_TABS.has(t)), "%s sorts into known tabs (%s)" % [r["out"], tabs])
	for t in ItemDB.ITEMS:
		if ItemDB.ITEMS[t].has("cat"):
			check(ItemDB.CRAFT_TABS.has(ItemDB.ITEMS[t]["cat"]), "%s has a known cat" % t)
	for pair in [["bolt", "Ammo"], ["arrow", "Ammo"], ["rounds", "Ammo"], ["helm_iron", "Armour"], ["shield_wood", "Armour"],
			["sword_iron", "Weapons"], ["crossbow", "Weapons"], ["jet_fuel", "Fuel"], ["cooked_meat", "Food"],
			["health_potion", "Medicine"], ["torch", "Lights"], ["speeder", "Vehicles"], ["lockpick", "Tools"],
			["iron_ingot", "Materials"], ["forge", "Stations"], ["wall_stone", "Building"], ["chair", "Furniture"]]:
		check(ItemDB.craft_tab(pair[0]) == pair[1], "%s is under %s (got %s)" % [pair[0], pair[1], ItemDB.craft_tab(pair[0])])
	check(ItemDB.craft_tabs("power_cell") == ["Materials", "Ammo"], "power cells also show under Ammo")
	check(ItemDB.craft_tabs("lantern") == ["Furniture", "Lights"], "lanterns also show under Lights")

func test_build_pieces() -> void:
	for id in BuildCatalog.PIECES:
		var m := BuildCatalog.mesh(id)
		check(m != null and m.get_surface_count() > 0 and m.get_aabb().size.length() > 0.3, "piece mesh %s (%s)" % [id, m.get_aabb().size if m else "null"])
		check(BuildCatalog.shape(BuildCatalog.PREFIX + id)[0] is Shape3D, "piece collision %s" % id)
		check(ItemDB.has(id) and ItemDB.def(id)["stack"], "piece %s is a stackable item" % id)
		check(Recipes.LIST.any(func(r): return r["out"] == id), "piece %s has a recipe" % id)
	for r in Recipes.LIST:
		check(ItemDB.has(r["out"]), "recipe output %s exists" % r["out"])
		if r.has("at"):
			check(BuildCatalog.PIECES.values().any(func(d): return d.get("station") == r["at"]), "station %s is buildable" % r["at"])
	# Village walls sit on cell edges, along x, at the storey of the piece they join.
	var w := BuildCatalog.snap("wall_plaster", Vector3(4.3, 0.2, 7.1), 0.0, 0, Vector3(5, 0, 7), false)
	check(w["pos"].is_equal_approx(Vector3(4, 0, 7)) and is_equal_approx(w["yaw"], PI * 0.5), "wall snaps to the x edge (%s)" % w["pos"])
	var w2 := BuildCatalog.snap("wall_plaster", Vector3(5.1, 3.3, 7.9), 0.0, 0, Vector3(5, 0, 7), false)
	check(w2["pos"].is_equal_approx(Vector3(5, 3, 8)) and is_equal_approx(w2["yaw"], 0.0), "aiming at a wall top builds the next storey (%s)" % w2["pos"])
	var f := BuildCatalog.snap("platform", Vector3(-1.0, 2.0, 9.5), 0.0, 0)
	check(f["pos"].is_equal_approx(Vector3(-2, 2, 10)), "sci-fi platforms use 4 m cells (%s)" % f["pos"])
	var rv := BuildCatalog.snap("roof_small", Vector3(3.2, 3.0, 4.9), 0.0, 0, Vector3(3, 0, 5), false)
	check(rv["pos"].is_equal_approx(Vector3(4, 3, 4)), "small roof centres on a grid corner (%s)" % rv["pos"])
	var g := BuildCatalog.snap("floor_wood", Vector3(1.0, -0.8, 1.0), 0.0, 0, Vector3(1, 0, 1), true)
	check(is_equal_approx(g["pos"].y, 0.0), "ground below a house keeps the floor level")
	# A floor aimed at the side of a wall goes on top of it, in the cell on your side.
	var fw := BuildCatalog.snap("floor_wood", Vector3(4.05, 1.5, 7.3), 0.0, 0, Vector3(4, 0, 7), false, {"hit_mode": "wall"})
	check(fw["pos"].is_equal_approx(Vector3(5, 3, 7)), "floor aimed at a wall sits on its top (%s)" % fw["pos"])
	var rw := BuildCatalog.snap("roof_small", Vector3(4.05, 2.9, 7.3), 0.0, 0, Vector3(4, 0, 7), false, {"hit_mode": "wall"})
	check(is_equal_approx(rw["pos"].y, 3.0), "roof aimed at a wall sits on its top (%s)" % rw["pos"])
	# Raise / lower by storeys, and free placement off the grid.
	var up := BuildCatalog.snap("floor_wood", Vector3(1.0, 0.2, 1.0), 0.0, 0, Vector3(1, 0, 1), true, {"lift": 2})
	check(is_equal_approx(up["pos"].y, 6.0), "raise lifts a piece two storeys (%s)" % up["pos"])
	var dn := BuildCatalog.snap("floor_wood", Vector3(1.0, 3.2, 1.0), 0.0, 0, Vector3(1, 0, 1), true, {"lift": -1})
	check(is_equal_approx(dn["pos"].y, 0.0), "lower drops a piece a storey (%s)" % dn["pos"])
	var fr := BuildCatalog.snap("wall_plaster", Vector3(1.37, 0.6, 2.11), 0.0, 1, null, true, {"free": true, "lift": 1})
	check(fr["pos"].is_equal_approx(Vector3(1.25, 0.75, 2.0)) and is_equal_approx(fr["yaw"], PI + PI / 12.0), "grid off places freely (%s, %.2f)" % [fr["pos"], fr["yaw"]])
	# Taking a piece down refunds it.
	var o := {"t": "b:wall_stone", "s": 1.0, "st": {}}
	var res := Durability.hit(o, 1000.0)
	check(res["destroyed"] and res["items"] == [["wall_stone", 1]], "destroyed piece yields itself")

func test_economy_arbitrage_and_demand() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var medieval := Economy.new_trader(Eras.MEDIEVAL, r)
	var cell := {"type": "power_cell", "quality": 1.0}
	var ore := {"type": "iron_ore", "quality": 1.0}
	var p_cell := Economy.buy_price(medieval, cell)
	check(p_cell > ItemDB.def("power_cell")["value"], "foreign goods sell at a premium (%d)" % p_cell)
	check(Economy.buy_price(medieval, ore) < ItemDB.def("iron_ore")["value"], "native goods discounted")
	Economy.record_sale_to_trader(medieval, "power_cell", 5)
	var after := Economy.buy_price(medieval, cell)
	check(after < p_cell, "selling lowers demand (%d -> %d)" % [p_cell, after])
	Economy.tick(medieval, 10.0)
	check(Economy.buy_price(medieval, cell) == p_cell, "demand recovers over days")
	var s1 = r.randi()
	var t1 := {"era": 0, "restock_seed": 77, "stock": {}, "demand": {}, "last_day": 0.0, "foreign": 2.0}
	var t2 := t1.duplicate(true)
	Economy.tick(t1, 7.0)
	Economy.tick(t2, 3.5)
	Economy.tick(t2, 7.0)
	check(t1["stock"] == t2["stock"], "restock is deterministic regardless of visit pattern")

# --- AI and NPCs -----------------------------------------------------------------

func test_ai_request_formats() -> void:
	var c := {"format": "openai", "base_url": "http://127.0.0.1:8080/v1/", "api_key": "k", "model": "m",
		"max_tokens": 100, "temperature": 0.5, "json_mode": true}
	var r := AIServiceShim.build(c)
	check(r["url"] == "http://127.0.0.1:8080/v1/chat/completions", "openai url")
	check(Array(r["headers"]).has("Authorization: Bearer k"), "openai auth header")
	var b = JSON.parse_string(r["body"])
	check(b["messages"][0]["role"] == "system" and b["model"] == "m", "openai body has system + model")
	check(b["response_format"]["type"] == "json_object", "json mode requested")
	c["format"] = "anthropic"
	c["model"] = "claude-haiku-5-5"
	r = AIServiceShim.build(c)
	check(r["url"] == "http://127.0.0.1:8080/v1/messages", "anthropic url")
	check(Array(r["headers"]).has("x-api-key: k") and Array(r["headers"]).has("anthropic-version: 2023-06-01"), "anthropic headers")
	b = JSON.parse_string(r["body"])
	check(b["system"] == "sys" and b["messages"][0]["role"] == "user", "anthropic body shape")
	check(not b.has("temperature") and not b.has("budget_tokens"), "no unsupported sampling params")
	c["api_key"] = ""
	r = AIServiceShim.build(c)
	check(not str(r["headers"]).contains("x-api-key"), "no key header without key")

func test_ai_response_parsing() -> void:
	var S = load("res://src/ai/ai_service.gd")
	var ok: Dictionary = S.parse_response("openai", 200, '{"choices":[{"message":{"content":"hi"}}]}')
	check(ok["ok"] and ok["text"] == "hi", "openai reply")
	ok = S.parse_response("anthropic", 200, '{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"yo"}]}')
	check(ok["ok"] and ok["text"] == "yo", "anthropic reply skips thinking blocks")
	var ref: Dictionary = S.parse_response("anthropic", 200, '{"stop_reason":"refusal","content":[]}')
	check(not ref["ok"], "refusal reported as failure")
	var bad: Dictionary = S.parse_response("openai", 401, '{"error":{"message":"bad key"}}')
	check(not bad["ok"] and bad["error"].contains("bad key"), "http error message surfaced")
	var j = S.extract_json('Sure! ```json\n{"say": "a } b", "n": {"x": 1}}\n``` done')
	check(j is Dictionary and j["say"] == "a } b" and j["n"]["x"] == 1, "lenient json extraction")
	check(S.extract_json("no json here") == null, "no json -> null")
	var d: Dictionary = S.parse_decisions('{"decisions":[{"id":"a","action":"wander"},{"id":"b","action":"explode"}]}')
	check(d.has("a") and not d.has("b"), "external decisions validated against action list")

func _npc_fixture() -> Array:
	var gen := ChunkGenerator.new(777)
	var site := {}
	for ring in 12:
		var f := gen.settlements_near(-ring * 256.0, -ring * 256.0, ring * 256.0, ring * 256.0)
		if not f.is_empty():
			site = f[0]
			break
	return [gen, site]

func test_npc_generation_deterministic() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var site: Dictionary = fx[1]
	check(not site.is_empty(), "settlement found")
	var a := NPCGen.generate(777, gen, site, gen.settlement_layout(site))
	var b := NPCGen.generate(777, gen, site, gen.settlement_layout(site))
	check(var_to_bytes(a) == var_to_bytes(b), "same seed, same people")
	check(a["npcs"][0]["job"] == "trader", "first person keeps the stall")
	check(a["npcs"].size() >= 4, "settlement has residents")
	var ids := {}
	for p in a["npcs"]:
		ids[p["id"]] = true
		for k in ["friendly", "brave", "curious", "diligent", "greedy"]:
			check(p["traits"][k] >= 0.0 and p["traits"][k] <= 1.0, "trait range")
	check(ids.size() == a["npcs"].size(), "unique ids")

func test_decision_engine() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var s := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var p: Dictionary = s["npcs"][2].duplicate(true)
	p["job"] = "farmer"
	var per := {"hour": 2.0, "pos": Vector2.ZERO, "center": s["center"], "player_dist": 100.0, "noise": 0.5, "now": 0.0}
	check(DecisionEngine.decide(p, per)["action"] == "sleep", "sleeps at night")
	per["hour"] = 11.0
	var day_a: String = DecisionEngine.decide(p, per)["action"]
	check(day_a in ["work", "wander", "socialize"], "daytime activity (%s)" % day_a)
	p["rel"] = -90
	p["traits"]["brave"] = 0.05
	per["player_dist"] = 5.0
	check(DecisionEngine.decide(p, per)["action"] == "flee", "timid npc flees a hated player")
	var g: Dictionary = s["npcs"][1].duplicate(true)
	g["job"] = NPCGen.GUARD_JOBS[g["era"]]
	g["rel"] = -90
	check(DecisionEngine.decide(g, per)["action"] == "attack", "guard attacks a hated player")
	var f: Dictionary = s["npcs"][2].duplicate(true)
	f["job"] = "farmer"
	per["override"] = {"action": "follow", "until": 10.0}
	var r := DecisionEngine.decide(f, per)
	check(r["action"] == "follow" and r.get("target_player", false), "instructions override the schedule")
	for a in DecisionEngine.ACTIONS:
		check(NPCMind.TALK_ACTIONS.has(a) or a in ["idle", "wander", "work", "socialize", "sleep", "greet", "confront", "dance", "sit"] , "action known: " + a)

func test_npc_memory_and_replies() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var s := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var p: Dictionary = s["npcs"][1]
	for i in 30:
		NPCMind.remember(p, "event %d" % i)
	check(p["mem"].size() == NPCMind.MAX_MEMORIES, "memory is bounded")
	check(String(p["mem"][-1]).ends_with("event 29"), "newest memory kept")
	var a := NPCMind.apply_reply(p, s, {"say": "hi", "mood": "happy", "rel_change": 50, "action": "trade", "remember": "x"})
	check(a == "trade", "anyone can trade the goods of their work")
	check(int(p["rel"]) == 10, "relationship change clamped per exchange")
	check(p["mood"] == "happy", "mood applied")
	var t: Dictionary = s["npcs"][0]
	check(NPCMind.builtin_reply(t, s, "Can we trade?")["action"] == "trade", "built-in trader trades")
	var sys := NPCMind.system_prompt(p, s, {"held": "Iron Sword"})
	check(sys.contains(p["name"]) and sys.contains("Iron Sword") and sys.contains("JSON"), "prompt carries persona, context and format")

func test_npc_money_gifts_and_loans() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var s := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var kind: Dictionary = s["npcs"][1].duplicate(true)
	var mean: Dictionary = s["npcs"][1].duplicate(true)
	kind["id"] = "k"
	mean["id"] = "m"
	NPCSocial.ensure(kind)
	NPCSocial.ensure(mean)
	kind["purse"] = 100
	mean["purse"] = 100
	kind["traits"] = {"friendly": 0.9, "brave": 0.5, "curious": 0.5, "diligent": 0.5, "greedy": 0.1}
	mean["traits"] = {"friendly": 0.1, "brave": 0.5, "curious": 0.5, "diligent": 0.5, "greedy": 0.9}
	kind["rel"] = 40
	mean["rel"] = 0
	kind["mood"] = "calm"
	mean["mood"] = "calm"
	var kg := NPCSocial.will_give(kind, "beg")
	check(kg > 0 and kg <= 100, "a kind friend spares some Marks (%d)" % kg)
	check(NPCSocial.will_give(mean, "beg") == 0, "a greedy stranger gives nothing")
	check(NPCSocial.will_give(kind, "beg", 3) == mini(3, kg), "never more than asked")
	var lent := NPCSocial.hand_over(kind, NPCSocial.will_give(kind, "lend"), "lend")
	check(lent > 0 and int(kind["debt"]) == lent and int(kind["purse"]) == 100 - lent, "a loan leaves a debt (%d)" % lent)
	check(NPCSocial.will_give(kind, "lend") == 0, "no second loan while one is owed")
	var r := NPCSocial.receive_marks(kind, lent + 10)
	check(int(r["repaid"]) == lent and int(kind["debt"]) == 0 and int(r["rel"]) > 0, "paying back clears the debt first, the rest is a gift")
	var g := NPCSocial.receive_item(kind, ItemDB.make("helm_iron", 1, 1.0, {}))
	check(g["use"] == "wear" and kind["gear"].has("head"), "armour you give is worn")
	check(NPCSocial.receive_item(kind, ItemDB.make("bread", 1, 1.0, {}))["use"] == "eat", "food gets eaten")
	var guard: Dictionary = s["npcs"][1].duplicate(true)
	guard["id"] = "g"
	guard.erase("gear")
	guard["job"] = NPCGen.GUARD_JOBS[int(guard["era"])]
	NPCSocial.ensure(guard)
	check(guard["gear"].has("chest") and guard["gear"].has("head"), "guards start in armour")
	# Trading with anyone: their goods, their purse, their prices.
	var st := NPCSocial.shop(kind)
	check(st.has("purse") and not st["stock"].is_empty(), "villagers trade their own goods")
	var friend_price := Economy.sell_price(st, st["stock"].keys()[0])
	kind["rel"] = -30
	var st2 := NPCSocial.shop(kind)
	check(Economy.sell_price(st2, st2["stock"].keys()[0]) >= friend_price, "strangers pay more than friends")
	st2["purse"] = 7
	NPCSocial.ensure(kind)
	check(int(kind["purse"]) == 7, "what they spend trading comes out of their purse")
	NPCSocial.receive_marks(kind, 5)
	check(int(kind["purse"]) == 12 and int(kind["shop"]["purse"]) == 12, "gifts reach the shop purse too")

func test_npc_requests_and_gestures() -> void:
	check(NPCMind.requested_do("Can you hold up three fingers?") == "fingers_3", "three fingers")
	check(NPCMind.requested_do("show me your middle finger") == "finger_middle", "a named finger")
	check(NPCMind.requested_do("Dance!") == "dance", "imperative request")
	check(NPCMind.requested_do("I think so") == "", "plain talk asks for nothing")
	check(NPCMind.requested_do("please visit me") == "", "whole words only")
	check(NPCMind.requested_do("could you wink at me") == "wink", "wink")
	for n in NPCMind.doable():
		check(NPCMind.PERFORM.has(n) or not BodyLanguage.resolve(n).is_empty(), "doable: " + n)
	var two := BodyLanguage.count_fingers(2)
	check(two[1] == 0.0 and two[2] == 0.0 and two[0] == 1.0 and two[3] == 1.0, "two fingers: index and middle")
	check(BodyLanguage.count_fingers(5) == [0.0, 0.0, 0.0, 0.0, 0.0], "five fingers: open hand")
	var mid: Array = BodyLanguage.resolve("finger_middle")["fingers_r"]
	check(mid[2] == 0.0 and mid[1] == 1.0 and mid[4] == 1.0, "middle finger alone")
	check(NPCMind.reply_do({"do": "Thumbs Up"}) == "thumbs_up" and NPCMind.reply_do({"do": "teleport"}) == "", "model 'do' is validated")
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var s := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var p: Dictionary = s["npcs"][1]
	p["rel"] = 60
	p["mood"] = "happy"
	var d := NPCMind.builtin_reply(p, s, "Can you dance for me?")
	check(d.get("do", "") == "dance", "a friend dances when asked")
	p["rel"] = -20
	p["mood"] = "angry"
	check(NPCMind.builtin_reply(p, s, "Can you dance for me?").get("do", "") != "dance", "an angry person won't")

func test_speech_to_text_request() -> void:
	var svc = load("res://src/ai/ai_service.gd")
	var pcm := PackedByteArray()
	pcm.resize(3200)
	var wav: PackedByteArray = load("res://src/ai/microphone.gd").wav_bytes(pcm, 16000)
	check(wav.size() == 44 + 3200 and wav.slice(0, 4).get_string_from_ascii() == "RIFF", "wav header")
	var req: Dictionary = svc.build_transcription({"url": "http://x/v1/audio/transcriptions", "key": "k", "model": "whisper-1"}, wav, "BND")
	var body: String = (req["body"] as PackedByteArray).slice(0, 300).get_string_from_ascii()
	check(body.contains("name=\"model\"") and body.contains("whisper-1") and body.contains("filename=\"speech.wav\""), "multipart fields")
	check(String(req["headers"][0]).contains("boundary=BND") and String(req["headers"][1]) == "Authorization: Bearer k", "headers")
	check(svc.parse_transcription(200, "{\"text\": \" hello there \"}")["text"] == "hello there", "transcription parsed")
	check(not svc.parse_transcription(401, "{\"error\": {\"message\": \"bad key\"}}")["ok"], "errors reported")

func test_npc_levels() -> void:
	var old := Eras.theme
	var base := Eras.base_level
	Eras.theme = "human"
	Eras.base_level = 1
	var mk := func(job: String, x: float, id: String) -> Dictionary:
		var r := {"id": id, "name": "A B", "job": job, "era": 0, "rel": 0, "hp": 100.0, "pos": Vector3(x, 0, 0),
			"traits": {"friendly": 0.5, "brave": 0.5, "curious": 0.5, "diligent": 0.5, "greedy": 0.5}}
		NPCSocial.ensure(r)
		return r
	var far: Dictionary = mk.call("farmer", 3000.0, "f1") # zone 21
	var guard: Dictionary = mk.call("guard", 3000.0, "g1")
	var near: Dictionary = mk.call("farmer", 10.0, "f2")
	check(NPCSocial.level(far) >= 19 and NPCSocial.level(far) <= 21, "townsfolk sit at their zone's level (%d)" % NPCSocial.level(far))
	check(NPCSocial.level(guard) > NPCSocial.level(far), "guards outrank the townsfolk around them")
	check(NPCSocial.level(near) == 1, "near the start people are level 1")
	check(is_equal_approx(float(far["hp"]), NPCSocial.max_hp(far)) and NPCSocial.max_hp(far) > 300.0, "health grows with level")
	check(NPCSocial.hit_mult(guard) > 1.8, "high level guards hit harder")
	var hurt := {"id": "h1", "name": "A B", "job": "farmer", "era": 0, "hp": 50.0, "pos": Vector3(3000, 0, 0),
		"traits": {"friendly": 0.5, "brave": 0.5, "curious": 0.5, "diligent": 0.5, "greedy": 0.5}}
	NPCSocial.ensure(hurt)
	check(is_equal_approx(float(hurt["hp"]) / NPCSocial.max_hp(hurt), 0.5), "an old save keeps how hurt they were")
	var lv := NPCSocial.level(far)
	NPCSocial.ensure(far)
	check(NPCSocial.level(far) == lv and is_equal_approx(float(far["hp"]), NPCSocial.max_hp(far)), "the level is set once")
	Eras.theme = old
	Eras.base_level = base

func test_voice_and_quick_replies() -> void:
	var rec := {"id": "q1", "name": "Edda Thorne", "job": "farmer", "era": 0, "rel": 30, "mood": "calm", "age": 40,
		"body": {"female": true}, "traits": {"friendly": 0.8, "brave": 0.5, "curious": 0.6, "diligent": 0.6, "greedy": 0.2}}
	check(Interject.pick_local(rec, "Can you dance for me?") == "yes", "a request they'd do gets a quick yes")
	var cross := rec.duplicate(true)
	cross["mood"] = "angry"
	check(Interject.pick_local(cross, "Can you dance for me?") == "no", "an angry person refuses at once")
	check(Interject.pick_local(rec, "What do you think about the old ruins up on the hill?") == "think", "a real question gets a thinking pause")
	check(Interject.pick_local(rec, "hello") == "greet", "greeting")
	check(Interject.pick_local(rec, "thank you") == "thanks", "thanks")
	check(Interject.pick_local(rec, "you are an idiot") == "offended", "rudeness")
	var shy := rec.duplicate(true)
	shy["traits"] = {"friendly": 0.1, "brave": 0.5, "curious": 0.1, "diligent": 0.5, "greedy": 0.5}
	check(Interject.pick_local(shy, "nice weather") == "none", "quiet people just wait")
	check(Interject.line(rec, "think") == Interject.line(rec, "think"), "each person keeps their phrasing")
	check(Interject.line(rec, "none") == "", "silence says nothing")
	check(Interject.parse_pick("{\"pick\": \"no\"}") == "no", "service pick parsed")
	check(Interject.parse_pick("{\"pick\": \"sing a song\"}") == "", "only pre-approved kinds are accepted")
	check(Interject.request_body(rec, "hi", "greet")["lines"]["think"] == Interject.line(rec, "think"), "service sees the actual lines")
	var svc = load("res://src/ai/ai_service.gd")
	var req: Dictionary = svc.build_speech({"url": "https://api.openai.com/v1/audio/speech", "key": "k", "model": "gpt-4o-mini-tts"}, "Hello.", {"voice": "coral", "instructions": "Scottish", "speed": 1.1})
	var body = JSON.parse_string(req["body"])
	check(body["voice"] == "coral" and body["instructions"] == "Scottish" and body["response_format"] == "pcm", "speech request for gpt-4o-mini-tts")
	check(not body.has("speed"), "no speed with directions")
	check(req["headers"].has("Authorization: Bearer k"), "voice key sent")
	body = JSON.parse_string(svc.build_speech({"url": "http://127.0.0.1:8880/v1/audio/speech", "key": "", "model": "kokoro"}, "Hi", {"voice": "bf_emma", "instructions": "x", "speed": 1.1})["body"])
	check(not body.has("instructions") and is_equal_approx(float(body["speed"]), 1.1), "kokoro gets speed, not directions")
	var pcm := PackedByteArray()
	pcm.resize(4800)
	var a: AudioStream = svc.audio_from_bytes(pcm)
	check(a is AudioStreamWAV and (a as AudioStreamWAV).mix_rate == 24000, "raw PCM plays at 24 kHz")
	var wav := Microphone.wav_bytes(pcm, 16000)
	wav.encode_u32(40, 0xFFFFFFFF) # streamed WAVs carry bogus sizes
	a = svc.audio_from_bytes(wav)
	check(a is AudioStreamWAV and (a as AudioStreamWAV).mix_rate == 16000 and (a as AudioStreamWAV).data.size() == 4800, "WAV with a bogus size")
	check(svc.parse_windows_stt("junk\nOK: hello there\n")["text"] == "hello there", "Windows recogniser output")
	check(not svc.parse_windows_stt("ERR:no recogniser")["ok"], "Windows recogniser error")
	check(not svc.parse_windows_stt("OK:")["ok"], "Windows recogniser heard nothing")
	var loud := PackedByteArray()
	loud.resize(800)
	check(Microphone.peak(loud) == 0.0, "silence has no peak")
	loud.encode_s16(400, -16384)
	check(is_equal_approx(Microphone.peak(loud), 0.5), "peak level")

func test_outfits() -> void:
	if not HumanModel.available():
		return
	var b := {"height": 1.0, "build": 1.0, "female": false, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}
	for era in 3:
		var h := HumanModel.new()
		root.add_child(h)
		h.build(b, era, "priest")
		var cl: MeshInstance3D = h.get_node_or_null(NodePath(String(h.get_path_to(h.skeleton)) + "/Clothes"))
		check(cl != null and cl.mesh.get_surface_count() == 1 and cl.skin != null, "era %d: clothes are a skinned mesh" % era)
		h.wear({"head": ItemDB.make("helm_iron", 1, 1.0, {}), "chest": ItemDB.make("mail_iron", 1, 1.0, {}), "shield": ItemDB.make("shield_wood", 1, 1.0, {})})
		var ar: MeshInstance3D = h.get_node_or_null(NodePath(String(h.get_path_to(h.skeleton)) + "/Armour"))
		check(ar != null and ar.mesh.get_surface_count() == 1, "era %d: armour drawn" % era)
		check(h.gesture("fingers_2") and h.gesture("wink") and not h.gesture("teleport"), "gestures play")
		h.free()

## A hand holding a tool closes round it: the handle goes through the curled fingers,
## on the palm side of the knuckles, and picks and hammers strike with their head ahead.
## Walk, jog and sprint are blended so the blended stride over the blended cycle is the
## speed the body moves: planted feet don't skate.
func test_gaits() -> void:
	if not HumanModel.available():
		return
	var lib := HumanModel.library()
	var gait := {}
	for g in HumanAnimator.GAITS:
		var a := lib.get_animation(g)
		check(float(a.get_meta("speed", 0.0)) > 0.5 and a.has_meta("phase"), "%s knows how fast it travels (%.2f m/s)" % [g, float(a.get_meta("speed", 0.0))])
		gait[g] = {"speed": float(a.get_meta("speed", 1.0)), "len": a.length, "phase": float(a.get_meta("phase", 0.0))}
	var worst := 0.0
	for i in 70:
		var v := 0.6 + i * 0.15
		var r := HumanAnimator.solve(v, gait)
		var stride := 0.0
		var wsum := 0.0
		for k in 3:
			var g: String = HumanAnimator.GAITS[k]
			stride += float(r["w"][k]) * float(gait[g]["speed"]) * float(gait[g]["len"])
			wsum += float(r["w"][k])
		check(is_equal_approx(wsum, 1.0), "gait weights sum to one at %.2f m/s" % v)
		worst = maxf(worst, absf(stride / float(r["cycle"]) - v) / v)
	check(worst < 0.01, "blended gaits cover the ground at the body's speed (worst %.1f%%)" % (worst * 100.0))
	var h := HumanModel.new()
	root.add_child(h)
	h.build(Player.LOOK, Eras.MEDIEVAL, "")
	check(h.anim is AnimationTree and h.ik != null, "people animate through a blend tree with IK")
	h.play("jog")
	h.play_once("hit")
	check(h.busy(), "a one-shot plays")
	h.pose("death", true)
	h.advance(0.1)
	check(h.animator.state() == "death", "posed bodies hold their pose")
	h.free()

func test_tool_grip() -> void:
	if not HumanModel.available():
		return
	var h := HumanModel.new()
	root.add_child(h)
	h.build(Player.LOOK, Eras.MEDIEVAL, "")
	var sk := h.skeleton
	var hole := HumanModel.fist_hole(sk)
	var inv := sk.get_bone_global_rest(sk.find_bone("hand_r")).affine_inverse()
	var up := (sk.get_bone_global_rest(sk.find_bone("Head")).origin - sk.get_bone_global_rest(sk.find_bone("pelvis")).origin).normalized()
	var palm := (sk.get_bone_global_rest(sk.find_bone("hand_r")).basis.inverse() * -up).normalized()
	var knuckle := inv * sk.get_bone_global_rest(sk.find_bone("middle_01_r")).origin
	check(hole != Vector3.INF and (hole - knuckle).dot(palm) > 0.01, "the fist's hole is on the palm side of the knuckles (%s)" % [hole - knuckle])
	check(hole.distance_to(knuckle) < 0.07, "and close to the hand (%.3f m)" % hole.distance_to(knuckle))
	var prop := Viewmodel.prop_for("pickaxe_iron")
	h.hold(prop)
	check(h.gestures.grip_r == HumanModel.GRIP, "holding a tool curls the fingers")
	var xf := HumanModel.grip_transform(sk, prop, 1.0)
	var axis := xf.basis.y.normalized()
	var off := hole - xf.origin
	check((off - axis * off.dot(axis)).length() < 0.005, "the handle runs through the fist")
	h.hold(null)
	check(h.gestures.grip_r.is_empty(), "an empty hand opens")
	h.free()
	check(Viewmodel._strike_axis("pickaxe_iron") == Vector3.RIGHT and Viewmodel._strike_axis("hammer") == Vector3.RIGHT, "a pick's point and a hammer's face lead")
	check(Viewmodel._strike_axis("axe_iron") == Vector3.FORWARD and Viewmodel._strike_axis("sword_iron") == Vector3.ZERO, "an axe's edge leads; a sword isn't turned")

## Hearths, campfires and torches burn with Ben's fire flipbook.
func test_fires() -> void:
	check(ResourceLoader.exists(FireFx.SHEET), "the fire flipbook is in the game")
	var f := Interiors.fires("cottage")
	check(f.size() >= 1 and absf((f[0][0] as Vector3).x - KitHouse.hearth_x("cottage")) < 0.01, "a cottage's fire burns in its hearth")
	var tower := Interiors.fires("castle_tower")
	check(tower.size() == 10 and tower.all(func(e): return float(e[1]) < 0.5), "a tower has no hearth, but its wall torches and chandelier burn")
	var keep := Interiors.fires("castle_keep")
	var torches := keep.filter(func(e): return float(e[1]) > 0.3)
	var candles := keep.filter(func(e): return float(e[1]) < 0.1)
	check(torches.size() == 3 and candles.size() == 11, "a keep's wall torches, chandelier and candlestick burn (%d torches, %d candles)" % [torches.size(), candles.size()])
	check(Interiors.fires("crypt_keep").size() == 17, "a crypt's candle stands and candles burn")
	var tf := FireFx.prop_flames([["props/Torch_Metal", 90, Vector3(1, 2, 3), 1.0]])
	check(tf.size() == 1 and (tf[0][0] as Vector3).is_equal_approx(Vector3(1.27, 2.34, 3.0)), "a wall torch's flame turns with it to stand in its cup")
	check(f.size() > 1 and f.slice(1).all(func(e): return float(e[1]) < 0.1), "a cottage's candles burn besides its hearth")
	check(float(BuildCatalog.def("campfire").get("fire", 0.0)) > 0.5, "a campfire you build has flames")
	var ck := MeshKit.new(1)
	BuildCatalog._proc(ck, "campfire")
	var cmesh := ck.commit(Materials.get_mat)
	var cmats := []
	for i in cmesh.get_surface_count():
		cmats.append(cmesh.surface_get_material(i))
	check(Materials.get_mat("river_stone") in cmats and Materials.get_mat("char") in cmats and Materials.get_mat("glow_warm") not in cmats, "a campfire is river stones round charred logs, with no glowing ball")
	check(cmesh.get_aabb().size.x < 1.3 and cmesh.get_aabb().size.y < 0.75, "a campfire's stones are small and its logs lean together low (%s)" % cmesh.get_aabb().size)
	var fll := FlickerLight.new()
	check(fll is OmniLight3D, "firelight is an omni light that wavers")
	fll.free()
	var fl := FireFx.flame(1.0)
	var cards := fl.find_children("*", "MeshInstance3D", true, false)
	check(cards.size() == 2 and (cards[0] as MeshInstance3D).material_override == FireFx.material(), "a flame is two cards sharing the fire material")
	fl.free()
	var torch := Viewmodel.prop_for("torch")
	check(torch.find_child("Flame", true, false) != null, "a torch in hand burns")
	check(torch.find_child("Sparks", true, false) is CPUParticles3D and torch.find_child("Smoke", true, false) is CPUParticles3D, "a torch throws sparks and smoke")
	check(not (torch.find_child("Sparks", true, false) as CPUParticles3D).local_coords, "a swung torch leaves its sparks behind")
	check((torch.get_child(0) as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a held torch doesn't shadow its own stick from its flame")
	torch.free()
	var sw := FireFx.swirl(WorldPortal.DOOR * 2.0)
	check(ResourceLoader.exists("res://assets/textures/fx/portal_swirl.png") and (sw.material_override as ShaderMaterial).get_shader_parameter("tex") != null, "a portal's door turns Ben's magic swirl")
	sw.free()
	var em := FireFx.embers(1.0, false)
	check(em.find_child("Smoke", true, false) == null, "a hearth's smoke goes up the chimney")
	em.free()
	var tm := HandLight.torch_model()
	var mats := []
	for i in tm.get_surface_count():
		mats.append(tm.surface_get_material(i))
	check(Materials.get_mat("torch_wood") in mats and Materials.get_mat("leather") in mats and Materials.get_mat("pitch_cloth") in mats, "a torch is a wooden stick with a leather grip and a pitch-soaked rag head")

func test_species_variety() -> void:
	var gen := ChunkGenerator.new(4242)
	var species := {}
	var keys := {}
	for cz in range(-3, 3):
		for cx in range(-3, 3):
			var c := gen.generate(cx * 9, cz * 9)
			for o in c["objects"]:
				if ObjectLibrary.kind(o["t"]) == "tree":
					check(o.has("sp") and o["v"] >= 0 and o["v"] < Flora.VARIANTS, "tree has species and variant")
					species[o["sp"]] = true
					keys[ObjectLibrary.mesh_key(o)] = true
	check(species.size() >= 10, "many species across regions (%d)" % species.size())
	var m := ObjectLibrary.get_mesh(keys.keys()[0])
	check(m != null and m.get_surface_count() > 0, "species mesh builds")
	check(Flora.species_name("oak", 12345) == Flora.species_name("oak", 12345), "species names stable")
	check(var_to_bytes(Flora.species("glowcap", 99)) == var_to_bytes(Flora.species("glowcap", 99)), "species params deterministic")

class AIServiceShim:
	static func build(c: Dictionary) -> Dictionary:
		return load("res://src/ai/ai_service.gd").build_request(c, "sys", [{"role": "user", "content": "hello"}])

func test_everything_is_destructible() -> void:
	for t in ObjectLibrary.KIND:
		var o := {"t": t, "s": 1.0, "e": 0, "st": {"yield": 4, "left": 5}}
		var hp := Durability.max_hp(o)
		check(hp > 0.0, "%s has health" % t)
		var total := Durability.total_items(o)
		check(total > 0, "%s yields something" % t)
		var got := 0
		var hits := 0
		var destroyed := false
		while not destroyed and hits < 100000:
			var r := Durability.hit(o, Durability.power(ItemDB.def("pickaxe_iron"), Durability.material(t)))
			for y in r["items"]:
				check(ItemDB.has(y[0]), "%s yields a real item (%s)" % [t, y[0]])
				got += y[1]
			destroyed = r["destroyed"]
			hits += 1
		check(destroyed, "%s can be destroyed" % t)
		check(got == total, "%s pays out exactly its yield (%d/%d)" % [t, got, total])
		check(hits >= 3, "%s is not instantly destroyed (%d hits)" % [t, hits])
	# Chopping a tree pays its main yield as you go; extras only when it falls.
	var ct := {"t": "crystal_tree", "s": 1.0, "e": 1, "st": {"yield": 4}}
	var axe0 := ItemDB.def("axe_iron")
	var mid: Array = []
	var fell: Array = []
	while true:
		var r := Durability.hit(ct, Durability.power(axe0, Durability.material("crystal_tree")))
		if r["destroyed"]:
			fell = r["items"]
			break
		mid += r["items"]
	check(mid.all(func(y): return y[0] == "glowroot"), "a crystal tree gives only its wood while chopping (%s)" % [mid])
	check(fell.any(func(y): return y[0] == "aether_crystal"), "its crystal comes when it falls (%s)" % [fell])
	var dome := {"t": "hab_dome", "s": 1.0, "e": 2, "st": {}}
	var tree := {"t": "oak", "s": 1.0, "e": 0, "st": {"yield": 4}}
	var axe := ItemDB.def("axe_iron")
	check(Durability.max_hp(dome) / Durability.power(axe, "metal") > 20.0 * Durability.max_hp(tree) / Durability.power(axe, "wood"), "metal buildings take far longer than trees")
	check(Durability.power(Durability.FIST, "stone") > 0.0, "bare hands do something")
	check(Durability.power(ItemDB.def("pickaxe_plasma"), "metal") > Durability.power(ItemDB.def("pickaxe_iron"), "metal"), "better tools are faster")

func test_icons_exist_for_every_item() -> void:
	for t in ItemDB.ITEMS:
		var ic := Icons.get_icon(t)
		check(ic != null and ic.get_width() >= 64, "icon for %s" % t)

func test_photo_textures_load() -> void:
	for t in ChunkNode.TERRAIN_TEXTURES + Materials.PHOTO_FOR.values():
		check(Materials.photo(t, "albedo") != null, "albedo texture for %s" % t)
		check(Materials.photo(t, "normal") != null, "normal map for %s" % t)
	for t in Materials.PHOTO_FOR.values():
		if not Materials.PHOTO_COLOUR.has(t):
			check(Materials.photo(t, "detail") != null, "detail texture for %s" % t)
	check(Materials.photo("leaves", "card") != null, "leaf card")
	check(Materials.photo("nonexistent", "albedo") == null, "missing textures fall back to procedural")

func test_ranged_weapons() -> void:
	for t in ["crossbow", "crossbow_runic", "scrap_pistol", "pulse_smg", "pulse_rifle", "rail_rifle", "arc_launcher"]:
		var d := ItemDB.def(t)
		check(d.get("ranged", false) and ItemDB.has(String(d["ammo"])), "%s fires %s" % [t, d.get("ammo", "?")])
		check(Recipes.LIST.any(func(r): return r["out"] == t), "%s can be crafted" % t)
		check(Viewmodel.model(t) != null and Viewmodel.model(t).get_surface_count() > 0, "%s has a model" % t)
	check(Recipes.LIST.any(func(r): return r["out"] == "bolt" and not r.has("at")), "bolts can be made anywhere")

func test_markers() -> void:
	var mk := Markers.new()
	var a := mk.add("Camp", 10.0, 20.0, 0)
	mk.add("Teleporter Pad 1", 100.0, 0.0, 0, "teleporter", {"key": str(Vector2i(1, 0)), "i": 7})
	mk.add("Moon pin", 5.0, 5.0, 2)
	check(mk.on_planet(0).size() == 2 and mk.on_planet(0, "teleporter").size() == 1, "markers are kept per world")
	var back := Markers.from_data(JSON.parse_string(JSON.stringify(mk.to_data())))
	check(back.list.size() == 3 and back.next_id == mk.next_id, "markers survive a save")
	back.remove_object(Vector2i(1, 0), 7)
	check(back.on_planet(0, "teleporter").is_empty(), "a teleporter taken down is forgotten")
	back.remove(int(a["id"]))
	check(back.on_planet(0).is_empty(), "a pin can be removed")
	for id in ["waystone", "teleporter"]:
		check(BuildCatalog.def(id).get("teleporter", false) and Recipes.LIST.any(func(r): return r["out"] == id), "%s can be built" % id)
		check(BuildCatalog.mesh(id) != null and BuildCatalog.mesh(id).get_surface_count() > 0, "%s has a model" % id)

func test_storage() -> void:
	var o := {"t": "b:storage_chest", "i": 1, "st": {}}
	check(Storage.capacity(o) == 30 and Storage.is_empty(o), "a new storage chest is empty, with 30 slots (%d)" % Storage.capacity(o))
	var pack := Inventory.new()
	pack.add(ItemDB.make("stone", 40, 1.0, {}))
	pack.add(ItemDB.make("axe_iron", 1, 1.0, {}))
	var box := Storage.open(o)
	check(Storage.transfer(pack, 0, box) == 40 and pack.count("stone") == 0 and box.count("stone") == 40, "a stack moves into the chest")
	Storage.save(o, box)
	var again := Storage.open(JSON.parse_string(JSON.stringify(o)))
	check(again.count("stone") == 40 and not Storage.is_empty(o), "the chest keeps its contents through a save")
	Storage.transfer_all(again, pack)
	check(pack.count("stone") == 40 and again.count("stone") == 0, "take all")
	Storage.save(o, again)
	check(Storage.is_empty(o), "emptied chest")
	box = Storage.open(o)
	box.add(ItemDB.make("planks", 5, 1.0, {}))
	Storage.save(o, box)
	var spilled := Storage.spill(o)
	check(spilled.size() == 1 and spilled[0]["qty"] == 5 and Storage.is_empty(o), "a broken chest spills what it held")
	check(Recipes.LIST.any(func(r): return r["out"] == "storage_chest"), "storage chests can be crafted")

class DoorStreamerShim:
	var chunks := {}
	func get_chunk(k: Vector2i):
		return chunks.get(k)

func test_doors() -> void:
	for id in ["door_wood", "door_iron", "door_bulkhead"]:
		check(Doors.is_door_piece(id) and Doors.is_door(BuildCatalog.PREFIX + id), "%s is a door" % id)
		check(BuildCatalog.mesh(id) != null and BuildCatalog.mesh(id).get_surface_count() > 0, "%s has a model" % id)
		check(Recipes.LIST.any(func(r): return r["out"] == id), "%s can be crafted" % id)
		check(ItemDB.has(id) and ItemDB.def(id).get("kind", "") == "placeable", "%s is a building item" % id)
		for m in BuildCatalog.def(id)["models"]:
			check(Doors.leaf_mesh(String(m[0])).get_surface_count() > 0, "%s leaf %s has a mesh" % [id, m[0]])
	check(Doors.fits("wall_door").has("door_wood") and Doors.fits("wall_door_stone").has("door_iron") and Doors.fits("door_scifi") == ["door_bulkhead"], "doors fit their doorways")
	check(Doors.fits("wall_plaster").is_empty(), "a plain wall takes no door")
	check(not Doors.is_door("b:wall_door") and not Doors.is_door("oak"), "a doorway isn't a door")
	check(ItemDB.UNLOCK["door_wood"] < ItemDB.UNLOCK["door_iron"] and ItemDB.UNLOCK["door_iron"] < Eras.UNLOCK_LEVEL and ItemDB.UNLOCK["door_bulkhead"] >= Eras.UNLOCK_LEVEL, "plank doors before iron-bound, both medieval; bulkheads later")
	var o := {"t": "b:door_wood", "i": 0, "p": Vector3(4, 0, 4), "r": 0.0, "s": 1.0, "e": 0, "st": {"by": "you"}}
	Doors.init_state(o["st"])
	check(not Doors.is_open(o) and not Doors.is_locked(o) and Doors.is_mine(o) and Doors.owner_of(o) == Doors.my_id(), "a new door is shut, unlocked and yours")
	check(Doors.toggle(o, 1.0) == "opened" and Doors.is_open(o), "it opens")
	check(Doors.toggle(o, 1.0) == "closed" and not Doors.is_open(o), "and shuts")
	check(Doors.set_locked(o, true) and Doors.is_locked(o) and Doors.can_open(o), "you lock it and still have the key")
	check(Doors.can_open(o), "no lock to pick on your own door")
	# Someone else's locked door.
	var theirs := {"t": "b:door_iron", "i": 1, "p": Vector3.ZERO, "r": 0.0, "s": 1.0, "e": 0, "st": {}}
	Doors.init_state(theirs["st"])
	theirs["st"]["owner"] = "player_42"
	check(Doors.toggle(theirs, 1.0) == "opened", "an unlocked door opens for anyone")
	Doors.toggle(theirs, 1.0)
	theirs["st"]["locked"] = true
	check(not Doors.can_open(theirs) and Doors.toggle(theirs, 1.0) == "locked" and not Doors.is_open(theirs), "a stranger's locked door stays shut")
	check(not Doors.set_locked(theirs, false) and Doors.is_locked(theirs), "and you can't unlock it")
	check(not Doors.grant(theirs, Doors.my_id()), "nor give yourself a key")
	check(Doors.tier(theirs) == 2 and Doors.verb(theirs, false).begins_with("Pick the adept lock"), "an iron-bound lock is adept to pick")
	theirs["st"]["access"] = [Doors.my_id()]
	check(Doors.can_open(theirs), "the access list lets you in")
	theirs["st"]["access"] = []
	Doors.picked(theirs, -1.0)
	check(not Doors.is_locked(theirs) and Doors.is_open(theirs) and float(theirs["st"]["side"]) == -1.0, "a picked lock opens away from you")
	check(Doors.grant(o, "friend") and Doors.has_access(o, "friend") and not Doors.has_access(o, "stranger"), "you can hand out a key")
	check(Doors.revoke(o, "friend") and not Doors.has_access(o, "friend"), "and take it back")
	check(Doors.may_access("") and Doors.may_access(Doors.my_id()) and not Doors.may_access("player_42"), "may_access: no owner, or you")
	# Swinging away from whoever opened it, with the hinge on either side.
	for e in [["village/Door_1_Round", 0, Vector3(-0.535, 0, -0.11), 1.0], ["village/Door_1_Round", 180, Vector3(0.535, 0, -0.11), 1.0]]:
		var edge := Vector3(1.0, 1.0, 0.0)
		var shut: Vector3 = Doors.leaf_xf(e, false, 0.0, 1.0) * edge
		check(shut.is_equal_approx(BuildCatalog._xf(e) * edge), "a shut leaf sits where the model puts it")
		check((Doors.leaf_xf(e, false, 1.0, 1.0) * edge).z < shut.z - 0.5, "opened from the front, it swings to the back (yaw %d)" % e[1])
		check((Doors.leaf_xf(e, false, 1.0, -1.0) * edge).z > shut.z + 0.5, "opened from the back, it swings to the front (yaw %d)" % e[1])
		check(Doors.leaf_xf(e, false, 1.0, 1.0).origin.is_equal_approx(BuildCatalog._xf(e).origin), "a leaf turns on its hinge")
	var bulk: Array = BuildCatalog.def("door_bulkhead")["models"]
	var l0 := Doors.leaf_xf(bulk[0], true, 1.0, 1.0).origin - BuildCatalog._xf(bulk[0]).origin
	var l1 := Doors.leaf_xf(bulk[1], true, 1.0, 1.0).origin - BuildCatalog._xf(bulk[1]).origin
	check(l0.x < -1.5 and l1.x > 1.5 and absf(l0.z) < 0.01, "bulkhead leaves slide apart")
	check(Doors.side_of(o, Vector3(4, 0, 4), Vector3(4, 0, 6)) == 1.0 and Doors.side_of(o, Vector3(4, 0, 4), Vector3(4, 0, 2)) == -1.0, "which side of a door you stand on")
	# Hanging a door in a doorway, and the door found there afterwards.
	var cd := {"cx": 0, "cz": 0, "objects": [{"t": "b:wall_door", "i": 0, "p": Vector3(5, 2, 7), "r": PI * 0.5, "s": 1.0, "e": 0, "st": {}}]}
	var shim := DoorStreamerShim.new()
	shim.chunks[Vector2i(0, 0)] = {"data": cd}
	var eye := Vector3(9, 3.6, 7)
	var dw := Doors.doorway_near(shim, "door_wood", eye, Vector3(1, 2.5, 7))
	check(not dw.is_empty() and (dw["pos"] as Vector3).is_equal_approx(Vector3(5, 2, 7)) and is_equal_approx(float(dw["yaw"]), PI * 0.5), "aiming through a doorway finds it")
	check(Doors.doorway_near(shim, "door_bulkhead", eye, Vector3(1, 2.5, 7)).is_empty(), "a bulkhead doesn't hang in a village doorway")
	check(Doors.doorway_near(shim, "door_wood", eye, Vector3(9, 0, 1)).is_empty(), "nothing when aiming away")
	check(Doors.door_at(shim, Vector3(5, 2, 7)).is_empty(), "no door there yet")
	var hung := {"t": "b:door_wood", "i": 1, "p": Vector3(5, 2, 7), "r": PI * 0.5, "s": 1.0, "e": 0, "st": {"by": "you"}}
	Doors.init_state(hung["st"])
	cd["objects"].append(hung)
	check(not Doors.door_at(shim, Vector3(5, 2, 7)).is_empty(), "the door in a doorway is found")
	check(BuildCatalog.occupied(shim, "door_iron", Vector3(5, 2, 7), PI * 1.5), "a doorway holds one door")
	# Door state is saved with the chunk.
	var s := _tmp_store("doors")
	var g := ChunkGenerator.new(77)
	var c := s.get_or_create_chunk(g, 1, 1)
	var st := {"by": "you"}
	Doors.init_state(st)
	st["locked"] = true
	st["open"] = true
	st["side"] = -1.0
	st["access"] = ["friend"]
	c["objects"].append({"t": "b:door_iron", "i": c["objects"].size(), "p": Vector3(3, 1, 3), "r": 0.0, "s": 1.0, "e": 0, "st": st})
	s.save_chunk(c)
	var back = s.load_chunk(1, 1)
	var bd: Dictionary = back["objects"][back["objects"].size() - 1]
	check(Doors.is_door(bd["t"]) and Doors.is_locked(bd) and Doors.is_open(bd) and float(bd["st"]["side"]) == -1.0 and Doors.has_access(bd, "friend") and Doors.is_mine(bd), "a door keeps its lock, owner, keys and swing through a save")

func test_hand_light() -> void:
	var inv := Inventory.new()
	var hl := HandLight.new()
	check(hl.toggle(inv).begins_with("No light") and not hl.is_on(), "no torch, no light")
	inv.add(ItemDB.make("torch", 2, 1.0, {}))
	hl.toggle(inv)
	check(hl.kind == "torch", "a torch lights")
	hl.tick(HandLight.TORCH_BURN + 1.0, inv)
	check(inv.count("torch") == 1 and hl.kind == "torch", "a burnt-out torch is used up and the next one lit")
	hl.tick(HandLight.TORCH_BURN + 1.0, inv)
	check(inv.count("torch") == 0 and not hl.is_on(), "the last torch burns out")
	inv.add(ItemDB.make("flashlight", 1, 1.0, {}))
	hl.toggle(inv)
	check(hl.kind == "flashlight", "a flashlight turns on")
	hl.tick(HandLight.FLASH_CHARGE * 0.5, inv)
	check(inv.count("flashlight") == 1, "the battery lasts hours")
	hl.tick(HandLight.FLASH_CHARGE, inv)
	check(inv.count("flashlight_dead") == 1 and inv.count("flashlight") == 0 and not hl.is_on(), "then the battery fails")
	var fix := false
	for r in Recipes.LIST:
		if r["out"] == "flashlight" and r["in"].has("flashlight_dead"):
			fix = true
	check(fix, "a dead flashlight can be repaired")
	hl.toggle(inv)
	check(not hl.is_on(), "a dead flashlight gives no light")
	# Holding a torch on the hotbar lights it, with no key press.
	inv.add(ItemDB.make("torch", 1, 1.0, {}))
	hl.set_held("torch", inv)
	check(hl.is_on() and hl.lit() == "torch", "a torch held in hand burns")
	check(hl.toggle(inv) != "Light off" and hl.is_on(), "the off-hand key does not put out a held torch")
	hl.tick(HandLight.TORCH_BURN + 1.0, inv)
	check(inv.count("torch") == 0 and not hl.is_on(), "a held torch burns down too")
	hl.set_held("", inv)
	check(not hl.is_on(), "putting it away puts it out")
	hl.free()

func test_wonders() -> void:
	var ruin := {"t": "alien_ruin", "sp": 5, "st": {}}
	check(Wonders.use_of(ruin, 2.4)["verb"].begins_with("Wake"), "a sleeping relic offers to wake")
	ruin["st"] = {"woke": true, "day": 2}
	check(Wonders.use_of(ruin, 2.9).is_empty(), "a woken relic rests the same day")
	check(Wonders.use_of(ruin, 3.1)["verb"].begins_with("Draw"), "and restores you the next")
	check(Wonders.use_of({"t": "standing_stone", "st": {"read": true}}, 9.0).is_empty(), "runes are read once")
	check(not Wonders.use_of({"t": "well", "st": {"day": 5}}, 5.5).is_empty(), "a well can always be drunk from")
	check(Wonders.unbreakable("alien_ruin") and Wonders.unbreakable("beacon") and not Wonders.unbreakable("well"), "relics can't be broken; a well can")
	check(not Wonders.use_of({"t": "summit_shrine", "st": {}}, 1.0).is_empty() and Wonders.use_of({"t": "summit_shrine", "st": {"used": true, "day": 1}}, 1.5).is_empty() and not Wonders.use_of({"t": "summit_shrine", "st": {"used": true, "day": 1}}, 2.2).is_empty(), "a shrine blesses you once a day")
	check(Wonders.use_of({"t": "eyrie", "st": {"used": true, "day": 1}}, 9.0).is_empty(), "a nest is searched once")
	for t in Wonders.LANDMARKS:
		check(Landmark.has(t) and Wonders.unbreakable(t), "landmark %s is used, not broken" % t)
	check(Wonders.compass(Vector2.ZERO, Vector2(0, -10)) == "north" and Wonders.compass(Vector2.ZERO, Vector2(10, 10)) == "southeast", "compass words")

func test_levelling_and_attributes() -> void:
	var s := Stats.new()
	check(s.level == 1 and s.points == 0 and s.max_health() == 100.0, "fresh character")
	check(Stats.xp_to_next(1) < Stats.xp_to_next(10), "levels get harder")
	var gained := s.add_xp(Stats.xp_to_next(1) + Stats.xp_to_next(2) + 5)
	check(gained == 2 and s.level == 3 and s.points == 2 * Stats.POINTS_PER_LEVEL and s.xp == 5, "xp carries over levels (%d, %d)" % [s.level, s.xp])
	check(s.spend("end") and s.max_health() == 110.0 and s.max_stamina() == 108.0, "endurance raises health and stamina")
	check(s.spend("str") and s.damage_mult() > 1.0, "strength hits harder")
	check(s.spend("agi") and s.speed_mult() > 1.0 and s.swing_mult() > 1.0, "agility moves and swings faster")
	check(s.spend("oxy") and s.max_breath() > Stats.BASE_BREATH, "oxygen holds your breath longer")
	var cap0 := s.carry_capacity()
	check(s.spend("str") and s.carry_capacity() > cap0, "strength carries more")
	check(is_equal_approx(s.carry_capacity() - cap0, Stats.CARRY_PER_STR), "each strength point adds %d kg" % int(Stats.CARRY_PER_STR))
	check(s.spend("int") and s.xp_mult() > 1.0, "intellect learns faster")
	var inv := Inventory.new()
	inv.add(ItemDB.make("stone", 10, 1.0, {}))
	inv.add(ItemDB.make("axe_iron", 1, 1.0, {}))
	check(is_equal_approx(inv.weight(), 10 * ItemDB.weight("stone") + ItemDB.weight("axe_iron")) and inv.weight() > 20.0, "the pack has weight (%.1f kg)" % inv.weight())
	check(not s.spend("luck"), "unknown attribute rejected")
	while s.points > 0:
		s.spend("end")
	check(not s.spend("end"), "no points, no spending")
	var back := Stats.from_data(JSON.parse_string(JSON.stringify(s.to_data())))
	check(back.level == s.level and back.xp == s.xp and back.attrs == s.attrs, "stats survive a save through JSON")
	for i in 400:
		s.add_xp(1000000)
	check(s.level == Stats.MAX_LEVEL and s.xp == 0, "level cap holds")

func test_thief_skills() -> void:
	var s := Stats.new()
	check(s.skills["sneak"] == 0 and s.skills["pick"] == 0 and s.skills["lock"] == 0, "skills start at zero")
	check(s.notice_mult(true) < s.notice_mult(false), "crouching hides you")
	var seen0 := s.notice_mult(true)
	var pick0 := s.pickpocket_chance(10.0, true, 0.2)
	var lock0 := LockGame.sweet_half(2, s.skills["lock"])
	check(s.pickpocket_chance(10.0, true, 0.2) > s.pickpocket_chance(10.0, false, 0.2), "picking from behind is easier")
	check(s.pickpocket_chance(5.0, true, 0.2) > s.pickpocket_chance(120.0, true, 0.2), "dear things are harder to lift")
	check(LockGame.sweet_half(1, 0) > LockGame.sweet_half(3, 0), "master locks have a narrower sweet spot")
	check(not s.spend_skill("sneak"), "skills cost points")
	s.points = 2
	check(s.spend_skill("sneak") and s.skills["sneak"] == 1 and s.points == 1, "a point buys a skill level")
	check(not s.spend_skill("juggling"), "unknown skill rejected")
	check(s.practice("pick", Stats.practice_to_next(0) + 0.5) == 1 and s.skills["pick"] == 1, "practice raises a skill")
	s.practice("lock", 100000.0)
	check(s.skills["lock"] == Stats.SKILL_MAX, "skills top out")
	check(s.notice_mult(true) < seen0 and s.pickpocket_chance(10.0, true, 0.2) > pick0 and LockGame.sweet_half(2, s.skills["lock"]) > lock0, "skills help")
	var back := Stats.from_data(JSON.parse_string(JSON.stringify(s.to_data())))
	check(back.skills == s.skills and is_equal_approx(float(back.skill_xp["pick"]), float(s.skill_xp["pick"])), "skills survive a save")
	var old := Stats.from_data({"level": 4, "attrs": {"str": 2}})
	check(old.skills["sneak"] == 0 and old.level == 4, "old saves get skills at zero")

func test_lock_game() -> void:
	var g := LockGame.new(2, 0, 1234)
	check(g.sweet >= -PI * 0.5 and g.sweet <= PI * 0.5, "the sweet spot is on the lock")
	check(LockGame.new(2, 0, 1234).sweet == g.sweet, "the same chest keeps its sweet spot")
	# Right on the sweet spot: the lock turns all the way and opens.
	g.set_pick(g.sweet)
	var r := ""
	for i in 120:
		r = g.step(1.0 / 60.0, true)
		if r != "":
			break
	check(r == "open", "on the sweet spot the lock opens (%s)" % r)
	# Way off: the lock jams and forcing it snaps the pick.
	var h := LockGame.new(3, 0, 99)
	h.set_pick(h.sweet + (1.2 if h.sweet < 0.0 else -1.2))
	check(h.max_turn() < 0.2, "far off the sweet spot the lock barely turns")
	r = ""
	for i in 600:
		r = h.step(1.0 / 60.0, true)
		if r != "":
			break
	check(r == "broke" and h.turn == 0.0 and is_equal_approx(h.pick_hp, 1.0), "forcing a jammed lock snaps the pick, and the next starts fresh (%s)" % r)
	# Near it: turns part way, more the closer you are.
	var k := LockGame.new(1, 0, 7)
	k.set_pick(k.sweet + k.half + 0.1)
	var near := k.max_turn()
	k.set_pick(k.sweet + k.half + 0.3 if k.sweet + k.half + 0.3 <= PI * 0.5 else k.sweet - k.half - 0.3)
	check(near > k.max_turn() and near < 1.0, "the closer to the sweet spot, the further it turns")
	# The pick can't move while the lock is turned.
	k.set_pick(k.sweet + k.half + 0.1)
	k.step(0.2, true)
	var at := k.pick
	k.set_pick(at + 0.5)
	check(k.pick == at, "the pick holds still while you turn")
	k.step(1.0, false)
	check(k.turn == 0.0, "letting go springs the lock back")
	check(LockGame.sweet_half(2, 50) > LockGame.sweet_half(2, 0) * 2.0, "Lockpicking widens the sweet spot")
	check(ItemDB.has("lockpick") and Recipes.LIST.any(func(rr): return rr["out"] == "lockpick"), "lockpicks are an item you can make")

func test_bounty_and_wanted() -> void:
	var c := Crime.new()
	check(c.stars("0:1_2", 3.0) == 0 and c.worst(3.0).is_empty(), "not wanted at first")
	c.add("0:1_2", "Ashford", 20, 3.0)
	check(c.stars("0:1_2", 3.0) == 1 and c.owed("0:1_2", 3.0) == 20, "a small theft is one star")
	c.add("0:1_2", "Ashford", 300, 3.2)
	check(c.stars("0:1_2", 3.2) == 3, "a big haul is three stars (%d)" % c.stars("0:1_2", 3.2))
	check(c.owed("0:1_2", 4.0) == 320, "no cooling off on the first day")
	check(c.owed("0:1_2", 5.2) == 160, "then it halves each day (%d)" % c.owed("0:1_2", 5.2))
	c.add("0:9_9", "Brookmere", 5, 3.0)
	check(c.worst(3.2)["name"] == "Ashford" and c.worst(3.2)["stars"] == 3, "the worst town shows")
	var back := Crime.from_data(JSON.parse_string(JSON.stringify(c.to_data())))
	check(back.owed("0:1_2", 3.2) == 320 and back.owed("0:9_9", 3.0) == 5, "bounties survive a save")
	c.clear("0:1_2")
	check(c.owed("0:1_2", 3.2) == 0, "paying clears it")
	check(c.owed("0:9_9", 30.0) == 0, "small bounties cool to nothing")
	c.prune(30.0)
	check(c.bounty.is_empty(), "cold bounties are dropped")
	check(Crime.stars_for(Crime.STARS[4]) == 5 and Crime.stars_for(0) == 0, "star thresholds")
	# Guards and townsfolk react to the wanted level.
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var st := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var g: Dictionary = st["npcs"][1].duplicate(true)
	g["job"] = NPCGen.GUARD_JOBS[g["era"]]
	g["rel"] = 0
	var per := {"hour": 11.0, "pos": Vector2.ZERO, "center": st["center"], "player_dist": 12.0, "noise": 0.5, "now": 0.0, "wanted": 1}
	check(DecisionEngine.decide(g, per)["action"] == "confront", "a guard comes to collect a bounty")
	per["wanted"] = 3
	check(DecisionEngine.decide(g, per)["action"] == "attack", "at three stars guards attack")
	var f: Dictionary = st["npcs"][2].duplicate(true)
	f["job"] = "farmer"
	f["rel"] = 0
	f["traits"]["brave"] = 0.1
	per["player_dist"] = 6.0
	check(DecisionEngine.decide(f, per)["action"] == "flee", "townsfolk keep clear of a wanted criminal")
	per["wanted"] = 0
	check(DecisionEngine.decide(g, per)["action"] != "attack", "no bounty, no fight")

func test_pockets() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var st := NPCGen.generate(777, gen, fx[1], gen.settlement_layout(fx[1]))
	var rec: Dictionary = st["npcs"][2].duplicate(true)
	var pk := NPCSocial.pockets(rec)
	check(pk.size() >= 0 and pk.size() <= 3 and NPCSocial.pockets(rec) == pk, "pockets are stable within a few days")
	for it in pk:
		check(ItemDB.has(it["type"]) and ItemDB.def(it["type"]).get("kind", "") != "armor", "pocket item %s" % it["type"])
	var purse := int(rec["purse"])
	check(NPCSocial.lift_marks(rec, purse + 50) == purse and int(rec["purse"]) == 0, "lifting a purse takes no more than it holds")

func test_vehicles() -> void:
	for k in Vehicle.KINDS:
		check(ItemDB.def(k).get("kind", "") == "vehicle" and not ItemDB.is_stackable(k), "%s is a vehicle item" % k)
		var made := false
		for r in Recipes.LIST:
			if r["out"] == k:
				made = Recipes.STATION_NAMES.has(r.get("at", ""))
		check(made, "%s is made at a station" % k)
		var m := Vehicle.make_model(k)
		var box := Vehicle._bounds(m)
		check(box.size.y > 0.5 and box.size.y < 4.0 and box.position.y > -0.2, "%s model is a sensible size (%s)" % [k, box])
		m.free()
	for st in ["vehicle_bay", "stable"]:
		check(BuildCatalog.def(st).get("station", "") == st and Recipes.STATION_NAMES.has(st), "%s is a crafting station" % st)

func test_undergrowth_harvest() -> void:
	for era in Eras.COUNT:
		for sp in 40:
			var y := Flora.under_yield(sp, era, 0.1)
			check(y.size() >= 1 and y[0][0] == "fiber" and ItemDB.ITEMS.has(y[0][0]), "undergrowth always gives fiber")
			for e in y:
				check(ItemDB.ITEMS.has(e[0]) and int(e[1]) >= 1, "undergrowth yields real items")
			check(Flora.UNDER_FORMS[era].has(Flora.under_form(sp, era)), "undergrowth form is one of its era's")
	var ch := {"cleared": PackedFloat32Array([3.5, 7.25])}
	check(Flora.was_cleared(ch, 3.5, 7.25) and not Flora.was_cleared(ch, 3.5, 8.0), "harvested spots are remembered")
	check(not Flora.was_cleared({}, 1.0, 1.0), "untouched chunk has nothing cleared")

func test_ore_names() -> void:
	for sp in [1, 77, 4242, 99991]:
		check(Flora.species_name("iron_vein", sp) == ObjectLibrary.label("iron_vein"), "an iron vein is named as iron, not a random colour")
		check(Flora.species_name("rock", sp) == ObjectLibrary.label("rock"), "rocks keep their plain name")

func test_planets() -> void:
	var a := Planets.system(4242)
	check(a.size() == Planets.COUNT and a[0]["kind"] == "home" and a[0]["seed"] == 4242, "home planet first, with the world seed")
	check(var_to_str(a) == var_to_str(Planets.system(4242)), "star system is deterministic")
	var kinds := {}
	var names := {}
	for p in a:
		kinds[p["kind"]] = true
		names[p["name"]] = true
	check(kinds.size() == Planets.COUNT and names.size() == Planets.COUNT, "every planet differs in kind and name")
	var store := _tmp_store("planets")
	var home_path := store.chunk_path(1, 2)
	store.set_planet(3)
	check(store.chunk_path(1, 2) != home_path and store.has_rivers(), "another planet's land is stored apart")
	Planets.apply({"kind": "fey", "seed": 1})
	var f := WorldField.new(99)
	var ok := true
	for i in 40:
		ok = ok and f.era_weights(i * 517.0, i * -311.0)[Eras.FANTASY] > 0.999
	check(ok, "a fey moon is all fantasy")
	Planets.apply({"kind": "home", "seed": 1})
	check(WorldField.allowed_eras.is_empty(), "home allows every era")

## Themed worlds: human home and two human worlds, two alien ones; eras, levels, gear
## and portals all follow the distance from the heart of the land.
func test_world_themes() -> void:
	var sys := Planets.system(4242, "human")
	check(sys[0]["kind"] == "homeland" and sys[0]["theme"] == "human" and int(sys[0]["base"]) == 1, "a new world's home is a human world")
	var alien := 0
	for p in sys:
		if p["theme"] == "alien":
			alien += 1
			check(int(p["base"]) >= 50, "alien worlds are level 50+ (%s)" % p["kind"])
	check(alien == 2, "two alien worlds are linked to a human home")
	# Oaks grow on human worlds, so no oak species has violet or magenta leaves.
	var odd := 0
	for sp in range(1, 3001):
		var h: float = Color(Flora.species("oak", sp)["leaf"]).h
		if h > 0.45 and h < 0.97:
			odd += 1
	check(odd == 0, "no purple oaks (%d of 3000)" % odd)
	check(var_to_str(Planets.system(4242)) != var_to_str(sys), "old worlds keep their old system")
	Planets.apply(sys[0])
	check(Eras.theme == "human" and WorldField.allowed_eras == [Eras.MEDIEVAL, Eras.SCIFI], "applying the home world sets its theme")
	var f := WorldField.new(77)
	var near_ok := true
	for i in 30:
		var a := i * 0.7
		near_ok = near_ok and f.era_weights(cos(a) * 700.0, sin(a) * 700.0)[Eras.MEDIEVAL] > 0.99
	check(near_ok, "the land round the start is all medieval")
	var far := 0
	for i in 60:
		var a := i * 0.37
		if WorldField.dominant(f.era_weights(cos(a) * 5000.0, sin(a) * 5000.0)) == Eras.SCIFI:
			far += 1
	check(far > 25 and far < 60, "far out, most land is sci-fi (%d of 60)" % far)
	check(Eras.zone_level(0, 0) == 1 and Eras.zone_level(1500, 0) == 11 and Eras.zone_level(0, -6000) == 41, "zone levels rise 1 per 150 m")
	check(Eras.nature(Eras.SCIFI) == Eras.MEDIEVAL and Eras.look(PackedFloat32Array([0.2, 0, 0.8]))[Eras.MEDIEVAL] > 0.99, "human sci-fi land looks natural")
	check(Biome.params(12345, Eras.SCIFI)["lumen"] == 0.0 and Biome.params(54321, Eras.SCIFI)["flora"][0]["t"] in ["oak", "pine"], "no glow and natural trees on a human world")
	check(Recipes.unlock_level("sword_iron") == 1 and Recipes.unlock_level("pulse_pistol") >= Eras.UNLOCK_LEVEL and Recipes.unlock_level("scrap_pistol") == 10, "advanced weapons unlock at level 10")
	check(Recipes.unlock_level("wall_scifi") >= Eras.UNLOCK_LEVEL and Recipes.unlock_level("wall_plaster") == 1 and Recipes.unlock_level("ship") == Recipes.SHIP_LEVEL, "building unlocks by level; a starship at 35")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var gun := false
	for i in 300:
		for it in ItemDB.roll_loot(Eras.MEDIEVAL, r, {"chunk": Vector2i(1, 1), "how": "found"}, 0.0):
			gun = gun or it["type"] == "scrap_pistol"
	check(not gun, "no guns in the caches round the start")
	var g := ChunkGenerator.new(77, true)
	var found := 0
	var low := 0
	for wz in range(-6, 7):
		for wx in range(-6, 7):
			var p := WorldPortal.spot(g, wx, wz)
			if p != Vector2.INF:
				found += 1
				if Eras.zone_level(p.x, p.y) < WorldPortal.MIN_LEVEL:
					low += 1
	check(found > 3 and low == 0, "portals only stand in level 40+ zones (%d found)" % found)
	var np := WorldPortal.nearest(g, Vector2(6500, 0))
	check(np != Vector2.INF and np.distance_to(Vector2(6500, 0)) < 4000.0, "the nearest portal can be found from afar")
	if np != Vector2.INF:
		var cx := int(floor(np.x / 64.0))
		var cz := int(floor(np.y / 64.0))
		var ch := g.generate(cx, cz)
		var has := false
		for o in ch["objects"]:
			has = has or o["t"] == WorldPortal.TYPE
		check(has, "the portal is built into its chunk")
	Planets.apply(sys[3])
	check(Eras.theme == "alien" and Eras.zone_level(0, 0) >= 50, "alien worlds start at level 50")
	var npc := NPCGen._person(r, Eras.SCIFI, 0, 0, 0)
	check(npc["race"] == "Vex" and not NPCGen.SKIN.has(npc["body"]["skin"]), "alien worlds' people are not human")
	Planets.apply(Planets.get_planet(0, 0))
	check(Eras.theme == "" and Eras.zone_level(9000, 0) == 1, "old worlds have no zones")

func test_kit_flora() -> void:
	var forms := {}
	for t in ["oak", "pine"]:
		for sp in range(1, 60):
			var p := Flora.species(t, sp)
			var bare: bool = p["form"] == "dead" or p["form"] == "snag"
			forms[t + ":" + String(p["form"])] = true
			var m := RealTree.build(t, sp, sp % Flora.VARIANTS)
			check(m != null and m.get_surface_count() == (1 if bare else 2), "%s species %d (%s) has bark%s" % [t, sp, p["form"], "" if bare else " and leaves"])
			if m == null:
				continue
			var tall := m.get_aabb().size.y
			check(tall > float(p["height"]) * 0.5 and tall < float(p["height"]) * 1.6, "%s species %d is about its species' height (%.1f m of %.1f)" % [t, sp, tall, p["height"]])
			if not bare:
				var leaves := m.surface_get_array_len(1)
				check(leaves >= (96 if p["form"] == "shrub" else 200), "%s species %d has a full crown of sprays (%d vertices)" % [t, sp, leaves])
				var far := RealTree.far_parts(t, sp, sp % Flora.VARIANTS)
				var fl: int = (far["leaf"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				check(fl > 0 and fl * 4 <= leaves, "%s species %d has a far version (%d vs %d vertices)" % [t, sp, fl, leaves])
	check(forms.size() >= 10, "trees come in many forms (%d)" % forms.size())
	var bush := RealTree.build_bush(5, 1.0)
	check(bush.get_surface_count() == 2 and bush.get_aabb().size.y < 1.6, "bushes are leaf sprays about a metre tall")
	# Oaks keep green (or copper beech) leaves on every world: violet foliage belongs to
	# alien flora, and oaks never grow there.
	var was := Eras.theme
	for th in ["human", "alien"]:
		Eras.theme = th
		var violet := 0
		for sp in range(1, 400):
			var h := (Flora.species("oak", sp)["leaf"] as Color).h
			if h > 0.7 and h < 0.97:
				violet += 1
		check(violet == 0, "no violet oaks on %s worlds: %d" % [th, violet])
	Eras.theme = was
	for n in KitFlora.ALL:
		check(ResourceLoader.exists(KitFlora.DIR + n + ".gltf"), "kit model %s is in the repo" % n)

func test_creature_levels() -> void:
	var seen := {}
	for sp in 60:
		for era in Eras.COUNT:
			var p := Creature.species(sp, era)
			var lv := Creature.level_of(p)
			check(lv >= 1 and lv <= 60, "animal level in range")
			seen[lv] = true
			if p["temper"] == "aggressive":
				check(lv >= 3, "predators are at least level 3")
	check(seen.size() >= 4, "animals span several levels (%d)" % seen.size())
	check(ItemDB.def("binoculars").get("zoom", false), "binoculars zoom")
	var made := false
	for r in Recipes.LIST:
		made = made or r["out"] == "binoculars"
	check(made, "binoculars can be crafted")

func test_gear_ranks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var counts := [0, 0, 0, 0, 0, 0]
	var lucky := [0, 0, 0, 0, 0, 0]
	for i in 4000:
		counts[Rarity.roll(rng, 0.0)] += 1
		lucky[Rarity.roll(rng, 1.0)] += 1
	check(counts[0] > counts[2] and counts[2] > counts[4], "lower ranks are commoner (%s)" % [counts])
	check(lucky[4] + lucky[5] > (counts[4] + counts[5]) * 3, "luck favours the top ranks (%s vs %s)" % [lucky, counts])
	var sword := ItemDB.make("sword_iron", 1, 1.0, {})
	check(Rarity.of(sword) == Rarity.COMMON and ItemDB.stats(sword)["damage"] == 25.0, "plain gear keeps its stats")
	Rarity.apply(sword, Rarity.MYTHIC, rng)
	check(sword["affixes"].size() == 4, "a mythic has four abilities")
	check(float(ItemDB.stats(sword)["damage"]) > 25.0 * 1.5, "a mythic hits much harder")
	check(sword["name"] != "", "an epic or better has its own name")
	for id in sword["affixes"]:
		check("melee" in Rarity.AFFIXES[id]["kinds"], "a sword only gets melee abilities (%s)" % id)
	check(Rarity.of({"type": "wood", "qty": 3}) == Rarity.COMMON, "resources have no rank")
	check(Rarity.of({"type": "sword_iron", "quality": 1.3}) == Rarity.UNCOMMON, "old fine gear reads as uncommon")
	var bread := ItemDB.make("bread", 2, 1.0, {}, rng)
	check(not bread.has("rarity"), "food never rolls a rank")
	# Dangerous places pay better.
	var poor := 0
	var rich := 0
	for i in 300:
		for it in ItemDB.roll_loot(0, rng, {}, 0.0):
			poor += Rarity.of(it) if it["type"] != "_marks" else 0
		for it in ItemDB.roll_loot(0, rng, {}, 1.0):
			rich += Rarity.of(it) if it["type"] != "_marks" else 0
	check(rich > poor * 3, "lucky loot has better gear (%d vs %d)" % [rich, poor])

func test_armor_items() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var slots := {}
	for t in ItemDB.ITEMS:
		var d: Dictionary = ItemDB.ITEMS[t]
		if d.get("kind", "") == "armor":
			check(d.get("slot", "") in ["head", "chest", "hands", "legs", "feet", "shield", "back", "ring", "neck"], "%s has a slot" % t)
			check(float(d.get("armor", 0)) > 0.0 or d.has("bonus"), "%s protects or helps" % t)
			slots[d["slot"]] = true
	check(slots.size() == 9, "armour for every slot")
	var helm := ItemDB.make("helm_iron", 1, 1.0, {})
	Rarity.apply(helm, Rarity.LEGENDARY, rng)
	check(float(ItemDB.stats(helm)["armor"]) > 8.0, "ranked armour protects more")
	for id in helm["affixes"]:
		check("armor" in Rarity.AFFIXES[id]["kinds"], "armour only gets armour abilities (%s)" % id)
	var craftable := {}
	for r in Recipes.LIST:
		craftable[r["out"]] = true
	check(craftable.has("mail_iron") and craftable.has("plate_mythril") and craftable.has("exo_chest"), "armour can be crafted in every era")

## The medieval age (pack A): every painted icon is a real item, every recipe makes and
## uses real things, and every item can be had somewhere (made, found, bought or looted).
func test_pack_a_items() -> void:
	var known := {}
	for sh in Icons.MORE_SHEETS:
		check((sh[1] as Array).size() == 30, "%s has 30 cells" % sh[0])
		for t in sh[1]:
			if t == "":
				continue
			check(ItemDB.has(t), "icon %s is an item" % t)
			known[t] = true
	var made := {}
	for r in Recipes.LIST:
		check(ItemDB.has(r["out"]), "recipe makes a real item: %s" % r["out"])
		for t in r["in"]:
			check(ItemDB.has(t), "recipe for %s uses a real item: %s" % [r["out"], t])
		for t in r.get("tools", []):
			check(ItemDB.has(t) and not ItemDB.is_stackable(t), "recipe for %s needs a real tool: %s" % [r["out"], t])
		if r.has("at"):
			check(Recipes.STATION_NAMES.has(r["at"]), "recipe for %s needs a known station" % r["out"])
		made[r["out"]] = true
	# Everything else turns up in loot, shops, pockets, plants or rocks.
	var found := {}
	for era in 3:
		for t in ItemDB.GEAR_LOOT[era] + ItemDB.DUNGEON_LOOT[era]:
			found[t] = true
	for k in TownShops.KINDS:
		for g in TownShops.KINDS[k]["goods"]:
			for t in g:
				found[t] = true
	for k in TownShops.GUILDS:
		for t in TownShops.GUILDS[k]["goods"]:
			found[t] = true
	for j in NPCSocial.JOB_GOODS:
		for t in NPCSocial.JOB_GOODS[j]:
			found[t] = true
	for k in Byproducts.FROM:
		for e in Byproducts.FROM[k]:
			found[e[0]] = true
	for t in Byproducts.HERBS + ["mushroom", "herb_nightshade", "flax", "clay"]:
		found[t] = true
	for t in known:
		if t in ["bone", "animal_fat", "antler", "fur_pelt", "leather", "treasure_map", "fish_raw", "flashlight_dead"]:
			continue # butchered, from treasure maps, caught, or a spent flashlight
		check(made.has(t) or found.has(t), "%s can be had somewhere" % t)
	# Level gates rise with the age: stone first, steel later, the finest last.
	check(ItemDB.UNLOCK.get("pickaxe_stone", 1) < ItemDB.UNLOCK["pickaxe_bronze"], "stone before bronze")
	check(ItemDB.UNLOCK["bronze_sword"] < ItemDB.UNLOCK["steel_sword"], "bronze before steel")
	check(ItemDB.UNLOCK["kings_mace"] <= 10, "medieval gear stays within the first ten levels")
	# Thrown weapons stack and never roll a rank; rings are gear.
	check(not Rarity.is_gear("throwing_knives") and ItemDB.is_stackable("javelin"), "thrown weapons are plain stacks")
	check(Rarity.is_gear("ring_ruby"), "trinkets are gear")

func test_recipe_tools() -> void:
	var inv := Inventory.new()
	var r: Dictionary = Recipes.LIST.filter(func(x): return x["out"] == "salt")[0]
	inv.add(ItemDB.make("salt_crystal", 2, 1.0, {}))
	check(Recipes.max_crafts(inv, r) == 0 and Recipes.missing_tools(inv, r) == ["mortar_pestle"], "no mortar, no salt")
	inv.add(ItemDB.make("mortar_pestle", 1, 1.0, {}))
	check(Recipes.max_crafts(inv, r) == 2, "with a mortar, salt from each crystal")
	check(Recipes.craft(inv, r, {}) and inv.count("mortar_pestle") == 1 and inv.count("salt") == 3, "the mortar is not used up")

func test_effects() -> void:
	var eq := {"ring": ItemDB.make("ring_silver", 1, 1.0, {}), "neck": ItemDB.make("amulet_bone", 1, 1.0, {})}
	var buffs := {"strength": 30.0, "courage": 5.0}
	var b := Effects.bonus(eq, buffs)
	check(is_equal_approx(float(b["damage"]), 0.4), "strength and courage add up (%s)" % b.get("damage"))
	check(is_equal_approx(float(b["carry"]), 160.0), "charm and strength add carry")
	check(is_equal_approx(float(b["stamina"]), 20.0), "a silver ring adds stamina")
	var st := Stats.new()
	var base := st.carry_capacity()
	st.bonus = b
	check(is_equal_approx(st.carry_capacity(), base + 160.0) and st.damage_mult() > 1.39, "stats take the bonus")
	var gone := Effects.tick(buffs, 10.0)
	check(gone == ["courage"] and buffs.has("strength") and is_equal_approx(float(buffs["strength"]), 20.0), "effects run out")
	check(Effects.damage_per_sec({"poison": 3.0}) > 0.0 and Effects.damage_per_sec(buffs) == 0.0, "poison hurts, strength does not")
	var stew := ItemDB.def("stew")
	check(not Effects.useful(stew, 100.0, 100.0, 50.0, 100.0, {}), "no stew when whole")
	check(Effects.useful(stew, 40.0, 100.0, 50.0, 100.0, {}), "stew when hurt")
	check(Effects.useful(ItemDB.def("antidote"), 100.0, 100.0, 100.0, 100.0, {"poison": 3.0}), "antidote when poisoned")
	for t in ItemDB.ITEMS:
		var d: Dictionary = ItemDB.ITEMS[t]
		if d.has("buff"):
			check(Effects.BUFFS.has(d["buff"][0]), "%s gives a known effect" % t)
		if d.has("play"):
			check(Effects.BUFFS.has(d["play"]), "%s plays a known effect" % t)
	check(Effects.describe(ItemDB.def("elixir_strength")).size() > 0, "elixirs say what they do")

func test_byproducts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var got := {}
	for i in 400:
		for y in Byproducts.of_object("iron_vein", 3, 1, rng):
			got[y[0]] = got.get(y[0], 0) + int(y[1])
	check(got.has("copper_ore") and got.has("tin_ore") and got.has("coal"), "iron veins give copper, tin and coal")
	check(not got.has("silver_ore") and not got.has("gold_ore"), "no silver or gold near spawn")
	check(Byproducts.of_object("pine", 0, 1, rng).is_empty(), "nothing from nothing")
	var herbs := 0
	for sp in 40:
		for y in Flora.under_yield(sp, Eras.MEDIEVAL, 0.1):
			if ItemDB.def(y[0]).get("kind", "") == "herb" or y[0] in ["mushroom", "flax"]:
				herbs += 1
	check(herbs > 0, "medieval undergrowth gives herbs, mushrooms or flax")

func test_road_profiles() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var roads := g.roads_near(-1600.0, -1600.0, 1600.0, 1600.0)
	check(roads.size() > 3, "v5 roads exist (%d)" % roads.size())
	var worst := 0.0
	var steep := 0
	var steps := 0
	var cut := 0.0
	var air := 0
	var held := {}
	var fills: Array = []
	for rd in roads:
		var lv: PackedFloat32Array = rd["level"]
		var pts: PackedVector2Array = rd["pts"]
		var ar: PackedByteArray = rd["air"]
		check(lv.size() == pts.size() and ar.size() == pts.size(), "a level and a viaduct flag for every point")
		for i in lv.size() - 1:
			var dh := absf(lv[i + 1] - lv[i])
			worst = maxf(worst, dh)
			steps += 1
			if dh > ChunkGenerator.ROAD_STEP * 0.25:
				steep += 1
		for i in lv.size():
			# Roads cut through rough relief (tors, towers) by design; measure the base,
			# levelled where a town flattens it.
			var sh := g.field.shape(pts[i].x, pts[i].y)
			var base := g._flatten(pts[i].x, pts[i].y, sh.x + sh.y, g._sites_for(pts[i])[0])
			cut = maxf(cut, base - lv[i])
			fills.append(lv[i] - base)
			if ar[i] == 1:
				air += 1
				held[Vector2i(int(floor(pts[i].x / ChunkGenerator.SIZE)), int(floor(pts[i].y / ChunkGenerator.SIZE)))] = true
	fills.sort()
	print("  roads %d, worst step %.2f m, steep %d/%d, deepest cut %.1f m, viaduct points %d, fill p50 %.1f p90 %.1f p99 %.1f max %.1f" % [roads.size(), worst, steep, steps, cut, air,
		fills[fills.size() / 2], fills[fills.size() * 9 / 10], fills[fills.size() * 99 / 100], fills[-1]])
	check(worst <= ChunkGenerator.ROAD_STEP * ChunkGenerator.ROAD_GRADE * 1.8 + 0.01, "roads never climb steeper than the steepest grade (worst %.2f m per step)" % worst)
	check(cut <= ChunkGenerator.ROAD_CUT + 0.01, "roads never cut deeper than %.0f m into a hill (%.1f)" % [ChunkGenerator.ROAD_CUT, cut])
	# Chunks a viaduct crosses get spans.
	var spans := 0
	var n := 0
	for k in held:
		if n >= 12:
			break
		n += 1
		for o in g.generate(k.x, k.y)["objects"]:
			if o["t"] == "bridge" and Bridge.is_viaduct(int(o.get("sp", 0))):
				spans += 1
	check(air == 0 or spans > 0, "viaducts carry roads over dips (%d spans in %d chunks)" % [spans, n])
	var m := Bridge.build(Bridge.pack_viaduct(24.0, 9.0, 2.0))
	check(m.get_surface_count() > 0 and absf(m.get_aabb().end.y - (9.0 + 1.0 + 0.92)) < 0.6, "a viaduct span climbs from end to end")

func test_bridges_meet_the_road() -> void:
	# Every bridge and viaduct near the origin comes down onto the road at its ends, in a
	# new world and an older one (towns and rivers reshape the land after roads are laid).
	var survey = load("res://tools/probe_bridges.gd")
	for tv in [ChunkGenerator.GEN_VERSION, 7]:
		var res: Dictionary = survey.survey(7, tv, 1)
		check(res["total"] >= 3 and res["bad"] == 0, "bridge ends meet the ground in v%d worlds (%d bridges, %d bad: %s)" % [tv, res["total"], res["bad"], str(res["lines"].filter(func(l): return l.ends_with("BAD")))])
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

func test_scenery_meshes() -> void:
	# Alien ruins in every form, the wayside markers and the fliers all build.
	var forms := {}
	for sp in range(1, 400, 7):
		var f: String = Flora.species("alien_ruin", sp)["form"]
		if forms.has(f):
			continue
		forms[f] = true
		var m := HiFlora.build("alien_ruin", sp, 0)
		check(m != null and m.get_surface_count() >= 2 and m.get_aabb().size.y > 2.0, "alien ruin '%s' builds (%s)" % [f, m.get_aabb().size if m else "null"])
	check(forms.size() == 5, "all five ruin forms seen (%s)" % [forms.keys()])
	# A xenolith circle collides with its blades, not a box: you can walk in to the core.
	var msp := 1
	while Flora.species("alien_ruin", msp)["form"] != "monoliths":
		msp += 1
	var mp := Flora.species("alien_ruin", msp)
	var rsh: Shape3D = ObjectLibrary.shape_of({"t": "alien_ruin", "sp": msp, "v": 0, "st": {}})[0]
	check(rsh is ConcavePolygonShape3D, "a ruin collides with its own shape")
	if rsh is ConcavePolygonShape3D:
		var faces: PackedVector3Array = rsh.get_faces()
		var sz: float = mp["size"]
		var gap := Vector3(cos(PI / float(mp["count"])), 0, sin(PI / float(mp["count"])))
		check(_ray_hit(faces, gap * 4.2 * sz + Vector3(0, 1.2, 0), gap * sz + Vector3(0, 1.2, 0)) == INF, "you can walk between the blades toward the core")
		check(_ray_hit(faces, Vector3(7.0 * sz, 1.0, 0), Vector3(3.0 * sz, 1.0, 0)) < INF, "the blades themselves are solid")
	# Ground clutter: kit pebbles (plus flowers, fungi or scrap) in a metre-square patch.
	for era in Eras.COUNT:
		var m := ObjectLibrary.get_mesh("clutter_%d" % era)
		var bb := m.get_aabb()
		var tris := 0
		for si in m.get_surface_count():
			tris += m.surface_get_array_index_len(si) / 3
		check(m.get_surface_count() >= 2 and bb.size.x < 1.3 and bb.size.z < 1.3 and bb.size.y < 0.6 and bb.size.y > 0.05, "era %d clutter is small kit pieces (%d surfaces, %s)" % [era, m.get_surface_count(), bb.size])
		check(tris < 700, "era %d clutter stays light (%d triangles)" % [era, tris])
		var stone: Material = m.surface_get_material(0)
		check(stone == Materials.get_mat("stone_w"), "era %d clutter pebbles use the photo stone" % era)
	for t in ["crystal_shard", "standing_stone", "beacon"]:
		var m := ObjectLibrary.get_mesh(t)
		check(m != null and m.get_surface_count() > 0 and m.get_aabb().size.y > 2.5, "%s builds (%s)" % [t, m.get_aabb().size if m else "null"])
	for era in 3:
		for nm in Creature.NAMES[era].get("bird", []):
			var bm := BirdModel.build({"name": nm, "col": Color(0.4, 0.3, 0.2), "col2": Color(0.6, 0.5, 0.4), "glow": 3, "has_glow": true}, era)
			var body: ArrayMesh = bm["body"]
			var wing: ArrayMesh = bm["wing"]
			check(body.get_surface_count() > 0 and wing.get_surface_count() > 0 and wing.get_aabb().size.x > 0.2, "%s has a body and wings" % nm)
	for kind in ["dome", "flat", "cone", "bell", "funnel", "shelf"]:
		check(HiFlora._cap_profile(kind, 0.1)[0].size() > 3, "mushroom cap '%s' has a profile" % kind)

## Landing pads: each ship stands on its struts within its pad, collides as a box you
## walk round, and can be salvaged; outposts beyond hamlets get one.
func test_ship_pads() -> void:
	for t in ShipPad.SHIPS:
		var m := ObjectLibrary.get_mesh(t)
		check(m != null and m.get_surface_count() >= 2, "%s builds" % t)
		var box := m.get_aabb()
		check(box.size.x <= ShipPad.PAD + 0.6 and box.size.z <= ShipPad.PAD + 0.6, "%s fits its pad (%s)" % [t, box.size])
		check(box.end.y > ShipPad.STRUTS + 1.5, "%s stands up off the pad (%.1f m)" % [t, box.end.y])
		check(ObjectLibrary.shape_of({"t": t, "st": {}})[0] is BoxShape3D, "%s collides" % t)
		check(Durability.total_items({"t": t, "s": 1.0, "e": Eras.SCIFI, "st": {}}) > 0, "%s can be salvaged" % t)
		check(ObjectLibrary.kind(t) == "structure" and ObjectLibrary.label(t).begins_with("Landed "), "%s is a structure (%s)" % [t, ObjectLibrary.label(t)])
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var pads := 0
	var outposts := 0
	for sz in range(-14, 15):
		for sx in range(-14, 15):
			var st := g.settlement_at(sx, sz)
			if st.is_empty() or st["era"] != Eras.SCIFI or int(st["size"]) < 1:
				continue
			outposts += 1
			for it in g.settlement_layout(st):
				if ShipPad.has(it["t"]):
					pads += 1
	check(outposts > 0 and pads == outposts, "each outpost beyond a hamlet has a landing pad (%d of %d)" % [pads, outposts])

## Livestock: a village's houses have cows, horses and dogs about them, real kit animals
## that keep near and don't run from you; open country has none.
func test_village_livestock() -> void:
	var houses := []
	for i in 3:
		houses.append({"i": i, "t": "cottage", "e": Eras.MEDIEVAL, "p": Vector3(20 + i * 9, 4, 30), "r": 0.0, "s": 1.0, "st": {}})
	var village := {"cx": 2, "cz": 5, "era": Eras.MEDIEVAL, "biome": 1, "objects": houses}
	var stock := []
	for h in Creature.livestock_for(9, village):
		stock.append(h)
	check(stock.size() >= 3, "a village has livestock (%d)" % stock.size())
	var near := true
	var names := []
	for h in stock:
		var p := Creature.species(h["sp"], h["era"])
		names.append(p["name"])
		check(AnimalModel.available(p["kit"]) and p["temper"] == "tame", "%s is a tame kit animal (%s)" % [p["name"], p["kit"]])
		var best := INF
		for o in houses:
			best = minf(best, Vector2(o["p"].x - h["lx"], o["p"].z - h["lz"]).length())
		near = near and best < 10.0
	check(near, "livestock stand by the houses (%s)" % [names])
	check(var_to_bytes(Creature.livestock_for(9, village)) == var_to_bytes(Creature.livestock_for(9, village)), "the same animals every time")
	var wild := {"cx": 2, "cz": 5, "era": Eras.MEDIEVAL, "biome": 1, "objects": [houses[0]]}
	check(Creature.livestock_for(9, wild).is_empty(), "a lone house keeps no livestock")
	check(Creature.species(-201, Eras.FANTASY)["name"] == "Moon Mare", "fantasy villages keep their own breeds")

func test_town_walls() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var town := {}
	for r in 30:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if town.is_empty() and maxi(absi(sx), absi(sz)) == r:
					var s := g.settlement_at(sx, sz)
					if s.get("walled", false) and not g.road_crossings(s, float(s["inner"]) + 2.5).is_empty():
						town = s
	check(not town.is_empty(), "walled towns exist")
	if town.is_empty():
		return
	var lay := g.settlement_layout(town)
	var kinds := {}
	for it in lay:
		if Stronghold.has(it["t"]):
			kinds[it["t"]] = int(kinds.get(it["t"], 0)) + 1
	var rad := float(town["inner"]) + 2.5
	var ways := g.road_crossings(town, rad)
	check(kinds.get("castle_gate", 0) >= 1 and kinds.get("castle_gate", 0) <= maxi(1, ways.size()), "a gate per road (%s, %d roads)" % [kinds, ways.size()])
	check(kinds.get("castle_wall", 0) > 20 and kinds.get("castle_tower", 0) >= 2, "a ring of walls and towers (%s)" % [kinds])
	# Every road passes through a gate.
	var c: Vector2 = town["center"]
	for w in ways:
		var best := INF
		for it in lay:
			if it["t"] == "castle_gate":
				best = minf(best, (it["p"] as Vector2).distance_to(c + Vector2.from_angle(w) * rad))
		check(best < 3.0, "the road at %.2f rad goes through a gate (%.1f m off)" % [w, best])
	# Old worlds keep their open towns.
	WorldField.terrain_v = 5
	var old := ChunkGenerator.new(4242)
	check(not old.settlement_at(town["sx"], town["sz"]).get("walled", false), "v5 towns stay unwalled")
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

func test_strongholds() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var found := {}
	for cz in range(-6, 6):
		for cx in range(-6, 6):
			var f := Stronghold.at_cell(g, cx, cz)
			if not f.is_empty():
				found = f
				break
		if not found.is_empty():
			break
	check(not found.is_empty(), "strongholds exist")
	if found.is_empty():
		return
	var lay := Stronghold.layout(g, found)
	var kinds := {}
	for it in lay:
		kinds[it["t"]] = int(kinds.get(it["t"], 0)) + 1
	var pc: Array = Stronghold.PIECES[found["era"]]
	check(kinds.get(pc[1], 0) == 4 and kinds.get(pc[2], 0) == 1 and kinds.get(pc[3], 0) == 1 and kinds.get(pc[0], 0) == 11, "four towers, a gate, a keep and eleven walls (%s)" % [kinds])
	check(Stronghold.guards(found).size() == 1 + int(found["tier"]) * 2, "guards scale with the tier")
	# The chunk at the centre holds pieces and is flat across the courtyard.
	var c: Vector2 = found["center"]
	var ch := g.generate(int(floor(c.x / ChunkGenerator.SIZE)), int(floor(c.y / ChunkGenerator.SIZE)))
	var here := 0
	for o in ch["objects"]:
		if Stronghold.has(o["t"]):
			here += 1
	check(here > 0, "the centre chunk holds stronghold pieces")
	var lx: float = c.x - ch["cx"] * ChunkGenerator.SIZE
	var lz: float = c.y - ch["cz"] * ChunkGenerator.SIZE
	check(absf(ChunkGenerator.height_at(ch, lx, lz) - float(found["target_h"])) < 0.6, "the courtyard is levelled")
	var sp := Creature.guard_species(found["era"], 3)
	check(sp["temper"] == "aggressive" and float(sp["hp"]) > 120.0, "dread guards are tough (%s hp)" % sp["hp"])

func test_wonder_sites() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(777, true)
	var found: Dictionary = {}
	var tried := 0
	var picks := 0
	for wz in range(-4, 4):
		for wx in range(-4, 4):
			var pick := WonderSite.cell_pick(g.seed, wx, wz)
			tried += 1
			if pick.is_empty():
				continue
			picks += 1
			var k: Vector2i = pick[0]
			var ch := g.generate(k.x, k.y)
			if ch.has("wonder"):
				found = ch
				break
		if not found.is_empty():
			break
	var all := 0
	for wz in range(-6, 6):
		for wx in range(-6, 6):
			all += 0 if WonderSite.cell_pick(g.seed, wx, wz).is_empty() else 1
	check(all > 20 and all < 124, "about half the cells try for a wonder (%d of 144)" % all)
	check(not found.is_empty(), "a wonder turns up within a few cells")
	if found.is_empty():
		return
	var w: Dictionary = found["wonder"]
	var t: String = w["t"]
	var pillars := 0
	var centre := 0
	var vault := {}
	var hoards := 0
	for o in found["objects"]:
		if o["t"] == t:
			centre += 1
		elif o["t"] == WonderSite.PILLAR[t]:
			pillars += 1
		elif o["st"].has("seal"):
			vault = o
		elif o["st"].has("wonder"):
			hoards += 1
	check(centre == 1 and pillars == 8 and hoards == 3, "a centrepiece, eight pillars and three hoards (%d, %d, %d)" % [centre, pillars, hoards])
	check(not vault.is_empty() and WonderSite.sealed(found, vault), "the vault is sealed")
	var top := 0
	for it in vault.get("st", {}).get("loot", []):
		if it.has("rarity") and int(it["rarity"]) >= Rarity.LEGENDARY:
			top += 1
	check(top >= 2, "the vault holds at least two legendary pieces (%d)" % top)
	# Nothing grows on the plaza and it is level.
	var c := Vector2(w["lx"], w["lz"])
	var h0 := ChunkGenerator.height_at(found, c.x, c.y)
	var flat := true
	for a in 8:
		var q := c + Vector2.from_angle(a * TAU / 8.0) * 12.0
		flat = flat and absf(ChunkGenerator.height_at(found, q.x, q.y) - h0) < 0.6
	check(flat, "the plaza is level")
	var trees := 0
	for o in found["objects"]:
		if ObjectLibrary.kind(o["t"]) == "tree" and Vector2(o["p"].x, o["p"].z).distance_to(c) < WonderSite.PLAZA:
			trees += 1
	check(trees == 0, "no trees on the plaza")
	# Guards: elites and one boss, which unseals the vault when it dies.
	var boss := {}
	var elites := 0
	for gd in found["guards"]:
		if int(gd["tier"]) >= 100:
			boss = gd
		elif int(gd["tier"]) >= 4:
			elites += 1
	check(elites >= 4 and not boss.is_empty(), "elite guards and a boss")
	var bp := Creature.species(-int(boss["tier"]), int(boss["era"]))
	check(bp.has("boss") and float(bp["hp"]) >= 1000.0 and Creature.level_of(bp) == 60, "the boss is level 60 with %d hp" % bp["hp"])
	var ep := Creature.species(-5, 0)
	check(float(ep["hp"]) > float(Creature.species(-3, 0)["hp"]) and String(ep["name"]).begins_with("Mythic"), "wonder guards outclass stronghold guards")
	found["fauna_dead"] = {boss["id"]: 1.0}
	check(not WonderSite.sealed(found, vault), "the vault opens once the boss is dead")
	# Same seed, same wonder.
	var again := g.generate(int(found["cx"]), int(found["cz"]))
	check(again.get("wonder", {}).get("t", "") == t, "wonders are deterministic")

func test_wonder_meshes() -> void:
	BuildCatalog.warm_kits()
	for t in WonderSite.LABELS:
		var m := WonderSite.build(t)
		check(m != null and m.get_surface_count() > 0, "%s has a mesh" % t)
		check(ObjectLibrary.kind(t) == "structure" and Wonders.unbreakable(t), "%s is an unbreakable structure" % t)
	var solid := WonderSite.build("w_gate", true)
	check(solid.get_surface_count() < WonderSite.build("w_gate").get_surface_count(), "the gate's collision leaves out its light and portal")
	# Human worlds: nothing on the wonders they can have glows, not even the locator beam.
	for t in ["w_throne", "w_dreadnought"]:
		check(_beam_surfaces(WonderSite.build(t, false, true)) == 0, "a human world's %s has no beam of light" % t)
	check(_beam_surfaces(WonderSite.build("w_throne")) > 0, "an alien world's throne keeps its beam")
	for t in ["w_throne", "w_dreadnought", "w_column", "w_pylon"]:
		var calm := WonderSite.build(t, true, true)
		var lit := 0
		for i in calm.get_surface_count():
			var mat := calm.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				lit += 1
		check(lit == 0, "a human world's %s has nothing glowing (%d lit surfaces)" % [t, lit])
	var o := {"t": "w_throne"}
	var was := Eras.theme
	Eras.theme = "human"
	check(ObjectLibrary.mesh_key(o) == "w_throne" + WonderSite.CALM, "human worlds use the calm wonder mesh")
	Eras.theme = "alien"
	check(ObjectLibrary.mesh_key(o) == "w_throne", "alien worlds keep the glow")
	Eras.theme = was


func _beam_surfaces(m: ArrayMesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i) as StandardMaterial3D
		if mat != null and mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			n += 1
	return n

## Nothing grows through a floor: trees, rocks, caches and markers keep out of every
## building's ground plan, including a neighbour chunk's building reaching in.
func test_keep_out() -> void:
	var plan := [ChunkGenerator._plan(10.0, 10.0, PI / 2.0, Vector2(-1, -3), Vector2(1, 3))]
	check(ChunkGenerator.kept_out(plan, 12.5, 10.0, 0.0), "a turned plan covers its long side")
	check(not ChunkGenerator.kept_out(plan, 10.0, 7.5, 0.0), "and not past its short side")
	check(ChunkGenerator.kept_out(plan, 10.0, 8.8, 0.3), "a margin widens it")
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var picked := {}
	for sz in range(-10, 11):
		for sx in range(-10, 11):
			var st := g.settlement_at(sx, sz)
			if not st.is_empty() and not picked.has(st["era"]) and int(st["size"]) >= 1:
				picked[st["era"]] = st
	check(picked.size() >= 2, "settlements of several eras to look at (%d)" % picked.size())
	var reach := 0
	var inside: Array = []
	var looked := 0
	for st in picked.values():
		var c: Vector2 = st["center"]
		var ccx := int(floor(c.x / ChunkGenerator.SIZE))
		var ccz := int(floor(c.y / ChunkGenerator.SIZE))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var ch := g.generate(ccx + dx, ccz + dz)
				var plans := ChunkGenerator.keep_out(ch)
				reach += (ch["keep_out"] as PackedFloat32Array).size() / 7
				for o in ch["objects"]:
					var k := ObjectLibrary.kind(o["t"])
					if k == "tree" or k == "rock" or k == "ore" or k == "marker" or (k == "cache" and not o["st"].has("landmark")):
						looked += 1
						if ChunkGenerator.kept_out(plans, o["p"].x, o["p"].z, 0.3):
							var by := "a neighbour"
							for b in ch["objects"]:
								if ObjectLibrary.keeps_out(b["t"]):
									var f := ObjectLibrary.footprint(b)
									if ChunkGenerator.kept_out([ChunkGenerator._plan(b["p"].x, b["p"].z, b["r"], f.position, f.end)], o["p"].x, o["p"].z, 0.3):
										by = b["t"]
							inside.append("%s in %s at (%.1f, %.1f)" % [o["t"], by, o["p"].x, o["p"].z])
				if dx == 0 and dz == 0:
					var again := ch.duplicate()
					again.erase("keep_out")
					check(g.fill_keep_out(again) and again["keep_out"] == ch["keep_out"], "chunks saved before keep the same plans when loaded (%d)" % (ch["keep_out"] as PackedFloat32Array).size())
	check(looked > 20 and inside.is_empty(), "nothing wild stands inside a building (%d looked at, %s)" % [looked, inside])
	check(reach > 0, "buildings reaching in from the next chunk are kept out too (%d)" % reach)

## Floors drawn twice at one height flicker: the sci-fi blocks' foundations sit under
## their floor tiles, and plates and forks sit on the table rather than in it.
func test_no_double_floors() -> void:
	for t in ["hab_block", "lab_block", "ops_tower", "bunker_keep", "bunker_tower"]:
		var low: Array = []
		for f in ZFight.find(t):
			var y := float(f.get_slice(" at y ", 1).get_slice(" ", 0))
			if y < 0.5:
				low.append(f)
		check(low.is_empty(), "%s has one floor (%s)" % [t, low])
	for t in KitHouse.FURNISH.keys() + Interiors.FURNISH.keys():
		var hits := ZFight.items(t)
		check(hits.is_empty(), "%s's furniture doesn't sink into each other (%s)" % [t, hits])

static func _species_named(name: String, era: int) -> Dictionary:
	for sp in range(1, 4000):
		var p := Creature.species(sp, era)
		if p["name"] == name:
			return p
	return {}

func test_death_bag() -> void:
	var inv := Inventory.new()
	inv.add(ItemDB.make("bread", 4, 1.0, {}))
	inv.add(ItemDB.make("sword_iron", 1, 1.0, {}))
	var armour := ""
	for t in ItemDB.ITEMS:
		if ItemDB.def(t).get("kind", "") == "armor":
			armour = t
			break
	var worn := ItemDB.make(armour, 1, 1.0, {})
	worn["uid"] = 77
	var slot: String = ItemDB.def(armour)["slot"]
	var bag := DeathBag.make("p1", "", inv, {slot: worn}, 120, 1000.0)
	var held := Inventory.new(DeathBag.SLOTS)
	held.from_data(bag["items"])
	check(held.count("bread") == 4 and held.count("sword_iron") == 1 and held.count(armour) == 1, "the bag holds the pack and the armour")
	check(int(bag["purse"]) == 120 and int(bag["worn"][slot]) == 77, "the bag keeps the purse and what was worn where")
	check(CorpseLoot.has_any(bag) and not CorpseLoot.has_any(DeathBag.make("p1", "", Inventory.new(), {}, 0, 0.0)), "an empty pack drops nothing worth keeping")
	check(DeathBag.SLOTS >= Inventory.SIZE + 7, "a full pack and full armour fit in a bag")
	check(DeathBag.title(bag, "p1") == "Your bag" and DeathBag.title(bag, "p2") == "Someone's bag", "your bag and someone else's")
	bag["owner_name"] = "Ada Smith"
	check(DeathBag.title(bag, "p2") == "Ada's bag", "a named player's bag")
	check(not DeathBag.expired(bag, 1.0e12), "bags never go away by default")
	DeathBag.lifetime_s = 3.0 * 86400.0
	check(not DeathBag.expired(bag, 1000.0 + 86400.0) and DeathBag.expired(bag, 1000.0 + 4.0 * 86400.0), "a server can make bags last a few days")
	DeathBag.lifetime_s = 0.0
	check(DeathBag.can_take(bag, "p2"), "anyone may open a bag")
	DeathBag.may_take = func(c: Dictionary, who: String) -> bool: return who == c["owner"]
	check(DeathBag.can_take(bag, "p1") and not DeathBag.can_take(bag, "p2"), "a server can say who may open it")
	DeathBag.may_take = Callable()
	# Where it lands: land rises to the east (x > 20 is dry), the sea is at 0.
	var ground := func(x: float, _z: float) -> float: return (x - 20.0) * 0.5
	var water := func(_x: float, _z: float) -> float: return 0.0
	var dry := DeathBag.rest_spot(Vector3(30, 5, 0), ground, water)
	check(dry == Vector3(30, 5, 0), "on dry ground the bag stays where you fell")
	var shore := DeathBag.rest_spot(Vector3(0, -10, 0), ground, water)
	check(shore.y >= DeathBag.DRY_MARGIN and shore.x > 20.0 and shore.x < 30.0, "drowned: the bag washes up on the nearest shore (%s)" % shore)
	var cave := DeathBag.rest_spot(Vector3(0, 12, 0), ground, water)
	check(cave == Vector3(0, 12, 0), "a floor above the water (a cave, a room) keeps the bag")
	var sea := DeathBag.rest_spot(Vector3(0, -10, 0), func(_x: float, _z: float) -> float: return -30.0, water)
	check(sea == Vector3(0, 0, 0), "far out at sea it floats where you went down")

func test_corpse_butchering() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wolf := _species_named("Grey Wolf", Eras.MEDIEVAL)
	check(not wolf.is_empty(), "a grey wolf species exists")
	var ys := CorpseLoot.animal_yields(wolf, 0.7, 0.0, rng)
	var got := {}
	for y in ys:
		got[y[0]] = y[1]
	check(got.get("raw_meat", 0) >= 1, "a fresh wolf gives meat")
	check(got.get("fur_pelt", 0) >= 1 and not got.has("hide"), "a wolf is skinned for a fur pelt")
	check(got.get("bone", 0) >= 1, "carcasses give bone")
	for t in got:
		check(ItemDB.has(t), "yield %s is a real item" % t)
	# A skinning knife gets more than bare hands; a rotten carcass gives no meat.
	var knife := {}
	for y in CorpseLoot.animal_yields(wolf, 1.5, 0.0, rng):
		knife[y[0]] = y[1]
	var bare := {}
	for y in CorpseLoot.animal_yields(wolf, 0.0, 0.0, rng):
		bare[y[0]] = y[1]
	check(knife.get("raw_meat", 0) > bare.get("raw_meat", 0) and knife.get("fur_pelt", 0) > bare.get("fur_pelt", 0), "a knife yields more than bare hands")
	var rot := {}
	for y in CorpseLoot.animal_yields(wolf, 0.7, CorpseLoot.ROT_DAYS + 0.1, rng):
		rot[y[0]] = y[1]
	check(not rot.has("raw_meat") and not rot.has("animal_fat") and rot.get("bone", 0) >= 1, "spoiled carcass: no meat or fat, bones remain")
	var elk := _species_named("Elk", Eras.MEDIEVAL)
	if not elk.is_empty():
		var e := {}
		for y in CorpseLoot.animal_yields(elk, 0.7, 0.0, rng):
			e[y[0]] = y[1]
		check(e.get("antler", 0) == 2 and e.has("hide") and e.has("animal_fat"), "an elk gives antlers, hide and fat")
	check(CorpseLoot.blade_of({"type": "skinning_knife"}) > CorpseLoot.blade_of({"type": "sword_iron"}), "knife beats sword at skinning")
	check(CorpseLoot.blade_of({"type": "crossbow"}) == 0.0 and CorpseLoot.blade_of(null) == 0.0, "no blade, no skinning bonus")
	check(CorpseLoot.butcher_time(wolf, 1.5) < CorpseLoot.butcher_time(wolf, 0.0), "a knife butchers faster")
	check(CorpseLoot.is_machine(Creature.guard_species(Eras.SCIFI, 1)) == (Eras.theme != "human"), "sci-fi crawlers are salvaged, not butchered")
	# People's bodies: what they wore, held and carried.
	var rec := {"gear": {"head": {"type": "helm_iron", "qty": 1, "quality": 1.0}}, "held": {"type": "dagger", "qty": 1, "quality": 1.1}}
	var items := CorpseLoot.person_items(rec, [ItemDB.make("bread", 2, 1.0, {})], {"how": "looted"})
	check(items.size() == 3, "body holds gear, held item and pockets")
	var inv := Inventory.new(CorpseLoot.SLOTS)
	for it in items:
		check(inv.add(it) == 0, "body item fits")
	var body := {"kind": "person", "day": 1.0, "items": inv.to_data(), "purse": 0}
	check(CorpseLoot.has_any(body), "a body with items has something to take")
	check(not CorpseLoot.expired(body, 1.0 + CorpseLoot.PERSON_GONE_DAYS - 0.1) and CorpseLoot.expired(body, 1.0 + CorpseLoot.PERSON_GONE_DAYS), "bodies decay on time")
	check(CorpseLoot.has_any({"kind": "animal", "butchered": false}), "an unbutchered carcass can be used")
	check(not CorpseLoot.has_any({"kind": "animal", "butchered": true, "items": Inventory.new(4).to_data()}), "a picked-clean carcass is done")

func test_corpses_persist_in_chunk() -> void:
	var s := _tmp_store("corpses")
	var g := ChunkGenerator.new(4321)
	var c := s.get_or_create_chunk(g, 1, 1)
	var inv := Inventory.new(CorpseLoot.SLOTS)
	inv.add(ItemDB.make("raw_meat", 3, 1.0, {}))
	c["corpses"] = {"a1_1_0": {"kind": "animal", "sp": 5, "era": 0, "p": Vector3(10, 4, 12), "yaw": 1.0, "day": 2.5, "name": "Elk", "butchered": true, "items": inv.to_data()}}
	s.save_chunk(c)
	var again := s.get_or_create_chunk(ChunkGenerator.new(1), 1, 1)
	var k: Dictionary = again.get("corpses", {}).get("a1_1_0", {})
	check(not k.is_empty(), "carcass survives a reload")
	check(k.get("p") == Vector3(10, 4, 12) and k.get("butchered", false), "carcass keeps its place and butchered state")
	var back := Inventory.new(CorpseLoot.SLOTS)
	back.from_data(k["items"])
	check(back.count("raw_meat") == 3, "what was left on the carcass stays on it")

func test_cave_networks() -> void:
	var was := WorldField.terrain_v
	WorldField.terrain_v = 8
	var old := ChunkGenerator.new(4242, true)
	var oc := old.generate(3, 1)
	check(not oc.has("cave") and not oc.has("hole"), "worlds before v10 keep their old caves")
	WorldField.terrain_v = 10
	var g := ChunkGenerator.new(4242, true)
	var nets: Array = []
	for sz in range(-2, 2):
		for sx in range(-2, 2):
			var n := Caves.network(g, sx, sz)
			if not n.is_empty():
				nets.append(n)
	check(nets.size() >= 3, "cave networks are common in hilly worlds (%d of 16 cells)" % nets.size())
	if nets.is_empty():
		WorldField.terrain_v = was
		return
	var net: Dictionary = nets[0]
	var mo: Vector3 = net["mouth"]
	var ps: PackedFloat32Array = net["prims"]
	var lowest := INF
	var reach := 0.0
	for i in ps.size() / Caves.STRIDE:
		var o := i * Caves.STRIDE
		if int(ps[o]) == Caves.TUNNEL:
			lowest = minf(lowest, minf(ps[o + 9], ps[o + 10]))
			reach = maxf(reach, Vector2(ps[o + 4] - mo.x, ps[o + 6] - mo.z).length())
	check(lowest >= Caves.MIN_FLOOR - 0.01, "cave floors stay above the water table (%f)" % lowest)
	check(reach > 50.0, "a network reaches far from its mouth (%.0f m)" % reach)
	var big := 0.0
	for ch in net["chambers"]:
		big = maxf(big, float(ch["rx"]))
		var cc: Vector3 = ch["p"]
		check(Caves.sdf(ps, cc) < 0.0, "chamber centres are open")
	check(big > 8.0, "chambers are roomy (widest %.1f m)" % big)
	# The mouth's chunk opens the ground, and the cave is meshed with collision.
	var mc := Vector2i(int(floor(mo.x / ChunkGenerator.SIZE)), int(floor(mo.z / ChunkGenerator.SIZE)))
	var ch := g.generate(mc.x, mc.y)
	check(ch.has("cave") and ch.has("hole"), "the mouth's chunk keeps its cave and opening")
	var again := ChunkGenerator.new(4242, true).generate(mc.x, mc.y)
	check(again.get("cave") == ch.get("cave") and again.get("hole") == ch.get("hole"), "caves are deterministic")
	check(ChunkGenerator.in_cave(ch, mo.x - mc.x * ChunkGenerator.SIZE, mo.z - mc.y * ChunkGenerator.SIZE), "nothing grows in the mouth")
	var res := Caves.build(ch)
	check(not res.is_empty() and (res["faces"] as PackedVector3Array).size() > 300, "cave walls are meshed (%d)" % (0 if res.is_empty() else (res["faces"] as PackedVector3Array).size()))
	# Everything placed underground sits in open cave air, on its floor.
	var under := 0
	for sz in range(mc.y - 3, mc.y + 4):
		for sx in range(mc.x - 3, mc.x + 4):
			var c := g.generate(sx, sz)
			if not c.has("cave"):
				continue
			for o in c["objects"]:
				var p: Vector3 = o["p"]
				if p.y < ChunkGenerator.height_at(c, p.x, p.z) - 3.0:
					under += 1
					var wp := p + Vector3(sx * ChunkGenerator.SIZE, 0.5, sz * ChunkGenerator.SIZE)
					check(Caves.sdf(c["cave"], wp) < 0.0, "%s underground is in the open" % o["t"])
	check(under > 3, "caves hold ore, crystals or loot (%d)" % under)
	# Nothing glows on human worlds.
	var was_theme := Eras.theme
	Eras.theme = "human"
	var hg := ChunkGenerator.new(4243, true)
	var glows := 0
	var crystals := 0
	for sz in range(-6, 6):
		for sx in range(-6, 6):
			for o in hg.generate(sx, sz)["objects"]:
				glows += int(o["t"] == "cave_glow")
				crystals += int(o["t"] == "cave_crystal")
	check(glows == 0 and crystals > 0, "human worlds' cave crystals give no light (%d glowing, %d plain)" % [glows, crystals])
	check(Caves.lights({"t": "cave_crystal", "v": 0}).is_empty(), "plain crystals carry no lamp")
	Eras.theme = was_theme
	WorldField.terrain_v = was

func test_treasure_maps() -> void:
	check(ItemDB.def("treasure_map").get("kind", "") == "map" and not ItemDB.is_stackable("treasure_map"), "a treasure map is its own item")
	check(Treasure.map_for(Eras.MEDIEVAL) == "treasure_map" and Treasure.map_for(Eras.SCIFI) == "treasure_chip", "parchment in the old lands, a data chip on the frontier")
	# A buried chest holds five or six ordinary caches' worth.
	var worth := func(loot: Array) -> int:
		var w := 0
		for it in loot:
			w += int(it["qty"]) if it["type"] == "_marks" else int(ItemDB.def(it["type"]).get("value", 1)) * int(it["qty"])
		return w
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var one := 0
	var chest := 0
	for i in 40:
		one += worth.call(ItemDB.roll_loot(Eras.MEDIEVAL, r, {"chunk": Vector2i(2, 2)}, Treasure.LUCK))
		var t := Treasure.roll_loot(Eras.MEDIEVAL, r, Vector2i(2, 2))
		chest += worth.call(t)
		var types := {}
		for it in t:
			check(not Treasure.is_map(it["type"]), "no maps inside treasure")
			if ItemDB.is_stackable(it["type"]) or it["type"] == "_marks":
				check(not types.has(it["type"]), "stacks in a chest are merged")
				types[it["type"]] = true
	check(chest > one * 4 and chest < one * 7, "a treasure chest is worth 5-6 caches (%d vs %d)" % [chest, one])
	# The spot: a few hundred metres to a kilometre off, on open dry land.
	var g := ChunkGenerator.new(5150)
	r.seed = 7
	var h := Treasure.new_hunt(1, g, Vector2(10, 20), 0, r)
	var d := Vector2(h["x"], h["z"]).distance_to(Vector2(10, 20))
	check(d >= Treasure.MIN_DIST and d <= Treasure.MAX_DIST, "the X is %d m away" % d)
	check(Treasure.open_land(g, Vector2(h["x"], h["z"])), "on open dry land")
	check(not (h["loot"] as Array).is_empty() and not h["found"], "the hunt knows what's in the chest")
	# Buried in its chunk under a mound of turned soil; dig and it can be opened.
	var k := Treasure.chunk_of(h)
	var c := g.generate(k.x, k.y)
	var ground := ChunkGenerator.height_at(c, float(h["x"]) - k.x * 64.0, float(h["z"]) - k.y * 64.0)
	var lp := Treasure.burial(c, h)
	check(lp.x >= Treasure.EDGE and lp.x <= 64.0 - Treasure.EDGE and lp.z >= Treasure.EDGE and lp.z <= 64.0 - Treasure.EDGE, "the chest lies inside its chunk")
	var before := ChunkGenerator.height_at(c, lp.x, lp.z)
	check(absf(before - Treasure.DEPTH - lp.y) < 0.01, "%.1f m under the ground" % Treasure.DEPTH)
	Treasure.dress(c, lp)
	check(ChunkGenerator.height_at(c, lp.x, lp.z) > before + 0.1 and ChunkGenerator.road_at(c, lp.x, lp.z) > 0.5, "turned soil heaps over it")
	var o := {"i": c["objects"].size(), "t": "chest", "p": lp, "r": 0.0, "s": 1.0, "e": 0, "st": {"loot": h["loot"], "opened": false, "treasure": 1}}
	c["objects"].append(o)
	check(Treasure.covered(c, o) and Treasure.chest_in(c, 1) == o and Treasure.chest_in(c, 2).is_empty(), "the chest starts buried")
	var hs: PackedFloat32Array = c["heights"]
	for j in range(int(lp.z) - 2, int(lp.z) + 3):
		for i in range(int(lp.x) - 2, int(lp.x) + 3):
			hs[j * ChunkGenerator.RES + i] = minf(hs[j * ChunkGenerator.RES + i], lp.y)
	c["heights"] = hs
	check(not Treasure.covered(c, o), "dug down to, it can be opened")
	check(not Treasure.covered(c, {"p": lp, "st": {}}), "ordinary caches are never buried")
	# The snapshot keeps chest, mound and hole.
	var s := _tmp_store("treasure")
	s.save_chunk(c)
	var back = s.load_chunk(k.x, k.y)
	check(back is Dictionary and int(Treasure.chest_in(back, 1).get("st", {}).get("treasure", -1)) == 1 and absf(ChunkGenerator.height_at(back, lp.x, lp.z) - lp.y) < 0.01, "the snapshot keeps the chest and the dig")
	check(Treasure.compass(Vector2(0, -5)) == "north" and Treasure.compass(Vector2(5, 5)) == "south-east", "compass directions")
	check(Treasure.hint(h, Vector3(h["x"], 0, h["z"] + 500.0)).contains("north"), "the map says which way to go")
	check(ground == ground, "ground sampled")

## The frontier age (pack B): guns have handling and real ammo, explosives burst, traps
## keep their place in a save, rare finds are never plain, and gear stays near its zone.
func test_pack_b_items() -> void:
	for t in ["flintlock_pistol", "musket", "blunderbuss", "revolver_six", "lever_rifle", "double_shotgun", "bolt_rifle",
			"derringer", "flare_gun", "harpoon_gun", "gatling", "elephant_gun"]:
		var d := ItemDB.def(t)
		check(ItemDB.has(String(d.get("ammo", ""))), "%s fires a real item (%s)" % [t, d.get("ammo", "")])
		check(int(d["era"]) == Eras.SCIFI and ItemDB.UNLOCK.get(t, 0) >= 10 and ItemDB.UNLOCK.get(t, 0) <= 25, "%s is a level 10-25 frontier gun" % t)
	check(int(ItemDB.def("double_shotgun").get("pellets", 1)) > 1, "a shotgun throws pellets")
	for t in ["dynamite", "frag_grenade", "powder_keg", "fire_bottle"]:
		var d := ItemDB.def(t)
		check(d.get("thrown", false) and d.has("splash") and d["ammo"] == t, "%s is thrown and bursts" % t)
	check(not Rarity.is_gear("dynamite"), "a stack of dynamite has no rank")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 20:
		check(Rarity.of(ItemDB.make("gatling", 1, 1.0, {}, rng)) >= Rarity.EPIC, "a gatling is never plain")
	# Traps: saved and restored where they were set.
	var tr := Traps.new()
	tr.add("bear_trap", Vector3(1, 2, 3))
	tr.add("tripwire", Vector3(-4, 0.5, 9))
	var back := Traps.new()
	back.from_data(JSON.parse_string(JSON.stringify(tr.to_data())))
	check(back.count() == 2 and back.to_data()[1]["type"] == "tripwire", "traps come back from a save")
	back.from_data([{"type": "not_an_item", "pos": [0, 0, 0]}, {"type": "bear_trap"}])
	check(back.count() == 0, "a broken trap record is dropped")
	tr.free()
	back.free()
	for t in ["bear_trap", "tripwire"]:
		check(ItemDB.def(t).get("trap", {}).has("radius"), "%s has a trigger radius" % t)
	# Effects: oiled guns reload faster; an ammo belt too; a diving helm holds breath.
	var st := Stats.new()
	var r0 := st.reload_mult()
	st.bonus = Effects.bonus({"back": {"type": "ammo_belt"}}, {"oiled": 60.0})
	check(st.reload_mult() > r0 + 0.4, "ammo belt and gun oil speed reloading (%.2f)" % st.reload_mult())
	var b0 := st.max_breath()
	st.bonus = Effects.bonus({"head": {"type": "helm_brass"}}, {})
	check(st.max_breath() >= b0 + 60.0, "a diving helm holds your breath longer")
	check(ItemDB.def("hardhat_lamp").get("lamp", false), "the miner's helmet has a lamp")
	check(Effects.describe(ItemDB.def("gun_oil")).size() > 0 and Effects.describe(ItemDB.def("bear_trap")).size() > 0, "kits and traps say what they do")
	# Loot out in the frontier zones is frontier gear, not stone knives or level-40 kit.
	var was := Eras.theme
	Eras.theme = "human"
	var lv_ok := true
	var seen := 0
	for i in 200:
		rng.seed = 900 + i
		# Zone level 15: about 2.1 km out.
		for it in ItemDB.roll_loot(Eras.SCIFI, rng, {"chunk": Vector2i(33, 0)}, 0.2):
			if Rarity.is_gear(it["type"]):
				seen += 1
				if ItemDB.unlock_level(it["type"]) > 22:
					lv_ok = false
	Eras.theme = was
	check(seen > 10 and lv_ok, "frontier caches hold gear near their level (%d pieces)" % seen)
	# A lantern of either kind lights up.
	var inv := Inventory.new()
	inv.add(ItemDB.make("lamp_kerosene", 1, 1.0, {}))
	check(HandLight.lanterns(inv) == 1, "a kerosene lamp counts as a lantern")

# --- Multiplayer -------------------------------------------------------------------------

class FakeNet:
	var sent: Array = []
	func rs_send_chunk(p, c): sent.append(["chunk", p, c["cx"], c["cz"]])
	func rs_send_player(d): sent.append(["player", d])
	func rs_request_town(p, site): sent.append(["town?", p, site["sx"], site["sz"]])
	func rs_send_town(p, s): sent.append(["town", p, s["sx"]])

func test_server_config() -> void:
	var c := ServerConfig.new()
	c.apply_args(PackedStringArray(["--name=My World", "--port=25001", "--max-players=4", "--password=pw",
		"--set", "pvp=off", "--set=time=night", "--set", "xp_mult=2.5", "--set", "time=noon", "--ignored"]))
	check(c.name == "My World" and c.port == 25001 and c.max_players == 4 and c.password == "pw", "flags set the server")
	check(c.options["pvp"] == false and c.options["time"] == "night" and is_equal_approx(c.options["xp_mult"], 2.5), "--set changes options")
	check(c.set_option("time", "noon") != "" and c.options["time"] == "night", "bad choices are refused")
	check(c.set_option("nope", "1") != "" and c.set_option("pvp", "maybe") != "", "unknown options and bad values are refused")
	var dir := "user://test_server_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	c.description = 'Quotes "and" back\\slashes'
	check(c.write_file(dir.path_join("server.cfg")), "server.cfg written")
	var d := ServerConfig.new()
	d.read_file(dir.path_join("server.cfg"))
	check(d.name == "My World" and d.description == c.description and d.port == 25001 and d.password == "pw", "server.cfg reads back (%s)" % d.description)
	check(d.options["pvp"] == false and d.options["time"] == "night" and is_equal_approx(d.options["xp_mult"], 2.5), "options read back")
	var e := ServerConfig.load_from(PackedStringArray(["--port=26000"]), dir)
	check(e.port == 26000 and e.name == "My World", "flags beat the file")
	var i := c.info(3)
	check(i["players"] == 3 and i["max_players"] == 4 and i["password"] == true and i["protocol"] == ServerConfig.PROTOCOL, "server info for the browser")

func test_identity_names() -> void:
	check(Identity.clean_name("  Ben  ") == "Ben", "names are trimmed")
	check(Identity.clean_name("A<b>[c]") == "Abc", "markup is stripped")
	check(Identity.clean_name("x".repeat(40)).length() == 20, "names are capped")
	check(Identity.valid_name("Sir Ben") and not Identity.valid_name("B") and not Identity.valid_name("<x>"), "valid names")
	Identity.override = "user://test_identity_%d.cfg" % Time.get_ticks_usec()
	var a := Identity.load_or_make()
	check(a["token"].length() == 64 and Identity.load_or_make()["token"] == a["token"], "the secret token is made once")
	Identity.remember_name("Ben")
	check(Identity.load_or_make()["name"] == "Ben", "the name is remembered")
	check(Identity.token_key(a["token"]) != a["token"] and Identity.token_key(a["token"]).length() == 64, "servers keep a hash, not the token")
	Identity.override = ""

func test_net_pack() -> void:
	var c := ChunkGenerator.new(55).generate(1, 2)
	var b := NetPack.pack(c)
	check(b.size() < var_to_bytes(c).size(), "chunks are compressed on the wire")
	var back = NetPack.unpack(b)
	check(back is Dictionary and back["heights"] == c["heights"] and back["objects"].size() == c["objects"].size(), "chunks round-trip")
	var bomb := PackedByteArray()
	bomb.resize(4)
	bomb.encode_u32(0, 512 * 1024 * 1024)
	bomb.append_array(PackedByteArray([1, 2, 3]))
	check(NetPack.unpack(bomb) == null, "oversized payloads are refused")
	check(NetPack.unpack(PackedByteArray([9, 9])) == null, "garbage is refused")

func test_remote_store() -> void:
	var net := FakeNet.new()
	var s := RemoteStore.new("user://test_remote_%d" % Time.get_ticks_usec(), {"seed": 5, "gen_version": ChunkGenerator.GEN_VERSION})
	s.net = net
	s.set_planet(0)
	check(not s.has_chunk(3, 4) and s.load_chunk(3, 4) == null, "nothing cached yet")
	var c := ChunkGenerator.new(5).generate(3, 4)
	s.deliver_chunk(0, c)
	check(s.has_chunk(3, 4) and s.load_chunk(3, 4) == c, "a delivered chunk is cached")
	check(s.get_or_create_chunk(ChunkGenerator.new(5), 3, 4) == c, "a cached chunk is served without asking")
	s.save_chunk(c)
	check(net.sent.size() == 1 and net.sent[0][0] == "chunk", "an edit goes to the server")
	s.closed = true
	var fallback := s.get_or_create_chunk(ChunkGenerator.new(5), 9, 9)
	check(fallback.has("heights") and not s.has_chunk(9, 9), "a closed connection never hangs a loader")
	s.closed = false
	var site := {"sx": 2, "sz": -1}
	check(not s.prefetch_settlement(site) and net.sent[-1][0] == "town?", "a town is asked for once")
	var n := net.sent.size()
	s.prefetch_settlement(site)
	check(net.sent.size() == n, "and not again while it is on its way")
	s.deliver_town(0, {"sx": 2, "sz": -1, "npcs": []})
	check(s.prefetch_settlement(site) and s.has_settlement(2, -1), "then it is ready")
	s.save_player({"money": 3})
	check(net.sent[-1][0] == "player" and s.load_player()["money"] == 3, "your save goes to the server")
	s.save_meta()
	check(not FileAccess.file_exists(s.root.path_join("world.dat")), "clients never write the world's meta")
