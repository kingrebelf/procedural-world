class_name EdgeField
extends Node3D
## The barrier at a finite world's edge (WorldBounds), seen only when you are right up
## against it: a panel of faint light on each side of the world you are near, centred on
## you, that fades out a few metres round where you stand. Out of sight from a distance.

const SHOW := 24.0 ## metres from the edge at which it starts to show
const W := 120.0 ## panel width and height (metres)
const H := 80.0

var target: Node3D
var _panels: Array = [] ## [x side, z side]
var _mat: ShaderMaterial

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/world/edge_field.gdshader")
	for i in 2:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(W, H)
		m.mesh = q
		m.material_override = _mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_panels.append(m)

func _process(_delta: float) -> void:
	if not WorldBounds.on() or target == null or not is_instance_valid(target):
		for m in _panels:
			m.visible = false
		return
	var p := target.global_position
	var h := WorldBounds.half()
	_mat.set_shader_parameter("near_pos", p)
	# x side: the wall at x = +-h, facing along x.
	var px: MeshInstance3D = _panels[0]
	px.visible = h - absf(p.x) < SHOW
	if px.visible:
		px.global_position = Vector3(signf(p.x) * h, p.y, p.z)
		px.rotation = Vector3(0, PI * 0.5, 0)
	var pz: MeshInstance3D = _panels[1]
	pz.visible = h - absf(p.z) < SHOW
	if pz.visible:
		pz.global_position = Vector3(p.x, p.y, signf(p.z) * h)
		pz.rotation = Vector3.ZERO
