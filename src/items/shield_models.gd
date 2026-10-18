class_name ShieldModels
## Shields, held by the grip behind the boss or by the strap: round, kite, heater, tower and buckler in wood, hide, bronze and steel; riot and ballistic shields; alien energy and crystal shields.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.
##
## Shields stand along +Y with their face on +Z and return the grip behind; things worn on
## the back (packs, jetpacks, wings, cloaks, quivers) stand along +Y with the side the
## icon shows on +Z and return the carry handle or strap.

const BUILD := {
	"shield_wood": "_shield_wood", "buckler_wood": "_buckler_wood", "shield_bronze": "_shield_bronze",
	"shield_hide": "_shield_hide", "shield_kite": "_shield_kite", "shield_tower": "_shield_tower",
	"shield_riot": "_shield_riot", "shield_ballistic": "_shield_ballistic",
	"shield_crystal": "_shield_crystal", "shield_emitter": "_shield_emitter",
	"shield_void": "_shield_void", "shield_prism": "_shield_prism",
	"backpack_canvas": "_backpack_canvas", "satchel": "_satchel", "pack_boiler": "_pack_boiler",
	"pack_recon": "_pack_recon", "oxygen_pack": "_oxygen_pack", "cloak_optic": "_cloak_optic",
	"jetpack_military": "_jetpack_military", "jetpack": "_jetpack", "wings_chitin": "_wings_chitin",
	"halo_pack": "_halo_pack", "cape_precursor": "_cape_precursor", "quiver": "_quiver",
	"ammo_belt": "_ammo_belt", "watch_tabard": "_watch_tabard",
}

const IRON := Color(0.5, 0.5, 0.5)
const STEEL := Color(0.66, 0.66, 0.67)
const BRASS := Color(0.7, 0.52, 0.26)
const LEATHER := Color(0.3, 0.16, 0.08)

# --- Surfaces ---------------------------------------------------------------------------

static func _c(col: Variant, p: Vector3) -> Color:
	return col.call(p) if col is Callable else col

## A surface through rows of points (a grid), smooth shaded: normals from neighbouring
## points, turned to face `dir` (or away from `centre` when dir is zero). `wrap` closes
## the rows round. `col` is a colour or col(p); `uvf(p)` gives the texture coordinate.
static func _grid(k: MeshKit, m: String, xf: Transform3D, rows: Array, wrap: bool, col: Variant, dir := Vector3.ZERO, centre := Vector3.ZERO, uvf: Variant = null) -> void:
	var nr := rows.size()
	var nc: int = (rows[0] as PackedVector3Array).size()
	var st := k._tool(m)
	var nb := xf.basis.inverse().transposed()
	var N: Array = []
	for i in nr:
		var r: PackedVector3Array = rows[i]
		var up: PackedVector3Array = rows[mini(i + 1, nr - 1)]
		var dn: PackedVector3Array = rows[maxi(i - 1, 0)]
		var rn := PackedVector3Array()
		for j in nc:
			var jn := (j + 1) % nc if wrap else mini(j + 1, nc - 1)
			var jp := (j - 1 + nc) % nc if wrap else maxi(j - 1, 0)
			var n := (r[jn] - r[jp]).cross(up[j] - dn[j])
			var want := dir if dir != Vector3.ZERO else r[j] - centre
			if n.length_squared() < 1e-14:
				n = want
			n = n.normalized()
			if n.dot(want) < 0.0:
				n = -n
			rn.append(n)
		N.append(rn)
	var span := nc if wrap else nc - 1
	for i in nr - 1:
		var a: PackedVector3Array = rows[i]
		var b: PackedVector3Array = rows[i + 1]
		var na: PackedVector3Array = N[i]
		var nb2: PackedVector3Array = N[i + 1]
		for j in span:
			var j2 := (j + 1) % nc
			var q := [a[j], a[j2], b[j2], b[j]]
			var qn := [na[j], na[j2], nb2[j2], nb2[j]]
			var qc := [_c(col, q[0]), _c(col, q[1]), _c(col, q[2]), _c(col, q[3])]
			var qu: Array = []
			for p: Vector3 in q:
				qu.append(uvf.call(p) if uvf is Callable else Vector2(p.x + p.z, p.y))
			Provisions._tri(st, xf, nb, [q[0], q[1], q[2]], [qn[0], qn[1], qn[2]], [qc[0], qc[1], qc[2]], [qu[0], qu[1], qu[2]])
			Provisions._tri(st, xf, nb, [q[0], q[2], q[3]], [qn[0], qn[2], qn[3]], [qc[0], qc[2], qc[3]], [qu[0], qu[2], qu[3]])

## A plate `th` thick whose face is the grid `front` (facing +Z): the back follows it and
## the cut edge is closed all round (rows wrapped round a centre, or an open grid).
static func _shell(k: MeshKit, m: String, xf: Transform3D, front: Array, th: float, wrap: bool, col: Variant, back_col: Variant, back_m := "", uvf: Variant = null) -> void:
	var back: Array = []
	for r: PackedVector3Array in front:
		var b := PackedVector3Array()
		for p in r:
			b.append(p - Vector3(0, 0, th))
		back.append(b)
	var bm := m if back_m == "" else back_m
	_grid(k, m, xf, front, wrap, col, Vector3.BACK, Vector3.ZERO, uvf)
	_grid(k, bm, xf, back, wrap, back_col, Vector3.FORWARD, Vector3.ZERO, uvf)
	var nr := front.size()
	var nc: int = (front[0] as PackedVector3Array).size()
	var loops: Array = [] # [front points, back points, inner neighbours, closed]
	var take := func(arr: Array, idx: Array) -> PackedVector3Array:
		var out := PackedVector3Array()
		for ij: Vector2i in idx:
			out.append((arr[ij.x] as PackedVector3Array)[ij.y])
		return out
	var edge := func(row_or_col: String, at: int, ref: int, count: int) -> Array:
		var e: Array = []
		var rr: Array = []
		for s in count:
			e.append(Vector2i(at, s) if row_or_col == "row" else Vector2i(s, at))
			rr.append(Vector2i(ref, s) if row_or_col == "row" else Vector2i(s, ref))
		return [e, rr]
	var sets: Array = [edge.call("row", nr - 1, nr - 2, nc)]
	var r0: PackedVector3Array = front[0]
	if not r0[0].is_equal_approx(r0[nc / 2]):
		sets.append(edge.call("row", 0, 1, nc))
	if not wrap:
		sets.append(edge.call("col", 0, 1, nr))
		sets.append(edge.call("col", nc - 1, nc - 2, nr))
	for s: Array in sets:
		loops.append([take.call(front, s[0]), take.call(back, s[0]), take.call(front, s[1]), wrap and (s[0] as Array).size() == nc])
	var st := k._tool(bm)
	var nbas := xf.basis.inverse().transposed()
	for l: Array in loops:
		var F: PackedVector3Array = l[0]
		var B: PackedVector3Array = l[1]
		var R: PackedVector3Array = l[2]
		var closed: bool = l[3]
		var n := F.size()
		var nrm := PackedVector3Array()
		for i in n:
			var t := F[(i + 1) % n if closed else mini(i + 1, n - 1)] - F[(i - 1 + n) % n if closed else maxi(i - 1, 0)]
			var o := Vector3(t.y, -t.x, 0.0).normalized()
			if o.dot(F[i] - R[i]) < 0.0:
				o = -o
			nrm.append(o)
		for i in (n if closed else n - 1):
			var i2 := (i + 1) % n
			var c0 := _c(back_col, F[i])
			var c1 := _c(back_col, F[i2])
			Provisions._tri(st, xf, nbas, [F[i], F[i2], B[i2]], [nrm[i], nrm[i2], nrm[i2]], [c0, c1, c1], [Vector2(F[i].x, F[i].y), Vector2(F[i2].x, F[i2].y), Vector2(B[i2].x, B[i2].y)])
			Provisions._tri(st, xf, nbas, [F[i], B[i2], B[i]], [nrm[i], nrm[i2], nrm[i]], [c0, c1, c0], [Vector2(F[i].x, F[i].y), Vector2(B[i2].x, B[i2].y), Vector2(B[i].x, B[i].y)])

## Rows from the centre `c` out to `outline` (`rings` of them), lifted to zf(point).
static func _radial(outline: PackedVector2Array, c: Vector2, rings: int, zf: Callable) -> Array:
	var rows: Array = []
	for i in rings + 1:
		var t := float(i) / rings
		var r := PackedVector3Array()
		for o in outline:
			var p := c.lerp(o, t)
			r.append(Vector3(p.x, p.y, zf.call(p)))
		rows.append(r)
	return rows

## A band between two outlines (inner and outer, same point count), lifted to zf + h.
static func _band_rows(inner: PackedVector2Array, outer: PackedVector2Array, zf: Callable, h: float) -> Array:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for i in inner.size():
		a.append(Vector3(inner[i].x, inner[i].y, zf.call(inner[i]) + h))
		b.append(Vector3(outer[i].x, outer[i].y, zf.call(outer[i]) + h))
	return [a, b]

static func _circle(r: float, n: int, c := Vector2.ZERO, sy := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * r, sin(a) * r * sy))
	return out

## A closed outline re-spaced to points about `step` apart (keeping its corners).
static func _resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for s in n:
			out.append(a.lerp(b, float(s) / n))
	return out

## The outline shrunk toward `c` by `d` (along each point's bisector, for bands).
static func _inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	var ccw := 0.0
	for i in n:
		ccw += poly[i].cross(poly[(i + 1) % n])
	var s := 1.0 if ccw > 0.0 else -1.0
	for i in n:
		var t := (poly[(i + 1) % n] - poly[(i - 1 + n) % n]).normalized()
		out.append(poly[i] + Vector2(-t.y, t.x) * d * s)
	return out

## A dome rivet head on the surface at `p` facing `n`.
static func _rivet(k: MeshKit, m: String, xf: Transform3D, p: Vector3, n: Vector3, r: float, col: Color) -> void:
	k.sphere(m, xf * Transform3D(Basis(Quaternion(Vector3.UP, n.normalized())), p), r, 4, 8, 0.0, 0.55, col, true)

## Normal of the surface z = zf(x, y) at p.
static func _zn(zf: Callable, p: Vector2) -> Vector3:
	var e := 0.002
	var dx: float = (zf.call(p + Vector2(e, 0)) - zf.call(p - Vector2(e, 0))) / (2.0 * e)
	var dy: float = (zf.call(p + Vector2(0, e)) - zf.call(p - Vector2(0, e))) / (2.0 * e)
	return Vector3(-dx, -dy, 1.0).normalized()

## Rivets along an outline, `n` of them evenly round it, on the surface zf + h.
static func _rivets_along(k: MeshKit, m: String, xf: Transform3D, poly: PackedVector2Array, count: int, zf: Callable, h: float, r: float, col: Color) -> void:
	var total := 0.0
	var lens := PackedFloat32Array()
	for i in poly.size():
		var l := poly[i].distance_to(poly[(i + 1) % poly.size()])
		lens.append(l)
		total += l
	for c in count:
		var want := total * (c + 0.5) / count
		var i := 0
		while i < poly.size() - 1 and want > lens[i]:
			want -= lens[i]
			i += 1
		var p := poly[i].lerp(poly[(i + 1) % poly.size()], clampf(want / maxf(lens[i], 1e-6), 0.0, 1.0))
		_rivet(k, m, xf, Vector3(p.x, p.y, zf.call(p) + h), _zn(zf, p), r, col)

## The rolled edge binding a shield's rim: a tube round the outline at mid-thickness.
static func _edge(k: MeshKit, m: String, xf: Transform3D, poly: PackedVector2Array, zf: Callable, mid: float, r: float, col: Color) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in poly.size() + 1:
		var p := poly[i % poly.size()]
		path.append(Vector3(p.x, p.y, zf.call(p) - mid))
		radii.append(r)
	ItemModels._tube(k, m, xf, path, radii, 8, col, false)

## A flat strap (a ribbon `w` wide and `th` thick) along `path`, its face toward `face`
## (one direction for all, or one per point).
static func _strap(k: MeshKit, m: String, xf: Transform3D, path: PackedVector3Array, face: Variant, w: float, th: float, col: Color) -> void:
	var n := path.size()
	var r0 := PackedVector3Array()
	var r1 := PackedVector3Array()
	var r2 := PackedVector3Array()
	var r3 := PackedVector3Array()
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var f: Vector3 = (face as PackedVector3Array)[i] if face is PackedVector3Array else face
		f = (f - t * f.dot(t)).normalized()
		var s := t.cross(f).normalized() * w * 0.5
		var h := f * th * 0.5
		r0.append(path[i] + h - s)
		r1.append(path[i] + h + s)
		r2.append(path[i] - h + s)
		r3.append(path[i] - h - s)
	var rows: Array = [r0, r1, r2, r3]
	for side in 4:
		var a: PackedVector3Array = rows[side]
		var b: PackedVector3Array = rows[(side + 1) % 4]
		for i in n - 1:
			var mid := (path[i] + path[i + 1]) * 0.5
			var out := ((a[i] + a[i + 1] + b[i] + b[i + 1]) * 0.25 - mid)
			ItemModels._quad(k, m, xf, a[i], a[i + 1], b[i + 1], b[i], out, col)

