class_name BoatNode
extends Node3D
## One boat on the water: its model riding the waves (pitch and roll from the swell
## under bow, stern and beam), sailing its loop or lying at anchor, leaving a wake. The
## crew stand at their stations aboard (NPCManager keeps them there through deck_xf).
## Moving boats heave to while someone is close, so you can come alongside and talk.
## A boat put in the water by Boats spawning code (pirates) can be steered with sail_to.

signal arrived(boat: BoatNode)

var site: Dictionary
var kind: String
var faction := "folk" ## "folk" or "pirate": who the crew are (NPC roles reads this)
var crew_nodes: Array = [] ## the NPC nodes aboard, while the crew is loaded
var body: CollisionObject3D
var model: Node3D
var deck := 0.3
var route_t := 0.0 ## seconds along the boat's loop
var held := 0.0 ## 0 sailing .. 1 hove to
var goal := Vector2.INF ## sail_to target (spawned boats)
var speed := 0.0
var players: Callable ## () -> Array of player positions near enough to matter
var rowing := 0.0 ## 0 oars at rest .. 1 pulling (rowboats)
var row_offset := 0.0 ## where this boat's stroke is in the shared rowing clock

var _water: BoatWater
var _trail: BoatWake
var _wake_v := 0.0 ## her speed, smoothed, for the waves she raises (water_wakes)
var _bow_y := NAN ## the bow's height last frame, to catch it slamming down into a wave
var _slam_t := 0.0
var _oar_ph := 0.0
var _oars: Array = [] ## [node, side]

var _wake_t := 0.0
var _line := PackedVector2Array() ## the hull's waterline outline (BoatModel.waterline)
var _bob := Vector3.ZERO
var _heel := 0.0
var _anchor: Node3D ## the anchor cable, shown only while she lies at anchor
var _fenders: Node3D ## fenders over the side, likewise only while she lies still
var _rig: BoatRig ## her sails, trimmed to the wind
var _yaw := 0.0
var _pos2 := Vector2.ZERO

func setup(s: Dictionary, t: float) -> BoatNode:
	site = s
	kind = s["boat"]
	faction = String(s.get("faction", "folk"))
	route_t = t
	name = "Boat_%s_%d_%d" % [kind, int(s["sx"]), int(s["sz"])]
	return self

func _ready() -> void:
	var d: Dictionary = Boats.KINDS[kind]
	# Anchored boats and rafts are still enough to stand on; the rest are moved by code.
	if float(d["moves"]) > 0.0 or site.has("spawned"):
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = false
		body = ab
	else:
		body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("boat", self)
	add_child(body)
	model = BoatModel.build(kind, int(site.get("seed", 1)), body)
	add_child(model)
	deck = BoatModel.deck_y(kind)
	_water = BoatWater.build(kind)
	add_child(_water)
	_trail = BoatWake.make(kind)
	add_child(_trail)
	row_offset = float(int(site.get("seed", 1)) % 97) / 97.0
	_anchor = model.get_node_or_null("Anchor")
	_fenders = model.get_node_or_null("Fenders")
	_rig = model.get_node_or_null("Rig")
	for s in [1.0, -1.0]:
		var o: Node3D = model.get_node_or_null("Oar_r" if s > 0.0 else "Oar_l")
		if o:
			_oars.append([o, s])
	var pose := Boats.pose_at(site, route_t)
	_pos2 = pose[0]
	_yaw = pose[1]
	if site.has("spawned"):
		_pos2 = site["center"]
		_yaw = float(site.get("yaw", 0.0))
	_place(0.0)
	_water.follow(_pos2, _yaw, 0.0)
	if float(d["moves"]) > 0.0 and not site.has("spawned"):
		prime_wake()

## Lays down the wake she'd have left over the last minute of her loop, so a boat that
## comes into view under way already has a track behind her.
func prime_wake() -> void:
	var d: Dictionary = Boats.KINDS[kind]
	var L := float(d["len"])
	var prev: Vector2 = Boats.pose_at(site, route_t - BoatWake.LIFE - 0.5)[0]
	var ago := BoatWake.LIFE
	while ago >= 0.0:
		var pose := Boats.pose_at(site, route_t - ago)
		var p: Vector2 = pose[0]
		var v := p.distance_to(prev) / 0.5
		prev = p
		var fwd := Vector2(-sin(float(pose[1])), -cos(float(pose[1])))
		_trail.feed(p - fwd * L * 0.45, fwd, v, _wake_strength(v, L), 0.5, ago)
		ago -= 0.5

