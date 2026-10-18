shader_type spatial;
// The small flame of a candle or a lamp's wick (FireFx.flame below SMALL), drawn rather
// than taken from the flipbook, whose bonfire shapes read as blobs at this size: a
// teardrop with a blue root, the darker cone of unburnt wax vapour over the wick, a
// white-gold heart and a soft orange skin, in a faint halo. It wavers, stretches and
// gutters with its life (fire.gdshaderinc, which its light follows) and bends in a
// draught; in a lantern (exposed near 0) it stands almost still.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

#include "res://src/world/fire.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float seed = 0.0;
instance uniform float size = 0.07; // the flame's height in metres
instance uniform float exposed = 0.15;
instance uniform vec3 drag = vec3(0.0);
varying float life;
varying float bend;
varying float stretch;

// The card spans [-W, W] across and [-B, T] up, in units of the flame's height (FireFx).
const float W = 0.42;
const float B = 0.18;
const float T = 1.32;

void vertex() {
	vec3 c = NODE_POSITION_WORLD;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - c;
	to_cam.y = 0.0;
	vec3 f = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
	vec3 lv = (inverse(MODEL_MATRIX) * vec4(VERTEX, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	life = fire_life(fire_time, seed);
	stretch = 0.84 + 0.32 * life;
	// A draught (and being carried) lays it over: the part across your view bends it in
	// the fragment; the part toward or away from you tips the card.
	float gust = 0.5 + 0.5 * fx_noise(fire_time * 1.7 + seed * 53.0);
	vec3 lean = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_strength * exposed * gust + drag;
	float ll = length(lean);
	lean *= ll > 0.9 ? 0.9 / ll : 1.0;
	// Its own restless sway, quicker and smaller than a torch's.
	float sway = (fx_noise(fire_time * 2.3 + seed * 71.0) - 0.5) * 0.22 + (fx_noise(fire_time * 8.5 + seed * 13.0) - 0.5) * 0.07 * (0.4 + exposed);
	bend = dot(lean, r) * 0.9 + sway;
	float h = max(lv.y, 0.0) / max(size, 1e-4);
	VERTEX = base + r * lv.x * sx + vec3(0.0, lv.y * sy, 0.0) + f * dot(lean, f) * h * h * size * sy * 0.5;
	NORMAL = f;
}

void fragment() {
	// x across and y up in flame heights, the wick's tip at (0, 0).
	vec2 p = vec2(mix(-W, W, UV.x), mix(T, -B, UV.y));
	float y = p.y / stretch;
	// The flame bends from its root: the tip goes furthest.
	float yc = clamp(y, 0.0, 1.0);
	float x = p.x - bend * yc * yc * 0.55;
	// Teardrop: widest a third of the way up, rounded at the root, drawn to a point.
	float prof = 0.2 * pow(clamp(y + 0.06, 0.0, 1.2), 0.42) * pow(clamp(1.0 - y, 0.0, 1.0), 0.9) * 1.55;
	float d = abs(x) / max(prof, 1e-3);
	float body = smoothstep(1.0, 0.55, d) * smoothstep(-0.06, 0.05, y) * smoothstep(1.02, 0.85, y);
	// The heart: white-gold, through the upper middle.
	float heart = smoothstep(0.7, 0.1, d) * smoothstep(0.12, 0.35, y) * smoothstep(0.95, 0.55, y);
	// Over the wick, a darker cone where the vapour hasn't burnt yet.
	float cone = smoothstep(0.55, 0.0, d) * smoothstep(0.32, 0.02, y) * smoothstep(-0.04, 0.04, y);
	// The blue root, a thin shell round the bottom.
	float blue = smoothstep(1.05, 0.5, d) * smoothstep(0.24, 0.0, y) * smoothstep(-0.08, 0.02, y) * (1.0 - cone * 0.6);
	vec3 skin = vec3(1.0, 0.48, 0.12);
	vec3 gold = vec3(1.0, 0.8, 0.42);
	vec3 white = vec3(1.0, 0.95, 0.82);
	vec3 col = skin * body * 1.4;
	col = mix(col, gold * 2.2, body * smoothstep(0.95, 0.35, d));
	col = mix(col, white * 3.4, heart);
	col = mix(col, vec3(0.55, 0.32, 0.18) * 0.9, cone * 0.75);
	col += vec3(0.12, 0.22, 0.85) * blue * 0.9;
	// A faint halo of light round it, as the eye sees a candle in the dark.
	float r2 = dot(vec2(x * 1.6, (p.y - 0.42) * 0.9), vec2(x * 1.6, (p.y - 0.42) * 0.9));
	col += vec3(1.0, 0.55, 0.22) * exp(-r2 * 16.0) * 0.16;
	// A leaping flame burns brighter, a sinking one dimmer and redder.
	col *= tint.rgb * tint.a * (0.82 + 0.36 * life);
	// The blue root stays blue; the rest keeps to warm hues so the heart reads gold.
	col = mix(fire_hue(col), col, clamp(blue * 1.5, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(max(col.r, max(col.g, col.b)) * 0.9, 0.0, 1.0);
}
