extends SceneTree
## Renders the sci-fi rooms (KitBase shell + Interiors.interior + its lights) from the
## doorway looking in and from the back looking out, for checking their fit-out:
##   godot --path . --script res://tools/preview_interiors.gd -- --out=<dir> [--types=hab_block,lab_block] [--size=1280x720]

const TYPES := ["hab_block", "lab_block", "ops_tower", "bunker_keep", "bunker_tower"]

func _initialize() -> void:
	var out := "user://interiors"
	var types: Array = TYPES
	var size := Vector2i(1280, 720)
	Eras.theme = "human"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--types="):
			types = Array(a.substr(8).split(","))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.32, 0.34, 0.37)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 80
	vp.add_child(cam)
	await process_frame
	for t: String in types:
		var room := Node3D.new()
		vp.add_child(room)
		for m in [KitBase.build(Interiors._kit_of(t)), Interiors.interior(t)]:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			room.add_child(mi)
		for l in Interiors.lights(t):
			var o := OmniLight3D.new()
			o.position = l[0]
			o.light_color = l[1]
			o.light_energy = l[2]
			o.omni_range = l[3]
			o.shadow_enabled = true
			room.add_child(o)
		var ih: Vector2 = Interiors.BOX[t][0]
		var door: Array = Interiors.BOX[t][5]
		for shot in [["in", Vector3(float(door[0]) * 0.5, 1.7, ih.y - 0.4), Vector3(-ih.x * 0.3, 1.2, -ih.y)],
				["out", Vector3(0.0, 1.7, -ih.y + 1.4), Vector3(float(door[0]), 1.4, ih.y)]]:
			cam.look_at_from_position(shot[1], shot[2])
			for f in 20:
				await process_frame
			var path: String = out + "/interior_%s_%s.png" % [t, shot[0]]
			vp.get_texture().get_image().save_png(path)
			print("saved ", path)
		room.queue_free()
		await process_frame
	quit()
