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
	player.velocity = Vector3.ZERO # whatever speed it fell at while the ground streamed in
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
		# Until they ride at the surface (up to 15 s): a fixed wait caught a fast runner's
		# swimmer mid-bob now and then.
		var off := INF
		for i in 900:
			await physics_frame
			if i >= 120:
				var s := Water.surface_height(player.global_position.x, player.global_position.z, fmod(Time.get_ticks_msec() / 1000.0, 3600.0))
				off = player.global_position.y - (s - Swim.FLOAT_CHEST)
				if player.swimming and absf(off) < 0.6:
					break
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
	for i in game.inventory.capacity:
		var it = game.inventory.get_slot(i)
		if it != null and loot.has(it["type"]):
			game.inventory.set_slot(i, null)
	for i in range(game.inventory.capacity - 1, -1, -1):
		if game.inventory.free_slots() >= n:
			break
		game.inventory.set_slot(i, null)

## What is in the pack, for a failure message.
func _pack_list(game) -> String:
	var out: PackedStringArray = []
	for i in game.inventory.capacity:
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
	for i in game.inventory.capacity:
		var sl = game.inventory.get_slot(i)
		if sl != null and sl["type"] == "door_wood":
			di = i
	game.inventory.swap(di, 6)
	player.select(6)
	await _frames(3)
	check(player.builder.piece_id() == "door_wood", "holding a door starts hanging it")
	# Put away, the hands are empty and out of view; the slot's key takes it out again.
	player.holster(true)
	await _frames(3)
	player.viewmodel.sway(0.016, 0.0)
	check(player.held_item() == null and (player.viewmodel.arms == null or not player.viewmodel.arms.visible), "put away, nothing is held and no hands show")
	player.select(6)
	await _frames(3)
	check(player.held_item() != null and player.builder.piece_id() == "door_wood", "taking it out again holds the door")
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

## Power: a wood-gas generator cabled through a knife switch to a lamp lights it while it
## has fuel and the switch is closed; the cables cost Copper Wire and give it back.
func _power_checks(game, world, player: Player, pc: ChunkNode, lp: Vector3) -> void:
	var grid: PowerGrid = PowerGrid.current
	check(grid != null and grid.get_parent() == world, "the world runs a power grid")
	if grid == null:
		return
	var mk := func(id: String, at: Vector3) -> Dictionary:
		var st := {"by": "you", "day": 0.0, "owner": Doors.my_id(), "owner_name": "You"}
		Power.init_state(id, st)
		return pc.add_built(id, at, 0.0, st)
	_make_room(game, 4)
	var gen: Dictionary = mk.call("gen_woodgas", lp)
	var sw: Dictionary = mk.call("knife_switch", lp + Vector3(3, 1.5, 0))
	var lamp: Dictionary = mk.call("lamp_wall", lp + Vector3(6, 1.8, 0))
	game.give(ItemDB.make("copper_wire", 10, 1.0, game.origin_here("crafted", -1, pc.key)))
	var w0: int = game.inventory.count("copper_wire")
	check(grid.connect_pieces(pc, gen, pc, sw) == "" and grid.connect_pieces(pc, sw, pc, lamp) == "", "cables strung generator to switch to lamp")
	check(game.inventory.count("copper_wire") < w0, "cables use Copper Wire")
	var far: Dictionary = mk.call("lamp_wall", lp + Vector3(40, 1.8, 0))
	check(grid.connect_pieces(pc, gen, pc, far) != "", "a cable can't span 40 m")
	var lit := func() -> bool:
		var pn: PowerNode = pc.power_node(lamp["i"])
		return pn != null and pn._lit
	var wait := func(want: bool) -> bool:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			if lit.call() == want:
				return true
			await process_frame
		return lit.call() == want
	check(not await wait.call(true), "no fuel, no light")
	game.give(ItemDB.make("wood", 4, 1.0, game.origin_here("crafted", -1, pc.key)))
	var wood0: int = game.inventory.count("wood")
	grid.use_piece(pc, gen, false)
	check(float(gen["st"]["fuel"]) > 0.0 and game.inventory.count("wood") < wood0 and Power.is_on(gen), "the generator takes wood from the pack and starts (fuel %.0f, wood %d, on %s)" % [float(gen["st"]["fuel"]), game.inventory.count("wood"), Power.is_on(gen)])
	check(await wait.call(true), "the lamp lights")
	var line: Array = grid.describe(pc, lamp, true)
	check(" ".join(line).contains("Network: makes"), "the look-at panel reads out the network (%s)" % [str(line)])
	grid.use_piece(pc, sw, false)
	check(await wait.call(false), "opening the switch cuts the lamp off")
	grid.use_piece(pc, sw, false)
	check(await wait.call(true), "closing it lights the lamp again")
	grid.use_piece(pc, lamp, false)
	check(await wait.call(false), "the lamp switches off on its own")
	await _signal_checks(game, grid, player, pc, lp, gen, lamp, mk, lit, wait)
	await _defence_checks(game, world, grid, player, pc, lp, gen, mk)
	await _automation_checks(game, grid, player, pc, lp, gen, mk)
	var before: int = game.inventory.count("copper_wire")
	check(player.deconstruct(pc, sw) and sw["st"].get("gone", false), "the switch comes down")
	check(game.inventory.count("copper_wire") > before and Power.links(gen).is_empty(), "its cables come down with it, as wire")
	for o in [gen, lamp, far]:
		player.deconstruct(pc, o)
	for t in ["copper_wire", "signal_wire", "gen_woodgas", "lamp_wall", "knife_switch", "lever", "relay", "door_motor", "pressure_plate", "wall_door", "door_wood"]:
		game.inventory.remove_type(t, game.inventory.count(t))

## The logic layer: a lever works a lamp through a signal wire and a relay, a door motor
## opens and shuts a door on the lever, and a pressure plate senses you on it.
func _signal_checks(game, grid: PowerGrid, player: Player, pc: ChunkNode, lp: Vector3, gen: Dictionary, lamp: Dictionary, mk: Callable, lit: Callable, wait: Callable) -> void:
	_make_room(game, 6)
	game.give(ItemDB.make("signal_wire", 12, 1.0, game.origin_here("crafted", -1, pc.key)))
	game.give(ItemDB.make("copper_wire", 10, 1.0, game.origin_here("crafted", -1, pc.key)))
	grid.use_piece(pc, lamp, false) # back on
	check(await wait.call(true), "the lamp is lit again before the signal test")
	var lever: Dictionary = mk.call("lever", lp + Vector3(5, 1.4, 1))
	var s0: int = game.inventory.count("signal_wire")
	check(grid.connect_signal(pc, lever, pc, lamp) == "", "a signal wire runs from the lever into the lamp")
	check(game.inventory.count("signal_wire") < s0, "it uses Signal Wire")
	check(grid.connect_signal(pc, lamp, pc, lever) != "", "a lamp makes no signal to wire from")
	check(await wait.call(false), "with the lever off, the lamp it is wired to goes dark")
	grid.use_piece(pc, lever, false)
	check(Power.is_on(lever) and await wait.call(true), "pulling the lever lights it")
	grid.use_piece(pc, lever, false)
	check(await wait.call(false), "and pushing it back puts it out")
	check(" ".join(grid.describe(pc, lamp, false)).contains("Signal in: 1 wire"), "the lamp's look-at shows its signal wire")
	# A door motor by a door, powered from the generator, worked by the same lever.
	var dway: Dictionary = pc.add_built("wall_door", lp + Vector3(0, 0, 6), 0.0, {"by": "you", "day": 0.0})
	var dst := {"by": "you", "day": 0.0}
	Doors.init_state(dst)
	var door: Dictionary = pc.add_built("door_wood", dway["p"], 0.0, dst)
	var motor: Dictionary = mk.call("door_motor", dway["p"] + Vector3(1.4, 1.6, 0.1))
	var why: String = grid.connect_pieces(pc, gen, pc, motor)
	check(why == "", "the motor is cabled to the generator (%s)" % why)
	check(grid.connect_signal(pc, lever, pc, motor) == "", "and wired to the lever")
	check(not grid.door_by(pc.position + motor["p"]).is_empty(), "the motor finds the door beside it")
	await _frames(30)
	check(not Doors.is_open(door), "the door starts shut")
	grid.use_piece(pc, lever, false)
	var t0 := Time.get_ticks_msec()
	while not Doors.is_open(door) and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	check(Doors.is_open(door), "pulling the lever, the motor opens the door")
	grid.use_piece(pc, lever, false)
	t0 = Time.get_ticks_msec()
	while Doors.is_open(door) and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	check(not Doors.is_open(door), "and pushing it back shuts it")
	# A pressure plate under your feet, wired through a relay in the lamp's line.
	var plate: Dictionary = mk.call("pressure_plate", player.global_position - pc.position)
	t0 = Time.get_ticks_msec()
	while not grid._signal(PowerGrid.id_of(pc, plate)) and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	check(grid._signal(PowerGrid.id_of(pc, plate)), "standing on a pressure plate presses it (you %s, plate %s)" % [player.global_position, pc.position + plate["p"]])
	var lamp2: Dictionary = mk.call("lamp_wall", lp + Vector3(2, 1.8, 3))
	var relay: Dictionary = mk.call("relay", lp + Vector3(1, 1.5, 3))
	why = grid.connect_pieces(pc, gen, pc, relay)
	var why2: String = grid.connect_pieces(pc, relay, pc, lamp2)
	check(why == "" and why2 == "", "a relay cabled in the line to a second lamp (%s / %s)" % [why, why2])
	check(grid.connect_signal(pc, plate, pc, relay) == "", "the plate wired to the relay")
	var lit2 := func() -> bool:
		var pn: PowerNode = pc.power_node(lamp2["i"])
		return pn != null and pn._lit
	t0 = Time.get_ticks_msec()
	while not lit2.call() and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	check(Power.is_on(relay) and lit2.call(), "the plate closes the relay and the lamp beyond it lights")
	var sb: int = game.inventory.count("signal_wire")
	check(player.deconstruct(pc, lever), "the lever comes down")
	check(game.inventory.count("signal_wire") > sb and Signals.inputs(lamp).is_empty() and Signals.inputs(motor).is_empty(), "its signal wires come down with it, as Signal Wire")
	for o in [plate, relay, lamp2, motor, door, dway]:
		player.deconstruct(pc, o)

