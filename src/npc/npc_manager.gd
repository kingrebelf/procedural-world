class_name NPCManager
extends Node3D
## Brings settlements' people to life around the player. Loads each settlement's
## persisted record when the player comes near, runs every NPC's mind (built-in utility
## AI, plus the external decision service and the language model when configured), and
## saves them back. People who are far away are frozen exactly as they were and caught up
## to the time of day when the player returns.

const LOAD_R := 170.0
const UNLOAD_R := 240.0
const SAVE_EVERY := 12.0
const DECIDE_EVERY := 2.0
const THINK_RANGE := 45.0

var streamer: ChunkStreamer
var player: Node3D
var gen: ChunkGenerator
var settlements: Dictionary = {} ## id -> {data, nodes: Array, dirty: bool}

var _by_id: Dictionary = {}
var _overrides: Dictionary = {} ## npc id -> {action, until}
var _scan_t := 0.0
var _save_t := 0.0
var _decide_t := 0.0
var _think_t := 0.0
var _deciding := false
var _thinking := false
var _ground := Callable(self, "ground")

func _ready() -> void:
	gen = ChunkGenerator.new(Game.seed)
	Game.saving.connect(save_all)
	add_to_group("npc_manager")

func _exit_tree() -> void:
	save_all()

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func ground(x: float, z: float) -> float:
	if streamer == null:
		return NAN
	var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
	var c := streamer.get_chunk(k)
	if c == null:
		return NAN
	return ChunkGenerator.height_at(c.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE)

func all_nodes() -> Array:
	var out: Array = []
	for s in settlements.values():
		out.append_array(s["nodes"])
	return out

func settlement_of(n: NPC) -> Dictionary:
	return n.settlement

## The generator's site record (center, era, size...) of the settlement n lives in.
func site_of(n: NPC) -> Dictionary:
	var e = settlements.get(NPCGen.settlement_id(n.settlement["sx"], n.settlement["sz"]))
	if e != null:
		return e["site"]
	return gen.settlement_at(n.settlement["sx"], n.settlement["sz"])

## You bought a house in site: whoever lived there moves out, and it gets your sign.
func houses_changed(site: Dictionary) -> void:
	var e = settlements.get(NPCGen.settlement_id(site["sx"], site["sz"]))
	if e == null:
		return
	TownShops.rehome(gen, site, e["data"], Game.estates)
	e["dirty"] = true
	e["decor"].estates = Game.estates
	e["decor"].refresh()

func mark_dirty(s: Dictionary) -> void:
	var e = settlements.get(NPCGen.settlement_id(s["sx"], s["sz"]))
	if e != null:
		e["dirty"] = true

# --- Loading ----------------------------------------------------------------------------

func _scan() -> void:
	if Game.store == null or player == null:
		return
	var p := player.global_position
	var near := gen.settlements_near(p.x - LOAD_R, p.z - LOAD_R, p.x + LOAD_R, p.z + LOAD_R)
	for site in near:
		var c: Vector2 = site["center"]
		var id := NPCGen.settlement_id(site["sx"], site["sz"])
		if settlements.has(id) or c.distance_to(Vector2(p.x, p.z)) > LOAD_R:
			continue
		_load(site, id)
	for id in settlements.keys():
		var e: Dictionary = settlements[id]
		var c: Vector2 = e["data"]["center"]
		if c.distance_to(Vector2(p.x, p.z)) < UNLOAD_R:
			continue
		var keep := false
		for n in e["nodes"]:
			if n.action == "follow" and n.global_position.distance_to(p) < 60.0:
				keep = true
		if not keep:
			_unload(id)

