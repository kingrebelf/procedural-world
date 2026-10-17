extends SceneTree
## Renders the reshaped animals (AnimalModel.VARIANTS) beside the kits they are built
## from, side on and three-quarter, for checking their look:
##   godot --path . --script res://tools/preview_variants.gd -- --out=<dir>

const FRAME := Vector2i(1600, 700)
const ROW := [["Cow", 1.0], ["Boar", 1.0], ["Fox", 1.0], ["Hare", 1.0]]

func _initialize() -> void:
	var out := "user://variants"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = FRAME
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.44, 0.3)
	ground.material_override = gm
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	var xs := [-2.7, -0.9, 0.9, 2.1]
	for i in ROW.size():
		var a := AnimalModel.new()
		vp.add_child(a)
		a.build(ROW[i][0])
		a.lod = false
		a.position = Vector3(xs[i], 0, 0)
		a.rotation.y = PI * 0.5 + 0.35
	for shot in [["side", Vector3(0, 0.9, 7.5)], ["front", Vector3(3.5, 1.1, 5.5)]]:
		cam.position = shot[1]
		cam.look_at(Vector3(0, 0.45, 0))
		for f in 30:
			await process_frame
		var path: String = out + "/variants_%s.png" % shot[0]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
