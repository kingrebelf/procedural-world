class_name KitHouse
## Village houses assembled from the Medieval Village kit's modular pieces: 2 m wall
## modules, 3 m storeys, tiled roofs with brick gables. The door faces +z (the square).

## [width modules, depth modules, storeys, ground wall style, upper wall style]
const PLANS := {
	"cottage": [3, 3, 1, "brick", ""],
	"townhouse": [3, 3, 2, "brick", "plaster"],
	"longhouse": [3, 4, 1, "plaster", ""],
}

const WALL := {
	"brick": ["village/Wall_UnevenBrick_Straight", "village/Wall_UnevenBrick_Window_Wide_Round", "village/Wall_UnevenBrick_Door_Round"],
	"plaster": ["village/Wall_Plaster_Straight", "village/Wall_Plaster_Window_Wide_Round", "village/Wall_Plaster_Door_Round"],
	"timber": ["village/Wall_Plaster_WoodGrid", "village/Wall_Plaster_Window_Wide_Round", "village/Wall_Plaster_Door_Round"],
}

static func has(t: String) -> bool:
	return PLANS.has(t)

## Collision box size for a house type.
static func size_of(t: String) -> Vector3:
	var p: Array = PLANS[t]
	return Vector3(p[0] * 2.0 + 0.4, p[2] * 3.0 + 4.0, p[1] * 2.0 + 0.4)

static func build(t: String) -> ArrayMesh:
	var p: Array = PLANS[t]
	var nx: int = p[0]
	var nz: int = p[1]
	var storeys: int = p[2]
	var w := nx * 2.0
	var d := nz * 2.0
	var r := WHash.rng(WHash.str_hash(t), 0, 0, 1)
	var models: Array = []
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	for s in storeys:
		var style: String = p[3] if s == 0 or String(p[4]) == "" else p[4]
		var y := s * 3.0
		# Edges: [yaw, module count, origin of the edge, step along it].
		for e in [[0.0, nx, Vector3(-w / 2 + 1, y, d / 2), Vector3(2, 0, 0)],
				[180.0, nx, Vector3(w / 2 - 1, y, -d / 2), Vector3(-2, 0, 0)],
				[90.0, nz, Vector3(w / 2, y, d / 2 - 1), Vector3(0, 0, -2)],
				[-90.0, nz, Vector3(-w / 2, y, -d / 2 + 1), Vector3(0, 0, 2)]]:
			var yaw: float = e[0]
			var basis := Basis(Vector3.UP, deg_to_rad(yaw))
			var out := basis * Vector3(0, 0, 1)
			for m in int(e[1]):
				var at: Vector3 = e[2] + e[3] * m
				var door: bool = s == 0 and yaw == 0.0 and m == int(e[1]) / 2
				var window := not door and (m % 2 == 1 or yaw == 0.0 or (s > 0 and r.randf() < 0.7)) and not (yaw != 0.0 and s == 0 and r.randf() < 0.4)
				var kind := 2 if door else (1 if window else 0)
				models.append([WALL[style][kind], yaw, at, 1.0])
				if door:
					models.append(["village/Door_1_Round", yaw, at - basis * Vector3(0.53, 0, 0.12), 1.0])
				elif window:
					models.append(["village/Window_Wide_Round1", yaw, at, 1.0])
					if r.randf() < 0.45:
						models.append(["village/WindowShutters_Wide_Round_Open" if r.randf() < 0.6 else "village/WindowShutters_Wide_Round_Closed", yaw, at, 1.0])
					# Lamplight behind the glass at night.
					k.box("glow_warm", Transform3D(basis, at + Vector3(0, 1.85, 0) - out * 0.4), Vector3(1.3, 1.6, 0.04))
		for c in [Vector3(-w / 2, y, -d / 2), Vector3(w / 2, y, -d / 2), Vector3(-w / 2, y, d / 2), Vector3(w / 2, y, d / 2)]:
			models.append(["village/Corner_Exterior_Brick" if style == "brick" else "village/Corner_Exterior_Wood", 0, c, 1.0])
	var top := storeys * 3.0
	var roof := "village/Roof_RoundTiles_6x8" if nz == 4 else "village/Roof_RoundTiles_6x6"
	models.append([roof, 0, Vector3(0, top, 0), 1.0])
	models.append(["village/Roof_Front_Brick6", 0, Vector3(0, top, d / 2), 1.0])
	models.append(["village/Roof_Front_Brick6", 180, Vector3(0, top, -d / 2), 1.0])
	models.append(["village/Prop_Chimney" if storeys > 1 else "village/Prop_Chimney2", 0, Vector3(w / 2 - 1.6, top + 0.9, -d / 2 + 1.4), 1.0])
	# Interior: a floor and a ceiling so open doors and windows don't show the sky.
	k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, 0.05, 0)), Vector3(w - 0.5, 0.1, d - 0.5))
	k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, top - 0.05, 0)), Vector3(w - 0.5, 0.1, d - 0.5))
	k.box("stone", Transform3D.IDENTITY.translated(Vector3(0, -0.4, 0)), Vector3(w + 0.5, 0.9, d + 0.5))
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh
