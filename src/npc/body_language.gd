class_name BodyLanguage
extends SkeletonModifier3D
## Hand, arm, head and face gestures layered over whatever animation a person is
## playing: waving, pointing, holding up any fingers, thumbs up, saluting, clapping,
## shrugging, nodding, winking, bowing and more. Each gesture is a pose described in the
## person's own frame (outward, up, forward), so the same data drives both arms and works
## for every body; poses are solved from the skeleton's rest pose at run time.
## Also blinks now and then, so faces never stare.

## Finger order everywhere: thumb, index, middle, ring, pinky. 0 = straight, 1 = curled.
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const FIST := [0.75, 1.0, 1.0, 1.0, 1.0]
const OPEN := [0.0, 0.0, 0.0, 0.0, 0.0]
const RELAXED := [0.15, 0.2, 0.25, 0.3, 0.35]

## Raised hand, palm out, for showing fingers.
const SHOW := {"upper": Vector3(0.35, -0.45, 0.8), "fore": Vector3(0.05, 1.0, 0.3), "palm": Vector3(0, 0, 1)}

## name -> {seconds (0 = until stopped), r / l: arm pose {upper, fore, palm, fingers, wave},
## head: {nod, shake, tilt, down}, bow, shrug, wink: "l"|"r"}
## Arm directions are (outward, up, forward) in the person's frame.
const GESTURES := {
	"wave": {"seconds": 2.6, "r": {"upper": Vector3(0.75, 0.55, 0.2), "fore": Vector3(0.12, 1.0, 0.1), "palm": Vector3(0, 0, 1), "fingers": OPEN, "wave": 0.35}},
	"wave_both": {"seconds": 2.6, "r": {"upper": Vector3(0.6, 0.9, 0.15), "fore": Vector3(0.12, 1.0, 0.1), "palm": Vector3(0, 0, 1), "fingers": OPEN, "wave": 0.35},
		"l": {"upper": Vector3(0.6, 0.9, 0.15), "fore": Vector3(0.12, 1.0, 0.1), "palm": Vector3(0, 0, 1), "fingers": OPEN, "wave": -0.35}},
	"point": {"seconds": 2.5, "r": {"upper": Vector3(0.1, 0.2, 1.0), "fore": Vector3(0.0, 0.15, 1.0), "palm": Vector3(-0.3, -1, 0), "fingers": [0.7, 0.0, 1.0, 1.0, 1.0]}},
	"thumbs_up": {"seconds": 2.5, "r": {"upper": Vector3(0.25, -0.6, 0.75), "fore": Vector3(-0.1, 0.15, 1.0), "palm": Vector3(-1, 0, 0), "fingers": [0.0, 1.0, 1.0, 1.0, 1.0]}},
	"thumbs_down": {"seconds": 2.5, "r": {"upper": Vector3(0.25, -0.6, 0.75), "fore": Vector3(-0.1, 0.15, 1.0), "palm": Vector3(1, 0, 0), "fingers": [0.0, 1.0, 1.0, 1.0, 1.0]}},
	"fist": {"seconds": 2.5, "r": {"upper": Vector3(0.3, 0.35, 0.6), "fore": Vector3(0.0, 1.0, 0.3), "palm": Vector3(0, 0, -1), "fingers": FIST, "shake": 0.12}},
	"salute": {"seconds": 2.5, "r": {"upper": Vector3(0.9, 0.25, 0.45), "fore": Vector3(-0.9, 0.65, 0.05), "palm": Vector3(0, -1, 0.3), "fingers": OPEN}},
	"beckon": {"seconds": 3.0, "r": {"upper": Vector3(0.2, -0.7, 0.7), "fore": Vector3(0.0, 0.35, 1.0), "palm": Vector3(0, 1, 0), "fingers": RELAXED, "curl_wave": 0.8}},
	"stop": {"seconds": 2.2, "r": {"upper": Vector3(0.15, 0.25, 1.0), "fore": Vector3(0.0, 0.6, 1.0), "palm": Vector3(0, 0, 1), "fingers": OPEN}},
	"shrug": {"seconds": 2.0, "shrug": 1.0, "head": {"tilt": 0.18},
		"r": {"upper": Vector3(0.5, -0.8, 0.25), "fore": Vector3(0.55, 0.1, 0.85), "palm": Vector3(0, 1, 0), "fingers": RELAXED},
		"l": {"upper": Vector3(0.5, -0.8, 0.25), "fore": Vector3(0.55, 0.1, 0.85), "palm": Vector3(0, 1, 0), "fingers": RELAXED}},
	"clap": {"seconds": 3.0, "r": {"upper": Vector3(0.3, -0.6, 0.75), "fore": Vector3(-0.55, 0.3, 0.8), "palm": Vector3(-1, 0, 0), "fingers": OPEN, "clap": 0.3},
		"l": {"upper": Vector3(0.3, -0.6, 0.75), "fore": Vector3(-0.55, 0.3, 0.8), "palm": Vector3(-1, 0, 0), "fingers": OPEN, "clap": 0.3}},
	"cheer": {"seconds": 3.0, "r": {"upper": Vector3(0.4, 1.0, 0.1), "fore": Vector3(0.15, 1.0, 0.0), "palm": Vector3(0, 0, 1), "fingers": FIST, "pump": 0.25},
		"l": {"upper": Vector3(0.4, 1.0, 0.1), "fore": Vector3(0.15, 1.0, 0.0), "palm": Vector3(0, 0, 1), "fingers": FIST, "pump": -0.25}},
	"facepalm": {"seconds": 2.5, "head": {"down": 0.3}, "r": {"upper": Vector3(0.15, -0.35, 0.9), "fore": Vector3(-0.45, 0.9, -0.05), "palm": Vector3(0, 0, -1), "fingers": RELAXED}},
	"think": {"seconds": 3.0, "head": {"tilt": -0.15, "down": 0.1}, "r": {"upper": Vector3(0.15, -0.75, 0.6), "fore": Vector3(-0.45, 0.95, 0.1), "palm": Vector3(-0.3, 0, -1), "fingers": [0.2, 0.3, 0.8, 0.9, 0.95]},
		"l": {"upper": Vector3(0.2, -0.9, 0.3), "fore": Vector3(-0.85, 0.1, 0.5), "palm": Vector3(0, 1, 0), "fingers": RELAXED}},
	"pray": {"seconds": 3.0, "head": {"down": 0.25}, "r": {"upper": Vector3(0.3, -0.75, 0.5), "fore": Vector3(-0.75, 0.6, 0.35), "palm": Vector3(-1, 0, 0), "fingers": OPEN},
		"l": {"upper": Vector3(0.3, -0.75, 0.5), "fore": Vector3(-0.75, 0.6, 0.35), "palm": Vector3(-1, 0, 0), "fingers": OPEN}},
	"hips": {"seconds": 3.0, "r": {"upper": Vector3(0.8, -0.7, -0.1), "fore": Vector3(-0.7, -0.45, 0.2), "palm": Vector3(-1, 0, 0), "fingers": RELAXED},
		"l": {"upper": Vector3(0.8, -0.7, -0.1), "fore": Vector3(-0.7, -0.45, 0.2), "palm": Vector3(-1, 0, 0), "fingers": RELAXED}},
	"peace": {"seconds": 2.5, "r": SHOW, "fingers_r": [1.0, 0.0, 0.0, 1.0, 1.0]},
	"rock": {"seconds": 2.5, "r": SHOW, "fingers_r": [0.8, 0.0, 1.0, 1.0, 0.0]},
	"ok": {"seconds": 2.5, "r": SHOW, "fingers_r": [0.55, 0.6, 0.0, 0.05, 0.1]},
	"call_me": {"seconds": 2.5, "r": {"upper": Vector3(0.6, -0.4, 0.5), "fore": Vector3(-0.3, 1.0, 0.0), "palm": Vector3(-1, 0, 0)}, "fingers_r": [0.0, 1.0, 1.0, 1.0, 0.0]},
	"crossed": {"seconds": 2.5, "r": SHOW, "fingers_r": [1.0, 0.0, 0.1, 1.0, 1.0], "cross": true},
	"count": {"seconds": 6.0, "r": SHOW, "count": true},
	"bow": {"seconds": 2.2, "bow": 0.75, "head": {"down": 0.25}},
	"nod": {"seconds": 1.6, "head": {"nod": 0.22}},
	"shake_head": {"seconds": 1.8, "head": {"shake": 0.35}},
	"tilt": {"seconds": 2.0, "head": {"tilt": 0.25}},
	"wink": {"seconds": 0.9, "wink": "l", "head": {"tilt": 0.12}},
	"wink_r": {"seconds": 0.9, "wink": "r", "head": {"tilt": -0.12}},
}

