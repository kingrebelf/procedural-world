shader_type spatial;
// Where a boat meets the water: foam lapping round the hull (BoatWater), and the wake she
// leaves (BoatWake). Lies on the swell (the same waves as water.gdshader). COLOR.r says
// which part a vertex belongs to: 0 the lapping foam (UV.x 1 at the bow, UV.y out from the
// hull), 0.5 a Kelvin arm, 0.75 the transverse waves, 1 the wash; for the wake COLOR.g is
// how strong it still is, UV.y runs across the strip, UV2.x is metres back along the
// track and UV2.y the transverse waves' phase.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

global uniform vec2 wind_dir;
global uniform float wind_strength;
instance uniform float speed = 0.0; // 0 still .. 1 at full pace

varying vec3 wpos;
varying vec4 col;

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}
float h(vec2 p) { return float(pcg2d(uvec2(ivec2(floor(p)))).x) * (1.0 / 4294967296.0); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
vec2 rot(vec2 v, float a) { return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)); }

// Must match Water.surface_height() (open water).
float swell(vec2 p, float t) {
	vec2 d = normalize(wind_dir + vec2(0.0001));
	vec2 dirs[4] = vec2[](d, rot(d, 0.6), rot(d, -0.45), rot(d, 1.3));
	float lens[4] = float[](38.0, 21.0, 13.0, 7.0);
	float amps[4] = float[](0.5, 0.28, 0.15, 0.07);
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		float k = 6.2831853 / lens[i];
		r += amps[i] * sin(k * (dot(p, dirs[i]) - sqrt(9.8 / k) * t));
	}
	return r * (0.04 + wind_strength * wind_strength * 1.1);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float y = swell(wpos.xz, TIME) + 0.035;
	VERTEX.y += y - wpos.y;
	wpos.y = y;
	col = COLOR;
}

void fragment() {
	float kind = col.r;
	float n = vn(wpos.xz * 2.2 + vec2(TIME * 0.35, -TIME * 0.2)) * 0.55 + vn(wpos.xz * 7.0 - TIME * 0.6) * 0.3 + vn(wpos.xz * 19.0 + TIME) * 0.15;
	float a = 0.0;
	if (kind < 0.25) {
		// Lapping at the hull: always a thin broken line, a white cushion at the bow under way.
		float edge = clamp(1.0 - UV.y, 0.0, 1.0);
		float bow = clamp(UV.x, 0.0, 1.0);
		bow *= bow;
		float reach = mix(0.7, 1.0, clamp(speed * (0.25 + 0.75 * bow) * 1.4, 0.0, 1.0));
		float e = smoothstep(1.0 - reach, 1.0, edge);
		// Patchy and see-through: lumps of foam with clear water between.
		float lumps = vn(wpos.xz * 1.3 - TIME * 0.15);
		a = e * smoothstep(0.55, 0.85, n * 0.7 + lumps * 0.3 + e * 0.15) * mix(0.22, 0.7, speed * bow);
	} else {
		// UV can stray a hair outside 0..1 between vertices: never raise a negative to a power
		// (a NaN here poisons the auto exposure and washes out the whole view).
		float across = clamp(UV.y, 0.0, 1.0);
		float mid = clamp(1.0 - abs(across * 2.0 - 1.0), 0.0, 1.0);
		float back = max(UV2.x, 0.0);
		float f = clamp(col.g, 0.0, 1.0);
		if (kind < 0.6) {
			// A Kelvin arm: a row of short crests slanting out from the track (the feathers a
			// real wake is made of), breaking white close behind her, rippled further back.
			float band = smoothstep(0.0, 0.55, mid);
			// Unevenly spaced, each one broken, some stretches stronger than others.
			float wob = vn(vec2(back * 0.35, 3.7)) * 5.0;
			float feathers = 0.5 + 0.5 * sin(back * 1.7 + wob + (across - 0.5) * 6.0 - TIME * 1.3);
			feathers = smoothstep(0.45, 0.97, feathers) * smoothstep(0.25, 0.65, vn(vec2(back * 0.9, across * 4.0 + TIME * 0.2)));
			float swell_of_it = 0.55 + 0.45 * vn(vec2(back * 0.12, 9.1));
			float whiten = mix(1.0, 0.3, smoothstep(4.0, 45.0, back));
			a = band * smoothstep(0.4, 0.85, n * 0.4 + feathers * 0.5 + band * 0.15) * f * whiten * swell_of_it * 0.9;
		} else if (kind < 0.85) {
			// Transverse waves: curved crests across her track (bowed back at the middle),
			// marked by thin foam lines and slicks rather than painted bands.
			float bow = (across - 0.5) * (across - 0.5);
			float crest = 0.5 + 0.5 * cos(6.2831853 * (UV2.y + bow * 1.4));
			crest = smoothstep(0.82, 1.0, crest);
			float edges = smoothstep(0.0, 0.2, mid);
			a = crest * edges * smoothstep(0.35, 0.75, n) * f * 0.35;
		} else {
			// The wash: churned white close astern, settling into a smooth slick with drifting
			// lace of old foam.
			float churn = vn(wpos.xz * 3.0 + TIME * 1.1) * 0.6 + vn(wpos.xz * 9.0 - TIME * 1.7) * 0.4;
			float fresh = 1.0 - smoothstep(0.0, 30.0, back);
			float band = smoothstep(0.0, mix(0.9, 0.5, fresh), mid);
			float lace = smoothstep(0.62, 0.8, vn(wpos.xz * 1.6 + vec2(back * 0.1, 0.0)) * 0.6 + n * 0.4);
			a = band * f * (fresh * smoothstep(0.3, 0.7, churn * 0.7 + band * 0.3) * 0.85 + (1.0 - fresh) * lace * 0.45);
		}
	}
	if (isnan(a) || isinf(a)) {
		a = 0.0;
	}
	ALBEDO = vec3(0.78, 0.82, 0.84);
	ALPHA = clamp(a, 0.0, 0.8);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
