extends SceneTree
## Renders food, drink and container models (Provisions) one by one on a wooden table
## under a bright sky, each framed to fill the picture, for checking them against their
## icons. Run windowed:
##   godot --path . --script res://tools/preview_provisions.gd -- --out=DIR [--items=a,b] [--size=512]
## Without --items it renders every item Provisions has a model for. "egg:msg_bottle" as
## an item renders that Easter egg (EasterEggs.build) instead.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://provisions"
	var items: Array = []
	var size := 512
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a.begins_with("--size="):
			size = a.substr(7).to_int()
	if items.is_empty():
		for t in ItemDB.ITEMS:
			if Provisions.has(t):
				items.append(t)
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(size, size)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.5, 0.75)
	sm.sky_horizon_color = Color(0.75, 0.8, 0.85)
	sm.ground_bottom_color = Color(0.25, 0.2, 0.16)
	sm.ground_horizon_color = Color(0.55, 0.5, 0.45)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.8
	e.ssao_enabled = true
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.7, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	get_root().add_child(sun)
	var table := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 0.05, 3)
	table.mesh = bm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.3, 0.22, 0.15)
	tm.roughness = 0.8
	table.material_override = tm
	get_root().add_child(table)
	var cam := Camera3D.new()
	cam.fov = 30.0
	get_root().add_child(cam)
	cam.make_current()
	var holder := MeshInstance3D.new()
	get_root().add_child(holder)
	for t in items:
		var m: ArrayMesh = EasterEggs.build(t.substr(4)) if t.begins_with("egg:") else Provisions.model(t)
		if m == null:
			print("no model: ", t)
			continue
		holder.mesh = m
		var box := m.get_aabb()
		# Stand it on the table.
		holder.position = Vector3(0, 0.025 - box.position.y, 0)
		var c := holder.position + box.get_center()
		var r := box.size.length() * 0.5
		if t == "egg:msg_bottle":
			# Close on the bottle, not the shells round it.
			c = holder.position + Vector3(0.13, 0.03, -0.05)
			r = 0.22
		var d := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.02
		cam.position = c + Vector3(0.35, 0.45, 1.0).normalized() * d
		if t.begins_with("egg:"):
			cam.position = c + Vector3(-0.3, 0.6, 1.0).normalized() * d
		cam.look_at(c)
		cam.near = 0.01
		for i in 4:
			await process_frame
		get_root().get_texture().get_image().save_png(out.path_join("%s.png" % t.replace(":", "_")))
		print("saved ", t)
	quit()
