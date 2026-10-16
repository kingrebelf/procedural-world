shader_type spatial;
// A planet seen from orbit: continents, seas, ice caps and drifting clouds from 3D noise
// on the sphere, coloured per planet kind (Planets.KINDS).

uniform vec3 sea_col : source_color = vec3(0.08, 0.22, 0.38);
uniform vec3 land_col : source_color = vec3(0.28, 0.42, 0.2);
uniform vec3 land2_col : source_color = vec3(0.45, 0.38, 0.28);
uniform float ice = 0.12;
uniform float land_level = 0.5;
uniform vec3 seed_off = vec3(0.0);
uniform float time_s = 0.0;

varying vec3 objn;

void vertex() {
	objn = normalize(VERTEX);
}

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

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 6; i++) {
		s += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec3 p = objn * 2.2 + seed_off;
	float h = fbm(p);
	float landm = smoothstep(land_level - 0.01, land_level + 0.02, h);
	vec3 land = mix(land_col, land2_col, smoothstep(0.45, 0.7, fbm(p * 2.7 + 3.0)));
	land *= 0.8 + 0.5 * (h - land_level);
	vec3 col = mix(sea_col * (0.65 + 0.7 * h), land, landm);
	float lat = abs(objn.y);
	float icem = smoothstep(1.0 - ice - 0.04, 1.0 - ice + 0.02, lat + (fbm(p * 3.0) - 0.5) * 0.18);
	col = mix(col, vec3(0.9, 0.94, 1.0), icem);
	float c = fbm(objn * 3.2 + vec3(time_s * 0.004, 0.0, time_s * 0.002) + seed_off * 1.7);
	float cl = smoothstep(0.52, 0.72, c);
	col = mix(col, vec3(0.97), cl * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.9, max(max(landm, cl), icem));
	SPECULAR = mix(0.7, 0.25, max(landm, cl));
}
