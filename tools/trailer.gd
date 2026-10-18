extends "res://tools/capture.gd"
## Trailer takes: moving-camera shots rendered offline at a fixed frame rate, every frame
## streamed into ffmpeg (or written as PNGs), for the game's trailer.
##   godot --path . --fixed-fps 60 --audio-driver Dummy res://src/world/world.tscn -- --capture --trailer [--fps=60]
##     --takes=rain_low,cog_orbit [--size=3840x2160] [--ffmpeg=PATH] [--png] [--cq=14] [--out=DIR]
##     [--len=1.0] [--seed=N] [--set=key=value ...]
## --fixed-fps is required: it steps the game clock (and the shaders' TIME) one frame at a
## time however slowly frames are drawn, so the water, the rain and every animation move
## exactly as they would at that frame rate (GameClock keeps the script clocks in step).
## The frames are drawn at --size whatever the window's size (the root viewport is
## stretched), so the window can stay small and out of the way.
## --len scales every take's length (0.3 for a quick path check). --takes=all renders them
## all. Each take writes TAKE.mp4 (HEVC 10-bit, NVENC), TAKE_proxy.mp4 (720p H.264, small
## enough to pass round for review), TAKE_mid.jpg and TAKE.json (what was found where).

const TAKES := ["rain_low", "rain_pov", "storm_town", "sunrise_peaks", "fly_rainforest", "fly_savanna", "fly_boreal",
	"fly_karst", "fly_needles", "waterfall_rise", "lake_glide", "cog_orbit", "cog_wake", "rowboat", "town_flyin",
	"market_dolly", "village_sunset", "village_night", "night_sky", "finale"]

var fps := 60
var size := Vector2i(3840, 2160)
var ffmpeg := "ffmpeg"
var frame_mode := "ffmpeg"
var cq := 14
var codec := "hevc_nvenc" ## --cpu: libx264 instead (no NVIDIA encoder), for checks on other machines
var len_scale := 1.0
var preroll := -1 ## --preroll=N overrides every take's unrecorded lead-in (for quick checks)
var takes: PackedStringArray = []
var gen: ChunkGenerator
var cam: Camera3D

## The take being recorded: its pose callable (t 0..1 -> [eye, look_at]), frame count, and
## the frame the late _process should pose next (-1: not recording).
var _pose: Callable
var _tick: Callable
var _frames := 1
var _rec_i := -1
var _day := Vector2(0.42, 0.42)
var _fov := 40.0
var _hold := {} ## global shader parameters held every frame (weather_puddle_g ...)
var _rain: HeroRain
const HeroRain := preload("res://tools/trailer_rain.gd")

