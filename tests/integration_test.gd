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

	# Loot the nearest cache by walking up to it, as a player would: the floating prompt
	# should pick it and Interact should open it.
	var looted := {}
	var best_c: ChunkNode = null
	var best_o := {}
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "cache" and not o["st"].get("opened", false):
				if best_c == null or (c.position + o["p"]).distance_to(player.global_position) < (best_c.position + best_o["p"]).distance_to(player.global_position):
					best_c = c
					best_o = o
	if best_c != null:
		var c := best_c
		var o := best_o
		var cw: Vector3 = c.position + o["p"]
		var stand := cw + Vector3(2.2, 0, 0)
		stand.y = ChunkGenerator.height_at(c.data, o["p"].x + 2.2, o["p"].z) + 0.1
		player.set_state({"pos": stand, "yaw": atan2(2.2, 0.0), "pitch": -0.35, "slot": 0})
		for i in 300:
			await _frames(1)
			if streamer.is_ready_at(stand):
				break
		player.global_position = stand
		await _frames(20)
		check(player.focus.get("kind", "") == "cache" and player.focus.get("i", -1) == o["i"], "walking up to a chest offers to open it (%s)" % player.focus.get("verb", "nothing"))
		player.interact()
		check(o["st"].get("opened", false), "interact opens the chest in focus")
		looted = {"key": c.key, "i": o["i"]}
	check(not looted.is_empty(), "found a chest to loot")

	# Build: aim at the ground and place a foundation through the real builder, then a
	# workbench next to it, and take a wall down for a refund.
	game.give(ItemDB.make("foundation", 3, 1.0, game.origin_here("crafted", -1, here_key)))
	var fi := -1
	for i in Inventory.SIZE:
		var sl = game.inventory.get_slot(i)
		if sl != null and sl["type"] == "foundation":
			fi = i
	game.inventory.swap(fi, 5)
	player.select(5)
	player.set_state({"pos": player.global_position, "yaw": 0.3, "pitch": -0.75, "slot": 5})
	await _frames(4)
	var built_before := 0
	for o in here.data["objects"]:
		if BuildCatalog.is_built(o["t"]):
			built_before += 1
	check(player.builder.active(), "holding a foundation starts building")
	check(player.builder.place(), "foundation placed where the player looks")
	check(game.inventory.count("foundation") == 2, "placing uses one piece")
	await _frames(2)
	var placed := {}
	for k in streamer.chunks:
		for o in streamer.chunks[k].data["objects"]:
			if o["t"] == "b:foundation":
				placed = {"key": k, "i": o["i"], "p": o["p"]}
	check(not placed.is_empty(), "foundation is a chunk object")
	var pc: ChunkNode = streamer.get_chunk(placed["key"])
	var fwp: Vector3 = pc.position + placed["p"]
	check(is_equal_approx(fmod(absf(fwp.x), 2.0), 1.0) and is_equal_approx(fmod(absf(fwp.z), 2.0), 1.0), "foundation sits on the 2 m grid (%s)" % fwp)
	var wb := pc.add_built("workbench", placed["p"] + Vector3(3, 0, 0), 0.0, {"by": "you", "day": 0.0})
	check(BuildCatalog.stations_near(streamer, fwp).has("workbench"), "workbench counts as a nearby station")
	var wall := pc.add_built("wall_stone", placed["p"] + Vector3(0, 0, 1), 0.0, {"by": "you", "day": 0.0})
	player.damage_object(pc, wall, 1000.0, 1.0)
	check(wall["st"].get("gone", false) and game.inventory.count("wall_stone") == 1, "taking a wall down returns it")
	var fence := pc.add_built("fence", placed["p"] + Vector3(-3, 0, 0), 0.0, {"by": "you", "day": 0.0})
	check(player.deconstruct(pc, fence) and fence["st"].get("gone", false) and game.inventory.count("fence") == 1, "deconstructing your own piece returns it")
	var bwall := {"key": placed["key"], "i": wall["i"]}
	var bwb := {"key": placed["key"], "i": wb["i"]}

	# Console cheats.
	var con: DevConsole = world.console
	con.run("god")
	game.set_health(10.0)
	check(game.health == 100.0, "god mode blocks damage")
	con.run("god")
	check(con.run("speed 3") == "Speed x3.0" and player.speed_mult == 3.0, "speed multiplier")
	con.run("speed 1")
	con.run("fly")
	var y0: float = player.global_position.y
	Input.action_press("jump")
	await _frames(30)
	Input.action_release("jump")
	check(player.global_position.y > y0 + 1.0, "fly mode rises (%.1f -> %.1f)" % [y0, player.global_position.y])
	con.run("fly")
	check(not player.fly and not player._shape.disabled, "fly off restores collision")
	check(con.run("give planks 25").begins_with("Gave 25"), "give command")
	await _frames(60)

	# Levelling: experience from the console, a point spent, all saved below.
	con.run("level 3")
	check(game.stats.level == 3 and game.stats.points == 6, "levelled to 3 with points (%d, %d)" % [game.stats.level, game.stats.points])
	check(game.spend_point("end") and game.max_health() == 110.0, "endurance point raises max health")
	var stamina0: float = game.stamina
	check(game.use_stamina(10.0) and game.stamina < stamina0, "actions spend stamina")

	# Third person: the camera swings out behind the shoulder, the body shows.
	player.toggle_view()
	await _frames(10)
	check(player.third_person and player.camera.global_position.distance_to(player.head.global_position) > 0.5 and not player.viewmodel.visible, "third person camera sits behind you")
	player.toggle_view()
	await _frames(5)
	check(not player.third_person and player.camera.global_position.distance_to(player.head.global_position) < 0.05, "back to first person")

	# Dying: health hits zero, a pause, then you wake at the spawn with your pack.
	var count_before: int = game.inventory.count("planks")
	game.set_health(-5.0, "test")
	check(game.dead and player.ui_open, "zero health kills you")
	await create_timer(4.6).timeout
	await _frames(30)
	check(not game.dead and game.health == game.max_health() and not player.ui_open, "you get back up with full health")
	check(game.inventory.count("planks") == count_before, "dying keeps your pack")
	await _frames(60)

	var inv_before := var_to_bytes(game.inventory.to_data())
	var money_before: int = game.money
	player.global_position += Vector3(3, 0, 2)
	await _frames(10)
	# Where the player ends up after physics settles (they may be standing on what was built).
	var pos_before: Vector3 = player.global_position

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
	check(game.stats.level == 3 and game.stats.attrs["end"] == 1 and game.max_health() == 110.0, "level and attributes restored")
	check(game.inventory.count(ObjectLibrary.YIELD[felled["t"]]) >= 5, "harvested wood is in the pack")
	check(game.pending_player_state["pos"].distance_to(pos_before) < 0.01, "player position restored")
	check(game.discovery["visited"].size() >= 1, "discovery log saved")
	var c4 = store.load_chunk(placed["key"].x, placed["key"].y)
	check(c4["objects"][placed["i"]]["t"] == "b:foundation" and c4["objects"][placed["i"]]["p"].distance_to(placed["p"]) < 0.001, "built foundation saved in place")
	check(c4["objects"][bwb["i"]]["t"] == "b:workbench", "workbench saved")
	check(c4["objects"][bwall["i"]]["st"].get("gone", false), "taken-down wall stays gone")

	# Regenerating the same chunk with today's generator would NOT reproduce the edits,
	# which proves the game reads the snapshot rather than regenerating.
	var fresh := ChunkGenerator.new(game.seed).generate(here_key.x, here_key.y)
	check(absf(ChunkGenerator.height_at(fresh, lx, lz) - after) > 0.5, "snapshot, not regeneration, is the source of truth")

	game.close_world()
	WorldStore.delete_world(world_id)
	print("integration: %s" % ("PASSED" if _fail == 0 else "%d FAILED" % _fail))
	quit(1 if _fail > 0 else 0)
