class_name PowerKit
## Meshes for the powered pieces (generators, batteries, poles, switches and lamps), built
## with MeshKit from the game's photo materials: riveted iron, painted steel, oak, brass
## and glass, early-industrial rather than sci-fi. proc() makes a piece's still parts (they
## go in the chunk's MultiMesh like any piece); part() makes the parts that move or light
## up, which PowerNode poses: a windmill's head and sails, a switch's blade, a lamp's bulb.
## Free-standing pieces face you with their local -z (BuildCatalog turns them that way);
## wall pieces stand out of the wall along +z; ceiling pieces hang down from their origin.

const COPPER := Color(0.78, 0.46, 0.28)
const BRASS := Color(0.8, 0.64, 0.32)
const ENGINE_GREEN := Color(0.24, 0.33, 0.25)
const GASIFIER := Color(1.0, 0.97, 0.94) ## a tint over the cast iron
const ENAMEL := Color(0.86, 0.85, 0.8)
const CERAMIC := Color(0.92, 0.9, 0.86)
const STEEL_GREY := Color(0.36, 0.4, 0.38) ## painted sheet steel on switchgear

static var _parts := {}
static var _lock := Mutex.new()

## A round bar of radius r from a to b.
static func beam(k: MeshKit, mat: String, a: Vector3, b: Vector3, r: float, segs := 6, color := Color.WHITE) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	k.cylinder(mat, Transform3D(Basis(x, y, z), a), r, r, l, segs, true, 0.0, 1, color)

## A square timber from a to b, `w` thick.
static func timber(k: MeshKit, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	k.box("timber", Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, l, w))

## Bolt heads in a row from a to b.
static func rivets(k: MeshKit, a: Vector3, b: Vector3, n: int, out: Vector3, r := 0.018) -> void:
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		var y := out.normalized()
		var x := y.cross(Vector3.FORWARD) if absf(y.z) < 0.9 else y.cross(Vector3.RIGHT)
		x = x.normalized()
		k.sphere("cast_iron", Transform3D(Basis(x, y, x.cross(y)), p), r, 3, 6, 0.0, 0.6, Color.WHITE, true)

## A white glazed insulator standing on `at`, pointing up.
static func insulator(k: MeshKit, at: Vector3) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("bone", I.translated(at), 0.012, 0.012, 0.05, 6)
	for n in 3:
		k.cylinder("bone", I.translated(at + Vector3(0, 0.05 + n * 0.03, 0)), 0.045 - n * 0.006, 0.03 - n * 0.004, 0.026, 10, true, 0.0, 1, CERAMIC)

## A small painted steel box on the wall, its face toward +z, for the logic pieces.
static func _logic_box(k: MeshKit, color: Color) -> void:
	var I := Transform3D.IDENTITY
	k.box("painted", I.translated(Vector3(0, 0, 0.04)), Vector3(0.22, 0.3, 0.08), color)
	k.box("painted", I.translated(Vector3(0, 0, 0.081)), Vector3(0.2, 0.28, 0.003), color.lightened(0.06))
	for c in [Vector2(-0.09, -0.13), Vector2(0.09, -0.13), Vector2(-0.09, 0.13), Vector2(0.09, 0.13)]:
		k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(c.x, c.y, 0.083)), 0.008, 0.008, 0.006, 6)
	_box_terminal(k, Vector3(0, -0.15, 0.04))

## An open box on the wall (back and four sides, no front) for a glass front to close.
static func _case(k: MeshKit, mat: String, size: Vector3, color: Color) -> void:
	var I := Transform3D.IDENTITY
	var t := 0.012
	k.box(mat, I.translated(Vector3(0, 0, t * 0.5)), Vector3(size.x, size.y, t), color.darkened(0.25))
	for sy in [-1.0, 1.0]:
		k.box(mat, I.translated(Vector3(0, sy * (size.y - t) * 0.5, size.z * 0.5)), Vector3(size.x, t, size.z), color)
	for sx in [-1.0, 1.0]:
		k.box(mat, I.translated(Vector3(sx * (size.x - t) * 0.5, 0, size.z * 0.5)), Vector3(t, size.y, size.z), color)

## A thin cast-iron plate the small pieces are screwed to the wall on.
static func _wall_plate(k: MeshKit, size: Vector2) -> void:
	k.box("cast_iron", Transform3D.IDENTITY.translated(Vector3(0, -0.02, 0.006)), Vector3(size.x, size.y, 0.012), GASIFIER.darkened(0.1))
	rivets(k, Vector3(0, size.y * 0.5 - 0.035, 0.013), Vector3(0, size.y * 0.5 - 0.035, 0.013), 1, Vector3(0, 0, 1))
	rivets(k, Vector3(0, -size.y * 0.5 - 0.005, 0.013), Vector3(0, -size.y * 0.5 - 0.005, 0.013), 1, Vector3(0, 0, 1))

## The brass binding post a signal wire is screwed to.
static func _box_terminal(k: MeshKit, at: Vector3) -> void:
	k.cylinder("gold", Transform3D.IDENTITY.translated(at + Vector3(0, -0.02, 0)), 0.012, 0.014, 0.025, 8, true, 0.0, 1, BRASS)

## An enamel dial facing +z with tick marks and a pointer at angle `needle` (radians).
static func _dial(k: MeshKit, at: Vector3, r: float, ticks: int, needle: float) -> void:
	k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), at), r, r, 0.004, 20, true, 0.0, 1, ENAMEL)
	for n in ticks:
		var a := TAU * n / ticks
		k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -a), at + Vector3(sin(a), cos(a), 0) * r * 0.82 + Vector3(0, 0, 0.004)), Vector3(r * 0.06, r * 0.18, 0.002), Color(0.1, 0.1, 0.1))
	k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -needle), at + Vector3(sin(needle), cos(needle), 0) * r * 0.35 + Vector3(0, 0, 0.007)), Vector3(r * 0.07, r * 0.75, 0.002), Color(0.55, 0.1, 0.08))

