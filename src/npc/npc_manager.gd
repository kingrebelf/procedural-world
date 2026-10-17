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
var corpses: Corpses
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
var _stealth_t := 0.0
var _mob_t := 0.0
## How close the nearest watcher is to noticing you, 0..1 (the sneak eye on the HUD), and
## whether anyone is near enough to watch at all.
var detection := 0.0
var watched := false

func _ready() -> void:
	gen = ChunkGenerator.new(Game.seed)
	Game.saving.connect(save_all)
	add_to_group("npc_manager")
	Net.mob_hit.connect(_on_mob_hit)
	Net.mob_said.connect(_on_mob_said)
	Net.town_pushed.connect(_on_town_pushed)
	Net.mob_talk.connect(_on_mob_talk)

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
		if not Game.store.prefetch_settlement(site):
			continue # on a server: its people are on their way
		_load(site, id)
	for id in settlements.keys():
		var e: Dictionary = settlements[id]
		if e.has("boat"):
			continue # BoatManager brings crews aboard and takes them off
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
	var e := {"data": data, "nodes": [], "dirty": false, "site": site, "outer": float(site.get("outer", 60.0)), "sid": "%d:%s" % [Game.planet, id]}
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
		_add_node(e, rec)
	# On a server: one player runs these people, the others see them (Net.holds).
	Net.watch("t", [[Vector2i(int(site["sx"]), int(site["sz"])), site["center"]]], [])

func _add_node(e: Dictionary, rec: Dictionary) -> NPC:
	var n := NPC.new()
	n.setup(rec, e["data"], self)
	n.think_at = now() + randf() * float(AI.get_value("think_interval"))
	var b = e.get("boat")
	if b is BoatNode and is_instance_valid(b):
		n.boat = b
		b.crew_nodes.append(n)
		rec["pos"] = b.deck_xf(int(rec.get("station", 0))).origin
	add_child(n)
	e["nodes"].append(n)
	_by_id[rec["id"]] = n
	return n

## Whether this game runs the town's people (always, offline).
func runs(e: Dictionary) -> bool:
	return Net.holds("t", Vector2i(int(e["data"]["sx"]), int(e["data"]["sz"])))

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
	var k := Vector2i(int(e["data"]["sx"]), int(e["data"]["sz"]))
	if (runs(e) or e["dirty"]) and not e.get("transient", false):
		if runs(e):
			e["data"]["sim_day"] = Game.day
		Game.store.save_settlement(e["data"])
	Net.watch("t", [], [k])
	Game.store.forget_settlement(k.x, k.y)
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
		if not runs(e) and not e["dirty"] or e.get("transient", false):
			continue
		if runs(e):
			e["data"]["sim_day"] = Game.day
		Game.store.save_settlement(e["data"])
		e["dirty"] = false

# --- Boats -----------------------------------------------------------------------------------

## A boat came near enough to meet its crew: loads them like a town's people (saved and
## shared the same way) and puts them aboard. Spawned boats' crews are made fresh and
## never saved. Returns false while a server is still sending the crew (try again).
func board(b: BoatNode) -> bool:
	if Game.store == null or not is_instance_valid(b):
		return false
	var site := b.site
	var id := NPCGen.settlement_id(int(site["sx"]), int(site["sz"]))
	if settlements.has(id):
		return true
	var transient := bool(site.get("spawned", false))
	var data: Dictionary
	if transient:
		data = Boats.crew(gen.seed, site)
		if site.get("crew") is Array:
			var given: Array = site["crew"]
			for i in given.size():
				var rec: Dictionary = given[i]
				rec["boat"] = b.kind
				rec["station"] = i
				rec["faction"] = b.faction
				rec["home"] = site["center"]
				rec["work"] = site["center"]
				if not rec.get("pos") is Vector3:
					rec["pos"] = Vector3(site["center"].x, 0.0, site["center"].y)
			data["npcs"] = given
	else:
		if not Game.store.prefetch_settlement(site):
			return false
		data = Game.store.get_or_create_settlement(gen, site)
	var e := {"data": data, "nodes": [], "dirty": false, "site": site, "outer": float(site.get("outer", 10.0)),
		"sid": "%d:%s" % [Game.planet, id], "boat": b, "transient": transient}
	settlements[id] = e
	for rec in data["npcs"]:
		if not rec.get("dead", false):
			_add_node(e, rec)
	if not transient:
		Net.watch("t", [[Vector2i(int(site["sx"]), int(site["sz"])), b.pos2()]], [])
	return true