## A buckle: a square frame of bar `bar` thick, `w` by `h`, at `at` facing `n` with `up`.
static func _buckle(k: MeshKit, m: String, xf: Transform3D, at: Vector3, n: Vector3, up: Vector3, w: float, h: float, bar: float, col: Color) -> void:
	var z := n.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var b := Basis(x, y, z)
	var o := xf * Transform3D(b, at)
	k.box(m, o * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5 - bar * 0.5, 0)), Vector3(w, bar, bar), col)
	k.box(m, o * Transform3D(Basis.IDENTITY, Vector3(0, -h * 0.5 + bar * 0.5, 0)), Vector3(w, bar, bar), col)
	k.box(m, o * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - bar * 0.5, 0, 0)), Vector3(bar, h, bar), col)
	k.box(m, o * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + bar * 0.5, 0, 0)), Vector3(bar, h, bar), col)
	k.box(m, o * Transform3D(Basis.IDENTITY, Vector3(0, 0, bar * 0.3)), Vector3(bar * 0.6, h * 0.95, bar * 0.6), col.darkened(0.1))

## A shield boss: a flange `rf` wide round a dome `rd` across and `h` high, at the face
## point `p` (facing +Z), with `rivets` round the flange.
static func _boss(k: MeshKit, m: String, xf: Transform3D, p: Vector3, rf: float, rd: float, h: float, col: Color, rivets: int) -> void:
	var prof := PackedVector2Array([Vector2(rf, -0.004), Vector2(rf, 0.002), Vector2(rf * 0.97, 0.005), Vector2(rd * 1.02, 0.006),
		Vector2(rd, 0.008), Vector2(rd * 0.96, 0.008 + h * 0.3), Vector2(rd * 0.82, 0.008 + h * 0.62), Vector2(rd * 0.55, 0.008 + h * 0.88), Vector2(rd * 0.22, 0.008 + h * 0.99), Vector2(0.0, 0.008 + h)])
	Provisions.lathe(k, m, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), prof, 28, col)
	for i in rivets:
		var a := TAU * (i + 0.5) / rivets + PI * 0.5
		var q := p + Vector3(cos(a), sin(a), 0) * (rf + rd) * 0.5
		_rivet(k, m, xf, q + Vector3(0, 0, 0.004), Vector3.BACK, (rf - rd) * 0.28, col.lightened(0.08))

## Wood texture coordinates for a vertical plank centred on x = cx: the grain runs up it
## and the plank shows one board of the photo (not the seams between them).
static func _plank_uv(cx: float, board: int, off: float) -> Callable:
	var bc := 0.05 + 0.1 * board
	return func(p: Vector3) -> Vector2:
		return Vector2(p.y * 0.6 + off, bc + (p.x - cx) * 0.6)

## Vertical planks filling `outline`, `n` of them over [x0, x1], each its own board
## (a slightly different tone, height and grain) with a hairline gap between. `tone(x)`
## gives each plank's colour.
static func _planks(k: MeshKit, r: RandomNumberGenerator, xf: Transform3D, outline: PackedVector2Array, x0: float, x1: float, n: int, zf: Callable, th: float, tone: Callable, back: Color) -> void:
	var w := (x1 - x0) / n
	for i in n:
		var a := x0 + w * i + 0.0022
		var b := x0 + w * (i + 1) - 0.0022
		var y0 := -5.0
		var y1 := 5.0
		var rect := PackedVector2Array([Vector2(a, y0), Vector2(b, y0), Vector2(b, y1), Vector2(a, y1)])
		var cut := Geometry2D.intersect_polygons(outline, rect)
		if cut.is_empty():
			continue
		var poly: PackedVector2Array = cut[0]
		poly = _resample(poly, 0.03)
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		var dz := r.randf_range(-0.0015, 0.0015)
		var cx := (a + b) * 0.5
		var col: Color = tone.call(cx)
		col = col.lightened(r.randf_range(-0.06, 0.08)) if r.randf() < 0.5 else col.darkened(r.randf_range(0.0, 0.12))
		var z2 := func(p: Vector2) -> float:
			return zf.call(p) + dz
		var rows := _radial(poly, c, 6, z2)
		_shell(k, "own:wood", xf, rows, th, true, col, back, "", _plank_uv(cx, r.randi_range(0, 8), r.randf()))

# --- Round shields ----------------------------------------------------------------------

## A round shield of planks under an iron rim and boss, as the icon: `R` across the
## radius, `n` planks, a band `band` wide on the face with rivets, a domed boss.
static func _round(k: MeshKit, r: RandomNumberGenerator, R: float, n: int, wood: Color, iron: Color, band: float, boss: float, rivets: int, bulge: float) -> Vector3:
	var zf := func(p: Vector2) -> float:
		return bulge * (1.0 - p.length_squared() / (R * R))
	var th := 0.012
	var outline := _circle(R * 0.995, 72)
	var tone := func(_x: float) -> Color:
		return wood
	_planks(k, r, Transform3D.IDENTITY, outline, -R, R, n, zf, th, tone, wood.darkened(0.3))
	# The dark glue line between the boards shows through the gaps.
	var under := func(p: Vector2) -> float:
		return zf.call(p) - 0.004
	_shell(k, "own:wood", Transform3D.IDENTITY, _radial(outline, Vector2.ZERO, 6, under), th - 0.006, true, wood.darkened(0.7), wood.darkened(0.5))
	# The iron rim: a flat band over the face, its edge rolled round to the back.
	var outer := _circle(R, 72)
	var inner := _circle(R - band, 72)
	_shell(k, "own:forged", Transform3D.IDENTITY, _band_rows(inner, outer, zf, 0.004), 0.006, true, iron, iron.darkened(0.2))
	_edge(k, "own:forged", Transform3D.IDENTITY, outer, zf, th * 0.5 - 0.002, th * 0.5 + 0.004, iron.darkened(0.1))
	_rivets_along(k, "own:forged", Transform3D.IDENTITY, _circle(R - band * 0.5, 72), rivets, zf, 0.004, band * 0.16, iron.lightened(0.1))
	# The boss over the hand.
	_boss(k, "own:forged", Transform3D.IDENTITY, Vector3(0, 0, bulge + 0.002), boss, boss * 0.66, boss * 0.5, iron, 4)
	# Behind: a grip bar across the hole under the boss.
	var gz := -th - 0.016
	k.bevel_box("own:wood", Transform3D(Basis.IDENTITY, Vector3(0, 0, gz)), Vector3(R * 1.3, 0.035, 0.022), 0.006, wood.darkened(0.25))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.06, 0, gz - 0.004), Vector3(0.06, 0, gz - 0.004)]), Vector3.FORWARD, 0.04, 0.004, LEATHER)
	return Vector3(0, 0, gz)

## A Viking-style round shield: five vertical planks of mid oak, a broad iron rim with a
## ring of rivets, a domed iron boss on a four-riveted flange. About 0.75 m across.
static func _shield_wood(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _round(k, r, 0.375, 6, Color(0.42, 0.29, 0.18), Color(0.5, 0.5, 0.52), 0.05, 0.11, 22, 0.02)

## A buckler: a small fist shield of dark reddish planks, a thin iron rim studded all round
## and a big domed boss filling the middle. 0.35 m across.
static func _buckler_wood(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _round(k, r, 0.175, 6, Color(0.34, 0.2, 0.12), Color(0.45, 0.45, 0.46), 0.014, 0.06, 26, 0.012)

## A bronze hoplite-style round shield: one dished sheet of hammered bronze with a raised
## ring and a riveted rim band, a boss on a flange; darker in the hollows, worn bright.
static func _shield_bronze(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var R := 0.36
	var bulge := 0.055
	var bronze := Color(0.6, 0.44, 0.22)
	var zf := func(p: Vector2) -> float:
		return bulge * (1.0 - p.length_squared() / (R * R))
	var col := func(p: Vector3) -> Color:
		var d := Vector2(p.x, p.y).length() / R
		return bronze.darkened(0.12 * d).lerp(Color(0.45, 0.3, 0.16), 0.25 * absf(sin(p.x * 31.0 + p.y * 17.0)) * d)
	_shell(k, "own:hammered", Transform3D.IDENTITY, _radial(_circle(R * 0.99, 72), Vector2.ZERO, 10, zf), 0.006, true, col, bronze.darkened(0.35))
	# A raised ring two thirds out and the rim band.
	_shell(k, "own:hammered", Transform3D.IDENTITY, _band_rows(_circle(R * 0.6, 72), _circle(R * 0.64, 72), zf, 0.004), 0.006, true, bronze.lightened(0.08), bronze)
	_shell(k, "own:hammered", Transform3D.IDENTITY, _band_rows(_circle(R * 0.9, 72), _circle(R, 72), zf, 0.004), 0.006, true, bronze.darkened(0.05), bronze)
	_edge(k, "own:hammered", Transform3D.IDENTITY, _circle(R, 72), zf, 0.0, 0.007, bronze.darkened(0.1))
	_rivets_along(k, "own:hammered", Transform3D.IDENTITY, _circle(R * 0.95, 72), 30, zf, 0.004, 0.0045, bronze.lightened(0.15))
	_boss(k, "own:hammered", Transform3D.IDENTITY, Vector3(0, 0, bulge), 0.1, 0.075, 0.05, bronze.lightened(0.05), 0)
	_shell(k, "own:hammered", Transform3D.IDENTITY, _band_rows(_circle(0.098, 48), _circle(0.108, 48), zf, 0.006), 0.006, true, bronze.lightened(0.1), bronze)
	_rivets_along(k, "own:hammered", Transform3D.IDENTITY, _circle(0.09, 48), 10, zf, 0.008, 0.003, bronze.lightened(0.15))
	# A leather arm strap and hand grip inside.
	var gz := -0.03
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.07, 0.0, -0.006), Vector3(-0.05, 0, gz), Vector3(0.05, 0, gz), Vector3(0.07, 0.0, -0.006)]), Vector3.FORWARD, 0.03, 0.005, LEATHER)
	return Vector3(0, 0, gz)

# --- Shaped shields ---------------------------------------------------------------------

## A kite outline: a gently arched top `w` wide at `top`, sides curving in to the point
## at `bottom`.
static func _kite_outline(w: float, top: float, bottom: float, arch: float, p: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var s := float(i) / n
		out.append(Vector2(w * 0.5 * (1.0 - pow(s, p)), lerpf(top, bottom, s)))
	for i in range(n - 1, -1, -1):
		var s := float(i) / n
		out.append(Vector2(-w * 0.5 * (1.0 - pow(s, p)), lerpf(top, bottom, s)))
	for i in range(1, 12):
		var s := float(i) / 12.0
		out.append(Vector2(lerpf(-w * 0.5, w * 0.5, s), top + arch * sin(s * PI)))
	return out

## A Norman kite shield: vertical planks painted half red, half white over a curved face,
## an iron rim band studded all round, a small boss high up. 0.9 m tall.
static func _shield_kite(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var w := 0.56
	var zf := func(p: Vector2) -> float:
		return -0.9 * p.x * p.x
	var outline := _kite_outline(w, 0.34, -0.56, 0.012, 2.3)
	var tone := func(x: float) -> Color:
		return Color(0.48, 0.13, 0.09) if x < 0.0 else Color(0.7, 0.66, 0.6)
	_planks(k, r, Transform3D.IDENTITY, outline, -w * 0.5, w * 0.5, 6, zf, 0.012, tone, Color(0.4, 0.28, 0.18))
	var inner := _inset(outline, 0.028)
	_shell(k, "own:forged", Transform3D.IDENTITY, _band_rows(inner, outline, zf, 0.004), 0.005, true, Color(0.42, 0.42, 0.43), Color(0.3, 0.3, 0.3))
	_edge(k, "own:forged", Transform3D.IDENTITY, outline, zf, 0.004, 0.009, Color(0.45, 0.45, 0.45))
	_rivets_along(k, "own:forged", Transform3D.IDENTITY, _inset(outline, 0.014), 30, zf, 0.004, 0.005, Color(0.55, 0.55, 0.55))
	_boss(k, "own:forged", Transform3D.IDENTITY, Vector3(0, 0.07, 0.002), 0.085, 0.055, 0.04, Color(0.42, 0.42, 0.44), 8)
	var gz := -0.03
	k.bevel_box("own:wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, gz)), Vector3(0.025, 0.12, 0.02), 0.005, Color(0.4, 0.28, 0.18))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.15, -0.12, -0.018), Vector3(-0.1, -0.12, -0.05), Vector3(0.1, -0.12, -0.05), Vector3(0.15, -0.12, -0.022)]), Vector3.FORWARD, 0.035, 0.005, LEATHER)
	return Vector3(0, 0.07, gz)

## A hide shield: an almond of stiff tanned hide over a frame, laced round the edge with
## thong in cross stitches, a small iron boss high on it; tilted as the icon leans.
static func _shield_hide(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var outline := PackedVector2Array()
	var n := 64
	for i in n:
		var a := TAU * i / n
		var s := sin(a)
		var c := cos(a)
		# Round and full above, drawn down to a blunt point below.
		var y := s * (0.36 if s > 0.0 else 0.46)
		var x := c * 0.26 * (1.0 - 0.75 * maxf(-s, 0.0) * maxf(-s, 0.0)) * (1.0 + 0.1 * s)
		outline.append(Vector2(x, y).rotated(-0.2))
	var zf := func(p: Vector2) -> float:
		return 0.025 - 0.9 * p.x * p.x - 0.12 * p.y * p.y
	var hide := Color(0.36, 0.22, 0.12)
	var col := func(p: Vector3) -> Color:
		var d := clampf(Vector2(p.x, p.y).length() / 0.4, 0.0, 1.0)
		var nn := 0.5 + 0.5 * sin(p.x * 37.0 + sin(p.y * 21.0) * 3.0) * sin(p.y * 27.0 - p.x * 11.0)
		return hide.lerp(Color(0.26, 0.15, 0.08), d * d * 0.7 + nn * 0.25)
	_shell(k, "im:hide", Transform3D.IDENTITY, _radial(outline, Vector2(0, 0.0), 10, zf), 0.01, true, col, Color(0.45, 0.32, 0.2), "im:flesh")
	# The rawhide lacing round the rim, through the edge in crossed stitches.
	_edge(k, "im:leather_armour", Transform3D.IDENTITY, outline, zf, 0.005, 0.0075, Color(0.24, 0.13, 0.07))
	var ins := _inset(outline, 0.016)
	for i in range(0, n, 1):
		var p := ins[i]
		var q := outline[(i + 1) % n]
		var a := Vector3(p.x, p.y, zf.call(p) + 0.002)
		var b := Vector3(q.x, q.y, zf.call(q) + 0.002)
		var path := PackedVector3Array([a, (a + b) * 0.5 + Vector3(0, 0, 0.002), b])
		Provisions.tube(k, "im:leather_armour", Transform3D.IDENTITY, path, PackedFloat32Array([0.0035, 0.004, 0.0035]), 5, Color(0.22, 0.12, 0.06))
	_boss(k, "own:forged", Transform3D.IDENTITY, Vector3(0, 0.0, zf.call(Vector2.ZERO)), 0.065, 0.042, 0.035, Color(0.45, 0.45, 0.47), 8)
	var gz := -0.03
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.07, 0, 0.0), Vector3(-0.05, 0, gz), Vector3(0.05, 0, gz), Vector3(0.07, 0, 0.0)]), Vector3.FORWARD, 0.035, 0.005, LEATHER)
	return Vector3(0, 0, gz)

