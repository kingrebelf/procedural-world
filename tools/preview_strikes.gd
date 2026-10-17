extends SceneTree
## Renders first-person tool strikes frame by frame, for judging that a swing stops on
## the surface it hits and what the impact throws off. A trunk, a rock top, an ore rock
## and a crystal stand in front of the camera; each item swings at each target and
## frames are saved around the moment it lands. Run windowed, at a fixed frame rate:
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/preview_strikes.gd -- --out=DIR \
##     [--items=axe_iron,pickaxe_iron] [--targets=trunk,rock,ore,crystal] [--dist=0.9]
## Frames: <item>_<target>_<n>.png, n = frames after the swing starts.
const FRAMES := [6, 12, 14, 18, 26]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://strikes"
	var items := ["axe_iron", "pickaxe_iron", "sword_iron"]
	var targets := ["trunk", "rock", "ore", "crystal"]
	var dist := 0.9
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
		elif a.begins_with("--targets="):
			targets = Array(a.substr(10).split(","))
		elif a.begins_with("--dist="):
			dist = a.substr(7).to_float()
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.9
	get_root().add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.material_override = Materials.get_mat("stone_dark")
	ground.position.y = -1.63
	get_root().add_child(ground)
	get_root().add_child(ImpactFx.new())
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.05
	get_root().add_child(cam)
	cam.make_current()
	var vm := Viewmodel.new()
	vm.look = Player.LOOK
	cam.add_child(vm)
	for target in targets:
		var body := _target(target, dist)
		get_root().add_child(body)
		# Look a little down at a rock's top, straight ahead at a trunk.
		cam.rotation = Vector3(-0.55 if target != "trunk" else 0.0, 0, 0)
		await physics_frame
		await physics_frame
		var from := cam.global_position
		var hit := get_root().world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 3.2))
		for t in items:
			vm.show_item(t)
			for i in 30:
				vm.sway(1.0 / 60.0, 0.0)
				await process_frame
			var land := vm.swing(0.55, {"point": hit["position"], "normal": hit["normal"]})
			var fired := false
			for f in 40:
				vm.sway(1.0 / 60.0, 0.0)
				if not fired and f / 60.0 >= land:
					fired = true
					ImpactFx.strike(hit["position"], hit["normal"], _mat(target), 1.0, true, (cam.global_basis * Vector3(-0.25, -0.75, -0.6)).normalized())
				await process_frame
				if f in FRAMES:
					await RenderingServer.frame_post_draw
					get_root().get_texture().get_image().save_png(out.path_join("%s_%s_%02d.png" % [t, target, f]))
		body.queue_free()
		await process_frame
	quit()

static func _mat(target: String) -> String:
	return {"trunk": "wood", "rock": "stone", "ore": "ore", "crystal": "crystal"}[target]

func _target(kind: String, dist: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	if kind == "trunk":
		var r := 0.38
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.9
		cm.bottom_radius = r
		cm.height = 6.0
		mi.mesh = cm
		mi.material_override = Materials.get_mat("bark")
		var sh := CylinderShape3D.new()
		sh.radius = r * 0.95
		sh.height = 6.0
		cs.shape = sh
		b.position = Vector3(0, 1.3, -(dist + r))
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.0, 1.4)
		mi.mesh = bm
		mi.material_override = Materials.get_mat({"rock": "stone", "ore": "stone_dark", "crystal": "slate"}[kind])
		var sh := BoxShape3D.new()
		sh.size = bm.size
		cs.shape = sh
		b.position = Vector3(0, -1.1, -(dist + 0.5))
	b.add_child(mi)
	b.add_child(cs)
	return b
