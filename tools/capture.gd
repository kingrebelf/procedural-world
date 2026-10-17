extends Node
## Automated screenshot tour used to check visuals without a human at the keyboard:
##   godot --path . res://src/world/world.tscn -- --capture [--out=DIR] [--seed=N] [--set=gi=0 ...] [--hud=MODE] [--env=tonemap_mode=4 ...] [--vfog=3]
## (seed 4242 unless given, so runs of the tour compare like with like)
## Finds a medieval town, a fantasy wildwood, a sci-fi outpost and an era border,
## frames each, waits for lighting to settle, and writes PNGs.

var world: Node3D
var out_dir := "user://captures"
var settle_frames := 150
var only: PackedStringArray = [] ## --shots=01,07 limits the tour to those shots
var shore_out := Vector2.ZERO ## which way the open lake lies from the beach _find_shore picked
## --hud=none hides the 2D layer, --hud=under keeps only the underwater overlay of it and
## --hud=nounder keeps all but that overlay: to tell whether an artefact is in the 3D image.
var hud_mode := ""
## --env=property=value sets a property of the world's Environment for this run, for A/B
## looks (tonemapper, exposure, contrast) without touching the game.
var env_sets: Array = []
## --vfog=N scales the volumetric haze (light shafts) for this run.
var vfog := 1.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--frames="):
			settle_frames = a.substr(9).to_int()
		if a.begins_with("--shots="):
			only = a.substr(8).split(",")
		if a.begins_with("--hud="):
			hud_mode = a.substr(6)
		if a.begins_with("--env=") and a.count("=") == 2:
			env_sets.append(a.substr(6).split("="))
		if a.begins_with("--vfog="):
			vfog = a.substr(7).to_float()
		# --set=gi=0 overrides a graphics setting for this run only (not saved), to tell
		# which effect an artefact comes from.
		if a.begins_with("--set=") and a.count("=") == 2:
			var kv := a.substr(6).split("=")
			Settings.set_value(kv[0], str_to_var(kv[1]) if str_to_var(kv[1]) != null else kv[1], false)
			print("setting ", kv[0], " = ", Settings.get_value(kv[0]))
	Settings.apply()
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Nothing may kill the photographer (castle hounds did, mid-tour).
	Game.cheats["god"] = true
	_run.call_deferred()

func _apply_hud_mode() -> void:
	var hud: HUD = world.hud if world else null
	if hud_mode == "" or hud == null:
		return
	var layer := hud.get_parent() as CanvasLayer
	if hud_mode == "none":
		layer.visible = false
		return
	# Hidden children move under one hidden holder: the HUD shows and hides them every
	# frame, which can't override a hidden parent.
	var hold := Control.new()
	hold.visible = false
	layer.add_child(hold)
	for c in layer.get_children() + hud.get_children():
		if c == hold or c == hud:
			continue
		if (c == hud._under) == (hud_mode == "nounder"):
			c.reparent(hold, false)
	print("hud mode ", hud_mode)

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_loaded(p: Player, streamer: ChunkStreamer) -> void:
	for i in 3000:
		await get_tree().process_frame
		var c := ChunkStreamer.chunk_of(p.global_position)
		var ok := streamer._jobs.is_empty() and streamer._results.is_empty()
		for dz in range(-streamer.view_radius, streamer.view_radius + 1):
			for dx in range(-streamer.view_radius, streamer.view_radius + 1):
				if not streamer.chunks.has(c + Vector2i(dx, dz)):
					ok = false
		if ok:
			return

func _find_settlement(g: ChunkGenerator, era: int, min_size := 0) -> Dictionary:
	for r in 40:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if maxi(absi(sx), absi(sz)) != r:
					continue
				var s := g.settlement_at(sx, sz)
				if not s.is_empty() and s["era"] == era and int(s["size"]) >= min_size:
					return s
	return {}

func _find_era(g: ChunkGenerator, era: int, min_w: float) -> Vector2:
	for i in 4000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (40.0 + i * 6.0)
		if g.field.era_weights(p.x, p.y)[era] >= min_w:
			return p
	return Vector2.ZERO

func _find_border(g: ChunkGenerator) -> Vector2:
	for i in 4000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 5.0)
		var w := g.field.era_weights(p.x, p.y)
		var sorted := Array(w)
		sorted.sort()
		if sorted[2] < 0.55 and sorted[1] > 0.4:
			return p
	return Vector2.ZERO

## A beach on open water: dry land just above the lake with a wide fan of deep water in
## front of it, so the shot looks out over the lake rather than at the far wall of a river
## canyon or a narrow inlet. Sets `shore_out` to the way the water lies.
func _find_shore(g: ChunkGenerator) -> Vector2:
	for i in 6000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 5.0)
		if g.field.height(p.x, p.y) >= Water.LEVEL - 4.0 or g.field.river_t(p.x, p.y) < 3.0:
			continue
		# Walk back toward the origin until we reach dry land a little above the water.
		var dir := -p.normalized()
		for k in 80:
			var q := p + dir * (k * 3.0)
			if g.field.height(q.x, q.y) > Water.LEVEL + 0.6:
				if _open_water(g, q, -dir) and _gentle_beach(g, q, -dir):
					shore_out = -dir
					return q
				break
	return Vector2.ZERO

## Low land behind and beside the spot (a beach, not the foot of a sea cliff that would
## fill one side of the frame).
func _gentle_beach(g: ChunkGenerator, q: Vector2, out: Vector2) -> bool:
	var side := Vector2(-out.y, out.x)
	for o in [side * 12.0, side * -12.0, side * 25.0, side * -25.0, -out * 15.0, -out * 30.0 + side * 15.0, -out * 30.0 - side * 15.0]:
		var w: Vector2 = q + o
		if g.field.height(w.x, w.y) > Water.LEVEL + 5.0:
			return false
	return true

func _open_water(g: ChunkGenerator, q: Vector2, out: Vector2) -> bool:
	var side := Vector2(-out.y, out.x)
	for d in [20.0, 40.0, 70.0, 110.0, 160.0]:
		for s in [-0.6, 0.0, 0.6]:
			var w: Vector2 = q + out * d + side * (d * s)
			if g.field.height(w.x, w.y) > Water.LEVEL - 1.0:
				return false
	return true

