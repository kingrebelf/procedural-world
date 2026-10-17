class_name Player
extends CharacterBody3D
## First- or third-person controller with tool use. Everything the player changes goes through
## ChunkNode/ChunkStreamer/Game so it is persisted.

signal look_target_changed(text: String)
signal selected_changed(slot: int)
signal used_tool(kind: String)
signal look_info_changed(info: Dictionary)

const WALK := 4.5
const SPRINT := 8.0
const CROUCH := 2.2
const JUMP := 5.2
const ACCEL := 10.0
const AIR_ACCEL := 2.5
const REACH := 3.2
const STAND_H := 1.75
const CROUCH_H := 1.15
const SWIM := 3.0
const BREATH := 30.0

var streamer: ChunkStreamer
var npcs: NPCManager
var fauna: FaunaManager
var corpses: Corpses
var vehicles: VehicleManager
var dungeons: Dungeons
## The vehicle you are riding, or null.
var vehicle: Vehicle = null
var pending_ride := -1 ## vehicle id to get back on once it loads (from a save)
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var gunplay: Gunplay ## magazines, aiming, recoil and flying shots for ranged weapons
var traps: Traps ## bear traps and tripwires you have set
var _trigger_held := false ## semi-automatic weapons wait for the trigger to come back
var hand_light: HandLight ## torch or flashlight in the off hand
var jetpack: Jetpack
var ray: RayCast3D
var builder: Builder
var wiring: Wiring
## Console cheats: fly (with optional noclip) and a movement speed multiplier.
var fly := false
var noclip := false
var speed_mult := 1.0
var snap_down := false ## Put the player on the ground once it loads (after a teleport).
var selected := 0
var frozen := true ## Until the ground under us is loaded.
var ui_open := false
var keep_crouch := false ## stay crouched behind an open UI (picking a lock)

var _yaw := 0.0
var _pitch := 0.0
var _eye := STAND_H - 0.12 ## eye height, eased as you crouch and stand
var bob := HeadBob.new()
var _cooldown := 0.0
var _rest := 0.0 ## seconds since stamina was last used; it refills after a short pause
var winded := false ## ran dry: no sprinting until stamina is back to a third
var _crouched := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _shape: CollisionShape3D
var _last_look := ""
var _last_info := ""
var _fall_from := 0.0
var swimming := false
var underwater := false
var breath := BREATH
var _drown_t := 0.0
var steps := Footsteps.new()
var swim := Swim.new()
## Your character: one body for third person (and your shadow in first person), and the
## arms in the viewmodel for first person. V toggles the camera.
const LOOK := {"female": false, "hair": Color(0.22, 0.14, 0.08), "hair_style": 1, "skin": Color(0.86, 0.66, 0.52),
	"cloth": Color(0.36, 0.42, 0.3), "cloth2": Color(0.28, 0.23, 0.18), "height": 1.0, "build": 0.5}
const BOOM := 3.2
var third_person := false
var body: HumanModel
var _arm: SpringArm3D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.6
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = STAND_H
	_shape.shape = cap
	_shape.position.y = STAND_H * 0.5
	add_child(_shape)
	head = Node3D.new()
	head.position.y = STAND_H - 0.12
	add_child(head)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.2
	_arm.spring_length = 0.0
	_arm.add_excluded_object(get_rid())
	head.add_child(_arm)
	camera = Camera3D.new()
	camera.near = 0.05
	# Far enough for the distant land (FarLand) to fade into the haze, not be cut off.
	camera.far = 6000.0
	camera.current = true
	_arm.add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	ray.add_exception(self)
	camera.add_child(ray)
	viewmodel = Viewmodel.new()
	viewmodel.look = Net.my_look()
	camera.add_child(viewmodel)
	hand_light = HandLight.new()
	camera.add_child(hand_light)
	gunplay = Gunplay.new()
	gunplay.player = self
	add_child(gunplay)
	add_child(ImpactFx.new())
	gunplay.gun_event.connect(_gun_sound)
	traps = Traps.new()
	traps.player = self
	add_child(traps)
	traps.sprung.connect(func(blast: bool, at: Vector3): Audio.play_at("weapon/explosion" if blast else "hit/metal", at, 2.0))
	if HumanModel.available():
		body = HumanModel.new()
		body.build(Net.my_look(), Eras.MEDIEVAL, "")
		body.rotation.y = PI
		add_child(body)
		body.set_ground(Callable(), [get_rid()])
		# The armour you wear shows on your body (third person, and your shadow).
		body.wear(Game.equipment)
		Game.equipment_changed.connect(func(): body.wear(Game.equipment))
	jetpack = Jetpack.new()
	add_child(jetpack)
	_apply_view()
	builder = Builder.new()
	builder.player = self
	add_child(builder)
	wiring = Wiring.new()
	wiring.player = self
	add_child(wiring)
	Settings.changed.connect(_apply_settings)
	Game.inventory.changed.connect(_refresh_held)
	_apply_settings()
	_refresh_held()

func _apply_settings() -> void:
	camera.fov = Settings.vertical_fov(float(Settings.get_value("fov")))

func get_state() -> Dictionary:
	# The world saves from its own _exit_tree, after the player has already left the
	# tree; the player is a direct child of the (untransformed) world, so position is
	# the world position.
	var pos := global_position if is_inside_tree() else position
	return {"pos": pos, "yaw": _yaw, "pitch": _pitch, "slot": selected, "view": 3 if third_person else 1,
		"riding": int(vehicle.rec["id"]) if vehicle != null and is_instance_valid(vehicle) else -1,
		"light": hand_light.to_data() if hand_light else {}, "traps": traps.to_data() if traps else []}

