// How the place's climate has weathered a surface (ClimateWear): moss where it is wet,
// snow lying and hoar frost where it is cold, dust where it is dry, kept out of rooms by
// the shelter map (ShelterMap). Nothing here glows. Include noise2d.gdshaderinc first.

global uniform sampler2D climate_wear_map_g : filter_linear, repeat_disable; // moss, cold, dust, bog
global uniform vec4 climate_wear_rect_g; // its origin x, z and side (0 before the first map)
global uniform vec4 climate_wear_now_g; // frost the time of day allows, game day
global uniform sampler2D shelter_map_g : filter_linear, repeat_disable; // top of everything, from above
global uniform vec4 shelter_rect_g; // its origin x, z, side, and the height its 0 stands for
global uniform float snow_line_g;
global uniform float weather_snow_g; // fresh snow from the weather (Weather), 0..1

const float SHELTER_RANGE = 256.0;
const vec4 WEAR_TEMPERATE = vec4(0.45, 0.0, 0.0, 0.0);
const vec3 WEAR_SNOW = vec3(0.8, 0.82, 0.86);
const vec3 WEAR_FROST = vec3(0.7, 0.75, 0.8);
const vec3 WEAR_DUST = vec3(0.56, 0.45, 0.31);

// The place's levels from the map (ClimateWear.levels), as the climate alone has them.
vec4 wear_map(vec3 p) {
	vec2 uv = (p.xz - climate_wear_rect_g.xy) / max(climate_wear_rect_g.z, 1.0);
	if (climate_wear_rect_g.z > 0.0 && uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		return texture(climate_wear_map_g, uv);
	}
	return WEAR_TEMPERATE;
}

// The place's levels at p, the cold (frost, winter-killed grass) rising over the last
// 20 m below the snow line.
vec4 wear_levels(vec3 p) {
	vec4 l = wear_map(p);
	l.y = max(l.y, smoothstep(snow_line_g - 20.0, snow_line_g + 2.0, p.y));
	return l;
}

// How much snow lies at p, 0..1: wherever it lies on the ground round it, so roofs, walls,
// rocks, grass and trees all carry it together. That is up past the snow line (as the
// ground's own snow, GroundCover), deep in the cold belt (the terrain's weather_ground
// lays the same), and anywhere fresh snow has fallen (weather_snow_g).
float wear_snow(vec3 p) {
	float belt = smoothstep(0.7, 1.0, wear_map(p).y);
	float high = smoothstep(snow_line_g - 6.0, snow_line_g + 8.0, p.y);
	return max(max(belt, high), clamp(weather_snow_g, 0.0, 1.0));
}

// Height of the highest thing over (x, z): a roof, a floor above, a canopy, or the ground
// itself. Very low off the map (all open sky).
float wear_top(vec2 xz) {
	vec2 uv = (xz - shelter_rect_g.xy) / max(shelter_rect_g.z, 1.0);
	if (shelter_rect_g.z <= 0.0 || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return -1e9;
	}
	return shelter_rect_g.w + texture(shelter_map_g, uv).r * SHELTER_RANGE;
}

// (open, indoors) at p with world normal n. open: 1 where p sees the sky straight up (a
// roof's own face does; the floor under it doesn't). indoors: 1 for a face looking into a
// roofed space (a room's walls and floor, the underside of eaves), 0 for one looking out
// (a house's outside walls, its roof), judged a metre out along the face.
vec2 wear_shelter(vec3 p, vec3 n) {
	// A sloping face spans heights within one texel, so allow for its slope.
	float tol = 0.3 + 0.2 * min(length(n.xz) / max(abs(n.y), 0.2), 3.0);
	float above = wear_top(p.xz) - p.y - tol;
	float open = 1.0 - smoothstep(0.0, 0.4, above) * (1.0 - 0.6 * smoothstep(8.0, 14.0, above));
	vec2 out_dir = n.xz / max(length(n.xz), 1e-4);
	vec2 q = p.xz + out_dir * (1.0 - abs(n.y)) * 1.0;
	float over = wear_top(q) - p.y;
	// Something 0.3 to 12 m over that spot is a ceiling or eave; higher is a tree's crown.
	float roofed = smoothstep(0.3, 0.8, over) * (1.0 - smoothstep(10.0, 14.0, over));
	// Floors and roofs go by what is over them, walls by what is over the ground they face.
	float indoors = mix(1.0 - open, roofed, 1.0 - smoothstep(0.3, 0.7, abs(n.y)));
	return vec2(open, clamp(indoors, 0.0, 1.0));
}

// Dust comes and goes: thicker after dry windy spells, a few game days each, at different
// times in different places.
float wear_dust_now(vec3 p) {
	return 0.55 + 0.45 * smoothstep(0.3, 0.75, vnoise(p.xz / 2600.0 + vec2(climate_wear_now_g.y * 0.31, 7.3)));
}

// Hoar frost the place and the hour allow: on cold mornings where it is cold, a thin rime
// that stays all day deep in the cold.
float wear_frost(vec4 lv) {
	return smoothstep(0.3, 0.7, lv.y) * climate_wear_now_g.x + smoothstep(0.75, 1.0, lv.y) * 0.2;
}

