shader_type sky;
render_mode use_half_res_pass;
#include "res://src/env/clouds.gdshaderinc"
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
uniform float cloud_cover = 0.5;
// Cloud quality (graphics settings): ray-marched clouds or the flat deck, and march steps.
uniform bool volumetric_clouds = true;
uniform int cloud_steps = 28;
uniform int cloud_light_steps = 4;
global uniform vec2 wind_dir;
global uniform float wind_strength;

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

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

// --- Volumetric clouds -----------------------------------------------------------------
// A slab of cloud between CLOUD_LO and CLOUD_HI metres, ray-marched at half resolution:
// weather-scale coverage, billowing 3D shape eroded at the edges, light marched toward the
// sun (Beer's law with a powder term) and a forward-scattering phase for silver linings.
const float CLOUD_LO = 1400.0;
const float CLOUD_HI = 3600.0;

float fbm_n(vec3 p, int oct) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		s += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float cloud_density(vec3 p, vec2 drift, bool cheap) {
	float h = (p.y - CLOUD_LO) / (CLOUD_HI - CLOUD_LO);
	if (h < 0.0 || h > 1.0) return 0.0;
	vec2 q = p.xz + drift;
	// Weather: which parts of the sky have clouds at all.
	float cov = cloud_coverage(q, cloud_cover);
	// Rounded bottoms, cauliflower tops.
	float profile = smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.45 - cov * 0.3, h);
	// Billows: big rounded lumps plus smaller ones, so tops pile up like cumulus.
	float shape = fbm_n(vec3(q.x, p.y * 1.2, q.y) * 0.0014 + vec3(0.0, time_s * 0.002, 0.0), cheap ? 2 : 4);
	float lumps = noise3(vec3(q.x, p.y * 0.8, q.y) * 0.00045);
	float d = cov * profile * (0.55 + lumps * 0.7) - (1.0 - shape) * 0.55;
	if (!cheap && d > 0.0) {
		// Erode the edges with finer detail.
		d -= (1.0 - fbm_n(vec3(q.x, p.y, q.y) * 0.004, 2)) * 0.12 * (1.0 - d);
	}
	return clamp(d * 2.2, 0.0, 1.0);
}

float hg(float c, float g) {
	return (1.0 - g * g) / (12.566 * pow(1.0 + g * g - 2.0 * g * c, 1.5));
}

vec4 march_clouds(vec3 d, vec3 sun, vec3 sun_col, vec3 amb, vec2 jitter_px) {
	if (d.y < 0.015) return vec4(0.0);
	float t0 = CLOUD_LO / d.y;
	float t1 = min(CLOUD_HI / d.y, 60000.0);
	if (t0 > 60000.0) return vec4(0.0);
	int STEPS = cloud_steps;
	float dt = (t1 - t0) / float(STEPS);
	float t = t0 + dt * hash(vec3(jitter_px, time_s));
	vec2 drift = cloud_drift;
	float cos_s = dot(d, sun);
	float phase = mix(hg(cos_s, 0.6), hg(cos_s, -0.25), 0.3) * 6.0 + 0.4;
	vec3 col = vec3(0.0);
	float trans = 1.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = d * t;
		float den = cloud_density(p, drift, false);
		if (den > 0.002) {
			// Light: a few steps toward the sun.
			float od = 0.0;
			// Fewer light steps reach the same distance with longer strides.
			float stride = 1760.0 / float(cloud_light_steps * cloud_light_steps);
			for (int j = 1; j <= cloud_light_steps; j++) {
				od += cloud_density(p + sun * (stride * float(j * j)), drift, true) * stride * float(2 * j - 1);
			}
			float sigma = 0.012;
			float beer = exp(-od * sigma * 0.55);
			float powder = 1.0 - exp(-den * 2.5);
			float hfrac = (p.y - CLOUD_LO) / (CLOUD_HI - CLOUD_LO);
			vec3 lum = sun_col * beer * powder * phase * 2.6 + amb * (0.55 + 0.8 * hfrac);
			float a = 1.0 - exp(-den * sigma * dt);
			col += trans * a * lum;
			trans *= 1.0 - a;
			if (trans < 0.02) break;
		}
		t += dt;
	}
	// Fade into the haze toward the horizon.
	float fade = smoothstep(0.015, 0.12, d.y);
	return vec4(col, (1.0 - trans) * fade);
}

