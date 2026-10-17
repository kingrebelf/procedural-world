class_name BoatManager
extends Node3D
## Puts the world's boats (Boats.plan) on the water around the player and hands their
## crews to NPCManager when you come close enough to meet them. Other code can launch a
## boat of its own with spawn() (pirates closing in), find open water with
## big_water_near(), and hear about boats as they appear and go (boat_added/boat_removed).

signal boat_added(boat: BoatNode)
signal boat_removed(boat: BoatNode)

const VIEW := 900.0 ## boats closer than this are on the water
const CREW_R := 190.0 ## crews come aboard (NPCManager) inside this
const SCAN_EVERY := 0.5

var player: Node3D
var npcs: NPCManager
var boats: Dictionary = {} ## Vector2i cell (or spawned id) -> BoatNode
var _field: WorldField
var _scan_t := 0.0
var _pending: Array = [] ## cells still to plan
var _spawned := 0
var _plans: Dictionary = {} ## Vector2i cell -> its Boats.plan ({} = no boat)
var _task := -1 ## the worker surveying a cell
var _task_cell := Vector2i.ZERO
var _task_out: Array = []
var _wgen: ChunkGenerator ## the surveying worker's own generator (one task at a time)

func _ready() -> void:
	add_to_group("boat_manager")

## The world's terrain field (with the save's rivers flag, so lakes match the land).
func field() -> WorldField:
	if _field == null and Game.store != null:
		_field = ChunkGenerator.new(Game.seed, Game.store.has_rivers()).field
	return _field

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func now_t() -> float:
	return Boats.world_time(Game.day, Game.day_seconds)

func _process(delta: float) -> void:
	_feed_wakes()
	if player == null or field() == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_scan()
	# Planning a cell surveys its lake (thousands of terrain samples): one at a time, on a
	# worker thread with its own generator.
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_plans[_task_cell] = _task_out[0] if not _task_out.is_empty() else {}
		_consider(_task_cell)
	while _task < 0 and not _pending.is_empty():
		var c: Vector2i = _pending.pop_back()
		if _plans.has(c):
			_consider(c)
			continue
		_task_cell = c
		_task_out = []
		var out := _task_out
		if _wgen == null:
			_wgen = ChunkGenerator.new(Game.seed, Game.store.has_rivers())
		var wf := _wgen.field
		_task = WorkerThreadPool.add_task(func(): out.append(Boats.plan(wf, c.x, c.y)), false, "boats %s" % c)

func _scan() -> void:
	var pp := player.global_position
	var lo := Boats.cell_of(pp.x - VIEW, pp.z - VIEW)
	var hi := Boats.cell_of(pp.x + VIEW, pp.z + VIEW)
	var want := {}
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cz)
			want[c] = true
			if not boats.has(c) and not (_plans.has(c) and (_plans[c] as Dictionary).is_empty()) and not _pending.has(c):
				_pending.push_front(c)
	# Nearest cells first (taken from the back).
	var p2 := Vector2(pp.x, pp.z)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_to(p2 / Boats.CELL) > (Vector2(b) + Vector2(0.5, 0.5)).distance_to(p2 / Boats.CELL))
	for key in boats.keys():
		var b: BoatNode = boats[key]
		if not is_instance_valid(b):
			boats.erase(key)
			continue
		var far := b.global_position.distance_to(pp) > VIEW + 120.0
		if key is Vector2i and not want.has(key) or far:
			_remove(key)
			continue
		var close := Vector2(pp.x, pp.z).distance_to(b.pos2()) < CREW_R
		if npcs:
			if close and b.crew_nodes.is_empty():
				npcs.board(b)
			elif not close and not b.crew_nodes.is_empty():
				npcs.disembark(b)

func _consider(c: Vector2i) -> void:
	if boats.has(c):
		return
	var pp := player.global_position
	var center := Vector2((c.x + 0.5) * Boats.CELL, (c.y + 0.5) * Boats.CELL)
	if center.distance_to(Vector2(pp.x, pp.z)) > VIEW + Boats.CELL:
		return
	var site: Dictionary = _plans.get(c, {})
	if site.is_empty():
		return
	var b := BoatNode.new().setup(site, now_t())
	b.players = _player_points
	add_child(b)
	boats[c] = b
	boat_added.emit(b)

func _remove(key) -> void:
	var b: BoatNode = boats.get(key)
	boats.erase(key)
	if b == null or not is_instance_valid(b):
		return
	if npcs and not b.crew_nodes.is_empty():
		npcs.disembark(b)
	boat_removed.emit(b)
	b.queue_free()

func _player_points() -> Array:
	var out: Array = [player.global_position]
	for p in Net.peers.values():
		if int((p as Dictionary).get("planet", -1)) == Game.planet and p.get("pos") is Vector3:
			out.append(p["pos"])
	return out

# --- For other systems -------------------------------------------------------------------

## Every boat on the water near the player.
func all_boats() -> Array:
	return boats.values().filter(func(b): return b != null and is_instance_valid(b))

