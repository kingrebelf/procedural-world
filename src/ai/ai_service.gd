extends Node
## AI service (autoload "AI"): connects NPC minds to a language model of the player's
## choice, and to an optional external fast-decision service.
##
## Providers speak one of two wire formats:
##   "openai"    POST {base}/chat/completions (OpenAI, Strata, Ollama, LM Studio,
##               llama.cpp server, vLLM, OpenRouter, anything OpenAI-compatible)
##   "anthropic" POST {base}/messages (Anthropic Claude API, or Strata's /v1/messages)
## With provider "off" every NPC still works: the built-in dialogue and the built-in
## decision engine need no network at all.
##
## The configuration, including any API key, is stored encrypted in user://ai.cfg with a
## key derived from this machine, so copying the file elsewhere does not leak the key.

signal config_changed
signal status_changed(text: String)

const PATH := "user://ai.cfg"

const PRESETS := {
	"off": {"label": "Off (built-in dialogue)", "format": "", "base_url": "", "model": "", "needs_key": false},
	"strata": {"label": "Strata (local)", "format": "openai", "base_url": "http://127.0.0.1:8080/v1", "model": "local", "needs_key": false},
	"ollama": {"label": "Ollama (local)", "format": "openai", "base_url": "http://127.0.0.1:11434/v1", "model": "llama3.1:8b", "needs_key": false},
	"lmstudio": {"label": "LM Studio (local)", "format": "openai", "base_url": "http://127.0.0.1:1234/v1", "model": "local-model", "needs_key": false},
	"anthropic": {"label": "Anthropic Claude API", "format": "anthropic", "base_url": "https://api.anthropic.com/v1", "model": "claude-haiku-5-5", "needs_key": true},
	"openai": {"label": "OpenAI API", "format": "openai", "base_url": "https://api.openai.com/v1", "model": "gpt-5-mini", "needs_key": true},
	"openrouter": {"label": "OpenRouter", "format": "openai", "base_url": "https://openrouter.ai/api/v1", "model": "openrouter/auto", "needs_key": true},
	"custom": {"label": "Custom (OpenAI-compatible)", "format": "openai", "base_url": "http://127.0.0.1:8000/v1", "model": "", "needs_key": false},
}
const PROVIDER_ORDER := ["off", "strata", "ollama", "lmstudio", "anthropic", "openai", "openrouter", "custom"]

const DEFAULTS := {
	"provider": "off", "format": "", "base_url": "", "api_key": "", "model": "",
	"temperature": 0.8, "max_tokens": 400, "timeout": 30.0,
	"json_mode": true, ## Ask OpenAI-format servers for a JSON object reply.
	"dialogue": true, ## Use the model for conversations.
	"background_thinking": true, ## Let nearby NPCs pick goals with the model now and then.
	"think_interval": 120.0, ## Seconds between an NPC's background thoughts.
	"max_rpm": 12, ## Hard cap on model requests per minute (protects API budgets).
	"decide_url": "", ## Optional external fast-decision endpoint.
	"decide_key": "",
	"decide_timeout": 1.5,
}

const MAX_CONCURRENT := 2

var cfg: Dictionary = DEFAULTS.duplicate()
var last_status := ""
var stats := {"requests": 0, "failures": 0, "last_latency_ms": 0}

var _active := 0
var _recent: Array = [] ## Unix times of recent model requests (rate limiting).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()

# --- Configuration -------------------------------------------------------------------

func _pass() -> String:
	var id := OS.get_unique_id()
	if id == "":
		id = OS.get_name() + ":" + OS.get_model_name()
	return ("procedural-world:" + id).sha256_text()

func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load_encrypted_pass(PATH, _pass()) != OK:
		return
	for k in DEFAULTS:
		cfg[k] = cf.get_value("ai", k, DEFAULTS[k])

func save_config() -> void:
	var cf := ConfigFile.new()
	for k in cfg:
		cf.set_value("ai", k, cfg[k])
	cf.save_encrypted_pass(PATH, _pass())
	config_changed.emit()

func get_value(k: String):
	return cfg.get(k, DEFAULTS.get(k))

func set_value(k: String, v) -> void:
	cfg[k] = v
	save_config()

## Switching provider fills in its address and default model; the key is kept only if
## the new provider also needs one, so a cloud key is never sent to a local server.
func use_provider(id: String) -> void:
	if not PRESETS.has(id):
		return
	var p: Dictionary = PRESETS[id]
	cfg["provider"] = id
	cfg["format"] = p["format"]
	cfg["base_url"] = p["base_url"]
	cfg["model"] = p["model"]
	if not p["needs_key"]:
		cfg["api_key"] = ""
	save_config()

