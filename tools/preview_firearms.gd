extends SceneTree
## Renders held ranged weapons one per cell, each scaled to fill its cell and labelled
## with its real length, for judging the gun models up close. Side view from the right
## (muzzle to the right) unless --quarter turns them three-quarters on.
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/preview_firearms.gd -- \
##     --out=/abs/path.png [--cols=3] [--quarter] musket revolver_six laser_pistol

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://firearms.png"
	var cols := 3
	var quarter := false
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a == "--quarter":
			quarter = true
		elif not a.begins_with("--"):
			names.append(a)
	cols = mini(cols, maxi(1, names.size()))
	var rows := int(ceil(names.size() / float(cols)))
	var cell := Vector2i(640, 360)
	var vp := SubViewport.new()
	vp.size = Vector2i(cell.x * cols, cell.y * rows)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# An open sky for the metals to reflect, as they do outdoors in the game.
	var sky := Sky.new()
	var skm := ProceduralSkyMaterial.new()
	skm.sky_top_color = Color(0.32, 0.45, 0.66)
	skm.sky_horizon_color = Color(0.7, 0.72, 0.74)
	skm.ground_bottom_color = Color(0.16, 0.14, 0.12)
	skm.ground_horizon_color = Color(0.45, 0.43, 0.4)
	sky.sky_material = skm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 55, 0)
	sun.light_energy = 1.5
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -130, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(60, 60)
	back.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.3, 0.32, 0.35)
	back.material_override = bm
	back.position.z = -3.0
	vp.add_child(back)
	var vm: GDScript = load("res://src/player/viewmodel.gd")
	# Each cell is 1.6 x 0.9 units; the gun is scaled so its longest side fills 85%.
	for i in names.size():
		var n: String = names[i]
		var mesh: ArrayMesh = vm.model(n)
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var len := maxf(box.size.z, maxf(box.size.y * 1.7, box.size.x))
		var s := 1.36 / len
		var c := Vector3((i % cols) * 1.6, -(i / cols) * 0.9, 0)
		var holder := Node3D.new()
		holder.position = c
		holder.rotation = Vector3(0.0, -PI * 0.5 + (0.6 if quarter else 0.0), 0.0)
		holder.scale = Vector3.ONE * s
		vp.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = -box.get_center()
		holder.add_child(mi)
		# The grip point, as a small marker.
		if mesh.has_meta("grip"):
			var dot := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.006 / s * 1.0
			sm.height = sm.radius * 2.0
			dot.mesh = sm
			var dm := StandardMaterial3D.new()
			dm.albedo_color = Color(1, 0.2, 0.6)
			dm.no_depth_test = true
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dot.material_override = dm
			dot.position = mi.position + Vector3(mesh.get_meta("grip"))
			holder.add_child(dot)
		var l := Label3D.new()
		l.text = "%s  %.2f m" % [n, box.size.z]
		l.font_size = 30
		l.pixel_size = 0.0014
		l.position = c + Vector3(0, -0.4, 0.2)
		vp.add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.9 * rows
	cam.position = Vector3((cols - 1) * 0.8, -(rows - 1) * 0.45, 5)
	vp.add_child(cam)
	cam.current = true
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
