class_name WorldStore
extends RefCounted
## On-disk storage for one world. Every chunk is snapshotted the first time it is generated
## and from then on only ever loaded, never regenerated. All writes are atomic
## (write .tmp, then rename), so a crash can never corrupt a previously good file.

const STORE_FORMAT := 1

var root: String
var meta: Dictionary = {}

func _init(world_dir: String) -> void:
	root = world_dir
	DirAccess.make_dir_recursive_absolute(root.path_join("chunks"))

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
	write_var(root.path_join("discovery.dat"), data, true)

func load_discovery() -> Dictionary:
	var d = read_var(root.path_join("discovery.dat"), true)
	return d if d is Dictionary else {"visited": {}, "regions": {}}

func chunk_path(cx: int, cz: int) -> String:
	return root.path_join("chunks").path_join("%d_%d.chunk" % [cx, cz])

func has_chunk(cx: int, cz: int) -> bool:
	return FileAccess.file_exists(chunk_path(cx, cz))

func load_chunk(cx: int, cz: int):
	return read_var(chunk_path(cx, cz), true)

func save_chunk(chunk: Dictionary) -> bool:
	return write_var(chunk_path(chunk["cx"], chunk["cz"]), chunk, true)

## The one way to obtain a chunk: from disk if it ever existed, otherwise generated
## and immediately snapshotted. Thread-safe as long as callers do not race on the
## same (cx, cz), which ChunkStreamer guarantees.
func get_or_create_chunk(gen: ChunkGenerator, cx: int, cz: int) -> Dictionary:
	var c = load_chunk(cx, cz)
	if c is Dictionary:
		return c
	c = gen.generate(cx, cz)
	c["created"] = Time.get_unix_time_from_system()
	stitch_edges(c)
	save_chunk(c)
	return c

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
