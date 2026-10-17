// The life of a flame, shared by every fire shader and mirrored line for line in
// FireFx.life() (GDScript), so a fire's light leaps and sinks with the flame you see.
// The hash is exact integer arithmetic below 2^24, so the GPU's floats and the CPU's
// doubles give the same answer.

global uniform float fire_time;

float fx_perm(float x) {
	return mod((34.0 * x + 1.0) * x, 289.0);
}

float fx_hash(float i) {
	return fx_perm(fx_perm(mod(i, 289.0)) + 17.0) / 289.0;
}

// Smooth 1-D value noise, 0..1.
float fx_noise(float x) {
	float i = floor(x);
	float f = x - i;
	return mix(fx_hash(i), fx_hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// 0 (sinking low) .. 1 (leaping), about 0.5 on average: a slow swell, a quicker
// waver and a fast shiver, each fire (seed 0..1) in its own time.
float fire_life(float t, float seed) {
	float s = seed * 97.0;
	return 0.5 * fx_noise(t * 1.9 + s) + 0.3 * fx_noise(t * 5.3 + s * 1.7 + 11.0) + 0.2 * fx_noise(t * 12.7 + s * 2.3 + 23.0);
}

// Smooth 2-D value noise, 0..1, for the turbulence that licks up through a flame.
float fx_cell(vec2 i) {
	return fx_perm(fx_perm(mod(i.x, 289.0)) + mod(i.y, 289.0)) / 289.0;
}

float fx_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fx_cell(i), fx_cell(i + vec2(1.0, 0.0)), u.x), mix(fx_cell(i + vec2(0.0, 1.0)), fx_cell(i + vec2(1.0)), u.x), u.y);
}
