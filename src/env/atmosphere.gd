class_name Atmosphere
extends Node3D
## Sun, moon, sky, fog and post-processing. Blends era atmosphere by the era weights at
## the player's position and runs the day/night cycle from Game.day.

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var field: WorldField
var target: Node3D

var _w := PackedFloat32Array([1, 0, 0])
var _sample_timer := 0.0
var _target_w := PackedFloat32Array([1, 0, 0])

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://src/env/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.2
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.1
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssil_radius = 6.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_bounce_feedback = 0.4
	env.ssr_max_steps = 48
	var we := WorldEnvironment.new()
	we.environment = env
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.3
	cam_attr.auto_exposure_min_sensitivity = 60.0
	cam_attr.auto_exposure_max_sensitivity = 800.0
	we.camera_attributes = cam_attr
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.12
	moon.shadow_enabled = false
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	field = WorldField.new(Game.seed)
	Settings.changed.connect(apply_settings)
	apply_settings()

func apply_settings() -> void:
	var gi := int(Settings.get_value("gi"))
	env.sdfgi_enabled = gi == Settings.GI.SDFGI
	env.ssil_enabled = gi == Settings.GI.SSIL
	env.ssao_enabled = bool(Settings.get_value("ssao"))
	env.ssr_enabled = bool(Settings.get_value("ssr"))
	env.glow_enabled = bool(Settings.get_value("glow"))
	var vf := int(Settings.get_value("volumetric_fog"))
	env.volumetric_fog_enabled = vf > 0
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if vf < 2 else 128, 64 if vf < 2 else 128)
	RenderingServer.environment_set_volumetric_fog_filter_active(vf >= 2)
	sun.directional_shadow_max_distance = float(Settings.get_value("shadow_distance"))
	var we := get_child(0) as WorldEnvironment
	(we.camera_attributes as CameraAttributesPractical).auto_exposure_enabled = bool(Settings.get_value("auto_exposure"))

## Era weights currently blended into the atmosphere (smoothed).
func current_weights() -> PackedFloat32Array:
	return _w

func _process(delta: float) -> void:
	if target != null:
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = 0.25
			var p := target.global_position
			_target_w = field.era_weights(p.x, p.z)
		for e in Eras.COUNT:
			_w[e] = lerpf(_w[e], _target_w[e], clampf(delta * 0.8, 0.0, 1.0))
	_update_time_of_day()

func _blend(arr: Array) -> Variant:
	var c = arr[0] * _w[0]
	for e in range(1, Eras.COUNT):
		c += arr[e] * _w[e]
	return c

func _update_time_of_day() -> void:
	var t := fposmod(Game.day, 1.0) # 0 = midnight, 0.25 = sunrise, 0.5 = noon
	var ang := (t - 0.25) * TAU
	# Sun path tilted toward the south.
	var dir := Vector3(cos(ang), sin(ang), 0.35).normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3(0, 0, 1) if absf(dir.y) > 0.99 else Vector3.UP)
	moon.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)
	var elev := dir.y
	var daylight := smoothstep(-0.12, 0.25, elev)
	var golden := 1.0 - smoothstep(0.0, 0.35, absf(elev))
	var sun_tint: Color = _blend(Eras.SUN_TINT)
	sun.light_color = sun_tint.lerp(Color(1.0, 0.62, 0.35), golden * 0.7)
	sun.light_energy = 2.4 * smoothstep(-0.05, 0.15, elev)
	sun.visible = elev > -0.1
	moon.visible = elev < 0.1
	moon.light_energy = 0.14 * (1.0 - daylight)

	var sky_tint: Color = _blend(Eras.SKY_TINT)
	sky_mat.set_shader_parameter("daylight", daylight)
	sky_mat.set_shader_parameter("zenith_day", sky_tint)
	sky_mat.set_shader_parameter("horizon_day", sky_tint.lerp(Color(0.85, 0.88, 0.92), 0.6))
	sky_mat.set_shader_parameter("era_fantasy", _w[Eras.FANTASY])
	sky_mat.set_shader_parameter("era_scifi", _w[Eras.SCIFI])
	sky_mat.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)

	var fog_c: Color = _blend(Eras.FOG_COLOR)
	var night_fog := Color(0.03, 0.04, 0.07)
	env.fog_light_color = fog_c.lerp(night_fog, 1.0 - daylight).lerp(Color(0.9, 0.55, 0.35), golden * 0.3 * daylight)
	var dens: float = _blend(Eras.FOG_DENSITY)
	env.fog_density = dens * 0.22
	env.volumetric_fog_density = dens * 1.4
	env.volumetric_fog_albedo = fog_c
	env.volumetric_fog_emission = Color(0.1, 0.25, 0.3) * _w[Eras.FANTASY] * 0.05
	env.ambient_light_energy = lerpf(0.2, 0.6, daylight)
	var night_glow := 0.6 + 0.8 * (1.0 - daylight)
	ChunkNode.ensure_shared()
	ChunkNode.terrain_material.set_shader_parameter("night_glow", night_glow)
	ChunkNode.grass_material.set_shader_parameter("night_glow", night_glow)
