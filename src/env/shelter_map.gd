class_name ShelterMap
extends Node3D
## Where the open sky is round the camera: the height of the highest thing over each
## patch of ground (roofs, floors above, canopies, or the ground itself), from a small
## orthographic camera looking straight down. Shaders read it (shelter_map_g, through
## climate_wear.gdshaderinc) to keep moss, dust and frost out of rooms and snow off
## floors under a roof, while the roof above gets them.
##
## Rendered once each time the camera has moved MOVE from the last middle, or every
## EVERY seconds for new building, unlit, with a plain environment (no GI, fog or
## shadows), so it costs a small extra pass now and then rather than every frame.

const RES := 512
const SIZE := 192.0 ## metres across (0.375 m a texel)
## Heights are kept as a fraction of RANGE metres below the camera (the shader's
## SHELTER_RANGE); nothing hit reads as RANGE down, the lowest there is.
const RANGE := 256.0
const ABOVE := 160.0 ## camera height over the target
const MOVE := 24.0
const EVERY := 8.0
## The depth quad's layer: only this camera draws it (its shader also hides it from any
## other camera).
const LAYER := 1 << 19

var target: Node3D
var _vp: SubViewport
var _cam: Camera3D
var _mid := Vector3(INF, 0, INF)
var _age := 0.0

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.use_hdr_2d = true # a float target: the heights must not be tonemapped or banded
	_vp.positional_shadow_atlas_size = 0
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_taa = false
	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_vp.scaling_3d_scale = 1.0
	_vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_vp.audio_listener_enable_3d = false
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = SIZE
	_cam.near = 0.5
	_cam.far = RANGE
	_cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0) # looking down, +x right, -z up the image
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = env
	_cam.cull_mask = 0xFFFFF
	_vp.add_child(_cam)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(SIZE * 1.1, SIZE * 1.1)
	quad.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/env/shelter_depth.gdshader")
	mat.set_shader_parameter("cam_size", SIZE)
	mat.set_shader_parameter("range", RANGE)
	quad.material_override = mat
	quad.layers = LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	quad.position = Vector3(0, 0, -1.0) # just past the near plane
	_cam.add_child(quad)
	RenderingServer.global_shader_parameter_set("shelter_map_g", _vp.get_texture())

func _process(delta: float) -> void:
	_age += delta
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = cam.global_position if cam != null else (target.global_position if target != null else Vector3.ZERO)
	if not _mid.is_finite() or Vector2(at.x - _mid.x, at.z - _mid.z).length() > MOVE or absf(at.y - _mid.y) > MOVE or _age > EVERY:
		# Snapped to whole texels, so the map doesn't shimmer as it follows.
		var t := SIZE / RES
		_mid = Vector3(snappedf(at.x, t), snappedf(at.y, 1.0), snappedf(at.z, t))
		_cam.global_position = _mid + Vector3(0, ABOVE, 0)
		# Sub-viewports draw before the main view in the same frame, so the new picture
		# and its new square arrive together.
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		RenderingServer.global_shader_parameter_set("shelter_rect_g",
			Vector4(_mid.x - SIZE * 0.5, _mid.z - SIZE * 0.5, SIZE, _mid.y + ABOVE - RANGE))
		_age = 0.0
