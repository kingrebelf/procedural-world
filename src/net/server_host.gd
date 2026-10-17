class_name ServerHost
extends Node
## The dedicated server's game: it owns the world save (meta, chunks, settlements and
## every player's save), the clock, who is connected, bans and admin commands. Requests
## arrive through the Net autoload's RPCs. Chunk and settlement loads run on worker
## threads; everything else runs on the main thread.

signal log_line(text: String)

const PUSH_RADIUS := 14 ## chunks: edits are pushed to players this close (Net.PRUNE_RADIUS + 2)
const RELAY_RANGE := 900.0 ## metres: players see each other's movement this far
const MAX_JOBS := 6
const HOT_LIMIT := 3000
const AUTOSAVE := 60.0
const CLOCK_EVERY := 10.0
const NIGHT := 0.0
const NOON := 0.5

var cfg: ServerConfig
var root := ""
var meta: Dictionary = {}
var day := 0.3
var _stores: Dictionary = {} ## planet -> WorldStore
var _gens: Dictionary = {} ## planet -> ChunkGenerator

## Connected players: peer -> {pid, name, planet, pos, chunk, admin, ip, equip, held}
var online: Dictionary = {}
var _index: Dictionary = {} ## sha256(token) -> {pid, name}
var _next_pid := 1
var _bans: Dictionary = {"pids": {}, "ips": {}}

var _hot: Dictionary = {} ## Vector3i(planet, cx, cz) -> packed chunk (Net.pack)
var _hot_order: Array = []
var _towns: Dictionary = {} ## Vector3i(planet, sx, sz) -> packed settlement
var _jobs: Dictionary = {} ## key String -> {"waiters": [peer...], "task": id}
var _queue: Array = [] ## jobs waiting for a worker slot
var _done: Array = []
var _lock := Mutex.new()
var _save_t := 0.0
var _clock_t := 0.0
var mp: SceneMultiplayer

func start(c: ServerConfig) -> Error:
	cfg = c
	root = cfg.data_dir.path_join("worlds").path_join(cfg.world.validate_filename())
	if not _open_world():
		return ERR_CANT_OPEN
	_load_index()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(cfg.port, cfg.max_players + 4, 3)
	if err != OK:
		return err
	mp = SceneMultiplayer.new()
	mp.auth_callback = _auth
	mp.auth_timeout = 15.0
	mp.server_relay = false
	mp.peer_authenticating.connect(func(id): _alive[id] = true)
	mp.peer_authentication_failed.connect(func(id): _alive.erase(id); online.erase(id))
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	get_tree().set_multiplayer(mp)
	mp.multiplayer_peer = peer
	Net.mode = Net.Mode.SERVER
	Net.host = self
	Net.options = cfg.options
	return OK

func _open_world() -> bool:
	DirAccess.make_dir_recursive_absolute(root)
	var m = WorldStore.read_var(root.path_join("world.dat"))
	if m is Dictionary:
		meta = m
	else:
		var s := cfg.seed_text.strip_edges()
		var sd: int = randi() if s == "" else (s.to_int() if s.is_valid_int() else WHash.str_hash(s))
		meta = {"store_format": WorldStore.STORE_FORMAT, "name": cfg.world, "seed": sd & WHash.MASK,
			"gen_version": ChunkGenerator.GEN_VERSION, "theme": "human",
			"created": Time.get_unix_time_from_system(), "last_played": Time.get_unix_time_from_system(),
			"play_time": 0.0, "day": 0.3}
		if not WorldStore.write_var(root.path_join("world.dat"), meta):
			return false
		say_log("Made a new world '%s' with seed %d" % [cfg.world, meta["seed"]])
	if not meta.has("uid"):
		meta["uid"] = "%s_%d" % [cfg.world.validate_filename(), int(meta.get("created", 0))]
	day = float(meta.get("day", 0.3))
	DirAccess.make_dir_recursive_absolute(root.path_join("players"))
	return true