## A tower shield (a pavise): a tall plate of bright steel curved round the bearer, the
## top corners peaked and the foot drawn to a shallow point, an iron rim and a riveted
## cross of straps over the face. 1.15 m tall.
static func _shield_tower(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.66
	var zf := func(p: Vector2) -> float:
		return -0.8 * p.x * p.x
	var top := 0.5
	var outline := _resample(PackedVector2Array([Vector2(-w * 0.5, top + 0.03), Vector2(0, top), Vector2(w * 0.5, top + 0.03),
		Vector2(w * 0.47, -0.45), Vector2(0, -0.62), Vector2(-w * 0.47, -0.45)]), 0.04)
	var steel := Color(0.66, 0.66, 0.67)
	var col := func(p: Vector3) -> Color:
		var n := 0.5 + 0.5 * sin(p.x * 43.0 + sin(p.y * 19.0) * 3.0) * sin(p.y * 31.0 - p.x * 13.0)
		return steel.darkened(0.15 * absf(p.x) / (w * 0.5)).lerp(Color(0.45, 0.43, 0.41), 0.25 * n)
	_shell(k, "own:plate", Transform3D.IDENTITY, _radial(outline, Vector2(0, 0), 8, zf), 0.006, true, col, steel.darkened(0.4))
	var inner := _inset(outline, 0.03)
	var iron := Color(0.48, 0.48, 0.49)
	_shell(k, "own:forged", Transform3D.IDENTITY, _band_rows(inner, outline, zf, 0.003), 0.005, true, iron, iron.darkened(0.2))
	_edge(k, "own:forged", Transform3D.IDENTITY, outline, zf, 0.003, 0.0065, iron.darkened(0.1))
	_rivets_along(k, "own:forged", Transform3D.IDENTITY, _inset(outline, 0.015), 40, zf, 0.003, 0.005, iron.lightened(0.1))
	# The cross: one strap down the middle, one across a third of the way down.
	var vert := PackedVector2Array()
	var horiz := PackedVector2Array()
	for i in 21:
		vert.append(Vector2(0, lerpf(top - 0.02, -0.6, i / 20.0)))
		horiz.append(Vector2(lerpf(-w * 0.47, w * 0.47, i / 20.0), 0.18))
	for line: PackedVector2Array in [vert, horiz]:
		var a := PackedVector2Array()
		var b := PackedVector2Array()
		var along := (line[line.size() - 1] - line[0]).normalized()
		var side := Vector2(-along.y, along.x) * 0.018
		for p in line:
			a.append(p - side)
			b.append(p + side)
		var rows := _band_rows(a, b, zf, 0.004)
		_shell(k, "own:forged", Transform3D.IDENTITY, rows, 0.005, false, iron, iron.darkened(0.2))
		for i in range(1, 20, 2):
			var p := line[i]
			for s: float in [-1.0, 1.0]:
				var q := p + side * 0.5 * s
				_rivet(k, "own:forged", Transform3D.IDENTITY, Vector3(q.x, q.y, zf.call(q) + 0.004), _zn(zf, q), 0.0045, iron.lightened(0.1))
	var gz := -0.035
	k.bevel_box("own:forged", Transform3D(Basis.IDENTITY, Vector3(0, 0.0, gz)), Vector3(0.025, 0.14, 0.02), 0.005, iron.darkened(0.2))
	return Vector3(0, 0, gz)

## A riot shield of old steel: a tall plate bowed round the bearer, pressed with a
## diamond tread, a riveted border, rust bleeding from every edge, a round boss to one
## side over the grip. 0.95 m tall.
static func _shield_riot(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var w := 0.56
	var h := 0.95
	var zf := func(p: Vector2) -> float:
		return -1.3 * p.x * p.x
	var steel := Color(0.36, 0.36, 0.37)
	var rust := Color(0.46, 0.24, 0.12)
	var col := func(p: Vector3) -> Color:
		var e := maxf(absf(p.x) / (w * 0.5), absf(p.y) / (h * 0.5))
		var n := 0.5 + 0.5 * sin(p.x * 41.0 + sin(p.y * 23.0) * 2.0) * sin(p.y * 29.0 + p.x * 9.0)
		return steel.lerp(rust, clampf(pow(e, 12.0) * 0.6 + pow(n, 6.0) * 0.3, 0.0, 0.7))
	var rows: Array = []
	for i in 13:
		var row := PackedVector3Array()
		var y := lerpf(-h * 0.5, h * 0.5, i / 12.0)
		for j in 17:
			var x := lerpf(-w * 0.5, w * 0.5, j / 16.0)
			row.append(Vector3(x, y, zf.call(Vector2(x, y))))
		rows.append(row)
	_shell(k, "own:plate_dark", Transform3D.IDENTITY, rows, 0.006, false, col, steel.darkened(0.4))
	# Diamond tread: short raised bars at alternating angles.
	var nx := 11
	var ny := 20
	for i in nx:
		for j in ny:
			var x := lerpf(-w * 0.44, w * 0.44, (i + 0.5 * (j % 2)) / nx)
			var y := lerpf(-h * 0.45, h * 0.45, float(j) / (ny - 1))
			if absf(x) > w * 0.44:
				continue
			var p := Vector2(x, y)
			var nrm := _zn(zf, p)
			var ang := 0.6 if (i + j) % 2 == 0 else -0.6
			var b := Basis(Quaternion(Vector3.BACK, nrm)) * Basis(Vector3.BACK, ang)
			k.bevel_box("own:plate_dark", Transform3D(b, Vector3(x, y, zf.call(p) + 0.001)), Vector3(0.022, 0.006, 0.003), 0.0012, Color(col.call(Vector3(x, y, 0))).lightened(0.1))
	# The riveted border.
	var outline := _resample(PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)]), 0.03)
	var inner := _inset(outline, 0.022)
	_shell(k, "own:plate_dark", Transform3D.IDENTITY, _band_rows(inner, outline, zf, 0.003), 0.004, true, steel.lerp(rust, 0.3).darkened(0.15), steel.darkened(0.3))
	_rivets_along(k, "own:plate_dark", Transform3D.IDENTITY, _inset(outline, 0.011), 46, zf, 0.003, 0.0045, rust.lerp(steel, 0.4))
	_edge(k, "own:plate_dark", Transform3D.IDENTITY, outline, zf, 0.002, 0.005, steel.lerp(rust, 0.5))
	var bx := 0.15
	_boss(k, "own:plate_dark", Transform3D.IDENTITY, Vector3(bx, 0.0, zf.call(Vector2(bx, 0))), 0.075, 0.055, 0.035, steel.lerp(rust, 0.3), 10)
	var gz: float = zf.call(Vector2(bx, 0)) - 0.04
	k.bevel_box("own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(bx, 0, gz)), Vector3(0.025, 0.13, 0.02), 0.005, steel.darkened(0.3))
	return Vector3(bx, 0, gz)

## A ballistic shield: a slab of black composite with cut corners, a strip of armoured
## glass to see through at the top, raised armour panels bolted on, and a tube handle up
## its side. 1.0 m tall.
static func _shield_ballistic(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.58
	var h := 1.0
	var c := 0.07
	var zf := func(p: Vector2) -> float:
		return -0.35 * p.x * p.x
	var black := Color(0.15, 0.155, 0.16)
	var outline := _resample(PackedVector2Array([Vector2(-w * 0.5 + c, -h * 0.5), Vector2(w * 0.5 - c, -h * 0.5), Vector2(w * 0.5, -h * 0.5 + c),
		Vector2(w * 0.5, h * 0.5 - c), Vector2(w * 0.5 - c, h * 0.5), Vector2(-w * 0.5 + c, h * 0.5), Vector2(-w * 0.5, h * 0.5 - c), Vector2(-w * 0.5, -h * 0.5 + c)]), 0.04)
	_shell(k, "im:composite", Transform3D.IDENTITY, _radial(outline, Vector2.ZERO, 6, zf), 0.03, true, black, black.darkened(0.3))
	var frame := _inset(outline, 0.025)
	_shell(k, "im:composite", Transform3D.IDENTITY, _band_rows(frame, outline, zf, 0.004), 0.004, true, black.lightened(0.12), black)
	# Raised panels: a big one in the middle, one each side of it.
	var zp := func(p: Vector2) -> float:
		return zf.call(p) + 0.006
	for pan: Array in [[Vector2(0, -0.08), Vector2(0.36, 0.62)], [Vector2(-0.22, -0.02), Vector2(0.06, 0.7)], [Vector2(0.22, -0.02), Vector2(0.06, 0.7)]]:
		var ctr: Vector2 = pan[0]
		var sz: Vector2 = pan[1] * 0.5
		var e := 0.03
		var po := _resample(PackedVector2Array([ctr + Vector2(-sz.x + e, -sz.y), ctr + Vector2(sz.x - e, -sz.y), ctr + Vector2(sz.x, -sz.y + e), ctr + Vector2(sz.x, sz.y - e),
			ctr + Vector2(sz.x - e, sz.y), ctr + Vector2(-sz.x + e, sz.y), ctr + Vector2(-sz.x, sz.y - e), ctr + Vector2(-sz.x, -sz.y + e)]), 0.04)
		_shell(k, "im:composite", Transform3D.IDENTITY, _radial(po, ctr, 3, zp), 0.006, true, black.lightened(0.06), black.darkened(0.2))
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var b: Vector2 = ctr + Vector2(sz.x - 0.016, sz.y - 0.016) * q
			_rivet(k, "own:forged", Transform3D.IDENTITY, Vector3(b.x, b.y, zp.call(b)), _zn(zf, b), 0.006, Color(0.55, 0.5, 0.4))
	# The viewport: armoured glass in a thick frame across the top.
	var vy := 0.36
	var vw := 0.3
	var vh := 0.07
	var vz: float = zf.call(Vector2(0, vy)) + 0.004
	k.bevel_box("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, vy, vz)), Vector3(vw + 0.04, vh + 0.04, 0.016), 0.006, black.lightened(0.1))
	k.box("im:visor", Transform3D(Basis.IDENTITY, Vector3(0, vy, vz + 0.006)), Vector3(vw, vh, 0.01), Color(0.55, 0.68, 0.8))
	# The side handle: a tube on two standoffs up the left edge.
	var hx := -w * 0.5 - 0.035
	var hz: float = zf.call(Vector2(-w * 0.5, 0)) - 0.01
	Provisions.tube(k, "im:rubber", Transform3D.IDENTITY, PackedVector3Array([Vector3(hx + 0.035, 0.22, hz), Vector3(hx, 0.2, hz), Vector3(hx, -0.08, hz), Vector3(hx + 0.035, -0.1, hz)]), PackedFloat32Array([0.011, 0.011, 0.011, 0.011]), 10, Color(0.16, 0.16, 0.17))
	for y: float in [0.21, -0.09]:
		k.cylinder("own:forged", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(hx + 0.035, y, hz)), 0.014, 0.014, 0.03, 10, true, 0.0, 1, Color(0.35, 0.35, 0.36))
	var gz := -0.06
	k.bevel_box("im:rubber", Transform3D(Basis.IDENTITY, Vector3(0, 0.0, gz)), Vector3(0.025, 0.14, 0.022), 0.005, Color(0.15, 0.15, 0.16))
	return Vector3(0, 0, gz)

# --- Crystal and energy shields ---------------------------------------------------------

## The crescent crystal shield: a waxing moon of pale ice-blue crystal, thick in the
## middle of the band and thin at the horns, with faint violet veins through it. Unlit.
static func _shield_crystal(k: MeshKit, _r: RandomNumberGenerator, t: String):
	var R := 0.38
	var ri := 0.27
	var off := Vector2(0.15, 0.06)
	var rows: Array = []
	var nu := 40
	var nv := 7
	var front: Array = []
	var back: Array = []
	for i in nv:
		var v := float(i) / (nv - 1)
		var fr := PackedVector3Array()
		var bk := PackedVector3Array()
		for j in nu + 1:
			var u := float(j) / nu
			var a := lerpf(0.42 * PI, 1.82 * PI, u) # round the left from the top to the bottom horn
			var o := Vector2(cos(a), sin(a)) * R
			# The inner edge: the offset circle where it lies inside, else the horn tip.
			var d := Vector2(cos(a), sin(a))
			var inner := off + d * ri
			var p := inner.lerp(o, v)
			var horn := sin(u * PI)
			var th := 0.008 + 0.05 * horn * sin(v * PI)
			fr.append(Vector3(p.x, p.y, th * 0.5))
			bk.append(Vector3(p.x, p.y, -th * 0.5))
		front.append(fr)
		back.append(bk)
	var col := func(p: Vector3) -> Color:
		var vein := absf(sin(p.x * 25.0 + p.y * 14.0 + sin(p.y * 9.0) * 2.0))
		var base := Color(0.42, 0.78, 0.88, 0.5)
		return base.lerp(Color(0.6, 0.48, 0.9, 0.6), pow(1.0 - vein, 5.0) * 0.9)
	var m := "im:crystal:" + t
	_grid(k, m, Transform3D.IDENTITY, front, false, col, Vector3.BACK)
	_grid(k, m, Transform3D.IDENTITY, back, false, col, Vector3.FORWARD)
	# Close the two edges and the horn tips.
	for e: Array in [[0, 1], [nv - 1, nv - 2]]:
		var F: PackedVector3Array = front[e[0]]
		var B: PackedVector3Array = back[e[0]]
		var Rr: PackedVector3Array = front[e[1]]
		for j in nu:
			var o := (F[j] - Rr[j])
			o.z = 0.0
			ItemModels._quad(k, m, Transform3D.IDENTITY, F[j], F[j + 1], B[j + 1], B[j], o, col.call(F[j]))
	for j: int in [0, nu]:
		for i in nv - 1:
			var a: Vector3 = (front[i] as PackedVector3Array)[j]
			var b: Vector3 = (front[i + 1] as PackedVector3Array)[j]
			var c: Vector3 = (back[i + 1] as PackedVector3Array)[j]
			var d: Vector3 = (back[i] as PackedVector3Array)[j]
			var o: Vector3 = a - (front[i] as PackedVector3Array)[nu / 2]
			o.z = 0.0
			ItemModels._quad(k, m, Transform3D.IDENTITY, a, b, c, d, o, col.call(a))
	var gz := -0.04
	k.bevel_box("own:forged", Transform3D(Basis.IDENTITY, Vector3(-0.27, 0.0, gz)), Vector3(0.025, 0.13, 0.02), 0.005, Color(0.6, 0.62, 0.66))
	return Vector3(-0.27, 0, gz)

## The emitter shield: a flat-topped hexagon of pale cyan tinted panel, domed a little,
## a white honeycomb grid laid over it and six grey frame clamps round the edge. Human
## sci-fi: no light of its own, the colour is in the panel. 0.75 m across.
static func _shield_emitter(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.37
	var hexo := PackedVector2Array()
	for i in 6:
		var a := TAU * i / 6.0
		hexo.append(Vector2(cos(a), sin(a)) * R)
	var outline := _resample(hexo, 0.03)
	var zf := func(p: Vector2) -> float:
		return 0.05 * (1.0 - minf(p.length_squared() / (R * R), 1.0))
	_shell(k, "own:tinted", Transform3D.IDENTITY, _radial(outline, Vector2.ZERO, 8, zf), 0.008, true, Color(0.55, 0.8, 0.86, 0.2), Color(0.45, 0.75, 0.82, 0.2))
	# The rim tube, pale cyan.
	_edge(k, "im:paint", Transform3D.IDENTITY, _inset(outline, 0.004), zf, 0.0, 0.011, Color(0.45, 0.85, 0.95))
	# The honeycomb: a lattice of flat-topped cells, the edges inside the panel drawn on it.
	var s := 0.085
	var seen := {}
	for qi in range(-5, 6):
		for ri in range(-5, 6):
			var cc := Vector2(1.5 * s * qi, sqrt(3.0) * s * (ri + 0.5 * qi))
			for e in 6:
				var a0 := TAU * e / 6.0
				var a1 := TAU * (e + 1) / 6.0
				var p0 := cc + Vector2(cos(a0), sin(a0)) * s
				var p1 := cc + Vector2(cos(a1), sin(a1)) * s
				var key := str((p0 + p1).snapped(Vector2.ONE * 0.001))
				if seen.has(key) or p0.length() > R * 0.84 or p1.length() > R * 0.84:
					continue
				seen[key] = true
				var path := PackedVector3Array()
				for st in 5:
					var p := p0.lerp(p1, st / 4.0)
					path.append(Vector3(p.x, p.y, zf.call(p) + 0.003))
				var near_c := cc.length() < 0.01
				Provisions.tube(k, "im:paint", Transform3D.IDENTITY, path, PackedFloat32Array([0.003, 0.003, 0.003, 0.003, 0.003]), 4, Color(0.92, 0.97, 0.98) if not near_c else Color(1, 1, 1))
	# Six clamps, one on each edge.
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		var d := Vector2(cos(a), sin(a))
		var p := d * R * cos(PI / 6.0)
		var b := Basis(Vector3.BACK, a - PI * 0.5)
		var o := Transform3D(b, Vector3(p.x, p.y, 0.0))
		k.bevel_box("im:composite", o * Transform3D(Basis.IDENTITY, Vector3(0, 0.004, 0.0)), Vector3(0.2, 0.03, 0.035), 0.007, Color(0.5, 0.53, 0.56))
		k.bevel_box("im:composite", o * Transform3D(Basis.IDENTITY, Vector3(0, -0.006, 0.014)), Vector3(0.15, 0.022, 0.012), 0.004, Color(0.38, 0.41, 0.44))
	var gz := -0.03
	k.bevel_box("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0, gz)), Vector3(0.025, 0.13, 0.02), 0.005, Color(0.35, 0.37, 0.4))
	return Vector3(0, 0, gz)

## A diamond outline: a short point at `top`, widest `w` at `wy`, a long point at `bottom`.
static func _diamond(w: float, top: float, wy: float, bottom: float, shoulder := 0.0) -> PackedVector2Array:
	return _resample(PackedVector2Array([Vector2(0, top), Vector2(w * 0.5, wy + shoulder), Vector2(w * 0.5, wy - shoulder), Vector2(0, bottom), Vector2(-w * 0.5, wy - shoulder), Vector2(-w * 0.5, wy + shoulder)]), 0.03)

## A silver alien frame round a diamond: a bevelled band proud of the face, rolled edge.
static func _alien_frame(k: MeshKit, outline: PackedVector2Array, zf: Callable, band: float) -> void:
	var silver := Color(0.74, 0.74, 0.78)
	var inner := _inset(outline, band)
	_shell(k, "own:forged", Transform3D.IDENTITY, _band_rows(inner, outline, zf, 0.008), 0.012, true, silver, silver.darkened(0.3))
	_shell(k, "own:forged", Transform3D.IDENTITY, _band_rows(_inset(outline, band * 0.75), _inset(outline, band * 0.45), zf, 0.012), 0.004, true, silver.darkened(0.25), silver.darkened(0.3))
	_edge(k, "own:forged", Transform3D.IDENTITY, outline, zf, 0.0, 0.008, silver.darkened(0.1))

## The void shield: a diamond kite framed in silver round a field of starry violet-black,
## a dark orb ringed in faint violet light at its heart and thin rays of it reaching to
## the points. Alien: the light is faint.
static func _shield_void(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var outline := _diamond(0.56, 0.38, 0.12, -0.5)
	var zf := func(p: Vector2) -> float:
		return 0.03 - 0.5 * p.x * p.x - 0.04 * p.y * p.y
	_shell(k, "own:void", Transform3D.IDENTITY, _radial(outline, Vector2(0, 0.05), 6, zf), 0.012, true, Color(0.16, 0.08, 0.28), Color(0.2, 0.18, 0.22), "own:forged")
	_alien_frame(k, outline, zf, 0.035)
	var oc := Vector2(0, 0.08)
	var oz: float = zf.call(oc)
	# Stars: specks of faint light scattered in the dark.
	var rs := RandomNumberGenerator.new()
	rs.seed = 11
	var field := _inset(outline, 0.04)
	for i in 70:
		var q := Vector2(rs.randf_range(-0.25, 0.25), rs.randf_range(-0.45, 0.35))
		if not Geometry2D.is_point_in_polygon(q, field):
			continue
		k.sphere("own:glow_violet", Transform3D(Basis.IDENTITY, Vector3(q.x, q.y, zf.call(q) + 0.001)), rs.randf_range(0.0015, 0.003), 3, 5, 0.0, 0.4, Color(0.9, 0.8, 1.0))
	# Rays: a cross of thin violet light through the orb.
	for ray: Array in [[Vector2(0, 0.33), Vector2(0, -0.44)], [Vector2(-0.24, 0.1), Vector2(0.24, 0.1)]]:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 17:
			var p := (ray[0] as Vector2).lerp(ray[1], i / 16.0)
			path.append(Vector3(p.x, p.y, zf.call(p) + 0.002))
			radii.append(0.0035 * (1.0 - 0.6 * absf(i / 8.0 - 1.0)))
		Provisions.tube(k, "own:glow_violet", Transform3D.IDENTITY, path, radii, 5, Color(0.75, 0.55, 1.0))
	k.sphere("own:void_orb", Transform3D(Basis.IDENTITY, Vector3(oc.x, oc.y, oz)), 0.065, 10, 16, 0.0, 0.6, Color(0.05, 0.03, 0.08))
	ItemModels._torus(k, "own:glow_violet", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(oc.x, oc.y, oz + 0.014)), 0.07, 0.007, 32, 6, Color(0.7, 0.45, 1.0))
	var gz := -0.035
	k.bevel_box("own:forged", Transform3D(Basis.IDENTITY, Vector3(0, 0.05, gz)), Vector3(0.025, 0.13, 0.02), 0.005, Color(0.5, 0.5, 0.55))
	return Vector3(0, 0.05, gz)

## The prism shield: a silver-framed elongated hexagon holding one great cut crystal of
## blue and violet, its facets meeting in a ridge down the middle. Alien: faint inner light.
static func _shield_prism(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var outline := _diamond(0.56, 0.4, 0.06, -0.46, 0.13)
	var zf := func(p: Vector2) -> float:
		return 0.01 - 0.3 * p.x * p.x
	_alien_frame(k, outline, zf, 0.032)
	# The crystal: facets from the frame up to a ridge, alternately light and deep.
	var inner := _inset(outline, 0.03)
	var corners := [Vector2(0, 0.36), Vector2(0.245, 0.17), Vector2(0.245, -0.06), Vector2(0, -0.42), Vector2(-0.245, -0.06), Vector2(-0.245, 0.17)]
	var ridge := [Vector3(0, 0.22, 0.07), Vector3(0.06, 0.1, 0.075), Vector3(0.06, -0.06, 0.075), Vector3(0, -0.24, 0.07), Vector3(-0.06, -0.06, 0.075), Vector3(-0.06, 0.1, 0.075)]
	var cols := [Color(0.78, 0.85, 1.0, 0.8), Color(0.28, 0.3, 0.9, 0.88), Color(0.55, 0.4, 0.95, 0.85), Color(0.45, 0.65, 1.0, 0.82), Color(0.36, 0.22, 0.8, 0.88), Color(0.85, 0.88, 1.0, 0.8)]
	var m := "own:prism"
	for i in 6:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 6]
		var A := Vector3(a.x, a.y, zf.call(a) + 0.006)
		var B := Vector3(b.x, b.y, zf.call(b) + 0.006)
		var ra: Vector3 = ridge[i]
		var rb: Vector3 = ridge[(i + 1) % 6]
		var mid := (A + B) * 0.5 + Vector3(0, 0, 0.03) + (ra + rb - A - B) * 0.15
		ItemModels._tri(k, m, Transform3D.IDENTITY, A, mid, ra, Vector3.BACK, Vector3.BACK, Vector3.BACK, cols[i])
		ItemModels._tri(k, m, Transform3D.IDENTITY, mid, B, rb, Vector3.BACK, Vector3.BACK, Vector3.BACK, cols[(i + 2) % 6])
		ItemModels._tri(k, m, Transform3D.IDENTITY, mid, rb, ra, Vector3.BACK, Vector3.BACK, Vector3.BACK, cols[(i + 4) % 6])
		var n := (ra - A).cross(mid - A).normalized()
		if n.z < 0.0:
			n = -n
	# Facet normals: re-shade flat (the tri helper took +Z; give each its own).
	# The table: the flat top facet inside the ridge.
	for i in range(1, 5):
		ItemModels._tri(k, m, Transform3D.IDENTITY, ridge[0], ridge[i], ridge[i + 1] if i + 1 < 6 else ridge[0], Vector3.BACK, Vector3.BACK, Vector3.BACK, Color(0.75, 0.8, 1.0, 0.75))
	_shell(k, "own:prism", Transform3D.IDENTITY, _radial(inner, Vector2(0, -0.02), 3, zf), 0.01, true, Color(0.3, 0.3, 0.8, 0.9), Color(0.3, 0.3, 0.6, 0.9), "own:forged")
	var gz := -0.035
	k.bevel_box("own:forged", Transform3D(Basis.IDENTITY, Vector3(0, 0.0, gz)), Vector3(0.025, 0.13, 0.02), 0.005, Color(0.5, 0.5, 0.55))
	return Vector3(0, 0, gz)

# --- Worn on the back -------------------------------------------------------------------

static func _sp(v: float, e: float) -> float:
	return signf(v) * pow(absf(v), e)

## A soft or boxy body: a superellipsoid `half` across each way about `c` (`e` 1 is a
## round pillow, 0.3 nearly a box), its surface rumpled by `wob`.
static func _pillow(k: MeshKit, m: String, xf: Transform3D, c: Vector3, half: Vector3, e: float, col: Variant, wob := 0.0, nl := 12, ns := 24) -> void:
	var rows: Array = []
	var nz := FastNoiseLite.new()
	nz.seed = int(c.x * 1000.0 + c.y * 3000.0) & 0xFFF
	nz.frequency = 6.0
	for i in nl + 1:
		var phi := lerpf(-PI * 0.5, PI * 0.5, float(i) / nl)
		var row := PackedVector3Array()
		for j in ns:
			var th := TAU * j / ns
			var d := Vector3(_sp(cos(phi), e) * _sp(cos(th), e), _sp(sin(phi), e), _sp(cos(phi), e) * _sp(sin(th), e))
			var p := d * half
			if wob > 0.0:
				p *= 1.0 + wob * nz.get_noise_3dv(p + c)
			row.append(c + p)
		rows.append(row)
	_grid(k, m, xf, rows, true, col, Vector3.ZERO, c)

## A flap of cloth or leather `w` wide over the top of a body and down its front: from
## `back` over the crown at `top` to its hem at `hem`, the hem's corners rounded.
static func _flap(k: MeshKit, m: String, xf: Transform3D, w: float, back: Vector3, top: Vector3, hem: Vector3, th: float, col: Color, under: Color, round := 0.4) -> void:
	var front_top := Vector3(0, top.y - 0.01, hem.z)
	var f := func(u: float, v: float) -> Vector3:
		var p: Vector3
		if v < 0.35:
			var s := v / 0.35
			p = back.lerp(top, s) + Vector3(0, sin(s * PI) * 0.012, 0)
		elif v < 0.5:
			var s := (v - 0.35) / 0.15
			var a := s * PI * 0.5
			p = Vector3(0, top.y - (1.0 - cos(a)) * (top.y - front_top.y), lerpf(top.z, hem.z, sin(a)))
		else:
			var s := (v - 0.5) / 0.5
			p = front_top.lerp(hem, s) + Vector3(0, 0, sin(s * PI) * 0.006)
		var x := (u - 0.5) * w
		# Round the hem's corners in.
		var t := clampf((v - (1.0 - round * 0.5)) / (round * 0.5), 0.0, 1.0)
		var edge := absf(u - 0.5) * 2.0
		var lift := t * t * pow(edge, 4.0) * (hem.y - front_top.y) * -0.35
		x *= 1.0 - 0.05 * t * edge
		return Vector3(x, p.y + lift, p.z)
	ItemModels._sheet(k, m, xf, f, 10, 18, th, col, under)

## A vertical strap down a body's front from `y0` to `y1` at x, `z(y)` its depth.
static func _front_strap(k: MeshKit, m: String, xf: Transform3D, x: float, y0: float, y1: float, zf: Callable, w: float, col: Color) -> void:
	var path := PackedVector3Array()
	for i in 9:
		var y := lerpf(y0, y1, i / 8.0)
		path.append(Vector3(x, y, zf.call(y)))
	_strap(k, m, xf, path, Vector3.BACK, w, 0.004, col)

## Shoulder straps down the back: two padded bands from the top to the bottom corners.
static func _shoulder_straps(k: MeshKit, m: String, xf: Transform3D, top: float, bottom: float, z: float, spread: float, col: Color, rise := 0.0) -> void:
	for s: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		for i in 11:
			var t := i / 10.0
			path.append(Vector3(s * lerpf(spread * 0.4, spread, t), lerpf(top + rise * sin(t * PI) * 0.0, bottom, t) + rise * sin(minf(t * 2.0, 1.0) * PI) * 0.5, z - sin(t * PI) * 0.05))
		_strap(k, m, xf, path, Vector3.FORWARD, 0.05, 0.012, col)

## A canvas rucksack: a soft olive body under a flap that reaches halfway down, two
## leather straps down it to brass buckles, a pocket below, pockets on the sides and a
## leather carry handle on top. 0.48 m tall.
static func _backpack_canvas(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var olive := Color(0.26, 0.23, 0.13)
	var body := func(p: Vector3) -> Color:
		return olive.darkened(0.15 * clampf(0.3 - p.y, 0.0, 0.3) / 0.3).lerp(Color(0.3, 0.28, 0.17), 0.3 * absf(sin(p.x * 30.0 + p.y * 18.0)))
	_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(0, 0.22, 0), Vector3(0.17, 0.22, 0.1), 0.35, body, 0.03)
	_flap(k, "im:linen", Transform3D.IDENTITY, 0.35, Vector3(0, 0.43, -0.08), Vector3(0, 0.46, 0.0), Vector3(0, 0.22, 0.112), 0.006, olive.lightened(0.05), olive.darkened(0.3))
	# Front pocket under the flap, with its own little flap.
	_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(0, 0.11, 0.1), Vector3(0.13, 0.075, 0.035), 0.4, olive.darkened(0.05), 0.04)
	k.bevel_box("im:linen", Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.165, 0.132)), Vector3(0.26, 0.05, 0.008), 0.003, olive)
	# Side pockets.
	for s: float in [-1.0, 1.0]:
		_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(s * 0.175, 0.12, 0.0), Vector3(0.035, 0.09, 0.07), 0.45, olive.darkened(0.1), 0.05)
		k.bevel_box("im:linen", Transform3D(Basis.IDENTITY, Vector3(s * 0.2, 0.2, 0.0)), Vector3(0.022, 0.035, 0.13), 0.004, olive)
	# Two straps from the crown down the flap to buckles, on down over the pocket.
	var zf := func(y: float) -> float:
		return 0.12 if y < 0.2 else (0.116 if y < 0.42 else 0.12 - (y - 0.42) * 2.2)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.085
		_front_strap(k, "im:leather_armour", Transform3D.IDENTITY, x, 0.46, 0.25, func(y: float) -> float: return 0.12 if y < 0.42 else 0.12 - (y - 0.42) * 2.4, 0.03, LEATHER)
		_front_strap(k, "im:leather_armour", Transform3D.IDENTITY, x, 0.2, 0.05, func(y: float) -> float: return 0.138, 0.03, LEATHER.darkened(0.05))
		_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(x, 0.235, 0.124), Vector3.BACK, Vector3.UP, 0.04, 0.032, 0.005, BRASS)
		_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(x, 0.14, 0.142), Vector3.BACK, Vector3.UP, 0.036, 0.028, 0.0045, BRASS)
	# The carry handle and the shoulder straps behind.
	var hp := PackedVector3Array()
	for i in 9:
		var a := PI * i / 8.0
		hp.append(Vector3(cos(a) * 0.05, 0.465 + sin(a) * 0.035, -0.03))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, hp, Vector3.FORWARD, 0.02, 0.006, LEATHER)
	_shoulder_straps(k, "im:leather_armour", Transform3D.IDENTITY, 0.42, 0.03, -0.1, 0.12, LEATHER.darkened(0.1))
	return Vector3(0, 0.5, -0.03)

