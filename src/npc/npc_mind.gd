class_name NPCMind
## What NPCs say and remember. Builds prompts for the language model, interprets its
## replies, and provides the built-in dialogue used when no model is connected.

const MAX_MEMORIES := 16
const MAX_RUMORS := 8
const MOODS := ["calm", "happy", "wary", "angry", "afraid", "sad", "curious"]
const TALK_ACTIONS := ["none", "follow", "stop_following", "trade", "go_home", "flee", "attack", "leave",
	"give_money", "lend_money", "gift", "ask_repay", "join_guild", "buy_house"]

## Full-body things a person can be asked to do (or does on a whim). Gestures
## (BodyLanguage.names()) are played over these. name -> [animation, seconds, mode]
## mode: "loop" holds the animation, "once" plays it through, "hold" stays in its last pose.
const PERFORM := {
	"dance": ["dance", 14.0, "loop"], "sit": ["sit", 25.0, "sit"], "stand": ["idle", 0.1, "stand"],
	"jump": ["jump_air", 1.1, "jump"], "crouch": ["crouch", 8.0, "loop"], "kneel": ["fix", 7.0, "loop"],
	"roll": ["roll", 1.3, "once"], "flip": ["flip", 1.2, "jump"], "eat": ["eat", 2.5, "once"],
	"throw": ["throw", 1.6, "once"], "phone": ["phone", 8.0, "loop"], "zombie": ["zombie", 9.0, "loop"],
	"play_dead": ["death", 9.0, "hold"], "cast": ["cast", 1.8, "once"], "block": ["block", 1.4, "once"],
	"punch": ["jab", 1.0, "once"], "combo": ["combo", 2.6, "once"], "push": ["push", 4.0, "loop"],
	"yes": ["yes", 2.0, "once"], "no": ["no", 2.0, "once"], "fold_arms": ["fold_arms", 7.0, "loop"],
	"spar": ["sword_idle", 5.0, "loop"], "pick_up": ["pickup", 2.0, "once"], "hand_over": ["interact", 1.6, "once"], "lantern": ["lantern", 8.0, "loop"],
}

## Everything a person can do on request: full-body actions (PERFORM) and gestures
## (BodyLanguage).
static func doable() -> Array:
	return PERFORM.keys() + BodyLanguage.names()

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

## What everyone knows about the world they live in, by its theme (Eras.theme).
static func world_line() -> String:
	match Eras.theme:
		"human":
			return "The world: a human world of medieval kingdoms, farms and forests near the old heartlands, and far out at its edges the frontier outposts of a starfaring human age. Nothing here glows or grows strangely; tales speak of rare ancient portals far beyond the frontier that open onto other worlds, some of them not human at all."
		"alien":
			return "The world: an alien world, far from any human home. Glowing fey wilds of the Sylvari give way to the crystal and alloy cities of the Vex. Humans who come here arrive through the ancient portals, and they look strange to you."
	return "The world: medieval kingdoms, glowing fantasy wildwoods and a sci-fi frontier of alloy and starships blend into one another across the land. People know the other lands exist and find them strange."

