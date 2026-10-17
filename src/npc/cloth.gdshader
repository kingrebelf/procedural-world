shader_type spatial;
// Garments from Outfit: woven cloth, leather boots and belts, folds on loose skirts and
// capes. Colours come from the same per-person instance uniforms as human.gdshader.
// CUSTOM0: x = part (1 shirt, 2 trousers, 3 boots, 4 belt, 5 skirt, 6 cape, 7 trim).
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

instance uniform vec4 shirt_col : source_color = vec4(0.5, 0.4, 0.3, 1.0);
instance uniform vec4 pants_col : source_color = vec4(0.3, 0.28, 0.25, 1.0);
instance uniform vec4 boot_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);
instance uniform vec4 accent_col : source_color = vec4(0.0);
instance uniform float flash = 0.0;

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
	int part = int(rest.x + 0.5);
	vec3 col = shirt_col.rgb;
	float rough = 0.92;
	float sheen = 0.0;
	if (part == 2) col = pants_col.rgb;
	else if (part == 3) { col = boot_col.rgb; rough = 0.55; }
	else if (part == 4) { col = mix(boot_col.rgb, vec3(0.16, 0.1, 0.06), 0.5); rough = 0.5; }
	else if (part == 6) col = mix(pants_col.rgb, shirt_col.rgb, 0.3) * 0.8;
	else if (part == 7) { col = pants_col.rgb * 0.7; rough = 0.6; }
	vec2 w = UV * (part >= 5 ? 220.0 : 900.0);
	float weave = 0.92 + 0.08 * (sin(w.x) * sin(w.y));
	float n = vnoise(UV * 30.0);
	col *= weave * (0.9 + 0.2 * n);
	if (part == 5 || part == 6) {
		// Hanging folds and a darker hem band.
		float folds = 0.82 + 0.18 * sin(UV.x * 34.0 + vnoise(UV * vec2(6.0, 2.0)) * 3.0);
		col *= folds;
		float edge = part == 5 ? UV.y : UV.y / 1.5;
		col = mix(col, col * 0.55, smoothstep(1.86, 1.92, edge));
		sheen = 0.25;
	}
	if (part == 3 || part == 4) {
		// Leather: creases and wear.
		col *= 0.85 + 0.25 * vnoise(UV * 160.0);
	}
	if (part == 7 && accent_col.a > 0.0) {
		float seam = 1.0 - smoothstep(0.003, 0.009, abs(fract(rest.y * 18.0) - 0.5) * 0.06);
		EMISSION = accent_col.rgb * seam * 1.5;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		col *= 0.6;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	RIM = sheen;
	RIM_TINT = 0.6;
	EMISSION += vec3(0.6, 0.05, 0.02) * flash;
}
