class_name HUD
extends Control
## In-game overlay: crosshair, hotbar, vitals, money, region banner, toasts, clock.

var player: Player
var atmosphere: Atmosphere

var _prompt: Label
var _cross: Control
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
var _fuel: ProgressBar ## shown only while a jetpack is worn
var _fuel_val: Label
var _xp: ProgressBar
var _xp_val: Label
var _level: Label
var _points: Label
var _xp_pop: Label
var _xp_pop_n := 0.0
var _xp_tw: Tween
var _money: Label
var _buffs: Label
var _weight: Label
var _xp_flash: Label ## "+N XP" that pops up under the crosshair
var _flash_tw: Tween
var _pulse := 0.0
var _marks: MarkerLayer
var _minimap: Minimap
var _banner: Label
var _banner_sub: Label
var _banner_box: VBoxContainer
var _toasts: VBoxContainer
var _info: Label
var _fps: Label
var _perf_t := 0.0
var _perf_cache := ""
var _look: PanelContainer
var _look_title: Label
var _look_sub: Label
var _look_lines: Label
var _look_hp: ProgressBar
var _look_icon: TextureRect
var _feed: VBoxContainer
var _under: ColorRect
var _bino: ColorRect ## the twin-circle view through raised binoculars
var _breath: ProgressBar
var _feed_rows: Dictionary = {} ## type -> {row, qty, label, t}
var _badge: Control ## the round level badge on the vitals plate
var _compass: Compass
var _mouse_hint: PanelContainer
var _mouse_key: PanelContainer
var _mouse_text: Label
var _mouse_state := -1
var _wanted: WantedBar ## wanted stars under the compass
var _eye: Label ## the sneak eye above the crosshair while crouched

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.draw.connect(_draw_cross.bind(cross))
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)
	_cross = cross

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
	_held_name.add_theme_font_size_override("font_size", 18)
	if UITheme.font("bold"):
		_held_name.add_theme_font_override("font", UITheme.font("bold"))
	_pin(_held_name, Control.PRESET_CENTER_BOTTOM, Rect2(-200, -SLOT - 66, 400, 26))
	add_child(_held_name)
	_hotbar = HBoxContainer.new()
	_pin(_hotbar, Control.PRESET_CENTER_BOTTOM, Rect2(-w / 2.0, -SLOT - 38, w, SLOT))
	_hotbar.add_theme_constant_override("separation", 5)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar)
	for i in Inventory.HOTBAR:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.pivot_offset = Vector2(SLOT, SLOT) * 0.5
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(box)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_pin(ic, Control.PRESET_FULL_RECT, Rect2(4, 2, -8, -6))
		box.add_child(ic)
		var key := UITheme.label(str((i + 1) % 10), 12, UITheme.DIM)
		_pin(key, Control.PRESET_TOP_LEFT, Rect2(-3, -6, 30, 16))
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

	# Vitals plate, bottom left: a round level badge beside the health, stamina and
	# experience bars; money and pack weight underneath.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UITheme.tex_sb("panel", 14, 12))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(plate, Control.PRESET_BOTTOM_LEFT, Rect2(20, -196, 360, 0))
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(plate)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(top)
	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(62, 62)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	top.add_child(_badge)
	var vit := VBoxContainer.new()
	vit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vit.add_theme_constant_override("separation", 3)
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(vit)
	var lv_row := HBoxContainer.new()
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level = UITheme.label("", 15, UITheme.ACCENT)
	if UITheme.font("bold"):
		_level.add_theme_font_override("font", UITheme.font("bold"))
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
	var hb := _bar(vit, "HEALTH", Color(0.8, 0.17, 0.15), 18, "health")
	_health = hb[0]
	_health_val = hb[1]
	var sb := _bar(vit, "STAMINA", Color(0.33, 0.7, 0.28), 12, "stamina")
	_stamina = sb[0]
	_stamina_val = sb[1]
	var fb := _bar(vit, "JETPACK FUEL", Color(0.95, 0.55, 0.15), 12, "burning")
	_fuel = fb[0]
	_fuel_val = fb[1]
	var xb := _bar(vit, "XP", Color(0.92, 0.72, 0.28), 7, "xp")
	_xp = xb[0]
	_xp_val = xb[1]
	# Timed effects from food, potions and scrolls, with the time each has left.
	_buffs = UITheme.label("", 12, UITheme.DIM)
	_buffs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.add_child(_buffs)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(bottom)
	var coin := UITheme.icon_rect("gold_coin", 24)
	if UITheme.status_icon("gold"):
		coin.texture = UITheme.status_icon("gold")
	bottom.add_child(coin)
	_money = UITheme.label("", 19, UITheme.ACCENT)
	if UITheme.font("bold"):
		_money.add_theme_font_override("font", UITheme.font("bold"))
	bottom.add_child(_money)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap2)
	_weight = UITheme.label("", 14, UITheme.DIM)
	_weight.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_weight)
	_xp_flash = UITheme.label("", 26, Color(1.0, 0.86, 0.35))
	_xp_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_flash.add_theme_constant_override("outline_size", 6)
	_xp_flash.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.0, 0.9))
	_pin(_xp_flash, Control.PRESET_CENTER, Rect2(-200, 34, 400, 40))
	_xp_flash.pivot_offset = Vector2(200, 20)
	_xp_flash.modulate.a = 0.0
	_xp_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_flash)
	_marks = MarkerLayer.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marks)
	move_child(_marks, 0)

	_banner_box = VBoxContainer.new()
	_pin(_banner_box, Control.PRESET_CENTER_TOP, Rect2(-600, 84, 1200, 100))
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
	_info.visible = false # the minimap shows the day, time and where you are
	add_child(_info)
	_minimap = Minimap.new()
	_pin(_minimap, Control.PRESET_TOP_RIGHT, Rect2(-Minimap.DIAM - 22, 18, Minimap.DIAM, Minimap.DIAM + 80))
	add_child(_minimap)
	# Top centre: a compass strip with your markers on it.
	_compass = Compass.new()
	_pin(_compass, Control.PRESET_CENTER_TOP, Rect2(-280, 14, 560, 40))
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compass)
	_build_mouse_hint()
	_wanted = WantedBar.new()
	_pin(_wanted, Control.PRESET_CENTER_TOP, Rect2(-300, 58, 600, 30))
	_wanted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wanted)
	_eye = UITheme.label("", 15)
	_pin(_eye, Control.PRESET_CENTER, Rect2(-120, -58, 240, 22))
	_eye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eye.add_theme_constant_override("outline_size", 4)
	_eye.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_eye)

	_fps = UITheme.label("", 14, UITheme.ACCENT_2)
	_pin(_fps, Control.PRESET_TOP_LEFT, Rect2(32, 16, 560, 64))
	_fps.visible = false
	add_child(_fps)

	# Which build this is, so a screenshot says what it shows.
	var ver := UITheme.label("v%s" % ProjectSettings.get_setting("application/config/version"), 12, UITheme.DIM)
	ver.name = "Version"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.modulate.a = 0.7
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ver.add_theme_constant_override("outline_size", 3)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_pin(ver, Control.PRESET_BOTTOM_RIGHT, Rect2(-210, -20, 200, 16))
	add_child(ver)

	_under = ColorRect.new()
	_under.set_anchors_preset(Control.PRESET_FULL_RECT)
	var um := ShaderMaterial.new()
	um.shader = load("res://src/env/underwater.gdshader")
	_under.material = um
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.visible = false
	add_child(_under)
	move_child(_under, 0)
	_bino = ColorRect.new()
	_bino.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bino.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bino.visible = false
	var sh := Shader.new()
	sh.code = BINO_SHADER
	_bino.material = ShaderMaterial.new()
	(_bino.material as ShaderMaterial).shader = sh
	add_child(_bino)
	move_child(_bino, 1)
	_breath = ProgressBar.new()
	_breath.add_theme_stylebox_override("fill", UITheme.bar_fill(Color(0.35, 0.7, 0.95)))
	_breath.custom_minimum_size = Vector2(260, 8)
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
	Game.discovered.connect(_on_discovered)
	Game.inventory.changed.connect(_refresh)
	_refresh()

