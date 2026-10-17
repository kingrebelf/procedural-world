shader_type spatial;
// Sunbeams through a room's windows (SunBeams): each window's box is drawn out along the
// sun's rays to the floor, and a pixel adds the light the dust scatters along the length
// of the shaft it looks through, up to whatever stands in front (the depth buffer). Lit
// dust shines most looking toward the sun.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, world_vertex_coords, shadows_disabled;

global uniform vec3 sun_dir_g;
// The sunlight reaching the ground (colour times energy), nothing under heavy cloud.
global uniform vec3 sun_light_g;
uniform float strength = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// The shaft: the window's centre and its half width and height (world), and the way the
// rays cross the room as far as the floor.
varying flat vec3 bc;
varying flat vec3 br;
varying flat vec3 bu;
varying flat vec3 bd;
// The room (centre and half axes, world): the beam is cut where it meets the walls.
varying flat vec3 rc;
varying flat vec3 rx;
varying flat vec3 ry;
varying flat vec3 rz;
varying vec3 wp;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 e = vec2(1.0, 0.0);
	return mix(mix(mix(hash13(i), hash13(i + e.xyy), f.x), mix(hash13(i + e.yxy), hash13(i + e.xxy), f.x), f.y),
		mix(mix(hash13(i + e.yyx), hash13(i + e.xyx), f.x), mix(hash13(i + e.yxx), hash13(i + e.xxx), f.x), f.y), f.z);
}

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
	float floor_y = (MODEL_MATRIX * vec4(CUSTOM0.x, CUSTOM0.w, CUSTOM0.z, 1.0)).y;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 n = normalize(mat3(MODEL_MATRIX) * vec3(CUSTOM1.x, 0.0, CUSTOM1.y));
	vec3 s = normalize(sun_dir_g);
	br = normalize(cross(n, vec3(0.0, 1.0, 0.0))) * CUSTOM1.z * sc;
	bu = vec3(0.0, CUSTOM1.w * sc, 0.0);
	bc = c;
	// Down to the floor from the top of the window, as far as a low sun reaches.
	bd = -s * min((c.y + bu.y - floor_y) / max(s.y, 0.12), 24.0);
	// Only while the sun is up on the window's side of the room.
	bool lit = dot(-s, n) > 0.05 && s.y > 0.03 && dot(sun_light_g, vec3(1.0)) > 0.001;
	float ceil_y = CUSTOM2.z;
	rc = (MODEL_MATRIX * vec4(0.0, (CUSTOM0.w + ceil_y) * 0.5, 0.0, 1.0)).xyz;
	rx = mat3(MODEL_MATRIX) * vec3(CUSTOM2.x, 0.0, 0.0);
	ry = mat3(MODEL_MATRIX) * vec3(0.0, (ceil_y - CUSTOM0.w) * 0.5, 0.0);
	rz = mat3(MODEL_MATRIX) * vec3(0.0, 0.0, CUSTOM2.y);
	vec3 p = bc + br * UV.x + bu * UV.y + bd * UV2.x;
	VERTEX = lit ? p : vec3(c.x, -10000.0, c.z);
	wp = VERTEX;
}

// Where a ray (in a box's own space) enters and leaves the box from lo to hi.
vec2 slab(vec3 o, vec3 d, vec3 lo, vec3 hi) {
	d += step(abs(d), vec3(1e-6)) * 1e-6;
	vec3 t0 = (lo - o) / d;
	vec3 t1 = (hi - o) / d;
	vec3 tmn = min(t0, t1);
	vec3 tmx = max(t0, t1);
	return vec2(max(max(tmn.x, tmn.y), tmn.z), min(min(tmx.x, tmx.y), tmx.z));
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wp - ro);
	// In the shaft's own space it is a box: x and y across the window (-1 to 1), z along
	// the rays (0 at the window, 1 at the floor).
	mat3 inv = inverse(mat3(br, bu, bd));
	vec3 lo = inv * (ro - bc);
	vec3 ld = inv * rd;
	vec2 tt = slab(lo, ld, vec3(-1.0, -1.0, 0.0), vec3(1.0));
	float tn = tt.x;
	float tf = tt.y;
	// Both faces are drawn: count the shaft once, where the eye's ray leaves it.
	float tw = length(wp - ro);
	if (tn > 0.0 && abs(tw - tn) < abs(tw - tf)) {
		discard;
	}
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float ts = length(v.xyz / v.w);
	// Only inside the room: a low sun's beam ends on the far wall.
	mat3 rinv = inverse(mat3(rx, ry, rz));
	vec2 room = slab(rinv * (ro - rc), rinv * rd, vec3(-1.0), vec3(1.0));
	tn = max(max(tn, room.x), 0.0);
	tf = min(min(tf, ts), room.y);
	float thick = tf - tn;
	if (thick <= 0.0) {
		discard;
	}
	vec3 lm = lo + ld * (tn + tf) * 0.5;
	// Brightest along the middle, falling away softly to the edges, and fading as the
	// light spreads toward the floor.
	float soft = exp(-2.2 * dot(lm.xy, lm.xy)) * (1.0 - smoothstep(0.8, 1.0, max(abs(lm.x), abs(lm.y))));
	float along = mix(1.0, 0.3, clamp(lm.z, 0.0, 1.0)) * smoothstep(0.0, 0.05, lm.z);
	// Streaks down the shaft (light caught by the window's edges and the dust in it), and
	// drifting dust thick and thin.
	float streaks = 0.55 + 0.9 * noise3(vec3(lm.xy * vec2(2.6, 1.8), bc.x * 0.37 + bc.z * 0.71));
	vec3 wm = ro + rd * (tn + tf) * 0.5;
	float motes = 0.75 + 0.5 * noise3(wm * 2.2 + vec3(0.0, TIME * 0.06, TIME * 0.02));
	// Forward scattering (Henyey-Greenstein).
	float g = 0.35;
	float cth = dot(rd, normalize(sun_dir_g));
	float phase = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cth, 1.5);
	float dens = 1.0 - exp(-thick * 0.3);
	ALBEDO = sun_light_g * (dens * soft * along * streaks * motes * phase * strength * 0.25);
	ALPHA = 1.0;
}
