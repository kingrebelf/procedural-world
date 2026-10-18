extends Node
## Autoload: runs the fires' clock (FireFx.time and the `fire_time` shader global) so every
## flame and its firelight read the same moment.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	FireFx.tick(delta)
