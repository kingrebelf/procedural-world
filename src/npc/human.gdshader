shader_type spatial;
// Kit base body dressed by region. CUSTOM0 carries, per vertex: x = body region (from the
// dominant skin bone), y = rest-pose height, z = rest-pose x (signed). Each person sets their own
// colours and cut through instance uniforms, so everyone shares one material.
//   regions: 0 head/neck, 1 torso, 2 upper arm, 3 forearm, 4 hand, 5 hips/thigh, 6 shin, 7 foot
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform float skin_mean = 0.45;
// The texture's average skin colour, so its own warmth (flushed knuckles, lips, palms)
// carries over onto each person's skin tone.
uniform vec3 skin_avg = vec3(0.65, 0.45, 0.32);

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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 tex = texture(skin_tex, UV).rgb;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114)) / skin_mean;
	int region = int(rest.x + 0.5);
	float h = rest.y;
	// arms_only: 1 both arms, 2 only the arm on the -x side, 3 only the +x side.
	bool other_arm = (arms_only > 1.5 && arms_only < 2.5 && rest.z > 0.0) || (arms_only > 2.5 && rest.z < 0.0);
	if (arms_only > 0.5 && (region < 2 || region > 4 || other_arm)) {
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
	vec3 nm = texture(normal_tex, UV).rgb;
	if (part == 0) {
		// Skin: the person's tone, shaded by the texture's light and dark and part of its
		// colour (redder knuckles, palms and lips), a mottle of blotches, pores in the
		// normal, oilier where the texture says, and light scattering under the surface.
		vec3 hue = clamp(tex / skin_avg, vec3(0.55), vec3(1.6));
		hue /= max(dot(hue, vec3(0.299, 0.587, 0.114)), 0.01); // only the colour shift
		col = skin_col.rgb * clamp(lum, 0.55, 1.45) * mix(vec3(1.0), hue, 0.5);
		float blotch = vnoise(UV * 90.0) * 0.6 + vnoise(UV * 260.0) * 0.4;
		col *= mix(vec3(1.0), vec3(1.04, 0.97, 0.96), smoothstep(0.45, 0.85, blotch) * 0.6);
		col *= 0.96 + 0.06 * vnoise(UV * 700.0);
		if (region == 4) {
			// Hands run warmer and a little darker than the arm.
			col *= vec3(1.02, 0.98, 0.97);
		}
		float pore = vnoise(UV * 2600.0) - 0.5;
		float pore2 = vnoise(UV * 2600.0 + vec2(0.37, 0.0)) - 0.5;
		nm.xy += vec2(pore, pore2) * 0.12;
		rough = clamp(0.48 + 0.25 * (texture(rough_tex, UV).r - 0.82) + 0.08 * vnoise(UV * 400.0), 0.32, 0.75);
		nd = 1.2;
		SPECULAR = 0.35;
		SSS_STRENGTH = region == 4 ? 0.35 : 0.25;
		BACKLIGHT = skin_col.rgb * vec3(0.9, 0.4, 0.3) * (region == 4 ? 0.2 : 0.1);
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
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = nd;
	// Sci-fi suits: a glowing seam down each side of the torso and along the sleeves.
	if (accent_col.a > 0.0 && part == 1) {
		float seam = (region == 1) ? 1.0 - smoothstep(0.004, 0.012, abs(abs(rest.z) - 0.13)) : 0.0;
		EMISSION = accent_col.rgb * seam * 2.5;
	}
	EMISSION += vec3(0.6, 0.05, 0.02) * cut.w;
}
