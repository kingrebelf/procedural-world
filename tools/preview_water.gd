extends SceneTree
## Renders a patch of lake (src/env/water.gdshader) over a sloping sandy bed, for judging
## the water's colour, see-through, foam and reflections:
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/preview_water.gd -- --out=F.png [--pitch=-20] [--river]
##     [--under [--novfog] [--nooverlay]]
## Rocks standing in the water and a sandbank give the reflections and shore foam
## something to show. --murk=M (0 clear sea, 1 silty pond) sets how murky the lake is.
## --river uses the river shader instead (flowing diagonally, no edge fade; --rapids
## makes it fall steeply). --under puts
## the eye 2.5 m under the surface with the game's underwater fog and overlay (either can
## be left out, to tell which one an artefact comes from).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://water.png"
	var pitch := -18.0
	var shader := "res://src/env/water.gdshader"
	var under := false
	var vfog := true
	var overlay := true
	var rapids := false
	var murk := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a == "--river":
			shader = "res://src/env/river.gdshader"
		elif a == "--under":
			under = true
		elif a == "--novfog":
			vfog = false
		elif a == "--nooverlay":
			overlay = false
		elif a.begins_with("--murk="):
			murk = float(a.substr(7))
		elif a == "--rapids":
			rapids = true
	get_root().size = Vector2i(1600, 900)
	RenderingServer.global_shader_parameter_set("sun_dir_g", Vector3(0.4, 0.6, 0.3).normalized())
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(1, 0.3))
	RenderingServer.global_shader_parameter_set("wind_strength", 0.35)
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	if under:
		# As Atmosphere sets it when the player is under water.
		var e := env.environment
		e.fog_enabled = true
		e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		e.fog_light_color = Color(0.06, 0.2, 0.24)
		e.fog_density = 0.075
		e.fog_sky_affect = 1.0
		e.fog_sun_scatter = 0.3
		e.volumetric_fog_enabled = vfog
		e.volumetric_fog_density = 0.02
		e.volumetric_fog_albedo = Color(0.3, 0.6, 0.65)
		e.volumetric_fog_length = 96.0
		e.volumetric_fog_detail_spread = 2.0
		e.volumetric_fog_anisotropy = 0.35
		if overlay:
			var layer := CanvasLayer.new()
			var rect := ColorRect.new()
			rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			var um := ShaderMaterial.new()
			um.shader = load("res://src/env/underwater.gdshader")
			um.set_shader_parameter("depth", 2.5)
			rect.material = um
			layer.add_child(rect)
			get_root().add_child(layer)
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -Vector3(0.4, 0.6, 0.3), Vector3.UP)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	get_root().add_child(sun)
	# A sandy bed sloping from the shore behind you (z = 16) to about 7 m deep at z = -60.
	var bed := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(200, 80)
	bm.subdivide_depth = 40
	bed.mesh = bm
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.62, 0.55, 0.42)
	bed.material_override = sand
	bed.rotation = Vector3(-atan(6.0 / 64.0), 0, 0)
	bed.position = Vector3(0, -4.0, -26)
	get_root().add_child(bed)
	# Rocks standing out of the water, and a sandbank breaking the surface.
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.32, 0.3, 0.28)
	rock_mat.roughness = 0.9
	for r in [Vector4(-14, -30, 2.5, 9.0), Vector4(9, -48, 4.0, 16.0), Vector4(26, -80, 6.0, 24.0), Vector4(-40, -70, 5.0, 12.0), Vector4(3, -14, 0.8, 1.2)]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r.z * 0.25
		cm.bottom_radius = r.z
		cm.height = r.w + 8.0
		cone.mesh = cm
		cone.material_override = rock_mat
		cone.position = Vector3(r.x, r.w * 0.5 - 4.0, r.y)
		get_root().add_child(cone)
	var bank := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	bank.mesh = sm
	bank.material_override = sand
	bank.scale = Vector3(14.0, 1.2, 6.0)
	bank.position = Vector3(-20, -0.9, -12)
	get_root().add_child(bank)
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(400, 400)
	wm.subdivide_width = 200
	wm.subdivide_depth = 200
	water.mesh = wm
	if shader.ends_with("river.gdshader"):
		# The flow, steepness and edge fade RiverMesh puts in the vertex colours.
		var arr := wm.get_mesh_arrays()
		var cols := PackedColorArray()
		cols.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.fill(Color(0.5 + 0.35, 0.5 - 0.2, 0.9 if rapids else 0.1, 1.0))
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		water.mesh = am
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	water.material_override = mat
	# Water's depth map: deep open water everywhere, as murky as asked.
	var dimg := Image.create(1, 1, false, Image.FORMAT_RGF)
	dimg.set_pixel(0, 0, Color(12.0, murk, 0.0))
	mat.set_shader_parameter("depth_map", ImageTexture.create_from_image(dimg))
	get_root().add_child(water)
	var cam := Camera3D.new()
	cam.fov = 70.0
	get_root().add_child(cam)
	cam.position = Vector3(0, 1.8, 8) if not under else Vector3(0, -2.5, -40)
	cam.rotation = Vector3(deg_to_rad(pitch), 0, 0)
	cam.make_current()
	for i in 30:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
