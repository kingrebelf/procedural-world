class_name TerminalUI
extends Control
## The window a terminal, monitor, wall screen, map table or bunker notice opens (see
## Lore, LoreUI): a little operating system drawn in code. It boots (the tube warms
## from a line, the kernel checks its memory, links to the grid and logs you in as the
## terminal's last user), then shows the site's name and the world's clock in its
## header, the pages as a menu, the page's text typing itself out under a command line,
## and live instruments round it: a radar with the real settlements near by, an
## oscilloscope, load meters and the code the station is running, over a faint rain of
## glyphs and the scan lines of the tube. Its colours are the screen's own
## (ScreenLook.ui_palette), so a bunker's amber console opens an amber window.

## Called with an action id; returns the line to show.
var act_fn := Callable()
## Called to close the window.
var close_fn := Callable()

var _entry: Dictionary
var _scr: Dictionary ## entry["screen"]: kind, room, os, sites, power, ticker, user
var _kind := "terminal"
var _p: Dictionary ## palette
var _font: Font
var _t := 0.0
var _boot_lines: Array = []
var _shown := false
var _page := 0
var _rng := RandomNumberGenerator.new()
var _stream: Array = []
var _stream_t := 0.0
var _rain: Array = []
var _fs := 16 ## base font size

var _rect := Rect2()
var _head := Rect2()
var _side := Rect2()
var _main := Rect2()
var _right := Rect2()
var _foot := Rect2()
var _map := Rect2()

var _menu: VBoxContainer
var _cmd: Label
var _body: RichTextLabel
var _actions: HBoxContainer
var _note: Label
var _away: Button
var _crt: ColorRect
var _content: Array = []
var _act_n := 0
var _map_on := false ## the page shows the map of sites (a holo-table, a survey)

const BOOT := 1.1 ## seconds the boot runs
const RAIN_CHARS := "0123456789ABCDEF#=+-*<>/[]{}"

func setup(entry: Dictionary, act: Callable, close: Callable) -> void:
	_entry = entry
	act_fn = act
	close_fn = close
	_scr = entry.get("screen", {})
	_kind = String(_scr.get("kind", "terminal"))
	_p = ScreenLook.ui_palette(String(_scr.get("room", "")), _kind)
	_rng.seed = hash(String(entry.get("title", ""))) ^ int(Time.get_ticks_usec() & 0xFFFF)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = mono()
	_fs = clampi(int(get_viewport_rect().size.y / 52.0), 13, 24)
	_layout()
	_boot_lines = _boot_text()
	_build()
	for c in _content:
		c.visible = false
	for i in 14:
		_stream.append(_stream_line())
	get_viewport().size_changed.connect(_on_resize)

func _on_resize() -> void:
	_fs = clampi(int(get_viewport_rect().size.y / 52.0), 13, 24)
	_layout()
	_place()

# --- Layout ------------------------------------------------------------------------

func _layout() -> void:
	var vp := get_viewport_rect().size
	var w := minf(vp.x * 0.9, _fs * 80.0)
	var h := minf(vp.y * 0.86, _fs * 46.0)
	_rect = Rect2((vp - Vector2(w, h)) * 0.5, Vector2(w, h))
	var pad := _fs * 0.8
	var hh := _fs * 2.4
	var fh := _fs * 2.2
	var sw := _fs * 13.0
	var rw := _fs * 15.0 if w > _fs * 60.0 else 0.0
	_head = Rect2(_rect.position, Vector2(w, hh))
	_foot = Rect2(_rect.position + Vector2(0, h - fh), Vector2(w, fh))
	var top := hh + pad * 0.6
	var mid_h := h - hh - fh - pad * 1.2
	_side = Rect2(_rect.position + Vector2(pad, top), Vector2(sw, mid_h))
	_right = Rect2(_rect.position + Vector2(w - pad - rw, top), Vector2(rw, mid_h))
	var mx := pad * 2.0 + sw
	_main = Rect2(_rect.position + Vector2(mx, top), Vector2(w - mx - pad * (2.0 if rw > 0.0 else 1.0) - rw, mid_h))
	_map = Rect2()
	if _map_on:
		_map = Rect2(_main.position + Vector2(0, _fs * 1.8), Vector2(_main.size.x, _main.size.y * 0.5))

