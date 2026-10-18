class_name NPC
extends Node3D
## One living person: a procedurally built, animated humanoid that walks to the targets
## its mind picks. All state that matters lives in `rec`, the persisted record.

const WALK := 1.35
const RUN := 3.6
const ARRIVE := 0.7

var rec: Dictionary
var settlement: Dictionary
var manager: Node

var action := "idle"
var target := Vector2.INF
var target_player := false
var talking := false ## True while the player is in a conversation with this NPC.
var talk_here := false ## talking with you while someone else's game runs them (multiplayer)
var decide_in := 0.0
var lod_dt := 0.0 ## time saved up while NPCManager skips frames for this person
var lod_tick := 0
var think_at := 0.0
var attack_cd := 0.0
## What their trade's routine has them doing (NPCRoles.duty_at), while action is "work".
var duty: Dictionary = {}
## Someone they are chatting with stands here: they turn to face them.
var face_to := Vector2.INF
## What the body does at their work right now ("" when not at it), and what the arms do
## on the way there (a load, a torch). Streamed to players who don't run this person.
var work_anim := ""
var upper_anim := ""
## An archer or gunner holds off this far from whoever they attack (0: up close).
var keep_off := 0.0

## The way they are walking: waypoints round ground too steep to walk (WalkGrid), the one
## they head for, the goal it was planned to and when they may plan again.
var _route := PackedVector2Array()
var _route_i := 0
var _route_goal := Vector2.INF
var _route_reached := true
var _route_wait := 0.0

var _body: AnimatableBody3D
var _model: Node3D
var _human: HumanModel ## the kit character, when its assets are present
## What each job looks like while working at its spot.
## Jobs whose tool in hand (a pickaxe standing in for a hoe) belongs only in the fields,
## and the duties done there.
const FIELD_TOOL_JOBS := ["farmer", "beekeeper", "hydroponics tech"]
const FIELD_DUTIES := ["till", "harvest", "bees", "grow"]
const WORK_ANIM := {"farmer": "harvest", "smith": "fix", "guard": "sword_idle", "innkeeper": "interact",
	"hunter": "chop", "priest": "fold_arms", "weaver": "interact", "miller": "carry", "herbalist": "harvest",
	"warden": "sword_idle", "runecarver": "fix", "bard": "dance", "mystic": "spell", "beekeeper": "plant",
	"lamplighter": "torch", "scribe": "interact", "engineer": "fix", "medic": "interact", "scavenger": "pickup",
	"pilot": "interact", "security officer": "fold_arms", "data broker": "fold_arms", "hydroponics tech": "water",
	"courier": "carry", "guildmaster": "fold_arms", "archmage": "spell", "fence": "fold_arms", "steward": "interact",
	"ranger captain": "fold_arms", "archdruid": "spell", "contract broker": "fold_arms", "flight master": "fold_arms"}
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array = [] ## [hip pivot, knee pivot]
var _arms: Array = [] ## [shoulder pivot, elbow pivot]
var _label: Label3D
var _speech_t := 0.0
var _phase := 0.0
var _speed := 0.0
var _scale := 1.0
var _pace := 1.0 ## walking pace for their age and weight (BodyShape.pace)
var _hit_flash := 0.0
var _speaking := false

var perform := ""
var perform_t := 0.0
var ambient := false ## the current performance was their own idea (ends when they move on)
var _jump_y := 0.0
var _stool: Node3D
var gear_shown := ""
var boat: BoatNode = null ## the boat they crew, while aboard (NPCManager sets it)
var _deck_pose := ""
## The last act (gesture or performance) and how many so far, so players who don't run
## this person see the same (NPCManager streams them).
var last_act := ""
var acts := 0
var _seen_acts := -1

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

func setup(r: Dictionary, s: Dictionary, m: Node) -> void:
	rec = r
	settlement = s
	manager = m
	name = "NPC_" + String(r["id"])

