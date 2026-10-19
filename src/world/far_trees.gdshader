shader_type spatial;
// The distant trees (FarTrees): a fixed grid of quads round you, one per forest cell
// (forest.gdshaderinc). Each quad stands up as a camera-facing billboard where its cell
// holds a tree beyond the streamed chunks and within TREE_BB_TO, and collapses to nothing
// everywhere else. The tree is drawn by the fragment shader in its species' form and
// colour (forest.gdshaderinc): a lumpy round crown on its trunk, lit as a soft dome that
// lets the light through, a conifer's spire of tiers, a palm, bare dead limbs, or an alien
// world's mushroom cap, crystal spike or mast.
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"
#include "res://src/world/forest.gdshaderinc"

varying vec2 tuv;
// Crown colour (linear) and form (FORM_* in forest.gdshaderinc).
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
		&& billboarded(c, dist) && hash12(c + 2.7) >= near_share(at);
	vec4 sp = tree_species(at, c);
	int form = tree_form(sp.a);
	float h = 6.5 + 7.0 * hash12(c + 9.7);
	float w = t.z * TREE_CELL * 2.6;
	if (form == FORM_CONIFER) {
		h *= 1.2;
		w = h * 0.42;
	} else if (form == FORM_CAP) {
		h *= 0.75;
		w = h * 0.9;
	} else if (form == FORM_CRYSTAL) {
		w = h * 0.5;
	} else if (form == FORM_PALM) {
		h *= 1.15;
		w = h * 0.7;
	}
	vec2 to = normalize(CAMERA_POSITION_WORLD.xz - at + vec2(0.0001));
	b_right = vec3(-to.y, 0.0, to.x);
	b_toward = vec3(to.x, 0.0, to.y);
	VERTEX = stands ? base + b_right * (UV.x - 0.5) * w + vec3(0.0, UV.y * h, 0.0) : vec3(at.x, -10000.0, at.y);
	NORMAL = b_toward;
	look = vec4(pow(max(sp.rgb, vec3(0.0)), vec3(2.2)), float(form));
	seed = hash12(c + 3.1);
	wp = VERTEX;
}

