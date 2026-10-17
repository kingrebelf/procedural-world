extends SceneTree
## Screenshots of the minimap and atlas with each map overlay (MapLayers):
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --script res://tools/preview_map_layers.gd -- [x z [chunks]]
## Paints and uncovers a square of land round world point (x, z) (default 1250, 300: the
## Medieval lands' edge), stands there and saves user://screenshots/layers_*.png.

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("layers_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var game = root.get_node("/root/Game")
	game.new_world("Layer preview", "4242")
	var args := OS.get_cmdline_user_args()
	var at := Vector2(1250, 300)
	var n := 20
	if args.size() >= 2:
		at = Vector2(args[0].to_float(), args[1].to_float())
	if args.size() >= 3:
		n = args[2].to_int()
	# Paint the land round the spot and lift the fog over it.
	var gen = load("res://src/world/chunk_generator.gd").new(game.seed)
	var c0 := Vector2i(floori(at.x / 64.0) - n / 2, floori(at.y / 64.0) - n / 2)
	var t0 := Time.get_ticks_msec()
	for cz in n:
		for cx in n:
			var ch: Dictionary = gen.generate(c0.x + cx, c0.y + cz)
			game.map.paint(ch)
			game.map.note_chunk(ch)
	game.map.reveal(at, n * 32.0)
	for k in 8:
		game.map.reveal(at + Vector2.from_angle(k * TAU / 8.0) * n * 20.0, n * 18.0)
	print("painted %d chunks in %d ms" % [n * n, Time.get_ticks_msec() - t0])
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.24, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3(at.x, 0, at.y)
	var mm: Control = load("res://src/ui/minimap.gd").new()
	mm.player = player
	mm.position = Vector2(1920 - 220 - 22, 18)
	mm.zoom = 2
	ui.add_child(mm)
	var menus = load("res://src/ui/game_menus.gd").new()
	ui.add_child(menus)
	var names := ["off", "levels", "danger", "era", "zones", "land"]
	for l in names.size():
		game.map.set_layer(l)
		load("res://src/ui/atlas_view.gd").set("_ppm", 0.09)
		menus.open("map")
		await _shot("atlas_" + names[l])
		menus.close()
		await _shot("minimap_" + names[l])
	quit()
