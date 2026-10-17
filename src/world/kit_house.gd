class_name KitHouse
## Village houses assembled from the Medieval Village kit's modular pieces: 2 m wall
## modules, 3 m storeys, tiled roofs with brick gables. The door faces +z (the square).
## Houses can be walked into: the door stands open, the walls and roof collide, and the
## rooms are furnished from the Fantasy Props kit, with a real chest to loot where
## Interiors.LOOT puts it. The furniture is its own mesh
## (key "<type>~in") drawn only up close; from further off, lamplit panels behind the
## windows (key "<type>~glow") stand in for it.

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

## Floor height inside. World objects sink 0.15 m into the ground, which leaves the
## floor 5 cm above it: a step the player walks straight over.
const FLOOR := 0.2
const SINK := 0.15
## Wall modules run 0.31 m in from the edge line and 0.09 m out.
const WALL_IN := 0.31
const WALL_OUT := 0.09
## Doorway: [half width, height].
const DOORWAY := [0.62, 2.4]

## Furniture per house: [model, yaw (degrees), position on the floor, solid].
## Kit props face +z; against the back wall yaw 0, the left wall 90, the right wall -90.
## Solid pieces get a collision box; chairs, benches and small things do not.
const F := FLOOR
## On Table_Large: its top is at 0.815, and a plate or fork any lower shows through it.
const T := FLOOR + 0.818
const FURNISH := {
	"cottage": [
		["props/Bed_Twin1", 0, Vector3(-1.6, F, -1.45), true],
		["props/Stool", 0, Vector3(-0.3, F, -2.35), false],
		["props/Candle_1", 0, Vector3(-0.3, F + 0.58, -2.35), false],
		["props/Table_Large", 90, Vector3(1.75, F, 0.75), true],
		["props/Chair_1", 90, Vector3(0.95, F, 0.2), false],
		["props/Chair_1", 90, Vector3(0.95, F, 1.35), false],
		["props/Table_Plate", 0, Vector3(1.7, T, 0.2), false],
		["props/Table_Plate", 0, Vector3(1.7, T, 1.35), false],
		["props/Table_Fork", 90, Vector3(1.7, T, 0.45), false],
		["props/Food_Bread", 20, Vector3(1.7, T + 0.014, 0.2), false],
		["props/Food_Cheese", 140, Vector3(1.7, T + 0.014, 1.35), false],
		["props/Food_Apples", 0, Vector3(1.45, T, 0.85), false],
		["props/Mug", 30, Vector3(2.0, T, 0.8), false],
		["props/CandleStick_Triple", 90, Vector3(2.05, T, 1.95), false],
		["props/Barrel", 0, Vector3(-2.2, F, 2.2), true],
		["props/Bag", 20, Vector3(-1.4, F, 2.3), false],
		["props/Bucket_Wooden_1", 0, Vector3(0.4, F, -2.35), false],
		["props/Shelf_Simple", 90, Vector3(-2.38, F + 1.5, 1.85), false],
		["props/BookGroup_Small_1", 90, Vector3(-2.15, F + 1.61, 1.7), false],
		["props/Potion_1", 0, Vector3(-2.15, F + 1.61, 2.2), false],
	],
	"townhouse": [
		["props/Bookcase_2", 0, Vector3(-1.75, F, -2.47), true],
		["props/Bookcase_2", 90, Vector3(-2.47, F, 1.75), true],
		["props/Table_Large", 0, Vector3(-0.2, F, -0.5), true],
		["props/Chair_1", 0, Vector3(-0.2, F, -1.45), false],
		["props/BookStand", -150, Vector3(1.3, F, 0.9), true],
		["props/Book_5", 10, Vector3(0.35, T, -0.5), false],
		["props/Scroll_1", 20, Vector3(-0.5, T, -0.35), false],
		["props/Book_Stack_1", 0, Vector3(-1.25, T, -0.6), false],
		["props/CandleStick_Triple", 0, Vector3(0.85, T, -0.75), false],
		["props/Potion_1", 0, Vector3(-0.95, T, -0.25), false],
		["props/Potion_2", 0, Vector3(-0.8, T, -0.7), false],
		["props/Bottle_1", 0, Vector3(1.0, T, -0.3), false],
		["props/Coin_Pile", 0, Vector3(0.05, T, -0.2), false],
		["props/Cabinet", -90, Vector3(2.5, F, 1.75), true],
		["props/Shelf_Small_Bottles", -90, Vector3(2.38, F + 1.0, 1.75), false],
		["props/Cauldron", 0, Vector3(-1.2, F, 0.95), true],
		["props/Vase_4", 0, Vector3(2.2, F, 0.6), false],
		["props/Chandelier", 0, Vector3(0, 5.95, 0), false],
	],
	"longhouse": [
		["props/Table_Large", 90, Vector3(0, F, -0.2), true],
		["props/Bench", 90, Vector3(-1.05, F, -0.2), false],
		["props/Bench", 90, Vector3(1.05, F, -0.2), false],
		["props/Mug", 0, Vector3(-0.25, T, -1.2), false],
		["props/Mug", 160, Vector3(0.3, T, -0.4), false],
		["props/Mug", 80, Vector3(-0.2, T, 0.7), false],
		["props/Chalice", 0, Vector3(0.25, T, 0.4), false],
		["props/Table_Plate", 0, Vector3(-0.25, T, -0.6), false],
		["props/Table_Plate", 0, Vector3(0.25, T, -1.3), false],
		["props/Food_Bread", -60, Vector3(-0.25, T + 0.014, -0.6), false],
		["props/Food_Cheese", 30, Vector3(0.25, T + 0.014, -1.3), false],
		["props/Food_Apples", 0, Vector3(0.22, T, 0.1), false],
		["props/CandleStick_Triple", 90, Vector3(0, T, -0.1), false],
		["props/Coin_Pile", 0, Vector3(-0.2, T, 1.1), false],
		["props/Barrel_Holder", 0, Vector3(-1.6, F, -3.3), true],
		["props/Barrel", 0, Vector3(-0.35, F, -3.25), true],
		["props/Cabinet", 90, Vector3(-2.5, F, 1.0), true],
		["props/Shelf_Small_Bottles", 90, Vector3(-2.38, F + 1.0, 1.0), false],
		["props/FarmCrate_Carrot", -90, Vector3(2.3, F, 2.1), true],
		["props/Barrel_Apples", 0, Vector3(2.2, F, 3.2), true],
		["props/Bucket_Wooden_1", 0, Vector3(1.45, F, 3.3), false],
		["props/Bag", -30, Vector3(2.2, F, -2.2), false],
	],
}

