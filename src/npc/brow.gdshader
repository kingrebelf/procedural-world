shader_type spatial;
// Eyebrows (HairStrands brow mesh): fine dark hairs over the skin, blended rather than cut
// out, so they stay soft at every distance: hairs streak along the combing direction
// (CUSTOM1), thin toward the tail (CUSTOM0.w) and fade out toward the brow's outline
// (COLOR.r); further off they average to an even soft tint.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 hair_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);
// How sparse the brow is, 0 full .. 1 barely there.
instance uniform float sparse = 0.42;
// Under a low hat brim (HumanModel.cap_hair), like the hair.
instance uniform float cap_y = 99.0;

varying vec4 rest;
varying vec3 flow;
varying float inner;

void vertex() {
	rest = CUSTOM0;
	flow = CUSTOM1.xyz;
	inner = COLOR.r;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 f = flow / max(length(flow), 1e-4);
	vec3 q = rest.xyz - f * dot(rest.xyz, f) * 0.97;
	vec3 dx = dFdx(rest.xyz);
	vec3 dy = dFdy(rest.xyz);
	float px = max(length(dx - f * dot(dx, f)), length(dy - f * dot(dy, f)));
	// Single hairs only while they are big enough to see.
	float near = 1.0 - smoothstep(0.5, 1.3, px * 1500.0);
	float hairs = mix(0.5, smoothstep(0.35, 0.75, vnoise3(q * 1500.0)), near);
	float tip = rest.w;
	float a = pow(hairs, 0.7) * smoothstep(0.0, 0.5, inner) * (1.0 - 0.6 * smoothstep(0.55, 1.0, tip)) * (1.0 - 0.35 * sparse);
	if (rest.y > cap_y) {
		a = 0.0;
	}
	ALBEDO = hair_col.rgb * (0.6 + 0.45 * hairs);
	ALPHA = clamp(a * 2.3, 0.0, 0.95);
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
}
