shader_type spatial;
// The distant trees (FarTrees): a fixed grid of quads round you, one per forest cell
// (forest.gdshaderinc). Each quad stands up as a camera-facing billboard where its cell
// holds a tree beyond the streamed chunks and within TREE_BB_TO, and collapses to nothing
// everywhere else. The tree is drawn by the fragment shader: a ragged round crown on its
// trunk, or a conifer's spire of tiers, lit as a rough dome.
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/world/forest.gdshaderinc"

varying vec2 tuv;
// Crown colour (linear) and 1 for a conifer.
varying vec4 look;
varying vec3 b_right;
varying vec3 b_toward;
varying float seed;
varying vec3 wp;

void vertex() {
	// Each quad's corners sit on its cell's corner (world x/z), UV the corner of the quad
	// (y up).
	tuv = UV;
	vec2 c = floor(VERTEX.xz / TREE_CELL + 0.5);
	vec3 t = tree_of(c);
	vec2 at = t.xy;
	vec2 fuv = forest_uv(at);
	vec4 fd = textureLod(forest_tex, fuv, 0.0);
	vec2 hc = textureLod(forest_hgt, fuv, 0.0).rg;
	vec3 base = vec3(at.x, hc.x - 0.4, at.y);
	float dist = length(base - CAMERA_POSITION_WORLD);
	bool stands = in_forest_rect(fuv) && hash12(c) < tree_density(fd.a, at) && dist < TREE_BB_TO
		&& billboarded(c, dist) && !near_drawn(at);
	float conifer = step(hash12(c + 31.7), hc.y);
	float h = (6.5 + 7.0 * hash12(c + 9.7)) * mix(1.0, 1.2, conifer);
	float w = mix(t.z * TREE_CELL * 2.6, h * 0.42, conifer);
	vec2 to = normalize(CAMERA_POSITION_WORLD.xz - at + vec2(0.0001));
	b_right = vec3(-to.y, 0.0, to.x);
	b_toward = vec3(to.x, 0.0, to.y);
	VERTEX = stands ? base + b_right * (UV.x - 0.5) * w + vec3(0.0, UV.y * h, 0.0) : vec3(at.x, -10000.0, at.y);
	NORMAL = b_toward;
	look = vec4(pow(fd.rgb, vec3(2.2)), conifer);
	seed = hash12(c + 3.1);
	wp = VERTEX;
}

void fragment() {
	vec2 q = tuv;
	float n = vnoise(q * vec2(6.0, 8.0) + seed * 91.0);
	float crown;
	vec2 sp; // where on the crown, about -1..1 across and up
	if (look.a > 0.5) {
		// A conifer: a narrow spire of drooping tiers on a short trunk.
		float y = clamp((q.y - 0.08) / 0.92, 0.0, 1.0);
		float tier = fract(y * 7.0 + seed * 3.0);
		float hw = 0.5 * (1.0 - y) * (0.72 + 0.28 * tier) * (0.85 + 0.3 * n);
		crown = step(abs(q.x - 0.5), hw) * step(0.08, q.y);
		sp = vec2((q.x - 0.5) / max(hw, 0.05), y * 2.0 - 1.0);
	} else {
		// A broadleaf: a round crown with a ragged edge, on its trunk.
		vec2 e = (q - vec2(0.5, 0.62)) / vec2(0.5, 0.38);
		crown = step(length(e), 0.8 + 0.22 * n);
		sp = e;
	}
	float trunk = step(abs(q.x - 0.5), 0.035) * step(q.y, 0.45);
	if (crown < 0.5 && trunk < 0.5) {
		discard;
	}
	vec3 nw = b_toward;
	vec3 alb = vec3(0.07, 0.05, 0.035);
	if (crown > 0.5) {
		// Lit as a rough dome: its sunward side bright, its underside dark.
		nw = normalize(b_right * sp.x * 0.9 + vec3(0.0, 1.0, 0.0) * (sp.y * 0.8 + 0.25) + b_toward * 0.7);
		alb = look.rgb * (0.7 + 0.45 * n) * (0.85 + 0.3 * seed) * mix(1.0, 0.8, look.a);
	}
	ALBEDO = alb * (1.0 - 0.42 * cloud_shadow(wp));
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
