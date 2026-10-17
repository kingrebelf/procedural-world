class_name HumanAnimator
extends Node
## Drives a person's AnimationTree. The pace of the walk comes from how fast the body
## actually moves over the ground (measured here, every frame), not from what the caller
## asks: walk, jog and sprint are blended stride for stride (their cycles share where the
## left foot lands, see tools/bake_anims.gd) and played at the cadence that makes the
## planted foot stay put, so feet never skate. Turning on the spot shuffles the feet,
## speeding up and slowing down tips the body, turns bank it (HumanIK).
##
## Layers, bottom to top: the state (idle, talk, work, sit...; cross-faded between two
## slots) under the gait blend (by speed), an upper-body layer (a sword or pistol held
## ready while running) and a one-shot (a swing, a hit, a shout) that plays over the whole
## body when standing and over the upper body only when on the move.
##
## Far and off-screen people update less often (animation LOD), and only those close by
## pay for foot placement.

## Gaits in order of speed, each played between these time scales before the next takes
## over (a walk quickens a little before it breaks into a jog).
const GAITS := ["walk", "jog", "sprint"]
const TS := {"walk": [0.5, 1.25], "jog": [0.8, 1.2], "sprint": [0.85, 1.45]}
## States that move the body themselves: played at the pace it moves, never under the gait.
const OWN_MOTION := ["swim", "zombie_walk", "carry", "crouch_walk", "walk_formal"]
## States the gait never blends over: sitting, lying, in the air, kneeling.
const STILL := ["sit", "sit_talk", "sit_down", "stand_up", "get_up", "death", "swim_idle", "jump_air",
	"jump_start", "jump_land", "fix", "roll", "flip", "climb", "crouch", "plant", "harvest"]
## States whose feet stay where the animation puts them (no ground fitting).
const NO_FEET := ["sit", "sit_talk", "sit_down", "stand_up", "get_up", "death", "swim", "swim_idle",
	"jump_air", "jump_start", "roll", "flip", "climb"]
const XFADE := 0.28
## Bones the upper-body layer and upper-body one-shots move (spine_01 and all above it).
const UPPER_ROOT := "spine_01"

var tree: AnimationTree
var skeleton: Skeleton3D
var ik: HumanIK
var body: Node3D ## whose motion over the ground sets the pace
var locomotion := true ## off for first-person arms, which ride the camera
var lod := true ## off where the person must always animate fully (first-person arms)
var manual := false ## advanced only by update() (tools stepping time exactly)

var _bt: AnimationNodeBlendTree
var _gait := {} ## name -> {speed, len, phase}
var _state := "idle"
var _state_speed := 1.0
var _slot := 0
var _mix := 1.0 ## 0..1 from the old slot to the current one
var _upper := ""
var _uslot := 0
var _umix := 1.0
var _upper_w := 0.0
var _move_w := 0.0
var _phase := 0.0
var _speed := 0.0 ## smoothed, in skeleton units per second
var _accel := 0.0
var _yaw_rate := 0.0
var _turn := 0.0
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _accum := 0.0
var _tick := 0
var _idle_rate := 1.0
var _hold := false

## lib: the people's AnimationLibrary; root: the node the clips' track paths start from.
func setup(lib: AnimationLibrary, root: Node, sk: Skeleton3D, who: Node3D) -> void:
	skeleton = sk
	body = who
	_idle_rate = randf_range(0.88, 1.12)
	_tick = randi() % 8
	_phase = randf() # a crowd never walks in step
	for g in GAITS:
		if lib.has_animation(g):
			var a := lib.get_animation(g)
			_gait[g] = {"speed": float(a.get_meta("speed", 1.0)), "len": a.length, "phase": float(a.get_meta("phase", 0.0))}
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.root_node = tree.get_path_to(root)
	tree.add_animation_library("", lib)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_bt = _graph(lib)
	tree.tree_root = _bt
	tree.active = true
	_assign(0, "idle", true)
	_assign(1, "idle", true)

