class_name VehicleManager
extends Node3D
## Your vehicles. Each is a record in Game.vehicles ({id, kind, pos, yaw, q}), saved with
## the player; a Vehicle node exists for each one near the player. Deploying a vehicle
## item puts a record in the world, packing it up turns it back into the item.

const RANGE := 220.0 ## vehicles closer than this are live nodes

var streamer: ChunkStreamer
var player: Node3D
var npcs: NPCManager
var nodes: Dictionary = {} ## id -> Vehicle
var _scan := 0.0

func ground(x: float, z: float) -> float:
	if streamer == null:
		return NAN
	var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
	var c := streamer.get_chunk(k)
	if c == null:
		return NAN
	return ChunkGenerator.height_at(c.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE)

func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		refresh()

## Spawns nodes for records in range and frees the ones that drifted out of it.
func refresh() -> void:
	if player == null:
		return
	var pp := player.global_position
	var live := {}
	for r in Game.vehicles:
		if int(r.get("planet", 0)) != Game.planet:
			continue # parked on another world (or out in space)
		var id: int = r["id"]
		live[id] = true
		var near: bool = (r["pos"] as Vector3).distance_to(pp) < RANGE
		var n: Vehicle = nodes.get(id)
		if near and n == null:
			n = Vehicle.new().setup(r)
			n.ground = ground
			add_child(n)
			nodes[id] = n
		elif not near and n != null and n.rider == null:
			n.queue_free()
			nodes.erase(id)
	for id in nodes.keys():
		if not live.has(id):
			if is_instance_valid(nodes[id]):
				nodes[id].queue_free()
			nodes.erase(id)

func all_nodes() -> Array:
	return nodes.values().filter(func(n): return is_instance_valid(n))

## Puts a vehicle item into the world at `at`, facing `yaw`. Returns the node, or null if
## the ground there isn't loaded or is under water the vehicle can't stand in.
func deploy(item: Dictionary, at: Vector3, yaw: float) -> Vehicle:
	var k: String = item["type"]
	if not Vehicle.is_vehicle_item(k):
		return null
	var h := ground(at.x, at.z)
	if is_nan(h):
		return null
	var surface := Water.surface_height(at.x, at.z, 0.0)
	var afloat := Vehicle.is_boat(k)
	if afloat:
		# Boats go in the water, deep enough to float her.
		if surface - h < float(Sailing.BOATS[k]["draft"]) + 0.1:
			return null
	elif surface - h > 1.0 and not Vehicle.KINDS[k].has("hover"):
		return null
	var id := 1
	for r in Game.vehicles:
		id = maxi(id, int(r["id"]) + 1)
	var y := surface if afloat else maxf(h, surface if Vehicle.KINDS[k].has("hover") else h) + 0.4
	var r := {"id": id, "kind": k, "pos": Vector3(at.x, y, at.z),
		"yaw": yaw, "q": float(item.get("quality", 1.0)), "origin": item.get("origin", {}), "planet": Game.planet}
	Game.vehicles.append(r)
	Game.mark_player_dirty()
	refresh()
	return nodes.get(id)

## Removes the vehicle from the world and returns it as an item (in your pack if it fits).
func pack_up(v: Vehicle) -> bool:
	if v == null or v.rider != null:
		return false
	var it := ItemDB.make(v.kind, 1, float(v.rec.get("q", 1.0)), v.rec.get("origin", {}))
	if not Game.give(it):
		return false
	Game.vehicles.erase(v.rec)
	nodes.erase(int(v.rec["id"]))
	v.queue_free()
	Game.mark_player_dirty()
	return true

func by_id(id: int) -> Vehicle:
	refresh()
	return nodes.get(id)