static func system_prompt(npc: Dictionary, settlement: Dictionary, ctx: Dictionary) -> String:
	var t: Dictionary = npc["traits"]
	var lines := PackedStringArray()
	if settlement.has("boat"):
		lines.append("You are %s. You are aboard %s, out on open water. %s" % [NPCGen.describe(npc), settlement["name"], BOAT_LIFE.get(npc["job"], "You work this boat with the others aboard.")])
	else:
		lines.append("You are %s. You live in %s, a %s settlement." % [NPCGen.describe(npc), settlement["name"], Eras.NAMES[npc["era"]].to_lower()])
	lines.append(world_line())
	lines.append("Your personality (0 to 1): friendliness %.1f, bravery %.1f, curiosity %.1f, diligence %.1f, greed %.1f. You like %s. You worry about %s." % [t["friendly"], t["brave"], t["curious"], t["diligent"], t["greedy"], npc["likes"], npc["worry"]])
	lines.append("You speak in a way that is %s." % npc["speech"])
	if npc["job"] == "trader":
		lines.append("You run the market stall here and will happily trade.")
	elif npc.has("shop_kind"):
		lines.append(TownShops.prompt_line(npc))
	lines.append("It is %s on day %d. You are currently feeling %s, and your goal is: %s." % [time_words(hour_now()), day_num(), npc.get("mood", "calm"), npc.get("goal", "") if npc.get("goal", "") != "" else "going about your day"])
	lines.append("You are talking to a traveller. You have met them %d times before; %s." % [npc.get("met", 0), feeling(int(npc.get("rel", 0)))])
	if ctx.get("held", "") != "":
		lines.append("The traveller is holding: %s." % ctx["held"])
	NPCSocial.ensure(npc)
	lines.append("You have %d Marks (the local money) in your purse." % int(npc["purse"]))
	if int(npc.get("debt", 0)) > 0:
		lines.append("The traveller owes you %d Marks%s." % [npc["debt"], ", and the loan is overdue" if NPCSocial.overdue(npc) else ""])
	var worn: PackedStringArray = []
	for slot in npc.get("gear", {}):
		worn.append(ItemDB.display_name(npc["gear"][slot]))
	if npc.get("held", null) is Dictionary:
		worn.append("holding " + ItemDB.display_name(npc["held"]))
	if not worn.is_empty():
		lines.append("You are wearing: %s." % ", ".join(worn))
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
	lines.append('{"say": "your words", "mood": "one of %s", "action": "one of %s", "do": "something you do with your body right now, or empty: one of %s", "marks": integer (only with give_money or lend_money: how many Marks you hand over), "rel_change": integer from -10 to 10 (how this exchange changed your opinion of the traveller), "remember": "a short note worth remembering about this exchange, or empty", "goal": "your current goal in a few words, or empty", "options": ["three short things the traveller might say next"]}' % ["|".join(MOODS), "|".join(TALK_ACTIONS), "|".join(doable())])
	lines.append('Use action "trade" if they want to buy or sell (you trade the goods of your work), "follow" only if you agree to go with them, and "attack" only if you are truly threatened or deeply insulted and brave enough.')
	lines.append('If they beg or ask for money, decide from your personality, your purse and how you feel about them: "give_money" to give some, "lend_money" for a loan they must repay, or refuse. "gift" hands them something from your goods. "ask_repay" if they owe you.')
	lines.append('Use "do" whenever it fits: wave, nod, shrug, wink, dance, sit, jump, point, hold up fingers (fingers_1 to fingers_5, or finger_index, finger_middle, finger_ring, finger_pinky, finger_thumb), and so on. If they ask you to do something and you are willing, do it; if not, refuse in character.')
	return "\n".join(lines)

static func think_prompt(npc: Dictionary, settlement: Dictionary, current: String) -> String:
	var base := system_prompt(npc, settlement, {}).split("You are talking to a traveller")[0]
	return base + "Right now you are: %s. Decide what you want to do for the next while.\nReply with only a JSON object: {\"goal\": \"a few words\", \"action\": \"one of wander|work|socialize|go_home|sleep|idle|greet|dance|sit\", \"say\": \"a short line you mutter or call out, or empty\", \"mood\": \"one of %s\"}" % [current, "|".join(MOODS)]

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
	return a

