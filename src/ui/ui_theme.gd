class_name UITheme
## One shared look for every menu and the HUD: framed dark-steel panels with gold trim,
## bevelled buttons, inset item slots and glossy bars. The frames are painted into small
## nine-slice textures at startup (no image files), so the whole look lives in this file.
## Fonts: Cinzel for titles, Barlow Semi Condensed for everything else (both SIL OFL,
## assets/fonts).

const ACCENT := Color(0.96, 0.79, 0.45)
const ACCENT_2 := Color(0.45, 0.85, 0.95)
const TEXT := Color(0.93, 0.92, 0.88)
const DIM := Color(0.62, 0.63, 0.66)
const BAD := Color(0.95, 0.45, 0.38)
const ERA_COLORS := [Color(0.55, 0.75, 0.35), Color(0.45, 0.85, 0.85), Color(0.55, 0.7, 1.0)]
## Panel body colours, top and bottom of the gradient.
const PANEL_TOP := Color(0.095, 0.105, 0.125, 0.96)
const PANEL_BOTTOM := Color(0.035, 0.04, 0.05, 0.96)
const SLOT_BG := Color(0.035, 0.04, 0.048, 0.92)

static var _theme: Theme
static var _tex: Dictionary = {}
static var _fonts: Dictionary = {}

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

# --- Fonts ------------------------------------------------------------------------

static func font(which: String) -> Font:
	if _fonts.has(which):
		return _fonts[which]
	var f: Font = null
	match which:
		"title":
			var base = _load_font("res://assets/fonts/Cinzel.ttf")
			if base:
				var v := FontVariation.new()
				v.base_font = base
				v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
				f = v
		"body": f = _load_font("res://assets/fonts/BarlowSemiCondensed-Medium.ttf")
		"bold": f = _load_font("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
	_fonts[which] = f
	return f

static func _load_font(path: String) -> Font:
	return load(path) as Font if ResourceLoader.exists(path) else null

# --- Painted frames -----------------------------------------------------------------

## Signed distance (negative inside) from p to a rounded rectangle of size sz.
static func _rr(p: Vector2, sz: Vector2, r: float) -> float:
	var q := (p - sz * 0.5).abs() - (sz * 0.5 - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r

static func _blend(under: Color, over: Color) -> Color:
	var a := over.a + under.a * (1.0 - over.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var c := (Color(over.r, over.g, over.b) * over.a + Color(under.r, under.g, under.b) * under.a * (1.0 - over.a)) / a
	return Color(c.r, c.g, c.b, a)

## Paints a framed box. look: "panel", "button", "hover", "pressed", "disabled", "slot",
## "slot_hover", "slot_sel", "bar_bg", "tab", "tab_on", "keycap".
static func _paint(look: String, n: int, radius: float) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var sz := Vector2(n, n)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := -_rr(p, sz, radius) ## depth inside the edge, in pixels
			if d <= -0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var cov := clampf(d + 0.5, 0.0, 1.0)
			var t := float(y) / (n - 1)
			var c: Color
			match look:
				"panel":
					c = PANEL_TOP.lerp(PANEL_BOTTOM, smoothstep(0.0, 1.0, t))
					c = _blend(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.05 * (1.0 - smoothstep(0.0, 0.35, t))))
					if d < 1.0: c = Color(0, 0, 0, 0.9)
					elif d < 2.0: c = _blend(c, Color(1, 1, 1, 0.09))
					elif d >= 4.0 and d < 5.0:
						# Inner gold line, brightest at the corners like a bracket.
						var corner := minf(minf(x, n - 1 - x), minf(y, n - 1 - y)) < 2 or (minf(x, n - 1 - x) < 16 and minf(y, n - 1 - y) < 16)
						c = _blend(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85 if corner else 0.22))
				"button", "hover", "pressed", "disabled", "tab", "tab_on":
					var top := Color(0.2, 0.21, 0.23, 0.95)
					var bot := Color(0.1, 0.105, 0.115, 0.95)
					var edge := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28)
					match look:
						"hover", "tab_on":
							top = Color(0.33, 0.27, 0.16, 0.97)
							bot = Color(0.16, 0.13, 0.08, 0.97)
							edge = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95)
						"pressed":
							top = Color(0.1, 0.08, 0.05, 0.97)
							bot = Color(0.24, 0.19, 0.11, 0.97)
							edge = ACCENT
						"disabled":
							top = Color(0.1, 0.1, 0.11, 0.7)
							bot = Color(0.07, 0.07, 0.08, 0.7)
							edge = Color(1, 1, 1, 0.06)
						"tab":
							top = Color(0.13, 0.14, 0.16, 0.9)
							bot = Color(0.07, 0.075, 0.085, 0.9)
							edge = Color(1, 1, 1, 0.1)
					c = top.lerp(bot, t)
					if d < 1.0: c = Color(0, 0, 0, 0.85)
					elif d < 2.0: c = edge
					elif d < 3.0 and y < n / 2 and look != "pressed": c = _blend(c, Color(1, 1, 1, 0.1))
				"slot", "slot_hover", "slot_sel":
					c = SLOT_BG
					# Inset: shadow falls from the top edge, the floor glows faintly.
					c = _blend(c, Color(0, 0, 0, 0.45 * (1.0 - smoothstep(0.0, 10.0, d)) * (1.2 - t)))
					var g := 1.0 - (p - sz * 0.5).length() / (n * 0.7)
					c = _blend(c, Color(0.5, 0.6, 0.75, 0.06 * maxf(g, 0.0)))
					var edge := Color(1, 1, 1, 0.13)
					if look == "slot_hover": edge = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7)
					if look == "slot_sel": edge = ACCENT
					if d < 1.0: c = Color(0, 0, 0, 0.8)
					elif d < (3.0 if look == "slot_sel" else 2.0): c = edge
					elif look == "slot_sel" and d < 7.0:
						c = _blend(c, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22 * (1.0 - (d - 3.0) / 4.0)))
				"bar_bg":
					c = Color(0.02, 0.022, 0.026, 0.85)
					c = _blend(c, Color(0, 0, 0, 0.5 * (1.0 - t)))
					if d < 1.0: c = Color(0, 0, 0, 0.9)
					elif d < 2.0: c = Color(1, 1, 1, 0.1)
				"keycap":
					c = Color(0.93, 0.9, 0.82).lerp(Color(0.7, 0.67, 0.6), t)
					if d < 1.0: c = Color(0.15, 0.13, 0.1, 0.9)
					elif d > 2.0 and y > n - 5: c = c.darkened(0.25)
			c.a *= cov
			img.set_pixel(x, y, c)
	return img