## A powered turret loads ammo and shoots an attacking animal it can see, and leaves a
## tame one alone; an alarm bell rings on its signal.
func _defence_checks(game, world, grid: PowerGrid, player: Player, pc: ChunkNode, lp: Vector3, gen: Dictionary, mk: Callable) -> void:
	_make_room(game, 4)
	game.give(ItemDB.make("copper_wire", 10, 1.0, game.origin_here("crafted", -1, pc.key)))
	game.give(ItemDB.make("wood", 6, 1.0, game.origin_here("crafted", -1, pc.key)))
	grid.use_piece(pc, gen, false) # top the generator up
	var tur: Dictionary = mk.call("auto_turret", lp + Vector3(-3, 0, -3))
	var why: String = grid.connect_pieces(pc, gen, pc, tur)
	check(why == "", "the turret is cabled to the generator (%s)" % why)
	game.give(ItemDB.make("rifle_cartridges", 20, 1.0, game.origin_here("crafted", -1, pc.key)))
	check(PowerGrid.verb(tur, false).begins_with("Load"), "with cartridges in the pack, Interact loads the turret")
	grid.use_piece(pc, tur, false)
	check(int(tur["st"].get("ammo", 0)) == 20 and game.inventory.count("rifle_cartridges") == 0, "it takes the cartridges (%d)" % int(tur["st"].get("ammo", 0)))
	check(" ".join(grid.describe(pc, tur, false)).contains("Ammo: 20"), "its look-at shows the ammo")
	# An animal held still in front of it: tame first, then attacking.
	var sp := 0
	while Creature.species(sp, Eras.MEDIEVAL)["kit"] == "":
		sp += 1
	var cr := Creature.new()
	var tw: Vector3 = pc.position + tur["p"]
	# Somewhere it can see 8 m off (the test's other pieces stand about).
	var spot := tw + Vector3(0, 0, -8)
	for a in 16:
		var p := tw + Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0)) * 8.0
		p.y = tw.y
		if grid._clear(tw + Vector3(0, 1.3, 0), p + Vector3(0, 0.6, 0), null):
			spot = p
			break
	cr.setup("test_turret_target", sp, Eras.MEDIEVAL, spot, world.fauna)
	world.fauna.add_child(cr)
	cr.p = cr.p.duplicate()
	cr.p["temper"] = "tame"
	cr.held_for = 1.0e6
	var scan0: float = world.fauna._scan
	world.fauna._scan = 1.0e9
	world.fauna._herds[Vector2i(99998, 99998)] = [cr]
	await _frames(3)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
	check(int(tur["st"]["ammo"]) == 20, "a turret leaves a tame animal alone")
	cr.p["temper"] = "aggressive"
	var hp0 := cr.hp
	t0 = Time.get_ticks_msec()
	while cr.hp >= hp0 and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	check(int(tur["st"]["ammo"]) < 20 and cr.hp < hp0, "it turns and shoots an attacking animal (ammo %d, hp %.0f -> %.0f)" % [int(tur["st"]["ammo"]), hp0, cr.hp])
	world.fauna._herds.erase(Vector2i(99998, 99998))
	world.fauna._scan = scan0
	if is_instance_valid(cr):
		cr.queue_free()
	# The alarm bell rings while the signal wired into it is on.
	var bell: Dictionary = mk.call("alarm_bell", lp + Vector3(-1, 1.6, -3))
	var lever: Dictionary = mk.call("lever", lp + Vector3(-1, 1.2, -2))
	game.give(ItemDB.make("signal_wire", 4, 1.0, game.origin_here("crafted", -1, pc.key)))
	check(grid.connect_pieces(pc, gen, pc, bell) == "" and grid.connect_signal(pc, lever, pc, bell) == "", "a bell cabled in and wired to a lever")
	grid.use_piece(pc, lever, false)
	var bn: PowerNode = pc.power_node(bell["i"])
	t0 = Time.get_ticks_msec()
	while (bn == null or bn._ring <= 0.0) and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	check(bn != null and bn._ring > 0.0, "pulling the lever rings the bell")
	for o in [tur, bell, lever]:
		player.deconstruct(pc, o)
	for t in ["auto_turret", "alarm_bell", "lever", "rifle_cartridges", "signal_wire"]:
		game.inventory.remove_type(t, game.inventory.count(t))

