extends SceneTree
## Frame strips of flames and cloth moving, for judging their motion (FireFx, ClothFx):
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_fire_cloth.gd -- \
##     --out=/abs/strip.png [--scene=fire|cloth|flag] [--wind=0.6] [--frames=6] [--dt=0.12] [--pops]
## fire: a campfire, a wall torch, a hanging lantern and a candle at night, with their light.
## cloth: two market stalls and a hanging banner by day. flag: a watchtower's flag up close.
## Each frame is dt seconds of the fires' and the wind's clocks after the one before; the
## strip reads left to right, top to bottom.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://fire_cloth.png"
	var scene := "fire"
	var wind := 0.6
	var frames := 6
	var dt := 0.12
	# --cam=px,py,pz,tx,ty,tz: look from p at t instead of the scene's own view.
	var cam_at := PackedFloat64Array()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--scene="):
			scene = a.substr(8)
		elif a.begins_with("--wind="):
			wind = float(a.substr(7))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--dt="):
			dt = float(a.substr(5))
		elif a.begins_with("--cam="):
			cam_at = a.substr(6).split_floats(",")
	# This strip runs the clocks itself, a fixed step per frame however slow the renderer.
	var clock := root.get_node_or_null("FireClock")
	if clock != null:
		clock.process_mode = Node.PROCESS_MODE_DISABLED
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 600)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var night := scene == "fire"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if night:
		sm.sky_top_color = Color(0.01, 0.015, 0.03)
		sm.sky_horizon_color = Color(0.03, 0.035, 0.05)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.01)
		sm.ground_horizon_color = Color(0.03, 0.03, 0.04)
		sm.sky_energy_multiplier = 0.4
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.15 if night else 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.ssao_enabled = true
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(150), 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.03 if night else 1.2
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.3, 0.26)
	ground.material_override = gm
	vp.add_child(ground)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(1, 0.25).normalized())
	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	match scene:
		"fire":
			var cf := MeshInstance3D.new()
			cf.mesh = BuildCatalog.mesh("campfire")
			cf.position = Vector3(-1.2, 0, 0)
			vp.add_child(cf)
			var fire := FireFx.flame(0.95)
			fire.add_child(FireFx.embers(0.95))
			fire.position = cf.position
			vp.add_child(fire)
			_light(vp, cf.position + Vector3(0, 1.0, 0), 1.6, 9.0)
			# A wall torch and a lantern on a post, a candle on a crate.
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.25, 2.2, 0.25)
			post.mesh = bm
			post.position = Vector3(1.0, 1.1, -0.6)
			vp.add_child(post)
			var props := BuildCatalog.merge_models([["props/Torch_Metal", 0, Vector3(1.0, 1.6, -0.47), 1.0],
				["props/Lantern_Wall", 90, Vector3(1.13, 0.5, -0.6), 1.0], ["props/Crate_Wooden", 0, Vector3(0.2, 0, 0.8), 1.0],
				["props/Candle_1", 0, Vector3(0.2, 0.7, 0.8), 1.0]])
			var pmi := MeshInstance3D.new()
			pmi.mesh = props
			vp.add_child(pmi)
			for f in FireFx.prop_flames([["props/Torch_Metal", 0, Vector3(1.0, 1.6, -0.47), 1.0],
					["props/Lantern_Wall", 90, Vector3(1.13, 0.5, -0.6), 1.0], ["props/Candle_1", 0, Vector3(0.2, 0.7, 0.8), 1.0]]):
				vp.add_child(FireFx.prop_flame(f))
				_light(vp, (f[0] as Vector3) + Vector3(0, 0.1, 0), 1.2 if f[1] > 0.2 else 0.5, 6.0 if f[1] > 0.2 else 3.0)
			cam.position = Vector3(0.0, 1.5, 4.2)
			cam.look_at(Vector3(0.0, 0.8, 0.0))
		"cloth":
			var stalls := MeshInstance3D.new()
			stalls.mesh = ObjectLibrary.get_mesh("market_stall")
			vp.add_child(stalls)
			var s2 := MeshInstance3D.new()
			s2.mesh = ObjectLibrary.get_mesh("fruit_cart")
			s2.position = Vector3(3.6, 0, 0.6)
			s2.rotation.y = -0.3
			vp.add_child(s2)
			var wall := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 4.0, 2.0)
			wall.mesh = bm
			wall.position = Vector3(-2.6, 2.0, 0)
			vp.add_child(wall)
			var bn := MeshInstance3D.new()
			bn.mesh = BuildCatalog.merge_models([["props/Banner_1", 0, Vector3(-2.45, 3.0, 0), 1.0]])
			vp.add_child(bn)
			cam.position = Vector3(0.4, 2.2, 6.5)
			cam.look_at(Vector3(0.4, 1.6, 0))
		"flag":
			var t := MeshInstance3D.new()
			t.mesh = Interiors.build("watchtower")
			vp.add_child(t)
			cam.position = Vector3(3.5, 15.6, 5.0)
			cam.look_at(Vector3(0.4, 15.6, 0))
	if cam_at.size() == 6:
		cam.position = Vector3(cam_at[0], cam_at[1], cam_at[2])
		cam.look_at(Vector3(cam_at[3], cam_at[4], cam_at[5]))
	# Let shaders compile and the sparks get going.
	for i in 30:
		FireFx.tick(1.0 / 30.0)
		RenderingServer.global_shader_parameter_set("wind_time", i / 30.0)
		await process_frame
	# Every fire pops a log as the strip starts, to see the sparks thrown.
	if OS.get_cmdline_user_args().has("--pops"):
		for p in vp.find_children("Pops", "", true, false):
			p.pop()
	var shots: Array = []
	var wt := 1.0
	for f in frames:
		FireFx.tick(dt)
		wt += dt * (1.0 + wind * 1.3)
		RenderingServer.global_shader_parameter_set("wind_time", wt)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		shots.append(vp.get_texture().get_image())
	var cols := mini(frames, 3)
	var rows := int(ceil(frames / float(cols)))
	var w := vp.size.x
	var h := vp.size.y
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	print("saved ", out)
	quit()

func _light(vp: Node, at: Vector3, energy: float, reach: float) -> void:
	var l := FlickerLight.new()
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = true
	l.position = at
	vp.add_child(l)
