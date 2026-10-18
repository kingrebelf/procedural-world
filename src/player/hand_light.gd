class_name HandLight
extends Node3D
## A light carried in the off hand, so it works while you hold any tool: a torch that
## burns down and is used up, or a flashlight whose battery runs for hours and then dies
## until it is repaired with a power cell, a lantern that burns lamp oil (or candles), or a
## lone candle. Lives under the camera. Holding any of them in your main hand (selected on
## the hotbar) lights it too.

const TORCH_BURN := 360.0 ## seconds one torch burns
const FLASH_CHARGE := 10800.0 ## seconds a flashlight runs before its battery fails

const CANDLE_BURN := 600.0 ## seconds one candle burns on its own
## What a lantern burns, best first: [item, seconds one lasts].
const LANTERN_FUEL := [["lamp_oil", 1800.0], ["candle", 900.0], ["kerosene_can", 5400.0], ["diesel_jerrycan", 7200.0]]
const KEROSENE_BURN := 1.5 ## a kerosene lamp's wick makes its fuel last this much longer

var kind := "" ## "", "torch", "flashlight", "lantern" or "candle": the light in the off hand (T)
var held := "" ## the same, when one is selected in the main hand
var torch_left := 0.0 ## seconds left on the burning torch
var lantern_left := 0.0 ## seconds left on the lantern's oil
var candle_left := 0.0 ## seconds left on the burning candle
var kerosene := false ## the lantern alight is a kerosene lamp: brighter, thriftier
var _omni: OmniLight3D
var _spot: SpotLight3D
var _torch_mesh: MeshInstance3D
var _t := 0.0
var _omni_at := Vector3.ZERO ## where the torch light rests before it sways
var show_model := true ## the torch in your hand (first person only)
var wet := false ## the flame would be under water: a torch, lantern or candle goes out and won't light

func _ready() -> void:
	_omni = OmniLight3D.new()
	_omni.light_color = Color(1.0, 0.62, 0.3)
	_omni.omni_range = 16.0
	_omni.omni_attenuation = 0.9
	_omni.light_energy = 2.4
	_omni.shadow_enabled = true
	_omni.position = Vector3(-0.35, -0.05, -0.4)
	_omni.visible = false
	add_child(_omni)
	_spot = SpotLight3D.new()
	_spot.light_color = Color(0.92, 0.96, 1.0)
	_spot.spot_range = 45.0
	_spot.spot_angle = 26.0
	_spot.spot_angle_attenuation = 1.6
	_spot.light_energy = 3.0
	_spot.shadow_enabled = true
	_spot.position = Vector3(-0.15, -0.12, -0.1)
	_spot.visible = false
	add_child(_spot)
	_torch_mesh = MeshInstance3D.new()
	_torch_mesh.mesh = torch_model()
	_torch_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_torch_mesh.position = Vector3(-0.42, -0.42, -0.62)
	_torch_mesh.rotation = Vector3(-0.25, 0.0, 0.18)
	_torch_mesh.visible = false
	add_child(_torch_mesh)
	_torch_mesh.add_child(torch_fire())

## Where a torch's flame stands on its model, and how tall it is.
const TORCH_FLAME := [Vector3(0, 0.4, 0), 0.32]
## The seed of a carried torch's flame, which the light in your hand follows.
const TORCH_SEED := 0.37

## A torch's living fire, to sit on its model: the flame, with sparks and smoke.
static func torch_fire() -> Node3D:
	var n := FireFx.carried(TORCH_FLAME[1], TORCH_SEED)
	n.position = TORCH_FLAME[0]
	n.add_child(FireFx.embers(TORCH_FLAME[1], false))
	n.add_child(_torch_smoke(TORCH_FLAME[1]))
	return n

static var _wisp_mat: StandardMaterial3D

## A burning rag's smoke: thin pale-grey wisps that leave the flame's tip, widen, drift and
## fade. Already streaming when lit (preprocess), so it never starts as one dark clump.
static func _torch_smoke(size: float) -> CPUParticles3D:
	if _wisp_mat == null:
		_wisp_mat = StandardMaterial3D.new()
		_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_wisp_mat.vertex_color_use_as_albedo = true
		_wisp_mat.albedo_texture = FireFx._dot()
		_wisp_mat.disable_receive_shadows = true
	var s := CPUParticles3D.new()
	s.name = "Smoke"
	s.amount = 16
	s.lifetime = 2.2
	s.preprocess = 2.2
	s.randomness = 0.6
	s.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size * 0.32
	q.material = _wisp_mat
	s.mesh = q
	s.position = Vector3(0, size * 0.9, 0)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = size * 0.06
	s.direction = Vector3.UP
	s.spread = 10.0
	s.initial_velocity_min = size * 1.0
	s.initial_velocity_max = size * 1.8
	s.gravity = Vector3(0, 0.1, 0)
	s.damping_min = size * 0.4
	s.damping_max = size * 0.8
	s.tangential_accel_min = -size * 1.5
	s.tangential_accel_max = size * 1.5
	s.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 2.0))
	s.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.62, 0.6, 0.58, 0.0))
	g.add_point(0.12, Color(0.6, 0.58, 0.56, 0.1))
	g.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	s.color_ramp = g
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.visibility_range_end = 60.0
	return s

