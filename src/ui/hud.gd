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
		v.add_child(key)
		v.add_child(n)
		v.add_child(q)
		p.add_child(v)
		_hotbar.add_child(p)
		_slots.append({"panel": p, "name": n, "qty": q})

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

	Game.toast.connect(_on_toast)
	Game.money_changed.connect(func(_m): _refresh())
	Game.health_changed.connect(func(_h): _refresh())
	Game.region_entered.connect(_on_region)
	Game.inventory.changed.connect(_refresh)
	_refresh()

func bind_player(p: Player) -> void:
	player = p
	p.look_target_changed.connect(func(t): _prompt.text = t)
	p.selected_changed.connect(func(_i): _refresh())
	_refresh()

func _refresh() -> void:
	for i in Inventory.HOTBAR:
		var it = Game.inventory.get_slot(i)
		var s: Dictionary = _slots[i]
		s["name"].text = ItemDB.display_name(it) if it != null else ""
		s["qty"].text = ("x%d" % it["qty"]) if it != null and ItemDB.is_stackable(it["type"]) else ""
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
	_fps.visible = Settings.get_value("show_fps")
	if _fps.visible:
		_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
