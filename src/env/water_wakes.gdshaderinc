// Boat wakes as real height on the water (BoatManager keeps the list): for each boat under
// way near the view, the Kelvin pattern her hull raises, worked out where you look rather
// than drawn on top. A bow wave heaped up at her shoulders; transverse waves across her
// track, as far apart as her speed sets (2 pi v^2 / g); and the diverging waves, short
// steep crests slanting out along the cusp lines at 19.5 degrees either side. They grow
// with her speed and size, fade with distance behind her, and stay out of the hull itself
// (no water standing up inside an open boat). BoatWake draws the foam that rides them.
// water_swell.gdshaderinc adds them into wake(p), the one call every water shader makes.

// Boats under way (BoatManager, Water.set_boat_wakes): an 8x2 float texture, one column a
// boat. Row 0: her bow x, z and heading x, z (unit, the way she faces). Row 1: speed m/s,
// hull length, half-beam, strength 0..1 (0: a free slot). Must match BoatManager.wake_at(),
// which answers the same heights for things that float.
global uniform sampler2D water_wake_boats : filter_nearest, repeat_disable;

// Height the boats' wakes add at p (metres).
float wake_height(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 b = texelFetch(water_wake_boats, ivec2(i, 1), 0);
		if (b.w <= 0.001) {
			continue;
		}
		vec4 a = texelFetch(water_wake_boats, ivec2(i, 0), 0);
		vec2 f = a.zw;
		vec2 d = p - a.xy;
		float x = -dot(d, f); // metres behind her bow
		float y = dot(d, vec2(-f.y, f.x)); // across
		float ay = abs(y);
		float v = max(b.x, 0.3);
		float L = b.y;
		float beam = b.z;
		float reach = 25.0 + 3.0 * L;
		if (x < -L * 0.4 || x > reach || ay > beam + max(x, 0.0) * 0.4 + 6.0) {
			continue;
		}
		float k0 = 9.8 / (v * v);
		// How tall: grows with speed and the square root of her length.
		float A = clamp(0.065 * v * sqrt(L) / 3.0, 0.0, 0.4) * b.w;
		float decay = inversesqrt(1.0 + max(x, 0.0) / max(L * 0.5, 1.0)) * (1.0 - smoothstep(reach * 0.6, reach, x));
		float wedge = max(x, 0.0) * 0.354 + beam * 0.6;
		// Transverse waves: inside the wedge, strongest near her track, crests bowed back.
		float inside = 1.0 - smoothstep(wedge * 0.7, wedge * 1.05, ay);
		float trans = cos(k0 * (x + ay * ay / max(2.0 * x + L, 1.0)) - 1.2) * inside * smoothstep(-L * 0.2, L * 0.4, x);
		// Diverging waves: short crests packed along the cusp line, slanting out.
		float q = ay - wedge;
		float wq = 0.6 + max(x, 0.0) * 0.08 + beam * 0.4;
		float cusp = exp(-(q * q) / (wq * wq)) * smoothstep(-L * 0.3, L * 0.2, x);
		float div = cos(k0 * 1.7 * (x * 0.574 + ay * 0.819)) * cusp;
		// The bow wave: water heaped against her shoulders, a trough along her sides.
		float bx = (x - L * 0.08) / (L * 0.18);
		float by = (ay - beam * 1.15) / (beam * 0.8 + 0.4);
		float bow = exp(-(bx * bx + by * by)) * 1.3 - exp(-pow((x - L * 0.5) / (L * 0.35), 2.0) - by * by) * 0.45;
		// Not inside the hull.
		float hull = (1.0 - smoothstep(beam * 0.85, beam * 1.2, ay)) * smoothstep(-L * 0.06, L * 0.02, x) * (1.0 - smoothstep(L * 0.95, L * 1.08, x));
		h += A * (trans * 0.55 * decay + div * 0.8 * decay + bow) * (1.0 - hull);
	}
	return clamp(h, -0.6, 0.6); // Water.WAKE_MAX
}

// Height and xz gradient (by differences), the shape wake(p) returns.
vec3 boat_wakes(vec2 p) {
	if (texelFetch(water_wake_boats, ivec2(0, 1), 0).w <= 0.001) {
		return vec3(0.0); // no boats under way (BoatManager fills the nearest first)
	}
	float h = wake_height(p);
	float e = 0.2;
	return vec3(h, (wake_height(p + vec2(e, 0.0)) - wake_height(p - vec2(e, 0.0))) / (2.0 * e),
		(wake_height(p + vec2(0.0, e)) - wake_height(p - vec2(0.0, e))) / (2.0 * e));
}
