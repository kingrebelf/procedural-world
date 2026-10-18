class_name PowerKit
## Meshes for the powered pieces (generators, batteries, poles, switches and lamps), built
## with MeshKit from the game's photo materials: riveted iron, painted steel, oak, brass
## and glass, early-industrial rather than sci-fi. proc() makes a piece's still parts (they
## go in the chunk's MultiMesh like any piece); part() makes the parts that move or light
## up, which PowerNode poses: a windmill's head and sails, a switch's blade, a lamp's bulb.
## Free-standing pieces face you with their local -z (BuildCatalog turns them that way);
## wall pieces stand out of the wall along +z; ceiling pieces hang down from their origin.

const COPPER := Color(0.78, 0.46, 0.28)
const BRASS := Color(1.0, 0.9, 0.68) ## a tint over the gold material: bright worked brass
const ENGINE_GREEN := Color(0.24, 0.33, 0.25)
const GASIFIER := Color(1.0, 0.97, 0.94) ## a tint over the cast iron
const ENAMEL := Color(0.86, 0.85, 0.8)
const CERAMIC := Color(0.92, 0.9, 0.86)
const STEEL_GREY := Color(0.36, 0.4, 0.38) ## painted sheet steel on switchgear
const SAFETY_GREY := Color(0.46, 0.48, 0.47) ## machine frames
const ARM_ORANGE := Color(0.86, 0.48, 0.12) ## robot arms
const DERRICK_RED := Color(0.55, 0.16, 0.12) ## oxide-red steelwork and cast wheels
const BOILER_GREEN := Color(0.16, 0.28, 0.2) ## a lined-out boiler barrel
const BOILER_BLACK := Color(0.12, 0.12, 0.13)
const SHADE_GREEN := Color(0.12, 0.3, 0.2) ## green enamel lamp shades
const BOX_STEEL := Color(0.47, 0.48, 0.47) ## worn grey switchgear steel
const WEATHERED := Color(0.92, 0.82, 0.7) ## warm, sun-dried timber over the planks photo
const RUST_FRAME := Color(0.46, 0.33, 0.26) ## rust-brown iron frames on the traps

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
	k.box("planks", Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, l, w), WEATHERED)

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

## A worn grey steel box on the wall, its face toward +z: a lid with four screws, side
## mounting lugs and two brass binding posts on top (the signal terminals). `window`
## (x, y, w, h) cuts a glazed window in the lid, framed, for what is inside to show.
static func _steel_box(k: MeshKit, size: Vector3, window := Vector4.ZERO) -> void:
	var I := Transform3D.IDENTITY
	var z := size.z
	if window == Vector4.ZERO:
		k.box("painted", I.translated(Vector3(0, 0, z * 0.5)), size, BOX_STEEL)
	else:
		# The box as a shell, so the window shows into it.
		_case(k, "painted", size, BOX_STEEL)
		var wx := window.x
		var wy := window.y
		var ww := window.z
		var wh := window.w
		var hw := size.x * 0.5
		var hh := size.y * 0.5
		# The lid round the window: four strips.
		k.box("painted", I.translated(Vector3(0, (hh + wy + wh * 0.5) * 0.5, z - 0.003)), Vector3(size.x, hh - wy - wh * 0.5, 0.006), BOX_STEEL)
		k.box("painted", I.translated(Vector3(0, (-hh + wy - wh * 0.5) * 0.5, z - 0.003)), Vector3(size.x, wy - wh * 0.5 + hh, 0.006), BOX_STEEL)
		k.box("painted", I.translated(Vector3((-hw + wx - ww * 0.5) * 0.5, wy, z - 0.003)), Vector3(wx - ww * 0.5 + hw, wh, 0.006), BOX_STEEL)
		k.box("painted", I.translated(Vector3((hw + wx + ww * 0.5) * 0.5, wy, z - 0.003)), Vector3(hw - wx - ww * 0.5, wh, 0.006), BOX_STEEL)
		for e in [[Vector3(wx, wy + wh * 0.5, z + 0.003), Vector3(ww + 0.02, 0.012, 0.008)], [Vector3(wx, wy - wh * 0.5, z + 0.003), Vector3(ww + 0.02, 0.012, 0.008)],
				[Vector3(wx - ww * 0.5, wy, z + 0.003), Vector3(0.012, wh, 0.008)], [Vector3(wx + ww * 0.5, wy, z + 0.003), Vector3(0.012, wh, 0.008)]]:
			k.box("metal_dark", I.translated(e[0]), e[1])
		k.box("clear_glass", I.translated(Vector3(wx, wy, z - 0.004)), Vector3(ww, wh, 0.003))
	# A raised lid lip and its four screws.
	for sy in [-1.0, 1.0]:
		k.box("painted", I.translated(Vector3(0, sy * (size.y * 0.5 - 0.006), z + 0.002)), Vector3(size.x, 0.012, 0.006), BOX_STEEL.darkened(0.1))
	for sx in [-1.0, 1.0]:
		k.box("painted", I.translated(Vector3(sx * (size.x * 0.5 - 0.006), 0, z + 0.002)), Vector3(0.012, size.y, 0.006), BOX_STEEL.darkened(0.1))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := Vector3(c.x * (size.x * 0.5 - 0.022), c.y * (size.y * 0.5 - 0.022), z + 0.004)
		k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), at), 0.009, 0.009, 0.005, 8)
	# Mounting lugs either side, screwed to the wall.
	for sx in [-1.0, 1.0]:
		k.box("metal_dark", I.translated(Vector3(sx * (size.x * 0.5 + 0.02), 0, 0.004)), Vector3(0.04, 0.07, 0.008))
		k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(sx * (size.x * 0.5 + 0.022), 0, 0.008)), 0.007, 0.007, 0.004, 6)
	# Two brass binding posts on top, on a black insulating block.
	k.box("rubber", I.translated(Vector3(0, size.y * 0.5 + 0.006, z * 0.5)), Vector3(size.x * 0.6, 0.012, z * 0.6))
	for x in [-0.045, 0.045]:
		_binding_post(k, Vector3(x, size.y * 0.5 + 0.012, z * 0.5))

