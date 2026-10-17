class_name Bridge
## Stone bridges where roads cross rivers. One object per crossing, built along local z,
## with its origin on the river bed: species `sp` packs the span and deck height
## (span metres * 100 + deck height in half metres), so each size is meshed once.

const WIDTH := 5.2
const RAMP := 6.0 ## length of each sloping approach beyond the span
const DROP := 3.2 ## how far the approaches fall below the deck

static func pack(span: float, deck: float) -> int:
	return int(ceil(span / 4.0) * 4.0) * 100 + clampi(int(round(deck * 2.0)), 2, 99)

## A viaduct span, carrying a road over a dip: no approaches, and its deck climbs `rise`
## metres from the -z end to the +z end so spans meet the road and each other. Packed
## above 10000 so river bridges keep their numbers.
static func pack_viaduct(span: float, deck: float, rise: float) -> int:
	return (clampi(int(round(rise * 2.0)), -49, 49) + 50) * 10000 + clampi(int(round(span)) + 1, 4, 99) * 100 + clampi(int(round(deck * 2.0)), 2, 99)

static func is_viaduct(sp: int) -> bool:
	return sp >= 10000

static func rise_of(sp: int) -> float:
	return float(sp / 10000 - 50) * 0.5 if sp >= 10000 else 0.0

static func span_of(sp: int) -> float:
	return float((sp % 10000) / 100)

static func deck_of(sp: int) -> float:
	return float(sp % 100) * 0.5

static func build(sp: int) -> ArrayMesh:
	if is_viaduct(sp):
		return _viaduct(sp)
	var L := span_of(sp)
	var H := deck_of(sp)
	var k := MeshKit.new(sp & 0xFFFF)
	var I := Transform3D.IDENTITY
	var hw := WIDTH * 0.5
	# Deck and its underside.
	k.box("cobble", I.translated(Vector3(0, H - 0.3, 0)), Vector3(WIDTH, 0.6, L))
	k.box("stone", I.translated(Vector3(0, H - 0.85, 0)), Vector3(WIDTH - 0.3, 0.5, L - 0.4))
	# Approaches: slabs tilted down to the banks, with solid footing under them.
	var slope := atan2(DROP, RAMP)
	var rl := sqrt(RAMP * RAMP + DROP * DROP)
	for s in [-1.0, 1.0]:
		var b := Basis(Vector3(1, 0, 0), s * slope)
		k.box("cobble", Transform3D(b, Vector3(0, H - DROP * 0.5 - 0.3, s * (L * 0.5 + RAMP * 0.5))), Vector3(WIDTH, 0.6, rl))
		k.box("stone", I.translated(Vector3(0, H - DROP - 1.2, s * (L * 0.5 + RAMP * 0.5))), Vector3(WIDTH - 0.2, 2.2, RAMP))
		# Parapets along the approaches.
		for x in [-hw + 0.2, hw - 0.2]:
			k.box("stone", Transform3D(b, Vector3(x, H - DROP * 0.5 + 0.35, s * (L * 0.5 + RAMP * 0.5))), Vector3(0.4, 0.8, rl))
	# Parapets along the span, capped.
	for x in [-hw + 0.2, hw - 0.2]:
		k.box("stone", I.translated(Vector3(x, H + 0.4, 0)), Vector3(0.4, 0.8, L))
		k.box("cobble", I.translated(Vector3(x, H + 0.86, 0)), Vector3(0.52, 0.12, L + 0.2))
	# Piers every ~8 m, from the bed up to the deck, with cutwaters upstream and down.
	var n := maxi(1, int(L / 8.0))
	for i in n + 1:
		var z := -L * 0.5 + L * i / n
		var ph := H + 2.0
		k.box("stone", I.translated(Vector3(0, H - 0.6 - ph * 0.5, z)), Vector3(WIDTH + 0.4, ph, 1.4))
		for s in [-1.0, 1.0]:
			k.box("stone", Transform3D(Basis(Vector3.UP, PI / 4), Vector3(s * (hw + 0.2), H - 0.6 - ph * 0.5, z)), Vector3(1.0, ph, 1.0))
	# Arch rings between piers: a few stepped voussoir blocks under the deck.
	for i in n:
		var z0 := -L * 0.5 + L * i / n
		var z1 := -L * 0.5 + L * (i + 1) / n
		var span := z1 - z0
		var rad := span * 0.5 - 0.7
		var rise := minf(rad, H - 0.6)
		for j in 9:
			var a := PI * (j + 0.5) / 9.0
			var z := (z0 + z1) * 0.5 - cos(a) * rad
			var y := H - 1.1 - rise + sin(a) * rise
			# Each block lies along the curve of the arch.
			var tilt := -atan2(cos(a) * rise, sin(a) * rad)
			var seg := PI * maxf(rad, rise) / 9.0 + 0.15
			k.box("stone", Transform3D(Basis(Vector3(1, 0, 0), tilt), Vector3(0, y, z)), Vector3(WIDTH + 0.1, 0.5, seg))
	return k.commit(Materials.get_mat)