func bind_player(p: Player) -> void:
	player = p
	_minimap.player = p
	p.look_info_changed.connect(_on_look)
	p.hit_marker.connect(_on_hit_marker)
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
		var box: StyleBox = UITheme.tex_sb("slot_sel", 8) if sel else (UITheme.rarity_sb(it, UITheme.SLOT_BG, 2, 8) if it != null else UITheme.tex_sb("slot", 8))
		s["panel"].add_theme_stylebox_override("panel", box)
		s["panel"].scale = Vector2(1.08, 1.08) if sel else Vector2.ONE
		s["panel"].z_index = 1 if sel else 0
		s["panel"].modulate.a = 1.0 if sel or it != null else 0.75
		if sel and it != null and Rarity.of(it) > 0:
			_held_name.add_theme_color_override("font_color", Rarity.color(it))
		elif sel:
			_held_name.remove_theme_color_override("font_color")
	_health.max_value = Game.max_health()
	_health.value = Game.health
	_health_val.text = "%d / %d" % [ceili(Game.health), int(Game.max_health())]
	var st := Game.stats
	_level.text = "LEVEL %d" % st.level
	_badge.queue_redraw()
	_points.text = ("   %d point%s to spend  [%s]" % [st.points, "" if st.points == 1 else "s", Bindings.key_name("character", Game.using_pad)]) if st.points > 0 else ""
	_xp.max_value = Stats.xp_to_next(st.level)
	_xp.value = st.xp
	_xp_val.text = "%d / %d" % [st.xp, Stats.xp_to_next(st.level)] if st.level < Stats.MAX_LEVEL else "MAX"
	_money.text = "%d" % Game.money

