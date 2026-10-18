shader_type spatial;
// Churned white water where a waterfall lands (WaterfallFx): a plane on the plunge pool,
// UV.y running out from the cliff. Boils of foam well up along the line where the sheet
// hits and spread out downstream and to the sides, thinning to scattered lace, carried on
// the outflow. Fades where the water under it is shallow, so it never lies on the bank.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

instance uniform vec2 size = vec2(10.0, 20.0);
instance uniform float foot = 2.0; // metres out from the plane's back edge the sheet lands
instance uniform float power = 1.0; // a high fall churns harder and further

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u; v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}
float h1(vec2 p) { return float(pcg2d(uvec2(ivec2(floor(p)) + 32768)).x) * (1.0 / 4294967296.0); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1, 0)), f.x), mix(h1(i + vec2(0, 1)), h1(i + vec2(1, 1)), f.x), f.y);
}
float lace(vec2 p) {
	float a = vn(p * 1.7);
	float b = vn(p * 4.1 + 11.0);
	return clamp(1.0 - abs(a * 2.0 - 1.0 + (b - 0.5) * 0.8) * 2.6, 0.0, 1.0);
}

void vertex() {
	// Boils heave the surface a little near the foot.
	vec2 m = (UV - 0.5) * size;
	float out_ = UV.y * size.y - foot;
	float boil = vn(vec2(m.x * 0.6, out_ * 0.6 - TIME * 1.4));
	VERTEX.y += (boil - 0.5) * 0.25 * power * exp(-max(out_, 0.0) / 3.0);
}

void fragment() {
	vec2 m = (UV - 0.5) * size; // metres: x across, y out from the cliff
	float out_ = UV.y * size.y - foot;
	// Behind the sheet it is a dark, churning gap; it spreads out away from the foot.
	float near = exp(-abs(out_) / (2.5 + power * 3.0));
	float spread = exp(-max(out_, 0.0) / (5.0 + power * 6.0));
	float side = 1.0 - smoothstep(size.x * 0.32, size.x * 0.5, abs(m.x));
	// Carried outward over time, in two phases that cross-fade so it never resets.
	float t0 = fract(TIME * 0.25);
	float t1 = fract(TIME * 0.25 + 0.5);
	float w = abs(t0 - 0.5) * 2.0;
	vec2 q0 = vec2(m.x, out_ - t0 * 4.0);
	vec2 q1 = vec2(m.x + 7.3, out_ - t1 * 4.0);
	float l = mix(lace(q0), lace(q1), w);
	float boils = mix(vn(q0 * 0.45), vn(q1 * 0.45), w);
	float foam = clamp(near * (0.65 + boils * 0.5) + spread * l * 0.8, 0.0, 1.0) * side;
	// Only on water deep enough: not on the bank or on the rocks round the pool.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float under = clamp(-world.z - (-VERTEX.z), 0.0, 50.0);
	foam *= smoothstep(0.05, 0.4, under);
	ALBEDO = vec3(0.86, 0.89, 0.9) * (0.85 + boils * 0.2);
	ROUGHNESS = 0.6;
	SPECULAR = 0.4;
	ALPHA = foam * 0.9;
}
