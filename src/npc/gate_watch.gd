class_name GateWatch
extends Node
## The watch on walled towns' gates, and how towns come to think of you (Standing).
##
## Every town you come near is noted, so word of what you do can reach it, and its
## people's regard for you is kept. At a walled town, whoever of its guards is near the
## gate stops a stranger coming in (GatePolicy says who that is): talk to them to pay the
## toll, try a bribe, name a friend in town who'll vouch for you, or turn back. If no
## guard is watching the gate, you can slip in, but inside, any guard who doesn't know
## your face asks for your pass; stay without one and it's trespass, which the town puts
## a bounty on like any crime. Those who earned their standing are waved through.
##
## At night, strict towns drop the portcullis in each gateway for anyone without leave
## (it rises for those with it); a rope thrown over an unwatched stretch of wall gets you
## over all the same, if nobody sees you climb.
##
## Runs on each player's own game with their own standing, so it works the same online
## (each player sees the portcullis as it stands for them).

const TICK := 0.25
## How near a gate (metres) the guard there stops you.
const HALT_R := 16.0
## How far from the gate a guard can be and still come to stop you.
const GUARD_R := 34.0
## How near a guard inside must be to ask for your pass.
const ASK_R := 14.0
## Seconds you have to sort it out (pay, or leave) once a guard asks for your pass.
const GRACE := 25.0
## Marks of trade with a town for each point of standing, and the most a day earns.
const TRADE_PER := 40
const TRADE_DAY_CAP := 5

var manager: NPCManager
var _t := 0.0
var _trade := {} ## sid -> [day number, marks this day]

func _ready() -> void:
	Game.vouch_betrayed.connect(_on_betrayed)
	Game.traded.connect(_on_traded)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	_climb_step(delta)
	_move_ports(delta)
	_t -= delta
	if _t > 0.0 or manager == null or manager.player == null or Game.store == null:
		return
	_t = TICK
	var pp: Vector3 = manager.player.global_position
	for e in manager.settlements.values():
		if e["data"].has("band") or e.has("boat") or not e.has("sid"):
			continue
		_watch(e, pp)

## Per town, its gate's state for you: {tp, gates, inside, halted_t, welcomed, warned, warn_until, folk_t}.
func _state(e: Dictionary) -> Dictionary:
	if e.has("gate"):
		return e["gate"]
	var site: Dictionary = e["site"]
	var sid := String(e["sid"])
	var g := {"inside": null, "halted_t": -999.0, "welcomed": false, "warned": false, "warn_until": 0.0, "folk_t": -999.0, "gates": []}
	if GatePolicy.is_walled(site):
		for it in manager.gen.settlement_layout(site):
			if it["t"] == "castle_gate":
				g["gates"].append(it["p"])
	e["gate"] = g
	Game.standing.note(sid, String(e["data"]["name"]), site["center"], Game.day)
	return g

func _watch(e: Dictionary, pp: Vector3) -> void:
	var g := _state(e)
	var t := _now()
	var sid := String(e["sid"])
	if t - float(g["folk_t"]) > 5.0:
		g["folk_t"] = t
		Game.standing.note(sid, String(e["data"]["name"]), e["site"]["center"], Game.day)
		g["tp"] = GatePolicy.temper(e["site"], e["data"])
		Game.standing.set_folk(sid, GatePolicy.folk_regard(e["data"]))
	# At night strict towns drop the portcullis, for anyone without leave to come in.
	if not (g["gates"] as Array).is_empty():
		g["shut"] = bool(g["tp"]["night_shut"]) and GatePolicy.is_night(NPCMind.hour_now()) and not verdict(e)["ok"]
	if (g["gates"] as Array).is_empty() or manager.player.get("ui_open"):
		return
	var site: Dictionary = e["site"]
	var c: Vector2 = site["center"]
	var p2 := Vector2(pp.x, pp.z)
	var d := p2.distance_to(c)
	var rad := float(site["inner"]) + 2.5 ## Stronghold.town_wall's ring
	if d > rad + 60.0:
		g["welcomed"] = false
		g["warned"] = false
		g["inside"] = false
		return
	var gate: Vector2 = g["gates"][0]
	for q in g["gates"]:
		if (q as Vector2).distance_to(p2) < gate.distance_to(p2):
			gate = q
	var gd := gate.distance_to(p2)
	var inside := d < rad - 1.0
	if g["inside"] == null:
		g["inside"] = inside # where you were when the town came near (a load inside is no crossing)
		return
	var v := verdict(e)
	if v["why"] == "disguise" and _seen_through(e, gate, gd, inside, pp, t):
		v = verdict(e)
	if v["ok"]:
		if not inside and gd < HALT_R * 0.8 and not g["welcomed"]:
			var guard := _gate_guard(e, gate, pp)
			if guard != null and guard.global_position.distance_to(pp) < 16.0:
				g["welcomed"] = true
				manager._bark(guard, GatePolicy.welcome_line(v["why"], Game.town_tier(sid)) if v["why"] != "disguise"
					else ["Evening.", "All quiet out there?", "On you go. Sergeant's looking for you."][randi() % 3], guard.global_position.distance_to(pp))
				guard.act("nod" if v["why"] != "standing" or Game.town_standing(sid) < 65 else "salute")
		elif gd > HALT_R * 2.0:
			g["welcomed"] = false
		g["warned"] = false
		g["inside"] = inside
		return
	# No leave to come in. At the gate: the guard there stops you.
	if not inside and d > rad and gd < HALT_R and t - float(g["halted_t"]) > 30.0:
		var guard := _gate_guard(e, gate, pp)
		if guard != null:
			g["halted_t"] = t
			_challenge(guard, GatePolicy.halt_line(v["why"], String(e["data"]["name"]), GatePolicy.toll(g["tp"], NPCMind.hour_now())), 15.0, pp)
			Game.toast.emit("The gate of %s is watched. Talk to the guard to get in." % e["data"]["name"])
	# Coming through.
	if inside and not g["inside"]:
		var seen := _seen_by(e, pp, 26.0, 0.35)
		if seen != null:
			_trespass(e, pp, seen)
		else:
			Game.toast.emit("You slipped into %s unseen. Guards who don't know you will ask for your pass." % e["data"]["name"])
			Game.practice("sneak", 3.0)
	# Inside without a pass: a guard who doesn't know you asks for it.
	elif inside:
		var asker := _seen_by(e, pp, ASK_R, 0.45, true)
		if asker != null:
			if not g["warned"]:
				g["warned"] = true
				g["warn_until"] = t + GRACE
				_challenge(asker, ["I don't know your face. Where's your pass?", "You there. Who let you in? Show me your pass.",
					"Hold. Strangers pay at the gate. Pay up or get out."][randi() % 3], GRACE, pp)
				Game.toast.emit("A guard wants to see your pass: talk to them, or leave %s." % e["data"]["name"])
			elif t > float(g["warn_until"]):
				_trespass(e, pp, asker)
	if not inside and d > rad + 8.0:
		g["warned"] = false
	g["inside"] = inside

