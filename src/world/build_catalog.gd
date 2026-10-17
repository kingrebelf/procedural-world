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
##   snap:   floor (cell centre), wall (cell edge), post (grid corner), roof_v (grid corner), roof_c (cell centre
##           a storey up), door (in a doorway you built, see Doors), free (anywhere, turned
##           with the rotate key).
##   grid / storey: cell size and floor-to-floor height in metres.
##   span:   cells a roof covers along each side.
##   ramp:   stairs. They climb away from you, two cells long; foot = cells from the
##           piece's origin to the cell their foot stands in (along its local +z).
##   proc:   extra procedural parts built with MeshKit (see _proc).
##   station: crafting station id recipes can ask for.  light: colour of its glow.
const PIECES := {
	# Medieval village kit: 2 m cells; storeys are as tall as its walls (3.12 m), so a wall
	# stacked on a wall meets it edge to edge and an upper floor covers the wall tops.
	"foundation": {"name": "Stone Foundation", "models": [["village/Floor_UnevenBrick", 0, Vector3.ZERO, 1.0]], "proc": "plinth",
		"snap": "floor", "grid": 2.0, "storey": 3.12, "mat": "stone", "hp": 14.0, "era": 0},
	"floor_wood": {"name": "Wooden Floor", "models": [["village/Floor_WoodDark", 0, Vector3.ZERO, 1.0]],
		"snap": "floor", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 6.0, "era": 0},
	"wall_plaster": {"name": "Timber Wall", "models": [["village/Wall_Plaster_Straight", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 10.0, "era": 0},
	"wall_stone": {"name": "Stone Wall", "models": [["village/Wall_UnevenBrick_Straight", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "stone", "hp": 16.0, "era": 0},
	"wall_window": {"name": "Window Wall", "models": [["village/Wall_Plaster_Window_Wide_Round", 0, Vector3.ZERO, 1.0], ["village/Window_Wide_Round1", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 10.0, "era": 0},
	"wall_window_stone": {"name": "Stone Window Wall", "models": [["village/Wall_UnevenBrick_Window_Wide_Round", 0, Vector3.ZERO, 1.0], ["village/Window_Wide_Round1", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "stone", "hp": 16.0, "era": 0},
	"wall_door": {"name": "Doorway", "models": [["village/Wall_Plaster_Door_Round", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 10.0, "era": 0},
	"wall_door_stone": {"name": "Stone Doorway", "models": [["village/Wall_UnevenBrick_Door_Round", 0, Vector3.ZERO, 1.0]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "stone", "hp": 16.0, "era": 0},
	"stairs_wood": {"name": "Wooden Stairs", "models": [["village/Stair_Interior_Solid", 0, Vector3(0, 0, 0.694), Vector3(1, 1.03, 0.8493)]],
		"snap": "floor", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 8.0, "era": 0, "ramp": true, "foot": 0},
	"roof_small": {"name": "Tiled Roof (4x4)", "models": [["village/Roof_RoundTiles_4x4", 0, Vector3.ZERO, 1.0],
		["village/Roof_Front_Brick4", 0, Vector3(0, 0, 2), 1.0], ["village/Roof_Front_Brick4", 180, Vector3(0, 0, -2), 1.0]],
		"snap": "roof_v", "span": 2, "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 10.0, "era": 0},
	"roof_large": {"name": "Tiled Roof (6x6)", "models": [["village/Roof_RoundTiles_6x6", 0, Vector3.ZERO, 1.0],
		["village/Roof_Front_Brick6", 0, Vector3(0, 0, 3), 1.0], ["village/Roof_Front_Brick6", 180, Vector3(0, 0, -3), 1.0]],
		"snap": "roof_c", "span": 3, "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 16.0, "era": 0},
	# Corner posts close the seam where two walls meet: a dressed stone quoin or a timber post.
	"corner_stone": {"name": "Stone Corner", "models": [["village/Corner_Exterior_Brick", 0, Vector3(0.087, 0, -0.089), Vector3(1, 1.04, 1)]],
		"snap": "post", "grid": 2.0, "storey": 3.12, "mat": "stone", "hp": 12.0, "era": 0},
	"corner_timber": {"name": "Timber Corner Post", "models": [["village/Corner_Exterior_Wood", 0, Vector3.ZERO, Vector3(1, 1.04, 1)]],
		"snap": "post", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 6.0, "era": 0},
	"fence": {"name": "Wooden Fence", "models": [["village/Prop_WoodenFence_Single", 0, Vector3.ZERO, 0.97]],
		"snap": "wall", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 4.0, "era": 0},
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
	# Doors hang in a doorway you built ("fits"), at its spot and facing; each leaf's model
	# origin is its hinge (Doors.leaf_xf). They open, close and lock (see Doors).
	"door_wood": {"name": "Wooden Door", "models": [["village/Door_1_Round", 0, Vector3(-0.535, 0, -0.11), 1.0]],
		"snap": "door", "grid": 2.0, "storey": 3.12, "mat": "wood", "hp": 30.0, "era": 0,
		"door": {"tier": 1, "fits": ["wall_door", "wall_door_stone"]}},
	"door_iron": {"name": "Iron-bound Door", "models": [["village/Door_2_Round", 0, Vector3(-0.535, 0, -0.11), 1.0]],
		"snap": "door", "grid": 2.0, "storey": 3.12, "mat": "metal", "hp": 40.0, "era": 0,
		"door": {"tier": 2, "fits": ["wall_door", "wall_door_stone"]}},
	"door_bulkhead": {"name": "Bulkhead Door", "models": [["scifi/Door_Metal", 0, Vector3(0, 0, -0.05), 1.0], ["scifi/Door_Metal", 180, Vector3(0, 0, 0.05), 1.0]],
		"snap": "door", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 160.0, "era": 2,
		"door": {"tier": 3, "fits": ["door_scifi"], "slide": true}},
	"stairs_scifi": {"name": "Alloy Stairs", "models": [["scifi/Platform_Stairs_4WideTall", 0, Vector3(0, 0, -2), Vector3(1, 5.0 / 3.0, 1.32)]],
		"snap": "floor", "grid": 4.0, "storey": 5.0, "mat": "metal", "hp": 30.0, "era": 2, "ramp": true, "foot": 1},
	# Crafting stations.
	"workbench": {"name": "Workbench", "models": [["props/Workbench", 0, Vector3.ZERO, 1.0], ["props/Workbench_Drawers", 0, Vector3.ZERO, 1.0]],
		"snap": "free", "mat": "wood", "hp": 10.0, "era": -1, "station": "workbench"},
	"campfire": {"name": "Campfire", "models": [], "proc": "campfire",
		"snap": "free", "mat": "stone", "hp": 5.0, "era": -1, "station": "campfire", "light": Color(1.0, 0.55, 0.25), "fire": 0.95},
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
	"bookcase": {"name": "Bookcase", "models": [["props/Bookcase_2", 0, Vector3.ZERO, 1.0],
		# A bookcase in use: books, a stack, scrolls and a bottle or two on its shelves.
		["props/BookGroup_Medium_1", 0, Vector3(0.0, 0.77, 0.02), 1.0], ["props/BookGroup_Small_1", 0, Vector3(-0.38, 1.15, 0.02), 1.0],
		["props/Book_Stack_1", 20, Vector3(0.15, 1.15, 0.0), 1.0], ["props/Potion_1", 0, Vector3(0.5, 1.15, 0.0), 1.0],
		["props/BookGroup_Medium_1", 180, Vector3(0.05, 1.53, -0.02), 1.0], ["props/Scroll_1", 10, Vector3(-0.3, 1.92, 0.0), 1.0],
		["props/Scroll_1", -15, Vector3(-0.28, 1.98, 0.02), 1.0], ["props/BookGroup_Small_1", 180, Vector3(0.38, 1.92, 0.0), 1.0],
		["props/Potion_2", 0, Vector3(0.02, 1.92, 0.0), 1.0]], "snap": "free", "mat": "wood", "hp": 8.0, "era": -1, "decor": true},
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
	# Power (see Power and PowerGrid): generators, batteries, poles, switches and electric
	# lamps, early-industrial. Their moving and lit parts are PowerNode's (PowerKit.part).
	# mount: wall (stands out of a wall you aim at) or ceiling (hangs from one).
	"gen_woodgas": {"name": "Wood-gas Generator", "models": [], "proc": "pw_woodgas", "snap": "free", "mat": "metal", "hp": 40.0, "era": -1,
		"power": {"role": "gen", "source": "fuel", "watts": 1500.0, "term": Vector3(0.4, 0.62, -0.42), "smoke": Vector3(0.52, 1.55, 0.25),
			"fuel": {"wood": 120.0, "firewood": 90.0, "planks": 45.0, "charcoal": 240.0, "peat": 120.0, "coal": 240.0, "coal_briquettes": 260.0, "resin": 40.0}}},
	"gen_diesel": {"name": "Diesel Generator", "models": [], "proc": "pw_diesel", "snap": "free", "mat": "metal", "hp": 60.0, "era": -1,
		"power": {"role": "gen", "source": "fuel", "watts": 3000.0, "term": Vector3(0.3, 0.88, 0.5), "smoke": Vector3(0.18, 1.52, 0.12),
			"fuel": {"diesel_jerrycan": 900.0, "kerosene_can": 600.0, "lamp_oil": 240.0, "fuel_canister": 600.0, "oil_barrel": 2400.0}}},
	"windmill": {"name": "Windmill", "models": [], "proc": "pw_windmill", "snap": "free", "mat": "wood", "hp": 45.0, "era": -1,
		"power": {"role": "gen", "source": "wind", "watts": 400.0, "term": Vector3(1.0, 1.24, 1.0), "head": 7.84}},
	"solar_array": {"name": "Solar Panel", "models": [], "proc": "pw_solar", "snap": "free", "mat": "metal", "hp": 20.0, "era": -1,
		"power": {"role": "gen", "source": "sun", "watts": 250.0, "term": Vector3(0.0, 0.95, 0.1)}},
	"battery_bank": {"name": "Battery Bank", "models": [], "proc": "pw_battery", "snap": "free", "mat": "wood", "hp": 16.0, "era": -1,
		"power": {"role": "store", "store": 2000.0, "rate": 1000.0, "term": Vector3(0.5, 1.12, 0.0)}},
	"power_pole": {"name": "Power Pole", "models": [], "proc": "pw_pole", "snap": "free", "mat": "wood", "hp": 24.0, "era": -1,
		"power": {"role": "node", "links": 8, "term": Vector3(0.0, 5.84, 0.0)}},
	"junction_box": {"name": "Junction Box", "models": [], "proc": "pw_junction", "snap": "free", "mount": "wall", "mat": "metal", "hp": 10.0, "era": -1,
		"power": {"role": "node", "links": 6, "term": Vector3(0.0, -0.25, 0.06)}},
	"knife_switch": {"name": "Knife Switch", "models": [], "proc": "pw_switch", "snap": "free", "mount": "wall", "mat": "metal", "hp": 6.0, "era": -1,
		"power": {"role": "switch", "links": 4, "term": Vector3(0.0, -0.2, 0.03)}},
	"lamp_ceiling": {"name": "Ceiling Lamp", "models": [], "proc": "pw_lamp_ceiling", "snap": "free", "mount": "ceiling", "mat": "metal", "hp": 4.0, "era": -1,
		"power": {"role": "use", "watts": 60.0, "prio": 0, "term": Vector3(0.0, -0.02, 0.0),
			"lamp": {"part": "bulb", "pos": Vector3(0, -0.72, 0), "range": 10.0, "energy": 2.2, "color": Color(1.0, 0.8, 0.58)}}},
	"lamp_wall": {"name": "Bulkhead Lamp", "models": [], "proc": "pw_lamp_wall", "snap": "free", "mount": "wall", "mat": "metal", "hp": 4.0, "era": -1,
		"power": {"role": "use", "watts": 40.0, "prio": 0, "term": Vector3(0.0, -0.06, 0.02),
			"lamp": {"part": "globe", "pos": Vector3(0, 0.1, 0.2), "range": 8.0, "energy": 1.2, "color": Color(1.0, 0.8, 0.6)}}},
	"floodlight": {"name": "Floodlight", "models": [], "proc": "pw_flood", "snap": "free", "mat": "metal", "hp": 10.0, "era": -1,
		"power": {"role": "use", "watts": 300.0, "prio": 0, "term": Vector3(0.0, 1.3, 0.0),
			"lamp": {"part": "flood_lens", "pos": Vector3(0, 1.72, -0.18), "aim": -15.0, "spot": 34.0, "range": 34.0, "energy": 6.0, "color": Color(1.0, 0.9, 0.78)}}},
	"street_lamp": {"name": "Street Lamp", "models": [], "proc": "pw_street", "snap": "free", "mat": "metal", "hp": 20.0, "era": -1,
		"power": {"role": "use", "watts": 100.0, "prio": 0, "term": Vector3(0.0, 2.9, 0.0),
			"lamp": {"part": "street_glass", "pos": Vector3(0, 3.0, -0.5), "light_at": Vector3(0, 3.12, -0.5), "range": 15.0, "energy": 2.6, "color": Color(1.0, 0.82, 0.6)}}},
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

static var _kept: Array = []

## Loads every kit model and texture the world builds meshes from on the main thread, at
## world start, so chunk workers only ever take them from the resource cache. A worker
## loading a scene at the same moment as the main thread could deadlock both.
static func warm_kits() -> void:
	if not _kept.is_empty():
		return
	for sub in ["village", "scifi", "props", "nature"]:
		# list_directory sees through the .import remaps of an exported game.
		for f in ResourceLoader.list_directory(DIR + sub):
			if f.ends_with(".gltf") or (sub == "nature" and f.ends_with(".png")):
				var r = load(DIR + sub + "/" + f)
				if r != null:
					_kept.append(r)
				if f.ends_with(".gltf") and sub != "nature":
					model_parts(sub + "/" + f.get_basename())
	# The wrecked starship landmark (Landmark) and the ships on outpost landing pads
	# (ShipPad) are built from the ship kit in chunk jobs.
	model_parts("ships/Striker")
	# The gnome ring's toadstools (EasterEggs).
	model_parts("nature/Mushroom_Common")
	# Food on house tables (KitHouse, Provisions.kit).
	for f in ["props/Food_Bread", "props/Food_Cheese", "props/Food_Apples"]:
		model_parts(f)
	for t in ShipPad.SHIPS:
		model_parts("ships/" + ShipPad.SHIPS[t])
	# Photo textures and shaders that materials built on worker threads use.
	for f in ResourceLoader.list_directory("res://assets/textures"):
		if f.ends_with(".jpg") or f.ends_with(".png"):
			_kept.append(load("res://assets/textures/" + f))
	for sh in ["res://src/world/foliage.gdshader", "res://src/world/ore.gdshader", "res://src/world/shaders/organic.gdshader",
			"res://src/world/shaders/crystal.gdshader"]:
		_kept.append(load(sh))

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
	# An optional sixth entry places the model by a whole transform (tilted or leaning).
	if entry.size() > 5 and entry[5] is Transform3D:
		return entry[5]
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
		k.commit(Materials.get_mat, out)
	return out

## Merges kit models ([path under assets/models, yaw degrees, offset, scale] each) into
## one mesh with a surface per material.
## `tint`, if given, is called as tint(material, arrays) on each merged surface before it
## is added, to colour its vertices.
static func merge_models(models: Array, tint := Callable()) -> ArrayMesh:
	var groups := {} ## material -> [[arrays, transform], ...]
	var order: Array = []
	for e in models:
		var base := _xf(e)
		# An optional fifth entry swaps the model's materials by name for others.
		var swap: Dictionary = e[4] if e.size() > 4 else {}
		for part in model_parts(String(e[0])):
			var mat: Material = part[0]
			if mat != null and swap.has(mat.resource_name):
				mat = swap[mat.resource_name]
			if not groups.has(mat):
				groups[mat] = []
				order.append(mat)
			groups[mat].append([part[1], base * (part[2] as Transform3D)])
	var out := ArrayMesh.new()
	for mat in order:
		var arrays := _merge_arrays(groups[mat])
		if tint.is_valid():
			tint.call(mat, arrays)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out

## A kit model's material by name (null if it has none by that name).
static func kit_material(model: String, name: String) -> Material:
	for part in model_parts(model):
		if part[0] != null and (part[0] as Material).resource_name == name:
			return part[0]
	return null

## Surfaces of each kit model as [material, arrays, transform]. Reading a mesh back from
## the renderer on a worker thread waits for the main thread (and hangs if the main
## thread is waiting for that worker), so they are read on the main thread at world start.
static var _parts := {}

static func model_parts(name: String) -> Array:
	_lock.lock()
	var have = _parts.get(name)
	_lock.unlock()
	if have != null:
		return have
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		push_warning("kit model read off the main thread: " + name)
	var out: Array = []
	# Containers and drink (bottles, mugs, barrels, chests, crates) are built by Provisions.
	var stand_in := Provisions.kit(name)
	for e in stand_in:
		var m: ArrayMesh = e[0]
		for s in m.get_surface_count():
			out.append([m.surface_get_material(s), m.surface_get_arrays(s), e[1]])
	var ps: PackedScene = null if not stand_in.is_empty() else load(DIR + name + ".gltf")
	if ps == null:
		if stand_in.is_empty():
			push_warning("missing kit model " + name)
	else:
		var root := ps.instantiate()
		for c in root.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var xf := _node_xf(mi, root)
			for s in mi.mesh.get_surface_count():
				var om: Material = mi.material_override
				if om == null and s < mi.get_surface_override_material_count():
					om = mi.get_surface_override_material(s)
				var mat: Material = worn(_aged(_tamed(om if om != null else mi.mesh.surface_get_material(s)), name), name)
				out.append([mat, mi.mesh.surface_get_arrays(s), xf])
		root.free()
	_lock.lock()
	_parts[name] = out
	_lock.unlock()
	return out

## One surface's arrays from several transformed ones (positions, normals, tangents,
## UVs, colours and indices), all on the CPU.
static func _merge_arrays(list: Array) -> Array:
	var with_col := false
	for e in list:
		if e[0][Mesh.ARRAY_COLOR] != null:
			with_col = true
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for e in list:
		var a: Array = e[0]
		var xf: Transform3D = e[1]
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var count := pv.size()
		var base := v.size()
		v.append_array(xf * pv)
		var nb := xf.basis.inverse().transposed()
		var pn = a[Mesh.ARRAY_NORMAL]
		if pn != null:
			for q in pn:
				n.append((nb * q).normalized())
		else:
			for i in count:
				n.append(Vector3.UP)
		var pt = a[Mesh.ARRAY_TANGENT]
		if pt != null and (pt as PackedFloat32Array).size() == count * 4:
			for i in count:
				var t3 := (xf.basis * Vector3(pt[i * 4], pt[i * 4 + 1], pt[i * 4 + 2])).normalized()
				tg.append_array([t3.x, t3.y, t3.z, pt[i * 4 + 3]])
		else:
			for i in count:
				tg.append_array([1.0, 0.0, 0.0, 1.0])
		var pu = a[Mesh.ARRAY_TEX_UV]
		if pu != null and (pu as PackedVector2Array).size() == count:
			uv.append_array(pu)
		else:
			uv.resize(uv.size() + count)
		if with_col:
			var pc = a[Mesh.ARRAY_COLOR]
			if pc != null and (pc as PackedColorArray).size() == count:
				col.append_array(pc)
			else:
				for i in count:
					col.append(Color.WHITE)
		var pi = a[Mesh.ARRAY_INDEX]
		if pi != null:
			for i in pi:
				idx.append(base + i)
		else:
			for i in count:
				idx.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_TANGENT] = tg
	out[Mesh.ARRAY_TEX_UV] = uv
	if with_col:
		out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_INDEX] = idx
	return out

static var _tamed_mats := {}

## Kit trims are authored fully metallic; with this game's lighting, fully metallic
## surfaces go black or foil-like away from a bright reflection, so cap them.
static func _tamed(m: Material) -> Material:
	# The sci-fi kit's window panes are flat light grey, which lit up reads as a blank
	# white sheet: give them the tinted, reflective glass the rest of the game uses.
	if m is BaseMaterial3D and m.resource_name == "M_Glass":
		return Materials.get_mat("glass")
	# The village kit's plaster normal map is authored for small props: on a whole wall it
	# reads as cottage cheese. Lime plaster is smooth with only a gentle unevenness.
	if m is BaseMaterial3D and m.resource_name == "MI_Plaster":
		if not _tamed_mats.has(m):
			var p := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			p.normal_scale = 0.3
			_tamed_mats[m] = p
		return _tamed_mats[m]
	if m is BaseMaterial3D and (m.resource_name.ends_with("_Dark") or m.resource_name.contains("Cables")):
		# The cabled inset panels are near black: a dark grey that still shows its cables.
		if not _tamed_mats.has(m):
			var dk := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			dk.albedo_color = dk.albedo_color * 2.0
			_tamed_mats[m] = dk
		return _tamed_mats[m]
	if not (m is BaseMaterial3D) or (m as BaseMaterial3D).metallic <= 0.6:
		return m
	if not _tamed_mats.has(m):
		# Bare polished metal mirrors the dark ground and turned whole outposts black:
		# the panels are painted plate, lighter, with a little sheen.
		var c := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		c.metallic = 0.2
		c.roughness = maxf(c.roughness, 0.55)
		c.albedo_color = c.albedo_color * 1.45
		_tamed_mats[m] = c
	return _tamed_mats[m]

static var _aged_mats := {}

## The Fantasy Props kit's furniture and fittings as the real things look: its iron
## straps, hinges, candle stands and lanterns are blackened wrought iron (not the light
## painted grey the sci-fi taming above gives every metal), its timber oak darkened and
## less orange with age and wax. Only furniture and props in the world; held tools keep
## their own look (Viewmodel.kit_mesh tames them itself).
static func _aged(m: Material, model := "") -> Material:
	if not (m is BaseMaterial3D) or not m.resource_name.begins_with("MI_Trim_"):
		return m
	if model.contains("Candle") and m.resource_name == "MI_Trim_Props_Vertex":
		# Candles and their drips are wax, cream and a little translucent (the kit tints
		# the drips purple).
		_lock.lock()
		var wax = _aged_mats.get("wax")
		if wax == null:
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.93, 0.88, 0.76)
			w.roughness = 0.5
			w.subsurf_scatter_enabled = true
			w.subsurf_scatter_strength = 0.5
			_aged_mats["wax"] = w
			wax = w
		_lock.unlock()
		return wax
	var metal: bool = m.resource_name.begins_with("MI_Trim_Metal")
	var wood: bool = m.resource_name == "MI_Trim_Furniture"
	if not metal and not wood:
		return m
	_lock.lock()
	var out = _aged_mats.get(m)
	if out == null:
		var c := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		if metal:
			c.albedo_color = Color(0.36, 0.35, 0.34)
			c.metallic = 0.65
			c.roughness = 1.0
		else:
			c.albedo_color = Color(0.68, 0.58, 0.52)
			c.roughness = 1.0
		_aged_mats[m] = c
		out = c
	_lock.unlock()
	return out

static var _worn_mats := {}

## How readily moss takes on each village kit material (kit_surface.gdshader): rough stone
## and roof tiles most, limewash and planed timber less, iron hardly at all.
const MOSS_TAKE := {"MI_RoundTiles": 1.2, "MI_RockTrim": 1.1, "MI_UnevenBrick": 1.0, "MI_Brick": 1.0,
	"MI_WoodTrim_Wear": 0.9, "MI_WoodTrim": 0.8, "MI_Plaster": 0.75, "MI_MetalOrnaments": 0.15}

## The village kit's opaque materials (houses and what the player builds from them) as
## kit_surface.gdshader: drawn the same, with the place's moss, snow, frost and dust out
## of doors (ClimateWear). Glass, leaves and anything glowing stay as they are, and so
## does every other kit.
static func worn(m: Material, model := "") -> Material:
	if not model.begins_with("village/") or not (m is BaseMaterial3D):
		return m
	var b := m as BaseMaterial3D
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.emission_enabled or b.uv1_triplanar \
			or b.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return m
	_lock.lock()
	var out = _worn_mats.get(m)
	_lock.unlock()
	if out != null:
		return out
	var w := ShaderMaterial.new()
	w.shader = load("res://src/world/shaders/kit_surface.gdshader")
	w.resource_name = b.resource_name
	w.set_shader_parameter("albedo", b.albedo_color)
	w.set_shader_parameter("albedo_tex", b.albedo_texture)
	w.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
	w.set_shader_parameter("roughness", b.roughness)
	w.set_shader_parameter("roughness_tex", b.roughness_texture)
	w.set_shader_parameter("roughness_channel", _channel(b.roughness_texture_channel))
	w.set_shader_parameter("metallic", b.metallic)
	w.set_shader_parameter("metallic_tex", b.metallic_texture)
	w.set_shader_parameter("metallic_channel", _channel(b.metallic_texture_channel))
	w.set_shader_parameter("specular", b.metallic_specular)
	w.set_shader_parameter("has_normal", b.normal_enabled and b.normal_texture != null)
	w.set_shader_parameter("normal_tex", b.normal_texture)
	w.set_shader_parameter("normal_scale", b.normal_scale)
	w.set_shader_parameter("uv1_scale", b.uv1_scale)
	w.set_shader_parameter("uv1_offset", b.uv1_offset)
	w.set_shader_parameter("moss_take", MOSS_TAKE.get(b.resource_name, 0.8))
	w.set_shader_parameter("mean_lum", _mean_lum(b))
	_lock.lock()
	_worn_mats[m] = w
	_lock.unlock()
	return w

static func _channel(c: int) -> Vector4:
	var v := Vector4.ZERO
	v[clampi(c, 0, 3)] = 1.0
	return v

## A material's average brightness (linear), from its colour map halved down to a texel.
static func _mean_lum(b: BaseMaterial3D) -> float:
	var t := b.albedo_texture
	var img: Image = t.get_image() if t != null else null
	if img == null or img.is_empty():
		return 0.35
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	while img.get_width() > 1 and img.get_height() > 1:
		img.shrink_x2() # each halving averages 2 x 2 texels
	var c := img.get_pixel(0, 0).srgb_to_linear() * b.albedo_color
	return maxf(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722, 0.02)

static func _node_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

static func _proc(k: MeshKit, what: String) -> void:
	if what.begins_with("pw_"):
		PowerKit.proc(k, what)
		return
	var I := Transform3D.IDENTITY
	match what:
		"plinth":
			# Stone block under the floor tile, reaching into the ground on slopes: a
			# storey deep, so a foundation set a storey above the ground still meets it.
			k.box("stone", I.translated(Vector3(0, -1.57, 0)), Vector3(2.0, 3.12, 2.0))
		"campfire":
			# A ring of smooth, flat river stones, sooted a little.
			for n in 11:
				var a := TAU * (n + 0.3 * sin(n * 2.3)) / 11.0
				var r := 0.5 + 0.03 * sin(n * 1.7)
				var sb := Basis(Vector3.UP, -a + 0.4 * sin(n * 3.1)).scaled(Vector3(1.0 + 0.25 * sin(n * 2.9), 1.0, 0.8))
				var sc := Color(0.66, 0.64, 0.62).darkened(0.15 * absf(sin(n * 1.3)))
				k.sphere("river_stone", Transform3D(sb, Vector3(cos(a) * r, 0.035, sin(a) * r)), 0.1, 6, 10, 0.08, 0.5, sc)
			# Ash, and a bed of embers under the flames ("fire").
			k.cylinder("ash", I, 0.4, 0.38, 0.015, 16)
			k.sphere("glow_red", I.translated(Vector3(0, 0.02, 0)), 0.2, 6, 10, 0.2, 0.22)
			# Two logs laid crosswise, burnt through in the middle.
			for n in 2:
				var lb := Basis(Vector3.UP, 0.4 + n * PI * 0.5) * Basis(Vector3(0, 0, 1), PI * 0.5)
				for seg in [[-0.42, 0.26, "bark"], [-0.16, 0.32, "char"], [0.16, 0.26, "bark"]]:
					k.cylinder(seg[2], Transform3D(lb, Vector3(0, 0.05 + n * 0.07, 0)) * I.translated(Vector3(0, seg[0], 0)), 0.05, 0.05, seg[1], 8)
			# A teepee of split logs leaning together, charred where the fire licks them.
			for n in 6:
				var a := TAU * n / 6.0 + 0.25
				var foot := Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3)
				var dir := (Vector3(0.02 * sin(n * 2.0), 0.62, 0.02 * cos(n * 2.0)) - foot)
				var lb := Basis(Vector3.UP.cross(dir.normalized()).normalized(), Vector3.UP.angle_to(dir))
				var ln := dir.length()
				k.cylinder("bark", Transform3D(lb, foot), 0.042, 0.036, ln * 0.45, 7)
				k.cylinder("char", Transform3D(lb, foot) * I.translated(Vector3(0, ln * 0.45, 0)), 0.036, 0.022, ln * 0.55, 7)
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

## On the ground, how far a floor's top may sit below the ground where you aim before it
## goes up a storey instead. Above the ground it may float up to a storey less this: the
## foundation's plinth reaches a storey down, so it still meets the ground.
const SINK := 0.6

## Which pieces can share a spot: a floor, stairs on it, walls round it and a roof over
## it each take their own slot; furniture only minds other furniture.
static func slot(id: String) -> String:
	var d := def(id)
	if d.get("ramp", false):
		return "stairs"
	var m: String = d.get("snap", "free")
	return "roof" if m.begins_with("roof") else m

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
	var ramp: bool = d.get("ramp", false)
	var y := hit.y
	if anchor != null:
		var a: Vector3 = anchor
		var hit_mode := String(ctx.get("hit_mode", ""))
		var level: float
		if on_ground:
			# On the ground: the storey of the building nearby whose floor level is nearest
			# the ground here, standing a little proud of it rather than buried. (Counted
			# from whichever piece is nearest, a roof as well as a foundation.)
			level = ceilf((hit.y - a.y - SINK) / storey)
		else:
			# Aiming at a wall's top (or anything above it) means the next storey up.
			level = floorf((hit.y - a.y + 0.3) / storey)
			if hit_mode == "wall" and mode in ["floor", "roof_c", "roof_v"] and not ramp:
				# A floor or roof aimed at a wall goes on top of it: the ceiling of that
				# storey, in the cell on your side of the wall.
				level = floorf((hit.y - a.y) / storey) + 1.0
			elif hit_mode == "floor" and level < 0.0:
				# The side of a foundation's plinth is still that floor's storey.
				level = 0.0
		y = a.y + (level + lift) * storey
	else:
		y += lift * storey
	var cell := Vector3(floorf(hit.x / g) * g + g * 0.5, y, floorf(hit.z / g) * g + g * 0.5)
	match mode:
		"floor":
			if ramp:
				# Stairs climb away from you, their foot in the cell you aim at.
				var sy := snappedf(look_yaw, PI * 0.5) + turn * PI * 0.5
				var back := Basis(Vector3.UP, sy) * Vector3.BACK
				return {"pos": cell - back * g * float(d.get("foot", 0)), "yaw": sy}
			var yaw := snappedf(look_yaw + PI, PI * 0.5) + turn * PI * 0.5
			return {"pos": cell, "yaw": yaw}
		"roof_c":
			return {"pos": cell, "yaw": turn * PI * 0.5}
		"roof_v", "post":
			return {"pos": Vector3(roundf(hit.x / g) * g, y, roundf(hit.z / g) * g), "yaw": turn * PI * 0.5}
		"wall":
			var dx := hit.x - cell.x
			var dz := hit.z - cell.z
			var flip := PI if turn % 2 else 0.0
			var e := Vector3(signf(dx), 0, 0) if absf(dx) > absf(dz) else Vector3(0, 0, signf(dz))
			var pos := cell + e * g * 0.5
			if ctx.has("near"):
				return {"pos": pos, "yaw": face_out(ctx["near"], pos, e, g, ctx.get("eye")) + flip}
			return {"pos": pos, "yaw": (PI * 0.5 if e.x != 0.0 else 0.0) + flip}
	return {"pos": hit, "yaw": 0.0}

## Where the held piece could go for this aim, best first; the builder takes the first
## spot that's free. Usually just snap()'s spot, but aiming at a piece of the same kit:
##   a wall at a wall: the next wall along the line (aiming near its end) or on top;
##   a floor at a floor's top: the next cell over, on the side you aim at;
##   a wall at a floor's top: the nearest free edge of that cell;
##   a floor at a wall: the ceiling on your side, else the other side;
##   a roof at the same roof: the next one edge to edge;
##   a roof at a wall: on its top, over the cells whose walls it covers best.
## ctx as for snap(), plus hit_pos / hit_yaw / hit_id of the built piece under the
## crosshair, normal of the surface hit, eye (the camera) and near (built_near()).
static func candidates(id: String, hit: Vector3, look_yaw: float, turn: int, anchor = null, on_ground := true, ctx := {}) -> Array:
	var first := snap(id, hit, look_yaw, turn, anchor, on_ground, ctx)
	var d := def(id)
	var mode: String = d.get("snap", "free")
	if mode == "free" or ctx.get("free", false) or not ctx.has("hit_pos"):
		return [first]
	var hd := def(String(ctx.get("hit_id", "")))
	if float(hd.get("grid", 0.0)) != float(d["grid"]):
		return [first]
	var g: float = d["grid"]
	var storey: float = d["storey"]
	var hp: Vector3 = ctx["hit_pos"]
	var hyaw := float(ctx.get("hit_yaw", 0.0))
	var hb := Basis(Vector3.UP, hyaw)
	var hit_mode: String = hd.get("snap", "free")
	var up := Vector3.UP * storey * int(ctx.get("lift", 0))
	var rel := Vector3(hit.x - hp.x, 0.0, hit.z - hp.z)
	var top_face: bool = (ctx.get("normal", Vector3.UP) as Vector3).y > 0.7
	var fwd := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var flip := PI if turn % 2 else 0.0
	var ramp: bool = d.get("ramp", false)
	var out: Array = []
	if mode == "wall" and hit_mode == "wall":
		var t := rel.dot(hb.x) / (g * 0.5)
		var sd := signf(t) if t != 0.0 else 1.0
		var top := {"pos": hp + Vector3.UP * storey + up, "yaw": hyaw + flip}
		var along := {"pos": hp + hb.x * sd * g + up, "yaw": hyaw + flip}
		var other := {"pos": hp - hb.x * sd * g + up, "yaw": hyaw + flip}
		out = [along, top] if absf(t) > 0.5 else [top, along, other]
	elif mode == "floor" and not ramp and hit_mode == "floor" and not hd.get("ramp", false) and top_face:
		# Raised a storey, the same cell may be free, so snap()'s spot comes first.
		out = [first]
		for dd in _sides(rel, fwd, g).slice(0, 2):
			out.append({"pos": hp + dd * g + up, "yaw": first["yaw"]})
	elif mode == "wall" and hit_mode == "floor" and not hd.get("ramp", false) and top_face:
		out = [first]
		for dd in _sides(rel, Vector3.ZERO, g):
			var e: Vector3 = dd
			out.append({"pos": hp + e * g * 0.5 + up, "yaw": _yaw_facing(e) + flip})
	elif mode == "floor" and not ramp and hit_mode == "wall":
		var mirror: Vector3 = first["pos"]
		mirror = Vector3(2.0 * hp.x - mirror.x, mirror.y, 2.0 * hp.z - mirror.z)
		out = [first, {"pos": mirror, "yaw": first["yaw"]}]
	elif mode.begins_with("roof") and hit_mode == mode:
		var step := g * float(d.get("span", 2))
		for dd in _sides(rel, fwd, step):
			out.append({"pos": hp + dd * step + up, "yaw": hyaw})
	elif mode.begins_with("roof") and hit_mode == "wall":
		var span := int(d.get("span", 2))
		var half := g * span * 0.5
		var eye: Vector3 = ctx.get("eye", hit + fwd * -2.0)
		var away := Vector3(hp.x - eye.x, 0.0, hp.z - eye.z).normalized()
		var near: Array = ctx.get("near", [])
		var at := rel.dot(hb.x)
		var scored: Array = []
		for s in [-1.0, 1.0]:
			for j in span:
				var off := (j - (span - 1) * 0.5) * g
				var c: Vector3 = hp + hb.x * off + hb.z * s * half + Vector3.UP * storey + up
				var score: float = 10.0 * _walls_under(near, c, half, hp.y) + (hb.z * s).dot(away) - 0.2 * absf(off - at)
				scored.append([score, {"pos": c, "yaw": first["yaw"]}])
		scored.sort_custom(func(p, q): return p[0] > q[0])
		for e in scored:
			out.append(e[1])
	return out if not out.is_empty() else [first]

## A wall's dressed face (stone, brick, timber framing) is its local +z; the other face
## is the plain inside. The yaw that turns it to face `out`.
static func _yaw_facing(out: Vector3) -> float:
	return atan2(out.x, out.z)

## Which way a wall at `pos` on a cell edge should face, `e` pointing from the cell you
## aimed at to the edge: away from a floor on one side (the room is inside), and with no
## floor either side, toward you.
static func face_out(near: Array, pos: Vector3, e: Vector3, g: float, eye = null) -> float:
	var here := _floor_at(near, pos - e * g * 0.5)
	var there := _floor_at(near, pos + e * g * 0.5)
	if here != there:
		return _yaw_facing(e if here else -e)
	if eye != null:
		var to_eye := Vector3((eye as Vector3).x - pos.x, 0, (eye as Vector3).z - pos.z)
		return _yaw_facing(e if to_eye.dot(e) >= 0.0 else -e)
	return _yaw_facing(e)

## True when a floor (or foundation, or platform) has its middle at this cell centre, on
## this level or below (an upper storey's walls go up before its floor does).
static func _floor_at(near: Array, c: Vector3) -> bool:
	for f in near:
		var p: Vector3 = f["pos"]
		if slot(f["id"]) == "floor" and absf(p.x - c.x) < 0.3 and absf(p.z - c.z) < 0.3 and p.y < c.y + 0.6:
			return true
	return false

## The four sides of a cell (unit vectors), the one `rel` (the aim, from the cell's
## middle) points at first; ties go to the side you face.
static func _sides(rel: Vector3, fwd: Vector3, size: float) -> Array:
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	var score := func(v: Vector3) -> float: return v.dot(rel) / maxf(size * 0.5, 0.01) + 0.35 * v.dot(fwd)
	dirs.sort_custom(func(p, q): return score.call(p) > score.call(q))
	return dirs

## Walls standing on `base_y` inside a roof's square (centre c, half size half).
static func _walls_under(near: Array, c: Vector3, half: float, base_y: float) -> int:
	var n := 0
	for e in near:
		var p: Vector3 = e["pos"]
		if slot(e["id"]) == "wall" and absf(p.y - base_y) < 0.3 and absf(p.x - c.x) <= half + 0.05 and absf(p.z - c.z) <= half + 0.05:
			n += 1
	return n

## Built pieces (not taken down) within `radius` of pos across the loaded chunks around
## it, as {id, pos (world), yaw}.
static func built_near(streamer, pos: Vector3, radius: float) -> Array:
	var out: Array = []
	if streamer == null:
		return out
	var ck := _chunk_of(pos)
	var reach := int(ceil(radius / ChunkGenerator.SIZE))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if not is_built(o["t"]) or o["st"].get("gone", false):
					continue
				var wp: Vector3 = origin + o["p"]
				if wp.distance_to(pos) <= radius:
					out.append({"id": id_of(o["t"]), "pos": wp, "yaw": float(o["r"])})
	return out

## Wild trees near `pos` (standing, not felled), each as [trunk foot, trunk radius,
## crown bottom, top, crown reach], all world space, from the tree's mesh at its scale.
static func trees_near(streamer, pos: Vector3, radius: float) -> Array:
	var out: Array = []
	if streamer == null:
		return out
	var ck := _chunk_of(pos)
	var reach := int(ceil(radius / ChunkGenerator.SIZE))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if ObjectLibrary.kind(o["t"]) != "tree" or o["st"].get("gone", false):
					continue
				var wp: Vector3 = origin + o["p"]
				if Vector2(wp.x - pos.x, wp.z - pos.z).length() > radius:
					continue
				out.append(tree_shape(ObjectLibrary.mesh_key(o), wp, float(o["s"])))
	return out

static var _tree_boxes := {} ## tree mesh key -> its AABB, unscaled

## A tree as tree_in_way() reads it: its trunk a post up the middle, its crown a drum
## from a third of the way up to the top, a little narrower than its widest leaves.
static func tree_shape(key: String, at: Vector3, s: float) -> Array:
	if not _tree_boxes.has(key):
		var m := ObjectLibrary.get_mesh(key)
		_tree_boxes[key] = m.get_aabb() if m != null else AABB(Vector3(-2, 0, -2), Vector3(4, 7, 4))
	var bb: AABB = _tree_boxes[key]
	var top := bb.end.y * s
	var wide := maxf(maxf(absf(bb.position.x), absf(bb.end.x)), maxf(absf(bb.position.z), absf(bb.end.z))) * s
	return [at, clampf(top * 0.03, 0.18, 0.5), at.y + top * 0.35, at.y + top, wide * 0.75]

## True when a piece filling `box` (world space) would stand through a tree's trunk or
## up into its crown (`trees` from trees_near). A floor laid under the crown is fine.
static func tree_in_way(trees: Array, box: AABB) -> bool:
	var lo := Vector2(box.position.x, box.position.z)
	var hi := Vector2(box.end.x, box.end.z)
	for t in trees:
		var at: Vector3 = t[0]
		var q := Vector2(at.x, at.z)
		var d := q.distance_to(q.clamp(lo, hi))
		if d < float(t[1]) and box.end.y > at.y + 0.1 and box.position.y < float(t[3]):
			return true
		if d < float(t[4]) and box.end.y > float(t[2]) + 0.2 and box.position.y < float(t[3]):
			return true
	return false

## True when a piece taking the same slot (see slot()) already sits at this spot.
static func occupied(streamer, id: String, pos: Vector3, yaw: float) -> bool:
	return occupied_in(built_near(streamer, pos, 1.0), id, pos, yaw)

## occupied() against a list from built_near().
static func occupied_in(near: Array, id: String, pos: Vector3, yaw: float) -> bool:
	var s := slot(id)
	for e in near:
		var os := slot(e["id"])
		if os != s:
			continue
		var dist: float = (e["pos"] as Vector3).distance_to(pos)
		if s == "free":
			if dist < 0.6:
				return true
		elif dist < 0.2:
			if s != "wall" or is_equal_approx(absf(cos(float(e["yaw"]) - yaw)), 1.0):
				return true
	return false

## The nearest grid piece's origin in a built_near() list within `radius` of pos, or null.
static func nearest_in(near: Array, pos: Vector3, radius: float):
	var best = null
	var best_d := radius
	for e in near:
		if def(e["id"]).get("snap") == "free":
			continue
		var dd: float = (e["pos"] as Vector3).distance_to(pos)
		if dd < best_d:
			best_d = dd
			best = e["pos"]
	return best

## A piece's world-space box at pos / yaw, from its mesh.
static func world_aabb(id: String, pos: Vector3, yaw: float) -> AABB:
	var a := mesh(id).get_aabb()
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	return xf * a

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
	return nearest_in(built_near(streamer, pos, radius), pos, radius)

## Same as ChunkStreamer.chunk_of; kept here so this class does not depend on the
## streamer (which needs the Game autoload) and stays usable from tools and tests.
static func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / ChunkGenerator.SIZE)), int(floor(p.z / ChunkGenerator.SIZE)))
