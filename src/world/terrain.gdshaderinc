// Era-blended terrain (terrain.gdshader; far_land.gdshader draws it out to the horizon). Vertex COLOR.rgb carries the era weights (medieval, fantasy,
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
// Ground cover (vertex CUSTOM3, GroundCover): scree, gravel, leaf litter, snow; and the
// layered rock of cliff faces.
TEX(scree_tex); NRM(scree_nrm);
TEX(gravel_tex); NRM(gravel_nrm);
TEX(litter_tex); NRM(litter_nrm);
TEX(cliff_tex); NRM(cliff_nrm);
uniform bool use_textures = false;
#ifdef FAR_LAND
// Where real chunks of terrain are drawn (one texel per 64 m chunk) over the distant
// land's span: origin x/z and 1 / span. The distant land leaves those out.
uniform sampler2D near_mask : filter_nearest, repeat_disable;
uniform vec4 near_rect = vec4(0.0, 0.0, 1.0, 1.0);
#endif
uniform float snow_line = 40.0;
// Human worlds dress sci-fi land as the wilds; there the blue vertex channel only says
// where a road is paved (outpost streets and the roads of the tech era).
uniform bool paved_roads = false;
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
const vec3 SCREE_MEAN = vec3(0.1527, 0.1086, 0.064);
const vec3 GRAVEL_MEAN = vec3(0.2507, 0.2429, 0.2351);
const vec3 LITTER_MEAN = vec3(0.145, 0.076, 0.0497);
const vec3 CLIFF_MEAN = vec3(0.2418, 0.2256, 0.2061);
const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
const float GRASS_TILE = 2.6; // metres per repeat
const float DIRT_TILE = 3.2;
const float ROCK_TILE = 6.0;
const float MUD_TILE = 3.5;
const float MOSS_TILE = 3.0;
const float DUST_TILE = 5.0;
const float SNOW_TILE = 7.0;
const float SCREE_TILE = 3.0;
const float GRAVEL_TILE = 1.8;
const float LITTER_TILE = 2.4;
const float CLIFF_TILE = 9.0;
uniform float night_glow = 1.0;

varying vec3 wpos;
varying vec3 wnorm;
// Landform look (v7 worlds): rock colour + amount, ground colour + amount, soft (sand,
// no bare rock on its slopes) and strata (banded rock).
varying vec4 stone_v;
varying vec4 soil_v;
varying vec2 form_v;
varying vec4 cover_v;

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
// Sampling takes explicit gradients (g = dp/dx, dp/dy) worked out once at the top of the
// fragment: implicit ones are undefined inside branches that neighbouring pixels skip
// (era, snow, slope), and some GPUs then pick garbage mips and draw black specks along
// the branch edge.
vec4 untiled(sampler2D t, vec2 p, vec4 g, float tile, float mask, float far) {
	vec4 a = textureGrad(t, p / tile, g.xy / tile, g.zw / tile);
	float s2 = 1.0 / (tile * 3.7);
	vec4 b = textureGrad(t, rot2(p, 1.13) * s2 + 0.37, rot2(g.xy, 1.13) * s2, rot2(g.zw, 1.13) * s2);
	return mix(a, b, clamp(mask * 0.6 + far, 0.0, 1.0));
}

// Ground sampling that switches from top-down to a side projection on slopes, so
// textures don't smear down hillsides. dx, dy: screen derivatives of the world position.
vec4 ground(sampler2D t, vec3 wp, vec3 n, vec2 off, vec3 dx, vec3 dy, float tile, float mask, float far) {
	vec4 top = untiled(t, wp.xz + off, vec4(dx.xz, dy.xz), tile, mask, far);
	float ws = smoothstep(0.22, 0.55, 1.0 - n.y);
	if (ws < 0.01) {
		return top;
	}
	bool zside = abs(n.x) > abs(n.z);
	vec2 side_uv = zside ? wp.zy : wp.xy;
	vec4 sg = zside ? vec4(dx.zy, dy.zy) : vec4(dx.xy, dy.xy);
	return mix(top, untiled(t, side_uv + off, sg, tile, mask, far), ws);
}

