shader_type spatial;
// Soot over anything a fire has scorched: drawn as an overlay pass that multiplies what
// is under it, so it works on every material (kit models, built pieces, houses). How
// burnt it is comes from the instance colour's alpha (1 = clean, 0 = black through: the
// chunk's multimesh rows, ChunkNode.build_object_buffers) or from `soot` (0..1) on a
// single mesh. Flames blacken from where they lick: heaviest round the openings and
// up under the eaves, patchy everywhere, in world-space noise so no two walls match.
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

instance uniform float soot = -1.0;

varying vec3 wp;
varying float burnt;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	burnt = soot >= 0.0 ? soot : 1.0 - COLOR.a;
}

void fragment() {
	if (burnt <= 0.001) {
		discard;
	}
	float n = noise(wp * 0.9) * 0.6 + noise(wp * 3.1) * 0.3 + noise(wp * 9.0) * 0.1;
	// Soot climbs: streaks run upward (stretched noise), denser higher on a wall.
	float streak = noise(vec3(wp.x * 2.2, wp.y * 0.35, wp.z * 2.2));
	float cover = clamp(burnt * 1.5 - (1.0 - n) * 0.9 + streak * 0.35, 0.0, 1.0);
	// Thin soot greys and browns the surface; thick soot is a matte black-brown.
	vec3 thin = vec3(0.62, 0.58, 0.54);
	vec3 thick = vec3(0.07, 0.06, 0.055);
	vec3 c = mix(vec3(1.0), thin, smoothstep(0.0, 0.35, cover));
	c = mix(c, thick, smoothstep(0.35, 1.0, cover));
	ALBEDO = c;
}
