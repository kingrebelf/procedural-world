shader_type spatial;
// Era-blended terrain. Vertex COLOR.rgb carries the era weights (medieval, fantasy,
// sci-fi) baked into the chunk snapshot. Detail is procedural and in world space, so
// there are no texture seams between chunks.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_m : source_color = vec3(0.24, 0.36, 0.12);
uniform vec3 soil_m : source_color = vec3(0.36, 0.28, 0.18);
uniform vec3 rock_m : source_color = vec3(0.55, 0.53, 0.49);
uniform vec3 grass_f : source_color = vec3(0.10, 0.34, 0.33);
uniform vec3 soil_f : source_color = vec3(0.22, 0.14, 0.28);
uniform vec3 rock_f : source_color = vec3(0.36, 0.33, 0.45);
uniform vec3 grass_s : source_color = vec3(0.20, 0.21, 0.22);
uniform vec3 soil_s : source_color = vec3(0.13, 0.13, 0.15);
uniform vec3 rock_s : source_color = vec3(0.42, 0.44, 0.47);
uniform vec3 glow_f : source_color = vec3(0.35, 0.9, 0.8);
uniform vec3 glow_s : source_color = vec3(0.2, 0.8, 1.0);
uniform float detail_strength = 0.6;
uniform float night_glow = 1.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = COLOR.rgb;
	w /= max(w.r + w.g + w.b, 0.001);
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	vec2 p = wpos.xz;

	// Multi-scale variation: macro patches, meso clumps, micro grain.
	float macro = fbm(p * 0.015);
	float meso = fbm(p * 0.18);
	float micro = vnoise(p * 3.1) * 0.5 + vnoise(p * 7.3) * 0.5;

	vec3 grass = grass_m * w.r + grass_f * w.g + grass_s * w.b;
	vec3 soil = soil_m * w.r + soil_f * w.g + soil_s * w.b;
	vec3 rock = rock_m * w.r + rock_f * w.g + rock_s * w.b;

	// Rock strata on steep faces (triplanar-ish: use height and horizontal position).
	float strata = fbm(vec2(wpos.y * 0.9, (wpos.x + wpos.z) * 0.05));
	rock *= 0.75 + 0.5 * strata;

	float soil_mask = smoothstep(0.45, 0.75, macro + (meso - 0.5) * 0.4);
	vec3 ground = mix(grass * (0.8 + 0.4 * meso), soil * (0.85 + 0.3 * micro), soil_mask * 0.7);
	float rock_mask = smoothstep(0.32, 0.52, slope + (meso - 0.5) * 0.18);
	vec3 col = mix(ground, rock, rock_mask);

	// Sci-fi: alloy plating with panel seams on flat ground.
	float plates = 0.0;
	if (w.b > 0.01) {
		vec2 g = fract(p / 4.0);
		vec2 id = floor(p / 4.0);
		float seam = 1.0 - smoothstep(0.0, 0.025, min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)));
		float flat_ = 1.0 - rock_mask;
		plates = w.b * flat_ * step(0.45, fbm(id * 0.13));
		col = mix(col, vec3(0.30, 0.31, 0.33) * (0.8 + 0.4 * hash12(id)), plates * 0.85);
		col *= 1.0 - seam * plates * 0.6;
		float lines = seam * plates * step(0.82, hash12(id + 3.0));
		EMISSION += glow_s * lines * 2.2 * night_glow;
	}

	// Fantasy: bioluminescent spores in the moss.
	if (w.g > 0.01) {
		float spores = smoothstep(0.86, 0.97, vnoise(p * 1.7)) * (1.0 - rock_mask);
		EMISSION += glow_f * spores * w.g * 1.6 * night_glow;
		col = mix(col, col * vec3(0.9, 1.0, 1.15), w.g * 0.3);
	}

	ALBEDO = col * (0.92 + 0.16 * micro);
	ROUGHNESS = mix(0.92, 0.55, plates) - 0.1 * rock_mask * w.b;
	METALLIC = plates * 0.6;
	SPECULAR = 0.4;

	// Procedural detail normal from the noise gradient (world space -> view space).
	float e = 0.15;
	float h0 = fbm(p * 0.9);
	float hx = fbm((p + vec2(e, 0.0)) * 0.9);
	float hz = fbm((p + vec2(0.0, e)) * 0.9);
	float rs = 1.0 + rock_mask * 1.5;
	vec3 dn = normalize(vec3(-(hx - h0) / e * detail_strength * rs, 1.0, -(hz - h0) / e * detail_strength * rs));
	vec3 n = normalize(wnorm + vec3(dn.x, 0.0, dn.z) * (1.0 - plates * 0.8));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
