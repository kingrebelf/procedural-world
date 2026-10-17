extends SceneTree
## Checks that road bridges meet the ground: generates the chunks along every road near
## the origin and reports bridge ends that stand above or sink below the road, and decks
## buried in the land. SEED, TV (terrain version) and R (settlement cells) from the
## environment. godot --headless --path . --script res://tools/probe_bridges.gd
func _init() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242
	var tv := int(OS.get_environment("TV")) if OS.get_environment("TV") != "" else 7
	var R := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 2
	var res := survey(seed, tv, R)
	for l in res["lines"]:
		print(l)
	print("bridges %d, bad ends %d" % [res["total"], res["bad"]])
	quit()

## Every bridge on the roads of the settlements within r cells of the origin:
## {"total", "bad", "lines"}.
static func survey(seed: int, tv: int, R: int) -> Dictionary:
	var keep_tv := WorldField.terrain_v
	WorldField.terrain_v = tv
	var lines: Array = []
	var g := ChunkGenerator.new(seed, true)
	var cache := {}
	var gen := func(cx: int, cz: int) -> Dictionary:
		var k := Vector2i(cx, cz)
		if not cache.has(k):
			cache[k] = g.generate(cx, cz)
		return cache[k]
	var ground := func(x: float, z: float) -> float:
		var cx := int(floor(x / 64.0))
		var cz := int(floor(z / 64.0))
		return ChunkGenerator.height_at(gen.call(cx, cz), x - cx * 64.0, z - cz * 64.0)
	var seen := {}
	var found: Array = []
	var profs: Array = []
	var bad := 0
	var total := 0
	for sz in range(-R, R + 1):
		for sx in range(-R, R + 1):
			var s := g.settlement_at(sx, sz)
			if s.is_empty():
				continue
			for t in g.owned_roads(s):
				var prof := g.road_profile(s, t)
				var pts: PackedVector2Array = prof["pts"]
				# Chunks along the road.
				for p in pts:
					var k := Vector2i(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))
					if seen.has(k):
						continue
					seen[k] = true
					var c: Dictionary = gen.call(k.x, k.y)
					for o in c["objects"]:
						if o["t"] != "bridge":
							continue
						var wp: Vector3 = Vector3(k.x * 64.0, 0, k.y * 64.0) + o["p"]
						found.append({"o": o, "wp": wp, "towns": [s, t], "prof": prof})
				profs.append({"prof": prof, "towns": [s, t]})
	var ends: Array = []
	for f in found:
		var o: Dictionary = f["o"]
		var sp: int = o["sp"]
		if not Bridge.is_viaduct(sp):
			continue
		var yaw: float = o["r"]
		var dir := Vector2(sin(yaw), cos(yaw))
		for sgn in [-1.0, 1.0]:
			ends.append(Vector2(f["wp"].x, f["wp"].z) + dir * Bridge.span_of(sp) * 0.5 * sgn)
	for f in found:
		var bd := INF
		for pr in profs:
			for q in pr["prof"]["pts"]:
				var d: float = q.distance_to(Vector2(f["wp"].x, f["wp"].z))
				if d < bd:
					bd = d
					f["prof"] = pr["prof"]
					f["towns"] = pr["towns"]
	for f in found:
		var o: Dictionary = f["o"]
		var sp: int = o["sp"]
		var L := Bridge.span_of(sp)
		var H := Bridge.deck_of(sp)
		var rise := Bridge.rise_of(sp)
		var via := Bridge.is_viaduct(sp)
		var wp: Vector3 = f["wp"]
		var yaw: float = o["r"]
		var dir := Vector2(sin(yaw), cos(yaw))
		var deck_y := wp.y - 0.15 + H
		var msg := ""
		var worst := 0.0
		for sgn in [-1.0, 1.0]:
			var c2: Vector2 = Vector2(wp.x, wp.z) + dir * L * 0.5 * sgn
			var dc := INF
			for tt in f["towns"]:
				dc = minf(dc, c2.distance_to(tt["center"]) / float(tt["outer"]))
			if via:
				var joined := 0
				for e in ends:
					if e.distance_to(c2) < 2.5:
						joined += 1
				if joined > 1:
					msg += " end%+d joins;" % int(sgn)
					continue
				var top: float = deck_y + sgn * rise * 0.5
				var step: float = top - ground.call(c2.x + dir.x * 0.5 * sgn, c2.y + dir.y * 0.5 * sgn)
				var pr: Dictionary = f["prof"]
				var pp: PackedVector2Array = pr["pts"]
				var bi := 0
				for q in pp.size():
					if pp[q].distance_to(c2) < pp[bi].distance_to(c2):
						bi = q
				var sh: Vector3 = g.field.shape(pp[bi].x, pp[bi].y)
				msg += " end%+d step %.2f town %.2f [pt %d/%d d %.1f lv %.1f gnd %.1f raw %.1f rough %.1f rt %.1f air %d est %.1f land %.1f runs %s];" % [int(sgn), step, dc, bi, pp.size(), pp[bi].distance_to(c2), pr["level"][bi], ground.call(pp[bi].x, pp[bi].y), sh.x + sh.y, sh.z, g.field.river_t(pp[bi].x, pp[bi].y), pr["air"][bi], g._road_ground(pr, pp[bi]), g._land_at(pp[bi]), str(g._viaduct_runs(pr))]
				worst = maxf(worst, absf(step))
			else:
				var e: Vector2 = c2 + dir * Bridge.RAMP * sgn
				var up: float = deck_y - Bridge.DROP - ground.call(e.x, e.y)
				var bank: float = ground.call(c2.x + dir.x * sgn, c2.y + dir.y * sgn) - deck_y
				msg += " end%+d ramp-end above gnd %.2f, bank over deck %.2f town %.2f;" % [int(sgn), up, bank, dc]
				worst = maxf(worst, maxf(up, bank))
		var bury := INF
		for q in range(2, 7):
			var z := -L * 0.5 + L * q / 8.0
			var pz: Vector2 = Vector2(wp.x, wp.z) + dir * z
			var line: float = deck_y + (rise * z / L if via else 0.0)
			bury = minf(bury, line - ground.call(pz.x, pz.y))
		msg += " min clearance %.2f" % bury
		if bury < -0.6:
			worst = 9.0
		total += 1
		if worst > 0.8:
			bad += 1
		lines.append("%s L=%d H=%.1f rise=%.1f at (%.0f,%.0f):%s %s" % ["viaduct" if via else "river", int(L), H, rise, wp.x, wp.z, msg, "BAD" if worst > 0.8 else ""])
	WorldField.terrain_v = keep_tv
	return {"total": total, "bad": bad, "lines": lines}
