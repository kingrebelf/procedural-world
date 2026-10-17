shader_type spatial;
// A planet seen from orbit: continents, seas, ice caps and drifting clouds from 3D noise
// on the sphere, coloured per planet kind (Planets.KINDS). Lit by the system's sun, so a
// terminator crosses it: a ruddy twilight band along it, and on the night side the lights
// of towns (human worlds) or a faint living glow (alien ones). Mountains stand out in
// relief where the light rakes across them; the seas catch the sun.

uniform vec3 sea_col : source_color = vec3(0.08, 0.22, 0.38);
uniform vec3 land_col : source_color = vec3(0.28, 0.42, 0.2);
uniform vec3 land2_col : source_color = vec3(0.45, 0.38, 0.28);
uniform float ice = 0.12;
uniform float land_level = 0.5;
uniform vec3 seed_off = vec3(0.0);
uniform float time_s = 0.0;
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.7); // world space, toward the sun
uniform vec3 air : source_color = vec3(0.45, 0.65, 1.0);
// Night lights: their colour and how many (0 none).
uniform vec3 lights_col : source_color = vec3(1.0, 0.72, 0.38);
uniform float lights = 0.0;
// Relief: how far mountains tilt the light (0 flat).
uniform float relief = 1.0;

varying vec3 objn;
varying vec3 world_n;

void vertex() {
	objn = normalize(VERTEX);
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

// Ridged noise for mountain chains: sharp crests, soft valleys.
float ridged(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		float n = 1.0 - abs(noise(p) * 2.0 - 1.0);
		s += a * n * n;
		p *= 2.1;
		a *= 0.5;
	}
	return s;
}

// Town lights: a scatter of points (one chance per cell, likelier where `pop` is high),
// each a small soft dot.
float towns(vec3 p, float cells, float pop) {
	vec3 g = p * cells;
	vec3 c = floor(g);
	float h = hash(c + 7.3);
	if (h > pop) {
		return 0.0;
	}
	vec3 at = c + 0.5 + (vec3(hash(c + 1.7), hash(c + 4.1), hash(c + 9.2)) - 0.5) * 0.6;
	float d = length(g - at);
	return (1.0 - smoothstep(0.04, 0.3, d)) * (0.45 + 0.55 * hash(c + 3.3));
}

