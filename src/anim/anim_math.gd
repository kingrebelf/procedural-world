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
## place): the speed at which feet on the ground slide backwards (the median over every
## foot and moment a foot is down, so a foot still landing or already lifting doesn't
## skew it). `feet` are bone indices; `tips` (optional, one per foot) is the point in each
## bone's own space that touches the ground (a hoof at the end of a leaf bone). Returns
## metres (skeleton units) per second. `in_place` holds root bones at rest (clips whose
## root carries the body along); off, free root bones (IK foot controllers) move as keyed.
static func planted_speed(a: Animation, sk: Skeleton3D, feet: Array, fwd := Vector3(0, 0, 1), samples := 60, tips := [], in_place := true) -> float:
	var tracks := track_map(a)
	var pts := []
	var lo := INF
	var hi := -INF
	for i in samples + 1:
		var t := a.length * float(i) / float(samples)
		var row := []
		for j in feet.size():
			var g := global_at(a, tracks, sk, feet[j], t, in_place)
			var p: Vector3 = g * (tips[j] as Vector3) if j < tips.size() else g.origin
			row.append(p)
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		pts.append(row)
	var down := lo + maxf((hi - lo) * 0.08, 0.005)
	var dt := a.length / float(samples)
	var v := []
	for i in samples:
		for j in feet.size():
			var p0: Vector3 = pts[i][j]
			var p1: Vector3 = pts[i + 1][j]
			if p0.y <= down and p1.y <= down:
				v.append((p0 - p1).dot(fwd) / dt)
	if v.is_empty():
		return 0.0
	v.sort()
	return maxf(float(v[v.size() / 2]), 0.0)

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

## One step of a critically damped spring: value `x` moving at `v` toward `to`, settling
## in about 4/omega seconds without overshoot. Exact for any `dt`, so a skipped frame (level
## of detail) lands where an even pace would have. Returns Vector2(new x, new v).
## Muscles move like this, easing off rest and settling on their mark, where lerping by a
## fixed share each frame starts at full speed and stops dead.
static func spring(x: float, v: float, to: float, omega: float, dt: float) -> Vector2:
	var y := x - to
	var j := (v + omega * y) * dt
	var e := exp(-omega * dt)
	return Vector2(to + (y + j) * e, (v - omega * j) * e)

## A slow, never-repeating wobble in -1..1 (three incommensurate sines): the drift of a
## head that is never held quite still. `seed` gives each body its own.
static func drift(t: float, seed: float) -> float:
	return (sin(t * 0.73 + seed) * 0.5 + sin(t * 1.37 + seed * 2.1) * 0.3 + sin(t * 2.91 + seed * 3.7) * 0.2)

## How a walk-like cycle should be paced through its stride so planted feet stay put.
## Clips ease each foot through its time on the ground (slow as it lands, fast in the
## middle, slow as it lifts), so played at an even rate under a body moving at an even
## speed, the planted foot slides forward then back: the skate that makes a gait look
## mechanical. Returns {"speed": the cycle's mean ground speed (units per clip second),
## "warp": `samples` factors by phase (0..1) to multiply the play rate by}: faster where
## the planted feet move slowly, slower where they move fast. Where no foot is down (a
## gallop's flight) the pace runs on smoothly. Arguments as planted_speed.
static func stance_warp(a: Animation, sk: Skeleton3D, feet: Array, fwd := Vector3(0, 0, 1), samples := 48, tips := [], in_place := true) -> Dictionary:
	var tracks := track_map(a)
	var pts := []
	var lo := INF
	var hi := -INF
	for i in samples + 1:
		var t := a.length * float(i) / float(samples)
		var row := []
		for j in feet.size():
			var g := global_at(a, tracks, sk, feet[j], t, in_place)
			var p: Vector3 = g * (tips[j] as Vector3) if j < tips.size() else g.origin
			row.append(p)
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		pts.append(row)
	var down := lo + maxf((hi - lo) * 0.08, 0.005)
	var dt := a.length / float(samples)
	var s := PackedFloat32Array()
	s.resize(samples)
	var known := []
	for i in samples:
		var sum := 0.0
		var n := 0
		for j in feet.size():
			var p0: Vector3 = pts[i][j]
			var p1: Vector3 = pts[i + 1][j]
			if p0.y <= down and p1.y <= down:
				sum += (p0 - p1).dot(fwd) / dt
				n += 1
		s[i] = sum / float(n) if n > 0 else NAN
		if n > 0:
			known.append(i)
	if known.is_empty():
		return {"speed": 0.0, "warp": PackedFloat32Array()}
	# Flight: run on from the planted pace either side of it.
	for i in samples:
		if is_nan(s[i]):
			var b := -1
			var f := -1
			for k in range(1, samples):
				if b < 0 and not is_nan(s[(i - k + samples) % samples]):
					b = k
				if f < 0 and not is_nan(s[(i + k) % samples]):
					f = k
				if b >= 0 and f >= 0:
					break
			var sb: float = s[(i - b + samples) % samples]
			var sf: float = s[(i + f) % samples]
			s[i] = NAN if b < 0 else lerpf(sb, sf, float(b) / float(b + f))
	var filled := s.duplicate()
	for i in samples:
		if is_nan(filled[i]):
			filled[i] = 0.0
	var mean := 0.0
	for i in samples:
		mean += filled[i]
	mean /= float(samples)
	if mean <= 0.01:
		return {"speed": maxf(mean, 0.0), "warp": PackedFloat32Array()}
	# A light blur, and no more than double or half pace, so the swing never lurches.
	var w := PackedFloat32Array()
	w.resize(samples)
	for i in samples:
		var v := (filled[(i - 1 + samples) % samples] + 2.0 * filled[i] + filled[(i + 1) % samples]) * 0.25
		w[i] = mean / clampf(v, mean * 0.5, mean * 2.0)
	# Keep the stride's length: one cycle still covers mean * length at the base rate.
	var period := 0.0
	for i in samples:
		period += 1.0 / w[i]
	period /= float(samples)
	for i in samples:
		w[i] *= period
	return {"speed": mean, "warp": w}

## A table sampled evenly over a cycle (stance_warp, stance_weights), read at `phase`
## (0..1) between its samples; 1 for an empty table.
static func cyclic_at(w: PackedFloat32Array, phase: float) -> float:
	if w.is_empty():
		return 1.0
	var x := fposmod(phase, 1.0) * float(w.size())
	var i := int(x)
	return lerpf(w[i % w.size()], w[(i + 1) % w.size()], x - float(i))

## How firmly each foot is on the ground through a cycle: per foot, `samples` weights
## by phase (1 planted .. 0 in the air), softened over the moments it lands and lifts.
## Arguments as planted_speed.
static func stance_weights(a: Animation, sk: Skeleton3D, feet: Array, samples := 48, tips := [], in_place := true) -> Array:
	var tracks := track_map(a)
	var out := []
	for j in feet.size():
		var ys := PackedFloat32Array()
		var lo := INF
		var hi := -INF
		for i in samples:
			var g := global_at(a, tracks, sk, feet[j], a.length * float(i) / float(samples), in_place)
			var p: Vector3 = g * (tips[j] as Vector3) if j < tips.size() else g.origin
			ys.append(p.y)
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var band := maxf((hi - lo) * 0.08, 0.005)
		var w := PackedFloat32Array()
		for y in ys:
			w.append(1.0 - smoothstep(band * 0.6, band * 1.8, y - lo))
		out.append(w)
	return out
