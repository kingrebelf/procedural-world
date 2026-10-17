shader_type spatial;
// The glass of a lit lantern (FireFx.flame with glass): sooty panes that catch the light
// of the wick inside, brightest toward their edges where you look through more glass, and
// rising and falling with the flame's life (fire.gdshaderinc). So a lantern reads as lit
// from any side, even where its frame hides the little flame.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://src/world/fire.gdshaderinc"

instance uniform float seed = 0.0;

void fragment() {
	float life = fire_life(fire_time, seed);
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	// Brighter low down, round the wick, fading toward the cap where the soot is.
	float low = mix(1.0, 0.55, UV.y < 0.5 ? 0.0 : 1.0);
	ALBEDO = vec3(1.0, 0.55, 0.2) * (0.22 + 0.5 * edge * edge) * (0.75 + 0.5 * life) * low;
}
