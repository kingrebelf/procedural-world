class_name MeshKit
extends RefCounted
## Procedural geometry builder. Primitives are added into named material buckets and
## committed as one multi-surface ArrayMesh. Faces use Godot's clockwise front-face
## winding; normals are computed analytically (or from neighbours for displaced shapes).

var _st: Dictionary = {} ## material name -> SurfaceTool
var _noise: FastNoiseLite
## While a grained box or cylinder is being added: (local point, local normal) -> UV.
var _uv_fn := Callable()
## While a screen face is being added: the UV2 its corners carry (ScreenLook).
var _uv2 := Vector2.INF

## Materials whose texture is wood grain, laid along each box's long axis and each
## cylinder's length (a beam is cut along the tree), not projected from the world.
const GRAIN := {"timber": true}
## Where across the grain photo its three boards that run the whole tile without an end
## joint lie, and how much of one board a narrow face may span (the board is 0.16 wide):
## a beam shows one board's grain, not the seams between them.
const BOARDS := [0.087, 0.416, 0.917]
const BOARD_SPAN := 0.12
const GRAIN_SCALE := 0.8 ## photo tiles per metre
## Faces wider than this show the photo's boards side by side, as planking.
const PLANKED := 0.4

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
	st.set_uv(_uv_fn.call(p, n) if _uv_fn.is_valid() else Vector2(wp.x + wp.z, wp.y))
	if _uv2 != Vector2.INF:
		st.set_uv2(_uv2)
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

## A flat face w x h in the xy plane of `xf`, facing +z, its UV spanning it (u right, v
## down) and `uv2` on every corner: a screen drawn by a shader (ScreenLook.face).
func panel(mat: String, xf: Transform3D, w: float, h: float, uv2: Vector2, color := Color.WHITE) -> void:
	_uv_fn = func(p: Vector3, _n: Vector3) -> Vector2: return Vector2(p.x / w + 0.5, 0.5 - p.y / h)
	_uv2 = uv2
	quad(mat, xf, Vector3(-w / 2, -h / 2, 0), Vector3(w / 2, -h / 2, 0), Vector3(w / 2, h / 2, 0), Vector3(-w / 2, h / 2, 0), color)
	_uv_fn = Callable()
	_uv2 = Vector2.INF

## A flat disc of radius r in the xz plane of `xf`, facing +y, its UV the square round it
## (v towards +z) and `uv2` on every point: a round screen (ScreenLook.disc).
func disc(mat: String, xf: Transform3D, r: float, segs: int, uv2: Vector2, color := Color.WHITE) -> void:
	_uv_fn = func(p: Vector3, _n: Vector3) -> Vector2: return Vector2(0.5 + p.x / (2.0 * r), 0.5 + p.z / (2.0 * r))
	_uv2 = uv2
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		tri(mat, xf, Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * r, Vector3(cos(a0), 0, sin(a0)) * r, Vector3.UP, Vector3.UP, Vector3.UP, color)
	_uv_fn = Callable()
	_uv2 = Vector2.INF

func box(mat: String, xf: Transform3D, size: Vector3, color := Color.WHITE) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	if GRAIN.has(mat):
		_uv_fn = _box_grain(xf, size)
	quad(mat, xf, p[4], p[5], p[6], p[7], color) # +z
	quad(mat, xf, p[1], p[0], p[3], p[2], color) # -z
	quad(mat, xf, p[5], p[1], p[2], p[6], color) # +x
	quad(mat, xf, p[0], p[4], p[7], p[3], color) # -x
	quad(mat, xf, p[7], p[6], p[2], p[3], color) # +y
	quad(mat, xf, p[0], p[1], p[5], p[4], color) # -y
	_uv_fn = Callable()

## A box with its twelve edges chamfered by `bevel` (capped to a third of its thinnest
## side): hand-worked timber, dressed stone and pressed panels never meet at a knife
## edge, and the narrow slanted face along each edge catches the light. 44 triangles.
func bevel_box(mat: String, xf: Transform3D, size: Vector3, bevel := 0.02, color := Color.WHITE) -> void:
	var c := minf(bevel, minf(size.x, minf(size.y, size.z)) / 3.0)
	if c < 0.004:
		box(mat, xf, size, color)
		return
	var h := size * 0.5
	var i := h - Vector3.ONE * c
	if GRAIN.has(mat):
		_uv_fn = _box_grain(xf, size)
	# The six faces, inset by the chamfer.
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[a] = s
			var pts: Array = []
			for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[a] = s * h[a]
				p[u] = q.x * i[u]
				p[v] = q.y * i[v]
				pts.append(p)
			_quad_n(mat, xf, pts, n, color)
	# The twelve chamfers, one along each edge.
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for su in [-1.0, 1.0]:
			for sv in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[u] = su
				n[v] = sv
				var pts: Array = []
				for e in [[-1.0, true], [1.0, true], [1.0, false], [-1.0, false]]:
					var p := Vector3.ZERO
					p[a] = e[0] * i[a]
					p[u] = su * (h[u] if e[1] else i[u])
					p[v] = sv * (i[v] if e[1] else h[v])
					pts.append(p)
				_quad_n(mat, xf, pts, n.normalized(), color)
	# The eight corners.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var a := Vector3(sx * h.x, sy * i.y, sz * i.z)
				var b := Vector3(sx * i.x, sy * h.y, sz * i.z)
				var d := Vector3(sx * i.x, sy * i.y, sz * h.z)
				_tri_n(mat, xf, a, b, d, n, n, n, color)
	_uv_fn = Callable()

