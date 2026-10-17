class_name Atmosphere
extends Node3D
## Sun, moon, sky, fog and post-processing. Blends era atmosphere by the era weights at
## the player's position and runs the day/night cycle from Game.day.

var env: Environment
## Toward the sun (as the shaders' sun_dir_g), for scripts that need it.
static var sun_dir := Vector3.UP
## Toward the moon, which goes round a little behind the sun each day.
static var moon_dir := Vector3.DOWN
## Moon phase: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
static var moon_phase := 0.5
## Tools set this (0..1) to shoot a given phase; below 0 the phase follows the calendar.
static var moon_phase_override := -1.0
## Game days from one full moon to the next. The first night of a new world is full.
const LUNAR_DAYS := 8.0
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var field: WorldField
var target: Node3D

var _w := PackedFloat32Array([1, 0, 0])
var _sample_timer := 0.0
var _target_w := PackedFloat32Array([1, 0, 0])

## World wind, shared by grass, leaves, water and clouds through global shader uniforms.
var wind_strength := 0.3 ## 0 calm .. 1 gale
var wind_dir := Vector2(0.8, 0.6)
var _wind_noise := FastNoiseLite.new()
var _gust_noise := FastNoiseLite.new() ## one smooth octave: gusts build and fade over seconds
var _wind_time := 0.0 ## wind phase; speeds up with the wind but never jumps
var _gust := 0.0
var _cloud_drift := Vector2.ZERO
var _ground := 0.0 ## land height under the target, sampled with the era weights
## Set by the world: lets the atmosphere see how deep under the ground the target is.
var streamer: Node3D ## a ChunkStreamer (untyped: tests load this without the Game autoload)
## 0 in the open .. 1 deep in a cave: daylight, sky light and haze fade out underground.
var underground := 0.0
var _under_target := 0.0

func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://src/env/sky.gdshader")
	if ResourceLoader.exists("res://assets/textures/sky/night_stars.jpg"):
		sky_mat.set_shader_parameter("night_stars", load("res://assets/textures/sky/night_stars.jpg"))
	if ResourceLoader.exists("res://assets/textures/sky/moon.png"):
		sky_mat.set_shader_parameter("moon_tex", load("res://assets/textures/sky/moon.png"))
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
	env.fog_sun_scatter = 0.12
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.2
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	# Forward scattering: the haze lights up toward the sun, so where leaves and trunks
	# shade it the light falls in shafts.
	env.volumetric_fog_anisotropy = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.98
	env.adjustment_contrast = 1.1
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	# A little AO on direct light too, so things sit on the ground even in sunlight.
	env.ssao_light_affect = 0.15
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
	cam_attr.auto_exposure_scale = 0.2
	cam_attr.auto_exposure_min_sensitivity = 60.0
	# How far the eye may stop down in bright light: far enough that a snowfield or a white
	# beach in full sun keeps its shading instead of washing out (an ordinary sunny day never
	# reaches this limit).
	cam_attr.auto_exposure_max_sensitivity = 800.0
	we.camera_attributes = cam_attr
	_cam_attr = cam_attr
	# Mends stray bad pixels before the exposure reads the frame (FrameMend): one of them
	# washed the whole view out white under MSAA.
	var comp := Compositor.new()
	comp.compositor_effects = [FrameMend.new()]
	we.compositor = comp
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.5
	sun.light_volumetric_fog_energy = 1.4
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_pancake_size = 30.0
	sun.shadow_blur = 1.2
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	# Cool, but not the saturated blue that turned steel tools and snow into neon.
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.0
	# Moonlight casts soft shadows, so a moonlit night has shape. The moon only lights the
	# land once the sun is below the horizon, so there is never more than one shadowed
	# directional light (the cost of a night is the cost of a day).
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.4
	moon.light_angular_distance = 0.5
	moon.light_volumetric_fog_energy = 0.8
	moon.directional_shadow_blend_splits = true
	moon.directional_shadow_split_1 = 0.06
	moon.directional_shadow_split_2 = 0.18
	moon.directional_shadow_split_3 = 0.45
	moon.directional_shadow_fade_start = 0.85
	moon.directional_shadow_pancake_size = 30.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_shafts = MeshInstance3D.new()
	_shafts.name = "SunShafts"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_shafts.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/env/sun_shafts.gdshader")
	_shafts.material_override = sm
	# The quad is moved to cover the screen in its shader: never cull it.
	_shafts.extra_cull_margin = 16384.0
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shafts)

	field = WorldField.new(Game.seed)
	_wind_noise.seed = Game.seed & 0x7FFFFFFF
	_wind_noise.frequency = 1.0
	_wind_noise.fractal_octaves = 3
	_gust_noise.seed = (Game.seed + 77) & 0x7FFFFFFF
	_gust_noise.frequency = 1.0
	_gust_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
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
	_shafts.visible = bool(Settings.get_value("sun_shafts"))
	RenderingServer.environment_set_volumetric_fog_volume_size(64 if vf < 2 else 128, 64 if vf < 2 else 128)
	RenderingServer.environment_set_volumetric_fog_filter_active(vf >= 2)
	sun.directional_shadow_max_distance = float(Settings.get_value("shadow_distance"))
	# Low shadows: two cascades instead of four (half the shadow passes).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(Settings.get_value("shadows")) == 0 \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = sun.directional_shadow_max_distance
	moon.directional_shadow_mode = sun.directional_shadow_mode
	var cq := int(Settings.get_value("clouds"))
	sky_mat.set_shader_parameter("volumetric_clouds", cq > 0)
	# Ben (2026-10-17): quality first, so the high setting marches the clouds finely.
	sky_mat.set_shader_parameter("cloud_steps", 20 if cq == 1 else 40)
	sky_mat.set_shader_parameter("cloud_light_steps", 3 if cq == 1 else 6)
	var we := get_child(0) as WorldEnvironment
	(we.camera_attributes as CameraAttributesPractical).auto_exposure_enabled = bool(Settings.get_value("auto_exposure"))

