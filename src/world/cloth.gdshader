shader_type spatial;
// Cloth in the wind (ClothFx): market awnings, hanging banners and the drapes of stalls,
// and flags on poles. Everything moves in the model's own space from where the cloth is
// held, read from CUSTOM0 (ClothFx works it out when the mesh is built):
//   x  hang:   metres the cloth hangs below where it is held (a drape or a banner); it
//              swings out downwind like a pendulum and ripples, more the further down;
//   y  billow: metres in from the frame a stretched canopy is (an awning's roof); it
//              lifts and breathes with the gusts, most in the middle;
//   z  along:  metres from the pole along a flag (with w = 1); the flag turns to stream
//              downwind from its pole at CUSTOM1.xy, droops in a calm, and waves run
//              out along it, quicker and harder as the wind rises, the fly end
//              snapping in a gale.
// CUSTOM1: xy the pole's x and z, z the flag's resting direction (radians, in the model's
// XZ plane, 0 along +X), w its length. The wind is the world's (Atmosphere's globals);
// the phase comes from where each piece stands, so no two move in step.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform vec4 albedo : source_color = vec4(1.0);
// Dye from vertex colours (flags), else from the texture alone (kit cloth).
uniform bool vertex_dye = false;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness = 0.92;
uniform float normal_depth = 1.0;
// 0 out in the open .. 1 indoors, where only a draught stirs it.
uniform float shelter = 0.0;
// How much light comes through the weave from behind.
uniform float translucency = 0.35;

// The wind where this piece stands, in the model's XZ plane, and how strong.
varying vec3 wl;
varying float ws;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(float x) {
	float i = floor(x);
	float f = x - i;
	return mix(hash12(vec2(i, 3.7)), hash12(vec2(i + 1.0, 3.7)), f * f * (3.0 - 2.0 * f));
}

// A drape or banner (hang h metres below its hold) or a canopy (billow b metres in from
// its frame): where its rest point p (model space, normal n) moves to.
vec3 drape(vec3 p, vec3 n, float h, float b, float t, float ph) {
	vec3 d = vec3(0.0);
	vec2 w2 = wl.xz;
	float along = dot(p.xz, w2);
	// Gusts roll through it downwind; a calm leaves only a slow drift.
	float g = 0.55 + 0.45 * sin(along * 0.7 - t * 1.25 + ph) * (0.6 + 0.4 * vnoise(t * 0.37 + ph));
	if (h > 0.0) {
		float hh = min(h, 2.5);
		// Pushed out downwind like a pendulum, lifting at the bottom as it swings.
		float push = hh * clamp(ws * (0.18 + 0.17 * abs(dot(n.xz, w2))) * g, 0.0, 0.55);
		push += hh * 0.025 * sin(t * 0.8 + ph * 2.0 + p.x * 0.6);
		d.xz += w2 * push;
		d.y += hh - sqrt(max(hh * hh - push * push, 0.0));
		// Ripples running across it with the wind, finer and quicker as the wind rises.
		float k = 3.5 + 3.0 * ws;
		float rip = sin(along * k - t * (2.2 + 5.0 * ws) + p.y * 2.2 + ph)
			+ 0.45 * sin(along * k * 2.3 + p.y * 3.1 - t * (3.7 + 8.0 * ws) + ph * 1.7);
		d += n * rip * hh * (0.008 + 0.03 * ws) * (0.4 + 0.6 * g);
	}
	if (b > 0.0) {
		// A stretched canopy breathes: lifted by the gusts, shivering in a strong wind.
		float bb = min(b, 1.2);
		float lift = bb * (0.04 + 0.22 * ws) * (g - 0.35);
		lift += bb * ws * ws * 0.03 * sin(along * 6.0 + p.y * 4.0 - t * 11.0 + ph);
		d += n * sign(n.y + 1e-4) * lift;
	}
	return d;
}