func _ready() -> void:
	process_priority = 1000 # pose the camera after the boats and the weather have moved
	out_dir = "user://trailer"
	# Cinematic quality: Ultra and then some (drawn offline, so the cost doesn't matter).
	# --set=... on the command line still wins (parsed after these by capture.gd).
	var looks := {"window_mode": 0, "resolution": "1280x720", "vsync": 0, "fps_cap": 0, "render_scale": 1.0, "upscaler": 0,
			"aa": 3, "shadows": 3, "shadow_distance": 600.0, "gi": 2, "ssao": true, "ssr": true, "volumetric_fog": 2,
			"sun_shafts": true, "glow": true, "auto_exposure": true, "view_distance": 8, "grass_density": 1.5, "effects": 2,
			"clouds": 2, "detail_distance": 1.6, "mesh_detail": 3, "anisotropic": 4, "motion_blur": true,
			"motion_blur_strength": 0.5, "film_grade": true, "head_bob": false}
	for k in looks:
		Settings.set_value(k, looks[k], false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fps="):
			fps = a.substr(6).to_int()
		if a.begins_with("--takes="):
			takes = a.substr(8).split(",")
		if a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(p[0].to_int(), p[1].to_int())
		if a.begins_with("--ffmpeg="):
			ffmpeg = a.substr(9)
		if a == "--png":
			frame_mode = "png"
		if a == "--cpu":
			codec = "libx264"
		if a.begins_with("--cq="):
			cq = a.substr(5).to_int()
		if a.begins_with("--preroll="):
			preroll = a.substr(10).to_int()
		if a.begins_with("--len="):
			len_scale = a.substr(6).to_float()
	if takes.is_empty() or takes.has("all"):
		takes = PackedStringArray(TAKES)
	GameClock.fixed_step = 1.0 / fps
	CameraBlur.fixed_dt = 1.0 / fps
	super._ready()
	# The frames are drawn at the trailer's size; the window shows them scaled down.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_window().content_scale_size = size

func _run() -> void:
	# The engine eats --fixed-fps, so check for it by its effect: every frame's step exactly
	# one frame long, however slowly they come.
	for i in 5:
		await get_tree().process_frame
		if not is_equal_approx(get_process_delta_time(), 1.0 / fps):
			push_error("trailer: run with --fixed-fps %d (before the scene path), or --fps=N to match it" % fps)
			get_tree().quit(1)
			return
	hud_mode = "none"
	_apply_hud_mode()
	gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var p: Player = world.player
	p.set_physics_process(false)
	p.visible = false
	cam = Camera3D.new()
	cam.name = "TrailerCamera"
	cam.near = 0.05
	cam.far = 6000.0
	world.add_child(cam)
	cam.current = true
	_rain = HeroRain.new()
	world.add_child(_rain)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for name in takes:
		if not has_method("_take_" + name):
			print("trailer: no take called ", name)
			continue
		var t0 := Time.get_ticks_msec()
		await call("_take_" + name)
		print("trailer: take %s done in %d s" % [name, (Time.get_ticks_msec() - t0) / 1000])
	Game.close_world()
	get_tree().quit()

# --- Recording ----------------------------------------------------------------------

## Late in each frame (after everything else has moved): the camera's pose for the frame
## about to be drawn, the clock, and the held shader parameters.
func _process(delta: float) -> void:
	super._process(delta)
	if _rec_i < 0 or not _pose.is_valid():
		return
	var t := float(_rec_i) / float(maxi(_frames - 1, 1))
	_apply_pose(t)
	Game.day = lerpf(_day.x, _day.y, t)
	for k in _hold:
		RenderingServer.global_shader_parameter_set(k, _hold[k])
	if _tick.is_valid():
		_tick.call(_rec_i, t)

func _apply_pose(t: float) -> void:
	var pl: Array = _pose.call(t)
	var eye: Vector3 = pl[0]
	var look: Vector3 = pl[1]
	cam.fov = _fov if pl.size() < 3 else float(pl[2])
	cam.global_position = eye
	if not eye.is_equal_approx(look):
		var up := Vector3.UP if absf((look - eye).normalized().y) < 0.99 else Vector3.FORWARD
		cam.look_at(look, up)
	# The world streams round the player: keep it with the camera.
	world.player.global_position = eye - Vector3(0, 1.6, 0)

## Records one take: puts the camera at its first pose, lets the land load and the light
## settle, rolls `preroll` frames unrecorded (rain filling the air, the eye adapting),
## then records `secs` seconds.
func _record(name: String, secs: float, pose: Callable, opts := {}) -> void:
	_pose = pose
	_tick = opts.get("tick", Callable())
	_fov = float(opts.get("fov", 40.0))
	var day = opts.get("day", 0.42)
	_day = day if day is Vector2 else Vector2(float(day), float(day))
	if day_override >= 0.0:
		_day = Vector2(day_override, day_override)
	_frames = maxi(2, int(round(secs * len_scale * fps)))
	_set_weather(String(opts.get("weather", "clear")))
	Game.day = _day.x
	_rec_i = -1
	_apply_pose(0.0)
	var at: Vector3 = (pose.call(0.0) as Array)[0]
	world.atmosphere._target_w = Eras.look(world.atmosphere.field.era_weights(at.x, at.z))
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	await _wait_loaded(world.player, world.streamer)
	# The land along the path, so nothing pops in mid-take: visit a few poses on the way.
	for k in range(1, 5):
		_apply_pose(k / 4.0)
		await _wait_loaded(world.player, world.streamer)
	_apply_pose(0.0)
	await _wait_loaded(world.player, world.streamer)
	Game.day = _day.x
	_clear_trees(world.streamer, at, 3.0)
	_shoo_creatures(at, 60.0, true)
	if opts.has("setup"):
		await (opts["setup"] as Callable).call()
	await _settle(world.player)
	for i in (preroll if preroll >= 0 else int(opts.get("preroll", 60))):
		Game.day = _day.x
		for k in _hold:
			RenderingServer.global_shader_parameter_set(k, _hold[k])
		await get_tree().process_frame
	var enc := _open(name)
	if enc.is_empty():
		return
	var mid: Image = null
	print("trailer: recording %s, %d frames at %dx%d" % [name, _frames, size.x, size.y])
	for i in _frames:
		_rec_i = i
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		_write(enc, img, i)
		if i == _frames / 2:
			mid = img.duplicate()
		if i % 60 == 0:
			_shoo_creatures(cam.global_position, 60.0, true)
			if not world.streamer.is_ready_at(cam.global_position):
				print("  frame %d: the ground under the camera isn't in yet" % i)
	_rec_i = -1
	_hold.clear()
	_tick = Callable()
	_rain.stop()
	await _close(enc, name)
	if mid:
		mid.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		mid.save_jpg(out_dir.path_join(name + "_mid.jpg"), 0.9)
	var info := {"take": name, "frames": _frames, "fps": fps, "size": [size.x, size.y], "seed": Game.seed,
		"start": var_to_str((pose.call(0.0) as Array)[0]), "end": var_to_str((pose.call(1.0) as Array)[0]),
		"day": [_day.x, _day.y], "weather": opts.get("weather", "clear"), "note": opts.get("note", "")}
	var f := FileAccess.open(out_dir.path_join(name + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	print("captured ", name)

func _open(name: String) -> Dictionary:
	var dir := ProjectSettings.globalize_path(out_dir)
	if frame_mode == "png":
		DirAccess.make_dir_recursive_absolute(dir.path_join(name))
		return {"png": dir.path_join(name), "tasks": []}
	var args := PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [size.x, size.y], "-r", str(fps), "-i", "-"])
	if codec == "hevc_nvenc":
		args.append_array(["-c:v", "hevc_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", str(cq), "-b:v", "0",
			"-maxrate", "250M", "-bufsize", "500M", "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v", "hvc1"])
	else:
		args.append_array(["-c:v", codec, "-crf", str(cq), "-preset", "slow", "-pix_fmt", "yuv420p"])
	args.append_array(["-movflags", "+faststart", dir.path_join(name + ".mp4")])
	var pipe := OS.execute_with_pipe(ffmpeg, args)
	if pipe.is_empty():
		push_error("trailer: couldn't start ffmpeg (%s); pass --ffmpeg=PATH or --png" % ffmpeg)
		return {}
	return pipe

func _write(enc: Dictionary, img: Image, i: int) -> void:
	if enc.has("png"):
		var tasks: Array = enc["tasks"]
		while tasks.size() > 6:
			WorkerThreadPool.wait_for_task_completion(tasks.pop_front())
		var path: String = (enc["png"] as String).path_join("%05d.png" % i)
		tasks.append(WorkerThreadPool.add_task(func() -> void: img.save_png(path)))
		return
	(enc["stdio"] as FileAccess).store_buffer(img.get_data())

func _close(enc: Dictionary, name: String) -> void:
	if enc.has("png"):
		for t in enc["tasks"]:
			WorkerThreadPool.wait_for_task_completion(t)
		return
	(enc["stdio"] as FileAccess).close()
	var pid := int(enc["pid"])
	while OS.is_process_running(pid):
		await get_tree().process_frame
	var err := (enc["stderr"] as FileAccess).get_as_text() if enc.has("stderr") else ""
	if err.strip_edges() != "":
		print("  ffmpeg: ", err.strip_edges())
	var dir := ProjectSettings.globalize_path(out_dir)
	var out := []
	OS.execute(ffmpeg, PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-i", dir.path_join(name + ".mp4"),
		"-vf", "scale=1280:-2", "-c:v", "h264_nvenc" if codec == "hevc_nvenc" else "libx264",
		"-cq" if codec == "hevc_nvenc" else "-crf", "27", "-pix_fmt", "yuv420p",
		"-movflags", "+faststart", dir.path_join(name + "_proxy.mp4")]), out, true)
	if not out.is_empty() and String(out[0]).strip_edges() != "":
		print("  proxy: ", String(out[0]).strip_edges())

