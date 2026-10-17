shader_type spatial;
// The loose locks that hang off a mane or tail (AnimalSkin._locks): each strip splits
// into a few strands of their own lengths, tapering to fine tips, with fibres running
// down them. Coloured like the hair they grow from, with the same per-animal shade as
// fur.gdshader, so a lock matches its own animal's mane.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 base : source_color = vec3(0.2, 0.15, 0.1);
uniform float vary = 0.12;
uniform float phases = 0.0;
uniform vec3 phase_dark = vec3(0.55, 0.52, 0.5);
uniform vec3 phase_warm = vec3(1.12, 0.98, 0.78);
instance uniform float seed = 0.0;

varying float lid;

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }

void vertex() {
	lid = UV2.x;
}

void fragment() {
	// Strands across the strip, each ending at its own length.
	float x = UV.x * 5.0;
	float si = floor(x);
	float fx = fract(x);
	float len = 0.5 + 0.5 * h1(si * 3.1 + lid * 17.0);
	float along = UV.y / len;
	float half_w = 0.5 * mix(1.0, 0.15, smoothstep(0.25, 1.0, along));
	if (along > 1.0 || abs(fx - 0.5) > half_w) discard;
	// The same shade of its kind as the rest of this animal's coat (fur.gdshader).
	float s = seed * 0.000173;
	vec3 c = base;
	float sh = h1(s + 4.1) * 2.0 - 1.0;
	sh = sign(sh) * mix(0.4, 1.0, abs(sh));
	c *= 1.0 + vary * sh * 1.4;
	float warm = h1(s + 5.3) * 2.0 - 1.0;
	c.r *= 1.0 + vary * 0.6 * warm;
	c.b *= 1.0 - vary * 0.6 * warm;
	c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))), vary * 1.6 * h1(s + 6.1));
	float ph = h1(s + 6.9);
	if (phases > 0.0 && ph < phases) c *= ph < phases * 0.5 ? phase_dark : phase_warm;
	// Fibres down each strand, each strand its own shade, sun-bleached toward the tips.
	float fib = sin((UV.x * 5.0 + h1(si + lid) * 0.3) * 6.2832 * 7.0) * 0.5 + 0.5;
	float ff = 1.0 - smoothstep(0.2, 0.6, fwidth(UV.x) * 35.0);
	c *= (0.85 + 0.3 * h1(si * 7.7 + lid * 3.0)) * (1.0 + (fib - 0.5) * 0.25 * ff);
	c *= 1.0 + 0.15 * along;
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	// Lit like the hair it grows from on both faces.
	if (!FRONT_FACING) NORMAL = -NORMAL;
	ROUGHNESS = 0.6;
	SPECULAR = 0.5;
	RIM = 0.3;
	RIM_TINT = 0.7;
	BACKLIGHT = c * 0.25;
}
