shader_type spatial;
// Stones and boulders: the rock photo mapped triplanar in world space, so a texel is the
// same size on a pebble and on a boulder ten times its size (object-space mapping
// stretched it with the instance's scale). COLOR.rgb is the stone's tint (vertex colour
// times instance colour, sRGB); COLOR.a how much moss grows on its top. Darker where it
// meets the ground.
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"
#include "res://src/world/noise2d.gdshaderinc"

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 1.6; // metres per repeat
uniform vec3 moss_col : source_color = vec3(0.24, 0.3, 0.12);
const vec3 ROCK_MEAN = vec3(0.266, 0.2665, 0.245);
const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);

varying vec3 wp;
varying vec3 wn;
varying float base_y;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_y = MODEL_MATRIX[3].y;
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
	// Contact shadow where the stone's sides meet the ground (a low stone's top, open to
	// the sky, stays lit).
	col *= mix(0.55, 1.0, max(smoothstep(-0.05, 0.3, wp.y - base_y), smoothstep(0.35, 0.8, wn.y)));
	ALBEDO = col * (1.0 - 0.42 * cloud_shadow(wp));
	ROUGHNESS = mix(0.82, 0.95, moss);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
