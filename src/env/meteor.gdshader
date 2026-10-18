shader_type spatial;
// A falling star (Starfall): a short streak burning across the night sky, brightest at its
// head and fading along the train behind it. A quad turned to face the camera, stretched
// from `tail` to `head`, never thinner than a pixel or two so it reads at any resolution.
// The big one that comes down near you is the same streak, wider and hotter.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform vec3 head = vec3(0.0, 100.0, 0.0);
uniform vec3 tail = vec3(0.0, 110.0, 0.0);
uniform float width = 0.0; // metres; 0 keeps it at the pixel floor
uniform float px = 1.6; // the pixel floor
uniform float pix = 0.004; // radians per pixel (Starfall sets it from the camera)
uniform float energy = 1.0;
uniform vec3 tint : source_color = vec3(0.92, 0.96, 1.0);

varying float along;

void vertex() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 world = mix(tail, head, UV.y);
	vec3 to = world - cam;
	float d = max(length(to), 0.001);
	vec3 ax = head - tail;
	vec3 side = normalize(cross(length(ax) > 0.001 ? ax : vec3(0.0, 1.0, 0.0), to / d));
	// Thicker at the head, tapering to a thread at the end of the train.
	float w = max(width, d * pix * px) * mix(0.35, 1.0, UV.y);
	along = UV.y;
	VERTEX = (VIEW_MATRIX * vec4(world + side * (UV.x - 0.5) * w, 1.0)).xyz;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float core = pow(1.0 - x, 2.0);
	// A white-hot head, the train behind it cooling to a faint greenish yellow.
	float train = along * along;
	vec3 col = mix(vec3(0.75, 0.95, 0.7), tint, smoothstep(0.6, 1.0, along));
	ALBEDO = col * core * train * energy * (1.0 + 3.0 * smoothstep(0.92, 1.0, along));
}
