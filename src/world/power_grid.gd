class_name PowerGrid
extends Node3D
## Runs the power networks of the loaded world (see Power for the rules): finds the
## powered pieces in loaded chunks, joins them into networks by their cables, shares power
## four times a second, poses their PowerNodes (lamps lit, sails turning) and draws the
## cables. It also does what the player does to them: fuel, switches, cables.
## Networks are only worked out again when something changes (a piece built or taken
## down, a cable strung, a switch thrown, a chunk loaded or let go), never every frame.
## Charge and fuel are saved with their chunk every SAVE_EVERY seconds (and with any other
## change to it); a network that was away (its chunks unloaded) catches up on the time it
## missed when it loads again.

const TICK := 0.25
const SAVE_EVERY := 60.0
const SAVE_EVERY_ONLINE := 180.0 ## a chunk save is pushed to every player near it
const CATCH_UP_MAX := 2.0 ## days a network away catches up at most
const CATCH_UP_STEP := 60.0 ## seconds per step when catching up
const SAG := 0.035 ## how far a cable sags per metre of span

static var current: PowerGrid

var streamer: ChunkStreamer
var atmosphere: Atmosphere
## The wind the windmills turn in, from Atmosphere (the one wind source).
var wind := 0.3
var wind_dir := Vector2(0.8, 0.6)

var _dirty := true
var _index := {} ## chunk key -> [ChunkNode, [object indices of its powered pieces]]
var _nets: Array = [] ## Arrays of piece ids
var _net_of := {} ## piece id -> index into _nets
var _results: Array = [] ## per network, the last Power.solve result
var _site := {} ## piece id -> site factor (a windmill's exposure)
var _cables := {} ## "a|b" -> MeshInstance3D
var _t := 0.0
var _save_t := 0.0
var _cable_mat: StandardMaterial3D
var _signal_mat: StandardMaterial3D
var _sig := {} ## piece id -> its output last tick (Signals)
var _mem := {} ## piece id -> its logic scratch (Signals.step)
var _en := {} ## piece id -> whether the signal wired into it is on (only pieces with one)
var _ver := 0 ## counts network rebuilds (cached neighbours are worked out again after one)

func _ready() -> void:
	current = self
	top_level = true
	_cable_mat = Materials.get_mat("rubber") as StandardMaterial3D
	_signal_mat = StandardMaterial3D.new()
	_signal_mat.albedo_color = Color(0.62, 0.16, 0.1)
	_signal_mat.roughness = 0.55
	if streamer != null:
		streamer.chunk_ready.connect(func(n: ChunkNode): _scan(n))

func _exit_tree() -> void:
	for k in _touched:
		if is_instance_valid(_touched[k]):
			Game.mark_chunk_dirty((_touched[k] as ChunkNode).data)
	_touched.clear()
	if current == self:
		current = null

## Something about the powered pieces changed (in `chunk`, when one was built or taken
## down there): work the networks out again next tick.
static func changed(chunk: ChunkNode = null) -> void:
	if current == null:
		return
	current._dirty = true
	if chunk != null:
		current._scan(chunk)

func _scan(n: ChunkNode) -> void:
	var list: Array = []
	for o in n.data["objects"]:
		if Power.is_power(o["t"]) and not o["st"].get("gone", false):
			list.append(int(o["i"]))
	if list.is_empty():
		_index.erase(n.key)
	else:
		_index[n.key] = [n, list]
	_dirty = true

## The object for a piece id, or {} when its chunk isn't loaded or it is gone.
func piece(id: String) -> Dictionary:
	var p := Power.parse_id(id)
	var e = _index.get(p[0])
	if e == null or not is_instance_valid(e[0]):
		return {}
	var objs: Array = (e[0] as ChunkNode).data["objects"]
	var i: int = p[1]
	if i < 0 or i >= objs.size() or objs[i]["st"].get("gone", false) or not Power.is_power(objs[i]["t"]):
		return {}
	return objs[i]

func chunk_of_id(id: String) -> ChunkNode:
	var e = _index.get(Power.parse_id(id)[0])
	return e[0] if e != null and is_instance_valid(e[0]) else null

static func id_of(chunk: ChunkNode, o: Dictionary) -> String:
	return Power.id_for(chunk.key, int(o["i"]))

func _process(delta: float) -> void:
	if atmosphere != null:
		wind = atmosphere.wind_strength
		wind_dir = atmosphere.wind_dir
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	_check_loaded()
	if _dirty:
		_rebuild()
	_tick(dt)
	_save_t += dt
	if _save_t >= (SAVE_EVERY_ONLINE if _online() else SAVE_EVERY):
		_save_t = 0.0
		_save_running()

## Chunks let go of (or swapped for a newer copy from the server) drop out of the index.
func _check_loaded() -> void:
	for k in _index.keys():
		var e: Array = _index[k]
		if not is_instance_valid(e[0]) or not (e[0] as ChunkNode).is_inside_tree() or streamer == null or streamer.get_chunk(k) != e[0]:
			_index.erase(k)
			_dirty = true
			var now = streamer.get_chunk(k) if streamer != null else null
			if now != null:
				_scan(now)

# --- Networks -------------------------------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	var pieces := {}
	for k in _index:
		var e: Array = _index[k]
		var c: ChunkNode = e[0]
		var keep: Array = []
		for i in e[1]:
			var o: Dictionary = c.data["objects"][i]
			if o["st"].get("gone", false):
				continue
			keep.append(i)
			pieces[Power.id_for(k, i)] = o
		e[1] = keep
	# Cables to a piece that was taken down (in a loaded chunk) are let go of.
	for id in pieces:
		var o: Dictionary = pieces[id]
		for other in Power.links(o).duplicate():
			var ok := Power.parse_id(String(other))[0] as Vector2i
			if _index.has(ok) and not pieces.has(other):
				Power.unlink(o, String(other))
		for src in Signals.inputs(o).duplicate():
			if _index.has(Power.parse_id(String(src))[0]) and not pieces.has(src):
				Signals.unlink_in(o, String(src))
		for dst in Signals.outputs(o).duplicate():
			if _index.has(Power.parse_id(String(dst))[0]) and not pieces.has(dst):
				Signals.unlink_out(o, String(dst))
	_nets = Power.networks(pieces)
	_net_of.clear()
	for n in _nets.size():
		for id in _nets[n]:
			_net_of[id] = n
	_results.resize(_nets.size())
	_site.clear()
	for id in pieces:
		if Power.spec(pieces[id]).get("source", "") == "wind":
			_site[id] = _exposure(id, pieces[id])
		elif Power.spec(pieces[id]).get("source", "") == "water":
			_site[id] = _in_water(id, pieces[id])
	_ver += 1
	for id in pieces:
		if Automation.is_auto(pieces[id]) and not _mem.get(id, {}).has("seen"):
			_machine_catch_up(id, pieces[id])
	for n in _nets.size():
		_catch_up(_nets[n])
	_draw_cables(pieces)

