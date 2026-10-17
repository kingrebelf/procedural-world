shader_type spatial;
// Armour from Outfit, worn by people and the player. COLOR.rgb is the item's colour,
// COLOR.a * 8 its style: 0 leather, 1 mail, 2 plate, 3 mythril/crystal, 4 exo-suit, 5 cloth.
// Only mythril/crystal (alien) has a light of its own; human armour never glows.
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

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise over the rest pose, for dents, tone and wear that ride with the body.
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
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
	// Edges of each lame or band (where it overlaps the next) and how far into one we are.
	float edge = 1.0 - smoothstep(0.06, 0.16, min(band, 1.0 - band));
	float tone = vnoise(rest_pos * 14.0);
	float dents = vnoise(rest_pos * 38.0) + 0.3 * vnoise(rest_pos * 110.0);
	float scuff = smoothstep(0.62, 0.8, vnoise(rest_pos * 45.0 + 3.1));
	if (style == 0) {
		metal = 0.0;
		rough = 0.65;
		float det = fabric(leather, rest_pos, rest_n, 0.25);
		col *= det / 0.72 * mix(0.75, 1.0, groove);
		// Burnished, darker edges and a row of saddle stitches just inside each one.
		col *= mix(1.0, 0.72, edge);
		float stitch_row = 1.0 - smoothstep(0.0, 0.012, abs(min(band, 1.0 - band) - 0.11));
		float dash = step(0.45, fract((rest_pos.x + rest_pos.z) * 140.0));
		col = mix(col, tint.rgb * 1.35 + vec3(0.08), stitch_row * dash * 0.8);
		rough += (0.72 - det) * 0.4 - edge * 0.15;
		h = det * 0.0012 + groove * 0.0015 - stitch_row * dash * 0.0004;
	} else if (style == 1) {
		// Mail: rows of interlocking rings, dark between them.
		float ring = clamp(fabric(chainmail, rest_pos, rest_n, 0.13) / 0.72, 0.0, 1.4);
		col *= mix(0.12, 1.15, ring * ring);
		rough = mix(0.85, 0.3, clamp(ring, 0.0, 1.0));
		// Rust and grime collect where rings overlap in the folds.
		col = mix(col, vec3(0.32, 0.18, 0.1) * 0.5, (1.0 - ring) * smoothstep(0.55, 0.8, tone) * 0.6);
		h = ring * 0.0025;
	} else if (style == 2) {
		// Forged plate: never mirror-flat. Hammer dents, a tone that wanders where the
		// smith worked it, edges rubbed bright by wear, grime and oil dark in the overlaps,
		// round rivet heads holding the lames.
		// Steel reflects about 55-60%: item colours near white would read as chrome.
		col = min(col, vec3(0.68)) * mix(0.45, 1.0, groove) * (0.85 + 0.22 * tone);
		col = mix(col, col * 1.35 + vec3(0.04), edge * groove * 0.6);
		col = mix(col, col * 0.55, (1.0 - groove) * 0.5);
		float rivet = step(0.985, hash(floor(UV * 120.0))) * (1.0 - groove);
		col += rivet * 0.25;
		rough = 0.32 + 0.22 * tone + 0.08 * scuff - edge * 0.12 + (1.0 - groove) * 0.25;
		h = groove * 0.002 + (dents - 0.65) * 0.0005 + rivet * 0.0008;
	} else if (style == 3) {
		// Mythril and crystal: alien work, the only armour with a faint light of its own.
		metal = 0.75;
		rough = 0.18;
		col *= mix(0.6, 1.05, groove);
		emit = tint.rgb * (1.0 - groove) * 0.25;
	} else if (style == 5) {
		// Quilted cloth and wool: matte, soft stitched rows, no shine.
		metal = 0.0;
		rough = 0.9;
		float det = fabric(leather, rest_pos * 1.8, rest_n, 0.35);
		col *= mix(0.7, 1.0, det / 0.72) * mix(0.82, 1.0, groove);
		h = groove * 0.001;
	} else {
		// Human sci-fi armour: painted composite plates over a dark undersuit. Panel
		// seams are dark recesses (nothing lit), paint scuffed through to bare alloy on
		// the edges, a tinted glass visor that only reflects.
		metal = 0.25;
		rough = 0.42 + 0.12 * tone;
		float seam = step(0.985, fract(UV.x * 9.0));
		float gap = clamp(seam + (1.0 - groove), 0.0, 1.0);
		col *= (1.0 - 0.7 * gap) * (0.92 + 0.12 * tone);
		float bare = edge * groove * scuff;
		col = mix(col, vec3(0.55, 0.56, 0.58), bare);
		metal = mix(metal, 0.9, bare);
		rough = mix(rough, 0.35, bare);
		h = groove * 0.0015 - seam * 0.0008;
		if (part == 5 && rest.z > 0.04 && abs(rest.y - visor_y) < 0.03) {
			col = vec3(0.02, 0.025, 0.03);
			metal = 0.1;
			rough = 0.04;
			h = 0.0;
		}
	}
	NORMAL = fabric_bump(NORMAL, VERTEX, h);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emit + vec3(0.6, 0.05, 0.02) * flash;
}
