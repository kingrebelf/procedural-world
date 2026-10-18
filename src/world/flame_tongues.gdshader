shader_type particles;
// The body of a flame in the round (FireFx.flame's "Tongues"): tongues of burning gas that
// rise off the fire's bed, quicken as they go (hot gas is light), neck in toward the
// middle, are tossed about by the rising turbulence and carried downwind, cooling from
// white-gold through orange to a dull red before they vanish. They fill out the flipbook
// cards with something that has depth from every side; the cards keep the fine detail.
// Everything is in units of the flame's height (the node's scale), so one material serves
// a torch and a burning house alike. Being in world space, a swung torch leaves them
// streaming behind it. The draw pass (flame_tongue.gdshader) reads each one's width and
// stretch from the basis written here.
render_mode disable_force;

#include "res://src/world/fire.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform float seed = 0.0; // the flame's, shared with its cards and its light
uniform float exposed = 1.0; // 1 out in the wind .. 0 still air indoors
uniform float bed = 0.16; // how far out from the middle they rise, in flame heights

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	w = (w >> 22u) ^ w;
	return float(w) / 4294967295.0;
}

void start() {
	uint s = uint(INDEX) * 1973u + RANDOM_SEED * 9277u + uint(NUMBER) * 26699u;
	float sz = length(EMISSION_TRANSFORM[1].xyz);
	float a = rnd(s) * TAU;
	float r = sqrt(rnd(s)) * bed;
	vec3 o = vec3(cos(a) * r, 0.02 + rnd(s) * 0.1, sin(a) * r);
	vec3 at = (EMISSION_TRANSFORM * vec4(o, 1.0)).xyz;
	TRANSFORM = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(at, 1.0));
	float vs = sz / LIFETIME;
	VELOCITY = vec3(0.0, vs * (0.45 + 0.4 * rnd(s)), 0.0);
	// x: this tongue's own nature; y: how far through its life; zw: where its fire stood.
	CUSTOM = vec4(rnd(s), 0.0, EMISSION_TRANSFORM[3].x, EMISSION_TRANSFORM[3].z);
	COLOR = vec4(0.0);
}

void process() {
	float sz = max(length(EMISSION_TRANSFORM[1].xyz), 1e-4);
	float h = CUSTOM.x;
	// Some burn out low, some lick up to the tips.
	CUSTOM.y += DELTA / (LIFETIME * (0.5 + 0.5 * h));
	float k = CUSTOM.y;
	if (k >= 1.0) {
		ACTIVE = false;
	}
	vec3 p = TRANSFORM[3].xyz;
	float life = fire_life(fire_time, seed);
	float acc = sz / (LIFETIME * LIFETIME);
	// Buoyancy, stronger as the flame leaps.
	VELOCITY.y += acc * (1.0 + 0.9 * life) * DELTA;
	// Drawn in toward the middle above the bed, as flames neck to a point...
	vec2 off = p.xz - CUSTOM.zw;
	VELOCITY.xz -= off / LIFETIME * 2.6 * DELTA;
	// ...tossed about by the turbulence rising through them...
	vec3 q = p / sz;
	float tt = fire_time * 2.4;
	vec2 turb = vec2(fx_noise2(vec2(q.y * 2.6 - tt, q.z * 2.6 + h * 13.0)),
		fx_noise2(vec2(q.x * 2.6 + 7.0, q.y * 2.6 - tt + h * 5.0))) - 0.5;
	VELOCITY.xz += turb * acc * 6.0 * (0.25 + k) * DELTA;
	// ...and laid over downwind, the more the higher they rise.
	VELOCITY.xz += wind_dir * wind_strength * exposed * acc * 2.4 * (0.3 + k) * DELTA;
	VELOCITY.xz *= 1.0 - clamp(2.2 * DELTA, 0.0, 1.0);
	// Wide and soft at the root, narrowing and stretching out along the way they go.
	float w = sz * (0.12 + 0.08 * h) * (1.0 - 0.6 * k) * (0.4 + 0.6 * smoothstep(0.0, 0.15, k));
	float len = w * (1.1 + 0.8 * k);
	float vl = length(VELOCITY);
	vec3 up = vl > 1e-5 ? VELOCITY / vl : vec3(0.0, 1.0, 0.0);
	TRANSFORM[0] = vec4(w, 0.0, 0.0, 0.0);
	TRANSFORM[1] = vec4(up * len, 0.0);
	TRANSFORM[2] = vec4(0.0, 0.0, w, 0.0);
	// White-gold low in the fire, orange, then a dull red as it cools and thins away.
	vec3 c = mix(vec3(1.0, 0.7, 0.32) * 1.9, vec3(1.0, 0.4, 0.08) * 1.3, smoothstep(0.04, 0.35, k));
	c = mix(c, vec3(0.75, 0.15, 0.03) * 0.55, smoothstep(0.35, 0.8, k));
	float al = 0.85 * smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.3, 0.85, k));
	COLOR = vec4(c * (0.72 + 0.56 * life), al);
}
