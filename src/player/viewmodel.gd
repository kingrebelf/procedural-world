class_name Viewmodel
extends Node3D
## First-person view of what you hold. With the character assets present, your own arms
## (the player's body with everything but the arms cut away) grip the item; otherwise the
## item floats alone. Sway, swing and recoil move the whole rig.

static var _models: Dictionary = {}

var _mesh: MeshInstance3D
var _rest := Vector3(0.32, -0.3, -0.55)
var _swing_t := 1.0
var _recoil := 0.0
var _sway_t := 0.0
var _type := ""
var arms: HumanModel
var look: Dictionary = {} ## the player's appearance (set before adding to the tree)
const ARMS_REST := Vector3(0.08, -0.03, 0.0)

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	if HumanModel.available() and not look.is_empty():
		arms = HumanModel.new()
		arms.build(look, Eras.MEDIEVAL, "")
		arms.rotation.y = PI
		arms.position = Vector3(0, -1.55, 0.12)
		add_child(arms)
		arms.set_arms_only()
		arms.play("pistol_idle")
		# Settle the pose now (skip the cross-fade) so the grip is computed on it.
		arms.anim.advance(0.5)
	position = _rest

## The item as something a hand can hold: tools and weapons as models, anything else as
## its icon on a card.
static func prop_for(t: String) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	n.add_child(mi)
	var d := ItemDB.def(t)
	if d.get("kind", "") in ["tool", "weapon"] and model(t) != null:
		mi.mesh = model(t)
	else:
		var q := QuadMesh.new()
		q.size = Vector2(0.2, 0.2)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.albedo_texture = Icons.get_icon(t)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = Vector3(0, 0.12, 0)
	return n

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
		"hammer":
			k.cylinder(handle, I.translated(Vector3(0, -0.15, 0)), 0.016, 0.014, 0.42, 6)
			k.box(head, I.translated(Vector3(0, 0.08, 0)), Vector3(0.16, 0.06, 0.06))
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
	if arms:
		_mesh.mesh = null
		_rest = ARMS_REST
		_hold_later.call_deferred(t)
		return
	_mesh.mesh = model(t) if t != "" else null
	if t.begins_with("pulse"):
		_mesh.rotation = Vector3(0, 0, 0)
		_rest = Vector3(0.22, -0.2, -0.45)
	else:
		_mesh.rotation = Vector3(-0.35, 0.25, 0.15)
		_rest = Vector3(0.32, -0.3, -0.55)

## Puts the item in the arms' hand once the pose has been applied this frame.
func _hold_later(t: String) -> void:
	if t != _type or not is_inside_tree():
		return
	await get_tree().process_frame
	if t != _type:
		return
	arms.hold(prop_for(t) if t != "" else null)
	_aim()

## Keeps the held item pointing the right way on screen: tools up and away, guns forward.
func _aim() -> void:
	if arms == null or _type == "":
		return
	# The rig's own frame, so the item swings with the arms.
	var b := global_transform.basis.orthonormalized()
	if ItemDB.def(_type).get("ranged", false):
		arms.reaim(arms.hand_space(b * Vector3.UP), 0.0, arms.hand_space(b * Vector3.FORWARD))
	else:
		arms.reaim(arms.hand_space(b * Vector3(0.25, 0.8, -0.6)), 0.6)

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
	if arms:
		# The whole rig swings down and across from just in front of the eyes.
		position = _rest + off + Vector3(-0.05 * s, -0.06 * s, -0.12 * s) + Vector3(0, 0, _recoil * 0.04)
		rotation = Vector3(-0.9 * s + _recoil * 0.12, 0.25 * s, 0.35 * s)
		_aim()
		return
	position = _rest + off + Vector3(-0.12 * s, 0.05 * s, -0.1 * s)
	rotation = Vector3(-1.1 * s + _recoil * 0.25, 0.3 * s, 0.3 * s)

func tracer(world_end: Vector3) -> void:
	var from := _mesh.global_position if arms == null else global_position + global_transform.basis * Vector3(0, -0.12, -0.5)
	var start := from + -global_transform.basis.z * 0.25
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