## How exposed a windmill stands: up to half again on a hilltop, less in a hollow (its
## ground against the ground 40 m round it, where that is loaded).
func _exposure(id: String, o: Dictionary) -> float:
	var c := chunk_of_id(id)
	if c == null or streamer == null:
		return 1.0
	var at: Vector3 = c.position + o["p"]
	var sum := 0.0
	var n := 0
	for a in 8:
		var p := at + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * 40.0
		var ck := ChunkStreamer.chunk_of(p)
		var cn := streamer.get_chunk(ck)
		if cn == null:
			continue
		sum += ChunkGenerator.height_at(cn.data, p.x - cn.position.x, p.z - cn.position.z)
		n += 1
	if n == 0:
		return 1.0
	return clampf(1.0 + (at.y - sum / n) / 30.0, 0.6, 1.5)

## A water wheel's share of its rating: 1 with running water (a river) or the sea's
## edge beside it, 0 on dry ground.
func _in_water(id: String, o: Dictionary) -> float:
	var c := chunk_of_id(id)
	if c == null:
		return 0.0
	var at: Vector3 = c.position + o["p"]
	for a in 9:
		var p := at if a == 8 else at + Vector3(cos(a * TAU / 8.0), 0, sin(a * TAU / 8.0)) * 2.5
		if not is_nan(Water.river_surface(p.x, p.z)):
			return 1.0
		var cn := streamer.get_chunk(ChunkStreamer.chunk_of(p)) if streamer != null else null
		if cn != null and ChunkGenerator.height_at(cn.data, p.x - cn.position.x, p.z - cn.position.z) < Water.LEVEL:
			return 0.6 # tide and waves turn it, less than a river
	return 0.0

func _entries(net: Array, sun: Vector3) -> Array:
	var out: Array = []
	for id in net:
		var o := piece(id)
		if o.is_empty():
			continue
		var f := 1.0
		match String(Power.spec(o).get("source", "")):
			"wind": f = float(_site.get(id, 1.0))
			"water": f = float(_site.get(id, 0.0))
			"sun": f = Power.solar_factor(float(o["r"]), sun)
		out.append({"id": id, "o": o, "f": f, "en": bool(_en.get(id, true))})
	return out

func _env() -> Dictionary:
	var cloud := 0.3
	if atmosphere != null and atmosphere.sky_mat != null:
		var cc = atmosphere.sky_mat.get_shader_parameter("cloud_cover")
		if cc != null:
			cloud = float(cc)
	return {"wind": wind, "sun": Atmosphere.sun_dir, "cloud": cloud}

func _tick(dt: float) -> void:
	var env := _env()
	_logic(env)
	if _dirty:
		_rebuild() # a relay closed or opened
	for n in _nets.size():
		var es := _entries(_nets[n], env["sun"])
		var r := Power.solve(es, env, dt)
		_results[n] = r
		for e in es:
			e["o"]["st"]["pt"] = Game.day
			var me: Dictionary = r["pieces"].get(e["id"], {})
			_pose(e["id"], e["o"], me)
			if Signals.kind(e["o"]) == "motor":
				_drive_door(e["id"], e["o"], bool(me.get("powered", false)) and bool(e["en"]))
			elif Defences.is_defence(e["o"]):
				_defend(e["id"], e["o"], Power.is_on(e["o"]) and bool(me.get("powered", false)), bool(e["en"]), dt)
			elif Automation.is_auto(e["o"]):
				var runs := Power.role(e["o"]) == "box" or (Power.is_on(e["o"]) and bool(me.get("powered", false)))
				_automate(e["id"], e["o"], runs and bool(e["en"]), dt)

# --- Signals --------------------------------------------------------------------------

