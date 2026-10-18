// The distant forest, shared by the distant land (far_land.gdshader, which paints crowns
// and tree shadows on the ground) and the distant trees (far_trees.gdshader, one
// billboard per tree), so both agree on where every tree stands: one cell of a jittered
// grid holds at most one tree, and a cell holds one where its hash falls under the local
// density. Needs noise2d.gdshaderinc.

// Where real chunks of terrain are drawn (one texel per 64 m chunk, how much of it while
// it fades) over the distant land's span: origin x/z and 1 / span. Neither draws there.
uniform sampler2D near_mask : filter_nearest, repeat_disable;
uniform vec4 near_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Over the square round where the distant land was built, one texel per 16 m grid point:
// the crown colour (sRGB) of the species that grows there and how densely trees stand;
// and the ground's height and that species' form (FORM_* over 6). forest_rect: origin
// x/z, 1 / spacing, 1 / texels across.
uniform sampler2D forest_tex : filter_linear, repeat_disable;
uniform sampler2D forest_hgt : filter_linear, repeat_disable;
uniform vec4 forest_rect = vec4(0.0, 0.0, 0.0625, 1.0);

// A tree's form (FarLand.FORM_*): a round crown, a mushroom cap, bare dead limbs, a
// crystal spike, a mast, a conifer's spire, a palm.
const int FORM_BROADLEAF = 0;
const int FORM_CAP = 1;
const int FORM_BARE = 2;
const int FORM_CRYSTAL = 3;
const int FORM_MAST = 4;
const int FORM_CONIFER = 5;
const int FORM_PALM = 6;

int tree_form(float g) {
	return int(g * 6.0 + 0.5);
}

const float TREE_CELL = 4.5;
// Trees stand as billboards out to here; beyond, they are painted on the ground. Between
// the two each tree is one or the other (by its own hash), so the change is gradual.
// FarLand pushes it out the higher you are (FarLand.TREE_BB at ground level).
uniform vec2 tree_bb = vec2(750.0, 900.0);
#define TREE_BB_FROM tree_bb.x
#define TREE_BB_TO tree_bb.y

// How much of the chunk at p is drawn: 1 in, 0 none, between while it fades in or out.
float near_share(vec2 p) {
	return textureLod(near_mask, (p - near_rect.xy) * near_rect.zw, 0.0).r;
}

bool near_drawn(vec2 p) {
	return near_share(p) > 0.5;
}

vec2 forest_uv(vec2 p) {
	return ((p - forest_rect.xy) * forest_rect.z + 0.5) * forest_rect.w;
}

bool in_forest_rect(vec2 uv) {
	return uv.x > 0.002 && uv.y > 0.002 && uv.x < 0.998 && uv.y < 0.998;
}

// Loose clumps: the density thinned and thickened by broad noise.
float tree_density(float a, vec2 p) {
	return clamp(a + (fbm(p * 0.012 + 7.0) - 0.5) * 0.45 * a, 0.0, 1.0);
}

// The tree cell c may hold: xy where it stands (world), z its crown radius (in cells).
vec3 tree_of(vec2 c) {
	vec2 o = c + 0.5 + (vec2(hash12(c), hash12(c + 17.3)) - 0.5) * 0.7;
	return vec3(o * TREE_CELL, 0.36 + 0.22 * hash12(c + 9.7));
}

// The species of the tree standing at `at` (cell c): its crown colour (sRGB) and form
// (as forest_hgt.g). It takes a grid point's own species (no blend), from a point jittered round it,
// so a mixed wood mixes tree by tree.
vec4 tree_species(vec2 at, vec2 c) {
	vec2 j = at + (vec2(hash12(c + 51.3), hash12(c + 77.1)) - 0.5) * 20.0;
	ivec2 sz = textureSize(forest_tex, 0);
	ivec2 t = clamp(ivec2(floor(forest_uv(j) * vec2(sz))), ivec2(0), sz - 1);
	return vec4(texelFetch(forest_tex, t, 0).rgb, texelFetch(forest_hgt, t, 0).g);
}

// Whether the tree of cell c stands as a billboard rather than painted on the ground, at
// this distance from the eye.
bool billboarded(vec2 c, float dist) {
	return hash12(c + 5.5) >= smoothstep(TREE_BB_FROM, TREE_BB_TO, dist);
}

// The nearest tree crown to p, where a fraction d of cells hold a tree: x 1 inside a
// standing tree's crown, y the distance from its centre over its radius, zw the offset to
// its centre (in crown radii); cell the cell it belongs to.
vec4 crown_at(vec2 p, float d, out vec2 cell) {
	vec2 g = p / TREE_CELL;
	vec2 gi = floor(g);
	float f1 = 9.0;
	vec2 off = vec2(0.0);
	float r = 1.0;
	cell = gi;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = gi + vec2(float(x), float(y));
			float h = hash12(c);
			vec2 o = c + 0.5 + (vec2(h, hash12(c + 17.3)) - 0.5) * 0.7 - g;
			float dd = dot(o, o);
			if (dd < f1) {
				f1 = dd;
				off = o;
				r = h;
				cell = c;
			}
		}
	}
	float size = 0.36 + 0.22 * hash12(cell + 9.7);
	float rad = sqrt(f1) / size;
	return vec4(step(r, d) * (1.0 - smoothstep(0.85, 1.05, rad)), rad, off / size);
}
