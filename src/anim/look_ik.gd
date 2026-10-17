class_name LookIK
extends SkeletonModifier3D
## Turns a chain of neck and head bones toward a world point after the animation: an
## animal lifting its head to watch you, a wolf keeping its eyes on you as it circles.
## Each bone takes a share of the turn; it eases in and out and gives up when the point
## is behind. The skeleton faces +Z.

## [[bone index, share of the yaw, share of the pitch], ...] from the body to the head.
var chain: Array = []
var target := Vector3.INF
var weight := 0.0
var max_yaw := 1.3
var max_pitch := 0.7

var _yaw := 0.0
var _pitch := 0.0
var _w := 0.0

## The neck and head of a skeleton: bones named Neck... then Head, the head taking most.
static func chain_for(sk: Skeleton3D) -> Array:
	var names := []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.begins_with("Neck") or n == "Head":
			names.append(i)
	if names.is_empty():
		return []
	var out := []
	var shares := 0.0
	for j in names.size():
		shares += float(j + 1)
	for j in names.size():
		var s := float(j + 1) / shares
		out.append([names[j], s, s])
	return out

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or chain.is_empty() or not sk.is_inside_tree():
		return
	var dt := clampf(delta, 0.0, 0.1)
	var gx := sk.global_transform
	var up := (gx.basis.inverse() * Vector3.UP).normalized()
	var want := 0.0
	var yaw := 0.0
	var pitch := 0.0
	if target != Vector3.INF and weight > 0.0:
		var head := sk.get_bone_global_pose(chain[-1][0]).origin
		var to := gx.affine_inverse() * target - head
		var flat := to - up * to.dot(up)
		yaw = atan2(flat.x, flat.z)
		pitch = atan2(to.dot(up), flat.length())
		want = weight if absf(yaw) < max_yaw + 0.6 else 0.0
		yaw = clampf(yaw, -max_yaw, max_yaw)
		pitch = clampf(pitch, -max_pitch, max_pitch)
	_w = lerpf(_w, want, clampf(dt * 3.0, 0.0, 1.0))
	if want > 0.0:
		var k := clampf(dt * 4.0, 0.0, 1.0)
		_yaw = lerpf(_yaw, yaw, k)
		_pitch = lerpf(_pitch, pitch, k)
	if _w < 0.002:
		return
	var right := up.cross(Vector3(0, 0, 1)).normalized()
	var turned := 0.0
	for e in chain:
		turned += _yaw * float(e[1]) * _w
		var axis := (Quaternion(up, turned) * right).normalized()
		var q := Quaternion(up, _yaw * float(e[1]) * _w) * Quaternion(axis, -_pitch * float(e[2]) * _w)
		var g := sk.get_bone_global_pose(e[0])
		g.basis = Basis(q) * g.basis
		sk.set_bone_global_pose(e[0], g)
