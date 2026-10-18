class_name Power
## The rules of the power system: what each powered piece is, and how one network of them
## shares power over one tick (solve). Pieces are ordinary built pieces whose BuildCatalog
## definition has a "power" spec:
##   role:   gen (makes power), store (holds it), use (draws it), node (a pole or junction
##           cables meet at), switch (passes power only while closed).
##   watts:  most a generator makes / what a consumer draws, in W.
##   source: fuel (burns what is in its fuel store), wind, sun.
##   fuel:   item id -> seconds it runs at full output.
##   store / rate: a battery's size in Wh and how fast it charges or discharges, in W.
##   prio:   consumers brown out lowest first when there isn't enough (0 lights,
##           1 machines, 2 defences).
##   term:   where cables meet the piece, in its own space.
##   lamp:   {pos, range, energy, color, spot (cone degrees, 0 = all round)}.
## The state of each piece lives in its chunk object's `st`, saved with the chunk:
##   pw (Array of piece ids it is cabled to), on (bool: switched on / closed),
##   fuel (seconds left at full output), charge (Wh), pt (Game.day it was last run).
## A piece's id is "cx,cz,i": its chunk and index there, which never change (pieces taken
## down stay in the list, marked gone).
## Game numbers, not real ones: one real second of play is a game minute, so energy in Wh
## is W x seconds / 60.

const MAX_CABLE := 24.0 ## longest cable span, in metres
const WIRE_PER := 5.0 ## metres of cable one Copper Wire makes
const WIRE := "copper_wire"
const METER := "multimeter"
const FUEL_CAP := 1800.0 ## seconds of full-output running a generator holds
const IDLE := 0.2 ## a running engine burns at least this share of its full rate
const PRIO_NAMES := ["Light", "Machine", "Defence"]

static func spec_of(id: String) -> Dictionary:
	return BuildCatalog.def(id).get("power", {})

static func is_power(t: String) -> bool:
	return BuildCatalog.is_built(t) and BuildCatalog.def(BuildCatalog.id_of(t)).has("power")

static func spec(o: Dictionary) -> Dictionary:
	return spec_of(BuildCatalog.id_of(o["t"]))

static func role(o: Dictionary) -> String:
	return String(spec(o).get("role", ""))

static func id_for(k: Vector2i, i: int) -> String:
	return "%d,%d,%d" % [k.x, k.y, i]

## [chunk key, object index] of an id.
static func parse_id(id: String) -> Array:
	var p := id.split(",")
	if p.size() != 3:
		return [Vector2i.ZERO, -1]
	return [Vector2i(p[0].to_int(), p[1].to_int()), p[2].to_int()]

## A newly built powered piece: switched on, no cables, empty batteries and tanks.
static func init_state(id: String, st: Dictionary) -> void:
	var s := spec_of(id)
	if s.is_empty():
		return
	st["pw"] = []
	st["on"] = true
	if s.has("fuel"):
		st["fuel"] = 0.0
	if s.has("store"):
		st["charge"] = 0.0

static func links(o: Dictionary) -> Array:
	return o["st"].get("pw", [])

static func is_on(o: Dictionary) -> bool:
	return bool(o["st"].get("on", true))

## Cables from `a` to `b` (both object dictionaries with their ids). False when already
## joined or either end is full.
static func link(a: Dictionary, a_id: String, b: Dictionary, b_id: String) -> bool:
	if a_id == b_id:
		return false
	var la: Array = a["st"].get("pw", [])
	var lb: Array = b["st"].get("pw", [])
	if la.has(b_id):
		return false
	if la.size() >= max_links(a) or lb.size() >= max_links(b):
		return false
	la.append(b_id)
	if not lb.has(a_id):
		lb.append(a_id)
	a["st"]["pw"] = la
	b["st"]["pw"] = lb
	return true

static func unlink(o: Dictionary, other_id: String) -> void:
	(o["st"].get("pw", []) as Array).erase(other_id)

static func max_links(o: Dictionary) -> int:
	return int(spec(o).get("links", 4))

## Copper Wire a cable this long takes.
static func wire_for(length: float) -> int:
	return maxi(1, ceili(length / WIRE_PER))

## Where cables meet the piece, in world space. `origin` is its chunk's position.
static func terminal(o: Dictionary, origin: Vector3) -> Vector3:
	var t: Vector3 = spec(o).get("term", Vector3(0, 0.5, 0))
	return origin + o["p"] + Basis(Vector3.UP, float(o["r"])) * t

