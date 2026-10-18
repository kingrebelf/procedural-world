class_name Sailing
extends RefCounted
## How a small boat moves on the water: the force a sail makes from the wind it feels,
## what paddles add, how the hull resists going forward and (much more) sideways, and
## how the rudder turns her. Pure functions on a state dictionary, so the physics can be
## tested without a scene and run the same for every player.
##
## Boat-local 2D space: x to starboard, y aft (the bow points to -y), like the 3D boats'
## x and z. World 2D is (x, z).

const RHO_AIR := 1.2
## Sail chord angle from the centreline (radians) at sheet 0 (hauled in) and 1 (eased
## right out), per rig. A square sail's chord runs across the boat: braced, it turns
## only so far; a fore-and-aft sail swings from nearly amidships to square out.
const RIGS := {
	"square": [PI * 0.5 - 0.7, PI * 0.5],
	"fore_aft": [0.1, 1.45],
}
## How close to the wind (the apparent wind's angle off the bow, radians) each rig still
## draws: inside it the sail only flaps. A square rig can't come much above the beam; a
## fore-and-aft sail points to about 45 degrees off the true wind.
const NO_GO := {"square": 1.1, "fore_aft": 0.55}

## Per boat kind: mass (kg, laden), sail area (m², 0 = none), rig, paddle force (N, 0 =
## none), forward drag k (N per (m/s)²), sideways resistance k, turn rate at speed
## (rad/s), draft (m: grounds shallower), stiff (how hard she resists heeling: a wide
## raft hardly leans at all), engine (the "paddle" is a motor), burn (seconds of full
## throttle on one can of fuel).
const BOATS := {
	"sail_raft": {"mass": 420.0, "sail": 3.6, "rig": "square", "paddle": 60.0, "drag": 38.0, "lateral": 160.0, "turn": 0.35, "draft": 0.2, "stiff": 0.5},
	"canoe": {"mass": 140.0, "sail": 0.0, "rig": "", "paddle": 85.0, "drag": 11.0, "lateral": 420.0, "turn": 0.6, "draft": 0.18},
	"kayak": {"mass": 110.0, "sail": 0.0, "rig": "", "paddle": 100.0, "drag": 8.0, "lateral": 380.0, "turn": 0.7, "draft": 0.16},
	"rowboat": {"mass": 260.0, "sail": 0.0, "rig": "", "paddle": 150.0, "drag": 18.0, "lateral": 520.0, "turn": 0.5, "draft": 0.3},
	# The existing boats, built on a slipway or in a vehicle bay. Engines push like paddles
	# that never tire ("engine": they burn fuel instead, Vehicle).
	"fishing_boat": {"mass": 3500.0, "sail": 24.0, "rig": "fore_aft", "paddle": 0.0, "drag": 150.0, "lateral": 10000.0, "turn": 0.4, "draft": 0.9, "stiff": 0.18},
	"cog": {"mass": 50000.0, "sail": 150.0, "rig": "square", "paddle": 0.0, "drag": 1000.0, "lateral": 60000.0, "turn": 0.2, "draft": 2.0, "stiff": 0.25},
	"motor_launch": {"mass": 2200.0, "sail": 0.0, "rig": "", "paddle": 5000.0, "drag": 55.0, "lateral": 3000.0, "turn": 0.8, "draft": 0.55, "engine": true, "burn": 600.0},
	"research_vessel": {"mass": 300000.0, "sail": 0.0, "rig": "", "paddle": 90000.0, "drag": 3500.0, "lateral": 300000.0, "turn": 0.15, "draft": 2.4, "engine": true, "burn": 900.0},
	"life_raft": {"mass": 180.0, "sail": 0.0, "rig": "", "paddle": 45.0, "drag": 35.0, "lateral": 120.0, "turn": 0.35, "draft": 0.2},
	"sloop": {"mass": 2600.0, "sail": 30.0, "rig": "fore_aft", "paddle": 0.0, "drag": 110.0, "lateral": 9000.0, "turn": 0.5, "draft": 1.1, "stiff": 0.14},
}

## A fresh state: velocity (world), yaw, yaw rate, sheet (0..1), sail side (+1 the sail
## out to starboard), heel (radians, + rolls her to starboard), and whether the sail is
## up.
static func new_state(yaw: float) -> Dictionary:
	return {"vel": Vector2.ZERO, "yaw": yaw, "omega": 0.0, "sheet": 0.5, "side": 1.0, "heel": 0.0, "raised": true,
		"drive": 0.0, "alpha": 0.0, "luff": 0.0}

