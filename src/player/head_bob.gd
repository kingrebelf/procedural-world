class_name HeadBob
extends RefCounted
## How your eye moves on foot (Settings "head_bob", "head_bob_strength"): it dips as each
## foot lands, in time with the footsteps (Footsteps.gait), sways over the standing foot
## and rolls a touch with it, nods a little at each step, dips and springs back up when
## you land from a jump or a fall, and leans into a strafe. Aiming down a gun's sights
## steadies most of the walking motion. Strength 1 is subtle; 0 turns it all off.

var offset := Vector3.ZERO ## head position offset (player space, metres)
var tilt := Vector3.ZERO ## head rotation added to the look: x nod, z roll (radians)

const VERT := 0.022 ## metres up and down at walking pace
const SIDE := 0.011 ## metres side to side
const ROLL := 0.0055 ## radians of roll with the sway (about 0.3 degrees)
const NOD := 0.0045 ## radians the head nods at each footfall
const LEAN := 0.016 ## radians of lean into a strafe at walking pace (about 0.9 degrees)
const LAND_W := 11.0 ## the landing spring (radians per second)
const LAND_DAMP := 0.75

var _amt := 0.0 ## how much of the walking motion shows: 0 standing, 1 walking, more running
var _land := 0.0 ## landing dip (metres, down is negative)
var _land_v := 0.0
var _lean := 0.0

## Each physics frame on foot. k: strength (0 off); gait: Footsteps.gait(); strafe: -1
## left to 1 right; pace: ground speed over walking speed; landed_vy: the downward speed of a landing this frame (0 if none);
## steady: 0-1, how far a gun is raised to the eye.
func step(delta: float, k: float, gait: float, pace: float, on_floor: bool, crouched: bool, strafe: float,
		landed_vy: float, steady: float) -> void:
	var target := 0.0
	if on_floor and pace > 0.07:
		target = clampf(pace, 0.0, 1.8) * (0.6 if crouched else 1.0)
	_amt = move_toward(_amt, target, delta * 3.0)
	var walk := _amt * k * lerpf(1.0, 0.25, clampf(steady, 0.0, 1.0))
	var ph := gait * TAU
	# Lowest as a foot comes down (twice a cycle), highest over the standing leg.
	var v := -(0.5 + 0.5 * cos(2.0 * ph))
	var side := sin(ph)

	if landed_vy > 1.5:
		_land_v -= minf(landed_vy, 14.0) * 0.11 * k
	_land_v += (-LAND_W * LAND_W * _land - 2.0 * LAND_DAMP * LAND_W * _land_v) * delta
	_land = clampf(_land + _land_v * delta, -0.15, 0.05)

	var lean_to := -clampf(strafe, -1.0, 1.0) * LEAN * clampf(pace, 0.0, 1.0) * k if on_floor else 0.0
	_lean = lerpf(_lean, lean_to, clampf(delta * 6.0, 0.0, 1.0))

	var want := Vector3(side * SIDE * walk, v * VERT * walk + _land, 0.0)
	# A little smoothing hides the jump in phase when a landing restarts the gait.
	offset = offset.lerp(want, clampf(delta * 20.0, 0.0, 1.0))
	tilt = Vector3(v * NOD * walk + _land * 0.3, 0.0, side * ROLL * walk + _lean)

## Back to rest at once (teleport, riding, third person).
func reset() -> void:
	offset = Vector3.ZERO
	tilt = Vector3.ZERO
	_amt = 0.0
	_land = 0.0
	_land_v = 0.0
	_lean = 0.0
