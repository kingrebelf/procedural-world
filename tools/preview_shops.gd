extends SceneTree
## Pictures of shops: each room type with a shop's sign, counter and wares, seen from
## the street and from just inside the door, without streaming a world:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_shops.gd
## Shots go to user://screenshots/shop_*.png.

const SHOTS := [
	["cottage", "armourer", 0], ["townhouse", "weaponsmith", 0], ["longhouse", "tavern", 0], ["cottage", "apothecary", 0],
	["townhouse", "land", 0], ["longhouse", "fighters_guild", 0], ["mushroom_house", "apothecary", 1], ["mushroom_house", "arcane_conclave", 1],
	["hab_block", "weaponsmith", 2], ["lab_block", "land", 2], ["hab_dome", "general", 2], ["ops_tower", "armourer", 2],
]

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("shop_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var shops = load("res://src/world/town_shops.gd")
	var lib = load("res://src/world/object_library.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.4, 0.22)
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 70
	root.add_child(cam)
	for s in SHOTS:
		var t: String = s[0]
		var kind: String = s[1]
		var era: int = s[2]
		var scene := Node3D.new()
		root.add_child(scene)
		for key in [t, t + "~in"]:
			var mi := MeshInstance3D.new()
			mi.mesh = lib.get_mesh(key)
			mi.position = Vector3(0, -0.15, 0)
			scene.add_child(mi)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 2.2, 0)
		lamp.light_energy = 1.6
		lamp.omni_range = 9.0
		lamp.light_color = Color(1.0, 0.8, 0.6) if era != 2 else Color(0.85, 0.93, 1.0)
		scene.add_child(lamp)
		var h := {"i": 0, "t": t, "p": Vector2.ZERO, "yaw": 0.0, "kind": kind, "era": era, "size": 2,
			"label": shops.label_of(kind, era), "sid": "preview",
			"title": shops.GUILDS[kind]["names"][0] if shops.is_guild(kind) else shops.KINDS[kind]["names"][era][0]}
		var decor = load("res://src/world/town_decor.gd").new()
		decor.data = {}
		scene.add_child(decor)
		decor._build(h, {"y": 0.0, "r": 0.0, "s": 1.0})
		var rm: Dictionary = shops.room(t)
		var dx: float = rm["door_x"]
		var dz: float = rm["door_z"]
		var sg: Vector3 = rm["sign"][0]
		cam.position = Vector3(dx + 1.8, 1.7, dz + 5.5)
		cam.look_at(Vector3(sg.x, sg.y - 0.3, sg.z))
		await _shot("%s_%s_out" % [t, kind])
		var half: Vector2 = rm["half"]
		cam.position = Vector3(dx + 0.2, 1.65, half.y - 0.35)
		var ft: Dictionary = shops.fit(t)
		var at: Vector2 = ft.get("counter", Vector2.ZERO)
		cam.look_at(Vector3(at.x, 0.9, at.y))
		await _shot("%s_%s_in" % [t, kind])
		var kp: Vector2 = ft.get("keeper", Vector2.ZERO)
		var face: Vector2 = ft.get("face", Vector2(0, 1))
		var mid := at.lerp(ft.get("display", at) if ft.get("display", Vector2.INF) != Vector2.INF else at, 0.4)
		cam.position = Vector3(mid.x + face.x * 2.3, 1.75, mid.y + face.y * 2.3)
		cam.look_at(Vector3(mid.x, 0.8, mid.y))
		await _shot("%s_%s_close" % [t, kind])
		scene.queue_free()
		await process_frame
	quit()