## The body action a reply asks for, if this person can do it ("" if none).
static func reply_do(d: Dictionary) -> String:
	var w := String(d.get("do", d.get("gesture", ""))).strip_edges().to_lower().replace(" ", "_")
	return w if doable().has(w) else ""

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
## Life aboard, by job, for the language model and the built-in replies.
const BOAT_LIFE := {
	"castaway": "Your ship went down and you have drifted for days with little water. You are desperate to reach land.",
	"fisher": "You fish these waters for a living and know where the shoals run.",
	"deckhand": "You haul lines, scrub decks and do whatever the skipper says.",
	"captain": "You command this vessel and her crew, and you are responsible for every soul aboard.",
	"sailor": "You are a sailor who has crossed these waters many times.",
	"ship's cook": "You keep the crew fed from a small galley, and you guard the stores.",
	"lookout": "You keep watch for shoals, weather and other sails.",
	"boat pilot": "You run a motor launch on these waters, ferrying, fishing and towing.",
	"marine biologist": "You study the life in these waters: fish, reefs and what lives in the deep.",
	"ship engineer": "You keep the engines, winches and pumps running.",
	"medic": "You are the ship's medic.",
	"pirate": "You are a pirate. You take what you want from anyone foolish enough to sail near.",
}
const BOAT_PLACE := "Welcome aboard %s. Mind your footing, the deck moves."

const PLACE := [
	"This is %s. Honest folk, hard work, and the ale's not bad.",
	"You stand in %s. The glow-moss keeps the old paths lit.",
	"%s. Not much, but the air scrubbers work and the walls hold.",
]
const FAREWELL := [["Safe roads.", "Off with you, then.", "Gods keep you."], ["May the light find you.", "Go gently.", "The wood remembers."], ["Stay frosty.", "Clear skies.", "Over and out."]]

## Default suggestions for the player.
static func default_options(npc: Dictionary) -> Array:
	var o := ["Who are you?", "What is this place?", "Any news?"]
	if npc.has("shop_kind"):
		o[2] = "What do you sell?"
		o.append({"land": "I'd like to buy a house."}.get(npc["shop_kind"], "Tell me about the guild." if TownShops.is_guild(npc["shop_kind"]) else "Let's trade."))
		return o
	o.append("Let's trade." if npc["job"] == "trader" else "Come with me.")
	return o

const NUMBERS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5}

## Things you can ask for in plain words -> what the person does. Checked in order.
const ASK_WORDS := [
	["middle finger", "finger_middle"], ["index finger", "finger_index"], ["pinky", "finger_pinky"], ["little finger", "finger_pinky"],
	["ring finger", "finger_ring"], ["thumbs down", "thumbs_down"], ["thumbs up", "thumbs_up"], ["thumb", "finger_thumb"],
	["peace", "peace"], ["rock on", "rock"], ["call me", "call_me"], ["fingers crossed", "crossed"], ["cross your fingers", "crossed"],
	["count", "count"], ["okay sign", "ok"], ["ok sign", "ok"], ["wink", "wink"], ["wave", "wave"], ["salute", "salute"],
	["bow", "bow"], ["nod", "nod"], ["shake your head", "shake_head"], ["shrug", "shrug"], ["clap", "clap"], ["applaud", "clap"],
	["cheer", "cheer"], ["point", "point"], ["pray", "pray"], ["think", "think"], ["facepalm", "facepalm"], ["hands on hips", "hips"],
	["beckon", "beckon"], ["fist", "fist"], ["dance", "dance"], ["sit", "sit"], ["stand", "stand"], ["get up", "stand"],
	["jump", "jump"], ["crouch", "crouch"], ["duck", "crouch"], ["kneel", "kneel"], ["roll", "roll"], ["flip", "flip"],
	["somersault", "flip"], ["play dead", "play_dead"], ["zombie", "zombie"], ["eat", "eat"], ["throw", "throw"],
	["phone", "phone"], ["cast", "cast"], ["magic", "cast"], ["spell", "cast"], ["block", "block"], ["punch", "punch"],
	["combo", "combo"], ["push", "push"], ["fold your arms", "fold_arms"], ["cross your arms", "fold_arms"], ["spar", "spar"],
]

