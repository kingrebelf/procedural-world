class_name ServerSync
extends RefCounted
## The server's side of sharing a world between players (stage 2, plans/multiplayer.md):
##   - Revisions: every chunk and settlement sent out carries `_rev`; the last few
##     versions of each are kept, so a save made from an older copy is merged
##     (NetMerge) with what others saved since instead of overwriting it.
##   - Holders: one player runs each town's people and each chunk's animals (the first to
##     load it, then the nearest of the others when they leave); the rest see puppets.

const HISTORY := 6 ## versions kept per chunk or settlement

var host: Node ## ServerHost
var _seq := 0
var _seq_lock := Mutex.new()
var _hist: Dictionary = {} ## key -> [[rev, packed bytes], ...] oldest first (key: "c:p:x:z" or "t:p:x:z")

## kind ("t" towns, "f" fauna chunks) + ":" + Vector3i key -> {peers: {peer: true}, holder: peer, at: Vector2}
var _watch: Dictionary = {}

func _init(h: Node) -> void:
	host = h
	# Rising across restarts, so a client's revision from an older run never matches.
	_seq = int(Time.get_unix_time_from_system() * 1000.0)

## Thread-safe: a fresh revision number.
func next_rev() -> int:
	_seq_lock.lock()
	_seq += 1
	var r := _seq
	_seq_lock.unlock()
	return r

static func key_of(kind: String, k: Vector3i) -> String:
	return "%s:%d:%d:%d" % [kind, k.x, k.y, k.z]

## Remembers a version sent out (main thread).
func remember(kind: String, k: Vector3i, rev: int, bytes: PackedByteArray) -> void:
	var key := key_of(kind, k)
	var h: Array = _hist.get(key, [])
	h.append([rev, bytes])
	while h.size() > HISTORY:
		h.pop_front()
	_hist[key] = h

func forget(kind: String, k: Vector3i) -> void:
	_hist.erase(key_of(kind, k))

func version(kind: String, k: Vector3i, rev: int):
	for e in _hist.get(key_of(kind, k), []):
		if int(e[0]) == rev:
			return NetPack.unpack(e[1])
	return null

## A save arriving from a player: `mine` was edited from revision mine._rev; `cur` is the
## server's copy (or null). Returns [the data to keep, whether it differs from mine].
func merge_save(kind: String, k: Vector3i, mine: Dictionary, cur) -> Array:
	if not (cur is Dictionary):
		return [mine, false]
	var base_rev := int(mine.get("_rev", -1))
	if int(cur.get("_rev", -2)) == base_rev:
		return [mine, false]
	var base = version(kind, k, base_rev)
	if base is Dictionary:
		var out = NetMerge.merge3(base, mine, cur)
		return [out, true]
	# Edited from a copy too old to merge: the newer save wins, as before stage 2, and the
	# saver is sent the result so it sees the same as everyone.
	return [mine, true]

# --- Holders ----------------------------------------------------------------------------

## A player loaded (add) or let go of (remove) towns or fauna chunks. adds: [[Vector2i, Vector2 centre], ...]
func watch(peer: int, kind: String, p: int, adds: Array, removes: Array) -> void:
	var changed: Array = []
	for a in adds:
		if not (a is Array and a.size() == 2 and a[0] is Vector2i and a[1] is Vector2):
			continue
		var key := key_of(kind, Vector3i(p, a[0].x, a[0].y))
		var w: Dictionary = _watch.get(key, {"peers": {}, "holder": 0, "at": a[1], "kind": kind, "k": Vector3i(p, a[0].x, a[0].y)})
		w["peers"][peer] = true
		_watch[key] = w
		if int(w["holder"]) == 0 or not host.online.has(int(w["holder"])):
			w["holder"] = peer
			changed.append(key)
		else:
			_tell(peer, w) # who holds it, for the newcomer
			_tell(int(w["holder"]), w) # and that someone else now sees it
	for r in removes:
		if r is Vector2i:
			_unwatch(peer, key_of(kind, Vector3i(p, r.x, r.y)), changed)
	for key in changed:
		_announce(key)

func _unwatch(peer: int, key: String, changed: Array) -> void:
	var w = _watch.get(key)
	if w == null or not w["peers"].has(peer):
		return
	w["peers"].erase(peer)
	if w["peers"].is_empty():
		_watch.erase(key)
		return
	if int(w["holder"]) == peer:
		w["holder"] = _nearest(w)
		if not changed.has(key):
			changed.append(key)
	else:
		_tell(int(w["holder"]), w)

## The watcher nearest the place, to take it over.
func _nearest(w: Dictionary) -> int:
	var best := 0
	var bd := INF
	var at: Vector2 = w["at"]
	for q in w["peers"]:
		var o = host.online.get(q)
		if o == null:
			continue
		var pos: Vector3 = o["pos"]
		var d := Vector2(pos.x, pos.z).distance_to(at)
		if d < bd:
			bd = d
			best = q
	return best

## A player left (or, with `planet`, left that planet): what they had loaded passes on.
func drop_peer(peer: int, planet := -1) -> void:
	var changed: Array = []
	for key in _watch.keys():
		if planet < 0 or (_watch[key]["k"] as Vector3i).x == planet:
			_unwatch(peer, key, changed)
	for key in changed:
		_announce(key)

func _announce(key: String) -> void:
	var w = _watch.get(key)
	if w == null:
		return
	for q in w["peers"]:
		_tell(q, w)

func _tell(q: int, w: Dictionary) -> void:
	var k: Vector3i = w["k"]
	if host.online.has(q):
		host.tell_hold(q, String(w["kind"]), k.x, Vector2i(k.y, k.z), int(w["holder"]), w["peers"].size())

func holder_of(kind: String, k: Vector3i) -> int:
	var w = _watch.get(key_of(kind, k))
	return int(w["holder"]) if w != null else 0

func watchers(kind: String, k: Vector3i) -> Array:
	var w = _watch.get(key_of(kind, k))
	return w["peers"].keys() if w != null else []