## A guard comes over to stop you and says so (already confronting, so the usual
## confrontation bark doesn't talk over it).
func _challenge(guard: NPC, line: String, seconds: float, pp: Vector3) -> void:
	manager.instruct(guard, "confront", seconds)
	guard.action = "confront"
	guard.target_player = true
	manager._bark(guard, line, guard.global_position.distance_to(pp))
	guard.act("point")

## Caught in town without leave: a bounty, and the town thinks less of you.
func _trespass(e: Dictionary, pp: Vector3, guard: NPC) -> void:
	var g: Dictionary = e["gate"]
	g["warned"] = true
	g["warn_until"] = _now() + 45.0
	manager.report_crime(pp, "trespass", 0, "", guard)
	Game.standing_deed(String(e["sid"]), Standing.DEEDS["trespass"])

## Whether the town's gates let you through now: GatePolicy.admit.
func verdict(e: Dictionary) -> Dictionary:
	var sid := String(e["sid"])
	var g := _state(e)
	if not g.has("tp"):
		g["tp"] = GatePolicy.temper(e["site"], e["data"])
	var v := GatePolicy.admit(g["tp"], Game.town_standing(sid), Game.is_citizen(sid), not Game.guilds.is_empty(),
		Game.crime.stars(sid, Game.day), Game.standing.has_pass(sid, Game.day) or has_writ(sid, e["site"]["center"]), NPCMind.hour_now())
	if not v["ok"] and v["why"] != "wanted" and disguised(e):
		return {"ok": true, "why": "disguise"}
	return v

## The guard nearest the gate and awake to come and stop you, or null.
func _gate_guard(e: Dictionary, gate: Vector2, pp: Vector3) -> NPC:
	var best: NPC = null
	var bd := GUARD_R
	for n in e["nodes"]:
		if not _on_watch(n):
			continue
		var q := Vector2(n.global_position.x, n.global_position.z)
		var dd := minf(q.distance_to(gate), n.global_position.distance_to(pp))
		if dd < bd:
			bd = dd
			best = n
	return best

## A guard of the town within `r` who notices you now (rolled), or null. `strangers_only`:
## only one who doesn't know you well enough to wave you on.
func _seen_by(e: Dictionary, pp: Vector3, r: float, at_least: float, strangers_only := false) -> NPC:
	for n in e["nodes"]:
		if not _on_watch(n) or n.global_position.distance_to(pp) > r:
			continue
		if strangers_only and int(n.rec.get("rel", 0)) >= GatePolicy.KNOWS_REL:
			continue
		var a := manager.awareness(n, pp)
		if a >= at_least and randf() < a:
			return n
	return null

static func _on_watch(n: NPC) -> bool:
	return is_instance_valid(n) and NPCGen.GUARD_JOBS.has(String(n.rec["job"])) and not n.rec.get("dead", false) and not n.is_hidden() and n.action != "sleep"

# --- At the gate, talking to a guard (DialogueUI) ---------------------------------------------

## The walled town this guard keeps the gate of, or {}.
func gate_of(n: NPC) -> Dictionary:
	if n == null or not NPCGen.GUARD_JOBS.has(String(n.rec["job"])) or n.settlement.has("band"):
		return {}
	var e := manager._entry_of(n.settlement)
	if e.is_empty() or not GatePolicy.is_walled(e["site"]):
		return {}
	_state(e)
	return e

