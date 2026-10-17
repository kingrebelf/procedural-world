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
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.7); // world space, toward the sun
uniform vec3 air : source_color = vec3(0.45, 0.65, 1.0);

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
	// The coasts wander (a warped field), so continents aren't round blobs.
	vec3 q = p + vec3(fbm(p * 1.3 + 11.0), fbm(p * 1.3 + 23.0), fbm(p * 1.3 + 37.0)) * 0.55;
	float h = fbm(q);
	float landm = smoothstep(land_level - 0.004, land_level + 0.006, h);
	float lat = abs(objn.y);
	// Dry belts either side of the equator, green between, paler tundra toward the poles.
	float dry = smoothstep(0.45, 0.72, fbm(q * 2.7 + 3.0) + (0.2 - abs(lat - 0.3)) * 0.9);
	vec3 land = mix(land_col, land2_col, dry);
	land = mix(land, land * 0.75 + vec3(0.1), smoothstep(0.55, 0.8, lat));
	// Mountains: darker rock, snow on the highest.
	float alt = h - land_level;
	land = mix(land, land2_col * 0.55, smoothstep(0.07, 0.15, alt));
	land = mix(land, vec3(0.9), smoothstep(0.16, 0.21, alt) * 0.85);
	land *= 0.82 + 0.36 * fbm(q * 9.0);
	// Sea: pale shelves round the coasts, dark open ocean.
	float shelf = smoothstep(land_level - 0.05, land_level, h);
	vec3 sea = mix(sea_col * 0.55, mix(sea_col, vec3(0.16, 0.42, 0.48), 0.35) * 1.15, shelf * shelf * 0.8);
	vec3 col = mix(sea, land, landm);
	float icem = smoothstep(1.0 - ice - 0.04, 1.0 - ice + 0.02, lat + (fbm(p * 3.0) - 0.5) * 0.18);
	col = mix(col, vec3(0.9, 0.94, 1.0), icem);
	// Clouds: swirled by the winds into bands and eddies, with crisp edges, and their
	// shadows a little to the side on the ground below.
	vec3 cp = objn * 3.2 + vec3(time_s * 0.004, 0.0, time_s * 0.002) + seed_off * 1.7;
	cp.y *= 1.6;
	vec3 cw = cp + vec3(fbm(cp * 0.8 + 5.0), fbm(cp * 0.8 + 9.0), fbm(cp * 0.8 + 13.0)) * 1.2;
	float c = fbm(cw) + (fbm(cw * 4.0) - 0.5) * 0.14;
	float cl = smoothstep(0.55, 0.64, c);
	vec3 sun_o = normalize((inverse(MODEL_MATRIX) * vec4(sun_dir, 0.0)).xyz);
	float cs = fbm(cw + (sun_o - objn * dot(sun_o, objn)) * 0.05) + (fbm(cw * 4.0) - 0.5) * 0.14;
	col *= 1.0 - 0.4 * smoothstep(0.55, 0.64, cs) * (1.0 - cl);
	col = mix(col, vec3(0.96), cl * 0.92);
	// Seen through the air: a haze of its colour that thickens toward the limb.
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, air * 0.8, pow(1.0 - ndv, 2.2) * 0.55);
	ALBEDO = col;
	ROUGHNESS = mix(0.16, 0.9, max(max(landm, cl), icem));
	SPECULAR = mix(0.8, 0.2, max(landm, cl));
}
