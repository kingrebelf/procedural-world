extends SceneTree
## Renders village cottages, boulders and oaks weathered by four climates side by side
## (ClimateWear): temperate, wet (moss), cold at dawn (snow and hoar frost), dry (dust),
## then the wet cottage up close and from inside (which must stay clean):
##   godot --path . --script res://tools/preview_wear.gd -- --out=<dir> [--day=0.27]

const FRAME := Vector2i(1920, 900)
const GAP := 40.0
## Each climate's levels (moss, cold, dust, bog), one map texel per cottage.
const CLIMATES := [["temperate", Color(0.45, 0.0, 0.0, 0.0)], ["wet", Color(1.0, 0.0, 0.0, 0.6)],
	["cold", Color(0.3, 0.95, 0.0, 0.0)], ["dry", Color(0.0, 0.0, 1.0, 0.0)]]

func _initialize() -> void:
	var out := "user://wear"
	var day := 0.27
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--day="):
			day = a.substr(6).to_float()
	DirAccess.make_dir_recursive_absolute(out)
	BuildCatalog.warm_kits()
	RenderingServer.global_shader_parameter_set("snow_line_g", 400.0)
	RenderingServer.global_shader_parameter_set("sun_dir_g", Vector3(0.4, 0.6, 0.3).normalized())
	# The map: a texel per cottage along x, the same down z.
	var n := CLIMATES.size()
	var img := Image.create(n, 4, false, Image.FORMAT_RGBA8)
	for i in n:
		for j in 4:
			img.set_pixel(i, j, CLIMATES[i][1])
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("climate_wear_map_g", tex)
	RenderingServer.global_shader_parameter_set("climate_wear_rect_g", Vector4(-GAP * 0.5, -GAP * 2.0, GAP * n, 0.0))
	RenderingServer.global_shader_parameter_set("climate_wear_now_g", Vector4(ClimateWear.frost_now(day), day, 0.0, 0.0))
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
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.38, 0.24)
	ground.material_override = gm
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 50
	cam.far = 600.0
	vp.add_child(cam)
	var shelter := ShelterMap.new()
	vp.add_child(shelter)
	var oak := 0
	for sp in range(1, 3000):
		if String(Flora.species("oak", sp).get("form", "")) == "round":
			oak = sp
			break
	for i in n:
		var x := i * GAP
		var house := MultiMeshInstance3D.new()
		house.multimesh = _one(KitHouse.build("cottage"), Transform3D(Basis(), Vector3(x, 0, 0)), Color(1, 1, 1, 1))
		vp.add_child(house)
		var rock := MultiMeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 24
		sm.rings = 12
		sm.material = StoneKit.material()
		rock.multimesh = _one(sm, Transform3D(Basis().scaled(Vector3(2.6, 1.6, 2.2)), Vector3(x + 9.0, 0.4, 6.0)), Color(0.55, 0.53, 0.5, 0.7))
		vp.add_child(rock)
		if oak > 0:
			var tree := MultiMeshInstance3D.new()
			tree.multimesh = _one(RealTree.build("oak", oak, 0), Transform3D(Basis(), Vector3(x - 10.0, 0, 7.0)), Color(1, 1, 1, 1))
			vp.add_child(tree)
		print("%s at x %.0f" % [CLIMATES[i][0], x])
	var mid := (n - 1) * GAP * 0.5
	var shots := [["row", Vector3(mid, 10.0, 78.0), Vector3(mid, 3.0, 0.0)]]
	for i in n:
		shots.append([CLIMATES[i][0], Vector3(i * GAP + 7.0, 3.0, 15.0), Vector3(i * GAP, 2.2, 0.0)])
	shots.append(["wet_inside", Vector3(GAP + 0.5, 1.7, 0.8), Vector3(GAP - 2.5, 0.8, -2.5)])
	await process_frame
	for shot in shots:
		cam.look_at_from_position(shot[1], shot[2])
		for f in 30:
			await process_frame
		var path: String = out + "/wear_%s.png" % shot[0]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()

func _one(mesh: Mesh, xf: Transform3D, c: Color) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, c)
	return mm
