class_name Cave
## Caves in rocky hillsides (v4 worlds): a thick, lumpy rock shell half sunk into the
## ground with a mouth facing +z, dark inside, with ore seams and sometimes a cache.
## Everything is a pure function of the species `sp`, so the mesh and its collision are
## built from the same triangles (no mesh read-back on worker threads).

const SEGS := 48
const RINGS := 16
const THICK := 1.6
const MOUTH := 0.62 ## half-angle of the mouth, radians
const MOUTH_TOP := 0.78 ## the mouth reaches this far up the dome (elevation, radians)
const PHI0 := -0.4 ## the shell starts below ground so slopes never show a gap

static func dims(sp: int) -> Vector2:
	var r := WHash.rng(sp, 0, 0, 3)
	return Vector2(r.randf_range(9.0, 13.0), r.randf_range(6.0, 8.0))

static func _noise(sp: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = sp & 0x7FFFFFFF
	n.frequency = 0.11
	n.fractal_octaves = 3
	return n

static func _open(i: int, j: int) -> bool:
	var th := TAU * (i + 0.5) / SEGS
	var ph := PHI0 + (PI * 0.5 - PHI0) * (j + 0.5) / RINGS
	if ph >= MOUTH_TOP or ph <= PHI0 + 0.12:
		return false
	# An arch: widest at the floor, narrowing to the top, with ragged edges.
	var u := (ph - PHI0) / (MOUTH_TOP - PHI0)
	var half := MOUTH * (0.35 + 0.65 * sqrt(maxf(0.0, 1.0 - u * u)))
	return absf(angle_difference(th, 0.0)) < half

## Point on the shell; out = 1 for the outer skin, 0 for the inner.
static func _p(i: int, j: int, out: float, d: Vector2, n: FastNoiseLite) -> Vector3:
	var th := TAU * i / SEGS
	var ph := PHI0 + (PI * 0.5 - PHI0) * j / RINGS
	var dir := Vector3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))
	var q := Vector3(dir.x * d.x, dir.y * d.y, dir.z * d.x)
	var bump := n.get_noise_3dv(q) * 2.2 + n.get_noise_3dv(q * 2.7) * 0.6
	var top := 1.0 if j < RINGS else 0.0 # the very top is shared by all segments
	return q + dir * (bump * top + out * (THICK + absf(bump) * 0.4))

## Triangles of the whole shell: [vertices (3 per triangle), normals].
static func triangles(sp: int) -> Array:
	var d := dims(sp)
	var n := _noise(sp)
	var vs := PackedVector3Array()
	for j in RINGS:
		for i in SEGS:
			if _open(i, j):
				continue
			for out in [1.0, 0.0]:
				var a := _p(i, j, out, d, n)
				var b := _p((i + 1) % SEGS, j, out, d, n)
				var c := _p((i + 1) % SEGS, j + 1, out, d, n)
				var e := _p(i, j + 1, out, d, n)
				if out > 0.5:
					vs.append_array([a, c, b, a, e, c])
				else:
					vs.append_array([a, b, c, a, c, e])
			# Rims where the shell meets the mouth: close the gap between the skins.
			for side in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ni: int = (i + side[0] + SEGS) % SEGS
				var nj: int = j + side[1]
				if nj < 0 or nj >= RINGS or not _open(ni, nj):
					continue
				var p0: Vector3
				var p1: Vector3
				var q0: Vector3
				var q1: Vector3
				match side:
					[-1, 0]:
						p0 = _p(i, j, 0.0, d, n); p1 = _p(i, j + 1, 0.0, d, n); q0 = _p(i, j, 1.0, d, n); q1 = _p(i, j + 1, 1.0, d, n)
					[1, 0]:
						p0 = _p(i + 1, j + 1, 0.0, d, n); p1 = _p(i + 1, j, 0.0, d, n); q0 = _p(i + 1, j + 1, 1.0, d, n); q1 = _p(i + 1, j, 1.0, d, n)
					[0, -1]:
						p0 = _p(i + 1, j, 0.0, d, n); p1 = _p(i, j, 0.0, d, n); q0 = _p(i + 1, j, 1.0, d, n); q1 = _p(i, j, 1.0, d, n)
					_:
						p0 = _p(i, j + 1, 0.0, d, n); p1 = _p(i + 1, j + 1, 0.0, d, n); q0 = _p(i, j + 1, 1.0, d, n); q1 = _p(i + 1, j + 1, 1.0, d, n)
				vs.append_array([p0, q0, q1, p0, q1, p1, p0, q1, q0, p0, p1, q1])
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	for t in vs.size() / 3:
		var nn := (vs[t * 3 + 1] - vs[t * 3]).cross(vs[t * 3 + 2] - vs[t * 3]).normalized()
		ns[t * 3] = nn
		ns[t * 3 + 1] = nn
		ns[t * 3 + 2] = nn
	return [vs, ns]

static func build(sp: int) -> ArrayMesh:
	var tr := triangles(sp)
	var vs: PackedVector3Array = tr[0]
	var ns: PackedVector3Array = tr[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in vs.size():
		st.set_normal(ns[k])
		st.set_uv(Vector2(vs[k].x + vs[k].z, vs[k].y) * 0.5)
		st.add_vertex(vs[k])
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var out := ArrayMesh.new()
	st.commit(out)
	out.surface_set_material(0, Materials.get_mat("stone"))
	return out

static func shape(sp: int) -> Array:
	var c := ConcavePolygonShape3D.new()
	c.backface_collision = true
	c.set_faces(triangles(sp)[0])
	return [c, Vector3.ZERO]
