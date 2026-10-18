class_name WindowLight
extends SpotLight3D
## Daylight in through a window: the sky seen through the pane lights the room softly,
## the wall opposite and the floor below it most. SDFGI alone left a cottage near black at
## noon (its cells are coarser than a small window). No shadows and no highlights, so it
## costs little; Atmosphere sets every one's energy as the day goes (window_fill), and
## at night they are out.

const GROUP := &"window_light"

## A window's light, `at` the pane's middle and `into` the way into the room, in its
## building's own space.
static func make(at: Vector3, into: Vector3) -> WindowLight:
	var l := WindowLight.new()
	l.add_to_group(GROUP)
	l.light_color = Color(0.88, 0.92, 1.0)
	l.light_energy = Atmosphere.window_fill
	l.visible = Atmosphere.window_fill > 0.0
	l.light_specular = 0.0
	l.shadow_enabled = false
	l.spot_range = 6.0
	l.spot_angle = 75.0
	l.spot_attenuation = 1.0
	l.spot_angle_attenuation = 1.6
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 10.0
	l.position = at + into * 0.25
	l.basis = Basis.looking_at(into, Vector3.UP)
	return l