static func _viaduct(sp: int) -> ArrayMesh:
	var L := span_of(sp)
	var H := deck_of(sp)
	var rise := rise_of(sp)
	var k := MeshKit.new(sp & 0xFFFF)
	var I := Transform3D.IDENTITY
	var hw := WIDTH * 0.5
	var tilt := Basis(Vector3(1, 0, 0), -atan2(rise, L))
	var rl := sqrt(L * L + rise * rise)
	# Deck height at z along the span.
	var at := func(z: float) -> float: return H + rise * (z / L)
	k.box("cobble", Transform3D(tilt, Vector3(0, H - 0.3, 0)), Vector3(WIDTH, 0.6, rl))
	k.box("stone", Transform3D(tilt, Vector3(0, H - 0.85, 0)), Vector3(WIDTH - 0.3, 0.5, rl - 0.4))
	for x in [-hw + 0.2, hw - 0.2]:
		k.box("stone", Transform3D(tilt, Vector3(x, H + 0.4, 0)), Vector3(0.4, 0.8, rl))
		k.box("cobble", Transform3D(tilt, Vector3(x, H + 0.86, 0)), Vector3(0.52, 0.12, rl + 0.1))
	# Piers every ~8 m, reaching well into the ground wherever it falls away.
	var n := maxi(1, int(round(L / 8.0)))
	for i in n + 1:
		var z := -L * 0.5 + L * i / n
		var top: float = at.call(z) - 0.6
		var bottom := minf(-8.0, top - 4.0)
		k.box("stone", I.translated(Vector3(0, (top + bottom) * 0.5, z)), Vector3(WIDTH + 0.2, top - bottom, 1.3))
		k.box("cobble", I.translated(Vector3(0, top - 0.2, z)), Vector3(WIDTH + 0.6, 0.4, 1.7))
	for i in n:
		var z0 := -L * 0.5 + L * i / n
		var z1 := -L * 0.5 + L * (i + 1) / n
		var rad := (z1 - z0) * 0.5 - 0.65
		var crown: float = at.call((z0 + z1) * 0.5) - 1.1
		var r2 := minf(rad, maxf(crown, 0.5))
		for j in 9:
			var a := PI * (j + 0.5) / 9.0
			var z := (z0 + z1) * 0.5 - cos(a) * rad
			var y := crown - r2 + sin(a) * r2
			var bt := -atan2(cos(a) * r2, sin(a) * rad)
			var seg := PI * maxf(rad, r2) / 9.0 + 0.15
			k.box("stone", Transform3D(Basis(Vector3(1, 0, 0), bt), Vector3(0, y, z)), Vector3(WIDTH, 0.5, seg))
	return k.commit(Materials.get_mat)

## Walkable collision: deck and both approaches as one convex solid.
static func shape(sp: int) -> Array:
	var L := span_of(sp)
	var H := deck_of(sp)
	var hw := WIDTH * 0.5
	var pts := PackedVector3Array()
	if is_viaduct(sp):
		var rise := rise_of(sp)
		for x in [-hw, hw]:
			for s in [-1.0, 1.0]:
				var y: float = H + s * rise * 0.5
				pts.append(Vector3(x, y, s * L * 0.5))
				pts.append(Vector3(x, y - 1.2, s * L * 0.5))
		var v := ConvexPolygonShape3D.new()
		v.points = pts
		return [v, Vector3.ZERO]
	for x in [-hw, hw]:
		for s in [-1.0, 1.0]:
			pts.append(Vector3(x, H, s * L * 0.5))
			pts.append(Vector3(x, H - DROP, s * (L * 0.5 + RAMP)))
			pts.append(Vector3(x, H - DROP - 2.0, s * (L * 0.5 + RAMP)))
			pts.append(Vector3(x, H - DROP - 2.0, s * L * 0.5))
	var c := ConvexPolygonShape3D.new()
	c.points = pts
	return [c, Vector3.ZERO]