# --- Ben's painted kit (assets/ui, made by tools/prepare_ui_kit.py) ---------------

## look -> [file, nine-slice margins l t r b, minimum content margins l/r and t/b, tint]
const KIT := {
	"panel": ["ui_panel", [42, 40, 42, 40], [28, 24], Color.WHITE],
	"button": ["ui_button", [24, 12, 24, 12], [26, 6], Color.WHITE],
	"hover": ["ui_button_hover", [26, 12, 26, 12], [26, 6], Color.WHITE],
	"tab_on": ["ui_button_hover", [26, 12, 26, 12], [26, 6], Color.WHITE],
	"pressed": ["ui_button_hover", [26, 12, 26, 12], [26, 6], Color(0.8, 0.75, 0.65)],
	"tab": ["ui_button", [24, 12, 24, 12], [26, 6], Color(0.75, 0.75, 0.75)],
	"disabled": ["ui_button", [24, 12, 24, 12], [26, 6], Color(0.55, 0.55, 0.55, 0.75)],
	"slot": ["ui_slot", [11, 11, 11, 11], [6, 6], Color.WHITE],
	"slot_hover": ["ui_slot", [11, 11, 11, 11], [6, 6], Color(1.45, 1.3, 1.1)],
	"slot_sel": ["ui_slot_selected", [13, 13, 13, 13], [6, 6], Color.WHITE],
	"tooltip": ["ui_tooltip", [12, 12, 12, 12], [14, 10], Color.WHITE],
	"bar_frame": ["ui_bar_frame", [32, 8, 32, 8], [30, 7], Color.WHITE],
}
static var _kit_tex: Dictionary = {}

static func kit_texture(file: String) -> Texture2D:
	if not _kit_tex.has(file):
		var path := "res://assets/ui/%s.png" % file
		_kit_tex[file] = load(path) if ResourceLoader.exists(path) else null
	return _kit_tex[file]

