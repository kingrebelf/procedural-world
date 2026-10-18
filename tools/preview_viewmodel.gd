extends SceneTree
## Renders the first-person view of held items against a plain sky, for tuning how big
## and where tools sit on screen. Run windowed:
##   godot --path . --script res://tools/preview_viewmodel.gd -- --out=DIR [--items=a,b] [--night] [--hand]
## --hand: close-ups of the gripping hand from the left and from the right as well.
## --night: a dark evening with a held torch's flickering light, to judge fire and shadow.
##   [--raise=0.5] (binoculars part way up to the eyes) [--wear=mail_iron,gloves_leather]
##   ("none" as an item shows the empty hands)
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://viewmodel"
	var items := ["pickaxe_iron", "axe_iron", "sword_iron", "torch", "pulse_rifle"]
	var raise := 0.0
	var wear := {}
	var night := false
	var hand := false
	var hfov := 0.0 ## --hfov=90: the camera as the game sets it (horizontal FOV), not the fixed 80° vertical
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a.begins_with("--wear="):
			for w in a.substr(7).split(","):
				wear[ItemDB.def(w)["slot"]] = ItemDB.make(w, 1, 1.0, {})
		elif a.begins_with("--raise="):
			raise = a.substr(8).to_float()
		elif a == "--night":
			night = true
		elif a == "--hand":
			hand = true
		elif a.begins_with("--hfov="):
			hfov = a.substr(7).to_float()
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(1600, 900)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Metal shows what it reflects: a daylight sky (with a darker ground below), as in game.
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.8)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.85)
	sm.ground_horizon_color = Color(0.55, 0.55, 0.5)
	sm.ground_bottom_color = Color(0.3, 0.28, 0.22)
	if night:
		sm.sky_energy_multiplier = 0.05
		sm.ground_energy_multiplier = 0.05
	sky.sky_material = sm
	env.environment.sky = sky
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	get_root().add_child(sun)
	if night:
		env.environment.background_color = Color(0.03, 0.04, 0.08)
		env.environment.ambient_light_color = Color(0.08, 0.09, 0.14)
		sun.light_energy = 0.05
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.position.y = -1.63
	get_root().add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 80.0
	if hfov > 0.0:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = hfov
	get_root().add_child(cam)
	cam.make_current()
	var vm := Viewmodel.new()
	# Player.LOOK, copied: naming Player would compile player.gd, which needs the Net and
	# Game autoloads that a --script run doesn't load.
	vm.look = {"female": false, "hair": Color(0.22, 0.14, 0.08), "hair_style": 1, "skin": Color(0.86, 0.66, 0.52),
		"cloth": Color(0.36, 0.42, 0.3), "cloth2": Color(0.28, 0.23, 0.18), "height": 1.0, "build": 0.5}
	cam.add_child(vm)
	if vm.arms and not wear.is_empty():
		vm.arms.wear(wear)
	var hl := HandLight.new()
	cam.add_child(hl)
	for t in items:
		vm.show_item("" if t == "none" else t)
		vm.raise = raise
		if night:
			hl.held = "torch" if t == "torch" else ""
			hl.kind = "" if t == "torch" else "torch"
			hl._apply()
		for i in (90 if night else 30):
			vm.sway(1.0 / 60.0, 0.0)
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out.path_join("%s.png" % t))
		if hand and vm.arms:
			var sk := vm.arms.skeleton
			var at: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))).origin
			var close := Camera3D.new()
			close.fov = 40.0
			get_root().add_child(close)
			for side in [["left", Vector3(-0.45, 0.12, 0.05)], ["right", Vector3(0.4, -0.05, 0.15)]]:
				close.position = at + side[1]
				close.look_at(at)
				close.make_current()
				await process_frame
				await process_frame
				get_root().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [t, side[0]]))
			close.queue_free()
			cam.make_current()
		print("saved ", t)
	quit()