func _graph(lib: AnimationLibrary) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	for i in 2:
		_clip(bt, "a%d" % i, "idle")
		bt.add_node("k%d" % i, AnimationNodeTimeSeek.new())
		bt.add_node("t%d" % i, AnimationNodeTimeScale.new())
		bt.connect_node("k%d" % i, 0, "a%d" % i)
		bt.connect_node("t%d" % i, 0, "k%d" % i)
		_clip(bt, "u%d" % i, "idle")
		bt.add_node("uk%d" % i, AnimationNodeTimeSeek.new())
		bt.connect_node("uk%d" % i, 0, "u%d" % i)
	bt.add_node("x", AnimationNodeBlend2.new())
	bt.connect_node("x", 0, "t0")
	bt.connect_node("x", 1, "t1")
	for g in GAITS:
		_clip(bt, g, g)
		bt.add_node("k_" + g, AnimationNodeTimeSeek.new())
		bt.connect_node("k_" + g, 0, g)
	bt.add_node("wj", AnimationNodeBlend2.new())
	bt.connect_node("wj", 0, "k_walk")
	bt.connect_node("wj", 1, "k_jog")
	bt.add_node("js", AnimationNodeBlend2.new())
	bt.connect_node("js", 0, "wj")
	bt.connect_node("js", 1, "k_sprint")
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.connect_node("move", 0, "x")
	bt.connect_node("move", 1, "js")
	bt.add_node("ux", AnimationNodeBlend2.new())
	bt.connect_node("ux", 0, "uk0")
	bt.connect_node("ux", 1, "uk1")
	var up := AnimationNodeBlend2.new()
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.12
	shot.fadeout_time = 0.22
	for p in upper_paths(lib, skeleton):
		up.set_filter_path(p, true)
		shot.set_filter_path(p, true)
	up.filter_enabled = true
	bt.add_node("up", up)
	bt.connect_node("up", 0, "move")
	bt.connect_node("up", 1, "ux")
	_clip(bt, "sa", "idle")
	bt.add_node("st", AnimationNodeTimeScale.new())
	bt.connect_node("st", 0, "sa")
	bt.add_node("shot", shot)
	bt.connect_node("shot", 0, "up")
	bt.connect_node("shot", 1, "st")
	bt.connect_node("output", 0, "shot")
	return bt

static func _clip(bt: AnimationNodeBlendTree, node: String, anim: String) -> void:
	var a := AnimationNodeAnimation.new()
	a.animation = anim
	bt.add_node(node, a)

## Track paths of the spine and everything above it, as the clips name them.
static func upper_paths(lib: AnimationLibrary, sk: Skeleton3D) -> Array:
	var prefix := ""
	var a := lib.get_animation("idle")
	for i in a.get_track_count():
		var p := String(a.track_get_path(i))
		if p.ends_with(":" + UPPER_ROOT):
			prefix = p.substr(0, p.length() - UPPER_ROOT.length())
			break
	var out := []
	var top := sk.find_bone(UPPER_ROOT)
	if top < 0 or prefix == "":
		return out
	for b in sk.get_bone_count():
		var c := b
		while c >= 0 and c != top:
			c = sk.get_bone_parent(c)
		if c == top:
			out.append(NodePath(prefix + sk.get_bone_name(b)))
	return out

# --- What the person is doing ------------------------------------------------------------

## The looping (or held) state under the gait: idle, talk, a job, sitting... Gait names
## (walk, jog, sprint) all mean "idle, moving at whatever pace the body moves".
func set_state(state: String, speed := 1.0, hold_end := false) -> void:
	if state in GAITS:
		state = "idle"
	if not tree.has_animation(state):
		state = "idle"
	_state_speed = speed
	_hold = hold_end
	if state == _state:
		return
	_state = state
	_slot = 1 - _slot
	_mix = 1.0 - _mix
	_assign(_slot, state, false)

func state() -> String:
	return _state

func _assign(slot: int, state: String, instant: bool) -> void:
	(_bt.get_node("a%d" % slot) as AnimationNodeAnimation).animation = state
	var a := tree.get_animation(state)
	var at := 0.0
	if state == "idle" or (a.loop_mode != Animation.LOOP_NONE and not state in OWN_MOTION):
		# Crowds never breathe in step.
		at = randf() * a.length
	if _hold and a.loop_mode == Animation.LOOP_NONE:
		at = a.length
	tree.set("parameters/k%d/seek_request" % slot, at)
	if instant:
		_mix = 1.0

