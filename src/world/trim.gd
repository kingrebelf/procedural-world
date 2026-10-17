class_name Trim
## Finishing trim: the mouldings, casings, sills and corner posts that finish a room
## where its walls meet the floor, the ceiling, a doorway or a window, and the plinth
## courses and corbels that finish a building outside. All of it is drawn into the
## room's or building's own MeshKit (one mesh, a few shared materials), as swept
## profiles (MeshKit.sweep) and chamfered blocks (MeshKit.bevel_box).
##
## A profile lists its visible faces from the wall (s = 0) round to the floor or
## ceiling (f = 0): s out from the wall, f up from the floor (or down from the ceiling).

## A timber skirting board, 15 cm, its top edge rounded over.
const SKIRT := [Vector2(0, 0.15), Vector2(0.009, 0.15), Vector2(0.016, 0.147), Vector2(0.021, 0.14), Vector2(0.022, 0.132), Vector2(0.022, 0)]
## A dressed stone plinth course at the foot of a wall, its top weathered off.
const PLINTH := [Vector2(0, 0.3), Vector2(0.02, 0.3), Vector2(0.06, 0.262), Vector2(0.06, 0)]
## A stone water table round a building's foot outside: a deep sloped top sheds rain.
const WATER_TABLE := [Vector2(0, 0.5), Vector2(0.03, 0.5), Vector2(0.16, 0.39), Vector2(0.16, 0)]
## A hewn timber wall plate under a ceiling (f down from the ceiling), its lower edge
## chamfered as the carpenter's draw knife left it.
const WALL_PLATE := [Vector2(0, 0.2), Vector2(0.14, 0.2), Vector2(0.18, 0.16), Vector2(0.18, 0)]
## Arch and jamb casings (s across the band from the opening, f proud of the wall,
## from the front at the opening's edge): a flat band, its inner edge chamfered, its
## outer edge rounded over.
const CASING := [Vector2(0, 0.016), Vector2(0.006, 0.022), Vector2(0.075, 0.022), Vector2(0.086, 0.016), Vector2(0.09, 0.006), Vector2(0.09, 0)]

## A cove (f down from the ceiling or a beam): a fillet on the wall, a quarter round
## hollow and a fillet out at `d`.
static func cove(h: float, d: float, fillet := 0.01, steps := 4) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(0, h), Vector2(fillet, h)])
	for i in range(1, steps):
		var a := PI + PI * 0.5 * i / steps
		out.append(Vector2(d + (d - fillet) * cos(a), h + (h - fillet) * sin(a)))
	out.append(Vector2(d, fillet))
	out.append(Vector2(d, 0))
	return out

