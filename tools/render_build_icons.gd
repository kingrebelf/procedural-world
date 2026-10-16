extends SceneTree
## Renders an icon for every building piece and station into assets/icons/build/.
##   xvfb-run godot --path . --rendering-driver vulkan --script res://tools/render_build_icons.gd

const SIZE := 256
const OUT := 96

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	DirAccess.make_dir_recursive_absolute("res://assets/icons/build")
	for id in BuildCatalog.PIECES:
		var m := BuildCatalog.mesh(id)
		mi.mesh = m
		var aabb := m.get_aabb()
		if id == "foundation":
			aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 1.2, 2))
		var c := aabb.get_center()
		var r := aabb.size.length() * 0.5
		var dir := Vector3(0.9, 0.7, 1.25).normalized()
		cam.position = c + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.02)
		cam.look_at(c, Vector3.UP)
		for i in 6:
			await process_frame
		var img := vp.get_texture().get_image()
		img.resize(OUT, OUT, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/icons/build/%s.png" % id)
		print("icon ", id)
	quit()
