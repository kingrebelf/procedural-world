class_name DialogueUI
extends Control
## Conversation window. Type anything, speak (hold the mic button, or hold the voice key
## while looking at someone), or pick a suggested reply. With a model connected the NPC
## answers in character from its personality and memories; without one, the built-in
## dialogue answers. Replies are spoken aloud (Voice) and can make the person act:
## follow, trade, give or lend you Marks, hand you a gift, dance, sit, wave, wink, hold up
## fingers... The Give tab hands them Marks or anything you carry; armour gets worn.

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
var _mic: Microphone
var _mic_btn: Button
var _extra: Control ## the Give / Ask drawer, when open
var _body: VBoxContainer

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("dialogue_ui")
	_mic = Microphone.new()
	add_child(_mic)

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
	Voice.speak(n.rec, first)
	if int(n.rec.get("rel", 0)) > 10:
		n.act("wave")
	elif NPCSocial.overdue(n.rec):
		_add_line(n.rec["name"].split(" ")[0], "And you still owe me %d Marks." % n.rec["debt"], UITheme.ACCENT)
	_history.append({"role": "user", "content": "(The traveller walks up to you.)"})
	_history.append({"role": "assistant", "content": JSON.stringify({"say": first})})
	_set_options(NPCMind.default_options(n.rec))
	_input.grab_focus()

func close_talk() -> void:
	if npc == null:
		return
	if _mic.recording:
		_mic.stop()
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
		return
	# Hold the voice key to speak to whoever you are looking at (or are talking to).
	if InputMap.has_action("voice") and event.is_action("voice") and not event.is_echo():
		if event.is_pressed():
			if npc == null and not menus.is_open():
				var f: Dictionary = player.focus if "focus" in player else {}
				if f.get("kind", "") == "npc" and is_instance_valid(f.get("npc")):
					open_with(f["npc"])
			if npc != null:
				_mic_start()
		elif _mic.recording:
			_mic_stop()
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
	head.add_child(UITheme.button("Trade", _open_trade))
	head.add_child(UITheme.button("Give", _show_give))
	head.add_child(UITheme.button("Ask", _show_ask))
	head.add_child(UITheme.button("Goodbye", close_talk))
	v.add_child(head)
	_body = v
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
	_mic_btn = UITheme.button("Hold to speak", func(): pass)
	_mic_btn.button_down.connect(_mic_start)
	_mic_btn.button_up.connect(_mic_stop)
	_mic_btn.tooltip_text = "Speak instead of typing (or hold %s while looking at someone). Needs a speech-to-text server in Settings > AI." % _voice_key()
	row.add_child(_mic_btn)
	v.add_child(row)
	_status = UITheme.label(_mode_text(), 12, UITheme.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var safe := text.replace("[i]", "\u0001").replace("[/i]", "\u0002").replace("[", "(").replace("]", ")").replace("\u0001", "[i][color=#9aa3ad]").replace("\u0002", "[/color][/i]")
	_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [c.to_html(false), who, safe])

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
	var doing := NPCMind.reply_do(d)
	var mem := {"say": say}
	if doing != "":
		mem["do"] = doing
	_history.append({"role": "assistant", "content": JSON.stringify(mem)})
	_add_line(n.rec["name"].split(" ")[0], say + ("  [i](%s)[/i]" % doing.replace("_", " ") if doing != "" else ""), UITheme.ACCENT)
	n.say(say, 6.0)
	Voice.speak(n.rec, say)
	var action := NPCMind.apply_reply(n.rec, n.settlement, d)
	var opts := NPCMind.clean_options(d)
	_set_options(opts if not opts.is_empty() else NPCMind.default_options(n.rec))
	manager.mark_dirty(n.settlement)
	if doing != "":
		n.act(doing)
	_act(action, d)

