extends SceneTree
## Shoots a person and a deer and films them going down as ragdolls (Ragdoll), then
## checks the settled pose saves and reloads exactly.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_ragdoll.gd -- --out=/abs/dir
##   godot --headless --path . --script res://tools/preview_ragdoll.gd -- --check [--animal=Boar]

const FRAME := Vector2i(480, 420)
const COLS := 6
const SLOPE := 0.25

var vp: SubViewport
var cam: Camera3D
var render := true

var animal := "Deer" ## --animal=<kind>: which animal falls, any AnimalModel kind

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://ragdoll"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--check":
			render = false
		elif a.begins_with("--animal="):
			animal = a.substr(9)
	DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = FRAME
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
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(50), 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	# A slope falling away along +z, solid to physics.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.4, 0.27)
	mi.material_override = gm
	ground.add_child(mi)
	ground.rotation.x = atan(SLOPE)
	vp.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	var ok := true
	ok = await _shoot_person(out + "/person_shot.png") and ok
	ok = await _shoot_animal(out + "/deer_shot.png") and ok
	print("ragdoll check: ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)

func _h(z: float) -> float:
	return -z * SLOPE

func _film(path: String, rd: Ragdoll, target: Node3D) -> PackedFloat32Array:
	var sheet: Image = null
	var shot := 0
	var t0 := Time.get_ticks_msec()
	var pose := PackedFloat32Array()
	var got := [false, PackedFloat32Array()]
	rd.settled.connect(func(p): got[0] = true; got[1] = p)
	var frames := 0
	# The camera follows the body as it slides and tumbles.
	var c0 := rd.center()
	var off := cam.global_position - c0
	var aim := -cam.global_basis.z
	while not got[0] and frames < 900:
		await physics_frame
		frames += 1
		var c := rd.center()
		if c != Vector3.INF:
			cam.global_position = cam.global_position.lerp(c + off, 0.15)
			cam.look_at(cam.global_position + aim)
		if render and frames % 9 == 1 and shot < COLS:
			await process_frame
			var img := vp.get_texture().get_image()
			if sheet == null:
				sheet = Image.create(FRAME.x * COLS, FRAME.y, false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, FRAME), Vector2i(FRAME.x * shot, 0))
			shot += 1
	if sheet:
		sheet.save_png(path)
		print("saved ", path)
	print("settled after %d physics frames (%.1f s wall)" % [frames, (Time.get_ticks_msec() - t0) / 1000.0])
	return got[1]

func _shoot_person(path: String) -> bool:
	var h := HumanModel.new()
	vp.add_child(h)
	h.build({"height": 1.0, "build": 1.0, "female": false, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.55, 0.25, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}, Eras.MEDIEVAL, "guard")
	h.global_position = Vector3(0, _h(0), 0)
	h.rotation.y = PI # facing -z, uphill toward the shooter
	h.play("jog")
	for i in 20:
		h.advance(1.0 / 60.0)
		await process_frame
	cam.global_position = Vector3(4.5, _h(0) + 1.3, 1.2)
	cam.look_at(Vector3(0, _h(1.0) + 0.5, 1.0))
	h.freeze_for_ragdoll()
	var rd := Ragdoll.new()
	h.add_child(rd)
	rd.build(h.skeleton, Ragdoll.HUMAN)
	var chest := h.skeleton.global_transform * h.skeleton.get_bone_global_pose(h.skeleton.find_bone("spine_03")).origin
	rd.start(Vector3(0, 0, -1.0), {"point": chest, "dir": Vector3(0, 0.1, 1).normalized(), "force": 60.0, "bone": ""})
	var pose := await _film(path, rd, h)
	return _check_reload(h, pose, "person")

func _shoot_animal(path: String) -> bool:
	for c in vp.get_children():
		if c is HumanModel:
			c.queue_free()
	var a := AnimalModel.new()
	vp.add_child(a)
	a.build(animal)
	a.global_position = Vector3(0, _h(0), 0)
	a.rotation.y = PI * 0.5
	a.play("Gallop")
	for i in 20:
		await process_frame
	cam.global_position = Vector3(0.5, _h(5.0) + 1.6, 5.0)
	cam.look_at(Vector3(0, _h(0.5) + 0.4, 0.5))
	var sk: Skeleton3D = a.find_children("*", "Skeleton3D", true, false)[0]
	a.freeze_for_ragdoll()
	var rd := Ragdoll.new()
	a.add_child(rd)
	rd.build(sk, Ragdoll.animal_spec(sk))
	var side := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Torso3")).origin
	rd.start(Vector3(4.0, 0, 0), {"point": side, "dir": Vector3(0, 0.2, 1).normalized(), "force": 40.0, "bone": ""})
	var pose := await _film(path, rd, a)
	return _check_reload_sk(sk, pose, "deer")

func _check_reload(h: HumanModel, pose: PackedFloat32Array, what: String) -> bool:
	return _check_reload_sk(h.skeleton, pose, what)

func _check_reload_sk(sk: Skeleton3D, pose: PackedFloat32Array, what: String) -> bool:
	if pose.size() != sk.get_bone_count() * 7:
		print("%s: no pose captured" % what)
		return false
	# The body lies low and still, in the pose it settled in.
	var pelvis := 0 if sk.find_bone("pelvis") < 0 else sk.find_bone("pelvis")
	var bytes := var_to_bytes(pose)
	var back: PackedFloat32Array = bytes_to_var(bytes)
	var ok := back == pose
	Ragdoll.apply_pose(sk, back)
	var hip := sk.global_transform * sk.get_bone_global_pose(pelvis).origin
	print("%s: pose %d floats, saves and loads %s, hips %.2f m above where it stood" % [what, pose.size(), "identically" if ok else "DIFFERENTLY", hip.y])
	return ok