static func _wake_strength(v: float, L: float) -> float:
	return clampf(pow(v / 4.0, 0.7), 0.0, 1.0) * clampf(0.45 + L / 16.0, 0.45, 1.0)

func _physics_process(delta: float) -> void:
	var d: Dictionary = Boats.KINDS[kind]
	var near := false
	if players.is_valid():
		for p in players.call():
			if (p as Vector3).distance_to(global_position) < float(d["len"]) * 0.5 + 12.0:
				near = true
	if goal != Vector2.INF:
		_steer(delta, d)
	elif float(d["moves"]) > 0.0:
		held = move_toward(held, 1.0 if near else 0.0, delta * 0.25)
		route_t += delta * (1.0 - held)
		var pose := Boats.pose_at(site, route_t)
		var to: Vector2 = pose[0]
		speed = to.distance_to(_pos2) / maxf(delta, 0.0001)
		_pos2 = to
		_yaw = lerp_angle(_yaw, float(pose[1]), clampf(delta * 2.0, 0.0, 1.0))
	else:
		var pose := Boats.pose_at(site, route_t)
		route_t += delta
		_yaw = float(pose[1])
		speed = 0.0
	_place(delta)
	_wake(delta, d)
	_slam(delta, d)
	_water.follow(_pos2, _yaw, clampf(pow(speed / 4.0, 0.7), 0.0, 1.0))
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	var L := float(d["len"])
	_trail.feed(_pos2 - fwd * L * 0.45, fwd, speed, _wake_strength(speed, L), delta)
	_wake_v = lerpf(_wake_v, speed, clampf(delta * 0.8, 0.0, 1.0))
	if not _oars.is_empty():
		rowing = move_toward(rowing, 1.0 if speed > 0.3 else 0.0, delta * 0.8)
		_row()

## Swings the oars through the stroke, in time with the rower (BodyLanguage.row): each
## blade throws up a splash as it bites at the catch and leaves a swirl and drips as it
## lifts out at the finish.
func _row() -> void:
	var ph := BodyLanguage.row_phase(row_offset)
	var catch_ := ph < _oar_ph # wrapped round: the blades go in
	var finish := _oar_ph < 0.42 and ph >= 0.42
	_oar_ph = ph
	for o in _oars:
		var oar := o[0] as Node3D
		oar.basis = BoatModel.oar_stroke(float(o[1]), ph, rowing)
		if rowing > 0.5 and (catch_ or finish) and _fx_near(oar.global_position, 90.0):
			var tip := oar.global_transform * Vector3(BoatModel.OAR_OUT - 0.25, 0.0, 0.0)
			var at := Vector3(tip.x, Water.surface_height(tip.x, tip.z, _water_t()), tip.z)
			if catch_:
				Splashes.splash(at, 0.12)
			else:
				Splashes.splash(at, 0.05)
				Splashes.ring(at, 0.9)

## Spawned boats: head for `goal` at the kind's pace (a pirate closing in).
func _steer(delta: float, d: Dictionary) -> void:
	var to := goal - _pos2
	var top := maxf(float(d["moves"]), 3.0) * 1.4
	if to.length() < float(d["len"]) * 0.6 + 4.0:
		speed = move_toward(speed, 0.0, delta * 1.5)
		if speed < 0.05:
			goal = Vector2.INF
			arrived.emit(self)
	else:
		speed = move_toward(speed, top, delta * 1.0)
		var want := atan2(-to.x, -to.y)
		_yaw = lerp_angle(_yaw, want, clampf(delta * 0.5, 0.0, 1.0))
	_pos2 += Vector2(-sin(_yaw), -cos(_yaw)) * speed * delta
	site["center"] = _pos2
	site["yaw"] = _yaw

