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
signal mob_hit(kind: String, id: String, dmg: float, killed: bool, from_peer: int) ## you run it; someone else hit it
signal mob_said(id: String, text: String, secs: float)
signal mob_talk(id: String, on: bool) ## someone else is talking with a person you run
signal town_pushed(sx: int, sz: int) ## someone else's save of a loaded town was merged into it
signal alliance_changed

const DEFAULT_PORT := 24600
const STATE_HZ := 15.0
const CH_STATE := 1 ## unreliable movement
const CH_DATA := 2 ## chunks and settlements, so big transfers don't hold up chat
const PRUNE_RADIUS := 12 ## chunks a client keeps cached around itself (the server pushes edits within PUSH_RADIUS)
const MOB_HZ := 10.0 ## updates a second of the people and animals you run, for others

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
## Who runs each town ("t") and each chunk's animals ("f") you have loaded:
## "kind:planet:x:z" -> [holder peer, how many players have it loaded]
var holders: Dictionary = {}
## Puppets' latest state from whoever runs them: kind -> id -> [msec, state Array]
var mobs: Dictionary = {"f": {}, "n": {}}
var _watch_out: Dictionary = {} ## kind:planet -> [adds, removes] waiting to be sent

# Alliances (stage 4): yours, invitations to others, and where your allies are.
var alliance: Dictionary = {} ## {id, name, leader: pid, members: {pid: name}} or {}
var ally_invites: Array = [] ## [{id, name, from}]
var allies_at: Dictionary = {} ## pid -> [planet, pos, msec]: allies anywhere, for the map

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

## Whether `pid` is in your alliance (never offline, or with alliances off).
func allied(pid: String) -> bool:
	return mode == Mode.CLIENT and pid != my_pid and bool(option("alliances")) \
		and (alliance.get("members", {}) as Dictionary).has(pid)

## An alliance command: create <name>, invite <pid>, accept/decline <id>, leave,
## kick/lead <pid>, chat <text>. The server answers in chat and with c_alliance.
func ally(cmd: String, arg := "") -> void:
	if mode == Mode.CLIENT:
		s_ally.rpc_id(1, cmd, arg)

## Whether `at` (on `planet`) is in a house one of your allies owns: what is inside is
## theirs to share with you, so taking it isn't stealing.
func ally_home_at(at: Vector3, planet: int) -> bool:
	var hs: Dictionary = alliance.get("homes", {})
	for pid in hs:
		if allied(pid):
			for h in hs[pid]:
				if int(h[0]) == planet and Vector2(float(h[1]), float(h[2])).distance_to(Vector2(at.x, at.z)) < 7.0:
					return true
	return false

## Your allies online with where they are (any distance): [[pid, name, planet, pos], ...].
func allies_where() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for pid in alliance.get("members", {}):
		if pid == my_pid:
			continue
		var at = null
		for peer in peers:
			var r: Dictionary = peers[peer]
			if r["pid"] == pid and now - int(r.get("t", 0)) < 3000:
				at = [int(r["planet"]), r["pos"]] # near: its live position
		if at == null and allies_at.has(pid) and now - int(allies_at[pid][2]) < 8000:
			at = allies_at[pid]
		if at != null:
			out.append([pid, String(alliance["members"][pid]), int(at[0]), at[1]])
	return out

## Whether this game runs a town ("t", key = settlement sx, sz) or a chunk's animals
## ("f", key = chunk): always offline; online when the server made you its holder.
func holds(kind: String, k: Vector2i) -> bool:
	if mode != Mode.CLIENT:
		return true
	var h = holders.get("%s:%d:%d:%d" % [kind, Game.planet, k.x, k.y])
	return h != null and int(h[0]) == multiplayer.get_unique_id()

## Whether anyone else has it loaded too (so its updates are worth sending).
func shared(kind: String, k: Vector2i) -> bool:
	var h = holders.get("%s:%d:%d:%d" % [kind, Game.planet, k.x, k.y])
	return mode == Mode.CLIENT and h != null and int(h[1]) > 1

