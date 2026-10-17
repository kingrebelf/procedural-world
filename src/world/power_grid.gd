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

func _ready() -> void:
	current = self
	top_level = true
	_cable_mat = Materials.get_mat("rubber") as StandardMaterial3D
	if streamer != null:
		streamer.chunk_ready.connect(func(n: ChunkNode): _scan(n))

func _exit_tree() -> void:
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

func _entries(net: Array, sun: Vector3) -> Array:
	var out: Array = []
	for id in net:
		var o := piece(id)
		if o.is_empty():
			continue
		var f := 1.0
		match String(Power.spec(o).get("source", "")):
			"wind": f = float(_site.get(id, 1.0))
			"sun": f = Power.solar_factor(float(o["r"]), sun)
		out.append({"id": id, "o": o, "f": f})
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
	for n in _nets.size():
		var es := _entries(_nets[n], env["sun"])
		var r := Power.solve(es, env, dt)
		_results[n] = r
		for e in es:
			e["o"]["st"]["pt"] = Game.day
			_pose(e["id"], e["o"], r["pieces"].get(e["id"], {}))

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
		"fuel": running = float(r.get("out", 0.0)) > 0.0 or (Power.is_on(o) and float(o["st"].get("fuel", 0.0)) > 0.0)
		"wind", "sun": running = float(r.get("out", 0.0)) > 1.0
	pn.apply(Power.is_on(o) and bool(r.get("powered", false)), running, Power.is_on(o))

## Fuel and charge change all the time; they go into the save (and to other players)
## every so often, not every tick. On a server only the player who runs a chunk's animals
## (or the only one there) saves them, so two players' copies don't fight.
func _save_running() -> void:
	var net = get_tree().root.get_node_or_null("Net")
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
	for key in _cables.keys():
		if not want.has(key):
			_cables[key].queue_free()
			_cables.erase(key)
	for key in want:
		var a := terminal_of(want[key][0])
		var b := terminal_of(want[key][1])
		var mi: MeshInstance3D = _cables.get(key)
		if mi != null and mi.get_meta("ends", []) == [a, b]:
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = _cable_mat
			mi.visibility_range_end = 220.0
			add_child(mi)
			_cables[key] = mi
		mi.mesh = cable_mesh(a, b)
		mi.set_meta("ends", [a, b])

func terminal_of(id: String) -> Vector3:
	var c := chunk_of_id(id)
	var o := piece(id)
	if c == null or o.is_empty():
		return Vector3.ZERO
	return Power.terminal(o, c.position)

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
	match String(s.get("role", "")):
		"gen":
			if s.get("source", "") == "fuel":
				if sneaking or _fuel_in_pack(o).is_empty():
					return "Switch %s the %s" % ["off" if Power.is_on(o) else "on", nm]
				return "Fuel the %s" % nm
			return ("Lock the %s" if Power.is_on(o) else "Release the %s") % ("sails" if s.get("source", "") == "wind" else nm)
		"use":
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
			o["st"]["on"] = not Power.is_on(o)
			Audio.play_at("door/lock", chunk.position + o["p"], -14.0)
		"switch":
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
	var lines: Array = []
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
			lines.append("%s  ·  draws %s" % ["Off" if not on else ("On" if me.get("powered", false) else "No power"), Power.watts(float(s["watts"]))])
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
