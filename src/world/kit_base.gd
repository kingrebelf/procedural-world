class_name KitBase
## Sci-fi outpost buildings and yard facilities assembled from the Modular SciFi kit:
## 4 m wall modules, 3 m walls under a 2 m trim band. The door faces +z (the street).

## [width modules, depth modules, storeys, wall style]
const PLANS := {
	"hab_block": [2, 2, 1, "astra"],
	"lab_block": [3, 2, 1, "band"],
	"ops_tower": [2, 2, 2, "astra"],
}

const WALL := {
	"astra": ["scifi/WallAstra_Straight", "scifi/WallAstra_Straight_Window"],
	"band": ["scifi/WallBand_Straight", "scifi/WallAstra_Straight_Flat_Window"],
}
const TOP := {"astra": "scifi/TopAstra_Straight", "band": "scifi/TopCables_Straight"}
const STOREY := 5.0

## Yard facilities: fenced, so their parts read as one installation.
const YARDS := {"solar_farm": Vector3(16, 2.2, 12), "depot": Vector3(12, 5.0, 12), "outpost_light": Vector3(0.9, 5.4, 0.9)}

static func has(t: String) -> bool:
	return PLANS.has(t) or YARDS.has(t)

## Collision box size for a building or yard.
static func size_of(t: String) -> Vector3:
	if YARDS.has(t):
		return YARDS[t]
	var p: Array = PLANS[t]
	return Vector3(p[0] * 4.0 + 1.6, p[2] * STOREY + 0.6, p[1] * 4.0 + 1.6)

static func build(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var models: Array = []
	match t:
		"solar_farm": _solar_farm(k, models)
		"depot": _depot(k, models)
		"outpost_light": _light(k, models)
		_: _building(t, k, models)
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh

## Walls go on each outer tile edge; a kit wall sits on its tile's -x edge, so the yaw
## turns -x to face outwards.
static func _building(t: String, k: MeshKit, models: Array) -> void:
	var p: Array = PLANS[t]
	var nx: int = p[0]
	var nz: int = p[1]
	var storeys: int = p[2]
	var style: String = p[3]
	var w := nx * 4.0
	var d := nz * 4.0
	var r := WHash.rng(WHash.str_hash(t), 0, 0, 1)
	var door_i := nx / 2
	for s in storeys:
		var y := s * STOREY
		for i in nx:
			for j in nz:
				var c := Vector3(-w / 2 + 2 + i * 4, y, -d / 2 + 2 + j * 4)
				var edges: Array = []
				if i == 0: edges.append([0.0, Vector3(-1, 0, 0)])
				if i == nx - 1: edges.append([180.0, Vector3(1, 0, 0)])
				if j == 0: edges.append([-90.0, Vector3(0, 0, -1)])
				if j == nz - 1: edges.append([90.0, Vector3(0, 0, 1)])
				for e in edges:
					var yaw: float = e[0]
					var out: Vector3 = e[1]
					if s == 0 and yaw == 90.0 and i == door_i:
						var at := c + out * 2.0
						models.append(["scifi/Door_Frame_Square", 0, at, 1.0])
						models.append(["scifi/Door_Metal", 0, at + Vector3(0, 0, -0.05), 1.0])
						models.append(["scifi/Door_Metal", 180, at + Vector3(0, 0, -0.05), 1.0])
						k.box("glow_white", Transform3D.IDENTITY.translated(at + Vector3(0, 4.35, 0.3)), Vector3(2.6, 0.07, 0.06))
						continue
					var window := (i + j + s) % 2 == 0 or yaw == 90.0 or r.randf() < 0.3
					models.append([WALL[style][1 if window else 0], yaw, c, 1.0])
					models.append([TOP[style], yaw, c, 1.0])
					if window:
						k.box("glow_white", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw + 90.0)), c + out * 1.55 + Vector3(0, 1.6, 0)), Vector3(3.0, 1.4, 0.04))
				if s == 0:
					models.append(["scifi/Platform_Simple", 0, c + Vector3(0, 0.03, 0), 1.0])
		for cx in [-w / 2, w / 2]:
			for cz in [-d / 2, d / 2]:
				models.append(["scifi/Column_Pipes", 0, Vector3(cx, y, cz), 1.0])
		if s > 0:
			k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, y - 0.1, 0)), Vector3(w - 0.4, 0.2, d - 0.4))
	var top := storeys * STOREY
	# Roof: a slab capped by plate tiles, with vents and fans on top.
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, top - 0.25, 0)), Vector3(w + 0.6, 0.5, d + 0.6))
	for i in nx:
		for j in nz:
			models.append(["scifi/Platform_Squares", 0, Vector3(-w / 2 + 2 + i * 4, top + 0.01, -d / 2 + 2 + j * 4), 1.0])
	models.append(["scifi/Prop_Fan_Small", 0, Vector3(-w / 2 + 2, top, -d / 2 + 2), 1.0])
	models.append(["scifi/Prop_Vent_Big", 90, Vector3(w / 2 - 1.6, top + 0.07, 0.5), 1.0])
	if storeys > 1:
		var b := Basis(Vector3(1, 0, 0), -0.9)
		k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(w / 2 - 1.2, top, -d / 2 + 1.2)), 0.08, 0.05, 4.0, 6)
		k.sphere("panel", Transform3D(b, Vector3(w / 2 - 1.2, top + 2.6, -d / 2 + 1.5)), 1.1, 6, 14, 0.0, 0.35, Color.WHITE, true)
		k.sphere("glow_red", Transform3D.IDENTITY.translated(Vector3(w / 2 - 1.2, top + 4.1, -d / 2 + 1.2)), 0.12, 4, 6)
	# Foundation pad, and a lit step out of the door.
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -0.45, 0)), Vector3(w + 1.4, 0.95, d + 1.4))
	models.append(["scifi/Platform_DarkPlates", 0, Vector3(-w / 2 + 2 + door_i * 4, 0.03, d / 2 + 2.0), Vector3(1, 1, 0.5)])
	models.append(["scifi/Prop_Light_Floor", 0, Vector3(-w / 2 + 2 + door_i * 4, 0.04, d / 2 + 2.9), 1.0])