## The boat sailed away from you: its crew are saved and taken off.
func disembark(b: BoatNode) -> void:
	if not is_instance_valid(b):
		return
	var id := NPCGen.settlement_id(int(b.site["sx"]), int(b.site["sz"]))
	if settlements.has(id):
		_unload(id)
	b.crew_nodes.clear()

## The crew's entry ({data, nodes, boat...}) for a boat, or {}.
func crew_of(b: BoatNode) -> Dictionary:
	return settlements.get(NPCGen.settlement_id(int(b.site["sx"]), int(b.site["sz"])), {})

## What someone aboard does: hails you as you come alongside, chats while you're near,
## and otherwise keeps to their station. (Hostile crews: "pirate" faction, handled by
## whoever launched them; here they only shout.)
func _decide_aboard(n: NPC, e: Dictionary, pp: Vector3, t: float) -> void:
	if n.talking:
		return
	var rec := n.rec
	var dist := n.global_position.distance_to(pp)
	var ov = _overrides.get(rec["id"])
	if ov is Dictionary and float(ov["until"]) > t:
		n.action = String(ov["action"])
		n.target_player = n.action in ["greet", "follow", "attack", "confront", "trade"]
	else:
		n.action = "work"
		n.target_player = false
	if dist > 40.0:
		rec["greeted"] = false
		return
	if not rec.get("greeted", false) and dist < 22.0:
		rec["greeted"] = true
		if String(rec.get("faction", "folk")) == "pirate":
			_bark(n, ["Heave to, landlubber!", "That one's ours, lads!", "Your purse or your life!"][randi() % 3], dist)
			n.act("fist")
		elif String(rec["job"]) == "castaway":
			_bark(n, ["Over here! Please, help!", "Thank the stars, a living soul!", "Hey! Hey! Over here!"][randi() % 3], dist)
			n.act("wave")
		else:
			_bark(n, NPCMind.bark(rec, "greet") if randf() < 0.5 else ["Ahoy there!", "Fair winds to you!", "Mind the lines, friend."][randi() % 3], dist)
			n.act(["wave", "nod", "salute"][randi() % 3])
		e["dirty"] = true

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
	_mob_t -= delta
	var send := _mob_t <= 0.0
	if send:
		_mob_t = 1.0 / Net.MOB_HZ
	var out: Array = []
	for e in settlements.values():
		var held := runs(e)
		if e.has("boat") and is_instance_valid(e["boat"]):
			e["data"]["center"] = e["boat"].pos2() # the crew's "town" goes where the boat goes
		var shared := send and held and Net.shared("t", Vector2i(int(e["data"]["sx"]), int(e["data"]["sz"])))
		for n in e["nodes"]:
			if not is_instance_valid(n):
				continue
			n.show_name(pp.distance_to(n.global_position) < 7.0 and not n.is_hidden())
			if n.boat != null:
				# Aboard: everyone draws the crew at their stations; the game that runs
				# them decides what they do.
				var bt: Array = Net.nearest_player(n.global_position, pp)
				if held:
					n.decide_in -= delta
					if n.decide_in <= 0.0:
						n.decide_in = randf_range(1.5, 3.0)
						_decide_aboard(n, e, bt[1], t)
				n.deck_step(delta, bt[1])
				continue
			if not held:
				n.follow(delta, Net.mob_state("n", String(n.rec["id"])), pp)
				continue
			# Online, people react to whichever player is nearest them.
			var tg: Array = Net.nearest_player(n.global_position, pp)
			var tp: Vector3 = tg[1]
			n.decide_in -= delta
			if n.decide_in <= 0.0:
				n.decide_in = randf_range(1.2, 2.4)
				_decide(n, e, tp, t, int(tg[0]))
			n.step(delta, _ground, tp, e["nodes"])
			if shared:
				out.append(n.net_state())
			if n.action == "attack" and n.attack_cd <= 0.0 and tp.distance_to(n.global_position) < 1.7:
				n.attack_cd = 1.4
				var dmg := (6.0 + float(n.rec["traits"]["brave"]) * 6.0) * NPCSocial.hit_mult(n.rec)
				if int(tg[0]) != 0:
					Net.hurt_player(int(tg[0]), dmg, "Killed by %s" % n.rec["name"], false)
					continue
				var took := Game.hurt(dmg, "Killed by %s" % n.rec["name"], func(back: float): player_hit(n, back))
				Game.toast.emit("%s hits you (-%d)" % [n.rec["name"].split(" ")[0], int(ceilf(took))])
	if not out.is_empty():
		Net.send_mobs("n", out)
	_stealth_t -= delta
	if _stealth_t <= 0.0:
		_stealth_t = 0.2
		_update_stealth(0.2)
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
			if e["dirty"] and not e.get("transient", false):
				if runs(e):
					e["data"]["sim_day"] = Game.day
				Game.store.save_settlement(e["data"])
				e["dirty"] = false