## The wind's speed in m/s from Atmosphere's 0..1 wind strength.
static func wind_speed(strength: float) -> float:
	return 1.5 + strength * 11.0

static func fwd(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))

## World 2D vector to boat-local (x starboard, y aft).
static func to_local(v: Vector2, yaw: float) -> Vector2:
	return v.rotated(yaw)

static func to_world(v: Vector2, yaw: float) -> Vector2:
	return v.rotated(-yaw)

## The force (boat-local) a sail of `area` m² makes in air moving at `air` (local, the
## way the air goes) with its chord `delta` radians off the centreline, out on `side`.
## Returns [force, angle of attack]. Lift across the flow from the air the sail turns
## aside, plus drag along it; a sail edge-on to the flow (luffing) makes neither.
static func sail_force(air: Vector2, delta: float, side: float, area: float) -> Array:
	var s := air.length()
	if s < 0.05 or area <= 0.0:
		return [Vector2.ZERO, 0.0]
	var a := air / s
	var c := Vector2(side * sin(delta), cos(delta)) # luff to leech: aft and out to the side
	var alpha := acos(clampf(a.dot(c), -1.0, 1.0))
	# Lift climbs with the angle of attack, stalls past ~40 degrees.
	var cl := 1.3 * sin(2.0 * minf(alpha, 0.7))
	if alpha > 0.7:
		cl *= maxf(0.45, 1.0 - (alpha - 0.7) * 0.9)
	var cd := 0.08 + 1.15 * pow(sin(alpha), 2.0)
	var turned := c - a * a.dot(c)
	var lift := -turned.normalized() if turned.length() > 0.001 else Vector2.ZERO
	var q := 0.5 * RHO_AIR * s * s * area
	return [(lift * cl + a * cd) * q, alpha]

## The sheet angle that drives her best for this apparent wind (auto-trim): the sail
## eased until it just stops luffing, plus a little.
static func best_sheet(kind: String, air: Vector2, side: float) -> float:
	var d: Dictionary = BOATS[kind]
	var r: Array = RIGS[d["rig"]]
	var best := 0.5
	var top := -INF
	for i in 21:
		var sh := float(i) / 20.0
		var f: Vector2 = sail_force(air, lerpf(r[0], r[1], sh), side, 1.0)[0]
		if -f.y > top:
			top = -f.y
			best = sh
	return best

