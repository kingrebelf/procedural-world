class_name WorldStore
extends RefCounted
## On-disk storage for one world. Every chunk is snapshotted the first time it is generated
## and from then on only ever loaded, never regenerated. All writes are atomic
## (write .tmp, then rename), so a crash can never corrupt a previously good file.

const STORE_FORMAT := 1

var root: String
var meta: Dictionary = {}
## Which planet's land and people are read and written (0 = the home world, kept at the
## root so worlds from before spaceflight are unchanged; others live in planets/<n>/).
var planet := 0
## In-memory store (the title screen's fly-over): chunks live only in RAM, nothing
## touches disk, and the oldest are dropped past MEM_LIMIT.
var _mem = null
var _mem_order: Array = []
var _mem_lock := Mutex.new()
const MEM_LIMIT := 400

func _init(world_dir: String) -> void:
	root = world_dir
	if world_dir == "":
		_mem = {}
		return
	DirAccess.make_dir_recursive_absolute(root.path_join("chunks"))
	DirAccess.make_dir_recursive_absolute(root.path_join("people"))

static func memory() -> WorldStore:
	var s := WorldStore.new("")
	s.meta = {"gen_version": ChunkGenerator.GEN_VERSION}
	return s

## Worlds created since rivers existed have them; older worlds keep their old terrain.
func has_rivers() -> bool:
	return planet != 0 or int(meta.get("gen_version", 1)) >= 3

## Terrain shapes this world was created with (WorldField.terrain_v).
func terrain_version() -> int:
	return int(meta.get("gen_version", 1))

func set_planet(n: int) -> void:
	planet = n
	if _mem == null:
		DirAccess.make_dir_recursive_absolute(_land().path_join("chunks"))
		DirAccess.make_dir_recursive_absolute(_land().path_join("people"))

## Where the atlas keeps its painted pages and places ("" for a world in memory).
func map_dir() -> String:
	return "" if _mem != null else _land().path_join("map")

func _land() -> String:
	return root if planet == 0 else root.path_join("planets").path_join(str(planet))

static func worlds_dir() -> String:
	return "user://worlds"

static func list_worlds() -> Array:
	var out: Array = []
	var d := DirAccess.open(worlds_dir())
	if d == null:
		return out
	for name in d.get_directories():
		var m = read_var(worlds_dir().path_join(name).path_join("world.dat"))
		if m is Dictionary:
			m["id"] = name
			out.append(m)
	out.sort_custom(func(a, b): return a.get("last_played", 0) > b.get("last_played", 0))
	return out

static func create_world(name: String, seed: int) -> WorldStore:
	var id := "%s_%d" % [name.to_lower().replace(" ", "_").validate_filename(), Time.get_unix_time_from_system()]
	var s := WorldStore.new(worlds_dir().path_join(id))
	s.meta = {
		"store_format": STORE_FORMAT, "name": name, "seed": seed & WHash.MASK,
		"gen_version": ChunkGenerator.GEN_VERSION,
		"created": Time.get_unix_time_from_system(), "last_played": Time.get_unix_time_from_system(),
		"play_time": 0.0, "day": 0.3,
	}
	s.save_meta()
	return s

static func open_world(id: String) -> WorldStore:
	var s := WorldStore.new(worlds_dir().path_join(id))
	var m = read_var(s.root.path_join("world.dat"))
	if not (m is Dictionary):
		return null
	s.meta = m
	return s

static func delete_world(id: String) -> void:
	_rm_tree(worlds_dir().path_join(id))

static func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

# --- Atomic IO ---------------------------------------------------------------

