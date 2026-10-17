shader_type spatial;
// The loose locks that hang off a mane or tail (AnimalSkin._locks): each strip ends
// in two pointed clumps of their own lengths, lighter toward the ends, with fibres running
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
varying vec3 strand_dir;

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }

void vertex() {
	lid = UV2.x;
}

void fragment() {
	// The lock stays whole down most of its length and ends in two tapered clumps of
	// their own lengths, each drawing to a point, instead of a comb of thin strands.
	// Where a clump is finer than a pixel the strip shows as one tapered lock, and its
	// edges are antialiased through alpha to coverage.
	float x = UV.x * 2.0 + sin(UV.y * 7.0 + lid * 40.0) * 0.12 * UV.y;
	float si = floor(x);
	float fx = fract(x);
	float fw = max(fwidth(x), 1e-4);
	float fine = 1.0 - smoothstep(0.25, 0.6, fw);
	float split = fine * smoothstep(0.55, 0.85, UV.y);
	float len = mix(0.88, 0.8 + 0.2 * h1(si * 3.1 + lid * 17.0), fine);
	float along = UV.y / len;
	// Clumps narrow to a point over their last third.
	float cw = 0.5 * mix(1.0, 0.08, smoothstep(0.6, 1.0, along));
	float strand = smoothstep(-fw, fw * 1.5, cw - abs(fx - 0.5));
	// Soft edges: coverage thins out over the outer part of the lock instead of a cut.
	float ld = 0.5 * mix(1.0, 0.3, smoothstep(0.4, 1.0, along)) - abs(UV.x - 0.5);
	float lock = smoothstep(-max(fwidth(UV.x), 1e-4), 0.16, ld);
	float tip = clamp((len - UV.y) / max(fwidth(UV.y), 1e-4) + 0.5, 0.0, 1.0);
	ALPHA = mix(lock, strand, split) * tip;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(2.0, 1.0) * 32.0;
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
	// The ends are lighter, so the fringe reads as fine hair, not dark lines.
	float fib = sin((UV.x * 2.0 + h1(si + lid) * 0.3) * 6.2832 * 10.0) * 0.5 + 0.5;
	float ff = 1.0 - smoothstep(0.1, 0.4, fw * 10.0);
	c *= (1.0 + (h1(si * 7.7 + lid * 3.0) - 0.5) * 0.08 * split) * (1.0 + (fib - 0.5) * 0.06 * ff);
	// Darker near the root, where it lies under the rest of the fall, to meet the tail it hangs from.
	c *= mix(0.78, 1.0, smoothstep(0.0, 0.6, along));
	c = mix(c, c * 1.15 + vec3(0.012), smoothstep(0.6, 1.0, along));
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	// Lit as hair: by the direction the lock runs (its tangent), not the way its root
	// faces, so locks rooted all round the tail shade alike instead of light and dark
	// by turns.
	strand_dir = normalize(TANGENT);
	ROUGHNESS = 0.68;
	SPECULAR = 0.5;
}

// Kajiya-Kay hair: a strand is lit by how square the light falls across it, with a
// little of the root's facing kept for form. The sun's shadow leaves a lock a quarter lit,
// since thin cards shadowing one another would otherwise stripe it like a row of cards.
// Other lights fall off as usual.
void light() {
	float tl = dot(strand_dir, LIGHT);
	float across = sqrt(max(1.0 - tl * tl, 0.0));
	float ndl = dot(NORMAL, LIGHT);
	float shade = across * mix(0.75, 1.0, clamp(ndl * 0.5 + 0.5, 0.0, 1.0));
	float att = LIGHT_IS_DIRECTIONAL ? mix(0.25, 1.0, ATTENUATION) : ATTENUATION;
	DIFFUSE_LIGHT += shade * 0.8 * att * LIGHT_COLOR / PI;
}
