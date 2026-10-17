shader_type spatial;
// Stones and boulders: the rock photo mapped triplanar in world space, so a texel is the
// same size on a pebble and on a boulder ten times its size (object-space mapping
// stretched it with the instance's scale). COLOR.rgb is the stone's tint (vertex colour
// times instance colour, sRGB); COLOR.a how much moss grows on its top. Darker where it
// meets the ground. Up past the snow line, snow lies on it instead of moss.
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 1.6; // metres per repeat
// How far (a fraction of the stone's size) its surface heaves in and out by where it
// lies, so no two stones from one mesh share an outline. 0 for cave shells, whose
// walls must stay where their collision is.
uniform float wobble = 0.07;
uniform vec3 soil_col : source_color = vec3(0.2, 0.16, 0.11);
uniform vec3 moss_col : source_color = vec3(0.24, 0.3, 0.12);
// 0 for cave shells: no snow inside a mountain.
uniform float snow_cover = 1.0;
global uniform float snow_line_g;
const vec3 ROCK_MEAN = vec3(0.266, 0.2665, 0.245);
const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);

varying vec3 wp;
varying vec3 wn;
varying float base_y;
varying float stone_size;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	base_y = MODEL_MATRIX[3].y;
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Out from the stone's own middle, by noise in the world: a corner shared by two faces
	// moves the same way for both, and a stone's base stays in the ground.
	float size = length(MODEL_MATRIX[0].xyz);
	stone_size = size;
	if (wobble > 0.0 && size > 0.0) {
		vec3 q = p / max(size, 0.05);
		float h = (vnoise3(q * 2.1 + o) - 0.5) + (vnoise3(q * 5.3 + o.zxy) - 0.5) * 0.45;
		vec3 dir = normalize(p - o + vec3(0.0, 1e-4, 0.0));
		float lift = smoothstep(0.0, 0.15 * size, p.y - base_y);
		p += dir * h * wobble * 2.0 * size * lift;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(p, 1.0)).xyz;
	}
	wp = p;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec3 q = wp / tile;
	vec3 t = texture(rock_tex, q.zy).rgb * bw.x + texture(rock_tex, q.xz + 0.37).rgb * bw.y + texture(rock_tex, q.xy + 0.71).rgb * bw.z;
	// A second, coarser scale over big faces (boulders, cave shells) so the repeat
	// doesn't read as a pattern.
	vec3 q2 = q * 0.23;
	vec3 t2 = texture(rock_tex, q2.zy + 0.5).rgb * bw.x + texture(rock_tex, q2.xz + 0.13).rgb * bw.y + texture(rock_tex, q2.xy + 0.29).rgb * bw.z;
	t = mix(t, t * dot(t2, LUM) / dot(ROCK_MEAN, LUM), 0.5);
	vec3 nx = texture(rock_nrm, q.zy).xyz * 2.0 - 1.0;
	vec3 ny = texture(rock_nrm, q.xz + 0.37).xyz * 2.0 - 1.0;
	vec3 nz = texture(rock_nrm, q.xy + 0.71).xyz * 2.0 - 1.0;
	vec3 n = normalize(wn + (vec3(0.0, nx.y, nx.x) * bw.x + vec3(ny.x, 0.0, -ny.y) * bw.y + vec3(nz.x, nz.y, 0.0) * bw.z) * 1.1);
	float lum = dot(t, LUM) / dot(ROCK_MEAN, LUM);
	vec3 tint = pow(clamp(COLOR.rgb, 0.0, 1.0), vec3(2.2));
	// Stone is seldom darker than basalt or bluer than slate: the darkest tints are lifted
	// and the strongest calmed, so a dark boulder in a meadow reads as stone, not a hole.
	float tl = dot(tint, LUM);
	tint = mix(vec3(tl), tint, 0.65) * max(1.0, 0.11 / max(tl, 0.001));
	// The tint's colour with the photo's light and shade, plus a little of its own hue.
	vec3 own = t / max(dot(t, LUM), 0.001) * dot(tint, LUM);
	vec3 col = mix(tint, own, 0.3) * clamp(mix(1.0, lum, 0.85), 0.3, 1.8);
	// Moss on the upward faces, filling the darker crevices first, in patches and
	// cushions with ragged edges (not a carpet laid over the top), the bare stone
	// showing through between them.
	float up = smoothstep(0.25, 0.9, n.y);
	vec3 mt = texture(moss_tex, wp.xz / 1.3).rgb;
	float patches = fbm(wp.xz * 0.45 + wp.y * 0.35 + 5.0) * 0.85 + fbm(wp.xz * 1.6 + 2.0) * 0.15;
	float moss = smoothstep(0.35, 0.7, COLOR.a * up * 1.18 - (lum - 1.0) * 0.45 + (dot(mt, LUM) - 0.12) * 1.2
		+ (patches - 0.5) * 1.9 - 0.1);
	// moss_col is already linear (source_color); the grass photo gives it texture, and
	// cushions in the sun go yellower and paler, those in the crevices deeper.
	vec3 mc = moss_col * clamp(dot(mt, LUM) / 0.155, 0.4, 1.6);
	mc = mix(mc * vec3(0.8, 0.85, 0.9), mc * vec3(1.25, 1.18, 0.85), smoothstep(0.35, 0.75, fbm(wp.xz * 2.3 + 9.0)));
	col = mix(col, mc * mix(0.75, 1.0, smoothstep(0.6, 1.0, moss)), moss * step(0.01, COLOR.a));
	// Where it meets the ground the stone is earthed: soil splashed and silted up its
	// foot in a ragged, uneven tide line (not a ruled edge), mossier in green lands, and
	// a contact shadow under that (a low stone's top, open to the sky, stays lit).
	float above = wp.y - base_y;
	float tide = (0.12 + 0.22 * fbm(wp.xz * 3.1 + wp.y * 1.7 + 11.0)) * clamp(stone_size, 0.15, 1.5);
	float earth = (1.0 - smoothstep(tide - 0.08, tide + 0.04, above)) * (1.0 - smoothstep(0.55, 0.85, wn.y));
	vec3 soil = mix(soil_col, mc * 0.7, step(0.01, COLOR.a) * 0.45) * clamp(dot(mt, LUM) / 0.155, 0.6, 1.3);
	col = mix(col, soil, earth * 0.85);
	// Above the snow line: snow on its upward faces in place of the moss, thinning to
	// streaks on the steeper ones, and banked up round its foot, as wind leaves it
	// against anything that stands in the open.
	float high = snow_cover * smoothstep(snow_line_g - 12.0, snow_line_g + 2.0, wp.y + (fbm(wp.xz * 0.07 + 3.0) - 0.5) * 10.0);
	float snow = 0.0;
	if (high > 0.0) {
		float cap = smoothstep(0.35, 0.75, n.y + (patches - 0.5) * 0.6 + (fbm(wp.xz * 4.0 + wp.y + 1.0) - 0.5) * 0.3);
		float bank = 1.0 - smoothstep(tide * 1.6 - 0.1, tide * 1.6 + 0.05, above);
		snow = max(cap, bank * (1.0 - smoothstep(0.85, 1.0, abs(wn.y)))) * high;
		vec3 sc = vec3(0.74) * mix(vec3(0.84, 0.91, 1.0), vec3(1.0), smoothstep(-0.1, 0.45, dot(n, sun_dir_g)));
		col = mix(col, sc, snow);
		moss *= 1.0 - snow;
		earth *= 1.0 - snow;
	}
	col *= mix(0.55, 1.0, max(max(smoothstep(-0.05, 0.3, above), smoothstep(0.35, 0.8, wn.y)), snow * 0.6));
	ALBEDO = col * (1.0 - 0.42 * cloud_shadow(wp));
	ROUGHNESS = mix(mix(0.82, 0.95, max(moss, earth)), 0.62, snow);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
