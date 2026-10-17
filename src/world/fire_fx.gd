class_name FireFx
extends RefCounted
## Living flames from Ben's fire flipbook (assets/textures/fx/fire_flipbook.png): upright
## cards that turn to face you about the vertical only and cross-fade through the sheet's
## 16 frames; the sheet's black is see-through (premultiplied blending). A flame's node
## sits at its base. For hearths, campfires and torches.

const SHEET := "res://assets/textures/fx/fire_flipbook.png"
## Each frame's flame stands this share of the frame above its bottom edge (a jet hangs
## this share below its top edge), per sheet.
const FOOT := {"fire": 0.12, "jet": 0.02}
const FPS := 12.0

static var _mats: Dictionary = {}

## The flipbook material for a sheet in assets/textures/fx ("fire", "jet").
static func material(sheet := "fire") -> ShaderMaterial:
	if _mats.has(sheet):
		return _mats[sheet]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float fps = 12.0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float phase = 0.0;
varying vec2 uv_a;
varying vec2 uv_b;
varying float mixf;
void vertex() {
	// Upright: turn about the vertical through the node to face the camera.
	vec3 c = NODE_POSITION_WORLD;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - c;
	to_cam.y = 0.0;
	vec3 f = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
	vec3 lv = (inverse(MODEL_MATRIX) * vec4(VERTEX, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX = base + r * lv.x * sx + vec3(0.0, 1.0, 0.0) * lv.y * sy;
	NORMAL = f;
	// Each fire runs out of step with the others, from where it stands.
	float t = TIME * fps + phase * 16.0 + fract(sin(dot(c.xz, vec2(12.9898, 78.233))) * 43758.5453) * 16.0;
	float f0 = mod(floor(t), 16.0);
	float f1 = mod(f0 + 1.0, 16.0);
	mixf = fract(t);
	uv_a = (UV + vec2(mod(f0, 4.0), floor(f0 / 4.0))) / 4.0;
	uv_b = (UV + vec2(mod(f1, 4.0), floor(f1 / 4.0))) / 4.0;
}
void fragment() {
	vec3 col = mix(texture(tex, uv_a).rgb, texture(tex, uv_b).rgb, mixf) * tint.rgb * tint.a;
	// Premultiplied: bright flame hides what is behind it in proportion, so it keeps its
	// colour against a bright sky instead of washing out as plain adding would.
	ALBEDO = col;
	ALPHA = clamp(max(col.r, max(col.g, col.b)) * 1.3, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("fps", FPS * (1.6 if sheet == "jet" else 1.0))
	var path := SHEET.replace("fire_", sheet + "_")
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
	_mats[sheet] = m
	return m

## A flame `size` metres tall, its base at the returned node's origin (or, with `hang`,
## hanging from it, as a jet from a nozzle): two cards out of step give it body.
static func flame(size: float, tint := Color(1, 1, 1, 1), sheet := "fire", hang := false) -> Node3D:
	var n := Node3D.new()
	n.name = "Flame"
	for i in 2:
		var s := size * (1.0 if i == 0 else 0.7)
		var q := QuadMesh.new()
		q.size = Vector2(s, s)
		q.center_offset = Vector3(0, s * (0.5 - float(FOOT.get(sheet, 0.0))) * (-1.0 if hang else 1.0), 0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = material(sheet)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The cards turn in the shader, so their box must hold them at any angle.
		mi.extra_cull_margin = s
		mi.visibility_range_end = 90.0
		mi.set_instance_shader_parameter("tint", tint)
		mi.set_instance_shader_parameter("phase", 0.45 * i)
		mi.position = Vector3(0.04 * size * i, 0, 0)
		n.add_child(mi)
	return n
