shader_type spatial;
// Rivers: a ribbon of water at the river's level, flowing downhill (vertex COLOR.rg is
// the flow direction, COLOR.a fades the edges). Ripples are advected along the flow in
// two phases that cross-fade, so the current never stretches or resets visibly.
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec3 sun_dir_g;
uniform vec3 shallow : source_color = vec3(0.2, 0.4, 0.4);
uniform vec3 deep : source_color = vec3(0.03, 0.1, 0.12);
uniform vec3 glow : source_color = vec3(0.1, 0.9, 0.8);
uniform float glow_amount = 0.0;
uniform float speed = 1.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;
varying vec2 flow;
varying float edge;

vec2 h2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(h2(i) - 0.5, f), dot(h2(i + vec2(1, 0)) - 0.5, f - vec2(1, 0)), u.x),
		mix(dot(h2(i + vec2(0, 1)) - 0.5, f - vec2(0, 1)), dot(h2(i + vec2(1, 1)) - 0.5, f - vec2(1, 1)), u.x), u.y);
}
float rip(vec2 p) { return n2(p * 0.6) * 0.55 + n2(p * 1.9) * 0.3 + n2(p * 5.1) * 0.15; }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = COLOR.rg * 2.0 - 1.0;
	edge = COLOR.a;
}

void fragment() {
	float t = TIME * speed * 0.25;
	float p0 = fract(t);
	float p1 = fract(t + 0.5);
	float w = abs(p0 - 0.5) * 2.0;
	vec2 off0 = -flow * p0 * 4.0;
	vec2 off1 = -flow * p1 * 4.0;
	float e = 0.08;
	vec2 q0 = wpos.xz + off0;
	vec2 q1 = wpos.xz + off1 + vec2(13.7, 5.1);
	float h0 = rip(q0);
	float h1 = rip(q1);
	vec2 g0 = vec2(rip(q0 + vec2(e, 0)) - h0, rip(q0 + vec2(0, e)) - h0) / e;
	vec2 g1 = vec2(rip(q1 + vec2(e, 0)) - h1, rip(q1 + vec2(0, e)) - h1) / e;
	vec2 g = mix(g0, g1, w) * (0.35 + length(flow) * 0.5);
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z - (-VERTEX.z)), 0.0, 50.0);
	float k = 1.0 - exp(-water_depth / 2.5);
	vec3 under = textureLod(screen_tex, SCREEN_UV + nw.xz * 0.015 * k, 1.0).rgb;
	// Sun caustics dancing on the riverbed, carried downstream.
	vec2 cq = (wpos.xz + off0 * 0.5) * 0.5;
	float c1 = abs(n2(cq + n2(cq * 0.7 + TIME * 0.2) * 1.5) * 2.0);
	float caus = pow(clamp(1.0 - c1 * 2.0, 0.0, 1.0), 4.0);
	under *= 1.0 + caus * (1.0 - k) * 1.2 * smoothstep(-0.05, 0.3, sun_dir_g.y);
	// As in the lakes: the riverbed is already lit, so it is seen through (emission), with
	// red and then green swallowed by depth; the water's own colour shows where it is deep.
	vec3 trans = exp(-vec3(0.4, 0.14, 0.17) * water_depth * 1.5);
	vec3 tint = mix(vec3(1.0), shallow / max(max(shallow.r, shallow.g), max(shallow.b, 0.01)), 0.3);
	vec3 seen = under * trans * tint;
	vec3 col = deep * (1.0 - trans.g) * 1.6;
	// Foam streaks where the current runs fast, and a thin line at the banks.
	float streak = smoothstep(0.18, 0.4, mix(h0, h1, w)) * length(flow) * 0.35;
	float bank = 1.0 - smoothstep(0.0, 0.15, water_depth);
	float foam = clamp(streak + bank * 0.4, 0.0, 0.8);
	col = mix(col, vec3(0.8, 0.84, 0.86), foam);
	vec3 vdir = normalize((inverse(VIEW_MATRIX) * vec4(VIEW, 0.0)).xyz); // back toward the eye
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, vdir), 0.0, 1.0), 5.0);
	seen *= (1.0 - foam) * (1.0 - fres);
	ALBEDO = col;
	ALPHA = edge * smoothstep(0.0, 0.25, water_depth);
	ROUGHNESS = 0.06;
	SPECULAR = 0.5;
	EMISSION = seen + glow * glow_amount * 0.4;
}
