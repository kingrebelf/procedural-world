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

## Crags set into cliffs never hang in mid-air: most of every one's base is on rock, and
## a good part of it is inside the hill.
func test_crags_seated() -> void:
	var g := ChunkGenerator.new(4242, true)
	var total := 0
	var hanging := 0
	for cz in range(5, 8):
		for cx in range(-6, -2):
			var c := g.generate(cx, cz)
			var out := ChunkNode.build_crag_buffers(c)
			for k in out:
				if not String(k).begins_with("stone:"):
					continue
				var buf: PackedFloat32Array = out[k]
				for n in range(0, buf.size(), 16):
					var b := Basis(Vector3(buf[n], buf[n + 4], buf[n + 8]), Vector3(buf[n + 1], buf[n + 5], buf[n + 9]), Vector3(buf[n + 2], buf[n + 6], buf[n + 10]))
					total += 1
					if ChunkNode._crag_loose(c, String(k).substr(6), b, Vector3(buf[n + 3], buf[n + 7], buf[n + 11]), b.x.length()):
						hanging += 1
	check(total > 20, "cliffs carry crags (%d)" % total)
	check(hanging == 0, "no crag hangs in mid-air (%d of %d)" % [hanging, total])

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

func test_waterfalls() -> void:
	var was := WorldField.terrain_v
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242, true)
	# The nearest falls to the spawn on seed 4242 (tools/probe_falls.gd lists them).
	var f := {}
	for r in 6:
		for iz in range(-r, r + 1):
			for ix in range(-r, r + 1):
				if f.is_empty() and maxi(absi(ix), absi(iz)) == r:
					f = Waterfalls.in_cell(g, ix, iz)
	check(not f.is_empty(), "a waterfall within 3 km of the spawn")
	if f.is_empty():
		WorldField.terrain_v = was
		return
	var lip: Vector2 = f["lip"]
	var d: Vector2 = f["dir"]
	var drop: float = f["drop"]
	var levels: PackedFloat32Array = f["levels"]
	print("    falls at %s: %.1f m in %d" % [lip, drop, levels.size()])
	check(drop >= Waterfalls.MIN_DROP and drop <= Waterfalls.MAX_DROP, "a natural height (%.1f m)" % drop)
	check(var_to_str(Waterfalls.in_cell(ChunkGenerator.new(4242, true), f["cell"].x, f["cell"].y)) == var_to_str(f), "falls are planned the same by any generator")
	var at := func(q: Vector2) -> Dictionary:
		return g.generate(int(floor(q.x / 64.0)), int(floor(q.y / 64.0)))
	var water := func(q: Vector2) -> float:
		var c: Dictionary = at.call(q)
		return ChunkGenerator.river_surface(c, q.x - c["cx"] * 64.0, q.y - c["cz"] * 64.0)
	var ground := func(q: Vector2) -> float:
		var c: Dictionary = at.call(q)
		return ChunkGenerator.height_at(c, q.x - c["cx"] * 64.0, q.y - c["cz"] * 64.0)
	var above: float = water.call(lip - d * 4.0)
	var below: float = water.call(lip + d * (Waterfalls.RAMP + 3.0))
	check(not is_nan(above) and above > float(f["top"]) - 1.0, "the river runs on to the lip (%.1f, top %.1f)" % [above, f["top"]])
	var tier := Waterfalls.tier_drop(f, 0)
	check(not is_nan(below) and absf(below - levels[0]) < 0.3, "it lands in its pool at the tier's level (%.1f, wanted %.1f)" % [below, levels[0]])
	check(above - below > tier * 0.8, "the water drops sheer at the lip (%.1f m of %.1f)" % [above - below, tier])
	var foot := lip + d * (Waterfalls.pool_centre(tier) + Waterfalls.RAMP * 0.5)
	check(float(water.call(foot)) - float(ground.call(foot)) > WorldField.RIVER_DEPTH + 0.8, "a plunge pool is cut deeper than the river's bed")
	# Beside the water, the bank steps down as well: the fall is a cliff across the valley.
	var side := Vector2(-d.y, d.x)
	var off := 2.0
	while off < 60.0 and g.field.river_t(lip.x + side.x * off, lip.y + side.y * off) < 1.6:
		off += 1.0
	var bank_hi: float = ground.call(lip - d * 1.0 + side * off)
	var bank_lo: float = ground.call(lip + d * (Waterfalls.RAMP + 2.0) + side * off)
	check(bank_hi - bank_lo > tier * 0.4, "a cliff steps down across the valley beside the fall (%.1f m at %.0f m out)" % [bank_hi - bank_lo, off])
	# The chunk the lip lies in keeps the drop for its water, mist and sound.
	var lc: Dictionary = at.call(lip)
	check(lc.has("falls") and not (lc["falls"] as Array).is_empty(), "the lip's chunk keeps its falls")
	if lc.has("falls"):
		var fx := WaterfallFx.new()
		fx.build(lc["falls"][0], lc)
		var sheet := fx.get_node("Sheet") as MeshInstance3D
		var vs: PackedVector3Array = sheet.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var finite := true
		var lowest := INF
		for v in vs:
			finite = finite and v.is_finite()
			lowest = minf(lowest, v.y)
		check(finite and vs.size() > 40, "the falling sheet is built (%d vertices)" % vs.size())
		check(lowest < levels[0], "the sheet reaches down into the pool")
		check(fx.has_node("Mist") and fx.has_node("Foam") and fx.has_node("Roar"), "with foam, mist and its roar")
		check(fx.has_node("Boulders") and fx.get_node("Boulders").get_child_count() >= 6, "and boulders round its pool")
		check((fx.get_node("Mist") as GPUParticles3D).amount <= 64, "mist stays cheap")
		fx.free()
	# Chunks round the falls meet seamlessly.
	var k := Vector2i(int(floor(lip.x / 64.0)), int(floor(lip.y / 64.0)))
	var R := ChunkGenerator.RES
	var maxd := 0.0
	var a: Dictionary = g.generate(k.x, k.y)
	var b: Dictionary = g.generate(k.x + 1, k.y)
	var c2: Dictionary = g.generate(k.x, k.y + 1)
	for i in R:
		maxd = maxf(maxd, absf(a["heights"][i * R + R - 1] - b["heights"][i * R]))
		maxd = maxf(maxd, absf(a["heights"][(R - 1) * R + i] - c2["heights"][i]))
	check(maxd < 0.0001, "chunks round a falls meet at their edges (max diff %f)" % maxd)
	# Worlds made before falls keep their rivers exactly; so do chunks far from any falls.
	WorldField.terrain_v = Waterfalls.V - 1
	var og := ChunkGenerator.new(4242, true)
	check(Waterfalls.near(og, lip.x, lip.y, lip.x, lip.y).is_empty(), "older worlds have no falls")
	var old: Dictionary = og.generate(k.x, k.y)
	check(not old.has("falls") and old["heights"] != a["heights"], "older worlds keep their river where a falls would be")
	WorldField.terrain_v = Waterfalls.V
	var now := ChunkGenerator.new(4242, true)
	# A river chunk no falls reaches.
	var away := Vector2i.MAX
	for r in range(4, 40):
		for cx in range(-r, r + 1):
			if away == Vector2i.MAX and now.field.river_t(cx * 64.0 + 32.0, r * 64.0 + 32.0) < 0.5 and Waterfalls.near(now, cx * 64.0, r * 64.0, cx * 64.0 + 64.0, r * 64.0 + 64.0).is_empty():
				away = Vector2i(cx, r)
	var after := now.generate(away.x, away.y)
	WorldField.terrain_v = Waterfalls.V - 1
	var before := ChunkGenerator.new(4242, true).generate(away.x, away.y)
	check(before.has("river"), "the chunk compared has a river")
	before.erase("created")
	after.erase("created")
	before.erase("gen_version")
	after.erase("gen_version")
	check(var_to_bytes(before) == var_to_bytes(after), "chunks away from falls are exactly as before (terrain, river and every object)")
	WorldField.terrain_v = was

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
	# v14 needles are broken rock: more points (lesser spires and split crowns) than the
	# smooth cones of v13, still as tall; v13 worlds keep theirs.
	if deep.has(WorldField.LF_NEEDLES):
		var c: Vector2 = deep[WorldField.LF_NEEDLES]
		var peaks := {}
		var tops := {}
		var at13 := 0.0
		for tv in [13, 14]:
			WorldField.terrain_v = tv
			var fv := WorldField.new(2024)
			var n := 120
			var hs := PackedFloat32Array()
			hs.resize(n * n)
			var lo := INF
			for j in n:
				for i in n:
					hs[j * n + i] = fv.height(c.x + i - n / 2, c.y + j - n / 2)
					lo = minf(lo, hs[j * n + i])
			var count := 0
			var top := -INF
			for j in range(1, n - 1):
				for i in range(1, n - 1):
					var h := hs[j * n + i]
					top = maxf(top, h - lo)
					if h - lo < 6.0:
						continue
					var peak := true
					for d in [-n - 1, -n, -n + 1, -1, 1, n - 1, n, n + 1]:
						peak = peak and h > hs[j * n + i + d]
					count += 1 if peak else 0
			peaks[tv] = count
			tops[tv] = top
			if tv == 13:
				at13 = fv.height(c.x, c.y)
		print("  needles: v13 %d points, %.1f m; v14 %d points, %.1f m" % [peaks[13], tops[13], peaks[14], tops[14]])
		check(peaks[14] > peaks[13] * 1.3, "v14 needles are broken rock, not cones (%d points vs %d)" % [peaks[14], peaks[13]])
		check(tops[14] > tops[13] * 0.8, "v14 needles still tower (%.1f vs %.1f m)" % [tops[14], tops[13]])
		WorldField.terrain_v = 13
		check(WorldField.new(2024).height(c.x, c.y) == at13, "v13 worlds keep their needles")
	# v15 karst towers are fluted and ledged: their walls are far rougher (bigger height
	# changes from one metre to the next than a smooth bullet's) and they stand as tall;
	# v14 worlds keep theirs.
	if deep.has(WorldField.LF_KARST):
		var c: Vector2 = deep[WorldField.LF_KARST]
		var rough := {}
		var tops := {}
		var at14 := 0.0
		for tv in [14, 15]:
			WorldField.terrain_v = tv
			var fv := WorldField.new(2024)
			var n := 120
			var hs := PackedFloat32Array()
			hs.resize(n * n)
			var lo := INF
			for j in n:
				for i in n:
					hs[j * n + i] = fv.height(c.x + i - n / 2, c.y + j - n / 2)
					lo = minf(lo, hs[j * n + i])
			var sum := 0.0
			var count := 0
			var top := -INF
			for j in range(1, n - 1):
				for i in range(1, n - 1):
					var h := hs[j * n + i]
					top = maxf(top, h - lo)
					if h - lo < 8.0:
						continue
					sum += absf(4.0 * h - hs[j * n + i - 1] - hs[j * n + i + 1] - hs[j * n + i - n] - hs[j * n + i + n])
					count += 1
			rough[tv] = sum / maxi(count, 1)
			tops[tv] = top
			if tv == 14:
				at14 = fv.height(c.x, c.y)
		print("  karst: v14 roughness %.2f, %.1f m; v15 roughness %.2f, %.1f m" % [rough[14], tops[14], rough[15], tops[15]])
		check(rough[15] > rough[14] * 1.3, "v15 karst towers are fluted and ledged, not smooth (%.2f vs %.2f)" % [rough[15], rough[14]])
		check(tops[15] > tops[14] * 0.8, "v15 karst towers still stand tall (%.1f vs %.1f m)" % [tops[15], tops[14]])
		WorldField.terrain_v = 14
		check(WorldField.new(2024).height(c.x, c.y) == at14, "v14 worlds keep their towers")
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

## v19 rock towers are believable: none taller than its width allows or squeezed into a
## thin sheer fin between its neighbours, none standing alone on open ground, and no
## higher than about fifteen storeys over the valley; older worlds keep theirs and the
## other landforms are untouched.
func test_film_grade_is_gentle() -> void:
	# Neutral greys keep their brightness (only a slight cool or warm lean), saturated
	# yellow-greens lose a little saturation, and other hues keep theirs.
	for v in [0.1, 0.5, 0.9]:
		var c := Grade.grade(Color(v, v, v))
		check(absf((c.r + c.g + c.b) / 3.0 - v) < 0.02, "grey %.1f stays %.1f, got %s" % [v, v, c])
	var leaf := Color(0.3, 0.6, 0.12)
	var g := Grade.grade(leaf)
	check(g.s < leaf.s - 0.03 and g.s > leaf.s * 0.7, "a leaf green softens a little: %.2f -> %.2f" % [leaf.s, g.s])
	var red := Color(0.7, 0.15, 0.1)
	check(absf(Grade.grade(red).s - red.s) < 0.05, "a red keeps its saturation")
	var lut := Grade.lut()
	check(lut != null and lut.get_width() == Grade.SIZE and lut.get_depth() == Grade.SIZE, "the grade table is %d cubed" % Grade.SIZE)

func test_believable_towers() -> void:
	WorldField.terrain_v = WorldField.TOWERS_V
	var f := WorldField.new(2024)
	var deep := {}
	for iz in range(-25, 25):
		for ix in range(-25, 25):
			var lf := f.site_landform(ix, iz)
			var p := f.site_pos(ix, iz)
			if (lf == WorldField.LF_KARST or lf == WorldField.LF_NEEDLES) and not deep.has(lf) and f.landform_weights(p.x, p.y)[lf] > 0.97:
				deep[lf] = p
	check(deep.size() == 2, "found karst and needle country (%d)" % deep.size())
	for lf in deep:
		var c: Vector2 = deep[lf]
		var st := {}
		for tv in [WorldField.TOWERS_V - 2, WorldField.TOWERS_V]:
			WorldField.terrain_v = tv
			st[tv] = _tower_stats(WorldField.new(2024), c, 200)
		var o: Dictionary = st[WorldField.TOWERS_V - 2]
		var n: Dictionary = st[WorldField.TOWERS_V]
		var name: String = WorldField.LANDFORM_NAMES[lf]
		print("  %-12s old: top %.1f m, %d towers, worst height:width %.2f, %d lone; new: top %.1f m, %d towers, worst %.2f, %d lone" % [name,
			o["top"], o["towers"], o["worst"], o["lone"], n["top"], n["towers"], n["worst"], n["lone"]])
		var cap := WorldField.TOWER_ASPECT if lf == WorldField.LF_KARST else WorldField.NEEDLE_ASPECT
		check(n["worst"] <= cap * 1.25, "%s: no tower is much taller than it is wide (%.2f)" % [name, n["worst"]])
		check(n["top"] > 25.0 and n["top"] < 52.0, "%s still tower, but no higher than about fifteen storeys (%.1f m)" % [name, n["top"]])
		check(n["towers"] >= 3, "%s: the towers are still there (%d)" % [name, n["towers"]])
		check(n["lone"] == 0, "%s: no tall tower stands alone (%d)" % [name, n["lone"]])
	# Old worlds keep their towers; every other landform is the same in v19 as before it.
	var other := 0
	var same := true
	for iz in range(-12, 12):
		for ix in range(-12, 12):
			var p := f.site_pos(ix, iz)
			var lw := f.landform_weights(p.x, p.y)
			if lw[WorldField.LF_KARST] > 0.0 or lw[WorldField.LF_NEEDLES] > 0.0:
				continue
			for k in 4:
				var x := p.x + k * 37.0 - 60.0
				var z := p.y - k * 23.0 + 30.0
				WorldField.terrain_v = WorldField.TOWERS_V - 1
				var a := WorldField.new(2024).shape(x, z)
				WorldField.terrain_v = WorldField.TOWERS_V
				var b := WorldField.new(2024).shape(x, z)
				same = same and a == b
				other += 1
	check(same and other > 200, "land away from towers is unchanged by v19 (%d samples)" % other)
	var c0: Vector2 = deep[WorldField.LF_KARST]
	var line := {}
	for tv in [WorldField.TOWERS_V - 2, WorldField.TOWERS_V - 2, WorldField.TOWERS_V]:
		WorldField.terrain_v = tv
		var fv := WorldField.new(2024)
		var hs := PackedFloat32Array()
		for i in 100:
			hs.append(fv.height(c0.x + i * 2.0 - 100.0, c0.y + i * 0.7))
		check(not line.has(tv) or line[tv] == hs, "older worlds keep their towers")
		line[tv] = hs
	WorldField.terrain_v = WorldField.TOWERS_V
	check(line[WorldField.TOWERS_V - 2] != line[WorldField.TOWERS_V], "new worlds get the new towers")
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

## Towers in an n x n metre patch round c: the highest relief, how many towers stand
## over 12 m, the worst height-to-width (width: of the part above half its height) and
## how many over 20 m have no other tower over 8 m within 50 m.
func _tower_stats(f: WorldField, c: Vector2, n: int) -> Dictionary:
	var rel := PackedFloat32Array()
	rel.resize(n * n)
	var top := 0.0
	for j in n:
		for i in n:
			var sh := f.shape(c.x + i - n / 2, c.y + j - n / 2)
			rel[j * n + i] = sh.z + sh.y
			top = maxf(top, sh.z)
	var peaks: Array[Vector3] = []
	for j in range(4, n - 4):
		for i in range(4, n - 4):
			var h := rel[j * n + i]
			if h < 8.0:
				continue
			var peak := true
			for dj in range(-4, 5):
				for di in range(-4, 5):
					if (di != 0 or dj != 0) and rel[(j + dj) * n + i + di] >= h:
						peak = false
			if peak:
				peaks.append(Vector3(i, j, h))
	var worst := 0.0
	var towers := 0
	var lone := 0
	for p in peaks:
		if p.z < 12.0:
			continue
		towers += 1
		# Flood the part of it above half its height.
		var seen := {}
		var todo := [Vector2i(int(p.x), int(p.y))]
		var area := 0
		while not todo.is_empty() and area < 4000:
			var q: Vector2i = todo.pop_back()
			if seen.has(q) or q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or rel[q.y * n + q.x] < p.z * 0.5:
				continue
			seen[q] = true
			area += 1
			todo.append_array([q + Vector2i.LEFT, q + Vector2i.RIGHT, q + Vector2i.UP, q + Vector2i.DOWN])
		# A cone's half-height section is half its foot: compare the height to twice it.
		worst = maxf(worst, p.z / (4.0 * sqrt(area / PI)))
		if p.z >= 20.0 and p.x > 50 and p.y > 50 and p.x < n - 50 and p.y < n - 50:
			var friend := false
			for p2 in peaks:
				friend = friend or (p2 != p and p2.z >= 8.0 and Vector2(p.x, p.y).distance_to(Vector2(p2.x, p2.y)) < 50.0)
			lone += 0 if friend else 1
	return {"top": top, "towers": towers, "worst": worst, "lone": lone}

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
		for e in Furnish.settled(t):
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

## Sunbeams come in where a tower's arrow slits are: a ray along each window's normal
## passes the walls there into the room, and the beams' boxes are built.
func test_sun_windows() -> void:
	for t in Interiors.TOWER:
		var wins := Interiors.sun_windows(t)
		check(wins.size() == 8, "%s lets the sun in through its eight arrow slits (%d)" % [t, wins.size()])
		var tm := ObjectLibrary.get_mesh(t).generate_triangle_mesh()
		var open := 0
		for w in wins:
			# The shell is drawn sunk by SINK: back into its own space.
			var c: Vector3 = (w[0] as Vector3) + Vector3(0, Interiors.SINK, 0)
			var n: Vector3 = w[1]
			if tm.intersect_segment(c - n * 2.0, c + n * 0.5).is_empty():
				open += 1
		check(open == wins.size(), "%s: every sun window is an opening in its walls (%d of %d)" % [t, open, wins.size()])
		var m := SunBeams.mesh(t)
		check(m != null and m.surface_get_array_len(0) == 8 * wins.size(), "%s has a beam box per window" % t)
	# A house lets the sun in through its unshuttered windows, each where a pane is.
	for t in KitHouse.PLANS:
		var wins := Interiors.sun_windows(t)
		var glows: Array = KitHouse._plan(t)["glows"]
		var at_pane := wins.all(func(w): return glows.any(func(g: Transform3D): return g.origin.distance_to((w[0] as Vector3) + Vector3(0, Interiors.SINK, 0)) < 0.3))
		check(not wins.is_empty() and wins.size() <= glows.size() and at_pane, "%s lets the sun in at its windows (%d of %d panes)" % [t, wins.size(), glows.size()])
	# Whether the sun reaches a window is asked by rays from just outside it, which must
	# start clear of the building's own collision (a ray inside a wall hits it).
	for t in Interiors.TOWER.keys() + KitHouse.PLANS.keys():
		var sh: Array = ObjectLibrary.shape_of({"t": t, "st": {}})
		var box := (sh[0] as Shape3D).get_debug_mesh().get_aabb()
		box.position += sh[1]
		var clear := Interiors.sun_windows(t).all(func(w): return not box.has_point((w[0] as Vector3) - (w[1] as Vector3) * SunBeams.RAY_OUT))
		check(clear, "%s: the sun rays start outside its walls" % t)
	check(SunBeams.mesh("hab_block") == null and Interiors.sun_windows("castle_keep").is_empty(), "rooms without sun windows have no beams")

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
			for e in Furnish.settled(t):
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

## Sci-fi rooms are painted, not plated: the bunker's walls, floors and ceilings and
## the outpost blocks' fit-out use painted panels, sheet vinyl and ceiling tiles (real
## textures, no metal in them), and tread plate is left to the stairs and stores.
func test_painted_scifi_interiors() -> void:
	for n in ["paint_wall", "vinyl_floor", "ceiling_tile"]:
		var m := Materials.get_mat(n) as StandardMaterial3D
		check(m.albedo_texture != null and m.normal_texture != null and m.metallic == 0.0, "%s is a textured, unmetallic surface" % n)
	var bunker: Dictionary = DungeonNode.MATS[Eras.SCIFI]
	for key in ["wall", "floor", "ceil", "beam"]:
		check(not String(bunker[key]) in ["scifi_panels", "scifi_floor", "metal", "metal_dark", "panel"], "a bunker's %s is painted (%s)" % [key, bunker[key]])
	for t in ["hab_block", "lab_block", "ops_tower", "bunker_keep", "bunker_tower"]:
		var room := ObjectLibrary.get_mesh(t + "~in")
		var mats := {}
		for i in room.get_surface_count():
			mats[room.surface_get_material(i)] = true
		check(mats.has(Materials.get_mat("vinyl_floor")) and mats.has(Materials.get_mat("ceiling_tile")), "%s has a vinyl floor and a tiled ceiling" % t)
		check(not mats.has(Materials.get_mat("metal_dark")), "%s has no dark plate in its fit-out" % t)

## Finishing trim: chamfered boxes and swept mouldings face out on every triangle (Godot
## culls the back faces, so a wrong winding is a hole), and a skirting leaves the
## doorway it is told about open.
func test_trim() -> void:
	var outward := func(m: ArrayMesh) -> int:
		var bad := 0
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var ii: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			for t in range(0, ii.size(), 3):
				var g := (v[ii[t + 2]] - v[ii[t]]).cross(v[ii[t + 1]] - v[ii[t]])
				if g.length() > 1e-9 and g.dot(n[ii[t]] + n[ii[t + 1]] + n[ii[t + 2]]) < 0.0:
					bad += 1
		return bad
	var k := MeshKit.new(1)
	k.bevel_box("stone", Transform3D(Basis(Vector3.UP, 0.4), Vector3(1, 2, 3)), Vector3(1, 0.5, 0.3), 0.05)
	var m := k.commit(Materials.get_mat)
	check(m.surface_get_array_len(0) == 44 * 3, "a chamfered box is 44 triangles")
	check(outward.call(m) == 0, "a chamfered box faces out all round")
	k = MeshKit.new(1)
	Trim.room(k, "timber", Trim.SKIRT, -2, 2, -2, 2, 0.0, [["+z", -0.6, 0.6]])
	Trim.room(k, "timber", Trim.cove(0.06, 0.11), -2, 2, -2, 2, 2.9, [], true)
	Trim.room(k, "stone", Trim.WATER_TABLE, -2, 2, -2, 2, 0.0, [], false, true)
	Trim.kit_wall(k, Transform3D.IDENTITY.translated(Vector3(5, 0, 0)), "door")
	Trim.kit_wall(k, Transform3D.IDENTITY.translated(Vector3(8, 0, 0)), "window")
	m = k.commit(Materials.get_mat)
	check(outward.call(m) == 0, "mouldings, casings and sills face out")
	var in_door := false
	for s in m.get_surface_count():
		for p: Vector3 in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if absf(p.x) < 0.55 and p.z > 1.9 and p.z < 2.0 and p.y < 0.2:
				in_door = true
	check(not in_door, "the skirting stops at the doorway")

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

func test_biome_coherence() -> void:
	# Broadleaf trees give way to conifers up by the snow line.
	var bp := Biome.params(12345, Eras.MEDIEVAL)
	var oak := {"t": "oak", "sp": 77, "w": 1.0}
	check(Biome.by_altitude(bp, oak, WorldField.snow_line - 40.0, 0.5)["t"] == "oak", "oaks in the lowlands")
	check(Biome.by_altitude(bp, oak, WorldField.snow_line + 2.0, 0.5)["t"] == "pine", "pines up by the snow")
	# Nothing takes root or lies about on open dune sand, and only dune animals live there.
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(2024)
	var dunes := 0
	var on_sand := []
	var animals_ok := true
	for iz in range(-25, 25):
		for ix in range(-25, 25):
			if dunes >= 3 or g.field.site_landform(ix, iz) != WorldField.LF_DUNES:
				continue
			var p := g.field.site_pos(ix, iz)
			if g.field.landform_weights(p.x, p.y)[WorldField.LF_DUNES] < 0.9:
				continue
			dunes += 1
			var ch := g.generate(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))
			for o in ch["objects"]:
				var k := ObjectLibrary.kind(o["t"])
				var at: Vector3 = o["p"]
				if (k == "tree" and o["t"] != "palm" or k == "rock") and ChunkGenerator.sand_at(ch, at.x, at.z) > 0.45:
					on_sand.append(o["t"])
			var fauna: Array = Biome.params(g.field.region_hash_at(p.x, p.y), Eras.MEDIEVAL)["fauna"]
			for lx in [10.0, 32.0, 54.0]:
				for pick in 6:
					if ChunkGenerator.sand_at(ch, lx, 32.0) < 0.5:
						continue
					var sp := Creature.fits_habitat(fauna, pick, Eras.MEDIEVAL, ch, lx, 32.0)
					animals_ok = animals_ok and (sp == 0 or Creature.species(sp, Eras.MEDIEVAL)["name"] in Creature.DUNE_ANIMALS)
	check(dunes > 0, "dunes to look at")
	check(on_sand.is_empty(), "no trees (but palms) or boulders on dune sand (%s)" % [on_sand])
	check(animals_ok, "only dune animals on the dunes")

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

## A piece can't go up through a wild tree: not over its trunk, not up into its crown;
## a floor laid in the crown's shade is fine, and so is a wall clear of it.
func test_build_round_trees() -> void:
	var trees := [[Vector3(10, 2, 10), 0.3, 4.0, 8.0, 2.5]]
	check(BuildCatalog.tree_in_way(trees, AABB(Vector3(9, 2, 9), Vector3(3, 0.4, 3))), "no floor over a trunk")
	check(not BuildCatalog.tree_in_way(trees, AABB(Vector3(11, 2, 9), Vector3(3, 0.4, 3))), "a floor under the crown, clear of the trunk")
	check(BuildCatalog.tree_in_way(trees, AABB(Vector3(11, 2, 9.9), Vector3(2, 3, 0.2))), "no wall up into the crown")
	check(not BuildCatalog.tree_in_way(trees, AABB(Vector3(13, 2, 9.9), Vector3(2, 3, 0.2))), "a wall clear of the crown")
	check(not BuildCatalog.tree_in_way(trees, AABB(Vector3(9, 8.5, 9), Vector3(3, 0.3, 3))), "a roof above the top")
	var key := ObjectLibrary.mesh_key({"t": "oak", "sp": 3, "v": 0, "s": 1.0, "p": Vector3.ZERO, "r": 0.0, "i": 0, "e": 0, "st": {}})
	var t := BuildCatalog.tree_shape(key, Vector3.ZERO, 1.0)
	check(float(t[3]) > 2.0 and float(t[4]) > 0.5 and float(t[2]) < float(t[3]), "a tree's shape from its mesh (%s)" % str(t))

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
	check(w2["pos"].is_equal_approx(Vector3(5, 3.12, 8)) and is_equal_approx(w2["yaw"], 0.0), "aiming at a wall top builds the next storey (%s)" % w2["pos"])
	var f := BuildCatalog.snap("platform", Vector3(-1.0, 2.0, 9.5), 0.0, 0)
	check(f["pos"].is_equal_approx(Vector3(-2, 2, 10)), "sci-fi platforms use 4 m cells (%s)" % f["pos"])
	var rv := BuildCatalog.snap("roof_small", Vector3(3.2, 3.2, 4.9), 0.0, 0, Vector3(3, 0, 5), false)
	check(rv["pos"].is_equal_approx(Vector3(4, 3.12, 4)), "small roof centres on a grid corner (%s)" % rv["pos"])
	var g := BuildCatalog.snap("floor_wood", Vector3(1.0, -0.8, 1.0), 0.0, 0, Vector3(1, 0, 1), true)
	check(is_equal_approx(g["pos"].y, 0.0), "ground below a house keeps the floor level")
	# A floor aimed at the side of a wall goes on top of it, in the cell on your side.
	var fw := BuildCatalog.snap("floor_wood", Vector3(4.05, 1.5, 7.3), 0.0, 0, Vector3(4, 0, 7), false, {"hit_mode": "wall"})
	check(fw["pos"].is_equal_approx(Vector3(5, 3.12, 7)), "floor aimed at a wall sits on its top (%s)" % fw["pos"])
	var rw := BuildCatalog.snap("roof_small", Vector3(4.05, 2.9, 7.3), 0.0, 0, Vector3(4, 0, 7), false, {"hit_mode": "wall"})
	check(is_equal_approx(rw["pos"].y, 3.12), "roof aimed at a wall sits on its top (%s)" % rw["pos"])
	# Raise / lower by storeys, and free placement off the grid.
	var up := BuildCatalog.snap("floor_wood", Vector3(1.0, 0.2, 1.0), 0.0, 0, Vector3(1, 0, 1), true, {"lift": 2})
	check(is_equal_approx(up["pos"].y, 6.24), "raise lifts a piece two storeys (%s)" % up["pos"])
	var dn := BuildCatalog.snap("floor_wood", Vector3(1.0, 3.2, 1.0), 0.0, 0, Vector3(1, 0, 1), true, {"lift": -1})
	check(is_equal_approx(dn["pos"].y, 0.0), "lower drops a piece a storey (%s)" % dn["pos"])
	var fr := BuildCatalog.snap("wall_plaster", Vector3(1.37, 0.6, 2.11), 0.0, 1, null, true, {"free": true, "lift": 1})
	check(fr["pos"].is_equal_approx(Vector3(1.25, 0.75, 2.0)) and is_equal_approx(fr["yaw"], PI + PI / 12.0), "grid off places freely (%s, %.2f)" % [fr["pos"], fr["yaw"]])
	_build_snapping()
	_grass_under_floors()
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
	# Households: children live at a home, have no trade, and the grown-ups are the same
	# people they were before children were added (their own random stream).
	var kids := 0
	var grown := 0
	for p in a["npcs"]:
		if p.get("child", false):
			kids += 1
			check(p["job"] == "child" and int(p["age"]) >= 4 and int(p["age"]) < BodyShape.ADULT, "a child is 4-17 with no trade")
		else:
			grown += 1
			check(int(p["age"]) >= 18, "grown-ups are grown")
	check(kids == 0 or a["npcs"][grown - 1].get("child", false) == false, "children come after the grown-ups")

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

