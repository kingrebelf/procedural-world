extends SceneTree
## Renders the first-person view of held items against a plain sky, for tuning how big
## and where tools sit on screen. Run windowed:
##   godot --path . --script res://tools/preview_viewmodel.gd -- --out=DIR [--items=a,b] [--night] [--hand]
## --hand: close-ups of the gripping hand from the left and from the right as well.
## --night: a dark evening with a held torch's flickering light, to judge fire and shadow.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://viewmodel"
	var items := ["pickaxe_iron", "axe_iron", "sword_iron", "torch", "pulse_rifle"]
	var night := false
	var hand := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a == "--night":
			night = true
		elif a == "--hand":
			hand = true
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(1600, 900)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
	get_root().add_child(cam)
	cam.make_current()
	var vm := Viewmodel.new()
	vm.look = Player.LOOK
	cam.add_child(vm)
	var hl := HandLight.new()
	cam.add_child(hl)
	for t in items:
		vm.show_item(t)
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