## Tells the server you loaded (adds: [[key Vector2i, centre Vector2], ...]) or let go of
## (removes: [key, ...]) towns or animal chunks. Sent in a batch each frame.
func watch(kind: String, adds: Array, removes: Array) -> void:
	if mode != Mode.CLIENT:
		return
	var q: String = "%s:%d" % [kind, Game.planet]
	var e: Array = _watch_out.get(q, [[], []])
	for a in adds:
		e[0].append(a)
		e[1].erase(a[0])
	for r in removes:
		e[1].append(r)
		holders.erase("%s:%d:%d:%d" % [kind, Game.planet, r.x, r.y])
	_watch_out[q] = e

func _send_watch() -> void:
	for q in _watch_out:
		var parts: PackedStringArray = q.split(":")
		var e: Array = _watch_out[q]
		s_watch.rpc_id(1, parts[0], int(parts[1]), e[0], e[1])
	_watch_out.clear()

## The latest state of a puppet you don't run, or [] (none yet, or stale).
func mob_state(kind: String, id: String) -> Array:
	var e = mobs[kind].get(id)
	if e == null or Time.get_ticks_msec() - int(e[0]) > 3000:
		return []
	return e[1]

## Sends the states of the people ("n") or animals ("f") you run to players near.
func send_mobs(kind: String, list: Array) -> void:
	if mode == Mode.CLIENT and not list.is_empty():
		s_mobs.rpc_id(1, Game.planet, kind, list)

func send_mob_say(id: String, text: String, secs: float) -> void:
	if mode == Mode.CLIENT:
		s_mob_say.rpc_id(1, Game.planet, id, text, secs)

## You hit a person or animal someone else runs: they apply it (killed: your blow killed it).
func hit_mob(kind: String, k: Vector2i, id: String, dmg: float, killed: bool) -> void:
	if mode == Mode.CLIENT:
		s_mob_hit.rpc_id(1, kind, Game.planet, k, id, dmg, killed)

## You started (or ended) talking with a person someone else runs: they stand still for it.
func talk_mob(k: Vector2i, id: String, on: bool) -> void:
	if mode == Mode.CLIENT:
		s_mob_talk.rpc_id(1, Game.planet, k, id, on)

## An animal or person you run hurt another player (pvp false), or you did (pvp true).
func hurt_player(peer: int, dmg: float, cause: String, pvp: bool) -> void:
	if mode == Mode.CLIENT and peers.has(peer):
		s_hurt.rpc_id(1, peer, dmg, cause, pvp)

var _ai_seq := 0
var _ai_replies: Dictionary = {}

## Asks the server's villager model (AI.chat, when this game has none of its own).
## Returns AI.chat's {ok, text, error}.
func ai_chat(system: String, messages: Array, background: bool) -> Dictionary:
	if mode != Mode.CLIENT:
		return {"ok": false, "text": "", "error": "Not on a server"}
	_ai_seq += 1
	var id := _ai_seq
	s_ai.rpc_id(1, id, system, messages, background)
	var t0 := Time.get_ticks_msec()
	while not _ai_replies.has(id):
		if mode != Mode.CLIENT or Time.get_ticks_msec() - t0 > 90000:
			return {"ok": false, "text": "", "error": "The server's AI didn't answer"}
		await get_tree().process_frame
	var r: Dictionary = _ai_replies[id]
	_ai_replies.erase(id)
	return {"ok": bool(r.get("ok", false)), "text": String(r.get("text", "")), "error": String(r.get("error", ""))}

