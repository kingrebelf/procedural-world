class_name WorkProps
extends Node3D
## The tools of people's trades set out where they work (NPCRoles.props): an anvil by the
## smith's door, crates at the edge of a farmer's plot, a cauldron for the herbalist.
## Placed as the ground under each loads; nothing is saved.

var _pending: Array = [] ## [models, Vector2, yaw]
var _ground: Callable
var _t := 0.0
static var _meshes := {}

func setup(list: Array, ground: Callable) -> void:
	_pending = list.duplicate()
	_ground = ground
	name = "WorkProps"

func _process(delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	for e in _pending.duplicate():
		var at: Vector2 = e[1]
		var h: float = _ground.call(at.x, at.y)
		if is_nan(h):
			continue
		_pending.erase(e)
		var mi := MeshInstance3D.new()
		var key := str(e[0])
		if not _meshes.has(key):
			_meshes[key] = BuildCatalog.merge_models(e[0])
		mi.mesh = _meshes[key]
		mi.transform = Transform3D(Basis(Vector3.UP, float(e[2])), Vector3(at.x, h, at.y))
		add_child(mi)
