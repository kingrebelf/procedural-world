// The weather on the ground (Weather sets the uniforms): rain darkens the ground and
// gives it a sheen, fills its hollows with puddles that ring with each drop, and drains
// and dries away after; fresh snow settles on open level ground anywhere, thin and patchy
// at first, and melts back when it thaws. Included by terrain.gdshaderinc (after its
// texture helpers), which calls weather_ground() once it has the ground's look.
global uniform float weather_wet_g; // 0 dry .. 1 soaked
global uniform float weather_puddle_g; // 0 none .. 1 the hollows brimming
global uniform float weather_snow_g; // fresh snow, 0 none .. 1 a full cover
global uniform float weather_rain_g; // how hard it is raining here now

float wg_hash(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

// Rings spreading from raindrops on standing water: every cell of a grid takes a drop at
// its own moment and its ring grows and dies away. Returns a world x/z tilt.
vec2 wg_rings(vec2 p, float t, float rate) {
	vec2 tilt = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p * (layer == 0 ? 2.6 : 3.7) + float(layer) * 17.3;
		vec2 cell = floor(q);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				float h = wg_hash(c);
				// In light rain only some cells catch a drop.
				if (fract(h * 91.7) > rate) {
					continue;
				}
				vec2 d = q - c - vec2(h, fract(h * 13.7));
				float r = length(d);
				float ph = fract(t * (0.8 + h * 0.5) + h * 7.0);
				float x = r - ph * 0.9;
				float wave = sin(x * 38.0) * exp(-x * x * 90.0) * (1.0 - ph) * (1.0 - ph);
				tilt += d / max(r, 0.001) * wave;
			}
		}
	}
	return tilt * 0.12;
}

// col, rough, spec: the ground's look so far; n: its world normal. rockiness: bare rock
// (sheds water, no puddles). Changes them in place.
void weather_ground(vec3 wp, vec3 wn, vec2 p, vec4 gp, float macro, float meso, float micro, float slope, float dist,
		float far, float rockiness, inout vec3 col, inout float rough, inout float spec, inout vec3 n) {
	if (weather_wet_g + weather_snow_g < 0.002 || wp.y < 0.05) {
		return;
	}
	vec3 up = vec3(0.0, 1.0, 0.0);
	// Fresh snow: settles first on level open ground and in the hollows of it, the
	// ground's grain showing through until it closes over.
	float fresh = 0.0;
	if (weather_snow_g > 0.001) {
		float level = smoothstep(0.55, 0.85, wn.y);
		fresh = smoothstep(0.05, 0.7, weather_snow_g * 1.35 + (0.5 - meso) * 0.5 + (micro - 0.5) * 0.2 - (1.0 - level) * 1.2);
		vec3 st = untiled(snow_tex, p + 41.0, gp, SNOW_TILE, meso, far).rgb * 0.8;
		st *= mix(vec3(0.84, 0.91, 1.0), vec3(1.0), smoothstep(-0.1, 0.45, dot(wn, sun_dir_g)));
		col = mix(col, mix(col * 0.6 + st * 0.4, st, smoothstep(0.35, 0.85, fresh)), fresh);
		rough = mix(rough, 0.62, fresh);
		spec = mix(spec, 0.4, fresh);
		n = normalize(mix(n, up, fresh * 0.6));
	}
	if (weather_wet_g < 0.002) {
		return;
	}
	// Wet: soil and grass soak up the water and go dark; rock darkens less but shines.
	float wet = weather_wet_g * (1.0 - fresh) * mix(0.55, 1.0, smoothstep(-0.2, 0.6, wn.y));
	col *= mix(1.0, mix(0.6, 0.78, rockiness), wet);
	rough = mix(rough, mix(0.35, 0.2, rockiness), wet);
	spec = mix(spec, 0.5, wet);
	// Puddles: the hollows of level ground fill, the big dips first; bare rock and
	// steep ground shed the water.
	float flat_g = 1.0 - smoothstep(0.03, 0.1, slope);
	float hollow = 1.0 - (meso * 0.65 + macro * 0.35);
	float brim = 1.0 - weather_puddle_g * 0.6;
	float pud = smoothstep(brim, brim + 0.035, hollow + (micro - 0.5) * 0.03) * flat_g * (1.0 - rockiness) * (1.0 - fresh)
		* (1.0 - smoothstep(150.0, 400.0, dist)) * step(0.001, weather_puddle_g);
	if (pud > 0.001) {
		// Muddy water: dark, with the sky in it.
		col = mix(col, col * 0.3 + vec3(0.008, 0.009, 0.008), pud);
		rough = mix(rough, 0.02, pud);
		spec = mix(spec, 0.5, pud);
		vec3 wn2 = up;
		if (weather_rain_g > 0.01 && dist < 35.0) {
			vec2 tilt = wg_rings(p, TIME, clamp(weather_rain_g * 1.3, 0.15, 1.0)) * (1.0 - smoothstep(20.0, 35.0, dist));
			wn2 = normalize(up + vec3(tilt.x, 0.0, tilt.y));
		}
		n = normalize(mix(n, wn2, pud));
	}
}
