#[compute]
#version 450
// Mends the few pixels a shader got wrong (not a number, infinite or negative: at the
// edges of triangles under MSAA a shader can be run just outside them and divide by
// nothing) with the average of their sound neighbours. One such pixel threw the eye's
// exposure all the way open, washing the whole frame out white.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 reserved;
} params;

bool bad(vec3 c) {
	return any(isnan(c)) || any(isinf(c)) || any(lessThan(c, vec3(0.0)));
}

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.size);
	if (uv.x >= size.x || uv.y >= size.y) {
		return;
	}
	vec4 c = imageLoad(color_image, uv);
	if (!bad(c.rgb)) {
		return;
	}
	if (params.reserved.x > 0.5) {
		// Shows where they are instead (capture --mend=show): bright magenta.
		imageStore(color_image, uv, vec4(40.0, 0.0, 40.0, 1.0));
		return;
	}
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 q = clamp(uv + ivec2(i == 0 ? 1 : (i == 1 ? -1 : 0), i == 2 ? 1 : (i == 3 ? -1 : 0)), ivec2(0), size - 1);
		vec3 s = imageLoad(color_image, q).rgb;
		if (!bad(s)) {
			sum += s;
			n += 1.0;
		}
	}
	imageStore(color_image, uv, vec4(n > 0.0 ? sum / n : vec3(0.0), 1.0));
}