## The nearest player to `at` among you (peer 0, at `me`) and the others on this planet
## within `radius`: [peer, position], or [0, me].
func nearest_player(at: Vector3, me: Vector3, radius := 200.0) -> Array:
	var best := [0, me]
	var bd := at.distance_to(me)
	if mode != Mode.CLIENT:
		return best
	var now := Time.get_ticks_msec()
	for peer in peers:
		var r: Dictionary = peers[peer]
		if int(r["planet"]) != Game.planet or now - int(r.get("t", 0)) > 5000 or r.get("dead", false):
			continue
		var d := at.distance_to(r["pos"])
		if d < bd and d < radius:
			bd = d
			best = [peer, r["pos"]]
	return best

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
	# Signals from an older connection still saying goodbye (_drain) must not touch this one.
	mp.peer_authenticating.connect(func(id): if multiplayer == mp: _on_authenticating(id))
	mp.peer_authentication_failed.connect(func(_id): if multiplayer == mp: _fail("The server didn't let you in."))
	mp.connection_failed.connect(func(): if multiplayer == mp: _fail("Couldn't connect to %s:%d. Is the server running and the port open?" % [address, port]))
	mp.server_disconnected.connect(func(): if multiplayer == mp: _on_server_gone())
	mp.connected_to_server.connect(func(): if multiplayer == mp: _on_connected())
	get_tree().set_multiplayer(mp)
	mp.multiplayer_peer = peer
	_joining = {"name": nm, "token": id["token"], "password": password, "address": address, "port": port}
	mode = Mode.CLIENT

## ENet drops a peer that goes about five seconds without answering, and loading the
## world (kit models, food, the first chunks) holds the main thread longer than that on
## a slow machine: allow 20 s before giving up on a quiet peer, 60 s for any one packet.
const PEER_TIMEOUT := [32, 20000, 60000]

static func patient(peer: MultiplayerPeer, id: int) -> void:
	var p := (peer as ENetMultiplayerPeer).get_peer(id) if peer is ENetMultiplayerPeer else null
	if p != null:
		p.set_timeout(PEER_TIMEOUT[0], PEER_TIMEOUT[1], PEER_TIMEOUT[2])

func _on_authenticating(id: int) -> void:
	if mode != Mode.CLIENT or id != 1:
		return
	patient(multiplayer.multiplayer_peer, 1)
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
	holders.clear()
	alliance = {}
	ally_invites = []
	allies_at.clear()
	mobs = {"f": {}, "n": {}}
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
	holders.clear()
	mobs = {"f": {}, "n": {}}
	_watch_out.clear()
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
	var p := mp.multiplayer_peer
	mode = Mode.OFFLINE
	if p is ENetMultiplayerPeer and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and p.get_peer(1) != null:
		# A polite goodbye: ENet sends what is still queued (your last save) and then
		# disconnects. The old peer is polled here until it has (_process).
		p.get_peer(1).peer_disconnect_later()
		p.host.flush()
		_draining.append([p, Time.get_ticks_msec() + 3000])
	elif p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	(func():
		if multiplayer == mp and mode == Mode.OFFLINE:
			get_tree().set_multiplayer(SceneMultiplayer.new())).call_deferred()

## Peers saying goodbye: [peer, give-up msec].
var _draining: Array = []

func _drain() -> void:
	for d in _draining.duplicate():
		var p: ENetMultiplayerPeer = d[0]
		if p.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			p.poll()
		if p.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED or Time.get_ticks_msec() > int(d[1]):
			p.close()
			_draining.erase(d)

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
	if not _draining.is_empty():
		_drain()
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
	if not _watch_out.is_empty():
		_send_watch()
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
		# The pace of a looping state (gaits follow the body's own motion on arrival).
		speed = body.animator._state_speed if body.animator else 1.0
		shot = body._shot if body.busy() else 0
	var pos: Vector3 = pl.global_position
	var yaw: float = pl.yaw()
	var riding = pl.get("vehicle")
	if riding != null and is_instance_valid(riding):
		# Riding: where the vehicle is, so others draw it under you.
		anim = "ride:" + String(riding.kind)
		pos = riding.global_position
		yaw = riding.rotation.y
	s_state.rpc_id(1, Game.planet, pos, yaw, float(pl.get("_pitch")), anim, speed, shot)
	var it = Game.inventory.get_slot(pl.selected) if Game.inventory else null
	var look := {"equip": Game.equipment, "held": it if it != null else {}, "wanted": _wanted(), "veh": _parked(riding)}
	if look != _last_look:
		_last_look = look.duplicate(true)
		s_look.rpc_id(1, look)