func _on_toast(text: String) -> void:
	var l := PanelContainer.new()
	l.add_theme_stylebox_override("panel", UITheme.sb(Color(0.04, 0.045, 0.055, 0.82), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.35), 5, 1, 12))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	var t := UITheme.label(text, 16)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(minf(300, 9.0 * text.length() + 10), 0)
	l.add_child(t)
	_toasts.add_child(l)
	if _toasts.get_child_count() > 7:
		_toasts.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _build_look_panel() -> void:
	_look = PanelContainer.new()
	_look.add_theme_stylebox_override("panel", UITheme.tex_sb("panel", 14, 10))
	_pin(_look, Control.PRESET_TOP_RIGHT, Rect2(-360, Minimap.DIAM + 112, 340, 40)) # under the minimap
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
	_look_title = UITheme.label("", 19, UITheme.ACCENT)
	if UITheme.font("bold"):
		_look_title.add_theme_font_override("font", UITheme.font("bold"))
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
	_use_box.add_theme_stylebox_override("panel", UITheme.tex_sb("panel", 10, 6))
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
		_use_keycap.add_theme_stylebox_override("panel", UITheme.tex_sb("keycap", 6, 1))
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
	var keep: bool = Game.server_option("death_penalty", "bag") == "keep"
	var w := UITheme.label(("You keep everything you carry, but" if keep else "Everything you carried is in a bag where you fell, marked on your map. Anyone who finds it can take it.\nYou also") + " lose a quarter of your progress to the next level.", 16, UITheme.DIM)
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

## A bar with its caption on the left and the value on the right, drawn inside the bar
## when it is tall enough, above it otherwise. A status icon sits in front of it, and tall
## bars sit in Ben's painted bar frame. Returns [bar, value label]; the bar's "row" meta
## is the whole row, to show or hide.
static func _bar(parent: Control, caption: String, col: Color, h: int, icon := "") -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := UITheme.status_icon(icon) if icon != "" else null
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.custom_minimum_size = Vector2(26, 26) if h >= 12 else Vector2(18, 18)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	var col_box := VBoxContainer.new()
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_box.add_theme_constant_override("separation", 1)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col_box)
	parent.add_child(row)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(150, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("fill", UITheme.bar_fill(col))
	b.set_meta("row", row)
	var cap := UITheme.label(caption, 11 if h >= 12 else 10, Color(1, 1, 1, 0.85) if h >= 12 else UITheme.DIM)
	var val := UITheme.label("", 11 if h >= 12 else 10, Color(1, 1, 1, 0.9) if h >= 12 else UITheme.DIM)
	for l in [cap, val]:
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if h >= 12:
		for l in [cap, val]:
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.offset_left = 6
			l.offset_right = -6
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b.add_child(l)
		var frame := UITheme.kit_sb("bar_frame", 0, 0)
		if frame:
			# The painted frame wraps the bar; its gem ends overhang the fill.
			frame.content_margin_left = 22
			frame.content_margin_right = 22
			frame.content_margin_top = 6
			frame.content_margin_bottom = 6
			var fp := PanelContainer.new()
			fp.add_theme_stylebox_override("panel", frame)
			fp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_theme_stylebox_override("background", StyleBoxEmpty.new())
			fp.add_child(b)
			col_box.add_child(fp)
		else:
			col_box.add_child(b)
	else:
		var cap_row := HBoxContainer.new()
		cap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap_row.add_child(cap)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap_row.add_child(gap)
		cap_row.add_child(val)
		col_box.add_child(b)
		col_box.add_child(cap_row)
	return [b, val]

## The crosshair: Ben's painted ones when present (a hand over things you can use, a
## pickaxe over things you can break, a sword over animals), else a drawn dot and ticks.
var _cross_mode := 0
func _draw_cross(cross: Control) -> void:
	if not Cursor.locked() and not Game.using_pad:
		return
	_draw_marker(cross)
	if player and player.gunplay and player.gunplay.held() != null:
		_draw_gun_cross(cross)
		return
	var tex := UITheme.crosshair(_cross_mode)
	if tex:
		var px := 30.0 if _cross_mode == 0 else 34.0
		cross.draw_texture_rect(tex, Rect2(Vector2(-px, -px) * 0.5 + Vector2(1, 1), Vector2(px, px)), false, Color(0, 0, 0, 0.5))
		cross.draw_texture_rect(tex, Rect2(Vector2(-px, -px) * 0.5, Vector2(px, px)), false, Color(1, 1, 1, 0.9))
		return
	cross.draw_circle(Vector2.ZERO, 3.5, Color(0, 0, 0, 0.35))
	cross.draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 1, 0.9))
	for a in 4:
		var d := Vector2.from_angle(a * PI * 0.5 + PI * 0.25)
		cross.draw_line(d * 7.0, d * 11.0, Color(0, 0, 0, 0.4), 3.0, true)
		cross.draw_line(d * 7.0, d * 11.0, Color(1, 1, 1, 0.55), 1.5, true)

