shader_type spatial;
// Overlay for ranked gear: a rim of light in the ability's colour with slow bands of
// energy running up the item. Stronger for higher ranks.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 aura : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float strength = 0.5;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bands = 0.5 + 0.5 * sin(wp.y * 22.0 - TIME * 3.0 + sin(wp.x * 9.0 + TIME) * 1.5);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2);
	ALBEDO = aura.rgb * (rim * 1.4 + bands * bands * 0.35) * strength * pulse;
}