func _place() -> void:
	if _menu == null:
		return
	_menu.position = _side.position + Vector2(0, _fs * 1.6)
	_menu.size = Vector2(_side.size.x, 0)
	_cmd.position = _main.position
	_cmd.size = Vector2(_main.size.x, _fs * 1.6)
	var body_top := _main.position.y + _fs * 1.8 + (_map.size.y + _fs * 0.6 if _map.size.y > 0.0 else 0.0)
	var act_h := _fs * 2.4 if _act_n > 0 else 0.0
	_body.position = Vector2(_main.position.x, body_top)
	_body.size = Vector2(_main.size.x, _main.end.y - body_top - act_h - _fs * 1.6)
	_actions.position = Vector2(_main.position.x, _main.end.y - act_h - _fs * 1.5)
	_actions.size = Vector2(_main.size.x, act_h)
	_note.position = Vector2(_main.position.x, _main.end.y - _fs * 1.4)
	_note.size = Vector2(_main.size.x, _fs * 1.4)
	_away.position = _foot.end - Vector2(_fs * 11.0, _foot.size.y - _fs * 0.35)
	_away.size = Vector2(_fs * 10.2, _foot.size.y - _fs * 0.7)
	_crt.position = _rect.position
	_crt.size = _rect.size

# --- Building ----------------------------------------------------------------------

func _style(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(2)
	s.content_margin_left = _fs * 0.6
	s.content_margin_right = _fs * 0.6
	s.content_margin_top = _fs * 0.25
	s.content_margin_bottom = _fs * 0.25
	return s

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", _fs)
	for k in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(k, _p["text"])
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, _p["key"])
	b.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), Color(_p["text"], 0.25)))
	b.add_theme_stylebox_override("hover", _style(Color(_p["text"], 0.12), Color(_p["key"], 0.7)))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color(_p["key"], 0.9), 2))
	b.add_theme_stylebox_override("pressed", _style(Color(_p["text"], 0.22), _p["key"]))
	b.add_theme_stylebox_override("hover_pressed", _style(Color(_p["text"], 0.26), _p["key"]))
	b.pressed.connect(cb)
	return b

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build() -> void:
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", int(_fs * 0.4))
	add_child(_menu)
	var pages: Array = _entry["pages"]
	for n in pages.size():
		var tab := String(pages[n].get("tab", ""))
		if tab == "":
			tab = {"bulletin": "Board", "map": "Map", "notice": "Notice"}.get(_kind, "Read")
		var b := _button("[%d] %s" % [n + 1, tab.to_upper()], func(): _show_page(n))
		b.toggle_mode = true
		_menu.add_child(b)
	_cmd = _label(_fs, _p["key"])
	add_child(_cmd)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_following = false
	for k in ["normal_font", "bold_font", "italics_font"]:
		_body.add_theme_font_override(k, _font)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_body.add_theme_font_size_override(k, int(_fs * 1.05))
	_body.add_theme_color_override("default_color", _p["text"])
	_body.add_theme_constant_override("line_separation", int(_fs * 0.25))
	add_child(_body)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", int(_fs * 0.6))
	add_child(_actions)
	_note = _label(_fs, _p["warn"])
	_note.text = String(_entry.get("note", ""))
	add_child(_note)
	_away = _button("[E] STEP AWAY", func(): close_fn.call())
	_away.alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_away)
	_content = [_menu, _cmd, _body, _actions, _note, _away]
	_crt = ColorRect.new()
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = _crt_shader()
	_crt.material = m
	add_child(_crt)
	_place()

func _show_page(n: int) -> void:
	_page = n
	var pg: Dictionary = _entry["pages"][n]
	for k in _menu.get_child_count():
		(_menu.get_child(k) as Button).button_pressed = k == n
	_cmd.text = "%s> %s" % [String(_scr.get("user", "guest")).to_lower().replace(" ", "."), _command(String(pg.get("tab", "")))]
	_cmd.visible_ratio = 0.0
	_cmd.create_tween().tween_property(_cmd, "visible_ratio", 1.0, 0.25)
	_body.text = String(pg["text"])
	_body.scroll_to_line(0)
	# The page types itself out after the command.
	_body.visible_ratio = 0.0
	var tw := _body.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_body, "visible_ratio", 1.0, clampf(_body.text.length() / 700.0, 0.3, 1.4))
	for ch in _actions.get_children():
		ch.queue_free()
	_act_n = (pg.get("actions", []) as Array).size()
	_map_on = (_kind == "map" or String(pg.get("tab", "")).to_lower() == "survey") and not (_scr.get("sites", []) as Array).is_empty()
	_layout()
	for a in pg.get("actions", []):
		var id: String = a[0]
		_actions.add_child(_button("> " + String(a[1]).to_upper(), func(): _act(id)))
	_place.call_deferred()
	UITheme.focus_first(_menu)

