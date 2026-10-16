extends SceneTree
func _initialize():
	_go.call_deferred()
func _go():
	for f in ["res://src/world/chunk_node.gd", "res://src/world/chunk_streamer.gd", "res://src/fauna/fauna_manager.gd", "res://src/fauna/creature.gd", "res://src/world/world.gd", "res://src/player/player.gd", "res://src/ui/hud.gd", "res://src/ui/settings_menu.gd", "res://src/env/water.gd", "res://src/env/atmosphere.gd"]:
		var s = load(f)
		print(f, " -> ", s != null and s.can_instantiate())
	quit()
