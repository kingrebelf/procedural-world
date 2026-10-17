extends SceneTree
## Renders line-ups of villagers of every age, weight and build (BodyShape), front and
## side on, for judging body variety: slim to heavy, young to stooped and grey.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_bodies.gd -- --out=/abs/dir
## --heads frames the heads close up (hair and faces). --walk films them walking at their
## own pace, three-quarter on (sway, limp, stoop). --check runs headless and
## prints each body's feet height and head height (feet must stay on the ground).

## [female, age, build (0.85..1.2), height (0.9..1.08), job]
const LINEUP := [
	[false, 19, 0.88, 1.04, "farmer"],
	[true, 22, 0.9, 0.98, "weaver"],
	[false, 34, 1.18, 1.0, "innkeeper"],
	[true, 38, 1.15, 0.94, "baker"],
	[false, 45, 0.98, 1.07, "smith"],
	[true, 47, 0.86, 1.05, "scribe"],
	[false, 58, 1.05, 0.96, "merchant"],
	[true, 61, 1.1, 0.92, "herbalist"],
	[false, 72, 0.9, 1.0, "priest"],
	[true, 70, 0.95, 0.97, "farmer"],
	[false, 26, 1.0, 0.91, "guard"],
	[true, 30, 1.02, 1.0, "miller"],
]

## Who --heads frames: young and old, men and women.
const HEADS := [0, 1, 4, 7, 8, 9]

func _initialize() -> void:
	_run.call_deferred()

func _body(i: int) -> Dictionary:
	var e: Array = LINEUP[i]
	var cl: Array = NPCGen.CLOTH[Eras.MEDIEVAL]
	return {"height": e[3], "build": e[2], "female": e[0], "skin": NPCGen.SKIN[(i * 3) % NPCGen.SKIN.size()],
		"hair": NPCGen.HAIR[(i * 5) % NPCGen.HAIR.size()], "hair_style": i % 4, "cloth": cl[i % cl.size()], "cloth2": cl[(i + 3) % cl.size()]}

func _run() -> void:
	var out := "user://"
	var check := false
	var heads := false
	var walk := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--walk":
			walk = true
		elif a == "--heads":
			heads = true
		elif a == "--check":
			check = true
	var vp := SubViewport.new()
	vp.size = Vector2i(2400, 760)
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
	var people: Array[HumanModel] = []
	var n := 6 if heads else LINEUP.size()
	var who: Array = []
	for i in n:
		who.append(HEADS[i] if heads else i)
	for i in n:
		var j: int = who[i]
		var b := _body(j)
		var h := HumanModel.new()
		vp.add_child(h)
		h.build(b, Eras.MEDIEVAL, String(LINEUP[j][4]), int(LINEUP[j][1]))
		var s := BodyShape.stature(b, int(LINEUP[j][1]))
		h.scale = Vector3(s, s, s)
		h.position = Vector3((i - (n - 1) * 0.5) * (0.42 if heads else 0.9), 0, 0)
		h.set_ground(flat)
		if walk:
			h.animator.manual = true
		people.append(h)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	var shots := [["front", Vector3.ZERO], ["side", Vector3(0, PI * 0.5, 0)]]
	if walk:
		shots = [["walk", Vector3.ZERO]]
	for shot in shots:
		var yaw: float = (shot[1] as Vector3).y
		for i in n:
			people[i].rotation.y = yaw
			people[i].position.z = 0.0
		cam.position = Vector3(0, 1.0, 7.4)
		cam.look_at(Vector3(0, 0.9, 0))
		if walk:
			cam.position = Vector3(5.5, 1.3, 9.0)
			cam.look_at(Vector3(0, 0.9, 2.6))
		if heads:
			cam.position = Vector3(0, 1.62, 1.55)
			cam.look_at(Vector3(0, 1.5, 0))
		var t0 := Time.get_ticks_msec()
		var frames := 0
		while frames < (75 if walk else 12) or (not walk and Time.get_ticks_msec() - t0 < 900 and frames < 200):
			for k in people.size():
				var h := people[k]
				if walk:
					var row: Array = LINEUP[who[k]]
					h.position.z += 1.35 * BodyShape.pace(_body(who[k]), int(row[1])) / 30.0
				h.advance(1.0 / 30.0)
			await process_frame
			frames += 1
		if check:
			for i in n:
				var sk := people[i].skeleton
				var gx := sk.global_transform
				var fl := gx * sk.get_bone_global_pose(sk.find_bone("foot_l")).origin
				var fr := gx * sk.get_bone_global_pose(sk.find_bone("foot_r")).origin
				var hd := gx * sk.get_bone_global_pose(sk.find_bone("Head")).origin
				var sh: Dictionary = people[i].shape
				var row: Array = LINEUP[who[i]]
				print("%s %-10s %s age %d w %.2f m %.2f stoop %.2f  feet %.3f %.3f head %.2f" % [shot[0], row[4], "F" if row[0] else "M",
					int(row[1]), sh["weight"], sh["muscle"], sh["stoop"], fl.y, fr.y, hd.y])
			continue
		var path := out.path_join("%s_%s.png" % ["heads" if heads else "bodies", shot[0]])
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