## One tick of the logic layer: every logic piece works out its output from its inputs as
## they were last tick; then what each signal-wired piece is told (relays close, consumers
## and generators run, door motors move).
func _logic(env: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var clock := Game.day * Game.day_seconds
	var ctx := {"now": now, "day": Game.day, "clock": clock, "hour": fposmod(Game.day, 1.0) * 24.0, "night": (env["sun"] as Vector3).y < 0.05}
	var next := {}
	for k in _index:
		var e: Array = _index[k]
		var c: ChunkNode = e[0]
		for i in e[1]:
			var o: Dictionary = c.data["objects"][i]
			if o["st"].get("gone", false) or not Signals.has_out(o):
				continue
			var id := Power.id_for(k, i)
			var ins: Array = []
			for src in Signals.inputs(o):
				ins.append(_signal(String(src)))
			var mem: Dictionary = _mem.get(id, {})
			_mem[id] = mem
			var kind := Signals.kind(o)
			if kind == "plate" or kind == "motion":
				var at: Vector3 = c.position + o["p"]
				var fwd := Basis(Vector3.UP, float(o["r"])) * Vector3(0, 0, 1)
				ctx["near"] = func(r: float, who: String, cone: bool) -> bool: return _senses(at, fwd, r, who, cone)
			elif kind == "charge":
				var r := network_of(id)
				ctx["charge"] = -1.0 if r.is_empty() or float(r["capacity"]) <= 0.0 else 100.0 * float(r["stored"]) / float(r["capacity"])
			var res := Signals.step(o, ins, mem, ctx)
			next[id] = bool(res[0])
			if bool(res[1]):
				Game.mark_chunk_dirty(c.data)
	for id in next:
		_sig[id] = next[id]
		var o := piece(id)
		if not o.is_empty():
			o["st"]["sg"] = next[id]
	_en.clear()
	for k in _index:
		var e: Array = _index[k]
		var c: ChunkNode = e[0]
		for i in e[1]:
			var o: Dictionary = c.data["objects"][i]
			var si := Signals.inputs(o)
			if si.is_empty() or o["st"].get("gone", false) or Signals.has_out(o):
				continue
			var on := false
			for src in si:
				if _signal(String(src)):
					on = true
					break
			var id := Power.id_for(k, i)
			if Power.role(o) == "switch":
				# A relay: closed while its signal is on.
				if Power.is_on(o) != on:
					o["st"]["on"] = on
					_dirty = true
			else:
				_en[id] = on

## A piece's output as of last tick (its saved one until it has run here).
func _signal(id: String) -> bool:
	if _sig.has(id):
		return bool(_sig[id])
	var o := piece(id)
	return false if o.is_empty() else bool(o["st"].get("sg", false))

## Whether someone (or some animal) is there for a plate or motion sensor: within `r` of
## `at` (across, for a plate; in front, in the cone, for a sensor).
func _senses(at: Vector3, fwd: Vector3, r: float, who: String, cone: bool) -> bool:
	for p in _beings(at, r + 1.0, who):
		var to: Vector3 = p - at
		if cone:
			if to.length() > r or to.length() < 0.05:
				continue
			if to.normalized().dot(fwd) < Signals.MOTION_CONE:
				continue
			return true
		if Vector2(to.x, to.z).length() <= r and to.y > -0.4 and to.y < 1.6:
			return true
	return false

## Where the people (you, other players, villagers) and animals near `at` are.
func _beings(at: Vector3, r: float, who: String) -> Array:
	var out: Array = []
	var w := get_parent()
	if w == null:
		return out
	if who != "animals":
		var pl = w.get("player")
		if pl is Node3D and (pl as Node3D).global_position.distance_to(at) <= r:
			out.append((pl as Node3D).global_position)
		var others = w.get_node_or_null("OtherPlayers")
		if others != null:
			for b in others.near(at, r):
				out.append((b as Node3D).global_position)
		var npcs = w.get("npcs")
		if npcs != null:
			out.append_array(npcs.people_near(at, r))
	if who != "people":
		var fauna = w.get("fauna")
		if fauna != null:
			for c in fauna.creatures_near(at, r):
				out.append((c as Node3D).global_position)
	return out

## A door motor moves its door when what it is told changes: open while powered and its
## signal is on, shut when that stops (in between, the door can be worked by hand). On a
## server only the player running the chunk's animals moves it, so it moves once.
func _drive_door(id: String, o: Dictionary, want: bool) -> void:
	var was = o["st"].get("mw")
	if was != null and bool(was) == want:
		return
	o["st"]["mw"] = want
	if was == null:
		return # just built or loaded: leave the door as it is
	var c := chunk_of_id(id)
	if c == null or not _authority(c.key):
		return
	var d := door_by(c.position + o["p"])
	if d.is_empty():
		return
	var dc: ChunkNode = d["chunk"]
	var door: Dictionary = d["obj"]
	if Doors.is_open(door) == want:
		return
	door["st"]["open"] = want
	if want:
		door["st"]["side"] = 1.0
	dc.door_changed(door["i"])
	var slide := bool(Doors.spec(door).get("slide", false))
	var wp: Vector3 = dc.position + door["p"] + Vector3(0, 1.2, 0)
	Audio.play_at(("door/slide_open" if slide else "door/open") if want else ("door/slide_close" if slide else "door/close"), wp, -4.0)

# --- Automation -----------------------------------------------------------------------

## One tick of a belt, hopper, arm or machine (see Automation). `runs`: powered (a hopper
## always), and told to by its signal if one is wired in.
func _automate(id: String, o: Dictionary, runs: bool, dt: float) -> void:
	var c := chunk_of_id(id)
	if c == null:
		return
	var mem: Dictionary = _mem.get(id, {})
	_mem[id] = mem
	mem["seen"] = true
	var pn := c.power_node(int(o["i"]))
	var k := Automation.kind(o)
	if pn != null:
		pn.set_running(runs and k != "hopper")
	if not runs or not _authority(c.key):
		if pn != null and k == "belt":
			pn.show_belt(o["st"].get("q", []), 0.0)
		return
	var s := Automation.spec(o)
	match k:
		"belt":
			var at_end := Automation.roll(o, dt)
			if at_end:
				var next := _neighbour(id, o, c, true)
				if not next.is_empty():
					var q: Array = o["st"]["q"]
					if Automation.put(next["o"], q[0][0]):
						q.pop_front()
						_moved(next["chunk"], c)
			if pn != null:
				pn.show_belt(o["st"].get("q", []), float(s.get("speed", 1.5)))
		"arm":
			mem["t"] = float(mem.get("t", 0.0)) + dt
			if float(mem["t"]) < float(s.get("every", 1.0)):
				return
			mem["t"] = 0.0
			var from := _neighbour(id, o, c, false)
			var to := _neighbour(id, o, c, true)
			if from.is_empty() or to.is_empty():
				return
			var it := Automation.take(from["o"], String(o["st"].get("flt", "")))
			if it.is_empty():
				return
			if Automation.put(to["o"], it):
				_moved(from["chunk"], to["chunk"])
				if pn != null:
					pn.swing()
			else:
				Automation.put(from["o"], it) # no room: back where it came from
		_:
			# Machines and hoppers: work (machines), then push what is made out the front.
			if k != "hopper":
				mem["w"] = float(mem.get("w", 0.0)) + dt
				if float(mem["w"]) >= float(s.get("every", 5.0)):
					mem["w"] = 0.0
					if Automation.work(o, _vein_of(id, o, c, mem), _zone(c, o), Game.origin_here("machined", -1, c.key), _rng, c.data):
						_touched[c.key] = c
			mem["p"] = float(mem.get("p", 0.0)) + dt
			if float(mem["p"]) >= Automation.PUSH_EVERY:
				mem["p"] = 0.0
				var next := _neighbour(id, o, c, true)
				if not next.is_empty() and Automation.kind(next["o"]) != "arm":
					var it := Automation.take(o)
					if not it.is_empty():
						if Automation.put(next["o"], it):
							_moved(next["chunk"], c)
						else:
							Automation.put(o, it)

var _rng := RandomNumberGenerator.new()
var _touched := {} ## chunk key -> ChunkNode whose belts, machines or chests changed since the last save

## Items moved between pieces: both chunks go into the next periodic save (marking them
## dirty each move would hold the save off for as long as the belts run).
func _moved(a: ChunkNode, b: ChunkNode) -> void:
	_touched[a.key] = a
	_touched[b.key] = b

func _zone(c: ChunkNode, o: Dictionary) -> int:
	var wp: Vector3 = c.position + o["p"]
	return Eras.zone_level(wp.x, wp.z) if Eras.themed() else 99

## The vein an auto-miner drills (worked out once per network rebuild).
func _vein_of(id: String, o: Dictionary, c: ChunkNode, mem: Dictionary) -> String:
	if Automation.kind(o) != "miner":
		return ""
	if int(mem.get("vv", -1)) != _ver:
		mem["vv"] = _ver
		mem["vein"] = Automation.vein_near(c, c.position + o["p"], float(Automation.spec(o).get("reach", 3.0)))
	return String(mem["vein"])

## The piece in front of (`ahead`) or behind a piece that items can go into or come out
## of, as {chunk, o}, or {}. Cached until the networks are worked out again.
func _neighbour(id: String, o: Dictionary, c: ChunkNode, ahead: bool) -> Dictionary:
	var mem: Dictionary = _mem[id]
	var key := "na" if ahead else "nb"
	if int(mem.get(key + "v", -1)) == _ver:
		var hit = mem.get(key)
		if hit == null:
			return {}
		var hc := streamer.get_chunk(hit[0]) if streamer != null else null
		if hc != null and int(hit[1]) < hc.data["objects"].size():
			var ho: Dictionary = hc.data["objects"][hit[1]]
			if not ho["st"].get("gone", false):
				return {"chunk": hc, "o": ho}
	mem[key + "v"] = _ver
	mem[key] = null
	var dist := Automation.reach(o) + 0.5
	var at := Automation.ahead_of(o, c.position, dist if ahead else -dist)
	var found := container_at(at, id)
	if not found.is_empty():
		mem[key] = [(found["chunk"] as ChunkNode).key, int(found["o"]["i"])]
	return found

## The belt, chest or machine standing at world point `at` (not `except`), as {chunk, o}.
func container_at(at: Vector3, except := "") -> Dictionary:
	if streamer == null:
		return {}
	var ck := ChunkStreamer.chunk_of(at)
	var best := {}
	var best_d := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cn := streamer.get_chunk(ck + Vector2i(dx, dz))
			if cn == null:
				continue
			for ob in cn.data["objects"]:
				if ob["st"].get("gone", false) or not Automation.is_container(ob["t"]):
					continue
				if Power.id_for(cn.key, int(ob["i"])) == except:
					continue
				var p: Vector3 = cn.position + ob["p"]
				var d := Vector2(p.x - at.x, p.z - at.z).length()
				if d <= maxf(Automation.reach(ob), 0.5) and absf(p.y - at.y) < 1.2 and d < best_d:
					best_d = d
					best = {"chunk": cn, "o": ob}
	return best

## A machine that was away (its chunk unloaded) makes up the cycles it missed, as far as
## its store has room. Only drills: the others would have run out of what to work.
func _machine_catch_up(id: String, o: Dictionary) -> void:
	var k := Automation.kind(o)
	if k != "miner" and k != "quarry":
		return
	var last := float(o["st"].get("pt", -1.0))
	var c := chunk_of_id(id)
	if last < 0.0 or c == null or not _authority(c.key) or not Power.is_on(o):
		return
	var secs := minf(Game.day - last, CATCH_UP_MAX) * Game.day_seconds
	var cycles := mini(int(secs / float(Automation.spec(o).get("every", 5.0))), Automation.CATCH_UP_MAX)
	var mem: Dictionary = _mem.get(id, {})
	_mem[id] = mem
	var vein := _vein_of(id, o, c, mem)
	var made := 0
	for n in cycles:
		if not Automation.work(o, vein, _zone(c, o), Game.origin_here("machined", -1, c.key), _rng, c.data):
			break
		made += 1
	if made > 0:
		Game.mark_chunk_dirty(c.data)

# --- Defences -------------------------------------------------------------------------

## One tick of a defence (see Defences): `powered` (switched on and getting power),
## `armed` (its signal, if one is wired in, is on).
func _defend(id: String, o: Dictionary, powered: bool, armed: bool, dt: float) -> void:
	var c := chunk_of_id(id)
	if c == null:
		return
	var pn := c.power_node(int(o["i"]))
	var s := Defences.spec(o)
	var mem: Dictionary = _mem.get(id, {})
	_mem[id] = mem
	var live := powered and armed
	var at: Vector3 = c.position + o["p"]
	var yaw := float(o["r"])
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1) # free pieces face -z
	var auth := _authority(c.key)
	match Defences.kind(o):
		"turret":
			var eye := at + Vector3(0, float(s.get("eye", 1.2)), 0)
			var foe: Array = _nearest_foe(eye, float(s.get("range", 24.0))) if live else []
			if pn != null:
				pn.aim(foe[1] if not foe.is_empty() else null)
			mem["t"] = float(mem.get("t", 0.0)) + dt
			if foe.is_empty() or int(o["st"].get("ammo", 0)) <= 0 or float(mem["t"]) < float(s.get("every", 0.6)):
				return
			mem["t"] = 0.0
			# Only once the barrels are on it (the head turns at its own speed).
			if pn != null and not pn.on_target(foe[1]):
				return
			o["st"]["ammo"] = int(o["st"]["ammo"]) - 1
			var muzzle: Vector3 = pn.muzzle() if pn != null else eye
			if pn != null:
				pn.shot(foe[1])
			Audio.play_at("weapon/explosion", muzzle, -16.0 if int(s.get("barrels", 1)) == 1 else -12.0)
			if auth:
				_strike(foe[0], float(s.get("damage", 15.0)) * randf_range(0.85, 1.15))
		"fence":
			if not live:
				return
			mem["t"] = float(mem.get("t", 0.0)) + dt
			if float(mem["t"]) < float(s.get("every", 1.0)):
				return
			mem["t"] = 0.0
			var a := Power.terminal(o, c.position)
			for other in Power.links(o):
				var oo := piece(String(other))
				if oo.is_empty() or Defences.kind(oo) != "fence" or String(other) < id:
					continue # each span once, from its lower id
				var b := terminal_of(String(other))
				var mid := (a + b) * 0.5
				for f in _foes_near(mid, a.distance_to(b) * 0.5 + 2.0):
					var p: Vector3 = f[1]
					var reach := float(s.get("reach", 0.9))
					# The wire runs at three heights up the post.
					var touch := false
					for hy in [-0.9, -0.45, 0.0]:
						if Defences.to_segment(p, a + Vector3(0, hy, 0), b + Vector3(0, hy, 0)) <= reach:
							touch = true
					if not touch:
						continue
					ImpactFx.strike(p, Vector3.UP, "metal", 0.6, true)
					Audio.play_at("weapon/laser", p, -10.0)
					if auth:
						_strike(f[0], float(s.get("damage", 8.0)))
						var cr := f[0] as Creature
						if cr != null and is_instance_valid(cr) and cr._body != null:
							cr.state = "flee"
							cr._think = 3.0
		"spikes":
			var plate_foes: Array = []
			for f in _foes_near(at, 1.4):
				var d: Vector3 = f[1] - at
				if absf(d.x) < 0.55 and absf(d.z) < 0.55 and d.y > -0.4 and d.y < 1.6:
					plate_foes.append(f)
			var fire := powered and ((not Signals.inputs(o).is_empty() and armed) or (Signals.inputs(o).is_empty() and not plate_foes.is_empty()))
			var was := bool(mem.get("up", false))
			mem["up"] = fire
			if pn != null:
				pn.apply(false, false, fire)
			if fire and not was:
				Audio.play_at("hit/metal", at, -2.0)
				if auth:
					for f in plate_foes:
						_strike(f[0], float(s.get("damage", 30.0)))
						var cr := f[0] as Creature
						if cr != null and is_instance_valid(cr):
							cr.held_for = float(s.get("hold", 2.0))
		"flame":
			var burning := live and float(o["st"].get("fuel", 0.0)) > 0.0
			if pn != null:
				pn.set_flame(burning)
			if not burning:
				return
			o["st"]["fuel"] = maxf(0.0, float(o["st"]["fuel"]) - dt)
			var nozzle := at + Vector3(0, float(s.get("eye", 0.5)), 0)
			if auth:
				for f in _foes_near(nozzle, float(s.get("range", 4.0))):
					if Defences.in_cone(nozzle, fwd, f[1] + Vector3(0, 0.5, 0), float(s.get("range", 4.0)), float(s.get("cone", 0.8))):
						_strike(f[0], float(s.get("dps", 14.0)) * dt)
		"bell":
			mem["t"] = float(mem.get("t", 0.0)) + dt
			if live and float(mem["t"]) >= 0.5:
				mem["t"] = 0.0
				Audio.play_at("hit/metal", at + Vector3(0, 0.3, 0), 2.0)
				if pn != null:
					pn.ring()
		"search":
			if pn != null:
				var foe: Array = _nearest_foe(at + Vector3(0, 1.7, 0), float(s.get("range", 60.0))) if live else []
				pn.aim(foe[1] if not foe.is_empty() else null)

