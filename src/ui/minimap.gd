class_name Minimap
extends Control
## The round map in the corner: the painted land around you under its fog of war,
## turned so the way you face is up, with a compass ring, nearby places and wonders,
## and your markers pinned to the rim when they are out of range. The minimap zoom key
## steps through three ranges; the map overlay key steps through the overlays (creature
## levels, danger, era, zones, landforms: MapLayers), with a legend beside the disc.

const DIAM := 220.0
const RANGES := [110.0, 200.0, 380.0] ## metres from centre to rim
const RES := 256 ## the map is drawn at this size, then masked round

var player: Node3D
var zoom := 1
var _vp: SubViewport
var _canvas: MapCanvas
var _disc: TextureRect
var _over: Control
var _info: Label
var _finds: Label
var _zone := {}
var _zone_t := 0.0
var _zone_kind := "" ## the zone you were last told you are in
var _zone_seen := ""
var _zone_held := 0
var _t := 0.0

const MASK := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - 0.5) * 2.0;
	c.a *= 1.0 - smoothstep(0.985, 1.0, d);
	// A slight vignette towards the rim.
	c.rgb *= 1.0 - 0.28 * smoothstep(0.6, 1.0, d);
	COLOR = c;
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DIAM, DIAM + 80)
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_canvas = MapCanvas.new()
	_canvas.size = Vector2(RES, RES)
	_vp.add_child(_canvas)
	_disc = TextureRect.new()
	_disc.texture = _vp.get_texture()
	_disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_disc.size = Vector2(DIAM, DIAM)
	_disc.pivot_offset = Vector2(DIAM, DIAM) * 0.5
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK
	var m := ShaderMaterial.new()
	m.shader = sh
	_disc.material = m
	add_child(_disc)
	_over = Control.new()
	_over.size = Vector2(DIAM, DIAM)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)
	_info = UITheme.label("", 13, UITheme.DIM)
	_info.position = Vector2(0, DIAM + 4)
	_info.size = Vector2(DIAM, 36)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_constant_override("outline_size", 4)
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(_info)
	# What this kind of zone holds, under the clock.
	_finds = UITheme.label("", 12, Color(1, 1, 1, 0.72))
	_finds.position = Vector2(-10, DIAM + 24)
	_finds.size = Vector2(DIAM + 20, 52)
	_finds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_finds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finds.add_theme_constant_override("outline_size", 4)
	_finds.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_finds)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("minimap_zoom"):
		zoom = (zoom + 1) % RANGES.size()
	elif e.is_action_pressed("map_layer") and Game.map:
		Game.map.set_layer((Game.map.layer + 1) % MapLayers.COUNT)
		Game.toast.emit("Map overlay: %s" % MapLayers.NAMES[Game.map.layer])

## The angle the map turns so that where you face is up.
func _turn() -> float:
	var f := -player.global_transform.basis.z
	if Vector2(f.x, f.z).length() < 0.01:
		return 0.0
	return -atan2(f.x, -f.z)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or Game.store == null:
		return
	_t += delta
	var p := player.global_position
	_canvas.center = Vector2(p.x, p.z)
	_canvas.scale_ppm = RES * 0.5 / RANGES[zoom]
	_canvas.refresh()
	_disc.rotation = _turn()
	_over.queue_redraw()
	var t := fposmod(Game.day, 1.0) * 24.0
	_info.text = "Day %d  %02d:%02d   ·   %d, %d" % [int(Game.day) + 1, int(t), int(fmod(t, 1.0) * 60), int(p.x), int(p.z)]
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 0.5
		_zone = ZoneInfo.at(Game.seed, p.x, p.z)
		_finds.text = _zone["finds"]
		_crossing(_zone)

## World x, z to a point on the turned disc, and whether it falls inside the rim.
func _place(x: float, z: float) -> Array:
	var r := DIAM * 0.5
	var px: Vector2 = (Vector2(x, z) - _canvas.center) * (r / float(RANGES[zoom]))
	px = px.rotated(_disc.rotation)
	return [Vector2(r, r) + px, px.length() <= r - 8.0, px]