## Forces the weather when the build has it (Weather, src/env/weather.gd).
func _set_weather(kind: String) -> void:
	var w := _weather()
	if w:
		w.call("force", kind)

func _weather() -> Node:
	return world.atmosphere.get_node_or_null("Weather") if world.atmosphere else null

## Holds the ground soaked and the hollows brimming for the take (with the weather).
func _wet() -> void:
	if _weather():
		_hold = {"weather_wet_g": 1.0, "weather_puddle_g": 1.0, "weather_rain_g": 1.0}

func _strike() -> void:
	var w := _weather()
	if w and "strike_now" in w:
		w.set("strike_now", true)

# --- Paths ----------------------------------------------------------------------------

## A smooth path through keys [eye, look_at] (Catmull-Rom, eased in and out).
func _path(keys: Array, ease := true) -> Callable:
	return func(t: float) -> Array:
		var u := smoothstep(0.0, 1.0, t) if ease else t
		return [_spline(keys, u, 0), _spline(keys, u, 1)]

func _spline(keys: Array, u: float, part: int) -> Vector3:
	var n := keys.size()
	if n == 1:
		return keys[0][part]
	var f := clampf(u, 0.0, 1.0) * (n - 1)
	var i := mini(int(f), n - 2)
	var s := f - i
	var p0: Vector3 = keys[maxi(i - 1, 0)][part]
	var p1: Vector3 = keys[i][part]
	var p2: Vector3 = keys[i + 1][part]
	var p3: Vector3 = keys[mini(i + 2, n - 1)][part]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s * s + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * s * s * s)