## The command a page is opened with, for the prompt.
func _command(tab: String) -> String:
	var site := String(_scr.get("site", "site")).to_lower().replace(" ", "_")
	match tab.to_lower():
		"logs": return "tail -n 40 /var/log/%s.log" % site
		"comms": return "comms --listen --relay"
		"status": return "sysstat --all"
		"survey": return "survey --list --range 1600"
		"notice": return "cat /board/notice.txt"
	match _kind:
		"map": return "holo --project --sites"
		"bulletin": return "board --show --news"
		"notice": return "cat /board/notice.txt"
	return "open %s" % tab.to_lower()

func _act(id: String) -> void:
	if not act_fn.is_valid():
		return
	_note.text = String(act_fn.call(id))
	_note.visible_ratio = 0.0
	_note.create_tween().tween_property(_note, "visible_ratio", 1.0, 0.3)

func set_note(text: String) -> void:
	if _note:
		_note.text = text

# --- Ticking -----------------------------------------------------------------------

func _process(d: float) -> void:
	_t += d
	if not _shown and _t >= BOOT:
		_shown = true
		for c in _content:
			c.visible = true
		_show_page(0)
	_stream_t += d
	if _stream_t > 0.16:
		_stream_t = 0.0
		_stream.append(_stream_line())
		if _stream.size() > 40:
			_stream.pop_front()
	_step_rain(d)
	queue_redraw()

func _stream_line() -> String:
	var vessel := String(_scr.get("room", "")) == "boat"
	if _rng.randf() < 0.45:
		return ScreenLook.log_line(_rng, ScreenLook.hours * 3600.0, vessel)
	return ScreenLook.code_line(_rng, vessel)

func _step_rain(d: float) -> void:
	if _rain.is_empty():
		var cols := int(_rect.size.x / (_fs * 0.9))
		for i in cols:
			_rain.append([float(i) * _fs * 0.9 + _fs * 0.3, _rng.randf_range(-_rect.size.y, _rect.size.y), _rng.randf_range(40.0, 160.0), _rng.randi_range(5, 18), _rng.randi()])
	for c in _rain:
		c[1] += c[2] * d
		if c[1] - c[3] * _fs > _rect.size.y:
			c[1] = _rng.randf_range(-_rect.size.y * 0.3, 0.0)
			c[4] = _rng.randi()

# --- Drawing -----------------------------------------------------------------------

func _boot_text() -> Array:
	var site := String(_scr.get("site", "Unknown")).to_upper()
	var os := String(_scr.get("os", "PWOS"))
	return [
		"%s v4.%d.%d  //  %s" % [os, _rng.randi_range(1, 9), _rng.randi_range(10, 99), site],
		"MEM CHECK  %dK ... OK" % (_rng.randi_range(4, 64) * 1024),
		"GRID LINK  %s ... %s" % [String(_scr.get("code", "NODE-1")), "OK" if float(_scr.get("power", 80)) > 30.0 else "LOW"],
		"AUTH  %s ... GRANTED" % String(_scr.get("user", "guest")).to_upper(),
		"LOADING SHELL",
	]