func test_npc_roles() -> void:
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var site: Dictionary = fx[1]
	var s := NPCGen.generate(777, gen, site, gen.settlement_layout(site))
	var pl := NPCRoles.places(gen, site, s)
	check(not (pl["gates"] as Array).is_empty() and not (pl["rounds"] as Array).is_empty(), "a town has gates and a guard's round")
	for job in NPCRoles.ROUTINES:
		for b in NPCRoles.ROUTINES[job]:
			check(b[2] == "sleep" or NPCRoles.DUTIES.has(b[2]), "routine duty exists: %s %s" % [job, b[2]])
	var f: Dictionary = s["npcs"][2].duplicate(true)
	f["job"] = "farmer"
	f["traits"]["diligent"] = 0.5
	var d := NPCRoles.duty_at(f, pl, 9.0, 100.0)
	check(d.get("duty", "") == "till", "a farmer is in the fields mid-morning (%s)" % d.get("duty", ""))
	if (pl["fields"] as Array).is_empty():
		check((d["target"] as Vector2).distance_to(site["center"]) > float(site["outer"]), "the fields are past the houses")
	check(NPCRoles.duty_at(f, pl, 9.0, 100.0)["target"] == d["target"], "the same stop at the same moment")
	check(NPCRoles.duty_at(f, pl, 23.0, 100.0).is_empty(), "evenings are their own")
	var per := {"hour": 9.0, "pos": Vector2.ZERO, "center": s["center"], "player_dist": 100.0, "noise": 0.5, "now": 0.0, "duty": d}
	var r := DecisionEngine.decide(f, per)
	check(r["action"] == "work" and r["target"] == d["target"], "the routine drives their work (%s)" % r["action"])
	var g: Dictionary = s["npcs"][1].duplicate(true)
	g["job"] = "guard"
	g["era"] = 0
	g["id"] = "x_y_7"
	var watch := false
	for i in 30:
		g["id"] = "x_y_%d" % (i + 2)
		if NPCRoles.night_watch(g):
			watch = true
			break
	check(watch, "some guards keep the night watch")
	var nd := NPCRoles.duty_at(g, pl, 2.0, 0.0)
	check(nd.get("duty", "") == "night_watch", "the night watch is out at 2am")
	per["hour"] = 2.0
	per["duty"] = nd
	check(DecisionEngine.decide(g, per)["action"] == "work", "and awake")
	per["hour"] = 11.0
	per["duty"] = NPCRoles.duty_at(g, pl, 11.0, 0.0)
	check(DecisionEngine.decide(g, per)["action"] == "sleep", "and sleeps by day")
	check(NPCRoles.day_words(f).contains("fields"), "the model hears their day")
	# A village with fields of its own (TownLife): its farmers work them.
	var vsite := {}
	for ring in 16:
		for st in gen.settlements_near(-ring * 256.0, -ring * 256.0, ring * 256.0, ring * 256.0):
			if TownLife.applies(gen, st) and not (TownLife.plan(gen, st)["fields"] as Array).is_empty():
				vsite = st
		if not vsite.is_empty():
			break
	check(not vsite.is_empty(), "a village with fields found")
	if not vsite.is_empty():
		var vs := NPCGen.generate(777, gen, vsite, gen.settlement_layout(vsite))
		var vpl := NPCRoles.places(gen, vsite, vs)
		var vf: Dictionary = f.duplicate(true)
		vf["era"] = Eras.MEDIEVAL
		var vd2 := NPCRoles.duty_at(vf, vpl, 9.0, 100.0)
		var inf := false
		for fl in vpl["fields"]:
			var l := TownLife.world_to_frame(fl["p"], float(fl["yaw"]), vd2["target"])
			inf = inf or absf(l.x) < float(fl["hx"]) and absf(l.y) < float(fl["hz"])
		check(vd2.get("duty", "") == "till" and inf, "a farmer works a row of the village's own field")
		var vd3 := NPCRoles.duty_at(vf, vpl, 9.0, 100.0 + float(NPCRoles.DUTIES["till"]["hop"]) * 1.3)
		check(vd3["target"] != vd2["target"] and (vd3["target"] as Vector2).distance_to(vd2["target"]) < 20.0, "moving on down the row")
		var crates := 0
		for pr in NPCRoles.props(vpl, vs):
			crates += int(pr[0] == NPCRoles.PROPS["field"])
		check(crates == 0, "no stand-in crop crates beside real fields")
		check(not (vpl["benches"] as Array).is_empty(), "the village's door benches are seats for sitters")
	# Market crowd: folk in from the country by day, gone by night.
	var crowd := MarketCrowd.roster(site, 0, 12, pl["gates"])
	check(crowd.size() >= MarketCrowd.BASE[int(site.get("size", 0))] - 1, "a town gets its day visitors (%d)" % crowd.size())
	check(str(MarketCrowd.roster(site, 0, 12, pl["gates"])) == str(crowd), "the same crowd on the same day, for everyone")
	check(str(MarketCrowd.roster(site, 0, 13, pl["gates"])) != str(crowd), "and a different one tomorrow")
	var noon := 0
	var dusk := 0
	var night := 0
	for v in crowd:
		check(not v.get("child", false) and (v["home"] as Vector2) in pl["gates"], "a visitor is an adult who came by a road")
		noon += int(MarketCrowd.here(v, 12.5))
		dusk += int(MarketCrowd.here(v, 20.0))
		night += int(MarketCrowd.here(v, 1.0)) + int(MarketCrowd.here(v, 23.5))
	check(noon >= crowd.size() / 3 and noon > dusk and night == 0, "busiest at midday, thinner at dusk, gone by night (%d/%d/%d)" % [noon, dusk, night])
	var v0: Dictionary = crowd[0]
	var vd := NPCRoles.duty_at(v0, pl, float(v0["visit"][0]) + 0.1, 0.0)
	check(vd.get("duty", "") == String(v0["visit"][2]) and vd["target"] != Vector2.INF, "a visitor's day out is a duty (%s)" % vd.get("duty", ""))
	check((vd["target"] as Vector2).distance_to(site["center"]) < float(site["outer"]), "spent in town")
	check(NPCRoles.duty_at(v0, pl, float(v0["visit"][1]) - 0.1, 0.0).get("duty", "") == "head_home", "and at the end they head for the road")
	check(NPCRoles.duty_at(v0, pl, 3.0, 0.0).is_empty() and not NPCRoles.day_words(v0).is_empty(), "nothing at night; the model knows they're visiting")
	var ks := MarketCrowd.knots(pl)
	check(ks.size() == 5 and (ks[0] as Vector2).distance_to(site["center"]) < float(site["inner"]), "idlers gather in knots in the square")
	var clear := true
	for v in crowd:
		for h in [9.0, 11.0, 13.0, 15.0, 19.0]:
			var dd := NPCRoles.duty_at(v, pl, h, 0.0)
			if dd.is_empty() or dd["duty"] == "head_home":
				continue
			for o in pl["obstacles"]:
				if (dd["target"] as Vector2).distance_to(o[0]) < float(o[1]):
					clear = false
	check(clear and not (pl["obstacles"] as Array).is_empty(), "nobody stands inside a stall, cart, chest or well")
	# A weaponsmith keeps a forge outside the shop door for part of the day.
	var shop := {}
	for h in TownShops.shops_of(gen, site):
		shop = h
	if not shop.is_empty():
		var ws: Dictionary = f.duplicate(true)
		ws["shop_kind"] = "weaponsmith"
		ws["shop_i"] = int(shop["i"])
		var wd := NPCRoles.duty_at(ws, pl, 10.0, 0.0)
		check(wd.get("duty", "") == "smithy" and (wd["target"] as Vector2).distance_to(TownShops.door_point(shop)) < 4.0, "a weaponsmith works a forge by the shop door (%s)" % wd.get("duty", ""))
		check(NPCRoles.duty_at(ws, pl, 12.5, 0.0).is_empty(), "and keeps the counter the rest of the day")
		var forge := false
		for pr in NPCRoles.props(pl, {"npcs": [ws]}):
			forge = forge or pr[0] == NPCRoles.PROPS["forge"]
		check(forge, "with an anvil set out there")
	# A shop too small for a counter still gets its stand and wares, clear of the keeper,
	# the doorway and the round wall.
	var small := TownShops.fit("mushroom_house")
	var sm_ok: bool = not small.has("counter") and (small.get("props", []) as Array).size() >= 2
	for sp: Vector2 in small.get("props", []):
		sm_ok = sm_ok and sp.distance_to(small["keeper"]) > 0.7 and sp.length() < 1.9 \
			and not (absf(sp.x - float(TownShops.room("mushroom_house")["door_x"])) < 0.9 and sp.y > 0.5)
	check(sm_ok, "a shop too small for a counter still has its stand and wares (%s)" % [small.get("props", [])])
	check((NPCRoles.chatter(f, g, s, 4) as Array).size() == 2, "small talk has an answer")

## A made-up stretch of land 2x2 chunks: flat at 5 m with a sheer-sided mesa (20 m)
## standing across the middle, and a road along its south foot.
func _walk_land() -> Dictionary:
	var res := ChunkGenerator.RES
	var land := {}
	for kz in 2:
		for kx in 2:
			var hs := PackedFloat32Array()
			hs.resize(res * res)
			var rb := PackedByteArray()
			rb.resize(res * res)
			for j in res:
				for i in res:
					var x := float(kx * ChunkGenerator.SIZE + i)
					var z := float(kz * ChunkGenerator.SIZE + j)
					hs[j * res + i] = 20.0 if x > 50.0 and x < 80.0 and z > 20.0 and z < 110.0 else 5.0
					if z > 12.0 and z < 16.0:
						rb[j * res + i] = 255
			land[Vector2i(kx, kz)] = {"heights": hs, "road": rb}
	return land

func test_walk_grid_goes_round_cliffs() -> void:
	var land := _walk_land()
	var walk := WalkGrid.new(func(k: Vector2i) -> Dictionary: return land.get(k, {}))
	walk.build_per_frame = 99
	walk.search_usec = 1 << 30
	check(is_equal_approx(walk.grade(10.0, 64.0), 0.0), "flat ground is flat (%.2f)" % walk.grade(10.0, 64.0))
	check(walk.grade(50.5, 64.0) > 2.0, "a mesa's side is a cliff (%.2f)" % walk.grade(50.5, 64.0))
	check(walk.on_road(30.0, 14.0) and not walk.on_road(30.0, 40.0), "the road is marked")
	var a := Vector2(20.0, 64.0)
	var b := Vector2(110.0, 64.0)
	check(not walk.clear(a, b, WalkGrid.PERSON), "straight across the mesa is too steep")
	check(walk.clear(a, Vector2(40.0, 90.0), WalkGrid.PERSON), "the flat beside it isn't")
	var r := walk.route(a, b, WalkGrid.PERSON)
	check(not r.is_empty() and r["reached"], "there is a way round")
	if r.is_empty():
		return
	var pts: PackedVector2Array = r["pts"]
	check(pts[pts.size() - 1] == b, "that ends where they were going")
	# Walk it a quarter metre at a time: nowhere on it is steeper than a person walks.
	var at := a
	var worst := 0.0
	var long := 0.0
	for q in pts:
		var n := int(ceil(at.distance_to(q) / 0.25))
		for i in n:
			var p := at.lerp(q, float(i + 1) / float(n))
			worst = maxf(worst, walk.grade(p.x, p.y))
		long += at.distance_to(q)
		at = q
	check(worst <= WalkGrid.PERSON, "the way round climbs nothing steeper than %.2f (%.2f)" % [WalkGrid.PERSON, worst])
	check(pts.size() <= 8, "pulled tight into a few legs, not grid steps (%d)" % pts.size())
	# Round the south end along the road (the north way round is as long without it).
	var south := false
	for q in pts:
		south = south or q.y < 22.0
	check(south and long < 160.0, "by the road at the mesa's south foot (%.0f m)" % long)
	# A goal up on the mesa can't be got to: the nearest place under it instead.
	var top := walk.route(a, Vector2(65.0, 64.0), WalkGrid.PERSON)
	check(not top.is_empty() and not top["reached"], "no way up a sheer mesa")
	if not top.is_empty():
		var end: Vector2 = (top["pts"] as PackedVector2Array)[top["pts"].size() - 1]
		check(end.distance_to(Vector2(65.0, 64.0)) < 20.0 and walk.grade(end.x, end.y) <= WalkGrid.PERSON, "but stops at its foot (%s)" % end)
	# A budget a frame: the second search in a frame waits for the next.
	var w2 := WalkGrid.new(func(k: Vector2i) -> Dictionary: return land.get(k, {}))
	w2.build_per_frame = 99
	w2.search_usec = 1
	check(not w2.route(a, b, WalkGrid.PERSON).is_empty() and w2.route(a, b, WalkGrid.PERSON).is_empty(), "searches wait once a frame's time is spent")
	var w3 := WalkGrid.new(func(k: Vector2i) -> Dictionary: return land.get(k, {}))
	w3.grade(10.0, 10.0)
	w3.grade(100.0, 10.0)
	check(is_nan(w3.grade(10.0, 100.0)) and not w3.clear(Vector2(10.0, 100.0), Vector2(12.0, 100.0), WalkGrid.PERSON), "ground not worked out yet isn't taken as safe")

func test_bandits() -> void:
	var gen := ChunkGenerator.new(777)
	var was := Eras.theme
	Eras.theme = "human"
	var bands: Array = []
	for day in 6:
		bands.append_array(Bandits.near(gen, Vector2.ZERO, 3000.0, float(day)))
	check(not bands.is_empty(), "bands roam the land (%d over six days)" % bands.size())
	var cells := 0
	for cz in range(-5, 5):
		for cx in range(-5, 5):
			cells += 1
	check(bands.size() < cells * 6 / 2, "but only now and then (%d)" % bands.size())
	var ok_spawn := true
	var ok_towns := true
	for b in bands:
		var camp: Vector2 = b["camp"]
		if camp.length() < Bandits.SAFE_R:
			ok_spawn = false
		for st in gen.settlements_near(camp.x - 200.0, camp.y - 200.0, camp.x + 200.0, camp.y + 200.0):
			if (st["center"] as Vector2).distance_to(camp) < float(st["outer"]) + Bandits.TOWN_CLEAR:
				ok_towns = false
	check(ok_spawn, "no band camps near where you arrive")
	check(ok_towns, "no band camps by a town")
	var b: Dictionary = bands[0]
	var again := Bandits.band_at(gen, b["cell"].x, b["cell"].y, int(String(b["id"]).get_slice("_", 2)))
	check(var_to_bytes(again["members"]) == var_to_bytes(b["members"]), "the same band for everyone")
	var m: Dictionary = b["members"][0]
	check(m.has("band") and m["held"] is Dictionary and ItemDB.has(String(m["held"]["type"])), "outlaws are armed (%s)" % m["held"]["type"])
	check(int(m["level"]) >= 1 and float(m["hp"]) >= 100.0, "and levelled by zone")
	var near_spawn := Bandits.tier(Eras.MEDIEVAL, 3)
	check(near_spawn == "low" and Bandits.tier(Eras.SCIFI, 30) == "raider", "poor cutthroats near spawn, raiders out on the frontier")
	var state := {"camp": b["camp"], "route": b["route"], "cell": b["cell"], "id": b["id"], "alert": false, "demand_until": 0.0}
	var per := {"hour": 12.0, "pos": b["camp"], "player_dist": 100.0, "player_pos": Vector2.ZERO, "now": 10.0, "band": state}
	check(Bandits.decide(m, per)["action"] == "wander", "by day the band walks its loop")
	per["hour"] = 23.0
	var m2: Dictionary = b["members"][b["members"].size() - 1]
	var na: String = Bandits.decide(m2, per)["action"]
	check(na in ["sit", "idle"], "by night they sit round the fire or keep watch (%s)" % na)
	per["hour"] = 12.0
	state["demand_until"] = 20.0
	per["player_dist"] = 6.0
	check(Bandits.decide(m, per)["action"] == "confront", "they stop you and demand a toll")
	state["alert"] = true
	check(Bandits.decide(m, per)["action"] == "attack", "and fight if you won't pay")
	var coward: Dictionary = m.duplicate(true)
	coward["traits"]["brave"] = 0.2
	coward["hp"] = 10.0
	check(Bandits.decide(coward, per)["action"] == "flee", "badly hurt, a coward runs")
	check(Bandits.toll(100, 1) >= 13 and Bandits.toll(5, 1) == 5, "the toll is a share of your purse")
	var r := NPCMind.builtin_reply(m, {"name": "Bandit band", "npcs": b["members"], "rumors": []}, "Fine, I'll pay")
	check(r["action"] == "pay_toll", "you can pay them off")
	Eras.theme = "alien"
	check(Bandits.near(gen, Vector2.ZERO, 3000.0, 0.0).is_empty(), "no bandits on alien worlds")
	Eras.theme = was

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

## A town's worth of people of one era, for the built-in dialogue tests.
func _talk_town(era: int, count: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = 99 + era
	var people: Array = []
	for i in count:
		var p := NPCGen.person(r, era, i, 7, 9)
		p["job"] = NPCGen.JOBS[era][i % NPCGen.JOBS[era].size()]
		people.append(p)
	return {"name": "Testford", "npcs": people, "rumors": ["Day 2: Wolves were seen by the mill."]}

func test_builtin_dialogue_variety() -> void:
	var was := Eras.theme
	Eras.theme = "human"
	var s := _talk_town(Eras.MEDIEVAL, 40)
	var greets := {}
	for p in s["npcs"]:
		greets[NPCMind.bark(p, "greet")] = true
	check(greets.size() >= 30, "forty villagers greet you forty ways, not four (%d distinct)" % greets.size())
	var hellos := {}
	for p in s["npcs"]:
		hellos[NPCMind.builtin_reply(p, s, "Hello")["say"]] = true
	check(hellos.size() >= 30, "and answer a hello differently (%d distinct)" % hellos.size())
	# One person asked the same odd thing over and over doesn't parrot one line.
	var p: Dictionary = s["npcs"][3]
	var seen := {}
	var last := ""
	var repeats := 0
	for i in 8:
		var say: String = NPCMind.builtin_reply(p, s, "I like turtles")["say"]
		seen[say] = true
		if say == last:
			repeats += 1
		last = say
	check(seen.size() >= 6 and repeats == 0, "no parroting the same answer (%d distinct of 8)" % seen.size())
	check((p["_said"] as Array).size() <= NPCTalk.SAID_MAX, "what they said lately stays a short list")
	Eras.theme = was

func test_builtin_dialogue_fits_the_world() -> void:
	var was := Eras.theme
	Eras.theme = "human"
	var banned := ["glow", "magic", "fey", "fairy", "faerie", "sylvari", "grove", "enchant", "spirit", "rune", "moss", "the light find", "*"]
	var asks := ["Hello", "Who are you?", "What is this place?", "Any news?", "What do you do here?", "Nice weather today", "Tell me a joke",
		"Is there magic here?", "Do you believe in the gods?", "What about the king?", "Tell me about the old days", "Any monsters about?",
		"How are you?", "What do you like?", "What worries you?", "I like turtles", "Goodbye", "Where is the tavern?", "Got any family?"]
	var bad: Array = []
	for era in [Eras.MEDIEVAL, Eras.SCIFI]:
		var s := _talk_town(era, 24)
		for p in s["npcs"]:
			var said: Array = [NPCMind.bark(p, "greet"), NPCMind.bark(p, "attack"), NPCMind.bark(p, "flee"), NPCMind.bark(p, "confront")]
			for q in asks:
				said.append(NPCMind.builtin_reply(p, s, q)["say"])
			for line in said:
				for w in banned:
					if String(line).to_lower().contains(w):
						bad.append(line)
			check(NPCTalk.culture(p) == ("old" if era == Eras.MEDIEVAL else "frontier"), "human folk speak as humans")
	check(bad.is_empty(), "nothing glows and nobody talks magic on a human world: %s" % str(bad.slice(0, 3)))
	check(NPCMind.system_prompt(_talk_town(0, 2)["npcs"][1], _talk_town(0, 2), {}).contains("no magic"), "the model is told the world's rules")
	Eras.theme = "alien"
	var v: Dictionary = _talk_town(Eras.SCIFI, 2)["npcs"][1]
	check(NPCTalk.culture(v) == "vex" and not NPCMind.system_prompt(v, _talk_town(Eras.SCIFI, 2), {}).contains("no magic"), "the Vex talk like the Vex")
	Eras.theme = was

func test_builtin_dialogue_never_dead_ends() -> void:
	var was := Eras.theme
	Eras.theme = ""
	var dead := ["Hm. Can't say I follow.", "Is that so?", "Interesting. Tell me more another time.", "If you say so."]
	var odd := ["blorp", "The moon is made of cheese", "hmm", "Do you have a dog?", "42", "...", "purple monkey dishwasher", "What would you do with a dragon?",
		"I'm hungry", "Tell me something", "yes", "Are you happy?", "What's the time?", "I come from far away"]
	var s := _talk_town(Eras.FANTASY, 6)
	for e in [Eras.MEDIEVAL, Eras.SCIFI]:
		s["npcs"].append_array(_talk_town(e, 6)["npcs"])
	var empty := 0
	var deadends := 0
	var staged := 0
	for p in s["npcs"]:
		for q in odd:
			var say := String(NPCMind.builtin_reply(p, s, q)["say"])
			if say.strip_edges() == "":
				empty += 1
			if dead.has(say):
				deadends += 1
			if say.contains("*") or say.contains("{") or say != say.strip_edges():
				staged += 1
	check(empty == 0, "always says something")
	check(deadends == 0, "never the old dead-end shrug")
	check(staged == 0, "no stage directions or unfilled blanks in spoken lines")
	# Rudeness stings, kind words warm, and both are remembered in how they feel.
	var p: Dictionary = s["npcs"][14]
	p["rel"] = 10
	p["mood"] = "calm"
	NPCMind.apply_reply(p, s, NPCMind.builtin_reply(p, s, "You're a stupid fool"))
	check(int(p["rel"]) < 10 and p["mood"] in ["angry", "sad"], "an insult lowers their opinion (%d)" % p["rel"])
	var low := int(p["rel"])
	NPCMind.apply_reply(p, s, NPCMind.builtin_reply(p, s, "You look lovely today"))
	check(int(p["rel"]) > low, "a compliment raises it")
	# What you talked about is remembered and brought up again.
	NPCMind.apply_reply(p, s, NPCMind.builtin_reply(p, s, "Lovely weather, isn't it?"))
	check(NPCTalk.last_topic(p) == "the weather", "they remember what you talked about (%s)" % NPCTalk.last_topic(p))
	# Requests and favours still take their actions.
	p["rel"] = 30
	check(NPCMind.builtin_reply(p, s, "Come with me.")["action"] == "follow", "a friend comes along")
	check(NPCMind.builtin_reply(p, s, "Stay here.")["action"] == "stop_following", "and stays when told")
	p["rel"] = 60
	p["mood"] = "happy"
	var wink := NPCMind.builtin_reply(p, s, "Could you wink at me?")
	check(wink.get("do", "") == "wink" and not String(wink["say"]).contains("*"), "a wink is done, not read out")
	var kid: Dictionary = s["npcs"][2].duplicate(true)
	kid["child"] = true
	kid["age"] = 9
	kid["id"] = "kid"
	check(NPCTalk.persona(kid)["tone"] == "child" and String(NPCMind.builtin_reply(kid, s, "Who are you?")["say"]).length() > 0, "children talk like children")
	Eras.theme = was

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

## Speech to text goes to the server set in Settings, else the built-in one, else OpenAI;
## local chat servers can't transcribe, so they are never asked.
func test_speech_to_text_target() -> void:
	var ai = load("res://src/ai/ai_service.gd").new()
	ai.cfg = ai.DEFAULTS.duplicate()
	ai.cfg.merge({"provider": "ollama", "format": "openai", "base_url": "http://127.0.0.1:11434/v1", "model": "llama3.1:8b"}, true)
	check(ai.stt_target().is_empty(), "a local chat server is not a speech-to-text server")
	ai.cfg.merge({"provider": "openai", "base_url": "https://api.openai.com/v1", "api_key": "k"}, true)
	check(String(ai.stt_target().get("url", "")) == "https://api.openai.com/v1/audio/transcriptions", "OpenAI transcribes")
	ai.cfg["stt_url"] = "http://127.0.0.1:8000/v1"
	check(String(ai.stt_target()["url"]) == "http://127.0.0.1:8000/v1/audio/transcriptions" and ai.stt_target()["model"] == "whisper-1", "a set server comes first")
	ai.free()

## Open mic: the speech gate cuts phrases out of a stream at the pauses, ignores clicks
## and steady hum, and only talk meant for the people around draws an answer.
func test_open_mic_gate() -> void:
	var g := SpeechGate.new()
	var rate := 48000.0
	var stream := PackedFloat32Array()
	# silence, a phrase, silence, a click, silence, another phrase, silence
	for part in [[1.0, 0.0], [1.2, 0.2], [1.2, 0.0], [0.05, 0.4], [1.0, 0.0], [0.8, 0.15], [1.2, 0.0]]:
		for i in int(part[0] * rate):
			stream.append(part[1] * sin(float(i) * 0.12) + randf_range(-0.002, 0.002))
	var got: Array = []
	for i in range(0, stream.size(), 1024): # as the capture buffer hands it over
		got.append_array(g.feed(stream.slice(i, i + 1024), rate))
	check(got.size() == 2, "two phrases heard, the click dropped (got %d)" % got.size())
	if got.size() == 2:
		var secs := float((got[0] as PackedFloat32Array).size()) / SpeechGate.RATE
		check(secs > 1.2 and secs < 2.6, "the phrase keeps its start and a short tail (%.2f s)" % secs)
		var wav := SpeechGate.to_wav(got[1])
		check(wav.decode_u32(24) == 16000 and wav.size() == 44 + (got[1] as PackedFloat32Array).size() * 2, "16 kHz WAV for speech to text")
	var hum := SpeechGate.new()
	var steady := PackedFloat32Array()
	steady.resize(int(rate * 4.0))
	for i in steady.size():
		steady[i] = 0.003 * sin(float(i) * 0.05)
	check(hum.feed(steady, rate).is_empty() and not hum.active, "a quiet hum is not speech")
	check(Interject.calls_out("Hey, can anyone spare me 5 marks?") and Interject.calls_out("Where's the smithy") and Interject.calls_out("Hello!"), "calling out to people")
	check(not Interject.calls_out("ugh this inventory is full") and not Interject.calls_out("yeah I'll be on in five minutes"), "talking to yourself draws no answer")

## The built-in natural voices: everyone in a town sounds like someone else, voices fit
## sex and age, accents fit the era, and long lines are spoken sentence by sentence.
func test_builtin_voices() -> void:
	check(Voice.catalog().size() >= 100, "voice table loaded (%d voices)" % Voice.catalog().size())
	for era in [Eras.MEDIEVAL, Eras.SCIFI]:
		var r := RandomNumberGenerator.new()
		r.seed = 7 + era
		var seen := {}
		var people := 0
		var accents := {}
		for i in 40:
			var p := NPCGen.person(r, era, i, 12, -5)
			p["job"] = NPCGen.JOBS[era][i % 8]
			var o := Voice.builtin_for(p)
			check(o == Voice.builtin_for(p), "a person keeps their voice")
			var sid := int(String(o["voice"]).get_slice("@", 0))
			var v: Dictionary = Voice.catalog()[sid]
			check(v["sex"] == ("f" if p["body"]["female"] else "m") or Voice.is_child(p), "voice fits sex")
			seen[[sid, o["pitch"]]] = true
			accents[String(o["voice"]).get_slice("@", 1)] = true
			people += 1
		check(seen.size() == people, "era %d: no two people of a town share a voice (%d of %d)" % [era, seen.size(), people])
		if era == Eras.MEDIEVAL:
			check(not accents.has("en-US") and not accents.has("en-US-nyc"), "no American accents in the old lands")
		else:
			check(accents.has("en-US"), "frontier accents")
	var kid := {"id": "3_4_9", "era": 0, "age": 8, "job": "farmer", "mood": "calm", "body": {"female": false, "build": 1.0},
		"traits": {"friendly": 0.5, "brave": 0.5, "curious": 0.5, "diligent": 0.5, "greedy": 0.5}}
	var old := kid.duplicate(true)
	old["age"] = 70
	check(float(Voice.builtin_for(kid)["pitch"]) > 1.12, "children sound young")
	check(float(Voice.builtin_for(old)["pitch"]) < 0.97, "old folk sound older")
	check(float(Voice.builtin_for(old)["speed"]) * float(Voice.builtin_for(old)["pitch"]) < float(Voice.builtin_for(kid)["speed"]) * float(Voice.builtin_for(kid)["pitch"]), "old folk talk slower")
	check(Voice.pieces("Aye. That's the miller's cart, not mine! Ask him yourself.") == ["Aye. That's the miller's cart, not mine!", "Ask him yourself."], "lines split into sentences")
	check(Voice.pieces("No full stop here") == ["No full stop here"], "a line without a stop")
	check(Voice.pieces("Hmm... let me think. Aye.") == ["Hmm... let me think. Aye."], "short bits stay together")
	var svc = load("res://src/ai/ai_service.gd")
	var body = JSON.parse_string(svc.build_speech({"url": "http://127.0.0.1:1/v1/audio/speech", "key": "t", "model": "builtin"}, "Hi", {"voice": "12@en-GB-scotland", "speed": 0.9, "pitch": 1.1})["body"])
	check(body["voice"] == "12@en-GB-scotland" and is_equal_approx(float(body["speed"]), 0.9), "built-in voice request")

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

## Nobody is a clone: age, weight, muscle and height shape each body (BodyShape), the
## same person always comes out the same, and clothes share the reshaped skin.
func test_body_variety() -> void:
	var b := {"height": 1.0, "build": 0.9, "female": false, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.25, 0.15, 0.08), "hair_style": 2, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}
	var heavy := b.duplicate()
	heavy["build"] = 1.2
	var fem := b.duplicate()
	fem["female"] = true
	check(str(BodyShape.shape(b, 30, "farmer")) == str(BodyShape.shape(b.duplicate(), 30, "farmer")), "a body's shape is the same every time")
	var young := BodyShape.shape(b, 22, "scribe")
	var old := BodyShape.shape(b, 76, "scribe")
	check(float(old["stoop"]) > 0.4 and float(young["stoop"]) < 0.2, "the old stoop (%.2f vs %.2f)" % [old["stoop"], young["stoop"]])
	check(float(old["pace"]) < 0.8 and is_equal_approx(float(young["pace"]), BodyShape.pace(b, 22)), "the old walk slower")
	check(BodyShape.hair_color(b, 74).get_luminance() > BodyShape.hair_color(b, 20).get_luminance() + 0.25, "hair greys with age")
	check(BodyShape.stature(fem, 30) < BodyShape.stature(b, 30) * 0.97, "women are shorter than men of the same height roll")
	check(BodyShape.stature(b, 78) < BodyShape.stature(b, 40), "the old lose a little height")
	var hs := BodyShape.shape(heavy, 40, "innkeeper")
	check(float(hs["girth"]["spine_01"][0][2]) > float(BodyShape.shape(b, 40, "innkeeper")["girth"]["spine_01"][0][2]) + 0.15, "heavier people have a belly")
	check(float(BodyShape.shape(b, 30, "smith")["muscle"]) > float(BodyShape.shape(b, 30, "scribe")["muscle"]), "a smith is more muscled than a scribe")
	# Facial hair: every style turns up among men, none on women.
	var styles := {}
	var womens := 0
	for k in 300:
		var m := b.duplicate()
		m["height"] = 0.9 + 0.0006 * k
		styles[BodyShape.beard(m, 45)] = true
		m["female"] = true
		womens += BodyShape.beard(m, 45)
	check(styles.size() == 6 and womens == 0, "men wear every facial hair style, from clean-shaven to a full beard; women none")
	# Children: small, growing every year, with large heads, no beards and no grey.
	check(BodyShape.stature(b, 4) < 0.6 and BodyShape.stature(b, 10) < BodyShape.stature(b, 14) and BodyShape.stature(b, 14) < BodyShape.stature(b, 30) * 1.0, "children are small and grow with age")
	check(float(BodyShape.shape(b, 5)["head"]) > 1.2 and float(BodyShape.shape(b, 30)["head"]) == 1.0, "a small child's head is large for its body")
	check(BodyShape.head_size(4) > 1.45 and BodyShape.head_size(10) < BodyShape.head_size(6) and BodyShape.head_size(17) < 1.05, "heads grow less than bodies through childhood")
	var k4 := BodyShape.shape(b, 4)
	check(float(k4["legs"]) < 0.9 and float(k4["neck"]) < 0.7 and float(k4["hands"]) < 0.95 and float(BodyShape.shape(b, 30)["legs"]) == 1.0, "small children have short legs and necks and small hands")
	check(BodyShape.beard(b, 10) == 0 and BodyShape.child(30) == 0.0 and BodyShape.child(6) > 0.8, "children have no beards")
	var grey := b.duplicate()
	grey["hair"] = Color(0.6, 0.6, 0.6)
	check(BodyShape.hair_color(grey, 8).s > 0.15, "no child has grey hair")
	check(float(BodyShape.shape(b, 8, "child")["muscle"]) < 0.15 and float(BodyShape.shape(b, 8)["stoop"]) <= 0.05, "children are slight and stand straight")
	# Until Outfit dresses children, a girl gets a plain tunic, never a bodice, apron or cape.
	var girl := b.duplicate()
	girl["female"] = true
	for era in [Eras.MEDIEVAL, Eras.SCIFI]:
		for k in 12:
			girl["cloth"] = Color(0.1 + 0.07 * k, 0.4, 0.3)
			var own := Outfit.wardrobe(girl, era, "child")
			var w := HumanModel.child_safe(own, era)
			if own.get("child", false):
				check(w == own, "Outfit's own child outfits are kept")
				continue
			var sp: Dictionary = w["spec"]
			check(int(sp["vest"]) == 0 and float(sp["apron"]) == 0.0 and float(sp["cape"]) == 0.0 and not sp.get("open", false) and w["child"], "children never wear adult garments")
	if not HumanModel.available():
		return
	var a := HumanModel.new()
	root.add_child(a)
	a.build(heavy, Eras.MEDIEVAL, "innkeeper", 40)
	var c := HumanModel.new()
	root.add_child(c)
	c.build(b, Eras.MEDIEVAL, "innkeeper", 40)
	var cl: MeshInstance3D = a.skeleton.get_node_or_null("Clothes")
	check(a._body.skin != c._body.skin and cl != null and cl.skin == a._body.skin, "each body has its own skin, and its clothes share it")
	var i := 0
	while i < a._body.skin.get_bind_count() and String(a._body.skin.get_bind_name(i)) != "spine_01":
		i += 1
	if i < a._body.skin.get_bind_count():
		check(a._body.skin.get_bind_pose(i).basis.z.length() > c._body.skin.get_bind_pose(i).basis.z.length() + 0.1, "the heavy body's belly is deeper")
	check(a.posture != null and a.ik != null and a.posture.get_index() < a.ik.get_index(), "posture runs before the feet are planted")
	a.free()
	c.free()