func _load(site: Dictionary, id: String) -> void:
	var data := Game.store.get_or_create_settlement(gen, site)
	# Shops need keepers (hired once, on the first visit since shops came in).
	var hired := TownShops.staff(gen, site, data)
	TownShops.rehome(gen, site, data, Game.estates)
	if hired:
		Game.store.save_settlement(data)
	var e := {"data": data, "nodes": [], "dirty": false, "site": site}
	settlements[id] = e
	var decor := TownDecor.new()
	decor.setup(gen, streamer, site, data, Game.estates)
	add_child(decor)
	e["decor"] = decor
	var stale: bool = float(data.get("sim_day", -1.0)) < 0.0 or Game.day - float(data["sim_day"]) > 0.03
	var hour := NPCMind.hour_now()
	for rec in data["npcs"]:
		if rec.get("dead", false):
			continue
		if stale:
			_catch_up(rec, data, hour)
		var n := NPC.new()
		n.setup(rec, data, self)
		n.think_at = now() + randf() * float(AI.get_value("think_interval"))
		add_child(n)
		e["nodes"].append(n)
		_by_id[rec["id"]] = n

## Where someone would be at this hour if they had been living their day unobserved.
func _catch_up(rec: Dictionary, data: Dictionary, hour: float) -> void:
	var at: Vector2
	if hour >= 21.5 or hour < 6.0:
		at = rec["home"]
	elif hour >= 8.0 and hour < 18.0 or (rec["job"] == "trader" or rec.has("shop_kind")) and hour >= 7.0 and hour < 20.0:
		at = rec["work"]
	else:
		var c: Vector2 = data["center"]
		var a := float(hash(rec["id"]) % 628) / 100.0
		at = c + Vector2(cos(a), sin(a)) * 5.0
	rec["pos"] = Vector3(at.x, gen.field.height(at.x, at.y), at.y)
	rec["energy"] = clampf(float(rec.get("energy", 1.0)) + 0.3, 0.0, 1.0)

func _unload(id: String) -> void:
	var e: Dictionary = settlements[id]
	e["data"]["sim_day"] = Game.day
	Game.store.save_settlement(e["data"])
	for n in e["nodes"]:
		_by_id.erase(n.rec["id"])
		n.queue_free()
	if is_instance_valid(e.get("decor")):
		e["decor"].queue_free()
	settlements.erase(id)

func save_all() -> void:
	if Game.store == null:
		return
	for e in settlements.values():
		e["data"]["sim_day"] = Game.day
		Game.store.save_settlement(e["data"])
		e["dirty"] = false

# --- Minds ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or Game.store == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_scan()
	var pp := player.global_position
	var t := now()
	for e in settlements.values():
		for n in e["nodes"]:
			if not is_instance_valid(n):
				continue
			n.decide_in -= delta
			if n.decide_in <= 0.0:
				n.decide_in = randf_range(1.2, 2.4)
				_decide(n, e, pp, t)
			n.step(delta, _ground, pp, e["nodes"])
			n.show_name(pp.distance_to(n.global_position) < 7.0 and not n.is_hidden())
			if n.action == "attack" and n.attack_cd <= 0.0 and pp.distance_to(n.global_position) < 1.7:
				n.attack_cd = 1.4
				var dmg := 6.0 + float(n.rec["traits"]["brave"]) * 6.0
				var took := Game.hurt(dmg, "Killed by %s" % n.rec["name"], func(back: float): player_hit(n, back))
				Game.toast.emit("%s hits you (-%d)" % [n.rec["name"].split(" ")[0], int(ceilf(took))])
	_decide_t -= delta
	if _decide_t <= 0.0:
		_decide_t = DECIDE_EVERY
		if AI.decide_enabled() and not _deciding:
			_external_decide(pp)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 3.0
		if AI.thinking_enabled() and not _thinking:
			_background_think(pp)
	_save_t += delta
	if _save_t >= SAVE_EVERY:
		_save_t = 0.0
		for e in settlements.values():
			if e["dirty"]:
				e["data"]["sim_day"] = Game.day
				Game.store.save_settlement(e["data"])
				e["dirty"] = false