func _act(action: String, d: Dictionary = {}) -> void:
	var first: String = npc.rec["name"].split(" ")[0]
	match action:
		"give_money", "lend_money":
			var kind := "lend" if action == "lend_money" else "beg"
			# The model names the sum; their purse and nature cap it.
			var cap := maxi(NPCSocial.will_give(npc.rec, kind) * 2, 1)
			var want := int(d.get("marks", NPCSocial.will_give(npc.rec, kind)))
			var n := NPCSocial.hand_over(npc.rec, clampi(want, 1, cap), kind)
			if n > 0:
				Game.add_money(n)
				npc.act("hand_over")
				Game.toast.emit("%s %s you %d Marks" % [first, "lent" if kind == "lend" else "gave", n])
				_add_line("", "(%s hands you %d Marks%s.)" % [first, n, ", to be repaid in three days" if kind == "lend" else ""], UITheme.DIM)
			manager.mark_dirty(npc.settlement)
		"gift":
			var g := NPCSocial.gift_for(npc.rec)
			npc.rec["gift_day"] = NPCSocial.day()
			if g.has("item") and Game.give(g["item"]):
				_add_line("", "(%s gives you %s.)" % [first, ItemDB.display_name(g["item"])], UITheme.DIM)
				npc.act("hand_over")
			elif g.has("marks"):
				var n := NPCSocial.hand_over(npc.rec, g["marks"], "beg")
				Game.add_money(n)
				_add_line("", "(%s gives you %d Marks.)" % [first, n], UITheme.DIM)
			manager.mark_dirty(npc.settlement)
		"ask_repay":
			npc.act("beckon")
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
	if npc.rec["job"] != "trader" or not npc.rec.has("stall"):
		# Anyone else trades the goods of their own work, from their own purse.
		if int(npc.rec.get("rel", 0)) <= -40:
			_add_line(npc.rec["name"].split(" ")[0], "I'm not trading with you.", UITheme.ACCENT)
			return
		var st := NPCSocial.shop(npc.rec)
		manager.mark_dirty(npc.settlement)
		close_talk()
		menus.open_trader(st, null)
		return
	var s := manager.trader_stall(npc)
	if s.is_empty():
		_add_line("", "(The stall is out of reach.)", UITheme.DIM)
		return
	Economy.tick(s[0], Game.day)
	close_talk()
	menus.open_trader(s[0], s[1])

# --- Giving and asking --------------------------------------------------------------------------

func _close_extra() -> void:
	if _extra:
		_extra.queue_free()
		_extra = null

func _drawer(title: String) -> VBoxContainer:
	_close_extra()
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.sb(Color(0.06, 0.07, 0.08, 0.95), Color(1, 1, 1, 0.1), 10, 1, 12))
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 1.0
	pc.anchor_bottom = 1.0
	pc.offset_left = -440
	pc.offset_right = 440
	pc.offset_top = -760
	pc.offset_bottom = -440
	add_child(pc)
	_extra = pc
	var v := VBoxContainer.new()
	pc.add_child(v)
	var h := HBoxContainer.new()
	var t := UITheme.label(title, 18, UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UITheme.button("Close", _close_extra))
	v.add_child(h)
	return v

## Give Marks or anything you carry. Armour is put on and shows on them.
func _show_give() -> void:
	var v := _drawer("Give %s something   ·   you have %d Marks" % [npc.rec["name"].split(" ")[0], Game.money])
	var row := HBoxContainer.new()
	row.add_child(UITheme.label("Marks:", 15))
	for amt in [1, 5, 10, 25, 50, 100]:
		var b := UITheme.button(str(amt), func(): _give_marks(amt))
		b.disabled = Game.money < amt
		row.add_child(b)
	if int(npc.rec.get("debt", 0)) > 0:
		var debt: int = npc.rec["debt"]
		var b := UITheme.button("Repay %d" % debt, func(): _give_marks(debt))
		b.disabled = Game.money < debt
		row.add_child(b)
	v.add_child(row)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	v.add_child(sc)
	for i in Inventory.SIZE:
		var it = Game.inventory.get_slot(i)
		if it == null:
			continue
		var idx := i
		var b := UITheme.button(ItemDB.display_name(it) + ("  x%d" % it["qty"] if int(it.get("qty", 1)) > 1 else ""), func(): _give_item(idx))
		b.tooltip_text = UITheme.describe_item(it)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)

func _give_marks(amt: int) -> void:
	if npc == null or Game.money < amt:
		return
	Game.add_money(-amt)
	var r := NPCSocial.receive_marks(npc.rec, amt)
	_reaction("(You give %d Marks.)" % amt, r["line"], "thumbs_up" if r["rel"] >= 3 else "nod")
	_history.append({"role": "user", "content": "(The traveller gives you %d Marks.)" % amt})
	_show_give()

func _give_item(idx: int) -> void:
	var it = Game.inventory.get_slot(idx)
	if it == null or npc == null:
		return
	var one: Dictionary = Game.inventory.remove_at(idx, 1)
	if one.is_empty():
		return
	var r := NPCSocial.receive_item(npc.rec, one)
	var what := ItemDB.display_name(one)
	var doing := "thumbs_up"
	match r["use"]:
		"wear", "hold":
			npc.refresh_gear()
			doing = "cheer" if r["rel"] >= 8 else "thumbs_up"
		"eat":
			doing = "eat"
	_reaction("(You give %s.)" % what, r["line"], doing)
	_history.append({"role": "user", "content": "(The traveller gives you %s.)" % what})
	_show_give()

