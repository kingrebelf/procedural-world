extends SceneTree
## Prints the bounding box of kit models: godot --headless --script res://tools/probe_boxes.gd -- name ...
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		print(a, " ", KitHouse._model_box(a, Transform3D.IDENTITY))
	quit()
