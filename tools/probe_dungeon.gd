extends SceneTree
## Walks the dungeon under the nearest stronghold in the real game: builds it, stands in
## the stair hall, works every seal by its puzzle in order, reads a notice and goes down
## to the deepest level, checking each step. With --out=<dir> (not headless) it also
## saves screenshots on the way: the gatehouse, the stair hall, the biggest hall, a maze
## passage, a shut seal and its notice, a puzzle part, the seal raised and the treasury.
##   godot --path . --script res://tools/probe_dungeon.gd -- [--seed=4242] [--out=<dir>] [--levels=2]

var _fail := 0
var _out := ""
var world
var player: Player
var pl: Dictionary

func check(c: bool, m: String) -> void:
	print("  ok   " if c else "  FAIL ", m)
	if not c:
		_fail += 1

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## Stand at plan point q (feet at its floor) looking toward plan point at.
func _stand(q: Vector3, at: Vector3, pitch := -0.08) -> void:
	var w := Dungeon.to_world(pl, q)
	var a := Dungeon.to_world(pl, at)
	var d := a - w
	player.set_state({"pos": w, "yaw": atan2(-d.x, -d.z), "pitch": pitch, "slot": 0})
	player.velocity = Vector3.ZERO

func _shot(name: String, settle := 40) -> void:
	if _out == "":
		return
	await _frames(settle)
	await create_timer(0.6).timeout
	var path := _out.path_join("dungeon__%s.png" % name)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("  shot ", path)

func _floor(lv: int, c: Vector2i) -> Vector3:
	var m := Dungeon.centre(pl, c)
	return Vector3(m.x, Dungeon.floor_y(pl, lv) + 0.05, m.y)

