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

## Walk up to a fern or flower and pick it with Interact, no tool needed.
func _pick_by_hand(game, streamer: ChunkStreamer, player) -> void:
	# The chest just opened is still showing its loot.
	player.get_tree().call_group("trade_ui", "close")
	await _frames(2)
	var plant := Vector3.INF
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for mmi in c._clutter:
			if not String(mmi.get_meta("key", "")).begins_with("under"):
				continue
			var buf: PackedFloat32Array = mmi.get_meta("buf")
			for i in buf.size() / 12:
				var o := Vector3(buf[i * 12 + 3], buf[i * 12 + 7], buf[i * 12 + 11])
				var at := c.position + o
				# The nearest on gentle ground.
				if Vector3(buf[i * 12 + 1], buf[i * 12 + 5], buf[i * 12 + 9]).length() > 0.5 and ChunkGenerator.slope_at(c.data, o.x, o.z) < 0.4 \
						and (plant == Vector3.INF or at.distance_to(player.global_position) < plant.distance_to(player.global_position)):
					plant = at
	check(plant != Vector3.INF, "a plant to pick by hand")
	if plant == Vector3.INF:
		return
	var pc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(plant))
	var stand := plant + Vector3(1.4, 0, 0)
	stand.y = ChunkGenerator.height_at(pc.data, stand.x - pc.position.x, stand.z - pc.position.z) + 0.1
	player.set_state({"pos": stand, "yaw": PI / 2.0, "pitch": -0.75, "slot": 0})
	for i in 300:
		await _frames(1)
		if streamer.is_ready_at(stand):
			break
	player.global_position = stand
	await _frames(20)
	check(player.focus.get("kind", "") == "plant", "looking at a plant offers to pick it (%s)" % player.focus.get("verb", "nothing"))
	var fiber: int = game.inventory.count("fiber")
	player.interact()
	check(game.inventory.count("fiber") > fiber, "picking it by hand gives fiber (%d -> %d)" % [fiber, game.inventory.count("fiber")])
	await _frames(15)
	check(player.focus.get("found", {}).get("pos", Vector3.INF) != plant, "a picked plant is gone")

## Swimming: dropped into deep water you float up and ride with your chest at the
## surface; a river carries you downstream; splashes are pooled and ready.
func _water_checks(streamer: ChunkStreamer, player) -> void:
	var back: Vector3 = player.global_position
	var sea := Vector3.INF
	var river := Vector3.INF
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for j in range(4, ChunkGenerator.SIZE - 4, 4):
			for i in range(4, ChunkGenerator.SIZE - 4, 4):
				var at := c.position + Vector3(i, 0, j)
				if sea == Vector3.INF and ChunkGenerator.height_at(c.data, i, j) < Water.LEVEL - 6.0:
					sea = at
				if river == Vector3.INF and Water.current(at.x, at.z).length() > 0.8:
					river = at
	check(Splashes._fx != null and Splashes._fx._rings.size() == Splashes.RINGS, "splashes and ripples are pooled")
	if sea == Vector3.INF:
		print("  skip no deep water near spawn")
	else:
		player.global_position = Vector3(sea.x, Water.LEVEL - 4.0, sea.z)
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		check(player.swimming and player.underwater, "deep in the water you swim, eyes under")
		for i in 360:
			await physics_frame
		var s := Water.surface_height(player.global_position.x, player.global_position.z, fmod(Time.get_ticks_msec() / 1000.0, 3600.0))
		var off: float = player.global_position.y - (s - Swim.FLOAT_CHEST)
		check(player.swimming and absf(off) < 0.6, "you float up and bob at the surface (%.2f m off)" % off)
	if river == Vector3.INF:
		print("  skip no river near spawn")
	else:
		var lv: float = Water.surface_height(river.x, river.z, 0.0)
		player.global_position = Vector3(river.x, lv - 1.4, river.z)
		player.velocity = Vector3.ZERO
		var flow := Water.current(river.x, river.z)
		for i in 90:
			await physics_frame
		var d := Vector2(player.global_position.x - river.x, player.global_position.z - river.z)
		check(d.dot(flow.normalized()) > 0.5, "the river carries you downstream (%.1f m)" % d.dot(flow.normalized()))
	player.global_position = back
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame

## Treasure maps: picking one up buries a chest out there and marks it; a chest in land
## that is already loaded is buried at once, dug out with the pickaxe and opened.
func _treasure(game, world, streamer: ChunkStreamer, player) -> Dictionary:
	var at: Vector3 = player.global_position
	game.give(Treasure.make_map(0, {}))
	var it = null
	for i in game.inventory.slots.size():
		var sl = game.inventory.get_slot(i)
		if sl != null and sl["type"] == "treasure_map":
			it = sl
	check(it != null and it.has("hunt") and game.treasure.size() == 1, "picking up a treasure map starts a hunt")
	if it == null or game.treasure.is_empty():
		return {}
	var h: Dictionary = game.treasure[0]
	var d := Vector2(h["x"], h["z"]).distance_to(Vector2(at.x, at.z))
	check(d > Treasure.MIN_DIST - 30.0 and d < Treasure.MAX_DIST + 30.0, "its chest lies a few hundred metres off (%d m)" % d)
	check(game.markers.count_kind("treasure") == 1, "an X marks the spot on the map")
	# A second hunt, pointed into loaded land outside any town, to dig up right here.
	var cn: ChunkNode = null
	var ck := ChunkStreamer.chunk_of(at)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c: ChunkNode = streamer.get_chunk(ck + off)
		if c != null and player.npcs.town_at(c.position + Vector3(32, 0, 32)).is_empty():
			cn = c
			break
	check(cn != null, "a loaded chunk outside town to bury a chest in")
	if cn == null:
		return {}
	var r := RandomNumberGenerator.new()
	var near := {"id": 99, "planet": game.planet, "x": cn.position.x + 32.0, "z": cn.position.z + 32.0, "era": 0, "level": 1,
		"loot": Treasure.roll_loot(0, r, cn.key), "found": false}
	game.treasure.append(near)
	world.get_node("Treasure").bury(cn, near)
	var o := Treasure.chest_in(cn.data, 99)
	check(not o.is_empty() and Treasure.covered(cn.data, o), "the chest is buried under the ground")
	if o.is_empty():
		return {}
	world.get_node("Treasure").bury(cn, near)
	var n := 0
	for oo in cn.data["objects"]:
		n += 1 if int(oo["st"].get("treasure", -1)) == 99 else 0
	check(n == 1, "a chest is buried only once")
	player._use_object(cn, o)
	check(not o["st"]["opened"], "a buried chest can't be opened")
	var wp: Vector3 = cn.position + o["p"]
	var hits := 0
	while Treasure.covered(cn.data, o) and hits < 40:
		streamer.dig(wp, 1.6 + 0.6 * 0.6, 0.35 * 0.6)
		hits += 1
	check(not Treasure.covered(cn.data, o) and hits > 4, "dug out with %d pickaxe blows" % hits)
	var m0: int = game.money
	player._use_object(cn, o)
	check(o["st"]["opened"] and near["found"] and game.money > m0, "opened, the chest pays out (%d Marks)" % (game.money - m0))
	await _frames(5)
	return {"key": cn.key, "id": 99, "open": int(h["id"])}

## Looting fills the pack with the item packs' odds and ends; set them aside so the items
## the test gives next have room; if that leaves fewer than `n` slots free, clear the last
## slots (whatever was looted lately) too.
func _make_room(game, n := 0) -> void:
	var loot := {}
	for sh in Icons.MORE_SHEETS.slice(1):
		for t in sh[1]:
			loot[t] = true
	for i in Inventory.SIZE:
		var it = game.inventory.get_slot(i)
		if it != null and loot.has(it["type"]):
			game.inventory.set_slot(i, null)
	for i in range(Inventory.SIZE - 1, -1, -1):
		if game.inventory.free_slots() >= n:
			break
		game.inventory.set_slot(i, null)

## What is in the pack, for a failure message.
func _pack_list(game) -> String:
	var out: PackedStringArray = []
	for i in Inventory.SIZE:
		var it = game.inventory.get_slot(i)
		if it != null:
			out.append("%s x%d" % [it["type"], int(it["qty"])])
	return ", ".join(out)