func perception(n: NPC, e: Dictionary, pp: Vector3, t: float) -> Dictionary:
	var held = Game.inventory.get_slot(player.selected) if player.has_method("held_item") else null
	var armed: bool = held != null and ItemDB.def(held["type"]).get("kind", "") == "weapon"
	var pos := Vector2(n.global_position.x, n.global_position.z)
	return {
		"hour": NPCMind.hour_now(), "pos": pos, "center": e["data"]["center"],
		"noise": float(absi(hash(n.rec["id"] + str(int(t / 20.0)))) % 1000) / 1000.0,
		"player_dist": n.global_position.distance_to(pp), "player_pos": Vector2(pp.x, pp.z),
		"player_armed": armed, "override": _overrides.get(n.rec["id"]), "now": t, "day": NPCMind.day_num(),
	}

func _decide(n: NPC, e: Dictionary, pp: Vector3, t: float) -> void:
	if n.talking:
		return
	var rec := n.rec
	var per := perception(n, e, pp, t)
	if per["player_dist"] > 30.0:
		rec["greeted"] = false
	var d := DecisionEngine.decide(rec, per)
	var prev := n.action
	n.action = d["action"]
	n.target = d.get("target", Vector2.INF)
	n.target_player = d.has("target_player")
	rec["_action"] = n.action
	var dist: float = per["player_dist"]
	if n.action != prev:
		# Ambient performances end when the person moves on to something else.
		if n.ambient and n.is_performing():
			n.stop_perform()
		match n.action:
			"greet":
				rec["greeted"] = true
				if NPCSocial.overdue(rec):
					_bark(n, "Oi! You still owe me %d Marks." % rec["debt"], dist)
					n.act("beckon")
					if int(rec.get("debt_noticed", -1)) != NPCMind.day_num():
						rec["debt_noticed"] = NPCMind.day_num()
						NPCMind.change_rel(rec, -5)
						NPCMind.remember(rec, "The traveller is late paying back my loan.")
				else:
					_bark(n, NPCMind.bark(rec, "greet"), dist)
					var t2: Dictionary = rec["traits"]
					if int(rec.get("rel", 0)) > 25 and float(t2["friendly"]) > 0.65 and float(t2["curious"]) > 0.55 and randf() < 0.35:
						n.act("wink")
					else:
						n.act(["wave", "wave", "nod", "salute" if NPCGen.GUARD_JOBS.has(rec["job"]) else "wave"][randi() % 4])
			"confront", "attack", "flee":
				_bark(n, NPCMind.bark(rec, n.action), dist)
				if n.action == "confront":
					n.act("point" if float(rec["traits"]["brave"]) < 0.7 else "fist")
	# Dancing in the square and sitting down start once they get there.
	if not n.is_performing() and n.target != Vector2.INF:
		var here := Vector2(n.global_position.x, n.global_position.z).distance_to(n.target) < 1.6
		if n.action == "dance" and here:
			n.act("dance", randf_range(15.0, 30.0))
			n.ambient = true
		elif n.action == "sit":
			n.act("sit", randf_range(20.0, 45.0))
			n.ambient = true
	# Chatting with neighbours comes with hands.
	if n.action == "socialize" and not n.is_performing() and randf() < 0.18:
		n.act(["nod", "shrug", "think", "point", "tilt", "shake_head", "clap", "hips"][randi() % 8])
	if n.action == "gift" and dist < 2.6:
		_give_gift(n)
	# Needs drift: sleep restores energy, company restores sociability.
	var sleeping: bool = n.action == "sleep" and n.is_hidden()
	rec["energy"] = clampf(float(rec.get("energy", 1.0)) + (0.02 if sleeping else -0.002), 0.0, 1.0)
	rec["social"] = clampf(float(rec.get("social", 0.5)) + (0.03 if n.action == "socialize" else -0.003), 0.0, 1.0)
	e["dirty"] = true

## A line said out loud: shown above their head, and spoken if passers-by have voices.
func _bark(n: NPC, line: String, dist: float) -> void:
	if line == "":
		return
	n.say(line)
	if AI.get_value("voice_barks"):
		Voice.speak(n.rec, line, dist, false)