## Everything the gate options show: {town, temper, tier, score, need, admit, toll, sells,
## bribe {price, odds}, vouchers [recs], pass {how, until}, late (fine on top for being
## inside without one), inside}.
func options(n: NPC) -> Dictionary:
	var e := gate_of(n)
	if e.is_empty():
		return {}
	var sid := String(e["sid"])
	var g: Dictionary = e["gate"]
	var tp: Dictionary = g.get("tp", GatePolicy.temper(e["site"], e["data"]))
	var hour := NPCMind.hour_now()
	var score := Game.town_standing(sid)
	var toll := GatePolicy.toll(tp, hour)
	var inside: bool = g.get("inside") == true
	return {"town": String(e["data"]["name"]), "temper": tp["label"], "tier": Game.town_tier(sid), "score": score,
		"need": GatePolicy.need(tp, not Game.guilds.is_empty(), bool(tp["night_shut"]) and GatePolicy.is_night(hour)),
		"admit": verdict(e), "toll": toll, "late": int(round(toll * GatePolicy.LATE_FINE)) if inside else 0, "inside": inside,
		"sells": GatePolicy.sells_pass(score, Game.crime.stars(sid, Game.day)), "bribe": GatePolicy.bribe(tp, n.rec, hour),
		"vouchers": GatePolicy.vouchers(e["data"]), "pass": Game.standing.pass_of(sid, Game.day), "days": float(tp["days"]),
		"writ": int(tp["toll"]) * WRIT_TOLLS if score >= WRIT_STANDING and Game.crime.stars(sid, Game.day) == 0 else 0}

## A writ of passage: the town's word, in writing, good at every walled town its word
## reaches, for some days. Sold by the watch to those it respects.
const WRIT_STANDING := 35
const WRIT_TOLLS := 3
const WRIT_DAYS := 7.0

func buy_writ(n: NPC) -> bool:
	var o := options(n)
	if o.is_empty() or int(o["writ"]) <= 0 or Game.money < int(o["writ"]):
		return false
	var e := gate_of(n)
	var c: Vector2 = e["site"]["center"]
	var w := ItemDB.make("writ", 1, 1.0, {"how": "bought", "sid": String(e["sid"]), "town": String(e["data"]["name"]),
		"x": c.x, "z": c.y, "until": Game.day + WRIT_DAYS})
	if not Game.inventory.add(w):
		return false
	Game.add_money(-int(o["writ"]))
	n.rec["purse"] = int(n.rec.get("purse", 0)) + int(o["writ"])
	_cleared(e)
	return true

## Pays the toll (and the fine for being found inside without it): a pass for some days.
func pay_toll(n: NPC) -> bool:
	var o := options(n)
	if o.is_empty() or not o["sells"]:
		return false
	var cost: int = int(o["toll"]) + int(o["late"])
	if Game.money < cost:
		return false
	var e := gate_of(n)
	var sid := String(e["sid"])
	Game.add_money(-cost)
	n.rec["purse"] = int(n.rec.get("purse", 0)) + cost
	Game.standing.give_pass(sid, Game.day + float(o["days"]), "toll")
	Game.standing_deed(sid, Standing.DEEDS["toll"])
	_cleared(e)
	return true

## Tries a bribe: true if the guard takes it (a pass), false if they refuse (a fine, and
## the town thinks less of you).
func try_bribe(n: NPC) -> bool:
	var o := options(n)
	if o.is_empty() or Game.money < int(o["bribe"]["price"]):
		return false
	var e := gate_of(n)
	var sid := String(e["sid"])
	if randf() < float(o["bribe"]["odds"]):
		var price: int = o["bribe"]["price"]
		Game.add_money(-price)
		n.rec["purse"] = int(n.rec.get("purse", 0)) + price
		NPCMind.change_rel(n.rec, 4)
		NPCMind.remember(n.rec, "Took a few Marks from the traveller to look the other way.")
		Game.standing.give_pass(sid, Game.day + float(o["days"]) * 0.5, "bribe", String(n.rec["id"]))
		_cleared(e)
		return true
	NPCMind.change_rel(n.rec, -20)
	Game.standing_deed(sid, Standing.DEEDS["bribe_refused"])
	manager.report_crime(n.global_position, "bribery", 0, "", n)
	return false

## A resident who likes you vouches for you: a pass, free, a day longer than a toll's.
func vouch(n: NPC, by: Dictionary) -> bool:
	var e := gate_of(n)
	if e.is_empty() or int(by.get("rel", 0)) < GatePolicy.VOUCH_REL or by.get("dead", false):
		return false
	var o := options(n)
	if Game.crime.stars(String(e["sid"]), Game.day) > 0:
		return false
	Game.standing.give_pass(String(e["sid"]), Game.day + float(o["days"]) + 1.0, "vouched", String(by["id"]))
	NPCMind.remember(by, "Vouched for the traveller at the gate.")
	_cleared(e)
	return true

## Leave given: the guard stands down.
func _cleared(e: Dictionary) -> void:
	var g: Dictionary = e["gate"]
	g["warned"] = false
	g["halted_t"] = _now()
	for o in e["nodes"]:
		if is_instance_valid(o) and NPCGen.GUARD_JOBS.has(String(o.rec["job"])) and Game.crime.stars(String(e["sid"]), Game.day) == 0:
			manager._overrides.erase(o.rec["id"])
			o.decide_in = 0.0
	manager.mark_dirty(e["data"])

# --- Word that reaches towns ------------------------------------------------------------------