## Hit marker: an X of four short slashes around the crosshair that pops out and fades
## when a blow or shot lands. White for a hit, red and wider for a headshot, and a
## bigger, bolder red X for a kill.
var _marker := ""
var _marker_t := 0.0
const MARKER_TIME := {"hit": 0.22, "head": 0.32, "kill": 0.5}

func _on_hit_marker(kind: String) -> void:
	# A kill or headshot isn't overwritten by the body-hit tick that may follow it.
	if _marker_t > 0.0 and MARKER_TIME.get(_marker, 0.0) > MARKER_TIME[kind]:
		return
	_marker = kind
	_marker_t = MARKER_TIME[kind]
	_cross.queue_redraw()

func _draw_marker(cross: Control) -> void:
	if _marker_t <= 0.0:
		return
	var f: float = _marker_t / float(MARKER_TIME[_marker]) # 1 fresh .. 0 gone
	var pop: float = 1.0 + 0.35 * f * f # opens outward and settles
	var col := Color(1, 1, 1) if _marker == "hit" else Color(1.0, 0.22, 0.18)
	var inner: float = (8.0 if _marker == "hit" else 9.0) * pop
	var outer: float = inner + (7.0 if _marker == "hit" else (10.0 if _marker == "head" else 13.0))
	var w: float = 2.0 if _marker == "hit" else (2.6 if _marker == "head" else 3.4)
	var a: float = clampf(f * 1.6, 0.0, 1.0)
	for i in 4:
		var d := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
		cross.draw_line(d * inner, d * outer, Color(0, 0, 0, 0.5 * a), w + 2.0, true)
		cross.draw_line(d * inner, d * outer, Color(col, a), w, true)