## A hopper tips stone onto two powered belts, which carry it into a chest.
func _automation_checks(game, grid: PowerGrid, player: Player, pc: ChunkNode, lp: Vector3, gen: Dictionary, mk: Callable) -> void:
	_make_room(game, 4)
	game.give(ItemDB.make("copper_wire", 10, 1.0, game.origin_here("crafted", -1, pc.key)))
	game.give(ItemDB.make("wood", 6, 1.0, game.origin_here("crafted", -1, pc.key)))
	grid.use_piece(pc, gen, false)
	var base := lp + Vector3(-6, 0, 2)
	var hop: Dictionary = mk.call("hopper", base)
	var b1: Dictionary = mk.call("conveyor_belt", base + Vector3(0, 0, 1))
	var b2: Dictionary = mk.call("conveyor_belt", base + Vector3(0, 0, 2))
	var chest: Dictionary = pc.add_built("storage_chest", base + Vector3(0, 0, 3), 0.0, {"by": "you", "day": 0.0})
	var w1: String = grid.connect_pieces(pc, gen, pc, b1)
	var w2: String = grid.connect_pieces(pc, b1, pc, b2)
	check(w1 == "" and w2 == "", "the belts are cabled to the generator (%s / %s)" % [w1, w2])
	var inv := Storage.open(hop)
	inv.add(ItemDB.make("stone", 3, 1.0, {}))
	Storage.save(hop, inv)
	var t0 := Time.get_ticks_msec()
	while Storage.open(chest).count("stone") < 3 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	check(Storage.open(chest).count("stone") == 3, "the hopper's stone rides the belts into the chest (%d)" % Storage.open(chest).count("stone"))
	check(" ".join(grid.describe(pc, b1, false)).contains("Carrying"), "a belt's look-at says what it carries")
	var pn: PowerNode = pc.power_node(b1["i"])
	check(pn != null and pn._belt != null, "a belt draws the items riding it")
	for o in [b1, b2, hop]:
		player.deconstruct(pc, o)
	var cinv := Storage.open(chest)
	cinv.remove_type("stone", 3)
	Storage.save(chest, cinv)
	player.deconstruct(pc, chest)
	for t in ["conveyor_belt", "hopper", "storage_chest"]:
		game.inventory.remove_type(t, game.inventory.count(t))

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	# Free pieces you build stand level on the floor under them, out of walls and pieces.
	var rest: Dictionary = await ProbeRest.run(self, Vector3(0, 3000, 0))
	for l in rest["lines"]:
		print("  ", l)
	check(rest["bad"] == 0, "built tables, chests and crates rest on their floor, clear of walls")
	var game = root.get_node("/root/Game")
	game.new_world("Integration", "424242")
	var world_id: String = game.store.root.get_file()
	change_scene_to_file("res://src/world/world.tscn")
	await _frames(5)
	var world = current_scene
	var player = world.player
	# Waits by the clock, not by frames: the cheaper the frames, the more of them pass
	# while the first chunks build on the workers.
	var t0 := Time.get_ticks_msec()
	while player.frozen and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
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
	# A chunk in grass range that landed bare (its load was asked for before a jump brought
	# it near) grows its grass once its next job comes back.
	for i in 300:
		if here.grass_built and not streamer._jobs.has(here_key):
			break
		await process_frame
	here.set_grass({})
	here.grass_built = false
	streamer._submit(here_key, "lod")
	for i in 900:
		if here.grass_built:
			break
		await process_frame
	check(here.grass_built and here.has_grass(), "a chunk that landed bare in grass range grows its grass")

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
	await _layer_checks(world, game)

	# Jetpack: worn on the back, it loads a canister of Jet Fuel and lifts you in the air.
	game.give(ItemDB.make("jetpack", 1, 1.0, {}))
	game.give(ItemDB.make("jet_fuel", 2, 1.0, {}))
	var jslot := -1
	for i in game.inventory.capacity:
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
			if String(key).begins_with("weed"):
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
					# (The rock sits into the face from the point it was placed on, up to half its
					# size further where it would otherwise jut out, and the ones at a rim stand by
					# the level ground above it.)
					var face := 0.0
					var reach := maxf(3.0, Vector3(b[i], b[i + 4], b[i + 8]).length() * 0.7)
					for o in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
						face = maxf(face, ChunkGenerator.slope_at(steep, clampf(b[i + 3] + o.x * reach, 0.0, 64.0), clampf(b[i + 11] + o.y * reach, 0.0, 64.0)))
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
		player.velocity = Vector3.ZERO
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
	for i in game.inventory.capacity:
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
	await _power_checks(game, world, player, pc, placed["p"] + Vector3(6, 0, 6))
	# Upwind of the power pieces (the fire checks blow the wind along +x).
	var burnt := await _fire_checks(game, world, pc, placed["p"] + Vector3(-8, 0, 12))
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
	for i in range(Inventory.HOTBAR, game.inventory.capacity):
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
	await _bandits(game, world, player)
	await _round_the_cliff(world, streamer, player)
	await _pirates(game, world, player)
	await _crowd(game, world, player)
	await _town_gate(game, world, player)
	await _fire_crew(game, world, player)

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
	# (Until it touches down: on a fast runner 30 frames weren't always enough.)
	for i in 240:
		await physics_frame
		if ship == null or (i >= 30 and ship.is_on_floor()):
			break
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
	await _cannon_check(game, world, player)

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

	# Levelling: experience from the console, a point spent, all saved below. At 4x
	# experience the harvesting above may already have levelled us, so start from 1.
	game.stats.level = 1
	game.stats.xp = 0
	game.stats.points = 0
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
	await _beds(game, world, player)

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
	if not burnt.is_empty():
		var c5 = store.load_chunk(burnt["key"].x, burnt["key"].y)
		check(c5["objects"][burnt["i"]]["st"].get("gone", false), "a wall that burnt down stays gone")
		check(burnt["ruin"] >= 0 and c5["objects"][burnt["ruin"]]["t"] == FireSim.RUIN and int(c5["objects"][burnt["ruin"]].get("sp", 0)) == burnt["sp"], "and its ash and charred beams are still there")
		check(float(c5["objects"][burnt["stone"]]["st"].get("char", 0.0)) > 0.0, "the stone wall it stood by stays scorched")
		check(c5["objects"][burnt["doused"]]["st"].has("fl") and not c5["objects"][burnt["doused"]]["st"].has("fire"), "the wall put out with a bucket stays out, half burnt")

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
	# The ship sets down on dry, loaded ground near you: try round about rather than only
	# straight ahead (a null there hung the run on sh.leaving).
	var sh: Vehicle = null
	for off: Vector3 in [Vector3(0, 0, -9), Vector3(9, 0, 0), Vector3(0, 0, 9), Vector3(-9, 0, 0), Vector3(0, 0, -16), Vector3(16, 0, 0)]:
		if sh == null:
			sh = world.vehicles.deploy(ItemDB.make("ship", 1, 1.0, {}), player.global_position + off, 0.0)
	check(sh != null, "a ship can be set down near the player (at %s)" % player.global_position)
	if sh == null:
		game.close_world()
		WorldStore.delete_world(world_id)
		print("integration: %d FAILED" % _fail)
		quit(1)
		return
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
	check(menus._mode == "corpse" and menus._store.capacity >= DeathBag.SLOTS, "opening the bag shows what is in it")
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

## Beds: a bed you make goes on your map as a place to wake; sleeping in it makes it the
## one picked first; after a fall you choose where to wake from a list and get up on it;
## taking it down forgets it.
func _beds(game, world, player) -> void:
	var start: Vector3 = player.global_position
	var pc: ChunkNode = world.streamer.get_chunk(ChunkStreamer.chunk_of(start))
	var lp := start + Vector3(3.0, 0, 0) - pc.position
	lp.x = clampf(lp.x, 1.0, ChunkGenerator.SIZE - 1.0)
	lp.y = ChunkGenerator.height_at(pc.data, lp.x, lp.z)
	var o: Dictionary = pc.add_built("bed", lp, 0.0, {"by": "you", "day": 0.0, "owner": Doors.my_id(), "owner_name": Doors.my_name()})
	var mk: Dictionary = game.markers.add_bed(pc.position + o["p"], game.planet, pc.key, o["i"])
	check(game.markers.on_planet(game.planet, "bed").size() == 1 and mk["name"] == "Bed 1", "a bed you make is marked on your map")
	check(String(Player._use_of(o).get("verb", "")).begins_with("Sleep in the bed"), "a bed offers to sleep in it")
	player._use_bed(pc, o)
	check(float(mk.get("slept", -1.0)) >= 0.0 and game.markers.on_planet(game.planet, "bed").size() == 1, "using it again doesn't mark it twice")
	var choices: Array = world.respawn_choices(start + Vector3(200, 0, 0))
	var bi := -1
	for i in choices.size():
		if choices[i]["kind"] == "bed":
			bi = i
	check(bi >= 0 and choices[-1]["kind"] == "spawn" and world.default_respawn(choices) == bi, "the bed you slept in is the first choice to wake at")
	# Die (keeping your things, so nothing else is disturbed) and wake on the bed.
	var net = root.get_node_or_null("/root/Net")
	if net:
		net.options["death_penalty"] = "keep"
	game.set_health(-5.0, "test")
	await create_timer(4.6).timeout
	await _frames(3)
	check(world.hud._wake.size() >= 2 and world.hud._wake_map != null, "after a fall you choose where to wake, with a map")
	world.hud._choose_wake(bi)
	var t0 := Time.get_ticks_msec()
	while (game.dead or player.frozen) and Time.get_ticks_msec() - t0 < 20000:
		await _frames(5)
	await _frames(30)
	var bed_at: Vector3 = pc.position + o["p"]
	check(not game.dead and Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(bed_at.x, bed_at.z)) < 2.5,
		"you wake on your bed (%.1f m off)" % Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(bed_at.x, bed_at.z)))
	if net:
		net.options.erase("death_penalty")
	player.deconstruct(pc, o)
	check(game.markers.on_planet(game.planet, "bed").is_empty(), "a bed taken down is no longer a place to wake")
	player.global_position = start + Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	await _frames(10)

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

## Outlaws: a band camped beside you spawns with its fire, stops you and demands a toll,
## fights when hit, and the one you kill stays dead (kept in its camp's chunk) and
## leaves a body to loot.
func _bandits(game, world, player) -> void:
	var at: Vector3 = player.global_position
	var camp := Vector2(at.x + 9.0, at.z + 4.0)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var b := {"id": "b9_9_0", "cell": Vector2i(9999, 9998), "camp": camp, "era": Eras.MEDIEVAL, "zone": 3,
		"route": [camp + Vector2(30, 0), camp + Vector2(0, 30)], "name": "Bandit band", "members": []}
	for i in 3:
		b["members"].append(Bandits._member(r, Eras.MEDIEVAL, 3, i, "b9_9_0", camp, 9999, 9998))
	world.npcs._load_band(b)
	await _frames(5)
	var e: Dictionary = world.npcs.settlements.get("b9_9_0", {})
	check(not e.is_empty() and e["nodes"].size() == 3, "a band near you comes to life (%d)" % (e.get("nodes", []).size()))
	if e.is_empty() or e["nodes"].is_empty():
		return
	check(is_instance_valid(e.get("decor")), "with its camp")
	check(not world.npcs.town_at(Vector3(camp.x, at.y, camp.y)).has("band"), "a band's camp is not a town")
	for n in e["nodes"]:
		n.decide_in = 0.0
	await _frames(10)
	var n0: NPC = e["nodes"][0]
	world.npcs.begin_talk(n0)
	var paid: int = game.money
	game.add_money(100)
	var took: int = world.npcs.pay_toll(n0)
	world.npcs.end_talk(n0)
	check(took > 0 and e["paid"] and game.money == paid + 100 - took, "paying the toll buys your way past (%d)" % took)
	var victim: NPC = e["nodes"][1]
	var vid := String(victim.rec["id"])
	victim.rec["hp"] = 1.0
	world.npcs.player_hit(victim, 50.0)
	await _frames(3)
	check(e["alert"] and not e["paid"], "hurt one and the band fights")
	check(not is_instance_valid(victim) or victim.is_queued_for_deletion(), "the dead outlaw is gone")
	var cn: ChunkNode = world.npcs._camp_chunk(b)
	check(cn != null and cn.data.get("bandits_dead", {}).has(vid), "and stays dead (kept in the camp's chunk)")
	var body := false
	for c in world.corpses.near(victim.global_position if is_instance_valid(victim) else Vector3(camp.x, at.y, camp.y), 30.0):
		if c["rec"]["kind"] == "person" and String(c["rec"].get("who", "")) == vid:
			body = true
	check(body, "leaving a body to search")
	for i in 30:
		await _frames(2)
	var fighting := 0
	for n in e["nodes"]:
		if is_instance_valid(n) and n.action in ["attack", "flee"]:
			fighting += 1
	check(fighting > 0, "the rest come for you (or run)")
	world.npcs._unload("b9_9_0")
	world.npcs._band_kills.clear()
	world.npcs._load_band(b)
	var e2: Dictionary = world.npcs.settlements.get("b9_9_0", {})
	check(e2.get("nodes", []).size() == 2, "the dead one doesn't come back with the band")
	world.npcs._unload("b9_9_0")
	game.health = 100.0

