class_name Weather
extends Node3D
## The weather where the player is: what the climate (Climate) is heading for there,
## eased in over time, and everything that shows it. A child of the Atmosphere, so it runs
## after it each frame and adjusts the light, fog and sky the atmosphere has just set.
##
## - Sky: cloud cover and wind come from here (Atmosphere._update_wind reads them); under
##   overcast the sun dims and its shadows soften, rain and storm clouds darken.
## - Rain, snow and blowing dust: particles in a box round the camera that stop at roofs,
##   canopies and cave ceilings (a collision height field over the camera), rain throwing
##   splashes where it lands; heavy rain, snow and dust close the view in with fog.
## - Ground: wet and darkened by rain, puddles in the hollows with rings from the drops,
##   fresh snow settling on open level ground, all drying, draining and melting again
##   (global shader uniforms weather_*_g, read by weather_ground.gdshaderinc).
## - Thunderstorms: lightning bolts from the cloud base, a flash on the land and inside
##   the clouds, and the thunder after it, late by the distance.
## - Mist on calm damp mornings, lying in the low ground.
## Sound (rain, rain on the roof, thunder) is played by the Audio autoload from `rain`,
## `snow`, `storm` and the strikes.

enum Kind { CLEAR, FAIR, CLOUDY, OVERCAST, MIST, DRIZZLE, RAIN, STORM, SNOW, BLIZZARD, DUST, HAIL }
const NAMES := ["Clear", "Fair", "Cloudy", "Overcast", "Mist", "Drizzle", "Rain", "Thunderstorm", "Snow", "Blizzard", "Dust storm", "Hail"]
## Console and capture names for forcing a weather.
const KEYS := ["clear", "fair", "cloudy", "overcast", "mist", "drizzle", "rain", "storm", "snow", "blizzard", "dust", "hail"]
## What each forced weather sets (Climate.at's keys). temp only matters for snow.
const PRESETS := {
	Kind.CLEAR: {"cover": 0.05, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.15},
	Kind.FAIR: {"cover": 0.35, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.3},
	Kind.CLOUDY: {"cover": 0.65, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.4},
	Kind.OVERCAST: {"cover": 0.95, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.35},
	Kind.MIST: {"cover": 0.6, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 1.0, "dust": 0.0, "wind": 0.05},
	Kind.DRIZZLE: {"cover": 0.95, "precip": 0.25, "snow": 0.0, "storm": 0.0, "mist": 0.2, "dust": 0.0, "wind": 0.25},
	Kind.RAIN: {"cover": 1.0, "precip": 0.75, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.45},
	Kind.STORM: {"cover": 1.0, "precip": 1.0, "snow": 0.0, "storm": 1.0, "mist": 0.0, "dust": 0.0, "wind": 0.95},
	Kind.SNOW: {"cover": 1.0, "precip": 0.6, "snow": 1.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 0.2, "temp": -3.0},
	Kind.BLIZZARD: {"cover": 1.0, "precip": 1.0, "snow": 1.0, "storm": 0.0, "mist": 0.0, "dust": 0.0, "wind": 1.0, "temp": -9.0},
	Kind.DUST: {"cover": 0.55, "precip": 0.0, "snow": 0.0, "storm": 0.0, "mist": 0.0, "dust": 1.0, "wind": 0.9},
	Kind.HAIL: {"cover": 1.0, "precip": 0.9, "snow": 0.0, "storm": 0.8, "mist": 0.0, "dust": 0.0, "wind": 0.9, "hail": 1.0},
}

## The weather over the player right now, for HUD, sound and NPCs (null outside a world).
static var current: Weather

var atmosphere: Atmosphere
var climate: Climate
## A weather forced by the console or a capture (Kind), or -1 to follow the climate.
var forced := -1
## How long weather takes to change, as a multiple (0 jumps straight there: captures).
var ease_time := 1.0

