class_name NPCMind
## What NPCs say and remember. Builds prompts for the language model, interprets its
## replies, and provides the built-in dialogue used when no model is connected.

const MAX_MEMORIES := 16
const MAX_RUMORS := 8
const MOODS := ["calm", "happy", "wary", "angry", "afraid", "sad", "curious"]
const TALK_ACTIONS := ["none", "follow", "stop_following", "trade", "go_home", "flee", "attack", "leave",
	"give_money", "lend_money", "gift", "ask_repay", "join_guild", "buy_house", "pay_toll"]

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
	elif npc.has("band"):
		lines.append("You are %s, an outlaw in a %s of %d camped out in the wilds, far from any town. You live by robbing travellers on the roads." % [NPCGen.describe(npc), String(settlement["name"]).to_lower(), (settlement["npcs"] as Array).size()])
		lines.append("You have stopped this traveller and want their money. If they agree to pay, take it with action \"pay_toll\" and let them go. If they refuse, insult you or threaten you, use \"attack\" (unless you are scared of them: then \"flee\"). You can be bargained with, bluffed or frightened, in character.")
	else:
		lines.append("You are %s. You live in %s, a %s settlement." % [NPCGen.describe(npc), settlement["name"], Eras.NAMES[npc["era"]].to_lower()])
	lines.append(world_line())
	lines.append("Your personality (0 to 1): friendliness %.1f, bravery %.1f, curiosity %.1f, diligence %.1f, greed %.1f. You like %s. You worry about %s." % [t["friendly"], t["brave"], t["curious"], t["diligent"], t["greedy"], npc["likes"], npc["worry"]])
	lines.append("You speak in a way that is %s." % npc["speech"])
	lines.append(NPCTalk.prompt_voice(npc))
	if npc["job"] == "trader":
		lines.append("You run the market stall here and will happily trade.")
	elif npc.has("shop_kind"):
		lines.append(TownShops.prompt_line(npc))
	var days := NPCRoles.day_words(npc)
	if days != "":
		lines.append("Your working day: %s." % days)
	if String(npc.get("_duty", "")) != "":
		lines.append("Right now you are %s." % npc["_duty"])
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
	lines.append("Stay fully in character. Never mention being an AI, a model or a game.")
	lines.append("Talk like a real person, not a storybook: contractions, short and longer sentences mixed, a dialect word now and then. React to what the traveller actually said; sometimes ask them something back or bring up your own concerns. Avoid stock phrases (\"Well met\", \"How can I help you\", calling them \"traveller\" every line) and never repeat anything you already said in this conversation. \"say\" is spoken aloud: one to three short sentences, no stage directions, asterisks or emoji; gestures go in \"do\".")
	lines.append("Reply with only a JSON object, no other text:")
	lines.append('{"say": "your words", "mood": "one of %s", "action": "one of %s", "do": "something you do with your body right now, or empty: one of %s", "marks": integer (only with give_money or lend_money: how many Marks you hand over), "rel_change": integer from -10 to 10 (how this exchange changed your opinion of the traveller), "remember": "a short note worth remembering about this exchange, or empty", "goal": "your current goal in a few words, or empty", "options": ["three short things the traveller might say next"]}' % ["|".join(MOODS), "|".join(TALK_ACTIONS), "|".join(doable())])
	lines.append('Use action "trade" if they want to buy or sell (you trade the goods of your work), "follow" only if you agree to go with them, and "attack" only if you are truly threatened or deeply insulted and brave enough.')
	lines.append('If they beg or ask for money, decide from your personality, your purse and how you feel about them: "give_money" to give some, "lend_money" for a loan they must repay, or refuse. "gift" hands them something from your goods. "ask_repay" if they owe you.')
	lines.append('Use "do" whenever it fits: wave, nod, shrug, wink, dance, sit, jump, point, hold up fingers (fingers_1 to fingers_5, or finger_index, finger_middle, finger_ring, finger_pinky, finger_thumb), and so on. If they ask you to do something and you are willing, do it; if not, refuse in character.')
	return "\n".join(lines)

static func think_prompt(npc: Dictionary, settlement: Dictionary, current: String) -> String:
	var base := system_prompt(npc, settlement, {}).split("You are talking to a traveller")[0]
	return base + "Right now you are: %s. Decide what you want to do for the next while.\nReply with only a JSON object: {\"goal\": \"a few words\", \"action\": \"one of wander|work|socialize|go_home|sleep|idle|greet|dance|sit\", \"say\": \"a short spoken line you mutter or call out, in your own voice, or empty\", \"mood\": \"one of %s\"}" % [current, "|".join(MOODS)]

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
## Default suggestions for the player.
static func default_options(npc: Dictionary) -> Array:
	if npc.has("band"):
		return ["Fine, take it. (pay the toll)", "I'm not paying you anything.", "Who are you people?"]
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

