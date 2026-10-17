class_name Swim
extends RefCounted
## How the player moves in water. Swimming has weight: strokes push you in pulses, you
## glide between them, buoyancy bobs you on the waves with your chest at the waterline,
## diving in carries you under before you float back up, and rivers carry you along.
## At a bank or a jetty, Space with forward pulls you out. Wading slows you as the water
## gets deeper. It also raises the splashes and ripples you make.

const FLOAT_CHEST := 1.35 ## floating: the feet hang this far below the surface
const LEAP := 6.4 ## pulling yourself out onto a bank: enough to clear a ledge above the waterline

var leap_t := 0.0 ## seconds left of a pull-out, when the water stops holding you
var _stroke := 0.0
var _ring_t := 0.0
var _was_wet := false
var _last_vy := 0.0

## Walking through water: speed multiplier for water this deep at your feet (metres).
static func wade(depth: float) -> float:
	return 1.0 - 0.5 * smoothstep(0.15, 1.1, depth)

## How much a current shoves you while wading: none in the shallows, half once waist-deep.
static func wade_push(depth: float) -> float:
	return 0.5 * smoothstep(0.4, 1.1, depth)

## One physics frame of swimming. surface: the water level above the player.
func step(pl: Player, delta: float, input: Vector2, surface: float) -> void:
	var up_in := 0.0
	if not pl.ui_open:
		up_in = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var fast := not pl.ui_open and not pl.winded and Input.is_action_pressed("sprint") and input.length() > 0.1
	if fast:
		pl._tire(10.0 * delta)
	var look3 := pl.camera.global_transform.basis * Vector3(input.x, 0, input.y)
	look3 = look3.limit_length(1.0)
	var top := Player.SWIM * (1.5 if fast else 1.0) * Game.stats.speed_mult() * pl.load_mult()
	var float_y := surface - FLOAT_CHEST
	var depth := float_y - pl.global_position.y # below floating height
	var cur := Water.current(pl.global_position.x, pl.global_position.z)
	var flow := Vector3(cur.x, 0.0, cur.y)

	# Pull yourself out where the water meets a bank, rock or jetty.
	if leap_t <= 0.0 and depth < 0.6 and pl.is_on_wall() and input.y < -0.3 and not pl.ui_open \
			and Input.is_action_just_pressed("jump") and pl._tire(8.0):
		var fwd := -pl.global_transform.basis.z
		pl.velocity = Vector3(fwd.x * 2.2, LEAP, fwd.z * 2.2)
		leap_t = 0.6
		Splashes.splash(Vector3(pl.global_position.x, surface, pl.global_position.z), 0.6)
	if leap_t > 0.0:
		leap_t -= delta
		pl.velocity.y -= 9.8 * delta
		pl.move_and_slide()
		return

	# Strokes: thrust comes in pulses (about one stroke a second), and you glide between.
	_stroke += delta * TAU * (1.35 if fast else 0.95) * look3.length()
	var want := look3 * top * (1.0 + 0.35 * sin(_stroke))
	# Swimming moves you through the water, and the water itself may be flowing.
	var rel := pl.velocity - flow
	var steer := clampf(2.2 * delta, 0.0, 1.0)
	rel.x = lerpf(rel.x, want.x, steer)
	rel.z = lerpf(rel.z, want.z, steer)
	if absf(up_in) > 0.1 or absf(look3.y) > 0.25:
		# Steering up or down: Space rises, Ctrl sinks, or swim where you look.
		var wy := want.y + up_in * 2.6
		if depth < 0.0 and wy > 0.0:
			wy = minf(wy, depth * 3.0) # treading water; you can't swim up into the air
		rel.y = lerpf(rel.y, wy, steer)
	else:
		# Buoyancy: a springy float at the surface, so you ride the swell and bob a little,
		# and below it a slow drift back up.
		var bob := clampf(depth, -1.5, 1.5) * 14.0 - rel.y * 3.2
		var drift := (0.45 - rel.y) * 1.5
		rel.y += lerpf(bob, drift, smoothstep(0.6, 1.4, depth)) * delta
	# Water is thick: big speeds (diving in, falling from a cliff) bleed away fast.
	var sp := rel.length()
	if sp > top:
		rel *= 1.0 / (1.0 + (sp - top) * 0.35 * delta)
	pl.velocity = rel + flow
	pl.move_and_slide()

## Every physics frame, swimming or not: splashes where you hit the water, a wake of
## rings while you swim at the surface, ripples round your legs as you wade.
func effects(pl: Player, delta: float, surface: float, swimming: bool, underwater: bool) -> void:
	var p := pl.global_position
	var feet := surface - p.y
	var wet := feet > 0.05
	if wet and not _was_wet and _last_vy < -2.5:
		Splashes.splash(Vector3(p.x, surface, p.z), clampf(-_last_vy / 9.0, 0.3, 1.6))
	_was_wet = wet
	_last_vy = pl.velocity.y
	if not wet:
		return
	var hs := Vector2(pl.velocity.x, pl.velocity.z).length()
	_ring_t -= delta
	if _ring_t > 0.0:
		return
	if swimming and not underwater and feet < FLOAT_CHEST + 0.8:
		_ring_t = 0.45 if hs > 0.5 else 1.4
		Splashes.ring(Vector3(p.x, surface, p.z), 0.8 + hs * 0.3)
		if hs > 1.5:
			Splashes.splash(Vector3(p.x, surface, p.z) - pl.velocity.normalized() * 0.4, 0.15)
	elif not swimming and hs > 0.6 and feet < 1.2:
		_ring_t = 0.35
		Splashes.ring(Vector3(p.x, surface, p.z), 0.5 + feet * 0.6)
		if hs > 3.0:
			Splashes.splash(Vector3(p.x, surface, p.z), 0.12 + feet * 0.15)
