extends SceneTree
## Renders the kit animals with their living skins (AnimalSkin): each kind twice, so two
## animals' own markings show side by side, plus a close look at fur and muscle:
##   godot --path . --script res://tools/preview_skins.gd -- --out=<dir> [--kinds=Deer,Cow] [--flat]
## --flat draws the kit's original flat-coloured meshes instead, for a before shot.
## --birds renders the birds' plumage instead. --bench=N times N walking animals, flat
## and with skins, and prints the frame times (vsync off; best on a real GPU).

const FRAME := Vector2i(1600, 900)

func _initialize() -> void:
	var out := "user://skins"
	var kinds := ["Deer", "Horse", "Cow", "Wolf", "Fox", "Boar"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--kinds="):
			kinds = Array(a.substr(8).split(","))
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = FRAME
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.54, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.4, 0.26)
	ground.material_override = gm
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 32
	vp.add_child(cam)
	await process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench="):
			await _bench(vp, cam, int(a.substr(8)), kinds)
			quit()
			return
	var flat := "--flat" in OS.get_cmdline_user_args()
	if "--birds" in OS.get_cmdline_user_args():
		kinds = []
		var bx := 0.0
		for bn in ["Crow", "Kestrel", "Swallow", "Finch"]:
			var bp := {"name": bn, "col": Color(0.55, 0.42, 0.3), "col2": Color(0.75, 0.66, 0.52), "glow": 0, "has_glow": false}
			var bm := BirdModel.build(bp, Eras.MEDIEVAL)
			var holder := Node3D.new()
			vp.add_child(holder)
			holder.position = Vector3(bx, 1.0, 0)
			holder.rotation.y = PI * 0.5 + 0.5
			holder.scale = Vector3.ONE * 2.0
			var body := MeshInstance3D.new()
			body.mesh = bm["body"]
			holder.add_child(body)
			for side in [-1.0, 1.0]:
				var at: Vector3 = bm["wing_at"]
				var wmi := MeshInstance3D.new()
				wmi.mesh = bm["wing"]
				wmi.position = Vector3(side * at.x, at.y, at.z)
				wmi.scale = Vector3(side, 1, 1)
				wmi.rotation.z = side * 0.35
				holder.add_child(wmi)
			bx += 1.3
		cam.look_at_from_position(Vector3(bx * 0.5 - 0.8, 3.4, 2.2), Vector3(bx * 0.5 - 0.8, 1.0, 0))
		for f in 12:
			await process_frame
		vp.get_texture().get_image().save_png(out + "/birds.png")
		print("saved ", out + "/birds.png")
		quit()
		return
	var x := 0.0
	var spots := []
	for k in kinds:
		var w := float(AnimalModel.HEIGHT.get(k, 1.0)) * 0.9
		for i in 2:
			var a := Node3D.new()
			if flat:
				var sc: Node3D = (load(AnimalModel.path_of(k)) as PackedScene).instantiate()
				sc.scale = Vector3.ONE * float(AnimalModel.HEIGHT.get(k, 1.0)) / 4.3
				a.add_child(sc)
			else:
				var am := AnimalModel.new()
				vp.add_child(am)
				am.build(k, 1.0, null, null, 1000 + i * 7919 + int(x * 13.0))
				am.lod = false
				a = am
			if a.get_parent() == null:
				vp.add_child(a)
			a.position = Vector3(x + i * w * 0.9, 0, -i * w * 0.6)
			a.rotation.y = PI * 0.5 + 0.3
			spots.append(a.position)
		x += w * 2.2
	var first: Vector3 = spots[0]
	var last: Vector3 = spots[-1]
	var mid := (first + last) * 0.5
	var width: float = last.x - first.x + 3.0
	# The second close-up looks at the third animal, or the last if there are fewer.
	var third: Vector3 = spots[mini(2, spots.size() - 1)]
	for shot in [["row", mid + Vector3(0, width * 0.16, width * 1.25), mid + Vector3(0, 0.6, 0)],
			["close", spots[0] + Vector3(-1.2, 1.2, 2.6), spots[0] + Vector3(0.2, 0.9, 0)],
			["close2", third + Vector3(1.0, 1.4, 3.0), third + Vector3(0, 1.0, 0)]]:
		cam.position = shot[1]
		cam.look_at(shot[2])
		for f in 12:
			await process_frame
		var path: String = out + "/skins_%s%s.png" % [shot[0], "_flat" if flat else ""]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()

func _bench(vp: SubViewport, cam: Camera3D, n: int, kinds: Array) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	vp.size = Vector2i(1920, 1080)
	var side := ceili(sqrt(float(n)))
	cam.look_at_from_position(Vector3(side * 1.25, 9.0, side * 3.2), Vector3(side * 1.25, 0.5, side * 1.0))
	for skinned in [false, true]:
		AnimalSkin.enabled = skinned
		var all := []
		for i in n:
			var a := AnimalModel.new()
			vp.add_child(a)
			a.build(kinds[i % kinds.size()], 1.0, null, null, i * 31)
			a.position = Vector3((i % side) * 2.5, 0, (i / side) * 2.0)
			a.rotation.y = 0.3 * i
			a.play("Walk")
			all.append(a)
		for f in 90:
			await process_frame
		var t := Time.get_ticks_usec()
		for f in 300:
			await process_frame
		var ms := (Time.get_ticks_usec() - t) / 300000.0
		print("bench %s: %d animals, %.2f ms a frame (%.0f fps)" % ["skinned" if skinned else "flat", n, ms, 1000.0 / ms])
		for a in all:
			a.free()