# The weather now, eased toward the climate's targets. 0..1 except temp (degrees C).
var cover := 0.35
var precip := 0.0 ## how hard it is raining or snowing
var snow := 0.0 ## share of it falling as snow
var storm := 0.0
var mist := 0.0
var dust := 0.0
var wind := 0.3
var wind_dir := Vector2(0.8, 0.6)
var temp := 12.0
# The ground: how wet it is, how full the puddles are, how deep the fresh snow lies.
var wet := 0.0
var puddles := 0.0
var snow_cover := 0.0
var hail := 0.0 ## hail falling with the rain, 0..1
## The great storm blowing here, by name, or "" (Climate.great).
var great_name := ""
var kind := Kind.FAIR

var _target := {}
var _sample_t := 0.0
var _last_pos := Vector3.INF
var _rain: GPUParticles3D
var _flakes: GPUParticles3D
var _splash: GPUParticles3D
var _rain_mat: ShaderMaterial
var _flake_mat: ShaderMaterial
var _rain_proc: ShaderMaterial
var _flake_proc: ShaderMaterial
var _field: GPUParticlesCollisionHeightField3D
var _flash: DirectionalLight3D
var _bolts: Array = [] ## [MeshInstance3D, age, life, energy, direction]
var _bolt_mat: ShaderMaterial
var starfall: Starfall
var _strike_slot := -1
var _quality := 1
var _enabled := true

## Rain: box half size round the camera and how many drops fill it at full pour, by
## quality (weather_fx 0-2).
const RAIN_BOX := Vector3(22.0, 13.0, 22.0)
const RAIN_COUNT := [6000, 14000, 24000]
const SNOW_BOX := Vector3(26.0, 12.0, 26.0)
const SNOW_COUNT := [3000, 7000, 12000]
const SPLASH_COUNT := [0, 1024, 2048]

func _ready() -> void:
	current = self
	climate = Climate.new(Game.seed)
	_build_precip()
	_flash = DirectionalLight3D.new()
	_flash.name = "Lightning"
	_flash.light_color = Color(0.78, 0.83, 1.0)
	_flash.visible = false
	_flash.shadow_enabled = true
	_flash.shadow_blur = 0.5
	_flash.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_flash)
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = load("res://src/env/bolt.gdshader")
	starfall = Starfall.new()
	starfall.name = "Starfall"
	starfall.weather = self
	add_child(starfall)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			force(a.substr(10))

func _exit_tree() -> void:
	if current == self:
		current = null
	# Unhook the splashes and stop the particles before the nodes go, so the renderer
	# never steps a rain system whose sub-emitter has already been freed.
	_rain.sub_emitter = NodePath()
	for gp in [_rain, _flakes, _splash]:
		gp.emitting = false
	set_process(false)

func _apply_settings() -> void:
	_enabled = bool(Settings.get_value("weather"))
	_quality = clampi(int(Settings.get_value("weather_fx")), 0, 2)
	_rain.amount = RAIN_COUNT[_quality]
	_flakes.amount = SNOW_COUNT[_quality]
	_splash.amount = maxi(SPLASH_COUNT[_quality], 1)
	_rain_proc.set_shader_parameter("splash", 0.0 if _quality == 0 else 0.35)
	_flash.shadow_enabled = _quality >= 2
	# The finer the height field, the closer to the eaves the rain stops.
	_field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256 if _quality == 0 \
		else GPUParticlesCollisionHeightField3D.RESOLUTION_512

## Forces a weather by its key ("rain", "storm", ...), or "auto" to follow the climate.
## Returns false for an unknown key.
func force(key: String) -> bool:
	if key == "auto" or key == "":
		forced = -1
		starfall.forced = false
		return true
	if key == "starfall":
		starfall.forced = true
		return true
	var i := KEYS.find(key)
	if i < 0:
		return false
	forced = i
	_sample_t = 0.0
	return true

## Short words for what the sky is doing, for the HUD and for people to talk about.
func describe() -> String:
	var s: String = NAMES[kind]
	if kind == Kind.RAIN and precip < 0.45:
		s = "Light rain"
	elif kind == Kind.RAIN and precip > 0.85:
		s = "Heavy rain"
	elif kind == Kind.SNOW and precip < 0.4:
		s = "Light snow"
	if great_name != "" and kind in [Kind.RAIN, Kind.STORM, Kind.HAIL]:
		# "Great storm Morwen", "Great storm, the Harrower"
		s = ("Great storm, %s" if great_name.begins_with("the ") else "Great storm %s") % great_name
	return s

