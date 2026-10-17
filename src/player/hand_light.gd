class_name HandLight
extends Node3D
## A light carried in the off hand, so it works while you hold any tool: a torch that
## burns down and is used up, or a flashlight whose battery runs for hours and then dies
## until it is repaired with a power cell. Lives under the camera. Holding a torch or a
## flashlight in your main hand (selected on the hotbar) lights it too.

const TORCH_BURN := 360.0 ## seconds one torch burns
const FLASH_CHARGE := 10800.0 ## seconds a flashlight runs before its battery fails

var kind := "" ## "", "torch" or "flashlight": the light in the off hand (T)
var held := "" ## "torch" or "flashlight" when one is selected in the main hand
var torch_left := 0.0 ## seconds left on the burning torch
var _omni: OmniLight3D
var _spot: SpotLight3D
var _torch_mesh: MeshInstance3D
var _t := 0.0
var show_model := true ## the torch in your hand (first person only)

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
	var fl := FireFx.flame(TORCH_FLAME[1])
	fl.position = TORCH_FLAME[0]
	_torch_mesh.add_child(fl)

## Where a torch's flame stands on its model, and how tall it is.
const TORCH_FLAME := [Vector3(0, 0.41, 0), 0.3]

static func torch_model() -> ArrayMesh:
	var k := MeshKit.new(5)
	k.cylinder("bark", Transform3D.IDENTITY, 0.024, 0.03, 0.42, 8)
	k.cylinder("cloth", Transform3D.IDENTITY.translated(Vector3(0, 0.36, 0)), 0.038, 0.036, 0.09, 8, true, 0.0, 1, Color(0.35, 0.28, 0.2))
	# Embers in the wrapping; the flame is FireFx (TORCH_FLAME).
	k.sphere("glow_red", Transform3D.IDENTITY.translated(Vector3(0, 0.44, 0)), 0.036, 6, 8, 0.2, 0.8)
	return k.commit(Materials.get_mat)

func is_on() -> bool:
	return lit() != ""

## The light actually burning: the one in your hand wins over the off-hand one.
func lit() -> String:
	return held if held != "" else kind

## Called when the hotbar selection changes: a torch or flashlight in hand lights itself.
func set_held(t: String, inv: Inventory) -> void:
	held = ""
	if t == "torch" and inv.count("torch") > 0:
		held = "torch"
		if torch_left <= 0.0:
			torch_left = TORCH_BURN
	elif t == "flashlight" and flashlight_slot(inv) >= 0:
		held = "flashlight"
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
	if inv.count("torch") > 0:
		kind = "torch"
		if torch_left <= 0.0:
			torch_left = TORCH_BURN
		_apply()
		return "Torch lit (%d left)" % inv.count("torch")
	if inv.count("flashlight_dead") > 0:
		return "Your flashlight's battery is dead: repair it with a power cell at a workbench"
	return "No light: craft a torch from 1 wood and 2 plant fiber"

static func flashlight_slot(inv: Inventory) -> int:
	for i in Inventory.SIZE:
		var s = inv.get_slot(i)
		if s != null and s["type"] == "flashlight" and float(s.get("charge", FLASH_CHARGE)) > 0.0:
			return i
	return -1

## Burns fuel. Returns a message when something runs out, else "".
func tick(delta: float, inv: Inventory) -> String:
	var msg := ""
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
	if lit() == "torch":
		# Flicker: two slow waves and a fast one.
		_omni.light_energy = 2.3 + 0.25 * sin(_t * 7.3) + 0.16 * sin(_t * 13.1 + 1.7) + 0.1 * sin(_t * 23.0)

func _apply() -> void:
	if _omni == null:
		return
	var k := lit()
	_omni.visible = k == "torch"
	_spot.visible = k == "flashlight"
	# The off-hand torch shows only when nothing lit is held in the main hand.
	_torch_mesh.visible = k == "torch" and held == "" and show_model
	# The light sits where the burning end is: left hand, or the held item on the right.
	_omni.position = Vector3(0.3, -0.02, -0.5) if held == "torch" else Vector3(-0.35, -0.05, -0.4)
	_spot.position = Vector3(0.22, -0.15, -0.2) if held == "flashlight" else Vector3(-0.15, -0.12, -0.1)

static func _hours(s: float) -> String:
	if s >= 3600.0:
		return "%.1f h" % (s / 3600.0)
	return "%d min" % int(ceil(s / 60.0))

func to_data() -> Dictionary:
	return {"kind": kind, "torch_left": torch_left}

func from_data(d) -> void:
	if d is Dictionary:
		kind = String(d.get("kind", ""))
		torch_left = float(d.get("torch_left", 0.0))
	_apply()
