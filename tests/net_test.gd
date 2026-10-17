extends SceneTree
## Dedicated server end to end:
##   godot --headless --path . --script res://tests/net_test.gd
## Starts a real server process, joins it, plays in the world scene through the network,
## edits a chunk, checks that the server saved it and pushed it to a second player (a
## separate process, tests/net_peer.gd), and that your save comes back when you rejoin.

const PORT := 24731
var _fail := 0
var _data := ""
var _server := -1
var _peer := -1

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

func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
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
	_server = OS.create_process(OS.get_executable_path(), _godot_args(["--", "--server", "--port=%d" % PORT,
		"--data=%s" % _data, "--config=%s" % _data.path_join("server.cfg"), "--world=nt", "--seed=1234",
		"--password=sesame", "--admin-password=boss", "--name=Test Server", "--no-console", "--set", "time=day"]))
	check(_server > 0, "server process started")
	# Wait for the server to write its world.
	var world_dat := _data.path_join("worlds/nt/world.dat")
	await _until(func(): return FileAccess.file_exists(world_dat), 1800)
	await _frames(30)
	check(FileAccess.file_exists(_data.path_join("server.cfg")), "server wrote its server.cfg")

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

	# A second player joins from another process and stands near this chunk.
	_peer = OS.create_process(OS.get_executable_path(), _godot_args(["--script", "res://tests/net_peer.gd", "--",
		"--port=%d" % PORT, "--cx=%d" % k0.x, "--cz=%d" % k0.y, "--identity=netpeer"]))
	check(await _until(func(): return net.peers.size() == 1, 2400), "the second player shows up in the roster")
	var other: Dictionary = net.peers.values()[0] if net.peers.size() > 0 else {}
	check(String(other.get("name", "")) == "Bob", "named Bob (%s)" % other.get("name", ""))
	check(await _until(func(): return world.get_node("OtherPlayers").get_child_count() == 1, 1200), "and is drawn in the world")
	# Bob says he's ready once he has this chunk; then we edit it.
	var said := [""]
	net.chat.connect(func(from, text, _k): if from == "Bob": said[0] = text)
	check(await _until(func(): return said[0] == "ready", 2400), "Bob chats (%s)" % said[0])
	here.data["net_test"] = 4242
	game.mark_chunk_dirty(here.data)
	game.flush_chunks()
	check(await _until(func(): return said[0] == "got 4242", 1800), "Bob saw the edit pushed to him (%s)" % said[0])
	var path := _data.path_join("worlds/nt/chunks/%d_%d.chunk" % [k0.x, k0.y])
	await _until(func(): return _saved_marker(path), 600)
	check(_saved_marker(path), "the server saved the edit to its world")

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
	var c = WorldStore.read_var(path, true)
	return c is Dictionary and int(c.get("net_test", 0)) == 4242
