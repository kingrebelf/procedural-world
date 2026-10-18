class_name Cannon
## A field cannon (a Vehicle kind): a bronze barrel on a wheeled oak carriage, set down
## from the pack and worked from behind. Get on it and the move keys roll and turn the
## carriage, looking up and down raises the barrel, and Use loads it (a ball from the pack
## and a measure of black powder) and then fires. Round shot smashes what it hits; hot
## shot (a ball heated in the forge) sets timber alight (FireSystem). Its load is kept in
## the vehicle's record, so a loaded cannon stays loaded.

const MIN_EL := deg_to_rad(-6.0)
const MAX_EL := deg_to_rad(32.0)
const LOAD_TIME := 3.5 ## seconds to swab, ram powder and ball
const SPEED := 95.0 ## muzzle velocity, m/s
const BARREL := 1.9 ## trunnion to muzzle, m
const TRUNNION := Vector3(0, 0.98, -0.1) ## the barrel's pivot on the carriage
const AMMO := ["cannon_ball", "hot_shot"]
const SHOT := {
	# Solid shot: no burst, it smashes what it strikes (and hot shot sets it alight).
	"cannon_ball": {"damage": 260.0, "range": 420.0, "tracer": "cannon"},
	"hot_shot": {"damage": 220.0, "range": 420.0, "tracer": "cannon", "incendiary": 0.95},
}

# --- Model ------------------------------------------------------------------------------

## The cannon facing -z, sitting on the origin: the carriage, and the barrel on its own
## node ("Barrel", pivoting at the trunnions) so it can be raised.
static func model() -> Node3D:
	var holder := Node3D.new()
	var carriage := MeshInstance3D.new()
	carriage.name = "Carriage"
	carriage.mesh = _carriage_mesh()
	holder.add_child(carriage)
	var pivot := Node3D.new()
	pivot.name = "Barrel"
	pivot.position = TRUNNION
	holder.add_child(pivot)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _barrel_mesh()
	pivot.add_child(barrel)
	return holder

static var _meshes := {}

static func _mat(name: String) -> Material:
	match name:
		"bronze":
			return Metals.mat("gun_bronze", -1.0, true)
		"iron":
			return Metals.mat("wrought", -1.0, true)
		"bore":
			if not _meshes.has("bore_mat"):
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.03, 0.028, 0.025)
				m.roughness = 0.9
				_meshes["bore_mat"] = m
			return _meshes["bore_mat"]
	return Materials.get_mat(name)

## A cast bronze barrel along -z from the trunnions: breech and cascabel knob behind,
## reinforcing rings, a taper to the muzzle swell, a dark bore.
static func _barrel_mesh() -> ArrayMesh:
	if _meshes.has("barrel"):
		return _meshes["barrel"]
	var k := MeshKit.new(7)
	var along := Basis(Vector3(1, 0, 0), -PI * 0.5) # lathe y -> -z
	# Profile (radius, distance forward of the trunnions); the breech sits 0.55 m behind.
	var prof := [Vector2(0.0, -0.74), Vector2(0.05, -0.74), Vector2(0.06, -0.69), Vector2(0.03, -0.64),
		Vector2(0.05, -0.6), Vector2(0.2, -0.57), Vector2(0.235, -0.52), Vector2(0.235, -0.36),
		Vector2(0.25, -0.34), Vector2(0.25, -0.3), Vector2(0.22, -0.28), Vector2(0.21, 0.2),
		Vector2(0.225, 0.22), Vector2(0.225, 0.27), Vector2(0.2, 0.29), Vector2(0.16, 1.62),
		Vector2(0.175, 1.66), Vector2(0.2, 1.76), Vector2(0.2, 1.84), Vector2(0.17, 1.9), Vector2(0.085, 1.9),
		Vector2(0.085, 1.5)]
	ToolModels.lathe(k, "bronze", Transform3D(along, Vector3.ZERO), prof, 20)
	k.cylinder("bore", Transform3D(along, Vector3(0, 0, -1.5)), 0.084, 0.084, 0.38, 14, false)
	# Trunnions out to the sides, and the dolphins (lifting handles) on top.
	var side := Basis(Vector3(0, 0, 1), PI * 0.5)
	k.cylinder("bronze", Transform3D(side, Vector3(0.31, 0, 0)), 0.065, 0.065, 0.62, 12) # cylinders grow from their base
	for z in [-0.05, 0.25]:
		k.box("bronze", Transform3D(Basis(), Vector3(0, 0.25, -z)), Vector3(0.05, 0.06, 0.14))
	var m := k.commit(_mat)
	_meshes["barrel"] = m
	return m