static func write_var(path: String, value, compressed: bool = false) -> bool:
	var tmp := path + ".tmp"
	var f: FileAccess
	if compressed:
		f = FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	else:
		f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("WorldStore: cannot write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	if compressed:
		f.store_var(value)
	else:
		f.store_string(var_to_str(value))
	f.flush()
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK

static func read_var(path: String, compressed: bool = false):
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess
	if compressed:
		f = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	else:
		f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if compressed:
		return f.get_var()
	return str_to_var(f.get_as_text())

# --- World data --------------------------------------------------------------

func save_meta() -> void:
	write_var(root.path_join("world.dat"), meta)

## Player and discovery data are binary: text serialisation rounds floats, and an item's
## quality must come back bit-for-bit identical.
func save_player(data: Dictionary) -> void:
	write_var(root.path_join("player.dat"), data, true)

func load_player():
	return read_var(root.path_join("player.dat"), true)

func save_discovery(data: Dictionary) -> void:
	write_var(_land().path_join("discovery.dat"), data, true)

func load_discovery() -> Dictionary:
	var d = read_var(_land().path_join("discovery.dat"), true)
	return d if d is Dictionary else {"visited": {}, "regions": {}}

func chunk_path(cx: int, cz: int) -> String:
	return _land().path_join("chunks").path_join("%d_%d.chunk" % [cx, cz])

func has_chunk(cx: int, cz: int) -> bool:
	if _mem != null:
		_mem_lock.lock()
		var h: bool = _mem.has(Vector2i(cx, cz))
		_mem_lock.unlock()
		return h
	return FileAccess.file_exists(chunk_path(cx, cz))

func load_chunk(cx: int, cz: int):
	if _mem != null:
		_mem_lock.lock()
		var c = _mem.get(Vector2i(cx, cz))
		_mem_lock.unlock()
		return c
	return read_var(chunk_path(cx, cz), true)

func save_chunk(chunk: Dictionary) -> bool:
	if _mem != null:
		var k := Vector2i(chunk["cx"], chunk["cz"])
		_mem_lock.lock()
		if not _mem.has(k):
			_mem_order.append(k)
		_mem[k] = chunk
		while _mem_order.size() > MEM_LIMIT:
			_mem.erase(_mem_order.pop_front())
		_mem_lock.unlock()
		return true
	return write_var(chunk_path(chunk["cx"], chunk["cz"]), chunk, true)

## The one way to obtain a chunk: from disk if it ever existed, otherwise generated
## and immediately snapshotted. Thread-safe as long as callers do not race on the
## same (cx, cz), which ChunkStreamer guarantees. Rooms get their loot the first time
## either way, so chunks saved before rooms had loot are stocked when next loaded.
func get_or_create_chunk(gen: ChunkGenerator, cx: int, cz: int) -> Dictionary:
	var c = load_chunk(cx, cz)
	if c is Dictionary:
		if Interiors.stock(c):
			save_chunk(c)
		return c
	c = gen.generate(cx, cz)
	c["created"] = Time.get_unix_time_from_system()
	Interiors.stock(c)
	stitch_edges(c)
	save_chunk(c)
	return c

# --- Settlements and their people ---------------------------------------------------

func settlement_path(sx: int, sz: int) -> String:
	return _land().path_join("people").path_join("%d_%d.dat" % [sx, sz])

func has_settlement(sx: int, sz: int) -> bool:
	return FileAccess.file_exists(settlement_path(sx, sz))

func load_settlement(sx: int, sz: int):
	return read_var(settlement_path(sx, sz), true)

func save_settlement(s: Dictionary) -> bool:
	return write_var(settlement_path(s["sx"], s["sz"]), s, true)

## Same rule as chunks: people are created the first time their settlement is seen,
## saved at once, and from then on only ever loaded.
func get_or_create_settlement(gen: ChunkGenerator, site: Dictionary) -> Dictionary:
	var s = load_settlement(site["sx"], site["sz"])
	if s is Dictionary:
		return s
	s = NPCGen.generate(gen.seed, gen, site, gen.settlement_layout(site))
	s["created"] = Time.get_unix_time_from_system()
	save_settlement(s)
	return s

## Already-existing neighbours are authoritative for shared edge vertices, so terrain
## stays seamless even across chunks made by different generator versions or edited
## by the player before this chunk existed.
func stitch_edges(c: Dictionary) -> void:
	var R := ChunkGenerator.RES
	var hs: PackedFloat32Array = c["heights"]
	var cx: int = c["cx"]
	var cz: int = c["cz"]
	var sides := [[-1, 0], [1, 0], [0, -1], [0, 1]]
	for s in sides:
		if not has_chunk(cx + s[0], cz + s[1]):
			continue
		var n = load_chunk(cx + s[0], cz + s[1])
		if not (n is Dictionary):
			continue
		var nh: PackedFloat32Array = n["heights"]
		for k in R:
			if s[0] == -1:
				hs[k * R] = nh[k * R + R - 1]
			elif s[0] == 1:
				hs[k * R + R - 1] = nh[k * R]
			elif s[1] == -1:
				hs[k] = nh[(R - 1) * R + k]
			else:
				hs[(R - 1) * R + k] = nh[k]
	c["heights"] = hs
