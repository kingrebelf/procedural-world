shader_type spatial;
// Lakes and rivers: depth-tinted, fresnel-reflective, with two scrolling wave normals.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.16, 0.36, 0.38);
uniform vec3 deep : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 glow : source_color = vec3(0.1, 0.9, 0.8);
uniform float glow_amount = 0.0;
uniform float clarity = 4.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

vec2 h2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(h2(i) - 0.5, f), dot(h2(i + vec2(1, 0)) - 0.5, f - vec2(1, 0)), u.x),
		mix(dot(h2(i + vec2(0, 1)) - 0.5, f - vec2(0, 1)), dot(h2(i + vec2(1, 1)) - 0.5, f - vec2(1, 1)), u.x), u.y);
}
float waves(vec2 p, float t) {
	return n2(p * 0.35 + vec2(t * 0.12, t * 0.05)) * 0.6 + n2(p * 1.1 - vec2(t * 0.2, -t * 0.15)) * 0.3 + n2(p * 3.3 + t * 0.4) * 0.1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float e = 0.08;
	float h = waves(wpos.xz, t);
	vec3 n = normalize(vec3(-(waves(wpos.xz + vec2(e, 0), t) - h) / e, 1.0, -(waves(wpos.xz + vec2(0, e), t) - h) / e) * vec3(0.6, 1.0, 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z - (-VERTEX.z)), 0.0, 100.0);
	float k = 1.0 - exp(-water_depth / clarity);
	vec2 refr_uv = SCREEN_UV + n.xz * 0.02 * k;
	vec3 under = textureLod(screen_tex, refr_uv, 1.0).rgb;
	vec3 col = mix(under * shallow * 2.2, deep, k);
	float shore = 1.0 - smoothstep(0.0, 0.6, water_depth);
	col = mix(col, vec3(0.85), shore * 0.35 * (0.5 + 0.5 * sin(t * 1.5 + wpos.x * 0.8 + wpos.z * 0.5)));
	ALBEDO = col;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = glow * glow_amount * (0.15 + 0.6 * smoothstep(0.1, 0.3, h)) * (1.0 - k * 0.5);
}