## Rug under each room's middle: [material, centre, size].
const RUGS := {
	"cottage": ["cloth", Vector3(-0.1, 0, 0.45), Vector2(1.2, 1.9)],
	"townhouse": ["cloth_blue", Vector3(-0.2, 0, -0.2), Vector2(3.4, 2.4)],
	"longhouse": ["cloth", Vector3(0, 0, -0.2), Vector2(3.2, 4.2)],
}

static func has(t: String) -> bool:
	return PLANS.has(t)

## Collision box size for a house type (the whole house, for footprint checks).
static func size_of(t: String) -> Vector3:
	var p: Array = PLANS[t]
	return Vector3(p[0] * 2.0 + 0.4, p[2] * 3.0 + 4.0, p[1] * 2.0 + 0.4)

static func _dims(t: String) -> Vector3:
	var p: Array = PLANS[t]
	return Vector3(p[0] * 2.0, p[2] * 3.0, p[1] * 2.0)

## Walls, roof and window glow positions. The same rng order every time, so the shell
## and the glow panels always agree on where the windows are.
static func _plan(t: String) -> Dictionary:
	var p: Array = PLANS[t]
	var nx: int = p[0]
	var nz: int = p[1]
	var storeys: int = p[2]
	var w := nx * 2.0
	var d := nz * 2.0
	var r := WHash.rng(WHash.str_hash(t), 0, 0, 1)
	var models: Array = []
	var glows: Array = []
	var suns: Array = []
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
					# Swung open into the room on its hinge.
					models.append(["village/Door_1_Round", yaw + 100.0, at - basis * Vector3(0.53, 0, 0.18), 1.0])
				elif window:
					models.append(["village/Window_Wide_Round1", yaw, at, 1.0])
					var shut := false
					if r.randf() < 0.45:
						shut = r.randf() >= 0.6
						models.append(["village/WindowShutters_Wide_Round_Closed" if shut else "village/WindowShutters_Wide_Round_Open", yaw, at, 1.0])
					glows.append(Transform3D(basis, at + Vector3(0, 1.85, 0) - out * 0.4))
					if not shut:
						# The pane (Window_Wide_Round1's glass) on the wall's inner face.
						suns.append([at + Vector3(0, 1.84, 0) - out * 0.2, -out, 0.54, 0.78])
		for c in [Vector3(-w / 2, y, -d / 2), Vector3(w / 2, y, -d / 2), Vector3(-w / 2, y, d / 2), Vector3(w / 2, y, d / 2)]:
			models.append(["village/Corner_Exterior_Brick" if style == "brick" else "village/Corner_Exterior_Wood", 0, c, 1.0])
	var top := storeys * 3.0
	var roof := "village/Roof_RoundTiles_6x8" if nz == 4 else "village/Roof_RoundTiles_6x6"
	models.append([roof, 0, Vector3(0, top, 0), 1.0])
	models.append(["village/Roof_Front_Brick6", 0, Vector3(0, top, d / 2), 1.0])
	models.append(["village/Roof_Front_Brick6", 180, Vector3(0, top, -d / 2), 1.0])
	models.append(["village/Prop_Chimney" if storeys > 1 else "village/Prop_Chimney2", 0, Vector3(w / 2 - 1.6, top + 0.9, -d / 2 + 1.4), 1.0])
	return {"models": models, "glows": glows, "suns": suns}

