shader_type spatial;
render_mode specular_schlick_ggx;

// Every lit display in the sci-fi rooms, the bunkers' notice panels and the boats'
// instruments, drawn in code (ScreenLook builds the faces). Nothing is a texture: text is
// a 5x6 pixel font and a small vocabulary of station words, so a log line reads
// "14:02:33 [OK] GRID SYNC 42" rather than noise; graphs, gauges, radar sweeps, contour
// maps and falling glyph rain are all functions of UV and TIME.
//
// UV spans the face (u right, v down). UV2.x is the kind (integer part, ScreenLook.KIND)
// plus a seed for the face (fraction); UV2.y the face's width over its height. COLOR.rgb
// is the accent of the room or vessel, COLOR.a the face's height / 4 m (text keeps a
// real size). Each room's header carries its site's name (title_a/b, 16 characters of
// 6 bits, four per float: ScreenLook.pack). Text fades to its average brightness where
// a glyph is smaller than a pixel, so far screens read as lines of text, not shimmer.

uniform float energy = 0.8; // emission; under the glow threshold on human worlds (Materials.set_screen_clock)
uniform float game_hours = 12.0; // the world's clock, so logs and clocks show the in-game time
instance uniform vec4 title_a = vec4(0.0);
instance uniform vec4 title_b = vec4(0.0);
instance uniform float power = 1.0;

varying flat vec3 v_acc;
varying flat float v_kind;
varying flat float v_seed;
varying flat float v_asp;
varying flat float v_h;
varying flat float v_hdg;

// " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.:-/><_=+#%[]()*!?,|{}'$@", bit row * 5 + col.
const uint FONT[62] = {0u, 488232750u, 474091716u, 1042424366u, 520632847u, 277850504u, 520633407u, 488160302u, 69345823u, 488159790u, 487540270u, 589284910u, 521715247u, 1007715390u, 521717295u, 1041284159u, 34651199u, 488170558u, 588840497u, 474091662u, 488129052u, 588553521u, 1041269793u, 588830577u, 589092465u, 488162862u, 35112495u, 748340782u, 580372015u, 520632382u, 138547359u, 488162865u, 145278513u, 599442993u, 581046609u, 138547537u, 1041305887u, 134217728u, 4194432u, 31744u, 1118480u, 2236546u, 8521864u, 1040187392u, 1016800u, 162944u, 11512810u, 27070835u, 471926862u, 478421262u, 136382532u, 142876932u, 703136u, 134353028u, 134357550u, 71303168u, 138547332u, 404819020u, 210002182u, 132u, 150616254u, 228259374u};
const int G_DOT = 37;
const int G_COLON = 38;
const int G_SLASH = 40;
const int G_LBR = 48;
const int G_RBR = 49;

// Words, five 6-bit glyphs each: 0-47 station, 48-59 code keywords, 60-75 vessel,
// 76-79 log tags (OK WARN ERR INFO).
const uint WORDS[80] = {121053u, 7943699u, 3716694u, 3749649u, 473831002u, 6337373u, 3991128u, 5604566u, 4048461u, 3007182u, 4555994u, 3508445u, 115915u, 6910942u, 255165392u, 7444046u, 5559894u, 6354585u, 5813213u, 6911962u, 5858253u, 5604044u, 590177244u, 258053902u, 259651164u, 7963616u, 99024u, 120780u, 95191u, 128653u, 131800u, 492664397u, 71254u, 7403359u, 7968348u, 4843467u, 144341u, 107223u, 4056285u, 4032100u, 255375134u, 259569421u, 473817825u, 9041296u, 6910678u, 7980634u, 4055761u, 8713997u, 1552u, 123862u, 1043u, 4052367u, 116304u, 257504417u, 123868u, 6919766u, 58891u, 124504u, 124887u, 115424u, 5859282u, 70546u, 309961678u, 3769569u, 5845725u, 494507541u, 6120402u, 256206028u, 95900u, 5830608u, 3990750u, 9279436u, 424469212u, 510702733u, 472745565u, 6108958u, 1369u, 6406881u, 116495u, 6620691u};
const int WLEN[80] = {3, 4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 4, 3, 4, 5, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 4, 3, 3, 3, 3, 3, 5, 3, 4, 4, 4, 3, 3, 4, 4, 5, 5, 5, 4, 4, 4, 4, 4, 2, 3, 2, 4, 3, 5, 3, 4, 3, 3, 3, 3, 4, 3, 5, 4, 4, 5, 4, 5, 3, 4, 4, 4, 5, 5, 5, 4, 2, 4, 3, 4};

// Fixed labels: TERMINAL 0, BULLETIN 8, NOTICE 16, SONAR 22, NEWS 27.
const int LABELS[31] = {30, 15, 28, 23, 19, 24, 11, 22, 12, 31, 22, 22, 15, 30, 19, 24, 24, 25, 30, 19, 13, 15, 29, 25, 24, 11, 28, 24, 15, 33, 29};