## What a request asks this person to do with their body ("" if nothing).
## Only a request counts: "can you dance", "please wave", "show me...", or a sentence
## that starts with the action ("dance!"). "I think so" asks for nothing.
static func requested_do(q: String) -> String:
	q = " " + q.to_lower().strip_edges() + " "
	var asked := false
	for cue in ["can you", "could you", "will you", "would you", "please", "show me", "do a ", "do the", "let's", "lets ", "go on", "try to", "i want you to", "hold up", "give me a", "give us a"]:
		if q.contains(cue):
			asked = true
	var m := RegEx.create_from_string("\\b(one|two|three|four|five|[1-5]) fingers?\\b").search(q)
	if m:
		return "fingers_%d" % NUMBERS[m.get_string(1)]
	for e in ASK_WORDS:
		var at := RegEx.create_from_string("\\b" + String(e[0]) + "\\b").search(q)
		if at and (asked or q.strip_edges().begins_with(e[0])):
			return e[1]
	return ""

## Would this person do `what` because the traveller asked? Silly or intimate things take
## more liking; anyone afraid or angry does nothing for you.
static func willing(npc: Dictionary, what: String) -> bool:
	var r := int(npc.get("rel", 0))
	var t: Dictionary = npc["traits"]
	if npc.get("mood", "") in ["angry", "afraid"] or r < -10:
		return what in ["finger_middle", "thumbs_down", "fist", "shake_head", "no"]
	match what:
		"wink", "dance", "flip", "zombie", "play_dead", "call_me", "rock":
			return r >= 20 or float(t["friendly"]) + float(t["curious"]) > 1.1
		"finger_middle":
			return r >= 35 or float(t["brave"]) > 0.8 # a joke between friends
		"punch", "combo", "spar":
			return float(t["brave"]) > 0.4
		"salute":
			return NPCGen.GUARD_JOBS.has(npc["job"]) or r >= 0
	return r >= -5

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
	NPCSocial.ensure(npc)
	var want := requested_do(q)
	var t: Dictionary = npc["traits"]
	if q.contains("lend") or q.contains("loan") or q.contains("borrow"):
		var n := NPCSocial.will_give(npc, "lend", _asked_amount(q))
		if int(npc["debt"]) > 0:
			out["say"] = "Not until you pay back the %d you already owe me." % npc["debt"]
			out["do"] = "shake_head"
		elif n > 0:
			out["say"] = ["I can spare %d. Pay me back within three days, mind.", "Here's %d. I'll want it back soon.", "%d, and not a Mark more. Three days."][h % 3] % n
			out["action"] = "lend_money"
			out["marks"] = n
			out["do"] = "nod"
		else:
			out["say"] = ["I'm not a bank.", "Lend to you? I hardly know you.", "My purse is spoken for."][h % 3]
			out["do"] = "shake_head"
		return out
	var about_money := q.contains("money") or q.contains("marks") or q.contains("coin")
	var asking := q.contains("give me") or q.contains("can i have") or q.contains("could i have") or q.contains("need") or q.contains("please")
	if (about_money and asking) or q.contains("spare") or q.contains("beg") or q.contains("alms"):
		var n := NPCSocial.will_give(npc, "beg", _asked_amount(q))
		if n > 0:
			out["say"] = ["Here, take %d. Don't spend it all on ale.", "Times are hard for all of us. Here's %d.", "%d Marks. Pay it forward someday."][h % 3] % n
			out["action"] = "give_money"
			out["marks"] = n
			out["rel_change"] = -1 if float(t["greedy"]) > 0.6 else 0
		else:
			out["say"] = ["Earn it like the rest of us.", "I've barely enough for myself.", "No. Go and work for it."][h % 3] if float(t["greedy"]) > 0.4 or r < 10 else "I wish I could, truly. My purse is empty."
			out["do"] = "shrug" if float(t["greedy"]) < 0.5 else "shake_head"
			out["rel_change"] = -1
		return out
	if q.contains("repay") or q.contains("pay back") or q.contains("owe"):
		out["say"] = "You owe me %d Marks. Give it over when you can." % npc["debt"] if int(npc["debt"]) > 0 else "You don't owe me anything."
		return out
	if q.contains("gift") or q.contains("present"):
		if r >= 30:
			out["say"] = "For a friend? I've something you might like."
			out["action"] = "gift"
		else:
			out["say"] = "Gifts are for friends. Maybe one day."
		return out
	if want != "":
		if willing(npc, want):
			out["do"] = want
			out["say"] = _doing_line(want, h)
			out["rel_change"] = 1 if r < 30 else 0
		else:
			out["do"] = "shake_head"
			out["say"] = ["I'd rather not.", "Not for you, I won't.", "Ask me again when we're better acquainted.", "Do I look like a performing bear?"][h % 4]
		return out
	if npc.has("shop_kind"):
		var kind: String = npc["shop_kind"]
		if TownShops.is_guild(kind) and (q.contains("guild") or q.contains("join") or q.contains("member")):
			out["say"] = TownShops.pitch(npc)
			out["action"] = "join_guild"
			return out
		if kind == "land" and (q.contains("house") or q.contains("land") or q.contains("home") or q.contains("deed") or q.contains("property")):
			out["say"] = "I've a few places free. Have a look."
			out["action"] = "buy_house"
			return out
	if q.contains("bye") or q.contains("farewell") or q.contains("leave"):
		out["say"] = FAREWELL[e][h % 3]
	elif q.contains("who") or q.contains("name") or q.contains("yourself"):
		out["say"] = "I'm %s. I work as a %s here, have done for years. I'm partial to %s." % [npc["name"], npc["job"], npc["likes"]]
		out["remember"] = "Told the traveller about myself."
	elif q.contains("place") or q.contains("where") or q.contains("town") or q.contains("village"):
		out["say"] = (BOAT_PLACE if settlement.has("boat") else PLACE[e]) % settlement["name"]
	elif q.contains("news") or q.contains("rumo") or q.contains("happen"):
		var rum: Array = settlement["rumors"]
		if not rum.is_empty():
			out["say"] = "Folk are saying: %s" % String(rum[-1]).split(": ", true, 1)[-1]
		else:
			out["say"] = "Not much. Mostly I worry about %s." % npc["worry"]
	elif q.contains("trade") or q.contains("buy") or q.contains("sell") or q.contains("wares"):
		if npc.has("shop_kind") and npc["shop_kind"] == "land":
			out["say"] = "Houses, traveller. Have a look at what's free."
			out["action"] = "buy_house"
		elif npc["job"] == "trader" or npc.has("shop_kind") or r >= -5:
			out["say"] = "Let's see what you've got." if npc["job"] == "trader" or npc.has("shop_kind") else "I've a few things from my work. Have a look."
			out["action"] = "trade"
		else:
			out["say"] = "Not with you. Try %s at the stall." % _trader_name(settlement)
	elif q.contains("follow") or q.contains("come with"):
		if r >= 20 and npc["job"] != "trader" and not npc.has("shop_kind"):
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

static func _asked_amount(q: String) -> int:
	var m := RegEx.create_from_string("(\\d+)").search(q)
	return m.get_string(1).to_int() if m else 0

static func _doing_line(want: String, h: int) -> String:
	match want:
		"dance":
			return ["Ha! Why not?", "Strike up a tune, then!", "Watch these feet."][h % 3]
		"sit":
			return ["Don't mind if I do.", "My feet could use the rest."][h % 2]
		"stand":
			return "Up I get."
		"jump", "flip":
			return ["Hup!", "Like this?", "Watch!"][h % 3]
		"wink":
			return ["*winks*", "Our secret.", "You didn't see that."][h % 3]
		"finger_middle":
			return "Only because it's you."
		"play_dead":
			return "Ugh... I'm done for..."
		"zombie":
			return "Braaains..."
	if want.begins_with("fingers_"):
		return "That many, like so."
	return ["Like this?", "Alright.", "There you go.", "If you insist."][h % 4]

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