## The carriage: two cheeks of oak with an axle, two spoked wheels bound in iron, and the
## trail running back to the ground.
static func _carriage_mesh() -> ArrayMesh:
	if _meshes.has("carriage"):
		return _meshes["carriage"]
	var k := MeshKit.new(11)
	var wood := "timber"
	for s in [-1.0, 1.0]:
		# Cheek: a heavy plank stepped under the trunnion, sloping back to the trail.
		k.bevel_box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.43), Vector3(s * 0.26, 0.5, 0.6)), Vector3(0.1, 0.3, 1.8), 0.015)
		k.bevel_box(wood, Transform3D(Basis(), Vector3(s * 0.26, 0.86, -0.12)), Vector3(0.1, 0.22, 0.55), 0.015)
		# Cap square over the trunnion.
		k.box("iron", Transform3D(Basis(), Vector3(s * 0.26, 1.0, -0.1)), Vector3(0.12, 0.03, 0.16))
		# Wheel: hub, twelve spokes, felloe and iron tyre.
		var wc := Vector3(s * 0.46, 0.62, -0.1)
		var axis := Basis(Vector3(0, 0, 1), PI * 0.5)
		k.cylinder(wood, Transform3D(axis, wc + Vector3(0.1, 0, 0)), 0.1, 0.1, 0.2, 12)
		k.cylinder("iron", Transform3D(axis, wc + Vector3(s * 0.1 + 0.02, 0, 0)), 0.06, 0.06, 0.04, 10)
		for i in 12:
			var a := TAU * i / 12.0
			var spoke := Basis(Vector3(1, 0, 0), a)
			k.box(wood, Transform3D(spoke, wc + spoke * Vector3(0, 0.33, 0)), Vector3(0.045, 0.48, 0.04))
		for i in 24:
			var a0 := TAU * i / 24.0
			var mid := wc + Vector3(0, cos(a0 + PI / 24.0), sin(a0 + PI / 24.0)) * 0.56
			var seg := Basis(Vector3(1, 0, 0), a0 + PI / 24.0)
			k.box(wood, Transform3D(seg, mid), Vector3(0.08, 0.08, 0.15))
			k.box("iron", Transform3D(seg, wc + seg * Vector3(0, 0.615, 0)), Vector3(0.085, 0.02, 0.16))
	# Axle tree, transoms and the trail's end on the ground.
	k.bevel_box(wood, Transform3D(Basis(), Vector3(0, 0.62, -0.1)), Vector3(0.84, 0.12, 0.14), 0.012)
	k.bevel_box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.43), Vector3(0, 0.62, 0.3)), Vector3(0.44, 0.1, 0.12), 0.012)
	k.bevel_box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.43), Vector3(0, 0.3, 1.05)), Vector3(0.44, 0.1, 0.16), 0.012)
	k.box("iron", Transform3D(Basis(Vector3(1, 0, 0), 0.43), Vector3(0, 0.12, 1.42)), Vector3(0.46, 0.05, 0.14))
	# The elevating quoin under the breech.
	k.bevel_box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.43), Vector3(0, 0.66, 0.5)), Vector3(0.3, 0.1, 0.32), 0.01)
	var m := k.commit(_mat)
	_meshes["carriage"] = m
	return m

