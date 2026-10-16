shader_type spatial;
// Kit base body dressed by region. CUSTOM0 carries, per vertex: x = body region (from the
// dominant skin bone), y = rest-pose height, z = rest-pose |x|. Each person sets their own
// colours and cut through instance uniforms, so everyone shares one material.
//   regions: 0 head/neck, 1 torso, 2 upper arm, 3 forearm, 4 hand, 5 hips/thigh, 6 shin, 7 foot
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float skin_mean = 0.45;

instance uniform vec4 skin_col : source_color = vec4(0.8, 0.6, 0.5, 1.0);
instance uniform vec4 shirt_col : source_color = vec4(0.5, 0.4, 0.3, 1.0);
instance uniform vec4 pants_col : source_color = vec4(0.3, 0.28, 0.25, 1.0);
instance uniform vec4 boot_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);
instance uniform vec4 accent_col : source_color = vec4(0.0);
// x: sleeves (0 none, 1 short, 2 long), y: boot top height, z: robe hem height (0 = none),
// w: hit flash.
instance uniform vec4 cut = vec4(2.0, 0.35, 0.0, 0.0);
// First-person arms: everything but the arms and hands is cut away.
instance uniform float arms_only = 0.0;

varying vec3 rest;

void vertex() {
	rest = CUSTOM0.xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 tex = texture(skin_tex, UV).rgb;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114)) / skin_mean;
	int region = int(rest.x + 0.5);
	float h = rest.y;
	if (arms_only > 0.5 && (region < 2 || region > 4)) {
		discard;
	}
	// 0 skin, 1 shirt, 2 trousers, 3 boots
	int part = 0;
	if (region == 1) part = 1;
	else if (region == 2) part = cut.x >= 1.0 ? 1 : 0;
	else if (region == 3) part = cut.x >= 2.0 ? 1 : 0;
	else if (region == 5) part = 2;
	else if (region == 6) part = h < cut.y ? 3 : 2;
	else if (region == 7) part = 3;
	// A robe or long coat carries the shirt down over the legs to its hem.
	if ((part == 2 || (part == 3 && h > 0.2)) && cut.z > 0.0 && h > cut.z) part = 1;
	vec3 col;
	float rough = 0.9;
	float nd = 0.35;
	if (part == 0) {
		col = skin_col.rgb * clamp(lum, 0.6, 1.4);
		rough = 0.55;
		nd = 1.0;
	} else {
		// Woven cloth: a fine thread pattern and a little fold shading from the body texture.
		vec2 w = UV * 900.0;
		float weave = 0.93 + 0.07 * (sin(w.x) * sin(w.y));
		float fold = mix(1.0, clamp(lum, 0.7, 1.2), 0.35);
		col = (part == 1 ? shirt_col.rgb : (part == 2 ? pants_col.rgb : boot_col.rgb)) * weave * fold;
		if (part == 3) rough = 0.6;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = nd;
	// Sci-fi suits: a glowing seam down each side of the torso and along the sleeves.
	if (accent_col.a > 0.0 && part == 1) {
		float seam = (region == 1) ? 1.0 - smoothstep(0.004, 0.012, abs(rest.z - 0.13)) : 0.0;
		EMISSION = accent_col.rgb * seam * 2.5;
	}
	EMISSION += vec3(0.6, 0.05, 0.02) * cut.w;
}
