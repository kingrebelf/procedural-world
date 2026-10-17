class_name Voice
## Spoken lines for people. Two engines (Settings > AI > Voices):
##   natural  an OpenAI-compatible voice server (OpenAI's gpt-4o-mini-tts, or a free local
##            Kokoro / speaches server). Each person gets a voice and an accent that fits
##            their era and temperament, and is heard from where they stand.
##   system   this PC's own text-to-speech voices, offline. The best installed voices are
##            preferred (Natural, Neural, Enhanced, Premium) and accents are spread around.
## Each person keeps the same voice. Lines queue so a quick "Hmm..." is never cut off by
## the answer that follows it.

const FEMALE := ["zira", "hazel", "susan", "eva", "catherine", "linda", "heather", "aria", "jenny", "sonia", "libby",
	"natasha", "clara", "emma", "samantha", "karen", "moira", "tessa", "fiona", "victoria", "female", "woman", "ava",
	"allison", "serena", "kate", "michelle", "michele", "nora", "salli", "joanna", "kimberly", "ivy", "amy", "heera",
	"maisie", "molly", "emily", "isabella", "ana", "neerja", "leah", "luna", "jane", "nancy", "sara", "ashley", "elizabeth"]
const MALE := ["david", "mark", "george", "ryan", "guy", "daniel", "alex", "fred", "richard", "james", "sean",
	"william", "male", "man", "tom", "aaron", "arthur", "oliver", "thomas", "brian", "matthew", "joey", "justin", "eric",
	"ravi", "connor", "liam", "prabhat", "mitchell", "christopher", "roger", "steffan", "andrew", "brandon", "davis", "tony"]
## Words in a system voice's name that mean it is one of the good, human-sounding ones.
const NATURAL_WORDS := ["natural", "neural", "online", "enhanced", "premium", "siri", "wavenet"]

## Natural voices by model family, [female, male].
const OPENAI_VOICES := [["coral", "nova", "shimmer", "sage", "marin"], ["ash", "ballad", "echo", "onyx", "verse", "cedar", "fable"]]
const OPENAI_TTS1 := [["nova", "shimmer", "alloy"], ["echo", "onyx", "fable"]]
## Kokoro: b* British, a* American.
const KOKORO_VOICES := [["bf_emma", "bf_isabella", "bf_alice", "bf_lily", "af_heart", "af_bella", "af_nicole", "af_sarah"],
	["bm_george", "bm_lewis", "bm_daniel", "bm_fable", "am_adam", "am_michael", "am_fenrir", "am_puck"]]
## Accents for the voice server to use, by era.
const ACCENTS := [
	["a soft West Country English", "a broad Yorkshire", "a gentle Scottish", "a lilting Irish", "a warm Welsh", "a rustic Northumbrian"],
	["a lilting Irish", "a soft Scottish Highland", "a refined old-fashioned English", "a melodic Welsh", "a gentle Cornish", "a warm Manx"],
	["a crisp Australian", "a relaxed Californian", "a clipped London", "a neutral transatlantic", "a South African", "a New Zealand"],
]

static var _voices: Array = []
static var _scanned := false
static var _out: VoiceOut

static func available() -> bool:
	var e := AI.voice_engine()
	return e == "ai" or (e == "system" and not _list().is_empty())

## English voices, best first (the dialogue is English), else whatever the system has.
static func _list() -> Array:
	if not _scanned:
		_scanned = true
		if DisplayServer.get_name() != "headless":
			var all: Array = DisplayServer.tts_get_voices()
			for v in all:
				if String(v.get("language", "")).begins_with("en"):
					_voices.append(v)
			if _voices.is_empty():
				_voices = all
			_voices.sort_custom(func(a, b): return _quality(a) > _quality(b))
	return _voices

static func _quality(v: Dictionary) -> int:
	var n := String(v.get("name", "")).to_lower()
	for w in NATURAL_WORDS:
		if n.contains(w):
			return 1
	return 0

static func _sex_of(v: Dictionary) -> int:
	var n := String(v.get("name", "")).to_lower()
	for w in FEMALE:
		if n.contains(w):
			return 1
	for w in MALE:
		if n.contains(w):
			return 0
	return -1

## {id, pitch, rate} on this PC's voices, the same every time. Only the best quality tier
## is used, and pitch stays close to natural (shifting it is what sounds robotic).
static func voice_for(rec: Dictionary) -> Dictionary:
	var list := _list()
	if list.is_empty():
		return {}
	var fem: bool = rec["body"]["female"]
	var h := absi(hash(String(rec["id"])))
	var best := _quality(list[0])
	var fit: Array = []
	for v in list:
		if _quality(v) == best and _sex_of(v) == (1 if fem else 0):
			fit.append(v)
	if fit.is_empty():
		for v in list:
			if _sex_of(v) == (1 if fem else 0):
				fit.append(v)
	var pitch := 0.97 + float(h % 7) / 100.0
	if fit.is_empty():
		fit = list
		# Only one kind of voice on this PC: shift the pitch to tell people apart.
		pitch = (1.15 if fem else 0.85) + float(h % 9) / 100.0
	var v: Dictionary = fit[h % fit.size()]
	var age := int(rec.get("age", 35))
	if age > 55:
		pitch -= 0.04
	elif age < 25:
		pitch += 0.03
	return {"id": v["id"], "pitch": clampf(pitch, 0.6, 1.5), "rate": _pace(rec)}