void sky() {
	vec3 d = EYEDIR;
	if (AT_HALF_RES_PASS) {
		vec3 sunh = LIGHT0_DIRECTION;
		vec3 scol = mix(vec3(1.0, 0.55, 0.32), vec3(1.0, 0.97, 0.92), smoothstep(0.0, 0.35, sunh.y)) * daylight;
		vec3 amb = mix(mix(horizon_night, horizon_day, daylight), mix(zenith_night, zenith_day, daylight), 0.5) * 0.9 + vec3(0.02, 0.025, 0.035);
		// Flat-cloud quality skips the march entirely.
		vec4 c = volumetric_clouds ? march_clouds(d, sunh, scol * 1.4, amb, FRAGCOORD.xy) : vec4(0.0);
		COLOR = c.rgb;
		ALPHA = c.a;
	} else {
	float up = clamp(d.y, 0.0, 1.0);
	vec3 sun = LIGHT0_DIRECTION;
	float sun_h = sun.y;

	vec3 zen = mix(zenith_night, zenith_day, daylight);
	vec3 hor = mix(horizon_night, horizon_day, daylight);
	vec3 col = mix(hor, zen, pow(up, 0.45));

	// Sunset glow near the sun when it is low.
	float sd = max(dot(d, sun), 0.0);
	float low = 1.0 - smoothstep(0.0, 0.35, abs(sun_h));
	col += sunset * pow(sd, 8.0) * low * 0.8 * (1.0 - up * 0.6) * smoothstep(-0.25, 0.05, sun_h);
	float az = dot(normalize(d.xz + vec2(0.0001)), normalize(sun.xz + vec2(0.0001))) * 0.5 + 0.5;
	col += sunset * low * 0.22 * pow(1.0 - up, 3.0) * az * az * daylight;

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
		// Thin rippling curtains with fine vertical rays, faint by day.
		float curtain = smoothstep(0.55, 0.8, noise3(vec3(uv.x * 2.5 + band * 3.0, uv.y * 0.4, time_s * 0.05)));
		float rays = 0.55 + 0.45 * noise3(vec3(uv.x * 18.0 + band * 6.0, 0.0, time_s * 0.2));
		float fade = smoothstep(0.05, 0.3, d.y) * (1.0 - smoothstep(0.55, 0.9, d.y));
		vec3 ac = mix(vec3(0.1, 0.9, 0.5), vec3(0.55, 0.25, 0.95), band);
		col += ac * curtain * rays * fade * era_fantasy * (0.02 + 0.45 * night * night);
	}

	// Sci-fi: a vast planetary ring arcing across the sky.
	if (era_scifi > 0.01) {
		vec3 rn = normalize(vec3(0.25, 0.35, 1.0));
		float plane = abs(dot(d, rn));
		// Rings: several soft concentric bands, brighter toward the inner edge.
		float side = dot(d, normalize(vec3(1.0, 0.0, -0.25)));
		float rr = plane / max(0.25, 1.0 - abs(side) * 0.5);
		float ring = smoothstep(0.11, 0.06, rr) * smoothstep(0.0, 0.02, rr);
		float bands = 0.55 + 0.25 * sin(rr * 220.0) + 0.2 * sin(rr * 61.0);
		ring *= smoothstep(0.0, 0.12, d.y);
		col = mix(col, vec3(0.88, 0.82, 0.74) * (0.25 + daylight * 0.75) * bands, ring * era_scifi * 0.45);
		// Distant planet.
		vec3 pd = normalize(vec3(-0.6, 0.35, -0.7));
		float pl = smoothstep(0.9965, 0.9970, dot(d, pd));
		float lit = clamp(dot(normalize(d - pd * 0.98), sun) * 0.5 + 0.5, 0.05, 1.0);
		col = mix(col, vec3(0.75, 0.55, 0.45) * lit, pl * era_scifi);
	}

	// Clouds: a lit cloud deck drifting with the wind. Density from fbm, cover from the
	// weather; the sun side gets silver lining, the far side is shaded.
	if (!AT_CUBEMAP_PASS && volumetric_clouds) {
		// Volumetric clouds from the half-resolution pass.
		col = col * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb;
	} else if (d.y > 0.0) {
		// Reflections and ambient light: a cheaper flat cloud deck.
		// A curved deck (larger offset) keeps the projection from stretching into
		// radial streaks toward the horizon.
		vec2 uv = d.xz / (d.y + 0.32) * 1.5;
		vec2 drift = wind_dir * time_s * (0.004 + wind_strength * 0.02);
		float base = fbm3(vec3(uv * 0.55 + drift, time_s * 0.004));
		float detail = fbm3(vec3(uv * 2.3 + drift * 1.7, time_s * 0.01));
		float dens = smoothstep(1.0 - cloud_cover * 0.75 - 0.18, 1.05 - cloud_cover * 0.45, base * 0.78 + detail * 0.32);
		dens *= smoothstep(0.02, 0.26, d.y);
		// Self shadowing: sample toward the sun.
		vec2 toward = normalize(sun.xz + vec2(0.0001)) * 0.12;
		float shade = fbm3(vec3((uv + toward) * 0.55 + drift, time_s * 0.004));
		float lit = clamp(1.0 - (shade - base) * 3.0, 0.35, 1.25);
		vec3 sun_col = mix(vec3(1.0, 0.62, 0.38), vec3(1.0, 0.98, 0.95), smoothstep(0.0, 0.4, sun_h));
		vec3 cloud = mix(hor * 0.9, sun_col * (0.7 + 0.5 * daylight), daylight) * lit;
		cloud += sun_col * pow(sd, 12.0) * 0.6 * daylight * (1.0 - dens);
		cloud = mix(cloud, vec3(0.05, 0.06, 0.09) + hor * 0.3, 1.0 - daylight);
		col = mix(col, cloud, dens * 0.92);
	}

	// Below horizon.
	// Below horizon: hazy toward the horizon colour, so the far edge of the land (seen from
	// the air) melts into haze instead of a dark band.
	vec3 below = mix(hor, ground_col * (0.2 + 0.8 * daylight), 0.4);
	col = mix(col, below, smoothstep(0.0, -0.08, d.y));
	COLOR = col;
	}
}
