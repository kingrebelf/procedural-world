class_name DialogueUI
extends Control
## Conversation window. Type anything, speak (hold the mic button, or hold the voice key
## while looking at someone), or pick a suggested reply. With a model connected the NPC
## answers in character from its personality and memories; without one, the built-in
## dialogue answers. Replies are spoken aloud (Voice) and can make the person act:
## follow, trade, give or lend you Marks, hand you a gift, dance, sit, wave, wink, hold up
## fingers... The Give tab hands them Marks or anything you carry; armour gets worn.
##
## Open mic (Settings > AI, or the open mic key): the microphone stays on. Said in a
## conversation, it is your reply. Said out loud near people ("Can anyone spare me five
## Marks?"), the people within earshot hear it, but only one who is willing answers (the
## one you face, else the nearest who would say yes); the rest ignore you, so voices never
## pile up. That person carries on talking with you hands-free, without this window,
## until you stop talking to them or walk off.

var player: Player
var menus: GameMenus
var manager: NPCManager

var npc: NPC
var _history: Array = [] ## [{role, content}] for this conversation.
var _panel: PanelContainer
var _log: RichTextLabel
var _entry: LineEdit
var _opts: HBoxContainer
var _status: Label
var _busy := false
var _mic: Microphone
var _mic_btn: Button
var _extra: Control ## the Give / Ask drawer, when open
var _body: VBoxContainer
var _join_btn: Button
## A conversation without the window (open mic): the person answers out loud and you talk
## back hands-free. Its log, status and options live off screen.
var _ambient := false
var _amb_t := 0.0 ## seconds since the last thing either of you said
var _amb_met := false ## they have come over (begin_talk)
var _hearing := false ## an open-mic phrase is being understood
var _hear_err_t := -100.0
var _mic_tag: Label

const HEAR_RADIUS := 14.0 ## how far people hear you on the open mic
const AMBIENT_SECONDS := 25.0 ## quiet this long ends a hands-free conversation
## The quick answers that mean "I'll help / I'll answer you" (Interject kinds).
const WILLING := ["yes", "think", "greet", "thanks"]

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("dialogue_ui")
	_mic = Microphone.new()
	add_child(_mic)
	_mic.heard.connect(_on_heard)
	_mic.paused_by = Voice.sounding # never hear the game's own voices

func is_open() -> bool:
	return npc != null

func open_with(n: NPC) -> void:
	if menus.is_open():
		return
	var kept: Array = []
	if _ambient:
		# Walking up to someone you're already talking to keeps the conversation going.
		if n == npc:
			kept = _history.duplicate()
		_end_ambient()
	if npc != null:
		return
	npc = n
	_history.clear()
	manager.begin_talk(n)
	_build()
	visible = true
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not kept.is_empty():
		_history = kept
		_replay()
		_set_options(NPCMind.default_options(n.rec))
		_status.text = "Hold %s to talk, or press Enter to type." % _voice_key()
		return
	var first: String = NPCMind.bark(n.rec, "greet") if int(n.rec.get("rel", 0)) > -40 else "What do you want?"
	if n.rec.has("shop_kind") and int(n.rec.get("rel", 0)) > -40:
		first = TownShops.greeting(n.rec, _shop())
	_add_line(n.rec["name"].split(" ")[0], first, UITheme.ACCENT)
	Voice.speak(n.rec, first, 0.0, true, n)
	Voice.prefetch(n.rec, ["think", "yes", "no", "maybe"].map(func(k): return Interject.line(n.rec, k)))
	if int(n.rec.get("rel", 0)) > 10:
		n.act("wave")
	elif NPCSocial.overdue(n.rec):
		_add_line(n.rec["name"].split(" ")[0], "And you still owe me %d Marks." % n.rec["debt"], UITheme.ACCENT)
	_history.append({"role": "user", "content": "(The traveller walks up to you.)"})
	_history.append({"role": "assistant", "content": JSON.stringify({"say": first})})
	_set_options(NPCMind.default_options(n.rec))
	# The text box waits for Enter or a click, so the voice key always works.
	_status.text = "Hold %s to talk, or press Enter to type." % _voice_key()

func close_talk() -> void:
	if npc == null:
		return
	if _mic.recording:
		_mic.stop()
	if _ambient:
		_end_ambient()
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
	Cursor.restore()