func set_state(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	_yaw = d.get("yaw", 0.0)
	_pitch = d.get("pitch", 0.0)
	select(d.get("slot", 0))
	if int(d.get("view", 1)) == 3 and not third_person:
		toggle_view()
	pending_ride = int(d.get("riding", -1))
	if hand_light:
		hand_light.from_data(d.get("light", {}))
	if traps:
		traps.from_data(d.get("traps", []))
	_apply_look()
	if d.get("drop", false):
		# Just through a portal: drop onto the ground once it has streamed in.
		teleport_to(global_position.x, global_position.z)

## Sends you to a spot on this world: you drop in from above once the ground there has
## streamed in (the same path the console's tp uses).
func teleport_to(x: float, z: float) -> void:
	if vehicle != null:
		dismount()
	global_position = Vector3(x, 200.0, z)
	velocity = Vector3.ZERO
	frozen = true
	snap_down = not fly

func yaw() -> float:
	return _yaw

func select(i: int) -> void:
	var was := selected
	selected = clampi(i, 0, Inventory.HOTBAR - 1)
	_refresh_held()
	var it = held_item()
	if was != selected and it != null and ItemDB.def(it["type"]).get("kind", "") == "weapon":
		Audio.play("weapon/draw", -10.0)
	selected_changed.emit(selected)

func held_item():
	return Game.inventory.get_slot(selected)

func _refresh_held() -> void:
	var it = held_item()
	var t: String = it["type"] if it != null else ""
	viewmodel.show_item(t, it)
	if hand_light:
		hand_light.set_held(t, Game.inventory)
	if body:
		body.hold(Viewmodel.prop_for(t, it) if t != "" else null)
		body.set_shadow_only(not third_person)

func toggle_view() -> void:
	third_person = not third_person
	_apply_view()

func _apply_view() -> void:
	# Riding pulls the third-person camera back and up to see the whole vehicle.
	var boom := BOOM
	var arm_at := Vector3(0.55, 0.2, 0.0)
	if vehicle != null and is_instance_valid(vehicle):
		boom = BOOM + float(vehicle.p["length"]) * 1.1
		arm_at = Vector3(0.0, 0.7, 0.0)
	_arm.spring_length = boom if third_person else 0.0
	_arm.position = arm_at if third_person else Vector3.ZERO
	ray.target_position = Vector3(0, 0, -(REACH + (boom if third_person else 0.0)))
	viewmodel.visible = not third_person and vehicle == null
	if hand_light:
		hand_light.show_model = not third_person and vehicle == null
		hand_light._apply()
	if body:
		body.set_shadow_only(not third_person)
	if jetpack:
		jetpack.set_shadow_only(not third_person)

## Body animation from what the controller is doing; swings come from use_held.
func _animate_body(hspeed: float) -> void:
	if body == null:
		return
	var t: String = _held_type()
	var ready := "pistol_idle" if t != "" and Viewmodel.pointed(t) else ("sword_idle" if t.begins_with("sword") else "")
	# The gait and its pace follow how fast you really move; a weapon stays raised on the run.
	if swimming:
		body.play("swim" if hspeed > 0.5 else "swim_idle")
		body.set_upper("")
	elif _crouched:
		body.play("crouch_walk" if hspeed > 0.3 else "crouch")
		body.set_upper(ready if hspeed > 0.3 else "")
	elif hspeed > 0.4:
		body.play("sprint" if hspeed > WALK + 1.0 else "jog")
		body.set_upper(ready)
	else:
		body.play(ready if ready != "" else "idle")
		body.set_upper("")
	_grip_body()

func _held_type() -> String:
	var it = held_item()
	return it["type"] if it != null else ""

## Third person: guns point where you face; tools are carried angled down and forward
## between swings, and left in the natural grip while a swing plays.
func _grip_body() -> void:
	if not third_person:
		return
	var t := _held_type()
	if t == "":
		return
	var up := global_transform.basis.y
	var fwd := -global_transform.basis.z
	if Viewmodel.pointed(t):
		body.reaim(body.hand_space(up), 0.0, body.hand_space(fwd))
	elif body.busy():
		body.aim_handle(Vector3.ZERO)
	else:
		body.aim_handle(fwd * 0.55 - up * 0.8, 0.75)

static func swing_anim(t: String) -> String:
	if t == "":
		return "punch"
	var d := ItemDB.def(t)
	if Viewmodel.pointed(t):
		return "pistol"
	if t.begins_with("sword"):
		return "sword"
	if d.get("kind", "") == "tool":
		return "chop"
	return "interact"

## Holding the pick button (LB) turns these into direct hotbar picks, in ARK's order:
## Y, B, X, A, D-pad left, right, up, down for slots 1 to 8.
const PICK_BUTTONS := [JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_A,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]

func _input(event: InputEvent) -> void:
	if ui_open or not (event is InputEventJoypadButton) or event.is_action("hotbar_pick"):
		return
	if Input.is_action_pressed("hotbar_pick"):
		if event.pressed:
			var i := PICK_BUTTONS.find(event.button_index)
			if i >= 0:
				select(i)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Slower when looking through sights or binoculars, so aim stays steady.
		var s := float(Settings.get_value("mouse_sensitivity")) * 0.01 / (gunplay.zoom() if gunplay else 1.0)
		_yaw -= event.relative.x * s
		var dy: float = event.relative.y * s * (-1.0 if Settings.get_value("invert_y") else 1.0)
		_pitch = clampf(_pitch - dy, -1.5, 1.5)
		if gunplay:
			gunplay.on_look(-dy)
		_apply_look()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % Inventory.HOTBAR)
	if event.is_action_pressed("hotbar_prev"):
		select((selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR)
	elif event.is_action_pressed("hotbar_next"):
		select((selected + 1) % Inventory.HOTBAR)
	for i in Inventory.HOTBAR:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select(i)
	if event.is_action_pressed("interact"):
		if vehicle != null:
			dismount()
		elif focus.get("kind", "") in ["built", "station", "vehicle", "carcass"] or (focus.get("kind", "") in ["door", "power"] and focus.get("own", false) and not sneaking()):
			# Your own pieces and vehicles: tap to use (a station) or ride (a vehicle),
			# hold to take the piece down or pack the vehicle up. Carcasses: hold to butcher.
			_decon_on = {"key": _focus_key(focus), "kind": focus["kind"]}
			if focus["kind"] == "carcass" and corpses:
				_decon_on["time"] = corpses.butcher_time(focus["body"], held_item())
				if body:
					body.play_once("harvest")
			decon = 0.0
		else:
			interact()
	if event.is_action_pressed("toggle_view"):
		toggle_view()
	if event.is_action_pressed("eat"):
		eat()
	if event.is_action_pressed("light"):
		Game.toast.emit(hand_light.toggle(Game.inventory))

func _apply_look() -> void:
	rotation = Vector3(0, _yaw, 0)
	if head:
		head.rotation = Vector3(_pitch + bob.tilt.x, 0, bob.tilt.z)

func _physics_process(delta: float) -> void:
	if frozen:
		if streamer != null and streamer.is_ready_at(global_position):
			frozen = false
			_snap_to_ground()
		else:
			return
	_cooldown = maxf(0.0, _cooldown - delta)
	if Game.health < Game.max_health() and Game.health > 0.0 and Game.wearing_affix("mending"):
		Game.set_health(Game.health + delta * 0.8)
	var lmsg := hand_light.tick(delta, Game.inventory)
	if lmsg != "":
		Game.toast.emit(lmsg)
	_tick_fishing(delta)
	_update_nightsight()
	if not ui_open:
		# Controller look: right stick, with a response curve for fine aim near centre.
		var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lv.length() > 0.0:
			var k := float(Settings.get_value("stick_sensitivity")) * delta * lv.length()
			_yaw -= lv.x * k
			_pitch = clampf(_pitch - lv.y * k * (-1.0 if Settings.get_value("invert_y") else 1.0), -1.5, 1.5)
			_apply_look()
	if pending_ride >= 0 and vehicles:
		var v := vehicles.by_id(pending_ride)
		pending_ride = -1
		if v:
			mount(v)
	if vehicle != null:
		_ride(delta)
		return
	var input := Vector2.ZERO
	if not ui_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_crouched = Input.is_action_pressed("crouch") if not ui_open else (_crouched and keep_crouch)
	var cap := _shape.shape as CapsuleShape3D
	var target_h := CROUCH_H if _crouched else STAND_H
	cap.height = move_toward(cap.height, target_h, delta * 4.0)
	_shape.position.y = cap.height * 0.5
	var pack := load_mult()
	var sprinting := not _crouched and not winded and pack >= 1.0 and Input.is_action_pressed("sprint") and input.y < 0 and not fly
	var speed := (CROUCH if _crouched else (SPRINT if sprinting else WALK)) * speed_mult * Game.stats.speed_mult() * pack
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var jumped := false
	var landed_vy := 0.0

	# Water: swim (Swim) once it is chest-deep; wade below that.
	var t_water := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var surface := Water.surface_height(global_position.x, global_position.z, t_water)
	swimming = surface - global_position.y > 1.15
	underwater = camera.global_position.y < Water.surface_height(camera.global_position.x, camera.global_position.z, t_water) - 0.05
	if fly:
		# Free flight where you look; jump rises, crouch sinks, sprint is four times faster.
		var up := 0.0
		if not ui_open:
			up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
		var look := camera.global_transform.basis * Vector3(input.x, 0, input.y)
		var fs := 12.0 * speed_mult * (4.0 if Input.is_action_pressed("sprint") else 1.0)
		velocity = velocity.lerp((look + Vector3.UP * up).limit_length(1.0) * fs, clampf(8.0 * delta, 0.0, 1.0))
		_shape.disabled = noclip
		move_and_slide()
	elif swimming:
		swim.step(self, delta, input, surface)
	else:
		var jump_ok := not ui_open and not Input.is_action_pressed("hotbar_pick")
		var lift := jetpack.thrust(delta, jump_ok and Input.is_action_pressed("jump"), jump_ok and Input.is_action_just_pressed("jump"),
			is_on_floor(), velocity.y, Game.inventory)
		# Steering is much better under thrust than in a plain fall.
		var a := ACCEL if is_on_floor() else (AIR_ACCEL * 2.4 if jetpack.firing else AIR_ACCEL)
		# Wading: deeper water slows you, and a river's current leans on you.
		var wet := surface - global_position.y
		var push := Vector3.ZERO
		if wet > 0.05:
			var cur := Water.current(global_position.x, global_position.z) * Swim.wade_push(wet)
			push = Vector3(cur.x, 0.0, cur.y)
		hv = hv.lerp(dir * speed * Swim.wade(wet) + push, clampf(a * delta, 0.0, 1.0))
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor():
			if jump_ok and Input.is_action_just_pressed("jump") and _tire(8.0):
				velocity.y = JUMP
				jumped = true
		else:
			velocity.y += (lift - _gravity) * delta
		var was_air := not is_on_floor()
		var vy := velocity.y
		move_and_slide()
		if was_air and is_on_floor():
			landed_vy = -vy
		if jetpack.firing:
			Audio.hold_loop("jetpack", 0.7)
		if was_air and is_on_floor() and vy < -11.0:
			Game.set_health(Game.health - (absf(vy) - 11.0) * 6.0, "You fell to your death")
	if not fly:
		swim.effects(self, delta, surface, swimming, underwater)
	# Stamina: sprinting drains it; it refills after a moment's rest.
	if sprinting and hv.length() > 1.0 and not swimming:
		_tire(13.0 * delta)
	_rest += delta
	if _rest > 0.8:
		Game.set_stamina(Game.stamina + 22.0 * delta * Game.stats.stamina_regen_mult())
	if winded and Game.stamina >= Game.max_stamina() * 0.33:
		winded = false
	# Breath.
	if underwater:
		breath = maxf(0.0, breath - delta)
		if breath <= 0.0:
			_drown_t -= delta
			if _drown_t <= 0.0:
				_drown_t = 1.0
				Game.set_health(Game.health - 8.0, "You drowned")
				Game.toast.emit("Drowning!")
	else:
		breath = minf(Game.stats.max_breath(), breath + delta * 6.0)
	# Safety net: never fall through the world.
	if global_position.y < -200.0:
		_snap_to_ground()

	# Camera height, and how the eye moves as you walk, land and strafe (HeadBob).
	_eye = lerpf(_eye, cap.height - 0.12, clampf(delta * 12.0, 0.0, 1.0))
	if third_person or fly:
		bob.reset()
	else:
		var k := float(Settings.get_value("head_bob_strength")) if Settings.get_value("head_bob") else 0.0
		bob.step(delta, k, steps.gait(), hv.length() / WALK, is_on_floor() and not swimming, _crouched, input.x, landed_vy, gunplay.ads)
	head.position = Vector3(0, _eye, 0) + bob.offset
	_apply_look()
	viewmodel.ads = gunplay.ads
	viewmodel.raise = _zoom
	# What the crosshair is on, when it is within arm's length: the held item rests
	# against it rather than sinking in.
	var touch := ray.is_colliding() and ray.get_collision_point().distance_to(camera.global_position) < 1.4
	viewmodel.near = {"point": ray.get_collision_point(), "normal": ray.get_collision_normal()} if touch else {}
	viewmodel.sway(delta, hv.length() / SPRINT)
	if not fly:
		steps.tick(self, delta, Vector2(velocity.x, velocity.z).length(), is_on_floor(), _crouched, landed_vy, jumped)
	_animate_body(Vector2(velocity.x, velocity.z).length())

	var looking := not ui_open and Input.is_action_pressed("use") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.using_pad)
	if not Input.is_action_pressed("use"):
		_trigger_held = false
	_binoculars(delta, looking and _holding_binoculars())
	if looking and _cooldown <= 0.0 and not _holding_binoculars():
		use_held()
	builder.update()
	wiring.update()
	_update_look_target()
	_update_focus(delta)
	_update_decon(delta)

func _snap_to_ground() -> void:
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(global_position)) if streamer else null
	if c == null:
		return
	var lx := global_position.x - c.key.x * ChunkGenerator.SIZE
	var lz := global_position.z - c.key.y * ChunkGenerator.SIZE
	var h := ChunkGenerator.height_at(c.data, lx, lz)
	if global_position.y < h + 0.1 or snap_down:
		snap_down = false
		global_position.y = h + 0.5
		velocity = Vector3.ZERO

# --- Interaction ---------------------------------------------------------------

func _hit_object() -> Dictionary:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var col := ray.get_collider()
	var out := {"point": ray.get_collision_point(), "normal": ray.get_collision_normal(), "collider": col}
	if col and col.has_meta("npc"):
		out["npc"] = col.get_meta("npc")
	if col and col.has_meta("vehicle"):
		out["vehicle"] = col.get_meta("vehicle")
	if col and col.has_meta("creature"):
		out["creature"] = col.get_meta("creature")
	if col and col.has_meta("remote_player"):
		out["rplayer"] = int(col.get_meta("remote_player"))
	if col and col.has_meta("chunk"):
		out["chunk"] = col.get_meta("chunk")
		if col.has_meta("obj"):
			out["obj"] = col.get_meta("obj")
	return out

static func _key(action: String) -> String:
	return Bindings.key_name(action, Game.using_pad)

# --- Interaction focus ------------------------------------------------------------
## What Interact acts on: the nearest usable thing in front of you, not only what the
## crosshair is exactly on. The HUD floats a key prompt over it.

const USE_RANGE := 3.6
var focus: Dictionary = {}
var _focus_t := 0.0

func _update_focus(delta: float) -> void:
	_focus_t -= delta
	if _focus_t > 0.0:
		return
	_focus_t = 0.1
	focus = {} if ui_open or builder.active() else _find_focus()

## Lower is better; INF when out of reach or behind you.
func _focus_score(eye: Vector3, fwd: Vector3, at: Vector3) -> float:
	var to := at - eye
	var d := to.length()
	if d > USE_RANGE + 0.8 or d < 0.01:
		return INF
	var a := fwd.angle_to(to / d)
	if a > 0.95:
		return INF
	return d + a * 4.0

func _find_focus() -> Dictionary:
	var eye := head.global_position
	var fwd := -camera.global_transform.basis.z
	var best := {}
	var best_s := INF
	if npcs:
		for n in npcs.all_nodes():
			if not is_instance_valid(n) or n.rec.get("dead", false):
				continue
			var sc := _focus_score(eye, fwd, n.global_position + Vector3(0, 1.3, 0))
			if sc < best_s:
				best_s = sc
				var first: String = n.rec["name"].split(" ")[0]
				best = {"kind": "npc", "npc": n, "pos": n.global_position + Vector3(0, 2.1, 0),
					"verb": ("Pick %s's pocket" % first) if sneaking() and not n.talking else "Talk to %s" % first}
	if vehicles:
		for v in vehicles.all_nodes():
			var sc := _focus_score(eye, fwd, v.global_position + Vector3(0, v.height * 0.5, 0))
			if sc < best_s:
				best_s = sc
				best = {"kind": "vehicle", "vehicle": v, "pos": v.global_position + Vector3(0, v.height + 0.35, 0),
					"verb": "Ride the %s   (hold: pack up)" % Vehicle.label(v.kind).to_lower()}
	if corpses:
		# Carcasses to butcher and bodies to search.
		for b in corpses.near(global_position, USE_RANGE + 2.5):
			var sc := _focus_score(eye, fwd, b["pos"] + Vector3(0, 0.4, 0))
			if sc < best_s:
				best_s = sc
				var u := Corpses.use_of(b["rec"])
				best = {"kind": u[0], "body": b["key"], "pos": b["pos"] + Vector3(0, 1.0, 0), "verb": u[1]}
	if streamer:
		var ck := ChunkStreamer.chunk_of(global_position)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var c := streamer.get_chunk(ck + Vector2i(dx, dz))
				if c == null:
					continue
				for o in c.data["objects"]:
					if o["st"].get("gone", false):
						continue
					var wp: Vector3 = c.position + o["p"]
					if Lore.has(o["t"]) and wp.distance_squared_to(global_position) < 196.0:
						# Terminals, books and the like inside rooms, each its own prompt.
						for k in Lore.spots(o["t"]).size():
							var at: Vector3 = c.position + Lore.anchor(o, k)
							var sl := _focus_score(eye, fwd, at)
							if sl < best_s and _can_see(eye, at):
								best_s = sl
								best = {"kind": "lore", "chunk": c, "i": o["i"], "spot": k, "pos": at + Vector3(0, 0.3, 0), "verb": Lore.verb(o, k)}
					if wp.distance_squared_to(global_position) > 49.0:
						continue
					var use := _use_of(o)
					if use.is_empty() or Treasure.covered(c.data, o):
						continue
					var sc := _focus_score(eye, fwd, wp + Vector3(0, use["h"] * 0.5, 0))
					if sc < best_s:
						best_s = sc
						best = {"kind": use["kind"], "chunk": c, "i": o["i"], "pos": wp + Vector3(0, use["h"] + 0.35, 0), "verb": _theft_verb(o, wp, use),
							"own": use["kind"] in ["door", "power"] and is_own_piece(o)}
	if dungeons:
		# Levers, keys, plates, braziers, seals and notices down in a dungeon.
		for u in dungeons.usables(global_position):
			var sc := _focus_score(eye, fwd, u["at"])
			if sc < best_s and _can_see(eye, u["at"]):
				best_s = sc
				best = {"kind": "dungeon", "node": u["node"], "n": u["n"], "pos": u["at"] + Vector3(0, 0.3, 0), "verb": u["verb"]}
	# Ferns, bushes, flowers and the like can be picked by hand, without a tool.
	if streamer and best.is_empty():
		var got := streamer.find_under(eye, eye + fwd * (USE_RANGE - 1.0), 0.45)
		if not got.is_empty():
			var parts := String(got["key"]).split("#")
			var pos: Vector3 = got["pos"]
			best = {"kind": "plant", "found": got, "pos": pos + Vector3(0, 0.9, 0), "verb": Flora.under_verb(int(parts[1]), int(parts[2]))}
	# A piece you built, right under the crosshair, can be taken down (or used, if a station).
	if not best.get("kind", "") in ["npc", "vehicle"]:
		var h := _hit_object()
		if h.has("obj") and h["point"].distance_to(eye) <= USE_RANGE + 1.0:
			var c: ChunkNode = h["chunk"]
			var o: Dictionary = c.get_object(h["obj"])
			if Doors.is_door(o["t"]) and not o["st"].get("gone", false):
				best = {"kind": "door", "chunk": c, "i": o["i"], "pos": h["point"] + Vector3(0, 0.35, 0), "verb": _door_verb(o), "own": is_own_piece(o)}
			elif Power.is_power(o["t"]) and not o["st"].get("gone", false) and PowerGrid.verb(o, sneaking()) != "":
				best = {"kind": "power", "chunk": c, "i": o["i"], "pos": h["point"] + Vector3(0, 0.35, 0), "verb": _power_verb(o), "own": is_own_piece(o)}
			elif is_own_piece(o):
				var d := BuildCatalog.def(BuildCatalog.id_of(o["t"]))
				var station := d.has("station") or d.has("storage") or d.has("teleporter")
				best = {"kind": "station" if station else "built", "chunk": c, "i": o["i"], "pos": h["point"] + Vector3(0, 0.35, 0),
					"verb": ("%s   (hold: take down)" % _station_verb(d)) if station else "Hold to take down %s" % d["name"]}
	return best

