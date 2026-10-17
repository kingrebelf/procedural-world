class_name HiFlora
## High-detail procedural meshes for the fantasy and alien flora that no asset pack
## covers: giant mushrooms (lathed caps with gills, bulbous stems), crystal trees and
## aether crystal clusters (faceted prisms with a crystal shader), and alien plants
## (blooms, weepers, tube corals, coiled fronds, pod stalks). Smooth normals, real
## silhouettes, and shader materials (subsurface light, spots, inner glow) instead of
## flat vertex-coloured primitives. Pure functions of (type, species); safe on worker
## threads (only SurfaceTool and resource creation, no RenderingServer reads).

static var _organic: Shader
static var _crystal: Shader
static var _lock := Mutex.new()

static func _shaders() -> void:
	_lock.lock()
	if _organic == null:
		_organic = load("res://src/world/shaders/organic.gdshader")
		_crystal = load("res://src/world/shaders/crystal.gdshader")
	_lock.unlock()

## Builds the mesh, or returns null for types this class does not draw.
static func build(t: String, sp: int, v: int) -> ArrayMesh:
	match t:
		"glowcap": return _mushroom(Flora.species(t, sp), _rng(sp, v))
		"crystal_tree": return _crystal_tree(Flora.species(t, sp), _rng(sp, v))
		"solar_mast": return _xeno(sp, _rng(sp, v))
		"aether_crystal": return _crystal_cluster(sp, _rng(sp, v))
	return null

