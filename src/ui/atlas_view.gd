class_name AtlasView
extends Control
## The atlas: the whole painted map under its fog of war. Drag to pan, scroll to zoom
## (towards the cursor), click to drop a marker, right-click a marker to remove it, and
## hover a place to see what it is and how far.

signal changed

var player: Node3D
var _canvas: MapCanvas
var _icons: Control
static var _pan := Vector2.ZERO ## world offset from the player (kept while the atlas rebuilds)
static var _ppm := 0.5 ## pixels per metre
var _drag := false
var _dragged := 0.0
var _hover := Vector2(-1, -1)
var _t := 0.0

const MIN_PPM := 0.06
const MAX_PPM := 4.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas = MapCanvas.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_icons = Control.new()
	_icons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.draw.connect(_draw_icons)
	add_child(_icons)

func _me() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z) if player and is_instance_valid(player) else Vector2.ZERO

func recentre() -> void:
	_pan = Vector2.ZERO

func zoom_by(f: float, at := Vector2(-1, -1)) -> void:
	if at.x < 0.0:
		at = size * 0.5
	var before := _canvas.to_world(at)
	_ppm = clampf(_ppm * f, MIN_PPM, MAX_PPM)
	_canvas.scale_ppm = _ppm
	# Keep the point under the cursor where it was.
	_pan += before - _canvas.to_world(at)

func _process(delta: float) -> void:
	_t += delta
	_canvas.center = _me() + _pan
	_canvas.scale_ppm = _ppm
	_canvas.refresh()
	_icons.queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag = true
				_dragged = 0.0
			else:
				_drag = false
				if _dragged < 5.0:
					# A click, not a drag: drop a marker there.
					var w := _canvas.to_world(e.position)
					Game.markers.add("Marker %d" % (Game.markers.count_kind("pin") + 1), w.x, w.y, Game.planet)
					Game.touch_player()
					changed.emit()
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			for mk in Game.markers.on_planet(Game.planet, "pin"):
				if _canvas.to_local_px(mk["x"], mk["z"]).distance_to(e.position) < 10.0:
					Game.markers.remove(mk["id"])
					Game.touch_player()
					changed.emit()
					break
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.2, e.position)
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.2, e.position)
			accept_event()
	elif e is InputEventMouseMotion:
		_hover = e.position
		if _drag:
			_dragged += e.relative.length()
			_pan -= e.relative / _ppm

## Everything drawn over the map, as [kind, screen point, label, payload].
func _things() -> Array:
	var out: Array = []
	var a := _canvas.to_world(Vector2.ZERO) - Vector2(40, 40) / _ppm
	var b := _canvas.to_world(size) + Vector2(40, 40) / _ppm
	var big := _ppm > 0.18
	for key in Game.map.pois:
		for poi in Game.map.pois[key]:
			var x: float = poi["x"]
			var z: float = poi["z"]
			if x < a.x or z < a.y or x > b.x or z > b.y or Game.map.revealed(x, z) < 0.45:
				continue
			if not big and poi["k"] != "town" and poi["k"] != "fort":
				continue
			out.append([poi["k"], _canvas.to_local_px(x, z), poi["name"], poi])
	for key in Game.map.wonders:
		var w: Dictionary = Game.map.wonders[key]
		out.append(["wonder", _canvas.to_local_px(w["x"], w["z"]), WonderSite.label(w["t"]) if w.get("found", false) else "Something powerful", w])
	for mk in Game.markers.on_planet(Game.planet):
		out.append(["marker", _canvas.to_local_px(mk["x"], mk["z"]), mk["name"], mk])
	return out