func _ground(q: Vector2) -> float:
	var k := Vector2i(int(floor(q.x / ChunkGenerator.SIZE)), int(floor(q.y / ChunkGenerator.SIZE)))
	var c: ChunkNode = world.streamer.get_chunk(k)
	if c:
		return ChunkGenerator.height_at(c.data, q.x - k.x * ChunkGenerator.SIZE, q.y - k.y * ChunkGenerator.SIZE)
	return gen.field.height(q.x, q.y)

## The highest ground within `r` metres of the line a..b (for a flight's clearance).
func _ridge(a: Vector2, b: Vector2, r: float) -> float:
	var top := maxf(Water.LEVEL, -INF)
	var side := (b - a).normalized().orthogonal()
	for k in 25:
		var q := a.lerp(b, k / 24.0)
		for s in [-1.0, 0.0, 1.0]:
			var w: Vector2 = q + side * r * s
			top = maxf(top, gen.field.height(w.x, w.y))
	return top

## A flight from a to b at `clear` metres over the highest ground on the way, looking
## `ahead` metres along the way and down to `look_down` metres below the eye.
func _flight(a: Vector2, b: Vector2, clear: float, ahead: float, look_down: float) -> Callable:
	var y := _ridge(a, b, 50.0) + clear
	var d := (b - a).normalized()
	var keys := []
	for k in 4:
		var q := a.lerp(b, k / 3.0)
		var l := q + d * ahead
		keys.append([Vector3(q.x, y, q.y), Vector3(l.x, y - look_down, l.y)])
	return _path(keys, false)

func _v3(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, q.y)

# --- Finds ---------------------------------------------------------------------------

var _town_cache := {}
func _town() -> Dictionary:
	if _town_cache.is_empty():
		_town_cache = _find_settlement(gen, Eras.MEDIEVAL, 2) if gen.towns else {}
		if _town_cache.is_empty():
			_town_cache = _find_settlement(gen, Eras.MEDIEVAL)
	return _town_cache

