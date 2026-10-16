class_name MeshKit
extends RefCounted
## Procedural geometry builder. Primitives are added into named material buckets and
## committed as one multi-surface ArrayMesh. Faces use Godot's clockwise front-face
## winding; normals are computed analytically (or from neighbours for displaced shapes).

var _st: Dictionary = {} ## material name -> SurfaceTool
var _noise: FastNoiseLite

func _init(noise_seed: int = 1) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.frequency = 1.6
	_noise.fractal_octaves = 3

func _tool(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	return _st[mat]

func _v(st: SurfaceTool, xf: Transform3D, nb: Basis, p: Vector3, n: Vector3, color: Color) -> void:
	var wp := xf * p
	st.set_normal((nb * n).normalized())
	st.set_color(color)
	st.set_uv(Vector2(wp.x + wp.z, wp.y))
	st.add_vertex(wp)

## Adds triangle (a, b, c) given counter-clockwise when seen from the front side.
func tri(mat: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb_: Vector3, nc: Vector3, color := Color.WHITE) -> void:
	var st := _tool(mat)
	var nbasis := xf.basis.inverse().transposed()
	_v(st, xf, nbasis, a, na, color)
	_v(st, xf, nbasis, c, nc, color)
	_v(st, xf, nbasis, b, nb_, color)

## Flat quad, corners counter-clockwise seen from outside.
func quad(mat: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color := Color.WHITE) -> void:
	var n := (b - a).cross(c - a).normalized()
	tri(mat, xf, a, b, c, n, n, n, color)
	tri(mat, xf, a, c, d, n, n, n, color)

## Double-sided textured card (foliage). UVs span the full texture.
func card(mat: String, xf: Transform3D, center: Vector3, basis: Basis, w: float, h: float, normal_bias := Vector3.ZERO, color := Color.WHITE) -> void:
	var st := _tool(mat)
	var nbasis := xf.basis.inverse().transposed()
	var r := basis.x * w * 0.5
	var u := basis.y * h * 0.5
	var n := (basis.z + normal_bias).normalized()
	var corners := [[center - r - u, Vector2(0, 1)], [center + r - u, Vector2(1, 1)], [center + r + u, Vector2(1, 0)], [center - r + u, Vector2(0, 0)]]
	for idx in [0, 2, 1, 0, 3, 2]:
		var c: Array = corners[idx]
		var wp: Vector3 = xf * c[0]
		st.set_normal((nbasis * n).normalized())
		st.set_color(color)
		st.set_uv(c[1])
		st.add_vertex(wp)

func box(mat: String, xf: Transform3D, size: Vector3, color := Color.WHITE) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	quad(mat, xf, p[4], p[5], p[6], p[7], color) # +z
	quad(mat, xf, p[1], p[0], p[3], p[2], color) # -z
	quad(mat, xf, p[5], p[1], p[2], p[6], color) # +x
	quad(mat, xf, p[0], p[4], p[7], p[3], color) # -x
	quad(mat, xf, p[7], p[6], p[2], p[3], color) # +y
	quad(mat, xf, p[0], p[1], p[5], p[4], color) # -y

## Cylinder / cone frustum from y=0 to y=h. `wobble` adds organic noise to the radius.
func cylinder(mat: String, xf: Transform3D, rb: float, rt: float, h: float, segs: int = 12, caps: bool = true, wobble: float = 0.0, rings: int = 1, color := Color.WHITE) -> void:
	var slope := (rb - rt) / maxf(h, 0.0001)
	var ring_pts: Array = []
	for r in rings + 1:
		var t := float(r) / rings
		var y := h * t
		var rad := lerpf(rb, rt, t)
		var pts: Array = []
		for s in segs:
			var a := TAU * s / segs
			var d := Vector3(cos(a), 0, sin(a))
			var rr := rad
			if wobble > 0.0:
				rr *= 1.0 + wobble * _noise.get_noise_3d(d.x * 2.0, y * 0.7, d.z * 2.0)
			pts.append(Vector3(d.x * rr, y, d.z * rr))
		ring_pts.append(pts)
	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var a0 := TAU * s / segs
			var a1 := TAU * s2 / segs
			var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
			var p00: Vector3 = ring_pts[r][s]
			var p01: Vector3 = ring_pts[r][s2]
			var p10: Vector3 = ring_pts[r + 1][s]
			var p11: Vector3 = ring_pts[r + 1][s2]
			# Outward: going around +angle is clockwise seen from +y, so order for CCW-outside.
			tri(mat, xf, p00, p11, p01, n0, n1, n1, color)
			tri(mat, xf, p00, p10, p11, n0, n0, n1, color)
	if caps:
		var top: Array = ring_pts[rings]
		var bot: Array = ring_pts[0]
		for s in segs:
			var s2 := (s + 1) % segs
			if rt > 0.0001:
				tri(mat, xf, Vector3(0, h, 0), top[s2], top[s], Vector3.UP, Vector3.UP, Vector3.UP, color)
			tri(mat, xf, Vector3.ZERO, bot[s], bot[s2], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color)

## Displaced sphere ("blob"): organic foliage, boulders, caps.
func sphere(mat: String, xf: Transform3D, radius: float, rings: int = 8, segs: int = 12, displace: float = 0.0, squash: float = 1.0, color := Color.WHITE, half: bool = false) -> void:
	var grid: Array = []
	var ring_end := rings if not half else rings / 2
	for r in rings + 1:
		var phi := PI * r / rings
		var row: Array = []
		for s in segs:
			var th := TAU * s / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var rr := radius * (1.0 + displace * _noise.get_noise_3dv(d * 1.3))
			row.append(Vector3(d.x * rr, d.y * rr * squash, d.z * rr))
		grid.append(row)
	var normal := func(r: int, s: int) -> Vector3:
		if r == 0:
			return Vector3.UP
		if r == rings:
			return Vector3.DOWN
		var sp := (s + 1) % segs
		var sm := (s - 1 + segs) % segs
		var du: Vector3 = grid[r][sp] - grid[r][sm]
		var dv: Vector3 = grid[r + 1][s] - grid[r - 1][s]
		var n := dv.cross(du).normalized()
		var p: Vector3 = grid[r][s]
		return n if n.dot(p) >= 0.0 else -n
	for r in ring_end:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var d: Vector3 = grid[r + 1][s]
			var na: Vector3 = normal.call(r, s)
			var nb_: Vector3 = normal.call(r, s2)
			var nc: Vector3 = normal.call(r + 1, s2)
			var nd: Vector3 = normal.call(r + 1, s)
			tri(mat, xf, a, b, c, na, nb_, nc, color)
			tri(mat, xf, a, c, d, na, nc, nd, color)
	if half:
		# Close the underside of a dome.
		var row: Array = grid[ring_end]
		for s in segs:
			var s2 := (s + 1) % segs
			var cy: float = row[s].y
			tri(mat, xf, Vector3(0, cy, 0), row[s], row[s2], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color)

## Crystal: n-sided prism with a pointed tip and flat facets.
func crystal(mat: String, xf: Transform3D, radius: float, h: float, sides: int = 6, tip: float = 0.35, color := Color.WHITE) -> void:
	var body := h * (1.0 - tip)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var b0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := b0 * 0.85 + Vector3(0, body, 0)
		var t1 := b1 * 0.85 + Vector3(0, body, 0)
		quad(mat, xf, b0, t0, t1, b1, color)
		var apex := Vector3(0, h, 0)
		var n := (t0 - apex).cross(t1 - apex).normalized()
		if n.y < 0.0:
			n = -n
		tri(mat, xf, t0, apex, t1, n, n, n, color)

## Commits every bucket as a surface of `into` (or of a new mesh).
func commit(materials: Callable, into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	var names := _st.keys()
	names.sort()
	for name in names:
		var st: SurfaceTool = _st[name]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.call(name))
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
	return mesh
