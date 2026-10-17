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

## (Oaks and pines are RealTree's now; their kit models stay as a fallback, loaded only if
## something asks for one.)
const ALL := ["Bush_Common", "Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
	"Bush_Common_Flowers", "Fern_1", "Flower_3_Group", "Flower_4_Group", "Grass_Wispy_Tall", "Grass_Common_Tall",
	"Plant_1_Big", "Plant_7_Big", "Mushroom_Common", "Mushroom_Laetiporus",
	"Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5",
	"Pebble_Square_1", "Pebble_Square_2", "Pebble_Square_3", "Flower_3_Single"]

## Undergrowth forms drawn from kit models: [model names, height range in metres].
const UNDER := {
	"fern": [["Fern_1"], 0.6, 1.1],
	"bush": [["Bush_Common", "Bush_Common_Flowers"], 0.7, 1.4],
	"flowers": [["Flower_3_Group", "Flower_4_Group"], 0.35, 0.6],
	"reeds": [["Grass_Wispy_Tall", "Grass_Common_Tall"], 0.7, 1.3],
	"fronds": [["Plant_1_Big", "Plant_7_Big"], 0.8, 1.5],
}

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

## An undergrowth plant from the kit (the same form Flora.under_form picks), or null for
## forms that stay procedural (glow bulbs, xeno tendrils).
static func build_under(sp: int, era: int) -> ArrayMesh:
	var form := Flora.under_form(sp, era)
	if not UNDER.has(form):
		return null
	var e: Array = UNDER[form]
	var r := Flora._rng(sp, 6)
	if form == "bush" and era != Eras.FANTASY:
		# Leaf-spray bushes (RealTree) rather than the kit's smooth lime blobs.
		return RealTree.build_bush(sp, r.randf_range(e[1], e[2]) * 1.15, r.randf() < 0.12)
	var names: Array = e[0]
	var src := _model(names[r.randi() % names.size()])
	if src.is_empty():
		return null
	var s := r.randf_range(e[1], e[2]) / maxf(float(src["height"]), 0.05)
	var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), Vector3.ZERO)
	# Mostly the kit's own colours, nudged toward the era's: greener fields, teal and violet
	# fantasy growth, rust-red sci-fi scrub.
	# Fantasy growth leans teal-green with some violet, but muted: saturated purple
	# carpets read as plastic.
	var fh := r.randf_range(0.36, 0.52) if r.randf() < 0.7 else r.randf_range(0.7, 0.8)
	var hue: float = [r.randf_range(0.18, 0.32), fh, r.randf_range(0.0, 0.1)][clampi(era, 0, 2)]
	var shift: float = [0.15, 0.35, 0.5][clampi(era, 0, 2)]
	var coloured := Color.WHITE.lerp(Color.from_hsv(hue, 0.5, 0.92), shift)
	var leaf := Color.from_hsv(hue, 0.5 + shift * 0.2, 0.62) if era != Eras.FANTASY else Color.from_hsv(hue, 0.36, 0.5)
	if form == "fern" and era == Eras.MEDIEVAL:
		# Woodland ferns are a deep, slightly blue-green in the shade, not the kit's lime
		# (which read as a tropical palm on the forest floor).
		leaf = Color.from_hsv(r.randf_range(0.24, 0.3), 0.45, 0.4)
		coloured = Color.WHITE.lerp(Color.from_hsv(0.27, 0.45, 0.62), 0.45)
	return _assemble(src, xf, leaf, Color.WHITE, coloured)

## A metre-square patch of ground clutter from kit models (instanced many times around
## the player, so kept to a few hundred triangles): pebbles of the photo stone and a wild
## flower (rusted scrap is added in sci-fi lands by ObjectLibrary).
static func build_clutter(era: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 21 + era
	var stones: Array = []
	var tint: Color = [Color(0.92, 0.9, 0.86), Color(0.62, 0.64, 0.7), Color(0.5, 0.45, 0.42)][clampi(era, 0, 2)]
	for n in [2, 2, 3][clampi(era, 0, 2)]:
		var m := ("Pebble_Round_%d" % (1 + (n * 2 + era) % 5)) if n != 1 else ("Pebble_Square_%d" % (1 + era % 3))
		var src := _model(m)
		if src.is_empty():
			continue
		# Pebbles a few centimetres high, the first of each patch a little bigger.
		var sz := (r.randf_range(0.03, 0.06) if n > 0 else r.randf_range(0.06, 0.1)) / maxf(float(src["height"]), 0.01)
		var b := Basis.from_euler(Vector3(r.randf_range(-0.3, 0.3), r.randf() * TAU, r.randf_range(-0.3, 0.3))).scaled(Vector3(sz, sz * r.randf_range(0.6, 1.0), sz))
		stones.append([m, Transform3D(b, Vector3(r.randf_range(-0.42, 0.42), -0.015, r.randf_range(-0.42, 0.42))), Flora._jit(tint, r, 0.08)])
	var out := ArrayMesh.new()
	var arr := _merge_pieces(stones)
	if not arr.is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(0, Materials.get_mat("stone_w"))
	if era != Eras.SCIFI:
		# One wild flower: meadow colours, or a teal stem in the fey lands.
		var src := _model("Flower_3_Single")
		if not src.is_empty():
			var s := r.randf_range(0.24, 0.36) / maxf(float(src["height"]), 0.05)
			var xf := Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4)))
			var stem := Color.from_hsv(0.27, 0.5, 0.55) if era == Eras.MEDIEVAL else Color.from_hsv(0.45, 0.36, 0.5)
			_assemble(src, xf, stem, Color.WHITE, Color.WHITE, out)
	return out