// Planar normal sample turned into a world-space tilt (x, z) for ground facing up.
vec2 untiled_n(sampler2D t, vec2 p, vec4 g, float tile, float mask, float far) {
	vec3 n = untiled(t, p, g, tile, mask, far).xyz * 2.0 - 1.0;
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
	cover_v = CUSTOM3;
}

// Height-blended layer amount: the layer shows first where its texture is bright (stones
// stand proud of the soil), and its edge is broken up by noise.
float layer(float amount, float lum, float mean, float noise) {
	return smoothstep(0.35, 0.65, amount + (lum / max(mean, 0.001) - 1.0) * 0.25 * amount + (noise - 0.5) * 0.35);
}

void fragment() {
#ifdef FAR_LAND
	vec2 nm = (wpos.xz - near_rect.xy) * near_rect.zw;
	if (texture(near_mask, nm).r > 0.5) {
		discard;
	}
#endif
	vec3 dwx = dFdx(wpos);
	vec3 dwy = dFdy(wpos);
	vec4 gp = vec4(dwx.xz, dwy.xz);
	vec3 w = COLOR.rgb;
	float paved = 0.0;
	if (paved_roads) {
		paved = w.b;
		w.b = 0.0;
	}
	w /= max(w.r + w.g + w.b, 0.001);
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	vec2 p = wpos.xz;

	// Multi-scale variation: macro patches, meso clumps, micro grain. On steep faces the
	// ground plane squeezes a whole cliff into a few texels of x/z, which drew the grain
	// as long vertical streaks; there it comes from 3D noise instead.
	float macro = fbm(p * 0.015);
	float meso = fbm(p * 0.18);
	float micro = vnoise(p * 3.1) * 0.5 + vnoise(p * 7.3) * 0.5;
	float steep = smoothstep(0.3, 0.55, slope);
	if (steep > 0.01) {
		float meso3 = vnoise3(wpos * 0.18) * 0.6 + vnoise3(wpos * 0.37 + 4.1) * 0.4;
		float micro3 = vnoise3(wpos * 3.1) * 0.5 + vnoise3(wpos * 7.3) * 0.5;
		meso = mix(meso, meso3, steep);
		micro = mix(micro, micro3, steep);
	}

	vec3 grass = grass_m * w.r + grass_f * w.g + grass_s * w.b;
	vec3 soil = soil_m * w.r + soil_f * w.g + soil_s * w.b;
	vec3 rock = rock_m * w.r + rock_f * w.g + rock_s * w.b;
	rock = mix(rock, pow(stone_v.rgb, vec3(2.2)), stone_v.a);

	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = smoothstep(25.0, 140.0, dist);
	vec2 tilt_g = vec2(0.0); // texture normal detail (world x/z) for grass, soil, rock
	vec2 tilt_s = vec2(0.0);
	vec2 tilt_r = vec2(0.0);
	vec3 rock_n = vec3(0.0); // world-space tilt of rock faces
	vec3 mud_d = vec3(1.0);
	float moss_glow = 0.0;
	if (use_textures) {
		// Ground: planar world mapping, one texture pair per era, skipped where absent.
		vec3 gm = vec3(0.0), gs = vec3(0.0);
		if (w.r > 0.01) {
			gm += w.r * recolor(ground(grass_tex, wpos, wnorm, vec2(0.0), dwx, dwy, GRASS_TILE, meso, far).rgb, GRASS_MEAN, grass_m, 0.6);
			gs += w.r * recolor(ground(dirt_tex, wpos, wnorm, vec2(11.0), dwx, dwy, DIRT_TILE, meso, far).rgb, DIRT_MEAN, soil_m, 0.6);
			tilt_g += w.r * untiled_n(grass_nrm, p, gp, GRASS_TILE, meso, far);
			tilt_s += w.r * untiled_n(dirt_nrm, p + 11.0, gp, DIRT_TILE, meso, far);
		}
		if (w.g > 0.01) {
			vec3 mt = ground(glowmoss_tex, wpos, wnorm, vec2(5.0), dwx, dwy, MOSS_TILE, meso, far).rgb;
			moss_glow = w.g * smoothstep(0.2, 0.5, dot(mt, LUM));
			gm += w.g * recolor(mt, GLOWMOSS_MEAN, grass_f, 0.2);
			gs += w.g * recolor(ground(darksoil_tex, wpos, wnorm, vec2(17.0), dwx, dwy, DIRT_TILE, meso, far).rgb, DARKSOIL_MEAN, soil_f, 0.4);
			tilt_g += w.g * untiled_n(glowmoss_nrm, p + 5.0, gp, MOSS_TILE, meso, far);
			tilt_s += w.g * untiled_n(darksoil_nrm, p + 17.0, gp, DIRT_TILE, meso, far);
		}
		if (w.b > 0.01) {
			vec3 dt = ground(regolith_tex, wpos, wnorm, vec2(29.0), dwx, dwy, DUST_TILE, meso, far).rgb;
			gm += w.b * recolor(dt, REGOLITH_MEAN, grass_s, 0.45);
			gs += w.b * recolor(dt, REGOLITH_MEAN, soil_s, 0.45);
			vec2 dn2 = untiled_n(regolith_nrm, p + 29.0, gp, DUST_TILE, meso, far);
			tilt_g += w.b * dn2;
			tilt_s += w.b * dn2;
		}
		grass = gm;
		soil = gs;
		mud_d = untiled(mud_tex, p + 23.0, gp, MUD_TILE, meso, far).rgb / MUD_MEAN;
		// Rock: triplanar so cliffs are textured from every side. Faces show layered cliff
		// rock (upright, at two scales so the repeat breaks up); tops the cracked rock.
		vec3 bw = pow(abs(wnorm), vec3(4.0));
		bw /= bw.x + bw.y + bw.z;
		vec3 rp = wpos / ROCK_TILE;
		vec2 cx = vec2(wpos.z, -wpos.y) / CLIFF_TILE;
		vec2 cz = vec2(wpos.x, -wpos.y) / CLIFF_TILE;
		float cm = smoothstep(0.3, 0.7, vnoise3(wpos * 0.06));
		vec3 rt = mix(texture(cliff_tex, cx).rgb, texture(cliff_tex, cx * 0.43 + 0.31).rgb, cm) * bw.x
			+ texture(rock_tex, rp.xz * 0.8 + 0.5).rgb * bw.y
			+ mix(texture(cliff_tex, cz).rgb, texture(cliff_tex, cz * 0.43 + 0.31).rgb, cm) * bw.z;
		vec3 rmean = mix(CLIFF_MEAN, ROCK_MEAN, bw.y);
		rock = recolor(rt, rmean, rock, 0.5 - 0.3 * stone_v.a) * (0.85 + 0.3 * fbm(vec2(wpos.y * 0.9, (wpos.x + wpos.z) * 0.05)));
		vec3 nx = mix(texture(cliff_nrm, cx).xyz, texture(cliff_nrm, cx * 0.43 + 0.31).xyz, cm) * 2.0 - 1.0;
		vec3 nz = mix(texture(cliff_nrm, cz).xyz, texture(cliff_nrm, cz * 0.43 + 0.31).xyz, cm) * 2.0 - 1.0;
		vec3 ny = texture(rock_nrm, rp.xz * 0.8 + 0.5).xyz * 2.0 - 1.0;
		// Each projection's tangent normal tilts the surface within its own plane.
		rock_n = vec3(0.0, nx.y, nx.x) * bw.x + vec3(ny.x, 0.0, -ny.y) * bw.y + vec3(nz.x, nz.y, 0.0) * bw.z;
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

	// Grass: lush and dry patches, darker in hollows, and broad swathes of deeper and
	// paler green so distant meadows are never one flat colour.
	float dry = smoothstep(0.42, 0.7, fbm(p * 0.006 + 7.0));
	vec3 g = mix(grass, grass * vec3(1.35, 1.15, 0.6), dry * 0.7 * w.r);
	float swathe = fbm(p * 0.035 + 21.0);
	g *= mix(vec3(0.82, 0.9, 0.8), vec3(1.12, 1.08, 0.92), smoothstep(0.3, 0.7, swathe));
	float soil_mask = smoothstep(0.45, 0.75, macro + (meso - 0.5) * 0.4);
	vec3 ground = mix(g * (0.78 + 0.44 * meso), soil * (0.85 + 0.3 * micro), soil_mask * 0.7);
	// A landform's own ground (sand, dust, clay) keeps the texture's light and shade.
	if (soil_v.a > 0.01) {
		vec3 own = pow(soil_v.rgb, vec3(2.2));
		float lm = dot(soil, LUM) / max(dot(soil_m * w.r + soil_f * w.g + soil_s * w.b, LUM), 0.001);
		own *= clamp(mix(1.0, lm, 0.6), 0.6, 1.4) * (0.86 + 0.28 * meso) * (0.94 + 0.12 * micro);
		ground = mix(ground, own, soil_v.a);
	}
	// Ground cover: leaf litter under trees, stony scree at the feet of cliffs and in rocky
	// patches, gravel on banks and shores. Each blends in by its own texture's height.
	vec2 tilt_c = vec2(0.0);
	float cov = 0.0;
	if (use_textures && cover_v.r + cover_v.g + cover_v.b > 0.01) {
		if (cover_v.b > 0.01) {
			vec3 lt = untiled(litter_tex, p + 51.0, gp, LITTER_TILE, meso, far).rgb;
			float a = layer(cover_v.b * (0.4 + 0.6 * w.r), dot(lt, LUM), dot(LITTER_MEAN, LUM), micro);
			ground = mix(ground, recolor(lt, LITTER_MEAN, soil, 0.75 * w.r), a);
			tilt_c = mix(tilt_c, untiled_n(litter_nrm, p + 51.0, gp, LITTER_TILE, meso, far), a);
			cov = max(cov, a);
		}
		if (cover_v.r > 0.01) {
			vec3 st = untiled(scree_tex, p + 61.0, gp, SCREE_TILE, meso, far).rgb;
			float a = layer(cover_v.r, dot(st, LUM), dot(SCREE_MEAN, LUM), micro);
			vec3 pal = mix(soil, rock, 0.35);
			ground = mix(ground, recolor(st, SCREE_MEAN, pal, 0.55 * w.r), a);
			tilt_c = mix(tilt_c, untiled_n(scree_nrm, p + 61.0, gp, SCREE_TILE, meso, far) * 1.3, a);
			cov = max(cov, a);
		}
		if (cover_v.g > 0.01) {
			vec3 gt = untiled(gravel_tex, p + 71.0, gp, GRAVEL_TILE, meso, far).rgb;
			float a = layer(cover_v.g, dot(gt, LUM), dot(GRAVEL_MEAN, LUM), micro);
			ground = mix(ground, recolor(gt, GRAVEL_MEAN, rock * 0.9, 0.5 * w.r), a);
			tilt_c = mix(tilt_c, untiled_n(gravel_nrm, p + 71.0, gp, GRAVEL_TILE, meso, far) * 1.2, a);
			cov = max(cov, a);
		}
	}
	// A landform's bare ground (crater dust, badland clay; not soft sand) is strewn with
	// grit and pebbles of its own colour, thicker in drifts.
	float grit = soil_v.a * (1.0 - form_v.x);
	if (use_textures && grit > 0.01) {
		vec3 gt = untiled(gravel_tex, p + 23.0, gp, GRAVEL_TILE * 1.4, meso, far).rgb;
		float a = layer(grit * (0.3 + 0.45 * fbm(p * 0.07 + 5.0)), dot(gt, LUM), dot(GRAVEL_MEAN, LUM), micro);
		ground = mix(ground, recolor(gt, GRAVEL_MEAN, pow(soil_v.rgb, vec3(2.2)) * 1.05, 0.6), a);
		tilt_c = mix(tilt_c, untiled_n(gravel_nrm, p + 23.0, gp, GRAVEL_TILE * 1.4, meso, far), a);
		cov = max(cov, a);
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
		vec2 tm = untiled_n(mud_nrm, p + 23.0, gp, MUD_TILE, meso, far);
		tilt = mix(mix(mix(mix(tilt_g, tilt_s, soil_mask * 0.7), tilt_c, cov), tm, shore), tilt_r, rock_mask) * (1.0 - far * 0.7);
	}
	vec3 col = mix(ground, rock, rock_mask);

	// Roads and village squares (vertex alpha): packed earth and gravel, pale flagstones
	// in the fey lands, dark grit in sci-fi ones. Ragged at the edges like a worn track.
	float road = 1.0 - COLOR.a;
	if (road > 0.01) {
		float edge = smoothstep(0.2, 0.65, road + (micro - 0.5) * 0.3 + (meso - 0.5) * 0.25);
		vec3 rm = soil * vec3(0.86, 0.8, 0.7) * (0.82 + 0.3 * micro);
		if (use_textures) {
			// Packed earth with drifts of trodden gravel, each edge following the stones.
			vec3 gt = untiled(gravel_tex, p + 91.0, gp, GRAVEL_TILE, meso, far).rgb;
			float a = layer(0.35 + 0.4 * fbm(p * 0.35 + 13.0), dot(gt, LUM), dot(GRAVEL_MEAN, LUM), micro) * w.r;
			rm = mix(rm, recolor(gt, GRAVEL_MEAN, soil * vec3(1.05, 1.0, 0.92) * 1.2, 0.55), a);
			tilt = mix(tilt, untiled_n(gravel_nrm, p + 91.0, gp, GRAVEL_TILE, meso, far), a * edge);
		} else {
			float stones = smoothstep(0.6, 0.85, vnoise(p * 2.3));
			rm = mix(rm, vec3(0.36, 0.34, 0.31), stones * 0.25);
		}
		float flags = smoothstep(0.08, 0.16, abs(fract(p.x * 0.6 + vnoise(p * 0.7) * 0.6) - 0.5)) * smoothstep(0.08, 0.16, abs(fract(p.y * 0.6) - 0.5));
		vec3 rf = vec3(0.52, 0.5, 0.55) * (0.7 + 0.35 * micro) * (0.7 + 0.3 * flags);
		vec3 rs = vec3(0.22, 0.2, 0.2) * (0.85 + 0.3 * micro);
		vec3 rc = rm * w.r + rf * w.g + rs * w.b;
		if (paved > 0.01) {
			// Asphalt: fine dark grit, greyer where it has worn and weathered.
			vec3 asph = vec3(0.07, 0.07, 0.068);
			if (use_textures) {
				vec3 gt2 = untiled(gravel_tex, p + 37.0, gp, GRAVEL_TILE * 0.5, meso, far).rgb;
				asph = recolor(gt2, GRAVEL_MEAN, asph, 0.0);
			}
			asph *= (0.8 + 0.5 * smoothstep(0.35, 0.75, fbm(p * 0.07 + 3.0))) * (0.92 + 0.16 * micro);
			rc = mix(rc, asph, paved);
			// A paved edge is a clean line, not a ragged track.
			edge = mix(edge, smoothstep(0.3, 0.45, road), paved);
		}
		col = mix(col, rc, edge * (1.0 - rock_mask * 0.6));
		tilt *= 1.0 - edge * mix(0.4, 0.85, paved);
	}

	// Snow on high ground (medieval and sci-fi peaks), thinning on steep faces.
	// The cover map says where snow lies (drifts on high ground, none on steep faces); it
	// settles into the hollows of the ground first, so its edge follows the texture.
	float snow = 0.0;
	if (use_textures && cover_v.a > 0.01 && wpos.y > snow_line - 20.0) {
		float under = dot(col, LUM) / max(dot(col, LUM) + 0.05, 0.001);
		snow = smoothstep(0.25, 0.6, cover_v.a + (meso - 0.5) * 0.3 + (micro - 0.5) * 0.12 - (under - 0.5) * 0.15 * (1.0 - cover_v.a));
		snow *= (1.0 - w.g) * (1.0 - smoothstep(0.55, 0.85, slope));
		// The map is per metre, so on a tall wall one triangle spans its snowy top and its
		// foot: never let snow run down below the snow line's reach.
		snow *= smoothstep(snow_line - 16.0, snow_line - 8.0, wpos.y + (macro - 0.5) * 8.0);
		vec3 st = untiled(snow_tex, p + 41.0, gp, SNOW_TILE, meso, far).rgb;
		// Thin snow lets the ground show as a grey-blue dusting before it closes over.
		vec3 dust = mix(col, st * vec3(0.86, 0.9, 0.96), 0.6);
		col = mix(col, mix(dust, st * 0.95, smoothstep(0.4, 0.9, snow)), snow);
		tilt = mix(tilt, untiled_n(snow_nrm, p + 41.0, gp, SNOW_TILE, meso, far) * 0.6, snow);
		rock_n *= 1.0 - snow;
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

	// Sunlight focused by the waves into caustics on lake and sea beds, fading with depth.
	if (wpos.y < 0.3) {
		float under = smoothstep(0.3, -0.4, wpos.y);
		vec2 cq = p * 0.45;
		float ct = TIME * 0.6;
		float c1 = vnoise(cq + vec2(ct * 0.5, -ct * 0.3) + vnoise(cq * 0.6 + ct * 0.2) * 1.8);
		float c2 = vnoise(cq * 1.37 + vec2(-ct * 0.4, ct * 0.45) + vnoise(cq * 0.8 - ct * 0.15) * 1.6);
		float caus = pow(1.0 - abs(c1 * 2.0 - 1.0), 7.0) + pow(1.0 - abs(c2 * 2.0 - 1.0), 7.0) * 0.7;
		float lit = smoothstep(-0.05, 0.3, sun_dir_g.y) * (1.0 - cloud_shadow(wpos));
		col *= 1.0 + caus * under * exp(wpos.y * 0.12) * lit * 1.4 * (1.0 - far);
	}

	// Cloud shadows drifting over the land.
	ALBEDO = col * (0.92 + 0.16 * micro) * (1.0 - 0.42 * cloud_shadow(wpos));
	ROUGHNESS = mix(mix(mix(0.92, 0.3, shore * 0.6), 0.5, plates) - 0.1 * rock_mask * w.b, 0.62, snow);
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
	vec3 bump = vec3(dn.x, 0.0, dn.z) * proc * (1.0 - steep) * (1.0 - snow * 0.7);
	if (steep > 0.01) {
		// Faces: the gradient of 3D noise, kept in the plane of the face.
		float e3 = 0.2;
		vec3 q = wpos * 0.9;
		float g0 = vnoise3(q) + vnoise3(q * 2.3) * 0.5;
		vec3 gr = vec3(vnoise3(q + vec3(e3, 0, 0)) + vnoise3((q + vec3(e3, 0, 0)) * 2.3) * 0.5,
			vnoise3(q + vec3(0, e3, 0)) + vnoise3((q + vec3(0, e3, 0)) * 2.3) * 0.5,
			vnoise3(q + vec3(0, 0, e3)) + vnoise3((q + vec3(0, 0, e3)) * 2.3) * 0.5) - g0;
		gr /= e3;
		gr -= dot(gr, wnorm) * wnorm;
		bump -= gr * detail_strength * 0.5 * steep * proc;
	}
	vec3 n = normalize(wnorm + bump * (1.0 - plates * 0.8) + vec3(tilt.x, 0.0, tilt.y) * 0.9 * (1.0 - rock_mask * steep) + rock_n * rock_mask * 0.9 + vec3(ripple.x, 0.0, ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
