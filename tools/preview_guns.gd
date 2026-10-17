extends SceneTree
## Renders held weapons side by side (as the viewmodel builds them), for judging the gun
## models. Pass item types, or kit paths prefixed with kit: to see raw kit models.
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/preview_guns.gd -- \
##     --out=/abs/path.png pulse_rifle scrap_pistol kit:scifi/AR_4

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://guns.png"
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif not a.begins_with("--"):
			names.append(a)
	var cols := 4
	var rows := int(ceil(names.size() / float(cols)))
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 360 * rows)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.34, 0.37)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 0.5
	vp.add_child(fill)
	var vm: GDScript = load("res://src/player/viewmodel.gd")
	for i in names.size():
		var n: String = names[i]
		var mi := MeshInstance3D.new()
		if n.begins_with("kit:"):
			var sc: Node3D = (load("res://assets/models/%s.gltf" % n.substr(4)) as PackedScene).instantiate()
			sc.rotation.y = PI * 0.5
			mi.add_child(sc)
		else:
			mi.mesh = vm.model(n)
		# Three-quarter view from +X: guns point along -Z, turned a little towards the camera.
		mi.position = Vector3(0, -(i / cols) * 0.5, (i % cols - (cols - 1) * 0.5) * 0.6)
		mi.rotation = Vector3(0.0, 0.55, -0.25)
		vp.add_child(mi)
		var l := Label3D.new()
		l.text = n
		l.font_size = 28
		l.pixel_size = 0.0012
		l.position = mi.position + Vector3(0.3, -0.19, 0)
		l.rotation.y = PI * 0.5
		vp.add_child(l)
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(40, 40)
	back.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.3, 0.32, 0.35)
	back.material_override = bm
	back.rotation.y = PI * 0.5
	back.position.x = -2.0
	vp.add_child(back)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.5 * rows + 0.05
	cam.position = Vector3(3, -(rows - 1) * 0.25 + 0.03, 0)
	cam.rotation.y = PI * 0.5
	vp.add_child(cam)
	cam.current = true
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
