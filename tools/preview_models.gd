extends SceneTree
## Renders kit models side by side on a grass plane, for judging how they look in-game.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_models.gd -- \
##     --out=/abs/path.png nature/CommonTree_1 nature/Pine_1 mesh:oak#1234#0 ...
## fire:SIZE is a flame with sparks and smoke; fires:TYPE the flames of a room (with --at0
## and "mesh:TYPE~in"); swirl:SIZE:Y:Z a portal's swirl at height Y, Z ahead;
## stone:KIND a loose ground stone (StoneKit); build:ID is a piece you build, with its fire if it has one;
## --frames=N waits N frames before saving (let sparks and smoke build up).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://preview.png"
	var names: Array = []
	# --at0 stacks every model at the origin (a house with its interior); --cam=px,py,pz,
	# tx,ty,tz places the camera; --omni=x,y,z adds a warm lamp (to see inside rooms).
	var at0 := false
	var cam_at := PackedFloat64Array()
	var omnis: Array = []
	var frames := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--at0":
			at0 = true
		elif a.begins_with("--cam="):
			cam_at = a.substr(6).split_floats(",")
		elif a.begins_with("--omni="):
			var v := a.substr(7).split_floats(",")
			omnis.append(Vector3(v[0], v[1], v[2]))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif not a.begins_with("--"):
			names.append(a)
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 700)
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
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.38, 0.2)
	ground.material_override = gm
	vp.add_child(ground)
	var x := 0.0
	var top := 1.0
	for n0 in names:
		# "name@deg" turns the model about Y (e.g. to see a long bridge side-on).
		var n := String(n0).get_slice("@", 0)
		var turn := float(String(n0).get_slice("@", 1)) if String(n0).contains("@") else 0.0
		var node: Node3D
		if String(n).begins_with("mesh:"):
			# A world object mesh by key, e.g. mesh:oak#1234#0 ("%" for the "@" of a key,
			# as in mesh:w_dreadnought%crash%calm).
			var mi := MeshInstance3D.new()
			mi.mesh = ObjectLibrary.get_mesh(String(n).substr(5).replace("%", "@"))
			node = Node3D.new()
			node.add_child(mi)
		elif String(n).begins_with("stone:"):
			# A loose ground stone (StoneKit kind), 1.5 m across.
			var smi := MeshInstance3D.new()
			smi.mesh = StoneKit.mesh(String(n).substr(6))
			smi.scale = Vector3.ONE * 1.5
			node = Node3D.new()
			node.add_child(smi)
		elif String(n).begins_with("fire:"):
			node = FireFx.flame(float(String(n).get_slice(":", 1)))
			node.add_child(FireFx.embers(float(String(n).get_slice(":", 1))))
		elif String(n).begins_with("build:"):
			var id := String(n).substr(6)
			node = Node3D.new()
			var bmi := MeshInstance3D.new()
			bmi.mesh = BuildCatalog.mesh(id)
			node.add_child(bmi)
			if BuildCatalog.def(id).has("fire"):
				var bf := FireFx.flame(float(BuildCatalog.def(id)["fire"]))
				bf.add_child(FireFx.embers(float(BuildCatalog.def(id)["fire"])))
				node.add_child(bf)
		elif String(n).begins_with("fires:"):
			node = Node3D.new()
			for f in Interiors.fires(String(n).substr(6)):
				var fl := FireFx.flame(f[1])
				# Fires are placed in the sunk body's space; the room mesh here is not sunk.
				fl.position = (f[0] as Vector3) + Vector3(0, Interiors.SINK, 0)
				if f[1] >= 0.3:
					fl.add_child(FireFx.embers(f[1], false))
				node.add_child(fl)
		elif String(n).begins_with("swirl:"):
			node = Node3D.new()
			var sw := FireFx.swirl(float(String(n).get_slice(":", 1)))
			sw.position.y = float(String(n).get_slice(":", 2))
			sw.position.z = float(String(n).get_slice(":", 3)) if String(n).get_slice_count(":") > 3 else 0.0
			node.add_child(sw)
		elif String(n).begins_with("bird:"):
			# A procedural flier by species name, wings spread, e.g. bird:Kestrel.
			var bn := String(n).substr(5)
			var era := Eras.MEDIEVAL if bn in ["Crow", "Kestrel", "Swallow"] else (Eras.FANTASY if bn in ["Glowmoth", "Wisp Finch"] else Eras.SCIFI)
			var bm := BirdModel.build({"name": bn, "col": Color(0.35, 0.3, 0.6), "col2": Color(0.6, 0.55, 0.85), "glow": 7, "has_glow": era != Eras.MEDIEVAL}, era)
			node = Node3D.new()
			var body := MeshInstance3D.new()
			body.mesh = bm["body"]
			node.add_child(body)
			var at: Vector3 = bm["wing_at"]
			for side in [-1.0, 1.0]:
				var wmi := MeshInstance3D.new()
				wmi.mesh = bm["wing"]
				wmi.scale = Vector3(side, 1, 1)
				wmi.position = Vector3(side * at.x, at.y, at.z)
				wmi.rotation.z = side * 0.15
				node.add_child(wmi)
			node.scale = Vector3.ONE * 4.0
			# Tipped towards the camera so the wings show from above.
			node.rotation.x = 1.0
		else:
			var ps: PackedScene = load("res://assets/models/%s.gltf" % n)
			if ps == null:
				print("missing ", n)
				continue
			node = ps.instantiate()
		vp.add_child(node)
		node.rotation.y = deg_to_rad(turn)
		var aabb := AABB()
		var first := true
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		if at0:
			continue
		x += aabb.size.x * 0.5 + 0.5
		node.position = Vector3(x - aabb.get_center().x, -aabb.position.y, 0)
		x += aabb.size.x * 0.5 + 0.5
		top = maxf(top, aabb.size.y)
	for o in omnis:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.32)
		l.light_energy = 1.5
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
		l.position = o
		vp.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	if cam_at.size() == 6:
		cam.fov = 70
		cam.position = Vector3(cam_at[0], cam_at[1], cam_at[2])
		cam.look_at(Vector3(cam_at[3], cam_at[4], cam_at[5]))
	else:
		var w := maxf(x, top * 2.3)
		cam.position = Vector3(x * 0.5, top * 0.55 + w * 0.08, w * 1.05)
		cam.look_at(Vector3(x * 0.5, top * 0.4, 0))
	for i in frames:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