// Line patterns, eight tokens each. 1 word, 3 number, 4 four hex digits, 5 clock,
// 6 log tag, 7 two hex digits, 8 comment, 100+g a glyph set tight, 200+g a glyph
// between spaces, 301-303 a keyword (assign / condition / flow).
const int PAT[96] = {
	5, 6, 1, 1, 3, 0, 0, 0,
	5, 6, 1, 137, 1, 244, 3, 0,
	5, 6, 1, 1, 1, 0, 0, 0,
	5, 6, 1, 241, 1, 3, 0, 0,
	301, 1, 244, 1, 150, 3, 151, 0,
	302, 1, 241, 3, 257, 0, 0, 0,
	158, 0, 0, 0, 0, 0, 0, 0,
	1, 137, 1, 150, 1, 151, 0, 0,
	303, 1, 0, 0, 0, 0, 0, 0,
	8, 1, 1, 1, 0, 0, 0, 0,
	4, 138, 7, 7, 7, 7, 7, 7,
	1, 1, 1, 3, 1, 1, 1, 1};

struct Pal {
	vec3 bg;
	vec3 dim;
	vec3 txt;
	vec3 key;
	vec3 warn;
};

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_acc = COLOR.rgb;
	v_h = max(COLOR.a * 4.0, 0.04);
	v_kind = floor(UV2.x + 0.001);
	vec3 o = MODEL_MATRIX[3].xyz;
	v_seed = fract(fract(UV2.x) + fract(dot(floor(o * 4.0), vec3(0.1031, 0.11369, 0.13787))) * 7.13);
	v_asp = max(UV2.y, 0.1);
	vec3 fwd = (MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz;
	v_hdg = atan(fwd.x, -fwd.z);
}

// 1 where glyph g covers point f (0..1 over its cell: a 6x8 cell round the 5x6 glyph).
float glyph(int g, vec2 f) {
	if (g <= 0 || g > 61) {
		return 0.0;
	}
	ivec2 px = ivec2(floor(f * vec2(6.0, 8.0)));
	int gx = px.x;
	int gy = px.y - 1;
	if (gx < 0 || gx > 4 || gy < 0 || gy > 5) {
		return 0.0;
	}
	return float((FONT[g] >> uint(gy * 5 + gx)) & 1u);
}

int wchar(int w, int k) {
	return int((WORDS[w] >> uint(6 * k)) & 63u);
}

int digit(int d) {
	return 1 + d;
}

int hexd(int d) {
	return d < 10 ? 1 + d : 11 + d - 10;
}

// Glyph at column c of generated line n (age: lines older than the newest). tone: 0 dim,
// 1 text, 2 key, 3 warning; len: the line's length in characters.
int line_char(int mode, float seed, float n, float age, int c, int vocab, out int tone, out int len) {
	float hl = h21(vec2(n, seed * 97.0));
	int pat = mode == 0 ? int(hl * 3.999) : mode == 1 ? 4 + int(hl * 5.999) : mode == 2 ? 10 : 11;
	int pos = (mode == 1 && pat != 6) ? int(h11(n * 1.7 + seed * 13.0) * 2.999) * 2 : 0;
	int g = 0;
	tone = 1;
	bool comment = false;
	bool found = false;
	bool prev_tight = true;
	for (int i = 0; i < 8; i++) {
		int tk = PAT[pat * 8 + i];
		if (tk == 0) {
			break;
		}
		bool tight = tk >= 100 && tk < 200;
		if (!tight && !prev_tight) {
			pos += 1;
		}
		float h = h21(vec2(n * 7.0 + float(i) * 3.1, seed * 131.0 + float(mode)));
		int tl = 1;
		int tt = 1;
		int w = 0;
		if (tk == 1) {
			// Vessels mix their own words with the station's.
			w = vocab == 1 && h < 0.6 ? 60 + int(fract(h * 7.3) * 15.999) : int(fract(h * 3.7) * 47.999);
			tl = WLEN[w];
		} else if (tk >= 301) {
			int grp = tk - 301;
			int pick = int(h * 2.999);
			w = grp == 0 ? (pick == 0 ? 49 : pick == 1 ? 59 : 58) : grp == 1 ? (pick == 0 ? 50 : pick == 1 ? 53 : 52) : (pick == 0 ? 54 : pick == 1 ? 55 : 48);
			tl = WLEN[w];
			tt = 2;
		} else if (tk == 3) {
			tl = 1 + int(h * 2.999);
		} else if (tk == 4) {
			tl = 4;
			tt = 0;
		} else if (tk == 5) {
			tl = 8;
			tt = 0;
		} else if (tk == 6) {
			w = h < 0.72 ? 76 : h < 0.86 ? 79 : h < 0.96 ? 77 : 78;
			tl = WLEN[w] + 2;
			tt = w == 77 || w == 78 ? 3 : 2;
		} else if (tk == 7) {
			tl = 2;
		} else if (tk == 8) {
			tl = 2;
			comment = true;
		}
		if (!found && c >= pos && c < pos + tl) {
			found = true;
			int k = c - pos;
			tone = comment ? 0 : tt;
			if (tk == 1 || tk >= 301) {
				g = wchar(w, k);
			} else if (tk == 3) {
				int d = int(h21(vec2(h * 91.0, float(k))) * 9.999);
				g = digit(k == 0 && tl > 1 ? max(d, 1) : d);
			} else if (tk == 4 || tk == 7) {
				g = hexd(int(h21(vec2(h * 57.0, float(k))) * 15.999));
			} else if (tk == 5) {
				// The newest line is stamped now; older ones a little earlier each.
				float secs = mod(game_hours * 3600.0 - age * (23.0 + seed * 40.0), 86400.0);
				int hh = int(secs / 3600.0);
				int mm = int(mod(secs / 60.0, 60.0));
				int ss = int(mod(secs, 60.0));
				int v = k < 2 ? hh : k < 5 ? mm : ss;
				int kk = k < 2 ? k : k < 5 ? k - 3 : k - 6;
				g = (k == 2 || k == 5) ? G_COLON : digit(kk == 0 ? v / 10 : v % 10);
			} else if (tk == 6) {
				g = k == 0 ? G_LBR : k == tl - 1 ? G_RBR : wchar(w, k - 1);
			} else if (tk == 8) {
				g = G_SLASH;
			} else {
				g = tk % 100;
			}
		}
		pos += tl;
		prev_tight = tight;
	}
	len = pos;
	return g;
}