func _ready() -> void:
	var b: Dictionary = rec["body"]
	var age := int(rec.get("age", -1))
	_scale = BodyShape.stature(b, age) if HumanModel.available() else float(b["height"])
	_pace = BodyShape.pace(b, age)
	if HumanModel.available():
		_human = HumanModel.new()
		# Scaled first: what the hands hold is sized against it (HumanModel.hold).
		_human.scale = Vector3(_scale, _scale, _scale)
		_human.build(b, int(rec["era"]), String(rec["job"]), age)
		add_child(_human)
		_model = _human
		if manager and manager.has_method("ground"):
			_human.set_ground(Callable(manager, "ground"))
	else:
		_build_model(b)
	_body = AnimatableBody3D.new()
	_body.collision_layer = 2
	_body.collision_mask = 0
	# Follow the model as it walks. With sync_to_physics on, a body under a moving parent
	# stays where it spawned, so shots aimed at the person passed straight through.
	_body.sync_to_physics = false
	_body.set_meta("npc", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8 * _scale
	cs.shape = cap
	cs.position.y = 0.9 * _scale
	_body.add_child(cs)
	add_child(_body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 26
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.no_depth_test = false
	_label.render_priority = Creature.TAG_PRIORITY
	_label.outline_render_priority = Creature.TAG_PRIORITY - 1
	Creature.crisp_tag(_label)
	_label.width = 420
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position.y = 2.05 * _scale
	_label.visible = false
	add_child(_label)
	global_position = rec["pos"]
	rotation.y = float(rec.get("yaw", 0.0))
	decide_in = randf() * 1.5
	NPCSocial.ensure(rec)
	refresh_gear()

## Whether a hit at world point `p` lands on the head (the top of the body).
func is_head(p: Vector3) -> bool:
	return p.y - global_position.y > 1.5 * _scale

## Puts on whatever the record says this person wears and holds.
func refresh_gear() -> void:
	if _human == null:
		return
	var key := str(rec.get("gear", {})) + str(rec.get("held", null))
	if key == gear_shown:
		return
	gear_shown = key
	_human.wear(rec.get("gear", {}))
	var held = rec.get("held", null)
	if held is Dictionary:
		_human.hold(Viewmodel.prop_for(held["type"], held))

## Does something: a full-body action from NPCMind.PERFORM or a gesture from BodyLanguage.
## Returns false if this person doesn't know how.
func act(what: String, seconds := 0.0) -> bool:
	what = what.strip_edges().to_lower().replace(" ", "_")
	if what == "" or what == "none":
		return false
	last_act = what
	acts += 1
	if NPCMind.PERFORM.has(what):
		var p: Array = NPCMind.PERFORM[what]
		if what == "stand":
			_end_perform()
			return true
		_end_perform()
		ambient = false
		perform = what
		perform_t = seconds if seconds > 0.0 else float(p[1])
		if _human:
			match String(p[2]):
				"once":
					_human.play_once(p[0])
				"hold":
					_human.pose(p[0])
				"sit":
					_human.play_once("sit_down")
				"jump":
					_human.play_once("jump_start" if what == "jump" else p[0])
					_jump_y = 0.0
		return true
	if _human and _human.gesture(what):
		return true
	return false

## A blow or a shot at whoever they are fighting (the hit itself is the manager's).
func strike(ranged: bool) -> void:
	last_act = "strike_r" if ranged else "strike"
	acts += 1
	if _human:
		var held = rec.get("held", null)
		var t := String(held.get("type", "")) if held is Dictionary else ""
		if ranged:
			_human.play_once("throw" if t in ["sling", "javelin", "throwing_knives"] else "pistol")
		else:
			_human.play_once(["slash_a", "slash_b", "sword"][randi() % 3] if t != "" else "punch")

func is_performing() -> bool:
	return perform != ""

func stop_perform() -> void:
	_end_perform()

func _end_perform() -> void:
	if perform == "":
		return
	var was := perform
	perform = ""
	perform_t = 0.0
	if _stool:
		_stool.queue_free()
		_stool = null
	if _human:
		_human.release()
		match was:
			"sit":
				_human.play_once("stand_up")
			"play_dead":
				_human.play_once("get_up")
	if _model:
		_model.position.y = 0.0

func _update_perform(delta: float) -> void:
	if perform == "":
		return
	perform_t -= delta
	var p: Array = NPCMind.PERFORM[perform]
	if String(p[2]) == "jump":
		# Up and down on a parabola, landing with the landing animation.
		var dur: float = p[1]
		var k := clampf(1.0 - perform_t / dur, 0.0, 1.0)
		_jump_y = sin(k * PI) * (0.55 if perform == "jump" else 0.9)
		if _model:
			_model.position.y = _jump_y
		if perform_t <= 0.0 and _human:
			_human.play_once("jump_land")
	if perform == "sit" and _human:
		if _stool == null and not _human.busy() and not (manager.has_method("bench_under") and manager.bench_under(self)):
			_stool = _make_stool()
	if perform_t <= 0.0:
		_end_perform()

## Something to sit on: people carry a stool (or a crate on the frontier).
func _make_stool() -> Node3D:
	var k := MeshKit.new(5)
	var I := Transform3D.IDENTITY
	var seat := 0.47
	if int(rec["era"]) == Eras.SCIFI:
		k.box("panel", I.translated(Vector3(0, seat * 0.5 - 0.02, 0)), Vector3(0.42, seat - 0.04, 0.42))
	else:
		# Wide enough, and the legs splayed enough, to show past a skirt.
		k.cylinder("planks", I.translated(Vector3(0, seat - 0.035, 0)), 0.23, 0.23, 0.05, 12)
		for i in 3:
			var a := TAU * i / 3.0
			k.cylinder("planks", Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), 0.22), Vector3(cos(a) * 0.17, (seat - 0.06) * 0.5, sin(a) * 0.17)), 0.028, 0.022, seat - 0.04, 6)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Materials.get_mat)
	add_child(mi)
	# Under the hips, wherever the sitting pose put them.
	var sk := _human.skeleton
	var pb := sk.find_bone("pelvis")
	if pb >= 0:
		var hips := sk.global_transform * sk.get_bone_global_pose(pb).origin
		var local := to_local(hips)
		mi.position = Vector3(local.x, 0.0, local.z - 0.04)
		mi.scale = Vector3.ONE * _scale
	return mi

