class_name Splashes
extends Node3D
## Splashes and ripples on water: where something hits the surface, a crown of droplets
## thrown up and out (streaks drawn along their flight), a jet of water for a hard
## landing, and a little spray; ring waves that run out across the water (drawn by the
## water shaders, water_rings.gdshaderinc, so they bend its reflections), with a thin
## lace of foam riding them. Pooled, so a busy swim never makes new nodes. Water creates
## the one instance; the static calls are safe (and do nothing) before it exists, e.g.
## in tests.

const BURSTS := 8
const RINGS := 24
## Ring waves the water shaders draw at once (the size of their `rings` array).
const WAVES := 12
const WAVE_LIFE := 4.5

static var _fx: Splashes
var _bursts: Array[GPUParticles3D] = []
var _jets: Array[GPUParticles3D] = []
var _spray: Array[GPUParticles3D] = []
var _waves := PackedVector4Array()
var _next_wave := 0
var _waves_shown := false
var _next_burst := 0
var _rings: Array[MeshInstance3D] = []
var _ring_age: PackedFloat32Array
var _ring_life: PackedFloat32Array
var _next_ring := 0

## A burst of droplets at pos (on the surface). strength ~0.1 for a stroke, 1 for a
## jump in, 1.6 for a fall from a height.
static func splash(pos: Vector3, strength: float) -> void:
	if is_instance_valid(_fx):
		_fx._splash(pos, strength)

## A ring of foam spreading from pos to about `size` metres across.
static func ring(pos: Vector3, size: float) -> void:
	if is_instance_valid(_fx):
		_fx._ring(pos, size)

func _ready() -> void:
	_fx = self
	top_level = true
	_waves.resize(WAVES)
	var dot := _dot_texture(Color(1, 1, 1, 0.75))
	var drop := _dot_texture(Color(1, 1, 1, 0.95))
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.7, Color(1, 1, 1, 0.7))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	var mist := Gradient.new()
	mist.set_color(0, Color(1, 1, 1, 0.0))
	mist.set_color(1, Color(1, 1, 1, 0.0))
	mist.add_point(0.15, Color(1, 1, 1, 0.18))
	var mist_tex := GradientTexture1D.new()
	mist_tex.gradient = mist
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.5))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	for i in BURSTS:
		# The crown: droplets thrown up and outward from a ring round the spot, falling back
		# under gravity, each a short streak along its flight as a fast drop looks.
		var drops := _emitter(72, 1.1, drop, Vector2(0.045, 0.16), true)
		var pm := drops.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 22.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.5
		pm.radial_velocity_min = 0.6
		pm.radial_velocity_max = 2.2
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.3
		pm.emission_ring_inner_radius = 0.18
		pm.emission_ring_height = 0.05
		pm.scale_min = 0.6
		pm.scale_max = 1.5
		pm.scale_curve = shrink_tex
		pm.color_ramp = fade_tex
		_bursts.append(drops)
		# The jet: after a hard landing a column of water shoots up from the middle.
		var jet := _emitter(28, 1.2, drop, Vector2(0.05, 0.2), true)
		pm = jet.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 7.0
		pm.initial_velocity_min = 3.5
		pm.initial_velocity_max = 6.5
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.1
		pm.scale_min = 0.7
		pm.scale_max = 1.6
		pm.scale_curve = shrink_tex
		pm.color_ramp = fade_tex
		jet.explosiveness = 0.6
		_jets.append(jet)
		# Spray: a faint, fine mist that billows a little and settles.
		var spray := _emitter(10, 1.3, dot, Vector2(0.6, 0.6), false)
		pm = spray.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 50.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.6
		pm.gravity = Vector3(0, -1.5, 0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35
		pm.scale_curve = grow_tex
		pm.color_ramp = mist_tex
		_spray.append(spray)
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = load("res://src/env/ripple.gdshader")
	ring_mat.render_priority = 1 # over the water surface
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	_ring_age.resize(RINGS)
	_ring_life.resize(RINGS)
	for i in RINGS:
		var m := MeshInstance3D.new()
		m.mesh = plane
		m.material_override = ring_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_rings.append(m)
		_ring_life[i] = 1.0
		_ring_age[i] = 1.0

## A soft round dot, opaque `core` in the middle fading to nothing at the rim.
static func _dot_texture(core: Color) -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, core)
	dot.gradient = g
	dot.width = 32
	dot.height = 32
	return dot

