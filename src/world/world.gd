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
	if OS.get_cmdline_user_args().has("--capture") and ResourceLoader.exists("res://tools/capture.gd"):
		var cap: Node = load("res://tools/capture.gd").new()
		cap.world = self
		add_child(cap)

func _apply_settings() -> void:
	streamer.apply_settings(int(Settings.get_value("view_distance")), float(Settings.get_value("grass_density")))

## A pleasant spawn: near the origin, on gentle ground. Deterministic per seed.
func find_spawn() -> Vector3:
	var g := ChunkGenerator.new(Game.seed)
	var best := Vector3(32, 0, 32)
	var best_slope := INF
	for n in 24:
		var x := 8.0 + (n % 6) * 9.0
		var z := 8.0 + int(n / 6) * 12.0
		var w := g.field.era_weights(x, z)
		var h0 := g.field.height(x, z, w)
		var s := absf(g.field.height(x + 2, z) - h0) + absf(g.field.height(x, z + 2) - h0)
		if h0 < Water.LEVEL + 1.0:
			s += 100.0
		if s < best_slope:
			best_slope = s
			best = Vector3(x, h0 + 1.0, z)
	return best

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