## A door hung through the real builder in a doorway you built: it opens and shuts,
## locks for its owner, needs picking when it's someone else's, and holds up its doorway.
func _door_checks(game, streamer, player: Player, pc: ChunkNode, lp: Vector3, here_key: Vector2i) -> void:
	var back := {"pos": player.global_position, "yaw": player.yaw(), "pitch": -0.75, "slot": player.selected}
	_make_room(game, 3)
	var dway := pc.add_built("wall_door", lp, 0.0, {"by": "you", "day": 0.0})
	var dwp: Vector3 = pc.position + dway["p"]
	game.give(ItemDB.make("door_wood", 1, 1.0, game.origin_here("crafted", -1, here_key)))
	var di := -1
	for i in Inventory.SIZE:
		var sl = game.inventory.get_slot(i)
		if sl != null and sl["type"] == "door_wood":
			di = i
	game.inventory.swap(di, 6)
	player.select(6)
	await _frames(3)
	check(player.builder.piece_id() == "door_wood", "holding a door starts hanging it")
	var miss: Dictionary = player.builder._door_target(dwp + Vector3(30, 1.6, 30), dwp + Vector3(34, 1.0, 34))
	check(not miss["ok"], "a door won't hang without a doorway")
	var tgt: Dictionary = player.builder._door_target(dwp + Vector3(0.3, 1.6, 4.0), dwp + Vector3(-0.2, 1.0, -3.0))
	check(tgt["ok"] and (tgt["pos"] as Vector3).is_equal_approx(dwp), "aiming through a doorway hangs the door in it (%s)" % tgt)
	player.builder._target = tgt
	check(player.builder.place(), "the door is hung")
	var dc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(dwp))
	var door := {}
	for o in dc.data["objects"]:
		if o["t"] == "b:door_wood" and not o["st"].get("gone", false):
			door = o
	check(not door.is_empty() and Doors.is_mine(door) and not Doors.is_locked(door), "it's a door of yours, unlocked")
	if door.is_empty():
		return
	var dn: DoorNode = dc._doors.get(door["i"])
	check(dn != null and dn._bodies.size() == 1, "a hung door is drawn with a solid leaf")
	var shut: Transform3D = dn._leaves[0].transform
	player.focus = {"kind": "door", "chunk": dc, "i": door["i"], "pos": dwp + Vector3(0, 1.5, 0), "verb": ""}
	player.global_position = dwp + Vector3(0, 0.2, 2.0)
	player._use_door()
	check(Doors.is_open(door) and float(door["st"]["side"]) == 1.0, "interact opens it, away from you")
	await _frames(150)
	check(dn._amount > 0.99 and not dn._leaves[0].transform.is_equal_approx(shut), "the door swings open (%.2f)" % dn._amount)
	player.focus = {"kind": "door", "chunk": dc, "i": door["i"], "pos": dwp + Vector3(0, 1.5, 0), "verb": ""}
	player._use_door()
	await _frames(150)
	check(not Doors.is_open(door) and dn._amount < 0.01, "and shut again")
	player._crouched = true
	player.focus = {"kind": "door", "chunk": dc, "i": door["i"], "pos": dwp + Vector3(0, 1.5, 0), "verb": ""}
	player._use_door()
	player._crouched = false
	check(Doors.is_locked(door) and Doors.can_open(door), "crouch and interact locks your door; you still open it")
	# Someone else's: the lock needs picking.
	door["st"]["owner"] = "player_42"
	check(Player.lock_of(door) == 1 and not Player.is_own_piece(door), "a stranger's door is a novice lock, not yours to take down")
	player.focus = {"kind": "door", "chunk": dc, "i": door["i"], "pos": dwp + Vector3(0, 1.5, 0), "verb": ""}
	player._use_door()
	check(not Doors.is_open(door), "it stays shut on you")
	# (With lockpicks in the pack that opened the minigame; leave it, and keep townsfolk
	# out of this, so a bounty doesn't set the guards on the rest of the run.)
	player.get_tree().call_group("lockpick_ui", "close_lock")
	var npcs = player.npcs
	player.npcs = null
	player.use_door_after_lock(dc, door)
	player.npcs = npcs
	check(Doors.is_open(door) and not Doors.is_locked(door), "a picked lock opens the door")
	door["st"]["owner"] = Doors.my_id()
	check(not player.deconstruct(pc, dway) and not dway["st"].get("gone", false), "the doorway stays up while a door hangs in it")
	check(player.deconstruct(dc, door) and door["st"].get("gone", false) and game.inventory.count("door_wood") == 1, "taking the door down returns it")
	await _frames(2)
	check(not dc._doors.has(door["i"]), "a door taken down is gone from the scene")
	check(player.deconstruct(pc, dway), "then the doorway comes down")
	# Leave the pack as it was: later checks need its free slots.
	game.inventory.remove_type("door_wood", 1)
	game.inventory.remove_type("wall_door", 1)
	player.set_state(back)
	await _frames(2)

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
	# Streaming runs on worker threads: give a busy machine longer than a fixed count of frames.
	for i in 600:
		if streamer.chunks.size() >= 9:
			break
		await process_frame
	check(streamer.chunks.size() >= 9, "chunks streamed in (%d)" % streamer.chunks.size())
	var here: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(player.global_position))
	var here_key: Vector2i = here.key

	# The atlas paints the land that streams in and lifts the fog where you stand.
	for i in 60:
		await process_frame
	var ppos: Vector3 = player.global_position
	check(game.map.revealed(ppos.x, ppos.z) > 0.9, "the fog has lifted where you stand")
	check(game.map.revealed(ppos.x + 600.0, ppos.z) == 0.0, "but not far away")
	check(not game.map.textures(WorldMap.page_of_chunk(here_key)).is_empty(), "the map page under you is painted")
	check(world.hud._minimap != null and world.hud._minimap.player == player, "the HUD has a minimap")
	var ver: Label = world.hud.get_node_or_null("Version")
	check(ver != null and ver.text == "v%s" % ProjectSettings.get_setting("application/config/version"), "the HUD shows the version in a corner (%s)" % (ver.text if ver else "none"))
	await process_frame
	var mc: Vector2 = world.hud._minimap._canvas.center
	check(mc.distance_to(Vector2(ppos.x, ppos.z)) < 2.0, "the minimap follows you (%s vs %s)" % [mc, Vector2(ppos.x, ppos.z)])
	var zone: Dictionary = world.hud._minimap._zone
	check(not zone.is_empty() and String(zone["finds"]) != "", "the minimap names the zone, its levels and what's found there (%s)" % zone.get("name", ""))
	var far := ZoneInfo.at(game.seed, 3000.0, 0.0)
	var flv := ZoneInfo.level_at(3000.0, 0.0)
	check(far["level_lo"] <= flv and flv <= far["level_hi"] and far["level_hi"] % 10 == 9, "the band holds the zone's level (%d in %d-%d)" % [flv, far["level_lo"], far["level_hi"]])
	check(far["level_lo"] >= zone["level_lo"], "zones further out are no lower level")
	await _map_unit_checks()

	# Jetpack: worn on the back, it loads a canister of Jet Fuel and lifts you in the air.
	game.give(ItemDB.make("jetpack", 1, 1.0, {}))
	game.give(ItemDB.make("jet_fuel", 2, 1.0, {}))
	var jslot := -1
	for i in Inventory.SIZE:
		var js = game.inventory.get_slot(i)
		if js != null and js["type"] == "jetpack":
			jslot = i
	check(jslot >= 0 and game.equip(jslot) and Jetpack.worn() != null, "a jetpack can be worn on the back")
	var lift: float = player.jetpack.thrust(0.1, true, true, false, 0.0, game.inventory)
	check(lift > 0.0 and player.jetpack.firing and game.inventory.count("jet_fuel") == 1, "jumping in the air fires the jetpack and loads a fuel canister")
	check(player.jetpack.thrust(0.1, true, true, true, 0.0, game.inventory) == 0.0, "the jetpack does not fire on the ground")
	Jetpack.worn()["fuel"] = 0.0
	game.inventory.remove_type("jet_fuel", 99)
	check(player.jetpack.thrust(0.1, true, true, false, 0.0, game.inventory) == 0.0 and not player.jetpack.firing, "an empty jetpack does nothing")
	game.unequip("back")
	game.inventory.remove_type("jetpack", 1)

	# Fell the first tree in the current chunk (or any loaded chunk).
	var felled := {}
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "tree" and not o["st"].get("gone", false):
				felled = {"key": k, "i": o["i"], "t": o["t"]}
				c.remove_object(o["i"])
				game.give(ItemDB.make(ObjectLibrary.YIELD[o["t"]], 5, 1.0, game.origin_here("gathered", o["e"], k)))
				check(game.inventory.count(ObjectLibrary.YIELD[o["t"]]) >= 5, "harvested %s goes in the pack" % ObjectLibrary.YIELD[o["t"]])
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
	var tre := await _treasure(game, world, streamer, player)

	# Pull up a plant of undergrowth: it vanishes and is remembered by its chunk.
	var plant := Vector3.INF
	for k in streamer.chunks:
		for mmi in streamer.chunks[k]._clutter:
			if String(mmi.get_meta("key", "")).begins_with("under") and mmi.multimesh.instance_count > 0:
				var b0: PackedFloat32Array = mmi.get_meta("buf")
				plant = streamer.chunks[k].position + Vector3(b0[3], b0[7], b0[11])
				break
		if plant != Vector3.INF:
			break
	check(plant != Vector3.INF, "undergrowth grows near the player")
	if plant != Vector3.INF:
		var got := streamer.harvest_under(plant + Vector3(0, 2.5, 1.5), plant + Vector3(0, 0.3, 0), 0.6)
		var pc0: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(plant))
		check(not got.is_empty() and pc0.data.get("cleared", PackedFloat32Array()).size() >= 2, "harvesting undergrowth removes and remembers it")
		var rebuilt := ChunkNode.build_clutter_buffers(pc0.data, 1.0)
		var still := false
		for key in rebuilt:
			if String(key).begins_with("under"):
				var b: PackedFloat32Array = rebuilt[key]
				for i in range(0, b.size(), 12):
					if Vector2(b[i + 3], b[i + 11]).distance_to(Vector2(got["pos"].x - pc0.position.x, got["pos"].z - pc0.position.z)) < 0.01:
						still = true
		check(not still, "a harvested plant does not grow back when the chunk is rebuilt")

	# Lake beds grow waterweed and lie strewn with stones.
	var lg := ChunkGenerator.new(game.seed, game.store.has_rivers())
	var bed := {}
	for r in 10:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if bed.is_empty() and maxi(absi(dx), absi(dz)) == r:
					var ch := lg.generate(dx, dz)
					var deep := 0
					for h in ch["heights"]:
						deep += 1 if h < -2.0 else 0
					if deep > 600:
						bed = ch
	check(not bed.is_empty(), "found a lake bed near spawn")
	if not bed.is_empty():
		var weeds := 0
		var grass := ChunkNode.build_grass_buffers(bed, 1.0)
		for key in grass:
			if String(key).begins_with("weed@"):
				weeds += (grass[key] as PackedFloat32Array).size() / 16
		var sunk := 0
		var clutter := ChunkNode.build_clutter_buffers(bed, 1.0)
		for key in clutter:
			if String(key).begins_with("stone:"):
				var b: PackedFloat32Array = clutter[key]
				for i in range(0, b.size(), 16):
					sunk += 1 if b[i + 7] < -0.6 else 0
		check(weeds > 20 and sunk > 20, "a lake bed has waterweed and stones (%d weeds, %d stones)" % [weeds, sunk])

	# Cliffs are dressed with crags: big rocks set into the steep faces only, the same
	# each time the chunk is built, each one solid.
	var steep := {}
	for r in 12:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if steep.is_empty() and maxi(absi(dx), absi(dz)) == r:
					var ch := lg.generate(dx, dz)
					var n := 0
					for j in 16:
						for i in 16:
							n += 1 if ChunkGenerator.slope_at(ch, i * 4.0 + 2.0, j * 4.0 + 2.0) > 1.3 else 0
					if n > 12:
						steep = ch
	if steep.is_empty():
		print("  no cliffs near spawn: crags not checked")
	else:
		var crags := ChunkNode.build_crag_buffers(steep)
		var placed := 0
		var on_steep := true
		for key in crags:
			if String(key).begins_with("stone:"):
				var b: PackedFloat32Array = crags[key]
				for i in range(0, b.size(), 16):
					placed += 1
					# (The rock sits a little into the face from the point it was placed on, and
					# the ones at a rim stand by the level ground above it.)
					var face := 0.0
					for o in [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
						face = maxf(face, ChunkGenerator.slope_at(steep, clampf(b[i + 3] + o.x, 0.0, 64.0), clampf(b[i + 11] + o.y, 0.0, 64.0)))
					on_steep = on_steep and face > 0.8
		var again := ChunkNode.build_crag_buffers(steep)
		check(placed > 3 and on_steep, "cliffs are dressed with crags on their steep faces (%d)" % placed)
		check(again.get("stone:rock_a") == crags.get("stone:rock_a") and again.get("stone:rock_b") == crags.get("stone:rock_b"), "crags are the same every time")
		check((crags.get("~crags", PackedFloat32Array()) as PackedFloat32Array).size() / 13 == placed, "every crag is solid")

	# Loot the nearest cache by walking up to it, as a player would: the floating prompt
	# should pick it and Interact should open it.
	var looted := {}
	var best_c: ChunkNode = null
	var best_o := {}
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "cache" and not o["st"].get("opened", false) and not o["st"].has("inside"):
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

	await _pick_by_hand(game, streamer, player)
	await _walk_into_house(game, world, streamer, player)
	await _rooms(game, streamer, player)
	await _relics(game, streamer, player)
	await _easter_eggs(game, streamer, player)
	await _audio_checks(world, player)
	await _water_checks(streamer, player)

	# Build: aim at the ground and place a foundation through the real builder, then a
	# workbench next to it, and take a wall down for a refund.
	_make_room(game)
	game.give(ItemDB.make("foundation", 3, 1.0, game.origin_here("crafted", -1, here_key)))
	var fi := -1
	for i in Inventory.SIZE:
		var sl = game.inventory.get_slot(i)
		if sl != null and sl["type"] == "foundation":
			fi = i
	game.inventory.swap(fi, 5)
	player.select(5)
	# Stand on open, level ground for it (wherever the chest left us may face a rock or a
	# terrace riser).
	var site := _open_ground(streamer, player.global_position)
	check(site != Vector3.INF, "found open level ground to build on")
	if site != Vector3.INF:
		player.global_position = site
	player.set_state({"pos": player.global_position, "yaw": 0.3, "pitch": -0.75, "slot": 5})
	await _frames(4)
	check(player.builder.active(), "holding a foundation starts building")
	check(player.builder.place(), "foundation placed where the player looks (%s)" % player.builder._target)
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
	_make_room(game, 3)
	var wall := pc.add_built("wall_stone", placed["p"] + Vector3(0, 0, 1), 0.0, {"by": "you", "day": 0.0})
	player.damage_object(pc, wall, 1000.0, 1.0)
	check(wall["st"].get("gone", false) and game.inventory.count("wall_stone") == 1, "taking a wall down returns it")
	var fence := pc.add_built("fence", placed["p"] + Vector3(-3, 0, 0), 0.0, {"by": "you", "day": 0.0})
	check(player.deconstruct(pc, fence) and fence["st"].get("gone", false) and game.inventory.count("fence") == 1, "deconstructing your own piece returns it")
	await _door_checks(game, streamer, player, pc, placed["p"] + Vector3(0, 0, -6), here_key)
	var bwall := {"key": placed["key"], "i": wall["i"]}
	var bwb := {"key": placed["key"], "i": wb["i"]}

	# Kit animals: a species drawn with a rigged model animates, reacts and dies.
	var ksp := 0
	while Creature.species(ksp, Eras.MEDIEVAL)["kit"] == "":
		ksp += 1
	var kc := Creature.new()
	kc.setup("test_kit", ksp, Eras.MEDIEVAL, player.global_position + Vector3(6, 0, 0), world.fauna)
	world.fauna.add_child(kc)
	await _frames(3)
	check(kc._kit != null and kc._kit.anim.is_playing(), "kit animal is animated (%s)" % kc.label())
	# Its name tag draws after the water surface (0) and splash rings (1), so a lake behind
	# or under the animal never covers it.
	kc.update_tag(true, 1)
	check(kc._tag_label.render_priority > 1 and kc._tag_label.outline_render_priority > 1
		and Creature._bar_mat.render_priority > 1, "animal name tags draw over the water")
	# ...but walls and roofs still hide them (they are depth-tested).
	check(not kc._tag_label.no_depth_test and not Creature._bar_mat.shader.code.contains("depth_test_disabled"), "animal name tags are hidden behind walls")
	# An animal stuck in the water next to ground that isn't loaded yet stays put instead
	# of jumping onto the missing ground (it went to NaN and vanished for good).
	var uc := Creature.new()
	var u0: Vector3 = player.global_position + Vector3(9, 0, 9)
	uc.setup("test_unstuck", ksp, Eras.MEDIEVAL, u0, world.fauna)
	world.fauna.add_child(uc)
	uc.global_position = Vector3(u0.x, -5.0, u0.z)
	uc._ground = func(x: float, z: float) -> float:
		return -5.0 if Vector2(x, z).distance_to(Vector2(u0.x, u0.z)) < 0.5 else NAN
	uc._get_unstuck()
	check(uc.global_position.is_finite() and uc.home.is_finite(), "an animal never moves onto unloaded ground (%s)" % uc.global_position)
	uc.queue_free()
	# Hunting: an animal in front of you takes damage from a swing, wherever it faces.
	# Hand the test animal to the fauna manager (so aim help finds it), and hold off its
	# herd refresh, which would free a herd this far from the player.
	world.fauna._scan = 1.0e9
	world.fauna._herds[Vector2i(99999, 99999)] = [kc]
	# Swing bare-handed: an empty hotbar slot, not the building piece left selected above.
	var bare := Inventory.HOTBAR - 1
	for i in Inventory.HOTBAR:
		if game.inventory.get_slot(i) == null:
			bare = i
			break
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		if game.inventory.get_slot(bare) == null:
			break
		if game.inventory.get_slot(i) == null:
			game.inventory.swap(bare, i)
	player.select(bare)
	for face in [0.0, PI * 0.5, PI]:
		var eye: Vector3 = player.camera.global_position
		var fwd: Vector3 = -player.camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		kc.global_position = Vector3(eye.x, 0, eye.z) + fwd * 2.2
		kc.global_position.y = world.vehicles.ground(kc.global_position.x, kc.global_position.z)
		kc.rotation.y = face
		kc.set_process(false)
		kc.set_physics_process(false)
		player.set_state({"pos": player.global_position, "yaw": player.yaw(), "pitch": -0.6, "slot": player.selected, "view": 1})
		await _frames(3)
		var hp0 := kc.hp
		player._cooldown = 0.0
		player.use_held()
		check(kc.hp < hp0, "a swing hits an animal facing %d deg (%.0f -> %.0f hp, aim hits %s)" % [rad_to_deg(face), hp0, kc.hp, str(player._hit_object().keys())])
		kc.hp = hp0
	# A wolf at your feet, with you looking straight ahead: the swing still lands.
	var feet_fwd: Vector3 = -player.camera.global_transform.basis.z
	feet_fwd.y = 0.0
	kc.global_position = player.global_position + feet_fwd.normalized() * 1.5
	player.set_state({"pos": player.global_position, "yaw": player.yaw(), "pitch": 0.0, "slot": player.selected, "view": 1})
	await _frames(3)
	var hp1 := kc.hp
	player._cooldown = 0.0
	player.use_held()
	check(kc.hp < hp1, "a level swing hits an animal at your feet (%.0f -> %.0f hp)" % [hp1, kc.hp])
	await _guns(game, world, player, kc, bare)
	world.fauna._herds.erase(Vector2i(99999, 99999))
	world.fauna._scan = 0.0
	await _corpses(game, world, player, kc)

	# Vehicles: set one down from the pack, ride it forward, get off, pack it up.
	_make_room(game)
	game.inventory.add(ItemDB.make("speeder", 1, 1.0, {}))
	var vslot := -1
	for i in game.inventory.slots.size():
		var it = game.inventory.get_slot(i)
		if it != null and it["type"] == "speeder":
			vslot = i
	if vslot >= Inventory.HOTBAR:
		game.inventory.swap(vslot, Inventory.HOTBAR - 1)
		vslot = Inventory.HOTBAR - 1
	player.select(vslot)
	check(player.deploy_vehicle() and game.vehicles.size() == 1 and game.inventory.count("speeder") == 0, "a speeder sets down from the pack")
	await _frames(5)
	var sp: Vehicle = world.vehicles.nodes.get(int(game.vehicles[0]["id"])) if not game.vehicles.is_empty() else null
	check(sp != null, "the speeder is in the world")
	if sp != null:
		player.mount(sp)
		var v0: Vector3 = sp.global_position
		Input.action_press("move_forward")
		for i in 120:
			await physics_frame
		Input.action_release("move_forward")
		var moved := Vector2(sp.global_position.x - v0.x, sp.global_position.z - v0.z).length()
		check(moved > 4.0, "riding forward moves the speeder (%.1f m)" % moved)
		check(player.global_position.distance_to(sp.seat_transform().origin) < 1.0, "the rider stays in the seat")
		check(sp.global_position.y > world.vehicles.ground(sp.global_position.x, sp.global_position.z) + 0.3, "the speeder hovers off the ground")
		check(player.get_state()["riding"] == int(sp.rec["id"]), "riding is saved")
		player.dismount()
		check(player.vehicle == null and sp.rider == null, "getting off")
		check(world.vehicles.pack_up(sp) and game.vehicles.is_empty() and game.inventory.count("speeder") == 1, "packing the speeder up returns it")
	# A starship climbs where you look, won't let you step out in mid-air, and lands.
	var ship: Vehicle = world.vehicles.deploy(ItemDB.make("ship", 1, 1.0, {}), player.global_position + Vector3(0, 0, -9), 0.0)
	for i in 30:
		await physics_frame
	check(ship != null and ship.is_on_floor(), "a starship sets down on the ground")
	player.mount(ship)
	var y0s: float = ship.global_position.y
	Input.action_press("jump")
	for i in 120:
		await physics_frame
	Input.action_release("jump")
	check(ship.global_position.y > y0s + 10.0, "the starship climbs (%.1f m)" % (ship.global_position.y - y0s))
	player.dismount()
	check(player.vehicle == ship, "can't step out in mid-air")
	Input.action_press("crouch")
	for i in 400:
		await physics_frame
		if ship.is_on_floor():
			break
	Input.action_release("crouch")
	check(ship.is_on_floor(), "the starship lands")
	player.dismount()
	check(player.vehicle == null, "stepping out after landing")
	world.vehicles.pack_up(ship)
	var hr: Vehicle = world.vehicles.deploy(ItemDB.make("horse", 1, 1.0, {}), player.global_position + Vector3(4, 0, 0), 0.0)
	await _frames(3)
	check(hr != null and hr._animal != null, "a riding horse stands ready")
	if hr:
		world.vehicles.pack_up(hr)

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
	_make_room(game)
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

	await _menu_checks(world, game, con)

	# Dying: health hits zero, everything you carry drops in a bag where you fell, a
	# pause, then you wake at the spawn with an empty pack and the bag on your map.
	await _death_bag(game, world, player)

	var inv_before := var_to_bytes(game.inventory.to_data())
	var money_before: int = game.money
	player.global_position += Vector3(3, 0, 2)
	await _frames(10)
	# Where the player ends up after physics settles (they may be standing on what was built).
	var pos_before: Vector3 = player.global_position

	var map_seen: float = game.map.revealed(pos_before.x, pos_before.z)
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
	if not tre.is_empty():
		var tc = store.load_chunk(tre["key"].x, tre["key"].y)
		var tch := Treasure.chest_in(tc, tre["id"])
		check(not tch.is_empty() and tch["st"]["opened"] and not Treasure.covered(tc, tch), "the dug-up chest stays dug up and empty")
		var th: Dictionary = game.hunt(tre["open"])
		check(not th.is_empty() and not th["found"] and not (th["loot"] as Array).is_empty() and game.hunt(tre["id"])["found"], "hunts are saved, found or not, with what's buried")
		# (Only that hunt's X: a body searched since may have carried a map of its own.)
		var xs: Array = game.markers.list.filter(func(mk): return mk["kind"] == "treasure" and int(mk.get("hunt", -1)) == int(tre["open"]))
		check(xs.size() == 1, "the open hunt keeps its X")
	var inv_after := var_to_bytes(game.inventory.to_data())
	check(inv_after == inv_before, "inventory bit-for-bit identical after reload")
	check(game.money == money_before, "money identical after reload")
	check(game.equipment.has("head") and game.equipment["head"]["type"] == "helm_elven", "worn armour restored")
	check(game.stats.level == 3 and game.stats.attrs["end"] == 1 and game.max_health() == 110.0, "level and attributes restored")
	check(game.inventory.count(ObjectLibrary.YIELD[felled["t"]]) >= 5, "harvested %s is in the pack (%d, pack %s)" % [ObjectLibrary.YIELD[felled["t"]], game.inventory.count(ObjectLibrary.YIELD[felled["t"]]), _pack_list(game)])
	check(game.pending_player_state["pos"].distance_to(pos_before) < 0.01, "player position restored")
	check(game.discovery["visited"].size() >= 1, "discovery log saved")
	check(absf(game.map.revealed(pos_before.x, pos_before.z) - map_seen) < 0.01 and map_seen > 0.9, "the atlas remembers where the fog lifted")
	var c4 = store.load_chunk(placed["key"].x, placed["key"].y)
	check(c4["objects"][placed["i"]]["t"] == "b:foundation" and c4["objects"][placed["i"]]["p"].distance_to(placed["p"]) < 0.001, "built foundation saved in place")
	check(c4["objects"][bwb["i"]]["t"] == "b:workbench", "workbench saved")
	check(c4["objects"][bwall["i"]]["st"].get("gone", false), "taken-down wall stays gone")

	# Regenerating the same chunk with today's generator would NOT reproduce the edits,
	# which proves the game reads the snapshot rather than regenerating.
	var fresh := ChunkGenerator.new(game.seed, store.has_rivers()).generate(here_key.x, here_key.y)
	check(absf(ChunkGenerator.height_at(fresh, lx, lz) - after) > 0.5, "snapshot, not regeneration, is the source of truth")

	# Spaceflight: climb out of the sky to orbit, warp to another planet and land there.
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	world = current_scene
	player = world.player
	for i in 600:
		await process_frame
		if not player.frozen:
			break
	var home_seed: int = game.seed
	var sh: Vehicle = world.vehicles.deploy(ItemDB.make("ship", 1, 1.0, {}), player.global_position + Vector3(0, 0, -9), 0.0)
	for i in 10:
		await physics_frame
	player.mount(sh)
	sh.leaving = Vehicle.LEAVE_TIME
	sh.at_ceiling = true
	for i in 20:
		await process_frame
	check(current_scene is OrbitView, "climbing out of the sky reaches orbit")
	var target := -1
	for pl in game.worlds():
		if pl["kind"] == "fey":
			target = pl["n"]
	OrbitView._arrive(target)
	check(game.planet == target and game.seed != home_seed and WorldField.allowed_eras == [Eras.FANTASY, Eras.SCIFI] and Eras.theme == "alien", "warping makes the fey world current")
	current_scene._land()
	await _frames(5)
	world = current_scene
	player = world.player
	for i in 900:
		await process_frame
		if player.vehicle != null:
			break
	check(player.vehicle != null and player.vehicle.kind == "ship", "you land flying your ship")
	var pw: PackedFloat32Array = world.atmosphere.field.era_weights(player.global_position.x, player.global_position.z)
	check(pw[Eras.FANTASY] > 0.99, "the fey world's heart is all fey land")
	check(DirAccess.dir_exists_absolute(game.store.root.path_join("planets/%d/chunks" % target)), "the planet's land is saved apart from home")
	# Through a portal from the fey world to the verdant one, then the fey world remembers
	# the portal you left by.
	var gone_from := Vector2(player.global_position.x, player.global_position.z)
	player.dismount(true)
	var verdant := 1
	for pl in game.worlds():
		if pl["kind"] == "verdant":
			verdant = pl["n"]
	game.travel_portal(player, verdant, gone_from)
	await _frames(5)
	world = current_scene
	player = world.player
	for i in 900:
		await process_frame
		if not player.frozen:
			break
	check(game.planet == verdant and Eras.theme == "human" and not player.frozen and player.is_inside_tree(), "a portal takes you to another world, on your feet")
	check(game.landings.get(target) == gone_from, "the world you left remembers the portal you used")
	target = verdant
	game.close_world()
	check(WorldField.allowed_eras.is_empty(), "closing the world resets planet rules")
	check(game.load_world(world_id) and game.planet == target, "the save remembers which planet you're on")

	game.close_world()
	WorldStore.delete_world(world_id)
	_check_landform_mesh()
	print("integration: %s" % ("PASSED" if _fail == 0 else "%d FAILED" % _fail))
	quit(1 if _fail > 0 else 0)

## Sound: every bank the game plays has files, the ambience sampler knows where you
## are, footsteps find a surface, and the buses follow the volume settings.
func _audio_checks(world, player) -> void:
	var audio = root.get_node("/root/Audio")
	var banks := ["step/grass", "step/stone", "step/wood", "step/snow", "step/gravel", "step/metal", "hit/wood",
		"hit/stone", "hit/metal", "hit/crystal", "hit/soft", "hit/flesh", "hit/heavy", "hit/dig", "hit/plank",
		"harvest/rustle", "swing/whoosh", "water/splash", "item/pickup", "item/coins", "item/equip",
		"weapon/laser", "weapon/laser_big", "weapon/explosion", "weapon/draw", "ui/click", "ui/hover", "ui/open",
		"ui/close", "ui/tab", "ui/toggle", "ui/tick", "ui/error", "jingle/level_up", "jingle/discovery", "jingle/death"]
	var empty: Array = []
	for b in banks:
		if audio.bank(b).is_empty():
			empty.append(b)
	check(empty.is_empty(), "every sound bank has files %s" % [empty])
	for id in audio.LAYERS:
		check(audio._layers[id].stream != null, "ambience layer %s loads" % id)
	for m in audio.MOODS:
		for t in audio.MOODS[m]:
			check(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % t), "music %s exists" % t)
	await _frames(30)
	check(audio.env.get("where", "") == "world", "ambience sampler sees the world (%s)" % audio.env.get("where", ""))
	var on := 0
	for id in audio._layer_target:
		if audio._layer_target[id] > 0.0:
			on += 1
	check(on > 0, "some ambience is playing outdoors (%d layers)" % on)
	var surf: String = player.steps.surface(player)
	check(surf in ["grass", "stone", "wood", "snow", "gravel", "metal", "sand", "wade"], "footstep surface under the player: %s" % surf)
	audio.combat()
	check(audio._want_mood() == "combat", "a fight brings in battle music")
	audio._combat_t = -100.0
	var s = root.get_node("/root/Settings")
	var old: float = s.get_value("music_volume")
	s.set_value("music_volume", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music slider at zero mutes the music bus")
	s.set_value("music_volume", old)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music bus back on")

## Death: your pack, armour and purse drop in a bag where you fell, saved with its chunk
## and marked on your map; taking it all back puts your armour on again and clears the mark.
func _death_bag(game, world, player) -> void:
	var count_before: int = game.inventory.count("planks")
	var items_before := 0
	for it in game.inventory.slots:
		if it != null:
			items_before += 1
	var money_before: int = game.money
	var worn_before: Dictionary = game.equipment.duplicate(true)
	var at: Vector3 = player.global_position
	game.set_health(-5.0, "test")
	check(game.dead and player.ui_open, "zero health kills you")
	check(game.inventory.free_slots() == game.inventory.capacity and game.equipment.is_empty() and game.money == 0, "dying empties your pack, armour and purse")
	await _frames(3)
	var bag := {}
	for b in world.corpses.near(at, 40.0):
		if DeathBag.is_bag(b["rec"]):
			bag = b
	check(not bag.is_empty() and Vector2(bag["pos"].x, bag["pos"].z).distance_to(Vector2(at.x, at.z)) < 6.0, "a bag lies where you fell")
	if bag.is_empty():
		print("  no bag drawn; shown: %s" % [world.corpses._shown.keys()])
	var marks: Array = game.markers.on_planet(game.planet, "death")
	check(marks.size() == 1 and Vector2(marks[0]["x"], marks[0]["z"]).distance_to(Vector2(at.x, at.z)) < 6.0, "the map marks where you died")
	if bag.is_empty():
		return
	check(DeathBag.is_mine(bag["rec"], game.my_id()) and Corpses.use_of(bag["rec"])[1] == "Open your bag", "it is your bag")
	var e: Dictionary = world.corpses._shown[bag["key"]]
	var saved = game.store.load_chunk(int(e["cn"].data["cx"]), int(e["cn"].data["cz"]))
	check(saved is Dictionary and saved.get("corpses", {}).has(e["id"]), "the bag is saved with its chunk at once")
	await create_timer(4.6).timeout
	await _frames(30)
	check(not game.dead and game.health == game.max_health() and not player.ui_open, "you get back up with full health")
	# Back to the bag: open it and take everything.
	var bag_at: Vector3 = bag["pos"]
	player.global_position = bag_at + Vector3(1.5, 1.0, 0)
	bag = {}
	# (Up to half a minute: the ground there has to stream back in first.)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		world.corpses._scan = 0.0
		await _frames(5)
		for b in world.corpses.near(bag_at, 2.0):
			if DeathBag.is_bag(b["rec"]):
				bag = b
		if not bag.is_empty():
			break
	check(not bag.is_empty(), "the bag is still there when you come back")
	if bag.is_empty():
		var bk := ChunkStreamer.chunk_of(bag_at)
		var bcn: ChunkNode = world.streamer.get_chunk(bk)
		print("  bag chunk %s loaded: %s, corpses there: %s, shown: %s" % [bk, bcn != null, bcn.data.get("corpses", {}).keys() if bcn else [], world.corpses._shown.keys()])
		return
	var menus = world.menus
	menus.open_corpse(world.corpses, bag["key"])
	check(menus._mode == "corpse" and menus._store.capacity == DeathBag.SLOTS, "opening the bag shows what is in it")
	var m: int = menus._take_purse()
	Storage.transfer_all(menus._store, game.inventory)
	menus._corpse_changed(m)
	if menus._mode != "":
		menus.close()
	var items_after := 0
	for it in game.inventory.slots:
		if it != null:
			items_after += 1
	check(game.inventory.count("planks") == count_before and items_after == items_before, "everything comes back out of the bag (%d of %d slots)" % [items_after, items_before])
	check(game.money == money_before, "the purse comes back")
	check(game.equipment.keys().size() == worn_before.keys().size(), "your armour goes back on (%d pieces)" % worn_before.size())
	world.corpses._scan = 0.0
	await _frames(3)
	check(world.corpses.record(bag["key"]).is_empty() and game.markers.on_planet(game.planet, "death").is_empty(), "the emptied bag and its marker are gone")
	await _frames(60)

## Bodies: a killed animal leaves a carcass where it fell, saved with its chunk, that is
## butchered for meat, hide and bone; a dead person's body holds their gear and purse.
func _corpses(game, world, player, kc: Creature) -> void:
	_make_room(game)
	var label := kc.label()
	var at := kc.global_position
	kc.hp = 1.0
	Ragdoll.mark_hit(kc, at + Vector3(0, 0.8, 0), Vector3(1, 0.1, 0), 40.0)
	world.fauna.player_hit(kc, 10.0)
	await _frames(3)
	check(not is_instance_valid(kc), "the killed animal stops being a live creature")
	var found := {}
	for b in world.corpses.near(at, 4.0):
		if b["rec"]["kind"] == "animal" and b["rec"]["name"] == label:
			found = b
	check(not found.is_empty(), "a carcass lies where the %s fell" % label)
	if found.is_empty():
		return
	var key: String = found["key"]
	var cr = world.corpses._shown[key]["node"]
	check(cr is Creature and cr.as_corpse and cr._body == null, "the carcass is drawn, with no hit box")
	if cr is Creature and cr._kit != null and not cr._kit.procedural():
		check(cr._kit._current == "Death", "a kit carcass lies in its death pose")
	if cr is Creature and cr._kit != null and not cr._kit.procedural():
		# It falls limp, comes to rest, and the pose it lies in is kept with it. (The
		# rest of the pack can't hurt you while you watch: later checks need your gear.)
		var god: bool = game.cheats["god"]
		game.cheats["god"] = true
		for i in 900:
			if world.corpses.record(key).has("rag"):
				break
			await physics_frame
		game.cheats["god"] = god
		var rag = world.corpses.record(key).get("rag")
		var sk: Skeleton3D = cr._kit.skeleton()
		check(rag is PackedFloat32Array and rag.size() == sk.get_bone_count() * 7, "the carcass falls as a ragdoll and keeps the pose it settled in")
		check(world.corpses.record(key).get("c") is Vector3, "the carcass remembers where its body came to rest")
		if rag is PackedFloat32Array:
			world.corpses._hide(key)
			world.corpses._scan = 0.0
			await _frames(3)
			var again = world.corpses._shown.get(key, {}).get("node")
			var sk2: Skeleton3D = again._kit.skeleton() if again is Creature and again._kit else null
			var back := Ragdoll.snapshot(sk2) if sk2 else PackedFloat32Array()
			var same: bool = back.size() == rag.size()
			for i in back.size():
				same = same and absf(back[i] - rag[i]) < 0.0001
			check(same, "drawn again, the carcass lies exactly as it fell")
			cr = again
	check(Corpses.use_of(found["rec"])[0] == "carcass", "a fresh carcass is held to butcher")
	var cn: ChunkNode = world.corpses._shown[key]["cn"]
	game.flush_chunks()
	var saved = game.store.load_chunk(int(cn.data["cx"]), int(cn.data["cz"]))
	check(saved is Dictionary and saved.get("corpses", {}).has(world.corpses._shown[key]["id"]), "the carcass is saved with its chunk")
	# What the hunt and the guard's body hand over, and the speeder after, need room.
	_make_room(game, 14)
	var bone0: int = game.inventory.count("bone")
	world.corpses.butcher(key, ItemDB.make("skinning_knife", 1, 1.0, {}))
	check(game.inventory.count("bone") > bone0, "butchering gives bone")
	check(world.corpses.record(key).get("butchered", false), "the carcass is marked butchered")
	world.corpses._scan = 0.0
	await _frames(3)
	check(world.corpses.record(key).is_empty(), "a picked-clean carcass is gone")
	# A guard, killed: their body keeps their armour, things and purse.
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var rec := NPCGen.person(r, Eras.MEDIEVAL, 0, 9999, 9999)
	rec["job"] = "guard"
	rec["home"] = Vector2(at.x, at.z)
	rec["work"] = Vector2(at.x, at.z)
	rec["pos"] = at
	var n := NPC.new()
	n.setup(rec, {"sx": 9999, "sz": 9999, "name": "Testford", "npcs": [rec]}, world.npcs)
	world.add_child(n)
	await _frames(2)
	var purse := int(rec["purse"])
	var gear_n: int = rec["gear"].size()
	world.corpses.add_person(n)
	n.queue_free()
	world.corpses._scan = 0.0
	await _frames(3)
	var body := {}
	for b in world.corpses.near(at, 4.0):
		if b["rec"]["kind"] == "person":
			body = b
	check(not body.is_empty(), "a dead person leaves a body")
	if body.is_empty():
		return
	check(gear_n > 0 and Corpses.still_worn(body["rec"]).size() == gear_n, "the body still wears its armour (%d pieces)" % gear_n)
	check(int(body["rec"]["purse"]) == purse and int(rec["purse"]) == 0, "the purse is on the body")
	var menus = world.menus
	menus.open_corpse(world.corpses, body["key"])
	check(menus._mode == "corpse", "searching a body opens it")
	var money0: int = game.money
	var m: int = menus._take_purse()
	Storage.transfer_all(menus._store, game.inventory)
	menus._corpse_changed(m)
	check(game.money == money0 + purse, "taking the purse pays its Marks")
	check(Corpses.still_worn(world.corpses.record(body["key"])).is_empty(), "taken armour comes off the body")
	if menus._mode != "":
		menus.close()

## Guns: a shot flies to an animal that has walked away from where it spawned and hurts
## it; the magazine empties and a reload takes a fresh power cell.
func _guns(game, world, player, kc: Creature, slot: int) -> void:
	_make_room(game)
	var cells0: int = game.inventory.count("power_cell")
	game.give(ItemDB.make("power_cell", 2, 1.0, {}))
	var gun := ItemDB.make("pulse_pistol", 1, 1.0, {})
	gun["charge"] = 2
	game.inventory.set_slot(slot, gun)
	player.select(slot)
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	fwd.y = 0.0
	# Held still (as in a trap) so it can't wander off the line of fire on a slow machine.
	kc.held_for = 3.0
	kc.global_position = player.global_position + fwd.normalized() * 12.0
	kc.global_position.y = world.vehicles.ground(kc.global_position.x, kc.global_position.z)
	await _frames(3)
	var aim_at: Vector3 = kc.global_position + Vector3(0, float(kc.p["size"]) * 0.45, 0)
	var d: Vector3 = (aim_at - player.camera.global_position).normalized()
	player.set_state({"pos": player.global_position, "yaw": atan2(-d.x, -d.z), "pitch": asin(d.y), "slot": slot, "view": 1})
	await _frames(2)
	var hp_was := kc.hp
	kc.hp = 10000.0 # tough enough not to die of it
	var hp0 := kc.hp
	player._cooldown = 0.0
	player.gunplay.ads = 1.0
	player.gunplay.bloom = 0.0
	player._trigger_held = false
	player.use_held()
	check(int(gun.get("charge", 0)) == 1, "firing spends a round from the magazine")
	check(player.gunplay._shots.size() == 1, "the shot is in flight, not an instant hit")
	await _frames(30)
	check(kc.hp < hp0, "a gunshot hits an animal away from its spawn point (%.0f -> %.0f hp)" % [hp0, kc.hp])
	kc.held_for = 0.0
	# Headshots: the upper front of the body box counts as the head and takes double.
	var cs: CollisionShape3D = kc._body.get_child(0)
	var bs: Vector3 = (cs.shape as BoxShape3D).size
	var head_pt: Vector3 = kc._body.to_global(cs.position + Vector3(0, bs.y * 0.35, bs.z * 0.4))
	var body_pt: Vector3 = kc._body.to_global(cs.position + Vector3(0, -bs.y * 0.2, -bs.z * 0.2))
	check(kc.is_head(head_pt) and not kc.is_head(body_pt), "an animal's head is the upper front of its body")
	var marks: Array = []
	var on_mark := func(k: String): marks.append(k)
	player.hit_marker.connect(on_mark)
	var pd: Dictionary = ItemDB.stats(gun)
	var h0 := kc.hp
	player.ranged_hit(gun, pd, {"collider": kc._body, "position": body_pt}, body_pt)
	var body_dmg: float = h0 - kc.hp
	h0 = kc.hp
	player.ranged_hit(gun, pd, {"collider": kc._body, "position": head_pt}, head_pt)
	var head_dmg: float = h0 - kc.hp
	check(head_dmg > body_dmg * 1.8, "a headshot does double damage (%.0f vs %.0f)" % [head_dmg, body_dmg])
	check(marks.size() >= 2 and marks[-2] == "hit" and marks[-1] == "head", "hits flash a hit marker, headshots a headshot marker (%s)" % str(marks))
	player.hit_marker.disconnect(on_mark)
	gun["charge"] = 0
	player._cooldown = 0.0
	player._trigger_held = false
	player.use_held()
	check(player.gunplay.reloading(), "pulling the trigger on an empty magazine starts a reload")
	# Reloads run on physics time, which headless frames outpace.
	await create_timer(player.gunplay.reload_total + 0.5).timeout
	check(not player.gunplay.reloading() and int(gun.get("charge", 0)) == player.gunplay.mag_size("pulse_pistol"), "the reload fills the magazine (%d)" % int(gun.get("charge", 0)))
	check(game.inventory.count("power_cell") == cells0 + 1, "the reload uses one power cell")
	# The plasma drill: held steady (no swing), a beam that burns the animal tick by tick.
	game.inventory.set_slot(slot, ItemDB.make("pickaxe_plasma", 1, 1.0, {}))
	player.select(slot)
	await _frames(2)
	var hp_b := kc.hp
	for n in 3:
		player._cooldown = 0.0
		player.use_held()
		await _frames(1)
	check(player.viewmodel._swing_t >= 1.0, "the plasma drill does not swing")
	var burnt: float = hp_b - kc.hp
	check(burnt > 5.0 and burnt < 60.0, "the plasma drill's beam burns the animal a little each tick (%.1f hp over 3 ticks)" % burnt)
	check(player.gunplay._beam_node != null and player.gunplay._beam_node.visible, "the beam shows while the drill fires")
	# The frontier (pack B): a shotgun throws a cloud of pellets; a bear trap catches.
	await _frames(40)
	var sg := ItemDB.make("double_shotgun", 1, 1.0, {})
	sg["charge"] = 2
	game.inventory.set_slot(slot, sg)
	player.select(slot)
	await _frames(2)
	player._cooldown = 0.0
	player._trigger_held = false
	var before_shots: int = player.gunplay._shots.size()
	player.use_held()
	check(player.gunplay._shots.size() - before_shots == int(ItemDB.def("double_shotgun")["pellets"]) and int(sg["charge"]) == 1, "a shotgun blast is %d pellets for one shell" % (player.gunplay._shots.size() - before_shots))
	await _frames(30)
	# Ammunition (pack E): a speed loader fills a revolver in one go, steel-core first.
	var rv := ItemDB.make("revolver_six", 1, 1.0, {})
	rv["charge"] = 0
	game.inventory.set_slot(slot, rv)
	player.select(slot)
	game.give(ItemDB.make("speed_loader", 1, 1.0, {}))
	game.give(ItemDB.make("rounds_ap", 8, 1.0, {}))
	await _frames(2)
	check(player.gunplay.start_reload(rv), "the revolver starts loading")
	await create_timer(player.gunplay.reload_total + 0.4).timeout
	check(int(rv["charge"]) == 6 and rv.get("loaded", "") == "rounds_ap" and game.inventory.count("rounds_ap") == 2, "a speed loader fills the cylinder at once, steel-core first (%d)" % int(rv["charge"]))
	game.inventory.remove_type("rounds_ap", 99)
	game.inventory.remove_type("speed_loader", 1)
	await _frames(30)
	game.inventory.set_slot(slot, ItemDB.make("bear_trap", 2, 1.0, {}))
	player.select(slot)
	await _frames(2)
	player._cooldown = 0.0
	player.use_held()
	check(player.traps.count() == 1 and game.inventory.count("bear_trap") == 1, "a bear trap is set at your feet")
	# Well away from the trap at your feet (it may have come for you), so only the trap
	# set under it can catch it.
	kc.global_position = player.global_position + Vector3(5, 0, 0)
	var hp_t := kc.hp
	player.traps.add("bear_trap", kc.global_position)
	await create_timer(0.8).timeout
	check(kc.hp < hp_t and kc.held_for > 0.0 and player.traps.count() == 1, "the trap snaps shut on the animal and holds it (%.0f -> %.0f hp)" % [hp_t, kc.hp])
	player.traps.from_data([])
	kc.held_for = 0.0
	kc.hp = hp_was
	# The sci-fi age (pack C): a turret shoots the animal; defib paddles catch a fall; a
	# beacon marks the map.
	kc.hp = 1000.0
	player.traps.add("turret_deploy", kc.global_position + Vector3(3, 0, 0))
	var hp_u := kc.hp
	await create_timer(0.6).timeout
	check(kc.hp < hp_u and player.traps.count() == 1 and int(player.traps.to_data()[0]["shots"]) < int(ItemDB.def("turret_deploy")["trap"]["shots"]), "a turret fires at the animal (%.0f -> %.0f hp)" % [hp_u, kc.hp])
	player.traps.from_data([])
	kc.hp = hp_was
	game.inventory.set_slot(slot, ItemDB.make("defibrillator", 1, 1.0, {}))
	game.set_health(0.0, "test")
	check(not game.dead and game.health > 1.0 and game.inventory.count("defibrillator") == 0, "defib paddles bring you back (%.0f hp)" % game.health)
	game.set_health(game.max_health())
	var marks0: int = game.markers.count_kind("pin")
	game.inventory.set_slot(slot, ItemDB.make("beacon_nav", 2, 1.0, {}))
	player.select(slot)
	await _frames(2)
	player._cooldown = 0.0
	player.use_held()
	check(game.markers.count_kind("pin") == marks0 + 1 and game.inventory.count("beacon_nav") == 1, "a nav beacon marks the map")
	# The alien endgame (pack D): an implant is fitted for good, once.
	var str0: int = game.stats.attrs["str"]
	game.inventory.set_slot(slot, ItemDB.make("implant_arm", 1, 1.0, {}))
	player.select(slot)
	await _frames(2)
	player._cooldown = 0.0
	player.use_held()
	check(game.stats.attrs["str"] == str0 + 1 and game.inventory.count("implant_arm") == 0, "an arm implant is fitted and makes you stronger")
	game.stats.attrs["str"] = str0
	game.stats.implants.clear()
	game.inventory.set_slot(slot, null)

## Village houses are open: walking at a house's door takes you inside onto its floor,
## and its walls keep you in.
## Relics and markers are used, not broken: a xenolith circle wakes once with gifts and
## then restores you once a day, a beacon calls down a supply pod and marks a settlement,
## runes are read once, a crystal recharges your flashlight.
func _relics(game, streamer: ChunkStreamer, player) -> void:
	var rc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(player.global_position))
	var at := func(dx: float, dz: float) -> Vector3:
		var lx := clampf(player.global_position.x - rc.position.x + dx, 4.0, 60.0)
		var lz := clampf(player.global_position.z - rc.position.z + dz, 4.0, 60.0)
		return Vector3(lx, ChunkGenerator.height_at(rc.data, lx, lz), lz)
	var day0: float = game.day
	var ruin: Dictionary = rc.add_object("alien_ruin", at.call(0.0, -12.0), 0.0, Eras.SCIFI, {})
	check(Wonders.use_of(ruin, game.day).get("verb", "").begins_with("Wake"), "a sleeping relic offers to wake")
	var items_before := 0
	for i in Inventory.SIZE:
		if game.inventory.get_slot(i) != null:
			items_before += int(game.inventory.get_slot(i)["qty"])
	var xp_before: int = game.stats.xp + game.stats.level * 100000
	game.set_health(30.0)
	var msg := WonderEffects.apply(ruin, rc, player)
	var items_after := 0
	for i in Inventory.SIZE:
		if game.inventory.get_slot(i) != null:
			items_after += int(game.inventory.get_slot(i)["qty"])
	check(ruin["st"].get("woke", false) and msg.contains("wakes"), "waking the relic (%s)" % msg)
	check(game.health >= game.stats.max_health() - 0.01, "the relic restores you")
	check(items_after > items_before and game.stats.xp + game.stats.level * 100000 > xp_before, "it gives gifts and experience (%d -> %d items)" % [items_before, items_after])
	check(Wonders.use_of(ruin, game.day).is_empty(), "and nothing more until tomorrow")
	player.damage_object(rc, ruin, 5000.0, 1.0)
	check(not ruin["st"].get("gone", false) and Durability.health_left(ruin) >= Durability.max_hp(ruin), "a relic can't be broken")
	game.day = day0 + 1.0
	check(Wonders.use_of(ruin, game.day).get("verb", "").begins_with("Draw"), "a day later it can restore you again")
	game.day = day0
	var beacon: Dictionary = rc.add_object("beacon", at.call(10.0, -12.0), 0.0, Eras.SCIFI, {})
	var objs_before: int = rc.data["objects"].size()
	var pins_before: int = game.markers.on_planet(game.planet).size()
	msg = WonderEffects.apply(beacon, rc, player)
	var pod := {}
	for i in range(objs_before, rc.data["objects"].size()):
		if rc.data["objects"][i]["t"] == "supply_pod":
			pod = rc.data["objects"][i]
	check(beacon["st"].get("lit", false) and not pod.is_empty() and not pod["st"].get("loot", []).is_empty(), "lighting a beacon calls down a stocked supply pod (%s)" % msg)
	check(game.markers.on_planet(game.planet).size() == pins_before + 1, "and marks the nearest settlement on the atlas")
	var stone: Dictionary = rc.add_object("standing_stone", at.call(-10.0, -12.0), 0.0, Eras.MEDIEVAL, {})
	msg = WonderEffects.apply(stone, rc, player)
	check(stone["st"].get("read", false) and Wonders.use_of(stone, game.day).is_empty(), "runes are read once (%s)" % msg)
	_make_room(game)
	game.give(ItemDB.make("flashlight_dead", 1, 1.0, {}))
	var crystal: Dictionary = rc.add_object("crystal_shard", at.call(-10.0, 0.0), 0.0, Eras.FANTASY, {})
	msg = WonderEffects.apply(crystal, rc, player)
	check(game.inventory.count("flashlight_dead") == 0 and game.inventory.count("flashlight") >= 1, "a crystal recharges a dead flashlight (%s)" % msg)
	var star: Dictionary = rc.add_object("star_wreck", at.call(10.0, 0.0), 0.0, Eras.SCIFI, {})
	var scrap0: int = game.inventory.count("alloy_scrap")
	msg = WonderEffects.apply(star, rc, player)
	check(game.inventory.count("alloy_scrap") > scrap0 and Wonders.use_of(star, game.day).is_empty(), "a wrecked starship can be salvaged once a day (%s)" % msg)
	# Out of the way of what comes next.
	for o in [ruin, beacon, pod, stone, crystal, star]:
		if not o.is_empty():
			rc.remove_object(o["i"])
	await _frames(2)

