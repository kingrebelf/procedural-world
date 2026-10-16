class_name SettingsMenu
extends PanelContainer
## Full settings screen: Graphics, Display, Controls, Audio. Used by the main menu and
## the pause menu. Every control writes straight to the Settings autoload.

signal closed

var _rows: Dictionary = {}
var _building := false

func _ready() -> void:
	theme = UITheme.get_theme()
	custom_minimum_size = Vector2(860, 640)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UITheme.title("Settings"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.button("Back", func(): closed.emit()))
	v.add_child(head)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_audio_tab())
	Settings.changed.connect(_sync)
	_sync()

func _page(title: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(g)
	return s

func _grid(page: ScrollContainer) -> GridContainer:
	return page.get_child(0)

func _label(g: GridContainer, text: String, hint: String = "") -> void:
	var l := UITheme.label(text, 17)
	l.custom_minimum_size = Vector2(300, 0)
	l.tooltip_text = hint
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	g.add_child(l)

func _option(g: GridContainer, key: String, text: String, items: Array, hint: String = "", values: Array = []) -> void:
	_label(g, text, hint)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(320, 0)
	for it in items:
		o.add_item(str(it))
	var vals := values if not values.is_empty() else range(items.size())
	o.item_selected.connect(func(i):
		if _building:
			return
		if key == "preset":
			if items[i] != "Custom":
				Settings.apply_preset(items[i])
		else:
			Settings.set_value(key, vals[i]))
	g.add_child(o)
	_rows[key] = {"ctl": o, "values": vals}

func _slider(g: GridContainer, key: String, text: String, lo: float, hi: float, step: float, fmt: String, hint: String = "") -> void:
	_label(g, text, hint)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UITheme.label("", 16, UITheme.DIM)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(val):
		l.text = fmt % val
		if not _building:
			Settings.set_value(key, int(val) if step >= 1.0 else val))
	h.add_child(s)
	h.add_child(l)
	g.add_child(h)
	_rows[key] = {"ctl": s, "label": l, "fmt": fmt}

func _check(g: GridContainer, key: String, text: String, hint: String = "") -> void:
	_label(g, text, hint)
	var c := CheckBox.new()
	c.toggled.connect(func(on):
		if not _building:
			Settings.set_value(key, on))
	g.add_child(c)
	_rows[key] = {"ctl": c}

func _graphics_tab() -> Control:
	var p := _page("Graphics")
	var g := _grid(p)
	_option(g, "preset", "Quality preset", Settings.PRESET_NAMES, "Low targets integrated GPUs; High targets an RTX 3070 at 1440p.")
	_option(g, "upscaler", "Upscaling", ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"], "FSR 2.2 is temporal and replaces TAA.")
	_slider(g, "render_scale", "Render scale", 0.5, 2.0, 0.05, "%.0f%%", "Below 100% renders fewer pixels and upscales; above 100% supersamples.")
	_rows["render_scale"]["fmt"] = "%.2fx"
	_slider(g, "sharpness", "Upscaler sharpness", 0.0, 2.0, 0.1, "%.1f", "FSR sharpening (0 = sharpest).")
	_option(g, "aa", "Anti-aliasing", ["Off", "FXAA", "SMAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"])
	_option(g, "shadows", "Shadow quality", ["Low", "Medium", "High", "Ultra"])
	_slider(g, "shadow_distance", "Shadow distance", 80, 600, 10, "%d m")
	_option(g, "gi", "Global illumination", ["Off", "Screen-space (SSIL)", "SDFGI (dynamic)"], "SDFGI gives bounced light everywhere; it is the most expensive option.")
	_check(g, "ssao", "Ambient occlusion (SSAO)")
	_check(g, "ssr", "Screen-space reflections")
	_option(g, "volumetric_fog", "Volumetric fog", ["Off", "Normal", "High"])
	_check(g, "glow", "Bloom")
	_check(g, "auto_exposure", "Auto exposure")
	_slider(g, "view_distance", "View distance", 3, 8, 1, "%d chunks", "Each chunk is 64 m. 5 chunks is about 320 m of detailed terrain.")
	_slider(g, "grass_density", "Grass density", 0.0, 1.5, 0.1, "%.1fx")
	var note := UITheme.label("Hardware ray tracing is not available in Godot 4.5; SDFGI and SSR provide dynamic bounced light and reflections instead.", 13, UITheme.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	g.add_child(note)
	return p

func _display_tab() -> Control:
	var p := _page("Display")
	var g := _grid(p)
	_option(g, "window_mode", "Window mode", ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"])
	var res := Settings.resolutions()
	_option(g, "resolution", "Window resolution", res.map(func(r): return "Native" if r == "native" else r), "Used in windowed mode.", res)
	_option(g, "vsync", "V-Sync", ["Off", "On", "Adaptive", "Mailbox"])
	_option(g, "fps_cap", "Frame rate limit", ["Unlimited", "30", "60", "90", "120", "144", "165", "240"], "", [0, 30, 60, 90, 120, 144, 165, 240])
	_slider(g, "fov", "Field of view", 60, 110, 1, "%d°")
	_check(g, "show_fps", "Show FPS counter")
	return p

func _controls_tab() -> Control:
	var p := _page("Controls")
	var g := _grid(p)
	_slider(g, "mouse_sensitivity", "Mouse sensitivity", 0.02, 0.5, 0.01, "%.2f")
	_check(g, "invert_y", "Invert vertical look")
	_check(g, "head_bob", "Head bob")
	var keys := [["Move", "W A S D"], ["Sprint / Crouch", "Shift / Ctrl"], ["Jump", "Space"], ["Use tool / weapon", "Left mouse"],
		["Interact / Trade", "E"], ["Eat", "F"], ["Inventory", "Tab"], ["Crafting", "R"], ["Map", "M"], ["Hotbar", "1 to 6, mouse wheel"], ["Pause", "Esc"]]
	for k in keys:
		_label(g, k[0])
		g.add_child(UITheme.label(k[1], 17, UITheme.DIM))
	return p

func _audio_tab() -> Control:
	var p := _page("Audio")
	var g := _grid(p)
	_slider(g, "master_volume", "Master volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(g, "music_volume", "Music volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(g, "sfx_volume", "Effects volume", 0.0, 1.0, 0.05, "%.2f")
	return p

func _sync() -> void:
	_building = true
	for key in _rows:
		var r: Dictionary = _rows[key]
		var v = Settings.get_value(key)
		var c = r["ctl"]
		if c is OptionButton:
			if key == "preset":
				c.select(Settings.PRESET_NAMES.find(v))
			else:
				var idx: int = r["values"].find(v)
				if idx < 0:
					for i in r["values"].size():
						if typeof(r["values"][i]) == typeof(v) or (r["values"][i] is int and (v is float or v is int) and int(v) == r["values"][i]):
							if r["values"][i] == v or (v is float and int(v) == r["values"][i]):
								idx = i
				c.select(maxi(idx, 0))
		elif c is HSlider:
			c.value = float(v)
			r["label"].text = r["fmt"] % float(v)
		elif c is CheckBox:
			c.button_pressed = bool(v)
	_building = false
