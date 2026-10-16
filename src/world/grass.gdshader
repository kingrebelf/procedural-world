shader_type spatial;
// Instanced grass blades with wind. INSTANCE_CUSTOM.rgb is the era-blended tint,
// INSTANCE_CUSTOM.a the fantasy glow amount.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float wind_strength;
global uniform vec2 wind_dir;
global uniform float wind_time;
uniform float night_glow = 1.0;
varying float glow;
varying vec3 tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// wind_time is the wind's own clock: it runs faster in a strong wind but never jumps,
	// so blades never snap when the wind changes.
	float t = wind_time * 1.3 + dot(wp.xz, wind_dir) * 0.35;
	float sway = sin(t) * 0.45 + sin(t * 2.3 + wp.x * 0.7) * 0.15;
	// Gusts roll across a field as broad waves travelling with the wind.
	float wave = smoothstep(0.2, 1.0, sin(dot(wp.xz, wind_dir) * 0.045 - wind_time * 0.55 + sin(wp.x * 0.013) * 1.5));
	float bend = UV.y * UV.y * (0.1 + wind_strength * 0.75) * (sway + wind_strength * 0.7 + wave * (0.25 + wind_strength * 0.6));
	vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	VERTEX.xz += normalize(local_wind.xz + vec2(0.0001)) * bend;
	VERTEX.y -= abs(bend) * 0.3;
	glow = INSTANCE_CUSTOM.a;
	// Tints are authored as sRGB colours; shading happens in linear space.
	tint = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
}

void fragment() {
	vec3 base = tint;
	ALBEDO = mix(base * 0.3, base * 1.05, UV.y);
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = base * 0.45;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.65));
	EMISSION = base * glow * smoothstep(0.75, 1.0, UV.y) * 1.2 * night_glow;
}