func store_for(p: int) -> WorldStore:
	if not _stores.has(p):
		var s := WorldStore.new(root)
		s.meta = meta
		s.set_planet(p)
		_stores[p] = s
	return _stores[p]

func gen_for(p: int) -> ChunkGenerator:
	if not _gens.has(p):
		var s := store_for(p)
		_gens[p] = ChunkGenerator.new(Planets.seed_of(int(meta["seed"]), p), s.has_rivers())
	return _gens[p]

func say_log(t: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), t]
	print(line)
	log_line.emit(line)

# --- Joining ----------------------------------------------------------------------------

func _auth(peer: int, data: PackedByteArray) -> void:
	var h = bytes_to_var(data) if data.size() < 4096 else null
	if not (h is Dictionary) or h.get("game", "") != "procedural-world":
		_refuse(peer, "That isn't a Procedural World client.")
		return
	if h.get("query", "") == "info":
		mp.send_auth(peer, var_to_bytes({"ok": false, "info": cfg.info(online.size()), "reason": "info"}))
		_drop_later(peer)
		return
	if int(h.get("protocol", -1)) != ServerConfig.PROTOCOL:
		_refuse(peer, "This server runs version %s; update your game to match." % ProjectSettings.get_setting("application/config/version", ""))
		return
	var ip := _ip_of(peer)
	if _bans["ips"].has(ip):
		_refuse(peer, "You are banned from this server.")
		return
	if cfg.password != "" and str(h.get("password", "")) != cfg.password:
		_refuse(peer, "Wrong password." if str(h.get("password", "")) != "" else "This server needs a password.")
		return
	var token := str(h.get("token", ""))
	var nm := Identity.clean_name(str(h.get("name", "")))
	if token.length() < 32 or nm.length() < 2:
		_refuse(peer, "Pick a name of at least 2 letters.")
		return
	var key := Identity.token_key(token)
	var rec = _index.get(key)
	for k in _index:
		if k != key and String(_index[k]["name"]).to_lower() == nm.to_lower():
			_refuse(peer, "Someone else on this server already goes by %s." % nm)
			return
	if rec != null and _bans["pids"].has(rec["pid"]):
		_refuse(peer, "You are banned from this server.")
		return
	# Back before the server noticed you left (a dropped connection): the old
	# session gives way to the new one. Only the token's owner can get here.
	var old := pid_online(rec["pid"]) if rec != null else 0
	if old != 0:
		say_log("%s reconnected; closing their old connection" % rec["name"])
		_on_peer_disconnected(old)
		_alive.erase(old)
		mp.disconnect_peer(old)
	if online.size() >= cfg.max_players:
		_refuse(peer, "The server is full (%d players)." % cfg.max_players)
		return
	if rec == null:
		rec = {"pid": "p%d" % _next_pid, "name": nm}
		_next_pid += 1
		_index[key] = rec
	elif rec["name"] != nm:
		say_log("%s is now called %s" % [rec["name"], nm])
		rec["name"] = nm
	_save_index()
	var save = WorldStore.read_var(_player_path(rec["pid"]), true)
	online[peer] = {"pid": rec["pid"], "name": nm, "planet": int(save.get("planet", 0)) if save is Dictionary else 0,
		"pos": save.get("pos", Vector3.ZERO) if save is Dictionary else Vector3.ZERO, "admin": false, "ip": ip,
		"equip": save.get("equipment", {}) if save is Dictionary else {}, "held": {}, "pending": true}
	online[peer]["chunk"] = ChunkStreamer.chunk_of(online[peer]["pos"])
	var welcome := {"ok": true, "pid": rec["pid"], "name": nm, "uid": meta["uid"], "day": day,
		"meta": _client_meta(), "info": cfg.info(online.size()), "options": cfg.options, "player": save}
	mp.send_auth(peer, var_to_bytes(welcome))
	mp.complete_auth(peer)

## What clients need of the world's meta to generate and draw it like the server.
func _client_meta() -> Dictionary:
	var m := {}
	for k in ["name", "seed", "gen_version", "theme", "store_format", "created", "uid"]:
		if meta.has(k):
			m[k] = meta[k]
	return m

