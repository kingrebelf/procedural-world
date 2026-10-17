shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;
// A planet's air, on a shell a little larger than it: sunlight scattered blue on the day
// side, thinning out above the limb over a few scale heights, ruddy along the terminator
// where the light comes through the air at sunset, and brightest where you look toward
// the sun through it.

uniform vec3 air : source_color = vec3(0.45, 0.65, 1.0);
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.7); // world space, toward the sun
uniform float planet_r = 60.0; // the planet's radius (world units)
uniform float scale_h = 0.36; // how fast the air thins with height (world units)
uniform float strength = 1.0;

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 centre = NODE_POSITION_WORLD;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize(wp - cam);
	// Where the line of sight passes nearest the planet's middle, and how high that is.
	vec3 near = cam + v * dot(centre - cam, v);
	float d = length(near - centre);
	vec3 n = (near - centre) / max(d, 1e-4);
	float dens;
	if (d >= planet_r) {
		dens = exp(-(d - planet_r) / scale_h);
	} else {
		// Over the disc: the air between you and the ground, thicker toward the limb.
		float mu = sqrt(max(1.0 - (d * d) / (planet_r * planet_r), 0.0));
		dens = 1.0 / (1.0 + mu * planet_r / (scale_h * 4.0));
	}
	vec3 s = normalize(sun_dir);
	float sl = dot(n, s);
	float lit = smoothstep(-0.22, 0.2, sl);
	vec3 tint = mix(vec3(1.0, 0.4, 0.16), air, smoothstep(-0.04, 0.3, sl));
	// Forward scattering: a bright halo where the sun shines toward you through the air.
	float fw = pow(max(dot(v, s), 0.0), 8.0) * 3.0;
	ALBEDO = tint * dens * lit * (1.1 + fw) * strength;
}