// Weathers a building's surface in place. p, n: world position and normal (the face's,
// before its normal map); base_y: the foot of the building or piece; age: how far it has
// weathered toward its place's level (ClimateWear.maturity); take: how readily the
// material holds moss (rough stone and tiles more than planed wood, metal hardly at all);
// lum: the surface's brightness against its average (mortar lines and cracks are darker
// and moss starts there). Returns how much snow lies on it (to flatten its relief).
float wear_building(inout vec3 alb, inout float rough, vec3 p, vec3 n, float base_y, float age, float take, float lum) {
	vec4 lv = wear_levels(p);
	float frost = wear_frost(lv);
	float s_lvl = wear_snow(p);
	if (lv.x * take * age + s_lvl + lv.z * age + frost < 0.02) {
		return 0.0;
	}
	vec2 sh = wear_shelter(p, n);
	float open = sh.x;
	float outside = 1.0 - sh.y;
	if (outside <= 0.001) {
		return 0.0;
	}
	float up = smoothstep(0.35, 0.85, n.y);
	// Patterns run up walls and across roofs alike.
	vec2 q = mix(vec2(p.x + p.z, p.y), p.xz, up);
	float pat = vnoise(q * 0.9 + 3.1) * 0.65 + vnoise(q * 3.7 + 9.4) * 0.35;
	float fine = vnoise(q * 11.0 + 1.7);
	// The ground against an outside wall (or a lower roof it rises from): where the
	// shelter map, a metre out, sees open sky down to something below this point.
	vec2 out_dir = n.xz / max(length(n.xz), 1e-4);
	float below = wear_top(p.xz + out_dir * 1.0);
	float ground = below < p.y ? max(below, base_y) : base_y;
	float h = p.y - ground;
	float crev = clamp(1.0 - lum, 0.0, 1.0);

	// Damp darkens the foot of a wall in a wet place, and moss creeps up from it, along
	// the tops of ledges, sills and roof tiles, and on the north side, in patches.
	float m_lvl = lv.x * take * age;
	float foot = 1.0 - smoothstep(0.1, 0.25 + 0.8 * m_lvl, h + (pat - 0.5) * 0.5);
	alb *= 1.0 - 0.28 * smoothstep(0.4, 1.0, lv.x) * foot * age * outside;
	float north = smoothstep(-0.2, 0.9, -n.z) * (1.0 - up);
	float m = (foot * 1.1 + up * 0.9 * open + north * 0.35) * m_lvl * 0.9 + crev * 0.4 * m_lvl + (pat - 0.5) * 1.6 - 0.45;
	m = smoothstep(0.15, 0.55, m) * outside;
	vec3 mc = mix(vec3(0.04, 0.055, 0.02), vec3(0.085, 0.095, 0.035), smoothstep(0.4, 0.8, fine) * (0.4 + 0.6 * up));
	alb = mix(alb, mc * (0.75 + 0.5 * fine), m);
	rough = mix(rough, 1.0, m);

	// Dust settles on what faces up under the open sky and is splashed up the foot of
	// walls, filling the cracks first.
	float d = lv.z * wear_dust_now(p) * smoothstep(0.0, 0.25, age);
	float foot_d = 1.0 - smoothstep(0.2, 0.9, h + (pat - 0.5) * 0.4);
	float dm = (up * open * 0.9 + foot_d * 0.7 + crev * 0.35) * d * 2.0 + (pat - 0.5) * 0.7 - 0.15;
	dm = smoothstep(0.1, 0.65, dm) * outside;
	alb = mix(alb, WEAR_DUST * (0.85 + 0.3 * fine), dm * 0.85);
	rough = mix(rough, 0.97, dm);

	// Snow lies on what faces up under the open sky, thick on gentle pitches, in streaks
	// on steep ones, and drifts against the foot of walls.
	float snow = 0.0;
	if (s_lvl > 0.0) {
		// Thin cover first in patches (the surface showing through), closing over as it
		// deepens; it never paints a roof one flat white, the courses and ridges still
		// read through it.
		float cap = smoothstep(0.55 - 0.25 * s_lvl, 0.8 - 0.2 * s_lvl, n.y + (pat - 0.5) * 0.35) * open;
		float drift = (1.0 - smoothstep(0.05, 0.2 + 0.4 * s_lvl, h + (pat - 0.5) * 0.25)) * (1.0 - up);
		float cover = smoothstep(0.0, 0.6, s_lvl * 1.2 + (pat - 0.5) * 0.8 + (fine - 0.5) * 0.2);
		snow = clamp(max(cap, drift * 0.9 * outside) * cover, 0.0, 0.92);
		alb = mix(alb, WEAR_SNOW * (0.84 + 0.1 * fine + 0.12 * clamp(lum - 0.6, -0.5, 0.6)), snow);
		rough = mix(rough, 0.55, snow);
	}
	// Hoar frost: feathery white rime over everything outdoors on a cold morning, up
	// faces and edges first, the surface showing through it.
	float fm = frost * (0.12 + 0.4 * up + 0.3 * smoothstep(0.45, 0.9, vnoise(q * 26.0))) * outside * (1.0 - snow);
	alb = mix(alb, WEAR_FROST, clamp(fm, 0.0, 0.55));
	rough = mix(rough, 0.85, fm);
	return snow;
}
