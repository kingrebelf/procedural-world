shader_type spatial;
// Plumage for the procedural birds (BirdModel). Body: rows of small overlapping contour
// feathers, each with a rounded tip, a pale or dark fringe and fine barbs, laid in the
// lathe's UVs (x round the body, y head to tail). Flight and tail feathers (ribbons,
// x across the vane, y root to tip): a pale shaft down the middle, barbs raked toward
// the tip, darker tips, optional barring. Coverts: scalloped rows along the wing. Dark
// birds get a faint oily sheen. Each bird's `seed` shifts its shade and markings.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform int mode = 0; // 0 body, 1 flight or tail feather, 2 wing coverts
uniform vec3 col_a : source_color = vec3(0.4, 0.35, 0.3);
uniform vec3 col_b : source_color = vec3(0.6, 0.5, 0.4);
uniform float rows = 22.0; // feather rows head to tail (body) or along the wing (coverts)
uniform float around = 16.0; // feathers round the body
uniform float fringe = 0.25; // pale (+) or dark (-) edge on each feather
uniform float bars = 0.0; // dark bars across flight feathers (kestrels)
uniform float sheen = 0.0; // oily blue-green sheen on dark plumage
uniform vec3 glow_col : source_color = vec3(0.3, 0.9, 1.0);
uniform float glow = 0.0;
global uniform float night_glow_g;
instance uniform float seed = 0.0;

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 bump(vec3 n, vec3 v, float h) {
	vec3 dpx = dFdx(v), dpy = dFdy(v);
	float hx = dFdx(h), hy = dFdy(h);
	vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 g = sign(det) * (hx * r1 + hy * r2);
	return normalize(abs(det) * n - g);
}

void fragment() {
	float s = seed * 0.000173;
	vec3 c;
	float h = 0.0;
	float px = length(fwidth(UV)); // UV a pixel covers: fade detail that would shimmer
	if (mode == 1) {
		float x = UV.x - 0.5;
		float ax = abs(x);
		c = mix(col_a, col_b, smoothstep(0.0, 1.0, UV.y));
		float barbs = sin((ax * 6.0 + UV.y * 1.0) * 70.0) * 0.5 + 0.5;
		float bf = 1.0 - smoothstep(0.01, 0.04, px);
		c *= 0.9 + 0.2 * barbs * bf;
		c *= 1.0 - 0.35 * smoothstep(0.6, 1.0, UV.y); // darker tips
		if (bars > 0.0) {
			float b = sin(UV.y * 31.4 + h1(s) * 6.28 + ax * 2.0);
			c *= 1.0 - bars * smoothstep(0.55, 0.8, b);
		}
		float shaft = 1.0 - smoothstep(0.015, 0.035, ax);
		c = mix(c, col_b * 1.3 + 0.05, shaft * 0.6);
		c *= 1.0 - 0.2 * smoothstep(0.38, 0.5, ax); // the vane's ragged edge
		h = (barbs * bf * 0.3 + shaft) * 0.0008;
	} else {
		float r = mode == 0 ? rows : rows * 0.6;
		float a = mode == 0 ? around : 9.0;
		vec2 g = vec2(UV.x * a, UV.y * r);
		if (mode == 2) g = vec2(UV.y * r, UV.x * a);
		float row = floor(g.y);
		g.x += mod(row, 2.0) * 0.5;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		// Each feather's rounded tip points tailward (+y). Outside the curve lies the
		// tip of the feather in the row before, shaded where it overlaps this one.
		float e = length(vec2((f.x - 0.5) / 0.62, f.y));
		float own = 1.0 - smoothstep(0.97, 1.0, e);
		float edge = smoothstep(0.7, 0.97, e) * own;
		vec2 id = own > 0.5 ? cell : cell - vec2(0.0, 1.0);
		float rnd = h2(id + s);
		c = mix(col_a, col_b, smoothstep(0.0, 1.0, mode == 0 ? UV.y : UV.x));
		c *= 0.92 + 0.16 * rnd;
		float df = 1.0 - smoothstep(0.08, 0.25, px * r);
		c *= 1.0 + fringe * edge * df;
		c *= 1.0 - 0.18 * (1.0 - own) * smoothstep(1.0, 1.25, e) * df;
		float barbs = sin((abs(f.x - 0.5) * 3.0 + f.y) * 40.0) * 0.5 + 0.5;
		c *= 1.0 + (barbs - 0.5) * 0.06 * df;
		h = (own * e * 0.8 + barbs * 0.05) * df * 0.0012;
	}
	c *= 1.0 + 0.16 * (h1(s + 3.0) - 0.5);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	c += vec3(0.02, 0.05, 0.1) * sheen * (0.4 + fres);
	ALBEDO = clamp(c, 0.0, 1.0);
	NORMAL = bump(NORMAL, VERTEX, h);
	ROUGHNESS = mix(0.75, 0.45, sheen);
	SPECULAR = 0.4;
	RIM = 0.25;
	RIM_TINT = 0.6;
	BACKLIGHT = c * (mode == 1 ? 0.35 : 0.1);
	float night = clamp(night_glow_g, 0.0, 1.5);
	EMISSION = glow_col * glow * (0.2 + 0.8 * night);
}
