// Raindrops on the water: each drop rings out from where it lands and fades, a scatter of
// small rings at random places and times, thicker the harder it rains. Tilts the surface
// (the reflections and what is seen through it ripple), nothing drawn on top.

// 0 dry .. 1 a downpour (Water feeds it from the weather each frame).
uniform float rain = 0.0;

vec2 rain_hash(vec2 c) {
	uvec2 v = uvec2(ivec2(c) + ivec2(1 << 20));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return vec2(v) * (1.0 / 4294967296.0);
}

// One layer of drops on a grid of `cell` metres: one drop per cell per cycle, the ring
// staying inside its cell so no neighbours need checking.
vec2 rain_layer(vec2 p, float t, float cell, float seed) {
	vec2 c = floor(p / cell);
	vec2 h = rain_hash(c + seed);
	// Not every cell gets a drop this cycle: fewer in a drizzle.
	float cycle = 0.9 + h.y * 0.5;
	float tt = t / cycle + h.x * 7.0;
	vec2 hh = rain_hash(c + floor(tt) * 31.0 + seed * 3.0);
	if (hh.x > rain) {
		return vec2(0.0);
	}
	vec2 centre = (c + 0.25 + hh * 0.5) * cell;
	float age = fract(tt);
	vec2 d = p - centre;
	float r = length(d);
	float front = age * cell * 0.45;
	float x = r - front;
	float env = exp(-x * x / 0.0016) * (1.0 - age) * (1.0 - age);
	return d / max(r, 0.001) * cos(x * 90.0) * env * 0.9;
}

// The slope the rain adds at p (xz gradient of height).
vec2 rain_slope(vec2 p, float t) {
	if (rain <= 0.01) {
		return vec2(0.0);
	}
	return rain_layer(p, t, 0.55, 0.0) + rain_layer(p + 0.3, t * 1.13, 0.8, 17.0) * 0.8;
}
