extends SceneTree
## Pictures of a village yard's pieces (TownLife) on flat ground, without streaming a world:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_town_life.gd
## Shots go to user://screenshots/life_*.png.

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
	var path := dir.path_join("life_%s.png" % name)
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
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.4, 0.22)
	ground.material_override = gm
	root.add_child(ground)
	var house := MeshInstance3D.new()
	house.mesh = ObjectLibrary.get_mesh("cottage")
	house.position = Vector3(0, -0.15, 0)
	root.add_child(house)
	var fs := FakeStreamer.new()
	root.add_child(fs)
	var life = load("res://src/world/town_life.gd").new()
	life.streamer = fs
	root.add_child(life)
	life.set_process(false) # (after ready, which turns processing on) the lamps stay as set here
	var P := func(k: String, p: Vector2, yaw: float, extra: Dictionary) -> Dictionary:
		var d := {"k": k, "p": p, "yaw": yaw, "house": 0, "seed": 7}
		d.merge(extra)
		return d
	# A cottage (6 x 6, door +z) and its yard, laid out as TownLife._yard would.
	life._build([P.call("plinth", Vector2.ZERO, 0.0, {"w": 6.0, "d": 6.0, "door": 0.0}),
		P.call("woodpile", Vector2(3.62, 0.0), PI * 0.5, {"len": 2.0, "roof": true}),
		P.call("chopping", Vector2(4.7, 0.6), 0.4, {}),
		P.call("garden", Vector2(0.3, -6.1), 0.0, {"hx": 2.3, "hz": 1.8}),
		P.call("washing", Vector2(-5.0, -0.2), 0.0, {"len": 4.0}),
		P.call("bench", Vector2(1.75, 3.42), 0.0, {}),
		P.call("barrels", Vector2(-1.7, 3.5), 0.2, {}),
		P.call("lantern", Vector2(-0.98, 3.1), 0.0, {"y": 2.0}),
		{"k": "smoke", "l": Vector3(1.4, 7.05, -1.6), "p": Vector2.ZERO, "yaw": 0.0, "house": 0},
		P.call("haystack", Vector2(9.0, 3.0), 0.0, {}),
		P.call("cart", Vector2(9.5, -4.0), 0.3, {"hay": true}),
		P.call("scarecrow", Vector2(-9.0, 5.0), 0.5, {}),
		P.call("torch_post", Vector2(-3.0, 6.0), PI, {}),
		{"k": "fence", "a": Vector2(-12, 9), "b": Vector2(-4, 9), "house": -1},
		{"k": "fence", "a": Vector2(-6.2, 2.4), "b": Vector2(-6.2, -8.6), "house": 0, "wattle": true},
		{"k": "fence", "a": Vector2(-6.2, -8.6), "b": Vector2(6.2, -8.6), "house": 0, "wattle": true}], 0.0)
	life._lit = 1
	for f in life._flames:
		f.visible = true
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	for s in [["front", Vector3(6, 3.2, 13), Vector3(0, 1.2, 0)], ["back", Vector3(-4, 4, -13), Vector3(0, 1, -3)],
			["side", Vector3(13, 2.5, 2), Vector3(3, 1, 0)], ["washing", Vector3(-9, 1.8, 3), Vector3(-5, 1.3, -0.5)],
			["farm", Vector3(2, 3, 14), Vector3(0, 1, 2)], ["wattle", Vector3(-9.5, 1.6, -11.5), Vector3(-5, 0.6, -6)]]:
		cam.position = s[1]
		cam.look_at(s[2])
		await _shot(s[0])
	# After dark: the lantern and the torch burn.
	sun.visible = false
	e.background_color = Color(0.02, 0.03, 0.06)
	e.ambient_light_energy = 0.05
	cam.position = Vector3(3, 2.2, 10)
	cam.look_at(Vector3(-1, 1.6, 2))
	await _shot("night")
	quit()
