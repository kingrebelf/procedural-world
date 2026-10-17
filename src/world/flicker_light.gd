class_name FlickerLight
extends OmniLight3D
## Firelight: its brightness wavers like the flame it comes from, each fire out of step.

var base := 1.0 ## the steady brightness it wavers about
var _t := 0.0

func _ready() -> void:
	base = light_energy
	_t = fposmod(global_position.x * 1.7 + global_position.z * 2.3, 100.0)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	light_energy = base * (1.0 + 0.13 * sin(_t * 7.3) + 0.08 * sin(_t * 13.1 + 1.7) + 0.05 * sin(_t * 23.0))