## You broke the law in a town where someone vouched for you: they lose face.
func _on_betrayed(sid: String, by: String) -> void:
	for e in manager.settlements.values():
		if String(e.get("sid", "")) != sid:
			continue
		for rec in e["data"]["npcs"]:
			if String(rec["id"]) == by:
				NPCMind.change_rel(rec, -35)
				NPCMind.remember(rec, "I vouched for the traveller at the gate and they shamed me.")
				manager.mark_dirty(e["data"])

## Trade with a town's stalls and shops counts toward your standing there, a little a day.
func _on_traded(marks: int) -> void:
	if manager.player == null:
		return
	var e := manager.town_at(manager.player.global_position)
	if e.is_empty():
		return
	var sid := String(e["sid"])
	var today := int(floor(Game.day))
	var tr: Array = _trade.get(sid, [today, 0])
	if int(tr[0]) != today:
		tr = [today, 0]
	var before := int(tr[1]) / TRADE_PER
	tr[1] = int(tr[1]) + marks
	_trade[sid] = tr
	var gain := mini(int(tr[1]) / TRADE_PER, TRADE_DAY_CAP) - mini(before, TRADE_DAY_CAP)
	if gain > 0:
		_state(e)
		Game.standing_deed(sid, gain * Standing.DEEDS["trade"])

## An outlaw cut down: the nearest town you know of (within a day's walk) is grateful.
func outlaw_slain(at: Vector3) -> void:
	var best := ""
	var bd := 900.0
	var pre := "%d:" % Game.planet
	for sid in Game.standing.towns:
		if not String(sid).begins_with(pre):
			continue
		var t: Dictionary = Game.standing.towns[sid]
		var d := Vector2(float(t["x"]), float(t["z"])).distance_to(Vector2(at.x, at.z))
		if d < bd:
			bd = d
			best = sid
	if best != "":
		Game.standing_deed(best, Standing.DEEDS["outlaw"])

## Your standing tier in this person's town ("" outside any town).
func tier_for(n: NPC) -> String:
	var e := manager._entry_of(n.settlement)
	if e.is_empty() or not e.has("sid") or n.settlement.has("band"):
		return ""
	_state(e)
	return Game.town_tier(String(e["sid"]))

## A deed in this person's town (guild joined, house bought...): Standing.DEEDS key.
func deed_for(n: NPC, kind: String) -> void:
	var e := manager._entry_of(n.settlement)
	if e.is_empty() or not e.has("sid"):
		return
	_state(e)
	Game.standing_deed(String(e["sid"]), Standing.DEEDS[kind])

# --- Night gates: the portcullis ---------------------------------------------------------------

## How far the portcullis drops below its raised place (the gateway's bars hang from 3.1 m).
const PORT_DROP := 3.1
## Metres a second it falls or is wound up.
const PORT_SPEED := 1.4
var _ports := {} ## sid -> [{node: Node3D, lift: Node3D, body: CollisionShape3D, up: float 0 (down)..1}]
static var _port_mesh: ArrayMesh

## Raises or lowers each town's portcullises toward where they stand for you now, and
## lets go of those of towns gone out of reach.
func _move_ports(delta: float) -> void:
	if manager == null:
		return
	var live := {}
	for e in manager.settlements.values():
		if e.has("gate") and e.has("sid") and not (e["gate"]["gates"] as Array).is_empty():
			live[String(e["sid"])] = e
	_place_posterns(live)
	for sid in _ports.keys():
		if not live.has(sid):
			for pt in _ports[sid]:
				if is_instance_valid(pt["node"]):
					pt["node"].queue_free()
			_ports.erase(sid)
	for sid in live:
		var e: Dictionary = live[sid]
		var shut: bool = e["gate"].get("shut", false)
		if not _ports.has(sid):
			if not shut:
				continue # made the first time one has to come down
			if not _make_ports(e):
				continue
		for pt in _ports[sid]:
			var up := move_toward(float(pt["up"]), 0.0 if shut else 1.0, delta * PORT_SPEED / PORT_DROP)
			if up == float(pt["up"]):
				continue
			pt["up"] = up
			(pt["lift"] as Node3D).position.y = up * PORT_DROP
			(pt["lift"] as Node3D).visible = up < 0.97
			# It bars the way until it is above head height.
			(pt["body"] as CollisionShape3D).disabled = up > 0.6

## Makes the portcullises in a town's gateways (once their chunks are in), raised.
func _make_ports(e: Dictionary) -> bool:
	var out: Array = []
	for q in e["gate"]["gates"]:
		var xf = _gate_xf(q)
		if xf == null:
			return false # its chunk isn't in yet
		if xf is Transform3D:
			out.append(_make_port(xf))
	_ports[String(e["sid"])] = out
	return true

## Where the gateway at `q` stands (its object in the chunk), null while its chunk isn't
## loaded, or false when it is gone.
func _gate_xf(q: Vector2):
	if manager.streamer == null:
		return null
	var c := manager.streamer.get_chunk(ChunkStreamer.chunk_of(Vector3(q.x, 0.0, q.y)))
	if c == null:
		return null
	for o in c.data["objects"]:
		if o["t"] == "castle_gate" and not o["st"].get("gone", false):
			var wp: Vector3 = c.position + (o["p"] as Vector3)
			if Vector2(wp.x, wp.z).distance_to(q) < 1.0:
				return Transform3D(Basis(Vector3.UP, float(o["r"])), wp)
	return false

