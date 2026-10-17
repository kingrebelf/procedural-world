shader_type spatial;
// Where a boat meets the water (BoatWater): foam lapping round the hull, the bow waves
// spreading back in a V and the churned wash behind the stern. Lies on the swell (the
// same waves as water.gdshader). COLOR.r says which part a vertex belongs to (0 the
// lapping foam, 0.5 a bow wave, 1 the stern wash), COLOR.g how strong that part is for
// this boat; UV.x runs along it (the foam: 1 at the bow), UV.y across.
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
		a = e * smoothstep(0.55, 0.85, n * 0.7 + lumps * 0.3 + e * 0.15) * mix(0.35, 0.7, speed * bow);
	} else {
		// UV can stray a hair outside 0..1 between vertices: never raise a negative to a power
		// (a NaN here poisons the auto exposure and washes out the whole view).
		float along = clamp(UV.x, 0.0, 1.0);
		float across = clamp(1.0 - abs(UV.y * 2.0 - 1.0), 0.0, 1.0);
		float fade = pow(1.0 - along, kind > 0.75 ? 1.2 : 1.6) * smoothstep(0.0, 0.04, along);
		float band = smoothstep(0.0, kind > 0.75 ? 0.7 : 0.45, across);
		float churn = kind > 0.75 ? vn(wpos.xz * 4.0 + TIME * 1.3) * 0.3 : 0.0;
		// Broken into crests along the arms, not a painted stripe.
		float crests = smoothstep(0.25, 0.75, vn(vec2(along * 30.0 - TIME * 0.5, UV.y * 3.0)));
		a = band * smoothstep(0.5, 0.85, n * 0.5 + crests * 0.5 + churn + band * 0.2) * fade * col.g * clamp(speed * 1.3, 0.0, 1.0) * 0.9;
	}
	if (isnan(a) || isinf(a)) {
		a = 0.0;
	}
	ALBEDO = vec3(0.78, 0.82, 0.84);
	ALPHA = clamp(a, 0.0, 0.8);
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