func say(text: String, seconds: float = 5.0) -> void:
	if text.strip_edges() == "":
		return
	_label.text = "%s\n%s" % [rec["name"].split(" ")[0], text]
	_label.modulate = Color(1, 1, 1)
	_label.visible = true
	_speech_t = seconds
	_speaking = true
	if manager and manager.has_method("said"):
		manager.said(self, text, seconds)

func show_name(on: bool) -> void:
	if _speaking:
		return
	_label.visible = on
	if on:
		_label.text = "Lv %d  %s\n%s" % [NPCSocial.level(rec), rec["name"], rec["job"].capitalize()]
		# Like an animal's tag: guards and anyone out to hurt you show their danger.
		var danger := action == "attack" or int(rec.get("rel", 0)) <= -40
		# Opaque: the tag is cut out solid (Creature.crisp_tag), and a see-through one is
		# dithered there, which temporal anti-aliasing scrambled into a ghosted double.
		_label.modulate = Color(1.0, 0.55, 0.45) if danger else (Color(1.0, 0.85, 0.55) if NPCGen.GUARD_JOBS.has(rec["job"]) else Color(1, 1, 1))

func is_hidden() -> bool:
	return not _model.visible

## Whether the name tag is up (shown, not speech).
func name_shown() -> bool:
	return _label.visible and not _speaking

func flash_hit() -> void:
	_hit_flash = 0.25
	if _human:
		_human.play_once("hit")

# --- Movement and animation ---------------------------------------------------------------

## Called every frame by the manager. ground: Callable(x, z) -> float (NAN if unloaded).
func step(delta: float, ground: Callable, player_pos: Vector3, others: Array) -> void:
	_speech_t -= delta
	if _speaking and _speech_t <= 0.0:
		_speaking = false
		_label.visible = false
	attack_cd = maxf(0.0, attack_cd - delta)
	var pos := global_position
	var p2 := Vector2(pos.x, pos.z)
	var goal := target
	var stop_at := ARRIVE
	if target_player:
		goal = Vector2(player_pos.x, player_pos.z)
		stop_at = {"greet": 2.2, "follow": 3.0, "confront": 2.8, "attack": 1.3, "trade": 2.0}.get(action, 2.0)
		if action == "attack" and keep_off > 0.0:
			stop_at = keep_off
		elif action == "confront" and rec.has("band"):
			stop_at = 4.5
	elif rec.has("room"):
		# Shopkeepers go in and out by the door.
		goal = TownShops.route(rec["room"], p2, goal)
	var moving := false
	_update_perform(delta)
	# Doing something on the spot holds them there, unless they must run.
	if perform != "" and action in ["flee", "attack"]:
		_end_perform()
	var run := action == "flee" or action == "attack" or (action == "follow" and p2.distance_to(goal) > 8.0)
	var stay := perform != "" and perform != "zombie"
	_route_wait -= delta
	var go := not talking and not stay and goal != Vector2.INF and p2.distance_to(goal) > stop_at
	var aim := _aim(p2, goal) if go else goal
	if go and p2.distance_to(aim) > 0.05:
		var dir := (aim - p2).normalized()
		# Keep a little personal space.
		for o in others:
			if o == self:
				continue
			var op := Vector2(o.global_position.x, o.global_position.z)
			var dd := p2.distance_to(op)
			if dd < 1.1 and dd > 0.001:
				dir += (p2 - op).normalized() * (1.1 - dd) * 1.5
		dir = dir.normalized()
		var want := (RUN if run else WALK) * (0.9 + float(rec["traits"]["diligent"]) * 0.2) * _pace
		_speed = move_toward(_speed, want, delta * 4.0)
		p2 += dir * _speed * delta
		var yaw := atan2(dir.x, dir.y)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
		moving = true
	else:
		_speed = move_toward(_speed, 0.0, delta * 6.0)
		var face := INF
		if talking or (target_player and action != "flee"):
			face = atan2(player_pos.x - pos.x, player_pos.z - pos.z)
		elif face_to != Vector2.INF and p2.distance_to(face_to) < 4.0:
			face = atan2(face_to.x - pos.x, face_to.y - pos.z)
		elif action == "work" and not duty.is_empty() and at_work():
			face = float(duty.get("face", INF))
		elif action == "work" and duty.is_empty() and p2.distance_to(rec["work"]) < 1.5:
			face = float(rec.get("work_yaw", rotation.y))
		if face != INF:
			rotation.y = lerp_angle(rotation.y, face, clampf(delta * 4.0, 0.0, 1.0))
	var h: float = ground.call(p2.x, p2.y)
	if is_nan(h):
		return
	if rec.has("room") and rec["room"].has("y"):
		# On the shop's floor, not the ground under it.
		var rm: Dictionary = rec["room"]
		var lp := TownShops.to_local(rm["c"], rm["yaw"], p2)
		if absf(lp.x) < (rm["half"] as Vector2).x and absf(lp.y) < (rm["half"] as Vector2).y:
			h = maxf(h, float(rm["y"]))
	global_position = Vector3(p2.x, h, p2.y)
	rec["pos"] = global_position
	work_anim = ""
	upper_anim = ""
	if action == "work" and not talking:
		if moving:
			upper_anim = String(duty.get("upper", ""))
		elif not duty.is_empty():
			if at_work():
				work_anim = String(duty.get("anim", ""))
		elif p2.distance_to(rec["work"]) < 1.5:
			work_anim = WORK_ANIM.get(rec["job"], "interact")
	rec["yaw"] = rotation.y
	if _human and FIELD_TOOL_JOBS.has(rec["job"]):
		# The hoe comes out in the fields and nowhere else.
		_human.show_tool(action == "work" and FIELD_DUTIES.has(String(duty.get("duty", ""))))
	# Asleep indoors: invisible and intangible until morning.
	var home: Vector2 = rec["home"]
	var indoors: bool = action == "sleep" and p2.distance_to(home) < 1.2
	_model.visible = not indoors
	_body.process_mode = Node.PROCESS_MODE_DISABLED if indoors else Node.PROCESS_MODE_INHERIT
	_animate(delta, moving, run, player_pos)