func _refuse(peer: int, reason: String) -> void:
	say_log("Refused peer %d (%s): %s" % [peer, _ip_of(peer), reason])
	mp.send_auth(peer, var_to_bytes({"ok": false, "reason": reason}))
	_drop_later(peer)

func _drop_later(peer: int) -> void:
	get_tree().create_timer(0.5).timeout.connect(func():
		if _alive.has(peer):
			_alive.erase(peer)
			mp.disconnect_peer(peer))

var _alive: Dictionary = {} ## peers still connected (joining or playing)

func _ip_of(peer: int) -> String:
	var p := mp.multiplayer_peer as ENetMultiplayerPeer
	if p == null:
		return ""
	var pp := p.get_peer(peer)
	return pp.get_remote_address() if pp != null else ""

func _on_peer_connected(peer: int) -> void:
	if not online.has(peer):
		mp.disconnect_peer(peer)
		return
	var o: Dictionary = online[peer]
	o.erase("pending")
	say_log("%s joined (%s, %s). %d/%d online" % [o["name"], o["pid"], o["ip"], online.size(), cfg.max_players])
	var roster: Array = []
	for p in online:
		if p != peer:
			roster.append(_card(p))
	Net.c_roster.rpc_id(peer, roster)
	for p in online:
		if p != peer:
			Net.c_joined.rpc_id(p, _card(peer))

func _card(peer: int) -> Dictionary:
	var o: Dictionary = online[peer]
	return {"peer": peer, "pid": o["pid"], "name": o["name"], "planet": o["planet"], "pos": o["pos"], "equip": o["equip"], "held": o["held"]}

func _on_peer_disconnected(peer: int) -> void:
	_alive.erase(peer)
	if not online.has(peer):
		return
	var o: Dictionary = online[peer]
	online.erase(peer)
	if o.has("pending"):
		return
	say_log("%s left. %d/%d online" % [o["name"], online.size(), cfg.max_players])
	for p in online:
		Net.c_left.rpc_id(p, peer)

func pid_online(pid: String) -> int:
	for p in online:
		if online[p]["pid"] == pid:
			return p
	return 0

# --- Players' saves -----------------------------------------------------------------------

func _player_path(pid: String) -> String:
	return root.path_join("players").path_join("%s.dat" % pid.validate_filename())

func player_save(peer: int, data: PackedByteArray) -> void:
	if not online.has(peer):
		return
	var d = NetPack.unpack(data)
	if not (d is Dictionary):
		return
	var o: Dictionary = online[peer]
	WorldStore.write_var(_player_path(o["pid"]), d, true)
	o["planet"] = int(d.get("planet", o["planet"]))
	if d.get("pos") is Vector3:
		o["pos"] = d["pos"]

func _load_index() -> void:
	var d = WorldStore.read_var(root.path_join("players").path_join("index.dat"), true)
	if d is Dictionary:
		_index = d.get("players", {})
		_next_pid = int(d.get("next", 1))
	var b = WorldStore.read_var(root.path_join("bans.dat"))
	if b is Dictionary:
		_bans = {"pids": b.get("pids", {}), "ips": b.get("ips", {})}

func _save_index() -> void:
	WorldStore.write_var(root.path_join("players").path_join("index.dat"), {"players": _index, "next": _next_pid}, true)

func _save_bans() -> void:
	WorldStore.write_var(root.path_join("bans.dat"), _bans)

# --- Movement relay -------------------------------------------------------------------------

func player_state(peer: int, p: int, pos: Vector3, yaw: float, pitch: float, anim: String, speed: float, shot: int) -> void:
	if not online.has(peer) or not pos.is_finite():
		return
	var o: Dictionary = online[peer]
	o["planet"] = p
	o["pos"] = pos
	o["chunk"] = ChunkStreamer.chunk_of(pos)
	anim = anim.substr(0, 32)
	for q in online:
		if q == peer or online[q].has("pending"):
			continue
		var r: Dictionary = online[q]
		if r["planet"] == p and (r["pos"] as Vector3).distance_to(pos) < RELAY_RANGE:
			Net.c_state.rpc_id(q, peer, p, pos, yaw, pitch, anim, speed, shot)

