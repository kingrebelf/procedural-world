shader_type spatial;
// What lies on a market square's setts: earth trodden in from the unpaved ground at the
// rim (COLOR.r), the kennel down the middle of a street, damp and dark with standing
// water (COLOR.g), patches of mud, wisps of straw dropped from the carts, and puddles
// in the hollows. All of it follows world position, so no two squares are alike. Where
// snow lies on the ground round the town it lies on the setts too (climate_wear).
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/env/climate_wear.gdshaderinc"

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float g_vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

float g_fbm(vec2 p) {
	return g_vnoise(p) * 0.55 + g_vnoise(p * 2.07) * 0.3 + g_vnoise(p * 4.3) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz;
	float rim = COLOR.r;
	float kennel = COLOR.g;
	vec3 earth = vec3(0.22, 0.17, 0.12) * (0.85 + 0.3 * g_vnoise(q * 5.0));
	// Earth at the rim, broken up so it reaches in further in places; mud patches inside.
	float n = g_fbm(q * 0.45);
	float a = smoothstep(0.35, 0.95, rim + (n - 0.5) * 0.7);
	a = max(a, smoothstep(0.62, 0.78, g_fbm(q * 0.3 + 7.0)) * 0.7);
	// Dirt packed between the stones everywhere: a faint film that never quite goes away.
	a = max(a, 0.12 + 0.1 * g_vnoise(q * 2.3));
	vec3 col = earth;
	float rough = 0.95;
	// Straw: short bright wisps scattered in drifts.
	vec2 sc = q * vec2(9.0, 9.0);
	vec2 cell = floor(sc);
	float h = hash2(cell);
	float ang = h * 6.2831;
	vec2 lp = fract(sc) - 0.5;
	vec2 dir = vec2(cos(ang), sin(ang));
	float along = dot(lp, dir);
	float across = abs(dot(lp, vec2(-dir.y, dir.x)));
	float wisp = (1.0 - smoothstep(0.02, 0.05, across)) * (1.0 - smoothstep(0.3, 0.42, abs(along)));
	float drift = smoothstep(0.5, 0.7, g_fbm(q * 0.6 + 3.0));
	float straw = wisp * step(0.55, h * 1.3 * drift + 0.0) * drift;
	col = mix(col, vec3(0.62, 0.5, 0.25) * (0.8 + 0.4 * hash2(cell + 9.0)), straw);
	a = max(a, straw * 0.95);
	// The kennel: wet and dark, with water standing along it; small puddles in the
	// hollows, a damp dark ring round each. The water is near black and glassy, so what
	// it shows is the sky's reflection.
	float wet = kennel * (0.75 + 0.25 * g_vnoise(q * 1.7));
	float pf = g_fbm(q * 0.55 + 21.0);
	float pud = smoothstep(0.76, 0.8, pf) + kennel * smoothstep(0.55, 0.65, g_vnoise(q * 1.3 + 5.0));
	pud = clamp(pud, 0.0, 1.0);
	float damp = max(wet, smoothstep(0.7, 0.76, pf));
	col = mix(col, vec3(0.1, 0.085, 0.07), damp * 0.5);
	a = max(a, damp * 0.45);
	rough = mix(rough, 0.4, damp);
	col = mix(col, vec3(0.05, 0.055, 0.06), pud);
	rough = mix(rough, 0.04, pud);
	a = max(a, pud * 0.75);
	a = clamp(a, 0.0, 1.0);
	// Snow, wherever it lies on the ground round about (wear_snow, the terrain's own
	// rule): thick and unbroken at the rim, where the setts meet the snowy ground, so the
	// ragged edge of the stones doesn't show through as squares; swept into soft drifts
	// against the walls; trodden to a thin grey slush across the middle of the square and
	// down the streets, the stones showing through in patches and melted along the kennel.
	float s_lvl = wear_snow(wpos);
	float snow_a = 0.0;
	if (s_lvl > 0.01) {
		float open = wear_shelter(wpos, vec3(0.0, 1.0, 0.0)).x;
		float n1 = g_fbm(q * 0.35 + 11.0);
		float n2 = g_fbm(q * 1.9 + 4.0);
		float n3 = g_vnoise(q * 7.0 + 2.0);
		// A wall close by: the top of everything (the shelter map) stands a storey over
		// this point within a metre or two. A tree's crown, higher up, doesn't count.
		float wall = 0.0;
		for (int i = 0; i < 6; i++) {
			float ang = float(i) * 1.0472 + n1 * 2.0;
			vec2 d = vec2(cos(ang), sin(ang));
			for (int k = 0; k < 2; k++) {
				float r = 0.6 + float(k) * 0.9;
				float t = wear_top(q + d * r) - wpos.y;
				wall = max(wall, smoothstep(1.2, 2.2, t) * (1.0 - smoothstep(9.0, 13.0, t)) * (1.0 - float(k) * 0.45));
			}
		}
		float drift = smoothstep(0.25, 0.75, wall + (n2 - 0.5) * 0.6);
		// The outermost setts (the frayed quarter cells) always closed over, so none of
		// their squares stands bare against the ground's snow.
		float edge = max(smoothstep(0.2, 0.75, rim + (n1 - 0.5) * 0.7 + (n3 - 0.5) * 0.12), smoothstep(0.55, 0.8, rim));
		// Trodden: patches of packed snow with soft edges and the stones bare between,
		// fewer where feet and wheels go most (the kennel's line). Packed snow is opaque,
		// not a veil, so the setts' cell-by-cell tones don't show through it as squares.
		float trod = smoothstep(0.38, 0.58, n1 * 0.6 + n2 * 0.4 + (n3 - 0.5) * 0.15 + 0.2 * s_lvl - 0.3 * kennel);
		float sa = max(max(edge, drift), trod) * smoothstep(0.0, 0.5, s_lvl) * open;
		float deep = max(edge, drift);
		vec3 slush = mix(vec3(0.36, 0.36, 0.37), vec3(0.5, 0.53, 0.57), n2) * (1.0 - 0.3 * kennel);
		// The ground's own snow colour (the terrain's snow texture, linear mean, at the
		// 0.8 it draws it), so the setts' rim doesn't stand out from the snow round it.
		vec3 sc = mix(slush, vec3(0.51, 0.56, 0.62) * (0.95 + 0.1 * n3), smoothstep(0.2, 0.8, deep));
		float out_a = sa + a * (1.0 - sa);
		col = (sc * sa + col * a * (1.0 - sa)) / max(out_a, 1e-4);
		// Matte as the open snow beside it, and lit as level ground rather than by each
		// sett cell's own tilt, so the cells don't read as lighter and darker squares.
		rough = mix(rough, 0.85, sa);
		pud *= 1.0 - sa;
		a = out_a;
		snow_a = sa;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, snow_a));
	SPECULAR = mix(mix(0.5, 0.6, pud), 0.3, snow_a);
	ALPHA = a;
}
