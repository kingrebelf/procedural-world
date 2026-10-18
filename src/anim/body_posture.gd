class_name BodyPosture
extends SkeletonModifier3D
## How a person holds themselves, over whatever they are animated doing: the old stoop
## (back rounded, head pushed forward but still looking ahead, shoulders rolled in, knees
## a little bent with the hips lowered to match), others slouch or stand straight.
## Runs after the animation and before HumanIK, so the feet are still planted on the
## ground and the head still turns to look at things.

## 0 upright .. 1 badly stooped; a little below 0 stands tall.
var stoop := 0.0
## How far each shoulder joint sits in from the kit hero's broad frame (rest units, m).
var shoulder_in := 0.0
## Arms held out from the body (radians): the heavy don't hang their arms against their sides.
var arms_out := 0.0
## Side-to-side sway over each planted foot while walking (heavy builds), 0..1.
var waddle := 0.0
## A limp: + favours the right leg, - the left, by how much (0..1).
var limp := 0.0
## Standing weight on one leg: + the left, by how much (0..1). The hips tilt up on that
## side and shift over it, the back straightens against them.
var hip := 0.0
## Head size against the body: a child's head is large for its height (1 grown).
var head_scale := 1.0
## A child's rounder face: the head a little wider and shorter (0 grown .. 1 at four).
var head_round := 0.0
## Leg and forearm length against the kit body's (children's legs are short); the hips
## come down to keep the feet where the animation put them.
var leg_len := 1.0
var arm_len := 1.0
## Hand size (a child's hands are small).
var hand_scale := 1.0
## Neck length against the kit's (a child's neck is short).
var neck_len := 1.0
## Where the stride is: HumanAnimator.stride() (phase, how much on the move).
var animator: HumanAnimator

var _ready_bones := false
var _bones: Array = [] ## [bone, local axis (character x in the bone's frame), angle per stoop]
var _legs: Array = [] ## [thigh, calf, local axis thigh, local axis calf, leg length]
var _pelvis := -1
var _arms: Array = [] ## [upper arm, its rest position from the clavicle, local forward axis, side +1 left]
var _roll := -1 ## spine_01: the torso leans over the planted foot
var _head := -1
var _shins: Array = [] ## [calf, foot] per leg
var _forearms: Array = [] ## [lower arm, hand] per arm
var _roll_axis := Vector3.ZERO

## Bend per unit of stoop, radians: the back rounds, the neck pushes the head forward and
## the head tips back up to look ahead (a little downcast).
const CHAIN := [["spine_01", 0.15], ["spine_02", 0.22], ["spine_03", 0.3], ["neck_01", 0.12], ["Head", -0.64]]
const KNEE := 0.2
const SHOULDER := 0.18
## Hip tilt (rad) and shift over the standing leg (m) at hip 1.
const HIP_TILT := 0.1
const HIP_SHIFT := 0.045

func _setup(sk: Skeleton3D) -> void:
	_ready_bones = true
	for e in CHAIN:
		var b := sk.find_bone(e[0])
		if b >= 0:
			_bones.append([b, _axis(sk, b, Vector3.RIGHT), float(e[1])])
	for s in ["l", "r"]:
		var c := sk.find_bone("clavicle_" + s)
		if c >= 0:
			# Shoulders rolled forward: the clavicle swings toward the chest.
			_bones.append([c, _axis(sk, c, Vector3.UP), SHOULDER * (-1.0 if s == "l" else 1.0)])
		var la := sk.find_bone("lowerarm_" + s)
		var hd := sk.find_bone("hand_" + s)
		if la >= 0 and hd >= 0:
			_forearms.append([la, hd])
		var ua := sk.find_bone("upperarm_" + s)
		if ua >= 0:
			_arms.append([ua, sk.get_bone_rest(ua).origin, _axis(sk, ua, Vector3.BACK), 1.0 if s == "l" else -1.0])
		var th := sk.find_bone("thigh_" + s)
		var ca := sk.find_bone("calf_" + s)
		var fo := sk.find_bone("foot_" + s)
		if th >= 0 and ca >= 0 and fo >= 0:
			_shins.append([ca, fo])
			var a := sk.get_bone_global_rest(th).origin.distance_to(sk.get_bone_global_rest(ca).origin)
			var l := sk.get_bone_global_rest(ca).origin.distance_to(sk.get_bone_global_rest(fo).origin)
			_legs.append([th, ca, _axis(sk, th, Vector3.RIGHT), _axis(sk, ca, Vector3.RIGHT), a + l])
	_pelvis = sk.find_bone("pelvis")
	_head = sk.find_bone("Head")
	_roll = sk.find_bone("spine_01")
	if _roll >= 0:
		_roll_axis = _axis(sk, _roll, Vector3.BACK)

