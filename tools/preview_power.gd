extends SceneTree
## Renders the powered pieces (generators, batteries, poles, switches, lamps) one by one on
## a stone floor, with their moving and lit parts posed as PowerNode poses them, and a dusk
## shot of each lamp lit, for checking the models. Run windowed:
##   godot --path . --script res://tools/preview_power.gd -- --out=DIR [--pieces=a,b] [--size=768]
## Without --pieces it renders every piece that has a "power" spec. Wall pieces get a wall
## behind them and ceiling pieces a ceiling over them.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://power"
	var pieces: Array = []
	var size := 768
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--pieces="):
			pieces = Array(a.substr(9).split(","))
		elif a.begins_with("--size="):
			size = a.substr(7).to_int()
	if pieces.is_empty():
		for id in BuildCatalog.PIECES:
			if BuildCatalog.def(id).has("power"):
				pieces.append(id)
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(size, size)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.85
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.6, 0)
	sun.shadow_enabled = true
	get_root().add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(30, 0.1, 30)
	floor_mi.mesh = fm
	floor_mi.material_override = Materials.get_mat("cobble")
	floor_mi.position.y = -0.05
	get_root().add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 35.0
	get_root().add_child(cam)
	cam.make_current()
	for id in pieces:
		var d := BuildCatalog.def(id)
		var s: Dictionary = d.get("power", {})
		var root := Node3D.new()
		get_root().add_child(root)
		var mi := MeshInstance3D.new()
		mi.mesh = BuildCatalog.mesh(id)
		root.add_child(mi)
		var mount := String(d.get("mount", ""))
		var box := mi.mesh.get_aabb()
		if mount == "wall":
			root.position = Vector3(0, 1.6, 0)
			var wall := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(3, 3.2, 0.2)
			wall.mesh = wm
			wall.material_override = Materials.get_mat("plaster")
			wall.position = Vector3(0, 1.6, -0.1)
			get_root().add_child(wall)
			root.set_meta("extra", wall)
		elif mount == "ceiling":
			root.position = Vector3(0, 2.6, 0)
			var ceil_mi := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(3, 0.15, 3)
			ceil_mi.mesh = cm
			ceil_mi.material_override = Materials.get_mat("planks")
			ceil_mi.position = Vector3(0, 2.675, 0)
			get_root().add_child(ceil_mi)
			root.set_meta("extra", ceil_mi)
		if s.get("source", "") == "wind":
			var head := MeshInstance3D.new()
			head.mesh = PowerKit.part("windmill_head")
			head.position = Vector3(0, float(s.get("head", 7.8)), 0)
			root.add_child(head)
			var rotor := MeshInstance3D.new()
			rotor.mesh = PowerKit.part("windmill_rotor")
			rotor.position = Vector3(0, 0.3, 0.86)
			rotor.rotation.z = 0.3
			head.add_child(rotor)
			box = box.merge(AABB(Vector3(-3.3, 4.8, -2.5), Vector3(6.6, 6.6, 4.0)))
		var bl: Dictionary = s.get("blade", {})
		if bl.is_empty() and s.get("role", "") == "switch" and not s.has("logic"):
			bl = {"part": "switch_blade", "pos": Vector3(0, -0.1, 0.07), "on": 0.0}
		if not bl.is_empty():
			var blade := MeshInstance3D.new()
			blade.mesh = PowerKit.part(String(bl["part"]))
			blade.position = bl["pos"]
			blade.rotation.x = float(bl.get("on", 0.0))
			root.add_child(blade)
		var light: Light3D = null
		var bulb_mat: StandardMaterial3D = null
		if s.has("lamp"):
			var l: Dictionary = s["lamp"]
			var bulb := MeshInstance3D.new()
			bulb.mesh = PowerKit.part(String(l.get("part", "bulb")))
			bulb.position = l["pos"]
			bulb_mat = StandardMaterial3D.new()
			bulb_mat.albedo_color = Color(0.92, 0.9, 0.85, 0.55)
			bulb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			bulb_mat.emission_enabled = true
			bulb_mat.emission = l.get("color", Color(1, 0.8, 0.6))
			bulb_mat.emission_energy_multiplier = 0.0
			bulb.material_override = bulb_mat
			root.add_child(bulb)
			if float(l.get("spot", 0.0)) > 0.0:
				var sp := SpotLight3D.new()
				sp.spot_range = float(l["range"])
				sp.spot_angle = float(l["spot"])
				sp.rotation.x = deg_to_rad(float(l.get("aim", 0.0)))
				light = sp
			else:
				var om := OmniLight3D.new()
				om.omni_range = float(l["range"])
				om.omni_attenuation = 1.4
				light = om
			light.light_color = l.get("color", Color(1, 0.8, 0.6))
			light.light_energy = float(l["energy"])
			light.shadow_enabled = true
			light.position = l.get("light_at", l["pos"])
			light.visible = false
			root.add_child(light)
		var c := root.position + box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
		# Look at its front: free pieces face -z, wall pieces +z.
		var view := Vector3(0.45, 0.35, -1.0) if mount == "" else Vector3(0.5, 0.25, 1.0)
		if mount == "ceiling":
			view = Vector3(0.5, -0.15, 1.0)
		cam.position = c + view.normalized() * maxf(dist, 1.2)
		cam.look_at(c)
		cam.near = 0.02
		sun.light_energy = 1.2
		e.background_energy_multiplier = 1.0
		e.ambient_light_energy = 1.0
		for i in 4:
			await process_frame
		get_root().get_texture().get_image().save_png(out.path_join("%s.png" % id))
		print("saved ", id)
		if light != null:
			# Dusk, lamp lit.
			light.visible = true
			bulb_mat.emission_energy_multiplier = PowerNode.BULB_ENERGY
			sun.light_energy = 0.03
			e.background_energy_multiplier = 0.06
			e.ambient_light_energy = 0.08
			for i in 4:
				await process_frame
			get_root().get_texture().get_image().save_png(out.path_join("%s_lit.png" % id))
			print("saved ", id, " lit")
		if root.has_meta("extra"):
			(root.get_meta("extra") as Node).queue_free()
		root.queue_free()
		await process_frame
	quit()
