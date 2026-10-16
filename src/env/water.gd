class_name Water
extends MeshInstance3D
## A single large water surface that follows the player, so every hollow below sea level
## becomes a lake or river. Tint and glow blend with the local era.

const LEVEL := 0.0

var target: Node3D
var atmosphere: Atmosphere
var _mat: ShaderMaterial

func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 64
	pm.subdivide_depth = 64
	mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/env/water.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = LEVEL

func _process(_d: float) -> void:
	if target:
		var p := target.global_position
		position = Vector3(snappedf(p.x, 32.0), LEVEL, snappedf(p.z, 32.0))
	if atmosphere:
		var w := atmosphere.current_weights()
		_mat.set_shader_parameter("shallow", Color(0.16, 0.36, 0.38) * w[0] + Color(0.1, 0.45, 0.5) * w[1] + Color(0.12, 0.28, 0.36) * w[2])
		_mat.set_shader_parameter("glow_amount", w[1] * 0.8)
