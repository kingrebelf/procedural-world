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

var _ready_bones := false
var _bones: Array = [] ## [bone, local axis (character x in the bone's frame), angle per stoop]
var _legs: Array = [] ## [thigh, calf, local axis thigh, local axis calf, leg length]
var _pelvis := -1
var _arms: Array = [] ## [upper arm, its rest position from the clavicle]

## Bend per unit of stoop, radians; the neck and head lift back so the eyes stay level.
const CHAIN := [["spine_01", 0.13], ["spine_02", 0.18], ["spine_03", 0.25], ["neck_01", -0.2], ["Head", -0.24]]
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
			_arms.append([ua, sk.get_bone_rest(ua).origin])
		var th := sk.find_bone("thigh_" + s)
		var ca := sk.find_bone("calf_" + s)
		var fo := sk.find_bone("foot_" + s)
		if th >= 0 and ca >= 0 and fo >= 0:
			var a := sk.get_bone_global_rest(th).origin.distance_to(sk.get_bone_global_rest(ca).origin)
			var l := sk.get_bone_global_rest(ca).origin.distance_to(sk.get_bone_global_rest(fo).origin)
			_legs.append([th, ca, _axis(sk, th, Vector3.RIGHT), _axis(sk, ca, Vector3.RIGHT), a + l])
	_pelvis = sk.find_bone("pelvis")

## A character-space axis in bone `b`'s own rest frame.
static func _axis(sk: Skeleton3D, b: int, v: Vector3) -> Vector3:
	return (sk.get_bone_global_rest(b).basis.orthonormalized().inverse() * v).normalized()

func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or (absf(stoop) < 0.01 and shoulder_in < 0.001):
		return
	if not _ready_bones:
		_setup(sk)
	# Narrower shoulders: the arm hangs from further in along the collarbone.
	if shoulder_in >= 0.001:
		for a in _arms:
			var r: Vector3 = a[1]
			sk.set_bone_pose_position(a[0], r * maxf(1.0 - shoulder_in / maxf(r.length(), 0.01), 0.5))
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
