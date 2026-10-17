class_name Traps
extends Node
## Bear traps and tripwires you set on the ground (a trap item's "trap": damage, radius,
## and hold seconds or a blast radius). Each springs once, on the first animal that
## steps within its radius, and is gone. Saved with the player.

const MAX := 12 ## traps you can have set at once
const CHECK := 0.25 ## seconds between looks for animals

signal sprung(blast: bool, at: Vector3)

var player: Node
var _set: Array = [] ## [{type, pos, node}]
var _t := 0.0

func count() -> int:
	return _set.size()

func add(type: String, at: Vector3) -> void:
	var e := {"type": type, "pos": at, "node": null}
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
		_spring(e, tr, hit)
		_set.remove_at(i)

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
	if ItemDB.def(e["type"]).get("trap", {}).has("blast"):
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
		out.append({"type": e["type"], "pos": [p.x, p.y, p.z]})
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
			add(String(r["type"]), Vector3(float(r["pos"][0]), float(r["pos"][1]), float(r["pos"][2])))
