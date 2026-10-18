class_name HumanIK
extends SkeletonModifier3D
## Runs after a person's animation every frame and fits it to the world:
## - Feet on the ground: each foot is lifted or lowered to the ground under it, the hips
##   drop for the lower foot, the knees bend to match (two-bone IK) and planted feet tilt
##   to the slope, so people stand and walk on hillsides and steps instead of floating
##   over or sinking into them. On the move, a foot that has come down stays on the spot
##   it landed on (pinned by the ball of the foot, so it still rolls heel to toe) until it
##   lifts: the clips' eased strides would otherwise slide it along the ground.
## - Looking: the eyes lead, then the head, neck and chest turn toward what the person
##   looks at (whoever is talking to them, something that caught their eye), within what a
##   neck can do and easing in and out.
## - Leaning: banking into turns and tipping with speeding up and slowing down (set by
##   HumanAnimator), and breathing in the chest and shoulders: each person at their own
##   pace, quick and deep after a run, slowing as they get their breath back.
## Turns ease in and settle like muscles do (critically damped springs, AnimMath.spring):
## a fixed lerp starts at full speed and stops dead, which reads as a machine.

## Ground height under a point: Callable(x, z) -> float (NAN if unknown). Without one,
## the ground is found by casting rays against the world (mask `ray_mask`).
var ground := Callable()
var ray_mask := 1
var ray_exclude: Array[RID] = []
var feet_on := true ## by distance (HumanAnimator's LOD)
var feet_allowed := true ## by what the body is doing (not sitting, swimming, lying down)
var feet_here := true ## by where it is (off on floors the ground source doesn't know)
var pin_on := false ## planted feet held where they landed (HumanAnimator: while on the move)
var look_on := true
## World point to look at, and how much (0..1). INF for none.
var look_target := Vector3.INF
var look_weight := 0.0
## x: bank (roll toward the inside of a turn), y: tip forward. Radians.
var lean := Vector2.ZERO
var breathe := true
var near := true ## by distance (HumanAnimator's LOD): breathing only shows close up
## 0 rested .. 1 winded (HumanAnimator raises it while running, it ebbs after).
var exertion := 0.0

## [bone, share of the yaw, share of the pitch, leads]: the head and neck lead and the chest
## follows them round a beat later, as eyes, then head, then body turn to look.
const LOOK_CHAIN := [["spine_02", 0.12, 0.0, false], ["spine_03", 0.18, 0.15, false], ["neck_01", 0.3, 0.35, true], ["Head", 0.4, 0.5, true]]
## Spring rates (1/s): how briskly the head and the chest come round, and the look fades.
const HEAD_RATE := 9.0
const CHEST_RATE := 3.8
const LOOK_FADE := 4.5
const MAX_YAW := 1.25
const MAX_PITCH := 0.6
## A ground step bigger than this under one foot is a wall, a floor or a jump, not a slope.
const MAX_STEP := 0.55
## Furthest (metres) a pinned foot is held from where the animation has it; past that it
## slides with the body (a sharp turn, a sudden stop).
const MAX_PIN := 0.16

var _ready_bones := false
var _pelvis := -1
var _spine1 := -1
var _legs: Array = [] ## [thigh, calf, foot, upper length, lower length]
## Leg length against the rest skeleton's (BodyPosture.leg_len: a child's short legs).
var leg_len := 1.0
var _look_bones: Array = []
var _clav := [-1, -1]
var _balls := [-1, -1]
var _pinned := [false, false]
var _pin_at := [Vector3.ZERO, Vector3.ZERO] ## world spot the ball of each foot is pinned to
var _pin := [Vector3.ZERO, Vector3.ZERO] ## world correction now
var _pin_v := [Vector3.ZERO, Vector3.ZERO]
var _spine3 := -1
var _drop := 0.0
var _d := [0.0, 0.0]
## Look springs: [value, velocity] for the leading head and the following chest.
var _hy := Vector2.ZERO
var _hp := Vector2.ZERO
var _by := Vector2.ZERO
var _bp := Vector2.ZERO
var _w := Vector2.ZERO
var _t := 0.0
var _seed := 0.0
var _breath := 0.0
var _breath_rate := 1.0

func _bones(sk: Skeleton3D) -> bool:
	if _ready_bones:
		return _pelvis >= 0
	_ready_bones = true
	_pelvis = sk.find_bone("pelvis")
	_spine1 = sk.find_bone("spine_01")
	for s in ["l", "r"]:
		var th := sk.find_bone("thigh_" + s)
		var ca := sk.find_bone("calf_" + s)
		var fo := sk.find_bone("foot_" + s)
		if th < 0 or ca < 0 or fo < 0:
			_legs.clear()
			break
		var a := sk.get_bone_global_rest(th).origin.distance_to(sk.get_bone_global_rest(ca).origin)
		var b := sk.get_bone_global_rest(ca).origin.distance_to(sk.get_bone_global_rest(fo).origin)
		_legs.append([th, ca, fo, a, b])
	for e in LOOK_CHAIN:
		var b := sk.find_bone(e[0])
		if b >= 0:
			_look_bones.append([b, e[1], e[2], e[3]])
	_clav = [sk.find_bone("clavicle_l"), sk.find_bone("clavicle_r")]
	_balls = [sk.find_bone("ball_l"), sk.find_bone("ball_r")]
	_spine3 = sk.find_bone("spine_03")
	# Nobody breathes or fidgets in step with anyone else.
	_seed = randf() * TAU
	_breath = randf() * TAU
	_breath_rate = randf_range(0.85, 1.15)
	_t = randf() * 100.0
	return _pelvis >= 0

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not _bones(sk) or not sk.is_inside_tree():
		return
	var dt := clampf(delta, 0.0, 0.1)
	_t += dt
	var gx := sk.global_transform
	var inv := gx.basis.inverse()
	var up := (inv * Vector3.UP).normalized()
	var s := maxf(gx.basis.get_scale().y, 0.01)
	_lean_and_breathe(sk, up, dt)
	_feet(sk, gx, up, s, dt)
	_look(sk, gx, up, dt)

func _lean_and_breathe(sk: Skeleton3D, up: Vector3, dt: float) -> void:
	if _spine1 < 0:
		return
	var fwd := Vector3(0, 0, 1)
	var right := up.cross(fwd).normalized()
	if lean != Vector2.ZERO:
		var g := sk.get_bone_global_pose(_spine1)
		g.basis = Basis(Quaternion(fwd, lean.x) * Quaternion(right, lean.y)) * g.basis
		sk.set_bone_global_pose(_spine1, g)
	if not breathe or not near:
		return
	# About 15 breaths a minute at rest, nearer 40 and much deeper when winded.
	var period := lerpf(3.9, 1.5, exertion) / _breath_rate
	_breath = fmod(_breath + dt * TAU / period, TAU * 64.0)
	var depth := 1.0 + exertion * 2.2
	var inhale := sin(_breath)
	# The chest lifts and opens, and the shoulders rise a little with it.
	var chest := _spine3 if _spine3 >= 0 else _spine1
	var c := sk.get_bone_global_pose(chest)
	c.basis = Basis(Quaternion(right, -inhale * 0.012 * depth)) * c.basis
	sk.set_bone_global_pose(chest, c)
	var lift := (inhale * 0.5 + 0.5) * 0.02 * depth
	for i in 2:
		if _clav[i] < 0:
			continue
		var g := sk.get_bone_global_pose(_clav[i])
		g.basis = Basis(Quaternion(fwd, -lift if i == 0 else lift)) * g.basis
		sk.set_bone_global_pose(_clav[i], g)

## Height of the ground under world point `p`, and its normal; [NAN, UP] if unknown.
func _ground_at(p: Vector3) -> Array:
	if ground.is_valid():
		var h: float = ground.call(p.x, p.z)
		if is_nan(h):
			return [NAN, Vector3.UP]
		var e := 0.3
		var hx: float = ground.call(p.x + e, p.z)
		var hz: float = ground.call(p.x, p.z + e)
		var n := Vector3.UP
		if not is_nan(hx) and not is_nan(hz):
			n = Vector3(h - hx, e, h - hz).normalized()
		return [h, n]
	var space := get_skeleton().get_world_3d().direct_space_state if get_skeleton().is_inside_tree() else null
	if space == null:
		return [NAN, Vector3.UP]
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.7, p + Vector3.DOWN * 0.8, ray_mask, ray_exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return [NAN, Vector3.UP]
	return [float((hit["position"] as Vector3).y), hit["normal"]]

