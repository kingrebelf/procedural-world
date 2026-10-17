class_name BodyShape
extends RefCounted
## What makes one person's body their own: age, weight, how muscled they are, how tall
## and how they hold themselves. The kit body is a superhero; this turns it into a
## villager. Worked out from the persisted body record (and the person's age), so old
## saves vary too and the same person always looks the same.
##
## Applied three ways, all on the shared skeleton so every garment, armour shell and the
## ragdoll fit without knowing about it:
## - girth: each body bone's skin bind is scaled in the rest pose (fatter belly, softer
##   arms, wider hips), so the body and everything skinned with the same Skin follow;
## - stature: the whole model's uniform scale (callers use stature() for that);
## - posture: BodyPosture bends the spine, head and knees after the animation.
##
## shape() keys (for clothing and anything else that fits the body):
##   age (years), weight 0..1 (slim..heavy), muscle 0..1 (soft..kit hero), old 0..1,
##   stoop 0..1, limp (-1..1, sign = side), waddle 0..1, arms_out (rad), shoulder_in (m the shoulder joints move in, BodyPosture), girth {bone name: [sx, sy, sz] in character space or [g] across the
##   bone, pivot offset Vector3}, stature (model scale), pace (walk speed multiplier).

## Jobs that build real muscle, jobs that keep people wiry, and jobs that don't.
const STRONG_JOBS := ["smith", "guard", "miner", "lumberjack", "security officer", "dock worker", "mason"]
const WIRY_JOBS := ["hunter", "miller", "farmer", "warden", "bandit", "pirate", "fisher", "sailor"]
const SOFT_JOBS := ["scribe", "priest", "mystic", "merchant", "innkeeper", "bard", "runecarver", "herbalist", "engineer", "doctor", "medic"]
## Silver and white for greying hair.
const GREY := Color(0.66, 0.65, 0.63)
const WHITE := Color(0.86, 0.85, 0.83)

## A stable random number 0..1 for this body, per `salt`.
static func _rnd(b: Dictionary, salt: String) -> float:
	var key := "%.4f|%.4f|%s|%s|%d|%s" % [float(b.get("height", 1.0)), float(b.get("build", 1.0)),
		(b.get("skin", Color.WHITE) as Color).to_html(), (b.get("hair", Color.BLACK) as Color).to_html(), int(b.get("hair_style", 0)), salt]
	return float(hash(key) & 0xFFFFFF) / float(0xFFFFFF)

## `age` < 0: unknown (the player, remote players): a fit young adult.
static func shape(b: Dictionary, age := -1, job := "") -> Dictionary:
	var fem: bool = b.get("female", false)
	var known := age >= 0
	var yrs := float(age) if known else 28.0
	# The body record's build: villagers roll 0.85..1.2, players 0.3..0.7.
	var build := float(b.get("build", 1.0))
	var w := clampf((build - 0.85) / 0.35, 0.0, 1.0) if build >= 0.8 else clampf(build, 0.0, 1.0)
	# Middle age puts weight on; the very old get thinner.
	w = clampf(w + 0.18 * smoothstep(32.0, 55.0, yrs) - 0.12 * smoothstep(68.0, 80.0, yrs), 0.0, 1.0)
	var m := pow(_rnd(b, "muscle"), 1.8) * 0.5
	if job in STRONG_JOBS:
		m += 0.35
	elif job in WIRY_JOBS:
		m += 0.12
	elif job in SOFT_JOBS:
		m -= 0.1
	if fem:
		m *= 0.7
	var old := smoothstep(48.0, 78.0, yrs + (_rnd(b, "old") - 0.5) * 12.0)
	m = clampf(m * (1.0 - 0.65 * old), 0.0, 1.0)
	if not known:
		m = 0.55 if not fem else 0.4
		w = minf(w, 0.5)
	var soft := 1.0 - m
	var f := 1.0 if fem else 0.0
	var thin := 1.0 - 0.17 * old # limbs lose muscle with age
	# Character space: x across (left +), y up, z forward. [sx, sy, sz] scales the
	# bone's flesh about its head plus `pivot`; [g] scales it across the bone's length.
	var girth := {
		"pelvis": [[1.0 + 0.24 * w + 0.07 * f - 0.03 * soft, 1.0, 1.0 + 0.3 * w + 0.04 * f], Vector3(0, 0, -0.02)],
		"spine_01": [[0.97 + 0.48 * w - 0.03 * f, 1.0, 0.95 + 0.9 * w + 0.1 * old * (1.0 - w)], Vector3(0, 0, -0.08)],
		"spine_02": [[0.95 + 0.4 * w - 0.05 * f, 1.0, 0.95 + 0.66 * w], Vector3(0, 0, -0.08)],
		"spine_03": [[0.97 - 0.17 * soft + 0.18 * w - 0.05 * old, 1.0, 0.98 - 0.14 * soft + 0.26 * w], Vector3(0, 0, -0.09)],
		"neck_01": [[1.0 - 0.22 * soft + 0.3 * w - 0.03 * f - 0.06 * old], Vector3.ZERO],
		"clavicle": [[1.0 - 0.26 * soft + 0.14 * w], Vector3.ZERO],
		"upperarm": [[(1.0 - 0.32 * soft + 0.36 * w) * thin], Vector3.ZERO],
		"lowerarm": [[(1.0 - 0.2 * soft + 0.2 * w) * thin], Vector3.ZERO],
		"thigh": [[(0.97 - 0.07 * soft + 0.36 * w + 0.05 * f) * thin], Vector3.ZERO],
		"calf": [[(1.0 - 0.07 * soft + 0.2 * w) * thin], Vector3.ZERO],
	}
	# The old stoop (some much more than others); everyone slouches or stands tall a little.
	var stoop := clampf(old * (0.45 + 0.75 * _rnd(b, "stoop")) + (_rnd(b, "slouch") - 0.4) * 0.25, -0.1, 1.0)
	# The kit hero's shoulders are broad as a door; most people's are not.
	var shoulder_in := (0.045 * (1.0 - f) + 0.02 * f) * soft * (1.0 - 0.4 * w)
	# A few limp (more of the old); heavy builds sway and hold their arms off their sides.
	var limp := 0.0
	if known and _rnd(b, "limp") < 0.05 + 0.12 * old:
		limp = (0.5 + 0.5 * _rnd(b, "limp_how")) * (1.0 if _rnd(b, "limp_side") < 0.5 else -1.0)
	var waddle := smoothstep(0.45, 1.0, w)
	var arms_out := 0.03 + 0.24 * w + 0.04 * m
	return {"age": yrs, "weight": w, "muscle": m, "old": old, "stoop": stoop, "female": fem, "shoulder_in": shoulder_in,
		"limp": limp, "waddle": waddle, "arms_out": arms_out,
		"girth": girth, "stature": stature(b, age), "pace": pace(b, age)}