## A leather satchel: a wide flat bag under a full flap with two strap-and-buckle closures,
## brass rings at the sides and a long shoulder strap. 0.36 m wide.
static func _satchel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var brown := Color(0.34, 0.17, 0.08)
	var col := func(p: Vector3) -> Color:
		return brown.lerp(Color(0.28, 0.14, 0.07), 0.35 * absf(sin(p.x * 23.0 + sin(p.y * 17.0) * 2.0)))
	_pillow(k, "im:leather_armour", Transform3D.IDENTITY, Vector3(0, 0.13, 0), Vector3(0.18, 0.13, 0.055), 0.25, col, 0.02)
	_flap(k, "im:leather_armour", Transform3D.IDENTITY, 0.37, Vector3(0, 0.255, -0.05), Vector3(0, 0.27, 0.0), Vector3(0, 0.07, 0.062), 0.006, brown.lightened(0.04), brown.darkened(0.35), 0.35)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.1
		_front_strap(k, "im:leather_armour", Transform3D.IDENTITY, x, 0.11, 0.02, func(y: float) -> float: return 0.06, 0.024, brown.darkened(0.15))
		_front_strap(k, "im:leather_armour", Transform3D.IDENTITY, x, 0.2, 0.09, func(y: float) -> float: return 0.068, 0.022, brown.darkened(0.2))
		_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(x, 0.1, 0.072), Vector3.BACK, Vector3.UP, 0.034, 0.03, 0.0045, BRASS)
		# A ring at each side for the strap.
		ItemModels._torus(k, "im:metal@0.35", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.19, 0.22, 0)), 0.016, 0.0028, 16, 6, BRASS)
	# The shoulder strap: up from the left ring, over and down to the right one.
	var sp := PackedVector3Array()
	for i in 25:
		var t := i / 24.0
		var a := PI * t
		# Down from the left ring, hanging in a loop below the bag, up to the right ring.
		sp.append(Vector3(-cos(a) * 0.2 + sin(a) * 0.04, 0.22 - sin(a) * 0.3, 0.02 + sin(a) * 0.06))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, sp, Vector3.BACK, 0.03, 0.005, brown.darkened(0.1))
	_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(0.14, -0.02, 0.07), Vector3(0.2, 0, 1), Vector3(0.6, 1.0, 0), 0.036, 0.03, 0.005, BRASS)
	return Vector3(0, 0.39, -0.04)

