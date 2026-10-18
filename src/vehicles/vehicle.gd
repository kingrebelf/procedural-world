class_name Vehicle
extends CharacterBody3D
## Something you ride: a hover speeder, a survey rover, a riding horse or a small boat.
## Arcade handling: throttle and steering from the rider, the body follows the ground (or
## hovers over land and water). Boats float and move by Sailing's physics instead: the
## wind in the sail, paddles, the keel and the rudder. The vehicle's record in
## Game.vehicles is its save state; this node keeps the record's position and heading up
## to date while it exists.

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
	# Boats: "boat" is the BoatModel hull, "seat_at" where the rider's hips go, "speed" her
	# rough top speed (for sounds and the HUD); Sailing.BOATS has how she handles.
	"sail_raft": {"name": "Sail Raft", "boat": "raft", "length": 3.4, "speed": 2.0, "seat_at": Vector3(-0.45, 0.77, 0.95)},
	"canoe": {"name": "Canoe", "boat": "canoe", "length": 4.8, "speed": 2.6, "seat_at": Vector3(0, 0.1, 1.45)},
	"kayak": {"name": "Kayak", "boat": "kayak", "length": 4.0, "speed": 3.2, "seat_at": Vector3(0, -0.05, 0.3)},
	"rowboat": {"name": "Rowboat", "boat": "rowboat", "length": 4.4, "speed": 2.8, "seat_at": Vector3(0, 0.36, 0.25)},
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
## Boats: Sailing's state (velocity, sheet, heel...), the sails, the foam round her and her
## wake, the rowboat's oars and where they are in the stroke.
var sail: Dictionary = {}
var auto_trim := false ## the rider's setting: the sail trims itself and W/S paddle
var _rig: BoatRig
var _foam: BoatWater
var _trail: BoatWake
var _oars: Array = []
var _stroke := 0.0
var _wake_v := 0.0

static func is_vehicle_item(type: String) -> bool:
	return KINDS.has(type)

static func label(k: String) -> String:
	return KINDS.get(k, {}).get("name", k.capitalize())

static func is_boat(k: String) -> bool:
	return KINDS.get(k, {}).has("boat")

## Where the rider's hips go on kind `k`, local, given the model's bounds.
static func seat_for(k: String, box: AABB) -> Vector3:
	var d: Dictionary = KINDS[k]
	if d.has("seat_at"):
		return d["seat_at"]
	if d.has("animal"):
		return Vector3(0, box.size.y * 0.66, 0.15)
	if d.get("stand", false):
		return Vector3(0, 0, float(d["seat_z"])) # where the feet go
	return Vector3(0, box.size.y * float(d.get("seat", 0.55)), float(d.get("seat_z", 0.25)))

## The model on its own, scaled to the vehicle's length and facing -z (also for icons).
static func make_model(k: String) -> Node3D:
	var d: Dictionary = KINDS[k]
	if d.get("proc", "") == "cannon":
		return Cannon.model()
	var holder := Node3D.new()
	if d.has("boat"):
		# Built from code like the boats on the lakes; their collision isn't wanted here.
		var scrap := StaticBody3D.new()
		holder.add_child(BoatModel.build(d["boat"], 7, scrap))
		scrap.free()
		return holder
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
		if m.mesh == null:
			continue # a boat's sheets before they're first drawn
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
	if boat():
		_setup_boat(bs, shape)
	add_child(shape)
	seat = seat_for(kind, box)
	position = r["pos"]
	rotation.y = r["yaw"]
	return self

## A boat floats: no floor, a hull-sized box at the waterline that bumps into shores, and
## the water's answer to her (foam and wake).
func _setup_boat(bs: BoxShape3D, shape: CollisionShape3D) -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var hull := _model.get_child(0).get_node_or_null("Hull") as MeshInstance3D
	var hb := hull.mesh.get_aabb() if hull else AABB(Vector3(-0.5, 0, -1), Vector3(1, 0.5, 2))
	bs.size = Vector3(hb.size.x * 0.9, 0.6, hb.size.z * 0.92)
	shape.position = Vector3(hb.get_center().x, 0.25, hb.get_center().z)
	height = minf(height, 1.2)
	half_width = hb.size.x * 0.5
	sail = Sailing.new_state(float(rec["yaw"]))
	sail["raised"] = false
	_rig = _model.get_child(0).get_node_or_null("Rig")
	var m: Node3D = _model.get_child(0)
	for sd in [1.0, -1.0]:
		var o: Node3D = m.get_node_or_null("Oar_r" if sd > 0.0 else "Oar_l")
		if o:
			_oars.append([o, sd])
	_foam = BoatWater.build(p["boat"])
	add_child(_foam)
	_trail = BoatWake.make(p["boat"])
	add_child(_trail)
	add_to_group("wake_boats")

