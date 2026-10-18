extends Node
## Settings autoload ("Settings"): graphics presets, display, controls and audio.
## Stored in user://settings.cfg, applied live. Systems that own the relevant objects
## (environment, streamer, player) listen to `changed` and read values from here.

signal changed

const PATH := "user://settings.cfg"

enum AA { OFF, FXAA, SMAA, TAA, MSAA2, MSAA4, MSAA8 }
enum GI { OFF, SSIL, SDFGI }
enum Upscaler { BILINEAR, FSR1, FSR2 }

const PRESET_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]

## Quality keys a preset sets. "effects" (0-2) scales SSAO/SSIL/SDFGI sample counts and
## half-resolution GI; "clouds" 0 is a flat painted deck, 1-2 ray-marched volumetric clouds;
## "detail_distance" scales how far grass, clutter and small props are drawn;
## "mesh_detail" 0-3 is the LOD bias (Low switches to simpler meshes sooner); "weather_fx" 0-2
## is how many raindrops and snowflakes fall (and whether rain splashes) (Weather).
const PRESETS := {
	"Low": {"render_scale": 0.67, "upscaler": Upscaler.FSR2, "aa": AA.TAA, "shadows": 0, "shadow_distance": 120.0,
		"gi": GI.OFF, "ssao": false, "ssr": false, "volumetric_fog": 0, "glow": true, "view_distance": 3, "grass_density": 0.3,
		"effects": 0, "clouds": 0, "detail_distance": 0.6, "mesh_detail": 0, "sun_shafts": false, "weather_fx": 0},
	"Medium": {"render_scale": 0.77, "upscaler": Upscaler.FSR2, "aa": AA.TAA, "shadows": 1, "shadow_distance": 200.0,
		"gi": GI.SSIL, "ssao": true, "ssr": false, "volumetric_fog": 1, "glow": true, "view_distance": 4, "grass_density": 0.6,
		"effects": 1, "clouds": 1, "detail_distance": 0.8, "mesh_detail": 1, "sun_shafts": true, "weather_fx": 1},
	"High": {"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "aa": AA.TAA, "shadows": 2, "shadow_distance": 300.0,
		"gi": GI.SDFGI, "ssao": true, "ssr": true, "volumetric_fog": 1, "glow": true, "view_distance": 5, "grass_density": 1.0,
		"effects": 1, "clouds": 2, "detail_distance": 1.0, "mesh_detail": 2, "sun_shafts": true, "weather_fx": 1},
	"Ultra": {"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "aa": AA.TAA, "shadows": 3, "shadow_distance": 450.0,
		"gi": GI.SDFGI, "ssao": true, "ssr": true, "volumetric_fog": 2, "glow": true, "view_distance": 7, "grass_density": 1.4,
		"effects": 2, "clouds": 2, "detail_distance": 1.4, "mesh_detail": 3, "sun_shafts": true, "weather_fx": 2},
}

## FSR 2 quality modes (AMD's names) and the render scale each uses.
const FSR_MODES := ["Native AA", "Quality", "Balanced", "Performance", "Ultra Performance"]
const FSR_SCALES := [1.0, 0.67, 0.59, 0.5, 0.33]
const MESH_LOD := [6.0, 3.0, 1.0, 0.5] ## Viewport.mesh_lod_threshold per mesh_detail level

const DEFAULTS := {
	"preset": "High",
	"window_mode": 1, "resolution": "native", "vsync": 1, "fps_cap": 0, "fov": 90.0,
	"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "sharpness": 0.2,
	"aa": AA.TAA, "shadows": 2, "shadow_distance": 300.0, "gi": GI.SDFGI, "ssao": true, "ssr": true,
	"volumetric_fog": 1, "sun_shafts": true, "glow": true, "auto_exposure": true, "view_distance": 5, "grass_density": 1.0,
	"effects": 1, "clouds": 2, "detail_distance": 1.0, "mesh_detail": 2, "anisotropic": 2,
	"weather": true, "weather_fx": 1,
	"mouse_sensitivity": 0.12, "invert_y": false, "head_bob": true, "head_bob_strength": 1.0, "stick_sensitivity": 3.0,
	"motion_blur": true, "motion_blur_strength": 0.3, "film_grade": true,
	"master_volume": 0.8, "music_volume": 0.5, "sfx_volume": 0.8, "ambience_volume": 0.7,
	"show_fps": false, "menu_flyover": true,
}

const SHADOW_SIZES := [1024, 2048, 4096, 8192]
const SHADOW_FILTERS := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]

var values: Dictionary = DEFAULTS.duplicate()

func _ready() -> void:
	if not load_settings():
		_first_run()
	apply()

## The "fov" setting is the horizontal angle on a 16:9 screen, as most shooters give it;
## cameras take the vertical angle (and keep it, so a wider screen sees more at the sides).
static func vertical_fov(horizontal: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal) * 0.5) * 9.0 / 16.0))

