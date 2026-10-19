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
	"fly_karst", "fly_needles", "fly_gorge", "waterfall_rise", "lake_glide", "cog_orbit", "cog_wake", "rowboat", "town_flyin",
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
const TAG_LAYER := 1 << 19
const LIFT := 60.0 ## metres the (hidden) player hangs over the camera
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
	if p.body:
		p.body.visible = false
	cam = Camera3D.new()
	cam.name = "TrailerCamera"
	cam.near = 0.05
	cam.far = 6000.0
	# Speech and name tags (Label3D) go on a layer this camera doesn't draw.
	cam.cull_mask &= ~TAG_LAYER
	world.add_child(cam)
	cam.current = true
	for n in world.find_children("*", "Label3D", true, false):
		(n as Label3D).layers = TAG_LAYER
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Label3D:
			(n as Label3D).layers = TAG_LAYER)
	# The world streams, lights and rains round the camera, not the player: the player
	# hangs well above it (out of sight), so villagers don't walk up to greet the lens.
	world.streamer.set_target(cam)
	world.atmosphere.target = cam
	for k in ["Water", "ClimateWear", "FarLand"]:
		var n := world.get_node_or_null(k)
		if n and "target" in n:
			n.set("target", cam)
	# Reflections that don't give up half way across a puddle (the game's 48 steps leave
	# holes where the sky shows through).
	world.atmosphere.env.ssr_max_steps = 256
	world.atmosphere.env.ssr_depth_tolerance = 0.3
	var w := _weather()
	if w:
		# The weather a take asks for, at once (no minute of clouds gathering).
		w.set("ease_time", 0.0)
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
## Close-ups at the puddle are of the rain, not of whoever wanders past the lens: the
## town's people within `people` metres of the camera stand still out of sight for the take.
var _people_r := 0.0
var _hidden: Array[Node3D] = []
func _hide_people() -> void:
	if _people_r <= 0.0 or world.npcs == null:
		return
	for n in world.npcs._by_id.values():
		if is_instance_valid(n) and (n as Node3D).visible and (n as Node3D).global_position.distance_to(cam.global_position) < _people_r:
			(n as Node3D).visible = false
			(n as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
			_hidden.append(n)

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
	_hide_people()
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
	world.player.global_position = eye + Vector3(0, LIFT, 0)

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
	world.atmosphere.vfog_boost = float(opts.get("vfog", 1.0))
	world.atmosphere.fog_boost = float(opts.get("fog", 1.0))
	_people_r = float(opts.get("people", 0.0))
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
	_hide_people()
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
	world.atmosphere.vfog_boost = 1.0
	world.atmosphere.fog_boost = 1.0
	_people_r = 0.0
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
			n.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden.clear()
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
		_hold = {"weather_wet_g": 1.0, "weather_puddle_g": 0.55, "weather_rain_g": 1.0}

func _strike() -> void:
	var w := _weather()
	if w and "strike_now" in w:
		w.set("strike_now", true)

## The capture tour's sight-line check, with the camera (which the land now streams
## round) taken along to the spot.
func _clear_view(cands: Array, target: Vector3, eye_h: float, near: float, min_y := -INF) -> Vector2:
	cam.global_position = target + Vector3(0, 20, 0)
	return await super._clear_view(cands, target, eye_h, near, min_y)

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
		_town_cache = _mild_town(2) if gen.towns else {}
		if _town_cache.is_empty():
			_town_cache = _mild_town(0)
		if _town_cache.is_empty():
			_town_cache = _find_settlement(gen, Eras.MEDIEVAL)
		print("trailer: town at ", _town_cache.get("center"))
	return _town_cache

## The nearest medieval town of at least min_size in a mild climate: no snow on its roofs
## or its firs (ClimateWear), well below the snow line, its tiles red in the sun.
func _mild_town(min_size: int) -> Dictionary:
	for r in 40:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if maxi(absi(sx), absi(sz)) != r:
					continue
				var s := gen.settlement_at(sx, sz)
				if s.is_empty() or s["era"] != Eras.MEDIEVAL or int(s["size"]) < min_size:
					continue
				var c: Vector2 = s["center"]
				var mild := true
				for o in [Vector2.ZERO, Vector2(250, 0), Vector2(-250, 0), Vector2(0, 250), Vector2(0, -250)]:
					var q: Vector2 = c + o
					if ClimateWear.levels(gen.field, q.x, q.y).g > 0.02 or gen.field.height(q.x, q.y) > WorldField.snow_line - 160.0:
						mild = false
				if mild:
					return s
	return {}

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
	var rs: Dictionary = await _rain_spot()
	if rs.is_empty():
		return
	var d: Vector2 = rs["d"]
	var gy: float = rs["gy"]
	var cam2: Vector2 = rs["cam"]
	var puddle := _v3(cam2 + d * 1.7, gy)
	var far: Vector3 = rs["look"]
	await _record("rain_low", 9.0, _path([[_v3(cam2, gy + 0.42), far + Vector3(0, -0.6, 0)],
		[_v3(cam2 + d * 0.45, gy + 0.36), far + Vector3(0, -0.8, 0)]]), {
		"weather": "rain", "day": 0.47, "fov": 34.0, "preroll": 240, "people": 40.0,
		"setup": func() -> void:
			_wet()
			_rain.start(puddle, 2.2, 1.5, 75.0)
			await _wait(1),
		"tick": func(i: int, _t: float) -> void:
			if i == int(_frames * 0.85):
				_strike(),
		"note": "puddle at %s" % puddle})

## The same puddle seen as you would standing over it: eyes down at the rain hitting the
## water at your feet, then up to the square.
func _take_rain_pov() -> void:
	var rs: Dictionary = await _rain_spot()
	if rs.is_empty():
		return
	var d: Vector2 = rs["d"]
	var gy: float = rs["gy"]
	var cam2: Vector2 = rs["cam"]
	var puddle := _v3(cam2 + d * 1.7, gy)
	var eye0 := _v3(cam2, gy + 1.65)
	await _record("rain_pov", 7.0, _path([[eye0, puddle], [eye0 + Vector3(0, -0.02, 0), rs["look"]]]), {
		"weather": "rain", "day": 0.47, "fov": 46.0, "preroll": 240, "people": 40.0,
		"setup": func() -> void:
			_wet()
			_rain.start(puddle, 2.2, 1.5, 60.0)
			await _wait(1)})

## A spot on the market square with open ground in front and a stall or house to look
## at beyond it: {cam, d (the way it looks), gy, look}.
var _rain_cache := {}
func _rain_spot() -> Dictionary:
	if not _rain_cache.is_empty():
		return _rain_cache
	var sq := _square()
	if sq.is_empty():
		return {}
	var c: Vector2 = sq["c"]
	var r: float = sq["rad"]
	var looks: Array = (sq["stalls"] as Array).duplicate()
	looks.append(c)
	for lk: Vector2 in looks:
		var cands := []
		for k in 12:
			var dir := Vector2.from_angle(TAU * k / 12.0)
			for dist in [9.0, 12.0, 7.0]:
				var q: Vector2 = lk + dir * dist
				if q.distance_to(c) < r and q.distance_to(sq["mid"]) > 3.5:
					cands.append(q)
		var gl := _ground(lk)
		var got: Vector2 = await _clear_view(cands, _v3(lk, gl + 1.2), 1.7, 1.5)
		if got != Vector2.INF:
			var d := (lk - got).normalized()
			_rain_cache = {"cam": got, "d": d, "gy": _ground(got), "look": _v3(lk, gl + 1.4)}
			return _rain_cache
	return {}

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
		"weather": "storm", "day": 0.6, "fov": 38.0, "preroll": 300, "vfog": 0.5,
		"tick": func(i: int, _t: float) -> void:
			if i == int(_frames * 0.25) or i == int(_frames * 0.7):
				_strike()})

