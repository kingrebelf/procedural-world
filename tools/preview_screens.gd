extends SceneTree
## Renders the code-drawn screens (ScreenLook, screen_ui.gdshader) in their rooms, close
## up and across the room, for checking their look:
##   godot --path . --script res://tools/preview_screens.gd -- --out=<dir> [--shots=console,wall]
##     [--size=1280x720] [--theme=human|alien] [--hour=14.5] [--wait=1.5]
## --wait lets the screens' animation run (seconds) before each picture.

const TITLE := "Kestrel Reach"

## [name, room type, camera, look at].
const SHOTS := [
	["console", "ops_tower", Vector3(-0.8, 1.55, -2.15), Vector3(-0.8, 1.05, -3.4)],
	["consoles", "ops_tower", Vector3(1.6, 1.8, -0.4), Vector3(-1.2, 1.0, -3.3)],
	["wall", "ops_tower", Vector3(-0.6, 2.1, -0.2), Vector3(-3.47, 2.45, -0.2)],
	["map", "ops_tower", Vector3(-1.2, 2.25, 2.0), Vector3(-1.2, 1.15, 0.85)],
	["computer", "lab_block", Vector3(-1.6, 1.95, -2.35), Vector3(-1.6, 1.58, -3.2)],
	["desk", "lab_block", Vector3(4.2, 1.45, 0.0), Vector3(5.38, 1.15, 0.0)],
	["lab", "lab_block", Vector3(0.0, 1.8, 3.0), Vector3(0.0, 1.0, -3.0)],
	["bunker", "bunker_keep", Vector3(3.6, 1.6, -1.2), Vector3(5.4, 1.1, -1.2)],
]

func _initialize() -> void:
	var out := "user://screens"
	var size := Vector2i(1280, 720)
	var want: Array = []
	var hour := 14.5
	var wait := 1.5
	Eras.theme = "human"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--shots="):
			want = Array(a.substr(8).split(","))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--theme="):
			Eras.theme = a.substr(8)
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
		elif a.begins_with("--wait="):
			wait = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	Materials.set_screen_clock(hour / 24.0)
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.34, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.2, 0.21, 0.23)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	# The game's glow, so any screen that would bloom shows it.
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	env.environment.glow_bloom = 0.08
	env.environment.glow_hdr_threshold = 1.1
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 70
	vp.add_child(cam)
	await process_frame
	var rooms := {}
	for shot: Array in SHOTS:
		if not want.is_empty() and not want.has(shot[0]):
			continue
		var t: String = shot[1]
		if not rooms.has(t):
			for r in rooms.values():
				r.queue_free()
			rooms.clear()
			var room := Node3D.new()
			vp.add_child(room)
			for m in [KitBase.build(Interiors._kit_of(t)), Interiors.interior(t)]:
				var mi := MeshInstance3D.new()
				mi.mesh = m
				room.add_child(mi)
				ScreenLook.set_title(mi, TITLE)
			for l in Interiors.lights(t):
				var o := OmniLight3D.new()
				o.position = l[0]
				o.light_color = l[1]
				o.light_energy = l[2]
				o.omni_range = l[3]
				o.shadow_enabled = true
				room.add_child(o)
			rooms[t] = room
		cam.look_at_from_position(shot[2], shot[3])
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < int(wait * 1000.0):
			await process_frame
		for f in 4:
			await process_frame
		var path: String = out + "/screens_%s_%s.png" % [shot[0], Eras.theme]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()
