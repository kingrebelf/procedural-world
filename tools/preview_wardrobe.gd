extends SceneTree
## Renders townsfolk in their everyday clothes (Outfit.wardrobe), for judging variety and
## clipping: a line-up of one town's people per era, and a sheet of people in skirts, robes,
## tunics, aprons and capes caught mid-stride, running, sitting, bending and folding arms.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_wardrobe.gd -- --out=/abs/dir [--seed=N] [--motion-only]

const DT := 1.0 / 60.0
const CELL := Vector2i(300, 420)
## One row of the motion sheet per person: [female, job].
const MOVERS := [[true, "weaver"], [false, "farmer"], [true, "priest"], [false, "smith"], [true, "innkeeper"], [false, "hunter"]]
## Columns: [state, ground speed m/s, seconds to run first, yaw toward the camera].
const ACTIONS := [["walk", 1.35, 0.9, 0.9], ["walk", 1.35, 1.25, 0.9], ["jog", 3.6, 0.8, 1.2], ["idle", 0.0, 2.0, 0.5],
	["fold_arms", 0.0, 1.5, 0.3], ["sit", 0.0, 1.5, 1.1], ["harvest", 0.0, 1.0, 1.0], ["pickup", 0.0, 0.7, 1.2]]

var vp: SubViewport
var cam: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://wardrobe"
	var sd := 11
	var lineups := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			sd = a.substr(7).to_int()
		elif a == "--motion-only":
			lineups = false
	DirAccess.make_dir_recursive_absolute(out)
	Eras.theme = "human"
	vp = SubViewport.new()
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
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.38, 0.3)
	ground.material_override = gm
	vp.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	for era in ([Eras.MEDIEVAL, Eras.SCIFI, Eras.FANTASY] if lineups else []):
		await _lineup(out + "/lineup_%s.png" % Eras.NAMES[era].to_lower(), era, sd)
	await _motion(out + "/motion.png", sd)
	print("saved to ", out)
	quit()

func _human(b: Dictionary, era: int, job: String) -> HumanModel:
	var h := HumanModel.new()
	vp.add_child(h)
	h.build(b, era, job)
	h.animator.manual = true
	h.animator.lod = false
	return h

## Twelve people of one town, made the way the game makes them, standing about.
func _lineup(path: String, era: int, sd: int) -> void:
	vp.size = Vector2i(2400, 760)
	var r := RandomNumberGenerator.new()
	r.seed = sd + era * 101
	var jobs: Array = NPCGen.JOBS[era] + ["trader"]
	var people: Array = []
	for i in 12:
		var p := NPCGen.person(r, era, i, 0, 0)
		var h := _human(p["body"], era, jobs[i % jobs.size()] if i < jobs.size() else jobs[r.randi() % jobs.size()])
		h.position = Vector3((i - 5.5) * 0.92, 0, (i % 2) * 0.5)
		h.rotation.y = r.randf_range(-0.5, 0.5)
		people.append(h)
	cam.position = Vector3(0, 1.3, 13.0)
	cam.look_at(Vector3(0, 0.9, 0))
	for f in 90:
		for h in people:
			h.play("idle")
			h.advance(DT)
		await process_frame
	vp.get_texture().get_image().save_png(path)
	print("saved ", path)
	for h in people:
		h.queue_free()
	await process_frame

## Each mover in each action, one cell each, from three-quarters in front.
func _motion(path: String, sd: int) -> void:
	vp.size = CELL
	var sheet: Image = null
	var r := RandomNumberGenerator.new()
	r.seed = sd
	for row in MOVERS.size():
		var p := NPCGen.person(r, Eras.MEDIEVAL, row, 0, 0)
		p["body"]["female"] = MOVERS[row][0]
		for col in ACTIONS.size():
			var act: Array = ACTIONS[col]
			var h := _human(p["body"], Eras.MEDIEVAL, MOVERS[row][1])
			var z := 0.0
			var steps := int(float(act[2]) / DT)
			for f in steps:
				z += float(act[1]) * DT
				h.position = Vector3(0, 0, z)
				if act[1] > 0.0:
					h.play(act[0], float(act[1]) / (1.35 if act[0] == "walk" else 3.6))
				elif f == 0:
					if act[0] == "pickup":
						h.play_once(act[0])
					else:
						h.play(act[0])
				h.advance(DT)
			var yaw: float = act[3]
			cam.position = h.position + Vector3(sin(yaw) * 3.4, 1.0, cos(yaw) * 3.4)
			cam.look_at(h.position + Vector3(0, 0.8 if act[0] != "sit" else 0.6, 0))
			for i in 3:
				await process_frame
			var img := vp.get_texture().get_image()
			if sheet == null:
				sheet = Image.create(CELL.x * ACTIONS.size(), CELL.y * MOVERS.size(), false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * col, CELL.y * row))
			h.queue_free()
			await process_frame
	sheet.save_png(path)
	print("saved ", path)
