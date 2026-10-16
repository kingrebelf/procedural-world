extends Node
## Screenshots of the title screen's live background, for checking it headless:
##   godot --path . -- --capture-menu   (shots go to user://screenshots/menu_*.png)

func _ready() -> void:
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 3:
		await get_tree().create_timer(15.0 if i == 0 else 10.0).timeout
		await RenderingServer.frame_post_draw
		var path := dir.path_join("menu_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
	get_tree().quit()