## What a person makes of the player at `pp`: you (peer 0), or online another player.
func perception(n: NPC, e: Dictionary, pp: Vector3, t: float, peer := 0) -> Dictionary:
	var held = Game.inventory.get_slot(player.selected) if player.has_method("held_item") else null
	var wanted: int = Game.crime.stars(String(e.get("sid", "")), Game.day)
	if peer != 0:
		var r: Dictionary = Net.peers.get(peer, {})
		held = r.get("held", {})
		held = held if held is Dictionary and held.has("type") else null
		wanted = int((r.get("wanted", {}) as Dictionary).get(String(e.get("sid", "")), 0))
	var armed: bool = held != null and ItemDB.def(held["type"]).get("kind", "") == "weapon"
	var pos := Vector2(n.global_position.x, n.global_position.z)
	return {
		"hour": NPCMind.hour_now(), "pos": pos, "center": e["data"]["center"],
		"noise": float(absi(hash(n.rec["id"] + str(int(t / 20.0)))) % 1000) / 1000.0,
		"player_dist": n.global_position.distance_to(pp), "player_pos": Vector2(pp.x, pp.z),
		"player_armed": armed, "override": _overrides.get(n.rec["id"]), "now": t, "day": NPCMind.day_num(),
		"wanted": wanted,
	}

func _decide(n: NPC, e: Dictionary, pp: Vector3, t: float, peer := 0) -> void:
	if n.talking:
		return
	var rec := n.rec
	var per := perception(n, e, pp, t, peer)
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
				var owe := Game.crime.owed(String(e.get("sid", "")), Game.day)
				if owe > 0 and NPCGen.GUARD_JOBS.has(rec["job"]):
					_bark(n, ("Stop right there, criminal! You owe %s %d Marks. Pay up or face the law." % [e["data"]["name"], owe]) if n.action == "confront"
						else ["Thief! Cut them down!", "You'll answer for your crimes!", "Stop, in the name of %s!" % e["data"]["name"]][randi() % 3], dist)
				else:
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
		Voice.speak(n.rec, line, dist, false, n)

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
		if not runs(e):
			continue
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
		if not runs(e):
			continue
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
	_tell_talk(n, true)
	n.rec["met"] = int(n.rec.get("met", 0)) + 1
	if int(n.rec["met"]) == 1:
		NPCMind.remember(n.rec, "Met a traveller for the first time.")
	Game.map.note_person(n.rec, String(n.settlement.get("name", "")))
	mark_dirty(n.settlement)