## The painted kit's style for a look, or null when the kit isn't there.
static func kit_sb(look: String, pad := 10, pad_v := -1) -> StyleBoxTexture:
	if not KIT.has(look):
		return null
	var k: Array = KIT[look]
	var t := kit_texture(k[0])
	if t == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = t
	s.texture_margin_left = k[1][0]
	s.texture_margin_top = k[1][1]
	s.texture_margin_right = k[1][2]
	s.texture_margin_bottom = k[1][3]
	s.content_margin_left = maxf(pad, k[2][0])
	s.content_margin_right = maxf(pad, k[2][0])
	var pv := pad * 0.6 if pad_v < 0 else float(pad_v)
	s.content_margin_top = maxf(pv, k[2][1])
	s.content_margin_bottom = maxf(pv, k[2][1])
	s.modulate_color = k[3]
	return s

## One cell of the HUD status icon sheet: health, stamina, hunger, thirst, warmth, cold,
## poison, bleeding, burning, well_fed, rested, sick, strength, defence, speed, stealth,
## luck, xp, day, night, rain, storm, snow, fog, gold, reputation, trade, friendship,
## hostile, quest.
const STATUS := ["health", "stamina", "hunger", "thirst", "warmth", "cold", "poison", "bleeding", "burning", "well_fed", "rested", "sick",
	"strength", "defence", "speed", "stealth", "luck", "xp", "day", "night", "rain", "storm", "snow", "fog",
	"gold", "reputation", "trade", "friendship", "hostile", "quest"]

static func status_icon(name: String) -> Texture2D:
	return _cell("status_icons", STATUS.find(name))

## One of the 30 crosshairs (6 x 5, row by row). 18 hand, 19 pickaxe, 20 sword.
static func crosshair(i: int) -> Texture2D:
	return _cell("crosshairs", i)

static func _cell(sheet: String, i: int) -> Texture2D:
	var key := "%s_%d" % [sheet, i]
	if not _tex.has(key):
		var t := kit_texture(sheet)
		if t == null or i < 0:
			_tex[key] = null
		else:
			var a := AtlasTexture.new()
			a.atlas = t
			var cw := t.get_width() / 6.0
			var ch := t.get_height() / 5.0
			a.region = Rect2((i % 6) * cw, (i / 6) * ch, cw, ch)
			_tex[key] = a
	return _tex[key]

## A nine-slice style of one of the looks: Ben's painted kit where it has one, else the
## frame painted here. painted forces the code-drawn frame (for small buttons the kit's
## pointed ends would crowd).
static func tex_sb(look: String, pad := 10, pad_v := -1, painted := false) -> StyleBoxTexture:
	if not painted:
		var k := kit_sb(look, pad, pad_v)
		if k:
			return k
	var key := look
	if not _tex.has(key):
		var n := 48
		var r := 6.0
		match look:
			"panel": n = 64; r = 7.0
			"slot", "slot_hover", "slot_sel": n = 48; r = 5.0
			"bar_bg": n = 16; r = 3.0
			"keycap": n = 24; r = 4.0
		_tex[key] = ImageTexture.create_from_image(_paint(look, n, r))
	var t: ImageTexture = _tex[key]
	var s := StyleBoxTexture.new()
	s.texture = t
	var m := 16.0 if look == "panel" else (5.0 if look == "bar_bg" or look == "keycap" else 9.0)
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6 if pad_v < 0 else pad_v
	s.content_margin_bottom = pad * 0.6 if pad_v < 0 else pad_v
	return s