func _reaction(note: String, line: String, doing: String) -> void:
	_add_line("", note, UITheme.DIM)
	if line != "":
		_add_line(npc.rec["name"].split(" ")[0], line, UITheme.ACCENT)
		npc.say(line, 5.0)
		Voice.speak(npc.rec, line)
		_history.append({"role": "assistant", "content": JSON.stringify({"say": line})})
	npc.act(doing)
	_panel_header_refresh()
	manager.mark_dirty(npc.settlement)

func _panel_header_refresh() -> void:
	if _body and _body.get_child_count() > 0:
		var head := _body.get_child(0)
		var tv := head.get_child(0)
		if tv.get_child_count() > 1:
			(tv.get_child(1) as Label).text = "%s of %s    %s" % [npc.rec["job"].capitalize(), npc.settlement["name"], _relation_text()]

## Ask them to do things. They decide by personality (and the model, if connected).
const ASKS := [
	["Wave", "Can you wave?"], ["Dance", "Can you dance for me?"], ["Sit down", "Please sit down."], ["Stand up", "Please stand up."],
	["Jump", "Can you jump?"], ["Wink", "Can you wink at me?"], ["Nod", "Can you nod?"], ["Shake head", "Can you shake your head?"],
	["Bow", "Please bow."], ["Salute", "Can you salute?"], ["Thumbs up", "Give me a thumbs up."], ["Thumbs down", "Give me a thumbs down."],
	["1 finger", "Hold up one finger."], ["2 fingers", "Hold up two fingers."], ["3 fingers", "Hold up three fingers."], ["4 fingers", "Hold up four fingers."],
	["5 fingers", "Hold up five fingers."], ["Index finger", "Show me your index finger."], ["Middle finger", "Show me your middle finger."], ["Pinky", "Show me your pinky."],
	["Peace sign", "Can you do a peace sign?"], ["Count to five", "Can you count to five on your fingers?"], ["Point", "Can you point?"], ["Shrug", "Can you shrug?"],
	["Clap", "Can you clap?"], ["Cheer", "Can you cheer?"], ["Pray", "Can you pray?"], ["Think", "Show me your thinking pose."],
	["Facepalm", "Do a facepalm."], ["Crouch", "Can you crouch?"], ["Kneel", "Please kneel."], ["Roll", "Can you do a roll?"],
	["Flip", "Can you do a flip?"], ["Play dead", "Can you play dead?"], ["Zombie", "Can you act like a zombie?"], ["Cast a spell", "Can you cast a spell?"],
	["Spar", "Let's spar."], ["Follow me", "Come with me."], ["Stop following", "Stay here."], ["Spare some Marks?", "Could you spare some Marks?"],
	["Lend me Marks", "Could you lend me 20 Marks?"], ["A gift?", "Do you have a gift for me?"], ["Go home", "You should go home."],
]

func _show_ask() -> void:
	var v := _drawer("Ask %s to..." % npc.rec["name"].split(" ")[0])
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 5
	sc.add_child(grid)
	v.add_child(sc)
	for a in ASKS:
		var line: String = a[1]
		var b := UITheme.button(a[0], func(): _send(line))
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)

# --- Voice input --------------------------------------------------------------------------------

func _voice_key() -> String:
	var ev := InputMap.action_get_events("voice") if InputMap.has_action("voice") else []
	return ev[0].as_text().split(" ")[0] if not ev.is_empty() else "B"

func _mic_start() -> void:
	if npc == null or _busy:
		return
	if not AI.stt_enabled():
		_status.text = "Speech-to-text isn't set up. In Settings > AI, use an OpenAI-compatible provider, or set a speech-to-text server."
		return
	if not _mic.start():
		_status.text = "No microphone input available (check your OS microphone permission)."
		return
	_status.text = "Listening... release to send."
	if _mic_btn:
		_mic_btn.text = "Listening..."

func _mic_stop() -> void:
	if _mic_btn:
		_mic_btn.text = "Hold to speak"
	if not _mic.recording:
		return
	var wav := _mic.stop()
	if wav.is_empty():
		_status.text = _mode_text()
		return
	_status.text = "Understanding what you said..."
	var r: Dictionary = await AI.transcribe(wav)
	if npc == null:
		return
	if not r["ok"] or String(r["text"]).strip_edges() == "":
		_status.text = "Couldn't make that out (%s)." % (r["error"] if r["error"] != "" else "silence")
		return
	_status.text = _mode_text()
	_send(r["text"])