func end_talk(n: NPC) -> void:
	if is_instance_valid(n):
		n.talking = false
		_tell_talk(n, false)
		n.decide_in = 0.0
		mark_dirty(n.settlement)

## The player struck an NPC. Everyone remembers.
func player_hit(n: NPC, damage: float) -> void:
	var rec := n.rec
	var s := n.settlement
	rec["hp"] = float(rec.get("hp", 100.0)) - damage
	n.flash_hit()
	var tk := Vector2i(int(s["sx"]), int(s["sz"]))
	if not Net.holds("t", tk):
		Net.hit_mob("n", tk, String(rec["id"]), damage, rec["hp"] <= 0.0) # whoever runs them feels it too
	NPCMind.change_rel(rec, -35)
	rec["mood"] = "angry" if float(rec["traits"]["brave"]) > 0.5 else "afraid"
	var e0 := _entry_of(s)
	if not e0.is_empty() and String(rec.get("faction", "")) != "pirate": # cutting down pirates is no crime
		# They saw who hit them. Assault is fined once a minute per person, so one fight
		# isn't a fortune; a killing always is.
		if rec["hp"] <= 0.0:
			Game.add_bounty(e0["sid"], s["name"], Crime.FINES["murder"], "Murder")
		elif now() - float(rec.get("_fined_t", -999.0)) > 60.0:
			rec["_fined_t"] = now()
			Game.add_bounty(e0["sid"], s["name"], Crime.FINES["assault"], "Assault")
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
		if corpses:
			corpses.add_person(n)
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
		if what != "" and not witnesses(pos).is_empty():
			Game.add_bounty(String(e["sid"]), s["name"], Crime.FINES["vandalism"] * 5, "Vandalism")
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

# --- Crime and stealth ------------------------------------------------------------------------

func _entry_of(s: Dictionary) -> Dictionary:
	return settlements.get(NPCGen.settlement_id(s["sx"], s["sz"]), {})

## The settlement whose ground `pos` is on, while its people are loaded: its entry
## ({data, nodes, outer, sid}), or {}. Things there belong to its people.
func town_at(pos: Vector3) -> Dictionary:
	for e in settlements.values():
		var c: Vector2 = e["data"]["center"]
		if c.distance_to(Vector2(pos.x, pos.z)) <= float(e.get("outer", 60.0)) + 4.0 and not e["nodes"].is_empty():
			return e
	return {}

## Whose house `pos` is in (the person living nearest), or null.
func owner_near(e: Dictionary, pos: Vector3) -> Variant:
	var best = null
	var bd := 9.0
	for rec in e["data"]["npcs"]:
		if rec.get("dead", false):
			continue
		var d := (rec["home"] as Vector2).distance_to(Vector2(pos.x, pos.z))
		if d < bd:
			bd = d
			best = rec
	return best

## How likely this person is to notice the player right now, 0..1: by distance, the
## dark, whether they face you, walls in the way, your sneaking and whether you run.
func awareness(n: NPC, pp: Vector3) -> float:
	if not is_instance_valid(n) or n.is_hidden() or n.rec.get("dead", false):
		return 0.0
	if n.talking:
		return 1.0
	var eye := n.global_position + Vector3(0, 1.6, 0)
	var me := pp + Vector3(0, 1.0, 0)
	var d := eye.distance_to(me)
	var hour := NPCMind.hour_now()
	var dark := hour >= 20.5 or hour < 5.5
	var lit: bool = player != null and "hand_light" in player and player.hand_light != null and player.hand_light.is_on()
	var reach := 22.0 * (0.5 if dark and not lit else 1.0)
	if d > reach:
		return 0.0
	var a := pow(1.0 - d / reach, 0.6)
	# Facing you, or with their back turned (they still hear you up close).
	var fwd := Vector2(sin(n.rotation.y), cos(n.rotation.y))
	var to := Vector2(me.x - eye.x, me.z - eye.z)
	if to.length() > 0.01 and fwd.dot(to.normalized()) < 0.2:
		a *= 0.25 if d > 3.0 else 0.55
	if n.action == "sleep":
		a *= 0.2
	var crouched: bool = player != null and player.has_method("sneaking") and player.sneaking()
	var moving: float = player.velocity.length() if player is CharacterBody3D else 0.0
	a *= Game.stats.notice_mult(crouched) * (1.5 if moving > 6.0 else 1.0)
	if a <= 0.01:
		return 0.0
	# Walls between you hide you, mostly.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, me, 1)
	if not space.intersect_ray(q).is_empty():
		a *= 0.12
	return clampf(a, 0.0, 1.0)

