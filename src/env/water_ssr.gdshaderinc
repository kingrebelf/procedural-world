// Reflections on lakes, seas and rivers, traced through the frame already drawn: the
// reflected ray steps out from the surface (in growing strides, then a short binary
// search) until it passes behind something on screen, and that pixel is what the water
// mirrors. Godot's own SSR skips transparent materials, so water traces its own. Where
// the ray finds nothing (it leaves the screen, or only sky lies that way) the sky's
// reflection from the environment shows instead. Needs depth_tex and screen_tex.

// Strides per ray; 0 turns the trace off (the "ssr" graphics setting).
uniform int ssr_steps = 20;

vec3 ssr_view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// p: the surface point and r: the reflected direction, both in view space. min_y: the
// lowest world height a reflected thing may have (below it lies under the water, seen
// through it rather than mirrored). Returns the mirrored colour and how sure the hit is.
vec4 water_ssr(vec3 p, vec3 r, mat4 proj, mat4 inv_proj, mat4 inv_view, float min_y, float lod) {
	if (ssr_steps <= 0) {
		return vec4(0.0);
	}
	float stride = max(0.35, -p.z * 0.02);
	float t = 0.0;
	float prev = 0.0;
	bool hit = false;
	vec2 uv = vec2(0.0);
	for (int i = 0; i < ssr_steps; i++) {
		prev = t;
		t += stride;
		stride *= 1.3;
		vec3 q = p + r * t;
		vec4 c = proj * vec4(q, 1.0);
		if (c.w <= 0.0) {
			break;
		}
		uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			break;
		}
		float sz = ssr_view_pos(uv, inv_proj).z;
		// Passed behind something, but not so far behind it that the ray went under it.
		if (q.z < sz && sz - q.z < max(stride * 1.6, 0.6)) {
			hit = true;
			break;
		}
	}
	if (!hit) {
		return vec4(0.0);
	}
	// Narrow the crossing down between the last two strides.
	float lo = prev;
	float hi = t;
	for (int j = 0; j < 5; j++) {
		float mid = (lo + hi) * 0.5;
		vec3 q = p + r * mid;
		vec4 c = proj * vec4(q, 1.0);
		vec2 u = c.xy / c.w * 0.5 + 0.5;
		if (q.z < ssr_view_pos(u, inv_proj).z) {
			hi = mid;
			uv = u;
		} else {
			lo = mid;
		}
	}
	vec3 s = ssr_view_pos(uv, inv_proj);
	if ((inv_view * vec4(s, 1.0)).y < min_y) {
		return vec4(0.0);
	}
	// Fade out toward the screen's edges and at the end of the ray, so the mirrored image
	// never stops on a hard line.
	vec2 edge = smoothstep(vec2(0.0), vec2(0.06, 0.1), uv) * (1.0 - smoothstep(vec2(0.94, 0.9), vec2(1.0), uv));
	float conf = edge.x * edge.y * (1.0 - smoothstep(180.0, 300.0, hi));
	return vec4(textureLod(screen_tex, uv, lod).rgb, conf);
}