## A brass binding post standing up from `at`: a threaded stem, a knurled nut and a cap.
static func _binding_post(k: MeshKit, at: Vector3) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("gold", I.translated(at), 0.016, 0.016, 0.012, 10, true, 0.0, 1, BRASS)
	k.cylinder("gold", I.translated(at + Vector3(0, 0.012, 0)), 0.006, 0.006, 0.014, 6, true, 0.0, 1, BRASS)
	k.cylinder("gold", I.translated(at + Vector3(0, 0.026, 0)), 0.014, 0.014, 0.014, 10, true, 0.0, 1, BRASS.lightened(0.1))

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
			# A big spoked flywheel on the crankshaft, out in front of the block.
			var fc := eng + Vector3(-0.1, 0.37, -0.32)
			beam(k, "metal", fc + Vector3(0, 0, 0.0), fc + Vector3(0, 0, 0.12), 0.03, 8)
			beam(k, "cast_iron", fc + Vector3(0, 0, -0.04), fc + Vector3(0, 0, 0.03), 0.3, 24, GASIFIER.darkened(0.1))
			beam(k, "metal_dark", fc + Vector3(0, 0, -0.045), fc + Vector3(0, 0, 0.035), 0.25, 24)
			for n in 6:
				var a := TAU * n / 6.0
				k.box("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), a), fc + Vector3(-sin(a), cos(a), 0) * 0.13 + Vector3(0, 0, -0.005)), Vector3(0.035, 0.24, 0.03), GASIFIER.darkened(0.1))
			beam(k, "cast_iron", fc + Vector3(0, 0, -0.06), fc + Vector3(0, 0, 0.05), 0.06, 12, GASIFIER)
			# The dynamo on the engine's far side, its brass terminals on top.
			var dyn := eng + Vector3(0.18, 0.26, 0.0)
			beam(k, "painted", dyn, dyn + Vector3(0.22, 0, 0), 0.13, 14, Color(0.2, 0.2, 0.22))
			for z in [-0.05, 0.05]:
				k.cylinder("gold", I.translated(dyn + Vector3(0.11, 0.12, z)), 0.018, 0.018, 0.04, 6, true, 0.0, 1, BRASS)
			# Exhaust stack up the back corner.
			beam(k, "rust", eng + Vector3(0.1, 0.7, 0.18), eng + Vector3(0.1, 1.45, 0.3), 0.04)
			k.cylinder("rust", I.translated(eng + Vector3(0.1, 1.45, 0.3)), 0.055, 0.06, 0.08, 10)
			# A pressure gauge on the drum, needle and tick marks only.
			var g := drum + Vector3(0.18, 0.95, -0.3)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), g), 0.06, 0.06, 0.03, 12, true, 0.0, 1, BRASS)
			k.box("painted", I.translated(g + Vector3(0, 0, -0.032)), Vector3(0.085, 0.085, 0.004), ENAMEL)
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), 0.6), g + Vector3(0, 0, -0.036)), Vector3(0.006, 0.05, 0.004), Color(0.1, 0.1, 0.1))
		"pw_diesel":
			# A green engine-generator set on a green steel skid: the radiator with its mesh
			# grille at the front (-z), the engine block with its injector pipes, the
			# generator drum at the back, and an exhaust silencer up on top.
			var dg := Color(0.3, 0.42, 0.3)
			for x in [-0.44, 0.44]:
				k.box("painted", I.translated(Vector3(x, 0.08, 0)), Vector3(0.1, 0.16, 1.8), dg.darkened(0.15))
				rivets(k, Vector3(x * 1.13, 0.08, -0.85), Vector3(x * 1.13, 0.08, 0.85), 6, Vector3(signf(x), 0, 0))
			for z in [-0.85, 0.0, 0.85]:
				k.box("painted", I.translated(Vector3(0, 0.08, z)), Vector3(0.88, 0.12, 0.08), dg.darkened(0.15))
			# Engine mounts and the block.
			for z in [-0.4, 0.15]:
				k.box("metal_dark", I.translated(Vector3(0, 0.2, z)), Vector3(0.6, 0.08, 0.1))
			k.box("machine_paint", I.translated(Vector3(0, 0.5, -0.12)), Vector3(0.52, 0.54, 0.8), dg)
			k.box("machine_paint", I.translated(Vector3(0, 0.84, -0.12)), Vector3(0.4, 0.14, 0.7), dg.lightened(0.05))
			for n in 4:
				var z := -0.4 + n * 0.18
				k.box("machine_paint", I.translated(Vector3(0, 0.93, z)), Vector3(0.3, 0.04, 0.1), dg.darkened(0.1))
				# Injector pipes curling down the side.
				beam(k, "metal", Vector3(0.21, 0.88, z), Vector3(0.28, 0.75, z), 0.008, 5)
				beam(k, "metal", Vector3(0.28, 0.75, z), Vector3(0.28, 0.55, -0.05), 0.008, 5)
			k.box("machine_paint", I.translated(Vector3(0.3, 0.5, -0.05)), Vector3(0.1, 0.16, 0.26), dg.darkened(0.05))
			beam(k, "machine_paint", Vector3(-0.27, 0.72, -0.4), Vector3(-0.27, 0.72, 0.2), 0.04, 8, dg)
			# Radiator: a deep box with a dark mesh face, filler cap on top.
			k.box("machine_paint", I.translated(Vector3(0, 0.6, -0.68)), Vector3(0.76, 0.84, 0.2), dg)
			k.box("metal_dark", I.translated(Vector3(0, 0.6, -0.785)), Vector3(0.62, 0.68, 0.01))
			for n in 12:
				k.box("metal_dark", I.translated(Vector3(-0.28 + n * 0.051, 0.6, -0.792)), Vector3(0.006, 0.66, 0.006))
			for n in 13:
				k.box("metal_dark", I.translated(Vector3(0, 0.29 + n * 0.051, -0.794)), Vector3(0.6, 0.006, 0.006))
			k.cylinder("metal", I.translated(Vector3(-0.2, 1.02, -0.68)), 0.035, 0.035, 0.04, 10)
			beam(k, "rubber", Vector3(0.1, 0.92, -0.6), Vector3(0.1, 0.8, -0.45), 0.03, 8)
			# The generator drum, its ribbed bell housing and the terminal box.
			beam(k, "machine_paint", Vector3(0, 0.5, 0.28), Vector3(0, 0.5, 0.78), 0.3, 20, dg)
			beam(k, "machine_paint", Vector3(0, 0.5, 0.26), Vector3(0, 0.5, 0.36), 0.33, 20, dg.darkened(0.1))
			for n in 3:
				beam(k, "machine_paint", Vector3(0, 0.5, 0.44 + n * 0.12), Vector3(0, 0.5, 0.46 + n * 0.12), 0.31, 20, dg.darkened(0.1))
			k.box("machine_paint", I.translated(Vector3(0.3, 0.72, 0.5)), Vector3(0.2, 0.24, 0.2), dg.lightened(0.04))
			for z in [0.46, 0.54]:
				k.cylinder("gold", I.translated(Vector3(0.3, 0.84, z)), 0.014, 0.014, 0.04, 6, true, 0.0, 1, BRASS)
			# Exhaust: a pipe up to a silencer drum lying along the top, the stack up.
			beam(k, "metal", Vector3(-0.15, 0.9, 0.1), Vector3(-0.1, 1.1, 0.1), 0.04, 8)
			beam(k, "metal", Vector3(0.18, 1.12, -0.25), Vector3(0.18, 1.12, 0.25), 0.1, 14)
			beam(k, "metal_dark", Vector3(0.18, 1.12, -0.27), Vector3(0.18, 1.12, -0.24), 0.105, 14)
			beam(k, "metal_dark", Vector3(0.18, 1.12, 0.24), Vector3(0.18, 1.12, 0.27), 0.105, 14)
			beam(k, "metal", Vector3(-0.1, 1.1, 0.1), Vector3(0.1, 1.12, 0.1), 0.04, 8)
			beam(k, "metal", Vector3(0.18, 1.2, 0.12), Vector3(0.18, 1.5, 0.12), 0.035, 8)
			# Lifting eyes on the corners.
			for p in [Vector3(-0.38, 1.03, -0.68), Vector3(0.38, 1.03, -0.68)]:
				k.cylinder("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), p), 0.03, 0.03, 0.012, 10, false)
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
				beam(k, "painted", Vector3(x, 0, -0.45), Vector3(x, 1.25, -0.25), 0.03, 6, Color(0.72, 0.73, 0.74))
				beam(k, "painted", Vector3(x, 0, 0.35), Vector3(x, 0.78, 0.2), 0.03, 6, Color(0.72, 0.73, 0.74))
				k.box("cobble", I.translated(Vector3(x, 0.05, -0.45)), Vector3(0.22, 0.1, 0.22))
				k.box("cobble", I.translated(Vector3(x, 0.05, 0.35)), Vector3(0.22, 0.1, 0.22))
			# A white backsheet behind the cells, in a raised aluminium frame; two rails
			# across the back carry it on the stand.
			k.box("painted", Transform3D(pb, c), Vector3(1.96, 0.03, 1.06), Color(0.84, 0.85, 0.86))
			for z in [-0.545, 0.545]:
				k.box("painted", Transform3D(pb, c + pb * Vector3(0, 0.0, z)), Vector3(2.04, 0.07, 0.035), Color(0.8, 0.81, 0.82))
			for x in [-1.005, 1.005]:
				k.box("painted", Transform3D(pb, c + pb * Vector3(x, 0.0, 0)), Vector3(0.035, 0.07, 1.12), Color(0.8, 0.81, 0.82))
			for x in [-0.8, 0.8]:
				k.box("painted", Transform3D(pb, c + pb * Vector3(x, -0.04, 0)), Vector3(0.05, 0.04, 1.06), Color(0.72, 0.73, 0.74))
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
					k.box("clear_glass", I.translated(j + Vector3(0, 0.17, 0)), Vector3(0.2, 0.34, 0.3))
					k.box("metal_dark", I.translated(j + Vector3(0, 0.02, 0)), Vector3(0.19, 0.04, 0.29))
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
			# A grey steel box on the wall with a screwed lid and mounting lugs; four brass
			# cable glands below with rubber cables out of them, bared copper at the ends.
			k.box("painted", I.translated(Vector3(0, 0, 0.06)), Vector3(0.3, 0.26, 0.12), BOX_STEEL)
			k.box("painted", I.translated(Vector3(0, 0, 0.125)), Vector3(0.28, 0.24, 0.012), BOX_STEEL.lightened(0.06))
			for c in [Vector2(-0.12, -0.1), Vector2(0.12, -0.1), Vector2(-0.12, 0.1), Vector2(0.12, 0.1)]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(c.x, c.y, 0.13)), 0.012, 0.012, 0.008, 8)
			for sx in [-1.0, 1.0]:
				k.box("metal_dark", I.translated(Vector3(sx * 0.17, 0.08, 0.006)), Vector3(0.05, 0.05, 0.012))
			for x in [-0.09, -0.03, 0.03, 0.09]:
				k.cylinder("gold", I.translated(Vector3(x, -0.165, 0.06)), 0.022, 0.022, 0.035, 6, true, 0.0, 1, BRASS)
				k.cylinder("gold", I.translated(Vector3(x, -0.185, 0.06)), 0.016, 0.02, 0.02, 10, true, 0.0, 1, BRASS)
				beam(k, "rubber", Vector3(x, -0.185, 0.06), Vector3(x * 1.1, -0.26, 0.075), 0.011, 8)
				beam(k, "painted", Vector3(x * 1.1, -0.26, 0.075), Vector3(x * 1.12, -0.285, 0.078), 0.006, 6, COPPER)
		"pw_switch":
			# A thick black slate base on the wall: two pairs of copper jaws on brass
			# blocks and the hinge post; the blade is a part.
			k.box("slate_board", I.translated(Vector3(0, 0, 0.025)), Vector3(0.2, 0.36, 0.05))
			for y in [-0.15, 0.15]:
				for x in [-0.075, 0.075]:
					k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(x, y, 0.05)), 0.01, 0.01, 0.006, 8)
			for y in [0.1, -0.1]:
				k.box("gold", I.translated(Vector3(0, y, 0.058)), Vector3(0.12, 0.04, 0.016), BRASS.darkened(0.1))
				for x in [-0.04, 0.04]:
					k.box("painted", I.translated(Vector3(x, y, 0.08)), Vector3(0.014, 0.04 if y > 0 else 0.03, 0.05), COPPER)
		"pw_lever":
			# A heavy cast backplate screwed to the wall, a round pivot boss, and a graduated
			# brass quadrant the arm moves over; the arm is a part (PowerNode swings it).
			k.box("painted", I.translated(Vector3(0, 0, 0.015)), Vector3(0.2, 0.34, 0.03), Color(0.2, 0.2, 0.21))
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(c.x * 0.075, c.y * 0.14, 0.03)), 0.012, 0.012, 0.006, 8)
			for n in 9:
				var a := -0.75 + n * 0.19
				k.box("painted", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0.06, 0.02, 0.06) + Vector3(0, sin(a), cos(a)) * 0.0), Vector3(0.004, 0.004, 0.004), Color.BLACK)
			# The quadrant: a brass arc plate on the right with tick marks.
			for n in 8:
				var a := -0.8 + n * 0.23
				var p := Vector3(0.05, 0.02 + sin(a) * 0.1, 0.035)
				k.box("gold", Transform3D(Basis(Vector3(0, 0, 1), a), p), Vector3(0.03, 0.022, 0.006), BRASS.darkened(0.2))
				k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), a), p + Vector3(0.006, 0, 0.004)), Vector3(0.016, 0.003, 0.002), Color(0.1, 0.1, 0.1))
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.03)), 0.036, 0.036, 0.03, 16)
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.04, 0.02, 0.06)), 0.016, 0.016, 0.08, 10)
			_box_terminal(k, Vector3(0, -0.16, 0.03))
		"pw_button":
			# A round cast-iron flange screwed to the wall, a thick brass bezel; the red
			# mushroom cap is a part, pushed in.
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0)), 0.1, 0.095, 0.03, 24, true, 0.0, 1, Color(0.2, 0.2, 0.21))
			for n in 4:
				var a := TAU * n / 4.0 + PI * 0.25
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(cos(a), sin(a), 0) * 0.078 + Vector3(0, 0, 0.03)), 0.011, 0.011, 0.006, 8)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.03)), 0.062, 0.056, 0.03, 24, true, 0.0, 1, BRASS)
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.055)), 0.046, 0.046, 0.006, 20)
			_box_terminal(k, Vector3(0, -0.11, 0.02))
		"pw_plate":
			# A riveted iron frame flush on the ground; the chequer-plate top is a part.
			for side in [-1.0, 1.0]:
				k.box("cast_iron", I.translated(Vector3(side * 0.43, 0.025, 0)), Vector3(0.06, 0.05, 0.92), RUST_FRAME)
				k.box("cast_iron", I.translated(Vector3(0, 0.025, side * 0.43)), Vector3(0.8, 0.05, 0.06), RUST_FRAME)
			for c in [Vector3(-0.43, 0.052, -0.43), Vector3(0.43, 0.052, -0.43), Vector3(-0.43, 0.052, 0.43), Vector3(0.43, 0.052, 0.43)]:
				k.sphere("cast_iron", I.translated(c), 0.016, 3, 6, 0.0, 0.6, BOX_STEEL, true)
			k.box("cast_iron", I.translated(Vector3(0, 0.03, -0.47)), Vector3(0.06, 0.04, 0.03), GASIFIER)
		"pw_motion":
			# A grey steel wall bracket holding out a domed hood with a dark glass eye
			# under it, looking out ahead and down.
			k.box("painted", I.translated(Vector3(0, 0.02, 0.01)), Vector3(0.14, 0.2, 0.02), BOX_STEEL)
			for y in [-0.06, 0.1]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, y, 0.02)), 0.009, 0.009, 0.005, 8)
			k.box("painted", I.translated(Vector3(0, 0.03, 0.05)), Vector3(0.08, 0.07, 0.07), BOX_STEEL)
			k.sphere("painted", Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0, 0.02, 0.1)), 0.075, 6, 16, 0.0, 0.85, BOX_STEEL.lightened(0.08), true)
			k.sphere("glass", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.6), Vector3(0, 0.0, 0.11)), 0.055, 6, 14, 0.0, 1.0, Color(0.1, 0.1, 0.12), true)
			_box_terminal(k, Vector3(0, -0.08, 0.02))
		"pw_daylight":
			# A grey cast box on lugs with a glass dome on top over a blue photocell, a brass
			# ring, and a cable gland out of its side.
			k.box("painted", I.translated(Vector3(0, -0.01, 0.06)), Vector3(0.13, 0.12, 0.12), BOX_STEEL.lightened(0.1))
			for c in [Vector2(-1, -1), Vector2(1, -1)]:
				k.box("painted", I.translated(Vector3(c.x * 0.08, -0.06, 0.03)), Vector3(0.04, 0.02, 0.06), BOX_STEEL)
			k.cylinder("gold", I.translated(Vector3(0, 0.05, 0.06)), 0.052, 0.052, 0.014, 18, true, 0.0, 1, BRASS)
			k.cylinder("solar_cell", I.translated(Vector3(0, 0.064, 0.06)), 0.04, 0.04, 0.004, 16)
			k.sphere("clear_glass", I.translated(Vector3(0, 0.064, 0.06)), 0.05, 6, 16, 0.0, 1.0, Color.WHITE, true)
			beam(k, "metal_dark", Vector3(0.065, -0.01, 0.06), Vector3(0.1, -0.01, 0.06), 0.02, 10)
			beam(k, "rubber", Vector3(0.1, -0.01, 0.06), Vector3(0.16, -0.08, 0.04), 0.01, 6)
			_box_terminal(k, Vector3(0, -0.08, 0.03))
		"pw_timer":
			# A grey steel box; on its face a big enamel dial ringed with brass setting
			# pins, and a pointer.
			_steel_box(k, Vector3(0.24, 0.3, 0.09))
			_dial(k, Vector3(0, -0.005, 0.094), 0.088, 12, 0.85)
			for n in 24:
				var a := TAU * n / 24.0
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(sin(a), cos(a), 0) * 0.1 + Vector3(0, -0.005, 0.092)), 0.006, 0.005, 0.016, 6)
		"pw_clock":
			# A grey steel box with a clock face in a heavy brass bezel: a time switch.
			_steel_box(k, Vector3(0.26, 0.3, 0.09))
			var cf := Vector3(0, -0.01, 0.09)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), cf), 0.105, 0.1, 0.016, 28, true, 0.0, 1, BRASS)
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), cf + Vector3(0, 0, 0.012)), 0.088, 0.088, 0.006, 28, true, 0.0, 1, ENAMEL)
			for n in 12:
				var a := TAU * n / 12.0
				var tl := 0.016 if n % 3 == 0 else 0.009
				k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -a), cf + Vector3(sin(a), cos(a), 0) * (0.078 - tl * 0.5) + Vector3(0, 0, 0.02)), Vector3(0.005, tl, 0.002), Color(0.1, 0.1, 0.1))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -2.1), cf + Vector3(sin(2.1), cos(2.1), 0) * 0.025 + Vector3(0, 0, 0.022)), Vector3(0.007, 0.05, 0.002), Color(0.08, 0.08, 0.08))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -0.7), cf + Vector3(sin(0.7), cos(0.7), 0) * 0.035 + Vector3(0, 0, 0.024)), Vector3(0.005, 0.07, 0.002), Color(0.08, 0.08, 0.08))
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), cf + Vector3(0, 0, 0.018)), 0.007, 0.007, 0.01, 8, true, 0.0, 1, BRASS)
		"pw_gate":
			# A grey steel box with a big window: two copper relay coils on an iron frame
			# inside, four brass input posts across the top.
			_steel_box(k, Vector3(0.26, 0.3, 0.1), Vector4(0, -0.01, 0.2, 0.22))
			k.box("metal_dark", I.translated(Vector3(0, 0.07, 0.04)), Vector3(0.18, 0.016, 0.03))
			k.box("metal_dark", I.translated(Vector3(0, -0.09, 0.04)), Vector3(0.18, 0.016, 0.03))
			for x in [-0.045, 0.045]:
				k.cylinder("painted", I.translated(Vector3(x, -0.075, 0.045)), 0.032, 0.032, 0.14, 16, true, 0.0, 1, COPPER)
				for y in [-0.075, 0.065]:
					k.cylinder("metal_dark", I.translated(Vector3(x, y, 0.045)), 0.036, 0.036, 0.008, 16)
			for x in [-0.09, 0.09]:
				_binding_post(k, Vector3(x, 0.162, 0.05))
		"pw_latch":
			# A grey steel box: a drop flag (red when set) behind a little window, and a
			# black reset button below it.
			_steel_box(k, Vector3(0.24, 0.3, 0.09), Vector4(0, 0.05, 0.12, 0.08))
			k.box("painted", I.translated(Vector3(0, 0.05, 0.07)), Vector3(0.11, 0.07, 0.004), Color(0.08, 0.08, 0.08))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.25), Vector3(0, 0.05, 0.075)), Vector3(0.045, 0.045, 0.004), Color(0.75, 0.1, 0.07))
			k.box("painted", I.translated(Vector3(0, 0.067, 0.076)), Vector3(0.08, 0.026, 0.004), Color(0.75, 0.1, 0.07))
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.065, 0.09)), 0.034, 0.034, 0.01, 18)
			k.cylinder("rubber", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.065, 0.1)), 0.026, 0.024, 0.024, 18)
		"pw_counter":
			# A grey steel box: three number drums behind a window (blank faces, no
			# writing) and a brass reset knob on the side.
			_steel_box(k, Vector3(0.26, 0.3, 0.09), Vector4(0, 0.0, 0.17, 0.08))
			for x in [-0.052, 0.0, 0.052]:
				k.cylinder("painted", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x + 0.024, 0.0, 0.05)), 0.042, 0.042, 0.048, 18, true, 0.0, 1, Color(0.9, 0.84, 0.66))
			beam(k, "gold", Vector3(0.13, 0.0, 0.05), Vector3(0.17, 0.0, 0.05), 0.012, 8, BRASS)
			beam(k, "gold", Vector3(0.17, 0.0, 0.05), Vector3(0.19, 0.0, 0.05), 0.024, 14, BRASS)
		"pw_delay":
			# A grey steel box with a brass dashpot (an oil damper that slows the contact)
			# strapped across its face, its rod out to a brass lever on the side.
			_steel_box(k, Vector3(0.26, 0.3, 0.09))
			beam(k, "gold", Vector3(-0.1, 0.0, 0.13), Vector3(0.06, 0.0, 0.13), 0.04, 18, BRASS)
			for x in [-0.1, 0.06]:
				beam(k, "gold", Vector3(x, 0.0, 0.13), Vector3(x + (0.012 if x < 0 else -0.012), 0.0, 0.13), 0.045, 18, BRASS.darkened(0.1))
			for x in [-0.065, 0.025]:
				k.box("gold", I.translated(Vector3(x, 0.0, 0.11)), Vector3(0.016, 0.1, 0.04), BRASS.darkened(0.15))
			beam(k, "metal", Vector3(0.06, 0.0, 0.13), Vector3(0.13, 0.0, 0.13), 0.008, 8)
			beam(k, "gold", Vector3(0.13, -0.06, 0.12), Vector3(0.13, 0.05, 0.13), 0.01, 8, BRASS)
		"pw_relay":
			# A dark iron box with a glass front: the copper coil, its iron armature and
			# the contact arm inside; brass posts at the top (signal) and bottom (power).
			_case(k, "painted", Vector3(0.24, 0.34, 0.11), Color(0.2, 0.2, 0.21))
			k.box("clear_glass", I.translated(Vector3(0, 0, 0.108)), Vector3(0.21, 0.31, 0.004))
			for e in [[Vector3(0, 0.162, 0.11), Vector3(0.24, 0.018, 0.01)], [Vector3(0, -0.162, 0.11), Vector3(0.24, 0.018, 0.01)], [Vector3(0.112, 0, 0.11), Vector3(0.018, 0.34, 0.01)], [Vector3(-0.112, 0, 0.11), Vector3(0.018, 0.34, 0.01)]]:
				k.box("painted", I.translated(e[0]), e[1], Color(0.24, 0.24, 0.25))
			k.cylinder("painted", I.translated(Vector3(-0.04, -0.09, 0.06)), 0.04, 0.04, 0.13, 16, true, 0.0, 1, COPPER)
			for y in [-0.09, 0.04]:
				k.cylinder("metal_dark", I.translated(Vector3(-0.04, y, 0.06)), 0.045, 0.045, 0.008, 16)
			k.box("metal", I.translated(Vector3(0.0, 0.07, 0.06)), Vector3(0.12, 0.014, 0.03))
			k.box("metal", I.translated(Vector3(0.055, 0.0, 0.06)), Vector3(0.012, 0.12, 0.02))
			k.box("painted", I.translated(Vector3(0.055, -0.07, 0.06)), Vector3(0.03, 0.012, 0.02), COPPER)
			for x in [-0.05, 0.05]:
				_binding_post(k, Vector3(x, 0.17, 0.06))
				k.box("rubber", I.translated(Vector3(x, -0.176, 0.06)), Vector3(0.05, 0.012, 0.05))
				k.cylinder("gold", I.translated(Vector3(x, -0.215, 0.06)), 0.016, 0.016, 0.035, 10, true, 0.0, 1, BRASS)
		"pw_charge":
			# A panel meter: a black iron case with a wide enamel arc scale behind glass, a
			# needle, and two brass terminals on the front below.
			k.box("painted", I.translated(Vector3(0, 0, 0.045)), Vector3(0.26, 0.24, 0.09), Color(0.16, 0.16, 0.17))
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(c.x * 0.112, c.y * 0.102, 0.09)), 0.008, 0.008, 0.005, 8)
			k.box("painted", I.translated(Vector3(0, 0.03, 0.092)), Vector3(0.2, 0.13, 0.003), ENAMEL)
			for n in 15:
				var a := -1.0 + n * (2.0 / 14.0)
				k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), -a), Vector3(sin(a) * 0.085, cos(a) * 0.085 - 0.04, 0.095)), Vector3(0.003, 0.018 if n % 2 == 0 else 0.01, 0.002), Color(0.1, 0.1, 0.1))
			k.box("painted", Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(-sin(0.5) * 0.045, cos(0.5) * 0.045 - 0.04, 0.097)), Vector3(0.004, 0.09, 0.002), Color(0.1, 0.1, 0.1))
			k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, -0.04, 0.094)), 0.012, 0.012, 0.006, 10)
			k.box("clear_glass", I.translated(Vector3(0, 0.03, 0.1)), Vector3(0.21, 0.14, 0.003))
			for x in [-0.07, 0.07]:
				k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(x, -0.08, 0.09)), 0.022, 0.022, 0.025, 12, true, 0.0, 1, BRASS)
		"pw_door_motor":
			# A geared motor on a wall plate: the ribbed green motor drum with its terminal
			# box, a reduction box and the chain sprocket, the chain hanging down to wind
			# the door.
			k.box("painted", I.translated(Vector3(0, 0, 0.012)), Vector3(0.44, 0.34, 0.024), Color(0.2, 0.2, 0.21))
			rivets(k, Vector3(-0.19, 0.15, 0.026), Vector3(0.19, 0.15, 0.026), 4, Vector3(0, 0, 1))
			rivets(k, Vector3(-0.19, -0.15, 0.026), Vector3(0.19, -0.15, 0.026), 4, Vector3(0, 0, 1))
			beam(k, "machine_paint", Vector3(-0.2, 0.02, 0.11), Vector3(0.04, 0.02, 0.11), 0.085, 18, ENGINE_GREEN)
			for n in 7:
				beam(k, "machine_paint", Vector3(-0.18 + n * 0.03, 0.02, 0.11), Vector3(-0.172 + n * 0.03, 0.02, 0.11), 0.094, 18, ENGINE_GREEN.darkened(0.15))
			k.box("machine_paint", I.translated(Vector3(-0.08, 0.13, 0.11)), Vector3(0.1, 0.05, 0.08), ENGINE_GREEN.lightened(0.05))
			k.box("metal_dark", I.translated(Vector3(0.1, 0.02, 0.1)), Vector3(0.1, 0.17, 0.13))
			var sp := Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.16, 0.02, 0.15))
			k.cylinder("metal", sp, 0.07, 0.07, 0.02, 18)
			for n in 12:
				var a := TAU * n / 12.0
				k.box("metal", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(0.16 + cos(a) * 0.075, 0.02 + sin(a) * 0.075, 0.16)), Vector3(0.012, 0.012, 0.02))
			k.cylinder("gold", sp.translated_local(Vector3(0, 0.02, 0)), 0.02, 0.02, 0.02, 8, true, 0.0, 1, BRASS)
			for side in [-1.0, 1.0]:
				for n in 9:
					k.box("metal_dark", I.translated(Vector3(0.16 + side * 0.075, -0.02 - n * 0.03, 0.16)), Vector3(0.014, 0.024, 0.014))
			for x in [-0.12, 0.12]:
				k.cylinder("gold", I.translated(Vector3(x, -0.18, 0.08)), 0.016, 0.018, 0.04, 8, true, 0.0, 1, BRASS)
		"pw_turret":
			# A grey iron pedestal on a riveted cross base, bolted down at each foot, with
			# the drive motor and a junction box on it; the head (yoke) and the gun are
			# parts PowerNode turns.
			for a in 4:
				var b := Basis(Vector3.UP, TAU * a / 4.0 + PI * 0.25)
				k.box("cast_iron", Transform3D(b, b * Vector3(0, 0.05, 0.32)), Vector3(0.14, 0.1, 0.62), GASIFIER.darkened(0.1))
				k.box("cast_iron", Transform3D(b, b * Vector3(0, 0.03, 0.6)), Vector3(0.22, 0.06, 0.12), GASIFIER.darkened(0.15))
				for s in [-0.07, 0.07]:
					k.cylinder("metal_dark", I.translated(b * Vector3(s, 0.06, 0.6)), 0.018, 0.018, 0.03, 6)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.08, 0)), 0.2, 0.16, 0.12, 16, true, 0.0, 1, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 0.2, 0)), 0.11, 0.1, 0.82, 14, true, 0.0, 1, GASIFIER.darkened(0.05))
			for y in [0.45, 0.75]:
				k.cylinder("cast_iron", I.translated(Vector3(0, y, 0)), 0.125, 0.125, 0.04, 14, true, 0.0, 1, GASIFIER.darkened(0.2))
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.0, 0)), 0.16, 0.16, 0.08, 18, true, 0.0, 1, GASIFIER)
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.55, 0.12)), 0.08, 0.08, 0.2, 14, true, 0.0, 1, GASIFIER.darkened(0.15))
			k.box("cast_iron", I.translated(Vector3(0, 0.3, 0.2)), Vector3(0.18, 0.2, 0.1), GASIFIER)
			for x in [-0.05, 0.05]:
				k.cylinder("gold", I.translated(Vector3(x, 0.4, 0.22)), 0.014, 0.016, 0.04, 8, true, 0.0, 1, BRASS)
		"pw_heavy_turret":
			# A squat riveted steel drum on a chamfered concrete plinth with iron corner
			# cleats; the domed head and the twin guns are parts.
			k.box("plaster", I.translated(Vector3(0, 0.2, 0)), Vector3(1.3, 0.4, 1.3), Color(0.8, 0.78, 0.74))
			k.cylinder("plaster", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.4, 0)), 0.92, 0.72, 0.14, 4, true, 0.0, 1, Color(0.78, 0.76, 0.72))
			for a in 4:
				var b := Basis(Vector3.UP, TAU * a / 4.0 + PI * 0.25)
				k.box("painted", Transform3D(b, b * Vector3(0, 0.3, 0.86)), Vector3(0.16, 0.36, 0.06), BOX_STEEL.darkened(0.2))
				for y in [0.2, 0.4]:
					k.cylinder("metal_dark", Transform3D(b * Basis(Vector3(1, 0, 0), PI * 0.5), b * Vector3(0, y, 0.89)), 0.02, 0.02, 0.02, 6)
			k.cylinder("painted", I.translated(Vector3(0, 0.54, 0)), 0.56, 0.56, 0.06, 24, true, 0.0, 1, BOX_STEEL.darkened(0.1))
			k.cylinder("painted", I.translated(Vector3(0, 0.6, 0)), 0.5, 0.5, 0.62, 24, true, 0.0, 1, BOX_STEEL)
			for y in [0.62, 0.9, 1.18]:
				k.cylinder("painted", I.translated(Vector3(0, y, 0)), 0.515, 0.515, 0.04, 24, true, 0.0, 1, BOX_STEEL.darkened(0.12))
				for a in 16:
					var p := Basis(Vector3.UP, TAU * a / 16.0) * Vector3(0, y + 0.02, 0.52)
					k.sphere("metal_dark", I.translated(p), 0.014, 3, 6, 0.0, 0.6)
			k.box("painted", I.translated(Vector3(0, 0.4, 0.6)), Vector3(0.24, 0.24, 0.12), BOX_STEEL.darkened(0.1))
		"pw_fence_post":
			# A square weathered timber post on a scatter of stones, three white ceramic
			# insulators on iron pins up its face, and a small brass warning plate.
			k.box("planks", I.translated(Vector3(0, 0.82, 0)), Vector3(0.14, 1.64, 0.14), Color(0.75, 0.68, 0.6))
			k.box("planks", I.translated(Vector3(0, 1.66, 0)), Vector3(0.12, 0.04, 0.12), Color(0.75, 0.68, 0.6))
			for n in 7:
				var a := TAU * n / 7.0 + 0.3
				k.sphere("cobble", I.translated(Vector3(cos(a) * 0.14, 0.02, sin(a) * 0.14)), 0.05, 3, 6, 0.2, 0.6)
			for y in [0.6, 1.05, 1.5]:
				var at := Vector3(0, y, 0)
				k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.06)), 0.01, 0.01, 0.06, 6)
				k.cylinder("bone", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.1)), 0.045, 0.045, 0.03, 12, true, 0.0, 1, Color.WHITE)
				k.cylinder("bone", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.13)), 0.035, 0.045, 0.03, 12, true, 0.0, 1, Color.WHITE)
				k.cylinder("bone", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at + Vector3(0, 0, -0.16)), 0.045, 0.035, 0.03, 12, true, 0.0, 1, Color.WHITE)
			# The brass warning plate (no writing), with its two screws.
			k.box("gold", I.translated(Vector3(0, 0.36, -0.074)), Vector3(0.11, 0.07, 0.006), BRASS.darkened(0.05))
			for x in [-0.04, 0.04]:
				k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(x, 0.36, -0.077)), 0.006, 0.006, 0.004, 6)
		"pw_spike_trap":
			# A sunken riveted iron frame with a grid of bars; the spikes are a part that
			# punches up between them.
			for side in [-1.0, 1.0]:
				k.box("painted", I.translated(Vector3(side * 0.53, 0.05, 0)), Vector3(0.08, 0.1, 1.14), RUST_FRAME)
				k.box("painted", I.translated(Vector3(0, 0.05, side * 0.53)), Vector3(1.0, 0.1, 0.08), RUST_FRAME)
				rivets(k, Vector3(side * 0.53, 0.1, -0.5), Vector3(side * 0.53, 0.1, 0.5), 6, Vector3.UP, 0.014)
				rivets(k, Vector3(-0.5, 0.1, side * 0.53), Vector3(0.5, 0.1, side * 0.53), 6, Vector3.UP, 0.014)
			for n in 4:
				var o := -0.285 + n * 0.19
				k.box("painted", I.translated(Vector3(o, 0.07, 0)), Vector3(0.025, 0.04, 1.0), RUST_FRAME.darkened(0.15))
				k.box("painted", I.translated(Vector3(0, 0.07, o)), Vector3(1.0, 0.04, 0.025), RUST_FRAME.darkened(0.15))
			k.box("metal_dark", I.translated(Vector3(0, -0.02, 0)), Vector3(1.0, 0.03, 1.0))
		"pw_flame_trap":
			# A riveted iron fuel tank lying on four splayed legs, a brass valve wheel and
			# the pump with its wooden T-handle on top, and the brass nozzle with its
			# vented shroud fed round the front end, facing out (-z).
			var tc := Vector3(0, 0.36, 0.15)
			beam(k, "painted", tc + Vector3(0, 0, 0.3), tc + Vector3(0, 0, -0.3), 0.2, 20, Color(0.34, 0.31, 0.28))
			for z in [-0.3, 0.3]:
				beam(k, "painted", tc + Vector3(0, 0, z - 0.02), tc + Vector3(0, 0, z + 0.02), 0.21, 20, Color(0.28, 0.26, 0.24))
				var cap := Transform3D(Basis(Vector3(1, 0, 0), signf(z) * PI * 0.5), tc + Vector3(0, 0, z))
				k.sphere("painted", cap, 0.2, 4, 20, 0.0, 0.25, Color(0.34, 0.31, 0.28), true)
				for n in 12:
					var a := TAU * n / 12.0
					k.sphere("cast_iron", I.translated(tc + Vector3(cos(a) * 0.21, sin(a) * 0.21, z)), 0.012, 3, 6, 0.0, 0.8)
			rivets(k, tc + Vector3(0, 0.205, -0.28), tc + Vector3(0, 0.205, 0.28), 7, Vector3.UP, 0.012)
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				beam(k, "cast_iron", tc + Vector3(c.x * 0.12, -0.12, c.y * 0.2), Vector3(c.x * 0.2, 0.0, 0.15 + c.y * 0.26), 0.022, 6, GASIFIER)
				k.box("cast_iron", I.translated(Vector3(c.x * 0.2, 0.01, 0.15 + c.y * 0.26)), Vector3(0.08, 0.02, 0.08), GASIFIER)
			# The pump: a brass collar, a steel rod and the wooden T-handle.
			var pump := tc + Vector3(0, 0.2, 0.18)
			k.cylinder("gold", I.translated(pump), 0.045, 0.04, 0.06, 12, true, 0.0, 1, BRASS)
			beam(k, "metal", pump + Vector3(0, 0.06, 0), pump + Vector3(0, 0.32, 0), 0.018, 8)
			k.cylinder("gold", I.translated(pump + Vector3(0, 0.06, 0)), 0.03, 0.03, 0.03, 10, true, 0.0, 1, BRASS)
			beam(k, "planks", pump + Vector3(-0.13, 0.33, 0), pump + Vector3(0.13, 0.33, 0), 0.028, 8, Color(0.75, 0.45, 0.3))
			# The valve with its handwheel.
			var v := tc + Vector3(0, 0.2, -0.05)
			k.cylinder("gold", I.translated(v), 0.035, 0.03, 0.07, 10, true, 0.0, 1, BRASS)
			k.cylinder("gold", I.translated(v + Vector3(0, 0.07, 0)), 0.012, 0.012, 0.05, 6, true, 0.0, 1, BRASS)
			k.cylinder("gold", I.translated(v + Vector3(0, 0.12, 0)), 0.06, 0.06, 0.012, 14, false, 0.0, 1, BRASS)
			for a in 4:
				var b := Basis(Vector3.UP, TAU * a / 4.0)
				k.box("gold", Transform3D(b, v + b * Vector3(0, 0.126, 0.03)), Vector3(0.008, 0.008, 0.06), BRASS)
			# Feed hose round to the nozzle, its brass pipe and the vented shroud.
			beam(k, "gold", v + Vector3(0, 0.03, -0.03), Vector3(0, 0.55, -0.2), 0.016, 8, BRASS)
			beam(k, "rubber", tc + Vector3(0.1, 0.17, -0.1), Vector3(0.06, 0.55, -0.2), 0.016, 6)
			k.box("gold", I.translated(Vector3(0, 0.55, -0.2)), Vector3(0.07, 0.07, 0.06), BRASS)
			beam(k, "gold", Vector3(0, 0.55, -0.2), Vector3(0, 0.55, -0.42), 0.04, 14, BRASS)
			for n in 4:
				for a in 6:
					var t := TAU * a / 6.0
					k.box("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), t), Vector3(0, 0.55, -0.26 - n * 0.04) + Vector3(-sin(t), cos(t), 0) * 0.039), Vector3(0.012, 0.004, 0.012))
			beam(k, "gold", Vector3(0, 0.55, -0.41), Vector3(0, 0.55, -0.43), 0.045, 14, BRASS.darkened(0.1))
			beam(k, "gold", Vector3(0, 0.55, -0.2), Vector3(0, 0.3, -0.15), 0.014, 6, BRASS)
		"pw_alarm_bell":
			# A red gong on a cast backplate, with its striker under it: a copper coil on an
			# iron frame, a brass hammer arm up the right side.
			k.box("painted", I.translated(Vector3(0, -0.06, 0.012)), Vector3(0.2, 0.4, 0.024), Color(0.2, 0.2, 0.21))
			for y in [0.1, -0.22]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, y, 0.024)), 0.012, 0.012, 0.006, 8)
			beam(k, "metal_dark", Vector3(0, 0.02, 0.02), Vector3(0, 0.02, 0.06), 0.02, 10)
			k.sphere("machine_paint", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.06)), 0.15, 7, 22, 0.0, 0.55, Color(0.7, 0.1, 0.07), true)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.02, 0.135)), 0.02, 0.02, 0.012, 10, true, 0.0, 1, BRASS)
			k.box("metal_dark", I.translated(Vector3(0, -0.18, 0.05)), Vector3(0.14, 0.03, 0.08))
			for x in [-0.03, 0.03]:
				k.cylinder("painted", I.translated(Vector3(x, -0.165, 0.06)), 0.024, 0.024, 0.07, 14, true, 0.0, 1, COPPER)
			k.box("metal_dark", I.translated(Vector3(0, -0.085, 0.05)), Vector3(0.12, 0.02, 0.06))
			beam(k, "gold", Vector3(0.06, -0.09, 0.08), Vector3(0.13, 0.12, 0.12), 0.01, 6, BRASS)
			k.box("gold", I.translated(Vector3(0.06, -0.22, 0.05)), Vector3(0.03, 0.04, 0.04), BRASS)
		"pw_searchlight":
			# A tripod of steel legs and a turntable; the yoke and the drum are parts.
			for a in 3:
				var b := Basis(Vector3.UP, TAU * a / 3.0)
				beam(k, "cast_iron", b * Vector3(0, 0, 0.65), Vector3(0, 1.15, 0), 0.03, 6, GASIFIER)
			k.cylinder("cast_iron", I.translated(Vector3(0, 1.15, 0)), 0.16, 0.16, 0.12, 16, true, 0.0, 1, GASIFIER)
			k.box("cast_iron", I.translated(Vector3(0, 0.45, 0.15)), Vector3(0.2, 0.22, 0.14), GASIFIER)
		"pw_belt":
			# A 1 m conveyor: two painted steel side channels on four legs, idler rollers
			# between them under a ribbed rubber belt (top run and return run), an end drum
			# at each end (the out end's drum is a part that turns) and the drive motor
			# and gearbox hung on the side.
			for x in [-0.33, 0.33]:
				k.box("machine_paint", I.translated(Vector3(x, 0.19, 0)), Vector3(0.03, 0.09, 1.0), SAFETY_GREY)
				k.box("machine_paint", I.translated(Vector3(x * 0.97, 0.235, 0)), Vector3(0.05, 0.012, 1.0), SAFETY_GREY.darkened(0.1))
				for z in [-0.42, 0.42]:
					beam(k, "metal_dark", Vector3(x, 0.0, z), Vector3(x, 0.15, z), 0.02)
					k.box("metal_dark", I.translated(Vector3(x, 0.005, z)), Vector3(0.08, 0.01, 0.08))
				beam(k, "metal_dark", Vector3(x, 0.03, -0.42), Vector3(x, 0.14, 0.0), 0.012)
			for n in 4:
				beam(k, "metal", Vector3(-0.31, 0.185, -0.3 + n * 0.2), Vector3(0.31, 0.185, -0.3 + n * 0.2), 0.022, 10)
			beam(k, "metal", Vector3(-0.31, 0.19, -0.46), Vector3(0.31, 0.19, -0.46), 0.035, 12)
			k.box("rubber", I.translated(Vector3(0, 0.218, 0)), Vector3(0.56, 0.01, 0.96))
			for n in 16:
				k.box("rubber", I.translated(Vector3(0, 0.225, -0.45 + n * 0.06)), Vector3(0.54, 0.006, 0.012))
			k.box("rubber", I.translated(Vector3(0, 0.155, 0)), Vector3(0.56, 0.008, 0.96))
			# The motor: a ribbed green can on a gearbox at the out end.
			beam(k, "machine_paint", Vector3(0.36, 0.12, 0.38), Vector3(0.56, 0.12, 0.38), 0.065, 14, ENGINE_GREEN)
			for n in 5:
				beam(k, "machine_paint", Vector3(0.38 + n * 0.035, 0.12, 0.38), Vector3(0.39 + n * 0.035, 0.12, 0.38), 0.072, 14, ENGINE_GREEN.darkened(0.1))
			k.box("machine_paint", I.translated(Vector3(0.39, 0.19, 0.44)), Vector3(0.08, 0.12, 0.12), SAFETY_GREY.darkened(0.2))
		"pw_hopper":
			# A galvanized steel funnel on four angle-iron legs, riveted at the seams, its
			# spout out the +z side.
			var galv := Color(0.68, 0.7, 0.69)
			for x in [-0.36, 0.36]:
				for z in [-0.36, 0.36]:
					k.box("painted", I.translated(Vector3(x, 0.45, z)), Vector3(0.06, 0.9, 0.06), galv.darkened(0.12))
					k.box("painted", I.translated(Vector3(x, 0.015, z)), Vector3(0.12, 0.03, 0.12), galv.darkened(0.2))
			k.cylinder("painted", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.45, 0)), 0.16, 0.54, 0.5, 4, false, 0.0, 1, galv)
			k.cylinder("painted", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.93, 0)), 0.54, 0.55, 0.04, 4, false, 0.0, 1, galv.darkened(0.08))
			for sd in [-1.0, 1.0]:
				rivets(k, Vector3(-0.32, 0.92, sd * 0.38), Vector3(0.32, 0.92, sd * 0.38), 5, Vector3(0, 0.3, sd), 0.012)
				rivets(k, Vector3(sd * 0.38, 0.92, -0.32), Vector3(sd * 0.38, 0.92, 0.32), 5, Vector3(sd, 0.3, 0), 0.012)
			k.box("painted", I.translated(Vector3(0, 0.42, 0)), Vector3(0.22, 0.1, 0.22), galv.darkened(0.15))
			beam(k, "painted", Vector3(0, 0.42, 0.08), Vector3(0, 0.3, 0.4), 0.07, 12, galv)
			beam(k, "painted", Vector3(0, 0.31, 0.37), Vector3(0, 0.29, 0.43), 0.08, 12, galv.darkened(0.15))
		"pw_robot_arm":
			# A bolted cast foot, a slewing ring and a motor drum; the arm is a part that
			# swings round on top.
			k.cylinder("metal_dark", I, 0.26, 0.28, 0.06, 20)
			for n in 8:
				var a := TAU * n / 8.0
				k.cylinder("metal", I.translated(Vector3(cos(a) * 0.23, 0.06, sin(a) * 0.23)), 0.015, 0.015, 0.02, 6)
			k.cylinder("machine_paint", I.translated(Vector3(0, 0.06, 0)), 0.17, 0.19, 0.24, 20, true, 0.0, 1, ARM_ORANGE)
			k.cylinder("metal_dark", I.translated(Vector3(0, 0.3, 0)), 0.2, 0.2, 0.05, 20)
			for n in 20:
				var a := TAU * n / 20.0
				k.box("metal_dark", Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.2, 0.325, sin(a) * 0.2)), Vector3(0.02, 0.04, 0.03))
			k.cylinder("machine_paint", I.translated(Vector3(0, 0.35, 0)), 0.15, 0.15, 0.13, 18, true, 0.0, 1, ARM_ORANGE)
			beam(k, "machine_paint", Vector3(0, 0.16, -0.18), Vector3(0, 0.16, -0.3), 0.07, 12, SAFETY_GREY)
		"pw_auto_miner":
			# A skid-mounted drill rig: a steel skid, a small grey engine house at the back
			# with its exhaust, the green drive motor and gearbox in the middle, and a steel
			# A-frame whose boom carries the auger out front (-z) at the rock. The bit is a
			# part that turns.
			for x in [-0.42, 0.42]:
				k.box("planks", I.translated(Vector3(x, 0.06, 0)), Vector3(0.14, 0.12, 1.5), WEATHERED)
				k.box("metal_dark", I.translated(Vector3(x, 0.13, 0)), Vector3(0.12, 0.03, 1.5))
			for z in [-0.62, 0.0, 0.62]:
				k.box("planks", I.translated(Vector3(0, 0.17, z)), Vector3(1.0, 0.08, 0.12), WEATHERED)
			# The engine house: grey riveted sheet with two windows and a stack.
			k.box("painted", I.translated(Vector3(0, 0.5, 0.48)), Vector3(0.62, 0.6, 0.44), BOX_STEEL.lightened(0.05))
			k.box("painted", I.translated(Vector3(0, 0.82, 0.48)), Vector3(0.66, 0.04, 0.48), BOX_STEEL.darkened(0.1))
			for x in [-0.14, 0.14]:
				k.box("metal_dark", I.translated(Vector3(x, 0.58, 0.255)), Vector3(0.14, 0.16, 0.01))
			rivets(k, Vector3(-0.3, 0.24, 0.255), Vector3(0.3, 0.24, 0.255), 6, Vector3(0, 0, -1), 0.01)
			k.cylinder("metal", I.translated(Vector3(-0.18, 0.84, 0.55)), 0.1, 0.1, 0.18, 12)
			k.cylinder("metal", I.translated(Vector3(-0.18, 1.02, 0.55)), 0.11, 0.06, 0.04, 12)
			beam(k, "metal", Vector3(0.2, 0.84, 0.55), Vector3(0.2, 1.02, 0.55), 0.03, 8)
			# The green drive motor, its fins, and the gearbox it turns.
			beam(k, "machine_paint", Vector3(-0.28, 0.42, 0.0), Vector3(0.12, 0.42, 0.0), 0.15, 16, Color(0.24, 0.46, 0.3))
			for n in 5:
				beam(k, "machine_paint", Vector3(-0.22 + n * 0.07, 0.42, 0), Vector3(-0.205 + n * 0.07, 0.42, 0), 0.165, 16, Color(0.2, 0.38, 0.25))
			k.box("metal_dark", I.translated(Vector3(-0.08, 0.25, 0)), Vector3(0.36, 0.06, 0.3))
			k.box("cast_iron", I.translated(Vector3(0.25, 0.4, 0.0)), Vector3(0.2, 0.3, 0.3), GASIFIER)
			beam(k, "metal", Vector3(0.12, 0.42, 0), Vector3(0.15, 0.42, 0), 0.05, 8)
			beam(k, "rubber", Vector3(-0.28, 0.5, 0.05), Vector3(-0.28, 0.6, 0.26), 0.02, 6)
			# The A-frame: two legs up from the skid, braced, the boom hung from its top
			# with a stay, ending at the auger's gearbox.
			for x in [-0.32, 0.32]:
				beam(k, "painted", Vector3(x, 0.2, -0.05), Vector3(x * 0.2, 1.6, -0.25), 0.03, 6, BOX_STEEL)
				beam(k, "painted", Vector3(x, 0.2, -0.62), Vector3(x * 0.2, 1.6, -0.25), 0.03, 6, BOX_STEEL)
				beam(k, "painted", Vector3(x * 0.8, 0.7, -0.2), Vector3(x * 0.8, 0.7, -0.5), 0.015, 6, BOX_STEEL)
			k.box("metal_dark", I.translated(Vector3(0, 1.6, -0.25)), Vector3(0.16, 0.08, 0.12))
			beam(k, "metal_dark", Vector3(0, 1.6, -0.25), Vector3(0, 0.95, -0.55), 0.008, 4)
			beam(k, "metal", Vector3(0.2, 0.45, 0.0), Vector3(0, 1.55, -0.25), 0.006, 4)
			k.box("painted", I.translated(Vector3(0, 0.95, -0.46)), Vector3(0.22, 0.22, 0.24), BOX_STEEL.darkened(0.1))
			beam(k, "metal_dark", Vector3(0, 0.95, -0.58), Vector3(0, 0.95, -0.62), 0.09, 12)
			beam(k, "painted", Vector3(0, 0.84, -0.4), Vector3(0, 0.2, -0.2), 0.03, 6, BOX_STEEL)
			beam(k, "metal", Vector3(0.25, 0.42, 0), Vector3(0.05, 0.86, -0.4), 0.02, 6)
		"pw_quarry":
			# A steel derrick braced over a rubble-ringed pit: a crown sheave at the top,
			# the hoist cable down to a swivel and the kelly bar, a rotary table and
			# gearbox at its foot, and the winch house with its drum and motor. The auger
			# that bores into the pit is a part that turns.
			for x in [-0.8, 0.8]:
				for z in [-0.8, 0.8]:
					beam(k, "machine_paint", Vector3(x, 0, z), Vector3(x * 0.25, 2.6, z * 0.25), 0.045, 6, DERRICK_RED)
					k.box("metal_dark", I.translated(Vector3(x, 0.02, z)), Vector3(0.2, 0.04, 0.2))
			for y in [0.8, 1.6, 2.2]:
				var w: float = 0.8 - float(y) * 0.21
				for e in [[Vector3(-w, y, -w), Vector3(w, y, -w)], [Vector3(w, y, -w), Vector3(w, y, w)], [Vector3(w, y, w), Vector3(-w, y, w)], [Vector3(-w, y, w), Vector3(-w, y, -w)]]:
					beam(k, "machine_paint", e[0], e[1], 0.025, 6, DERRICK_RED)
			for e in [[Vector3(-0.8, 0, -0.8), Vector3(0.63, 0.8, -0.63)], [Vector3(0.8, 0, 0.8), Vector3(-0.63, 0.8, 0.63)]]:
				beam(k, "machine_paint", e[0], e[1], 0.018, 6, DERRICK_RED)
			k.box("metal_dark", I.translated(Vector3(0, 2.65, 0)), Vector3(0.5, 0.1, 0.5))
			beam(k, "metal", Vector3(-0.04, 2.8, 0), Vector3(0.04, 2.8, 0), 0.14, 16)
			beam(k, "metal_dark", Vector3(0, 2.7, 0), Vector3(0, 2.8, 0), 0.03)
			# The hoist cable from the winch drum up over the sheave and down to the swivel.
			beam(k, "rubber", Vector3(0.5, 0.75, 0.0), Vector3(0.0, 2.94, 0.0), 0.008, 4)
			beam(k, "rubber", Vector3(0.0, 2.66, 0.0), Vector3(0.0, 2.1, 0.0), 0.008, 4)
			k.cylinder("machine_paint", I.translated(Vector3(0, 1.9, 0)), 0.07, 0.07, 0.2, 10, true, 0.0, 1, SAFETY_GREY)
			# The rotary table and its gearbox at the foot of the kelly.
			k.box("machine_paint", I.translated(Vector3(0, 1.08, 0)), Vector3(0.44, 0.16, 0.44), SAFETY_GREY)
			k.cylinder("metal_dark", I.translated(Vector3(0, 1.16, 0)), 0.16, 0.16, 0.04, 16)
			for x in [-0.34, 0.34]:
				beam(k, "metal_dark", Vector3(x, 1.08, 0), Vector3(x * 2.2, 1.0, 0), 0.03)
			# The winch house: a green box with louvres, a drum and the motor on top.
			k.box("machine_paint", I.translated(Vector3(1.05, 0.4, 0.0)), Vector3(0.5, 0.8, 0.7), ENGINE_GREEN)
			for n in 5:
				k.box("metal_dark", I.translated(Vector3(1.05, 0.25 + n * 0.1, -0.355)), Vector3(0.36, 0.02, 0.01))
			beam(k, "metal_dark", Vector3(0.62, 0.75, -0.2), Vector3(0.62, 0.75, 0.2), 0.11, 14)
			for z in [-0.22, 0.2]:
				beam(k, "metal", Vector3(0.62, 0.75, z), Vector3(0.62, 0.75, z + 0.02), 0.16, 14)
			beam(k, "machine_paint", Vector3(1.05, 0.88, -0.2), Vector3(1.05, 0.88, 0.2), 0.1, 14, ENGINE_GREEN.darkened(0.15))
			# The pit: a ring of broken stone round the hole the auger bores.
			k.cylinder("metal_dark", I.translated(Vector3(0, -0.04, 0)), 0.34, 0.34, 0.05, 18)
			for n in 14:
				var a := TAU * n / 14.0 + 0.2
				var rr := 0.42 + 0.06 * float((n * 5) % 3)
				k.sphere("cobble", I.translated(Vector3(cos(a) * rr, 0.02, sin(a) * rr)), 0.07 + 0.02 * float(n % 3), 4, 6, 0.3, 0.6)
		"pw_furnace":
			# A brick-lined furnace in a riveted steel frame: brick shows between the
			# corner angles and straps, a heavy riveted door with a latch bar on the
			# front (-z), a feed hopper on legs on top and the junction box on the right
			# with its cable; the heat is inside (nothing glows).
			var brick := Color(0.6, 0.28, 0.15)
			k.box("painted", I.translated(Vector3(0, 0.62, 0)), Vector3(1.12, 1.04, 1.02), brick)
			# Mortar courses on the sides and front.
			for n in 9:
				var y := 0.18 + n * 0.11
				k.box("painted", I.translated(Vector3(0, y, 0)), Vector3(1.125, 0.012, 1.025), Color(0.42, 0.36, 0.32))
			for n in 10:
				var y := 0.24 + n * 0.11
				if y > 1.1:
					break
				for x in [-0.3, 0.0, 0.3]:
					var dx := 0.15 if n % 2 == 0 else 0.0
					k.box("painted", I.translated(Vector3(x + dx, y, 0)), Vector3(0.012, 0.1, 1.025), Color(0.42, 0.36, 0.32))
					k.box("painted", I.translated(Vector3(0, y, x + dx)), Vector3(1.125, 0.1, 0.012), Color(0.42, 0.36, 0.32))
			# Steel corner angles, top and bottom frames, middle straps, all riveted.
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				k.box("painted", I.translated(Vector3(c.x * 0.55, 0.62, c.y * 0.5)), Vector3(0.1, 1.24, 0.1), BOX_STEEL)
				k.box("metal_dark", I.translated(Vector3(c.x * 0.55, 0.03, c.y * 0.5)), Vector3(0.16, 0.06, 0.16))
			for y in [0.1, 1.14]:
				k.box("painted", I.translated(Vector3(0, y, 0)), Vector3(1.2, 0.1, 1.1), BOX_STEEL.darkened(0.08))
				rivets(k, Vector3(-0.55, y, -0.555), Vector3(0.55, y, -0.555), 9, Vector3(0, 0, -1), 0.014)
				rivets(k, Vector3(0.605, y, -0.5), Vector3(0.605, y, 0.5), 8, Vector3(1, 0, 0), 0.014)
			k.box("painted", I.translated(Vector3(0.605, 0.62, 0)), Vector3(0.02, 0.94, 0.08), BOX_STEEL)
			rivets(k, Vector3(-0.605, 0.2, -0.5), Vector3(-0.605, 1.05, -0.5), 6, Vector3(-1, 0, 0), 0.014)
			rivets(k, Vector3(-0.55, 0.2, -0.555), Vector3(-0.55, 1.05, -0.555), 6, Vector3(0, 0, -1), 0.014)
			rivets(k, Vector3(0.55, 0.2, -0.555), Vector3(0.55, 1.05, -0.555), 6, Vector3(0, 0, -1), 0.014)
			# The front plate and the heavy door with hinges and a latch bar.
			k.box("painted", I.translated(Vector3(0, 0.62, -0.515)), Vector3(0.9, 0.94, 0.02), BOX_STEEL.darkened(0.05))
			k.box("cast_iron", I.translated(Vector3(-0.02, 0.6, -0.535)), Vector3(0.6, 0.62, 0.04), GASIFIER.darkened(0.05))
			rivets(k, Vector3(-0.3, 0.9, -0.56), Vector3(0.26, 0.9, -0.56), 6, Vector3(0, 0, -1), 0.012)
			rivets(k, Vector3(-0.3, 0.3, -0.56), Vector3(0.26, 0.3, -0.56), 6, Vector3(0, 0, -1), 0.012)
			for y in [0.42, 0.78]:
				k.box("metal_dark", I.translated(Vector3(-0.34, y, -0.56)), Vector3(0.12, 0.06, 0.03))
			beam(k, "metal_dark", Vector3(0.16, 0.5, -0.56), Vector3(0.16, 0.5, -0.6), 0.03, 8)
			beam(k, "metal", Vector3(0.16, 0.5, -0.6), Vector3(0.36, 0.34, -0.6), 0.02, 8)
			beam(k, "rubber", Vector3(0.3, 0.38, -0.6), Vector3(0.4, 0.3, -0.6), 0.03, 8)
			# The feed hopper on four legs on the top.
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				beam(k, "metal_dark", Vector3(c.x * 0.2, 1.19, c.y * 0.15), Vector3(c.x * 0.2, 1.36, c.y * 0.15), 0.02, 6)
			k.cylinder("metal", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.32, 0)), 0.16, 0.36, 0.3, 4, false)
			k.cylinder("metal", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.62, 0)), 0.36, 0.37, 0.03, 4, false)
			# The junction box on the right side, a cable looping down from it.
			k.box("painted", I.translated(Vector3(0.66, 0.78, -0.15)), Vector3(0.1, 0.32, 0.26), BOX_STEEL.lightened(0.05))
			k.box("painted", I.translated(Vector3(0.715, 0.78, -0.15)), Vector3(0.01, 0.28, 0.22), BOX_STEEL.darkened(0.08))
			beam(k, "rubber", Vector3(0.68, 0.62, -0.25), Vector3(0.7, 0.4, -0.3), 0.02, 6)
			beam(k, "rubber", Vector3(0.7, 0.4, -0.3), Vector3(0.66, 0.3, -0.18), 0.02, 6)
			beam(k, "rubber", Vector3(0.66, 0.94, -0.15), Vector3(0.62, 1.5, 0.0), 0.02, 6)
		"pw_sawmill":
			# A timber trestle bench bound in iron: a heavy plank top with the blade slot,
			# braced legs, the electric motor slung under the front with a belt up to the
			# arbor. The big circular blade is a part.
			k.box("planks", I.translated(Vector3(0, 0.74, 0)), Vector3(0.9, 0.08, 1.8), WEATHERED)
			for x in [-0.4, 0.4]:
				k.box("planks", I.translated(Vector3(x, 0.66, 0)), Vector3(0.1, 0.1, 1.76), WEATHERED.darkened(0.1))
				for z in [-0.78, 0.78]:
					timber(k, Vector3(x, 0, z), Vector3(x, 0.7, z), 0.1)
					k.box("metal_dark", I.translated(Vector3(x, 0.64, z)), Vector3(0.12, 0.08, 0.12))
				timber(k, Vector3(x, 0.18, -0.78), Vector3(x, 0.18, 0.78), 0.07)
				timber(k, Vector3(x, 0.2, -0.7), Vector3(x, 0.6, 0.0), 0.05)
			for z in [-0.78, 0.78]:
				timber(k, Vector3(-0.4, 0.4, z), Vector3(0.4, 0.4, z), 0.06)
			# The arbor bearings under the slot.
			for x in [-0.1, 0.1]:
				k.box("cast_iron", I.translated(Vector3(x, 0.6, 0)), Vector3(0.06, 0.12, 0.14), GASIFIER.lightened(0.1))
			# The motor: a grey ribbed drum on a bracket, its pulley and belt.
			var m := Vector3(0.05, 0.38, -0.35)
			k.box("metal_dark", I.translated(m + Vector3(0, -0.16, 0)), Vector3(0.3, 0.04, 0.24))
			beam(k, "painted", m + Vector3(-0.15, 0, 0), m + Vector3(0.15, 0, 0), 0.13, 16, BOX_STEEL)
			for n in 5:
				beam(k, "painted", m + Vector3(-0.11 + n * 0.055, 0, 0), m + Vector3(-0.1 + n * 0.055, 0, 0), 0.14, 16, BOX_STEEL.darkened(0.12))
			beam(k, "metal_dark", m + Vector3(0.15, 0, 0), m + Vector3(0.24, 0, 0), 0.06, 12)
			beam(k, "rubber", m + Vector3(0.2, 0.05, 0), Vector3(0.2, 0.86, 0.0), 0.012, 4)
			beam(k, "rubber", m + Vector3(0.2, -0.05, 0.02), Vector3(0.2, 0.84, 0.05), 0.012, 4)
			k.box("painted", I.translated(m + Vector3(-0.05, 0.15, 0)), Vector3(0.1, 0.06, 0.1), BOX_STEEL.darkened(0.1))
		"pw_assembler":
			# A riveted steel machine on four feet: the lower cabinet with a gear on its
			# face, a glass case above showing the press column and its gears, an open
			# gear train up the left side, a galvanized feed hopper on top and the output
			# chute out to the right.
			for c in [Vector2(-0.55, -0.38), Vector2(0.55, -0.38), Vector2(-0.55, 0.38), Vector2(0.55, 0.38)]:
				k.box("metal_dark", I.translated(Vector3(c.x, 0.04, c.y)), Vector3(0.16, 0.08, 0.16))
			k.box("painted", I.translated(Vector3(0, 0.45, 0)), Vector3(1.2, 0.7, 0.86), BOX_STEEL)
			k.box("painted", I.translated(Vector3(0, 0.82, 0)), Vector3(1.24, 0.05, 0.9), BOX_STEEL.darkened(0.15))
			k.box("painted", I.translated(Vector3(0, 0.12, 0)), Vector3(1.24, 0.06, 0.9), BOX_STEEL.darkened(0.15))
			for x in [-0.6, 0.0, 0.6]:
				k.box("painted", I.translated(Vector3(x, 0.45, -0.435)), Vector3(0.05, 0.66, 0.01), BOX_STEEL.darkened(0.12))
			rivets(k, Vector3(-0.6, 0.78, -0.44), Vector3(0.6, 0.78, -0.44), 10, Vector3(0, 0, -1), 0.012)
			rivets(k, Vector3(-0.6, 0.16, -0.44), Vector3(0.6, 0.16, -0.44), 10, Vector3(0, 0, -1), 0.012)
			# The drive gear on the cabinet front.
			beam(k, "cast_iron", Vector3(-0.32, 0.45, -0.43), Vector3(-0.32, 0.45, -0.48), 0.16, 20, GASIFIER.darkened(0.1))
			for n in 16:
				var a := TAU * n / 16.0
				k.box("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(-0.32 - sin(a) * 0.165, 0.45 + cos(a) * 0.165, -0.455)), Vector3(0.03, 0.03, 0.05), GASIFIER.darkened(0.1))
			beam(k, "gold", Vector3(-0.32, 0.45, -0.48), Vector3(-0.32, 0.45, -0.51), 0.05, 12, BRASS)
			# The glass case: a dark steel frame, glazed, with the works inside.
			var cx := 0.15
			for p in [Vector2(-0.3, -0.32), Vector2(0.6, -0.32), Vector2(-0.3, 0.32), Vector2(0.6, 0.32)]:
				k.box("metal_dark", I.translated(Vector3(p.x, 1.2, p.y)), Vector3(0.04, 0.72, 0.04))
			for y in [0.86, 1.54]:
				for z in [-0.32, 0.32]:
					k.box("metal_dark", I.translated(Vector3(cx, y, z)), Vector3(0.94, 0.04, 0.04))
				for x in [-0.3, 0.6]:
					k.box("metal_dark", I.translated(Vector3(x, y, 0)), Vector3(0.04, 0.04, 0.68))
			k.box("painted", I.translated(Vector3(cx, 1.57, 0)), Vector3(0.96, 0.03, 0.7), BOX_STEEL)
			k.box("clear_glass", I.translated(Vector3(cx, 1.2, -0.32)), Vector3(0.88, 0.66, 0.005))
			k.box("clear_glass", I.translated(Vector3(0.6, 1.2, 0)), Vector3(0.005, 0.66, 0.6))
			k.box("clear_glass", I.translated(Vector3(-0.3, 1.2, 0)), Vector3(0.005, 0.66, 0.6))
			k.box("clear_glass", I.translated(Vector3(cx, 1.2, 0.32)), Vector3(0.88, 0.66, 0.005))
			# Inside: the press column, its head, a die plate and brass gears.
			beam(k, "metal", Vector3(cx, 0.86, 0.0), Vector3(cx, 1.54, 0.0), 0.05, 12)
			k.box("metal_dark", I.translated(Vector3(cx, 1.3, -0.02)), Vector3(0.22, 0.14, 0.2))
			beam(k, "metal", Vector3(cx, 1.23, -0.02), Vector3(cx, 1.05, -0.02), 0.035, 10)
			beam(k, "gold", Vector3(cx, 0.86, 0.0), Vector3(cx, 0.9, 0.0), 0.2, 20, BRASS)
			for g in [[Vector3(-0.12, 1.12, -0.05), 0.09], [Vector3(0.42, 1.2, -0.05), 0.11], [Vector3(0.42, 1.0, 0.1), 0.07]]:
				beam(k, "gold", g[0], g[0] + Vector3(0, 0, -0.03), g[1], 16, BRASS)
				beam(k, "metal_dark", g[0] + Vector3(0, 0, 0.01), g[0] + Vector3(0, 0, -0.04), 0.02, 8)
			# The open gear train up the left side.
			for g in [[Vector3(-0.5, 1.02, -0.2), 0.11], [Vector3(-0.5, 1.22, -0.05), 0.08], [Vector3(-0.5, 1.12, 0.15), 0.1], [Vector3(-0.48, 1.38, 0.1), 0.06]]:
				var c: Vector3 = g[0]
				var r: float = g[1]
				beam(k, "cast_iron", c, c + Vector3(-0.04, 0, 0), r, 18, GASIFIER.darkened(0.15))
				var teeth := int(r * 120)
				for n in teeth:
					var a := TAU * n / teeth
					k.box("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), a), c + Vector3(-0.02, cos(a) * r, sin(a) * r)), Vector3(0.04, 0.022, 0.022), GASIFIER.darkened(0.15))
				beam(k, "gold", c + Vector3(-0.04, 0, 0), c + Vector3(-0.06, 0, 0), r * 0.35, 10, BRASS)
				beam(k, "metal", c, c + Vector3(0.2, 0, 0), 0.015, 6)
			k.box("metal_dark", I.translated(Vector3(-0.38, 1.2, 0)), Vector3(0.04, 0.6, 0.6))
			# The feed hopper on legs over the left of the top.
			k.cylinder("metal", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(-0.42, 1.6, 0)), 0.08, 0.26, 0.22, 4, false)
			k.cylinder("metal", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(-0.42, 1.82, 0)), 0.26, 0.27, 0.03, 4, false)
			beam(k, "metal", Vector3(-0.42, 1.36, 0), Vector3(-0.42, 1.6, 0), 0.05, 8)
			# The output chute out to the right, a small tray at its lip.
			k.box("metal", Transform3D(Basis(Vector3(0, 0, 1), -0.12), Vector3(0.82, 1.0, -0.05)), Vector3(0.5, 0.04, 0.24))
			for z in [-0.17, 0.07]:
				k.box("metal", Transform3D(Basis(Vector3(0, 0, 1), -0.12), Vector3(0.82, 1.05, z)), Vector3(0.5, 0.08, 0.02))
			beam(k, "metal_dark", Vector3(0.62, 0.86, -0.05), Vector3(0.9, 0.92, -0.05), 0.025, 6)
			# The cable gland on top at the back.
			k.box("metal_dark", I.translated(Vector3(0, 1.6, 0.4)), Vector3(0.14, 0.1, 0.1))
		"pw_water_wheel":
			# An undershot wheel's frame: two heavy timber A-frames on sills, iron-strapped,
			# the axle bearings at their peaks, and the generator on the axle's end; the
			# wheel is a part that turns about x.
			for x in [-0.78, 0.78]:
				timber(k, Vector3(x, 0.06, -1.1), Vector3(x, 0.06, 1.1), 0.16)
				timber(k, Vector3(x, 0.1, -1.0), Vector3(x, 1.45, 0), 0.16)
				timber(k, Vector3(x, 0.1, 1.0), Vector3(x, 1.45, 0), 0.16)
				timber(k, Vector3(x, 0.55, -0.62), Vector3(x, 0.55, 0.62), 0.1)
				k.box("painted", I.translated(Vector3(x, 1.4, 0)), Vector3(0.2, 0.18, 0.24), BOX_STEEL.darkened(0.2))
				for z in [-0.62, 0.62]:
					k.box("metal_dark", I.translated(Vector3(x, 0.55, z)), Vector3(0.18, 0.14, 0.14))
			# The generator: a grey ribbed drum on a bracket off the right frame.
			k.box("planks", I.translated(Vector3(1.05, 1.15, 0)), Vector3(0.4, 0.06, 0.4), WEATHERED)
			timber(k, Vector3(0.86, 0.6, 0.0), Vector3(1.2, 1.12, 0.0), 0.08)
			beam(k, "metal_dark", Vector3(0.7, 1.4, 0), Vector3(0.92, 1.4, 0), 0.06, 10)
			beam(k, "painted", Vector3(0.9, 1.4, 0), Vector3(1.22, 1.4, 0), 0.2, 18, BOX_STEEL)
			for n in 4:
				beam(k, "painted", Vector3(0.95 + n * 0.07, 1.4, 0), Vector3(0.965 + n * 0.07, 1.4, 0), 0.215, 18, BOX_STEEL.darkened(0.15))
			beam(k, "painted", Vector3(1.22, 1.4, 0), Vector3(1.28, 1.4, 0), 0.12, 14, BOX_STEEL.darkened(0.2))
			k.box("painted", I.translated(Vector3(1.06, 1.66, 0)), Vector3(0.14, 0.1, 0.14), BOX_STEEL.darkened(0.1))
		"pw_steam":
			# A portable steam engine on a timber skid: the firebox at the back (+z) with
			# its door and pressure gauge, a riveted boiler barrel forward to the smokebox
			# and its stack, a steam dome with a brass safety valve and whistle, and on the
			# right side the engine: a steam cylinder, the slide bars and a big spoked
			# flywheel (a part) on the crankshaft, its crosshead (a part) running in the
			# bars, a ball governor on top and the dynamo it drives by belt.
			for x in [-0.42, 0.42]:
				k.box("planks", I.translated(Vector3(x, 0.06, 0)), Vector3(0.14, 0.12, 2.1))
			for z in [-0.8, 0.0, 0.8]:
				k.box("planks", I.translated(Vector3(0, 0.15, z)), Vector3(1.0, 0.06, 0.14))
			k.box("machine_paint", I.translated(Vector3(0, 0.6, 0.72)), Vector3(0.84, 0.9, 0.5), BOILER_BLACK)
			k.box("metal_dark", I.translated(Vector3(0, 0.42, 0.975)), Vector3(0.3, 0.26, 0.03))
			beam(k, "gold", Vector3(-0.1, 0.42, 1.0), Vector3(0.1, 0.42, 1.0), 0.012, 6, BRASS)
			k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.22, 0.85, 0.97)), 0.06, 0.06, 0.03, 14, true, 0.0, 1, BRASS)
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0.22, 0.85, 1.0)), 0.05, 0.05, 0.005, 14, true, 0.0, 1, ENAMEL)
			beam(k, "machine_paint", Vector3(0, 0.82, 0.5), Vector3(0, 0.82, -0.85), 0.4, 22, BOILER_GREEN)
			for z in [0.35, -0.1, -0.55]:
				beam(k, "gold", Vector3(0, 0.82, z), Vector3(0, 0.82, z - 0.04), 0.41, 22, BRASS)
			beam(k, "metal_dark", Vector3(0, 0.82, -0.85), Vector3(0, 0.82, -1.0), 0.42, 22)
			beam(k, "metal_dark", Vector3(0, 0.82, -1.0), Vector3(0, 0.82, -1.03), 0.3, 18)
			k.cylinder("metal_dark", I.translated(Vector3(0, 1.1, -0.9)), 0.12, 0.1, 1.3, 14)
			k.cylinder("metal_dark", I.translated(Vector3(0, 2.38, -0.9)), 0.14, 0.14, 0.06, 14)
			k.cylinder("machine_paint", I.translated(Vector3(0, 1.15, -0.15)), 0.14, 0.12, 0.2, 16, true, 0.0, 1, BOILER_GREEN)
			k.cylinder("gold", I.translated(Vector3(0, 1.35, -0.15)), 0.1, 0.06, 0.05, 14, true, 0.0, 1, BRASS)
			k.cylinder("gold", I.translated(Vector3(0.0, 1.18, 0.25)), 0.025, 0.02, 0.18, 8, true, 0.0, 1, BRASS)
			k.cylinder("gold", I.translated(Vector3(-0.15, 1.18, 0.25)), 0.02, 0.03, 0.14, 8, true, 0.0, 1, BRASS)
			# The engine, on the right side: cylinder forward, bars, crank at the back.
			beam(k, "machine_paint", Vector3(0.56, 0.95, -0.75), Vector3(0.56, 0.95, -0.4), 0.12, 16, BOILER_BLACK)
			for z in [-0.75, -0.4]:
				beam(k, "metal", Vector3(0.56, 0.95, z), Vector3(0.56, 0.95, z + (0.03 if z < -0.5 else -0.03)), 0.135, 16)
			k.box("machine_paint", I.translated(Vector3(0.45, 0.95, -0.58)), Vector3(0.12, 0.16, 0.3), BOILER_BLACK)
			for y in [0.9, 1.0]:
				beam(k, "metal", Vector3(0.56, y, -0.4), Vector3(0.56, y, 0.12), 0.012, 6)
			beam(k, "metal", Vector3(0.48, 0.95, 0.32), Vector3(0.82, 0.95, 0.32), 0.035, 10)
			k.box("metal_dark", I.translated(Vector3(0.52, 0.6, 0.32)), Vector3(0.08, 0.7, 0.1))
			# The governor: a spindle with two brass balls on the cylinder.
			beam(k, "metal", Vector3(0.56, 1.07, -0.58), Vector3(0.56, 1.3, -0.58), 0.01, 6)
			for x in [-0.07, 0.07]:
				beam(k, "metal", Vector3(0.56, 1.28, -0.58), Vector3(0.56 + x, 1.2, -0.58), 0.006, 4)
				k.sphere("gold", I.translated(Vector3(0.56 + x, 1.19, -0.58)), 0.03, 5, 8, 0.0, 1.0, BRASS)
			# The dynamo on the skid, belted to the flywheel.
			beam(k, "machine_paint", Vector3(0.2, 0.32, 0.32), Vector3(0.48, 0.32, 0.32), 0.12, 14, ENGINE_GREEN)
			beam(k, "rubber", Vector3(0.8, 0.95 + 0.5, 0.32), Vector3(0.5, 0.42, 0.32), 0.01, 4)
			beam(k, "rubber", Vector3(0.8, 0.95 - 0.5, 0.32), Vector3(0.5, 0.22, 0.32), 0.01, 4)
		"pw_lamp_ceiling":
			# A cast ceiling cup, a short steel stem, and a green enamel shade white inside;
			# the bulb is a part.
			k.cylinder("metal_dark", I.translated(Vector3(0, -0.04, 0)), 0.04, 0.07, 0.04, 16)
			k.cylinder("metal", I.translated(Vector3(0, -0.2, 0)), 0.012, 0.012, 0.17, 8)
			k.cylinder("gold", I.translated(Vector3(0, -0.28, 0)), 0.022, 0.026, 0.08, 10, true, 0.0, 1, BRASS)
			k.cylinder("machine_paint", I.translated(Vector3(0, -0.4, 0)), 0.25, 0.05, 0.13, 24, false, 0.0, 2, SHADE_GREEN)
			# Its white inside, facing in: it bounces the bulb's light down, and casts the
			# shadow that keeps the ceiling above in the shade's shadow.
			for n in 20:
				var a0 := TAU * n / 20.0
				var a1 := TAU * (n + 1) / 20.0
				var q := [Vector3(cos(a0) * 0.242, -0.398, sin(a0) * 0.242), Vector3(cos(a1) * 0.242, -0.398, sin(a1) * 0.242),
					Vector3(cos(a1) * 0.024, -0.262, sin(a1) * 0.024), Vector3(cos(a0) * 0.024, -0.262, sin(a0) * 0.024)]
				var mid: Vector3 = (q[0] + q[2]) * 0.5
				if ((q[1] - q[0]) as Vector3).cross(q[2] - q[0]).dot(Vector3(mid.x, 0, mid.z)) > 0.0:
					q.reverse()
				k.quad("painted", I, q[0], q[1], q[2], q[3], Color(0.95, 0.94, 0.9))
			k.cylinder("painted", I.translated(Vector3(0, -0.405, 0)), 0.255, 0.255, 0.008, 24, false, 0.0, 1, ENAMEL)
		"pw_lamp_wall":
			# A bulkhead lamp flat on the wall: a thick oval cast backplate, an oval glass
			# (a part) under an iron cage of hoops and bars.
			k.sphere("painted", Transform3D(Basis().scaled(Vector3(1.0, 1.45, 0.35)), Vector3(0, 0, 0.0)), 0.11, 6, 18, 0.0, 1.0, Color(0.2, 0.2, 0.21), true)
			for y in [-0.13, 0.13]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, y, 0.025)), 0.012, 0.012, 0.008, 8)
			k.cylinder("metal_dark", Transform3D(Basis().scaled(Vector3(1.0, 1.0, 1.4)) * Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.03)), 0.09, 0.09, 0.02, 20)
			for n in 5:
				var t := -0.8 + n * 0.4
				var y := sin(t) * 0.12
				var r := cos(t) * 0.085
				for m in 12:
					var a0 := PI * m / 12.0
					var a1 := PI * (m + 1) / 12.0
					beam(k, "metal_dark", Vector3(cos(a0) * r, y, 0.04 + sin(a0) * r * 0.75), Vector3(cos(a1) * r, y, 0.04 + sin(a1) * r * 0.75), 0.005, 4)
			for x in [-0.03, 0.03]:
				for m in 10:
					var b0 := -PI * 0.5 + PI * m / 10.0
					var b1 := -PI * 0.5 + PI * (m + 1) / 10.0
					beam(k, "metal_dark", Vector3(x, sin(b0) * 0.125, 0.04 + cos(b0) * 0.065), Vector3(x, sin(b1) * 0.125, 0.04 + cos(b1) * 0.065), 0.006, 4)
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
				k.box("painted", I.translated(Vector3(x, 0.1, 0)), Vector3(0.01, 0.22, 0.026), COPPER)
			k.box("painted", I.translated(Vector3(0, 0.22, 0)), Vector3(0.1, 0.02, 0.02), COPPER.darkened(0.2))
			k.cylinder("painted", I.translated(Vector3(0, 0.22, 0)), 0.02, 0.016, 0.11, 10, true, 0.0, 1, Color(0.08, 0.07, 0.06))
			k.sphere("painted", I.translated(Vector3(0, 0.33, 0)), 0.022, 5, 10, 0.0, 1.0, Color(0.08, 0.07, 0.06))
		"lever_arm":
			# An iron arm with a turned wooden grip; it turns about its local x at the boss.
			k.box("metal_dark", I.translated(Vector3(0, 0.09, 0)), Vector3(0.024, 0.2, 0.016))
			k.sphere("painted", I.translated(Vector3(0, 0.21, 0)), 0.034, 6, 12, 0.0, 1.0, Color(0.06, 0.06, 0.06))
		"button_cap":
			# A red enamel mushroom cap (paint, not a light).
			k.cylinder("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, -0.01)), 0.03, 0.03, 0.03, 16, true, 0.0, 1, Color(0.66, 0.08, 0.06))
			k.sphere("painted", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0, 0.018)), 0.045, 5, 18, 0.0, 0.55, Color(0.72, 0.08, 0.06), true)
		"plate_top":
			# The chequer plate: an iron sheet with raised diamond treads.
			k.box("painted", I, Vector3(0.8, 0.02, 0.8), BOX_STEEL)
			for x in 8:
				for z in 8:
					var p := Vector3(-0.35 + x * 0.1, 0.012, -0.35 + z * 0.1)
					k.box("painted", Transform3D(Basis(Vector3.UP, PI * 0.25 if (x + z) % 2 == 0 else -PI * 0.25), p), Vector3(0.05, 0.005, 0.012), BOX_STEEL.lightened(0.1))
		"turret_head":
			# The yoke: a turntable and two cheeks the gun trunnions sit in.
			k.cylinder("cast_iron", I, 0.18, 0.18, 0.06, 18, true, 0.0, 1, GASIFIER.darkened(0.1))
			for x in [-0.17, 0.17]:
				k.box("cast_iron", I.translated(Vector3(x, 0.15, 0)), Vector3(0.05, 0.26, 0.18), GASIFIER)
				k.cylinder("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x + signf(x) * 0.05, 0.24, 0)), 0.04, 0.04, 0.03, 10)
			k.box("cast_iron", I.translated(Vector3(0, 0.05, 0.12)), Vector3(0.2, 0.12, 0.12), GASIFIER.darkened(0.15))
		"turret_gun":
			# A belt-fed machine gun, motor driven: the receiver, a perforated cooling
			# jacket round the barrel, the muzzle, and an olive ammunition box on the
			# right feeding a brass belt into the breech. Points along -z.
			k.box("cast_iron", I.translated(Vector3(0, 0.0, 0.12)), Vector3(0.14, 0.16, 0.42), GASIFIER.darkened(0.1))
			k.box("cast_iron", I.translated(Vector3(0, 0.1, 0.1)), Vector3(0.12, 0.04, 0.3), GASIFIER.darkened(0.2))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0, 0)), 0.035, 0.035, 0.36, 10, true, 0.0, 1, GASIFIER.darkened(0.2))
			beam(k, "cast_iron", Vector3(0, 0.0, -0.09), Vector3(0, 0.0, -0.66), 0.05, 14, GASIFIER.darkened(0.25))
			for n in 7:
				for a in 6:
					var t := TAU * a / 6.0
					k.box("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), t), Vector3(-sin(t), cos(t), 0) * 0.049 + Vector3(0, 0, -0.14 - n * 0.07)), Vector3(0.018, 0.006, 0.03))
			beam(k, "cast_iron", Vector3(0, 0.0, -0.66), Vector3(0, 0.0, -0.96), 0.018, 8, GASIFIER.darkened(0.3))
			beam(k, "cast_iron", Vector3(0, 0.0, -0.88), Vector3(0, 0.0, -0.96), 0.03, 10, GASIFIER.darkened(0.3))
			k.box("cast_iron", I.translated(Vector3(0, 0.06, -0.92)), Vector3(0.01, 0.05, 0.02), GASIFIER.darkened(0.3))
			# The ammunition box and its belt.
			k.box("machine_paint", I.translated(Vector3(0.22, 0.02, 0.08)), Vector3(0.14, 0.18, 0.24), Color(0.36, 0.38, 0.24))
			k.box("machine_paint", I.translated(Vector3(0.22, 0.115, 0.08)), Vector3(0.15, 0.015, 0.25), Color(0.3, 0.32, 0.2))
			for n in 6:
				var p := Vector3(0.15 - n * 0.016, 0.06 + n * 0.004, 0.02 + n * 0.005)
				k.cylinder("gold", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), p), 0.008, 0.006, 0.06, 6, true, 0.0, 1, BRASS)
		"heavy_head":
			# A riveted steel dome on a turret ring, a mantlet slot at the front.
			k.cylinder("painted", I, 0.5, 0.5, 0.1, 24, true, 0.0, 1, BOX_STEEL.darkened(0.15))
			k.cylinder("painted", I.translated(Vector3(0, 0.1, 0)), 0.48, 0.48, 0.2, 24, false, 0.0, 1, BOX_STEEL)
			k.sphere("painted", I.translated(Vector3(0, 0.3, 0)), 0.48, 6, 24, 0.0, 0.62, BOX_STEEL, true)
			for y in [0.12, 0.28]:
				for a in 18:
					var p := Basis(Vector3.UP, TAU * a / 18.0) * Vector3(0, y, 0.485)
					k.sphere("metal_dark", I.translated(p), 0.013, 3, 6, 0.0, 0.6)
			for a in 8:
				var b := Basis(Vector3.UP, TAU * a / 8.0)
				k.box("painted", Transform3D(b * Basis(Vector3(1, 0, 0), -0.75), b * Vector3(0, 0.46, 0.33)), Vector3(0.02, 0.012, 0.3), BOX_STEEL.darkened(0.15))
			k.cylinder("metal_dark", I.translated(Vector3(0.18, 0.56, 0.1)), 0.1, 0.1, 0.06, 14)
			k.box("painted", I.translated(Vector3(0, 0.3, -0.45)), Vector3(0.46, 0.2, 0.1), BOX_STEEL.darkened(0.1))
		"heavy_gun":
			# Twin heavy barrels on one cradle, out through the mantlet. Points along -z.
			k.box("metal_dark", I.translated(Vector3(0, 0, -0.3)), Vector3(0.4, 0.16, 0.3))
			for x in [-0.12, 0.12]:
				beam(k, "painted", Vector3(x, 0, -0.4), Vector3(x, 0, -1.0), 0.06, 14, BOX_STEEL.darkened(0.15))
				beam(k, "painted", Vector3(x, 0, -0.42), Vector3(x, 0, -0.52), 0.075, 14, BOX_STEEL.darkened(0.25))
				beam(k, "metal_dark", Vector3(x, 0, -1.0), Vector3(x, 0, -1.3), 0.035, 10)
				beam(k, "metal_dark", Vector3(x, 0, -1.22), Vector3(x, 0, -1.34), 0.05, 12)
		"spikes":
			# A bed of iron spikes on a plate; it rises through the grate.
			k.box("cast_iron", I, Vector3(0.96, 0.03, 0.96), GASIFIER.darkened(0.2))
			for x in 5:
				for z in 5:
					var p := Vector3(-0.38 + x * 0.19, 0.0, -0.38 + z * 0.19)
					k.cylinder("painted", I.translated(p), 0.026, 0.002, 0.3, 8, false, 0.0, 1, Color(0.7, 0.71, 0.7))
					k.cylinder("painted", I.translated(p), 0.034, 0.03, 0.03, 8, true, 0.0, 1, RUST_FRAME)
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
			# A shoulder housing on the turntable, an upper and a fore link with round
			# joint housings and a hydraulic ram, a wrist and a two-finger gripper,
			# reaching out along -z.
			k.box("machine_paint", I.translated(Vector3(0, 0.1, 0)), Vector3(0.2, 0.2, 0.22), ARM_ORANGE)
			beam(k, "metal_dark", Vector3(-0.13, 0.16, 0), Vector3(0.13, 0.16, 0), 0.07, 14)
			for x in [-0.07, 0.07]:
				beam(k, "machine_paint", Vector3(x, 0.16, 0), Vector3(x, 0.52, -0.22), 0.032, 8, ARM_ORANGE)
			beam(k, "metal", Vector3(0, 0.08, -0.1), Vector3(0, 0.36, -0.15), 0.018, 8)
			beam(k, "metal_dark", Vector3(-0.1, 0.52, -0.22), Vector3(0.1, 0.52, -0.22), 0.055, 12)
			beam(k, "machine_paint", Vector3(0, 0.52, -0.22), Vector3(0, 0.3, -0.6), 0.04, 10, ARM_ORANGE)
			beam(k, "metal_dark", Vector3(0, 0.3, -0.6), Vector3(0, 0.22, -0.62), 0.045, 10)
			k.box("metal_dark", I.translated(Vector3(0, 0.19, -0.63)), Vector3(0.12, 0.04, 0.06))
			for x in [-0.045, 0.045]:
				k.box("metal", I.translated(Vector3(x, 0.13, -0.63)), Vector3(0.015, 0.09, 0.04))
		"drill_bit":
			# A spiral rock drill along -z.
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0, 0)), 0.07, 0.07, 0.1, 10, true, 0.0, 1, GASIFIER)
			for n in 8:
				var b := Basis(Vector3(0, 0, 1), n * 0.8)
				k.box("cast_iron", Transform3D(b, Vector3(0, 0, -0.12 - n * 0.06)), Vector3(0.16 - n * 0.012, 0.02, 0.04), GASIFIER.lightened(0.08))
			k.cylinder("cast_iron", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0, -0.1)), 0.025, 0.004, 0.5, 8, true, 0.0, 1, GASIFIER.lightened(0.08))
		"quarry_bit":
			# The kelly bar from the rotary table down into the pit, and the auger at its
			# foot: a spiral of flights round the shaft with carbide teeth on the cutter.
			k.cylinder("metal_dark", I.translated(Vector3(0, -0.25, 0)), 0.045, 0.045, 1.8, 6)
			for n in 22:
				var b := Basis(Vector3.UP, n * 0.6)
				var y := -0.25 + n * 0.022
				k.box("metal", Transform3D(b, Vector3(0, y, 0) + b * Vector3(0.14, 0, 0)), Vector3(0.22, 0.012, 0.07))
			k.cylinder("metal_dark", I.translated(Vector3(0, -0.3, 0)), 0.24, 0.24, 0.05, 16)
			for n in 6:
				var b := Basis(Vector3.UP, n * TAU / 6.0)
				k.box("metal", Transform3D(b, b * Vector3(0.21, -0.32, 0)), Vector3(0.05, 0.04, 0.04))
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
			# A heavy cast flywheel turning about x: rim, six curved spokes, a hub and
			# the crank disc with its pin.
			beam(k, "machine_paint", Vector3(0.24, 0, 0), Vector3(0.34, 0, 0), 0.5, 28, DERRICK_RED)
			beam(k, "metal_dark", Vector3(0.235, 0, 0), Vector3(0.345, 0, 0), 0.44, 28)
			for n in 6:
				var a := TAU * n / 6.0
				k.box("machine_paint", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0.29, cos(a), sin(a)) * Vector3(1, 0.23, 0.23)), Vector3(0.05, 0.42, 0.06), DERRICK_RED)
			beam(k, "machine_paint", Vector3(0.22, 0, 0), Vector3(0.36, 0, 0), 0.09, 14, DERRICK_RED.darkened(0.2))
			beam(k, "metal_dark", Vector3(-0.08, 0, 0), Vector3(-0.04, 0, 0), 0.16, 16)
			beam(k, "metal", Vector3(-0.08, 0, 0.12), Vector3(-0.14, 0, 0.12), 0.025, 8)
		"belt_drum":
			# A conveyor's end drum, turning about x, with lagging strips that show it turn.
			beam(k, "metal", Vector3(-0.31, 0, 0), Vector3(0.31, 0, 0), 0.035, 12)
			for n in 4:
				var a := TAU * n / 4.0
				k.box("rubber", Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(0, cos(a), sin(a)) * 0.036), Vector3(0.6, 0.006, 0.012))
		"crosshead":
			# The crosshead and its connecting rod, sliding in the engine's bars along z.
			k.box("metal", I, Vector3(0.06, 0.08, 0.1))
			beam(k, "metal", Vector3(0, 0, -0.05), Vector3(0, 0, -0.3), 0.018, 8)
			beam(k, "metal_dark", Vector3(0, 0, 0.05), Vector3(0, 0, 0.3), 0.022, 8)
		"bulb":
			# A pear-shaped glass bulb, its neck up.
			k.sphere("glass", I.translated(Vector3(0, -0.035, 0)), 0.035, 8, 12, 0.0, 1.15)
			k.cylinder("glass", I.translated(Vector3(0, -0.01, 0)), 0.018, 0.016, 0.03, 10)
		"globe":
			# An oval ribbed glass, its back flat on the lamp's base.
			k.sphere("glass", Transform3D(Basis().scaled(Vector3(1.0, 1.45, 0.75)), Vector3.ZERO), 0.08, 8, 16, 0.0, 1.0, Color.WHITE, true)
		"flood_lens":
			k.box("glass", I, Vector3(0.42, 0.36, 0.01))
		"street_glass":
			k.cylinder("glass", I, 0.15, 0.185, 0.29, 6, false)
	var out := k.commit(Materials.get_mat)
	_lock.lock()
	_parts[name] = out
	_lock.unlock()
	return out
