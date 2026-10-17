// The swell on lakes and seas: a sum of four directional deep-water waves running with
// the wind, larger over deep water and in a strong wind. The one copy every shader that
// lies on the water includes (the water itself, the foam round boats), so they move
// together. Must match Water.surface_height() and Water.amplitude(), which boats and
// swimmers float on: change all three together.
// Needs `global uniform vec2 wind_dir` and `global uniform float wind_strength`.

vec2 swell_rot(vec2 v, float a) { return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)); }

// How tall the swell runs over water `depth` metres deep (Water.amplitude()).
float swell_amp(float depth) {
	float open = smoothstep(0.5, 14.0, depth);
	return (0.04 + wind_strength * wind_strength * 1.1) * (0.15 + 0.85 * open);
}

// Height above the water level at p, time t, scaled by a (swell_amp); then its xz gradient.
vec3 swell(vec2 p, float t, float a) {
	vec2 d = normalize(wind_dir + vec2(0.0001));
	vec2 dirs[4] = vec2[](d, swell_rot(d, 0.6), swell_rot(d, -0.45), swell_rot(d, 1.3));
	float lens[4] = float[](38.0, 21.0, 13.0, 7.0);
	float amps[4] = float[](0.5, 0.28, 0.15, 0.07);
	vec3 r = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float k = 6.2831853 / lens[i];
		float c = sqrt(9.8 / k);
		float ph = k * (dot(p, dirs[i]) - c * t);
		r.x += amps[i] * sin(ph);
		r.yz += amps[i] * k * cos(ph) * dirs[i];
	}
	return r * a;
}
