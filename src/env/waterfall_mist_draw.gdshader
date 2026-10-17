shader_type spatial;
// A soft puff of waterfall mist (WaterfallFx): a camera-facing quad, round and ragged,
// fading where it meets the ground or the water so it never shows a hard edge. Lit, so
// at night it is as dark as the night (nothing on a human world glows).
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

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

varying float seed;

void vertex() {
	// Face the camera, keeping the particle's size.
	float sz = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sz, INV_VIEW_MATRIX[1] * sz, INV_VIEW_MATRIX[2] * sz, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291 + float(INSTANCE_ID) * 0.618);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float n = vn(UV * 4.0 + seed * 40.0) * 0.6 + vn(UV * 9.0 + seed * 70.0) * 0.4;
	float a = (1.0 - smoothstep(0.35, 1.0, r + (n - 0.5) * 0.5)) * COLOR.a;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	a *= smoothstep(0.0, 1.5, -world.z - (-VERTEX.z));
	ALBEDO = vec3(0.9, 0.92, 0.94) * COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
