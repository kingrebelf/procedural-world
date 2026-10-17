#[compute]
#version 450
// Mends the few pixels a shader got wrong (not a number, infinite or negative: at the
// edges of triangles under MSAA a shader can be run just outside them and divide by
// nothing) with the average of their sound neighbours. One such pixel threw the eye's
// exposure all the way open, washing the whole frame out white.
// At night it also grades the dim parts of the frame as the dark-adapted eye sees them
// (Purkinje shift): moonlit land loses its colour and shifts toward blue, while what a
// window, a fire or a torch lights stays warm and saturated, so lamps stand out.

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
	float night = params.reserved.y;
	if (!bad(c.rgb)) {
		if (night > 0.0) {
			float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
			// Scene-linear, before exposure: moonlit ground sits well under 0.2, lamplight
			// and the surfaces right by a flame well over 1.
			float rod = night * (1.0 - smoothstep(0.2, 1.2, lum));
			imageStore(color_image, uv, vec4(mix(c.rgb, lum * vec3(0.78, 0.9, 1.18), rod * 0.7), c.a));
		}
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