## A boiler pack: two upright tanks, a slim brass one and a stout iron one banded in
## brass, pipes and a valve between their tops, a cog at the side, leather harness loops.
static func _pack_boiler(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var brass := Color(0.6, 0.43, 0.2)
	var iron := Color(0.24, 0.22, 0.2)
	var tank := func(x: float, rad: float, h: float, col: Variant) -> void:
		var prof := PackedVector2Array([Vector2(0, 0.02), Vector2(rad * 0.7, 0.022), Vector2(rad, 0.04), Vector2(rad, 0.12), Vector2(rad, 0.12), Vector2(rad, 0.4), Vector2(rad, 0.4), Vector2(rad, h - 0.04), Vector2(rad * 0.7, h - 0.012), Vector2(rad * 0.3, h), Vector2(0, h + 0.004)])
		Provisions.lathe(k, "im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), prof, 28, col)
	var right := func(p: Vector3, _a: float, _t2: float) -> Color:
		return iron if p.y > 0.121 and p.y < 0.399 else brass
	tank.call(-0.1, 0.065, 0.48, brass)
	tank.call(0.07, 0.095, 0.5, right)
	for b: Array in [[-0.1, 0.067, 0.1], [-0.1, 0.067, 0.38], [0.07, 0.098, 0.12], [0.07, 0.098, 0.4], [0.07, 0.098, 0.26]]:
		ItemModels._torus(k, "im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(b[0], b[2], 0)), b[1], 0.006, 28, 6, brass.darkened(0.1))
	# Rivets down the iron.
	for i in 8:
		var a := lerpf(-0.9, 0.9, i / 7.0) + PI * 0.5
		_rivet(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(0.07 + cos(a) * 0.098, 0.2, sin(a) * 0.098), Vector3(cos(a), 0, sin(a)), 0.005, brass)
	# The valve stack on the big tank and a pipe over to the small one.
	k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0.07, 0.5, 0)), 0.022, 0.018, 0.07, 14, true, 0.0, 1, brass)
	k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0.07, 0.57, 0)), 0.03, 0.03, 0.012, 14, true, 0.0, 1, brass.darkened(0.1))
	k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0.07, 0.58, 0)), 0.008, 0.008, 0.03, 8, true, 0.0, 1, brass)
	Provisions.tube(k, "im:metal@0.35", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.1, 0.47, 0), Vector3(-0.1, 0.53, 0.0), Vector3(-0.04, 0.56, 0.02), Vector3(0.04, 0.54, 0.02)]), PackedFloat32Array([0.011, 0.011, 0.011, 0.011]), 10, brass)
	Provisions.tube(k, "im:metal@0.35", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.04, 0.06, 0.05), Vector3(-0.01, 0.04, 0.07), Vector3(0.04, 0.06, 0.09)]), PackedFloat32Array([0.008, 0.008, 0.008]), 8, brass)
	# A cog and a little valve wheel at the right.
	ItemModels._gear(k, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.16, 0.14, 0.05)), 0.04, 0.012, 12, brass)
	ItemModels._torus(k, "im:metal@0.35", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.175, 0.38, 0.0)), 0.02, 0.004, 16, 6, brass)
	# Leather harness loops down the left.
	for y: float in [0.3, 0.12]:
		var hp := PackedVector3Array()
		for i in 11:
			var a := PI * i / 10.0
			hp.append(Vector3(-0.17 - sin(a) * 0.06, y + cos(a) * 0.1, -0.04 + sin(a) * 0.02))
		_strap(k, "im:leather_armour", Transform3D.IDENTITY, hp, Vector3.BACK, 0.03, 0.006, LEATHER)
	_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(-0.235, 0.21, -0.02), Vector3.LEFT, Vector3.UP, 0.04, 0.03, 0.005, brass)
	return Vector3(0.07, 0.58, 0)

