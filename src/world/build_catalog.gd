class_name BuildCatalog
## Everything the player can build: house pieces that snap to a grid, and crafting
## stations placed freely. A built piece is a normal chunk object of type "b:<id>", so it
## is saved in the chunk snapshot like everything else, and taking it down returns the
## piece. Meshes come from the CC0 Quaternius kits in assets/models (village, sci-fi,
## props), merged into one mesh per piece for MultiMesh instancing.

const PREFIX := "b:"
const DIR := "res://assets/models/"

## id -> definition.
##   models: [[file under assets/models, yaw degrees, offset, scale]] merged in order.
##   snap:   floor (cell centre), wall (cell edge), roof_v (grid corner), roof_c (cell centre
##           a storey up), free (anywhere, turned with the rotate key).
##   grid / storey: cell size and floor-to-floor height in metres.
##   proc:   extra procedural parts built with MeshKit (see _proc).
##   station: crafting station id recipes can ask for.  light: colour of its glow.
const PIECES := {
	# Medieval village kit: 2 m cells, 3 m storeys.
	"foundation": {"name": "Stone Foundation", "models": [["village/Floor_UnevenBrick", 0, Vector3.ZERO, 1.0]], "proc": "plinth",
		"snap": "floor", "grid": 2.0, "storey": 3.0, "mat": "stone", "hp": 14.0, "era": 0},
	"floor_wood": {"name": "Wooden Floor", "models": [["village/Floor_WoodDark", 0, Vector3.ZERO, 1.0]],
		"snap": "floor", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 6.0, "era": 0},
	"wall_plaster": {"name": "Timber Wall", "models": [["village/Wall_Plaster_Straight", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 10.0, "era": 0},
	"wall_stone": {"name": "Stone Wall", "models": [["village/Wall_UnevenBrick_Straight", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.0, "mat": "stone", "hp": 16.0, "era": 0},
	"wall_window": {"name": "Window Wall", "models": [["village/Wall_Plaster_Window_Wide_Round", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 10.0, "era": 0},
	"wall_door": {"name": "Doorway", "models": [["village/Wall_Plaster_Door_Round", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 10.0, "era": 0},
	"stairs_wood": {"name": "Wooden Stairs", "models": [["village/Stair_Interior_Solid", 0, Vector3(0, 0, 1.0), 1.0]],
		"snap": "floor", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 8.0, "era": 0, "ramp": true},
	"roof_small": {"name": "Tiled Roof (4x4)", "models": [["village/Roof_RoundTiles_4x4", 0, Vector3.ZERO, 1.0],
		["village/Roof_Front_Brick4", 0, Vector3(0, 0, 2), 1.0], ["village/Roof_Front_Brick4", 180, Vector3(0, 0, -2), 1.0]],
		"snap": "roof_v", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 10.0, "era": 0},
	"roof_large": {"name": "Tiled Roof (6x6)", "models": [["village/Roof_RoundTiles_6x6", 0, Vector3.ZERO, 1.0],
		["village/Roof_Front_Brick6", 0, Vector3(0, 0, 3), 1.0], ["village/Roof_Front_Brick6", 180, Vector3(0, 0, -3), 1.0]],
		"snap": "roof_c", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 16.0, "era": 0},
	"fence": {"name": "Wooden Fence", "models": [["village/Prop_WoodenFence_Single", 0, Vector3.ZERO, 0.97]],
		"snap": "wall", "grid": 2.0, "storey": 3.0, "mat": "wood", "hp": 4.0, "era": 0},
	# Sci-fi kit: 4 m cells, 5 m storeys. Its walls sit on a cell's -x edge; turn them
	# onto the shared convention (along x, centred on the edge).
	"platform": {"name": "Alloy Platform", "models": [["scifi/Platform_Metal", 0, Vector3.ZERO, 1.0]],
		"snap": "floor", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 30.0, "era": 2},
	"wall_scifi": {"name": "Alloy Wall", "models": [["scifi/WallAstra_Straight", 90, Vector3(0, 0, -2), 1.0], ["scifi/TopSimple_Straight", 90, Vector3(0, 0, -2), 1.0]],
		"snap": "wall", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 40.0, "era": 2},
	"wall_scifi_window": {"name": "Alloy Window Wall", "models": [["scifi/WallAstra_Straight_Window", 90, Vector3(0, 0, -2), 1.0], ["scifi/TopSimple_Straight", 90, Vector3(0, 0, -2), 1.0]],
		"snap": "wall", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 34.0, "era": 2},
	"door_scifi": {"name": "Bulkhead Doorway", "models": [["scifi/Door_Frame_Square", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 40.0, "era": 2},
	"stairs_scifi": {"name": "Alloy Stairs", "models": [["scifi/Platform_Stairs_4WideTall", 0, Vector3(0, 0, -2), Vector3(1, 5.0 / 3.0, 1.32)]],
		"snap": "floor", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 30.0, "era": 2, "ramp": true},
	# Crafting stations.
	"workbench": {"name": "Workbench", "models": [["props/Workbench", 0, Vector3.ZERO, 1.0], ["props/Workbench_Drawers", 0, Vector3.ZERO, 1.0]],
		"snap": "free", "mat": "wood", "hp": 10.0, "era": -1, "station": "workbench"},
	"campfire": {"name": "Campfire", "models": [], "proc": "campfire",
		"snap": "free", "mat": "stone", "hp": 5.0, "era": -1, "station": "campfire", "light": Color(1.0, 0.55, 0.25)},
	"forge": {"name": "Forge", "models": [["props/Bucket_Metal", 0, Vector3(1.15, 0, 0.35), 1.0]], "proc": "forge",
		"snap": "free", "mat": "stone", "hp": 24.0, "era": -1, "station": "forge", "light": Color(1.0, 0.45, 0.2)},
	"anvil": {"name": "Anvil", "models": [["props/Anvil_Log", 0, Vector3.ZERO, 1.0]],
		"snap": "free", "mat": "metal", "hp": 20.0, "era": -1, "station": "anvil"},
	"cauldron": {"name": "Arcane Cauldron", "models": [["props/Cauldron", 0, Vector3.ZERO, 1.0]], "proc": "brew",
		"snap": "free", "mat": "metal", "hp": 16.0, "era": 1, "station": "cauldron", "light": Color(0.35, 1.0, 0.8)},
	"fabricator": {"name": "Fabricator", "models": [["scifi/Prop_Computer", 0, Vector3.ZERO, 1.0], ["scifi/Prop_Crate3", 0, Vector3(0.95, 0.5, 0.0), 1.0]],
		"snap": "free", "mat": "metal", "hp": 30.0, "era": 2, "station": "fabricator"},
	# Furniture and decor (Quaternius Fantasy Props, CC0). Purely for looks; some give light.
	"bed": {"name": "Bed", "models": [["props/Bed_Twin1", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
	"bench": {"name": "Bench", "models": [["props/Bench", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 6.0, "era": -1, "decor": true},
	"bookcase": {"name": "Bookcase", "models": [["props/Bookcase_2", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
	"cabinet": {"name": "Cabinet", "models": [["props/Cabinet", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
	"chair": {"name": "Chair", "models": [["props/Chair_1", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 4.0, "era": -1, "decor": true},
	"table": {"name": "Long Table", "models": [["props/Table_Large", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
	"stool": {"name": "Stool", "models": [["props/Stool", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"nightstand": {"name": "Nightstand", "models": [["props/Nightstand_Shelf", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 4.0, "era": -1, "decor": true},
	"shelf": {"name": "Shelf", "models": [["props/Shelf_Simple", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 4.0, "era": -1, "decor": true},
	"shelf_arch": {"name": "Arched Shelf", "models": [["props/Shelf_Arch", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 6.0, "era": -1, "decor": true},
	"candle_stand": {"name": "Candle Stand", "models": [["props/CandleStick_Stand", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "metal", "hp": 3.0, "era": -1, "decor": true, "light": Color(1.0, 0.68, 0.35)},
	"lantern": {"name": "Lantern", "models": [["props/Lantern_Wall", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "metal", "hp": 3.0, "era": -1, "decor": true, "light": Color(1.0, 0.65, 0.3)},
	"banner_red": {"name": "Banner", "models": [["props/Banner_1", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"banner_blue": {"name": "Banner (striped)", "models": [["props/Banner_2", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"weapon_stand": {"name": "Weapon Rack", "models": [["props/WeaponStand", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 6.0, "era": -1, "decor": true},
	"dummy": {"name": "Training Dummy", "models": [["props/Dummy", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 30.0, "era": -1, "decor": true},
	"market_stall": {"name": "Market Stall", "models": [["props/Stall_Empty", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 10.0, "era": -1, "decor": true},
	"cart": {"name": "Hand Cart", "models": [["props/Stall_Cart_Empty", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
	"apple_crate": {"name": "Crate of Apples", "models": [["props/FarmCrate_Apple", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"apple_barrel": {"name": "Barrel of Apples", "models": [["props/Barrel_Apples", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 4.0, "era": -1, "decor": true},
	"metal_crate": {"name": "Iron-bound Crate", "models": [["props/Crate_Metal", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "metal", "hp": 8.0, "era": -1, "decor": true},
	"vase": {"name": "Metal Basin", "models": [["props/Vase_2", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "stone", "hp": 2.0, "era": -1, "decor": true},
	"pot": {"name": "Clay Pot", "models": [["props/Pot_1", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "stone", "hp": 2.0, "era": -1, "decor": true},
	"book_stand": {"name": "Book Stand", "models": [["props/BookStand", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"peg_rack": {"name": "Peg Rack", "models": [["props/Peg_Rack", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "wood", "hp": 3.0, "era": -1, "decor": true},
	"cage": {"name": "Small Cage", "models": [["props/Cage_Small", 0, Vector3.ZERO, 1.0]], "snap": "free", "mat": "metal", "hp": 5.0, "era": -1, "decor": true},
	# Storage: chests that keep what you put in them, forever.
	"storage_chest": {"name": "Storage Chest", "models": [["props/Chest_Wood", 0, Vector3.ZERO, 1.0]],
		"snap": "free", "mat": "wood", "hp": 10.0, "era": -1, "storage": 30},
	"storage_crate": {"name": "Cargo Locker", "models": [["scifi/Prop_Chest", 0, Vector3.ZERO, 1.0]],
		"snap": "free", "mat": "metal", "hp": 30.0, "era": 2, "storage": 50},
	# Teleporters: step on one to travel to any other you have built on this world.
	"waystone": {"name": "Waystone", "models": [], "proc": "waystone",
		"snap": "free", "mat": "stone", "hp": 40.0, "era": 1, "teleporter": true, "light": Color(0.5, 0.75, 1.0)},
	"teleporter": {"name": "Teleporter Pad", "models": [["scifi/Platform_DarkPlates", 0, Vector3.ZERO, 0.75]], "proc": "portal",
		"snap": "free", "mat": "metal", "hp": 50.0, "era": 2, "teleporter": true, "light": Color(0.4, 0.9, 1.0)},
	# Vehicle stations: where vehicles are put together (see Vehicle).
	"vehicle_bay": {"name": "Vehicle Bay", "models": [["scifi/Platform_DarkPlates", 0, Vector3.ZERO, 1.0],
		["scifi/Prop_Computer", 90, Vector3(-1.5, 0.05, 0.6), 1.0], ["scifi/Prop_Light_Floor", 0, Vector3(1.6, 0.05, 1.6), 1.0],
		["scifi/Prop_Light_Floor", 0, Vector3(1.6, 0.05, -1.6), 1.0], ["scifi/Prop_Crate3", 0, Vector3(-1.4, 0.05, -1.3), 1.0]],
		"snap": "free", "mat": "metal", "hp": 40.0, "era": 2, "station": "vehicle_bay", "light": Color(0.4, 0.85, 1.0)},
	"launch_pad": {"name": "Launch Pad", "models": [["scifi/Platform_Metal", 0, Vector3(-2, 0, -2), 1.0], ["scifi/Platform_Metal", 0, Vector3(2, 0, -2), 1.0],
		["scifi/Platform_Metal", 0, Vector3(-2, 0, 2), 1.0], ["scifi/Platform_Metal", 0, Vector3(2, 0, 2), 1.0],
		["scifi/Prop_Light_Floor", 0, Vector3(3.6, 0.05, 3.6), 1.0], ["scifi/Prop_Light_Floor", 0, Vector3(-3.6, 0.05, 3.6), 1.0],
		["scifi/Prop_Light_Floor", 0, Vector3(3.6, 0.05, -3.6), 1.0], ["scifi/Prop_Light_Floor", 0, Vector3(-3.6, 0.05, -3.6), 1.0],
		["scifi/Prop_Computer", 0, Vector3(-3.4, 0.05, 0), 1.0]],
		"snap": "free", "mat": "metal", "hp": 60.0, "era": 2, "station": "launch_pad", "light": Color(1.0, 0.6, 0.3)},
	"stable": {"name": "Stable", "models": [["village/Prop_Wagon", 0, Vector3(0, 0, 0.4), 1.0],
		["village/Prop_WoodenFence_Single", 0, Vector3(-1.0, 0, -1.6), 0.97], ["village/Prop_WoodenFence_Single", 0, Vector3(1.0, 0, -1.6), 0.97],
		["props/Barrel", 0, Vector3(2.2, 0, -1.0), 1.0]],
		"snap": "free", "mat": "wood", "hp": 18.0, "era": 0, "station": "stable"},
}

const STATION_RANGE := 6.0

static var _meshes := {}
static var _shapes := {}
static var _lock := Mutex.new()

static func is_built(t: String) -> bool:
	return t.begins_with(PREFIX)

static func id_of(t: String) -> String:
	return t.substr(PREFIX.length())

static func def(id: String) -> Dictionary:
	return PIECES.get(id, {})

static func is_piece_item(type: String) -> bool:
	return PIECES.has(type)

static func label(t: String) -> String:
	return def(id_of(t)).get("name", id_of(t).capitalize())

## Loads every piece mesh on the calling thread (the main thread, at world start), so
## chunk worker threads only ever read the cache.
static func warm() -> void:
	for id in PIECES:
		mesh(id)

static func mesh(id: String) -> ArrayMesh:
	_lock.lock()
	var m = _meshes.get(id)
	_lock.unlock()
	if m != null:
		return m
	m = _build(id)
	_lock.lock()
	_meshes[id] = m
	_lock.unlock()
	return m

static func _xf(entry: Array) -> Transform3D:
	var sc = entry[3]
	var s: Vector3 = sc if sc is Vector3 else Vector3.ONE * float(sc)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(entry[1]))) * Basis.from_scale(s), entry[2])

## Merges the kit model(s) into one mesh with a surface per material, plus procedural parts.
static func _build(id: String) -> ArrayMesh:
	var d := def(id)
	var out := merge_models(d.get("models", []))
	if d.has("proc"):
		var k := MeshKit.new(WHash.str_hash(id) & 0xFFFF)
		_proc(k, String(d["proc"]))
		var pm := k.commit(Materials.get_mat)
		for s in pm.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm.surface_get_arrays(s))
			out.surface_set_material(out.get_surface_count() - 1, pm.surface_get_material(s))
	return out

## Merges kit models ([path under assets/models, yaw degrees, offset, scale] each) into
## one mesh with a surface per material.
static func merge_models(models: Array) -> ArrayMesh:
	var tools := {}
	var order: Array = []
	for e in models:
		var ps: PackedScene = load(DIR + String(e[0]) + ".gltf")
		if ps == null:
			push_warning("missing kit model " + String(e[0]))
			continue
		var root := ps.instantiate()
		var base := _xf(e)
		for c in root.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var xf := base * _node_xf(mi, root)
			for s in mi.mesh.get_surface_count():
				var om: Material = mi.material_override
				if om == null and s < mi.get_surface_override_material_count():
					om = mi.get_surface_override_material(s)
				var mat: Material = _tamed(om if om != null else mi.mesh.surface_get_material(s))
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mat] = st
					order.append(mat)
				(tools[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
		root.free()
	var out := ArrayMesh.new()
	for mat in order:
		var st: SurfaceTool = tools[mat]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out

static var _tamed_mats := {}

## Kit trims are authored fully metallic; with this game's lighting, fully metallic
## surfaces go black or foil-like away from a bright reflection, so cap them.
static func _tamed(m: Material) -> Material:
	if not (m is BaseMaterial3D) or (m as BaseMaterial3D).metallic <= 0.6:
		return m
	if not _tamed_mats.has(m):
		var c := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		c.metallic = 0.55
		c.roughness = maxf(c.roughness, 0.55)
		_tamed_mats[m] = c
	return _tamed_mats[m]

static func _node_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

static func _proc(k: MeshKit, what: String) -> void:
	var I := Transform3D.IDENTITY
	match what:
		"plinth":
			# Stone block under the floor tile, reaching into the ground on slopes.
			k.box("stone", I.translated(Vector3(0, -1.0, 0)), Vector3(2.0, 1.98, 2.0))
		"campfire":
			for n in 9:
				var a := TAU * n / 9.0
				k.sphere("stone", I.translated(Vector3(cos(a) * 0.62, 0.08, sin(a) * 0.62)), 0.17, 5, 7, 0.3)
			for n in 3:
				var b := Basis(Vector3.UP, n * TAU / 3.0) * Basis(Vector3.RIGHT, 1.1)
				k.cylinder("bark", Transform3D(b, Vector3(0, 0.05, 0)) * I.translated(Vector3(0, -0.45, 0)), 0.07, 0.06, 0.9, 6)
			k.sphere("glow_warm", I.translated(Vector3(0, 0.12, 0)), 0.3, 6, 8, 0.25)
		"forge":
			k.box("cobble", I.translated(Vector3(0, 0.45, 0)), Vector3(1.6, 0.9, 1.2))
			k.box("glow_red", I.translated(Vector3(0, 0.91, 0)), Vector3(1.1, 0.04, 0.7))
			k.box("cobble", I.translated(Vector3(0, 1.25, -0.45)), Vector3(1.6, 0.7, 0.3))
			k.cylinder("cobble", I.translated(Vector3(0, 1.4, -0.35)), 0.38, 0.28, 1.9, 8)
		"brew":
			k.cylinder("glow_teal", I.translated(Vector3(0, 0.66, 0)), 0.4, 0.4, 0.04, 14)
		"waystone":
			# A standing stone on a round step, a glowing rune band and a crystal cap.
			k.cylinder("cobble", I, 1.1, 1.2, 0.25, 12)
			k.cylinder("rune_stone", I.translated(Vector3(0, 0.25, 0)), 0.38, 0.28, 2.3, 6, true, 0.04, 3)
			for n in 3:
				k.cylinder("glow_cyan", I.translated(Vector3(0, 0.8 + n * 0.45, 0)), 0.36 - n * 0.025, 0.35 - n * 0.025, 0.06, 6)
			k.crystal("glow_cyan", I.translated(Vector3(0, 2.5, 0)), 0.18, 0.6)
		"portal":
			# A ring of light over the pad, held up by two posts.
			for n in 24:
				var a := TAU * n / 24.0
				k.box("glow_cyan", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(cos(a) * 1.1, 1.5 + sin(a) * 1.1, 0)), Vector3(0.08, 0.3, 0.08))
			for sx in [-1.25, 1.25]:
				k.box("metal_dark", I.translated(Vector3(sx, 1.1, 0)), Vector3(0.18, 2.2, 0.3))
			k.cylinder("glow_cyan", I.translated(Vector3(0, 0.12, 0)), 1.2, 1.2, 0.03, 20)

## Collision for a built piece: the merged mesh as a concave shape (doorways and window
## holes stay open), or a ramp for stairs so the player walks up instead of into steps.
static func shape(t: String) -> Array:
	if _shapes.has(t):
		return _shapes[t]
	var id := id_of(t)
	var d := def(id)
	var m := mesh(id)
	var out: Array
	if d.get("ramp", false):
		out = _ramp(m)
	elif d.get("snap", "") == "free":
		var aabb := m.get_aabb()
		var b := BoxShape3D.new()
		b.size = aabb.size
		out = [b, aabb.get_center()]
	else:
		out = [m.create_trimesh_shape(), Vector3.ZERO]
	_shapes[t] = out
	return out

## A thin slab from the low end of the stairs to the high end.
static func _ramp(m: ArrayMesh) -> Array:
	var aabb := m.get_aabb()
	var lo_z := aabb.position.z
	var hi_z := aabb.end.z
	# Which end is high: average height of the vertices in the front and back quarters.
	var front := 0.0
	var back := 0.0
	for s in m.get_surface_count():
		var v: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			if p.z < lo_z + aabb.size.z * 0.25:
				back = maxf(back, p.y)
			elif p.z > hi_z - aabb.size.z * 0.25:
				front = maxf(front, p.y)
	var rise := aabb.size.y
	var run := aabb.size.z
	var ang := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	var b := BoxShape3D.new()
	b.size = Vector3(aabb.size.x, 0.2, length)
	var sgn := 1.0 if front > back else -1.0
	var basis := Basis(Vector3.RIGHT, ang * sgn)
	var c := aabb.get_center()
	var shp := [b, c - basis.y * 0.1, basis]
	return shp

# --- Placement --------------------------------------------------------------------

## Snaps a desired world position to the piece's grid. `anchor` is a nearby built
## piece's world origin (or null); storeys are counted from it. `turn` is a quarter-turn
## count for free pieces and flips walls. Returns {pos, yaw}.
## ctx (all optional): hit_mode = snap mode of the built piece under the crosshair,
## lift = storeys to raise (+) or lower (-) from where the aim puts it, free = true to
## ignore the grid (0.25 m steps, 15 degree turns).
static func snap(id: String, hit: Vector3, look_yaw: float, turn: int, anchor = null, on_ground := true, ctx := {}) -> Dictionary:
	var d := def(id)
	var mode: String = d.get("snap", "free")
	var lift := int(ctx.get("lift", 0))
	if mode != "free" and ctx.get("free", false):
		var fy := snappedf(look_yaw + PI, PI / 12.0) + turn * PI / 12.0
		return {"pos": Vector3(snappedf(hit.x, 0.25), snappedf(hit.y, 0.25) + lift * 0.25, snappedf(hit.z, 0.25)), "yaw": fy}
	if mode == "free":
		var yaw := snappedf(look_yaw + PI, PI / 12.0) + turn * PI * 0.5
		return {"pos": Vector3(snappedf(hit.x, 0.1), hit.y, snappedf(hit.z, 0.1)), "yaw": yaw}
	var g: float = d["grid"]
	var storey: float = d["storey"]
	var y := hit.y
	if anchor != null:
		var a: Vector3 = anchor
		# Aiming at a wall's top (or anything above it) means the next storey up.
		var level := floorf((hit.y - a.y + 0.3) / storey)
		# A floor or roof aimed at a wall goes on top of it: the ceiling of that storey,
		# in the cell on your side of the wall.
		if ctx.get("hit_mode", "") == "wall" and mode in ["floor", "roof_c", "roof_v"]:
			level = floorf((hit.y - a.y) / storey) + 1.0
		level += lift
		if on_ground and level < 0.0:
			level = 0.0
		y = a.y + level * storey
	else:
		y += lift * storey
	var cell := Vector3(floorf(hit.x / g) * g + g * 0.5, y, floorf(hit.z / g) * g + g * 0.5)
	match mode:
		"floor":
			var yaw := snappedf(look_yaw + PI, PI * 0.5) + turn * PI * 0.5
			return {"pos": cell, "yaw": yaw}
		"roof_c":
			return {"pos": cell, "yaw": turn * PI * 0.5}
		"roof_v":
			return {"pos": Vector3(roundf(hit.x / g) * g, y, roundf(hit.z / g) * g), "yaw": turn * PI * 0.5}
		"wall":
			var dx := hit.x - cell.x
			var dz := hit.z - cell.z
			var flip := PI if turn % 2 else 0.0
			if absf(dx) > absf(dz):
				return {"pos": Vector3(cell.x + signf(dx) * g * 0.5, y, cell.z), "yaw": PI * 0.5 + flip}
			return {"pos": Vector3(cell.x, y, cell.z + signf(dz) * g * 0.5), "yaw": flip}
	return {"pos": hit, "yaw": 0.0}

## True when a piece of the same placement kind already sits at this spot.
static func occupied(streamer, id: String, pos: Vector3, yaw: float) -> bool:
	if streamer == null:
		return false
	var mode: String = def(id).get("snap", "free")
	var ck := _chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if not is_built(o["t"]) or o["st"].get("gone", false):
					continue
				var other: String = def(id_of(o["t"])).get("snap", "free")
				var dist: float = (origin + o["p"]).distance_to(pos)
				if mode == "free" or other == "free":
					if dist < 0.6:
						return true
				elif other == mode and dist < 0.2:
					if mode != "wall" or is_equal_approx(absf(cos(o["r"] - yaw)), 1.0):
						return true
	return false

## Station ids within reach of a world position, from loaded chunks.
static func stations_near(streamer, pos: Vector3) -> Dictionary:
	var out := {}
	if streamer == null:
		return out
	var ck := _chunk_of(pos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if not is_built(o["t"]) or o["st"].get("gone", false):
					continue
				var st = def(id_of(o["t"])).get("station")
				if st != null and (origin + o["p"]).distance_to(pos) <= STATION_RANGE:
					out[st] = true
	return out

## The nearest built piece origin (world space) within `radius` of pos, or null.
static func nearest_piece(streamer, pos: Vector3, radius: float):
	if streamer == null:
		return null
	var ck := _chunk_of(pos)
	var best = null
	var best_d := radius
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if not is_built(o["t"]) or o["st"].get("gone", false) or def(id_of(o["t"])).get("snap") == "free":
					continue
				var wp: Vector3 = origin + o["p"]
				var dd := wp.distance_to(pos)
				if dd < best_d:
					best_d = dd
					best = wp
	return best

## Same as ChunkStreamer.chunk_of; kept here so this class does not depend on the
## streamer (which needs the Game autoload) and stays usable from tools and tests.
static func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))
