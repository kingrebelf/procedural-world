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
# Defences (Defences): a turret's or searchlight's turning head and tipping gun, a flame
# trap's jet, an alarm bell's clapper.
var _turn: Node3D ## turns about y
var _tip: Node3D ## tips about x, inside _turn
var _aim_at = null ## world point to aim at, or null (a searchlight then sweeps)
var _sweep := 0.0
var _flame: Node3D
var _flame_on := false
var _clapper: Node3D
var _ring := 0.0
var _flash: OmniLight3D
var _flash_t := 0.0
var _smoke_mat: StandardMaterial3D

const TURN_SPEED := 2.4 ## rad/s a turret head turns

# Automation (Automation): a belt's riding items, a machine's turning part, an arm.
var _belt: MultiMeshInstance3D
var _belt_q: Array = [] ## [[colour, how far along], ...] as drawn
var _belt_v := 0.0
var _spinner: Node3D
var _spin_axis := Vector3.UP
var _spin_rate := 0.0
var _spin_max := 9.0
var _piston: MeshInstance3D ## a crosshead the crank drives, or null
var _piston_spec := {}
var _crank := 0.0
var _machine_on := false
var _arm: Node3D
var _arm_t := 0.0

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
	var df: Dictionary = _spec.get("defence", {})
	if df.has("head"):
		_turn = Node3D.new()
		_turn.position = df["head"]
		if df.has("head_part"):
			_turn.add_child(_mesh(String(df["head_part"])))
		_tip = Node3D.new()
		_tip.position = df.get("tip_at", Vector3.ZERO)
		if df.has("gun_part"):
			_tip.add_child(_mesh(String(df["gun_part"])))
		_turn.add_child(_tip)
		add_child(_turn)
	if df.has("nozzle"):
		_flame = FireFx.flame(1.6, Color(1, 0.85, 0.7, 1), "jet", true)
		_flame.position = df["nozzle"]
		_flame.rotation.x = PI * 0.5 # the jet hangs along -y: tip it out along -z
		_flame.visible = false
		add_child(_flame)
	if df.has("clapper"):
		_clapper = Node3D.new()
		_clapper.position = df["clapper"]
		_clapper.add_child(_mesh("bell_clapper"))
		add_child(_clapper)
	var au: Dictionary = _spec.get("auto", {})
	if au.get("kind", "") == "belt":
		_belt = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.14, 0.22)
		mm.mesh = bm
		mm.instance_count = 4
		mm.visible_instance_count = 0
		_belt.multimesh = mm
		var bmat := StandardMaterial3D.new()
		bmat.vertex_color_use_as_albedo = true
		bmat.roughness = 0.8
		_belt.material_override = bmat
		add_child(_belt)
	if au.has("spin") or _spec.has("spin"):
		var sp: Dictionary = au.get("spin", _spec.get("spin", {}))
		_spin_max = float(sp.get("rate", 9.0))
		_spinner = Node3D.new()
		_spinner.position = sp["pos"]
		_spinner.add_child(_mesh(String(sp["part"])))
		_spin_axis = sp.get("axis", Vector3.UP)
		add_child(_spinner)
		if sp.has("piston"):
			# A crosshead or piston driven off the spinner's crank, to and fro.
			_piston_spec = sp["piston"]
			_piston = _mesh(String(_piston_spec["part"]))
			_piston.position = _piston_spec["pos"]
			add_child(_piston)
	if au.has("arm"):
		_arm = Node3D.new()
		_arm.position = au["arm"]
		_arm.add_child(_mesh("robot_arm"))
		add_child(_arm)
	if _spec.has("lamp"):
		_make_lamp(_spec["lamp"])
		if _tip != null:
			# A searchlight's lamp turns with its head.
			for n in [_bulb, _light]:
				n.reparent(_tip, false)
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
	set_process(_head != null or _blade != null or _spec.has("lamp") or _turn != null or _belt != null)

