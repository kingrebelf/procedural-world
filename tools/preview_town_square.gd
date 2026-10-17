extends SceneTree
## A real town's market square (TownLife) on flat ground: its houses, the setts, the well
## or cross, stalls and carts, without streaming a world:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_town_square.gd
## Shots go to user://screenshots/square_*.png.

class FakeChunk:
	var data := {}

class FakeStreamer extends Node:
	var chunk := FakeChunk.new()
	func _init() -> void:
		var hs := PackedFloat32Array()
		hs.resize(ChunkGenerator.RES * ChunkGenerator.RES)
		chunk.data = {"heights": hs, "objects": []}
	func get_chunk(_k: Vector2i):
		return chunk

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("square_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _run() -> void:
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
	var gen := ChunkGenerator.new(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 4242)
	var site := {}
	for sz in range(-4, 5):
		for sx in range(-4, 5):
			var s2 := gen.settlement_at(sx, sz)
			if not s2.is_empty() and TownLife.applies(gen, s2) and int(s2["size"]) >= int(OS.get_environment("SIZE") if OS.get_environment("SIZE") != "" else "1"):
				if site.is_empty() or (s2["center"] as Vector2).length() < (site["center"] as Vector2).length():
					site = s2
	var c: Vector2 = site["center"]
	print("town at ", c, " size ", site["size"])
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.36, 0.28)
	ground.material_override = gm
	ground.position = Vector3(c.x, 0, c.y)
	root.add_child(ground)
	for it in gen.settlement_layout(site):
		var key: String = it["t"]
		if not (KitHouse.has(key) or ObjectLibrary.TOWN_PROPS.has(key) or key == "signpost"):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = ObjectLibrary.get_mesh(key)
		mi.position = Vector3(it["p"].x, -0.15, it["p"].y)
		mi.rotation.y = it["yaw"]
		root.add_child(mi)
	var fs := FakeStreamer.new()
	root.add_child(fs)
	var life = load("res://src/world/town_life.gd").new()
	life.gen = gen
	life.site = site
	life.streamer = fs
	root.add_child(life)
	life.set_process(false)
	var pl := TownLife.plan(gen, site)
	var sqd: Dictionary = pl["square"]
	var pieces: Array = []
	for p in pl["pieces"]:
		if (p.get("p", Vector2.INF) as Vector2).distance_to(c) < float(sqd["streets"]) and int(p["house"]) == -1:
			pieces.append(p)
	life._build([{"k": "paving", "p": c, "rad": sqd["rad"], "streets": sqd["streets"], "seed": sqd["seed"]}], 0.0)
	life._build(pieces, 0.0)
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	var cc := Vector3(c.x, 0, c.y)
	for s in [["high", cc + Vector3(18, 16, 22), cc], ["eye", cc + Vector3(10, 1.7, 9), cc + Vector3(0, 1.5, 0)],
			["eye2", cc + Vector3(-9, 1.7, -6), cc + Vector3(2, 1.2, 2)]]:
		cam.position = s[1]
		cam.look_at(s[2])
		await _shot(s[0])
	quit()