## streak: drawn as a quad stretched along the particle's flight (for droplets), else a
## camera-facing billboard (for spray).
func _emitter(amount: int, life: float, tex: Texture2D, size: Vector2, streak: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 10, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if streak:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if streak else BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.roughness = 0.12 if streak else 0.6
	mat.disable_receive_shadows = true
	if not streak:
		# Mist fades out where it meets the water instead of cutting a hard line.
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p

func _splash(pos: Vector3, strength: float) -> void:
	var s := clampf(strength, 0.05, 2.0)
	var i := _next_burst
	_next_burst = (_next_burst + 1) % BURSTS
	var drops := _bursts[i]
	drops.global_position = pos
	drops.amount_ratio = clampf(0.2 + s * 0.55, 0.12, 1.0)
	var pm := drops.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = 2.0 * (0.4 + s * 0.6)
	pm.initial_velocity_max = 4.5 * (0.4 + s * 0.6)
	pm.radial_velocity_max = 2.2 * (0.5 + s * 0.5)
	pm.emission_ring_radius = 0.18 + s * 0.15
	pm.emission_ring_inner_radius = pm.emission_ring_radius * 0.6
	drops.restart()
	var jet := _jets[i]
	jet.visible = s > 0.5
	if jet.visible:
		jet.global_position = pos
		jet.amount_ratio = clampf((s - 0.4) * 0.8, 0.2, 1.0)
		pm = jet.process_material as ParticleProcessMaterial
		pm.initial_velocity_min = 3.5 * (0.6 + s * 0.4)
		pm.initial_velocity_max = 6.5 * (0.6 + s * 0.4)
		jet.restart()
	var spray := _spray[i]
	spray.visible = s > 0.25
	if spray.visible:
		spray.global_position = pos
		spray.amount_ratio = clampf(s * 0.6, 0.2, 1.0)
		spray.restart()
	_ring(pos, 1.5 + s * 2.5)

func _ring(pos: Vector3, size: float) -> void:
	var i := _next_ring
	_next_ring = (_next_ring + 1) % RINGS
	var m := _rings[i]
	m.global_position = pos + Vector3(0, 0.04, 0)
	m.scale = Vector3.ONE * maxf(size, 0.3)
	m.rotation.y = randf() * TAU
	m.visible = true
	_ring_age[i] = 0.0
	_ring_life[i] = 1.2 + size * 0.25
	m.set_instance_shader_parameter("age", 0.0)
	var w := _next_wave
	_next_wave = (_next_wave + 1) % WAVES
	_waves[w] = Vector4(pos.x, pos.z, 0.0, clampf(size * 0.3, 0.1, 1.6))

func _process(delta: float) -> void:
	_age_waves(delta)
	for i in RINGS:
		var m := _rings[i]
		if not m.visible:
			continue
		_ring_age[i] += delta
		var t := _ring_age[i] / _ring_life[i]
		if t >= 1.0:
			m.visible = false
			continue
		m.set_instance_shader_parameter("age", t)
		# Ride the swell rather than float above it or sink into it.
		var c := m.global_position
		m.global_position.y = Water.surface_height(c.x, c.z, _water_t()) + 0.04

## Ages the ring waves, frees the spent ones, and hands the list to the lake and river
## shaders.
func _age_waves(delta: float) -> void:
	var live := false
	for w in WAVES:
		var v := _waves[w]
		if v.w <= 0.0:
			continue
		v.z += delta
		if v.z > WAVE_LIFE:
			v = Vector4.ZERO
		else:
			live = true
		_waves[w] = v
	if not live and not _waves_shown:
		return
	_waves_shown = live
	var lake := get_parent() as GeometryInstance3D
	if lake and lake.material_override is ShaderMaterial:
		(lake.material_override as ShaderMaterial).set_shader_parameter("rings", _waves)
	if ChunkNode.river_material:
		ChunkNode.river_material.set_shader_parameter("rings", _waves)

static func _water_t() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