static func proc(k: MeshKit, what: String) -> void:
	var I := Transform3D.IDENTITY
	match what:
		"pw_woodgas":
			# A timber skid; on it a tall riveted gasifier drum (fed from the top hatch), a
			# filter pot, and a little single-cylinder engine with a flywheel turning the
			# dynamo. Front (-z): the fuel hatch, a gauge and the dynamo's brass terminals.
			for x in [-0.55, 0.55]:
				k.box("planks", I.translated(Vector3(x, 0.06, 0)), Vector3(0.14, 0.12, 1.1))
			k.box("planks", I.translated(Vector3(0, 0.15, 0)), Vector3(1.5, 0.06, 1.1))
			var drum := Vector3(-0.38, 0.18, 0.05)
			k.cylinder("cast_iron", I.translated(drum), 0.34, 0.34, 1.35, 16, true, 0.0, 1, GASIFIER)
			for y in [0.2, 0.68, 1.16]:
				k.cylinder("cast_iron", I.translated(drum + Vector3(0, y, 0)), 0.355, 0.355, 0.04, 16, true, 0.0, 1, GASIFIER.darkened(0.15))
			k.cylinder("cast_iron", I.translated(drum + Vector3(0, 1.35, 0)), 0.36, 0.2, 0.12, 16, true, 0.0, 1, GASIFIER)
			# Hopper hatch on the top, with its lever.
			k.cylinder("cast_iron", I.translated(drum + Vector3(0, 1.47, 0)), 0.2, 0.2, 0.05, 14, true, 0.0, 1, GASIFIER.darkened(0.2))
			beam(k, "cast_iron", drum + Vector3(0, 1.53, 0), drum + Vector3(0.18, 1.62, -0.1), 0.012)
			# Ash door low on the front.
			k.box("cast_iron", I.translated(drum + Vector3(0, 0.38, -0.33)), Vector3(0.28, 0.22, 0.04), GASIFIER.darkened(0.25))
			rivets(k, drum + Vector3(-0.12, 0.29, -0.355), drum + Vector3(0.12, 0.29, -0.355), 4, Vector3.BACK * -1.0)
			# Gas pipe over to the filter pot and on to the engine.
			var pot := Vector3(0.12, 0.18, 0.35)
			k.cylinder("cast_iron", I.translated(pot), 0.15, 0.15, 0.6, 12, true, 0.0, 1, GASIFIER.lightened(0.1))
			beam(k, "rust", drum + Vector3(0.2, 1.2, 0.2), pot + Vector3(0, 0.72, 0), 0.035)
			beam(k, "rust", pot + Vector3(0, 0.72, 0), pot + Vector3(0, 0.6, 0), 0.035)
			beam(k, "rust", pot + Vector3(0.1, 0.3, 0), Vector3(0.38, 0.62, 0.15), 0.03)
			# The engine: block, head with fins, crank case, flywheel and the dynamo.
			var eng := Vector3(0.42, 0.18, -0.05)
			k.box("painted", I.translated(eng + Vector3(0, 0.22, 0)), Vector3(0.36, 0.44, 0.42), ENGINE_GREEN)
			k.box("painted", I.translated(eng + Vector3(0, 0.62, 0)), Vector3(0.24, 0.36, 0.26), ENGINE_GREEN.darkened(0.1))
			for f in 5:
				k.box("cast_iron", I.translated(eng + Vector3(0, 0.84 + f * 0.035, 0)), Vector3(0.3, 0.012, 0.32), GASIFIER)
			var fly := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), eng + Vector3(0.2, 0.3, 0))
			k.cylinder("cast_iron", fly, 0.26, 0.26, 0.08, 18, true, 0.0, 1, GASIFIER.darkened(0.1))
			k.cylinder("cast_iron", fly.translated_local(Vector3(0, 0.08, 0)), 0.05, 0.05, 0.08, 8)
			var dyn := eng + Vector3(-0.02, 0.26, -0.36)
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), dyn), 0.13, 0.13, 0.3, 14, true, 0.0, 1, Color(0.2, 0.2, 0.22))
			for x in [-0.05, 0.05]:
				k.cylinder("gold", I.translated(dyn + Vector3(x, 0.12, -0.12)), 0.018, 0.018, 0.04, 6, true, 0.0, 1, BRASS)
			# Exhaust stack up the back corner.
			beam(k, "rust", eng + Vector3(0.1, 0.7, 0.18), eng + Vector3(0.1, 1.45, 0.3), 0.04)
			k.cylinder("rust", I.translated(eng + Vector3(0.1, 1.45, 0.3)), 0.055, 0.06, 0.08, 10)
			# A pressure gauge on the drum, needle and tick marks only.
			var g := drum + Vector3(0.18, 0.95, -0.3)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), g), 0.06, 0.06, 0.03, 12, true, 0.0, 1, BRASS)
			k.box("painted", I.translated(g + Vector3(0, 0, -0.032)), Vector3(0.085, 0.085, 0.004), ENAMEL)
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), 0.6), g + Vector3(0, 0, -0.036)), Vector3(0.006, 0.05, 0.004), Color(0.1, 0.1, 0.1))
		"pw_diesel":
			# A green-painted engine set on a steel skid: radiator grille at the front, the
			# generator end at the back, an exhaust and silencer on top, a fuel tank under.
			k.box("cast_iron", I.translated(Vector3(0, 0.05, 0)), Vector3(0.9, 0.1, 1.8), GASIFIER.darkened(0.2))
			k.box("painted", I.translated(Vector3(0, 0.22, 0.1)), Vector3(0.8, 0.24, 1.3), Color(0.32, 0.31, 0.29))
			k.box("painted", I.translated(Vector3(0, 0.62, -0.25)), Vector3(0.62, 0.58, 0.9), ENGINE_GREEN)
			k.box("painted", I.translated(Vector3(0, 0.95, -0.25)), Vector3(0.5, 0.1, 0.8), ENGINE_GREEN.darkened(0.1))
			# Radiator.
			k.box("painted", I.translated(Vector3(0, 0.66, -0.78)), Vector3(0.7, 0.72, 0.14), ENGINE_GREEN.darkened(0.15))
			for n in 9:
				k.box("cast_iron", I.translated(Vector3(-0.28 + n * 0.07, 0.66, -0.855)), Vector3(0.02, 0.6, 0.02), GASIFIER)
			# Generator drum and its terminal box.
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.62, 0.25)), 0.3, 0.3, 0.5, 18, true, 0.0, 1, ENGINE_GREEN.lightened(0.05))
			k.box("painted", I.translated(Vector3(0.3, 0.75, 0.5)), Vector3(0.18, 0.22, 0.16), Color(0.2, 0.2, 0.22))
			# Exhaust and silencer.
			k.cylinder("rust", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.18, 1.12, -0.5)), 0.08, 0.08, 0.55, 12)
			beam(k, "rust", Vector3(0.18, 1.0, -0.4), Vector3(0.18, 1.12, -0.4), 0.035)
			beam(k, "rust", Vector3(0.18, 1.12, 0.05), Vector3(0.18, 1.5, 0.12), 0.04)
			# Filler cap and lifting eyes.
			k.cylinder("cast_iron", I.translated(Vector3(-0.3, 0.34, 0.55)), 0.05, 0.05, 0.05, 10)
			for z in [-0.6, 0.6]:
				beam(k, "cast_iron", Vector3(-0.42, 0.1, z), Vector3(-0.42, 0.22, z), 0.02)
		"pw_windmill":
			# A four-legged timber lattice tower with cross-braces and a platform on top.
			var top := 7.8
			var base_r := 1.1
			var top_r := 0.38
			var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
			for c in corners:
				timber(k, Vector3(c.x * base_r, 0.0, c.y * base_r), Vector3(c.x * top_r, top, c.y * top_r), 0.13)
				k.box("cobble", I.translated(Vector3(c.x * base_r, 0.08, c.y * base_r)), Vector3(0.36, 0.16, 0.36))
			for lv in 4:
				var y0 := 0.4 + lv * 1.85
				var y1 := y0 + 1.85
				var r0 := lerpf(base_r, top_r, y0 / top)
				var r1 := lerpf(base_r, top_r, minf(y1, top) / top)
				for s in 4:
					var a: Vector2 = corners[s]
					var b: Vector2 = corners[(s + 1) % 4]
					timber(k, Vector3(a.x * r0, y0, a.y * r0), Vector3(b.x * r0, y0, b.y * r0), 0.08)
					# One diagonal per face, alternating, like a real tower.
					if (s + lv) % 2 == 0:
						timber(k, Vector3(a.x * r0, y0, a.y * r0), Vector3(b.x * r1, minf(y1, top), b.y * r1), 0.06)
					else:
						timber(k, Vector3(b.x * r0, y0, b.y * r0), Vector3(a.x * r1, minf(y1, top), a.y * r1), 0.06)
			k.box("planks", I.translated(Vector3(0, top + 0.04, 0)), Vector3(0.95, 0.08, 0.95))
			# Ladder up one face.
			for x in [-0.16, 0.16]:
				timber(k, Vector3(x, 0.0, -base_r - 0.05), Vector3(x, top, -top_r - 0.05), 0.045)
			for n in 22:
				var t := (n + 0.5) / 22.0
				var z := lerpf(-base_r - 0.05, -top_r - 0.05, t)
				timber(k, Vector3(-0.16, t * top, z), Vector3(0.16, t * top, z), 0.03)
			# The dynamo's cable down the tower to a terminal box at the foot.
			beam(k, "rubber", Vector3(top_r * 0.9, top, top_r * 0.9), Vector3(base_r * 0.92, 1.2, base_r * 0.92), 0.015)
			k.box("painted", I.translated(Vector3(base_r * 0.92, 1.1, base_r * 0.92)), Vector3(0.22, 0.26, 0.14), Color(0.2, 0.2, 0.22))
		"pw_solar":
			# A panel of cells in an aluminium frame, tipped 35 degrees on a galvanised
			# stand, its face toward its local +z; a junction box on the back.
			var tilt := deg_to_rad(35.0)
			var pb := Basis(Vector3(1, 0, 0), tilt)
			var c := Vector3(0, 1.05, 0)
			for x in [-0.8, 0.8]:
				beam(k, "metal", Vector3(x, 0, -0.45), Vector3(x, 1.25, -0.25), 0.03)
				beam(k, "metal", Vector3(x, 0, 0.35), Vector3(x, 0.78, 0.2), 0.03)
				k.box("cobble", I.translated(Vector3(x, 0.05, -0.45)), Vector3(0.22, 0.1, 0.22))
				k.box("cobble", I.translated(Vector3(x, 0.05, 0.35)), Vector3(0.22, 0.1, 0.22))
			# A white backsheet behind the cells, in a raised aluminium frame; two rails
			# across the back carry it on the stand.
			k.box("painted", Transform3D(pb, c), Vector3(1.96, 0.03, 1.06), Color(0.84, 0.85, 0.86))
			for z in [-0.545, 0.545]:
				k.box("metal", Transform3D(pb, c + pb * Vector3(0, 0.0, z)), Vector3(2.04, 0.07, 0.035))
			for x in [-1.005, 1.005]:
				k.box("metal", Transform3D(pb, c + pb * Vector3(x, 0.0, 0)), Vector3(0.035, 0.07, 1.12))
			for x in [-0.8, 0.8]:
				k.box("metal", Transform3D(pb, c + pb * Vector3(x, -0.04, 0)), Vector3(0.05, 0.04, 1.06))
			# 6 x 3 dark blue cells with thin gaps, each crossed by two silver busbars.
			for i in 6:
				for j in 3:
					var p := c + pb * Vector3(-0.83 + i * 0.332, 0.021, -0.36 + j * 0.36)
					k.box("solar_cell", Transform3D(pb, p), Vector3(0.32, 0.012, 0.345))
					for bx in [-0.08, 0.08]:
						k.box("metal", Transform3D(pb, p + pb * Vector3(bx, 0.0065, 0)), Vector3(0.006, 0.002, 0.345))
			k.box("painted", Transform3D(pb, c + pb * Vector3(0.0, -0.06, 0.0)), Vector3(0.2, 0.06, 0.14), Color(0.2, 0.2, 0.22))
		"pw_battery":
			# An oak rack holding two shelves of glass-jar lead cells, joined in series by
			# copper straps, with brass terminal posts on top.
			for x in [-0.6, 0.6]:
				for z in [-0.24, 0.24]:
					k.box("planks", I.translated(Vector3(x, 0.5, z)), Vector3(0.07, 1.0, 0.07))
			for y in [0.06, 0.52, 0.98]:
				k.box("planks", I.translated(Vector3(0, y, 0)), Vector3(1.28, 0.05, 0.55))
			for shelf in 2:
				var y := 0.085 + shelf * 0.46
				for n in 5:
					var x := -0.48 + n * 0.24
					var j := Vector3(x, y, 0)
					k.box("bottle_glass", I.translated(j + Vector3(0, 0.17, 0)), Vector3(0.2, 0.34, 0.3))
					# Lead plates inside the jar, grey and dark.
					for pz in [-0.08, 0.0, 0.08]:
						k.box("metal_dark", I.translated(j + Vector3(0, 0.15, pz)), Vector3(0.16, 0.26, 0.012))
					k.box("planks", I.translated(j + Vector3(0, 0.35, 0)), Vector3(0.2, 0.025, 0.3))
					for pz in [-0.08, 0.08]:
						k.cylinder("gold", I.translated(j + Vector3(0, 0.36, pz)), 0.015, 0.015, 0.05, 6, true, 0.0, 1, BRASS)
					if n < 4:
						k.box("painted", I.translated(j + Vector3(0.12, 0.405, 0.08)), Vector3(0.24, 0.008, 0.03), COPPER)
			k.box("painted", I.translated(Vector3(0.5, 1.06, 0)), Vector3(0.18, 0.12, 0.12), Color(0.2, 0.2, 0.22))
		"pw_pole":
			# A creosoted pole set in a stone collar, a crossarm and four glass-white
			# insulators, braced.
			k.cylinder("planks", I, 0.12, 0.09, 6.0, 10, true, 0.0, 1, Color(0.62, 0.52, 0.42))
			k.cylinder("cobble", I, 0.3, 0.26, 0.18, 10)
			k.box("timber", I.translated(Vector3(0, 5.7, 0)), Vector3(1.5, 0.1, 0.1))
			for x in [-0.32, 0.32]:
				timber(k, Vector3(x * 2.0, 5.65, 0), Vector3(0, 5.25, 0.0), 0.04)
			for x in [-0.66, -0.22, 0.22, 0.66]:
				insulator(k, Vector3(x, 5.75, 0))
			for n in 8:
				# Climbing steps up one side.
				var y := 1.4 + n * 0.45
				var a := PI * 0.5 * (n % 2)
				beam(k, "cast_iron", Vector3(0, y, 0), Vector3(sin(a) * 0.3, y, cos(a) * 0.3 * (1 if n % 4 < 2 else -1)), 0.012)
		"pw_junction":
			# A painted steel box on the wall with a screwed lid and four cable glands below.
			k.box("painted", I.translated(Vector3(0, 0, 0.06)), Vector3(0.3, 0.36, 0.12), STEEL_GREY)
			k.box("painted", I.translated(Vector3(0, 0, 0.125)), Vector3(0.26, 0.32, 0.015), STEEL_GREY.lightened(0.1))
			for c in [Vector2(-0.11, -0.14), Vector2(0.11, -0.14), Vector2(-0.11, 0.14), Vector2(0.11, 0.14)]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(c.x, c.y, 0.13)), 0.012, 0.012, 0.01, 6)
			for x in [-0.09, -0.03, 0.03, 0.09]:
				k.cylinder("gold", I.translated(Vector3(x, -0.22, 0.06)), 0.02, 0.022, 0.05, 8, true, 0.0, 1, BRASS)
		"pw_switch":
			# A slate panel with two copper jaws and the hinge post; the blade is a part.
			k.box("slate_board", I.translated(Vector3(0, 0, 0.02)), Vector3(0.22, 0.36, 0.04))
			for y in [-0.14, 0.14]:
				for x in [-0.08, 0.08]:
					k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(x, y, 0.04)), 0.01, 0.01, 0.008, 6)
			for x in [-0.04, 0.04]:
				k.box("painted", I.translated(Vector3(x, 0.1, 0.07)), Vector3(0.012, 0.06, 0.06), COPPER)
				k.box("painted", I.translated(Vector3(x, -0.1, 0.07)), Vector3(0.012, 0.05, 0.06), COPPER)
		"pw_lever":
			# A cast-iron backplate with a pivot boss; the arm is a part (PowerNode swings it).
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.015)), Vector3(0.14, 0.34, 0.03), GASIFIER)
			rivets(k, Vector3(-0.05, 0.15, 0.032), Vector3(0.05, 0.15, 0.032), 2, Vector3(0, 0, 1))
			rivets(k, Vector3(-0.05, -0.15, 0.032), Vector3(0.05, -0.15, 0.032), 2, Vector3(0, 0, 1))
			# A quadrant guide the arm runs in.
			for x in [-0.035, 0.035]:
				k.box("cast_iron", I.translated(Vector3(x, 0.02, 0.05)), Vector3(0.012, 0.22, 0.04), GASIFIER.darkened(0.15))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.02, 0.06)), 0.022, 0.022, 0.1, 10, true, 0.0, 1, GASIFIER)
			_box_terminal(k, Vector3(0, -0.16, 0.03))
		"pw_button":
			# A round cast housing with a brass bezel; the cap is a part, pushed in.
			_wall_plate(k, Vector2(0.16, 0.26))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0)), 0.06, 0.055, 0.045, 16, true, 0.0, 1, GASIFIER)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.045)), 0.04, 0.038, 0.012, 16, true, 0.0, 1, BRASS)
			_box_terminal(k, Vector3(0, -0.08, 0.03))
		"pw_plate":
			# A riveted iron frame flush on the ground; the chequer-plate top is a part.
			for side in [-1.0, 1.0]:
				k.box("cast_iron", I.translated(Vector3(side * 0.43, 0.025, 0)), Vector3(0.06, 0.05, 0.92), GASIFIER.darkened(0.1))
				k.box("cast_iron", I.translated(Vector3(0, 0.025, side * 0.43)), Vector3(0.8, 0.05, 0.06), GASIFIER.darkened(0.1))
			for c in [Vector3(-0.43, 0.052, -0.43), Vector3(0.43, 0.052, -0.43), Vector3(-0.43, 0.052, 0.43), Vector3(0.43, 0.052, 0.43)]:
				k.sphere("cast_iron", I.translated(c), 0.016, 3, 6, 0.0, 0.6, Color.WHITE, true)
			k.box("cast_iron", I.translated(Vector3(0, 0.03, -0.47)), Vector3(0.06, 0.04, 0.03), GASIFIER)
		"pw_motion":
			# A little enamelled hood with a dark lens that looks out ahead and down.
			_wall_plate(k, Vector2(0.16, 0.26))
			k.box("painted", I.translated(Vector3(0, 0, 0.035)), Vector3(0.12, 0.14, 0.07), ENAMEL)
			k.box("painted", Transform3D(Basis(Vector3(1, 0, 0), 0.35), Vector3(0, 0.07, 0.07)), Vector3(0.14, 0.012, 0.09), ENAMEL.darkened(0.08))
			k.sphere("glass", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.005, 0.07)), 0.04, 6, 12, 0.0, 1.0, Color(0.12, 0.1, 0.1), true)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.005, 0.068)), 0.046, 0.046, 0.008, 14, true, 0.0, 1, BRASS)
			_box_terminal(k, Vector3(0, -0.08, 0.03))
		"pw_daylight":
			# A selenium cell under a glass dome, on a small box.
			_wall_plate(k, Vector2(0.16, 0.26))
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.04)), Vector3(0.12, 0.12, 0.08), GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.06, 0.045)), 0.045, 0.045, 0.012, 12, true, 0.0, 1, GASIFIER.darkened(0.1))
			k.cylinder("painted", I.translated(Vector3(0, 0.072, 0.045)), 0.034, 0.034, 0.004, 12, true, 0.0, 1, Color(0.36, 0.16, 0.12))
			k.sphere("clear_glass", I.translated(Vector3(0, 0.072, 0.045)), 0.042, 6, 12, 0.0, 1.0, Color.WHITE, true)
			_box_terminal(k, Vector3(0, -0.08, 0.03))
		"pw_timer":
			_logic_box(k, Color(0.24, 0.32, 0.26))
			# A dial with a pointer and a ring of pins.
			_dial(k, Vector3(0, 0.03, 0.082), 0.075, 12, 0.9)
		"pw_clock":
			# A round brass-cased time switch: a clock face with two hands.
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0)), 0.15, 0.15, 0.07, 24, true, 0.0, 1, BRASS)
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.07)), 0.13, 0.13, 0.004, 24, true, 0.0, 1, ENAMEL)
			for n in 12:
				var a := TAU * n / 12.0
				var tl := 0.022 if n % 3 == 0 else 0.012
				k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -a), Vector3(sin(a), cos(a), 0) * (0.112 - tl * 0.5) + Vector3(0, 0, 0.075)), Vector3(0.006, tl, 0.003), Color(0.1, 0.1, 0.1))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -2.1), Vector3(sin(2.1), cos(2.1), 0) * 0.035 + Vector3(0, 0, 0.078)), Vector3(0.008, 0.07, 0.003), Color(0.08, 0.08, 0.08))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -5.3), Vector3(sin(5.3), cos(5.3), 0) * 0.05 + Vector3(0, 0, 0.08)), Vector3(0.005, 0.1, 0.003), Color(0.08, 0.08, 0.08))
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.074)), 0.009, 0.009, 0.01, 8, true, 0.0, 1, BRASS)
			_box_terminal(k, Vector3(0, -0.17, 0.04))
		"pw_gate":
			# An open steel case with a glass front: the relay coils inside, four input
			# terminals across the top.
			_case(k, "painted", Vector3(0.22, 0.3, 0.08), Color(0.27, 0.31, 0.38))
			k.box("clear_glass", I.translated(Vector3(0, 0, 0.078)), Vector3(0.2, 0.28, 0.004))
			_box_terminal(k, Vector3(0, -0.15, 0.04))
			for x in [-0.045, 0.0, 0.045]:
				k.cylinder("painted", I.translated(Vector3(x, -0.02, 0.05)), 0.016, 0.016, 0.08, 10, true, 0.0, 1, COPPER)
			for x in [-0.075, -0.025, 0.025, 0.075]:
				k.cylinder("gold", I.translated(Vector3(x, 0.15, 0.05)), 0.01, 0.012, 0.03, 8, true, 0.0, 1, BRASS)
		"pw_latch":
			_logic_box(k, Color(0.4, 0.2, 0.15))
			# A drop flag in a window shows it set; a reset knob below.
			k.box("painted", I.translated(Vector3(0, 0.04, 0.082)), Vector3(0.1, 0.07, 0.004), ENAMEL)
			k.box("painted", I.translated(Vector3(0, 0.04, 0.086)), Vector3(0.06, 0.03, 0.004), Color(0.1, 0.1, 0.1))
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.06, 0.08)), 0.02, 0.018, 0.025, 12, true, 0.0, 1, Color(0.1, 0.1, 0.1))
		"pw_counter":
			_logic_box(k, Color(0.15, 0.15, 0.16))
			# Three number wheels behind a slot (blank faces: no writing).
			k.box("painted", I.translated(Vector3(0, 0.03, 0.082)), Vector3(0.15, 0.06, 0.004), Color(0.05, 0.05, 0.05))
			for x in [-0.045, 0.0, 0.045]:
				k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x, 0.03, 0.07)), 0.03, 0.03, 0.035, 14, true, 0.0, 1, ENAMEL)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.05, -0.06, 0.08)), 0.014, 0.014, 0.02, 10, true, 0.0, 1, BRASS)
		"pw_delay":
			_logic_box(k, Color(0.2, 0.26, 0.2))
			# A brass dashpot (an oil damper that slows the contact) on the front.
			k.cylinder("gold", I.translated(Vector3(0, -0.07, 0.11)), 0.03, 0.03, 0.14, 14, true, 0.0, 1, BRASS)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.07, 0.11)), 0.006, 0.006, 0.05, 6)
			k.box("cast_iron", I.translated(Vector3(0, -0.075, 0.09)), Vector3(0.08, 0.02, 0.04), GASIFIER)
			_dial(k, Vector3(0, 0.1, 0.082), 0.03, 6, 2.2)
		"pw_relay":
			# An iron box with a glass front: the coil and the contact arm inside.
			_case(k, "cast_iron", Vector3(0.22, 0.34, 0.11), GASIFIER)
			k.box("clear_glass", I.translated(Vector3(0, 0, 0.108)), Vector3(0.2, 0.32, 0.004))
			k.cylinder("painted", I.translated(Vector3(-0.04, -0.05, 0.06)), 0.035, 0.035, 0.12, 14, true, 0.0, 1, COPPER)
			k.box("cast_iron", I.translated(Vector3(0.03, 0.09, 0.06)), Vector3(0.1, 0.012, 0.03), GASIFIER.darkened(0.2))
			k.box("painted", I.translated(Vector3(0.06, 0.0, 0.06)), Vector3(0.012, 0.1, 0.02), COPPER)
			for x in [-0.05, 0.05]:
				k.cylinder("gold", I.translated(Vector3(x, -0.2, 0.06)), 0.018, 0.02, 0.05, 8, true, 0.0, 1, BRASS)
			_box_terminal(k, Vector3(0, 0.19, 0.06))
		"pw_charge":
			# A meter on a small iron box: an enamel scale and a needle.
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.04)), Vector3(0.18, 0.2, 0.08), GASIFIER)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.08)), 0.065, 0.065, 0.012, 18, true, 0.0, 1, BRASS)
			_dial(k, Vector3(0, 0.02, 0.093), 0.055, 7, 0.4)
			for x in [-0.0, 0.07]:
				k.cylinder("gold", I.translated(Vector3(x, -0.13, 0.05)), 0.014, 0.016, 0.04, 8, true, 0.0, 1, BRASS)
		"pw_door_motor":
			# A geared motor on a wall plate: the motor drum, a reduction box and the chain
			# sprocket that winds the door.
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.012)), Vector3(0.42, 0.34, 0.024), GASIFIER.darkened(0.1))
			rivets(k, Vector3(-0.18, 0.15, 0.026), Vector3(0.18, 0.15, 0.026), 4, Vector3(0, 0, 1))
			rivets(k, Vector3(-0.18, -0.15, 0.026), Vector3(0.18, -0.15, 0.026), 4, Vector3(0, 0, 1))
			k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.06, 0.02, 0.1)), 0.075, 0.075, 0.22, 16, true, 0.0, 1, ENGINE_GREEN)
			for n in 6:
				k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.15 + n * 0.035, 0.02, 0.1)), Vector3(0.16, 0.006, 0.16), ENGINE_GREEN.darkened(0.15))
			k.box("cast_iron", I.translated(Vector3(0.12, 0.02, 0.09)), Vector3(0.12, 0.18, 0.13), GASIFIER)
			var sp := Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.12, 0.02, 0.16))
			k.cylinder("cast_iron", sp, 0.06, 0.06, 0.02, 14, true, 0.0, 1, GASIFIER.darkened(0.25))
			k.cylinder("cast_iron", sp.translated_local(Vector3(0, 0.02, 0)), 0.015, 0.015, 0.03, 8)
			for x in [-0.12, 0.12]:
				k.cylinder("gold", I.translated(Vector3(x, -0.18, 0.08)), 0.016, 0.018, 0.04, 8, true, 0.0, 1, BRASS)
		"pw_turret":
			# A pedestal on a riveted cross base, the drive motor and a junction box on it;
			# the head (yoke) and the gun are parts PowerNode turns.
			for a in 4:
				var b := Basis(Vector3.UP, TAU * a / 4.0 + PI * 0.25)
				k.box("cast_iron", Transform3D(b, b * Vector3(0, 0.05, 0.32)), Vector3(0.14, 0.1, 0.62), GASIFIER.darkened(0.1))
				rivets(k, b * Vector3(0, 0.1, 0.5), b * Vector3(0, 0.1, 0.5), 1, Vector3.UP, 0.025)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.08, 0)), 0.2, 0.16, 0.12, 16, true, 0.0, 1, GASIFIER)
			k.cylinder("painted", I.translated(Vector3(0, 0.2, 0)), 0.11, 0.09, 0.82, 14, true, 0.0, 1, ENGINE_GREEN)
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.0, 0)), 0.16, 0.16, 0.08, 18, true, 0.0, 1, GASIFIER)
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.55, 0.12)), 0.08, 0.08, 0.2, 14, true, 0.0, 1, ENGINE_GREEN.darkened(0.15))
			k.box("cast_iron", I.translated(Vector3(0, 0.3, 0.2)), Vector3(0.18, 0.2, 0.1), GASIFIER)
			for x in [-0.05, 0.05]:
				k.cylinder("gold", I.translated(Vector3(x, 0.4, 0.22)), 0.014, 0.016, 0.04, 8, true, 0.0, 1, BRASS)
		"pw_heavy_turret":
			# A squat armoured drum on a concrete-and-iron plinth.
			k.box("cobble", I.translated(Vector3(0, 0.12, 0)), Vector3(1.2, 0.24, 1.2))
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.24, 0)), 0.5, 0.44, 0.7, 20, true, 0.0, 1, ENGINE_GREEN.darkened(0.25))
			for y in [0.36, 0.82]:
				k.cylinder("cast_iron", I.translated(Vector3(0, y, 0)), 0.515, 0.515, 0.04, 20, true, 0.0, 1, GASIFIER)
			for a in 10:
				var p := Basis(Vector3.UP, TAU * a / 10.0) * Vector3(0, 0.6, 0.5)
				k.sphere("cast_iron", I.translated(p), 0.02, 3, 6, 0.0, 0.6)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.94, 0)), 0.36, 0.36, 0.34, 18, true, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.4, 0.5)), Vector3(0.24, 0.24, 0.12), GASIFIER)
		"pw_fence_post":
			# A tarred timber post with three ceramic insulators up its face.
			k.cylinder("bark", I, 0.07, 0.06, 1.65, 8, true, 0.02, 3, Color(0.45, 0.38, 0.3))
			for y in [0.6, 1.05, 1.5]:
				var at := Vector3(0, y, 0)
				k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.05)), 0.008, 0.008, 0.07, 6)
				k.cylinder("bone", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.1)), 0.034, 0.026, 0.05, 10, true, 0.0, 1, CERAMIC)
			# A yellow warning plate (paint, no writing).
			k.box("painted", I.translated(Vector3(0, 0.9, -0.075)), Vector3(0.16, 0.12, 0.008), Color(0.78, 0.62, 0.12))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(0, 0.9, -0.08)), Vector3(0.02, 0.09, 0.004), Color(0.08, 0.08, 0.08))
		"pw_spike_trap":
			# A sunken iron box with a grate top; the spikes are a part that punches up.
			for side in [-1.0, 1.0]:
				k.box("cast_iron", I.translated(Vector3(side * 0.53, 0.04, 0)), Vector3(0.06, 0.08, 1.12), GASIFIER.darkened(0.15))
				k.box("cast_iron", I.translated(Vector3(0, 0.04, side * 0.53)), Vector3(1.0, 0.08, 0.06), GASIFIER.darkened(0.15))
			for n in 6:
				k.box("cast_iron", I.translated(Vector3(-0.42 + n * 0.168, 0.07, 0)), Vector3(0.02, 0.02, 1.0), GASIFIER.darkened(0.3))
			k.box("rust", I.translated(Vector3(0, -0.02, 0)), Vector3(1.0, 0.03, 1.0))
		"pw_flame_trap":
			# A fuel tank on legs with a pump and the nozzle facing out front (-z).
			k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.25, 0.3, 0.1)), 0.18, 0.18, 0.5, 16, true, 0.0, 1, Color(0.55, 0.12, 0.08))
			for x in [-0.4, 0.15]:
				for z in [-0.05, 0.25]:
					beam(k, "cast_iron", Vector3(x, 0.0, z), Vector3(x, 0.16, z), 0.02)
			k.box("cast_iron", I.translated(Vector3(0.18, 0.3, 0.1)), Vector3(0.16, 0.22, 0.2), GASIFIER)
			beam(k, "rust", Vector3(0.18, 0.4, 0.0), Vector3(0, 0.55, -0.15), 0.025)
			beam(k, "gold", Vector3(0, 0.55, -0.15), Vector3(0, 0.55, -0.4), 0.03, 10, BRASS)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.55, -0.4)), 0.04, 0.03, 0.06, 10, true, 0.0, 1, BRASS)
			beam(k, "cast_iron", Vector3(0, 0.0, -0.3), Vector3(0, 0.53, -0.3), 0.02)
		"pw_alarm_bell":
			# A red gong on an iron bracket off the wall, with its striker coil box below.
			k.box("cast_iron", I.translated(Vector3(0, -0.18, 0.04)), Vector3(0.14, 0.12, 0.08), GASIFIER)
			beam(k, "cast_iron", Vector3(0, 0.02, 0.0), Vector3(0, 0.02, 0.14), 0.015)
			k.sphere("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.06)), 0.13, 6, 18, 0.0, 0.6, Color(0.62, 0.1, 0.08), true)
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.01)), 0.06, 0.06, 0.02, 12, true, 0.0, 1, GASIFIER)
		"pw_searchlight":
			# A tripod of steel legs and a turntable; the yoke and the drum are parts.
			for a in 3:
				var b := Basis(Vector3.UP, TAU * a / 3.0)
				beam(k, "cast_iron", b * Vector3(0, 0, 0.65), Vector3(0, 1.15, 0), 0.03, 6, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.15, 0)), 0.16, 0.16, 0.12, 16, true, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.45, 0.15)), Vector3(0.2, 0.22, 0.14), GASIFIER)
		"pw_belt":
			# A 1 m conveyor: a steel frame on four legs, rollers and a rubber belt running
			# along +z, with the drive motor at the side.
			for x in [-0.32, 0.32]:
				k.box("cast_iron", I.translated(Vector3(x, 0.17, 0)), Vector3(0.04, 0.08, 1.0), GASIFIER.darkened(0.1))
				for z in [-0.42, 0.42]:
					beam(k, "cast_iron", Vector3(x, 0.0, z), Vector3(x, 0.15, z), 0.02)
			for n in 5:
				k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.17, -0.4 + n * 0.2)), 0.03, 0.03, 0.6, 8, true, 0.0, 1, GASIFIER.lightened(0.05))
			k.box("rubber", I.translated(Vector3(0, 0.205, 0)), Vector3(0.58, 0.012, 1.0))
			k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.4, 0.14, 0.0)), 0.05, 0.05, 0.12, 10, true, 0.0, 1, ENGINE_GREEN)
		"pw_hopper":
			# A riveted steel funnel on four legs, its spout out the +z side.
			for x in [-0.36, 0.36]:
				for z in [-0.36, 0.36]:
					beam(k, "cast_iron", Vector3(x, 0, z), Vector3(x * 0.9, 0.55, z * 0.9), 0.025)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.45, 0)), 0.18, 0.46, 0.5, 4, false, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.4, 0.32)), Vector3(0.18, 0.12, 0.3), GASIFIER.darkened(0.1))
			rivets(k, Vector3(-0.3, 0.92, -0.3), Vector3(0.3, 0.92, -0.3), 4, Vector3(0, 0.3, -1))
		"pw_robot_arm":
			# A turntable base with its motor; the arm is a part that swings round.
			k.cylinder("cast_iron", I, 0.24, 0.26, 0.12, 18, true, 0.0, 1, GASIFIER.darkened(0.1))
			k.cylinder("painted", I.translated(Vector3(0, 0.12, 0)), 0.16, 0.16, 0.36, 16, true, 0.0, 1, Color(0.78, 0.55, 0.12))
			k.box("cast_iron", I.translated(Vector3(0, 0.15, -0.22)), Vector3(0.14, 0.14, 0.1), GASIFIER)
		"pw_auto_miner":
			# A skid-mounted drill rig: engine house with the motor, a gearbox and a boom
			# that holds the drill out front (-z) at the rock. The bit is a part that turns.
			k.box("planks", I.translated(Vector3(0, 0.06, 0)), Vector3(1.1, 0.12, 1.4))
			k.box("painted", I.translated(Vector3(0, 0.55, 0.25)), Vector3(0.9, 0.85, 0.8), Color(0.62, 0.5, 0.14))
			k.box("painted", I.translated(Vector3(0, 1.0, 0.25)), Vector3(0.96, 0.06, 0.86), Color(0.52, 0.42, 0.12))
			for n in 6:
				k.box("cast_iron", I.translated(Vector3(-0.47, 0.5, 0.0 + n * 0.1)), Vector3(0.02, 0.4, 0.05), GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.95, -0.3)), Vector3(0.36, 0.36, 0.4), GASIFIER)
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.95, -0.5)), 0.08, 0.08, 0.2, 12, true, 0.0, 1, GASIFIER.darkened(0.2))
			beam(k, "cast_iron", Vector3(-0.3, 0.12, -0.5), Vector3(-0.15, 0.9, -0.5), 0.03)
			beam(k, "cast_iron", Vector3(0.3, 0.12, -0.5), Vector3(0.15, 0.9, -0.5), 0.03)
			k.box("cast_iron", I.translated(Vector3(0, 0.3, 0.72)), Vector3(0.3, 0.22, 0.1), GASIFIER)
		"pw_quarry":
			# A derrick: four legs braced over the hole, a winch house, the drill shaft
			# down the middle (its bit is a part that turns).
			for x in [-0.8, 0.8]:
				for z in [-0.8, 0.8]:
					beam(k, "cast_iron", Vector3(x, 0, z), Vector3(x * 0.25, 2.6, z * 0.25), 0.045, 6, GASIFIER)
			for y in [0.8, 1.6]:
				var w: float = 0.8 - float(y) * 0.21
				for e in [[Vector3(-w, y, -w), Vector3(w, y, -w)], [Vector3(w, y, -w), Vector3(w, y, w)], [Vector3(w, y, w), Vector3(-w, y, w)], [Vector3(-w, y, w), Vector3(-w, y, -w)]]:
					beam(k, "cast_iron", e[0], e[1], 0.025, 6, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 2.65, 0)), Vector3(0.5, 0.12, 0.5), GASIFIER)
			beam(k, "cast_iron", Vector3(0, 0.3, 0), Vector3(0, 2.6, 0), 0.04, 8, GASIFIER.darkened(0.2))
			k.box("painted", I.translated(Vector3(0.7, 0.45, 0.0)), Vector3(0.5, 0.9, 0.6), ENGINE_GREEN)
			k.cylinder("cobble", I.translated(Vector3(0, -0.02, 0)), 0.55, 0.6, 0.06, 18)
		"pw_furnace":
			# A brick-lined steel box with a heavy door, a crucible chute on top and a
			# junction box; the heat is inside (nothing glows).
			k.box("painted", I.translated(Vector3(0, 0.65, 0)), Vector3(1.2, 1.3, 1.1), Color(0.3, 0.3, 0.32))
			k.box("cast_iron", I.translated(Vector3(0, 0.6, -0.56)), Vector3(0.6, 0.6, 0.06), GASIFIER.darkened(0.2))
			beam(k, "cast_iron", Vector3(-0.2, 0.6, -0.62), Vector3(0.2, 0.6, -0.62), 0.02)
			for y in [0.1, 1.2]:
				k.box("cast_iron", I.translated(Vector3(0, y, 0)), Vector3(1.24, 0.08, 1.14), GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(-0.3, 1.3, 0.2)), 0.12, 0.08, 0.5, 12, true, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0.3, 1.38, 0.0)), Vector3(0.3, 0.16, 0.5), GASIFIER.darkened(0.1))
			k.box("cast_iron", I.translated(Vector3(0, 0.4, 0.58)), Vector3(0.3, 0.12, 0.12), GASIFIER)
		"pw_sawmill":
			# A timber bench with a feed table; the big circular blade is a part.
			k.box("planks", I.translated(Vector3(0, 0.72, 0)), Vector3(0.9, 0.08, 1.8))
			for x in [-0.38, 0.38]:
				for z in [-0.8, 0.8]:
					timber(k, Vector3(x, 0, z), Vector3(x, 0.7, z), 0.09)
			k.box("painted", I.translated(Vector3(0.0, 0.35, 0.0)), Vector3(0.5, 0.45, 0.6), ENGINE_GREEN)
			k.box("cast_iron", I.translated(Vector3(0, 0.98, 0)), Vector3(0.06, 0.3, 0.7), GASIFIER.lightened(0.05))
		"pw_assembler":
			# A machine cabinet: its works (gear trains and a stamping head) on the front
			# behind glass, a feed hopper on top, the chute out the back (+z).
			k.box("painted", I.translated(Vector3(0, 0.75, 0)), Vector3(1.2, 1.5, 1.0), Color(0.36, 0.4, 0.46))
			k.box("painted", I.translated(Vector3(0, 0.75, -0.505)), Vector3(1.0, 1.1, 0.01), Color(0.18, 0.2, 0.22))
			for g in 3:
				k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(-0.3 + g * 0.3, 1.0, -0.53)), 0.11 - g * 0.02, 0.11 - g * 0.02, 0.03, 18, true, 0.0, 1, BRASS)
			k.box("cast_iron", I.translated(Vector3(0, 0.55, -0.55)), Vector3(0.3, 0.3, 0.06), GASIFIER)
			beam(k, "cast_iron", Vector3(0, 0.75, -0.56), Vector3(0, 0.95, -0.56), 0.025)
			k.box("clear_glass", I.translated(Vector3(0, 0.75, -0.6)), Vector3(1.04, 1.14, 0.006))
			for x in [-0.52, 0.52]:
				k.box("painted", I.translated(Vector3(x, 0.75, -0.56)), Vector3(0.04, 1.18, 0.1), Color(0.3, 0.33, 0.38))
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.5, 0)), 0.12, 0.34, 0.4, 4, false, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.3, 0.56)), Vector3(0.3, 0.16, 0.12), GASIFIER)
		"pw_water_wheel":
			# An undershot wheel's frame: two timber A-frames and the axle bearing; the
			# wheel is a part that turns about x.
			for x in [-0.75, 0.75]:
				timber(k, Vector3(x, 0, -1.0), Vector3(x, 1.5, 0), 0.12)
				timber(k, Vector3(x, 0, 1.0), Vector3(x, 1.5, 0), 0.12)
				k.box("cast_iron", I.translated(Vector3(x, 1.42, 0)), Vector3(0.16, 0.14, 0.2), GASIFIER)
			k.box("painted", I.translated(Vector3(0.95, 1.5, 0.0)), Vector3(0.3, 0.4, 0.4), ENGINE_GREEN)
		"pw_steam":
			# A horizontal boiler with its firebox, a tall stack, the cylinder and the
			# flywheel (a part) driving a dynamo.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.75, -0.9)), 0.45, 0.45, 1.6, 20, true, 0.0, 1, GASIFIER)
			for z in [-0.75, -0.25, 0.25]:
				k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.75, z)), 0.47, 0.47, 0.04, 20, true, 0.0, 1, GASIFIER.darkened(0.2))
			k.box("cast_iron", I.translated(Vector3(0, 0.35, 0.78)), Vector3(0.9, 0.7, 0.5), GASIFIER.darkened(0.1))
			k.box("cast_iron", I.translated(Vector3(0, 0.3, 1.04)), Vector3(0.3, 0.26, 0.03), GASIFIER.darkened(0.3))
			k.cylinder("rust", I.translated(Vector3(-0.35, 1.0, 0.3)), 0.11, 0.1, 1.6, 12)
			k.box("painted", I.translated(Vector3(0.45, 0.6, -0.2)), Vector3(0.18, 0.3, 0.6), ENGINE_GREEN)
			k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.62, 0.75, 0.45)), 0.18, 0.18, 0.3, 14, true, 0.0, 1, Color(0.2, 0.2, 0.22))
			for x in [-0.4, 0.4]:
				k.box("planks", I.translated(Vector3(x, 0.05, 0)), Vector3(0.14, 0.1, 2.0))
		"pw_lamp_ceiling":
			# A ceiling rose, a cloth flex, and a white enamel shade; the bulb is a part.
			k.cylinder("painted", I.translated(Vector3(0, -0.03, 0)), 0.06, 0.06, 0.03, 12, true, 0.0, 1, ENAMEL)
			k.cylinder("rubber", I.translated(Vector3(0, -0.2, 0)), 0.006, 0.006, 0.18, 5)
			k.cylinder("gold", I.translated(Vector3(0, -0.28, 0)), 0.022, 0.026, 0.08, 10, true, 0.0, 1, BRASS)
			k.cylinder("painted", I.translated(Vector3(0, -0.4, 0)), 0.2, 0.05, 0.13, 20, false, 0.0, 2, ENAMEL)
			# Its white inside, facing in: it bounces the bulb's light down, and casts the
			# shadow that keeps the ceiling above in the shade's shadow.
			for n in 20:
				var a0 := TAU * n / 20.0
				var a1 := TAU * (n + 1) / 20.0
				var q := [Vector3(cos(a0) * 0.192, -0.398, sin(a0) * 0.192), Vector3(cos(a1) * 0.192, -0.398, sin(a1) * 0.192),
					Vector3(cos(a1) * 0.024, -0.262, sin(a1) * 0.024), Vector3(cos(a0) * 0.024, -0.262, sin(a0) * 0.024)]
				var mid: Vector3 = (q[0] + q[2]) * 0.5
				if ((q[1] - q[0]) as Vector3).cross(q[2] - q[0]).dot(Vector3(mid.x, 0, mid.z)) > 0.0:
					q.reverse()
				k.quad("painted", I, q[0], q[1], q[2], q[3], Color(0.95, 0.94, 0.9))
			k.cylinder("painted", I.translated(Vector3(0, -0.405, 0)), 0.205, 0.205, 0.008, 20, false, 0.0, 1, Color(0.18, 0.2, 0.22))
		"pw_lamp_wall":
			# A cast bracket holding a bulkhead lamp: a ribbed glass globe in an iron cage.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0)), 0.07, 0.07, 0.03, 12, true, 0.0, 1, GASIFIER)
			beam(k, "cast_iron", Vector3(0, 0, 0.02), Vector3(0, 0.02, 0.18), 0.016, 6, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, -0.02, 0.2)), 0.05, 0.05, 0.05, 10, true, 0.0, 1, GASIFIER)
			for n in 4:
				var a := TAU * n / 4.0 + PI * 0.25
				var p := Vector3(cos(a) * 0.075, 0.0, sin(a) * 0.075) + Vector3(0, 0, 0.2)
				beam(k, "cast_iron", p + Vector3(0, 0.03, 0), p + Vector3(0, 0.17, 0), 0.006, 4, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.18, 0.2)), 0.08, 0.04, 0.03, 10, true, 0.0, 1, GASIFIER)
		"pw_flood":
			# A folding tripod, a yoke and a deep square lamp head aimed down at the ground ahead.
			for n in 3:
				var a := TAU * n / 3.0
				beam(k, "cast_iron", Vector3(cos(a) * 0.5, 0, sin(a) * 0.5), Vector3(0, 1.3, 0), 0.02, 6, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.3, 0)), 0.03, 0.03, 0.25, 8, true, 0.0, 1, GASIFIER)
			beam(k, "cast_iron", Vector3(-0.28, 1.55, 0), Vector3(0.28, 1.55, 0), 0.018, 6, GASIFIER)
			for x in [-0.28, 0.28]:
				beam(k, "cast_iron", Vector3(x, 1.55, 0), Vector3(x, 1.72, 0), 0.018, 6, GASIFIER)
			var hb := Basis(Vector3(1, 0, 0), deg_to_rad(-28.0))
			var hc := Vector3(0, 1.72, 0)
			k.box("painted", Transform3D(hb, hc), Vector3(0.48, 0.4, 0.3), Color(0.42, 0.43, 0.4))
			k.box("painted", Transform3D(hb, hc + hb * Vector3(0, 0, -0.16)), Vector3(0.52, 0.44, 0.03), Color(0.36, 0.37, 0.35))
			for n in 4:
				k.box("cast_iron", Transform3D(hb, hc + hb * Vector3(0, 0.205, 0.14 - n * 0.07)), Vector3(0.44, 0.012, 0.012), GASIFIER)
		"pw_street":
			# A cast-iron post on a fluted base with a scrolled arm and a lantern head.
			k.cylinder("cast_iron", I, 0.18, 0.13, 0.5, 12, true, 0.0, 2, Color(0.75, 0.76, 0.78))
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.5, 0)), 0.07, 0.05, 3.1, 10, true, 0.0, 1, Color(0.75, 0.76, 0.78))
			for y in [0.55, 1.6, 3.5]:
				k.cylinder("cast_iron", I.translated(Vector3(0, y, 0)), 0.085, 0.085, 0.04, 10, true, 0.0, 1, Color(0.66, 0.67, 0.7))
			beam(k, "cast_iron", Vector3(0, 3.45, 0), Vector3(0, 3.45, -0.5), 0.025, 6, Color(0.75, 0.76, 0.78))
			beam(k, "cast_iron", Vector3(0, 3.1, 0), Vector3(0, 3.45, -0.35), 0.015, 6, Color(0.75, 0.76, 0.78))
			var lh := Vector3(0, 3.0, -0.5)
			k.cylinder("cast_iron", I.translated(lh + Vector3(0, 0.42, 0)), 0.03, 0.03, 0.05, 8, true, 0.0, 1, Color(0.75, 0.76, 0.78))
			k.cylinder("cast_iron", I.translated(lh + Vector3(0, 0.3, 0)), 0.2, 0.04, 0.12, 6, true, 0.0, 1, Color(0.75, 0.76, 0.78))
			for n in 6:
				var a := TAU * n / 6.0
				beam(k, "cast_iron", lh + Vector3(cos(a) * 0.15, 0.0, sin(a) * 0.15), lh + Vector3(cos(a) * 0.19, 0.3, sin(a) * 0.19), 0.008, 4, Color(0.75, 0.76, 0.78))
			k.cylinder("cast_iron", I.translated(lh + Vector3(0, -0.04, 0)), 0.12, 0.15, 0.04, 6, true, 0.0, 1, Color(0.75, 0.76, 0.78))