## With a gun or bow: four ticks spaced to the real spread of the next shot (they open
## up as you move or fire and close as you aim), a ring filling through a reload, and
## the rounds loaded and carried under it. Looking down the sights leaves only a dot.
func _draw_gun_cross(cross: Control) -> void:
	var g: Gunplay = player.gunplay
	var it = g.held()
	var cam := get_viewport().get_camera_3d()
	var half_h := get_viewport_rect().size.y * 0.5
	var fov := deg_to_rad(cam.fov if cam else 75.0)
	var gap := clampf(tan(deg_to_rad(g.spread_deg())) / tan(fov * 0.5) * half_h, 3.0, 160.0)
	var a := clampf(1.0 - g.ads * 1.4, 0.0, 1.0)
	var dim := Color(0, 0, 0, 0.45 * a)
	var lit := Color(1, 1, 1, 0.9 * a)
	if a > 0.0:
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			cross.draw_line(d * gap, d * (gap + 9.0), dim, 3.5, true)
			cross.draw_line(d * gap, d * (gap + 9.0), lit, 1.6, true)
	cross.draw_circle(Vector2.ZERO, 2.2, Color(0, 0, 0, 0.4))
	cross.draw_circle(Vector2.ZERO, 1.3, Color(1, 1, 1, 0.85))
	if g.reloading():
		cross.draw_arc(Vector2.ZERO, 22.0, 0, TAU, 40, Color(0, 0, 0, 0.35), 4.0, true)
		cross.draw_arc(Vector2.ZERO, 22.0, -PI * 0.5, -PI * 0.5 + TAU * g.reload_progress(), 40, UITheme.ACCENT, 2.5, true)
	var font := UITheme.font("title") if UITheme.font("title") else cross.get_theme_default_font()
	var loaded := g.rounds(it)
	var txt := "%d / %d" % [loaded, g.reserve(it)]
	var col := Color(1.0, 0.45, 0.35) if loaded == 0 else (UITheme.ACCENT if loaded * 4 <= g.mag_size(it["type"]) else Color(1, 1, 1, 0.85))
	var pos := Vector2(38, 46)
	cross.draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0, 0.7))
	cross.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	if loaded == 0 and not g.reloading():
		var hint := "[%s] Reload" % Player._key("reload") if g.reserve(it) > 0 else "No ammo"
		cross.draw_string(font, pos + Vector2(0, 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))

## Which crosshair fits what you are looking at.
func _update_cross() -> void:
	var mode := 0
	if not player.focus.is_empty():
		mode = 18
	elif _look.visible and _look_sub.text.begins_with("Wild animal"):
		mode = 20
	elif _look.visible and _look_hp.visible and not _look_sub.text.begins_with("Relic") and not _look_sub.text.begins_with("Wonder"):
		mode = 19
	if mode != _cross_mode:
		_cross_mode = mode
		_cross.queue_redraw()

## The round level badge: a gold ring that fills with progress to the next level.
func _draw_badge() -> void:
	var c := _badge.size * 0.5
	var st := Game.stats
	var f := clampf(float(st.xp) / maxf(1.0, Stats.xp_to_next(st.level)), 0.0, 1.0) if st.level < Stats.MAX_LEVEL else 1.0
	_badge.draw_circle(c, 30, Color(0, 0, 0, 0.75))
	_badge.draw_circle(c, 25, Color(0.12, 0.1, 0.07))
	_badge.draw_arc(c, 27.5, 0, TAU, 48, Color(1, 1, 1, 0.08), 4.0, true)
	_badge.draw_arc(c, 27.5, -PI * 0.5, -PI * 0.5 + TAU * f, 48, UITheme.ACCENT, 4.0, true)
	var font := UITheme.font("title") if UITheme.font("title") else _badge.get_theme_default_font()
	var txt := str(st.level)
	var sz := 26 if txt.length() < 3 else 20
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	_badge.draw_string(font, c + Vector2(-w.x * 0.5, sz * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, UITheme.ACCENT)
	if st.points > 0:
		_badge.draw_circle(c + Vector2(21, -21), 8, Color(0.1, 0.5, 0.6))
		_badge.draw_arc(c + Vector2(21, -21), 8, 0, TAU, 16, UITheme.ACCENT_2, 1.5, true)

## Bottom-centre hint for the mouse lock: "[Alt] Free mouse" while the mouse steers,
## a highlighted "Mouse free · [Alt] Lock" while the pointer is out.
func _build_mouse_hint() -> void:
	_mouse_hint = PanelContainer.new()
	_mouse_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_mouse_hint, Control.PRESET_CENTER_BOTTOM, Rect2(-150, -32, 300, 26))
	_mouse_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouse_key = UITheme.keycap("Alt", 12)
	_mouse_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_mouse_key)
	_mouse_text = UITheme.label("", 14, UITheme.DIM)
	h.add_child(_mouse_text)
	_mouse_hint.add_child(h)
	add_child(_mouse_hint)

