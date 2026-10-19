extends Node
## Crash breadcrumbs. Godot already writes everything printed, every error and its own
## crash backtrace to user://logs/godot.log (on Windows %APPDATA%\ProceduralWorld\logs);
## this adds what that log can't know: the machine, where the player was and which way
## they were heading, and which chunk jobs were running when the game died.
##
## A marker file says a session is running. If it is still there at the next start, the
## last session crashed, and its log is copied to user://logs/last_crash.log so there is
## one fixed file to send.
##
## A watchdog thread notes when the main thread stops ticking (a freeze or deadlock) and
## which chunk jobs were running at the time, and when one job runs unusually long.

const LOG_DIR := "user://logs"
const MARKER := "user://logs/running.flag"
const CRASH_COPY := "user://logs/last_crash.log"
const BEAT := 3.0 ## seconds between position breadcrumbs

var _beat := 0.0
var _last_chunk := Vector2i(999999, 999999)
var _tick := 0 ## last main-thread frame, msec; read by the watchdog
var _jobs: Dictionary = {} ## "chunk (x, y) mode" -> start msec, under _lock
var _lock := Mutex.new()
var _watchdog: Thread
var _stop := false
var crashed_last_time := false ## the main menu offers the log folder when true
var _where := "menu" ## last breadcrumb line, for the watchdog

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if FileAccess.file_exists(MARKER):
		crashed_last_time = true
		_keep_crashed_log()
	var f := FileAccess.open(MARKER, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())
	_header()
	get_tree().scene_changed.connect(_on_scene_changed)
	_tick = Time.get_ticks_msec()
	_watchdog = Thread.new()
	_watchdog.start(_watch)

func _on_scene_changed() -> void:
	var sc := get_tree().current_scene
	note("scene %s" % (sc.scene_file_path if sc else "none"))

## Key and button presses, by action name: the last thing done before a crash.
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton) \
			or not e.is_pressed() or e.is_echo():
		return
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_") and e.is_action_pressed(a):
			note("input %s" % a)
			return

## Chunk job breadcrumbs, from the streamer's worker threads.
func job_start(what: String) -> void:
	_lock.lock()
	_jobs[what] = Time.get_ticks_msec()
	_lock.unlock()
	note("%s start" % what)

func job_done(what: String) -> void:
	_lock.lock()
	var t: int = _jobs.get(what, Time.get_ticks_msec())
	_jobs.erase(what)
	_lock.unlock()
	note("%s done %d ms" % [what, Time.get_ticks_msec() - t])

func _running_jobs(now: int) -> String:
	_lock.lock()
	var out := PackedStringArray()
	for w in _jobs:
		out.append("%s (%.1f s)" % [w, (now - int(_jobs[w])) / 1000.0])
	_lock.unlock()
	return ", ".join(out) if out.size() > 0 else "none"

## Watchdog thread: reports a main thread that has stopped ticking, and stuck jobs.
func _watch() -> void:
	var stalled := false
	var next_mem := 0
	var flagged: Dictionary = {}
	while not _stop:
		OS.delay_msec(250)
		var now := Time.get_ticks_msec()
		var idle := now - _tick
		if idle > 1000 and not stalled:
			stalled = true
			next_mem = now + 1000
			note("WATCHDOG main thread not responding for %.1f s; last %s; %s; chunk jobs running: %s" % [
				idle / 1000.0, _where, _ram(), _running_jobs(now)])
		elif stalled and idle > 1000 and now >= next_mem:
			# Memory running away during a freeze points at a runaway loop.
			next_mem = now + 1000
			note("WATCHDOG still frozen %.1f s; %s" % [idle / 1000.0, _ram()])
		elif idle < 500 and stalled:
			stalled = false
			note("WATCHDOG main thread responding again")
		_lock.lock()
		var slow := PackedStringArray()
		for w in _jobs:
			if now - int(_jobs[w]) > 15000 and not flagged.has(w):
				flagged[w] = true
				slow.append(w)
		_lock.unlock()
		for w in slow:
			note("WATCHDOG %s still running after 15 s" % w)