## Where you are wanted (settlement id -> stars), so townsfolk others run know too.
func _wanted() -> Dictionary:
	var out := {}
	if Game.crime:
		for sid in Game.crime.bounty:
			var st: int = Game.crime.stars(sid, Game.day)
			if st > 0:
				out[sid] = st
	return out

## Your parked vehicles, for others to see: [[kind, pos, yaw, planet], ...].
func _parked(riding) -> Array:
	var out: Array = []
	for r in Game.vehicles:
		if riding != null and is_instance_valid(riding) and riding.rec == r:
			continue
		out.append([String(r["kind"]), r["pos"], float(r.get("yaw", 0.0)), int(r.get("planet", 0))])
	return out

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
func s_ally(cmd: String, arg: String) -> void:
	if host:
		host.ally(_sender(), cmd, arg)

@rpc("authority", "call_remote", "reliable")
func c_alliance(mine: Dictionary, invites: Array) -> void:
	alliance = mine
	ally_invites = invites
	alliance_changed.emit()

@rpc("authority", "call_remote", "unreliable_ordered", CH_STATE)
func c_allies_at(list: Array) -> void:
	var now := Time.get_ticks_msec()
	for e in list:
		if e is Array and e.size() == 3 and e[2] is Vector3:
			allies_at[String(e[0])] = [int(e[1]), e[2], now]

@rpc("any_peer", "call_remote", "reliable")
func s_admin(cmd: String) -> void:
	if host:
		host.admin_from(_sender(), cmd)

# Same channel as town saves, so a holder's last save arrives before it lets go.
@rpc("any_peer", "call_remote", "reliable", CH_DATA)
func s_watch(kind: String, p: int, adds: Array, removes: Array) -> void:
	if host:
		host.watch(_sender(), kind, p, adds, removes)

@rpc("any_peer", "call_remote", "unreliable_ordered", CH_STATE)
func s_mobs(p: int, kind: String, list: Array) -> void:
	if host:
		host.mobs(_sender(), p, kind, list)

@rpc("any_peer", "call_remote", "reliable")
func s_mob_say(p: int, id: String, text: String, secs: float) -> void:
	if host:
		host.mob_say(_sender(), p, id, text, secs)

@rpc("any_peer", "call_remote", "reliable")
func s_mob_hit(kind: String, p: int, k: Vector2i, id: String, dmg: float, killed: bool) -> void:
	if host:
		host.mob_hit(_sender(), kind, p, k, id, dmg, killed)

@rpc("any_peer", "call_remote", "reliable")
func s_mob_talk(p: int, k: Vector2i, id: String, on: bool) -> void:
	if host:
		host.mob_talk(_sender(), p, k, id, on)

@rpc("any_peer", "call_remote", "reliable")
func s_ai(id: int, system: String, messages: Array, background: bool) -> void:
	if host:
		host.ai_chat(_sender(), id, system, messages, background)

@rpc("any_peer", "call_remote", "reliable")
func s_hurt(target: int, dmg: float, cause: String, pvp: bool) -> void:
	if host:
		host.hurt_player(_sender(), target, dmg, cause, pvp)

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
func c_town(p: int, data: PackedByteArray, pushed: bool) -> void:
	if store == null:
		return
	var s = NetPack.unpack(data)
	if s is Dictionary and s.has("sx") and s.has("sz") and s.get("npcs") is Array:
		if store.deliver_town(p, s, pushed) and p == Game.planet:
			town_pushed.emit(int(s["sx"]), int(s["sz"]))

