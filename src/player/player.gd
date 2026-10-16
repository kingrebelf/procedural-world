class_name Player
extends CharacterBody3D
## First-person controller with tool use. Everything the player changes goes through
## ChunkNode/ChunkStreamer/Game so it is persisted.

signal look_target_changed(text: String)
signal selected_changed(slot: int)
signal used_tool(kind: String)

const WALK := 4.5
const SPRINT := 8.0
const CROUCH := 2.2
const JUMP := 5.2
const ACCEL := 10.0
const AIR_ACCEL := 2.5
const REACH := 3.2
const STAND_H := 1.75
const CROUCH_H := 1.15

var streamer: ChunkStreamer
var npcs: NPCManager
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var ray: RayCast3D
var selected := 0
var frozen := true ## Until the ground under us is loaded.
var ui_open := false

var _yaw := 0.0
var _pitch := 0.0
var _bob_t := 0.0
var _cooldown := 0.0
var _crouched := false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _shape: CollisionShape3D
var _last_look := ""
var _fall_from := 0.0

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
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 2400.0
	camera.current = true
	head.add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	ray.add_exception(self)
	camera.add_child(ray)
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	Settings.changed.connect(_apply_settings)
	Game.inventory.changed.connect(_refresh_held)
	_apply_settings()
	_refresh_held()

func _apply_settings() -> void:
	camera.fov = float(Settings.get_value("fov"))

func get_state() -> Dictionary:
	return {"pos": global_position, "yaw": _yaw, "pitch": _pitch, "slot": selected}

func set_state(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	_yaw = d.get("yaw", 0.0)
	_pitch = d.get("pitch", 0.0)
	select(d.get("slot", 0))
	_apply_look()

func select(i: int) -> void:
	selected = clampi(i, 0, Inventory.HOTBAR - 1)
	_refresh_held()
	selected_changed.emit(selected)

func held_item():
	return Game.inventory.get_slot(selected)

func _refresh_held() -> void:
	var it = held_item()
	viewmodel.show_item(it["type"] if it != null else "")

func _unhandled_input(event: InputEvent) -> void:
	if ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(Settings.get_value("mouse_sensitivity")) * 0.01
		_yaw -= event.relative.x * s
		var dy: float = event.relative.y * s * (-1.0 if Settings.get_value("invert_y") else 1.0)
		_pitch = clampf(_pitch - dy, -1.5, 1.5)
		_apply_look()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % Inventory.HOTBAR)
	for i in Inventory.HOTBAR:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select(i)
	if event.is_action_pressed("interact"):
		interact()
	if event.is_action_pressed("eat"):
		eat()

func _apply_look() -> void:
	rotation = Vector3(0, _yaw, 0)
	if head:
		head.rotation = Vector3(_pitch, 0, 0)

