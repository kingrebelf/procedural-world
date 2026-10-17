shader_type spatial;
// Rock with mineral veins: the stone photo texture mapped triplanar, tinted by vertex
// colour, crossed by thin seams of ore (a band of 3D noise) that catch the light like metal.

uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 ore_col : source_color = vec3(0.55, 0.28, 0.14);
uniform vec3 ore_col2 : source_color = vec3(0.75, 0.72, 0.68);
uniform float vein_width = 0.16;
uniform float vein_freq = 1.6;
uniform float ore_metal = 0.7;
uniform float tri_scale = 0.35;
// Ben's ore photos already carry their veins: then the photo is the rock, in its own
// colours, and its saturated parts (rust, gold, mineral) are the ore that shines.
uniform bool photo_ore = false;
// Close-up pieces (held ore): the mineral as small disseminated grains clustered in
// patches with a rusty stain round them, instead of seams (which read as paint up close).
uniform float grain_freq = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying vec3 tint;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	tint = pow(COLOR.rgb, vec3(2.2));
}

vec4 tri(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.yz) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 p = obj_pos * tri_scale;
	if (photo_ore) {
		vec3 c = tri(stone_tex, p, obj_nrm).rgb;
		float lt = max(dot(tint, vec3(0.3333)), 0.02);
		vec3 rock = c * mix(vec3(1.0), tint / lt, 0.25) * (0.75 + 0.5 * clamp(lt * 3.0, 0.0, 1.0));
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.02);
		float ore = smoothstep(0.35, 0.6, sat) * smoothstep(0.03, 0.12, mx);
		ALBEDO = rock;
		METALLIC = ore * ore_metal;
		ROUGHNESS = mix(0.88, 0.45, ore);
		NORMAL_MAP = tri(stone_nrm, p, obj_nrm).rgb;
	} else if (grain_freq > 0.0) {
		vec3 stone = tri(stone_tex, p, obj_nrm).rgb * tint * 1.25;
		float patch = smoothstep(0.32, 0.55, noise(obj_pos * vein_freq * 0.35 + 7.3));
		float gn = noise(obj_pos * grain_freq) * 0.7 + noise(obj_pos * grain_freq * 2.7) * 0.3;
		float grain = smoothstep(0.62, 0.66, gn) * patch;
		float stain = smoothstep(0.5, 0.66, gn) * patch * (1.0 - grain);
		vec3 ore = mix(ore_col, ore_col2, step(0.6, noise(obj_pos * grain_freq * 0.5 + 3.0))) * (0.75 + 0.35 * noise(obj_pos * grain_freq * 4.0));
		ore = mix(ore, stone, 0.25);
		vec3 rust = stone * vec3(0.95, 0.72, 0.5);
		ALBEDO = mix(mix(stone, rust, stain * 0.45), ore, grain);
		METALLIC = grain * ore_metal;
		ROUGHNESS = mix(0.9, mix(0.75, 0.3, ore_metal), grain);
		NORMAL_MAP = tri(stone_nrm, p, obj_nrm).rgb;
	} else {
		vec3 stone = tri(stone_tex, p, obj_nrm).rgb * tint * 1.25;
		// Veins: where a warped noise field crosses 0.5, in thin seams that branch.
		vec3 q = obj_pos * vein_freq;
		float n = noise(q + noise(q * 2.3) * 1.5);
		float d = abs(n - 0.5);
		float vein = 1.0 - smoothstep(vein_width * 0.35, vein_width * 0.5, d);
		// Specks of the paler second mineral inside the seams.
		float speck = step(0.78, noise(obj_pos * 9.0)) * vein;
		vec3 ore = mix(ore_col, ore_col2, speck) * (0.8 + 0.4 * noise(obj_pos * 4.0));
		ALBEDO = mix(stone, ore, vein);
		METALLIC = vein * ore_metal;
		ROUGHNESS = mix(0.9, 0.35, vein);
		NORMAL_MAP = tri(stone_nrm, p, obj_nrm).rgb;
	}
}
