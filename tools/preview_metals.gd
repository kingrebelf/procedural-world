extends SceneTree
## Every shared metal (Metals.KINDS) as a ball and a bevelled bar on a ground plane under
## the game's own sky, plus metal items, for judging whether metal reads as metal. Run
## windowed (Forward+, for SDFGI and screen-space reflections):
##   godot --path . --script res://tools/preview_metals.gd -- --out=DIR [--size=1280x720]
##     [--items=iron_ingot,gold_ingot,b:anvil] [--day=0.42] [--ssr=1] [--sdfgi=1]
## Writes metals.png (the line-up) and items.png.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://metals"
	var size := Vector2i(1280, 720)
	var items: Array = ["iron_ingot", "steel_ingot", "copper_ingot", "bronze_ingot", "silver_ingot", "gold_ingot"]
	var sun_elev := 0.6
	var ssr := true
	var sdfgi := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(p[0].to_int(), p[1].to_int())
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a.begins_with("--sun="):
			sun_elev = a.substr(6).to_float()
		elif a.begins_with("--ssr="):
			ssr = a.substr(6) == "1"
		elif a.begins_with("--sdfgi="):
			sdfgi = a.substr(8) == "1"
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/env/sky.gdshader")
	sm.set_shader_parameter("volumetric_clouds", false)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 8.0
	e.ssr_enabled = ssr
	e.ssr_max_steps = 48
	e.sdfgi_enabled = sdfgi
	e.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = e
	get_root().add_child(we)
	var sun := DirectionalLight3D.new()
	# From behind the camera's left shoulder.
	sun.rotation = Vector3(-sun_elev, -0.7, 0)
	sun.light_energy = 2.0
	sun.light_angular_distance = 0.5
	sun.shadow_enabled = true
	get_root().add_child(sun)
	# Grass-and-earth ground, so reflections have a lower half.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := Materials.get_mat("stone") as StandardMaterial3D
	ground.material_override = gm
	get_root().add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40.0
	get_root().add_child(cam)
	cam.make_current()
	var kinds: Array = Metals.KINDS.keys()
	var row := Node3D.new()
	get_root().add_child(row)
	for i in kinds.size():
		# Two rows of eight.
		var per := 8
		var x := (i % per - (per - 1) * 0.5) * 0.62
		var z := -float(i / per) * 1.1
		var k := MeshKit.new(7)
		var col := Color(0.25, 0.4, 0.62) if kinds[i] == "painted" else (Color(0.46, 0.45, 0.44) if kinds[i].begins_with("worked") else Color.WHITE)
		k.sphere("m", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), 0.22, 16, 24, 0.0, 1.0, col)
		k.cylinder("m", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.07, 0.48)), 0.07, 0.07, 0.4, 20, true, 0.0, 1, col)
		var mi := MeshInstance3D.new()
		var mat := Metals.mat(kinds[i], -1.0, false)
		mi.mesh = k.commit(func(_n: String) -> Material: return mat)
		mi.position = Vector3(x, 0, z)
		row.add_child(mi)
	cam.position = Vector3(0, 1.6, 4.4)
	cam.look_at(Vector3(0, 0.1, -0.4))
	for f in 40:
		await process_frame
	get_root().get_texture().get_image().save_png(out.path_join("metals.png"))
	print("metals ", kinds)
	row.queue_free()
	# Each item framed on its own, then a contact sheet of three across.
	var shots: Array[Image] = []
	for t in items:
		var mesh: Mesh = BuildCatalog.mesh(t.substr(2)) if t.begins_with("b:") else ItemModels.model(t)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		get_root().add_child(mi)
		var box := mesh.get_aabb()
		mi.position = Vector3(0, -box.position.y + 0.002, 0)
		var ctr := box.get_center() + mi.position
		var rad := box.size.length() * 0.5
		var dist := rad / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
		cam.position = ctr + Vector3(0.55, 0.45, 1.0).normalized() * dist
		cam.look_at(ctr)
		cam.near = dist * 0.02
		for f in 30:
			await process_frame
		shots.append(get_root().get_texture().get_image())
		mi.queue_free()
		print("item ", t)
	if not shots.is_empty():
		var cw := size.x / 2
		var ch := size.y / 2
		var sheet := Image.create(cw * 3, ch * int(ceil(shots.size() / 3.0)), false, Image.FORMAT_RGB8)
		for i in shots.size():
			var im := shots[i]
			im.convert(Image.FORMAT_RGB8)
			im.resize(cw, ch)
			sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((i % 3) * cw, (i / 3) * ch))
		sheet.save_png(out.path_join("items.png"))
	quit()
