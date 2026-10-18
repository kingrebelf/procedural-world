shader_type spatial;
// A rain puddle for the trailer's close-ups (tools/trailer_rain.gd): a still, dark mirror
// with a ragged edge, ringing out from each drop that lands in it. The drops are handed
// in by the script (local x, z, the moment it landed, strength) so every ring starts
// exactly where a drop is seen to hit.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float radius = 1.9;
uniform float now = 0.0;
uniform vec4 drops[24];

varying vec3 lp;

float h(vec2 p) {
	uvec2 v = uvec2(ivec2(floor(p)) + ivec2(1 << 20));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return float(v.x) * (1.0 / 4294967296.0);
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xz;
	float r = length(q) / radius;
	float edge = 0.72 + 0.22 * vn(q * 1.4 + 7.0) + 0.08 * vn(q * 5.0);
	if (r > edge) {
		discard;
	}
	vec2 tilt = vec2(0.0);
	for (int i = 0; i < 24; i++) {
		vec4 d = drops[i];
		float age = now - d.z;
		if (d.w <= 0.0 || age < 0.0 || age > 1.8) {
			continue;
		}
		vec2 dd = q - d.xy;
		float rr = length(dd);
		// Capillary rings: a short train of ripples running out at about 25 cm/s.
		float x = rr - age * 0.25;
		float wave = sin(x * 230.0) * exp(-x * x * 1800.0) * exp(-age * 2.4) * d.w;
		tilt += dd / max(rr, 0.0005) * wave;
	}
	// Shallower near its ragged rim, where the ground's grain breaks the surface.
	float rim = smoothstep(edge, edge - 0.08, r);
	vec3 n = normalize(vec3(-tilt.x * 0.9, 1.0, -tilt.y * 0.9));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(vec3(0.06, 0.055, 0.05), vec3(0.015, 0.017, 0.02), rim);
	ROUGHNESS = mix(0.35, 0.02, rim);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