## The glossy fill of a bar in the given colour.
static func bar_fill(col: Color) -> StyleBoxTexture:
	var key := "fill_" + col.to_html()
	if not _tex.has(key):
		var h := 16
		var img := Image.create(8, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var t := float(y) / (h - 1)
			var c := col.lightened(0.35).lerp(col, smoothstep(0.0, 0.45, t)).lerp(col.darkened(0.35), smoothstep(0.5, 1.0, t))
			if y == 1:
				c = c.lightened(0.4)
			for x in 8:
				img.set_pixel(x, y, c)
		_tex[key] = ImageTexture.create_from_image(img)
	var s := StyleBoxTexture.new()
	s.texture = _tex[key]
	s.texture_margin_top = 3
	s.texture_margin_bottom = 3
	s.texture_margin_left = 2
	s.texture_margin_right = 2
	return s

## A slot frame in the item's rank colour; Uncommon and up glow, brighter by rank.
static func rarity_sb(it: Dictionary, bg: Color = SLOT_BG, bw := 2, pad := 6) -> StyleBox:
	var r := Rarity.of(it)
	if r == 0:
		return tex_sb("slot", pad)
	var c := Rarity.color(it)
	var s := sb(bg.lerp(c * Color(0.3, 0.3, 0.3, 1.0), 0.1 + 0.05 * r), c * Color(1, 1, 1, 0.95), 5, bw, pad)
	s.shadow_color = c * Color(1, 1, 1, 0.22 + 0.08 * r)
	s.shadow_size = 2 + r * 2
	return s

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	if font("body"):
		t.default_font = font("body")
	t.default_font_size = 19
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("shadow_offset_x", "Label", 0)
	if font("bold"):
		t.set_font("font", "Button", font("bold"))
		t.set_font("font", "OptionButton", font("bold"))
		t.set_font("font", "TabContainer", font("bold"))
	for ty in ["Button", "OptionButton"]:
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color(1.0, 0.92, 0.72))
		t.set_color("font_pressed_color", ty, ACCENT)
		t.set_color("font_hover_pressed_color", ty, ACCENT)
		t.set_color("font_focus_color", ty, Color(1.0, 0.92, 0.72))
		t.set_color("font_disabled_color", ty, Color(0.45, 0.45, 0.47))
		t.set_stylebox("normal", ty, tex_sb("button", 14, 7))
		t.set_stylebox("hover", ty, tex_sb("hover", 14, 7))
		t.set_stylebox("pressed", ty, tex_sb("pressed", 14, 7))
		t.set_stylebox("hover_pressed", ty, tex_sb("pressed", 14, 7))
		t.set_stylebox("disabled", ty, tex_sb("disabled", 14, 7))
		t.set_stylebox("focus", ty, sb(Color(0, 0, 0, 0), ACCENT * Color(1, 1, 1, 0.75), 6, 2))
	t.set_stylebox("panel", "PanelContainer", tex_sb("panel", 22, 18))
	t.set_stylebox("panel", "Panel", tex_sb("panel", 22, 18))
	t.set_stylebox("normal", "LineEdit", tex_sb("bar_bg", 10, 8))
	t.set_stylebox("focus", "LineEdit", sb(Color(0, 0, 0, 0), ACCENT, 4, 1))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PopupMenu", tex_sb("panel", 10, 8, true))
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("hover", "PopupMenu", sb(Color(0.3, 0.24, 0.13, 0.9), Color(0, 0, 0, 0), 4, 0))
	t.set_stylebox("tab_selected", "TabContainer", tex_sb("tab_on", 18, 8))
	t.set_stylebox("tab_unselected", "TabContainer", tex_sb("tab", 18, 8))
	t.set_stylebox("tab_hovered", "TabContainer", tex_sb("hover", 18, 8))
	t.set_stylebox("panel", "TabContainer", sb(Color(0.02, 0.025, 0.03, 0.55), Color(1, 1, 1, 0.06), 6, 1, 16))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_stylebox("background", "ProgressBar", tex_sb("bar_bg", 0, 0))
	t.set_stylebox("fill", "ProgressBar", bar_fill(Color(0.75, 0.2, 0.18)))
	t.set_stylebox("slider", "HSlider", tex_sb("bar_bg", 0, 3))
	t.set_stylebox("grabber_area", "HSlider", bar_fill(ACCENT.darkened(0.15)))
	t.set_stylebox("grabber_area_highlight", "HSlider", bar_fill(ACCENT))
	for sbar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbar, sb(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 4, 0, 3))
		t.set_stylebox("grabber", sbar, sb(ACCENT * Color(0.7, 0.7, 0.7, 0.6), Color(0, 0, 0, 0), 4, 0, 3))
		t.set_stylebox("grabber_highlight", sbar, sb(ACCENT * Color(1, 1, 1, 0.85), Color(0, 0, 0, 0), 4, 0, 3))
		t.set_stylebox("grabber_pressed", sbar, sb(ACCENT, Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("panel", "TooltipPanel", kit_sb("tooltip") if kit_sb("tooltip") else tex_sb("panel", 14, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", ACCENT)
	t.set_stylebox("separator", "HSeparator", sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 0, 0))
	_theme = t
	return t

static func title(text: String, size: int = 30) -> Label:
	var l := Label.new()
	l.text = text
	if font("title"):
		l.add_theme_font_override("font", font("title"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color(0.18, 0.11, 0.03, 0.6))
	return l

## A small gold caption in capitals, for section headings inside a panel.
static func heading(text: String, size: int = 14) -> Label:
	var l := label(text.to_upper(), size, ACCENT)
	if font("bold"):
		l.add_theme_font_override("font", font("bold"))
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

## A tall main-menu button.
static func big_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 22)
	return b

## A keyboard key drawn as a little cap: "[Tab]".
static func keycap(text: String, size := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", tex_sb("keycap", 6, 1, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, Color(0.1, 0.09, 0.08))
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	if font("bold"):
		l.add_theme_font_override("font", font("bold"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(maxi(12, size), 0)
	p.add_child(l)
	return p

## An ornamental rule: a gold line fading out at both ends with a diamond in the middle.
static func divider(width := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 12)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var w := c.size.x
		var y := c.size.y * 0.5
		var segs := 24
		for i in segs:
			var a := float(i) / segs
			var b := float(i + 1) / segs
			var k := 1.0 - absf((a + b) - 1.0)
			c.draw_line(Vector2(w * a, y), Vector2(w * b, y), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55 * k), 1.0)
		var m := Vector2(w * 0.5, y)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -4), m + Vector2(5, 0), m + Vector2(0, 4), m + Vector2(-5, 0)]), ACCENT)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(-14, 0), m + Vector2(-10, -2), m + Vector2(-8, 0), m + Vector2(-10, 2)]), ACCENT * Color(1, 1, 1, 0.6))
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(14, 0), m + Vector2(10, -2), m + Vector2(8, 0), m + Vector2(10, 2)]), ACCENT * Color(1, 1, 1, 0.6)))
	return c