func hover() -> bool:
	return p.has("hover")

func boat() -> bool:
	return p.has("boat")

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
	if boat():
		_float(delta, g)
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

## Afloat: Sailing moves her (sail, paddles, keel, rudder, the river's current) and she
## rides the swell, heeling to the wind. With nobody aboard she's tied up and stays put.
func _float(delta: float, g: float) -> void:
	if is_nan(g):
		velocity = Vector3.ZERO
		return
	var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var pos := Vector2(global_position.x, global_position.z)
	var surface := Water.surface_height(pos.x, pos.y, t)
	var d: Dictionary = Sailing.BOATS[kind]
	var wind := Water._dir.normalized() * Sailing.wind_speed(Water._wind)
	sail["yaw"] = rotation.y
	if rider != null:
		var paddle := 0.0
		var sheet := 0.0
		var auto := auto_trim
		# W/S work the sheet while the sail is up and you trim it yourself; otherwise they
		# paddle (or pole the raft along).
		if float(d["sail"]) > 0.0 and bool(sail["raised"]) and not auto:
			sheet = drive.y
		else:
			paddle = drive.y
		Sailing.step(kind, sail, delta, wind, Water.current(pos.x, pos.y), drive.x, paddle, sheet, auto, surface - g)
		_row(delta, paddle)
	else:
		sail["vel"] = (sail["vel"] as Vector2).lerp(Vector2.ZERO, clampf(delta * 2.0, 0.0, 1.0))
		sail["omega"] = 0.0
		sail["heel"] = lerpf(float(sail["heel"]), 0.0, clampf(delta, 0.0, 1.0))
		_row(delta, 0.0)
	var v: Vector2 = sail["vel"]
	var L := float(p["length"])
	# Dry land ahead: she runs up the beach no further (but can back off it).
	if v.length() > 0.05:
		var dir := v.normalized()
		var at := pos + dir * (L * 0.45 + 0.2)
		var ga: float = ground.call(at.x, at.y)
		if not is_nan(ga) and Water.surface_height(at.x, at.y, t) - ga < 0.05:
			v -= dir * maxf(v.dot(dir), 0.0)
	rotation.y = float(sail["yaw"])
	velocity = Vector3(v.x, clampf((_heave(t, L) - global_position.y) * 5.0, -3.0, 3.0), v.y)
	move_and_slide()
	# Bumping into a shore or a jetty takes her way off.
	var real := get_real_velocity()
	sail["vel"] = Vector2(real.x, real.z) if v.length() > 0.05 and real.is_finite() else v
	var fwd := Sailing.fwd(rotation.y)
	spd = (sail["vel"] as Vector2).dot(fwd)
	_float_pose(delta, t, L)
	if _rig:
		var air := wind - (sail["vel"] as Vector2)
		var from := Basis(Vector3.UP, rotation.y).inverse() * Vector3(-air.x, 0.0, -air.y)
		_rig.trim(Vector2(from.x, from.z), Water._wind, bool(sail["raised"]), delta, Sailing.sail_turn(kind, sail), 1.0 - float(sail["luff"]))
	var sp := absf(spd)
	_wake_v = lerpf(_wake_v, sp, clampf(delta * 0.8, 0.0, 1.0))
	_foam.follow(pos, rotation.y, clampf(pow(sp / 4.0, 0.7), 0.0, 1.0))
	_trail.feed(pos - fwd * L * 0.45, fwd, sp, BoatNode._wake_strength(sp, L), delta)
	rec["pos"] = global_position
	rec["yaw"] = rotation.y

## The water level under her middle, the small waves averaged over her length.
func _heave(t: float, L: float) -> float:
	var f := -global_transform.basis.z * L * 0.35
	var x := global_position.x
	var z := global_position.z
	return (Water.surface_height(x + f.x, z + f.z, t) + Water.surface_height(x - f.x, z - f.z, t) + Water.surface_height(x, z, t) * 2.0) / 4.0