func _feet(sk: Skeleton3D, gx: Transform3D, up: Vector3, s: float, dt: float) -> void:
	var on := feet_on and feet_allowed and feet_here and _legs.size() == 2
	var k := clampf(dt * 12.0, 0.0, 1.0)
	var base := gx.origin.y
	var anim_feet := []
	var normals := []
	for i in 2:
		var leg: Array = _legs[i] if _legs.size() == 2 else []
		var want := 0.0
		var n := Vector3.UP
		if on:
			var f := sk.get_bone_global_pose(leg[2])
			anim_feet.append(f)
			var g := _ground_at(gx * f.origin)
			if not is_nan(g[0]):
				var d: float = float(g[0]) - base
				if absf(d) < MAX_STEP:
					want = d
					n = g[1]
		_d[i] = lerpf(_d[i], want, k)
		normals.append(n)
	if _legs.size() != 2:
		return
	if anim_feet.size() != 2:
		anim_feet = [sk.get_bone_global_pose(_legs[0][2]), sk.get_bone_global_pose(_legs[1][2])]
	var pins := _pins(sk, gx, up, s, dt, on and pin_on)
	# The hips come down only as far as a leg needs to reach its foot's ground: on a
	# slope the downhill leg straightens before the body sinks.
	var drop := 0.0
	if on:
		for i in 2:
			var leg: Array = _legs[i]
			var hip := sk.get_bone_global_pose(leg[0]).origin
			var target: Vector3 = (anim_feet[i] as Transform3D).origin + up * (_d[i] / s) + (pins[i] as Vector3)
			var reach := (float(leg[3]) + float(leg[4])) * leg_len
			var anim_len := hip.distance_to((anim_feet[i] as Transform3D).origin)
			# Never straighter than the animation already holds the leg (or nearly straight).
			var allowed := maxf(anim_len, reach * 0.97)
			var over := hip.distance_to(target) - allowed
			if over > 0.0:
				# How far down the hip must go for the target to come within reach.
				var to := target - hip
				var vert := -to.dot(up)
				var flat := sqrt(maxf(to.length_squared() - vert * vert, 0.0))
				var need := vert - sqrt(maxf(allowed * allowed - flat * flat, 0.0)) if allowed > flat else vert
				drop = minf(drop, -maxf(need, 0.0) * s)
	drop = maxf(drop, -MAX_STEP)
	_drop = lerpf(_drop, drop, k)
	if not on and absf(_drop) < 0.002 and absf(_d[0]) < 0.002 and absf(_d[1]) < 0.002 and (pins[0] as Vector3).is_zero_approx() and (pins[1] as Vector3).is_zero_approx():
		return
	# The hips come down for the lower foot.
	var pg := sk.get_bone_global_pose(_pelvis)
	pg.origin += up * (_drop / s)
	sk.set_bone_global_pose(_pelvis, pg)
	for i in 2:
		var leg: Array = _legs[i]
		var f0: Transform3D = anim_feet[i]
		var target: Vector3 = f0.origin + up * (_d[i] / s) + (pins[i] as Vector3)
		var h := sk.get_bone_global_pose(leg[0])
		var kn := sk.get_bone_global_pose(leg[1])
		# Knees bend forward, the way the animation already bends them.
		var knee := AnimMath.knee_for(h.origin, target, float(leg[3]) * leg_len, float(leg[4]) * leg_len, kn.origin + Vector3(0, 0, 0.3))
		h.basis = Basis(AnimMath.arc(kn.origin - h.origin, knee - h.origin)) * h.basis
		sk.set_bone_global_pose(leg[0], h)
		kn = sk.get_bone_global_pose(leg[1])
		var fo := sk.get_bone_global_pose(leg[2])
		kn.basis = Basis(AnimMath.arc(fo.origin - kn.origin, target - kn.origin)) * kn.basis
		sk.set_bone_global_pose(leg[1], kn)
		# The foot keeps its animated angle, tilted to the slope while it bears weight.
		fo = sk.get_bone_global_pose(leg[2])
		var height := (f0.origin - (gx.affine_inverse() * Vector3(0, base, 0))).dot(up) * s
		var plant := clampf(1.0 - (height - 0.08) / 0.12, 0.0, 1.0)
		var ns := (gx.basis.inverse() * (normals[i] as Vector3)).normalized()
		var tilt := Quaternion.IDENTITY.slerp(AnimMath.arc(up, ns), plant * 0.85)
		sk.set_bone_global_pose(leg[2], Transform3D(Basis(tilt) * f0.basis, fo.origin))