func _unhandled_input(event: InputEvent) -> void:
	if _pick_npc != null and event.is_action_pressed("pause"):
		close_pickpocket()
		get_viewport().set_input_as_handled()
		return
	if npc != null and not _ambient and event.is_action_pressed("pause"):
		close_talk()
		get_viewport().set_input_as_handled()
		return
	if npc != null and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		if _ambient:
			open_with(npc) # typing needs the window
			if npc == null or _ambient:
				return
		_entry.grab_focus()
		get_viewport().set_input_as_handled()
		return
	# Hold the voice key to speak to whoever you are looking at (or are talking to).
	if InputMap.has_action("voice") and event.is_action("voice") and not event.is_echo():
		if event.is_pressed():
			var f: Dictionary = player.focus if "focus" in player else {}
			var looked: NPC = f["npc"] if f.get("kind", "") == "npc" and is_instance_valid(f.get("npc")) else null
			if _ambient and looked != null and looked != npc:
				_end_ambient() # you turned to someone else
			if npc == null and not menus.is_open() and looked != null:
				open_with(looked)
			if npc != null:
				_mic_start()
		get_viewport().set_input_as_handled()

	if InputMap.has_action("open_mic") and event.is_action_pressed("open_mic") and not event.is_echo():
		var on := not bool(AI.get_value("open_mic"))
		AI.set_value("open_mic", on)
		Game.toast.emit("Open mic on: people near you can hear you" if on else "Open mic off")
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Letting go of the voice key always ends the recording, wherever focus is.
	if _mic.recording and InputMap.has_action("voice") and event.is_action_released("voice"):
		_mic_stop()
		get_viewport().set_input_as_handled()

func _process(_d: float) -> void:
	if _pick_npc != null and (not is_instance_valid(_pick_npc) or _pick_npc.global_position.distance_to(player.global_position) > 2.8 or _pick_npc.action in ["flee", "attack", "confront"]):
		close_pickpocket()
	if _mic.recording and _mic_btn:
		_mic_btn.text = "Listening " + "|".repeat(1 + int(_mic.level() * 9.0))
	_sync_open_mic()
	if _ambient:
		_ambient_tick(_d)
		return
	if npc != null and (not is_instance_valid(npc) or npc.global_position.distance_to(player.global_position) > 8.0):
		npc = null if not is_instance_valid(npc) else npc
		if npc == null:
			visible = false
			player.ui_open = false
			Cursor.restore()
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
	var who := _who()
	tv.add_child(UITheme.label("%s    %s" % [who, _relation_text()], 14, UITheme.DIM))
	head.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var owe := manager.bounty_for(npc)
	if owe > 0 and NPCGen.GUARD_JOBS.has(npc.rec["job"]):
		var pay := UITheme.button("Pay bounty (%d)" % owe, func(): pass)
		pay.pressed.connect(func(): _pay_bounty(pay))
		pay.disabled = Game.money < owe
		pay.tooltip_text = "Settle what you owe %s and the guards stand down." % npc.settlement["name"]
		head.add_child(pay)
	if not manager.gates.gate_of(npc).is_empty():
		var gb := UITheme.button("Gate", _show_gate)
		gb.tooltip_text = "Ask to be let into %s: your standing, the toll, a bribe, or a friend in town to vouch for you." % npc.settlement["name"]
		head.add_child(gb)
	var kind: String = npc.rec.get("shop_kind", "")
	if kind == "land":
		head.add_child(UITheme.button("Houses", _show_houses))
	else:
		head.add_child(UITheme.button("Trade", _open_trade))
	if TownShops.is_guild(kind) and not Game.guilds.has(kind):
		_join_btn = UITheme.button("Join", _join_guild)
		head.add_child(_join_btn)
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
	_entry = LineEdit.new()
	_entry.placeholder_text = "Say something..."
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(t): _send(t))
	row.add_child(_entry)
	row.add_child(UITheme.button("Say", func(): _send(_entry.text)))
	_mic_btn = UITheme.button("Hold to speak", func(): pass)
	_mic_btn.button_down.connect(_mic_start)
	_mic_btn.button_up.connect(_mic_stop)
	_mic_btn.tooltip_text = "Speak instead of typing (or hold %s while looking at someone). With open mic on (%s), just talk." % [_voice_key(), _open_mic_key()]
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

