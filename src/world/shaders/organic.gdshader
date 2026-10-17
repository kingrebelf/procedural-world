shader_type spatial;
// Living surfaces of fantasy and alien flora (mushroom caps and stems, xeno plants):
// a colour gradient along the shape (UV.y), fibrous streaks (UV.x), mottling, optional
// glowing spots, subsurface scattering and light shining through thin parts.
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night_glow_g;
global uniform float wind_time;
global uniform float wind_strength;
uniform vec3 col_a : source_color = vec3(0.6, 0.5, 0.4);
uniform vec3 col_b : source_color = vec3(0.8, 0.7, 0.6);
uniform vec3 spot_col : source_color = vec3(1.0);
uniform float spot_amt = 0.0;
uniform float spot_scale = 2.5;
uniform vec3 glow_col : source_color = vec3(0.3, 0.9, 1.0);
uniform float glow = 0.0; // glow over the whole surface (gills, pods)
uniform float spot_glow = 0.0; // glow of the spots
uniform float streaks = 0.3;
uniform float sss = 0.5;
uniform float rough = 0.6;
uniform float sway = 0.0; // metres of sway at 10 m height

varying vec3 opos;

float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return n3(p) * 0.5 + n3(p * 2.03) * 0.3 + n3(p * 4.1) * 0.2; }
// Distance to the nearest random point in a 3D cell grid (round spots).
float cells(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); float d = 8.0;
	for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 r = o + vec3(h3(i + o), h3(i + o + 7.1), h3(i + o + 13.7)) - f;
		d = min(d, dot(r, r));
	}
	return sqrt(d);
}

void vertex() {
	opos = VERTEX;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y, 0.0) / 10.0;
		float s = sin(wind_time * 1.3 + wp.x * 0.07 + wp.z * 0.05) * (0.4 + wind_strength);
		VERTEX.x += s * sway * h * h;
		VERTEX.z += s * sway * 0.6 * h * h;
	}
}

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	vec3 c = mix(col_a, col_b, smoothstep(0.0, 1.0, t));
	float m = fbm(opos * 1.7);
	c *= 0.78 + 0.44 * m;
	c *= 1.0 - streaks * 0.5 * (0.5 + 0.5 * sin(UV.x * 6.2831 * 22.0 + m * 6.0));
	float spot = 0.0;
	if (spot_amt > 0.0) {
		float d = cells(opos * spot_scale);
		// Round warts of varied size, softly edged.
		float sz = 0.12 + 0.2 * spot_amt * h3(floor(opos * spot_scale) + 3.3);
		spot = (1.0 - smoothstep(sz, sz + 0.05, d)) * step(0.3, h3(floor(opos * spot_scale)));
		c = mix(c, spot_col, spot);
	}
	c *= COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = rough - spot * 0.2;
	SSS_STRENGTH = sss;
	BACKLIGHT = c * sss * 0.8;
	float night = clamp(night_glow_g, 0.0, 1.5);
	EMISSION = glow_col * (glow * (0.6 + 0.4 * m) + spot_glow * spot) * (0.2 + 0.8 * night);
}