## A recon pack: an olive nylon rucksack with a rounded top, a front pocket lined with
## webbing loops, side pouches, compression straps, and shoulder straps arching over.
static func _pack_recon(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var od := Color(0.17, 0.19, 0.14)
	var col := func(p: Vector3) -> Color:
		return od.lerp(od.darkened(0.25), 0.3 * absf(sin(p.x * 26.0 + p.y * 31.0)))
	_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(0, 0.24, 0), Vector3(0.16, 0.24, 0.1), 0.45, col, 0.02)
	_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(0, 0.15, 0.1), Vector3(0.12, 0.13, 0.035), 0.3, od.darkened(0.06), 0.02)
	# Webbing: rows of strips across the pocket, tacked down at intervals.
	for i in 5:
		var y := 0.06 + i * 0.045
		k.box("im:linen", Transform3D(Basis.IDENTITY, Vector3(0, y, 0.138)), Vector3(0.23, 0.02, 0.005), od.darkened(0.2))
		for j in 5:
			k.box("im:linen", Transform3D(Basis.IDENTITY, Vector3(-0.1 + j * 0.05, y, 0.141)), Vector3(0.004, 0.022, 0.003), od.darkened(0.35))
	for s: float in [-1.0, 1.0]:
		_pillow(k, "im:linen", Transform3D.IDENTITY, Vector3(s * 0.165, 0.14, 0.0), Vector3(0.035, 0.11, 0.075), 0.35, od.darkened(0.1), 0.02)
		for y: float in [0.1, 0.18]:
			k.box("im:linen", Transform3D(Basis.IDENTITY, Vector3(s * 0.2, y, 0.0)), Vector3(0.005, 0.018, 0.14), od.darkened(0.25))
		_front_strap(k, "im:linen", Transform3D.IDENTITY, s * 0.135, 0.45, 0.04, func(y: float) -> float: return 0.1 * sqrt(maxf(0.0, 1.0 - pow((y - 0.24) / 0.25, 4.0))) + 0.004, 0.022, od.darkened(0.3))
		_buckle(k, "im:composite", Transform3D.IDENTITY, Vector3(s * 0.135, 0.33, 0.105), Vector3.BACK, Vector3.UP, 0.032, 0.026, 0.005, Color(0.12, 0.12, 0.12))
	# Shoulder straps rising from the back over the top.
	for s: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		for i in 15:
			var t := i / 14.0
			var a := t * PI
			path.append(Vector3(s * (0.07 + t * 0.05), 0.42 + sin(a) * 0.1 - t * t * 0.38, -0.08 - sin(a) * 0.06))
		_strap(k, "im:linen", Transform3D.IDENTITY, path, Vector3(s * 0.3, 0.3, -1.0), 0.05, 0.014, od.darkened(0.15))
	var hp := PackedVector3Array()
	for i in 9:
		var a := PI * i / 8.0
		hp.append(Vector3(cos(a) * 0.035, 0.475 + sin(a) * 0.025, -0.02))
	_strap(k, "im:linen", Transform3D.IDENTITY, hp, Vector3.FORWARD, 0.02, 0.006, od.darkened(0.3))
	return Vector3(0, 0.5, -0.02)

