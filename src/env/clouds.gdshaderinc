// Shared by the sky (which draws the clouds) and the ground (which takes their shadows),
// so shadows fall where the clouds are.
global uniform vec2 cloud_drift; // metres the cloud field has moved with the wind
global uniform float cloud_cover_g;
global uniform vec3 sun_dir_g; // toward the sun

float c_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float c_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(c_hash(i), c_hash(i + vec3(1, 0, 0)), f.x), mix(c_hash(i + vec3(0, 1, 0)), c_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(c_hash(i + vec3(0, 0, 1)), c_hash(i + vec3(1, 0, 1)), f.x), mix(c_hash(i + vec3(0, 1, 1)), c_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float c_fbm(vec3 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		s += a * c_noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// Weather coverage (0..1) of the cloud field over world point q (already drifted).
float cloud_coverage(vec2 q, float cover) {
	float cov = c_fbm(vec3(q * 0.00018, 0.5), 3);
	return smoothstep(0.56 - cover * 0.4, 0.86 - cover * 0.3, cov);
}

// How much sunlight the clouds block at a ground point: 0 clear, ~1 under a thick cloud.
float cloud_shadow(vec3 wp) {
	if (sun_dir_g.y < 0.05) return 0.0;
	vec2 q = wp.xz + sun_dir_g.xz / sun_dir_g.y * (2200.0 - wp.y) + cloud_drift;
	float cov = cloud_coverage(q, cloud_cover_g);
	float lumps = c_noise(vec3(q.x, 2200.0 * 0.8, q.y) * 0.00045);
	return smoothstep(0.15, 0.6, cov * (0.55 + lumps * 0.7));
}

// How much a cloud's shadow darkens the ground under it: a gentle dip as a cloud passes
// over, not a blackout (at 0.42 the whole view went dim under every passing cloud).
const float CLOUD_SHADE = 0.2;
float cloud_shade(vec3 wp) {
	return 1.0 - CLOUD_SHADE * cloud_shadow(wp);
}
