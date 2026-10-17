class_name UITheme
## One shared look for every menu: dark glass panels, warm gold accent.

const ACCENT := Color(0.95, 0.78, 0.42)
const ACCENT_2 := Color(0.45, 0.85, 0.95)
const TEXT := Color(0.93, 0.92, 0.88)
const DIM := Color(0.62, 0.62, 0.62)
const ERA_COLORS := [Color(0.55, 0.75, 0.35), Color(0.45, 0.85, 0.85), Color(0.55, 0.7, 1.0)]

static var _theme: Theme

static func sb(bg: Color, border: Color = Color(1, 1, 1, 0.08), radius: int = 6, bw: int = 1, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s

## A slot frame in the item's rank colour; Uncommon and up glow, brighter by rank.
static func rarity_sb(it: Dictionary, bg: Color, bw := 2, pad := 6) -> StyleBoxFlat:
	var r := Rarity.of(it)
	var c := Rarity.color(it)
	var s := sb(bg.lerp(c * Color(0.35, 0.35, 0.35, 1.0), 0.12 * r), c * Color(1, 1, 1, 0.45 if r == 0 else 0.95), 6, bw if r > 0 else 1, pad)
	if r > 0:
		s.shadow_color = c * Color(1, 1, 1, 0.25 + 0.1 * r)
		s.shadow_size = 2 + r * 2
	return s

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_stylebox("normal", "Button", sb(Color(0.12, 0.13, 0.15, 0.85)))
	t.set_stylebox("hover", "Button", sb(Color(0.2, 0.19, 0.16, 0.95), ACCENT * Color(1, 1, 1, 0.7)))
	t.set_stylebox("pressed", "Button", sb(Color(0.25, 0.21, 0.13, 0.95), ACCENT))
	t.set_stylebox("disabled", "Button", sb(Color(0.1, 0.1, 0.1, 0.6)))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), ACCENT * Color(1, 1, 1, 0.5)))
	t.set_stylebox("panel", "PanelContainer", sb(Color(0.06, 0.07, 0.085, 0.88), Color(1, 1, 1, 0.1), 10, 1, 18))
	t.set_stylebox("panel", "Panel", sb(Color(0.06, 0.07, 0.085, 0.88), Color(1, 1, 1, 0.1), 10))
	t.set_stylebox("normal", "LineEdit", sb(Color(0.08, 0.09, 0.1, 0.9)))
	t.set_stylebox("focus", "LineEdit", sb(Color(0.08, 0.09, 0.1, 0.9), ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "OptionButton", sb(Color(0.12, 0.13, 0.15, 0.85)))
	t.set_stylebox("hover", "OptionButton", sb(Color(0.2, 0.19, 0.16, 0.95), ACCENT))
	t.set_stylebox("pressed", "OptionButton", sb(Color(0.2, 0.19, 0.16, 0.95), ACCENT))
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.08, 0.09, 0.1, 0.98)))
	t.set_stylebox("tab_selected", "TabContainer", sb(Color(0.2, 0.18, 0.13, 0.95), ACCENT, 6, 1, 14))
	t.set_stylebox("tab_unselected", "TabContainer", sb(Color(0.1, 0.1, 0.12, 0.8), Color(1, 1, 1, 0.05), 6, 1, 14))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color(0.16, 0.15, 0.13, 0.9), ACCENT * Color(1, 1, 1, 0.5), 6, 1, 14))
	t.set_stylebox("panel", "TabContainer", sb(Color(0.05, 0.06, 0.07, 0.6), Color(1, 1, 1, 0.06), 8, 1, 16))
	t.set_stylebox("background", "ProgressBar", sb(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.1), 4, 1, 0))
	t.set_stylebox("fill", "ProgressBar", sb(Color(0.75, 0.2, 0.18), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("slider", "HSlider", sb(Color(0.2, 0.2, 0.22), Color(0, 0, 0, 0), 3, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", sb(ACCENT * Color(1, 1, 1, 0.8), Color(0, 0, 0, 0), 3, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(ACCENT, Color(0, 0, 0, 0), 3, 0, 2))
	t.set_stylebox("panel", "TooltipPanel", sb(Color(0.05, 0.05, 0.06, 0.97), ACCENT * Color(1, 1, 1, 0.5)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	_theme = t
	return t

static func title(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l

static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

static func describe_item(it: Dictionary) -> String:
	var d := ItemDB.def(it["type"])
	var lines := [ItemDB.display_name(it)]
	var era: int = d.get("era", -1)
	if Rarity.is_gear(it["type"]):
		lines.append("%s %s %s" % [Rarity.NAMES[Rarity.of(it)], Eras.NAMES[era] if era >= 0 else "", d.get("kind", "item")])
		var st := ItemDB.stats(it)
		if st.has("damage"):
			lines.append("Damage %d" % int(round(float(st["damage"]) * it.get("quality", 1.0))))
		if st.has("armor"):
			lines.append("Armour %d" % int(round(float(st["armor"]) * it.get("quality", 1.0))))
		lines.append_array(Rarity.describe(it))
	else:
		lines.append("%s %s" % [Eras.NAMES[era] if era >= 0 else "Common", d.get("kind", "item")])
	lines.append("Quality %d%%   Value %d" % [int(it.get("quality", 1.0) * 100), int(d.get("value", 0) * (1.0 + 0.6 * Rarity.of(it) * Rarity.of(it)))])
	var srcs: Array = Inventory.sources_of(it) if Inventory.stacks(it) else [[it.get("origin", {}), it.get("qty", 1)]]
	for pair in srcs:
		var line := _origin_line(pair[0])
		if line != "":
			lines.append(line + (("  x%d" % pair[1]) if srcs.size() > 1 else ""))
	if it.has("uid") and not ItemDB.is_stackable(it["type"]):
		lines.append("#%d" % it["uid"])
	return "\n".join(lines)

static func _origin_line(o: Dictionary) -> String:
	if o.is_empty():
		return ""
	var how: String = o.get("how", "found")
	var where := ""
	if o.has("chunk") and Game.discovery.has("visited"):
		var c: Vector2i = o["chunk"]
		var v = Game.discovery["visited"].get("%d,%d" % [c.x, c.y])
		if v is Dictionary:
			where = " in %s" % v["region"]
	var when := " on day %d" % (int(o["day"]) + 1) if o.has("day") else ""
	return "%s%s%s" % [how.capitalize(), where, when]

## Gives keyboard/controller focus to the first enabled button inside a panel.
static func focus_first(root: Node) -> void:
	if not is_instance_valid(root):
		return
	for c in root.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return
