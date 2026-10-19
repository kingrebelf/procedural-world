class_name SettingsMenu
extends PanelContainer
## Full settings screen: Graphics, Display, Controls, Audio. Used by the main menu and
## the pause menu. Every control writes straight to the Settings autoload.

signal closed

var _rows: Dictionary = {}
var _building := false
var _tabs: TabContainer

## Settings > AI > Voice engine choices, in menu order.
const ENGINES := ["auto", "builtin", "ai", "system"]

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
	_tabs = tabs
	tabs.add_child(_graphics_tab())
	tabs.add_child(_display_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_ai_tab())
	v.add_child(UITheme.pad_hints([[JOY_BUTTON_A, "Select"], ["dpad", "Move / adjust"], ["rs", "Scroll"],
		[[JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER], "Switch tab"], [JOY_BUTTON_B, "Back"]]))
	tabs.tab_changed.connect(func(_i): if Game.using_pad: _focus_page.call_deferred())
	Game.pad_changed.connect(_on_pad)
	Settings.changed.connect(_sync)
	_sync()
	if Game.using_pad:
		_focus_page.call_deferred()

# --- Controller -------------------------------------------------------------------------

func _on_pad() -> void:
	if Game.using_pad and not UITheme.has_focus_in(self):
		_focus_page()

## Focus on the first setting of the open tab.
func _focus_page() -> void:
	if is_instance_valid(_tabs) and _tabs.get_current_tab_control():
		UITheme.focus_first(_tabs.get_current_tab_control())

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
	elif event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		var n := _tabs.get_tab_count()
		_tabs.current_tab = posmod(_tabs.current_tab + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), n)
	else:
		return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# The right stick scrolls the open tab.
	if not Game.using_pad or not is_instance_valid(_tabs):
		return
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var page := _tabs.get_current_tab_control() as ScrollContainer
	if absf(ry) > 0.2 and page:
		page.scroll_vertical += int(ry * absf(ry) * 1400.0 * delta)