## Per foot, how far (skeleton space) to shift it to keep a planted foot where it landed:
## the ball of the foot is held on its world spot while the animation has it down (within
## 3 cm of its ground), let go as it lifts, and the correction springs back to nothing.
func _pins(sk: Skeleton3D, gx: Transform3D, up: Vector3, s: float, dt: float, on: bool) -> Array:
	var out := [Vector3.ZERO, Vector3.ZERO]
	if _balls[0] < 0 or _balls[1] < 0:
		return out
	var to_sk := gx.basis.inverse()
	for i in 2:
		var ball := sk.get_bone_global_pose(_balls[i]).origin
		var p := gx * ball
		var down := 1.0 - smoothstep(0.03, 0.06, ball.dot(up) * s) if on else 0.0
		if down > 0.5:
			if not _pinned[i]:
				_pinned[i] = true
				_pin_at[i] = p + (_pin[i] as Vector3)
			var d: Vector3 = (_pin_at[i] as Vector3) - p
			d.y = 0.0
			if d.length() > MAX_PIN:
				d = d.normalized() * MAX_PIN
				_pin_at[i] = p + d
			_pin[i] = d * smoothstep(0.5, 0.85, down)
			_pin_v[i] = Vector3.ZERO
		else:
			_pinned[i] = false
			var o: Vector3 = _pin[i]
			var v: Vector3 = _pin_v[i]
			var nx := AnimMath.spring(o.x, v.x, 0.0, 18.0, dt)
			var nz := AnimMath.spring(o.z, v.z, 0.0, 18.0, dt)
			_pin[i] = Vector3(nx.x, 0.0, nz.x)
			_pin_v[i] = Vector3(nx.y, 0.0, nz.y)
		out[i] = to_sk * (_pin[i] as Vector3)
	return out

func _look(sk: Skeleton3D, gx: Transform3D, up: Vector3, dt: float) -> void:
	var yaw := 0.0
	var pitch := 0.0
	var want := 0.0
	if look_on and look_target != Vector3.INF and look_weight > 0.0 and not _look_bones.is_empty():
		var head := sk.get_bone_global_pose(_look_bones[-1][0]).origin
		var to := gx.affine_inverse() * look_target - head
		var flat := to - up * to.dot(up)
		yaw = atan2(flat.x, flat.z)
		pitch = atan2(to.dot(up), flat.length())
		want = look_weight
		if absf(yaw) > MAX_YAW + 0.5:
			want = 0.0 # behind them: they'd turn round, not wring their neck
		yaw = clampf(yaw, -MAX_YAW, MAX_YAW)
		pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)
	_w = AnimMath.spring(_w.x, _w.y, want, LOOK_FADE, dt)
	_w.x = clampf(_w.x, 0.0, 1.0)
	if want > 0.0:
		_hy = AnimMath.spring(_hy.x, _hy.y, yaw, HEAD_RATE, dt)
		_hp = AnimMath.spring(_hp.x, _hp.y, pitch, HEAD_RATE, dt)
		_by = AnimMath.spring(_by.x, _by.y, yaw, CHEST_RATE, dt)
		_bp = AnimMath.spring(_bp.x, _bp.y, pitch, CHEST_RATE, dt)
	if _look_bones.is_empty() or not look_on:
		return
	# A head is never held dead still: a slow drift of a degree or so over the look (seen
	# only close up).
	var dy := AnimMath.drift(_t * 0.55, _seed) * 0.022 if near else 0.0
	var dp := AnimMath.drift(_t * 0.47, _seed + 1.7) * 0.014 if near else 0.0
	var w := _w.x
	var fwd := Vector3(0, 0, 1)
	var right := up.cross(fwd).normalized()
	var turned := 0.0
	for e in _look_bones:
		var lead: bool = e[3]
		var y: float = (_hy.x if lead else _by.x) * float(e[1]) * w
		var p: float = (_hp.x if lead else _bp.x) * float(e[2]) * w
		if e == _look_bones[-1]:
			y += dy
			p += dp
		if absf(y) < 1e-4 and absf(p) < 1e-4:
			continue
		turned += y
		var axis := (Quaternion(up, turned) * right).normalized()
		var q := Quaternion(up, y) * Quaternion(axis, -p)
		var g := sk.get_bone_global_pose(e[0])
		g.basis = Basis(q) * g.basis
		sk.set_bone_global_pose(e[0], g)