void fragment() {
	vec3 p = objn * 2.2 + seed_off;
	// The coasts wander (a warped field), so continents aren't round blobs.
	vec3 q = p + vec3(fbm(p * 1.3 + 11.0), fbm(p * 1.3 + 23.0), fbm(p * 1.3 + 37.0)) * 0.55;
	float h = fbm(q);
	float landm = smoothstep(land_level - 0.002, land_level + 0.004, h + (noise(q * 40.0) - 0.5) * 0.006);
	float lat = abs(objn.y);
	float alt = h - land_level;
	// Mountain chains along inland ridges.
	float chain = ridged(q * 3.1 + 17.0) * smoothstep(0.02, 0.12, alt);
	// Dry belts either side of the equator, green between, paler tundra toward the poles;
	// forest in darker drifts.
	float dry = smoothstep(0.45, 0.72, fbm(q * 2.7 + 3.0) + (0.2 - abs(lat - 0.3)) * 0.9);
	vec3 land = mix(land_col, land2_col, dry);
	float forest = smoothstep(0.48, 0.66, fbm(q * 6.0 + 41.0)) * (1.0 - dry) * (1.0 - smoothstep(0.5, 0.75, lat));
	land = mix(land, land * vec3(0.62, 0.72, 0.6), forest);
	// Sand seas in the driest hearts of the belts.
	land = mix(land, land2_col * vec3(1.35, 1.22, 1.0) + 0.05, smoothstep(0.75, 0.95, dry + (fbm(q * 11.0) - 0.5) * 0.3) * 0.7);
	land = mix(land, land * 0.75 + vec3(0.1), smoothstep(0.55, 0.8, lat));
	// Mountains: darker rock, snow on the highest crests.
	float rock = clamp(smoothstep(0.07, 0.15, alt) + smoothstep(0.25, 0.6, chain), 0.0, 1.0);
	land = mix(land, land2_col * 0.55 + vec3(0.04), rock * 0.85);
	land = mix(land, vec3(0.9), clamp(smoothstep(0.16, 0.21, alt) + smoothstep(0.6, 0.8, chain), 0.0, 1.0) * 0.85);
	land *= 0.8 + 0.4 * fbm(q * 9.0) * (0.85 + 0.3 * noise(q * 37.0));
	// Sea: pale shelves round the coasts, dark open ocean.
	float shelf = smoothstep(land_level - 0.05, land_level, h);
	vec3 sea = mix(sea_col * 0.55, mix(sea_col, vec3(0.16, 0.42, 0.48), 0.35) * 1.15, shelf * shelf * 0.8);
	vec3 col = mix(sea, land, landm);
	float icem = smoothstep(1.0 - ice - 0.04, 1.0 - ice + 0.02, lat + (fbm(p * 3.0) - 0.5) * 0.18);
	col = mix(col, vec3(0.9, 0.94, 1.0), icem);
	// Clouds: swirled by the winds into bands and eddies, their edges broken into cells,
	// thin streaks of high cloud, and their shadows a little to the side on the ground.
	vec3 cp = objn * 3.2 + vec3(time_s * 0.004, 0.0, time_s * 0.002) + seed_off * 1.7;
	cp.y *= 1.6;
	vec3 cw = cp + vec3(fbm(cp * 0.8 + 5.0), fbm(cp * 0.8 + 9.0), fbm(cp * 0.8 + 13.0)) * 1.2;
	float detail = (fbm(cw * 4.0) - 0.5) * 0.16 + (noise(cw * 19.0) - 0.5) * 0.06;
	float c = fbm(cw) + detail;
	float cl = smoothstep(0.54, 0.62, c);
	// Cirrus: long thin streaks along the wind.
	float cirrus = smoothstep(0.62, 0.82, fbm(cw * vec3(1.6, 5.0, 1.6) + 31.0 + vec3(0.0, fbm(cw * 2.0) * 1.5, 0.0))) * 0.3 * (1.0 - cl);
	vec3 sun_o = normalize((inverse(MODEL_MATRIX) * vec4(sun_dir, 0.0)).xyz);
	float cs = fbm(cw + (sun_o - objn * dot(sun_o, objn)) * 0.05) + detail;
	col *= 1.0 - 0.45 * smoothstep(0.54, 0.62, cs) * (1.0 - cl);
	// Thick cloud is brighter on top; its thinner edges let the ground through.
	float thick = smoothstep(0.56, 0.72, c);
	col = mix(col, vec3(0.97), cl * (0.8 + 0.18 * thick));
	col = mix(col, vec3(0.92, 0.95, 1.0), cirrus);
	float cover = max(cl, cirrus);

	// Relief: tilt the normal by the slope of the land (bump from screen-space slopes), so
	// mountains throw light and shade where the sun is low.
	float hb = (alt * 2.0 + chain * 0.8) * landm * relief * (1.0 - cover) * (1.0 - icem * 0.6);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(hb) * r1 + dFdy(hb) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);

	// Seen through the air: a haze of its colour toward the limb (the rim shell adds the
	// scattered light itself).
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, air * 0.7, pow(1.0 - ndv, 3.0) * 0.4);
	ALBEDO = col;
	float sea_m = (1.0 - landm) * (1.0 - icem) * (1.0 - cover);
	ROUGHNESS = mix(0.9, 0.11, sea_m);
	SPECULAR = mix(0.25, 0.75, sea_m);

	// Day and night: how squarely the sun stands over this point.
	float nl = dot(normalize(world_n), sun_dir);
	// Twilight: a ruddy band along the terminator, lit by sun through the air.
	float twi = smoothstep(-0.16, 0.0, nl) * (1.0 - smoothstep(0.0, 0.14, nl));
	vec3 glow = col * vec3(1.0, 0.45, 0.22) * twi * 0.12;
	// The night side: towns along the coasts of the temperate lands, dimmed by cloud.
	float night = smoothstep(0.0, -0.14, nl);
	if (lights > 0.0 && night > 0.0) {
		float coast = 1.0 - smoothstep(0.0, 0.05, alt);
		float pop = landm * (1.0 - icem) * (1.0 - smoothstep(0.5, 0.7, lat)) * (1.0 - rock) * (0.3 + 0.7 * coast) * (0.6 + 0.4 * (1.0 - dry));
		pop *= smoothstep(0.35, 0.6, fbm(q * 5.0 + 71.0));
		float t = towns(objn, 90.0, pop * 0.7) + towns(objn, 240.0, pop * 0.55) * 0.6 + towns(objn + 0.37, 600.0, pop * 0.4) * 0.35;
		glow += lights_col * t * lights * night * (1.0 - cover * 0.85) * 1.5;
	}
	EMISSION = glow;
}
