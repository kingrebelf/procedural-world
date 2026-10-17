class_name Ragdoll
extends Node
## A body going limp: rigid bodies and cone-twist joints (Jolt) built over a person's or an animal's skeleton,
## starting from the pose they were in when they died, moving as they were moving, and
## knocked by what killed them (the shot's direction and weight, at the point it struck).
## When it has come to rest, the pose it settled in is captured (every bone's local
## transform) so the corpse can be saved and drawn exactly that way again (Corpses).
##
## Only a few bodies simulate at once (MAX_ACTIVE): when another dies, the oldest still
## falling settles where it is.

signal settled(pose: PackedFloat32Array)

const MAX_ACTIVE := 4
const LAYER := 16 ## its own physics layer; it lands on the ground (1) and on things (2)
const MAX_TIME := 7.0

## People: [bone, end bone ("" = along the bone for `len`), radius, mass (kg), len,
## swing limit, twist limit (degrees)]. Bones not listed follow their parent rigidly.
const HUMAN := [
	["pelvis", "spine_02", 0.13, 11.0, 0.0, 30.0, 15.0],
	["spine_02", "neck_01", 0.14, 15.0, 0.0, 35.0, 25.0],
	["Head", "", 0.11, 5.0, 0.24, 45.0, 50.0],
	["upperarm_l", "lowerarm_l", 0.055, 2.5, 0.0, 80.0, 40.0],
	["upperarm_r", "lowerarm_r", 0.055, 2.5, 0.0, 80.0, 40.0],
	["lowerarm_l", "hand_l", 0.045, 1.6, 0.0, 70.0, 20.0],
	["lowerarm_r", "hand_r", 0.045, 1.6, 0.0, 70.0, 20.0],
	["thigh_l", "calf_l", 0.08, 8.0, 0.0, 60.0, 20.0],
	["thigh_r", "calf_r", 0.08, 8.0, 0.0, 60.0, 20.0],
	["calf_l", "foot_l", 0.06, 4.0, 0.0, 65.0, 8.0],
	["calf_r", "foot_r", 0.06, 4.0, 0.0, 65.0, 8.0],
	["foot_l", "ball_leaf_l", 0.045, 1.0, 0.0, 30.0, 10.0],
	["foot_r", "ball_leaf_r", 0.045, 1.0, 0.0, 30.0, 10.0],
]

static var _active: Array = []

var skeleton: Skeleton3D
var _world: Node3D
var _writer: RagdollWriter
var _bones: Array = [] ## RigidBody3D per simulated bone
var _bone_ids: Array = []
var _spec: Array = []
var _joints: Array = []
var _live := false
var _follow := {} ## free root bone -> [body index, offset from that body's bone]
var _t := 0.0
var _still := 0.0
var _done := false

## Hit data the next ragdoll of `target` uses: where it was struck, which way, how hard
## (newton-seconds), and the bone if the weapon knows it (a headshot: "Head").
static func mark_hit(target: Object, point: Vector3, dir: Vector3, force: float, bone := "") -> void:
	if target == null or not is_instance_valid(target):
		return
	target.set_meta("last_hit", {"point": point, "dir": dir.normalized(), "force": force, "bone": bone, "ms": Time.get_ticks_msec()})

static func hit_of(target: Object) -> Dictionary:
	if target == null or not is_instance_valid(target) or not target.has_meta("last_hit"):
		return {}
	var h: Dictionary = target.get_meta("last_hit")
	# Only a hit that just happened knocks the body.
	return h if Time.get_ticks_msec() - int(h["ms"]) < 1500 else {}

