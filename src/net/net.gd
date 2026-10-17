extends Node
## Multiplayer (autoload "Net"). Offline (solo) by default; a client of a dedicated
## server after join(); the server itself when launched with --server (DedicatedServer).
## Every RPC lives here so its node path (/root/Net) is the same on both ends. The
## server's side of each request is handled by `host` (ServerHost); see
## plans/multiplayer.md for who owns what.

signal join_failed(reason: String)
signal joined
signal left(reason: String) ## the connection ended (kicked, server stopped, lost)
signal chat(from: String, text: String, kind: String) ## kind: chat, server, join, leave, admin
signal players_changed
signal peer_state(peer: int) ## another player's position or look changed
signal options_changed

const DEFAULT_PORT := 24600
const STATE_HZ := 15.0
const CH_STATE := 1 ## unreliable movement
const CH_DATA := 2 ## chunks and settlements, so big transfers don't hold up chat
const PRUNE_RADIUS := 12 ## chunks a client keeps cached around itself (the server pushes edits within PUSH_RADIUS)

enum Mode {OFFLINE, CLIENT, SERVER}
var mode := Mode.OFFLINE

# --- Client ---
var store: RemoteStore
var info: Dictionary = {} ## the server's name, description, max players...
var options: Dictionary = {}
var my_pid := ""
var my_name := ""
var is_admin := false
## Other players, by peer id: {pid, name, planet, pos, yaw, pitch, anim, speed, shot, look, held, equip}
var peers: Dictionary = {}
var _joining := {}
var _state_t := 0.0
var _prune_t := 0.0
var _last_look := {}
var _leaving := false

# --- Server ---
var host: Object ## ServerHost while this process is a dedicated server

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if wants_server():
		_start_server.call_deferred()

## True when this process should be a dedicated server.
static func wants_server() -> bool:
	return OS.has_feature("server") or OS.get_cmdline_user_args().has("--server") or OS.get_cmdline_args().has("--server")

func _start_server() -> void:
	var ds: Node = load("res://src/net/dedicated_server.gd").new()
	ds.name = "DedicatedServer"
	var tree := get_tree()
	if tree.current_scene != null:
		tree.current_scene.queue_free()
	tree.root.add_child(ds)
	tree.current_scene = ds

func online() -> bool:
	return mode != Mode.OFFLINE

func is_server() -> bool:
	return mode == Mode.SERVER

func is_client() -> bool:
	return mode == Mode.CLIENT

## Your player id: "solo" offline, the server's id for you online.
func my_id() -> String:
	return my_pid if mode == Mode.CLIENT else "solo"

## A server option (ServerConfig.OPTIONS); its default offline.
func option(k: String):
	return options.get(k, ServerConfig.OPTIONS.get(k))

## Whether you may open or take what `owner_id` owns: nobody's, yours, or (with
## alliances) an ally's.
func may_access(owner_id: String) -> bool:
	if owner_id == "" or owner_id == my_id():
		return true
	return allied(owner_id)

## Whether you may hurt another player.
func may_hurt(pid: String) -> bool:
	return mode == Mode.CLIENT and bool(option("pvp")) and pid != my_pid and not allied(pid)

## Alliances arrive in a later stage; until then nobody is allied.
func allied(_pid: String) -> bool:
	return false

func player_name(pid: String) -> String:
	if pid == my_id():
		return my_name if my_name != "" else "You"
	for p in peers.values():
		if p["pid"] == pid:
			return p["name"]
	return pid

## Your character's look. Online every player gets their own, made from their id, so
## you look the same to yourself and to everyone else.
func my_look() -> Dictionary:
	return look_for(my_pid) if mode == Mode.CLIENT else Player.LOOK