func _make_port(xf: Transform3D) -> Dictionary:
	var node := Node3D.new()
	node.transform = xf
	add_child(node)
	var lift := Node3D.new()
	lift.position.y = PORT_DROP
	lift.visible = false
	node.add_child(lift)
	var mi := MeshInstance3D.new()
	mi.mesh = port_mesh()
	lift.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, PORT_DROP, 0.3)
	cs.shape = box
	cs.position = Vector3(0.0, PORT_DROP * 0.5, 0.12)
	cs.disabled = true
	body.add_child(cs)
	node.add_child(body)
	return {"node": node, "lift": lift, "body": cs, "up": 1.0}

## The lower part of a castle gateway's portcullis (its top hangs in the gateway's own
## mesh, Stronghold._gateway): the same iron bars carried down to the ground, cross-bars
## and pointed teeth that bite into the road.
static func port_mesh() -> ArrayMesh:
	if _port_mesh != null:
		return _port_mesh
	var k := MeshKit.new(4117)
	var I := Transform3D.IDENTITY
	var x := -1.8
	while x <= 1.81:
		k.box("iron", I.translated(Vector3(x, 0.15 + PORT_DROP * 0.5, 0.125)), Vector3(0.07, PORT_DROP - 0.3, 0.07))
		k.cylinder("iron", I.translated(Vector3(x, 0.0, 0.125)), 0.006, 0.045, 0.3, 5)
		x += 0.3
	for y: float in [0.55, 1.35, 2.15, 2.9]:
		k.box("iron", I.translated(Vector3(0, y, 0.125)), Vector3(3.75, 0.06, 0.06))
	_port_mesh = k.commit(Materials.get_mat)
	return _port_mesh

## Whether the portcullis of this town is down for you (for the tests and the HUD).
func gate_shut(sid: String) -> bool:
	if not _ports.has(sid):
		return false
	for pt in _ports[sid]:
		if float(pt["up"]) < 0.4:
			return true
	return false

# --- Over the wall with a rope ------------------------------------------------------------------

## Rope it takes (left hanging on the wall).
const CLIMB_ROPE := 2
const CLIMB_SECONDS := 3.4
## A grappling hook gets you over without leaving rope, and quicker.
const HOOK := "grappling_hook"
const HOOK_SECONDS := 2.6
## How far from a gate the wall can be climbed (the gate is watched; the towers are in the way).
const CLIMB_CLEAR := 9.0
var _climb := {} ## {path: [Vector3], t, e, seen: NPC or null, inward}

## What you can do at a town wall from `pos`: [{node, n, at, verb}] like Dungeons.usables.
func usables(pos: Vector3) -> Array:
	if not _climb.is_empty() or manager == null:
		return []
	var door := _postern_use(pos)
	if not door.is_empty():
		return door
	var p2 := Vector2(pos.x, pos.z)
	for e in manager.settlements.values():
		if not e.has("gate") or (e["gate"]["gates"] as Array).is_empty():
			continue
		var site: Dictionary = e["site"]
		var c: Vector2 = site["center"]
		var rad := float(site["inner"]) + 2.5
		var d := p2.distance_to(c)
		if absf(d - rad) > 3.5 or absf(d - rad) < 0.4:
			continue
		var near_gate := false
		for q in e["gate"]["gates"]:
			if (q as Vector2).distance_to(p2) < CLIMB_CLEAR:
				near_gate = true
		if near_gate:
			continue
		var dir := (p2 - c).normalized()
		var w := c + dir * rad
		var have := Game.inventory.count("rope")
		var verb := ("Climb over the wall (%d rope)" if have >= CLIMB_ROPE else "Climb over the wall (needs %d rope)") % CLIMB_ROPE
		if Game.inventory.count(HOOK) > 0:
			verb = "Climb over the wall (grappling hook)"
		return [{"node": self, "n": String(e["sid"]), "at": Vector3(w.x, pos.y + 1.4, w.y), "verb": verb}]
	return []

## Throws a rope over the wall and climbs it: up the face, over the wall walk and down
## the other side. Climbing in without leave is trespass if a guard sees you.
func use(sid: String, player: Node3D) -> void:
	if not _climb.is_empty():
		return
	if sid.begins_with("postern:"):
		_use_postern(sid.trim_prefix("postern:"), player)
		return
	var e := {}
	for x in manager.settlements.values():
		if String(x.get("sid", "")) == sid:
			e = x
	if e.is_empty():
		return
	var hook := Game.inventory.count(HOOK) > 0
	if not hook and Game.inventory.count("rope") < CLIMB_ROPE:
		Game.toast.emit("You need %d rope or a grappling hook to get over the wall" % CLIMB_ROPE)
		return
	var site: Dictionary = e["site"]
	var c: Vector2 = site["center"]
	var rad := float(site["inner"]) + 2.5
	var from: Vector3 = player.global_position
	var dir := (Vector2(from.x, from.z) - c).normalized()
	var inward := Vector2(from.x, from.z).distance_to(c) > rad
	var near_side := c + dir * (rad + (1.6 if inward else -2.2))
	var far_side := c + dir * (rad + (-2.6 if inward else 2.4))
	var wall := c + dir * rad
	# The top of the wall walk: straight down onto the wall from well above.
	var top := from.y + 7.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(wall.x, from.y + 30.0, wall.y), Vector3(wall.x, from.y - 4.0, wall.y), 1)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		top = (hit["position"] as Vector3).y
	var land := manager.ground(far_side.x, far_side.y)
	if is_nan(land):
		land = from.y
	if not hook:
		Game.inventory.remove_type("rope", CLIMB_ROPE)
	var seen := _seen_by(e, from, 38.0, 0.12)
	_climb = {"e": e, "t": 0.0, "inward": inward, "seen": seen, "player": player, "secs": HOOK_SECONDS if hook else CLIMB_SECONDS,
		"path": [from, Vector3(near_side.x, from.y + 0.2, near_side.y), Vector3(near_side.x, top + 0.3, near_side.y),
			Vector3(far_side.x, top + 0.3, far_side.y), Vector3(far_side.x, land + 0.1, far_side.y)]}
	player.set("script_move", true)
	if not hook:
		_hang_rope(Vector3(near_side.x, top, near_side.y), from.y) # a hook comes down with you
	Game.practice("sneak", 2.0)
	Audio.play("weapon/draw", -8.0)

