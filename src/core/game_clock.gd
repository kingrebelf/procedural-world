class_name GameClock
## The clock things that move on screen keep time by (clouds drifting, oars pulling, the
## water's swell under a boat, glances and idles, splash rings). Normally the real clock.
## A tool rendering at a fixed frame rate (godot --fixed-fps N, slower than real time:
## tools/trailer.gd) sets fixed_step, and the clock then counts frames as the shaders'
## TIME does, so every motion keeps pace with the frames and the waves a boat rides are
## the waves that are drawn.

## Seconds per frame of a fixed-frame-rate run (0: the real clock).
static var fixed_step := 0.0

static func sec() -> float:
	if fixed_step > 0.0:
		return Engine.get_process_frames() * fixed_step
	return Time.get_ticks_msec() / 1000.0

static func msec() -> int:
	return int(sec() * 1000.0)