## People go round a cliff, not up it: a wall too steep to climb put across the ground
## under you (in memory only) with a way round its end; an outlaw sent across it walks
## round by the gap, and nowhere under their feet is steeper than a person walks.
func _round_the_cliff(world, streamer: ChunkStreamer, player) -> void:
	var npcs: NPCManager = world.npcs
	var k := ChunkStreamer.chunk_of(player.global_position)
	var cn: ChunkNode = streamer.get_chunk(k)
	var res := ChunkGenerator.RES
	var hs0: PackedFloat32Array = cn.data["heights"]
	var hs := hs0.duplicate()
	var o := Vector2(k.x * ChunkGenerator.SIZE, k.y * ChunkGenerator.SIZE)
	var h0: float = maxf(hs0[32 * res + 32], ChunkGenerator.WATER_LEVEL + 2.0)
	for j in range(2, 63):
		for i in range(2, 63):
			hs[j * res + i] = h0 + (12.0 if i >= 30 and i <= 33 and j <= 44 else 0.0)
	cn.data["heights"] = hs
	npcs.walk._chunks.erase(k)
	var camp := o + Vector2(10.0, 10.0)
	var r := RandomNumberGenerator.new()
	r.seed = 91
	var b := {"id": "b9_9_1", "cell": Vector2i(9999, 9997), "camp": camp, "era": Eras.MEDIEVAL, "zone": 3,
		"route": [camp], "name": "Cliff band", "members": [Bandits._member(r, Eras.MEDIEVAL, 3, 0, "b9_9_1", camp, 9999, 9997)]}
	npcs._load_band(b)
	await _frames(3)
	var e: Dictionary = npcs.settlements.get("b9_9_1", {})
	if e.is_empty() or e["nodes"].is_empty():
		check(false, "a band to walk round the cliff")
		cn.data["heights"] = hs0
		return
	# Out of the manager's hands, walked here a step at a time.
	var n: NPC = e["nodes"][0]
	e["nodes"] = []
	var from := o + Vector2(18.0, 24.0)
	var to := o + Vector2(46.0, 24.0)
	n.global_position = Vector3(from.x, h0, from.y)
	n.action = "flee"
	n.target = to
	n.target_player = false
	check(not npcs.walk.clear(from, to, WalkGrid.PERSON), "the straight way is up a cliff")
	var far := Vector3(o.x + 400.0, h0, o.y + 400.0)
	var top := -INF
	var worst := 0.0
	var round_end := false
	for f in 200:
		for s in 4:
			n.step(0.05, npcs._ground, far, PackedVector2Array())
		var at: Vector3 = n.global_position
		top = maxf(top, at.y)
		worst = maxf(worst, npcs.walk.grade(at.x, at.z))
		round_end = round_end or at.z - o.y > 44.0
		if Vector2(at.x, at.z).distance_to(to) < 1.0:
			break
		await process_frame
	var end := Vector2(n.global_position.x, n.global_position.z)
	check(end.distance_to(to) < 1.0, "they get there (%.1f m off)" % end.distance_to(to))
	check(top < h0 + 0.5 and worst <= WalkGrid.PERSON, "without climbing it (highest %.1f m up, steepest %.2f)" % [top - h0, worst])
	check(round_end, "going round its end")
	# A market stall across the way past the cliff's end: round it, never through it.
	var stall := o + Vector2(32.0, 54.0)
	npcs.walk.set_solids("test_stall", [PackedFloat32Array([stall.x, stall.y, cos(0.3), sin(0.3), 1.3, 0.6])])
	var from2 := o + Vector2(20.0, 54.0)
	var to2 := o + Vector2(44.0, 54.5)
	n.global_position = Vector3(from2.x, h0, from2.y)
	n.target = to2
	n._route = PackedVector2Array()
	n._route_goal = Vector2.INF
	n._route_wait = 0.0
	check(not npcs.walk.clear(from2, to2, WalkGrid.PERSON), "the straight way is through a stall")
	var into := 0.0
	for f in 200:
		for s in 4:
			n.step(0.05, npcs._ground, far, [])
		var at2 := Vector2(n.global_position.x, n.global_position.z)
		if npcs.walk.solid_at(at2, WalkGrid.BODY - 0.05):
			into = maxf(into, 0.05)
		if at2.distance_to(to2) < 1.0:
			break
		await process_frame
	var end2 := Vector2(n.global_position.x, n.global_position.z)
	check(end2.distance_to(to2) < 1.0 and into == 0.0, "they walk round the stall (%.1f m off, %s)" % [end2.distance_to(to2), "never in it" if into == 0.0 else "went into it"])
	npcs.walk.set_solids("test_stall", [])
	npcs._by_id.erase(n.rec["id"])
	n.queue_free()
	npcs._unload("b9_9_1")
	cn.data["heights"] = hs0
	npcs.walk._chunks.erase(k)