vec3 tone_col(int tone, Pal P) {
	return tone == 0 ? P.dim : tone == 2 ? P.key : tone == 3 ? P.warn : P.txt;
}

// Generated text over a block (q 0..1 across it) of `rows` lines and `cols` columns,
// scrolling `rate` lines a second with the newest typing itself out (rate 0: a still
// page that turns every `rate`-less 14 s). cpp: cells per screen pixel.
vec3 text_area(vec2 q, float rows, float cols, int mode, float seed, float rate, int vocab, Pal P, float cpp) {
	vec2 cell = q * vec2(cols, rows);
	vec2 ci = floor(cell);
	vec2 cf = fract(cell);
	float t = rate > 0.0 ? TIME * rate + seed * 50.0 : floor(TIME / 14.0 + seed * 9.0) * 37.0;
	float top = floor(t);
	float n = ci.y + top;
	float age = rows - 1.0 - ci.y;
	float lod = smoothstep(0.3, 0.75, cpp);
	if (lod > 0.98) {
		// Far off: a line's worth of light where its text would be.
		float est = 6.0 + h21(vec2(n, seed * 97.0)) * cols * 0.7;
		return P.txt * 0.3 * step(ci.x, est) * step(0.12, cf.y) * step(cf.y, 0.88);
	}
	int tone;
	int len;
	int g = line_char(mode, seed, n, age, int(ci.x), vocab, tone, len);
	bool newest = rate > 0.0 && age < 0.5;
	float typed = fract(t) * float(len) * 1.6;
	if (newest && ci.x >= typed) {
		g = 0;
	}
	float ink = mix(glyph(g, cf), g > 0 ? 0.36 : 0.0, lod);
	vec3 o = tone_col(tone, P) * ink;
	if (newest && abs(ci.x - floor(min(typed, float(len)))) < 0.5 && fract(TIME * 1.7) < 0.55) {
		o = P.txt * (step(0.1, cf.y) * step(cf.y, 0.9));
	}
	return o;
}

// Character k (0..31) of the room's name, as ScreenLook.pack stores it.
int title_char(int k) {
	if (k < 0 || k > 31) {
		return 0;
	}
	vec4 v = k < 16 ? title_a : title_b;
	int j = (k % 16) / 4;
	float f = j == 0 ? v.x : j == 1 ? v.y : j == 2 ? v.z : v.w;
	return (int(f + 0.5) >> (6 * (k % 4))) & 63;
}

bool has_title() {
	return title_a.x > 0.5;
}

int label_char(int start, int n, int k) {
	return k >= 0 && k < n ? LABELS[start + k] : 0;
}

// Ink of a single text row filling band q (0..1), `cols` characters wide: the room's
// name when it has one, else the label.
float title_row(vec2 q, float cols, int lab, int lab_n, float cpp) {
	vec2 cell = vec2(q.x * cols, q.y);
	int k = int(floor(cell.x));
	int g = has_title() ? title_char(k) : label_char(lab, lab_n, k);
	return mix(glyph(g, vec2(fract(cell.x), cell.y)), g > 0 ? 0.36 : 0.0, smoothstep(0.3, 0.75, cpp));
}

float clock_row(vec2 q, float cpp) {
	// "HH:MM" right-aligned in five cells.
	int k = int(floor(q.x * 5.0));
	float secs = mod(game_hours * 3600.0, 86400.0);
	int hh = int(secs / 3600.0);
	int mm = int(mod(secs / 60.0, 60.0));
	int g = k == 2 ? (fract(TIME) < 0.5 ? G_COLON : 0) : k < 2 ? digit(k == 0 ? hh / 10 : hh % 10) : digit(k == 3 ? mm / 10 : mm % 10);
	return mix(glyph(g, vec2(fract(q.x * 5.0), q.y)), 0.3, smoothstep(0.3, 0.75, cpp));
}

bool inr(vec2 p, vec4 r) {
	return p.x >= r.x && p.x < r.z && p.y >= r.y && p.y < r.w;
}

vec2 loc(vec2 p, vec4 r) {
	return (p - r.xy) / (r.zw - r.xy);
}

// A hairline round rect r, `px` thick (in u).
float frame(vec2 p, vec4 r, float px) {
	vec2 d = min(p - r.xy, r.zw - p);
	return inr(p, r) ? 1.0 - step(px, min(d.x, d.y / v_asp)) : 0.0;
}

// Columns that fit `rows` lines in a block ext (UV) of this face.
float cols_for(float rows, vec2 ext) {
	return max(4.0, floor(rows * ext.x * v_asp / ext.y / 0.75));
}

