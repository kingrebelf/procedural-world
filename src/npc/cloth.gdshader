shader_type spatial;
// Garments from Outfit: linen, knitted wool, velvet and worn leather from Ben's fabric
// sheets, tinted in the same per-person colours as human.gdshader, with folds on loose
// skirts and capes and gold embroidery on fine robes.
// CUSTOM0: x = part (1 shirt, 2 trousers, 3 boots, 4 belt, 5 skirt, 6 cape, 7 trim).
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/npc/fabric.gdshaderinc"

instance uniform vec4 shirt_col : source_color = vec4(0.5, 0.4, 0.3, 1.0);
instance uniform vec4 pants_col : source_color = vec4(0.3, 0.28, 0.25, 1.0);
instance uniform vec4 boot_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);
instance uniform vec4 accent_col : source_color = vec4(0.0);
instance uniform float flash = 0.0;
// era (0 medieval, 1 fantasy, 2 sci-fi), knit: a wool jumper, trim: velvet robes with
// embroidered hems.
instance uniform float era = 0.0;
instance uniform float knit = 0.0;
instance uniform float trim = 0.0;

uniform sampler2D linen : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wool : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D velvet : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leather : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gold_trim : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 rest;

void vertex() {
	rest = CUSTOM0.xyz;
	rest_pos = vec3(CUSTOM0.w, CUSTOM0.y, CUSTOM0.z);
	rest_n = CUSTOM1.xyz;
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
	int part = int(rest.x + 0.5);
	int age = int(era + 0.5);
	bool robe = trim > 0.5 && age < 2;
	vec3 col = shirt_col.rgb;
	float rough = 0.92;
	float metal = 0.0;
	float sheen = 0.0;
	if (part == 2) col = pants_col.rgb;
	else if (part == 3) { col = boot_col.rgb; rough = 0.55; }
	else if (part == 4) { col = mix(boot_col.rgb, vec3(0.16, 0.1, 0.06), 0.5); rough = 0.5; }
	else if (part == 6) col = mix(pants_col.rgb, shirt_col.rgb, 0.3) * 0.8;
	else if (part == 7) { col = pants_col.rgb * 0.7; rough = 0.6; }
	// The cloth itself: what it is, how big its weave is and how deep.
	float det;
	float relief;
	if (part == 3 || part == 4) {
		det = fabric(leather, rest_pos, rest_n, 0.22);
		relief = 0.0012;
		rough += (0.72 - det) * 0.5;
	} else if (part == 6 || (part == 5 && robe)) {
		det = fabric(velvet, rest_pos, rest_n, 0.3);
		relief = 0.0004;
		sheen = 0.45;
	} else if (part == 1 && knit > 0.5 && age < 2) {
		det = fabric(wool, rest_pos, rest_n, 0.085);
		relief = 0.0016;
	} else {
		det = fabric(linen, rest_pos, rest_n, age == 2 ? 0.045 : (part == 2 ? 0.13 : 0.1));
		relief = 0.0006;
	}
	col *= det / 0.72;
	float h = det * relief;
	if (part == 7 && age == 2) {
		// Quilted channels on the sci-fi vest.
		float q = abs(fract(rest.y * 14.0) - 0.5) * 2.0;
		col *= 0.75 + 0.25 * smoothstep(0.0, 0.35, q);
		h += smoothstep(0.0, 0.6, q) * 0.003;
	}
	if (part == 5 || part == 6) {
		// Hanging folds and a darker hem band, or embroidery on a fine robe or cape.
		float folds = 0.82 + 0.18 * sin(UV.x * 34.0 + vnoise(UV * vec2(6.0, 2.0)) * 3.0);
		col *= folds;
		float edge = part == 5 ? UV.y : UV.y / 1.5;
		if (robe && edge > 1.8 && edge < 1.97) {
			float t = (edge - 1.8) / 0.17;
			vec3 g = texture(gold_trim, vec2(UV.x * (part == 5 ? 5.0 : 3.8), 0.07 + t * 0.38)).rgb;
			float gold = smoothstep(0.12, 0.3, max(g.r, g.g) - g.b);
			col = mix(col * 0.35, g, gold) * mix(1.0, folds, 0.5);
			metal = gold * 0.6;
			rough = mix(0.8, 0.4, gold);
			h += gold * dot(g, vec3(0.33)) * 0.002;
			sheen = 0.0;
		} else {
			col = mix(col, col * 0.55, smoothstep(1.86, 1.92, edge));
			sheen = max(sheen, 0.25);
		}
	}
	if (part == 7 && accent_col.a > 0.0) {
		float seam = 1.0 - smoothstep(0.003, 0.009, abs(fract(rest.y * 18.0) - 0.5) * 0.06);
		EMISSION = accent_col.rgb * seam * 1.5;
	}
	vec3 n = NORMAL;
	if (!FRONT_FACING) {
		n = -n;
		col *= 0.6;
	}
	NORMAL = fabric_bump(n, VERTEX, h);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	RIM = sheen;
	RIM_TINT = 0.6;
	EMISSION += vec3(0.6, 0.05, 0.02) * flash;
}
