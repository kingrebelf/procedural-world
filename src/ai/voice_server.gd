class_name VoiceServer
extends Node
## The game's built-in natural voices: a small voice program shipped beside the game in
## voices/ (tools/voice_server) that speaks with the Kokoro neural voice model, offline.
## It is started in the background when the game starts, on a random local port with a
## random token, and answers like any OpenAI-compatible voice server, so AI.speech and
## VoiceOut use it the same way. It runs below the game's priority and quits with it.

const STARTUP_TIMEOUT := 45.0 ## seconds to load the model before giving up
const POLL := 0.4

## "", "starting", "ready" or "failed".
var state := ""
var _pid := -1
var _port := 0
var _token := ""
var _tries := 0
var _restarts := 0
var _since := 0.0
var _poll_at := 0.0
var _http: HTTPRequest

signal settled(ok: bool)

## Where the voice pack is: PW_VOICES (for development), else voices/ beside the game.
static func dir() -> String:
	var env := OS.get_environment("PW_VOICES")
	if env != "":
		return env
	return OS.get_executable_path().get_base_dir().path_join("voices")

static func _binary() -> String:
	return dir().path_join("voice_server.exe" if OS.get_name() == "Windows" else "voice_server")

## Whether this install has the built-in voices.
static func present() -> bool:
	return FileAccess.file_exists(_binary()) and FileAccess.file_exists(dir().path_join("data/model.onnx"))

## Whether the built-in voices can be used now or soon (present, not given up on).
func usable() -> bool:
	return state != "failed" and present()

## {url, key, model} for AI.speech; starts the server if it isn't running yet.
func target() -> Dictionary:
	if not usable():
		return {}
	if state == "":
		start()
	return {"url": "http://127.0.0.1:%d/v1/audio/speech" % _port, "key": _token, "model": "builtin"}

## Waits until the server answers (true) or has failed (false).
func wait_ready() -> bool:
	if state == "":
		start()
	if state == "starting":
		await settled
	return state == "ready"

func start() -> void:
	if state == "starting" or state == "ready" or not present():
		return
	_tries += 1
	_port = 20000 + randi() % 40000
	_token = "%08x%08x" % [randi(), randi()]
	var threads := clampi(OS.get_processor_count() / 3, 2, 6)
	var args := PackedStringArray(["--dir", dir().path_join("data"), "--port", str(_port), "--token", _token,
		"--parent-pid", str(OS.get_process_id()), "--threads", str(threads)])
	_pid = OS.create_process(_binary(), args)
	if _pid <= 0:
		_fail("could not start %s" % _binary())
		return
	state = "starting"
	_since = 0.0
	_poll_at = 0.5
	set_process(true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _process(dt: float) -> void:
	if state != "starting":
		set_process(false)
		return
	_since += dt
	if _since > STARTUP_TIMEOUT or not OS.is_process_running(_pid):
		_stop()
		state = ""
		if _tries < 2:
			start() # maybe the port was taken: once more on another
		else:
			_fail("the voice program did not start")
		return
	if _http == null and _since >= _poll_at:
		_poll_at = _since + POLL
		_http = HTTPRequest.new()
		_http.timeout = 2.0
		add_child(_http)
		_http.request_completed.connect(_on_health)
		if _http.request("http://127.0.0.1:%d/health" % _port) != OK:
			_http.queue_free()
			_http = null

func _on_health(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	_http = null
	if state != "starting" or result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if d is Dictionary and String(d.get("token", "")) == _token:
		state = "ready"
		set_process(false)
		settled.emit(true)

## After a failed line: if the voice program has died, start it again next time (twice at
## most; after that this PC's voices take over).
func check() -> void:
	if state == "ready" and not OS.is_process_running(_pid):
		state = "" if _restarts < 2 else "failed"
		_restarts += 1
		_tries = 0

func _fail(why: String) -> void:
	push_warning("Built-in voices: " + why)
	state = "failed"
	set_process(false)
	settled.emit(false)

func _stop() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop()
