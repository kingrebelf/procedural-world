class_name Vehicle
extends CharacterBody3D
## Something you ride: a hover speeder, a survey rover or a riding horse. Arcade handling:
## throttle and steering from the rider, the body follows the ground (or hovers over land
## and water). The vehicle's record in Game.vehicles is its save state; this node keeps
## the record's position and heading up to date while it exists.

const KINDS := {
	"speeder": {"name": "Hover Speeder", "model": "res://assets/models/vehicles/Speeder.glb", "length": 3.6,
		"speed": 24.0, "boost": 1.6, "accel": 10.0, "turn": 2.0, "hover": 0.9, "reverse": 6.0},
	"rover": {"name": "Survey Rover", "model": "res://assets/models/vehicles/Rover.glb", "length": 3.4,
		"speed": 15.0, "boost": 1.35, "accel": 6.0, "turn": 1.6, "reverse": 5.0, "seat": 0.47},
	"horse": {"name": "Riding Horse", "animal": "Horse", "length": 2.2,
		"speed": 7.5, "boost": 2.0, "accel": 5.0, "turn": 2.4, "reverse": 1.6, "swims": true},
	# Flies where the rider looks: thrust, climb and descend, land anywhere flat enough.
	"ship": {"name": "Starship", "model": "res://assets/models/ships/Striker.gltf", "length": 9.0, "yaw": PI,
		"speed": 40.0, "boost": 2.5, "accel": 16.0, "turn": 1.4, "reverse": 12.0, "fly": true, "seat": 0.62, "seat_z": -0.6},
	# A field gun (Cannon) you push from behind the trail: you stand, look up and down to lay
	# the barrel, and Use loads and fires it.
	"cannon": {"name": "Field Cannon", "proc": "cannon", "length": 2.8,
		"speed": 1.4, "boost": 1.0, "accel": 1.5, "turn": 0.55, "reverse": 1.0, "gun": true, "stand": true, "seat_z": 2.05},
}
const CEILING := 180.0 ## metres above the ground a ship flies at most; climbing on leaves for orbit
const LEAVE_TIME := 2.0
const ANIMAL_YAW := PI ## the animal kit faces +z; vehicles drive toward -z (the Kenney craft already do)

var rec: Dictionary
var kind: String
var p: Dictionary
var rider: Node3D = null
## Rider input: x = steer (right positive), y = throttle (forward positive).
var drive := Vector2.ZERO
var boosting := false
var aim := Vector3.FORWARD ## flying: the direction the rider looks
var _wake_t := 0.0
var lift := 0.0 ## flying: climb (+1) or descend (-1)
var at_ceiling := false ## flying at the top of the sky
var leaving := 0.0 ## seconds spent climbing against the top of the sky; past LEAVE_TIME, orbit
var spd := 0.0 ## forward speed along the heading, m/s
var seat := Vector3.ZERO ## where the rider's hips go, in local space
var ground: Callable ## (x, z) -> terrain height or NAN while the chunk is not loaded
var height := 1.0
var half_width := 1.0

var _model: Node3D
var _animal: AnimalModel
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _tilt := Basis.IDENTITY
var _bob := 0.0
var barrel: Node3D = null ## a gun's barrel, pivoting at its trunnions
var elevation := 0.0 ## a gun: the barrel raised this far (radians)
var kick := 0.0 ## a gun: the barrel's recoil, 1 just after firing, easing back to 0

static func is_vehicle_item(type: String) -> bool:
	return KINDS.has(type)

static func label(k: String) -> String:
	return KINDS.get(k, {}).get("name", k.capitalize())

## The model on its own, scaled to the vehicle's length and facing -z (also for icons).
static func make_model(k: String) -> Node3D:
	var d: Dictionary = KINDS[k]
	if d.get("proc", "") == "cannon":
		return Cannon.model()
	var holder := Node3D.new()
	if d.has("animal"):
		var a := AnimalModel.new().build(d["animal"])
		a.rotation.y = ANIMAL_YAW
		holder.add_child(a)
		return holder
	var scene: Node3D = (load(d["model"]) as PackedScene).instantiate()
	holder.add_child(scene)
	var box := _bounds(scene)
	var s: float = d["length"] / maxf(maxf(box.size.x, box.size.z), 0.01)
	scene.scale = Vector3.ONE * s
	var yaw: float = d.get("yaw", 0.0)
	scene.rotation.y = yaw
	# Sit the model on the origin, centred.
	var c := Basis(Vector3.UP, yaw) * (box.get_center() * s)
	scene.position = Vector3(-c.x, -box.position.y * s, -c.z)
	return holder

