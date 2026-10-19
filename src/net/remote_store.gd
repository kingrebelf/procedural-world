class_name RemoteStore
extends WorldStore
## A client's view of a server's world. The game reads and writes through the usual
## WorldStore calls; chunks, settlements and the player's save come from and go to the
## server (through `net`, the Net autoload). Map pages and discovery are cached locally
## under `root` (user://servers/<server id>), and the world's meta is read-only here.

const CACHE_LIMIT := 900
const RETRY_MS := 12000
const GIVE_UP_MS := 90000

var net: Object
var player_data = null ## your save, from the handshake
var closed := false
## The planet every message to the server names: always 0, there is one world.
var planet := 0

var _chunks: Dictionary = {} ## Vector3i(planet, cx, cz) -> chunk
var _order: Array = []
var _asked: Dictionary = {} ## Vector3i -> msec asked
var _towns: Dictionary = {} ## Vector3i(planet, sx, sz) -> settlement
var _towns_asked: Dictionary = {}
var _town_base: Dictionary = {} ## Vector3i -> the server's last copy, for merging pushes into yours
var _town_sent: Dictionary = {} ## Vector3i -> a copy of your last save, until the server keeps it
var _lock := Mutex.new()
var _outbox: Array = [] ## requests from worker threads, sent by Net on the main thread

func _init(cache_dir: String, world_meta: Dictionary) -> void:
	super("")
	_mem = null
	root = cache_dir
	meta = world_meta.duplicate(true)
	DirAccess.make_dir_recursive_absolute(root)
	DirAccess.make_dir_recursive_absolute(map_dir())

func save_meta() -> void:
	pass # the server keeps the world's meta

func save_player(data: Dictionary) -> void:
	player_data = data
	if net != null and not closed:
		net.rs_send_player(data)

func load_player():
	return player_data

# --- Chunks --------------------------------------------------------------------

func has_chunk(cx: int, cz: int) -> bool:
	_lock.lock()
	var h := _chunks.has(Vector3i(planet, cx, cz))
	_lock.unlock()
	return h

func load_chunk(cx: int, cz: int):
	_lock.lock()
	var c = _chunks.get(Vector3i(planet, cx, cz))
	_lock.unlock()
	return c

## Sends an edited chunk to the server, which saves it and shows it to everyone near.
func save_chunk(chunk: Dictionary) -> bool:
	_keep(Vector3i(planet, int(chunk["cx"]), int(chunk["cz"])), chunk)
	if net != null and not closed:
		net.rs_send_chunk(planet, chunk)
	return true

## Worker thread: waits for the server's copy. If the server never answers (the
## connection dropped), the chunk is generated here so the thread can finish; it is
## not saved, and the world closes on disconnect anyway.
func get_or_create_chunk(gen: ChunkGenerator, cx: int, cz: int) -> Dictionary:
	var k := Vector3i(planet, cx, cz)
	var start := Time.get_ticks_msec()
	while not closed and Time.get_ticks_msec() - start < GIVE_UP_MS:
		_lock.lock()
		var c = _chunks.get(k)
		if c == null:
			var asked: int = _asked.get(k, -RETRY_MS)
			if Time.get_ticks_msec() - asked >= RETRY_MS:
				_asked[k] = Time.get_ticks_msec()
				_outbox.append(["chunk", k])
		_lock.unlock()
		if c is Dictionary:
			return c
		OS.delay_msec(8)
	var g := gen.generate(cx, cz)
	Interiors.stock(g)
	Dungeon.stock(gen, g)
	return g

## Main thread (Net): a chunk from the server, asked for or pushed after someone's edit.
func deliver_chunk(p: int, chunk: Dictionary) -> void:
	var k := Vector3i(p, int(chunk["cx"]), int(chunk["cz"]))
	_keep(k, chunk)
	_lock.lock()
	_asked.erase(k)
	_lock.unlock()

