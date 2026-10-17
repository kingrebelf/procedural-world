shader_type spatial;
// Rivers: a ribbon of water at the river's level, flowing downhill (vertex COLOR.rg is
// the flow direction and speed, COLOR.b how steeply the river falls, COLOR.a fades the
// edges). Ripples and long streaks are advected along the flow in two phases that
// cross-fade, so the current never stretches or resets visibly. Where it falls steeply
// it breaks into rapids: standing waves and white water. Foam piles up against rocks and
// trails away downstream of them, and the banks and sky are mirrored (water_ssr).
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec3 sun_dir_g;
uniform vec3 shallow : source_color = vec3(0.2, 0.4, 0.4);
uniform vec3 deep : source_color = vec3(0.04, 0.07, 0.045);
uniform vec3 glow : source_color = vec3(0.1, 0.9, 0.8);
uniform float glow_amount = 0.0;
uniform float speed = 1.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
#include "res://src/env/water_ssr.gdshaderinc"
#include "res://src/env/water_rings.gdshaderinc"

varying vec3 wpos;
varying vec2 flow;
varying float edge;
varying float rapids;

// Integer hash of a lattice point (PCG2D). Exact on every GPU: the old sin() hash gave a
// shared cell corner two different values on some GPUs (NVIDIA: light and dark rectangles
// across the view), and lost all precision far from the world's origin.
uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}
vec2 h2(vec2 p) { return vec2(pcg2d(uvec2(ivec2(floor(p))))) * (1.0 / 4294967296.0); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(h2(i) - 0.5, f), dot(h2(i + vec2(1, 0)) - 0.5, f - vec2(1, 0)), u.x),
		mix(dot(h2(i + vec2(0, 1)) - 0.5, f - vec2(0, 1)), dot(h2(i + vec2(1, 1)) - 0.5, f - vec2(1, 1)), u.x), u.y);
}
float rip(vec2 p) { return n2(p * 0.6) * 0.55 + n2(p * 1.9) * 0.3 + n2(p * 5.1) * 0.15; }
// Streaks drawn out along the current (d: flow direction): long, thin, and finer where
// it runs fast.
float streaks(vec2 p, vec2 d) {
	vec2 q = vec2(dot(p, d), dot(p, vec2(-d.y, d.x)));
	return n2(q * vec2(0.3, 1.2)) * 0.3 + n2(q * vec2(0.7, 3.0) + 7.0) * 0.1;
}
// Foam lace: thin, branching strands with holes between.
float foam_lace(vec2 p) {
	float a = n2(p * 2.3);
	float b = n2(p * 5.3 + 11.0);
	return clamp(1.0 - abs(a * 2.0 + b) * 2.4, 0.0, 1.0);
}
// 1 when something stands up out of the water (a rock, a post, a leg) right by the
// surface point q, from the frame's depth. Probed a little up- and downstream, this puts
// foam against rocks and trails it off below them.
float obstacle(vec3 q, mat4 view, mat4 proj, mat4 inv_proj, mat4 inv_view) {
	vec4 c = proj * (view * vec4(q, 1.0));
	if (c.w <= 0.0) {
		return 0.0;
	}
	vec2 uv = c.xy / c.w * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec3 s = (inv_view * vec4(ssr_view_pos(uv, inv_proj), 1.0)).xyz;
	return smoothstep(q.y - 0.3, q.y - 0.05, s.y) * (1.0 - smoothstep(q.y + 2.0, q.y + 4.0, s.y)) * (1.0 - smoothstep(0.2, 1.0, length(s.xz - q.xz)));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = COLOR.rg * 2.0 - 1.0;
	edge = COLOR.a;
	rapids = smoothstep(0.4, 0.9, COLOR.b) * edge; // falling more than about 1 in 12
	// Standing waves in the rapids: they hold their place while the water runs through.
	vec2 d = normalize(flow + vec2(0.0001));
	float sw = sin(dot(wpos.xz, d) * 1.9 + n2(wpos.xz * 0.4) * 5.0) * (0.5 + n2(wpos.xz * 0.9 + 4.0));
	VERTEX.y += rapids * 0.12 * sw;
	wpos.y += rapids * 0.12 * sw;
}

