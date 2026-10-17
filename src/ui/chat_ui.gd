class_name ChatUI
extends Control
## Server chat: the last few lines fade in the lower left; Enter (rebindable) opens a
## line to type in. Lines starting with / are server commands (/admin <password>,
## then /kick, /set and the rest; /help lists them). Only shown on a server.

const KEEP := 10
const FADE_AFTER := 12.0

var player: Player
var _lines: VBoxContainer
var _input: LineEdit
var _ages: Array = []

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -470
	box.offset_bottom = -170
	box.offset_left = 24
	box.offset_right = 584
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)
	_lines = VBoxContainer.new()
	_lines.alignment = BoxContainer.ALIGNMENT_END
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_lines)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something (Enter), /a to your alliance, or /help"
	_input.max_length = 240
	_input.visible = false
	_input.text_submitted.connect(_send)
	_input.gui_input.connect(_on_key)
	box.add_child(_input)
	Net.chat.connect(_on_chat)
	visible = Net.is_client()

func _on_chat(from: String, text: String, kind: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 16)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	var safe := text.replace("[", "[lb]")
	match kind:
		"chat":
			l.text = "[color=#e8c26a]%s:[/color] %s" % [from.replace("[", "[lb]"), safe]
		"admin":
			l.text = "[color=#9ab]%s[/color]" % safe
		"ally":
			if from != "":
				l.text = "[color=#7fdc8a][Alliance] %s:[/color] %s" % [from.replace("[", "[lb]"), safe]
			else:
				l.text = "[color=#7fdc8a]%s[/color]" % safe
		_:
			l.text = "[color=#cfd8b0]%s[/color]" % safe
	_lines.add_child(l)
	_ages.append(0.0)
	while _lines.get_child_count() > KEEP:
		_lines.get_child(0).queue_free()
		_lines.remove_child(_lines.get_child(0))
		_ages.pop_front()

func _process(delta: float) -> void:
	var n := _lines.get_child_count()
	for i in n:
		_ages[i] = float(_ages[i]) + delta
		var a := 1.0 if _input.visible else clampf(FADE_AFTER + 1.0 - float(_ages[i]), 0.0, 1.0)
		(_lines.get_child(i) as Control).modulate.a = a

func _unhandled_input(event: InputEvent) -> void:
	if not Net.is_client() or _input.visible:
		return
	if event.is_action_pressed("chat") and player != null and not player.ui_open:
		open()
		get_viewport().set_input_as_handled()

func open() -> void:
	_input.visible = true
	_input.clear()
	if player:
		player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input.grab_focus.call_deferred()

func close() -> void:
	_input.visible = false
	_input.release_focus()
	if player:
		player.ui_open = false
	Cursor.restore()

func _on_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _send(text: String) -> void:
	close()
	text = text.strip_edges()
	if text == "":
		return
	if text.begins_with("/a ") or text.begins_with("/ally "):
		Net.ally("chat", text.substr(text.find(" ") + 1)) # to your alliance only
	elif text.begins_with("/"):
		_on_chat("", "> " + text, "admin")
		Net.admin(text.substr(1))
	else:
		Net.say(text)