## A child's short legs and forearms and small hands, on the animated pose. Each joint
## moves in toward its parent rather than scaling the bone, so the limbs keep their girth.
func _proportions(sk: Skeleton3D) -> void:
	if neck_len < 0.999 and _head >= 0:
		sk.set_bone_pose_position(_head, sk.get_bone_pose_position(_head) * neck_len)
	if arm_len < 0.999:
		for e in _forearms:
			sk.set_bone_pose_position(e[0], sk.get_bone_pose_position(e[0]) * arm_len)
			sk.set_bone_pose_position(e[1], sk.get_bone_pose_position(e[1]) * arm_len)
	if hand_scale < 0.999:
		for e in _forearms:
			sk.set_bone_pose_scale(e[1], Vector3.ONE * hand_scale)
	if leg_len > 0.999 or _pelvis < 0 or _shins.size() != 2:
		return
	var before := 0.0
	for e in _shins:
		before += sk.get_bone_global_pose(e[1]).origin.y
	for e in _shins:
		sk.set_bone_pose_position(e[0], sk.get_bone_pose_position(e[0]) * leg_len)
		sk.set_bone_pose_position(e[1], sk.get_bone_pose_position(e[1]) * leg_len)
	var after := 0.0
	for e in _shins:
		after += sk.get_bone_global_pose(e[1]).origin.y
	var pg := sk.get_bone_global_pose(_pelvis)
	pg.origin.y -= (after - before) * 0.5
	sk.set_bone_global_pose(_pelvis, pg)

## A character-space axis in bone `b`'s own rest frame.
static func _axis(sk: Skeleton3D, b: int, v: Vector3) -> Vector3:
	return (sk.get_bone_global_rest(b).basis.orthonormalized().inverse() * v).normalized()

func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ready_bones:
		_setup(sk)
	for a in _arms:
		# Narrower shoulders: the arm hangs from further in along the collarbone.
		if shoulder_in >= 0.001:
			var r: Vector3 = a[1]
			sk.set_bone_pose_position(a[0], r * maxf(1.0 - shoulder_in / maxf(r.length(), 0.01), 0.5))
		if arms_out > 0.001:
			sk.set_bone_pose_rotation(a[0], sk.get_bone_pose_rotation(a[0]) * Quaternion(a[2], arms_out * float(a[3])))
	if _head >= 0 and absf(head_scale - 1.0) > 0.001:
		# Everything on the head (hair, eyes, brows, a hat) is skinned or attached to it.
		# The head bone's axes are the body's (x across, y up, z forward).
		sk.set_bone_pose_scale(_head, Vector3(1.0 + 0.06 * head_round, 1.0 - 0.04 * head_round, 1.0 + 0.02 * head_round) * head_scale)
	_proportions(sk)
	_gait(sk)
	_stand(sk)
	if absf(stoop) < 0.01:
		return
	for e in _bones:
		var b: int = e[0]
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(e[1], float(e[2]) * stoop))
	if stoop <= 0.0 or _pelvis < 0 or _legs.size() != 2:
		return
	# Knees: the thigh forward, the shin back twice as far, so the foot stays under the
	# hip; the hips come down by what the bent leg no longer reaches.
	var k := KNEE * stoop
	var drop := 0.0
	for leg in _legs:
		sk.set_bone_pose_rotation(leg[0], sk.get_bone_pose_rotation(leg[0]) * Quaternion(leg[2], -k))
		sk.set_bone_pose_rotation(leg[1], sk.get_bone_pose_rotation(leg[1]) * Quaternion(leg[3], 2.0 * k))
		drop = maxf(drop, float(leg[4]) * leg_len * (1.0 - cos(k)))
	var pg := sk.get_bone_global_pose(_pelvis)
	pg.origin.y -= drop
	sk.set_bone_global_pose(_pelvis, pg)

## Sway and limp, in step with the stride: the torso leans over the planted foot (the left
## is down from phase 0 to 0.5); a limping body lurches and dips over its bad leg.
func _gait(sk: Skeleton3D) -> void:
	if animator == null or _roll < 0 or (waddle < 0.01 and absf(limp) < 0.01):
		return
	var st := animator.stride()
	if st.y < 0.02:
		return
	var w := sin(st.x * TAU) # + while the left foot bears the weight
	# Rotating about the body's back-to-front axis tips the torso toward -x (its right).
	var lean := waddle * 0.07 * w
	var dip := 0.0
	if absf(limp) >= 0.01:
		var on_bad := maxf(0.0, -w if limp > 0.0 else w)
		lean += 0.13 * absf(limp) * on_bad * (-1.0 if limp > 0.0 else 1.0)
		dip = 0.03 * absf(limp) * on_bad
	sk.set_bone_pose_rotation(_roll, sk.get_bone_pose_rotation(_roll) * Quaternion(_roll_axis, -lean * st.y))
	if dip > 0.0 and _pelvis >= 0:
		var pg := sk.get_bone_global_pose(_pelvis)
		pg.origin.y -= dip * st.y
		sk.set_bone_global_pose(_pelvis, pg)

## Standing at rest: the weight on one leg (contrapposto), faded out as they move off.
func _stand(sk: Skeleton3D) -> void:
	if absf(hip) < 0.01 or _pelvis < 0 or _roll < 0:
		return
	var still := 1.0
	if animator != null:
		still = 1.0 - clampf(animator.stride().y * 3.0, 0.0, 1.0)
	if still < 0.01:
		return
	# Rotating about the body's forward axis lifts the +x (left) hip.
	var ang := HIP_TILT * hip * still
	var pg := sk.get_bone_global_pose(_pelvis)
	pg.basis = Basis(Vector3.BACK, ang) * pg.basis
	pg.origin.x += HIP_SHIFT * hip * still
	sk.set_bone_global_pose(_pelvis, pg)
	sk.set_bone_pose_rotation(_roll, sk.get_bone_pose_rotation(_roll) * Quaternion(_roll_axis, -1.25 * ang))
