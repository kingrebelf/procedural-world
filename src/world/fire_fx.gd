class_name FireFx
extends RefCounted
## Living flames: Ben's fire flipbook (assets/textures/fx/fire_flipbook.png) on upright
## cards that turn to face you about the vertical only and cross-fade through the sheet's
## 16 frames, with turbulence licking up through them (flame.gdshader); candle and lamp
## flames drawn (wick_flame.gdshader). Each flickers with its own life (life(), shared with
## the FlickerLight beside it), leans downwind and trails behind when carried. The sheet's
## black is see-through (premultiplied blending). A flame's node sits at its base.

const SHEET := "res://assets/textures/fx/fire_flipbook.png"
## Each frame's flame stands this share of the frame above its bottom edge (a jet hangs
## this share below its top edge), per sheet.
const FOOT := {"fire": 0.12, "jet": 0.02}
const FPS := 8.0

## Where kit props burn, in the prop's own space: model -> [[foot of the flame, height]].
## Wall torches burn in their iron cups; candles at their wicks.
const PROP_FLAMES := {
	"props/Torch_Metal": [[Vector3(0, 0.34, 0.27), 0.42]],
	# The wick in the hanging lantern, behind its glass (the third entry: the panes' box).
	"props/Lantern_Wall": [[Vector3(0, 0.2, 0.8), 0.11, Vector3(0.2, 0.24, 0.2)]],
	"props/Candle_1": [[Vector3(0, 0.128, 0), 0.07]],
	"props/CandleStick_Triple": [[Vector3(0, 0.457, 0), 0.07], [Vector3(-0.17, 0.335, 0), 0.07], [Vector3(0.18, 0.335, 0), 0.07]],
	"props/CandleStick_Stand": [[Vector3(-0.31, 1.3, 0), 0.07], [Vector3(0.31, 1.297, 0), 0.07], [Vector3(-0.21, 1.297, 0.21), 0.07],
		[Vector3(0.22, 1.296, -0.21), 0.07], [Vector3(0, 1.272, 0), 0.07]],
	"props/Chandelier": [[Vector3(0.41, -0.912, -0.41), 0.07], [Vector3(0.41, -0.973, 0.41), 0.07], [Vector3(-0.58, -0.912, 0), 0.07],
		[Vector3(0, -0.947, -0.57), 0.07], [Vector3(0.58, -0.912, 0), 0.07], [Vector3(-0.41, -0.912, 0.41), 0.07],
		[Vector3(0, -0.947, 0.58), 0.07], [Vector3(-0.41, -0.973, -0.41), 0.07]],
}

static var _mats: Dictionary = {}

## The flames of the burning props among placed models ([model, yaw degrees, position,
## scale], as rooms and build pieces list them): [[foot, height]] in the same space.
static func prop_flames(models: Array) -> Array:
	var out: Array = []
	for m in models:
		var at: Array = PROP_FLAMES.get(m[0], [])
		if at.is_empty():
			continue
		var s: float = float(m[3]) if m.size() > 3 and m[3] is float else 1.0
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(m[1]))).scaled(Vector3.ONE * s), m[2])
		for f in at:
			out.append([xf * (f[0] as Vector3), float(f[1]) * s] + ([(f[2] as Vector3) * s] if f.size() > 2 else []))
	return out

## Flames smaller than this (candles, lamp wicks) are drawn (wick_flame.gdshader) rather
## than taken from the flipbook.
const SMALL := 0.2

## The fires' clock, in seconds: FireClock advances it every frame and hands it to the
## shaders as `fire_time`, so a flame and its light read the same moment. Wraps round.
static var time := 0.0
const WRAP := 4096.0

static func tick(delta: float) -> void:
	time = fmod(time + delta, WRAP)
	RenderingServer.global_shader_parameter_set("fire_time", time)

## fire.gdshaderinc's fx_perm/fx_hash/fx_noise/fire_life, line for line: the life of a
## flame at time t, 0 (sinking low) .. 1 (leaping), about 0.5 on average.
static func _perm(x: float) -> float:
	return fposmod((34.0 * x + 1.0) * x, 289.0)

static func _hash(i: float) -> float:
	return _perm(_perm(fposmod(i, 289.0)) + 17.0) / 289.0