## A twin-cylinder air pack: two white tanks either side of a black harness frame with a
## regulator, strapped across twice, black hoses looping from the valves round the sides.
static func _oxygen_pack(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var white := Color(0.8, 0.8, 0.78)
	var black := Color(0.12, 0.12, 0.13)
	for s: float in [-1.0, 1.0]:
		var prof := PackedVector2Array([Vector2(0, 0.0), Vector2(0.06, 0.003), Vector2(0.075, 0.03), Vector2(0.075, 0.46), Vector2(0.06, 0.51), Vector2(0.02, 0.53), Vector2(0, 0.53)])
		Provisions.lathe(k, "im:enamel", Transform3D(Basis.IDENTITY, Vector3(s * 0.1, 0, 0)), prof, 28, white)
		k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(s * 0.1, 0.52, 0)), 0.018, 0.018, 0.04, 12, true, 0.0, 1, Color(0.55, 0.55, 0.57))
		k.cylinder("im:rubber", Transform3D(Basis.IDENTITY, Vector3(s * 0.1, 0.56, 0)), 0.024, 0.024, 0.02, 12, true, 0.0, 1, black)
		# A hose from each valve out round the side and back down.
		var hp := PackedVector3Array()
		for i in 13:
			var t := i / 12.0
			hp.append(Vector3(s * (0.1 + sin(t * PI) * 0.13 + t * 0.03), 0.57 - t * 0.5 + sin(t * PI) * 0.06, 0.01 - t * 0.02))
		Provisions.tube(k, "im:rubber", Transform3D.IDENTITY, hp, PackedFloat32Array([0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012, 0.012]), 8, black)
	# The frame and regulator between, a black backplate behind.
	k.bevel_box("im:rubber", Transform3D(Basis.IDENTITY, Vector3(0, 0.27, -0.085)), Vector3(0.34, 0.5, 0.02), 0.008, black)
	k.bevel_box("im:rubber", Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.0)), Vector3(0.07, 0.46, 0.07), 0.01, black)
	k.bevel_box("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0.04)), Vector3(0.06, 0.1, 0.03), 0.006, Color(0.2, 0.2, 0.21))
	k.bevel_box("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0.22, 0.04)), Vector3(0.05, 0.06, 0.025), 0.006, Color(0.22, 0.22, 0.23))
	k.box("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0.056)), Vector3(0.03, 0.04, 0.004), Color(0.35, 0.35, 0.36))
	# Two straps round the front of the pair, each with a buckle.
	for y: float in [0.14, 0.38]:
		var path := PackedVector3Array()
		for i in 25:
			var a := lerpf(PI * 1.05, -0.05, i / 24.0)
			var cx := -0.1 if a > PI * 0.5 else 0.1
			var p := Vector3(cx + cos(a) * 0.079, y, sin(a) * 0.079)
			path.append(p)
		_strap(k, "im:rubber", Transform3D.IDENTITY, path, Vector3.UP, 0.03, 0.004, black)
		_buckle(k, "im:metal@0.4", Transform3D.IDENTITY, Vector3(0, y, 0.05), Vector3.BACK, Vector3.UP, 0.04, 0.034, 0.005, Color(0.45, 0.45, 0.47))
	return Vector3(0, 0.56, 0)

## The optic cloak, folded: a soft square stack of dark camouflage weave shot with a fine
## hexagon lattice, the folds rolled at the front and the hood bunched on top.
static func _cloak_optic(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var dark := Color(0.3, 0.32, 0.4)
	for i in 3:
		var y := 0.02 + i * 0.038
		_pillow(k, "own:hexcloth", Transform3D(Basis(Vector3.UP, r.randf_range(-0.04, 0.04)), Vector3(r.randf_range(-0.01, 0.01), 0, 0)), Vector3(0, y, 0), Vector3(0.2 - i * 0.008, 0.024, 0.15 - i * 0.006), 0.25, dark.darkened(0.06 * (2 - i)), 0.05, 8, 24)
	# The rolled folds along the front of each layer.
	for i in 3:
		var y := 0.02 + i * 0.038
		var path := PackedVector3Array()
		var rad := PackedFloat32Array()
		for j in 9:
			var x := lerpf(-0.2, 0.2, j / 8.0)
			path.append(Vector3(x, y + sin(j * 1.3 + i) * 0.003, 0.148 - i * 0.006))
			rad.append(0.02)
		Provisions.tube(k, "own:hexcloth", Transform3D.IDENTITY, path, rad, 10, dark.darkened(0.05 * (2 - i)))
	# The hood, bunched on top towards the back.
	_pillow(k, "own:hexcloth", Transform3D(Basis(Vector3.UP, 0.4), Vector3.ZERO), Vector3(-0.04, 0.13, -0.04), Vector3(0.16, 0.035, 0.11), 0.5, dark, 0.35, 12, 24)
	# A fold of it draping down over the front edge.
	var f := func(u: float, v: float) -> Vector3:
		var x := lerpf(-0.12, 0.08, u)
		var a := v * PI * 0.6
		return Vector3(x + v * 0.02, 0.15 - sin(a) * 0.07 - v * 0.03, 0.04 + v * 0.12 + sin(u * PI * 3.0) * 0.008)
	ItemModels._sheet(k, "own:hexcloth", Transform3D.IDENTITY, f, 8, 8, 0.008, dark.lightened(0.04), dark.darkened(0.2))
	return Vector3(0, 0.08, 0)

## A military jetpack: an armoured backplate with a raised hexagonal plate, two fat
## thruster pods either side ending in ribbed nozzles, shoulder hoops above. Gunmetal.
static func _jetpack_military(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var gun := Color(0.4, 0.41, 0.42)
	var dark := Color(0.2, 0.2, 0.21)
	k.bevel_box("own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(0.22, 0.42, 0.1), 0.02, gun.darkened(0.1))
	var hexo := PackedVector2Array([Vector2(-0.07, 0.48), Vector2(0.07, 0.48), Vector2(0.095, 0.42), Vector2(0.095, 0.2), Vector2(0.06, 0.13), Vector2(-0.06, 0.13), Vector2(-0.095, 0.2), Vector2(-0.095, 0.42)])
	var zf := func(_p: Vector2) -> float:
		return 0.065
	_shell(k, "own:plate_dark", Transform3D.IDENTITY, _radial(_resample(hexo, 0.03), Vector2(0, 0.3), 3, zf), 0.02, true, gun, dark)
	var zf2 := func(_p: Vector2) -> float:
		return 0.072
	var inner := _inset(_resample(hexo, 0.03), 0.025)
	_shell(k, "own:plate_dark", Transform3D.IDENTITY, _radial(inner, Vector2(0, 0.3), 3, zf2), 0.01, true, gun.lightened(0.08), dark)
	for p: Vector2 in hexo:
		var q := p * 0.88 + Vector2(0, 0.3) * 0.12
		_rivet(k, "own:forged", Transform3D.IDENTITY, Vector3(q.x, q.y, 0.073), Vector3.BACK, 0.006, Color(0.6, 0.55, 0.4))
	for s: float in [-1.0, 1.0]:
		var x := s * 0.18
		var prof := PackedVector2Array([Vector2(0.06, 0.1), Vector2(0.08, 0.13), Vector2(0.085, 0.16), Vector2(0.085, 0.46), Vector2(0.07, 0.52), Vector2(0.04, 0.55), Vector2(0, 0.56)])
		Provisions.lathe(k, "own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), prof, 24, gun)
		for y: float in [0.2, 0.42]:
			ItemModels._torus(k, "own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(x, y, 0)), 0.087, 0.007, 24, 6, dark)
		# Ribbed nozzle: stacked rings narrowing then flaring.
		var noz := PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.055, 0.1), Vector2(0.055, 0.085), Vector2(0.062, 0.08), Vector2(0.062, 0.07), Vector2(0.055, 0.065), Vector2(0.055, 0.05), Vector2(0.065, 0.045), Vector2(0.065, 0.03), Vector2(0.07, 0.0), Vector2(0.05, 0.0), Vector2(0.04, 0.03)])
		var flipped := PackedVector2Array()
		for i in range(noz.size() - 1, -1, -1):
			flipped.append(noz[i])
		Provisions.lathe(k, "own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), flipped, 24, dark)
		k.box("own:plate_dark", Transform3D(Basis.IDENTITY, Vector3(s * 0.11, 0.3, 0)), Vector3(0.04, 0.3, 0.06), dark)
		# Shoulder hoop.
		var hp := PackedVector3Array()
		for i in 11:
			var a := PI * i / 10.0
			hp.append(Vector3(s * (0.06 + 0.05 * (1.0 - cos(a)) * 0.5), 0.5 + sin(a) * 0.08, -0.03 - (1.0 - cos(a)) * 0.04))
		_strap(k, "own:plate_dark", Transform3D.IDENTITY, hp, Vector3.BACK, 0.03, 0.012, dark)
	return Vector3(0, 0.56, -0.05)

## The jetpack: twin silver rocket tanks with pointed noses, banded in copper, a copper
## panel down the right tank, a small tank between, fins at the outer feet and grey bell
## nozzles beneath.
static func _jetpack(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var silver := Color(0.7, 0.71, 0.73)
	var copper := Color(0.82, 0.5, 0.24)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.12
		var prof := PackedVector2Array([Vector2(0.0, 0.11), Vector2(0.06, 0.11), Vector2(0.08, 0.13), Vector2(0.082, 0.4), Vector2(0.075, 0.45), Vector2(0.058, 0.5), Vector2(0.032, 0.54), Vector2(0.0, 0.56)])
		Provisions.lathe(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), prof, 32, silver)
		for y: float in [0.385, 0.2]:
			k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(x, y, 0)), 0.085, 0.085, 0.032, 32, false, 0.0, 1, copper)
		# Bell nozzle.
		var bell := PackedVector2Array([Vector2(0.03, 0.115), Vector2(0.035, 0.09), Vector2(0.05, 0.05), Vector2(0.066, 0.0), Vector2(0.06, 0.0), Vector2(0.04, 0.05)])
		Provisions.lathe(k, "im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), bell, 24, Color(0.55, 0.55, 0.57))
		# A swept fin at the outer foot.
		var a := Vector3(x + s * 0.075, 0.24, 0.0)
		var b := Vector3(x + s * 0.13, 0.05, 0.0)
		var c := Vector3(x + s * 0.078, 0.11, 0.0)
		for dz: float in [0.004, -0.004]:
			ItemModels._tri(k, "im:metal@0.3", Transform3D.IDENTITY, a + Vector3(0, 0, dz), b + Vector3(0, 0, dz), c + Vector3(0, 0, dz), Vector3(0, 0, signf(dz)), Vector3(0, 0, signf(dz)), Vector3(0, 0, signf(dz)), silver.darkened(0.05))
	# The copper panel down the right tank's outer face.
	k.bevel_box("im:metal@0.35", Transform3D(Basis(Vector3.UP, -0.6), Vector3(0.165, 0.3, 0.055)), Vector3(0.03, 0.15, 0.012), 0.004, copper)
	# The small centre tank, a frame behind them all.
	var prof2 := PackedVector2Array([Vector2(0.0, 0.18), Vector2(0.035, 0.18), Vector2(0.04, 0.2), Vector2(0.04, 0.38), Vector2(0.03, 0.41), Vector2(0.0, 0.42)])
	Provisions.lathe(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.02)), prof2, 24, silver.darkened(0.05))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0.02)), 0.041, 0.006, 24, 6, copper)
	k.bevel_box("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -0.05)), Vector3(0.2, 0.3, 0.03), 0.01, silver.darkened(0.25))
	for y: float in [0.38, 0.22]:
		k.bevel_box("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, y, -0.02)), Vector3(0.16, 0.03, 0.04), 0.006, silver.darkened(0.15))
	return Vector3(0, 0.45, -0.05)

## Chitin wings: two pairs of long translucent membranes, pale and veined in red-brown,
## hanging in a V from a dark red segmented spine. Alien.
static func _wings_chitin(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var red := Color(0.26, 0.08, 0.06)
	var vein := Color(0.5, 0.2, 0.12)
	# The spine: segments narrowing down, with spurs.
	for i in 9:
		var y := 0.55 - i * 0.065
		var rad := 0.045 - i * 0.004
		k.sphere("im:enamel", Transform3D(Basis.IDENTITY, Vector3(0, y, 0.01)), rad, 6, 10, 0.0, 0.8, red.darkened(0.1 * (i % 2)))
		for s: float in [-1.0, 1.0]:
			Provisions.tube(k, "im:enamel", Transform3D.IDENTITY, PackedVector3Array([Vector3(s * rad * 0.7, y, 0.01), Vector3(s * (rad + 0.025), y - 0.015, 0.02)]), PackedFloat32Array([0.007, 0.0005]), 5, red)
	# Four wings: root by the shoulders, tip far below and out.
	for w: Array in [[1.0, Vector2(0.45, -0.3), 0.22, 0.02], [1.0, Vector2(0.24, -0.34), 0.17, -0.0], [-1.0, Vector2(0.45, -0.3), 0.22, 0.02], [-1.0, Vector2(0.24, -0.34), 0.17, -0.0]]:
		var s: float = w[0]
		var tip: Vector2 = w[1]
		var wid: float = w[2]
		var root := Vector2(0.03, 0.55)
		var along := (Vector2(tip.x * s, tip.y) - Vector2(root.x * s, root.y))
		var dir := along.normalized()
		var side := Vector2(-dir.y, dir.x) * s * -1.0
		var f := func(u: float, v: float) -> Vector3:
			var c := Vector2(root.x * s, root.y) + along * u
			var half := wid * 0.5 * sin(PI * pow(u, 0.7)) * (0.35 + 0.65 * u)
			var p := c + side * lerpf(-half, half, v)
			return Vector3(p.x, p.y, float(w[3]) - u * 0.04 + sin(v * PI) * 0.01)
		ItemModels._sheet(k, "own:membrane", Transform3D.IDENTITY, f, 16, 4, 0.002, Color(0.94, 0.88, 0.78, 0.72), Color(0.9, 0.82, 0.72, 0.72))
		# Veins along and across.
		for vv: float in [0.0, 0.33, 0.66, 1.0]:
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 17:
				var u := i / 16.0
				path.append((f.call(u, vv) as Vector3) + Vector3(0, 0, 0.002))
				radii.append((0.004 if vv == 0.0 or vv == 1.0 else 0.0022) * (1.0 - u * 0.6))
			Provisions.tube(k, "im:enamel", Transform3D.IDENTITY, path, radii, 4, vein if vv > 0.0 and vv < 1.0 else red)
		for i in range(2, 15, 2):
			var u := i / 16.0
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for j in 5:
				path.append((f.call(u + sin(j * 1.7) * 0.01, j / 4.0) as Vector3) + Vector3(0, 0, 0.002))
				radii.append(0.0016)
			Provisions.tube(k, "im:enamel", Transform3D.IDENTITY, path, radii, 4, vein)
	return Vector3(0, 0.5, -0.02)

## The halo pack: a gilded spine crowned by a silver crystal, holding out two great gold
## rings, each round a disc of deep blue-violet light. Alien: the discs glow faintly.
static func _halo_pack(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var gold := Color(0.86, 0.64, 0.3)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(s * 0.19, 0.2, 0.0)
		var o := Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.85, 1.0, 1.0)), c)
		ItemModels._torus(k, "im:metal@0.3", o, 0.13, 0.022, 40, 10, gold)
		ItemModels._torus(k, "im:metal@0.3", o.translated_local(Vector3(0, 0.012, 0)), 0.1, 0.008, 40, 6, gold.darkened(0.15))
		ItemModels._torus(k, "im:metal@0.3", o.translated_local(Vector3(0, 0.0, 0)), 0.165, 0.007, 40, 6, gold.lightened(0.05))
		for i in 12:
			var a := TAU * i / 12.0
			var p := c + Vector3(cos(a) * 0.13 * 0.85, sin(a) * 0.13, 0.022)
			_rivet(k, "im:metal@0.3", Transform3D.IDENTITY, p, Vector3.BACK, 0.007, gold.lightened(0.1))
		# The disc of light, domed.
		var cc := Vector2(c.x, c.y)
		var rows := _radial(_circle(0.088, 40, cc, 1.18), cc, 5, func(p: Vector2) -> float: return 0.014 * (1.0 - minf((p - cc).length_squared() / 0.011, 1.0)))
		_shell(k, "own:portal", Transform3D.IDENTITY, rows, 0.01, true, Color(0.4, 0.4, 1.0), Color(0.2, 0.2, 0.5))
		# Arms out to the rings.
		k.bevel_box("im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(s * 0.06, 0.2, -0.01)), Vector3(0.06, 0.05, 0.03), 0.008, gold.darkened(0.1))
	# The spine: stacked gilded plates and a silver crystal on top.
	for i in 5:
		var y := 0.06 + i * 0.07
		var w := 0.1 - absf(i - 2) * 0.014
		k.bevel_box("im:metal@0.3", Transform3D(Basis(Vector3.BACK, 0.0), Vector3(0, y, 0.0)), Vector3(w, 0.06, 0.05), 0.012, gold if i % 2 == 0 else gold.darkened(0.2))
	k.crystal("im:crystal:halo_pack", Transform3D(Basis.IDENTITY, Vector3(0, 0.38, 0.0)), 0.04, 0.13, 4, 0.5, Color(0.85, 0.88, 0.95, 0.9))
	k.crystal("im:crystal:halo_pack", Transform3D(Basis(Vector3.BACK, PI), Vector3(0, 0.03, 0.0)), 0.02, 0.07, 4, 0.5, Color(0.8, 0.82, 0.9, 0.9))
	return Vector3(0, 0.2, -0.03)

## The precursor cape: a gold collar with a blue stone at the clasp, the cape below in
## pleated panels of starry blue-violet cloth, each panel ending in a point. Alien: the
## stars in the weave shine faintly.
static func _cape_precursor(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var panels := 7
	var f := func(u: float, v: float) -> Vector3:
		var x := lerpf(-0.16, 0.16, u) * (1.0 - v) + lerpf(-0.5, 0.5, u) * v
		var ph := fposmod(u * panels, 1.0)
		var point := 1.0 - absf(ph - 0.5) * 2.0
		var len := 0.58 + 0.16 * point * point + 0.08 * sin(u * PI)
		var y := 0.8 - v * len
		var z := 0.035 * sin(u * panels * TAU) * (0.3 + v) - 0.12 * pow(absf(u - 0.5) * 2.0, 2.0) * (0.4 + v)
		return Vector3(x, y, z)
	var col := func(p: Vector3) -> Color:
		return Color(0.2, 0.2, 0.6)
	# Pleats: the crests catch a lavender light, the folds deep blue.
	var rows: Array = []
	var nu := panels * 8
	var nv := 14
	for j in nv + 1:
		var row := PackedVector3Array()
		for i in nu + 1:
			row.append(f.call(float(i) / nu, float(j) / nv))
		rows.append(row)
	var shade := func(p: Vector3) -> Color:
		var crest := clampf(p.z * 30.0 + 0.5, 0.0, 1.0)
		return Color(0.14, 0.12, 0.46).lerp(Color(0.62, 0.58, 0.95), crest * crest * 0.85)
	_grid(k, "own:starcloth", Transform3D.IDENTITY, rows, false, shade, Vector3.BACK)
	var back: Array = []
	for row: PackedVector3Array in rows:
		var b := PackedVector3Array()
		for p in row:
			b.append(p - Vector3(0, 0, 0.004))
		back.append(b)
	_grid(k, "own:starcloth", Transform3D.IDENTITY, back, false, Color(0.08, 0.07, 0.25), Vector3.FORWARD)
	# The collar: a gilded crescent across the shoulders with the stone at its middle.
	var cp := PackedVector3Array()
	var cr := PackedFloat32Array()
	for i in 17:
		var u := i / 16.0
		cp.append(Vector3(lerpf(-0.2, 0.2, u), 0.8 + 0.03 * sin(u * PI), 0.01 - 0.06 * pow(absf(u - 0.5) * 2.0, 2.0)))
		cr.append(0.018 * (0.6 + 0.4 * sin(u * PI)))
	Provisions.tube(k, "im:metal@0.3", Transform3D.IDENTITY, cp, cr, 10, Color(0.85, 0.64, 0.3))
	for s: float in [-1.0, 1.0]:
		for i in 3:
			var x := s * (0.05 + i * 0.045)
			k.bevel_box("im:metal@0.3", Transform3D(Basis(Vector3.BACK, s * (0.4 + i * 0.25)), Vector3(x, 0.77 - i * 0.015, 0.02 - i * 0.008)), Vector3(0.025, 0.06, 0.01), 0.004, Color(0.82, 0.6, 0.28))
	k.sphere("im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0.83, 0.02)), 0.026, 8, 12, 0.0, 0.7, Color(0.85, 0.64, 0.3))
	k.sphere("own:glow_blue", Transform3D(Basis.IDENTITY, Vector3(0, 0.83, 0.036)), 0.015, 8, 12, 0.0, 0.8, Color(0.2, 0.25, 0.9))
	return Vector3(0, 0.8, -0.02)

## A leather quiver: a tooled brown tube with a braided rim at the foot and a stitched
## seam, a strap down its side with a buckle, a sheaf of arrows fletched in grey and white.
static func _quiver(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var brown := Color(0.33, 0.18, 0.09)
	var tooled := func(p: Vector3, a: float, _t2: float) -> Color:
		var n := absf(sin(a * 6.0 + p.y * 40.0)) * absf(sin(a * 6.0 - p.y * 40.0))
		return brown.lerp(brown.darkened(0.35), n * 0.6)
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.055, 0.01), Vector2(0.058, 0.25), Vector2(0.066, 0.5), Vector2(0.064, 0.5), Vector2(0.06, 0.49)])
	Provisions.lathe(k, "im:leather_armour", Transform3D.IDENTITY, prof, 28, tooled)
	ItemModels._torus(k, "im:leather_armour", Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), 0.066, 0.006, 28, 6, brown.darkened(0.2))
	# The braided rim at the foot and a band above it.
	for i in 2:
		ItemModels._torus(k, "im:rope", Transform3D(Basis.IDENTITY, Vector3(0, 0.025 + i * 0.012, 0)), 0.057, 0.0065, 28, 6, Color(0.7, 0.55, 0.32))
	ItemModels._torus(k, "im:leather_armour", Transform3D(Basis.IDENTITY, Vector3(0, 0.42, 0)), 0.064, 0.005, 28, 6, brown.darkened(0.25))
	# The stitched seam down the front-right.
	var seam := PackedVector3Array()
	for i in 9:
		var y := lerpf(0.05, 0.48, i / 8.0)
		var rad := 0.058 + (y - 0.25) * 0.032 if y > 0.25 else 0.057
		seam.append(Vector3(cos(0.6) * (rad + 0.002), y, sin(0.6) * (rad + 0.002)))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, seam, Vector3(cos(0.6), 0, sin(0.6)), 0.012, 0.003, brown.darkened(0.3))
	# The strap: from the rim out down the right side to the foot, with a buckle.
	var sp := PackedVector3Array()
	for i in 13:
		var t := i / 12.0
		sp.append(Vector3(0.068 + sin(t * PI) * 0.06, lerpf(0.45, 0.06, t), -0.01 - sin(t * PI) * 0.02))
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, sp, Vector3.BACK, 0.028, 0.005, brown.darkened(0.15))
	_buckle(k, "im:metal@0.4", Transform3D.IDENTITY, Vector3(0.125, 0.3, -0.03), Vector3(0.3, 0, 1.0), Vector3(0.2, 1.0, 0), 0.036, 0.03, 0.005, Color(0.5, 0.48, 0.44))
	# The arrows.
	for i in 9:
		var a := TAU * i / 9.0 + r.randf() * 0.4
		var rr := 0.035 * sqrt(r.randf())
		var base := Vector3(cos(a) * rr, 0.12, sin(a) * rr)
		var tilt := Vector3(cos(a) * 0.08 + 0.06, 1.0, sin(a) * 0.05).normalized()
		var l := r.randf_range(0.6, 0.66)
		var top := base + tilt * (l - 0.12)
		Provisions.tube(k, "own:wood", Transform3D.IDENTITY, PackedVector3Array([base, top]), PackedFloat32Array([0.004, 0.004]), 6, Color(0.6, 0.45, 0.28))
		k.cylinder("im:bone", Transform3D(Basis(Quaternion(Vector3.UP, tilt)), top), 0.0045, 0.004, 0.012, 6, true, 0.0, 1, Color(0.85, 0.82, 0.75))
		# Three vanes, white with a grey bar.
		var side := tilt.cross(Vector3.BACK).normalized()
		for v in 3:
			var d := side.rotated(tilt, TAU * v / 3.0 + a)
			var p0 := top - tilt * 0.1
			var p1 := top - tilt * 0.012
			var vcol := Color(0.92, 0.92, 0.9) if v != 0 else Color(0.55, 0.55, 0.56)
			var q := [p0 + d * 0.003, p1 + d * 0.003, p1 + d * 0.016 - tilt * 0.01, p0 + d * 0.02 + tilt * 0.015]
			ItemModels._quad(k, "im:linen", Transform3D.IDENTITY, q[0], q[1], q[2], q[3], d.cross(tilt), vcol)
			ItemModels._quad(k, "im:linen", Transform3D.IDENTITY, q[3], q[2], q[1], q[0], -d.cross(tilt), vcol)
	return Vector3(0.08, 0.3, -0.02)

