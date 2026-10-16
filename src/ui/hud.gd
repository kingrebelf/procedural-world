class_name HUD
extends Control
## In-game overlay: crosshair, hotbar, vitals, money, region banner, toasts, clock.

var player: Player
var atmosphere: Atmosphere

var _prompt: Label
var _hotbar: HBoxContainer
var _slots: Array = []
var _health: ProgressBar
var _money: Label
var _banner: Label
var _banner_sub: Label
var _banner_box: VBoxContainer
var _toasts: VBoxContainer
var _info: Label
var _fps: Label
var _look: PanelContainer
var _look_title: Label
var _look_sub: Label
var _look_lines: Label
var _look_hp: ProgressBar
var _look_icon: TextureRect
var _feed: VBoxContainer
var _under: ColorRect
var _breath: ProgressBar
var _feed_rows: Dictionary = {} ## type -> {row, qty, label, t}

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.draw.connect(func():
		cross.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.85))
		cross.draw_arc(Vector2.ZERO, 9, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true))
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	_prompt = UITheme.label("", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-200, 28)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_prompt)

	_hotbar = HBoxContainer.new()
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar.position = Vector2(-((96 + 6) * 6) / 2.0, -112)
	add_child(_hotbar)
	for i in Inventory.HOTBAR:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(96, 70)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var n := UITheme.label("", 13)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(80, 0)
		var q := UITheme.label("", 13, UITheme.DIM)
		var key := UITheme.label(str(i + 1), 11, UITheme.DIM)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var top := HBoxContainer.new()
		top.add_child(key)
		top.add_child(ic)
		v.add_child(top)
		v.add_child(n)
		v.add_child(q)
		p.add_child(v)
		_hotbar.add_child(p)
		_slots.append({"panel": p, "name": n, "qty": q, "icon": ic})

	var vit := VBoxContainer.new()
	vit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vit.position = Vector2(28, -96)
	add_child(vit)
	_health = ProgressBar.new()
	_health.custom_minimum_size = Vector2(260, 14)
	_health.show_percentage = false
	_health.max_value = 100
	vit.add_child(UITheme.label("HEALTH", 12, UITheme.DIM))
	vit.add_child(_health)
	_money = UITheme.label("", 22, UITheme.ACCENT)
	vit.add_child(_money)

	_banner_box = VBoxContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_box.position = Vector2(-400, 70)
	_banner_box.size = Vector2(800, 100)
	_banner_box.modulate.a = 0.0
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_box)
	_banner_sub = UITheme.label("", 16, UITheme.DIM)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner = UITheme.label("", 40, UITheme.TEXT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_banner_box.add_child(_banner_sub)
	_banner_box.add_child(_banner)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toasts.position = Vector2(-340, -320)
	_toasts.size = Vector2(320, 300)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_info = UITheme.label("", 14, UITheme.DIM)
	_info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info.position = Vector2(-330, 20)
	_info.size = Vector2(310, 80)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_info)

	_fps = UITheme.label("", 14, UITheme.ACCENT_2)
	_fps.position = Vector2(20, 20)
	add_child(_fps)

	_under = ColorRect.new()
	_under.set_anchors_preset(Control.PRESET_FULL_RECT)
	_under.color = Color(0.05, 0.25, 0.3, 0.45)
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.visible = false
	add_child(_under)
	move_child(_under, 0)
	_breath = ProgressBar.new()
	_breath.custom_minimum_size = Vector2(260, 10)
	_breath.show_percentage = false
	_breath.max_value = Player.BREATH
	_breath.visible = false
	vit.add_child(_breath)
	_build_look_panel()
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_feed.position = Vector2(28, -40)
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	Game.item_gained.connect(_on_item)
	Game.toast.connect(_on_toast)
	Game.money_changed.connect(func(_m): _refresh())
	Game.health_changed.connect(func(_h): _refresh())
	Game.region_entered.connect(_on_region)
	Game.inventory.changed.connect(_refresh)
	_refresh()

func bind_player(p: Player) -> void:
	player = p
	p.look_info_changed.connect(_on_look)
	p.look_target_changed.connect(func(t): _prompt.text = t)
	p.selected_changed.connect(func(_i): _refresh())
	_refresh()

