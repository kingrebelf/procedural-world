// The swell on lakes and seas: a long, low swell rolling in under four shorter wind waves,
// all running with the wind, larger over deep water and in a strong wind; plus the wakes
// boats leave (water_wake_map). The one copy every shader that lies on the water includes
// (the water itself, the foam round boats), so they move together. Must match
// Water.surface_height() and Water.amplitude(), which boats and swimmers float on: change
// all three together.
// Needs `global uniform vec2 wind_dir` and `global uniform float wind_strength`.

// Wakes: metres of height above (or below) the swell, over the square water_wake_rect
// (origin x, z, size; size 0 = no wakes). Boats write it (Water.set_wakes()).
global uniform sampler2D water_wake_map : filter_linear, repeat_disable;
global uniform vec4 water_wake_rect;
#include "res://src/env/water_wakes.gdshaderinc"

const int SWELL_N = 5;
const float SWELL_LENS[SWELL_N] = float[](64.0, 38.0, 21.0, 13.0, 7.0);
const float SWELL_AMPS[SWELL_N] = float[](0.5, 0.45, 0.35, 0.25, 0.14);
const float SWELL_TURN[SWELL_N] = float[](-0.2, 0.0, 0.6, -0.45, 1.3);

vec2 swell_rot(vec2 v, float a) { return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)); }

// How tall the swell runs over water `depth` metres deep (Water.amplitude()).
float swell_amp(float depth) {
	float open = smoothstep(0.5, 14.0, depth);
	return (0.18 + wind_strength * wind_strength * 1.2) * (0.15 + 0.85 * open);
}

// Height above the water level at p, time t, scaled by a (swell_amp); then its xz gradient.
vec3 swell(vec2 p, float t, float a) {
	vec2 d = normalize(wind_dir + vec2(0.0001));
	vec3 r = vec3(0.0);
	for (int i = 0; i < SWELL_N; i++) {
		vec2 dir = swell_rot(d, SWELL_TURN[i]);
		float k = 6.2831853 / SWELL_LENS[i];
		float c = sqrt(9.8 / k);
		float ph = k * (dot(p, dir) - c * t);
		r.x += SWELL_AMPS[i] * sin(ph);
		r.yz += SWELL_AMPS[i] * k * cos(ph) * dir;
	}
	return r * a;
}

// The wakes' height at p and its xz gradient: what was painted into the wake map (zero
// outside its square), plus the Kelvin waves of the boats under way (water_wakes).
vec3 wake(vec2 p) {
	vec3 r = boat_wakes(p);
	if (water_wake_rect.z <= 0.0) {
		return r;
	}
	vec2 uv = (p - water_wake_rect.xy) / water_wake_rect.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return r;
	}
	float px = 1.0 / float(textureSize(water_wake_map, 0).x);
	float h = clamp(textureLod(water_wake_map, uv, 0.0).r, -0.6, 0.6); // Water.WAKE_MAX
	float hx = textureLod(water_wake_map, uv + vec2(px, 0.0), 0.0).r;
	float hz = textureLod(water_wake_map, uv + vec2(0.0, px), 0.0).r;
	// Fade out at the square's rim, so a wake never stops on a line.
	vec2 rim = smoothstep(vec2(0.0), vec2(0.05), uv) * (1.0 - smoothstep(vec2(0.95), vec2(1.0), uv));
	float f = rim.x * rim.y;
	float cell = water_wake_rect.z * px;
	r += vec3(h, (hx - h) / cell, (hz - h) / cell) * f;
	r.x = clamp(r.x, -0.6, 0.6); // Water.WAKE_MAX
	return r;
}