## The boat whose deck or hull is at `pos` (within its length), or null.
func boat_at(pos: Vector3) -> BoatNode:
	for b in all_boats():
		var d: Dictionary = Boats.KINDS[b.kind]
		if Vector2(pos.x, pos.z).distance_to(b.pos2()) < float(d["len"]) * 0.55:
			return b
	return null

## How far open water reaches round (x, z) in metres (0 on land or in shallows).
func open_water(x: float, z: float) -> float:
	return Boats.open_radius(field(), x, z) if field() != null else 0.0

## A point on open water at least `min_open` m wide, between `near` and `far` metres from
## `from` (tries a ring of points). Vector3.INF if there is none.
func big_water_near(from: Vector3, min_open := 100.0, near := 60.0, far := 400.0) -> Vector3:
	if field() == null:
		return Vector3.INF
	for ring in [near, (near + far) * 0.5, far]:
		for k in 10:
			var a: float = TAU * k / 10.0 + ring * 0.01
			var p: Vector2 = Vector2(from.x, from.z) + Vector2(cos(a), sin(a)) * ring
			if Boats.open_radius(_field, p.x, p.y) >= min_open:
				return Vector3(p.x, 0.0, p.y)
	return Vector3.INF

## Puts a boat of `kind` on the water at `at` facing `yaw`, crewed by `faction` ("pirate"
## crews are hostile: rel -60, job "pirate"). `crew_recs`: NPC records to use instead of
## generated ones (each gets boat/station/faction set). Spawned boats aren't saved; their
## crews board at once if the player is near. Returns the boat (sail it with sail_to).
func spawn(kind: String, at: Vector3, yaw := 0.0, faction := "pirate", crew_recs: Array = []) -> BoatNode:
	if not Boats.KINDS.has(kind):
		return null
	_spawned += 1
	var id := Vector2i(Boats.SPAWNED_BASE + _spawned, Boats.SPAWNED_BASE)
	var r := RandomNumberGenerator.new()
	r.randomize()
	var d: Dictionary = Boats.KINDS[kind]
	var names: Array = Boats.SHIP_NAMES[clampi(int(d["era"]), 0, 2)]
	var site := {"boat": kind, "sx": id.x, "sz": id.y, "center": Vector2(at.x, at.z), "era": int(d["era"]), "open": 0.0,
		"loop": 0.0, "phase": 0.0, "dir": 1.0, "yaw": yaw, "name": ("Black " if faction == "pirate" else "") + String(names[r.randi() % names.size()]),
		"faction": faction, "seed": r.randi(), "outer": float(d["len"]) * 0.6 + 4.0, "spawned": true}
	if not crew_recs.is_empty():
		site["crew"] = crew_recs
	var b := BoatNode.new().setup(site, 0.0)
	b.players = _player_points
	add_child(b)
	boats["spawned_%d" % _spawned] = b
	boat_added.emit(b)
	if npcs and player and player.global_position.distance_to(at) < CREW_R:
		npcs.board(b)
	return b

## Puts the boat of a planned site on the water now (it would come anyway, in its turn),
## `still`: hove to from the start. For tools that need a particular boat in view.
func put(site: Dictionary, still := false) -> BoatNode:
	var c := Vector2i(int(site["cx"]), int(site["cz"]))
	_plans[c] = site
	_consider(c)
	var b: BoatNode = boats.get(c)
	if b and still:
		b.held = 1.0
	return b

## Takes a spawned (or any) boat off the water.
func despawn(b: BoatNode) -> void:
	for key in boats.keys():
		if boats[key] == b:
			_remove(key)
			return

## Hands the lake shader (water_wakes) the waves raised by the boats under way nearest the
## view, at most 8.
var _wakes_a := PackedVector4Array()
var _wakes_b := PackedVector4Array()
var _wakes_live := false

func _feed_wakes() -> void:
	var lake := Water.lake
	if not is_instance_valid(lake) or not (lake.material_override is ShaderMaterial):
		return
	var cam := get_viewport().get_camera_3d()
	var found: Array = [] # [distance, info]
	if cam:
		var cp := cam.global_position
		for b in boats.values():
			if not is_instance_valid(b):
				continue
			var info: Array = (b as BoatNode).wake_info()
			if info.is_empty():
				continue
			var a: Vector4 = info[0]
			var dist := Vector2(a.x, a.y).distance_to(Vector2(cp.x, cp.z))
			if dist < 500.0:
				found.append([dist, info])
	found.sort_custom(func(p, q): return p[0] < q[0])
	if found.is_empty() and not _wakes_live:
		return
	_wakes_live = not found.is_empty()
	_wakes_a.resize(8)
	_wakes_b.resize(8)
	for i in 8:
		_wakes_a[i] = found[i][1][0] if i < found.size() else Vector4.ZERO
		_wakes_b[i] = found[i][1][1] if i < found.size() else Vector4.ZERO
	var m := lake.material_override as ShaderMaterial
	m.set_shader_parameter("wakes_a", _wakes_a)
	m.set_shader_parameter("wakes_b", _wakes_b)
