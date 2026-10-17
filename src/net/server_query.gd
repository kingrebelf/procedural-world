class_name ServerQuery
extends Node
## Finds servers and asks them how they are, for the Join Server screen:
##   - ask(address, port): connects just long enough to get the server's info (name,
##     description, players, password, version) and how long the answer took (ping).
##   - scan(): asks every server on your local network (UDP broadcast to LAN_PORT; a
##     server with lan_discovery on answers with its info and game port).
## Answers arrive as `answered(key, info)` with info["ping"] in ms, or info["error"].

signal answered(key: String, info: Dictionary)

const LAN_PORT := 24599 ## servers listen here for "who's there?" on the local network
const HELLO := "procedural-world?"
const TIMEOUT_MS := 4000

var _asks: Array = [] ## {key, mp, peer, t0, done}
var _udp: PacketPeerUDP
var _scan_until := 0
var _scan_t0 := 0

## Whether an address is on this machine or a private local network (where LAN
## discovery answers), not out on the internet.
static func is_local(ip: String) -> bool:
	if ip.begins_with("::ffff:"):
		ip = ip.substr(7)
	if ip == "::1" or ip.to_lower().begins_with("fe80:") or ip.to_lower().begins_with("fc") or ip.to_lower().begins_with("fd"):
		return true
	var q := ip.split(".")
	if q.size() != 4:
		return false
	var a := q[0].to_int()
	var b := q[1].to_int()
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)

## Asks one server for its info. The answer comes as answered("host:port", info).
func ask(host: String, port: int) -> void:
	var key := "%s:%d" % [host, port]
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(host, port, 1) != OK:
		answered.emit(key, {"error": "Can't reach %s" % key})
		return
	var mp := SceneMultiplayer.new()
	var e := {"key": key, "mp": mp, "peer": peer, "t0": Time.get_ticks_msec(), "done": false}
	mp.auth_callback = func(_id: int, data: PackedByteArray): _on_answer(e, data)
	mp.auth_timeout = TIMEOUT_MS / 1000.0
	mp.peer_authenticating.connect(func(id: int):
		e["t0"] = Time.get_ticks_msec()
		mp.send_auth(id, var_to_bytes({"game": "procedural-world", "query": "info"})))
	mp.multiplayer_peer = peer
	_asks.append(e)

func _on_answer(e: Dictionary, data: PackedByteArray) -> void:
	if e["done"]:
		return
	e["done"] = true
	var r = bytes_to_var(data) if data.size() < 65536 else null
	var info: Dictionary = r.get("info", {}) if r is Dictionary and r.get("info") is Dictionary else {}
	if info.is_empty():
		answered.emit(e["key"], {"error": "Not a Procedural World server"})
	else:
		info = info.duplicate()
		info["ping"] = Time.get_ticks_msec() - int(e["t0"])
		answered.emit(e["key"], info)
	_close(e)

func _close(e: Dictionary) -> void:
	(e["peer"] as ENetMultiplayerPeer).close()
	_asks.erase(e)

## Asks the local network (or one machine, `to`). Answers come as
## answered("lan:host:port", info), info["host"] and info["port"] saying where to join.
func scan(to := "255.255.255.255") -> void:
	if _udp == null:
		_udp = PacketPeerUDP.new()
		_udp.set_broadcast_enabled(true)
		if _udp.bind(0) != OK:
			_udp = null
			return
	_scan_t0 = Time.get_ticks_msec()
	_scan_until = _scan_t0 + 2000
	_udp.set_dest_address(to, LAN_PORT)
	_udp.put_packet(HELLO.to_utf8_buffer())

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for e in _asks.duplicate():
		(e["mp"] as SceneMultiplayer).poll()
		if not e["done"] and now - int(e["t0"]) > TIMEOUT_MS + 500:
			e["done"] = true
			answered.emit(e["key"], {"error": "No answer"})
			_close(e)
	if _udp != null and now < _scan_until:
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet()
			var host := _udp.get_packet_ip()
			var info = JSON.parse_string(pkt.get_string_from_utf8()) if pkt.size() < 8192 else null
			if info is Dictionary and info.get("game", "") == "procedural-world":
				var port := int(info.get("port", Net.DEFAULT_PORT))
				info["host"] = host
				info["port"] = port
				info["ping"] = now - _scan_t0
				answered.emit("lan:%s:%d" % [host, port], info)

func _exit_tree() -> void:
	for e in _asks.duplicate():
		_close(e)
	if _udp != null:
		_udp.close()