## A spot on a river bank, with a point mid-river to look at (Vector4: at.xy, look.zw).
func _find_river(g: ChunkGenerator) -> Vector4:
	var cache := {}
	for i in 6000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 4.0)
		if g.field.river_t(p.x, p.y) > 0.15 or g.field.era_weights(p.x, p.y)[Eras.MEDIEVAL] < 0.8:
			continue
		var lv := g.field.river_level(p.x, p.y, cache)
		if WorldField.river_strength(g.field.height(p.x, p.y), lv) < 0.8:
			continue
		for k in 16:
			var d := Vector2.from_angle(k * TAU / 16.0)
			var q := p + d * 26.0
			var t := g.field.river_t(q.x, q.y)
			if t > 1.8 and t < 3.5:
				return Vector4(q.x, q.y, p.x - d.x * 20.0 - d.y * 25.0, p.y - d.y * 20.0 + d.x * 25.0)
	return Vector4.ZERO

func _shot(name: String, at: Vector2, look_at: Vector2, day: float, height := 1.7, look_y := NAN, before := Callable()) -> void:
	if not only.is_empty() and not only.has(name.substr(0, 2)):
		return
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	Game.day = day
	var g := ChunkGenerator.new(Game.seed)
	var y := g.field.height(at.x, at.y) + height
	p.set_physics_process(false)
	p.global_position = Vector3(at.x, y, at.y)
	await _wait_loaded(p, streamer)
	# Loading can take a long while on a slow renderer: put the clock back to the shot's time.
	Game.day = day
	# Use the real (snapshotted, flattened) height once the chunk exists.
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(p.global_position))
	if c:
		y = ChunkGenerator.height_at(c.data, at.x - c.key.x * 64.0, at.y - c.key.y * 64.0) + height
		p.global_position.y = y
	# The eye never stands inside a tree's crown (the river shot was one big leaf).
	_clear_trees(streamer, Vector3(at.x, y, at.y), 4.5)
	_shoo_creatures(Vector3(at.x, y, at.y), 45.0, true)
	var tgt_h := y
	var tc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(Vector3(look_at.x, 0, look_at.y)))
	if tc:
		tgt_h = ChunkGenerator.height_at(tc.data, look_at.x - tc.key.x * 64.0, look_at.y - tc.key.y * 64.0) + 3.0
	if not is_nan(look_y):
		tgt_h = look_y
	var d := Vector3(look_at.x - at.x, tgt_h - y, look_at.y - at.y)
	p.set_state({"pos": p.global_position, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.9, 0.5), "slot": 0})
	world.atmosphere._target_w = world.atmosphere.field.era_weights(at.x, at.y)
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	# The eye adapts in a few frames instead of seconds: after the night-sky shot the lake
	# came out white, still exposed for the dark.
	var ca := (world.atmosphere.get_child(0) as WorldEnvironment).camera_attributes as CameraAttributesPractical
	var speed := ca.auto_exposure_speed
	ca.auto_exposure_speed = 20.0
	await _wait(settle_frames)
	ca.auto_exposure_speed = speed
	# The clock ran on while things settled (a game hour per real minute).
	Game.day = day
	await _wait(3)
	_shoo_creatures(p.global_position, 45.0, true)
	if before.is_valid():
		await before.call()
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name, " at ", at, " weights ", world.atmosphere._w)

