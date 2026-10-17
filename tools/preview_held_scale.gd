extends SceneTree
## Renders villagers holding things, next to a 1.8 m measuring pole marked every half
## metre, to judge held items' size from a distance (HeldScale). The first four are
## built by job, holding their own work tools (HumanModel.WORK_TOOLS); the rest hold
## the --items given (or a default set of tools, weapons, a torch and food).
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_held_scale.gd -- --out=/abs/dir [--items=a,b,c]

const JOBS := ["smith", "farmer", "hunter", "guard"]
const ITEMS := ["pickaxe_iron", "axe_iron", "hammer", "sword_iron", "dagger", "shovel", "spear", "longbow", "torch", "musket", "bread"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://"
	var items: Array = ITEMS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--items="):
			items = Array(a.substr(8).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var vp := SubViewport.new()
	vp.size = Vector2i(2800, 900)
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
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.37, 0.3)
	ground.material_override = gm
	vp.add_child(ground)
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var n := JOBS.size() + items.size() + 1
	var cl: Array = NPCGen.CLOTH[Eras.MEDIEVAL]
	var people: Array[HumanModel] = []
	for i in n - 1:
		var b := {"height": 1.0, "build": 1.0, "female": i % 3 == 1, "skin": NPCGen.SKIN[(i * 3) % NPCGen.SKIN.size()],
			"hair": NPCGen.HAIR[(i * 5) % NPCGen.HAIR.size()], "hair_style": i % 4, "cloth": cl[i % cl.size()], "cloth2": cl[(i + 3) % cl.size()]}
		var job: String = JOBS[i] if i < JOBS.size() else "villager"
		var h := HumanModel.new()
		var s := BodyShape.stature(b, 35)
		h.scale = Vector3(s, s, s)
		vp.add_child(h)
		h.build(b, Eras.MEDIEVAL, job, 35)
		if i >= JOBS.size():
			h.hold(Viewmodel.prop_for(String(items[i - JOBS.size()])))
		h.position = Vector3((i - (n - 1) * 0.5) * 0.95, 0, 0)
		h.set_ground(flat)
		people.append(h)
	# The measuring pole: white and red half-metre bands up to 1.8 m.
	for k in 4:
		var band := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 0.5 if k < 3 else 0.3
		band.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.9, 0.9) if k % 2 == 0 else Color(0.8, 0.1, 0.1)
		band.material_override = m
		band.position = Vector3(((n - 1) - (n - 1) * 0.5) * 0.95, k * 0.5 + cm.height * 0.5, 0)
		vp.add_child(band)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	for shot in [["front", 0.0], ["side", PI * 0.5]]:
		for h in people:
			h.rotation.y = shot[1]
		cam.position = Vector3(0, 1.0, n * 0.95 * 0.5 / tan(deg_to_rad(15.0)) * 0.36)
		cam.look_at(Vector3(0, 0.9, 0))
		for f in 30:
			for h in people:
				h.advance(1.0 / 30.0)
			await process_frame
		var path := out.path_join("held_scale_%s.png" % shot[0])
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
