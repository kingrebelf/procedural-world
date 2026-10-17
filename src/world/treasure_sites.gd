class_name TreasureSites
extends Node
## Buries the chests of your treasure hunts (Game.treasure, see Treasure) as the land they
## lie in streams in, or at once when a new map points into land already loaded. Once in
## its chunk the chest is part of that chunk's snapshot, like anything built there.

var streamer: ChunkStreamer

func _ready() -> void:
	streamer.chunk_ready.connect(_on_chunk)
	Game.treasure_started.connect(_on_started)

func _on_started(h: Dictionary) -> void:
	var n := streamer.get_chunk(Treasure.chunk_of(h))
	if n != null:
		bury(n, h)

func _on_chunk(n: ChunkNode) -> void:
	for h in Game.treasure:
		if int(h["planet"]) == Game.planet and not h.get("found", false) and Treasure.chunk_of(h) == n.key:
			bury(n, h)

## Puts hunt `h`'s chest under the ground of chunk `n` (once) and heaps the turned soil
## over it. The hunt and its marker move to where the chest really went.
func bury(n: ChunkNode, h: Dictionary) -> void:
	var id := int(h["id"])
	if not Treasure.chest_in(n.data, id).is_empty():
		return
	var lp := Treasure.burial(n.data, h)
	Treasure.dress(n.data, lp)
	var era := int(h["era"])
	var yaw := float(WHash.hash2(id, n.key.x, n.key.y) % 628) / 100.0
	n.add_object(Eras.CACHE_TYPES[era], lp, yaw, era, {"loot": (h["loot"] as Array).duplicate(true), "opened": false, "treasure": id})
	h["x"] = n.position.x + lp.x
	h["z"] = n.position.z + lp.z
	var m := Game.markers.get_by_id(int(h.get("marker", -1)))
	if not m.is_empty():
		m["x"] = h["x"]
		m["z"] = h["z"]
	Game.touch_player()
	streamer.rebuild_now(n.key)
	if n.has_grass():
		streamer.refresh_grass(n.key)
