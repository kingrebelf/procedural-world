class_name MapCanvas
extends Control
## The painted land under its fog of war, centred on `center` (world x, z) at `scale`
## pixels per metre, north up. Used by the minimap and the atlas; icons go on top.

var center := Vector2.ZERO
var scale_ppm := 1.0
var _terrain: Control
var _fog: Control
var _fog_mat: ShaderMaterial

const FOG_SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform float ppm = 1.0;
uniform vec2 half_size;
varying vec2 world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 17.1; a *= 0.5; }
	return v;
}
void vertex() {
	world = center + (VERTEX - half_size) / ppm;
}
void fragment() {
	float reveal = texture(TEXTURE, UV).a * COLOR.a;
	vec2 drift = vec2(TIME * 1.5, TIME * 0.7);
	float cloud = fbm((world + drift) * 0.006);
	float wisp = fbm((world - drift * 1.7) * 0.03);
	float edge = reveal + (wisp - 0.5) * 0.45;
	float fog = 1.0 - smoothstep(0.32, 0.62, edge);
	vec3 col = mix(vec3(0.07, 0.085, 0.11), vec3(0.2, 0.23, 0.28), cloud);
	col += vec3(0.03, 0.035, 0.045) * smoothstep(0.55, 0.8, wisp);
	// A warm rim where the fog gives way, like the edge of an old chart.
	float rim = smoothstep(0.22, 0.45, edge) * (1.0 - smoothstep(0.45, 0.62, edge));
	col = mix(col, vec3(0.62, 0.52, 0.36), rim * 0.35);
	COLOR = vec4(col, fog);
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain = Control.new()
	_terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.draw.connect(_draw_terrain)
	_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	_fog.material = _fog_mat
	add_child(_fog)

func refresh() -> void:
	_fog_mat.set_shader_parameter("center", center)
	_fog_mat.set_shader_parameter("ppm", scale_ppm)
	_fog_mat.set_shader_parameter("half_size", size * 0.5)
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

const POI_COLORS := {"town": Color(0.98, 0.9, 0.7), "fort": Color(0.85, 0.82, 0.78), "landmark": Color(0.95, 0.78, 0.42),
	"cave": Color(0.75, 0.7, 0.62), "trader": Color(0.6, 0.95, 0.6)}

## Draws a place's glyph centred on p, `s` about its radius in pixels.
static func draw_poi(ci: CanvasItem, kind: String, p: Vector2, s: float, col: Color) -> void:
	var dark := Color(0.04, 0.04, 0.05, 0.85 * col.a)
	match kind:
		"town":
			var pts := PackedVector2Array([p + Vector2(-s, s * 0.8), p + Vector2(-s, -s * 0.1), p + Vector2(0, -s), p + Vector2(s, -s * 0.1), p + Vector2(s, s * 0.8)])
			ci.draw_colored_polygon(_grow(pts, p, 1.6), dark)
			ci.draw_colored_polygon(pts, col)
		"fort":
			var r := Rect2(p - Vector2(s * 0.8, s * 0.5), Vector2(s * 1.6, s * 1.3))
			ci.draw_rect(r.grow(1.5), dark)
			ci.draw_rect(r, col)
			for x in [-0.8, -0.1, 0.6]:
				ci.draw_rect(Rect2(p + Vector2(x * s, -s), Vector2(s * 0.45, s * 0.55)), col)
		"cave":
			ci.draw_circle(p, s + 1.5, dark)
			ci.draw_arc(p + Vector2(0, s * 0.3), s * 0.7, PI, TAU, 10, col, 2.0, true)
		"trader":
			ci.draw_circle(p, s * 0.75 + 1.5, dark)
			ci.draw_circle(p, s * 0.75, col)
		_:
			var pts := PackedVector2Array()
			for i in 8:
				var a := i * TAU / 8.0 - PI * 0.5
				pts.append(p + Vector2.from_angle(a) * (s if i % 2 == 0 else s * 0.42))
			ci.draw_colored_polygon(_grow(pts, p, 1.6), dark)
			ci.draw_colored_polygon(pts, col)

## A wonder: a glowing star in its colour, a check when conquered, a pulsing "?" before
## you have reached it.
static func draw_wonder(ci: CanvasItem, w: Dictionary, p: Vector2, s: float, t: float) -> void:
	var col: Color = WonderSite.COLORS.get(w["t"], Color.WHITE)
	if not w.get("found", false):
		var pulse := 0.5 + 0.5 * sin(t * 3.0)
		ci.draw_circle(p, s * (1.3 + pulse * 0.5), Color(col.r, col.g, col.b, 0.18 + 0.12 * pulse))
		ci.draw_circle(p, s * 0.85, Color(0.05, 0.04, 0.08, 0.9))
		ci.draw_arc(p, s * 0.85, 0, TAU, 20, col, 1.5, true)
		var f: Font = (ci as Control).get_theme_default_font() if ci is Control else ThemeDB.fallback_font
		var fs := int(s * 1.3)
		var w2: float = f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, p + Vector2(-w2 * 0.5, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	ci.draw_circle(p, s * 1.7, Color(col.r, col.g, col.b, 0.22))
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0 - PI * 0.5 + t * 0.2
		pts.append(p + Vector2.from_angle(a) * (s * 1.25 if i % 2 == 0 else s * 0.55))
	ci.draw_colored_polygon(_grow(pts, p, 1.8), Color(0.05, 0.04, 0.06, 0.9))
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(p, s * 0.32, Color(1, 1, 1, 0.9))
	if w.get("cleared", false):
		ci.draw_polyline(PackedVector2Array([p + Vector2(-s * 0.5, 0), p + Vector2(-s * 0.1, s * 0.4), p + Vector2(s * 0.6, -s * 0.45)]), Color(0.3, 1.0, 0.45), 2.5, true)

## The player's arrow pointing along `dir` (screen space).
static func draw_player(ci: CanvasItem, p: Vector2, dir: Vector2, s: float) -> void:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([p + d * s, p - d * s * 0.6 + side * s * 0.65, p - d * s * 0.25, p - d * s * 0.6 - side * s * 0.65])
	ci.draw_colored_polygon(_grow(pts, p, 2.0), Color(0, 0, 0, 0.8))
	ci.draw_colored_polygon(pts, Color(1, 1, 1))

static func _grow(pts: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(q + (q - c).normalized() * by)
	return out