var _cam_attr: CameraAttributesPractical
var _shafts: MeshInstance3D
## Scales the light shafts (tools try looks with it; 1 in the game).
var shaft_boost := 1.0

## Scales the open-air volumetric haze (tools try looks with it; 1 in the game).
var vfog_boost := 1.0

## Era weights currently blended into the atmosphere (smoothed).
func current_weights() -> PackedFloat32Array:
	return _w

func _process(delta: float) -> void:
	if target != null:
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = 0.25
			var p := target.global_position
			var ew := field.era_weights(p.x, p.z)
			_ground = maxf(field.height(p.x, p.z, ew), 0.0)
			_target_w = Eras.look(ew) # human worlds keep a natural sky over their outposts
			_under_target = _depth_factor(p)
		underground = move_toward(underground, _under_target, delta * 0.5)
		for e in Eras.COUNT:
			_w[e] = lerpf(_w[e], _target_w[e], clampf(delta * 0.8, 0.0, 1.0))
	_update_time_of_day()
	_update_wind(delta)
	_refresh_gi(delta)

## The global illumination (SDFGI) takes in the ground and buildings round you as you
## move. Built where you arrive before they have streamed in (a new game, a respawn, a
## portal), it leaves rooms lit as if open to the sky until you walk well away: so once
## they are in, it is built again.
var _gi_at := Vector3.INF
var _gi_stale := true
var _gi_wait := 1.0
var _gi_off := false

func _refresh_gi(delta: float) -> void:
	if _gi_off:
		_gi_off = false
		env.sdfgi_enabled = int(Settings.get_value("gi")) == Settings.GI.SDFGI
		return
	if target == null or streamer == null:
		return
	var p := target.global_position
	if _gi_at != Vector3.INF and p.distance_to(_gi_at) > 48.0:
		_gi_stale = true
		_gi_wait = 1.0
	_gi_at = p
	if not _gi_stale or not streamer.ready_round(p):
		return
	# Give the buildings of the last chunks in a moment to stand up.
	_gi_wait -= delta
	if _gi_wait > 0.0:
		return
	_gi_stale = false
	if env.sdfgi_enabled:
		env.sdfgi_enabled = false
		_gi_off = true