## Townsfolk dress for their job and sex, each in their own colours, the same every time
## they load; loose cloth below the waist rides on the legs so strides don't pass through it.
func test_wardrobes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	var looks := {}
	var men_in_gowns := 0
	for i in 40:
		var p := NPCGen.person(r, Eras.MEDIEVAL, i, 0, 0)
		var job: String = NPCGen.JOBS[Eras.MEDIEVAL][i % 8]
		var w := Outfit.wardrobe(p["body"], Eras.MEDIEVAL, job)
		check(str(w) == str(Outfit.wardrobe(p["body"].duplicate(true), Eras.MEDIEVAL, job)), "a wardrobe is the same every time")
		looks[str(w["cols"][Outfit.PART_SHIRT]) + str(w["cols"][Outfit.PART_SKIRT])] = true
		var hem: float = w["spec"]["hem"]
		if not p["body"]["female"] and job != "priest" and hem > 0.0 and hem < 0.45:
			men_in_gowns += 1
		if job == "smith":
			check(w["spec"]["apron"] > 0.0, "smiths wear a leather apron")
		for part in [Outfit.PART_SHIRT, Outfit.PART_PANTS]:
			check(not Outfit._near(w["cols"][part], p["body"]["skin"]), "%s's clothes don't pass for bare skin" % job)
	check(looks.size() >= 36, "nobody dresses like anyone else (%d looks in 40)" % looks.size())
	check(men_in_gowns == 0, "men wear tunics and trousers, not gowns")
	# Children dress as children in every era: nothing low-cut, nothing of a trade.
	for i in 60:
		var p := NPCGen.person(r, Eras.MEDIEVAL, i, 0, 0)
		p["body"]["female"] = i % 2 == 0
		for era in [Eras.MEDIEVAL, Eras.FANTASY, Eras.SCIFI]:
			var w := Outfit.wardrobe(p["body"], era, "child")
			var sp: Dictionary = w["spec"]
			check(w["child"], "a child's wardrobe says it was cut for a child")
			check(sp["vest"] == 0 and sp["apron"] == 0.0 and not sp["bib"] and sp["cape"] == 0.0 and not sp.has("pouch") and not sp.get("open", false),
				"a child wears no bodice, apron, cape, pouch or coat (%s)" % str(sp))
			for part in [Outfit.PART_SHIRT, Outfit.PART_PANTS]:
				check(not Outfit._near(w["cols"][part], p["body"]["skin"]), "a child's clothes don't pass for bare skin")
	if not HumanModel.available():
		return
	var h := HumanModel.new()
	root.add_child(h)
	h.build({"height": 1.0, "build": 1.0, "female": true, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}, Eras.MEDIEVAL, "priest")
	var cl: MeshInstance3D = h.get_node(NodePath(String(h.get_path_to(h.skeleton)) + "/Clothes"))
	var a := cl.mesh.surface_get_arrays(0)
	var custom: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / (custom.size() / 4)
	var on_legs := 0
	var hem_verts := 0
	for v in custom.size() / 4:
		if int(custom[v * 4]) != Outfit.PART_SKIRT or custom[v * 4 + 1] > 0.3:
			continue
		hem_verts += 1
		var leg := 0.0
		for j in per:
			var bi := bones[v * per + j]
			var bn := String(cl.skin.get_bind_name(bi))
			if bn == "":
				bn = h.skeleton.get_bone_name(cl.skin.get_bind_bone(bi))
			if bn.begins_with("thigh") or bn.begins_with("calf"):
				leg += wts[v * per + j]
		if leg > 0.95:
			on_legs += 1
	check(hem_verts > 0 and on_legs == hem_verts, "a robe's hem is carried by the legs (%d of %d)" % [on_legs, hem_verts])
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

## Everything a hand can hold is its real size (HeldScale): no six-foot pickaxes, in a
## villager's hand or yours, whoever is holding it.
## The icon is the standard for an item's look: everything with an icon has a 3D model
## (not its icon on a card, not a painted block) unless it's on GearModels.OWED, and an owed
## item that gains a model must come off the list. tools/icon_match.gd shows each model
## beside its icon to check they match.
func test_icon_models() -> void:
	var items := GearModels.icon_items()
	check(items.size() > 600, "the icon sheets list the items (%d)" % items.size())
	for t: String in items:
		if not ItemDB.ITEMS.has(t):
			continue
		var prop := Viewmodel.prop_for(t)
		var card := HeldScale.unmodelled(prop)
		prop.free()
		if GearModels.OWED.has(t):
			check(card, "%s has a model now: take it off GearModels.OWED" % t)
		else:
			check(not card, "%s has an icon but no model: build it like its icon (or list it on GearModels.OWED)" % t)
	for t: String in GearModels.OWED:
		check(items.has(t), "%s is on GearModels.OWED but has no icon" % t)

func test_held_scale() -> void:
	var checked := 0
	for t: String in ItemDB.ITEMS:
		if ItemDB.def(t).get("kind", "") in ["armor", "ammo", "resource", "vehicle", "station", "camp", "crop"]:
			continue
		var prop := Viewmodel.prop_for(t)
		if not HeldScale.unmodelled(prop):
			checked += 1
			var p := HeldScale.problem(t, prop)
			if HeldScale.OWED.has(t):
				check(p != "", "%s is its real size now: take it off HeldScale.OWED" % t)
			else:
				check(p == "", p)
		prop.free()
	check(checked > 100, "most things held have a model to measure (%d)" % checked)
	if not HumanModel.available():
		return
	var h := HumanModel.new()
	h.scale = Vector3.ONE * 0.9
	root.add_child(h)
	h.build({"height": 1.0, "build": 1.0, "female": true, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}, Eras.MEDIEVAL, "farmer")
	var tool = h._held.get_child(0) if h._held else null
	check(tool == null or String(tool.get_meta("item", "")) in HumanModel.WORK_TOOLS["farmer"], "a farmer works with a farm tool, not a pickaxe")
	for job: String in HumanModel.WORK_TOOLS:
		h._tool(job)
		if h._held == null:
			continue
		var prop: Node3D = h._held.get_child(0)
		var t := String(prop.get_meta("item", ""))
		check(t in HumanModel.WORK_TOOLS[job], "a %s holds their own tool (%s)" % [job, t])
		check(HeldScale.problem(t, prop) == "", "a %s's %s is its real size" % [job, t])
		# The body is drawn at 0.9 of the rig; the tool is not shrunk (or grown) with it.
		check(is_equal_approx(prop.transform.basis.get_scale().x * h.scale.x, 1.0), "a short person's %s is as big as anyone's" % t)
		h.hold(null)
	h.free()

## Muscle-like easing: turns ease off and settle without overshoot, and a skipped frame
## lands where even steps would have. Kit animals' gaits are paced from their hooves'
## IK controllers, and pacing a gallop through its stride keeps the stride's length.
func test_natural_motion() -> void:
	var a := Vector2(0.0, 0.0)
	var peak := 0.0
	for i in 120:
		a = AnimMath.spring(a.x, a.y, 1.0, 8.0, 1.0 / 60.0)
		peak = maxf(peak, a.x)
	check(absf(a.x - 1.0) < 0.001 and peak <= 1.0 + 1e-5, "a spring settles on its mark without overshoot (%.4f)" % a.x)
	var one := AnimMath.spring(0.0, 0.0, 1.0, 8.0, 0.2)
	var two := Vector2.ZERO
	for i in 4:
		two = AnimMath.spring(two.x, two.y, 1.0, 8.0, 0.05)
	check(absf(one.x - two.x) < 1e-4, "one long spring step is four short ones")
	check(absf(AnimMath.drift(3.0, 1.0)) <= 1.0, "a drift stays in -1..1")
	if not AnimalModel.available("Horse"):
		return
	var sc: Node3D = (load(AnimalModel.path_of("Horse")) as PackedScene).instantiate()
	var ap: AnimationPlayer = sc.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = sc.find_children("*", "Skeleton3D", true, false)[0]
	var g := AnimalModel.gaits("Horse", ap, sk)
	check(g.has("Walk") and g.has("Gallop") and float(g["Gallop"]) > float(g["Walk"]) * 2.0, "a horse's gallop covers ground faster than its walk (%s)" % str(g))
	var w: PackedFloat32Array = AnimalModel._warp_cache["Horse"].get("Gallop", PackedFloat32Array())
	var inv := 0.0
	for x in w:
		inv += 1.0 / x
	check(w.size() == 48 and absf(inv / w.size() - 1.0) < 0.01, "pacing a gallop through its stride keeps its length")
	var st: Array = AnimalModel._stance_cache["Horse"].get("Walk", [])
	check(st.size() == 4, "each of a horse's feet knows when it is down in a walk")
	sc.free()

func test_tool_grip() -> void:
	if not HumanModel.available():
		return
	var h := HumanModel.new()
	root.add_child(h)
	h.build(Player.LOOK, Eras.MEDIEVAL, "")
	var sk := h.skeleton
	var prop := Viewmodel.prop_for("pickaxe_iron")
	h.hold(prop)
	check(h.gestures.grip_r == HumanModel.GRIP and not h.gestures.grip_rot.is_empty(), "holding a tool closes the fingers")
	# The handle lies on the palm side, and every finger ends wrapped round it.
	var fr := HandGrip.frame(sk)
	var axis := prop.transform.basis.y.normalized()
	var c := prop.transform * HandGrip.handle_center(prop, HumanModel.grip_point(prop))
	var r := HandGrip.handle_radius(prop, HumanModel.grip_point(prop))
	check((c - Vector3(fr["mcp"])).dot(fr["palm"]) > 0.02, "the handle lies in the palm (%.3f m)" % (c - Vector3(fr["mcp"])).dot(fr["palm"]))
	check(r > 0.01 and r < 0.03, "the handle is a hand's width round (r %.3f m)" % r)
	var inv := sk.get_bone_global_rest(sk.find_bone("hand_r")).affine_inverse()
	for f in HandGrip.FINGERS:
		var ch := HandGrip._chain(sk, f)
		var ax := HandGrip._flex_axes(sk, ch, inv, fr["palm"])
		var ang := []
		for j in 3:
			ang.append((sk.get_bone_rest(ch[j]).basis.get_rotation_quaternion().inverse() * h.gestures.grip_rot[ch[j]]).get_angle())
		var pts := HandGrip._fk(sk, ch, inv, ax, ang)
		var d := INF
		for j in 3:
			d = minf(d, HandGrip._seg_line(pts[j], pts[j + 1], c, axis))
		check(d > r and d < r + HandGrip.FINGER_R + 0.012, "the %s finger closes on the handle without passing into it (%.3f m from its middle)" % [f, d])
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
	var fl := FireFx.flame(0.42)
	var cards := fl.find_children("*", "MeshInstance3D", true, false)
	check(cards.size() == 2 and (cards[0] as MeshInstance3D).material_override == FireFx.material(), "a torch's flame is two cards sharing the fire material")
	fl.free()
	var bon := FireFx.flame(1.0)
	var bcards := bon.find_children("*", "MeshInstance3D", true, false).filter(func(c): return (c as MeshInstance3D).material_override == FireFx.material())
	check(bcards.size() >= 3 and bon.find_child("Coals", true, false) != null, "a big fire burns across its bed, over glowing coals")
	var spread := 0.0
	for c in bcards:
		spread = maxf(spread, Vector2((c as Node3D).position.x, (c as Node3D).position.z).length())
	check(spread > 0.1, "a big fire's tongues stand apart (%.2f m)" % spread)
	var tg := bon.find_child("Tongues", true, false) as GPUParticles3D
	check(tg != null and tg.process_material is ShaderMaterial and not tg.local_coords and tg.amount >= 30,
		"a big fire burns in the round, its tongues rising through the world (%s)" % (tg.amount if tg != null else -1))
	if tg != null:
		check(is_equal_approx(float((tg.process_material as ShaderMaterial).get_shader_parameter("seed")), float(bon.get_meta("fire_seed"))),
			"its tongues leap with the same life as its cards and light")
		check(tg.amount_ratio > 0.0 and tg.amount_ratio <= 1.0 and FireFx.TONGUE_RATIO[0] < FireFx.TONGUE_RATIO[2], "the fire setting sets how many tongues burn")
	var pops := bon.find_child("Pops", true, false)
	check(pops is FireFx.Pops, "now and then a log pops in a fire")
	if pops is FireFx.Pops:
		var waits := []
		for i in 20:
			waits.append(pops._rest())
		check(waits.min() >= 2.0 and waits.max() <= 26.0 and waits.max() - waits.min() > 1.0, "a fire pops at random, every few seconds")
		pops.pop()
		var burst := pops.find_child("Burst", true, false) as CPUParticles3D
		check(burst != null and burst.one_shot and burst.gravity.y < 0.0, "a pop throws sparks that arc and fall back")
	bon.free()
	var jet := FireFx.flame(1.0, Color(1, 1, 1, 1), "jet", true)
	check(jet.find_child("Tongues", true, false) == null and jet.find_child("Pops", true, false) == null, "a jet is no wood fire: no tongues, no pops")
	jet.free()
	var wick := FireFx.flame(0.07)
	var wc := wick.find_children("*", "MeshInstance3D", true, false)
	check(wc.size() == 1 and (wc[0] as MeshInstance3D).material_override == FireFx.wick_material(), "a candle's flame is drawn, not a flipbook blob")
	check(wick.find_child("Tongues", true, false) == null, "a candle burns without tongues")
	var lit := Node3D.new()
	var lfl := FireFx.flame(0.42)
	lit.add_child(lfl)
	var ll := FlickerLight.new()
	ll.light_energy = 2.0
	lit.add_child(ll)
	ll._ready()
	check(is_equal_approx(ll.seed, float(lfl.get_meta("fire_seed"))), "firelight follows the flame beside it")
	FireFx.time = 12.3
	ll.distance_fade_enabled = false
	ll._process(0.0)
	var want := 2.0 * (1.0 + ll.depth * (FireFx.life(12.3, ll.seed) - 0.5) * 2.0)
	check(is_equal_approx(ll.light_energy, want), "firelight leaps and sinks with its flame's life (%.3f, %.3f)" % [ll.light_energy, want])
	lit.free()
	wick.free()
	var lsum := 0.0
	var lmin := 1.0
	var lmax := 0.0
	for i in 2000:
		var lv := FireFx.life(i * 0.037, 0.41)
		lsum += lv
		lmin = minf(lmin, lv)
		lmax = maxf(lmax, lv)
	check(lmin >= 0.0 and lmax <= 1.0 and absf(lsum / 2000.0 - 0.5) < 0.12 and lmax - lmin > 0.4, "a flame's life wavers about the middle (%.2f..%.2f, mean %.2f)" % [lmin, lmax, lsum / 2000.0])
	check(not is_equal_approx(FireFx.life(5.0, 0.1), FireFx.life(5.0, 0.6)), "no two fires flicker in step")
	var lf := FireFx.prop_flames(BuildCatalog.def("lantern")["models"])
	check(lf.size() == 1, "a lantern you hang burns")
	if lf.size() == 1:
		var ln := FireFx.prop_flame(lf[0])
		check(ln.find_child("Glass", true, false) != null, "a lit lantern's glass glows with its flame, seen from any side")
		ln.free()
	var torch := Viewmodel.prop_for("torch")
	check(torch.find_child("Flame", true, false) != null, "a torch in hand burns")
	check(torch.find_child("Drag", true, false) != null, "a carried torch's flame trails as it moves")
	var ttg := torch.find_child("Tongues", true, false) as GPUParticles3D
	check(ttg != null and is_equal_approx(float((ttg.process_material as ShaderMaterial).get_shader_parameter("seed")), HandLight.TORCH_SEED),
		"a carried torch's tongues burn with the seed its light follows")
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
	check(ToolModels.mat("it_wood") in mats and ToolModels.mat("it_leather") in mats and ToolModels.mat("it_pitch") in mats, "a torch is a wooden stick with a leather grip and a pitch-soaked rag head")
	# Tool metal is the shared metal look: forged on a medieval axe, brushed alloy on a
	# sci-fi multitool, rust on a used crowbar, and mirror chrome on none.
	var kinds := func(t: String) -> Array:
		var mesh := ToolModels.build(t)
		var ks := []
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			if sm is ShaderMaterial:
				ks.append(sm.resource_name)
		return ks
	var axe: Array = kinds.call("axe_steel")
	var mt: Array = kinds.call("multitool")
	check("metal_steel" in axe and "metal_iron" in axe and not "metal_chrome" in axe, "a medieval axe head is forged steel and iron in the shared metal look")
	check("metal_alloy" in mt and not "metal_steel" in mt and not "metal_chrome" in mt, "a sci-fi multitool is brushed alloy, not forged steel or mirror chrome")
	check("metal_rusty" in kinds.call("crowbar"), "a crowbar is rusty from use, like its icon")

## Stall awnings and drapes, banners and flags move in the wind.
func test_cloth() -> void:
	var stall := ObjectLibrary.get_mesh("market_stall")
	var cs := -1
	for i in stall.get_surface_count():
		if stall.surface_get_material(i) is ShaderMaterial and (stall.surface_get_material(i) as ShaderMaterial).shader.resource_path.ends_with("cloth.gdshader"):
			cs = i
	check(cs >= 0, "a market stall's canvas is cloth that moves")
	if cs < 0:
		return
	check(stall.surface_get_format(cs) & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "the canvas knows how it hangs")
	var a := stall.surface_get_arrays(cs)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c0: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var hang := 0.0
	var billow := 0.0
	for i in v.size():
		hang = maxf(hang, c0[i * 4])
		billow = maxf(billow, c0[i * 4 + 1])
	check(hang > 0.8 and billow > 0.2, "a stall's back drape hangs free and its roof canvas billows (hang %.2f m, billow %.2f m)" % [hang, billow])
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var longest := 0.0
	for t in range(0, idx.size(), 3):
		for k in 3:
			longest = maxf(longest, v[idx[t + k]].distance_to(v[idx[t + (k + 1) % 3]]))
	# The stall stands 1.2 times its kit size.
	check(longest <= ClothFx.MAX_EDGE * 1.2 + 0.01 and idx.size() / 3 > 2000, "the canvas is cut fine enough to bend smoothly (%d triangles, longest edge %.2f m)" % [idx.size() / 3, longest])
	var sub := ClothFx._subdivide(BuildCatalog.model_parts("props/Banner_1")[2][1], 0.1)
	var sv: PackedVector3Array = sub[Mesh.ARRAY_VERTEX]
	var area := 0.0
	var si: PackedInt32Array = sub[Mesh.ARRAY_INDEX]
	for t in range(0, si.size(), 3):
		area += (sv[si[t + 1]] - sv[si[t]]).cross(sv[si[t + 2]] - sv[si[t]]).length() * 0.5
	var oa: Array = BuildCatalog.model_parts("props/Banner_1")[2][1]
	var ov: PackedVector3Array = oa[Mesh.ARRAY_VERTEX]
	var oi: PackedInt32Array = oa[Mesh.ARRAY_INDEX]
	var oarea := 0.0
	for t in range(0, oi.size(), 3):
		oarea += (ov[oi[t + 1]] - ov[oi[t]]).cross(ov[oi[t + 2]] - ov[oi[t]]).length() * 0.5
	check(absf(area - oarea) < 0.001 * maxf(oarea, 1.0), "cutting cloth finer keeps it the same cloth (%.3f vs %.3f m2)" % [area, oarea])
	var room := Interiors.interior("castle_keep")
	var sheltered := false
	for i in room.get_surface_count():
		var m := room.surface_get_material(i)
		if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("shelter") == 1.0:
			sheltered = true
	check(sheltered, "a keep's banners stir only in a draught indoors")
	var tower := Interiors.build("watchtower")
	var fi := -1
	for i in tower.get_surface_count():
		if tower.surface_get_material(i) == ClothFx.flag_material():
			fi = i
	check(fi >= 0 and tower.surface_get_format(fi) & Mesh.ARRAY_FORMAT_CUSTOM1 != 0, "a watchtower flies a real flag from its pole")

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

## Placement polish: what can share a spot, stairs, and carrying on from a piece you aim at.
## No grass grows up through a floor the player laid, even one at the chunk's edge.
func _grass_under_floors() -> void:
	var g := ChunkGenerator.new(4242)
	var floors := Rect2(56, 20, 8, 6) # four by three cells, the last one on the chunk's edge
	var chunk := {}
	var bare := {}
	for i in 60:
		chunk = g.generate(i, 3)
		bare = ChunkNode.build_grass_buffers(chunk, 1.0)
		if _grass_in(bare, floors) > 100:
			break
	check(_grass_in(bare, floors) > 50, "the test ground is grassy (%d blades)" % _grass_in(bare, floors))
	for x in [57.0, 59.0, 61.0, 63.0]:
		for z in [21.0, 23.0, 25.0]:
			var id := "foundation" if z < 25.0 else "floor_wood"
			chunk["objects"].append({"i": chunk["objects"].size(), "t": BuildCatalog.PREFIX + id, "p": Vector3(x, 0, z), "r": 0.0, "s": 1.0, "e": 0, "st": {}})
	var n := _grass_in(ChunkNode.build_grass_buffers(chunk, 1.0), floors.grow(-0.05))
	check(n == 0, "no grass grows through the floors (%d blades)" % n)

func _grass_in(bufs: Dictionary, r: Rect2) -> int:
	var n := 0
	for k in bufs:
		var b: PackedFloat32Array = bufs[k]
		for i in range(0, b.size(), 16):
			if r.has_point(Vector2(b[i + 3], b[i + 11])):
				n += 1
	return n

