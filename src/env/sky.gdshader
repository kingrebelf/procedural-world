shader_type sky;
// Era-aware sky: physically inspired gradient, sun and moon discs, stars, a fantasy
// aurora and a sci-fi planetary ring, all weighted by the era weights at the player.

uniform vec3 zenith_day : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 horizon_day : source_color = vec3(0.70, 0.80, 0.92);
uniform vec3 zenith_night : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 horizon_night : source_color = vec3(0.04, 0.05, 0.09);
uniform vec3 sunset : source_color = vec3(1.0, 0.45, 0.2);
uniform vec3 ground_col : source_color = vec3(0.12, 0.12, 0.13);
uniform float daylight = 1.0;
uniform float era_fantasy = 0.0;
uniform float era_scifi = 0.0;
uniform float time_s = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 sun = LIGHT0_DIRECTION;
	float sun_h = sun.y;

	vec3 zen = mix(zenith_night, zenith_day, daylight);
	vec3 hor = mix(horizon_night, horizon_day, daylight);
	vec3 col = mix(hor, zen, pow(up, 0.45));

	// Sunset glow near the sun when it is low.
	float sd = max(dot(d, sun), 0.0);
	float low = 1.0 - smoothstep(0.0, 0.35, abs(sun_h));
	col += sunset * pow(sd, 6.0) * low * 0.9 * (1.0 - up * 0.6);
	col += sunset * low * 0.25 * (1.0 - up) * smoothstep(-0.2, 0.3, dot(normalize(d.xz + vec2(0.0001)), normalize(sun.xz + vec2(0.0001))));

	// Sun disc and halo.
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR * (smoothstep(0.9994, 0.9998, sd) * 40.0 + pow(sd, 400.0) * 3.0) * LIGHT0_ENERGY * step(-0.05, sun_h);
	}
	// Moon opposite the sun.
	float md = max(dot(d, -sun), 0.0);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9990, 0.9994, md) * 2.0 * (1.0 - daylight);

	// Stars.
	float night = 1.0 - daylight;
	if (night > 0.01 && d.y > 0.0) {
		vec3 sp = d * 300.0;
		float s = hash(floor(sp));
		float star = smoothstep(0.9975, 1.0, s) * (0.5 + 0.5 * sin(time_s * 2.0 + s * 100.0));
		col += vec3(star) * night * 1.5;
	}

	// Fantasy aurora: drifting curtains of light.
	if (era_fantasy > 0.01 && d.y > 0.02) {
		vec2 uv = d.xz / (d.y + 0.15);
		float band = noise3(vec3(uv * 0.6, time_s * 0.03));
		float curtain = smoothstep(0.45, 0.75, noise3(vec3(uv.x * 2.5 + band * 3.0, uv.y * 0.4, time_s * 0.05)));
		float fade = smoothstep(0.02, 0.25, d.y) * (1.0 - smoothstep(0.6, 0.95, d.y));
		vec3 ac = mix(vec3(0.1, 1.0, 0.6), vec3(0.6, 0.3, 1.0), band);
		col += ac * curtain * fade * era_fantasy * (0.35 + 1.4 * night);
	}

	// Sci-fi: a vast planetary ring arcing across the sky.
	if (era_scifi > 0.01) {
		vec3 rn = normalize(vec3(0.25, 0.35, 1.0));
		float plane = abs(dot(d, rn));
		float ring = smoothstep(0.035, 0.0, plane) * smoothstep(0.0, 0.15, d.y);
		float bands = 0.6 + 0.4 * sin(dot(d, vec3(1.0, 0.2, 0.0)) * 80.0);
		col = mix(col, vec3(0.85, 0.80, 0.75) * (0.35 + daylight * 0.9) * bands, ring * era_scifi * 0.7);
		// Distant planet.
		vec3 pd = normalize(vec3(-0.6, 0.35, -0.7));
		float pl = smoothstep(0.9965, 0.9970, dot(d, pd));
		float lit = clamp(dot(normalize(d - pd * 0.98), sun) * 0.5 + 0.5, 0.05, 1.0);
		col = mix(col, vec3(0.75, 0.55, 0.45) * lit, pl * era_scifi);
	}

	// Below horizon.
	col = mix(col, ground_col * (0.2 + 0.8 * daylight), smoothstep(0.0, -0.08, d.y));
	COLOR = col;
}
