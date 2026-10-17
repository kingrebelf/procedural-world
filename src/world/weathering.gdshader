shader_type spatial;
// Weathering laid over old masonry on a card just proud of the face: damp, moss and
// splashed earth rising from the ground (COLOR.r > 0.5), or rain streaks running down
// from a parapet (COLOR.r < 0.5). UV.y runs 0 at the card's top to 1 at its foot. The
// pattern follows world position, so no two wall sections weather alike.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

varying vec3 wpos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13) * 0.3 + vnoise(p * 4.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = UV.y;
	float a;
	vec3 col;
	if (COLOR.r > 0.5) {
		// From the ground up: darkest and greenest at the foot, a ragged upper edge.
		float n = fbm(wpos * vec3(0.55, 0.9, 0.55));
		float edge = 0.3 + 0.6 * n;
		a = (1.0 - smoothstep(edge - 0.25, edge + 0.08, 1.0 - h));
		float moss = smoothstep(0.45, 0.7, fbm(wpos * 1.7 + 11.0)) * smoothstep(0.35, 0.9, h);
		col = mix(vec3(0.17, 0.15, 0.12), vec3(0.17, 0.24, 0.08), moss);
		col *= 0.85 + 0.3 * vnoise(wpos * 6.0);
		a *= mix(0.9, 1.0, moss);
	} else {
		// Streaks from the top: narrow columns, long and short.
		float s = fbm(vec3(wpos.x * 3.1, wpos.y * 0.12, wpos.z * 3.1));
		float len = 0.15 + 0.85 * fbm(vec3(wpos.x * 0.9, 3.0, wpos.z * 0.9));
		a = smoothstep(0.5, 0.75, s) * (1.0 - smoothstep(len * 0.5, len, h));
		a = max(a, 0.35 * (1.0 - smoothstep(0.0, 0.18, h)));
		col = vec3(0.16, 0.15, 0.13) * (0.85 + 0.3 * vnoise(wpos * 4.0));
		a *= 0.75;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