## Where to head for next on the way to `goal`: straight there when nothing on the way is
## too steep, else along a route round it (planned again when the goal moves on or the
## route runs out). Where they are now when they must wait (for a route, or at the end of
## one that can't get any nearer).
func _aim(p2: Vector2, goal: Vector2) -> Vector2:
	var walk: WalkGrid = manager.get("walk") if manager else null
	if walk == null:
		return goal
	var moved := _route_goal == Vector2.INF or goal.distance_to(_route_goal) > maxf(2.0, p2.distance_to(goal) * 0.15)
	var done := _route_i >= _route.size()
	if (moved or done) and _route_wait <= 0.0:
		_route_wait = 0.4
		if walk.clear(p2, goal, WalkGrid.PERSON):
			_set_route(PackedVector2Array([goal]), goal, true)
		else:
			var r := walk.route(p2, goal, WalkGrid.PERSON)
			if not r.is_empty() and not r["reached"]:
				# No walk there: a scramble up a steep bank will do, but not a cliff.
				var up := walk.route(p2, goal, WalkGrid.SCRAMBLE)
				if not up.is_empty() and up["reached"]:
					r = up
			if not r.is_empty():
				_set_route(r["pts"], goal, r["reached"])
				if not r["reached"]:
					# Nowhere nearer to be got to: try again in a while (the way may open).
					_route_wait = 3.0
	while _route_i < _route.size() - 1 and p2.distance_to(_route[_route_i]) < 1.2:
		_route_i += 1
	if _route_i >= _route.size():
		return p2
	if _route_i < _route.size() - 1:
		return _route[_route_i]
	# The last leg: to the goal itself (it may have moved on a little since), or to the
	# nearest place to it they can get to, where they wait.
	if _route_reached:
		return goal
	if p2.distance_to(_route[_route_i]) < 0.6:
		_route_i += 1
		return p2
	return _route[_route_i]

func _set_route(pts: PackedVector2Array, goal: Vector2, reached: bool) -> void:
	_route = pts
	_route_i = 0
	_route_goal = goal
	_route_reached = reached

## Whether they have got to where their duty is done.
func at_work() -> bool:
	var t: Vector2 = duty.get("target", Vector2.INF)
	return t != Vector2.INF and Vector2(global_position.x, global_position.z).distance_to(t) < 1.5

