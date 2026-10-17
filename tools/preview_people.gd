extends SceneTree
## Renders a line-up of people in their clothes and armour, each mid-gesture, for judging
## Outfit and BodyLanguage.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_people.gd -- --out=/abs/path.png

## [female, era, job, gear (slot -> item), gesture or animation]
const LINEUP := [
	[false, Eras.MEDIEVAL, "farmer", {}, "wave"],
	[true, Eras.MEDIEVAL, "weaver", {}, "fingers_3"],
	[false, Eras.MEDIEVAL, "guard", {"head": "helm_iron", "chest": "mail_iron", "feet": "boots_leather", "hands": "gloves_leather", "shield": "shield_wood"}, "salute"],
	[true, Eras.FANTASY, "mystic", {}, "thumbs_up"],
	[false, Eras.FANTASY, "warden", {"head": "helm_elven", "chest": "plate_mythril", "legs": "guards_mythril", "feet": "boots_elven"}, "point"],
	[true, Eras.SCIFI, "engineer", {}, "peace"],
	[false, Eras.SCIFI, "security officer", {"head": "helm_visor", "chest": "exo_chest", "legs": "exo_legs", "feet": "mag_boots", "hands": "gauntlets_power"}, "shrug"],
	[true, Eras.MEDIEVAL, "priest", {}, "@dance"],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://people.png"
	var only := -1 ## --only=N renders just that person, close up
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).to_int()
	var vp := SubViewport.new()
	vp.size = Vector2i(1800, 760)
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
	gm.albedo_color = Color(0.32, 0.36, 0.24)
	ground.material_override = gm
	vp.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var people: Array = []
	for i in LINEUP.size():
		if only >= 0 and i != only:
			continue
		var e2: Array = LINEUP[i]
		var era: int = e2[1]
		var cl: Array = NPCGen.CLOTH[era]
		var b := {"height": 1.0, "build": 1.0, "female": e2[0], "skin": NPCGen.SKIN[i % NPCGen.SKIN.size()], "hair": NPCGen.HAIR[i % NPCGen.HAIR.size()],
			"hair_style": i % 4, "cloth": cl[i % cl.size()], "cloth2": cl[(i + 2) % cl.size()]}
		var h := HumanModel.new()
		vp.add_child(h)
		h.build(b, era, e2[2])
		var worn := {}
		for slot in e2[3]:
			worn[slot] = ItemDB.make(e2[3][slot], 1, 1.0, {})
		h.wear(worn)
		h.position = Vector3((i - (LINEUP.size() - 1) * 0.5) * 0.95 if only < 0 else 0.0, 0, 0)
		people.append([h, String(e2[4])])
	var cam := Camera3D.new()
	cam.fov = 32
	vp.add_child(cam)
	cam.position = Vector3(0, 1.25, 7.4) if only < 0 else Vector3(0.6, 1.3, 2.4)
	cam.look_at(Vector3(0, 0.95, 0))
	for p in people:
		var g: String = p[1]
		if g.begins_with("@"):
			p[0].play(g.substr(1))
		else:
			p[0].gesture(g)
	# Let the gestures blend in (they run on wall-clock time).
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 12 or (Time.get_ticks_msec() - t0 < 1100 and frames < 200):
		await process_frame
		frames += 1
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
