class_name BoatNode
extends Node3D
## One boat on the water: its model riding the waves (pitch and roll from the swell
## under bow, stern and beam), sailing its loop or lying at anchor, leaving a wake. The
## crew stand at their stations aboard (NPCManager keeps them there through deck_xf).
## Moving boats heave to while someone is close, so you can come alongside and talk.
## A boat put in the water by Boats spawning code (pirates) can be steered with sail_to.

signal arrived(boat: BoatNode)

var site: Dictionary
var kind: String
var faction := "folk" ## "folk" or "pirate": who the crew are (NPC roles reads this)
var crew_nodes: Array = [] ## the NPC nodes aboard, while the crew is loaded
var body: CollisionObject3D
var model: Node3D
var deck := 0.3
var route_t := 0.0 ## seconds along the boat's loop
var held := 0.0 ## 0 sailing .. 1 hove to
var goal := Vector2.INF ## sail_to target (spawned boats)
var speed := 0.0
var players: Callable ## () -> Array of player positions near enough to matter

var _wake_t := 0.0
var _bob := Vector3.ZERO
var _yaw := 0.0
var _pos2 := Vector2.ZERO

func setup(s: Dictionary, t: float) -> BoatNode:
	site = s
	kind = s["boat"]
	faction = String(s.get("faction", "folk"))
	route_t = t
	name = "Boat_%s_%d_%d" % [kind, int(s["sx"]), int(s["sz"])]
	return self

func _ready() -> void:
	var d: Dictionary = Boats.KINDS[kind]
	# Anchored boats and rafts are still enough to stand on; the rest are moved by code.
	if float(d["moves"]) > 0.0 or site.has("spawned"):
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = false
		body = ab
	else:
		body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("boat", self)
	add_child(body)
	model = BoatModel.build(kind, int(site.get("seed", 1)), body)
	add_child(model)
	deck = BoatModel.deck_y(kind)
	var pose := Boats.pose_at(site, route_t)
	_pos2 = pose[0]
	_yaw = pose[1]
	if site.has("spawned"):
		_pos2 = site["center"]
		_yaw = float(site.get("yaw", 0.0))
	_place(0.0)

func _physics_process(delta: float) -> void:
	var d: Dictionary = Boats.KINDS[kind]
	var near := false
	if players.is_valid():
		for p in players.call():
			if (p as Vector3).distance_to(global_position) < float(d["len"]) * 0.5 + 12.0:
				near = true
	if goal != Vector2.INF:
		_steer(delta, d)
	elif float(d["moves"]) > 0.0:
		held = move_toward(held, 1.0 if near else 0.0, delta * 0.25)
		route_t += delta * (1.0 - held)
		var pose := Boats.pose_at(site, route_t)
		var to: Vector2 = pose[0]
		speed = to.distance_to(_pos2) / maxf(delta, 0.0001)
		_pos2 = to
		_yaw = lerp_angle(_yaw, float(pose[1]), clampf(delta * 2.0, 0.0, 1.0))
	else:
		var pose := Boats.pose_at(site, route_t)
		route_t += delta
		_yaw = float(pose[1])
		speed = 0.0
	_place(delta)
	_wake(delta, d)

## Spawned boats: head for `goal` at the kind's pace (a pirate closing in).
func _steer(delta: float, d: Dictionary) -> void:
	var to := goal - _pos2
	var top := maxf(float(d["moves"]), 3.0) * 1.4
	if to.length() < float(d["len"]) * 0.6 + 4.0:
		speed = move_toward(speed, 0.0, delta * 1.5)
		if speed < 0.05:
			goal = Vector2.INF
			arrived.emit(self)
	else:
		speed = move_toward(speed, top, delta * 1.0)
		var want := atan2(-to.x, -to.y)
		_yaw = lerp_angle(_yaw, want, clampf(delta * 0.5, 0.0, 1.0))
	_pos2 += Vector2(-sin(_yaw), -cos(_yaw)) * speed * delta
	site["center"] = _pos2
	site["yaw"] = _yaw

## Rides the swell: heave from the water under the middle, pitch and roll from the
## difference between bow and stern, port and starboard.
func _place(delta: float) -> void:
	var d: Dictionary = Boats.KINDS[kind]
	var L: float = d["len"]
	var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var c := _pos2
	var half := L * 0.4
	var beam := maxf(L * 0.14, 0.8)
	var hc := Water.surface_height(c.x, c.y, t)
	var hb := Water.surface_height(c.x + fwd.x * half, c.y + fwd.y * half, t)
	var hs := Water.surface_height(c.x - fwd.x * half, c.y - fwd.y * half, t)
	var hp := Water.surface_height(c.x + side.x * beam, c.y + side.y * beam, t)
	var hq := Water.surface_height(c.x - side.x * beam, c.y - side.y * beam, t)
	# Big hulls average the small waves out and answer slowly.
	var mass := clampf(L / 8.0, 0.5, 3.0)
	var want := Vector3((hb + hs + hp + hq + hc * 2.0) / 6.0, atan2(hb - hs, half * 2.0) / mass, atan2(hp - hq, beam * 2.0) / mass)
	_bob = want if delta <= 0.0 else _bob.lerp(want, clampf(delta * 3.0 / mass, 0.0, 1.0))
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_bob.y * 0.8) * Basis(Vector3.BACK, _bob.z * 0.8)
	global_transform = Transform3D(b, Vector3(c.x, _bob.x, c.y))

func _wake(delta: float, d: Dictionary) -> void:
	_wake_t -= delta
	if _wake_t > 0.0 or speed < 0.6:
		return
	_wake_t = clampf(1.4 / speed, 0.12, 0.6)
	var at := global_position + global_transform.basis.z * float(d["len"]) * 0.45
	Splashes.ring(Vector3(at.x, Water.surface_height(at.x, at.z, fmod(Time.get_ticks_msec() / 1000.0, 3600.0)), at.z), 0.8 + speed * 0.25)
	if speed > 3.0:
		var bow := global_position - global_transform.basis.z * float(d["len"]) * 0.45
		Splashes.splash(bow, clampf(speed / 25.0, 0.05, 0.3))

## Where crew station i is now: feet position and facing, in world space.
func deck_xf(i: int) -> Transform3D:
	var st: Array = BoatModel.stations(kind)
	if st.is_empty():
		return global_transform
	var s: Dictionary = st[i % st.size()]
	var local := Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["p"])
	return global_transform * local

## What crew station i is for: {p, yaw, pose, sit?} (BoatModel.STATIONS).
func station(i: int) -> Dictionary:
	var st: Array = BoatModel.stations(kind)
	return {"pose": "stand"} if st.is_empty() else st[i % st.size()]

## The boat's place on the water as a 2D point.
func pos2() -> Vector2:
	return _pos2

## Spawned boats: sail toward a point on the water (arrived fires when there).
func sail_to(target: Vector2) -> void:
	goal = target

## The crew's NPC nodes aboard (only while they are loaded near a player).
func crew() -> Array:
	return crew_nodes.filter(func(n): return is_instance_valid(n))