## The status icon for this weather (UITheme.status_icon), or "" for a plain sky.
func icon() -> String:
	match kind:
		Kind.DRIZZLE, Kind.RAIN, Kind.HAIL: return "rain"
		Kind.STORM: return "storm"
		Kind.SNOW, Kind.BLIZZARD: return "snow"
		Kind.MIST, Kind.DUST: return "fog"
	return ""

func _process(delta: float) -> void:
	if atmosphere == null or not is_instance_valid(atmosphere.target) or not is_inside_tree():
		return
	var p := atmosphere.target.global_position
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 0.5
		_target = _sample(p)
	# A long jump (respawn, portal, teleport) lands you in that place's weather.
	var jumped := _last_pos == Vector3.INF or p.distance_to(_last_pos) > 300.0
	_last_pos = p
	_ease(delta, jumped)
	_ground(delta, jumped)
	kind = _classify()
	_publish()
	_light()
	_precipitation(p)
	_lightning(delta, p)

func _sample(p: Vector3) -> Dictionary:
	var lf := atmosphere.field.landform_at(p.x, p.z)
	var ground := atmosphere.field.height(p.x, p.z)
	var c := climate.at(Climate.hours_of(Game.day), p.x, p.z, ground, lf, Planets.snow_line)
	if forced >= 0:
		var pr: Dictionary = PRESETS[forced]
		c["hail"] = 0.0
		for k in pr:
			c[k] = pr[k]
		if not pr.has("temp"):
			c["temp"] = maxf(float(c["temp"]), 6.0)
	elif not _enabled:
		# Weather off: fair skies, the clouds still come and go.
		for k in ["precip", "storm", "mist", "dust", "hail"]:
			c[k] = 0.0
		c["cover"] = minf(float(c["cover"]), 0.55)
		c["wind"] = minf(float(c["wind"]), 0.5)
	return c

func _ease(delta: float, jump: bool) -> void:
	if _target.is_empty():
		return
	var k := 1.0 if jump or ease_time <= 0.0 else 0.0
	# Clouds gather over a minute or so; rain sets in and eases off faster.
	cover = _toward(cover, _target["cover"], k, delta, 45.0)
	precip = _toward(precip, _target["precip"], k, delta, 20.0)
	snow = _toward(snow, _target["snow"], k, delta, 30.0)
	storm = _toward(storm, _target["storm"], k, delta, 25.0)
	mist = _toward(mist, _target["mist"], k, delta, 40.0)
	dust = _toward(dust, _target["dust"], k, delta, 20.0)
	hail = _toward(hail, float(_target.get("hail", 0.0)), k, delta, 8.0)
	great_name = String(_target.get("great", ""))
	wind = _toward(wind, _target["wind"], k, delta, 15.0)
	temp = _toward(temp, _target["temp"], k, delta, 30.0)
	var wd: Vector2 = _target["wind_dir"]
	wind_dir = wd if k > 0.0 else wind_dir.slerp(wd, clampf(delta / 20.0, 0.0, 1.0)).normalized()
	# Rain is only as heavy as the clouds are thick: no rain from a clear sky while easing.
	precip = minf(precip, smoothstep(0.55, 0.9, cover) * 1.2)

func _toward(v: float, want: float, jump: float, delta: float, sec: float) -> float:
	if jump > 0.0:
		return want
	return lerpf(v, want, clampf(delta / (sec * ease_time), 0.0, 1.0))