## Ragdoll spec for an animal's skeleton (Quaternius animal rigs), sized to it.
static func animal_spec(sk: Skeleton3D) -> Array:
	var head := sk.find_bone("Head")
	var h := sk.get_bone_global_rest(head).origin.y if head >= 0 else 2.0
	var body_r := h * 0.11
	var out := []
	var add := func(bone: String, end: String, r: float, m: float, len: float, swing: float, twist: float) -> void:
		if sk.find_bone(bone) >= 0 and (end == "" or sk.find_bone(end) >= 0):
			out.append([bone, end, r, m, len, swing, twist])
	add.call("Back", "Torso3", body_r, 30.0, 0.0, 20.0, 10.0)
	add.call("Torso3", "Neck1", body_r * 0.9, 20.0, 0.0, 25.0, 12.0)
	add.call("Neck2", "Head", body_r * 0.4, 4.0, 0.0, 40.0, 20.0)
	add.call("Head", "", body_r * 0.45, 4.0, h * 0.14, 35.0, 20.0)
	for s in ["L", "R"]:
		for leg in [["FrontUpperLeg.", "FrontLowerLeg."], ["BackUpperLeg.", "BackLowerLeg."]]:
			var up: String = leg[0] + s
			var lo: String = leg[1] + s
			add.call(up, lo, body_r * 0.35, 4.0, 0.0, 55.0, 10.0)
			var lb := sk.find_bone(lo)
			if lb >= 0:
				add.call(lo, "", body_r * 0.22, 2.0, sk.get_bone_global_rest(lb).origin.y * 0.95, 60.0, 8.0)
	add.call("Tail1", "Tail2", body_r * 0.2, 0.5, 0.0, 40.0, 10.0)
	return out

## Builds the bodies over `sk` from `spec` (HUMAN or animal_spec()): a rigid capsule per
## listed bone, in world space (so scaled models simulate at their real size), joined to
## its nearest listed ancestor by a cone-twist joint at the bone's head.
func build(sk: Skeleton3D, spec: Array) -> Ragdoll:
	skeleton = sk
	_world = Node3D.new()
	_world.name = "RagdollBodies"
	_world.top_level = true
	add_child(_world)
	_world.global_transform = Transform3D.IDENTITY
	var gx := sk.global_transform
	var k := gx.basis.get_scale().y
	var rot := gx.basis.orthonormalized()
	for e in spec:
		var b := sk.find_bone(e[0])
		if b < 0:
			continue
		var rest := sk.get_bone_global_rest(b)
		var dir: Vector3
		if String(e[1]) != "":
			dir = rest.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(e[1])).origin
		else:
			dir = Vector3(0, float(e[4]), 0) # a leaf bone runs along its +Y
		var body := RigidBody3D.new()
		body.name = "RB_" + String(e[0])
		body.mass = float(e[3]) # real kilograms, whatever size the model is drawn at
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.0
		body.physics_material_override = pm
		body.linear_damp = 0.15
		body.angular_damp = 1.5
		body.collision_layer = LAYER
		body.collision_mask = 1 | 2
		body.continuous_cd = true
		body.can_sleep = true
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var r: float = float(e[2]) * k
		var len := dir.length() * k
		cap.radius = r
		cap.height = maxf(len + r * 2.0, r * 2.0 + 0.01)
		cs.shape = cap
		var y := dir.normalized() if dir.length() > 0.0001 else Vector3.UP
		cs.transform = Transform3D(Basis(AnimMath.arc(Vector3.UP, y)), y * len * 0.5)
		body.add_child(cs)
		_world.add_child(body)
		body.global_transform = _world_of(gx, rot, sk.get_bone_global_pose(b))
		_bones.append(body)
		_bone_ids.append(b)
		_spec.append(e)
	# Joints, child to nearest listed ancestor, and no collisions between joined pieces.
	for i in _bones.size():
		var p := _sim_parent(_bone_ids[i])
		if p < 0:
			continue
		var pi := _bone_ids.find(p)
		var a: RigidBody3D = _bones[pi]
		var c: RigidBody3D = _bones[i]
		c.add_collision_exception_with(a)
		var j := ConeTwistJoint3D.new()
		# The twist axis (the joint's X) runs along the child bone.
		var along := (c.global_basis * Vector3.UP).normalized()
		var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		_world.add_child(j)
		j.global_transform = Transform3D(Basis(along, side, along.cross(side)).orthonormalized(), c.global_position)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(float(_spec[i][5])))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(float(_spec[i][6])))
		j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
		j.node_a = j.get_path_to(a)
		j.node_b = j.get_path_to(c)
		_joints.append(j)
	for i in _bones.size():
		(_bones[i] as RigidBody3D).freeze = true
	_writer = RagdollWriter.new()
	_writer.rag = self
	_writer.active = false
	sk.add_child(_writer)
	return self