## `note`: what the person knows about how it was said (only the model sees it).
func _send(text: String, note := "") -> void:
	text = text.strip_edges()
	if text == "" or _busy or npc == null:
		return
	_amb_t = 0.0
	_entry.text = ""
	if _entry.is_inside_tree():
		_entry.release_focus() # back to the voice key
	_add_line("You", text, UITheme.ACCENT_2)
	_history.append({"role": "user", "content": note + text})
	var n := npc
	var d: Dictionary
	var quick := ""
	if AI.dialogue_enabled():
		_busy = true
		_status.text = "%s is thinking..." % n.rec["name"].split(" ")[0]
		if _ambient:
			n.act("think")
		var held = player.held_item()
		var ctx := {"held": ItemDB.display_name(held) if held != null else ""}
		var msgs := _history.slice(-12)
		if AI.get_value("quick_replies"):
			quick = await _quick_reply(n, text)
			if npc != n:
				_busy = false
				return
			if quick != "":
				# The model hears what was already said, so its answer carries on from it.
				msgs = msgs.duplicate(true)
				msgs[-1] = {"role": "user", "content": text + Interject.note_for_model(quick)}
		var r: Dictionary = await AI.chat_json(NPCMind.system_prompt(n.rec, n.settlement, ctx), msgs)
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
	var said := quick.to_lower().trim_suffix("...").trim_suffix(".")
	if quick != "" and say.to_lower().begins_with(said):
		say = say.substr(said.length()).lstrip(".!,; ").strip_edges() # don't say it twice
		if say == "":
			say = "..."
	var doing := NPCMind.reply_do(d)
	var mem := {"say": (quick + " " + say) if quick != "" else say}
	if doing != "":
		mem["do"] = doing
	_history.append({"role": "assistant", "content": JSON.stringify(mem)})
	_add_line(n.rec["name"].split(" ")[0], say + ("  [i](%s)[/i]" % doing.replace("_", " ") if doing != "" else ""), UITheme.ACCENT)
	n.say(say, 6.0)
	Voice.speak(n.rec, say, 0.0, true, n, quick != "")
	var action := NPCMind.apply_reply(n.rec, n.settlement, d)
	var opts := NPCMind.clean_options(d)
	_set_options(opts if not opts.is_empty() else NPCMind.default_options(n.rec))
	manager.mark_dirty(n.settlement)
	if doing != "":
		n.act(doing)
	_amb_t = 0.0
	_act(action, d)

func _act(action: String, d: Dictionary = {}) -> void:
	if npc == null:
		return
	if _ambient and action in ["trade", "join_guild", "buy_house"]:
		open_with(npc) # these need the window
		if npc == null or _ambient:
			return
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
		"pay_toll":
			var paid: int = manager.pay_toll(npc)
			if paid > 0:
				npc.act("hand_over")
				Game.toast.emit("You paid %s %d Marks" % [first, paid])
				_add_line("", "(You hand over %d Marks. They let you pass.)" % paid, UITheme.DIM)
			elif paid == 0:
				_add_line("", "(You have nothing to give.)", UITheme.DIM)
		"trade":
			_open_trade()
		"join_guild":
			_join_guild()
		"buy_house":
			_show_houses()
		"follow":
			manager.instruct(npc, "follow", 1800.0)
			Game.toast.emit("%s is following you" % npc.rec["name"].split(" ")[0])
		"stop_following":
			manager.instruct(npc, "stop_following", 0.0)
		"go_home", "leave", "flee", "attack":
			var n := npc
			close_talk()
			manager.instruct(n, action, 60.0)

func _who() -> String:
	if npc.rec.has("shop_kind"):
		var t: String = npc.rec.get("shop_title", "")
		var lbl: String = npc.rec.get("shop_label", "")
		if npc.rec["shop_kind"] == "land" or t == "":
			return "%s of %s, %s" % [npc.rec["job"].capitalize(), lbl if lbl != "" else "town", npc.settlement["name"]]
		return "%s of %s, %s" % [npc.rec["job"].capitalize(), t, npc.settlement["name"]]
	return "%s of %s" % [npc.rec["job"].capitalize(), npc.settlement["name"]]

## The shop this person keeps (TownShops plan entry), or {}.
func _shop() -> Dictionary:
	var site := manager.site_of(npc)
	return {} if site.is_empty() else TownShops.shop_of(manager.gen, site, npc.rec)

func _pay_bounty(btn: Button) -> void:
	var paid := manager.pay_bounty(npc)
	if paid < 0:
		return
	var line: String = ["Your debt to %s is paid. Keep your hands to yourself." % npc.settlement["name"], "Fine. You're free to go, for now.", "Paid in full. Don't let me catch you again."][randi() % 3]
	_add_line("", "(You pay a %d Mark bounty.)" % paid, UITheme.DIM)
	_add_line(npc.rec["name"].split(" ")[0], line, UITheme.ACCENT)
	npc.say(line, 5.0)
	Voice.speak(npc.rec, line)
	_history.append({"role": "user", "content": "(The traveller pays the %d Mark bounty they owed the town.)" % paid})
	_history.append({"role": "assistant", "content": JSON.stringify({"say": line})})
	npc.act("nod")
	btn.text = "Bounty paid"
	btn.disabled = true

# --- Pickpocketing ------------------------------------------------------------------------------
## Crouch behind someone and Interact: a small window of what they carry, each with its
## chance. Fail and they catch you; their town puts a bounty on you.

var _pick_npc: NPC
var _pick_panel: PanelContainer