void fragment() {
	float spd = length(flow);
	vec2 fd = flow / max(spd, 0.001);
	float t = TIME * speed * (0.25 + rapids * 0.35);
	float p0 = fract(t);
	float p1 = fract(t + 0.5);
	float w = abs(p0 - 0.5) * 2.0;
	vec2 off0 = -flow * p0 * 4.0;
	vec2 off1 = -flow * p1 * 4.0;
	float e = 0.08;
	vec2 q0 = wpos.xz + off0;
	vec2 q1 = wpos.xz + off1 + vec2(13.7, 5.1);
	float sk = 0.5 + spd * 0.5;
	float h0 = rip(q0) + streaks(q0, fd) * sk;
	float h1 = rip(q1) + streaks(q1, fd) * sk;
	vec2 g0 = vec2(rip(q0 + vec2(e, 0)) + streaks(q0 + vec2(e, 0), fd) * sk - h0, rip(q0 + vec2(0, e)) + streaks(q0 + vec2(0, e), fd) * sk - h0) / e;
	vec2 g1 = vec2(rip(q1 + vec2(e, 0)) + streaks(q1 + vec2(e, 0), fd) * sk - h1, rip(q1 + vec2(0, e)) + streaks(q1 + vec2(0, e), fd) * sk - h1) / e;
	vec2 g = mix(g0, g1, w) * (0.35 + spd * 0.4 + rapids * 0.8) + ring_slope(wpos.xz);
	// Never tilted so far that a facet mirrors the ground under the horizon (black flecks).
	g /= max(1.0, length(g) / 0.55);
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z - (-VERTEX.z)), 0.0, 50.0);
	float vdepth = max(wpos.y - (INV_VIEW_MATRIX * vec4(world.xyz, 1.0)).y, 0.0);
	float k = 1.0 - exp(-water_depth / 2.5);
	vec3 under = textureLod(screen_tex, SCREEN_UV + nw.xz * 0.015 * k, 1.0).rgb;
	// Sun caustics dancing on the riverbed, carried downstream.
	vec2 cq = (wpos.xz + off0 * 0.5) * 0.5;
	float c1 = abs(n2(cq + n2(cq * 0.7 + TIME * 0.2) * 1.5) * 2.0);
	float caus = pow(clamp(1.0 - c1 * 2.0, 0.0, 1.0), 4.0);
	under *= 1.0 + caus * (1.0 - k) * 1.2 * smoothstep(-0.05, 0.3, sun_dir_g.y);
	// As in the lakes: the riverbed is already lit, so it is seen through (emission). River
	// water carries peat and silt, so blue goes first and the deep runs green-brown, not
	// the sea's turquoise; the water's own colour shows where it is deep.
	vec3 trans = exp(-vec3(0.38, 0.24, 0.45) * water_depth * 1.5);
	vec3 tint = mix(vec3(1.0), shallow / max(max(shallow.r, shallow.g), max(shallow.b, 0.01)), 0.3);
	vec3 seen = under * trans * tint;
	vec3 col = deep * (1.0 - trans.g) * 1.6;
	// Foam, as lace carried on the current: flecks where it runs fast, white water in the
	// rapids, a broken line at the banks, piled against rocks and trailing below them.
	float lace = mix(foam_lace(q0 * 0.8), foam_lace(q1 * 0.8), w);
	float hs = mix(h0, h1, w);
	float flecks = smoothstep(0.35, 0.6, hs) * spd * 0.3;
	float white = rapids * smoothstep(0.05, 0.55, hs + rapids * 0.15);
	float bank = (1.0 - smoothstep(0.0, 0.12, vdepth)) * smoothstep(0.0, 0.02, vdepth);
	vec3 f3 = vec3(fd.x, 0.0, fd.y);
	float rocks = 0.0;
	if (spd > 0.05) {
		rocks = obstacle(wpos + f3 * 0.5, VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX) * 0.7
			+ obstacle(wpos - f3 * 1.2, VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX) * 0.6
			+ obstacle(wpos - f3 * 2.8, VIEW_MATRIX, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX) * 0.35;
		rocks *= 0.4 + spd;
	}
	float foam = clamp((flecks + white + bank * 0.5 + rocks * 0.8) * lace + white * white * 0.3, 0.0, 0.85);
	col = mix(col, vec3(0.8, 0.84, 0.86), foam);
	vec3 vdir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz); // back toward the eye
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, vdir), 0.0, 1.0), 5.0);
	seen *= (1.0 - foam) * (1.0 - fres);
	// The banks and trees mirrored where the water is smooth enough to hold them.
	vec4 refl = vec4(0.0);
	if (FRONT_FACING && fres > 0.025) {
		vec3 rw = reflect(-vdir, nw);
		rw = normalize(vec3(rw.x, max(rw.y, 0.02), rw.z));
		refl = water_ssr(VERTEX, (VIEW_MATRIX * vec4(rw, 0.0)).xyz, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, wpos.y - 0.3, 1.0 + rapids * 2.0);
		refl.a *= 1.0 - rapids * 0.7;
	}
	ALBEDO = col;
	ALPHA = edge * smoothstep(0.0, 0.05, vdepth);
	ROUGHNESS = 0.06 + rapids * 0.1 + foam * 0.5;
	SPECULAR = 0.5 * (1.0 - refl.a * 0.9);
	EMISSION = seen + refl.rgb * fres * refl.a * (1.0 - foam) + glow * glow_amount * 0.4;
}
