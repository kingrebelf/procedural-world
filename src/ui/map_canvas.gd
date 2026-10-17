class_name MapCanvas
extends Control
## The painted land under its fog of war, centred on `center` (world x, z) at `scale`
## pixels per metre, north up. Used by the minimap and the atlas; icons go on top.

var center := Vector2.ZERO
var scale_ppm := 1.0
var _terrain: Control
var _fog: Control
var _fog_mat: ShaderMaterial
var _land_mat: ShaderMaterial

const FOG_SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform float ppm = 1.0;
uniform vec2 half_size;
uniform sampler2D clouds : repeat_enable, filter_linear_mipmap;
uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
varying vec2 world;

void vertex() {
	world = center + (VERTEX - half_size) / ppm;
}
void fragment() {
	float reveal = texture(TEXTURE, UV).a * COLOR.a;
	vec2 drift = vec2(TIME * 1.6, TIME * 0.6);
	// Two layers of Ben's cloud texture drifting at different speeds over old paper.
	float c1 = texture(clouds, (world + drift) / 900.0).r;
	float c2 = texture(clouds, (world - drift * 1.8) / 260.0).r;
	vec3 sheet = texture(paper, world / 700.0).rgb;
	float edge = reveal + (c2 - 0.6) * 0.5;
	float fog = 1.0 - smoothstep(0.3, 0.62, edge);
	vec3 col = sheet * vec3(0.42, 0.4, 0.38);
	col = mix(col, vec3(0.72, 0.74, 0.78), smoothstep(0.45, 0.95, c1) * 0.55);
	col = mix(col, vec3(0.85, 0.86, 0.9), smoothstep(0.6, 1.0, c2) * 0.25);
	// A burnt rim where the fog gives way, like the edge of an old chart.
	float rim = smoothstep(0.22, 0.45, edge) * (1.0 - smoothstep(0.45, 0.62, edge));
	col = mix(col, vec3(0.36, 0.24, 0.12), rim * 0.55);
	COLOR = vec4(col, fog);
}
"""

## The painted land, printed on paper: a little of the parchment's grain shows through.
const LAND_SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform float ppm = 1.0;
uniform vec2 half_size;
uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
varying vec2 world;

void vertex() {
	world = center + (VERTEX - half_size) / ppm;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 sheet = texture(paper, world / 700.0).rgb;
	c.rgb = mix(c.rgb, c.rgb * sheet * 1.25, 0.35);
	COLOR = c;
}
"""
const FOG_TEX := preload("res://assets/map/fog.jpg")
const PAPER_TEX := preload("res://assets/map/parchment.jpg")
const MARKERS := preload("res://assets/map/markers.png")
## Cells of Ben's marker sheet (6 x 5, 128 px), left to right, top to bottom.
const ICON := {"player": 0, "village": 1, "town": 2, "fort": 3, "dungeon": 4, "campfire": 5,
	"wonder": 6, "w_throne": 7, "w_worldroot": 8, "w_dreadnought": 9, "w_gate": 10, "boss": 11,
	"chest": 12, "beacon": 13, "landmark": 14, "alien_ruin": 15, "cave": 16, "mine": 17,
	"quest": 18, "pin": 19, "death": 20, "vehicle": 21, "horse": 22, "ship": 23,
	"well": 24, "trader": 25, "smithy": 26, "inn": 27, "teleporter": 28, "danger": 29}

## Draws icon `name` centred on p, `s` pixels across.
static func draw_icon(ci: CanvasItem, name: String, p: Vector2, s: float, tint := Color.WHITE) -> void:
	var i: int = ICON.get(name, 6)
	ci.draw_texture_rect_region(MARKERS, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Rect2((i % 6) * 128, (i / 6) * 128, 128, 128), tint)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain = Control.new()
	_terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.draw.connect(_draw_terrain)
	_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var lsh := Shader.new()
	lsh.code = LAND_SHADER
	_land_mat = ShaderMaterial.new()
	_land_mat.shader = lsh
	_land_mat.set_shader_parameter("paper", PAPER_TEX)
	_terrain.material = _land_mat
	add_child(_terrain)
	_fog = Control.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.draw.connect(_draw_fog)
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = sh
	_fog_mat.set_shader_parameter("clouds", FOG_TEX)
	_fog_mat.set_shader_parameter("paper", PAPER_TEX)
	_fog.material = _fog_mat
	add_child(_fog)