## True when nothing stands between the eye and `at` (a prop seen through a wall isn't).
func _can_see(eye: Vector3, at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, at, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(eye) > eye.distance_to(at) - 0.75

## Crouched on foot: sneaking (people notice you less; Interact on someone picks their pocket).
func sneaking() -> bool:
	return _crouched and vehicle == null

static func is_own_piece(o: Dictionary) -> bool:
	if ObjectLibrary.kind(o["t"]) != "built" or o["st"].get("gone", false):
		return false
	if Doors.is_door(o["t"]):
		return Doors.is_mine(o)
	# Pieces record their builder; on a server their allies may take them down too.
	# (Older pieces only say "by": "you".)
	if o["st"].has("owner"):
		return Doors.may_access(String(o["st"]["owner"]))
	return String(o["st"].get("by", "you")) == "you"

## "Built by you on day 3", or by whoever built it on a server.
static func built_by(o: Dictionary) -> String:
	var who := "you"
	var owner := String(o["st"].get("owner", ""))
	if owner != "" and owner != Doors.my_id():
		var nm := String(o["st"].get("owner_name", ""))
		who = nm if nm != "" and nm != "You" else "another player"
	return "Built by %s on day %d" % [who, int(o["st"].get("day", 0)) + 1]

# --- Deconstructing your own pieces -------------------------------------------------
const DECON_TIME := 0.8
## 0..1 while Interact is held on one of your pieces; the HUD draws it under the prompt.
var decon := 0.0
var _decon_on := {}

func _update_decon(delta: float) -> void:
	if _decon_on.is_empty():
		decon = 0.0
		return
	var same: bool = _focus_key(focus) == _decon_on["key"]
	if ui_open or not same:
		_decon_on = {}
		decon = 0.0
		return
	if Input.is_action_pressed("interact"):
		decon += delta / float(_decon_on.get("time", DECON_TIME))
		if decon >= 1.0:
			_decon_on = {}
			decon = 0.0
			if focus["kind"] == "carcass":
				if corpses:
					corpses.butcher(focus["body"], held_item())
					used_tool.emit("hit")
					if body:
						body.play_once("interact")
				_focus_t = 0.0
				return
			if focus["kind"] == "vehicle":
				var v: Vehicle = focus["vehicle"]
				if is_instance_valid(v):
					if vehicles.pack_up(v):
						Game.toast.emit("Packed up the %s" % Vehicle.label(v.kind).to_lower())
					else:
						Game.toast.emit("No room in your pack")
				_focus_t = 0.0
				return
			var c: ChunkNode = focus["chunk"]
			if is_instance_valid(c):
				deconstruct(c, c.get_object(focus["i"]))
		return
	# Released early: a tap, so use the station or ride the vehicle.
	if _decon_on["kind"] == "carcass":
		Game.toast.emit("Keep holding [%s] to %s it" % [_key("interact"), focus.get("verb", "butcher").split(" ")[0].to_lower()])
	elif _decon_on["kind"] == "station" and decon < 0.5:
		_use_station()
	elif _decon_on["kind"] == "door" and decon < 0.5:
		_use_door()
	elif _decon_on["kind"] == "power" and decon < 0.5:
		_use_power()
	elif _decon_on["kind"] == "vehicle" and decon < 0.5 and is_instance_valid(focus.get("vehicle")):
		mount(focus["vehicle"])
	_decon_on = {}
	decon = 0.0

## Takes one of your own pieces down whole and puts it back in your pack.
func deconstruct(chunk: ChunkNode, o: Dictionary) -> bool:
	if not is_own_piece(o):
		return false
	if not Storage.is_empty(o):
		Game.toast.emit("Empty the chest before taking it down")
		return false
	if not Doors.fits(BuildCatalog.id_of(o["t"])).is_empty() and not Doors.door_at(streamer, chunk.position + o["p"]).is_empty():
		Game.toast.emit("Take the door down before its doorway")
		return false
	if Power.is_power(o["t"]) and PowerGrid.current != null:
		# Its cables come down with it, back into your pack as wire.
		var back := PowerGrid.current.unhook(chunk, o)
		if back > 0:
			Game.give(ItemDB.make(Power.WIRE, back, 1.0, Game.origin_here("salvaged", -1, chunk.key)))
	used_tool.emit("hit")
	if body:
		body.play_once("interact")
	damage_object(chunk, o, Durability.health_left(o) + 1.0, 1.0)
	Game.toast.emit("Took down the %s" % String(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("name", "piece")).to_lower())
	_focus_t = 0.0
	return true

## How an object can be used with Interact, or {} if it can't.
static func _use_of(o: Dictionary) -> Dictionary:
	var t: String = o["t"]
	if t == WorldPortal.TYPE:
		return {"kind": "portal", "verb": "Step into the portal", "h": 3.4}
	if Wonders.has(t):
		var w := Wonders.use_of(o, Game.day)
		return {} if w.is_empty() else {"kind": "wonder", "verb": w["verb"], "h": w["h"]}
	match ObjectLibrary.kind(t):
		"cache":
			if o["st"].get("opened", false):
				return {}
			return {"kind": "cache", "verb": "Open %s" % ObjectLibrary.label(t), "h": 1.0}
		"trader":
			return {"kind": "trader", "verb": "Trade with %s" % String(o["st"].get("name", "the trader")).split(" ")[0], "h": 2.6}
		"built":
			var d := BuildCatalog.def(BuildCatalog.id_of(t))
			if d.has("door"):
				return {"kind": "door", "verb": Doors.verb(o, false), "h": 1.4}
			if d.has("power"):
				var pv := PowerGrid.verb(o, false)
				if pv == "":
					return {}
				var box := BuildCatalog.mesh(BuildCatalog.id_of(t)).get_aabb()
				return {"kind": "power", "verb": pv, "h": clampf(box.get_center().y * 2.0, -1.6, 2.2)}
			if d.has("station") or d.has("storage") or d.has("teleporter"):
				return {"kind": "station", "verb": _station_verb(d), "h": 1.2}
	return {}

static func _station_verb(d: Dictionary) -> String:
	if d.has("storage"):
		return "Open the %s" % String(d["name"]).to_lower()
	if d.has("teleporter"):
		return "Travel from the %s" % String(d["name"]).to_lower()
	return "Craft at the %s" % String(d["name"]).to_lower()

## Tap on a station: craft there, or open a storage chest.
func _use_station() -> void:
	var c = focus.get("chunk")
	if c is ChunkNode and is_instance_valid(c):
		var o: Dictionary = c.get_object(focus["i"])
		var d := BuildCatalog.def(BuildCatalog.id_of(o["t"]))
		if d.has("storage"):
			get_tree().call_group("trade_ui", "open_storage", o, c)
			return
		if d.has("teleporter"):
			get_tree().call_group("trade_ui", "open_travel", o, c)
			return
	get_tree().call_group("trade_ui", "open", "craft")

## The prompt on a powered piece: switch it, fuel it; your own can also be taken down.
func _power_verb(o: Dictionary) -> String:
	return PowerGrid.verb(o, sneaking()) + ("   (hold: take down)" if is_own_piece(o) and not sneaking() else "")

## Interact on a powered piece: lamps and switches flip, generators take fuel from your
## pack (crouched: start or stop them). Only yours, or your alliance's.
func _use_power() -> void:
	var c = focus.get("chunk")
	if not (c is ChunkNode and is_instance_valid(c)) or PowerGrid.current == null:
		return
	var o: Dictionary = c.get_object(focus["i"])
	if o["st"].get("gone", false) or not Power.is_power(o["t"]):
		return
	_focus_t = 0.0
	if not Doors.may_access(String(o["st"].get("owner", ""))):
		Game.toast.emit("That isn't yours")
		return
	PowerGrid.current.use_piece(c, o, sneaking())
	used_tool.emit("interact")

## The prompt on a door: open, shut, lock or pick it; your own can also be taken down.
func _door_verb(o: Dictionary) -> String:
	var v := Doors.verb(o, sneaking())
	return v + ("   (hold: take down)" if is_own_piece(o) and not sneaking() else "")

## Interact on a door: crouched, lock or unlock it (when it's yours, or your alliance's);
## otherwise open or shut it. A lock you have no key for brings out the lockpicks.
func _use_door() -> void:
	var c = focus.get("chunk")
	if not (c is ChunkNode and is_instance_valid(c)):
		return
	var o: Dictionary = c.get_object(focus["i"])
	if o["st"].get("gone", false) or not Doors.is_door(o["t"]):
		return
	_focus_t = 0.0
	var wp: Vector3 = c.position + o["p"]
	var nm := String(BuildCatalog.def(BuildCatalog.id_of(o["t"]))["name"]).to_lower()
	if sneaking() and Doors.set_locked(o, not Doors.is_locked(o)):
		c.door_changed(o["i"])
		Audio.play_at("door/lock", wp + Vector3(0, 1.0, 0), -4.0)
		Game.toast.emit(("Locked the %s. Only you%s can open it now." % [nm, "" if Doors.SOLO == Doors.my_id() else " and your alliance"]) if Doors.is_locked(o) else "Unlocked the %s" % nm)
		return
	var slide := bool(Doors.spec(o).get("slide", false))
	match Doors.toggle(o, Doors.side_of(o, wp, global_position)):
		"locked":
			Audio.play_at("door/lock", wp + Vector3(0, 1.0, 0), -6.0)
			get_tree().call_group("lockpick_ui", "open_lock", c, o, wp)
			return
		"opened":
			Audio.play_at("door/slide_open" if slide else "door/open", wp + Vector3(0, 1.2, 0), -3.0)
		"closed":
			Audio.play_at("door/slide_close" if slide else "door/close", wp + Vector3(0, 1.2, 0), -3.0)
	c.door_changed(o["i"])
	used_tool.emit("interact")

## The lockpicks beat a door's lock: it swings open, away from you. Picking someone
## else's lock in a town is a break-in if anyone sees.
func use_door_after_lock(chunk: ChunkNode, o: Dictionary) -> void:
	if not is_instance_valid(chunk):
		return
	var wp: Vector3 = chunk.position + o["p"]
	Doors.picked(o, Doors.side_of(o, wp, global_position))
	chunk.door_changed(o["i"])
	Audio.play_at("door/slide_open" if bool(Doors.spec(o).get("slide", false)) else "door/open", wp + Vector3(0, 1.2, 0), -3.0)
	if npcs and not Doors.is_mine(o):
		npcs.report_crime(wp, "lockpick", 0, "")

# --- Binoculars ----------------------------------------------------------------------
## Hold Use with binoculars: the view zooms in, and an animal under the crosshair (out to
## SPOT_RANGE) shows its tag and full stats.

const SPOT_RANGE := 260.0
const ZOOM_FOV := 12.0
var spotted: Creature = null
var _zoom := 0.0

func _holding_binoculars() -> bool:
	var it = held_item()
	return it != null and ItemDB.def(it["type"]).get("zoom", false)

func _binoculars(delta: float, on: bool) -> void:
	_zoom = move_toward(_zoom, 1.0 if on else 0.0, delta * 4.0)
	# Aiming down a gun's sights narrows the view too (fov is a full angle, so divide the
	# tangent, not the angle, to magnify).
	var base := Settings.vertical_fov(float(Settings.get_value("fov")))
	base = rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / gunplay.zoom()))
	camera.fov = lerpf(base, ZOOM_FOV, smoothstep(0.0, 1.0, _zoom))
	spotted = null
	if _zoom < 0.5:
		return
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * SPOT_RANGE, 1 | 2, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit and hit["collider"] and (hit["collider"] as Object).has_meta("creature"):
		spotted = hit["collider"].get_meta("creature")

