class_name QuadFeet
extends SkeletonModifier3D
## Keeps a four-legged animal's planted hooves and paws where they came down. The kit's
## walks ease every foot onto and off the ground, so at an even pace a planted hoof
## drifts along the ground (AnimMath.stance_warp evens out most of a gallop's, not a
## walk's, where three feet are down at once each at its own speed). Here each foot is
## pinned to the spot it landed on for as long as it bears weight, the leg bending to
## reach it (two-bone IK on the lower leg), and let go to catch up with the animation as
## it lifts. Runs after BodyFlex (so the bent spine keeps its feet) and before LookIK.
## The rigs' hooves are skinned to free IK controller bones at the end of each leg.

## How planted each foot is this frame, 0..1, in LEGS order (AnimalModel sets it from
## the clip's stance_weights; all 0 when standing, busy or not walking).
var stance := [0.0, 0.0, 0.0, 0.0]

## [hoof controller, upper joint, lower joint] per leg.
const LEGS := [["IKFrontLeg.L", "FrontUpperLeg.L", "FrontLowerLeg.L"], ["IKFrontLeg.R", "FrontUpperLeg.R", "FrontLowerLeg.R"],
	["IKBackLeg.L", "BackUpperLeg.L", "BackLowerLeg.L"], ["IKBackLeg.R", "BackUpperLeg.R", "BackLowerLeg.R"]]
## A pinned foot is let slide rather than held further than this share of its lower leg
## from where the animation has it (a sharp turn, a pace the clip can't keep up with).
const MAX_SLIP := 0.4

var _ready_bones := false
var _legs: Array = [] ## [hoof, upper, lower, leg length]
var _locked := [false, false, false, false]
var _at: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO] ## world spot pinned
var _off: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO] ## world correction
var _vel: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _last_ms := 0

func _setup(sk: Skeleton3D) -> void:
	_ready_bones = true
	for l in LEGS:
		var h := sk.find_bone(l[0])
		var u := sk.find_bone(l[1])
		var o := sk.find_bone(l[2])
		if h < 0 or u < 0 or o < 0:
			_legs.clear()
			return
		var len := sk.get_bone_global_rest(u).origin.distance_to(sk.get_bone_global_rest(o).origin) + sk.get_bone_global_rest(o).origin.distance_to(sk.get_bone_global_rest(h).origin)
		_legs.append([h, u, o, len])

## Forget where the feet were pinned (the body was moved, not walked).
func reset() -> void:
	for i in 4:
		_locked[i] = false
		_off[i] = Vector3.ZERO
		_vel[i] = Vector3.ZERO

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not sk.is_inside_tree():
		return
	if not _ready_bones:
		_setup(sk)
	if _legs.size() != 4:
		return
	var dt := clampf(delta, 0.0, 0.1)
	# Switched off a while (far away, out of sight): where the feet were is stale.
	var now := GameClock.msec()
	if now - _last_ms > 250:
		reset()
	_last_ms = now
	var gx := sk.global_transform
	var to_sk := gx.basis.inverse()
	var s := maxf(gx.basis.get_scale().y, 0.001)
	for i in 4:
		var leg: Array = _legs[i]
		var hoof := sk.get_bone_global_pose(leg[0])
		var p := gx * hoof.origin
		var w: float = stance[i]
		if w > 0.5:
			if not _locked[i]:
				_locked[i] = true
				# Pinned where it is drawn now, so a foot still catching up doesn't jump.
				_at[i] = p + (_off[i] as Vector3)
			var d: Vector3 = (_at[i] as Vector3) - p
			d.y = 0.0
			var most := float(leg[3]) * s * MAX_SLIP
			if d.length() > most:
				d = d.normalized() * most
				_at[i] = p + d
			_off[i] = d * smoothstep(0.5, 0.85, w)
			_vel[i] = Vector3.ZERO
		else:
			_locked[i] = false
			var o: Vector3 = _off[i]
			var v: Vector3 = _vel[i]
			var nx := AnimMath.spring(o.x, v.x, 0.0, 16.0, dt)
			var nz := AnimMath.spring(o.z, v.z, 0.0, 16.0, dt)
			_off[i] = Vector3(nx.x, 0.0, nz.x)
			_vel[i] = Vector3(nx.y, 0.0, nz.y)
		var off: Vector3 = _off[i]
		if off.length_squared() < 1e-8:
			continue
		var target := hoof.origin + to_sk * off
		var top := sk.get_bone_global_pose(leg[1])
		var mid := sk.get_bone_global_pose(leg[2])
		var foot_in_mid := mid.affine_inverse() * hoof.origin
		var a := top.origin.distance_to(mid.origin)
		var b := mid.origin.distance_to(hoof.origin)
		# The joint bends the way the animation already bends it.
		var pole := mid.origin + (mid.origin - (top.origin + hoof.origin) * 0.5)
		var knee := AnimMath.knee_for(top.origin, target, a, b, pole)
		top.basis = Basis(AnimMath.arc(mid.origin - top.origin, knee - top.origin)) * top.basis
		sk.set_bone_global_pose(leg[1], top)
		mid = sk.get_bone_global_pose(leg[2])
		mid.basis = Basis(AnimMath.arc(mid * foot_in_mid - mid.origin, target - mid.origin)) * mid.basis
		sk.set_bone_global_pose(leg[2], mid)
		hoof.origin = mid * foot_in_mid
		sk.set_bone_global_pose(leg[0], hoof)
