shader_type spatial;
// Armour from Outfit, worn by people and the player. COLOR.rgb is the item's colour,
// COLOR.a * 8 its style: 0 leather, 1 mail, 2 plate, 3 mythril/crystal, 4 exo-suit.
// CUSTOM0: x = slot part (1 chest, 2 legs, 3 feet, 4 hands, 5 head), y = rest height,
// z = rest depth.
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform float visor_y = 1.68;
instance uniform float flash = 0.0;

varying vec3 rest;
varying vec4 tint;

void vertex() {
	rest = CUSTOM0.xyz;
	tint = COLOR;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	int style = int(tint.a * 8.0 + 0.5);
	int part = int(rest.x + 0.5);
	vec3 col = tint.rgb;
	float metal = 0.9;
	float rough = 0.32;
	vec3 emit = vec3(0.0);
	float band = fract(rest.y * (style == 1 ? 28.0 : 12.0));
	float groove = smoothstep(0.0, 0.06, band) * smoothstep(1.0, 0.94, band);
	if (style == 0) {
		metal = 0.0;
		rough = 0.65;
		col *= 0.6 + 0.25 * hash(floor(UV * 300.0));
		col *= mix(0.75, 1.0, groove);
	} else if (style == 1) {
		// Mail: rows of interlocking rings.
		vec2 g = UV * vec2(700.0, 900.0);
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		float d = length(fract(g) - 0.5);
		float ring = smoothstep(0.22, 0.3, d) * smoothstep(0.5, 0.42, d);
		col *= mix(0.25, 1.1, ring);
		rough = mix(0.8, 0.35, ring);
	} else if (style == 2) {
		col *= mix(0.45, 1.0, groove);
		float rivet = step(0.985, hash(floor(UV * 120.0))) * (1.0 - groove);
		col += rivet * 0.25;
		rough = 0.28 + 0.15 * hash(floor(UV * 40.0));
	} else if (style == 3) {
		metal = 0.75;
		rough = 0.18;
		col *= mix(0.6, 1.05, groove);
		emit = tint.rgb * (1.0 - groove) * 0.6;
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
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emit + vec3(0.6, 0.05, 0.02) * flash;
}
