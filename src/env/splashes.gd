class_name Splashes
extends Node3D
## Splashes and ripples on water: a burst of droplets and spray where something hits the
## surface, and foam rings that spread and fade where you swim, wade or fall in. Pooled,
## so a busy swim never makes new nodes. Water creates the one instance; the static
## calls are safe (and do nothing) before it exists, e.g. in tests.

const BURSTS := 8
const RINGS := 24

static var _fx: Splashes
var _bursts: Array[GPUParticles3D] = []
var _spray: Array[GPUParticles3D] = []
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
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	dot.gradient = g
	dot.width = 32
	dot.height = 32
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.35))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	for i in BURSTS:
		# Droplets: thrown up and out, falling back under gravity.
		var drops := _emitter(48, 1.1, dot, Vector2(0.09, 0.09))
		var pm := drops.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 28.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 5.5
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		pm.scale_curve = shrink_tex
		pm.color_ramp = fade_tex
		_bursts.append(drops)
		# Spray: a soft white cloud that billows and drifts down.
		var spray := _emitter(14, 1.4, dot, Vector2(0.7, 0.7))
		pm = spray.process_material as ParticleProcessMaterial
		pm.direction = Vector3.UP
		pm.spread = 50.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 2.2
		pm.gravity = Vector3(0, -2.0, 0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.4
		pm.scale_curve = grow_tex
		pm.color_ramp = fade_tex
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

func _emitter(amount: int, life: float, tex: Texture2D, size: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.92, 0.96, 1.0)
	mat.roughness = 0.4
	mat.disable_receive_shadows = true
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p

func _splash(pos: Vector3, strength: float) -> void:
	var s := clampf(strength, 0.05, 2.0)
	var i := _next_burst
	_next_burst = (_next_burst + 1) % BURSTS
	for p: GPUParticles3D in [_bursts[i], _spray[i]]:
		p.global_position = pos
		p.amount_ratio = clampf(0.25 + s * 0.6, 0.15, 1.0)
		p.speed_scale = 1.0
		var pm := p.process_material as ParticleProcessMaterial
		var big := p == _spray[i]
		pm.initial_velocity_min = (0.6 if big else 2.0) * (0.5 + s * 0.6)
		pm.initial_velocity_max = (2.2 if big else 5.5) * (0.5 + s * 0.6)
		p.restart()
	_spray[i].visible = s > 0.25
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

func _process(delta: float) -> void:
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

static func _water_t() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
