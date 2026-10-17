class_name RemotePlayers
extends Node3D
## The other players on a server, drawn on this world: each one's body walks where the
## server says they are, plays what they are doing, wears their armour, holds what they
## hold, and has their name over their head.

const DELAY := 0.12 ## seconds behind the newest position, to glide between updates
const NAME_RANGE := 40.0

var _bodies: Dictionary = {} ## peer -> RemotePlayers.Puppet

class Puppet extends Node3D:
	var peer := 0
	var body: HumanModel
	var tag: Label3D
	var _samples: Array = [] ## [msec, pos, yaw]
	var _look_v := -1
	var _shot := 0

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
		tag.position.y = 2.1
		tag.modulate = Color(1, 0.95, 0.85)
		add_child(tag)

	func push(rec: Dictionary) -> void:
		_samples.append([Time.get_ticks_msec(), rec["pos"], float(rec["yaw"])])
		while _samples.size() > 8:
			_samples.pop_front()
		if body == null:
			return
		var shot := int(rec.get("shot", 0))
		if shot != 0 and shot != _shot:
			body.play_once(String(rec["anim"]))
		elif shot == 0 and not body.busy():
			body.play(String(rec["anim"]), float(rec.get("speed", 1.0)))
		_shot = shot
		if int(rec.get("look_v", 0)) != _look_v:
			_look_v = int(rec.get("look_v", 0))
			body.wear(rec.get("equip", {}))
			var held: Dictionary = rec.get("held", {})
			var t := String(held.get("type", ""))
			body.hold(Viewmodel.prop_for(t, held) if t != "" else null)

	func _process(_delta: float) -> void:
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

func _ready() -> void:
	Net.peer_state.connect(_on_state)
	Net.players_changed.connect(_sync)
	_sync()

func _sync() -> void:
	for peer in _bodies.keys():
		if not Net.peers.has(peer) or int(Net.peers[peer]["planet"]) != Game.planet:
			_bodies[peer].queue_free()
			_bodies.erase(peer)

func _on_state(peer: int) -> void:
	var rec = Net.peers.get(peer)
	if rec == null:
		return
	if int(rec["planet"]) != Game.planet:
		if _bodies.has(peer):
			_bodies[peer].queue_free()
			_bodies.erase(peer)
		return
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
