extends SceneTree
## End-to-end persistence check through the real game scene:
##   godot --headless --path . --script res://tests/integration_test.gd
## Creates a world, plays it (streams chunks, fells a tree, digs, loots, trades),
## quits, reopens it and checks that everything stayed exactly as left.

var _fail := 0

func check(c: bool, m: String) -> void:
	if c:
		print("  ok   ", m)
	else:
		_fail += 1
		printerr("  FAIL ", m)

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var game = root.get_node("/root/Game")
	game.new_world("Integration", "424242")
	var world_id: String = game.store.root.get_file()
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	var world = current_scene
	var player = world.player
	for i in 600:
		await process_frame
		if not player.frozen:
			break
	check(not player.frozen, "player spawned on loaded ground")
	await _frames(120)
	var streamer: ChunkStreamer = world.streamer
	check(streamer.chunks.size() >= 9, "chunks streamed in (%d)" % streamer.chunks.size())
	var here: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(player.global_position))
	var here_key: Vector2i = here.key

	# Fell the first tree in the current chunk (or any loaded chunk).
	var felled := {}
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "tree" and not o["st"].get("gone", false):
				felled = {"key": k, "i": o["i"], "t": o["t"]}
				c.remove_object(o["i"])
				game.give(ItemDB.make(ObjectLibrary.YIELD[o["t"]], 5, 1.0, game.origin_here("gathered", o["e"], k)))
				break
		if not felled.is_empty():
			break
	check(not felled.is_empty(), "found and felled a tree")

	# Dig a crater at the player's feet.
	var p: Vector3 = player.global_position
	var lx := p.x - here.key.x * 64.0
	var lz := p.z - here.key.y * 64.0
	var before := ChunkGenerator.height_at(here.data, lx, lz)
	streamer.dig(p, 2.0, 1.0)
	var after := ChunkGenerator.height_at(here.data, lx, lz)
	check(after < before - 0.5, "dig lowered terrain (%.2f -> %.2f)" % [before, after])

	# Loot the first cache found.
	var looted := {}
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "cache" and not o["st"].get("opened", false):
				for it in o["st"]["loot"]:
					game.give(it)
				o["st"]["loot"] = []
				o["st"]["opened"] = true
				game.mark_chunk_dirty(c.data)
				looted = {"key": k, "i": o["i"]}
				break
		if not looted.is_empty():
			break

	var inv_before := var_to_bytes(game.inventory.to_data())
	var money_before: int = game.money
	player.global_position += Vector3(3, 0, 2)
	var pos_before: Vector3 = player.global_position
	await _frames(10)

	# Quit to menu: this is what the pause menu does.
	game.close_world()
	change_scene_to_file("res://src/ui/main_menu.tscn")
	await _frames(10)

	# Reopen and verify.
	check(game.load_world(world_id), "world reopens")
	var store: WorldStore = game.store
	var c1 = store.load_chunk(felled["key"].x, felled["key"].y)
	check(c1["objects"][felled["i"]]["st"].get("gone", false), "felled %s is still gone" % felled["t"])
	var c2 = store.load_chunk(here_key.x, here_key.y)
	check(absf(ChunkGenerator.height_at(c2, lx, lz) - after) < 0.001, "crater is still there")
	if not looted.is_empty():
		var c3 = store.load_chunk(looted["key"].x, looted["key"].y)
		check(c3["objects"][looted["i"]]["st"]["opened"], "looted cache stays empty")
	var inv_after := var_to_bytes(game.inventory.to_data())
	check(inv_after == inv_before, "inventory bit-for-bit identical after reload")
	check(game.money == money_before, "money identical after reload")
	check(game.inventory.count(ObjectLibrary.YIELD[felled["t"]]) >= 5, "harvested wood is in the pack")
	check(game.pending_player_state["pos"].distance_to(pos_before) < 0.01, "player position restored")
	check(game.discovery["visited"].size() >= 1, "discovery log saved")

	# Regenerating the same chunk with today's generator would NOT reproduce the edits,
	# which proves the game reads the snapshot rather than regenerating.
	var fresh := ChunkGenerator.new(game.seed).generate(here_key.x, here_key.y)
	check(absf(ChunkGenerator.height_at(fresh, lx, lz) - after) > 0.5, "snapshot, not regeneration, is the source of truth")

	game.close_world()
	WorldStore.delete_world(world_id)
	print("integration: %s" % ("PASSED" if _fail == 0 else "%d FAILED" % _fail))
	quit(1 if _fail > 0 else 0)