float wave(vec2 q, float t, float s, float px) {
	float y = 0.5 + 0.32 * (sin(q.x * 11.0 + t * 2.7 + s * 6.0) * 0.55 + sin(q.x * 29.0 - t * 4.3 + s * 9.0) * 0.25
		+ sin(q.x * 4.0 + t * 0.9) * 0.2) * (0.6 + 0.4 * sin(t * 0.37 + s * 3.0));
	float grid = (fract(q.y * 4.0) < px * 4.0 || fract(q.x * 8.0) < 0.025) ? 0.18 : 0.0;
	return max(1.0 - smoothstep(px * 1.2, px * 3.0, abs(q.y - y) * 0.5), grid);
}

float bars(vec2 q, float t, float s, float n) {
	float bi = floor(q.x * n);
	float fx = fract(q.x * n);
	float hgt = 0.12 + 0.8 * vnoise(vec2(bi * 1.7 + s * 30.0, t * 1.3));
	float peak = 0.12 + 0.8 * vnoise(vec2(bi * 1.7 + s * 30.0, t * 1.3 - 0.4)) + 0.04;
	float y = 1.0 - q.y;
	float seg = step(0.25, fract(y * 18.0));
	float b = (fx > 0.12 && fx < 0.88 && y < hgt) ? seg * (0.55 + 0.45 * y) : 0.0;
	return max(b, (fx > 0.12 && fx < 0.88 && abs(y - max(peak, hgt)) < 0.02) ? 0.9 : 0.0);
}

// A ring gauge in a square block: fraction f of 270 degrees lit.
float gauge(vec2 q, float f, float px) {
	vec2 d = (q - 0.5) * vec2(1.0, 1.0);
	float r = length(d) * 2.0;
	float a = fract(atan(d.x, d.y) / 6.2832 + 0.5);
	float on = step(abs(a - 0.5), 0.375);
	float ring = step(0.68, r) * step(r, 0.9) * on;
	float lit = step((a - 0.125) / 0.75, f);
	float tick = step(0.94, r) * step(r, 1.0) * step(fract(a * 24.0), 0.12) * on;
	return ring * (lit > 0.5 ? 1.0 : 0.16) + tick * 0.5;
}

float radar(vec2 q, float t, float s, float px) {
	vec2 d = q - 0.5;
	float r = length(d) * 2.0;
	if (r > 1.0) {
		return 0.0;
	}
	float a = atan(d.x, -d.y);
	float sweep = fract((a - t * 1.6) / 6.2832);
	float trail = pow(1.0 - sweep, 6.0) * 0.6;
	float rings = step(fract(r * 4.0), px * 8.0) * 0.35 + step(0.985, r) * 0.6;
	float cross = (abs(d.x) < px || abs(d.y) < px) ? 0.25 : 0.0;
	float blip = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 bp = vec2(h11(fi * 3.1 + s * 17.0), h11(fi * 5.7 + s * 23.0)) * 1.3 - 0.65;
		bp *= 0.75;
		float ba = atan(bp.x, -bp.y);
		float since = fract((t * 1.6 - ba) / 6.2832);
		blip += (1.0 - smoothstep(0.02, 0.035, length(d - bp * 0.5))) * (1.0 - since);
	}
	return max(max(rings, cross), trail) + blip;
}

// Falling glyph rain: columns of characters each led by a bright head.
vec3 rain(vec2 q, float rows, float cols, float s, Pal P, float cpp) {
	vec2 cell = q * vec2(cols, rows);
	vec2 ci = floor(cell);
	float sp = 3.0 + h11(ci.x * 1.3 + s * 11.0) * 9.0;
	float len = 6.0 + h11(ci.x * 2.1 + s) * 14.0;
	float head = mod(TIME * sp + h11(ci.x + s * 5.0) * 60.0, rows + len);
	float behind = head - ci.y;
	if (behind < 0.0 || behind > len) {
		return vec3(0.0);
	}
	int g = 1 + int(h21(vec2(ci.x, ci.y + floor(TIME * 6.0 + h11(ci.y + ci.x)))) * 60.0);
	float ink = mix(glyph(g, fract(cell)), 0.4, smoothstep(0.3, 0.75, cpp));
	float fade = 1.0 - behind / len;
	return (behind < 1.0 ? P.key : P.txt * fade * fade) * ink;
}

// Contour lines of the land round the table, its sites and a sweep, on a disc.
vec3 topo_map(vec2 uv, float s, Pal P, float px) {
	vec2 d = uv - 0.5;
	float r = length(d) * 2.0;
	if (r > 1.0) {
		return P.bg * 0.5;
	}
	vec2 w = d * 5.0 + s * 40.0;
	float e = vnoise(w) * 0.6 + vnoise(w * 2.3) * 0.3 + vnoise(w * 5.1) * 0.1;
	float lines = fract(e * 9.0);
	float iso = 1.0 - smoothstep(0.0, 0.09, min(lines, 1.0 - lines));
	float major = step(0.5, fract(floor(e * 9.0) * 0.2 + 0.1)) ;
	vec3 c = P.bg + P.dim * (0.25 + e * 0.35) + P.txt * iso * (0.35 + major * 0.4);
	float grid = (fract(uv.x * 10.0) < px * 10.0 || fract(uv.y * 10.0) < px * 10.0) ? 1.0 : 0.0;
	c += P.dim * grid * 0.4;
	float a = atan(d.x, -d.y);
	float sweep = fract((a - TIME * 0.6) / 6.2832);
	c += P.txt * pow(1.0 - sweep, 8.0) * 0.4;
	// Sites: pulsing rings; here, at the centre.
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 bp = (vec2(h11(fi * 3.1 + s * 17.0), h11(fi * 5.7 + s * 23.0)) - 0.5) * 0.7;
		float dist = length(d - bp);
		c += P.key * (1.0 - smoothstep(0.008, 0.016, dist));
		float ring = abs(dist - fract(TIME * 0.5 + fi * 0.25) * 0.06);
		c += P.key * (1.0 - smoothstep(0.0, 0.004, ring)) * (1.0 - fract(TIME * 0.5 + fi * 0.25));
	}
	float me = length(d);
	c += P.warn * (1.0 - smoothstep(0.01, 0.018, me)) + P.warn * (1.0 - smoothstep(0.0, 0.004, abs(me - 0.03))) * 0.6;
	c += P.txt * step(0.965, r) * 0.7;
	return c;
}