// A flag: where the point `a` metres along from the pole, at height y, moves to (relative
// to the pole at that height), with the surface's normal.
vec3 flag(float a, float y, float len, float t, float ph, out vec3 nrm) {
	// It turns downwind, wandering a little, and droops toward the pole in a calm.
	float wander = (vnoise(t * 0.21 + ph) - 0.5) * 0.5 * (1.0 - 0.6 * ws);
	float ang = atan(wl.z, wl.x) + wander;
	float droop = 1.0 - smoothstep(0.05, 0.55, ws);
	float u = clamp(a / max(len, 1e-3), 0.0, 1.0);
	float phi = mix(0.06, 1.25, droop) * (0.3 + 0.35 * u);
	vec3 dir = vec3(cos(ang) * cos(phi), -sin(phi), sin(ang) * cos(phi));
	vec3 side = vec3(-sin(ang), 0.0, cos(ang));
	// Waves run out from the pole; a stronger wind drives them faster and shorter and
	// makes the fly end snap.
	float om = 2.2 + 9.0 * ws;
	float k1 = 6.2831 / (len * (1.15 - 0.35 * ws));
	float amp = len * (0.07 + 0.11 * ws) * (1.0 - 0.55 * droop);
	float s1 = a * k1 - t * om + ph;
	float s2 = a * k1 * 2.1 + y * 2.6 - t * om * 1.7 + ph * 1.3;
	float s3 = a * k1 * 4.3 - y * 5.0 - t * om * 2.9 + ph * 2.1;
	float env = pow(u, 1.15);
	float fly = smoothstep(0.55, 1.0, u) * ws * ws;
	float w = amp * env * (sin(s1) + 0.38 * sin(s2)) + len * 0.025 * fly * sin(s3);
	float dw_da = amp * env * (k1 * cos(s1) + 0.38 * k1 * 2.1 * cos(s2)) + amp * 1.15 * pow(u, 0.15) / len * (sin(s1) + 0.38 * sin(s2))
		+ len * 0.025 * fly * k1 * 4.3 * cos(s3);
	float dw_dy = amp * env * 0.38 * 2.6 * cos(s2) - len * 0.025 * fly * 5.0 * cos(s3);
	// A rippled flag is a little shorter than a flat one.
	float aa = a * (1.0 - 0.04 * (1.0 - droop) - 0.03 * ws);
	vec3 ta = dir + side * dw_da;
	vec3 ty = vec3(0.0, 1.0, 0.0) + side * dw_dy;
	nrm = normalize(cross(ty, ta));
	return dir * aa + side * w;
}

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 lw = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	vec2 w2 = normalize(lw.xz + vec2(1e-4));
	wl = vec3(w2.x, 0.0, w2.y);
	// Each piece its own gusts, from where it stands in the world.
	vec3 piece = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = hash12(floor(piece.xz * 0.5) + 0.37) * 6.2831;
	float local = 0.75 + 0.5 * vnoise(wind_time * 0.23 + ph * 3.0 + dot(wpos.xz, wind_dir) * 0.02);
	ws = mix(clamp(wind_strength * local, 0.0, 1.0), 0.03 + 0.03 * vnoise(TIME * 0.2 + ph), shelter);
	float t = mix(wind_time, TIME * 0.6, shelter);
	vec4 c0 = CUSTOM0;
	if (c0.w > 0.5) {
		vec4 c1 = CUSTOM1;
		vec3 n;
		vec3 off = flag(c0.z, VERTEX.y, c1.w, t, ph, n);
		// The side of the flag this vertex's normal faced at rest, kept as it turns.
		vec2 rest_side = vec2(-sin(c1.z), cos(c1.z));
		float sgn = dot(NORMAL.xz, rest_side) >= 0.0 ? 1.0 : -1.0;
		VERTEX = vec3(c1.x, VERTEX.y, c1.y) + off;
		NORMAL = n * sgn;
	} else if (c0.x > 0.0 || c0.y > 0.0) {
		vec3 p = VERTEX;
		vec3 n = NORMAL;
		vec3 d0 = drape(p, n, c0.x, c0.y, t, ph);
		// The surface's new slope, from two nearby points moved the same way (a point
		// higher up hangs less far).
		vec3 t1 = normalize(abs(n.y) < 0.9 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
		vec3 t2 = normalize(cross(n, t1));
		float e = 0.06;
		vec3 q1 = p + t1 * e;
		vec3 q2 = p + t2 * e;
		float h1 = c0.x > 0.0 ? max(c0.x - t1.y * e, 0.0) : 0.0;
		float h2 = c0.x > 0.0 ? max(c0.x - t2.y * e, 0.0) : 0.0;
		vec3 p0 = p + d0;
		vec3 p1 = q1 + drape(q1, n, h1, c0.y, t, ph);
		vec3 p2 = q2 + drape(q2, n, h2, c0.y, t, ph);
		vec3 nn = normalize(cross(p1 - p0, p2 - p0));
		NORMAL = dot(nn, n) >= 0.0 ? nn : -nn;
		VERTEX = p0;
	}
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = albedo.rgb;
	if (has_albedo) {
		col *= texture(albedo_tex, uv).rgb;
	}
	if (vertex_dye) {
		// Dyes are given as sRGB colours, as the game's other vertex colours are.
		col *= pow(COLOR.rgb, vec3(2.2));
	}
	ALBEDO = col;
	float ao = 1.0;
	float rough = roughness;
	if (has_orm) {
		vec3 orm = texture(orm_tex, uv).rgb;
		ao = orm.r;
		rough = orm.g;
	}
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.3;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	// Sun through the weave: a banner glows warm where the light is behind it.
	BACKLIGHT = col * translucency;
}
