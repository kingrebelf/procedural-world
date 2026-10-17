// Every tree and bush its own: a hash of where the plant stands (its instance origin)
// gives it its own leaf shade, share of dry sprays, thin lopsided side and moss. RealTree
// .plant_look() is the same function on the CPU, for the merged far mesh that bakes it.

uint plant_h32(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

// Four uniform randoms for the plant standing at `origin` (world space), `salt` picking
// another four.
vec4 plant_rand(vec3 origin, uint salt) {
	ivec2 c = ivec2(floor(origin.xz * 2.0)) + ivec2(1048576);
	uint h = plant_h32(uint(c.x) ^ plant_h32(uint(c.y) + salt * 0x9E3779B1u));
	uint g = plant_h32(h);
	return vec4(float(h & 0xFFFFu), float(h >> 16u), float(g & 0xFFFFu), float(g >> 16u)) / 65536.0;
}

// (leaf shade -0.8 cool blue-green .. 0.8 warm yellow-green, share of dry sprays, how
// thin one side of the crown is, which side): most plants healthy and full, a few tired.
vec4 plant_look(vec3 origin) {
	vec4 r = plant_rand(origin, 0u);
	float dry = r.y < 0.75 ? r.y * 0.08 : 0.06 + (r.y - 0.75) * 0.6;
	float thin = r.z < 0.6 ? r.z * 0.15 : 0.09 + (r.z - 0.6) * 0.6;
	return vec4((r.x * 2.0 - 1.0) * 0.8, dry, thin, r.w * 6.2831853);
}

// The leaf colour of a plant with that look: `card` is the spray's own random (its vertex
// alpha), so the same sprays are dry whatever the light.
vec3 plant_leaf(vec3 col, vec4 look, float card) {
	vec3 warm = vec3(1.1, 1.03, 0.78);
	vec3 cool = vec3(0.88, 0.98, 1.08);
	col *= look.x > 0.0 ? mix(vec3(1.0), warm, look.x) : mix(vec3(1.0), cool, -look.x);
	float dry = step(1.0 - look.y, fract(card * 7.31));
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	return mix(col, lum * vec3(1.45, 1.02, 0.42), dry * 0.8);
}

// Whether a spray at `p` (plant space) is missing: thinned crowns are thinnest on one side.
bool plant_gap(vec3 p, vec4 look, float card) {
	vec2 side = vec2(cos(look.w), sin(look.w));
	float lop = dot(normalize(p.xz + vec2(0.0001)), side) * 0.5 + 0.5;
	return card < look.z * (0.35 + 0.65 * lop);
}
