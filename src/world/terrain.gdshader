shader_type spatial;
// Era-blended terrain. Vertex COLOR.rgb carries the era weights (medieval, fantasy,
// sci-fi) baked into the chunk snapshot. Photo textures (grass, dirt, rock, mud) give the
// surface detail; they are mapped in world space, so there are no seams between chunks,
// and recoloured to each era's palette so fantasy moss and sci-fi dust keep their look.
// Tiling is broken up by blending two rotated scales under a noise mask.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://src/env/clouds.gdshaderinc"

uniform vec3 grass_m : source_color = vec3(0.34, 0.42, 0.24);
uniform vec3 soil_m : source_color = vec3(0.44, 0.36, 0.28);
uniform vec3 rock_m : source_color = vec3(0.55, 0.53, 0.49);
uniform vec3 grass_f : source_color = vec3(0.10, 0.34, 0.33);
uniform vec3 soil_f : source_color = vec3(0.22, 0.14, 0.28);
uniform vec3 rock_f : source_color = vec3(0.36, 0.33, 0.45);
uniform vec3 grass_s : source_color = vec3(0.42, 0.28, 0.20);
uniform vec3 soil_s : source_color = vec3(0.33, 0.21, 0.15);
uniform vec3 rock_s : source_color = vec3(0.36, 0.32, 0.30);
uniform vec3 glow_f : source_color = vec3(0.35, 0.9, 0.8);
uniform vec3 glow_s : source_color = vec3(0.2, 0.8, 1.0);
uniform float detail_strength = 0.6;

#define TEX(n) uniform sampler2D n : source_color, filter_linear_mipmap_anisotropic, repeat_enable
#define NRM(n) uniform sampler2D n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable
// Ground layers per era: medieval grass/dirt, fantasy glow moss/dark soil, sci-fi red dust.
TEX(grass_tex); NRM(grass_nrm);
TEX(dirt_tex); NRM(dirt_nrm);
TEX(glowmoss_tex); NRM(glowmoss_nrm);
TEX(darksoil_tex); NRM(darksoil_nrm);
TEX(regolith_tex); NRM(regolith_nrm);
TEX(rock_tex); NRM(rock_nrm);
TEX(mud_tex); NRM(mud_nrm);
TEX(snow_tex); NRM(snow_nrm);
uniform bool use_textures = false;
uniform float snow_line = 40.0;
// Linear-space mean colour of each texture (printed by tools/make_textures.py). Detail is
// the texture's brightness relative to its mean, recoloured by the era palette and mixed
// with some of the photo's own colour.
const vec3 GRASS_MEAN = vec3(0.1191, 0.1707, 0.0626);
const vec3 DIRT_MEAN = vec3(0.1918, 0.1228, 0.0773);
const vec3 GLOWMOSS_MEAN = vec3(0.0054, 0.0724, 0.0557);
const vec3 DARKSOIL_MEAN = vec3(0.0399, 0.0322, 0.0412);
const vec3 REGOLITH_MEAN = vec3(0.1887, 0.1621, 0.1343);
const vec3 ROCK_MEAN = vec3(0.266, 0.2665, 0.245);
const vec3 MUD_MEAN = vec3(0.1112, 0.094, 0.0732);
const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
const float GRASS_TILE = 2.6; // metres per repeat
const float DIRT_TILE = 3.2;
const float ROCK_TILE = 6.0;
const float MUD_TILE = 3.5;
const float MOSS_TILE = 3.0;
const float DUST_TILE = 5.0;
const float SNOW_TILE = 7.0;
uniform float night_glow = 1.0;

varying vec3 wpos;
varying vec3 wnorm;
// Landform look (v7 worlds): rock colour + amount, ground colour + amount, soft (sand,
// no bare rock on its slopes) and strata (banded rock).
varying vec4 stone_v;
varying vec4 soil_v;
varying vec2 form_v;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Cracked rock: ridged 3D noise gives crevices on cliffs from any direction.
float rock3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * (1.0 - abs(vnoise3(p) * 2.0 - 1.0));
		p = p * 2.1 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return s;
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Two scales of the same texture, rotated against each other and blended by a noise mask
// with distance, so the repeat never lines up into a visible grid.
vec4 untiled(sampler2D t, vec2 p, float tile, float mask, float far) {
	vec4 a = texture(t, p / tile);
	vec4 b = texture(t, rot2(p, 1.13) / (tile * 3.7) + 0.37);
	return mix(a, b, clamp(mask * 0.6 + far, 0.0, 1.0));
}