## A triangle facing `n` whichever order its corners come in.
func _tri_n(mat: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb_: Vector3, nc: Vector3, color := Color.WHITE) -> void:
	if (b - a).cross(c - a).dot(na + nb_ + nc) < 0.0:
		tri(mat, xf, a, c, b, na, nc, nb_, color)
	else:
		tri(mat, xf, a, b, c, na, nb_, nc, color)

## A flat quad (corners in order round it) facing `n`.
func _quad_n(mat: String, xf: Transform3D, p: Array, n: Vector3, color := Color.WHITE) -> void:
	_tri_n(mat, xf, p[0], p[1], p[2], n, n, n, color)
	_tri_n(mat, xf, p[0], p[2], p[3], n, n, n, color)

## A moulding: `profile` swept along `path`. A profile point (s, f) sits at
## path point + side * s + face * f, where `sides` holds each path point's side
## direction (perpendicular to the run) and `face` is shared by the whole run: for a
## skirting board, side points into the room and face is up; for a door casing, side
## points away from the opening and face out of the wall. Only the profile's visible
## faces are given, wall to wall, with the solid on the right going along it (seen
## along the run); joints between runs are mitred (pass the bisected side, longer by
## 1 / cos of half the turn), facets meeting at under 40 degrees are shaded smooth,
## and open ends get a cap closed against the wall's corner (s, f) = (0, 0). Wood
## grain and photo textures run along the path.
func sweep(mat: String, xf: Transform3D, path: PackedVector3Array, sides: PackedVector3Array, face: Vector3, profile: PackedVector2Array, closed := false, caps := true, color := Color.WHITE) -> void:
	var st := _tool(mat)
	var nb := xf.basis.inverse().transposed()
	var np := profile.size()
	var pick := _grain_pick(xf.translated(path[0])) if GRAIN.has(mat) else Vector2.ZERO
	# Each profile facet's outward normal in (side, face) terms, and where it starts
	# along the profile (for the texture across it).
	var fn: Array = []
	var arc := PackedFloat32Array([0.0])
	for j in np - 1:
		var d := profile[j + 1] - profile[j]
		fn.append(Vector2(-d.y, d.x).normalized())
		arc.append(arc[j] + d.length())
	var su := minf(GRAIN_SCALE, BOARD_SPAN / maxf(arc[np - 1], 0.001)) if GRAIN.has(mat) else GRAIN_SCALE
	var smooth := func(j: int, end: int) -> Vector2:
		# The normal at facet j's start (end 0) or end (end 1).
		var other := j - 1 if end == 0 else j + 1
		if other < 0 or other >= np - 1 or (fn[j] as Vector2).dot(fn[other]) < 0.766:
			return fn[j]
		return ((fn[j] as Vector2) + (fn[other] as Vector2)).normalized()
	var runs := path.size() if closed else path.size() - 1
	var along := 0.0
	for k in runs:
		var k2 := (k + 1) % path.size()
		var p0 := path[k]
		var p1 := path[k2]
		var s0 := sides[k]
		var s1 := sides[k2]
		var run := p0.distance_to(p1)
		var dir := (p1 - p0) / maxf(run, 0.0001)
		# The side direction square to this run, for the normals.
		var sq := (s0 - dir * s0.dot(dir)).normalized()
		for j in np - 1:
			var a := profile[j]
			var b := profile[j + 1]
			var na2: Vector2 = smooth.call(j, 0)
			var nb2: Vector2 = smooth.call(j, 1)
			var na := sq * na2.x + face * na2.y
			var nbv := sq * nb2.x + face * nb2.y
			var q := [p0 + s0 * a.x + face * a.y, p1 + s1 * a.x + face * a.y, p1 + s1 * b.x + face * b.y, p0 + s0 * b.x + face * b.y]
			var uv := [Vector2(pick.x + arc[j] * su, along * GRAIN_SCALE + pick.y), Vector2(pick.x + arc[j] * su, (along + run) * GRAIN_SCALE + pick.y),
				Vector2(pick.x + arc[j + 1] * su, (along + run) * GRAIN_SCALE + pick.y), Vector2(pick.x + arc[j + 1] * su, along * GRAIN_SCALE + pick.y)]
			var ns := [na, na, nbv, nbv]
			var flip: bool = ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3)).dot(na + nbv) < 0.0
			for idx in ([0, 2, 1, 0, 3, 2] if not flip else [0, 1, 2, 0, 2, 3]):
				st.set_normal((nb * (ns[idx] as Vector3)).normalized())
				st.set_color(color)
				st.set_uv(uv[idx])
				st.add_vertex(xf * (q[idx] as Vector3))
		along += run
	if closed or not caps:
		return
	# End caps: the profile closed against the wall's corner.
	var poly := PackedVector2Array(profile)
	if not poly[0].is_zero_approx() and not poly[np - 1].is_zero_approx():
		poly.append(Vector2.ZERO)
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	for e in [[0, 1], [path.size() - 1, path.size() - 2]]:
		var p := path[e[0]]
		var s := sides[e[0]]
		var n := (p - path[e[1]]).normalized()
		for t in range(0, tris.size(), 3):
			var c: Array = []
			for m in 3:
				var q2 := poly[tris[t + m]]
				c.append(p + s * q2.x + face * q2.y)
			_tri_n(mat, xf, c[0], c[1], c[2], n, n, n, color)

