class_name Player
extends CharacterBody3D
## First-person controller with tool use. Everything the player changes goes through
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
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var ray: RayCast3D
var builder: Builder
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
var _last_info := ""
var _fall_from := 0.0
var swimming := false
var underwater := false
var breath := BREATH
var _drown_t := 0.0

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
	builder = Builder.new()
	builder.player = self
	add_child(builder)
	Settings.changed.connect(_apply_settings)
	Game.inventory.changed.connect(_refresh_held)
	_apply_settings()
	_refresh_held()

func _apply_settings() -> void:
	camera.fov = float(Settings.get_value("fov"))

func get_state() -> Dictionary:
	# The world saves from its own _exit_tree, after the player has already left the
	# tree; the player is a direct child of the (untransformed) world, so position is
	# the world position.
	var pos := global_position if is_inside_tree() else position
	return {"pos": pos, "yaw": _yaw, "pitch": _pitch, "slot": selected}

func set_state(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	_yaw = d.get("yaw", 0.0)
	_pitch = d.get("pitch", 0.0)
	select(d.get("slot", 0))
	_apply_look()

func yaw() -> float:
	return _yaw

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
	if event.is_action_pressed("hotbar_prev"):
		select((selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR)
	elif event.is_action_pressed("hotbar_next"):
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
	if not ui_open:
		# Controller look: right stick, with a response curve for fine aim near centre.
		var lv := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lv.length() > 0.0:
			var k := float(Settings.get_value("stick_sensitivity")) * delta * lv.length()
			_yaw -= lv.x * k
			_pitch = clampf(_pitch - lv.y * k * (-1.0 if Settings.get_value("invert_y") else 1.0), -1.5, 1.5)
			_apply_look()
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

	# Water: float with the chest at the surface; dive with crouch, rise with jump.
	var t_water := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var surface := Water.surface_height(global_position.x, global_position.z, t_water)
	swimming = surface - global_position.y > 1.15
	underwater = camera.global_position.y < Water.surface_height(camera.global_position.x, camera.global_position.z, t_water) - 0.05
	if swimming:
		hv = hv.lerp(dir * SWIM * (1.4 if Input.is_action_pressed("sprint") else 1.0), clampf(3.0 * delta, 0.0, 1.0))
		var target_y := surface - 1.35
		var vy_want := (target_y - global_position.y) * 2.2
		if not ui_open and Input.is_action_pressed("crouch"):
			vy_want = -2.2
		elif not ui_open and Input.is_action_pressed("jump"):
			vy_want = 2.5
		velocity.y = lerpf(velocity.y, vy_want, clampf(4.0 * delta, 0.0, 1.0))
		velocity.x = hv.x
		velocity.z = hv.z
		move_and_slide()
	else:
		var a := ACCEL if is_on_floor() else AIR_ACCEL
		hv = hv.lerp(dir * speed, clampf(a * delta, 0.0, 1.0))
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor():
			if not ui_open and Input.is_action_just_pressed("jump"):
				velocity.y = JUMP
		else:
			velocity.y -= _gravity * delta
		var was_air := not is_on_floor()
		var vy := velocity.y
		move_and_slide()
		if was_air and is_on_floor() and vy < -11.0:
			Game.set_health(Game.health - (absf(vy) - 11.0) * 6.0)
	# Breath.
	if underwater:
		breath = maxf(0.0, breath - delta)
		if breath <= 0.0:
			_drown_t -= delta
			if _drown_t <= 0.0:
				_drown_t = 1.0
				Game.set_health(Game.health - 8.0)
				Game.toast.emit("Drowning!")
	else:
		breath = minf(BREATH, breath + delta * 6.0)
	# Safety net: never fall through the world.
	if global_position.y < -200.0:
		_snap_to_ground()

	# Head bob and camera height.
	var eye := cap.height - 0.12
	var bob := Vector3.ZERO
	if is_on_floor() and not swimming and hv.length() > 0.5 and Settings.get_value("head_bob"):
		_bob_t += delta * hv.length() * 1.6
		bob = Vector3(cos(_bob_t * 0.5) * 0.03, absf(sin(_bob_t)) * 0.045, 0)
	head.position = head.position.lerp(Vector3(0, eye, 0) + bob, clampf(delta * 12.0, 0.0, 1.0))
	viewmodel.sway(delta, hv.length() / SPRINT)

	if not ui_open and Input.is_action_pressed("use") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.using_pad) and _cooldown <= 0.0:
		use_held()
	builder.update()
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
	if col and col.has_meta("creature"):
		out["creature"] = col.get_meta("creature")
	if col and col.has_meta("chunk"):
		out["chunk"] = col.get_meta("chunk")
		if col.has_meta("obj"):
			out["obj"] = col.get_meta("obj")
	return out

func _update_look_target() -> void:
	var h := _hit_object()
	var text := ""
	var info := {}
	if builder.active():
		text = "[LMB] Place %s   [Q] Rotate" % BuildCatalog.def(builder.piece_id())["name"]
		info = builder.info()
	elif h.has("creature") and is_instance_valid(h["creature"]):
		var cr: Creature = h["creature"]
		var drops: Array = []
		for d in cr.p["drops"]:
			drops.append("%s x%d" % [ItemDB.def(d[0])["name"], d[1]])
		info = {"title": cr.label(), "sub": "Wild animal  ·  %s" % String(cr.p["temper"]).capitalize(),
			"lines": ["Drops: " + ", ".join(drops), "Hunt with a sword, axe or pistol"], "hp": cr.hp / float(cr.p["hp"]), "icon": cr.p["drops"][0][0]}
	elif h.has("npc") and is_instance_valid(h["npc"]):
		var n: NPC = h["npc"]
		text = "[E] Talk to %s" % n.rec["name"].split(" ")[0]
		var r := int(n.rec.get("rel", 0))
		info = {"title": n.rec["name"], "sub": "%s of %s" % [String(n.rec["job"]).capitalize(), n.settlement["name"]],
			"lines": ["Feels %s toward you (%d)" % ["hostile" if r <= -40 else ("wary" if r < -5 else ("neutral" if r < 15 else "friendly")), r],
				"Mood: %s" % n.rec.get("mood", "calm"), "Doing: %s" % n.action.replace("_", " ")],
			"hp": float(n.rec.get("hp", 100.0)) / 100.0}
	elif h.has("obj"):
		var o: Dictionary = (h["chunk"] as ChunkNode).get_object(h["obj"])
		var t: String = o["t"]
		var k := ObjectLibrary.kind(t)
		var mat := Durability.material(t)
		match k:
			"cache":
				text = "[E] Open %s" % ObjectLibrary.label(t) if not o["st"].get("opened", false) else "%s (empty)" % ObjectLibrary.label(t)
			"trader":
				text = "%s's stall" % o["st"]["name"]
			"built":
				text = "[LMB] take down (returns the piece)"
			_:
				text = "[LMB] %s" % ("chop" if mat == "wood" or mat == "fungus" else "break")
		var lines: Array = ["Yields: " + Durability.describe_yields(o)] if k != "built" else ["Built by you on day %d" % (int(o["st"].get("day", 0)) + 1)]
		if k == "cache" and not o["st"].get("opened", false):
			lines.append("Contains: %d item stacks" % o["st"].get("loot", []).size())
		lines.append("Best tool: %s" % (Durability.BEST_TOOL[mat] if k != "built" else "Builder's Hammer (one hit)"))
		var held = held_item()
		var d: Dictionary = ItemDB.def(held["type"]) if held != null else Durability.FIST
		var hits := ceili(Durability.health_left(o) / maxf(0.001, Durability.power(d, mat) * (held.get("quality", 1.0) if held != null else 1.0)))
		lines.append("About %d hits with %s" % [hits, ItemDB.display_name(held) if held != null else "bare hands"])
		info = {"title": ObjectLibrary.label_of(o), "sub": "%s  ·  %s" % [Durability.MATERIAL_NAMES[mat], Eras.NAMES[o["e"]] if o["e"] >= 0 else ("Yours" if k == "built" else "")],
			"lines": lines, "hp": Durability.health_left(o) / Durability.max_hp(o), "icon": Durability.yields(o)[0][0]}
	elif h.has("chunk"):
		var held = held_item()
		var can_dig: bool = held != null and ItemDB.def(held["type"]).has("dig")
		info = {"title": "Ground", "sub": "Terrain", "lines": ["Dig with a pickaxe or drill for Stone" if not can_dig else "[LMB] dig: leaves a permanent crater"], "icon": "stone"}
	if text != _last_look:
		_last_look = text
		look_target_changed.emit(text)
	var key := str(info)
	if key != _last_info:
		_last_info = key
		look_info_changed.emit(info)

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
	if it != null and BuildCatalog.is_piece_item(it["type"]):
		_cooldown = 0.25
		if builder.place():
			used_tool.emit("build")
		return
	var d: Dictionary = ItemDB.def(it["type"]) if it != null else Durability.FIST
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
	if h.has("creature") and is_instance_valid(h["creature"]) and fauna:
		used_tool.emit("hit")
		fauna.player_hit(h["creature"], float(d.get("damage", 2)) * q)
		return
	if h.has("npc") and is_instance_valid(h["npc"]) and npcs:
		used_tool.emit("hit")
		npcs.player_hit(h["npc"], float(d.get("damage", 2)) * q)
		return
	if h.has("obj"):
		var chunk: ChunkNode = h["chunk"]
		var o: Dictionary = chunk.get_object(h["obj"])
		var mat := Durability.material(o["t"])
		used_tool.emit("chop" if mat == "wood" or mat == "fungus" else "mine")
		if d.get("build", false) and ObjectLibrary.kind(o["t"]) == "built":
			# The builder's hammer takes your own pieces down in one blow.
			damage_object(chunk, o, Durability.health_left(o) + 1.0, 1.0)
			return
		damage_object(chunk, o, Durability.power(d, mat) * q, q)
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
	if hit.has("collider") and hit["collider"].has_meta("creature") and fauna:
		fauna.player_hit(hit["collider"].get_meta("creature"), float(d.get("damage", 10)))
		return
	if hit.has("collider") and hit["collider"].has_meta("npc") and npcs:
		npcs.player_hit(hit["collider"].get_meta("npc"), float(d.get("damage", 10)))
		return
	if hit.has("collider") and hit["collider"].has_meta("obj"):
		var chunk: ChunkNode = hit["collider"].get_meta("chunk")
		var o: Dictionary = chunk.get_object(hit["collider"].get_meta("obj"))
		damage_object(chunk, o, Durability.power({"mine": 0.6, "chop": 0.6, "damage": d.get("damage", 10)}, Durability.material(o["t"])), 0.8)

## One hit on a world object: damage, pay out yields as they are earned, destroy at zero.
func damage_object(chunk: ChunkNode, o: Dictionary, amount: float, quality: float) -> void:
	var r := Durability.hit(o, amount)
	var how := "reclaimed" if ObjectLibrary.kind(o["t"]) == "built" else "gathered" if ObjectLibrary.kind(o["t"]) == "tree" else ("salvaged" if ObjectLibrary.kind(o["t"]) in ["structure", "cache", "trader", "marker"] else "mined")
	for y in r["items"]:
		Game.give(ItemDB.make(y[0], y[1], quality * randf_range(0.92, 1.08), Game.origin_here(how, o["e"], chunk.key)))
	if r["destroyed"]:
		# A destroyed cache spills whatever was still inside.
		for it in o["st"].get("loot", []):
			Game.give(it)
		o["st"]["loot"] = []
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
