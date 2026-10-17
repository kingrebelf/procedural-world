shader_type spatial;
// Leaves and needles: alpha-scissored cards (or the opaque leaf core when is_core) that
// sway with the world wind. Displacement grows with height above the mesh origin, so
// trunks stay planted while crowns move; the phase comes from the instance position so
// neighbouring trees never move in lockstep.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Repeats of the leaf texture across a card: >1 makes individual leaves smaller.
uniform float uv_scale = 1.0;
uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 back : source_color = vec3(0.3, 0.35, 0.12);
uniform bool is_core = false;
uniform float sway = 1.0;
// RealTree crowns: vertex normals point out of the crown volume. Godot flips a back
// face's normal before the fragment runs, which would light half the cards from inside,
// so the crown normal is passed through unflipped instead.
uniform bool crown_normals = false;
uniform float alpha_cut = 0.45;

varying vec3 inst_col;
varying vec3 crown_n;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float t = wind_time; // the wind's own clock, so a change in wind never makes leaves jump
	float ws = wind_strength;
	// Slow whole-crown lean plus faster leaf flutter, and the same rolling gust waves the
	// grass shows.
	float wave = smoothstep(0.2, 1.0, sin(dot(origin.xz, wind_dir) * 0.045 - t * 0.55 + sin(origin.x * 0.013) * 1.5));
	float lean = (sin(t * 0.6 + phase) * 0.4 + 0.6 + wave * 0.5) * ws;
	float flutter = sin(t * 3.5 + VERTEX.x * 2.1 + VERTEX.z * 1.7 + phase * 3.0) * 0.07 * (0.3 + ws);
	// Bend grows with height but is capped, so tall trees sway rather than tilt over.
	float k = min(h * h * 0.006, 0.6) * sway;
	vec3 wl = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	vec2 wd = normalize(wl.xz + vec2(0.0001));
	VERTEX.xz += wd * k * lean * 1.2;
	// Flutter is a leaf's own trembling: it doesn't grow with a small plant's extra bend
	// (multiplying it by that made bushes thrash as if in a gale).
	VERTEX += NORMAL * flutter * min(h * 0.3, 1.0) * min(sway, 1.0);
	// Vertex and instance colours are authored as sRGB; shading happens in linear space.
	inst_col = pow(COLOR.rgb, vec3(2.2));
	crown_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 tex = is_core ? vec4(0.55, 0.62, 0.5, 1.0) : texture(albedo_tex, uv);
	// Thin needles and leaf tips average away in distant mip levels; raising alpha with the
	// mip level keeps far cards as full as near ones instead of breaking into speckles.
	vec2 px = uv * vec2(textureSize(albedo_tex, 0));
	float lod = max(0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))), 0.0);
	tex.a *= 1.0 + lod * 0.28;
	if (!is_core && tex.a < alpha_cut) {
		discard;
	}
	ALBEDO = tex.rgb * albedo * inst_col;
	// Bend normals toward the sky: cards facing the ground otherwise render near black.
	vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	// The core's underside would otherwise go black in its own shadow.
	if (crown_normals) {
		NORMAL = normalize(mix(normalize(crown_n), up_v, 0.2));
	} else {
		NORMAL = normalize(mix(NORMAL, up_v, is_core ? 0.8 : 0.55));
	}
	ROUGHNESS = 0.8;
	SPECULAR = crown_normals ? 0.25 : 0.35;
	BACKLIGHT = back * inst_col * 1.4;
}
