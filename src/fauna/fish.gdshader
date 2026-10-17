shader_type spatial;
// Fish (FishKit meshes, one metre long along +Z). The body swims by a wave running down to
// the tail; the markings are painted from UV (x: tail 0 .. snout 1, y: belly -1 .. back 1).
// INSTANCE_CUSTOM: r = species pattern + the individual's own shade as the fraction,
// g = its tail-beat phase (turns, run on by AquaticLife so a faster swimmer beats faster),
// b = how hard it is swimming (0..1), a = the individual's markings seed (0..1).
// COLOR.r marks fins, COLOR.g the paired fins.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float night_glow_g;
varying vec2 uvp;
varying float fin;
varying float pattern;
varying float own;
varying float seed;

void vertex() {
	pattern = floor(INSTANCE_CUSTOM.r + 0.001);
	own = INSTANCE_CUSTOM.r - pattern;
	seed = INSTANCE_CUSTOM.a;
	fin = COLOR.r;
	uvp = UV;
	float z = VERTEX.z;
	// The swimming wave: small at the head, sweeping wide at the tail.
	float tail = clamp(0.45 - z, 0.0, 1.0);
	float amp = (0.015 + 0.13 * tail * tail) * (0.45 + 0.55 * INSTANCE_CUSTOM.b);
	float w = sin(TAU * INSTANCE_CUSTOM.g - z * 6.5);
	VERTEX.x += amp * w;
	// The body turns with the wave, so its sides stay smooth.
	NORMAL.x -= amp * 6.5 * cos(TAU * INSTANCE_CUSTOM.g - z * 6.5) * 0.3;
	// Paired fins scull.
	if (COLOR.g > 0.5) {
		VERTEX.y += sin(TAU * INSTANCE_CUSTOM.g * 1.6 + 1.0) * 0.012 * (abs(VERTEX.x) * 8.0 + 0.2);
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Dark round spots on a jittered grid (trout, pike).
float spots(vec2 p, float size) {
	vec2 c = floor(p);
	float best = 1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = c + vec2(float(i), float(j));
			vec2 o = vec2(hash(g + seed * 13.0), hash(g + 7.1 + seed * 5.0));
			best = min(best, length(p - g - o));
		}
	}
	return 1.0 - smoothstep(size * 0.7, size, best);
}