## Hidden finds: the sword won't come for a weak arm and comes once for a strong one (the
## stone then stands empty), the bottle's letter is a treasure map and the bottle is gone,
## the gnome ring only wakes after dark, and the tiny door gives once then answers daily.
func _easter_eggs(game, streamer: ChunkStreamer, player) -> void:
	var rc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(player.global_position))
	var at := func(dx: float, dz: float) -> Vector3:
		var lx := clampf(player.global_position.x - rc.position.x + dx, 4.0, 60.0)
		var lz := clampf(player.global_position.z - rc.position.z + dz, 4.0, 60.0)
		return Vector3(lx, ChunkGenerator.height_at(rc.data, lx, lz), lz)
	_make_room(game)
	var day0: float = game.day
	var str0: int = game.stats.attrs["str"]
	# Finds pay experience; put the levels back after so later checks start where they expect.
	var stats0: Dictionary = game.stats.to_data()
	var sword: Dictionary = rc.add_object("sword_stone", at.call(0.0, 12.0), 0.0, Eras.MEDIEVAL, {})
	game.stats.attrs["str"] = 0
	game.buffs.erase("strength")
	var msg := WonderEffects.apply(sword, rc, player)
	check(not sword["st"].get("drawn", false) and msg.contains("stronger arm"), "a weak arm can't draw the sword (%s)" % msg)
	game.stats.attrs["str"] = EasterEggs.SWORD_STR
	var swords0: int = game.inventory.count("sword_iron")
	msg = WonderEffects.apply(sword, rc, player)
	check(sword["st"].get("drawn", false) and game.inventory.count("sword_iron") == swords0 + 1, "a strong arm draws it (%s)" % msg)
	var drawn := {}
	for i in Inventory.SIZE:
		var it = game.inventory.get_slot(i)
		if it != null and it["type"] == "sword_iron" and int(it.get("rarity", 0)) == 4:
			drawn = it
	check(not drawn.is_empty() and String(drawn["name"]) != "", "it is a named legendary blade (%s)" % drawn.get("name", ""))
	check(Wonders.use_of(sword, game.day).is_empty() and ObjectLibrary.mesh_key(sword) == "sword_stone~drawn", "and the stone stands empty")
	game.stats.attrs["str"] = str0
	var bottle: Dictionary = rc.add_object("msg_bottle", at.call(4.0, 12.0), 0.0, Eras.MEDIEVAL, {})
	var maps0: int = game.inventory.count("treasure_map")
	var hunts0: int = game.treasure.size()
	msg = WonderEffects.apply(bottle, rc, player)
	await _frames(2)
	check(bottle["st"].get("gone", false) and (game.inventory.count("treasure_map") > maps0 or game.treasure.size() > hunts0), "the bottle holds a treasure map and is gone (%s)" % msg)
	var ring: Dictionary = rc.add_object("gnome_ring", at.call(-6.0, 12.0), 0.0, Eras.MEDIEVAL, {})
	game.day = floor(day0) + 0.5
	msg = WonderEffects.apply(ring, rc, player)
	check(not ring["st"].get("used", false) and msg.contains("sun"), "the gnome ring sleeps by day (%s)" % msg)
	game.day = floor(day0) + 0.95
	msg = WonderEffects.apply(ring, rc, player)
	check(ring["st"].get("used", false) and game.buffs.has("inspired"), "and wakes after dark (%s)" % msg)
	var door: Dictionary = rc.add_object("tiny_door", at.call(-6.0, 6.0), 0.0, Eras.MEDIEVAL, {})
	var money0: int = game.money
	msg = WonderEffects.apply(door, rc, player)
	check(game.money > money0 and EasterEggs.use_of(door, game.day).is_empty(), "the tiny door pays once (%s)" % msg)
	game.day += 1.0
	check(not EasterEggs.use_of(door, game.day).is_empty(), "and answers again the next day")
	var camp: Dictionary = rc.add_object("lost_camp", at.call(8.0, 4.0), 0.0, Eras.MEDIEVAL, {})
	msg = WonderEffects.apply(camp, rc, player)
	check(camp["st"].get("used", false) and msg.contains("journal"), "the explorer's journal reads (%s)" % msg)
	check(game.discovery.get("secrets", {}).size() >= 5, "the secrets you found are counted")
	game.day = day0
	game.stats.level = int(stats0["level"])
	game.stats.xp = stats0["xp"]
	game.stats.points = int(stats0["points"])
	for o in [sword, ring, door, camp]:
		rc.remove_object(o["i"])
	await _frames(2)