func _draw() -> void:
	var p := _p
	var col_bg: Color = p["bg"]
	var col_dim: Color = p["dim"]
	var col_text: Color = p["text"]
	var col_key: Color = p["key"]
	# The tube warms up: a line of light that opens to the full picture.
	var open := clampf(_t / 0.22, 0.0, 1.0)
	var r := _rect
	if open < 1.0:
		var hh := lerpf(2.0, r.size.y, ease(open, 0.4))
		var rr := Rect2(r.position + Vector2(0, (r.size.y - hh) * 0.5), Vector2(r.size.x * lerpf(0.3, 1.0, ease(open, 0.3)), hh))
		rr.position.x = r.position.x + (r.size.x - rr.size.x) * 0.5
		draw_rect(rr, col_bg)
		draw_rect(Rect2(rr.position + Vector2(0, rr.size.y * 0.5 - 1.0), Vector2(rr.size.x, 2.0)), col_key)
		return
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.45))
	draw_rect(r, col_bg)
	_draw_rain(col_text)
	# A faint grid over the glass.
	var g := _fs * 2.0
	var x := r.position.x + fmod(r.size.x * 0.5, g)
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(col_text, 0.025))
		x += g
	if _t < BOOT:
		_draw_boot(col_text, col_key)
		_draw_frame(col_dim, col_key)
		return
	_draw_header(col_dim, col_text, col_key)
	if _kind == "notice":
		# Hazard stripes under the header.
		var band := Rect2(_head.position + Vector2(0, _head.size.y), Vector2(_head.size.x, _fs * 0.5))
		var x0 := band.position.x
		var i := 0
		while x0 + _fs * 1.5 < band.end.x:
			if i % 2 == 0:
				var w := _fs
				draw_colored_polygon(PackedVector2Array([Vector2(x0, band.end.y), Vector2(x0 + w * 0.5, band.position.y),
					Vector2(x0 + w * 1.5, band.position.y), Vector2(x0 + w, band.end.y)]), Color(_p["warn"], 0.7))
			x0 += _fs
			i += 1
	_draw_side(col_dim, col_text, col_key)
	if _right.size.x > 0.0:
		_draw_right(col_dim, col_text, col_key)
	if _map.size.y > 0.0:
		_draw_map(_map, col_dim, col_text, col_key)
	_draw_footer(col_dim, col_text, col_key)
	# The page's box.
	draw_rect(Rect2(_main.position + Vector2(-_fs * 0.4, _fs * 1.6), Vector2(_main.size.x + _fs * 0.8, _main.size.y - _fs * 1.6)), Color(col_dim, 0.6), false, 1.0)
	_draw_frame(col_dim, col_key)

func _draw_rain(c: Color) -> void:
	var r := _rect
	for col in _rain:
		var h := int(col[4])
		for i in int(col[3]):
			var y: float = col[1] - i * _fs
			if y < _fs or y > r.size.y - 2.0:
				continue
			var ch := RAIN_CHARS[(h + i * 7 + int(_t * 8.0) * (1 if i == 0 else 0)) % RAIN_CHARS.length()]
			var a: float = 0.1 if i == 0 else 0.055 * (1.0 - float(i) / col[3])
			draw_string(_font, r.position + Vector2(col[0], y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2, Color(c, a))

func _draw_boot(c: Color, key: Color) -> void:
	var y := _rect.position.y + _fs * 2.0
	var n := int(clampf((_t - 0.25) / (BOOT - 0.45), 0.0, 1.0) * _boot_lines.size() + 0.999)
	for i in n:
		draw_string(_font, Vector2(_rect.position.x + _fs * 1.5, y), String(_boot_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, c if i < n - 1 else key)
		y += _fs * 1.5
	# A progress bar under the last line.
	var f := clampf((_t - 0.25) / (BOOT - 0.3), 0.0, 1.0)
	var bar := Rect2(Vector2(_rect.position.x + _fs * 1.5, y), Vector2(_fs * 20.0, _fs * 0.6))
	draw_rect(bar, Color(c, 0.6), false, 1.0)
	draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * f, bar.size.y - 4)), c)

func _draw_frame(dim: Color, key: Color) -> void:
	var r := _rect
	draw_rect(r, dim, false, 1.0)
	var L := _fs * 1.6
	for c in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
		var o: Vector2 = c[0]
		var s: Vector2 = c[1]
		draw_line(o, o + Vector2(L * s.x, 0), key, 2.0)
		draw_line(o, o + Vector2(0, L * s.y), key, 2.0)

