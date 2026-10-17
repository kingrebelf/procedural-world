shader_type spatial;
// A flame from Ben's fire flipbook (FireFx.flame): an upright card that turns to face you
// about the vertical and cross-fades through the sheet's 16 frames. Turbulence licks up
// through it, it stretches and sinks with its life (fire.gdshaderinc, the same life its
// FlickerLight follows), and it leans downwind and away from the way it is carried.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

#include "res://src/world/fire.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float fps = 8.0;
// Each frame's flame stands this share of the frame above its bottom edge (FireFx.FOOT).
uniform float foot = 0.12;
// A jet hangs down from its nozzle instead of standing up.
uniform bool hang = false;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float seed = 0.0; // 0..1, shared with its light
instance uniform float card = 0.0; // which of the flame's cards: each runs its own frames
instance uniform float size = 1.0; // the card's height in metres
instance uniform float exposed = 1.0; // 1 out in the wind .. 0 still air indoors
instance uniform vec3 drag = vec3(0.0); // how far it trails as it is carried (FireFx.Drag)
varying vec2 uv_a;
varying vec2 uv_b;
varying float mixf;
varying float life;
varying float mirror;

void vertex() {
	// Upright: turn about the vertical through the node to face the camera.
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
	// The flame leaps up and sinks back with its life; a second card a beat behind.
	float l2 = fire_life(fire_time - 0.08 * card, seed);
	float stretch = 0.8 + 0.42 * l2;
	float up = lv.y * sy * (hang ? 1.0 : stretch);
	VERTEX = base + r * lv.x * sx + vec3(0.0, up, 0.0);
	// Downwind and behind the way it is carried, more at the tips than at the root: gusts
	// push it over and let it stand again.
	float h = clamp(abs(lv.y * sy) / max(size * sy, 1e-3), 0.0, 1.0);
	float gust = 0.55 + 0.45 * fx_noise(fire_time * 1.3 + seed * 41.0);
	vec3 lean = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_strength * exposed * gust * 0.9 + drag;
	float ll = length(lean);
	lean *= ll > 1.1 ? 1.1 / ll : 1.0;
	// Leaning over shortens it as it bends, so it keeps its length.
	VERTEX += lean * size * sy * h * h * (hang ? -0.4 : 0.85);
	VERTEX.y -= length(lean) * size * sy * h * h * 0.25 * (hang ? -1.0 : 1.0);
	NORMAL = f;
	// Frames cross-fade slowly; turbulence (fragment) does the quick licking.
	float t = fire_time * fps * (0.85 + 0.3 * fx_hash(seed * 289.0 + card)) + seed * 16.0 + card * 5.3;
	float f0 = mod(floor(t), 16.0);
	float f1 = mod(f0 + 1.0, 16.0);
	mixf = smoothstep(0.15, 0.85, fract(t));
	mirror = fx_hash(seed * 211.0 + card * 7.0) > 0.5 ? 1.0 : 0.0;
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, mirror), UV.y);
	uv_a = uv + vec2(mod(f0, 4.0), floor(f0 / 4.0));
	uv_b = uv + vec2(mod(f1, 4.0), floor(f1 / 4.0));
}

vec3 frame(vec2 cell_uv) {
	// Keep within the frame's own cell so a neighbour never bleeds in.
	vec2 cell = floor(cell_uv);
	vec2 q = clamp(cell_uv - cell, vec2(0.004), vec2(0.996));
	return texture(tex, (cell + q) / 4.0).rgb;
}

void fragment() {
	// How far up the flame: turbulence grows toward the tips, rising as hot gas does.
	float up = hang ? UV.y : 1.0 - UV.y;
	float above = clamp((up - foot) / (1.0 - foot), 0.0, 1.0);
	float rise = fire_time * (hang ? -6.0 : 2.6);
	vec2 np = vec2(UV.x * 5.0 + seed * 31.0 + card * 3.0, UV.y * 3.5 + rise);
	vec2 warp = vec2(fx_noise2(np) - 0.5, fx_noise2(np * 1.9 + 7.0) - 0.5);
	vec2 w = warp * vec2(0.09, 0.05) * above * (0.6 + 0.6 * life);
	vec3 col = mix(frame(uv_a + w), frame(uv_b + w), mixf);
	// Brighter as it leaps; the tips burn cooler and redder than the heart.
	col *= tint.rgb * tint.a * (0.78 + 0.5 * life);
	col *= mix(vec3(1.0), vec3(1.0, 0.72, 0.5), smoothstep(0.45, 1.0, above) * 0.55);
	// Premultiplied: bright flame hides what is behind it in proportion, so it keeps its
	// colour against a bright sky instead of washing out as plain adding would.
	ALBEDO = col;
	ALPHA = clamp(max(col.r, max(col.g, col.b)) * 1.3, 0.0, 1.0);
}
