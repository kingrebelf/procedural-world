// Fabric detail for Outfit garments and armour: textures are laid onto the rest pose
// (CUSTOM0.wyz position, CUSTOM1 normal) from three sides, so the weave rides along with
// the body instead of swimming, and a height bump from the same detail gives it relief.

varying vec3 rest_pos;
varying vec3 rest_n;

// In vertex(): rest_pos = vec3(CUSTOM0.w, CUSTOM0.y, CUSTOM0.z); rest_n = CUSTOM1.xyz;

// Greyscale detail (mean ~0.72) tiled every `tile` metres, texture up = body up.
float fabric(sampler2D t, vec3 rp, vec3 rn, float tile) {
	vec3 w = pow(abs(rn), vec3(4.0));
	w /= w.x + w.y + w.z + 1e-5;
	vec3 p = rp / tile;
	return texture(t, vec2(p.z, -p.y)).r * w.x + texture(t, p.xz).r * w.y + texture(t, vec2(p.x, -p.y)).r * w.z;
}

// Tilts a view-space normal by the screen-space slope of a height (in metres).
vec3 fabric_bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - g);
}
