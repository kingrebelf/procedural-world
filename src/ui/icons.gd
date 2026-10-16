class_name Icons
## Procedurally drawn item icons (64x64), cached per item type. Used by the pickup feed,
## the hotbar, the inventory and the look-at panel.

const S := 64
static var _cache: Dictionary = {}

## Cell order of the painted icon sheet (6 columns x 5 rows) at SHEET_PATH. When the
## sheet exists its icons replace the procedural ones below.
const SHEET_PATH := "res://assets/icons/items.png"
const SHEET_COLS := 6
const SHEET_ORDER := [
	"wood", "glowroot", "circuitry", "stone", "iron_ore", "aether_crystal",
	"alloy_scrap", "planks", "iron_ingot", "mythril_ingot", "alloy_plate", "power_cell",
	"silver_chalice", "moonpearl", "data_core", "bread", "glowberry", "ration_pack",
	"pickaxe_iron", "pickaxe_mythril", "pickaxe_plasma", "axe_iron", "axe_mythril", "sword_iron",
	"sword_runic", "pulse_pistol", "gold_coin", "raw_meat", "hide", "cooked_meat",
]
const BUILD_DIR := "res://assets/icons/build/"
static var _sheet: Image
static var _sheet_checked := false

static func _from_sheet(type: String) -> Texture2D:
	if not _sheet_checked:
		_sheet_checked = true
		if ResourceLoader.exists(SHEET_PATH):
			var tex := load(SHEET_PATH) as Texture2D
			if tex:
				_sheet = tex.get_image()
	var idx := SHEET_ORDER.find(type)
	if _sheet == null or idx < 0:
		return null
	var rows := ceili(SHEET_ORDER.size() / float(SHEET_COLS))
	var cw := _sheet.get_width() / SHEET_COLS
	var ch := _sheet.get_height() / rows
	var cell := _sheet.get_region(Rect2i((idx % SHEET_COLS) * cw, (idx / SHEET_COLS) * ch, cw, ch))
	cell.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(cell)

