class_name FrameMend
extends CompositorEffect
## Runs frame_mend.glsl over each 3D frame after it is drawn and before the eye's
## exposure, glow and tonemap read it: a stray bad pixel (NaN, infinite or negative)
## made the auto exposure average hit its floor and open up all the way (any MSAA mode
## did it every frame; with TAA it happened now and then).

## 0 mends, 1 paints the bad pixels magenta instead (to find what makes them), 2 is off
## (capture --mend=show / --mend=off).
static var mode := 0
## 0 by day .. 1 in full night: how strongly the dim parts of the frame are graded as the
## dark-adapted eye sees them (Atmosphere sets it).
static var night := 0.0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd:
		RenderingServer.call_on_render_thread(_build)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shader.is_valid():
		# Freeing the shader frees the pipeline made from it.
		_rd.free_rid(_shader)

func _build() -> void:
	var f := load("res://src/env/frame_mend.glsl") as RDShaderFile
	if f == null:
		return
	_shader = _rd.shader_create_from_spirv(f.get_spirv())
	if _shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)

func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid() or mode == 2:
		return
	var rsb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if rsb == null:
		return
	var size := rsb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var push := PackedFloat32Array([size.x, size.y, 1.0 if mode == 1 else 0.0, night]).to_byte_array()
	for view in rsb.get_view_count():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = 0
		u.add_id(rsb.get_color_layer(view))
		var uset := UniformSetCacheRD.get_cache(_shader, 0, [u])
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
		_rd.compute_list_bind_uniform_set(cl, uset, 0)
		_rd.compute_list_set_push_constant(cl, push, push.size())
		_rd.compute_list_dispatch(cl, (size.x - 1) / 8 + 1, (size.y - 1) / 8 + 1, 1)
		_rd.compute_list_end()
