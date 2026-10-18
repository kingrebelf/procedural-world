extends SceneTree
## Rides each small boat (Vehicle + Sailing) on a flat sea for a few seconds of real
## physics and prints how she went, with a picture from astern at the end:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tools/preview_ride.gd [-- --kind=sail_raft]
## Shots go to user://screenshots/ride_*.png.

## [kind, drive (steer, W/S), wind toward (world x, z), seconds, sail up].
const RUNS := [
	["canoe", Vector2(0, 1), Vector2.ZERO, 12.0, false],
	["kayak", Vector2(0.6, 1), Vector2.ZERO, 12.0, false],
	["rowboat", Vector2(0, 1), Vector2.ZERO, 12.0, false],
	["sail_raft", Vector2.ZERO, Vector2(0, -1), 25.0, true],
	["sail_raft", Vector2.ZERO, Vector2(1, -0.3), 25.0, true],
	["sail_raft", Vector2.ZERO, Vector2(0, 1), 15.0, true],
	["sloop", Vector2.ZERO, Vector2(1, 0), 40.0, true],
	["sloop", Vector2.ZERO, Vector2(0.7, 0.7), 40.0, true],
	["sloop", Vector2(0.4, 0), Vector2(1, 0), 30.0, true],
	["fishing_boat", Vector2.ZERO, Vector2(1, 0), 40.0, true],
	["cog", Vector2.ZERO, Vector2(0.3, -1), 60.0, true],
	["motor_launch", Vector2(0, 1), Vector2.ZERO, 20.0, false],
	["research_vessel", Vector2(0.5, 1), Vector2.ZERO, 40.0, false],
	["life_raft", Vector2(0, 1), Vector2.ZERO, 15.0, false],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			only = a.substr(7)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.58, 0.7, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.7)
	e.ambient_light_energy = 0.75
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.24, 0.3)
	sm.roughness = 0.1
	sea.material_override = sm
	root.add_child(sea)
	var cam := Camera3D.new()
	cam.fov = 70
	root.add_child(cam)
	var veh = load("res://src/vehicles/vehicle.gd")
	var water = load("res://src/env/water.gd")
	var sailing = load("res://src/vehicles/sailing.gd")
	var n := 0
	for r in RUNS:
		n += 1
		if only != "" and r[0] != only:
			continue
		water._wind = 0.4
		water._dir = (r[2] as Vector2) if (r[2] as Vector2).length() > 0.0 else Vector2(0.01, 0.0)
		var v = veh.new().setup({"id": n, "kind": r[0], "pos": Vector3.ZERO, "yaw": 0.0})
		v.ground = func(_x: float, _z: float) -> float: return -4.0
		root.add_child(v)
		v.rider = Node3D.new()
		v.drive = r[1]
		v.auto_trim = true
		if r[4]:
			v.toggle_sail()
		var frames := int(float(r[3]) * 60.0)
		for i in frames:
			await physics_frame
		var p: Vector3 = v.global_position
		var wind: Vector2 = water._dir.normalized() * sailing.wind_speed(water._wind)
		print("%s drive %s wind toward %s: at (%.1f, %.2f, %.1f) yaw %.2f, %.2f m/s, heel %.2f, %s %s, sheet %.2f" % [r[0], r[1], r[2],
			p.x, p.y, p.z, v.rotation.y, v.spd, float(v.sail["heel"]), sailing.point_of_sail(wind, v.rotation.y),
			sailing.sail_state(v.sail), float(v.sail["sheet"])])
		var back: Vector3 = v.global_transform.basis.z
		var far := maxf(7.0, float(v.p["length"]) * 1.8)
		cam.global_position = p + back * far + Vector3(far * 0.35, far * 0.45, 0)
		cam.look_at(p + Vector3(0, float(v.p["length"]) * 0.2, 0))
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		var path := "user://screenshots/ride_%d_%s.png" % [n, r[0]]
		root.get_texture().get_image().save_png(path)
		v.rider.free()
		v.rider = null
		v.queue_free()
		await process_frame
	quit()
