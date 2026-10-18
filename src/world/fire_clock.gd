extends Node
## Autoload: runs the fires' clock (FireFx.time and the `fire_time` shader global) so every
## flame and its firelight read the same moment.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The fire_fx setting sets how many tongues every flame burns with.
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.changed.connect(func(): FireFx.apply_quality(get_tree()))

func _process(delta: float) -> void:
	FireFx.tick(delta)
