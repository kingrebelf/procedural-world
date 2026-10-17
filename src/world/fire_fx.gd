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

static var _swirl: ShaderMaterial

## The door of light in a portal, flat in its node's XY plane and seen from both sides:
## the fullest frames of Ben's magic flipbook (assets/textures/fx/portal_swirl.png) turning
## one way, a larger copy turning slowly the other, over a deep violet that hides most of
## what is behind. `size` is the disc's diameter.
static func swirl(size: float, tint := Color(1, 1, 1, 1)) -> MeshInstance3D:
	if _swirl == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float fps = 2.5;
uniform float turn = 0.55;
instance uniform vec4 tint : source_color = vec4(1.0);
mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}
// The strip's four frames cross-faded in turn, at p (centred, frame half-width 0.5).
vec3 frames(vec2 p, float t) {
	vec2 q = clamp(p + 0.5, vec2(0.002), vec2(0.998));
	float f0 = mod(floor(t), 4.0);
	float f1 = mod(f0 + 1.0, 4.0);
	vec3 a = texture(tex, vec2((q.x + f0) / 4.0, q.y)).rgb;
	vec3 b = texture(tex, vec2((q.x + f1) / 4.0, q.y)).rgb;
	return mix(a, b, smoothstep(0.0, 1.0, fract(t)));
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	if (r > 0.5) {
		discard;
	}
	float t = TIME * fps;
	// The frames' swirl fills about nine tenths of each frame; scale it to the rim.
	vec3 c = frames(rot(TIME * turn) * p * 0.95, t);
	c += 0.45 * frames(rot(1.3 - TIME * turn * 0.45) * p * 1.4, t + 2.0);
	c *= tint.rgb * tint.a;
	float rim = smoothstep(0.5, 0.42, r);
	vec3 deep = vec3(0.07, 0.025, 0.15) * rim;
	ALBEDO = c + deep;
	ALPHA = clamp(max(c.r, max(c.g, c.b)) * 1.3 + 0.82 * rim, 0.0, 1.0);
}
"""
		_swirl = ShaderMaterial.new()
		_swirl.shader = sh
		var path := "res://assets/textures/fx/portal_swirl.png"
		if ResourceLoader.exists(path):
			_swirl.set_shader_parameter("tex", load(path))
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "Swirl"
	mi.mesh = q
	mi.material_override = _swirl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	mi.set_instance_shader_parameter("tint", tint)
	return mi

static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D

## A soft round dot, for sparks and smoke puffs.
static func _dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## Sparks that fly up off a flame `size` metres tall and die out, and with `smoke` a thin
## grey smoke rising above it. They are left behind in the world as the fire moves, so a
## swung torch trails them. Put it where the flame stands.
static func embers(size: float, smoke := true) -> Node3D:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_texture = _dot()
		_spark_mat.disable_fog = true
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_texture = _dot()
		_smoke_mat.roughness = 1.0
	var n := Node3D.new()
	n.name = "Embers"
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.amount = clampi(int(size * 28.0), 8, 28)
	p.lifetime = 1.3
	p.randomness = 0.6
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE * clampf(size * 0.05, 0.012, 0.03)
	q.material = _spark_mat
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.12
	p.position = Vector3(0, size * 0.25, 0)
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = size * 1.2
	p.initial_velocity_max = size * 3.2
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = size * 1.5
	p.damping_max = size * 3.0
	# Hot air tosses them about as they rise.
	p.tangential_accel_min = -size * 4.0
	p.tangential_accel_max = size * 4.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.15, 1.0))
	p.color_ramp = g
	n.add_child(p)
	if smoke:
		var s := CPUParticles3D.new()
		s.name = "Smoke"
		s.amount = 10
		s.lifetime = 2.8
		s.randomness = 0.5
		s.local_coords = false
		var sq := QuadMesh.new()
		sq.size = Vector2.ONE * size * 0.5
		sq.material = _smoke_mat
		s.mesh = sq
		s.position = Vector3(0, size * 0.85, 0)
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		s.emission_sphere_radius = size * 0.08
		s.direction = Vector3.UP
		s.spread = 12.0
		s.initial_velocity_min = size * 0.8
		s.initial_velocity_max = size * 1.4
		s.gravity = Vector3(0, 0.15, 0)
		s.damping_min = size * 0.3
		s.damping_max = size * 0.6
		s.angle_min = 0.0
		s.angle_max = 360.0
		var ss := Curve.new()
		ss.add_point(Vector2(0, 0.35))
		ss.add_point(Vector2(1, 1.6))
		s.scale_amount_curve = ss
		var sg := Gradient.new()
		sg.set_color(0, Color(0.35, 0.33, 0.31, 0.0))
		sg.set_color(1, Color(0.42, 0.41, 0.4, 0.0))
		sg.add_point(0.15, Color(0.33, 0.31, 0.3, 0.22))
		s.color_ramp = sg
		n.add_child(s)
	for c in n.get_children():
		(c as CPUParticles3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(c as CPUParticles3D).visibility_range_end = 60.0
	return n
