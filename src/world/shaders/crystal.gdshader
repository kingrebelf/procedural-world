shader_type spatial;
// Crystal: glassy, faceted, with a light caught inside. Opaque (so it casts shadows and
// batches), faking depth with a glow that is brightest through the core and fades at
// grazing angles, drifting bands of colour, and a strong fresnel sheen on each facet.
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night_glow_g;
uniform vec3 tint : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 core : source_color = vec3(0.6, 1.0, 1.0);
uniform float glow = 1.0;
uniform float clarity = 0.8;

varying vec3 opos;

float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	// Inner structure seen "through" the surface: parallax-shifted noise bands.
	vec3 q = opos * 2.2 + VIEW * 0.6;
	float inner = n3(q) * 0.6 + n3(q * 2.7 + 3.0) * 0.4;
	float bands = 0.5 + 0.5 * sin(opos.y * 7.0 + inner * 5.0);
	float depth = ndv * clarity;
	vec3 body = mix(tint * 0.18, tint * 0.55, bands * depth);
	ALBEDO = body * COLOR.rgb;
	ROUGHNESS = 0.06 + 0.1 * inner;
	SPECULAR = 0.9;
	METALLIC = 0.1;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.05;
	float night = clamp(night_glow_g, 0.0, 1.5);
	vec3 light = mix(tint, core, inner * depth);
	EMISSION = light * glow * (0.12 + 0.6 * depth * (0.4 + 0.6 * bands)) * (0.35 + 0.65 * night) * COLOR.rgb + tint * fres * 0.25;
	RIM = 0.4;
	RIM_TINT = 0.6;
}