## The ground keeps the weather: rain wets it within a minute and fills the hollows over a
## few, then sun and wind dry it over several; snow settles over a few minutes and melts
## when it is above freezing.
func _ground(delta: float, jump: bool) -> void:
	var rain := precip * (1.0 - snow)
	var falling := precip * snow
	if jump or ease_time <= 0.0:
		# Arriving somewhere: the ground as the weather there would have left it.
		wet = clampf(rain * 1.5 + (cover - 0.6) * 0.5, 0.0, 1.0) if snow < 0.5 else 0.0
		puddles = clampf(rain * 1.2 - 0.15, 0.0, 1.0)
		snow_cover = clampf(falling * 1.4, 0.0, 1.0) if temp < 1.0 else 0.0
		return
	var sun := clampf(Atmosphere.sun_dir.y * 2.0, 0.0, 1.0) * (1.0 - cover * 0.8)
	var dry := (0.05 + sun * 0.6 + wind * 0.35) * (1.0 - rain) * (1.0 - mist * 0.7)
	wet = clampf(wet + delta * (rain / 40.0 - dry / 360.0), 0.0, 1.0)
	puddles = clampf(puddles + delta * ((rain - 0.25) / 150.0 - dry / 900.0 * (1.0 if rain < 0.25 else 0.0)), 0.0, 1.0)
	var melt := maxf(temp - 0.5, 0.0) * (1.0 + sun * 2.0)
	snow_cover = clampf(snow_cover + delta * ((falling + hail * 0.5) / 180.0 - melt / (900.0 if hail < 0.05 else 3000.0)), 0.0, 1.0)
	# Melting snow leaves the ground wet.
	if melt > 0.0 and snow_cover > 0.0:
		wet = minf(1.0, wet + delta * snow_cover * 0.01)

func _classify() -> int:
	if dust > 0.4:
		return Kind.DUST
	if precip > 0.12:
		if hail > 0.3 and snow < 0.5:
			return Kind.HAIL
		if snow > 0.5:
			return Kind.BLIZZARD if wind > 0.7 and precip > 0.6 else Kind.SNOW
		if storm > 0.4:
			return Kind.STORM
		return Kind.DRIZZLE if precip < 0.3 else Kind.RAIN
	if mist > 0.4:
		return Kind.MIST
	if cover > 0.85:
		return Kind.OVERCAST
	if cover > 0.5:
		return Kind.CLOUDY
	return Kind.FAIR if cover > 0.2 else Kind.CLEAR

func _publish() -> void:
	RenderingServer.global_shader_parameter_set("weather_wet_g", wet)
	RenderingServer.global_shader_parameter_set("weather_puddle_g", puddles)
	RenderingServer.global_shader_parameter_set("weather_snow_g", snow_cover)
	RenderingServer.global_shader_parameter_set("weather_rain_g", precip * (1.0 - snow) * (1.0 - atmosphere.underground))

const AERIAL := 0.35 ## the atmosphere's fog_aerial_perspective

## The light under the weather: overcast dims the sun and spreads its shadows; rain, snow
## and dust thicken the air. Runs after the atmosphere has set this frame's values.
func _light() -> void:
	var env := atmosphere.env
	var sky := atmosphere.sky_mat
	var oc := smoothstep(0.6, 1.0, cover)
	# Mist scatters a dawn's colour too: a soft grey-pink instead of a red sky over black land.
	var gloom := clampf(maxf(oc * 0.55 + storm * 0.45 + precip * 0.2, mist * 0.6), 0.0, 1.0)
	sky.set_shader_parameter("storm", gloom)
	sky.set_shader_parameter("dust", dust)
	var sun := atmosphere.sun
	sun.light_energy *= lerpf(1.0, 0.22, oc) * (1.0 - storm * 0.5) * (1.0 - dust * 0.6)
	# Thin cloud scatters the sun's disc into a wide soft source: shadows lose their edge.
	sun.light_angular_distance = lerpf(0.5, 4.0, oc)
	sun.shadow_blur = lerpf(1.2, 3.0, oc)
	atmosphere.moon.light_energy *= lerpf(1.0, 0.2, oc)
	if atmosphere.target.get("underwater"):
		return
	var daylight := smoothstep(-0.12, 0.25, Atmosphere.sun_dir.y)
	# Visibility: about 2 km in rain, under a kilometre in a storm, a hundred metres or
	# two in a blizzard or a dust storm.
	var rain := precip * (1.0 - snow)
	var thick := rain * 0.0016 + storm * 0.0018 + precip * snow * (0.004 + wind * 0.012) + dust * 0.014 + mist * 0.0035
	thick *= 1.0 - atmosphere.underground
	var k := clampf(thick * 400.0, 0.0, 1.0)
	# (Set once by the atmosphere, so set here from its own value every frame.)
	env.fog_aerial_perspective = AERIAL * (1.0 - k * 0.7)
	if thick > 0.0:
		var grey := Color(0.52, 0.55, 0.58) * lerpf(0.06, 1.0, daylight)
		# Mist in a low sun glows a pale rose; it lifts the land instead of burying it.
		var low := 1.0 - smoothstep(0.05, 0.35, Atmosphere.sun_dir.y)
		grey = grey.lerp(Color(0.62, 0.55, 0.56) * lerpf(0.25, 1.0, daylight), mist * low)
		var want := grey
		if dust > 0.0:
			want = grey.lerp(Color(0.62, 0.47, 0.3) * lerpf(0.08, 1.0, daylight), dust / maxf(dust + rain + mist, 0.001))
		env.fog_light_color = env.fog_light_color.lerp(want, k)
		env.fog_density += thick
		env.fog_sun_scatter *= 1.0 - k * 0.6
		env.volumetric_fog_density += (rain * 0.004 + mist * 0.02 + dust * 0.03 + precip * snow * 0.01) * (1.0 - atmosphere.underground)
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(want, k)
	# Mist lies in the low ground: thick a few metres up, clear above.
	env.fog_height = atmosphere.target.global_position.y - 2.0 + mist * 6.0
	env.fog_height_density = mist * 0.08 * (1.0 - atmosphere.underground)

