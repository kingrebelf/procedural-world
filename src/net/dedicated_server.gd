extends Node
## The dedicated server process (Net starts it for --server or a "server" build): reads
## server.cfg and the flags, opens the world, listens, and runs admin commands typed on
## standard input. See docs/SERVER.md.

var host: ServerHost
var _stdin: Thread
var _lines: Array = []
var _lock := Mutex.new()
var _stopping := false

func _ready() -> void:
	Engine.max_fps = 30 # a server has nothing to draw
	var args := OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args():
		if a.begins_with("--") and not args.has(a):
			args.append(a)
	var base := _base_dir()
	var cfg := ServerConfig.load_from(args, base)
	host = ServerHost.new()
	host.name = "Host"
	add_child(host)
	host.stop_requested.connect(_stop)
	var err := host.start(cfg)
	print("Procedural World server %s" % ProjectSettings.get_setting("application/config/version", ""))
	if err != OK:
		printerr("Could not start the server on port %d: %s" % [cfg.port, error_string(err)])
		get_tree().quit(1)
		return
	print("%s: listening on UDP port %d, world '%s' in %s" % [cfg.name, cfg.port, cfg.world, host.root])
	print("Settings: %s. Type help for commands." % (cfg.path if cfg.path != "" else "flags only"))
	if OS.get_stdin_type() != OS.STD_HANDLE_INVALID and not args.has("--no-console"):
		_stdin = Thread.new()
		_stdin.start(_read_stdin)

## Where server.cfg and the worlds folder live by default: beside the executable, or
## the user data folder ("server") when run from source.
static func _base_dir() -> String:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return OS.get_user_data_dir().path_join("server")
	var exe := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "macOS" and exe.ends_with(".app/Contents/MacOS"):
		# Keep the data next to the .app, not inside it.
		exe = exe.get_base_dir().get_base_dir().get_base_dir()
	return exe

func _read_stdin() -> void:
	var empty := 0
	while not _stopping:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			empty += 1
			# End of input (no terminal): stop listening rather than spin.
			if empty > 20:
				return
			OS.delay_msec(100)
			continue
		empty = 0
		_lock.lock()
		var last := ""
		for l in line.split("\n"):
			_lines.append(l.strip_edges())
			last = l.strip_edges().to_lower()
		_lock.unlock()
		if last in ["stop", "quit", "exit"]:
			return

func _process(_delta: float) -> void:
	_lock.lock()
	var lines := _lines
	_lines = []
	_lock.unlock()
	for l in lines:
		if l != "":
			print(host.run_command(l))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop()

func _stop() -> void:
	if _stopping:
		return
	_stopping = true
	host.say_log("Saving and stopping...")
	host.stop()
	await get_tree().create_timer(0.5).timeout
	host.save()
	if _stdin != null and not _stdin.is_alive():
		_stdin.wait_to_finish()
	print("Stopped.")
	get_tree().quit(0)