## A fenced array: three rows of tilted panels facing the same way, an inverter and
## battery bank at the gate end, cable runs between them.
static func _solar_farm(k: MeshKit, models: Array) -> void:
	var sz: Vector3 = YARDS["solar_farm"]
	_fence(models, sz.x, sz.z, 1)
	var tilt := Basis(Vector3(1, 0, 0), -0.45)
	for row in 3:
		var z := -sz.z / 2 + 2.4 + row * 3.0
		for n in 4:
			var x := -sz.x / 2 + 2.2 + n * 3.1
			for lx in [-1.2, 1.2]:
				k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(x + lx, 0, z + 0.3)), 0.05, 0.05, 1.6, 6)
				k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(x + lx, 0, z - 0.4)), 0.05, 0.05, 1.2, 6)
			k.box("metal_dark", Transform3D(tilt, Vector3(x, 1.45, z)), Vector3(2.9, 0.06, 1.9))
			k.box("solar_cell", Transform3D(tilt, Vector3(x, 1.49, z)), Vector3(2.8, 0.02, 1.8))
	# Inverter and batteries by the gate (gate is on +z).
	var bz := sz.z / 2 - 2.0
	models.append(["scifi/Prop_PipeHolder", 0, Vector3(3.5, 0, bz), 1.0])
	for n in 4:
		k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(-5.2 + n * 1.0, 0.75, bz)), Vector3(0.8, 1.5, 0.9))
		k.box("glow_cyan", Transform3D.IDENTITY.translated(Vector3(-5.2 + n * 1.0, 1.2, bz + 0.46)), Vector3(0.4, 0.05, 0.02))
	models.append(["scifi/Prop_Computer", 180, Vector3(0.6, 0, bz + 0.2), 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -0.15, 0)), Vector3(sz.x, 0.35, sz.z))

