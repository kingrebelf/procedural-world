shader_type spatial;
// Instanced grass blades with wind. INSTANCE_CUSTOM.rgb is the era-blended tint,
// INSTANCE_CUSTOM.a the fantasy glow amount.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float wind_strength;
global uniform vec2 wind_dir;
uniform float night_glow = 1.0;
varying float glow;
varying vec3 tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * (1.2 + wind_strength * 1.6) + dot(wp.xz, wind_dir) * 0.35;
	float gust = sin(t) * 0.6 + sin(t * 2.3 + wp.x * 0.7) * 0.25 + sin(TIME * 0.4 + wp.z * 0.05) * 0.4;
	float bend = UV.y * UV.y * (0.12 + wind_strength * 0.9) * (gust + wind_strength * 0.8);
	vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	VERTEX.xz += normalize(local_wind.xz + vec2(0.0001)) * bend;
	VERTEX.y -= abs(bend) * 0.3;
	glow = INSTANCE_CUSTOM.a;
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 base = tint;
	ALBEDO = mix(base * 0.3, base * 1.05, UV.y);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = base * 0.45;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.65));
	EMISSION = base * glow * smoothstep(0.7, 1.0, UV.y) * 2.5 * night_glow;
}