## Lines for the money and favours the built-in dialogue handles (%d is the sum).
const LEND_YES := ["I can spare %d. Pay me back within three days, mind.", "Here's %d. I'll want it back soon.", "%d, and not a Mark more. Three days.",
	"Alright. %d Marks, and I'm trusting you with them. Three days.", "Take %d. Don't make me come looking for you."]
const LEND_NO := ["I'm not a bank.", "Lend to you? I hardly know you.", "My purse is spoken for.", "Not a chance. I've been burned before.",
	"If I had it to lend, I'd lend it. I don't.", "Ask me again when I know your face better."]
const GIVE_YES := ["Here, take %d. Don't spend it all at once.", "Times are hard for all of us. Here's %d.", "%d Marks. Pay it forward someday.",
	"Go on, then. %d, and buy yourself something hot to eat.", "Here's %d. I was poor once too."]
const GIVE_NO := ["Earn it like the rest of us.", "I've barely enough for myself.", "No. Go and work for it.", "Do I look like I'm made of Marks?",
	"There's honest work about, if you want coin."]
const GIVE_SORRY := ["I wish I could, truly. My purse is empty.", "I'd help if I could. I've nothing to spare this week.", "Sorry. I'm scraping by myself."]
const REFUSE_DO := ["I'd rather not.", "Not for you, I won't.", "Ask me again when we're better acquainted.", "Do I look like a performing bear?",
	"Hah. No.", "Not today.", "You'll have to buy me a drink first."]
const FOLLOW_YES := ["Alright, lead the way.", "Why not? Let's go.", "I'll come. Don't get us killed.", "Right behind you."]
const FOLLOW_NO := ["I hardly know you. I've work to do.", "Follow you? I've got a life here.", "Not today. Too much to do.", "Maybe when I know you better."]
const STOP_LINES := ["Very well, I'll head back.", "Alright. I'll be going home, then.", "Fair enough. You know where to find me.", "Suit yourself. Back I go."]
const TRADE_YES := ["Let's see what you've got.", "Trade? Always. Show me.", "I'm listening. What are you after?"]
const TRADE_OWN := ["I've a few things from my work. Have a look.", "Not a shop, but I've some bits. See if anything takes your fancy."]
const GIFT_YES := ["For a friend? I've something you might like.", "Here. I was saving this for someone who deserved it."]
const GIFT_NO := ["Gifts are for friends. Maybe one day.", "A gift? We've only just met.", "Earn a bit more of my trust first."]

