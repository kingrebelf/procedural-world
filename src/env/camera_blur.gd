class_name CameraBlur
extends CompositorEffect
## Motion blur (Settings "motion_blur", "motion_blur_strength"): camera_blur.glsl smears
## the frame along each pixel's motion on screen, as if the shutter stayed open for
## `strength` / 60 of a second, whatever the frame rate. It runs after FrameMend and
## before exposure, bloom and the upscaler. Nothing is drawn while the camera holds
## still, so standing and the capture tool's still shots cost nothing.

## Shutter time in 60ths of a second (0 is off). Set from Settings by Atmosphere.
static var strength := 0.0
## 1 paints the motion instead of smearing, 2 paints where the engine's motion vectors
## and the camera's own motion agree (green) or not (red) (tools/probe_camera_blur.gd).
static var debug := 0
## Seconds per frame to assume instead of the clock (tools rendering at a fixed frame
## rate, slower than real time); 0 uses the clock.
static var fixed_dt := 0.0
## The longest smear, as a fraction of the screen width.
const MAX_LEN := 0.03
## Nearer than this (metres) is the held item: never smeared, never smeared into.
const NEAR := 1.3

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _copy_shader: RID
var _copy_pipeline: RID
var _linear: RID
var _nearest: RID
var _tmp: RID
var _tmp_size := Vector2i.ZERO
## The camera last frame, per viewport drawing with this effect: {xf, proj, usec}.
var _prev := {}

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	access_resolved_depth = true
	enabled = false
	_rd = RenderingServer.get_rendering_device()
	if _rd:
		RenderingServer.call_on_render_thread(_build)

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	for r in [_tmp, _linear, _nearest, _shader, _copy_shader]:
		if r.is_valid():
			_rd.free_rid(r)

func _build() -> void:
	var f := load("res://src/env/camera_blur.glsl") as RDShaderFile
	var g := load("res://src/env/camera_blur_copy.glsl") as RDShaderFile
	if f == null or g == null:
		return
	_shader = _rd.shader_create_from_spirv(f.get_spirv())
	_copy_shader = _rd.shader_create_from_spirv(g.get_spirv())
	if not _shader.is_valid() or not _copy_shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	_copy_pipeline = _rd.compute_pipeline_create(_copy_shader)
	var s := RDSamplerState.new()
	s.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	s.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_linear = _rd.sampler_create(s)
	s.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	s.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest = _rd.sampler_create(s)

## The shutter time over this frame's time, or 0 to skip the frame: the camera held still,
## or jumped (a teleport, a respawn, a cut) so there is no motion to show.
static func shutter_scale(prev: Transform3D, cur: Transform3D, dt: float) -> float:
	if strength <= 0.0 or dt <= 0.0 or dt > 0.25:
		return 0.0
	var moved := prev.origin.distance_to(cur.origin)
	var turned := prev.basis.get_rotation_quaternion().angle_to(cur.basis.get_rotation_quaternion())
	if moved > 4.0 or turned > deg_to_rad(25.0):
		return 0.0
	if moved < 0.001 and turned < deg_to_rad(0.02) and debug == 0:
		return 0.0
	return minf(strength / 60.0 / dt, 1.5)

func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid() or strength <= 0.0:
		return
	var rsb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := render_data.get_render_scene_data()
	if rsb == null or sd == null or rsb.get_view_count() != 1:
		return
	var size := rsb.get_internal_size()
	# Small views (a minimap, a preview) are not the player's eye.
	if size.x < 320 or size.y < 200:
		return
	var key := rsb.get_instance_id()
	var xf := sd.get_cam_transform()
	var proj := sd.get_cam_projection()
	var now := Time.get_ticks_usec()
	var last: Dictionary = _prev.get(key, {})
	if last.is_empty():
		_prev[key] = {"xf": xf, "proj": proj, "usec": now, "vel": Vector3.ZERO}
		return
	var dt := fixed_dt if fixed_dt > 0.0 else (now - int(last["usec"])) / 1000000.0
	var last_xf: Transform3D = last["xf"]
	# The body (and the eye with it) moves in physics steps, so at a frame rate above
	# 60 one frame moves and the next does not: the eye's speed is averaged over a few
	# frames so the smear from walking stays steady. Turning is per frame already.
	var vel: Vector3 = last["vel"]
	if dt > 0.0 and last_xf.origin.distance_to(xf.origin) < 4.0:
		vel = vel.lerp((xf.origin - last_xf.origin) / dt, 1.0 - exp(-dt / 0.05))
	else:
		vel = Vector3.ZERO
	_prev[key] = {"xf": xf, "proj": proj, "usec": now, "vel": vel}
	var from := Transform3D(last_xf.basis, xf.origin - vel * dt)
	var k := shutter_scale(last_xf, xf, dt) if last_xf.origin.distance_to(xf.origin) >= 4.0 else shutter_scale(from, xf, dt)
	if k <= 0.0:
		return
	var lp: Projection = last["proj"]
	var reproject: Projection = lp * Projection(from.affine_inverse() * xf) * proj.inverse()
	var inv := proj.inverse()
	_ensure_tmp(size)

	var push := PackedFloat32Array()
	for col in [reproject.x, reproject.y, reproject.z, reproject.w]:
		push.append_array([col.x, col.y, col.z, col.w])
	push.append_array([inv.x.z, inv.y.z, inv.z.z, inv.w.z, inv.x.w, inv.y.w, inv.z.w, inv.w.w])
	var target := rsb.get_target_size()
	var out_scale := clampf(float(target.x) / float(size.x), 0.25, 4.0) if target.x > 0 else 1.0
	push.append_array([size.x, size.y, k, MAX_LEN, NEAR, float(debug), out_scale, 0.0])
	var push_bytes := push.to_byte_array()
	var copy_push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
	var groups := Vector2i((size.x - 1) / 8 + 1, (size.y - 1) / 8 + 1)

	var color := rsb.get_color_layer(0)
	var copy_set := UniformSetCacheRD.get_cache(_copy_shader, 0, [_image(0, color), _image(1, _tmp)])
	var blur_set := UniformSetCacheRD.get_cache(_shader, 0, [_image(0, color), _sampled(1, _linear, _tmp),
		_sampled(2, _nearest, rsb.get_depth_layer(0)), _sampled(3, _nearest, rsb.get_velocity_layer(0))])
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _copy_pipeline)
	_rd.compute_list_bind_uniform_set(cl, copy_set, 0)
	_rd.compute_list_set_push_constant(cl, copy_push, copy_push.size())
	_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, blur_set, 0)
	_rd.compute_list_set_push_constant(cl, push_bytes, push_bytes.size())
	_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
	_rd.compute_list_end()

func _ensure_tmp(size: Vector2i) -> void:
	if _tmp.is_valid() and _tmp_size == size:
		return
	if _tmp.is_valid():
		_rd.free_rid(_tmp)
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.width = size.x
	tf.height = size.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	_tmp = _rd.texture_create(tf, RDTextureView.new())
	_tmp_size = size

static func _image(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u

static func _sampled(binding: int, sampler: RID, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler)
	u.add_id(tex)
	return u