## Steps the climb along its path; at the end you stand on the far side.
func _climb_step(delta: float) -> void:
	if _climb.is_empty():
		return
	var pl = _climb["player"]
	if not is_instance_valid(pl):
		_climb = {}
		return
	_climb["t"] = float(_climb["t"]) + delta / float(_climb.get("secs", CLIMB_SECONDS))
	var t: float = minf(float(_climb["t"]), 1.0)
	var path: Array = _climb["path"]
	# Time per leg: a step to the wall, the long haul up, across the top, down the far side
	# (or through a postern: up to the door, and through).
	var legs: Array = _climb.get("legs", [0.08, 0.5, 0.17, 0.25])
	var acc := 0.0
	var at: Vector3 = path[-1]
	for i in legs.size():
		if t <= acc + float(legs[i]):
			at = (path[i] as Vector3).lerp(path[i + 1], smoothstep(0.0, 1.0, (t - acc) / float(legs[i])))
			break
		acc += float(legs[i])
	pl.global_position = at
	if pl is CharacterBody3D:
		(pl as CharacterBody3D).velocity = Vector3.ZERO
	if t < 1.0:
		return
	pl.set("script_move", false)
	if _climb.get("door", false):
		_climb = {}
		return # coming in by the postern is like slipping in at the gate: the watch sees to it
	var e: Dictionary = _climb["e"]
	var seen = _climb["seen"]
	var inward: bool = _climb["inward"]
	_climb = {}
	var g: Dictionary = e["gate"]
	g["inside"] = inward
	if inward and not verdict(e)["ok"]:
		if seen != null and is_instance_valid(seen):
			_trespass(e, pl.global_position, seen)
			Game.standing_deed(String(e["sid"]), Standing.DEEDS["trespass"]) # scaling the walls is worse than walking in
		else:
			Game.toast.emit("Over the wall into %s, unseen. Guards who don't know you will ask for your pass." % e["data"]["name"])
	elif not inward:
		g["warned"] = false