func _build_snapping() -> void:
	# Walls are as tall as the storey, so stacked walls meet edge to edge.
	var wa := BuildCatalog.mesh("wall_plaster").get_aabb()
	check(absf(wa.end.y - float(BuildCatalog.def("wall_plaster")["storey"])) < 0.02, "village walls fill one storey (%.3f)" % wa.end.y)
	# The plinth reaches a storey down; the stairs rise exactly one storey over two cells.
	check(BuildCatalog.mesh("foundation").get_aabb().position.y < -3.0, "a foundation's plinth reaches a storey down")
	var sa := BuildCatalog.mesh("stairs_wood").get_aabb()
	check(absf(sa.end.y - 3.12) < 0.05 and absf(sa.position.z + 3.0) < 0.05 and absf(sa.end.z - 1.0) < 0.05, "wooden stairs fill two cells, one storey up (%s)" % sa)
	# Furniture minds only furniture; stairs can stand on a floor.
	var near := [{"id": "foundation", "pos": Vector3(1, 0, 1), "yaw": 0.0}, {"id": "wall_plaster", "pos": Vector3(1, 0, 2), "yaw": 0.0},
		{"id": "chair", "pos": Vector3(3, 0, 3), "yaw": 0.0}]
	check(not BuildCatalog.occupied_in(near, "table", Vector3(1, 0.01, 1), 0.0), "furniture fits in the middle of a floor")
	check(not BuildCatalog.occupied_in(near, "bench", Vector3(1, 0.01, 1.9), 0.0), "and against a wall")
	check(BuildCatalog.occupied_in(near, "stool", Vector3(3.2, 0, 3.1), 0.0), "but not on top of other furniture")
	check(not BuildCatalog.occupied_in(near, "stairs_wood", Vector3(1, 0, 1), 0.0), "stairs stand on a floor")
	check(BuildCatalog.occupied_in(near, "floor_wood", Vector3(1, 0, 1), 0.0), "one floor per cell")
	# Stairs climb away from you, foot in the aimed cell, for both kits.
	for id in ["stairs_wood", "stairs_scifi"]:
		var st := BuildCatalog.snap(id, Vector3(1.0, 0.0, 1.0), 0.0, 0, Vector3(1, 0, 1), true)
		var box := BuildCatalog.world_aabb(id, st["pos"], st["yaw"])
		var g: float = BuildCatalog.def(id)["grid"]
		var cell := Vector3(floorf(1.0 / g) * g + g * 0.5, 0, floorf(1.0 / g) * g + g * 0.5)
		check(absf(box.end.z - (cell.z + g * 0.5)) < 0.1 and box.position.z < cell.z - g, "%s: foot in the aimed cell, climbing away (%s)" % [id, box])
		var hi := BuildCatalog.mesh(id)
		var top_z := 0.0
		var top_y := -1.0
		for s in hi.get_surface_count():
			for v in (hi.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var w: Vector3 = Transform3D(Basis(Vector3.UP, st["yaw"]), st["pos"]) * v
				if w.y > top_y:
					top_y = w.y
					top_z = w.z
		check(top_z < cell.z - g * 0.5, "%s: the high end is the far one" % id)
	# A foundation on the ground beside a house keeps to its floor level even when the
	# nearest piece is its roof.
	var gr := BuildCatalog.snap("foundation", Vector3(7.0, 0.3, 1.0), 0.0, 0, Vector3(4, 6.24, 2), true)
	check(is_equal_approx(gr["pos"].y, 0.0), "ground placement finds the storey nearest the ground (%s)" % gr["pos"])
	# Aiming at a foundation's side is still its storey.
	var sf := BuildCatalog.snap("wall_stone", Vector3(2.05, -0.8, 1.2), 0.0, 0, Vector3(1, 0, 1), false, {"hit_mode": "floor"})
	check(is_equal_approx(sf["pos"].y, 0.0), "a wall aimed at a plinth's side stands on that floor (%s)" % sf["pos"])
	# Aiming at a floor's top carries on to the next cell on that side.
	var ctx := {"hit_mode": "floor", "hit_pos": Vector3(1, 0, 1), "hit_yaw": 0.0, "hit_id": "foundation", "normal": Vector3.UP}
	var fc := BuildCatalog.candidates("foundation", Vector3(1.8, 0.01, 1.1), 0.0, 0, Vector3(1, 0, 1), false, ctx)
	var pick = fc.filter(func(e): return not BuildCatalog.occupied_in(near, "foundation", e["pos"], e["yaw"]))
	check(not pick.is_empty() and (pick[0]["pos"] as Vector3).is_equal_approx(Vector3(3, 0, 1)), "the next floor goes on the side you aim at (%s)" % [pick])
	# A wall aimed at a wall: near its end the next along, in the middle on top.
	var wctx := {"hit_mode": "wall", "hit_pos": Vector3(1, 0, 2), "hit_yaw": 0.0, "hit_id": "wall_plaster", "normal": Vector3.BACK}
	var wend := BuildCatalog.candidates("wall_plaster", Vector3(1.85, 1.5, 2.05), 0.0, 0, Vector3(1, 0, 2), false, wctx)
	check((wend[0]["pos"] as Vector3).is_equal_approx(Vector3(3, 0, 2)), "a wall aimed at another's end continues the line (%s)" % wend[0]["pos"])
	var wmid := BuildCatalog.candidates("wall_plaster", Vector3(1.1, 1.0, 2.05), 0.0, 0, Vector3(1, 0, 2), false, wctx)
	check((wmid[0]["pos"] as Vector3).is_equal_approx(Vector3(1, 3.12, 2)), "aimed at its middle it stacks on top (%s)" % wmid[0]["pos"])
	# A wall's dressed face (local +z) turns away from the room it closes, aimed from inside
	# or out, on the ground floor or the storey above; with no floor either side, toward you.
	var fnear := [{"id": "foundation", "pos": Vector3(1, 0, 1), "yaw": 0.0}]
	var out_in := BuildCatalog.snap("wall_stone", Vector3(1.9, 0.5, 1.2), 0.0, 0, Vector3(1, 0, 1), false, {"hit_mode": "floor", "near": fnear})
	var out_out := BuildCatalog.snap("wall_stone", Vector3(2.1, 0.5, 1.2), 0.0, 0, Vector3(1, 0, 1), true, {"near": fnear})
	var out_up := BuildCatalog.snap("wall_stone", Vector3(1.0, 3.6, -0.1), 0.0, 0, Vector3(1, 0, 1), false, {"hit_mode": "wall", "near": fnear})
	var dressed := func(s: Dictionary) -> Vector3: return Basis(Vector3.UP, float(s["yaw"])) * Vector3.BACK
	check(dressed.call(out_in).is_equal_approx(Vector3(1, 0, 0)) and dressed.call(out_out).is_equal_approx(Vector3(1, 0, 0)), "walls face out of the room (%s, %s)" % [dressed.call(out_in), dressed.call(out_out)])
	check(dressed.call(out_up).is_equal_approx(Vector3(0, 0, -1)), "upstairs too, before its floor is down (%s)" % dressed.call(out_up))
	var bare := BuildCatalog.snap("fence", Vector3(10.9, 0.0, 10.2), 0.0, 0, null, true, {"near": [], "eye": Vector3(10, 1.6, 14)})
	check(dressed.call(bare).is_equal_approx(Vector3(0, 0, 1)), "a lone fence shows you its good side (%s)" % dressed.call(bare))
	# Corner posts stand on the grid corner nearest the aim, on the storey of the wall aimed at.
	var post := BuildCatalog.snap("corner_stone", Vector3(2.8, 4.0, 0.3), 0.0, 0, Vector3(1, 3.12, 0), false, {"hit_mode": "wall"})
	check((post["pos"] as Vector3).is_equal_approx(Vector3(2, 3.12, 0)), "a corner post stands where walls meet (%s)" % post["pos"])
	check(not BuildCatalog.occupied_in(near, "corner_stone", Vector3(0, 0, 0), 0.0), "a corner post fits beside the walls it joins")
	# Window walls are glazed.
	check(BuildCatalog.def("wall_window")["models"].any(func(e): return String(e[0]).begins_with("village/Window_")), "window walls have a glazed frame")
	# A roof aimed at a wall covers the room that wall belongs to.
	var room := []
	for e in [[Vector3(1, 0, 0), 0.0], [Vector3(3, 0, 0), 0.0], [Vector3(1, 0, 4), 0.0], [Vector3(3, 0, 4), 0.0],
			[Vector3(0, 0, 1), PI * 0.5], [Vector3(0, 0, 3), PI * 0.5], [Vector3(4, 0, 1), PI * 0.5], [Vector3(4, 0, 3), PI * 0.5]]:
		room.append({"id": "wall_plaster", "pos": e[0], "yaw": e[1]})
	var rctx := {"hit_mode": "wall", "hit_pos": Vector3(1, 0, 4), "hit_yaw": 0.0, "hit_id": "wall_plaster", "normal": Vector3.UP,
		"eye": Vector3(1, 1.6, 2), "near": room}
	var rc := BuildCatalog.candidates("roof_small", Vector3(1.2, 3.12, 4.0), 0.0, 0, Vector3(1, 0, 4), false, rctx)
	check((rc[0]["pos"] as Vector3).is_equal_approx(Vector3(2, 3.12, 2)), "a roof on a wall top covers its room, even seen from inside (%s)" % rc[0]["pos"])
	# A roof aimed at the same roof goes edge to edge.
	var rrc := BuildCatalog.candidates("roof_small", Vector3(3.5, 4.0, 2.2), 0.0, 0, Vector3(2, 3.12, 2), false,
		{"hit_mode": "roof_v", "hit_pos": Vector3(2, 3.12, 2), "hit_yaw": 0.0, "hit_id": "roof_small", "normal": Vector3.UP})
	check((rrc[0]["pos"] as Vector3).is_equal_approx(Vector3(6, 3.12, 2)), "roofs line up edge to edge (%s)" % rrc[0]["pos"])

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

func test_standing_and_town_gates() -> void:
	var st := Standing.new()
	st.note("0:1_1", "Ashford", Vector2(0, 0), 1.0)
	st.note("0:3_1", "Brookmere", Vector2(900, 0), 1.0)
	st.note("0:9_9", "Farholt", Vector2(5000, 0), 1.0)
	st.note("1:1_1", "Moonbase", Vector2(10, 0), 1.0)
	check(st.score("0:1_1", 1.0) == 0 and Standing.tier_of(0) == "Stranger", "a new town sees a stranger")
	st.deed("0:1_1", "Ashford", Vector2(0, 0), -60.0, 1.0)
	check(st.score("0:1_1", 1.0) == -60 and Standing.tier_of(-60) == "Outcast", "a bad deed counts in full")
	check(st.score("0:3_1", 1.0) < -5 and st.score("0:3_1", 1.0) > -25, "word reaches a town near (%d)" % st.score("0:3_1", 1.0))
	check(st.score("0:9_9", 1.0) == 0 and st.score("1:1_1", 1.0) == 0, "but not one far off, nor another planet")
	check(st.score("0:1_1", 13.0) == -30, "bad deeds halve in %d days (%d)" % [int(Standing.FADE_BAD), st.score("0:1_1", 13.0)])
	st.note("0:2_1", "Coldwell", Vector2(400, 0), 1.0)
	check(st.score("0:2_1", 1.0) < -10, "a town seen for the first time has already heard (%d)" % st.score("0:2_1", 1.0))
	st.set_folk("0:9_9", 60.0)
	check(st.score("0:9_9", 1.0) == 30 and Standing.tier_of(30) == "Known", "townsfolk who like you raise your standing")
	check(st.score("0:9_9", 1.0, 2) == 30 - 2 * Standing.PER_STAR, "being wanted there counts against you")
	st.give_pass("0:9_9", 3.0, "vouched", "9_9_4")
	check(st.has_pass("0:9_9", 2.0) and not st.has_pass("0:9_9", 3.5) and st.pass_of("0:9_9", 2.0)["by"] == "9_9_4", "passes run out")
	var back := Standing.from_data(bytes_to_var(var_to_bytes(st.to_data())))
	check(back.score("0:1_1", 1.0) == -60 and back.has_pass("0:9_9", 2.0) and back.towns["0:3_1"]["name"] == "Brookmere", "standing survives a save")
	back.revoke("0:9_9")
	check(not back.has_pass("0:9_9", 2.0), "a crime tears up the pass")
	# Town tempers come from the people who live there.
	var fx := _npc_fixture()
	var gen: ChunkGenerator = fx[0]
	var site: Dictionary = fx[1]
	var data := NPCGen.generate(777, gen, site, gen.settlement_layout(site))
	var kind := data.duplicate(true)
	var harsh := data.duplicate(true)
	for rec in kind["npcs"]:
		rec["traits"]["friendly"] = 0.95
		rec["traits"]["brave"] = 0.2
		rec["worry"] = "taxes"
	for rec in harsh["npcs"]:
		rec["traits"]["friendly"] = 0.1
		rec["traits"]["brave"] = 0.95
		rec["worry"] = "bandits on the road"
	var tk := GatePolicy.temper(site, kind)
	var th := GatePolicy.temper(site, harsh)
	check(float(th["strict"]) > float(tk["strict"]) + 0.3, "brave, wary folk make a stricter town (%.2f vs %.2f)" % [th["strict"], tk["strict"]])
	check(int(th["need"]) > int(tk["need"]) and int(th["toll"]) > int(tk["toll"]), "a strict town asks more standing and a higher toll")
	check(th["night_shut"] and not tk["night_shut"], "strict towns shut their gates at night")
	harsh["rumors"] = ["The traveller was seen stealing.", "Ada was killed by the traveller."]
	check(float(GatePolicy.temper(site, harsh)["strict"]) >= float(th["strict"]), "trouble you made makes it stricter still")
	var need: int = tk["need"]
	check(GatePolicy.admit(tk, need, false, false, 0, false, 12.0)["ok"], "standing enough: waved through")
	check(GatePolicy.admit(tk, need - 1, false, false, 0, false, 12.0)["why"] == "stranger", "a little less and you're a stranger")
	check(GatePolicy.admit(tk, need - 1, false, true, 0, false, 12.0)["ok"], "a guild seal helps")
	check(GatePolicy.admit(tk, -80, false, false, 0, true, 12.0)["ok"], "a pass is a pass")
	check(GatePolicy.admit(tk, -80, true, false, 0, false, 12.0)["why"] == "citizen", "your own house: you're a citizen")
	check(GatePolicy.admit(tk, 100, true, false, 1, true, 12.0)["why"] == "wanted", "nobody gets in wanted")
	check(GatePolicy.admit(th, int(th["need"]), false, false, 0, false, 23.0)["why"] == "night", "strict gates are shut at night")
	check(GatePolicy.toll(th, 23.0) == 2 * int(th["toll"]), "the night toll is double")
	check(not GatePolicy.sells_pass(-40, 0) and GatePolicy.sells_pass(0, 0) and not GatePolicy.sells_pass(50, 1), "no pass for the Distrusted or the wanted")
	var greedy := {"traits": {"greedy": 0.95}, "rel": 20}
	var honest := {"traits": {"greedy": 0.05}, "rel": 0}
	check(float(GatePolicy.bribe(tk, greedy, 12.0)["odds"]) > 0.7 and float(GatePolicy.bribe(tk, honest, 12.0)["odds"]) < 0.15, "greedy guards take bribes, honest ones don't")
	check(int(GatePolicy.bribe(tk, greedy, 12.0)["price"]) < int(tk["toll"]), "a bribe is cheaper than the toll")
	kind["npcs"][2]["rel"] = 55
	var vs := GatePolicy.vouchers(kind)
	check(vs.size() == 1 and vs[0]["id"] == kind["npcs"][2]["id"] or NPCGen.GUARD_JOBS.has(String(kind["npcs"][2]["job"])), "a friend in town will vouch for you")
	check(GatePolicy.folk_regard(kind) > 0.0, "the people's regard is their mean")
	var shop := GatePolicy.priced({"charge_mult": 1.1, "pay_mult": 0.9}, "Honoured")
	check(is_equal_approx(float(shop["charge_mult"]), 1.1 * 0.86) and float(shop["pay_mult"]) > 0.9, "the Honoured pay less and are paid more")
	check(float(GatePolicy.priced({}, "Distrusted")["charge_mult"]) > 1.2, "the Distrusted pay more")
	check(GatePolicy.port_mesh_ok(), "the portcullis has bars, cross-bars and teeth")
	check(GateWatch.postern_tier({"strict": 0.2}) == 1 and GateWatch.postern_tier({"strict": 0.5}) == 2 and GateWatch.postern_tier({"strict": 0.8}) == 3,
		"a stricter town keeps a harder lock on its postern")
	var pt := {"p": Vector2(10, 0), "yaw": PI / 2.0}
	check(GateWatch.postern_side(pt, true).x > 10.0 and GateWatch.postern_side(pt, false).x < 10.0, "the postern's outer side is away from town")
	check(GateWatch.see_through_odds({"strict": 0.5}, 60, false) == 1.0, "a guard who knows your face sees through a tabard")
	check(GateWatch.see_through_odds({"strict": 0.8}, 0, false) > GateWatch.see_through_odds({"strict": 0.2}, 0, false)
		and GateWatch.see_through_odds({"strict": 0.5}, 0, true) < GateWatch.see_through_odds({"strict": 0.5}, 0, false), "a strict watch is sharper, and night hides you")
	for t in ["grappling_hook", "watch_keys", "writ", "watch_tabard"]:
		check(ItemDB.has(t), "%s is an item" % t)
	check(Recipes.LIST.any(func(r): return r["out"] == "grappling_hook"), "a grappling hook can be made")
	var pm := GateWatch.postern_mesh()
	check(pm.get_aabb().size.y > 2.5 and pm.get_aabb().position.z < -0.7 and pm.get_aabb().end.z > 0.7, "the postern door shows on both faces of the wall")

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
	check(Eras.zone_level(26364, -9360) == Eras.HUMAN_MAX_LEVEL and Eras.zone_level(0, 200000) == Eras.HUMAN_MAX_LEVEL, "human zone levels stop at %d" % Eras.HUMAN_MAX_LEVEL)
	check(int(ZoneInfo.at(77, 26364, -9360)["level_hi"]) <= Eras.HUMAN_MAX_LEVEL, "the minimap never shows a band past the cap")
	# Wonder guardians rate by their zone: a boss near the start is a few levels up, not 60.
	var boss := Creature.species(-100, Eras.MEDIEVAL)
	boss["zone"] = 3
	var elite := Creature.species(-5, Eras.MEDIEVAL)
	elite["zone"] = 3
	var blv := Creature.level_of(boss)
	var elv := Creature.level_of(elite)
	check(blv > elv and elv > 3 and blv <= 3 + WonderSite.BOSS_ABOVE, "a Lv 3 zone's boss is Lv %d and its elites Lv %d" % [blv, elv])
	check(float(boss["hp"]) > float(elite["hp"]), "the boss still outlasts its elites")
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

func test_climates() -> void:
	# Worlds made before climates keep their biomes exactly: no climate bits, no palms.
	var was := WorldField.terrain_v
	WorldField.terrain_v = WorldField.CLIMATE_V - 1
	var old := ChunkGenerator.new(4242)
	check(WorldField.region_climate(old.field.region_hash_at(3000.0, 1200.0)) == Vector2i(-1, -1), "old worlds have no climates")
	var palms_old := 0
	for i in 400:
		for f in Biome.params(WHash.h32(i * 13 + 5), Eras.MEDIEVAL)["flora"]:
			palms_old += 1 if f["t"] == "palm" or f["t"] == "tropic" else 0
	check(palms_old == 0, "no palms in old worlds")
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var kinds := {}
	var hot_wet := 0
	var hot_trees := 0
	var cold := 0
	var cold_palms := 0
	var near_palms := 0
	for iz in range(-14, 15):
		for ix in range(-14, 15):
			var p := Vector2(ix * 400.0, iz * 400.0)
			var h := g.field.region_hash_at(p.x, p.y)
			var c := WorldField.region_climate(h)
			kinds[c] = true
			var bp := Biome.params(h, Eras.MEDIEVAL)
			var tropical := 0
			for f in bp["flora"]:
				if f["t"] == "palm" or f["t"] == "tropic":
					tropical += 1
			if c.x == 3 and c.y >= 2:
				hot_wet += 1
				hot_trees += 1 if tropical > 0 else 0
			if c.x == 0:
				cold += 1
				cold_palms += tropical
			if p.length() < 900.0:
				near_palms += tropical
	check(kinds.size() >= 12, "a world has many climates (%d)" % kinds.size())
	check(hot_wet > 3 and hot_trees == hot_wet, "the wet tropics grow palms and jungle (%d of %d)" % [hot_trees, hot_wet])
	check(cold > 3 and cold_palms == 0, "no palms in the cold")
	check(near_palms == 0, "the land round the spawn is temperate")
	# A climate is the same wherever it is asked for in a region, and region_climate reads
	# it back from the hash.
	var q := g.field.region_site_at(2500.0, -1800.0)
	var sp := g.field.site_pos(q.x, q.y)
	check(g.field.region_hash_at(sp.x, sp.y) == g.field.region_hash_at(2500.0, -1800.0), "one hash per region")
	# Every palm form builds, near and far, with whole-frond LOD groups.
	var forms := {}
	for s in range(1, 400):
		var pp := Flora.species("palm", s)
		if forms.has(pp["form"]):
			continue
		forms[pp["form"]] = true
		var m := RealTree.build("palm", s, 0)
		check(m != null and m.get_surface_count() == 2, "a %s builds bark and leaves" % pp["form"])
		var far := RealTree.far_parts("palm", s, 1)
		var lv: PackedVector3Array = far["leaf"][Mesh.ARRAY_VERTEX]
		var li: PackedInt32Array = far["leaf"][Mesh.ARRAY_INDEX]
		check(lv.size() > 0 and lv.size() % 4 == 0 and li.size() == lv.size() / 4 * 6, "a far %s is whole leaf cards" % pp["form"])
	check(forms.size() == 5, "five kinds of palm (%s)" % [forms.keys()])
	for s in range(1, 60):
		var tp := Flora.species("tropic", s)
		check(RealTree.build("tropic", s, 0) != null, "a %s builds" % tp["form"])
		break
	check(ObjectLibrary.kind("palm") == "tree" and ObjectLibrary.kind("tropic") == "tree" and Durability.TABLE.has("palm"), "palms can be felled")
	check(FarLand.FORMS["palm"] == FarLand.FORM_PALM, "distant palms stand as palms")
	# Regions meet in a band of mixed plants, not on a line: walking from one site to the
	# next, the neighbour's share rises from none to half at the line.
	var s0 := g.field.site_pos(3, 2)
	var s1 := g.field.site_pos(4, 2)
	var shares := []
	for k in 81:
		var p := s0.lerp(s1, k / 80.0)
		var bl := g.field.region_blend(p.x, p.y)
		shares.append(float(bl[2]))
	var steady := true
	for k in range(1, 81):
		steady = steady and absf(float(shares[k]) - float(shares[k - 1])) < 0.2
	check(float(shares[0]) == 0.0 and shares.max() > 0.4 and steady, "regions blend gradually (%s)" % [shares])
	var ca := g.generate(20, 7)
	var cb := g.generate(21, 7)
	var agree := ca.has("biome_mix") and cb.has("biome_mix")
	for j in ChunkGenerator.MIX_N:
		agree = agree and ChunkGenerator.biome_pick(ca, 64.0, j * 8.0, 0.3) == ChunkGenerator.biome_pick(cb, 0.0, j * 8.0, 0.3)
	check(agree, "neighbouring chunks agree on how their regions blend")
	# Mixing species at a border moves nothing: same objects, same places, same order.
	var changed := 0
	var same := true
	var edge_pts := 0
	for k in 41:
		var p := s0.lerp(s1, k / 40.0)
		if float(g.field.region_blend(p.x, p.y)[2]) < 0.3:
			continue
		edge_pts += 1
		var bx := int(floor(p.x / 64.0))
		var bz := int(floor(p.y / 64.0))
		g.mix_species = false
		var plain := g.generate(bx, bz)
		g.mix_species = true
		var mixed := g.generate(bx, bz)
		same = same and plain["objects"].size() == mixed["objects"].size()
		for i in mini(plain["objects"].size(), mixed["objects"].size()):
			var o1: Dictionary = plain["objects"][i]
			var o2: Dictionary = mixed["objects"][i]
			same = same and o1["p"] == o2["p"] and o1["i"] == o2["i"] and o1["s"] == o2["s"]
			changed += 1 if o1.get("sp", 0) != o2.get("sp", 0) else 0
	check(edge_pts > 0 and same, "mixing species at a border keeps every object in its place")
	check(changed > 0, "the neighbour's species mix in near the border (%d)" % changed)
	var grid := ChunkGenerator.biome_mix_grid(ca, Eras.MEDIEVAL, ["grass_tint", "lush", "grass_density"])
	check(grid.size() == ChunkGenerator.MIX_N * ChunkGenerator.MIX_N and grid[0].size() == 5, "grass blends tint, lushness and thickness")
	WorldField.terrain_v = was

func test_kit_flora() -> void:
	# Autumn by the stand: a region's broadleaves have all turned or none have; reds, golds
	# and browns; never up by the snow.
	var turned := 0
	var mixed := 0
	var hues := {}
	var browns := 0
	for i in 300:
		var bp := Biome.params(WHash.h32(i * 7 + 3), Eras.MEDIEVAL)
		var stand: bool = bp.get("autumn", false)
		if stand:
			turned += 1
		for f in bp["flora"]:
			if f["t"] != "oak":
				continue
			var p := Flora.species("oak", f["sp"])
			if bool(p.get("autumn", false)) and not stand:
				mixed += 1
			elif stand:
				var leaf: Color = p["leaf"]
				hues[int(leaf.h / 0.05)] = true
				if leaf.s < 0.42:
					browns += 1
		if stand:
			var high := Biome.fit_flora(bp, {"t": "oak", "sp": 0}, Biome.snow_line)
			check(high.is_empty() or not bool(Flora.species(high["t"], high["sp"]).get("autumn", false)), "no turned leaves by the snow (region %d)" % i)
	check(mixed <= 3, "no lone autumn trees in a green region (%d odd ones)" % mixed)
	check(turned > 25 and turned < 100, "about one region in five is in autumn colour (%d of 300)" % turned)
	check(hues.size() >= 3 and browns > 0, "autumn runs red, orange and gold, with some browns (%d hue bands, %d brown)" % [hues.size(), browns])
	# Each plant its own look, from where it stands: stable, varied, mostly healthy.
	var shades := {}
	var tired := 0
	for i in 400:
		var lk := RealTree.plant_look(i * 3.7 - 600.0, i * -5.3 + 211.0)
		check(lk == RealTree.plant_look(i * 3.7 - 600.0, i * -5.3 + 211.0), "a plant's look depends only on where it stands")
		check(absf(lk.x) <= 1.0 and lk.y >= 0.0 and lk.y <= 0.39 and lk.z >= 0.0 and lk.z <= 0.33, "plant look %d within its ranges" % i)
		shades[int((lk.x + 1.0) * 4.0)] = true
		if lk.y > 0.15 or lk.z > 0.15:
			tired += 1
	check(shades.size() >= 7, "plants come in many leaf shades (%d)" % shades.size())
	check(tired > 40 and tired < 240, "a few plants look tired, most healthy (%d of 400)" % tired)
	var green := Color(0.4, 0.6, 0.3, 0.5)
	check(RealTree.plant_leaf(green, Vector4(0.8, 0, 0, 0.5)) != RealTree.plant_leaf(green, Vector4(-0.8, 0, 0, 2.0)), "two looks give two leaf colours")
	check(RealTree.plant_leaf(green, Vector4(0.8, 0, 0, 0.5)).b < green.b, "a warm look yellows the leaves")
	check(not RealTree.plant_gap(Vector3(1, 3, 0), Vector4(0, 0, 0, 0), 0.01), "a full crown has no gaps")
	check(RealTree.plant_gap(Vector3(1, 3, 0), Vector4(0, 0, 0.3, 0), 0.2) and not RealTree.plant_gap(Vector3(-1, 3, 0), Vector4(0, 0, 0.3, 0), 0.2), "a thinned crown is thinnest on its own side")
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
		if t in ["bone", "animal_fat", "antler", "fur_pelt", "leather", "treasure_map", "fish_raw", "flashlight_dead", "power_cell_spent"]:
			continue # butchered, from treasure maps, caught, or a spent flashlight or cell
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
	# Every walking animal has a real model: none falls back to the block body.
	for e in Creature.NAMES.size():
		for n in Creature.NAMES[e].get("quad", []) + Creature.NAMES[e].get("hexa", []):
			check(AnimalModel.available(Creature.KIT_OF.get(n, "")), "%s has a rigged model" % n)
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
	check(Stronghold.guards(found).size() == Stronghold.sentries(found), "sentries keep the gate")
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

func test_dungeons() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var forts: Array = []
	for cz in range(-8, 8):
		for cx in range(-8, 8):
			var f := Stronghold.at_cell(g, cx, cz)
			if not f.is_empty():
				forts.append(f)
	check(forts.size() >= 3, "a few strongholds to dig under (%d)" % forts.size())
	var big := 0
	for f in forts.slice(0, 6):
		var pl := Dungeon.plan(g, f)
		Dungeon._cache.clear()
		var again := Dungeon.plan(g, f)
		check(again["rooms"].size() == pl["rooms"].size() and again["locks"].size() == pl["locks"].size()
			and again["parts"].size() == pl["parts"].size(), "a dungeon's plan is the same every time")
		if pl["levels"].is_empty():
			continue
		var rooms := Dungeon.room_count(pl)
		if pl["levels"].size() >= 2:
			big += 1
		check(rooms >= 4, "a dungeon has rooms to explore (%d)" % rooms)
		# Every seal can be opened in turn: its parts and its door are reachable with the
		# seals before it open, and nothing is left behind once all are.
		for li in pl["locks"].size():
			var seen := Dungeon._reach(pl, func(x: int) -> bool: return x < li)
			var lk: Dictionary = pl["locks"][li]
			var fr: Array = Dungeon.front_of(pl, li)
			check(seen.has(Dungeon._key(lk["lv"], fr[0])), "seal %d of %s can be reached" % [li, pl["id"]])
			for pi in lk["parts"]:
				var p: Dictionary = pl["parts"][pi]
				var c := Dungeon.cell_at(pl, Vector2(p["p"].x, p["p"].z))
				check(seen.has(Dungeon._key(p["lv"], c)), "the %s for seal %d of %s is on the near side" % [p["kind"], li, pl["id"]])
			check(String(lk.get("hint", "")) != "" and String(lk.get("sealed", "")) != "", "seal %d says how it opens" % li)
		var all := Dungeon._reach(pl, func(_x: int) -> bool: return true)
		for ri in pl["rooms"].size():
			var rm: Dictionary = pl["rooms"][ri]
			if rm["kind"] == "gone":
				continue
			var any := false
			for q in Dungeon._cells(rm):
				any = any or all.has(Dungeon._key(rm["lv"], q))
			check(any, "room %d of %s can be reached" % [ri, pl["id"]])
		# Everything walkable lies under the courtyard's ground, with earth over it.
		for lv in pl["levels"].size():
			check(Dungeon.floor_y(pl, lv) + Dungeon.HALL_H < float(pl["y0"]) - 1.0, "level %d is underground" % lv)
	check(big > 0, "some dungeons go more than one level down")
	# Stocking: the centre chunk gets the dungeon's state, its chests and guards, and the
	# mouth is opened in the ground, once.
	var f: Dictionary = forts[0]
	var pl := Dungeon.plan(g, f)
	var k: Vector2i = pl["chunk"]
	var ch := g.generate(k.x, k.y)
	ch.erase("dg_v")
	var before: int = ch["objects"].size()
	check(Dungeon.stock(g, ch), "a fort's chunk is stocked")
	check(ch.has("dgn"), "the centre chunk keeps the dungeon's state")
	var m := Dungeon.mouth(pl)
	var mw := Dungeon.to_world(pl, Vector3(m.x, 0, m.y - 2.0))
	var mk := ChunkStreamer.chunk_of(mw)
	var mc := ch if mk == k else g.generate(mk.x, mk.y)
	if mk != k:
		Dungeon.stock(g, mc)
	var mh: PackedByteArray = mc.get("hole", PackedByteArray())
	var hi := clampi(roundi(mw.x - mk.x * ChunkGenerator.SIZE), 0, ChunkGenerator.RES - 1)
	var hj := clampi(roundi(mw.z - mk.y * ChunkGenerator.SIZE), 0, ChunkGenerator.RES - 1)
	check(not mh.is_empty() and mh[hj * ChunkGenerator.RES + hi] != 0, "the stair's mouth is open in the ground")
	var n: int = ch["objects"].size()
	check(not Dungeon.stock(g, ch) and ch["objects"].size() == n, "stocked only once")
	var dg := 0
	for o in ch["objects"].slice(before):
		if String(o["st"].get("dg", "")) == String(pl["id"]):
			dg += 1
	var guards := 0
	for gd in ch.get("guards", []):
		if gd.has("dg"):
			guards += 1
	check(dg + guards > 0 or pl["loot"].is_empty(), "the dungeon's chests and guards land in their chunks")

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

## Outpost blocks come in several looks by where they stand, each a whole building with
## its own paint and fittings, and a look's key still finds its type's rooms.
func test_outpost_variants() -> void:
	for t in KitBase.VARIANTS:
		var keys := {}
		for i in 60:
			keys[ObjectLibrary.mesh_key({"t": t, "p": Vector3(i * 7.3, 0, i * 3.1)})] = true
		check(keys.size() == int(KitBase.VARIANTS[t]), "%s comes in %d looks (%s)" % [t, KitBase.VARIANTS[t], keys.keys()])
		var plain := ObjectLibrary.get_mesh(t)
		var plain_v := 0
		for i in plain.get_surface_count():
			plain_v += (plain.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for key: String in keys:
			check(key.get_slice(Stronghold.VAR, 0) == t, "%s is still a %s" % [key, t])
			var m := ObjectLibrary.get_mesh(key)
			var n := 0
			for i in m.get_surface_count():
				n += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			check(n > plain_v, "%s has its own paint and fittings (%d vertices, plain %d)" % [key, n, plain_v])

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

func test_net_merge() -> void:
	# Two players edit the same chunk from the same copy: both edits stay.
	var base := {"cx": 1, "objects": [{"t": "door", "st": {"open": false}}, {"t": "tree", "st": {}}],
		"corpses": {"bag1": {"kind": "bag", "items": [1]}, "deer": {"kind": "animal"}}, "fauna_dead": {}}
	var alice := base.duplicate(true)
	alice["objects"][0]["st"]["open"] = true # opened the door
	alice["corpses"].erase("bag1") # emptied the bag
	var bob := base.duplicate(true)
	bob["fauna_dead"]["7_7_0"] = 3.0 # killed a deer
	bob["objects"][1]["st"]["gone"] = true # felled the tree
	bob["objects"].append({"t": "wall", "st": {}}) # built a wall
	var m: Dictionary = NetMerge.merge3(base, bob, alice) # Bob's save lands after Alice's
	check(m["objects"][0]["st"]["open"] == true and m["objects"][1]["st"].get("gone", false), "both players' object edits are kept")
	check(not m["corpses"].has("bag1") and m["corpses"].has("deer"), "a bag taken stays taken")
	check(m["fauna_dead"].has("7_7_0") and m["objects"].size() == 3, "a kill and a new piece are kept")
	# Both built at once: both pieces stay.
	var a2 := base.duplicate(true)
	a2["objects"].append({"t": "chest", "st": {}})
	var m2: Dictionary = NetMerge.merge3(base, bob, a2)
	check(m2["objects"].size() == 4, "two players building at once keep both pieces")
	# The same thing changed on both sides: the newer save wins.
	var c1 := base.duplicate(true)
	c1["objects"][0]["st"]["open"] = true
	var c2 := base.duplicate(true)
	c2["objects"][0]["st"]["open"] = 1
	check(NetMerge.merge3(base, c2, c1)["objects"][0]["st"]["open"] == 1, "a real clash takes the newer save")
	# Towns: people merge by id; records changed on one side keep the other's changes.
	var town := {"sx": 1, "sz": 2, "npcs": [{"id": "a", "hp": 100.0, "rel": 0, "mem": []}, {"id": "b", "hp": 100.0, "rel": 0, "mem": []}]}
	var holder := town.duplicate(true)
	holder["npcs"][0]["pos"] = Vector3(5, 0, 5)
	holder["npcs"][1]["mem"] = ["Day 2: sold bread"]
	var hitter := town.duplicate(true)
	hitter["npcs"][0]["hp"] = 40.0
	hitter["npcs"][0]["rel"] = -35
	hitter["npcs"].append({"id": "c", "hp": 100.0})
	var t: Dictionary = NetMerge.merge3(town, hitter, holder)
	check(t["npcs"].size() == 3 and t["npcs"][0]["hp"] == 40.0 and t["npcs"][0]["pos"] == Vector3(5, 0, 5), "a blow and a walk on the same person both count")
	check(t["npcs"][1]["mem"].size() == 1 and t["npcs"][2]["id"] == "c", "and other people's records and new hires stay")
	# Merging a pushed town into the live one keeps the same record objects.
	var live := town.duplicate(true)
	var rec_a: Dictionary = live["npcs"][0]
	rec_a["mood"] = "happy" # an unsaved change here
	NetMerge.merge_into(live, town, hitter)
	check(live["npcs"][0] == rec_a and is_same(live["npcs"][0], rec_a), "people keep their records when a town is merged in")
	check(rec_a["hp"] == 40.0 and rec_a["mood"] == "happy" and live["npcs"].size() == 3, "with their changes and yours")
	var gone := hitter.duplicate(true)
	gone["npcs"].remove_at(1)
	NetMerge.merge_into(live, hitter, gone)
	check(live["npcs"].size() == 2 and is_same(live["npcs"][0], rec_a), "someone removed over there goes here too")

func test_server_sync() -> void:
	var host := Node.new()
	host.set_script(load("res://tests/fake_host.gd"))
	var sync := ServerSync.new(host)
	var r1 := sync.next_rev()
	check(sync.next_rev() > r1, "revisions rise")
	var k := Vector3i(0, 4, 5)
	var v1 := {"cx": 4, "cz": 5, "a": 1, "b": 1, "_rev": r1}
	sync.remember("c", k, r1, NetPack.pack(v1))
	var cur := v1.duplicate()
	cur["a"] = 2
	cur["_rev"] = sync.next_rev()
	var mine := v1.duplicate()
	mine["b"] = 3
	var m: Array = sync.merge_save("c", k, mine, cur)
	check(m[1] and m[0]["a"] == 2 and m[0]["b"] == 3, "a save from an older copy is merged with the newer one")
	var same := cur.duplicate()
	same["b"] = 9
	m = sync.merge_save("c", k, same, cur)
	check(not m[1] and m[0]["b"] == 9, "a save from the current copy is kept as it is")
	for i in ServerSync.HISTORY + 1:
		sync.remember("c", k, sync.next_rev(), NetPack.pack(v1))
	check(sync.version("c", k, r1) == null, "only the last few versions are kept")
	host.online = {10: {"pos": Vector3(0, 0, 0)}, 11: {"pos": Vector3(500, 0, 0)}, 12: {"pos": Vector3(100, 0, 0)}}
	sync.watch(10, "t", 0, [[Vector2i(1, 1), Vector2(0, 0)]], [])
	sync.watch(11, "t", 0, [[Vector2i(1, 1), Vector2(0, 0)]], [])
	sync.watch(12, "t", 0, [[Vector2i(1, 1), Vector2(0, 0)]], [])
	check(sync.holder_of("t", Vector3i(0, 1, 1)) == 10, "the first player to load a town runs it")
	sync.watch(10, "t", 0, [], [Vector2i(1, 1)])
	check(sync.holder_of("t", Vector3i(0, 1, 1)) == 12, "then the nearest of the others")
	sync.drop_peer(12)
	check(sync.holder_of("t", Vector3i(0, 1, 1)) == 11 and sync.watchers("t", Vector3i(0, 1, 1)) == [11], "and whoever is left when they go")
	sync.drop_peer(11)
	check(sync.holder_of("t", Vector3i(0, 1, 1)) == 0, "nobody runs a town nobody has loaded")
	host.free()

func test_pack_c_items() -> void:
	for t in ["laser_pistol", "plasma_rifle", "gauss_rifle", "smart_pistol", "auto_shotgun", "sniper_rail", "minigun",
			"flamethrower", "rocket_launcher", "grenade_launcher", "needle_gun", "carbine_combat"]:
		var d := ItemDB.def(t)
		check(ItemDB.has(String(d.get("ammo", ""))), "%s fires a real item (%s)" % [t, d.get("ammo", "")])
		check(int(d["era"]) == Eras.SCIFI and ItemDB.UNLOCK.get(t, 0) >= 25 and ItemDB.UNLOCK.get(t, 0) <= 50, "%s is a level 25-50 gun" % t)
		check(String(d.get("tracer", "glow_cyan")) in ["bolt", "glow_cyan", "glow_teal", "glow_violet", "glow_white", "glow_warm", "glow_red"], "%s has a tracer the guns can draw" % t)
	for t in ["laser_cutter", "welder", "mining_laser"]:
		check(ItemDB.def(t).get("beam", false) and ItemDB.def(t).has("beam_dps"), "%s cuts with a beam" % t)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		check(Rarity.of(ItemDB.make("chest_power", 1, 1.0, {}, rng)) >= Rarity.EPIC, "power armour is never plain")
	# Stealth gear makes you harder to notice; a hacking tablet picks locks better.
	var st := Stats.new()
	var n0 := st.notice_mult(false)
	st.bonus = Effects.bonus({"chest": {"type": "suit_stealth"}, "back": {"type": "cloak_optic"}}, {})
	check(st.notice_mult(false) < n0 * 0.8, "stealth gear hides you (%.2f)" % st.notice_mult(false))
	st.bonus = Effects.bonus({}, {"hidden": 10.0})
	check(st.notice_mult(false) <= n0 * 0.5, "standing in smoke hides you")
	st.bonus = Effects.bonus({"neck": {"type": "hack_tablet"}}, {})
	check(st._b("lock") > 0.0, "a hacking tablet helps with locks")
	st.bonus = Effects.bonus({}, {"shielded": 10.0})
	check(float(st.bonus.get("armor", 0.0)) >= 30.0, "a shield generator adds armour")
	check(ItemDB.def("jetpack_military").get("slot", "") == "back" and float(ItemDB.def("jetpack_military")["jet"]) > 1.0, "the military jump pack is worn and lifts harder")
	# Turrets keep their shots left through a save.
	var tr := Traps.new()
	tr.add("turret_deploy", Vector3(1, 2, 3), 12)
	var back := Traps.new()
	back.from_data(JSON.parse_string(JSON.stringify(tr.to_data())))
	check(back.count() == 1 and int(back.to_data()[0]["shots"]) == 12, "a turret keeps its shots left")
	tr.free()
	back.free()
	for t in ["scanner", "drone_scout", "shield_gen", "beacon_nav", "o2_canister", "defibrillator", "grapple", "turret_deploy"]:
		check(Effects.describe(ItemDB.def(t)).size() > 0, "%s says what it does" % t)
	# The sci-fi ores turn up only out in the sci-fi zones.
	rng.seed = 11
	var near := Byproducts.of_object("iron_vein", 400, 5, rng).map(func(e): return e[0])
	var far := Byproducts.of_object("iron_vein", 400, 30, rng).map(func(e): return e[0])
	check(not near.has("titanium_ore") and far.has("titanium_ore"), "titanium is found out past level 25")
	# Caches in the frontier zones hold nothing from the sci-fi age; far out they do.
	var was := Eras.theme
	Eras.theme = "human"
	var early_ok := true
	var late := 0
	for i in 200:
		rng.seed = 1900 + i
		for it in ItemDB.roll_loot(Eras.SCIFI, rng, {"chunk": Vector2i(33, 0)}, 0.6):
			if ItemDB.UNLOCK.get(it["type"], 1) >= 25:
				early_ok = false
		rng.seed = 2900 + i
		# Zone level 40: about 5.9 km out.
		for it in ItemDB.roll_loot(Eras.SCIFI, rng, {"chunk": Vector2i(92, 0)}, 0.4):
			if ItemDB.UNLOCK.get(it["type"], 1) >= 25:
				late += 1
	Eras.theme = was
	check(early_ok, "frontier caches hold no sci-fi gear")
	check(late > 30, "far-out caches hold the sci-fi age (%d)" % late)

func test_pack_d_items() -> void:
	for t in ["bio_rifle", "star_pistol", "crystal_bow", "hive_cannon", "singularity_orb", "spore_launcher", "shard_gauntlet",
			"precursor_rifle", "nova_staff", "eclipse_bow"]:
		var d := ItemDB.def(t)
		check(ItemDB.has(String(d.get("ammo", ""))), "%s fires a real item (%s)" % [t, d.get("ammo", "")])
		check(d.get("alien", false) and ItemDB.UNLOCK.get(t, 0) >= 50, "%s is alien endgame gear" % t)
	var r0 := RandomNumberGenerator.new()
	r0.seed = 3
	check(Rarity.of(ItemDB.make("worldbreaker", 1, 1.0, {}, r0)) >= Rarity.LEGENDARY, "a found Worldbreaker is legendary")
	# Implants: each kind fits once, its points kept through a save.
	var st := Stats.new()
	var str0: int = st.attrs["str"]
	check(st.fit_implant("implant_arm", ItemDB.def("implant_arm")["implant"]), "an arm implant fits")
	check(st.attrs["str"] == str0 + 1, "and makes you stronger")
	check(not st.fit_implant("implant_arm", ItemDB.def("implant_arm")["implant"]) and st.attrs["str"] == str0 + 1, "a second of the same kind does not")
	var back := Stats.from_data(JSON.parse_string(JSON.stringify(st.to_data())))
	check(back.implants == ["implant_arm"] and back.attrs["str"] == str0 + 1, "implants are saved")
	check(Stats.from_data({"level": 2}).implants.is_empty(), "older saves have no implants")
	check(Effects.describe(ItemDB.def("symbiote")).size() > 0, "an implant says what it does")
	# Alien work turns up only on alien worlds.
	var was := Eras.theme
	var rng := RandomNumberGenerator.new()
	Eras.theme = "human"
	var human_ok := true
	for i in 200:
		rng.seed = 3900 + i
		for it in ItemDB.roll_loot(Eras.SCIFI, rng, {"chunk": Vector2i(100, 0)}, 0.8):
			if ItemDB.def(it["type"]).get("alien", false):
				human_ok = false
	check(human_ok, "human worlds hold no alien loot, however far out")
	Eras.theme = "alien"
	var base := Eras.base_level
	Eras.base_level = 60
	var alien := 0
	var human_gear := 0
	for i in 200:
		rng.seed = 4900 + i
		for it in ItemDB.roll_loot(Eras.SCIFI, rng, {"chunk": Vector2i(4, 0)}, 0.6):
			if ItemDB.def(it["type"]).get("alien", false):
				alien += 1
			elif Rarity.is_gear(it["type"]) and ItemDB.UNLOCK.get(it["type"], 1) >= 25:
				human_gear += 1
	Eras.base_level = base
	Eras.theme = was
	check(alien > 30, "xeno caches hold alien work (%d)" % alien)
	check(human_gear == 0, "and no human sci-fi gear (%d)" % human_gear)
	# Alien beasts give up alien parts.
	Eras.theme = "alien"
	rng.seed = 5
	var parts := CorpseLoot.animal_yields({"name": "Test Beast", "size": 1.5, "drops": [["raw_meat", 1], ["hide", 1]]}, 1.0, 0.0, rng).map(func(e): return e[0])
	Eras.theme = was
	check(parts.has("hide_xeno") and parts.has("meat_xeno"), "an alien beast gives xeno hide and meat (%s)" % str(parts))

func test_pack_e_items() -> void:
	# Better loads go in first, and each changes the shot.
	var inv := Inventory.new()
	inv.add(ItemDB.make("arrow", 10, 1.0, {}))
	check(ItemDB.ammo_next(inv, "arrow") == "arrow", "plain arrows when that is all you carry")
	inv.add(ItemDB.make("arrow_barbed", 5, 1.0, {}))
	inv.add(ItemDB.make("arrow_fire", 3, 1.0, {}))
	check(ItemDB.ammo_next(inv, "arrow") == "arrow_fire", "fire arrows are nocked first")
	check(ItemDB.ammo_carried(inv, "arrow") == 18, "every kind of arrow counts toward what a bow can shoot")
	check(float(ItemDB.ammo_mods("arrow", "arrow_fire").get("damage", 1.0)) > 1.0, "a fire arrow hits harder")
	check(ItemDB.ammo_mods("arrow", "arrow").is_empty(), "a plain arrow is plain")
	check(int(ItemDB.ammo_mods("shotgun_shells", "slug_shells").get("pellets", 8)) == 1, "a slug is one heavy ball")
	for a in ItemDB.AMMO_VARIANTS:
		for v in ItemDB.AMMO_VARIANTS[a]:
			check(ItemDB.has(v[0]) and ItemDB.has(a), "%s is a real load for %s" % [v[0], a])
	check(String(ItemDB.def("speed_loader").get("loader", "")) == "rounds", "a speed loader holds rounds")
	check(String(ItemDB.def("power_cell").get("spent", "")) == "power_cell_spent", "a used cell leaves its shell")
	# Jetpack fuels: jet fuel first, and every kind adds thrust.
	check(ItemDB.JET_FUELS[0][0] == "jet_fuel", "plain jet fuel loads first")
	var inv2 := Inventory.new()
	inv2.add(ItemDB.make("rocket_fuel", 1, 1.0, {}))
	var tank := {"type": "jetpack"}
	check(ItemDB.load_jet_fuel(tank, inv2) != "" and float(tank["fuel"]) == 40.0 and inv2.count("rocket_fuel") == 0, "rocket propellant fills the jetpack's tank")
	for f in ItemDB.JET_FUELS:
		check(ItemDB.has(f[0]), "%s is a real fuel" % f[0])
	for f in HandLight.LANTERN_FUEL:
		check(ItemDB.has(f[0]), "%s is a real lantern fuel" % f[0])
	check(Effects.describe(ItemDB.def("rounds_box")).size() > 0 and Effects.describe(ItemDB.def("rifle_clip")).size() > 0, "boxes and clips say what they do")

func test_easter_eggs() -> void:
	var keep_tv := WorldField.terrain_v
	var keep_theme := Eras.theme
	var keep_eras := WorldField.allowed_eras
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	WorldField.allowed_eras = [Eras.MEDIEVAL, Eras.SCIFI]
	Eras.theme = "human"
	var g := ChunkGenerator.new(4242, true)
	var kinds := {}
	var plans: Array = []
	for wz in range(-5, 5):
		for wx in range(-5, 5):
			var e := EasterEggs.plan(g, wx, wz)
			if e.is_empty():
				continue
			plans.append(e)
			kinds[e["t"]] = true
			var p: Vector2 = e["p"]
			check(EasterEggs.cell_of(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.y / ChunkGenerator.SIZE))) == Vector2i(wx, wz), "a find stays in its own cell")
			if int(e["era"]) == Eras.SCIFI:
				check(e["t"] in ["lost_camp", "msg_bottle"], "no sword, gnome or tiny door in human sci-fi land (%s)" % e["t"])
	check(plans.size() > 10 and plans.size() < 60, "finds are rare but there (%d of 100 cells)" % plans.size())
	check(kinds.size() >= 4, "most kinds of find turn up (%s)" % str(kinds.keys()))
	# Pure in the seed: a fresh generator plans the same.
	EasterEggs._plans.clear()
	var g2 := ChunkGenerator.new(4242, true)
	var e0: Dictionary = plans[0]
	var c0 := EasterEggs.cell_of(int(floor(e0["p"].x / ChunkGenerator.SIZE)), int(floor(e0["p"].y / ChunkGenerator.SIZE)))
	check(EasterEggs.plan(g2, c0.x, c0.y) == e0, "plans are deterministic")
	# The chunk that holds a planned find places it, once, near the spot.
	var placed := 0
	for e in plans.slice(0, 6):
		var p: Vector2 = e["p"]
		var cx := int(floor(p.x / ChunkGenerator.SIZE))
		var cz := int(floor(p.y / ChunkGenerator.SIZE))
		var n := 0
		for o in g.generate(cx, cz)["objects"]:
			if o["t"] == e["t"]:
				n += 1
				check(Vector2(cx * ChunkGenerator.SIZE + o["p"].x, cz * ChunkGenerator.SIZE + o["p"].z).distance_to(p) < 10.0, "placed near its planned spot")
		check(n <= 1, "one find per chunk")
		placed += n
	check(placed >= 5, "planned finds get placed (%d of 6)" % placed)
	# A journal's rumour points at another find, not at itself.
	var near := EasterEggs.nearest(g, e0["p"], 1400.0, e0["p"])
	check(near.is_empty() or (near["p"] as Vector2).distance_to(e0["p"]) > 30.0, "a rumour points elsewhere")
	# Using them: what they offer before and after.
	var sword := {"t": "sword_stone", "e": 0, "i": 0, "st": {}}
	check(Wonders.has("sword_stone") and Wonders.unbreakable("sword_stone"), "finds are used, not broken")
	check(Wonders.use_of(sword, 3.0).get("verb", "") != "", "an untouched sword offers a pull")
	check(ObjectLibrary.mesh_key(sword) == "sword_stone", "sword mesh before")
	sword["st"]["drawn"] = true
	check(Wonders.use_of(sword, 3.0).is_empty(), "a drawn sword offers nothing")
	check(ObjectLibrary.mesh_key(sword) == "sword_stone~drawn", "an empty stone once drawn")
	var door := {"t": "tiny_door", "e": 0, "i": 0, "st": {"used": true, "day": 3}}
	check(EasterEggs.use_of(door, 3.5).is_empty() and not EasterEggs.use_of(door, 4.1).is_empty(), "the tiny door answers once a day")
	check(ObjectLibrary.mesh_key({"t": "lost_camp", "e": Eras.SCIFI, "st": {}}) == "lost_camp~s", "the sci-fi camp")
	for t in EasterEggs.TYPES:
		check(ObjectLibrary.kind(t) == "structure" and ObjectLibrary.label(t) == EasterEggs.LABELS[t], "%s is a labelled structure" % t)
		check(ObjectLibrary.get_mesh(t).get_surface_count() > 0, "%s has a mesh" % t)
		check(not ItemDB.def(EasterEggs.ICON[t]).is_empty(), "%s has an icon item" % t)
	# Alien worlds keep only the explorer's camp.
	Eras.theme = "alien"
	WorldField.allowed_eras = [Eras.FANTASY, Eras.SCIFI]
	EasterEggs._plans.clear()
	var ga := ChunkGenerator.new(99, true)
	for wz in range(-3, 3):
		for wx in range(-3, 3):
			var e := EasterEggs.plan(ga, wx, wz)
			check(e.is_empty() or e["t"] == "lost_camp", "alien worlds only hide camps")
	EasterEggs._plans.clear()
	WorldField.terrain_v = keep_tv
	Eras.theme = keep_theme
	WorldField.allowed_eras = keep_eras