static func look_for(pid: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash("look:" + pid)
	var fem := r.randf() < 0.5
	var skins := [Color(0.95, 0.78, 0.66), Color(0.86, 0.66, 0.52), Color(0.72, 0.52, 0.38), Color(0.55, 0.38, 0.26), Color(0.4, 0.27, 0.18)]
	var hairs := [Color(0.08, 0.06, 0.05), Color(0.22, 0.14, 0.08), Color(0.45, 0.3, 0.15), Color(0.7, 0.55, 0.3), Color(0.55, 0.2, 0.08), Color(0.6, 0.6, 0.58)]
	var cloth := Color.from_hsv(r.randf(), r.randf_range(0.2, 0.55), r.randf_range(0.25, 0.55))
	var cloth2 := Color.from_hsv(r.randf(), r.randf_range(0.15, 0.4), r.randf_range(0.15, 0.35))
	return {"female": fem, "hair": hairs[r.randi() % hairs.size()], "hair_style": r.randi() % 4,
		"skin": skins[r.randi() % skins.size()], "cloth": cloth, "cloth2": cloth2,
		"height": r.randf_range(0.94, 1.06), "build": r.randf_range(0.3, 0.7)}

# --- Joining -----------------------------------------------------------------------

## Connects to a server. joined fires once the world is ready to stream in (the caller
## then opens the world scene); join_failed says why not.
func join(address: String, port: int, player_name_: String, password: String) -> void:
	leave("")
	var id := Identity.load_or_make()
	var nm := Identity.clean_name(player_name_)
	if nm.length() < 2:
		join_failed.emit("Pick a name of at least 2 letters.")
		return
	Identity.remember_name(nm)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port, 3)
	if err != OK:
		join_failed.emit("Couldn't reach %s:%d (%s)." % [address, port, error_string(err)])
		return
	var mp := SceneMultiplayer.new()
	mp.auth_callback = _client_auth
	mp.auth_timeout = 15.0
	mp.peer_authenticating.connect(_on_authenticating)
	mp.peer_authentication_failed.connect(func(_id): _fail("The server didn't let you in."))
	mp.connection_failed.connect(func(): _fail("Couldn't connect to %s:%d. Is the server running and the port open?" % [address, port]))
	mp.server_disconnected.connect(_on_server_gone)
	mp.connected_to_server.connect(_on_connected)
	get_tree().set_multiplayer(mp)
	mp.multiplayer_peer = peer
	_joining = {"name": nm, "token": id["token"], "password": password, "address": address, "port": port}
	mode = Mode.CLIENT

func _on_authenticating(id: int) -> void:
	if mode != Mode.CLIENT or id != 1:
		return
	var hello := {"game": "procedural-world", "protocol": ServerConfig.PROTOCOL,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"name": _joining.get("name", ""), "token": _joining.get("token", ""), "password": _joining.get("password", "")}
	multiplayer.send_auth(1, var_to_bytes(hello))

func _client_auth(id: int, data: PackedByteArray) -> void:
	var r = bytes_to_var(data)
	if not (r is Dictionary):
		_fail("The server sent something this game doesn't understand.")
		return
	if not r.get("ok", false):
		_fail(str(r.get("reason", "The server turned you away.")))
		return
	_joining["welcome"] = r
	(multiplayer as SceneMultiplayer).complete_auth(id)

func _on_connected() -> void:
	var w: Dictionary = _joining.get("welcome", {})
	if w.is_empty():
		_fail("The server didn't finish letting you in.")
		return
	info = w.get("info", {})
	options = w.get("options", {})
	my_pid = str(w["pid"])
	my_name = str(w["name"])
	is_admin = false
	peers.clear()
	var meta: Dictionary = w["meta"]
	store = RemoteStore.new("user://servers".path_join(str(w.get("uid", "server")).validate_filename()), meta)
	store.net = self
	store.player_data = w.get("player")
	Game.join_remote(store)
	_apply_clock(float(w.get("day", 0.3)))
	_joining = {}
	joined.emit()

func _fail(reason: String) -> void:
	if _joining.is_empty() and mode != Mode.CLIENT:
		return
	_close_peer()
	_joining = {}
	join_failed.emit(reason)

func _on_server_gone() -> void:
	leave("The server closed the connection.")

## Disconnects (and closes the world if one is open). `reason` goes to `left`.
func leave(reason: String = "") -> void:
	if mode != Mode.CLIENT or _leaving:
		return
	_leaving = true
	var was_in := store != null
	if store != null and Game.store == store:
		Game.save_all()
		_flush()
		Game.close_world()
	if store != null:
		store.closed = true
	store = null
	_close_peer()
	peers.clear()
	_leaving = false
	if was_in:
		last_reason = reason
		left.emit(reason)
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != MENU:
			get_tree().change_scene_to_file.call_deferred(MENU)

## Why you last left a server ("" if you chose to); the title screen shows it.
var last_reason := ""
const MENU := "res://src/ui/main_menu.tscn"

## Closes the connection. The multiplayer API itself is swapped out after this frame,
## since this may run inside its own signal.
func _close_peer() -> void:
	var mp := multiplayer
	if mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		_flush() # your last save goes out before the line drops
		mp.multiplayer_peer.close()
	mode = Mode.OFFLINE
	(func():
		if multiplayer == mp and mode == Mode.OFFLINE:
			get_tree().set_multiplayer(SceneMultiplayer.new())).call_deferred()

func _flush() -> void:
	var p := multiplayer.multiplayer_peer
	if p is ENetMultiplayerPeer and p.host != null:
		p.host.flush()