## Rides the swell: heave from the water under the middle, pitch and roll from the
## difference between bow and stern, port and starboard. On top of that every hull keeps
## rocking a little (more in a wind, less the bigger she is), a sailing boat heels away
## from the wind while she's under way, and a launch lifts her bow at speed.
func _place(delta: float) -> void:
	var d: Dictionary = Boats.KINDS[kind]
	var L: float = d["len"]
	var t := fmod(GameClock.sec(), 3600.0)
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	var side := Vector2(fwd.y, -fwd.x) # port (-x when she faces -z)
	var c := _pos2
	var half := L * 0.4
	var beam := maxf(L * 0.14, 0.8)
	var hc := Water.surface_height(c.x, c.y, t)
	var hb := Water.surface_height(c.x + fwd.x * half, c.y + fwd.y * half, t)
	var hs := Water.surface_height(c.x - fwd.x * half, c.y - fwd.y * half, t)
	var hp := Water.surface_height(c.x + side.x * beam, c.y + side.y * beam, t)
	var hq := Water.surface_height(c.x - side.x * beam, c.y - side.y * beam, t)
	# Big hulls average the small waves out and answer slowly.
	var mass := clampf(L / 8.0, 0.5, 3.0)
	var want := Vector3((hb + hs + hp + hq + hc * 2.0) / 6.0, atan2(hb - hs, half * 2.0) / mass, atan2(hp - hq, beam * 2.0) / mass)
	# The hull's own rocking: two out-of-step swings each way so it never looks like a
	# metronome, slower and smaller for big hulls, and calmer with someone aboard.
	var ph := float(int(site.get("seed", 1)) % 1000) * 0.37
	var wind := Water._wind
	var sm := sqrt(mass)
	var calm := 1.0 - 0.4 * held
	var per := 2.6 * sm
	var amp := (0.025 + wind * 0.07) / sm * calm
	var rock := Vector3(
		(0.02 + wind * 0.1) / sm * calm * sin(t * TAU / (per * 1.3) + ph * 2.0),
		amp * 0.5 * (sin(t * TAU / (per * 1.17) + ph) + 0.35 * sin(t * TAU / (per * 0.53) + ph * 3.0)),
		amp * (sin(t * TAU / per + ph * 1.7) + 0.3 * sin(t * TAU / (per * 0.61) + ph * 0.6)))
	want += rock
	var v := float(d["moves"])
	var way := clampf(speed / maxf(v, 0.5), 0.0, 1.0)
	if kind == "launch":
		want.y += 0.06 * way # bow up on the plane
	var heel := 0.0
	if kind in ["cog", "fishing_boat"]:
		# The wind's push across her (toward starboard is +) heels her to leeward, lifting
		# the windward side (a + roll lifts port).
		var across := Water._dir.normalized().dot(-side)
		heel = across * (0.04 + wind * 0.16) * way * (1.25 if kind == "fishing_boat" else 1.0)
	_heel = heel if delta <= 0.0 else lerpf(_heel, heel, clampf(delta * 0.3, 0.0, 1.0))
	want.z += _heel
	_bob = want if delta <= 0.0 else _bob.lerp(want, clampf(delta * 3.0 / mass, 0.0, 1.0))
	# Pitch: + lifts the bow (-z). Roll: + lifts the port side (-x).
	var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _bob.y) * Basis(Vector3.BACK, -_bob.z)
	global_transform = Transform3D(b, Vector3(c.x, _bob.x, c.y))
	if _anchor:
		_anchor.visible = speed < 0.2
	if _fenders:
		_fenders.visible = speed < 0.2
	if _rig:
		# The wind she feels: the true wind (Atmosphere's, via Water) less her own way.
		# Rafts never anchor, so theirs stays up.
		var air := Water._dir.normalized() * (1.5 + wind * 11.0) - fwd * speed
		var lb := Basis(Vector3.UP, _yaw).inverse() * Vector3(-air.x, 0.0, -air.y)
		_rig.trim(Vector2(lb.x, lb.z), wind, speed > 0.25 or not d.has("rest"), delta)

## Splashes come from a small shared pool (Splashes): only spend them where they'll be seen.
func _fx_near(at: Vector3, within: float) -> bool:
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(at) < within

