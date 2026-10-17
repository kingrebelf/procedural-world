class_name HandGrip
## A right hand closing round a handle the way a real one does. The handle lies across
## the palm on a diagonal (in at the base of the index finger, out at the heel of the
## hand), touching the palm. Each finger then closes joint by joint, knuckle first, until
## that bone meets the handle, so the fingers wrap a thick handle loosely and a thin one
## tightly instead of always clenching into the same fist. The thumb comes round the
## other way and rests on the index and middle fingers. Worked out once per skeleton and
## handle size from the rest pose; the result is each finger bone's local rotation.

## Hand space here is the hand bone's own rest frame (worked out per skeleton, not assumed).
const FINGERS := ["index", "middle", "ring", "pinky"]
## Skin round a finger bone, and from the knuckle-line plane to the skin of the palm.
const FINGER_R := 0.0095
const PALM := 0.024
## How far the handle sits back from the knuckles toward the wrist, at the middle finger.
const BACK := 0.012
## The handle's angle across the palm from the knuckle line (index end toward the fingers).
const DIAGONAL := 0.32
## Joint limits (radians): knuckle, middle joint, end joint.
const LIMIT := [1.45, 1.65, 1.2]
const STEP := 0.025

static var _cache := {}

## The hand's frame in its own rest space: "fingers" (along them), "knuckles" (pinky to
## index), "palm" (out of the palm), and the knuckle joints' middle "mcp".
static func frame(sk: Skeleton3D) -> Dictionary:
	var hb := sk.find_bone("hand_r")
	var inv := sk.get_bone_global_rest(hb).affine_inverse()
	var i := inv * sk.get_bone_global_rest(sk.find_bone("index_01_r")).origin
	var p := inv * sk.get_bone_global_rest(sk.find_bone("pinky_01_r")).origin
	var m := inv * sk.get_bone_global_rest(sk.find_bone("middle_01_r")).origin
	var k := (i - p).normalized()
	var f := (m - k * m.dot(k)).normalized()
	# The palm faces the way the thumb sits from the knuckle line.
	var t := inv * sk.get_bone_global_rest(sk.find_bone("thumb_01_r")).origin
	var n := k.cross(f).normalized()
	if (t - m).dot(n) < 0.0:
		n = -n
	return {"fingers": f, "knuckles": k, "palm": n, "mcp": m, "index": i, "pinky": p}

## Where a handle of `radius` lies in the hand (hand space): "axis" (unit, index end) and
## "center" (on the axis, under the middle finger).
static func handle_line(sk: Skeleton3D, radius: float) -> Dictionary:
	var fr := frame(sk)
	var f: Vector3 = fr["fingers"]
	var k: Vector3 = fr["knuckles"]
	var n: Vector3 = fr["palm"]
	var axis := (k * cos(DIAGONAL) + f * sin(DIAGONAL)).normalized()
	var c: Vector3 = fr["mcp"] - f * BACK + n * (PALM + radius)
	return {"axis": axis, "center": c}