func _walk_into_house(game, world, streamer: ChunkStreamer, player) -> void:
	var gen := ChunkGenerator.new(game.seed, game.store.has_rivers())
	var here: Vector3 = player.global_position
	var best := {}
	var bd := INF
	var cell := int(floor(here.x / ChunkGenerator.SETTLEMENT_CELL))
	var cellz := int(floor(here.z / ChunkGenerator.SETTLEMENT_CELL))
	for sz in range(cellz - 4, cellz + 5):
		for sx in range(cell - 4, cell + 5):
			var s := gen.settlement_at(sx, sz)
			if s.is_empty():
				continue
			for it in gen.settlement_layout(s):
				if KitHouse.has(it["t"]):
					var d := Vector2(here.x, here.z).distance_to(it["p"])
					if d < bd:
						bd = d
						best = it
	check(not best.is_empty(), "found a village house")
	if best.is_empty():
		return
	var t: String = best["t"]
	var yaw: float = best["yaw"]
	var out := Vector3(sin(yaw), 0, cos(yaw))
	var dims := KitHouse.size_of(t)
	var hp := Vector3(best["p"].x, 0, best["p"].y)
	var stand := hp + out * (dims.z * 0.5 + 1.0)
	for i in 600:
		player.global_position = Vector3(stand.x, 400, stand.z)
		await _frames(1)
		if streamer.is_ready_at(stand):
			break
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(stand))
	stand.y = ChunkGenerator.height_at(c.data, stand.x - c.position.x, stand.z - c.position.z) + 0.1
	player.set_state({"pos": stand, "yaw": atan2(out.x, out.z), "pitch": 0.0, "slot": 0})
	# The body turns to the new heading over a few frames; let it settle on the spot.
	for i in 3:
		await _frames(20)
		player.global_position = stand
		player.velocity = Vector3.ZERO
	var hc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(hp))
	var floor_y := ChunkGenerator.height_at(hc.data, hp.x - hc.position.x, hp.z - hc.position.z) - KitHouse.SINK + KitHouse.FLOOR
	Input.action_press("move_forward")
	for i in 240:
		await physics_frame
	var lp: Vector3 = (player.global_position - hp).rotated(Vector3.UP, -yaw)
	var inside := absf(lp.x) < dims.x * 0.5 - 0.5 and absf(lp.z) < dims.z * 0.5 - 0.5
	check(inside, "walking at the door of a %s takes you inside (%.1f, %.1f)" % [t, lp.x, lp.z])
	check(absf(player.global_position.y - floor_y) < 0.4, "you stand on the house floor (%.2f m off)" % (player.global_position.y - floor_y))
	# Keep walking: the back wall or the furniture stops you.
	for i in 180:
		await physics_frame
	Input.action_release("move_forward")
	lp = (player.global_position - hp).rotated(Vector3.UP, -yaw)
	check(absf(lp.x) < dims.x * 0.5 and lp.z > -dims.z * 0.5 + 0.2, "the walls keep you in (%.1f, %.1f)" % [lp.x, lp.z])
	var lit := false
	for b in hc.get_children():
		if b is StaticBody3D:
			for l in b.get_children():
				lit = lit or l is OmniLight3D
	check(lit, "the hearth lights the room")
	var room := false
	for mmi in hc.get_children():
		room = room or (String(mmi.name).begins_with("Rooms_") and String(mmi.name).ends_with("_in") and mmi.get_child_count() > 0)
	check(room, "the room is furnished")
	# The house's chest: walk up to it and open it.
	var chest := {}
	var chest_c: ChunkNode = null
	for k in streamer.chunks:
		var cn: ChunkNode = streamer.chunks[k]
		for o in cn.data["objects"]:
			if o["st"].get("inside", "") == t and (cn.position + o["p"]).distance_to(hp + Vector3(0, (cn.position + o["p"]).y, 0)) < 4.0:
				chest = o
				chest_c = cn
	check(not chest.is_empty() and chest["t"] == "chest" and not chest["st"]["opened"], "the %s has a chest to loot" % t)
	if not chest.is_empty():
		await _open_inside(player, chest_c, chest)

