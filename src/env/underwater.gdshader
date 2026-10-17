shader_type canvas_item;
// Looking out from under water: the view wobbles and softens, light falls off the deeper
// you go, a shimmer of sunlight plays near the surface, and the edges darken.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float depth = 0.0; // metres the eye is below the surface
uniform float daylight = 1.0;
uniform vec3 tint : source_color = vec3(0.35, 0.7, 0.75);

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	vec2 wob = vec2(sin(uv.y * 23.0 + t * 1.7) + sin(uv.y * 41.0 - t * 2.3) * 0.5,
		cos(uv.x * 19.0 + t * 1.3) + cos(uv.x * 37.0 + t * 2.1) * 0.5) * 0.0028;
	vec3 c = textureLod(screen_tex, uv + wob, 1.5).rgb;
	float d = clamp(depth / 30.0, 0.0, 1.0);
	// Water swallows red first, then green: deeper is bluer and darker.
	vec3 absorb = mix(vec3(1.0), tint, 0.55 + 0.45 * d);
	c *= absorb * mix(1.15, 0.32, sqrt(d));
	// Sun shimmer: soft moving light bands, strongest just under the surface and looking up.
	float shim = vn(uv * vec2(9.0, 5.0) + vec2(t * 0.25, t * 0.4)) * vn(uv * vec2(6.0, 11.0) - vec2(t * 0.3, t * 0.15));
	c += tint * smoothstep(0.25, 0.6, shim) * 0.12 * (1.0 - d) * (1.0 - uv.y) * daylight;
	float vig = smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(1.4, 1.1)));
	c *= mix(0.55, 1.0, vig);
	COLOR = vec4(c, 1.0);
}