func _page(title: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true # moving down the list on a controller keeps the setting in view
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
		elif key == "fsr_mode":
			if i < Settings.FSR_MODES.size():
				Settings.set_fsr_mode(i)
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
	_option(g, "fsr_mode", "FSR 2 upscaling", Settings.FSR_MODES + ["Off / custom"],
		"Renders fewer pixels and rebuilds a sharp full-resolution image. The biggest frame-rate gain at 1440p and 4K: Quality renders 67% of the width and height, Performance 50%.")
	_option(g, "upscaler", "Upscaler", ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"], "FSR 2.2 is temporal and replaces TAA.")
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
	_check(g, "sun_shafts", "Light shafts", "Rays of sunlight through trees, gaps and windows.")
	_check(g, "glow", "Bloom")
	_check(g, "auto_exposure", "Auto exposure")
	_check(g, "film_grade", "Film colour grade", "Cool shadows, warm highlights and softer greens, as a graded film. Off shows the raw colours.")
	_check(g, "motion_blur", "Motion blur", "A slight smear when you turn or move fast, as a camera shutter gives. The held item stays sharp.")
	_slider(g, "motion_blur_strength", "Motion blur amount", 0.1, 1.0, 0.05, "%.2f", "How long the shutter stays open, in 60ths of a second. 0.3 is subtle; 1.0 is film-like.")
	_option(g, "clouds", "Cloud quality", ["Flat (fastest)", "Volumetric", "Volumetric high"], "Ray-marched 3D clouds cost a lot at 4K; Flat paints a cloud deck on the sky.")
	_option(g, "effects", "Effects quality", ["Low", "Medium", "High"], "Sample counts for ambient occlusion, screen-space and SDFGI light. Low and Medium run GI at half resolution.")
	_check(g, "weather", "Dynamic weather", "Rain, snow, storms, mist and dust storms that come and go. Off keeps fair skies.")
	_option(g, "weather_fx", "Weather effects", ["Low", "Normal", "High"], "How many raindrops and snowflakes fall round you; Normal and High add splashes where rain lands, High lets lightning cast shadows.")
	_option(g, "fire_fx", "Fire and smoke", ["Low", "Normal", "High"], "How many burning buildings show flames and cast firelight (High: more of them throw shadows), and how thick the smoke rises.")
	_slider(g, "view_distance", "View distance", 3, 8, 1, "%d chunks", "Each chunk is 64 m. 5 chunks is about 320 m of detailed terrain.")
	_slider(g, "detail_distance", "Detail distance", 0.4, 1.5, 0.1, "%.1fx", "How far grass, ground clutter and small props are drawn. Trees and buildings are not affected.")
	_slider(g, "grass_density", "Grass density", 0.0, 1.5, 0.1, "%.1fx")
	_option(g, "mesh_detail", "Mesh detail", ["Low", "Medium", "High", "Ultra"], "How soon distant models switch to simpler versions.")
	_option(g, "anisotropic", "Texture filtering", ["Bilinear", "2x anisotropic", "4x anisotropic", "8x anisotropic", "16x anisotropic"])
	_check(g, "menu_flyover", "Animated title screen", "Shots of the world playing behind the main menu.")
	var note := UITheme.label("Turn on Display > Show FPS counter to see whether the GPU or the CPU limits your frame rate. Hardware ray tracing and DLSS are not available in Godot 4.5; SDFGI and SSR provide bounced light and reflections, and FSR 2 does the upscaling.", 13, UITheme.DIM)
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
	_slider(g, "fov", "Field of view", 70, 120, 1, "%d°", "The horizontal angle you see on a 16:9 screen, as most shooters measure it. 90 is usual; wider screens see more at the sides.")
	_slider(g, "brightness", "Brightness", 0.5, 1.6, 0.05, "%.2f", "How much light the picture lets in, as a camera's exposure. 1.00 is how the world is meant to look; raise it if nights and interiors are too dark on your screen.")
	_slider(g, "gamma", "Gamma", 0.7, 1.5, 0.05, "%.2f", "Lifts (above 1) or deepens (below 1) the shadows and mid-tones without touching the brightest whites. Adjust until dark corners show detail but still read as dark.")
	_label(g, "")
	g.add_child(UITheme.button("Reset brightness and gamma", func():
		Settings.set_value("brightness", 1.0, false)
		Settings.set_value("gamma", 1.0)))
	_check(g, "show_fps", "Show FPS counter")
	return p

func _controls_tab() -> Control:
	var p := _page("Controls")
	var g := _grid(p)
	_slider(g, "mouse_sensitivity", "Mouse sensitivity", 0.02, 0.5, 0.01, "%.2f")
	_slider(g, "stick_sensitivity", "Controller look speed", 0.5, 8.0, 0.1, "%.1f")
	_check(g, "invert_y", "Invert vertical look")
	_check(g, "head_bob", "Head bob and sway", "Your view rises and falls with each step, sways side to side, dips when you land and leans a little as you strafe.")
	_slider(g, "head_bob_strength", "Head bob amount", 0.2, 1.5, 0.05, "%.2f")
	_check(g, "sail_auto_trim", "Auto-trim sails", "Your boat's sail is trimmed to the wind for you, and W/S paddle instead. Off, W/S haul in and ease out the sheet yourself.")
	var pads := Input.get_connected_joypads()
	_label(g, "Controller")
	g.add_child(UITheme.label(Input.get_joy_name(pads[0]) if not pads.is_empty() else "None connected (Xbox, PlayStation and generic pads are supported)", 15, UITheme.DIM))
	_label(g, "Click a binding (or press A on it), then press the new key or button. Esc, or B for a key, cancels.", "")
	g.add_child(UITheme.button("Reset all to defaults", func():
		Bindings.reset()
		_refresh_binds()))
	for a in Bindings.ACTIONS:
		_label(g, Bindings.ACTIONS[a][0])
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		for slot in ["kb", "pad"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 0)
			b.clip_text = true
			b.pressed.connect(func(): _begin_capture(a, slot, b))
			h.add_child(b)
			_bind_buttons.append({"action": a, "slot": slot, "btn": b})
		g.add_child(h)
	_refresh_binds()
	return p

var _bind_buttons: Array = []
var _capture: Dictionary = {}

func _refresh_binds() -> void:
	for e in _bind_buttons:
		var s = Bindings.spec(e["action"], e["slot"])
		e["btn"].text = ("Keyboard: " if e["slot"] == "kb" else "Pad: ") + Bindings.describe(s)

func _begin_capture(action: String, slot: String, b: Button) -> void:
	_capture = {"action": action, "slot": slot}
	b.text = "Press a %s..." % ("key" if slot == "kb" else "button")

func _input(event: InputEvent) -> void:
	if _capture.is_empty():
		return
	if (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE) \
			or (_capture["slot"] == "kb" and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		_capture = {}
		_refresh_binds()
		get_viewport().set_input_as_handled()
		return
	var s = Bindings.spec_from_event(event, _capture["slot"])
	if s == null:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			get_viewport().set_input_as_handled() # the pad doesn't wander off while you choose
		return
	Bindings.rebind(_capture["action"], _capture["slot"], s)
	_capture = {}
	_refresh_binds()
	get_viewport().set_input_as_handled()

func _audio_tab() -> Control:
	var p := _page("Audio")
	var g := _grid(p)
	_slider(g, "master_volume", "Master volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(g, "music_volume", "Music volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(g, "sfx_volume", "Effects volume", 0.0, 1.0, 0.05, "%.2f")
	_slider(g, "ambience_volume", "Ambience volume", 0.0, 1.0, 0.05, "%.2f")
	return p

# --- AI ----------------------------------------------------------------------------------

var _ai_fields: Dictionary = {}
var _ai_status: Label

func _ai_tab() -> Control:
	var p := _page("AI")
	var g := _grid(p)
	_label(g, "AI provider", "Who voices and directs the NPCs. Off uses the built-in dialogue and decisions, which need no network.")
	var prov := OptionButton.new()
	prov.custom_minimum_size = Vector2(320, 0)
	for id in AI.PROVIDER_ORDER:
		prov.add_item(AI.PRESETS[id]["label"])
	prov.select(maxi(AI.PROVIDER_ORDER.find(AI.get_value("provider")), 0))
	prov.item_selected.connect(func(i):
		AI.use_provider(AI.PROVIDER_ORDER[i])
		_ai_refresh())
	g.add_child(prov)
	_ai_fields["provider"] = prov
	_ai_line(g, "base_url", "Server address", "OpenAI-compatible servers end in /v1. Strata: http://127.0.0.1:8080/v1")
	_ai_line(g, "model", "Model", "Model name as the server knows it, e.g. claude-haiku-5-5, gpt-5-mini, llama3.1:8b.")
	_ai_line(g, "api_key", "API key", "Stored encrypted on this PC. Only sent to the server above.", true)
	_label(g, "Wire format", "Anthropic Messages or OpenAI chat-completions. Set automatically by the provider.")
	var fmt := OptionButton.new()
	fmt.add_item("OpenAI-compatible")
	fmt.add_item("Anthropic Messages")
	fmt.item_selected.connect(func(i): AI.set_value("format", ["openai", "anthropic"][i]))
	g.add_child(fmt)
	_ai_fields["format"] = fmt
	_ai_slider(g, "temperature", "Creativity (temperature)", 0.0, 1.5, 0.05, "%.2f")
	_ai_slider(g, "max_tokens", "Max reply length (tokens)", 100, 1500, 50, "%d")
	_ai_slider(g, "timeout", "Request timeout", 5, 120, 5, "%d s")
	_ai_check(g, "json_mode", "Ask for JSON replies", "Turn off for servers that reject response_format.")
	_ai_check(g, "dialogue", "AI conversations", "NPCs answer free-typed speech with the model.")
	_ai_check(g, "background_thinking", "AI background goals", "Nearby NPCs occasionally ask the model what to do next. Uses more requests.")
	_ai_slider(g, "think_interval", "Seconds between an NPC's thoughts", 30, 600, 10, "%d s")
	_ai_slider(g, "max_rpm", "Max model requests per minute", 2, 120, 1, "%d")
	_ai_line(g, "decide_url", "Fast decision service URL", "Optional. An HTTP endpoint that picks NPC actions every 2 s (see docs/AI.md). Leave empty to use the built-in engine.")
	_ai_line(g, "decide_key", "Decision service key", "Optional bearer token for the decision service.", true)
	_ai_check(g, "voices", "Spoken voices", "People say their lines aloud.")
	_label(g, "Voice engine", "The built-in natural voices come with the game and run offline: everyone has their own voice and accent. A voice server (below) can be used instead. This PC's voices sound robotic.")
	var eng := OptionButton.new()
	for t in ["Automatic (voice server if set, else built-in)", "Built-in natural voices", "Natural voices (voice server)", "This PC's voices"]:
		eng.add_item(t)
	eng.select(maxi(ENGINES.find(AI.get_value("voice_engine")), 0))
	eng.item_selected.connect(func(i): AI.set_value("voice_engine", ENGINES[i]))
	g.add_child(eng)
	_ai_fields["voice_engine"] = eng
	_ai_line(g, "tts_url", "Voice server", "OpenAI-compatible /audio/speech. Empty uses the OpenAI provider above if that is your provider. Free and local: a Kokoro server (e.g. Kokoro-FastAPI, http://127.0.0.1:8880/v1) or speaches. Cloud: https://api.openai.com/v1")
	_ai_line(g, "tts_model", "Voice model", "Empty picks gpt-4o-mini-tts for OpenAI (accents and tone per person), kokoro elsewhere.")
	_ai_line(g, "tts_key", "Voice server key", "Only if the voice server differs from the provider above.", true)
	_ai_check(g, "quick_replies", "Quick replies", "People answer \"Yes.\", \"No.\" or \"Hmm, let me think about that.\" straight away (picked by the fast decision service if set), then the full reply follows.")
	_ai_check(g, "voice_barks", "Passers-by speak too", "Greetings and shouts from people nearby are spoken, not only conversations.")
	_ai_slider(g, "voice_volume", "Voice volume", 0, 100, 5, "%d")
	_ai_check(g, "open_mic", "Open mic", "Your microphone stays on (toggle with O): say something and the people near you hear it. One who is willing answers; the rest carry on. Wear headphones, or people may hear each other through your speakers.")
	_ai_line(g, "stt_url", "Speech-to-text server", "For talking with your microphone (hold B near someone, or open mic). Empty uses the built-in speech recognition that comes with the game (offline), else the OpenAI provider. Any server with /audio/transcriptions works, e.g. https://api.openai.com/v1 or a local speaches / LocalAI server.")
	_ai_line(g, "stt_model", "Speech-to-text model", "Empty picks gpt-4o-mini-transcribe for OpenAI, whisper-1 elsewhere.")
	_ai_line(g, "stt_key", "Speech-to-text key", "Only if the speech-to-text server differs from the provider above.", true)
	var vrow := HBoxContainer.new()
	vrow.add_child(UITheme.button("Test voice", _voice_test))
	vrow.add_child(UITheme.button("Test microphone (3 s)", _mic_test))
	_label(g, "Voice checks", "Hear a sample voice, or record three seconds and see what was understood.")
	g.add_child(vrow)
	var test := UITheme.button("Test connection", _ai_test)
	g.add_child(test)
	_ai_status = UITheme.label(AI.last_status, 14, UITheme.DIM)
	_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_status.custom_minimum_size = Vector2(320, 0)
	g.add_child(_ai_status)
	var note := UITheme.label("A ChatGPT or Claude chat subscription cannot be used here: those apps do not offer an API for games. Use an API key from platform.openai.com or console.anthropic.com, or run a free local model with Strata, Ollama or LM Studio.", 13, UITheme.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	g.add_child(note)
	_ai_refresh()
	return p

func _ai_line(g: GridContainer, key: String, text: String, hint: String, secret: bool = false) -> void:
	_label(g, text, hint)
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(320, 0)
	e.secret = secret
	e.tooltip_text = hint
	e.text_changed.connect(func(t): AI.set_value(key, t.strip_edges()))
	g.add_child(e)
	_ai_fields[key] = e

func _ai_slider(g: GridContainer, key: String, text: String, lo: float, hi: float, step: float, fmt: String) -> void:
	_label(g, text)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240, 24)
	var l := UITheme.label("", 16, UITheme.DIM)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v):
		l.text = fmt % v
		AI.set_value(key, int(v) if step >= 1.0 else v))
	h.add_child(s)
	h.add_child(l)
	g.add_child(h)
	_ai_fields[key] = s

func _ai_check(g: GridContainer, key: String, text: String, hint: String) -> void:
	_label(g, text, hint)
	var c := CheckBox.new()
	c.toggled.connect(func(on): AI.set_value(key, on))
	g.add_child(c)
	_ai_fields[key] = c

func _ai_refresh() -> void:
	for k in _ai_fields:
		var c = _ai_fields[k]
		var v = AI.get_value(k)
		if c is LineEdit:
			if c.text != str(v):
				c.text = str(v)
		elif c is HSlider:
			c.set_value_no_signal(float(v))
			(c.get_parent().get_child(1) as Label).text = str(v)
		elif c is CheckBox:
			c.set_pressed_no_signal(bool(v))
		elif k == "format":
			c.select(1 if v == "anthropic" else 0)
		elif k == "voice_engine":
			c.select(maxi(ENGINES.find(v), 0))
	var off: bool = AI.get_value("provider") == "off"
	for k in _ai_fields:
		if not k in ["provider", "decide_url", "decide_key", "voices", "voice_barks", "voice_volume", "stt_url", "stt_model", "stt_key", "open_mic",
				"voice_engine", "tts_url", "tts_model", "tts_key", "quick_replies"]:
			var c = _ai_fields[k]
			if c is BaseButton:
				c.disabled = off
			elif c is LineEdit:
				c.editable = not off
			elif c is Range:
				c.editable = not off

## Each press is someone new: another voice, age and accent.
func _voice_test() -> void:
	var era := 0 if randf() < 0.6 else 2
	var rec := {"id": "%d_%d_%d" % [randi() % 99, randi() % 99, randi() % 40], "name": "Edda Thorne", "job": "farmer", "era": era,
		"age": [9, 16, 25, 34, 45, 58, 70][randi() % 7], "mood": "happy",
		"body": {"female": randf() < 0.5, "build": randf_range(0.85, 1.2)}, "traits": {"friendly": 0.8, "brave": 0.5, "curious": 0.6, "diligent": 0.6, "greedy": 0.2}}
	var line: String = ["Well met! Fine weather for the road, isn't it?", "Mind the mud by the well, it's been raining since Tuesday."][randi() % 2] if era == 0 \
		else ["Hey there. Power's back on in the east block, finally.", "You picked a good day to land. Supply drop came in early."][randi() % 2]
	var e := AI.voice_engine()
	if e == "":
		_ai_status.text = "Spoken voices are off."
		return
	if e == "ai":
		var builtin: bool = AI.tts_target().get("model", "") == "builtin"
		_ai_status.text = "Loading the built-in voices..." if builtin else "Asking the voice server..."
		var r: Dictionary = await AI.speech(line, Voice.natural_for(rec))
		if not is_instance_valid(_ai_status):
			return
		if not r["ok"]:
			_ai_status.text = "%s failed: %s. Using this PC's voices until it works." % ["Built-in voices" if builtin else "Voice server", r["error"]]
			return
		var o := Voice.natural_for(rec)
		_ai_status.text = ("Built-in voice %s, a %d-year-old %s." % [o["voice"], rec["age"], "woman" if rec["body"]["female"] else "man"]) if builtin else "Natural voice: %s." % o["voice"]
		Voice.speak(rec, line)
		return
	else:
		var v := Voice.voice_for(rec)
		_ai_status.text = "This PC's voice: %s. For natural voices, set a voice server." % (v.get("id", "none") if not v.is_empty() else "none installed")
	Voice.speak(rec, line)

func _mic_test() -> void:
	var mic := Microphone.new()
	add_child(mic)
	if not mic.start():
		_ai_status.text = "No microphone input available (check your OS microphone permission)."
		mic.queue_free()
		return
	_ai_status.text = "Recording for 3 seconds: say something..."
	var top := 0.0
	for i in 30:
		await get_tree().create_timer(0.1, true, false, true).timeout
		top = maxf(top, mic.level())
	var wav := mic.stop()
	var peak := mic.last_peak
	mic.queue_free()
	if not is_instance_valid(_ai_status):
		return
	if peak < 0.004:
		_ai_status.text = "Only silence came in from %s. Check Windows Settings > Privacy & security > Microphone and the default input device." % Microphone.device()
		return
	_ai_status.text = "Heard you (level %d%%). Understanding..." % int(peak * 100.0)
	var r: Dictionary = await AI.transcribe(wav)
	if is_instance_valid(_ai_status):
		_ai_status.text = ("Understood (%s): \"%s\"" % [r.get("via", "?"), r["text"]]) if r["ok"] else "Heard you, but speech-to-text failed: %s" % r["error"]

func _ai_test() -> void:
	_ai_status.text = "Testing..."
	var r: Dictionary = await AI.test_connection()
	if is_instance_valid(_ai_status):
		_ai_status.text = r["message"]
		_ai_status.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if r["ok"] else Color(1, 0.5, 0.4))

func _sync() -> void:
	_building = true
	for key in _rows:
		var r: Dictionary = _rows[key]
		var v = Settings.get_value(key)
		var c = r["ctl"]
		if c is OptionButton:
			if key == "preset":
				c.select(Settings.PRESET_NAMES.find(v))
			elif key == "fsr_mode":
				var m := Settings.fsr_mode()
				c.select(m if m >= 0 else Settings.FSR_MODES.size())
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