func _build_precip() -> void:
	var pshader := load("res://src/env/precip_particles.gdshader") as Shader
	var dshader := load("res://src/env/precip.gdshader") as Shader
	_rain_proc = ShaderMaterial.new()
	_rain_proc.shader = pshader
	_rain_proc.set_shader_parameter("box_half", RAIN_BOX)
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = dshader
	_rain_mat.set_shader_parameter("streak", 0.75)
	_rain_mat.set_shader_parameter("thick", 0.01)
	_rain_mat.set_shader_parameter("reach", RAIN_BOX.x)
	_rain = _particles("Rain", _rain_proc, _rain_mat, RAIN_BOX)

	_flake_proc = ShaderMaterial.new()
	_flake_proc.shader = pshader
	_flake_proc.set_shader_parameter("box_half", SNOW_BOX)
	_flake_proc.set_shader_parameter("speed_jitter", 0.3)
	_flake_mat = ShaderMaterial.new()
	_flake_mat.shader = dshader
	_flake_mat.set_shader_parameter("streak", 0.0)
	_flake_mat.set_shader_parameter("thick", 0.014)
	_flake_mat.set_shader_parameter("reach", SNOW_BOX.x)
	_flakes = _particles("Snow", _flake_proc, _flake_mat, SNOW_BOX)

	# Splashes: a few droplets thrown up where a drop lands, gone in a fifth of a second.
	_splash = GPUParticles3D.new()
	_splash.name = "Splashes"
	_splash.emitting = false
	_splash.lifetime = 0.25
	_splash.amount = 1024
	_splash.local_coords = false
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3.UP
	sp.spread = 35.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.4
	sp.gravity = Vector3(0, -9.8, 0)
	sp.scale_min = 0.5
	sp.scale_max = 1.0
	_splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.025, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.8, 0.85, 0.9, 0.35)
	sm.albedo_texture = _drop_texture()
	sq.material = sm
	_splash.draw_pass_1 = sq
	_splash.visibility_aabb = AABB(-RAIN_BOX * 1.5, RAIN_BOX * 3.0)
	add_child(_splash)
	_rain.sub_emitter = _rain.get_path_to(_splash)

	# Over the camera: the height of the first thing a drop would hit.
	_field = GPUParticlesCollisionHeightField3D.new()
	_field.name = "RainCatch"
	_field.size = Vector3(SNOW_BOX.x * 2.0 + 4.0, 120.0, SNOW_BOX.z * 2.0 + 4.0)
	_field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_field.follow_camera_enabled = true
	_field.visible = false
	add_child(_field)

## A soft round droplet, for the splashes.
func _drop_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 16
	t.height = 16
	return t