func _creature_info(cr: Creature) -> Dictionary:
	var drops: Array = []
	for d in cr.p["drops"]:
		drops.append("%s x%d" % [ItemDB.def(d[0])["name"], d[1]])
	return {"title": "Lv %d  %s" % [cr.level(), cr.label()], "sub": "Wild animal  ·  %s" % String(cr.p["temper"]).capitalize(),
		"lines": ["Health %d / %d" % [int(maxf(cr.hp, 0.0)), int(cr.p["hp"])],
			"Bite %d  ·  Speed %.1f m/s" % [int(cr.bite_damage()), float(cr.p["speed"]) * 1.6] if cr.p["temper"] == "aggressive" else "Harmless  ·  Speed %.1f m/s" % (float(cr.p["speed"]) * (3.2 if cr.p["temper"] == "skittish" else 1.0)),
			"Drops: " + ", ".join(drops),
			"Distance %d m" % int(cr.global_position.distance_to(global_position))],
		"hp": cr.hp / float(cr.p["hp"]), "icon": cr.p["drops"][0][0]}

## The animal under the crosshair (or in the binoculars), whose tag FaunaManager shows
## at any distance.
var looking_at: Creature = null

func _update_look_target() -> void:
	var h := _hit_object()
	if spotted != null and is_instance_valid(spotted):
		h = {"creature": spotted}
	looking_at = h["creature"] if h.has("creature") and is_instance_valid(h["creature"]) else null
	var text := ""
	var info := {}
	if builder.active():
		text = "[%s] Place %s   [%s] Rotate" % [_key("use"), BuildCatalog.def(builder.piece_id())["name"], _key("rotate_build")]
		info = builder.info()
	elif wiring.active():
		info = wiring.info()
	elif h.has("creature") and is_instance_valid(h["creature"]):
		info = _creature_info(h["creature"])
	elif h.has("npc") and is_instance_valid(h["npc"]):
		var n: NPC = h["npc"]
		var r := int(n.rec.get("rel", 0))
		info = {"title": "Lv %d  %s" % [NPCSocial.level(n.rec), n.rec["name"]], "sub": "%s of %s" % [String(n.rec["job"]).capitalize(), n.settlement["name"]],
			"lines": ["Feels %s toward you (%d)" % ["hostile" if r <= -40 else ("wary" if r < -5 else ("neutral" if r < 15 else "friendly")), r],
				"Mood: %s" % n.rec.get("mood", "calm"), "Doing: %s" % n.action.replace("_", " ")],
			"hp": float(n.rec.get("hp", 100.0)) / NPCSocial.max_hp(n.rec)}
	elif h.has("obj"):
		var o: Dictionary = (h["chunk"] as ChunkNode).get_object(h["obj"])
		var t: String = o["t"]
		var k := ObjectLibrary.kind(t)
		var mat := Durability.material(t)
		if t == WorldPortal.TYPE:
			text = "[%s] Step into the portal" % _key("interact")
			info = {"title": "Ancient Portal", "sub": "Zone level %d" % Eras.zone_level(global_position.x, global_position.z),
				"lines": ["A door to the other worlds bound to this one", "Can't be broken"]}
		elif Wonders.unbreakable(t):
			# A relic: what it does instead of what it yields.
			var w := Wonders.use_of(o, Game.day)
			text = ("[%s] %s" % [_key("interact"), w["verb"]]) if not w.is_empty() else Wonders.describe(o, Game.day)
			if EasterEggs.has(t):
				info = {"title": EasterEggs.label(t), "sub": "Secret",
					"lines": [Wonders.describe(o, Game.day), "Can't be broken: use it with [%s]" % _key("interact")], "icon": EasterEggs.ICON[t]}
			elif WonderSite.has(t):
				info = {"title": WonderSite.label(t), "sub": "Wonder  ·  %s" % (Eras.NAMES[o["e"]] if o["e"] >= 0 else ""),
					"lines": [WonderSite.lore(t), "Can't be broken"], "icon": Durability.yields(o)[0][0]}
			else:
				info = {"title": ObjectLibrary.label_of(o), "sub": "Relic  ·  %s" % (Eras.NAMES[o["e"]] if o["e"] >= 0 else ""),
					"lines": [Wonders.describe(o, Game.day), "Can't be broken: use it with [%s]" % _key("interact")], "icon": Durability.yields(o)[0][0]}
		else:
			match k:
				"cache":
					text = "" if not o["st"].get("opened", false) else "%s (empty)" % ObjectLibrary.label(t)
				"trader":
					text = ""
				"built":
					# The prompt box already says how to take it down.
					text = ""
				_:
					text = "[%s] %s" % [_key("use"), "chop" if mat == "wood" or mat == "fungus" else "break"]
			var lines: Array = ["Yields: " + Durability.describe_yields(o)] if k != "built" else [built_by(o)]
			if Doors.is_door(t):
				lines = Doors.describe(o) if not is_own_piece(o) else [built_by(o)] + Doors.describe(o)
			elif Power.is_power(t) and PowerGrid.current != null:
				var held_m = held_item()
				lines = PowerGrid.current.describe(h["chunk"], o, held_m != null and held_m["type"] == Power.METER) + lines
			if Wonders.has(t):
				lines.push_front(Wonders.describe(o, Game.day))
			if k == "cache" and not o["st"].get("opened", false):
				lines.append("Contains: %d item stacks" % o["st"].get("loot", []).size())
				if WonderSite.sealed((h["chunk"] as ChunkNode).data, o):
					lines.append("Sealed until %s falls" % WonderSite.BOSSES[o["st"]["wonder"]][0])
			if k != "built":
				lines.append("Best tool: %s" % Durability.BEST_TOOL[mat])
			elif is_own_piece(o):
				lines.append("Hold [%s] to take it down, or one hit with a Builder's Hammer" % _key("interact"))
			var held = held_item()
			var d: Dictionary = ItemDB.stats(held) if held != null else Durability.FIST
			var hits := ceili(Durability.health_left(o) / maxf(0.001, Durability.power(d, mat) * (held.get("quality", 1.0) if held != null else 1.0)))
			lines.append("About %d hits with %s" % [hits, ItemDB.display_name(held) if held != null else "bare hands"])
			info = {"title": ObjectLibrary.label_of(o), "sub": "%s  ·  %s" % [Durability.MATERIAL_NAMES[mat], Eras.NAMES[o["e"]] if o["e"] >= 0 else ("Yours" if k == "built" else "")],
				"lines": lines, "hp": Durability.health_left(o) / Durability.max_hp(o), "icon": Durability.yields(o)[0][0]}
	elif h.has("chunk"):
		var held = held_item()
		var can_dig: bool = held != null and ItemDB.def(held["type"]).has("dig")
		info = {"title": "Ground", "sub": "Terrain", "lines": ["Dig with a pickaxe or drill for Stone" if not can_dig else "[%s] dig: leaves a permanent crater" % _key("use")], "icon": "stone"}
		var cn = h["chunk"]
		if cn is ChunkNode and h.has("point"):
			var lp: Vector3 = h["point"] - cn.position
			for o in cn.data["objects"]:
				if Treasure.covered(cn.data, o) and Vector2(o["p"].x - lp.x, o["p"].z - lp.z).length() < Treasure.MOUND_R + 1.0:
					info = {"title": "Turned Soil", "sub": "Something is buried here", "lines": ["Dig it out with a pickaxe or drill"], "icon": Treasure.MAPS[0]}
					break
	if text != _last_look:
		_last_look = text
		look_target_changed.emit(text)
	var key := str(info)
	if key != _last_info:
		_last_info = key
		look_info_changed.emit(info)

func interact() -> void:
	if not focus.is_empty():
		match focus["kind"]:
			"npc":
				if is_instance_valid(focus["npc"]):
					get_tree().call_group("dialogue_ui", "open_pickpocket" if sneaking() else "open_with", focus["npc"])
				return
			"station":
				_use_station()
				return
			"door":
				_use_door()
				return
			"power":
				_use_power()
				return
			"portal":
				if is_instance_valid(focus["chunk"]):
					get_tree().call_group("trade_ui", "open_portal", focus["chunk"].get_object(focus["i"]), focus["chunk"])
				_focus_t = 0.0
				return
			"wonder":
				if is_instance_valid(focus["chunk"]):
					_use_wonder(focus["chunk"], focus["chunk"].get_object(focus["i"]))
				_focus_t = 0.0
				return
			"cache", "trader":
				if is_instance_valid(focus["chunk"]):
					_use_object(focus["chunk"], focus["chunk"].get_object(focus["i"]))
				_focus_t = 0.0
				return
			"dungeon":
				if is_instance_valid(focus["node"]):
					focus["node"].use(focus["n"], self)
					used_tool.emit("interact")
				_focus_t = 0.0
				return
			"plant":
				_pick_plant(focus["found"])
				_focus_t = 0.0
				return
			"corpse":
				get_tree().call_group("trade_ui", "open_corpse", corpses, focus["body"])
				_focus_t = 0.0
				return
			"lore":
				if is_instance_valid(focus["chunk"]):
					get_tree().call_group("lore_ui", "open_spot", focus["chunk"], focus["i"], focus["spot"])
					used_tool.emit("interact")
				_focus_t = 0.0
				return
	var h := _hit_object()
	if h.has("npc") and is_instance_valid(h["npc"]):
		get_tree().call_group("dialogue_ui", "open_pickpocket" if sneaking() else "open_with", h["npc"])
		return
	if not h.has("obj"):
		return
	_use_object(h["chunk"], (h["chunk"] as ChunkNode).get_object(h["obj"]))