## Walks up to a cache inside a room, as a player would, and opens it.
func _open_inside(player, c: ChunkNode, o: Dictionary) -> void:
	var f := Vector3(sin(o["r"]), 0, cos(o["r"]))
	var cw: Vector3 = c.position + o["p"]
	var stand := cw + f * 1.3
	player.set_state({"pos": stand + Vector3(0, 0.1, 0), "yaw": atan2(f.x, f.z), "pitch": -0.45, "slot": 0})
	await _frames(20)
	check(player.focus.get("kind", "") == "cache" and player.focus.get("i", -1) == o["i"], "facing the %s in the %s offers to open it (%s)" % [o["t"], o["st"]["inside"], player.focus.get("verb", "nothing")])
	# Town chests may be locked: the lockpicking minigame opens; on the sweet spot it gives
	# and the chest is looted straight away.
	if Player.lock_of(o) > 0:
		var game = root.get_node("/root/Game")
		if game.inventory.count("lockpick") <= 0:
			game.inventory.add(ItemDB.make("lockpick", 3, 1.0, {}))
		player.interact()
		var ui: LockpickUI = player.get_tree().get_first_node_in_group("lockpick_ui")
		check(ui != null and ui.is_open() and player.ui_open, "a locked chest opens the lockpicking minigame")
		if ui and ui.is_open():
			ui._game.set_pick(ui._game.sweet)
			var r := ""
			for i in 200:
				r = ui._game.step(1.0 / 60.0, true)
				if r != "":
					break
			check(r == "open", "on the sweet spot the lock turns all the way")
			ui._opened()
			check(Player.lock_of(o) <= 0 and not ui.is_open() and not player.ui_open, "the lock is open and the minigame closes")
	else:
		player.interact()
	check(o["st"].get("opened", false) or (o["st"]["loot"] as Array).size() < 2, "interact loots it")
	# Looting in town may have been seen; let the law forget so guards don't crowd later checks.
	root.get_node("/root/Game").crime = Crime.new()

