class_name AnimMath
extends RefCounted
## Reading poses straight out of Animation resources, without a scene playing them: used
## to measure clips (how fast a walk travels, when a foot lands) when they are baked or
## first loaded, and the two-bone leg solve the IK modifiers share.

## bone name -> [position track, rotation track, scale track] (-1 where there is none).
static func track_map(a: Animation) -> Dictionary:
	var out := {}
	for i in a.get_track_count():
		var p := String(a.track_get_path(i))
		var c := p.rfind(":")
		if c < 0:
			continue
		var bone := p.substr(c + 1)
		if not out.has(bone):
			out[bone] = [-1, -1, -1]
		match a.track_get_type(i):
			Animation.TYPE_POSITION_3D: out[bone][0] = i
			Animation.TYPE_ROTATION_3D: out[bone][1] = i
			Animation.TYPE_SCALE_3D: out[bone][2] = i
	return out

## Bone `bone`'s pose in skeleton space at time `t` of `a` (forward kinematics from the
## skeleton's rest pose and the clip's tracks). `skip_root_motion` keeps the root bone at
## rest, the way the game plays clips in place.
static func global_at(a: Animation, tracks: Dictionary, sk: Skeleton3D, bone: int, t: float, skip_root_motion := false) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		var name := sk.get_bone_name(b)
		var rest := sk.get_bone_rest(b)
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var scl := rest.basis.get_scale()
		var tr: Array = tracks.get(name, [-1, -1, -1])
		if tr[0] >= 0 and not (skip_root_motion and sk.get_bone_parent(b) < 0):
			pos = a.position_track_interpolate(tr[0], t)
		if tr[1] >= 0:
			rot = a.rotation_track_interpolate(tr[1], t)
		if tr[2] >= 0:
			scl = a.scale_track_interpolate(tr[2], t)
		xf = Transform3D(Basis(rot).scaled(scl), pos) * xf
		b = sk.get_bone_parent(b)
	return xf

## Where in a walk-like cycle (0..1) the foot `foot` is furthest forward, about to land:
## clips that share this point can be blended stride for stride. `fwd` is the skeleton's
## forward axis.
static func foot_forward_phase(a: Animation, sk: Skeleton3D, foot: int, fwd := Vector3.FORWARD * -1.0, samples := 48) -> float:
	var tracks := track_map(a)
	var best := -INF
	var at := 0.0
	for i in samples:
		var t := a.length * float(i) / float(samples)
		var z := global_at(a, tracks, sk, foot, t, true).origin.dot(fwd)
		if z > best:
			best = z
			at = float(i) / float(samples)
	return at

## How fast a cycle carries its body along, from the feet alone (for clips made to play in
## place): the speed at which whichever foot is lowest slides backwards. `feet` are bone
## indices; returns metres (skeleton units) per second.
static func planted_speed(a: Animation, sk: Skeleton3D, feet: Array, fwd := Vector3(0, 0, 1), samples := 60) -> float:
	var tracks := track_map(a)
	var dt := a.length / float(samples)
	var travel := 0.0
	var counted := 0
	var prev := []
	for f in feet:
		prev.append(global_at(a, tracks, sk, f, 0.0, true).origin)
	for i in range(1, samples + 1):
		var t := dt * float(i)
		var cur := []
		var low := 0
		for j in feet.size():
			cur.append(global_at(a, tracks, sk, feet[j], t, true).origin)
			if (cur[j] as Vector3).y < (cur[low] as Vector3).y:
				low = j
		var d := ((prev[low] as Vector3) - (cur[low] as Vector3)).dot(fwd)
		if d > 0.0:
			travel += d
			counted += 1
		prev = cur
	return travel / maxf(a.length, 0.001) if counted > 0 else 0.0

## The knee position that puts a two-bone limb (hip `h`, lengths `a` and `b`) on target `t`,
## bending toward `pole` (any point the knee should lean toward). The target is pulled in
## when out of reach.
static func knee_for(h: Vector3, t: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var to := t - h
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var u := to.normalized() if to.length() > 0.0001 else Vector3.DOWN
	var v := (pole - h) - u * (pole - h).dot(u)
	if v.length() < 0.0001:
		v = u.cross(Vector3.RIGHT)
		if v.length() < 0.0001:
			v = u.cross(Vector3.FORWARD)
	v = v.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var ang := acos(cos_a)
	return h + (u * cos(ang) + v * sin(ang)) * a

## The rotation taking direction `from` onto `to` (shortest arc).
static func arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	if f.length() < 0.0001 or t.length() < 0.0001:
		return Quaternion.IDENTITY
	if f.dot(t) < -0.9999:
		var ax := f.cross(Vector3.UP)
		if ax.length() < 0.001:
			ax = f.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(f, t)
