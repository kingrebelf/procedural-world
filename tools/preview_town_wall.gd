extends SceneTree
## Pictures of a town's curtain wall (Stronghold castle pieces): the four tower builds,
## wall sections and the gate, on flat ground:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_town_wall.gd
## Shots go to user://screenshots/wall_*.png.

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("wall_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _put(key: String, p: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ObjectLibrary.get_mesh(key)
	mi.position = p
	mi.rotation.y = yaw
	root.add_child(mi)

func _run() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.4, 0.22)
	ground.material_override = gm
	root.add_child(ground)
	# A straight run, outer faces toward +z (the camera): tower, walls, gate, walls, ...
	# Towers turn their door inward (yaw PI), as Stronghold.town_wall places them.
	var x := -36.0
	var seq := ["castle_tower~var0", "castle_wall~var0", "castle_wall~var1", "castle_tower~var1", "castle_gate",
		"castle_tower~var2", "castle_wall~var2", "castle_wall~var0", "castle_tower~var3"]
	for key: String in seq:
		var tower := key.begins_with("castle_tower")
		_put(key, Vector3(x + (4.0 if tower else 4.0), 0, 2.0 if tower else 0.0), PI if tower else 0.0)
		x += 8.0
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	for s in [["run", Vector3(0, 9, 42), Vector3(0, 6, 0)], ["gate", Vector3(4, 2.2, 14), Vector3(4, 3.5, 0)],
			["inside", Vector3(4, 2.0, -9), Vector3(4, 2.5, 0)], ["towers", Vector3(26, 6, 22), Vector3(28, 9, 0)],
			["left", Vector3(-28, 5, 20), Vector3(-26, 8, 0)]]:
		cam.position = s[1]
		cam.look_at(s[2])
		await _shot(s[0])
	quit()