func open_pickpocket(n: NPC) -> void:
	if npc != null or _pick_npc != null or menus.is_open() or not is_instance_valid(n):
		return
	if n.talking or n.action in ["flee", "attack", "confront"]:
		Game.toast.emit("%s is watching you too closely" % n.rec["name"].split(" ")[0])
		return
	if int(n.rec.get("caught_pick_day", -99)) == NPCMind.day_num():
		Game.toast.emit("%s is keeping a hand on their purse today" % n.rec["name"].split(" ")[0])
		return
	_pick_npc = n
	visible = true
	player.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_pick()

func close_pickpocket() -> void:
	if _pick_npc == null and _pick_panel == null:
		return
	_pick_npc = null
	if _pick_panel:
		_pick_panel.queue_free()
		_pick_panel = null
	if npc == null:
		visible = false
		player.ui_open = false
		Cursor.restore()

## Their back to you counts, and how alert they are right now.
func _pick_odds(worth: float) -> float:
	var n := _pick_npc
	var fwd := Vector2(sin(n.rotation.y), cos(n.rotation.y))
	var to := Vector2(player.global_position.x - n.global_position.x, player.global_position.z - n.global_position.z)
	var behind := to.length() < 0.01 or fwd.dot(to.normalized()) < 0.0
	return Game.stats.pickpocket_chance(worth, behind, manager.awareness(n, player.global_position))