func _run() -> void:
	await _wait(5)
	_apply_hud_mode()
	world.atmosphere.vfog_boost = vfog
	for kv in env_sets:
		var env: Environment = world.atmosphere.env
		var v = str_to_var(kv[1])
		env.set(kv[0], v if v != null else kv[1])
		print("env ", kv[0], " = ", env.get(kv[0]))
	var g := ChunkGenerator.new(Game.seed)
	if g.deep_caves and (only.is_empty() or only.has("40") or only.has("41") or only.has("42")):
		# Caves are planned on the land rivers carve: plan with the world's own rivers flag.
		await _cave_shots(ChunkGenerator.new(Game.seed, Game.store.has_rivers()))
	if only.is_empty() or only.has("43") or only.has("44"):
		await _forest_shots(g)
	var med := _find_settlement(g, Eras.MEDIEVAL)
	var fan := _find_settlement(g, Eras.FANTASY)
	var sci := _find_settlement(g, Eras.SCIFI)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		# The biggest town nearby, seen from the road into it.
		var town := _find_settlement(g, Eras.MEDIEVAL, 2) if g.towns else {}
		var ways: Array = g.road_angles(town) if not town.is_empty() else []
		if not ways.is_empty():
			var tc: Vector2 = town["center"]
			# High enough to see over the trees along the road and the wall beyond.
			await _shot("01_medieval_town", tc + Vector2.from_angle(ways[0]) * 100.0, tc, 0.40, 18.0, float(town["target_h"]) + 4.0)
		else:
			await _shot("01_medieval_town", c + Vector2(44, 30), c, 0.40)
	# Human worlds have no wildwood (the fantasy era is alien-only), so there's nothing to frame.
	var f := _find_era(g, Eras.FANTASY, 0.995)
	if f != Vector2.ZERO:
		await _shot("02_fantasy_wildwood", f, f + Vector2(60, 30), 0.36)
	if not sci.is_empty():
		var c: Vector2 = sci["center"]
		var big := _find_settlement(g, Eras.SCIFI, 1) if g.outposts else {}
		if not big.is_empty():
			var bc: Vector2 = big["center"]
			var a := g.outpost_angle(big) + 0.6
			await _shot("03_scifi_outpost", bc + Vector2.from_angle(a) * 62.0, bc, 0.55, 14.0)
		else:
			await _shot("03_scifi_outpost", c + Vector2(-42, 38), c, 0.55, 2.5)
	if g.outposts and (only.is_empty() or only.has("37")):
		# The nearest stronghold, from outside its gate.
		var best := {}
		for r in 8:
			for cz in range(-r, r + 1):
				for cx in range(-r, r + 1):
					if best.is_empty() and maxi(absi(cx), absi(cz)) == r:
						best = Stronghold.at_cell(g, cx, cz)
		if not best.is_empty():
			var fc: Vector2 = best["center"]
			var out := Vector2(0, 46).rotated(-float(best["yaw"]))
			await _shot("37_stronghold", fc + out + out.orthogonal() * 0.5, fc, 0.45, 9.0)
	if g.outposts and (only.is_empty() or only.has("16")):
		# The nearest tall viaduct (deck well above the valley under it), from the side.
		var best_d := INF
		var vm := Vector2.ZERO
		var vd := Vector2.ZERO
		var deck := 0.0
		for need in [8.0, 3.0]:
			for rd in g.roads_near(-1500.0, -1500.0, 1500.0, 1500.0):
				var pts: PackedVector2Array = rd["pts"]
				var ar: PackedByteArray = rd["air"]
				var lv: PackedFloat32Array = rd["level"]
				for i in range(2, pts.size() - 2):
					if ar[i] == 1 and ar[i - 1] == 1 and ar[i + 1] == 1 and pts[i].length() < best_d \
							and lv[i] - g.field.height(pts[i].x, pts[i].y) > need:
						best_d = pts[i].length()
						vm = pts[i]
						vd = (pts[i + 1] - pts[i - 1]).normalized()
						deck = lv[i]
			if best_d < INF:
				break
		if best_d < INF:
			# Stand level with the deck, off to one side, where no hill hides the arches:
			# the first spot whose sight line to the middle of the span clears the ground.
			var cam := vm + vd.orthogonal() * 48.0
			var found := false
			for dist in [45.0, 60.0, 75.0, 90.0]:
				for side in [-1.0, 1.0]:
					var c: Vector2 = vm + vd.orthogonal() * dist * side + vd * 14.0
					var eye := maxf(deck + 2.0, g.field.height(c.x, c.y) + 2.0)
					var clear := true
					for k in range(1, 10):
						var fr := k / 10.0
						var q := c.lerp(vm, fr)
						if g.field.height(q.x, q.y) > lerpf(eye, deck - 4.0, fr) - 0.5:
							clear = false
							break
					if clear and not found:
						cam = c
						found = true
			# The field's heights miss rock spires and cliffs (the shot once faced a rock
			# wall): check the sight line against what is really there.
			var cands: Array = [cam] if found else []
			for dist in [45.0, 60.0, 75.0, 90.0, 110.0]:
				for side in [-1.0, 1.0]:
					for along in [14.0, -14.0, 30.0]:
						cands.append(vm + vd.orthogonal() * dist * side + vd * along)
			var seen := await _clear_view(cands, Vector3(vm.x, deck - 4.0, vm.y), 2.0, 12.0, deck + 2.0)
			if seen != Vector2.INF:
				cam = seen
			var low := g.field.height(cam.x, cam.y)
			await _shot("16_viaduct", cam, vm, 0.4, maxf(deck - low + 2.0, 2.0), deck - 4.0)
	if g.outposts and (only.is_empty() or only.has("27") or only.has("28") or only.has("29") or only.has("33") or only.has("34")):
		await _room_shots(g)
	if only.is_empty() or only.has("30") or only.has("31") or only.has("32"):
		await _wonder_shots()
	if only.is_empty() or only.has("45") or only.has("46") or only.has("47") or only.has("48"):
		await _wonder_types()
	if g.landforms:
		await _landform_shots(g)
	if only.is_empty() or only.has("50") or only.has("51") or only.has("52"):
		await _ground_shots(g)
	var b := _find_border(g)
	await _shot("04_era_border", b + Vector2(-25, -25), b + Vector2(40, 40), 0.45, 6.0)
	if not fan.is_empty():
		var c: Vector2 = fan["center"]
		await _shot("05_fantasy_village_night", c + Vector2(40, -34), c, 0.93)
	elif not med.is_empty():
		# Human worlds have no fantasy villages: a medieval one by night, its windows and
		# hearths the only light.
		var c: Vector2 = med["center"]
		await _shot("05_village_night", c + Vector2(40, -34), c, 0.93)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		# Half turned toward the low sun (west-south-west at this hour), so the light rakes
		# across the houses and their shadows reach toward you.
		await _shot("06_medieval_sunset", c + Vector2(24, -50), c, 0.735)
	# Midnight, looking as far up as a player can: the stars and the Milky Way.
	await _shot("39_night_sky", Vector2(8, 8), Vector2(208, 108), 0.0, 1.7, 400.0)
	var shore := _find_shore(g)
	if shore != Vector2.ZERO:
		await _shot("07_lake_day", shore, shore + shore_out * 60.0, 0.42, 2.5)
	var rv := _find_river(ChunkGenerator.new(Game.seed, Game.store.has_rivers()))
	if rv != Vector4.ZERO:
		await _shot("08_river", Vector2(rv.x, rv.y), Vector2(rv.z, rv.w), 0.4, 7.0)
	if shore != Vector2.ZERO and (only.is_empty() or only.has("35") or only.has("36")):
		await _water_shots(g, shore)
	if only.is_empty() or only.has("09") or only.has("10"):
		await _vehicles()
	if only.is_empty() or only.has("11") or only.has("12"):
		await _starship()
	if only.is_empty() or only.has("13") or only.has("14") or only.has("15"):
		await _space()
		return
	Game.close_world()
	get_tree().quit()

## Grass and ground cover up close: a medieval meadow at eye level, the foot of a cliff
## (scree and the cliff face, from far enough back to see both) and the scree underfoot.
func _ground_shots(g: ChunkGenerator) -> void:
	var meadow := Vector2.ZERO
	var cliff := Vector4.ZERO
	for i in 12000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (50.0 + i * 3.0)
		if g.field.era_weights(p.x, p.y)[Eras.MEDIEVAL] < 0.9:
			continue
		var h := g.field.height(p.x, p.y)
		if h < 3.0:
			continue
		var flat := true
		for k in 8:
			var d := Vector2.from_angle(k * TAU / 8.0)
			flat = flat and absf(g.field.height(p.x + d.x * 6.0, p.y + d.y * 6.0) - h) < 0.9
		if not flat:
			continue
		if meadow == Vector2.ZERO:
			var open := true
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				open = open and absf(g.field.height(p.x + d.x * 30.0, p.y + d.y * 30.0) - h) < 4.0
			if open:
				meadow = p
		if cliff == Vector4.ZERO:
			# A wall, not a lone pillar: the ground rises steeply ahead across a broad
			# front, and stays level behind for the camera.
			for k in 16:
				var d := Vector2.from_angle(k * TAU / 16.0)
				var side := d.orthogonal()
				var wall := true
				for o: float in [-12.0, 0.0, 12.0]:
					var q: Vector2 = p + side * o
					wall = wall and g.field.height(q.x + d.x * 20.0, q.y + d.y * 20.0) - h > 8.0
					wall = wall and absf(g.field.height(q.x + d.x * 4.0, q.y + d.y * 4.0) - h) < 1.2
				var back := p - d * 18.0
				wall = wall and absf(g.field.height(back.x, back.y) - h) < 2.0
				# On dry ground: no lake or river where the camera stands or looks.
				if wall:
					for t in 5:
						wall = wall and _dry(g, back.lerp(p + d * 3.0, t / 4.0))
				if wall:
					cliff = Vector4(p.x, p.y, d.x, d.y)
					break
		if meadow != Vector2.ZERO and cliff != Vector4.ZERO:
			break
	if meadow != Vector2.ZERO:
		await _shot("50_meadow", meadow, meadow + Vector2(40, 25), 0.4, 1.7)
	if cliff != Vector4.ZERO:
		var at := Vector2(cliff.x, cliff.y)
		var d := Vector2(cliff.z, cliff.w)
		var h := g.field.height(at.x, at.y)
		await _shot("51_cliff_scree", at - d * 18.0, at + d * 12.0, 0.4, 2.2, h + 5.0)
		# Standing at the cliff foot, looking down at the stones ahead.
		await _shot("52_ground", at, at + d * 3.0, 0.42, 1.7, h - 1.2)

