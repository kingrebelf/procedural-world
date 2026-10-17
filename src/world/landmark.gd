class_name Landmark
## Hidden landmarks (v7 worlds): one at the heart of every region whose landform has one,
## each guarding a rich cache. A shrine on the tallest karst tower, a giant's eyrie on a
## needle, an altar at the bottom of a sinkhole, a fallen star in a crater, a wrecked
## starship in the dunes, titan bones in the badlands, a dolmen in a stone circle among
## the crags, a lost caravan on a gorge floor and a ruined tower on a lake isle.

const LABELS := {
	"summit_shrine": "Summit Shrine", "eyrie": "Giant's Eyrie", "sunken_altar": "Sunken Altar",
	"fallen_star": "Fallen Star", "star_wreck": "Wrecked Starship", "titan_bones": "Titan's Bones",
	"dolmen": "Dolmen", "star_iron": "Fallen Star",
}
## Collision boxes (the meshes stand on y = 0).
const SIZE := {
	"summit_shrine": Vector3(3.8, 3.4, 3.8), "eyrie": Vector3(4.2, 1.0, 4.2), "sunken_altar": Vector3(2.4, 1.1, 1.3),
	"fallen_star": Vector3(4.6, 3.2, 4.6), "star_wreck": Vector3(8.0, 3.6, 13.0), "titan_bones": Vector3(4.0, 2.6, 15.0),
	"dolmen": Vector3(3.2, 2.0, 1.8), "star_iron": Vector3(3.0, 1.2, 3.0),
}

## [landmark, where to put it: "high", "low" or "flat"] by landform.
const BY_LANDFORM := {
	WorldField.LF_KARST: ["summit_shrine", "high"], WorldField.LF_NEEDLES: ["eyrie", "high"],
	WorldField.LF_TERRACES: ["summit_shrine", "high"], WorldField.LF_SINKHOLES: ["sunken_altar", "low"],
	WorldField.LF_CRATERS: ["fallen_star", "low"], WorldField.LF_DUNES: ["star_wreck", "flat"],
	WorldField.LF_BADLANDS: ["titan_bones", "flat"], WorldField.LF_CRAGS: ["dolmen", "flat"],
	WorldField.LF_GORGE: ["caravan", "low"], WorldField.LF_LAKES: ["watchtower", "high"],
}

static func has(t: String) -> bool:
	return LABELS.has(t)

