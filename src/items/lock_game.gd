class_name LockGame
extends RefCounted
## The lockpicking minigame, as pure state so it can be tested: set the pick at an angle,
## then turn the lock. Near the hidden sweet spot the lock turns all the way and opens;
## the further off, the less it turns before it jams. Forcing a jammed lock strains the
## pick until it snaps. Lockpicking widens the sweet spot and makes picks last longer;
## harder locks narrow it.

const TIERS := ["", "Novice", "Adept", "Master"]
const SWEET_DEG := [0.0, 20.0, 11.0, 5.0] ## half-width of the sweet spot by lock tier, at skill 0
const FALLOFF := deg_to_rad(40.0) ## how far past the sweet spot the lock still turns a little
const TURN_SPEED := 1.4 ## of a full turn per second
const RETURN_SPEED := 2.6

var tier := 1
var skill := 0
var sweet := 0.0 ## the sweet spot's angle, -PI/2 (left) .. PI/2 (right)
var half := 0.0
var pick := 0.0
var turn := 0.0 ## 0..1, how far the lock has turned
var pick_hp := 1.0
var strain := 0.0 ## 0..1, how hard the pick is being forced this frame (for shaking)

static func sweet_half(t: int, sk: int) -> float:
	return deg_to_rad(SWEET_DEG[clampi(t, 1, 3)] * (1.0 + 0.03 * float(sk)))

func _init(t: int = 1, sk: int = 0, seed_: int = 0) -> void:
	tier = clampi(t, 1, 3)
	skill = sk
	half = sweet_half(tier, skill)
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	sweet = r.randf_range(-PI * 0.5 + half, PI * 0.5 - half)

## How far the lock can turn with the pick where it is.
func max_turn() -> float:
	var d := absf(pick - sweet)
	if d <= half:
		return 1.0
	return clampf(1.0 - (d - half) / FALLOFF, 0.0, 1.0) * 0.92

## Moves the pick (only while the lock is at rest, as with a real pick).
func set_pick(a: float) -> void:
	if turn > 0.03:
		return
	pick = clampf(a, -PI * 0.5, PI * 0.5)

## Advances the game. Returns "open" when the lock gives, "broke" when the pick snaps
## (the next pick starts fresh), or "".
func step(dt: float, turning: bool) -> String:
	strain = 0.0
	if not turning:
		turn = maxf(0.0, turn - dt * RETURN_SPEED)
		return ""
	var lim := max_turn()
	if turn < lim:
		turn = minf(lim, turn + dt * TURN_SPEED)
	if turn >= 1.0:
		return "open"
	if turn >= lim - 0.001:
		# Jammed and still forcing it.
		strain = 1.0
		pick_hp -= dt * (0.8 + 0.3 * float(tier)) * (1.0 - 0.01 * float(skill))
		if pick_hp <= 0.0:
			pick_hp = 1.0
			turn = 0.0
			return "broke"
	return ""