## A small item icon as a TextureRect.
static func icon_rect(type: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Icons.get_icon(type)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## "[coin] 293": money with the coin icon.
static func money_tag(amount: int, size := 22) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := icon_rect("gold_coin", size + 6)
	if status_icon("gold"):
		coin.texture = status_icon("gold")
	h.add_child(coin)
	var l := label("%d" % amount, size, ACCENT)
	if font("bold"):
		l.add_theme_font_override("font", font("bold"))
	h.add_child(l)
	h.tooltip_text = "Marks"
	return h

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
	lines.append_array(Effects.describe(d))
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

## Gives keyboard/controller focus to the first enabled button inside a panel (or the
## control marked with the "pad_first" meta, when a panel wants another start), else the
## first control that takes focus at all (a slider, a text box).
static func focus_first(root: Node) -> void:
	if not is_instance_valid(root):
		return
	var all := root.find_children("*", "Control", true, false)
	var ok := func(c: Control) -> bool:
		return c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and not (c is BaseButton and (c as BaseButton).disabled)
	for c in all:
		if c.has_meta("pad_first") and ok.call(c):
			c.grab_focus()
			return
	for c in all:
		if c is BaseButton and ok.call(c):
			c.grab_focus()
			return
	for c in all:
		if ok.call(c):
			c.grab_focus()
			return

## True when focus sits on a control inside `root`.
static func has_focus_in(root: Control) -> bool:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return false
	var f := root.get_viewport().gui_get_focus_owner()
	return f != null and (f == root or root.is_ancestor_of(f))

# --- Controller prompts ---------------------------------------------------------------

## True when the first controller is a PlayStation pad (its face buttons are shapes).
static func pad_is_sony() -> bool:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return false
	var n := Input.get_joy_name(pads[0]).to_lower()
	return n.contains("ps3") or n.contains("ps4") or n.contains("ps5") or n.contains("dualshock") or n.contains("dualsense") \
		or n.contains("sony") or n.contains("playstation")

const PAD_FACE := {JOY_BUTTON_A: ["A", Color(0.42, 0.8, 0.3)], JOY_BUTTON_B: ["B", Color(0.92, 0.32, 0.27)],
	JOY_BUTTON_X: ["X", Color(0.3, 0.55, 0.95)], JOY_BUTTON_Y: ["Y", Color(0.96, 0.78, 0.25)]}
const SONY_FACE := {JOY_BUTTON_A: Color(0.5, 0.65, 0.95), JOY_BUTTON_B: Color(0.95, 0.4, 0.42),
	JOY_BUTTON_X: Color(0.9, 0.55, 0.8), JOY_BUTTON_Y: Color(0.35, 0.8, 0.65)}
## Prompt names for the other buttons: [Xbox, PlayStation]. "lt"/"rt" are the triggers,
## "rs" the right stick, "ls" the left stick, "dpad" the D-pad.
const PAD_NAMES := {JOY_BUTTON_LEFT_SHOULDER: ["LB", "L1"], JOY_BUTTON_RIGHT_SHOULDER: ["RB", "R1"],
	JOY_BUTTON_START: ["Menu", "Options"], JOY_BUTTON_BACK: ["View", "Share"], "lt": ["LT", "L2"], "rt": ["RT", "R2"],
	"rs": ["RS", "R"], "ls": ["LS", "L"], "dpad": ["D-pad", "D-pad"]}

## One controller button drawn as on the pad: a coloured letter in a dark disc for the
## face buttons (shapes on a PlayStation pad), a small cap with its name for the rest.
static func pad_glyph(btn, size := 24) -> Control:
	if btn is int and PAD_FACE.has(btn):
		var c := Control.new()
		c.custom_minimum_size = Vector2(size, size)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sony := pad_is_sony()
		c.draw.connect(func():
			var r := size * 0.5
			var mid := Vector2(r, r)
			c.draw_circle(mid, r, Color(0.07, 0.075, 0.085, 0.95))
			c.draw_arc(mid, r - 1.0, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 1.5, true)
			if not sony:
				var f := font("bold") if font("bold") else ThemeDB.fallback_font
				var fs := int(size * 0.62)
				var t: String = PAD_FACE[btn][0]
				var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				c.draw_string(f, Vector2(r - w.x * 0.5, r + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PAD_FACE[btn][1])
				return
			var col: Color = SONY_FACE[btn]
			var k := r * 0.42
			if btn == JOY_BUTTON_A:
				c.draw_line(mid + Vector2(-k, -k), mid + Vector2(k, k), col, 2.0, true)
				c.draw_line(mid + Vector2(k, -k), mid + Vector2(-k, k), col, 2.0, true)
			elif btn == JOY_BUTTON_B:
				c.draw_arc(mid, k * 1.1, 0.0, TAU, 24, col, 2.0, true)
			elif btn == JOY_BUTTON_X:
				c.draw_rect(Rect2(mid - Vector2(k, k), Vector2(k, k) * 2.0), col, false, 2.0)
			else:
				c.draw_polyline(PackedVector2Array([mid + Vector2(0, -k * 1.15), mid + Vector2(k * 1.1, k * 0.8),
					mid + Vector2(-k * 1.1, k * 0.8), mid + Vector2(0, -k * 1.15)]), col, 2.0, true))
		return c
	var names: Array = PAD_NAMES.get(btn, [str(btn), str(btn)])
	return keycap(names[1] if pad_is_sony() else names[0], int(size * 0.5))

## A row of controller prompts, [[button or [buttons], "what it does"], ...], shown only
## while the controller is in use (it hides itself for the mouse and keyboard).
static func pad_hints(pairs: Array, size := 24) -> PadHints:
	var row := PadHints.new()
	row.set_hints(pairs, size)
	return row

class PadHints extends HBoxContainer:
	func _init() -> void:
		add_theme_constant_override("separation", 18)
		alignment = BoxContainer.ALIGNMENT_END
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = Game.using_pad

	func set_hints(pairs: Array, size := 24) -> void:
		for ch in get_children():
			ch.queue_free()
		for pr in pairs:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			for b in (pr[0] if pr[0] is Array else [pr[0]]):
				var g := UITheme.pad_glyph(b, size)
				g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(g)
			var l := UITheme.label(pr[1], 15, UITheme.TEXT)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(l)
			add_child(h)

	func _process(_d: float) -> void:
		visible = Game.using_pad