## The market square of the biggest town near spawn: {c, rad, mid (well/cross), stalls}.
func _square() -> Dictionary:
	var town := _town()
	if town.is_empty():
		return {}
	var pl := TownLife.plan(gen, town)
	var sq: Dictionary = pl["square"]
	if sq.is_empty():
		return {"c": town["center"], "rad": 10.0, "mid": town["center"], "stalls": []}
	var mid: Vector2 = sq["c"]
	var stalls: Array = []
	for e in pl["pieces"]:
		if e["k"] == "well" or e["k"] == "cross":
			mid = e["p"]
		elif e["k"] == "stall":
			stalls.append(e["p"])
	return {"c": sq["c"], "rad": float(sq["rad"]), "mid": mid, "stalls": stalls}

func _climate_spot(want: Array) -> Vector2:
	for r in 16:
		for iz in range(-r, r + 1):
			for ix in range(-r, r + 1):
				if maxi(absi(ix), absi(iz)) != r or gen.field.site_landform(ix, iz) != WorldField.LF_NONE:
					continue
				var p := gen.field.site_pos(ix, iz)
				if _climate_is(gen, p, want) and _low_ground(gen, p) and _climate_is(gen, p + Vector2(150, 0), want) \
						and _climate_is(gen, p - Vector2(150, 0), want):
					return p
	return Vector2.INF

func _landform_spot(lf: int) -> Vector2:
	for r in 14:
		for iz in range(-r, r + 1):
			for ix in range(-r, r + 1):
				if maxi(absi(ix), absi(iz)) != r:
					continue
				var p := gen.field.site_pos(ix, iz)
				if gen.field.site_landform(ix, iz) == lf and gen.field.landform_weights(p.x, p.y)[lf] > 0.95:
					return p
	return Vector2.INF

func _peak() -> Vector3:
	var peak := Vector3(0, -INF, 0)
	for iz in range(-60, 61):
		for ix in range(-60, 61):
			var h := gen.field.height(ix * 40.0, iz * 40.0)
			if h > peak.y:
				peak = Vector3(ix * 40.0, h, iz * 40.0)
	return peak

func _boat(kind: String) -> Dictionary:
	for r in 12:
		for cz in range(-r, r + 1):
			for cx in range(-r, r + 1):
				if maxi(absi(cx), absi(cz)) != r:
					continue
				var s := Boats.plan(gen.field, cx, cz)
				if s.is_empty():
					continue
				var key: String = "small" if s["boat"] in ["fishing_boat", "launch", "rowboat"] else s["boat"]
				if key == kind:
					return s
	return {}

## A boat under way at a fixed stretch of its loop, wake primed.
func _sail(kind: String, route_t: float) -> BoatNode:
	var site := _boat(kind)
	if site.is_empty():
		print("trailer: no %s boat near spawn" % kind)
		return null
	var bc: Vector2 = site["center"]
	world.player.global_position = Vector3(bc.x + 20.0, 3.0, bc.y)
	var b: BoatNode = world.boats.put(site, false)
	b.held = 0.0
	b.route_t = route_t
	b.prime_wake()
	return b

# --- Takes ---------------------------------------------------------------------------

## Rain falling into a puddle on the market square, the camera a hand's breadth over the
## water, the stalls and houses mirrored in it and soft behind; it creeps forward.
func _take_rain_low() -> void:
	var sq := _square()
	if sq.is_empty():
		return
	var c: Vector2 = sq["c"]
	var look2: Vector2 = (sq["stalls"][0] if not (sq["stalls"] as Array).is_empty() else sq["mid"])
	var d := (look2 - c).normalized() if look2 != c else Vector2(1, 0)
	var spot := c - d * 2.0
	var gy := _ground(spot)
	var puddle := _v3(spot + d * 1.4, gy)
	var eye0 := _v3(spot, gy + 0.16)
	var eye1 := _v3(spot + d * 0.5, gy + 0.13)
	var look := _v3(look2, gy + 1.2)
	await _record("rain_low", 9.0, _path([[eye0, look], [eye1, look + Vector3(0, -0.3, 0)]]), {
		"weather": "storm", "day": 0.47, "fov": 32.0, "preroll": 240,
		"setup": func() -> void:
			_wet()
			_rain.start(puddle, 2.4, 1.9, 70.0)
			await _wait(1),
		"tick": func(i: int, _t: float) -> void:
			if i == int(_frames * 0.62):
				_strike(),
		"note": "puddle at %s" % puddle})

