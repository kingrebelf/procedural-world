shader_type sky;
// Deep space: scattered stars of a few sizes, faint nebulae and the system's sun.

uniform vec3 nebula_a : source_color = vec3(0.05, 0.02, 0.1);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.1, 0.16);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float stars(vec3 d, float cells, float density) {
	vec3 g = d * cells;
	vec3 c = floor(g);
	float h = hash(c);
	if (h < 1.0 - density) {
		return 0.0;
	}
	vec3 centre = c + 0.5 + (vec3(hash(c + 3.1), hash(c + 7.7), hash(c + 1.3)) - 0.5) * 0.6;
	float r = length(g - centre);
	return smoothstep(0.35, 0.0, r) * (0.4 + 0.6 * hash(c + 11.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float n = noise(d * 2.5) * 0.6 + noise(d * 6.0) * 0.3 + noise(d * 13.0) * 0.1;
	vec3 col = mix(nebula_a, nebula_b, smoothstep(0.3, 0.7, noise(d * 1.7 + 4.0))) * smoothstep(0.35, 0.75, n);
	col += vec3(stars(d, 220.0, 0.06)) * 0.9;
	col += vec3(0.8, 0.9, 1.0) * stars(d, 90.0, 0.015) * 1.6;
	float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += vec3(1.0, 0.92, 0.8) * (pow(s, 3000.0) * 30.0 + pow(s, 80.0) * 0.4 + pow(s, 8.0) * 0.05);
	COLOR = col;
}
