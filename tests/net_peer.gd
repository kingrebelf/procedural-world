extends SceneTree
## The second player in tests/net_test.gd: joins as Bob, fetches one chunk, says
## "ready", and says "got 4242" when the other player's edit to it is pushed to him.

func _initialize() -> void:
	_run.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d

func _run() -> void:
	var net = root.get_node("/root/Net")
	var game = root.get_node("/root/Game")
	var ok := [false]
	net.joined.connect(func(): ok[0] = true)
	net.join_failed.connect(func(r): printerr("peer: join failed: ", r); quit(2))
	net.join("127.0.0.1", int(_arg("port", "24731")), "Bob", "sesame")
	for i in 1800:
		if ok[0]:
			break
		await process_frame
	if not ok[0]:
		quit(3)
		return
	var cx := int(_arg("cx", "0"))
	var cz := int(_arg("cz", "0"))
	var store = game.store
	# Stand there (the server pushes edits to players near them) and fetch the chunk.
	var pos := Vector3((cx + 0.5) * ChunkGenerator.SIZE, 50.0, (cz + 0.5) * ChunkGenerator.SIZE)
	net.s_state.rpc_id(1, 0, pos, 0.0, 0.0, "idle", 1.0, 0)
	net.s_chunk_req.rpc_id(1, 0, cx, cz)
	for i in 1800:
		if store.load_chunk(cx, cz) != null:
			break
		await process_frame
	net.say("ready")
	for i in 3600:
		net.s_state.rpc_id(1, 0, pos, float(i) * 0.01, 0.0, "idle", 1.0, 0)
		var c = store.load_chunk(cx, cz)
		if c is Dictionary and int(c.get("net_test", 0)) == 4242:
			net.say("got 4242")
			for j in 30:
				await process_frame
			quit(0)
			return
		await process_frame
	quit(4)