## A walled town's gate: its guard stops a stranger, a paid toll lets you in; slip in
## past nobody and a guard who doesn't know you asks for your pass, then fines you for
## trespass; a friend in town vouches for you, and is shamed if you break the law. Standing
## and passes are kept in your save.
func _town_gate(game, world, player) -> void:
	var at: Vector3 = player.global_position
	var npcs: NPCManager = world.npcs
	var c := Vector2(at.x + 40.0, at.z)
	var gate := Vector2(at.x + 18.0, at.z)
	var site := {"center": c, "walled": true, "inner": 20.0, "outer": 40.0, "sx": 9997, "sz": 9996, "era": Eras.MEDIEVAL, "size": 2}
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var guard := NPCGen.person(r, Eras.MEDIEVAL, 0, 9997, 9996)
	guard["job"] = "guard"
	guard["traits"]["greedy"] = 0.0
	var friend := NPCGen.person(r, Eras.MEDIEVAL, 1, 9997, 9996)
	friend["job"] = "farmer"
	for rec in [guard, friend]:
		rec["home"] = c
		rec["work"] = c
		rec["pos"] = Vector3(gate.x + 2.0, at.y, gate.y)
	friend["pos"] = Vector3(c.x, at.y, c.y)
	var data := {"sx": 9997, "sz": 9996, "era": Eras.MEDIEVAL, "center": c, "name": "Gatehold", "npcs": [guard, friend], "rumors": [], "sim_day": -1.0}
	var sid := "%d:9997_9996" % game.planet
	var e := {"data": data, "nodes": [], "dirty": false, "site": site, "outer": 40.0, "sid": sid, "transient": true,
		"gate": {"inside": false, "halted_t": -999.0, "welcomed": false, "warned": false, "warn_until": 0.0, "folk_t": -999.0, "gates": [gate], "postern": {}}}
	npcs.settlements["9997_9996"] = e
	var gn: NPC = npcs._add_node(e, guard)
	var fn: NPC = npcs._add_node(e, friend)
	game.crime = Crime.new()
	game.standing = Standing.new() # earlier checks' crimes nearby would have reached it by word
	var wait := func(): await create_timer(0.4).timeout
	# Walk up to the gate: the guard stops you.
	player.global_position = Vector3(gate.x - 6.0, at.y, gate.y)
	player.velocity = Vector3.ZERO
	await wait.call()
	check(game.standing.towns.has(sid) and game.standing.towns[sid]["name"] == "Gatehold", "a town you come near is noted")
	var o: Dictionary = npcs.gates.options(gn)
	check(not o.is_empty() and not o["admit"]["ok"] and o["sells"], "a stranger isn't let in, but can pay (%s, standing %s)" % [str(o.get("admit")), str(o.get("score"))])
	check(gn.action == "confront", "the gate guard comes to stop you (%s)" % gn.action)
	# Pay the toll: a pass.
	game.add_money(int(o["toll"]) + 10)
	var m0: int = game.money
	check(npcs.gates.pay_toll(gn) and game.money == m0 - int(o["toll"]), "the toll is paid")
	check(npcs.gates.options(gn)["admit"]["why"] == "pass" and game.standing.has_pass(sid, game.day), "and buys a pass")
	# Slip in with no guard on watch.
	game.standing.revoke(sid)
	gn.rec["dead"] = true
	player.global_position = Vector3(c.x - 10.0, at.y, c.y)
	player.velocity = Vector3.ZERO
	await wait.call()
	check(e["gate"]["inside"] and game.crime.owed(sid, game.day) == 0, "with nobody watching you slip in")
	# A guard who doesn't know you, up close and facing you, asks for your pass, then fines you.
	gn.rec["dead"] = false
	gn.rec["rel"] = 0
	gn.global_position = player.global_position + Vector3(1.5, 0, 0)
	gn.rotation.y = atan2(-1.5, 0.0)
	for i in 12:
		await wait.call()
		if e["gate"]["warned"]:
			break
	check(e["gate"]["warned"], "a guard asks a stranger inside for their pass")
	var before: int = game.town_standing(sid)
	e["gate"]["warn_until"] = 0.0
	for i in 12:
		await wait.call()
		if game.crime.owed(sid, game.day) > 0:
			break
	check(game.crime.owed(sid, game.day) >= Crime.FINES["trespass"], "staying without leave is trespass (%d)" % game.crime.owed(sid, game.day))
	check(game.town_standing(sid) < before, "and the town thinks less of you (%d -> %d)" % [before, game.town_standing(sid)])
	# A friend vouches; break the law and they're shamed.
	game.crime = Crime.new()
	friend["rel"] = 60
	check(npcs.gates.vouch(gn, friend) and game.standing.pass_of(sid, game.day)["how"] == "vouched", "a friend in town vouches for you")
	var rel0 := int(friend["rel"])
	game.add_bounty(sid, "Gatehold", 20, "Theft")
	check(int(friend["rel"]) < rel0 - 20 and not game.standing.has_pass(sid, game.day), "break the law and they're shamed, and the pass is gone")
	# At night a strict town's portcullis comes down for a stranger, and rises for a pass.
	game.crime = Crime.new()
	game.standing.revoke(sid)
	var day0: float = game.day
	game.day = floorf(game.day) + 23.0 / 24.0
	var tp: Dictionary = GatePolicy.temper(site, data)
	tp["night_shut"] = true
	tp["need"] = 90
	e["gate"]["tp"] = tp
	e["gate"]["folk_t"] = 1e12
	npcs.gates._ports[sid] = [npcs.gates._make_port(Transform3D(Basis(), Vector3(gate.x, at.y, gate.y)))]
	player.global_position = Vector3(gate.x - 8.0, at.y, gate.y)
	player.velocity = Vector3.ZERO
	for i in 10:
		await wait.call()
	var pt: Dictionary = npcs.gates._ports[sid][0]
	check(npcs.gates.gate_shut(sid) and not (pt["body"] as CollisionShape3D).disabled, "at night the portcullis comes down and bars the way")
	game.standing.give_pass(sid, game.day + 1.0, "toll")
	for i in 10:
		await wait.call()
	check(not npcs.gates.gate_shut(sid) and (pt["body"] as CollisionShape3D).disabled, "with leave it is wound up again")
	game.day = day0
	game.standing.revoke(sid)
	# Over the wall with a rope, away from the gate.
	gn.rec["dead"] = true
	player.global_position = Vector3(c.x, at.y, c.y + 24.5)
	player.velocity = Vector3.ZERO
	await _frames(2)
	var us: Array = npcs.gates.usables(player.global_position)
	check(us.size() == 1 and String(us[0]["verb"]).begins_with("Climb over the wall"), "a stretch of wall away from the gate can be climbed (%s)" % str(us))
	game.inventory.add(ItemDB.make("rope", 3, 1.0, {}))
	var ropes: int = game.inventory.count("rope")
	if not us.is_empty():
		npcs.gates.use(sid, player)
		for i in 14:
			await wait.call()
	var pin := Vector2(player.global_position.x, player.global_position.z)
	check(pin.distance_to(c) < 20.0 and not player.script_move, "you climb up, over and down inside (%.1f m from the middle)" % pin.distance_to(c))
	check(game.inventory.count("rope") == ropes - GateWatch.CLIMB_ROPE, "the rope is left on the wall")
	# The postern: pick its lock from outside and step through into town.
	var pst := {"p": c + Vector2(0, -22.5), "yaw": PI, "tier": 1}
	e["gate"]["postern"] = pst
	var po: Vector2 = GateWatch.postern_side(pst, true)
	player.global_position = Vector3(po.x, at.y, po.y)
	player.velocity = Vector3.ZERO
	e["gate"]["inside"] = false
	await _frames(2)
	if game.inventory.count("lockpick") <= 0:
		game.inventory.add(ItemDB.make("lockpick", 3, 1.0, {}))
	var pu: Array = npcs.gates.usables(player.global_position)
	check(pu.size() == 1 and String(pu[0]["n"]) == "postern:" + sid and String(pu[0]["verb"]).begins_with("Pick the postern"), "a town's postern door can be picked from outside (%s)" % str(pu))
	npcs.gates.use("postern:" + sid, player)
	var lui: LockpickUI = player.get_tree().get_first_node_in_group("lockpick_ui")
	check(lui != null and lui.is_open(), "picking the postern opens the lockpicking minigame")
	if lui and lui.is_open():
		lui._opened()
		for i in 6:
			await wait.call()
	var pin2 := Vector2(player.global_position.x, player.global_position.z)
	check(pin2.distance_to(c) < 21.5 and not player.script_move, "through the postern and into town (%.1f m from the middle)" % pin2.distance_to(c))
	check(npcs.gates._posterns.get(sid, {}).get("open", false), "a picked postern stays open")
	# The watch's keys open the postern without picking it.
	npcs.gates._posterns[sid]["open"] = false
	game.inventory.add(ItemDB.make("watch_keys", 1, 1.0, {"how": "stolen", "sid": sid}))
	player.global_position = Vector3(po.x, at.y, po.y)
	player.velocity = Vector3.ZERO
	e["gate"]["inside"] = false
	await _frames(2)
	var ku: Array = npcs.gates.usables(player.global_position)
	check(ku.size() == 1 and String(ku[0]["verb"]).contains("watch's keys"), "the watch's keys fit the postern (%s)" % str(ku))
	npcs.gates.use("postern:" + sid, player)
	for i in 6:
		await wait.call()
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(c) < 21.5 and not (lui != null and lui.is_open()), "and you're through without picking it")
	# A grappling hook gets you back over the wall without leaving rope behind.
	game.inventory.add(ItemDB.make("grappling_hook", 1, 1.0, {}))
	var r0: int = game.inventory.count("rope")
	player.global_position = Vector3(c.x, at.y, c.y + 21.0)
	player.velocity = Vector3.ZERO
	await _frames(2)
	var hu: Array = npcs.gates.usables(player.global_position)
	check(hu.size() == 1 and String(hu[0]["verb"]).contains("grappling hook"), "a grappling hook climbs the wall (%s)" % str(hu))
	npcs.gates.use(sid, player)
	for i in 12:
		await wait.call()
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(c) > 23.5 and game.inventory.count("rope") == r0 and not player.script_move,
		"over and out, and the rope is still yours")
	# A writ of passage from a town whose word reaches here is as good as a pass.
	check(not npcs.gates.verdict(e)["ok"], "a stranger without leave still isn't let in")
	game.inventory.add(ItemDB.make("writ", 1, 1.0, {"sid": "%d:1_1" % game.planet, "x": c.x + 300.0, "z": c.y, "until": game.day + 2.0}))
	check(npcs.gates.verdict(e)["why"] == "pass", "a writ from a town nearby lets you in")
	game.inventory.remove_type("writ", 1)
	# In the watch's tabard, guards who don't know you take you for one of their own...
	game.equipment["back"] = ItemDB.make("watch_tabard", 1, 1.0, {})
	check(npcs.gates.verdict(e)["why"] == "disguise", "in the watch's tabard you pass for one of them")
	# ...but one who knows your face sees through it.
	gn.rec["dead"] = false
	gn.rec["rel"] = 60
	gn.action = "idle"
	gn.global_position = Vector3(gate.x + 2.0, at.y, gate.y)
	e["gate"]["welcomed"] = false
	e["gate"]["inside"] = false
	player.global_position = Vector3(gate.x - 6.0, at.y, gate.y)
	player.velocity = Vector3.ZERO
	game.crime = Crime.new()
	for i in 6:
		await wait.call()
		if game.crime.owed(sid, game.day) > 0:
			break
	check(game.crime.owed(sid, game.day) >= Crime.FINES["impersonation"] and npcs.gates.verdict(e)["why"] != "disguise",
		"a guard who knows you sees through it: posing as the watch (%d)" % game.crime.owed(sid, game.day))
	game.equipment.erase("back")
	game.crime = Crime.new()
	gn.rec["dead"] = false
	# Saved with you.
	game.save_player()
	var p = game.store.load_player()
	check(p is Dictionary and Standing.from_data(p.get("standing")).towns.has(sid), "standing is kept in your save")
	npcs._unload("9997_9996")
	game.crime = Crime.new()
	game.standing.towns.erase(sid)
	# Over the wall and back is a long way: let the ground round where you stood come
	# back in at full detail before the next checks drive about on it, held still (not
	# falling) meanwhile, then set down on it.
	for i in 300:
		player.global_position = at + Vector3(0, 1.0, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		if world.streamer.ready_round(at):
			break
	var gy: float = npcs.ground(at.x, at.z)
	player.global_position = Vector3(at.x, (at.y if is_nan(gy) else gy) + 0.1, at.z)
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
		if player.is_on_floor():
			break
	player.velocity = Vector3.ZERO

## Pirates: a pirate boat put out near you comes crewed with armed pirates who demand a
## toll; paid, they sail off; hurt one and they all fight.
## Market crowd: folk from the countryside fill the square by day and go home by night.
func _crowd(game, world, player) -> void:
	var e: Dictionary = {}
	for x in world.npcs.settlements.values():
		if x.has("places") and not x["data"].has("band") and not x.has("boat"):
			e = x
	check(not e.is_empty(), "a town is loaded for the market crowd")
	if e.is_empty():
		return
	var day0: float = game.day
	var c: Vector2 = e["data"]["center"]
	var at := Vector3(c.x, player.global_position.y, c.y)
	var visitors := func() -> Array:
		var out: Array = []
		for n in e["nodes"]:
			if is_instance_valid(n) and n.rec.has("visit"):
				out.append(n)
		return out
	var residents: int = e["nodes"].size() - visitors.call().size()
	var was: Vector3 = player.global_position
	player.global_position = at + Vector3(0, 1, 0) # near enough that they stay
	game.day = floor(day0) + 12.5 / 24.0
	world.npcs._crowd(e, at)
	await _frames(5)
	var vs: Array = visitors.call()
	check(vs.size() >= 3, "by midday visitors fill the town (%d, with %d townsfolk)" % [vs.size(), residents])
	var inside := 0
	for n in vs:
		inside += int(Vector2(n.global_position.x, n.global_position.z).distance_to(c) < float(e["places"]["outer"]))
	check(inside == vs.size(), "in the town, not out in the fields (%d/%d)" % [inside, vs.size()])
	for n in vs:
		n.decide_in = 0.0
	await _frames(10)
	var busy := 0
	for n in vs:
		busy += int(n.action == "work" and not n.duty.is_empty())
	check(busy >= vs.size() / 2, "browsing the stalls and standing about the square (%d/%d)" % [busy, vs.size()])
	check(not e["data"]["npcs"].has(vs[0].rec), "visitors are not townsfolk (nothing saved)")
	for n in e["nodes"]:
		if is_instance_valid(n) and n._human and is_instance_valid(n._human._work_tool) and NPC.FIELD_TOOL_JOBS.has(n.rec["job"]):
			var in_field: bool = n.action == "work" and NPC.FIELD_DUTIES.has(String(n.duty.get("duty", "")))
			check(n._human._work_tool.visible == in_field, "a farmer's tool is out only in the fields (%s, %s)" % [n.action, n.duty.get("duty", "")])
			break
	var benches: Array = e["places"].get("benches", [])
	if not benches.is_empty():
		var sitter: NPC = vs[0]
		var spot: Array = world.npcs._bench_spot(sitter, e, benches[0][0])
		sitter.global_position = Vector3(spot[0].x, sitter.global_position.y, spot[0].y)
		sitter.target = spot[0]
		sitter.face_to = spot[1]
		world.npcs.instruct(sitter, "sit", 120.0) # told to sit and stay sat
		await _frames(120)
		check(sitter.perform == "sit" and world.npcs.bench_under(sitter) and sitter._stool == null, "someone sitting down by a door sits on its bench, not a stool")
		var other: NPC = vs[1]
		check(world.npcs._bench_spot(other, e, benches[0][0]).is_empty() or int(other.get_meta("bench_i", -1)) != int(sitter.get_meta("bench_i", -2)), "one to a bench")
		sitter.stop_perform()
	# A name tag at the edge of its range holds steady: up inside 7 m, down only past 8.
	var tagged: NPC = vs[vs.size() - 1]
	tagged._speech_t = 0.0
	tagged._speaking = false
	var pp: Vector3 = player.global_position
	var tag_at := func(d: float) -> bool:
		tagged.global_position = Vector3(pp.x + d, tagged.global_position.y, pp.z)
		tagged.target = Vector2(pp.x + d, pp.z)
		await _frames(1)
		return tagged.name_shown()
	var up: bool = await tag_at.call(5.0)
	var held: bool = await tag_at.call(7.5)
	var down: bool = await tag_at.call(8.6)
	var stays_down: bool = await tag_at.call(7.5)
	check(up and held and not down and not stays_down, "a name tag doesn't blink at the edge of its range (%s %s %s %s)" % [up, held, down, stays_down])
	# A speech line is drawn in the open, and not through a wall between you and the speaker.
	var cam: Camera3D = world.get_viewport().get_camera_3d()
	if cam:
		var ahead := -cam.global_transform.basis.z
		ahead.y = 0.0
		ahead = ahead.normalized()
		var spot := cam.global_position + ahead * 12.0
		tagged.global_position = Vector3(spot.x, tagged.global_position.y, spot.z)
		tagged.target = Vector2(spot.x, spot.z)
		tagged.say("Fire! Fetch the buckets!", 30.0)
		await _frames(10)
		var in_open: bool = tagged.tag_visible()
		var head: Vector3 = tagged.tag_point()
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8, 8, 0.5)
		cs.shape = box
		wall.add_child(cs)
		world.add_child(wall)
		wall.global_position = (cam.global_position + head) * 0.5
		wall.look_at(head, Vector3.UP)
		# Line of sight is re-asked every TagLayout.RECHECK seconds, in physics.
		await create_timer(0.6).timeout
		await _frames(5)
		var walled: bool = tagged.tag_visible()
		wall.queue_free()
		await create_timer(0.6).timeout
		await _frames(5)
		check(in_open and not walled and tagged.tag_visible(), "a speech line shows in the open and hides behind a wall (%s %s %s)" % [in_open, walled, tagged.tag_visible()])
		var lay: TagLayout = world.npcs._tags
		var vh: float = world.get_viewport().get_visible_rect().size.y
		check(lay.layer < 1 and not lay._pool.is_empty() and lay._font_px == maxi(14, int(round(vh * TagLayout.FONT_FRAC))), "villager tags are flat text over the view, under the HUD, sized to the screen (%d px)" % lay._font_px)
		tagged._speech_t = 0.0
	world.npcs._crowd(e, at + Vector3(400, 0, 0))
	check(visitors.call().is_empty(), "nobody near: they cost nothing")
	game.day = floor(day0) + 1.0 + 3.0 / 24.0
	world.npcs._crowd(e, at)
	check(visitors.call().is_empty(), "and by night they have gone home")
	game.day = day0
	player.global_position = was

