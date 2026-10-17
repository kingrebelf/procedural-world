extends SceneTree
## Lists coplanar, overlapping upward faces from different surfaces (or between a
## building and its furniture), which flicker against each other ("z-fighting"):
## godot --headless --script res://tools/probe_zfight.gd [-- type ...]
func _init() -> void:
	var types: Array = OS.get_cmdline_user_args()
	if types.is_empty():
		types = ZFight.building_types()
	var bad := 0
	for t in types:
		for f in ZFight.find(t):
			print(t, ": ", f)
			bad += 1
		if KitHouse.has(t) or Interiors.has(t):
			for f in ZFight.items(t):
				print(t, " items: ", f)
	print("zfight: %d" % bad)
	quit()