static func _rng(sp: int, v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(sp, 9100 + v)
	return r

static func glow_colour(bucket: int) -> Color:
	return Color.from_hsv(float(bucket % 12) / 12.0, 0.65, 1.0)

static func organic(a: Color, b: Color, opts := {}) -> ShaderMaterial:
	_shaders()
	var m := ShaderMaterial.new()
	m.shader = _organic
	m.set_shader_parameter("col_a", a)
	m.set_shader_parameter("col_b", b)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	return m

static func crystal(tint: Color, core: Color, glow: float, clarity := 0.8) -> ShaderMaterial:
	_shaders()
	var m := ShaderMaterial.new()
	m.shader = _crystal
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("clarity", clarity)
	return m

# --- Geometry --------------------------------------------------------------------

class Geo:
	var tools := {} ## key -> SurfaceTool
	var mats := {} ## key -> Material

	func add_mat(key: String, m: Material) -> void:
		mats[key] = m

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		return tools[key]

	## One triangle; the winding is chosen from the normals, so callers need not care.
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, col := Color.WHITE) -> void:
		var st := _st(key)
		var face := (b - a).cross(c - a)
		if face.dot(na + nb + nc) > 0.0:
			# Godot's front faces are clockwise seen from the front: swap b and c.
			var tv := b; b = c; c = tv
			var tn := nb; nb = nc; nc = tn
			var tu := ub; ub = uc; uc = tu
		for e in [[a, na, ua], [b, nb, ub], [c, nc, uc]]:
			st.set_normal(e[1])
			st.set_uv(e[2])
			st.set_color(col)
			st.add_vertex(e[0])

	func flat_tri(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col := Color.WHITE) -> void:
		var n := (b - a).cross(c - a).normalized()
		if n.dot(outward) < 0.0:
			n = -n
		tri(key, a, b, c, n, n, n, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), col)

	## Revolves a profile of (radius, height) points about the y axis. The surface faces
	## to the left of the direction of travel (so trace caps outward over the top and
	## back under, stems from top to bottom). `bend` leans it: x/z offset per (y/top)^2.
	func lathe(key: String, prof: PackedVector2Array, segs: int, xf: Transform3D, bend := Vector2.ZERO, col := Color.WHITE, wobble := 0.0, seed := 0) -> void:
		var n := prof.size()
		var top := 0.0
		for p in prof:
			top = maxf(top, absf(p.y))
		top = maxf(top, 0.01)
		# Normals and arc-length v coordinates along the profile.
		var nrm := PackedVector2Array()
		var vv := PackedFloat32Array()
		var acc := 0.0
		for i in n:
			var a := prof[maxi(i - 1, 0)]
			var b := prof[mini(i + 1, n - 1)]
			var t := (b - a).normalized()
			nrm.append(Vector2(-t.y, t.x))
			if i > 0:
				acc += prof[i].distance_to(prof[i - 1])
			vv.append(acc)
		var total := maxf(acc, 0.001)
		var rings: Array = []
		for i in n:
			var ring: Array = []
			for s in segs + 1:
				var ang := TAU * s / segs
				var cs := cos(ang)
				var sn := sin(ang)
				var r := prof[i].x
				if wobble > 0.0 and r > 0.001:
					r *= 1.0 + wobble * sin(ang * 3.0 + seed + prof[i].y * 1.7) * sin(ang * 5.0 - seed * 0.7)
				var y := prof[i].y
				var k := (y / top) * (y / top)
				var p := Vector3(r * cs + bend.x * k, y, r * sn + bend.y * k)
				var nn := Vector3(nrm[i].x * cs, nrm[i].y, nrm[i].x * sn).normalized()
				ring.append([xf * p, (xf.basis * nn).normalized(), Vector2(float(s) / segs, vv[i] / total)])
			rings.append(ring)
		for i in n - 1:
			for s in segs:
				var p00: Array = rings[i][s]
				var p01: Array = rings[i][s + 1]
				var p10: Array = rings[i + 1][s]
				var p11: Array = rings[i + 1][s + 1]
				tri(key, p00[0], p10[0], p11[0], p00[1], p10[1], p11[1], p00[2], p10[2], p11[2], col)
				tri(key, p00[0], p11[0], p01[0], p00[1], p11[1], p01[1], p00[2], p11[2], p01[2], col)

	## A tube swept along a curve (parallel-transported frames), radius per point.
	func sweep(key: String, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col := Color.WHITE, cap_end := true) -> void:
		var n := pts.size()
		var up := Vector3.UP if absf((pts[1] - pts[0]).normalized().y) < 0.95 else Vector3.RIGHT
		var t0 := (pts[1] - pts[0]).normalized()
		var side := t0.cross(up).normalized()
		var rings: Array = []
		var acc := 0.0
		for i in n:
			var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			side = (side - t * side.dot(t)).normalized()
			var bin := t.cross(side)
			if i > 0:
				acc += pts[i].distance_to(pts[i - 1])
			var ring: Array = []
			for s in sides + 1:
				var a := TAU * s / sides
				var d := side * cos(a) + bin * sin(a)
				ring.append([pts[i] + d * radii[i], d, Vector2(float(s) / sides, acc)])
			rings.append(ring)
		for i in n - 1:
			for s in sides:
				var p00: Array = rings[i][s]
				var p01: Array = rings[i][s + 1]
				var p10: Array = rings[i + 1][s]
				var p11: Array = rings[i + 1][s + 1]
				tri(key, p00[0], p10[0], p11[0], p00[1], p10[1], p11[1], p00[2] / Vector2(1, maxf(acc, 0.01)), p10[2] / Vector2(1, maxf(acc, 0.01)), p11[2] / Vector2(1, maxf(acc, 0.01)), col)
				tri(key, p00[0], p11[0], p01[0], p00[1], p11[1], p01[1], p00[2] / Vector2(1, maxf(acc, 0.01)), p11[2] / Vector2(1, maxf(acc, 0.01)), p01[2] / Vector2(1, maxf(acc, 0.01)), col)
		if cap_end and radii[n - 1] > 0.001:
			var tip := pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * radii[n - 1] * 0.6
			var tn := (pts[n - 1] - pts[n - 2]).normalized()
			for s in sides:
				var p0: Array = rings[n - 1][s]
				var p1: Array = rings[n - 1][s + 1]
				tri(key, p0[0], p1[0], tip, (p0[1] + tn).normalized(), (p1[1] + tn).normalized(), tn, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 1), col)

	## A two-sided strip along a curve (petals, fronds, hanging filaments). `widths` per
	## point; `curl` lifts the edges so the strip is gently cupped.
	func ribbon(key: String, pts: PackedVector3Array, widths: PackedFloat32Array, side0: Vector3, col := Color.WHITE, curl := 0.0) -> void:
		var n := pts.size()
		var side := side0.normalized()
		var rows: Array = []
		for i in n:
			var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			side = (side - t * side.dot(t)).normalized()
			var nrm := t.cross(side).normalized()
			var w := widths[i]
			var v := float(i) / (n - 1)
			var l := pts[i] - side * w + nrm * curl * w
			var c := pts[i] + nrm * (-curl * w * 0.3)
			var r := pts[i] + side * w + nrm * curl * w
			rows.append([[l, (nrm + side * curl).normalized(), Vector2(0, v)], [c, nrm, Vector2(0.5, v)], [r, (nrm - side * curl).normalized(), Vector2(1, v)]])
		for i in n - 1:
			for j in 2:
				var a: Array = rows[i][j]
				var b: Array = rows[i][j + 1]
				var c: Array = rows[i + 1][j]
				var d: Array = rows[i + 1][j + 1]
				for f in [1.0, -1.0]:
					tri(key, a[0], c[0], d[0], a[1] * f, c[1] * f, d[1] * f, a[2], c[2], d[2], col)
					tri(key, a[0], d[0], b[0], a[1] * f, d[1] * f, b[1] * f, a[2], d[2], b[2], col)

	## A faceted crystal: a `sides`-gon prism with a pyramid tip, flat normals.
	func prism(key: String, base: Vector3, dir: Vector3, radius: float, length: float, sides := 6, tip := 0.3, twist := 0.0, col := Color.WHITE) -> void:
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var bin := dir.cross(side)
		var body := length * (1.0 - tip)
		var lo: Array = []
		var hi: Array = []
		for s in sides:
			var a := TAU * s / sides + twist
			var d := side * cos(a) + bin * sin(a)
			lo.append(base + d * radius * 0.92)
			hi.append(base + dir * body + d * radius)
		var apex := base + dir * length
		for s in sides:
			var s1 := (s + 1) % sides
			var mid: Vector3 = (lo[s] + lo[s1] + hi[s] + hi[s1]) * 0.25 - (base + dir * body * 0.5)
			flat_tri(key, lo[s], hi[s], hi[s1], mid, col)
			flat_tri(key, lo[s], hi[s1], lo[s1], mid, col)
			var tm: Vector3 = (hi[s] + hi[s1] + apex) / 3.0 - (base + dir * body)
			flat_tri(key, hi[s], apex, hi[s1], tm, col)
			flat_tri(key, lo[s], lo[s1], base, -dir, col)

	func commit() -> ArrayMesh:
		var out := ArrayMesh.new()
		for key in tools:
			var st: SurfaceTool = tools[key]
			st.generate_tangents()
			st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, mats.get(key))
		return out