static func get_icon(type: String) -> Texture2D:
	if _cache.has(type):
		return _cache[type]
	var painted := _from_sheet(type)
	if painted == null and ResourceLoader.exists(BUILD_DIR + type + ".png"):
		# Building pieces and stations: rendered from their models by tools/render_build_icons.gd.
		painted = load(BUILD_DIR + type + ".png")
	if painted:
		_cache[type] = painted
		return painted
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var d := ItemDB.def(type)
	var c: Color = d.get("color", Color(0.7, 0.7, 0.7))
	match type:
		"stone":
			_poly(img, [Vector2(14, 40), Vector2(20, 22), Vector2(36, 16), Vector2(50, 26), Vector2(52, 42), Vector2(38, 50), Vector2(22, 50)], c)
			_poly(img, [Vector2(24, 26), Vector2(36, 20), Vector2(44, 28), Vector2(30, 32)], c.lightened(0.25))
		"iron_ore", "alloy_scrap":
			_poly(img, [Vector2(12, 42), Vector2(18, 20), Vector2(38, 12), Vector2(54, 28), Vector2(48, 48), Vector2(26, 54)], Color(0.38, 0.36, 0.36))
			var fleck := c.lightened(0.2) if type == "iron_ore" else Color(0.85, 0.87, 0.9)
			for p in [Vector2(26, 28), Vector2(38, 36), Vector2(30, 44), Vector2(42, 22)]:
				_circle(img, p, 4.0, fleck)
		"wood", "glowroot":
			_rect(img, Rect2(10, 22, 40, 20), c)
			_circle(img, Vector2(50, 32), 10.0, c.lightened(0.3))
			_circle(img, Vector2(50, 32), 5.0, c.lightened(0.1))
			for x in [18, 28, 38]:
				_rect(img, Rect2(x, 24, 2, 16), c.darkened(0.25))
		"aether_crystal":
			_poly(img, [Vector2(32, 6), Vector2(48, 26), Vector2(40, 56), Vector2(24, 56), Vector2(16, 26)], c)
			_poly(img, [Vector2(32, 6), Vector2(40, 26), Vector2(32, 56), Vector2(24, 26)], c.lightened(0.35))
		"circuitry":
			_rect(img, Rect2(16, 16, 32, 32), Color(0.1, 0.35, 0.18))
			_rect(img, Rect2(24, 24, 16, 16), Color(0.15, 0.15, 0.17))
			for i in 4:
				_rect(img, Rect2(18 + i * 8, 10, 3, 6), Color(0.85, 0.75, 0.3))
				_rect(img, Rect2(18 + i * 8, 48, 3, 6), Color(0.85, 0.75, 0.3))
		"planks":
			for i in 3:
				_rect(img, Rect2(8, 16 + i * 11, 48, 9), c.darkened(i * 0.08))
		"iron_ingot", "mythril_ingot":
			_poly(img, [Vector2(10, 46), Vector2(18, 24), Vector2(46, 24), Vector2(54, 46)], c)
			_poly(img, [Vector2(18, 24), Vector2(46, 24), Vector2(42, 30), Vector2(22, 30)], c.lightened(0.3))
		"alloy_plate":
			_rect(img, Rect2(10, 14, 44, 36), c)
			for p in [Vector2(15, 19), Vector2(49, 19), Vector2(15, 45), Vector2(49, 45)]:
				_circle(img, p, 2.5, c.darkened(0.4))
		"power_cell":
			_rect(img, Rect2(20, 12, 24, 42), Color(0.2, 0.22, 0.25))
			_rect(img, Rect2(27, 7, 10, 6), Color(0.6, 0.6, 0.62))
			_rect(img, Rect2(24, 28, 16, 22), c)
		"bread":
			_ellipse(img, Vector2(32, 36), Vector2(24, 14), c)
			for x in [22, 32, 42]:
				_rect(img, Rect2(x, 28, 3, 8), c.darkened(0.3))
		"glowberry":
			for p in [Vector2(24, 38), Vector2(40, 38), Vector2(32, 26)]:
				_circle(img, p, 10.0, c)
				_circle(img, p + Vector2(-3, -3), 3.0, c.lightened(0.5))
		"ration_pack":
			_rect(img, Rect2(12, 18, 40, 30), c)
			_rect(img, Rect2(12, 28, 40, 6), c.darkened(0.35))
		"silver_chalice":
			_poly(img, [Vector2(16, 12), Vector2(48, 12), Vector2(40, 30), Vector2(24, 30)], c)
			_rect(img, Rect2(30, 30, 4, 14), c)
			_rect(img, Rect2(20, 44, 24, 6), c)
		"gold_coin":
			_circle(img, Vector2(32, 32), 18.0, Color(0.95, 0.75, 0.3))
			_circle(img, Vector2(32, 32), 12.0, Color(1.0, 0.85, 0.45))
		"raw_meat", "cooked_meat":
			_ellipse(img, Vector2(30, 34), Vector2(20, 14), c)
			_ellipse(img, Vector2(26, 31), Vector2(9, 6), c.lightened(0.25))
			_line(img, Vector2(46, 40), Vector2(56, 50), 5, Color(0.92, 0.9, 0.84))
		"hide":
			_poly(img, [Vector2(12, 16), Vector2(52, 14), Vector2(56, 34), Vector2(48, 52), Vector2(16, 50), Vector2(8, 32)], c)
			_poly(img, [Vector2(18, 22), Vector2(46, 20), Vector2(48, 30), Vector2(20, 32)], c.lightened(0.15))
		"hammer":
			_line(img, Vector2(18, 54), Vector2(40, 22), 6, Color(0.55, 0.38, 0.22))
			_line(img, Vector2(18, 54), Vector2(40, 22), 2, Color(0.66, 0.48, 0.3))
			_poly(img, [Vector2(28, 12), Vector2(50, 26), Vector2(44, 36), Vector2(22, 22)], Color(0.48, 0.5, 0.54))
			_poly(img, [Vector2(28, 12), Vector2(50, 26), Vector2(48, 29), Vector2(26, 15)], Color(0.7, 0.72, 0.76))
		"moonpearl", "data_core":
			_circle(img, Vector2(32, 32), 18.0, c)
			_circle(img, Vector2(26, 26), 6.0, c.lightened(0.6))
		_:
			var kind: String = d.get("kind", "")
			var metal := Color(0.75, 0.76, 0.8) if d.get("era", 0) != Eras.FANTASY else Color(0.6, 0.85, 1.0)
			if type.begins_with("pickaxe"):
				_line(img, Vector2(18, 54), Vector2(42, 18), 4, Color(0.45, 0.3, 0.18))
				_line(img, Vector2(22, 12), Vector2(56, 26), 5, metal)
			elif type.begins_with("axe"):
				_line(img, Vector2(18, 56), Vector2(40, 12), 4, Color(0.45, 0.3, 0.18))
				_poly(img, [Vector2(36, 10), Vector2(54, 14), Vector2(50, 32), Vector2(34, 22)], metal)
			elif type.begins_with("sword"):
				_line(img, Vector2(16, 48), Vector2(50, 14), 5, metal)
				_line(img, Vector2(12, 40), Vector2(24, 52), 4, Color(0.6, 0.45, 0.2))
				_line(img, Vector2(10, 54), Vector2(16, 48), 4, Color(0.4, 0.25, 0.15))
			elif type == "pulse_pistol":
				_rect(img, Rect2(12, 22, 38, 12), Color(0.3, 0.32, 0.36))
				_rect(img, Rect2(16, 34, 10, 18), Color(0.25, 0.26, 0.3))
				_rect(img, Rect2(34, 25, 14, 3), Color(0.3, 0.9, 1.0))
			elif kind == "food":
				_circle(img, Vector2(32, 32), 16.0, c)
			else:
				_circle(img, Vector2(32, 32), 16.0, c)
	_outline(img)
	var t := ImageTexture.create_from_image(img)
	_cache[type] = t
	return t

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)

static func _circle(img: Image, p: Vector2, r: float, c: Color) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			if Vector2(x, y).distance_to(p) <= r:
				_put(img, x, y, c)

static func _ellipse(img: Image, p: Vector2, r: Vector2, c: Color) -> void:
	for y in range(int(p.y - r.y), int(p.y + r.y) + 1):
		for x in range(int(p.x - r.x), int(p.x + r.x) + 1):
			var d := Vector2((x - p.x) / r.x, (y - p.y) / r.y)
			if d.length_squared() <= 1.0:
				_put(img, x, y, c)

static func _rect(img: Image, r: Rect2, c: Color) -> void:
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			_put(img, x, y, c)

static func _poly(img: Image, pts: Array, c: Color) -> void:
	var poly := PackedVector2Array(pts)
	var b := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		b = b.expand(p)
	for y in range(int(b.position.y), int(b.end.y) + 1):
		for x in range(int(b.position.x), int(b.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				_put(img, x, y, c)

static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n := int(a.distance_to(b))
	for i in n + 1:
		_circle(img, a.lerp(b, float(i) / maxf(n, 1)), w * 0.5, c)

## Dark outline around every opaque pixel so icons read on any background.
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < S and q.y < S and src.get_pixel(q.x, q.y).a > 0.0:
					img.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.9))
					break
