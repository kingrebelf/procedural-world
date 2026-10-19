shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The barrier at a finite world's edge (EdgeField): a faint lattice of light that shows
// only round where you stand against it and fades out a few metres away.
uniform vec3 near_pos;
uniform float reach = 18.0;
uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fade = 1.0 - smoothstep(reach * 0.25, reach, distance(wpos, near_pos));
	// Three sets of lines 60 degrees apart, fixed to the world (one of x and z is the
	// same all along a wall), so the lattice stays put as the panel follows you.
	vec2 p = vec2(wpos.x + wpos.z, wpos.y) / 2.5;
	float l = 0.0;
	for (int i = 0; i < 3; i++) {
		float a = float(i) * 2.0944;
		float v = dot(p, vec2(cos(a), sin(a)));
		l = max(l, smoothstep(0.88, 1.0, abs(fract(v) - 0.5) * 2.0));
	}
	float shimmer = 0.75 + 0.25 * sin(TIME * 2.0 + p.y * 0.7);
	ALBEDO = tint.rgb * (0.08 + 0.92 * l) * fade * shimmer * 0.6;
}