## What a person says to the traveller without a model: money, favours, requests and
## trade first (the same actions the model can take), then how it was said (rudeness,
## kind words), then talk about themselves, the town, the news and anything else
## (NPCTalk). Returns the reply contract of docs/AI.md.
static func builtin_reply(npc: Dictionary, settlement: Dictionary, text: String) -> Dictionary:
	var q := text.to_lower().strip_edges()
	var r := int(npc.get("rel", 0))
	var h := absi(hash(text + str(game_day()) + String(npc.get("id", ""))))
	var out := {"say": "", "action": "none", "rel_change": 0, "remember": "", "options": default_options(npc)}
	if npc.has("band"):
		return _outlaw_reply(npc, q, h)
	var rng := NPCTalk.rng_for(npc, "reply" + q)
	var line := func(pool: Array) -> String:
		var s := NPCTalk.pick(npc, pool, rng)
		NPCTalk.note_said(npc, s)
		return s
	if r <= -40:
		out["say"] = NPCTalk.bark(npc, "hostile", settlement)
		out["mood"] = "afraid" if float(npc["traits"]["brave"]) < 0.5 else "angry"
		return out
	NPCSocial.ensure(npc)
	var want := requested_do(q)
	var t: Dictionary = npc["traits"]
	var words := q.split(" ", false).size()
	if q.contains("lend") or q.contains("loan") or q.contains("borrow"):
		var n := NPCSocial.will_give(npc, "lend", _asked_amount(q))
		if int(npc["debt"]) > 0:
			out["say"] = "Not until you pay back the %d you already owe me." % npc["debt"]
			out["do"] = "shake_head"
		elif n > 0:
			out["say"] = line.call(LEND_YES) % n
			out["action"] = "lend_money"
			out["marks"] = n
			out["do"] = "nod"
		else:
			out["say"] = line.call(LEND_NO)
			out["do"] = "shake_head"
		return out
	var about_money := q.contains("money") or q.contains("marks") or q.contains("coin")
	var asking := q.contains("give me") or q.contains("can i have") or q.contains("could i have") or q.contains("need") or q.contains("please")
	if (about_money and asking) or q.contains("spare") or q.contains("beg") or q.contains("alms"):
		var n := NPCSocial.will_give(npc, "beg", _asked_amount(q))
		if n > 0:
			out["say"] = line.call(GIVE_YES) % n
			out["action"] = "give_money"
			out["marks"] = n
			out["rel_change"] = -1 if float(t["greedy"]) > 0.6 else 0
		else:
			out["say"] = line.call(GIVE_NO if float(t["greedy"]) > 0.4 or r < 10 else GIVE_SORRY)
			out["do"] = "shrug" if float(t["greedy"]) < 0.5 else "shake_head"
			out["rel_change"] = -1
		return out
	if q.contains("repay") or q.contains("pay back") or q.contains("owe"):
		out["say"] = "You owe me %d Marks. Give it over when you can." % npc["debt"] if int(npc["debt"]) > 0 else "You don't owe me anything."
		return out
	if q.contains("gift") or q.contains("present"):
		if r >= 30:
			out["say"] = line.call(GIFT_YES)
			out["action"] = "gift"
		else:
			out["say"] = line.call(GIFT_NO)
		return out
	if want != "":
		if willing(npc, want):
			out["do"] = want
			out["say"] = _doing_line(want, h)
			out["rel_change"] = 1 if r < 30 else 0
		else:
			out["do"] = "shake_head"
			out["say"] = line.call(REFUSE_DO)
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
	# How it was said comes before what it was about: rudeness stings, kind words warm.
	var manner := NPCTalk.tone_of(q)
	if manner == "insult":
		out.merge(NPCTalk.insulted(npc, settlement, q), true)
		return out
	if manner == "compliment":
		out.merge(NPCTalk.flattered(npc, settlement, q), true)
		return out
	var following := String(npc.get("_action", "")) == "follow"
	var place_word := q.contains("town") or q.contains("place") or q.contains("village")
	if NPCTalk.has_any(q, ["bye", "goodbye", "farewell", "see you", "leave", "must go", "have to go", "got to go", "gotta go", "take care", "so long"]):
		out["say"] = NPCTalk.farewell(npc, settlement)
		out["do"] = "wave"
	elif q.contains("your name") or NPCTalk.has_any(q, ["who are you", "who're you", "yourself", "introduce"]) or (q.contains("name") and not place_word):
		out["say"] = NPCTalk.about_self(npc, settlement)
		out["remember"] = "Told the traveller about myself."
	elif (q.contains("trade") and not q.contains("your trade")) or q.contains("buy") or q.contains("sell") or q.contains("wares"):
		if npc.has("shop_kind") and npc["shop_kind"] == "land":
			out["say"] = "Houses{a}. Have a look at what's free."
			out["action"] = "buy_house"
		elif npc["job"] == "trader" or npc.has("shop_kind") or r >= -5:
			out["say"] = line.call(TRADE_YES if npc["job"] == "trader" or npc.has("shop_kind") else TRADE_OWN)
			out["action"] = "trade"
		else:
			out["say"] = "Not with you. Try %s at the stall." % _trader_name(settlement)
	elif q.contains("follow") or q.contains("come with"):
		if r >= 20 and npc["job"] != "trader" and not npc.has("shop_kind"):
			out["say"] = line.call(FOLLOW_YES)
			out["action"] = "follow"
			out["remember"] = "Agreed to travel with the traveller."
		else:
			out["say"] = line.call(FOLLOW_NO)
	elif (NPCTalk.has_any(q, ["stop following", "stay here", "stay put", "wait here", "go back", "don't follow", "stay"]) and (following or words <= 4 or q.contains("here"))) \
			or (following and NPCTalk.has_any(q, ["stop", "wait"])):
		out["say"] = line.call(STOP_LINES)
		out["action"] = "stop_following"
	elif q.contains("where") and NPCTalk.has_any(q, ["inn", "tavern", "market", "smith", "shop", "temple", "shrine", "well", "gate", "stall", "healer", "guild", "cantina", "bar", "trader", "way out"]):
		out.merge(NPCTalk.topic_reply(npc, settlement, "directions", q), true)
	elif place_word or q.contains("where"):
		out["say"] = NPCTalk.about_place(npc, settlement)
	elif q.contains("news") or q.contains("rumo") or q.contains("happen") or q.contains("gossip"):
		out["say"] = NPCTalk.news(npc, settlement)
	elif q.contains("job") or q.contains("work") or q.contains("do here") or q.contains("trade"):
		out.merge(NPCTalk.topic_reply(npc, settlement, "work", q), true)
	elif q.contains("thank"):
		out["say"] = NPCTalk.thanked(npc, settlement)
		out["rel_change"] = 2
	elif NPCTalk.topic_of(q) != "":
		out.merge(NPCTalk.topic_reply(npc, settlement, NPCTalk.topic_of(q), q), true)
	elif NPCTalk.has_any(q, NPCTalk.GREET_WORDS) and words <= 5:
		out["say"] = NPCTalk.greet(npc, settlement)
		out["rel_change"] = 1 if r < 15 else 0
		if r >= 15:
			out["do"] = "wave"
	elif q.contains("friend") or q.contains("help"):
		out.merge(NPCTalk.topic_reply(npc, settlement, "help", q), true)
		out["rel_change"] = 1
	elif NPCTalk.has_any(q, NPCTalk.YESNO_WORDS) and words <= 4:
		out.merge(NPCTalk.topic_reply(npc, settlement, "yesno", q), true)
	else:
		out["say"] = NPCTalk.puzzled(npc, settlement, q)
	out["say"] = NPCTalk.fill(npc, settlement, String(out["say"]), rng)
	if String(out["say"]).strip_edges() == "":
		out["say"] = NPCTalk.puzzled(npc, settlement, q)
	return out