void fragment() {
	float u = uvp.x;
	float v = clamp(uvp.y, -1.0, 1.0);
	int p = int(pattern);
	// Back, flank, belly colours and how silvery the flank is.
	vec3 back = vec3(0.2, 0.25, 0.18);
	vec3 flank = vec3(0.55, 0.55, 0.45);
	vec3 belly = vec3(0.85, 0.84, 0.78);
	float silver = 0.2;
	vec3 mark = vec3(0.05);
	float marks = 0.0;
	vec3 fins = vec3(0.0); // 0: fins take the body colour
	if (p == 0) { // sardine / herring
		back = vec3(0.08, 0.2, 0.3); flank = vec3(0.7, 0.74, 0.76); belly = vec3(0.9); silver = 0.85;
	} else if (p == 1) { // mackerel: wavy dark bars over a blue-green back
		back = vec3(0.1, 0.3, 0.32); flank = vec3(0.68, 0.72, 0.72); belly = vec3(0.9); silver = 0.7;
		marks = step(0.25, v) * smoothstep(0.35, 0.6, sin(u * 70.0 + sin(v * 9.0 + seed * 6.0) * 1.6));
		mark = vec3(0.03, 0.05, 0.07);
	} else if (p == 2) { // perch: olive with dark bars, orange-red lower fins
		back = vec3(0.2, 0.26, 0.1); flank = vec3(0.5, 0.52, 0.24); belly = vec3(0.82, 0.8, 0.62); silver = 0.15;
		marks = step(-0.35, v) * smoothstep(0.3, 0.7, sin(u * 34.0 + seed * 3.0)) * step(0.22, u) * step(u, 0.82);
		mark = vec3(0.07, 0.09, 0.04);
		fins = v < -0.5 || uvp.x < 0.0 ? vec3(0.8, 0.3, 0.12) : vec3(0.0);
	} else if (p == 3) { // brown trout: spotted, with a rosy band
		back = vec3(0.22, 0.2, 0.12); flank = vec3(0.6, 0.5, 0.32); belly = vec3(0.86, 0.8, 0.62); silver = 0.25;
		flank = mix(flank, vec3(0.75, 0.45, 0.4), (1.0 - smoothstep(0.0, 0.25, abs(v - 0.05))) * 0.5);
		marks = spots(vec2(u * 28.0, v * 7.0), 0.33) * step(-0.3, v);
		mark = mix(vec3(0.06), vec3(0.6, 0.12, 0.08), step(0.7, hash(floor(vec2(u * 28.0, v * 7.0)))));
	} else if (p == 4) { // carp: bronze, its big scales edged dark
		back = vec3(0.24, 0.2, 0.1); flank = vec3(0.62, 0.48, 0.2); belly = vec3(0.82, 0.72, 0.5); silver = 0.45;
		vec2 sc = vec2(u * 26.0, v * 6.0 + floor(u * 26.0) * 0.5);
		marks = smoothstep(0.32, 0.48, length(fract(sc) - 0.5)) * 0.6;
		mark = vec3(0.15, 0.1, 0.05);
	} else if (p == 5) { // minnow: olive with a dark line down the side
		back = vec3(0.2, 0.22, 0.14); flank = vec3(0.55, 0.55, 0.42); belly = vec3(0.86, 0.82, 0.72); silver = 0.4;
		marks = 1.0 - smoothstep(0.04, 0.12, abs(v - 0.05));
		mark = vec3(0.08, 0.08, 0.06);
	} else if (p == 6) { // sea bream: silver-grey with faint gold lines
		back = vec3(0.3, 0.32, 0.34); flank = vec3(0.7, 0.72, 0.72); belly = vec3(0.88); silver = 0.75;
		marks = step(0.8, fract(v * 7.0)) * 0.5 * step(-0.6, v);
		mark = vec3(0.75, 0.62, 0.3);
	} else if (p == 7) { // yellow tang
		back = vec3(0.92, 0.75, 0.1); flank = back; belly = vec3(0.95, 0.82, 0.25); silver = 0.0;
		marks = (1.0 - smoothstep(0.0, 0.03, abs(u - 0.08))) * step(abs(v), 0.4);
		mark = vec3(0.95);
	} else if (p == 8) { // damselfish: deep blue, yellow tail
		back = vec3(0.08, 0.16, 0.42); flank = vec3(0.12, 0.24, 0.55); belly = vec3(0.3, 0.4, 0.6); silver = 0.1;
		fins = uvp.x < 0.02 ? vec3(0.95, 0.78, 0.1) : vec3(0.0);
	} else if (p == 9) { // clownfish: orange, three white bands edged black
		back = vec3(0.95, 0.4, 0.06); flank = back; belly = vec3(0.95, 0.5, 0.15); silver = 0.0;
		float band = 0.0;
		for (int i = 0; i < 3; i++) {
			float c = 0.78 - float(i) * 0.3;
			float d = abs(u - c) - (i == 1 ? 0.06 : 0.04);
			band = max(band, 1.0 - smoothstep(0.0, 0.012, d));
			marks = max(marks, (1.0 - smoothstep(0.012, 0.03, abs(d))) * step(-0.012, d));
		}
		flank = mix(flank, vec3(0.95), band);
		back = flank;
		belly = mix(belly, vec3(0.95), band);
		mark = vec3(0.02);
		fins = fin > 0.5 ? vec3(0.95, 0.42, 0.08) : vec3(0.0);
	} else if (p == 10) { // parrotfish: sea green, each scale edged pink
		back = vec3(0.1, 0.5, 0.42); flank = vec3(0.2, 0.62, 0.5); belly = vec3(0.4, 0.7, 0.6); silver = 0.1;
		vec2 sc = vec2(u * 22.0, v * 5.0 + floor(u * 22.0) * 0.5);
		marks = smoothstep(0.32, 0.46, length(fract(sc) - 0.5));
		mark = vec3(0.85, 0.45, 0.55);
		fins = fin > 0.5 ? vec3(0.8, 0.45, 0.6) : vec3(0.0);
	} else if (p == 12) { // pike: green, barred with pale spots
		back = vec3(0.12, 0.2, 0.08); flank = vec3(0.3, 0.42, 0.16); belly = vec3(0.85, 0.82, 0.65); silver = 0.15;
		marks = spots(vec2(u * 30.0, v * 6.0), 0.3) * step(-0.4, v);
		mark = vec3(0.75, 0.72, 0.45);
	} else { // 11: an alien world's fish, iridescent and strange
		float h = fract(seed + u * 0.3);
		back = 0.5 + 0.5 * cos(TAU * (h + vec3(0.0, 0.33, 0.67)));
		back *= 0.4;
		flank = 0.5 + 0.5 * cos(TAU * (h + 0.4 + vec3(0.0, 0.33, 0.67)));
		belly = flank * 1.2;
		silver = 0.5;
		marks = spots(vec2(u * 18.0, v * 5.0), 0.3);
		mark = vec3(0.6, 1.0, 0.9);
	}
	// The individual's own shade: no two quite alike.
	float shade_j = 0.85 + own * 0.3;
	vec3 col = mix(belly, flank, smoothstep(-0.75, -0.1, v));
	col = mix(col, back, smoothstep(0.15, 0.85, v));
	col = mix(col, mark, clamp(marks, 0.0, 1.0)) * shade_j;
	bool is_fin = fin > 0.5;
	if (is_fin) {
		col = (fins.r + fins.g + fins.b > 0.0 ? fins : mix(flank, back, 0.5)) * 0.8;
	}
	// The eye: a dark pupil in a gold or silver ring, behind the snout.
	float e = length(vec2((u - 0.885) * 5.5, (v - 0.25) * 1.6));
	if (!is_fin && e < 0.2) {
		col = mix(vec3(0.8, 0.7, 0.4) * 0.7, vec3(0.01), 1.0 - smoothstep(0.1, 0.13, e));
	}
	// Gill cover: a faint darker curve.
	if (!is_fin) {
		col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.012, abs(u - 0.78 + v * v * 0.04))) * step(abs(v), 0.85);
	}
	ALBEDO = pow(col, vec3(2.2));
	METALLIC = is_fin ? 0.0 : silver * smoothstep(0.6, -0.4, v) * 0.7;
	ROUGHNESS = is_fin ? 0.6 : mix(0.45, 0.22, silver);
	SPECULAR = 0.6;
	BACKLIGHT = is_fin ? ALBEDO * 0.6 : vec3(0.0);
	if (is_fin && dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	if (p == 11) {
		EMISSION = mark * marks * night_glow_g * 1.5;
	}
}
