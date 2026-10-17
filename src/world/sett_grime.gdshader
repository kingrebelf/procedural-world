shader_type spatial;
// What lies on a market square's setts: earth trodden in from the unpaved ground at the
// rim (COLOR.r), the kennel down the middle of a street, damp and dark with standing
// water (COLOR.g), patches of mud, wisps of straw dropped from the carts, and puddles
// in the hollows. All of it follows world position, so no two squares are alike.
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.07) * 0.3 + vnoise(p * 4.3) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz;
	float rim = COLOR.r;
	float kennel = COLOR.g;
	vec3 earth = vec3(0.22, 0.17, 0.12) * (0.85 + 0.3 * vnoise(q * 5.0));
	// Earth at the rim, broken up so it reaches in further in places; mud patches inside.
	float n = fbm(q * 0.45);
	float a = smoothstep(0.35, 0.95, rim + (n - 0.5) * 0.7);
	a = max(a, smoothstep(0.62, 0.78, fbm(q * 0.3 + 7.0)) * 0.7);
	// Dirt packed between the stones everywhere: a faint film that never quite goes away.
	a = max(a, 0.12 + 0.1 * vnoise(q * 2.3));
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
	float drift = smoothstep(0.5, 0.7, fbm(q * 0.6 + 3.0));
	float straw = wisp * step(0.55, h * 1.3 * drift + 0.0) * drift;
	col = mix(col, vec3(0.62, 0.5, 0.25) * (0.8 + 0.4 * hash2(cell + 9.0)), straw);
	a = max(a, straw * 0.95);
	// The kennel: wet and dark, with water standing along it; small puddles in the
	// hollows, a damp dark ring round each. The water is near black and glassy, so what
	// it shows is the sky's reflection.
	float wet = kennel * (0.75 + 0.25 * vnoise(q * 1.7));
	float pf = fbm(q * 0.55 + 21.0);
	float pud = smoothstep(0.76, 0.8, pf) + kennel * smoothstep(0.55, 0.65, vnoise(q * 1.3 + 5.0));
	pud = clamp(pud, 0.0, 1.0);
	float damp = max(wet, smoothstep(0.7, 0.76, pf));
	col = mix(col, vec3(0.1, 0.085, 0.07), damp * 0.5);
	a = max(a, damp * 0.45);
	rough = mix(rough, 0.4, damp);
	col = mix(col, vec3(0.05, 0.055, 0.06), pud);
	rough = mix(rough, 0.04, pud);
	a = max(a, pud * 0.75);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.6, pud);
	ALPHA = clamp(a, 0.0, 1.0);
}