func _exit_tree() -> void:
	if mode == Mode.CLIENT:
		_flush()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and mode == Mode.CLIENT and store != null:
		Game.save_all()
		_flush()

# --- Client per frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if mode != Mode.CLIENT or store == null:
		return
	if Game.store != store:
		# The world was closed from the menus: that is leaving the server.
		leave("")
		return
	for req in store.take_outbox():
		if req[0] == "chunk":
			var k: Vector3i = req[1]
			s_chunk_req.rpc_id(1, k.x, k.y, k.z)
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree():
		return
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_HZ
		_send_state(pl)
	_prune_t -= delta
	if _prune_t <= 0.0:
		_prune_t = 3.0
		_prune(pl)

func _send_state(pl: Node3D) -> void:
	var anim := "idle"
	var speed := 1.0
	var shot := 0
	var body = pl.get("body")
	if body is HumanModel:
		anim = body._current if body._current != "" else "idle"
		speed = body.anim.speed_scale if body.anim else 1.0
		shot = body._shot if body.busy() else 0
	var pos: Vector3 = pl.global_position
	if pl.get("vehicle") != null and is_instance_valid(pl.vehicle):
		anim = "sit"
	s_state.rpc_id(1, Game.planet, pos, pl.yaw(), float(pl.get("_pitch")), anim, speed, shot)
	var it = Game.inventory.get_slot(pl.selected) if Game.inventory else null
	var look := {"equip": Game.equipment, "held": it if it != null else {}}
	if look != _last_look:
		_last_look = look.duplicate(true)
		s_look.rpc_id(1, look)

## Forgets cached chunks far from you; the server only sends edits to players near them.
func _prune(pl: Node3D) -> void:
	var c := ChunkStreamer.chunk_of(pl.global_position)
	store._lock.lock()
	var drop: Array = []
	for k in store._chunks:
		if k.x != Game.planet or maxi(absi(k.y - c.x), absi(k.z - c.y)) > PRUNE_RADIUS:
			drop.append(k)
	for k in drop:
		store._chunks.erase(k)
		store._order.erase(k)
	store._lock.unlock()

func _apply_clock(day: float) -> void:
	Game.day = day
	Game.day_seconds = float(option("day_minutes")) * 60.0
	match String(option("time")):
		"day": Game.time_lock = 0.5
		"night": Game.time_lock = 0.0
		_: Game.time_lock = -1.0

## Sends a chat line (or, from an admin, a server command starting with /).
func say(text: String) -> void:
	text = text.strip_edges().substr(0, 240)
	if text == "" or mode != Mode.CLIENT:
		return
	s_chat.rpc_id(1, text)

func admin(cmd: String) -> void:
	if mode == Mode.CLIENT:
		s_admin.rpc_id(1, cmd)

# --- RemoteStore hooks (client, main thread) ----------------------------------------------

func rs_send_chunk(p: int, chunk: Dictionary) -> void:
	if mode == Mode.CLIENT:
		s_chunk_save.rpc_id(1, p, NetPack.pack(chunk))

func rs_send_player(d: Dictionary) -> void:
	if mode == Mode.CLIENT:
		s_player_save.rpc_id(1, NetPack.pack(d))

func rs_request_town(p: int, site: Dictionary) -> void:
	if mode == Mode.CLIENT:
		s_town_req.rpc_id(1, p, site)

func rs_send_town(p: int, s: Dictionary) -> void:
	if mode == Mode.CLIENT:
		s_town_save.rpc_id(1, p, NetPack.pack(s))

# --- Client -> server ---------------------------------------------------------------------

func _sender() -> int:
	return multiplayer.get_remote_sender_id()

@rpc("any_peer", "call_remote", "reliable", CH_DATA)
func s_chunk_req(p: int, cx: int, cz: int) -> void:
	if host:
		host.chunk_request(_sender(), p, cx, cz)

@rpc("any_peer", "call_remote", "reliable", CH_DATA)
func s_chunk_save(p: int, data: PackedByteArray) -> void:
	if host:
		host.chunk_save(_sender(), p, data)

@rpc("any_peer", "call_remote", "reliable", CH_DATA)
func s_town_req(p: int, site: Dictionary) -> void:
	if host:
		host.town_request(_sender(), p, site)

@rpc("any_peer", "call_remote", "reliable", CH_DATA)
func s_town_save(p: int, data: PackedByteArray) -> void:
	if host:
		host.town_save(_sender(), p, data)

@rpc("any_peer", "call_remote", "reliable")
func s_player_save(data: PackedByteArray) -> void:
	if host:
		host.player_save(_sender(), data)