static func build(t: String) -> ArrayMesh:
	var dm := _dims(t)
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var models: Array = _plan(t)["models"]
	# Kit floorboards just above the ground, a plank ceiling on beams, and a stone plinth
	# reaching into slopes.
	for i in int(dm.x / 2):
		for j in int(dm.z / 2):
			models.append(["village/Floor_WoodDark", 90 * ((i + j) % 2), Vector3(-dm.x / 2 + 1 + 2 * i, FLOOR - 0.01, -dm.z / 2 + 1 + 2 * j), 1.0])
	k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, FLOOR - 0.07, 0)), Vector3(dm.x - 0.5, 0.1, dm.z - 0.5))
	k.box("wood_floor", Transform3D.IDENTITY.translated(Vector3(0, dm.y - 0.05, 0)), Vector3(dm.x - 0.5, 0.1, dm.z - 0.5))
	for j in int(dm.z / 2) + 1:
		var z := -dm.z / 2 + WALL_IN + 0.1 + (dm.z - 2 * WALL_IN - 0.2) * j / int(dm.z / 2)
		k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, dm.y - 0.2, z)), Vector3(dm.x - 0.5, 0.22, 0.2))
	k.box("stone", Transform3D.IDENTITY.translated(Vector3(0, -0.4, 0)), Vector3(dm.x + 0.5, 0.9, dm.z + 0.5))
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh

## Where the hearth sits: under the chimney, against the back wall.
static func hearth_x(t: String) -> float:
	return _dims(t).x / 2 - 1.6

## Warm light by the hearth, in the house's own space (sunk like the house).
static func light_at(t: String) -> Vector3:
	var dm := _dims(t)
	return Vector3(hearth_x(t), FLOOR + 1.0 - SINK, -dm.z / 2 + WALL_IN + 1.0)

## The foot of the hearth fire, in the house's own space (sunk like the house).
static func fire_at(t: String) -> Vector3:
	var dm := _dims(t)
	return Vector3(hearth_x(t), FLOOR + 0.2 - SINK, -dm.z / 2 + WALL_IN + 0.42)