var _dry_chunks := {}
var _dry_gen: ChunkGenerator

## Whether a point is on land, above the sea and out of any river or river-fed lake
## (those sit above sea level). Built with the world's own rivers flag, as the game is.
func _dry(_g: ChunkGenerator, p: Vector2) -> bool:
	if _dry_gen == null:
		_dry_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var key := Vector2i(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))
	if not _dry_chunks.has(key):
		_dry_chunks[key] = _dry_gen.generate(key.x, key.y)
	var c: Dictionary = _dry_chunks[key]
	var lx := p.x - key.x * 64.0
	var lz := p.y - key.y * 64.0
	var h := ChunkGenerator.height_at(c, lx, lz)
	var rs := ChunkGenerator.river_surface(c, lx, lz)
	return h > ChunkGenerator.WATER_LEVEL + 1.5 and not ChunkGenerator.by_river(c, lx, lz) and (is_nan(rs) or h > rs + 1.0)

## Inside walk-in rooms, from just within the door: an outpost block, the nearest
## stronghold's keep, and a mushroom house at night. Then up a stone tower's stairwell
## and out from its battlements over the courtyard.
func _room_shots(g: ChunkGenerator) -> void:
	var picks: Array = [] ## [name, type, centre, yaw, ground height, day]
	var sci := _find_settlement(g, Eras.SCIFI, 1)
	if not sci.is_empty():
		for it in g.settlement_layout(sci):
			if it["t"] in ["lab_block", "hab_block", "ops_tower"]:
				picks.append(["27_outpost_room", it["t"], it["p"], it["yaw"], float(sci["target_h"]), 0.45])
				break
	var fort := {}
	for r in 8:
		for cz in range(-r, r + 1):
			for cx in range(-r, r + 1):
				if fort.is_empty() and maxi(absi(cx), absi(cz)) == r:
					fort = Stronghold.at_cell(g, cx, cz)
	if not fort.is_empty():
		for it in Stronghold.layout(g, fort):
			if String(it["t"]).ends_with("_keep"):
				picks.append(["28_keep_hall", it["t"], it["p"], it["yaw"], float(fort["target_h"]), 0.45])
	var fan := _find_settlement(g, Eras.FANTASY)
	if not fan.is_empty():
		for it in g.settlement_layout(fan):
			if it["t"] == "mushroom_house":
				picks.append(["29_mushroom_night", it["t"], it["p"], it["yaw"], float(fan["target_h"]), 0.93])
				break
	for pk in picks:
		var t: String = pk[1]
		var c: Vector2 = pk[2]
		var yaw: float = pk[3]
		var fl := 0.2
		var cam := Vector2.ZERO
		var look := Vector2.ZERO
		if Interiors.BOX.has(t):
			var b: Array = Interiors.BOX[t]
			fl = b[1]
			cam = Vector2(float(b[5][0]), (b[0] as Vector2).y - 0.5)
			look = Vector2(float(b[5][0]) * 0.3 - 1.0, -(b[0] as Vector2).y)
		elif Interiors.ROUND.has(t):
			var p: Array = Interiors.ROUND[t]
			fl = p[5]
			cam = Vector2(0, float(p[0]) - float(p[2]) - 0.45)
			look = Vector2(-0.3, -2.0)
		var to_w := func(l: Vector2) -> Vector2: return c + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))
		await _shot(pk[0], to_w.call(cam), to_w.call(look), pk[5], fl - 0.1, float(pk[4]) + fl + 0.7)
	if fort.is_empty() or int(fort["era"]) == 2:
		return
	for it in Stronghold.layout(g, fort):
		if String(it["t"]).ends_with("_tower"):
			var c: Vector2 = it["p"]
			var yaw: float = it["yaw"]
			var gh: float = fort["target_h"]
			var b: Array = Interiors.BOX[it["t"]]
			var to_w := func(l: Vector2) -> Vector2: return c + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))
			await _shot("33_tower_stair", to_w.call(Vector2(1.6, 2.2)), to_w.call(Vector2(-3.0, -3.0)), 0.45, float(b[1]) - 0.1, gh + 7.0)
			# Stand on the side of the roof toward the castle so the flag pole in the middle
			# is behind you, not across the view.
			var fc: Vector2 = fort["center"]
			var rel := fc - c
			var loc := Vector2(rel.x * cos(yaw) - rel.y * sin(yaw), rel.x * sin(yaw) + rel.y * cos(yaw)).normalized() * 2.6
			await _shot("34_tower_roof", to_w.call(loc), fc, 0.45, float(b[4]) - 0.1, gh + 2.0)
			break

## v7 landforms, each from the heart of the nearest region that has it: towers and
## needles from the valley floor, holes (craters, gorges, sinkholes) from the rim.
const LANDFORM_SHOTS := {
	"17_karst": WorldField.LF_KARST, "18_needles": WorldField.LF_NEEDLES, "19_dunes": WorldField.LF_DUNES,
	"20_craters": WorldField.LF_CRATERS, "21_gorge": WorldField.LF_GORGE, "22_badlands": WorldField.LF_BADLANDS,
	"23_crags": WorldField.LF_CRAGS, "24_sinkholes": WorldField.LF_SINKHOLES, "25_lakes": WorldField.LF_LAKES,
	"26_terraces": WorldField.LF_TERRACES,
}

