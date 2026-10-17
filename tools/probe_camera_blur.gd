extends SceneTree
## Checks and shows motion blur (CameraBlur). A field of posts and a held box stand
## around a camera that turns and walks:
## 1. With TAA on (so every surface writes motion vectors) it paints where the engine's
##    motion vectors and the camera's own motion agree (debug 2) and prints the share
##    that agree: it must be near 100%, or the smear would point the wrong way on the
##    land and sky while people and the held item smear correctly.
## 2. Saves frames with the blur off and on, turning and walking.
## Run windowed, at a fixed frame rate:
##   xvfb-run godot --path . --fixed-fps 60 --script res://tools/probe_camera_blur.gd -- [--out=DIR] [--strength=0.4]
const TURN := 2.2 ## radians per second

var _cam: Camera3D
var _held: MeshInstance3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://camera_blur"
	var strength := 0.4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--strength="):
			strength = a.substr(11).to_float()
	DirAccess.make_dir_recursive_absolute(out)
	get_root().size = Vector2i(960, 540)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	we.environment.sky = sky
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var comp := Compositor.new()
	var blur := CameraBlur.new()
	comp.compositor_effects = [blur]
	we.compositor = comp
	get_root().add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	get_root().add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.45, 0.2)
	ground.material_override = gmat
	get_root().add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 160:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, rng.randf_range(1.0, 4.0), 0.4)
		post.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(rng.randf(), 0.7, 0.9)
		post.material_override = m
		var ang := rng.randf() * TAU
		var r := rng.randf_range(3.0, 40.0)
		post.position = Vector3(cos(ang) * r, bm.size.y * 0.5, sin(ang) * r)
		get_root().add_child(post)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.6, 0)
	get_root().add_child(_cam)
	_cam.current = true
	# The held item: a box riding with the camera, as the viewmodel does.
	_held = MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.08, 0.08, 0.5)
	_held.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.6, 0.4, 0.25)
	_held.material_override = hm
	_held.position = Vector3(0.3, -0.25, -0.6)
	_cam.add_child(_held)

	# 1. Agreement, with TAA (motion vectors everywhere).
	get_root().use_taa = true
	CameraBlur.strength = strength
	CameraBlur.fixed_dt = 1.0 / 60.0
	CameraBlur.debug = 2
	blur.enabled = true
	# (The held item moves with the camera, so the two disagree there by design.)
	_held.visible = false
	await _turn(20)
	var img := get_root().get_texture().get_image()
	img.save_png(out.path_join("agree.png"))
	var good := 0
	var bad := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.g > 0.5 and c.r < 0.3:
				good += 1
			elif c.r > 0.5 and c.g < 0.3:
				bad += 1
	print("camera blur: motion agrees on %d of %d samples (%.1f%%)" % [good, good + bad, 100.0 * good / maxf(good + bad, 1)])

	# 2. Off and on, with the game's own anti-aliasing off so the smear itself shows.
	get_root().use_taa = false
	CameraBlur.debug = 0
	_held.visible = true
	for on in [false, true]:
		blur.enabled = on
		await _turn(20)
		get_root().get_texture().get_image().save_png(out.path_join("turn_%s.png" % ("on" if on else "off")))
		await _walk(20)
		get_root().get_texture().get_image().save_png(out.path_join("walk_%s.png" % ("on" if on else "off")))
	print("camera blur: frames in ", ProjectSettings.globalize_path(out))
	quit()

func _turn(frames: int) -> void:
	for i in frames:
		_cam.rotation.y += TURN / 60.0
		_cam.rotation.x = sin(i * 0.2) * 0.15
		await process_frame

func _walk(frames: int) -> void:
	_cam.rotation = Vector3(0, 0.3, 0)
	for i in frames:
		_cam.position += -_cam.global_transform.basis.z * (8.0 / 60.0)
		await process_frame
