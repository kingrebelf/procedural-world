shader_type particles;
// Mist and spray off the foot of a waterfall (WaterfallFx). Each puff starts somewhere
// along the line where the sheet lands, is thrown up and out, slows, swells and thins,
// and drifts off with the wind (Atmosphere's wind_dir and wind_strength, the one wind).
// The emitter's own axes: x across the fall, z out from the cliff.

global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform vec3 spread = vec3(4.0, 10.0, 8.0); // half-width, drop, pool radius

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) * (1.0 / 4294967296.0);
}

void start() {
	uint s = NUMBER * 9781u + RANDOM_SEED * 6271u + uint(INDEX) * 3617u;
	vec3 p = vec3((rnd(s) * 2.0 - 1.0) * spread.x, rnd(s) * 1.2, (rnd(s) - 0.3) * 2.5);
	TRANSFORM = EMISSION_TRANSFORM * mat4(vec4(1, 0, 0, 0), vec4(0, 1, 0, 0), vec4(0, 0, 1, 0), vec4(p, 1.0));
	float up = (0.8 + rnd(s) * 1.4) * (0.6 + spread.y * 0.03);
	float outv = 0.6 + rnd(s) * 1.6;
	VELOCITY = (EMISSION_TRANSFORM * vec4((rnd(s) * 2.0 - 1.0) * 0.6, up, outv, 0.0)).xyz;
	// x: size at birth, y: how big it grows, z: a little variety in brightness.
	CUSTOM = vec4(0.0, 1.5 + rnd(s) * 1.5, 0.85 + rnd(s) * 0.15, 0.0);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}

void process() {
	float life = CUSTOM.w / LIFETIME;
	CUSTOM.w += DELTA;
	vec3 wind = vec3(wind_dir.x, 0.0, wind_dir.y) * (0.4 + wind_strength * 3.5);
	// Air drag pulls it toward the wind's speed; it rises a little, warm off the churn.
	// (The engine moves it on by its velocity.)
	VELOCITY += ((wind + vec3(0.0, 0.25, 0.0)) - VELOCITY) * min(DELTA * 0.9, 1.0);
	float sz = (1.2 + spread.y * 0.08) * (CUSTOM.y * (0.35 + life * 0.9));
	TRANSFORM[0].xyz = vec3(sz, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sz, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sz);
	float a = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.45, 1.0, life));
	COLOR = vec4(vec3(CUSTOM.z), a * (0.3 + min(spread.y, 30.0) * 0.01));
}
