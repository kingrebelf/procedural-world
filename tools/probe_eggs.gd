extends SceneTree
## Surveys the hidden finds (EasterEggs) round the origin: how many cells plan one, of
## which kinds, how far out, and whether the chunk that should hold each really places
## it. SEED, R (egg cells each way) and GEN (1 to also generate the chunks) from the
## environment. godot --headless --path . --script res://tools/probe_eggs.gd
func _init() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var R := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 4
	var gen := OS.get_environment("GEN") == "1"
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	# A new human homeland (Planets.apply, without the autoloads it pulls in).
	WorldField.allowed_eras = [Eras.MEDIEVAL, Eras.SCIFI]
	Eras.theme = "human"
	var g := ChunkGenerator.new(seed, true)
	var count := {}
	var placed := 0
	var planned := 0
	for wz in range(-R, R):
		for wx in range(-R, R):
			var e := EasterEggs.plan(g, wx, wz)
			if e.is_empty():
				continue
			planned += 1
			count[e["t"]] = int(count.get(e["t"], 0)) + 1
			var p: Vector2 = e["p"]
			var line := "%-11s at %7.1f, %7.1f  (%4d m out, era %d)" % [e["t"], p.x, p.y, int(p.length()), e["era"]]
			if gen:
				var cx := int(floor(p.x / ChunkGenerator.SIZE))
				var cz := int(floor(p.y / ChunkGenerator.SIZE))
				var c := g.generate(cx, cz)
				var got := false
				for o in c["objects"]:
					if o["t"] == e["t"]:
						got = true
						var wp := Vector2(cx * ChunkGenerator.SIZE + o["p"].x, cz * ChunkGenerator.SIZE + o["p"].z)
						line += "  placed %.1f m off, y %.1f" % [wp.distance_to(p), o["p"].y]
				if got:
					placed += 1
				else:
					line += "  NOT PLACED"
			print(line)
	var cells := 4 * R * R
	print("%d of %d cells plan a find (%s)%s" % [planned, cells, str(count), (", %d placed" % placed) if gen else ""])
	for t in EasterEggs.TYPES:
		var m := ObjectLibrary.get_mesh(t)
		print("%s mesh: %d surfaces, aabb %s" % [t, m.get_surface_count(), m.get_aabb()])
	quit()