func test_server_alliances() -> void:
	var host := Node.new()
	host.set_script(load("res://tests/fake_host.gd"))
	host.pids = ["p1", "p2", "p3", "p4"]
	for i in 4:
		host.online[i + 1] = {"pid": host.pids[i], "planet": 0, "pos": Vector3(i * 10, 0, 0)}
	var path := "user://test_alliances_%d.dat" % Time.get_ticks_usec()
	var al := ServerAlliances.new(host, path)
	check(al.command("p1", "Ann", "invite", "p2") != "", "you can't invite without an alliance")
	check(al.command("p1", "Ann", "create", "x") != "", "a name needs two letters")
	check(al.command("p1", "Ann", "create", "Iron [Wolves]") == "", "anyone can found an alliance")
	var id := al.of("p1")
	check(id != "" and al.list[id]["name"] == "Iron Wolves" and al.list[id]["leader"] == "p1", "named, with its founder leading (%s)" % al.list.get(id))
	check(al.command("p2", "Bob", "create", "iron wolves") != "", "names are unique")
	check(al.command("p2", "Bob", "accept", id) != "", "you can't join uninvited")
	check(al.command("p1", "Ann", "invite", "p2") == "" and host.views["p2"][1].size() == 1, "an invitation reaches them")
	check(not al.allied("p1", "p2"), "an invitation alone doesn't ally you")
	check(al.command("p2", "Bob", "accept", id) == "" and al.allied("p1", "p2") and al.allied("p2", "p1"), "accepting allies you both ways")
	check(host.views["p1"][0]["members"].has("p2") and host.views["p2"][0]["name"] == "Iron Wolves", "both are told")
	check(not al.allied("p1", "p1") and not al.allied("p1", "p3"), "nobody else is allied")
	al.command("p2", "Bob", "invite", "p3")
	al.command("p3", "Cat", "accept", id)
	check(al.command("p1", "Ann", "invite", "p4") != "", "an alliance is capped at max_alliance")
	check(al.command("p2", "Bob", "kick", "p3") != "", "only the leader removes members")
	al.command("p2", "Bob", "chat", "hello")
	check(host.chats.size() == 3 and host.chats.all(func(c): return c[1] == "Bob" and c[2] == "hello"), "alliance chat reaches every member")
	al.set_homes("p2", [[0, 10.0, 20.0]])
	check(host.views["p1"][0]["homes"].get("p2", []) == [[0, 10.0, 20.0]] and not host.views["p2"][0]["homes"].has("p2"), "allies are told which houses each other owns")
	var at := al.positions()
	check(at["p1"].size() == 2 and not at["p1"].any(func(e): return e[0] == "p1"), "members are told where their allies are")
	# Saved, and loaded on restart.
	var al2 := ServerAlliances.new(host, path)
	check(al2.allied("p1", "p3") and al2.list[id]["members"].size() == 3, "alliances survive a restart")
	check(al.command("p1", "Ann", "kick", "p3") == "" and not al.allied("p1", "p3") and host.views["p3"][0].is_empty(), "the leader can remove a member")
	al.command("p1", "Ann", "leave", "")
	check(al.list[id]["leader"] == "p2" and not al.allied("p1", "p2"), "leadership passes on when the leader leaves")
	host.opts["alliances"] = false
	check(not al.allied("p2", "p2") and al.command("p2", "Bob", "invite", "p1") != "", "with alliances off nobody is allied")
	host.opts["alliances"] = true
	al.command("p2", "Bob", "leave", "")
	check(not al.list.has(id), "an alliance ends with its last member")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.free()

func test_tool_models() -> void:
	# Every tool and weapon with a built model is a real shape (not the fallback box),
	# of a believable size, and is an item the game knows.
	for t in ToolModels.BUILD:
		check(not ItemDB.def(t).is_empty(), "%s: modelled item exists" % t)
		var m := ToolModels.build(t)
		check(m != null and m.get_surface_count() > 0, "%s: model builds" % t)
		if m == null:
			continue
		var n := 0
		for i in m.get_surface_count():
			n += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		check(n > 24, "%s: more than a box (%d verts)" % [t, n])
		var s := m.get_aabb().size
		check(maxf(s.x, maxf(s.y, s.z)) > 0.04 and maxf(s.x, maxf(s.y, s.z)) < 2.5, "%s: believable size %s" % [t, s])
	check(Viewmodel._strike_axis("tomahawk") == Vector3.FORWARD and Viewmodel._strike_axis("warpick") == Vector3.RIGHT, "new axes and picks swing edge first")