## Kit models ([name, transform, colour] each) merged into one surface for the photo
## stone material, with vertex colours. Empty if none of them loaded.
static func _merge_pieces(pieces: Array) -> Array:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	var ix := PackedInt32Array()
	for pc in pieces:
		var src := _model(pc[0])
		if src.is_empty():
			continue
		var xf: Transform3D = pc[1]
		var nb := xf.basis.inverse().transposed()
		var c: Color = pc[2]
		for part in src["parts"]:
			var a: Array = part[0]
			var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var base_i := vs.size()
			for j in pv.size():
				vs.append(xf * pv[j])
				ns.append((nb * pn[j]).normalized())
				cs.append(c)
			if a[Mesh.ARRAY_TEX_UV] != null:
				uvs.append_array(a[Mesh.ARRAY_TEX_UV])
			else:
				var zero := PackedVector2Array()
				zero.resize(pv.size())
				uvs.append_array(zero)
			if a[Mesh.ARRAY_INDEX] != null:
				for k in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
					ix.append(base_i + k)
			else:
				for k in pv.size():
					ix.append(base_i + k)
	if vs.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = ix
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_tangents()
	return st.commit_to_arrays()

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
	leaf = Color.from_hsv(leaf.h, clampf(leaf.s * 0.78, 0.0, 1.0), clampf(leaf.v * 1.22 + 0.05, 0.0, 0.9))
	var bark: Color = p.get("bark", Color(0.4, 0.3, 0.2))
	var bark_tint := Color.WHITE.lerp(bark * 2.2, 0.35)
	if p.get("form", "") == "column":
		bark_tint = Color(1.5, 1.5, 1.45) # birch: pale bark
	return _assemble(src, xf, leaf, bark_tint)

## A kit model moved by `xf`, its leaves tinted `leaf` (as brightness times hue) and its
## bark `bark_tint`. Parts whose texture is already coloured (flowers) keep their colours.
## Kit textures that are already coloured (not white masks): tinted only lightly.
const COLOURED := ["Leaves", "Grass", "Flowers"]

