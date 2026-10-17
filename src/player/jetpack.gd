class_name Jetpack
extends Node3D
## A fuel-burning jetpack worn in the "back" armour slot. In the air, press (or keep
## holding) Jump to fire it: it lifts you up cliffs and slows a fall. It burns Jet Fuel
## from its tank and loads the next canister from your pack when the tank runs dry.
## Lives under the player, at your back.

const TANK := 20.0 ## seconds of thrust in one canister (the tank holds one)
const LIFT := 9.0 ## upward acceleration over gravity, m/s^2
const MAX_CLIMB := 8.0 ## climb speed it stops accelerating at
const HOLD_DELAY := 0.28 ## after a normal jump, hold this long to fire

var firing := false
var _air_hold := 0.0
var _pack: MeshInstance3D
var _flames: Array[Node3D] = []
var _light: OmniLight3D
var _flicker := 0.0
var _empty_warned := false
var _ticked := 0 ## physics frame of the last thrust() call

func _ready() -> void:
	_pack = MeshInstance3D.new()
	_pack.mesh = pack_model()
	_pack.position = Vector3(0, 1.05, 0.2)
	_pack.visible = false
	add_child(_pack)
	for x in [-0.11, 0.11]:
		# Ben's blue jet flipbook, hanging from each nozzle.
		var f := FireFx.flame(0.75, Color(1, 1, 1, 1), "jet", true)
		f.position = Vector3(x, 0.93, 0.27)
		f.visible = false
		add_child(f)
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.75, 1.0)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.6, 0.3)
	add_child(_light)

static func pack_model() -> ArrayMesh:
	var k := MeshKit.new(7)
	# Two fuel tanks on a back plate, with nozzles underneath.
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 0.02, -0.04)), Vector3(0.34, 0.42, 0.05))
	for x in [-0.11, 0.11]:
		k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(x, -0.17, 0.04)), 0.075, 0.075, 0.38, 12)
		k.sphere("metal", Transform3D.IDENTITY.translated(Vector3(x, 0.21, 0.04)), 0.075, 6, 12, 0.0, 1.0, Color.WHITE, true)
		k.cylinder("metal_dark", Transform3D.IDENTITY.translated(Vector3(x, -0.25, 0.04)), 0.05, 0.065, 0.08, 10)
		k.box("cloth", Transform3D.IDENTITY.translated(Vector3(x, 0.05, 0.04)), Vector3(0.16, 0.035, 0.16), Color(0.25, 0.25, 0.27))
	return k.commit(Materials.get_mat)

## The jetpack you are wearing, or null.
static func worn():
	var it = Game.equipment.get("back")
	return it if it != null and (it["type"] == "jetpack" or ItemDB.def(it["type"]).has("jet")) else null

## Seconds of thrust left: the tank plus every canister in the pack.
static func fuel_total(inv: Inventory) -> float:
	var it = worn()
	if it == null:
		return 0.0
	return float(it.get("fuel", 0.0)) + inv.count("jet_fuel") * TANK

## Upward acceleration to add this physics frame (0 when not firing).
## `held`/`pressed`: the Jump action; `vy`: current vertical speed.
func thrust(delta: float, held: bool, pressed: bool, on_floor: bool, vy: float, inv: Inventory) -> float:
	_ticked = Engine.get_physics_frames()
	var it = worn()
	_pack.visible = it != null
	var want := false
	if it != null and not on_floor and held:
		_air_hold += delta
		want = pressed or _air_hold >= HOLD_DELAY or firing
	else:
		_air_hold = 0.0
	if want and float(it.get("fuel", 0.0)) <= 0.0:
		if inv.remove_type("jet_fuel", 1) > 0:
			it["fuel"] = TANK
			Game._player_dirty = true
			Game.toast.emit("Jetpack: loaded a fuel canister (%d left)" % inv.count("jet_fuel"))
		elif not _empty_warned:
			_empty_warned = true
			Game.toast.emit("Jetpack out of fuel: make Jet Fuel at a forge or fabricator")
	if want and float(it.get("fuel", 0.0)) > 0.0:
		_empty_warned = false
		it["fuel"] = maxf(0.0, float(it["fuel"]) - delta)
		firing = true
	elif firing:
		firing = false
		Game._player_dirty = true # save the fuel left in the tank
	_update_fx(delta)
	if not firing:
		return 0.0
	# Full lift while climbing slower than MAX_CLIMB, then just hold the climb.
	var jet := float(ItemDB.def(it["type"]).get("jet", 1.0))
	return LIFT * jet if vy < MAX_CLIMB * jet else 0.0

## Swimming, flying or riding skip thrust(): put the flames out.
func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() - _ticked > 1 and (firing or _light.light_energy > 0.01):
		firing = false
		_update_fx(delta)

## First person: the pack only casts its shadow, like the body.
func set_shadow_only(on: bool) -> void:
	_pack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _update_fx(delta: float) -> void:
	_flicker += delta * 31.0
	var s := 0.85 + 0.15 * sin(_flicker) * sin(_flicker * 0.37)
	for f in _flames:
		f.visible = firing
		f.scale = Vector3(1, s * (1.0 + 0.2 * sin(_flicker * 1.7 + f.position.x * 40.0)), 1)
	_light.light_energy = lerpf(_light.light_energy, 2.2 * s if firing else 0.0, clampf(delta * 18.0, 0.0, 1.0))