## The furnished room: kit furniture, a stone hearth with a fire, and a rug.
static func interior(t: String) -> ArrayMesh:
	var dm := _dims(t)
	var models: Array = []
	for f in FURNISH[t]:
		models.append([f[0], f[1], f[2], 1.0])
	var mesh := BuildCatalog.merge_models(models)
	var k := MeshKit.new(WHash.str_hash(t + "~in") & 0xFFFF)
	var I := Transform3D.IDENTITY
	var hx := hearth_x(t)
	var back := -dm.z / 2 + WALL_IN
	# Hearth: a raised stone floor, cheeks, a timber mantel and the chimney breast.
	k.box("stone_floor", I.translated(Vector3(hx, FLOOR + 0.1, back + 0.45)), Vector3(1.7, 0.2, 0.9))
	for side in [-1.0, 1.0]:
		k.box("hearth_brick", I.translated(Vector3(hx + side * 0.66, FLOOR + 0.7, back + 0.33)), Vector3(0.38, 1.0, 0.66))
	k.box("stone_dark", I.translated(Vector3(hx, FLOOR + 0.7, back + 0.05)), Vector3(1.0, 1.0, 0.1))
	k.box("timber", I.translated(Vector3(hx, FLOOR + 1.27, back + 0.38)), Vector3(1.9, 0.14, 0.78))
	var breast := dm.y - (FLOOR + 1.34)
	k.box("hearth_brick", I.translated(Vector3(hx, FLOOR + 1.34 + breast * 0.5, back + 0.28)), Vector3(1.4, breast, 0.56))
	# The fire: crossed logs and embers.
	for n in 3:
		var b := Basis(Vector3.UP, n * 1.1 + 0.3) * Basis(Vector3.RIGHT, PI / 2)
		k.cylinder("bark", Transform3D(b, Vector3(hx, FLOOR + 0.28, back + 0.4)) * I.translated(Vector3(0, -0.32, 0)), 0.06, 0.05, 0.64, 6)
	# Embers under the flames (FireFx, Interiors.fires).
	k.sphere("glow_red", I.translated(Vector3(hx, FLOOR + 0.22, back + 0.4)), 0.2, 5, 8, 0.3, 0.25)
	# Signs of use: an iron pot keeping warm on the hearthstone, and split logs stacked
	# in the corner between the hearth and the side wall.
	var pot := I.translated(Vector3(hx + 0.5, FLOOR + 0.2, back + 0.78))
	k.cylinder("iron", pot, 0.1, 0.12, 0.15, 12)
	k.cylinder("iron", pot.translated(Vector3(0, 0.15, 0)), 0.125, 0.125, 0.012, 12)
	var r := WHash.rng(WHash.str_hash(t + "~logs"), 0, 0, 7)
	for row in 3:
		for n in 2:
			var lx := hx + 1.0 + n * 0.145 + (0.07 if row % 2 else 0.0) * (0.5 - n) + r.randf_range(-0.01, 0.01)
			var lb := Basis(Vector3.UP, r.randf_range(-0.06, 0.06)) * Basis(Vector3.RIGHT, PI / 2)
			k.cylinder("bark", Transform3D(lb, Vector3(lx, FLOOR + 0.065 + row * 0.12, back + 0.03)), 0.065, 0.06, 0.48, 7)
	if t != "townhouse":
		# A hanging on the plain stretch of back wall away from the hearth.
		Interiors.tapestry(k, I.translated(Vector3(-1.8, 1.8, back + 0.02)))
	var rug: Array = RUGS[t]
	var rc: Vector3 = rug[1]
	var rs: Vector2 = rug[2]
	k.box(rug[0], I.translated(Vector3(rc.x, FLOOR + 0.006, rc.z)), Vector3(rs.x, 0.012, rs.y))
	k.commit(Materials.get_mat, mesh)
	return mesh

## The windows the sun can shine in through (not shuttered), for Interiors.sun_windows:
## [centre on the wall's inner face, inward normal, half width, half height], unsunk.
static func sun_windows(t: String) -> Array:
	return _plan(t)["suns"]