static func _noise(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	return lerpf(_hash(i), _hash(i + 1.0), f * f * (3.0 - 2.0 * f))

static func life(t: float, seed: float) -> float:
	var s := seed * 97.0
	return 0.5 * _noise(t * 1.9 + s) + 0.3 * _noise(t * 5.3 + s * 1.7 + 11.0) + 0.2 * _noise(t * 12.7 + s * 2.3 + 23.0)

## The flame for one entry of prop_flames(), stood where it burns (with its lantern
## glass, if it has one).
static func prop_flame(f: Array) -> Node3D:
	var n := flame(float(f[1]), Color(1, 1, 1, 1), "fire", false, -1.0, f[2] if f.size() > 2 else Vector3.ZERO)
	n.position = f[0]
	return n

## The flipbook material for a sheet in assets/textures/fx ("fire", "jet").
static func material(sheet := "fire") -> ShaderMaterial:
	if _mats.has(sheet):
		return _mats[sheet]
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/flame.gdshader")
	m.set_shader_parameter("fps", FPS * (2.0 if sheet == "jet" else 1.0))
	m.set_shader_parameter("foot", FOOT.get(sheet, 0.0))
	m.set_shader_parameter("hang", sheet == "jet")
	var path := SHEET.replace("fire_", sheet + "_")
	if ResourceLoader.exists(path):
		m.set_shader_parameter("tex", load(path))
	_mats[sheet] = m
	return m

static var _wick: ShaderMaterial

## The drawn flame of a candle or a lamp's wick.
static func wick_material() -> ShaderMaterial:
	if _wick == null:
		_wick = ShaderMaterial.new()
		_wick.shader = load("res://src/world/wick_flame.gdshader")
	return _wick

## A flame `size` metres tall, its base at the returned node's origin (or, with `hang`,
## hanging from it, as a jet from a nozzle). A big one is two flipbook cards out of step,
## filled out in the round by rising tongues (tongues()) and now and then a popping log
## (Pops); a small one (under SMALL) a drawn candle flame. `wind` is how much a breeze reaches it:
## 1 in the open, about 0.15 indoors or behind a lantern's glass; below 0 picks by size.
## Its seed (meta "fire_seed") is what a FlickerLight beside it follows.
static func flame(size: float, tint := Color(1, 1, 1, 1), sheet := "fire", hang := false, wind := -1.0, glass := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = "Flame"
	var seed := randf()
	var small := size < SMALL and sheet == "fire"
	if wind < 0.0:
		wind = 0.15 if small else 1.0
	n.set_meta("fire_seed", seed)
	n.set_meta("fire_size", size)
	if small:
		var q := QuadMesh.new()
		q.size = Vector2(size * 0.84, size * 1.5)
		q.center_offset = Vector3(0, size * (1.32 - 0.18) * 0.5, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = wick_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = size
		mi.visibility_range_end = 45.0
		mi.set_instance_shader_parameter("tint", tint)
		mi.set_instance_shader_parameter("seed", seed)
		mi.set_instance_shader_parameter("size", size)
		mi.set_instance_shader_parameter("exposed", wind)
		n.add_child(mi)
		if glass != Vector3.ZERO:
			# A lantern's panes, lit by it: centred on the wick, its bottom a little below.
			var g := MeshInstance3D.new()
			g.name = "Glass"
			var bm := BoxMesh.new()
			bm.size = glass
			g.mesh = bm
			g.material_override = glass_material()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.position = Vector3(0, glass.y * 0.5 - 0.03, 0)
			g.visibility_range_end = 120.0
			g.set_instance_shader_parameter("seed", seed)
			n.add_child(g)
		return n
	# A big fire burns all across its bed: more tongues of flame round the middle one,
	# over glowing coals.
	var big := size >= 0.6 and not hang and sheet == "fire"
	var cards := 4 if big else 2
	for i in cards:
		var s := size * (1.0 if i == 0 else (0.7 if not big else 0.5 + 0.08 * i))
		var q := QuadMesh.new()
		q.size = Vector2(s, s)
		q.center_offset = Vector3(0, s * (0.5 - float(FOOT.get(sheet, 0.0))) * (-1.0 if hang else 1.0), 0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = material(sheet)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The cards turn and lean in the shader, so their box must hold them at any angle.
		mi.extra_cull_margin = s * 1.5
		mi.visibility_range_end = 90.0
		mi.set_instance_shader_parameter("tint", tint)
		mi.set_instance_shader_parameter("seed", seed)
		mi.set_instance_shader_parameter("card", float(i))
		mi.set_instance_shader_parameter("size", s)
		mi.set_instance_shader_parameter("exposed", wind)
		if big and i > 0:
			var a := TAU * (i / 3.0) + seed * TAU
			mi.position = Vector3(cos(a), 0, sin(a)) * size * 0.16
		else:
			mi.position = Vector3(0.04 * size * i, 0, 0)
		n.add_child(mi)
	if big:
		var bed := MeshInstance3D.new()
		bed.name = "Coals"
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * size * 0.62
		bed.mesh = pm
		bed.material_override = coal_material()
		bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bed.position = Vector3(0, 0.02, 0)
		bed.visibility_range_end = 90.0
		bed.set_instance_shader_parameter("seed", seed)
		n.add_child(bed)
	if sheet == "fire" and not hang:
		n.add_child(tongues(size, seed, wind, big))
		n.add_child(Pops.new(size))
	return n

## By the fire_fx setting (Low, Normal, High): the share of each flame's tongues that burn.
const TONGUE_RATIO := [0.4, 0.7, 1.0]
static var _tongue_draw: QuadMesh

## The share of a flame's tongues the fire_fx setting lets burn.
static func tongue_ratio() -> float:
	# Looked up, not named: tools run without the autoloads compiled in.
	var tree := Engine.get_main_loop() as SceneTree
	var st: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	var v = st.get_value("fire_fx") if st != null else null
	return TONGUE_RATIO[clampi(1 if v == null else int(v), 0, TONGUE_RATIO.size() - 1)]

## Tells every burning flame's tongues of a change to the fire_fx setting (FireClock).
static func apply_quality(tree: SceneTree) -> void:
	var r := tongue_ratio()
	for t in tree.get_nodes_in_group("fire_tongues"):
		(t as GPUParticles3D).amount_ratio = r

## A flame's body in the round (flame_tongues.gdshader): tongues of burning gas rising
## off its bed, for depth the flat cards can't give from the side or above. Scaled by the
## flame's height, so the shaders work in flame heights.
static func tongues(size: float, seed: float, wind: float, big := false) -> GPUParticles3D:
	if _tongue_draw == null:
		_tongue_draw = QuadMesh.new()
		var dm := ShaderMaterial.new()
		dm.shader = load("res://src/world/flame_tongue.gdshader")
		_tongue_draw.material = dm
	var p := GPUParticles3D.new()
	p.name = "Tongues"
	p.add_to_group("fire_tongues")
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/flame_tongues.gdshader")
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("exposed", wind)
	m.set_shader_parameter("bed", 0.2 if big else 0.1)
	p.process_material = m
	p.draw_pass_1 = _tongue_draw
	p.amount = clampi(roundi(size * 40.0), 12, 64)
	p.amount_ratio = tongue_ratio()
	# Hot gas rises at about the root of its height (a bonfire's tongues live longer).
	p.lifetime = 0.75 * sqrt(maxf(size, 0.05))
	p.preprocess = p.lifetime
	p.local_coords = false
	p.scale = Vector3.ONE * size
	p.visibility_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.8, 2.4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 90.0
	return p

static var _pop_sounds: Array = []

## Now and then a log pops: a little crack and a few sparks thrown out in arcs that fall
## back, the bigger the fire the more often. Only near you, and only while it is shown.
class Pops extends Node3D:
	var size := 1.0
	var _wait := 0.0
	var _burst: CPUParticles3D
	var _snd: AudioStreamPlayer3D

	func _init(s: float) -> void:
		name = "Pops"
		size = s
		_wait = randf_range(0.5, _rest())

	## Seconds until the next pop: a bonfire every few seconds, a torch now and then.
	func _rest() -> float:
		var k := clampf((size - 0.3) / 0.7, 0.0, 1.0)
		return randf_range(lerpf(9.0, 2.5, k), lerpf(26.0, 11.0, k))

	func _process(delta: float) -> void:
		_wait -= delta
		if _wait > 0.0:
			return
		_wait = _rest()
		if not is_visible_in_tree():
			return
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam == null or cam.global_position.distance_to(global_position) > 40.0:
			return
		pop()

	func pop() -> void:
		if _burst == null:
			_build()
		var s := size * scale_of()
		var a := randf() * TAU
		_burst.position = Vector3(cos(a), 0.0, sin(a)) * size * 0.12 + Vector3(0, size * 0.12, 0)
		_burst.initial_velocity_min = s * 2.2
		_burst.initial_velocity_max = s * 5.0
		_burst.restart()
		if _snd != null:
			if not FireFx._pop_sounds.is_empty():
				_snd.stream = FireFx._pop_sounds.pick_random()
			_snd.pitch_scale = randf_range(0.8, 1.25)
			_snd.volume_db = randf_range(-14.0, -5.0) + clampf(size - 0.6, -0.4, 0.6) * 8.0
			_snd.play()

	func scale_of() -> float:
		var p := get_parent() as Node3D
		return p.global_basis.get_scale().y if p != null and p.is_inside_tree() else 1.0

	func _build() -> void:
		var em := FireFx.embers(size, false)
		_burst = em.get_node("Sparks") as CPUParticles3D
		em.remove_child(_burst)
		em.free()
		_burst.name = "Burst"
		_burst.one_shot = true
		_burst.emitting = false
		_burst.explosiveness = 0.92
		_burst.amount = 9
		_burst.lifetime = 1.4
		_burst.randomness = 0.7
		_burst.emission_sphere_radius = size * 0.04
		_burst.direction = Vector3.UP
		_burst.spread = 50.0
		# Thrown out, they arc and fall back as they cool, not drift up like the rest.
		_burst.gravity = Vector3(0, -5.5, 0)
		_burst.damping_min = 0.4
		_burst.damping_max = 1.2
		_burst.tangential_accel_min = 0.0
		_burst.tangential_accel_max = 0.0
		_burst.visibility_range_end = 45.0
		add_child(_burst)
		if FireFx._pop_sounds.is_empty():
			for i in 4:
				var path := "res://assets/audio/sfx/fire/pop_%d.ogg" % i
				if ResourceLoader.exists(path):
					FireFx._pop_sounds.append(load(path))
		if not FireFx._pop_sounds.is_empty():
			_snd = AudioStreamPlayer3D.new()
			_snd.bus = "Effects"
			_snd.unit_size = 2.5
			_snd.max_distance = 35.0
			add_child(_snd)

static var _glass: ShaderMaterial

## A lit lantern's glass.
static func glass_material() -> ShaderMaterial:
	if _glass == null:
		_glass = ShaderMaterial.new()
		_glass.shader = load("res://src/world/lamp_glass.gdshader")
	return _glass

static var _coals: ShaderMaterial

## The glowing ember bed under a big fire.
static func coal_material() -> ShaderMaterial:
	if _coals == null:
		_coals = ShaderMaterial.new()
		_coals.shader = load("res://src/world/coals.gdshader")
	return _coals

## A flame that is carried about (a torch in hand): it trails behind the way it moves,
## and burns with the given seed, so the light that goes with it can follow it by
## FireFx.life(FireFx.time, seed) without finding it.
static func carried(size: float, seed: float) -> Node3D:
	var n := flame(size)
	n.set_meta("fire_seed", seed)
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).set_instance_shader_parameter("seed", seed)
		elif c is GPUParticles3D:
			((c as GPUParticles3D).process_material as ShaderMaterial).set_shader_parameter("seed", seed)
	n.add_child(Drag.new())
	return n

## Watches how fast its flame moves through the world and leans the flame's cards back
## against it, easing, so a swung torch streams and settles.
class Drag extends Node3D:
	var _last := Vector3.ZERO
	var _lean := Vector3.ZERO
	var _have := false

	func _init() -> void:
		name = "Drag"

	func _process(delta: float) -> void:
		var p := global_position
		if not _have or delta <= 0.0:
			_last = p
			_have = true
			return
		var v := (p - _last) / delta
		_last = p
		# Teleports and respawns would fling it: ignore anything faster than a sprint swing.
		if v.length() > 25.0:
			v = Vector3.ZERO
		var want := -v * 0.22
		want.y = 0.0
		var was := _lean
		_lean = _lean.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
		if _lean.length_squared() < 1e-6:
			_lean = Vector3.ZERO
		# A flame that stays put (a town's torches and hearths, most of them) has nothing
		# to send once it has settled.
		if _lean == was:
			return
		for c in get_parent().get_children():
			if c is MeshInstance3D and c.name != "Coals" and c.name != "Glass":
				(c as MeshInstance3D).set_instance_shader_parameter("drag", _lean)

static var _swirl: ShaderMaterial

## The door of light in a portal, flat in its node's XY plane and seen from both sides:
## the fullest frames of Ben's magic flipbook (assets/textures/fx/portal_swirl.png) turning
## one way, a larger copy turning slowly the other, over a deep violet that hides most of
## what is behind. `size` is the disc's diameter.
static func swirl(size: float, tint := Color(1, 1, 1, 1)) -> MeshInstance3D:
	if _swirl == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float fps = 2.5;
uniform float turn = 0.55;
instance uniform vec4 tint : source_color = vec4(1.0);
mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}
// The strip's four frames cross-faded in turn, at p (centred, frame half-width 0.5).
vec3 frames(vec2 p, float t) {
	vec2 q = clamp(p + 0.5, vec2(0.002), vec2(0.998));
	float f0 = mod(floor(t), 4.0);
	float f1 = mod(f0 + 1.0, 4.0);
	vec3 a = texture(tex, vec2((q.x + f0) / 4.0, q.y)).rgb;
	vec3 b = texture(tex, vec2((q.x + f1) / 4.0, q.y)).rgb;
	return mix(a, b, smoothstep(0.0, 1.0, fract(t)));
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	if (r > 0.5) {
		discard;
	}
	float t = TIME * fps;
	// The frames' swirl fills about nine tenths of each frame; scale it to the rim.
	vec3 c = frames(rot(TIME * turn) * p * 0.95, t);
	c += 0.45 * frames(rot(1.3 - TIME * turn * 0.45) * p * 1.4, t + 2.0);
	c *= tint.rgb * tint.a;
	float rim = smoothstep(0.5, 0.42, r);
	vec3 deep = vec3(0.07, 0.025, 0.15) * rim;
	ALBEDO = c + deep;
	ALPHA = clamp(max(c.r, max(c.g, c.b)) * 1.3 + 0.82 * rim, 0.0, 1.0);
}
"""
		_swirl = ShaderMaterial.new()
		_swirl.shader = sh
		var path := "res://assets/textures/fx/portal_swirl.png"
		if ResourceLoader.exists(path):
			_swirl.set_shader_parameter("tex", load(path))
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "Swirl"
	mi.mesh = q
	mi.material_override = _swirl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	mi.set_instance_shader_parameter("tint", tint)
	return mi

static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D

## A soft round dot, for sparks and smoke puffs.
static func _dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## A wisp: a round puff that thins out gently from the middle, with no hard rim (the
## plain dot made smoke into a dark ball hanging over a fire).
static func _wisp() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.add_point(0.35, Color(1, 1, 1, 0.32))
	g.add_point(0.7, Color(1, 1, 1, 0.08))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## Sparks that fly up off a flame `size` metres tall and die out, and with `smoke` a thin
## grey smoke rising above it. They are left behind in the world as the fire moves, so a
## swung torch trails them. Put it where the flame stands.
static func embers(size: float, smoke := true) -> Node3D:
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.albedo_texture = _dot()
		_spark_mat.disable_fog = true
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_texture = _wisp()
		_smoke_mat.roughness = 1.0
	var n := Node3D.new()
	n.name = "Embers"
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.amount = clampi(int(size * 28.0), 8, 28)
	p.lifetime = 1.3
	p.randomness = 0.6
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE * clampf(size * 0.05, 0.012, 0.03)
	q.material = _spark_mat
	p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.12
	p.position = Vector3(0, size * 0.25, 0)
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = size * 1.2
	p.initial_velocity_max = size * 3.2
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = size * 1.5
	p.damping_max = size * 3.0
	# Hot air tosses them about as they rise.
	p.tangential_accel_min = -size * 4.0
	p.tangential_accel_max = size * 4.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.15, 1.0))
	p.color_ramp = g
	n.add_child(p)
	if smoke:
		var s := CPUParticles3D.new()
		s.name = "Smoke"
		s.amount = 22
		s.lifetime = 2.8
		s.randomness = 0.5
		s.preprocess = 2.8
		s.local_coords = false
		var sq := QuadMesh.new()
		sq.size = Vector2.ONE * size * 0.5
		sq.material = _smoke_mat
		s.mesh = sq
		s.position = Vector3(0, size * 0.85, 0)
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		s.emission_sphere_radius = size * 0.18
		s.direction = Vector3.UP
		s.spread = 20.0
		s.initial_velocity_min = size * 0.8
		s.initial_velocity_max = size * 1.4
		s.gravity = Vector3(0, 0.15, 0)
		s.damping_min = size * 0.3
		s.damping_max = size * 0.6
		s.angle_min = 0.0
		s.angle_max = 360.0
		var ss := Curve.new()
		ss.add_point(Vector2(0, 0.35))
		ss.add_point(Vector2(1, 1.6))
		s.scale_amount_curve = ss
		var sg := Gradient.new()
		sg.set_color(0, Color(0.35, 0.33, 0.31, 0.0))
		sg.set_color(1, Color(0.42, 0.41, 0.4, 0.0))
		# Thin: fades in above the flame and is mostly gone before it rises far.
		sg.add_point(0.2, Color(0.4, 0.38, 0.36, 0.09))
		sg.add_point(0.55, Color(0.42, 0.41, 0.4, 0.05))
		s.color_ramp = sg
		n.add_child(s)
	for c in n.get_children():
		(c as CPUParticles3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(c as CPUParticles3D).visibility_range_end = 60.0
	return n