func _particles(nm: String, proc: ShaderMaterial, draw: ShaderMaterial, box: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.name = nm
	gp.process_material = proc
	gp.local_coords = false
	gp.explosiveness = 1.0
	# The drops wrap round the box forever; a long life only redeals them now and then.
	gp.lifetime = 600.0
	gp.amount = 1000
	gp.fixed_fps = 0
	gp.interpolate = false
	gp.collision_base_size = 0.02
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(-box * 1.2, box * 2.4)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = draw
	gp.draw_pass_1 = q
	gp.emitting = false
	gp.visible = false
	add_child(gp)
	return gp

func _precipitation(p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var at := cam.global_position if cam != null else p
	var open := 1.0 - atmosphere.underground
	if atmosphere.target.get("underwater"):
		open = 0.0
	var rain := precip * (1.0 - snow) * open
	var flakes := precip * snow * open
	var specks := dust * open
	var daylight := smoothstep(-0.12, 0.25, Atmosphere.sun_dir.y)
	# Drops take the colour of the light around them: grey-white by day, near black at
	# night, white for a moment in a lightning flash.
	var lum := lerpf(0.03, 0.75, daylight) * lerpf(1.0, 0.6, storm) + _flash_now * 1.5
	var w3 := Vector3(wind_dir.x, 0.0, wind_dir.y) * wind
	# Rain: falls at about 9 m/s, slanted by the wind.
	var rfall := Vector3(0.0, -9.0, 0.0) + w3 * 7.0
	_rain_proc.set_shader_parameter("fall", rfall)
	_rain_proc.set_shader_parameter("density", clampf(rain * 1.1, 0.0, 1.0))
	_rain_mat.set_shader_parameter("fall_dir", rfall.normalized())
	_rain_mat.set_shader_parameter("tint", Color(lum * 1.15, lum * 1.2, lum * 1.25))
	_rain_mat.set_shader_parameter("opacity", 0.35 + 0.2 * rain)
	_show(_rain, rain > 0.01, at, rfall)
	# Snow drifts down at about a metre a second and goes where the wind takes it; dust
	# streams along it, barely falling.
	var snowing := flakes > 0.01
	# Hail (with the rain, in a great storm's heart) takes the flakes' place: hard white
	# pellets coming down fast and straight.
	var hailing := hail * open > 0.02 and not snowing
	var fl := Vector3(0.0, -1.1, 0.0) + w3 * 9.0 if snowing else Vector3(0.0, -0.25, 0.0) + w3 * 14.0
	if hailing:
		fl = Vector3(0.0, -15.0, 0.0) + w3 * 6.0
	_flake_proc.set_shader_parameter("fall", fl)
	_flake_proc.set_shader_parameter("sway", 0.0 if hailing else 0.5 if snowing else 1.2)
	_flake_proc.set_shader_parameter("density", clampf((hail * open * 0.7 if hailing else flakes if snowing else specks * 0.8) * 1.1, 0.0, 1.0))
	var fc := Color(lum, lum, lum * 1.03) if snowing or hailing else Color(0.7, 0.55, 0.38) * lum
	_flake_mat.set_shader_parameter("tint", fc * (1.25 if hailing else 1.0))
	_flake_mat.set_shader_parameter("thick", 0.011 if hailing else 0.014 if snowing else 0.006)
	_flake_mat.set_shader_parameter("opacity", 0.95 if hailing else 0.85 if snowing else 0.45)
	_show(_flakes, snowing or hailing or specks > 0.02, at, fl)
	_field.visible = _rain.visible or _flakes.visible

func _show(gp: GPUParticles3D, on: bool, at: Vector3, fall: Vector3) -> void:
	if on and not gp.visible:
		gp.visible = true
		gp.emitting = true
		gp.restart()
	elif not on and gp.visible:
		gp.visible = false
		gp.emitting = false
	if on:
		# The box sits a little upwind and above, where the drops in view come from.
		var lead := Vector3(fall.x, 0.0, fall.z) * -0.4
		gp.global_position = at + lead + Vector3(0.0, 2.0, 0.0)

# --- Lightning --------------------------------------------------------------------------

var _flash_now := 0.0
## Set to make a bolt strike in front of the camera at once (console, captures).
var strike_now := false

## Strikes come from a fixed grid of cells 2.5 km across round the player, each second of
## the world clock rolling for each cell: so the same strikes happen for everyone on a
## server, and a storm on the horizon flickers before it arrives.
const CELL := 2500.0

func _lightning(delta: float, p: Vector3) -> void:
	var secs := Game.day * Game.day_seconds
	var slot := int(floor(secs))
	if slot != _strike_slot:
		_strike_slot = slot
		var cx := int(floor(p.x / CELL))
		var cz := int(floor(p.z / CELL))
		for i in 9:
			var gx := cx + i % 3 - 1
			var gz := cz + floori(i / 3.0) - 1
			var hh := WHash.hash2(Game.seed ^ slot, gx, gz, 403)
			if WHash.to_unit(hh) > 0.02:
				continue
			var at := Vector2((gx + WHash.unit2(hh, 1, 0, 404)) * CELL, (gz + WHash.unit2(hh, 2, 0, 404)) * CELL)
			var st := _storm_at(at)
			if WHash.unit2(hh, 3, 0, 404) < st * 0.6:
				_strike(Vector3(at.x, 0.0, at.y), hh)
	if strike_now:
		# Somewhere in front of the camera, so you see it.
		strike_now = false
		var cam := get_viewport().get_camera_3d()
		var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
		var a := atan2(fwd.z, fwd.x) + randf_range(-0.35, 0.35)
		_strike(p + Vector3(cos(a), 0.0, sin(a)) * randf_range(500.0, 1500.0), randi())
	_flash_now = 0.0
	var dir := Vector3.ZERO
	for b in _bolts.duplicate():
		b[1] += delta
		var t: float = b[1]
		if t > b[2]:
			(b[0] as Node).queue_free()
			_bolts.erase(b)
			continue
		# A stroke and its return strokes: two or three bright pulses within a third of a
		# second, the channel glowing faintly between.
		var pulse := exp(-t * 18.0) + 0.7 * exp(-absf(t - 0.09) * 40.0) + 0.5 * exp(-absf(t - 0.21) * 35.0)
		var e: float = pulse * b[3]
		((b[0] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("energy", pulse)
		if e > _flash_now:
			_flash_now = e
			dir = b[4]
	_flash.visible = _flash_now > 0.01
	if _flash.visible:
		_flash.light_energy = _flash_now * 3.0
		_flash.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	atmosphere.sky_mat.set_shader_parameter("flash", _flash_now)
	if dir != Vector3.ZERO:
		atmosphere.sky_mat.set_shader_parameter("flash_dir", dir)

## How stormy it is at a point: where you are, what you see; elsewhere, the climate's.
func _storm_at(at: Vector2) -> float:
	var p := atmosphere.target.global_position
	if forced >= 0 or at.distance_to(Vector2(p.x, p.z)) < 600.0:
		return storm
	if not _enabled:
		return 0.0
	var lf := atmosphere.field.landform_at(at.x, at.y)
	var c := climate.at(Climate.hours_of(Game.day), at.x, at.y, 20.0, lf, Planets.snow_line)
	return float(c["storm"])

func _strike(at: Vector3, h: int) -> void:
	var p := atmosphere.target.global_position
	var d := Vector2(at.x - p.x, at.z - p.z).length()
	if d > CELL * 2.2:
		return
	at.y = atmosphere.field.height(at.x, at.z)
	var r := RandomNumberGenerator.new()
	r.seed = h
	var mi := MeshInstance3D.new()
	mi.mesh = Lightning.bolt_mesh(r, at, 700.0 + r.randf() * 400.0)
	var m := _bolt_mat.duplicate() as ShaderMaterial
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)
	# Brightness on the land falls off with distance; the flash lights it from the bolt.
	var energy := 1.0 / (1.0 + d / 700.0)
	var to := (at + Vector3(0.0, 500.0, 0.0) - p).normalized()
	_bolts.append([mi, 0.0, 0.45, energy, to])
	# Thunder: late by the distance (sound covers a kilometre in three seconds); close
	# strikes crack, far ones rumble.
	var delay := d / 343.0
	var near := d < 1200.0
	var vol := linear_to_db(clampf(1.4 / (1.0 + d / 900.0), 0.05, 1.0))
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			Audio.play("weather/thunder_near" if near else "weather/thunder_far", vol, 0.12, 1.0, "Ambience"))