func _keep(k: Vector3i, chunk: Dictionary) -> void:
	_lock.lock()
	if not _chunks.has(k):
		_order.append(k)
	_chunks[k] = chunk
	while _order.size() > CACHE_LIMIT:
		_chunks.erase(_order.pop_front())
	_lock.unlock()

## Main thread (Net): the server kept your save as it was, now revision `rev`.
func chunk_acked(p: int, k: Vector2i, base_rev: int, rev: int) -> void:
	_lock.lock()
	var c = _chunks.get(Vector3i(p, k.x, k.y))
	if c is Dictionary and int(c.get("_rev", -1)) == base_rev:
		c["_rev"] = rev
	_lock.unlock()

## Main thread (Net): the requests waiting to go out.
func take_outbox() -> Array:
	_lock.lock()
	var out := _outbox
	_outbox = []
	_lock.unlock()
	return out

# --- Settlements -----------------------------------------------------------------

## True once a settlement's people have arrived from the server; until then this asks
## for them and NPCManager waits.
func prefetch_settlement(site: Dictionary) -> bool:
	var k := Vector3i(planet, int(site["sx"]), int(site["sz"]))
	if _towns.has(k):
		return true
	var now := Time.get_ticks_msec()
	if now - int(_towns_asked.get(k, -RETRY_MS)) >= RETRY_MS:
		_towns_asked[k] = now
		if net != null and not closed:
			net.rs_request_town(planet, site)
	return false

## A town from the server: asked for, or (pushed) someone else's save of it, which is
## merged into the copy you have so the people walking about keep their records.
## Returns true when it was merged into a copy in use.
func deliver_town(p: int, s: Dictionary, pushed := false) -> bool:
	var k := Vector3i(p, int(s["sx"]), int(s["sz"]))
	var live = _towns.get(k)
	if pushed and live is Dictionary and _town_base.has(k):
		NetMerge.merge_into(live, _town_base[k], s)
		live["_rev"] = s.get("_rev", -1)
		_town_base[k] = s.duplicate(true)
		_town_sent.erase(k)
		return true
	_towns[k] = s
	_town_base[k] = s.duplicate(true)
	return false

## The server kept your save of a town as it was: it is now revision `rev`.
func town_acked(p: int, k2: Vector2i, base_rev: int, rev: int) -> void:
	var k := Vector3i(p, k2.x, k2.y)
	var live = _towns.get(k)
	if live is Dictionary and int(live.get("_rev", -1)) == base_rev:
		live["_rev"] = rev
	var sent = _town_sent.get(k)
	if sent is Dictionary and int(sent.get("_rev", -1)) == base_rev:
		sent["_rev"] = rev
		_town_base[k] = sent
	_town_sent.erase(k)

## Lets go of a town you walked away from: nobody sends you its changes any more, so
## it is asked for again when you come back.
func forget_settlement(sx: int, sz: int) -> void:
	var k := Vector3i(planet, sx, sz)
	_towns.erase(k)
	_towns_asked.erase(k)
	_town_base.erase(k)
	_town_sent.erase(k)

func has_settlement(sx: int, sz: int) -> bool:
	return _towns.has(Vector3i(planet, sx, sz))

func load_settlement(sx: int, sz: int):
	return _towns.get(Vector3i(planet, sx, sz))

func save_settlement(s: Dictionary) -> bool:
	var k := Vector3i(planet, int(s["sx"]), int(s["sz"]))
	_towns[k] = s
	_town_sent[k] = s.duplicate(true)
	if net != null and not closed:
		net.rs_send_town(planet, s)
	return true

func get_or_create_settlement(gen: ChunkGenerator, site: Dictionary) -> Dictionary:
	var s = load_settlement(int(site["sx"]), int(site["sz"]))
	if s is Dictionary:
		return s
	# Not fetched first: make it the way the server would; the server's copy wins later.
	prefetch_settlement(site)
	s = NPCGen.create(gen, site)
	return s