func _use_object(chunk: ChunkNode, o: Dictionary) -> void:
	if o["t"] == WorldPortal.TYPE:
		get_tree().call_group("trade_ui", "open_portal", o, chunk)
		return
	if Wonders.has(o["t"]):
		_use_wonder(chunk, o)
		return
	match ObjectLibrary.kind(o["t"]):
		"cache":
			if o["st"].get("opened", false):
				Game.toast.emit("It's empty.")
				return
			if WonderSite.sealed(chunk.data, o):
				Game.toast.emit("Sealed. %s still keeps this vault" % WonderSite.BOSSES[o["st"]["wonder"]][0])
				return
			if Treasure.covered(chunk.data, o):
				Game.toast.emit("Still buried. Dig it out with a pickaxe.")
				return
			if not o["st"].has("map_roll") and not o["st"].has("treasure"):
				# Now and then a cache holds a treasure map (decided when first opened).
				o["st"]["map_roll"] = true
				if randf() < Treasure.CACHE_CHANCE:
					var era := maxi(int(o["e"]), 0)
					(o["st"]["loot"] as Array).append(Treasure.make_map(era, Game.origin_here("found", era, chunk.key)))
				Game.mark_chunk_dirty(chunk.data)
			var wp: Vector3 = chunk.position + o["p"]
			var town: Dictionary = npcs.town_at(wp) if npcs and not Game.may_use_house_at(wp) else {}
			if not town.is_empty() and not _pick_lock(chunk, o, wp):
				return
			var loot: Array = o["st"]["loot"]
			var kept: Array = []
			var worth := 0
			for it in loot:
				if not Game.give(it):
					kept.append(it)
				else:
					worth += int(ItemDB.def(it["type"]).get("value", 1)) * int(it.get("qty", 1))
			o["st"]["loot"] = kept
			o["st"]["opened"] = kept.is_empty()
			Game.mark_chunk_dirty(chunk.data)
			if o["st"].has("treasure") and o["st"]["opened"]:
				Game.finish_treasure(int(o["st"]["treasure"]))
			if not town.is_empty() and worth > 0:
				# It belonged to someone here. Seen or not, it's stolen.
				if not npcs.report_crime(wp, "theft", worth, ObjectLibrary.label(o["t"]).to_lower()):
					Game.toast.emit("Stolen unseen (%d Marks' worth)" % worth)
					Game.practice("sneak", 2.0)
			if o["st"].has("wonder"):
				Game.map.note_chunk(chunk.data)
		"trader":
			Economy.tick(o["st"], Game.day)
			get_tree().call_group("trade_ui", "open_trader", o["st"], chunk)

# --- Theft --------------------------------------------------------------------------

## The prompt for a cache, saying when it belongs to someone in town (and how likely the lock is to give).
func _theft_verb(o: Dictionary, wp: Vector3, use: Dictionary) -> String:
	if use["kind"] == "door":
		return _door_verb(o)
	if use["kind"] != "cache" or npcs == null or o["st"].has("wonder"):
		return use["verb"]
	var town := npcs.town_at(wp)
	if town.is_empty() or Game.may_use_house_at(wp):
		return use["verb"]
	var lock := lock_of(o)
	if lock > 0:
		return "Pick the %s lock  (%d lockpicks, steal)" % [LockGame.TIERS[lock].to_lower(), Game.inventory.count("lockpick")]
	return "Steal from the %s" % ObjectLibrary.label(o["t"]).to_lower()

## How hard a town chest's lock is: 0 for none or picked, 1..3. Chosen once per chest.
static func lock_of(o: Dictionary) -> int:
	if Doors.is_door(o["t"]):
		return Doors.tier(o) if not Doors.can_open(o) else 0
	var st: Dictionary = o["st"]
	if not st.has("lock"):
		var h := absi(hash(str(o["p"]) + String(o["t"])))
		st["lock"] = 0 if h % 10 < 4 else 1 + (h / 10) % 3
	return int(st["lock"])

## A locked town chest opens the lockpicking minigame (LockpickUI). True when it is
## open (or never was locked).
func _pick_lock(chunk: ChunkNode, o: Dictionary, wp: Vector3) -> bool:
	if lock_of(o) <= 0:
		return true
	get_tree().call_group("lockpick_ui", "open_lock", chunk, o, wp)
	return false

## The minigame opened the lock: take what's inside.
func use_cache_after_lock(chunk: ChunkNode, o: Dictionary) -> void:
	if is_instance_valid(chunk):
		_use_object(chunk, o)

## Eats what is in your hand, else the first food in the pack that would do you good:
## plain food before medicine, and raw food that could make you sick last of all.
func eat() -> void:
	var it = held_item()
	if it != null and ItemDB.def(it["type"]).get("kind", "") == "food":
		consume(selected)
		return
	var idx := -1
	var best := 99
	for i in Inventory.SIZE:
		var s = Game.inventory.get_slot(i)
		if s == null:
			continue
		var fd := ItemDB.def(s["type"])
		if fd.get("kind", "") != "food" or fd.get("keep", false) or fd.has("buff") and not fd.has("heal"):
			continue
		if not Effects.useful(fd, Game.health, Game.max_health(), Game.stamina, Game.max_stamina(), Game.buffs):
			continue
		var rank := 2 if fd.has("sicken") else (1 if fd.get("cat", "") == "Medicine" else 0)
		if rank < best:
			best = rank
			idx = i
	if idx < 0:
		Game.toast.emit("You're not hungry." if Game.inventory.count_kind("food") > 0 else "No food.")
		return
	consume(idx)

## Uses up one of what is in a pack slot: eats or drinks it, reads it, plays it or sleeps
## on it. Each does what Effects describes.
func consume(idx: int) -> void:
	var it = Game.inventory.get_slot(idx)
	if it == null:
		return
	var fd := ItemDB.def(it["type"])
	var name := ItemDB.display_name(it)
	match String(fd.get("kind", "")):
		"food":
			if fd.get("keep", false):
				# A waterskin: drink, and it is there again once you are thirsty.
				if Game.has_buff("quenched"):
					Game.toast.emit("You're not thirsty.")
					return
				Game.set_stamina(Game.stamina + float(fd.get("stamina_add", 0)))
				Game.add_buff("quenched", 90.0)
				Game.toast.emit("You drink from your %s" % name.to_lower())
				return
			if not Effects.useful(fd, Game.health, Game.max_health(), Game.stamina, Game.max_stamina(), Game.buffs):
				Game.toast.emit("You're not hungry." if not fd.has("buff") else "That would do nothing for you now.")
				return
			Game.inventory.remove_at(idx, 1)
			Game.set_health(Game.health + float(fd.get("heal", 0)))
			Game.regen_left += float(fd.get("regen", 0))
			if fd.get("stamina", false):
				Game.set_stamina(Game.max_stamina())
				winded = false
			Game.set_stamina(Game.stamina + float(fd.get("stamina_add", 0)))
			if fd.get("cure", false):
				Game.cure()
			if fd.has("buff"):
				Game.add_buff(String(fd["buff"][0]), float(fd["buff"][1]))
			if randf() < float(fd.get("sicken", 0.0)) and not Game.has_buff("immune"):
				Game.add_buff("poison", Effects.SICK_SECS)
				Game.toast.emit("Ate %s. Your stomach turns..." % name)
				return
			Game.toast.emit("%s %s" % ["Drank" if fd.get("drink", false) or fd.get("cat", "") == "Medicine" else "Ate", name])
		"scroll":
			_read(idx, fd, name)
		"instrument":
			Game.add_buff(String(fd["play"]), 180.0)
			Audio.play("ui/click", -6.0)
			var b: Dictionary = Effects.BUFFS[fd["play"]]
			if fd["play"] == "inspired":
				Game.toast.emit("You play a tune on the %s. You feel inspired." % name.to_lower())
			else:
				Game.toast.emit("You while away a little time with the %s. %s." % [name.to_lower(), b["name"]])
		"camp":
			_sleep(fd, name)
		"kit":
			_use_kit(idx, fd, name)
		"trap":
			_set_trap(idx, String(it["type"]), name)
		"implant":
			if Game.fit_implant(idx):
				Audio.play("ui/click", -6.0)
				Game.toast.emit("The %s takes. You feel it settle in: %s" % [name.to_lower(), ", ".join(Effects.describe(fd)).to_lower()])
			else:
				Game.toast.emit("You already have a %s fitted" % name.to_lower())

## Fires a grapple line where you look (out to `reach` m) and hauls you toward the spot
## it catches. Returns whether it caught.
func grapple(reach: float) -> bool:
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * reach, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		Game.toast.emit("The grapple finds nothing to catch on")
		return false
	var to: Vector3 = hit["position"] - global_position
	# Fast enough to cover the gap in about a second, with a little lift to clear the lip.
	velocity = to.normalized() * clampf(to.length() * 1.1, 8.0, 30.0) + Vector3(0, 4.0, 0)
	Audio.play("weapon/draw", -6.0)
	return true

## Gun oil, scanners, beacons, air and the like (an item of kind "kit"). Kept ones
## ("keep") are not used up.
func _use_kit(idx: int, fd: Dictionary, name: String) -> void:
	if fd.has("unpack"):
		# A box of rounds and the like: opened into what it holds.
		Game.inventory.remove_at(idx, 1)
		Game.give(ItemDB.make(String(fd["unpack"][0]), int(fd["unpack"][1]), 1.0, {}))
		Game.toast.emit("You open the %s: %d %s" % [name.to_lower(), int(fd["unpack"][1]), ItemDB.def(fd["unpack"][0]).get("name", "").to_lower()])
		return
	if fd.get("revive", false):
		Game.toast.emit("Keep the %s in your pack: it brings you back if you fall" % name.to_lower())
		return
	if fd.get("beacon", false):
		Game.inventory.remove_at(idx, 1)
		Game.markers.add(name, global_position.x, global_position.z, Game.planet, "pin", {"icon": "beacon"})
		Game.touch_player()
		Game.toast.emit("You set down the %s. It's on your map." % name.to_lower())
		return
	if fd.get("air", false):
		if breath >= Game.stats.max_breath() - 0.5:
			Game.toast.emit("You have all the air you need")
			return
		if not fd.get("keep", false):
			Game.inventory.remove_at(idx, 1)
		breath = Game.stats.max_breath()
		Game.toast.emit("You breathe from the %s" % name.to_lower())
		return
	var id := String(fd["buff"][0])
	if fd.get("keep", false) and Game.has_buff(id):
		Game.toast.emit("The %s is already working" % name.to_lower())
		return
	if not fd.get("keep", false):
		Game.inventory.remove_at(idx, 1)
	Game.add_buff(id, float(fd["buff"][1]))
	Game.toast.emit("You use the %s: %s" % [name.to_lower(), Effects.BUFFS[id]["desc"].to_lower()])

## Sets the trap from pack slot `idx` on the ground at your feet (Traps).
func _set_trap(idx: int, type: String, name: String) -> void:
	if traps == null or not is_on_floor():
		Game.toast.emit("Stand on firm ground to set the %s" % name.to_lower())
		return
	if traps.count() >= Traps.MAX:
		Game.toast.emit("You have %d traps set already" % Traps.MAX)
		return
	Game.inventory.remove_at(idx, 1)
	traps.add(type, global_position)
	Game.toast.emit("You set the %s. Mind your step." % name.to_lower())

func _read(idx: int, fd: Dictionary, name: String) -> void:
	var what := String(fd.get("read", ""))
	match what:
		"courage", "warded":
			Game.add_buff(what, 300.0)
			Game.toast.emit("You read the %s. %s" % [name.to_lower(), Effects.BUFFS[what]["desc"]])
		"return":
			var home = Game.home_near(global_position)
			if home is Vector2:
				teleport_to(home.x, home.y)
			else:
				var sp := Planets.spawn_point(Game.seed, Game.store != null and Game.store.has_rivers())
				teleport_to(sp.x, sp.z)
			Game.toast.emit("The words fade, and the world folds you home.")
		"book":
			var gain := 30.0 + randf() * 50.0
			Game.add_xp(gain, "Reading")
			Game.toast.emit("You read the old book cover to cover.")
		_:
			return
	Game.inventory.remove_at(idx, 1)

## Sleeps until morning on a bedroll or in a tent: whole again, and well rested.
func _sleep(fd: Dictionary, name: String) -> void:
	var t := fposmod(Game.day, 1.0)
	if t > 0.24 and t < 0.78:
		Game.toast.emit("It's too light to sleep. Use the %s at night." % name.to_lower())
		return
	Game.day = floor(Game.day) + (1.0 if t >= 0.5 else 0.0) + 0.26
	Game.set_health(Game.max_health())
	Game.set_stamina(Game.max_stamina())
	Game.add_buff("rested", 600.0 * float(fd.get("sleep", 1.0)))
	Game.toast.emit("You sleep on your %s and wake at dawn, well rested." % name.to_lower())

