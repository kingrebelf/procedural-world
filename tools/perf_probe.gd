extends "res://tools/capture.gd"
## Performance probe: where the frame time goes, in one run.
##   godot --path . res://src/world/world.tscn -- --capture --perf [--seed=N] [--set=key=value ...] [--spots=town,forest] [--quick]
## (--capture is what makes the world load this tour; --perf swaps the screenshots for this.)
## At a few fixed views (seed 4242 unless given) it measures the frame, GPU and CPU times
## and the scene's size, what each graphics feature costs on the GPU, what each game system
## costs on the CPU, then flies across the land and lists the frame hitches. Prints a
## report and writes it to user://perf_probe.txt. Run with vsync off for real frame times.

const SETTLE := 45
const SAMPLE := 90

var spots: PackedStringArray = []
var quick := false ## --quick: skip the per-feature GPU tests
## --compare=name:key=value+key=value/name2:... measures whole groups of settings at each
## view instead of the per-system and per-feature tests (e.g. render scale options).
var compare: Array = []
var report: PackedStringArray = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spots="):
			spots = a.substr(8).split(",")
		if a == "--quick":
			quick = true
		if a.begins_with("--compare="):
			for opt in a.substr(10).split("/"):
				var sets := {}
				for kv in opt.get_slice(":", 1).split("+"):
					if kv.count("=") == 1:
						var v = str_to_var(kv.get_slice("=", 1))
						sets[kv.get_slice("=", 0)] = v if v != null else kv.get_slice("=", 1)
				compare.append([opt.get_slice(":", 0), sets])
	super._ready()

func _out(s: String) -> void:
	print(s)
	report.append(s)

func _run() -> void:
	await _wait(5)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var size := get_viewport().get_visible_rect().size
	_out("Perf probe  %s  %dx%d  render %.0f%%  preset %s  vsync %s  seed %d" % [ProjectSettings.get_setting("application/config/version", ""),
		int(size.x), int(size.y), float(Settings.values["render_scale"]) * 100.0, Settings.values["preset"],
		str(Settings.values["vsync"]), Game.seed])
	_out("GPU: %s   CPU threads: %d" % [RenderingServer.get_video_adapter_name(), OS.get_processor_count()])
	var g := ChunkGenerator.new(Game.seed)
	var sp := Planets.spawn_point(Game.seed, Game.store.has_rivers())
	var views := []
	views.append(["spawn", Vector2(sp.x, sp.z), Vector2(sp.x + 60, sp.z + 40), 1.7])
	var town := _find_settlement(g, Eras.MEDIEVAL, 2) if g.towns else {}
	if town.is_empty():
		town = _find_settlement(g, Eras.MEDIEVAL)
	if not town.is_empty():
		var tc: Vector2 = town["center"]
		var ways: Array = g.road_angles(town) if g.towns else []
		var a: float = ways[0] if not ways.is_empty() else 0.6
		views.append(["town_overview", tc + Vector2.from_angle(a) * 100.0, tc, 18.0])
		views.append(["town_street", tc + Vector2.from_angle(a) * 12.0, tc - Vector2.from_angle(a) * 30.0, 1.7])
	var shore := _find_shore(g)
	if shore != Vector2.ZERO:
		views.append(["lake", shore, shore + shore_out * 60.0, 2.5])
	var forest := _forest_spot(g)
	if forest.size() == 2:
		views.append(["forest", forest[0], forest[1], 1.7])
	for v in views:
		if not spots.is_empty() and not spots.has(String(v[0]).get_slice("_", 0)) and not spots.has(v[0]):
			continue
		await _probe_view(v[0], v[1], v[2], v[3])
		if v[0] == "lake":
			await _splash_test(v[1])
	if spots.is_empty() or spots.has("fly"):
		var from: Vector2 = views[1][1] if views.size() > 1 else views[0][1]
		await _fly("fly_run", from, Vector2(1, 0.3).normalized(), 9.0, 12.0)
		await _fly("fly_horse", from + Vector2(0, 300), Vector2(-0.4, 1).normalized(), 22.0, 12.0)
		await _fly("fly_jet", from + Vector2(300, 0), Vector2(0.2, -1).normalized(), 60.0, 12.0)
	var f := FileAccess.open("user://perf_probe.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(report))
	print("perf probe written to ", ProjectSettings.globalize_path("user://perf_probe.txt"))
	get_tree().quit()

func _forest_spot(g: ChunkGenerator) -> Array:
	var sp3 := Planets.spawn_point(Game.seed, Game.store.has_rivers())
	var c0 := Vector2i(int(floor(sp3.x / 64.0)), int(floor(sp3.z / 64.0)))
	var top := c0
	var most := -1
	for dz in range(-12, 13, 3):
		for dx in range(-12, 13, 3):
			var n := 0
			for o in g.generate(c0.x + dx, c0.y + dz)["objects"]:
				if ObjectLibrary.kind(o["t"]) == "tree":
					n += 1
			if n > most:
				most = n
				top = c0 + Vector2i(dx, dz)
	if most <= 0:
		return []
	var mid := Vector2(top.x * 64.0 + 32.0, top.y * 64.0 + 32.0)
	return [mid + Vector2(-20, -14), mid + Vector2(30, 20)]

## Stands at `at` looking at `look`, waits for the ground to load and the view to settle.
func _goto(at: Vector2, look: Vector2, height: float) -> void:
	var p: Player = world.player
	Game.day = 0.4
	var g := ChunkGenerator.new(Game.seed)
	var y := g.field.height(at.x, at.y) + height
	p.set_physics_process(false)
	p.global_position = Vector3(at.x, y, at.y)
	await _wait_loaded(p, world.streamer)
	var c: ChunkNode = world.streamer.get_chunk(ChunkStreamer.chunk_of(p.global_position))
	if c:
		y = ChunkGenerator.height_at(c.data, at.x - c.key.x * 64.0, at.y - c.key.y * 64.0) + height
		p.global_position.y = y
	var ty := g.field.height(look.x, look.y) + 2.0
	var d := Vector3(look.x - at.x, ty - y, look.y - at.y)
	p.set_state({"pos": p.global_position, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.9, 0.65), "slot": 0})
	world.atmosphere._target_w = Eras.look(world.atmosphere.field.era_weights(at.x, at.y))
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	for i in 120:
		await get_tree().process_frame
		if i % 10 == 0:
			_shoo_creatures(p.global_position, 45.0, true)
	Game.day = 0.4