func _draw_header(dim: Color, c: Color, key: Color) -> void:
	var h := _head
	draw_rect(h, Color(dim, 0.25))
	draw_line(Vector2(h.position.x, h.end.y), h.end, dim, 1.0)
	var y := h.position.y + h.size.y * 0.5 + _fs * 0.38
	var os := String(_scr.get("os", "PWOS"))
	var tag := Rect2(h.position + Vector2(_fs * 0.6, h.size.y * 0.2), Vector2(_font.get_string_size(os, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + _fs, h.size.y * 0.6))
	draw_rect(tag, key)
	draw_string(_font, Vector2(tag.position.x + _fs * 0.5, y), os, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _p["bg"])
	var title := String(_entry.get("title", "")).to_upper()
	draw_string(_font, Vector2(tag.end.x + _fs * 0.8, y), title, HORIZONTAL_ALIGNMENT_LEFT, h.size.x * 0.5, int(_fs * 1.15), key)
	var sub := String(_entry.get("sub", ""))
	var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_fs * 1.15)).x
	if tag.end.x + tw + _fs * 2.0 < h.position.x + h.size.x * 0.55:
		draw_string(_font, Vector2(tag.end.x + _fs * 1.6 + tw, y), sub, HORIZONTAL_ALIGNMENT_LEFT, h.size.x * 0.55 - tw - tag.size.x - _fs * 3.0, _fs - 2, Color(c, 0.6))
	# Right: clock, power meter, signal.
	var hr := ScreenLook.hours
	var clock := "%02d%s%02d" % [int(hr), ":" if fmod(_t, 1.0) < 0.5 else " ", int(fmod(hr * 60.0, 60.0))]
	var cw := _font.get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_fs * 1.15)).x
	var x := h.end.x - _fs * 0.8 - cw
	draw_string(_font, Vector2(x, y), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_fs * 1.15), key)
	x -= _fs * 3.0
	for i in 4:
		var bh := (i + 1) * _fs * 0.25
		var lit := i < 3 or fmod(_t, 2.0) < 1.4
		draw_rect(Rect2(Vector2(x + i * _fs * 0.45, y - bh), Vector2(_fs * 0.3, bh)), c if lit else Color(c, 0.2))
	var pw := float(_scr.get("power", -1))
	if pw >= 0.0:
		x -= _fs * 9.5
		draw_string(_font, Vector2(x, y), "PWR", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2, Color(c, 0.7))
		var bar := Rect2(Vector2(x + _fs * 2.4, y - _fs * 0.7), Vector2(_fs * 5.5, _fs * 0.7))
		draw_rect(bar, Color(c, 0.5), false, 1.0)
		var segs := 10
		for i in segs:
			if float(i) / segs < pw / 100.0:
				draw_rect(Rect2(bar.position + Vector2(2 + i * (bar.size.x - 4) / segs, 2), Vector2((bar.size.x - 4) / segs - 2, bar.size.y - 4)),
					_p["warn"] if pw < 50.0 else c)

func _draw_side(dim: Color, c: Color, key: Color) -> void:
	var s := _side
	draw_string(_font, s.position + Vector2(0, _fs), "// MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2, Color(c, 0.55))
	# A radar of the settlements round about, under the menu.
	var sites: Array = _scr.get("sites", [])
	if sites.is_empty():
		return
	var size := minf(s.size.x, s.size.y * 0.45)
	var box := Rect2(Vector2(s.position.x, s.end.y - size - _fs * 1.5), Vector2(size, size))
	if box.position.y < _menu.position.y + _menu.size.y + _fs:
		return
	draw_string(_font, box.position - Vector2(0, _fs * 0.4), "// SCAN %d M" % int(_range()), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.55))
	_draw_radar(box, sites, dim, c, key, false)

