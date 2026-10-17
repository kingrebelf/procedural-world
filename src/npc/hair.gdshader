shader_type spatial;
// Kit hair, eyebrows and beards drawn as strands (HairStrands): fine strands and looser
// clumps combed along each vertex's tangent, a highlight band running across them, roots
// darker than the ends. Shells (shell > 0) are the same mesh pushed out a little and cut
// to fewer, finer strands, so the outline breaks into fibres instead of a moulded edge.
// CUSTOM0 = rest position + tip factor, CUSTOM1 = rest combing direction (HairStrands);
// `strands` is set on meshes that carry them; others (eyebrows) keep the texture alone.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled, alpha_to_coverage;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
instance uniform vec4 hair_col : source_color = vec4(0.2, 0.14, 0.1, 1.0);
// 0 the base mesh, (0, 1] a shell this far out of `shell_depth` (m).
instance uniform float shell = 0.0;
instance uniform float shell_depth = 0.006;
// Thinning with age: 0 full, 1 the crown mostly bare.
instance uniform float thin = 0.0;
// The person's skin, for thinning hair seen from too far to resolve single strands.
instance uniform vec4 scalp_col : source_color = vec4(0.0);
instance uniform float strands = 0.0;
// Sparse hair (eyebrows): only the strands above this survive.
instance uniform float sparse = 0.0;
// Under a hat: hair above this rest height is hidden (HumanModel.cap_hair).
instance uniform float cap_y = 99.0;
// The base layer stands this far off the scalp (m), so the head can't push through it
// where the kit mesh hugs the skull (a parting, a buzz cut).
instance uniform float lift = 0.0;
// Beard style (BodyShape.beard): 1 stubble, 2 moustache, 3 goatee, 4 short, 5 full; the
// kit beard mesh covers the whole jaw and is cut down to the style.
instance uniform float beard = 0.0;

varying vec4 rest;
varying vec3 flow;

