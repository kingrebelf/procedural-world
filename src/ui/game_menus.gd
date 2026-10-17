class_name GameMenus
extends Control
## Inventory, crafting, trading, map and pause screens. Owns mouse capture and pausing.

var player: Player
var streamer: ChunkStreamer
var _panel: Control
var _mode := ""
var _swap_from := -1
var _trader: Dictionary
var _trader_chunk: ChunkNode
var _store_obj: Dictionary ## the storage chest that is open
var _store_chunk: ChunkNode
var _store: Inventory
var _corpses: Corpses ## the body that is open (mode "corpse")
var _corpse_key := ""
var _backdrop: TextureRect ## darkens the world behind an open menu
var _animate := false ## the next panel built fades and scales in

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("trade_ui")
	Game.inventory.changed.connect(_refresh)
	Game.money_changed.connect(func(_m): _refresh())
	Game.stats_changed.connect(func(): if _mode == "character": _refresh())
	Game.equipment_changed.connect(func(): if _mode == "inventory" or _mode == "character": _refresh())
	Net.alliance_changed.connect(func(): if _mode == "players": _refresh())
	Net.players_changed.connect(func(): if _mode == "players": _refresh())
	_backdrop = TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.72)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.1, 1.1)
	gt.width = 128
	gt.height = 128
	_backdrop.texture = gt
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	add_child(_backdrop)

func is_open() -> bool:
	return _mode != ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _mode == "":
			open("pause")
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _mode != "" and event is InputEventJoypadButton:
		if _mode == "settings":
			open("pause")
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_toggle("inventory")
	elif event.is_action_pressed("craft") and not (_mode == "" and event.is_action_pressed("reload") and player and player.gunplay.wants_reload()):
		# R is both Crafting and Reload: with a gun in hand that can be reloaded, it reloads.
		_toggle("craft")
	elif event.is_action_pressed("map"):
		_toggle("map")
	elif event.is_action_pressed("character"):
		_toggle("character")
	elif event.is_action_pressed("mouse_toggle") and not event.is_echo():
		# Free the pointer to click on things, or lock it to steer again. In a menu the
		# pointer is free anyway; the choice applies once the menu closes.
		Cursor.free = not Cursor.free
		if _mode == "":
			Cursor.restore()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _mode == "" and not Cursor.free and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle(m: String) -> void:
	if _mode == m:
		close()
	elif _mode == "" or _mode != "pause":
		open(m)
	get_viewport().set_input_as_handled()

func open(m: String) -> void:
	_animate = _mode == ""
	if _mode == "":
		Audio.ui("ui/open")
	_mode = m
	_swap_from = -1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.ui_open = true
	get_tree().paused = m == "pause" or m == "settings"
	if m == "pause" or m == "settings":
		Game.save_all()
	_refresh()

func close() -> void:
	if _mode != "":
		Audio.ui("ui/close")
	_mode = ""
	if _panel:
		_panel.queue_free()
		_panel = null
	_backdrop.visible = false
	Cursor.restore()
	if player:
		player.ui_open = false
	get_tree().paused = false

func open_trader(st: Dictionary, chunk: ChunkNode) -> void:
	_trader = st
	_trader_chunk = chunk
	open("trade")

func open_storage(o: Dictionary, chunk: ChunkNode) -> void:
	_store_obj = o
	_store_chunk = chunk
	_store = Storage.open(o)
	open("storage")

## A carcass or a person's body: take what is on it.
func open_corpse(corpses: Corpses, key: String) -> void:
	var c := corpses.record(key)
	if c.is_empty():
		return
	if DeathBag.is_bag(c) and not DeathBag.can_take(c, Game.my_id()):
		Game.toast.emit("You can't open that bag")
		return
	_corpses = corpses
	_corpse_key = key
	_store = Inventory.new(Corpses.slots_of(c))
	if c.get("items") is Dictionary:
		_store.from_data(c["items"])
	open("corpse")

## An ancient portal: pick a world to step through to.
func open_portal(o: Dictionary, chunk: ChunkNode) -> void:
	_store_obj = o
	_portal_at = Vector2(chunk.position.x + o["p"].x, chunk.position.z + o["p"].z)
	open("portal")

var _portal_at := Vector2.ZERO

## Writes the open chest back into its chunk, to be saved.
func open_travel(o: Dictionary, chunk: ChunkNode) -> void:
	_store_obj = o
	_store_chunk = chunk
	open("travel")

func _store_changed() -> void:
	if _mode == "corpse":
		_corpse_changed()
		return
	Storage.save(_store_obj, _store)
	if _store_chunk and is_instance_valid(_store_chunk):
		Game.mark_chunk_dirty(_store_chunk.data)
	_refresh()

func _refresh() -> void:
	if _mode == "":
		return
	if _panel:
		_panel.queue_free()
	match _mode:
		"pause": _panel = _pause_panel()
		"settings": _panel = _settings_panel()
		"inventory": _panel = _inventory_panel()
		"craft": _panel = _craft_panel()
		"trade": _panel = _trade_panel()
		"storage": _panel = _storage_panel()
		"corpse": _panel = _corpse_panel()
		"travel": _panel = _travel_panel()
		"portal": _panel = _portal_panel()
		"map": _panel = _map_panel()
		"character": _panel = _character_panel()
		"players": _panel = _players_panel()
	_backdrop.visible = true
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.reset_size()
	_panel.position = ((get_viewport_rect().size - _panel.get_combined_minimum_size()) * 0.5).round()
	if _animate:
		_animate = false
		_panel.pivot_offset = _panel.get_combined_minimum_size() * 0.5
		_panel.modulate.a = 0.0
		_panel.scale = Vector2(0.96, 0.96)
		var tw := _panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.14)
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.18)
	if Game.using_pad:
		UITheme.focus_first.call_deferred(_panel)

## The main screens share one tab strip so you can hop between them.
const TABS := [["inventory", "Inventory"], ["craft", "Crafting"], ["character", "Character"], ["map", "Atlas"]]

func _shell(title: String, subtitle: String = "") -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UITheme.title(title, 32))
	if subtitle != "":
		tv.add_child(UITheme.label(subtitle, 15, UITheme.DIM))
	h.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var mt := UITheme.money_tag(Game.money, 22)
	mt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mt)
	h.add_child(_close_button())
	v.add_child(h)
	if TABS.any(func(t): return t[0] == _mode):
		v.add_child(_tab_strip())
	v.add_child(UITheme.divider())
	return [p, v]

func _tab_strip() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for t in TABS:
		var m: String = t[0]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE if not Game.using_pad else Control.FOCUS_ALL
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 22 # clear of the painted frame's gem ends
		inner.offset_right = -22
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := UITheme.label(t[1], 17, UITheme.ACCENT if m == _mode else UITheme.DIM)
		if UITheme.font("bold"):
			l.add_theme_font_override("font", UITheme.font("bold"))
		inner.add_child(l)
		if not Game.using_pad:
			var kc := UITheme.keycap(Bindings.key_name(m, false), 12)
			kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			inner.add_child(kc)
		b.add_child(inner)
		b.custom_minimum_size = Vector2(176, 40)
		b.add_theme_stylebox_override("normal", UITheme.tex_sb("tab_on" if m == _mode else "tab"))
		b.add_theme_stylebox_override("hover", UITheme.tex_sb("tab_on" if m == _mode else "hover"))
		b.add_theme_stylebox_override("pressed", UITheme.tex_sb("tab_on"))
		b.pressed.connect(func(): if m != _mode: open(m))
		row.add_child(b)
	return row