# --- Lived-in villages ------------------------------------------------------------

func _medieval_town(gen: ChunkGenerator) -> Dictionary:
	var best := {}
	for sz in range(-4, 5):
		for sx in range(-4, 5):
			var s := gen.settlement_at(sx, sz)
			if not s.is_empty() and int(s["era"]) == Eras.MEDIEVAL and int(s["size"]) >= 1:
				if best.is_empty() or (s["center"] as Vector2).length() < (best["center"] as Vector2).length():
					best = s
	return best

## A streamer of flat, empty chunks for TownLife, with objects placed by hand.
class FakeTownStreamer extends Node:
	class Chunk:
		var data := {}
	var chunks := {}
	func get_chunk(k: Vector2i):
		if not chunks.has(k):
			var c := Chunk.new()
			var hs := PackedFloat32Array()
			hs.resize(ChunkGenerator.RES * ChunkGenerator.RES)
			c.data = {"heights": hs, "objects": []}
			chunks[k] = c
		return chunks[k]

func test_town_life() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var gen := ChunkGenerator.new(4242)
	var s := _medieval_town(gen)
	check(not s.is_empty(), "a medieval town near spawn")
	if s.is_empty():
		return
	var pl := TownLife.plan(gen, s)
	check(pl["houses"].size() >= 5, "the town's houses are known (%d)" % pl["houses"].size())
	check(pl["paths"].size() >= pl["houses"].size(), "paths lead from the doors (%d)" % pl["paths"].size())
	check(pl["fields"].size() >= 3, "fields outside town (%d)" % pl["fields"].size())
	check(pl["smoke"].size() > 0 and pl["lamps"].size() > 0, "smoking chimneys and torches")
	# The town's chest isn't left out on the square: it stands by a house's front door.
	var lay := gen.settlement_layout(s)
	for it in lay:
		if Eras.CACHE_TYPES.has(it["t"]):
			var by_door := false
			for h in lay:
				if KitHouse.has(h["t"]):
					var l := TownLife.world_to_frame(h["p"], h["yaw"], it["p"])
					var hd := KitHouse.size_of(h["t"])
					by_door = by_door or (absf(l.x) < hd.x * 0.5 and l.y > hd.z * 0.5 and l.y < hd.z * 0.5 + 1.0)
			check(by_door, "the town's chest stands against a house front, not mid-square")
	# Each chimney's smoke reaches the builder with its household, which seeds its fire.
	var tl := TownLife.new()
	tl.setup(gen, null, s)
	var smokes := 0
	var keyed := 0
	for g in tl._pending:
		for e in g["pieces"]:
			if e["k"] == "smoke":
				smokes += 1
				if e.has("house") and int(e["house"]) == int(g["house"]):
					keyed += 1
	check(smokes > 0 and keyed == smokes, "every smoke piece knows its house (%d of %d)" % [keyed, smokes])
	tl.free()
	# An orchard tree (or a yard prop) where the player has built doesn't grow through it,
	# and comes back when the building is dismantled.
	var orch: Array = pl["orchards"]
	check(not orch.is_empty(), "the town has an orchard")
	if not orch.is_empty():
		var t0: Dictionary = orch[0]["trees"][0]
		var tp: Vector2 = t0["p"]
		var tree := {"k": "tree", "p": tp, "yaw": t0["yaw"], "sp": orch[0]["sp"], "v": t0["v"], "s": t0["s"]}
		var pile := {"k": "barrels", "p": tp + Vector2(5.0, 0.0), "seed": 1}
		var fs := FakeTownStreamer.new()
		var tl0 := TownLife.new()
		tl0.gen = gen
		tl0.site = s
		tl0.streamer = fs
		check(tl0._standing([tree, pile]).size() == 2, "with nothing built, the orchard tree and the prop stand")
		var k := TownLife._chunk_of(Vector3(tp.x, 0, tp.y))
		var lp := Vector3(tp.x - k.x * ChunkGenerator.SIZE + 1.5, 0, tp.y - k.y * ChunkGenerator.SIZE)
		var fo := {"t": BuildCatalog.PREFIX + "foundation", "p": lp, "r": 0.0, "s": 1.0, "st": {}}
		fs.get_chunk(k).data["objects"].append(fo)
		var left := tl0._standing([tree, pile])
		check(left.size() == 1 and left[0]["k"] == "barrels", "a foundation built 1.5 m from an orchard tree keeps it from being built")
		# Built a little beyond the trunk, but under the crown: the leaves would reach in.
		var reach := TownLife.crown_reach(tree)
		check(reach > 1.0 and reach < TownLife.REACH_MAX, "an orchard tree's crown reaches out (%.1f m)" % reach)
		fo["p"] = lp + Vector3(reach + 0.5, 0, 0)
		check(tl0._standing([tree]).is_empty(), "a wall built under an orchard tree's crown keeps it from being built")
		fo["p"] = lp + Vector3(reach + TownLife.PIECE_HALF + TownLife.TREE_CLEAR + 0.3, 0, 0)
		check(tl0._standing([tree]).size() == 1, "one built clear of the crown leaves the tree standing")
		fo["p"] = lp
		var rev := TownLife._rev
		TownLife.note_built(tp)
		check(TownLife._rev == rev + 1 and tl0._seen != TownLife._rev, "a build is noted for the towns to stand aside")
		fo["st"]["gone"] = true
		check(tl0._standing([tree, pile]).size() == 2, "once it's dismantled the tree stands again")
		tl0.free()
		fs.free()
	var kinds := {}
	for e in pl["pieces"]:
		kinds[e["k"]] = true
	for k in ["woodpile", "garden", "fence"]:
		check(kinds.has(k), "a town has a %s" % k)
	# Nothing in a yard stands inside another house.
	var inside := 0
	for e in pl["pieces"]:
		if not e.has("p"):
			continue
		for h in pl["houses"]:
			if int(h["i"]) == int(e["house"]):
				continue
			var q := TownLife.world_to_frame(h["p"], h["yaw"], e["p"])
			if absf(q.x) < float(h["w"]) * 0.5 and absf(q.y) < float(h["d"]) * 0.5:
				inside += 1
	check(inside == 0, "yard pieces stay out of other houses (%d inside)" % inside)
	# The same every time (it is never saved).
	TownLife._plans.clear()
	var again := TownLife.plan(gen, s)
	check(str(again["pieces"]) == str(pl["pieces"]) and str(again["fields"]) == str(pl["fields"]), "the plan follows from the seed")
	# A field's chunk has worn ground and crops in rows among the grass.
	var f: Dictionary = pl["fields"].filter(func(x): return x["crop"] != "fallow")[0]
	var k := TownLife._chunk_of(Vector3(f["p"].x, 0, f["p"].y))
	var chunk := gen.generate(k.x, k.y)
	TownLife.annotate(gen, chunk)
	check(chunk.has("worn") and chunk.has("crops"), "the field's chunk is worn and planted")
	var lp: Vector2 = (f["p"] as Vector2) - Vector2(k.x, k.y) * ChunkGenerator.SIZE
	check(TownLife.wear_at(chunk, lp.x, lp.y) > 0.3, "the field's ground is worn (%f)" % TownLife.wear_at(chunk, lp.x, lp.y))
	var g := {}
	TownLife.crops(chunk, g, 1.0, ChunkGenerator.keep_out(chunk))
	var crops := 0
	for key in g:
		crops += (g[key] as PackedFloat32Array).size() / 16
	check(crops > 200, "crops grow in the field (%d)" % crops)
	# No wild tree is left standing in the field.
	var standing := 0
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) == "tree" and not o["st"].get("gone", false):
			var q := TownLife.world_to_frame(f["p"], f["yaw"], Vector2(o["p"].x, o["p"].z) + Vector2(k.x, k.y) * ChunkGenerator.SIZE)
			if absf(q.x) < float(f["hx"]) and absf(q.y) < float(f["hz"]):
				standing += 1
	check(standing == 0, "the field is cleared of trees (%d standing)" % standing)
	# The market square: paved, a well or cross near the middle, stalls round it.
	check(not (pl["square"] as Dictionary).is_empty(), "the town has a market square")
	var sq_kinds := {}
	for e in pl["pieces"]:
		sq_kinds[e["k"]] = int(sq_kinds.get(e["k"], 0)) + 1
	check(sq_kinds.has("well") or sq_kinds.has("cross"), "a well or market cross on the square")
	check(int(sq_kinds.get("stall", 0)) >= 2, "stalls round the square (%d)" % int(sq_kinds.get("stall", 0)))
	# Castle wall and tower builds: a type alone has a footprint, placed ones a build of
	# their own, and every build shares the plain wall's ground plan.
	var fw := ObjectLibrary.footprint({"t": "castle_wall"})
	check(fw.size.x > 7.0 and fw.size.y > 1.5, "a castle wall has a footprint by type alone (%s)" % fw)
	check(ObjectLibrary.mesh_key({"t": "castle_tower", "p": Vector3(3, 0, 5), "st": {}}).begins_with("castle_tower" + Stronghold.VAR), "a placed tower picks a build")
	# Far from any town, nothing changes.
	var wild := gen.generate(400, 400)
	TownLife.annotate(gen, wild)
	check(not wild.has("worn") and not wild.has("crops"), "the wilds stay as they were")

# --- Boats ---------------------------------------------------------------------------------

func test_boats_on_the_water() -> void:
	var old_theme := Eras.theme
	var old_eras := WorldField.allowed_eras
	var old_v := WorldField.terrain_v
	Eras.theme = "human"
	WorldField.allowed_eras = [Eras.MEDIEVAL, Eras.SCIFI]
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var gen := ChunkGenerator.new(424242)
	var found: Array = []
	for cz in range(-6, 6):
		for cx in range(-6, 6):
			var s := Boats.plan(gen.field, cx, cz)
			if not s.is_empty():
				found.append(s)
	check(found.size() >= 3 and found.size() <= 60, "boats are out on some lakes, not all (%d in 144 cells)" % found.size())
	for s in found:
		var c: Vector2 = s["center"]
		check(gen.field.height(c.x, c.y) < Boats.WET, "%s lies on water" % s["boat"])
		check(Boats.cell_of(c.x, c.y) == Vector2i(int(s["cx"]), int(s["cz"])), "a boat belongs to the cell its lake's middle is in")
		check(s == Boats.plan(gen.field, int(s["cx"]), int(s["cz"])), "planning is repeatable")
		var d: Dictionary = Boats.KINDS[s["boat"]]
		check(float(s["clear"]) >= float(d["len"]) * 0.5 + 10.0, "%s fits its lake (clear %d m)" % [s["boat"], s["clear"]])
		# Its loop stays on deep water.
		for i in 48:
			var p: Vector2 = Boats.pose_at(s, float(i) * 37.0)[0]
			check(gen.field.height(p.x, p.y) < 0.0, "%s sails on water at %s" % [s["boat"], p])
		# Under way she keeps to her pace (no jumps), and she stops at anchor now and then.
		var v := float(d["moves"])
		if v > 0.0 and float(s["loop"]) > 0.0:
			var still := 0
			var prev: Vector2 = Boats.pose_at(s, 0.0)[0]
			for i in range(1, 1200):
				var q: Vector2 = Boats.pose_at(s, float(i))[0]
				check(q.distance_to(prev) < v * 1.6 + 0.01, "%s never jumps along her loop (%.2f m in 1 s)" % [s["boat"], q.distance_to(prev)])
				if q.distance_to(prev) < 0.001:
					still += 1
				prev = q
			check((still > 30) == (float(d.get("rest", 0.0)) > 0.0), "%s lies at anchor between passages (%d s still)" % [s["boat"], still])
		var era := int(d["era"])
		var tech := WorldField.dominant(gen.field.era_weights(c.x, c.y)) == Eras.SCIFI
		check((era == Eras.SCIFI) == tech, "%s matches the land's era" % s["boat"])
		var crew := Boats.crew(424242, s)
		var cr: Array = d["crew"]
		check(crew["npcs"].size() >= int(cr[0]) and crew["npcs"].size() <= BoatModel.stations(s["boat"]).size(), "%s has a crew" % s["boat"])
		check(crew == NPCGen.create(gen, s), "crews are made through the settlement store path")
		for p in crew["npcs"]:
			check(p["boat"] == s["boat"] and p.has("station") and p["faction"] == "folk", "crew records know their boat and station")
			check(String(p["id"]).begins_with("%d_%d_" % [s["sx"], s["sz"]]), "crew ids are unique to the boat")
	var alien := ChunkGenerator.new(424242)
	Eras.theme = "alien"
	var any := false
	for cx in range(-3, 3):
		any = any or not Boats.plan(alien.field, cx, 0).is_empty()
	check(not any, "no human boats on alien worlds")
	Eras.theme = old_theme
	WorldField.allowed_eras = old_eras
	WorldField.terrain_v = old_v

func test_boat_wake_waves() -> void:
	# A cog at 2.6 m/s heading -z with her bow at the origin: her wake stands up behind her
	# (both up and down), stays out of her hull and out of the water ahead of her.
	var bm := BoatManager.new()
	bm._wakes = [[Vector4(0, 0, 0, -1), Vector4(2.6, 20.0, 3.2, 1.0)]]
	var hi := -1.0
	var lo := 1.0
	for z in range(0, 80):
		for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			var h := bm.wake_at(x, float(z))
			hi = maxf(hi, h)
			lo = minf(lo, h)
	check(hi > 0.08 and lo < -0.05, "a boat under way raises crests and troughs behind her (%.2f .. %.2f m)" % [hi, lo])
	check(absf(bm.wake_at(0.0, 10.0)) < 0.02, "no wake inside her hull")
	check(absf(bm.wake_at(0.0, -40.0)) < 0.001, "no wake ahead of her")
	check(hi <= Water.WAKE_MAX and lo >= -Water.WAKE_MAX, "wakes stay within WAKE_MAX")
	bm._wakes = []
	check(bm.wake_at(0.0, 20.0) == 0.0, "no boats, no wake")
	bm.free()

func test_boat_models() -> void:
	for k in Boats.KINDS:
		var body := StaticBody3D.new()
		var m := BoatModel.build(k, 3, body)
		var mi: MeshInstance3D = m.find_children("*", "MeshInstance3D", false, false)[0]
		check(mi.mesh != null and mi.mesh.get_surface_count() > 0, "%s has a model" % k)
		check(body.get_child_count() > 0, "%s has collision" % k)
		check(not BoatModel.stations(k).is_empty() and BoatModel.stations(k).size() >= int(Boats.KINDS[k]["crew"][1]), "%s has a station per crew member" % k)
		m.free()
		body.free()
	# Pirates: a spawned site makes a hostile crew.
	var site := {"boat": "cog", "sx": Boats.SPAWNED_BASE + 1, "sz": Boats.SPAWNED_BASE, "center": Vector2(10, 20), "faction": "pirate",
		"name": "Black Gull", "phase": 0.0, "yaw": 0.0, "loop": 0.0}
	var crew := Boats.crew(1, site)
	check(not crew["npcs"].is_empty() and crew["npcs"].all(func(p): return p["job"] == "pirate" and p["faction"] == "pirate" and int(p["rel"]) < 0), "pirate crews are hostile")

## Every held ranged weapon (bar thrown ones) has a real model with a grip, and nothing
## people made glows: only alien (Fantasy era) weapons have emissive parts.
func test_firearm_models() -> void:
	for t in ItemDB.ITEMS:
		var d: Dictionary = ItemDB.def(t)
		if not d.get("ranged", false) or d.get("thrown", false):
			continue
		check(GunLook.has(t), "%s has a ranged-weapon model" % t)
		var m: ArrayMesh = Viewmodel.model(t)
		if m == null:
			check(false, "%s has a mesh" % t)
			continue
		var verts := 0
		for i in m.get_surface_count():
			verts += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		check(verts > 300, "%s is built from parts, not a box" % t)
		check(m.has_meta("grip"), "%s says where the hand grips it" % t)
		if Firearms.has(t):
			check(float(m.get_meta("grip_r", 0.0)) > 0.005, "%s says how thick its grip is" % t)
		if Firearms.has(t) and d.get("era", -1) != Eras.FANTASY and not d.get("alien", false):
			var lit := false
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i) as BaseMaterial3D
				lit = lit or (mat != null and mat.emission_enabled)
			check(not lit, "%s (human work) has no glowing part" % t)

# --- v16: zone lines, craters, the Fallen Dreadnought's crash ---------------------------

func _human_world() -> Array:
	var was := [Eras.theme, Eras.base_level, WorldField.allowed_eras, WorldField.terrain_v]
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	Planets.apply(Planets.get_planet(4242, 0, "human"))
	return was

func _restore_world(was: Array) -> void:
	Eras.theme = was[0]
	Eras.base_level = was[1]
	WorldField.allowed_eras = was[2]
	WorldField.terrain_v = was[3]

func test_zone_borders() -> void:
	var was := _human_world()
	var rs := ZoneBorder.rings()
	check(rs.size() == 3 and is_equal_approx(rs[0], 1350.0) and is_equal_approx(rs[1], 2850.0), "a human world marks its zone lines at levels 10, 20 and 40: %s" % rs)
	check(ZoneBorder.road_rings() == Vector2(1350.0, 2850.0), "and the road surface changes at the first two")
	check(ZoneInfo.band_range(12) == Vector2i(10, 19) and ZoneInfo.band_range(3) == Vector2i(1, 9) and ZoneInfo.band_range(44) == Vector2i(40, 55), "zone bands: %s %s %s" % [ZoneInfo.band_range(12), ZoneInfo.band_range(3), ZoneInfo.band_range(44)])
	check(ZoneInfo.entering({"kind": "Borderlands", "band_lo": 10, "band_hi": 19}) == "Entering the Borderlands  ·  Lv 10-19", "the toast names the zone and its levels")
	var g := ChunkGenerator.new(4242, true)
	# Boundary stones all round the first line, in every chunk it crosses that has room.
	var stones := 0
	var chunks := 0
	var seen := {}
	for i in 60:
		var a := i * TAU / 60.0
		var p := Vector2(cos(a), sin(a)) * rs[0]
		var k := Vector2i(floori(p.x / 64.0), floori(p.y / 64.0))
		if seen.has(k):
			continue
		seen[k] = true
		chunks += 1
		for o in g.generate(k.x, k.y)["objects"]:
			if o["t"] == "border_stone":
				stones += 1
				var w := Vector2(k.x * 64.0 + o["p"].x, k.y * 64.0 + o["p"].z)
				check(absf(w.length() - rs[0]) < 1.5, "a boundary stone stands on the line (%.1f m off)" % (w.length() - rs[0]))
	check(stones > chunks / 2, "boundary stones along the line: %d in %d chunks" % [stones, chunks])
	# Where a road crosses the second line: a barrier on the road, a sign and a booth by it.
	var cps := ZoneBorder.checkpoints(g, rs[1], 1, Rect2(-3000, -3000, 6000, 6000))
	var bars := cps.filter(func(c): return c["t"] == "border_barrier")
	check(not bars.is_empty() and cps.size() == bars.size() * 3, "checkpoints where roads cross the line: %d" % bars.size())
	if not bars.is_empty():
		var x: Vector2 = bars[0]["p"]
		var k := Vector2i(floori(x.x / 64.0), floori(x.y / 64.0))
		var ch := g.generate(k.x, k.y)
		var has := false
		for o in ch["objects"]:
			has = has or o["t"] == "border_barrier"
		check(has, "the barrier is placed in its chunk")
		check(ChunkGenerator.road_at(ch, x.x - k.x * 64.0, x.y - k.y * 64.0) > 0.5, "on the road")
	for t in ZoneBorder.LABELS:
		var m := ZoneBorder.build(t)
		var lit := 0
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				lit += 1
		check(m.get_surface_count() > 0 and lit == 0, "%s has a mesh and nothing on it glows" % t)
		check(ObjectLibrary.kind(t) == "structure" and ObjectLibrary.label(t) == ZoneBorder.LABELS[t], "%s is a labelled structure" % t)
	_restore_world(was)
	check(ZoneBorder.rings().is_empty() or Eras.theme == "human", "only human worlds have zone lines")

func test_crater_rims() -> void:
	var was := _human_world()
	var f := WorldField.new(4242)
	var tested := 0
	for j in range(-40, 41):
		for i in range(-40, 41):
			if tested >= 6:
				break
			var p := Vector2(i, j) * 37.0 + Vector2(5000, -3000)
			var c := f._crater_at(p.x, p.y)
			if c.is_empty() or float(c[0]) < 30.0 or absf(float(c[5]) - 1.0) > 0.03 or float(c[3]) < 1.0 or float(c[4]) < 0.9:
				continue
			# Out from the middle of the crater, from the crest.
			var d0 := f._cell(p.x, p.y, WorldField.CRATER_CELL, WorldField.CRATER_SALT).x
			var out := Vector2(f._cell(p.x + 0.5, p.y, WorldField.CRATER_CELL, WorldField.CRATER_SALT).x - d0, f._cell(p.x, p.y + 0.5, WorldField.CRATER_CELL, WorldField.CRATER_SALT).x - d0).normalized()
			var r: float = c[0]
			var crest := f._craters_v16(p.x, p.y)
			var inside := f._craters_v16(p.x - out.x * r * 0.5, p.y - out.y * r * 0.5)
			var blanket := f._craters_v16(p.x + out.x * r * 0.4, p.y + out.y * r * 0.4)
			check(crest.y > 0.07 * r, "a crater's crest stands up (%.1f m on a %.0f m crater)" % [crest.y, r])
			check(inside.x + inside.y < crest.y - 0.15 * r, "its bowl is well below the crest")
			check(blanket.y > 0.05 and blanket.y < crest.y, "ejecta lies outside the rim, lower than it (%.2f m)" % blanket.y)
			check(f.crater_spoil(p.x, p.y) > 0.6, "fresh spoil shows on the crest")
			tested += 1
	check(tested > 0, "found big craters to check")
	# Old craters on a human world are grassed over: stony only along the inner lip.
	var g := ChunkGenerator.new(4242, true)
	var bare := 0
	var grassy := 0
	var lip_scree := 0.0
	var lips := 0
	for kz in range(25, 28):
		for kx in range(25, 28):
			var ch := g.generate(kx, kz)
			if not ch.has("grassed"):
				continue
			var cov := GroundCover.build(ch)
			for vj in ChunkGenerator.RES:
				for vi in ChunkGenerator.RES:
					var gw := GroundCover._look_cell(ch["grassed"], vi, vj, 1, 0)
					var sp := GroundCover._look_cell(ch["look"], vi, vj, ChunkGenerator.LOOK_BYTES, 11)
					var sc := cov[(vj * ChunkGenerator.RES + vi) * 4] / 255.0
					if gw > 0.95 and sp < 0.01:
						grassy += 1
						bare += int(sc > 0.1)
					elif gw > 0.95 and sp > 0.4:
						lips += 1
						lip_scree += sc
	check(grassy > 500 and bare < grassy * 0.01, "an old crater field is grassed, not scree (%d of %d bare)" % [bare, grassy])
	WorldField.terrain_v = 15
	check(f.crater_spoil(5000, -3000) == 0.0, "older worlds keep their craters")
	_restore_world(was)

func test_dreadnought_crash() -> void:
	BuildCatalog.warm_kits()
	var was := _human_world()
	var g := ChunkGenerator.new(4242, true)
	var cr := {}
	var k := Vector2i.ZERO
	for r in 6:
		for wz in range(-r, r + 1):
			for wx in range(-r, r + 1):
				if not cr.is_empty() or maxi(absi(wx), absi(wz)) != r:
					continue
				var pick := WonderSite.cell_pick(g.seed, wx, wz)
				if not pick.is_empty():
					cr = WonderSite.crash_of(g, pick[0])
					k = pick[0]
	check(not cr.is_empty(), "a crashed dreadnought near the origin")
	if cr.is_empty():
		_restore_world(was)
		return
	check(float(cr["len"]) >= WonderSite.CRASH_MIN, "its trench runs %.0f m" % cr["len"])
	var ch := g.generate(k.x, k.y)
	var hull := {}
	for o in ch["objects"]:
		if o["t"] == "w_dreadnought":
			hull = o
	check(not hull.is_empty() and hull["st"].get("crash", false), "the hull lies at the end of it")
	check(ObjectLibrary.mesh_key(hull) == "w_dreadnought" + WonderSite.CRASH + WonderSite.CALM, "a human world's crashed hull wears the calm mesh")
	var m := ObjectLibrary.get_mesh(ObjectLibrary.mesh_key(hull))
	var lit := 0
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i) as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			lit += 1
	check(lit == 0 and m.get_aabb().size.z > 55.0, "it is capital-ship size (%.0f m) and nothing on it glows" % m.get_aabb().size.z)
	# The trench: cut well into the land along its length, in the chunks it crosses.
	var c := Vector2(cr["x"], cr["z"])
	var deep := 0
	var n := 0
	for v in [-30.0, -60.0, -90.0]:
		if v < -float(cr["len"]) + 20.0:
			continue
		var mid := c + Vector2(0, v).rotated(-float(cr["yaw"]))
		var hm := _ground(g, mid)
		var raw := g.field.height(mid.x, mid.y)
		n += 1
		if hm < raw - 1.5:
			deep += 1
	check(n > 0 and deep == n, "the trench is cut into the ground (%d of %d)" % [deep, n])
	# Seams: neighbours meet the wonder's chunk, and the wreckage lies out round it.
	var bad := 0
	var bits := 0
	var burnt := 0
	var felled := 0
	var standing := 0
	var snags := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb := g.generate(k.x + d.x, k.y + d.y)
		for o in nb["objects"]:
			if o["t"] == WonderSite.DEBRIS:
				bits += 1
			elif o["t"] == WonderSite.TRUNK:
				felled += 1
			elif ObjectLibrary.kind(o["t"]) == "tree":
				snags += int(o["st"].get("burnt", false) and String(Flora.species(o["t"], int(o["sp"]))["form"]) in ["dead", "snag"])
				var wp: Vector3 = o["p"] + Vector3((k.x + d.x) * 64.0, 0, (k.y + d.y) * 64.0)
				standing += int(WonderSite.blast(cr, wp.x, wp.z) > 0.95)
		var lb: PackedByteArray = nb.get("look", PackedByteArray())
		for i in range(10, lb.size(), ChunkGenerator.LOOK_BYTES):
			burnt += int(lb[i] > 40)
		for t in ChunkGenerator.RES:
			var a: float
			var b: float
			match d:
				Vector2i(1, 0):
					a = ch["heights"][t * ChunkGenerator.RES + ChunkGenerator.SIZE]
					b = nb["heights"][t * ChunkGenerator.RES]
				Vector2i(-1, 0):
					a = ch["heights"][t * ChunkGenerator.RES]
					b = nb["heights"][t * ChunkGenerator.RES + ChunkGenerator.SIZE]
				Vector2i(0, 1):
					a = ch["heights"][ChunkGenerator.SIZE * ChunkGenerator.RES + t]
					b = nb["heights"][t]
				_:
					a = ch["heights"][t]
					b = nb["heights"][ChunkGenerator.SIZE * ChunkGenerator.RES + t]
			if absf(a - b) > 0.01:
				bad += 1
	check(bad == 0, "the trench's chunks meet the wonder's (%d bad edge points)" % bad)
	check(bits > 0 and burnt > 0, "wreckage (%d) and scorched ground (%d) reach the chunks round it" % [bits, burnt])
	for o in ch["objects"]:
		if o["t"] == WonderSite.TRUNK:
			felled += 1
	check(snags > 0, "further out the trees stand burnt bare (%d)" % snags)
	check(standing == 0, "no tree stands where the blast hit hardest (%d do)" % standing)
	check(felled > 0 and ObjectLibrary.kind(WonderSite.TRUNK) == "structure" and WonderSite.trunk(5, 1).get_surface_count() > 0, "the trees it reached lie snapped and scorched (%d)" % felled)
	for sp in range(1, 7):
		check(WonderSite.debris(sp, 1).get_surface_count() > 0, "wreckage kind %d has a mesh" % sp)
	_restore_world(was)

func _ground(g: ChunkGenerator, p: Vector2) -> float:
	var k := Vector2i(floori(p.x / 64.0), floori(p.y / 64.0))
	return ChunkGenerator.height_at(g.generate(k.x, k.y), p.x - k.x * 64.0, p.y - k.y * 64.0)

# --- Boats ---------------------------------------------------------------------------------

# --- Food, drink and containers ------------------------------------------------------