func _landform_shots(g: ChunkGenerator) -> void:
	for shot in LANDFORM_SHOTS:
		if not only.is_empty() and not only.has(String(shot).substr(0, 2)):
			continue
		var lf: int = LANDFORM_SHOTS[shot]
		var best := Vector2.INF
		for r in 14:
			for iz in range(-r, r + 1):
				for ix in range(-r, r + 1):
					if best != Vector2.INF or maxi(absi(ix), absi(iz)) != r:
						continue
					var p := g.field.site_pos(ix, iz)
					if g.field.site_landform(ix, iz) == lf and g.field.landform_weights(p.x, p.y)[lf] > 0.95:
						best = p
		if best == Vector2.INF:
			print("no region with landform ", lf)
			continue
		var looking_down := lf in [WorldField.LF_CRATERS, WorldField.LF_GORGE, WorldField.LF_SINKHOLES, WorldField.LF_LAKES, WorldField.LF_TERRACES]
		var cam := best
		var pick := INF if not looking_down else -INF
		for k in 12:
			var c := best + Vector2.from_angle(k * TAU / 12.0) * 70.0
			var h := g.field.height(c.x, c.y)
			if h < WATER_SAFE:
				continue
			if (h < pick) != looking_down:
				pick = h
				cam = c
		var tgt := g.field.height(best.x, best.y)
		await _shot(shot, cam, best, 0.42, 9.0 if looking_down else 2.5, tgt + (2.0 if looking_down else 14.0))

const WATER_SAFE := 1.0

## The nearest wonder by day and by night, then the atlas and minimap around it.
func _wonder_shots() -> void:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var ch := {}
	for r in 6:
		for wz in range(-r, r + 1):
			for wx in range(-r, r + 1):
				if not ch.is_empty() or maxi(absi(wx), absi(wz)) != r:
					continue
				var pick := WonderSite.cell_pick(g.seed, wx, wz)
				if pick.is_empty():
					continue
				var k: Vector2i = pick[0]
				var c := g.generate(k.x, k.y)
				if c.has("wonder"):
					ch = c
	if ch.is_empty():
		print("no wonder near the origin")
		return
	var w: Dictionary = ch["wonder"]
	var wc := Vector2(ch["cx"] * 64.0 + float(w["lx"]), ch["cz"] * 64.0 + float(w["lz"]))
	var yaw := 0.0
	for o in ch["objects"]:
		if o["t"] == w["t"]:
			yaw = o["r"]
	var front := Vector2(0, 1).rotated(-yaw)
	var cam := wc + front * 40.0 + front.orthogonal() * 14.0
	print("wonder ", w["t"], " at ", wc)
	await _shot("30_wonder", cam, wc, 0.42, 6.0, ChunkGenerator.height_at(ch, w["lx"], w["lz"]) + 8.0)
	await _shot("31_wonder_night", wc + front * 140.0, wc, 0.9, 12.0, ChunkGenerator.height_at(ch, w["lx"], w["lz"]) + 40.0)
	if only.is_empty() or only.has("32"):
		world.player.global_position = Vector3(wc.x + front.x * 60.0, world.player.global_position.y, wc.y + front.y * 60.0)
		await _wait(120)
		var mk := Game.markers.add("Dreadnought crash", wc.x + 30.0, wc.y + 20.0, Game.planet, "pin", {"icon": "danger", "color": 2})
		AtlasView.selected = int(mk["id"])
		world.menus.open("map")
		await _wait(30)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("32_atlas.png"))
		print("captured 32_atlas")
		world.menus.close()
		await _wait(5)

## The nearest wonder of each kind, close up by day: 45 throne, 46 worldroot,
## 47 dreadnought, 48 gate.
func _wonder_types() -> void:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var found := {}
	for r in 16:
		for wz in range(-r, r + 1):
			for wx in range(-r, r + 1):
				if found.size() == WonderSite.TYPES.size() or maxi(absi(wx), absi(wz)) != r:
					continue
				var pick := WonderSite.cell_pick(g.seed, wx, wz)
				if pick.is_empty():
					continue
				var k: Vector2i = pick[0]
				var c := g.generate(k.x, k.y)
				if c.has("wonder") and not found.has(c["wonder"]["t"]):
					found[c["wonder"]["t"]] = c
	for i in WonderSite.TYPES.size():
		var t: String = WonderSite.TYPES[i]
		if not found.has(t):
			print("no ", t, " found")
			continue
		var ch: Dictionary = found[t]
		var w: Dictionary = ch["wonder"]
		var wc := Vector2(ch["cx"] * 64.0 + float(w["lx"]), ch["cz"] * 64.0 + float(w["lz"]))
		var yaw := 0.0
		for o in ch["objects"]:
			if o["t"] == t:
				yaw = o["r"]
		var front := Vector2(0, 1).rotated(-yaw)
		var h := ChunkGenerator.height_at(ch, w["lx"], w["lz"])
		var name := "%d_%s" % [45 + i, t]
		if not only.is_empty() and not only.has(name.substr(0, 2)):
			continue
		print("wonder ", t, " at ", wc)
		var cam := await _wonder_view(wc, front, h + 6.0)
		var at := Vector3(wc.x, h, wc.y)
		_shoo_creatures(at, 70.0)
		await _shot(name, cam, wc, 0.4, 3.0, h + 6.0, func():
			_shoo_creatures(at, 70.0)
			await _wait(3))

## Where to stand to see a wonder whole: out in front at a slight angle, not inside its
## rocks or a hill (the throne shot stood in the stone king's knees), with nothing solid
## between the eye and the middle of the wonder. Tries wider and further spots in turn.
func _wonder_view(wc: Vector2, front: Vector2, look_y: float) -> Vector2:
	var cands: Array = []
	for d in [30.0, 38.0, 46.0, 56.0]:
		for a in [0.3, -0.3, 0.6, -0.6, 0.0, 0.9, -0.9, 1.25, -1.25]:
			cands.append(wc + front.rotated(a) * d)
	var at := await _clear_view(cands, Vector3(wc.x, look_y, wc.y), 3.0, 14.0)
	return at if at != Vector2.INF else wc + front * 30.0

