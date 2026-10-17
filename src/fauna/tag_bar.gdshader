shader_type spatial;
// An animal's health bar under its name: faces you and keeps its size on screen like the
// name above it, so the two never slide into each other with distance.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

instance uniform float fill = 1.0;
uniform vec4 back_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform vec4 fill_color : source_color = vec4(0.9, 0.2, 0.15, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sc = -MODELVIEW_MATRIX[3].z;
	MODELVIEW_MATRIX[0] *= sc;
	MODELVIEW_MATRIX[1] *= sc;
	MODELVIEW_MATRIX[2] *= sc;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = UV.x <= fill ? fill_color : back_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