## Gestures you can ask for by holding up given fingers ("show me your middle finger").
static func fingers_gesture(which: Array) -> Dictionary:
	var f: Array = [1.0, 1.0, 1.0, 1.0, 1.0]
	if not which.has("thumb"):
		f[0] = 1.0
	for w in which:
		var i := FINGERS.find(w)
		if i >= 0:
			f[i] = 0.0
	return {"seconds": 2.6, "r": SHOW, "fingers_r": f}

## Hold up n fingers (1-5), counting the way most people do: index first, thumb last.
static func count_fingers(n: int) -> Array:
	var f: Array = [1.0, 1.0, 1.0, 1.0, 1.0]
	for i in clampi(n, 0, 5):
		f[[1, 2, 3, 4, 0][i]] = 0.0
	return f

## Every gesture name a person understands, including "fingers_1".."fingers_5" and
## "finger_<name>".
static func names() -> Array:
	var out: Array = GESTURES.keys()
	for n in range(1, 6):
		out.append("fingers_%d" % n)
	for f in FINGERS:
		out.append("finger_" + f)
	return out

static func resolve(name: String) -> Dictionary:
	if GESTURES.has(name):
		return GESTURES[name]
	if name.begins_with("fingers_"):
		return {"seconds": 2.6, "r": SHOW, "fingers_r": count_fingers(name.substr(8).to_int())}
	if name.begins_with("finger_"):
		if name == "finger_thumb":
			return GESTURES["thumbs_up"]
		return fingers_gesture([name.substr(7)])
	return {}

