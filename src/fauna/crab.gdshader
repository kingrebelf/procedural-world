shader_type spatial;
// Crabs and crayfish (FishKit). INSTANCE_CUSTOM.rgb is the shell colour (sRGB), .a the
// walk phase in turns (run on by AquaticLife as it walks). Legs are COLOR.a 1, with their
// own step phase in COLOR.r and how far out along the leg in UV.y; the shell's COLOR.r
// darkens it (eyes are near black).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying float leg;
varying float dark;
varying vec3 lp;
varying vec3 shell;

void vertex() {
	leg = COLOR.a;
	dark = COLOR.a > 0.5 ? 0.85 : COLOR.r;
	lp = VERTEX;
	shell = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
	if (COLOR.a > 0.5) {
		// Each leg lifts and swings in turn: the far end most.
		float ph = TAU * (INSTANCE_CUSTOM.a + COLOR.r);
		float reach = UV.y;
		VERTEX.y += max(sin(ph), 0.0) * 0.06 * reach;
		VERTEX.z += cos(ph) * 0.05 * reach;
	}
}

void fragment() {
	// Darker on top, paler underneath and toward the leg tips; a mottle over the shell.
	float mottle = 0.85 + 0.15 * sin(lp.x * 60.0) * sin(lp.z * 47.0 + lp.x * 13.0);
	vec3 col = shell * dark * mottle * mix(0.75, 1.15, smoothstep(0.12, 0.0, lp.y));
	if (leg > 0.5) {
		col = shell * mix(0.95, 1.3, UV.y);
	}
	ALBEDO = col;
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
}
