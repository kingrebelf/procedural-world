extends SceneTree
## How a world's climates fall (v18): the share of regions in each warmth and wetness
## level within R metres of the spawn, the nearest region of palms and jungle, and a
## coarse map. Run: godot --headless --path . --script res://tools/probe_climate.gd
## (env SEED, R).

func _init() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 8000.0
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	Eras.theme = "human"
	var f := WorldField.new(seed)
	var counts := {}
	var nearest := {}
	var n := 0
	var step := 128.0
	var rows: Array = []
	var x := -reach
	var cells := int(reach * 2.0 / step)
	for j in cells:
		var row := ""
		for i in cells:
			var px := -reach + i * step
			var pz := -reach + j * step
			var c := WorldField.region_climate(f.region_hash_at(px, pz))
			var key := "%d%d" % [c.x, c.y]
			counts[key] = int(counts.get(key, 0)) + 1
			n += 1
			var d := Vector2(px, pz).length()
			if d < float(nearest.get(key, INF)):
				nearest[key] = d
			if i % 2 == 0 and j % 2 == 0:
				row += "*" if c.x == 3 and c.y >= 2 else ("~" if c.x == 3 else ("^" if c.x == 0 else ("." if c.x == 1 else " ")))
		if j % 2 == 0:
			rows.append(row)
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("warm %s wet %s: %5.1f%%  nearest %6.0f m" % [k[0], k[1], 100.0 * counts[k] / n, nearest[k]])
	print("map (* tropics, ~ hot dry, ^ cold, . cool, blank temperate; spawn at centre):")
	for r in rows:
		print(r)
	quit()