func _update_mouse_hint() -> void:
	var hidden := player.ui_open or Game.using_pad
	var state := -1 if hidden else (0 if Cursor.locked() else 1)
	_mouse_hint.visible = not hidden
	_cross.queue_redraw()
	if state == _mouse_state:
		return
	_mouse_state = state
	(_mouse_key.get_child(0) as Label).text = Bindings.key_name("mouse_toggle")
	if state == 1:
		_mouse_text.text = "MOUSE FREE  ·  press to lock and look around"
		_mouse_text.add_theme_color_override("font_color", UITheme.ACCENT)
		_mouse_hint.add_theme_stylebox_override("panel", UITheme.sb(Color(0.2, 0.15, 0.06, 0.88), UITheme.ACCENT, 5, 1, 12))
	else:
		_mouse_text.text = "Free mouse"
		_mouse_text.add_theme_color_override("font_color", UITheme.DIM)
		_mouse_hint.add_theme_stylebox_override("panel", UITheme.sb(Color(0.03, 0.035, 0.04, 0.55), Color(1, 1, 1, 0.08), 5, 1, 10))
	_mouse_hint.reset_size()
	_mouse_hint.offset_left = -_mouse_hint.get_combined_minimum_size().x * 0.5
	_mouse_hint.offset_right = -_mouse_hint.offset_left

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

## A wonder found or its keeper slain: the big banner, in the wonder's colour.
func _on_discovered(title: String, sub: String, col: Color) -> void:
	_banner.text = title
	_banner_sub.text = sub.to_upper()
	_banner_sub.add_theme_color_override("font_color", col)
	_banner_box.modulate.a = 0.0
	var tw := _banner_box.create_tween()
	tw.tween_property(_banner_box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(5.0)
	tw.tween_property(_banner_box, "modulate:a", 0.0, 2.0)

func _on_region(region: String, era: int) -> void:
	_banner.text = region
	_banner_sub.text = "%s lands" % Eras.NAMES[era]
	_banner_sub.add_theme_color_override("font_color", UITheme.ERA_COLORS[era])
	var tw := _banner_box.create_tween()
	tw.tween_property(_banner_box, "modulate:a", 1.0, 1.2)
	tw.tween_interval(3.5)
	tw.tween_property(_banner_box, "modulate:a", 0.0, 2.0)

## Dark everywhere but two overlapping circles, softly edged, with a faint lens tint.
const BINO_SHADER := """shader_type canvas_item;
uniform float amount = 1.0;
void fragment() {
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * px / px.y;
	float r = 0.36;
	float d = min(length(p - vec2(-0.2, 0.0)), length(p - vec2(0.2, 0.0)));
	float inside = 1.0 - smoothstep(r - 0.02, r + 0.005, d);
	float rim = smoothstep(r - 0.12, r, d) * inside;
	COLOR = vec4(0.0, 0.0, 0.0, amount * mix(1.0, 0.45 * rim, inside));
}"""

func _update_buffs() -> void:
	var parts: PackedStringArray = []
	for id in Game.buffs:
		var b: Dictionary = Effects.BUFFS.get(id, {})
		if not b.is_empty() and not b.get("hidden", false):
			parts.append("%s %s" % [b["name"], Effects.clock(float(Game.buffs[id]))])
	_buffs.text = "   ".join(parts)
	_buffs.visible = not parts.is_empty()
	_buffs.add_theme_color_override("font_color", Color(0.95, 0.5, 0.45) if Game.has_buff("poison") else UITheme.ACCENT)

func _process(_d: float) -> void:
	if player == null:
		return
	_bino.visible = player._zoom > 0.75
	if _bino.visible:
		(_bino.material as ShaderMaterial).set_shader_parameter("amount", smoothstep(0.75, 1.0, player._zoom))
	_update_use_prompt(_d)
	var p := player.global_position
	var t := fposmod(Game.day, 1.0) * 24.0
	var heading := int(round(fposmod(-rad_to_deg(player.rotation.y), 360.0)))
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	_info.text = "Day %d  %02d:%02d\n%s  %d°\n%d, %d" % [int(Game.day) + 1, int(t), int(fmod(t, 1.0) * 60), dirs[int(round(heading / 45.0)) % 8], heading, int(p.x), int(p.z)]
	_compass.player = player
	_compass.heading = float(heading)
	_compass.queue_redraw()
	_update_mouse_hint()
	_update_cross()
	if _marker_t > 0.0:
		_marker_t = maxf(0.0, _marker_t - _d)
		_cross.queue_redraw()
	if player.gunplay and player.gunplay.held() != null:
		_cross.queue_redraw()
	_update_crime()
	_under.visible = player.underwater
	if _under.visible:
		var cam := player.camera.global_position
		var um := _under.material as ShaderMaterial
		um.set_shader_parameter("depth", Water.surface_height(cam.x, cam.z, fmod(Time.get_ticks_msec() / 1000.0, 3600.0)) - cam.y)
		um.set_shader_parameter("daylight", smoothstep(-0.12, 0.25, sin((fposmod(Game.day, 1.0) - 0.25) * TAU)))
		# Green in a silty pond, blue-green in the open sea.
		um.set_shader_parameter("tint", Color(0.35, 0.7, 0.75).lerp(Color(0.42, 0.62, 0.45), Water.turbidity(cam.x, cam.z)))
	_breath.max_value = Game.stats.max_breath()
	_marks.player = player
	_marks.queue_redraw()
	# Unspent attribute points glow slowly until spent.
	_pulse += _d
	_points.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * 2.6)) if Game.stats.points > 0 else 1.0
	_update_buffs()
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
	var jp = Jetpack.worn()
	_fuel.get_meta("row").visible = jp != null
	if jp != null:
		_fuel.max_value = float(jp.get("tank", Jetpack.TANK))
		_fuel.value = float(jp.get("fuel", 0.0))
		_fuel_val.text = "%d s  +%d canisters" % [int(ceilf(_fuel.value)), Jetpack.canisters(Game.inventory)]
	var show: bool = Settings.get_value("show_fps")
	if show != _fps.visible:
		# GPU timing costs a query per frame, so only measure while the counter is shown.
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), show)
	_fps.visible = show
	if _fps.visible:
		_fps.text = _perf_text()


