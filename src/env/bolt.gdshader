shader_type spatial;
// A lightning bolt (Lightning.bolt_mesh): ribbons turned to face the camera, a white-hot
// core in a violet-blue glow, never thinner than a couple of pixels so a strike miles off
// still reads. Haze dims it with distance, but less than the fog would: a bolt shows
// through rain that hides the hills.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float energy = 1.0; // the stroke's pulse (Weather)

varying float bright;
varying float dist;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to = VERTEX - cam;
	dist = length(to);
	float pix = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec3 side = normalize(cross(NORMAL, to / max(dist, 0.001)));
	float w = max(UV2.x, dist * pix * 2.5 * (0.5 + 0.5 * COLOR.a));
	bright = COLOR.a;
	VERTEX = (VIEW_MATRIX * vec4(VERTEX + side * UV.x * w, 1.0)).xyz;
}

void fragment() {
	float x = abs(UV.x);
	float core = pow(1.0 - x, 3.0);
	float halo = (1.0 - x) * 0.35;
	vec3 col = vec3(1.0, 0.98, 1.0) * core * 6.0 + vec3(0.55, 0.6, 1.0) * halo * 2.0;
	ALBEDO = col * bright * energy * exp(-dist * 0.0005);
}
