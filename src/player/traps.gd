class_name Traps
extends Node
## Bear traps and tripwires you set on the ground (a trap item's "trap": damage, radius,
## and hold seconds or a blast radius). Each springs once, on the first animal that
## steps within its radius, and is gone. A turret ("shots") instead fires at the nearest
## animal in range every second until its shots run out. Saved with the player.

const MAX := 12 ## traps you can have set at once
const CHECK := 0.25 ## seconds between looks for animals
const TURRET_EVERY := 4 ## checks between a turret's shots

signal sprung(blast: bool, at: Vector3)
signal fired(at: Vector3)

var player: Node
var _set: Array = [] ## [{type, pos, node}]
var _t := 0.0

func count() -> int:
	return _set.size()

func add(type: String, at: Vector3, shots := -1) -> void:
	var e := {"type": type, "pos": at, "node": null, "wait": 0}
	var tr: Dictionary = ItemDB.def(type).get("trap", {})
	if tr.has("shots"):
		e["shots"] = shots if shots >= 0 else int(tr["shots"])
	_set.append(e)
	_show(e)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or _set.is_empty() or player == null or player.fauna == null:
		return
	_t = CHECK
	for i in range(_set.size() - 1, -1, -1):
		var e: Dictionary = _set[i]
		var tr: Dictionary = ItemDB.def(e["type"]).get("trap", {})
		var hit: Array = player.fauna.creatures_near(e["pos"], float(tr.get("radius", 1.0)))
		if hit.is_empty():
			continue
		if e.has("shots"):
			e["wait"] = int(e["wait"]) - 1
			if int(e["wait"]) > 0:
				continue
			e["wait"] = TURRET_EVERY
			_shoot(e, tr, hit)
			if int(e["shots"]) > 0:
				continue
			if e["node"] != null and is_instance_valid(e["node"]):
				e["node"].queue_free()
		else:
			_spring(e, tr, hit)
		_set.remove_at(i)

## A turret's shot at the nearest of `hit`.
func _shoot(e: Dictionary, tr: Dictionary, hit: Array) -> void:
	var best = null
	for c in hit:
		if is_instance_valid(c) and (best == null or c.global_position.distance_to(e["pos"]) < best.global_position.distance_to(e["pos"])):
			best = c
	if best == null:
		return
	e["shots"] = int(e["shots"]) - 1
	player.fauna.player_hit(best, float(tr.get("damage", 20.0)))
	if e["node"] != null and is_instance_valid(e["node"]):
		var to: Vector3 = best.global_position - e["pos"]
		e["node"].rotation.y = atan2(-to.x, -to.z)
	fired.emit(e["pos"])

func _spring(e: Dictionary, tr: Dictionary, hit: Array) -> void:
	if e["node"] != null and is_instance_valid(e["node"]):
		e["node"].queue_free()
	if tr.has("blast"):
		player._blast(e["pos"] + Vector3(0, 0.4, 0), float(tr["blast"]), float(tr.get("damage", 50.0)), true)
		sprung.emit(true, e["pos"])
		return
	var c = hit[0]
	if c.has_method("hurt"):
		c.held_for = float(tr.get("hold", 0.0))
		player.fauna.player_hit(c, float(tr.get("damage", 50.0)))
	sprung.emit(false, e["pos"])

## A simple model at the trap's spot: an open iron jaw, or two stakes and a wire.
func _show(e: Dictionary) -> void:
	if player == null or not player.is_inside_tree():
		return
	var root := Node3D.new()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.22, 0.21, 0.2)
	iron.metallic = 0.7
	iron.roughness = 0.55
	if e.has("shots"):
		# A squat tripod with a boxy gun on top.
		for a in 3:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.02
			lm.bottom_radius = 0.02
			lm.height = 0.7
			leg.mesh = lm
			var ang := TAU * a / 3.0
			leg.position = Vector3(sin(ang) * 0.18, 0.3, cos(ang) * 0.18)
			leg.rotation = Vector3(cos(ang) * 0.4, 0, -sin(ang) * 0.4)
			leg.material_override = iron
			root.add_child(leg)
		var gun := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.22, 0.2, 0.6)
		gun.mesh = gm
		gun.position = Vector3(0, 0.7, -0.1)
		gun.material_override = iron
		root.add_child(gun)
	elif ItemDB.def(e["type"]).get("trap", {}).has("blast"):
		for x in [-0.9, 0.9]:
			var stake := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.025
			cm.bottom_radius = 0.035
			cm.height = 0.45
			stake.mesh = cm
			stake.position = Vector3(x, 0.2, 0)
			stake.material_override = iron
			root.add_child(stake)
		var wire := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 0.008, 0.008)
		wire.mesh = bm
		wire.position = Vector3(0, 0.25, 0)
		wire.material_override = iron
		root.add_child(wire)
	else:
		for side in [-1.0, 1.0]:
			var jaw := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.26
			tm.outer_radius = 0.3
			jaw.mesh = tm
			jaw.rotation = Vector3(0, 0, side * 0.35)
			jaw.position = Vector3(side * 0.12, 0.05, 0)
			jaw.scale = Vector3(1.0, 1.0, 0.8)
			jaw.material_override = iron
			root.add_child(jaw)
	player.get_tree().current_scene.add_child(root)
	root.global_position = e["pos"]
	e["node"] = root

func to_data() -> Array:
	var out: Array = []
	for e in _set:
		var p: Vector3 = e["pos"]
		var r := {"type": e["type"], "pos": [p.x, p.y, p.z]}
		if e.has("shots"):
			r["shots"] = int(e["shots"])
		out.append(r)
	return out

func from_data(d) -> void:
	for e in _set:
		if e["node"] != null and is_instance_valid(e["node"]):
			e["node"].queue_free()
	_set.clear()
	if not d is Array:
		return
	for r in d:
		if r is Dictionary and ItemDB.has(String(r.get("type", ""))) and r.get("pos") is Array and (r["pos"] as Array).size() == 3:
			add(String(r["type"]), Vector3(float(r["pos"][0]), float(r["pos"][1]), float(r["pos"][2])), int(r.get("shots", -1)))