# --- Mushrooms -------------------------------------------------------------------

## Cap profiles, top centre -> rim -> underside -> stem, in units of the cap radius.
## Returns [top+lip points, underside points].
static func _cap_profile(kind: String, sr: float) -> Array:
	var top := PackedVector2Array()
	var under := PackedVector2Array()
	match kind:
		"dome":
			for i in 9:
				var a := PI * 0.5 * i / 8.0
				top.append(Vector2(sin(a), 0.55 * cos(a)))
			top.append(Vector2(1.02, -0.04))
			under = PackedVector2Array([Vector2(0.97, -0.09), Vector2(0.75, -0.12), Vector2(0.45, -0.13), Vector2(sr * 1.3, -0.11), Vector2(sr, -0.17)])
		"flat":
			top = PackedVector2Array([Vector2(0, 0.2), Vector2(0.12, 0.215), Vector2(0.25, 0.18), Vector2(0.45, 0.13), Vector2(0.7, 0.07), Vector2(0.92, 0.0), Vector2(1.0, -0.035)])
			under = PackedVector2Array([Vector2(0.97, -0.075), Vector2(0.75, -0.08), Vector2(0.45, -0.085), Vector2(sr * 1.25, -0.07), Vector2(sr, -0.13)])
		"cone":
			top = PackedVector2Array([Vector2(0, 1.3), Vector2(0.08, 1.2), Vector2(0.2, 0.95), Vector2(0.38, 0.6), Vector2(0.56, 0.28), Vector2(0.72, 0.04), Vector2(0.78, -0.06)])
			under = PackedVector2Array([Vector2(0.72, -0.07), Vector2(0.55, 0.08), Vector2(0.36, 0.3), Vector2(sr * 1.2, 0.35), Vector2(sr, 0.25)])
		"bell":
			top = PackedVector2Array([Vector2(0, 0.95), Vector2(0.28, 0.9), Vector2(0.52, 0.76), Vector2(0.68, 0.5), Vector2(0.75, 0.22), Vector2(0.84, 0.0), Vector2(0.9, -0.08)])
			under = PackedVector2Array([Vector2(0.84, -0.09), Vector2(0.7, 0.1), Vector2(0.58, 0.38), Vector2(0.38, 0.56), Vector2(sr * 1.15, 0.55), Vector2(sr, 0.45)])
		"funnel":
			top = PackedVector2Array([Vector2(0, 0.06), Vector2(0.25, 0.1), Vector2(0.5, 0.24), Vector2(0.75, 0.42), Vector2(0.95, 0.6), Vector2(1.03, 0.66), Vector2(1.04, 0.6)])
			under = PackedVector2Array([Vector2(0.95, 0.5), Vector2(0.72, 0.3), Vector2(0.45, 0.1), Vector2(sr * 1.4, -0.04), Vector2(sr, -0.14)])
	return [top, under]

