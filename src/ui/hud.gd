class_name HUD
extends Control
## In-game overlay: crosshair, hotbar, vitals, money, region banner, toasts, clock.

var player: Player
var atmosphere: Atmosphere

var _prompt: Label
var _hotbar: HBoxContainer
var _slots: Array = []
var _health: ProgressBar
var _held_name: Label
var _use_box: PanelContainer
var _use_key: Label
var _use_keycap: PanelContainer
var _use_hold: ProgressBar
var _use_verb: Label
const PAD_FACE := {0: ["A", Color(0.38, 0.75, 0.3)], 1: ["B", Color(0.85, 0.3, 0.27)], 2: ["X", Color(0.3, 0.55, 0.9)], 3: ["Y", Color(0.92, 0.75, 0.25)]}
const PICK_GLYPHS := ["Y", "B", "X", "A", "←", "→", "↑", "↓"]
var _health_val: Label
var _stamina: ProgressBar
var _stamina_val: Label
var _xp: ProgressBar
var _xp_val: Label
var _level: Label
var _points: Label
var _xp_pop: Label
var _xp_pop_n := 0.0
var _xp_tw: Tween
var _money: Label
var _weight: Label
var _xp_flash: Label ## "+N XP" that pops up under the crosshair
var _flash_tw: Tween
var _pulse := 0.0
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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.draw.connect(func():
		cross.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.85))
		cross.draw_arc(Vector2.ZERO, 9, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true))
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	_prompt = UITheme.label("", 18)
	_pin(_prompt, Control.PRESET_CENTER, Rect2(-200, 28, 400, 30))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_prompt)

	# Ten slots, ARK style: big icons, the key in the corner, the count underneath, and the
	# held item's name above the bar.
	const SLOT := 60
	var w := (SLOT + 5) * Inventory.HOTBAR
	_held_name = UITheme.label("", 16)
	_held_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_pin(_held_name, Control.PRESET_CENTER_BOTTOM, Rect2(-200, -SLOT - 52, 400, 24))
	add_child(_held_name)
	_hotbar = HBoxContainer.new()
	_pin(_hotbar, Control.PRESET_CENTER_BOTTOM, Rect2(-w / 2.0, -SLOT - 24, w, SLOT))
	_hotbar.add_theme_constant_override("separation", 5)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar)
	for i in Inventory.HOTBAR:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(box)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_pin(ic, Control.PRESET_FULL_RECT, Rect2(4, 2, -8, -6))
		box.add_child(ic)
		var key := UITheme.label(str((i + 1) % 10), 11, UITheme.DIM)
		_pin(key, Control.PRESET_TOP_LEFT, Rect2(-4, -8, 30, 16))
		key.add_theme_constant_override("outline_size", 3)
		key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		box.add_child(key)
		var q := UITheme.label("", 12)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_pin(q, Control.PRESET_BOTTOM_RIGHT, Rect2(-50, -12, 54, 16))
		q.add_theme_constant_override("outline_size", 4)
		q.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		box.add_child(q)
		_hotbar.add_child(p)
		_slots.append({"panel": p, "qty": q, "icon": ic, "key": key})

	var vit := VBoxContainer.new()
	_pin(vit, Control.PRESET_BOTTOM_LEFT, Rect2(24, -178, 260, 160))
	vit.alignment = BoxContainer.ALIGNMENT_END
	vit.add_theme_constant_override("separation", 3)
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vit)
	var lv_row := HBoxContainer.new()
	_level = UITheme.label("", 18, UITheme.ACCENT)
	_points = UITheme.label("", 13, UITheme.ACCENT_2)
	_xp_pop = UITheme.label("", 13, UITheme.DIM)
	_xp_pop.modulate.a = 0.0
	lv_row.add_child(_level)
	lv_row.add_child(_points)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.add_child(gap)
	lv_row.add_child(_xp_pop)
	vit.add_child(lv_row)
	var hb := _bar(vit, "HEALTH", Color(0.78, 0.2, 0.18), 14)
	_health = hb[0]
	_health_val = hb[1]
	var sb := _bar(vit, "STAMINA", Color(0.36, 0.72, 0.3), 10)
	_stamina = sb[0]
	_stamina_val = sb[1]
	var xb := _bar(vit, "EXPERIENCE", Color(0.92, 0.72, 0.28), 6)
	_xp = xb[0]
	_xp_val = xb[1]
	_money = UITheme.label("", 22, UITheme.ACCENT)
	vit.add_child(_money)
	_weight = UITheme.label("", 13, UITheme.DIM)
	vit.add_child(_weight)
	_xp_flash = UITheme.label("", 26, Color(1.0, 0.86, 0.35))
	_xp_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_flash.add_theme_constant_override("outline_size", 6)
	_xp_flash.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.0, 0.9))
	_pin(_xp_flash, Control.PRESET_CENTER, Rect2(-200, 34, 400, 40))
	_xp_flash.pivot_offset = Vector2(200, 20)
	_xp_flash.modulate.a = 0.0
	_xp_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_flash)

	_banner_box = VBoxContainer.new()
	_pin(_banner_box, Control.PRESET_CENTER_TOP, Rect2(-600, 70, 1200, 100))
	_banner_box.modulate.a = 0.0
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_box)
	_banner_sub = UITheme.label("", 16, UITheme.DIM)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner = UITheme.label("", 40, UITheme.TEXT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_banner_sub.add_theme_constant_override("outline_size", 4)
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_banner_box.add_child(_banner_sub)
	_banner_box.add_child(_banner)

	_toasts = VBoxContainer.new()
	_pin(_toasts, Control.PRESET_BOTTOM_RIGHT, Rect2(-340, -320, 320, 300))
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_info = UITheme.label("", 14, UITheme.DIM)
	_pin(_info, Control.PRESET_TOP_RIGHT, Rect2(-330, 20, 310, 80))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_info)

	_fps = UITheme.label("", 14, UITheme.ACCENT_2)
	_pin(_fps, Control.PRESET_TOP_LEFT, Rect2(20, 20, 300, 24))
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
	_breath.max_value = Stats.BASE_BREATH
	_breath.visible = false
	vit.add_child(_breath)
	_build_look_panel()
	_build_use_prompt()
	_feed = VBoxContainer.new()
	_pin(_feed, Control.PRESET_CENTER_LEFT, Rect2(28, -40, 360, 300))
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	Game.item_gained.connect(_on_item)
	Game.toast.connect(_on_toast)
	Game.money_changed.connect(func(_m): _refresh())
	Game.health_changed.connect(func(_h): _refresh())
	Game.stats_changed.connect(_refresh)
	Game.leveled_up.connect(_on_level)
	Game.xp_gained.connect(_on_xp)
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
		s["qty"].text = ("%d" % it["qty"]) if it != null and ItemDB.is_stackable(it["type"]) else ""
		s["icon"].texture = Icons.get_icon(it["type"]) if it != null else null
		var sel := player != null and player.selected == i
		if sel:
			_held_name.text = ItemDB.display_name(it) if it != null else ""
		s["panel"].add_theme_stylebox_override("panel", UITheme.sb(Color(0.08, 0.08, 0.09, 0.8 if sel else 0.55),
			UITheme.ACCENT if sel else Color(1, 1, 1, 0.1), 6, 2 if sel else 1, 8))
	_health.max_value = Game.max_health()
	_health.value = Game.health
	_health_val.text = "%d / %d" % [ceili(Game.health), int(Game.max_health())]
	var st := Game.stats
	_level.text = "Level %d" % st.level
	_points.text = ("   %d point%s to spend  [%s]" % [st.points, "" if st.points == 1 else "s", Bindings.key_name("character", Game.using_pad)]) if st.points > 0 else ""
	_xp.max_value = Stats.xp_to_next(st.level)
	_xp.value = st.xp
	_xp_val.text = "%d / %d" % [st.xp, Stats.xp_to_next(st.level)] if st.level < Stats.MAX_LEVEL else "MAX"
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
	_pin(_look, Control.PRESET_TOP_RIGHT, Rect2(-360, 96, 340, 40))
	_look.grow_horizontal = Control.GROW_DIRECTION_BEGIN
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