## A round scope in box: rings, a sweep, and the sites ([name, dx, dz, d]) as blips that
## light as the sweep passes, labelled when `labels`.
func _draw_radar(box: Rect2, sites: Array, dim: Color, c: Color, key: Color, labels: bool) -> void:
	var ctr := box.get_center()
	var rad := box.size.x * 0.5 - 2.0
	draw_circle(ctr, rad, Color(dim, 0.15))
	for k in 4:
		draw_arc(ctr, rad * (k + 1) / 4.0, 0, TAU, 48, Color(c, 0.25 if k < 3 else 0.55), 1.0)
	draw_line(ctr - Vector2(rad, 0), ctr + Vector2(rad, 0), Color(c, 0.18))
	draw_line(ctr - Vector2(0, rad), ctr + Vector2(0, rad), Color(c, 0.18))
	var ang := fmod(_t * 1.4, TAU)
	for k in 14:
		var a := ang - k * 0.035
		draw_line(ctr, ctr + Vector2(sin(a), -cos(a)) * rad, Color(c, 0.3 * (1.0 - k / 14.0)), 2.0)
	draw_string(_font, ctr + Vector2(-_fs * 0.3, -rad + _fs * 0.9), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.6))
	for st in sites:
		var dv := Vector2(float(st[1]), float(st[2]))
		var d := clampf(float(st[3]) / _range(), 0.05, 1.0)
		var dir := dv.normalized()
		var at := ctr + dir * d * rad
		var sa := fposmod(atan2(dir.x, -dir.y), TAU)
		var since := fposmod(ang - sa, TAU) / TAU
		var glow := 1.0 - since
		draw_circle(at, _fs * 0.22 + glow * _fs * 0.15, Color(key, 0.45 + 0.55 * glow))
		if labels:
			draw_string(_font, at + Vector2(_fs * 0.5, _fs * 0.3), "%s %dM" % [String(st[0]).to_upper(), int(round(float(st[3]) / 10.0)) * 10],
				HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.75 + 0.25 * glow))
	# You are here.
	draw_arc(ctr, _fs * 0.35 + fmod(_t, 1.0) * _fs * 0.6, 0, TAU, 20, Color(_p["warn"], 1.0 - fmod(_t, 1.0)), 1.5)
	draw_circle(ctr, _fs * 0.2, _p["warn"])

func _draw_map(box: Rect2, dim: Color, c: Color, key: Color) -> void:
	var sq := Rect2(box.position + Vector2((box.size.x - box.size.y) * 0.5, 0), Vector2(box.size.y, box.size.y))
	# Contour rings drawn round the table's land, wobbling with the seed.
	var ctr := sq.get_center()
	var rad := sq.size.x * 0.5
	var h := hash(String(_entry.get("sub", "")))
	for k in 6:
		var pts := PackedVector2Array()
		var base := rad * (0.2 + k * 0.14)
		for i in 49:
			var a := TAU * i / 48.0
			var wob := 1.0 + 0.12 * sin(a * 3.0 + k + h % 7) + 0.06 * sin(a * 7.0 - k * 2.0 + h % 5)
			pts.append(ctr + Vector2(sin(a), -cos(a)) * minf(base * wob, rad))
		draw_polyline(pts, Color(dim, 0.7), 1.0)
	_draw_radar(sq, _scr.get("sites", []), dim, c, key, true)

