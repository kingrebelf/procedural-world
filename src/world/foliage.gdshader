shader_type spatial;
// Leaves and needles: alpha-scissored cards (or the opaque leaf core when is_core) that
// sway with the world wind. Displacement grows with height above the mesh origin, so
// trunks stay planted while crowns move; the phase comes from the instance position so
// neighbouring trees never move in lockstep. Where it is cold (ClimateWear) snow dusts the
// tops of leaves and boughs, and hoar frost rimes them on cold mornings.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/plant_look.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Repeats of the leaf texture across a card: >1 makes individual leaves smaller.
uniform float uv_scale = 1.0;
uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 back : source_color = vec3(0.3, 0.35, 0.12);
uniform bool is_core = false;
uniform float sway = 1.0;
// RealTree crowns: vertex normals point out of the crown volume. Godot flips a back
// face's normal before the fragment runs, which would light half the cards from inside,
// so the crown normal is passed through unflipped instead.
uniform bool crown_normals = false;
uniform float alpha_cut = 0.45;
// Darkens a card toward its stem (UV.x 0, the spruce bough's trunk end): the inside of a
// dense crown, where the light doesn't reach.
uniform float stem_shade = 0.0;
// How far crown normals lean toward the sky. Conifer boughs are flat layers, each lit on
// top; a narrow spire's outward normals left its lower half facing the ground, black.
uniform float crown_up = 0.2;
// Each plant its own shade, dry sprays and thin side (plant_look.gdshaderinc). Off on the
// merged far mesh, which has them baked in.
uniform bool individual = false;

varying vec3 inst_col;
varying vec3 crown_n;
varying vec4 look;
varying vec3 plant_p;
varying vec3 winter; // snow lying, hoar frost, a patch value

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	look = individual ? plant_look(origin) : vec4(0.0);
	plant_p = VERTEX;
	float h = max(VERTEX.y, 0.0);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float t = wind_time; // the wind's own clock, so a change in wind never makes leaves jump
	float ws = wind_strength;
	// Slow whole-crown lean plus faster leaf flutter, and the same rolling gust waves the
	// grass shows.
	float wave = smoothstep(0.2, 1.0, sin(dot(origin.xz, wind_dir) * 0.045 - t * 0.55 + sin(origin.x * 0.013) * 1.5));
	float lean = (sin(t * 0.6 + phase) * 0.4 + 0.6 + wave * 0.5) * ws;
	float flutter = sin(t * 3.5 + VERTEX.x * 2.1 + VERTEX.z * 1.7 + phase * 3.0) * 0.07 * (0.3 + ws);
	// Bend grows with height but is capped, so tall trees sway rather than tilt over.
	float k = min(h * h * 0.006, 0.6) * sway;
	vec3 wl = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	vec2 wd = normalize(wl.xz + vec2(0.0001));
	VERTEX.xz += wd * k * lean * 1.2;
	// Flutter is a leaf's own trembling: it doesn't grow with a small plant's extra bend
	// (multiplying it by that made bushes thrash as if in a gale).
	VERTEX += NORMAL * flutter * min(h * 0.3, 1.0) * min(sway, 1.0);
	// Vertex and instance colours are authored as sRGB; shading happens in linear space.
	inst_col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	crown_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 lv = wear_levels(vw);
	winter = vec3(smoothstep(0.55, 1.0, lv.y), wear_frost(lv), vnoise(vw.xz * 0.9 + vw.y * 0.7));
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex = is_core ? vec4(0.55, 0.62, 0.5, 1.0) : texture(albedo_tex, uv);
	// Thin needles and leaf tips average away in distant mip levels; raising alpha with the
	// mip level keeps far cards as full as near ones instead of breaking into speckles.
	vec2 px = uv * vec2(textureSize(albedo_tex, 0));
	float lod = max(0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))), 0.0);
	tex.a *= 1.0 + lod * 0.28;
	if (!is_core && tex.a < alpha_cut) {
		discard;
	}
	if (individual && plant_gap(plant_p, look, COLOR.a)) {
		discard;
	}
	ALBEDO = tex.rgb * albedo * inst_col * mix(1.0 - stem_shade, 1.0, smoothstep(0.05, 0.75, UV.x));
	if (individual) {
		ALBEDO = plant_leaf(ALBEDO, look, COLOR.a);
	}
	// Bend normals toward the sky: cards facing the ground otherwise render near black.
	vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	// The core's underside would otherwise go black in its own shadow.
	if (crown_normals) {
		NORMAL = normalize(mix(normalize(crown_n), up_v, crown_up));
	} else {
		NORMAL = normalize(mix(NORMAL, up_v, is_core ? 0.8 : 0.55));
	}
	ROUGHNESS = 0.8;
	SPECULAR = crown_normals ? 0.25 : 0.35;
	BACKLIGHT = back * inst_col * 1.4;
	if (winter.x + winter.y > 0.01) {
		// Snow lies on what faces the sky, in clumps, leaving the undersides dark; rime
		// catches every edge.
		float up = dot(NORMAL, up_v);
		float sn = winter.x * smoothstep(0.25, 0.75, up + (winter.z - 0.5) * 0.6) * 0.8;
		float fr = clamp(winter.y * (0.2 + 0.35 * up), 0.0, 0.45) * (1.0 - sn);
		ALBEDO = mix(mix(ALBEDO, WEAR_FROST, fr), WEAR_SNOW, sn);
		ROUGHNESS = mix(0.8, 0.6, sn);
		BACKLIGHT *= 1.0 - 0.8 * sn;
	}
}
