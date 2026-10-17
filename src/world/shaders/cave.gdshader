shader_type spatial;
// Cave walls: photo rock projected three ways in world space, wet mud on the floors,
// darkened in hollows by the vertex colour. Drawn from both sides so the rocky lip
// around a mouth reads from outside too.
render_mode cull_disabled;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.22;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * scale;
	vec3 rock = tri(rock_tex, p, w) * vec3(0.78, 0.74, 0.70);
	// Bands of darker stone through the walls.
	float strata = 0.85 + 0.15 * sin(wpos.y * 1.7 + sin(wpos.x * 0.21) * 2.0 + cos(wpos.z * 0.17) * 2.0);
	rock *= strata;
	float floor_w = smoothstep(0.55, 0.85, n.y);
	vec3 mud = texture(floor_tex, wpos.xz * 0.3).rgb * 0.7;
	vec3 col = mix(rock, mud, floor_w);
	ALBEDO = col * COLOR.r;
	AO = COLOR.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = mix(0.82, 0.45, floor_w);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
