shader_type spatial;
// RealTree bark: the bark photo (and its normal map) tinted by the vertex and instance
// colour, with each tree's own moss and lichen (plant_look.gdshaderinc): moss thickest at
// the foot of the trunk, on the tops of limbs and on the north side, lichen in pale
// blotches. The place's climate (climate_wear.gdshaderinc) furs it with moss where it is
// wet and bares it where it is dry, and lays snow along the limbs and hoar frost on cold
// mornings where it is cold. Off on the merged far mesh (`individual` false), where it is
// too small to see.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/plant_look.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_scale = 1.3;
uniform vec3 albedo : source_color = vec3(1.0);
uniform bool individual = false;
// Smooth pale bark (birch) holds less moss.
uniform float moss_scale = 1.0;

varying vec3 col;
varying vec3 plant_p;
varying vec2 growth; // moss, lichen
varying float seed;
varying vec3 tone;
varying vec3 wp;

void vertex() {
	// Vertex and instance colours are authored as sRGB.
	col = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	plant_p = VERTEX;
	growth = vec2(0.0);
	seed = 0.0;
	tone = vec3(1.0);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (individual) {
		vec4 r = plant_rand((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, 1u);
		// Each trunk its own lit grey-brown: cool grey to warm brown, lighter or darker.
		tone = mix(vec3(0.95, 0.97, 1.0), vec3(1.08, 0.97, 0.84), r.w) * (0.85 + 0.35 * fract(r.z * 5.3));
		// From bare to furred with moss; lichen on about two thirds.
		vec4 lv = wear_levels(MODEL_MATRIX[3].xyz);
		growth = vec2(r.x * moss_scale * clamp(lv.x / WEAR_TEMPERATE.x, 0.0, 2.0), smoothstep(0.35, 1.0, r.y) * clamp(1.6 - lv.x, 0.4, 1.2));
		seed = r.z * 97.0;
	}
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo * col * tone;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ROUGHNESS = 0.92;
	if (growth.x + growth.y > 0.001) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec2 q = vec2(plant_p.x + plant_p.z, plant_p.y) + seed;
		float n = vnoise(q * 2.2) * 0.6 + vnoise(q * 7.3 + 5.1) * 0.4;
		float foot = 1.0 - smoothstep(0.2, 1.5 + 3.0 * growth.x, plant_p.y);
		float up = smoothstep(0.15, 0.75, wn.y);
		float north = smoothstep(-0.3, 0.9, -wn.z);
		float m = (foot * 0.9 + up * 0.7) * (0.45 + 0.55 * north) * growth.x * 1.8 - (1.0 - n) * 0.75;
		m = smoothstep(0.05, 0.4, m);
		vec3 moss = vec3(0.075, 0.11, 0.025) * (0.7 + 0.7 * n);
		ALBEDO = mix(ALBEDO, moss, m);
		ROUGHNESS = mix(ROUGHNESS, 1.0, m);
		float l = smoothstep(0.7, 0.78, vnoise(q * 4.1 + 31.0)) * growth.y * (1.0 - m);
		ALBEDO = mix(ALBEDO, vec3(0.32, 0.34, 0.26), l * 0.75);
	}
	if (individual) {
		vec4 lv = wear_levels(wp);
		float frost = wear_frost(lv);
		float s_lvl = smoothstep(0.35, 0.85, lv.y);
		if (frost + s_lvl > 0.01) {
			vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
			vec2 q = vec2(plant_p.x + plant_p.z, plant_p.y) + seed;
			float up = smoothstep(0.2, 0.8, wn.y);
			// Snow along the tops of limbs, hoar frost furring the bark on its upper side.
			float sn = smoothstep(0.35, 0.65, up * s_lvl * 1.4 + (vnoise(q * 3.1) - 0.5) * 0.5);
			ALBEDO = mix(ALBEDO, WEAR_SNOW, sn);
			float fm = frost * (0.12 + 0.4 * up + 0.3 * smoothstep(0.45, 0.9, vnoise(q * 19.0))) * (1.0 - sn);
			ALBEDO = mix(ALBEDO, WEAR_FROST, clamp(fm, 0.0, 0.55));
			ROUGHNESS = mix(ROUGHNESS, 0.6, sn);
		}
	}
}