func player_look(peer: int, look: Dictionary) -> void:
	if not online.has(peer):
		return
	var o: Dictionary = online[peer]
	o["equip"] = look.get("equip", {})
	o["held"] = look.get("held", {})
	for q in online:
		if q != peer and not online[q].has("pending"):
			Net.c_look.rpc_id(q, peer, {"equip": o["equip"], "held": o["held"]})

# --- Chunks ------------------------------------------------------------------------------------

func chunk_request(peer: int, p: int, cx: int, cz: int) -> void:
	if not online.has(peer) or p < 0 or p >= Planets.COUNT:
		return
	var k := Vector3i(p, cx, cz)
	_lock.lock()
	var hot = _hot.get(k)
	_lock.unlock()
	if hot != null:
		Net.c_chunk.rpc_id(peer, p, hot, false)
		return
	_want("c:%d:%d:%d" % [p, cx, cz], peer, {"kind": "chunk", "key": k})

func town_request(peer: int, p: int, site: Dictionary) -> void:
	if not online.has(peer) or p < 0 or p >= Planets.COUNT or not (site.get("sx") is int and site.get("sz") is int):
		return
	var k := Vector3i(p, site["sx"], site["sz"])
	_lock.lock()
	var hot = _towns.get(k)
	_lock.unlock()
	if hot != null:
		Net.c_town.rpc_id(peer, p, hot)
		return
	_want("t:%d:%d:%d" % [p, k.y, k.z], peer, {"kind": "town", "key": k, "site": site})

func _want(id: String, peer: int, job: Dictionary) -> void:
	if _jobs.has(id):
		if not _jobs[id]["waiters"].has(peer):
			_jobs[id]["waiters"].append(peer)
		return
	job["id"] = id
	job["waiters"] = [peer]
	_jobs[id] = job
	_queue.append(job)
	_launch()

## World generation reads a few globals set per planet (Planets.apply, WorldField.terrain_v),
## so jobs run one planet at a time: another planet's wait until these finish.
var _active_planet := -1

func _launch() -> void:
	var running := 0
	for id in _jobs:
		if _jobs[id].has("task"):
			running += 1
	if running == 0 and not _queue.is_empty() and int(_queue[0]["key"].x) != _active_planet:
		_use_planet(int(_queue[0]["key"].x))
	var i := 0
	while running < MAX_JOBS and i < _queue.size():
		var job: Dictionary = _queue[i]
		if int(job["key"].x) != _active_planet:
			i += 1
			continue
		_queue.remove_at(i)
		# Stores and generators are made here, on the main thread, before a worker uses them.
		job["store"] = store_for(_active_planet)
		job["gen"] = gen_for(_active_planet)
		job["task"] = WorkerThreadPool.add_task(_run.bind(job), false, job["id"])
		running += 1

## Sets the world-generation globals for planet `p`, as Game._enter_planet does on a client.
func _use_planet(p: int) -> void:
	_active_planet = p
	WorldField.terrain_v = int(meta.get("gen_version", 1))
	Planets.apply(Planets.get_planet(int(meta["seed"]), p, String(meta.get("theme", ""))))

## Worker thread.
func _run(job: Dictionary) -> void:
	var k: Vector3i = job["key"]
	var s: WorldStore = job["store"]
	var out
	if job["kind"] == "chunk":
		out = NetPack.pack(s.get_or_create_chunk(job["gen"], k.y, k.z))
	else:
		out = NetPack.pack(s.get_or_create_settlement(job["gen"], job["site"]))
	_lock.lock()
	_done.append([job, out])
	_lock.unlock()

