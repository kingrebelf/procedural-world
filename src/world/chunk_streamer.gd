class_name ChunkStreamer
extends Node3D
## Keeps the chunks around the player loaded. Loading/generation and mesh building
## run on the WorkerThreadPool; uploads to the scene are budgeted per frame.

signal chunk_ready(node: ChunkNode)

var view_radius := 5
var near_radius := 1
var grass_radius := 1
var grass_density := 1.0
var max_jobs := 4
var uploads_per_frame := 2

var chunks: Dictionary = {} ## Vector2i -> ChunkNode
var _jobs: Dictionary = {} ## Vector2i -> task id
var _results: Array = []
var _mutex := Mutex.new()
var _center := Vector2i(999999, 999999)
var _target: Node3D
## Optional own world (the title screen's fly-over); by default the open game's.
var store: WorldStore
var seed := 0
var preview := false

func _ready() -> void:
	ChunkNode.ensure_shared()
	KitFlora.preload_all()

func set_target(t: Node3D) -> void:
	_target = t

static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))

static func lod_for(d: int) -> int:
	if d <= 2:
		return 1
	if d <= 4:
		return 2
	return 4

func _exit_tree() -> void:
	for k in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[k])
	_jobs.clear()

func _process(_delta: float) -> void:
	if _target == null or (store if store else Game.store) == null:
		return
	var c := chunk_of(_target.global_position)
	if c != _center:
		_center = c
		_retarget()
	_launch_jobs()
	_collect()

func is_ready_at(p: Vector3) -> bool:
	var c: ChunkNode = chunks.get(chunk_of(p))
	return c != null and c.near

func get_chunk(k: Vector2i) -> ChunkNode:
	return chunks.get(k)

func _dist(k: Vector2i) -> int:
	return maxi(absi(k.x - _center.x), absi(k.y - _center.y))

func _retarget() -> void:
	# Unload far chunks (their data is already on disk or queued in Game's dirty set).
	for k in chunks.keys():
		if _dist(k) > view_radius + 1:
			chunks[k].queue_free()
			chunks.erase(k)
	for k in chunks:
		var node: ChunkNode = chunks[k]
		var d := _dist(k)
		node.set_near(d <= near_radius)
		if node.lod != lod_for(d) and not _jobs.has(k):
			_submit(k, "lod")
		var want_grass := d <= grass_radius and grass_density > 0.0
		if want_grass and not node.has_grass() and not _jobs.has(k):
			_submit(k, "grass")
		elif not want_grass and node.has_grass():
			node.set_grass(PackedFloat32Array())
	var cur := chunks.get(_center) as ChunkNode
	if cur != null and not preview:
		Game.visit_chunk(cur.data)

func _wanted() -> Array:
	var out: Array = []
	for r in view_radius + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				out.append(_center + Vector2i(dx, dz))
	return out

func _launch_jobs() -> void:
	if _jobs.size() >= max_jobs:
		return
	for k in _wanted():
		if _jobs.size() >= max_jobs:
			return
		if chunks.has(k) or _jobs.has(k):
			continue
		_submit(k, "load")

func _submit(k: Vector2i, mode: String) -> void:
	var d := _dist(k)
	# Capture the store and seed now: the world may be closed while the job runs.
	var job := {"key": k, "mode": mode, "lod": lod_for(d), "grass": d <= grass_radius, "density": grass_density,
		"store": store if store else Game.store, "seed": seed if store else Game.seed}
	if mode != "load":
		job["data"] = chunks[k].data
	_jobs[k] = WorkerThreadPool.add_task(_run_job.bind(job), false, "chunk %s" % k)

## Worker thread.
func _run_job(job: Dictionary) -> void:
	var k: Vector2i = job["key"]
	var res := {"key": k, "mode": job["mode"], "lod": job["lod"]}
	var chunk: Dictionary
	if job["mode"] == "load":
		var gen := ChunkGenerator.new(job["seed"], (job["store"] as WorldStore).has_rivers())
		chunk = (job["store"] as WorldStore).get_or_create_chunk(gen, k.x, k.y)
		res["data"] = chunk
		res["objects"] = ChunkNode.build_object_buffers(chunk)
		res["river"] = RiverMesh.build_river_arrays(chunk)
		# Build any new species meshes here, off the main thread.
		for mk in res["objects"]:
			ObjectLibrary.get_mesh(mk)
	else:
		chunk = job["data"]
	if job["mode"] != "grass":
		res["terrain"] = ChunkNode.build_terrain_arrays(chunk, job["lod"])
	if job["grass"] and job["mode"] != "lod":
		res["grass"] = ChunkNode.build_grass_buffer(chunk, job["density"])
		res["clutter"] = ChunkNode.build_clutter_buffers(chunk, minf(job["density"], 1.0))
		for mk in res["clutter"]:
			ObjectLibrary.get_mesh(mk)
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()

