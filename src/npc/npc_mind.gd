class_name NPCMind
## What NPCs say and remember. Builds prompts for the language model, interprets its
## replies, and provides the built-in dialogue used when no model is connected.

const MAX_MEMORIES := 16
const MAX_RUMORS := 8
const MOODS := ["calm", "happy", "wary", "angry", "afraid", "sad", "curious"]
const TALK_ACTIONS := ["none", "follow", "stop_following", "trade", "go_home", "flee", "attack", "leave"]

## The in-game day, read without a compile-time dependency on the Game autoload so this
## class also works in tools and tests.
static func game_day() -> float:
	var g = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	return float(g.day) if g != null else 0.0

static func hour_now() -> float:
	return fposmod(game_day(), 1.0) * 24.0

static func day_num() -> int:
	return int(game_day()) + 1

static func time_words(h: float) -> String:
	if h < 5.0: return "the dead of night"
	if h < 8.0: return "early morning"
	if h < 12.0: return "morning"
	if h < 14.0: return "midday"
	if h < 18.0: return "afternoon"
	if h < 21.0: return "evening"
	return "night"

static func feeling(rel: int) -> String:
	if rel <= -60: return "you hate them and want them gone"
	if rel <= -30: return "you distrust and fear them"
	if rel < -5: return "you are wary of them"
	if rel < 15: return "they are a stranger to you"
	if rel < 40: return "you like them"
	if rel < 70: return "you consider them a friend"
	return "you trust them completely"

static func remember(npc: Dictionary, text: String) -> void:
	text = text.strip_edges().left(160)
	if text == "":
		return
	var mem: Array = npc["mem"]
	mem.append("Day %d: %s" % [day_num(), text])
	while mem.size() > MAX_MEMORIES:
		mem.pop_front()

static func add_rumor(settlement: Dictionary, text: String) -> void:
	var r: Array = settlement["rumors"]
	r.append("Day %d: %s" % [day_num(), text.left(160)])
	while r.size() > MAX_RUMORS:
		r.pop_front()

static func change_rel(npc: Dictionary, d: int) -> void:
	npc["rel"] = clampi(int(npc.get("rel", 0)) + d, -100, 100)

# --- Language model -----------------------------------------------------------------

static func system_prompt(npc: Dictionary, settlement: Dictionary, ctx: Dictionary) -> String:
	var t: Dictionary = npc["traits"]
	var lines := PackedStringArray()
	lines.append("You are %s. You live in %s, a %s settlement." % [NPCGen.describe(npc), settlement["name"], Eras.NAMES[npc["era"]].to_lower()])
	lines.append("The world: medieval kingdoms, glowing fantasy wildwoods and a sci-fi frontier of alloy and starships blend into one another across the land. People know the other lands exist and find them strange.")
	lines.append("Your personality (0 to 1): friendliness %.1f, bravery %.1f, curiosity %.1f, diligence %.1f, greed %.1f. You like %s. You worry about %s." % [t["friendly"], t["brave"], t["curious"], t["diligent"], t["greedy"], npc["likes"], npc["worry"]])
	lines.append("You speak in a way that is %s." % npc["speech"])
	if npc["job"] == "trader":
		lines.append("You run the market stall here and will happily trade.")
	lines.append("It is %s on day %d. You are currently feeling %s, and your goal is: %s." % [time_words(hour_now()), day_num(), npc.get("mood", "calm"), npc.get("goal", "") if npc.get("goal", "") != "" else "going about your day"])
	lines.append("You are talking to a traveller. You have met them %d times before; %s." % [npc.get("met", 0), feeling(int(npc.get("rel", 0)))])
	if ctx.get("held", "") != "":
		lines.append("The traveller is holding: %s." % ctx["held"])
	var mem: Array = npc["mem"]
	if not mem.is_empty():
		lines.append("What you remember:")
		for m in mem:
			lines.append("- " + m)
	var rum: Array = settlement["rumors"]
	if not rum.is_empty():
		lines.append("News going around %s:" % settlement["name"])
		for r in rum:
			lines.append("- " + r)
	lines.append("Stay fully in character. Never mention being an AI, a model or a game. Keep what you say to one to three short sentences.")
	lines.append("Reply with only a JSON object, no other text:")
	lines.append('{"say": "your words", "mood": "one of %s", "action": "one of %s", "rel_change": integer from -10 to 10 (how this exchange changed your opinion of the traveller), "remember": "a short note worth remembering about this exchange, or empty", "goal": "your current goal in a few words, or empty", "options": ["three short things the traveller might say next"]}' % ["|".join(MOODS), "|".join(TALK_ACTIONS)])
	lines.append('Use action "trade" only if you are the trader and they want to trade, "follow" only if you agree to go with them, and "attack" only if you are truly threatened.')
	return "\n".join(lines)