## The same puddle seen as you would standing over it: eyes down at the rain hitting the
## water at your feet.
func _take_rain_pov() -> void:
	var sq := _square()
	if sq.is_empty():
		return
	var c: Vector2 = sq["c"]
	var look2: Vector2 = (sq["stalls"][0] if not (sq["stalls"] as Array).is_empty() else sq["mid"])
	var d := (look2 - c).normalized() if look2 != c else Vector2(1, 0)
	var spot := c - d * 2.0
	var gy := _ground(spot)
	var puddle := _v3(spot + d * 1.4, gy)
	var eye0 := _v3(spot - d * 0.2, gy + 1.65)
	await _record("rain_pov", 7.0, _path([[eye0, puddle + _v3(d * 0.2, 0.0)], [eye0 + Vector3(0, -0.02, 0), puddle + _v3(d * 2.5, 0.6)]]), {
		"weather": "rain", "day": 0.47, "fov": 46.0, "preroll": 240,
		"setup": func() -> void:
			_wet()
			_rain.start(puddle, 2.4, 1.9, 55.0)
			await _wait(1)})

## The town under a thunderstorm from the road outside its walls; two strikes.
func _take_storm_town() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var ways: Array = gen.road_angles(town)
	var dir := Vector2.from_angle(ways[0] if not ways.is_empty() else 0.8)
	var a := tc + dir * 170.0
	var b := tc + dir * 140.0 + dir.orthogonal() * 25.0
	var th := float(town["target_h"])
	await _record("storm_town", 9.0, _path([[_v3(a, _ground(a) + 14.0), _v3(tc, th + 6.0)], [_v3(b, _ground(b) + 11.0), _v3(tc, th + 8.0)]]), {
		"weather": "storm", "day": 0.6, "fov": 38.0, "preroll": 300,
		"tick": func(i: int, _t: float) -> void:
			if i == int(_frames * 0.25) or i == int(_frames * 0.7):
				_strike()})

## Dawn breaking over the highest snowy peak (a time-lapse: half a morning in 10 s), the
## camera drifting toward it.
func _take_sunrise_peaks() -> void:
	var peak := _peak()
	var top := Vector2(peak.x, peak.z)
	var best := Vector2.INF
	var low := INF
	for k in 16:
		var q := top + Vector2.from_angle(TAU * k / 16.0) * 600.0
		var h := gen.field.height(q.x, q.y)
		if h > WATER_SAFE + 1.0 and h < low:
			low = h
			best = q
	if best == Vector2.INF:
		return
	var d := (top - best).normalized()
	var b := best + d * 120.0
	var y0 := _ridge(best, b, 30.0) + 30.0
	await _record("sunrise_peaks", 10.0, _path([[_v3(best, y0), _v3(top, peak.y - 40.0)], [_v3(b, y0 + 10.0), _v3(top, peak.y - 30.0)]]), {
		"day": Vector2(0.215, 0.31), "fov": 36.0})

func _fly_over(name: String, at: Vector2, day: float, dir_deg: float, clear := 32.0) -> void:
	if at == Vector2.INF:
		print("trailer: nowhere for ", name)
		return
	var d := Vector2.from_angle(deg_to_rad(dir_deg))
	await _record(name, 8.0, _flight(at - d * 140.0, at + d * 140.0, clear, 90.0, 28.0), {"day": day, "fov": 42.0})

func _take_fly_rainforest() -> void:
	await _fly_over("fly_rainforest", _climate_spot(CLIMATE_SHOTS["93_rainforest"]), 0.38, 30.0, 26.0)

func _take_fly_savanna() -> void:
	await _fly_over("fly_savanna", _climate_spot(CLIMATE_SHOTS["94_savanna"]), 0.70, -60.0, 22.0)

func _take_fly_boreal() -> void:
	await _fly_over("fly_boreal", _climate_spot(CLIMATE_SHOTS["95_boreal"]), 0.33, 120.0, 30.0)

func _take_fly_karst() -> void:
	await _fly_over("fly_karst", _landform_spot(WorldField.LF_KARST), 0.40, 200.0, 18.0)