Pal palette(vec3 a) {
	Pal P;
	P.bg = a * 0.03 + vec3(0.004, 0.006, 0.008);
	P.dim = a * 0.3;
	P.txt = a * 0.8;
	P.key = mix(a, vec3(1.0), 0.5);
	float amber = step(a.g * 1.2, a.r);
	P.warn = mix(vec3(1.0, 0.55, 0.15), vec3(1.0, 0.22, 0.18), amber);
	return P;
}

// --- Layouts -------------------------------------------------------------------------

// A console's main screen: header, a scrolling log or live code, and the instruments.
vec3 terminal(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	float px = duv;
	vec4 hd = vec4(0.0, 0.0, 1.0, 0.1);
	if (inr(uv, hd)) {
		c = P.bg + P.dim * 0.35;
		if (inr(uv, vec4(0.015, 0.02, 0.6, 0.08))) {
			vec2 tq = loc(uv, vec4(0.015, 0.02, 0.6, 0.08));
			c += P.key * title_row(tq, cols_for(1.0, vec2(0.585, 0.06)), 0, 8, duv * cols_for(1.0, vec2(0.585, 0.06)) / 0.585);
		}
		vec4 cr = vec4(0.88, 0.02, 0.985, 0.08);
		if (inr(uv, cr)) {
			c += P.txt * clock_row(loc(uv, cr), duv * 5.0 / 0.105);
		}
		// Signal bars.
		vec4 sb = vec4(0.82, 0.025, 0.865, 0.075);
		if (inr(uv, sb)) {
			vec2 q2 = loc(uv, sb);
			float bi = floor(q2.x * 4.0);
			c += P.txt * step(1.0 - q2.y, (bi + 1.0) * 0.25) * step(0.25, fract(q2.x * 4.0)) * step(bi, 2.0 + step(0.5, fract(TIME * 0.3 + s)));
		}
		return c;
	}
	vec4 lg = vec4(0.012, 0.13, 0.585, 0.975);
	vec2 lext = lg.zw - lg.xy;
	float rows = max(6.0, floor(lext.y * v_h / 0.019));
	float cols = cols_for(rows, lext);
	if (inr(uv, lg)) {
		int mode = s < 0.55 ? 0 : 1;
		c += text_area(loc(uv, lg), rows, cols, mode, s, 0.9 + s * 1.4, 0, P, duv * cols / lext.x);
	}
	c += P.dim * frame(uv, vec4(0.004, 0.118, 0.593, 0.99), px * 1.5);
	vec4 wv = vec4(0.61, 0.13, 0.99, 0.43);
	if (inr(uv, wv)) {
		c += P.txt * wave(loc(uv, wv), TIME, s, px * v_asp / (wv.w - wv.y)) * 0.8;
	}
	vec4 br = vec4(0.61, 0.47, 0.99, 0.72);
	if (inr(uv, br)) {
		c += P.txt * bars(loc(uv, br), TIME, s, 18.0);
	}
	// Two gauges and a progress bar.
	float gw = 0.25 / v_asp;
	vec4 g1 = vec4(0.61, 0.75, 0.61 + gw, 1.0);
	vec4 g2 = vec4(0.62 + gw, 0.75, 0.62 + gw * 2.0, 1.0);
	if (inr(uv, g1)) {
		c += P.key * gauge(loc(uv, g1), 0.45 + 0.35 * sin(TIME * 0.21 + s * 7.0), px);
	}
	if (inr(uv, g2)) {
		c += P.txt * gauge(loc(uv, g2), 0.7 + 0.2 * vnoise(vec2(TIME * 0.8, s * 9.0)), px);
	}
	vec4 pb = vec4(0.63 + gw * 2.0, 0.8, 0.99, 0.95);
	if (inr(uv, pb)) {
		vec2 q = loc(uv, pb);
		float row = floor(q.y * 3.0);
		float fill = fract(TIME * (0.05 + 0.04 * row) + h11(row + s * 10.0));
		float seg = step(0.2, fract(q.y * 3.0)) * step(fract(q.y * 3.0), 0.75);
		c += (q.x < fill ? P.txt : P.dim * 0.4) * seg;
	}
	c += P.dim * (frame(uv, vec4(0.603, 0.118, 0.996, 0.44), px * 1.5) + frame(uv, vec4(0.603, 0.46, 0.996, 0.73), px * 1.5));
	return c;
}

