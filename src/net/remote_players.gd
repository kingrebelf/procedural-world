class_name RemotePlayers
extends Node3D
## The other players on a server, drawn on this world: each one's body walks where the
## server says they are, plays what they are doing, wears their armour, holds what they
## hold, rides what they ride, and has their name over their head. Their bodies can be
## hit (PvP, when the server allows it), and their parked vehicles stand where they left
## them.

const DELAY := 0.12 ## seconds behind the newest position, to glide between updates
const NAME_RANGE := 40.0

var _bodies: Dictionary = {} ## peer -> RemotePlayers.Puppet
var _parked: Dictionary = {} ## peer -> {sig: the list drawn, nodes: [Node3D]}

class Puppet extends Node3D:
	var peer := 0
	var body: HumanModel
	var tag: Label3D
	var _samples: Array = [] ## [msec, pos, yaw]
	var _look_v := -1
	var _shot := 0
	var hitbox: AnimatableBody3D
	var ride := "" ## the kind of vehicle they are riding, or ""
	var _ride_model: Node3D
	var _animal: AnimalModel
	var _speed := 0.0
	var _last_pos := Vector3.INF
	var _dt := 0.0

	func setup(rec: Dictionary) -> void:
		if HumanModel.available():
			body = HumanModel.new()
			body.build(Net.look_for(rec["pid"]), Eras.MEDIEVAL, "")
			body.rotation.y = PI
			add_child(body)
		else:
			var mi := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.35
			cap.height = 1.75
			mi.mesh = cap
			mi.position.y = 0.875
			add_child(mi)
		tag = Label3D.new()
		tag.text = rec["name"]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.fixed_size = false
		tag.pixel_size = 0.004
		tag.font_size = 48
		tag.outline_size = 10
		tag.no_depth_test = false
		tag.render_priority = Creature.TAG_PRIORITY
		tag.outline_render_priority = Creature.TAG_PRIORITY - 1
		Creature.crisp_tag(tag)
		tag.position.y = 2.1
		tag.modulate = Color(1, 0.95, 0.85)
		add_child(tag)
		# Something to hit (like a townsperson's: layer 2, nothing collides into it).
		hitbox = AnimatableBody3D.new()
		hitbox.collision_layer = 2
		hitbox.collision_mask = 0
		hitbox.sync_to_physics = false
		hitbox.set_meta("remote_player", peer)
		hitbox.set_meta("remote_player_node", self)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.34
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		hitbox.add_child(cs)
		add_child(hitbox)

	## Riding (`kind`) or on foot (""): the vehicle is drawn under them, and they sit on it.
	func _set_ride(kind: String) -> void:
		if kind == ride:
			return
		ride = kind
		if _ride_model:
			_ride_model.queue_free()
			_ride_model = null
			_animal = null
		var seat := Vector3.ZERO
		if kind != "" and Vehicle.KINDS.has(kind):
			_ride_model = Vehicle.make_model(kind)
			add_child(_ride_model)
			var box := Vehicle._bounds(_ride_model)
			var d: Dictionary = Vehicle.KINDS[kind]
			if d.has("animal"):
				_animal = _ride_model.get_child(0)
				seat = Vector3(0, box.size.y * 0.66, 0.15)
			else:
				seat = Vector3(0, box.size.y * float(d.get("seat", 0.55)), float(d.get("seat_z", 0.25)))
		if body:
			body.position = seat
		hitbox.position = seat
		tag.position.y = 2.1 + seat.y
	func push(rec: Dictionary) -> void:
		_samples.append([Time.get_ticks_msec(), rec["pos"], float(rec["yaw"])])
		tag.modulate = Color(0.6, 1.0, 0.62) if Net.allied(String(rec["pid"])) else Color(1, 0.95, 0.85)
		while _samples.size() > 8:
			_samples.pop_front()
		if body == null:
			return
		var anim := String(rec["anim"])
		_set_ride(anim.substr(5) if anim.begins_with("ride:") else "")
		if ride != "":
			anim = "sit"
		var shot := int(rec.get("shot", 0))
		if shot != 0 and shot != _shot:
			body.play_once(anim)
		elif shot == 0 and not body.busy():
			body.play(anim, float(rec.get("speed", 1.0)))
		_shot = shot
		if int(rec.get("look_v", 0)) != _look_v:
			_look_v = int(rec.get("look_v", 0))
			body.wear(rec.get("equip", {}))
			var held: Dictionary = rec.get("held", {})
			var t := String(held.get("type", ""))
			body.hold(Viewmodel.prop_for(t, held) if t != "" else null)

	func _process(delta: float) -> void:
		_dt = delta
		if _samples.is_empty():
			return
		var t := Time.get_ticks_msec() - int(DELAY * 1000.0)
		var a: Array = _samples[0]
		var b: Array = _samples[_samples.size() - 1]
		for i in range(_samples.size() - 1):
			if int(_samples[i][0]) <= t and int(_samples[i + 1][0]) >= t:
				a = _samples[i]
				b = _samples[i + 1]
				break
		var span := float(int(b[0]) - int(a[0]))
		var f := clampf((t - int(a[0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
		if t > int(b[0]):
			f = 1.0
		var pa: Vector3 = a[1]
		var pb: Vector3 = b[1]
		# A jump of more than 30 m (teleport, respawn) snaps rather than slides.
		global_position = pb if pa.distance_to(pb) > 30.0 else pa.lerp(pb, f)
		rotation.y = lerp_angle(float(a[2]), float(b[2]), f)
		if _animal:
			# A ridden horse's gait from how fast it goes.
			if _last_pos != Vector3.INF and _dt > 0.0:
				_speed = lerpf(_speed, Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length() / _dt, 0.2)
			_animal.play("Idle" if _speed < 0.3 else ("Walk" if _speed < 3.5 else "Gallop"))
		_last_pos = global_position

func _ready() -> void:
	add_to_group("remote_players")
	Net.peer_state.connect(_on_state)
	Net.players_changed.connect(_sync)
	_sync()

func _sync() -> void:
	for peer in _bodies.keys():
		if not Net.peers.has(peer) or int(Net.peers[peer]["planet"]) != Game.planet:
			_bodies[peer].queue_free()
			_bodies.erase(peer)
	for peer in _parked.keys():
		if not Net.peers.has(peer):
			_park(peer, [])

## Draws a player's parked vehicles: [[kind, pos, yaw], ...] on this planet.
func _park(peer: int, list: Array) -> void:
	var e: Dictionary = _parked.get(peer, {"sig": [], "nodes": []})
	if e["sig"] == list:
		return
	for n in e["nodes"]:
		if is_instance_valid(n):
			n.queue_free()
	e = {"sig": list.duplicate(true), "nodes": []}
	for v in list:
		if v is Array and v.size() == 3 and Vehicle.KINDS.has(String(v[0])) and v[1] is Vector3:
			var m := Vehicle.make_model(String(v[0]))
			add_child(m)
			m.global_position = v[1]
			m.rotation.y = float(v[2])
			e["nodes"].append(m)
	if list.is_empty():
		_parked.erase(peer)
	else:
		_parked[peer] = e

## Other players' bodies within `radius` of `at` (blasts).
func near(at: Vector3, radius: float) -> Array:
	var out: Array = []
	for p in _bodies.values():
		if is_instance_valid(p) and (p.global_position as Vector3).distance_to(at) <= radius:
			out.append(p)
	return out

func _on_state(peer: int) -> void:
	var rec = Net.peers.get(peer)
	if rec == null:
		return
	if int(rec["planet"]) != Game.planet:
		if _bodies.has(peer):
			_bodies[peer].queue_free()
			_bodies.erase(peer)
		return
	var veh: Array = []
	for v in rec.get("veh", []):
		if v is Array and v.size() == 4 and int(v[3]) == Game.planet:
			veh.append([v[0], v[1], v[2]])
	_park(peer, veh)
	if not _bodies.has(peer):
		var p := Puppet.new()
		p.peer = peer
		p.name = "Player_%d" % peer
		add_child(p)
		p.setup(rec)
		p.global_position = rec["pos"]
		_bodies[peer] = p
	_bodies[peer].push(rec)

func _process(_delta: float) -> void:
	var me = Game.player
	if me == null or not is_instance_valid(me):
		return
	for p in _bodies.values():
		p.tag.visible = (p.global_position as Vector3).distance_to(me.global_position) < NAME_RANGE

## The body of a player, for whoever needs to aim at them (PvP comes later).
func body_of(peer: int) -> Node3D:
	return _bodies.get(peer)