## An ammunition belt: a loop of studded brown leather buckled in brass, a row of brass
## cartridges with copper noses held in loops along the front.
static func _ammo_belt(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var brown := Color(0.22, 0.13, 0.07)
	var rx := 0.2
	var rz := 0.13
	var path := PackedVector3Array()
	var face := PackedVector3Array()
	for i in 49:
		var a := lerpf(PI * 0.95, PI * 0.95 + TAU * 1.04, i / 48.0)
		path.append(Vector3(cos(a) * rx, 0.0, sin(a) * rz))
		face.append(Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized())
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, path, face, 0.055, 0.005, brown)
	# Cartridges in loops along the front.
	var n := 17
	for i in n:
		var a := lerpf(PI * 0.12, PI * 0.88, float(i) / (n - 1))
		var nrm := Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized()
		var p := Vector3(cos(a) * rx, -0.036, sin(a) * rz) + nrm * 0.011
		var prof := PackedVector2Array([Vector2(0, 0), Vector2(0.0095, 0), Vector2(0.0095, 0.003), Vector2(0.0088, 0.004), Vector2(0.0088, 0.05), Vector2(0.0078, 0.053), Vector2(0.007, 0.062), Vector2(0.0045, 0.07), Vector2(0, 0.073)])
		var c := func(q: Vector3, _a: float, _t2: float) -> Color:
			return Color(0.5, 0.3, 0.18) if q.y > 0.051 else BRASS
		Provisions.lathe(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, p), prof, 12, c)
	# The loops over them: a second band, stitched between each round.
	var lp := PackedVector3Array()
	var lf := PackedVector3Array()
	for i in 25:
		var a := lerpf(PI * 0.08, PI * 0.92, i / 24.0)
		var nrm := Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized()
		lp.append(Vector3(cos(a) * rx, 0.0, sin(a) * rz) + nrm * 0.0205)
		lf.append(nrm)
	_strap(k, "im:leather_armour", Transform3D.IDENTITY, lp, lf, 0.03, 0.004, brown.lightened(0.05))
	# Studs along the top edge of the back half, and the brass buckle at the left.
	for i in 10:
		var a := lerpf(PI * 1.1, PI * 1.9, i / 9.0)
		var nrm := Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized()
		_rivet(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(cos(a) * rx, 0.015, sin(a) * rz) + nrm * 0.003, nrm, 0.004, BRASS)
	var ba := PI * 0.97
	var bn := Vector3(cos(ba) / rx, 0.0, sin(ba) / rz).normalized()
	_buckle(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(cos(ba) * rx, 0.0, sin(ba) * rz) + bn * 0.007, bn, Vector3.UP, 0.04, 0.062, 0.006, BRASS)
	return Vector3(-rx, 0, 0)

# --- Materials --------------------------------------------------------------------------

static var _mats := {}
static var _lock := Mutex.new()

static func mat(name: String) -> Material:
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_lock.unlock()
	return m

static func _std(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Bumps from a noise texture, laid triplanar.
static func _bump(m: StandardMaterial3D, key: String, freq: float, scale: float, strength: float, cellular := false) -> void:
	m.normal_enabled = true
	m.normal_texture = Materials._noise_tex(key, freq, true, 4, cellular)
	m.normal_scale = strength
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0

static func _make(n: String) -> Material:
	match n:
		"wood":
			# Planed boards: the grain photo laid along each plank by its own coordinates.
			var m := _std(0.82)
			var t := Materials.photo("planks", "detail")
			if t != null:
				m.albedo_texture = t
				m.albedo_color = Color(1.0 / 0.72, 1.0 / 0.72, 1.0 / 0.72)
			var nt := Materials.photo("planks", "normal")
			if nt != null:
				m.normal_enabled = true
				m.normal_texture = nt
				m.normal_scale = 0.6
			return m
		"forged":
			# Hand-forged iron: hammer marks in the normal, satin rather than mirror.
			var m := _std(0.5, 0.8)
			_bump(m, "sh_forged", 0.05, 5.0, 0.35)
			return m
		"hammered":
			# Bronze beaten from the sheet: dimpled all over, warm sheen.
			var m := _std(0.4, 0.85)
			_bump(m, "sh_hammer", 0.08, 6.0, 0.5, true)
			return m
		"plate":
			# Rolled and polished plate steel, a little worn.
			var m := _std(0.4, 0.8)
			_bump(m, "sh_forged", 0.05, 4.0, 0.2)
			return m
		"plate_dark":
			var m := _std(0.6, 0.45)
			_bump(m, "sh_plate_dark", 0.06, 6.0, 0.4)
			return m
		"tinted":
			# A tinted polymer panel: see-through, its colour in the vertices.
			var m := _std(0.15)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic_specular = 0.8
			return m
		"glow_violet":
			var m := _std(0.3)
			m.emission_enabled = true
			m.emission = Color(0.6, 0.3, 1.0)
			m.emission_energy_multiplier = 1.4
			return m
		"glow_blue":
			var m := _std(0.3)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.45, 1.0)
			m.emission_energy_multiplier = 0.7
			return m
		"void":
			# Starry violet-black glass: pinpricks of faint light in the deep.
			var m := _std(0.55)
			m.metallic_specular = 0.3
			m.albedo_texture = _stars_tex(false)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.0
			return m
		"void_orb":
			var m := _std(0.05)
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			return m
		"prism":
			var m := _std(0.05)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.metallic_specular = 1.0
			m.rim_enabled = true
			m.rim = 0.4
			m.emission_enabled = true
			m.emission = Color(0.35, 0.4, 1.0)
			m.emission_energy_multiplier = 0.25
			return m
		"membrane":
			# Insect wing: thin, see-through, light shining through it.
			var m := _std(0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.backlight_enabled = true
			m.backlight = Color(0.5, 0.4, 0.3)
			return m
		"hexcloth":
			# Optic camouflage weave: a fine hexagon lattice of faint gold threads.
			var m := _std(0.78)
			m.metallic_specular = 0.3
			m.albedo_texture = _hex_tex()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 9.0
			m.uv1_triplanar_sharpness = 6.0
			_bump(m, "sh_cloth", 0.15, 10.0, 0.3)
			m.albedo_texture = _hex_tex()
			return m
		"starcloth":
			# Precursor cloth: deep blue-violet with pinpricks of faint light woven in.
			var m := _std(0.7)
			m.metallic_specular = 0.3
			m.albedo_texture = _stars_tex(false)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 3.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"portal":
			# A disc of deep blue light, brightest at its heart.
			var m := _std(0.1)
			m.albedo_texture = _stars_tex(false)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.35, 1.0)
			m.emission_energy_multiplier = 0.6
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 4.0
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			return m
	return ItemModels.mat("im:paint")

static var _tex := {}

## A starfield: violet-black with nebula haze (albedo), or just the stars (emission).
static func _stars_tex(emit: bool) -> Texture2D:
	var key := "stars_%s" % emit
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.frequency = 0.02
	for y in 256:
		for x in 256:
			var h := 0.5 + 0.5 * nz.get_noise_2d(x, y)
			img.set_pixel(x, y, Color(0, 0, 0) if emit else Color(0.25 + 0.5 * h, 0.2 + 0.25 * h, 0.4 + 0.6 * h))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 260:
		var x := r.randi_range(0, 255)
		var y := r.randi_range(0, 255)
		var b := r.randf_range(0.5, 1.0)
		img.set_pixel(x, y, Color(b, b, b))
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

## A hexagon lattice: thin pale threads (white, tinted by the vertices) on a dark ground,
## tiling seamlessly (the cells nearest each pixel, across the wrap).
static func _hex_tex() -> Texture2D:
	if _tex.has("hex"):
		return _tex["hex"]
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var nx := 4
	var ny := 4
	var cw := 256.0 / nx
	var ch := 256.0 / ny
	var pts: Array = []
	for j in ny:
		for i in nx:
			for o: Vector2 in [Vector2(0, 0), Vector2(0.5, 0.5)]:
				pts.append(Vector2((i + o.x) * cw, (j + o.y) * ch))
	for y in 256:
		for x in 256:
			var d1 := 1e9
			var d2 := 1e9
			for p: Vector2 in pts:
				var dx := absf(x - p.x)
				var dy := absf(y - p.y)
				dx = minf(dx, 256.0 - dx)
				dy = minf(dy, 256.0 - dy)
				var d := sqrt(dx * dx + dy * dy * 1.3)
				if d < d1:
					d2 = d1
					d1 = d
				elif d < d2:
					d2 = d
			var line := clampf(1.0 - (d2 - d1) / 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.5, 0.5, 0.52).lerp(Color(1.0, 0.82, 0.4), line))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["hex"] = t
	return t

## The town watch's tabard: a sleeveless wool tunic quartered gold and red, the town's
## gold shield with its red tower on the breast, leather side straps, and the hem worn
## ragged. Laid out flat, face on +Z.
static func _watch_tabard(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var red := Color(0.55, 0.09, 0.07)
	var gold := Color(0.68, 0.46, 0.1)
	var H := 0.56
	var half := func(v: float) -> float:
		# Wider at the hem, cut in for the arms, out again to the shoulders.
		var hw := lerpf(0.2, 0.165, smoothstep(0.0, 0.6, v))
		return hw - 0.04 * smoothstep(0.62, 0.8, v) * (1.0 - smoothstep(0.9, 1.0, v) * 0.6)
	var hem := func(x: float) -> float:
		return 0.03 * absf(sin(x * 61.0 + sin(x * 23.0) * 2.0)) + 0.012 * sin(x * 140.0)
	var top := func(x: float) -> float:
		return H - (0.045 * cos(absf(x) / 0.065 * PI * 0.5) if absf(x) < 0.065 else 0.0)
	var rows: Array = []
	var nu := 48
	var nv := 28
	for j in nv + 1:
		var v := float(j) / nv
		var row := PackedVector3Array()
		for i in nu + 1:
			var u := float(i) / nu
			var x: float = (u - 0.5) * 2.0 * half.call(v)
			var y: float = lerpf(hem.call(x), top.call(x), v)
			row.append(Vector3(x, y, 0.007 * sin(x * 30.0) * smoothstep(0.07, 0.13, absf(x))))
		rows.append(row)
	var mid := 0.3
	var col := func(p: Vector3) -> Color:
		var c: Color = red if (p.x < 0.0) == (p.y > mid) else gold
		return c.darkened(0.08 * (Provisions._nz(p, 90.0) + 0.3))
	_shell(k, "im:wool", Transform3D.IDENTITY, rows, 0.004, false, col, Color(0.3, 0.2, 0.12))
	# The breast shield: gold with a red rim, the red tower with its battlements and door.
	var sh := PackedVector2Array([Vector2(-0.058, 0.445), Vector2(0.058, 0.445), Vector2(0.058, 0.39), Vector2(0.05, 0.36), Vector2(0.032, 0.335), Vector2(0.0, 0.315), Vector2(-0.032, 0.335), Vector2(-0.05, 0.36), Vector2(-0.058, 0.39)])
	TechModels._ext(k, "im:wool", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0008)), sh, [], 0.0012, red.darkened(0.1))
	var inner: Array = Geometry2D.offset_polygon(sh, -0.005)
	TechModels._ext(k, "im:wool", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0016)), inner[0], [], 0.0012, gold.lightened(0.05))
	var tz := 0.0024
	k.box("im:wool", Transform3D(Basis.IDENTITY, Vector3(0, 0.37, tz)), Vector3(0.03, 0.05, 0.0012), red)
	k.box("im:wool", Transform3D(Basis.IDENTITY, Vector3(0, 0.398, tz)), Vector3(0.04, 0.008, 0.0012), red)
	for i in 3:
		k.box("im:wool", Transform3D(Basis.IDENTITY, Vector3((i - 1) * 0.016, 0.405, tz)), Vector3(0.008, 0.009, 0.0012), red)
	k.box("im:wool", Transform3D(Basis.IDENTITY, Vector3(0, 0.355, tz + 0.0004)), Vector3(0.01, 0.018, 0.0012), gold.darkened(0.45))
	# Leather straps buckled at the sides.
	for s: float in [-1.0, 1.0]:
		for y: float in [0.24, 0.38]:
			var v := y / H
			var x: float = s * half.call(v)
			k.box("im:leather_armour", Transform3D(Basis.IDENTITY, Vector3(x + s * 0.008, y, 0.002)), Vector3(0.03, 0.012, 0.004), LEATHER.lightened(0.1))
			k.box("im:metal@0.5", Transform3D(Basis.IDENTITY, Vector3(x + s * 0.02, y, 0.0045)), Vector3(0.008, 0.014, 0.002), Color(0.4, 0.38, 0.34))
	return Vector3(0, 0.5, 0)
