extends SceneTree
## Renders the sky shader alone at a time of day, for judging stars, clouds and dusk:
##   godot --path . --script res://tools/preview_sky.gd -- --out=F.png [--daylight=0.0]
##     [--sun=-0.3] [--pitch=40] [--cover=0.5] [--stars=1.3]
## --sun is the sun's height (sin of its elevation); --pitch looks up that many degrees.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://sky.png"
	var daylight := 0.0
	var sun_y := -0.3
	var pitch := 40.0
	var cover := 0.5
	var stars := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--daylight="):
			daylight = float(a.substr(11))
		elif a.begins_with("--sun="):
			sun_y = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--cover="):
			cover = float(a.substr(8))
		elif a.begins_with("--stars="):
			stars = float(a.substr(8))
	get_root().size = Vector2i(1600, 900)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/env/sky.gdshader")
	if ResourceLoader.exists("res://assets/textures/sky/night_stars.jpg"):
		mat.set_shader_parameter("night_stars", load("res://assets/textures/sky/night_stars.jpg"))
	if ResourceLoader.exists("res://assets/textures/sky/moon.png"):
		mat.set_shader_parameter("moon_tex", load("res://assets/textures/sky/moon.png"))
	mat.set_shader_parameter("daylight", daylight)
	mat.set_shader_parameter("cloud_cover", cover)
	mat.set_shader_parameter("time_s", 100.0)
	if stars >= 0.0:
		mat.set_shader_parameter("stars_gain", stars)
	var sky := Sky.new()
	sky.sky_material = mat
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	var dir := Vector3(sqrt(maxf(0.0, 1.0 - sun_y * sun_y - 0.1)), sun_y, 0.3).normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
	sun.light_energy = 2.0 * smoothstep(-0.05, 0.15, sun_y)
	# As in the game: the sun light goes out below the horizon, the sky still knows where it is.
	sun.visible = sun_y > -0.1
	RenderingServer.global_shader_parameter_set("sun_dir_g", dir)
	get_root().add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 70.0
	get_root().add_child(cam)
	cam.rotation = Vector3(deg_to_rad(pitch), PI * 0.5, 0)
	cam.make_current()
	for i in 20:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
