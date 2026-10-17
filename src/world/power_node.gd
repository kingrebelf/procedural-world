class_name PowerNode
extends Node3D
## One powered piece's moving and lit parts in the scene (its still parts are in the
## chunk's MultiMesh like any piece): a lamp's bulb and light, a windmill's head and sails,
## a knife switch's blade, an engine's exhaust smoke. PowerGrid tells it each tick what the
## piece is doing (apply); it eases toward that, so lamps warm up and fade like filaments
## and sails spin up and run down instead of snapping.

var chunk: ChunkNode
var obj_i := -1
var _spec := {}
var _light: Light3D
var _bulb: MeshInstance3D
var _bulb_mat: StandardMaterial3D
var _glow := 0.0 ## 0 dark .. 1 fully lit, as drawn
var _lit := false ## what the grid says
var _head: Node3D
var _rotor: Node3D
var _spin := 0.0 ## rad/s the sails turn at, as drawn
var _blade: Node3D
var _closed := true
var _blade_a := 0.0 ## 0 open / off .. 1 closed / on, as drawn
var _blade_spec := {}
var _smoke: Node3D
var _running := false

const BULB_ENERGY := 5.0 ## a lit bulb's own brightness (it lights; nothing else glows)
const FILAMENT := 7.0 ## of full brightness per second a bulb warms up or fades
const OPEN_ANGLE := -1.75 ## how far an open knife switch's blade hangs out

func setup(c: ChunkNode, o: Dictionary) -> void:
	chunk = c
	obj_i = int(o["i"])
	name = "Power_%d" % obj_i
	_spec = Power.spec(o)
	position = o["p"]
	rotation.y = o["r"]
	if _spec.has("lamp"):
		_make_lamp(_spec["lamp"])
	if _spec.get("source", "") == "wind":
		_head = Node3D.new()
		_head.position = Vector3(0, float(_spec.get("head", 7.8)), 0)
		_head.add_child(_mesh("windmill_head"))
		_rotor = Node3D.new()
		_rotor.position = Vector3(0, 0.3, 0.86)
		_rotor.add_child(_mesh("windmill_rotor"))
		_head.add_child(_rotor)
		add_child(_head)
		# Start facing the wind, not turning round from north the moment you arrive.
		var g := PowerGrid.current
		if g != null:
			_head.global_rotation.y = _wind_yaw(g.wind_dir)
	var bl: Dictionary = _spec.get("blade", {})
	if bl.is_empty() and _spec.get("role", "") == "switch" and not _spec.has("logic"):
		bl = {"part": "switch_blade", "pos": Vector3(0, -0.1, 0.07), "on": 0.0, "off": OPEN_ANGLE}
	if not bl.is_empty():
		# A part that swings (knife blade, lever) or is pushed in (button, plate).
		_blade_spec = bl
		_blade = Node3D.new()
		_blade.position = bl["pos"]
		_blade.add_child(_mesh(String(bl["part"])))
		add_child(_blade)
		_closed = Power.is_on(o) if Signals.kind(o) in ["", "lever"] else bool(o["st"].get("sg", false))
		_blade_a = 1.0 if _closed else 0.0
		_pose_blade()
	if _spec.has("smoke"):
		_smoke = FireFx.embers(0.9, true)
		var sparks := _smoke.get_node_or_null("Sparks")
		if sparks != null:
			_smoke.remove_child(sparks)
			sparks.free()
		_smoke.position = (_spec["smoke"] as Vector3) - Vector3(0, 0.75, 0)
		add_child(_smoke)
		_set_smoke(false)
	set_process(_head != null or _blade != null or _spec.has("lamp"))