func test_provisions_models() -> void:
	var n := 0
	for t in ItemDB.ITEMS:
		var m := Provisions.model(t)
		if m == null:
			continue
		n += 1
		check(m.get_surface_count() > 0, "%s has surfaces" % t)
		check(m.has_meta("grip"), "%s says where it is held" % t)
		if m.has_meta("grip"):
			check(m.get_aabb().grow(0.03).has_point(m.get_meta("grip")), "%s is held on itself" % t)
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			check(not (mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_color == Color(1, 0, 1)), "%s surface %s has a real material" % [t, m.surface_get_name(i)])
	check(n >= 120, "food and drink models: %d" % n)
	check(Provisions.model("sword_iron") == null, "a sword is not food")
	var k := MeshKit.new()
	Provisions.msg_bottle(k, RandomNumberGenerator.new())
	check(k.commit(Provisions._mat).get_surface_count() >= 6, "the message in a bottle builds")
	# Kit props that are containers come from Provisions at about the kit model's size.
	for e in [["props/Barrel", 0.88], ["props/Chest_Wood", 0.7], ["props/Crate_Wooden", 0.86], ["props/Mug", 0.17], ["props/Bottle_1", 0.36], ["props/Barrel_Apples", 0.88], ["props/FarmCrate_Apple", 0.24], ["props/Bag", 0.78]]:
		check(not Provisions.kit(e[0]).is_empty(), "%s has a stand-in" % e[0])
		var km := BuildCatalog.merge_models([[e[0], 0, Vector3.ZERO, 1.0]])
		check(absf(km.get_aabb().size.y - float(e[1])) < float(e[1]) * 0.2, "%s stands %.2f m tall" % [e[0], km.get_aabb().size.y])
## No two of a herd alike: kit animals each get their own size (from the id, so it is
## the same for everyone), and manes and tails grow hanging locks bound to the skeleton.
func test_animal_individuals() -> void:
	var sp := -1
	for i in 400:
		var p := Creature.species(i, Eras.MEDIEVAL)
		if AnimalModel.available(p.get("kit", "")) and p["plan"] == "quad":
			sp = i
			break
	check(sp >= 0, "a medieval kit species exists")
	var scales := {}
	for i in 12:
		var c := Creature.new()
		c.id = "herd_%d" % i
		c.sp = sp
		c.p = Creature.species(sp, Eras.MEDIEVAL)
		c._individual()
		scales[snappedf(float(c.p["kit_scale"]), 0.001)] = true
		var again := Creature.new()
		again.id = c.id
		again.sp = sp
		again.p = Creature.species(sp, Eras.MEDIEVAL)
		again._individual()
		check(is_equal_approx(float(again.p["kit_scale"]), float(c.p["kit_scale"])), "%s is the same size every time" % c.id)
		c.free()
		again.free()
	check(scales.size() >= 8, "a herd of 12 comes in many sizes (%d)" % scales.size())
	var m := AnimalModel.new().build("Horse", 1.0, null, null, 7)
	var locks := 0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_name(s) == AnimalSkin.LOCKS:
				locks += 1
				var a := mesh.surface_get_arrays(s)
				check(a[Mesh.ARRAY_BONES] != null and (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 600, "horse locks are skinned and plentiful")
				check((mi as MeshInstance3D).get_surface_override_material(s).shader.resource_path == AnimalSkin.LOCK_SHADER, "horse locks use the lock shader")
	check(locks >= 1, "a horse's mane and tail grow locks (%d)" % locks)
	m.free()
func test_camera_feel() -> void:
	# Head bob: still at rest, moves when walking, dips on landing, and is gone when off.
	var hb := HeadBob.new()
	for i in 30:
		hb.step(1.0 / 60.0, 1.0, 0.0, 0.0, true, false, 0.0, 0.0, 0.0)
	check(hb.offset.length() < 0.001 and hb.tilt.length() < 0.001, "head bob rests when standing")
	var lo := 0.0
	var hi := -1.0
	for i in 120:
		hb.step(1.0 / 60.0, 1.0, fmod(i / 60.0, 1.0), 1.0, true, false, 0.0, 0.0, 0.0)
		lo = minf(lo, hb.offset.y)
		hi = maxf(hi, hb.offset.y)
	check(hi - lo > 0.01 and hi - lo < 0.05, "walking bobs the eye a little (%.3f m)" % (hi - lo))
	hb.reset()
	var dip := 0.0
	hb.step(1.0 / 60.0, 1.0, 0.0, 0.0, true, false, 0.0, 8.0, 0.0)
	for i in 60:
		hb.step(1.0 / 60.0, 1.0, 0.0, 0.0, true, false, 0.0, 0.0, 0.0)
		dip = minf(dip, hb.offset.y)
	check(dip < -0.02 and dip > -0.15 and absf(hb.offset.y) < 0.01, "a landing dips the eye and springs back (%.3f m)" % dip)
	hb.reset()
	for i in 60:
		hb.step(1.0 / 60.0, 0.0, fmod(i / 60.0, 1.0), 1.8, true, false, 1.0, 6.0, 0.0)
	check(hb.offset.length() < 0.0001 and hb.tilt.length() < 0.0001, "head bob off keeps the eye still")
	# Motion blur: skips still frames and cuts, and scales with the shutter.
	var old := CameraBlur.strength
	CameraBlur.strength = 0.3
	var a := Transform3D.IDENTITY
	check(CameraBlur.shutter_scale(a, a, 1.0 / 60.0) == 0.0, "no blur while the camera holds still")
	check(CameraBlur.shutter_scale(a, a.rotated(Vector3.UP, 1.2), 1.0 / 60.0) == 0.0, "no blur across a camera cut")
	check(is_equal_approx(CameraBlur.shutter_scale(a, a.rotated(Vector3.UP, 0.05), 1.0 / 60.0), 0.3), "the shutter is strength / 60 s")
	check(is_equal_approx(CameraBlur.shutter_scale(a, a.rotated(Vector3.UP, 0.05), 1.0 / 120.0), 0.6), "the same shutter at a higher frame rate")
	CameraBlur.strength = 0.0
	check(CameraBlur.shutter_scale(a, a.rotated(Vector3.UP, 0.05), 1.0 / 60.0) == 0.0, "motion blur off")
	CameraBlur.strength = old

# --- Weather -----------------------------------------------------------------------

func test_climate() -> void:
	var a := Climate.new(4242)
	var b := Climate.new(4242)
	check(a.at(37.5, 120.0, -80.0, 12.0, WorldField.LF_NONE, 50.0) == b.at(37.5, 120.0, -80.0, 12.0, WorldField.LF_NONE, 50.0),
		"the same world, place and hour have the same weather (every player on a server agrees)")
	var keys := ["cover", "precip", "snow", "storm", "mist", "dust", "wind"]
	var wet := {WorldField.LF_NONE: 0, WorldField.LF_DUNES: 0}
	var snowed_low := 0
	var snowed_high := 0
	var dust_green := 0
	var changes := 0
	var last := -1
	for i in 2000:
		var h := i * 0.5
		for lf in wet:
			var c := a.at(h, 300.0, -200.0, 8.0, lf, 50.0)
			for k in keys:
				check(float(c[k]) >= 0.0 and float(c[k]) <= 1.0, "%s stays within 0..1" % k)
			if float(c["precip"]) > 0.5:
				wet[lf] += 1
			if lf == WorldField.LF_NONE:
				if float(c["dust"]) > 0.05:
					dust_green += 1
				var raining := 1 if float(c["precip"]) > 0.3 else 0
				if raining != last:
					changes += 1
				last = raining
				if float(c["precip"]) > 0.3 and float(c["snow"]) > 0.5:
					snowed_low += 1
		var hi := a.at(h, 300.0, -200.0, 85.0, WorldField.LF_NONE, 50.0)
		if float(hi["precip"]) > 0.3 and float(hi["snow"]) > 0.5:
			snowed_high += 1
	check(wet[WorldField.LF_NONE] > 40 and wet[WorldField.LF_NONE] < 800, "it rains some of the time, not all of it (%d / 2000)" % wet[WorldField.LF_NONE])
	check(wet[WorldField.LF_DUNES] * 4 < wet[WorldField.LF_NONE], "deserts are much drier (%d vs %d)" % [wet[WorldField.LF_DUNES], wet[WorldField.LF_NONE]])
	check(snowed_high > snowed_low * 3 and snowed_high > 0, "it snows on the peaks far more than in the lowlands (%d vs %d)" % [snowed_high, snowed_low])
	check(dust_green == 0, "no dust storms on green land")
	check(changes >= 4 and changes < 400, "rain comes and goes in spells (%d changes)" % changes)
	# Fronts travel: the weather here now is the weather upwind a little earlier.
	var up := a.prevailing * -Climate.FRONT_SPEED
	var now := a.at(50.0, 0.0, 0.0, 8.0, WorldField.LF_NONE, 50.0)
	var then := a.at(49.0, up.x, up.y, 8.0, WorldField.LF_NONE, 50.0)
	check(absf(float(now["cover"]) - float(then["cover"])) < 0.25, "a front passing upwind an hour ago is over you now")
	check(Climate.base_temp(6.0) < 0.0 and Climate.base_temp(50.0) > 10.0, "frozen worlds are cold")

func test_starfall() -> void:
	var nights := 0
	for n in 2000:
		if Climate.starfall_is_night(4242, float(n)):
			nights += 1
	check(nights > 120 and nights < 300, "about one night in ten is a starfall night (%d of 2000)" % nights)
	var n0 := -1
	for n in 200:
		if Climate.starfall_is_night(4242, float(n)):
			n0 = n
			break
	check(n0 >= 0, "a starfall night comes within 200 days")
	check(Climate.starfall(4242, n0) > 0.99, "a starfall night is at its height at midnight")
	check(Climate.starfall(4242, n0 + 0.5) == 0.0, "no falling stars at noon")
	check(Climate.starfall(4242, n0 + 0.5) == Climate.starfall(4242, n0 + 0.5) and Climate.starfall_radiant(4242, n0) == Climate.starfall_radiant(4242, n0),
		"the same night falls the same way for everyone")
	check(Climate.starfall_radiant(4242, n0).y > 0.4, "the stars fall from high in the sky")
	check(Landmark.has("star_iron") and Wonders.LANDMARKS.has("star_iron") and ObjectLibrary.kind("star_iron") == "structure",
		"a fallen fragment is a landmark you can pry at")

func test_great_storms() -> void:
	var c := Climate.new(4242)
	var seen := {}
	var strong := 0
	var hail := 0
	var banks := 0
	# Walk one spot through 80 days, a sample every game hour.
	for i in 80 * 24:
		var w := c.at(float(i), 500.0, -300.0, 12.0, WorldField.LF_NONE, 50.0)
		if w["great"] != "":
			seen[w["great"]] = true
			strong += 1
			check(float(w["wind"]) > 0.45 and float(w["cover"]) > 0.4, "a great storm blows hard under thick cloud")
		if float(w["hail"]) > 0.3:
			hail += 1
		if float(w["bank"]) > 0.3:
			banks += 1
	check(not seen.is_empty(), "great storms come by within 80 days (%d hours of one)" % strong)
	check(strong < 80 * 24 / 6, "great storms are rare (%d hours of 1920)" % strong)
	check(hail > 0, "great storms bring hail")
	check(banks > 0, "fog banks roll in on some mornings")
	var g := c.great(1000.0, 500.0, -300.0)
	check(g == c.great(1000.0, 500.0, -300.0), "the same great storm for everyone")

# --- Power ------------------------------------------------------------------------

func _pw(id: String, i: int, st := {}) -> Dictionary:
	var s := {"owner": "solo"}
	Power.init_state(id, s)
	s.merge(st, true)
	return {"i": i, "t": BuildCatalog.PREFIX + id, "p": Vector3.ZERO, "r": 0.0, "s": 1.0, "e": -1, "st": s}

func test_power_networks_and_switches() -> void:
	var gen := _pw("windmill", 0)
	var sw := _pw("knife_switch", 1)
	var lamp := _pw("lamp_ceiling", 2)
	var far_lamp := _pw("lamp_wall", 3)
	check(Power.link(gen, "0,0,0", sw, "0,0,1"), "cable windmill to switch")
	check(Power.link(sw, "0,0,1", lamp, "0,0,2"), "cable switch to lamp")
	check(not Power.link(sw, "0,0,1", lamp, "0,0,2"), "no second cable between the same two")
	check(lamp["st"]["pw"].has("0,0,1") and gen["st"]["pw"].has("0,0,1"), "both ends know the cable")
	var pieces := {"0,0,0": gen, "0,0,1": sw, "0,0,2": lamp, "0,0,3": far_lamp}
	var nets := Power.networks(pieces)
	check(nets.size() == 2, "closed switch joins windmill and lamp, the lone lamp is its own (%d)" % nets.size())
	sw["st"]["on"] = false
	nets = Power.networks(pieces)
	check(nets.size() == 4, "an open switch cuts the line (%d networks)" % nets.size())
	check(Power.wire_for(4.0) == 1 and Power.wire_for(11.0) == 3, "a Copper Wire per 5 m of cable")
	var pole := _pw("power_pole", 4)
	for n in 8:
		Power.link(pole, "0,0,4", _pw("lamp_wall", 10 + n), "0,0,%d" % (10 + n))
	check(not Power.link(pole, "0,0,4", _pw("lamp_wall", 30), "0,0,30"), "a pole takes 8 cables, no more")
	check(Power.parse_id("-3,7,12") == [Vector2i(-3, 7), 12], "piece ids parse back")

func test_power_sharing() -> void:
	var gen := _pw("windmill", 0)
	var bank := _pw("battery_bank", 1)
	var lamp := _pw("lamp_ceiling", 2)
	var es := [{"id": "a", "o": gen, "f": 1.0}, {"id": "b", "o": bank}, {"id": "c", "o": lamp}]
	# A fresh breeze: the windmill lights the lamp and charges the bank with the rest.
	var r := Power.solve(es, {"wind": 0.8, "sun": Vector3.DOWN, "cloud": 0.0}, 60.0)
	check(r["pieces"]["c"]["powered"], "lamp lit by the wind")
	check(is_equal_approx(float(bank["st"]["charge"]), 400.0 - 60.0), "bank took the spare 340 W for an hour (%.1f Wh)" % float(bank["st"]["charge"]))
	# Calm: the bank carries the lamp.
	r = Power.solve(es, {"wind": 0.0, "sun": Vector3.DOWN, "cloud": 0.0}, 60.0)
	check(r["pieces"]["c"]["powered"] and is_equal_approx(float(bank["st"]["charge"]), 280.0), "bank carries the lamp in a calm (%.1f Wh)" % float(bank["st"]["charge"]))
	lamp["st"]["on"] = false
	r = Power.solve(es, {"wind": 0.0, "sun": Vector3.DOWN, "cloud": 0.0}, 60.0)
	check(not r["pieces"]["c"]["powered"] and is_equal_approx(float(bank["st"]["charge"]), 280.0), "a lamp switched off draws nothing")
	# Flat batteries, no wind: dark.
	lamp["st"]["on"] = true
	bank["st"]["charge"] = 0.0
	r = Power.solve(es, {"wind": 0.0, "sun": Vector3.DOWN, "cloud": 0.0}, 1.0)
	check(not r["pieces"]["c"]["powered"] and float(r["short"]) > 59.0, "no power, no light")

func test_power_engines_and_brownout() -> void:
	var gen := _pw("gen_woodgas", 0, {"fuel": 100.0})
	var lamps: Array = []
	var es := [{"id": "g", "o": gen}]
	for n in 5:
		var l := _pw("floodlight", 1 + n)
		lamps.append(l)
		es.append({"id": "l%d" % n, "o": l})
	# 1500 W engine, 5 x 300 W floodlights: exactly full load.
	var r := Power.solve(es, {"wind": 0.0}, 10.0)
	check(r["pieces"]["l4"]["powered"] and is_equal_approx(float(gen["st"]["fuel"]), 90.0), "full load burns a second of fuel a second (%.2f)" % float(gen["st"]["fuel"]))
	for n in 4:
		lamps[n]["st"]["on"] = false
	r = Power.solve(es, {"wind": 0.0}, 10.0)
	check(is_equal_approx(float(gen["st"]["fuel"]), 88.0), "a fifth of the load burns a fifth as fast (%.2f)" % float(gen["st"]["fuel"]))
	gen["st"]["on"] = false
	r = Power.solve(es, {"wind": 0.0}, 10.0)
	check(is_equal_approx(float(gen["st"]["fuel"]), 88.0) and not r["pieces"]["l4"]["powered"], "a stopped engine burns nothing and powers nothing")
	# Short of power, defences outlast lights: a 400 W windmill on 3 x 300 W floods.
	var wind := _pw("windmill", 9)
	var es2 := [{"id": "w", "o": wind, "f": 1.0}]
	for n in 3:
		es2.append({"id": "f%d" % n, "o": _pw("floodlight", 10 + n)})
	r = Power.solve(es2, {"wind": 1.0}, 1.0)
	var lit := 0
	for n in 3:
		lit += 1 if r["pieces"]["f%d" % n]["powered"] else 0
	check(lit == 1, "400 W lights one 300 W floodlight of three, not all dimly (%d)" % lit)

func test_power_sun_and_wind() -> void:
	var noon := Power.sun_dir_at(10.5)
	var midnight := Power.sun_dir_at(10.0)
	check(noon.y > 0.9 and midnight.y < -0.9, "sun high at noon, under at midnight")
	check(Power.solar_factor(0.0, noon) > 0.8, "a panel tipped toward the sun's side takes most of it (%.2f)" % Power.solar_factor(0.0, noon))
	check(Power.solar_factor(0.0, midnight) == 0.0, "no sun at night")
	check(Power.solar_factor(0.0, noon) > Power.solar_factor(PI, noon), "facing the sun beats facing away")
	check(Power.wind_curve(0.02) == 0.0 and Power.wind_curve(0.9) == 1.0, "calm makes nothing, a fresh wind full power")
	for id in BuildCatalog.PIECES:
		var s := Power.spec_of(id)
		if s.is_empty():
			continue
		check(ItemDB.UNLOCK.has(id), "%s has an unlock level" % id)
		check(ItemDB.UNLOCK.get(id, 0) >= Eras.UNLOCK_LEVEL, "%s is past the medieval age" % id)
		var made := false
		for rc in Recipes.LIST:
			if rc["out"] == id:
				made = true
		check(made, "%s can be made" % id)
		check(BuildCatalog.mesh(id).get_surface_count() > 0, "%s has a mesh" % id)

func _step(o: Dictionary, ins: Array, mem: Dictionary, ctx := {}) -> bool:
	return bool(Signals.step(o, ins, mem, ctx)[0])

func test_power_signals_gates_and_memory() -> void:
	var g := _pw("logic_gate", 0)
	var want := {"AND": [false, false, false, true], "OR": [false, true, true, true], "XOR": [false, true, true, false],
		"NOT": [true, false, false, false], "NAND": [true, true, true, false], "NOR": [true, false, false, false], "XNOR": [true, false, false, true]}
	for m in Signals.GATES.size():
		g["st"]["m"] = m
		var row: Array = want[Signals.GATES[m]]
		var got := [_step(g, [false, false], {}), _step(g, [true, false], {}), _step(g, [false, true], {}), _step(g, [true, true], {})]
		check(got == row, "%s gate truth table (%s)" % [Signals.GATES[m], str(got)])
	# A toggle latch flips on each rising edge, not while held.
	var l := _pw("logic_latch", 1)
	var mem := {}
	var seq := [[false], [true], [true], [false], [true], [false]]
	var outs: Array = []
	for ins in seq:
		outs.append(_step(l, ins, mem))
	check(outs == [false, true, true, true, false, false], "toggle latch flips on rising edges (%s)" % str(outs))
	check(l["st"].get("lt", true) == false, "the latch keeps its state in st")
	# Set / reset: the first wire in sets, the others reset.
	l["st"]["m"] = 1
	l["st"]["lt"] = false
	mem = {}
	check(_step(l, [true, false], mem), "set")
	check(_step(l, [false, false], mem), "stays set")
	check(not _step(l, [false, true], mem), "reset")
	check(not _step(l, [true, true], mem), "reset wins a tie")
	# A counter pulses every N rising edges.
	var c := _pw("logic_counter", 2) # first setting: every 2
	mem = {}
	var hits := 0
	for n in 6:
		_step(c, [true], mem, {"now": n * 2.0})
		if _step(c, [false], mem, {"now": n * 2.0 + 0.1}):
			hits += 1
	check(hits == 3, "a counter set to 2 fires on every second pulse (%d of 6)" % hits)
	# A delay passes a change on after its time.
	var d := _pw("logic_delay", 3)
	d["st"]["a"] = 2 # 2 s
	mem = {}
	check(not _step(d, [true], mem, {"now": 0.0}), "delay: not yet")
	check(not _step(d, [true], mem, {"now": 1.5}), "delay: still not")
	check(_step(d, [true], mem, {"now": 2.1}), "delay: on after 2 s")
	check(_step(d, [false], mem, {"now": 3.0}), "delay: holds on after the input drops")
	check(not _step(d, [false], mem, {"now": 5.1}), "delay: off 2 s after")

func test_power_signal_sources() -> void:
	var lever := _pw("lever", 0)
	check(not _step(lever, [], {}), "a new lever is off")
	lever["st"]["on"] = true
	check(_step(lever, [], {}), "a pulled lever is on")
	var b := _pw("push_button", 1)
	Signals.press(b, 3.0, 1440.0)
	check(_step(b, [], {}, {"day": 3.0 + 0.5 / 1440.0}) and not _step(b, [], {}, {"day": 3.0 + 1.5 / 1440.0}), "a button is on for its 1 s pulse")
	var t := _pw("logic_timer", 2) # on 1 s every 5 s
	var on := 0
	for n in 50:
		if _step(t, [], {}, {"clock": 100.0 + n * 0.1}):
			on += 1
	check(on == 10, "timer on 1 s in every 5 (%d of 50 ticks)" % on)
	var clk := _pw("logic_clock", 3) # dusk to dawn
	check(_step(clk, [], {}, {"hour": 23.0}) and _step(clk, [], {}, {"hour": 2.0}) and not _step(clk, [], {}, {"hour": 12.0}), "a time switch set dusk to dawn wraps midnight")
	var day := _pw("daylight_sensor", 4)
	check(_step(day, [], {}, {"night": true}) and not _step(day, [], {}, {"night": false}), "a daylight sensor is on at night")
	var ch := _pw("charge_sensor", 5)
	ch["st"]["a"] = 2 # 50 %
	check(_step(ch, [], {}, {"charge": 60.0}) and not _step(ch, [], {}, {"charge": 40.0}), "charge sensor on above its level")
	ch["st"]["m"] = 1
	check(_step(ch, [], {}, {"charge": 40.0}) and not _step(ch, [], {}, {"charge": -1.0}), "or below it, and off with no batteries")
	var plate := _pw("pressure_plate", 6)
	var seen := []
	var near := func(r: float, who: String, cone: bool) -> bool:
		seen.append([r, who, cone])
		return true
	check(_step(plate, [], {}, {"near": near}) and seen[0] == [Signals.PRESENCE, "anyone", false], "a plate asks who stands on it")
	# Every setting cycles and reads back in words, with no text left blank.
	for id in ["push_button", "pressure_plate", "motion_sensor", "daylight_sensor", "logic_timer", "logic_clock", "logic_gate", "logic_latch", "logic_counter", "logic_delay", "charge_sensor"]:
		var o := _pw(id, 9)
		var first := Signals.describe_setting(o)
		var after := Signals.cycle(o, id == "push_button")
		check(first != "" and after != "", "%s describes its setting (%s -> %s)" % [id, first, after])
		check(Signals.verb(o, false) != "", "%s has a verb" % id)

func test_power_signal_wiring() -> void:
	var lever := _pw("lever", 0)
	var lamp := _pw("lamp_wall", 1)
	var relay := _pw("relay", 2)
	var gate := _pw("logic_gate", 3)
	check(Signals.link(lever, "0,0,0", lamp, "0,0,1"), "lever wired into a lamp")
	check(not Signals.link(lever, "0,0,0", lamp, "0,0,1"), "not twice")
	check(not Signals.link(lamp, "0,0,1", lever, "0,0,0"), "a lamp makes no signal")
	check(not Signals.link(_pw("lever", 4), "0,0,4", lamp, "0,0,1"), "a lamp takes one signal")
	check(lever["st"]["so"] == ["0,0,1"] and lamp["st"]["si"] == ["0,0,0"], "both ends know the wire")
	for n in 4:
		check(Signals.link(_pw("lever", 10 + n), "0,0,%d" % (10 + n), gate, "0,0,3"), "gate input %d" % n)
	check(not Signals.link(_pw("lever", 20), "0,0,20", gate, "0,0,3"), "a gate takes 4 inputs")
	check(Signals.link(gate, "0,0,3", relay, "0,0,2"), "gate into a relay")
	check(Signals.max_in(_pw("windmill", 5)) == 1 and Signals.max_in(_pw("power_pole", 6)) == 0, "generators take a signal, poles don't")
	check(Power.max_links(lever) == 0, "a lever takes no power cable")
	# A consumer told off by its signal draws nothing; a generator told off makes nothing.
	var gen := _pw("windmill", 7)
	var r := Power.solve([{"id": "a", "o": gen, "f": 1.0, "en": false}, {"id": "b", "o": _pw("lamp_ceiling", 8), "f": 1.0}], {"wind": 1.0}, 1.0)
	check(r["supply"] == 0.0 and r["demand"] > 0.0, "a windmill told off makes nothing")
	r = Power.solve([{"id": "a", "o": _pw("windmill", 7), "f": 1.0}, {"id": "b", "o": _pw("lamp_ceiling", 8), "f": 1.0, "en": false}], {"wind": 1.0}, 1.0)
	check(r["demand"] == 0.0 and not r["pieces"]["b"]["powered"], "a lamp told off draws nothing")

func test_power_defences() -> void:
	check(absf(Defences.to_segment(Vector3(1, 1, 0), Vector3.ZERO, Vector3(2, 0, 0)) - 1.0) < 0.001, "distance to a fence span")
	check(Defences.to_segment(Vector3(5, 0, 0), Vector3.ZERO, Vector3(2, 0, 0)) > 2.9, "past the end of a span is measured to its end")
	check(Defences.in_cone(Vector3.ZERO, Vector3(0, 0, -1), Vector3(0.5, 0, -3), 4.0, 0.8), "in the flame's cone")
	check(not Defences.in_cone(Vector3.ZERO, Vector3(0, 0, -1), Vector3(3, 0, -1), 4.0, 0.8), "off to the side is out of it")
	check(not Defences.in_cone(Vector3.ZERO, Vector3(0, 0, -1), Vector3(0, 0, -6), 4.0, 0.8), "and so is too far")
	for id in ["auto_turret", "heavy_turret", "fence_post", "spike_trap", "flame_trap", "alarm_bell", "searchlight"]:
		var o := _pw(id, 0)
		check(Defences.is_defence(o) and int(Power.spec(o).get("prio", 0)) == 2, "%s is a defence, last to brown out" % id)
		check(Signals.max_in(o) == 1, "%s can be armed by a signal" % id)
		check(not Defences.lines(o, true).is_empty(), "%s describes itself" % id)
	check(_pw("flame_trap", 0)["st"].has("fuel"), "a flame trap has a fuel store")
	check(Defences.hostile_creature(null) == false and Defences.hostile_npc(null) == false, "nothing is no target")

func test_fov_is_horizontal() -> void:
	var gs = load("res://src/settings/graphics_settings.gd")
	check(absf(gs.vertical_fov(90.0) - 58.72) < 0.05, "90 degrees across a 16:9 screen is about 58.7 degrees tall")
	check(absf(gs.vertical_fov(121.28) - 90.0) < 0.05, "the old 90 tall is about 121 across")
	check(is_equal_approx(float(gs.DEFAULTS["fov"]), 90.0), "the default view is 90 degrees across")

func test_power_automation() -> void:
	var belt := _pw("conveyor_belt", 0)
	var rock := ItemDB.make("stone", 1, 1.0, {})
	check(Automation.put(belt, rock) and not Automation.put(belt, rock.duplicate()), "a belt takes an item at its start, then not another right on top")
	Automation.roll(belt, 0.3)
	check(Automation.put(belt, rock.duplicate()), "once the first has moved on, the next goes on")
	var ended := false
	for n in 10:
		ended = Automation.roll(belt, 0.1) or ended
	check(ended and float(belt["st"]["q"][0][1]) == 1.0, "the front item reaches the end")
	check(float(belt["st"]["q"][0][1]) - float(belt["st"]["q"][1][1]) >= Automation.GAP - 0.001, "items keep their gap")
	check(Automation.take(belt)["type"] == "stone" and belt["st"]["q"].size() == 1, "an arm can take the front item off")
	# A furnace smelts ore put in it and gives out only the ingots.
	var fur := _pw("electric_furnace", 1)
	check(not Automation.put(fur, ItemDB.make("planks", 1, 1.0, {})), "a furnace won't take planks")
	for n in 4:
		check(Automation.put(fur, ItemDB.make("iron_ore", 1, 1.0, {})), "a furnace takes iron ore")
	var rng := RandomNumberGenerator.new()
	check(Automation.work(fur, "", 10, {}, rng), "it smelts")
	var inv := Storage.open(fur)
	check(inv.count("iron_ingot") >= 1 and inv.count("iron_ore") < 4, "ore became ingots (%d ingots, %d ore)" % [inv.count("iron_ingot"), inv.count("iron_ore")])
	check(Automation.take(fur)["type"] == "iron_ingot", "it lets go of the ingots, not the ore")
	# A sawmill saws logs.
	var saw := _pw("power_sawmill", 2)
	Automation.put(saw, ItemDB.make("wood", 1, 1.0, {}))
	check(Automation.work(saw, "", 10, {}, rng) and Storage.open(saw).count("planks") == 6, "a sawmill makes 6 planks a log")
	# An auto-miner drills its vein for ever; with no vein it does nothing.
	var miner := _pw("auto_miner", 3)
	check(not Automation.work(miner, "", 10, {}, rng), "no vein, no ore")
	for n in 3:
		Automation.work(miner, "iron_vein", 10, {}, rng)
	check(Storage.open(miner).count("iron_ore") == 3, "three cycles, three iron ore")
	check(not Automation.put(miner, ItemDB.make("stone", 1, 1.0, {})), "nothing goes into a miner")
	check(Automation.main_yield("rock") == "stone", "a quarry digs stone")
	# An assembler picks a recipe it has the makings for.
	var asm := _pw("assembler", 4)
	check(Automation.next_recipe(asm) == "", "an empty assembler has nothing to make")
	Automation.put(asm, ItemDB.make("copper_wire", 1, 1.0, {}))
	Automation.put(asm, ItemDB.make("resin", 1, 1.0, {}))
	var what := Automation.next_recipe(asm)
	check(what != "" and Automation.work(asm, "", 10, {}, rng), "with wire and resin in it, it makes something (%s)" % what)
	check(Automation.is_container("b:storage_chest") and Automation.is_container("b:conveyor_belt") and not Automation.is_container("b:robot_arm"), "chests and belts hold items, arms don't")
	var wheel := _pw("water_wheel", 5)
	var r := Power.solve([{"id": "w", "o": wheel, "f": 1.0}, {"id": "l", "o": _pw("lamp_ceiling", 6), "f": 1.0}], {}, 1.0)
	check(is_equal_approx(float(r["supply"]), 600.0), "a water wheel in a river makes its full 600 W")
	r = Power.solve([{"id": "w", "o": _pw("water_wheel", 5), "f": 0.0}], {}, 1.0)
	check(float(r["supply"]) == 0.0, "and nothing on dry ground")

# --- Fire ------------------------------------------------------------------------------

func test_fire_burns_by_material() -> void:
	check(FireSim.burns("longhouse") and FireSim.burns("market_stall") and FireSim.burns("pine"), "timber buildings, stalls and trees burn")
	check(not FireSim.burns("castle_wall") and not FireSim.burns("rock") and not FireSim.burns("hab_block"), "stone, rock and metal do not")
	check(FireSim.burns("b:wall_plaster") and not FireSim.burns("b:wall_stone"), "a built timber wall burns, a stone one does not")
	check(FireSim.profile("cottage")["leaves"] == "masonry" and FireSim.profile("longhouse")["leaves"] == "timber", "brick houses leave walls, timber ones fall in")
	var st := {}
	check(not FireSim.ignite("castle_wall", st, 1.0, 0.0) and not st.has("fire"), "stone will not catch")
	FireSim.scorch(st, 0.3)
	check(is_equal_approx(float(st["char"]), 0.3), "but it scorches")

func test_fire_grows_and_burns_out() -> void:
	var e := FireSim.calm()
	var st := {}
	check(FireSim.ignite("market_stall", st, 0.6, 0.0, true), "a stall catches")
	var h0 := FireSim.heat(st)
	for i in 30:
		FireSim.step("market_stall", st, 1.0, e, i)
	check(FireSim.heat(st) > h0 + 0.4, "it takes hold within half a minute (%.2f -> %.2f)" % [h0, FireSim.heat(st)])
	check(float(st.get("char", 0.0)) > 0.05, "and scorches as it burns")
	var r := ""
	var secs := 0
	while r == "" and secs < 2000:
		r = FireSim.step("market_stall", st, 1.0, e, secs)
		secs += 1
	check(r == "burnt" and not st.has("fire"), "with nothing left to burn it burns out (%s after %d s)" % [r, secs])
	check(int(st.get("lit_by", 0)) == 1, "and remembers who lit it")
	check(FireSim.catch_chance("market_stall", st, 1.0, e, 0.0) == 0.0 or not st.has("fl"), "what burnt out does not light again")

func test_fire_rain_beats_it_down() -> void:
	var dry := FireSim.calm()
	var wet := FireSim.calm()
	wet["rain"] = 1.0
	wet["wet"] = 1.0
	var a := {}
	var b := {}
	FireSim.ignite("longhouse", a, 1.0, 0.0)
	FireSim.ignite("longhouse", b, 1.0, 0.0)
	for i in 120:
		FireSim.step("longhouse", a, 1.0, dry, i)
		FireSim.step("longhouse", b, 1.0, wet, i)
	check(FireSim.heat(a) > 0.85, "a house goes up in dry weather (%.2f)" % FireSim.heat(a))
	check(not b.has("fire") or FireSim.heat(b) < FireSim.heat(a) - 0.3, "a downpour holds it down (%.2f)" % FireSim.heat(b))
	check(FireSim.catch_chance("longhouse", {}, 1.0, wet, 0.0) < FireSim.catch_chance("longhouse", {}, 1.0, dry, 0.0) * 0.6, "and wet things are hard to light")

func test_fire_put_out_and_fed() -> void:
	var e := FireSim.calm()
	var st := {}
	FireSim.ignite("fruit_cart", st, 0.5, 0.0)
	for i in 8:
		FireSim.step("fruit_cart", st, 1.0, e, i)
	var blows := 0
	while st.has("fire") and blows < 10:
		FireSim.beat(st, 0.8, 8.0)
		blows += 1
	check(not st.has("fire") and blows <= 6, "a small fire is beaten out in a few blows (%d)" % blows)
	check(float(st.get("fl", 0.0)) > 1.0, "with fuel left in it")
	var big := {}
	FireSim.ignite("longhouse", big, 1.0, 0.0)
	for i in 90:
		FireSim.step("longhouse", big, 1.0, e, i)
	var h := FireSim.heat(big)
	FireSim.beat(big, 0.8, 90.0)
	check(big.has("fire") and FireSim.heat(big) > h - 0.05, "but a house well alight barely notices a beating")
	var buckets := 0
	while big.has("fire") and buckets < 12:
		FireSim.quench(big, 0.55, 90.0 + buckets)
		buckets += 1
	check(not big.has("fire") and buckets >= 2 and buckets <= 6, "a few buckets put out a house (%d)" % buckets)
	check(FireSim.soak(big, 100.0) > 0.5 and FireSim.catch_chance("longhouse", big, 1.0, e, 100.0) < 0.2, "soaked, it is hard to light again")
	check(FireSim.soak(big, 100.0 + 600.0) == 0.0, "until it dries out")
	var oiled := {}
	FireSim.feed(oiled, 60.0)
	check(FireSim.catch_chance("chest", oiled, 0.3, e, 0.0) >= 0.9, "oil on it, it catches from a spark")
	FireSim.ignite("chest", oiled, 0.3, 0.0)
	var h1 := FireSim.heat(oiled)
	FireSim.feed(oiled, 60.0)
	check(FireSim.heat(oiled) > h1 + 0.2, "more oil on a fire flares it up")

func test_fire_spreads_downwind() -> void:
	var e := FireSim.calm()
	e["wind"] = 0.8
	e["wind_dir"] = Vector2(1, 0)
	var down := FireSim.spread_rate(0.9, 2.5, Vector2(1, 0), 6.0, "longhouse", {}, e, 0.0)
	var up := FireSim.spread_rate(0.9, 2.5, Vector2(-1, 0), 6.0, "longhouse", {}, e, 0.0)
	check(down > up * 2.0 and down > 0.0, "flames lick much further downwind (%.3f vs %.3f)" % [down, up])
	check(FireSim.spread_rate(0.9, 0.0, Vector2(1, 0), 6.0, "longhouse", {}, e, 0.0) > down, "touching buildings catch fastest")
	check(FireSim.spread_rate(0.9, 40.0, Vector2(1, 0), 6.0, "longhouse", {}, e, 0.0) == 0.0, "but not across a field")
	check(FireSim.spread_rate(0.9, 0.0, Vector2(1, 0), 6.0, "castle_wall", {}, e, 0.0) == 0.0, "and never to stone")
	check(FireSim.spread_rate(0.2, 0.0, Vector2(1, 0), 6.0, "longhouse", {}, e, 0.0) == 0.0, "a fire just catching throws no flame yet")
	check(FireSim.spread_rate(0.9, 1.0, Vector2(1, 0), 6.0, "oak", {}, e, 0.0) < FireSim.spread_rate(0.9, 1.0, Vector2(1, 0), 6.0, "longhouse", {}, e, 0.0) * 0.3, "live trees catch much less readily than timber")

func test_fire_catches_up_while_away() -> void:
	var st := {}
	FireSim.ignite("barrels", st, 1.0, 0.0)
	check(FireSim.catch_up("barrels", st, 3600.0, FireSim.calm(), 3600.0) == "burnt", "a fire left an hour has burnt out")

func test_fire_ruins() -> void:
	var sp := FireRuins.encode(7.5, 9.0, 300)
	var d := FireRuins.decode(sp)
	check(is_equal_approx(d[0], 7.5) and is_equal_approx(d[1], 9.0) and d[2] == 300 & 255, "a ruin's size survives its species number (%s)" % [d])
	for v in [FireRuins.TIMBER, FireRuins.MASONRY, FireRuins.HEAP]:
		var m := FireRuins.build(sp, v)
		var a := m.get_aabb()
		check(m.get_surface_count() >= 2 and a.size.x > 6.0 and a.size.x < 12.0, "ruin %d is built to its footprint (%s)" % [v, a.size])
	check(FireRuins.build(sp, FireRuins.MASONRY).get_aabb().size.y > FireRuins.build(sp, FireRuins.TIMBER).get_aabb().size.y * 0.8, "brick walls stand above the ash")
	check(ObjectLibrary.label(FireSim.RUIN) == "Burnt Ruin" and ObjectLibrary.kind(FireSim.RUIN) == "structure", "a ruin is a structure you can pick through")
	check(Durability.TABLE.has(FireSim.RUIN), "for charcoal, nails and stone")

func test_fire_items() -> void:
	for t in ["fire_pot", "fire_bottle", "incendiary_grenade", "flamethrower"]:
		check(float(ItemDB.def(t).get("incendiary", 0.0)) > 0.0, "%s sets things alight" % t)
	check(ItemDB.def("fire_pot")["era"] == Eras.MEDIEVAL and int(ItemDB.UNLOCK.get("fire_pot", 99)) < int(ItemDB.UNLOCK.get("fire_bottle", 0)), "the fire pot comes before the fire bottle")
	check(ItemDB.def("incendiary_grenade")["era"] == Eras.SCIFI and int(ItemDB.UNLOCK.get("incendiary_grenade", 0)) > int(ItemDB.UNLOCK.get("fire_bottle", 99)), "the incendiary grenade is a later-era fire")
	check(float(ItemDB.ammo_mods("arrow", "arrow_fire").get("incendiary", 0.0)) > 0.0, "fire arrows set things alight")
	check(Crime.FINES.has("arson"), "arson is a crime")

func test_water_life() -> void:
	# Lakes grow lily pads and reeds, the open sea reefs and kelp; every key's buffer holds
	# whole instances and its mesh builds. (On today's terrain, as a new world has it.)
	var tv := WorldField.terrain_v
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242)
	var f := AquaFlora.Field.new(4242)
	var lakes: Array = []
	var seas: Array = []
	for j in range(-60, 60, 2):
		for i in range(-60, 60, 2):
			var x := i * 64.0 + 32.0
			var z := j * 64.0 + 32.0
			var h := g.field.height(x, z)
			if h > -0.5 or h < -9.0:
				continue
			if f.sea_t(x, z) < 0.05 and h > -2.5 and lakes.size() < 8:
				lakes.append(Vector2i(i, j))
			elif f.sea_t(x, z) > 0.95 and h < -2.0 and seas.size() < 12:
				seas.append(Vector2i(i, j))
	check(lakes.size() > 0 and seas.size() > 0, "found lakes (%d) and sea (%d)" % [lakes.size(), seas.size()])
	var lake := {}
	for k in lakes:
		AquaFlora.build(g.generate(k.x, k.y), 1.0, lake)
	var sea := {}
	for k in seas:
		AquaFlora.build(g.generate(k.x, k.y), 1.0, sea)
	check(lake.has("aq_reed@0") and (lake.has("aq_pad_0@0") or lake.has("aq_pad_1@0") or lake.has("aq_pad_2@0")), "lakes have reeds and lily pads: %s" % [lake.keys()])
	check(not lake.has("aq_coral_brain@0"), "no reef in a lake")
	check(sea.has("aq_coral_branch@0") and sea.has("aq_kelp@0"), "the sea has reefs and kelp: %s" % [sea.keys()])
	# Reefs stand on rock: some sea chunk has bommies, laid as stones.
	var rocks := {}
	var solid := PackedFloat32Array()
	for k in seas:
		AquaFlora.reef_rocks(g.generate(k.x, k.y), rocks, solid)
	check(rocks.has("stone:rock_a") or rocks.has("stone:rock_b"), "reefs have rock bommies")
	check(solid.size() % 13 == 0 and solid.size() > 0, "bommie rocks are solid")
	# No coral in water under snowy mountains, however wide.
	var cold := {}
	var n_cold := 0
	for j in range(-20, 20, 2):
		for i in range(-20, 20, 2):
			var x := i * 64.0 + 32.0
			var z := j * 64.0 + 32.0
			if n_cold < 6 and g.field.height(x, z) < -2.0 and f.warm(x, z) < 0.02:
				n_cold += 1
				AquaFlora.build(g.generate(i, j), 1.0, cold)
	check(n_cold > 0 and not cold.has("aq_coral_branch@0") and not cold.has("aq_coral_brain@0"), "no coral in cold mountain water (%d chunks)" % n_cold)
	var one := {}
	var again := {}
	var sea_chunk := g.generate(seas[0].x, seas[0].y)
	AquaFlora.build(sea_chunk, 1.0, one)
	AquaFlora.build(sea_chunk, 1.0, again)
	check(one.hash() == again.hash(), "water plants are the same every time")
	for k in lake.keys() + sea.keys():
		var buf: PackedFloat32Array = lake.get(k, sea.get(k))
		check(buf.size() % 16 == 0 and buf.size() > 0, "%s holds whole instances" % k)
		check(AquaKit.SPECIES.has(k.get_slice("@", 0)), "%s is a known species" % k)
	var dry := {}
	AquaFlora.build(g.generate(0, 0), 1.0, dry)
	check(dry.is_empty() or g.field.height(32.0, 32.0) < 1.0, "dry land grows no water plants")
	for sp in AquaKit.SPECIES:
		check(AquaKit.mesh(sp).get_surface_count() == 1, "%s mesh builds" % sp)
	for k in FishKit.KINDS:
		check(FishKit.mesh(k).get_surface_count() == 1, "%s mesh builds" % k)
	WorldField.terrain_v = tv