func refresh() -> void:
	for m in [_fog_mat, _land_mat]:
		m.set_shader_parameter("center", center)
		m.set_shader_parameter("ppm", scale_ppm)
		m.set_shader_parameter("half_size", size * 0.5)
	_terrain.queue_redraw()
	_fog.queue_redraw()

func to_local_px(x: float, z: float) -> Vector2:
	return size * 0.5 + (Vector2(x, z) - center) * scale_ppm

func to_world(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / scale_ppm

## Pages that show, as [key, rect].
func _visible_pages() -> Array:
	var out: Array = []
	var a := to_world(Vector2.ZERO)
	var b := to_world(size)
	var pm := float(WorldMap.PAGE_M)
	for pz in range(floori(a.y / pm), floori(b.y / pm) + 1):
		for px in range(floori(a.x / pm), floori(b.x / pm) + 1):
			var tl := to_local_px(px * pm, pz * pm)
			out.append([Vector2i(px, pz), Rect2(tl, Vector2(pm, pm) * scale_ppm)])
	return out

func _draw_terrain() -> void:
	for e in _visible_pages():
		var tex: Array = Game.map.textures(e[0])
		if not tex.is_empty():
			_terrain.draw_texture_rect(tex[0], e[1], false)

func _draw_fog() -> void:
	for e in _visible_pages():
		var tex: Array = Game.map.textures(e[0])
		if tex.is_empty():
			_fog.draw_rect(e[1], Color(1, 1, 1, 0))
		else:
			_fog.draw_texture_rect(tex[1], e[1], false)

# --- Icons (shared by the minimap and atlas) ------------------------------------------


## Draws a place's marker centred on p, `s` about its radius in pixels.
static func draw_poi(ci: CanvasItem, poi: Dictionary, p: Vector2, s: float) -> void:
	var k: String = poi["k"]
	if k == "town" and int(poi.get("size", 0)) == 0:
		k = "village"
	draw_icon(ci, k, p, s * 2.6)

## A wonder: its own marker with a glow in its colour and a skull while its keeper lives,
## a green check once conquered, a pulsing star before you have reached it.
static func draw_wonder(ci: CanvasItem, w: Dictionary, p: Vector2, s: float, t: float) -> void:
	var col: Color = WonderSite.COLORS.get(w["t"], Color.WHITE)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	if not w.get("found", false):
		ci.draw_circle(p, s * (1.4 + pulse * 0.5), Color(col.r, col.g, col.b, 0.16 + 0.14 * pulse))
		draw_icon(ci, "wonder", p, s * (2.4 + pulse * 0.4))
		return
	ci.draw_circle(p, s * 1.7, Color(col.r, col.g, col.b, 0.25))
	draw_icon(ci, w["t"], p, s * 3.0)
	if w.get("cleared", false):
		ci.draw_polyline(PackedVector2Array([p + Vector2(s * 0.5, s * 0.9), p + Vector2(s * 0.9, s * 1.3), p + Vector2(s * 1.6, s * 0.4)]), Color(0.3, 1.0, 0.45), 2.5, true)
	else:
		draw_icon(ci, "boss", p + Vector2(s * 1.1, -s * 1.1), s * 1.4)

## The player's arrow pointing along `dir` (screen space).
static func draw_player(ci: CanvasItem, p: Vector2, dir: Vector2, s: float) -> void:
	ci.draw_set_transform(p, dir.angle() + PI * 0.5, Vector2.ONE)
	draw_icon(ci, "player", Vector2.ZERO, s * 2.6)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A map pin or teleporter.
static func draw_marker(ci: CanvasItem, mk: Dictionary, p: Vector2, s: float) -> void:
	if mk["kind"] == "teleporter":
		draw_icon(ci, "teleporter", p, s * 2.4)
	else:
		draw_icon(ci, "pin", p - Vector2(0, s * 0.9), s * 2.4, Markers.color_of(mk).lerp(Color.WHITE, 0.35))

static func _grow(pts: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(q + (q - c).normalized() * by)
	return out
