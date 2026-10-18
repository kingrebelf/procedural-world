shader_type spatial;
// Masonry, slate and timber drawn as Materials' triplanar StandardMaterial3D draws them
// (object-space triplanar colour and normal maps, vertex colour as sRGB albedo) with the
// place's weathering over them (climate_wear.gdshaderinc): moss, snow, hoar frost and
// dust out of doors, nothing in rooms. Materials.worn() makes these for castles, town
// walls and towers, so their stone weathers with the houses and the ground round them.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform bool has_normal = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform float sharpness = 4.0;
uniform float moss_take = 1.0;
uniform float mean_lum = 0.35;

varying vec3 tri_w;
varying vec3 tri_p;
varying vec3 wp;
varying vec3 wn;
varying float base_y;

vec4 tri(sampler2D s) {
	return texture(s, tri_p.xy) * tri_w.z + texture(s, tri_p.xz) * tri_w.y + texture(s, tri_p.zy * vec2(-1.0, 1.0)) * tri_w.x;
}

void vertex() {
	TANGENT = normalize(vec3(0.0, 0.0, -1.0) * abs(NORMAL.x) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.y) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.z));
	BINORMAL = normalize(vec3(0.0, 1.0, 0.0) * abs(NORMAL.x) + vec3(0.0, 0.0, -1.0) * abs(NORMAL.y) + vec3(0.0, 1.0, 0.0) * abs(NORMAL.z));
	tri_w = pow(abs(NORMAL), vec3(sharpness));
	tri_w /= dot(tri_w, vec3(1.0));
	tri_p = VERTEX * uv1_scale * vec3(1.0, -1.0, 1.0);
	// Vertex colours are authored as sRGB.
	vec3 c = max(COLOR.rgb, vec3(0.0));
	COLOR.rgb = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_y = MODEL_MATRIX[3].y;
}

void fragment() {
	vec3 alb = albedo.rgb * tri(albedo_tex).rgb * COLOR.rgb;
	float rough = roughness;
	float lum = dot(alb, vec3(0.2126, 0.7152, 0.0722)) / max(mean_lum, 0.01);
	float snow = wear_building(alb, rough, wp, normalize(wn), base_y, 1.0, moss_take, lum);
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metallic * (1.0 - snow);
	SPECULAR = 0.5;
	if (has_normal) {
		NORMAL_MAP = tri(normal_tex).rgb;
		NORMAL_MAP_DEPTH = normal_scale * (1.0 - 0.8 * snow);
	}
}