static func _mushroom(p: Dictionary, r: RandomNumberGenerator) -> ArrayMesh:
	var g := Geo.new()
	# Natural, slightly muted tones read as real; full saturation reads as a toy.
	var cap_col: Color = p["cap_col"]
	cap_col = Color.from_hsv(cap_col.h, cap_col.s * 0.72, cap_col.v * 0.9)
	var stem_col: Color = p["stem_col"]
	stem_col = Color.from_hsv(stem_col.h, stem_col.s * 0.6, stem_col.v * 0.92)
	var gcol := glow_colour(int(p["glow"]))
	var spots: int = p["spots"]
	var luminous := r.randf() < 0.55
	g.add_mat("cap", organic(cap_col.darkened(0.25), cap_col.lightened(0.15), {
		"spot_amt": clampf(spots / 12.0, 0.0, 1.0), "spot_col": cap_col.lightened(0.6).lerp(gcol, 0.4),
		"spot_glow": 0.9 if luminous else 0.0, "glow_col": gcol, "sss": 0.55, "rough": 0.5, "streaks": 0.12, "spot_scale": 1.1}))
	g.add_mat("gill", organic(cap_col.darkened(0.55), cap_col.darkened(0.2).lerp(gcol, 0.3), {
		"glow": 0.9 if luminous else 0.15, "glow_col": gcol, "sss": 0.4, "streaks": 0.7}))
	g.add_mat("stem", organic(stem_col.darkened(0.3), stem_col, {"sss": 0.35, "rough": 0.7, "streaks": 0.45}))
	var kind := String(p["cap"])
	var heads: int = p["heads"]
	for hd in heads:
		var sc := 1.0 if hd == 0 else r.randf_range(0.4, 0.7)
		var off := Vector3.ZERO if hd == 0 else Vector3.FORWARD.rotated(Vector3.UP, r.randf() * TAU) * float(p["cap_r"]) * r.randf_range(0.7, 1.1)
		_shroom(g, kind, off, float(p["height"]) * sc * r.randf_range(0.9, 1.1), float(p["stem_r"]) * sc, float(p["cap_r"]) * sc * r.randf_range(0.9, 1.1),
			Vector2(float(p["bend"]), float(p["bend"]) * r.randf_range(-0.6, 0.6)) * float(p["height"]) * sc * 0.5, r, hd == 0)
	# A ring of little ones at the foot.
	for n in r.randi_range(1, 5):
		var a := r.randf() * TAU
		var pos := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.9, 2.2)
		var hh := r.randf_range(0.25, 0.6)
		_shroom(g, "dome" if kind != "funnel" else "funnel", pos, hh, hh * 0.12, hh * r.randf_range(0.45, 0.7), Vector2(r.randf_range(-0.1, 0.1), r.randf_range(-0.1, 0.1)), r, false)
	return g.commit()

static func _shroom(g: Geo, kind: String, at: Vector3, h: float, sr: float, cr: float, bend: Vector2, r: RandomNumberGenerator, big: bool) -> void:
	var xf := Transform3D(Basis(), at)
	var segs := 28 if big else 12
	# Stem: top to bottom, flaring into a bulb that sinks into the ground.
	var stem := PackedVector2Array([Vector2(sr * 0.82, h), Vector2(sr * 0.88, h * 0.9), Vector2(sr * 0.97, h * 0.65), Vector2(sr * 1.02, h * 0.4),
		Vector2(sr * 1.15, h * 0.2), Vector2(sr * 1.45, h * 0.07), Vector2(sr * 1.62, h * 0.015), Vector2(sr * 1.5, -0.25)])
	g.lathe("stem", stem, segs, xf, bend, Color.WHITE, 0.06 if big else 0.0, r.randi() % 100)
	if big and kind in ["dome", "flat", "bell"] and r.randf() < 0.6:
		# A skirt (annulus) hanging from the stem below the cap.
		var y := h * 0.8
		var ring := PackedVector2Array([Vector2(sr * 1.0, y + 0.06), Vector2(sr * 1.6, y - 0.08), Vector2(sr * 1.75, y - 0.2), Vector2(sr * 1.65, y - 0.22), Vector2(sr * 1.4, y - 0.1), Vector2(sr * 0.98, y - 0.02)])
		var k := 0.8 * 0.8
		g.lathe("stem", ring, segs, Transform3D(Basis(), at + Vector3(bend.x * k, 0, bend.y * k)))
	var prof: Array = _cap_profile(kind, sr / cr)
	var top: PackedVector2Array = prof[0]
	var under: PackedVector2Array = prof[1]
	var head := at + Vector3(bend.x, h, bend.y)
	var tilt := Basis(Vector3(bend.y, 0, -bend.x).normalized(), clampf(bend.length() / maxf(h, 0.1), 0.0, 0.35)) if bend.length() > 0.01 else Basis()
	var cxf := Transform3D(tilt.scaled(Vector3(cr, cr, cr)), head - Vector3(0, cr * 0.05, 0))
	g.lathe("cap", top, segs, cxf, Vector2.ZERO, Color.WHITE, 0.035 if big else 0.0, r.randi() % 100)
	var und := PackedVector2Array([top[top.size() - 1]])
	und.append_array(under)
	g.lathe("cap" if kind == "funnel" else "gill", und, segs, cxf)
	if big and kind != "funnel":
		# Gills: thin radial blades between the underside and the stem.
		var blades := 56
		for b in blades:
			var a := TAU * (b + 0.5) / blades
			var d := Vector3(cos(a), 0, sin(a))
			var pts: Array = []
			for i in 6:
				var rr := lerpf(under[under.size() - 2].x, under[0].x * 0.96, i / 5.0)
				var yy := _under_y(under, rr)
				var depth := 0.07 * sin(PI * i / 5.0) + 0.005
				pts.append([cxf * (d * rr + Vector3(0, yy - 0.004, 0)), cxf * (d * rr + Vector3(0, yy - depth, 0))])
			var side := cxf.basis * Vector3(-sin(a), 0, cos(a))
			for i in 5:
				g.tri("gill", pts[i][0], pts[i + 1][0], pts[i + 1][1], side, side, side)
				g.tri("gill", pts[i][0], pts[i + 1][1], pts[i][1], side, side, side)
				g.tri("gill", pts[i][0], pts[i + 1][0], pts[i + 1][1], -side, -side, -side)
				g.tri("gill", pts[i][0], pts[i + 1][1], pts[i][1], -side, -side, -side)

