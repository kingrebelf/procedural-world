shader_type spatial;
// Glass and the liquids inside it. The vertex colour is the tint and its alpha how much
// of the light behind gets through face on; at grazing angles both turn to mirror
// (Fresnel), so the walls of a bottle read as thick glass with bright edges.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float rough = 0.04;
uniform float edge_alpha = 0.92;
uniform float edge_power = 3.0;
// Light passing through: a liquid lit from behind shows its colour, never glows.
uniform float through = 0.0;
// How much it reflects face on (glass about 4%, the specular default of 0.5).
uniform float spec = 0.5;

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 tint = to_linear(COLOR.rgb);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - facing, edge_power);
	ALBEDO = tint;
	ALPHA = mix(COLOR.a, edge_alpha, f);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec + (1.0 - spec) * f;
	if (through > 0.0) {
		BACKLIGHT = tint * through;
	}
}
