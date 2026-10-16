shader_type spatial;
// Leaves and needles: alpha-scissored cards (or the opaque leaf core when is_core) that
// sway with the world wind. Displacement grows with height above the mesh origin, so
// trunks stay planted while crowns move; the phase comes from the instance position so
// neighbouring trees never move in lockstep.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_dir;
global uniform float wind_strength;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 albedo : source_color = vec3(1.0);
uniform vec3 back : source_color = vec3(0.3, 0.35, 0.12);
uniform bool is_core = false;
uniform float sway = 1.0;

varying vec3 inst_col;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = dot(origin.xz, vec2(0.13, 0.17));
	float t = TIME;
	float ws = wind_strength;
	// Slow whole-crown lean plus faster leaf flutter.
	float lean = (sin(t * 0.7 + phase) * 0.5 + 0.6) * ws;
	float flutter = sin(t * (3.0 + ws * 4.0) + VERTEX.x * 2.1 + VERTEX.z * 1.7 + phase * 3.0) * 0.08 * (0.3 + ws);
	float k = h * h * 0.006 * sway;
	vec3 wl = (inverse(MODEL_MATRIX) * vec4(wind_dir.x, 0.0, wind_dir.y, 0.0)).xyz;
	vec2 wd = normalize(wl.xz + vec2(0.0001));
	VERTEX.xz += wd * k * lean * 3.0;
	VERTEX += NORMAL * flutter * min(h * 0.3, 1.0) * sway;
	inst_col = COLOR.rgb;
}

void fragment() {
	vec4 tex = is_core ? vec4(0.55, 0.62, 0.5, 1.0) : texture(albedo_tex, UV);
	if (!is_core && tex.a < 0.45) {
		discard;
	}
	ALBEDO = tex.rgb * albedo * inst_col;
	// Bend normals toward the sky: cards facing the ground otherwise render near black.
	vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up_v, 0.55));
	ROUGHNESS = 0.8;
	SPECULAR = 0.35;
	BACKLIGHT = back * inst_col * 1.4;
}
