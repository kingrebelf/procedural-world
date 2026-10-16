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

func test_levelling_and_attributes() -> void:
	var s := Stats.new()
	check(s.level == 1 and s.points == 0 and s.max_health() == 100.0, "fresh character")
	check(Stats.xp_to_next(1) < Stats.xp_to_next(10), "levels get harder")
	var gained := s.add_xp(Stats.xp_to_next(1) + Stats.xp_to_next(2) + 5)
	check(gained == 2 and s.level == 3 and s.points == 2 * Stats.POINTS_PER_LEVEL and s.xp == 5, "xp carries over levels (%d, %d)" % [s.level, s.xp])
	check(s.spend("end") and s.max_health() == 110.0 and s.max_stamina() == 108.0, "endurance raises health and stamina")
	check(s.spend("str") and s.damage_mult() > 1.0, "strength hits harder")
	check(s.spend("agi") and s.speed_mult() > 1.0 and s.stamina_cost_mult() < 1.0, "agility is faster and tires less")
	check(s.spend("int") and s.xp_mult() > 1.0, "intellect learns faster")
	check(not s.spend("luck"), "unknown attribute rejected")
	while s.points > 0:
		s.spend("end")
	check(not s.spend("end"), "no points, no spending")
	var back := Stats.from_data(JSON.parse_string(JSON.stringify(s.to_data())))
	check(back.level == s.level and back.xp == s.xp and back.attrs == s.attrs, "stats survive a save through JSON")
	for i in 400:
		s.add_xp(1000000)
	check(s.level == Stats.MAX_LEVEL and s.xp == 0, "level cap holds")