## The first of `cands` (ground-plan points) where an eye `eye_h` above the ground, or at
## least `min_y`, stands in open air under open sky and sees `target` (or something within
## `near` of it). Loads the ground around the target first. Vector2.INF if none does.
func _clear_view(cands: Array, target: Vector3, eye_h: float, near: float, min_y := -INF) -> Vector2:
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	p.set_physics_process(false)
	p.global_position = target + Vector3(0, 20, 0)
	await _wait_loaded(p, streamer)
	await _wait(5) # colliders of the new chunks
	var space := p.get_world_3d().direct_space_state
	for q in cands:
		var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(Vector3(q.x, 0, q.y)))
		if c == null:
			continue
		var gy := ChunkGenerator.height_at(c.data, q.x - c.key.x * 64.0, q.y - c.key.y * 64.0)
		var eye := Vector3(q.x, maxf(gy + eye_h, min_y), q.y)
		var ball := PhysicsShapeQueryParameters3D.new()
		ball.shape = SphereShape3D.new()
		(ball.shape as SphereShape3D).radius = 1.2
		ball.transform = Transform3D(Basis(), eye)
		ball.exclude = [p.get_rid()]
		if not space.intersect_shape(ball, 1).is_empty():
			continue
		# Open sky overhead: a sphere wholly inside a big rock touches none of its faces.
		var up := PhysicsRayQueryParameters3D.create(eye + Vector3(0, 60, 0), eye)
		up.exclude = [p.get_rid()]
		if not space.intersect_ray(up).is_empty():
			continue
		var ray := PhysicsRayQueryParameters3D.create(eye, target)
		ray.exclude = [p.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < near:
			print("clear view from ", q, " (", eye.distance_to(target), " m)")
			return q
	print("no clear view of ", target)
	return Vector2.INF

## Guards and the boss would run at the camera and fill the photo with their name tags:
## the photo is of the place, so they go (only the hostile ones, if asked).
func _shoo_creatures(at: Vector3, r: float, hostile_only := false) -> void:
	for k in world.fauna._herds:
		var herd: Array = world.fauna._herds[k]
		for cr in herd.duplicate():
			if not is_instance_valid(cr) or cr.global_position.distance_to(at) >= r:
				continue
			if hostile_only and String(cr.p.get("temper", "")) != "aggressive":
				continue
			herd.erase(cr)
			cr.queue_free()

## Trees standing within r (on the ground plan) of the eye, whose crowns would wrap it.
func _clear_trees(streamer: ChunkStreamer, eye: Vector3, r: float) -> void:
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if o["st"].get("gone", false) or ObjectLibrary.kind(o["t"]) != "tree":
				continue
			var w: Vector3 = c.position + o["p"]
			if Vector2(w.x - eye.x, w.z - eye.z).length() < r:
				c.remove_object(o["i"])

## A starship on its launch pad, then in flight over the land.
func _starship() -> void:
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	var vm: VehicleManager = world.vehicles
	if p.vehicle:
		p.dismount(true)
	var g0 := ChunkGenerator.new(Game.seed)
	var s2 := _find_era(g0, Eras.SCIFI, 0.9)
	var at := _flat_spot(vm, Vector3(s2.x, 0, s2.y))
	print("starship: pad at ", at)
	p.fly = true
	p.global_position = at + Vector3(0, 3, 0)
	await _wait_loaded(p, streamer)
	var pad := Vector3(at.x, vm.ground(at.x, at.z), at.z)
	_clear_around(streamer, pad, 26.0)
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(at))
	c.add_built("launch_pad", pad - c.position, 0.0, {"by": "you", "day": 0.0})
	var ship := vm.deploy(ItemDB.make("ship", 1, 1.0, {}), pad, 0.6)
	ship.global_position.y = pad.y + 0.6
	Game.day = 0.62
	var eye := pad + Vector3(12, 8, 14)
	var d := pad + Vector3(0, 1.5, 0) - eye
	p.set_state({"pos": eye, "yaw": atan2(-d.x, -d.z), "pitch": atan2(d.y, Vector2(d.x, d.z).length()), "slot": 0})
	await _wait(settle_frames)
	if only.is_empty() or only.has("11"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("11_starship.png"))
		print("captured 11_starship")
	p.fly = false
	p.mount(ship)
	if not p.third_person:
		p.toggle_view()
	p.set_state({"pos": p.global_position, "yaw": ship.rotation.y, "pitch": 0.25, "slot": 0, "view": 3})
	Input.action_press("jump")
	await _wait(60)
	Input.action_press("move_forward")
	await _wait(60)
	Input.action_release("jump")
	await _wait(40)
	Input.action_release("move_forward")
	# Hover while the land below streams in, then look down over the nose.
	await _wait_loaded(p, streamer)
	p.set_state({"pos": p.global_position, "yaw": ship.rotation.y, "pitch": -0.35, "slot": 0, "view": 3})
	Input.action_press("move_forward")
	await _wait(30)
	if only.is_empty() or only.has("12"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("12_flight.png"))
		print("captured 12_flight")
	Input.action_release("move_forward")

## Under the lake looking back up the shelf to the shore, and a splash just off the beach.
func _water_shots(g: ChunkGenerator, shore: Vector2) -> void:
	var out := shore_out
	var deep := Vector2.INF
	for k in 60:
		var q := shore + out * (k * 3.0)
		if g.field.height(q.x, q.y) < Water.LEVEL - 9.0:
			deep = q
			break
	# (Only where the lake is deep enough to stand under: anywhere else this would be dry
	# land seen through the underwater look.)
	if deep != Vector2.INF:
		var p: Player = world.player
		p.underwater = true
		await _shot("35_underwater", deep, shore, 0.45, 4.0, Water.LEVEL + 1.0)
		p.underwater = false
	var spot := shore + out * 9.0
	var burst := func() -> void:
		for i in 3:
			Splashes.splash(Vector3(spot.x, Water.surface_height(spot.x, spot.y, 0.0), spot.y), 1.2)
			Splashes.ring(Vector3(spot.x + 2.0, 0.0, spot.y + 1.0), 1.6)
			await _wait(4)
	await _shot("36_splash", shore - out * 2.0, spot, 0.42, 2.2, Water.LEVEL + 0.6, burst)

## Clears trees, rocks and ruins near `at` so a staged shot has a clear view.
func _clear_around(streamer: ChunkStreamer, at: Vector3, r: float) -> void:
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if not o["st"].get("gone", false) and (c.position + o["p"]).distance_to(at) < r:
				c.remove_object(o["i"])

func _snap(name: String) -> void:
	if only.is_empty() or only.has(name.substr(0, 2)):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
		print("captured ", name)