// A desk monitor: by its seed, live code, glyph rain, a dashboard or a memory dump.
vec3 monitor(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	int variant = int(s * 3.999);
	float rows = max(8.0, floor(0.9 * v_h / 0.0155));
	vec4 hd = vec4(0.0, 0.0, 1.0, 0.075);
	if (inr(uv, hd)) {
		c += P.dim * 0.35;
		vec4 tr = vec4(0.02, 0.012, 0.7, 0.065);
		c += inr(uv, tr) ? P.key * title_row(loc(uv, tr), cols_for(1.0, tr.zw - tr.xy), 0, 8, duv * cols_for(1.0, tr.zw - tr.xy) / 0.68) * 0.9 : vec3(0.0);
		vec4 cr = vec4(0.84, 0.012, 0.98, 0.065);
		c += inr(uv, cr) ? P.txt * clock_row(loc(uv, cr), duv * 5.0 / 0.14) : vec3(0.0);
		return c;
	}
	if (variant == 0) {
		// An editor: line numbers, code being written, a scroll map.
		vec4 nr = vec4(0.015, 0.09, 0.075, 0.98);
		vec4 ed = vec4(0.09, 0.09, 0.93, 0.98);
		float cols = cols_for(rows, ed.zw - ed.xy);
		float t = TIME * (0.6 + s) + s * 50.0;
		if (inr(uv, nr)) {
			vec2 q = loc(uv, nr);
			vec2 cell = q * vec2(3.0, rows);
			int n = int(floor(cell.y) + floor(t)) % 1000;
			int k = int(cell.x);
			int g = digit(k == 0 ? n / 100 : k == 1 ? (n / 10) % 10 : n % 10);
			c += P.dim * glyph(g, fract(cell));
		}
		if (inr(uv, ed)) {
			c += text_area(loc(uv, ed), rows, cols, 1, s, 0.6 + s, 0, P, duv * cols / (ed.z - ed.x));
		}
		vec4 mp = vec4(0.945, 0.09, 0.985, 0.98);
		if (inr(uv, mp)) {
			vec2 q = loc(uv, mp);
			float ln = floor(q.y * 60.0);
			c += P.dim * step(q.x, h21(vec2(ln, s)) * 0.9) * step(0.3, fract(q.y * 60.0));
			c += P.txt * 0.25 * step(abs(q.y - 0.75), 0.08);
		}
	} else if (variant == 1) {
		vec4 rr = vec4(0.0, 0.08, 1.0, 1.0);
		float cols = cols_for(rows, rr.zw - rr.xy);
		c += rain(loc(uv, rr), rows, cols, s, P, duv * cols);
	} else if (variant == 2) {
		vec4 rd = vec4(0.02, 0.1, 0.02 + 0.86 / v_asp, 0.96);
		if (inr(uv, rd)) {
			c += P.txt * radar(loc(uv, rd), TIME, s, duv / (rd.z - rd.x));
		}
		vec4 wv = vec4(0.04 + 0.86 / v_asp, 0.1, 0.98, 0.5);
		if (inr(uv, wv)) {
			c += P.txt * wave(loc(uv, wv), TIME, s, duv * v_asp / 0.4) * 0.8;
		}
		vec4 br = vec4(0.04 + 0.86 / v_asp, 0.56, 0.98, 0.96);
		if (inr(uv, br)) {
			c += P.txt * bars(loc(uv, br), TIME, s, 12.0);
		}
	} else {
		vec4 hx = vec4(0.02, 0.09, 0.62, 0.98);
		float cols = cols_for(rows, hx.zw - hx.xy);
		if (inr(uv, hx)) {
			c += text_area(loc(uv, hx), rows, cols, 2, s, 2.5, 0, P, duv * cols / 0.6);
		}
		vec4 lg = vec4(0.65, 0.09, 0.98, 0.98);
		float c2 = cols_for(rows, lg.zw - lg.xy);
		if (inr(uv, lg)) {
			c += text_area(loc(uv, lg), rows, c2, 0, s + 0.37, 0.7, 0, P, duv * c2 / 0.33) * 0.9;
		}
	}
	return c;
}