static func _under_y(under: PackedVector2Array, rr: float) -> float:
	for i in under.size() - 1:
		var a := under[i]
		var b := under[i + 1]
		if (rr <= a.x and rr >= b.x) or (rr >= a.x and rr <= b.x):
			return lerpf(a.y, b.y, (rr - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.0001 else 0.0)
	return under[under.size() - 1].y

# --- Crystal trees and clusters --------------------------------------------------

static func _crystal_tree(p: Dictionary, r: RandomNumberGenerator) -> ArrayMesh:
	var g := Geo.new()
	var gcol := glow_colour(int(p["glow"]))
	var bark: Color = p["bark"]
	g.add_mat("trunk", crystal(bark.lerp(gcol, 0.25).darkened(0.2), gcol.darkened(0.3), 0.35, 0.5))
	g.add_mat("shard", crystal(gcol.lerp(Color.WHITE, 0.15), gcol.lerp(Color.WHITE, 0.6), 1.0))
	g.add_mat("rock", Materials.get_mat("stone_dark"))
	g.add_mat("veil", organic(gcol.darkened(0.4), gcol.lightened(0.3), {"glow": 0.7, "glow_col": gcol, "sss": 0.8, "rough": 0.4, "streaks": 0.0, "sway": 0.6}))
	var h: float = p["height"] * r.randf_range(0.9, 1.1)
	var gi: float = p["girth"]
	var twist: float = p["twist"]
	# Rocky root mass.
	var root := PackedVector2Array([Vector2(0, gi * 2.2), Vector2(gi * 1.6, gi * 1.6), Vector2(gi * 2.8, gi * 0.5), Vector2(gi * 3.2, -0.1), Vector2(gi * 3.0, -0.6)])
	g.lathe("rock", root, 14, Transform3D.IDENTITY, Vector2.ZERO, Color(0.55, 0.52, 0.58), 0.25, r.randi() % 100)
	# Trunk: three to five crystal columns twisting around each other.
	var cols := r.randi_range(3, 5)
	var crown := Vector3(r.randf_range(-0.4, 0.4), h, r.randf_range(-0.4, 0.4))
	for c in cols:
		var a0 := TAU * c / cols
		var segs := 4
		var prev := Vector3(cos(a0), 0, sin(a0)) * gi * 0.9
		for s in segs:
			var t := float(s + 1) / segs
			var a := a0 + twist * 3.0 * t
			var rad := gi * 0.9 * (1.0 - 0.55 * t)
			var nxt := crown * t + Vector3(cos(a), 0, sin(a)) * rad
			var rr := gi * 0.55 * (1.0 - 0.45 * t)
			g.prism("trunk", prev - (nxt - prev).normalized() * 0.15, nxt - prev, rr, prev.distance_to(nxt) + 0.4, 6, 0.0, a)
			prev = nxt
	# Crown: a burst of shards, longest upward, with a few side clusters on the way up.
	var spikes: int = p["spikes"] * 2 + 6
	var sl: float = p["spike_len"]
	for n in spikes:
		var a := r.randf() * TAU
		var up := r.randf_range(0.25, 1.0)
		var dir := Vector3(cos(a) * (1.0 - up), up + 0.15, sin(a) * (1.0 - up))
		g.prism("shard", crown + dir.normalized() * gi * 0.3 - Vector3(0, r.randf() * 0.5, 0), dir, r.randf_range(0.07, 0.2) * (0.6 + sl * 0.3), sl * r.randf_range(0.5, 1.3), 6, r.randf_range(0.25, 0.45), r.randf() * TAU)
	for n in r.randi_range(1, 3):
		var at := crown * r.randf_range(0.35, 0.75)
		var a := r.randf() * TAU
		for m in r.randi_range(3, 6):
			var dir := Vector3(cos(a), r.randf_range(0.3, 1.0), sin(a)) + Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
			g.prism("shard", at + Vector3(cos(a), 0, sin(a)) * gi * 0.5, dir, r.randf_range(0.05, 0.12), sl * r.randf_range(0.3, 0.6), 6, 0.35, r.randf())
	# Ghostly veils hanging from the crown.
	if p["moss"]:
		for n in r.randi_range(8, 18):
			var a := r.randf() * TAU
			var start := crown + Vector3(cos(a), 0, sin(a)) * r.randf_range(0.3, sl * 0.8) + Vector3(0, r.randf_range(-0.2, 0.6), 0)
			var length := r.randf_range(1.0, h * 0.55)
			var pts := PackedVector3Array()
			var ws := PackedFloat32Array()
			for i in 7:
				var t := i / 6.0
				pts.append(start + Vector3(sin(t * 3.0 + a) * 0.15, -length * t, cos(t * 2.0 + a) * 0.15))
				ws.append(lerpf(0.09, 0.015, t))
			g.ribbon("veil", pts, ws, Vector3(cos(a + PI / 2), 0, sin(a + PI / 2)))
	return g.commit()

## Aether crystal ore: a dark boulder split open by a fan of glowing crystals.
static func _crystal_cluster(sp: int, r: RandomNumberGenerator) -> ArrayMesh:
	var g := Geo.new()
	var hue := r.randf_range(0.45, 0.62) if r.randf() < 0.7 else r.randf_range(0.72, 0.9)
	var tint := Color.from_hsv(hue, 0.55, 0.95)
	g.add_mat("shard", crystal(tint, tint.lerp(Color.WHITE, 0.6), 1.2))
	g.add_mat("rock", Materials.get_mat("stone_dark"))
	var rock := PackedVector2Array([Vector2(0, 0.55), Vector2(0.45, 0.5), Vector2(0.85, 0.3), Vector2(1.05, 0.05), Vector2(1.0, -0.3)])
	g.lathe("rock", rock, 14, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.8)), Vector3.ZERO), Vector2.ZERO, Color.WHITE, 0.22, r.randi() % 100)
	var n := r.randi_range(7, 14)
	var lean := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
	for i in n:
		var a := r.randf() * TAU
		var spread := r.randf_range(0.0, 0.8)
		var dir := (Vector3(cos(a) * spread, 1.0, sin(a) * spread) + lean).normalized()
		var big := 1.0 if i < 3 else r.randf_range(0.35, 0.75)
		g.prism("shard", Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.45) + Vector3(0, 0.25, 0), dir, 0.16 * big + 0.05, r.randf_range(0.8, 1.8) * big + 0.3, 6, r.randf_range(0.2, 0.4), r.randf() * TAU)
	return g.commit()

