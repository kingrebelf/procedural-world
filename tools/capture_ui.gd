extends SceneTree
## Screenshots of the HUD and menus over a still background, without streaming a world:
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --script res://tools/capture_ui.gd -- [background.png]
## Shots go to user://screenshots/ui_*.png.

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("ui_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var game = root.get_node("/root/Game")
	game.new_world("UI capture", "777")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var img := Image.load_from_file(args[0])
		if img:
			# Only the top of the shot: game screenshots carry the HUD along the bottom.
			img = img.get_region(Rect2i(0, 0, img.get_width(), int(img.get_height() * 0.6)))
			var bg := TextureRect.new()
			bg.texture = ImageTexture.create_from_image(img)
			bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ui.add_child(bg)
	var item_db = load("res://src/items/item_db.gd")
	for t in ["pickaxe_iron", "axe_iron", "sword_iron", "bread", "torch", "wood", "stone", "iron_ingot", "helm_iron", "mail_iron", "gloves_leather", "greaves_iron", "boots_elven", "shield_crystal", "pulse_pistol", "glowberry"]:
		if item_db.ITEMS.has(t):
			game.give(item_db.make(t, 3 if item_db.is_stackable(t) else 1, 1.0, {}))
	# Loaded by path: naming these classes here would compile them before the autoloads.
	var hud: Control = load("res://src/ui/hud.gd").new()
	ui.add_child(hud)
	var menus = load("res://src/ui/game_menus.gd").new()
	ui.add_child(menus)
	await _shot("hud")
	# Wear a couple of pieces so the body shows both empty and filled slots.
	for i in game.inventory.capacity:
		var it = game.inventory.get_slot(i)
		if it != null and (it["type"] == "mail_iron" or it["type"] == "helm_iron"):
			game.equip(i)
	for m in ["inventory", "character", "craft", "pause"]:
		menus.open(m)
		await _shot(m)
	# A few crafting tabs, and the search with "Can craft now".
	for tab in ["Ammo", "Armour"]:
		menus._craft_tab = tab
		menus.open("craft")
		await _shot("craft_" + tab.to_lower())
	menus._craft_tab = "All"
	menus._craft_find = "iron"
	menus._craft_ready_only = true
	menus.open("craft")
	await _shot("craft_search")
	menus.close()
	quit()
