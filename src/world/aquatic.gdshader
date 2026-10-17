shader_type spatial;
// Water plants and reef life (AquaKit). INSTANCE_CUSTOM.rgb is the instance's tint (sRGB);
// INSTANCE_CUSTOM.a its sway (0 in the wind, 1 in the current, 2 still) plus its glow as
// the fraction (alien worlds only). Vertex COLOR: rgb the part's shade times SHADE_SCALE,
// or with a = 0 a fixed colour. UV.y is how far up the plant a vertex is, UV2 the distance
// over which the species thins out.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"

global uniform float wind_strength;
global uniform vec2 wind_dir;
global uniform float wind_time;
global uniform float night_glow_g;
uniform float detail = 1.0; // graphics setting "detail_distance"
const float SHADE_SCALE = 0.7;
varying vec3 tint;
varying float shade;
varying float glow;
varying float leafy;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float mode = floor(INSTANCE_CUSTOM.a + 0.001);
	glow = INSTANCE_CUSTOM.a - mode;
	leafy = mode < 1.5 ? 1.0 : 0.0;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float h = UV.y * UV.y;
	vec2 dir = vec2(0.0);
	float bend = 0.0;
	if (mode < 0.5) {
		// Reeds in the wind, like the grass on the bank.
		float t = wind_time * 1.3 + dot(wp.xz, wind_dir) * 0.35;
		float sway = sin(t) * 0.45 + sin(t * 2.3 + wp.x * 0.7) * 0.15;
		bend = h * (0.06 + wind_strength * 0.45) * (sway + wind_strength * 0.7);
		dir = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xz;
	} else if (mode < 1.5) {
		// Under water: a slow to-and-fro in the swell, each plant in its own phase, the
		// tops of tall kelp swinging furthest (worked in metres, then back to the mesh).
		float ph = TIME * 0.55 + wp.x * 0.31 + wp.z * 0.19;
		float swing = sin(ph) * 0.8 + sin(ph * 2.1 + 1.3) * 0.25;
		bend = h * swing * 0.22 * max(VERTEX.y * sy, 0.05) / max(sx, 0.01);
		dir = (inverse(MODEL_MATRIX) * vec4(0.8, 0.0, 0.6, 0.0)).xz;
	}
	VERTEX.xz += normalize(dir + vec2(0.0001)) * bend;
	VERTEX.y -= abs(bend) * 0.25;
	tint = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
	shade = 1.0 - 0.42 * cloud_shadow(wp);
	// Thin out with distance, each clump at its own cut-off, as the grass does.
	float far = smoothstep(UV2.x * detail, UV2.y * detail, length(wp - CAMERA_POSITION_WORLD));
	vec3 p3 = fract(vec3(wp.xzx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float pick = fract((p3.x + p3.y) * p3.z);
	VERTEX *= smoothstep(pick, pick + 0.12, (1.0 - far) * 1.12);
}

void fragment() {
	bool own = COLOR.a < 0.5;
	vec3 base = own ? pow(COLOR.rgb, vec3(2.2)) : tint * COLOR.rgb / SHADE_SCALE;
	base *= shade;
	ALBEDO = base;
	// Wet, waxy pads and kelp catch a sheen; coral and sponge are dull.
	ROUGHNESS = own ? 0.6 : 0.7;
	SPECULAR = 0.4;
	BACKLIGHT = base * 0.35;
	// Leaves, petals and fans are seen from both sides: light the side that faces you.
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	// Thin leaves and ribbons shade like the bed of plants they make, not each on its own
	// (as the grass does), and glow through when the light is behind them.
	if (leafy > 0.5) {
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up, 0.45));
		BACKLIGHT = base * 0.55;
	}
	EMISSION = base * glow * night_glow_g * 2.0;
}