## A blow from a defence: animals through FaunaManager (it passes it to whoever runs
## them, and the kill is yours), outlaws through NPCManager.
func _strike(target: Object, dmg: float) -> void:
	var w := get_parent()
	if w == null or not is_instance_valid(target):
		return
	if target is Creature:
		var fauna = w.get("fauna")
		if fauna != null and (target as Creature)._body != null:
			fauna.player_hit(target, dmg)
	elif Defences.hostile_npc(target):
		var npcs = w.get("npcs")
		if npcs != null:
			npcs.player_hit(target, dmg)

## What a defence goes for near `at`: [[node, where it is (its middle)], ...].
func _foes_near(at: Vector3, r: float) -> Array:
	var out: Array = []
	var w := get_parent()
	if w == null:
		return out
	var fauna = w.get("fauna")
	if fauna != null:
		for c in fauna.creatures_near(at, r):
			if Defences.hostile_creature(c):
				out.append([c, (c as Node3D).global_position + Vector3(0, float(c.p.get("size", 1.0)) * 0.35, 0)])
	var npcs = w.get("npcs")
	if npcs != null:
		for n in npcs.all_nodes():
			if is_instance_valid(n) and (n as Node3D).global_position.distance_to(at) <= r and Defences.hostile_npc(n):
				out.append([n, (n as Node3D).global_position + Vector3(0, 1.1, 0)])
	return out

