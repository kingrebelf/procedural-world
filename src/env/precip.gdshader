shader_type spatial;
// How a raindrop, snowflake or speck of dust is drawn (Weather, precip_particles.gdshader).
// Rain: a thin streak along its fall, as the eye sees a drop in motion. Snow and dust: a
// soft round fleck facing you. Far off a drop would be thinner than a pixel and shimmer, so
// it never gets thinner than one; it gets fainter instead, which keeps the rain's look the
// same at every resolution and distance.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float streak = 0.5; // metres; 0 draws round flecks
uniform float thick = 0.006; // metres across
uniform vec3 tint : source_color = vec3(0.6);
uniform float opacity = 0.2;
uniform float reach = 24.0; // the box's half width: fade out before the wrap

varying float fade;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to = c - cam;
	float d = max(length(to), 0.001);
	float seed = INSTANCE_CUSTOM.x;
	// Radians per pixel, so a fleck is never thinner than about a pixel.
	float pix = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec3 world;
	if (streak > 0.0) {
		vec3 ax = normalize(fall_dir);
		vec3 side = normalize(cross(ax, to / d));
		float w = max(thick, d * pix * 1.2);
		// (Square root: a lit drop still catches the eye when it is thinner than a pixel.)
		fade = sqrt(thick / w);
		float len = streak * (0.75 + 0.5 * seed);
		world = c + side * VERTEX.x * w + ax * VERTEX.y * len;
	} else {
		float s = thick * (0.6 + 0.8 * seed);
		float w = max(s, d * pix * 1.5);
		fade = (s / w) * (s / w);
		world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * w;
	}
	// Not right in your face, and gone softly before the far side of the box.
	fade *= smoothstep(0.3, 1.2, d) * (1.0 - smoothstep(reach * 0.7, reach * 0.98, length(to.xz)));
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	if (INSTANCE_CUSTOM.z < 0.5) {
		VERTEX = vec3(0.0, 0.0, 1.0); // behind the camera: dropped
	}
}

void fragment() {
	float a;
	if (streak > 0.0) {
		float across = 1.0 - abs(UV.x * 2.0 - 1.0);
		a = across * smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.75, UV.y);
	} else {
		float r = length(UV * 2.0 - 1.0);
		a = smoothstep(1.0, 0.15, r);
	}
	ALBEDO = tint;
	ALPHA = clamp(a * opacity * fade, 0.0, 1.0);
}
