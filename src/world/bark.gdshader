shader_type spatial;
// RealTree bark: the bark photo (and its normal map) tinted by the vertex and instance
// colour, with each tree's own moss and lichen (plant_look.gdshaderinc): moss thickest at
// the foot of the trunk, on the tops of limbs and on the north side, lichen in pale
// blotches. Off on the merged far mesh (`individual` false), where it is too small to see.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/plant_look.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"

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

void vertex() {
	// Vertex and instance colours are authored as sRGB.
	col = pow(COLOR.rgb, vec3(2.2));
	plant_p = VERTEX;
	growth = vec2(0.0);
	seed = 0.0;
	if (individual) {
		vec4 r = plant_rand((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, 1u);
		// Most trees a little moss, some furred with it; lichen on about half.
		growth = vec2(r.x * r.x * moss_scale, smoothstep(0.45, 1.0, r.y));
		seed = r.z * 97.0;
	}
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo * col;
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
}
