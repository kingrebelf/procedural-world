#[compute]
#version 450
// Motion blur (CameraBlur): smears each pixel along the way it moved on screen since the
// last frame, as a camera shutter that stays open for a moment would. Motion comes from
// the engine's motion vectors where an object wrote them (people, animals, the held item)
// and otherwise from the pixel's depth and how the camera itself moved (the land, the sky).
// The held item (anything nearer than near_dist) is never smeared and never bleeds into
// the world behind it. Reads a copy of the frame (camera_blur_copy.glsl) and writes the
// smeared pixels back into it.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D out_image;
layout(set = 0, binding = 1) uniform sampler2D color_tex;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3) uniform sampler2D velocity_tex;

layout(push_constant, std430) uniform Params {
	mat4 reproject; // this frame's clip space -> last frame's clip space
	vec4 inv_z; // rows of the inverse projection, for the distance of a pixel
	vec4 inv_w;
	vec2 size;
	float scale; // shutter time / frame time
	float max_len; // longest smear, as a fraction of the width
	float near_dist;
	float debug; // 1: paint the motion instead (red/green = x/y)
	vec2 reserved;
} p;

vec4 clip_of(vec2 uv, float d) {
	return vec4(uv * 2.0 - 1.0, d, 1.0);
}

float dist_of(vec4 c) {
	return -dot(p.inv_z, c) / dot(p.inv_w, c);
}

// Screen motion of the pixel at px in uv units, as the engine's motion vectors give it:
// where it was last frame minus where it is now.
vec2 motion(ivec2 px, vec2 uv, float d) {
	vec2 mv = texelFetch(velocity_tex, px, 0).xy;
	// (-1, -1) marks "not written" (with FSR 2 only moving objects write them); the sky
	// never writes any.
	if (d > 0.0 && mv.x > -0.99) {
		return mv;
	}
	vec4 prev = p.reproject * clip_of(uv, d);
	if (prev.w <= 0.0) {
		return vec2(0.0);
	}
	return (prev.xy / prev.w * 0.5 + 0.5) - uv;
}

float noise(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 isize = ivec2(p.size);
	if (px.x >= isize.x || px.y >= isize.y) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / p.size;
	vec4 c = texelFetch(color_tex, px, 0);
	float d = texelFetch(depth_tex, px, 0).r;
	vec2 b = motion(px, uv, d) * p.scale;
	if (p.debug > 1.5) {
		// Checks the two sources agree (tools/probe_camera_blur.gd, with TAA so every
		// surface writes motion vectors): green where they point the same way and are about
		// as long, red where not. The held item moves with the camera, so it is red.
		vec2 mv = texelFetch(velocity_tex, px, 0).xy;
		vec4 prev = p.reproject * clip_of(uv, d);
		vec2 cam = (prev.xy / prev.w * 0.5 + 0.5) - uv;
		bool ok = dot(mv, cam) > 0.95 * length(mv) * length(cam) && abs(length(mv) / length(cam) - 1.0) < 0.25;
		imageStore(out_image, px, d > 0.0 && length(cam) > 1e-4 ? (ok ? vec4(0.0, 4.0, 0.0, 1.0) : vec4(4.0, 0.0, 0.0, 1.0)) : vec4(0.0, 0.0, 0.0, 1.0));
		return;
	}
	if (p.debug > 0.5) {
		imageStore(out_image, px, vec4(max(b * 40.0, 0.0), max(-b.x * 40.0, 0.0), 1.0));
		return;
	}
	float len_px = length(b * p.size);
	float max_px = p.max_len * p.size.x;
	if (len_px > max_px) {
		b *= max_px / len_px;
		len_px = max_px;
	}
	if (len_px < 1.0 || dist_of(clip_of(uv, d)) < p.near_dist) {
		return;
	}
	// Centred on the pixel: half the shutter before this moment, half after.
	int n = clamp(int(len_px * 0.5) + 2, 3, 12);
	float j = noise(vec2(px)) - 0.5;
	vec3 sum = c.rgb;
	float w = 1.0;
	for (int i = 0; i < n; i++) {
		vec2 s = uv + b * ((float(i) + 0.5 + j) / float(n) - 0.5);
		ivec2 sp = clamp(ivec2(s * p.size), ivec2(0), isize - 1);
		if (dist_of(clip_of(s, texelFetch(depth_tex, sp, 0).r)) < p.near_dist) {
			continue;
		}
		sum += textureLod(color_tex, s, 0.0).rgb;
		w += 1.0;
	}
	imageStore(out_image, px, vec4(sum / w, c.a));
}