static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var q: Node = m
		while q != n and q is Node3D:
			xf = (q as Node3D).transform * xf
			q = q.get_parent()
		var b: AABB = xf * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func setup(r: Dictionary) -> Vehicle:
	rec = r
	kind = r["kind"]
	p = KINDS[kind]
	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.8
	set_meta("vehicle", self)
	_model = make_model(kind)
	add_child(_model)
	if p.has("animal"):
		_animal = _model.get_child(0)
	barrel = _model.find_child("Barrel", false, false)
	var box := _bounds(_model)
	height = box.size.y
	half_width = box.size.x * 0.5
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(box.size.x * 0.8, box.size.y * 0.9, box.size.z * 0.85)
	shape.shape = bs
	shape.position = Vector3(box.get_center().x, box.size.y * 0.45, box.get_center().z)
	add_child(shape)
	if _animal:
		seat = Vector3(0, box.size.y * 0.66, 0.15)
	elif p.get("stand", false):
		seat = Vector3(0, 0, float(p["seat_z"])) # where the feet go
	else:
		seat = Vector3(0, box.size.y * float(p.get("seat", 0.55)), float(p.get("seat_z", 0.25)))
	position = r["pos"]
	rotation.y = r["yaw"]
	return self

func hover() -> bool:
	return p.has("hover")

func flies() -> bool:
	return p.has("fly")

func airborne() -> bool:
	return flies() and not is_on_floor()

func _physics_process(delta: float) -> void:
	var g := NAN
	if ground.is_valid():
		g = ground.call(global_position.x, global_position.z)
	if flies():
		_fly(delta, g)
		return
	if is_nan(g):
		# The ground here isn't loaded (yet): hold still rather than fall through the world.
		velocity = Vector3.ZERO
		return
	var t_water := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var surface := Water.surface_height(global_position.x, global_position.z, t_water)
	var depth := surface - global_position.y
	var top: float = p["speed"] * (p["boost"] if boosting else 1.0)
	if not hover() and depth > 0.9:
		top = 3.0 if p.get("swims", false) else 2.0
	var want: float = drive.y * (top if drive.y >= 0.0 else float(p["reverse"]))
	var a: float = p["accel"] * (1.0 if absf(want) > absf(spd) and signf(want) == signf(spd) else 1.8)
	spd = move_toward(spd, want, a * delta)
	# Steering bites with speed; reversing steers the other way like a car.
	var grip := clampf(absf(spd) / 3.0, 0.0, 1.0) * (1.0 if spd >= 0.0 else -1.0)
	if _animal or p.get("gun", false):
		grip = 1.0 if spd > -0.1 else -1.0 # a horse turns on the spot, a gun is swung round by its trail
	rotation.y -= drive.x * float(p["turn"]) * grip * delta
	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * spd
	velocity.z = fwd.z * spd
	if hover():
		var target := maxf(g, surface) + float(p["hover"]) + sin(_bob) * 0.06
		_bob += delta * 2.0
		velocity.y = clampf((target - global_position.y) * 6.0, -14.0, 14.0)
	elif p.get("swims", false) and depth > 1.2:
		velocity.y = clampf((surface - 1.15 - global_position.y) * 3.0, -2.0, 2.0)
		# Swimming, the river carries you along.
		var cur := Water.current(global_position.x, global_position.z)
		velocity.x += cur.x
		velocity.z += cur.y
	elif is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	_wake(delta, surface, g)
	# Bumping into something sheds speed.
	var real := get_real_velocity()
	if absf(spd) > 2.0 and Vector2(real.x, real.z).length() < absf(spd) * 0.35:
		spd *= 0.6
	if global_position.y < g - 2.0:
		global_position.y = g + 0.3
	_pose(delta, g)
	rec["pos"] = global_position
	rec["yaw"] = rotation.y

## Rings and spray behind you on water: swimming, wading, or skimming low over it.
func _wake(delta: float, surface: float, g: float) -> void:
	_wake_t -= delta
	var above := global_position.y - surface
	var fast := absf(spd)
	if _wake_t > 0.0 or surface - g < 0.25 or above > 1.6 or above < -1.8 or fast < 1.0:
		return
	_wake_t = clampf(1.2 / fast, 0.08, 0.5)
	var at := Vector3(global_position.x, surface, global_position.z) + global_transform.basis.z * float(p["length"]) * 0.4
	Splashes.ring(at, 1.0 + fast * 0.12)
	if fast > 6.0:
		Splashes.splash(at, clampf(fast / 30.0, 0.1, 0.6))

