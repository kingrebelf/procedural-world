extends SceneTree
## A sheet of held-item models laid on their sides under an open sky, for judging shape
## and material. Run windowed:
##   godot --path . --script res://tools/preview_tools.gd -- --out=/abs/sheet.png [--items=a,b] [--cols=6]
## Without --items it draws every ToolModels model (tools, weapons, lights). "gltf:props/Name" draws a kit model.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "/tmp/sheet.png"
	var items: Array = ToolModels.BUILD.keys()
	var cols := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--items="): items = Array(a.substr(8).split(","))
		elif a.begins_with("--cols="): cols = a.substr(7).to_int()
	var rows := int(ceil(items.size() / float(cols)))
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * 320, rows * 260)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.position = Vector3((cols - 1) * 0.5 * 1.28, -(rows - 1) * 0.5 * 1.04, 5)
	cam.size = rows * 1.04
	for i in items.size():
		var t: String = items[i]
		var m: ArrayMesh = Viewmodel.kit_mesh(t.substr(5), Transform3D.IDENTITY) if t.begins_with("gltf:") else Viewmodel.model(t)
		if t == "gltf:props/Torch_Metal":
			var kk := MeshKit.new(3)
			ToolModels.torch_wad(kk, Transform3D.IDENTITY)
			kk.commit(ToolModels.mat, m)
		if m == null: continue
		var mi := MeshInstance3D.new()
		mi.mesh = m
		var ab := m.get_aabb()
		var s := 0.95 / maxf(ab.size.y, maxf(ab.size.x, ab.size.z))
		# Handle (+Y) lies to the right, a little toward the camera.
		var b := Basis(Vector3.BACK, PI * 0.5 - 0.35) * Basis(Vector3.UP, 0.6)
		if ab.size.y < 1.6 * maxf(ab.size.x, ab.size.z):
			# Squat things (a pot, a box, a lamp) stand upright, seen a little from above.
			b = Basis(Vector3.RIGHT, 0.45) * Basis(Vector3.UP, 0.6)
		mi.basis = b.scaled(Vector3.ONE * s)
		var c := (b.scaled(Vector3.ONE * s)) * ab.get_center()
		mi.position = Vector3((i % cols) * 1.28, -(i / cols) * 1.04, 0) - c
		vp.add_child(mi)
		var l := Label3D.new()
		l.text = t
		l.pixel_size = 0.0016
		l.position = Vector3((i % cols) * 1.28, -(i / cols) * 1.04 - 0.46, 0.5)
		vp.add_child(l)
	for f in 8:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