## Someone fond of you hands over a little present.
func _give_gift(n: NPC) -> void:
	var rec := n.rec
	if int(rec.get("gift_day", -1)) == NPCMind.day_num():
		return
	rec["gift_day"] = NPCMind.day_num()
	var g := NPCSocial.gift_for(rec)
	var first: String = rec["name"].split(" ")[0]
	var what := ""
	if g.has("item") and Game.give(g["item"]):
		what = ItemDB.display_name(g["item"])
	elif g.has("marks"):
		var m := NPCSocial.hand_over(rec, int(g["marks"]), "beg")
		if m <= 0:
			return
		Game.add_money(m)
		what = "%d Marks" % m
	if what == "":
		return
	NPCMind.remember(rec, "Gave the traveller a present: %s." % what)
	_bark(n, ["Here, I wanted you to have this.", "A little something for you, friend.", "Saw this and thought of you."][randi() % 3], 2.0)
	n.act("hand_over")
	Game.toast.emit("%s gave you %s" % [first, what])
	n.decide_in = 0.5
	mark_dirty(n.settlement)

## Gives an NPC an instruction for a while (from dialogue, the model or the service).
func instruct(n: NPC, action: String, seconds: float) -> void:
	if action == "none" or action == "":
		return
	if action == "stop_following":
		_overrides.erase(n.rec["id"])
		n.decide_in = 0.0
		return
	if action == "leave":
		action = "go_home"
	if action in ["follow", "go_home", "flee", "attack"]:
		n.stop_perform()
	_overrides[n.rec["id"]] = {"action": action, "until": now() + seconds}
	n.decide_in = 0.0

func _external_decide(pp: Vector3) -> void:
	var batch: Array = []
	var t := now()
	for e in settlements.values():
		for n in e["nodes"]:
			if n.global_position.distance_to(pp) < 90.0 and not n.talking:
				batch.append(DecisionEngine.snapshot(n.rec, perception(n, e, pp, t)))
	if batch.is_empty():
		return
	_deciding = true
	var ctx := {"hour": snappedf(NPCMind.hour_now(), 0.1), "day": NPCMind.day_num(), "player": {"x": snappedf(pp.x, 0.1), "z": snappedf(pp.z, 0.1), "health": Game.health}}
	var res: Dictionary = await AI.decide_external(batch, ctx)
	_deciding = false
	for id in res:
		var n = _by_id.get(id)
		if n == null or not is_instance_valid(n):
			continue
		var d: Dictionary = res[id]
		var keep: float = clampf(float(d.get("seconds", DECIDE_EVERY * 2.0)), 0.5, 600.0)
		_overrides[id] = {"action": d["action"], "until": now() + keep}
		if d.get("say", "") is String and d.get("say", "") != "":
			n.say(String(d["say"]).left(140))

func _background_think(pp: Vector3) -> void:
	var t := now()
	var pick: NPC = null
	for e in settlements.values():
		for n in e["nodes"]:
			if n.talking or n.is_hidden() or n.think_at > t:
				continue
			if n.global_position.distance_to(pp) < THINK_RANGE:
				pick = n
				break
		if pick:
			break
	if pick == null or not AI.has_budget(3):
		return
	pick.think_at = t + float(AI.get_value("think_interval")) * randf_range(0.8, 1.2)
	_thinking = true
	var s: Dictionary = pick.settlement
	var r: Dictionary = await AI.chat_json(NPCMind.think_prompt(pick.rec, s, pick.action), [{"role": "user", "content": "What do you do now?"}], true)
	_thinking = false
	if not r["ok"] or not is_instance_valid(pick):
		return
	var d: Dictionary = r["data"]
	if d.get("goal", "") is String and d.get("goal", "") != "":
		pick.rec["goal"] = String(d["goal"]).left(80)
	if NPCMind.MOODS.has(d.get("mood", "")):
		pick.rec["mood"] = d["mood"]
	var a := String(d.get("action", ""))
	if a in ["wander", "work", "socialize", "go_home", "sleep", "idle", "greet"]:
		instruct(pick, a, 45.0)
	var line = d.get("say", "")
	if line is String and line.strip_edges() != "" and pick.global_position.distance_to(pp) < 25.0:
		pick.say(line.strip_edges().left(140), 6.0)
	mark_dirty(s)