## How far under the actual ground (the chunk's own heights, so cave mouths count) p is,
## as 0..1: a few metres into a cave mouth is still lit, ten metres down is dark.
func _depth_factor(p: Vector3) -> float:
	if streamer == null:
		return 0.0
	var k := Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))
	var node = streamer.call("get_chunk", k)
	if node == null or not (node.data as Dictionary).has("cave"):
		return 0.0
	var depth := ChunkGenerator.height_at(node.data, p.x - k.x * ChunkGenerator.SIZE, p.z - k.y * ChunkGenerator.SIZE) - p.y
	return smoothstep(2.5, 10.0, depth)

func _update_wind(delta: float) -> void:
	# Weather drifts over in-game hours; gusts swell and die away over several seconds.
	var gt := Game.day * Game.DAY_SECONDS
	var base := 0.32 + _wind_noise.get_noise_1d(gt * 0.0006) * 0.75
	var want := smoothstep(0.0, 0.6, _gust_noise.get_noise_1d(gt * 0.045 + 500.0)) * 0.35 * (0.4 + base)
	# Rise slower than the noise can, and fall slower still.
	_gust = lerpf(_gust, want, clampf(delta * (0.6 if want > _gust else 0.3), 0.0, 1.0))
	wind_strength = clampf(base + _gust, 0.03, 1.0)
	_wind_time += delta * (1.0 + wind_strength * 1.3)
	RenderingServer.global_shader_parameter_set("wind_time", _wind_time)
	# The cloud field drifts with the wind (accumulated, so a change in wind never jumps it).
	_cloud_drift += wind_dir * delta * (6.0 + wind_strength * 22.0)
	RenderingServer.global_shader_parameter_set("cloud_drift", _cloud_drift)
	var ang := _wind_noise.get_noise_1d(gt * 0.0002 + 900.0) * TAU * 1.5
	wind_dir = Vector2(cos(ang), sin(ang))
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	# Cloud cover follows the weather: windy spells are cloudier.
	var cover := clampf(0.35 + _wind_noise.get_noise_1d(gt * 0.0004 + 300.0) * 0.6 + wind_strength * 0.25, 0.05, 0.95)
	sky_mat.set_shader_parameter("cloud_cover", cover)
	RenderingServer.global_shader_parameter_set("cloud_cover_g", cover)
	sun.shadow_opacity = lerpf(1.0, 0.75, cover)
	RenderingServer.global_shader_parameter_set("wind_dir", wind_dir)

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
	# The moon trails the sun by its phase: new with the sun, full opposite it (up all
	# night), first quarter six hours behind (high at dusk, down by midnight).
	moon_phase = moon_phase_override if moon_phase_override >= 0.0 \
		else fposmod(0.5 + (Game.day - 0.9) / LUNAR_DAYS, 1.0)
	var mang := ang - moon_phase * TAU
	var mdir := Vector3(cos(mang), sin(mang), 0.3).normalized()
	moon_dir = mdir
	moon.look_at_from_position(Vector3.ZERO, -mdir, Vector3(0, 0, 1) if absf(mdir.y) > 0.99 else Vector3.UP)
	# Share of the face that is lit, and how bright the moon is: a full moon is far
	# brighter than a half one (the face's shadows vanish when lit head on), but even a
	# thin crescent gives a little light.
	var lit_frac := (1.0 - cos(moon_phase * TAU)) * 0.5
	var moon_bright := 0.12 + 0.88 * pow(lit_frac, 1.6)
	var elev := dir.y
	RenderingServer.global_shader_parameter_set("sun_dir_g", dir)
	sun_dir = dir
	var daylight := smoothstep(-0.12, 0.25, elev)
	var golden := 1.0 - smoothstep(0.0, 0.35, absf(elev))
	var sun_tint: Color = _blend(Eras.SUN_TINT)
	sun.light_color = sun_tint.lerp(Color(1.0, 0.62, 0.35), golden * 0.7)
	# The low sun is still strong, and warmer: long, hard, golden shadows at dusk instead of
	# a flat grey wash.
	sun.light_energy = 2.0 * smoothstep(-0.05, 0.08, elev) * (1.0 + 0.2 * golden)
	sun.visible = elev > -0.1
	# Moonlight takes over as the sun's light goes (the sun is gone below -0.05), rises
	# with the moon and thins under cloud.
	var sun_down := 1.0 - smoothstep(-0.16, -0.05, elev)
	var moon_up := smoothstep(-0.02, 0.12, mdir.y)
	var cc0 = sky_mat.get_shader_parameter("cloud_cover")
	var cover0: float = cc0 if cc0 != null else 0.0
	# 0..1: how moonlit the night is (sky glow, clouds and the light itself go by it).
	var moonlit := sun_down * moon_up * moon_bright
	moon.light_energy = 0.45 * moonlit * lerpf(1.0, 0.55, smoothstep(0.5, 0.95, cover0))
	moon.shadow_opacity = lerpf(1.0, 0.6, cover0)
	moon.visible = moon.light_energy > 0.002
	# The eye may only brighten a dark scene so far: a night outdoors reads as night (cool
	# moonlight, warm windows) instead of dusk, but the land stays readable. Under a bright
	# moon it is held back more (a full moon read as dusk), on a moonless night it adapts
	# further. Underground it adapts fully to the torch.
	_cam_attr.auto_exposure_min_sensitivity = lerpf(lerpf(55.0, 105.0, moonlit), 60.0, maxf(daylight, underground))
	# The eye loses colour in the dark (rod vision): FrameMend greys and blues the dim
	# moonlit parts of the frame, leaving lamplight warm.
	FrameMend.night = (1.0 - daylight) * (1.0 - underground)

	var sky_tint: Color = _blend(Eras.SKY_TINT)
	sky_mat.set_shader_parameter("daylight", daylight)
	sky_mat.set_shader_parameter("stars_turn", t)
	sky_mat.set_shader_parameter("moon_dir", mdir)
	sky_mat.set_shader_parameter("moon_lit", moonlit)
	# In the golden hour the zenith deepens and the whole horizon warms to peach, not only
	# the sun's side: a low sun should read at a glance whichever way you look.
	sky_mat.set_shader_parameter("zenith_day", sky_tint.lerp(Color(0.24, 0.3, 0.52), golden * 0.45))
	sky_mat.set_shader_parameter("horizon_day", sky_tint.lerp(Color(0.85, 0.88, 0.92), 0.6).lerp(Color(1.0, 0.7, 0.52), golden * 0.5))
	sky_mat.set_shader_parameter("era_fantasy", _w[Eras.FANTASY])
	sky_mat.set_shader_parameter("era_scifi", _w[Eras.SCIFI])
	sky_mat.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)

	var fog_c: Color = _blend(Eras.FOG_COLOR)
	# Night haze: moonlit air is a dim blue-grey, so the far land fades instead of
	# vanishing into black.
	var night_fog := Color(0.045, 0.055, 0.085).lerp(Color(0.07, 0.09, 0.14), moonlit)
	env.fog_light_color = fog_c.lerp(night_fog, 1.0 - daylight).lerp(Color(0.9, 0.55, 0.35), golden * 0.3 * daylight)
	var dens: float = _blend(Eras.FOG_DENSITY)
	# High up (flying), thicker distance fog hides the edge of the streamed world. Height is
	# above the land below, so standing on a tall hill is not flying.
	var alt := clampf((target.global_position.y - _ground - 40.0) / 160.0, 0.0, 1.0) if target else 0.0
	env.fog_density = dens * 0.22 + alt * 0.0025
	env.fog_sky_affect = 0.2 + alt * 0.8
	# Light haze near you: thick volumetric fog washed the whole view out to white when
	# looking towards the sun. Under a low sun the air holds more of it (morning mist,
	# evening haze), so the light falls through the trees in shafts.
	var haze := 1.0 + 2.5 * (1.0 - smoothstep(0.08, 0.4, elev)) * daylight
	env.volumetric_fog_density = dens * 0.5 * haze * vfog_boost
	env.volumetric_fog_albedo = fog_c
	env.volumetric_fog_emission = Color(0.1, 0.25, 0.3) * _w[Eras.FANTASY] * 0.05
	# Light shafts: strongest under a low sun, gone under heavy cloud, at night and below
	# ground (and under water, below). Twice the old strength (render DN 58): at that the
	# rays through a gap in the canopy only just showed.
	var sm := _shafts.material_override as ShaderMaterial
	var cc = sky_mat.get_shader_parameter("cloud_cover")
	var cover: float = cc if cc != null else 0.0
	sm.set_shader_parameter("strength", 4.8 * shaft_boost * smoothstep(-0.02, 0.1, elev) * (1.0 + 0.8 * golden)
		* (1.0 - smoothstep(0.55, 0.9, cover)) * (1.0 - underground))
	sm.set_shader_parameter("tint", sun.light_color)
	if target and target.get("underwater"):
		sm.set_shader_parameter("strength", 0.0)
		# Under water you see a few metres into a lit blue-green murk, darker at night.
		var murk := Color(0.06, 0.2, 0.24).lerp(Color(0.01, 0.03, 0.05), 1.0 - daylight)
		env.fog_light_color = murk
		env.fog_density = 0.075
		env.fog_sky_affect = 1.0
		env.fog_sun_scatter = 0.3
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = Color(0.3, 0.6, 0.65)
	else:
		env.fog_sun_scatter = 0.12
	# Less sky fill in the golden hour, so the side away from the sun falls into shade.
	# At night the sky's light is starlight and airglow (and the moonlit sky's), weak but
	# enough to see the shapes of the land on the side away from the moon.
	# (Only in full night: dusk keeps its shaded side.) The night sky is too dark to light
	# much by itself, so part of the night fill is a flat cool starlight: on a moonless
	# night the land, the trees and the skyline still stand out as dim shapes.
	var dark := 1.0 - smoothstep(0.0, 0.2, daylight)
	env.ambient_light_sky_contribution = 1.0 - 0.6 * dark
	env.ambient_light_color = Color(0.14, 0.17, 0.25)
	env.ambient_light_energy = (lerpf(0.2, 0.6, daylight) + (0.55 + 0.35 * moonlit) * dark) * lerpf(1.0, 0.55, golden * smoothstep(0.0, 0.3, daylight)) \
		* lerpf(1.0, 0.05, underground)
	if underground > 0.0:
		var lit := 1.0 - underground
		sun.light_energy *= lit
		sun.visible = sun.visible and lit > 0.02
		moon.light_energy *= lit
		env.fog_density *= lerpf(1.0, 0.4, underground)
		env.volumetric_fog_density *= lit
	# The sunlight a window lets in as a beam (SunBeams), gone under heavy cloud.
	var beam := sun.light_color * (sun.light_energy * (1.0 - smoothstep(0.55, 0.9, cover)) if sun.visible else 0.0)
	RenderingServer.global_shader_parameter_set("sun_light_g", Vector3(beam.r, beam.g, beam.b))
	# Glowing plants and moss: a hint in the dark, not a lamp; you still want a torch.
	var night_glow := 0.08 + 0.4 * (1.0 - daylight)
	ChunkNode.ensure_shared()
	RenderingServer.global_shader_parameter_set("night_glow_g", night_glow)
	ChunkNode.terrain_material.set_shader_parameter("night_glow", night_glow)
	ChunkNode.terrain_material.set_shader_parameter("snow_line", Planets.snow_line)
	RenderingServer.global_shader_parameter_set("snow_line_g", Planets.snow_line)
	ChunkNode.terrain_material.set_shader_parameter("paved_roads", Eras.theme == "human")
	ChunkNode.terrain_material.set_shader_parameter("zone_rings", ZoneBorder.road_rings())
	ChunkNode.grass_material.set_shader_parameter("night_glow", night_glow)