// Ground sampling that switches from top-down to a side projection on slopes, so
// textures don't smear down hillsides.
vec4 ground(sampler2D t, vec3 wp, vec3 n, vec2 off, float tile, float mask, float far) {
	vec4 top = untiled(t, wp.xz + off, tile, mask, far);
	float ws = smoothstep(0.22, 0.55, 1.0 - n.y);
	if (ws < 0.01) {
		return top;
	}
	vec2 side_uv = abs(n.x) > abs(n.z) ? wp.zy : wp.xy;
	return mix(top, untiled(t, side_uv + off, tile, mask, far), ws);
}

// Planar normal sample turned into a world-space tilt (x, z) for ground facing up.
vec2 untiled_n(sampler2D t, vec2 p, float tile, float mask, float far) {
	vec3 n = untiled(t, p, tile, mask, far).xyz * 2.0 - 1.0;
	return vec2(n.x, -n.y);
}

// Texture detail (brightness relative to its mean) on the era palette colour, plus a share
// (k) of the photo's own colour scaled to the palette's brightness.
// The brightness ratio is softened and clamped so sparkly textures (glow moss) don't
// blow out into specks many times brighter than the palette.
vec3 recolor(vec3 t, vec3 mean, vec3 pal, float k) {
	float lm = max(dot(mean, LUM), 0.001);
	float ratio = clamp(mix(1.0, dot(t, LUM) / lm, 0.7), 0.25, 1.8);
	vec3 own = t / max(dot(t, LUM), 0.001) * dot(pal, LUM) * ratio;
	return mix(pal * ratio, own, k);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	stone_v = CUSTOM0;
	soil_v = CUSTOM1;
	form_v = CUSTOM2.xy;
}

