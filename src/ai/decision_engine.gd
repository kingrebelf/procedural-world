class_name DecisionEngine
## Built-in fast decisions for NPCs: a utility AI that scores every action from the NPC's
## personality, needs, schedule and what it perceives, then picks the best. It runs in
## microseconds, needs no network, and is what NPCs fall back on whenever a model or the
## external decision service is slow, off or unreachable.
##
## The same action vocabulary is used by the LLM (dialogue and background goals) and by
## the external decision service, so every source of "what to do next" is interchangeable.

const ACTIONS := ["idle", "wander", "work", "socialize", "go_home", "sleep", "greet", "follow", "flee", "confront", "attack", "trade",
	"dance", "sit", "gift"]

## per (perception):
##   hour: float 0..24, pos: Vector2, center: Vector2, noise: float 0..1,
##   player_dist: float, player_pos: Vector2, player_armed: bool,
##   override: {action, until, target?} from dialogue / LLM / external service, now: float
static func decide(npc: Dictionary, per: Dictionary) -> Dictionary:
	var t: Dictionary = npc["traits"]
	var hour: float = per["hour"]
	var rel: float = float(npc.get("rel", 0)) / 100.0
	var pd: float = per.get("player_dist", INF)
	var guard: bool = NPCGen.GUARD_JOBS.has(npc["job"])
	var trader: bool = npc["job"] == "trader"
	var energy: float = npc.get("energy", 1.0)
	var social: float = npc.get("social", 0.5)
	var noise: float = per.get("noise", 0.5)
	var s := {}

	var night := hour >= 22.0 or hour < 6.0
	var evening := hour >= 19.0 and hour < 22.0
	var workday := hour >= 8.0 and hour < 18.0
	s["sleep"] = (0.9 if night else 0.0) + (1.0 - energy) * 0.4
	s["go_home"] = 0.55 if evening else 0.05
	s["work"] = (0.45 + float(t["diligent"]) * 0.45 + (0.4 if trader else 0.0)) if workday or (trader and hour >= 7.0 and hour < 20.0) else 0.0
	s["socialize"] = (1.0 - social) * 0.45 + (0.25 if hour >= 17.0 and hour < 21.0 else 0.0)
	s["wander"] = 0.15 + float(t["curious"]) * 0.25 + noise * 0.1
	s["idle"] = 0.15 + noise * 0.05
	# Guards walk their rounds rather than standing at one spot all day.
	if guard and workday:
		s["wander"] += 0.25
	# Evenings: the sociable dance in the square (every seventh day is a festival), the
	# weary and the old sit down for a while.
	var mood: String = npc.get("mood", "calm")
	var festive := int(per.get("day", 1)) % 7 == 0
	var dance := 0.1 + float(t["friendly"]) * 0.35 + float(t["curious"]) * 0.25 - float(t["diligent"]) * 0.2 + (0.2 if mood == "happy" else 0.0)
	if hour >= 18.0 and hour < 22.5:
		s["dance"] = dance * (1.6 if festive else 0.75)
	elif not night:
		s["dance"] = dance * 0.12
	if not night:
		s["sit"] = (1.0 - energy) * 0.7 + (0.18 if int(npc.get("age", 30)) > 55 else 0.0) + (0.1 if evening else 0.0)
	if guard:
		s["dance"] = s.get("dance", 0.0) * 0.3
		s["sit"] = s.get("sit", 0.0) * 0.5
	# Someone who is fond of you may bring you a little present, once a day.
	var rel_i := int(npc.get("rel", 0))
	if rel_i >= 50 and float(t["friendly"]) > 0.45 and pd < 25.0 and int(npc.get("gift_day", -1)) != int(per.get("day", 1)):
		s["gift"] = 0.55 + float(t["friendly"]) * 0.45

	# The player.
	if pd < 7.0 and rel > -0.15 and not npc.get("greeted", false):
		s["greet"] = 0.35 + float(t["friendly"]) * 0.5 + float(t["curious"]) * 0.15
	var threat: bool = rel < -0.35 or (per.get("player_armed", false) and rel < -0.1)
	if threat and pd < 18.0:
		s["flee"] = (1.0 - float(t["brave"])) * 1.3 * (1.0 if not guard else 0.2)
		if guard or float(t["brave"]) > 0.75:
			s["confront"] = 0.8 + float(t["brave"]) * 0.4
	if rel <= -0.6 and pd < 25.0 and (guard or float(t["brave"]) > 0.8):
		s["attack"] = 1.25 + float(t["brave"]) * 0.3
	if night and s.has("greet"):
		s["greet"] *= 0.3

	# An instruction from a conversation, the model or the external service wins unless
	# the NPC is in danger.
	var ov = per.get("override", null)
	if ov is Dictionary and float(ov.get("until", 0.0)) > float(per.get("now", 0.0)) and ACTIONS.has(ov.get("action", "")):
		var a: String = ov["action"]
		var danger: float = maxf(s.get("flee", 0.0), s.get("attack", 0.0))
		if danger < 1.0 or a == "flee" or a == "attack":
			return _resolve(npc, per, a, 2.0, "instructed")

	var best := "idle"
	var bs := -INF
	for a in s:
		if s[a] > bs:
			bs = s[a]
			best = a
	return _resolve(npc, per, best, bs, "utility")

## Turns an action into a concrete movement target.
static func _resolve(npc: Dictionary, per: Dictionary, a: String, score: float, why: String) -> Dictionary:
	var out := {"action": a, "score": score, "why": why}
	var c: Vector2 = per["center"]
	var pos: Vector2 = per["pos"]
	var noise: float = per.get("noise", 0.5)
	match a:
		"sleep", "go_home":
			out["target"] = npc["home"]
		"work":
			out["target"] = npc["work"]
		"socialize":
			var ang := noise * TAU
			out["target"] = c + Vector2(cos(ang), sin(ang)) * 4.0
		"wander":
			var ang := noise * TAU * 3.0
			out["target"] = c + Vector2(cos(ang), sin(ang)) * (6.0 + noise * 12.0)
		"greet", "follow", "confront", "attack", "trade", "gift":
			out["target_player"] = true
		"dance":
			var ang := noise * TAU * 2.0
			out["target"] = c + Vector2(cos(ang), sin(ang)) * (2.5 + noise * 3.0)
		"sit":
			out["target"] = pos
		"flee":
			var pp: Vector2 = per.get("player_pos", pos)
			var away := (pos - pp)
			if away.length() < 0.1:
				away = Vector2(1, 0)
			out["target"] = pos + away.normalized() * 25.0
		_:
			out["target"] = pos
	return out

## Perception summary sent to the external decision service (see docs/AI.md).
static func snapshot(npc: Dictionary, per: Dictionary) -> Dictionary:
	return {
		"id": npc["id"], "name": npc["name"], "job": npc["job"], "era": Eras.NAMES[npc["era"]],
		"traits": npc["traits"], "rel": npc.get("rel", 0), "mood": npc.get("mood", "calm"),
		"energy": snappedf(npc.get("energy", 1.0), 0.01), "hp": npc.get("hp", 100.0),
		"hour": snappedf(per["hour"], 0.1), "player_dist": snappedf(minf(per.get("player_dist", 999.0), 999.0), 0.1),
		"player_armed": per.get("player_armed", false), "goal": npc.get("goal", ""),
		"current": npc.get("_action", "idle"),
	}