func _refresh() -> void:
	for i in Inventory.HOTBAR:
		var it = Game.inventory.get_slot(i)
		var s: Dictionary = _slots[i]
		s["name"].text = ItemDB.display_name(it) if it != null else ""
		s["qty"].text = ("x%d" % it["qty"]) if it != null and ItemDB.is_stackable(it["type"]) else ""
		s["icon"].texture = Icons.get_icon(it["type"]) if it != null else null
		var sel := player != null and player.selected == i
		s["panel"].add_theme_stylebox_override("panel", UITheme.sb(Color(0.08, 0.08, 0.09, 0.8 if sel else 0.55),
			UITheme.ACCENT if sel else Color(1, 1, 1, 0.1), 6, 2 if sel else 1, 8))
	_health.value = Game.health
	_money.text = "%d Marks" % Game.money

func _on_toast(text: String) -> void:
	var l := UITheme.label(text, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toasts.add_child(l)
	if _toasts.get_child_count() > 7:
		_toasts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _build_look_panel() -> void:
	_look = PanelContainer.new()
	_look.add_theme_stylebox_override("panel", UITheme.sb(Color(0.05, 0.06, 0.07, 0.72), Color(1, 1, 1, 0.08), 8, 1, 12))
	_look.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_look.position = Vector2(-360, 96)
	_look.custom_minimum_size = Vector2(340, 0)
	_look.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look.visible = false
	add_child(_look)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_look.add_child(h)
	_look_icon = TextureRect.new()
	_look_icon.custom_minimum_size = Vector2(48, 48)
	_look_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_look_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_look_icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	_look_title = UITheme.label("", 18, UITheme.ACCENT)
	_look_sub = UITheme.label("", 13, UITheme.DIM)
	_look_hp = ProgressBar.new()
	_look_hp.custom_minimum_size = Vector2(0, 6)
	_look_hp.show_percentage = false
	_look_hp.max_value = 1.0
	_look_lines = UITheme.label("", 14)
	_look_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_look_lines.custom_minimum_size = Vector2(260, 0)
	for c in [_look_title, _look_sub, _look_hp, _look_lines]:
		v.add_child(c)

func _on_look(info: Dictionary) -> void:
	_look.visible = not info.is_empty()
	if info.is_empty():
		return
	_look_title.text = info["title"]
	_look_sub.text = info.get("sub", "")
	_look_lines.text = "\n".join(info.get("lines", []))
	_look_hp.visible = info.has("hp")
	_look_hp.value = info.get("hp", 1.0)
	_look_icon.texture = Icons.get_icon(info["icon"]) if info.has("icon") else null
	_look_icon.visible = info.has("icon")
	_look.reset_size()

## Pickup feed: "[icon] +1 Stone". Repeated pickups of the same item merge into one row.
func _on_item(type: String, qty: int) -> void:
	var e = _feed_rows.get(type)
	if e != null and is_instance_valid(e["row"]):
		e["qty"] += qty
		e["tw"].kill()
		e["row"].modulate.a = 1.0
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = Icons.get_icon("gold_coin" if type == "_marks" else type)
		row.add_child(ic)
		var l := UITheme.label("", 18)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		row.add_child(l)
		_feed.add_child(row)
		if _feed.get_child_count() > 6:
			_feed.get_child(0).queue_free()
		e = {"row": row, "label": l, "qty": qty}
		_feed_rows[type] = e
	var name: String = "Marks" if type == "_marks" else ItemDB.def(type).get("name", type)
	e["label"].text = "+%d %s" % [e["qty"], name]
	var row: Control = e["row"]
	var tw := row.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(row, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		_feed_rows.erase(type)
		row.queue_free())
	e["tw"] = tw

func _on_region(region: String, era: int) -> void:
	_banner.text = region
	_banner_sub.text = "%s lands" % Eras.NAMES[era]
	_banner_sub.add_theme_color_override("font_color", UITheme.ERA_COLORS[era])
	var tw := _banner_box.create_tween()
	tw.tween_property(_banner_box, "modulate:a", 1.0, 1.2)
	tw.tween_interval(3.5)
	tw.tween_property(_banner_box, "modulate:a", 0.0, 2.0)

func _process(_d: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var t := fposmod(Game.day, 1.0) * 24.0
	var heading := int(round(fposmod(-rad_to_deg(player.rotation.y), 360.0)))
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	_info.text = "Day %d  %02d:%02d\n%s  %d°\n%d, %d" % [int(Game.day) + 1, int(t), int(fmod(t, 1.0) * 60), dirs[int(round(heading / 45.0)) % 8], heading, int(p.x), int(p.z)]
	_under.visible = player.underwater
	_breath.visible = player.breath < Player.BREATH - 0.01
	_breath.value = player.breath
	_fps.visible = Settings.get_value("show_fps")
	if _fps.visible:
		_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