static func think_prompt(npc: Dictionary, settlement: Dictionary, current: String) -> String:
	var base := system_prompt(npc, settlement, {}).split("You are talking to a traveller")[0]
	return base + "Right now you are: %s. Decide what you want to do for the next while.\nReply with only a JSON object: {\"goal\": \"a few words\", \"action\": \"one of wander|work|socialize|go_home|sleep|idle|greet\", \"say\": \"a short line you mutter or call out, or empty\", \"mood\": \"one of %s\"}" % [current, "|".join(MOODS)]

## Applies a model (or built-in) reply. Returns the action to perform ("none" if none).
static func apply_reply(npc: Dictionary, settlement: Dictionary, d: Dictionary) -> String:
	var mood := String(d.get("mood", ""))
	if MOODS.has(mood):
		npc["mood"] = mood
	var rc = d.get("rel_change", 0)
	if rc is float or rc is int:
		change_rel(npc, clampi(int(rc), -10, 10))
	var rem = d.get("remember", "")
	if rem is String and rem.strip_edges() != "":
		remember(npc, rem)
	var goal = d.get("goal", "")
	if goal is String and goal.strip_edges() != "":
		npc["goal"] = goal.strip_edges().left(80)
	var a := String(d.get("action", "none"))
	if not TALK_ACTIONS.has(a):
		a = "none"
	if a == "trade" and npc["job"] != "trader":
		a = "none"
	return a

static func clean_options(d: Dictionary) -> Array:
	var out: Array = []
	var o = d.get("options", [])
	if o is Array:
		for x in o:
			if x is String and x.strip_edges() != "":
				out.append(x.strip_edges().left(70))
	return out.slice(0, 3)

# --- Built-in dialogue (no model) --------------------------------------------------------

const GREET := [
	["Good day to you, traveller.", "Well met.", "Mind the mud, stranger.", "You're not from round here, are you?"],
	["The grove whispered you'd come.", "Light on your path, wanderer.", "Ah, a new face beneath the old trees.", "Welcome, if you come in peace."],
	["Hey. Keep your weapon holstered and we'll get along.", "New arrival? Welcome to the frontier.", "Signal's good today. What do you need?", "Copy that, stranger. Go ahead."],
]
const PLACE := [
	"This is %s. Honest folk, hard work, and the ale's not bad.",
	"You stand in %s. The glow-moss keeps the old paths lit.",
	"%s. Not much, but the air scrubbers work and the walls hold.",
]
const FAREWELL := [["Safe roads.", "Off with you, then.", "Gods keep you."], ["May the light find you.", "Go gently.", "The wood remembers."], ["Stay frosty.", "Clear skies.", "Over and out."]]

## Default suggestions for the player.
static func default_options(npc: Dictionary) -> Array:
	var o := ["Who are you?", "What is this place?", "Any news?"]
	if npc["job"] == "trader":
		o.append("Let's trade.")
	else:
		o.append("Come with me.")
	return o