## Aboard a boat: stays at their station on deck as the boat moves and rolls, doing
## that station's job (rowing, fishing, at the helm, mending, keeping a lookout), and
## turns to face you when you talk. Called every frame instead of step().
func deck_step(delta: float, player_pos: Vector3) -> void:
	_speech_t -= delta
	if _speaking and _speech_t <= 0.0:
		_speaking = false
		_label.visible = false
	attack_cd = maxf(0.0, attack_cd - delta)
	var i := int(rec.get("station", 0))
	var xf := boat.deck_xf(i)
	var st := boat.station(i)
	var sit := BoatModel.seated(st)
	global_position = xf.origin
	var face := xf.basis.get_euler().y
	if (talking or target_player) and not sit:
		face = atan2(player_pos.x - global_position.x, player_pos.z - global_position.z)
	rotation.y = face if _deck_pose == "" else lerp_angle(rotation.y, face, clampf(delta * 4.0, 0.0, 1.0))
	rec["yaw"] = rotation.y
	var pose := String(st.get("pose", "stand"))
	if _human == null:
		_speed = 0.0
		_animate(delta, false, false, player_pos)
		return
	if _deck_pose != pose:
		_deck_pose = pose
		if pose == "fish" and not rec.has("held"):
			_human.hold(Viewmodel.prop_for("fishing_rod", null), Vector3(0, 0.6, 1).normalized())
	_human.ik.feet_here = false
	var near := global_position.distance_to(player_pos)
	if (talking or target_player) and near < 25.0:
		_human.look_at_target(player_pos + Vector3.UP * 1.6, 1.0)
	elif pose == "lookout":
		_human.look_at_target(global_position - xf.basis.z * 60.0 + Vector3.UP * 1.5, 0.6)
	elif near < 8.0:
		_human.look_at_target(player_pos + Vector3.UP * 1.6, 0.5)
	else:
		_human.look_at_target(Vector3.INF)
	var chat := talking or _speech_t > 0.0
	if pose == "row" and _human.gestures:
		_human.gestures.row(boat.rowing > 0.5 and not chat, boat.row_offset)
	if sit:
		_human.play("sit_talk" if chat and _human.anim.has_animation("sit_talk") else "sit")
	elif chat:
		_human.play("talk")
	else:
		match pose:
			"steer":
				_human.play("interact" if int(rec["era"]) == Eras.SCIFI else "idle")
			"work":
				_human.play("fix" if int(rec["era"]) != Eras.SCIFI else "interact")
			"lookout":
				_human.play("fold_arms" if _human.anim.has_animation("fold_arms") else "idle")
			_:
				_human.play("idle")
	if _hit_flash > 0.0:
		_hit_flash -= delta
	_human.set_flash(clampf(_hit_flash * 4.0, 0.0, 1.0))

## What players who don't run this person need to draw them (read back by follow).
func net_state() -> Array:
	return [rec["id"], global_position, rotation.y, action, perform, _speed, talking, last_act, acts, attack_cd, target_player, is_hidden(), work_anim, upper_anim]

## Drawn from someone else's game (multiplayer): glides to where they say this person
## is and does what they say, instead of thinking for itself.
func follow(delta: float, st: Array, player_pos: Vector3) -> void:
	_speech_t -= delta
	if _speaking and _speech_t <= 0.0:
		_speaking = false
		_label.visible = false
	if st.size() < 12:
		_animate(delta, false, false, player_pos)
		return
	var to: Vector3 = st[1]
	global_position = to if global_position.distance_to(to) > 8.0 else global_position.lerp(to, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, float(st[2]), clampf(delta * 10.0, 0.0, 1.0))
	action = String(st[3])
	_speed = float(st[5])
	talking = bool(st[6]) or talk_here
	attack_cd = float(st[9])
	target_player = bool(st[10])
	if st.size() >= 14:
		work_anim = String(st[12])
		upper_anim = String(st[13])
	if _human and FIELD_TOOL_JOBS.has(rec["job"]):
		_human.show_tool(action == "work" and work_anim in ["plant", "harvest"])
	if _seen_acts < 0:
		_seen_acts = int(st[8]) # what they did before you came is over
	elif int(st[8]) != _seen_acts:
		_seen_acts = int(st[8])
		if String(st[7]).begins_with("strike"):
			strike(String(st[7]) == "strike_r")
		else:
			act(String(st[7]), 600.0 if String(st[4]) != "" else 0.0)
	if String(st[4]) == "" and perform != "":
		_end_perform()
	elif perform != "":
		perform_t = maxf(perform_t, 1.0) # it ends when they say so
	_update_perform(delta)
	_model.visible = not bool(st[11])
	_body.process_mode = Node.PROCESS_MODE_DISABLED if bool(st[11]) else Node.PROCESS_MODE_INHERIT
	_animate(delta, _speed > 0.05, _speed > WALK * 1.5, player_pos)