# --- Player interactions ---------------------------------------------------------------------

func begin_talk(n: NPC) -> void:
	n.talking = true
	n.rec["met"] = int(n.rec.get("met", 0)) + 1
	if int(n.rec["met"]) == 1:
		NPCMind.remember(n.rec, "Met a traveller for the first time.")
	mark_dirty(n.settlement)

func end_talk(n: NPC) -> void:
	if is_instance_valid(n):
		n.talking = false
		n.decide_in = 0.0
		mark_dirty(n.settlement)

## The player struck an NPC. Everyone remembers.
func player_hit(n: NPC, damage: float) -> void:
	var rec := n.rec
	var s := n.settlement
	rec["hp"] = float(rec.get("hp", 100.0)) - damage
	n.flash_hit()
	NPCMind.change_rel(rec, -35)
	rec["mood"] = "angry" if float(rec["traits"]["brave"]) > 0.5 else "afraid"
	for o in all_nodes():
		if o != n and o.settlement == s and o.global_position.distance_to(n.global_position) < 40.0:
			NPCMind.change_rel(o.rec, -15)
			o.decide_in = 0.0
	if rec["hp"] <= 0.0:
		rec["dead"] = true
		rec["hp"] = 0.0
		NPCMind.add_rumor(s, "%s was killed by the traveller." % rec["name"])
		for o in s["npcs"]:
			if o != rec and not o.get("dead", false):
				NPCMind.change_rel(o, -40)
				NPCMind.remember(o, "The traveller killed %s." % rec["name"])
		Game.toast.emit("%s is dead" % rec["name"])
		var e: Dictionary = settlements.get(NPCGen.settlement_id(s["sx"], s["sz"]), {})
		if e.has("nodes"):
			e["nodes"].erase(n)
		_by_id.erase(rec["id"])
		n.queue_free()
	else:
		n.say(NPCMind.bark(rec, "hurt"), 3.0)
		var today := "Day %d" % NPCMind.day_num()
		var mem: Array = rec["mem"]
		if mem.is_empty() or not String(mem[-1]).begins_with(today) or not String(mem[-1]).contains("attacked"):
			NPCMind.remember(rec, "The traveller attacked me.")
			NPCMind.add_rumor(s, "The traveller attacked %s." % rec["name"])
		n.decide_in = 0.0
	mark_dirty(s)
	Game.save_all()

## The player damaged or destroyed something that belongs to a settlement.
func player_vandalised(pos: Vector3, what: String) -> void:
	for e in settlements.values():
		var s: Dictionary = e["data"]
		if (s["center"] as Vector2).distance_to(Vector2(pos.x, pos.z)) > 60.0:
			continue
		for n in e["nodes"]:
			if n.global_position.distance_to(pos) < 45.0:
				NPCMind.change_rel(n.rec, -25 if what != "" else -4)
				n.decide_in = 0.0
				if what == "" and randf() < 0.3:
					n.say(["Hey! Stop that!", "Leave that alone!", "What do you think you're doing?"][randi() % 3], 3.0)
		if what != "":
			NPCMind.add_rumor(s, "The traveller destroyed the %s." % what.to_lower())
			for p in s["npcs"]:
				if not p.get("dead", false):
					NPCMind.remember(p, "The traveller destroyed the %s." % what.to_lower())
		e["dirty"] = true

## The trader stall object this NPC keeps, as [state dict, ChunkNode], or [].
func trader_stall(n: NPC) -> Array:
	if not n.rec.has("stall"):
		return []
	var sp: Vector2 = n.rec["stall"]
	var k := ChunkStreamer.chunk_of(Vector3(sp.x, 0, sp.y))
	var c := streamer.get_chunk(k)
	if c == null:
		return []
	for o in c.data["objects"]:
		if o["t"] == "trader" and not o["st"].get("gone", false):
			var wp := Vector2(o["p"].x + k.x * ChunkGenerator.SIZE, o["p"].z + k.y * ChunkGenerator.SIZE)
			if wp.distance_to(sp) < 0.5:
				return [o["st"], c]
	return []
