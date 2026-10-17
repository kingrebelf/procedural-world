class_name FlickerLight
extends OmniLight3D
## Firelight: it leaps and sinks with the flame it comes from (the flame beside it: the
## nearest FireFx flame among its parent's children, whose seed it takes, so both read
## the same FireFx.life) and warms as it sinks. Each fire is out of step with the others.
## It rests when it is too far off to be seen. It never moves: a shadow-casting light
## that moves has its shadows redrawn every frame, with every stall and its wares in
## reach, and a town has many of these lights.

var base := 1.0 ## the steady brightness it wavers about
var seed := -1.0 ## the flame's seed (FireFx.flame), or below 0 to find it at _ready
var depth := 0.45 ## how far it wavers: 0.45 a torch or hearth, less for a candle
var _col := Color.WHITE

func _ready() -> void:
	base = light_energy
	_col = light_color
	if seed < 0.0:
		_follow_flame()

## Takes the seed of the nearest flame beside it, within a few metres.
func _follow_flame() -> void:
	var best: Node3D = null
	var bd := 3.0
	var p := get_parent()
	if p != null:
		for c in p.find_children("Flame*", "Node3D", true, false):
			if c.has_meta("fire_seed"):
				var d := _within(c as Node3D, p).distance_to(position)
				if d < bd:
					bd = d
					best = c
	if best != null:
		seed = float(best.get_meta("fire_seed"))
		var fs := float(best.get_meta("fire_size", 0.5))
		if fs < FireFx.SMALL:
			# A candle or lamp burns steadier than an open fire.
			depth = 0.22
	else:
		var at := global_position if is_inside_tree() else position
		seed = fposmod(at.x * 0.0173 + at.z * 0.0291, 1.0)

## Where n stands in p's space (p one of its parents); works before either is in the tree.
static func _within(n: Node3D, p: Node) -> Vector3:
	var xf := n.transform
	var q := n.get_parent()
	while q != null and q != p:
		if q is Node3D:
			xf = (q as Node3D).transform * xf
		q = q.get_parent()
	return xf.origin

func _process(_delta: float) -> void:
	if not visible:
		return
	if distance_fade_enabled:
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam != null and cam.global_position.distance_squared_to(global_position) > pow(distance_fade_begin + distance_fade_length, 2.0):
			return
	var t := FireFx.time
	var l := FireFx.life(t, seed)
	light_energy = base * (1.0 + depth * (l - 0.5) * 2.0)
	# A low flame burns redder.
	light_color = _col.lerp(Color(1.0, 0.42, 0.16), clampf((0.5 - l) * 0.35, 0.0, 0.2))