## A fenced cargo yard: containers in rows, crates and drums stacked on pallets.
static func _depot(k: MeshKit, models: Array) -> void:
	var sz: Vector3 = YARDS["depot"]
	_fence(models, sz.x, sz.z, 1)
	var cols := [Color(0.62, 0.3, 0.16), Color(0.16, 0.3, 0.5), Color(0.62, 0.55, 0.22), Color(0.28, 0.42, 0.32)]
	for n in 3:
		var p := Vector3(-3.4 + n * 3.3, 1.25, -3.0)
		var c: Color = cols[n % cols.size()]
		k.box("painted", Transform3D.IDENTITY.translated(p), Vector3(2.6, 2.5, 5.0), c)
		for z in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			k.box("painted", Transform3D.IDENTITY.translated(p + Vector3(1.32, 0, z)), Vector3(0.04, 2.3, 0.1), c.darkened(0.25))
			k.box("painted", Transform3D.IDENTITY.translated(p + Vector3(-1.32, 0, z)), Vector3(0.04, 2.3, 0.1), c.darkened(0.25))
	k.box("painted", Transform3D.IDENTITY.translated(Vector3(-1.75, 3.75, -3.0)), Vector3(2.6, 2.5, 5.0), cols[3])
	for n in 3:
		var x := -3.6 + n * 1.3
		models.append(["scifi/Prop_Crate4", 0, Vector3(x, 0.56, 2.6), 1.0])
		if n != 1:
			models.append(["scifi/Prop_Crate3", 0, Vector3(x, 1.62, 2.6), 1.0])
	for n in 5:
		models.append(["scifi/Prop_Barrel_Large", 0, Vector3(2.0 + (n % 3) * 0.6, 0, 2.2 + (n / 3) * 0.6), 1.0])
	models.append(["scifi/Prop_Computer", 180, Vector3(3.8, 0, 4.6), 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -0.15, 0)), Vector3(sz.x, 0.35, sz.z))

## A street lamp: a pipe column with a light bar under a cap.
static func _light(k: MeshKit, models: Array) -> void:
	models.append(["scifi/Column_Pipes", 0, Vector3.ZERO, 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 5.1, 0.5)), Vector3(0.5, 0.15, 1.6))
	k.box("glow_white", Transform3D.IDENTITY.translated(Vector3(0, 5.0, 0.9)), Vector3(0.3, 0.05, 1.0))
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 0.1, 0)), Vector3(1.1, 0.2, 1.1))

## A railing round a w by d yard, with a gap of `gates` sections at mid +z. A rail
## section runs 4 m along its -z from where it is placed.
static func _fence(models: Array, w: float, d: float, gates: int) -> void:
	var nx := int(w / 4.0)
	var nz := int(d / 4.0)
	for i in nx:
		var x := -w / 2 + i * 4
		models.append(["scifi/Prop_Rail_4", -90, Vector3(x, 0, -d / 2), 1.0])
		if absi(i * 2 - (nx - 1)) >= gates:
			models.append(["scifi/Prop_Rail_4", -90, Vector3(x, 0, d / 2), 1.0])
	for j in nz:
		var z := -d / 2 + j * 4
		models.append(["scifi/Prop_Rail_4", 180, Vector3(-w / 2, 0, z), 1.0])
		models.append(["scifi/Prop_Rail_4", 180, Vector3(w / 2, 0, z), 1.0])
	for c in [Vector2(-w / 2, -d / 2), Vector2(w / 2, -d / 2), Vector2(-w / 2, d / 2), Vector2(w / 2, d / 2)]:
		models.append(["scifi/Column_Simple", 0, Vector3(c.x, 0, c.y), 0.5])