// A wall bulletin: header and clock, notices that turn page every few seconds, a sweep
// of the area and a news ticker.
vec3 bulletin(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	vec4 hd = vec4(0.0, 0.0, 1.0, 0.11);
	if (inr(uv, hd)) {
		c += P.dim * 0.4;
		vec4 tr = vec4(0.02, 0.02, 0.62, 0.09);
		float tc = cols_for(1.0, tr.zw - tr.xy);
		c += inr(uv, tr) ? P.key * title_row(loc(uv, tr), tc, 8, 8, duv * tc / 0.6) : vec3(0.0);
		vec4 cr = vec4(0.84, 0.02, 0.98, 0.09);
		c += inr(uv, cr) ? P.key * clock_row(loc(uv, cr), duv * 5.0 / 0.14) : vec3(0.0);
		return c;
	}
	// Three notices, each a heading and a few lines of words.
	float lh = 0.04 / v_h;
	for (int i = 0; i < 3; i++) {
		float y0 = 0.14 + float(i) * 0.24;
		vec4 nb = vec4(0.02, y0, 0.64, y0 + 0.21);
		if (inr(uv, nb)) {
			c += P.dim * frame(uv, nb, duv * 1.5);
			vec4 bar = vec4(0.02, y0, 0.03, y0 + 0.21);
			c += inr(uv, bar) ? P.key * 0.8 : vec3(0.0);
			vec4 tx = vec4(0.045, y0 + 0.02, 0.63, y0 + 0.2);
			float rows = max(3.0, floor((tx.w - tx.y) * v_h / 0.04));
			float cols = cols_for(rows, tx.zw - tx.xy);
			if (inr(uv, tx)) {
				vec2 q = loc(uv, tx);
				vec3 tcol = text_area(q, rows, cols, 3, s + float(i) * 0.31, 0.0, 0, P, duv * cols / 0.585);
				c += floor(q.y * rows) < 0.5 ? tcol * 1.25 : tcol * 0.85;
			}
		}
	}
	vec4 rd = vec4(0.67, 0.14, 0.67 + 0.56 / v_asp, 0.7);
	if (inr(uv, rd)) {
		c += P.txt * radar(loc(uv, rd), TIME * 0.6, s, duv / (rd.z - rd.x));
	}
	vec4 br = vec4(0.67 + 0.6 / v_asp, 0.14, 0.98, 0.7);
	if (inr(uv, br)) {
		c += P.txt * bars(loc(uv, br), TIME * 0.5, s, 8.0) * 0.8;
	}
	// The ticker: a band of news crawling right to left.
	vec4 tk = vec4(0.0, 0.88, 1.0, 0.99);
	if (inr(uv, tk)) {
		c = P.bg + P.dim * 0.5;
		vec4 lb = vec4(0.01, 0.9, 0.08, 0.97);
		if (inr(uv, lb)) {
			c = P.key * 0.7;
			vec2 q = loc(uv, lb);
			int k = int(q.x * 4.0);
			c -= P.key * 0.7 * glyph(label_char(27, 4, k), vec2(fract(q.x * 4.0), q.y));
			return c;
		}
		vec4 tx = vec4(0.09, 0.9, 1.0, 0.97);
		if (inr(uv, tx)) {
			float cols = cols_for(1.0, tx.zw - tx.xy);
			vec2 q = loc(uv, tx);
			float shift = TIME * 6.0;
			float cx = q.x * cols + shift;
			float line = floor(cx / 48.0);
			int tone;
			int len;
			int g = line_char(3, s + 0.77, line, 0.0, int(mod(cx, 48.0)), 0, tone, len);
			c += P.txt * mix(glyph(g, vec2(fract(cx), q.y)), g > 0 ? 0.36 : 0.0, smoothstep(0.3, 0.75, duv * cols / 0.91));
		}
	}
	return c;
}

// A boat's instrument: a heading tape that follows the vessel, a sonar fan and readouts.
vec3 nav(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	vec4 hd = vec4(0.0, 0.0, 1.0, 0.18);
	float hdg = degrees(v_hdg);
	if (inr(uv, hd)) {
		vec2 q = loc(uv, hd);
		float span = 90.0;
		float deg = hdg + (q.x - 0.5) * span;
		float d10 = fract(deg / 10.0);
		float tick = step(min(d10, 1.0 - d10), duv * span / 10.0 * 1.2) * step(0.55, q.y);
		float d30 = fract(deg / 90.0);
		float big = step(min(d30, 1.0 - d30), duv * span / 90.0 * 2.0) * step(0.25, q.y);
		c += P.txt * max(tick * 0.6, big);
		c += P.warn * step(abs(q.x - 0.5), duv * 2.0) * step(0.3, q.y);
		// Cardinal letter under the nearest quarter.
		float near = floor(deg / 90.0 + 0.5);
		float off = (near * 90.0 - hdg) / span + 0.5;
		float cw = 0.75 * 0.55 * (hd.w - hd.y) / v_asp;
		vec2 lq = vec2((q.x - off) / cw + 0.5, q.y / 0.55);
		int dir = int(mod(near, 4.0));
		int g = dir == 0 ? 24 : dir == 1 ? 15 : dir == 2 ? 29 : 33;
		if (lq.x >= 0.0 && lq.x < 1.0 && lq.y >= 0.0 && lq.y < 1.0) {
			c += P.key * glyph(g, lq);
		}
		return c;
	}
	vec4 sn = vec4(0.03, 0.22, 0.03 + 1.5 / v_asp * 0.78, 0.98);
	if (inr(uv, sn)) {
		vec2 q = loc(uv, sn);
		vec2 d = q - vec2(0.5, 0.0);
		float r = length(d * vec2(1.0, 1.0)) * 1.0;
		float a = atan(d.x, d.y);
		if (r < 1.0 && abs(a) < 0.9) {
			float bed = 0.55 + 0.25 * vnoise(vec2(a * 3.0 + TIME * 0.15 + s * 9.0, s));
			c += P.txt * step(bed, r) * (0.25 + 0.5 * vnoise(vec2(a * 40.0, r * 30.0)));
			c += P.dim * step(fract(r * 5.0), duv * 6.0);
			float sweep = fract(TIME * 0.4 + s);
			c += P.key * (1.0 - smoothstep(0.0, 0.03, abs((a + 0.9) / 1.8 - sweep))) * 0.6;
			float fish = 1.0 - smoothstep(0.012, 0.02, length(q - vec2(0.35 + 0.2 * sin(TIME * 0.3 + s * 6.0), 0.35)));
			c += P.key * fish;
		}
	}
	vec4 rd = vec4(0.05 + 1.5 / v_asp * 0.78, 0.22, 0.98, 0.98);
	if (inr(uv, rd)) {
		float rows = max(3.0, floor((rd.w - rd.y) * v_h / 0.012));
		float cols = cols_for(rows, rd.zw - rd.xy);
		c += text_area(loc(uv, rd), rows, cols, 0, s, 0.5, 1, P, duv * cols / (rd.z - rd.x));
	}
	return c;
}

