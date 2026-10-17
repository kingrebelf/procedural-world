extends SceneTree
## Dedicated server end to end:
##   godot --headless --path . --script res://tests/net_test.gd
## Starts a real server process, joins it, plays in the world scene through the network,
## edits a chunk, checks that the server saved it and pushed it to a second player (a
## separate process, tests/net_peer.gd), that his edit from an older copy is merged with
## yours instead of undoing it, that one of you runs the animals and the other sees them,
## PvP (on, then off), alliances, the server lending its villager AI, and that your save comes back
## when you rejoin.

const PORT := 24731
const AI_PORT := 24732
var _fail := 0
var _data := ""
var _server := -1
var _peer := -1
var _heard: Array = [] ## what Bob said, in order

## The last thing Bob said starting with `prefix`, or "".
func _said(prefix: String) -> String:
	for i in range(_heard.size() - 1, -1, -1):
		if String(_heard[i]).begins_with(prefix):
			return _heard[i]
	return ""

func check(c: bool, m: String) -> void:
	if c:
		print("  ok   ", m)
	else:
		_fail += 1
		printerr("  FAIL ", m)

func _initialize() -> void:
	_run.call_deferred()
	# A script error inside the awaits would otherwise leave the test hanging.
	create_timer(600.0, true).timeout.connect(func():
		printerr("net test: timed out")
		if _server > 0:
			OS.kill(_server)
		if _peer > 0 and OS.is_process_running(_peer):
			OS.kill(_peer)
		quit(1))

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Waits until `cond` holds: for `max_frames` frames, and never less than that many
## frames take at 60 fps (a headless frame can take a millisecond, and frames alone ran
## out before the server had sent the land).
func _until(cond: Callable, max_frames: int) -> bool:
	var end := Time.get_ticks_msec() + max_frames * 1000 / 60
	var i := 0
	while i < max_frames or Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
		i += 1
	return cond.call()

func _godot_args(extra: Array) -> PackedStringArray:
	var a := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://")])
	a.append_array(extra)
	return a

func _join(net, nm: String, pw: String) -> String:
	var result := [""]
	var on_fail := func(r): result[0] = "fail:" + r
	var on_join := func(): result[0] = "ok"
	net.join_failed.connect(on_fail)
	net.joined.connect(on_join)
	net.join("127.0.0.1", PORT, nm, pw)
	await _until(func(): return result[0] != "", 900)
	net.join_failed.disconnect(on_fail)
	net.joined.disconnect(on_join)
	return result[0]

