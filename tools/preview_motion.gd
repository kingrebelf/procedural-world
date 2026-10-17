extends SceneTree
## Renders people moving, as film strips, for judging the animation: a walk and a run up
## a slope (side on, frames a fixed time apart), and people standing about on a hillside,
## one turning to look at the camera. Works on code from before HumanAnimator too, so the
## same shots can be taken of the old animation.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_motion.gd -- --out=/abs/dir

const SLOPE := 0.36 ## rise per metre uphill (about 20 degrees)
const FRAME := Vector2i(480, 560)
const COLS := 6
const DT := 1.0 / 60.0

var vp: SubViewport
var cam: Camera3D
var people: Array = []

func ground(x: float, z: float) -> float:
	return z * SLOPE

func _initialize() -> void:
	_run.call_deferred()

func _body(i: int, fem: bool) -> Dictionary:
	var cl: Array = NPCGen.CLOTH[Eras.MEDIEVAL]
	return {"height": 1.0, "build": 1.0, "female": fem, "skin": NPCGen.SKIN[(i * 3) % NPCGen.SKIN.size()], "hair": NPCGen.HAIR[i % NPCGen.HAIR.size()],
		"hair_style": i % 4, "cloth": cl[i % cl.size()], "cloth2": cl[(i + 2) % cl.size()]}

func _person(i: int, fem: bool, job: String) -> HumanModel:
	var h := HumanModel.new()
	vp.add_child(h)
	h.build(_body(i, fem), Eras.MEDIEVAL, job)
	if h.has_method("set_ground"):
		h.set_ground(Callable(self, "ground"))
		h.animator.manual = true
		h.animator.lod = false
	return h

func _step(h: HumanModel, dt: float) -> void:
	if h.get("animator") != null:
		h.advance(dt)
	else:
		h.anim.advance(dt)

func _run() -> void:
	var out := "user://motion"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
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
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(60), 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	# The hillside, with a grid on it so feet can be seen to stay put.
	var hill := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 120)
	hill.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _grid()
	gm.uv1_scale = Vector3(60, 120, 1)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	hill.material_override = gm
	hill.rotation.x = -atan(SLOPE)
	hill.scale.z = sqrt(1.0 + SLOPE * SLOPE)
	vp.add_child(hill)
	cam = Camera3D.new()
	cam.fov = 34
	vp.add_child(cam)
	await _strip(out + "/walk_uphill.png", 1.35, "walk")
	await _strip(out + "/run_uphill.png", 3.6, "jog")
	await _standing(out + "/standing_on_slope.png")
	await _animals(out + "/animals_on_slope.png")
	print("saved to ", out)
	quit()

func _grid() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	img.fill(Color(0.36, 0.4, 0.27))
	for i in 64:
		for j in [0, 1]:
			img.set_pixel(i, j, Color(0.26, 0.3, 0.19))
			img.set_pixel(j, i, Color(0.26, 0.3, 0.19))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _clear() -> void:
	for p in people:
		p.queue_free()
	people.clear()

## A person walks (or runs) uphill at `v` m/s; COLS frames, 0.1 s apart, side on.
func _strip(path: String, v: float, gait: String) -> void:
	_clear()
	var h := _person(1, false, "farmer")
	people.append(h)
	var z := -2.0
	var sheet: Image = null
	var t := 0.0
	var shot := 0
	var next := 2.0
	while shot < COLS:
		z += v * DT
		h.global_position = Vector3(0, ground(0, z), z)
		h.rotation.y = 0.0
		h.play(gait, v / (1.35 if gait == "walk" else 3.6))
		_step(h, DT)
		t += DT
		if t >= next:
			cam.global_position = Vector3(4.2, ground(0, z) + 1.0, z)
			cam.look_at(Vector3(0, ground(0, z) + 0.85, z))
			for i in 3:
				await process_frame
			var img := vp.get_texture().get_image()
			if sheet == null:
				sheet = Image.create(FRAME.x * COLS, FRAME.y, false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, FRAME), Vector2i(FRAME.x * shot, 0))
			shot += 1
			next += 0.1 if v < 2.0 else 0.06
	sheet.save_png(path)
	print("saved ", path)

## Three people stand across the slope; the middle one turns to look at the camera.
func _standing(path: String) -> void:
	_clear()
	vp.size = Vector2i(FRAME.x * 2, FRAME.y)
	for i in 3:
		var h := _person(i + 2, i == 1, ["farmer", "weaver", "guard"][i])
		people.append(h)
		h.global_position = Vector3((i - 1) * 1.1, ground(0, 0), 0)
		h.rotation.y = PI * 0.5 * (1.0 if i != 1 else -1.0) + (i - 1) * 0.3
		h.global_position.y = ground(h.global_position.x, h.global_position.z)
	# From uphill, so both feet of each show: the uphill foot stands higher.
	cam.global_position = Vector3(0.0, ground(0, 4.4) + 0.9, 4.4)
	cam.look_at(Vector3(0, 0.75, 0))
	if people[1].has_method("look_at_target"):
		people[1].look_at_target(cam.global_position, 1.0)
	for f in 120:
		for h in people:
			h.play("idle")
			_step(h, DT)
		await process_frame
	vp.get_texture().get_image().save_png(path)
	vp.size = FRAME
	print("saved ", path)

## A deer and a horse stand across the slope; the deer has seen the camera and watches it.
func _animals(path: String) -> void:
	_clear()
	vp.size = Vector2i(FRAME.x * 2, FRAME.y)
	var kinds := ["Deer", "Horse"]
	for i in 2:
		var a := AnimalModel.new()
		vp.add_child(a)
		a.build(kinds[i])
		people.append(a)
		a.global_position = Vector3((i - 0.5) * 2.6, 0, 0.3 * i)
		a.global_position.y = ground(a.global_position.x, a.global_position.z)
		a.rotation.y = PI * 0.5 if i == 0 else -PI * 0.6
		if a.get("ground") != null:
			a.ground = Callable(self, "ground")
			a.lod = false
	cam.global_position = Vector3(0.0, ground(0, 5.0) + 0.9, 5.0)
	cam.look_at(Vector3(0, 0.7, 0))
	if people[0].has_method("look_at_target"):
		people[0].look_at_target(cam.global_position, 1.0)
	for f in 90:
		for a in people:
			a.play("Idle")
		await process_frame
	vp.get_texture().get_image().save_png(path)
	vp.size = FRAME
	print("saved ", path)
