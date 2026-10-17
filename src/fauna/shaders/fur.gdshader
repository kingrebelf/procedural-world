shader_type spatial;
// Living skins for the kit animals (AnimalSkin): fur that lies in strands and clumps
// along the way it grows, with a soft sheen at the edges; bare skin on muzzles and
// noses, wet at the tip; ridged horn and hoof; glossy eyes. Every pattern is laid on
// the body at rest (its rest position rides in UV and UV2.x, so it stays put on a
// moving, skinned body), and each animal's own `seed` gives it its own markings:
// patches, dapples, socks, a blaze, how dark its back and how pale its belly are.
render_mode diffuse_burley, specular_schlick_ggx;

uniform int role = 0; // 0 fur, 1 long hair (manes, tails), 2 bare skin, 3 horn and hoof, 4 eye
uniform vec3 base : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 lo = vec3(-1.0); // the body's bounds at rest
uniform vec3 hi = vec3(1.0);
uniform float unit = 0.35; // metres per rest unit
uniform float strand = 0.004; // metres between hairs
uniform float clump = 0.02; // metres across a lock of fur
uniform float fur = 1.0; // how strongly the hair shows
uniform float coarse = 0.0; // bristles: sparse, contrasty hair
uniform float legs_y = 0.4; // where the legs meet the body, 0..1 of the height
uniform float back_y = 0.75; // the top of the back
uniform float belly = 0.25; // paler underneath
uniform float dorsal = 0.15; // darker along the back
uniform float stripe = 0.0; // a dark line down the spine
uniform float grizzle = 0.0; // banded, salt-and-pepper guard hairs
uniform float spots = 0.0; // chance of dapples or fawn spots
uniform vec3 spot_col : source_color = vec3(0.85, 0.8, 0.7);
uniform float spot_size = 0.05; // metres
uniform float patches = 0.0; // chance and extent of pied patches
uniform vec3 patch_col : source_color = vec3(0.9, 0.88, 0.84);
uniform float socks = 0.0; // chance of pale (or dark) lower legs
uniform vec3 sock_col : source_color = vec3(0.66, 0.63, 0.58);
uniform float blaze = 0.0; // chance of a pale streak down the face
uniform float vary = 0.12;
uniform float phases = 0.0; // chance of a colour phase: darker or tawnier than most
uniform vec3 phase_dark = vec3(0.55, 0.52, 0.5);
uniform vec3 phase_warm = vec3(1.12, 0.98, 0.78);
uniform vec3 other : source_color = vec3(0.5); // the coat this one meets
uniform float blend = 0.0; // 1: blend into `other` near the seam // how much one animal's coat differs from the next
uniform vec3 emit : source_color = vec3(0.0);
uniform float emit_e = 0.0;
instance uniform float seed = 0.0;

varying vec3 rest;
varying float seam; // 0 on a seam with another coat, 1 well away from it

float h1(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return n3(p) * 0.5 + n3(p * 2.03 + 1.7) * 0.28 + n3(p * 4.11 + 3.1) * 0.14 + n3(p * 8.3 + 5.3) * 0.08; }
float cells(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); float d = 8.0;
	for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 r = o + vec3(h3(i + o), h3(i + o + 7.1), h3(i + o + 13.7)) * 0.8 + 0.1 - f;
		d = min(d, dot(r, r));
	}
	return sqrt(d);
}

void vertex() {
	rest = vec3(UV, UV2.x);
	seam = UV2.y;
}

// Which way the hair lies at rest: back along the body and down its flanks, straight
// down the legs, back from the face.
vec3 flow(vec3 q, vec3 p) {
	float half_w = max((hi.x - lo.x) * 0.5, 0.001);
	float side = clamp(abs(p.x) / half_w, 0.0, 1.0);
	vec3 body = normalize(mix(vec3(0.0, -0.2, -1.0), vec3(sign(p.x) * 0.25, -1.0, -0.35), smoothstep(0.35, 0.95, side)));
	vec3 f = mix(vec3(0.0, -1.0, -0.12), body, smoothstep(legs_y - 0.06, legs_y + 0.04, q.y));
	if (role == 1) f = normalize(mix(vec3(sign(p.x) * 0.4, -1.0, -0.3), vec3(0.0, -1.0, 0.0), 0.5));
	return normalize(f);
}

// Bump from a height field (metres) through screen derivatives: no tangents needed, so
// it works on these UV-less, skinned meshes.
vec3 bump(vec3 n, vec3 v, float h) {
	vec3 dpx = dFdx(v), dpy = dFdy(v);
	float hx = dFdx(h), hy = dFdy(h);
	vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 g = sign(det) * (hx * r1 + hy * r2);
	return normalize(abs(det) * n - g);
}