## The finger rotations that wrap a handle lying along `axis` through `center` (hand
## space), of `radius`: bone index -> local rotation. `pose` "trigger": the hand closes
## as round a pistol grip with the index finger crooked round the trigger; "fist": the
## same with the index closed too (a flashlight); "" wraps the handle.
static func solve(sk: Skeleton3D, radius: float, axis: Vector3, center: Vector3, pose := "") -> Dictionary:
	var key := "%d|%.3f|%s|%s|%s" % [sk.get_bone_count(), radius, axis.snappedf(0.01), center.snappedf(0.002), pose]
	key += str(sk.get_bone_global_rest(sk.find_bone("hand_r")).origin.snappedf(0.001))
	if _cache.has(key):
		return _cache[key]
	var out := {}
	var fr := frame(sk)
	var hb := sk.find_bone("hand_r")
	var inv := sk.get_bone_global_rest(hb).affine_inverse()
	var palm: Vector3 = fr["palm"]
	var reach := radius + FINGER_R
	for f in FINGERS:
		var chain := _chain(sk, f)
		if chain.is_empty():
			continue
		var axes := _flex_axes(sk, chain, inv, palm)
		var ang := [0.0, 0.0, 0.0]
		if pose != "":
			# A gun's grip is no round handle and is turned to the view each frame: the
			# fingers close as round a pistol grip, the trigger finger crooked.
			ang = [0.45, 0.85, 0.4] if f == "index" and pose == "trigger" else [1.2, 1.45, 0.8]
		else:
			# Real fingers bend all three joints together; close until a bone meets the
			# handle, then let the last joint finish wrapping.
			var c := 0.0
			while c < 1.0:
				var next := c + STEP * 0.5
				var trial := [LIMIT[0] * next, LIMIT[1] * next, LIMIT[2] * next * 0.8]
				var segs := _fk(sk, chain, inv, axes, trial)
				if _touches(segs, center, axis, reach):
					break
				c = next
			ang = [LIMIT[0] * c, LIMIT[1] * c, LIMIT[2] * c * 0.8]
			while ang[2] < LIMIT[2]:
				var trial := [ang[0], ang[1], ang[2] + STEP]
				var segs := _fk(sk, chain, inv, axes, trial)
				if _seg_line(segs[2], segs[3], center, axis) < reach:
					break
				ang[2] += STEP
		for j in 3:
			out[chain[j]] = _local(sk, chain[j], axes[j], ang[j])
	_thumb(sk, inv, fr, radius, axis, center, out)
	_cache[key] = out
	return out

## The finger's three bones and its tip ("..._04_leaf_r", or the last bone run on).
static func _chain(sk: Skeleton3D, f: String) -> Array:
	var c := []
	for j in 3:
		var b := sk.find_bone("%s_%02d_r" % [f, j + 1])
		if b < 0:
			return []
		c.append(b)
	c.append(sk.find_bone("%s_04_leaf_r" % f))
	return c

## Each joint's bend axis in its bone's own space: bending the bone toward the palm.
static func _flex_axes(sk: Skeleton3D, chain: Array, inv: Transform3D, palm: Vector3) -> Array:
	var axes := []
	for j in 3:
		var g := sk.get_bone_global_rest(chain[j])
		var d := (inv.basis * g.basis.y).normalized()
		var ax := d.cross(palm).normalized()
		var hand_from_bone := (inv.basis * g.basis).orthonormalized()
		axes.append((hand_from_bone.inverse() * ax).normalized())
	return axes

