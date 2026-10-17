class_name Signals
## The logic layer of the power system: signal wire, the pieces that make a signal (levers,
## buttons, pressure plates, sensors, timers, clocks), the ones that work on it (gates,
## latches, counters, delays) and what a signal does where it ends:
##   - into a generator or consumer, it runs only while the signal is on;
##   - into a relay, it closes the relay (which joins power like a switch);
##   - into a door motor, it opens the door it stands by (on) and shuts it (off).
## A signal wire runs one way, from a piece's output to another's input; a piece has any
## number of outputs and up to `in` inputs. A signal is on or off. Each tick a logic piece
## reads its inputs as they were on the last tick, so clocks, latches and loops work and
## nothing locks up.
## A piece's logic is its power spec's "logic": {kind, out (makes a signal), in (inputs it
## takes, 0 = none)}. State in its chunk object's `st`:
##   si (Array of source ids wired in, in the order wired), so (target ids), sg_wire (id ->
##   Signal Wire spent), m (mode index), a (setting index), sg (its output), lt (a latch's
##   state), cn (a counter's count), mw (a door motor's last want).

const WIRE := "signal_wire"
const WIRE_PER := 8.0 ## metres of signal wire one Signal Wire makes
const MAX_SPAN := 24.0
const PRESENCE := 0.8 ## how near (across) something has to stand on a pressure plate
const MOTION_CONE := 0.5 ## cos of half the motion sensor's cone (120 degrees wide)
const MOTOR_REACH := 3.0 ## how far from its door a door motor may stand

## Settings each kind cycles through with Interact (a) and crouched Interact (m).
const GATES := ["AND", "OR", "XOR", "NOT", "NAND", "NOR", "XNOR"]
const PULSE := [1.0, 3.0, 10.0]
const RANGES := [4.0, 8.0, 16.0, 32.0]
const WHO := ["anyone", "people", "animals"]
const TIMERS := [[1.0, 5.0], [1.0, 10.0], [5.0, 30.0], [10.0, 60.0], [30.0, 120.0], [60.0, 600.0]]
const CLOCKS := [[18.0, 6.0, "dusk to dawn"], [6.0, 18.0, "dawn to dusk"], [8.0, 18.0, "working hours"], [22.0, 6.0, "night watch"], [12.0, 13.0, "noon"]]
const LEVELS := [10.0, 25.0, 50.0, 75.0, 90.0]
const COUNTS := [2, 3, 5, 10, 20]
const DELAYS := [0.5, 1.0, 2.0, 5.0, 10.0, 30.0]
const LATCH := ["toggle", "set / reset"]

static func logic(o: Dictionary) -> Dictionary:
	return Power.spec(o).get("logic", {})

static func kind(o: Dictionary) -> String:
	return String(logic(o).get("kind", ""))

## Makes a signal (has an output to wire from).
static func has_out(o: Dictionary) -> bool:
	return bool(logic(o).get("out", false))

## How many signal wires it takes in: a logic piece's own number; any generator or
## consumer takes one (it then runs only while it is on).
static func max_in(o: Dictionary) -> int:
	var l := logic(o)
	if l.has("in"):
		return int(l["in"])
	return 1 if Power.role(o) in ["gen", "use"] else 0

static func inputs(o: Dictionary) -> Array:
	return o["st"].get("si", [])

static func outputs(o: Dictionary) -> Array:
	return o["st"].get("so", [])

static func setting(o: Dictionary) -> int:
	return int(o["st"].get("a", 0))

static func mode(o: Dictionary) -> int:
	return int(o["st"].get("m", 0))

## Wires a's output into b's input (ids given). False when already wired, or full.
static func link(a: Dictionary, a_id: String, b: Dictionary, b_id: String) -> bool:
	if a_id == b_id or not has_out(a):
		return false
	var si: Array = b["st"].get("si", [])
	if si.has(a_id) or si.size() >= max_in(b):
		return false
	si.append(a_id)
	b["st"]["si"] = si
	var so: Array = a["st"].get("so", [])
	if not so.has(b_id):
		so.append(b_id)
	a["st"]["so"] = so
	return true

static func unlink_in(o: Dictionary, src: String) -> void:
	(o["st"].get("si", []) as Array).erase(src)

static func unlink_out(o: Dictionary, dst: String) -> void:
	(o["st"].get("so", []) as Array).erase(dst)

static func wire_for(length: float) -> int:
	return maxi(1, ceili(length / WIRE_PER))