## Spends stamina; returns false if there was not enough. Running dry leaves you winded.
## How a heavy pack slows you: 1 up to your carry capacity, then down to a crawl. Over
## capacity you cannot sprint.
func load_mult() -> float:
	var r := Game.inventory.weight() / Game.stats.carry_capacity()
	if r <= 1.0:
		return 1.0
	return maxf(0.3, 1.0 - (r - 1.0) * 1.4)

func _tire(n: float) -> bool:
	_rest = 0.0
	if Game.use_stamina(n):
		return true
	Game.set_stamina(0.0)
	winded = true
	return false

func use_held() -> void:
	var it = held_item()
	if it != null and ItemDB.def(it["type"]).get("kind", "") in ["food", "scroll", "instrument", "camp", "kit", "trap", "implant"]:
		_cooldown = 0.5
		consume(selected)
		return
	if it != null and ItemDB.def(it["type"]).has("fish"):
		_cooldown = 0.6
		_cast_line()
		return
	if it != null and ItemDB.def(it["type"]).has("grapple"):
		_cooldown = 0.8
		grapple(float(ItemDB.def(it["type"])["grapple"]))
		return
	if it != null and ItemDB.def(it["type"]).get("kind", "") == "armor":
		_cooldown = 0.4
		Game.equip(selected)
		return
	if it != null and Vehicle.is_vehicle_item(it["type"]):
		_cooldown = 0.5
		deploy_vehicle()
		return
	if it != null and Treasure.is_map(it["type"]):
		_cooldown = 0.5
		var h := Game.hunt(int(it.get("hunt", -1))) if it.has("hunt") else Game.start_treasure(it)
		Game.toast.emit(Treasure.hint(h, global_position))
		return
	if wiring.active():
		_cooldown = 0.2
		if not _trigger_held:
			_trigger_held = true
			wiring.use()
		return
	if it != null and BuildCatalog.is_piece_item(it["type"]):
		_cooldown = 0.25
		if builder.place():
			Audio.play("hit/plank", -4.0)
			used_tool.emit("build")
			Game.add_xp(4.0, "Building")
		return
	var d: Dictionary = ItemDB.stats(it) if it != null else Durability.FIST
	var q: float = it.get("quality", 1.0) if it != null else 1.0
	if d.get("ranged", false):
		_fire(it, d)
		return
	if d.get("beam", false):
		# Held steady, burning for as long as Use is held: no swing.
		_cooldown = Gunplay.BEAM_TICK
		gunplay.beam(it, d)
		if body:
			body.play_once("pistol", 0.3)
		return
	# A tired swing is slow and weak.
	var fresh := _tire(5.0)
	var force: float = Game.stats.damage_mult() * (1.0 if fresh else 0.5)
	var hq: float = q * force
	_cooldown = (0.55 if fresh else 0.9) / Game.stats.swing_mult() * (0.75 if d.get("swift", false) else 1.0) * float(d.get("swing", 1.0))
	if body:
		body.play_once(swing_anim(it["type"] if it != null else ""), _cooldown + 0.1)
	var h := _hit_object()
	if fauna and not h.has("creature") and not h.has("npc"):
		# From your own head, not the camera, so it works the same in third person.
		var head := global_position + Vector3(0, 1.6, 0)
		var c := fauna.melee_target(head, -camera.global_transform.basis.z, float(d.get("range", REACH)))
		if c != null and (not h.has("point") or head.distance_to(h["point"]) > head.distance_to(c.global_position) - 0.5):
			h = {"creature": c, "point": c.global_position}
	# The swing comes down on what the crosshair is on and stops there; the blow's
	# sound and marks wait for the moment it lands.
	var land := viewmodel.swing(_cooldown, h if h.has("normal") else {})
	if (h.is_empty() or (h.has("chunk") and not h.has("obj"))) and _harvest_under(h, q):
		return
	Audio.play("swing/whoosh", -10.0 if fresh else -14.0, 0.1)
	if h.is_empty():
		used_tool.emit("miss")
		return
	if h.has("creature") and is_instance_valid(h["creature"]) and fauna:
		used_tool.emit("hit")
		_on_land(land, Audio.play_at.bind("hit/flesh", h["point"], -2.0))
		_strike(it, h["creature"], null, float(d.get("damage", 2)) * hq, false, h.get("point", Vector3.INF))
		return
	if h.has("npc") and is_instance_valid(h["npc"]) and npcs:
		used_tool.emit("hit")
		_on_land(land, Audio.play_at.bind("hit/flesh", h["point"] if h.has("point") else (h["npc"] as Node3D).global_position, -2.0))
		_strike(it, null, h["npc"], float(d.get("damage", 2)) * hq, false, h.get("point", Vector3.INF))
		return
	if h.has("rplayer"):
		used_tool.emit("hit")
		_pvp_hit(it, int(h["rplayer"]), float(d.get("damage", 2)) * hq, false, h.get("point", Vector3.INF))
		return
	if h.has("obj"):
		var chunk: ChunkNode = h["chunk"]
		var o: Dictionary = chunk.get_object(h["obj"])
		var mat := Durability.material(o["t"])
		used_tool.emit("chop" if mat == "wood" or mat == "fungus" else "mine")
		var at: Vector3 = h.get("point", chunk.position + o["p"])
		var sound := "hit/plank" if ObjectLibrary.kind(o["t"]) == "built" else Audio.hit_bank(mat)
		var oi: int = h["obj"]
		var steel := ImpactFx.steel_edge(it["type"] if it != null else "")
		var along := _blow_dir()
		_on_land(land, func():
			Audio.play_at(sound, at, -1.0 if fresh else -5.0)
			# No mark left hanging in the air where the thing was felled or broken.
			var there: bool = is_instance_valid(chunk) and not chunk.get_object(oi)["st"].get("gone", false)
			ImpactFx.strike(at, h.get("normal", Vector3.UP), mat, force if it != null else 0.4, steel, along, there))
		if d.get("build", false) and is_own_piece(o):
			# The builder's hammer takes your own pieces down in one blow.
			damage_object(chunk, o, Durability.health_left(o) + 1.0, 1.0)
			return
		damage_object(chunk, o, Durability.power(d, mat) * hq, q)
	elif h.has("chunk") and d.has("dig"):
		# Digging the ground itself: a persistent crater, and some stone.
		used_tool.emit("dig")
		var p: Vector3 = h["point"]
		_on_land(land, func():
			Audio.play_at("hit/dig", p, -2.0)
			ImpactFx.strike(p, h.get("normal", Vector3.UP), "dirt", force, false, Vector3.ZERO, false))
		streamer.dig(p, 1.6 + d["dig"] * 0.6, 0.35 * d["dig"] * hq)
		var ck := ChunkStreamer.chunk_of(p)
		if randf() < 0.5:
			Game.give(ItemDB.make("stone", 1, 1.0, Game.origin_here("dug", -1, ck)))
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for y in Byproducts.of_digging(float(d["dig"]), rng):
			Game.give_loot(ItemDB.make(y[0], y[1], 1.0, Game.origin_here("dug", -1, ck)))

## Runs `f` when a swing lands (`delay` seconds from now), or now if it already has.
func _on_land(delay: float, f: Callable) -> void:
	if delay <= 0.01 or not is_inside_tree():
		f.call()
		return
	get_tree().create_timer(delay, false).timeout.connect(f)

## Which way a melee blow travels in the world: down and across in front of you.
func _blow_dir() -> Vector3:
	return (camera.global_transform.basis * Vector3(-0.25, -0.75, -0.6)).normalized()

## Undergrowth has no collision, so a swing that reaches the ground (or nothing) first
## looks for a bush, fern or flower along the swing and pulls it up.
func _harvest_under(h: Dictionary, q: float) -> bool:
	if streamer == null:
		return false
	var from := camera.global_position
	var to: Vector3 = h["point"] if h.has("point") else from - camera.global_transform.basis.z * REACH
	var got := streamer.harvest_under(from, to, 0.6)
	if got.is_empty():
		return false
	used_tool.emit("chop")
	Audio.play_at("harvest/rustle", got["pos"], 0.0, 0.15)
	var parts := String(got["key"]).split("#")
	var era := int(parts[2])
	var ck := ChunkStreamer.chunk_of(got["pos"])
	for y in Flora.under_yield(int(parts[1]), era, randf()):
		Game.give_loot(ItemDB.make(y[0], y[1], q, Game.origin_here("gathered", era, ck)))
	return true

## Picks a plant by hand (Interact): the same yield as cutting it, at plain quality.
# --- Fishing and night-eye ---------------------------------------------------------

const CAST_RANGE := 16.0
var _fish_t := 0.0 ## seconds until a bite, while a line is out
var _fish_uid := -1 ## the rod the line belongs to
var _night_light: OmniLight3D
var _head_lamp: SpotLight3D

## Casts a line where you look, if that is water within reach.
func _cast_line() -> void:
	if _fish_t > 0.0:
		Game.toast.emit("Your line is already out. Wait for a bite.")
		return
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * CAST_RANGE, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var far: float = from.distance_to(hit["position"]) if hit.has("position") else CAST_RANGE
	var tw := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var wet := false
	var d := 2.0
	while d <= far:
		var p := from + fwd * d
		if p.y < Water.surface_height(p.x, p.z, tw) - 0.2:
			wet = true
			break
		d += 1.0
	if not wet:
		Game.toast.emit("Cast your line into water.")
		return
	_fish_t = randf_range(3.0, 8.0) / float(ItemDB.def(held_item()["type"]).get("fish", 1.0))
	_fish_uid = int(held_item().get("uid", -1))
	Audio.play("water/splash", -12.0)
	Game.toast.emit("You cast your line...")

func _tick_fishing(delta: float) -> void:
	if _fish_t <= 0.0:
		return
	var it = held_item()
	if it == null or int(it.get("uid", -2)) != _fish_uid:
		_fish_t = 0.0
		Game.toast.emit("You reel in your line.")
		return
	_fish_t -= delta
	if _fish_t > 0.0:
		return
	_fish_t = 0.0
	if randf() < 0.7:
		var ck := ChunkStreamer.chunk_of(global_position)
		var n := 2 if randf() < 0.12 else 1
		Game.give_loot(ItemDB.make("fish_raw", n, randf_range(0.9, 1.15), Game.origin_here("caught", -1, ck)))
		Game.add_xp(5.0, "Fishing")
		Audio.play("water/splash", -8.0)
		Game.toast.emit("You caught %s!" % ("two fish" if n == 2 else "a fish"))
	else:
		Game.toast.emit("Something nibbled, and got away.")

## Night-eye drops: a soft, wide, shadowless light only you see by.
func _update_nightsight() -> void:
	var on := Game.has_buff("nightsight")
	if on and _night_light == null:
		_night_light = OmniLight3D.new()
		_night_light.light_color = Color(0.72, 0.8, 0.95)
		_night_light.omni_range = 30.0
		_night_light.omni_attenuation = 0.6
		_night_light.light_energy = 0.55
		_night_light.shadow_enabled = false
		camera.add_child(_night_light)
	if _night_light:
		_night_light.visible = on
	# A miner's helmet lamp shines where you look for as long as you wear it.
	var head = Game.equipment.get("head")
	var lamp: bool = head is Dictionary and ItemDB.def(String(head.get("type", ""))).get("lamp", false)
	if lamp and _head_lamp == null:
		_head_lamp = SpotLight3D.new()
		_head_lamp.light_color = Color(1.0, 0.86, 0.62)
		_head_lamp.spot_range = 30.0
		_head_lamp.spot_angle = 24.0
		_head_lamp.spot_angle_attenuation = 1.4
		_head_lamp.light_energy = 2.2
		_head_lamp.shadow_enabled = false
		_head_lamp.position = Vector3(0, 0.12, -0.05)
		camera.add_child(_head_lamp)
	if _head_lamp:
		_head_lamp.visible = lamp

