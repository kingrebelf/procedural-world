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

var _chunks: Dictionary = {} ## Vector3i(planet, cx, cz) -> chunk
var _order: Array = []
var _asked: Dictionary = {} ## Vector3i -> msec asked
var _towns: Dictionary = {} ## Vector3i(planet, sx, sz) -> settlement
var _towns_asked: Dictionary = {}
var _lock := Mutex.new()
var _outbox: Array = [] ## requests from worker threads, sent by Net on the main thread

func _init(cache_dir: String, world_meta: Dictionary) -> void:
	super("")
	_mem = null
	root = cache_dir
	meta = world_meta.duplicate(true)
	DirAccess.make_dir_recursive_absolute(root)

func set_planet(n: int) -> void:
	planet = n
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

func deliver_town(p: int, s: Dictionary) -> void:
	_towns[Vector3i(p, int(s["sx"]), int(s["sz"]))] = s

func has_settlement(sx: int, sz: int) -> bool:
	return _towns.has(Vector3i(planet, sx, sz))

func load_settlement(sx: int, sz: int):
	return _towns.get(Vector3i(planet, sx, sz))

func save_settlement(s: Dictionary) -> bool:
	_towns[Vector3i(planet, int(s["sx"]), int(s["sz"]))] = s
	if net != null and not closed:
		net.rs_send_town(planet, s)
	return true

func get_or_create_settlement(gen: ChunkGenerator, site: Dictionary) -> Dictionary:
	var s = load_settlement(int(site["sx"]), int(site["sz"]))
	if s is Dictionary:
		return s
	# Not fetched first: make it the way the server would; the server's copy wins later.
	prefetch_settlement(site)
	s = NPCGen.generate(gen.seed, gen, site, gen.settlement_layout(site))
	return s