## A moulding round a rectangular room, against its walls: x0..x1 by z0..z1 are the
## walls' faces, at height y (the floor for a skirting, the ceiling for a cornice, with
## `down`); `outside` runs it round the outside of a building instead. `gaps` leave doorways open: [side, from, to] with side "+z", "-z", "+x" or
## "-x" and from/to along x (on a z wall) or z (on an x wall). Corners are mitred; runs
## that stop at a gap end in a cap.
static func room(k: MeshKit, mat: String, profile: Array, x0: float, x1: float, z0: float, z1: float, y: float, gaps: Array = [], down := false, outside := false) -> void:
	var face := Vector3.DOWN if down else Vector3.UP
	var o := -1.0 if outside else 1.0
	var prof := PackedVector2Array(profile)
	# The walls round the room, clockwise seen from above: each [start, end, inward side].
	var walls := [
		["-z", Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(0, 0, o)],
		["+x", Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(-o, 0, 0)],
		["+z", Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3(0, 0, -o)],
		["-x", Vector3(x0, y, z1), Vector3(x0, y, z0), Vector3(o, 0, 0)],
	]
	if gaps.is_empty():
		var path := PackedVector3Array()
		var sides := PackedVector3Array()
		for i in 4:
			var prev: Vector3 = walls[(i + 3) % 4][3]
			var cur: Vector3 = walls[i][3]
			path.append(walls[i][1])
			sides.append(prev + cur)
		k.sweep(mat, Transform3D.IDENTITY, path, sides, face, prof, true)
		return
	# With doorways, each wall is its own run (or runs): corners still mitred, ends at
	# a doorway capped.
	for i in 4:
		var w: Array = walls[i]
		var a: Vector3 = w[1]
		var b: Vector3 = w[2]
		var dir := (b - a).normalized()
		var side: Vector3 = w[3]
		var sa: Vector3 = (walls[(i + 3) % 4][3] as Vector3) + side
		var sb: Vector3 = (walls[(i + 1) % 4][3] as Vector3) + side
		var pieces := [[0.0, a.distance_to(b)]]
		for g in gaps:
			if g[0] != w[0]:
				continue
			# Gap ends along this run, whichever way it goes.
			var axis := 0 if absf(dir.x) > 0.5 else 2
			var t0 := (float(g[1]) - a[axis]) / dir[axis]
			var t1 := (float(g[2]) - a[axis]) / dir[axis]
			var lo := minf(t0, t1)
			var hi := maxf(t0, t1)
			var next: Array = []
			for p in pieces:
				if hi <= p[0] or lo >= p[1]:
					next.append(p)
					continue
				if lo > p[0] + 0.02:
					next.append([p[0], lo])
				if hi < p[1] - 0.02:
					next.append([hi, p[1]])
			pieces = next
		var full := a.distance_to(b)
		for p in pieces:
			var path := PackedVector3Array([a + dir * float(p[0]), a + dir * float(p[1])])
			var sides := PackedVector3Array([sa if p[0] < 0.001 else side, sb if p[1] > full - 0.001 else side])
			k.sweep(mat, Transform3D.IDENTITY, path, sides, face, prof, false, true)