static func torch_model() -> ArrayMesh:
	var k := MeshKit.new(5)
	ToolModels.torch(k)
	return k.commit(ToolModels.mat)

func is_on() -> bool:
	return lit() != ""

## The light actually burning: the one in your hand wins over the off-hand one.
func lit() -> String:
	return held if held != "" else kind

static func flame(k: String) -> bool:
	return k == "torch" or k == "lantern" or k == "candle"

## Called when the hotbar selection changes: a torch or flashlight in hand lights itself
## (a flame not under water).
func set_held(t: String, inv: Inventory) -> void:
	held = ""
	if wet and t in ["torch", "hand_lantern", "lamp_kerosene", "candle"]:
		pass
	elif t == "torch" and inv.count("torch") > 0:
		held = "torch"
		if torch_left <= 0.0:
			torch_left = TORCH_BURN
	elif t == "flashlight" and flashlight_slot(inv) >= 0:
		held = "flashlight"
	elif (t == "hand_lantern" or t == "lamp_kerosene") and (lantern_left > 0.0 or _lantern_fuel(inv) != ""):
		held = "lantern"
		kerosene = t == "lamp_kerosene"
	elif t == "candle" and inv.count("candle") > 0:
		held = "candle"
		if candle_left <= 0.0:
			candle_left = CANDLE_BURN
	_apply()

## Turns the light off, or on with the best light you carry. Returns a line to show.
func toggle(inv: Inventory) -> String:
	if held != "":
		return "Put the %s away to put it out" % held
	if is_on():
		kind = ""
		_apply()
		return "Light off"
	var fi := flashlight_slot(inv)
	if fi >= 0:
		kind = "flashlight"
		_apply()
		return "Flashlight on (%s left)" % _hours(float(inv.get_slot(fi).get("charge", FLASH_CHARGE)))
	if wet:
		return "You can't light a flame under water"
	if lanterns(inv) > 0 and (lantern_left > 0.0 or _lantern_fuel(inv) != ""):
		kind = "lantern"
		kerosene = inv.count("lamp_kerosene") > 0
		_apply()
		return "Lantern lit"
	if inv.count("torch") > 0:
		kind = "torch"
		if torch_left <= 0.0:
			torch_left = TORCH_BURN
		_apply()
		return "Torch lit (%d left)" % inv.count("torch")
	if inv.count("candle") > 0:
		kind = "candle"
		if candle_left <= 0.0:
			candle_left = CANDLE_BURN
		_apply()
		return "Candle lit (%d left)" % inv.count("candle")
	if lanterns(inv) > 0:
		return "Your lantern needs lamp oil or a candle"
	if inv.count("flashlight_dead") > 0:
		return "Your flashlight's battery is dead: repair it with a power cell at a workbench"
	return "No light: craft a torch from 1 wood and 2 plant fiber"

## The fuel a lantern would burn next, or "" if there is none.
static func _lantern_fuel(inv: Inventory) -> String:
	for f in LANTERN_FUEL:
		if inv.count(f[0]) > 0:
			return f[0]
	return ""

## Lanterns carried: the medieval kind and the frontier's kerosene lamp.
static func lanterns(inv: Inventory) -> int:
	return inv.count("hand_lantern") + inv.count("lamp_kerosene")

static func flashlight_slot(inv: Inventory) -> int:
	for i in inv.capacity:
		var s = inv.get_slot(i)
		if s != null and s["type"] == "flashlight" and float(s.get("charge", FLASH_CHARGE)) > 0.0:
			return i
	return -1