## Small buttons keep the plain bevelled frame: the painted kit's pointed ends need room.
static func _small_button(b: Button) -> void:
	for st in [["normal", "button"], ["hover", "hover"], ["pressed", "pressed"], ["hover_pressed", "pressed"], ["disabled", "disabled"]]:
		b.add_theme_stylebox_override(st[0], UITheme.tex_sb(st[1], 10, 6, true))

## A square button with a drawn X.
func _close_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Close  [%s]" % Bindings.key_name("pause", Game.using_pad)
	_small_button(b)
	b.pressed.connect(close)
	b.draw.connect(func():
		var c := b.size * 0.5
		var col := UITheme.ACCENT if b.is_hovered() else UITheme.TEXT
		b.draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), col, 2.5, true)
		b.draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), col, 2.5, true))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	return b

# --- Character -------------------------------------------------------------------

func _character_panel() -> Control:
	var st := Game.stats
	var nxt := Stats.xp_to_next(st.level)
	var s := _shell("Character", "Level %d  ·  %d / %d XP to the next level" % [st.level, st.xp, nxt] if st.level < Stats.MAX_LEVEL else "Level %d (max)" % st.level)
	var v: VBoxContainer = s[1]
	s[0].custom_minimum_size = Vector2(720, 0)
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(0, 10)
	xp.show_percentage = false
	xp.max_value = nxt
	xp.value = st.xp
	xp.add_theme_stylebox_override("fill", UITheme.sb(Color(0.92, 0.72, 0.28), Color(0, 0, 0, 0), 4, 0, 0))
	v.add_child(xp)
	v.add_child(UITheme.label("Points to spend: %d" % st.points if st.points > 0 else "No points to spend. Gather, craft, build, hunt and explore to level up.",
		18, UITheme.ACCENT if st.points > 0 else UITheme.DIM))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 10)
	for a in Stats.ATTRS:
		var attr: String = a
		g.add_child(UITheme.label(Stats.NAMES[attr], 20))
		var val := UITheme.label(str(st.attrs[attr]), 22, UITheme.ACCENT)
		val.custom_minimum_size = Vector2(40, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_child(val)
		var b := UITheme.button("+", func(): Game.spend_point(attr))
		_small_button(b)
		b.disabled = st.points <= 0
		b.custom_minimum_size = Vector2(44, 0)
		g.add_child(b)
		g.add_child(UITheme.label(Stats.BLURBS[attr], 15, UITheme.DIM))
	v.add_child(g)
	# Thieves' skills: the same points buy levels, and practice raises them too.
	v.add_child(UITheme.heading("Skills"))
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 18)
	sg.add_theme_constant_override("v_separation", 10)
	for k in Stats.SKILLS:
		var sk: String = k
		var lv: int = st.skills[sk]
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", 2)
		nm.add_child(UITheme.label(Stats.SKILL_NAMES[sk], 20))
		var pr := ProgressBar.new()
		pr.custom_minimum_size = Vector2(130, 5)
		pr.show_percentage = false
		pr.max_value = Stats.practice_to_next(lv)
		pr.value = float(st.skill_xp[sk]) if lv < Stats.SKILL_MAX else pr.max_value
		pr.add_theme_stylebox_override("fill", UITheme.sb(Color(0.55, 0.75, 0.95), Color(0, 0, 0, 0), 2, 0, 0))
		pr.tooltip_text = "Practice: %d / %d" % [int(st.skill_xp[sk]), int(pr.max_value)]
		nm.add_child(pr)
		sg.add_child(nm)
		var val := UITheme.label("%d" % lv, 22, UITheme.ACCENT)
		val.custom_minimum_size = Vector2(40, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sg.add_child(val)
		var b := UITheme.button("+", func(): Game.spend_skill_point(sk))
		_small_button(b)
		b.disabled = st.points <= 0 or lv >= Stats.SKILL_MAX
		b.custom_minimum_size = Vector2(44, 0)
		sg.add_child(b)
		var blurb := String(Stats.SKILL_BLURBS[sk]).replace("[crouch]", "[%s]" % Bindings.key_name("crouch", Game.using_pad)).replace("[interact]", "[%s]" % Bindings.key_name("interact", Game.using_pad))
		sg.add_child(UITheme.label(blurb, 15, UITheme.DIM))
	v.add_child(sg)
	var w := Game.crime.worst(Game.day)
	if not w.is_empty():
		v.add_child(UITheme.label("Wanted in %s (%d of %d stars)  ·  %d Marks bounty. Pay a guard there, or lie low and it cools off." % [w["name"], w["stars"], Crime.MAX_STARS, w["b"]], 16, Color(0.95, 0.45, 0.38)))
	v.add_child(HSeparator.new())
	var d := GridContainer.new()
	d.columns = 4
	d.add_theme_constant_override("h_separation", 24)
	for row in [["Health", "%d" % int(st.max_health())], ["Stamina", "%d" % int(st.max_stamina())],
			["Damage and harvesting", "x%.2f" % st.damage_mult()], ["Move speed", "x%.2f" % st.speed_mult()],
			["Swing speed", "x%.2f" % st.swing_mult()], ["Carry weight", "%.1f / %d kg" % [Game.inventory.weight(), int(st.carry_capacity())]],
			["Breath", "%d s" % int(st.max_breath())], ["Experience gain", "x%.2f" % st.xp_mult()],
			["Crafted quality", "x%.2f" % st.craft_quality_mult()],
			["Noticed while sneaking", "x%.2f" % st.notice_mult(true)],
			["Armour", "%d  (takes %d%% of damage)" % [int(Game.armor()), int(round(10000.0 / (100.0 + Game.armor())))]]]:
		d.add_child(UITheme.label(row[0], 16, UITheme.DIM))
		d.add_child(UITheme.label(row[1], 16))
	v.add_child(d)
	v.add_child(HSeparator.new())
	# Worn armour: the same slots as the body in the Inventory; click one to take it off.
	v.add_child(UITheme.heading("Worn armour"))
	v.add_child(UITheme.label("Drag armour onto your body in the Inventory [%s], or right-click it there. Click a piece here to take it off." % Bindings.key_name("inventory", Game.using_pad), 14, UITheme.DIM))
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 8)
	for where in Game.ARMOR_SLOTS:
		eq.add_child(EquipSlot.new(where))
	v.add_child(eq)
	return s[0]

# --- Pause -----------------------------------------------------------------------