func _pick_plant(found: Dictionary) -> void:
	if streamer == null or not streamer.pick_under(found):
		return
	used_tool.emit("interact")
	if body:
		body.play_once("interact")
	var parts := String(found["key"]).split("#")
	var era := int(parts[2])
	var ck := ChunkStreamer.chunk_of(found["pos"])
	var got: Array = []
	# A sickle or a hoe takes more from each plant.
	var reap: float = ItemDB.def(held_item()["type"]).get("reap", 1.0) if held_item() != null else 1.0
	for y in Flora.under_yield(int(parts[1]), era, randf()):
		y[1] = int(ceil(int(y[1]) * reap))
		Game.give_loot(ItemDB.make(y[0], y[1], 1.0, Game.origin_here("gathered", era, ck)))
		got.append("%s x%d" % [ItemDB.def(y[0])["name"], y[1]])
	Game.toast.emit("Picked: " + ", ".join(got))

func _fire(it: Dictionary, d: Dictionary) -> void:
	if not d.get("auto", false):
		# One shot per pull of the trigger.
		if _trigger_held:
			return
		_trigger_held = true
	gunplay.fire(it, d)

## Gun sounds, from Gunplay's hooks: energy guns zap, bows and crossbows whoosh.
func _gun_sound(kind: String, t: String, at: Vector3, what: String) -> void:
	var d := ItemDB.def(t)
	match kind:
		"fire":
			if Gunplay.handling(t).get("auto_reload", false) or d.get("thrown", false):
				Audio.play("swing/whoosh", -8.0, 0.1)
			elif Gunplay.handling(t).get("powder", false) or d.has("flare"):
				Audio.play("weapon/explosion", -14.0, 0.1, 1.6)
			else:
				Audio.play("weapon/laser_big" if d.has("splash") else "weapon/laser", -6.0, 0.06)
		"dry":
			Audio.ui("ui/error")
		"beam":
			Audio.play("weapon/laser", -16.0, 0.15, 0.6)
		"reload_start", "reload_round":
			Audio.play("weapon/draw", -12.0)
		"impact":
			if d.get("smoke", false):
				Audio.play_at("hit/metal", at, -6.0)
			elif d.has("splash"):
				Audio.play_at("weapon/explosion", at, 4.0)
			elif what == "creature" or what == "npc":
				Audio.play_at("hit/flesh", at, -4.0)
			elif what == "ground":
				Audio.play_at("hit/dig", at, -8.0)
			else:
				Audio.play_at(Audio.hit_bank(what), at, -6.0)

var _beam_dig := 0.0

## One tick of a beam on what it touches: `tick` seconds of its damage per second on
## animals and people, of fast mining on objects, and on bare ground a crater burnt in
## every so often. Returns what was hit, like ranged_hit.
func beam_hit(it, d: Dictionary, hit: Dictionary, tick: float) -> String:
	var col = hit.get("collider")
	var q: float = it.get("quality", 1.0) if it is Dictionary else 1.0
	if not (col is Object) or not is_instance_valid(col):
		return "ground"
	var dmg := float(d.get("beam_dps", 40.0)) * q * Game.stats.damage_mult() * tick
	if col.has_meta("creature") and fauna:
		var c = col.get_meta("creature")
		if is_instance_valid(c):
			fauna.player_hit(c, dmg)
			if c.hp <= 0.0 or gunplay._beam_ticks % 3 == 1:
				_mark(c, null, false)
		return "creature"
	if col.has_meta("npc") and npcs:
		var n = col.get_meta("npc")
		if is_instance_valid(n):
			npcs.player_hit(n, dmg)
			if float(n.rec.get("hp", 1.0)) <= 0.0 or gunplay._beam_ticks % 3 == 1:
				_mark(null, n, false)
		return "npc"
	if col.has_meta("remote_player"):
		_pvp_hit(it, int(col.get_meta("remote_player")), dmg, false, hit.get("position", Vector3.INF), gunplay._beam_ticks % 3 == 1)
		return "npc"
	if col.has_meta("obj"):
		var chunk: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = chunk.get_object(col.get_meta("obj"))
		var mat := Durability.material(o["t"])
		damage_object(chunk, o, Durability.power(d, mat) * float(d.get("beam_mine", 4.0)) * q * tick, q)
		return "wood" if mat in ["wood", "planks", "fungus"] else ("metal" if mat in ["metal", "circuitry"] else "stone")
	if col.has_meta("chunk") and d.has("dig") and streamer:
		_beam_dig += tick
		if _beam_dig >= 0.6:
			_beam_dig = 0.0
			var p: Vector3 = hit["position"]
			streamer.dig(p, 1.2 + float(d["dig"]) * 0.4, 0.25 * float(d["dig"]) * q)
			if randf() < 0.5:
				var ck := ChunkStreamer.chunk_of(p)
				Game.give(ItemDB.make("stone", 1, 1.0, Game.origin_here("dug", -1, ck)))
	return "ground"

## A shot from a ranged weapon landed: hurt what it hit (or blast everything around, for
## splash weapons). Returns what was hit, for the impact effect and sound: "creature",
## "npc", "stone", "wood", "metal" or "ground".
func ranged_hit(it, d: Dictionary, hit: Dictionary, at: Vector3) -> String:
	var col = hit.get("collider")
	var q: float = it.get("quality", 1.0) if it is Dictionary else 1.0
	if d.has("splash"):
		_blast(at, float(d["splash"]), float(d.get("damage", 10)), not String(d.get("tracer", "")).begins_with("glow") or d.get("tracer", "") == "glow_warm")
		if col is Object and is_instance_valid(col) and col.has_meta("obj"):
			var bc: ChunkNode = col.get_meta("chunk")
			damage_object(bc, bc.get_object(col.get_meta("obj")), float(d.get("damage", 10)) * 0.5, 0.8)
		return "ground"
	if not (col is Object) or not is_instance_valid(col):
		return "ground"
	if col.has_meta("creature") and fauna:
		var c = col.get_meta("creature")
		if is_instance_valid(c):
			_strike(it, c, null, float(d.get("damage", 10)) * q, c.is_head(at), at)
		return "creature"
	if col.has_meta("npc") and npcs:
		var n = col.get_meta("npc")
		if is_instance_valid(n):
			_strike(it, null, n, float(d.get("damage", 10)) * q, n.is_head(at), at)
		return "npc"
	if col.has_meta("remote_player"):
		var rp = col.get_meta("remote_player_node") if col.has_meta("remote_player_node") else null
		var head: bool = rp != null and is_instance_valid(rp) and at.y - (rp as Node3D).global_position.y > 1.45
		_pvp_hit(it, int(col.get_meta("remote_player")), float(d.get("damage", 10)) * q, head, at)
		return "npc"
	if col.has_meta("obj"):
		var chunk: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = chunk.get_object(col.get_meta("obj"))
		if o.is_empty():
			return "ground"
		var mat := Durability.material(o["t"])
		damage_object(chunk, o, Durability.power({"mine": 0.6, "chop": 0.6, "damage": d.get("damage", 10)}, mat), 0.8)
		match mat:
			"wood", "planks", "fungus":
				return "wood"
			"metal", "circuitry":
				return "metal"
			"stone", "ore", "crystal":
				return "stone"
	return "ground"

## A hit on a creature or person, with the held item's abilities: critical strikes,
## life drain and arcs of lightning to whatever stands close by.
## `head`: a shot to the head (guns and bows), for HEADSHOT times the damage.
## `point`: where it struck, so a killing blow knocks the body that way (Ragdoll).
func _strike(it, creature, npc, dmg: float, head := false, point := Vector3.INF) -> void:
	Audio.combat()
	if Rarity.has_affix(it, "keen") and randf() < 0.2:
		dmg *= 2.0
		Game.toast.emit("Critical hit!")
	if head:
		dmg *= HEADSHOT
	var at: Vector3 = creature.global_position if creature != null else npc.global_position
	_mark_blow(creature if creature != null else npc, point if point != Vector3.INF else at + Vector3(0, 1.0, 0), dmg, head)
	if creature != null:
		fauna.player_hit(creature, dmg)
	else:
		npcs.player_hit(npc, dmg)
	_mark(creature, npc, head)
	if Rarity.has_affix(it, "vampiric"):
		Game.set_health(minf(Game.max_health(), Game.health + dmg * 0.08))
	if Rarity.has_affix(it, "shock") and fauna:
		viewmodel.tracer(at + Vector3(0, 1.0, 0), "glow_cyan")
		for c in fauna.creatures_near(at, 3.0):
			if c != creature:
				fauna.player_hit(c, dmg * 0.4)

const HEADSHOT := 2.0

## A hit on another player (multiplayer): sent to them through the server, which lets
## it through only with PvP on (and never between allies).
func _pvp_hit(it, peer: int, dmg: float, head := false, _point := Vector3.INF, marker := true) -> void:
	var rec: Dictionary = Net.peers.get(peer, {})
	if rec.is_empty():
		return
	if not Net.may_hurt(String(rec["pid"])):
		if Time.get_ticks_msec() - _pvp_note > 8000:
			_pvp_note = Time.get_ticks_msec()
			Game.toast.emit("PvP is off on this server" if not bool(Net.option("pvp")) else "%s is your ally" % rec["name"])
		return
	Audio.combat()
	if Rarity.has_affix(it, "keen") and randf() < 0.2:
		dmg *= 2.0
		Game.toast.emit("Critical hit!")
	if head:
		dmg *= HEADSHOT
	Net.hurt_player(peer, dmg, "", true)
	if marker:
		hit_marker.emit("head" if head else "hit")
		Audio.play("hit/marker", -3.0 if head else -13.0, 0.05, 1.8 if head else 1.3)

var _pvp_note := -99999

## Remembers a blow on `target` for its ragdoll, should it die of it: from your eyes
## through the point struck, harder the more it hurt.
func _mark_blow(target: Node3D, point: Vector3, dmg: float, head := false) -> void:
	var dir := point - camera.global_position if camera else -global_basis.z
	dir.y = maxf(dir.y, -0.2 * dir.length())
	Ragdoll.mark_hit(target, point, dir, clampf(10.0 + dmg * 0.8, 10.0, 70.0), "Head" if head else "")

## Hit markers: the HUD flashes a cross around the crosshair ("hit", "head" or "kill")
## and a metallic tick confirms it, sharper and higher for a headshot, lower and fuller
## for a kill.
signal hit_marker(kind: String)

func _mark(creature, npc, head: bool) -> void:
	var dead := false
	if creature != null:
		dead = not is_instance_valid(creature) or creature.hp <= 0.0
	elif npc != null:
		dead = not is_instance_valid(npc) or float(npc.rec.get("hp", 1.0)) <= 0.0
	var kind := "kill" if dead else ("head" if head else "hit")
	hit_marker.emit(kind)
	match kind:
		"kill":
			Audio.play("hit/marker", -4.0, 0.03, 0.8)
		"head":
			Audio.play("hit/marker", -3.0, 0.03, 1.8)
		_:
			Audio.play("hit/marker", -13.0, 0.05, 1.3)

## A blast: every animal within `radius` takes damage, less towards the edge.
func _blast(at: Vector3, radius: float, dmg: float, powder := false) -> void:
	var fx := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	fx.mesh = sm
	# Black powder bursts in fire; energy weapons in violet light.
	fx.material_override = Materials.get_mat("glow_warm" if powder else "glow_violet")
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(fx)
	fx.global_position = at
	var tw := fx.create_tween()
	tw.tween_property(fx, "scale", Vector3.ONE * radius * 2.0, 0.25)
	tw.tween_callback(fx.queue_free)
	var others = get_tree().get_first_node_in_group("remote_players")
	if others != null:
		for rp in others.near(at, radius):
			var f := 1.0 - 0.6 * clampf((rp.global_position as Vector3).distance_to(at) / radius, 0.0, 1.0)
			_pvp_hit(null, rp.peer, dmg * f, false, at)
	if fauna == null:
		return
	for c in fauna.creatures_near(at, radius):
		var f := 1.0 - 0.6 * clampf(c.global_position.distance_to(at) / radius, 0.0, 1.0)
		# Thrown outward and up from the blast.
		var mid: Vector3 = c.global_position + Vector3(0, 0.6, 0)
		var out := (mid - at).normalized() + Vector3(0, 0.6, 0)
		Ragdoll.mark_hit(c, mid, out, clampf(dmg * f * 1.5, 20.0, 160.0))
		fauna.player_hit(c, dmg * f)