func enabled() -> bool:
	return cfg["provider"] != "off" and cfg["format"] != "" and String(cfg["base_url"]) != ""

func dialogue_enabled() -> bool:
	return enabled() and bool(cfg["dialogue"])

func thinking_enabled() -> bool:
	return enabled() and bool(cfg["background_thinking"])

func decide_enabled() -> bool:
	return String(cfg["decide_url"]).strip_edges() != ""

func provider_label() -> String:
	return PRESETS.get(cfg["provider"], PRESETS["off"])["label"]

# --- Rate limiting ---------------------------------------------------------------------

func _now() -> float:
	return Time.get_unix_time_from_system()

## True if a request may start now. Background work asks with reserve > 0 so it always
## leaves headroom for conversations the player is actually having.
func has_budget(reserve: int = 0) -> bool:
	var t := _now()
	while not _recent.is_empty() and t - _recent[0] > 60.0:
		_recent.pop_front()
	return _recent.size() + reserve < int(cfg["max_rpm"]) and _active < MAX_CONCURRENT

# --- Chat --------------------------------------------------------------------------------

## Builds the HTTP request for the configured provider. Pure, so it is unit-tested.
## messages: [{role: "user"|"assistant", content: String}]
static func build_request(c: Dictionary, system: String, messages: Array) -> Dictionary:
	var base := String(c["base_url"]).strip_edges().trim_suffix("/")
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := String(c.get("api_key", "")).strip_edges()
	var body: Dictionary
	var url: String
	if c["format"] == "anthropic":
		url = base + "/messages"
		headers.append("anthropic-version: 2023-06-01")
		if key != "":
			headers.append("x-api-key: " + key)
		body = {"model": c["model"], "max_tokens": int(c["max_tokens"]), "system": system, "messages": messages}
		# Short, in-character replies: keep thinking effort low for latency and cost.
		if String(c["model"]).begins_with("claude-"):
			body["output_config"] = {"effort": "low"}
	else:
		url = base + "/chat/completions"
		if key != "":
			headers.append("Authorization: Bearer " + key)
		var msgs: Array = [{"role": "system", "content": system}]
		msgs.append_array(messages)
		body = {"messages": msgs, "max_tokens": int(c["max_tokens"]), "temperature": float(c["temperature"]), "stream": false}
		if String(c["model"]) != "":
			body["model"] = c["model"]
		if c.get("json_mode", false):
			body["response_format"] = {"type": "json_object"}
	return {"url": url, "headers": headers, "body": JSON.stringify(body)}

## Extracts the reply text from either wire format. Returns {ok, text, error}.
static func parse_response(format: String, code: int, raw: String) -> Dictionary:
	var data = JSON.parse_string(raw) if raw != "" else null
	if code < 200 or code >= 300:
		var msg := "HTTP %d" % code
		if data is Dictionary and data.get("error") != null:
			var e = data["error"]
			msg += ": " + (String(e.get("message", "")) if e is Dictionary else str(e))
		return {"ok": false, "text": "", "error": msg}
	if not (data is Dictionary):
		return {"ok": false, "text": "", "error": "Reply was not JSON"}
	var text := ""
	if format == "anthropic":
		if data.get("stop_reason", "") == "refusal":
			return {"ok": false, "text": "", "error": "The model declined to answer"}
		for b in data.get("content", []):
			if b is Dictionary and b.get("type", "") == "text":
				text += String(b.get("text", ""))
	else:
		var ch: Array = data.get("choices", [])
		if not ch.is_empty() and ch[0] is Dictionary:
			var m = ch[0].get("message", {})
			if m is Dictionary:
				text = String(m.get("content", "") if m.get("content") != null else "")
	if text.strip_edges() == "":
		return {"ok": false, "text": "", "error": "Empty reply"}
	return {"ok": true, "text": text, "error": ""}

## Finds the first JSON object in model output, tolerating code fences and chatter.
static func extract_json(text: String):
	var t := text.strip_edges()
	var a := t.find("{")
	if a < 0:
		return null
	var depth := 0
	var in_str := false
	var esc := false
	for i in range(a, t.length()):
		var ch := t[i]
		if in_str:
			if esc:
				esc = false
			elif ch == "\\":
				esc = true
			elif ch == "\"":
				in_str = false
		elif ch == "\"":
			in_str = true
		elif ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				var v = JSON.parse_string(t.substr(a, i - a + 1))
				return v if v is Dictionary else null
	return null

