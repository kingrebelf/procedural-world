class_name StoneKit
## Loose stones on the ground, from gravel-sized pebbles to rocks you step around, and the
## rock material they and the boulders share (shaders/rock.gdshader). Every mesh is one
## metre across, so an instance's scale is its size in metres.
##   pebble   a jittered low-poly stone (scattered by the thousand, so a few triangles)
##   stone_a, stone_b   CC0 Quaternius kit pebbles, for stones of a hand's breadth or more
##   rock_a, rock_b     kit rocks, for the big ones in scree and rocky ground

const KINDS := ["pebble", "stone_a", "stone_b", "rock_a", "rock_b"]
const MODELS := {"stone_a": "Pebble_Square_2", "stone_b": "Pebble_Round_4", "rock_a": "Rock_Medium_1", "rock_b": "Rock_Medium_2"}

static var _meshes: Dictionary = {}
static var _hulls: Dictionary = {}
static var _mat: ShaderMaterial
static var _lock := Mutex.new()

static func material() -> Material:
	# Never hold the lock across a load: a load on a worker thread can wait on the main
	# thread, and the main thread may be waiting on this lock (that deadlocked streaming).
	_lock.lock()
	var m := _mat
	_lock.unlock()
	if m != null:
		return m
	var rock := Materials.photo("rock", "albedo")
	if rock == null:
		return Materials.get_mat("stone_w")
	m = ShaderMaterial.new()
	m.shader = load("res://src/world/shaders/rock.gdshader")
	m.set_shader_parameter("rock_tex", rock)
	m.set_shader_parameter("rock_nrm", Materials.photo("rock", "normal"))
	m.set_shader_parameter("moss_tex", Materials.photo("grass", "albedo"))
	_lock.lock()
	if _mat == null:
		_mat = m
	m = _mat
	_lock.unlock()
	return m

static func mesh(kind: String) -> ArrayMesh:
	_lock.lock()
	var m: ArrayMesh = _meshes.get(kind)
	_lock.unlock()
	if m != null:
		return m
	var arr := _arrays(kind)
	m = ArrayMesh.new()
	if not arr.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, material())
		var pts := PackedVector3Array()
		var seen := {}
		for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var key := Vector3i(roundi(v.x * 40.0), roundi(v.y * 40.0), roundi(v.z * 40.0))
			if not seen.has(key):
				seen[key] = true
				pts.append(v)
		_lock.lock()
		_hulls[kind] = pts
		_lock.unlock()
	_lock.lock()
	if _meshes.has(kind):
		m = _meshes[kind]
	else:
		_meshes[kind] = m
	_lock.unlock()
	return m

## The points of a stone's collision hull, in mesh space (after mesh() built it).
static func hull(kind: String) -> PackedVector3Array:
	if not _hulls.has(kind):
		mesh(kind)
	_lock.lock()
	var h: PackedVector3Array = _hulls.get(kind, PackedVector3Array())
	_lock.unlock()
	return h

static func _arrays(kind: String) -> Array:
	if kind == "pebble":
		return _pebble()
	var name: String = MODELS.get(kind, "")
	var src := KitFlora._model(name)
	if src.is_empty():
		return _pebble()
	# Fit the model to a metre across, its base at y = 0 and centred.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for part in src["parts"]:
		for v in (part[0][Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = lo.min(v)
			hi = hi.max(v)
	var s := 1.0 / maxf(maxf(hi.x - lo.x, hi.z - lo.z), 0.01)
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), -Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5) * s)
	return KitFlora._merge_pieces([[name, xf, Color.WHITE]])

## A faceted pebble: an icosahedron with its corners pushed in and out, flat underneath.
static func _pebble() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var r := RandomNumberGenerator.new()
	r.seed = 4111
	for i in vs.size():
		var v: Vector3 = vs[i].normalized() * r.randf_range(0.82, 1.12)
		vs[i] = Vector3(v.x * 0.5, maxf(v.y, -0.35) * 0.32 + 0.11, v.z * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	for f in faces:
		# Clockwise from outside (Godot front faces).
		for k in [0, 2, 1]:
			st.add_vertex(vs[f[k]])
	st.generate_normals()
	return st.commit_to_arrays()
