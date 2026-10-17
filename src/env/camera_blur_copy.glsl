#[compute]
#version 450
// Copies the frame for CameraBlur to read while it writes the smeared frame back.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 reserved;
} p;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) {
		return;
	}
	imageStore(dst_image, px, imageLoad(src_image, px));
}