func _take_fly_needles() -> void:
	await _fly_over("fly_needles", _landform_spot(WorldField.LF_NEEDLES), 0.66, 10.0, 15.0)

## Rising from the plunge pool of the nearest tall waterfall up past its lip.
func _take_waterfall_rise() -> void:
	var best := {}
	var bd := INF
	for iz in range(-6, 6):
		for ix in range(-6, 6):
			var f := Waterfalls.in_cell(gen, ix, iz)
			if f.is_empty() or float(f["drop"]) < 8.0:
				continue
			var dl := (f["lip"] as Vector2).length()
			if dl < bd:
				bd = dl
				best = f
	if best.is_empty():
		print("trailer: no waterfall near the spawn")
		return
	var lip: Vector2 = best["lip"]
	var d: Vector2 = best["dir"]
	var side := Vector2(-d.y, d.x)
	var top: float = best["top"]
	var low: float = (best["levels"] as PackedFloat32Array)[0]
	var h := Waterfalls.tier_drop(best, 0)
	var a := lip + d * (Waterfalls.pool_radius(h) * 1.5 + h * 0.8 + 10.0) + side * 5.0
	var b := lip + d * (h * 0.8 + 22.0) - side * 8.0
	var face := _v3(lip, low + h * 0.5)
	await _record("waterfall_rise", 9.0, _path([[_v3(a, maxf(low, _ground(a)) + 1.5), face], [_v3(b, top + 8.0), _v3(lip - d * 40.0, top + 2.0)]]), {
		"day": 0.42, "fov": 40.0, "note": "waterfall at %s drop %.1f" % [lip, float(best["drop"])]})

## Skimming out over the lake at sunset, a metre over the swell.
func _take_lake_glide() -> void:
	var shore := _find_shore(gen)
	if shore == Vector2.ZERO:
		print("trailer: no shore")
		return
	var out := shore_out
	var a := shore + out * 6.0
	var b := shore + out * 70.0
	await _record("lake_glide", 8.0, _path([[_v3(a, Water.LEVEL + 1.4), _v3(a + out * 120.0, Water.LEVEL + 0.4)],
		[_v3(b, Water.LEVEL + 0.9), _v3(b + out * 120.0 + out.orthogonal() * 20.0, Water.LEVEL + 0.3)]], false), {
		"day": 0.725, "fov": 40.0})

## Half way round the cog as she sails, low over the water.
func _take_cog_orbit() -> void:
	var b := _sail("cog", 120.0)
	if b == null:
		return
	await _record("cog_orbit", 10.0, func(t: float) -> Array:
		var a := lerpf(-0.6, 1.9, smoothstep(0.0, 1.0, t))
		var eye := b.to_global(Vector3(cos(a) * 30.0, 0.0, sin(a) * 30.0))
		eye.y = Water.LEVEL + 4.0 + 3.0 * t
		return [eye, b.to_global(Vector3(0, 4.0, 0))], {"day": 0.62, "fov": 38.0, "preroll": 30})

## High on the cog's quarter keeping pace with her, the wake fanning out behind.
func _take_cog_wake() -> void:
	var b := _sail("cog", 130.0)
	if b == null:
		return
	await _record("cog_wake", 9.0, func(t: float) -> Array:
		var eye := b.to_global(Vector3(18.0 - 8.0 * t, 0.0, 34.0 - 6.0 * t))
		eye.y = Water.LEVEL + 16.0 - 4.0 * t
		return [eye, b.to_global(Vector3(0, 0.0, 18.0))], {"day": 0.44, "fov": 40.0, "preroll": 30})

## Alongside a small boat as her crew pull at the oars.
func _take_rowboat() -> void:
	var b := _sail("small", 120.0)
	if b == null:
		return
	await _record("rowboat", 8.0, func(t: float) -> Array:
		var eye := b.to_global(Vector3(7.5, 0.0, 3.0 - 6.0 * t))
		eye.y = Water.LEVEL + 1.3
		return [eye, b.to_global(Vector3(0, 0.9, -0.5))], {"day": 0.4, "fov": 40.0, "preroll": 30})

