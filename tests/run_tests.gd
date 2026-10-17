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
		check(NPCMind.TALK_ACTIONS.has(a) or a in ["idle", "wander", "work", "socialize", "sleep", "greet", "confront"] , "action known: " + a)

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
	check(a == "none", "non-traders cannot open trade")
	check(int(p["rel"]) == 10, "relationship change clamped per exchange")
	check(p["mood"] == "happy", "mood applied")
	var t: Dictionary = s["npcs"][0]
	check(NPCMind.builtin_reply(t, s, "Can we trade?")["action"] == "trade", "built-in trader trades")
	var sys := NPCMind.system_prompt(p, s, {"held": "Iron Sword"})
	check(sys.contains(p["name"]) and sys.contains("Iron Sword") and sys.contains("JSON"), "prompt carries persona, context and format")

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

func test_kit_flora() -> void:
	for t in ["oak", "pine"]:
		for sp in range(1, 40):
			var p := Flora.species(t, sp)
			var n := KitFlora.model_name(t, p, sp, 0)
			check(n != "" and ResourceLoader.exists(KitFlora.DIR + n + ".gltf"), "%s species %d has a kit model (%s)" % [t, sp, n])
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
			check(d.get("slot", "") in ["head", "chest", "hands", "legs", "feet", "shield"], "%s has a slot" % t)
			check(float(d.get("armor", 0)) > 0.0, "%s protects" % t)
			slots[d["slot"]] = true
	check(slots.size() == 6, "armour for every slot")
	var helm := ItemDB.make("helm_iron", 1, 1.0, {})
	Rarity.apply(helm, Rarity.LEGENDARY, rng)
	check(float(ItemDB.stats(helm)["armor"]) > 8.0, "ranked armour protects more")
	for id in helm["affixes"]:
		check("armor" in Rarity.AFFIXES[id]["kinds"], "armour only gets armour abilities (%s)" % id)
	var craftable := {}
	for r in Recipes.LIST:
		craftable[r["out"]] = true
	check(craftable.has("mail_iron") and craftable.has("plate_mythril") and craftable.has("exo_chest"), "armour can be crafted in every era")

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
			# Roads cut through rough relief (tors, towers) by design; measure the base.
			var sh := g.field.shape(pts[i].x, pts[i].y)
			cut = maxf(cut, sh.x + sh.y - lv[i])
			fills.append(lv[i] - sh.x - sh.y)
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
