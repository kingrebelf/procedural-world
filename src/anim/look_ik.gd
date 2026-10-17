class_name LookIK
extends SkeletonModifier3D
## Turns a chain of neck and head bones toward a world point after the animation: an
## animal lifting its head to watch you, a wolf keeping its eyes on you as it circles.
## Each bone takes a share of the turn; it eases in and out and gives up when the point
## is behind. The head leads and the neck's root follows a beat later, each easing in and
## settling like a muscle (AnimMath.spring), and the ears (which hang off the neck in the
## kit's rigs) turn with the head instead of being left behind. The skeleton faces +Z.

## [[bone index, share of the yaw, share of the pitch], ...] from the body to the head.
var chain: Array = []
var target := Vector3.INF
var weight := 0.0
var max_yaw := 1.3
var max_pitch := 0.7

## Bones carried round with the head though not its children: the ears.
var riders: Array = []

## [value, velocity] springs: the head end of the chain, its root end, the weight.
var _hy := Vector2.ZERO
var _hp := Vector2.ZERO
var _ry := Vector2.ZERO
var _rp := Vector2.ZERO
var _w := Vector2.ZERO

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

## Ear roots: bones named Ear... hanging off the head's parent rather than the head.
static func riders_for(sk: Skeleton3D, chain: Array) -> Array:
	if chain.is_empty():
		return []
	var head: int = chain[-1][0]
	var up := sk.get_bone_parent(head)
	var out := []
	for i in sk.get_bone_count():
		if i != head and sk.get_bone_parent(i) == up and sk.get_bone_name(i).begins_with("Ear"):
			out.append(i)
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
	_w = AnimMath.spring(_w.x, _w.y, want, 4.0, dt)
	_w.x = clampf(_w.x, 0.0, 1.0)
	if want > 0.0:
		_hy = AnimMath.spring(_hy.x, _hy.y, yaw, 8.0, dt)
		_hp = AnimMath.spring(_hp.x, _hp.y, pitch, 8.0, dt)
		_ry = AnimMath.spring(_ry.x, _ry.y, yaw, 3.5, dt)
		_rp = AnimMath.spring(_rp.x, _rp.y, pitch, 3.5, dt)
	if _w.x < 0.002:
		return
	var w := _w.x
	var right := up.cross(Vector3(0, 0, 1)).normalized()
	var turned := 0.0
	var n := chain.size()
	var q := Quaternion.IDENTITY
	for j in n:
		var e: Array = chain[j]
		# The last two bones (upper neck and head) lead; the rest follow.
		var lead := j >= n - 2
		var y: float = (_hy.x if lead else _ry.x) * float(e[1]) * w
		var p: float = (_hp.x if lead else _rp.x) * float(e[2]) * w
		turned += y
		var axis := (Quaternion(up, turned) * right).normalized()
		q = Quaternion(up, y) * Quaternion(axis, -p)
		var g := sk.get_bone_global_pose(e[0])
		g.basis = Basis(q) * g.basis
		sk.set_bone_global_pose(e[0], g)
	if riders.is_empty():
		return
	# The head's own turn, about the head, for the ears that hang off its parent.
	var at := sk.get_bone_global_pose(chain[-1][0]).origin
	for r in riders:
		var g := sk.get_bone_global_pose(r)
		g.basis = Basis(q) * g.basis
		g.origin = at + q * (g.origin - at)
		sk.set_bone_global_pose(r, g)