## The model's uniform scale: the kit body is 1.82 m (male) and 1.78 m (female); people
## then range about 1.56-1.87 m (men) and 1.46-1.72 m (women), and lose a little height
## when old (the stoop takes more).
static func stature(b: Dictionary, age := -1) -> float:
	var s := float(b.get("height", 1.0)) * 0.95
	if b.get("female", false):
		s *= 0.955
	if age >= 0:
		s *= 1.0 - 0.035 * smoothstep(55.0, 80.0, float(age))
	return s

## How fast they walk compared with a fit adult: the old slow down, the heavy a little.
static func pace(b: Dictionary, age := -1) -> float:
	if age < 0:
		return 1.0
	var w := clampf((float(b.get("build", 1.0)) - 0.85) / 0.35, 0.0, 1.0)
	return (1.0 - 0.32 * smoothstep(55.0, 80.0, float(age))) * (1.0 - 0.08 * w)

## Hair greys from the forties (some sooner, some later) and turns white when old.
static func hair_color(b: Dictionary, age := -1) -> Color:
	var c: Color = b.get("hair", Color(0.2, 0.15, 0.1))
	if age < 0:
		return c
	var yrs := float(age) + (_rnd(b, "grey") - 0.5) * 16.0
	var g := smoothstep(38.0, 66.0, yrs)
	if g <= 0.0:
		return c
	var to := GREY.lerp(WHITE, smoothstep(62.0, 82.0, yrs))
	# Fair hair goes straight to white; dark hair keeps some of its depth (salt and pepper).
	return c.lerp(to.darkened(0.25 * (1.0 - c.get_luminance()) * (1.0 - g)), g)

## Whether an older man has lost his hair.
static func bald(b: Dictionary, age := -1) -> bool:
	return age >= 0 and not b.get("female", false) and _rnd(b, "bald") < 0.55 * smoothstep(40.0, 70.0, float(age))

## How thin the hair has got at the crown, 0..1 (men more than women).
static func thinning(b: Dictionary, age := -1) -> float:
	if age < 0:
		return 0.0
	var k := 0.85 if not b.get("female", false) else 0.4
	return clampf(k * smoothstep(42.0, 78.0, float(age)) * (0.4 + 0.8 * _rnd(b, "thin")), 0.0, 1.0)

## Reshapes `skin` (a per-person copy) in place for shape `sh`: each body bone's flesh is
## scaled in the rest pose, so skinning carries it through every animation.
static func apply_girth(skin: Skin, sk: Skeleton3D, sh: Dictionary) -> void:
	var girth: Dictionary = sh["girth"]
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "":
			bn = sk.get_bone_name(skin.get_bind_bone(i))
		var key := bn
		if bn.ends_with("_l") or bn.ends_with("_r"):
			key = bn.substr(0, bn.length() - 2)
		if not girth.has(key):
			continue
		var e: Array = girth[key]
		var sc: Array = e[0]
		var bind := skin.get_bind_pose(i)
		var rest := bind.affine_inverse() # the bone in mesh space
		var c: Vector3 = rest.origin + (e[1] as Vector3)
		var s: Basis
		if sc.size() == 3:
			s = Basis.from_scale(Vector3(sc[0], sc[1], sc[2]))
		else:
			# Across the bone: everything but its length scaled by g.
			var d := rest.basis.y.normalized()
			var g := float(sc[0]) - 1.0
			s = Basis(Vector3(1, 0, 0) + (Vector3(1, 0, 0) - d * d.x) * g,
				Vector3(0, 1, 0) + (Vector3(0, 1, 0) - d * d.y) * g,
				Vector3(0, 0, 1) + (Vector3(0, 0, 1) - d * d.z) * g)
		var m := Transform3D(s, c - s * c)
		skin.set_bind_pose(i, bind * m)