func _build_pick() -> void:
	if _pick_panel:
		_pick_panel.queue_free()
	var n := _pick_npc
	var rec := n.rec
	NPCSocial.ensure(rec)
	_pick_panel = PanelContainer.new()
	_pick_panel.add_theme_stylebox_override("panel", UITheme.tex_sb("panel", 16, 14))
	_pick_panel.anchor_left = 0.5
	_pick_panel.anchor_right = 0.5
	_pick_panel.anchor_top = 0.5
	_pick_panel.anchor_bottom = 0.5
	_pick_panel.offset_left = -300
	_pick_panel.offset_right = 300
	_pick_panel.offset_top = -40
	_pick_panel.offset_bottom = 300
	add_child(_pick_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_pick_panel.add_child(v)
	var head := HBoxContainer.new()
	var first: String = rec["name"].split(" ")[0]
	var t := UITheme.title("Pick %s's pocket" % first, 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("Leave", close_pickpocket))
	v.add_child(head)
	v.add_child(UITheme.label("Pickpocketing %d  ·  stay behind them; dearer things are harder to lift" % Game.stats.skills["pick"], 14, UITheme.DIM))
	var purse := int(rec["purse"])
	if purse > 0:
		var take := maxi(1, purse)
		var odds := _pick_odds(float(take) * 0.6)
		v.add_child(_pick_row("Purse: %d Marks" % take, odds, func(): _try_pick(-1, take)))
	var pk: Array = NPCSocial.pockets(rec)
	for i in pk.size():
		var it: Dictionary = pk[i]
		var worth := float(ItemDB.def(it["type"]).get("value", 1)) * float(it.get("qty", 1))
		var idx := i
		v.add_child(_pick_row(ItemDB.display_name(it) + ("  x%d" % it["qty"] if int(it.get("qty", 1)) > 1 else ""), _pick_odds(worth), func(): _try_pick(idx, 0)))
	if purse <= 0 and pk.is_empty():
		v.add_child(UITheme.label("Their pockets are empty.", 16, UITheme.DIM))

func _pick_row(text: String, odds: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := UITheme.label(text, 17)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := UITheme.label("%d%%" % int(round(odds * 100.0)), 17, UITheme.ACCENT if odds >= 0.5 else Color(0.95, 0.5, 0.4))
	c.custom_minimum_size = Vector2(56, 0)
	row.add_child(c)
	row.add_child(UITheme.button("Steal", cb))
	return row

## idx >= 0: an item from their pockets; idx -1: `marks` from their purse.
func _try_pick(idx: int, marks: int) -> void:
	var n := _pick_npc
	if n == null or not is_instance_valid(n):
		close_pickpocket()
		return
	var rec := n.rec
	var first: String = rec["name"].split(" ")[0]
	var pk: Array = NPCSocial.pockets(rec)
	var worth := float(marks) * 0.6
	if idx >= 0:
		if idx >= pk.size():
			return
		worth = float(ItemDB.def(pk[idx]["type"]).get("value", 1)) * float(pk[idx].get("qty", 1))
	if randf() < _pick_odds(worth):
		var what := ""
		if idx < 0:
			var got := NPCSocial.lift_marks(rec, marks)
			Game.add_money(got)
			what = "%d Marks" % got
		else:
			var it: Dictionary = pk[idx]
			if not Game.give(it.duplicate(true)):
				return
			pk.remove_at(idx)
			what = ItemDB.display_name(it)
		Game.practice("pick", 3.0 + sqrt(worth))
		Game.add_xp(2.0 + sqrt(worth) * 0.5, "Pickpocketing")
		Game.toast.emit("Lifted %s from %s" % [what, first])
		manager.mark_dirty(n.settlement)
		_build_pick()
		return
	# Caught.
	Game.practice("pick", 1.0)
	rec["caught_pick_day"] = NPCMind.day_num()
	close_pickpocket()
	manager.report_crime(n.global_position, "pickpocket", int(worth), "", n)
	n.decide_in = 0.0
	manager.mark_dirty(n.settlement)

func _open_trade() -> void:
	if npc.rec.has("shop_kind"):
		var kind: String = npc.rec["shop_kind"]
		var first: String = npc.rec["name"].split(" ")[0]
		if int(npc.rec.get("rel", 0)) <= -40:
			_add_line(first, "Get out of my shop.", UITheme.ACCENT)
			return
		if kind == "land":
			_show_houses()
			return
		if TownShops.is_guild(kind) and not Game.guilds.has(kind):
			_add_line(first, "Guild goods are for members. %s" % TownShops.pitch(npc.rec), UITheme.ACCENT)
			return
		var st := TownShops.trade_state(npc.rec, _shop(), Game.guilds)
		manager.mark_dirty(npc.settlement)
		close_talk()
		menus.open_trader(st, null)
		return
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

# --- Guilds and houses ---------------------------------------------------------------------------

func _join_guild() -> void:
	var kind: String = npc.rec.get("shop_kind", "")
	if not TownShops.is_guild(kind):
		return
	var first: String = npc.rec["name"].split(" ")[0]
	var g: Dictionary = TownShops.GUILDS[kind]
	if Game.guilds.has(kind):
		_add_line(first, "You're already one of us.", UITheme.ACCENT)
		return
	var fee := TownShops.fee(kind, npc.rec)
	if int(npc.rec.get("rel", 0)) <= -30:
		_add_line(first, "We don't take your sort.", UITheme.ACCENT)
		return
	if Game.money < fee:
		_add_line(first, "Membership is %d Marks. Come back when you have it." % fee, UITheme.ACCENT)
		return
	Game.add_money(-fee)
	npc.rec["purse"] = int(npc.rec["purse"]) + fee
	Game.join_guild(kind, npc.settlement["name"])
	NPCMind.change_rel(npc.rec, 8)
	NPCMind.remember(npc.rec, "The traveller joined the %s." % g["label"])
	var line := "Welcome to the %s. %s" % [g["label"], g["perk"]]
	_reaction("(You pay %d Marks and join the %s.)" % [fee, g["label"]], line, "cheer")
	Game.toast.emit("Joined the %s" % g["label"])
	manager.gates.deed_for(npc, "guild")
	if is_instance_valid(_join_btn):
		_join_btn.queue_free()

## The land seller's houses: each with where it is and what it costs.
func _show_houses() -> void:
	if npc == null or npc.rec.get("shop_kind", "") != "land":
		return
	var site := manager.site_of(npc)
	if site.is_empty():
		return
	var houses := TownShops.for_sale(manager.gen, site, Game.estates)
	var v := _drawer("Houses for sale in %s   ·   you have %d Marks" % [npc.settlement["name"], Game.money])
	if houses.is_empty():
		v.add_child(UITheme.label("Nothing is for sale here just now.", 15, UITheme.DIM))
		return
	var note := UITheme.label("A house of your own is where you wake if you fall, and has a sign over the door with your name.", 13, UITheme.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for h in houses:
		var cost := TownShops.price(h, npc.rec)
		var row := HBoxContainer.new()
		var l := UITheme.label(TownShops.where(h, site["center"]), 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var hh: Dictionary = h
		var b := UITheme.button("Buy for %d" % cost, func(): _buy_house(hh, cost))
		b.disabled = Game.money < cost
		row.add_child(b)
		list.add_child(row)

func _buy_house(h: Dictionary, cost: int) -> void:
	if npc == null or Game.money < cost:
		return
	var site := manager.site_of(npc)
	Game.add_money(-cost)
	npc.rec["purse"] = int(npc.rec["purse"]) + cost
	Game.buy_house(TownShops.estate(h, npc.settlement["name"], Game.planet))
	manager.houses_changed(site)
	NPCMind.change_rel(npc.rec, 10)
	NPCMind.remember(npc.rec, "Sold the traveller a %s in town." % String(h["t"]).replace("_", " "))
	_close_extra()
	_reaction("(You pay %d Marks for the deed.)" % cost, "It's yours. Your name goes over the door today. Welcome home.", "bow")
	Game.toast.emit("You own a house in %s" % npc.settlement["name"])
	manager.gates.deed_for(npc, "house")

# --- At a town's gate ---------------------------------------------------------------------------

## A guard of a walled town: what it takes to be let in, and each way you might try.
func _show_gate() -> void:
	var o := manager.gates.options(npc)
	if o.is_empty():
		return
	var v := _drawer("The gate of %s   ·   you have %d Marks" % [o["town"], Game.money])
	var ad: Dictionary = o["admit"]
	var head := UITheme.label("%s town. Your standing: %s (%d). Waved through from %d." % [o["temper"], o["tier"], o["score"], o["need"]], 15)
	head.add_theme_color_override("font_color", Standing.tier_color(o["tier"]))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var ps: Dictionary = o["pass"]
	var note := ""
	match String(ad["why"]):
		"citizen": note = "You own a house here: you come and go as you please."
		"pass": note = "Your pass is good for %.1f more days." % (float(ps["until"]) - Game.day)
		"standing": note = "They know you here. Walk on through."
		"wanted": note = "You're wanted here. Pay your bounty before they'll let you in."
		"outcast": note = "They won't sell an Outcast a pass. A bribe, or another way in."
		"night": note = "The gates are shut for the night. Strangers pay double."
		_: note = "A stranger here pays the toll, or needs someone in town to speak for them."
	if bool(o["inside"]) and not ad["ok"]:
		note += " You're already inside without leave: paying now costs a %d Mark fine on top." % o["late"]
	var nl := UITheme.label(note, 14, UITheme.DIM)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nl)
	if ad["ok"]:
		return
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	var row := func(text: String, btn: String, cb: Callable, ok: bool) -> void:
		var h := HBoxContainer.new()
		var l := UITheme.label(text, 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(l)
		var b := UITheme.button(btn, cb)
		b.disabled = not ok
		h.add_child(b)
		list.add_child(h)
	if String(ad["why"]) == "wanted":
		return
	var cost: int = int(o["toll"]) + int(o["late"])
	if o["sells"]:
		row.call("Pay the toll: a pass for %.1f days." % o["days"], "Pay %d" % cost, _gate_toll, Game.money >= cost)
	var br: Dictionary = o["bribe"]
	row.call("Slip the guard something to look the other way (%d%% they take it; if not, it's a crime)." % int(round(float(br["odds"]) * 100.0)),
		"Bribe %d" % br["price"], _gate_bribe, Game.money >= int(br["price"]))
	for rec in o["vouchers"]:
		var who: Dictionary = rec
		row.call("%s, the %s, thinks well of you and would vouch for you." % [who["name"], String(who["job"])], "Name them", func(): _gate_vouch(who), true)
	if (o["vouchers"] as Array).is_empty():
		var hint := UITheme.label("Nobody in town would vouch for you yet. Townsfolk who like you (gifts, help, a kind word) will.", 13, UITheme.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(hint)

func _gate_toll() -> void:
	var o := manager.gates.options(npc)
	var cost: int = int(o.get("toll", 0)) + int(o.get("late", 0))
	if not manager.gates.pay_toll(npc):
		return
	_close_extra()
	_reaction("(You pay %d Marks at the gate.)" % cost, ["Pass is good for a few days. Mind the law in here.", "Welcome to %s. Keep out of trouble." % o["town"], "On you go."][randi() % 3], "nod")
	_history.append({"role": "user", "content": "(The traveller pays the toll to enter town.)"})

func _gate_bribe() -> void:
	var o := manager.gates.options(npc)
	var price: int = int(o.get("bribe", {}).get("price", 0))
	_close_extra()
	if manager.gates.try_bribe(npc):
		_reaction("(You press %d Marks into the guard's hand.)" % price, ["I didn't see you. Go on, quick.", "Never met you. Move along.", "Pleasure doing business."][randi() % 3], "wink")
		_history.append({"role": "user", "content": "(The traveller bribes you to let them into town, and you take it.)"})
	else:
		_reaction("(The guard won't take it.)", ["You think the watch can be bought? That's a fine.", "Put that away before I put you in irons.", "A bribe? You'll pay for that."][randi() % 3], "fist")
		_history.append({"role": "user", "content": "(The traveller tried to bribe you. You refused and reported it.)"})

func _gate_vouch(by: Dictionary) -> void:
	if not manager.gates.vouch(npc, by):
		return
	_close_extra()
	_reaction("(You name %s.)" % by["name"], "%s speaks for you? Then you're welcome. Don't make them regret it." % String(by["name"]).split(" ")[0], "nod")
	_history.append({"role": "user", "content": "(%s vouches for the traveller at the gate.)" % by["name"]})

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
		Voice.speak(npc.rec, line, 0.0, true, npc)
		_history.append({"role": "assistant", "content": JSON.stringify({"say": line})})
	npc.act(doing)
	_panel_header_refresh()
	manager.mark_dirty(npc.settlement)

func _panel_header_refresh() -> void:
	if _body and _body.get_child_count() > 0:
		var head := _body.get_child(0)
		var tv := head.get_child(0)
		if tv.get_child_count() > 1:
			(tv.get_child(1) as Label).text = "%s    %s" % [_who(), _relation_text()]

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

## Says the instant answer for `text` ("Yes.", "Hmm, let me think...") with a fitting
## gesture, and returns it ("" when they just wait for the model).
func _quick_reply(n: NPC, text: String) -> String:
	var kind: String = await AI.interject(n.rec, text)
	if npc != n:
		return ""
	var line := Interject.line(n.rec, kind)
	if line == "":
		return ""
	_add_line(n.rec["name"].split(" ")[0], line, UITheme.ACCENT)
	n.say(line, 2.5)
	Voice.speak(n.rec, line, 0.0, true, n)
	n.act(Interject.GESTURE.get(kind, ""))
	return line

## A voice problem: in the status line and in the conversation, where it can't be missed.
func _problem(text: String) -> void:
	_status.text = text
	_log.append_text("[color=#ff9a80][i]%s[/i][/color]\n" % text.replace("[", "("))

func _mic_start() -> void:
	if npc == null or _busy or _mic.recording:
		return
	if not AI.stt_enabled() and OS.get_name() != "Windows":
		_problem("Speech recognition isn't installed. Reinstall with \"Talk with your voice\" ticked, or set a speech-to-text server in Settings > AI.")
		return
	if not _mic.start():
		_problem("No microphone input available (check your OS microphone permission).")
		return
	Voice.hush() # don't talk over you
	npc.act("tilt")
	_status.text = "Listening... release %s to send." % _voice_key()
	if _mic_btn:
		_mic_btn.text = "Listening |"

func _mic_stop() -> void:
	if _mic_btn:
		_mic_btn.text = "Hold to speak"
	if not _mic.recording:
		return
	var wav := _mic.stop()
	if wav.is_empty():
		_status.text = "Too short. Hold %s while you speak." % _voice_key()
		return
	if _mic.last_peak < 0.004:
		_problem("Your microphone sent only silence. Check that apps may use the microphone (Windows: Settings > Privacy & security > Microphone) and that your mic is the default input device (now: %s)." % Microphone.device())
		return
	_status.text = "Understanding what you said..."
	var r: Dictionary = await AI.transcribe(wav)
	if npc == null:
		return
	if not r["ok"] or String(r["text"]).strip_edges() == "":
		var why := "Couldn't make that out (%s)." % (r["error"] if r["error"] != "" else "silence")
		if r.get("via", "") == "windows" and not AI.stt_enabled():
			why += " For better recognition, reinstall with \"Talk with your voice\" ticked."
		_problem(why)
		return
	_status.text = _mode_text()
	_send(r["text"])

# --- Open mic and hands-free conversations ------------------------------------------------------

## Keeps the microphone in step with the open mic setting (the key and Settings both
## change it), and shows a small tag on screen while it is on.
func _sync_open_mic() -> void:
	var want := bool(AI.get_value("open_mic")) and DisplayServer.get_name() != "headless"
	if want != _mic.listening:
		if want and not _mic.listen(true):
			AI.set_value("open_mic", false)
			Game.toast.emit("Open mic: no microphone input (check your OS microphone permission)")
			want = false
		elif not want:
			_mic.listen(false)
	if want and _mic_tag == null and get_parent() != null:
		_mic_tag = UITheme.label("", 14, UITheme.DIM)
		_mic_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mic_tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_mic_tag.offset_left = -220
		_mic_tag.offset_right = -16
		_mic_tag.offset_top = 64
		_mic_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		get_parent().add_child(_mic_tag)
	if _mic_tag:
		_mic_tag.visible = want
		if want:
			var lv := _mic.level()
			_mic_tag.text = "Mic open (%s)  %s" % [_open_mic_key(), "|".repeat(1 + int(lv * 6.0))] if not _hearing else "Mic open: understanding..."
			_mic_tag.modulate = Color(1, 1, 1, 0.55 + 0.45 * minf(lv * 3.0, 1.0))

func _open_mic_key() -> String:
	var ev := InputMap.action_get_events("open_mic") if InputMap.has_action("open_mic") else []
	return ev[0].as_text().split(" ")[0] if not ev.is_empty() else "O"

## A phrase came in on the open mic.
func _on_heard(wav: PackedByteArray, peak: float) -> void:
	if _hearing or player == null or menus.is_open() or get_tree().paused or _pick_npc != null:
		return
	var windowed := npc != null and not _ambient
	var listeners: Array = []
	if npc == null:
		listeners = _listeners()
		if listeners.is_empty():
			return # nobody near enough to hear: no need to understand it
	elif _busy:
		return
	if windowed and _entry.has_focus():
		return # typing
	_hearing = true
	if windowed:
		_status.text = "Understanding what you said..."
	var r: Dictionary = await AI.transcribe(wav)
	_hearing = false
	var text := String(r.get("text", "")).strip_edges()
	if not r["ok"] or text.length() < 2:
		var why := String(r.get("error", ""))
		if windowed and npc != null:
			_status.text = _mode_text() if why in ["", "silence"] else "Couldn't make that out (%s)." % why
		elif why not in ["", "silence"] and Time.get_ticks_msec() / 1000.0 - _hear_err_t > 30.0:
			_hear_err_t = Time.get_ticks_msec() / 1000.0
			Game.toast.emit("Open mic: %s" % why)
		return
	if npc != null:
		if is_instance_valid(npc) and not _busy:
			if not windowed:
				Game.toast.emit("You: \"%s\"" % text)
			_send(text)
		return
	Game.toast.emit("You: \"%s\"" % text)
	var who: NPC = await _answerer(text, listeners)
	if who == null or npc != null or not is_instance_valid(who):
		return
	_open_ambient(who)
	_send(text, "(The traveller called this out to anyone nearby; you heard it and chose to answer.) ")

## The people near enough to hear you, nearest first (the one you face first of all).
func _listeners() -> Array:
	var pp := player.global_position
	var near: Array = []
	for n in manager.all_nodes():
		if not is_instance_valid(n) or not (n is NPC):
			continue
		var d: float = (n as NPC).global_position.distance_to(pp)
		if d <= HEAR_RADIUS and not n.talking and not String(n.action) in ["flee", "attack", "confront"]:
			near.append([d, n])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = near.slice(0, 5).map(func(e): return e[1])
	var looked := _looked_at()
	if looked != null and out.has(looked):
		out.erase(looked)
		out.push_front(looked)
	return out

func _looked_at() -> NPC:
	var f: Dictionary = player.focus if "focus" in player else {}
	return f["npc"] if f.get("kind", "") == "npc" and is_instance_valid(f.get("npc")) else null

## Who answers what you called out: the person you face, whatever they think of it;
## otherwise the nearest one who would say yes (or has an answer), and nobody when
## nobody would. Talk that isn't meant for anyone gets no answer at all.
func _answerer(text: String, listeners: Array) -> NPC:
	var looked := _looked_at()
	if looked != null and listeners.has(looked) and looked.global_position.distance_to(player.global_position) < 8.0:
		return looked
	if not Interject.calls_out(text):
		return null
	for n in listeners:
		if not is_instance_valid(n) or n.talking:
			continue
		var kind: String = await AI.interject(n.rec, text)
		if kind in WILLING:
			return n
	return null

## Starts talking with `n` without the window: they turn to you, come over and answer.
func _open_ambient(n: NPC) -> void:
	npc = n
	_ambient = true
	_amb_t = 0.0
	_amb_met = false
	_history.clear()
	_mic_btn = null
	# The conversation's log, status and options are kept off screen.
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_status = Label.new()
	_entry = LineEdit.new()
	_opts = HBoxContainer.new()
	if n.global_position.distance_to(player.global_position) > 3.5:
		manager.instruct(n, "greet", 10.0) # walk over
	else:
		_meet()

func _meet() -> void:
	if _amb_met or npc == null:
		return
	_amb_met = true
	manager.instruct(npc, "stop_following", 0.0)
	manager.begin_talk(npc)

func _ambient_tick(dt: float) -> void:
	if not is_instance_valid(npc):
		_end_ambient()
		return
	var d := npc.global_position.distance_to(player.global_position)
	if not _amb_met and (d < 3.5 or _amb_t > 10.0):
		_meet()
	if not _busy and not _hearing and not _mic.recording:
		_amb_t += dt
	if _amb_t > AMBIENT_SECONDS or d > HEAR_RADIUS + 6.0:
		_end_ambient()

func _end_ambient() -> void:
	var n := npc
	_ambient = false
	npc = null
	_busy = false
	if is_instance_valid(n):
		if _history.size() > 1 and not AI.dialogue_enabled():
			NPCMind.remember(n.rec, "Chatted with the traveller.")
		if _amb_met:
			manager.end_talk(n)
		else:
			manager.instruct(n, "stop_following", 0.0)
	for c in [_log, _status, _entry, _opts]:
		if is_instance_valid(c) and not c.is_inside_tree():
			c.queue_free()
	_log = null
	_status = null
	_entry = null
	_opts = null

## Shows what was said so far (when a hands-free conversation moves into the window).
func _replay() -> void:
	var first: String = npc.rec["name"].split(" ")[0]
	for h in _history.slice(-8):
		var c := String(h["content"])
		if h["role"] == "user":
			c = c.substr(c.find(") ") + 2) if c.begins_with("(") and c.contains(") ") else c
			if c != "" and not c.begins_with("("):
				_add_line("You", c, UITheme.ACCENT_2)
		else:
			var d = JSON.parse_string(c)
			if d is Dictionary and String(d.get("say", "")) != "":
				_add_line(first, String(d["say"]), UITheme.ACCENT)