## A bone's skeleton-space pose as a world transform without the model's scale.
static func _world_of(gx: Transform3D, rot: Basis, pose: Transform3D) -> Transform3D:
	return Transform3D(rot * pose.basis.orthonormalized(), gx * pose.origin)

## The skeleton-space pose for a body's world transform (the inverse of _world_of).
func pose_of(i: int) -> Transform3D:
	var gx := skeleton.global_transform
	var body := _bones[i] as Node3D
	var basis := gx.basis.orthonormalized().inverse() * body.global_basis.orthonormalized()
	return Transform3D(basis, gx.affine_inverse() * body.global_position)

func _sim_parent(b: int) -> int:
	var p := skeleton.get_bone_parent(b)
	while p >= 0:
		if _bone_ids.has(p):
			return p
		p = skeleton.get_bone_parent(p)
	return -1

## Goes limp, moving at `velocity` (m/s, what the body was doing), knocked by `hit`
## (Ragdoll.hit_of): an impulse at the point struck, on the bone nearest it.
func start(velocity: Vector3, hit: Dictionary) -> void:
	if _bones.is_empty():
		return
	var gx := skeleton.global_transform
	var rot := gx.basis.orthonormalized()
	for i in _bones.size():
		var body := _bones[i] as RigidBody3D
		body.global_transform = _world_of(gx, rot, skeleton.get_bone_global_pose(_bone_ids[i]))
		body.freeze = false
		body.linear_velocity = velocity
	_follow_free_roots()
	_writer.active = true
	_live = true
	if not hit.is_empty():
		var at: Vector3 = hit["point"]
		var best: RigidBody3D = null
		var bd := INF
		for i in _bones.size():
			var body := _bones[i] as RigidBody3D
			var d := body.global_position.distance_to(at)
			if String(hit.get("bone", "")) != "" and skeleton.get_bone_name(_bone_ids[i]) == hit["bone"]:
				d = -1.0
			if d < bd:
				bd = d
				best = body
		if best:
			var j: Vector3 = (hit["dir"] as Vector3) * float(hit["force"])
			# The part struck takes the brunt, at the point struck (so it twists the body);
			# the rest of the blow carries the whole body, as the joints would.
			best.apply_impulse(j * 0.4, at - best.global_position)
			var total := 0.0
			for body in _bones:
				total += (body as RigidBody3D).mass
			for body in _bones:
				(body as RigidBody3D).apply_central_impulse(j * 0.6 * (body as RigidBody3D).mass / total)
	_active.append(self)
	while _active.size() > MAX_ACTIVE:
		var old: Ragdoll = _active.pop_front()
		if is_instance_valid(old) and old != self:
			old.settle()

func _physics_process(delta: float) -> void:
	if not _live or _done:
		return
	_t += delta
	var moving := false
	for body in _bones:
		var p := body as RigidBody3D
		if p.linear_velocity.length() > 0.1 or p.angular_velocity.length() > 0.5:
			moving = true
			break
	_still = 0.0 if moving else _still + delta
	if (_still > 0.5 and _t > 1.0) or _t > MAX_TIME:
		settle()

## Stops simulating and keeps the pose it is in; emits settled(pose) with that pose.
func settle() -> void:
	if _done or _bones.is_empty():
		return
	_done = true
	_live = false
	_active.erase(self)
	var pose := capture()
	apply_pose(skeleton, pose)
	if is_instance_valid(_writer):
		_writer.queue_free()
	if is_instance_valid(_world):
		_world.queue_free()
	settled.emit(pose)