func _physics_process(delta: float) -> void:
	if frozen:
		if streamer != null and streamer.is_ready_at(global_position):
			frozen = false
			_snap_to_ground()
		else:
			return
	_cooldown = maxf(0.0, _cooldown - delta)
	var input := Vector2.ZERO
	if not ui_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_crouched = not ui_open and Input.is_action_pressed("crouch")
	var cap := _shape.shape as CapsuleShape3D
	var target_h := CROUCH_H if _crouched else STAND_H
	cap.height = move_toward(cap.height, target_h, delta * 4.0)
	_shape.position.y = cap.height * 0.5
	var speed := CROUCH if _crouched else (SPRINT if Input.is_action_pressed("sprint") and input.y < 0 else WALK)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var a := ACCEL if is_on_floor() else AIR_ACCEL
	hv = hv.lerp(dir * speed, clampf(a * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if velocity.y < -12.0:
			pass
		if not ui_open and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		velocity.y -= _gravity * delta
	var was_air := not is_on_floor()
	var vy := velocity.y
	move_and_slide()
	if was_air and is_on_floor() and vy < -11.0:
		Game.set_health(Game.health - (absf(vy) - 11.0) * 6.0)
	# Safety net: never fall through the world.
	if global_position.y < -200.0:
		_snap_to_ground()

	# Head bob and camera height.
	var eye := cap.height - 0.12
	var bob := Vector3.ZERO
	if is_on_floor() and hv.length() > 0.5 and Settings.get_value("head_bob"):
		_bob_t += delta * hv.length() * 1.6
		bob = Vector3(cos(_bob_t * 0.5) * 0.03, absf(sin(_bob_t)) * 0.045, 0)
	head.position = head.position.lerp(Vector3(0, eye, 0) + bob, clampf(delta * 12.0, 0.0, 1.0))
	viewmodel.sway(delta, hv.length() / SPRINT)

	if not ui_open and Input.is_action_pressed("use") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cooldown <= 0.0:
		use_held()
	_update_look_target()

func _snap_to_ground() -> void:
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(global_position)) if streamer else null
	if c == null:
		return
	var lx := global_position.x - c.key.x * ChunkGenerator.SIZE
	var lz := global_position.z - c.key.y * ChunkGenerator.SIZE
	var h := ChunkGenerator.height_at(c.data, lx, lz)
	if global_position.y < h + 0.1:
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
	if col and col.has_meta("chunk"):
		out["chunk"] = col.get_meta("chunk")
		if col.has_meta("obj"):
			out["obj"] = col.get_meta("obj")
	return out

func _update_look_target() -> void:
	var h := _hit_object()
	var text := ""
	if h.has("npc") and is_instance_valid(h["npc"]):
		var n: NPC = h["npc"]
		text = "[E] Talk to %s (%s)" % [n.rec["name"], n.rec["job"]]
	elif h.has("obj"):
		var o: Dictionary = (h["chunk"] as ChunkNode).get_object(h["obj"])
		var t: String = o["t"]
		match ObjectLibrary.kind(t):
			"cache":
				text = "[E] Open %s" % ObjectLibrary.label(t) if not o["st"].get("opened", false) else "%s (empty)" % ObjectLibrary.label(t)
			"trader":
				text = "[E] Trade with %s" % o["st"]["name"]
			"tree":
				text = "%s  [LMB] chop" % ObjectLibrary.label(t)
			"rock", "ore":
				text = "%s  [LMB] mine (%d left)" % [ObjectLibrary.label(t), o["st"].get("left", 0)]
	if text != _last_look:
		_last_look = text
		look_target_changed.emit(text)

func interact() -> void:
	var h := _hit_object()
	if h.has("npc") and is_instance_valid(h["npc"]):
		get_tree().call_group("dialogue_ui", "open_with", h["npc"])
		return
	if not h.has("obj"):
		return
	var chunk: ChunkNode = h["chunk"]
	var o: Dictionary = chunk.get_object(h["obj"])
	match ObjectLibrary.kind(o["t"]):
		"cache":
			if o["st"].get("opened", false):
				Game.toast.emit("It's empty.")
				return
			var loot: Array = o["st"]["loot"]
			var kept: Array = []
			for it in loot:
				if not Game.give(it):
					kept.append(it)
			o["st"]["loot"] = kept
			o["st"]["opened"] = kept.is_empty()
			Game.mark_chunk_dirty(chunk.data)
		"trader":
			Economy.tick(o["st"], Game.day)
			get_tree().call_group("trade_ui", "open_trader", o["st"], chunk)

func eat() -> void:
	var it = held_item()
	var idx := selected
	if it == null or ItemDB.def(it["type"]).get("kind", "") != "food":
		idx = -1
		for i in Inventory.SIZE:
			var s = Game.inventory.get_slot(i)
			if s != null and ItemDB.def(s["type"]).get("kind", "") == "food":
				idx = i
				it = s
				break
	if idx < 0:
		Game.toast.emit("No food.")
		return
	if Game.health >= 100.0:
		Game.toast.emit("You're not hungry.")
		return
	Game.inventory.remove_at(idx, 1)
	Game.set_health(Game.health + ItemDB.def(it["type"]).get("heal", 10))
	Game.toast.emit("Ate %s" % ItemDB.display_name(it))

func use_held() -> void:
	var it = held_item()
	var d: Dictionary = ItemDB.def(it["type"]) if it != null else {"mine": 0.15, "chop": 0.15, "damage": 2, "range": 2.0}
	var q: float = it.get("quality", 1.0) if it != null else 1.0
	if d.get("ranged", false):
		_fire(it, d)
		return
	_cooldown = 0.55
	viewmodel.swing()
	var h := _hit_object()
	if h.is_empty():
		used_tool.emit("miss")
		return
	if h.has("npc") and is_instance_valid(h["npc"]) and npcs:
		used_tool.emit("hit")
		npcs.player_hit(h["npc"], float(d.get("damage", 2)) * q)
		return
	if h.has("obj"):
		var chunk: ChunkNode = h["chunk"]
		var o: Dictionary = chunk.get_object(h["obj"])
		var t: String = o["t"]
		match ObjectLibrary.kind(t):
			"tree":
				o["st"]["hp"] = float(o["st"].get("hp", 3)) - float(d.get("chop", 0.2)) * q
				used_tool.emit("chop")
				if o["st"]["hp"] <= 0.0:
					var y: int = o["st"].get("yield", 3)
					Game.give(ItemDB.make(ObjectLibrary.YIELD[t], y, q, Game.origin_here("gathered", o["e"], chunk.key)))
					chunk.remove_object(o["i"])
				else:
					Game.mark_chunk_dirty(chunk.data)
			"rock", "ore":
				used_tool.emit("mine")
				o["st"]["progress"] = float(o["st"].get("progress", 0.0)) + float(d.get("mine", 0.2)) * q
				while o["st"]["progress"] >= 1.0 and o["st"]["left"] > 0:
					o["st"]["progress"] -= 1.0
					o["st"]["left"] -= 1
					Game.give(ItemDB.make(ObjectLibrary.YIELD[t], 1, q * randf_range(0.9, 1.1), Game.origin_here("mined", o["e"], chunk.key)))
				if o["st"]["left"] <= 0:
					chunk.remove_object(o["i"])
				else:
					Game.mark_chunk_dirty(chunk.data)
	elif h.has("chunk") and d.has("dig"):
		# Digging the ground itself: a persistent crater, and some stone.
		used_tool.emit("dig")
		var p: Vector3 = h["point"]
		streamer.dig(p, 1.6 + d["dig"] * 0.6, 0.35 * d["dig"] * q)
		if randf() < 0.5:
			var ck := ChunkStreamer.chunk_of(p)
			Game.give(ItemDB.make("stone", 1, 1.0, Game.origin_here("dug", -1, ck)))

func _fire(it: Dictionary, d: Dictionary) -> void:
	_cooldown = 0.22
	var ammo_t: String = d.get("ammo", "")
	var shots: int = it.get("charge", 0)
	if shots <= 0:
		if Game.inventory.remove_type(ammo_t, 1) == 0:
			Game.toast.emit("Needs a %s" % ItemDB.def(ammo_t)["name"])
			_cooldown = 0.6
			return
		shots = d.get("shots_per_ammo", 10)
	it["charge"] = shots - 1
	viewmodel.recoil()
	used_tool.emit("fire")
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * float(d.get("range", 60.0))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var hit := space.intersect_ray(q)
	var end: Vector3 = hit.get("position", to)
	viewmodel.tracer(end)
	if hit.has("collider") and hit["collider"].has_meta("npc") and npcs:
		npcs.player_hit(hit["collider"].get_meta("npc"), float(d.get("damage", 10)))
		return
	if hit.has("collider") and hit["collider"].has_meta("obj"):
		var chunk: ChunkNode = hit["collider"].get_meta("chunk")
		var o: Dictionary = chunk.get_object(hit["collider"].get_meta("obj"))
		if ObjectLibrary.kind(o["t"]) == "tree":
			o["st"]["hp"] = float(o["st"].get("hp", 3)) - 1.5
			if o["st"]["hp"] <= 0.0:
				Game.give(ItemDB.make(ObjectLibrary.YIELD[o["t"]], o["st"].get("yield", 3), 0.8, Game.origin_here("gathered", o["e"], chunk.key)))
				chunk.remove_object(o["i"])
			else:
				Game.mark_chunk_dirty(chunk.data)
