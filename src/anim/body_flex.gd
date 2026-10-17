class_name BodyFlex
extends SkeletonModifier3D
## A four-legged animal's body is not a plank: over its animation, the spine curves into a
## turn with the neck leading, the tail lags out the other way and swishes on its own,
## and now and then an ear flicks. Runs before LookIK. The skeleton faces +Z.
## Turns and flicks are springs (AnimMath.spring), so they ease in and settle.

## Turn rate of the body, radians a second (+ toward +X), and 0..1 how much it is moving.
var yaw_rate := 0.0
var moving := 0.0

## Share of the spine's bend per bone, hips to neck. Most of the curve is in the neck, so
## the shoulders (and the front legs on them) stay over their planted hooves.
const SPINE := {"Torso": 0.1, "Torso2": 0.14, "Torso3": 0.1, "Neck1": 0.33, "Neck2": 0.33}
## Bend per radian a second of turning, and its limit (radians, the whole spine).
const BEND := 0.3
const MAX_BEND := 0.55
## How far the tail swings out of a turn per radian a second, and its limit.
const TAIL := 0.35
const MAX_TAIL := 0.6

var _ready_bones := false
var _spine: Array = [] ## [bone, share]
var _tail: Array = [] ## bones, root to tip
var _ears: Array = [] ## Ear roots
var _bend := Vector2.ZERO
var _tail_s := Vector2.ZERO
var _flick: Array = [] ## per ear: Vector2 spring
var _t := 0.0
var _seed := 0.0
var _next_flick := 0.0

func _setup(sk: Skeleton3D) -> void:
	_ready_bones = true
	var total := 0.0
	for n in SPINE:
		var b := sk.find_bone(n)
		if b >= 0:
			_spine.append([b, SPINE[n]])
			total += float(SPINE[n])
	for e in _spine:
		e[1] = float(e[1]) / maxf(total, 0.01)
	for i in range(1, 12):
		var b := sk.find_bone("Tail%d" % i)
		if b < 0:
			break
		_tail.append(b)
	for n in ["Ear1.L", "Ear1.R"]:
		var b := sk.find_bone(n)
		if b >= 0:
			_ears.append(b)
			_flick.append(Vector2.ZERO)
	_seed = randf() * TAU
	_t = randf() * 100.0
	_next_flick = randf_range(1.0, 6.0)

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not sk.is_inside_tree():
		return
	if not _ready_bones:
		_setup(sk)
	var dt := clampf(delta, 0.0, 0.1)
	_t += dt
	var up := (sk.global_basis.inverse() * Vector3.UP).normalized()
	var right := up.cross(Vector3(0, 0, 1)).normalized()
	# The spine curves into the turn.
	_bend = AnimMath.spring(_bend.x, _bend.y, clampf(yaw_rate * BEND, -MAX_BEND, MAX_BEND), 5.0, dt)
	if absf(_bend.x) > 1e-4:
		for e in _spine:
			var g := sk.get_bone_global_pose(e[0])
			g.basis = Basis(Quaternion(up, _bend.x * float(e[1]))) * g.basis
			sk.set_bone_global_pose(e[0], g)
	# The tail trails out of the turn, a beat behind, and swishes now and then.
	if not _tail.is_empty():
		var swish := AnimMath.drift(_t * (0.9 + moving * 1.4), _seed) * lerpf(0.22, 0.1, moving)
		var want := clampf(-yaw_rate * TAIL, -MAX_TAIL, MAX_TAIL) + swish
		_tail_s = AnimMath.spring(_tail_s.x, _tail_s.y, want, 3.2, dt)
		var per := _tail_s.x / float(_tail.size())
		for b in _tail:
			var g := sk.get_bone_global_pose(b)
			# Sideways whichever way this bone points (out behind, or hanging down).
			var axis := g.basis.y.normalized().cross(right)
			if axis.length() < 0.01:
				continue
			g.basis = Basis(Quaternion(axis.normalized(), per)) * g.basis
			sk.set_bone_global_pose(b, g)
	# An ear flicks back now and then, more often standing about.
	if not _ears.is_empty():
		_next_flick -= dt
		if _next_flick <= 0.0:
			_next_flick = randf_range(2.0, 9.0) * (1.0 + moving * 2.0)
			var which := randi() % _ears.size()
			var f: Vector2 = _flick[which]
			_flick[which] = Vector2(f.x, f.y - randf_range(9.0, 14.0))
			if randf() < 0.25 and _ears.size() > 1:
				var o: Vector2 = _flick[1 - which]
				_flick[1 - which] = Vector2(o.x, o.y - randf_range(6.0, 10.0))
		for i in _ears.size():
			var f: Vector2 = _flick[i]
			f = AnimMath.spring(f.x, f.y, 0.0, 14.0, dt)
			_flick[i] = f
			if absf(f.x) < 1e-3:
				continue
			var g := sk.get_bone_global_pose(_ears[i])
			g.basis = Basis(Quaternion(right, f.x)) * g.basis
			sk.set_bone_global_pose(_ears[i], g)