## Burns fuel. Returns a message when something runs out, else "". `under` is whether
## the flame is under water, which puts out a torch, lantern or candle.
func tick(delta: float, inv: Inventory, under := false) -> String:
	var msg := ""
	wet = under
	if wet and flame(lit()):
		var gone := lit()
		if flame(held):
			held = ""
		if flame(kind):
			kind = ""
		_apply()
		return "Your %s goes out in the water" % gone
	var was := lit()
	if was == "torch":
		torch_left -= delta
		if inv.count("torch") <= 0:
			kind = ""
			held = ""
		elif torch_left <= 0.0:
			inv.remove_type("torch", 1)
			if inv.count("torch") > 0:
				torch_left = TORCH_BURN
				msg = "Your torch burned out; you light another (%d left)" % inv.count("torch")
			else:
				kind = ""
				held = ""
				torch_left = 0.0
				msg = "Your torch burned out"
	elif was == "lantern":
		lantern_left -= delta
		if lanterns(inv) <= 0:
			kind = ""
			held = ""
		elif lantern_left <= 0.0:
			var f := _lantern_fuel(inv)
			if f != "":
				inv.remove_type(f, 1)
				for e in LANTERN_FUEL:
					if e[0] == f:
						lantern_left = e[1] * (KEROSENE_BURN if kerosene else 1.0)
			else:
				lantern_left = 0.0
				kind = ""
				held = ""
				msg = "Your lantern burned dry. Fill it with lamp oil or a candle"
	elif was == "candle":
		candle_left -= delta
		if inv.count("candle") <= 0:
			kind = ""
			held = ""
		elif candle_left <= 0.0:
			inv.remove_type("candle", 1)
			if inv.count("candle") > 0:
				candle_left = CANDLE_BURN
				msg = "Your candle burned down; you light another (%d left)" % inv.count("candle")
			else:
				kind = ""
				held = ""
				candle_left = 0.0
				msg = "Your candle burned down"
	elif was == "flashlight":
		var fi := flashlight_slot(inv)
		if fi < 0:
			kind = ""
			held = ""
		else:
			var it: Dictionary = inv.get_slot(fi)
			it["charge"] = float(it.get("charge", FLASH_CHARGE)) - delta
			if it["charge"] <= 0.0:
				it["type"] = "flashlight_dead"
				it.erase("charge")
				kind = ""
				held = ""
				inv.changed.emit()
				msg = "Your flashlight's battery failed. Repair it with a power cell at a workbench"
	if msg != "" or lit() != was:
		_apply()
	return msg

func _process(delta: float) -> void:
	_t += delta
	var k := lit()
	if k == "torch" or k == "lantern" or k == "candle":
		# It leaps and sinks with the torch's flame (FireFx.life); a wick behind glass or a
		# lone candle burns steadier.
		var l := FireFx.life(FireFx.time, TORCH_SEED)
		var base: float = {"lantern": 3.0 if kerosene else 2.6, "candle": 1.1}.get(k, 2.3)
		_omni.light_energy = base * (1.0 + (0.42 if k == "torch" else 0.16) * (l - 0.5) * 2.0)
		# The light sways with the flame, so the shadows it casts move a little.
		var sw := 0.012 if k == "torch" else 0.004
		_omni.position = _omni_at + Vector3(FireFx._noise(FireFx.time * 2.3 + 26.0) - 0.5, l - 0.5, FireFx._noise(FireFx.time * 2.1 + 19.0) - 0.5) * sw * 2.0

func _apply() -> void:
	if _omni == null:
		return
	var k := lit()
	_omni.visible = k == "torch" or k == "lantern" or k == "candle"
	# A lantern's glass keeps its flame steady and bright; a candle lights only nearby.
	_omni.omni_range = {"lantern": 24.0 if kerosene else 18.0, "candle": 7.0}.get(k, 16.0)
	_omni.light_energy = {"lantern": 3.0 if kerosene else 2.6, "candle": 1.1}.get(k, _omni.light_energy)
	_spot.visible = k == "flashlight"
	# The off-hand torch shows only when nothing lit is held in the main hand.
	_torch_mesh.visible = k == "torch" and held == "" and show_model
	# The light sits where the burning end is: left hand, or the held item on the right.
	# A held torch's flame stands about (0.25, 0.03, -0.51) from the eye, the far end of a
	# stick that leans away from you; the light sits a little nearer you than the flame
	# so it falls on the stick and hand you see, not only on their far side.
	_omni_at = Vector3(0.17, 0.02, -0.36) if held != "" else Vector3(-0.35, -0.05, -0.4)
	_omni.position = _omni_at
	_spot.position = Vector3(0.22, -0.15, -0.2) if held == "flashlight" else Vector3(-0.15, -0.12, -0.1)

static func _hours(s: float) -> String:
	if s >= 3600.0:
		return "%.1f h" % (s / 3600.0)
	return "%d min" % int(ceil(s / 60.0))

func to_data() -> Dictionary:
	return {"kind": kind, "torch_left": torch_left, "lantern_left": lantern_left, "candle_left": candle_left}

func from_data(d) -> void:
	if d is Dictionary:
		kind = String(d.get("kind", ""))
		torch_left = float(d.get("torch_left", 0.0))
		lantern_left = float(d.get("lantern_left", 0.0))
		candle_left = float(d.get("candle_left", 0.0))
	_apply()