## Dawn breaking over the highest snowy peak (a time-lapse: half a morning in 10 s), the
## camera drifting toward it.
func _take_sunrise_peaks() -> void:
	var peak := _peak()
	var top := Vector2(peak.x, peak.z)
	# Stand on the sun's side, so the first light falls on the faces we look at.
	Game.day = 0.27
	await _wait(3)
	var sd := Vector2(Atmosphere.sun_dir.x, Atmosphere.sun_dir.z)
	var sun2 := sd.normalized() if sd.length() > 0.01 else Vector2(1, 0)
	var best := Vector2.INF
	for k in 9:
		var q := top + sun2.rotated(deg_to_rad((k - 4) * 12.0)) * 650.0
		var h := gen.field.height(q.x, q.y)
		if h > WATER_SAFE + 1.0 and (best == Vector2.INF or h < gen.field.height(best.x, best.y)):
			best = q
	if best == Vector2.INF:
		return
	var d := (top - best).normalized()
	var b := best + d * 120.0
	var y0 := _ridge(best, b, 30.0) + 30.0
	await _record("sunrise_peaks", 10.0, _path([[_v3(best, y0), _v3(top, peak.y - 40.0)], [_v3(b, y0 + 10.0), _v3(top, peak.y - 30.0)]]), {
		"day": Vector2(0.258, 0.272), "fov": 36.0, "vfog": 0.25, "fog": 0.4})

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

