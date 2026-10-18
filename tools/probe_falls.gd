extends SceneTree
## Lists the waterfalls (Waterfalls) within --r metres of the origin (default 6000) for
## --seed (default 4242): where they are, how high, in how many tiers.
##   godot --headless --path . --script res://tools/probe_falls.gd -- --seed=4242

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seed := int(args.get("seed", "4242"))
	var r := float(args.get("r", "6000"))
	Planets.apply(Planets.get_planet(seed, 0, "human"))
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(seed, true)
	var n := 0
	var cells := 0
	var c := int(ceil(r / Waterfalls.CELL))
	var all := []
	var why := {}
	for iz in range(-c, c):
		for ix in range(-c, c):
			cells += 1
			var f := Waterfalls.plan(g, ix, iz)
			if f.has("no"):
				why[f["no"]] = why.get(f["no"], 0) + 1
				continue
			n += 1
			var l: Vector2 = f["lip"]
			all.append([l.length(), l.x, l.y, f["drop"], (f["steps"] as PackedFloat32Array).size(), f["top"]])
	all.sort()
	for a in all:
		print("%5.0f m out: lip %.0f, %.0f  drop %.1f m in %d  top %.1f" % a)
	print("cells without: ", why)
	print("%d falls in %d cells of %.0f m (one per %.1f km2)" % [n, cells, Waterfalls.CELL, cells * pow(Waterfalls.CELL / 1000.0, 2) / maxf(n, 1)])
	quit()
