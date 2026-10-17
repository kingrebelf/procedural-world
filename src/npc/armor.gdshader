shader_type spatial;
// Armour from Outfit, worn by people and the player. COLOR.rgb is the item's colour,
// COLOR.a * 8 its style: 0 leather, 1 mail, 2 plate, 3 mythril/crystal, 4 exo-suit, 5 cloth.
// CUSTOM0: x = slot part (1 chest, 2 legs, 3 feet, 4 hands, 5 head), y = rest height,
// z = rest depth, w = rest side; CUSTOM1 the rest normal (see fabric.gdshaderinc).
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/npc/fabric.gdshaderinc"

instance uniform float visor_y = 1.68;
instance uniform float flash = 0.0;
// First-person arms (as human.gdshader): 1 both arms, 2 only the -x arm, 3 only the +x
// arm; everything nearer the middle than arms_x is cut away.
instance uniform float arms_only = 0.0;
instance uniform float arms_x = 0.25;

uniform sampler2D chainmail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leather : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 rest;
varying vec4 tint;

void vertex() {
	rest = CUSTOM0.xyz;
	tint = COLOR;
	rest_pos = vec3(CUSTOM0.w, CUSTOM0.y, CUSTOM0.z);
	rest_n = CUSTOM1.xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	if (arms_only > 0.5) {
		bool other_arm = (arms_only > 1.5 && arms_only < 2.5 && rest_pos.x > 0.0) || (arms_only > 2.5 && rest_pos.x < 0.0);
		if (abs(rest_pos.x) < arms_x || other_arm) {
			discard;
		}
	}
	int style = int(tint.a * 8.0 + 0.5);
	int part = int(rest.x + 0.5);
	vec3 col = tint.rgb;
	float metal = 0.9;
	float rough = 0.32;
	vec3 emit = vec3(0.0);
	float h = 0.0;
	float band = fract(rest.y * (style == 1 ? 28.0 : 12.0));
	float groove = smoothstep(0.0, 0.06, band) * smoothstep(1.0, 0.94, band);
	if (style == 0) {
		metal = 0.0;
		rough = 0.65;
		float det = fabric(leather, rest_pos, rest_n, 0.25);
		col *= det / 0.72 * mix(0.75, 1.0, groove);
		rough += (0.72 - det) * 0.4;
		h = det * 0.0012 + groove * 0.0015;
	} else if (style == 1) {
		// Mail: rows of interlocking rings, dark between them.
		float ring = clamp(fabric(chainmail, rest_pos, rest_n, 0.13) / 0.72, 0.0, 1.4);
		col *= mix(0.12, 1.15, ring * ring);
		rough = mix(0.85, 0.3, clamp(ring, 0.0, 1.0));
		h = ring * 0.0025;
	} else if (style == 2) {
		col *= mix(0.45, 1.0, groove);
		h = groove * 0.002;
		float rivet = step(0.985, hash(floor(UV * 120.0))) * (1.0 - groove);
		col += rivet * 0.25;
		rough = 0.28 + 0.15 * hash(floor(UV * 40.0));
	} else if (style == 3) {
		metal = 0.75;
		rough = 0.18;
		col *= mix(0.6, 1.05, groove);
		emit = tint.rgb * (1.0 - groove) * 0.6;
	} else if (style == 5) {
		// Quilted cloth and wool: matte, soft stitched rows, no shine.
		metal = 0.0;
		rough = 0.9;
		float det = fabric(leather, rest_pos * 1.8, rest_n, 0.35);
		col *= mix(0.7, 1.0, det / 0.72) * mix(0.82, 1.0, groove);
		h = groove * 0.001;
	} else {
		metal = 0.55;
		rough = 0.35;
		float seam = step(0.985, fract(UV.x * 9.0));
		col *= 1.0 - 0.45 * clamp(seam + (1.0 - groove), 0.0, 1.0);
		emit = vec3(0.3, 0.9, 1.0) * (1.0 - smoothstep(0.0, 0.03, band)) * 0.9;
		if (part == 5 && rest.z > 0.04 && abs(rest.y - visor_y) < 0.03) {
			col = vec3(0.02, 0.05, 0.08);
			metal = 1.0;
			rough = 0.05;
			emit = vec3(0.2, 0.7, 1.0) * 0.6;
		}
	}
	NORMAL = fabric_bump(NORMAL, VERTEX, h);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emit + vec3(0.6, 0.05, 0.02) * flash;
}