## A pose held over the arms and chest whatever the legs do ("" for none): a sword or gun
## ready while running.
func set_upper(state: String) -> void:
	if state != "" and not tree.has_animation(state):
		state = ""
	if state == _upper:
		return
	_upper = state
	if state != "":
		_uslot = 1 - _uslot
		_umix = 1.0 - _umix
		(_bt.get_node("u%d" % _uslot) as AnimationNodeAnimation).animation = state
		tree.set("parameters/uk%d/seek_request" % _uslot, 0.0)

## Plays `state` once over the current animation, at `speed`. Over the upper body only
## while walking or running, so the legs keep going.
func shot(state: String, speed := 1.0) -> void:
	(_bt.get_node("sa") as AnimationNodeAnimation).animation = state
	var one := _bt.get_node("shot") as AnimationNodeOneShot
	one.filter_enabled = _move_w > 0.35 and not state in ["death", "get_up", "sit_down", "stand_up", "roll", "flip", "jump_start", "jump_land", "climb", "knockback"]
	tree.set("parameters/st/scale", speed)
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func end_shot() -> void:
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

## True while the feet should be fitted to the ground.
func feet_free() -> bool:
	return not (_state in NO_FEET)

## Where the stride cycle is, 0..1 (the left foot lands at 0), and how much the body is
## on the move (0 standing .. 1 walking or running), for BodyPosture's sway and limp.
func stride() -> Vector2:
	return Vector2(_phase, _move_w)

## How fast the body moves over the ground, metres a second.
func ground_speed() -> float:
	return _speed * _scale()

func _scale() -> float:
	return body.global_basis.get_scale().y if body and body.is_inside_tree() else 1.0

# --- Gait --------------------------------------------------------------------------------

## The gait blend for skeleton-space speed `v`: {"w": weights per gait (GAITS order),
## "cycle": seconds per stride cycle}. Between two gaits the blend weight is solved so the
## blended stride over the blended cycle is exactly `v`: the planted foot stays planted.
static func solve(v: float, gait: Dictionary) -> Dictionary:
	var w := [0.0, 0.0, 0.0]
	var names: Array = GAITS.filter(func(g): return gait.has(g))
	if names.is_empty():
		return {"w": w, "cycle": 1.0}
	for i in names.size():
		var g: String = names[i]
		var nat: float = maxf(float(gait[g]["speed"]), 0.01)
		var len: float = gait[g]["len"]
		var last := i == names.size() - 1
		var top: float = 1.6 if last else TS[g][1]
		if v <= nat * top or last:
			var ts := clampf(v / nat, TS[g][0], top)
			w[GAITS.find(g)] = 1.0
			return {"w": w, "cycle": len / ts}
		var n: String = names[i + 1]
		var nat2: float = maxf(float(gait[n]["speed"]), 0.01)
		var lo2: float = TS[n][0]
		if v < nat2 * lo2:
			# Between this gait at its quickest and the next at its slowest.
			var s1 := nat * len
			var c1 := len / top
			var len2: float = gait[n]["len"]
			var s2 := nat2 * len2
			var c2 := len2 / lo2
			var k := clampf((v * c1 - s1) / ((s2 - s1) - v * (c2 - c1)), 0.0, 1.0)
			w[GAITS.find(g)] = 1.0 - k
			w[GAITS.find(n)] = k
			return {"w": w, "cycle": lerpf(c1, c2, k)}
	return {"w": w, "cycle": 1.0}

# --- Every frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if tree == null or manual:
		return
	_accum += delta
	_tick += 1
	var every := 1
	if lod and body:
		every = _lod_every()
	if _tick % every != 0:
		return
	update(_accum)
	_accum = 0.0

func _lod_every() -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1
	var p := body.global_position
	var d := cam.global_position.distance_to(p)
	var every := 1 if d < 22.0 else (2 if d < 45.0 else (4 if d < 90.0 else 8))
	if d > 5.0 and not cam.is_position_in_frustum(p + Vector3.UP):
		every = maxi(every, 6)
	if ik:
		ik.feet_on = d < 28.0 and every <= 2
		ik.look_on = d < 40.0
	return every

