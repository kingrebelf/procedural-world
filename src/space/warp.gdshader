shader_type canvas_item;
// Warp: star streaks rushing past from the centre of the screen, ending in a white flash.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.78;
	float a = atan(uv.y, uv.x);
	float r = length(uv);
	float lane = floor(a * 160.0);
	float h = fract(sin(lane * 91.7) * 43758.5);
	float pos = fract(h * 7.0 - time_s * (0.6 + h * 1.4));
	float len = 0.05 + amount * 0.5;
	float streak = step(0.75, h) * smoothstep(pos - len, pos, r) * step(r, pos) * smoothstep(0.03, 0.25, r);
	float flash = smoothstep(0.8, 1.0, amount);
	vec3 c = vec3(0.7, 0.85, 1.0) * streak * amount * 1.5;
	COLOR = vec4(c + vec3(flash), clamp(streak * amount + flash, 0.0, 1.0));
}