## Fuel this generator takes: seconds of full-output running per item, 0 if none.
static func fuel_value(o: Dictionary, type: String) -> float:
	return float((spec(o).get("fuel", {}) as Dictionary).get(type, 0.0))

# --- Weather -----------------------------------------------------------------------

## Share of a windmill's rating it makes in this wind (Atmosphere.wind_strength, 0..1):
## nothing in a calm, full from a fresh breeze, eased between.
static func wind_curve(wind: float) -> float:
	return smoothstep(0.08, 0.7, wind)

## The sun's direction on Game.day `day`, as Atmosphere draws it (used to catch up while a
## base was away, when there is no live sky to read).
static func sun_dir_at(day: float) -> Vector3:
	var ang := (fposmod(day, 1.0) - 0.25) * TAU
	return Vector3(cos(ang), sin(ang), 0.35).normalized()

## A solar panel at `yaw` (its front tipped toward its local +z) in sun `sun`: its share of
## its rating, before cloud.
static func solar_factor(yaw: float, sun: Vector3) -> float:
	var tilt := deg_to_rad(35.0)
	var n := Basis(Vector3.UP, yaw) * Vector3(0.0, cos(tilt), sin(tilt))
	return clampf(n.dot(sun), 0.0, 1.0) * smoothstep(-0.02, 0.12, sun.y)

# --- One tick of one network -------------------------------------------------------

## Shares power across one network for `dt` seconds. `entries` are its pieces, each
## {id, o (the chunk object), f (a generator's site factor: a windmill's exposure, a solar
## panel's facing; 1 otherwise)}. `env` = {wind (0..1), sun (direction), cloud (0..1)}.
## Batteries charge, tanks burn down (in each piece's st) and the result says what each
## piece did: {supply, demand, stored, capacity, short (W missing), pieces: {id: {out, draw,
## powered, flow}}}.
static func solve(entries: Array, env: Dictionary, dt: float) -> Dictionary:
	var h := dt / 60.0 ## hours of game time this tick
	var res := {"supply": 0.0, "demand": 0.0, "stored": 0.0, "capacity": 0.0, "short": 0.0, "pieces": {}}
	var free_gens: Array = []
	var fuel_gens: Array = []
	var stores: Array = []
	var users: Array = []
	var free_w := 0.0
	var fuel_w := 0.0
	var demand := 0.0
	for e in entries:
		var o: Dictionary = e["o"]
		var s := spec(o)
		var out := {"out": 0.0, "draw": 0.0, "powered": false, "flow": 0.0}
		res["pieces"][e["id"]] = out
		match String(s.get("role", "")):
			"gen":
				var rated := float(s.get("watts", 0.0))
				var src := String(s.get("source", ""))
				if src == "fuel":
					# An engine runs at whatever share of its rating the network takes.
					if is_on(o) and float(o["st"].get("fuel", 0.0)) > 0.0:
						fuel_gens.append([e, rated, out])
						fuel_w += rated
				else:
					var w := 0.0
					if is_on(o):
						if src == "wind":
							w = rated * wind_curve(float(env.get("wind", 0.0))) * float(e.get("f", 1.0))
						elif src == "sun":
							w = rated * float(e.get("f", 1.0)) * (1.0 - 0.75 * float(env.get("cloud", 0.0)))
					out["out"] = w
					free_w += w
					free_gens.append([e, w, out])
			"store":
				stores.append([e, s, out])
				res["stored"] += float(o["st"].get("charge", 0.0))
				res["capacity"] += float(s.get("store", 0.0))
			"use":
				var d := float(s.get("watts", 0.0)) if is_on(o) else 0.0
				out["draw"] = d
				if d > 0.0:
					users.append([e, s, out, d])
					demand += d
	res["supply"] = free_w + fuel_w
	res["demand"] = demand
	# What the batteries could take or give this tick, in W.
	var room_w := 0.0
	var avail_w := 0.0
	if h > 0.0:
		for st_e in stores:
			var o: Dictionary = st_e[0]["o"]
			if not is_on(o):
				continue
			var cap := float(st_e[1].get("store", 0.0))
			var rate := float(st_e[1].get("rate", cap))
			var ch := float(o["st"].get("charge", 0.0))
			room_w += minf(rate, (cap - ch) / h)
			avail_w += minf(rate, ch / h)
	var need := demand
	var from_free := minf(free_w, need)
	need -= from_free
	var from_fuel := minf(fuel_w, need)
	need -= from_fuel
	var from_store := minf(avail_w, need)
	need -= from_store
	# Whatever is left over charges the batteries: the wind and sun first, then engines.
	var spare_free := free_w - from_free
	var charge_in := minf(room_w, spare_free + (fuel_w - from_fuel))
	var fuel_to_charge := maxf(0.0, charge_in - spare_free)
	var fuel_out := from_fuel + fuel_to_charge
	if fuel_w > 0.0:
		var frac := fuel_out / fuel_w
		for g in fuel_gens:
			var o: Dictionary = g[0]["o"]
			g[2]["out"] = float(g[1]) * frac
			o["st"]["fuel"] = maxf(0.0, float(o["st"].get("fuel", 0.0)) - dt * maxf(IDLE, frac))
	# Batteries share the flow by how much room (or charge) each has.
	var net_flow := charge_in - from_store ## + charging, - discharging, in W
	if absf(net_flow) > 0.0001 and h > 0.0:
		var total := room_w if net_flow > 0.0 else avail_w
		for st_e in stores:
			var o: Dictionary = st_e[0]["o"]
			if not is_on(o) or total <= 0.0:
				continue
			var cap := float(st_e[1].get("store", 0.0))
			var rate := float(st_e[1].get("rate", cap))
			var ch := float(o["st"].get("charge", 0.0))
			var mine := minf(rate, (cap - ch) / h) if net_flow > 0.0 else minf(rate, ch / h)
			var f := net_flow * mine / total
			o["st"]["charge"] = clampf(ch + f * h, 0.0, cap)
			st_e[2]["flow"] = f
	res["stored"] = 0.0
	for st_e in stores:
		res["stored"] += float(st_e[0]["o"]["st"].get("charge", 0.0))
	# Who gets power: everyone, unless short; then defences first, lights last.
	var have := demand - maxf(need, 0.0)
	res["short"] = maxf(need, 0.0)
	if need <= 0.001:
		for u in users:
			u[2]["powered"] = true
	else:
		users.sort_custom(func(a, b): return int(a[1].get("prio", 0)) > int(b[1].get("prio", 0)))
		for u in users:
			if have + 0.001 >= float(u[3]):
				have -= float(u[3])
				u[2]["powered"] = true
	return res