## In over the fields and the wall to the heart of the town.
func _take_town_flyin() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var ways: Array = gen.road_angles(town)
	var dir := Vector2.from_angle((ways[0] if not ways.is_empty() else 0.8) + 0.35)
	var th := float(town["target_h"])
	var a := tc + dir * 260.0
	var b := tc + dir * 70.0
	var y0 := maxf(_ridge(a, b, 30.0), th) + 55.0
	await _record("town_flyin", 10.0, _path([[_v3(a, y0), _v3(tc, th)], [_v3(tc.lerp(a, 0.5), y0 - 15.0), _v3(tc, th)],
		[_v3(b, th + 26.0), _v3(tc - dir * 30.0, th + 2.0)]]), {"day": 0.40, "fov": 42.0})

## Along the market at the height of the crowd, past the stalls.
func _take_market_dolly() -> void:
	var sq := _square()
	if sq.is_empty():
		return
	var c: Vector2 = sq["c"]
	var mid: Vector2 = sq["mid"]
	var r: float = sq["rad"]
	var stall: Vector2 = sq["stalls"][0] if not (sq["stalls"] as Array).is_empty() else c + Vector2(r, 0)
	var d := (stall - mid).normalized()
	var side := d.orthogonal()
	var a := mid - d * 3.0 - side * (r * 0.5)
	var b := mid - d * 3.0 + side * (r * 0.5)
	var gy := _ground(mid)
	await _record("market_dolly", 9.0, _path([[_v3(a, gy + 2.0), _v3(stall - side * 3.0, gy + 1.3)], [_v3(b, gy + 2.3), _v3(stall + side * 3.0, gy + 1.3)]]), {
		"day": 0.43, "fov": 40.0})

## Round the town at sunset, the low sun raking the roofs.
func _take_village_sunset() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var th := float(town["target_h"])
	var y := maxf(_ridge(tc - Vector2(100, 100), tc + Vector2(100, 100), 60.0), th) + 30.0
	await _record("village_sunset", 10.0, func(t: float) -> Array:
		var a := deg_to_rad(lerpf(-80.0, -30.0, smoothstep(0.0, 1.0, t)))
		var q := tc + Vector2.from_angle(a) * 95.0
		return [_v3(q, y), _v3(tc, th + 4.0)], {"day": 0.735, "fov": 40.0})

## Night: the town's windows and hearths lit under a full moon, slowly pushing in.
func _take_village_night() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var th := float(town["target_h"])
	var a := tc + Vector2(55, -45)
	var b := tc + Vector2(40, -32)
	var keep := Atmosphere.moon_phase_override
	Atmosphere.moon_phase_override = 0.5
	await _record("village_night", 9.0, _path([[_v3(a, _ground(a) + 4.0), _v3(tc, th + 2.0)], [_v3(b, _ground(b) + 3.0), _v3(tc, th + 2.5)]]), {
		"day": 0.93, "fov": 42.0})
	Atmosphere.moon_phase_override = keep

## From the town's roofs up to the Milky Way.
func _take_night_sky() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var th := float(town["target_h"])
	var eye := _v3(tc + Vector2(70, 50), _ground(tc + Vector2(70, 50)) + 3.0)
	var sky := Vector2(2, 1).normalized()
	await _record("night_sky", 10.0, _path([[eye, _v3(tc, th + 3.0)], [eye + Vector3(0, 0.5, 0), eye + _v3(sky * 200.0, 200.0 * tan(0.5))]]), {
		"day": 0.0, "fov": 46.0})

## The last shot: rising and pulling back from the town at golden hour until the land
## runs to the horizon.
func _take_finale() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var th := float(town["target_h"])
	var d := Vector2(-0.7, 0.5).normalized()
	var a := tc + d * 60.0
	var b := tc + d * 420.0
	await _record("finale", 12.0, _path([[_v3(a, th + 22.0), _v3(tc, th + 4.0)], [_v3(tc.lerp(b, 0.5), th + 90.0), _v3(tc, th)],
		[_v3(b, th + 190.0), _v3(tc - d * 400.0, th + 40.0)]]), {"day": 0.70, "fov": 40.0})