func get_value(k: String):
	return values.get(k, DEFAULTS.get(k))

## Setting any preset-controlled key switches the preset to Custom.
func set_value(k: String, v, apply_now: bool = true) -> void:
	values[k] = v
	if PRESETS["High"].has(k):
		values["preset"] = "Custom"
	if apply_now:
		apply()
		save_settings()

func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	for k in PRESETS[name]:
		values[k] = PRESETS[name][k]
	values["preset"] = name
	apply()
	save_settings()

## Returns false when there is no settings file yet (first run).
func load_settings() -> bool:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return false
	for k in DEFAULTS:
		values[k] = cf.get_value("settings", k, DEFAULTS[k])
	return true

## First run: High, but upscale with FSR 2 on big screens so the game renders about a
## 1440p image (4K native is 2.25x the pixels and the main cost on fast GPUs).
func _first_run() -> void:
	for k in PRESETS["High"]:
		values[k] = PRESETS["High"][k]
	var scale := recommended_scale()
	if scale < 1.0:
		values["upscaler"] = Upscaler.FSR2
		values["render_scale"] = scale
		values["preset"] = "Custom"

## The FSR 2 scale that brings the screen down to roughly 1440p (1.0 at or below it).
func recommended_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var h := DisplayServer.screen_get_size().y
	if h <= 1600:
		return 1.0
	for i in FSR_SCALES.size():
		if h * FSR_SCALES[i] <= 1600.0:
			return FSR_SCALES[i]
	return 0.5

## Picks an FSR 2 quality mode: switches the upscaler to FSR 2 and sets the render scale.
func set_fsr_mode(i: int) -> void:
	values["upscaler"] = Upscaler.FSR2
	set_value("render_scale", FSR_SCALES[clampi(i, 0, FSR_SCALES.size() - 1)])

## The FSR 2 mode matching the current render scale, or -1.
func fsr_mode() -> int:
	if int(values["upscaler"]) != Upscaler.FSR2:
		return -1
	for i in FSR_SCALES.size():
		if absf(float(values["render_scale"]) - FSR_SCALES[i]) < 0.011:
			return i
	return -1

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.save(PATH)

static func resolutions() -> Array:
	return ["native", "1280x720", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]

func apply() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		match int(values["window_mode"]):
			0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if int(values["window_mode"]) == 0 and values["resolution"] != "native":
			var parts: PackedStringArray = String(values["resolution"]).split("x")
			DisplayServer.window_set_size(Vector2i(parts[0].to_int(), parts[1].to_int()))
		DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
			DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][int(values["vsync"])])
	Engine.max_fps = int(values["fps_cap"])

	var vp := get_viewport()
	var aa := int(values["aa"])
	var up := int(values["upscaler"])
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][up]
	vp.scaling_3d_scale = float(values["render_scale"])
	vp.fsr_sharpness = float(values["sharpness"])
	# FSR 2 is itself temporal AA, so TAA is redundant with it.
	vp.use_taa = aa == AA.TAA and up != Upscaler.FSR2
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == AA.FXAA else (Viewport.SCREEN_SPACE_AA_SMAA if aa == AA.SMAA else Viewport.SCREEN_SPACE_AA_DISABLED)
	vp.msaa_3d = {AA.MSAA2: Viewport.MSAA_2X, AA.MSAA4: Viewport.MSAA_4X, AA.MSAA8: Viewport.MSAA_8X}.get(aa, Viewport.MSAA_DISABLED)
	vp.mesh_lod_threshold = MESH_LOD[clampi(int(values["mesh_detail"]), 0, 3)]
	vp.anisotropic_filtering_level = clampi(int(values["anisotropic"]), 0, 4) as Viewport.AnisotropicFiltering

	# Screen-space effects and GI cost: sample counts and half resolution.
	var fx := clampi(int(values["effects"]), 0, 2)
	RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		RenderingServer.ENV_SSAO_QUALITY_HIGH][fx], fx < 2, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality([RenderingServer.ENV_SSIL_QUALITY_LOW, RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		RenderingServer.ENV_SSIL_QUALITY_HIGH][fx], fx < 2, 0.5, 4, 50.0, 300.0)
	RenderingServer.gi_set_use_half_resolution(fx < 2)
	RenderingServer.environment_set_sdfgi_ray_count([RenderingServer.ENV_SDFGI_RAY_COUNT_4, RenderingServer.ENV_SDFGI_RAY_COUNT_8,
		RenderingServer.ENV_SDFGI_RAY_COUNT_16][fx])
	RenderingServer.environment_set_sdfgi_frames_to_converge([RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES,
		RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES, RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES][fx])

	var sq := clampi(int(values["shadows"]), 0, 3)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[sq], true)
	# Lamps, hearths and torches share one atlas for their shadows.
	vp.positional_shadow_atlas_size = SHADOW_SIZES[sq]
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTERS[sq])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTERS[sq])

	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(values["master_volume"]), 0.0001)))
	changed.emit()