func _collect() -> void:
	_mutex.lock()
	var batch := _results.slice(0, uploads_per_frame)
	_results = _results.slice(uploads_per_frame)
	_mutex.unlock()
	for res in batch:
		var k: Vector2i = res["key"]
		if _jobs.has(k):
			WorkerThreadPool.wait_for_task_completion(_jobs[k])
			_jobs.erase(k)
		var d := _dist(k)
		if res["mode"] == "load":
			if d > view_radius + 1 or chunks.has(k):
				continue
			var node := ChunkNode.new()
			node.setup(res["data"], res["terrain"], res["lod"], res["objects"])
			node.set_river(res["river"])
			add_child(node)
			chunks[k] = node
			node.set_near(d <= near_radius)
			if res.has("grass") and d <= grass_radius:
				node.set_grass(res["grass"])
				node.set_clutter(res["clutter"])
			if k == _center and not preview:
				Game.visit_chunk(node.data)
			chunk_ready.emit(node)
		elif chunks.has(k):
			var node: ChunkNode = chunks[k]
			if res.has("terrain"):
				node.set_terrain(res["terrain"], res["lod"])
			if res.has("grass") and d <= grass_radius:
				node.set_grass(res["grass"])
				node.set_clutter(res["clutter"])
		# The center may have moved while this job ran; re-evaluate LOD/grass.
		if chunks.has(k):
			var node: ChunkNode = chunks[k]
			node.set_near(d <= near_radius)
			if node.lod != lod_for(d) and not _jobs.has(k):
				_submit(k, "lod")

## Rebuilds a chunk's terrain mesh and collision immediately (after digging).
func rebuild_now(k: Vector2i) -> void:
	var node: ChunkNode = chunks.get(k)
	if node == null:
		return
	node.set_terrain(ChunkNode.build_terrain_arrays(node.data, node.lod), node.lod)

## Applies a crater across every loaded chunk it touches (shared edges stay in sync).
func dig(world_pos: Vector3, radius: float, depth: float) -> void:
	var touched: Array = []
	var c0 := chunk_of(world_pos - Vector3(radius + 1, 0, radius + 1))
	var c1 := chunk_of(world_pos + Vector3(radius + 1, 0, radius + 1))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var node: ChunkNode = chunks.get(Vector2i(cx, cz))
			if node == null:
				continue
			if node.dig(world_pos.x - cx * ChunkGenerator.SIZE, world_pos.z - cz * ChunkGenerator.SIZE, radius, depth):
				touched.append(node.key)
	for k in touched:
		rebuild_now(k)
		# Grass that was floating over the crater is regenerated against the new ground.
		var node: ChunkNode = chunks[k]
		if node.has_grass() and not _jobs.has(k):
			_submit(k, "grass")

## Harvests the undergrowth plant nearest the segment from..to, in whichever loaded
## chunk it grows. Returns {"key", "pos"} or {}.
func harvest_under(from: Vector3, to: Vector3, reach: float) -> Dictionary:
	var c0 := chunk_of(to - Vector3(reach + 1, 0, reach + 1))
	var c1 := chunk_of(to + Vector3(reach + 1, 0, reach + 1))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var node: ChunkNode = chunks.get(Vector2i(cx, cz))
			if node == null:
				continue
			var got := node.harvest_under(from, to, reach)
			if not got.is_empty():
				return got
	return {}

## Regrows a chunk's grass in the background, e.g. after something was built on it.
func refresh_grass(k: Vector2i) -> void:
	var node: ChunkNode = chunks.get(k)
	if node != null and node.has_grass() and not _jobs.has(k):
		_submit(k, "grass")

func apply_settings(radius: int, grass: float) -> void:
	view_radius = radius
	grass_density = grass
	_center = Vector2i(999999, 999999)
	for k in chunks:
		chunks[k].set_grass(PackedFloat32Array())