void fragment() {
	vec3 w = COLOR.rgb;
	w /= max(w.r + w.g + w.b, 0.001);
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	vec2 p = wpos.xz;

	// Multi-scale variation: macro patches, meso clumps, micro grain.
	float macro = fbm(p * 0.015);
	float meso = fbm(p * 0.18);
	float micro = vnoise(p * 3.1) * 0.5 + vnoise(p * 7.3) * 0.5;

	vec3 grass = grass_m * w.r + grass_f * w.g + grass_s * w.b;
	vec3 soil = soil_m * w.r + soil_f * w.g + soil_s * w.b;
	vec3 rock = rock_m * w.r + rock_f * w.g + rock_s * w.b;
	rock = mix(rock, pow(stone_v.rgb, vec3(2.2)), stone_v.a);

	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = smoothstep(25.0, 140.0, dist);
	vec2 tilt_g = vec2(0.0); // texture normal detail (world x/z) for grass, soil, rock
	vec2 tilt_s = vec2(0.0);
	vec2 tilt_r = vec2(0.0);
	vec3 mud_d = vec3(1.0);
	float moss_glow = 0.0;
	if (use_textures) {
		// Ground: planar world mapping, one texture pair per era, skipped where absent.
		vec3 gm = vec3(0.0), gs = vec3(0.0);
		if (w.r > 0.01) {
			gm += w.r * recolor(ground(grass_tex, wpos, wnorm, vec2(0.0), GRASS_TILE, meso, far).rgb, GRASS_MEAN, grass_m, 0.6);
			gs += w.r * recolor(ground(dirt_tex, wpos, wnorm, vec2(11.0), DIRT_TILE, meso, far).rgb, DIRT_MEAN, soil_m, 0.6);
			tilt_g += w.r * untiled_n(grass_nrm, p, GRASS_TILE, meso, far);
			tilt_s += w.r * untiled_n(dirt_nrm, p + 11.0, DIRT_TILE, meso, far);
		}
		if (w.g > 0.01) {
			vec3 mt = ground(glowmoss_tex, wpos, wnorm, vec2(5.0), MOSS_TILE, meso, far).rgb;
			moss_glow = w.g * smoothstep(0.2, 0.5, dot(mt, LUM));
			gm += w.g * recolor(mt, GLOWMOSS_MEAN, grass_f, 0.2);
			gs += w.g * recolor(ground(darksoil_tex, wpos, wnorm, vec2(17.0), DIRT_TILE, meso, far).rgb, DARKSOIL_MEAN, soil_f, 0.4);
			tilt_g += w.g * untiled_n(glowmoss_nrm, p + 5.0, MOSS_TILE, meso, far);
			tilt_s += w.g * untiled_n(darksoil_nrm, p + 17.0, DIRT_TILE, meso, far);
		}
		if (w.b > 0.01) {
			vec3 dt = ground(regolith_tex, wpos, wnorm, vec2(29.0), DUST_TILE, meso, far).rgb;
			gm += w.b * recolor(dt, REGOLITH_MEAN, grass_s, 0.45);
			gs += w.b * recolor(dt, REGOLITH_MEAN, soil_s, 0.45);
			vec2 dn2 = untiled_n(regolith_nrm, p + 29.0, DUST_TILE, meso, far);
			tilt_g += w.b * dn2;
			tilt_s += w.b * dn2;
		}
		grass = gm;
		soil = gs;
		mud_d = untiled(mud_tex, p + 23.0, MUD_TILE, meso, far).rgb / MUD_MEAN;
		// Rock: triplanar so cliffs are textured from every side.
		vec3 bw = pow(abs(wnorm), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec3 rp = wpos / ROCK_TILE;
		vec3 rt = texture(rock_tex, rp.zy).rgb * bw.x + texture(rock_tex, rp.xz * 0.8 + 0.5).rgb * bw.y + texture(rock_tex, rp.xy).rgb * bw.z;
		rock = recolor(rt, ROCK_MEAN, rock, 0.5 - 0.3 * stone_v.a) * (0.85 + 0.3 * fbm(vec2(wpos.y * 0.9, (wpos.x + wpos.z) * 0.05)));
		vec3 nx = texture(rock_nrm, rp.zy).xyz * 2.0 - 1.0;
		vec3 nz = texture(rock_nrm, rp.xy).xyz * 2.0 - 1.0;
		vec3 ny = texture(rock_nrm, rp.xz * 0.8 + 0.5).xyz * 2.0 - 1.0;
		tilt_r = vec2(nz.x * bw.z + ny.x * bw.y, nx.x * bw.x - ny.y * bw.y);
	} else {
		// Rock: stratified bands plus 3D crevices so cliffs read as stone from every angle.
		float strata = fbm(vec2(wpos.y * 0.9, (wpos.x + wpos.z) * 0.05));
		float crev = rock3(wpos * 0.45);
		rock *= (0.6 + 0.45 * strata) * (0.55 + 0.6 * crev);
	}

	// Strata: layered bands of paler and redder stone that wander gently with height.
	if (form_v.y > 0.01) {
		float lay = wpos.y * 0.55 + fbm(p * 0.02) * 2.5;
		float band = smoothstep(0.25, 0.75, fbm(vec2(lay, 3.7)));
		float fine = vnoise(vec2(wpos.y * 4.0, (wpos.x + wpos.z) * 0.15));
		vec3 alt = rock * vec3(1.25, 1.05, 0.85);
		rock = mix(rock, mix(rock * 0.78, alt, band) * (0.9 + 0.2 * fine), form_v.y);
	}

	// Grass: lush and dry patches, darker in hollows.
	float dry = smoothstep(0.42, 0.7, fbm(p * 0.006 + 7.0));
	vec3 g = mix(grass, grass * vec3(1.35, 1.15, 0.6), dry * 0.55 * w.r);
	float soil_mask = smoothstep(0.45, 0.75, macro + (meso - 0.5) * 0.4);
	vec3 ground = mix(g * (0.78 + 0.44 * meso), soil * (0.85 + 0.3 * micro), soil_mask * 0.7);
	// A landform's own ground (sand, dust, clay) keeps the texture's light and shade.
	if (soil_v.a > 0.01) {
		vec3 own = pow(soil_v.rgb, vec3(2.2));
		float lm = dot(soil, LUM) / max(dot(soil_m * w.r + soil_f * w.g + soil_s * w.b, LUM), 0.001);
		own *= clamp(mix(1.0, lm, 0.6), 0.6, 1.4) * (0.86 + 0.28 * meso) * (0.94 + 0.12 * micro);
		ground = mix(ground, own, soil_v.a);
	}
	// Shoreline: wet sand/mud near the water level.
	float shore = 1.0 - smoothstep(0.2, 1.6, wpos.y);
	ground = mix(ground, mix(vec3(0.42, 0.38, 0.3), vec3(0.18, 0.16, 0.13), smoothstep(0.6, -0.2, wpos.y)) * mud_d, shore);
	float rock_mask = smoothstep(0.32, 0.52, slope + (meso - 0.5) * 0.18) * (1.0 - form_v.x);
	// Sand: wind ripples across the dunes.
	vec2 ripple = vec2(0.0);
	if (form_v.x > 0.01) {
		vec2 rd = normalize(vec2(0.8, 0.6) + vec2(fbm(p * 0.03), fbm(p * 0.03 + 9.0)) - 0.5);
		float ph = dot(p, rd) * 4.2 + fbm(p * 0.35) * 5.0;
		ripple = rd * cos(ph) * 0.35 * form_v.x * (1.0 - far);
	}
	vec2 tilt = vec2(0.0);
	if (use_textures) {
		vec2 tm = untiled_n(mud_nrm, p + 23.0, MUD_TILE, meso, far);
		tilt = mix(mix(mix(tilt_g, tilt_s, soil_mask * 0.7), tm, shore), tilt_r, rock_mask) * (1.0 - far * 0.7);
	}
	vec3 col = mix(ground, rock, rock_mask);

	// Roads and village squares (vertex alpha): packed earth and gravel, pale flagstones
	// in the fey lands, dark grit in sci-fi ones. Ragged at the edges like a worn track.
	float road = 1.0 - COLOR.a;
	if (road > 0.01) {
		float edge = smoothstep(0.2, 0.65, road + (micro - 0.5) * 0.3 + (meso - 0.5) * 0.25);
		float stones = smoothstep(0.6, 0.85, vnoise(p * 2.3));
		vec3 rm = soil * vec3(0.86, 0.8, 0.7) * (0.82 + 0.3 * micro);
		rm = mix(rm, vec3(0.36, 0.34, 0.31), stones * 0.25);
		float flags = smoothstep(0.08, 0.16, abs(fract(p.x * 0.6 + vnoise(p * 0.7) * 0.6) - 0.5)) * smoothstep(0.08, 0.16, abs(fract(p.y * 0.6) - 0.5));
		vec3 rf = vec3(0.52, 0.5, 0.55) * (0.7 + 0.35 * micro) * (0.7 + 0.3 * flags);
		vec3 rs = vec3(0.22, 0.2, 0.2) * (0.85 + 0.3 * micro);
		vec3 rc = rm * w.r + rf * w.g + rs * w.b;
		col = mix(col, rc, edge * (1.0 - rock_mask * 0.6));
		tilt *= 1.0 - edge * 0.6;
	}

	// Snow on high ground (medieval and sci-fi peaks), thinning on steep faces.
	float snow = 0.0;
	if (use_textures && wpos.y > snow_line - 12.0) {
		snow = smoothstep(snow_line - 6.0, snow_line + 8.0, wpos.y + (macro - 0.5) * 14.0 + (meso - 0.5) * 4.0);
		snow *= (1.0 - w.g) * (1.0 - smoothstep(0.45, 0.75, slope));
		vec3 st = untiled(snow_tex, p + 41.0, SNOW_TILE, meso, far).rgb;
		col = mix(col, st * 0.92, snow);
		tilt = mix(tilt, untiled_n(snow_nrm, p + 41.0, SNOW_TILE, meso, far), snow);
	}

	// Sci-fi: weathered dust and ash; no panel grid, no glitter.
	float plates = 0.0;
	if (w.b > 0.01) {
		float ash = fbm(p * 0.05 + 31.0);
		col = mix(col, col * vec3(1.08, 0.95, 0.88) * (0.85 + 0.3 * ash), w.b * 0.5);
	}

	// Fantasy: bioluminescent spores in the moss (from the moss texture when present).
	if (w.g > 0.01) {
		float spores = use_textures ? moss_glow * (1.0 - soil_mask * 0.7) * 0.6 : smoothstep(0.86, 0.97, vnoise(p * 1.7)) * w.g;
		EMISSION += glow_f * spores * (1.0 - rock_mask) * 0.55 * night_glow;
		col = mix(col, col * vec3(0.9, 1.0, 1.15), w.g * 0.3);
	}

	// Cloud shadows drifting over the land.
	ALBEDO = col * (0.92 + 0.16 * micro) * (1.0 - 0.42 * cloud_shadow(wpos));
	ROUGHNESS = mix(mix(mix(0.92, 0.3, shore * 0.6), 0.5, plates) - 0.1 * rock_mask * w.b, 0.75, snow);
	METALLIC = plates * 0.6;
	SPECULAR = 0.4;

	// Procedural detail normal from the noise gradient (world space -> view space).
	float e = 0.15;
	float h0 = fbm(p * 0.9);
	float hx = fbm((p + vec2(e, 0.0)) * 0.9);
	float hz = fbm((p + vec2(0.0, e)) * 0.9);
	float rs = 1.0 + rock_mask * 1.5;
	vec3 dn = normalize(vec3(-(hx - h0) / e * detail_strength * rs, 1.0, -(hz - h0) / e * detail_strength * rs));
	float proc = use_textures ? 0.35 : 1.0;
	vec3 n = normalize(wnorm + vec3(dn.x, 0.0, dn.z) * proc * (1.0 - plates * 0.8) + vec3(tilt.x, 0.0, tilt.y) * 0.9 + vec3(ripple.x, 0.0, ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