## Walk-in rooms beyond village houses: set each down near the player, walk in through
## its door, stand on its floor, see it lit, and open the loot inside.
func _rooms(game, streamer: ChunkStreamer, player) -> void:
	var rc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(player.global_position))
	# The flattest spot in the chunk, as a settlement's ground would be.
	var lp := Vector3.ZERO
	var rough := INF
	for gz in range(14, 51, 4):
		for gx in range(14, 51, 4):
			var crowded := false
			for o in rc.data["objects"]:
				if not o["st"].get("gone", false) and Vector2(o["p"].x - gx, o["p"].z - gz).length() < 10.0:
					crowded = true
			if crowded:
				continue
			var h0 := ChunkGenerator.height_at(rc.data, gx, gz)
			var worst := 0.0
			for dz in range(-7, 8, 2):
				for dx in range(-7, 8, 2):
					worst = maxf(worst, absf(ChunkGenerator.height_at(rc.data, gx + dx, gz + dz) - h0))
			if worst < rough:
				rough = worst
				lp = Vector3(gx, h0, gz)
	print("  rooms stand where the ground varies %.2f m" % rough)
	for t in ["ops_tower", "hab_dome", "mushroom_house", "castle_keep", "watchtower", "castle_tower"]:
		var era := Eras.SCIFI if t in ["ops_tower", "hab_dome"] else (Eras.FANTASY if t == "mushroom_house" else Eras.MEDIEVAL)
		var n0: int = rc.data["objects"].size()
		var room: Dictionary = rc.add_object(t, lp, 0.0, era, {})
		# Rooms are stocked as their chunk loads; this one arrived later.
		Interiors.stock(rc.data)
		rc.set_objects(ChunkNode.build_object_buffers(rc.data))
		for i in range(n0 + 1, rc.data["objects"].size()):
			rc._add_obj_body(rc.data["objects"][i])
		var door_x := 0.0
		var front := 0.0
		var fl := 0.0
		var deep := 0.0
		if Interiors.BOX.has(t):
			var b: Array = Interiors.BOX[t]
			door_x = b[5][0]
			front = (b[3] as Vector2).y
			fl = b[1]
			deep = (b[0] as Vector2).y
		elif Interiors.ROUND.has(t):
			var p: Array = Interiors.ROUND[t]
			front = p[0]
			fl = p[5]
			deep = float(p[0]) - float(p[2])
		else:
			front = 5.1
			fl = Interiors.DOME[3]
			deep = 3.6
		var w: Vector3 = rc.position + lp
		var stand := w + Vector3(door_x, 0, front + 1.2)
		player.set_state({"pos": stand + Vector3(0, 0.3, 0), "yaw": 0.0, "pitch": 0.0, "slot": 0})
		for i in 3:
			await _frames(15)
			player.global_position = stand + Vector3(0, 0.3, 0)
			player.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		for i in 150:
			await physics_frame
		Input.action_release("move_forward")
		await _frames(10)
		var l: Vector3 = player.global_position - w
		check(l.z < deep - 0.4 and l.z > -deep, "walking in at the door of a %s takes you inside (%.1f, %.1f, %.2f)" % [t, l.x, l.z, l.y])
		var floor_y: float = w.y - Interiors.SINK + fl
		check(absf(player.global_position.y - floor_y) < 0.45, "you stand on the %s floor (%.2f m off)" % [t, player.global_position.y - floor_y])
		var lit := false
		for b in rc.get_children():
			if b is StaticBody3D and b.get_meta("obj", -1) == room["i"]:
				for c in b.get_children():
					lit = lit or c is OmniLight3D
		check(lit, "the %s is lit inside" % t)
		var cache: Dictionary = rc.data["objects"][rc.data["objects"].size() - 1]
		check(cache["st"].get("inside", "") == t, "the %s is stocked" % t)
		if Lore.has(t):
			await _use_lore(game, player, rc, room)
		if Interiors.TOWER.has(t):
			await _climb(player, w, t)
		await _open_inside(player, rc, cache)
		rc.remove_object(cache["i"])
		rc.remove_object(room["i"])
		await _frames(2)

