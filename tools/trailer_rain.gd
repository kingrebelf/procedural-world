extends Node3D
## Close-up rain for the trailer (tools/trailer.gd): drops falling round a spot in front
## of the camera, each landing with a tiny crown of droplets, and a puddle there whose
## surface rings out from exactly where each drop hits it (tools/trailer_puddle.gdshader).
## The game's own rain stays clear of the camera's first metre or two, which is just
## where these fall.

const POOL := 260
const CROWNS := 32
const RINGS := 24
const FALL := 8.5 ## metres per second

var _center := Vector3.ZERO
var _area := 2.0
var _rate := 60.0
var _on := false
var _drops: Array[MeshInstance3D] = []
var _vel := PackedFloat32Array()
var _crowns: Array[GPUParticles3D] = []
var _next_crown := 0
var _puddle: MeshInstance3D
var _puddle_mat: ShaderMaterial
var _probe: ReflectionProbe
var _rings := PackedVector4Array()
var _next_ring := 0
var _owed := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	_rng.seed = 4242
	var q := QuadMesh.new()
	q.size = Vector2(0.011, 0.22)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.6)
	m.roughness = 0.05
	m.disable_receive_shadows = true
	q.material = m
	for i in POOL:
		var d := MeshInstance3D.new()
		d.mesh = q
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		_drops.append(d)
	_vel.resize(POOL)
	var cq := QuadMesh.new()
	cq.size = Vector2(0.004, 0.014)
	var cm := m.duplicate() as StandardMaterial3D
	cm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.albedo_color = Color(0.9, 0.94, 1.0, 0.55)
	cq.material = cm
	for i in CROWNS:
		var p := GPUParticles3D.new()
		p.amount = 10
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.local_coords = false
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		var pm := ParticleProcessMaterial.new()
		pm.gravity = Vector3(0, -9.8, 0)
		pm.direction = Vector3.UP
		pm.spread = 32.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.4
		pm.radial_velocity_min = 0.15
		pm.radial_velocity_max = 0.55
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.012
		pm.emission_ring_inner_radius = 0.006
		pm.emission_ring_height = 0.002
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		p.process_material = pm
		p.draw_pass_1 = cq
		add_child(p)
		_crowns.append(p)
	_puddle_mat = ShaderMaterial.new()
	_puddle_mat.shader = load("res://tools/trailer_puddle.gdshader")
	_puddle = MeshInstance3D.new()
	var pl := PlaneMesh.new()
	_puddle.mesh = pl
	_puddle.material_override = _puddle_mat
	_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puddle.visible = false
	add_child(_puddle)
	_rings.resize(RINGS)
	# What the puddle mirrors where the screen has nothing to reflect (above the frame).
	_probe = ReflectionProbe.new()
	_probe.size = Vector3(40, 16, 40)
	_probe.box_projection = true
	_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	_probe.visible = false
	add_child(_probe)

## Rain round `center` (on the ground) over a square `area` metres either side, `rate`
## drops a second, with a puddle `radius` metres across lying there.
func start(center: Vector3, area: float, radius: float, rate: float) -> void:
	_center = center
	_area = area
	_rate = rate
	_on = true
	(_puddle.mesh as PlaneMesh).size = Vector2(radius * 2.4, radius * 2.4)
	_puddle.global_position = center + Vector3(0, 0.012, 0)
	_puddle_mat.set_shader_parameter("radius", radius)
	_puddle.visible = true
	_probe.global_position = center + Vector3(0, 1.2, 0)
	_probe.visible = true
	_rings.fill(Vector4.ZERO)

func stop() -> void:
	_on = false
	_puddle.visible = false
	_probe.visible = false
	for d in _drops:
		d.visible = false

func _process(delta: float) -> void:
	if not _on:
		return
	_t += delta
	_owed += _rate * delta
	for i in POOL:
		var d := _drops[i]
		if not d.visible:
			if _owed >= 1.0:
				_owed -= 1.0
				d.global_position = _center + Vector3(_rng.randf_range(-_area, _area), _rng.randf_range(0.5, 4.5), _rng.randf_range(-_area, _area))
				_vel[i] = FALL * _rng.randf_range(0.9, 1.1)
				d.visible = true
			continue
		var p := d.global_position
		p.y -= _vel[i] * delta
		if p.y <= _center.y:
			d.visible = false
			_land(Vector3(p.x, _center.y, p.z))
			continue
		d.global_position = p
	_puddle_mat.set_shader_parameter("now", _t)
	_puddle_mat.set_shader_parameter("drops", _rings)

func _land(at: Vector3) -> void:
	var c := _crowns[_next_crown]
	_next_crown = (_next_crown + 1) % CROWNS
	c.global_position = at + Vector3(0, 0.014, 0)
	c.restart()
	var local := at - _puddle.global_position
	_rings[_next_ring] = Vector4(local.x, local.z, _t, _rng.randf_range(0.7, 1.0))
	_next_ring = (_next_ring + 1) % RINGS