## Your map markers and teleporters drawn where they are in the world, with distance.
class MarkerLayer extends Control:
	const RANGE := 3000.0
	var player: Player

	func _draw() -> void:
		if player == null or player.camera == null or not is_instance_valid(player.camera):
			return
		var cam := player.camera
		var font := get_theme_default_font()
		var me := player.global_position
		for mk in Game.markers.on_planet(Game.planet):
			var wp := Vector3(mk["x"], me.y + 2.0, mk["z"])
			var d := Vector2(wp.x - me.x, wp.z - me.z).length()
			if d > RANGE or d < 4.0 or cam.is_position_behind(wp):
				continue
			var p := cam.unproject_position(wp)
			p.y = clampf(p.y, 40.0, size.y * 0.55)
			if p.x < 0.0 or p.x > size.x:
				continue
			var c := Color(0.45, 0.9, 1.0) if mk["kind"] == "teleporter" else Markers.color_of(mk)
			var a := clampf(1.2 - d / RANGE, 0.45, 1.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(5, 0), p + Vector2(0, 7), p + Vector2(-5, 0)]), c * Color(1, 1, 1, a))
			var txt := "%s  %s" % [mk["name"], ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else "%d m" % int(d)]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string_outline(font, p + Vector2(-w * 0.5, -12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7 * a))
			draw_string(font, p + Vector2(-w * 0.5, -12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, a))

## Wanted stars (the worst town you are wanted in) and, while crouched, how close anyone
## is to noticing you.
func _update_crime() -> void:
	var w := Game.crime.worst(Game.day)
	_wanted.show_wanted(w)
	var m = player.npcs
	if not player.sneaking() or player.ui_open:
		_eye.text = ""
		return
	var det: float = m.detection if m else 0.0
	if m == null or not m.watched or det < 0.2:
		_eye.text = "( HIDDEN )"
		_eye.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85, 0.75))
	elif det < 0.5:
		_eye.text = "( CAUTION )"
		_eye.add_theme_color_override("font_color", Color(0.98, 0.78, 0.35))
	else:
		_eye.text = "( DETECTED )"
		_eye.add_theme_color_override("font_color", Color(1.0, 0.4, 0.32))

## FPS plus where the frame time goes: GPU render time and CPU render submission. If the
## GPU time is close to the frame time the GPU is the limit and graphics settings help.
func _perf_text() -> String:
	_perf_t -= get_process_delta_time()
	if _perf_t > 0.0 and _perf_cache != "":
		return _perf_cache
	_perf_t = 0.25
	var fps := Engine.get_frames_per_second()
	var vp := get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var frame := 1000.0 / maxf(1.0, fps)
	# The GPU works on one frame while the CPU prepares the next, so whichever is close
	# to the whole frame time is the limit.
	var tag := ""
	if gpu > 0.0:
		tag = "  GPU-bound" if gpu >= frame * 0.8 else "  CPU-bound"
	_perf_cache = "%d FPS  %.1f ms\nGPU %.1f ms  CPU render %.1f ms\n%d draw calls%s   (console: bench)" % [
		fps, frame, gpu, cpu, draws, tag]
	return _perf_cache


