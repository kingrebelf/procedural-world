// Ring waves spreading where something broke the surface (Splashes keeps the list): a
// train of small crests running out from the spot, the leading one steepest, longer and
// gentler as they spread and die away. They tilt the surface, so the water's reflections
// and what is seen through it ripple, instead of a white disc being drawn on top.

// x, z: where; age: seconds since; strength: 0 for a free slot, ~0.1 a stroke, 1 a jump in.
uniform vec4 rings[12];

// The slope (xz gradient of height) the rings add at p.
vec2 ring_slope(vec2 p) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 12; i++) {
		vec4 w = rings[i];
		if (w.w <= 0.0) {
			continue;
		}
		vec2 d = p - w.xy;
		float r = length(d);
		float age = w.z;
		float front = 0.1 + age * (0.75 + 0.35 * min(w.w, 1.5));
		float x = r - front;
		if (x > 0.5 || x < -4.0) {
			continue;
		}
		float len = 0.22 + 0.12 * age;
		float width = (0.25 + 0.4 * age) * (x > 0.0 ? 0.35 : 1.0);
		float env = exp(-(x * x) / (width * width));
		float a = min(w.w, 1.6) * 0.8 * exp(-age * 0.9) / (1.0 + front * 1.2);
		g += d / max(r, 0.01) * a * env * cos(6.2831853 * x / len);
	}
	return g;
}
