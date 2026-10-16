class_name KitFlora
## Trees, snags and shrubs built from the CC0 Quaternius Stylized Nature kit instead of
## procedural boxes and cones. Each species still has its own look: the kit's white leaf
## masks are tinted with the species' leaf colour through the vertex colours, and the
## model is scaled to the species' height (which also sizes its collider).

const DIR := "res://assets/models/nature/"

## Leaf material per kit leaf mask; bark material per kit bark texture.
static var _mats: Dictionary = {}
## Model name -> [[arrays, kind ("leaf" / "bark"), texture base], ...] plus its height.
static var _models: Dictionary = {}
static var _lock := Mutex.new()

const ALL := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5",
	"Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5", "DeadTree_1", "DeadTree_2", "DeadTree_3",
	"DeadTree_4", "DeadTree_5", "TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4",
	"TwistedTree_5", "Bush_Common", "Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]

## Loads every kit model and material on the main thread, before chunk workers need them:
## loading the same scene from several worker threads at once can stall the loader.
static func preload_all() -> void:
	for n in ALL:
		var src := _model(n)
		for part in src.get("parts", []):
			_material(part[1], part[2])
	_ore_material("iron")

## Which kit model a species (and variant) uses, or "" to stay procedural.
static func model_name(t: String, p: Dictionary, sp: int, v: int) -> String:
	var i := 1 + (sp + v * 2) % 5
	var form: String = p.get("form", "")
	match t:
		"oak":
			match form:
				"dead": return "DeadTree_%d" % i
				"shrub": return "Bush_Common"
				"weeping": return "TwistedTree_%d" % i
				_: return "CommonTree_%d" % i
		"pine":
			if form == "snag":
				return "DeadTree_%d" % i
			return "Pine_%d" % i
	return ""

## The species' mesh from its kit model, or null when it has none.
static func build(t: String, sp: int, v: int) -> ArrayMesh:
	var p := Flora.species(t, sp)
	if p.is_empty():
		return null
	if t == "rock" or t == "iron_vein" or t == "aether_crystal":
		return _rock(t, p, sp, v)
	var mname := model_name(t, p, sp, v)
	if mname == "":
		return null
	var src := _model(mname)
	if src.is_empty():
		return null
	var r := Flora._rng(sp, 300 + v)
	var target: float = p.get("height", 6.0) * r.randf_range(0.9, 1.1)
	var s := target / maxf(float(src["height"]), 0.1)
	# Kit trees are slim for their height; widen the crown a little toward the species'.
	var wide := s * (1.0 + clampf(float(p.get("crown", p.get("width", 2.0))) * 0.08, 0.0, 0.25))
	var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(wide, s, wide)), Vector3.ZERO)
	var leaf: Color = p.get("leaf", Color(0.3, 0.5, 0.2))
	# Brighten: the mask is white, so the tint is the final colour (the procedural trees
	# darkened their leaves for shading that the kit's vertex colours now provide).
	leaf = Color.from_hsv(leaf.h, clampf(leaf.s * 0.9, 0.0, 1.0), clampf(leaf.v * 1.35 + 0.08, 0.0, 0.95))
	var bark: Color = p.get("bark", Color(0.4, 0.3, 0.2))
	var bark_tint := Color.WHITE.lerp(bark * 2.2, 0.35)
	if p.get("form", "") == "column":
		bark_tint = Color(1.5, 1.5, 1.45) # birch: pale bark
	var out := ArrayMesh.new()
	for part in src["parts"]:
		var a: Array = (part[0] as Array).duplicate(true)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if col.size() != pos.size():
			col.resize(pos.size())
			col.fill(Color.WHITE)
		var tint: Color = leaf if part[1] == "leaf" else bark_tint
		var nb := xf.basis.inverse().transposed()
		for j in pos.size():
			pos[j] = xf * pos[j]
			nrm[j] = (nb * nrm[j]).normalized()
			var c := col[j]
			# Kit vertex colours shade the crown (dark inside, light outside); keep that as
			# brightness only, so the species colour decides the hue.
			var lum := clampf(c.get_luminance() * 1.15 + 0.15, 0.35, 1.0) if part[1] == "leaf" else 1.0
			col[j] = Color(tint.r * lum, tint.g * lum, tint.b * lum, 1.0)
		a[Mesh.ARRAY_VERTEX] = pos
		a[Mesh.ARRAY_NORMAL] = nrm
		a[Mesh.ARRAY_COLOR] = col
		a[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(a)
		if part[1] == "bark":
			st.generate_tangents() # for the bark normal map
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _material(part[1], part[2]))
	return with_lods(out)

