shader_type spatial;
// Lakes and seas: wind-driven swell (sum of directional deep-water waves, larger over
// deep water), depth-tinted, refractive, mirroring the shores and sky (water_ssr), with
// whitecaps when the wind is strong, lacy foam rolling in through the shallows, and ring
// waves where something broke the surface (water_rings), and boats' wakes standing up
// as real waves (water_wakes). The open sea is clear and blue;
// ponds and small lakes are green-brown with silt (murk_map, from Water._murk).
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/env/clouds.gdshaderinc"
global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform vec3 shallow : source_color = vec3(0.16, 0.36, 0.38);
uniform vec3 deep : source_color = vec3(0.02, 0.08, 0.12);
uniform vec3 glow : source_color = vec3(0.1, 0.9, 0.8);
uniform float glow_amount = 0.0;
uniform float clarity = 4.0;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform sampler2D murk_map : filter_linear, repeat_disable; // Water._murk, over the same square
uniform vec2 depth_origin = vec2(-800.0);
uniform float depth_size = 1600.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
#include "res://src/env/water_ssr.gdshaderinc"
#include "res://src/env/water_rings.gdshaderinc"
#include "res://src/env/water_swell.gdshaderinc"
#include "res://src/env/water_wakes.gdshaderinc"

varying vec3 wpos;
varying float crest;
varying float amp;
varying float murk;
varying float exposure;

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
float ripples(vec2 p, float t) {
	return n2(p * 0.35 + vec2(t * 0.12, t * 0.05)) * 0.6 + n2(p * 1.1 - vec2(t * 0.2, -t * 0.15)) * 0.3 + n2(p * 3.3 + t * 0.4) * 0.1;
}
// Foam lace: thin, branching strands with holes between, as foam lies on the water,
// not a solid white sheet.
float foam_lace(vec2 p, float t) {
	float a = n2(p * 2.3 + vec2(t * 0.15, -t * 0.1));
	float b = n2(p * 5.3 - vec2(t * 0.2, t * 0.12));
	float web = clamp(1.0 - abs(a * 2.0 + b) * 2.6, 0.0, 1.0);
	return web * smoothstep(-0.25, 0.15, n2(p * 0.7 + t * 0.05) + 0.1);
}

float depth_here(vec2 p) {
	vec2 uv = (p - depth_origin) / depth_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 12.0;
	return texture(depth_map, uv).r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = depth_here(wpos.xz);
	amp = swell_amp(depth);
	vec2 muv = (wpos.xz - depth_origin) / depth_size;
	// How squarely the wind drives waves onto the nearest shore: surf breaks on the lee
	// shore the wind blows toward, and the shore it blows off stays nearly still.
	vec2 dg = vec2(depth_here(wpos.xz + vec2(12.0, 0.0)) - depth_here(wpos.xz - vec2(12.0, 0.0)),
		depth_here(wpos.xz + vec2(0.0, 12.0)) - depth_here(wpos.xz - vec2(0.0, 12.0)));
	exposure = length(dg) > 0.05 ? smoothstep(-0.3, 0.7, dot(normalize(wind_dir + vec2(0.0001)), -normalize(dg))) : 0.5;
	murk = (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) ? 0.0 : texture(murk_map, muv).r;
	vec3 s = swell(wpos.xz, TIME, amp);
	float wk = wake_height(wpos.xz);
	VERTEX.y += s.x + wk;
	wpos.y += s.x + wk;
	NORMAL = normalize(vec3(-s.y, 1.0, -s.z));
	crest = s.x / max(amp, 0.001);
}