void fragment() {
	vec3 p = rest;
	vec3 q = (p - lo) / max(hi - lo, vec3(0.0001));
	vec3 pm = p * unit;
	float px = length(fwidth(pm)); // metres a pixel covers here
	float s = seed * 0.000173;
	vec3 so = vec3(h1(s), h1(s + 1.3), h1(s + 2.7)) * 61.0;
	vec3 c = base;
	// Soft, ragged edges where two coats meet: both sides fade to the same mix.
	if (blend > 0.0 && role <= 1) {
		float n = fbm(pm * 9.0 + so) - 0.5;
		c = mix(base, other, 0.5 * (1.0 - smoothstep(0.0, 1.0, seam + n * 0.7)));
	}
	// This animal's own shade of its species' coat.
	// Pushed away from the average, so two animals side by side rarely match.
	float sh = h1(s + 4.1) * 2.0 - 1.0;
	sh = sign(sh) * mix(0.4, 1.0, abs(sh));
	c *= 1.0 + vary * sh * 1.4;
	float warm = h1(s + 5.3) * 2.0 - 1.0;
	c.r *= 1.0 + vary * 0.6 * warm;
	c.b *= 1.0 - vary * 0.6 * warm;
	c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))), vary * 1.6 * h1(s + 6.1));
	float ph = h1(s + 6.9);
	if (role <= 1 && phases > 0.0 && ph < phases) c *= ph < phases * 0.5 ? phase_dark : phase_warm;
	float h = 0.0;
	float rough = 0.88;
	float spec = 0.35;
	float rim = 0.0;
	float wet = 0.0;
	if (role <= 1) {
		float torso = smoothstep(legs_y - 0.03, legs_y + 0.06, q.y);
		float t = clamp((q.y - legs_y) / max(back_y - legs_y, 0.05), 0.0, 1.0);
		float mid = abs(p.x) / max((hi.x - lo.x) * 0.5, 0.001);
		// Counter-shading: a darker back, a paler belly, with some ragged edge.
		float edge = fbm(pm * 6.0 + so) - 0.5;
		// Every animal has its own coat: how dark its back, how pale its belly, broad
		// cloudy shading, and maybe a darker or paler face.
		float dor = dorsal * (0.4 + 1.2 * h1(s + 21.0));
		float bel = belly * (0.5 + h1(s + 22.0));
		c *= 1.0 + (fbm(pm * 0.8 + so * 0.5) - 0.5) * vary * 2.2;
		float face = smoothstep(0.84, 0.9, q.z) * smoothstep(back_y - 0.05, back_y + 0.05, q.y);
		float fpick = h1(s + 23.0);
		c *= mix(1.0, fpick < 0.25 ? 0.75 : (fpick > 0.8 ? 1.15 : 1.0), face);
		c *= 1.0 - dor * smoothstep(0.55, 1.0, t + edge * 0.15) * torso * (1.0 - 0.5 * mid);
		vec3 pale = mix(c, vec3(dot(c, vec3(0.33))) * 1.35 + 0.08, 0.6);
		// Some animals carry a darker saddle over the back.
		c *= 1.0 - 0.3 * step(0.55, h1(s + 24.0)) * smoothstep(0.55, 0.85, t + edge * 0.3) * torso * smoothstep(0.25, 0.4, q.z) * (1.0 - smoothstep(0.6, 0.72, q.z));
		c = mix(c, pale, bel * (1.0 - smoothstep(0.1, 0.4, t + edge * 0.2)) * torso);
		c *= 1.0 - stripe * (1.0 - smoothstep(0.04, 0.12, mid + edge * 0.04)) * smoothstep(0.7, 0.9, t) * 0.55;
		// Pied patches: big, ragged, different on every animal.
		float pick = h1(s + 7.7);
		if (patches > 0.0 && pick < patches * 1.4) {
			float n = fbm(pm * 2.2 + so * 0.37) + (fbm(pm * 7.0 + so) - 0.5) * 0.12;
			float amt = mix(0.62, 0.42, patches * h1(s + 8.1));
			c = mix(c, patch_col, smoothstep(amt, amt + 0.015, n));
		}
		// Dapples or fawn spots.
		if (spots > 0.0 && h1(s + 9.3) < spots) {
			float d = cells(pm / spot_size + so);
			float r = 0.22 + 0.12 * h1(s + 9.9);
			// On the back and flanks only, thinning out toward the belly.
			float body = smoothstep(0.35, 0.7, t) * (1.0 - smoothstep(0.66, 0.74, q.z)) * smoothstep(0.08, 0.2, q.z);
			float thin = step(0.35 + 0.4 * (1.0 - t), h3(floor(pm / spot_size + so) + 2.0));
			float sp = (1.0 - smoothstep(r, r + 0.1, d)) * torso * body * thin;
			c = mix(c, spot_col, sp * 0.7);
		}
		// Socks: each leg its own height, or none.
		if (socks > 0.0) {
			float leg = (p.x > 0.0 ? 1.0 : 0.0) + (q.z > 0.5 ? 2.0 : 0.0);
			if (h1(s + 11.0 + leg * 1.7) < socks) {
				float top = legs_y * (0.25 + 0.6 * h1(s + 12.0 + leg));
				c = mix(c, sock_col, 1.0 - smoothstep(top - 0.02, top + 0.03, q.y + edge * 0.05));
			}
		}
		// A blaze or star down the front of the face.
		if (blaze > 0.0 && h1(s + 13.0) < blaze) {
			float w = 0.06 + 0.1 * h1(s + 13.5);
			float face = smoothstep(0.86, 0.9, q.z) * smoothstep(0.68, 0.74, q.y);
			c = mix(c, vec3(0.7, 0.68, 0.63), face * (1.0 - smoothstep(w, w + 0.03, mid + edge * 0.05)));
		}
		// The hair itself: locks and single hairs, stretched the way they lie.
		vec3 f = flow(q, p);
		// Hair doesn't lie perfectly straight: whorls and partings.
		if (role == 0) f = normalize(f + (vec3(fbm(pm * 3.0 + so), fbm(pm * 3.0 + so + 9.1), fbm(pm * 3.0 + so + 4.7)) - 0.5) * 0.8);
		// Shorter hair on the legs and face.
		float short_hair = mix(0.6, 1.0, torso) * mix(1.0, 0.65, smoothstep(0.86, 0.92, q.z));
		vec3 a = normalize(cross(f, abs(f.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
		vec3 b = cross(f, a);
		vec3 sc = vec3(dot(pm, a), dot(pm, b), dot(pm, f));
		// Manes and tails hang in long, thick locks.
		float stretch = role == 1 ? 0.05 : 0.35;
		float ck = role == 1 ? clump * 2.5 : clump * short_hair;
		float sk = role == 1 ? strand * 3.0 : strand * 0.75 * short_hair;
		float cl = n3(sc * vec3(1.0, 1.0, stretch * 1.5) / ck + so);
		// Single hairs as short strokes along the flow: staggered cells, each one hair
		// with its own shade, in two crossing layers.
		float fi = 0.0;
		for (int layer = 0; layer < 2; layer++) {
			vec2 hp = layer == 0 ? vec2(sc.x, sc.z) : vec2(sc.y + 0.37 * sk, sc.z + 2.1 * sk);
			hp /= vec2(sk, sk * (role == 1 ? 14.0 : 5.0));
			float col_i = floor(hp.x);
			hp.y += h1(col_i + float(layer) * 17.0 + so.x);
			vec2 cell = floor(hp);
			vec2 fr = fract(hp);
			float rn = h3(vec3(cell, float(layer)) + so);
			float off = 0.5 + (rn - 0.5) * 0.4;
			float stroke = (1.0 - smoothstep(0.12, 0.38, abs(fr.x - off))) * smoothstep(0.0, 0.25, fr.y) * (1.0 - smoothstep(0.75, 1.0, fr.y));
			fi = max(fi, stroke * (0.55 + 0.45 * rn));
		}
		float fc = 1.0 - smoothstep(ck * 0.4, ck * 1.6, px);
		float ff = 1.0 - smoothstep(sk * 0.4, sk * 1.6, px);
		fi = mix(fi, smoothstep(0.35, 0.75, fi), coarse);
		float hv = (cl - 0.5) * fc * 0.1 + (fi - 0.45) * ff * (0.7 + coarse * 0.4);
		c *= 1.0 + hv * fur * (0.75 + coarse * 0.5);
		// Dark hair still catches the light along each strand.
		c += vec3(0.035) * max(hv, 0.0) * fur * (role == 1 ? 1.2 : 0.6);
		// Guard hairs banded pale and dark: grizzled wolves, agouti hares.
		if (grizzle > 0.0) {
			float g = n3(sc * vec3(1.0, 1.0, 0.5) / (strand * 1.6) + so * 3.0);
			float gm = mix(0.5, g, 1.0 - smoothstep(strand * 0.6, strand * 2.5, px));
			c *= 1.0 + (gm - 0.5) * grizzle * 0.9;
		}
		h = (cl * fc * 0.25 + fi * ff * 0.5) * clump * 0.08 * fur;
		rim = 0.3 * fur;
		rough = role == 1 ? 0.62 : 0.9 - coarse * 0.08;
		spec = role == 1 ? 0.5 : 0.3;
	} else if (role == 2) {
		// Bare skin: fine creases and pores, wet and dark at the nose tip.
		float n = fbm(pm * 160.0 + so);
		c *= 0.9 + 0.2 * fbm(pm * 30.0 + so);
		h = n * 0.0006;
		wet = smoothstep(0.93, 0.99, q.z);
		rough = mix(0.55, 0.2, wet);
		spec = 0.45;
	} else if (role == 3) {
		// Horn and hoof: growth rings and lengthwise grain.
		float ring = sin(pm.y * 900.0 + fbm(pm * 40.0) * 6.0) * 0.5 + 0.5;
		float grain = fbm(vec3(pm.x * 120.0, pm.y * 12.0, pm.z * 120.0) + so);
		c *= (0.82 + 0.3 * grain) * 0.7;
		h = (ring * 0.4 + grain * 0.6) * 0.0008;
		rough = 0.5;
		spec = 0.4;
	} else {
		rough = 0.04;
		spec = 0.8;
	}
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (role == 4) {
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.03;
	}
	if (h != 0.0) NORMAL = bump(NORMAL, VERTEX, h);
	RIM = rim;
	RIM_TINT = 0.7;
	BACKLIGHT = role <= 2 ? c * 0.12 : vec3(0.0);
	EMISSION = emit * emit_e;
}