## Which board of the grain photo a piece shows and how far along it starts, picked from
## where the piece is so neighbouring beams differ.
func _grain_pick(xf: Transform3D) -> Vector2:
	var h := absi(hash(xf.origin.snapped(Vector3.ONE * 0.01)))
	return Vector2(BOARDS[h % BOARDS.size()], float(h % 997) / 997.0)

## Grain UVs for a box: along its longest side; each narrow face centred on one board,
## wide faces planked, the end grain flat.
func _box_grain(xf: Transform3D, size: Vector3) -> Callable:
	var sc := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
	var s := size * sc
	var l := s.max_axis_index()
	var pick := _grain_pick(xf)
	return func(p: Vector3, n: Vector3) -> Vector2:
		var na := n.abs().max_axis_index()
		if na == l:
			return Vector2(p[(l + 1) % 3] * sc[(l + 1) % 3], p[(l + 2) % 3] * sc[(l + 2) % 3]) * GRAIN_SCALE
		var a := 3 - l - na
		var across := p[a] * sc[a]
		var su := GRAIN_SCALE if s[a] > PLANKED else minf(GRAIN_SCALE, BOARD_SPAN / maxf(s[a], 0.001))
		return Vector2(pick.x + across * su, p[l] * sc[l] * GRAIN_SCALE + pick.y)

## Grain UVs for a cylinder: along its length, mirrored round the back so there is no
## seam, the caps flat.
func _cylinder_grain(xf: Transform3D, r: float) -> Callable:
	var sr := xf.basis.x.length()
	var sy := xf.basis.y.length()
	var half := PI * r * sr
	var su := GRAIN_SCALE if half > PLANKED else minf(GRAIN_SCALE, BOARD_SPAN / maxf(half, 0.001))
	var pick := _grain_pick(xf)
	return func(p: Vector3, n: Vector3) -> Vector2:
		if absf(n.y) > 0.9:
			return Vector2(p.x, p.z) * sr * GRAIN_SCALE
		var round_ := absf(atan2(p.z, p.x)) / PI
		return Vector2(pick.x + (round_ - 0.5) * half * su, p.y * sy * GRAIN_SCALE + pick.y)

## Cylinder / cone frustum from y=0 to y=h. `wobble` adds organic noise to the radius.
func cylinder(mat: String, xf: Transform3D, rb: float, rt: float, h: float, segs: int = 12, caps: bool = true, wobble: float = 0.0, rings: int = 1, color := Color.WHITE) -> void:
	if GRAIN.has(mat):
		_uv_fn = _cylinder_grain(xf, maxf(rb, rt))
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
	_uv_fn = Callable()

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
## `tint`, if given, is called as tint(material name, arrays) on each surface before it is
## added, to colour its vertices.
func commit(materials: Callable, into: ArrayMesh = null, tint := Callable()) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	var names := _st.keys()
	names.sort()
	for name in names:
		var st: SurfaceTool = _st[name]
		st.generate_tangents()
		if tint.is_valid():
			var arrays := st.commit_to_arrays()
			tint.call(name, arrays)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		else:
			st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.call(name))
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
	return mesh
