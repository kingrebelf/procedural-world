class_name Voice
## Spoken lines for people, through this PC's own text-to-speech voices (Windows, macOS
## and Linux speech engines, via DisplayServer). Each person keeps one voice that suits
## them: a male or female voice where the system offers both, with pitch and pace from
## their age, temperament and mood. Nothing is sent anywhere.

const FEMALE := ["zira", "hazel", "susan", "eva", "catherine", "linda", "heather", "aria", "jenny", "sonia", "libby",
	"natasha", "clara", "emma", "samantha", "karen", "moira", "tessa", "fiona", "victoria", "female", "woman", "ava",
	"allison", "serena", "kate", "michelle", "michele", "nora", "salli", "joanna", "kimberly", "ivy", "amy"]
const MALE := ["david", "mark", "george", "ryan", "guy", "daniel", "alex", "fred", "richard", "james", "sean",
	"william", "male", "man", "tom", "aaron", "arthur", "oliver", "thomas", "brian", "matthew", "joey", "justin", "eric"]

static var _voices: Array = []
static var _scanned := false

static func available() -> bool:
	return bool(AI.get_value("voices")) and not _list().is_empty()

## English voices first (the dialogue is English), else whatever the system has.
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
	return _voices

static func _sex_of(v: Dictionary) -> int:
	var n := String(v.get("name", "")).to_lower()
	for w in FEMALE:
		if n.contains(w):
			return 1
	for w in MALE:
		if n.contains(w):
			return 0
	return -1

## {id, pitch, rate} for this person, the same every time.
static func voice_for(rec: Dictionary) -> Dictionary:
	var list := _list()
	if list.is_empty():
		return {}
	var fem: bool = rec["body"]["female"]
	var h := absi(hash(String(rec["id"])))
	var fit: Array = []
	for v in list:
		if _sex_of(v) == (1 if fem else 0):
			fit.append(v)
	var pitch := 0.9 + float(h % 21) / 100.0
	if fit.is_empty():
		fit = list
		# Only one kind of voice on this PC: shift the pitch to tell people apart.
		pitch = (1.2 if fem else 0.8) + float(h % 15) / 100.0
	var v: Dictionary = fit[h % fit.size()]
	var age := int(rec.get("age", 35))
	if age > 55:
		pitch -= 0.08
	elif age < 25:
		pitch += 0.06
	var t: Dictionary = rec["traits"]
	var rate := 0.92 + float(t["diligent"]) * 0.1 + float(t["curious"]) * 0.08
	match String(rec.get("mood", "calm")):
		"afraid": rate += 0.2; pitch += 0.08
		"angry": rate += 0.1; pitch -= 0.05
		"sad": rate -= 0.12; pitch -= 0.05
		"happy": rate += 0.05; pitch += 0.04
	return {"id": v["id"], "pitch": clampf(pitch, 0.5, 1.6), "rate": clampf(rate, 0.6, 1.5)}

## Says `text` as this person. `dist`: how far they are (quieter further off); `interrupt`
## cuts off whoever is talking (a conversation always does). Stage directions such as
## "*winks*" are not read out.
static func speak(rec: Dictionary, text: String, dist := 0.0, interrupt := true) -> void:
	if not available() or dist > 28.0:
		return
	text = RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)").sub(text, "", true).strip_edges()
	if text == "":
		return
	if not interrupt and DisplayServer.tts_is_speaking():
		return
	var v := voice_for(rec)
	if v.is_empty():
		return
	var vol := int(float(AI.get_value("voice_volume")) * clampf(1.0 - dist / 30.0, 0.15, 1.0))
	DisplayServer.tts_speak(text, v["id"], vol, v["pitch"], v["rate"], 0, interrupt)

static func hush() -> void:
	if not _list().is_empty():
		DisplayServer.tts_stop()
