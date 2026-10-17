extends SceneTree
## Renders close-ups of item models (ItemModels) one by one under a daylight sky, and a
## contact sheet of them all, for judging whether each reads as the real thing. Run windowed:
##   godot --path . --script res://tools/preview_items.gd -- --out=DIR [--items=a,b] [--size=512]
## With no --items, every item ItemModels has is shown; "b:<id>" shows a build piece.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://items"
	var items: Array = ItemModels.SHAPES.keys()
	var size := 512
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a.begins_with("--size="):
			size = a.substr(7).to_int()
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(size, size)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.8)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.85)
	sm.ground_bottom_color = Color(0.25, 0.22, 0.18)
	sm.ground_horizon_color = Color(0.55, 0.52, 0.48)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.44, 0.47)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.7, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	get_root().add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	get_root().add_child(cam)
	cam.make_current()
	var holder := Node3D.new()
	get_root().add_child(holder)
	var shots: Array[Image] = []
	for t in items:
		for c in holder.get_children():
			c.queue_free()
		# "b:<id>" shows a build piece (BuildCatalog) instead.
		var mesh: Mesh = BuildCatalog.mesh(t.substr(2)) if t.begins_with("b:") else ItemModels.model(t)
		if mesh == null:
			push_warning("no model for " + t)
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		holder.add_child(mi)
		var box := mesh.get_aabb()
		var ctr := box.get_center()
		var rad := box.size.length() * 0.5
		var dist := rad / tan(deg_to_rad(cam.fov * 0.5)) * 1.1
		var dir := Vector3(0.55, 0.35, 1.0).normalized()
		cam.position = ctr + dir * dist
		cam.look_at(ctr)
		cam.near = dist * 0.05
		for i in 6:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out.path_join("%s.png" % t))
		shots.append(img)
		print("item ", t)
	# Contact sheet: 6 across, each at a quarter of the shot size.
	var cell := size / 2
	var cols := 6
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(cell * cols, cell * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s := shots[i]
		s.convert(Image.FORMAT_RGBA8)
		s.resize(cell, cell)
		sheet.blit_rect(s, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
	sheet.save_png(out.path_join("_sheet.png"))
	quit()