func _draw_right(dim: Color, c: Color, key: Color) -> void:
	var r := _right
	var y := r.position.y
	draw_string(_font, Vector2(r.position.x, y + _fs), "// SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.55))
	# Oscilloscope.
	var sc := Rect2(Vector2(r.position.x, y + _fs * 1.4), Vector2(r.size.x, _fs * 5.0))
	draw_rect(sc, Color(dim, 0.5), false, 1.0)
	for k in 3:
		draw_line(Vector2(sc.position.x, sc.position.y + sc.size.y * (k + 1) / 4.0), Vector2(sc.end.x, sc.position.y + sc.size.y * (k + 1) / 4.0), Color(c, 0.08))
	var pts := PackedVector2Array()
	for i in 64:
		var f := i / 63.0
		var v := sin(f * 11.0 + _t * 3.1) * 0.55 + sin(f * 29.0 - _t * 5.3) * 0.25 + sin(f * 4.0 + _t) * 0.2
		pts.append(Vector2(sc.position.x + f * sc.size.x, sc.get_center().y + v * sc.size.y * 0.38))
	draw_polyline(pts, key, 1.5, true)
	y = sc.end.y + _fs * 0.6
	# Load meters.
	draw_string(_font, Vector2(r.position.x, y + _fs), "// LOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.55))
	y += _fs * 1.4
	var labels := ["CPU", "MEM", "NET", "I/O"]
	for i in 4:
		var v := 0.5 + 0.45 * sin(_t * (0.7 + i * 0.37) + i * 1.9) * sin(_t * 0.23 + i)
		draw_string(_font, Vector2(r.position.x, y + _fs * 0.8), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.7))
		var bar := Rect2(Vector2(r.position.x + _fs * 2.6, y), Vector2(r.size.x - _fs * 2.6, _fs * 0.8))
		var segs := 16
		for k in segs:
			var on := float(k) / segs < v
			draw_rect(Rect2(bar.position + Vector2(k * bar.size.x / segs, 0), Vector2(bar.size.x / segs - 2, bar.size.y)),
				(_p["warn"] if k > 12 else c) if on else Color(c, 0.1))
		y += _fs * 1.2
	# The code the station is running, the newest line typing.
	y += _fs * 0.4
	draw_string(_font, Vector2(r.position.x, y + _fs), "// PROC", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, Color(c, 0.55))
	y += _fs * 2.4
	var lines := int((r.end.y - y) / (_fs * 1.15))
	var start := maxi(0, _stream.size() - lines)
	for i in range(start, _stream.size()):
		var line := String(_stream[i])
		var newest := i == _stream.size() - 1
		if newest:
			line = line.substr(0, int(line.length() * clampf(_stream_t / 0.12, 0.0, 1.0)))
		var lc: Color = _p["warn"] if line.contains("[WARN]") or line.contains("[ERR]") else (Color(c, 0.45) if line.begins_with("  //") or line.begins_with("//") else Color(c, 0.75))
		draw_string(_font, Vector2(r.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, _fs - 4, key if newest else lc)
		y += _fs * 1.15

func _draw_footer(dim: Color, c: Color, key: Color) -> void:
	var f := _foot
	draw_line(f.position, Vector2(f.end.x, f.position.y), dim, 1.0)
	var y := f.position.y + f.size.y * 0.5 + _fs * 0.35
	var ticker: Array = _scr.get("ticker", [])
	if not ticker.is_empty():
		# News crawling along the foot.
		var tag := Rect2(f.position + Vector2(_fs * 0.6, f.size.y * 0.2), Vector2(_fs * 3.6, f.size.y * 0.6))
		draw_rect(tag, key)
		draw_string(_font, Vector2(tag.position.x + _fs * 0.5, y), "NEWS", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _p["bg"])
		var text := "   +++   ".join(ticker).to_upper() + "   +++   "
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		var x0 := tag.end.x + _fs
		var room := f.size.x - (x0 - f.position.x) - _fs * 12.0
		var off := fmod(_t * _fs * 5.0, maxf(tw, 1.0))
		var cl := Rect2(Vector2(x0, f.position.y), Vector2(room, f.size.y))
		# Draw twice so it wraps; clip by drawing per character only inside the band.
		for rep in 2:
			var x := x0 - off + rep * tw
			for i in text.length():
				var cw := _font.get_char_size(text.unicode_at(i), _fs).x
				if x > cl.position.x - cw and x < cl.end.x:
					draw_char(_font, Vector2(x, y), text[i], _fs, c)
				x += cw
				if x > cl.end.x:
					break
		return
	var prompt := "%s@%s:~$ " % [String(_scr.get("user", "guest")).to_lower().split(" ")[0], String(_scr.get("site", "site")).to_lower().replace(" ", "-")]
	draw_string(_font, Vector2(f.position.x + _fs * 0.8, y), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Color(c, 0.7))
	var pw := _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	if fmod(_t, 1.0) < 0.55:
		draw_rect(Rect2(Vector2(f.position.x + _fs * 0.8 + pw, y - _fs * 0.8), Vector2(_fs * 0.55, _fs * 0.95)), c)

## How far the radar reaches: the terminal's survey range (Lore.LOOK).
func _range() -> float:
	return float(_scr.get("range", 1600.0))

static var _mono_font: Font

## The terminals' fixed-width face.
static func mono() -> Font:
	if _mono_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "monospace"])
		_mono_font = f
	return _mono_font

# --- The tube ------------------------------------------------------------------------

static var _crt_sh: Shader

static func _crt_shader() -> Shader:
	if _crt_sh == null:
		_crt_sh = Shader.new()
		_crt_sh.code = """
shader_type canvas_item;
// Scan lines, a slow rolling band, a dark rim and a breath of flicker over the window.
void fragment() {
	float scan = mod(FRAGCOORD.y, 3.0) < 1.0 ? 0.16 : 0.0;
	vec2 d = UV - 0.5;
	float rim = smoothstep(0.32, 0.75, length(d * vec2(0.9, 1.1)));
	float roll = 1.0 - smoothstep(0.0, 0.08, abs(fract(UV.y - TIME * 0.12) - 0.5));
	float a = scan + rim * 0.45 - roll * 0.06 + 0.025 * sin(TIME * 53.0);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 0.8));
}
"""
	return _crt_sh