func _run() -> void:
	var seed := "4242"
	var want_lv := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--levels="):
			want_lv = int(a.substr(9))
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	var game = root.get_node("/root/Game")
	game.new_world("DungeonProbe", seed)
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	world = current_scene
	player = world.player
	var t0 := Time.get_ticks_msec()
	while player.frozen and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	game.day = floor(game.day) + 0.45
	game.cheats["god"] = true # guards bite; the walk is about the place
	var g := Lore.gen()
	var p := player.global_position
	var forts := g.forts_near(p.x - 3000, p.z - 3000, p.x + 3000, p.z + 3000)
	forts.sort_custom(func(a, b): return (a["center"] as Vector2).distance_to(Vector2(p.x, p.z)) < (b["center"] as Vector2).distance_to(Vector2(p.x, p.z)))
	for f in forts:
		pl = Dungeon.plan(g, f)
		if pl["levels"].size() >= want_lv:
			break
	check(not pl.is_empty(), "a dungeon to visit (%s, %s, %d levels, %d rooms, %d seals)" % [pl.get("id"), pl.get("name"), pl["levels"].size(), Dungeon.room_count(pl), pl["locks"].size()])
	var m := Dungeon.mouth(pl)
	var gc := Dungeon.gatehouse(pl)
	var top := Vector3(m.x, float(pl["y0"]), m.y + 9.0)
	_stand(top, Vector3(gc.get_center().x, float(pl["y0"]) + 2.5, gc.get_center().y), -0.05)
	t0 = Time.get_ticks_msec()
	var dgs = world.get_node("Dungeons")
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		_stand(top, Vector3(gc.get_center().x, float(pl["y0"]) + 2.5, gc.get_center().y), -0.05)
		if world.streamer.is_ready_at(Dungeon.to_world(pl, top)) and dgs._nodes.has(pl["id"]):
			break
	var dn: DungeonNode = dgs._nodes.get(pl["id"])
	check(dn != null, "the dungeon stands by its fort")
	if dn == null:
		quit(1)
		return
	var td := Time.get_ticks_msec()
	while not dn.deep and Time.get_ticks_msec() - td < 5000:
		await process_frame
	check(dn.deep, "its levels are built when you're near")
	while not dn._queue.is_empty():
		await process_frame
	print("  blocks %d, torches %d, seals %d, puzzle parts %d" % [dn._blocks.size(), dn._lamps.size(), dn._seals.size(), dn._parts.size()])
	await _shot("1_gatehouse", 120)

	# The stair hall.
	var land: Vector2i = pl["entry"]["land"]
	var hall_far := _floor(0, land + Vector2i(0, -2))
	_stand(_floor(0, land) + Vector3(0, 0, 1.0), hall_far + Vector3(0, 1.2, 0))
	await _frames(90)
	var lw := Dungeon.to_world(pl, _floor(0, land))
	check(absf(player.global_position.y - lw.y) < 1.0, "you stand on the stair hall's floor (%.2f vs %.2f)" % [player.global_position.y, lw.y])
	check(not Dungeon.around(player.global_position).is_empty(), "the game knows you're in the dungeon")
	check(world.atmosphere._under_target > 0.5, "it's dark down here")
	check(not world.get_node("Water").visible and not player.swimming, "no sea down here, though it's below sea level")
	check(dgs._panel.visible and dgs._line.text.contains("Level 1"), "the tracker: %s / %s" % [dgs._title.text, dgs._line.text])
	await _shot("2_stair_hall")

	# The biggest hall on the first level.
	var big := -1
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["kind"] != "gone" and int(rm["lv"]) == 0 and (big < 0 or rm["w"] * rm["d"] > pl["rooms"][big]["w"] * pl["rooms"][big]["d"]):
			big = ri
	if big >= 0:
		var rm: Dictionary = pl["rooms"][big]
		var a := _floor(0, Vector2i(rm["x"], rm["z"]))
		var b := _floor(0, Vector2i(rm["x"] + rm["w"] - 1, rm["z"] + rm["d"] - 1))
		_stand(a + (b - a).normalized() * -0.8 + Vector3(0, 0, 0), b + Vector3(0, 1.4, 0))
		await _shot("3_hall_%s" % rm["kind"])

	# A maze passage.
	for lv in pl["levels"].size():
		if not pl["levels"][lv]["maze"]:
			continue
		var n: int = pl["n"]
		var picked := false
		for j in n:
			for i in n:
				var c := Vector2i(i, j)
				if Dungeon.kind(pl, lv, c) == Dungeon.CORR and Dungeon.is_open(pl, lv, c, 0) and Dungeon.is_open(pl, lv, c + Vector2i(1, 0), 0):
					_stand(_floor(lv, c), _floor(lv, c + Vector2i(2, 0)) + Vector3(0, 1.4, 0))
					picked = true
					break
			if picked:
				break
		if picked:
			await _shot("4_maze_level%d" % (lv + 1))
			break

	# Every seal, worked by its puzzle in order.
	for li in pl["locks"].size():
		var lk: Dictionary = pl["locks"][li]
		var fr: Array = Dungeon.front_of(pl, li)
		var dv := Vector2(Dungeon.DIRS[fr[1]])
		var fc := _floor(int(lk["lv"]), fr[0])
		if li == 0:
			_stand(fc - Vector3(dv.x, 0, dv.y) * 1.2, fc + Vector3(dv.x * 3.0, 1.4, dv.y * 3.0))
			await _shot("5_seal_shut_%s" % lk["kind"])
			var us: Array = dn.usables(player.global_position)
			check(us.any(func(u): return String(u["n"]).begins_with("note")), "the notice by the shut %s can be read" % Dungeon.WORDS[int(pl["era"])][0])
		for pi in lk["parts"]:
			var part: Dictionary = pl["parts"][pi]
			var at: Vector3 = part["p"]
			if part["kind"] == "plate":
				_stand(at + Vector3(0, 0.1, 0), at + Vector3(1, 0, 0))
				await create_timer(0.5).timeout
			else:
				var q := Dungeon.to_plan(pl, player.global_position)
				var c := Dungeon.centre(pl, Dungeon.cell_at(pl, Vector2(at.x, at.z)))
				_stand(Vector3(c.x, at.y if part["kind"] != "lever" else Dungeon.floor_y(pl, int(part["lv"])), c.y), at + Vector3(0, 0.9, 0), -0.2)
				await _frames(4)
				if li == 0 and pi == lk["parts"][0]:
					await _shot("6_puzzle_%s" % part["kind"])
				dn.use("part:%d" % pi, player)
				await _frames(2)
		if lk["kind"] == "key":
			dn.use("seal:%d" % li, player)
		await _frames(6)
		check(dn.seal_open(li), "seal %d (%s, to the %s) opens: %s" % [li, lk["kind"], lk["what"], lk["hint"]])
		if li == 0:
			await create_timer(3.0).timeout
			_stand(fc - Vector3(dv.x, 0, dv.y) * 1.2, fc + Vector3(dv.x * 3.0, 1.4, dv.y * 3.0))
			await _shot("7_seal_open")
	await create_timer(3.0).timeout
	var raised := 0
	for s in dn._seals:
		if float(s["amt"]) > 0.5:
			raised += 1
	check(raised == dn._seals.size(), "every seal is raised (%d/%d)" % [raised, dn._seals.size()])
	var ni: int = pl["notes"].size() - 1
	player.global_position = Dungeon.to_world(pl, pl["notes"][ni]["p"]) - Vector3(0, 1.4, 0)
	await _frames(3)
	dn.use("note:%d" % ni, player)
	await _frames(2)
	check(world.lore.is_open(), "reading a notice opens it")
	world.lore.close()

	# The treasury.
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["kind"] == "vault":
			var lv: int = rm["lv"]
			# From its doorway, looking in at the hoard.
			var dr: Dictionary = pl["doors"][rm["doors"][0]]
			var inside: bool = Dungeon.room_of(pl, lv, dr["a"]) == ri
			var out_c: Vector2i = dr["a"] + Dungeon.DIRS[dr["d"]] if inside else dr["a"]
			var in_c: Vector2i = dr["a"] if inside else dr["a"] + Dungeon.DIRS[dr["d"]]
			var o := _floor(lv, out_c)
			var c := _floor(lv, in_c)
			_stand(o + (c - o) * 0.3, c + Vector3(0, 0.6, 0), -0.12)
			await _shot("8_treasury")
			break

	# Down to the deepest level.
	var deep_lv: int = pl["levels"].size() - 1
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if rm["lv"] == deep_lv and rm["kind"] != "gone":
			_stand(_floor(deep_lv, Vector2i(rm["x"] + rm["w"] / 2, rm["z"] + rm["d"] / 2)) + Vector3(0, 0.2, 0), _floor(deep_lv, Vector2i(rm["x"], rm["z"])) + Vector3(0, 1.4, 0))
			break
	await _frames(60)
	check(dgs._line.text.contains("Level %d" % (deep_lv + 1)), "the tracker follows you down: %s" % dgs._line.text)
	var guards := 0
	for k in world.fauna._herds:
		for c in world.fauna._herds[k]:
			if is_instance_valid(c) and c.in_dungeon:
				guards += 1
	check(guards > 0, "guards keep the dungeon (%d)" % guards)
	await create_timer(3.0).timeout
	var chasing := 0
	for k in world.fauna._herds:
		for c in world.fauna._herds[k]:
			if is_instance_valid(c) and c.in_dungeon and c.state == "chase":
				chasing += 1
	print("  guards chasing you by the passages: %d" % chasing)
	print("dungeon probe: %d failed" % _fail)
	quit(1 if _fail > 0 else 0)
