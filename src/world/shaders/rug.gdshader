shader_type spatial;
// A hand-knotted wool rug (Rugs): on the rug's own UVs (0..1 over its size in metres), a
// dark guard band, a border of repeating lozenges between two thin lines, and a field
// with a lattice of diamonds and a medallion (one in the middle of a rug, a row of them
// down a runner), or a plain field and stripes for a flatweave. The pattern is read at
// each knot, so its edges step as woven ones do; each knot's wool takes the dye a little
// differently, dye lots band across the length (abrash), the pile is worn flat and
// faded towards the bare warp where feet go, and the long edges fray. Natural dyes:
// madder, indigo, weld, walnut and undyed wool. Nothing glows.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/noise2d.gdshaderinc"

uniform vec2 size_m = vec2(1.0, 2.0);
uniform int style = 0; // 0 knotted with medallions, 1 flatweave
uniform vec3 field_col : source_color = vec3(0.5, 0.17, 0.13);
uniform vec3 border_col : source_color = vec3(0.16, 0.2, 0.32);
uniform vec3 motif_col : source_color = vec3(0.8, 0.72, 0.56);
uniform vec3 accent_col : source_color = vec3(0.7, 0.55, 0.25);
uniform vec3 guard_col : source_color = vec3(0.22, 0.14, 0.09);
uniform vec3 warp_col : source_color = vec3(0.66, 0.6, 0.5);
uniform float seed = 0.0;
uniform float wear = 0.85;

const float KNOTS = 150.0; // per metre
const float GUARD = 0.03;
const float LINE = 0.012;

float lozenge(vec2 p, vec2 r) {
	return abs(p.x) / r.x + abs(p.y) / r.y;
}

void fragment() {
	vec2 m = UV * size_m;
	vec2 k = m * KNOTS;
	vec2 kq = (floor(k) + 0.5) / KNOTS; // the knot this point is in
	vec2 c = kq - size_m * 0.5;
	vec2 ed = min(kq, size_m - kq);
	float d = min(ed.x, ed.y);
	float bw = clamp(min(size_m.x, size_m.y) * 0.11, 0.07, 0.2);
	vec3 col = field_col;
	if (d < GUARD) {
		col = guard_col;
	} else if (d < GUARD + LINE) {
		col = motif_col;
	} else if (d < GUARD + LINE + bw) {
		// Along the nearest edge, and across the border from its outside.
		float s = ed.x < ed.y ? kq.y : kq.x;
		float t = (d - GUARD - LINE) / bw;
		col = border_col;
		if (style == 1) {
			col = abs(t - 0.5) < 0.18 ? accent_col : border_col;
		} else {
			float per = bw * 1.25;
			vec2 q = vec2(fract(s / per) - 0.5, t - 0.5);
			float l = lozenge(q, vec2(0.42, 0.42));
			if (l < 0.45) col = motif_col;
			else if (l < 0.8) col = accent_col;
			else if (l < 0.95) col = guard_col;
		}
	} else if (d < GUARD + 2.0 * LINE + bw) {
		col = motif_col;
	} else if (style == 0) {
		// A lattice of small diamonds, a dot at each crossing.
		float L = 0.24;
		vec2 r = vec2(c.x + c.y, c.x - c.y) * 0.70710678;
		vec2 g = abs(fract(r / L) - 0.5);
		if (min(g.x, g.y) < 0.045) col = mix(field_col, guard_col, 0.4);
		if (max(g.x, g.y) > 0.45) col = mix(accent_col, field_col, 0.35);
		// Medallions: one in the middle, or a row down a long runner.
		vec2 inner = size_m - 2.0 * (GUARD + 2.0 * LINE + bw);
		bool tall = inner.y >= inner.x;
		float w = tall ? inner.x : inner.y;
		float len = tall ? inner.y : inner.x;
		vec2 cl = tall ? c : c.yx;
		if (len > w * 2.2) {
			float per = w * 1.3;
			cl.y = (fract(cl.y / per + 0.5) - 0.5) * per;
		}
		vec2 rad = len > w * 2.2 ? vec2(w * 0.42, w * 0.55) : vec2(w * 0.36, len * 0.36);
		float l = lozenge(cl, rad);
		if (l < 1.0) {
			col = border_col;
			if (l > 0.9) col = mix(motif_col, border_col, 0.25);
			else if (l < 0.3) col = mix(accent_col, field_col, 0.25);
			else if (l < 0.38) col = mix(motif_col, border_col, 0.25);
			else if (abs(fract(l * 6.0) - 0.5) < 0.12) col = mix(border_col, field_col, 0.6);
		}
	} else {
		// A flatweave: bands across its length.
		float along = size_m.y >= size_m.x ? c.y : c.x;
		if (abs(fract(along / 0.5) - 0.5) < 0.05) col = accent_col;
	}
	// Each knot's wool, and the dye lots across the length.
	float h = hash12(floor(k) + seed);
	col *= 0.93 + 0.12 * h;
	float lot = vnoise(vec2((size_m.y >= size_m.x ? m.y : m.x) * 1.7 + seed, seed * 0.3));
	col *= 0.94 + 0.1 * lot;
	// Worn where feet go: the middle and the length of it more than the edges.
	vec2 rel = abs(m - size_m * 0.5) / (size_m * 0.5);
	float path = 1.0 - smoothstep(0.2, 1.0, max(rel.x * 1.1, rel.y * 0.8));
	float wn = fbm(m * 2.2 + seed * 7.0);
	float w = clamp((wn - 0.35) * 1.8 + path * 0.35, 0.0, 1.0) * wear;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum), w * 0.35);
	col = mix(col, warp_col * 0.85, w * 0.42);
	// Frayed long edges.
	float fray = fbm(vec2(m.x + m.y, seed) * 40.0);
	if (d < 0.006 + 0.008 * fray) col *= 0.7;
	ALBEDO = col;
	ROUGHNESS = 0.92 + 0.06 * w;
	SPECULAR = 0.3;
	// The pile: a little dome per knot, flattened where worn; the rows of a flatweave.
	vec2 f = fract(k) - 0.5;
	vec2 n = style == 1 ? vec2(0.0, sin(f.y * 6.2831) * 0.35) : -f * 0.9;
	n *= 1.0 - 0.75 * w;
	NORMAL_MAP = normalize(vec3(n, 1.0)) * 0.5 + 0.5;
}