func _take_fly_gorge() -> void:
	await _fly_over("fly_gorge", _landform_spot(WorldField.LF_GORGE), 0.36, 70.0, 20.0)

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
		var eye := b.to_global(Vector3(12.0 - 6.0 * t, 0.0, 30.0 - 6.0 * t))
		eye.y = Water.LEVEL + 7.0 - 2.5 * t
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
	var gs := _ground(stall)
	var tgt := _v3(stall, gs + 1.3)
	# Two clear spots facing the stall from across the square, a few metres apart, and
	# well off the well or cross in the middle.
	var cands := []
	for k in 16:
		var q := stall + Vector2.from_angle(TAU * k / 16.0) * 9.0
		if q.distance_to(c) < r + 2.0 and q.distance_to(mid) > 4.5:
			cands.append(q)
	var a: Vector2 = await _clear_view(cands, tgt, 1.7, 1.5)
	if a == Vector2.INF:
		return
	var side := (stall - a).normalized().orthogonal()
	var bc := []
	for off in [6.0, -6.0, 4.0, -4.0]:
		var q: Vector2 = a + side * off
		if q.distance_to(mid) > 4.5:
			bc.append(q)
	var b: Vector2 = await _clear_view(bc, tgt, 1.7, 1.5)
	if b == Vector2.INF:
		b = a
	await _record("market_dolly", 9.0, _path([[_v3(a, _ground(a) + 2.0), tgt + _v3(-side * 1.5, 0.0)], [_v3(b, _ground(b) + 2.2), tgt + _v3(side * 1.5, 0.0)]]), {
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
		return [_v3(q, y), _v3(tc, th + 4.0)], {"day": 0.72, "fov": 40.0, "vfog": 0.3})

## Night: the town's windows and hearths lit under a full moon, slowly pushing in.
func _take_village_night() -> void:
	var town := _town()
	if town.is_empty():
		return
	var tc: Vector2 = town["center"]
	var th := float(town["target_h"])
	var cands := []
	for k in 12:
		for dist in [60.0, 75.0, 50.0]:
			cands.append(tc + Vector2.from_angle(TAU * k / 12.0 + 0.3) * dist)
	var a: Vector2 = await _clear_view(cands, _v3(tc, th + 3.0), 9.0, 12.0)
	if a == Vector2.INF:
		return
	var b := a.lerp(tc, 0.25)
	var keep := Atmosphere.moon_phase_override
	Atmosphere.moon_phase_override = 0.5
	await _record("village_night", 9.0, _path([[_v3(a, _ground(a) + 9.0), _v3(tc, th + 2.0)], [_v3(b, maxf(_ground(b), _ground(a)) + 8.0), _v3(tc, th + 2.5)]]), {
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
	# Up only so far that the land stays clear to the horizon, ending on the town with the
	# country running away beyond it.
	await _record("finale", 12.0, _path([[_v3(a, th + 22.0), _v3(tc, th + 4.0)], [_v3(tc.lerp(b, 0.45), th + 55.0), _v3(tc, th + 2.0)],
		[_v3(tc.lerp(b, 0.8), th + 85.0), _v3(tc - d * 300.0, th + 10.0)]]), {"day": 0.68, "fov": 40.0, "vfog": 0.15, "fog": 0.35})
