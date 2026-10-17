shader_type spatial;
// The bed of embers under a big fire (FireFx.flame): charred wood and ash with coals
// glowing through the cracks, each patch breathing brighter and dimmer on its own, and the
// whole bed swelling with the fire's life (fire.gdshaderinc), as its light does.
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

#include "res://src/world/fire.gdshaderinc"

instance uniform float seed = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float life = fire_life(fire_time, seed);
	vec2 q = UV * 9.0 + seed * 40.0;
	// Lumps of coal and the cracks between them.
	float lump = fx_noise2(q) * 0.65 + fx_noise2(q * 2.3 + 5.0) * 0.35;
	float crack = smoothstep(0.42, 0.62, lump);
	// Each patch glows in its own slow breath.
	float breath = 0.55 + 0.45 * fx_noise2(UV * 4.0 + vec2(fire_time * 0.35, seed * 17.0 + fire_time * 0.21));
	float hot = (1.0 - crack) * breath * (0.75 + 0.5 * life) * smoothstep(1.0, 0.35, r);
	// Grey ash crusts the cooler outside.
	float ash = smoothstep(0.55, 0.95, r) * (0.6 + 0.4 * fx_noise2(q * 1.7));
	ALBEDO = mix(vec3(0.035, 0.03, 0.028), vec3(0.33, 0.31, 0.29), ash);
	ROUGHNESS = 1.0;
	EMISSION = mix(vec3(0.8, 0.12, 0.02), vec3(1.0, 0.45, 0.1), hot * hot) * hot * 3.2;
	ALPHA = smoothstep(1.0, 0.8, r);
}