# --- One tick ----------------------------------------------------------------------

## A logic piece's output this tick. `ins` = its inputs' values (last tick), in wired
## order; `mem` = this piece's own scratch (rising edges, pulses, a delay's queue; not
## saved). `ctx`: {now (real s), day (Game.day), clock (real s of game time), hour (0..24), night (bool), near
## (Callable(range, who, cone) -> bool, for plates and sensors), charge (0..100 or -1)}.
## May change the piece's st (latch, counter) and returns [output, st changed].
static func step(o: Dictionary, ins: Array, mem: Dictionary, ctx: Dictionary) -> Array:
	var any := ins.has(true)
	var rose := any and not bool(mem.get("any", false))
	mem["any"] = any
	var st: Dictionary = o["st"]
	var changed := false
	var out := false
	match kind(o):
		"lever":
			out = Power.is_on(o)
		"button":
			out = float(ctx.get("day", 0.0)) < float(st.get("pu", -1.0))
		"plate":
			out = (ctx["near"] as Callable).call(PRESENCE, WHO[mode(o) % WHO.size()], false)
		"motion":
			out = (ctx["near"] as Callable).call(RANGES[setting(o) % RANGES.size()], WHO[mode(o) % WHO.size()], true)
		"daylight":
			out = bool(ctx.get("night", false)) != (mode(o) == 1)
		"timer":
			var t: Array = TIMERS[setting(o) % TIMERS.size()]
			out = fposmod(float(ctx.get("clock", 0.0)), float(t[1])) < float(t[0])
		"clock":
			var c: Array = CLOCKS[setting(o) % CLOCKS.size()]
			var h := float(ctx.get("hour", 12.0))
			out = (h >= c[0] and h < c[1]) if c[0] < c[1] else (h >= c[0] or h < c[1])
		"charge":
			var pct := float(ctx.get("charge", -1.0))
			var lvl := float(LEVELS[setting(o) % LEVELS.size()])
			out = pct >= 0.0 and ((pct >= lvl) if mode(o) == 0 else (pct < lvl))
		"gate":
			out = gate(GATES[mode(o) % GATES.size()], ins)
		"latch":
			var was := bool(st.get("lt", false))
			var now_v := was
			if mode(o) == 0:
				if rose:
					now_v = not was
			else:
				# The first wire in sets it, any other resets it; reset wins a tie.
				var set_on := ins.size() > 0 and bool(ins[0]) and not bool(mem.get("s0", false))
				var reset := false
				for i in range(1, ins.size()):
					if bool(ins[i]):
						reset = true
				mem["s0"] = ins.size() > 0 and bool(ins[0])
				if reset:
					now_v = false
				elif set_on:
					now_v = true
			if now_v != was:
				st["lt"] = now_v
				changed = true
			out = now_v
		"counter":
			if rose:
				var n := int(st.get("cn", 0)) + 1
				if n >= int(COUNTS[setting(o) % COUNTS.size()]):
					n = 0
					mem["until"] = float(ctx.get("now", 0.0)) + 1.0
				st["cn"] = n
				changed = true
			out = float(ctx.get("now", 0.0)) < float(mem.get("until", -1.0))
		"delay":
			var lag := float(DELAYS[setting(o) % DELAYS.size()])
			var q: Array = mem.get("q", [])
			var now := float(ctx.get("now", 0.0))
			if q.is_empty() or bool(q[-1][1]) != any:
				q.append([now, any])
			var v := bool(mem.get("v", false))
			while not q.is_empty() and float(q[0][0]) + lag <= now:
				v = bool(q[0][1])
				q.pop_front()
			mem["q"] = q
			mem["v"] = v
			out = v
		_:
			out = any
	return [out, changed]

static func gate(g: String, ins: Array) -> bool:
	var n := 0
	for v in ins:
		if bool(v):
			n += 1
	match g:
		"AND": return ins.size() > 0 and n == ins.size()
		"OR": return n > 0
		"XOR": return n % 2 == 1
		"NOT": return n == 0
		"NAND": return not (ins.size() > 0 and n == ins.size())
		"NOR": return n == 0
		"XNOR": return n % 2 == 0
	return false

## A push button pressed on Game.day `day`: on for its pulse length (real seconds, with
## `day_seconds` to a day). Kept in its st, so the press reaches other players.
static func press(o: Dictionary, day: float, day_seconds: float) -> void:
	o["st"]["pu"] = day + float(PULSE[setting(o) % PULSE.size()]) / maxf(day_seconds, 1.0)