var eyelids: Array = [null, null] ## [left, right] Node3D, shown while the eye is shut.

var _g: Dictionary = {}
var _name := ""
var _t := 0.0
var _len := 0.0
var _w := 0.0
var _last := 0
var _blink_at := 0.0
var _blink := 0.0
var _frame: Basis ## columns: outward-left, up, forward in skeleton space
var _bones := {}
var _rest_dir := {}
var _palm0: Vector3
## Right-hand finger curls (thumb..pinky, 0..1) held while the hand grips something
## (HumanModel.hold), under any gesture; [] for none.
var grip_r: Array = []
## The right hand's orientation in skeleton space, overriding the animation's (a gun
## held square to the view); null leaves the hand as animated.
var hand_r = null

func play(name: String) -> bool:
	var g := resolve(name)
	if g.is_empty():
		return false
	_g = g
	_name = name
	_t = 0.0
	_len = float(g.get("seconds", 2.5))
	return true

func stop() -> void:
	_len = minf(_len, _t + 0.3)

func current() -> String:
	return _name if _t < _len else ""

func _bone(n: String) -> int:
	if not _bones.has(n):
		_bones[n] = get_skeleton().find_bone(n)
	return _bones[n]

func _setup(sk: Skeleton3D) -> void:
	var up := (sk.get_bone_global_rest(_bone("Head")).origin - sk.get_bone_global_rest(_bone("pelvis")).origin).normalized()
	var fwd := sk.get_bone_global_rest(_bone("ball_l")).origin - sk.get_bone_global_rest(_bone("foot_l")).origin
	fwd = (fwd - up * fwd.dot(up)).normalized()
	_frame = Basis(up.cross(fwd).normalized(), up, fwd)
	_palm0 = -up

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bone("Head") < 0:
		return
	if _frame == Basis():
		_setup(sk)
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last) / 1000.0, 0.0, 0.1) if _last > 0 else 0.0
	_last = now
	if hand_r != null and _bone("hand_r") >= 0:
		var hb := _bone("hand_r")
		var parent := sk.get_bone_parent(hb)
		var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
		sk.set_bone_pose_rotation(hb, (pb.inverse() * (hand_r as Basis)).get_rotation_quaternion())
	if not grip_r.is_empty():
		for i in 5:
			_finger(sk, "r", i, float(grip_r[i]), 1.0)
	_t += dt
	var active := _t < _len
	_w = move_toward(_w, 1.0 if active else 0.0, dt * 4.0)
	_blinks(dt)
	if _w <= 0.001 or _g.is_empty():
		return
	var w := smoothstep(0.0, 1.0, _w)
	var t := _t
	if _g.has("bow"):
		var b: float = _g["bow"] * w * minf(1.0, t * 2.0)
		for n in ["spine_01", "spine_02", "spine_03"]:
			_turn(sk, _bone(n), _frame.x, b / 3.0)
	if _g.has("shrug"):
		var s: float = _g["shrug"] * w * (0.5 + 0.5 * sin(minf(t, 1.0) * PI))
		_turn(sk, _bone("clavicle_l"), _frame.z, -0.18 * s)
		_turn(sk, _bone("clavicle_r"), _frame.z, 0.18 * s)
	for side in ["r", "l"]:
		if _g.has(side):
			_arm(sk, side, _g[side], w, t)
	var h: Dictionary = _g.get("head", {})
	if not h.is_empty():
		var hb := _bone("Head")
		var fade := w * clampf((_len - t) * 2.0, 0.0, 1.0) if h.has("nod") or h.has("shake") else w
		if h.has("nod"):
			_turn(sk, hb, _frame.x, sin(t * 9.0) * float(h["nod"]) * fade)
		if h.has("shake"):
			_turn(sk, hb, _frame.y, sin(t * 10.0) * float(h["shake"]) * fade)
		if h.has("tilt"):
			_turn(sk, hb, _frame.z, float(h["tilt"]) * w)
		if h.has("down"):
			_turn(sk, hb, _frame.x, float(h["down"]) * w)

