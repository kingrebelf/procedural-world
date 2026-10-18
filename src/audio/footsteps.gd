class_name Footsteps
extends RefCounted
## The player's own movement sounds: footsteps that match the ground (grass, stone,
## wood, snow, sand, gravel, metal decking, rugs), landings, swimming strokes and
## splashes, hooves when riding, and engine and jetpack loops.

const HOUSE_FLOORS := ["cottage", "townhouse", "longhouse"] ## timber floors inside

var _dist := 0.0
var _swim_t := 0.0
var _was_swimming := false
var _surface := "grass"
var _surface_t := 0.0
var _stride := 2.2
var _foot := 0 ## which foot came down last (0 or 1)

## Each physics frame on foot. hspeed: horizontal speed; landed_vy: the downward speed
## of a landing this frame (0 if none).
func tick(pl: Player, delta: float, hspeed: float, on_floor: bool, crouched: bool, landed_vy: float, jumped: bool) -> void:
	if pl.swimming:
		if not _was_swimming:
			Audio.play("water/splash", -2.0)
		_swim_t -= delta
		if hspeed > 0.6 and not pl.underwater and _swim_t <= 0.0:
			_swim_t = 1.1
			Audio.play("water/splash", -14.0, 0.15)
		_was_swimming = true
		_dist = 0.0
		return
	_was_swimming = false
	_surface_t -= delta
	if _surface_t <= 0.0 or landed_vy > 0.0 or jumped:
		_surface_t = 0.25
		_surface = surface(pl)
	if landed_vy > 4.0:
		var loud := clampf((landed_vy - 4.0) * 1.5, 0.0, 10.0)
		_step(-8.0 + loud)
		if landed_vy > 8.0:
			Audio.play("hit/dig", -14.0 + loud)
		_dist = 0.0
	if jumped:
		_step(-8.0)
		_dist = 0.0
	if not on_floor or hspeed < 0.4:
		return
	_dist += hspeed * delta
	var stride := 1.7 + hspeed * 0.12
	_stride = stride
	if _dist >= stride:
		_dist -= stride
		_foot = 1 - _foot
		var vol := -9.0 if crouched else (-6.0 if hspeed < Player.SPRINT * 0.8 else -3.0)
		_step(vol)

## Where you are in your gait, 0-1 over two steps (left then right): a footstep sounds
## at 0 and 0.5. The head bob (Player) follows it so the view dips as each foot lands.
func gait() -> float:
	return (float(_foot) + clampf(_dist / _stride, 0.0, 1.0)) * 0.5

func _step(vol: float) -> void:
	match _surface:
		"sand":
			Audio.play("step/snow", vol - 3.0, 0.06, 0.72)
		"wade":
			Audio.play("water/splash", vol - 8.0, 0.2)
		_:
			Audio.play("step/" + _surface, vol, 0.07)

## Riding: hooves on a horse, an engine hum on the rest.
func ride(v: Vehicle, delta: float) -> void:
	var spd := absf(v.spd)
	if v.kind == "horse":
		if spd < 0.5:
			return
		_dist += spd * delta
		var stride := 0.9 + spd * 0.06
		if _dist >= stride:
			_dist -= stride
			Audio.play("step/gravel", -7.0, 0.12)
		return
	if v.boat():
		return # boats are quiet: the water and the wind do the talking
	var top := float(v.p.get("speed", 20.0)) * float(v.p.get("boost", 1.0))
	var k := clampf(maxf(spd, v.velocity.length()) / top, 0.0, 1.0)
	Audio.hold_loop("engine_big" if v.flies() else "engine", 0.35 + 0.5 * k, 0.75 + 0.6 * k)

## What the player is standing on, as a step/ sound name (or "sand", "wade").
static func surface(pl: Player) -> String:
	var p := pl.global_position
	var t_water := fmod(GameClock.sec(), 3600.0)
	if Water.surface_height(p.x, p.z, t_water) > p.y + 0.15:
		return "wade"
	var space := pl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.3, 0), p - Vector3(0, 0.9, 0), 1, [pl.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return "grass"
	var col: Object = hit["collider"]
	if col.has_meta("stones"):
		return "stone"
	if col.has_meta("obj") and col.has_meta("chunk"):
		var oc: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = oc.get_object(col.get_meta("obj"))
		if o.is_empty():
			return "stone"
		var tt: String = o["t"]
		var mat := Durability.material(tt)
		if mat == "metal" or int(o.get("e", 0)) == 2:
			return "metal"
		if mat == "wood" or tt in HOUSE_FLOORS:
			return "wood"
		return "stone"
	if not col.has_meta("chunk"):
		return "stone"
	var c: ChunkNode = col.get_meta("chunk")
	var lx := p.x - c.key.x * ChunkGenerator.SIZE
	var lz := p.z - c.key.y * ChunkGenerator.SIZE
	var slope := ChunkGenerator.slope_at(c.data, lx, lz)
	var cv := GroundCover.at(c.cover, lx, lz)
	if cv.a > 0.45 or (c.cover.is_empty() and p.y > Planets.snow_line - 2.0 and slope < 0.6):
		return "snow"
	if ChunkGenerator.road_at(c.data, lx, lz) > 0.4:
		return "gravel"
	if ChunkGenerator.height_at(c.data, lx, lz) < Water.LEVEL + 1.2 or ChunkGenerator.by_river(c.data, lx, lz):
		return "gravel"
	# Scree and gravel beds crunch underfoot (GroundCover).
	if cv.g > 0.5 or cv.r > 0.5:
		return "gravel"
	if ChunkGenerator.cover_at(c.data, lx, lz) < 0.35:
		return "sand"
	if slope > 0.55 or ChunkGenerator.stone_at(c.data, lx, lz).a > 0.6:
		return "stone"
	return "grass"
