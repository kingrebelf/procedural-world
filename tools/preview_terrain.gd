extends Node3D
## Bare terrain round a point under a plain sun and sky, for quick ground and rock shader
## checks without streaming the world (a frame in under a minute on a software renderer):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan \
##     --resolution 1280x720 res://tools/preview_terrain.tscn -- --at=x,z [--yaw=deg]
##     [--pitch=deg] [--up=m above the ground] [--r=chunks round, 3] [--grass] [--grade]
##     [--seed=4242] [--lods] [--out=path.png]
## --grass adds the grass blades on the nine chunks round the camera; --grade the film
## grade (Grade.lut); --lods builds farther chunks coarser, as the game streams them
## (ChunkStreamer.lod_for), instead of every chunk at full detail. Objects, trees, water and the distant land are not drawn.
## The shot goes to user://screenshots/terrain.png unless --out names a file.
func _ready() -> void:
	var out := "user://screenshots/terrain.png"
	var world_seed := 4242
	var at := Vector2.ZERO
	var yaw := 0.0
	var up := 2.0
	var pitch := -8.0
	var r := 3
	var grass := false
	var grade := false
	var lods := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--at="):
			var v := a.substr(5).split(",")
			at = Vector2(float(v[0]), float(v[1]))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--up="):
			up = float(a.substr(5))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a == "--grade":
			grade = true
		elif a == "--grass":
			grass = true
		elif a == "--lods":
			lods = true
		elif a.begins_with("--r="):
			r = int(a.substr(4))
		elif a.begins_with("--seed="):
			world_seed = int(a.substr(7))
	Eras.theme = "human"
	Planets.apply(Planets.get_planet(world_seed, 0, "human"))
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION
	var g := ChunkGenerator.new(world_seed, true)
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.fog_enabled = true
	e.fog_density = 0.0015
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.98
	e.adjustment_contrast = 1.1
	if grade:
		e.adjustment_color_correction = Grade.lut()
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(yaw + 140), 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_dir_g", -sun.global_transform.basis.z)
	var ci := int(floor(at.x / 64.0))
	var cj := int(floor(at.y / 64.0))
	var ground_y := 0.0
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var c := g.generate(ci + di, cj + dj)
			var node := ChunkNode.new()
			add_child(node)
			var lod := ChunkStreamer.lod_for(maxi(absi(di), absi(dj))) if lods else 1
			node.setup(c, ChunkNode.build_terrain_arrays(c, lod), lod, {})
			if grass and absi(di) <= 1 and absi(dj) <= 1:
				node.set_grass(ChunkNode.build_grass_buffers(c, 1.0))
			if di == 0 and dj == 0:
				ground_y = ChunkGenerator.height_at(c, at.x - ci * 64.0, at.y - cj * 64.0)
	var cam := Camera3D.new()
	cam.fov = 75
	cam.far = 2000
	add_child(cam)
	cam.position = Vector3(at.x, ground_y + up, at.y)
	cam.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)
	print("ground ", ground_y)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
