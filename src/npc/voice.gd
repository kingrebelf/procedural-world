class_name Voice
## Spoken lines for people. Engines (Settings > AI > Voices):
##   built-in natural voices: the Kokoro neural voices shipped with the game (VoiceServer),
##            offline and with no setup. Every person gets their own mix of voices for their
##            sex and age, a regional accent, a pitch and a pace (builtin_for).
##   voice server: an OpenAI-compatible one (OpenAI's gpt-4o-mini-tts, or a local Kokoro /
##            speaches server). Each person gets a voice and an accent that fits their era
##            and temperament.
##   system   this PC's own text-to-speech voices, offline. The best installed voices are
##            preferred (Natural, Neural, Enhanced, Premium) and accents are spread around.
## Natural voices are heard from where the person stands. Each person keeps the same voice.
## Lines queue so a quick "Hmm..." is never cut off by the answer that follows it.

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

## Built-in voices: eSpeak NG accents the words are sounded out in.
const RP := "en-GB-x-rp" ## received pronunciation: the gentry, clergy, scholars
## Regional accents of the old (medieval) lands; neighbouring towns share one.
const OLD_REGIONS := ["en", "en-GB-x-gbclan", "en-GB-scotland", "en-GB-x-gbcwmd", "en", "en-GB-x-gbclan", "en-GB-scotland"]
## Accents heard out on the frontier, most common first.
const FRONTIER := ["en-US", "en-US", "en-US", "en-US-nyc", "en-029", "en", RP, "en-GB-scotland"]
## Which voices of the catalog suit each era: accent family -> weight.
const FAMILY_WEIGHTS := [
	{"gb": 6.0, "mid": 3.0, "fr": 0.4, "it": 0.4, "es": 0.3, "pt": 0.3},
	{"gb": 5.0, "mid": 3.0, "fr": 1.0, "it": 0.8, "in": 0.5, "pt": 0.5},
	{"us": 4.0, "mid": 3.0, "gb": 2.0, "in": 0.8, "es": 0.8, "pt": 0.6, "it": 0.5, "fr": 0.5},
]
const POSH_JOBS := ["priest", "scribe", "noble", "lord", "lady", "mayor", "magistrate", "scholar", "physician", "captain", "data broker", "reeve", "steward"]
const CATALOG := "res://assets/voices/catalog.json"

static var _catalog: Array = []
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

## {voice, instructions, speed, pitch} on the natural voice engine in use for this person.
static func natural_for(rec: Dictionary) -> Dictionary:
	var model := String(AI.tts_target().get("model", ""))
	if model == "builtin":
		return builtin_for(rec)
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

## The built-in voice table (assets/voices/catalog.json): [{mix, accent, sex, pitch}].
static func catalog() -> Array:
	if _catalog.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if d is Dictionary:
			_catalog = d["voices"]
	return _catalog

## Whether `rec` is a child (newer worlds mark them; else by age).
static func is_child(rec: Dictionary) -> bool:
	return bool(rec.get("child", false)) or int(rec.get("age", 35)) < 13