## Up to orbit, warp to the fey moon, and land there.
func _space() -> void:
	var p: Player = world.player
	var vm: VehicleManager = world.vehicles
	if p.vehicle:
		p.dismount(true)
	p.set_physics_process(true)
	p.fly = false
	var ship := vm.deploy(ItemDB.make("ship", 1, 1.0, {}), p.global_position + Vector3(0, 0, -10), p.yaw())
	await _wait(10)
	p.mount(ship)
	ship.leaving = Vehicle.LEAVE_TIME
	ship.at_ceiling = true
	# The world (and this node's parent) goes away; keep the tour running from the root.
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	for i in 600:
		await tree.process_frame
		if tree.current_scene is OrbitView:
			break
	var orbit: OrbitView = tree.current_scene
	await _wait(settle_frames)
	await _snap("13_orbit")
	var fey := 1
	for pl in Game.worlds():
		if pl["kind"] == "fey":
			fey = pl["n"]
	# Slow time so the streaks are mid-flight when the (slow) software renderer shoots.
	Engine.time_scale = 0.05
	orbit._warp(fey)
	for i in 400:
		await tree.process_frame
		if float(orbit._warp_mat.get_shader_parameter("amount")) > 0.75:
			break
	await _snap("14_warp")
	Engine.time_scale = 1.0
	while orbit._busy:
		await tree.process_frame
	await _wait(30)
	orbit._land()
	for i in 600:
		await tree.process_frame
		if tree.current_scene != orbit and tree.current_scene != null and tree.current_scene.get("player") != null:
			break
	world = tree.current_scene
	p = world.player
	for i in 3000:
		await tree.process_frame
		if p.vehicle != null:
			break
	if not p.third_person:
		p.toggle_view()
	Input.action_press("crouch")
	await _wait(150)
	Input.action_release("crouch")
	p.dismount(true)
	# Look away from the parked ship, over the alien landscape.
	p.set_state({"pos": p.global_position + Vector3(0, 0, 6), "yaw": p.yaw() + 2.4, "pitch": -0.15, "slot": 0, "view": 3, "riding": -1})
	await _wait_loaded(p, world.streamer)
	Game.day = 0.42
	await _wait(settle_frames)
	await _snap("15_fey_moon")
	Game.close_world()
	get_tree().quit()

## The flattest dry 24 m square near `from` (for setting things out to photograph).
func _flat_spot(vm: VehicleManager, from: Vector3) -> Vector3:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var best := from
	var best_s := INF
	for i in 400:
		var a := i * 0.61
		var q := Vector2(from.x, from.z) + Vector2(cos(a), sin(a)) * (i * 0.8)
		var lo := INF
		var hi := -INF
		var wet := false
		for dz in [-12.0, 0.0, 12.0]:
			for dx in [-12.0, 0.0, 12.0]:
				var h := g.field.height(q.x + dx, q.y + dz)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				if h < Water.LEVEL + 1.0 or g.field.river_t(q.x + dx, q.y + dz) < 3.0:
					wet = true
		if not wet and hi - lo < best_s:
			best_s = hi - lo
			best = Vector3(q.x, g.field.height(q.x, q.y) + 1.0, q.y)
	return best

## The vehicle bay and stable with a speeder, a rover and a horse in front, then riding.
func _vehicles() -> void:
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	var g0 := ChunkGenerator.new(Game.seed)
	var m2 := _find_era(g0, Eras.MEDIEVAL, 0.95)
	var at := Vector3(m2.x, 0, m2.y)
	p.set_physics_process(false)
	p.global_position = at
	await _wait_loaded(p, streamer)
	var vm: VehicleManager = world.vehicles
	at = _flat_spot(vm, at)
	print("vehicles: showcase at ", at)
	p.global_position = at
	await _wait_loaded(p, streamer)
	print("vehicles: ground loaded")
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(at))
	var g := func(x: float, z: float) -> Vector3:
		return Vector3(x, vm.ground(x, z), z)
	var bay: Vector3 = g.call(at.x - 6, at.z - 10)
	c.add_built("vehicle_bay", bay - c.position, 0.0, {"by": "you", "day": 0.0})
	var st: Vector3 = g.call(at.x + 6, at.z - 10)
	c.add_built("stable", st - c.position, 0.0, {"by": "you", "day": 0.0})
	vm.deploy(ItemDB.make("speeder", 1, 1.0, {}), at + Vector3(-7.5, 0, -5), 0.5)
	vm.deploy(ItemDB.make("rover", 1, 1.0, {}), at + Vector3(-2, 0, -5), 0.2)
	vm.deploy(ItemDB.make("horse", 1, 1.0, {}), at + Vector3(5, 0, -5), -0.4)
	Game.day = 0.4
	p.set_physics_process(true)
	p.set_state({"pos": at + Vector3(0, 0.2, 7), "yaw": 0.0, "pitch": -0.22, "slot": 0})
	p.fly = true # hold the camera a little above the ground
	p.global_position.y += 2.5
	await _wait(settle_frames)
	if only.is_empty() or only.has("09"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("09_vehicles.png"))
		print("captured 09_vehicles")
	var sp: Vehicle = vm.all_nodes()[0]
	for v in vm.all_nodes():
		if v.kind == "speeder":
			sp = v
	p.fly = false
	p.mount(sp)
	if not p.third_person:
		p.toggle_view()
	Input.action_press("move_forward")
	await _wait(150)
	if only.is_empty() or only.has("10"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("10_riding.png"))
		print("captured 10_riding")
	Input.action_release("move_forward")

## The nearest cave network: its mouth from down the hill, the entry passage by torch,
## and its biggest chamber.
func _cave_shots(g: ChunkGenerator) -> void:
	var net := {}
	for r in 8:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if net.is_empty() and maxi(absi(sx), absi(sz)) == r:
					net = Caves.network(g, sx, sz)
	if net.is_empty():
		print("no cave network found")
		return
	var mo: Vector3 = net["mouth"]
	var up: Vector2 = net["dir"]
	var m2 := Vector2(mo.x, mo.z)
	print("cave mouth at ", mo)
	await _shot("40_cave_mouth", m2 - up * 13.0 + up.orthogonal() * 3.0, m2 + up * 3.0, 0.42, 1.8, mo.y + 1.0)
	var ps := Caves.prims_near(g, mo.x - 200.0, mo.z - 200.0, mo.x + 200.0, mo.z + 200.0)
	var e := m2 + up * 9.0
	var ey := _cave_floor(ps, e, mo.y + 3.0)
	if not is_nan(ey):
		var deep := m2 + up * 30.0
		await _abs_shot("41_cave_entry", Vector3(e.x, ey + 1.7, e.y), Vector3(deep.x, ey - 3.0, deep.y), 0.42, true)
	var best := {}
	for ch in net["chambers"]:
		if best.is_empty() or float(ch["rx"]) > float(best["rx"]):
			best = ch
	var cc: Vector3 = best["p"]
	var at := Vector2(cc.x, cc.z) - up * float(best["rx"]) * 0.55
	var ay := _cave_floor(ps, at, cc.y)
	if is_nan(ay):
		at = Vector2(cc.x, cc.z)
		ay = _cave_floor(ps, at, cc.y)
	if not is_nan(ay):
		await _abs_shot("42_cave_chamber", Vector3(at.x, ay + 1.7, at.y), Vector3(cc.x, cc.y - 1.0, cc.z) + Vector3(up.x, 0, up.y) * 6.0, 0.42, true)