## Every bone's local transform as the simulation has it: 7 floats a bone (position,
## rotation quaternion), in bone order.
func capture() -> PackedFloat32Array:
	var sk := skeleton
	var n := sk.get_bone_count()
	var by_bone := {}
	for i in _bones.size():
		by_bone[_bone_ids[i]] = i
	var g: Array = []
	g.resize(n)
	var out := PackedFloat32Array()
	out.resize(n * 7)
	for b in n:
		var parent := sk.get_bone_parent(b)
		var local: Transform3D
		if by_bone.has(b) or _follow.has(b):
			var gb := pose_of(by_bone[b]) if by_bone.has(b) else pose_of(_follow[b][0]) * (_follow[b][1] as Transform3D)
			g[b] = gb
			local = (g[parent] as Transform3D).affine_inverse() * gb if parent >= 0 else gb
			local.basis = local.basis.orthonormalized()
			# Joints keep bones where they belong: only the body's root (the pelvis) moves.
			if by_bone.has(b) and _sim_parent(b) >= 0:
				local.origin = sk.get_bone_pose_position(b)
		else:
			local = sk.get_bone_pose(b)
		g[b] = (g[parent] as Transform3D) * local if parent >= 0 else local
		var q := local.basis.get_rotation_quaternion()
		out[b * 7] = local.origin.x
		out[b * 7 + 1] = local.origin.y
		out[b * 7 + 2] = local.origin.z
		out[b * 7 + 3] = q.x
		out[b * 7 + 4] = q.y
		out[b * 7 + 5] = q.z
		out[b * 7 + 6] = q.w
	return out

## Each frame while falling: the bones follow their bodies.
func write_pose() -> void:
	for i in _bones.size():
		skeleton.set_bone_global_pose(_bone_ids[i], pose_of(i))
	for b in _follow:
		skeleton.set_bone_global_pose(b, pose_of(_follow[b][0]) * (_follow[b][1] as Transform3D))

## Rigs that steer their legs with free-standing IK bones (the animal kit's hoof targets)
## skin the hooves to those: each such bone rides along with the nearest body, or the
## hooves would stay standing while the legs fell.
func _follow_free_roots() -> void:
	_follow.clear()
	var sk := skeleton
	var has_sim_below := {}
	for b in _bone_ids:
		var p: int = b
		while p >= 0:
			has_sim_below[p] = true
			p = sk.get_bone_parent(p)
	for b in sk.get_bone_count():
		if sk.get_bone_parent(b) >= 0 or has_sim_below.has(b):
			continue
		var g := sk.get_bone_global_pose(b)
		var best := -1
		var bd := INF
		for i in _bone_ids.size():
			var d := sk.get_bone_global_pose(_bone_ids[i]).origin.distance_to(g.origin)
			# A hoof target sits at the end of its leg, not at the leg's head.
			var tip := sk.get_bone_global_pose(_bone_ids[i]) * (Vector3(0, float(_spec[i][4]), 0) if String(_spec[i][1]) == "" else Vector3.ZERO)
			d = minf(d, tip.distance_to(g.origin))
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			_follow[b] = [best, sk.get_bone_global_pose(_bone_ids[best]).affine_inverse() * g]

## The pose a skeleton is in right now, in the same form as capture(): what a body was
## doing the moment it died, for its ragdoll to start from.
static func snapshot(sk: Skeleton3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(sk.get_bone_count() * 7)
	for b in sk.get_bone_count():
		var o := sk.get_bone_pose_position(b)
		var q := sk.get_bone_pose_rotation(b)
		out[b * 7] = o.x
		out[b * 7 + 1] = o.y
		out[b * 7 + 2] = o.z
		out[b * 7 + 3] = q.x
		out[b * 7 + 4] = q.y
		out[b * 7 + 5] = q.z
		out[b * 7 + 6] = q.w
	return out

## Puts a captured pose back on a skeleton (a saved corpse, drawn again).
static func apply_pose(sk: Skeleton3D, pose: PackedFloat32Array) -> bool:
	if pose.size() != sk.get_bone_count() * 7:
		return false
	for b in sk.get_bone_count():
		sk.set_bone_pose_position(b, Vector3(pose[b * 7], pose[b * 7 + 1], pose[b * 7 + 2]))
		sk.set_bone_pose_rotation(b, Quaternion(pose[b * 7 + 3], pose[b * 7 + 4], pose[b * 7 + 5], pose[b * 7 + 6]).normalized())
	return true

## Where the body's middle is (first physical bone), in world space.
func center() -> Vector3:
	return (_bones[0] as Node3D).global_position if not _bones.is_empty() and is_instance_valid(_bones[0]) else Vector3.INF

func is_live() -> bool:
	return _live

func _exit_tree() -> void:
	_active.erase(self)
