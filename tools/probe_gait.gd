extends SceneTree
## Measures how well people's feet stay planted (HumanAnimator + HumanIK): walks a person
## across flat ground and up a slope at a range of speeds and reports, per speed, how fast
## the planted feet skate (it should not move at all), how high it sits above the ground
## and the gait blend chosen.
##   godot --headless --path . --script res://tools/probe_gait.gd

const SPEEDS := [0.4, 0.8, 1.35, 2.2, 3.6, 4.5, 6.0, 8.0]
const SLOPE := 0.3 ## rise per metre of x on the sloped run

var h: HumanModel
var v := 0.0
var slope := 0.0
var t := 0.0
var samples: Array = []
var runs: Array = []
var run := 0
var _prev := []
var _dt := 1.0 / 60.0
var _last_t := -1.0
var _latest := []

func ground(x: float, z: float) -> float:
	return x * slope

func _initialize() -> void:
	var lib_ok := HumanModel.available()
	if not lib_ok:
		print("people assets missing")
		quit()
		return
	for s in [0.0, SLOPE]:
		for sp in SPEEDS:
			runs.append([sp, s])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 2, -6)
	h = HumanModel.new()
	root.add_child(h)
	h.build({"height": 1.0, "build": 1.0, "female": false, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}, 0, "farmer")
	h.set_ground(Callable(self, "ground"))
	h.animator.lod = false
	h.skeleton.skeleton_updated.connect(_sample)
	_start()

func _start() -> void:
	v = runs[run][0]
	slope = runs[run][1]
	t = 0.0
	samples.clear()
	_prev = []
	h.global_position = Vector3(-2.0, ground(-2.0, -6.0), -6.0)
	h.rotation = Vector3.ZERO
	h.play("walk")

func _process(delta: float) -> bool:
	_measure()
	delta = maxf(delta, 0.001)
	_dt = delta
	t += delta
	# Walk along +z (across the slope's fall line when slope is in x: tests the feet's
	# side-to-side fitting), then diagonally up it.
	var dir := Vector3(0.6, 0, 0.8).normalized() if slope > 0.0 else Vector3(0, 0, 1)
	var p := h.global_position + dir * v * delta
	p.y = ground(p.x, p.z)
	h.global_position = p
	h.rotation.y = atan2(dir.x, dir.z)
	h.play("walk")
	if t > 4.0:
		_report()
		run += 1
		if run >= runs.size():
			return true
		_start()
	return false

## The skeleton can report more than once a frame; the last report is the frame's pose.
func _sample() -> void:
	var sk := h.skeleton
	_latest.clear()
	for b in ["ball_l", "ball_r"]:
		_latest.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin)

func _measure() -> void:
	if t < 1.5 or _latest.size() != 2:
		_prev = _latest.duplicate()
		_last_t = t
		return
	if _prev.size() == 2:
		var dt := t - _last_t
		for i in 2:
			var f: Vector3 = _latest[i]
			var hgt := f.y - ground(f.x, f.z)
			var was: Vector3 = _prev[i]
			if hgt < 0.03 and was.y - ground(was.x, was.z) < 0.03:
				samples.append([Vector2(f.x - was.x, f.z - was.z).length() / dt, hgt])
	_prev = _latest.duplicate()
	_last_t = t

func _report() -> void:
	var hs := []
	var sk := []
	for s in samples:
		sk.append(float(s[0]))
		hs.append(float(s[1]))
	sk.sort()
	var skate: float = sk[sk.size() / 2] if not sk.is_empty() else NAN
	hs.sort()
	var med: float = hs[hs.size() / 2] if not hs.is_empty() else NAN
	var g := HumanAnimator.solve(v, h.animator._gait)
	print("%s v=%.2f m/s: planted feet skate %.3f m/s (median of %d) (%.0f%% of speed), planted toes %.3f m up, gait w=%s cycle=%.2fs" % [
		"slope" if slope > 0.0 else "flat ", v, skate, sk.size(), 100.0 * skate / v, med, g["w"], g["cycle"]])