## Kit trees are thousands of triangles; let distant ones draw simplified versions.
static func with_lods(m: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in m.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, m.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

## Surface arrays of a kit model in its own space, cached.
static func _model(mname: String) -> Dictionary:
	_lock.lock()
	var m = _models.get(mname)
	_lock.unlock()
	if m != null:
		return m
	var ps: PackedScene = load(DIR + mname + ".gltf")
	if ps == null:
		push_warning("missing nature model " + mname)
		return {}
	var root := ps.instantiate()
	var parts: Array = []
	var lo := INF
	var hi := -INF
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := BuildCatalog._node_xf(mi, root)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var tex_name := ""
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				tex_name = (mat as BaseMaterial3D).albedo_texture.resource_path.get_file().get_basename()
			var mat_name: String = mat.resource_name if mat != null else ""
			var kind := "leaf" if mat_name.begins_with("Lea") else "bark"
			var a := mi.mesh.surface_get_arrays(s)
			var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var nb := xf.basis.inverse().transposed()
			for j in pos.size():
				pos[j] = xf * pos[j]
				nrm[j] = (nb * nrm[j]).normalized()
				lo = minf(lo, pos[j].y)
				hi = maxf(hi, pos[j].y)
			a[Mesh.ARRAY_VERTEX] = pos
			a[Mesh.ARRAY_NORMAL] = nrm
			parts.append([a, kind, _texture_base(mat_name, tex_name, kind)])
	root.free()
	# Stand the model on its lowest point.
	for part in parts:
		var pos: PackedVector3Array = part[0][Mesh.ARRAY_VERTEX]
		for j in pos.size():
			pos[j].y -= lo
		part[0][Mesh.ARRAY_VERTEX] = pos
	m = {"parts": parts, "height": hi - lo}
	_lock.lock()
	_models[mname] = m
	_lock.unlock()
	return m

## Leaves use the kit's white masks (not its pre-coloured "_C" textures) so any colour works.
static func _texture_base(mat_name: String, tex_name: String, kind: String) -> String:
	if kind == "leaf":
		match mat_name:
			"Leaves_Pine": return "Leaf_Pine"
			"Leaves_NormalTree": return "Leaves_NormalTree"
			"Leaves_TwistedTree": return "Leaves_TwistedTree"
		return tex_name.trim_suffix("_C")
	return mat_name if mat_name.begins_with("Bark_") else tex_name

static func _material(kind: String, base: String) -> Material:
	var key := kind + ":" + base
	_lock.lock()
	var m = _mats.get(key)
	if m == null:
		if kind == "leaf":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://src/world/foliage.gdshader")
			sm.set_shader_parameter("albedo_tex", load(DIR + base + ".png"))
			sm.set_shader_parameter("back", Color(0.3, 0.35, 0.12))
			sm.set_shader_parameter("sway", 0.6 if base == "Leaf_Pine" else 1.0)
			m = sm
		else:
			var bm := StandardMaterial3D.new()
			bm.albedo_texture = load(DIR + base + ".png")
			if ResourceLoader.exists(DIR + base + "_Normal.png"):
				bm.normal_enabled = true
				bm.normal_texture = load(DIR + base + "_Normal.png")
			bm.vertex_color_use_as_albedo = true
			bm.vertex_color_is_srgb = true
			bm.roughness = 0.9
			bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m = bm
		_mats[key] = m
	_lock.unlock()
	return m

# --- Rocks and ore -------------------------------------------------------------------
## Faceted kit rock shapes under the photo stone texture, stretched per species into
## boulders, slabs, spires, clusters or flat outcrops. Iron veins carry metal seams.

static func _rock(t: String, p: Dictionary, sp: int, v: int) -> ArrayMesh:
	var r := Flora._rng(sp, 400 + v)
	var col: Color = p["stone"]
	var sq: float = p["squash"]
	var pieces: Array = [] # [model, transform]
	var base := "Rock_Medium_%d" % (1 + (sp + v) % 3)
	var u := 2.0 / 3.2 # kit rocks are ~3.2 m across; the old rocks were ~2 m
	var shape := String(p["shape"])
	if t != "rock" and (shape == "flat" or shape == "slab"):
		shape = "boulder" # ore and crystal nodes stand up where you can see them
	match shape:
		"slab": pieces.append([base, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.5, 0.45, 1.2) * u), Vector3.ZERO)])
		"spire": pieces.append([base, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(0.7, 1.9, 0.7) * u), Vector3.ZERO)])
		"flat": pieces.append([base, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.4, 0.3, 1.4) * u), Vector3.ZERO)])
		"cluster":
			for n in 3:
				var a := TAU * n / 3.0 + r.randf()
				var sz := r.randf_range(0.45, 0.75)
				pieces.append(["Rock_Medium_%d" % (1 + (sp + n) % 3), Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sz, sz * sq * 1.2, sz) * u),
					Vector3(cos(a) * 0.7, -0.05, sin(a) * 0.7))])
		_: pieces.append([base, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(1.0, 0.55 + sq * 0.6, 1.0) * u), Vector3(0, -0.1, 0))])
	var mat: Material = Materials.get_mat("stone_w")
	if t == "iron_vein":
		mat = _ore_material("iron")
		col = col.darkened(0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pc in pieces:
		var src := _model(pc[0])
		if src.is_empty():
			continue
		for part in src["parts"]:
			var a: Array = (part[0] as Array).duplicate(true)
			var n := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var cols := PackedColorArray()
			cols.resize(n)
			cols.fill(Flora._jit(col, r, 0.06))
			a[Mesh.ARRAY_COLOR] = cols
			a[Mesh.ARRAY_TANGENT] = null
			var one := ArrayMesh.new()
			one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			st.append_from(one, 0, pc[1])
	st.generate_tangents()
	var out := st.commit()
	out.surface_set_material(0, mat)
	out = with_lods(out)
	if t == "aether_crystal":
		# The crystals themselves stay procedural (they glow and are the point of the node).
		var k := MeshKit.new(sp & 0xFFFF)
		var cm := "crystal@%d" % int(p["glow"])
		for i in r.randi_range(4, 9):
			var a2 := r.randf() * TAU
			var b := Basis(Vector3(cos(a2), 0, sin(a2)).cross(Vector3.UP).normalized(), r.randf_range(0.1, 0.6))
			k.crystal(cm, Transform3D(b, Vector3(cos(a2) * 0.35, 0.35, sin(a2) * 0.35)), r.randf_range(0.12, 0.26), r.randf_range(0.8, 2.4))
		var km := k.commit(Materials.get_mat)
		for s2 in km.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, km.surface_get_arrays(s2))
			out.surface_set_material(out.get_surface_count() - 1, km.surface_get_material(s2))
	return out

const ORES := {
	"iron": [Color(0.5, 0.24, 0.12), Color(0.62, 0.6, 0.58), 0.16, 1.4],
}

static func _ore_material(kind: String) -> Material:
	var key := "ore:" + kind
	_lock.lock()
	var m = _mats.get(key)
	if m == null:
		var o: Array = ORES[kind]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://src/world/ore.gdshader")
		var alb := Materials.photo("rock", "albedo")
		if alb == null:
			alb = Materials.photo("rock", "detail")
		sm.set_shader_parameter("stone_tex", alb)
		sm.set_shader_parameter("stone_nrm", Materials.photo("rock", "normal"))
		sm.set_shader_parameter("ore_col", o[0])
		sm.set_shader_parameter("ore_col2", o[1])
		sm.set_shader_parameter("vein_width", o[2])
		sm.set_shader_parameter("vein_freq", o[3])
		m = sm
		_mats[key] = m
	_lock.unlock()
	return m
