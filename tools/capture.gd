extends Node
## Automated screenshot tour used to check visuals without a human at the keyboard:
##   godot --path . res://src/world/world.tscn -- --capture [--out=DIR] [--seed=N]
## Finds a medieval town, a fantasy wildwood, a sci-fi outpost and an era border,
## frames each, waits for lighting to settle, and writes PNGs.

var world: Node3D
var out_dir := "user://captures"
var settle_frames := 150
var only: PackedStringArray = [] ## --shots=01,07 limits the tour to those shots

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--frames="):
			settle_frames = a.substr(9).to_int()
		if a.begins_with("--shots="):
			only = a.substr(8).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

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

func _find_settlement(g: ChunkGenerator, era: int) -> Dictionary:
	for r in 40:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if maxi(absi(sx), absi(sz)) != r:
					continue
				var s := g.settlement_at(sx, sz)
				if not s.is_empty() and s["era"] == era:
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

func _find_shore(g: ChunkGenerator) -> Vector2:
	for i in 6000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 5.0)
		if g.field.height(p.x, p.y) < Water.LEVEL - 4.0:
			# Walk back toward the origin until we reach dry land a little above the water.
			var dir := -p.normalized()
			for k in 80:
				var q := p + dir * (k * 3.0)
				if g.field.height(q.x, q.y) > Water.LEVEL + 0.6:
					return q
	return Vector2.ZERO

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

func _shot(name: String, at: Vector2, look_at: Vector2, day: float, height := 1.7) -> void:
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
	# Use the real (snapshotted, flattened) height once the chunk exists.
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(p.global_position))
	if c:
		y = ChunkGenerator.height_at(c.data, at.x - c.key.x * 64.0, at.y - c.key.y * 64.0) + height
		p.global_position.y = y
	var tgt_h := y
	var tc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(Vector3(look_at.x, 0, look_at.y)))
	if tc:
		tgt_h = ChunkGenerator.height_at(tc.data, look_at.x - tc.key.x * 64.0, look_at.y - tc.key.y * 64.0) + 3.0
	var d := Vector3(look_at.x - at.x, tgt_h - y, look_at.y - at.y)
	p.set_state({"pos": p.global_position, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5), "slot": 0})
	world.atmosphere._target_w = world.atmosphere.field.era_weights(at.x, at.y)
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	await _wait(settle_frames)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name, " at ", at, " weights ", world.atmosphere._w)

func _run() -> void:
	await _wait(5)
	var g := ChunkGenerator.new(Game.seed)
	var med := _find_settlement(g, Eras.MEDIEVAL)
	var fan := _find_settlement(g, Eras.FANTASY)
	var sci := _find_settlement(g, Eras.SCIFI)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		await _shot("01_medieval_town", c + Vector2(44, 30), c, 0.40)
	var f := _find_era(g, Eras.FANTASY, 0.995)
	await _shot("02_fantasy_wildwood", f, f + Vector2(60, 30), 0.36)
	if not sci.is_empty():
		var c: Vector2 = sci["center"]
		await _shot("03_scifi_outpost", c + Vector2(-42, 38), c, 0.55, 2.5)
	var b := _find_border(g)
	await _shot("04_era_border", b + Vector2(-25, -25), b + Vector2(40, 40), 0.45, 6.0)
	if not fan.is_empty():
		var c: Vector2 = fan["center"]
		await _shot("05_fantasy_village_night", c + Vector2(40, -34), c, 0.93)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		await _shot("06_medieval_sunset", c + Vector2(-50, 14), c, 0.735)
	var shore := _find_shore(g)
	if shore != Vector2.ZERO:
		await _shot("07_lake_day", shore, shore + shore.normalized() * 60.0, 0.42, 2.5)
	var rv := _find_river(ChunkGenerator.new(Game.seed, Game.store.has_rivers()))
	if rv != Vector4.ZERO:
		await _shot("08_river", Vector2(rv.x, rv.y), Vector2(rv.z, rv.w), 0.4, 7.0)
	Game.close_world()
	get_tree().quit()
