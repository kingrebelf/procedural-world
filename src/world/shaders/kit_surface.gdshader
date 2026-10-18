shader_type spatial;
// The village kit's surfaces (walls, roofs, beams, floors), drawn as their own glTF
// materials drew them (colour, normal and roughness/metal maps on the model's UVs, two
// sided) with the place's weathering over them (climate_wear.gdshaderinc): moss, snow,
// hoar frost and dust out of doors. BuildCatalog.worn() makes these from the imported
// materials. COLOR.a is how far a built piece has weathered (ClimateWear.maturity; 1 on
// everything that isn't the player's).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = false;
uniform float roughness = 1.0;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform float specular = 0.5;
uniform bool has_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
// How readily moss takes (BuildCatalog.MOSS_TAKE).
uniform float moss_take = 1.0;
// The material's mean brightness, so darker cracks and mortar can be told apart.
uniform float mean_lum = 0.35;

varying vec3 wp;
varying vec3 wn;
varying float base_y;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_y = MODEL_MATRIX[3].y;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 alb = albedo.rgb * t.rgb;
	if (use_vertex_color) {
		alb *= COLOR.rgb;
	}
	float rough = dot(texture(roughness_tex, UV), roughness_channel) * roughness;
	// The face's own normal, turned to face the viewer on a two-sided face's back.
	vec3 n = normalize(wn) * (FRONT_FACING ? 1.0 : -1.0);
	float lum = dot(alb, vec3(0.2126, 0.7152, 0.0722)) / max(mean_lum, 0.01);
	float snow = wear_building(alb, rough, wp, n, base_y, COLOR.a, moss_take, lum);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = dot(texture(metallic_tex, UV), metallic_channel) * metallic * (1.0 - snow);
	SPECULAR = specular;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale * (1.0 - 0.8 * snow);
	}
}
