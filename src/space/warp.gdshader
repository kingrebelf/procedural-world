shader_type canvas_item;
// Warp: the stars stretch into streaks that rush past on every side, from a point dead
// ahead out past the edges of the view, longer and brighter the faster you go; a blue
// tunnel of light closes round you, and it ends in a white flash.
render_mode blend_premul_alpha;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

float hash11(float n) {
	return fract(sin(n * 91.7 + 3.1) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One layer of streaks: `lanes` directions round the view, a star in about half of them
// flying outward. Returns brightness.
float streaks(float a, float r, float lanes, float seed, float speed, float len, float px) {
	float u = a / 6.2831853 * lanes + seed;
	float lane = floor(u);
	float h = hash11(lane + seed * 13.0);
	if (h < 0.45) {
		return 0.0;
	}
	// Where along its lane the star is: it starts near the centre and speeds up as it
	// comes past, as a star would that you were rushing toward.
	float t = fract(hash11(lane * 1.7 + seed) + time_s * speed * (0.5 + h));
	float head = t * t * 1.9 + 0.02;
	float tail = head * (1.0 - len);
	float along = smoothstep(tail, head, r) * (1.0 - smoothstep(head, head + px * 2.0, r));
	// A line a pixel or two wide, wherever it is on the screen.
	float off = abs(fract(u) - 0.5) * 6.2831853 / lanes * r;
	float w = px * (0.8 + 1.6 * head);
	float across = 1.0 - smoothstep(w * 0.5, w, off);
	return along * across * (0.35 + 0.65 * smoothstep(0.0, 0.8, head)) * (0.6 + 0.4 * h);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 1e-6);
	float a = atan(uv.y, uv.x) + 3.14159265;
	float r = length(uv);
	float px = SCREEN_PIXEL_SIZE.y;
	float go = smoothstep(0.0, 0.85, amount);
	float len = 0.08 + go * 0.75;
	float s = streaks(a, r, 140.0, 0.0, 0.5, len, px)
		+ streaks(a, r, 230.0, 0.37, 0.65, len, px)
		+ streaks(a, r, 370.0, 0.71, 0.8, len * 0.8, px) * 0.7;
	s *= smoothstep(0.02, 0.12, r) * go;
	// The tunnel: blue light streaming past, in bands that run outward along the view.
	float lr = log(r + 0.02);
	float tun = vnoise(vec2(a * 5.0, lr * 3.0 - time_s * 6.0)) * vnoise(vec2(a * 11.0 + 7.0, lr * 6.0 - time_s * 9.0));
	float wall = smoothstep(0.15, 0.85, amount) * smoothstep(0.08, 0.5, r);
	vec3 tunnel = mix(vec3(0.15, 0.3, 0.9), vec3(0.55, 0.8, 1.0), tun) * tun * wall * 0.9;
	// Dead ahead, the point you are falling toward glows.
	vec3 core = vec3(0.7, 0.85, 1.0) * exp(-r * 14.0) * go * 1.2;
	vec3 c = vec3(0.75, 0.88, 1.0) * s * 1.6 + tunnel + core;
	// The view behind dims as the tunnel closes in, then all goes white. (Premultiplied:
	// the light is added over what is left of the view.)
	float dim = clamp(go * 0.55 + wall * 0.3, 0.0, 0.85);
	float flash = smoothstep(0.82, 1.0, amount);
	COLOR = vec4(mix(c, vec3(1.0), flash), max(dim, flash));
}
