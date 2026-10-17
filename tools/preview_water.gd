extends SceneTree
## Renders a patch of lake (src/env/water.gdshader) over a sloping sandy bed, for judging
## the water's colour, see-through, foam and reflections:
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_water.gd -- --out=F.png [--pitch=-20] [--river]
## --river uses the river shader instead (flowing diagonally, no edge fade).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://water.png"
	var pitch := -18.0
	var shader := "res://src/env/water.gdshader"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a == "--river":
			shader = "res://src/env/river.gdshader"
	get_root().size = Vector2i(1600, 900)
	RenderingServer.global_shader_parameter_set("sun_dir_g", Vector3(0.4, 0.6, 0.3).normalized())
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(1, 0.3))
	RenderingServer.global_shader_parameter_set("wind_strength", 0.35)
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -Vector3(0.4, 0.6, 0.3), Vector3.UP)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	get_root().add_child(sun)
	# A sandy bed sloping from the shore behind you (z = 16) to about 7 m deep at z = -60.
	var bed := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(200, 80)
	bm.subdivide_depth = 40
	bed.mesh = bm
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.62, 0.55, 0.42)
	bed.material_override = sand
	bed.rotation = Vector3(-atan(6.0 / 64.0), 0, 0)
	bed.position = Vector3(0, -4.0, -26)
	get_root().add_child(bed)
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(400, 400)
	wm.subdivide_width = 200
	wm.subdivide_depth = 200
	water.mesh = wm
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	water.material_override = mat
	get_root().add_child(water)
	var cam := Camera3D.new()
	cam.fov = 70.0
	get_root().add_child(cam)
	cam.position = Vector3(0, 1.8, 8)
	cam.rotation = Vector3(deg_to_rad(pitch), 0, 0)
	cam.make_current()
	for i in 30:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