// A bunker notice: a hazard-striped header and the notice's text.
vec3 notice(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	vec4 hd = vec4(0.0, 0.0, 1.0, 0.18);
	if (inr(uv, hd)) {
		vec2 q = loc(uv, hd);
		float stripe = step(0.5, fract((uv.x * v_asp + uv.y) * 6.0));
		bool lab = q.x > 0.25 && q.x < 0.75;
		c = lab ? P.warn * 0.75 : P.warn * stripe * 0.5;
		if (lab) {
			vec2 lq = vec2((q.x - 0.25) / 0.5, q.y);
			float cols = 6.0;
			int k = int(lq.x * cols);
			float pulse = 0.5 + 0.5 * step(0.5, fract(TIME * 0.8));
			c -= P.warn * 0.75 * glyph(label_char(16, 6, k), vec2(fract(lq.x * cols), lq.y * 1.1 - 0.05)) * pulse;
		}
		return c;
	}
	vec4 tx = vec4(0.04, 0.24, 0.96, 0.96);
	float rows = max(4.0, floor((tx.w - tx.y) * v_h / 0.02));
	float cols = cols_for(rows, tx.zw - tx.xy);
	if (inr(uv, tx)) {
		c += text_area(loc(uv, tx), rows, cols, 3, s, 0.0, 0, P, duv * cols / 0.92);
	}
	return c;
}

// The touch deck in front of a console: keys that light as they are pressed, sliders.
vec3 touch(vec2 uv, Pal P, float duv) {
	vec3 c = P.bg;
	float s = v_seed;
	vec2 g = vec2(8.0, 3.0);
	vec4 kb = vec4(0.04, 0.08, 0.7, 0.92);
	if (inr(uv, kb)) {
		vec2 q = loc(uv, kb) * g;
		vec2 ki = floor(q);
		vec2 kf = fract(q);
		float key = step(0.1, kf.x) * step(kf.x, 0.9) * step(0.14, kf.y) * step(kf.y, 0.86);
		float edge = key * (1.0 - step(0.16, kf.x) * step(kf.x, 0.84) * step(0.22, kf.y) * step(kf.y, 0.78));
		float hit = h21(ki + floor(TIME * 2.0 + h21(ki + s) * 3.0) + s * 7.0);
		c += P.dim * edge * 0.8 + (hit > 0.88 ? P.key * key * 0.6 : P.dim * key * 0.15);
	}
	for (int i = 0; i < 3; i++) {
		float x0 = 0.74 + float(i) * 0.085;
		vec4 sl = vec4(x0, 0.1, x0 + 0.04, 0.9);
		if (inr(uv, sl)) {
			vec2 q = loc(uv, sl);
			float lvl = 0.3 + 0.5 * vnoise(vec2(TIME * 0.3, float(i) * 3.0 + s * 9.0));
			c += (1.0 - q.y < lvl ? P.txt * 0.6 : P.dim * 0.2) * step(0.3, q.x) * step(q.x, 0.7);
			c += P.key * step(abs(1.0 - q.y - lvl), 0.03);
		}
	}
	return c;
}

void fragment() {
	vec2 uv = UV;
	// A screen pixel's size in u (the face's width), taken before any branch.
	float duv = max(max(fwidth(uv.x), fwidth(uv.y) / v_asp), 1e-6);
	Pal P = palette(v_acc);
	int kind = int(v_kind);
	// Now and then a line of the picture tears sideways for a few frames.
	float gl = step(0.996, h11(floor(TIME * 12.0) + v_seed * 300.0));
	uv.x += gl * (h11(floor(uv.y * 30.0) + floor(TIME * 40.0)) - 0.5) * 0.02;
	vec3 c;
	if (kind == 0) {
		c = terminal(uv, P, duv);
	} else if (kind == 1) {
		c = monitor(uv, P, duv);
	} else if (kind == 2) {
		c = bulletin(uv, P, duv);
	} else if (kind == 3) {
		c = topo_map(uv, v_seed, P, duv);
	} else if (kind == 4) {
		c = nav(uv, P, duv);
	} else if (kind == 5) {
		c = notice(uv, P, duv);
	} else {
		c = touch(uv, P, duv);
	}
	// The panel itself: a faint pixel grid and scan lines up close, darker at the rim.
	float close = 1.0 - smoothstep(0.0006, 0.0015, duv * v_asp * v_h);
	float scan = 1.0 - close * 0.18 * step(0.5, fract(uv.y * v_h * 220.0));
	vec2 e = min(uv, 1.0 - uv) * vec2(v_asp, 1.0);
	float rim = smoothstep(0.0, 0.04, min(e.x, e.y));
	float on = clamp(power, 0.0, 1.0);
	c *= scan * (0.75 + 0.25 * rim) * (0.97 + 0.03 * sin(TIME * 60.0 + v_seed * 10.0));
	ALBEDO = vec3(0.012, 0.014, 0.016);
	ROUGHNESS = 0.2;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	EMISSION = c * energy * on;
}
