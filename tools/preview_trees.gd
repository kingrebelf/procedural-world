extends SceneTree
## Renders a row of trees (RealTree) side by side for checking their look: by default one
## of each palm (coconut, royal, date, palmetto, banana) and of each tropical broadleaf
## (acacia, fig, kapok), with an oak for scale, from the side and from under the crowns:
##   godot --path . --script res://tools/preview_trees.gd -- --out=<dir> [--types=palm,tropic,oak] [--far]
## --far draws each tree's merged far version instead.

const FRAME := Vector2i(1920, 900)

func _initialize() -> void:
	var out := "user://trees"
	var types := ["palm", "tropic", "oak"]
	var far := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--types="):
			types = Array(a.substr(8).split(","))
		elif a == "--far":
			far = true
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(1, 0.3).normalized())
	RenderingServer.global_shader_parameter_set("wind_strength", 0.3)
	var vp := SubViewport.new()
	vp.size = FRAME
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.5, 0.36)
	ground.material_override = gm
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.far = 600.0
	vp.add_child(cam)
	# One species of each form, in order.
	var row: Array = []
	for t in types:
		var seen := {}
		for sp in range(1, 3000):
			var p := Flora.species(t, sp)
			var form := String(p.get("form", ""))
			if seen.has(form) or form in ["dead", "snag", "shrub", "column", "weeping"]:
				continue
			if t == "oak" and (form != "round" or bool(p.get("autumn", false))):
				continue
			seen[form] = true
			row.append([t, sp, form, float(p["height"])])
	var x := 0.0
	var gap := 3.0
	var spots: Array = []
	for e in row:
		var w: float = clampf(float(e[3]) * 0.55, 3.0, 9.0)
		x += w * 0.5
		var mi := MeshInstance3D.new()
		if far:
			var parts := RealTree.far_parts(e[0], e[1], 0)
			var m := ArrayMesh.new()
			for part in ["bark", "leaf"]:
				var a: Array = parts[part]
				if (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
					continue
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
				var look: Array = parts["look"]
				m.surface_set_material(m.get_surface_count() - 1, RealTree.bark_material(look[1], true) if part == "bark" else RealTree.leaf_material(look[0], true))
			mi.mesh = m
		else:
			mi.mesh = RealTree.build(e[0], e[1], 0)
		mi.position = Vector3(x, 0, 0)
		mi.rotation.y = 0.6
		vp.add_child(mi)
		spots.append(x)
		print("%-7s %-9s sp %4d  %.1f m at x %.1f" % [e[0], e[2], e[1], e[3], x])
		x += w * 0.5 + gap
	var mid := x * 0.5
	var shots := [["side", Vector3(mid, 7.0, x * 0.95), Vector3(mid, 7.0, 0)],
		["crowns", Vector3(mid * 0.5, 2.0, 16.0), Vector3(mid * 0.5, 9.0, 0)]]
	for shot in shots:
		await process_frame
		cam.position = shot[1]
		cam.look_at(shot[2])
		for f in 40:
			await process_frame
		var path: String = out + "/trees_%s%s.png" % [shot[0], "_far" if far else ""]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
