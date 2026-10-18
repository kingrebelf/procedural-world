// Dissolves between levels of detail, so nothing pops: a mesh coming in draws a growing
// share of the screen's pixels and the one it replaces the rest, picked by the same
// screen-space noise (which TAA and FSR smooth into a soft cross-fade). All opaque: no
// sorting, no alpha pass. Shadows switch over halfway instead (a shadow map's pixels
// aren't the screen's).

// Where the eye is (ChunkStreamer sets it each frame): shadow passes see from the sun.
global uniform vec3 eye_pos_g;
// How much of a mesh is drawn (ChunkNode sets it): 1 all of it; 0 to 1 coming in;
// -1 - a going out, the exact complement of a mesh coming in at a.
instance uniform float appear = 1.0;
// Fading with distance from the eye (ChunkNode.TREE_FADE): x to y metres, z +1 drawn
// nearer than the band and dissolving through it, -1 the other way; 0 off.
instance uniform vec3 lod_band = vec3(0.0);

float lod_noise(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// The share `lod_band` gives at this distance, as in `appear`.
float lod_band_share(float dist) {
	if (lod_band.z == 0.0) {
		return 1.0;
	}
	float t = smoothstep(lod_band.x, lod_band.y, dist);
	return lod_band.z > 0.0 ? -1.0 - t : t;
}

// Whether this pixel is left to the other level, for a share `a` as in `appear`.
bool lod_cut(float a, vec2 frag, bool shadow) {
	if (a >= 1.0) {
		return false;
	}
	if (shadow) {
		return (a >= 0.0 ? a : 2.0 + a) < 0.5;
	}
	float h = lod_noise(frag);
	return a >= 0.0 ? h >= a : h < -1.0 - a;
}

// Both at once, for a point of the mesh at `world`.
bool lod_hidden(vec3 world, vec2 frag, bool shadow) {
	return lod_cut(appear, frag, shadow) || lod_cut(lod_band_share(distance(world, eye_pos_g)), frag, shadow);
}
