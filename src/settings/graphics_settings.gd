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

const PRESETS := {
	"Low": {"render_scale": 0.75, "upscaler": Upscaler.FSR1, "aa": AA.FXAA, "shadows": 0, "shadow_distance": 120.0,
		"gi": GI.OFF, "ssao": false, "ssr": false, "volumetric_fog": 0, "glow": true, "view_distance": 3, "grass_density": 0.3},
	"Medium": {"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "aa": AA.TAA, "shadows": 1, "shadow_distance": 200.0,
		"gi": GI.SSIL, "ssao": true, "ssr": false, "volumetric_fog": 1, "glow": true, "view_distance": 4, "grass_density": 0.6},
	"High": {"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "aa": AA.TAA, "shadows": 2, "shadow_distance": 300.0,
		"gi": GI.SDFGI, "ssao": true, "ssr": true, "volumetric_fog": 1, "glow": true, "view_distance": 5, "grass_density": 1.0},
	"Ultra": {"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "aa": AA.TAA, "shadows": 3, "shadow_distance": 450.0,
		"gi": GI.SDFGI, "ssao": true, "ssr": true, "volumetric_fog": 2, "glow": true, "view_distance": 7, "grass_density": 1.4},
}

const DEFAULTS := {
	"preset": "High",
	"window_mode": 1, "resolution": "native", "vsync": 1, "fps_cap": 0, "fov": 80.0,
	"render_scale": 1.0, "upscaler": Upscaler.BILINEAR, "sharpness": 0.2,
	"aa": AA.TAA, "shadows": 2, "shadow_distance": 300.0, "gi": GI.SDFGI, "ssao": true, "ssr": true,
	"volumetric_fog": 1, "glow": true, "auto_exposure": true, "view_distance": 5, "grass_density": 1.0,
	"mouse_sensitivity": 0.12, "invert_y": false, "head_bob": true,
	"master_volume": 0.8, "music_volume": 0.6, "sfx_volume": 0.8,
	"show_fps": false,
}

const SHADOW_SIZES := [1024, 2048, 4096, 8192]
const SHADOW_FILTERS := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]

var values: Dictionary = DEFAULTS.duplicate()

func _ready() -> void:
	load_settings()
	apply()

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

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in DEFAULTS:
		values[k] = cf.get_value("settings", k, DEFAULTS[k])

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
	vp.mesh_lod_threshold = 1.0

	var sq := clampi(int(values["shadows"]), 0, 3)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[sq], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTERS[sq])
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTERS[sq])

	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(values["master_volume"]), 0.0001)))
	changed.emit()