# --- Networks -----------------------------------------------------------------------

## Splits pieces into networks: those joined by cables, where an open switch joins nothing.
## `pieces` is id -> object dictionary (loaded, standing pieces only). Returns an Array of
## Arrays of ids, each sorted, the networks in order of their first id.
static func networks(pieces: Dictionary) -> Array:
	var parent := {}
	for id in pieces:
		parent[id] = id
	var find := func(x: String) -> String:
		var r: String = x
		while parent[r] != r:
			parent[r] = parent[parent[r]]
			r = parent[r]
		return r
	for id in pieces:
		var o: Dictionary = pieces[id]
		if _blocks(o):
			continue
		for other in links(o):
			if not pieces.has(other) or _blocks(pieces[other]):
				continue
			var ra: String = find.call(id)
			var rb: String = find.call(String(other))
			if ra != rb:
				parent[ra] = rb
	var groups := {}
	for id in pieces:
		var r: String = find.call(id)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(id)
	var out: Array = []
	for r in groups:
		var g: Array = groups[r]
		g.sort()
		out.append(g)
	out.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	return out

## An open switch carries nothing through itself.
static func _blocks(o: Dictionary) -> bool:
	return role(o) == "switch" and not is_on(o)

# --- Words --------------------------------------------------------------------------

static func watts(w: float) -> String:
	if absf(w) >= 1000.0:
		return "%.1f kW" % (w / 1000.0)
	return "%d W" % roundi(w)

static func energy(wh: float) -> String:
	if absf(wh) >= 1000.0:
		return "%.1f kWh" % (wh / 1000.0)
	return "%d Wh" % roundi(wh)

## Fuel left as game time ("2 h 10 min" of full-output running).
static func run_time(seconds: float) -> String:
	var mins := int(seconds) # one real second is one game minute
	if mins >= 60:
		return "%d h %02d min" % [mins / 60, mins % 60]
	return "%d min" % mins