# --- Alien plants (sci-fi wilds) -------------------------------------------------

const XENO_FORMS := ["bloom", "weeper", "tube", "frond", "pod"]
const XENO_NOUNS := {"bloom": "Xeno Bloom", "weeper": "Weeper", "tube": "Tubecoral", "frond": "Coilfrond", "pod": "Podstalk"}

static func xeno_form(sp: int) -> String:
	return XENO_FORMS[WHash.combine(sp, 51) % XENO_FORMS.size()]

static func _xeno(sp: int, r: RandomNumberGenerator) -> ArrayMesh:
	var p := Flora.species("solar_mast", sp)
	var g := Geo.new()
	var hue := r.randf()
	var body := Color.from_hsv(hue, r.randf_range(0.35, 0.7), r.randf_range(0.35, 0.65))
	var accent := Color.from_hsv(fposmod(hue + r.randf_range(0.3, 0.6), 1.0), 0.7, 1.0)
	var gcol := glow_colour(int(p["glow"]))
	g.add_mat("body", organic(body.darkened(0.35), body, {"sss": 0.5, "rough": 0.55, "streaks": 0.5, "sway": 0.25}))
	g.add_mat("flesh", organic(body.lerp(accent, 0.5), accent, {"sss": 0.9, "rough": 0.4, "glow": 0.25, "glow_col": accent, "streaks": 0.2, "sway": 0.35}))
	g.add_mat("light", organic(gcol, gcol.lightened(0.4), {"sss": 1.0, "glow": 1.4, "glow_col": gcol, "rough": 0.3, "streaks": 0.0, "sway": 0.35}))
	var h: float = clampf(float(p["height"]) * 0.6, 2.0, 7.0)
	match xeno_form(sp):
		"bloom": _bloom(g, h, r)
		"weeper": _weeper(g, h, r)
		"tube": _tubes(g, h, r)
		"frond": _fronds(g, h, r)
		_: _pods(g, h, r)
	return g.commit()