# --- Settings ----------------------------------------------------------------------

## What Interact does on a logic piece ("" when it only switches, like a lever).
static func verb(o: Dictionary, sneaking: bool) -> String:
	match kind(o):
		"lever": return "Pull the lever " + ("down" if Power.is_on(o) else "up")
		"button": return "Set the pulse length" if sneaking else "Press the button"
		"plate", "motion": return "Change who it senses" if sneaking or kind(o) == "plate" else "Change its range"
		"daylight": return "Make it switch on by %s" % ("night" if mode(o) == 1 else "day")
		"timer", "clock", "counter", "delay": return "Change the setting"
		"charge": return "Switch it to on %s the level" % ("above" if mode(o) == 1 else "below") if sneaking else "Change the level"
		"gate": return "Change the gate"
		"latch": return "Change the mode"
	return ""

## Interact on a logic piece: turns its setting on one step (crouched: its other setting).
## Returns what it is set to now, in words, or "" when it isn't a setting change.
static func cycle(o: Dictionary, sneaking: bool) -> String:
	var st: Dictionary = o["st"]
	match kind(o):
		"button":
			if not sneaking:
				return ""
			st["a"] = (setting(o) + 1) % PULSE.size()
		"plate":
			st["m"] = (mode(o) + 1) % WHO.size()
		"motion":
			if sneaking:
				st["m"] = (mode(o) + 1) % WHO.size()
			else:
				st["a"] = (setting(o) + 1) % RANGES.size()
		"daylight": st["m"] = 1 - (mode(o) % 2)
		"timer": st["a"] = (setting(o) + 1) % TIMERS.size()
		"clock": st["a"] = (setting(o) + 1) % CLOCKS.size()
		"counter": st["a"] = (setting(o) + 1) % COUNTS.size()
		"delay": st["a"] = (setting(o) + 1) % DELAYS.size()
		"charge":
			if sneaking:
				st["m"] = 1 - (mode(o) % 2)
			else:
				st["a"] = (setting(o) + 1) % LEVELS.size()
		"gate": st["m"] = (mode(o) + 1) % GATES.size()
		"latch":
			st["m"] = (mode(o) + 1) % LATCH.size()
			st["lt"] = false
		_:
			return ""
	return describe_setting(o)

## Its setting in words ("on 5 s every 30 s").
static func describe_setting(o: Dictionary) -> String:
	match kind(o):
		"lever": return "On" if Power.is_on(o) else "Off"
		"button": return "Pulse %s" % _secs(PULSE[setting(o) % PULSE.size()])
		"plate": return "Senses %s standing on it" % WHO[mode(o) % WHO.size()]
		"motion": return "Senses %s moving within %d m in front" % [WHO[mode(o) % WHO.size()], int(RANGES[setting(o) % RANGES.size()])]
		"daylight": return "On by day" if mode(o) == 1 else "On at night"
		"timer":
			var t: Array = TIMERS[setting(o) % TIMERS.size()]
			return "On %s every %s" % [_secs(t[0]), _secs(t[1])]
		"clock":
			var c: Array = CLOCKS[setting(o) % CLOCKS.size()]
			return "On %02d:00 to %02d:00 (%s)" % [int(c[0]), int(c[1]), c[2]]
		"charge":
			return "On while the batteries are %s %d%%" % ["above" if mode(o) == 0 else "below", int(LEVELS[setting(o) % LEVELS.size()])]
		"gate": return "%s gate" % GATES[mode(o) % GATES.size()]
		"latch": return "Latch: %s%s" % [LATCH[mode(o) % LATCH.size()], " (first wire in sets, the others reset)" if mode(o) == 1 else " (each pulse flips it)"]
		"counter": return "On for a moment every %d pulses (at %d now)" % [int(COUNTS[setting(o) % COUNTS.size()]), int(o["st"].get("cn", 0))]
		"delay": return "Passes a change on after %s" % _secs(DELAYS[setting(o) % DELAYS.size()])
		"relay": return "Closed while its signal is on"
		"motor": return "Opens the door by it while its signal is on"
	return ""

## Game seconds in words. One real second is a game minute, but a timer counts what you
## see, so these are real seconds.
static func _secs(s: float) -> String:
	if s >= 60.0 and fmod(s, 60.0) == 0.0:
		return "%d min" % int(s / 60.0)
	if s < 1.0:
		return "%.1f s" % s
	return "%d s" % int(s)