void vertex() {
	rest = CUSTOM0;
	flow = CUSTOM1.xyz;
	VERTEX += NORMAL * lift;
	if (shell > 0.0) {
		// Ends stand off further than roots.
		VERTEX += NORMAL * shell * shell_depth * (0.45 + 0.55 * CUSTOM0.w);
	}
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// How much of the kit beard mesh a style keeps at rest position `p` (1 keep, 0 cut);
// `e` shifts the edges so strands break them up.
float beard_mask(vec3 p, float style, float e) {
	if (style < 1.5 || style > 3.5) {
		return 1.0;
	}
	float ax = abs(p.x);
	float lip = step(1.612 + e, p.y) * step(p.y, 1.648 + e) * step(ax, 0.042 + e) * step(0.055, p.z);
	if (style < 2.5) {
		return lip;
	}
	float chin = step(1.556, p.y) * step(p.y, 1.618 + e) * step(ax, 0.03 + e) * step(0.045, p.z);
	return max(lip, chin);
}

// Coverage of a cut at `edge` through the pattern value `x`: 0..1 over about one pixel
// (`w` = how fast x changes on screen), so cut strand edges are antialiased (alpha to
// coverage under MSAA) instead of stair-stepped and sparkling.
float cut(float edge, float x, float w) {
	return clamp((x - edge) / max(w, 0.002) + 0.5, 0.0, 1.0);
}

void fragment() {
	// Position with the run along the strand squeezed out: noise in it streaks along the
	// combing direction. Its screen-space footprint says how fine a strand can be drawn;
	// only the size across the strands counts, so hair seen edge-on keeps its strands.
	// Everything that takes derivatives is worked out here, before any branch that differs
	// from pixel to pixel.
	vec3 f = flow / max(length(flow), 1e-4);
	vec3 q = rest.xyz - f * dot(rest.xyz, f) * 0.985;
	vec3 dx = dFdx(rest.xyz);
	vec3 dy = dFdy(rest.xyz);
	float px = max(length(dx - f * dot(dx, f) * 0.985), length(dy - f * dot(dy, f) * 0.985));
	// Strands finer than a pixel fade to their average instead of sparkling.
	float hi = 1.0 - smoothstep(0.5, 1.3, px * 1000.0);
	float lo = 1.0 - smoothstep(0.5, 1.3, px * 420.0);
	float fine = mix(0.5, vnoise3(q * 420.0), lo) * 0.55 + mix(0.5, vnoise3(q * 1000.0), hi) * 0.45;
	fine = smoothstep(0.2, 0.8, fine);
	float clump = vnoise3(q * 140.0 + vec3(3.1));
	float wave = vnoise3(rest.xyz * 55.0);
	float s = fine * 0.75 + clump * 0.25;
	float tip = rest.w;
	// 1 while single strands are big enough to see, 0 once they are finer than a pixel.
	float near = smoothstep(0.35, 0.65, lo);
	// 1 only while the finest strands span a few pixels. Strands cut out of a surface
	// any smaller than that stair-step and sparkle (and flicker under TAA), so cut-outs
	// (shells, thinning) are kept for close looks; further off, strands are colour only.
	float close = smoothstep(0.55, 0.85, hi);
	float fs = fwidth(s);
	float ff = fwidth(fine);
	float cov = 1.0;
	if (shell > 0.0) {
		// Fewer, finer strands further out, and fewer near the roots; only for close looks
		// (`close`), further off the smooth base layer alone.
		float sc = s * (0.85 + 0.3 * clump);
		cov = cut(0.42 + shell * 0.38 - tip * 0.12, sc, fwidth(sc)) * close;
	}
	if (beard > 0.5 && beard < 1.5) {
		// Stubble: sparse fine dots close up; further off, a shadow on the skin.
		cov *= cut(0.78 * smoothstep(0.35, 0.65, hi), fine, ff);
	}
	// Thinning hair: the scalp shows between single strands, most at the crown. Cut by
	// the strand pattern alone (cut by the clumps it read as a patchy wig), and only while
	// strands are big enough to see; further off the scalp tints the hair.
	float bare = thin * (1.0 - tip) * 0.85;
	if (shell <= 0.0 && sparse <= 0.0 && bare > 0.0) {
		cov = cut(bare * close, fine, ff);
	}
	vec3 t = texture(tex, UV).rgb;
	float lum = clamp(dot(t, vec3(0.299, 0.587, 0.114)) / 0.56, 0.4, 1.6);
	// The cut itself stays where it was (half coverage); under MSAA the inner half of
	// each strand's edge is feathered by alpha to coverage.
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (strands < 0.5 || dot(flow, flow) < 0.25) {
		// Where the combing direction cancels out (a few odd triangles) the plain look,
		// but still cut to the beard style and the hat.
		if (beard_mask(rest.xyz, beard, 0.0) < 0.5 || (beard > 0.5 && beard < 1.5) || rest.y > cap_y || shell > 0.0) {
			discard;
		}
		ALBEDO = hair_col.rgb * lum;
		ALPHA = 1.0;
		NORMAL_MAP = texture(nrm, UV).rgb;
		ROUGHNESS = 0.55;
		SPECULAR = 0.4;
	} else {
		if (rest.y > cap_y) {
			discard;
		}
		// Regions of the beard mesh (rest metres: mouth about 1.63 up, face forward +z).
		cov *= beard_mask(rest.xyz, beard, (s - 0.5) * 0.01);
		if (shell > 0.0) {
			// Seen edge-on, a shell is a smear of cut strands over the sky: let the outer
			// ones thin out at the outline, so it is a few loose fibres, not a fuzz.
			cov *= mix(1.0, smoothstep(0.05, 0.45, abs(dot(NORMAL, VIEW))), shell);
		}
		ALPHA = cov;
		// Roots and the inner layers in shadow; ends catch the light.
		float ao = mix(0.55, 1.0, clamp(shell * 0.8 + tip * 0.35 + 0.2, 0.0, 1.0));
		vec3 col = hair_col.rgb * (0.5 + 0.8 * s) * (0.9 + 0.2 * wave) * mix(1.0, lum, 0.2) * ao;
		if (scalp_col.a > 0.0) {
			float skin = bare * 0.6 * (1.0 - close);
			if (beard > 0.5 && beard < 1.5) {
				skin = 0.4 + 0.35 * (1.0 - smoothstep(0.35, 0.65, hi));
			} else if (sparse > 0.0) {
				// Brows: never cut (cut-out hairs that small read as a stipple of dots);
				// the hairs are dark streaks over the skin, fewer toward the tail, and
				// further off they blend to an even soft tint.
				float hair = mix(0.55, smoothstep(0.3, 0.75, s), near) * (1.0 - 0.55 * smoothstep(0.6, 1.0, tip));
				skin = 1.0 - hair * (1.0 - sparse * 0.6);
			}
			col = mix(col, scalp_col.rgb, skin);
		}
		ALBEDO = col;
		// Each strand a little round: the normal tips across it with the strand pattern.
		NORMAL = normalize(NORMAL + BINORMAL * (fine - 0.5) * 0.6);
		NORMAL_MAP = texture(nrm, UV).rgb;
		NORMAL_MAP_DEPTH = 0.2;
		ROUGHNESS = 0.42;
		SPECULAR = 0.38;
		// The highlight stretches across the strands, the way hair shines.
		ANISOTROPY = 0.8;
		ANISOTROPY_FLOW = vec2(0.0, 1.0);
		BACKLIGHT = hair_col.rgb * 0.25;
	}
}