## Everyone who notices what you just did at `pos` (rolled now). `extra` people always count.
func witnesses(pos: Vector3, extra: Array = []) -> Array:
	var out: Array = extra.duplicate()
	if player == null:
		return out
	for n in all_nodes():
		if out.has(n) or not is_instance_valid(n):
			continue
		if n.global_position.distance_to(pos) > 30.0:
			continue
		if randf() < awareness(n, player.global_position):
			out.append(n)
	return out

## A crime in a town: if anyone sees it (or `caught_by` caught you at it), the town puts a
## bounty on you, the witnesses think less of you and shout, and guards come running.
## kind: a Crime.FINES key; worth: Marks taken. Returns true if you were seen.
## Other systems (shops, stalls) call this when you take what isn't yours.
func report_crime(pos: Vector3, kind: String, worth: int, what: String, caught_by: NPC = null) -> bool:
	var e := town_at(pos)
	if e.is_empty():
		return false
	var seen := witnesses(pos, [caught_by] if caught_by != null else [])
	if seen.is_empty():
		return false
	var s: Dictionary = e["data"]
	var fine := int(Crime.FINES.get(kind, 10)) + maxi(0, worth)
	var why: String = {"theft": "Theft", "pickpocket": "Caught pickpocketing", "lockpick": "Caught breaking in", "trespass": "Trespassing", "vandalism": "Vandalism"}.get(kind, "Crime")
	Game.add_bounty(String(e["sid"]), s["name"], fine, why)
	var shout: Array = {"theft": ["Thief! Stop, thief!", "Hey! That's not yours!", "Guards! A thief!"],
		"pickpocket": ["Get your hands off me!", "Thief! Guards!", "Hey! My purse!"],
		"lockpick": ["What are you doing with that lock?", "Guards! Someone's breaking in!"],
		"vandalism": ["Hey! Stop smashing that!", "Guards! They're breaking the door down!"]}.get(kind, ["Guards!"])
	var shouted := false
	for n in seen:
		if not is_instance_valid(n):
			continue
		NPCMind.change_rel(n.rec, -30 if n == caught_by else -12)
		NPCMind.remember(n.rec, "Saw the traveller %s." % {"theft": "stealing " + what, "pickpocket": "trying to pick my pocket" if n == caught_by else "picking pockets",
			"lockpick": "breaking into a chest", "vandalism": "smashing down a door"}.get(kind, "committing a crime"))
		n.rec["mood"] = "angry" if float(n.rec["traits"]["brave"]) > 0.5 else "afraid"
		if not shouted:
			_bark(n, shout[randi() % shout.size()], n.global_position.distance_to(player.global_position))
			n.act("point")
			shouted = true
		n.decide_in = 0.0
	# Word gets to the guards.
	for n in e["nodes"]:
		if NPCGen.GUARD_JOBS.has(n.rec["job"]):
			n.decide_in = 0.0
	NPCMind.add_rumor(s, "The traveller was seen %s." % {"theft": "stealing", "pickpocket": "picking pockets", "lockpick": "breaking into a chest"}.get(kind, "breaking the law"))
	e["dirty"] = true
	return true

## The sneak eye: how near anyone is to noticing you. Sneaking past people unseen is
## practice at Sneaking.
func _update_stealth(dt: float) -> void:
	if player == null:
		return
	var pp := player.global_position
	var best := 0.0
	var any := false
	for n in all_nodes():
		if not is_instance_valid(n) or n.global_position.distance_to(pp) > 24.0:
			continue
		any = true
		best = maxf(best, awareness(n, pp))
	detection = best
	watched = any
	var crouched: bool = player.has_method("sneaking") and player.sneaking()
	if crouched and any and best < 0.35 and player.velocity.length() > 0.5:
		Game.practice("sneak", 0.5 * dt)