## This person's built-in voice: {voice: "<number>@<accent>", speed, pitch}. The same
## every time. People of one town get different voices (their place in the town picks
## from a town-shuffled list); age and build set the pitch (children and teens higher,
## old folk lower and slower), and the accent comes from the region, the era and the job.
## The voice is generated at speed/pitch and played back at `pitch`, so the pace stays
## right while the voice gets lighter or deeper.
static func builtin_for(rec: Dictionary) -> Dictionary:
	var cat := catalog()
	if cat.is_empty():
		return {"voice": "0", "speed": 1.0, "pitch": 1.0}
	var id := String(rec["id"])
	var parts := id.split("_")
	var town := "_".join(parts.slice(0, 2)) if parts.size() >= 3 else id
	var idx := int(parts[2]) if parts.size() >= 3 and parts[2].is_valid_int() else absi(hash(id))
	var h := absi(hash(id + "voice"))
	var era := clampi(int(rec.get("era", 0)), 0, 2)
	var fem: bool = rec["body"]["female"]
	var age := int(rec.get("age", 35))
	var child := is_child(rec)
	# Which voices fit: the sex (children of both sexes use light voices) and pitch band.
	var fits: Array = []
	for i in cat.size():
		var v: Dictionary = cat[i]
		var p := float(v["pitch"])
		var ok: bool
		if child:
			ok = v["sex"] == "f" and p >= (180.0 if fem else 170.0)
		elif age < 18:
			ok = (v["sex"] == "f" and p >= 170.0) if fem else (v["sex"] == "m" and p >= 120.0 and p < 170.0)
		elif age > 55 and not fem:
			ok = v["sex"] == "m" and p < 150.0
		else:
			ok = v["sex"] == ("f" if fem else "m")
		if ok:
			fits.append(i)
	if fits.is_empty():
		for i in cat.size():
			if cat[i]["sex"] == ("f" if fem else "m"):
				fits.append(i)
	# Shuffle them for this town, the era's accents first (weighted random keys), and
	# take this person's place in the town: neighbours rarely share a voice.
	var weights: Dictionary = FAMILY_WEIGHTS[era]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(town + "voices")
	var keyed: Array = []
	for i in fits:
		var w := float(weights.get(String(cat[i]["accent"]), 0.05))
		keyed.append([pow(rng.randf(), 1.0 / w), i])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	var sid: int = keyed[idx % keyed.size()][1]
	# Pitch (played back faster or slower) from age and build, with a touch of their own.
	var pitch := 0.97 + float(h % 61) / 1000.0
	if child:
		pitch = (1.2 if fem else 1.16) + float(h % 9) / 100.0
	elif age < 18:
		pitch = 1.05 + float(h % 6) / 100.0
	elif age > 64:
		pitch -= 0.05
	elif age > 50:
		pitch -= 0.025
	pitch -= (float(rec["body"].get("build", 1.0)) - 1.0) * 0.12
	if String(rec.get("race", "Human")) == "Vex":
		pitch -= 0.1
	pitch = clampf(pitch, 0.82, 1.32)
	var pace := _pace(rec)
	if age > 64:
		pace -= 0.05
	if child:
		pace += 0.04
	return {"voice": "%d@%s" % [sid, accent_for(rec, String(cat[sid]["accent"]))], "speed": snappedf(clampf(pace / pitch, 0.6, 1.5), 0.01), "pitch": snappedf(pitch, 0.01)}

## The eSpeak NG accent a built-in voice speaks in for this person.
static func accent_for(rec: Dictionary, family: String) -> String:
	var parts := String(rec["id"]).split("_")
	var h := absi(hash(String(rec["id"]) + "accent"))
	if family in ["fr", "it", "es", "pt", "in"]:
		return "en" if int(rec.get("era", 0)) < 2 else "en-US" # their own voice carries the accent
	if int(rec.get("era", 0)) >= 2:
		return FRONTIER[h % FRONTIER.size()] if family != "gb" else ["en", RP, "en-GB-scotland", "en-GB-x-gbclan"][h % 4]
	if String(rec.get("job", "")) in POSH_JOBS and h % 10 < 7:
		return RP
	# The old lands: the region's accent for most, someone from elsewhere now and then.
	var region := 0
	if parts.size() >= 3 and parts[0].is_valid_int() and parts[1].is_valid_int():
		region = absi(hash(Vector2i(floori(int(parts[0]) / 3.0), floori(int(parts[1]) / 3.0))))
	if h % 100 < 72:
		return OLD_REGIONS[region % OLD_REGIONS.size()]
	return OLD_REGIONS[(h / 100) % OLD_REGIONS.size()]

## A line split into its sentences, so the first can be spoken while the rest are made.
static func pieces(text: String) -> Array:
	var out: Array = []
	var cur := ""
	for m in RegEx.create_from_string("[^.!?]+[.!?]+[\"')]*\\s*|[^.!?]+$").search_all(text):
		cur += m.get_string()
		if cur.strip_edges().length() >= 12: # keep "Aye." with what follows
			out.append(cur.strip_edges())
			cur = ""
	if cur.strip_edges() != "":
		if out.is_empty():
			out.append(cur.strip_edges())
		else:
			out[-1] = String(out[-1]) + " " + cur.strip_edges()
	return out

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
		var ps := pieces(text) if interrupt or after else [text]
		for i in ps.size():
			_player().say(rec, ps[i], dist, interrupt and i == 0, node, after or i > 0)
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
			for p in pieces(clean(String(l))):
				_player().fetch(rec, p)

static func is_speaking() -> bool:
	if AI.voice_engine() == "ai":
		return _out != null and is_instance_valid(_out) and _out.busy()
	return not _list().is_empty() and DisplayServer.tts_is_speaking()

static func hush() -> void:
	if _out != null and is_instance_valid(_out):
		_out.stop_all()
	if not _list().is_empty():
		DisplayServer.tts_stop()
