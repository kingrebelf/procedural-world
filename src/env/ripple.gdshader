shader_type spatial;
// A foam ring spreading on the water (Splashes): grows from the centre, thins and fades.
// age runs 0..1 over the ring's life. Broken up by noise so it reads as foam, not a hoop.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

instance uniform float age = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float t = age;
	float rad = 0.15 + 0.82 * (1.0 - (1.0 - t) * (1.0 - t)); // fast at first, then slowing
	float w = mix(0.16, 0.05, t);
	float band = 1.0 - smoothstep(0.0, w, abs(r - rad));
	// A fainter inner ring trailing the first.
	float rad2 = rad * 0.62;
	band = max(band, (1.0 - smoothstep(0.0, w * 0.8, abs(r - rad2))) * 0.45);
	float a = atan(q.y, q.x);
	float n = vn(vec2(a * 5.0, r * 6.0 + t * 2.0)) * 0.6 + vn(q * 9.0) * 0.4;
	float foam = band * smoothstep(0.25, 0.7, n) * (1.0 - t) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = vec3(0.9, 0.94, 0.97);
	ALPHA = foam * 0.75;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}