## Pay off your bounty in this person's town (to a guard). Returns what was paid, or -1.
func pay_bounty(n: NPC) -> int:
	var e := _entry_of(n.settlement)
	if e.is_empty():
		return -1
	var owe := Game.crime.owed(String(e["sid"]), Game.day)
	if owe <= 0 or Game.money < owe:
		return -1
	Game.add_money(-owe)
	Game.clear_bounty(String(e["sid"]))
	# The law is satisfied: guards stand down.
	for o in e["nodes"]:
		if NPCGen.GUARD_JOBS.has(o.rec["job"]):
			o.rec["rel"] = maxi(int(o.rec.get("rel", 0)), -20)
			_overrides.erase(o.rec["id"])
			o.decide_in = 0.0
	NPCMind.remember(n.rec, "The traveller paid a %d Mark bounty." % owe)
	e["dirty"] = true
	return owe

func bounty_for(n: NPC) -> int:
	var e := _entry_of(n.settlement)
	return 0 if e.is_empty() else Game.crime.owed(String(e["sid"]), Game.day)

# --- Multiplayer ---------------------------------------------------------------------------

## Something one of the people you run said: players near see it too.
func said(n: NPC, text: String, seconds: float) -> void:
	if Net.is_client() and n.settlement.has("sx") and Net.holds("t", Vector2i(int(n.settlement["sx"]), int(n.settlement["sz"]))):
		Net.send_mob_say(String(n.rec["id"]), text, seconds)

func _on_mob_said(id: String, text: String, secs: float) -> void:
	var n = _by_id.get(id)
	if n != null and is_instance_valid(n):
		n.say(text, secs)

## Another player hit one of the people you run. Their game counts the crime and, if the
## blow killed, the death and the body; here the person feels it at once.
func _on_mob_hit(kind: String, id: String, dmg: float, killed: bool, _from: int) -> void:
	if kind != "n":
		return
	var n = _by_id.get(id)
	if n == null or not is_instance_valid(n):
		return
	var rec: Dictionary = n.rec
	if killed:
		rec["dead"] = true
		rec["hp"] = 0.0
		_drop_node(n)
		return
	rec["hp"] = maxf(1.0, float(rec.get("hp", 100.0)) - dmg)
	n.flash_hit()
	n.say(NPCMind.bark(rec, "hurt"), 3.0)
	n.decide_in = 0.0
	mark_dirty(n.settlement)

## Talking with someone another player's game runs: they hold still for you there too.
func _tell_talk(n: NPC, on: bool) -> void:
	var k := Vector2i(int(n.settlement["sx"]), int(n.settlement["sz"]))
	if not Net.holds("t", k):
		n.talk_here = on
		Net.talk_mob(k, String(n.rec["id"]), on)

func _on_mob_talk(id: String, on: bool) -> void:
	var n = _by_id.get(id)
	if n != null and is_instance_valid(n):
		n.talking = on
		n.decide_in = 0.0

func _drop_node(n: NPC) -> void:
	var e: Dictionary = _entry_of(n.settlement)
	if e.has("nodes"):
		e["nodes"].erase(n)
	_by_id.erase(n.rec["id"])
	n.queue_free()

## Someone else's save of a town was merged into yours: people who died there go, and
## anyone newly hired comes.
func _on_town_pushed(sx: int, sz: int) -> void:
	var e = settlements.get(NPCGen.settlement_id(sx, sz))
	if e == null:
		return
	for n in e["nodes"].duplicate():
		if is_instance_valid(n) and n.rec.get("dead", false):
			_drop_node(n)
	for rec in e["data"]["npcs"]:
		if not rec.get("dead", false) and not _by_id.has(rec["id"]):
			_add_node(e, rec)
