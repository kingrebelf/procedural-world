class_name WorldBuilder
extends RefCounted
## Builds the land of a finite world (WorldBounds) ahead of the people in it: every tile
## within BUFFER tiles of someone is generated and saved before they get there, nearest
## first, on worker threads. A new world builds START tiles round the centre before you
## step in. Only land someone has come near is ever built, so the world stays small on
## disk. The game runs one for you (Game.builder) and a server one for every player.

const START := 20 ## tiles built in every direction round the centre of a new world
const BUFFER := 20 ## tiles kept built in every direction round each player
## Tiles within this of a player are left to the streamer, which loads them anyway (two
## workers writing one chunk's file at once would garble it).
const NEAR := 8

var store: WorldStore
var seed: int
var rivers: bool
var max_tasks := 1
var built := 0 ## tiles this builder made

var _queue: Array = [] ## Vector2i, nearest first
var _queued := {}
var _known := {} ## tiles built, or found already on disk
var _tasks := {} ## Vector2i -> worker task id
var _centres := {} ## who -> the tile they were last seen in

func _init(s: WorldStore, world_seed: int, has_rivers: bool) -> void:
	store = s
	seed = world_seed
	rivers = has_rivers

static func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))

## Asks for the land within `radius` tiles of `who` (at p) to be built. Cheap to call
## every frame: it only looks again when they cross into a new tile.
func watch(who: Variant, p: Vector3, radius := BUFFER, near := NEAR) -> void:
	var c := tile_of(p)
	if _centres.get(who) == c:
		return
	_centres[who] = c
	var fresh: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dz)) <= near:
				continue
			var k := c + Vector2i(dx, dz)
			if _known.has(k) or _queued.has(k) or _tasks.has(k) or not WorldBounds.buildable(k):
				continue
			if store.has_chunk(k.x, k.y):
				_known[k] = true
				continue
			fresh.append(k)
	if fresh.is_empty():
		return
	fresh.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	for k in fresh:
		_queued[k] = true
	# The one who moved last is the one walking into unbuilt land: their tiles go first.
	_queue = fresh + _queue

func forget(who: Variant) -> void:
	_centres.erase(who)

## Collects finished tiles and starts more. Call every frame.
func tick() -> void:
	for k in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			WorkerThreadPool.wait_for_task_completion(_tasks[k])
			_tasks.erase(k)
			_known[k] = true
			built += 1
	while _tasks.size() < max_tasks and not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		_queued.erase(k)
		if _known.has(k) or store.has_chunk(k.x, k.y):
			_known[k] = true
			continue
		_tasks[k] = WorkerThreadPool.add_task(_build.bind(store, seed, rivers, k), false, "build tile %s" % k)

## Tiles being built right now.
func busy() -> int:
	return _tasks.size()

## Tiles waiting or being built.
func remaining() -> int:
	return _queue.size() + _tasks.size()

## Builds everything waiting here and now, on this thread (tools and tests, where no
## frames run for the workers' loads to finish on).
func build_now() -> void:
	stop_tasks()
	while not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		_queued.erase(k)
		if not _known.has(k) and not store.has_chunk(k.x, k.y):
			_build(store, seed, rivers, k)
			built += 1
		_known[k] = true

func stop_tasks() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_known[k] = true
	_tasks.clear()

## Waits for the tiles being built and drops the rest.
func stop() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()
	_queue.clear()
	_queued.clear()
	_centres.clear()

## Worker thread.
static func _build(s: WorldStore, sd: int, riv: bool, k: Vector2i) -> void:
	s.get_or_create_chunk(ChunkGenerator.new(sd, riv), k.x, k.y)