## side: "r" or "l". The person's right hand is on the -x side of their frame.
func _arm(sk: Skeleton3D, side: String, p: Dictionary, w: float, t: float) -> void:
	var out := -_frame.x if side == "r" else _frame.x
	var to_world := func(v: Vector3) -> Vector3:
		return (out * v.x + _frame.y * v.y + _frame.z * v.z).normalized()
	var upper: Vector3 = p["upper"]
	var fore: Vector3 = p["fore"]
	if p.has("wave"):
		fore = Vector3(fore.x + sin(t * 9.0) * float(p["wave"]), fore.y, fore.z)
	if p.has("pump"):
		upper.y += sin(t * 8.0) * absf(float(p["pump"]))
	if p.has("clap"):
		var c := pow(absf(sin(t * 6.5)), 0.6)
		fore = Vector3(fore.x + float(p["clap"]) * c, fore.y, fore.z)
	if p.has("shake"):
		fore = fore + Vector3(0, 0, sin(t * 18.0) * float(p["shake"]))
	var palm: Vector3 = to_world.call(p["palm"])
	_aim(sk, _bone("upperarm_" + side), to_world.call(upper), palm, w)
	_aim(sk, _bone("lowerarm_" + side), to_world.call(fore), palm, w)
	_aim(sk, _bone("hand_" + side), to_world.call(fore), palm, w)
	var fingers: Array = _g.get("fingers_" + side, p.get("fingers", RELAXED))
	if _g.get("count", false):
		fingers = count_fingers(1 + int(t / (_len / 5.2)))
	var cw := float(p.get("curl_wave", 0.0))
	for i in 5:
		var c := float(fingers[i])
		if cw > 0.0 and i > 0:
			c = clampf(c + (0.5 + 0.5 * sin(t * 7.0 - i * 0.4)) * cw, 0.0, 1.0)
		_finger(sk, side, i, c, w)
	if _g.get("cross", false) and side == "r":
		# Middle finger crossed over the index.
		_turn(sk, _bone("middle_01_r"), _frame.y, -0.35 * w)