## The nearest foe a turret or searchlight at `eye` can see within `r`, or [].
func _nearest_foe(eye: Vector3, r: float) -> Array:
	var best: Array = []
	var best_d := INF
	for f in _foes_near(eye, r):
		var d := eye.distance_to(f[1])
		if d < best_d and _clear(eye, f[1], f[0]):
			best_d = d
			best = f
	return best

## Nothing solid (ground, a wall) between `from` and `to` but the target itself.
func _clear(from: Vector3, to: Vector3, target: Object) -> bool:
	var dir := (to - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from + dir * 0.7, to, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col: Object = hit.get("collider")
	if col == null:
		return true
	for m in ["creature", "npc"]:
		if col.has_meta(m) and col.get_meta(m) == target:
			return true
	return false

## The door nearest a world point, within Signals.MOTOR_REACH, as {chunk, obj}, or {}.
func door_by(at: Vector3) -> Dictionary:
	if streamer == null:
		return {}
	var ck := ChunkStreamer.chunk_of(at)
	var best := {}
	var best_d := Signals.MOTOR_REACH
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			for o in c.data["objects"]:
				if not Doors.is_door(o["t"]) or o["st"].get("gone", false):
					continue
				var d: float = (c.position + o["p"] + Vector3(0, 1.0, 0)).distance_to(at)
				if d < best_d:
					best_d = d
					best = {"chunk": c, "obj": o}
	return best

## This game moves things in chunk `k` for everyone (offline, or it runs the animals there).
func _authority(k: Vector2i) -> bool:
	var net = get_tree().root.get_node_or_null("Net")
	if net == null or not net.is_client():
		return true
	return net.holds("f", k) or not net.shared("f", k)

## Runs a network over the time it was away (none of its pieces loaded), in steps, with
## the day's sun and an average wind.
func _catch_up(net: Array) -> void:
	var last := -1.0
	var es := _entries(net, Atmosphere.sun_dir)
	for e in es:
		last = maxf(last, float(e["o"]["st"].get("pt", -1.0)))
	if last < 0.0:
		return
	var away := minf(Game.day - last, CATCH_UP_MAX)
	var secs := away * Game.day_seconds
	if secs < CATCH_UP_STEP * 0.5:
		return
	var steps := ceili(secs / CATCH_UP_STEP)
	var dt := secs / steps
	for s in steps:
		var day := last + (s + 0.5) * away / steps
		var sun := Power.sun_dir_at(day)
		Power.solve(_entries(net, sun), {"wind": 0.35, "sun": sun, "cloud": 0.4}, dt)
	for e in es:
		e["o"]["st"]["pt"] = Game.day

func _pose(id: String, o: Dictionary, r: Dictionary) -> void:
	var c := chunk_of_id(id)
	if c == null:
		return
	var pn := c.power_node(int(o["i"]))
	if pn == null:
		return
	var s := Power.spec(o)
	var running := false
	match String(s.get("source", "")):
		"fuel": running = float(r.get("out", 0.0)) > 0.0 or (Power.is_on(o) and bool(_en.get(id, true)) and float(o["st"].get("fuel", 0.0)) > 0.0)
		"wind", "sun", "water": running = float(r.get("out", 0.0)) > 1.0
	var closed := Power.is_on(o) if Signals.kind(o) in ["", "lever", "relay", "motor"] else _signal(id)
	pn.apply(Power.is_on(o) and bool(r.get("powered", false)), running, closed)

## Fuel and charge change all the time; they go into the save (and to other players)
## every so often, not every tick. On a server only the player who runs a chunk's animals
## (or the only one there) saves them, so two players' copies don't fight.
func _save_running() -> void:
	var net = get_tree().root.get_node_or_null("Net")
	for k in _touched:
		if is_instance_valid(_touched[k]):
			Game.mark_chunk_dirty((_touched[k] as ChunkNode).data)
	_touched.clear()
	for k in _index:
		var e: Array = _index[k]
		var c: ChunkNode = e[0]
		var busy := false
		for i in e[1]:
			var s := Power.spec(c.data["objects"][i])
			if s.has("store") or s.has("fuel"):
				busy = true
				break
		if not busy:
			continue
		if net != null and net.is_client() and not net.holds("f", k) and net.shared("f", k):
			continue
		Game.mark_chunk_dirty(c.data)

func _online() -> bool:
	var net = get_tree().root.get_node_or_null("Net")
	return net != null and net.is_client()

## The network a piece is on, as its last Power.solve result ({} if none yet).
func network_of(id: String) -> Dictionary:
	var n = _net_of.get(id)
	if n == null or n >= _results.size() or _results[n] == null:
		return {}
	return _results[n]

func pieces_on(id: String) -> Array:
	var n = _net_of.get(id)
	return [] if n == null else _nets[n]

# --- Cables ---------------------------------------------------------------------------

func _draw_cables(pieces: Dictionary) -> void:
	var want := {}
	for id in pieces:
		for other in Power.links(pieces[id]):
			if not pieces.has(other):
				continue
			var key: String = (id + "|" + String(other)) if id < String(other) else (String(other) + "|" + id)
			want[key] = [id, String(other)]
			if Defences.kind(pieces[id]) == "fence" and Defences.kind(pieces[other]) == "fence":
				# An electric fence: two more strands below the top one.
				want["f1:" + key] = [id, String(other)]
				want["f2:" + key] = [id, String(other)]
		for dst in Signals.outputs(pieces[id]):
			if pieces.has(dst):
				want["s:" + id + ">" + String(dst)] = [id, String(dst)]
	for key in _cables.keys():
		if not want.has(key):
			_cables[key].queue_free()
			_cables.erase(key)
	for key in want:
		var sig := (key as String).begins_with("s:")
		var a := signal_terminal_of(want[key][0]) if sig else terminal_of(want[key][0])
		var b := signal_terminal_of(want[key][1]) if sig else terminal_of(want[key][1])
		if (key as String).begins_with("f"):
			var drop := Vector3(0, -0.45 if (key as String).begins_with("f1") else -0.9, 0)
			a += drop
			b += drop
		var mi: MeshInstance3D = _cables.get(key)
		if mi != null and mi.get_meta("ends", []) == [a, b]:
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = _signal_mat if sig else _cable_mat
			mi.visibility_range_end = 120.0 if sig else 220.0
			add_child(mi)
			_cables[key] = mi
		mi.mesh = cable_mesh(a, b, 0.006) if sig else cable_mesh(a, b)
		mi.set_meta("ends", [a, b])

func terminal_of(id: String) -> Vector3:
	var c := chunk_of_id(id)
	var o := piece(id)
	if c == null or o.is_empty():
		return Vector3.ZERO
	return Power.terminal(o, c.position)

## Where signal wires meet the piece, in world space.
func signal_terminal_of(id: String) -> Vector3:
	var c := chunk_of_id(id)
	var o := piece(id)
	if c == null or o.is_empty():
		return Vector3.ZERO
	return Power.signal_terminal(o, c.position)

## A sagging cable from a to b (world space): a thin tube along a catenary-like curve.
static func cable_mesh(a: Vector3, b: Vector3, radius := 0.012) -> ArrayMesh:
	var span := a.distance_to(b)
	var segs := clampi(int(span * 1.5), 4, 32)
	var sag := SAG * span + 0.05
	var pts: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	var rings: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var fwd: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(fwd).normalized()
		var ring: Array = []
		for s in sides:
			var ang := TAU * s / sides
			var nrm := side * cos(ang) + up * sin(ang)
			ring.append([p + nrm * radius, nrm])
		rings.append(ring)
	for i in rings.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var q := [rings[i][s], rings[i + 1][s], rings[i + 1][s2], rings[i][s], rings[i + 1][s2], rings[i][s2]]
			for v in q:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()

# --- What the player does -------------------------------------------------------------

## The prompt Interact shows on a powered piece, or "" when it has no use.
static func verb(o: Dictionary, sneaking: bool) -> String:
	var s := Power.spec(o)
	var nm := String(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("name", "piece")).to_lower()
	var lv := Signals.verb(o, sneaking)
	if lv != "":
		return lv
	var av := _auto_verb(o, sneaking, nm)
	if av != "":
		return av
	if Power.role(o) == "switch" and not Signals.inputs(o).is_empty():
		return "Check the %s" % nm
	match String(s.get("role", "")):
		"gen":
			if s.get("source", "") == "fuel":
				if sneaking or _fuel_in_pack(o).is_empty():
					return "Switch %s the %s" % ["off" if Power.is_on(o) else "on", nm]
				return "Fuel the %s" % nm
			return ("Lock the %s" if Power.is_on(o) else "Release the %s") % ("sails" if s.get("source", "") == "wind" else nm)
		"use":
			if not sneaking and not Defences.ammo_in_pack(o).is_empty() and int(o["st"].get("ammo", 0)) < Defences.AMMO_CAP:
				return "Load the %s" % nm
			if not sneaking and not Defences.fuel_in_pack(o).is_empty() and float(o["st"].get("fuel", 0.0)) < Defences.FUEL_CAP:
				return "Fuel the %s" % nm
			return "Switch %s the %s" % ["off" if Power.is_on(o) else "on", nm]
		"switch":
			return "%s the %s" % ["Open" if Power.is_on(o) else "Close", nm]
		"store":
			return "Check the %s" % nm
	return ""

## Fuel in your pack this generator burns: [[type, seconds per item], ...], best first.
static func _fuel_in_pack(o: Dictionary) -> Array:
	var out: Array = []
	if Game.inventory == null:
		return out
	var fuels: Dictionary = Power.spec(o).get("fuel", {})
	for t in fuels:
		if Game.inventory.count(t) > 0:
			out.append([t, float(fuels[t])])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out

## Interact on a powered piece (already checked to be yours, or your alliance's).
func use_piece(chunk: ChunkNode, o: Dictionary, sneaking: bool) -> void:
	var s := Power.spec(o)
	var nm := String(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("name", "piece")).to_lower()
	var id := id_of(chunk, o)
	if _use_logic(chunk, o, sneaking, nm) or _use_auto(chunk, o, sneaking, nm):
		return
	match String(s.get("role", "")):
		"gen":
			if s.get("source", "") == "fuel" and not sneaking and not _fuel_in_pack(o).is_empty():
				var added := _add_fuel(o)
				if added == "":
					Game.toast.emit("The %s's tank is full: %s of running" % [nm, Power.run_time(float(o["st"].get("fuel", 0.0)))])
					return
				o["st"]["on"] = true
				Game.toast.emit("Fed the %s %s: %s of running at full load" % [nm, added, Power.run_time(float(o["st"].get("fuel", 0.0)))])
				Audio.play_at("hit/plank", chunk.position + o["p"], -8.0)
			else:
				o["st"]["on"] = not Power.is_on(o)
				if Power.is_on(o) and s.get("source", "") == "fuel" and float(o["st"].get("fuel", 0.0)) <= 0.0:
					var names: Array = []
					for t in (s.get("fuel", {}) as Dictionary).keys().slice(0, 4):
						names.append(String(ItemDB.def(t).get("name", t)).to_lower())
					Game.toast.emit("The %s has no fuel. It burns %s and more" % [nm, ", ".join(names)])
				else:
					Game.toast.emit("%s the %s" % ["Started" if Power.is_on(o) else "Stopped", nm])
		"use":
			if not sneaking and not Defences.ammo_in_pack(o).is_empty() and int(o["st"].get("ammo", 0)) < Defences.AMMO_CAP:
				var n := Defences.load_ammo(o)
				Audio.play_at("weapon/draw", chunk.position + o["p"], -6.0)
				Game.toast.emit("Loaded %d rounds into the %s: %d in all" % [n, nm, int(o["st"]["ammo"])])
			elif not sneaking and not Defences.fuel_in_pack(o).is_empty() and float(o["st"].get("fuel", 0.0)) < Defences.FUEL_CAP:
				var w := Defences.load_fuel(o)
				Audio.play_at("hit/plank", chunk.position + o["p"], -8.0)
				Game.toast.emit("Filled the %s with %s: %d s of burning" % [nm, w, int(o["st"]["fuel"])])
			else:
				o["st"]["on"] = not Power.is_on(o)
				Audio.play_at("door/lock", chunk.position + o["p"], -14.0)
		"switch":
			if not Signals.inputs(o).is_empty():
				Game.toast.emit("The %s is %s: it follows the signal wired into it" % [nm, "closed" if Power.is_on(o) else "open"])
				return
			o["st"]["on"] = not Power.is_on(o)
			_dirty = true
			Audio.play_at("door/lock", chunk.position + o["p"], -6.0)
			Game.toast.emit("%s the %s: %s" % ["Closed" if Power.is_on(o) else "Opened", nm, "power flows through it" if Power.is_on(o) else "the line beyond it is cut"])
		"store":
			var r := network_of(id)
			var cap := float(s.get("store", 0.0))
			var ch := float(o["st"].get("charge", 0.0))
			Game.toast.emit("%s: %s of %s (%d%%)%s" % [String(BuildCatalog.def(BuildCatalog.id_of(o["t"]))["name"]), Power.energy(ch), Power.energy(cap),
				roundi(100.0 * ch / maxf(cap, 1.0)), "" if r.is_empty() else ", network %s made, %s used" % [Power.watts(r["supply"]), Power.watts(r["demand"])]])
			return
		_:
			return
	Game.mark_chunk_dirty(chunk.data)
	# Show it at once rather than on the next tick.
	var n = _net_of.get(id)
	if n != null and not _dirty:
		_tick(0.0)

## What Interact does on an automation piece ("" for the usual power use).
static func _auto_verb(o: Dictionary, sneaking: bool, nm: String) -> String:
	if not Automation.is_auto(o):
		return ""
	match Automation.kind(o):
		"arm":
			return "Set what it moves to what you hold" if sneaking else "Switch %s the %s" % ["off" if Power.is_on(o) else "on", nm]
		"assembler":
			if sneaking:
				return "Pick what it makes"
		"miner":
			if sneaking:
				return "Pick which ore it drills"
		"belt":
			return "Switch %s the %s" % ["off" if Power.is_on(o) else "on", nm]
	if Storage.capacity(o) > 0 and not sneaking:
		return "Open the %s" % nm
	return ""

## Interact on an automation piece. False when it is the usual power use (on / off).
func _use_auto(chunk: ChunkNode, o: Dictionary, sneaking: bool, nm: String) -> bool:
	if not Automation.is_auto(o):
		return false
	match Automation.kind(o):
		"arm":
			if not sneaking:
				return false
			var it = Game.player.held_item() if Game.player is Player else null
			o["st"]["flt"] = "" if it == null else String(it["type"])
			Game.toast.emit("The %s now moves %s" % [nm, "everything" if it == null else String(ItemDB.def(it["type"]).get("name", it["type"]))])
			Game.mark_chunk_dirty(chunk.data)
			return true
		"miner":
			if sneaking:
				var cur := Deposits.target(chunk.data, String(o["st"].get("ore", "")))
				var ore := Deposits.next_target(chunk.data, cur)
				o["st"]["ore"] = ore
				Game.toast.emit("The %s now drills %s" % [nm, String(ItemDB.def(ore).get("name", ore))] if ore != "" else "There is no ore left under this tile")
				Game.mark_chunk_dirty(chunk.data)
				return true
		"assembler":
			if sneaking:
				var what := Automation.next_recipe(o)
				Game.toast.emit("The %s now makes %s" % [nm, what] if what != "" else "Put the ingredients for what it should make in it first")
				Game.mark_chunk_dirty(chunk.data)
				return true
		"belt":
			return false
	if Storage.capacity(o) > 0 and not sneaking:
		get_tree().call_group("trade_ui", "open_storage", o, chunk)
		return true
	return false

## Interact on a logic piece: pull a lever, press a button, or turn a setting on a step.
## False when the piece has nothing of the kind (and the power use goes ahead).
func _use_logic(chunk: ChunkNode, o: Dictionary, sneaking: bool, nm: String) -> bool:
	var at: Vector3 = chunk.position + o["p"]
	match Signals.kind(o):
		"lever":
			o["st"]["on"] = not Power.is_on(o)
			Audio.play_at("door/lock", at, -4.0)
		"button":
			if sneaking:
				Game.toast.emit("%s: %s" % [nm.capitalize(), Signals.cycle(o, true)])
			else:
				Signals.press(o, Game.day, Game.day_seconds)
				Audio.play_at("door/lock", at, -10.0)
		"", "relay", "motor":
			return false
		_:
			var now := Signals.cycle(o, sneaking)
			if now == "":
				return false
			Audio.play_at("door/lock", at, -12.0)
			Game.toast.emit("%s: %s" % [nm.capitalize(), now])
	Game.mark_chunk_dirty(chunk.data)
	return true

## Tops up a generator's tank from your pack, best fuel first. Returns what went in, in
## words ("4 oak wood"), or "" when the tank is full.
func _add_fuel(o: Dictionary) -> String:
	var fuel := float(o["st"].get("fuel", 0.0))
	var used := {}
	for f in _fuel_in_pack(o):
		var type: String = f[0]
		var each: float = f[1]
		while fuel + each <= Power.FUEL_CAP + each * 0.5 and Game.inventory.count(type) > 0:
			Game.inventory.remove_type(type, 1)
			fuel += each
			used[type] = int(used.get(type, 0)) + 1
	o["st"]["fuel"] = minf(fuel, Power.FUEL_CAP)
	var words: Array = []
	for t in used:
		words.append("%d %s" % [used[t], String(ItemDB.def(t).get("name", t)).to_lower()])
	return ", ".join(words)

## Lines for the look-at panel. With a multimeter held, the whole network's breakdown.
func describe(chunk: ChunkNode, o: Dictionary, meter: bool) -> Array:
	var s := Power.spec(o)
	var id := id_of(chunk, o)
	var r := network_of(id)
	var me: Dictionary = r.get("pieces", {}).get(id, {})
	var lines := signal_lines(id, o)
	if Automation.is_auto(o):
		lines.append_array(Automation.lines(o))
		if Automation.kind(o) == "miner":
			lines.append_array(Deposits.lines(chunk.data, String(o["st"].get("ore", ""))))
	if Power.role(o) == "logic" or Power.role(o) == "box":
		return lines
	match String(s.get("role", "")):
		"gen":
			var out := float(me.get("out", 0.0))
			match String(s.get("source", "")):
				"fuel":
					var fuel := float(o["st"].get("fuel", 0.0))
					lines.append("%s  ·  making %s of %s" % ["Running" if Power.is_on(o) and fuel > 0.0 else ("Out of fuel" if fuel <= 0.0 else "Stopped"), Power.watts(out), Power.watts(float(s["watts"]))])
					lines.append("Fuel: %s at full load" % Power.run_time(fuel))
				"wind":
					lines.append("%s  ·  making %s of %s" % ["Sails locked" if not Power.is_on(o) else "Turning", Power.watts(out), Power.watts(float(s["watts"]))])
					var f := float(_site.get(id, 1.0))
					lines.append("Wind %d%%  ·  %s" % [roundi(wind * 100.0), "well exposed" if f > 1.15 else ("sheltered" if f < 0.85 else "open ground")])
				"water":
					lines.append("Making %s of %s" % [Power.watts(out), Power.watts(float(s["watts"]))])
					lines.append("In running water" if float(_site.get(id, 0.0)) >= 1.0 else ("At the sea's edge" if float(_site.get(id, 0.0)) > 0.0 else "On dry ground: build it in a river"))
				"sun":
					var f := Power.solar_factor(float(o["r"]), Atmosphere.sun_dir)
					lines.append("Making %s of %s" % [Power.watts(out), Power.watts(float(s["watts"]))])
					lines.append("Facing %d%% of the sun" % roundi(f * 100.0) if Atmosphere.sun_dir.y > 0.0 else "Night: no sun")
		"store":
			var cap := float(s.get("store", 0.0))
			var ch := float(o["st"].get("charge", 0.0))
			var flow := float(me.get("flow", 0.0))
			lines.append("Charge %s of %s (%d%%)" % [Power.energy(ch), Power.energy(cap), roundi(100.0 * ch / maxf(cap, 1.0))])
			if absf(flow) > 1.0:
				lines.append("%s at %s" % ["Charging" if flow > 0.0 else "Discharging", Power.watts(absf(flow))])
		"use":
			var on := Power.is_on(o)
			var armed := bool(_en.get(id, true))
			lines.append("%s  ·  draws %s" % ["Off" if not on else ("On" if me.get("powered", false) else ("Waiting for its signal" if not armed else "No power")), Power.watts(float(s["watts"]))])
			if Defences.is_defence(o):
				lines.append_array(Defences.lines(o, armed))
		"switch":
			lines.append("Closed: power flows through" if Power.is_on(o) else "Open: the line is cut here")
		"node":
			lines.append("Joins up to %d cables" % int(s.get("links", 4)))
	lines.append("Cables: %d of %d" % [Power.links(o).size(), Power.max_links(o)])
	if r.is_empty() or pieces_on(id).size() <= 1:
		lines.append("Not wired to anything: string Copper Wire to it")
		return lines
	var line := "Network: makes %s, uses %s" % [Power.watts(r["supply"]), Power.watts(r["demand"])]
	if float(r["capacity"]) > 0.0:
		line += ", stored %s of %s" % [Power.energy(r["stored"]), Power.energy(r["capacity"])]
	lines.append(line)
	if float(r["short"]) > 0.5:
		lines.append("Short by %s: some lights are dark" % Power.watts(r["short"]))
	elif float(r["capacity"]) > 0.0 and float(r["demand"]) > float(r["supply"]) + 0.5:
		var hours := float(r["stored"]) / maxf(float(r["demand"]) - float(r["supply"]), 0.1)
		lines.append("Batteries last about %s at this load" % Power.run_time(hours * 60.0))
	if meter:
		var count := {}
		for pid in pieces_on(id):
			var po := piece(pid)
			if po.is_empty():
				continue
			var nm := String(BuildCatalog.def(BuildCatalog.id_of(po["t"])).get("name", "?"))
			count[nm] = int(count.get(nm, 0)) + 1
		var parts: Array = []
		for nm in count:
			parts.append("%d %s" % [count[nm], nm])
		lines.append("On it: " + ", ".join(parts))
	return lines

## The logic side of a piece for the look-at panel: its setting, its output and its
## signal wires.
func signal_lines(id: String, o: Dictionary) -> Array:
	var lines: Array = []
	var set := Signals.describe_setting(o)
	if set != "":
		lines.append(set)
	if Signals.has_out(o):
		lines.append("Signal out: %s" % ("ON" if _signal(id) else "off"))
	var ins := Signals.inputs(o)
	if not ins.is_empty():
		var on := 0
		for src in ins:
			if _signal(String(src)):
				on += 1
		lines.append("Signal in: %d wire%s, %d on" % [ins.size(), "" if ins.size() == 1 else "s", on])
	if Power.role(o) == "logic" or Signals.max_in(o) > 0:
		var parts: Array = []
		if Signals.has_out(o):
			parts.append("%d out" % Signals.outputs(o).size())
		if Signals.max_in(o) > 0:
			parts.append("%d of %d in" % [ins.size(), Signals.max_in(o)])
		lines.append("Signal wires: " + ", ".join(parts))
	if Power.role(o) == "logic" and ins.is_empty() and Signals.outputs(o).is_empty():
		lines.append("Run Signal Wire from it to what it should work")
	return lines

## Wires one piece's signal output into another's input. Returns "" or why not, in words.
func connect_signal(ca: ChunkNode, a: Dictionary, cb: ChunkNode, b: Dictionary) -> String:
	var ia := id_of(ca, a)
	var ib := id_of(cb, b)
	if ia == ib:
		return "That's the same piece"
	if not Signals.has_out(a):
		return "It makes no signal: start at a lever, button, sensor, timer or gate"
	if Signals.max_in(b) == 0:
		return "That takes no signal"
	if Signals.inputs(b).has(ia):
		return "They're already wired"
	if Signals.inputs(b).size() >= Signals.max_in(b):
		return "Every signal input on it is taken (%d)" % Signals.max_in(b)
	var length := Power.signal_terminal(a, ca.position).distance_to(Power.signal_terminal(b, cb.position))
	if length > Signals.MAX_SPAN:
		return "Too far: a signal wire spans at most %d m (that's %d m)" % [int(Signals.MAX_SPAN), int(length)]
	var need := Signals.wire_for(length)
	if Game.inventory.count(Signals.WIRE) < need:
		return "Needs %d Signal Wire for %d m" % [need, int(length)]
	if not Signals.link(a, ia, b, ib):
		return "Can't wire those"
	Game.inventory.remove_type(Signals.WIRE, need)
	var spent: Dictionary = a["st"].get("sg_wire", {})
	spent[ib] = need
	a["st"]["sg_wire"] = spent
	Game.mark_chunk_dirty(ca.data)
	if cb != ca:
		Game.mark_chunk_dirty(cb.data)
	_dirty = true
	return ""

## Takes down every signal wire on a piece, in and out; returns the Signal Wire back.
func unhook_signals(chunk: ChunkNode, o: Dictionary) -> int:
	var id := id_of(chunk, o)
	var back := 0
	for dst in Signals.outputs(o).duplicate():
		var w := int((o["st"].get("sg_wire", {}) as Dictionary).get(dst, 1))
		var oo := piece(String(dst))
		if not oo.is_empty():
			Signals.unlink_in(oo, id)
			_dirty_chunk(String(dst), chunk)
		back += maxi(w, 1)
	for src in Signals.inputs(o).duplicate():
		var so := piece(String(src))
		var w := 1
		if not so.is_empty():
			w = int((so["st"].get("sg_wire", {}) as Dictionary).get(id, 1))
			Signals.unlink_out(so, id)
			(so["st"].get("sg_wire", {}) as Dictionary).erase(id)
			_dirty_chunk(String(src), chunk)
		back += maxi(w, 1)
	o["st"]["si"] = []
	o["st"]["so"] = []
	o["st"]["sg_wire"] = {}
	Game.mark_chunk_dirty(chunk.data)
	_dirty = true
	return back

func _dirty_chunk(id: String, other_than: ChunkNode) -> void:
	var c := chunk_of_id(id)
	if c != null and c != other_than:
		Game.mark_chunk_dirty(c.data)

## Strings a cable between two pieces. Returns "" or why not, in words.
func connect_pieces(ca: ChunkNode, a: Dictionary, cb: ChunkNode, b: Dictionary) -> String:
	var ia := id_of(ca, a)
	var ib := id_of(cb, b)
	if ia == ib:
		return "That's the same piece"
	if Power.links(a).has(ib):
		return "They're already joined"
	var length := Power.terminal(a, ca.position).distance_to(Power.terminal(b, cb.position))
	if length > Power.MAX_CABLE:
		return "Too far: a cable spans at most %d m (that's %d m). Put up a power pole between" % [int(Power.MAX_CABLE), int(length)]
	if Power.links(a).size() >= Power.max_links(a) or Power.links(b).size() >= Power.max_links(b):
		return "No free terminal: a junction box or pole joins more cables"
	var need := Power.wire_for(length)
	if Game.inventory.count(Power.WIRE) < need:
		return "Needs %d Copper Wire for %d m" % [need, int(length)]
	if not Power.link(a, ia, b, ib):
		return "Can't join those"
	Game.inventory.remove_type(Power.WIRE, need)
	# Remember how much went in, so taking it down gives it back.
	var spent: Dictionary = a["st"].get("pw_wire", {})
	spent[ib] = need
	a["st"]["pw_wire"] = spent
	Game.mark_chunk_dirty(ca.data)
	if cb != ca:
		Game.mark_chunk_dirty(cb.data)
	_dirty = true
	return ""

## Takes down every cable on a piece; returns the Copper Wire they come back as.
func unhook(chunk: ChunkNode, o: Dictionary) -> int:
	var id := id_of(chunk, o)
	var back := 0
	for other in Power.links(o).duplicate():
		var oo := piece(String(other))
		var spent: Dictionary = o["st"].get("pw_wire", {})
		var w := int(spent.get(other, 0))
		if not oo.is_empty():
			w = maxi(w, int((oo["st"].get("pw_wire", {}) as Dictionary).get(id, 0)))
			Power.unlink(oo, id)
			(oo["st"].get("pw_wire", {}) as Dictionary).erase(id)
			var oc := chunk_of_id(String(other))
			if oc != null and oc != chunk:
				Game.mark_chunk_dirty(oc.data)
		back += maxi(w, 1)
	o["st"]["pw"] = []
	o["st"]["pw_wire"] = {}
	Game.mark_chunk_dirty(chunk.data)
	_dirty = true
	return back