func _draw_over() -> void:
	if player == null or not is_instance_valid(player):
		return
	var r := DIAM * 0.5
	var c := Vector2(r, r)
	var font := get_theme_default_font()
	# Places you can see on the map.
	var reach: float = RANGES[zoom] * 1.05
	var me := _canvas.center
	var c0 := Vector2i(floori((me.x - reach) / ChunkGenerator.SIZE), floori((me.y - reach) / ChunkGenerator.SIZE))
	var c1 := Vector2i(floori((me.x + reach) / ChunkGenerator.SIZE), floori((me.y + reach) / ChunkGenerator.SIZE))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var key := "%d,%d" % [cx, cz]
			for o in Game.map.ores.get(key, []):
				if Game.map.shows("ore_" + o["t"]) and Game.map.revealed(o["x"], o["z"]) >= 0.45:
					var at: Array = _place(o["x"], o["z"])
					if at[1]:
						MapCanvas.draw_ore(_over, o, at[0], 5.0)
			for poi in Game.map.pois.get(key, []):
				var wp := Vector2(poi["x"], poi["z"])
				if not Game.map.shows(poi["k"]) or absf(wp.x - me.x) > reach or absf(wp.y - me.y) > reach or Game.map.revealed(wp.x, wp.y) < 0.45:
					continue
				var at: Array = _place(wp.x, wp.y)
				if at[1]:
					MapCanvas.draw_poi(_over, poi, at[0], 6.5)
	# People about: villagers near you, ringed once you have spoken with them.
	if Game.map.shows("people"):
		var npcs := get_tree().get_first_node_in_group("npc_manager")
		if npcs:
			for n in npcs.all_nodes():
				var at: Array = _place(n.global_position.x, n.global_position.z)
				if at[1]:
					MapCanvas.draw_person(_over, at[0], 2.6, n.rec.get("job", "") == "trader", Game.map.people.has(String(n.rec["id"])))
	# Wonders: shown once their chunk has loaded near you, pinned to the rim beyond range.
	for key in Game.map.wonders if Game.map.shows("wonder") else {}:
		var w: Dictionary = Game.map.wonders[key]
		var at: Array = _place(w["x"], w["z"])
		if at[1]:
			MapCanvas.draw_wonder(_over, w, at[0], 7.0, _t)
		elif (at[2] as Vector2).length() < r * 4.0:
			_edge_pin(c + (at[2] as Vector2).normalized() * (r - 7.0), WonderSite.COLORS[w["t"]], Vector2(w["x"], w["z"]).distance_to(me))
	# Your markers and teleporters.
	for mk in Game.markers.on_planet(Game.planet) if Game.map.shows("marker") else []:
		var at: Array = _place(mk["x"], mk["z"])
		var col := Color(0.45, 0.9, 1.0) if mk["kind"] == "teleporter" else Markers.color_of(mk)
		if at[1]:
			MapCanvas.draw_marker(_over, mk, at[0], 7.0)
		else:
			_edge_pin(c + (at[2] as Vector2).normalized() * (r - 7.0), col, Vector2(mk["x"], mk["z"]).distance_to(me))
	# Your allies, wherever they are.
	for al in Net.allies_where():
		if int(al[2]) != Game.planet:
			continue
		var at: Array = _place(al[3].x, al[3].z)
		if at[1]:
			MapCanvas.draw_ally(_over, at[0], 4.0)
		else:
			_edge_pin(c + (at[2] as Vector2).normalized() * (r - 7.0), Color(0.42, 0.86, 0.5), Vector2(al[3].x, al[3].z).distance_to(me))
	# The rim: a dark band, a thin gold line and the compass points turning with you.
	_over.draw_arc(c, r - 1.0, 0, TAU, 72, Color(0.04, 0.05, 0.06, 0.85), 5.0, true)
	_over.draw_arc(c, r - 3.5, 0, TAU, 72, UITheme.ACCENT * Color(1, 1, 1, 0.75), 1.2, true)
	for i in 36:
		var a := _disc.rotation + i * TAU / 36.0 - PI * 0.5
		var len := 6.0 if i % 9 == 0 else 3.0
		var d := Vector2.from_angle(a)
		_over.draw_line(c + d * (r - 4.0), c + d * (r - 4.0 - len), Color(1, 1, 1, 0.5 if i % 9 == 0 else 0.25), 1.0, true)
	var letters := ["N", "E", "S", "W"]
	for i in 4:
		var a := _disc.rotation + i * PI * 0.5 - PI * 0.5
		var q := c + Vector2.from_angle(a) * (r - 15.0)
		var fs := 15 if i == 0 else 12
		var tw := font.get_string_size(letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_over.draw_circle(q, 9.0, Color(0.04, 0.05, 0.06, 0.8))
		_over.draw_string(font, q + Vector2(-tw * 0.5, fs * 0.36), letters[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1.0, 0.42, 0.35) if i == 0 else UITheme.TEXT)
	_draw_layer(font, c, r)
	MapCanvas.draw_player(_over, c, Vector2(0, -1), 8.0)
	_draw_zone(font, c, r)
	var zs := "%d m" % int(RANGES[zoom])
	_over.draw_string(font, c + Vector2(r * 0.52, r * 0.98), zs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

## The map overlay's rings of equal level (inside the rim) and its legend, left of the disc.
func _draw_layer(font: Font, c: Vector2, r: float) -> void:
	var l := MapLayers.current()
	if l == MapLayers.OFF:
		return
	var to_px := func(x: float, z: float) -> Vector2: return _place(x, z)[0]
	for ln in MapLayers.ring_lines(l, _canvas.center, RANGES[zoom] * 1.05, to_px):
		var pts: PackedVector2Array = ln[0]
		for k in pts.size() - 1:
			if pts[k].distance_to(c) < r - 6.0 and pts[k + 1].distance_to(c) < r - 6.0:
				_over.draw_line(pts[k], pts[k + 1], Color(0, 0, 0, 0.45), 3.0, true)
				_over.draw_line(pts[k], pts[k + 1], Color(1, 0.95, 0.8, 0.85), 1.2, true)
		# Named a little way along the ring, clear of your arrow in the middle.
		var mid := Vector2(INF, INF)
		for q in pts:
			if q.distance_to(c) < r - 24.0 and q.distance_to(c) > 34.0:
				mid = q
				break
		if mid.x < INF:
			var s: String = ln[1]
			var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			_over.draw_string_outline(font, mid + Vector2(-tw * 0.5, -4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
			_over.draw_string(font, mid + Vector2(-tw * 0.5, -4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.96, 0.85))
	MapLayers.draw_legend(_over, font, Vector2(-10, 6), l, _canvas.layer_mask, true, 11)

## A translucent band across the lower disc: the zone's name, kind and level range.
func _draw_zone(font: Font, c: Vector2, r: float) -> void:
	if _zone.is_empty():
		return
	var y := c.y + r * 0.42
	var w := r * 1.25
	var box := Rect2(c.x - w * 0.5, y, w, 38)
	_over.draw_rect(box, Color(0.03, 0.04, 0.05, 0.5))
	var col: Color = _zone["color"]
	_over.draw_line(box.position, box.position + Vector2(w, 0), Color(col.r, col.g, col.b, 0.7), 1.0)
	var name: String = _zone["name"]
	var nw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_over.draw_string_outline(font, Vector2(c.x - nw * 0.5, y + 15), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.6))
	_over.draw_string(font, Vector2(c.x - nw * 0.5, y + 15), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT)
	var sub := "%s  ·  Lv %d–%d" % [_zone["kind"], _zone["level_lo"], _zone["level_hi"]]
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_over.draw_string(font, Vector2(c.x - sw * 0.5, y + 31), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.25))

func _edge_pin(q: Vector2, col: Color, dist: float) -> void:
	_over.draw_circle(q, 5.5, Color(0, 0, 0, 0.7))
	_over.draw_circle(q, 4.0, col)
	if dist < 2000.0:
		var font := get_theme_default_font()
		var s := "%d" % int(dist) if dist < 1000.0 else "%.1fk" % (dist / 1000.0)
		var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var inward := (Vector2(DIAM, DIAM) * 0.5 - q).normalized() * 14.0
		_over.draw_string_outline(font, q + inward + Vector2(-tw * 0.5, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
		_over.draw_string(font, q + inward + Vector2(-tw * 0.5, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))

## Says so when you walk into another zone (once it holds for a second, so a line you
## walk along doesn't chatter); not for the zone you start or arrive in.
func _crossing(z: Dictionary) -> void:
	var kind := String(z["kind"])
	if kind != _zone_seen:
		_zone_seen = kind
		_zone_held = 0
		return
	_zone_held += 1
	if _zone_held != 2 or kind == _zone_kind:
		return
	var first := _zone_kind == ""
	_zone_kind = kind
	if not first:
		Game.toast.emit(ZoneInfo.entering(z))