func _draw_icons() -> void:
	var font := get_theme_default_font()
	var things := _things()
	var near: Array = []
	var nd := 14.0
	for th in things:
		var p: Vector2 = th[1]
		match String(th[0]):
			"wonder":
				MapCanvas.draw_wonder(_icons, th[3], p, 9.0, _t)
			"marker":
				var mk: Dictionary = th[3]
				var c := Color(0.45, 0.9, 1.0) if mk["kind"] == "teleporter" else Markers.color_of(mk)
				if mk["kind"] == "teleporter":
					_icons.draw_circle(p, 7.0, Color(0, 0, 0, 0.6))
					_icons.draw_arc(p, 6.0, 0.0, TAU, 16, c, 2.0)
				else:
					_icons.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(6, 0), p + Vector2(0, 9), p + Vector2(-6, 0)]), Color(0, 0, 0, 0.7))
					_icons.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(5, 0), p + Vector2(0, 8), p + Vector2(-5, 0)]), c)
				_label(font, p + Vector2(10, 5), th[2], 13, Color(1, 1, 1, 0.9))
			_:
				var s := 6.0 if th[0] != "town" else 5.0 + float(th[3].get("size", 0)) * 1.5
				MapCanvas.draw_poi(_icons, th[0], p, s, MapCanvas.POI_COLORS.get(th[0], Color.WHITE))
				if th[0] == "town" and _ppm > 0.1:
					_label(font, p + Vector2(10, 5), th[2], 13 + int(th[3].get("size", 0)), Color(1, 0.96, 0.86, 0.95))
		if p.distance_to(_hover) < nd:
			nd = p.distance_to(_hover)
			near = th
	var me := _me()
	var at := _canvas.to_local_px(me.x, me.y)
	if player and is_instance_valid(player):
		var f := -player.global_transform.basis.z
		MapCanvas.draw_player(_icons, at, Vector2(f.x, f.z), 10.0)
	# Hover: what it is and how far.
	if not near.is_empty():
		var wp := _canvas.to_world(near[1])
		var txt := "%s  ·  %s" % [near[2], _dist(wp.distance_to(me))]
		_tooltip(font, near[1] + Vector2(14, -14), txt)
	elif _hover.x >= 0.0 and Rect2(Vector2.ZERO, size).has_point(_hover):
		var wp := _canvas.to_world(_hover)
		if Game.map.revealed(wp.x, wp.y) < 0.3:
			_tooltip(font, _hover + Vector2(14, -14), "Unexplored")
	_scale_bar(font)
	_label(font, Vector2(12, size.y - 12), "Drag to pan   ·   scroll to zoom   ·   click to mark   ·   right-click a marker to remove", 13, Color(1, 1, 1, 0.5))

func _label(font: Font, p: Vector2, s: String, fs: int, c: Color) -> void:
	_icons.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.75))
	_icons.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _tooltip(font: Font, p: Vector2, s: String) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16
	var r := Rect2(p, Vector2(w, 26))
	r.position.x = minf(r.position.x, size.x - w - 4)
	_icons.draw_rect(r, Color(0.05, 0.06, 0.07, 0.92))
	_icons.draw_rect(r, UITheme.ACCENT * Color(1, 1, 1, 0.6), false, 1.0)
	_icons.draw_string(font, r.position + Vector2(8, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.TEXT)

## A bar of a round length, bottom right.
func _scale_bar(font: Font) -> void:
	var metres := 10.0
	for m in [10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0]:
		if m * _ppm <= 140.0:
			metres = m
	var w := metres * _ppm
	var o := Vector2(size.x - w - 20, size.y - 18)
	_icons.draw_rect(Rect2(o + Vector2(-2, -8), Vector2(w + 4, 10)), Color(0, 0, 0, 0.5))
	_icons.draw_line(o, o + Vector2(w, 0), UITheme.TEXT, 2.0)
	_icons.draw_line(o, o + Vector2(0, -6), UITheme.TEXT, 2.0)
	_icons.draw_line(o + Vector2(w, 0), o + Vector2(w, -6), UITheme.TEXT, 2.0)
	var s := "%d m" % int(metres) if metres < 1000.0 else "%.1f km" % (metres / 1000.0)
	_label(font, o + Vector2(w * 0.5 - 16, -12), s, 12, UITheme.TEXT)

static func _dist(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % int(m)