static func _pace(rec: Dictionary) -> float:
	var t: Dictionary = rec["traits"]
	var rate := 0.97 + float(t["diligent"]) * 0.06 + float(t["curious"]) * 0.05
	if int(rec.get("age", 35)) > 60:
		rate -= 0.06
	match String(rec.get("mood", "calm")):
		"afraid": rate += 0.12
		"angry": rate += 0.06
		"sad": rate -= 0.08
	return clampf(rate, 0.75, 1.3)

## {voice, instructions, speed} on the voice server for this person.
static func natural_for(rec: Dictionary) -> Dictionary:
	var model := String(AI.tts_target().get("model", ""))
	var pool: Array = KOKORO_VOICES
	if model.begins_with("gpt-4o"):
		pool = OPENAI_VOICES
	elif model.begins_with("tts-1"):
		pool = OPENAI_TTS1
	var fem: bool = rec["body"]["female"]
	var h := absi(hash(String(rec["id"])))
	var voices: Array = pool[0 if fem else 1]
	if pool == KOKORO_VOICES and int(rec.get("era", 0)) < 2:
		voices = voices.filter(func(v): return String(v).begins_with("b")) # British voices for the old worlds
	return {"voice": voices[h % voices.size()], "instructions": manner(rec), "speed": _pace(rec)}

## How this person sounds, for voice models that take directions.
static func manner(rec: Dictionary) -> String:
	var t: Dictionary = rec["traits"]
	var accents: Array = ACCENTS[clampi(int(rec.get("era", 0)), 0, 2)]
	var accent: String = accents[absi(hash(String(rec["id"]) + "accent")) % accents.size()]
	var tone := "warm and easy-going" if float(t["friendly"]) > 0.6 else ("gruff and guarded" if float(t["friendly"]) < 0.3 else "plain and matter-of-fact")
	if float(t["brave"]) > 0.75:
		tone += ", confident"
	elif float(t["brave"]) < 0.25:
		tone += ", a little timid"
	var age := int(rec.get("age", 35))
	var who := "an older %s" % ("woman" if rec["body"]["female"] else "man") if age > 55 else ("a young %s" % ("woman" if rec["body"]["female"] else "man") if age < 25 else "a %s" % ("woman" if rec["body"]["female"] else "man"))
	var mood := String(rec.get("mood", "calm"))
	var feel: String = {"afraid": " Right now you are frightened and a bit breathless.", "angry": " Right now you are annoyed and sharp.",
		"sad": " Right now you are low and subdued.", "happy": " Right now you are in high spirits."}.get(mood, "")
	return "You are %s, a %s, speaking with %s accent. Your manner is %s.%s Talk naturally and conversationally, like a real person chatting face to face, with natural pauses and flow; never like an announcer or narrator." % [
		who, rec["job"], accent, tone, feel]

static func _player() -> VoiceOut:
	if _out == null or not is_instance_valid(_out):
		_out = VoiceOut.new()
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_out)
	return _out

## Says `text` as this person. `dist`: how far they are (quieter further off; past 28 m
## not at all). `interrupt` cuts off whoever is talking (a conversation always does);
## without it a passer-by only speaks if nobody else is. `after` waits for the current
## line to finish instead. `node`: where the voice comes from. Stage directions such as
## "*winks*" are not read out.
static func speak(rec: Dictionary, text: String, dist := 0.0, interrupt := true, node: Node3D = null, after := false) -> void:
	if not available() or dist > 28.0:
		return
	text = clean(text)
	if text == "":
		return
	if AI.voice_engine() == "ai":
		_player().say(rec, text, dist, interrupt, node, after)
		return
	if not interrupt and not after and DisplayServer.tts_is_speaking():
		return
	var v := voice_for(rec)
	if v.is_empty():
		return
	var vol := int(float(AI.get_value("voice_volume")) * clampf(1.0 - dist / 30.0, 0.15, 1.0))
	DisplayServer.tts_speak(text, v["id"], vol, v["pitch"], v["rate"], 0, interrupt and not after)

static func clean(text: String) -> String:
	text = RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)|\\[[^\\]]*\\]").sub(text, "", true)
	return RegEx.create_from_string("\\s+([.,!?;:])").sub(text, "$1", true).strip_edges()

## Fetches these lines ahead of time so they play the moment they are needed.
static func prefetch(rec: Dictionary, lines: Array) -> void:
	if AI.voice_engine() == "ai":
		for l in lines:
			if String(l) != "":
				_player().fetch(rec, clean(l))

static func is_speaking() -> bool:
	if AI.voice_engine() == "ai":
		return _out != null and is_instance_valid(_out) and _out.busy()
	return not _list().is_empty() and DisplayServer.tts_is_speaking()

static func hush() -> void:
	if _out != null and is_instance_valid(_out):
		_out.stop_all()
	if not _list().is_empty():
		DisplayServer.tts_stop()
