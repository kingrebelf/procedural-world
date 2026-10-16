class_name Viewmodel
extends Node3D
## First-person held item: procedural tool and weapon models with sway, swing and recoil.

static var _models: Dictionary = {}

var _mesh: MeshInstance3D
var _rest := Vector3(0.32, -0.3, -0.55)
var _swing_t := 1.0
var _recoil := 0.0
var _sway_t := 0.0
var _type := ""

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	position = _rest

static func model(t: String) -> ArrayMesh:
	if _models.has(t):
		return _models[t]
	var k := MeshKit.new(3)
	var I := Transform3D.IDENTITY
	var handle := "timber"
	var head := "iron"
	if t.ends_with("mythril"):
		head = "crystal"
	match t:
		"pickaxe_iron", "pickaxe_mythril":
			k.cylinder(handle, I.translated(Vector3(0, -0.25, 0)), 0.018, 0.016, 0.62, 6)
			k.box(head, Transform3D(Basis(Vector3(0, 0, 1), 0.12), Vector3(0, 0.36, 0)), Vector3(0.42, 0.05, 0.05))
			k.box(head, I.translated(Vector3(0, 0.36, 0)), Vector3(0.07, 0.08, 0.07))
		"axe_iron", "axe_mythril":
			k.cylinder(handle, I.translated(Vector3(0, -0.25, 0)), 0.018, 0.016, 0.62, 6)
			k.box(head, I.translated(Vector3(0.07, 0.3, 0)), Vector3(0.14, 0.16, 0.02))
		"pickaxe_plasma":
			k.box("metal_dark", I, Vector3(0.08, 0.32, 0.1))
			k.cylinder("iron", I.translated(Vector3(0, 0.16, 0)), 0.03, 0.01, 0.28, 8)
			k.box("glow_cyan", I.translated(Vector3(0, 0.0, 0.051)), Vector3(0.03, 0.2, 0.01))
		"sword_iron", "sword_runic":
			k.box(handle, I.translated(Vector3(0, -0.12, 0)), Vector3(0.035, 0.18, 0.035))
			k.box("gold" if t == "sword_runic" else "iron", I.translated(Vector3(0, -0.02, 0)), Vector3(0.18, 0.025, 0.04))
			k.box("crystal" if t == "sword_runic" else "iron", I.translated(Vector3(0, 0.33, 0)), Vector3(0.05, 0.68, 0.012))
		"pulse_pistol":
			k.box("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -0.25), Vector3(0, -0.08, 0.04)), Vector3(0.05, 0.14, 0.06))
			k.box("metal", I.translated(Vector3(0, 0.0, -0.06)), Vector3(0.06, 0.07, 0.26))
			k.box("glow_cyan", I.translated(Vector3(0, 0.038, -0.06)), Vector3(0.02, 0.005, 0.2))
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.0, -0.18)), 0.02, 0.02, 0.06, 8)
		_:
			var def := ItemDB.def(t)
			if def.is_empty():
				return null
			k.box("painted", I, Vector3(0.12, 0.12, 0.12), def.get("color", Color.WHITE))
	_models[t] = k.commit(Materials.get_mat)
	return _models[t]

func show_item(t: String) -> void:
	_type = t
	_mesh.mesh = model(t) if t != "" else null
	if t.begins_with("pulse"):
		_mesh.rotation = Vector3(0, 0, 0)
		_rest = Vector3(0.22, -0.2, -0.45)
	else:
		_mesh.rotation = Vector3(-0.35, 0.25, 0.15)
		_rest = Vector3(0.32, -0.3, -0.55)

func swing() -> void:
	_swing_t = 0.0

func recoil() -> void:
	_recoil = 1.0

func sway(delta: float, speed: float) -> void:
	_sway_t += delta * (1.0 + speed * 6.0)
	_swing_t = minf(1.0, _swing_t + delta * 2.4)
	_recoil = maxf(0.0, _recoil - delta * 8.0)
	var s := sin(_swing_t * PI)
	var off := Vector3(sin(_sway_t) * 0.006 * (1.0 + speed * 3.0), absf(cos(_sway_t)) * 0.006 * (1.0 + speed * 3.0), _recoil * 0.06)
	position = _rest + off + Vector3(-0.12 * s, 0.05 * s, -0.1 * s)
	rotation = Vector3(-1.1 * s + _recoil * 0.25, 0.3 * s, 0.3 * s)

func tracer(world_end: Vector3) -> void:
	var start := _mesh.global_position + -global_transform.basis.z * 0.25
	var len := start.distance_to(world_end)
	if len < 0.1:
		return
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = len
	cm.radial_segments = 6
	beam.mesh = cm
	beam.material_override = Materials.get_mat("glow_cyan")
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(beam)
	var mid := (start + world_end) * 0.5
	beam.global_position = mid
	var dir := (world_end - start).normalized()
	beam.global_transform.basis = Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else Basis()
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(0.1, 1, 0.1), 0.12)
	tw.tween_callback(beam.queue_free)
