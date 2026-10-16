class_name DialogueUI
extends Control
## Conversation window. Type anything, or pick a suggested reply. With a model connected
## the NPC answers in character from its personality and memories; without one, the
## built-in dialogue answers. The NPC's reply can also make it act (follow, trade, leave).

var player: Player
var menus: GameMenus
var manager: NPCManager

var npc: NPC
var _history: Array = [] ## [{role, content}] for this conversation.
var _panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit
var _opts: HBoxContainer
var _status: Label
var _busy := false

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("dialogue_ui")

func is_open() -> bool:
	return npc != null

func open_with(n: NPC) -> void:
	if npc != null or menus.is_open():
		return
	npc = n
	_history.clear()
	manager.begin_talk(n)
	_build()
	visible = true
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first: String = NPCMind.bark(n.rec, "greet") if int(n.rec.get("rel", 0)) > -40 else "What do you want?"
	_add_line(n.rec["name"].split(" ")[0], first, UITheme.ACCENT)
	_history.append({"role": "user", "content": "(The traveller walks up to you.)"})
	_history.append({"role": "assistant", "content": JSON.stringify({"say": first})})
	_set_options(NPCMind.default_options(n.rec))
	_input.grab_focus()

func close_talk() -> void:
	if npc == null:
		return
	if _history.size() > 2 and not AI.dialogue_enabled():
		NPCMind.remember(npc.rec, "Chatted with the traveller.")
	manager.end_talk(npc)
	npc = null
	visible = false
	if _panel:
		_panel.queue_free()
		_panel = null
	player.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if npc != null and event.is_action_pressed("pause"):
		close_talk()
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	if npc != null and (not is_instance_valid(npc) or npc.global_position.distance_to(player.global_position) > 8.0):
		npc = null if not is_instance_valid(npc) else npc
		if npc == null:
			visible = false
			player.ui_open = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if _panel:
				_panel.queue_free()
				_panel = null
		else:
			close_talk()

func _build() -> void:
	if _panel:
		_panel.queue_free()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.06, 0.07, 0.08, 0.92), Color(1, 1, 1, 0.1), 10, 1, 16))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -440
	_panel.offset_right = 440
	_panel.offset_top = -430
	_panel.offset_bottom = -150
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_child(UITheme.title(npc.rec["name"], 24))
	var who := "%s of %s" % [npc.rec["job"].capitalize(), npc.settlement["name"]]
	tv.add_child(UITheme.label("%s    %s" % [who, _relation_text()], 14, UITheme.DIM))
	head.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if npc.rec["job"] == "trader":
		head.add_child(UITheme.button("Trade", _open_trade))
	head.add_child(UITheme.button("Goodbye", close_talk))
	v.add_child(head)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 17)
	v.add_child(_log)
	_opts = HBoxContainer.new()
	_opts.add_theme_constant_override("separation", 6)
	v.add_child(_opts)
	var row := HBoxContainer.new()
	_input = LineEdit.new()
	_input.placeholder_text = "Say something..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(t): _send(t))
	row.add_child(_input)
	row.add_child(UITheme.button("Say", func(): _send(_input.text)))
	v.add_child(row)
	_status = UITheme.label(_mode_text(), 12, UITheme.DIM)
	v.add_child(_status)

func _mode_text() -> String:
	if AI.dialogue_enabled():
		return "Voiced by %s (%s). Esc to leave." % [AI.provider_label(), AI.get_value("model")]
	return "Built-in dialogue. Connect a local or cloud AI in Settings > AI for free conversation. Esc to leave."

func _relation_text() -> String:
	var r := int(npc.rec.get("rel", 0))
	var word := "Hostile" if r <= -40 else ("Wary" if r < -5 else ("Neutral" if r < 15 else ("Friendly" if r < 50 else "Trusted")))
	return "%s (%d)    Feeling %s" % [word, r, npc.rec.get("mood", "calm")]

func _add_line(who: String, text: String, c: Color) -> void:
	_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [c.to_html(false), who, text.replace("[", "(").replace("]", ")")])

func _set_options(opts: Array) -> void:
	for ch in _opts.get_children():
		ch.queue_free()
	for o in opts:
		var b := UITheme.button(o, func(): _send(o))
		b.add_theme_font_size_override("font_size", 14)
		_opts.add_child(b)

func _send(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _busy or npc == null:
		return
	_input.text = ""
	_add_line("You", text, UITheme.ACCENT_2)
	_history.append({"role": "user", "content": text})
	var n := npc
	var d: Dictionary
	if AI.dialogue_enabled():
		_busy = true
		_status.text = "%s is thinking..." % n.rec["name"].split(" ")[0]
		var held = player.held_item()
		var ctx := {"held": ItemDB.display_name(held) if held != null else ""}
		var r: Dictionary = await AI.chat_json(NPCMind.system_prompt(n.rec, n.settlement, ctx), _history.slice(-12))
		_busy = false
		if npc != n:
			return
		if r["ok"] and String(r["data"].get("say", "")).strip_edges() != "":
			d = r["data"]
			_status.text = _mode_text()
		else:
			d = NPCMind.builtin_reply(n.rec, n.settlement, text)
			_status.text = "AI unavailable (%s); using built-in dialogue." % r.get("error", "no reply")
	else:
		d = NPCMind.builtin_reply(n.rec, n.settlement, text)
	var say := String(d.get("say", "...")).strip_edges().left(600)
	_history.append({"role": "assistant", "content": JSON.stringify({"say": say})})
	_add_line(n.rec["name"].split(" ")[0], say, UITheme.ACCENT)
	n.say(say, 6.0)
	var action := NPCMind.apply_reply(n.rec, n.settlement, d)
	var opts := NPCMind.clean_options(d)
	_set_options(opts if not opts.is_empty() else NPCMind.default_options(n.rec))
	manager.mark_dirty(n.settlement)
	_act(action)

func _act(action: String) -> void:
	match action:
		"trade":
			_open_trade()
		"follow":
			manager.instruct(npc, "follow", 1800.0)
			Game.toast.emit("%s is following you" % npc.rec["name"].split(" ")[0])
		"stop_following":
			manager.instruct(npc, "stop_following", 0.0)
		"go_home", "leave", "flee", "attack":
			var n := npc
			close_talk()
			manager.instruct(n, action, 60.0)

func _open_trade() -> void:
	var s := manager.trader_stall(npc)
	if s.is_empty():
		_add_line("", "(The stall is out of reach.)", UITheme.DIM)
		return
	Economy.tick(s[0], Game.day)
	close_talk()
	menus.open_trader(s[0], s[1])