## An outlaw who has stopped you: pay, and you go; refuse or threaten, and they fight.
static func _outlaw_reply(npc: Dictionary, q: String, h: int) -> Dictionary:
	var out := {"say": "", "action": "none", "rel_change": 0, "remember": "", "options": ["Fine, take it. (pay the toll)", "I'm not paying you anything.", "Who are you people?"]}
	var brave := float(npc["traits"]["brave"])
	if q.contains("pay") or q.contains("take it") or q.contains("toll") or q.contains("here") or (q.contains("money") and not q.contains("no")):
		out["say"] = ["Wise. Very wise.", "There, that didn't hurt, did it?", "Pleasure doing business.", "Good choice. Off you go, quick now.",
			"Smart. You'll live to grumble about it."][h % 5]
		out["action"] = "pay_toll"
		out["do"] = "nod"
	elif q.contains("not pay") or q.contains("no") or q.contains("never") or q.contains("kill") or q.contains("die") or q.contains("fight") or q.contains("leave me"):
		if brave < 0.3:
			out["say"] = ["Alright, alright! No need for that!", "Not worth it. Go on, then.", "Easy! We were only joking!"][h % 3]
			out["action"] = "flee"
		else:
			out["say"] = ["Wrong answer.", "Then we'll take it off your corpse.", "Have it your way!", "Brave. Stupid, but brave.",
				"Lads! This one wants to do it the hard way."][h % 5]
			out["action"] = "attack"
			out["do"] = "fist"
	elif q.contains("who") or q.contains("name"):
		out["say"] = "%s. Folk on this road know the name. Now, your purse." % npc["name"]
	else:
		out["say"] = ["Stop stalling. Coin, now.", "I'm not here to chat.", "Purse. Now. Or else.", "Talk all you like. The toll's still due.",
			"You're wasting daylight, and my patience.", "Clever words won't fill my pockets. Your Marks will."][h % 6]
		out["do"] = "point"
	return out

static func _asked_amount(q: String) -> int:
	var m := RegEx.create_from_string("(\\d+)").search(q)
	return m.get_string(1).to_int() if m else 0

static func _doing_line(want: String, h: int) -> String:
	match want:
		"dance":
			return ["Ha! Why not?", "Strike up a tune, then!", "Watch these feet.", "I haven't danced since the harvest. Here goes."][h % 4]
		"sit":
			return ["Don't mind if I do.", "My feet could use the rest.", "Oof. That's better."][h % 3]
		"stand":
			return ["Up I get.", "Alright, alright, I'm up."][h % 2]
		"jump", "flip":
			return ["Hup!", "Like this?", "Watch!", "Here goes nothing!"][h % 4]
		"wink":
			return ["Our little secret.", "You didn't see that.", "There. Don't tell anyone."][h % 3]
		"finger_middle":
			return "Only because it's you."
		"play_dead":
			return ["Ugh... I'm done for...", "Tell my mother... I loved her..."][h % 2]
		"zombie":
			return "Braaains..."
		"bow":
			return ["At your service.", "My pleasure."][h % 2]
		"salute":
			return ["As you were.", "There. Proper and all."][h % 2]
	if want.begins_with("fingers_"):
		return ["That many, like so.", "There. Count them."][h % 2]
	return ["Like this?", "Alright.", "There you go.", "If you insist.", "Happy now?"][h % 5]

static func _trader_name(settlement: Dictionary) -> String:
	for p in settlement["npcs"]:
		if p["job"] == "trader":
			return p["name"].split(" ")[0]
	return "the trader"

## Short line an NPC says on its own: "greet" (a passer-by, or the traveller walking up),
## "confront", "attack", "flee", "hurt" or "hostile". Fitted to the person (NPCTalk).
static func bark(npc: Dictionary, kind: String, settlement := {}) -> String:
	return NPCTalk.bark(npc, kind, settlement)