static func build(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(t)
	match t:
		"summit_shrine":
			# A stone pavilion with a slate pyramid roof and a lantern under it.
			k.box("castle_stone", I.translated(Vector3(0, 0.08, 0)), Vector3(3.8, 0.16, 3.8))
			k.box("castle_stone", I.translated(Vector3(0, 0.3, 0)), Vector3(3.3, 0.3, 3.3))
			for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				k.cylinder("castle_stone", I.translated(Vector3(c.x * 1.32, 0.45, c.y * 1.32)), 0.17, 0.14, 2.3, 8)
				k.box("castle_stone", I.translated(Vector3(c.x * 1.32, 0.5, c.y * 1.32)), Vector3(0.46, 0.12, 0.46))
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				k.box("timber", Transform3D(b, b * Vector3(0, 2.82, 1.32)), Vector3(3.0, 0.2, 0.22))
			k.cylinder("slate", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 2.92, 0)), 2.75, 0.06, 1.35, 4)
			k.sphere("gold", I.translated(Vector3(0, 4.3, 0)), 0.14, 4, 6)
			k.cylinder("iron", I.translated(Vector3(0, 2.2, 0)), 0.015, 0.015, 0.62, 4, false)
			k.sphere("glow_warm", I.translated(Vector3(0, 2.1, 0)), 0.16, 5, 8)
			k.cylinder("gold", I.translated(Vector3(0, 0.45, 0)), 0.32, 0.22, 0.16, 10)
		"eyrie":
			# A huge nest of branches round three speckled eggs, old bones in the rim.
			for i in 44:
				var a := i * TAU / 44.0 + r.randf_range(-0.1, 0.1)
				var rad := r.randf_range(1.3, 1.9)
				var tangent := Vector3(-sin(a), r.randf_range(-0.25, 0.35), cos(a)).normalized()
				var b := Basis(Vector3.UP.cross(tangent).normalized(), Vector3.UP.angle_to(tangent))
				k.cylinder("timber", Transform3D(b, Vector3(cos(a) * rad, r.randf_range(0.15, 0.75), sin(a) * rad) - tangent * 1.1),
					r.randf_range(0.04, 0.07), 0.03, r.randf_range(1.6, 2.4), 5, false)
			for i in 14:
				var a := r.randf() * TAU
				var d := Vector3(cos(a), r.randf_range(-0.05, 0.05), sin(a))
				var b := Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d))
				k.cylinder("timber", Transform3D(b, Vector3(0, 0.12 + i * 0.012, 0) - d * 1.3), 0.045, 0.03, 2.6, 5, false)
			for i in 3:
				var a := i * TAU / 3.0 + 0.4
				var eb := Basis.from_euler(Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))).scaled(Vector3(1.0, 1.3, 1.0))
				k.sphere("plaster", Transform3D(eb, Vector3(cos(a) * 0.38, 0.5, sin(a) * 0.38)), 0.26, 7, 10, 0.0, 1.0, Color(0.92, 0.88, 0.8))
			for i in 4:
				var a := r.randf() * TAU
				var b := Basis(Vector3(cos(a), 0, sin(a)), PI * 0.5 + r.randf_range(-0.3, 0.3))
				k.cylinder("bone", Transform3D(b, Vector3(cos(a + 1.5) * 1.5, 0.6, sin(a + 1.5) * 1.5)), 0.05, 0.04, 0.9, 6)
		"sunken_altar":
			# A mossy altar stone with candles and a golden idol on it.
			k.box("crypt_stone", I.translated(Vector3(0, 0.45, 0)), Vector3(2.1, 0.9, 1.1))
			k.box("crypt_stone", I.translated(Vector3(0, 0.95, 0)), Vector3(2.3, 0.12, 1.25))
			k.sphere("moss", I.translated(Vector3(-0.7, 0.98, 0.3)), 0.35, 4, 8, 0.2, 0.25)
			k.sphere("moss", I.translated(Vector3(0.9, 0.2, -0.5)), 0.5, 4, 8, 0.2, 0.3)
			k.cylinder("gold", I.translated(Vector3(0, 1.01, 0)), 0.16, 0.13, 0.08, 10)
			k.sphere("gold", I.translated(Vector3(0, 1.2, 0)), 0.11, 6, 8, 0.0, 1.4)
			k.sphere("gold", I.translated(Vector3(0, 1.38, 0)), 0.08, 6, 8)
			for x in [-0.8, 0.8]:
				k.cylinder("plaster", I.translated(Vector3(x, 1.01, -0.3)), 0.04, 0.04, 0.22, 6)
				k.sphere("glow_warm", I.translated(Vector3(x, 1.27, -0.3)), 0.03, 3, 5)
		"fallen_star":
			# A pitted black meteorite split by glowing crystal, half buried in its crater.
			k.sphere("stone_dark", I.translated(Vector3(0, 0.6, 0)), 2.1, 9, 14, 0.38, 0.75)
			k.sphere("stone_dark", I.translated(Vector3(1.6, 0.2, 1.0)), 0.8, 6, 9, 0.4, 0.7)
			for i in 7:
				var a := i * TAU / 7.0 + r.randf_range(-0.3, 0.3)
				var tilt := r.randf_range(0.3, 0.9)
				var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), tilt)
				k.crystal("crystal", Transform3D(b, Vector3(cos(a) * 1.0, 1.2 + r.randf_range(-0.2, 0.4), sin(a) * 1.0)),
					r.randf_range(0.14, 0.26), r.randf_range(0.9, 1.7))
		"star_iron":
			# What a starfall night brings down (Starfall): a torn, scorched slab of hull
			# driven into its crater, smaller shards and a ring of thrown-up earth round it.
			k.box("metal_dark", Transform3D(Basis.from_euler(Vector3(0.55, 0.3, 0.2)), Vector3(0, 0.35, 0)), Vector3(1.9, 0.14, 1.2))
			k.box("rust", Transform3D(Basis.from_euler(Vector3(0.62, 0.3, 0.24)), Vector3(0.05, 0.42, 0.08)), Vector3(1.5, 0.05, 0.9))
			k.box("metal_dark", Transform3D(Basis.from_euler(Vector3(-0.3, 1.1, 0.7)), Vector3(-0.7, 0.25, 0.5)), Vector3(0.8, 0.5, 0.1))
			for i in 5:
				var a := i * TAU / 5.0 + r.randf_range(-0.4, 0.4)
				var b := Basis.from_euler(Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6)))
				k.box("metal_dark" if i % 2 else "rust", Transform3D(b, Vector3(cos(a) * r.randf_range(1.0, 1.7), 0.08, sin(a) * r.randf_range(1.0, 1.7))),
					Vector3(r.randf_range(0.2, 0.5), 0.04, r.randf_range(0.15, 0.35)))
			for i in 9:
				var a := i * TAU / 9.0 + r.randf_range(-0.2, 0.2)
				k.sphere("ash", I.translated(Vector3(cos(a) * 2.6, -0.15, sin(a) * 2.6)), r.randf_range(0.5, 0.8), 4, 6, 0.3, 0.35)
		"star_wreck":
			# The same make of ship you fly, nose down in the sand, plating strewn about.
			var hull := Transform3D(Basis.from_euler(Vector3(0.32, 0.4, 0.22)).scaled(Vector3.ONE * 1.5), Vector3(0, 0.2, 0))
			var out := _merge(["ships/Striker"], [hull])
			for i in 7:
				var a := r.randf() * TAU
				var d := r.randf_range(3.5, 7.5)
				var b := Basis.from_euler(Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4)))
				k.box("metal_dark" if i % 2 else "rust", Transform3D(b, Vector3(cos(a) * d, 0.05, sin(a) * d)), Vector3(r.randf_range(0.6, 1.6), 0.06, r.randf_range(0.4, 1.0)))
			k.sphere("stone_dark", I.translated(Vector3(0.4, -0.2, 3.2)), 2.4, 5, 10, 0.2, 0.28)
			return k.commit(Materials.get_mat, out)
		"titan_bones":
			# The bleached skeleton of something enormous: spine, ribs and a long skull.
			var spine: Array = []
			for i in 16:
				var z := -6.5 + i * 0.85
				var y := 0.55 + sin(i / 15.0 * PI) * 0.9
				spine.append(Vector3(0, y, z))
				k.sphere("bone", I.translated(Vector3(0, y, z)), 0.3, 5, 8, 0.1, 0.8)
			for i in range(3, 12):
				for side in [-1.0, 1.0]:
					var p: Vector3 = spine[i]
					var reach := 1.6 + sin((i - 3) / 8.0 * PI) * 0.9
					var prev := p
					for s in 6:
						var u := (s + 1) / 6.0
						var q := Vector3(side * sin(u * PI * 0.62) * reach, p.y + 0.3 - u * u * (p.y + 0.35) + sin(u * PI) * 0.4, p.z + u * 0.4)
						var d := q - prev
						var b := Basis(Vector3.UP.cross(d.normalized()).normalized(), Vector3.UP.angle_to(d.normalized())) if absf(d.normalized().y) < 0.999 else Basis.IDENTITY
						k.cylinder("bone", Transform3D(b, prev), 0.11 - u * 0.04, 0.1 - u * 0.04, d.length(), 6, false)
						prev = q
			var head := Basis(Vector3.RIGHT, -0.25).scaled(Vector3(0.8, 0.65, 1.6))
			k.sphere("bone", Transform3D(head, Vector3(0, 0.75, 7.7)), 0.85, 7, 10, 0.12)
			k.sphere("stone_dark", I.translated(Vector3(0.35, 0.95, 7.55)), 0.16, 4, 6)
			k.sphere("stone_dark", I.translated(Vector3(-0.35, 0.95, 7.55)), 0.16, 4, 6)
			for side in [-1.0, 1.0]:
				var tusk := Basis(Vector3(1, 0, 0), 1.75).rotated(Vector3.UP, side * 0.3)
				k.cylinder("bone", Transform3D(tusk, Vector3(side * 0.4, 0.45, 8.6)), 0.12, 0.02, 1.6, 7, false)
		"dolmen":
			# Two standing slabs under a great capstone.
			k.box("stone", Transform3D(Basis(Vector3.FORWARD, 0.04), Vector3(-1.0, 0.75, 0)), Vector3(0.45, 1.5, 1.3))
			k.box("stone", Transform3D(Basis(Vector3.FORWARD, -0.05), Vector3(1.0, 0.72, 0)), Vector3(0.45, 1.45, 1.2))
			k.sphere("stone", Transform3D(Basis(Vector3.FORWARD, 0.06), Vector3(0, 1.62, 0)), 1.0, 5, 8, 0.15, 0.32)
			k.sphere("moss", I.translated(Vector3(0.3, 1.88, 0.2)), 0.45, 4, 7, 0.2, 0.2)
	return k.commit(Materials.get_mat)

## Kit models with full transforms (tilts and all) merged into one mesh, a surface per
## material, from the arrays BuildCatalog cached on the main thread.
static func _merge(names: Array, xfs: Array) -> ArrayMesh:
	var groups := {}
	var order: Array = []
	for i in names.size():
		for part in BuildCatalog.model_parts(String(names[i])):
			var mat: Material = part[0]
			if not groups.has(mat):
				groups[mat] = []
				order.append(mat)
			groups[mat].append([part[1], (xfs[i] as Transform3D) * (part[2] as Transform3D)])
	var out := ArrayMesh.new()
	for mat in order:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BuildCatalog._merge_arrays(groups[mat]))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out