func _collect() -> void:
	_lock.lock()
	var done := _done
	_done = []
	_lock.unlock()
	for d in done:
		var job: Dictionary = d[0]
		var bytes: PackedByteArray = d[1]
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_jobs.erase(job["id"])
		var k: Vector3i = job["key"]
		_lock.lock()
		if job["kind"] == "chunk":
			# Someone may have saved this chunk while it loaded: theirs is newer.
			if _hot.has(k):
				bytes = _hot[k]
			else:
				_remember(k, bytes)
		elif _towns.has(k):
			bytes = _towns[k]
		else:
			_towns[k] = bytes
		_lock.unlock()
		for peer in job["waiters"]:
			if online.has(peer):
				if job["kind"] == "chunk":
					Net.c_chunk.rpc_id(peer, k.x, bytes, false)
				else:
					Net.c_town.rpc_id(peer, k.x, bytes)
	if not done.is_empty():
		_launch()

## Caller holds _lock.
func _remember(k: Vector3i, bytes: PackedByteArray) -> void:
	if not _hot.has(k):
		_hot_order.append(k)
	_hot[k] = bytes
	while _hot_order.size() > HOT_LIMIT:
		_hot.erase(_hot_order.pop_front())

## A player's edit: saved at once and shown to everyone else near it.
func chunk_save(peer: int, p: int, data: PackedByteArray) -> void:
	if not online.has(peer) or p < 0 or p >= Planets.COUNT:
		return
	var c = NetPack.unpack(data)
	if not _valid_chunk(c):
		say_log("Ignored a damaged chunk from %s" % online[peer]["name"])
		return
	var k := Vector3i(p, int(c["cx"]), int(c["cz"]))
	store_for(p).save_chunk(c)
	_lock.lock()
	_remember(k, data)
	_lock.unlock()
	for q in online:
		if q == peer or online[q].has("pending"):
			continue
		var r: Dictionary = online[q]
		var rc: Vector2i = r["chunk"]
		if r["planet"] == p and maxi(absi(rc.x - k.y), absi(rc.y - k.z)) <= PUSH_RADIUS:
			Net.c_chunk.rpc_id(q, p, data, true)

static func _valid_chunk(c) -> bool:
	if not (c is Dictionary and c.get("cx") is int and c.get("cz") is int):
		return false
	var h = c.get("heights")
	return h is PackedFloat32Array and h.size() == ChunkGenerator.RES * ChunkGenerator.RES and c.get("objects") is Array

func town_save(peer: int, p: int, data: PackedByteArray) -> void:
	if not online.has(peer) or p < 0 or p >= Planets.COUNT:
		return
	var s = NetPack.unpack(data)
	if not (s is Dictionary and s.get("sx") is int and s.get("sz") is int and s.get("npcs") is Array):
		return
	store_for(p).save_settlement(s)
	_lock.lock()
	_towns[Vector3i(p, s["sx"], s["sz"])] = data
	_lock.unlock()

# --- Clock and saving ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if mp == null:
		return
	_collect()
	match String(cfg.options["time"]):
		"day": day = floorf(day) + NOON
		"night": day = floorf(day) + NIGHT
		_: day += delta / (float(cfg.options["day_minutes"]) * 60.0)
	meta["play_time"] = float(meta.get("play_time", 0.0)) + delta
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = CLOCK_EVERY
		for q in online:
			if not online[q].has("pending"):
				Net.c_clock.rpc_id(q, day)
	_save_t += delta
	if _save_t >= AUTOSAVE:
		_save_t = 0.0
		save()

func save() -> void:
	meta["day"] = day
	meta["last_played"] = Time.get_unix_time_from_system()
	WorldStore.write_var(root.path_join("world.dat"), meta)
	_save_index()

func stop() -> void:
	for q in online.keys():
		Net.c_kicked.rpc_id(q, "The server is shutting down.")
	for id in _jobs:
		if _jobs[id].has("task"):
			WorkerThreadPool.wait_for_task_completion(_jobs[id]["task"])
	_collect()
	save()
	var p := mp.multiplayer_peer
	if p is ENetMultiplayerPeer and p.host != null:
		p.host.flush()

## Tells every player about changed options (and the clock, which they may lock).
func broadcast_options() -> void:
	Net.options = cfg.options
	for q in online:
		if not online[q].has("pending"):
			Net.c_options.rpc_id(q, cfg.options, cfg.info(online.size()))
			Net.c_clock.rpc_id(q, day)

