shader_type spatial;
// Shared metal look (Metals): real metals' reflectance, never flat. Roughness drifts in
// smudges and fine scratches, forged iron carries hammer dimples, edges rounded by use
// are rubbed bright and smoother, grime settles dark and dull in patches, and rust,
// verdigris or paint sit on top as non-metal coats that chip at the edges. Mapped
// triplanar in the mesh's own space, so meshes need no UV work.
// Metal shine is reflection: nothing here emits.
render_mode diffuse_burley, specular_schlick_ggx;

// The metal's reflectance tint (sRGB), multiplied by the vertex colour.
uniform vec3 base_color : source_color = vec3(1.0);
uniform bool vertex_tint = true;
// 0..1: raise dark vertex colours to a real metal's reflectance (bare metal reflects
// 50-95% of light; a mid-grey colour reads as grey paint).
uniform float lift = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
// Smudges and polished spots.
uniform float rough_var = 0.25;
uniform float scratches = 0.3;
// Hammer dimples from the forge, in the normal.
uniform float hammer = 0.0;
// Brushed or rolled grain: stretched highlights.
uniform float brushed = 0.0;
// Edges rounded by use, rubbed bright.
uniform float wear = 0.4;
// Dark, dull dirt in patches.
uniform float grime = 0.3;
// Rust (or verdigris) coat: how much of the surface it covers.
uniform float rust = 0.0;
uniform vec3 rust_color : source_color = vec3(0.5, 0.27, 0.13);
// 1: the vertex colour is paint over the metal, chipped at edges and scuffs.
uniform float paint = 0.0;
uniform float paint_rough = 0.5;
// Repeats per metre in the mesh's space, and the radius (m) of an edge that counts as worn.
uniform float tri_scale = 6.0;
uniform float edge_size = 0.01;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scratch_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dimple_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Optional photo detail (greyscale, averaging 0.72) and its normal map.
uniform bool use_detail = false;
uniform float detail_scale = 0.33;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 obj_pos;
varying vec3 obj_n;

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / max(w.x + w.y + w.z, 1e-5);
}

float tri1(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).r * w.x + texture(t, p.xz).r * w.y + texture(t, p.xy).r * w.z;
}

// Triplanar normal map as a perturbation in the mesh's space (whiteout-style).
vec3 tri_bump(sampler2D t, vec3 p, vec3 w) {
	vec2 bx = texture(t, p.zy).xy * 2.0 - 1.0;
	vec2 by = texture(t, p.xz).xy * 2.0 - 1.0;
	vec2 bz = texture(t, p.xy).xy * 2.0 - 1.0;
	return vec3(0.0, bx.y, bx.x) * w.x + vec3(by.x, 0.0, by.y) * w.y + vec3(bz.x, bz.y, 0.0) * w.z;
}

void fragment() {
	vec3 n = normalize(obj_n);
	vec3 w = tri_w(n);
	vec3 p = obj_pos * tri_scale;
	float smudge = tri1(noise_tex, p * 0.35, w);
	float blot = tri1(noise_tex, p * 0.13 + vec3(7.3), w);
	float spots = tri1(noise_tex, p * 1.1 + vec3(3.1), w);
	// Brushed grain runs along the mesh's local Y and X; plain metal gets scattered scratches.
	vec3 ps = brushed > 0.0 ? p * vec3(0.25, 6.0, 0.25) : p * 1.7;
	float scr = tri1(scratch_tex, ps, w);

	// How rounded the surface is here (1/radius, from the change of normal per metre on
	// screen), so the edges of a bevel, a rim or a handle wear.
	float curv = length(fwidth(NORMAL)) / max(length(fwidth(VERTEX)), 1e-5);
	float edge = smoothstep(0.5, 1.5, curv * edge_size) * smoothstep(0.25, 0.6, spots + 0.2);

	vec3 vc = vertex_tint ? to_linear(COLOR.rgb) : vec3(1.0);
	vec3 metal_col = to_linear(base_color) * (paint > 0.5 ? vec3(1.0) : vc);
	float lum = dot(metal_col, vec3(0.2126, 0.7152, 0.0722));
	// Lift to a real metal's reflectance; very dark colours are holes and recesses, and
	// rough (tarnished, oxidised) metal stays darker.
	float target = 0.25 + 0.72 * sqrt(lum);
	float lw = lift * smoothstep(0.012, 0.05, lum) * (1.0 - 0.6 * smoothstep(0.55, 0.8, roughness));
	metal_col = mix(metal_col, min(metal_col * target / max(lum, 1e-4), vec3(1.0)), lw);

	float r = roughness + rough_var * (smudge - 0.5) + scratches * 0.35 * (scr - 0.45);
	vec3 col = metal_col * (0.92 + 0.16 * smudge);
	float metal = 1.0;
	vec3 bump = vec3(0.0);
	if (hammer > 0.0) {
		bump += tri_bump(dimple_tex, p * 0.8, w) * hammer;
	}
	if (use_detail) {
		vec3 pd = obj_pos * detail_scale;
		col *= tri1(detail_tex, pd, w) / 0.72;
		bump += tri_bump(detail_normal, pd, w) * 0.45;
	}

	// Worn edges: bare, brighter, smoother.
	float we = edge * wear;
	col = mix(col, min(metal_col * 1.12 + 0.02, vec3(1.0)), we);
	r = mix(r, r * 0.55, we);

	// Grime in patches, never on the rubbed edges.
	float g = grime * smoothstep(0.42, 0.78, blot) * (1.0 - edge);
	col *= mix(1.0, 0.55, g);
	r = mix(r, 0.85, g);
	metal = mix(metal, 0.45, g);

	// Paint over the metal, chipped at the edges and where scratched through.
	if (paint > 0.5) {
		float chip = clamp(we * 1.4 + smoothstep(0.78, 0.9, scr) * 0.6, 0.0, 1.0);
		float coat = 1.0 - chip;
		col = mix(col, vc * (0.94 + 0.1 * smudge) * mix(1.0, 0.75, g), coat);
		r = mix(r, paint_rough + 0.15 * (smudge - 0.5) + 0.3 * g, coat);
		metal = mix(metal, 0.0, coat);
	}

	// Rust (or verdigris): a non-metal coat in blotches, pitted, eaten back on worn edges.
	if (rust > 0.0) {
		float rm = smoothstep(1.0 - rust - 0.12, 1.0 - rust + 0.12, blot * 0.65 + spots * 0.35) * (1.0 - 0.7 * we);
		vec3 rc = to_linear(rust_color) * (0.7 + 0.6 * spots);
		col = mix(col, rc, rm);
		r = mix(r, 0.88 + 0.1 * spots, rm);
		metal = mix(metal, 0.0, rm);
		bump += tri_bump(dimple_tex, p * 3.1, w) * 0.5 * rm;
	}

	vec3 nb = normalize(n + bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * nb, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = clamp(r, 0.03, 1.0);
	if (brushed > 0.0) {
		ANISOTROPY = brushed * 0.6 * metal;
	}
}