## A casing round a doorway or window on a wall: `xf` puts the wall's face at z = 0
## facing +z, `edge` is the opening's outline on it (x, y), up one jamb, over the head
## and down the other, as the kit's arch is cut. The band stands off the wall and out
## from the opening; its feet stand on the floor.
static func casing(k: MeshKit, mat: String, xf: Transform3D, edge: PackedVector2Array, profile: Array = CASING) -> void:
	var path := PackedVector3Array()
	var sides := PackedVector3Array()
	var n := edge.size()
	for i in n:
		var p := edge[i]
		path.append(Vector3(p.x, p.y, 0))
		var t_in := (edge[i] - edge[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var t_out := (edge[i + 1] - edge[i]).normalized() if i < n - 1 else Vector2.ZERO
		# Away from the opening: the outline runs clockwise seen from the front (up the
		# left jamb, over to the right), so the outside is on its left.
		var o := Vector2.ZERO
		for t in [t_in, t_out]:
			if t != Vector2.ZERO:
				o += Vector2(-t.y, t.x)
		o = o.normalized()
		var tt: Vector2 = t_out if t_out != Vector2.ZERO else t_in
		var cs := absf(o.dot(Vector2(-tt.y, tt.x)))
		o /= maxf(cs, 0.5)
		sides.append(Vector3(o.x, o.y, 0))
	k.sweep(mat, xf, path, sides, Vector3(0, 0, 1), _casing_profile(profile), false, true)

## A casing profile as sweep wants it: from the wall at the opening's edge, round the
## band's front, to the wall at its outer edge.
static func _casing_profile(profile: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(0, 0))
	for q in profile:
		out.append(q)
	return out

## The kit village doorway's opening on the wall's inner face (Wall_*_Door_Round): the
## jambs from the floor to 2.156 and the round head.
const KIT_DOOR := [Vector2(-0.649, 0.0), Vector2(-0.649, 2.156), Vector2(-0.505, 2.3), Vector2(-0.341, 2.399), Vector2(-0.172, 2.457),
	Vector2(0.004, 2.473), Vector2(0.174, 2.457), Vector2(0.343, 2.399), Vector2(0.505, 2.3), Vector2(0.655, 2.156), Vector2(0.655, 0.0)]
## Where the kit village walls' plaster (inner) face lies, in from the wall's line.
const KIT_PLASTER := 0.2
## The bottom of the kit's wide round window frame (Window_Wide_Round1), and its half
## width and how far it stands in from the wall's line.
const KIT_WINDOW_FOOT := 1.016
const KIT_WINDOW_HALF := 0.682
const KIT_WINDOW_IN := 0.252

## The trim on the inner face of a kit village wall module: `xf` is the module's own
## transform (its line at z = 0, the room toward -z). A skirting board along the foot
## (broken for a doorway, which gets a casing), and under a window an inside sill on a
## small apron. `floor` is how high the room's floor stands on the module's foot.
static func kit_wall(k: MeshKit, xf: Transform3D, kind: String, floor := 0.0, skirting := true) -> void:
	var I := Transform3D.IDENTITY
	var inner := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -KIT_PLASTER))
	if skirting:
		var runs := [[-1.0, 1.0]] if kind != "door" else [[-1.0, -0.649], [0.655, 1.0]]
		for r in runs:
			# Seen from the room, the wall runs the other way.
			var path := PackedVector3Array([Vector3(-float(r[1]), floor, 0), Vector3(-float(r[0]), floor, 0)])
			var sides := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1)])
			k.sweep("timber", inner, path, sides, Vector3.UP, PackedVector2Array(SKIRT), false, true)
	match kind:
		"door":
			var edge := PackedVector2Array()
			for i in range(KIT_DOOR.size() - 1, -1, -1):
				var p: Vector2 = KIT_DOOR[i]
				edge.append(Vector2(-p.x, maxf(p.y, floor)))
			casing(k, "timber", inner, edge)
		"window":
			var deep := KIT_WINDOW_IN - KIT_PLASTER + 0.1
			var y := KIT_WINDOW_FOOT
			k.bevel_box("timber", inner * I.translated(Vector3(0, y - 0.025, deep * 0.5)), Vector3(KIT_WINDOW_HALF * 2.0 + 0.16, 0.05, deep), 0.012)
			k.bevel_box("timber", inner * I.translated(Vector3(0, y - 0.1, 0.012)), Vector3(KIT_WINDOW_HALF * 2.0 + 0.02, 0.1, 0.024), 0.008)

## A row of stone corbels under a cornice or wall plate along a wall: `xf` puts the
## wall's face at z = 0 facing +z, the corbels' tops at y = 0, centred at each x.
static func corbels(k: MeshKit, mat: String, xf: Transform3D, xs: Array, w := 0.22, h := 0.3, d := 0.22) -> void:
	for x in xs:
		var c := xf * Transform3D.IDENTITY.translated(Vector3(float(x), 0, 0))
		# Two courses, the lower set back and shallower: a stepped bracket.
		k.bevel_box(mat, c * Transform3D.IDENTITY.translated(Vector3(0, -h * 0.3, d * 0.5)), Vector3(w, h * 0.6, d), 0.02)
		k.bevel_box(mat, c * Transform3D.IDENTITY.translated(Vector3(0, -h * 0.8, d * 0.3)), Vector3(w * 0.85, h * 0.4, d * 0.6), 0.025)

## A wall corner post inside a room: a square timber, its arrises chamfered, from y0 to
## y1, its centre set in by half its width from both walls at (x, z) toward the room.
static func corner_post(k: MeshKit, mat: String, corner: Vector3, into: Vector3, y0: float, y1: float, w := 0.13) -> void:
	var c := corner + Vector3(signf(into.x), 0, signf(into.z)) * w * 0.5
	k.bevel_box(mat, Transform3D.IDENTITY.translated(Vector3(c.x, (y0 + y1) * 0.5, c.z)), Vector3(w, y1 - y0, w), 0.02)
