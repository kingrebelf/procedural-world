extends SceneTree
## Renders village cottages, boulders and oaks weathered by four climates side by side
## (ClimateWear): temperate, wet (moss), cold at dawn (snow and hoar frost), dry (dust),
## each with a patch of grass, then the wet cottage up close and from inside (which must stay clean):
##   godot --path . --script res://tools/preview_wear.gd -- --out=<dir> [--day=0.27]

const FRAME := Vector2i(1920, 900)
const GAP := 40.0
## Each climate's levels (moss, cold, dust, bog), one map texel per cottage.
const CLIMATES := [["temperate", Color(0.45, 0.0, 0.0, 0.0)], ["wet", Color(1.0, 0.0, 0.0, 0.6)],
	["cold", Color(0.3, 1.0, 0.0, 0.0)], ["dry", Color(0.0, 0.0, 1.0, 0.0)]]

func _initialize() -> void:
	var out := "user://wear"
	var day := 0.27
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--day="):
			day = a.substr(6).to_float()
	DirAccess.make_dir_recursive_absolute(out)
	BuildCatalog.warm_kits()
	RenderingServer.global_shader_parameter_set("snow_line_g", 400.0)
	RenderingServer.global_shader_parameter_set("sun_dir_g", Vector3(0.4, 0.6, 0.3).normalized())
	# The map: one climate per cottage's plot along x, the same down z.
	var n := CLIMATES.size()
	# Many texels per cottage, so each climate holds flat out to the edge of its plot
	# (the shaders read the map filtered).
	var img := Image.create(n * 16, 64, false, Image.FORMAT_RGBA8)
	for i in n * 16:
		for j in 64:
			img.set_pixel(i, j, CLIMATES[i / 16][1])
	var tex := ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("climate_wear_map_g", tex)
	RenderingServer.global_shader_parameter_set("climate_wear_rect_g", Vector4(-GAP * 0.5, -GAP * 2.0, GAP * n, 0.0))
	RenderingServer.global_shader_parameter_set("climate_wear_now_g", Vector4(ClimateWear.frost_now(day), day, 0.0, 0.0))
	var vp := SubViewport.new()
	vp.size = FRAME
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.38, 0.24)
	ground.material_override = gm
	# The terrain's own shader on a strip in front, to show its snow beside the rest.
	var strip := MeshInstance3D.new()
	var sp_m := PlaneMesh.new()
	sp_m.size = Vector2(n * GAP, 14.0)
	sp_m.subdivide_width = 40
	strip.mesh = sp_m
	strip.position = Vector3((n - 1) * GAP * 0.5, 0.02, 16.0)
	var tm := ShaderMaterial.new()
	tm.shader = load("res://src/world/terrain.gdshader")
	strip.material_override = tm
	vp.add_child(ground)
	vp.add_child(strip)
	var cam := Camera3D.new()
	cam.fov = 50
	cam.far = 600.0
	vp.add_child(cam)
	cam.current = true
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://src/world/grass.gdshader")
	var shelter := ShelterMap.new()
	vp.add_child(shelter)
	var oak := 0
	for sp in range(1, 3000):
		if String(Flora.species("oak", sp).get("form", "")) == "round":
			oak = sp
			break
	for i in n:
		var x := i * GAP
		var house := MultiMeshInstance3D.new()
		house.multimesh = _one(KitHouse.build("cottage"), Transform3D(Basis(), Vector3(x, 0, 0)), Color(1, 1, 1, 1))
		vp.add_child(house)
		var wall := MultiMeshInstance3D.new()
		wall.multimesh = _one(Stronghold.build("castle_tower"), Transform3D(Basis(), Vector3(x + 14.0, 0, -6.0)), Color(1, 1, 1, 1))
		vp.add_child(wall)
		var rock := MultiMeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 24
		sm.rings = 12
		sm.material = StoneKit.material()
		rock.multimesh = _one(sm, Transform3D(Basis().scaled(Vector3(2.6, 1.6, 2.2)), Vector3(x + 9.0, 0.4, 6.0)), Color(0.55, 0.53, 0.5, 0.7))
		vp.add_child(rock)
		if oak > 0:
			var tree := MultiMeshInstance3D.new()
			tree.multimesh = _one(RealTree.build("oak", oak, 0), Transform3D(Basis(), Vector3(x - 10.0, 0, 7.0)), Color(1, 1, 1, 1))
			vp.add_child(tree)
		for sp in ["meadow", "tall", "flowers_0"]:
			var g := MultiMeshInstance3D.new()
			g.multimesh = _grass(sp, Vector2(x + 2.0, 7.5), 6.0, 140 if sp == "meadow" else 40, i)
			g.material_override = grass_mat
			vp.add_child(g)
		var spruce := MultiMeshInstance3D.new()
		spruce.multimesh = _one(RealTree.build("pine", 7, 0), Transform3D(Basis(), Vector3(x - 4.0, 0, -9.0)), Color(1, 1, 1, 1))
		vp.add_child(spruce)
		_setts(vp, Vector2(x + 15.0, 16.0), 4.5)
		print("%s at x %.0f" % [CLIMATES[i][0], x])
	var mid := (n - 1) * GAP * 0.5
	var shots := [["row", Vector3(mid, 10.0, 78.0), Vector3(mid, 3.0, 0.0)]]
	for i in n:
		shots.append([CLIMATES[i][0], Vector3(i * GAP + 7.0, 3.0, 15.0), Vector3(i * GAP, 2.2, 0.0)])
	shots.append(["cold_tower", Vector3(2 * GAP + 2.0, 20.0, 18.0), Vector3(2 * GAP + 12.0, 7.0, -6.0)])
	shots.append(["cold_setts", Vector3(2 * GAP + 15.0, 4.5, 25.0), Vector3(2 * GAP + 15.0, 0.0, 15.0)])
	shots.append(["wet_inside", Vector3(GAP + 0.5, 1.7, 0.8), Vector3(GAP - 2.5, 0.8, -2.5)])
	await process_frame
	for shot in shots:
		cam.look_at_from_position(shot[1], shot[2])
		for f in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out + "/wear_%s%s.png" % [shot[0], "" if is_equal_approx(day, 0.27) else "_day%02d" % roundi(day * 100.0)]
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()

