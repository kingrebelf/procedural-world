class_name Benchmark
extends Node
## In-game performance test (console: bench). Measures the GPU and CPU frame time at the
## current view, then switches one feature off at a time and measures again, so the
## table shows what each feature costs on this PC. Nothing is saved: every setting is
## put back afterwards. The table is shown on screen, copied to the clipboard and
## written to user://benchmark.txt.

const SETTLE := 45 ## frames to wait after a change (TAA/GI history settles)
const SAMPLE := 90 ## frames averaged per test

var world: Node
var quit_when_done := false
var _panel: Label
var _saved: Dictionary

func _ready() -> void:
	_panel = Label.new()
	_panel.add_theme_font_size_override("font_size", 15)
	_panel.add_theme_color_override("font_color", Color(1, 1, 1))
	_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_panel.add_theme_constant_override("outline_size", 5)
	_panel.position = Vector2(30, 120)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(_panel)
	add_child(layer)
	_run.call_deferred()

## One test: a name, and a callable that switches its feature on (true) or off (false).
func _tests() -> Array:
	var atm: Atmosphere = world.atmosphere
	var t := []
	t.append(["Render at 67% (FSR 2 Quality)", func(off: bool):
		Settings.values["upscaler"] = Settings.Upscaler.FSR2 if off else _saved["upscaler"]
		Settings.values["render_scale"] = 0.67 if off else _saved["render_scale"]
		Settings.apply()])
	for k in [["gi", "Global illumination", Settings.GI.OFF], ["ssr", "Reflections (SSR)", false], ["ssao", "Ambient occlusion", false],
			["volumetric_fog", "Volumetric fog", 0], ["clouds", "Volumetric clouds", 0], ["glow", "Bloom", false]]:
		var key: String = k[0]
		var off_v = k[2]
		t.append([k[1], func(off: bool):
			Settings.values[key] = off_v if off else _saved[key]
			Settings.apply()])
	t.append(["Effects quality Low", func(off: bool):
		Settings.values["effects"] = 0 if off else _saved["effects"]
		Settings.apply()])
	var ang := atm.sun.light_angular_distance
	t.append(["Soft sun shadow edges (PCSS)", func(off: bool): atm.sun.light_angular_distance = 0.0 if off else ang])
	var sd := atm.sun.directional_shadow_max_distance
	t.append(["Shadow distance 150 m", func(off: bool): atm.sun.directional_shadow_max_distance = 150.0 if off else sd])
	t.append(["Sun shadows", func(off: bool): atm.sun.shadow_enabled = not off])
	t.append(["Sky lighting updates", func(off: bool):
		atm.env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL if off else Sky.PROCESS_MODE_REALTIME])
	t.append(["Grass", func(off: bool):
		for c in world.streamer.chunks.values():
			for ch in c.get_children():
				if ch.name.begins_with("Grass"):
					ch.visible = not off])
	t.append(["Ground clutter and small props", func(off: bool):
		for c in world.streamer.chunks.values():
			for ch in c.get_children():
				if ch is GeometryInstance3D and ch.has_meta("range") and not ch.name.begins_with("Grass"):
					ch.visible = not off])
	t.append(["Trees and buildings", func(off: bool):
		for c in world.streamer.chunks.values():
			for ch in c.get_children():
				if ch is MultiMeshInstance3D and not ch.has_meta("range") and ch.name.begins_with("MM_"):
					ch.visible = not off])
	t.append(["Water", func(off: bool):
		var w = world.get_node_or_null("Water")
		if w:
			w.visible = not off])
	t.append(["People and animals", func(off: bool):
		for n in ["People", "Wildlife"]:
			var nd = world.get_node_or_null(n)
			if nd:
				nd.visible = not off
				nd.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT])
	return t

static func _show_named(streamer: ChunkStreamer, n: String, on: bool) -> void:
	for c in streamer.chunks.values():
		var g = c.get_node_or_null(n)
		if g:
			g.visible = on

func _measure() -> Dictionary:
	for i in SETTLE:
		await get_tree().process_frame
	var vp := get_viewport().get_viewport_rid()
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0.0
	var t0 := Time.get_ticks_usec()
	for i in SAMPLE:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var frame := (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE
	return {"frame": frame, "gpu": gpu / SAMPLE, "cpu": cpu / SAMPLE, "draws": draws / SAMPLE}

func _run() -> void:
	_saved = Settings.values.duplicate()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var lines: PackedStringArray = []
	var size := get_viewport().get_visible_rect().size
	lines.append("Performance test  %s  %dx%d  render %.0f%%  preset %s" % [ProjectSettings.get_setting("application/config/version", ""),
		int(size.x), int(size.y), float(Settings.values["render_scale"]) * 100.0, Settings.values["preset"]])
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	_panel.text = "\n".join(lines) + "\nMeasuring... keep still"
	var base: Dictionary = await _measure()
	lines.append("Baseline: %.1f ms/frame (%d FPS)  GPU %.1f ms  CPU render %.1f ms  %d draw calls" % [
		base["frame"], int(1000.0 / maxf(base["frame"], 0.1)), base["gpu"], base["cpu"], int(base["draws"])])
	lines.append("Turning off one at a time (saves GPU ms / frame ms):")
	for t in _tests():
		_panel.text = "\n".join(lines) + "\nMeasuring: %s..." % t[0]
		(t[1] as Callable).call(true)
		var m: Dictionary = await _measure()
		(t[1] as Callable).call(false)
		lines.append("  %-32s GPU %5.1f   frame %5.1f   draws %5d" % [t[0], base["gpu"] - m["gpu"], base["frame"] - m["frame"], int(base["draws"] - m["draws"])])
	Settings.values = _saved
	Settings.apply()
	if not Settings.get_value("show_fps"):
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	lines.append("Settings restored. Copied to clipboard; saved to user://benchmark.txt")
	var text := "\n".join(lines)
	print(text)
	DisplayServer.clipboard_set(text)
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
	if quit_when_done:
		get_tree().quit()
		return
	_panel.text = text + "\n(this panel closes in 60 s)"
	await get_tree().create_timer(60.0).timeout
	queue_free()