## The room's first readable prop (a terminal, bookcase, book...): look at it, Interact
## opens its page, and everything every room can show reads without loose placeholders.
func _use_lore(game, player, rc: ChunkNode, room: Dictionary) -> void:
	var at: Vector3 = rc.position + Lore.anchor(room, 0)
	var ctr: Vector3 = rc.position + room["p"]
	var d := Vector3(ctr.x - at.x, 0, ctr.z - at.z).normalized()
	var stand: Vector3 = at + d * 1.5
	stand.y = player.global_position.y
	var to: Vector3 = at - (stand + Vector3(0, 1.6, 0))
	player.set_state({"pos": stand, "yaw": atan2(-to.x, -to.z), "pitch": atan2(to.y, Vector2(to.x, to.z).length()), "slot": 0})
	player.velocity = Vector3.ZERO
	await _frames(30)
	var eye: Vector3 = player.head.global_position
	check(player.focus.get("kind", "") == "lore", "looking at the %s's %s offers to use it (focus: %s; score %.2f, in sight %s, %.2f m)" % [room["t"], Lore.spots(room["t"])[0][0],
		player.focus.get("verb", "nothing"), player._focus_score(eye, -player.camera.global_transform.basis.z, at), player._can_see(eye, at), eye.distance_to(at)])
	if player.focus.get("kind", "") == "lore":
		player.interact()
		await _frames(3)
		var ui = player.get_tree().get_first_node_in_group("lore_ui")
		check(ui != null and ui.is_open(), "Interact opens the %s's page" % room["t"])
		if ui != null and ui.is_open():
			check(String(ui._body.text).length() > 40, "the page has something to read")
			ui.close()
			await _frames(2)
		check(not player.ui_open, "stepping away gives the controls back")
	if room["t"] != "ops_tower":
		return
	# Reading everything gives XP and marks the atlas; later checks count on neither.
	var stats: Dictionary = game.stats.to_data()
	var marks: Dictionary = game.markers.to_data()
	var loose: Array = []
	var types: Array = Interiors.FURNISH.keys() + KitHouse.FURNISH.keys()
	for t in types:
		for era in Eras.COUNT:
			var o := {"t": t, "e": era, "p": room["p"], "r": 0.0, "s": 1.0, "i": 9000 + era, "st": {}}
			for k in Lore.spots(t).size():
				var e: Dictionary = Lore.read(o, rc, k, player.npcs)
				for pg in e["pages"]:
					if String(pg["text"]).contains("{") or String(pg["text"]).strip_edges() == "":
						loose.append("%s/%d/%d" % [t, era, k])
				for pg in e["pages"]:
					for a in pg.get("actions", []):
						if Lore.act(o, rc, k, a[0], player) == "":
							loose.append("%s/%d/%d action %s" % [t, era, k, a[0]])
	check(loose.is_empty(), "every readable prop reads cleanly in every era (%s)" % ", ".join(loose.slice(0, 6)))
	game.stats = Stats.from_data(stats)
	game.markers = Markers.from_data(marks)