func test_props_settle_on_ground() -> void:
	# A chest on a 15 degree slope lies with it, every corner bedded in by SINK.
	var box := AABB(Vector3(-0.6, 0, -0.4), Vector3(1.2, 0.7, 0.8))
	var slope := tan(deg_to_rad(15.0))
	var ground := func(x: float, z: float) -> float: return 10.0 + x * slope
	var xf := PropSettle.fit(ground, Vector3(5, 10, 5), 0.7, 1.0, box)
	var up := Vector3(-slope, 1, 0).normalized()
	check(xf.basis.y.normalized().angle_to(up) < 0.01, "prop tips to the slope, off by %.3f" % xf.basis.y.normalized().angle_to(up))
	for c in [Vector3(-0.6, 0, -0.4), Vector3(0.6, 0, -0.4), Vector3(-0.6, 0, 0.4), Vector3(0.6, 0, 0.4)]:
		var w: Vector3 = xf * c
		var d: float = ground.call(w.x, w.z) - w.y
		check(absf(d - PropSettle.SINK) < 0.01, "corner bedded in by SINK, got %.3f" % d)
	# Flat ground: level, its base just under the ground.
	var flat := func(_x: float, _z: float) -> float: return 3.0
	var fx := PropSettle.fit(flat, Vector3(0, 3, 0), 1.2, 1.0, box)
	check(fx.basis.y.normalized().angle_to(Vector3.UP) < 0.001 and absf(fx.origin.y - (3.0 - PropSettle.SINK)) < 0.001, "level on the flat")
	# A cliff: the lean stops at MAX_TILT and nothing floats.
	var cliff := func(x: float, _z: float) -> float: return x * 2.0
	var cx := PropSettle.fit(cliff, Vector3.ZERO, 0.0, 1.0, box)
	check(absf(cx.basis.y.normalized().angle_to(Vector3.UP) - PropSettle.MAX_TILT) < 0.01, "lean capped on a cliff")
	for c in [Vector3(-0.6, 0, -0.4), Vector3(0.6, 0, 0.4)]:
		var w: Vector3 = cx * c
		check(cliff.call(w.x, w.z) - w.y >= PropSettle.SINK - 0.001, "nothing floats on a cliff")
	# Generated props: a town's wagons, stalls and barrels (on its flattened ground) sit
	# flush; out in the wilds chests lie far less buried than they stood level, and none
	# hangs in the air.
	var keep_tv := WorldField.terrain_v
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(4242, true)
	var n := 0
	var bury_old := 0.0
	var bury_new := 0.0
	for kz in range(-2, 3):
		for kx in range(-2, 3):
			var chunk := g.generate(kx, kz)
			for o in chunk["objects"]:
				var m := ProbeProps.measure(chunk, o) if PropSettle.settles(o["t"]) else {}
				if m.is_empty():
					continue
				n += 1
				bury_new += m["bury"]
				bury_old += ProbeProps.measure(chunk, o, true)["bury"]
				check(m["float"] < 0.2, "%s floats %.3f m" % [o["t"], m["float"]])
				if not Eras.CACHE_TYPES.has(o["t"]):
					check(m["bury"] < 0.05 and m["float"] < 0.01, "%s sits flush: bury %.3f, float %.3f" % [o["t"], m["bury"], m["float"]])
	check(bury_new < bury_old * 0.7, "props less buried than standing level: %.2f m against %.2f m" % [bury_new, bury_old])
	check(n > 5, "found settled props to check (%d)" % n)
	# Rooms keep theirs: a chest stocked in a cottage is not set on the ground.
	var inside := {"t": "chest", "p": Vector3(5, 99, 5), "r": 0.0, "s": 1.0, "st": {"inside": "cottage"}}
	check(PropSettle.transform(g.generate(0, 0), inside) == null, "a room's chest keeps its place")
	WorldField.terrain_v = keep_tv
	# Furniture stands on its floor.
	check(ProbeProps.floors()["bad"] == 0, "room furniture stands on its floor, inside its walls and clear of its neighbours")

func test_caches_rest_v21() -> void:
	# A v20 world places every cache where it always did (object id and x, z pinned from
	# before v21).
	const PINS := [[-2, -2, 4, 51.700, 31.762], [-1, -2, 5, 42.985, 19.893], [0, -2, 4, 47.298, 4.408], [1, -2, 25, 15.836, 59.603],
		[2, -2, 6, 34.055, 33.602], [2, -2, 19, 5.978, 50.770], [-2, -1, 6, 25.838, 25.457], [-1, -1, 8, 13.510, 53.874],
		[0, -1, 7, 50.438, 32.712], [1, -1, 35, 53.973, 43.445], [2, -1, 40, 23.289, 21.417], [-2, 0, 8, 51.542, 5.719],
		[-1, 0, 4, 52.599, 48.489], [0, 0, 39, 25.048, 40.415], [1, 0, 92, 29.070, 29.661], [2, 0, 68, 49.710, 59.097],
		[-2, 1, 7, 22.348, 31.355], [-1, 1, 37, 46.482, 36.538], [0, 1, 59, 24.312, 34.652], [1, 1, 53, 39.748, 57.065],
		[2, 1, 15, 20.775, 51.181], [-2, 2, 6, 15.242, 12.988], [-1, 2, 61, 4.307, 48.625], [0, 2, 10, 6.272, 41.878],
		[1, 2, 0, 9.614, 45.000], [2, 2, 0, 33.063, 16.947]]
	var keep_tv := WorldField.terrain_v
	var old := {}
	var new := {}
	for tv in [ChunkGenerator.CACHE_REST_V - 1, ChunkGenerator.CACHE_REST_V]:
		WorldField.terrain_v = tv
		var g := ChunkGenerator.new(4242, true) # a generator per version: it caches what it plans
		for kz in range(-2, 3):
			for kx in range(-2, 3):
				(old if tv < ChunkGenerator.CACHE_REST_V else new)[Vector2i(kx, kz)] = g.generate(kx, kz)
	WorldField.terrain_v = keep_tv
	for pin in PINS:
		var o := {"t": "", "p": Vector3.INF}
		for c in old[Vector2i(pin[0], pin[1])]["objects"]:
			if int(c["i"]) == pin[2]:
				o = c
		var p: Vector3 = o["p"]
		check(Eras.CACHE_TYPES.has(o["t"]) and absf(p.x - pin[3]) < 0.002 and absf(p.z - pin[4]) < 0.002,
			"v20 cache %s at (%.3f, %.3f), pinned (%.3f, %.3f)" % [o["t"], p.x, p.z, pin[3], pin[4]])
	# v21 moves wild caches only: every other object, and every index, stays as it was;
	# a moved cache goes no further than a few metres, onto ground it fits no worse.
	var moved := 0
	for k in old:
		var oa: Array = old[k]["objects"]
		var na: Array = new[k]["objects"]
		check(oa.size() == na.size(), "same objects in chunk %s" % k)
		for i in mini(oa.size(), na.size()):
			var a: Dictionary = oa[i]
			var b: Dictionary = na[i]
			if Eras.CACHE_TYPES.has(a["t"]):
				check(Eras.CACHE_TYPES.has(b["t"]), "cache %d of %s still a cache" % [i, k])
				var d := Vector2(a["p"].x - b["p"].x, a["p"].z - b["p"].z).length()
				check(d < 7.01, "cache moved %.2f m" % d)
				if d > 0.001:
					moved += 1
					var foot := AABB(Vector3(-0.8, 0, -0.8), Vector3(1.6, 0.8, 1.6))
					var ga := func(x: float, z: float) -> float: return ChunkGenerator.height_at(old[k], x, z)
					var gb := func(x: float, z: float) -> float: return ChunkGenerator.height_at(new[k], x, z)
					check(PropSettle.misfit(gb, b["p"], foot) <= PropSettle.misfit(ga, a["p"], foot) + 0.001, "a moved cache fits its ground no worse")
			else:
				check(a["t"] == b["t"] and a["p"] == b["p"] and a["r"] == b["r"], "object %d of %s unchanged by v21" % [i, k])
	check(moved > 0, "v21 moved some caches off rough ground (%d)" % moved)

func test_climate_wear() -> void:
	var was := WorldField.terrain_v
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var f := WorldField.new(4242)
	var g := WorldField.new(4242)
	var mossy := 0
	var cold := 0
	var dusty := 0
	var boggy := 0
	var ranged := true
	var same := true
	var desert_dust := true
	var home_mild := true
	for iz in range(-15, 16):
		for ix in range(-15, 16):
			var x := ix * 400.0 + 17.0
			var z := iz * 400.0 - 31.0
			var c := ClimateWear.levels(f, x, z)
			same = same and c == ClimateWear.levels(g, x, z)
			for v in [c.r, c.g, c.b, c.a]:
				ranged = ranged and v >= 0.0 and v <= 1.0
			mossy += 1 if c.r > 0.8 else 0
			cold += 1 if c.g > 0.6 else 0
			dusty += 1 if c.b > 0.5 else 0
			boggy += 1 if c.a > 0.5 else 0
			var cl := f.climate_at(x, z)
			var lf := f.landform_at(x, z)
			if cl.y + WorldField.LF_WET[lf] < 0.15 and cl.x > 0.55:
				desert_dust = desert_dust and c.b > 0.5
			if Vector2(x, z).length() < 900.0:
				home_mild = home_mild and c.g < 0.3
	check(ranged, "levels are 0..1")
	check(same, "levels are the same from any field of the seed (nothing to sync)")
	check(mossy > 0 and cold > 0 and dusty > 0 and boggy > 0, "the world has wet, cold, dusty and boggy places (%d %d %d %d)" % [mossy, cold, dusty, boggy])
	check(mossy < 961 and cold < 961 and dusty < 961, "and they are regions, not the whole world")
	check(desert_dust, "hot dry land is dusty")
	check(home_mild, "the land round the spawn is not frozen")
	# The map holds the levels at its texel middles.
	var b := ClimateWear.map_bytes(f, Vector2(-1000, 500), 640.0, 8)
	check(b.size() == 8 * 8 * 4, "map is RES x RES RGBA8")
	var lv := ClimateWear.levels(f, -1000 + 3.5 * 80.0, 500 + 5.5 * 80.0)
	check(absi(b[(5 * 8 + 3) * 4 + 1] - int(round(lv.g * 255.0))) <= 1 and absi(b[(5 * 8 + 3) * 4] - int(round(lv.r * 255.0))) <= 1, "map texel = levels there")
	check(absf(ClimateWear.bog(f, 123.0, 456.0) - ClimateWear.levels(f, 123.0, 456.0).a) < 1e-5, "bog() matches the map's bog")
	WorldField.terrain_v = WorldField.CLIMATE_V - 1
	var old := WorldField.new(4242)
	var none := true
	for i in 40:
		var oc := ClimateWear.levels(old, i * 731.0 - 9000.0, i * -517.0 + 4000.0)
		none = none and oc.g == 0.0
	check(none, "worlds made before climates have no cold belts")
	WorldField.terrain_v = was
	# Built pieces weather toward their place's level over game days; the rest are old.
	check(ClimateWear.maturity(-1.0, 5.0) == 1.0, "no build day: as old as the village")
	check(ClimateWear.maturity(5.0, 5.0) == 0.0, "new built piece is clean")
	check(absf(ClimateWear.maturity(5.0, 5.0 + ClimateWear.MATURE_DAYS * 0.5) - 0.5) < 1e-4, "half weathered half way")
	check(ClimateWear.maturity(5.0, 500.0) == 1.0, "fully weathered in time")
	check(ClimateWear.frost_now(10.22) > 0.9, "frost thickest before dawn")
	check(ClimateWear.frost_now(10.5) == 0.0 and ClimateWear.frost_now(10.7) == 0.0, "no frost by day")
	check(ClimateWear.frost_now(10.0) > 0.3, "frost growing at midnight")
	var chunk := {"seed": 1, "cx": 0, "cz": 0, "objects": [
		{"t": "b:wall_plaster", "i": 0, "p": Vector3(1, 0, 1), "r": 0.0, "s": 1.0, "st": {"day": 1e9}},
		{"t": "b:wall_plaster", "i": 1, "p": Vector3(3, 0, 1), "r": 0.0, "s": 1.0, "st": {}}]}
	var bufs := ChunkNode.build_object_buffers(chunk, false)
	var buf: PackedFloat32Array = bufs[ObjectLibrary.mesh_key(chunk["objects"][0])]
	check(buf.size() == 32 and buf[15] == 0.0 and buf[31] == 1.0, "a piece built today is clean, one with no day is old (instance alpha)")

func test_kit_surfaces_worn() -> void:
	var parts := BuildCatalog.model_parts("village/Wall_Plaster_Straight")
	var worn := 0
	for p in parts:
		var m: Material = p[0]
		if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("kit_surface.gdshader"):
			worn += 1
			var sm := m as ShaderMaterial
			check(sm.get_shader_parameter("albedo_tex") != null, "worn %s keeps its colour map" % m.resource_name)
			check(sm.get_shader_parameter("mean_lum") > 0.02, "worn %s has a mean brightness" % m.resource_name)
	check(worn == parts.size() and worn > 0, "village wall surfaces weather (%d of %d)" % [worn, parts.size()])
	for p in BuildCatalog.model_parts("village/Window_Wide_Round1"):
		if p[0] != null and (p[0] as Material).resource_name == "MI_WindowGlass":
			check(p[0] is BaseMaterial3D, "window glass stays glass")
	var std := StandardMaterial3D.new()
	check(BuildCatalog.worn(std, "props/Barrel") == std, "only the village kit weathers")
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	check(BuildCatalog.worn(glow, "village/X") == glow, "nothing glowing is touched")

func test_climate_belts() -> void:
	var c := Climate.new(4242)
	var snow_tropic := 0
	var snow_cold := 0
	var rain_wet := 0
	var rain_dry := 0
	for i in 1500:
		var h := float(i) * 1.7
		if float(c.at(h, 0.0, 0.0, 10.0, WorldField.LF_NONE, 50.0, Vector2(0.95, 0.5))["snow"]) > 0.5:
			snow_tropic += 1
		if float(c.at(h, 0.0, 0.0, 10.0, WorldField.LF_NONE, 50.0, Vector2(0.05, 0.5))["snow"]) > 0.5:
			snow_cold += 1
		if float(c.at(h, 0.0, 0.0, 10.0, WorldField.LF_NONE, 50.0, Vector2(0.5, 0.95))["precip"]) > 0.3:
			rain_wet += 1
		if float(c.at(h, 0.0, 0.0, 10.0, WorldField.LF_NONE, 50.0, Vector2(0.5, 0.1))["precip"]) > 0.3:
			rain_dry += 1
	check(snow_tropic == 0, "it never snows on low ground in the tropics")
	check(snow_cold > snow_tropic, "the cold belts get snow (%d of 1500)" % snow_cold)
	check(rain_wet > rain_dry * 2, "wet lands rain much oftener than dry ones (%d vs %d)" % [rain_wet, rain_dry])

func test_bog_mist() -> void:
	var c := Climate.new(4242)
	var bog := 0.0
	var dry := 0.0
	for i in 1500:
		var h := float(i) * 1.3
		bog += float(c.at(h, 0.0, 0.0, 3.0, WorldField.LF_NONE, 50.0, Vector2(0.5, 0.9))["mist"])
		dry += float(c.at(h, 0.0, 0.0, 3.0, WorldField.LF_NONE, 50.0, Vector2(0.5, 0.5))["mist"])
	check(bog > dry * 1.5, "bogs lie under mist far oftener (%.0f vs %.0f)" % [bog, dry])
