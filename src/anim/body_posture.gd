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
## Where the stride is: HumanAnimator.stride() (phase, how much on the move).
var animator: HumanAnimator

var _ready_bones := false
var _bones: Array = [] ## [bone, local axis (character x in the bone's frame), angle per stoop]
var _legs: Array = [] ## [thigh, calf, local axis thigh, local axis calf, leg length]
var _pelvis := -1
var _arms: Array = [] ## [upper arm, its rest position from the clavicle, local forward axis, side +1 left]
var _roll := -1 ## spine_01: the torso leans over the planted foot
var _roll_axis := Vector3.ZERO

## Bend per unit of stoop, radians: the back rounds, the neck pushes the head forward and
## the head tips back up to look ahead (a little downcast).
const CHAIN := [["spine_01", 0.15], ["spine_02", 0.22], ["spine_03", 0.3], ["neck_01", 0.12], ["Head", -0.64]]
const KNEE := 0.2
const SHOULDER := 0.18

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
		var ua := sk.find_bone("upperarm_" + s)
		if ua >= 0:
			_arms.append([ua, sk.get_bone_rest(ua).origin, _axis(sk, ua, Vector3.BACK), 1.0 if s == "l" else -1.0])
		var th := sk.find_bone("thigh_" + s)
		var ca := sk.find_bone("calf_" + s)
		var fo := sk.find_bone("foot_" + s)
		if th >= 0 and ca >= 0 and fo >= 0:
			var a := sk.get_bone_global_rest(th).origin.distance_to(sk.get_bone_global_rest(ca).origin)
			var l := sk.get_bone_global_rest(ca).origin.distance_to(sk.get_bone_global_rest(fo).origin)
			_legs.append([th, ca, _axis(sk, th, Vector3.RIGHT), _axis(sk, ca, Vector3.RIGHT), a + l])
	_pelvis = sk.find_bone("pelvis")
	_roll = sk.find_bone("spine_01")
	if _roll >= 0:
		_roll_axis = _axis(sk, _roll, Vector3.BACK)

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
	_gait(sk)
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
		drop = maxf(drop, float(leg[4]) * (1.0 - cos(k)))
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
