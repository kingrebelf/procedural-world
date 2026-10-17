extends Node3D
## The playable world scene: atmosphere, chunk streaming, player, HUD and menus.

var streamer: ChunkStreamer
var atmosphere: Atmosphere
var player: Player
var hud: HUD
var console: DevConsole
var menus: GameMenus
var npcs: NPCManager
var fauna: FaunaManager
var corpses: Corpses
var vehicles: VehicleManager
var boats: BoatManager
var dialogue: DialogueUI
var lore: LoreUI

func _ready() -> void:
	if not Game.is_playing():
		# Launched directly (e.g. from the editor): open a scratch world.
		var seed_arg := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--seed="):
				seed_arg = a.substr(7)
		# The capture tour defaults to one fixed world, so before and after shots compare.
		if seed_arg == "" and OS.get_cmdline_user_args().has("--capture"):
			seed_arg = "4242"
		Game.new_world("Quick World", seed_arg)
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	BuildCatalog.warm_kits()
	streamer = ChunkStreamer.new()
	streamer.name = "Chunks"
	add_child(streamer)
	streamer.chunk_ready.connect(func(n: ChunkNode): Game.map.note_chunk(n.data))
	var sites := TreasureSites.new()
	sites.name = "Treasure"
	sites.streamer = streamer
	add_child(sites)
	player = Player.new()
	player.name = "Player"
	player.streamer = streamer
	add_child(player)
	Game.player = player
	Audio.world = self
	if Game.pending_player_state is Dictionary and Game.pending_player_state.has("pos"):
		player.set_state(Game.pending_player_state)
	else:
		player.global_position = find_spawn()
	streamer.set_target(player)
	atmosphere.target = player
	atmosphere.streamer = streamer
	var water := Water.new()
	water.name = "Water"
	water.target = player
	water.atmosphere = atmosphere
	water.streamer = streamer
	add_child(water)
	var far := FarLand.new()
	far.name = "FarLand"
	far.target = player
	far.streamer = streamer
	add_child(far)

	npcs = NPCManager.new()
	npcs.name = "People"
	npcs.streamer = streamer
	npcs.player = player
	add_child(npcs)
	player.npcs = npcs
	fauna = FaunaManager.new()
	fauna.name = "Wildlife"
	fauna.streamer = streamer
	fauna.player = player
	fauna.npcs = npcs
	add_child(fauna)
	player.fauna = fauna
	corpses = Corpses.new()
	corpses.name = "Corpses"
	corpses.streamer = streamer
	corpses.player = player
	corpses.npcs = npcs
	add_child(corpses)
	npcs.corpses = corpses
	fauna.corpses = corpses
	player.corpses = corpses
	boats = BoatManager.new()
	boats.name = "Boats"
	boats.player = player
	boats.npcs = npcs
	add_child(boats)
	vehicles = VehicleManager.new()
	vehicles.name = "Vehicles"
	vehicles.streamer = streamer
	vehicles.player = player
	add_child(vehicles)
	player.vehicles = vehicles
	var fires := FireSystem.new()
	fires.name = "Fires"
	fires.streamer = streamer
	fires.atmosphere = atmosphere
	fires.player = player
	add_child(fires)
	Game.died.connect(_on_died)

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = HUD.new()
	ui.add_child(hud)
	hud.bind_player(player)
	menus = GameMenus.new()
	menus.player = player
	menus.streamer = streamer
	ui.add_child(menus)
	dialogue = DialogueUI.new()
	dialogue.player = player
	dialogue.menus = menus
	dialogue.manager = npcs
	ui.add_child(dialogue)
	var picking := LockpickUI.new()
	picking.player = player
	ui.add_child(picking)
	lore = LoreUI.new()
	lore.player = player
	ui.add_child(lore)
	console = DevConsole.new()
	console.player = player
	ui.add_child(console)
	if Net.is_client():
		var others := RemotePlayers.new()
		others.name = "OtherPlayers"
		add_child(others)
		var chat := ChatUI.new()
		chat.player = player
		ui.add_child(chat)

	Settings.changed.connect(_apply_settings)
	_apply_settings()
	Cursor.restore()
	if OS.get_cmdline_user_args().has("--capture") and ResourceLoader.exists("res://tools/capture.gd") and not get_tree().root.has_node("CaptureTour"):
		# --perf runs the performance probe (tools/perf_probe.gd) instead of the screenshots.
		var tour := "res://tools/perf_probe.gd" if OS.get_cmdline_user_args().has("--perf") else "res://tools/capture.gd"
		var cap: Node = load(tour).new()
		cap.name = "CaptureTour"
		cap.world = self
		add_child(cap)

	if OS.get_cmdline_user_args().has("--bench"):
		_auto_bench.call_deferred()