## Flight: turn toward where the rider looks, thrust along the nose, climb and descend.
## Without a rider the ship settles to the ground and stays put.
func _fly(delta: float, g: float) -> void:
	var top: float = p["speed"] * (p["boost"] if boosting else 1.0)
	var want: float = drive.y * (top if drive.y >= 0.0 else float(p["reverse"]))
	spd = move_toward(spd, want, float(p["accel"]) * (1.0 if absf(want) > absf(spd) else 1.5) * delta)
	var fwd := -global_transform.basis.z
	if rider != null and (is_on_floor() == false or drive.y > 0.1 or lift > 0.1):
		# Nose follows the view; pitch is limited so the ship never flips over.
		var a := aim.normalized()
		var pitch := clampf(asin(clampf(a.y, -1.0, 1.0)), -1.2, 1.2)
		var yaw := atan2(-a.x, -a.z)
		var k := clampf(float(p["turn"]) * delta, 0.0, 1.0)
		var dyaw := wrapf(yaw - rotation.y, -PI, PI)
		rotation.y += dyaw * k * 2.0
		rotation.x = lerp_angle(rotation.x, pitch if absf(spd) > 2.0 else 0.0, k * 2.0)
		rotation.z = lerp_angle(rotation.z, clampf(dyaw * 1.2, -0.7, 0.7), k * 2.0)
		fwd = -global_transform.basis.z
	else:
		rotation.x = lerp_angle(rotation.x, 0.0, clampf(delta * 2.0, 0.0, 1.0))
		rotation.z = lerp_angle(rotation.z, 0.0, clampf(delta * 2.0, 0.0, 1.0))
	if rider != null:
		velocity = fwd * spd + Vector3.UP * lift * 12.0
		if absf(spd) < 0.5 and absf(lift) < 0.1 and not is_on_floor():
			velocity = velocity.lerp(Vector3.ZERO, clampf(delta * 3.0, 0.0, 1.0)) # hold a hover
	else:
		spd = move_toward(spd, 0.0, 20.0 * delta)
		velocity.x = fwd.x * spd
		velocity.z = fwd.z * spd
		velocity.y = maxf(velocity.y - _gravity * delta, -20.0)
	if is_nan(g):
		velocity.y = maxf(velocity.y, 0.0) # the ground below isn't loaded: don't sink into it
	elif global_position.y < g - 3.0:
		global_position.y = g + 0.5
	at_ceiling = not is_nan(g) and global_position.y - g > CEILING - 3.0
	if at_ceiling and lift > 0.5 and rider != null:
		leaving += delta
	else:
		leaving = 0.0
	if not is_nan(g) and global_position.y - g > CEILING and velocity.y > 0.0:
		velocity.y = 0.0
	move_and_slide()
	if is_on_floor() and rider == null:
		spd = 0.0
	rec["pos"] = global_position
	rec["yaw"] = rotation.y

## Lean with the ground, bank into turns, and animate the horse.
func _pose(delta: float, g: float) -> void:
	if flies():
		return
	var up := Vector3.UP
	if not hover() and is_on_floor():
		up = get_floor_normal()
	elif hover() and ground.is_valid():
		var f := -global_transform.basis.z * 1.5
		var hf: float = ground.call(global_position.x + f.x, global_position.z + f.z)
		if not is_nan(hf):
			up = Vector3(0, 1, 0).rotated(global_transform.basis.x, clampf((hf - g) * 0.12, -0.25, 0.25))
	var local_up := global_transform.basis.inverse() * up
	var bank := -drive.x * clampf(absf(spd) / float(p["speed"]), 0.0, 1.0) * (0.3 if hover() else 0.06)
	var want := Basis(Quaternion(Vector3.UP, local_up.normalized())) * Basis(Vector3.FORWARD, bank)
	_tilt = _tilt.slerp(want.orthonormalized(), clampf(delta * 6.0, 0.0, 1.0))
	_model.basis = _tilt
	if barrel != null:
		kick = move_toward(kick, 0.0, delta * 1.6)
		barrel.rotation.x = elevation
		barrel.position = Cannon.TRUNNION + Vector3(0, 0, 0.16 * kick * kick)
	if _animal:
		var s := absf(spd)
		if s < 0.3:
			_animal.play("Idle")
		elif s < 4.0:
			_animal.play("Walk", clampf(s / 2.2, 0.6, 1.6))
		else:
			_animal.play("Gallop", clampf(s / 9.0, 0.7, 1.5))

## The rider's world transform: on the seat, facing forward with the vehicle's lean.
func seat_transform() -> Transform3D:
	return global_transform * Transform3D(_model.basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, seat)

## A clear spot beside the vehicle to step off onto.
func exit_point() -> Vector3:
	var side := global_transform.basis.x
	for s in [1.0, -1.0]:
		var q: Vector3 = global_position + side * s * (half_width + 0.9)
		var h: float = ground.call(q.x, q.z) if ground.is_valid() else NAN
		if not is_nan(h) and absf(h - global_position.y) < 2.5:
			return Vector3(q.x, h + 0.2, q.z)
	return global_position + Vector3(0, height + 0.3, 0)
