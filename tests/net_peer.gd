extends SceneTree
## The second player in tests/net_test.gd: joins as Bob and stands in one chunk.
##   - says "ready" once he has the chunk, and "got 4242" when the other player's edit to
##     it is pushed to him; then saves an edit of his own made from his older copy (the
##     server must merge it, not let it undo the other player's);
##   - asks to see the animals around him and says "mobs N" once someone else runs them,
##     then hits one ("hit <id>") so whoever runs it feels it;
##   - says "hurt <health>" whenever another player hurts him;
##   - accepts an alliance invitation and says "ally <name>";
##   - leaves when the other player says "bye".

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
	var bye := [false]
	net.chat.connect(func(from, text, _k): if text == "bye": bye[0] = true)
	# Accepts any alliance invitation, and says which alliance he is in.
	net.alliance_changed.connect(func():
		if net.alliance.is_empty() and not net.ally_invites.is_empty():
			net.ally("accept", String(net.ally_invites[0]["id"]))
		elif not net.alliance.is_empty():
			net.say("ally %s" % net.alliance["name"]))
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
	var stale: Dictionary = store.load_chunk(cx, cz).duplicate(true)
	# The animals around: someone else already runs them.
	var adds: Array = []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			adds.append([Vector2i(cx + dx, cz + dz), Vector2((cx + dx + 0.5) * 64.0, (cz + dz + 0.5) * 64.0)])
	net.s_watch.rpc_id(1, "f", 0, adds, [])
	net.say("ready")
	var got := false
	var told_mobs := false
	var hp: float = game.health
	for i in 20000:
		net.s_state.rpc_id(1, 0, pos, float(i) * 0.01, 0.0, "idle", 1.0, 0)
		var c = store.load_chunk(cx, cz)
		if not got and c is Dictionary and int(c.get("net_test", 0)) == 4242:
			got = true
			net.say("got 4242")
			# An edit from the copy Bob had before: the server merges it with the other's.
			stale["bob_mark"] = 7
			net.s_chunk_save.rpc_id(1, 0, NetPack.pack(stale))
		if not told_mobs and net.mobs["f"].size() > 0:
			told_mobs = true
			net.say("mobs %d" % net.mobs["f"].size())
			for id in net.mobs["f"]:
				var parts: PackedStringArray = String(id).split("_")
				if parts.size() == 3 and parts[0].is_valid_int():
					net.s_mob_hit.rpc_id(1, "f", 0, Vector2i(parts[0].to_int(), parts[1].to_int()), id, 1.0, false)
					net.say("hit %s" % id)
					break
		if game.health < hp - 0.01:
			hp = game.health
			net.say("hurt %d" % int(hp))
		if bye[0]:
			for j in 30:
				await process_frame
			quit(0)
			return
		await process_frame
	quit(4)