## Lamplit panels just inside the windows, for houses seen from further than the
## furniture is drawn.
static func glow(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t + "~glow") & 0xFFFF)
	for xf in _plan(t)["glows"]:
		k.box("glow_warm", xf, Vector3(1.3, 1.6, 0.04))
	return k.commit(Materials.get_mat)

## Collision you can walk into: floor, four walls with the doorway left open, the roof
## as a solid gable, and boxes for the bigger furniture. [shape, offset].
static func shape(t: String) -> Array:
	var dm := _dims(t)
	var w := dm.x
	var d := dm.z
	var top := dm.y
	var f := PackedVector3Array()
	var th := WALL_IN + WALL_OUT
	var mid := (WALL_IN - WALL_OUT) * 0.5 # wall centre, inwards of the edge line
	_box_faces(f, Vector3(0, FLOOR - 0.5, 0), Vector3(w + 0.5, 1.0, d + 0.5))
	_box_faces(f, Vector3(0, top * 0.5, -d / 2 + mid), Vector3(w + 0.4, top, th))
	_box_faces(f, Vector3(w / 2 - mid, top * 0.5, 0), Vector3(th, top, d + 0.4))
	_box_faces(f, Vector3(-w / 2 + mid, top * 0.5, 0), Vector3(th, top, d + 0.4))
	# Front wall around the doorway (the middle module).
	var p: Array = PLANS[t]
	var door_x := -w / 2 + 1 + 2.0 * int(int(p[0]) / 2)
	var hw: float = DOORWAY[0]
	var dh: float = DOORWAY[1]
	var zf := d / 2 - mid
	var left := door_x - hw - (-w / 2 - 0.2)
	var right := w / 2 + 0.2 - (door_x + hw)
	_box_faces(f, Vector3(-w / 2 - 0.2 + left * 0.5, top * 0.5, zf), Vector3(left, top, th))
	_box_faces(f, Vector3(door_x + hw + right * 0.5, top * 0.5, zf), Vector3(right, top, th))
	_box_faces(f, Vector3(door_x, (dh + top) * 0.5, zf), Vector3(hw * 2.0, top - dh, th))
	# Gable roof along z, eaves past the walls.
	var ex := w / 2 + 0.5
	var ez := d / 2 + 0.5
	var ridge := top + 4.4
	var a := Vector3(-ex, top, -ez)
	var b := Vector3(ex, top, -ez)
	var c := Vector3(0, ridge, -ez)
	var a2 := Vector3(-ex, top, ez)
	var b2 := Vector3(ex, top, ez)
	var c2 := Vector3(0, ridge, ez)
	f.append_array([a, c, b, a2, b2, c2])
	f.append_array([a, a2, c2, a, c2, c, b, c, c2, b, c2, b2])
	f.append_array([a, b, b2, a, b2, a2])
	# Furniture you bump into.
	for e in FURNISH[t]:
		if e[3]:
			var bx := _model_box(String(e[0]), Transform3D(Basis(Vector3.UP, deg_to_rad(float(e[1]))), e[2]))
			_box_faces(f, bx.get_center(), bx.size)
	var cs := ConcavePolygonShape3D.new()
	cs.backface_collision = true
	cs.set_faces(f)
	return [cs, Vector3(0, -SINK, 0)]

## Axis-aligned bounds of a kit model under a transform, from the cached arrays.
static func _model_box(name: String, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	for part in BuildCatalog.model_parts(name):
		var pxf: Transform3D = xf * (part[2] as Transform3D)
		var pos: PackedVector3Array = (part[1] as Array)[Mesh.ARRAY_VERTEX]
		for v in pos:
			var q := pxf * v
			if first:
				box = AABB(q, Vector3.ZERO)
				first = false
			else:
				box = box.expand(q)
	return box

static func _box_faces(f: PackedVector3Array, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var v: Array = []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		f.append_array([v[q[0]], v[q[1]], v[q[2]], v[q[0]], v[q[2]], v[q[3]]])