func _run() -> void:
	var net = root.get_node("/root/Net")
	var game = root.get_node("/root/Game")
	_data = OS.get_user_data_dir().path_join("net_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_data)
	# The server's villagers think with a model on this machine (a stand-in).
	var fake_ai = load("res://tests/fake_ai_server.gd").new()
	root.add_child(fake_ai)
	check(fake_ai.start(AI_PORT), "stand-in model listening")
	var cf := ConfigFile.new()
	cf.set_value("ai", "provider", "custom")
	cf.set_value("ai", "base_url", "http://127.0.0.1:%d/v1" % AI_PORT)
	cf.set_value("ai", "model", "test")
	cf.save(_data.path_join("server.cfg"))
	var ai_node = root.get_node("/root/AI")
	ai_node.cfg["provider"] = "off" # this game has no model of its own
	_server = OS.create_process(OS.get_executable_path(), _godot_args(["--", "--server", "--port=%d" % PORT,
		"--data=%s" % _data, "--config=%s" % _data.path_join("server.cfg"), "--world=nt", "--seed=1234",
		"--password=sesame", "--admin-password=boss", "--name=Test Server", "--no-console", "--set", "time=day"]))
	check(_server > 0, "server process started")
	# Wait for the server to write its world.
	var world_dat := _data.path_join("worlds/nt/world.dat")
	await _until(func(): return FileAccess.file_exists(world_dat), 1800)
	await _frames(30)
	check(FileAccess.file_exists(_data.path_join("server.cfg")), "server wrote its server.cfg")

	# The Join Server screen asks servers how they are, and finds ones on your network.
	var q = load("res://src/net/server_query.gd").new() # by path: Net is not up yet when this compiles
	root.add_child(q)
	var answers := {}
	q.answered.connect(func(k, info): answers[k] = info)
	q.ask("127.0.0.1", PORT)
	q.scan("127.0.0.1")
	q.ask("127.0.0.1", PORT + 50)
	var t_ask := Time.get_ticks_msec()
	await _until(func(): return answers.size() >= 3 or Time.get_ticks_msec() - t_ask > 8000, 100000)
	var a1: Dictionary = answers.get("127.0.0.1:%d" % PORT, {})
	check(String(a1.get("name", "")) == "Test Server" and bool(a1.get("password", false)) and a1.has("ping"), "a server answers with its name, password flag and ping (%s)" % a1)
	var lan: Dictionary = answers.get("lan:127.0.0.1:%d" % PORT, {})
	check(String(lan.get("name", "")) == "Test Server" and int(lan.get("port", 0)) == PORT, "and on the local network (%s)" % lan)
	var sq = load("res://src/net/server_query.gd") # by path, as above
	check(sq.is_local("192.168.1.20") and sq.is_local("10.0.0.7") and sq.is_local("172.20.1.1") and sq.is_local("::1")
		and not sq.is_local("8.8.8.8") and not sq.is_local("172.32.0.1") and not sq.is_local("2001:db8::1"),
		"LAN discovery answers only this machine and private networks")
	check(answers.get("127.0.0.1:%d" % (PORT + 50), {}).has("error"), "an address with no server says so")
	q.queue_free()

	# Identity, password and names.
	root.get_node("/root/Net") # keep autoload path in use
	_identity("alice")
	var r: String = await _join(net, "Alice", "")
	check(r.begins_with("fail:") and r.contains("password"), "no password is refused (%s)" % r)
	r = await _join(net, "Alice", "wrong")
	check(r.begins_with("fail:") and r.contains("Wrong password"), "a wrong password is refused (%s)" % r)
	r = await _join(net, "Alice", "sesame")
	check(r == "ok", "the right password lets you in (%s)" % r)
	check(net.is_client() and net.my_pid != "", "you get a player id (%s)" % net.my_pid)
	check(game.store is RemoteStore, "the world comes from the server")
	check(int(game.store.meta["seed"]) == 1234, "with the server's seed")
	check(String(net.info.get("name", "")) == "Test Server", "and its name (%s)" % net.info.get("name", ""))
	check(String(net.option("time")) == "day" and is_equal_approx(game.time_lock, 0.5), "always-day locks the clock")
	check(game.money == 50 and game.inventory.count("pickaxe_iron") == 1, "a new player gets the starter pack")

	# Server rates: loot and experience.
	var opts: Dictionary = net.options
	net.options = {"loot_mult": 0.0}
	var st0: int = game.inventory.count("stone")
	check(game.give_loot({"type": "stone", "qty": 3}) and game.inventory.count("stone") == st0, "a loot rate of 0 gives nothing")
	net.options = {"loot_mult": 2.0}
	game.give_loot({"type": "stone", "qty": 3})
	check(game.inventory.count("stone") == st0 + 6, "a loot rate of 2 doubles a harvest")
	net.options = {"xp_mult": 3.0}
	var xp0: float = game.stats.xp
	var lv0: int = game.stats.level
	game.add_xp(1.0)
	check(game.stats.level > lv0 or is_equal_approx(game.stats.xp - xp0, 3.0), "an experience rate of 3 triples experience")
	net.options = opts

	# The server's model, for a player with none.
	check(bool(net.info.get("ai", false)) and ai_node.enabled(), "the server offers its villagers' model")
	var said_ai: Dictionary = await ai_node.chat_json("You are a test.", [{"role": "user", "content": "Hello?"}])
	check(said_ai["ok"] and String(said_ai["data"].get("say", "")) == "hello from the server" and fake_ai.hits == 1, "and dialogue goes through it (%s)" % said_ai)

	# Play through the network in the real world scene.
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	var world = current_scene
	var player = world.player
	check(await _until(func(): return not player.frozen, 2400), "spawned on ground streamed from the server")
	var streamer = world.streamer
	check(await _until(func(): return streamer.chunks.size() >= 9, 2400), "chunks streamed from the server (%d)" % streamer.chunks.size())
	check(world.get_node_or_null("OtherPlayers") != null, "other players are drawn")
	# The server's chunk is the same land this client would have generated.
	var k0 := Vector2i(int(floor(player.global_position.x / 64.0)), int(floor(player.global_position.z / 64.0)))
	var here = streamer.get_chunk(k0)
	var local := ChunkGenerator.new(game.seed, game.store.has_rivers()).generate(k0.x, k0.y)
	var hs: PackedFloat32Array = here.data["heights"]
	var lh: PackedFloat32Array = local["heights"]
	check(hs.size() == lh.size() and absf(hs[hs.size() / 2] - lh[lh.size() / 2]) < 0.001, "server land matches the seed")

	# A second player joins from another process and stands near this chunk. (Listen to
	# him from the start: he can say he's ready before he is drawn here.)
	net.chat.connect(func(from, text, _k): if from == "Bob": _heard.append(text))
	_peer = OS.create_process(OS.get_executable_path(), _godot_args(["--script", "res://tests/net_peer.gd", "--",
		"--port=%d" % PORT, "--cx=%d" % k0.x, "--cz=%d" % k0.y, "--identity=netpeer"]))
	check(await _until(func(): return net.peers.size() == 1, 2400), "the second player shows up in the roster")
	var other: Dictionary = net.peers.values()[0] if net.peers.size() > 0 else {}
	check(String(other.get("name", "")) == "Bob", "named Bob (%s)" % other.get("name", ""))
	check(await _until(func(): return world.get_node("OtherPlayers").get_child_count() == 1, 1200), "and is drawn in the world")
	# Bob says he's ready once he has this chunk; then we edit it.
	check(await _until(func(): return _heard.has("ready"), 2400), "Bob chats (%s)" % str(_heard))
	here.data["net_test"] = 4242
	game.mark_chunk_dirty(here.data)
	game.flush_chunks()
	check(await _until(func(): return _heard.has("got 4242"), 1800), "Bob saw the edit pushed to him (%s)" % str(_heard))
	var path := _data.path_join("worlds/nt/chunks/%d_%d.chunk" % [k0.x, k0.y])
	await _until(func(): return _saved_marker(path), 600)
	check(_saved_marker(path), "the server saved the edit to its world")
	# Bob then saves an edit made from the copy he had before yours: merged, not lost.
	await _until(func(): return _saved_key(path, "bob_mark") == 7, 900)
	check(_saved_marker(path) and _saved_key(path, "bob_mark") == 7, "two players' edits to one chunk both stay")
	check(await _until(func(): return int(streamer.get_chunk(k0).data.get("bob_mark", 0)) == 7 and int(streamer.get_chunk(k0).data.get("net_test", 0)) == 4242, 900),
		"and the merged chunk reaches you")

	# Animals: you loaded them first, so you run them; Bob sees them move.
	check(net.holds("f", k0), "the first player near runs the animals")
	check(await _until(func(): return net.shared("f", k0), 900), "and knows someone else sees them")
	var fauna = world.fauna
	var mine := 0
	for k in fauna._herds:
		if absi(k.x - k0.x) <= 2 and absi(k.y - k0.y) <= 2:
			mine += fauna._herds[k].size()
	if mine > 0:
		check(await _until(func(): return _said("mobs") != "", 1200), "Bob sees the animals you run (%s, %d here)" % [str(_heard), mine])
		check(await _until(func(): return _said("hit ") != "", 600), "Bob hits one (%s)" % str(_heard))
		var hid := _said("hit ").substr(4)
		var hurt_one := func():
			for k in fauna._herds:
				for c in fauna._herds[k]:
					if is_instance_valid(c) and c.id == hid:
						return c.hp < float(c.p["hp"])
			return false
		check(await _until(hurt_one, 600), "and the animal you run feels his blow")
	else:
		print("  (no animals near this spot; skipped the animal checks)")

	# PvP: on by default.
	var bob_peer: int = net.peers.keys()[0] if net.peers.size() > 0 else 0
	net.hurt_player(bob_peer, 10.0, "", true)
	check(await _until(func(): return _said("hurt") != "", 600), "with PvP on, your blow hurts Bob (%s)" % str(_heard))

	# Alliances: found one, invite Bob; allies can't hurt each other and share a chat.
	var ally_lines: Array = []
	net.chat.connect(func(f, text, k): if k == "ally": ally_lines.append([f, text]))
	net.ally("create", "Test Alliance")
	check(await _until(func(): return net.alliance.get("name", "") == "Test Alliance", 600), "you found an alliance (%s)" % net.alliance)
	var bob_pid: String = net.peers[bob_peer]["pid"] if net.peers.has(bob_peer) else ""
	net.ally("invite", bob_pid)
	check(await _until(func(): return _said("ally") == "ally Test Alliance", 900), "Bob accepts your invitation (%s)" % str(_heard))
	check(await _until(func(): return net.allied(bob_pid), 600) and not net.may_hurt(bob_pid), "and he is your ally")
	check(await _until(func(): return net.allies_where().any(func(e): return e[0] == bob_pid), 600), "you see where your ally is")
	var hurts := _heard.filter(func(h): return String(h).begins_with("hurt")).size()
	net.hurt_player(bob_peer, 10.0, "", true)
	await _frames(90)
	check(_heard.filter(func(h): return String(h).begins_with("hurt")).size() == hurts, "allies can't hurt each other, even with PvP on")
	net.ally("chat", "hold the bridge")
	check(await _until(func(): return ally_lines.any(func(l): return l[0] == "Alice" and l[1] == "hold the bridge"), 600), "alliance chat")
	check(FileAccess.file_exists(_data.path_join("worlds/nt/alliances.dat")), "the server keeps alliances")
	net.ally("leave")
	check(await _until(func(): return not net.allied(bob_pid) and net.alliance.is_empty(), 600), "you can leave your alliance")

	# Chat commands and admin.
	var replies: Array = []
	net.chat.connect(func(_f, text, k): if k == "admin": replies.append(text))
	net.admin("set pvp off")
	await _until(func(): return replies.size() > 0, 600)
	check(replies.size() > 0 and String(replies[-1]).contains("Only admins"), "non-admins can't change options")
	net.admin("admin boss")
	await _until(func(): return net.is_admin, 600)
	check(net.is_admin, "the admin password works")
	net.admin("set pvp off")
	check(await _until(func(): return net.option("pvp") == false, 600), "an admin's option change reaches players")
	var before := _heard.size()
	net.hurt_player(bob_peer, 10.0, "", true)
	await _frames(90)
	check(_heard.size() == before, "with PvP off, it doesn't (%s)" % str(_heard))

	# A town's people saved from an older copy are merged too.
	var site := _nearest_site(world.npcs.gen, player.global_position)
	check(await _until(func(): return game.store.prefetch_settlement(site), 1800), "a town's people arrive")
	var sx: int = site["sx"]
	var sz: int = site["sz"]
	var old: Dictionary = game.store.load_settlement(sx, sz).duplicate(true)
	var live: Dictionary = game.store.load_settlement(sx, sz)
	live["test_a"] = 1
	game.store.save_settlement(live)
	await _until(func(): return int(live.get("_rev", 0)) != int(old.get("_rev", 0)), 600)
	old["test_b"] = 2 # as if someone else saved from the copy before yours
	net.rs_send_town(0, old)
	check(await _until(func(): return int(game.store.load_settlement(sx, sz).get("test_b", 0)) == 2, 900) and int(game.store.load_settlement(sx, sz).get("test_a", 0)) == 1,
		"a town saved by two players keeps both")
	var town_file := _data.path_join("worlds/nt/people/%d_%d.dat" % [sx, sz])
	var tf = WorldStore.read_var(town_file, true)
	check(tf is Dictionary and int(tf.get("test_a", 0)) == 1 and int(tf.get("test_b", 0)) == 2, "on the server too")
	net.say("bye")

	# Your save lives on the server.
	game.add_money(727)
	var pos: Vector3 = player.global_position
	net.leave("")
	await _until(func(): return net._draining.is_empty(), 600)
	check(not net.online() and game.store == null and net._draining.is_empty(), "leaving closes the world and says goodbye")
	r = await _join(net, "Alice", "sesame")
	check(r == "ok", "rejoin (%s)" % r)
	check(game.money == 777, "money kept on the server (%d)" % game.money)
	var back = game.store.load_player()
	check(back is Dictionary and back.get("pos") is Vector3 and (back["pos"] as Vector3).distance_to(pos) < 1.0, "position kept on the server")
	net.leave("")
	await _frames(10)

	# Someone else can't take your name.
	_identity("mallory")
	r = await _join(net, "Alice", "sesame")
	check(r.begins_with("fail:") and r.contains("already goes by"), "someone else can't use your name (%s)" % r)

	OS.kill(_server)
	if _peer > 0 and OS.is_process_running(_peer):
		OS.kill(_peer)
	print("\nnet test: %s" % ("all passed" if _fail == 0 else "%d FAILED" % _fail))
	quit(1 if _fail > 0 else 0)

func _identity(who: String) -> void:
	Identity.override = "user://test_identity_%s.cfg" % who

func _saved_marker(path: String) -> bool:
	return _saved_key(path, "net_test") == 4242

func _saved_key(path: String, k: String) -> int:
	var c = WorldStore.read_var(path, true)
	return int(c.get(k, 0)) if c is Dictionary else 0

func _nearest_site(gen: ChunkGenerator, at: Vector3) -> Dictionary:
	for r in [400.0, 1200.0, 3000.0, 8000.0]:
		var best := {}
		for site in gen.settlements_near(at.x - r, at.z - r, at.x + r, at.z + r):
			if best.is_empty() or (site["center"] as Vector2).distance_to(Vector2(at.x, at.z)) < (best["center"] as Vector2).distance_to(Vector2(at.x, at.z)):
				best = site
		if not best.is_empty():
			return best
	return {}
