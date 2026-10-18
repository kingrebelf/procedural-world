shader_type spatial;
// ShelterMap's picture: over the whole view of its downward orthographic camera, how
// high the nearest surface below it stands, as a fraction of `range` metres up from the
// far plane (0 where nothing was hit). Any other camera never draws it.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float cam_size = 192.0;
uniform float range = 256.0;

void vertex() {
	bool mine = PROJECTION_MATRIX[3][3] > 0.5 && abs(PROJECTION_MATRIX[0][0] - 2.0 / cam_size) < 1e-4;
	// The quad becomes the whole screen for that camera, and falls outside every other.
	POSITION = mine ? vec4(UV * 2.0 - 1.0, 0.5, 1.0) : vec4(4.0, 4.0, 4.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float dist = -v.z / v.w;
	ALBEDO = vec3(clamp(1.0 - dist / range, 0.0, 1.0));
	ALPHA = 1.0;
}