static func _curve(from: Vector3, to: Vector3, lift: Vector3, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var t := float(i) / (n - 1)
		pts.append(from.lerp(to, t) + lift * sin(PI * t))
	return pts

static func _taper(n: int, a: float, b: float, bulge := 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		var t := float(i) / (n - 1)
		out.append(lerpf(a, b, t) * (1.0 + bulge * sin(PI * t)))
	return out

static func _bloom(g: Geo, h: float, r: RandomNumberGenerator) -> void:
	var lean := Vector3(r.randf_range(-0.8, 0.8), 0, r.randf_range(-0.8, 0.8))
	var top := Vector3(0, h, 0) + lean
	g.sweep("body", _curve(Vector3(0, -0.3, 0), top, lean * -0.3 + Vector3(0, 0, 0), 10), _taper(10, h * 0.07 + 0.08, h * 0.035, 0.25), 10)
	var petals := r.randi_range(5, 9)
	var pl := h * r.randf_range(0.28, 0.42)
	for i in petals:
		var a := TAU * i / petals + r.randf_range(-0.1, 0.1)
		var out := Vector3(cos(a), 0, sin(a))
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for k in 8:
			var t := k / 7.0
			# Up out of the cup, then curling outward and down at the tip.
			pts.append(top + out * pl * t + Vector3(0, pl * (0.55 * sin(t * PI * 0.8) - 0.25 * t * t), 0))
			ws.append(pl * 0.22 * sin(PI * minf(t * 1.1, 1.0)) + 0.02)
		g.ribbon("flesh", pts, ws, Vector3(-sin(a), 0, cos(a)), Color.WHITE, 0.35)
	g.lathe("light", _ellipse(h * 0.07, h * 0.06, 8), 12, Transform3D(Basis(), top + Vector3(0, h * 0.04, 0)))
	for i in r.randi_range(5, 10):
		var a := r.randf() * TAU
		var tip := top + Vector3(cos(a) * pl * 0.25, pl * r.randf_range(0.35, 0.6), sin(a) * pl * 0.25)
		g.sweep("body", _curve(top, tip, Vector3.ZERO, 4), _taper(4, 0.025, 0.012), 5)
		g.lathe("light", _ellipse(0.045, 0.045, 5), 6, Transform3D(Basis(), tip))
	_leaves(g, r, h * 0.35, 3)

static func _weeper(g: Geo, h: float, r: RandomNumberGenerator) -> void:
	var trunk := PackedVector2Array([Vector2(h * 0.05, h * 0.8), Vector2(h * 0.09, h * 0.65), Vector2(h * 0.11, h * 0.4), Vector2(h * 0.08, h * 0.2), Vector2(h * 0.13, h * 0.05), Vector2(h * 0.16, -0.3)])
	g.lathe("body", trunk, 14, Transform3D.IDENTITY, Vector2.ZERO, Color.WHITE, 0.12, r.randi() % 100)
	var arms := r.randi_range(6, 11)
	for i in arms:
		var a := TAU * i / arms + r.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var from := Vector3(0, h * r.randf_range(0.6, 0.8), 0)
		var reach := h * r.randf_range(0.35, 0.6)
		var pts := PackedVector3Array()
		for k in 10:
			var t := k / 9.0
			# Up and out, then weeping down toward the ground.
			pts.append(from + out * reach * t + Vector3(0, h * (0.35 * sin(t * PI * 0.9) - 0.75 * t * t * t), 0))
		g.sweep("flesh", pts, _taper(10, h * 0.025, h * 0.008), 6, Color.WHITE, false)
		g.lathe("light", _ellipse(h * 0.035, h * 0.06, 7), 8, Transform3D(Basis(), pts[9] - Vector3(0, h * 0.05, 0)))
	g.lathe("light", _ellipse(h * 0.07, h * 0.09, 8), 12, Transform3D(Basis(), Vector3(0, h * 0.84, 0)))

static func _tubes(g: Geo, h: float, r: RandomNumberGenerator) -> void:
	var n := r.randi_range(5, 12)
	for i in n:
		var a := r.randf() * TAU
		var d := r.randf_range(0.0, h * 0.25)
		var th := h * r.randf_range(0.35, 1.0)
		var tr := th * r.randf_range(0.06, 0.11)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		# Outer wall up, lip, inner wall down: a hollow tube.
		var prof := PackedVector2Array([Vector2(tr * 0.75, th - tr * 1.2), Vector2(tr * 0.85, th - 0.02), Vector2(tr, th), Vector2(tr * 1.1, th * 0.85), Vector2(tr * 0.95, th * 0.5), Vector2(tr * 1.2, th * 0.1), Vector2(tr * 1.4, -0.3)])
		prof.reverse()
		var bend := Vector2(r.randf_range(-0.3, 0.3), r.randf_range(-0.3, 0.3)) * th * 0.3
		g.lathe("body", prof, 12, Transform3D(Basis(), at), bend)
		var lip := PackedVector2Array([Vector2(tr * 0.95, th + 0.01), Vector2(tr * 0.7, th - tr * 0.6), Vector2(tr * 0.3, th - tr * 1.6), Vector2(0, th - tr * 1.8)])
		lip.reverse()
		g.lathe("light", lip, 12, Transform3D(Basis(), at), bend)

static func _fronds(g: Geo, h: float, r: RandomNumberGenerator) -> void:
	var n := r.randi_range(4, 8)
	for i in n:
		var a := TAU * i / n + r.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var fh := h * r.randf_range(0.6, 1.0)
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		var steps := 16
		for k in steps:
			var t := float(k) / (steps - 1)
			# Rising, leaning out, the last third coiled into a fiddlehead.
			var coil := smoothstep(0.62, 1.0, t)
			var ang := coil * TAU * 0.85
			var rad := fh * 0.18 * (1.0 - coil * 0.7)
			var base := out * fh * 0.3 * t + Vector3(0, fh * minf(t, 0.7), 0)
			var curl := out * (sin(ang) * rad) + Vector3(0, (cos(ang) - 1.0) * rad * -1.0, 0) * coil
			pts.append(base + curl * coil)
			ws.append(fh * 0.08 * (1.0 - t * 0.7))
		g.ribbon("flesh", pts, ws, Vector3(-sin(a), 0, cos(a)), Color.WHITE, 0.25)
		g.sweep("body", pts, _taper(steps, fh * 0.012, fh * 0.004), 5, Color.WHITE, false)
		g.lathe("light", _ellipse(fh * 0.03, fh * 0.03, 5), 6, Transform3D(Basis(), pts[steps - 1]))

static func _pods(g: Geo, h: float, r: RandomNumberGenerator) -> void:
	var n := r.randi_range(3, 7)
	for i in n:
		var a := r.randf() * TAU
		var tip := Vector3(cos(a) * h * r.randf_range(0.1, 0.35), h * r.randf_range(0.5, 1.0), sin(a) * h * r.randf_range(0.1, 0.35))
		var base := Vector3(cos(a) * 0.2, -0.2, sin(a) * 0.2)
		g.sweep("body", _curve(base, tip, Vector3(cos(a + 1.5), 0, sin(a + 1.5)) * h * 0.08, 8), _taper(8, h * 0.035, h * 0.02), 7, Color.WHITE, false)
		var pr := h * r.randf_range(0.07, 0.13)
		g.lathe("flesh", _ellipse(pr, pr * 1.5, 10), 14, Transform3D(Basis(), tip + Vector3(0, pr * 1.2, 0)))
		g.lathe("light", _ellipse(pr * 0.55, pr * 0.9, 8), 10, Transform3D(Basis(), tip + Vector3(0, pr * 1.25, 0)))
	_leaves(g, r, h * 0.3, 4)

## Broad, drooping leaves at the foot of a plant.
static func _leaves(g: Geo, r: RandomNumberGenerator, size: float, count: int) -> void:
	for i in count + r.randi_range(0, 2):
		var a := r.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var pts := PackedVector3Array()
		var ws := PackedFloat32Array()
		for k in 7:
			var t := k / 6.0
			pts.append(out * size * t * 1.4 + Vector3(0, size * (0.5 * sin(t * PI * 0.7) - 0.3 * t * t), 0))
			ws.append(size * 0.28 * sin(PI * minf(t * 1.05, 1.0)) + 0.01)
		g.ribbon("body", pts, ws, Vector3(-sin(a), 0, cos(a)), Color.WHITE, 0.3)

## A closed ellipsoid profile (top to bottom) for lathing.
static func _ellipse(rx: float, ry: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := PI * i / n
		out.append(Vector2(sin(a) * rx, cos(a) * ry))
	return out