static func builtin_reply(npc: Dictionary, settlement: Dictionary, text: String) -> Dictionary:
	var e: int = npc["era"]
	var q := text.to_lower()
	var r := int(npc.get("rel", 0))
	var h := absi(hash(text + str(game_day())))
	var out := {"say": "", "action": "none", "rel_change": 0, "remember": "", "options": default_options(npc)}
	if r <= -40:
		out["say"] = ["Keep away from me.", "I've nothing to say to you.", "Leave, before I call the guard."][h % 3]
		out["mood"] = "afraid" if float(npc["traits"]["brave"]) < 0.5 else "angry"
		return out
	if q.contains("bye") or q.contains("farewell") or q.contains("leave"):
		out["say"] = FAREWELL[e][h % 3]
	elif q.contains("who") or q.contains("name") or q.contains("yourself"):
		out["say"] = "I'm %s. I work as a %s here, have done for years. I'm partial to %s." % [npc["name"], npc["job"], npc["likes"]]
		out["remember"] = "Told the traveller about myself."
	elif q.contains("place") or q.contains("where") or q.contains("town") or q.contains("village"):
		out["say"] = PLACE[e] % settlement["name"]
	elif q.contains("news") or q.contains("rumo") or q.contains("happen"):
		var rum: Array = settlement["rumors"]
		if not rum.is_empty():
			out["say"] = "Folk are saying: %s" % String(rum[-1]).split(": ", true, 1)[-1]
		else:
			out["say"] = "Not much. Mostly I worry about %s." % npc["worry"]
	elif q.contains("trade") or q.contains("buy") or q.contains("sell") or q.contains("wares"):
		if npc["job"] == "trader":
			out["say"] = "Let's see what you've got."
			out["action"] = "trade"
		else:
			out["say"] = "Talk to %s at the stall." % _trader_name(settlement)
	elif q.contains("follow") or q.contains("come with"):
		if r >= 20 and npc["job"] != "trader":
			out["say"] = "Alright, lead the way."
			out["action"] = "follow"
			out["remember"] = "Agreed to travel with the traveller."
		else:
			out["say"] = "I hardly know you. I've work to do."
	elif q.contains("stop") or q.contains("stay") or q.contains("wait"):
		out["say"] = "Very well, I'll head back."
		out["action"] = "stop_following"
	elif q.contains("job") or q.contains("work") or q.contains("do here"):
		out["say"] = "I'm the %s. It keeps me busy." % npc["job"]
	elif q.contains("thank") or q.contains("friend") or q.contains("help"):
		out["say"] = "Kind of you to say."
		out["rel_change"] = 2
	elif r < 15 and int(npc.get("met", 0)) <= 1:
		out["say"] = GREET[e][h % GREET[e].size()]
		out["rel_change"] = 1
	else:
		out["say"] = ["Hm. Can't say I follow.", "Is that so?", "Interesting. Tell me more another time.", "If you say so."][h % 4]
	return out

static func _trader_name(settlement: Dictionary) -> String:
	for p in settlement["npcs"]:
		if p["job"] == "trader":
			return p["name"].split(" ")[0]
	return "the trader"

## Short line an NPC says on its own (greeting a passer-by, a warning, a mutter).
static func bark(npc: Dictionary, kind: String) -> String:
	var e: int = npc["era"]
	var h := absi(hash(npc["id"] + str(int(game_day() * 200.0))))
	match kind:
		"greet":
			if int(npc.get("met", 0)) > 0 and int(npc.get("rel", 0)) > 10:
				return ["Back again! Good to see you.", "There you are, friend.", "Ah, it's you."][h % 3]
			return GREET[e][h % GREET[e].size()]
		"confront":
			return ["That's far enough. Put it away.", "One more step and you'll regret it.", "We know what you did."][h % 3]
		"attack":
			return ["You'll pay for that!", "To arms!", "Hostile engaged!"][e if e < 3 else 0]
		"flee":
			return ["Help! Help!", "Stay away from me!", "Somebody stop them!"][h % 3]
		"hurt":
			return ["Argh!", "What are you doing?!", "Stop!"][h % 3]
	return ""
