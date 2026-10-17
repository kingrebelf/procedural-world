shader_type spatial;
// Light shafts (crepuscular rays): a full-screen pass that marches from each pixel toward
// the sun on screen, gathering the open sky it passes. Where leaves, trunks, walls or
// peaks cut the sky up near the sun, the light streams out between them in rays.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

global uniform vec3 sun_dir_g;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float strength = 0.0; // set each frame (0 at night, under cloud, under ground)
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.75);
const int STEPS = 48;

void vertex() {
	// A 2x2 quad covering the screen, whatever the camera does.
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	vec4 sp = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(sun_dir_g, 0.0));
	if (strength <= 0.0 || sp.w <= 0.0) {
		discard;
	}
	vec2 sun_uv = sp.xy / sp.w * 0.5 + 0.5;
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 uv = SCREEN_UV;
	// March at most most of a screen toward the sun; far pixels get only the rays' tails.
	vec2 delta = (sun_uv - uv) / float(STEPS);
	float len = length(delta * aspect);
	if (len > 0.02) {
		delta *= 0.02 / len;
	}
	// Per-pixel offset breaks up the banding of the fixed steps (TAA smooths the rest).
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec2 s = uv + delta * jitter;
	float decay = 1.0;
	float acc = 0.0;
	for (int i = 0; i < STEPS; i++) {
		s += delta;
		if (s.x < 0.0 || s.y < 0.0 || s.x > 1.0 || s.y > 1.0) {
			break;
		}
		// Reverse-Z: the sky (nothing drawn) sits at depth 0.
		float sky = 1.0 - step(1e-6, texture(depth_tex, s).r);
		// Sky near the sun shines hardest.
		float near = exp(-length((s - sun_uv) * aspect) * 5.0);
		acc += sky * near * decay;
		decay *= 0.965;
	}
	acc /= float(STEPS);
	// Rays fade with distance from the sun on screen, and over open sky they are only a
	// faint halo: they show in the air in front of trees, walls and hills.
	float fall = 1.0 - smoothstep(0.2, 1.1, length((uv - sun_uv) * aspect));
	float sky_here = 1.0 - step(1e-6, texture(depth_tex, uv).r);
	ALBEDO = tint * acc * strength * fall * mix(1.0, 0.3, sky_here);
}