# --- Chat and admin ---------------------------------------------------------------------------------

func chat(peer: int, text: String) -> void:
	if not online.has(peer):
		return
	text = text.strip_edges().substr(0, 240)
	if text == "":
		return
	var o: Dictionary = online[peer]
	if text.begins_with("/"):
		admin_from(peer, text.substr(1))
		return
	say_log("<%s> %s" % [o["name"], text])
	for q in online:
		if not online[q].has("pending"):
			Net.c_chat.rpc_id(q, o["name"], text, "chat")

func announce(text: String) -> void:
	say_log("[server] %s" % text)
	for q in online:
		if not online[q].has("pending"):
			Net.c_chat.rpc_id(q, "", text, "server")

## A player's server command: `admin <password>` signs them in first.
func admin_from(peer: int, cmd: String) -> void:
	if not online.has(peer):
		return
	var o: Dictionary = online[peer]
	var a := cmd.strip_edges().split(" ", false)
	if a.is_empty():
		return
	if a[0] == "admin" or a[0] == "login":
		var ok := cfg.admin_password != "" and a.size() > 1 and a[1] == cfg.admin_password
		o["admin"] = o["admin"] or ok
		say_log("%s %s admin" % [o["name"], "is now" if ok else "failed to become"])
		Net.c_admin.rpc_id(peer, ok, "You are a server admin." if ok else ("Wrong admin password." if cfg.admin_password != "" else "This server has no admin password set."))
		return
	if not o["admin"] and a[0].to_lower() in ["help", "?", "players", "who", "list"]:
		Net.c_admin.rpc_id(peer, false, run_command(cmd) + ("\nAdmins: /admin <password> first." if a[0] in ["help", "?"] else ""))
		return
	if not o["admin"]:
		Net.c_admin.rpc_id(peer, false, "Only admins can do that. Type /admin <password> first.")
		return
	say_log("%s ran: %s" % [o["name"], cmd])
	Net.c_admin.rpc_id(peer, true, run_command(cmd))

const HELP := """Commands:
  status                 server name, world, players, options
  players                who is online
  say <text>             message everyone
  kick <name> [reason]   disconnect a player
  ban <name>             ban a player (and their address)
  unban <name>           lift a ban
  bans                   list bans
  save                   save the world now
  get [option]           show options
  set <option> <value>   change an option (saved to server.cfg)
  name <text>            rename the server
  description <text>     change the description
  maxplayers <n>         change the player limit
  password [text]        set the join password (none to clear)
  stop                   save and shut down"""

