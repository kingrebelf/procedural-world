extends SceneTree
## Plans cave networks near the origin of a v10 world and meshes the chunks of one,
## printing sizes and timings. SEED env picks the world.

func _initialize() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 12345
	WorldField.terrain_v = 10
	var gen := ChunkGenerator.new(seed, true)
	var found := 0
	var first := {}
	for sz in range(-3, 3):
		for sx in range(-3, 3):
			var t := Time.get_ticks_msec()
			var net := Caves.network(gen, sx, sz)
			if net.is_empty():
				continue
			found += 1
			var ps: PackedFloat32Array = net["prims"]
			print("cell %d,%d: mouth %s, %d prims, %d chambers, plan %d ms" % [sx, sz, net["mouth"], ps.size() / Caves.STRIDE, net["chambers"].size(), Time.get_ticks_msec() - t])
			if first.is_empty():
				first = net
	print("networks: %d of 36 cells" % found)
	if first.is_empty():
		quit()
		return
	var mo: Vector3 = first["mouth"]
	var mc := Vector2i(int(floor(mo.x / 64.0)), int(floor(mo.z / 64.0)))
	var tris := 0
	var holes := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var t := Time.get_ticks_msec()
			var ch := gen.generate(mc.x + dx, mc.y + dz)
			var tg := Time.get_ticks_msec() - t
			if not ch.has("cave"):
				continue
			t = Time.get_ticks_msec()
			var res := Caves.build(ch)
			var tm := Time.get_ticks_msec() - t
			var nt: int = (res["faces"] as PackedVector3Array).size() / 3 if not res.is_empty() else 0
			var nh := 0
			if ch.has("hole"):
				for b in (ch["hole"] as PackedByteArray):
					nh += b
			var extra := 0
			for o in ch["objects"]:
				if o["t"] == "cave_glow" or (o["p"] as Vector3).y < ChunkGenerator.height_at(ch, o["p"].x, o["p"].z) - 2.0:
					extra += 1
			tris += nt
			holes += nh
			print("chunk %d,%d: gen %d ms, mesh %d ms, %d tris, %d hole verts, %d underground objects" % [mc.x + dx, mc.y + dz, tg, tm, nt, nh, extra])
	print("total tris %d, hole verts %d" % [tris, holes])
	quit()
