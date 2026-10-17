shader_type spatial;
// A waterfall's falling sheet (WaterfallFx). UV is (metres across the lip, metres fallen
// below it, negative on the tongue of river just above), UV2 is (how far down, 0..1;
// across, 0..1), COLOR.r the layer (0 the sheet, 1 the spray billowing off it) and COLOR.g
// the drop's height over 30 m.
//
// The pattern runs on the time since the water left the lip (sqrt(2y/g)), not on the
// metres fallen, so it streams over the lip slowly and stretches out into long streaks as
// the water speeds up, as falling water does. Glassy and dark where it rolls over the
// lip, it takes in air as it falls and breaks into white strands with gaps between, and
// the spray layer is a thin veil of drifting white. Lit like any water: it never glows.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

global uniform vec2 wind_dir;
global uniform float wind_strength;

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}
float h1(vec2 p) { return float(pcg2d(uvec2(ivec2(floor(p)) + 32768)).x) * (1.0 / 4294967296.0); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}

varying float layer;
varying vec3 wpos;

void vertex() {
	layer = COLOR.r;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The spray layer sways a little with the wind as it falls.
	float u = max(UV2.x, 0.0);
	vec3 w = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_strength * u * u * (0.4 + layer * 1.2);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * w);
}

void fragment() {
	float across = UV.x;
	float fallen = UV.y;
	float u = UV2.x; // < 0 on the tongue above the lip
	float side = UV2.y;
	float tau = fallen >= 0.0 ? sqrt(2.0 * fallen / 9.8) : fallen / 1.6;
	float t = tau - TIME * 0.9 + layer * 7.3;
	// Streaks: fine ones riding on broad ones, stretched along the fall.
	float s1 = vn(vec2(across * 2.1 + layer * 31.0, t * 2.4));
	float s2 = vn(vec2(across * 6.3 + 5.0, t * 6.0 + across * 0.3));
	float s3 = vn(vec2(across * 0.7 - 9.0, t * 0.9));
	float streak = s1 * 0.5 + s2 * 0.3 + s3 * 0.2;
	float down = clamp(u, 0.0, 1.0);
	// Air: glassy over the lip, white from a few metres down.
	float air = smoothstep(0.02, 0.35, down + (s3 - 0.5) * 0.15);
	// The sheet breaks into strands with gaps lower down, more on a high fall.
	float gaps = smoothstep(0.25, 1.0, down) * (0.35 + COLOR.g * 0.5);
	float a = smoothstep(gaps - 0.05, gaps + 0.25, streak);
	// Ragged at the sides, where the water thins over the rocks.
	float rag = 0.08 + vn(vec2(fallen * 0.7 + TIME * 0.3, side * 9.0)) * 0.12;
	a *= smoothstep(0.0, rag, side) * smoothstep(0.0, rag, 1.0 - side);
	// Into the foam at the foot, and in from the river on the tongue.
	a *= 1.0 - smoothstep(0.93, 1.0, down) * 0.85;
	a *= smoothstep(-1.0, -0.4, u);
	vec3 glass = vec3(0.08, 0.13, 0.11);
	vec3 white = vec3(0.86, 0.89, 0.9) * (0.82 + streak * 0.25);
	vec3 col = mix(glass, white, air * (0.75 + s2 * 0.35));
	float alpha = a * mix(0.82, 0.95, air);
	if (layer > 0.5) {
		// Spray: a veil of fine drops, thinnest at the top and gone at the sides.
		float veil = vn(vec2(across * 1.3 + 17.0, t * 1.6)) * vn(vec2(across * 4.0, t * 3.5 + 3.0));
		alpha = smoothstep(0.08, 0.5, veil) * smoothstep(0.05, 0.6, down) * 0.35 * smoothstep(0.0, 0.2, side) * smoothstep(0.0, 0.2, 1.0 - side);
		col = vec3(0.88, 0.9, 0.92);
	}
	// Ripples on the face, from the streaks' slope across the sheet.
	float e = 0.15;
	float ds = (vn(vec2((across + e) * 2.1 + layer * 31.0, t * 2.4)) - s1) / e;
	NORMAL = normalize(NORMAL + TANGENT * ds * 0.35 * (1.0 - air * 0.6));
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.55, air);
	SPECULAR = 0.5;
	// Light through the thin water and the spray.
	BACKLIGHT = vec3(0.35, 0.4, 0.4) * (0.4 + air * 0.6);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
