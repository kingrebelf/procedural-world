shader_type spatial;
// Lakes and seas: wind-driven swell (sum of directional deep-water waves, larger over
// deep water), depth-tinted, refractive and fresnel-reflective, with whitecaps when the
// wind is strong and foam where waves meet the shore.
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/env/clouds.gdshaderinc"
global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform vec3 shallow : source_color = vec3(0.16, 0.36, 0.38);
uniform vec3 deep : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 glow : source_color = vec3(0.1, 0.9, 0.8);
uniform float glow_amount = 0.0;
uniform float clarity = 4.0;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec2 depth_origin = vec2(-800.0);
uniform float depth_size = 1600.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;
varying float crest;
varying float amp;

vec2 h2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(h2(i) - 0.5, f), dot(h2(i + vec2(1, 0)) - 0.5, f - vec2(1, 0)), u.x),
		mix(dot(h2(i + vec2(0, 1)) - 0.5, f - vec2(0, 1)), dot(h2(i + vec2(1, 1)) - 0.5, f - vec2(1, 1)), u.x), u.y);
}
float ripples(vec2 p, float t) {
	return n2(p * 0.35 + vec2(t * 0.12, t * 0.05)) * 0.6 + n2(p * 1.1 - vec2(t * 0.2, -t * 0.15)) * 0.3 + n2(p * 3.3 + t * 0.4) * 0.1;
}
vec2 rot(vec2 v, float a) { return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)); }

// Must match Water.surface_height(). Returns height and its xz gradient.
vec3 swell(vec2 p, float t, float a) {
	vec2 d = normalize(wind_dir + vec2(0.0001));
	vec2 dirs[4] = vec2[](d, rot(d, 0.6), rot(d, -0.45), rot(d, 1.3));
	float lens[4] = float[](38.0, 21.0, 13.0, 7.0);
	float amps[4] = float[](0.5, 0.28, 0.15, 0.07);
	vec3 r = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float k = 6.2831853 / lens[i];
		float c = sqrt(9.8 / k);
		float ph = k * (dot(p, dirs[i]) - c * t);
		r.x += amps[i] * sin(ph);
		r.yz += amps[i] * k * cos(ph) * dirs[i];
	}
	return r * a;
}

float depth_here(vec2 p) {
	vec2 uv = (p - depth_origin) / depth_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 12.0;
	return texture(depth_map, uv).r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = depth_here(wpos.xz);
	float open = smoothstep(0.5, 14.0, depth);
	amp = (0.04 + wind_strength * wind_strength * 1.1) * (0.15 + 0.85 * open);
	vec3 s = swell(wpos.xz, TIME, amp);
	VERTEX.y += s.x;
	wpos.y += s.x;
	NORMAL = normalize(vec3(-s.y, 1.0, -s.z));
	crest = s.x / max(amp, 0.001);
}

void fragment() {
	float t = TIME;
	float e = 0.08;
	float h = ripples(wpos.xz, t);
	float rs = 0.5 + wind_strength * 1.2;
	vec3 rn = vec3(-(ripples(wpos.xz + vec2(e, 0), t) - h) / e, 0.0, -(ripples(wpos.xz + vec2(0, e), t) - h) / e) * rs;
	vec3 nw = normalize((inverse(VIEW_MATRIX) * vec4(NORMAL, 0.0)).xyz + rn * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z - (-VERTEX.z)), 0.0, 100.0);
	float k = 1.0 - exp(-water_depth / clarity);
	vec2 refr_uv = SCREEN_UV + nw.xz * 0.02 * k;
	vec3 under = textureLod(screen_tex, refr_uv, 1.0).rgb;
	vec3 col = mix(under * shallow * 2.2, deep, k);
	// Light passing through the thin tops of waves turns them a brighter green-blue,
	// most when you look toward a low sun.
	vec3 vdir = normalize((inverse(VIEW_MATRIX) * vec4(VIEW, 0.0)).xyz);
	float back = pow(clamp(dot(-vdir, normalize(sun_dir_g)), 0.0, 1.0), 3.0);
	float tip = smoothstep(0.15, 0.9, crest) * clamp(amp * 3.0, 0.0, 1.0);
	col += vec3(0.04, 0.16, 0.13) * tip * (0.35 + 1.2 * back) * smoothstep(-0.05, 0.2, sun_dir_g.y);
	col *= 1.0 - 0.3 * cloud_shadow(wpos);
	// Shore foam and wind whitecaps on wave crests.
	float shore = 1.0 - smoothstep(0.0, 0.6 + amp, water_depth);
	float foam_n = smoothstep(0.1, 0.35, n2(wpos.xz * 1.7 + t * 0.3));
	float caps = smoothstep(0.55, 0.95, crest) * smoothstep(0.45, 0.85, wind_strength) * foam_n;
	float foam = max(shore * 0.5 * (0.5 + 0.5 * sin(t * 1.5 + wpos.x * 0.8 + wpos.z * 0.5)), caps);
	col = mix(col, vec3(0.88, 0.92, 0.95), foam);
	ALBEDO = col;
	ROUGHNESS = 0.03 + wind_strength * 0.08 + foam * 0.6;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = glow * glow_amount * (0.15 + 0.6 * smoothstep(0.1, 0.3, h)) * (1.0 - k * 0.5);
}