func _mesh(part: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = PowerKit.part(part)
	mi.visibility_range_end = 400.0
	return mi

func _make_lamp(l: Dictionary) -> void:
	_bulb = _mesh(String(l.get("part", "bulb")))
	_bulb.position = l["pos"]
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(0.92, 0.9, 0.85, 0.55)
	_bulb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_bulb_mat.roughness = 0.08
	_bulb_mat.metallic_specular = 0.9
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = l.get("color", Color(1.0, 0.8, 0.58))
	_bulb_mat.emission_energy_multiplier = 0.0
	_bulb.material_override = _bulb_mat
	_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulb)
	var spot := float(l.get("spot", 0.0))
	if spot > 0.0:
		var s := SpotLight3D.new()
		s.spot_range = float(l["range"])
		s.spot_angle = spot
		s.spot_attenuation = 0.9
		s.spot_angle_attenuation = 1.6
		s.rotation.x = deg_to_rad(float(l.get("aim", 0.0)))
		_light = s
	else:
		var o := OmniLight3D.new()
		o.omni_range = float(l["range"])
		o.omni_attenuation = 1.4
		_light = o
	_light.light_color = l.get("color", Color(1.0, 0.8, 0.58))
	_light.light_energy = 0.0
	_light.position = l.get("light_at", l["pos"])
	if _light is OmniLight3D:
		ChunkNode._cast_shadows(_light)
	else:
		_spot_shadows(_light)
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 70.0 if spot > 0.0 else 45.0
	_light.distance_fade_length = 15.0
	_light.visible = false
	add_child(_light)

static func _spot_shadows(l: Light3D) -> void:
	l.shadow_enabled = true
	l.shadow_bias = 0.03
	l.shadow_normal_bias = 1.0
	l.shadow_blur = 1.2
	l.light_size = 0.08
	l.distance_fade_shadow = 40.0

## What the piece is doing this tick: lit (a lamp with power and switched on), running
## (an engine burning or a windmill's dynamo turning), closed (a switch closed, a lever
## on, a button or plate pressed).
func apply(lit: bool, running: bool, closed: bool) -> void:
	_lit = lit
	if _closed != closed:
		_closed = closed
	if _running != running:
		_running = running
		_set_smoke(running and _smoke != null)
	if not is_processing() and (_light != null or _blade != null or _head != null):
		set_process(true)

func _pose_blade() -> void:
	if _blade_spec.has("push"):
		_blade.position = (_blade_spec["pos"] as Vector3) + (_blade_spec["push"] as Vector3) * _blade_a
	else:
		_blade.rotation.x = lerpf(float(_blade_spec.get("off", OPEN_ANGLE)), float(_blade_spec.get("on", 0.0)), _blade_a)

func _set_smoke(on: bool) -> void:
	if _smoke == null:
		return
	for c in _smoke.get_children():
		(c as CPUParticles3D).emitting = on

static func _wind_yaw(wind_dir: Vector2) -> float:
	# The sails face into the wind (their local +z upwind), the tail vane downwind.
	return atan2(-wind_dir.x, -wind_dir.y)

func _process(delta: float) -> void:
	var busy := false
	if _light != null:
		var want := 1.0 if _lit else 0.0
		_glow = move_toward(_glow, want, delta * FILAMENT)
		# A filament's light goes as a power of its temperature: it reddens as it fades.
		var g := _glow * _glow
		var l: Dictionary = _spec["lamp"]
		_light.light_energy = float(l["energy"]) * g
		_light.visible = _glow > 0.01
		var base: Color = l.get("color", Color(1.0, 0.8, 0.58))
		_light.light_color = base.lerp(Color(1.0, 0.45, 0.2), 1.0 - _glow)
		_bulb_mat.emission = _light.light_color
		_bulb_mat.emission_energy_multiplier = BULB_ENERGY * g
		busy = busy or not is_equal_approx(_glow, want)
	if _blade != null:
		var a := 1.0 if _closed else 0.0
		_blade_a = move_toward(_blade_a, a, delta * (12.0 if _blade_spec.has("push") else 5.0))
		_pose_blade()
		busy = busy or not is_equal_approx(_blade_a, a)
	if _head != null:
		var g := PowerGrid.current
		var wind := g.wind if g != null else 0.3
		var want_spin := (0.4 + Power.wind_curve(wind) * 2.6) if Power.is_on(chunk.get_object(obj_i)) and wind > 0.06 else 0.0
		_spin = move_toward(_spin, want_spin, delta * 0.35)
		_rotor.rotation.z += _spin * delta
		if g != null:
			var yaw := _wind_yaw(g.wind_dir)
			_head.global_rotation.y = lerp_angle(_head.global_rotation.y, yaw, clampf(delta * 0.25, 0.0, 1.0))
		busy = true
	if not busy:
		set_process(false)