## Anchors a control to a screen edge or corner with an explicit rectangle relative to
## that anchor, so it stays in place whatever the window size was when the HUD was built.
static func _pin(c: Control, preset: int, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

## The floating "[E] Open chest" prompt that hovers over whatever Interact will use.
func _build_use_prompt() -> void:
	_use_box = PanelContainer.new()
	_use_box.add_theme_stylebox_override("panel", UITheme.sb(Color(0.04, 0.045, 0.05, 0.78), Color(1, 1, 1, 0.12), 8, 1, 6))
	_use_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_box.modulate.a = 0.0
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_use_keycap = PanelContainer.new()
	_use_keycap.custom_minimum_size = Vector2(26, 26)
	_use_key = UITheme.label("E", 15, Color(0.08, 0.08, 0.09))
	_use_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_use_keycap.add_child(_use_key)
	h.add_child(_use_keycap)
	_use_verb = UITheme.label("", 16)
	h.add_child(_use_verb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.add_child(h)
	# Fills while Interact is held on one of your pieces, to take it down.
	_use_hold = ProgressBar.new()
	_use_hold.show_percentage = false
	_use_hold.custom_minimum_size = Vector2(0, 5)
	_use_hold.max_value = 1.0
	_use_hold.add_theme_stylebox_override("background", UITheme.sb(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 2, 0, 0))
	_use_hold.add_theme_stylebox_override("fill", UITheme.sb(Color(0.95, 0.62, 0.25), Color(0, 0, 0, 0), 2, 0, 0))
	_use_hold.visible = false
	v.add_child(_use_hold)
	_use_box.add_child(v)
	add_child(_use_box)

func _update_use_prompt(delta: float) -> void:
	var f: Dictionary = player.focus
	var cam := get_viewport().get_camera_3d()
	var show := not f.is_empty() and cam != null and not cam.is_position_behind(f["pos"]) and not player.ui_open
	_use_box.modulate.a = move_toward(_use_box.modulate.a, 1.0 if show else 0.0, delta * 8.0)
	if not show:
		return
	_use_verb.text = f["verb"]
	_use_hold.visible = player.decon > 0.0
	_use_hold.value = player.decon
	var spec = Bindings.spec("interact", "pad" if Game.using_pad else "kb")
	var pad_btn := String(spec).trim_prefix("btn:").to_int() if Game.using_pad and String(spec).begins_with("btn:") else -1
	if PAD_FACE.has(pad_btn):
		_use_key.text = PAD_FACE[pad_btn][0]
		_use_keycap.add_theme_stylebox_override("panel", UITheme.sb(PAD_FACE[pad_btn][1], Color(0, 0, 0, 0.3), 13, 1, 2))
	else:
		_use_key.text = Bindings.describe(spec)
		_use_keycap.add_theme_stylebox_override("panel", UITheme.sb(Color(0.9, 0.88, 0.82), Color(0.45, 0.42, 0.36), 5, 2, 4))
	_use_box.reset_size()
	var at := cam.unproject_position(f["pos"])
	_use_box.position = (at - Vector2(_use_box.size.x * 0.5, _use_box.size.y)).round()

var _death: Control

func show_death(cause: String) -> void:
	if _death:
		_death.queue_free()
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.12, 0.0, 0.0, 0.0)
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := UITheme.label("YOU DIED", 64, Color(0.9, 0.25, 0.2))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(t)
	var c := UITheme.label(cause, 22)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var w := UITheme.label("You keep everything you carry, but lose a quarter of your progress to the next level.", 16, UITheme.DIM)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(w)
	_death.add_child(v)
	add_child(_death)
	_death.modulate.a = 0.0
	var tw := _death.create_tween()
	tw.tween_property(_death, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(_death, "color:a", 0.75, 1.5)

func hide_death() -> void:
	if _death:
		var d := _death
		_death = null
		var tw := d.create_tween()
		tw.tween_property(d, "modulate:a", 0.0, 0.8)
		tw.tween_callback(d.queue_free)

## A captioned bar: a small label and value above a coloured ProgressBar.
static func _bar(parent: Control, caption: String, col: Color, h: int) -> Array:
	var row := HBoxContainer.new()
	row.add_child(UITheme.label(caption, 11, UITheme.DIM))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var val := UITheme.label("", 11, UITheme.DIM)
	row.add_child(val)
	parent.add_child(row)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(260, h)
	b.show_percentage = false
	b.add_theme_stylebox_override("fill", UITheme.sb(col, Color(0, 0, 0, 0), 4, 0, 0))
	parent.add_child(b)
	return [b, val]

func _on_level(level: int) -> void:
	_banner.text = "Level %d" % level
	_banner_sub.text = "%d attribute points to spend  [%s]" % [Game.stats.points, Bindings.key_name("character", Game.using_pad)]
	_banner_sub.add_theme_color_override("font_color", UITheme.ACCENT)
	var tw := _banner_box.create_tween()
	tw.tween_property(_banner_box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(3.0)
	tw.tween_property(_banner_box, "modulate:a", 0.0, 1.5)

func _on_xp(amount: int, why: String) -> void:
	if amount <= 0:
		return
	if _xp_tw and _xp_tw.is_valid():
		_xp_tw.kill()
	else:
		_xp_pop_n = 0.0
	_xp_pop_n += amount
	_xp_pop.text = "+%d XP  %s" % [int(_xp_pop_n), why]
	_xp_pop.modulate.a = 1.0
	_xp_tw = _xp_pop.create_tween()
	_xp_tw.tween_interval(2.0)
	_xp_tw.tween_property(_xp_pop, "modulate:a", 0.0, 0.8)
	# A bright pop under the crosshair, and the experience bar flares.
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	_xp_flash.text = "+%d XP" % int(_xp_pop_n)
	_xp_flash.modulate = Color(1.6, 1.6, 1.6, 1.0)
	_xp_flash.scale = Vector2(1.5, 1.5)
	_xp_flash.position.y = get_viewport_rect().size.y * 0.5 + 34.0
	_flash_tw = _xp_flash.create_tween()
	_flash_tw.set_parallel(true)
	_flash_tw.tween_property(_xp_flash, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flash_tw.tween_property(_xp_flash, "modulate", Color(1, 1, 1, 1), 0.3)
	_flash_tw.tween_property(_xp_flash, "position:y", _xp_flash.position.y - 26.0, 1.4).set_ease(Tween.EASE_OUT)
	_flash_tw.chain().tween_property(_xp_flash, "modulate:a", 0.0, 0.6)
	_xp.modulate = Color(2.2, 2.0, 1.4)
	_xp.create_tween().tween_property(_xp, "modulate", Color.WHITE, 0.6)

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
	_update_use_prompt(_d)
	var p := player.global_position
	var t := fposmod(Game.day, 1.0) * 24.0
	var heading := int(round(fposmod(-rad_to_deg(player.rotation.y), 360.0)))
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	_info.text = "Day %d  %02d:%02d\n%s  %d°\n%d, %d" % [int(Game.day) + 1, int(t), int(fmod(t, 1.0) * 60), dirs[int(round(heading / 45.0)) % 8], heading, int(p.x), int(p.z)]
	_under.visible = player.underwater
	_breath.max_value = Game.stats.max_breath()
	# Unspent attribute points glow slowly until spent.
	_pulse += _d
	_points.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * 2.6)) if Game.stats.points > 0 else 1.0
	var kg := Game.inventory.weight()
	var cap := Game.stats.carry_capacity()
	_weight.text = "Pack %.0f / %d kg%s" % [kg, int(cap), "  OVERLOADED" if kg > cap else ""]
	_weight.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if kg > cap else UITheme.DIM)
	_breath.visible = player.breath < Game.stats.max_breath() - 0.01
	_breath.value = player.breath
	# On a controller, holding the pick button shows which face button picks each slot.
	var pick := Game.using_pad and Input.is_action_pressed("hotbar_pick")
	for i in _slots.size():
		_slots[i]["key"].text = (PICK_GLYPHS[i] if i < PICK_GLYPHS.size() else "") if pick else ("" if Game.using_pad else str((i + 1) % 10))
		_slots[i]["key"].add_theme_color_override("font_color", UITheme.ACCENT if pick else UITheme.DIM)
	_stamina.max_value = Game.max_stamina()
	_stamina.value = Game.stamina
	_stamina_val.text = "WINDED" if player.winded else "%d / %d" % [int(Game.stamina), int(Game.max_stamina())]
	_fps.visible = Settings.get_value("show_fps")
	if _fps.visible:
		_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
