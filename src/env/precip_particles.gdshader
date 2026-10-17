shader_type particles;
// Rain, snow and blown dust round the camera (Weather). The drops live in a box that
// follows the emitter (moved to the camera each frame): each falls with the wind, and
// whatever leaves the box comes back in on the far side, so the box is always full and
// walking, riding or flying never outruns the weather. A drop that hits anything (the
// collision height field Weather keeps over the camera: ground, roofs, canopies) is
// hidden until it wraps back to the top, so nothing falls indoors or under a cave roof;
// on the way it can throw a splash (the sub-emitter).
render_mode disable_velocity, disable_force;

uniform vec3 box_half = vec3(24.0, 14.0, 24.0);
uniform vec3 fall = vec3(0.0, -9.0, 0.0); // metres per second, wind included
uniform float speed_jitter = 0.15;
uniform float sway = 0.0; // flakes flutter side to side, metres per second
uniform float density = 1.0; // share of the drops shown
uniform float splash = 0.0; // chance a landing drop throws a splash

float h1(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	if (RESTART_POSITION) {
		vec3 r = vec3(h1(INDEX * 3u + 1u), h1(INDEX * 3u + 2u), h1(INDEX * 3u + 3u));
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + (r * 2.0 - 1.0) * box_half;
		// x: the drop's own random value, y: 1 once it has landed, z: 1 while drawn.
		CUSTOM = vec4(h1(INDEX * 7u + 11u), 0.0, 0.0, 0.0);
	}
}

void process() {
	float seed = CUSTOM.x;
	vec3 v = fall * (1.0 + (seed - 0.5) * 2.0 * speed_jitter);
	if (sway > 0.0) {
		float ph = TIME * (0.6 + seed * 0.9) + seed * 40.0;
		v.xz += vec2(sin(ph), cos(ph * 1.37)) * sway;
	}
	vec3 c = EMISSION_TRANSFORM[3].xyz;
	vec3 pos = TRANSFORM[3].xyz + v * DELTA;
	vec3 rel = pos - c;
	rel.xz = mod(rel.xz + box_half.xz, box_half.xz * 2.0) - box_half.xz;
	if (rel.y < -box_half.y) {
		rel.y += box_half.y * 2.0;
		CUSTOM.y = 0.0;
	} else if (rel.y > box_half.y) {
		rel.y -= box_half.y * 2.0;
	}
	if (COLLIDED && CUSTOM.y < 0.5) {
		CUSTOM.y = 1.0;
		if (splash > 0.0 && fract(seed * 97.31 + TIME * 3.7) < splash) {
			mat4 at = mat4(1.0);
			at[3].xyz = pos + COLLISION_NORMAL * 0.02;
			emit_subparticle(at, COLLISION_NORMAL, vec4(1.0), vec4(0.0), FLAG_EMIT_POSITION | FLAG_EMIT_VELOCITY);
		}
	}
	TRANSFORM[3].xyz = c + rel;
	VELOCITY = v;
	CUSTOM.z = (seed < density && CUSTOM.y < 0.5) ? 1.0 : 0.0;
}