func _header() -> void:
	note("Procedural World %s, %s" % [ProjectSettings.get_setting("application/config/version", "?"),
		Time.get_datetime_string_from_system()])
	note("OS %s %s, %s, %d threads, locale %s" % [OS.get_name(), OS.get_version(), OS.get_processor_name(),
		OS.get_processor_count(), OS.get_locale()])
	note("Godot %s, %s build" % [Engine.get_version_info().get("string", "?"), "debug" if OS.is_debug_build() else "release"])
	var rd := RenderingServer.get_rendering_device()
	note("GPU %s (%s), driver %s, renderer %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?") if rd else "compatibility/headless"])
	note("Screen %s, args %s" % [DisplayServer.screen_get_size(), " ".join(OS.get_cmdline_args() + OS.get_cmdline_user_args())])

## Copies the newest rotated log (the session that died) to last_crash.log.
func _keep_crashed_log() -> void:
	var newest := ""
	var newest_t := 0
	for name in DirAccess.get_files_at(LOG_DIR):
		if not name.begins_with("godot") or not name.ends_with(".log") or name == "godot.log":
			continue
		var t := FileAccess.get_modified_time(LOG_DIR.path_join(name))
		if t >= newest_t:
			newest_t = t
			newest = name
	if newest == "":
		note("The last session did not exit cleanly, but its log was not found.")
		return
	DirAccess.copy_absolute(LOG_DIR.path_join(newest), CRASH_COPY)
	note("The last session did not exit cleanly; its log %s is copied to %s" % [newest,
		ProjectSettings.globalize_path(CRASH_COPY)])

func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(LOG_DIR))

## A timestamped line in the log. Safe to call from worker threads.
func note(text: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), text])

func _process(delta: float) -> void:
	_tick = Time.get_ticks_msec()
	var p: Node3D = Game.player if is_instance_valid(Game.player) else null
	if p == null or not p.is_inside_tree():
		return
	var pos := p.global_position
	var k := Vector2i(floori(pos.x / ChunkGenerator.SIZE), floori(pos.z / ChunkGenerator.SIZE))
	_beat -= delta
	if k == _last_chunk and _beat > 0.0:
		return
	_beat = BEAT
	var entered := k != _last_chunk
	_last_chunk = k
	_where = "pos (%.0f, %.0f, %.0f) chunk %s heading %s" % [pos.x, pos.y, pos.z, k, _heading(p)]
	note("%s pos (%.0f, %.0f, %.0f) chunk %s heading %s speed %.1f | fps %d, %s, vram %.0f MB, planet %d seed %d" % [
		"enter" if entered else "at", pos.x, pos.y, pos.z, k, _heading(p), _speed(p),
		Engine.get_frames_per_second(), _ram(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		Game.planet, Game.seed])

## The machine's free memory (the game's own isn't counted in release builds).
func _ram() -> String:
	var m := OS.get_memory_info()
	return "RAM free %.1f of %.1f GB" % [float(m.get("available", -1)) / 1073741824.0, float(m.get("physical", -1)) / 1073741824.0]

func _heading(p: Node3D) -> String:
	var fwd := -p.global_transform.basis.z
	var deg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0) ## 0 = north (-Z), 90 = east (+X)
	return "%s (%d deg)" % [["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(deg / 45.0)) % 8], int(deg)]

func _speed(p: Node3D) -> float:
	if p is CharacterBody3D:
		return (p as CharacterBody3D).velocity.length()
	return 0.0

func _exit_tree() -> void:
	_stop = true
	if _watchdog and _watchdog.is_started():
		_watchdog.wait_to_finish()
	note("Clean exit.")
	DirAccess.remove_absolute(MARKER)