# --- Moving and lit parts ---------------------------------------------------------

## A part's mesh, cached. Main thread only (PowerNode makes them as pieces appear).
static func part(name: String) -> ArrayMesh:
	_lock.lock()
	var m = _parts.get(name)
	_lock.unlock()
	if m != null:
		return m
	var k := MeshKit.new(WHash.str_hash(name) & 0xFFFF)
	var I := Transform3D.IDENTITY
	match name:
		"windmill_head":
			# Turns on the tower top: a turntable, a timber nacelle with the dynamo inside
			# a hood, and a tail vane that keeps the sails into the wind (local +z).
			k.cylinder("cast_iron", I, 0.42, 0.42, 0.06, 16, true, 0.0, 1, GASIFIER)
			k.box("planks", I.translated(Vector3(0, 0.28, 0.05)), Vector3(0.42, 0.46, 1.25))
			k.box("planks", Transform3D(Basis(Vector3(0, 0, 1), 0.0), Vector3(0, 0.55, 0.05)), Vector3(0.5, 0.08, 1.35))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.3, 0.65)), 0.06, 0.06, 0.25, 10, true, 0.0, 1, GASIFIER)
			timber(k, Vector3(0, 0.32, -0.5), Vector3(0, 0.36, -2.4), 0.07)
			timber(k, Vector3(0, 0.12, -0.6), Vector3(0, 0.34, -1.8), 0.05)
			k.box("planks", I.translated(Vector3(0, 0.55, -2.25)), Vector3(0.04, 1.0, 0.85))
		"windmill_rotor":
			# Four lattice sails clad in canvas, on a hub; turns about its local z.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, -0.1)), 0.16, 0.12, 0.25, 12, true, 0.0, 1, GASIFIER)
			for n in 4:
				var b := Basis(Vector3(0, 0, 1), TAU * n / 4.0)
				var tip := b * Vector3(0, 3.3, 0)
				timber(k, b * Vector3(0, 0.12, 0), tip, 0.07)
				# The lattice: two rails and the bars between them, clad on the windward face.
				var side := b * Vector3(1, 0, 0)
				var r0 := b * Vector3(0, 0.75, 0)
				timber(k, r0 + side * 0.62, tip + side * 0.62, 0.03)
				for j in 7:
					var p: Vector3 = r0.lerp(tip, j / 6.0)
					timber(k, p, p + side * 0.62, 0.03)
				var mid: Vector3 = (r0 + tip) * 0.5 + side * 0.31
				k.box("linen", Transform3D(b, mid + Vector3(0, 0, 0.035)), Vector3(0.58, (tip - r0).length() * 0.98, 0.01))
		"switch_blade":
			# The knife: two copper blades on a hinge, joined by a wooden handle. Turns
			# about its local x at the lower jaws; closed lies flat up into the top jaws.
			for x in [-0.04, 0.04]:
				k.box("painted", I.translated(Vector3(x, 0.1, 0)), Vector3(0.008, 0.22, 0.022), COPPER)
			k.box("planks", I.translated(Vector3(0, 0.22, 0)), Vector3(0.12, 0.02, 0.02))
			k.cylinder("planks", I.translated(Vector3(0, 0.22, 0)), 0.018, 0.016, 0.1, 8, true, 0.0, 1, Color(0.3, 0.18, 0.1))
		"lever_arm":
			# An iron arm with a turned wooden grip; it turns about its local x at the boss.
			beam(k, "cast_iron", Vector3.ZERO, Vector3(0, 0.2, 0), 0.011, 8, GASIFIER)
			k.cylinder("planks", I.translated(Vector3(0, 0.19, 0)), 0.02, 0.016, 0.09, 10, true, 0.0, 1, Color(0.24, 0.13, 0.07))
			k.sphere("planks", I.translated(Vector3(0, 0.285, 0)), 0.022, 5, 10, 0.0, 1.0, Color(0.24, 0.13, 0.07))
		"button_cap":
			# A red enamel mushroom cap (paint, not a light).
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, -0.01)), 0.022, 0.022, 0.02, 12, true, 0.0, 1, Color(0.6, 0.1, 0.08))
			k.sphere("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.01)), 0.032, 4, 14, 0.0, 0.5, Color(0.62, 0.1, 0.08), true)
		"plate_top":
			# The chequer plate: an iron sheet with raised diamond treads.
			k.box("cast_iron", I, Vector3(0.8, 0.02, 0.8), GASIFIER.lightened(0.05))
			for x in 8:
				for z in 8:
					var p := Vector3(-0.35 + x * 0.1, 0.012, -0.35 + z * 0.1)
					k.box("cast_iron", Transform3D(Basis(Vector3.UP, PI * 0.25 if (x + z) % 2 == 0 else -PI * 0.25), p), Vector3(0.05, 0.005, 0.012), GASIFIER.lightened(0.1))
		"turret_head":
			# The yoke: a turntable and two cheeks the gun trunnions sit in.
			k.cylinder("cast_iron", I, 0.18, 0.18, 0.06, 18, true, 0.0, 1, GASIFIER.darkened(0.1))
			for x in [-0.17, 0.17]:
				k.box("cast_iron", I.translated(Vector3(x, 0.15, 0)), Vector3(0.05, 0.26, 0.18), GASIFIER)
			k.box("painted", I.translated(Vector3(0, 0.05, 0.12)), Vector3(0.2, 0.12, 0.12), ENGINE_GREEN)
		"turret_gun":
			# A hand-cranked-look rotary gun, motor driven: a cluster of six barrels in two
			# guide rings, the breech casing, and a drum magazine on top. Points along -z.
			var bx := Basis(Vector3(1, 0, 0), PI * 0.5)
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.12)), Vector3(0.26, 0.2, 0.36), GASIFIER)
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0, 0)), 0.035, 0.035, 0.36, 10, true, 0.0, 1, GASIFIER.darkened(0.2))
			for n in 6:
				var a := TAU * n / 6.0
				var off := Vector3(cos(a), sin(a), 0) * 0.05
				beam(k, "cast_iron", off + Vector3(0, 0, -0.06), off + Vector3(0, 0, -0.96), 0.014, 8, GASIFIER.darkened(0.3))
			for z in [-0.35, -0.9]:
				k.cylinder("gold", Transform3D(bx, Vector3(0, 0, z)), 0.075, 0.075, 0.03, 16, true, 0.0, 1, BRASS)
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0.17, 0.1)), 0.12, 0.12, 0.08, 18, true, 0.0, 1, ENGINE_GREEN)
		"heavy_head":
			# A low turret ring with an armour shield across the front.
			k.cylinder("cast_iron", I, 0.38, 0.38, 0.08, 20, true, 0.0, 1, GASIFIER.darkened(0.15))
			k.box("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -0.18), Vector3(0, 0.36, -0.36)), Vector3(0.86, 0.62, 0.05), ENGINE_GREEN.darkened(0.2))
			for x in [-0.3, 0.3]:
				k.box("cast_iron", I.translated(Vector3(x, 0.22, 0)), Vector3(0.06, 0.32, 0.4), GASIFIER)
			rivets(k, Vector3(-0.38, 0.62, -0.42), Vector3(0.38, 0.62, -0.42), 7, Vector3(0, 0, -1))
		"heavy_gun":
			# Twin heavy barrels with cooling jackets on one cradle. Points along -z.
			k.box("cast_iron", I.translated(Vector3(0, 0, 0.15)), Vector3(0.44, 0.24, 0.5), GASIFIER)
			for x in [-0.12, 0.12]:
				var bx := Basis(Vector3(1, 0, 0), PI * 0.5)
				k.cylinder("cast_iron", Transform3D(bx, Vector3(x, 0, -0.55)), 0.06, 0.06, 0.8, 14, true, 0.0, 1, GASIFIER.darkened(0.1))
				for n in 9:
					k.cylinder("cast_iron", Transform3D(bx, Vector3(x, 0, -0.25 - n * 0.065)), 0.07, 0.07, 0.02, 14, true, 0.0, 1, GASIFIER.darkened(0.3))
				beam(k, "cast_iron", Vector3(x, 0, -0.9), Vector3(x, 0, -1.34), 0.03, 10, GASIFIER.darkened(0.35))
		"spikes":
			# A bed of iron spikes on a plate; it rises through the grate.
			k.box("cast_iron", I, Vector3(0.96, 0.03, 0.96), GASIFIER.darkened(0.2))
			for x in 5:
				for z in 5:
					var p := Vector3(-0.38 + x * 0.19, 0.0, -0.38 + z * 0.19)
					k.cylinder("cast_iron", I.translated(p), 0.025, 0.002, 0.3, 6, false, 0.0, 1, GASIFIER.lightened(0.05))
		"bell_clapper":
			k.box("cast_iron", I.translated(Vector3(0, -0.05, 0)), Vector3(0.012, 0.1, 0.012))
			k.sphere("cast_iron", I.translated(Vector3(0, -0.1, 0)), 0.02, 4, 8)
		"search_yoke":
			k.cylinder("cast_iron", I, 0.15, 0.15, 0.05, 16, true, 0.0, 1, GASIFIER.darkened(0.1))
			for x in [-0.3, 0.3]:
				beam(k, "cast_iron", Vector3(x * 0.4, 0.04, 0), Vector3(x, 0.3, 0), 0.022, 6, GASIFIER)
		"search_drum":
			# The lamp drum: a deep steel barrel, cooling fins on its back, the lens a part.
			var bx := Basis(Vector3(1, 0, 0), PI * 0.5)
			k.cylinder("painted", Transform3D(bx, Vector3(0, 0, -0.06)), 0.26, 0.26, 0.42, 22, false, 0.0, 1, Color(0.3, 0.32, 0.3))
			k.cylinder("painted", Transform3D(bx, Vector3(0, 0, 0.15)), 0.26, 0.18, 0.08, 22, true, 0.0, 1, Color(0.3, 0.32, 0.3))
			for n in 5:
				k.cylinder("cast_iron", Transform3D(bx, Vector3(0, 0, 0.0 + n * 0.035)), 0.27, 0.27, 0.01, 22, true, 0.0, 1, GASIFIER)
			k.cylinder("gold", Transform3D(bx, Vector3(0, 0, -0.38)), 0.27, 0.27, 0.03, 22, false, 0.0, 1, BRASS)
			for x in [-0.27, 0.27]:
				k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x, 0, 0)), 0.03, 0.03, 0.06, 8)
		"search_lens":
			k.cylinder("glass", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3.ZERO), 0.25, 0.25, 0.01, 22)
		"robot_arm":
			# Two links and a gripper, reaching out along -z from the turntable.
			k.cylinder("painted", I, 0.1, 0.1, 0.12, 12, true, 0.0, 1, Color(0.78, 0.55, 0.12))
			beam(k, "painted", Vector3(0, 0.06, 0), Vector3(0, 0.45, -0.25), 0.04, 8, Color(0.78, 0.55, 0.12))
			k.sphere("cast_iron", I.translated(Vector3(0, 0.45, -0.25)), 0.055, 5, 10)
			beam(k, "painted", Vector3(0, 0.45, -0.25), Vector3(0, 0.2, -0.62), 0.035, 8, Color(0.78, 0.55, 0.12))
			for x in [-0.04, 0.04]:
				k.box("cast_iron", I.translated(Vector3(x, 0.14, -0.64)), Vector3(0.015, 0.1, 0.03), GASIFIER)
		"drill_bit":
			# A spiral rock drill along -z.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0, 0)), 0.07, 0.07, 0.1, 10, true, 0.0, 1, GASIFIER)
			for n in 8:
				var b := Basis(Vector3(0, 0, 1), n * 0.8)
				k.box("cast_iron", Transform3D(b, Vector3(0, 0, -0.12 - n * 0.06)), Vector3(0.16 - n * 0.012, 0.02, 0.04), GASIFIER.lightened(0.08))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0, -0.1)), 0.025, 0.004, 0.5, 8, true, 0.0, 1, GASIFIER.lightened(0.08))
		"quarry_bit":
			k.cylinder("cast_iron", I.translated(Vector3(0, -0.2, 0)), 0.2, 0.06, 0.3, 12, true, 0.0, 1, GASIFIER.lightened(0.05))
			for n in 4:
				var b := Basis(Vector3.UP, n * PI * 0.5)
				k.box("cast_iron", Transform3D(b, b * Vector3(0.18, -0.1, 0)), Vector3(0.12, 0.05, 0.04), GASIFIER)
		"saw_blade":
			# A big circular saw blade standing up in the bench, turning about x.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), 0.32, 0.32, 0.006, 32, true, 0.0, 1, GASIFIER.lightened(0.2))
			for n in 24:
				var a := TAU * n / 24.0
				k.box("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0, cos(a), sin(a)) * 0.33), Vector3(0.008, 0.025, 0.025), GASIFIER.lightened(0.2))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), 0.05, 0.05, 0.03, 10)
		"wheel_rim":
			# The water wheel: two rims on spokes with paddles between, turning about x.
			for x in [-0.6, 0.6]:
				for n in 16:
					var a0 := TAU * n / 16.0
					var a1 := TAU * (n + 1) / 16.0
					timber(k, Vector3(x, cos(a0), sin(a0)) * Vector3(1, 1.35, 1.35), Vector3(x, cos(a1), sin(a1)) * Vector3(1, 1.35, 1.35), 0.07)
				for n in 6:
					var a := TAU * n / 6.0
					timber(k, Vector3(x, 0, 0), Vector3(x, cos(a) * 1.3, sin(a) * 1.3), 0.06)
			for n in 12:
				var a := TAU * n / 12.0
				k.box("planks", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0, cos(a), sin(a)) * 1.3), Vector3(1.2, 0.04, 0.3))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), 0.08, 0.08, 1.5, 10, true, 0.0, 1, GASIFIER)
		"flywheel":
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), 0.5, 0.5, 0.08, 24, true, 0.0, 1, GASIFIER.darkened(0.1))
			for n in 6:
				var a := TAU * n / 6.0
				k.box("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0, cos(a), sin(a)) * 0.25), Vector3(0.05, 0.42, 0.06), GASIFIER.darkened(0.15))
		"bulb":
			# A pear-shaped glass bulb, its neck up.
			k.sphere("glass", I.translated(Vector3(0, -0.035, 0)), 0.035, 8, 12, 0.0, 1.15)
			k.cylinder("glass", I.translated(Vector3(0, -0.01, 0)), 0.018, 0.016, 0.03, 10)
		"globe":
			k.sphere("glass", I, 0.065, 8, 14, 0.0, 1.1)
		"flood_lens":
			k.box("glass", I, Vector3(0.42, 0.36, 0.01))
		"street_glass":
			k.cylinder("glass", I, 0.15, 0.185, 0.29, 6, false)
	var out := k.commit(Materials.get_mat)
	_lock.lock()
	_parts[name] = out
	_lock.unlock()
	return out