## A fire in a town: the able-bodied run a bucket line between the well and the flames,
## the rest get clear; animals bolt from it; when it is out they go back to their day.
## A field cannon: man it, load hot shot from the pack, lay it on a timber wall and fire;
## the ball flies, strikes the wall and sets it alight.
func _cannon_check(game, world, player) -> void:
	var fs: FireSystem = FireSystem.current
	var cv: Vehicle = world.vehicles.deploy(ItemDB.make("cannon", 1, 1.0, {}), player.global_position + Vector3(4, 0, 0), 0.0)
	await _frames(3)
	check(cv != null and cv.barrel != null, "a field cannon stands ready with its barrel")
	if cv == null or fs == null:
		return
	_make_room(game, 2)
	game.inventory.add(ItemDB.make("hot_shot", 1, 1.0, {}))
	game.inventory.add(ItemDB.make("black_powder", 2, 1.0, {}))
	player.mount(cv)
	await _frames(3)
	check(player.vehicle == cv, "manning the cannon")
	Cannon.use(player, cv)
	check(cv.rec.has("loading") and game.inventory.count("hot_shot") == 0, "loading takes the ball from the pack")
	await create_timer(Cannon.LOAD_TIME + 0.3).timeout
	check(cv.rec.get("load", "") == "hot_shot", "loaded with hot shot")
	# A timber wall down range, the barrel laid on its middle.
	var wp: Vector3 = cv.global_position + Vector3(0, 0, -22)
	var gy: float = world.vehicles.ground(wp.x, wp.z)
	wp.y = gy if not is_nan(gy) else cv.global_position.y
	var node: ChunkNode = world.streamer.get_chunk(ChunkStreamer.chunk_of(wp))
	var wall := node.add_built("wall_plaster", wp - node.position, 0.0, {"by": "you", "day": 0.0})
	await _frames(3)
	var mz := Cannon.muzzle(cv)
	var aim: Vector3 = wp + Vector3(0, 1.4, 0) - mz.origin
	player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length()) - 0.08
	await _frames(4)
	Cannon.use(player, cv)
	check(not cv.rec.has("load") and cv.kick > 0.5, "the cannon fires and kicks back")
	var lit := false
	for i in 90:
		await physics_frame
		if (wall["st"] as Dictionary).has("fire") or float(wall["st"].get("dmg", 0.0)) > 0.0:
			lit = true
			break
	check(lit and (wall["st"] as Dictionary).has("fire"), "hot shot strikes the wall and sets it alight (%s)" % [wall["st"].keys()])
	player.dismount()
	fs.douse_all()
	node.remove_object(wall["i"])
	world.vehicles.pack_up(cv)