static func _local(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> Quaternion:
	return sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(axis, angle)

## Joint positions (hand space) of a finger bent by `ang`: the three joints and the tip.
static func _fk(sk: Skeleton3D, chain: Array, inv: Transform3D, axes: Array, ang: Array) -> Array:
	var t := inv * sk.get_bone_global_rest(sk.get_bone_parent(chain[0]))
	var pts := []
	for j in 3:
		var r := sk.get_bone_rest(chain[j])
		t = t * Transform3D(Basis(_local(sk, chain[j], axes[j], ang[j])), r.origin)
		pts.append(t.origin)
	if chain[3] >= 0:
		pts.append(t * sk.get_bone_rest(chain[3]).origin)
	else:
		pts.append(t * (sk.get_bone_rest(chain[2]).origin))
	return pts

static func _touches(segs: Array, c: Vector3, u: Vector3, reach: float) -> bool:
	for j in 3:
		if _seg_line(segs[j], segs[j + 1], c, u) < reach:
			return true
	return false

## Closest distance between the segment a-b and the infinite line through c along u.
static func _seg_line(a: Vector3, b: Vector3, c: Vector3, u: Vector3) -> float:
	var best := INF
	for s in 9:
		var p := a.lerp(b, s / 8.0) - c
		best = minf(best, (p - u * p.dot(u)).length())
	return best

## The thumb wraps round the handle from the palm side and lies across the index and
## middle fingers' middle bones: a few rounds of bending its joints toward that spot
## (no twisting about the bone), each joint within a human range.
static func _thumb(sk: Skeleton3D, inv: Transform3D, fr: Dictionary, radius: float, axis: Vector3, center: Vector3, out: Dictionary) -> void:
	var chain := _chain(sk, "thumb")
	var mid := _chain(sk, "index")
	if chain.is_empty() or mid.is_empty():
		return
	# Where the index finger's middle bone ended up, pushed out off the fingers' backs.
	var it := inv * sk.get_bone_global_rest(sk.get_bone_parent(mid[0]))
	for j in 3:
		it = it * Transform3D(Basis(out[mid[j]]), sk.get_bone_rest(mid[j]).origin)
		if j == 1:
			break
	var p := it * (sk.get_bone_rest(mid[2]).origin * 0.6)
	var rel := p - center
	var radial := (rel - axis * rel.dot(axis)).normalized()
	var target := p + radial * FINGER_R * 1.7 - axis * 0.004
	var rot := []
	for j in 3:
		rot.append(sk.get_bone_rest(chain[j]).basis.get_rotation_quaternion())
	var limit := [0.9, 0.9, 1.3]
	var start := rot.duplicate()
	for it_n in 24:
		for j in [2, 1, 0]:
			var xf := _thumb_fk(sk, chain, inv, rot)
			var joint: Transform3D = xf[j]
			var tip: Vector3 = xf[3].origin
			var to_tip := (tip - joint.origin)
			var to_goal := (target - joint.origin)
			# Never let the bones pass into the handle: aim outside it on the way round.
			if to_tip.length() < 1e-4 or to_goal.length() < 1e-4:
				continue
			var ax := to_tip.cross(to_goal)
			if ax.length() < 1e-6:
				continue
			var ang := to_tip.angle_to(to_goal) * 0.5
			var local_ax := (joint.basis.orthonormalized().inverse() * ax.normalized()).normalized()
			var q: Quaternion = (rot[j] as Quaternion) * Quaternion(local_ax, ang)
			# Keep the joint within its range from where it started.
			var d: Quaternion = (start[j] as Quaternion).inverse() * q
			if d.get_angle() > limit[j]:
				q = (start[j] as Quaternion) * Quaternion(d.get_axis(), limit[j])
			rot[j] = q
	for j in 3:
		out[chain[j]] = rot[j]

static func _thumb_fk(sk: Skeleton3D, chain: Array, inv: Transform3D, rot: Array) -> Array:
	var t := inv * sk.get_bone_global_rest(sk.get_bone_parent(chain[0]))
	var xs := []
	for j in 3:
		t = t * Transform3D(Basis(rot[j] as Quaternion), sk.get_bone_rest(chain[j]).origin)
		xs.append(t)
	var tip := t * (sk.get_bone_rest(chain[3]).origin if chain[3] >= 0 else Vector3(0, 0.03, 0))
	xs.append(Transform3D(t.basis, tip))
	return xs

## A handle's radius where the hand closes on it: the spread of the prop's vertices round
## the middle of its cross-section near `grip` (prop space), clamped to what a hand holds.
static func handle_radius(prop: Node3D, grip: Vector3) -> float:
	return float(_section(prop, grip)[1])

## Where the handle's cross-section is centred at the grip's height (prop space): a bent
## handle (an axe's) is off its model's axis there.
static func handle_center(prop: Node3D, grip: Vector3) -> Vector3:
	var c: Vector2 = _section(prop, grip)[0]
	return Vector3(grip.x + c.x, grip.y, grip.z + c.y)

static func _section(prop: Node3D, grip: Vector3) -> Array:
	if prop.has_meta("grip_section"):
		return prop.get_meta("grip_section")
	var got := _measure(prop, grip)
	prop.set_meta("grip_section", got)
	return got

static func _measure(prop: Node3D, grip: Vector3) -> Array:
	var pts := PackedVector2Array()
	for mi in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null or mesh is PrimitiveMesh:
			continue
		if mesh.has_meta("grip_r"):
			return [Vector2.ZERO, float(mesh.get_meta("grip_r"))]
		var xf := HumanModel._rel(prop, mi)
		for s in mesh.get_surface_count():
			var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p0 in v:
				var p := xf * p0 - grip
				if absf(p.y) < 0.025:
					pts.append(Vector2(p.x, p.z))
	if pts.size() < 3:
		return [Vector2.ZERO, 0.016]
	# The middle of the outline's extent, and its half-width averaged over both ways.
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	var r := ((hi.x - lo.x) + (hi.y - lo.y)) * 0.25
	return [c, clampf(r, 0.009, 0.03)]