## Runs one admin command and returns what to print.
func run_command(text: String) -> String:
	var a := text.strip_edges().split(" ", false)
	if a.is_empty():
		return ""
	var rest := text.strip_edges().substr(a[0].length()).strip_edges()
	match a[0].to_lower():
		"help", "?":
			return HELP
		"status":
			return "%s\n%s\nWorld %s (seed %d), day %.2f, port %d, %d/%d players, password %s\nOptions: %s" % [cfg.name, cfg.description,
				cfg.world, meta["seed"], day, cfg.port, online.size(), cfg.max_players, "on" if cfg.password != "" else "off", _opts_text()]
		"players", "list", "who":
			if online.is_empty():
				return "Nobody is online."
			var lines := PackedStringArray()
			for q in online:
				var o: Dictionary = online[q]
				var pos: Vector3 = o["pos"]
				lines.append("%s (%s)%s planet %d at %d, %d, ping %d ms" % [o["name"], o["pid"], " admin" if o["admin"] else "", o["planet"], int(pos.x), int(pos.z), _ping(q)])
			return "\n".join(lines)
		"say":
			if rest == "":
				return "Usage: say <text>"
			announce(rest)
			return "Said: %s" % rest
		"kick":
			if a.size() < 2:
				return "Usage: kick <name> [reason]"
			var q := _find_online(a[1])
			if q == 0:
				return "%s isn't online." % a[1]
			kick(q, rest.substr(a[1].length()).strip_edges())
			return "Kicked %s" % a[1]
		"ban":
			if a.size() < 2:
				return "Usage: ban <name>"
			var rec := _find_known(a[1])
			if rec.is_empty():
				return "Nobody called %s has played here." % a[1]
			_bans["pids"][rec["pid"]] = rec["name"]
			var q := pid_online(rec["pid"])
			if q != 0:
				_bans["ips"][online[q]["ip"]] = rec["name"]
				kick(q, "You are banned from this server.")
			_save_bans()
			return "Banned %s" % rec["name"]
		"unban":
			if a.size() < 2:
				return "Usage: unban <name>"
			var n := a[1].to_lower()
			var hit := false
			for d in [_bans["pids"], _bans["ips"]]:
				for k in d.keys():
					if String(d[k]).to_lower() == n:
						d.erase(k)
						hit = true
			_save_bans()
			return "Unbanned %s" % a[1] if hit else "%s isn't banned." % a[1]
		"bans":
			return "Banned: %s" % (", ".join(_bans["pids"].values()) if not _bans["pids"].is_empty() else "nobody")
		"save":
			save()
			return "Saved."
		"get":
			if a.size() > 1:
				return "%s = %s" % [a[1], str(cfg.options.get(a[1], "(no such option)"))]
			return _opts_text()
		"set":
			if a.size() < 3:
				return "Usage: set <option> <value>. Options: %s" % ", ".join(ServerConfig.OPTIONS.keys())
			var err := cfg.set_option(a[1], a[2])
			if err != "":
				return err
			cfg.write_file()
			broadcast_options()
			announce("Server option %s is now %s" % [a[1], str(cfg.options[a[1]])])
			return "%s = %s" % [a[1], str(cfg.options[a[1]])]
		"name":
			if rest == "":
				return "Name: %s" % cfg.name
			cfg.name = rest.substr(0, 60)
			cfg.write_file()
			broadcast_options()
			return "Server name: %s" % cfg.name
		"description", "desc":
			if rest == "":
				return "Description: %s" % cfg.description
			cfg.description = rest.substr(0, 400)
			cfg.write_file()
			broadcast_options()
			return "Description set."
		"maxplayers", "max_players":
			if a.size() < 2 or not a[1].is_valid_int():
				return "Max players: %d" % cfg.max_players
			cfg.max_players = clampi(a[1].to_int(), 1, 256)
			cfg.write_file()
			return "Max players: %d (applies to new joins)" % cfg.max_players
		"password":
			cfg.password = rest if rest.to_lower() != "none" else ""
			cfg.write_file()
			return "Password %s" % ("set" if cfg.password != "" else "cleared: anyone can join")
		"stop", "quit", "exit":
			stop_requested.emit()
			return "Stopping."
	return "Unknown command %s. Type help." % a[0]

signal stop_requested

func kick(peer: int, reason: String) -> void:
	if not online.has(peer):
		return
	say_log("Kicked %s%s" % [online[peer]["name"], ": " + reason if reason != "" else ""])
	Net.c_kicked.rpc_id(peer, reason if reason != "" else "You were kicked from the server.")
	_drop_later(peer)

func _ping(peer: int) -> int:
	var p := mp.multiplayer_peer as ENetMultiplayerPeer
	var pp := p.get_peer(peer) if p != null else null
	return int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if pp != null else -1

func _opts_text() -> String:
	var parts := PackedStringArray()
	for k in cfg.options:
		parts.append("%s=%s" % [k, str(cfg.options[k])])
	return ", ".join(parts)

func _find_online(n: String) -> int:
	n = n.to_lower()
	for q in online:
		if String(online[q]["name"]).to_lower() == n or online[q]["pid"] == n:
			return q
	return 0

func _find_known(n: String) -> Dictionary:
	n = n.to_lower()
	for k in _index:
		if String(_index[k]["name"]).to_lower() == n or _index[k]["pid"] == n:
			return _index[k]
	return {}