func _fire_crew(game, world, player) -> void:
	var fs: FireSystem = FireSystem.current
	var e: Dictionary = {}
	for x in world.npcs.settlements.values():
		if x.has("places") and not x["data"].has("band") and not x.has("boat") and not (x["nodes"] as Array).is_empty():
			e = x
	check(not e.is_empty(), "a town is loaded for the fire")
	if e.is_empty() or fs == null:
		return
	var n: NPC = null
	for o in e["nodes"]:
		if is_instance_valid(o) and not o.rec.has("visit") and not o.rec.get("child", false):
			n = o
	check(n != null, "a townsman to fight the fire")
	if n == null:
		return
	n.rec["traits"]["brave"] = 0.9
	var was: Vector3 = player.global_position
	player.global_position = n.global_position + Vector3(0, 1, 30)
	var wp: Vector3 = n.global_position + Vector3(7, 0, 0)
	var node: ChunkNode = world.streamer.get_chunk(ChunkStreamer.chunk_of(wp))
	var wall := node.add_built("wall_plaster", wp - node.position, 0.0, {"by": "you", "day": 0.0})
	fs.ignite(node, wall["i"], 1.0, false, true)
	wall["st"]["fire"]["h"] = 0.7
	var held_was = n.rec.get("held", null)
	world.npcs._decide(n, e, player.global_position, world.npcs.now())
	check(n.action == "fight_fire" and String((n.rec.get("held", {}) as Dictionary).get("type", "")) == "bucket", "a townsman grabs a bucket to fight the fire (%s)" % n.action)
	var well: Vector2 = n.target
	n.global_position = Vector3(well.x, n.global_position.y, well.y)
	world.npcs._decide(n, e, player.global_position, world.npcs.now())
	check(n.rec.get("_fire_leg", "") == "carry", "fills it at the well")
	# Heat of every fire before the carry: the throw can land on the wall or on
	# whatever it spread to, and can happen on any carry step (a well near the edge
	# throws on the first one), so walk the carry until the bucket is empty, capped.
	var h0 := _fire_heat(world, fs)
	for _step in 10:
		if n.rec.get("_fire_leg", "") == "fetch":
			break
		n.stop_perform()
		world.npcs._decide(n, e, player.global_position, world.npcs.now())
		var to: Vector2 = n.target
		n.global_position = Vector3(to.x, n.global_position.y, to.y)
	var h1 := _fire_heat(world, fs)
	check(n.rec.get("_fire_leg", "") == "fetch" and h1 < h0, "and throws it on the flames (%.2f -> %.2f)" % [h0, h1])
	# Animals near it run.
	var ksp := 0
	while Creature.species(ksp, Eras.MEDIEVAL)["kit"] == "":
		ksp += 1
	var cr := Creature.new()
	cr.setup("test_fire_animal", ksp, Eras.MEDIEVAL, wp + Vector3(6, 0, 4), world.fauna)
	world.fauna.add_child(cr)
	# In the herd of the chunk it stands in: a herd far from the player is let go (freed)
	# on the fauna's next refresh, which on a fast runner came within these frames.
	var hk := ChunkStreamer.chunk_of(wp + Vector3(6, 0, 4))
	var had_herd: bool = world.fauna._herds.has(hk)
	if not had_herd:
		world.fauna._herds[hk] = []
	world.fauna._herds[hk].append(cr)
	await _frames(2)
	fs._scare_animals()
	check(is_instance_valid(cr) and cr.scared_t > 0.0 and cr.scared_of.distance_to(wp) < 3.0, "an animal by the fire bolts from it")
	if world.fauna._herds.has(hk):
		world.fauna._herds[hk].erase(cr)
		if not had_herd and world.fauna._herds[hk].is_empty():
			world.fauna._herds.erase(hk)
	if is_instance_valid(cr):
		cr.queue_free()
	# Out: back to their day, bucket put away.
	fs.douse_all()
	n.stop_perform()
	world.npcs._decide(n, e, player.global_position, world.npcs.now())
	check(n.action != "fight_fire" and not n.rec.has("_fire") and str(n.rec.get("held", null)) == str(held_was), "with the fire out they put the bucket down")
	wall["st"]["gone"] = true
	player.global_position = was

func _pirates(game, world, player) -> void:
	var at: Vector3 = player.global_position + Vector3(14.0, 0.0, 0.0)
	var npcs: NPCManager = world.npcs
	var b: BoatNode = npcs.spawn_pirates(at)
	check(b != null and b.faction == "pirate", "a pirate boat puts out")
	if b == null:
		return
	await _frames(3)
	var crew: Dictionary = npcs.crew_of(b)
	var nodes: Array = crew.get("nodes", [])
	check(nodes.size() >= 2, "crewed by pirates (%d)" % nodes.size())
	if nodes.is_empty():
		return
	var p0: NPC = nodes[0]
	check(String(p0.rec.get("faction", "")) == "pirate" and Bandits.ranged(p0.rec), "armed to fight from the deck (%s)" % p0.rec.get("held", {}).get("type", ""))
	npcs._decide_pirate(p0, crew, player.global_position, npcs.now())
	var st: Dictionary = npcs._pirate_state(p0)
	check(float(st["demand_until"]) > 0.0 and p0.action == "confront", "they hail you and demand a toll")
	game.add_money(100)
	var m0: int = game.money
	var took: int = npcs.pay_toll(p0)
	check(took > 0 and game.money == m0 - took and st["paid"], "paying them off (%d)" % took)
	npcs._pirate_leave(st)
	check(st["leaving"] and b.goal != Vector2.INF, "and they sail away")
	world.boats.despawn(b)
	npcs._pirates.clear()
	await _frames(3)
	var b2: BoatNode = npcs.spawn_pirates(at)
	await _frames(3)
	var crew2: Dictionary = npcs.crew_of(b2)
	var nodes2: Array = crew2.get("nodes", [])
	if nodes2.is_empty():
		check(false, "a second crew boards")
		return
	var victim: NPC = nodes2[0]
	var bounty0: int = game.crime.owed(String(crew2.get("sid", "")), game.day)
	npcs.player_hit(victim, 5.0)
	var st2: Dictionary = npcs._pirate_state(nodes2[nodes2.size() - 1])
	check(st2["alert"], "hurt one and they all fight")
	check(game.crime.owed(String(crew2.get("sid", "")), game.day) == bounty0, "fighting pirates is no crime")
	var other: NPC = nodes2[nodes2.size() - 1]
	npcs._decide_pirate(other, crew2, player.global_position, npcs.now())
	check(other.action == "attack", "they shoot from the deck")
	world.boats.despawn(b2)
	npcs._pirates.clear()
	game.health = 100.0

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
	# Until it lands (the shot flies in physics steps, which a fast runner's frames outpace).
	for i in 120:
		await process_frame
		if kc.hp < hp0 or player.gunplay._shots.is_empty() and i > 10:
			break
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
	for i in game.inventory.capacity:
		if game.inventory.get_slot(i) != null:
			items_before += int(game.inventory.get_slot(i)["qty"])
	var xp_before: int = game.stats.xp + game.stats.level * 100000
	game.set_health(30.0)
	var msg := WonderEffects.apply(ruin, rc, player)
	var items_after := 0
	for i in game.inventory.capacity:
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
	for i in game.inventory.capacity:
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
	# Held high over the spot (not falling: speed piled up over hundreds of frames up
	# there, on a fast machine, landed the player hard enough to die, and they woke far
	# away) until the house's chunk and its neighbours are in at full detail.
	for i in 600:
		player.global_position = Vector3(stand.x, 400, stand.z)
		player.velocity = Vector3.ZERO
		await _frames(1)
		if streamer.ready_round(stand):
			break
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(stand))
	stand.y = ChunkGenerator.height_at(c.data, stand.x - c.position.x, stand.z - c.position.z) + 0.1
	player.set_state({"pos": stand, "yaw": atan2(out.x, out.z), "pitch": 0.0, "slot": 0})
	player.velocity = Vector3.ZERO
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
	# The checks before this fill the pack, and a full pack leaves the loot in the chest
	# (which read here as the chest not opening, now and then): make room first.
	var inv: Inventory = root.get_node("/root/Game").inventory
	for i in range(inv.capacity - 1, Inventory.HOTBAR - 1, -1):
		if inv.free_slots() >= 12:
			break
		var it = inv.get_slot(i)
		if it != null and it["type"] != "lockpick":
			inv.set_slot(i, null)
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
	check(o["st"].get("opened", false) or (o["st"]["loot"] as Array).size() < 2, "interact loots it (%d left in it, %d free slots, facing %s)" % [(o["st"]["loot"] as Array).size(), inv.free_slots(), player.focus.get("kind", "nothing")])
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
			check(ui.page_text().length() > 40, "the page has something to read")
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

