class_name LoreUI
extends Control
## The window a readable or usable room prop opens (see Lore): a terminal's screen (a
## little operating system drawn in code, TerminalUI), or a page of parchment for books,
## letters, scrolls and epitaphs. Tabs for each page, buttons for what the thing can do,
## and Esc or Interact to step away.

var player: Player

var _panel: Control ## the parchment page, or the terminal window
var _body: RichTextLabel
var _tabs: HBoxContainer
var _actions: HBoxContainer
var _note: Label
var _entry: Dictionary = {}
var _page := 0
var _chunk: ChunkNode
var _i := -1
var _spot := -1
var _opened_at := 0
var _screen := false
var _at := Vector3.INF ## where a free-standing entry (open_entry) was read

const INK := Color(0.2, 0.13, 0.07)

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("lore_ui")

func is_open() -> bool:
	return _panel != null

## Opens spot `spot` of object `i` in `chunk`.
func open_spot(chunk: ChunkNode, i: int, spot: int) -> void:
	if is_open() or not is_instance_valid(chunk):
		return
	var o: Dictionary = chunk.get_object(i)
	if o.is_empty() or spot < 0 or spot >= Lore.spots(o["t"]).size():
		return
	_chunk = chunk
	_i = i
	_spot = spot
	_at = Vector3.INF
	_entry = Lore.read(o, chunk, spot, player.npcs)
	_screen = _entry["look"] == "screen"
	_page = 0
	_opened_at = Time.get_ticks_msec()
	_build()
	if not _screen:
		_show_page(0)
		if _entry.get("note", "") != "":
			_note.text = _entry["note"]
	visible = true
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Opens a text that isn't a chunk's object (a dungeon's notice): `entry` as Lore.read
## gives it, closed again once you walk 12 m from `at`.
func open_entry(entry: Dictionary, at: Vector3) -> void:
	if is_open():
		return
	_chunk = null
	_i = -1
	_spot = -1
	_at = at
	_entry = entry
	_screen = _entry.get("look", "") == "screen"
	_page = 0
	_opened_at = Time.get_ticks_msec()
	_build()
	if not _screen:
		_show_page(0)
	visible = true
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The text of the page showing (the first page while a terminal boots).
func page_text() -> String:
	if not is_open():
		return ""
	return String(_entry["pages"][_page if not _screen else (_panel as TerminalUI)._page]["text"])

func close() -> void:
	if not is_open():
		return
	_panel.queue_free()
	_panel = null
	visible = false
	player.ui_open = false
	Cursor.restore()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	var quick := Time.get_ticks_msec() - _opened_at < 250 # the press that opened us
	if event.is_action_pressed("pause") or (event.is_action_pressed("interact") and not quick) \
			or (event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		# LB / RB turn the page.
		var n := (_entry["pages"] as Array).size()
		if n > 1:
			var to := posmod(_page_now() + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), n)
			if _screen:
				(_panel as TerminalUI)._show_page(to)
			else:
				_show_page(to)
		get_viewport().set_input_as_handled()

func _page_now() -> int:
	return (_panel as TerminalUI)._page if _screen else _page

func _process(_d: float) -> void:
	if not is_open():
		return
	if _at != Vector3.INF:
		if player.global_position.distance_to(_at) > 12.0:
			close()
		return
	var o: Dictionary = _chunk.get_object(_i) if is_instance_valid(_chunk) else {}
	if o.is_empty() or player.global_position.distance_to(_chunk.position + o["p"]) > 12.0:
		close()

func _build() -> void:
	if _screen:
		var term := TerminalUI.new()
		term.setup(_entry, _act, close)
		_panel = term
		add_child(term)
		return
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _parchment())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -400
	_panel.offset_right = 400
	_panel.offset_top = -280
	_panel.offset_bottom = 280
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var t := UITheme.title(_entry["title"], 26)
	t.add_theme_color_override("font_color", INK)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	t.add_theme_constant_override("outline_size", 0)
	v.add_child(t)
	v.add_child(UITheme.label(_entry.get("sub", ""), 14, Color(INK, 0.7)))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	v.add_child(_tabs)
	var pages: Array = _entry["pages"]
	if pages.size() > 1:
		for n in pages.size():
			var b := UITheme.button(String(pages[n]["tab"]), func(): _show_page(n))
			b.add_theme_font_size_override("font_size", 14)
			b.toggle_mode = true
			_tabs.add_child(b)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.add_theme_font_size_override("italics_font_size", 18)
	_body.add_theme_color_override("default_color", INK)
	v.add_child(_body)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	v.add_child(_actions)
	_note = UITheme.label("", 15, Color(0.45, 0.22, 0.05))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)
	var foot := HBoxContainer.new()
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	foot.add_child(UITheme.button("Step away", close))
	v.add_child(foot)

func _show_page(n: int) -> void:
	_page = n
	var pg: Dictionary = _entry["pages"][n]
	_body.text = String(pg["text"])
	_body.scroll_to_line(0)
	for k in _tabs.get_child_count():
		(_tabs.get_child(k) as Button).button_pressed = k == n
	for ch in _actions.get_children():
		ch.queue_free()
	for a in pg.get("actions", []):
		var id: String = a[0]
		_actions.add_child(UITheme.button(String(a[1]), func(): _act(id)))
	UITheme.focus_first(_panel)

func _act(id: String) -> String:
	if not is_instance_valid(_chunk):
		return ""
	var msg := Lore.act(_chunk.get_object(_i), _chunk, _spot, id, player)
	if _note:
		_note.text = msg
	Game.toast.emit(msg)
	return msg

static var _parch: StyleBox

## The atlas's parchment where it is there, else a warm flat page.
static func _parchment() -> StyleBox:
	if _parch == null:
		var path := "res://assets/map/parchment.jpg"
		if ResourceLoader.exists(path):
			var s := StyleBoxTexture.new()
			s.texture = load(path)
			s.set_texture_margin_all(40)
			s.set_content_margin_all(34)
			_parch = s
		else:
			_parch = UITheme.sb(Color(0.86, 0.78, 0.6, 0.98), Color(0.4, 0.28, 0.12), 4, 3, 30)
	return _parch