## Your save was kept as it was: the copy you have is now revision `rev`.
@rpc("authority", "call_remote", "reliable", CH_DATA)
func c_rev(kind: String, p: int, k: Vector2i, base_rev: int, rev: int) -> void:
	if store == null:
		return
	if kind == "t":
		store.town_acked(p, k, base_rev, rev)
		return
	store.chunk_acked(p, k, base_rev, rev)
	if p == Game.planet:
		var w = Game.player.get("streamer") if Game.player != null and is_instance_valid(Game.player) else null
		var cn = w.get_chunk(k) if w is ChunkStreamer else null
		if cn != null and int(cn.data.get("_rev", -1)) == base_rev:
			cn.data["_rev"] = rev

@rpc("authority", "call_remote", "reliable", CH_DATA)
func c_hold(kind: String, p: int, k: Vector2i, holder: int, count: int) -> void:
	holders["%s:%d:%d:%d" % [kind, p, k.x, k.y]] = [holder, count]

@rpc("authority", "call_remote", "unreliable_ordered", CH_STATE)
func c_mobs(_peer: int, p: int, kind: String, list: Array) -> void:
	if p != Game.planet or not mobs.has(kind):
		return
	var now := Time.get_ticks_msec()
	var m: Dictionary = mobs[kind]
	for st in list:
		if st is Array and st.size() > 1 and st[0] is String:
			m[st[0]] = [now, st]
	if now - _mob_sweep > 5000:
		_mob_sweep = now
		for id in m.keys():
			if now - int(m[id][0]) > 10000:
				m.erase(id)

var _mob_sweep := 0

@rpc("authority", "call_remote", "reliable")
func c_mob_say(p: int, id: String, text: String, secs: float) -> void:
	if p == Game.planet:
		mob_said.emit(id, text, secs)

@rpc("authority", "call_remote", "reliable")
func c_mob_hit(kind: String, p: int, id: String, dmg: float, killed: bool, from_peer: int) -> void:
	if p == Game.planet:
		mob_hit.emit(kind, id, dmg, killed, from_peer)

@rpc("authority", "call_remote", "reliable")
func c_mob_talk(p: int, id: String, on: bool) -> void:
	if p == Game.planet:
		mob_talk.emit(id, on)

@rpc("authority", "call_remote", "reliable")
func c_ai(id: int, r: Dictionary) -> void:
	_ai_replies[id] = r

## Someone else hurt you: another player (by_name), or an animal or person they run.
@rpc("authority", "call_remote", "reliable")
func c_hurt(dmg: float, cause: String, by_name: String, _from_peer: int) -> void:
	if Game.store == null or Game.health <= 0.0:
		return
	var took := Game.hurt(dmg, cause)
	if by_name != "":
		Game.toast.emit("%s hits you (-%d)" % [by_name, int(ceilf(took))])
	else:
		Game.toast.emit("%s (-%d)" % [cause.replace("Killed by ", "Hit by "), int(ceilf(took))])

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
		peers[peer]["wanted"] = look.get("wanted", {})
		peers[peer]["veh"] = look.get("veh", [])
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
		"equip": r.get("equip", {}), "held": r.get("held", {}), "wanted": r.get("wanted", {}), "veh": r.get("veh", []),
		"look_v": 0, "t": Time.get_ticks_msec()}

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
	if kind != "chat" and not (kind == "ally" and from != ""):
		Game.toast.emit(text if from == "" else "%s: %s" % [from, text])

@rpc("authority", "call_remote", "reliable")
func c_admin(ok: bool, text: String) -> void:
	is_admin = is_admin or ok
	chat.emit("", text, "admin")

@rpc("authority", "call_remote", "reliable")
func c_kicked(reason: String) -> void:
	leave.call_deferred(reason)
