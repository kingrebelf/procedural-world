shader_type spatial;
// Instanced grass blades with wind. INSTANCE_CUSTOM.rgb is the era-blended tint,
// INSTANCE_CUSTOM.a the fantasy glow amount, or -1 for waterweed, which sways slowly in
// the current instead of the wind. Vertex COLOR (GrassKit): rgb the blade's own
// shade times SHADE_SCALE, or with a = 0 the fixed colour of a petal or seed head. UV2 is
// the distance over which the species thins out. Where it is cold (ClimateWear, and up
// toward the snow line) the grass is winter-killed straw with snow and hoar frost on it.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

global uniform float wind_strength;
global uniform vec2 wind_dir;
global uniform float wind_time;
uniform float night_glow = 1.0;
uniform float detail = 1.0; // graphics setting "detail_distance"
const float SHADE_SCALE = 0.7;
varying float glow;
varying vec3 tint;
varying float shade;
varying vec3 winter; // dead (straw), snow on the blades, hoar frost
varying vec3 blade_wp;
// Winter-killed grass: pale straw to a darker russet, linear.
const vec3 STRAW = vec3(0.36, 0.27, 0.14);
const vec3 RUSSET = vec3(0.2, 0.12, 0.06);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Blades under a pixel wide (GrassKit's CUSTOM0): from the distance where a blade is
	// one pixel across to twice that, every other one narrows to nothing (its triangles
	// are then skipped) and the rest widen to twice their width, so the field keeps its
	// cover and colour for half the blades. A pixel's size per metre of distance follows
	// the field of view, the resolution and the render scale.
	if (CUSTOM0.w != 0.0) {
		float px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float bw = abs(CUSTOM0.w) * length(MODEL_MATRIX[0].xyz);
		float k = clamp(length(wp - CAMERA_POSITION_WORLD) * px / bw - 1.0, 0.0, 1.0);
		VERTEX += CUSTOM0.xyz * (CUSTOM0.w > 0.0 ? k : -k);
	}
	// wind_time is the wind's own clock: it runs faster in a strong wind but never jumps,
	// so blades never snap when the wind changes.
	float t = wind_time * 1.3 + dot(wp.xz, wind_dir) * 0.35;
	float sway = sin(t) * 0.45 + sin(t * 2.3 + wp.x * 0.7) * 0.15;
	// Gusts roll across a field as broad waves travelling with the wind.
	float wave = smoothstep(0.2, 1.0, sin(dot(wp.xz, wind_dir) * 0.045 - wind_time * 0.55 + sin(wp.x * 0.013) * 1.5));
	float bend = UV.y * UV.y * (0.1 + wind_strength * 0.75) * (sway + wind_strength * 0.7 + wave * (0.25 + wind_strength * 0.6));
	vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	if (INSTANCE_CUSTOM.a < -0.5) {
		// Under water: a slow to-and-fro, each clump in its own phase, the same in any wind.
		float ph = TIME * 0.7 + wp.x * 0.37 + wp.z * 0.23;
		bend = UV.y * UV.y * (sin(ph) * 0.32 + sin(ph * 2.3 + 1.7) * 0.1);
		local_wind = (inverse(MODEL_MATRIX) * vec4(0.8, 0.0, 0.6, 0.0)).xyz;
	}
	VERTEX.xz += normalize(local_wind.xz + vec2(0.0001)) * bend;
	VERTEX.y -= abs(bend) * 0.3;
	glow = max(INSTANCE_CUSTOM.a, 0.0);
	// Tints are authored as sRGB colours; shading happens in linear space.
	tint = pow(max(INSTANCE_CUSTOM.rgb, vec3(0.0)), vec3(2.2)) * (1.0 - 0.42 * cloud_shadow(wp));
	shade = 1.0 - 0.42 * cloud_shadow(wp);
	winter = vec3(0.0);
	if (INSTANCE_CUSTOM.a > -0.5) {
		vec4 lv = wear_levels(wp);
		// Dead where snow lies or frost bites every night; snow on the blades only where
		// it lies, in patches, and the frost of a cold dawn.
		float patch = vnoise(wp.xz * 0.21 + 5.3);
		winter = vec3(smoothstep(0.4, 0.85, lv.y + (patch - 0.5) * 0.2),
			smoothstep(0.55, 1.0, lv.y) * (0.45 + 0.55 * patch), wear_frost(lv));
	}
	blade_wp = wp;
	// Thin out with distance: each clump has its own cut-off, so the field thins evenly
	// instead of a hard edge; the clumps that remain grow a little to keep the cover.
	float far = smoothstep(UV2.x * detail, UV2.y * detail, length(wp - CAMERA_POSITION_WORLD));
	vec3 p3 = fract(vec3(wp.xzx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	float pick = fract((p3.x + p3.y) * p3.z);
	VERTEX *= smoothstep(pick, pick + 0.12, (1.0 - far) * 1.12) * (1.0 + far * 0.4);
}

void fragment() {
	bool own = COLOR.a < 0.5;
	vec3 base = own ? pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)) * shade : tint * COLOR.rgb / SHADE_SCALE;
	if (!own) {
		// GrassKit's dry blades and yellowing tips are warmer than they are blue: a shade
		// can only scale the green tint, which kept even a dead blade green, so they turn
		// toward straw here, as bright as the blade.
		float dry = smoothstep(0.1, 0.4, (COLOR.r - COLOR.b) / SHADE_SCALE);
		vec3 straw = vec3(0.42, 0.33, 0.13);
		straw *= dot(base, vec3(0.2126, 0.7152, 0.0722)) / dot(straw, vec3(0.2126, 0.7152, 0.0722)) * 1.5;
		base = mix(base, straw, dry);
	}
	float rough = 0.85;
	if (winter.x > 0.0) {
		// Each blade its own shade of straw, keeping its own light and dark.
		float l = dot(base, vec3(0.2126, 0.7152, 0.0722)) / max(dot(tint, vec3(0.2126, 0.7152, 0.0722)), 0.01);
		vec3 dead = mix(RUSSET, STRAW, hash12(blade_wp.xz * 3.1 + COLOR.rg * 17.0)) * clamp(l, 0.5, 1.4) * shade;
		base = mix(base, dead, winter.x * (own ? 0.8 : 1.0));
	}
	vec3 alb = own ? base : mix(base * 0.35, base * 1.05, UV.y);
	// Snow caught along the blades, thickest up the blade where it bends over, and rime.
	float sn = winter.y * smoothstep(0.15, 0.9, UV.y + (hash12(blade_wp.xz * 7.7 + UV.x) - 0.5) * 0.5) * 0.4;
	float fr = winter.z * (0.1 + 0.25 * UV.y) * (0.5 + hash12(blade_wp.xz * 5.3 + UV.y * 9.0));
	alb = mix(alb, WEAR_SNOW * shade, sn);
	alb = mix(alb, WEAR_FROST * shade, clamp(fr, 0.0, 0.3) * (1.0 - sn));
	base = mix(base, alb, max(sn, fr));
	ALBEDO = alb;
	ROUGHNESS = mix(rough, 0.6, sn);
	SPECULAR = 0.3;
	BACKLIGHT = base * (own ? 0.3 : 0.45);
	// Rounded across the blade, and leaning toward up so a field shades like a surface.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec3 n = normalize(mix(NORMAL, up, 0.55));
	NORMAL = normalize(n + cross(n, up) * (UV.x - 0.5) * 0.6);
	EMISSION = base * glow * smoothstep(0.75, 1.0, UV.y) * 1.2 * night_glow;
}