static func _water_t() -> float:
	return fmod(GameClock.sec(), 3600.0)

## The bow pitching down into the swell (or a wave under it) shoves water aside: when it
## drops fast enough, spray flies up round the stem and a ring spreads from it. Harder the
## faster she's going and the bigger she is.
func _slam(delta: float, d: Dictionary) -> void:
	var L := float(d["len"])
	var bow := global_transform * Vector3(0.0, 0.0, -L * 0.42)
	_slam_t -= delta
	if is_nan(_bow_y) or delta <= 0.0:
		_bow_y = bow.y
		return
	var fall := (_bow_y - bow.y) / delta
	_bow_y = bow.y
	if _slam_t > 0.0 or kind in ["raft", "life_raft"] or not _fx_near(bow, 160.0):
		return
	if fall > 0.16 + 0.006 * L - minf(speed, 4.0) * 0.02:
		_slam_t = randf_range(1.2, 2.4)
		var at := Vector3(bow.x, Water.surface_height(bow.x, bow.z, _water_t()), bow.z)
		Splashes.splash(at, clampf(0.12 + fall * 0.5 + speed * 0.04, 0.12, 0.7) * clampf(L / 10.0, 0.4, 1.2))
		Splashes.ring(at, 1.0 + L * 0.08)

func _wake(delta: float, d: Dictionary) -> void:
	_wake_t -= delta
	if _wake_t > 0.0:
		return
	if speed < 0.6:
		# At rest the swell still slaps the hull: now and then a soft ring spreads from a
		# point on the waterline.
		_wake_t = randf_range(0.8, 2.2)
		if _line.is_empty():
			_line = BoatModel.waterline(kind)
		var q := _line[randi() % _line.size()]
		var at := global_transform * Vector3(q.x * 1.05, 0.0, q.y * 1.02)
		Splashes.ring(Vector3(at.x, Water.surface_height(at.x, at.z, fmod(GameClock.sec(), 3600.0)), at.z), 0.5 + float(d["len"]) * 0.03)
		return
	_wake_t = clampf(1.4 / speed, 0.12, 0.6)
	var at := global_position + global_transform.basis.z * float(d["len"]) * 0.45
	Splashes.ring(Vector3(at.x, Water.surface_height(at.x, at.z, fmod(GameClock.sec(), 3600.0)), at.z), 0.8 + speed * 0.25)
	if speed > 3.0:
		var bow := global_position - global_transform.basis.z * float(d["len"]) * 0.45
		Splashes.splash(bow, clampf(speed / 25.0, 0.05, 0.3))

## Where crew station i is now: feet position and facing, in world space.
func deck_xf(i: int) -> Transform3D:
	var st: Array = BoatModel.stations(kind)
	if st.is_empty():
		return global_transform
	var s: Dictionary = st[i % st.size()]
	var local := Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["p"])
	return global_transform * local

## What crew station i is for: {p, yaw, pose, sit?} (BoatModel.STATIONS).
func station(i: int) -> Dictionary:
	var st: Array = BoatModel.stations(kind)
	return {"pose": "stand"} if st.is_empty() else st[i % st.size()]

## The waves she raises, for the water shader (water_wakes): [bow x, z, heading x, z] and
## [speed, length, half-beam, strength], or [] while she's (nearly) still.
func wake_info() -> Array:
	if _wake_v < 0.15:
		return []
	var L := float(Boats.KINDS[kind]["len"])
	var fwd := Vector2(-sin(_yaw), -cos(_yaw))
	var bow := _pos2 + fwd * L * 0.47
	var w := clampf((_wake_v - 0.15) / 0.6, 0.0, 1.0)
	return [Vector4(bow.x, bow.y, fwd.x, fwd.y), Vector4(_wake_v, L, _trail.beam, w)]

## The boat's place on the water as a 2D point.
func pos2() -> Vector2:
	return _pos2

## Spawned boats: sail toward a point on the water (arrived fires when there).
func sail_to(target: Vector2) -> void:
	goal = target

## The crew's NPC nodes aboard (only while they are loaded near a player).
func crew() -> Array:
	return crew_nodes.filter(func(n): return is_instance_valid(n))