static func _assemble(src: Dictionary, xf: Transform3D, leaf: Color, bark_tint: Color, coloured := Color.WHITE, into: ArrayMesh = null) -> ArrayMesh:
	var out := into if into != null else ArrayMesh.new()
	var nb := xf.basis.inverse().transposed()
	for part in src["parts"]:
		var a: Array = (part[0] as Array).duplicate(true)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var tan = a[Mesh.ARRAY_TANGENT]
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if col.size() != pos.size():
			col.resize(pos.size())
			col.fill(Color.WHITE)
		var tint: Color = leaf if part[1] == "leaf" else bark_tint
		if part[2] in COLOURED:
			tint = Color.WHITE if part[2] == "Flowers" else coloured
		for j in pos.size():
			pos[j] = xf * pos[j]
			nrm[j] = (nb * nrm[j]).normalized()
			var c := col[j]
			# Kit vertex colours shade the crown (dark inside, light outside); keep that as
			# brightness only, so the species colour decides the hue.
			var lum := clampf(c.get_luminance() * 1.15 + 0.15, 0.35, 1.0) if part[1] == "leaf" else 1.0
			col[j] = Color(tint.r * lum, tint.g * lum, tint.b * lum, 1.0)
		if tan is PackedFloat32Array:
			var tg: PackedFloat32Array = tan
			for j in pos.size():
				var tv := (xf.basis * Vector3(tg[j * 4], tg[j * 4 + 1], tg[j * 4 + 2])).normalized()
				tg[j * 4] = tv.x
				tg[j * 4 + 1] = tv.y
				tg[j * 4 + 2] = tv.z
			a[Mesh.ARRAY_TANGENT] = tg
		a[Mesh.ARRAY_VERTEX] = pos
		a[Mesh.ARRAY_NORMAL] = nrm
		a[Mesh.ARRAY_COLOR] = col
		# LOD index lists were made once per model (see _model) and still fit: the vertices
		# are the same, only moved and recoloured.
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], part[3])
		out.surface_set_material(out.get_surface_count() - 1, _material(part[1], part[2]))
	return out

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
			var kind := "leaf" if mat_name.begins_with("Lea") or mat_name in ["Flowers", "Grass"] else "bark"
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
	# Tangents (for the bark normal map) and LODs, once per model. Simplifying a mesh runs
	# on the worker pool and waits for it, so it must never happen inside a chunk job:
	# preload_all calls this on the main thread.
	for part in parts:
		var st := SurfaceTool.new()
		var arr: Array = part[0]
		arr[Mesh.ARRAY_TANGENT] = null
		st.create_from_arrays(arr)
		if part[1] == "bark":
			st.generate_tangents()
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			im.generate_lods(25.0, 60.0, [])
		part[0] = im.get_surface_arrays(0)
		var lods := {}
		for l in im.get_surface_lod_count(0):
			lods[im.get_surface_lod_size(0, l)] = im.get_surface_lod_indices(0, l)
		part.append(lods)
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
			sm.set_shader_parameter("sway", 0.6 if base == "Leaf_Pine" else (8.0 if base in ["Leaves", "Grass", "Flowers"] else 1.0))
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
	var mat: Material = StoneKit.material()
	if t == "iron_vein":
		mat = _ore_material("iron")
		col = col.darkened(0.25)
	elif t == "aether_crystal":
		mat = _ore_material("aether")
	# Merge the pieces as raw arrays. Never round-trip through a temporary ArrayMesh here:
	# reading a mesh's arrays back asks the RenderingServer, which waits on the main thread,
	# and this runs in chunk jobs the main thread may itself be waiting on (scene change).
	for pc in pieces:
		pc.append(Flora._jit(col, r, 0.06))
	var merged := _merge_pieces(pieces)
	var out := ArrayMesh.new()
	if not merged.is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
		out.surface_set_material(0, mat)
	if t == "aether_crystal":
		# The crystals themselves stay procedural (they glow and are the point of the node).
		var k := MeshKit.new(sp & 0xFFFF)
		var cm := "crystal@%d" % int(p["glow"])
		for i in r.randi_range(4, 9):
			var a2 := r.randf() * TAU
			var b := Basis(Vector3(cos(a2), 0, sin(a2)).cross(Vector3.UP).normalized(), r.randf_range(0.1, 0.6))
			k.crystal(cm, Transform3D(b, Vector3(cos(a2) * 0.35, 0.35, sin(a2) * 0.35)), r.randf_range(0.12, 0.26), r.randf_range(0.8, 2.4))
		k.commit(Materials.get_mat, out)
	return out

## kind -> [vein colour, speck colour, vein width, vein frequency, Ben's ore photo]. With
## the photo in assets/textures the rock is that photo and the veins are its own.
const ORES := {
	"iron": [Color(0.5, 0.24, 0.12), Color(0.62, 0.6, 0.58), 0.16, 1.4, "iron_ore"],
	"aether": [Color(0.25, 0.45, 0.75), Color(0.6, 0.85, 0.9), 0.1, 1.2, "aether_rock"],
}

static func _ore_material(kind: String) -> Material:
	var key := "ore:" + kind
	_lock.lock()
	var m = _mats.get(key)
	if m == null:
		var o: Array = ORES[kind]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://src/world/ore.gdshader")
		var alb := Materials.photo(o[4], "albedo")
		if alb != null:
			sm.set_shader_parameter("photo_ore", true)
			sm.set_shader_parameter("stone_nrm", Materials.photo(o[4], "normal"))
			sm.set_shader_parameter("tri_scale", 0.45)
			sm.set_shader_parameter("ore_metal", 0.45)
		else:
			alb = Materials.photo("rock", "albedo")
			if alb == null:
				alb = Materials.photo("rock", "detail")
			sm.set_shader_parameter("stone_nrm", Materials.photo("rock", "normal"))
		sm.set_shader_parameter("stone_tex", alb)
		sm.set_shader_parameter("ore_col", o[0])
		sm.set_shader_parameter("ore_col2", o[1])
		sm.set_shader_parameter("vein_width", o[2])
		sm.set_shader_parameter("vein_freq", o[3])
		m = sm
		_mats[key] = m
	_lock.unlock()
	return m
