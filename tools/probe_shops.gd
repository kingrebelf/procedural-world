extends SceneTree
## Lists the shops, guild halls and houses for sale in the settlements near the origin,
## and where each room type's counter fits. SEED, TV (terrain version) and R (settlement
## cells) from the environment.
## godot --headless --path . --script res://tools/probe_shops.gd
func _initialize() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var tv := int(OS.get_environment("TV")) if OS.get_environment("TV") != "" else 8
	var R := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 2
	WorldField.terrain_v = tv
	for t in TownShops.ROOMS:
		var ft := TownShops.fit(t)
		print("%-15s %s" % [t, ft if not ft.is_empty() else "NO COUNTER"])
	var g := ChunkGenerator.new(seed, true)
	for sz in range(-R, R + 1):
		for sx in range(-R, R + 1):
			var s := g.settlement_at(sx, sz)
			if s.is_empty():
				continue
			var plan := TownShops.plan(g, s)
			var shops := plan.filter(func(h): return h["kind"] != "")
			print("\n%s settlement %d,%d size %d: %d rooms, %d shops" % [Eras.NAMES[s["era"]], sx, sz, int(s["size"]), plan.size(), shops.size()])
			for h in shops:
				print("  %-16s %-22s %-28s in a %s" % [h["kind"], h["label"], h["title"], h["t"]])
	quit()
