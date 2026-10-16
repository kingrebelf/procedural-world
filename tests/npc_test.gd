extends SceneTree
## End-to-end NPC check through the real game scene:
##   godot --headless --path . --script res://tests/npc_test.gd
## Walks into a settlement, talks to someone, angers someone else, kills a third,
## quits, reopens and checks that every person remembers exactly what happened.
## With --llm=<base_url> it also routes the conversation through that server
## (tests/mock_llm.py provides a fake OpenAI- and Anthropic-compatible server).

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
	var ai = root.get_node("/root/AI")
	var llm := ""
	var fmt := "openai"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--llm="):
			llm = a.substr(6)
		if a.begins_with("--format="):
			fmt = a.substr(9)
	var saved_cfg: Dictionary = ai.cfg.duplicate()
	if llm != "":
		ai.cfg["provider"] = "custom"
		ai.cfg["format"] = fmt
		ai.cfg["base_url"] = llm
		ai.cfg["model"] = "mock"
		ai.cfg["api_key"] = "test-key"
		ai.cfg["think_interval"] = 5.0
		ai.cfg["max_rpm"] = 60
	else:
		ai.cfg["provider"] = "off"
		ai.cfg["format"] = ""

	game.new_world("NPC Test", "777")
	var world_id: String = game.store.root.get_file()
	# Find the nearest settlement and spawn beside its square.
	var gen := ChunkGenerator.new(game.seed)
	var site := {}
	for ring in 12:
		var found := gen.settlements_near(-ring * 256.0, -ring * 256.0, ring * 256.0, ring * 256.0)
		if not found.is_empty():
			site = found[0]
			break
	check(not site.is_empty(), "found a settlement")
	var c: Vector2 = site["center"]
	game.day = 0.5 # Midday: everyone is up and about.
	game.pending_player_state = {"pos": Vector3(c.x + 6, gen.field.height(c.x + 6, c.y) + 2.0, c.y), "yaw": 0.0, "pitch": 0.0, "slot": 0}
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	var world = current_scene
	var player = world.player
	for i in 900:
		await process_frame
		if not player.frozen:
			break
	await _frames(120)
	var mgr: NPCManager = world.npcs
	var nodes: Array = mgr.all_nodes()
	check(nodes.size() >= 4, "people spawned in %s (%d)" % [site.get("sx", 0), nodes.size()])
	var sid := NPCGen.settlement_id(site["sx"], site["sz"])
	check(FileAccess.file_exists(game.store.settlement_path(site["sx"], site["sz"])), "settlement saved on first sight")
	var trader: NPC = null
	var others: Array = []
	for n in nodes:
		if n.rec["job"] == "trader":
			trader = n
		else:
			others.append(n)
	check(trader != null, "the trader is a person")
	check(others.size() >= 3, "residents exist")
	if trader == null or others.size() < 3:
		_finish(game, world_id, ai, saved_cfg)
		return
	# Everyone moves under the decision engine.
	var p0: Vector3 = others[0].global_position
	await _frames(240)
	var moved := false
	for n in others:
		if n.action != "idle":
			moved = true
	check(moved, "residents are doing things (%s)" % ", ".join(others.map(func(n): return n.action)))

	# Talk to the first resident.
	var talker: NPC = others[0]
	var dlg: DialogueUI = world.dialogue
	player.global_position = talker.global_position + Vector3(1.5, 0.5, 0)
	dlg.open_with(talker)
	check(dlg.is_open() and talker.talking, "conversation opened")
	await dlg._send("Who are you?")
	for i in 600:
		if not dlg._busy:
			break
		await process_frame
	var log_text: String = dlg._log.get_parsed_text()
	check(log_text.contains("You: Who are you?"), "player line shown")
	check(log_text.count(":") >= 3, "npc replied: " + log_text.replace("\n", " | ").right(140))
	if llm != "":
		check(log_text.contains("mock"), "reply came from the model server")
		check(talker.rec["mem"].any(func(m): return String(m).contains("mock memory")), "model's 'remember' stored in memory")
	var talker_id: String = talker.rec["id"]
	var talker_met: int = talker.rec["met"]
	dlg.close_talk()
	check(not talker.talking, "conversation closed")

	# Ask the trader to trade: opens the trade window.
	player.global_position = trader.global_position + Vector3(1.5, 0.5, 0)
	dlg.open_with(trader)
	dlg._send("Let's trade.")
	for i in 600:
		if not dlg._busy:
			break
		await process_frame
	await _frames(2)
	if llm == "":
		check(world.menus._mode == "trade", "trader opened the trade window")
	world.menus.close()
	if dlg.is_open():
		dlg.close_talk()

	# Hit a resident: they and the neighbours remember.
	var victim: NPC = others[1]
	var victim_id: String = victim.rec["id"]
	mgr.player_hit(victim, 10.0)
	check(int(victim.rec["rel"]) <= -35, "victim turned hostile (%d)" % victim.rec["rel"])
	check(victim.rec["mem"].any(func(m): return String(m).contains("attacked")), "victim remembers the attack")
	var settlement: Dictionary = victim.settlement
	check(settlement["rumors"].any(func(m): return String(m).contains("attacked")), "the settlement gossips about it")

	# Kill another.
	var dead: NPC = others[2]
	var dead_id: String = dead.rec["id"]
	mgr.player_hit(dead, 500.0)
	await _frames(2)
	check(not is_instance_valid(dead) or dead.is_queued_for_deletion(), "killed NPC removed")

	await _frames(30)
	game.close_world()
	change_scene_to_file("res://src/ui/main_menu.tscn")
	await _frames(10)

	check(game.load_world(world_id), "world reopens")
	var data = game.store.load_settlement(site["sx"], site["sz"])
	check(data is Dictionary, "settlement file loads")
	var by_id := {}
	for p in data["npcs"]:
		by_id[p["id"]] = p
	check(int(by_id[talker_id]["met"]) == talker_met, "conversation count persisted")
	check(by_id[talker_id]["mem"].size() >= 1, "talker's memories persisted")
	check(int(by_id[victim_id]["rel"]) <= -35, "victim still hostile after reload")
	check(by_id[dead_id]["dead"], "the dead stay dead")
	var regen := NPCGen.generate(game.seed, gen, site, gen.settlement_layout(site))
	check(by_id.size() == regen["npcs"].size(), "same people as first generated")
	_finish(game, world_id, ai, saved_cfg)

func _finish(game, world_id: String, ai, saved_cfg: Dictionary) -> void:
	game.close_world()
	WorldStore.delete_world(world_id)
	ai.cfg = saved_cfg
	print("npc: %s" % ("PASSED" if _fail == 0 else "%d FAILED" % _fail))
	quit(1 if _fail > 0 else 0)