func _mesh(part: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = PowerKit.part(part)
	mi.visibility_range_end = 400.0
	return mi

func _make_lamp(l: Dictionary) -> void:
	_bulb = _mesh(String(l.get("part", "bulb")))
	_bulb.position = l["pos"]
	if float(l.get("spot", 0.0)) > 0.0:
		_bulb.rotation.x = deg_to_rad(float(l.get("aim", 0.0)))
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
		o.omni_attenuation = float(l.get("atten", 1.4))
		_light = o
	_light.light_color = l.get("color", Color(1.0, 0.8, 0.58))
	_light.light_energy = 0.0
	_light.position = l.get("light_at", l["pos"])
	if _light is OmniLight3D:
		ChunkNode._cast_shadows(_light)
		_light.light_size = float(l.get("soft", _light.light_size))
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
	if not is_processing() and (_light != null or _blade != null or _head != null or _spinner != null):
		set_process(true)

func _pose_blade() -> void:
	if _blade_spec.has("push"):
		_blade.position = (_blade_spec["pos"] as Vector3) + (_blade_spec["push"] as Vector3) * _blade_a
	else:
		_blade.rotation.x = lerpf(float(_blade_spec.get("off", OPEN_ANGLE)), float(_blade_spec.get("on", 0.0)), _blade_a)

## A turret or searchlight aims at a world point, or (null) settles back / sweeps.
func aim(at) -> void:
	_aim_at = at
	if not is_processing():
		set_process(true)

## The barrels are on `at` (near enough to shoot).
func on_target(at: Vector3) -> bool:
	if _turn == null:
		return true
	var want := _yaw_to(at)
	return absf(angle_difference(_turn.rotation.y, want)) < 0.12

func _yaw_to(at: Vector3) -> float:
	var local := global_transform.affine_inverse() * at - (_turn.position if _turn != null else Vector3.ZERO)
	return atan2(-local.x, -local.z)

## Where the shot leaves the barrel, in world space.
func muzzle() -> Vector3:
	var m: Vector3 = (_spec.get("defence", {}) as Dictionary).get("muzzle", Vector3(0, 0, -0.8))
	return _tip.global_transform * m if _tip != null else global_position + Vector3(0, 1, 0)

## A shot at `at`: the muzzle flash (real fire: a flash of powder flame and its light), a
## puff of smoke along the shot and a strike where it lands.
func shot(at: Vector3) -> void:
	var from := muzzle()
	if _flash == null:
		_flash = OmniLight3D.new()
		_flash.light_color = Color(1.0, 0.72, 0.4)
		_flash.omni_range = 7.0
		_flash.shadow_enabled = false
		add_child(_flash)
	_flash.global_position = from
	_flash.light_energy = 3.0
	_flash.visible = true
	_flash_t = 0.06
	var fl := FireFx.flame(0.35, Color(1, 0.9, 0.7, 1), "fire", true)
	add_child(fl)
	fl.global_position = from
	fl.global_rotation = Vector3(PI * 0.5 + (_tip.rotation.x if _tip != null else 0.0), _turn.global_rotation.y if _turn != null else 0.0, 0)
	get_tree().create_timer(0.07).timeout.connect(fl.queue_free)
	_smoke_line(from, at)
	ImpactFx.strike(at, (from - at).normalized(), "dirt", 0.5, false)
	set_process(true)

func _smoke_line(a: Vector3, b: Vector3) -> void:
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.albedo_color = Color(0.8, 0.78, 0.74, 0.22)
	var mi := MeshInstance3D.new()
	mi.mesh = PowerGrid.cable_mesh(a, b, 0.01)
	mi.material_override = _smoke_mat.duplicate()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(mi.queue_free)

func set_flame(on: bool) -> void:
	if _flame == null or _flame_on == on:
		return
	_flame_on = on
	_flame.visible = on
	if _light == null:
		return

## A machine works (its drill or blade turns) or stops.
func set_running(on: bool) -> void:
	if _machine_on == on:
		return
	_machine_on = on
	if (_spinner != null or _belt != null) and not is_processing():
		set_process(true)

## A belt's items, as the grid has them: drawn moving on at `speed` until the next tick.
func show_belt(q: Array, speed: float) -> void:
	_belt_q.clear()
	for e in q:
		var c: Color = ItemDB.def(String(e[0]["type"])).get("color", Color(0.6, 0.55, 0.5))
		_belt_q.append([c, float(e[1])])
	_belt_v = speed
	if not is_processing():
		set_process(true)

## A robot arm makes one move.
func swing() -> void:
	_arm_t = 1.0
	set_process(true)

## The bell's clapper swings.
func ring() -> void:
	_ring = 1.0
	set_process(true)

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
	if _turn != null:
		var want := _turn.rotation.y
		var tip := 0.0
		if _aim_at != null:
			want = _yaw_to(_aim_at)
			var from := _tip.global_position
			var d: Vector3 = (_aim_at as Vector3) - from
			tip = atan2(d.y, Vector2(d.x, d.z).length())
		elif _spec.has("lamp") and _lit:
			# A searchlight with nothing to follow sweeps to and fro.
			_sweep += delta * 0.35
			want = sin(_sweep) * 1.2
			tip = -0.12
		_turn.rotation.y = rotate_toward(_turn.rotation.y, want, TURN_SPEED * delta)
		_tip.rotation.x = rotate_toward(_tip.rotation.x, tip, TURN_SPEED * 0.6 * delta)
		busy = busy or _aim_at != null or (_spec.has("lamp") and _lit) or absf(angle_difference(_turn.rotation.y, want)) > 0.01
	if _flash != null and _flash.visible:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
		busy = true
	if _belt != null:
		var mm := _belt.multimesh
		var n := mini(_belt_q.size(), mm.instance_count)
		var ahead := 2.0
		for i in n:
			var e: Array = _belt_q[i]
			e[1] = minf(float(e[1]) + _belt_v * delta, minf(1.0, ahead - Automation.GAP))
			ahead = float(e[1])
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(i) * 0.7), Vector3(0, 0.27, float(e[1]) - 0.5)))
			mm.set_instance_color(i, e[0])
		mm.visible_instance_count = n
		busy = busy or (n > 0 and _belt_v > 0.0)
	if _spinner != null:
		_spin_rate = move_toward(_spin_rate, _spin_max if (_machine_on or _running) else 0.0, delta * _spin_max * 0.6)
		_spinner.rotate_object_local(_spin_axis, _spin_rate * delta)
		if _piston != null:
			_crank = fmod(_crank + _spin_rate * delta, TAU)
			_piston.position = (_piston_spec["pos"] as Vector3) + (_piston_spec["axis"] as Vector3) * float(_piston_spec["stroke"]) * cos(_crank)
		busy = busy or _spin_rate > 0.0
	if _arm != null and _arm_t > 0.0:
		_arm_t = maxf(0.0, _arm_t - delta * 1.6)
		_arm.rotation.y = sin((1.0 - _arm_t) * PI) * PI
		busy = true
	if _clapper != null and _ring > 0.0:
		_ring = maxf(0.0, _ring - delta * 2.0)
		_clapper.rotation.z = sin(_ring * 22.0) * 0.5 * _ring
		busy = true
	if not busy:
		set_process(false)