## Pitch and roll with the swell under bow and stern, port and starboard, and the heel
## the wind in her sail gives her.
func _float_pose(delta: float, t: float, L: float) -> void:
	var f := -global_transform.basis.z
	var sd := global_transform.basis.x
	var half := L * 0.4
	var beam := maxf(half_width, 0.4)
	var x := global_position.x
	var z := global_position.z
	var hb := Water.surface_height(x + f.x * half, z + f.z * half, t)
	var hs := Water.surface_height(x - f.x * half, z - f.z * half, t)
	var hp := Water.surface_height(x - sd.x * beam, z - sd.z * beam, t)
	var hq := Water.surface_height(x + sd.x * beam, z + sd.z * beam, t)
	# Pitch: + lifts the bow. Roll: + lifts the port side (heel to starboard is +).
	var pitch := atan2(hb - hs, half * 2.0)
	var roll := atan2(hp - hq, beam * 2.0) * 0.7 + float(sail["heel"])
	roll += -drive.x * clampf(absf(spd) / 3.0, 0.0, 1.0) * 0.03 if rider != null else 0.0
	var want := Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, -roll)
	_tilt = _tilt.slerp(want.orthonormalized(), clampf(delta * 3.0, 0.0, 1.0))
	_model.basis = _tilt

## The rowboat's oars swing through the stroke while you row (backwards to back water);
## canoe and kayak paddles dip a ring into the water now and then on each side.
func _row(delta: float, paddle: float) -> void:
	var w := absf(paddle)
	if w > 0.05:
		var before := fposmod(_stroke, 1.0)
		_stroke += delta * 0.85
		var ph := fposmod(_stroke, 1.0)
		if _oars.is_empty() and (ph < before or (before < 0.5 and ph >= 0.5)):
			var sd := 1.0 if ph < 0.5 else -1.0
			var at := global_transform * Vector3(sd * (half_width + 0.35), 0.0, -0.2)
			Splashes.ring(Vector3(at.x, Water.surface_height(at.x, at.z, fmod(Time.get_ticks_msec() / 1000.0, 3600.0)), at.z), 0.6)
	if _oars.is_empty():
		return
	sail["rowing"] = move_toward(float(sail.get("rowing", 0.0)), 1.0 if w > 0.05 else 0.0, delta * 1.5)
	var phase := fposmod(_stroke, 1.0)
	if paddle < 0.0:
		phase = 1.0 - phase
	for o in _oars:
		(o[0] as Node3D).basis = BoatModel.oar_stroke(float(o[1]), phase, float(sail["rowing"]))

## The waves she raises, for the water shader (BoatManager): as BoatNode.wake_info.
func wake_info() -> Array:
	if _wake_v < 0.15 or _trail == null:
		return []
	var L := float(p["length"])
	var fwd := Sailing.fwd(rotation.y)
	var bow := Vector2(global_position.x, global_position.z) + fwd * L * 0.47
	return [Vector4(bow.x, bow.y, fwd.x, fwd.y), Vector4(_wake_v, L, _trail.beam, clampf((_wake_v - 0.15) / 0.6, 0.0, 1.0))]

## Raises or lowers the sail. Returns whether it's now up.
func toggle_sail() -> bool:
	if not boat() or float(Sailing.BOATS[kind]["sail"]) <= 0.0:
		return false
	sail["raised"] = not bool(sail["raised"])
	return sail["raised"]

func has_sail() -> bool:
	return boat() and float(Sailing.BOATS[kind]["sail"]) > 0.0

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

## A clear spot beside the vehicle to step off onto. Off a boat out on the water, that's
## into the water beside her.
func exit_point() -> Vector3:
	var side := global_transform.basis.x
	var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	for s in [1.0, -1.0]:
		var q: Vector3 = global_position + side * s * (half_width + 0.9)
		var h: float = ground.call(q.x, q.z) if ground.is_valid() else NAN
		if is_nan(h) or absf(h - global_position.y) >= 2.5:
			continue
		if boat() and Water.surface_height(q.x, q.z, t) - h > 0.6:
			continue
		return Vector3(q.x, h + 0.2, q.z)
	if boat():
		var q: Vector3 = global_position + side * (half_width + 0.7)
		return Vector3(q.x, Water.surface_height(q.x, q.z, t) - 0.9, q.z)
	return global_position + Vector3(0, height + 0.3, 0)
