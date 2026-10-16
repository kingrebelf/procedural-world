shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
// The thin glowing edge of a planet's atmosphere, on a sphere slightly larger than it.

uniform vec3 air : source_color = vec3(0.45, 0.65, 1.0);
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.7);

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = clamp(dot(wn, normalize(sun_dir)) + 0.35, 0.0, 1.0);
	ALBEDO = air * pow(rim, 3.0) * 1.8 * lit;
}
