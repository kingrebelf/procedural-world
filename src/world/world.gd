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
var vehicles: VehicleManager
var dialogue: DialogueUI

func _ready() -> void:
	if not Game.is_playing():
		# Launched directly (e.g. from the editor): open a scratch world.
		var seed_arg := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--seed="):
				seed_arg = a.substr(7)
		Game.new_world("Quick World", seed_arg)
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	BuildCatalog.warm_kits()
	streamer = ChunkStreamer.new()
	streamer.name = "Chunks"
	add_child(streamer)
	player = Player.new()
	player.name = "Player"
	player.streamer = streamer
	add_child(player)
	Game.player = player
	if Game.pending_player_state is Dictionary and Game.pending_player_state.has("pos"):
		player.set_state(Game.pending_player_state)
	else:
		player.global_position = find_spawn()
	streamer.set_target(player)
	atmosphere.target = player
	var water := Water.new()
	water.name = "Water"
	water.target = player
	water.atmosphere = atmosphere
	water.streamer = streamer
	add_child(water)

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
	vehicles = VehicleManager.new()
	vehicles.name = "Vehicles"
	vehicles.streamer = streamer
	vehicles.player = player
	add_child(vehicles)
	player.vehicles = vehicles
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
	console = DevConsole.new()
	console.player = player
	ui.add_child(console)

	Settings.changed.connect(_apply_settings)
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_cmdline_user_args().has("--capture") and ResourceLoader.exists("res://tools/capture.gd") and not get_tree().root.has_node("CaptureTour"):
		var cap: Node = load("res://tools/capture.gd").new()
		cap.name = "CaptureTour"
		cap.world = self
		add_child(cap)

func _apply_settings() -> void:
	streamer.apply_settings(int(Settings.get_value("view_distance")), float(Settings.get_value("grass_density")))

## Death: a few seconds of "You died", then you wake at the world's spawn point with your
## pack intact, minus some of the progress toward your next level.
func _on_died(cause: String) -> void:
	player.dismount(true)
	player.ui_open = true
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(cause)
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	Game.stats.xp = int(Game.stats.xp * 0.75)
	player.global_position = find_spawn() + Vector3(0, 2, 0)
	player.velocity = Vector3.ZERO
	player.frozen = true
	player.snap_down = true
	player.breath = Game.stats.max_breath()
	Game.revive()
	Game.stats_changed.emit()
	hud.hide_death()
	player.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.toast.emit("You wake where you first arrived. Your pack is safe.")

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
	Game.save_all()