## --bench: run the performance test once the ground has loaded, print it and quit.
func _auto_bench() -> void:
	while player.frozen:
		await get_tree().process_frame
	for i in 300:
		await get_tree().process_frame
	var b := Benchmark.new()
	b.name = "Benchmark"
	b.world = self
	b.quit_when_done = true
	add_child(b)

func _apply_settings() -> void:
	streamer.apply_settings(int(Settings.get_value("view_distance")), float(Settings.get_value("grass_density")),
		float(Settings.get_value("detail_distance")))

## Death: everything you carry drops in a bag where you fell (marked on your map), a few
## seconds of "You died", then you wake at your house or the world's spawn point, empty
## handed and short some of the progress toward your next level.
func _on_died(cause: String) -> void:
	player.dismount(true)
	# A server can let players keep their things ("keep"); otherwise they drop in a bag.
	var dropped: bool = Game.server_option("death_penalty", "bag") != "keep"
	var bag := Game.pack_death_bag() if dropped else {}
	dropped = dropped and CorpseLoot.has_any(bag)
	if dropped and corpses.drop_bag(player.global_position, bag) == "":
		# Nowhere loaded to leave it (should not happen): keep it all instead.
		var inv := Inventory.new(DeathBag.SLOTS)
		inv.from_data(bag["items"])
		Storage.transfer_all(inv, Game.inventory)
		Game.add_money(int(bag["purse"]))
		Game.rewear(bag["worn"])
		dropped = false
	# Saved at once: the bag on its ground, your empty pack and the marker.
	Game.flush_chunks()
	Game.save_player()
	player.ui_open = true
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(cause)
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	Game.stats.xp = int(Game.stats.xp * 0.75)
	var home = Game.home_near(player.global_position)
	if home is Vector2:
		var h := npcs.ground(home.x, home.y)
		if is_nan(h):
			h = npcs.gen.field.height(home.x, home.y)
		player.global_position = Vector3(home.x, h + 1.5, home.y)
	else:
		player.global_position = find_spawn() + Vector3(0, 2, 0)
	player.velocity = Vector3.ZERO
	player.frozen = true
	player.snap_down = true
	player.breath = Game.stats.max_breath()
	Game.revive()
	Game.stats_changed.emit()
	hud.hide_death()
	player.ui_open = false
	Cursor.restore()
	Game.toast.emit(("You wake at your house." if home is Vector2 else "You wake where you first arrived.") + (" Your things are in a bag where you fell, marked on your map." if dropped else ""))

## A pleasant spawn: near the origin, on gentle ground. Deterministic per seed.
func find_spawn() -> Vector3:
	return Planets.spawn_point(Game.seed, Game.store != null and Game.store.has_rivers())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("shot_%d.png" % Time.get_unix_time_from_system())
		get_viewport().get_texture().get_image().save_png(path)
		Game.toast.emit("Screenshot saved")
	elif event.is_action_pressed("debug_overlay"):
		Settings.set_value("show_fps", not Settings.get_value("show_fps"))

func _exit_tree() -> void:
	Audio.world = null
	Game.save_all()
