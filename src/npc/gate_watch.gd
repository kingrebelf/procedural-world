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
## Runs on each player's own game with their own standing, so it works the same online.

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
	if v["ok"]:
		if not inside and gd < HALT_R * 0.8 and not g["welcomed"]:
			var guard := _gate_guard(e, gate, pp)
			if guard != null and guard.global_position.distance_to(pp) < 16.0:
				g["welcomed"] = true
				manager._bark(guard, GatePolicy.welcome_line(v["why"], Game.town_tier(sid)), guard.global_position.distance_to(pp))
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
	return GatePolicy.admit(g["tp"], Game.town_standing(sid), Game.is_citizen(sid), not Game.guilds.is_empty(),
		Game.crime.stars(sid, Game.day), Game.standing.has_pass(sid, Game.day), NPCMind.hour_now())

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
		"vouchers": GatePolicy.vouchers(e["data"]), "pass": Game.standing.pass_of(sid, Game.day), "days": float(tp["days"])}

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

## A deed in this person's town (guild joined, house bought...): Standing.DEEDS key.
func deed_for(n: NPC, kind: String) -> void:
	var e := manager._entry_of(n.settlement)
	if e.is_empty() or not e.has("sid"):
		return
	_state(e)
	Game.standing_deed(String(e["sid"]), Standing.DEEDS[kind])
