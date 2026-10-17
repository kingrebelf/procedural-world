extends SceneTree
## Measures how well animals' hooves and paws stay planted: moves each kit animal at a
## range of speeds and reports how fast the planted feet skate.
##   godot --headless --path . --script res://tools/probe_animal_gait.gd

const KINDS := ["Deer", "Wolf", "Horse", "Cow", "Fox"]
const SPEEDS := [0.7, 1.4, 2.5, 4.0, 6.0, 8.0]

var a: AnimalModel
var runs: Array = []
var run := 0
var t := 0.0
var v := 0.0
var samples: Array = []
var _feet: Array = []
var _prev: Array = []
var _latest: Array = []
var _last_t := 0.0

func _initialize() -> void:
	for k in KINDS:
		for sp in SPEEDS:
			runs.append([k, sp])
	_start()

func _start() -> void:
	if a:
		a.free()
	var kind: String = runs[run][0]
	v = runs[run][1]
	a = AnimalModel.new()
	root.add_child(a)
	a.build(kind)
	a.lod = false
	var sk: Skeleton3D = a.find_children("*", "Skeleton3D", true, false)[0]
	sk.skeleton_updated.connect(_sample.bind(sk))
	_feet.clear()
	for b in ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]:
		var i := sk.find_bone(b)
		_feet.append([i, Vector3(0, sk.get_bone_global_rest(i).origin.y, 0)])
	t = 0.0
	samples.clear()
	_prev.clear()
	_latest.clear()

func _sample(sk: Skeleton3D) -> void:
	_latest.clear()
	for f in _feet:
		_latest.append(sk.global_transform * (sk.get_bone_global_pose(f[0]) * (f[1] as Vector3)))

func _process(delta: float) -> bool:
	if t > 1.5 and _latest.size() == 4 and _prev.size() == 4:
		var dt := t - _last_t
		var low := 0.05 * a.global_basis.get_scale().y + 0.03
		for i in 4:
			if (_latest[i] as Vector3).y < low and (_prev[i] as Vector3).y < low:
				samples.append(Vector2(_latest[i].x - _prev[i].x, _latest[i].z - _prev[i].z).length() / dt)
	_prev = _latest.duplicate()
	_last_t = t
	t += delta
	a.global_position += Vector3(0, 0, v * delta)
	a.play("Walk")
	if t > 4.0:
		samples.sort()
		var med: float = samples[samples.size() / 2] if not samples.is_empty() else NAN
		print("%-6s v=%.1f m/s: %s at %.2fx, planted feet skate %.2f m/s (%.0f%%, %d samples)" % [runs[run][0], v, a._current, a.anim.speed_scale, med, 100.0 * med / v, samples.size()])
		run += 1
		if run >= runs.size():
			return true
		_start()
	return false
