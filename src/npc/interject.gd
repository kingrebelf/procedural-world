class_name Interject
## The instant first answer a person gives while they think about the rest: "Yes.",
## "No.", "Hmm, let me think about that.", or nothing at all. It is picked from a fixed,
## pre-approved list (by the fast decision service if one is set, otherwise here from what
## you said and who they are), spoken straight away with a nod, a head shake or a thinking
## pose, and the model's full reply follows on from it.

## kind -> the lines a person may use. Each person sticks to one phrasing per kind.
const KINDS := {
	"yes": ["Yes.", "Sure.", "Of course.", "Alright.", "Happily."],
	"no": ["No.", "I don't think so.", "Hmm, no.", "I'd rather not."],
	"think": ["Hmm, let me think about that.", "Let me see...", "Hmm...", "Good question."],
	"maybe": ["Maybe.", "Perhaps...", "We'll see."],
	"greet": ["Oh, hello!", "Well, hello there.", "Hello to you too."],
	"thanks": ["You're welcome.", "Glad to help.", "Any time."],
	"surprised": ["Oh!", "Really?", "Is that so?"],
	"offended": ["Excuse me?", "How rude.", "Watch your tongue."],
	"none": [],
}
## Old-world phrasing, used in the medieval and fantasy eras.
const OLD := {"yes": ["Aye.", "Aye, gladly."], "no": ["Nay.", "I'd sooner not."], "greet": ["Well met!", "Good day to you."]}
## What their body does with each.
const GESTURE := {"yes": "nod", "no": "shake_head", "think": "think", "maybe": "tilt", "greet": "wave",
	"thanks": "nod", "surprised": "tilt", "offended": "hips"}

const QUESTION_WORDS := ["what", "why", "how", "where", "who", "when", "which", "whose", "tell me", "do you", "did you",
	"are you", "is there", "is it", "have you", "should i", "would you", "could you", "can you", "will you"]
const RUDE := ["stupid", "idiot", "ugly", "shut up", "hate you", "fool", "moron", "dumb", "loser", "smell"]

static func _has_word(q: String, w: String) -> bool:
	return RegEx.create_from_string("\\b" + w + "\\b").search(q) != null

## The kind of instant answer this person gives to `text` without a model ("none" for
## silence). Requests use the same rules the built-in dialogue does, so a quick "yes" is
## what they would actually do.
static func pick_local(rec: Dictionary, text: String) -> String:
	var q := text.to_lower().strip_edges()
	if q == "":
		return "none"
	var words := q.split(" ", false).size()
	var t: Dictionary = rec["traits"]
	for w in RUDE:
		if q.contains(w):
			return "offended"
	if words <= 4:
		for g in ["hello", "hi", "hey", "greetings", "good morning", "good evening", "good day", "howdy"]:
			if _has_word(q, g):
				return "greet"
	for g in ["thanks", "thank you", "cheers"]:
		if _has_word(q, g):
			return "thanks"
	var doing := NPCMind.requested_do(q)
	if doing != "":
		return "yes" if NPCMind.willing(rec, doing) else "no"
	if q.contains("lend") or q.contains("spare") or (q.contains("give me") and (q.contains("mark") or q.contains("money") or q.contains("coin"))):
		return "think" if NPCSocial.will_give(rec, "lend" if q.contains("lend") else "beg") > 0 else "no"
	var question := q.ends_with("?")
	for w in QUESTION_WORDS:
		if q.begins_with(w + " ") or q.begins_with(w + "?"):
			question = true
	# Quiet, unfriendly people let you finish and simply answer.
	var talky := float(t["friendly"]) * 0.6 + float(t["curious"]) * 0.4
	if question:
		if words >= 5 or talky > 0.45:
			return "think"
		return "maybe" if talky > 0.3 else "none"
	if q.contains("!") and words <= 8 and talky > 0.4:
		return "surprised"
	if words >= 10 and talky > 0.35:
		return "think"
	return "none"

## Whether something said out loud, to nobody in particular, is meant for the people
## around ("Can anyone spare me five Marks?", "Hello!", "Where's the smithy?") rather
## than talking to yourself or someone on the other end of a headset.
const CALLS := ["anyone", "anybody", "someone", "somebody", "everyone", "everybody", "hey", "hello", "hi", "excuse me",
	"please", "help", "spare", "lend", "need", "looking for", "does anyone", "is there", "where", "who", "can", "could",
	"would", "will you", "good morning", "good evening", "good day", "greetings", "howdy", "oi", "you there", "sir", "madam", "friend"]

static func calls_out(text: String) -> bool:
	var q := text.to_lower().strip_edges()
	if q == "":
		return false
	if q.ends_with("?"):
		return true
	for w in CALLS:
		if _has_word(q, w):
			return true
	return false

## The words this person uses for `kind` ("" for none).
static func line(rec: Dictionary, kind: String) -> String:
	var opts: Array = KINDS.get(kind, []).duplicate()
	if opts.is_empty():
		return ""
	if int(rec.get("era", 0)) < 2 and OLD.has(kind):
		opts.append_array(OLD[kind])
	return opts[absi(hash(String(rec["id"]) + kind)) % opts.size()]

## What the fast decision service is sent for one quick answer.
static func request_body(rec: Dictionary, text: String, local: String) -> Dictionary:
	var lines := {}
	for k in KINDS:
		lines[k] = line(rec, k)
	return {"version": 1, "kind": "interject", "said": text, "suggested": local, "options": KINDS.keys(), "lines": lines,
		"npc": {"id": rec["id"], "name": rec["name"], "job": rec["job"], "traits": rec["traits"],
			"rel": int(rec.get("rel", 0)), "mood": rec.get("mood", "calm")}}

## The service's choice: {"pick": "<kind>"} (or "interject"); "" if it gave none we know.
static func parse_pick(raw: String) -> String:
	var d = JSON.parse_string(raw)
	if not (d is Dictionary):
		return ""
	var k := String(d.get("pick", d.get("interject", "")))
	return k if KINDS.has(k) else ""

## A note for the model, so its full reply carries on from what was already said.
static func note_for_model(said: String) -> String:
	return "\n\n(You already answered straight away with \"%s\". Carry on from there and don't repeat it.)" % said
