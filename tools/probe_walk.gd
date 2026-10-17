extends SceneTree
## How well people can get about the towns near spawn on the slope-aware grid: from
## each town's middle to points round it out to its outer edge (and a bit beyond), the
## share with a straight clear way, a route round, or no way at all, and search times.
##   godot --headless --path . --script res://tools/probe_walk.gd   (SEED, R env)

func _initialize() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 1500.0
	var gen := ChunkGenerator.new(seed)
	var land := {}
	var walk := WalkGrid.new(func(k: Vector2i) -> Dictionary:
		if not land.has(k):
			land[k] = gen.generate(k.x, k.y)
		return land[k])
	walk.build_per_frame = 1 << 20
	walk.search_usec = 1 << 30
	var straight := 0
	var round := 0
	var none := 0
	var scramble := 0
	var places := 0
	var lost := 0
	var worst_us := 0
	var total_us := 0
	var searched := 0
	var towns := gen.settlements_near(-reach, -reach, reach, reach)
	for s in towns.slice(0, 12):
		var c: Vector2 = s["center"]
		var outer := float(s["outer"])
		var t_none := 0
		# Work the land out first so the timings are the searches alone.
		for kz in range(floori((c.y - outer * 2.5) / 64.0), floori((c.y + outer * 2.5) / 64.0) + 1):
			for kx in range(floori((c.x - outer * 2.5) / 64.0), floori((c.x + outer * 2.5) / 64.0) + 1):
				walk.grade(kx * 64.0 + 1.0, kz * 64.0 + 1.0)
		for i in 24:
			var a := TAU * float(i) / 24.0
			var p := c + Vector2.from_angle(a) * outer * (0.4 + 0.75 * float(i % 3) / 2.0)
			if walk.clear(c, p, WalkGrid.PERSON):
				straight += 1
				continue
			var t0 := Time.get_ticks_usec()
			var r := walk.route(c, p, WalkGrid.PERSON)
			var us := Time.get_ticks_usec() - t0
			total_us += us
			searched += 1
			worst_us = maxi(worst_us, us)
			if not r["reached"]:
				var up := walk.route(c, p, WalkGrid.SCRAMBLE)
				if up["reached"]:
					scramble += 1
					continue
			if r["reached"]:
				round += 1
			else:
				none += 1
				t_none += 1
				var g := walk.grade(p.x, p.y)
				var pts: PackedVector2Array = r["pts"]
				var e := pts[pts.size() - 1]
				print("   no way to %s (grade there %.2f, height %.1f vs %.1f; got to %.1f m off)" % [p, g, gen.field.height(p.x, p.y), gen.field.height(c.x, c.y), e.distance_to(p)])
		print("town at %s outer %.0f: %d of 24 points round it can't be got to" % [c, outer, t_none])
		# The places its people work at: every one should still be got to from the square.
		var pl := NPCRoles.places(gen, s, {})
		var spots: Array = []
		for key in ["gates", "market", "towers", "wells", "holy", "tavern", "stall"]:
			spots.append_array(pl[key])
		for y in pl["shop_yards"].values():
			spots.append(y[0])
		for q in spots:
			places += 1
			if walk.clear(c, q, WalkGrid.PERSON):
				continue
			var r := walk.route(c, q, WalkGrid.PERSON)
			if not r["reached"] and not walk.route(c, q, WalkGrid.SCRAMBLE)["reached"]:
				lost += 1
				print("   can't get to a work place at %s (grade there %.2f)" % [q, walk.grade(q.x, q.y)])
	print("straight %d, round %d, scramble %d, no way %d; search avg %d us, worst %d us" % [straight, round, scramble, none, total_us / maxi(searched, 1), worst_us])
	print("work places: %d of %d can't be got to from their square" % [lost, places])
	quit()