func _pause_panel() -> Control:
	var s := _shell("Paused", Game.store.meta.get("name", "") if Game.store else "")
	var v: VBoxContainer = s[1]
	s[0].custom_minimum_size = Vector2(480, 0)
	v.add_child(UITheme.big_button("Resume", close))
	v.add_child(UITheme.big_button("Character", func(): open("character")))
	v.add_child(UITheme.big_button("Atlas", func(): open("map")))
	if Net.is_client():
		v.add_child(UITheme.big_button("Players and alliance", func():
			get_tree().paused = false
			open("players")))
	v.add_child(UITheme.big_button("Settings", func(): open("settings")))
	v.add_child(UITheme.big_button("Leave the server" if Net.is_client() else "Save and quit to menu", func():
		get_tree().paused = false
		Game.close_world()
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")))
	v.add_child(UITheme.big_button("Save and exit to desktop", func():
		Game.close_world()
		get_tree().quit()))
	var meta := Game.store.meta if Game.store else {}
	var pt := int(meta.get("play_time", 0.0))
	v.add_child(UITheme.label("Seed %d    Played %dh %02dm    %d places discovered" % [Game.seed, pt / 3600, (pt / 60) % 60, Game.discovery["visited"].size()], 14, UITheme.DIM))
	if Net.is_client():
		v.add_child(UITheme.label("On %s with %d other%s. Your character is saved on the server." % [Net.info.get("name", "a server"), Net.peers.size(), "" if Net.peers.size() == 1 else "s"], 14, UITheme.DIM))
	else:
		v.add_child(UITheme.label("Everything you see is saved the moment it first exists.", 14, UITheme.DIM))
	return s[0]

## Online: who is here, your alliance and invitations to others.
const ALLY := Color(0.5, 0.86, 0.54)

func _players_panel() -> Control:
	var s := _shell("Players", "On %s" % Net.info.get("name", "the server"))
	var v: VBoxContainer = s[1]
	s[0].custom_minimum_size = Vector2(640, 0)
	var on := bool(Net.option("alliances"))
	var al := Net.alliance
	var lead: bool = al.get("leader", "") == Net.my_pid
	if not on:
		v.add_child(UITheme.label("Alliances are turned off on this server.", 15, UITheme.DIM))
	elif al.is_empty():
		v.add_child(UITheme.heading("Alliance"))
		v.add_child(UITheme.label("Allies can't hurt each other, open each other's locked doors and see each other on the map.", 15, UITheme.DIM))
		var h := HBoxContainer.new()
		var nm := LineEdit.new()
		nm.max_length = 24
		nm.placeholder_text = "Name your alliance"
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(UITheme.button("Found it", func(): Net.ally("create", nm.text)))
		nm.text_submitted.connect(func(t): Net.ally("create", t))
		v.add_child(h)
		for inv in Net.ally_invites:
			var r := HBoxContainer.new()
			var l := UITheme.label("%s invites you to %s" % [inv["from"], inv["name"]], 16, ALLY)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			var id: String = inv["id"]
			r.add_child(UITheme.button("Join", func(): Net.ally("accept", id)))
			r.add_child(UITheme.button("Decline", func(): Net.ally("decline", id)))
			v.add_child(r)
	else:
		v.add_child(UITheme.heading("Alliance: %s" % al["name"]))
		var here := {}
		for p in Net.peers.values():
			here[p["pid"]] = true
		for pid in al["members"]:
			var r := HBoxContainer.new()
			var me: bool = pid == Net.my_pid
			var tag := "  (leader)" if pid == al["leader"] else ""
			var l := UITheme.label(String(al["members"][pid]) + (" (you)" if me else "") + tag, 16, ALLY if me or here.has(pid) else UITheme.DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			if not me:
				r.add_child(UITheme.label("online" if here.has(pid) else "away", 13, UITheme.DIM))
				if lead:
					var who: String = pid
					r.add_child(UITheme.button("Make leader", func(): Net.ally("lead", who)))
					r.add_child(UITheme.button("Remove", func(): Net.ally("kick", who)))
			v.add_child(r)
		v.add_child(UITheme.label("Type /a and a message in chat (T) to talk to your alliance.", 14, UITheme.DIM))
		v.add_child(UITheme.button("Leave %s" % al["name"], func(): Net.ally("leave")))
	v.add_child(UITheme.divider())
	v.add_child(UITheme.heading("Online now"))
	if Net.peers.is_empty():
		v.add_child(UITheme.label("Nobody else is here right now.", 15, UITheme.DIM))
	for p in Net.peers.values():
		var r := HBoxContainer.new()
		var pid: String = p["pid"]
		var l := UITheme.label(String(p["name"]), 16, ALLY if Net.allied(pid) else UITheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		if int(p["planet"]) == Game.planet and player:
			r.add_child(UITheme.label("%d m" % int(player.global_position.distance_to(p["pos"])), 13, UITheme.DIM))
		if Net.allied(pid):
			r.add_child(UITheme.label("Ally", 13, ALLY))
		elif on and not al.is_empty():
			r.add_child(UITheme.button("Invite", func(): Net.ally("invite", pid)))
		v.add_child(r)
	return s[0]

func _settings_panel() -> Control:
	var m := SettingsMenu.new()
	m.closed.connect(func(): open("pause"))
	return m

# --- Inventory ----------------------------------------------------------------------

const SLOT_PX := 68

## Dresses a slot button: inset frame (in the item's rank colour), centred icon, and the
## stack count in the corner.
static func _style_slot(b: Button, it, px: int) -> void:
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_ALL if Game.using_pad else Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UITheme.rarity_sb(it) if it != null else UITheme.tex_sb("slot"))
	b.add_theme_stylebox_override("hover", UITheme.tex_sb("slot_hover"))
	b.add_theme_stylebox_override("pressed", UITheme.tex_sb("slot_sel"))
	b.add_theme_stylebox_override("disabled", UITheme.tex_sb("slot"))
	b.add_theme_stylebox_override("focus", UITheme.tex_sb("slot_hover"))
	if it == null:
		return
	var ic := UITheme.icon_rect(it["type"], px - 12)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 6
	ic.offset_top = 6
	ic.offset_right = -6
	ic.offset_bottom = -6
	b.add_child(ic)
	if ItemDB.is_stackable(it["type"]):
		var q := UITheme.label("%d" % it["qty"], 14)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		q.add_theme_constant_override("outline_size", 4)
		q.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		q.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		q.offset_left = -px
		q.offset_top = -20
		q.offset_right = -5
		q.offset_bottom = -1
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(q)
	b.tooltip_text = UITheme.describe_item(it)

func _slot_button(i: int) -> Button:
	var it = Game.inventory.get_slot(i)
	var b := Button.new()
	_style_slot(b, it, SLOT_PX)
	if it != null and Game.armor_slot_of(it) != "":
		b.tooltip_text += "\nRight-click or drag onto your body to wear it"
	if i == _swap_from:
		b.add_theme_stylebox_override("normal", UITheme.tex_sb("slot_sel"))
	b.pressed.connect(func():
		if _swap_from < 0:
			if Game.inventory.get_slot(i) != null:
				_swap_from = i
				_refresh()
		else:
			Game.inventory.swap(_swap_from, i)
			_swap_from = -1)
	# Right-click armour to put it on, and food, potions, scrolls and the like to use them.
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var there = Game.inventory.get_slot(i)
			if Game.armor_slot_of(there) != "":
				_swap_from = -1
				Game.equip(i)
			elif there != null and player and ItemDB.def(there["type"]).get("kind", "") in ["food", "scroll", "instrument", "camp"]:
				_swap_from = -1
				player.consume(i)
				_refresh())
	# Drag and drop: drag any item onto another slot (or onto the hotbar row) to move,
	# swap or merge it, or armour onto your body to wear it.
	b.set_drag_forwarding(func(_at):
		if Game.inventory.get_slot(i) == null:
			return null
		b.set_drag_preview(_drag_preview(Game.inventory.get_slot(i)["type"]))
		return {"inv_slot": i},
		func(_at, d): return d is Dictionary and (d.has("inv_slot") or d.has("equip")),
		func(_at, d):
			_swap_from = -1
			if d.has("equip"):
				Game.unequip_to(d["equip"], i)
			elif d["inv_slot"] != i:
				Game.inventory.swap(d["inv_slot"], i))
	return b

static func _drag_preview(type: String) -> Control:
	var prev := UITheme.icon_rect(type, 60)
	prev.size = Vector2(60, 60)
	prev.position = Vector2(-30, -30)
	var holder := Control.new()
	holder.add_child(prev)
	return holder

func _inventory_panel() -> Control:
	var s := _shell("Inventory", "Drag items between slots. Drag armour onto your body to wear it. Hover for details.")
	var v: VBoxContainer = s[1]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)
	# Left: the body you dress.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.add_child(UITheme.heading("Equipment"))
	var doll := Mannequin.new()
	left.add_child(doll)
	var arm := HBoxContainer.new()
	arm.add_child(UITheme.label("Armour", 16, UITheme.DIM))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arm.add_child(gap)
	arm.add_child(UITheme.label("%d" % int(Game.armor()), 18, UITheme.ACCENT))
	arm.tooltip_text = "You take %d%% of incoming damage" % int(round(10000.0 / (100.0 + Game.armor())))
	left.add_child(arm)
	var kg := Game.inventory.weight()
	var cap := Game.stats.carry_capacity()
	var wrow := HBoxContainer.new()
	wrow.add_child(UITheme.label("Weight", 16, UITheme.DIM))
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(gap2)
	wrow.add_child(UITheme.label("%.0f / %d kg" % [kg, int(cap)], 16, UITheme.BAD if kg > cap else UITheme.TEXT))
	left.add_child(wrow)
	var wb := ProgressBar.new()
	wb.show_percentage = false
	wb.custom_minimum_size = Vector2(0, 8)
	wb.max_value = cap
	wb.value = minf(kg, cap)
	wb.add_theme_stylebox_override("fill", UITheme.bar_fill(UITheme.BAD if kg > cap else Color(0.75, 0.62, 0.35)))
	left.add_child(wb)
	cols.add_child(left)
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override("separator", UITheme.sb(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 0, 0))
	cols.add_child(sep)
	# Right: the pack and the hotbar.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.add_child(UITheme.heading("Pack  ·  %d / %d slots" % [Inventory.SIZE - Inventory.HOTBAR - _free_in_pack(), Inventory.SIZE - Inventory.HOTBAR]))
	var g := GridContainer.new()
	g.columns = Inventory.HOTBAR
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		g.add_child(_slot_button(i))
	right.add_child(g)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	right.add_child(sp)
	right.add_child(UITheme.heading("Hotbar  ·  keys 1 to 0, or hold LB on a controller"))
	var hb := GridContainer.new()
	hb.columns = Inventory.HOTBAR
	hb.add_theme_constant_override("h_separation", 6)
	for i in Inventory.HOTBAR:
		hb.add_child(_slot_button(i))
	right.add_child(hb)
	cols.add_child(right)
	v.add_child(_hint_row([["Drag", "move or wear"], ["Right-click", "wear / take off"], ["Click, click", "swap two slots"]]))
	return s[0]

func _free_in_pack() -> int:
	var n := 0
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		if Game.inventory.get_slot(i) == null:
			n += 1
	return n

## A row of "[key] what it does" hints along the bottom of a panel.
static func _hint_row(pairs: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_END
	for pr in pairs:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var kc := UITheme.keycap(pr[0], 12)
		kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kc)
		h.add_child(UITheme.label(pr[1], 14, UITheme.DIM))
		row.add_child(h)
	return row

# --- Crafting ------------------------------------------------------------------------

const CRAFT_AMOUNTS := [1, 5, 10, 100]
var _craft_scroll := 0
var _craft_tab := "All"
var _craft_find := ""
var _craft_ready_only := false

## True when the recipe is in the open tab and passes the search and "Can craft now".
func _craft_shows(r: Dictionary, stations: Dictionary) -> bool:
	if _craft_tab != "All" and not ItemDB.craft_tabs(r["out"]).has(_craft_tab):
		return false
	if _craft_ready_only and not _craft_ready(r, stations):
		return false
	var q := _craft_find.strip_edges().to_lower()
	if q == "":
		return true
	if String(ItemDB.def(r["out"]).get("name", r["out"])).to_lower().contains(q):
		return true
	return r["in"].keys().any(func(t): return String(ItemDB.def(t).get("name", t)).to_lower().contains(q))

static func _craft_ready(r: Dictionary, stations: Dictionary) -> bool:
	return Recipes.station_ok(r, stations) and Recipes.level_ok(r, Game.stats.level) and Recipes.max_crafts(Game.inventory, r) > 0

static func _icon_rect(type: String, px: int) -> TextureRect:
	var r := UITheme.icon_rect(type, px)
	r.tooltip_text = ItemDB.def(type).get("name", type)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

func _do_craft(r: Dictionary, times: int, stations: Dictionary) -> void:
	if not Recipes.station_ok(r, stations) or not Recipes.level_ok(r, Game.stats.level):
		return
	var pos := player.global_position if player else Vector3.ZERO
	var ck := ChunkStreamer.chunk_of(pos)
	var made := Recipes.craft_many(Game.inventory, r, Game.origin_here("crafted", -1, ck), times, Game.stats.craft_quality_mult())
	if made > 0:
		Game.item_gained.emit(r["out"], made * int(r["qty"]))
		# Experience grows with what the thing is worth, a little less for each in a batch.
		var each := 2.0 + sqrt(float(ItemDB.def(r["out"]).get("value", 1)) * int(r["qty"]))
		Game.add_xp(each * pow(made, 0.8), "Crafting")

func _craft_panel() -> Control:
	var s := _shell("Crafting", "Pick an amount, or Craft all. Some recipes need a station nearby; build them from the Stations tab.")
	var v: VBoxContainer = s[1]
	var here := player.global_position if player else Vector3.ZERO
	var stations := BuildCatalog.stations_near(streamer, here)
	# One tab per kind of thing; tabs with nothing to make in them stay hidden.
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for t in ["All"] + ItemDB.CRAFT_TABS:
		var tab: String = t
		if tab != "All" and not Recipes.LIST.any(func(r): return ItemDB.craft_tabs(r["out"]).has(tab)):
			continue
		var tb := UITheme.button(tab, func():
			_craft_tab = tab
			_craft_scroll = 0
			_refresh())
		tb.toggle_mode = true
		tb.button_pressed = tab == _craft_tab
		tabs.add_child(tb)
	v.add_child(tabs)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	var sc := ScrollContainer.new()
	var list := VBoxContainer.new()
	var find := LineEdit.new()
	find.placeholder_text = "Search recipes or materials"
	find.text = _craft_find
	find.custom_minimum_size = Vector2(300, 0)
	find.clear_button_enabled = true
	# Typing only redraws the list, so the box keeps its focus.
	find.text_changed.connect(func(t):
		_craft_find = t
		_craft_scroll = 0
		sc.scroll_vertical = 0
		_fill_craft_list(list, stations))
	find.text_submitted.connect(func(_t): find.release_focus())
	bar.add_child(find)
	var ready_b := UITheme.button("Can craft now", func():
		_craft_ready_only = not _craft_ready_only
		_craft_scroll = 0
		_refresh())
	ready_b.toggle_mode = true
	ready_b.button_pressed = _craft_ready_only
	bar.add_child(ready_b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var names: Array = []
	for st in stations:
		names.append(Recipes.STATION_NAMES.get(st, st))
	var near := UITheme.label("Nearby: " + (", ".join(names) if not names.is_empty() else "no stations"), 15, UITheme.ACCENT if not names.is_empty() else UITheme.DIM)
	near.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(near)
	v.add_child(bar)
	sc.custom_minimum_size = Vector2(980, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	_fill_craft_list(list, stations)
	sc.get_v_scroll_bar().value_changed.connect(func(val): _craft_scroll = int(val))
	(func(): sc.scroll_vertical = _craft_scroll).call_deferred()
	v.add_child(sc)
	if _craft_find != "" and not Game.using_pad:
		# Back after crafting from a search: keep typing where you left off.
		(func():
			find.grab_focus()
			find.caret_column = find.text.length()).call_deferred()
	return s[0]

func _fill_craft_list(list: VBoxContainer, stations: Dictionary) -> void:
	for c in list.get_children():
		c.queue_free()
	# Recipes you can make first, then the rest in their usual order.
	var order: Array = Recipes.LIST.filter(func(r): return _craft_shows(r, stations))
	var lv := Game.stats.level
	var ready := func(r): return _craft_ready(r, stations)
	# Locked recipes go last, soonest unlocked first.
	order.sort_custom(func(x, y):
		if ready.call(x) != ready.call(y):
			return ready.call(x)
		return Recipes.unlock_level(x["out"]) < Recipes.unlock_level(y["out"]) and not Recipes.level_ok(x, lv))
	if order.is_empty():
		var msg := "Nothing you can craft here right now." if _craft_ready_only else "No recipes match."
		list.add_child(UITheme.label(msg, 16, UITheme.DIM))
	for r in order:
		var at_ok := Recipes.station_ok(r, stations)
		var unlocked := Recipes.level_ok(r, lv)
		var most := Recipes.max_crafts(Game.inventory, r) if at_ok and unlocked else 0
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UITheme.tex_sb("tab" if most > 0 else "disabled", 10, 6))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(_icon_rect(r["out"], 52))
		var name_box := VBoxContainer.new()
		name_box.custom_minimum_size = Vector2(210, 0)
		name_box.add_child(UITheme.label("%s%s" % [ItemDB.def(r["out"])["name"], (" x%d" % r["qty"]) if r["qty"] > 1 else ""], 17, UITheme.TEXT if most > 0 else UITheme.DIM))
		var status := ("Can make %d" % most) if most > 0 else "Missing materials"
		if not unlocked:
			status = "Unlocks at level %d" % Recipes.unlock_level(r["out"])
		elif not at_ok:
			status = "Needs a %s nearby" % Recipes.STATION_NAMES.get(r["at"], r["at"])
		var no_tools := Recipes.missing_tools(Game.inventory, r)
		if unlocked and at_ok and not no_tools.is_empty():
			status = "Needs %s in your pack" % ", ".join(no_tools.map(func(t): return ItemDB.def(t)["name"]))
		name_box.add_child(UITheme.label(status, 13, UITheme.ACCENT if most > 0 else (Color(0.9, 0.55, 0.4) if not at_ok or not unlocked or not no_tools.is_empty() else UITheme.DIM)))
		row.add_child(name_box)
		var ins := HBoxContainer.new()
		ins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ins.add_theme_constant_override("separation", 12)
		for t in r["in"]:
			var have: int = Game.inventory.count(t)
			var need: int = r["in"][t]
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			chip.add_child(_icon_rect(t, 30))
			chip.add_child(UITheme.label("%d/%d" % [have, need], 15, UITheme.TEXT if have >= need else Color(0.9, 0.45, 0.4)))
			chip.tooltip_text = ItemDB.def(t)["name"]
			ins.add_child(chip)
		# Tools the recipe needs but does not use up.
		for t in r.get("tools", []):
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			chip.add_child(_icon_rect(t, 30))
			chip.add_child(UITheme.label("tool", 13, UITheme.DIM if Game.inventory.count(t) > 0 else Color(0.9, 0.45, 0.4)))
			chip.tooltip_text = "%s (not used up)" % ItemDB.def(t)["name"]
			ins.add_child(chip)
		row.add_child(ins)
		for n in CRAFT_AMOUNTS:
			var amount: int = n
			var b := UITheme.button("x%d" % amount, func(): _do_craft(r, amount, stations))
			_small_button(b)
			b.custom_minimum_size = Vector2(54, 0)
			b.disabled = most < amount
			row.add_child(b)
		var all := UITheme.button("All", func(): _do_craft(r, -1, stations))
		_small_button(all)
		all.custom_minimum_size = Vector2(60, 0)
		all.disabled = most <= 0
		row.add_child(all)
		list.add_child(card)

# --- Storage -------------------------------------------------------------------------

func _storage_panel() -> Control:
	var cname := String(BuildCatalog.def(BuildCatalog.id_of(_store_obj["t"])).get("name", "Chest"))
	var kg := Game.inventory.weight()
	var s := _shell(cname, "Click an item to move it across. Your pack: %.0f / %d kg." % [kg, int(Game.stats.carry_capacity())])
	var v: VBoxContainer = s[1]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.add_child(UITheme.label("IN THE %s  (%d / %d slots)" % [cname.to_upper(), _store.capacity - _store.free_slots(), _store.capacity], 15, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	bar.add_child(UITheme.button("Take all", func():
		Storage.transfer_all(_store, Game.inventory)
		_store_changed()))
	bar.add_child(UITheme.button("Store all (not the hotbar)", func():
		Storage.transfer_all(Game.inventory, _store, true)
		_store_changed()))
	v.add_child(bar)
	var g := GridContainer.new()
	g.columns = 10
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in _store.capacity:
		g.add_child(_move_button(_store, i, Game.inventory))
	v.add_child(g)
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label("YOUR PACK", 15, UITheme.ACCENT))
	var pg := GridContainer.new()
	pg.columns = 10
	pg.add_theme_constant_override("h_separation", 6)
	pg.add_theme_constant_override("v_separation", 6)
	for i in Inventory.SIZE:
		pg.add_child(_move_button(Game.inventory, i, _store))
	v.add_child(pg)
	return s[0]

# --- Bodies ----------------------------------------------------------------------------

static func _worth(inv: Inventory) -> int:
	var n := 0
	for i in inv.capacity:
		var it = inv.get_slot(i)
		if it != null:
			n += int(ItemDB.def(it["type"]).get("value", 1)) * int(it["qty"])
	return n

## Writes what is left back onto the body and tells Corpses what was taken (theft, in town).
func _corpse_changed(marks := 0) -> void:
	var c := _corpses.record(_corpse_key) if is_instance_valid(_corpses) else {}
	if c.is_empty():
		close()
		return
	var before := 0
	if c.get("items") is Dictionary:
		var old := Inventory.new(Corpses.slots_of(c))
		old.from_data(c["items"])
		before = _worth(old)
	c["items"] = _store.to_data()
	if DeathBag.is_mine(c, Game.my_id()) and not (c.get("worn", {}) as Dictionary).is_empty():
		# Your own armour goes back on as you take it.
		Game.rewear(c["worn"])
	_corpses.took_from(_corpse_key, maxi(0, before - _worth(_store)) + marks)
	if not CorpseLoot.has_any(c) and c["kind"] == "animal":
		close()
		return
	_refresh()

func _take_purse() -> int:
	var c := _corpses.record(_corpse_key) if is_instance_valid(_corpses) else {}
	var m := int(c.get("purse", 0))
	if m > 0:
		c["purse"] = 0
		Game.give({"type": "_marks", "qty": m})
	return m

func _corpse_panel() -> Control:
	var c := _corpses.record(_corpse_key) if is_instance_valid(_corpses) else {}
	var person: bool = c.get("kind", "") == "person"
	var bag := DeathBag.is_bag(c)
	var title := ("%s (dead)" % c.get("name", "Someone")) if person else "%s carcass" % c.get("name", "Animal")
	if bag:
		title = DeathBag.title(c, Game.my_id())
	var kg := Game.inventory.weight()
	var s := _shell(title, "Click an item to take it. Your pack: %.0f / %d kg." % [kg, int(Game.stats.carry_capacity())])
	var v: VBoxContainer = s[1]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.add_child(UITheme.label("IN THE BAG" if bag else "ON THE BODY" if person else "LEFT ON THE CARCASS", 15, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var purse := int(c.get("purse", 0))
	if purse > 0:
		bar.add_child(UITheme.button("Take purse (%d Marks)" % purse, func():
			_corpse_changed(_take_purse())))
	bar.add_child(UITheme.button("Take all", func():
		var m := _take_purse()
		Storage.transfer_all(_store, Game.inventory)
		_corpse_changed(m)))
	v.add_child(bar)
	var g := GridContainer.new()
	g.columns = 10
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in _store.capacity:
		g.add_child(_move_button(_store, i, Game.inventory))
	v.add_child(g)
	if (person or bag) and _store.free_slots() == _store.capacity and purse <= 0:
		v.add_child(UITheme.label("Nothing left on them.", 15, UITheme.DIM))
	return s[0]

## A slot that sends its whole stack to the other side when clicked.
func _move_button(from: Inventory, i: int, to: Inventory) -> Button:
	var it = from.get_slot(i)
	var b := Button.new()
	_style_slot(b, it, 60)
	if it != null:
		b.tooltip_text = UITheme.describe_item(it) + "\n%.1f kg" % (ItemDB.weight(it["type"]) * it["qty"])
		b.pressed.connect(func():
			if Storage.transfer(from, i, to) == 0:
				Game.toast.emit("No room")
			_store_changed())
	else:
		b.disabled = true
	return b

# --- Teleporters ----------------------------------------------------------------------

func _travel_panel() -> Control:
	var here := String(_store_obj.get("st", {}).get("name", "This teleporter"))
	var s := _shell(here, "Every teleporter and waystone you build on this world links to the others.")
	var v: VBoxContainer = s[1]
	var me := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	var any := false
	for m in Game.markers.on_planet(Game.planet, "teleporter"):
		var d := Vector2(m["x"], m["z"]).distance_to(me)
		if d < 6.0:
			continue
		any = true
		var row := HBoxContainer.new()
		var l := UITheme.label("%s   ·   %s away" % [m["name"], _dist(d)], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(420, 0)
		row.add_child(l)
		var mx: float = m["x"]
		var mz: float = m["z"]
		row.add_child(UITheme.button("Travel", func():
			close()
			if player:
				player.teleport_to(mx + 2.5, mz + 2.5)
			Game.toast.emit("Travelling to %s" % m["name"])))
		v.add_child(row)
	if not any:
		v.add_child(UITheme.label("No other teleporters yet. Build another one somewhere else to link them.", 16, UITheme.DIM))
	return s[0]

func _portal_panel() -> Control:
	var s := _shell("Ancient Portal", "The ring hums. Through it lie the other worlds bound to this one; the alien ones are deadly.")
	var v: VBoxContainer = s[1]
	for p in Game.worlds():
		var n: int = p["n"]
		if n == Game.planet:
			continue
		var row := HBoxContainer.new()
		var been := Game.landings.has(n) or n == 0
		var l := UITheme.label("%s   ·   %s   ·   zone level %d+%s" % [p["name"], Planets.theme_label(p), int(p["base"]), "" if been else "   ·   unexplored"], 17,
			Color(0.85, 0.6, 1.0) if p.get("theme", "") == "alien" else UITheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(520, 0)
		row.add_child(l)
		var from := _portal_at
		row.add_child(UITheme.button("Step through", func():
			close()
			Game.travel_portal(player, n, from)))
		v.add_child(row)
	return s[0]

static func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

# --- Trading -------------------------------------------------------------------------

func _trade_panel() -> Control:
	var st := _trader
	var blurb := "%s trader. Goods from other eras fetch a premium here; selling floods demand." % Eras.NAMES[st["era"]]
	if st.has("purse"):
		blurb = "Trading with %s, who has %d Marks to spend. Friends get better prices." % [st["name"], int(st["purse"])]
	var s := _shell(st["name"], blurb)
	var v: VBoxContainer = s[1]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	# Buy column.
	var buy := VBoxContainer.new()
	buy.custom_minimum_size = Vector2(420, 480)
	buy.add_child(UITheme.label("Buy", 20, UITheme.ACCENT))
	for t in st["stock"]:
		var qty: int = st["stock"][t]
		if qty <= 0:
			continue
		var price := Economy.sell_price(st, t)
		var row := HBoxContainer.new()
		var l := UITheme.label("%s  (%d)" % [ItemDB.def(t)["name"], qty], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := UITheme.button("%d" % price, func():
			if Game.money < price:
				Game.toast.emit("Not enough Marks")
				return
			var ck := _trader_chunk.key if _trader_chunk else Vector2i.ZERO
			var o := Game.origin_here("bought", st["era"], ck)
			if Game.give(ItemDB.make(t, 1, 1.0, o)):
				Game.add_money(-price)
				st["stock"][t] -= 1
				if st.has("purse"):
					st["purse"] = int(st["purse"]) + price
				if _trader_chunk:
					Game.mark_chunk_dirty(_trader_chunk.data)
				_refresh())
		b.disabled = Game.money < price
		row.add_child(b)
		buy.add_child(row)
	h.add_child(buy)
	# Sell column.
	var sell_sc := ScrollContainer.new()
	sell_sc.custom_minimum_size = Vector2(460, 480)
	var sell := VBoxContainer.new()
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_sc.add_child(sell)
	sell.add_child(UITheme.label("Sell", 20, UITheme.ACCENT))
	for i in Inventory.SIZE:
		var it = Game.inventory.get_slot(i)
		if it == null:
			continue
		var unit := Economy.buy_price(st, it)
		var row := HBoxContainer.new()
		var l := UITheme.label("%s%s" % [ItemDB.display_name(it), ("  x%d" % it["qty"]) if ItemDB.is_stackable(it["type"]) else ""], 16)
		l.tooltip_text = UITheme.describe_item(it)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var idx := i
		row.add_child(UITheme.button("%d" % unit, func(): _sell(idx, 1)))
		if ItemDB.is_stackable(it["type"]) and it["qty"] > 1:
			row.add_child(UITheme.button("All", func(): _sell(idx, -1)))
		sell.add_child(row)
	h.add_child(sell_sc)
	return s[0]

func _sell(idx: int, qty: int) -> void:
	var it = Game.inventory.get_slot(idx)
	if it == null:
		return
	var n: int = it["qty"] if qty < 0 else qty
	var total := 0
	var sold := 0
	for k in n:
		var unit := Economy.buy_price(_trader, it)
		if _trader.has("purse") and total + unit > int(_trader["purse"]):
			break
		total += unit
		sold += 1
		Economy.record_sale_to_trader(_trader, it["type"], 1)
	if sold == 0:
		Game.toast.emit("%s can't afford that" % String(_trader["name"]).split(" ")[0])
		return
	n = sold
	if _trader.has("purse"):
		_trader["purse"] = int(_trader["purse"]) - total
	Game.inventory.remove_at(idx, n)
	Game.add_money(total)
	Game.toast.emit("Sold for %d Marks" % total)
	if _trader_chunk:
		Game.mark_chunk_dirty(_trader_chunk.data)
	_refresh()

# --- Map ------------------------------------------------------------------------------

func _map_panel() -> Control:
	var s := _shell("Atlas", "The land you have seen, under the fog of everything you haven't. %d regions discovered." % Game.discovery["regions"].size())
	var v: VBoxContainer = s[1]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var left := VBoxContainer.new()
	h.add_child(left)
	var m := AtlasView.new()
	m.player = player
	m.custom_minimum_size = Vector2(760, 560)
	m.changed.connect(_refresh)
	left.add_child(m)
	var tools := HBoxContainer.new()
	tools.add_child(UITheme.button("Centre on me", m.recentre))
	tools.add_child(UITheme.button("Zoom in", func(): m.zoom_by(1.5)))
	tools.add_child(UITheme.button("Zoom out", func(): m.zoom_by(1.0 / 1.5)))
	left.add_child(tools)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 610)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	scroll.add_child(side)
	var me := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	var sel := Game.markers.get_by_id(AtlasView.selected)
	if not sel.is_empty() and sel["kind"] == "pin" and int(sel["planet"]) == Game.planet:
		_marker_editor(side, sel)
		side.add_child(HSeparator.new())
	_map_filters(side)
	side.add_child(HSeparator.new())
	_map_finder(side, me)
	side.add_child(HSeparator.new())
	side.add_child(UITheme.label("Wonders", 18, UITheme.ACCENT))
	var any := false
	for key in Game.map.wonders:
		var w: Dictionary = Game.map.wonders[key]
		if not w.get("found", false):
			continue
		any = true
		var state := "conquered" if w.get("cleared", false) else "guarded"
		side.add_child(UITheme.label("%s  ·  %s  ·  %s" % [WonderSite.label(w["t"]), _dist(Vector2(w["x"], w["z"]).distance_to(me)), state], 14, WonderSite.COLORS[w["t"]]))
	if not any:
		side.add_child(UITheme.label("None found yet. Look for a beam of light on the horizon.", 13, UITheme.DIM))
	side.add_child(HSeparator.new())
	side.add_child(UITheme.label("Markers", 18, UITheme.ACCENT))
	side.add_child(UITheme.label("Click the map to drop one, click a marker to edit it.", 13, UITheme.DIM))
	side.add_child(UITheme.button("Mark where I stand", func():
		if player:
			var n := Game.markers.count_kind("pin") + 1
			var mk := Game.markers.add("Marker %d" % n, player.global_position.x, player.global_position.z, Game.planet)
			AtlasView.selected = int(mk["id"])
			Game.touch_player()
			_refresh()))
	for mk in Game.markers.on_planet(Game.planet):
		var row := HBoxContainer.new()
		var l := UITheme.label("%s  ·  %s" % [mk["name"], _dist(Vector2(mk["x"], mk["z"]).distance_to(me))], 14, Markers.color_of(mk))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var mx: float = mk["x"]
		var mz: float = mk["z"]
		row.add_child(_mini_button("Show", func():
			AtlasView.focus(mx, mz, me)))
		if mk["kind"] == "pin":
			var id: int = mk["id"]
			row.add_child(_mini_button("Edit", func():
				AtlasView.selected = id
				_refresh()))
		side.add_child(row)
	side.add_child(HSeparator.new())
	side.add_child(UITheme.label("Regions discovered", 18, UITheme.ACCENT))
	var regions: Dictionary = Game.discovery["regions"]
	var names := regions.keys()
	names.sort_custom(func(a, b): return regions[a]["day"] < regions[b]["day"])
	for n in names.slice(maxi(0, names.size() - 8)):
		side.add_child(UITheme.label("%s  ·  day %d" % [n, int(regions[n]["day"]) + 1], 14, UITheme.ERA_COLORS[regions[n]["era"]]))
	h.add_child(scroll)
	return s[0]

func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE if not Game.using_pad else Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 13)
	_small_button(b)
	b.pressed.connect(cb)
	return b

## Rename a marker, pick its colour and icon, or delete it. Changes save as you make them.
func _marker_editor(side: VBoxContainer, mk: Dictionary) -> void:
	var id: int = mk["id"]
	side.add_child(UITheme.label("Edit marker", 18, UITheme.ACCENT))
	var name_e := LineEdit.new()
	name_e.text = mk["name"]
	name_e.max_length = 40
	name_e.placeholder_text = "Marker name"
	var commit := func(_t = null) -> void:
		if name_e.text.strip_edges() != "" and name_e.text != Game.markers.get_by_id(id).get("name", ""):
			Game.markers.edit(id, {"name": name_e.text})
			Game.touch_player()
	name_e.text_submitted.connect(func(t):
		commit.call(t)
		name_e.release_focus()
		_refresh.call_deferred())
	name_e.focus_exited.connect(commit)
	side.add_child(name_e)
	var cols := GridContainer.new()
	cols.columns = 10
	cols.add_theme_constant_override("h_separation", 4)
	for i in Markers.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(26, 26)
		b.focus_mode = Control.FOCUS_NONE
		var on := int(mk.get("color", 0)) % Markers.COLORS.size() == i
		var sb := UITheme.sb(Markers.COLORS[i], Color.WHITE if on else Color(0, 0, 0, 0.6), 13, 3 if on else 1, 0)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.tooltip_text = "Colour"
		b.pressed.connect(func():
			commit.call()
			Game.markers.edit(id, {"color": i})
			Game.touch_player()
			_refresh())
		cols.add_child(b)
	side.add_child(cols)
	var icons := GridContainer.new()
	icons.columns = 6
	for ic in Markers.ICONS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.icon = MapCanvas.icon_texture(ic)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = String(ic).capitalize()
		# Flat tiles: the painted button frame would hide the small icons.
		var on: bool = String(mk.get("icon", "pin")) == String(ic)
		var flat := UITheme.sb(Color(1, 1, 1, 0.14) if on else Color(0, 0, 0, 0.35), UITheme.ACCENT if on else Color(1, 1, 1, 0.08), 6, 2 if on else 1, 4)
		for st in ["normal", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, flat)
		b.add_theme_stylebox_override("hover", UITheme.sb(Color(1, 1, 1, 0.18), UITheme.ACCENT, 6, 1, 4))
		b.pressed.connect(func():
			commit.call()
			Game.markers.edit(id, {"icon": ic})
			Game.touch_player()
			_refresh())
		icons.add_child(b)
	side.add_child(icons)
	var row := HBoxContainer.new()
	row.add_child(_mini_button("Done", func():
		commit.call()
		AtlasView.selected = -1
		_refresh()))
	row.add_child(_mini_button("Delete", func():
		Game.markers.remove(id)
		AtlasView.selected = -1
		Game.touch_player()
		_refresh()))
	side.add_child(row)

## Ticks for what the atlas and minimap show.
func _map_filters(side: VBoxContainer) -> void:
	side.add_child(UITheme.label("Show on map", 18, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	for c in WorldMap.CATEGORIES:
		var cat: String = c[0]
		var cb := CheckBox.new()
		cb.text = c[1]
		cb.icon = MapCanvas.icon_texture(c[2])
		cb.expand_icon = true
		cb.add_theme_constant_override("icon_max_width", 22)
		cb.add_theme_font_size_override("font_size", 14)
		cb.focus_mode = Control.FOCUS_NONE if not Game.using_pad else Control.FOCUS_ALL
		cb.button_pressed = Game.map.shows(cat)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			cb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		cb.toggled.connect(func(on): Game.map.set_shown(cat, on))
		grid.add_child(cb)
	side.add_child(grid)
	# The overlay painted over the land, one at a time (also the map overlay key).
	side.add_child(UITheme.label("Map overlay", 18, UITheme.ACCENT))
	var lg := GridContainer.new()
	lg.columns = 2
	var group := ButtonGroup.new()
	for i in MapLayers.COUNT:
		var rb := CheckBox.new()
		rb.text = MapLayers.NAMES[i]
		rb.button_group = group
		rb.add_theme_font_size_override("font_size", 14)
		rb.focus_mode = Control.FOCUS_NONE if not Game.using_pad else Control.FOCUS_ALL
		rb.button_pressed = Game.map.layer == i
		# Ticks like the filters above (the default radio rings barely show on the panel).
		for ic in [["radio_checked", "checked"], ["radio_unchecked", "unchecked"]]:
			rb.add_theme_icon_override(ic[0], ThemeDB.get_default_theme().get_icon(ic[1], "CheckBox"))
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			rb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		rb.toggled.connect(func(on): if on: Game.map.set_layer(i))
		lg.add_child(rb)
	side.add_child(lg)

static var _find := "ore_iron_vein"

## The nearest known places of one kind, each with a button to look at it on the map and
## one to pin it (so the minimap points the way).
func _map_finder(side: VBoxContainer, me: Vector2) -> void:
	var head := HBoxContainer.new()
	var t := UITheme.label("Find", 18, UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE if not Game.using_pad else Control.FOCUS_ALL
	for c in WorldMap.CATEGORIES:
		if c[0] == "marker":
			continue
		pick.add_item(c[1])
		pick.set_item_metadata(pick.item_count - 1, c[0])
		if c[0] == _find:
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(i):
		_find = pick.get_item_metadata(i)
		_refresh())
	head.add_child(pick)
	side.add_child(head)
	var found: Array = Game.map.known(_find)
	found.sort_custom(func(a, b): return Vector2(a["x"], a["z"]).distance_squared_to(me) < Vector2(b["x"], b["z"]).distance_squared_to(me))
	if found.is_empty():
		side.add_child(UITheme.label("None seen yet. Explore, and what you pass is remembered here.", 13, UITheme.DIM))
	for f in found.slice(0, 6):
		var row := HBoxContainer.new()
		var name: String = f["name"]
		if f.has("job") and f.has("town"):
			name = "%s, %s of %s" % [f["name"], f["job"], f["town"]]
		var l := UITheme.label("%s  ·  %s" % [name, _dist(Vector2(f["x"], f["z"]).distance_to(me))], 14, UITheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var fx: float = f["x"]
		var fz: float = f["z"]
		row.add_child(_mini_button("Show", func(): AtlasView.focus(fx, fz, me)))
		var icon: String = "mine" if _find.begins_with("ore_") else "quest"
		row.add_child(_mini_button("Pin", func():
			var mk := Game.markers.add(name.left(40), fx, fz, Game.planet, "pin", {"icon": icon})
			AtlasView.selected = int(mk["id"])
			Game.touch_player()
			_refresh()))
		side.add_child(row)


## One worn-armour slot. Drop matching armour from the pack on it to wear it, drag it back
## out (or click / right-click it) to take it off. While armour is being dragged, the slot
## it fits lights up.
class EquipSlot extends Button:
	const NAMES := {"head": "Head", "chest": "Chest", "hands": "Hands", "legs": "Legs", "feet": "Feet", "shield": "Off hand", "back": "Back", "ring": "Ring", "neck": "Neck"}
	var where: String
	var _glow := false

	func _init(w: String, px := 64) -> void:
		where = w
		var it = Game.equipment.get(where)
		GameMenus._style_slot(self, it, px)
		if it == null:
			var l := UITheme.label(NAMES.get(where, where.capitalize()).to_upper(), 11, Color(1, 1, 1, 0.28))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
			tooltip_text = "%s: nothing worn. Drag armour here." % NAMES.get(where, where)
		else:
			tooltip_text = "%s\nClick, right-click or drag out to take it off" % UITheme.describe_item(it)
		pressed.connect(func(): Game.unequip(where))
		gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				Game.unequip(where))

	func _get_drag_data(_at: Vector2) -> Variant:
		var it = Game.equipment.get(where)
		if it == null:
			return null
		set_drag_preview(GameMenus._drag_preview(it["type"]))
		return {"equip": where}

	func _can_drop_data(_at: Vector2, d: Variant) -> bool:
		return d is Dictionary and d.has("inv_slot") and Game.armor_slot_of(Game.inventory.get_slot(d["inv_slot"])) == where

	func _drop_data(_at: Vector2, d: Variant) -> void:
		Game.equip(d["inv_slot"])

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			var d = get_viewport().gui_get_drag_data()
			_glow = d is Dictionary and d.has("inv_slot") and Game.armor_slot_of(Game.inventory.get_slot(d["inv_slot"])) == where
			if _glow:
				add_theme_stylebox_override("normal", UITheme.tex_sb("slot_sel"))
		elif what == NOTIFICATION_DRAG_END and _glow:
			_glow = false
			add_theme_stylebox_override("normal", UITheme.rarity_sb(Game.equipment[where]) if Game.equipment.has(where) else UITheme.tex_sb("slot"))

	func _process(_d: float) -> void:
		if _glow:
			modulate = Color(1, 1, 1).lerp(Color(1.5, 1.35, 1.0), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008))
		elif modulate != Color.WHITE:
			modulate = Color.WHITE


## The figure you dress: Ben's engraved slate figure (assets/ui/ui_paperdoll.png) when it
## is there, else a drawn one, with the armour slots placed on it.
class Mannequin extends Control:
	const W := 300.0
	const H := 460.0
	## Slot centres. With the slate figure they sit on its head, chest, hands, legs and feet.
	const SLOT_AT := {"head": Vector2(150, 50), "chest": Vector2(150, 140), "hands": Vector2(78, 232), "shield": Vector2(222, 232), "legs": Vector2(150, 298), "feet": Vector2(150, 388), "back": Vector2(236, 96), "neck": Vector2(64, 96), "ring": Vector2(64, 162)}
	const SLOT_AT_DRAWN := {"head": Vector2(150, 58), "chest": Vector2(150, 160), "hands": Vector2(44, 252), "shield": Vector2(256, 252), "legs": Vector2(150, 296), "feet": Vector2(150, 396), "back": Vector2(256, 122), "neck": Vector2(44, 110), "ring": Vector2(44, 180)}
	var _doll: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_PASS
		_doll = UITheme.kit_texture("ui_paperdoll")
		var at: Dictionary = SLOT_AT if _doll else SLOT_AT_DRAWN
		for w in at:
			if not Game.ARMOR_SLOTS.has(w):
				continue
			var e := EquipSlot.new(w, 64)
			e.position = at[w] - Vector2(32, 32)
			e.size = Vector2(64, 64)
			add_child(e)

	func _limb(a: Vector2, b: Vector2, r: float, c: Color) -> void:
		draw_line(a, b, c, r * 2.0)
		draw_circle(a, r, c)
		draw_circle(b, r, c)

	func _figure(grow: float, c: Color) -> void:
		draw_circle(Vector2(150, 58), 30 + grow, c)
		_limb(Vector2(150, 86), Vector2(150, 104), 10 + grow, c)
		draw_colored_polygon(PackedVector2Array([Vector2(96 - grow, 104 - grow), Vector2(204 + grow, 104 - grow), Vector2(184 + grow, 232), Vector2(116 - grow, 232)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(116 - grow, 226), Vector2(184 + grow, 226), Vector2(190 + grow, 266 + grow), Vector2(110 - grow, 266 + grow)]), c)
		for sgn in [-1.0, 1.0]:
			var x := func(v: float) -> float: return 150.0 + sgn * v
			_limb(Vector2(x.call(50), 112), Vector2(x.call(80), 184), 13 + grow, c)
			_limb(Vector2(x.call(80), 184), Vector2(x.call(100), 236), 11 + grow, c)
			_limb(Vector2(x.call(22), 266), Vector2(x.call(26), 336), 17 + grow, c)
			_limb(Vector2(x.call(26), 336), Vector2(x.call(28), 392), 14 + grow, c)

	func _draw() -> void:
		if _doll:
			# The slate plate, fitted to the height and centred.
			var h := H
			var w := _doll.get_width() * h / _doll.get_height()
			draw_texture_rect(_doll, Rect2((W - w) * 0.5, 0, w, h), false)
			return
		# Floor glow, a soft rim of gold, then the body.
		for i in 6:
			var k := 1.0 - i / 6.0
			draw_set_transform(Vector2(150, 420), 0.0, Vector2(1.0, 0.22))
			draw_circle(Vector2.ZERO, 40 + i * 14, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.035 * k))
		draw_set_transform(Vector2.ZERO)
		_figure(3.0, Color(UITheme.ACCENT.r * 0.35, UITheme.ACCENT.g * 0.3, UITheme.ACCENT.b * 0.22, 1.0))
		_figure(0.0, Color(0.13, 0.145, 0.17, 1.0))
		draw_circle(Vector2(142, 48), 14, Color(1, 1, 1, 0.035))
		draw_colored_polygon(PackedVector2Array([Vector2(100, 106), Vector2(200, 106), Vector2(196, 120), Vector2(104, 120)]), Color(1, 1, 1, 0.03))