## Turns a bone so it points along `dir` (skeleton space) with its palm side facing
## `palm`, blended by w over the animated pose.
func _aim(sk: Skeleton3D, b: int, dir: Vector3, palm: Vector3, w: float) -> void:
	if b < 0:
		return
	var rest := sk.get_bone_global_rest(b)
	if not _rest_dir.has(b):
		var child := -1
		for c in sk.get_bone_children(b):
			var cn := sk.get_bone_name(c)
			if cn.begins_with("middle_01") or child < 0:
				child = c
		_rest_dir[b] = (sk.get_bone_global_rest(child).origin - rest.origin).normalized() if child >= 0 else rest.basis.y.normalized()
	var d0: Vector3 = _rest_dir[b]
	var r1 := Quaternion(d0, dir)
	var n1 := r1 * _palm0
	var a := (n1 - dir * n1.dot(dir)).normalized()
	var h := (palm - dir * palm.dot(dir)).normalized()
	var twist := 0.0
	if a.length_squared() > 0.5 and h.length_squared() > 0.5:
		twist = a.signed_angle_to(h, dir)
	var target := Basis(Quaternion(dir, twist) * r1) * rest.basis.orthonormalized()
	var parent := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local := (pb.inverse() * target).get_rotation_quaternion()
	var cur := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, cur.slerp(local, w))

## Curls one finger (all three joints) toward the palm.
func _finger(sk: Skeleton3D, side: String, i: int, curl: float, w: float) -> void:
	var f: String = FINGERS[i]
	var b1 := _bone("%s_01_%s" % [f, side])
	if b1 < 0:
		return
	var toward := _palm0
	if i == 0 and hand_r != null and side == "r":
		# Round a gun's grip the thumb wraps the palm side and lies along it, forward.
		toward = _palm0
	elif i == 0:
		# The thumb folds across the palm toward the little finger.
		var pk := sk.get_bone_global_rest(_bone("pinky_01_" + side)).origin
		var ix := sk.get_bone_global_rest(_bone("index_01_" + side)).origin
		toward = (_palm0 * 0.7 + (pk - ix).normalized() * 0.7).normalized()
	var amounts := [0.55, 0.75, 0.6] if i > 0 else [0.35, 0.5, 0.45]
	for j in 3:
		var b := _bone("%s_%02d_%s" % [f, j + 1, side])
		if b < 0:
			continue
		var rest := sk.get_bone_global_rest(b)
		var d0 := rest.basis.y.normalized()
		var axis := d0.cross(toward)
		if axis.length_squared() < 1e-6:
			continue
		var local_axis := (rest.basis.orthonormalized().inverse() * axis.normalized()).normalized()
		var q := sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(local_axis, curl * amounts[j] * 2.0)
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(q, w))

## Rotates a bone about a skeleton-space axis, on top of its current pose.
func _turn(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 1e-4:
		return
	var g := sk.get_bone_global_pose(b).basis.orthonormalized()
	var local_axis := (g.inverse() * axis).normalized()
	sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion(local_axis, angle))

func _blinks(dt: float) -> void:
	if eyelids[0] == null:
		return
	_blink_at -= dt
	if _blink_at <= 0.0:
		_blink_at = randf_range(2.2, 6.0)
		_blink = 0.14
	_blink -= dt
	var wink := String(_g.get("wink", "")) if _t < _len else ""
	var shut_l := _blink > 0.0 or (wink == "l" and _t > 0.15 and _t < _len - 0.2)
	var shut_r := _blink > 0.0 or (wink == "r" and _t > 0.15 and _t < _len - 0.2)
	(eyelids[0] as Node3D).visible = shut_l
	(eyelids[1] as Node3D).visible = shut_r
