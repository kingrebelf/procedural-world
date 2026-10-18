shader_type spatial;
// One tongue of a flame in the round (flame_tongues.gdshader moves them): a soft teardrop
// turned to face you about the way it is going and stretched along it, its edges eaten
// by rising noise so no two look alike. Drawn like the flipbook cards (premultiplied), so
// flame hides what is behind it in proportion to its brightness.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

#include "res://src/world/fire.gdshaderinc"

varying float nature;

void vertex() {
	// The particle's basis carries its width (x) and its stretch along its flight (y).
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 up = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - c;
	vec3 r = cross(up, to_cam);
	float rl = length(r);
	r = rl > 1e-6 ? r / rl : INV_VIEW_MATRIX[0].xyz;
	vec2 corner = vec2(UV.x - 0.5, 0.5 - UV.y);
	VERTEX = c + r * corner.x * w * 2.0 + up * corner.y * 2.0;
	NORMAL = normalize(to_cam);
	nature = INSTANCE_CUSTOM.x;
}

void fragment() {
	// x across, y along its flight, both -0.5..0.5: rounded below, drawn to a point above.
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y);
	float wide = 0.5 * (0.62 - 0.55 * p.y);
	float d = length(vec2(p.x / max(wide, 1e-3), (p.y + 0.08) / 0.58));
	float shape = 1.0 - smoothstep(0.25, 1.0, d);
	// Eaten at the edges and streaked inside by noise rising through it, two scales.
	vec2 np = vec2(p.x * 4.5 + nature * 17.0, p.y * 3.0 - fire_time * 3.4 + nature * 5.0);
	float n = 0.65 * fx_noise2(np) + 0.35 * fx_noise2(np * 2.3 + 9.0);
	shape = clamp(shape * shape * (0.3 + 1.3 * n) - 0.1, 0.0, 1.0);
	vec3 col = COLOR.rgb * COLOR.a * shape;
	ALBEDO = col;
	ALPHA = clamp(max(col.r, max(col.g, col.b)) * 0.9, 0.0, 1.0);
}