## The rope left hanging down the wall: there for a while, then someone hauls it in.
func _hang_rope(top: Vector3, foot: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var len := maxf(1.0, top.y - foot)
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = len
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = _rope_mat()
	add_child(mi)
	mi.global_position = Vector3(top.x, foot + len * 0.5, top.z)
	get_tree().create_timer(90.0).timeout.connect(mi.queue_free)

static var _rope: StandardMaterial3D
static func _rope_mat() -> StandardMaterial3D:
	if _rope == null:
		_rope = StandardMaterial3D.new()
		_rope.albedo_color = Color(0.62, 0.5, 0.33)
		_rope.roughness = 0.95
	return _rope

# --- The postern: a small locked door in the wall ----------------------------------------------

## How near the postern's door you must be to use it.
const POSTERN_R := 2.4
## Seconds to step through the wall.
const POSTERN_SECONDS := 1.1
var _posterns := {} ## sid -> {node: Node3D, open: bool}

## The postern of a walled town: the stretch of wall furthest round from its gates.
## {p: Vector2 (the wall section's middle), yaw (its outer face's), tier (lock 1..3)} or {}.
func postern(e: Dictionary) -> Dictionary:
	var g := _state(e)
	if g.has("postern"):
		return g["postern"]
	if (g["gates"] as Array).is_empty() or not GatePolicy.is_walled(e["site"]):
		return {}
	var c: Vector2 = e["site"]["center"]
	var best := {}
	var far := -1.0
	for it in manager.gen.settlement_layout(e["site"]):
		if it["t"] != "castle_wall":
			continue
		var a := (it["p"] as Vector2 - c).angle()
		var near := TAU
		for q in g["gates"]:
			near = minf(near, absf(angle_difference(a, (q as Vector2 - c).angle())))
		if near > far:
			far = near
			best = {"p": it["p"], "yaw": float(it["yaw"])}
	if not best.is_empty():
		best["tier"] = postern_tier(GatePolicy.temper(e["site"], e["data"]))
	g["postern"] = best
	return best

## The postern's lock by how strict the town is: Novice, Adept or Master (LockGame).
static func postern_tier(tp: Dictionary) -> int:
	var s := float(tp["strict"])
	return 1 + (1 if s >= 0.4 else 0) + (1 if s >= 0.7 else 0)

## Where you stand to use the postern from outside (true) or inside (false).
static func postern_side(pt: Dictionary, outside: bool) -> Vector2:
	var out := Vector2(sin(float(pt["yaw"])), cos(float(pt["yaw"])))
	return (pt["p"] as Vector2) + out * (1.5 if outside else -1.7)

func _postern_at(pos: Vector3) -> Array:
	var p2 := Vector2(pos.x, pos.z)
	for e in manager.settlements.values():
		if not e.has("gate") or not e.has("sid") or (e["gate"]["gates"] as Array).is_empty():
			continue
		var pt := postern(e)
		if pt.is_empty() or p2.distance_to(pt["p"]) > POSTERN_R + 2.0:
			continue
		for outside in [true, false]:
			if p2.distance_to(postern_side(pt, outside)) < POSTERN_R:
				return [e, pt, outside]
	return []

## What the postern offers from here: [{node, n, at, verb}], or [].
func _postern_use(pos: Vector3) -> Array:
	var hit := _postern_at(pos)
	if hit.is_empty():
		return []
	var e: Dictionary = hit[0]
	var pt: Dictionary = hit[1]
	var outside: bool = hit[2]
	var open := bool(_posterns.get(String(e["sid"]), {}).get("open", false))
	var verb := "Go through the postern"
	if outside and not open:
		verb = "Pick the postern's lock (%s)" % LockGame.TIERS[int(pt["tier"])] if Game.inventory.count(LockpickUI.PICK_ITEM) > 0 \
			else "Postern door (locked: needs a lockpick)"
		if has_keys(String(e["sid"])):
			verb = "Unlock the postern (the watch's keys)"
	elif not outside and not open:
		verb = "Unbar the postern and slip out"
	var at := pos
	var g := manager.ground(float(pt["p"].x), float(pt["p"].y))
	at = Vector3(pt["p"].x, (pos.y if is_nan(g) else g) + 1.1, pt["p"].y)
	return [{"node": self, "n": "postern:" + String(e["sid"]), "at": at, "verb": verb}]

## Uses the postern from where the player stands: pick the lock from outside (then step
## through), unbar it from inside, or walk through once it's open. Coming in this way
## without leave is the same as slipping in at the gate: trespass if a guard sees you.
func _use_postern(sid: String, player: Node3D) -> void:
	var hit := _postern_at(player.global_position)
	if hit.is_empty() or String(hit[0]["sid"]) != sid:
		return
	var pt: Dictionary = hit[1]
	var outside: bool = hit[2]
	if not _posterns.has(sid):
		_posterns[sid] = {"node": null, "open": false}
	var st: Dictionary = _posterns[sid]
	if bool(st["open"]) or not outside:
		st["open"] = true
		_through(hit[0], pt, outside, player)
		return
	if has_keys(sid):
		Game.toast.emit("One of the watch's keys turns the postern's lock")
		Audio.play("door/lock", -6.0)
		st["open"] = true
		_through(hit[0], pt, outside, player)
		return
	var at := Vector3(pt["p"].x, player.global_position.y, pt["p"].y)
	var seed_ := absi(hash(sid + "postern"))
	get_tree().call_group("lockpick_ui", "open_custom", int(pt["tier"]), seed_, at, func() -> void:
		st["open"] = true
		_through(hit[0], pt, true, player))

## Steps through the postern, from one side of the wall to the other.
func _through(e: Dictionary, pt: Dictionary, outside: bool, player: Node3D) -> void:
	if not _climb.is_empty() or not is_instance_valid(player):
		return
	var a := postern_side(pt, outside)
	var b := postern_side(pt, not outside)
	var y0: float = player.global_position.y
	var y1 := manager.ground(b.x, b.y)
	if is_nan(y1):
		y1 = y0
	var from: Vector3 = player.global_position
	_climb = {"e": e, "t": 0.0, "inward": outside, "seen": null, "player": player, "secs": POSTERN_SECONDS, "door": true,
		"legs": [0.3, 0.7], "path": [from, Vector3(a.x, y0, a.y), Vector3(b.x, y1 + 0.05, b.y)]}
	player.set("script_move", true)
	Audio.play("door/open", -6.0)

## Puts the postern doors of the towns about into the wall (once their ground is in), and
## takes away those of towns gone out of reach.
func _place_posterns(live: Dictionary) -> void:
	for sid in _posterns.keys():
		if not live.has(sid):
			if is_instance_valid(_posterns[sid]["node"]):
				_posterns[sid]["node"].queue_free()
			_posterns.erase(sid)
	for sid in live:
		if _posterns.has(sid) and is_instance_valid(_posterns[sid]["node"]):
			continue
		var pt := postern(live[sid])
		if pt.is_empty():
			continue
		var y := manager.ground(float(pt["p"].x), float(pt["p"].y))
		if is_nan(y):
			continue
		var node := MeshInstance3D.new()
		node.mesh = postern_mesh()
		add_child(node)
		node.global_transform = Transform3D(Basis(Vector3.UP, float(pt["yaw"])), Vector3(pt["p"].x, y, pt["p"].y))
		if not _posterns.has(sid):
			_posterns[sid] = {"node": node, "open": false}
		else:
			_posterns[sid]["node"] = node

static var _postern_mesh: ArrayMesh
## A low arched oak door with iron straps, in a frame of dressed stone, on the wall's
## outer face; the same door (barred) on the inner face. Local +z is out of town.
static func postern_mesh() -> ArrayMesh:
	if _postern_mesh != null:
		return _postern_mesh
	var k := MeshKit.new(4121)
	var I := Transform3D.IDENTITY
	for side: float in [1.0, -1.0]:
		var z := 0.76 * side
		var r := Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
		var X := func(v: Vector3) -> Transform3D: return Transform3D(r, Vector3(v.x * side, v.y, z + v.z * side))
		k.box("planks", X.call(Vector3(0, 1.0, 0.02)), Vector3(1.0, 2.0, 0.08), Color(0.62, 0.5, 0.4))
		for y: float in [0.35, 1.0, 1.65]:
			k.box("iron", X.call(Vector3(0, y, 0.07)), Vector3(1.0, 0.07, 0.02))
		k.box("iron", X.call(Vector3(0.36 * side, 1.05, 0.08)), Vector3(0.08, 0.08, 0.04)) # the lock plate
		# Dressed stone round it: jambs, a lintel and its relieving arch.
		for x: float in [-0.66, 0.66]:
			k.box("castle_stone", X.call(Vector3(x, 1.12, 0.08)), Vector3(0.32, 2.24, 0.16))
		k.box("castle_stone", X.call(Vector3(0, 2.36, 0.08)), Vector3(1.64, 0.3, 0.18))
		k.box("castle_stone", X.call(Vector3(0, 2.64, 0.06)), Vector3(1.2, 0.26, 0.14))
		if side < 0.0:
			k.box("planks", X.call(Vector3(0, 1.1, 0.1)), Vector3(1.3, 0.14, 0.1), Color(0.5, 0.4, 0.32)) # the bar
	_postern_mesh = k.commit(Materials.get_mat)
	return _postern_mesh

## Whether you carry this town's watch keys (lifted from one of its guards).
static func has_keys(sid: String) -> bool:
	for it in Game.inventory.slots:
		if it is Dictionary and it["type"] == "watch_keys" and String((it.get("origin", {}) as Dictionary).get("sid", "")) == sid:
			return true
	return false

# --- Disguised as the watch ---------------------------------------------------------------------

## The tabard of the town watch, worn: guards who don't know your face take you for one of theirs.
const TABARD := "watch_tabard"
## Seconds between looks from the watch inside town while you're in their colours.
const LOOK_EVERY := 45.0

## Whether you are passing as one of this town's watch (in its tabard, not yet found out today).
func disguised(e: Dictionary) -> bool:
	var it = Game.equipment.get("back")
	if not it is Dictionary or it["type"] != TABARD:
		return false
	return float(e.get("gate", {}).get("unmasked", -1.0)) < Game.day

## The odds a guard sees through the tabard: the stricter the town, the sharper the watch;
## by night it's harder to tell. A guard who knows your face isn't fooled.
static func see_through_odds(tp: Dictionary, guard_rel: int, night: bool) -> float:
	if guard_rel >= GatePolicy.KNOWS_REL:
		return 1.0
	return clampf(0.12 + float(tp["strict"]) * 0.4 - (0.1 if night else 0.0), 0.05, 0.9)

## A guard at the gate (or, now and then, inside) gives you a look. True if they saw
## through the disguise: posing as the watch is a crime, and you're unmasked there till tomorrow.
func _seen_through(e: Dictionary, gate: Vector2, gd: float, inside: bool, pp: Vector3, t: float) -> bool:
	var g: Dictionary = e["gate"]
	var guard: NPC = null
	if not inside and gd < HALT_R * 0.8 and not g["welcomed"]:
		guard = _gate_guard(e, gate, pp)
		if guard != null and guard.global_position.distance_to(pp) > 16.0:
			guard = null
	elif inside and t - float(g.get("looked_t", -999.0)) > LOOK_EVERY:
		guard = _seen_by(e, pp, ASK_R, 0.45)
		if guard != null:
			g["looked_t"] = t
	if guard == null:
		return false
	var odds := see_through_odds(g["tp"], int(guard.rec.get("rel", 0)), GatePolicy.is_night(NPCMind.hour_now()))
	if inside:
		odds *= 0.5
	if randf() >= odds:
		return false
	g["unmasked"] = Game.day + 1.0
	g["welcomed"] = false
	manager.report_crime(pp, "impersonation", 0, "", guard)
	Game.standing_deed(String(e["sid"]), DISGUISE_DEED)
	Game.toast.emit("A guard saw through your tabard: posing as the watch of %s is a crime." % e["data"]["name"])
	return true

const DISGUISE_DEED := -10

## A writ of passage you carry, good at this town: issued by a town whose word reaches it,
## and not yet run out.
static func has_writ(sid: String, center: Vector2) -> bool:
	for it in Game.inventory.slots:
		if not it is Dictionary or it["type"] != "writ":
			continue
		var o: Dictionary = it.get("origin", {})
		if float(o.get("until", 0.0)) < Game.day or String(o.get("sid", "")).get_slice(":", 0) != sid.get_slice(":", 0):
			continue
		if Vector2(float(o.get("x", 0.0)), float(o.get("z", 0.0))).distance_to(center) <= Standing.WORD_REACH:
			return true
	return false
