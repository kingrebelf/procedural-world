class_name DayClock
## How fast the in-game clock runs. A game day is still 24 hours (so crops, schedules,
## taxes and moon phases keep counting days), but daylight hours run slower than night
## ones (Ben 10-19: four times the daytime, the same night). With the default 24-minute
## `day_seconds` that is 12 real minutes from sunset to sunrise and 48 from sunrise to
## sunset: an hour a day.
##
## `day_seconds` is now the length a day would have at night pace. The slowdown eases in
## over the first hour after sunrise and out over the last before sunset, so night keeps
## its old length exactly and dawn and dusk never lurch. Everything here is pure maths on
## the day number, so a server and its clients agree on the clock without sending more.

const DAY_STRETCH := 4.0 ## daylight (sunrise to sunset) lasts this many times its old length
const RAMP := 0.04 ## half the span (in days) the pace takes to change: ~1 h after sunrise
const SUNRISE := 0.25
const SUNSET := 0.75
## How much slower the clock runs at full pace, so the eased daylight averages DAY_STRETCH.
const PEAK := 1.0 + (DAY_STRETCH - 1.0) * (SUNSET - SUNRISE) / (SUNSET - SUNRISE - 2.0 * RAMP)
const _UP := SUNRISE + RAMP
const _DOWN := SUNSET - RAMP
## Real length of a whole day, in `day_seconds`.
const CYCLE := 1.0 + (DAY_STRETCH - 1.0) * (SUNSET - SUNRISE)

## 0 at night, 1 through the day, eased between.
static func slow(day: float) -> float:
	var t := fposmod(day, 1.0)
	return _up(t, _UP) - _up(t, _DOWN)

## Game days per real second at `day`.
static func rate(day: float, day_seconds: float) -> float:
	return 1.0 / (maxf(day_seconds, 1.0) * (1.0 + (PEAK - 1.0) * slow(day)))

## The clock after `delta` real seconds.
static func advance(day: float, delta: float, day_seconds: float) -> float:
	# Midpoint step: exact enough that a client and the server (which resyncs it every
	# few seconds) never visibly part.
	return day + delta * rate(day + delta * rate(day, day_seconds) * 0.5, day_seconds)

## Real seconds of world time since day 0: steady, so things that move in real time
## (boats, lightning, timers, machines) keep their pace by day and night alike.
static func world_seconds(day: float, day_seconds: float) -> float:
	var n := floorf(day)
	var t := day - n
	return maxf(day_seconds, 1.0) * (n * CYCLE + t + (PEAK - 1.0) * (_area(t, _UP) - _area(t, _DOWN)))

## The day number `world_seconds` real seconds since day 0 (the inverse of world_seconds).
static func day_at(secs: float, day_seconds: float) -> float:
	var per := maxf(day_seconds, 1.0) * CYCLE
	var n := floorf(secs / per)
	var lo := n
	var hi := n + 1.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if world_seconds(mid, day_seconds) < secs:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## Smoothstep from 0 to 1 centred on `c`.
static func _up(t: float, c: float) -> float:
	var u := clampf((t - c + RAMP) / (2.0 * RAMP), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

## The integral of _up from 0 to t (t in 0..1).
static func _area(t: float, c: float) -> float:
	var u := clampf((t - c + RAMP) / (2.0 * RAMP), 0.0, 1.0)
	return 2.0 * RAMP * (u * u * u - u * u * u * u * 0.5) + maxf(0.0, t - c - RAMP)