## A strip across the top: the eight directions and degree ticks slide past as you turn,
## with your markers and teleporters shown where they lie.
class Compass extends Control:
	const SPAN := 180.0 ## degrees visible across the strip
	var heading := 0.0
	var player: Player

	func _x(deg: float) -> float:
		var d := wrapf(deg - heading, -180.0, 180.0)
		return size.x * 0.5 + d / SPAN * size.x

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Backing band, fading out at both ends.
		var segs := 20
		for i in segs:
			var a := float(i) / segs
			var k := 1.0 - absf(a * 2.0 + 1.0 / segs - 1.0)
			draw_rect(Rect2(w * a, 6, w / segs + 1, h - 12), Color(0.02, 0.025, 0.03, 0.55 * minf(1.0, k * 2.0)))
		var font := UITheme.font("bold") if UITheme.font("bold") else get_theme_default_font()
		var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
		for deg in range(0, 360, 15):
			var x := _x(deg)
			if x < 0 or x > w:
				continue
			var fade := 1.0 - absf(x - w * 0.5) / (w * 0.5)
			if names.has(deg):
				var n: String = names[deg]
				var sz := 18 if n.length() == 1 else 14
				var col := UITheme.ACCENT if deg == 0 else UITheme.TEXT
				var sw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
				draw_string_outline(font, Vector2(x - sw * 0.5, h * 0.5 + sz * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 3, Color(0, 0, 0, 0.6 * fade))
				draw_string(font, Vector2(x - sw * 0.5, h * 0.5 + sz * 0.36), n, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col * Color(1, 1, 1, fade))
			else:
				draw_line(Vector2(x, h * 0.5 - 4), Vector2(x, h * 0.5 + 4), Color(1, 1, 1, 0.45 * fade), 1.5)
		# Markers.
		if player:
			var me := player.global_position
			for mk in Game.markers.on_planet(Game.planet):
				var dv := Vector2(mk["x"] - me.x, mk["z"] - me.z)
				if dv.length() < 4.0:
					continue
				var bearing := fposmod(rad_to_deg(atan2(dv.x, -dv.y)), 360.0)
				var x := _x(bearing)
				if x < 6 or x > w - 6:
					continue
				var c := Color(0.45, 0.9, 1.0) if mk["kind"] == "teleporter" else Markers.color_of(mk)
				var p := Vector2(x, h - 4)
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(4, 0), p + Vector2(0, 6), p + Vector2(-4, 0)]), c)
		# The centre notch.
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 6, 0), Vector2(w * 0.5 + 6, 0), Vector2(w * 0.5, 7)]), UITheme.ACCENT)

## "WANTED", five drawn stars (the fonts have no star glyph) and where and how much.
class WantedBar extends Control:
	var stars := 0
	var text := ""
	var _key := ""
	const RED := Color(0.98, 0.36, 0.3)

	func show_wanted(w: Dictionary) -> void:
		var k := str(w)
		if k == _key:
			return
		_key = k
		stars = int(w.get("stars", 0))
		text = "" if w.is_empty() else "%s  ·  %d Marks" % [w["name"], w["b"]]
		visible = stars > 0
		queue_redraw()

	func _draw() -> void:
		var f := get_theme_default_font()
		var fs := 17
		var head := "WANTED"
		var hw := f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var sw := 22.0
		var total := hw + 12.0 + sw * Crime.MAX_STARS + 12.0 + tw
		var x := (size.x - total) * 0.5
		var base := size.y * 0.5 + fs * 0.35
		draw_string_outline(f, Vector2(x, base), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(f, Vector2(x, base), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RED)
		x += hw + 12.0
		for i in Crime.MAX_STARS:
			_star(Vector2(x + sw * 0.5, size.y * 0.5), 9.0, i < stars)
			x += sw
		x += 12.0
		draw_string_outline(f, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(f, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.9, 0.85))

	func _star(c: Vector2, r: float, lit: bool) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		var outline := pts.duplicate()
		outline.append(pts[0])
		if lit:
			draw_colored_polygon(pts, Color(1.0, 0.8, 0.3))
		else:
			draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
		draw_polyline(outline, Color(0, 0, 0, 0.8) if lit else Color(1, 1, 1, 0.45), 1.5, true)