func _animate(delta: float, moving: bool, run: bool, player_pos: Vector3) -> void:
	if _human:
		_animate_human(delta, moving, run, player_pos)
		return
	var amt := clampf(_speed / WALK, 0.0, 1.6)
	_phase += delta * (_speed * 2.9 / _scale + 0.0)
	var sw := sin(_phase)
	for i in 2:
		var s := sw if i == 0 else -sw
		var leg: Array = _legs[i]
		(leg[0] as Node3D).rotation.x = s * 0.5 * amt
		(leg[1] as Node3D).rotation.x = maxf(0.0, -cos(_phase + (0.0 if i == 0 else PI))) * 0.9 * amt
		var arm: Array = _arms[i]
		(arm[0] as Node3D).rotation.x = -s * 0.42 * amt
		(arm[0] as Node3D).rotation.z = (0.08 if i == 0 else -0.08)
		(arm[1] as Node3D).rotation.x = -0.25 - (0.5 if run else 0.0) * amt
	# Idle breathing, talk gestures and the walk bob.
	var t := Time.get_ticks_msec() / 1000.0 + float(rec["traits"]["curious"]) * 10.0
	_torso.scale = Vector3(1.0, 1.0 + sin(t * 1.6) * 0.012, 1.0)
	_hips.position.y = 0.95 + absf(cos(_phase)) * 0.035 * amt
	if (_speech_t > 0.0 or talking) and not moving:
		(_arms[0][0] as Node3D).rotation.x = -0.35 + sin(t * 3.0) * 0.18
		(_arms[0][1] as Node3D).rotation.x = -1.0 + sin(t * 4.2) * 0.25
	if action == "attack" and attack_cd > 0.8:
		(_arms[0][0] as Node3D).rotation.x = -2.2
	# Look at the player when close.
	var to_p := player_pos - global_position
	var look := 0.0
	if to_p.length() < 9.0 and action != "flee":
		look = clampf(wrapf(atan2(to_p.x, to_p.z) - rotation.y, -PI, PI), -1.1, 1.1)
	_head.rotation.y = lerpf(_head.rotation.y, look, clampf(delta * 5.0, 0.0, 1.0))
	if _hit_flash > 0.0:
		_hit_flash -= delta
		_model.position.x = sin(_hit_flash * 80.0) * 0.04
	else:
		_model.position.x = 0.0

func _animate_human(delta: float, moving: bool, run: bool, player_pos: Vector3) -> void:
	# Eyes on you when talking to you or coming for you; a curious look when you pass close.
	var near := global_position.distance_to(player_pos)
	if action != "flee" and (talking or target_player) and near < 25.0:
		_human.look_at_target(player_pos + Vector3.UP * 1.6, 1.0)
	elif action != "flee" and near < 6.0 and perform == "":
		_human.look_at_target(player_pos + Vector3.UP * 1.6, 0.55)
	else:
		_human.look_at_target(Vector3.INF)
	# Shop floors aren't the ground under them.
	_human.ik.feet_here = not rec.has("room") and boat == null
	var up := upper_anim if moving else ""
	if moving and (NPCGen.GUARD_JOBS.has(rec["job"]) or rec.has("band")) and action in ["confront", "attack"]:
		up = "pistol_idle" if keep_off > 0.0 else "sword_idle"
	_human.set_upper(up)
	# Day visitors standing about (MarketCrowd) are a background crowd: animated a little
	# less often unless you are close.
	_human.animator.calm = rec.has("visit") and not moving and not talking and _speech_t <= 0.0 and (perform == "" or perform == "sit")
	if action == "attack" and attack_cd > 1.3 and not rec.has("band"):
		_human.play_once("sword" if NPCGen.GUARD_JOBS.has(rec["job"]) else "punch")
	if perform != "":
		var p: Array = NPCMind.PERFORM[perform]
		if perform == "zombie" and moving:
			_human.play("zombie_walk", clampf(_speed / WALK, 0.5, 1.2))
		elif String(p[2]) in ["loop", "sit"]:
			_human.play(p[0])
		elif String(p[2]) == "jump" and not _human.busy():
			_human.play("jump_air")
		elif String(p[2]) == "once" and not _human.busy():
			perform_t = minf(perform_t, 0.05)
		if _hit_flash > 0.0:
			_hit_flash -= delta
		_human.set_flash(clampf(_hit_flash * 4.0, 0.0, 1.0))
		return
	if moving:
		if run:
			_human.play("sprint" if action == "flee" else "jog", clampf(_speed / RUN, 0.5, 1.4))
		else:
			_human.play("walk", clampf(_speed / WALK, 0.5, 1.5))
	elif talking or _speech_t > 0.0:
		_human.play("talk")
	elif work_anim != "":
		_human.play(work_anim)
	elif action == "socialize" and face_to != Vector2.INF and Vector2(global_position.x, global_position.z).distance_to(face_to) < 2.5:
		# Chatting with a neighbour: they take turns to talk.
		_human.play("talk" if (int(Time.get_ticks_msec() / 3500) + absi(hash(String(rec["id"])))) % 2 == 0 else "idle")
	elif action in ["confront", "attack"]:
		if rec.has("band"):
			_human.play("pistol_idle" if keep_off > 0.0 else "sword_idle")
		else:
			_human.play("sword_idle" if NPCGen.GUARD_JOBS.has(rec["job"]) else "fold_arms")
	else:
		_human.play("idle")
	if _hit_flash > 0.0:
		_hit_flash -= delta
	_human.set_flash(clampf(_hit_flash * 4.0, 0.0, 1.0))

