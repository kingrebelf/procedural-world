extends Node
## Crash breadcrumbs. Godot already writes everything printed, every error and its own
## crash backtrace to user://logs/godot.log (on Windows %APPDATA%\ProceduralWorld\logs);
## this adds what that log can't know: the machine, where the player was and which way
## they were heading, and which chunk jobs were running when the game died.
##
## A marker file says a session is running. If it is still there at the next start, the
## last session crashed, and its log is copied to user://logs/last_crash.log so there is
## one fixed file to send.

const LOG_DIR := "user://logs"
const MARKER := "user://logs/running.flag"
const CRASH_COPY := "user://logs/last_crash.log"
const BEAT := 3.0 ## seconds between position breadcrumbs

var _beat := 0.0
var _last_chunk := Vector2i(999999, 999999)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if FileAccess.file_exists(MARKER):
		_keep_crashed_log()
	var f := FileAccess.open(MARKER, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system())
	_header()

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

## A timestamped line in the log. Safe to call from worker threads.
func note(text: String) -> void:
	print("[%s] %s" % [Time.get_time_string_from_system(), text])

func _process(delta: float) -> void:
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
	note("%s pos (%.0f, %.0f, %.0f) chunk %s heading %s speed %.1f | fps %d, mem %.0f MB, vram %.0f MB, planet %d seed %d" % [
		"enter" if entered else "at", pos.x, pos.y, pos.z, k, _heading(p), _speed(p),
		Engine.get_frames_per_second(), OS.get_static_memory_usage() / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		Game.planet, Game.seed])

func _heading(p: Node3D) -> String:
	var fwd := -p.global_transform.basis.z
	var deg := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0) ## 0 = north (-Z), 90 = east (+X)
	return "%s (%d deg)" % [["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(deg / 45.0)) % 8], int(deg)]

func _speed(p: Node3D) -> float:
	if p is CharacterBody3D:
		return (p as CharacterBody3D).velocity.length()
	return 0.0

func _exit_tree() -> void:
	note("Clean exit.")
	DirAccess.remove_absolute(MARKER)
