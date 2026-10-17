class_name DoorNode
extends Node3D
## One built door in the scene: its leaves as their own meshes (not in the chunk's
## MultiMesh, so they can move), swinging or sliding to match the door's saved state,
## and, near the player, a collision box on each leaf that moves with it. The state
## itself lives in the chunk object (see Doors); call refresh() after changing it.

var chunk: ChunkNode
var obj_i := -1
var _entries: Array = []
var _slide := false
var _leaves: Array = [] ## Node3D per leaf, posed by Doors.leaf_xf
var _bodies: Array = []
var _amount := 0.0 ## 0 shut .. 1 open, as drawn

func setup(c: ChunkNode, o: Dictionary) -> void:
	chunk = c
	obj_i = int(o["i"])
	name = "Door_%d" % obj_i
	var d := BuildCatalog.def(BuildCatalog.id_of(o["t"]))
	_entries = d.get("models", [])
	_slide = bool(d["door"].get("slide", false))
	position = o["p"]
	rotation.y = o["r"]
	for e in _entries:
		var leaf := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = Doors.leaf_mesh(String(e[0]))
		mi.visibility_range_end = 900.0
		leaf.add_child(mi)
		add_child(leaf)
		_leaves.append(leaf)
	_amount = 1.0 if Doors.is_open(o) else 0.0
	_pose()
	set_process(false)

func _obj() -> Dictionary:
	return chunk.get_object(obj_i)

## Starts it moving toward its saved state.
func refresh() -> void:
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if Doors.is_open(_obj()) else 0.0
	_amount = move_toward(_amount, target, delta * Doors.SPEED)
	_pose()
	if is_equal_approx(_amount, target):
		set_process(false)

func _pose() -> void:
	var side := float(_obj()["st"].get("side", 1.0))
	# Ease in and out, like a door pushed and caught.
	var a := smoothstep(0.0, 1.0, _amount)
	for k in _leaves.size():
		(_leaves[k] as Node3D).transform = Doors.leaf_xf(_entries[k], _slide, a, side)

## Solid leaves only exist near the player, like every other object's collision.
func set_near(on: bool) -> void:
	for b in _bodies:
		b.queue_free()
	_bodies.clear()
	if not on:
		return
	for k in _leaves.size():
		var aabb := Doors.leaf_mesh(String(_entries[k][0])).get_aabb()
		var b := StaticBody3D.new()
		b.collision_layer = 2
		b.set_meta("chunk", chunk)
		b.set_meta("obj", obj_i)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.max(Vector3(0.08, 0.08, 0.08))
		cs.shape = box
		cs.position = aabb.get_center()
		b.add_child(cs)
		(_leaves[k] as Node3D).add_child(b)
		_bodies.append(b)