void fragment() {
	vec2 q = tuv;
	int form = int(look.a + 0.5);
	float n = vnoise(q * vec2(6.0, 8.0) + seed * 91.0);
	float crown = 0.0;
	float trunk = 0.0;
	// The crown's own normal there (billboard space: across, up, toward you).
	vec3 cn = vec3(0.0, 0.0, 1.0);
	vec3 stem = vec3(0.07, 0.05, 0.035);
	float leafy = 1.0;
	float rough = 0.85;
	if (form == FORM_CONIFER) {
		// A narrow spire of drooping tiers on a short trunk.
		float y = clamp((q.y - 0.08) / 0.92, 0.0, 1.0);
		float tier = fract(y * 7.0 + seed * 3.0);
		float hw = 0.5 * (1.0 - y) * (0.72 + 0.28 * tier) * (0.85 + 0.3 * n);
		crown = step(abs(q.x - 0.5), hw) * step(0.08, q.y);
		float sx = (q.x - 0.5) / max(hw, 0.05);
		// Each tier's needles droop: lit on top, shaded underneath.
		cn = vec3(sx * 0.75, 0.55 + 0.5 * (1.0 - tier), sqrt(max(1.0 - sx * sx, 0.0)) * 0.6);
		trunk = step(abs(q.x - 0.5), 0.035) * step(q.y, 0.45);
	} else if (form == FORM_CAP) {
		// A mushroom: a broad domed cap on a pale stalk.
		vec2 e = (q - vec2(0.5, 0.68)) / vec2(0.5, 0.3);
		crown = step(length(e), 0.92 + 0.08 * (n - 0.5)) * step(-0.3, e.y);
		cn = vec3(e.x, max(e.y, 0.0) + 0.3, sqrt(max(1.0 - dot(e, e), 0.0)));
		trunk = step(abs(q.x - 0.5), 0.07 + 0.03 * (1.0 - q.y)) * step(q.y, 0.7);
		stem = look.rgb * 0.3 + vec3(0.25, 0.24, 0.2);
	} else if (form == FORM_CRYSTAL) {
		// A cluster of crystal spikes: flat facets that catch the light.
		float hw = 0.42 * (1.0 - q.y) * (0.8 + 0.4 * seed);
		float side = 0.18 * (1.0 - q.y * 1.6);
		crown = max(step(abs(q.x - 0.5), hw), step(abs(q.x - 0.5 - 0.22 * (seed - 0.5)), side));
		cn = vec3(sign(q.x - 0.5) * 0.8, 0.35, 0.6);
		rough = 0.25;
	} else if (form == FORM_PALM) {
		// A palm: a slim stem, curving a little, under a star of fronds that arch out and
		// hang at their tips.
		float bend = (seed - 0.5) * 0.18 * q.y * q.y;
		vec2 e = (q - vec2(0.5 + bend, 0.8)) / vec2(0.5, 0.2);
		float a = atan(e.y, e.x);
		float lobe = 0.45 + 0.55 * pow(abs(sin(a * 3.5 + seed * 11.0)), 0.6);
		// Fronds droop: the crown hangs lower at its sides than it stands up in the middle.
		float hang = e.y + 0.55 * e.x * e.x;
		crown = step(length(vec2(e.x, hang)), lobe * (0.9 + 0.12 * n)) * step(-0.95, e.y);
		cn = vec3(e.x, max(e.y, 0.0) + 0.35, sqrt(max(1.0 - dot(e, e), 0.0)));
		trunk = step(abs(q.x - 0.5 - bend), 0.022 * (1.2 - q.y * 0.5)) * step(q.y, 0.8);
		stem = vec3(0.17, 0.15, 0.12);
	} else if (form == FORM_MAST) {
		// A mast: a thin pole and its panels.
		trunk = step(abs(q.x - 0.5), 0.025);
		crown = step(abs(q.x - 0.5), 0.34) * step(0.74, q.y) * step(q.y, 0.9);
		cn = vec3(0.0, 0.6, 0.8);
		stem = vec3(0.3, 0.31, 0.33);
		leafy = 0.0;
		rough = 0.4;
	} else {
		// A broadleaf: a lumpy round crown (a few lobes round its rim) on its trunk.
		vec2 e = (q - vec2(0.5, 0.62)) / vec2(0.5, 0.38);
		float a = atan(e.y, e.x);
		float rim = 0.8 + 0.09 * sin(a * 3.0 + seed * 6.3) + 0.06 * sin(a * 5.0 + seed * 17.0) + 0.16 * (n - 0.5);
		crown = step(length(e), rim);
		vec2 s = e / rim;
		cn = vec3(s.x, s.y, sqrt(max(1.0 - dot(s, s), 0.0)));
		trunk = step(abs(q.x - 0.5), 0.035) * step(q.y, 0.45);
		if (form == FORM_BARE) {
			// A dead tree: only a tangle of bare limbs where its crown was, on a tall
			// tapering trunk, all the grey of old wood.
			crown *= step(0.66, vnoise(q * vec2(16.0, 20.0) + seed * 41.0));
			trunk = step(abs(q.x - 0.5), 0.035 * (1.0 - q.y * 0.6)) * step(q.y, 0.85);
			stem = look.rgb * 0.6;
			leafy = 0.0;
		}
	}
	if (crown < 0.5 && trunk < 0.5) {
		discard;
	}
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 nw = b_toward;
	vec3 alb = stem;
	vec3 back = vec3(0.0);
	if (crown > 0.5 && form == FORM_BARE) {
		alb = stem;
	} else if (crown > 0.5) {
		// Lit as a soft dome, bent toward the sky as the near trees' crowns are; clumps of
		// leaves catch the light, with shade between them.
		nw = normalize(mix(normalize(b_right * cn.x + up * cn.y + b_toward * cn.z), up, 0.25));
		float clump = mix(1.0, 0.72 + 0.5 * vnoise(q * vec2(10.0, 13.0) + seed * 37.0), leafy);
		alb = look.rgb * clump * (0.85 + 0.3 * seed);
		// A solid crown shows more of its own shade than a near tree's open leaves do.
		if (form == FORM_BROADLEAF) {
			alb = mix(vec3(dot(alb, vec3(0.2126, 0.7152, 0.0722))), alb, 0.88) * 0.8;
		}
		// Leaves let the light through: a crown against the sun glows its own colour.
		back = look.rgb / max(max(look.r, look.g), 0.001) * 0.55 * leafy;
	}
	ALBEDO = alb * (1.0 - 0.42 * cloud_shadow(wp));
	BACKLIGHT = back;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