## One hit on a world object: damage, pay out yields as they are earned, destroy at zero.
## Relics and markers answer to Interact, not to your pick.
func _use_wonder(chunk: ChunkNode, o: Dictionary) -> void:
	if Wonders.use_of(o, Game.day).is_empty():
		Game.toast.emit(Wonders.describe(o, Game.day))
		return
	Game.toast.emit(WonderEffects.apply(o, chunk, self))
	used_tool.emit("interact")

var _wonder_hint_t := -10.0

func damage_object(chunk: ChunkNode, o: Dictionary, amount: float, quality: float) -> void:
	if Wonders.unbreakable(o["t"]):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _wonder_hint_t > 3.0:
			_wonder_hint_t = now
			var w := Wonders.use_of(o, Game.day)
			Game.toast.emit("Your blows glance off the %s.%s" % [ObjectLibrary.label_of(o), "" if w.is_empty() else " [%s] %s" % [_key("interact"), w["verb"]]])
		return
	var r := Durability.hit(o, amount)
	var k0 := ObjectLibrary.kind(o["t"])
	var mat0 := Durability.material(o["t"])
	var how := "reclaimed" if k0 == "built" else ("salvaged" if k0 in ["structure", "cache", "trader", "marker"] or mat0 == "metal" else ("gathered" if k0 == "tree" else "mined"))
	var xp := 0.0
	var twice := Rarity.has_affix(held_item(), "bountiful") and randf() < 0.25
	var units := 0
	for y in r["items"]:
		Game.give_loot(ItemDB.make(y[0], y[1] * (2 if twice else 1), quality * randf_range(0.92, 1.08), Game.origin_here(how, o["e"], chunk.key)))
		xp += 2.0 * y[1]
		units += int(y[1])
	if units > 0 and Byproducts.FROM.has(o["t"]):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var wp: Vector3 = chunk.position + o["p"]
		var zone := Eras.zone_level(wp.x, wp.z) if Eras.themed() else 99
		for y in Byproducts.of_object(o["t"], units, zone, rng):
			Game.give_loot(ItemDB.make(y[0], y[1], quality, Game.origin_here(how, o["e"], chunk.key)))
			Game.toast.emit("Found %s" % ItemDB.def(y[0])["name"].to_lower())
	if r["destroyed"]:
		ImpactFx.clear_near(chunk.position + o["p"], 3.0 * float(o.get("s", 1.0)))
		if k0 == "built" and BuildCatalog.def(BuildCatalog.id_of(o["t"])).has("teleporter"):
			Game.markers.remove_object(chunk.key, o["i"])
			Game.touch_player()
		for it in Storage.spill(o):
			if not Game.give(it):
				Game.toast.emit("No room for the %s from the chest" % ItemDB.display_name(it).to_lower())
		if k0 == "built":
			_doorway_gone(chunk, o)
		if Doors.is_door(o["t"]) and not Doors.is_mine(o) and npcs:
			# Breaking down someone else's door, in a town, is a crime if anyone sees.
			npcs.report_crime(chunk.position + o["p"], "vandalism", 0, "door")
		xp += clampf(Durability.max_hp(o) * 0.5, 3.0, 60.0)
	if k0 != "built" and xp > 0.0:
		Game.add_xp(xp, "Gathering" if how == "gathered" else ("Mining" if how == "mined" else "Salvaging"))
	if r["destroyed"]:
		# A destroyed cache spills whatever was still inside (stolen, in a town).
		var spilled := 0
		for it in o["st"].get("loot", []):
			if Game.give(it):
				spilled += int(ItemDB.def(it["type"]).get("value", 1)) * int(it.get("qty", 1))
		o["st"]["loot"] = []
		if o["st"].has("treasure"):
			Game.finish_treasure(int(o["st"]["treasure"]))
		if spilled > 0 and npcs and not Game.may_use_house_at(chunk.position + o["p"]):
			npcs.report_crime(chunk.position + o["p"], "theft", spilled, ObjectLibrary.label(o["t"]).to_lower())
		var k := ObjectLibrary.kind(o["t"])
		if k == "structure" or k == "trader":
			Game.toast.emit("Destroyed %s" % ObjectLibrary.label_of(o))
			if npcs:
				npcs.player_vandalised(chunk.position + o["p"], ObjectLibrary.label_of(o))
		chunk.remove_object(o["i"])
	else:
		Game.mark_chunk_dirty(chunk.data)
		if npcs and ObjectLibrary.kind(o["t"]) in ["structure", "trader"] and randf() < 0.15:
			npcs.player_vandalised(chunk.position + o["p"], "")

## A doorway brought down takes the door hanging in it along (back to your pack if it was yours).
func _doorway_gone(chunk: ChunkNode, o: Dictionary) -> void:
	if Doors.fits(BuildCatalog.id_of(o["t"])).is_empty():
		return
	var hit := Doors.door_at(streamer, chunk.position + o["p"])
	if hit.is_empty():
		return
	var dc: ChunkNode = hit["chunk"]
	var door: Dictionary = hit["obj"]
	if Doors.is_mine(door):
		Game.give(ItemDB.make(BuildCatalog.id_of(door["t"]), 1, 1.0, Game.origin_here("reclaimed", door["e"], dc.key)))
	dc.remove_object(door["i"])

# --- Vehicles ------------------------------------------------------------------------

## A stable name for what the player is focused on, to tell when the focus changes.
static func _focus_key(f: Dictionary) -> String:
	if f.has("vehicle") and is_instance_valid(f["vehicle"]):
		return "v%d" % int((f["vehicle"] as Vehicle).rec["id"])
	if f.has("body"):
		return "b" + String(f["body"])
	if f.has("chunk") and is_instance_valid(f["chunk"]):
		return "%s:%d%s" % [(f["chunk"] as ChunkNode).key, int(f["i"]), (":%d" % int(f["spot"])) if f.has("spot") else ""]
	return ""

## Sets the held vehicle down a few steps ahead.
func deploy_vehicle() -> bool:
	var it = held_item()
	if it == null or vehicles == null or not Vehicle.KINDS.has(it["type"]):
		return false
	var fwd := -global_transform.basis.z
	var at := global_position + Vector3(fwd.x, 0, fwd.z).normalized() * (2.0 + float(Vehicle.KINDS[it["type"]]["length"]) * 0.6)
	var v := vehicles.deploy(it, at, _yaw)
	if v == null:
		Game.toast.emit("There's no room for it here")
		return false
	Game.inventory.remove_at(selected, 1)
	Game.toast.emit("%s ready: [%s] to ride, hold to pack it up" % [Vehicle.label(v.kind), _key("interact")])
	return true

func mount(v: Vehicle) -> void:
	if v == null or v.rider != null:
		return
	vehicle = v
	v.rider = self
	_ride_yaw = v.rotation.y
	bob.reset()
	_apply_look()
	ray.add_exception(v)
	_shape.disabled = true
	velocity = Vector3.ZERO
	focus = {}
	_decon_on = {}
	swimming = false
	viewmodel.visible = false
	if body:
		body.hold(null)
	look_target_changed.emit("")
	_last_info = ""
	look_info_changed.emit({})
	_apply_view()
	Game.toast.emit("%s: [%s/%s] drive, [%s/%s] steer, [%s] %s, [%s] get off" % [Vehicle.label(v.kind),
		_key("move_forward"), _key("move_back"), _key("move_left"), _key("move_right"), _key("sprint"),
		"gallop" if v.kind == "horse" else "boost", _key("interact")])
	if v.flies():
		Game.toast.emit("Look where you want to fly. [%s/%s] climb and descend." % [_key("jump"), _key("crouch")])

func dismount(force := false) -> void:
	var v := vehicle
	if v == null:
		return
	if not force and is_instance_valid(v) and v.flies() and not v.is_on_floor():
		var g := vehicles.ground(v.global_position.x, v.global_position.z) if vehicles else NAN
		if is_nan(g) or v.global_position.y - g > 3.0:
			Game.toast.emit("Land first: hold %s to descend" % _key("crouch"))
			return
	vehicle = null
	if is_instance_valid(v):
		v.rider = null
		v.drive = Vector2.ZERO
		v.boosting = false
		ray.remove_exception(v)
		global_position = v.exit_point()
	_shape.disabled = noclip and fly
	velocity = Vector3.ZERO
	head.position = Vector3(0, STAND_H - 0.12, 0)
	bob.reset()
	_apply_look()
	if body:
		body.position = Vector3.ZERO
		body.rotation = Vector3(0, PI, 0)
	_apply_view()
	_refresh_held()
	_focus_t = 0.0

## Riding: the vehicle takes the move keys; you sit on it and look around freely.
func _ride(delta: float) -> void:
	var v := vehicle
	if not is_instance_valid(v):
		vehicle = null
		_shape.disabled = false
		return
	var input := Vector2.ZERO
	if not ui_open:
		input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	v.drive = input
	v.boosting = not ui_open and Input.is_action_pressed("sprint") and input.y > 0.1
	if v.flies():
		# A ship flies where you look; Jump climbs and Crouch descends.
		v.aim = -camera.global_transform.basis.z
		v.lift = 0.0 if ui_open else (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	else:
		# The view turns with the vehicle, so steering doesn't leave you looking sideways.
		var turned := wrapf(v.rotation.y - _ride_yaw, -PI, PI)
		_ride_yaw = v.rotation.y
		if absf(turned) < 1.0:
			_yaw += turned
			_apply_look()
	var seat := v.seat_transform()
	# Sitting: hips on the seat. The body faces the vehicle's way, whatever you look at.
	global_position = seat.origin - Vector3(0, SIT_HIPS, 0)
	if body:
		body.rotation = Vector3(0, PI + wrapf(v.rotation.y - _yaw, -PI, PI), 0)
		body.play("sit")
	head.position = head.position.lerp(Vector3(0, SIT_HIPS + 0.62, 0), clampf(delta * 10.0, 0.0, 1.0))
	steps.ride(v, delta)
	var t_water := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	underwater = camera.global_position.y < Water.surface_height(camera.global_position.x, camera.global_position.z, t_water) - 0.05
	if underwater:
		breath = maxf(0.0, breath - delta)
		if breath <= 0.0:
			_drown_t -= delta
			if _drown_t <= 0.0:
				_drown_t = 1.0
				Game.set_health(Game.health - 8.0, "You drowned")
	else:
		breath = minf(Game.stats.max_breath(), breath + delta * 6.0)
	_rest += delta
	if _rest > 0.8:
		Game.set_stamina(Game.stamina + 22.0 * delta * Game.stats.stamina_regen_mult())
	var text := "%d km/h   [%s] get off" % [roundi(absf(v.spd) * 3.6), _key("interact")]
	if v.flies() and v.leaving >= Vehicle.LEAVE_TIME:
		go_to_orbit()
		return
	if v.flies():
		var g := vehicles.ground(v.global_position.x, v.global_position.z) if vehicles else NAN
		text = "%d km/h   %s   [%s/%s] climb/descend   [%s] get off" % [roundi(v.velocity.length() * 3.6),
			"altitude %d m" % roundi(v.global_position.y - g) if not is_nan(g) else "", _key("jump"), _key("crouch"), _key("interact")]
		if v.at_ceiling:
			text = "%d km/h   Top of the sky: keep holding [%s] to leave for orbit   [%s] descend" % [roundi(v.velocity.length() * 3.6), _key("jump"), _key("crouch")]
	if text != _last_look:
		_last_look = text
		look_target_changed.emit(text)

var _ride_yaw := 0.0
const SIT_HIPS := 0.5 ## hip height above the feet in the sitting pose

## Up and out: the ship leaves the atmosphere for orbit. You'll land back above this spot
## (or wherever you warp to); that landing is also what's saved while you're in orbit.
func go_to_orbit() -> void:
	var v := vehicle
	if v == null or not is_instance_valid(v):
		return
	Game.landings[Game.planet] = Vector2(v.global_position.x, v.global_position.z)
	var spot := OrbitView.landing_spot()
	v.set_physics_process(false)
	v.rec["pos"] = spot
	var st := get_state()
	st["pos"] = spot
	st["riding"] = int(v.rec["id"])
	Game.pending_player_state = st
	set_physics_process(false)
	Game.player = null
	Game.toast.emit("Leaving the atmosphere")
	get_tree().change_scene_to_file.call_deferred("res://src/space/orbit.tscn")