void fragment() {
	float t = TIME;
	float e = 0.08;
	float h = ripples(wpos.xz, t);
	float rs = 0.5 + wind_strength * 1.2;
	vec3 rn = vec3(-(ripples(wpos.xz + vec2(e, 0), t) - h) / e, 0.0, -(ripples(wpos.xz + vec2(0, e), t) - h) / e) * rs;
	vec2 rg = ring_slope(wpos.xz) + wake_slope(wpos.xz);
	vec3 swell_n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 nw = normalize(swell_n + rn * 0.6 + vec3(-rg.x, 0.0, -rg.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z - (-VERTEX.z)), 0.0, 100.0);
	// How deep the bed lies straight down (the path through the water is longer).
	float vdepth = max(wpos.y - (INV_VIEW_MATRIX * vec4(world.xyz, 1.0)).y, 0.0);
	float clear_m = mix(clarity, 2.2, murk);
	float k = 1.0 - exp(-water_depth / clear_m);
	vec2 refr_uv = SCREEN_UV + nw.xz * 0.02 * k;
	vec3 under = textureLod(screen_tex, refr_uv, 1.0).rgb;
	// What lies under the water is already lit, so it is seen through (emission), dimmed
	// as the water swallows red first, then green: clear and sandy in the shallows,
	// green-blue then dark further out. Lighting it again as albedo made lakes glare cyan.
	// Silt in a pond swallows blue most: the bed shows in the shallows, gone by two metres.
	vec3 absorb = mix(vec3(0.4, 0.14, 0.17) * (4.0 / clarity), vec3(0.42, 0.33, 0.62), murk);
	vec3 trans = exp(-absorb * water_depth * 1.5);
	vec3 tint = mix(mix(vec3(1.0), shallow / max(max(shallow.r, shallow.g), max(shallow.b, 0.01)), 0.3), vec3(0.95, 1.0, 0.78), murk);
	vec3 seen = under * trans * tint;
	// The water's own colour, from light scattered inside it: shows where it is deep.
	// ...in a pond, the silt hanging in it, lit by the sun: murky green-brown.
	vec3 col = mix(deep * 1.6, vec3(0.03, 0.034, 0.016), murk) * (1.0 - trans.g);
	// Light passing through the thin tops of waves turns them a brighter green-blue,
	// most when you look toward a low sun.
	vec3 vdir = normalize((inverse(VIEW_MATRIX) * vec4(VIEW, 0.0)).xyz);
	float back = pow(clamp(dot(-vdir, normalize(sun_dir_g)), 0.0, 1.0), 3.0);
	float tip = smoothstep(0.15, 0.9, crest) * clamp(amp * 3.0, 0.0, 1.0);
	col += vec3(0.04, 0.16, 0.13) * tip * (0.35 + 1.2 * back) * smoothstep(-0.05, 0.2, sun_dir_g.y);
	col *= 1.0 - 0.3 * cloud_shadow(wpos);
	// Foam: lace where the wash thins out at the water's edge, and lines of broken water
	// rolling in through the shallows toward the beach (they ride the depth, so they
	// follow the shore's shape); whitecaps on wave crests in a strong wind.
	float lace = foam_lace(wpos.xz, t);
	float lap = 0.5 + 0.5 * sin(t * 0.9 + n2(wpos.xz * 0.08) * 9.0);
	float edge_f = (1.0 - smoothstep(0.0, 0.06 + amp * 0.3 + lap * 0.05, vdepth)) * smoothstep(0.0, 0.015, vdepth);
	float roll = sin(vdepth * 7.0 + t * 1.3 + n2(wpos.xz * 0.25) * 4.0);
	float rollers = smoothstep(0.8, 1.0, roll) * (1.0 - smoothstep(0.2, 0.8 + amp * 2.0, vdepth)) * smoothstep(0.03, 0.12, vdepth);
	// Broken into stretches, as real breakers are, never a ring round the whole shore.
	rollers *= smoothstep(-0.05, 0.25, n2(wpos.xz * 0.05 + vec2(t * 0.03, 0.0)));
	// Surf needs fetch: a sheltered pond barely laps, a big lake or the sea breaks.
	float surf = (1.0 - 0.85 * murk) * exposure * smoothstep(0.05, 0.6, wind_strength);
	// (Not on the tool in your hand where it dips into the water: it is no shore.)
	float shore = clamp(edge_f * (0.12 + 0.75 * surf) + rollers * (0.35 + wind_strength) * surf, 0.0, 1.0) * lace
		* smoothstep(1.0, 2.0, -world.z);
	float foam_n = smoothstep(0.1, 0.35, n2(wpos.xz * 1.7 + t * 0.3));
	float caps = smoothstep(0.55, 0.95, crest) * smoothstep(0.45, 0.85, wind_strength) * foam_n * (0.5 + 0.5 * lace);
	float foam = max(shore * 0.85, caps);
	col = mix(col, vec3(0.8, 0.84, 0.86), foam);
	seen *= 1.0 - foam;
	// Looking across the water you see more reflection and less of what lies beneath.
	float ndv = clamp(dot(nw, vdir), 0.0, 1.0); // vdir points back at the eye
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	seen *= 1.0 - fres;
	// The shores, rocks and trees mirrored, traced through the frame; the sky's own
	// reflection (from the environment) shows wherever the trace finds nothing.
	vec4 refl = vec4(0.0);
	if (FRONT_FACING && fres > 0.025) {
		// Half the small ripples' tilt: at their full tilt the mirrored image broke into
		// scattered blobs.
		vec3 rw = reflect(-vdir, normalize(mix(swell_n, nw, 0.5)));
		rw = normalize(vec3(rw.x, max(rw.y, 0.02), rw.z));
		refl = water_ssr(VERTEX, (VIEW_MATRIX * vec4(rw, 0.0)).xyz, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, wpos.y - 0.3, 0.6 + wind_strength * 1.5);
	}
	if (!FRONT_FACING) {
		// Seen from below: Snell's window. Looking up steeply you see the bright, rippling
		// sky through the surface; at shallower angles the surface is a mirror (total
		// internal reflection) showing the bed and whatever swims below, traced like the
		// reflections above, and the lit water itself where the trace finds nothing.
		float up = clamp(-vdir.y, 0.0, 1.0);
		float window = smoothstep(0.62, 0.74, up + (nw.x + nw.z) * 0.08);
		vec3 sky = textureLod(screen_tex, SCREEN_UV + nw.xz * 0.05, 0.0).rgb;
		float day = smoothstep(-0.1, 0.25, sun_dir_g.y);
		vec3 lit_water = mix(vec3(0.03, 0.12, 0.16), vec3(0.06, 0.09, 0.04), murk);
		vec3 mirror = lit_water * (0.25 + 1.2 * day);
		if (window < 0.99) {
			vec3 rd = reflect(-vdir, -nw);
			rd = normalize(vec3(rd.x, min(rd.y, -0.02), rd.z));
			vec4 below = water_ssr(VERTEX, (VIEW_MATRIX * vec4(rd, 0.0)).xyz, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, -10000.0, 1.0);
			mirror = mix(mirror, below.rgb * 0.85, below.a);
		}
		ALBEDO = vec3(0.0);
		EMISSION = mix(mirror, sky * vec3(0.75, 0.95, 1.0) * 1.1, window) + vec3(0.9, 0.95, 1.0) * caps * 0.15 * day;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	} else {
		ALBEDO = col;
		ALPHA = smoothstep(0.0, 0.012, vdepth);
		ROUGHNESS = 0.03 + wind_strength * 0.08 + foam * 0.6;
		METALLIC = 0.0;
		SPECULAR = 0.5 * (1.0 - refl.a * 0.9);
		EMISSION = seen + refl.rgb * fres * refl.a * (1.0 - foam) + glow * glow_amount * (0.15 + 0.6 * smoothstep(0.1, 0.3, h)) * (1.0 - k * 0.5);
	}
}
