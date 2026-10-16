extends SceneTree
## Headless test suite. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.

var _failures := 0
var _passes := 0
var _current := ""

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
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