func _measure() -> Dictionary:
	for i in SETTLE:
		await get_tree().process_frame
	var vp := get_viewport().get_viewport_rid()
	var m := {"gpu": 0.0, "cpu": 0.0, "proc": 0.0, "phys": 0.0, "draws": 0.0, "prims": 0.0, "objs": 0.0, "worst": 0.0}
	var t0 := Time.get_ticks_usec()
	var last := t0
	for i in SAMPLE:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		m["worst"] = maxf(m["worst"], (now - last) / 1000.0)
		last = now
		m["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		m["cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		m["proc"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		m["phys"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		m["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		m["prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		m["objs"] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	m["frame"] = (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE
	for k in ["gpu", "cpu", "proc", "phys", "draws", "prims", "objs"]:
		m[k] /= SAMPLE
	return m

func _fmt(m: Dictionary) -> String:
	return "frame %.1f ms (%d FPS, worst %.0f)  GPU %.1f  CPU render %.1f  script %.1f  physics %.1f  draws %d  objects %d  tris %.2fM" % [
		m["frame"], int(1000.0 / maxf(m["frame"], 0.1)), m["worst"], m["gpu"], m["cpu"], m["proc"], m["phys"], int(m["draws"]), int(m["objs"]), m["prims"] / 1e6]

## Counts what is in the scene round the player.
func _census() -> String:
	var lights := 0
	var shadow_lights := 0
	var particles := 0
	var mmis := 0
	var instances := 0
	var meshes := 0
	var bodies := 0
	var stack: Array = [world]
	var nodes := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		if n is OmniLight3D or n is SpotLight3D:
			if (n as Light3D).is_visible_in_tree():
				lights += 1
				if (n as Light3D).shadow_enabled:
					shadow_lights += 1
		elif n is GPUParticles3D or n is CPUParticles3D:
			if (n as Node3D).is_visible_in_tree():
				particles += 1
		elif n is MultiMeshInstance3D:
			mmis += 1
			if (n as MultiMeshInstance3D).multimesh:
				instances += (n as MultiMeshInstance3D).multimesh.instance_count
		elif n is MeshInstance3D:
			meshes += 1
		elif n is CollisionObject3D:
			bodies += 1
		stack.append_array(n.get_children())
	var near_lights := 0
	var cam := get_viewport().get_camera_3d()
	if cam:
		stack = [world]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is OmniLight3D and (n as OmniLight3D).shadow_enabled and (n as Node3D).is_visible_in_tree() \
					and (n as Node3D).global_position.distance_to(cam.global_position) < 55.0:
				near_lights += 1
			stack.append_array(n.get_children())
	return "scene: %d nodes, %d chunks, %d multimeshes (%d instances), %d meshes, %d bodies, %d lights (%d shadowed, %d of them within 55 m), %d particle systems" % [
		nodes, world.streamer.chunks.size(), mmis, instances, meshes, bodies, lights, shadow_lights, near_lights, particles]

func _probe_view(label: String, at: Vector2, look: Vector2, height: float) -> void:
	await _goto(at, look, height)
	var base: Dictionary = await _measure()
	_out("")
	_out("== %s at %s" % [label, at])
	_out("  " + _fmt(base))
	_out("  " + _census())
	if not compare.is_empty():
		var saved := Settings.values.duplicate()
		for c in compare:
			for k in c[1]:
				Settings.values[k] = c[1][k]
			Settings.apply()
			var m: Dictionary = await _measure()
			_out("  %-22s %s" % [c[0], _fmt(m)])
			Settings.values = saved.duplicate()
			Settings.apply()
		return
	# CPU: what each game system's scripts cost per frame (switched off one at a time).
	_out("  Script/physics cost by system (ms saved: frame / script / physics):")
	for n in ["People", "Wildlife", "Corpses", "Vehicles", "Water", "FarLand", "Chunks", "Treasure", "Player"]:
		var nd := world.get_node_or_null(n)
		if nd == null:
			continue
		var was := nd.process_mode
		nd.process_mode = Node.PROCESS_MODE_DISABLED
		var m: Dictionary = await _measure()
		nd.process_mode = was
		_out("    %-12s %5.2f  %5.2f  %5.2f" % [n, base["frame"] - m["frame"], base["proc"] - m["proc"], base["phys"] - m["phys"]])
	var ui := world.hud.get_parent() as CanvasLayer
	ui.process_mode = Node.PROCESS_MODE_DISABLED
	var mu: Dictionary = await _measure()
	ui.process_mode = Node.PROCESS_MODE_INHERIT
	_out("    %-12s %5.2f  %5.2f  %5.2f" % ["HUD and UI", base["frame"] - mu["frame"], base["proc"] - mu["proc"], base["phys"] - mu["phys"]])
	var atm: Node = world.atmosphere
	atm.process_mode = Node.PROCESS_MODE_DISABLED
	var ma: Dictionary = await _measure()
	atm.process_mode = Node.PROCESS_MODE_INHERIT
	_out("    %-12s %5.2f  %5.2f  %5.2f" % ["Atmosphere", base["frame"] - ma["frame"], base["proc"] - ma["proc"], base["phys"] - ma["phys"]])
	if quick:
		return
	# GPU: the benchmark's feature list, measured here.
	var b := Benchmark.new()
	b.world = world
	b._saved = Settings.values.duplicate()
	_out("  GPU cost by feature (GPU ms saved / frame ms saved / draws saved):")
	for t in b._tests():
		(t[1] as Callable).call(true)
		var m: Dictionary = await _measure()
		(t[1] as Callable).call(false)
		_out("    %-32s %5.1f  %5.1f  %6d" % [t[0], base["gpu"] - m["gpu"], base["frame"] - m["frame"], int(base["draws"] - m["draws"])])
	Settings.values = b._saved
	Settings.apply()
	b.free()

## Splashes in front of the eye (as capture shot 36): frame times through two bursts,
## the first one paying for any shader compiles.
func _splash_test(shore: Vector2) -> void:
	var spot := shore + shore_out * 9.0
	await _goto(shore - shore_out * 2.0, spot, 2.2)
	var vp := get_viewport().get_viewport_rid()
	for burst in 2:
		var worst := 0.0
		var gpu := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		var n := 0
		for i in 90:
			if i % 4 == 0 and i < 12:
				Splashes.splash(Vector3(spot.x, Water.surface_height(spot.x, spot.y, 0.0), spot.y), 1.2)
				Splashes.ring(Vector3(spot.x + 2.0, 0.0, spot.y + 1.0), 1.6)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			n += 1
		var fr := (Time.get_ticks_usec() - t0) / 1000.0 / n
		_out("== splash burst %d: frame %.1f ms (%d FPS)  GPU %.1f ms  worst frame %.0f ms" % [burst + 1, fr, int(1000.0 / maxf(fr, 0.1)), gpu / n, worst])
		await _wait(120)

## Moves the player in a straight line at `speed` m/s for `secs`, 1.7 m over the ground
## (well above it for the jetpack), and lists the frames that took far longer than usual.
func _fly(label: String, from: Vector2, dir: Vector2, speed: float, secs: float) -> void:
	var height := 25.0 if speed > 30.0 else 1.7
	await _goto(from, from + dir * 50.0, height)
	var p: Player = world.player
	var g := ChunkGenerator.new(Game.seed)
	var times: PackedFloat32Array = []
	var procs: PackedFloat32Array = []
	var hitches: PackedStringArray = []
	var pos := from
	var t0 := Time.get_ticks_usec()
	var last := t0
	var loads0: int = world.streamer.chunks.size()
	while (Time.get_ticks_usec() - t0) / 1e6 < secs:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		var ms := dt * 1000.0
		times.append(ms)
		var pr := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		procs.append(pr)
		if ms > 25.0 and times.size() > 2:
			hitches.append("%.0f ms (script %.0f, physics %.0f, %d jobs)" % [ms, pr, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, world.streamer._jobs.size()])
		pos += dir * speed * minf(dt, 0.1)
		p.global_position = Vector3(pos.x, g.field.height(pos.x, pos.y) + height, pos.y)
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= maxf(n, 1)
	var pavg := 0.0
	for x in procs:
		pavg += x
	pavg /= maxf(procs.size(), 1)
	_out("")
	_out("== %s: %.0f m/s for %.0f s, %d frames, %d chunks in view now (%d at start)" % [label, speed, secs, n, world.streamer.chunks.size(), loads0])
	_out("  frame avg %.1f  median %.1f  p95 %.1f  p99 %.1f  worst %.1f ms   script avg %.1f ms   frames over 25 ms: %d" % [
		avg, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], pavg, hitches.size()])
	for i in mini(hitches.size(), 12):
		_out("    " + hitches[i])
	p.set_physics_process(true)