@rpc("any_peer", "call_remote", "unreliable_ordered", CH_STATE)
func s_state(p: int, pos: Vector3, yaw: float, pitch: float, anim: String, speed: float, shot: int) -> void:
	if host:
		host.player_state(_sender(), p, pos, yaw, pitch, anim, speed, shot)

@rpc("any_peer", "call_remote", "reliable")
func s_look(look: Dictionary) -> void:
	if host:
		host.player_look(_sender(), look)

@rpc("any_peer", "call_remote", "reliable")
func s_chat(text: String) -> void:
	if host:
		host.chat(_sender(), text)

@rpc("any_peer", "call_remote", "reliable")
func s_admin(cmd: String) -> void:
	if host:
		host.admin_from(_sender(), cmd)

# --- Server -> client ---------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable", CH_DATA)
func c_chunk(p: int, data: PackedByteArray, pushed: bool) -> void:
	if store == null:
		return
	var c = NetPack.unpack(data)
	if not (c is Dictionary and c.has("cx") and c.has("cz")):
		return
	store.deliver_chunk(p, c)
	if pushed and p == Game.planet:
		var w = Game.player.get("streamer") if Game.player != null and is_instance_valid(Game.player) else null
		if w is ChunkStreamer:
			w.replace_chunk(c)

@rpc("authority", "call_remote", "reliable", CH_DATA)
func c_town(p: int, data: PackedByteArray) -> void:
	if store == null:
		return
	var s = NetPack.unpack(data)
	if s is Dictionary and s.has("sx") and s.has("sz"):
		store.deliver_town(p, s)

@rpc("authority", "call_remote", "unreliable_ordered", CH_STATE)
func c_state(peer: int, p: int, pos: Vector3, yaw: float, pitch: float, anim: String, speed: float, shot: int) -> void:
	if not peers.has(peer):
		return
	var e: Dictionary = peers[peer]
	e["planet"] = p
	e["pos"] = pos
	e["yaw"] = yaw
	e["pitch"] = pitch
	e["anim"] = anim
	e["speed"] = speed
	e["shot"] = shot
	e["t"] = Time.get_ticks_msec()
	peer_state.emit(peer)

@rpc("authority", "call_remote", "reliable")
func c_look(peer: int, look: Dictionary) -> void:
	if peers.has(peer):
		peers[peer]["equip"] = look.get("equip", {})
		peers[peer]["held"] = look.get("held", {})
		peers[peer]["look_v"] = int(peers[peer].get("look_v", 0)) + 1
		peer_state.emit(peer)

@rpc("authority", "call_remote", "reliable")
func c_roster(list: Array) -> void:
	peers.clear()
	for r in list:
		_add_peer(r)
	players_changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_joined(r: Dictionary) -> void:
	_add_peer(r)
	chat.emit("", "%s joined" % r.get("name", "Someone"), "join")
	players_changed.emit()

func _add_peer(r: Dictionary) -> void:
	var peer := int(r.get("peer", 0))
	if peer == 0 or peer == multiplayer.get_unique_id():
		return
	peers[peer] = {"pid": str(r.get("pid", "")), "name": str(r.get("name", "")), "planet": int(r.get("planet", 0)),
		"pos": r.get("pos", Vector3.ZERO), "yaw": 0.0, "pitch": 0.0, "anim": "idle", "speed": 1.0, "shot": 0,
		"equip": r.get("equip", {}), "held": r.get("held", {}), "look_v": 0, "t": Time.get_ticks_msec()}

@rpc("authority", "call_remote", "reliable")
func c_left(peer: int) -> void:
	if peers.has(peer):
		chat.emit("", "%s left" % peers[peer]["name"], "leave")
		peers.erase(peer)
		players_changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_clock(day: float) -> void:
	_apply_clock(day)

@rpc("authority", "call_remote", "reliable")
func c_options(o: Dictionary, server_info: Dictionary) -> void:
	options = o
	info = server_info
	_apply_clock(Game.day)
	options_changed.emit()

@rpc("authority", "call_remote", "reliable")
func c_chat(from: String, text: String, kind: String) -> void:
	chat.emit(from, text, kind)
	if kind != "chat":
		Game.toast.emit(text if from == "" else "%s: %s" % [from, text])

@rpc("authority", "call_remote", "reliable")
func c_admin(ok: bool, text: String) -> void:
	is_admin = is_admin or ok
	chat.emit("", text, "admin")

@rpc("authority", "call_remote", "reliable")
func c_kicked(reason: String) -> void:
	leave.call_deferred(reason)