func _cave_floor(ps: PackedFloat32Array, p: Vector2, top: float) -> float:
	var y := top
	while y > top - 20.0:
		if Caves.sdf(ps, Vector3(p.x, y, p.y)) < -0.6:
			return Caves.floor_below(ps, Vector3(p.x, y, p.y), 20.0)
		y -= 0.25
	return NAN

func _abs_shot(name: String, at: Vector3, look: Vector3, day: float, torch: bool) -> void:
	if not only.is_empty() and not only.has(name.substr(0, 2)):
		return
	var p: Player = world.player
	Game.day = day
	p.set_physics_process(false)
	p.global_position = at
	await _wait_loaded(p, world.streamer)
	var d := look - at
	p.set_state({"pos": at, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5), "slot": 9})
	if torch:
		p.hand_light.from_data({"kind": "torch", "torch_left": 300.0})
	world.atmosphere._target_w = world.atmosphere.field.era_weights(at.x, at.z)
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	await _wait(settle_frames)
	world.atmosphere.underground = world.atmosphere._under_target
	await _wait(20)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name, " at ", at, " underground ", world.atmosphere.underground)
	if torch:
		p.hand_light.from_data({"kind": "", "torch_left": 0.0})

## The densest woodland near spawn: a close look under the trees (44) and an overlook from
## a rise like the one players stand on (43), each followed by a draw-call breakdown so
## foliage batching can be compared before and after.
func _forest_shots(g: ChunkGenerator) -> void:
	var sp3 := Planets.spawn_point(Game.seed, Game.store.has_rivers())
	# Coarse pass every third chunk out to ~1 km (any seed has woods somewhere in that), then
	# the chunks around the best one.
	var c0 := Vector2i(int(floor(sp3.x / 64.0)), int(floor(sp3.z / 64.0)))
	var counts := {}
	var count := func(k: Vector2i) -> int:
		if not counts.has(k):
			var n := 0
			for o in g.generate(k.x, k.y)["objects"]:
				if ObjectLibrary.kind(o["t"]) == "tree":
					n += 1
			counts[k] = n
		return counts[k]
	var top := c0
	for dz in range(-15, 16, 3):
		for dx in range(-15, 16, 3):
			if count.call(c0 + Vector2i(dx, dz)) > count.call(top):
				top = c0 + Vector2i(dx, dz)
	var around := top
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if count.call(around + Vector2i(dx, dz)) > count.call(top):
				top = around + Vector2i(dx, dz)
	var best := Vector2(top.x * 64.0 + 32.0, top.y * 64.0 + 32.0)
	var most: int = count.call(top)
	print("forest chunk ", best, " trees ", most)
	# Stand in a clearing among the trees: the spot in the chunk with the most trees 6-25 m
	# away and none (trunk or crown) within 4 m, looking toward the thickest of them.
	var trees: Array = []
	for o in g.generate(top.x, top.y)["objects"]:
		if ObjectLibrary.kind(o["t"]) == "tree":
			trees.append(Vector2(o["p"].x, o["p"].z) + Vector2(top.x * 64.0, top.y * 64.0))
	var stand := best + Vector2(-14, -10)
	var look := best + Vector2(20, 18)
	var score := -1.0
	for j in range(4, 61, 3):
		for i in range(4, 61, 3):
			var q := Vector2(top.x * 64.0 + i, top.y * 64.0 + j)
			var near := INF
			var pull := Vector2.ZERO
			var n := 0
			for tp in trees:
				var d: float = q.distance_to(tp)
				near = minf(near, d)
				if d > 6.0 and d < 25.0:
					n += 1
					pull += (tp - q) / d
			if near >= 4.0 and n > score and pull.length() > 0.01:
				score = n
				stand = q
				look = q + pull.normalized() * 20.0
	await _shot("44_forest_close", stand, look, 0.4, 1.7, NAN, _draw_stats)
	await _shot("43_forest_overlook", best + Vector2(-90, -70), best, 0.4, 28.0, NAN, _draw_stats)

func _draw_stats() -> void:
	var count := func() -> float:
		var tot := 0.0
		for i in 20:
			await get_tree().process_frame
			tot += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		return tot / 20.0
	var base: float = await count.call()
	var hidden: Array = []
	for c in world.streamer.chunks.values():
		for ch in c.get_children():
			if ch is GeometryInstance3D and ch.visible and (String(ch.name).begins_with("MM_oak") or String(ch.name).begins_with("MM_pine") \
					or String(ch.name).begins_with("Trees") or (ch.has_meta("key") and String(ch.get_meta("key")).begins_with("under"))):
				ch.visible = false
				hidden.append(ch)
	var without: float = await count.call()
	for ch in hidden:
		ch.visible = true
	# Let the restored trees draw again before the shot is saved (the frame grabbed right
	# after this returns was still rendered without them).
	for i in 8:
		await get_tree().process_frame
	print("DRAWS total %d  trees+bushes %d  (%d nodes)" % [int(base), int(base - without), hidden.size()])
	var here: ChunkNode = world.streamer.get_chunk(ChunkStreamer.chunk_of(world.player.global_position))
	if here:
		var trees := 0
		for o in here.data["objects"]:
			if ObjectLibrary.kind(o["t"]) == "tree" and not o["st"].get("gone", false):
				trees += 1
		var mms := []
		for ch in here.get_children():
			if ch is MultiMeshInstance3D:
				mms.append("%s x%d vis_end %.0f" % [ch.name, (ch as MultiMeshInstance3D).multimesh.instance_count, ch.visibility_range_end])
		print("chunk ", here.key, " standing trees ", trees, " pos ", world.player.global_position, " ", mms)