## Map overlays: each paints tiles under the minimap and lists what is in view.
func _layer_checks(world, game) -> void:
	var mm: Minimap = world.hud._minimap
	# Your standing shows only round towns you know: one where you stand.
	var here: Vector3 = game.player.global_position
	var tsid := "%d:layer_test" % game.planet
	game.standing.note(tsid, "Layerton", Vector2(here.x, here.z), game.day)
	for l in range(1, MapLayers.COUNT):
		game.map.set_layer(l)
		mm._canvas.layer_mask = 0
		await process_frame
		var n := 0
		while mm._canvas.layer_mask == 0 and n < 240:
			await process_frame
			n += 1
		check(mm._canvas.layer_mask != 0, "the %s overlay paints the minimap (%d frames)" % [MapLayers.NAMES[l], n])
	check(MapLayers.describe(MapLayers.STANDING, here.x, here.z).begins_with("Layerton: "), "the standing overlay names the town and your tier (%s)" % MapLayers.describe(MapLayers.STANDING, here.x, here.z))
	game.standing.towns.erase(tsid)
	check(MapLayers.sample(MapLayers.LEVELS, 3000.0, 0.0) == Eras.zone_level(3000.0, 0.0) / 10, "the level overlay follows zone levels")
	var lv := Eras.zone_level(3000.0, 0.0)
	var far_danger: int = MapLayers.sample(MapLayers.DANGER, 3000.0, 0.0)
	check(lv - game.stats.level < 8 or MapLayers.category(MapLayers.DANGER, far_danger)[1] == "Deadly", "land far above your level reads as deadly (Lv %d, you %d)" % [lv, game.stats.level])
	var rs := MapLayers.rings(MapLayers.LEVELS)
	check(not Eras.themed() or (rs.size() >= 4 and is_equal_approx(rs[0][0], (10 - Eras.base_level) * Eras.LEVEL_STEP)), "level rings sit where the levels change (%s)" % [rs])
	check(MapLayers.category(MapLayers.ERA, Eras.SCIFI)[1] != "", "eras have names")
	game.map.set_layer(MapLayers.OFF)
	await process_frame
	check(mm._canvas.layer_mask == 0, "the overlay can be turned off")

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
	for i in range(game.inventory.capacity - 1, -1, -1):
		if game.inventory.free_slots() >= 3:
			break
		game.inventory.set_slot(i, null)
	con.run("give helm_iron 1")
	con.run("give helm_elven 1")
	var hi := -1
	var he := -1
	for i in game.inventory.capacity:
		var it = game.inventory.get_slot(i)
		if it != null and it["type"] == "helm_iron": hi = i
		if it != null and it["type"] == "helm_elven": he = i
	check(hi >= 0 and he >= 0, "two helmets in the pack")
	check(game.equip(hi) and game.equipment["head"]["type"] == "helm_iron" and game.inventory.get_slot(hi) == null, "drop a helmet on the head to wear it")
	check(game.equip(he) and game.equipment["head"]["type"] == "helm_elven" and game.inventory.get_slot(he)["type"] == "helm_iron", "swapping helmets puts the old one where the new came from")
	var empty := -1
	for i in range(game.inventory.capacity - 1, Inventory.HOTBAR, -1):
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
		for i in game.inventory.capacity:
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

## Fire: a timber wall set alight takes hold, throws flame onto the wall touching it,
## scorches the stone wall beside it, burns down to ash and charred beams; a bucket of
## water puts out another, a few blows beat out a small one, rain holds fires down.
## Returns what to check after the reload.
func _fire_checks(game, world, pc: ChunkNode, at: Vector3) -> Dictionary:
	var fs: FireSystem = FireSystem.current
	check(fs != null and fs.get_parent() == world, "the world runs its fires")
	if fs == null:
		return {}
	# Stand well upwind of the test fires, and don't burn: they run for minutes of game time
	# here and can spread into the trees round about, and dying in one would spoil the
	# death checks further on.
	var stood: Vector3 = world.player.global_position
	world.player.global_position = pc.position + at + Vector3(-14, 0, -3)
	var god: bool = game.cheats["god"]
	game.cheats["god"] = true
	var wood := pc.add_built("wall_plaster", at, 0.0, {"by": "you", "day": 0.0})
	var next := pc.add_built("wall_plaster", at + Vector3(2, 0, 0), 0.0, {"by": "you", "day": 0.0})
	var stone := pc.add_built("wall_stone", at + Vector3(-2, 0, 0), 0.0, {"by": "you", "day": 0.0})
	check(not fs.ignite(pc, stone["i"], 1.0, false, true), "a stone wall will not burn")
	check(fs.ignite(pc, wood["i"], 1.0, false, true), "a timber wall catches")
	check(fs.is_burning(pc.key, wood["i"]) and fs.burning_count() >= 1, "and is burning")
	# Wind along the row, to carry it.
	world.atmosphere.wind_dir = Vector2(1, 0)
	fs.rain_override = 0.0
	var secs := 0.0
	while secs < 900.0 and not wood["st"].get("gone", false):
		fs._process(1.0)
		secs += 1.0
		# The stone wall beside it is in the flames.
		if wood["st"].has("fire") and FireSim.heat(wood["st"]) > 0.5 and not stone["st"].has("char"):
			fs.ignite(pc, stone["i"], 1.0, false, false, 5.0)
	check(wood["st"].get("gone", false), "it burns down (%.0f s)" % secs)
	check(next["st"].has("fire") or next["st"].get("gone", false) or next["st"].has("lit_by") or float(next["st"].get("char", 0.0)) > 0.0, "flames caught the wall touching it")
	check(float(stone["st"].get("char", 0.0)) > 0.0, "and scorched the stone one")
	var ruin := -1
	for o in pc.data["objects"]:
		if o["t"] == FireSim.RUIN and not o["st"].get("gone", false) and (o["p"] as Vector3).distance_to(at) < 2.0:
			ruin = o["i"]
	check(ruin >= 0, "it leaves a heap of ash and charred beams")
	var bufs := ChunkNode.build_object_buffers(pc.data, false)
	var sooty := false
	for k in bufs:
		if String(k).ends_with(ChunkNode.SOOT) and String(k).begins_with("b:wall_stone"):
			sooty = true
	check(sooty, "the scorched stone wall is drawn sooted")
	fs.douse_all()
	# A bucket of water on the next one.
	var third := pc.add_built("wall_plaster", at + Vector3(0, 0, 4), 0.0, {"by": "you", "day": 0.0})
	fs.ignite(pc, third["i"], 1.0, false, true)
	for i in 40:
		fs._process(1.0)
	var buckets := 0
	while third["st"].has("fire") and buckets < 8:
		fs.douse(pc.position + (third["p"] as Vector3) + Vector3(0, 1, 0), 2.2, 0.55)
		buckets += 1
	check(not third["st"].has("fire") and buckets <= 5, "a few buckets put it out (%d)" % buckets)
	check(not fs.is_burning(pc.key, third["i"]), "and the fire is gone")
	# Beaten out with your fists while it is small.
	var fence := pc.add_built("fence", at + Vector3(0, 0, 8), 0.0, {"by": "you", "day": 0.0})
	fs.ignite(pc, fence["i"], 0.4, false, true)
	var blows := 0
	while fence["st"].has("fire") and blows < 10:
		fs.player_use(world.player, null, Durability.FIST, {"obj": fence["i"], "chunk": pc, "point": pc.position + (fence["p"] as Vector3)})
		blows += 1
	check(not fence["st"].has("fire") and blows <= 6, "a small fire is beaten out (%d blows)" % blows)
	check(not fence["st"].get("gone", false), "without breaking what was burning")
	# Rain beats a fire down.
	var fourth := pc.add_built("wall_plaster", at + Vector3(0, 0, 12), 0.0, {"by": "you", "day": 0.0})
	fs.ignite(pc, fourth["i"], 1.0, false, true)
	fs.rain_override = 1.0
	for i in 120:
		fs._process(1.0)
	check(not fourth["st"].has("fire") or FireSim.heat(fourth["st"]) < 0.6, "a downpour holds it down (%.2f)" % FireSim.heat(fourth["st"]))
	print("  (fires still burning after the checks: %d)" % fs.burning_count())
	fs.douse_all()
	fs.rain_override = -1.0
	game.cheats["god"] = god
	world.player.global_position = stood
	game.flush_chunks()
	return {"key": pc.key, "i": wood["i"], "ruin": ruin, "sp": int(pc.get_object(ruin).get("sp", 0)) if ruin >= 0 else -1, "stone": stone["i"], "doused": third["i"]}


# Total heat of everything burning that is loaded.
func _fire_heat(world, fs: FireSystem) -> float:
	var h := 0.0
	for key in fs._burning:
		var b: Dictionary = fs._burning[key]
		var c: Node = world.streamer.get_chunk(b["k"])
		if c != null:
			h += FireSim.heat((c as ChunkNode).get_object(int(b["i"]))["st"])
	return h