## One step of `dt` seconds. `wind`: the true wind (world, m/s, the way the air goes),
## `current`: the water's drift (world m/s), `rudder` -1..1 (+ turns to starboard),
## `paddle` -1..1 (stroking forward or back), `sheet_in` -1..1 (hauling in / easing out
## the sheet), `auto` trims the sheet itself, `depth` water under her (m).
static func step(kind: String, st: Dictionary, dt: float, wind: Vector2, current: Vector2, rudder: float, paddle: float,
		sheet_in: float, auto: bool, depth: float) -> void:
	var d: Dictionary = BOATS[kind]
	var yaw: float = st["yaw"]
	var v: Vector2 = st["vel"]
	# Through the water, not over the ground: the current carries water and boat alike.
	var vw := to_local(v - current, yaw)
	var air := to_local(wind, yaw) - vw
	var force := Vector2.ZERO
	var sail_x := 0.0
	st["drive"] = 0.0
	st["luff"] = 0.0
	if float(d["sail"]) > 0.0 and bool(st["raised"]):
		# The sail goes out to leeward, coming across only once the wind is clearly on
		# the other side (a gybe or a tack).
		if absf(air.x) > 0.3 and signf(air.x) != float(st["side"]):
			# 0 when the air flows forward along her (the wind dead astern).
			if absf(atan2(air.x, -air.y)) > 0.3:
				st["side"] = signf(air.x)
		var r: Array = RIGS[d["rig"]]
		if auto:
			st["sheet"] = move_toward(float(st["sheet"]), best_sheet(kind, air, float(st["side"])), dt * 0.6)
		else:
			st["sheet"] = clampf(float(st["sheet"]) - sheet_in * dt * 0.35, 0.0, 1.0)
		var res := sail_force(air, lerpf(r[0], r[1], float(st["sheet"])), float(st["side"]), float(d["sail"]))
		var off := acos(clampf(air.y / maxf(air.length(), 0.001), -1.0, 1.0))
		st["off"] = off
		var ng := float(NO_GO[d["rig"]])
		var draws := smoothstep(ng - 0.15, ng + 0.1, off)
		res[0] = (res[0] as Vector2) * draws
		if draws < 1.0:
			res[1] = float(res[1]) * draws
		force += res[0]
		sail_x = (res[0] as Vector2).x
		st["alpha"] = res[1]
		st["drive"] = -(res[0] as Vector2).y
		st["luff"] = 1.0 - smoothstep(0.05, 0.25, float(res[1]))
	force.y -= paddle * float(d["paddle"])
	# The hull: cheap to push ahead, hard to push sideways (the keel), drag both ways.
	force.y -= float(d["drag"]) * vw.y * absf(vw.y) + 6.0 * vw.y
	force.x -= float(d["lateral"]) * vw.x * absf(vw.x) + float(d["lateral"]) * 0.2 * vw.x
	var m := float(d["mass"])
	vw += force / m * dt
	var ahead := -vw.y
	# Aground: she stops dead.
	if depth < float(d["draft"]):
		vw *= maxf(0.0, 1.0 - dt * 4.0)
		ahead = -vw.y
	# Turning: the rudder bites with speed through the water; paddles turn her even
	# from a standstill.
	var bite := clampf(absf(ahead) / 1.5, 0.0, 1.0) * signf(ahead) if absf(ahead) > 0.02 else 0.0
	var want := -rudder * float(d["turn"]) * bite
	if float(d["paddle"]) > 0.0:
		# Paddles spin a small boat round; an engine's wash over the rudder turns a big
		# one slowly.
		var spin := float(d["turn"]) * 0.3 if d.get("engine", false) else 0.5
		want -= rudder * spin * (1.0 - absf(bite))
	st["omega"] = move_toward(float(st["omega"]), want, dt * 1.5)
	yaw += float(st["omega"]) * dt
	st["yaw"] = wrapf(yaw, -PI, PI)
	# The water's grip turns her way with her heading (no skating sideways after a turn).
	st["vel"] = to_world(vw, float(st["yaw"])) + current
	# Heel: the sail's push across her against her stability, eased.
	var heel := clampf(sail_x / (m * 9.8 * float(d.get("stiff", 0.2))), -0.45, 0.45)
	st["heel"] = lerpf(float(st["heel"]), heel, clampf(dt * 1.2, 0.0, 1.0))

## How far the yard or boom stands off square (BoatRig's swing, radians, + to port) for
## her current sheet: a square yard is braced round from across the boat, a fore-and-aft
## boom swings out from the centreline.
static func sail_turn(kind: String, st: Dictionary) -> float:
	var d: Dictionary = BOATS[kind]
	if float(d["sail"]) <= 0.0:
		return 0.0
	var r: Array = RIGS[d["rig"]]
	var delta := lerpf(r[0], r[1], float(st["sheet"]))
	var side := float(st["side"])
	return side * (PI * 0.5 - delta) if d["rig"] == "square" else side * delta

## The point of sail for the true wind `wind` (world, the way the air goes) and heading:
## in irons, close-hauled, close reach, beam reach, broad reach or running.
static func point_of_sail(wind: Vector2, yaw: float) -> String:
	if wind.length() < 0.01:
		return "Becalmed"
	var from := to_local(-wind, yaw) # where the wind comes from, boat-local
	var off := rad_to_deg(acos(clampf(-from.normalized().y, -1.0, 1.0))) # 0 dead ahead
	if off < 35.0:
		return "In irons"
	if off < 55.0:
		return "Close-hauled"
	if off < 80.0:
		return "Close reach"
	if off < 110.0:
		return "Beam reach"
	if off < 155.0:
		return "Broad reach"
	return "Running"

## How the sail is doing, for the HUD: "Luffing", "Drawing" or "Stalled".
static func sail_state(st: Dictionary) -> String:
	if float(st["luff"]) > 0.6:
		return "Luffing"
	# Sheeted in too hard on a reach; running, the sail is meant to stand square to the wind.
	return "Stalled" if float(st["alpha"]) > 0.75 and float(st.get("off", PI)) < 1.9 else "Drawing"