## The flying ball: dark iron, or glowing red-hot for hot shot.
static func ball_node(hot: bool) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.radial_segments = 12
	sm.rings = 6
	if hot:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.08, 0.02)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.32, 0.06)
		m.emission_energy_multiplier = 3.0
		sm.material = m
	else:
		sm.material = _mat("iron")
	n.mesh = sm
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

# --- Working it -------------------------------------------------------------------------

## What it is doing, for the prompt while you man it.
static func status(v: Vehicle) -> String:
	if v.rec.has("loading"):
		return "Loading..."
	var load := String(v.rec.get("load", ""))
	if load == "":
		return "[%s] Load (a ball and a measure of black powder)" % Player._key("use")
	return "%s loaded   [%s] Fire" % [ItemDB.def(load)["name"], Player._key("use")]

## The shot to load from the pack: the one you have selected if it is cannon shot,
## otherwise round shot before hot shot.
static func _pick_shot(pl: Player) -> String:
	var it = Game.inventory.get_slot(pl.selected)
	if it != null and it["type"] in AMMO:
		return it["type"]
	for t in AMMO:
		if Game.inventory.count(t) > 0:
			return t
	return ""

## Use, while manning it: load it if empty, fire it if loaded.
static func use(pl: Player, v: Vehicle) -> void:
	if v.rec.has("loading"):
		return
	var load := String(v.rec.get("load", ""))
	if load != "":
		fire(pl, v)
		return
	var shot := _pick_shot(pl)
	if shot == "":
		Game.toast.emit("No cannon balls in your pack")
		return
	if Game.inventory.count("black_powder") < 1:
		Game.toast.emit("You need black powder to load it")
		return
	Game.inventory.remove_type(shot, 1)
	Game.inventory.remove_type("black_powder", 1)
	v.rec["loading"] = true
	Audio.play_at("weapon/draw", v.global_position, -4.0)
	Game.toast.emit("Swabbing, ramming powder, loading %s..." % ItemDB.def(shot)["name"].to_lower())
	v.get_tree().create_timer(LOAD_TIME, false).timeout.connect(func():
		if is_instance_valid(v):
			v.rec.erase("loading")
			v.rec["load"] = shot)

## Where the barrel points from and to, in the world.
static func muzzle(v: Vehicle) -> Transform3D:
	var b: Node3D = v.barrel
	var xf := b.global_transform if b != null else v.global_transform
	return Transform3D(xf.basis, xf.origin - xf.basis.z * BARREL)

## Fires the loaded shot along the barrel.
static func fire(pl: Player, v: Vehicle) -> void:
	var load := String(v.rec.get("load", ""))
	v.rec.erase("load")
	var mz := muzzle(v)
	var fwd := -mz.basis.z.normalized()
	var d: Dictionary = SHOT[load].duplicate()
	var hot := load == "hot_shot"
	pl.gunplay.launch(mz.origin + fwd * 0.25, fwd * SPEED, d, load, ball_node(hot), {"type": load}, [v.get_rid()])
	# Flash, a great bank of smoke, the boom, and the carriage kicks back.
	var g := pl.gunplay
	g._flipbook("sparks", true, mz.origin + fwd * 0.2, 1.4, 0.1, Color(1.0, 0.8, 0.5, 1.0), Vector2(3, 5))
	g._flash_light(mz.origin + fwd * 0.4, Color(1.0, 0.65, 0.35), 12.0, 22.0, 0.12)
	for i in 4:
		g._flipbook("smoke", false, mz.origin + fwd * (0.6 + i * 0.7), 1.2 + i * 0.5, 3.5 + i, Color(0.82, 0.8, 0.77, 0.75), Vector2(0, 13),
			fwd * (1.6 - i * 0.3) + Vector3(0, 0.3, 0), 3.0)
	Audio.play_at("fire/cannon", mz.origin, 4.0, 0.05)
	v.spd = -2.4
	v.kick = 1.0
	pl.used_tool.emit("fire")
