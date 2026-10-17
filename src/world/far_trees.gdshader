shader_type spatial;
// The distant trees (FarTrees): a fixed grid of quads round you, one per forest cell
// (forest.gdshaderinc). Each quad stands up as a camera-facing billboard where its cell
// holds a tree beyond the streamed chunks and within TREE_BB_TO, and collapses to nothing
// everywhere else. The tree is drawn by the fragment shader: a lumpy round crown on its
// trunk, or a conifer's spire of tiers, in its species' colour, lit as a soft dome that
// lets the light through.
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/world/forest.gdshaderinc"

varying vec2 tuv;
// Crown colour (linear) and form (forest.gdshaderinc: 0 round, 1 conifer, 0.5 bare).
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
	vec4 sp = tree_species(at, c);
	float conifer = step(0.75, sp.a);
	float h = (6.5 + 7.0 * hash12(c + 9.7)) * mix(1.0, 1.2, conifer);
	float w = mix(t.z * TREE_CELL * 2.6, h * 0.42, conifer);
	vec2 to = normalize(CAMERA_POSITION_WORLD.xz - at + vec2(0.0001));
	b_right = vec3(-to.y, 0.0, to.x);
	b_toward = vec3(to.x, 0.0, to.y);
	VERTEX = stands ? base + b_right * (UV.x - 0.5) * w + vec3(0.0, UV.y * h, 0.0) : vec3(at.x, -10000.0, at.y);
	NORMAL = b_toward;
	look = vec4(pow(sp.rgb, vec3(2.2)), sp.a);
	seed = hash12(c + 3.1);
	wp = VERTEX;
}

void fragment() {
	vec2 q = tuv;
	float n = vnoise(q * vec2(6.0, 8.0) + seed * 91.0);
	float crown;
	vec3 cn; // the crown's own normal there (billboard space: across, up, toward you)
	bool bare = abs(look.a - 0.5) < 0.25;
	if (look.a > 0.75) {
		// A conifer: a narrow spire of drooping tiers on a short trunk.
		float y = clamp((q.y - 0.08) / 0.92, 0.0, 1.0);
		float tier = fract(y * 7.0 + seed * 3.0);
		float hw = 0.5 * (1.0 - y) * (0.72 + 0.28 * tier) * (0.85 + 0.3 * n);
		crown = step(abs(q.x - 0.5), hw) * step(0.08, q.y);
		float sx = (q.x - 0.5) / max(hw, 0.05);
		// Each tier's needles droop: lit on top, shaded underneath.
		cn = vec3(sx * 0.75, 0.55 + 0.5 * (1.0 - tier), sqrt(max(1.0 - sx * sx, 0.0)) * 0.6);
	} else {
		// A broadleaf: a lumpy round crown (a few lobes round its rim) on its trunk.
		vec2 e = (q - vec2(0.5, 0.62)) / vec2(0.5, 0.38);
		float a = atan(e.y, e.x);
		float rim = 0.8 + 0.09 * sin(a * 3.0 + seed * 6.3) + 0.06 * sin(a * 5.0 + seed * 17.0) + 0.16 * (n - 0.5);
		crown = step(length(e), rim);
		vec2 s = e / rim;
		cn = vec3(s.x, s.y, sqrt(max(1.0 - dot(s, s), 0.0)));
		// A dead tree: only a tangle of bare limbs where its crown was.
		if (bare) {
			crown *= step(0.66, vnoise(q * vec2(16.0, 20.0) + seed * 41.0));
		}
	}
	float trunk = step(abs(q.x - 0.5), 0.035 * (bare ? 1.0 - q.y * 0.6 : 1.0)) * step(q.y, bare ? 0.85 : 0.45);
	if (crown < 0.5 && trunk < 0.5) {
		discard;
	}
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 nw = b_toward;
	vec3 alb = vec3(0.07, 0.05, 0.035);
	vec3 back = vec3(0.0);
	if (crown > 0.5 && bare) {
		alb = look.rgb * 0.6;
	} else if (crown > 0.5) {
		// Lit as a soft dome, bent toward the sky as the near trees' crowns are; clumps of
		// leaves catch the light, with shade between them.
		nw = normalize(mix(normalize(b_right * cn.x + up * cn.y + b_toward * cn.z), up, 0.25));
		float clump = vnoise(q * vec2(10.0, 13.0) + seed * 37.0);
		alb = look.rgb * (0.72 + 0.5 * clump) * (0.85 + 0.3 * seed);
		// Leaves let the light through: a crown against the sun glows its own colour.
		back = look.rgb / max(max(look.r, look.g), 0.001) * 0.55;
	}
	ALBEDO = alb * (1.0 - 0.42 * cloud_shadow(wp));
	BACKLIGHT = back;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