## A paved patch on the terrain strip, laid as TownLife._paving lays a square: metre setts,
## quarter cells at the ragged rim with some missing, the grime over them (red how near the
## rim), and a stretch of wall standing on it for snow to drift against.
func _setts(vp: Node, c: Vector2, rad: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grime := SurfaceTool.new()
	grime.begin(Mesh.PRIMITIVE_TRIANGLES)
	var margin := func(q: Vector2) -> float:
		var a := (q - c).angle()
		return rad + 0.8 * sin(a * 3.0) + 0.4 * sin(a * 7.0) - q.distance_to(c)
	var quad := func(q0: Vector2, sz: float) -> void:
		var v: Array[Vector3] = []
		for cq: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var q := q0 + cq * sz
			v.append(Vector3(q.x, 0.055, q.y))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0.8, 0.78, 0.75))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v[idx].x, v[idx].z))
			st.add_vertex(v[idx])
			var m: float = margin.call(Vector2(v[idx].x, v[idx].z))
			grime.set_normal(Vector3.UP)
			grime.set_color(Color(1.0 - clampf(m / 2.5, 0.0, 1.0), 0.0, 0.0, 1.0))
			grime.add_vertex(v[idx] + Vector3(0, 0.012, 0))
	var n := int(ceil(rad + 1.5))
	for j in range(-n, n):
		for i in range(-n, n):
			var q0 := c + Vector2(i, j)
			var low := INF
			for cq: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
				low = minf(low, margin.call(q0 + cq))
			if low > 1.2:
				quad.call(q0, 1.0)
			elif low > -1.0:
				for sj in 4:
					for si in 4:
						var qc := q0 + Vector2(si * 0.25 + 0.125, sj * 0.25 + 0.125)
						var m: float = margin.call(qc)
						var hsh := fposmod(sin(qc.x * 91.7 + qc.y * 47.3) * 43758.5453, 1.0)
						if m <= 0.0 or (m < 1.2 and hsh < 0.55 * (1.0 - m / 1.2)):
							continue
						quad.call(q0 + Vector2(si, sj) * 0.25, 0.25)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Materials.get_mat("cobble")
	vp.add_child(mi)
	var gi := MeshInstance3D.new()
	gi.mesh = grime.commit()
	gi.material_override = Materials.get_mat("sett_grime")
	vp.add_child(gi)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 3.0, 0.6)
	wall.mesh = bm
	wall.material_override = Materials.worn("castle_stone")
	wall.position = Vector3(c.x - 0.5, 1.5, c.y - 2.0)
	vp.add_child(wall)

## Clumps of a grass species scattered over a disc, tinted meadow green (as ChunkNode lays
## them: INSTANCE_CUSTOM the tint, alpha 0).
func _grass(sp: String, at: Vector2, rad: float, count: int, salt: int) -> MultiMesh:
	var r := RandomNumberGenerator.new()
	r.seed = hash(sp) + salt
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = GrassKit.mesh(sp)
	mm.instance_count = count
	for k in count:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * rad
		var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * r.randf_range(0.8, 1.2))
		mm.set_instance_transform(k, Transform3D(b, Vector3(at.x + cos(a) * d, 0.0, at.y + sin(a) * d)))
		mm.set_instance_custom_data(k, Color(0.42, 0.55, 0.22, 0.0))
	return mm

func _one(mesh: Mesh, xf: Transform3D, c: Color) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	mm.set_instance_color(0, c)
	return mm