# --- Procedural model -------------------------------------------------------------------------

static func _mat(c: Color, rough: float = 0.85, skin: bool = false, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%s_%.1f" % [c.to_html(), rough, skin, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if skin:
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.35
		m.rim_enabled = true
		m.rim = 0.15
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

static func _capsule(r: float, h: float) -> Mesh:
	var key := "cap%.3f_%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 12
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]

static func _sphere(r: float, hemi: bool = false) -> Mesh:
	var key := "sph%.3f_%s" % [r, hemi]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.is_hemisphere = hemi
		m.radial_segments = 16
		m.rings = 8
		_meshes[key] = m
	return _meshes[key]

static func _box(s: Vector3) -> Mesh:
	var key := "box%s" % s
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = s
		_meshes[key] = m
	return _meshes[key]

static func _cyl(top: float, bottom: float, h: float) -> Mesh:
	var key := "cyl%.3f_%.3f_%.3f" % [top, bottom, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = 14
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

func _build_model(b: Dictionary) -> void:
	var era: int = rec["era"]
	var job: String = rec["job"]
	var w: float = b["build"]
	var fem: bool = b["female"]
	var skin := _mat(b["skin"], 0.55, true)
	var cloth := _mat(b["cloth"], 0.92)
	var cloth2 := _mat(b["cloth2"], 0.9)
	var hair := _mat(b["hair"], 0.7)
	var dark := _mat(Color(0.12, 0.1, 0.09), 0.8)
	var boots := _mat(Color(0.22, 0.15, 0.1) if era != Eras.SCIFI else Color(0.15, 0.16, 0.18), 0.6)
	var accent := _mat(Color(0.3, 0.9, 1.0) if era == Eras.SCIFI else Color(0.4, 1.0, 0.7), 0.4, false, 2.5)
	_model = Node3D.new()
	_model.scale = Vector3(_scale, _scale, _scale)
	add_child(_model)
	_hips = Node3D.new()
	_hips.position.y = 0.95
	_model.add_child(_hips)
	var sw := 0.105 * w
	# Legs: hip pivot -> thigh, knee pivot -> shin and boot.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := Node3D.new()
		hip.position = Vector3(side * sw * 0.9, -0.02, 0)
		_hips.add_child(hip)
		_part(hip, _capsule(0.075 * w, 0.48), cloth2, Vector3(0, -0.22, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.45, 0)
		hip.add_child(knee)
		_part(knee, _capsule(0.06 * w, 0.46), cloth2 if era != Eras.MEDIEVAL else boots, Vector3(0, -0.22, 0))
		_part(knee, _box(Vector3(0.1, 0.07, 0.24)), boots, Vector3(0, -0.46, 0.05))
		_legs.append([hip, knee])
	# Torso.
	_torso = Node3D.new()
	_hips.add_child(_torso)
	var chest_w := (0.17 if fem else 0.19) * w
	_part(_torso, _capsule(chest_w, 0.62), cloth, Vector3(0, 0.27, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.68))
	_part(_torso, _cyl(0.15 * w, 0.16 * w, 0.08), dark, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.75))
	# Skirt, robe or long coat depending on era and job.
	if era == Eras.FANTASY or (fem and era == Eras.MEDIEVAL) or job in ["priest", "mystic", "scribe"]:
		_part(_torso, _cyl(0.17 * w, 0.27 * w, 0.62), cloth, Vector3(0, -0.3, 0), Vector3.ZERO, Vector3(1, 1, 0.85))
	if era == Eras.SCIFI:
		_part(_torso, _box(Vector3(0.04, 0.3, 0.01)), accent, Vector3(chest_w * 0.5, 0.32, chest_w * 0.68))
		_part(_torso, _box(Vector3(0.18 * w, 0.06, 0.16)), _mat(Color(0.35, 0.37, 0.4), 0.4), Vector3(-0.19 * w, 0.55, 0))
		_part(_torso, _box(Vector3(0.18 * w, 0.06, 0.16)), _mat(Color(0.35, 0.37, 0.4), 0.4), Vector3(0.19 * w, 0.55, 0))
	elif era == Eras.FANTASY:
		_part(_torso, _sphere(0.025), accent, Vector3(0, 0.42, chest_w * 0.66))
	if job == "smith" or job == "trader":
		_part(_torso, _box(Vector3(0.3 * w, 0.5, 0.02)), _mat(Color(0.35, 0.25, 0.16), 0.7), Vector3(0, 0.12, chest_w * 0.7))
	# Arms.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sh := Node3D.new()
		sh.position = Vector3(side * (chest_w + 0.04), 0.52, 0)
		_torso.add_child(sh)
		_part(sh, _capsule(0.055 * w, 0.32), cloth, Vector3(0, -0.15, 0))
		var el := Node3D.new()
		el.position = Vector3(0, -0.3, 0)
		sh.add_child(el)
		_part(el, _capsule(0.045 * w, 0.29), cloth if era == Eras.SCIFI else skin, Vector3(0, -0.13, 0))
		_part(el, _sphere(0.05), skin, Vector3(0, -0.3, 0.01), Vector3.ZERO, Vector3(0.8, 1.1, 0.6))
		_arms.append([sh, el])
	# Neck and head.
	_part(_torso, _cyl(0.045, 0.055, 0.12), skin, Vector3(0, 0.66, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.72, 0)
	_torso.add_child(_head)
	var hr := 0.105 if fem else 0.112
	_part(_head, _sphere(hr), skin, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.88, 1.08, 0.98))
	# Face: brow, eyes, nose, mouth.
	var eye := _mat(Color(0.95, 0.95, 0.93), 0.3)
	var iris := _mat(Color(0.12, 0.09, 0.07), 0.2)
	for sx in [-0.035, 0.035]:
		_part(_head, _sphere(0.016), eye, Vector3(sx, 0.125, hr * 0.86))
		_part(_head, _sphere(0.008), iris, Vector3(sx, 0.125, hr * 0.86 + 0.012))
		_part(_head, _box(Vector3(0.035, 0.008, 0.012)), hair, Vector3(sx, 0.155, hr * 0.88))
	_part(_head, _box(Vector3(0.022, 0.045, 0.03)), skin, Vector3(0, 0.095, hr * 0.92))
	_part(_head, _box(Vector3(0.04, 0.006, 0.01)), _mat(Color(0.45, 0.22, 0.2), 0.6), Vector3(0, 0.055, hr * 0.86))
	for sx in [-1.0, 1.0]:
		_part(_head, _sphere(0.022), skin, Vector3(sx * hr * 0.86, 0.11, 0), Vector3.ZERO, Vector3(0.5, 1, 0.8))
	# Hair or headgear.
	var guard: bool = NPCGen.GUARD_JOBS.has(job)
	if guard:
		var metal := _mat(Color(0.55, 0.56, 0.58) if era != Eras.FANTASY else Color(0.35, 0.5, 0.45), 0.35)
		_part(_head, _sphere(hr * 1.12, true), metal, Vector3(0, 0.13, -0.005))
		metal.metallic = 0.8
	else:
		match int(b["hair_style"]):
			0:
				_part(_head, _sphere(hr * 1.05, true), hair, Vector3(0, 0.12, -0.01), Vector3(-0.15, 0, 0))
			1:
				_part(_head, _sphere(hr * 1.06, true), hair, Vector3(0, 0.12, -0.01), Vector3(-0.15, 0, 0))
				_part(_head, _box(Vector3(hr * 1.8, 0.24, 0.06)), hair, Vector3(0, 0.02, -hr * 0.8))
			2:
				_part(_head, _sphere(hr * 1.05, true), hair, Vector3(0, 0.12, -0.01), Vector3(-0.15, 0, 0))
				_part(_head, _capsule(0.035, 0.2), hair, Vector3(0, 0.02, -hr * 1.05), Vector3(0.3, 0, 0))
			3:
				pass # Bald.
		if era == Eras.MEDIEVAL and job in ["farmer", "hunter", "miller"]:
			_part(_head, _cyl(0.07, 0.1, 0.08), _mat(Color(0.65, 0.55, 0.3), 0.9), Vector3(0, 0.23, 0))
			_part(_head, _cyl(0.2, 0.2, 0.01), _mat(Color(0.65, 0.55, 0.3), 0.9), Vector3(0, 0.19, 0))
		elif era == Eras.FANTASY and job in ["mystic", "warden", "herbalist"]:
			_part(_head, _cyl(0.0, 0.13, 0.26), cloth2, Vector3(0, 0.3, -0.02), Vector3(-0.2, 0, 0))
		if not fem and int(b["hair_style"]) % 2 == 1 and era != Eras.SCIFI:
			_part(_head, _sphere(0.07), hair, Vector3(0, 0.03, hr * 0.62), Vector3.ZERO, Vector3(1.1, 0.9, 0.6))
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