## Sends one chat request. Always returns {ok, text, error}; never throws.
func chat(system: String, messages: Array, background: bool = false) -> Dictionary:
	if not enabled():
		return {"ok": false, "text": "", "error": "AI is off"}
	if background and not has_budget(3):
		return {"ok": false, "text": "", "error": "Rate limited"}
	while _active >= MAX_CONCURRENT:
		await get_tree().process_frame
	_recent.append(_now())
	_active += 1
	var req := build_request(cfg, system, messages)
	var http := HTTPRequest.new()
	http.timeout = float(cfg["timeout"])
	add_child(http)
	var t0 := Time.get_ticks_msec()
	var err := http.request(req["url"], req["headers"], HTTPClient.METHOD_POST, req["body"])
	var out: Dictionary
	if err != OK:
		out = {"ok": false, "text": "", "error": "Could not start request (%s)" % error_string(err)}
	else:
		var res: Array = await http.request_completed
		var result: int = res[0]
		if result != HTTPRequest.RESULT_SUCCESS:
			out = {"ok": false, "text": "", "error": _result_text(result)}
		else:
			out = parse_response(cfg["format"], res[1], (res[3] as PackedByteArray).get_string_from_utf8())
	http.queue_free()
	_active -= 1
	stats["requests"] += 1
	stats["last_latency_ms"] = Time.get_ticks_msec() - t0
	if not out["ok"]:
		stats["failures"] += 1
		_set_status("Last request failed: " + out["error"])
	else:
		_set_status("Connected to %s (%d ms)" % [provider_label(), stats["last_latency_ms"]])
	return out

## chat() plus JSON extraction. Returns {ok, data, text, error}.
func chat_json(system: String, messages: Array, background: bool = false) -> Dictionary:
	var r: Dictionary = await chat(system, messages, background)
	if not r["ok"]:
		return {"ok": false, "data": {}, "text": "", "error": r["error"]}
	var d = extract_json(r["text"])
	if d == null:
		# Some small local models ignore the format; keep their words as speech.
		return {"ok": true, "data": {"say": r["text"].strip_edges().left(400)}, "text": r["text"], "error": ""}
	return {"ok": true, "data": d, "text": r["text"], "error": ""}

func test_connection() -> Dictionary:
	var sys := "You are a connection test for a video game. Reply with a JSON object only."
	var r: Dictionary = await chat_json(sys, [{"role": "user", "content": "Reply with {\"say\": \"ready\"}."}])
	if r["ok"]:
		return {"ok": true, "message": "Connected to %s in %d ms. Model said: %s" % [provider_label(), stats["last_latency_ms"], String(r["data"].get("say", r["text"])).left(80)]}
	return {"ok": false, "message": "Could not connect: " + r["error"]}

func _result_text(r: int) -> String:
	match r:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Cannot connect to %s (is the server running?)" % cfg["base_url"]
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve host"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake failed"
		HTTPRequest.RESULT_TIMEOUT:
			return "Timed out after %ds" % int(cfg["timeout"])
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response"
	return "Request failed (%d)" % r

func _set_status(t: String) -> void:
	last_status = t
	status_changed.emit(t)

# --- External fast decisions --------------------------------------------------------------

## Asks the external decision service what each NPC should do next. The contract is
## documented in docs/AI.md. Returns {npc_id: {action, target?, say?}} or {} on any
## failure, in which case the built-in engine's choices stand.
func decide_external(npcs: Array, context: Dictionary) -> Dictionary:
	if not decide_enabled():
		return {}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := String(cfg["decide_key"]).strip_edges()
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var body := JSON.stringify({"version": 1, "context": context, "actions": DecisionEngine.ACTIONS, "npcs": npcs})
	var http := HTTPRequest.new()
	http.timeout = float(cfg["decide_timeout"])
	add_child(http)
	var out := {}
	if http.request(String(cfg["decide_url"]).strip_edges(), headers, HTTPClient.METHOD_POST, body) == OK:
		var res: Array = await http.request_completed
		if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] >= 200 and res[1] < 300:
			out = parse_decisions((res[3] as PackedByteArray).get_string_from_utf8())
	http.queue_free()
	return out

static func parse_decisions(raw: String) -> Dictionary:
	var d = JSON.parse_string(raw)
	var out := {}
	if not (d is Dictionary) or not (d.get("decisions") is Array):
		return out
	for e in d["decisions"]:
		if e is Dictionary and e.has("id") and DecisionEngine.ACTIONS.has(String(e.get("action", ""))):
			out[String(e["id"])] = e
	return out