## Climbs a tower's stair from the corner at its foot, flight by flight, turning on each
## landing, and walks out through the hatch onto the roof.
func _climb(player, w: Vector3, t: String) -> void:
	var fs := Interiors.flights(t)
	var c: float = (Interiors.BOX[t][0] as Vector2).x - Interiors.STAIR_W * 0.5
	var top: float = Interiors.BOX[t][4]
	var foot: Vector3 = fs[0][0]
	player.set_state({"pos": w + Vector3(-c, foot.y - Interiors.SINK + 0.1, c), "yaw": 0.0, "pitch": 0.0, "slot": 0})
	player.velocity = Vector3.ZERO
	await _frames(10)
	var yaws := [0.0, -PI / 2.0, PI, PI / 2.0, 0.0]
	for i in 5:
		player.set_state({"pos": player.global_position, "yaw": yaws[i], "pitch": 0.0, "slot": 0})
		# Walk until a wall stops you (a pack full of loot slows you down).
		Input.action_press("move_forward")
		var was: Vector3 = player.global_position
		for n in 60:
			await _frames(15)
			if player.global_position.distance_to(was) < 0.02:
				break
			was = player.global_position
		Input.action_release("move_forward")
		await _frames(5)
		var l: Vector3 = player.global_position - w
		if i < 4:
			var want: float = (fs[i][1] as Vector3).y - Interiors.SINK
			check(absf(l.y - want) < 0.3, "climbing flight %d of the %s takes you up a storey (%.2f m up, the landing at %.2f)" % [i + 1, t, l.y, want])
		else:
			check(absf(l.y - (top - Interiors.SINK)) < 0.2 and l.z < 0.0, "out through the hatch onto the %s's roof (%.1f, %.2f, %.1f)" % [t, l.x, l.y, l.z])

## v7 landforms colour the terrain through vertex data: a karst chunk's mesh carries
## pale limestone for every vertex, at every LOD.
func _check_landform_mesh() -> void:
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(2024)
	var at := Vector2.INF
	for iz in range(-25, 25):
		for ix in range(-25, 25):
			var p := g.field.site_pos(ix, iz)
			if at == Vector2.INF and g.field.site_landform(ix, iz) == WorldField.LF_KARST and g.field.landform_weights(p.x, p.y)[WorldField.LF_KARST] > 0.97:
				at = p
	check(at != Vector2.INF, "found a karst region")
	if at == Vector2.INF:
		return
	var ch := g.generate(int(floor(at.x / 64.0)), int(floor(at.y / 64.0)))
	for step in [1, 2, 4]:
		var arr := ChunkNode.build_terrain_arrays(ch, step)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var c0: PackedByteArray = arr[Mesh.ARRAY_CUSTOM0]
		var c2: PackedByteArray = arr[Mesh.ARRAY_CUSTOM2]
		var pale := 0
		for i in verts.size():
			pale += 1 if c0[i * 4 + 3] > 150 and c0[i * 4] > 140 else 0
		check(c0.size() == verts.size() * 4 and c2.size() == verts.size() * 4 and pale > verts.size() / 2,
			"karst terrain at LOD %d is pale limestone (%d of %d vertices)" % [step, pale, verts.size()])
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, ChunkNode.LOOK_FORMAT | ChunkNode.COVER_FORMAT)
		check(m.get_surface_count() == 1 and m.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0, "the LOD %d mesh takes the look" % step)

## The nearest level spot near `from` with nothing standing within 5 m, to stand on.
func _open_ground(streamer: ChunkStreamer, from: Vector3) -> Vector3:
	var best := Vector3.INF
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for j in range(4, 61, 4):
			for i in range(4, 61, 4):
				var h := ChunkGenerator.height_at(c.data, i, j)
				var wp := c.position + Vector3(i, h + 0.1, j)
				if h < ChunkGenerator.WATER_LEVEL + 0.8 or wp.distance_to(from) >= best.distance_to(from):
					continue
				var level := true
				for o in [Vector2(0, 0), Vector2(2.5, 0), Vector2(-1.5, 2.5), Vector2(0, -2.5), Vector2(2.5, 2.5)]:
					level = level and ChunkGenerator.slope_at(c.data, i + o.x, j + o.y) < 0.12
				if not level or ChunkGenerator.road_at(c.data, i, j) > 0.0:
					continue
				var clear := true
				for o in c.data["objects"]:
					if not o["st"].get("gone", false) and Vector2(o["p"].x - i, o["p"].z - j).length() < 5.0:
						clear = false
						break
				if clear:
					best = wp
	return best

func _map_unit_checks() -> void:
	var g := ChunkGenerator.new(31337, true)
	var ch := g.generate(2, -3)
	var tile := WorldMap.paint_tile(ch)
	check(tile.size() == WorldMap.CPX * WorldMap.CPX * 3, "a chunk paints a full tile")
	var distinct := {}
	for i in range(0, tile.size(), 3 * 37):
		distinct[Vector3i(tile[i], tile[i + 1], tile[i + 2])] = true
	check(distinct.size() > 8, "the painted land is shaded, not flat (%d colours)" % distinct.size())
	var m := WorldMap.new()
	m.open(WorldStore.memory(), {})
	m.paint(ch)
	check(m.textures(Vector2i(0, -1)).size() == 2, "the page holding the chunk has textures")
	var at := Vector2(2 * 64 + 32, -3 * 64 + 32)
	check(m.revealed(at.x, at.y) == 0.0, "fog until you have been there")
	m.reveal(at, 60.0)
	check(m.revealed(at.x, at.y) > 0.95, "the fog lifts where you stand")
	check(m.revealed(at.x + 25.0, at.y) > 0.9 and m.revealed(at.x + 200.0, at.y) == 0.0, "only nearby")
	# A circle across a page corner lifts the fog on every page it touches.
	m.reveal(Vector2(0, 0), 40.0)
	check(m.revealed(-5, -5) > 0.9 and m.revealed(5, 5) > 0.9 and m.revealed(-5, 5) > 0.9, "reveals cross page edges")
	# Ore deposits are remembered per chunk and forgotten when mined out.
	var orech := {}
	for k in [Vector2i(2, -3), Vector2i(0, 0), Vector2i(1, 1), Vector2i(-2, 4), Vector2i(5, 5), Vector2i(-6, -1), Vector2i(3, 7), Vector2i(8, -2)]:
		var c := g.generate(k.x, k.y)
		if c["objects"].any(func(o): return ObjectLibrary.kind(o["t"]) == "ore"):
			orech = c
			break
	check(not orech.is_empty(), "found a chunk with ore")
	if not orech.is_empty():
		var key := "%d,%d" % [orech["cx"], orech["cz"]]
		m.note_chunk(orech)
		check(m.ores.has(key) and int(m.ores[key][0]["n"]) > 0, "the map notes the ore in a chunk")
		for o in orech["objects"]:
			if ObjectLibrary.kind(o["t"]) == "ore":
				o["st"]["gone"] = true
		m.note_chunk(orech)
		check(not m.ores.has(key), "mined-out ore drops off the map")
	m.set_shown("cave", false)
	check(not m.shows("cave") and m.shows("town"), "filters hide one kind only")
	m.note_person({"id": "1_2_3", "name": "Ada Vale", "job": "smith", "work": Vector2(10, 20), "pos": Vector3.ZERO}, "Elmford")
	check(m.known("people").size() == 1 and m.known("people")[0]["town"] == "Elmford", "people you met are remembered")
	var mk := Markers.new()
	var pin := mk.add("Marker 1", 1, 2, 0)
	mk.edit(pin["id"], {"name": "  Iron here ", "color": 7, "icon": "mine"})
	check(pin["name"] == "Iron here" and pin["color"] == 7 and pin["icon"] == "mine", "a marker can be renamed, recoloured and given an icon")
	mk.edit(pin["id"], {"name": "", "icon": "nonsense"})
	check(pin["name"] == "Iron here" and pin["icon"] == "mine", "blank names and unknown icons are ignored")
	check(Markers.from_data(mk.to_data()).get_by_id(pin["id"])["icon"] == "mine", "marker edits are saved")

## Menus and the armour paper-doll (kept out of _run so its locals stay separate).
func _menu_checks(world, game, con) -> void:
	# Menus and the armour paper-doll: every screen builds, armour dropped on the body is
	# worn, the old piece lands in the slot the new one came from, and dragging it out
	# puts it in the chosen slot.
	var menus: GameMenus = world.menus
	var edit_pin: Dictionary = game.markers.add("Edit me", 0, 0, game.planet)
	AtlasView.selected = int(edit_pin["id"])
	for m in ["inventory", "craft", "character", "map", "pause"]:
		menus.open(m)
		await _frames(2)
		check(menus._panel != null and is_instance_valid(menus._panel), "%s screen builds" % m)
	menus.close()
	game.markers.remove(edit_pin["id"])
	AtlasView.selected = -1
	# What the test has looted so far can fill the pack: two helmets and a slot to drag
	# one into need room.
	for i in range(Inventory.SIZE - 1, -1, -1):
		if game.inventory.free_slots() >= 3:
			break
		game.inventory.set_slot(i, null)
	con.run("give helm_iron 1")
	con.run("give helm_elven 1")
	var hi := -1
	var he := -1
	for i in Inventory.SIZE:
		var it = game.inventory.get_slot(i)
		if it != null and it["type"] == "helm_iron": hi = i
		if it != null and it["type"] == "helm_elven": he = i
	check(hi >= 0 and he >= 0, "two helmets in the pack")
	check(game.equip(hi) and game.equipment["head"]["type"] == "helm_iron" and game.inventory.get_slot(hi) == null, "drop a helmet on the head to wear it")
	check(game.equip(he) and game.equipment["head"]["type"] == "helm_elven" and game.inventory.get_slot(he)["type"] == "helm_iron", "swapping helmets puts the old one where the new came from")
	var empty := -1
	for i in range(Inventory.SIZE - 1, Inventory.HOTBAR, -1):
		if game.inventory.get_slot(i) == null:
			empty = i
			break
	check(game.unequip_to("head", empty) and game.inventory.get_slot(empty)["type"] == "helm_elven" and not game.equipment.has("head"), "dragging armour off the body drops it in that slot")
	check(game.equip(empty) and game.equipment.has("head"), "wear it again")
	menus.open("inventory")
	await _frames(2)
	var dolls := 0
	for n in menus._panel.find_children("*", "", true, false):
		if n is GameMenus.Mannequin:
			dolls += 1
	check(dolls == 1, "inventory shows the body")
	menus.close()
	# Pack A items: a ring raises stamina, an elixir and a scroll last a while, a salve
	# heals over time.
	var find := func(t: String) -> int:
		for i in Inventory.SIZE:
			var it = game.inventory.get_slot(i)
			if it != null and it["type"] == t:
				return i
		return -1
	var st0: float = game.stats.max_stamina()
	con.run("give ring_silver 1")
	check(game.equip(find.call("ring_silver")) and game.equipment.has("ring") and game.stats.max_stamina() > st0, "a silver ring on a finger raises stamina")
	var dm0: float = game.stats.damage_mult()
	con.run("give elixir_strength 1")
	world.player.consume(find.call("elixir_strength"))
	check(game.has_buff("strength") and game.stats.damage_mult() > dm0 and find.call("elixir_strength") < 0, "an elixir of strength is drunk and makes you stronger")
	var ar0: float = game.armor()
	con.run("give scroll_blue 1")
	world.player.consume(find.call("scroll_blue"))
	check(game.has_buff("warded") and game.armor() > ar0, "a scroll of warding adds armour")
	game.set_health(40.0)
	con.run("give salve 1")
	world.player.consume(find.call("salve"))
	check(game.health > 40.0 and game.regen_left > 0.0, "a salve heals now and over time")
	game.save_player()
	check(game.store.load_player().get("buffs", {}).has("strength"), "timed effects are saved")
	# Mouse lock: the toggle frees the pointer, a menu keeps it free, closing restores it.
	Cursor.free = true
	Cursor.restore()
	menus.open("inventory")
	menus.close()
	check(Cursor.free and not Cursor.locked(), "a freed pointer stays free after a menu closes")
	Cursor.free = false
	Cursor.restore()