## Advances the animation by `dt` seconds (also used to settle a pose at once).
func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_measure(dt)
	# The state, cross-faded between its two slots.
	_mix = move_toward(_mix, 1.0, dt / XFADE)
	tree.set("parameters/x/blend_amount", _mix if _slot == 1 else 1.0 - _mix)
	var ts := _state_speed * (_idle_rate if _state == "idle" else 1.0)
	if _state in OWN_MOTION:
		var nat := float(tree.get_animation(_state).get_meta("speed", 1.0))
		ts = clampf(_speed / maxf(nat, 0.05), 0.35, 2.2)
	elif _state == "swim_idle" or _state == "swim":
		ts = maxf(ts, 0.6)
	tree.set("parameters/t%d/scale" % _slot, 0.0 if _hold else ts)
	tree.set("parameters/t%d/scale" % (1 - _slot), 0.0 if _hold else ts)
	# The gait, by speed, and a shuffle of the feet when turning on the spot.
	var want := 0.0
	var v := _speed
	if locomotion and not _hold and not (_state in STILL) and not (_state in OWN_MOTION):
		want = smoothstep(0.05, 0.38, _speed)
		var turning := absf(_yaw_rate) > 1.1 and _speed < 0.3
		_turn = move_toward(_turn, 1.0 if turning else 0.0, dt * (6.0 if turning else 3.0))
		if _turn > 0.0:
			want = maxf(want, 0.7 * _turn)
			v = maxf(v, lerpf(v, 0.6, _turn))
	else:
		_turn = 0.0
	_move_w = move_toward(_move_w, want, dt * 5.0)
	tree.set("parameters/move/blend_amount", _move_w)
	if _move_w > 0.001:
		var g := solve(v, _gait)
		_phase = fposmod(_phase + dt / maxf(float(g["cycle"]), 0.05), 1.0)
		var w: Array = g["w"]
		tree.set("parameters/wj/blend_amount", clampf(w[1] + w[2], 0.0, 1.0))
		tree.set("parameters/js/blend_amount", clampf(w[2], 0.0, 1.0))
		for name in _gait:
			var e: Dictionary = _gait[name]
			tree.set("parameters/k_%s/seek_request" % name, fposmod(_phase + float(e["phase"]), 1.0) * float(e["len"]))
	# The upper-body layer.
	_umix = move_toward(_umix, 1.0, dt / XFADE)
	tree.set("parameters/ux/blend_amount", _umix if _uslot == 1 else 1.0 - _umix)
	_upper_w = move_toward(_upper_w, 1.0 if _upper != "" else 0.0, dt / XFADE)
	tree.set("parameters/up/blend_amount", _upper_w)
	if ik:
		var s := _scale()
		var vw := _speed * s
		# Bank into turns as a body must (tan = v w / g), tip with speeding up and slowing.
		var bank := atan(vw * _yaw_rate / 9.8) * 0.55 * _move_w
		var tip := atan(_accel * s / 9.8) * 0.45 * _move_w
		ik.lean = ik.lean.lerp(Vector2(clampf(-bank, -0.3, 0.3), clampf(tip, -0.15, 0.25)), clampf(dt * 6.0, 0.0, 1.0))
		ik.feet_allowed = feet_free()
	tree.advance(dt)

func _measure(dt: float) -> void:
	if body == null or not body.is_inside_tree():
		return
	var p := body.global_position
	var f := body.global_basis.z
	var yaw := atan2(f.x, f.z)
	if _last_pos == Vector3.INF:
		_last_pos = p
		_last_yaw = yaw
		return
	var raw := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / dt
	if raw > 30.0:
		raw = 0.0 # a teleport, not a run
	var v := raw / maxf(_scale(), 0.01)
	var k := clampf(dt * 9.0, 0.0, 1.0)
	var before := _speed
	_speed = lerpf(_speed, v, k)
	_accel = lerpf(_accel, (_speed - before) / dt, clampf(dt * 4.0, 0.0, 1.0))
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / dt, k)
	_last_pos = p
	_last_yaw = yaw
