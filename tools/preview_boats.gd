extends SceneTree
## Pictures of every boat (src/vehicles/boat_model.gd) on a flat sea, with its crew posed
## at their stations, from outside and from the deck (and inside the cabins that have one):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_boats.gd [-- --kind=cog]
## Shots go to user://screenshots/boat_*.png.

## [kind, [camera, look at] per shot (boat-local)].
const SHOTS := {
	"raft": [[Vector3(5, 2.5, 4), Vector3(0, 0.4, 0)]],
	"rowboat": [[Vector3(5, 2.6, 4), Vector3(0, 0.3, 0)], [Vector3(-1.6, 2.2, 3.6), Vector3(0, 0.2, -0.5)], [Vector3(4.5, 1.4, -1.5), Vector3(0, 0.5, 0.4)]],
	"fishing_boat": [[Vector3(9, 4, 8), Vector3(0, 2.0, 0)], [Vector3(-1.2, 2.3, 4.2), Vector3(0, 1.0, -2)]],
	"cog": [[Vector3(22, 9, 18), Vector3(0, 4, 0)], [Vector3(-14, 5, -16), Vector3(0, 3, 0)], [Vector3(1.8, 3.4, -4.5), Vector3(0, 3.0, 6)],
		[Vector3(-1.5, 3.3, 5.2), Vector3(1.2, 2.0, 8.5)], [Vector3(14, 1.2, 1), Vector3(0, 1.5, -1)]],
	"life_raft": [[Vector3(4, 2.6, 4), Vector3(0, 0.6, 0)]],
	"launch": [[Vector3(8, 4, 7), Vector3(0, 1.2, 0)], [Vector3(-1.0, 2.4, 4.6), Vector3(0.4, 1.2, -1)]],
	"research_vessel": [[Vector3(26, 10, 22), Vector3(0, 4, 0)], [Vector3(-20, 6, -20), Vector3(0, 4, 0)], [Vector3(1.2, 6.3, 0.9), Vector3(0, 5.6, -2.2)],
		[Vector3(0.0, 3.6, 5.2), Vector3(1.6, 2.6, -1.0)], [Vector3(4, 4.5, 16), Vector3(0, 2.5, 6)]],
}

func _initialize() -> void:
	_run.call_deferred()

var _oars: Array = []
var _rowing := 0.0

func _shot(name: String) -> void:
	for i in 8:
		var ph: float = load("res://src/npc/body_language.gd").row_phase(0.0)
		for o in _oars:
			o.basis = load("res://src/vehicles/boat_model.gd").oar_stroke(1.0 if o.name == "Oar_r" else -1.0, ph, _rowing)
		await process_frame
	await RenderingServer.frame_post_draw
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("boat_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			only = a.substr(7)
	var bm = load("res://src/vehicles/boat_model.gd")
	var hm = load("res://src/npc/human_model.gd")
	var gen = load("res://src/npc/npc_gen.gd")
	var vm = load("res://src/player/viewmodel.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.58, 0.7, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.7)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.24, 0.3, 0.82)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.08
	sm.metallic = 0.2
	sea.material_override = sm
	root.add_child(sea)
	var cam := Camera3D.new()
	cam.fov = 70
	root.add_child(cam)
	for kind in SHOTS:
		if only != "" and kind != only:
			continue
		var scene := Node3D.new()
		root.add_child(scene)
		var body := StaticBody3D.new()
		scene.add_child(body)
		scene.add_child(bm.build(kind, 11, body))
		var bw = load("res://src/vehicles/boat_water.gd").build(kind)
		scene.add_child(bw)
		bw.follow(Vector2.ZERO, 0.0, 0.7 if kind in ["rowboat", "fishing_boat", "launch"] else 0.0)
		var r := RandomNumberGenerator.new()
		r.seed = 5
		var era := 2 if kind in ["life_raft", "launch", "research_vessel"] else 0
		var st: Array = bm.stations(kind)
		for i in st.size():
			var s: Dictionary = st[i]
			var p: Dictionary = gen.person(r, era, i, 0, 0)
			var h = hm.new()
			h.build(p["body"], era, "sailor")
			scene.add_child(h)
			h.position = s["p"]
			h.rotation.y = float(s["yaw"])
			h.ik.feet_here = false
			if bm.seated(s):
				h.play("sit")
			else:
				h.play({"steer": "interact" if era == 2 else "idle", "work": "fix" if era != 2 else "interact", "lookout": "fold_arms"}.get(s["pose"], "idle"))
			if s["pose"] == "row":
				h.gestures.row(true, 0.0)
			if s["pose"] == "fish":
				h.hold(vm.prop_for("fishing_rod", null), Vector3(0, 0.6, 1).normalized())
		for i in 30:
			await process_frame
		var shots: Array = SHOTS[kind]
		for i in shots.size():
			cam.position = shots[i][0]
			cam.look_at(shots[i][1])
			await _shot("%s_%d" % [kind, i])
		scene.queue_free()
		await process_frame
	quit()
