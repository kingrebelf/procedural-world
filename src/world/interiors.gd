class_name Interiors
## Rooms you can walk into beyond the village houses (KitHouse builds its own): stone
## keeps and mausoleums, sci-fi hab and lab blocks, ops towers and bunkers, mushroom
## houses, hab domes, watchtowers and the open fantasy shrine. Every room has its
## doorway on the +z side, collision you walk in through (shape()), furniture drawn up
## close (mesh key "<type>~in", interior()), lights of its own, and loot spots that
## stock() fills once with the era's chest, rune coffer or supply crate, in new chunks
## and in chunks saved before rooms had loot alike.

## World objects sink this far into the ground (ChunkNode); collision follows.
const SINK := 0.15

## Box rooms: [inner half size (x, z), floor, ceiling, outer half size, top of the solid
## block above the ceiling, doorway [centre x, half width, height]].
const BOX := {
	"castle_keep": [Vector2(3.69, 3.69), 0.22, 2.9, Vector2(4.3, 4.3), 9.45, [1.0, 0.62, 2.4]],
	"crypt_keep": [Vector2(3.69, 3.69), 0.22, 2.9, Vector2(4.3, 4.3), 9.45, [1.0, 0.62, 2.4]],
	"hab_block": [Vector2(3.56, 3.56), 0.2, 4.5, Vector2(4.7, 4.7), 5.0, [2.0, 1.95, 4.0]],
	"lab_block": [Vector2(5.56, 3.56), 0.2, 4.5, Vector2(6.7, 4.7), 5.0, [0.0, 1.95, 4.0]],
	"ops_tower": [Vector2(3.56, 3.56), 0.2, 4.8, Vector2(4.7, 4.7), 10.0, [2.0, 1.95, 4.0]],
	"bunker_keep": [Vector2(5.56, 3.56), 0.2, 4.5, Vector2(6.7, 4.7), 5.0, [0.0, 1.95, 4.0]],
	"bunker_tower": [Vector2(3.56, 3.56), 0.2, 4.8, Vector2(4.7, 4.7), 10.0, [2.0, 1.95, 4.0]],
	"castle_tower": [Vector2(3.69, 3.69), 0.22, 12.0, Vector2(4.3, 4.3), 12.3, [3.0, 0.62, 2.4]],
	"crypt_tower": [Vector2(3.69, 3.69), 0.22, 12.0, Vector2(4.3, 4.3), 12.3, [3.0, 0.62, 2.4]],
}

## Stone towers you climb (box rooms whose "ceiling" is the roof): a flight up each wall
## in turn, one storey each, to a hatch onto the battlements. The tread material by type.
const TOWER := {"castle_tower": "flagstone", "crypt_tower": "stone_dark"}
const STAIR_W := 1.0
## The hatch over the last flight reaches from the stair head to this x.
const HATCH_X := 1.5
const PARAPET := 0.95

## Round rooms, rebuilt here with a doorway: [wall radius at the base (outside), at the
## top, wall thickness, wall from y, to y, floor, ceiling, top of the solid block,
## doorway [half width, height, wall segments it opens], segments].
const ROUND := {
	"mushroom_house": [2.75, 2.35, 0.32, -0.3, 3.5, 0.22, 3.35, 5.3, [0.62, 2.4, 2], 20],
	"watchtower": [2.3, 1.9, 0.42, -0.3, 12.0, 0.22, 3.2, 12.5, [0.55, 2.4, 2], 16],
}

## The hab dome: [radius, shell thickness, squash, floor, door segments, door rings,
## segments, rings from the rim to the top].
const DOME := [4.2, 0.12, 0.85, 0.3, 2, 3, 24, 6]

## The ramp out of the hab dome's airlock: [inner z, height there, outer z, height
## there]. It meets the base's rim at its full height, so there is no step onto it.
const RAMP := [4.6, 0.31, 5.35, 0.08]

## The shrine's platform top (an open pavilion you step onto).
const SHRINE_FLOOR := 0.25

const _F_KEEP := 0.22
const _F_KIT := 0.2
const _F_HUT := 0.22
const _F_DOME := 0.3

## Furniture: [model or "@piece", yaw (degrees), position, solid]. Kit props and pieces
## face +z; against the back wall yaw 0, the left wall 90, the right wall -90.
const FURNISH := {
	"castle_keep": [
		["props/Table_Large", 90, Vector3(-1.2, _F_KEEP, 0.3), true],
		["props/Bench", 90, Vector3(-2.2, _F_KEEP, 0.3), false],
		["props/Bench", 90, Vector3(-0.2, _F_KEEP, 0.3), false],
		["props/Chandelier", 0, Vector3(-1.2, 2.9, 0.3), false],
		["props/Table_Plate", 0, Vector3(-1.2, _F_KEEP + 0.818, -0.6), false],
		["props/Table_Plate", 0, Vector3(-1.2, _F_KEEP + 0.818, 0.5), false],
		["props/Table_Plate", 0, Vector3(-1.25, _F_KEEP + 0.818, 1.3), false],
		["props/Mug", 40, Vector3(-0.95, _F_KEEP + 0.818, -0.2), false],
		["props/Mug", 200, Vector3(-1.45, _F_KEEP + 0.818, 0.9), false],
		["props/Chalice", 0, Vector3(-1.0, _F_KEEP + 0.818, 1.0), false],
		["props/CandleStick_Triple", 90, Vector3(-1.2, _F_KEEP + 0.818, 0.05), false],
		["props/Coin_Pile", 0, Vector3(-1.4, _F_KEEP + 0.818, -1.0), false],
		["props/Chair_1", 0, Vector3(0.0, _F_KEEP, -3.15), false],
		["props/Banner_1", 0, Vector3(-0.8, 2.05, -3.6), false],
		["props/Torch_Metal", 0, Vector3(-1.3, 1.9, -3.69), false],
		["props/Bookcase_2", 0, Vector3(2.6, _F_KEEP, -3.45), true],
		["props/WeaponStand", 90, Vector3(-3.19, _F_KEEP, -1.0), true],
		["props/Shield_Wooden", 90, Vector3(-3.69, 1.75, -0.4), false],
		["props/Shield_Wooden", 90, Vector3(-3.69, 1.75, 0.6), false],
		["props/Banner_2", 90, Vector3(-3.6, 2.05, 2.9), false],
		["props/Barrel", 0, Vector3(-3.0, _F_KEEP, 3.2), true],
		["props/Torch_Metal", -90, Vector3(3.69, 1.9, -0.4), false],
		["props/Dummy", -90, Vector3(2.9, _F_KEEP, 0.6), true],
		["props/Crate_Wooden", 0, Vector3(3.15, _F_KEEP, 2.5), true],
		["props/Crate_Wooden", 25, Vector3(3.15, _F_KEEP + 0.88, 2.5), false],
		["props/Barrel", 0, Vector3(2.3, _F_KEEP, 3.2), true],
		["props/Torch_Metal", 180, Vector3(2.5, 1.9, 3.69), false],
	],
	"crypt_keep": [
		["@tomb", 0, Vector3(-0.4, _F_KEEP, -0.5), true],
		["props/Candle_2", 0, Vector3(-0.7, _F_KEEP + 0.93, 0.45), false],
		["props/Candle_1", 0, Vector3(-0.15, _F_KEEP + 0.93, 0.5), false],
		["props/Candle_1", 0, Vector3(-0.65, _F_KEEP + 0.93, -1.45), false],
		["props/Scroll_1", 30, Vector3(-0.15, _F_KEEP + 0.93, -1.35), false],
		["props/CandleStick_Stand", 0, Vector3(-1.3, _F_KEEP, -1.7), false],
		["props/CandleStick_Stand", 0, Vector3(0.5, _F_KEEP, -1.7), false],
		["props/CandleStick_Stand", 0, Vector3(-1.3, _F_KEEP, 0.9), false],
		["@tomb", 0, Vector3(-3.1, _F_KEEP, -2.2), true],
		["@tomb", 0, Vector3(-3.1, _F_KEEP, 1.1), true],
		["props/Banner_2", 0, Vector3(0.4, 2.05, -3.6), false],
		["props/Bookcase_2", -90, Vector3(3.45, _F_KEEP, -1.0), true],
		["props/Cage_Small", 20, Vector3(3.0, _F_KEEP, 1.4), true],
		["props/Chain_Coil", 0, Vector3(2.2, _F_KEEP, 0.4), false],
		["props/Vase_Rubble_Medium", 0, Vector3(-1.9, _F_KEEP, 3.1), false],
		["props/Vase_2", 0, Vector3(-3.1, _F_KEEP, 3.15), true],
		["props/Pot_1", 0, Vector3(3.0, _F_KEEP + 0.02, 3.0), false],
		["props/Vase_4", 0, Vector3(3.25, _F_KEEP, 2.4), false],
	],
	"hab_block": [
		["@bunk", 0, Vector3(-2.45, _F_KIT, -3.05), true],
		["@bunk", 90, Vector3(-3.05, _F_KIT, 0.0), true],
		["@locker", 0, Vector3(-0.95, _F_KIT, -3.25), true],
		["@locker", 0, Vector3(-0.3, _F_KIT, -3.25), true],
		["@locker", 0, Vector3(0.35, _F_KIT, -3.25), true],
		["scifi/Prop_Computer", -90, Vector3(3.25, _F_KIT, -1.6), true],
		["@desk", -90, Vector3(3.1, _F_KIT, 0.2), true],
		["@chair", 90, Vector3(2.3, _F_KIT, 0.2), false],
		["@table", 0, Vector3(-0.9, _F_KIT, 0.9), true],
		["@chair", 0, Vector3(-0.9, _F_KIT, 0.1), false],
		["@chair", 180, Vector3(-0.9, _F_KIT, 1.7), false],
		["props/Mug", 30, Vector3(-1.2, _F_KIT + 0.76, 0.8), false],
		["props/Bottle_1", 0, Vector3(-0.5, _F_KIT + 0.76, 1.05), false],
		["scifi/Prop_Crate3", 0, Vector3(-3.0, _F_KIT + 0.5, 3.0), true],
		["scifi/Prop_Crate3", 40, Vector3(-3.0, _F_KIT + 1.5, 3.0), false],
		["scifi/Prop_Crate4", 15, Vector3(-1.85, _F_KIT + 0.56, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(-0.8, _F_KIT, 3.15), true],
	],
	"lab_block": [
		["@console", 0, Vector3(-3.6, _F_KIT, -3.1), true],
		["scifi/Prop_Computer", 0, Vector3(-1.6, _F_KIT, -3.25), true],
		["scifi/Prop_Computer", 0, Vector3(1.6, _F_KIT, -3.25), true],
		["@console", 0, Vector3(3.0, _F_KIT, -3.1), true],
		["@chair", 180, Vector3(-3.6, _F_KIT, -2.2), false],
		["@chair", 180, Vector3(3.0, _F_KIT, -2.2), false],
		["@tank", 0, Vector3(-5.0, _F_KIT, -1.4), true],
		["@tank", 0, Vector3(-5.0, _F_KIT, 0.0), true],
		["@tank", 0, Vector3(-5.0, _F_KIT, 1.4), true],
		["@holo", 0, Vector3(0.0, _F_KIT, -0.7), true],
		["@desk", -90, Vector3(5.1, _F_KIT, 0.3), true],
		["@chair", 90, Vector3(4.3, _F_KIT, 0.3), false],
		["scifi/Prop_Crate4", 0, Vector3(-4.9, _F_KIT + 0.56, 2.9), true],
		["scifi/Prop_Crate3", 30, Vector3(-3.8, _F_KIT + 0.5, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(4.9, _F_KIT, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(4.35, _F_KIT, 3.15), true],
		["scifi/Prop_Crate3", 0, Vector3(3.5, _F_KIT + 0.5, 3.0), true],
	],
	"ops_tower": [
		["@console", 0, Vector3(-2.5, _F_KIT, -3.1), true],
		["@console", 0, Vector3(-0.8, _F_KIT, -3.1), true],
		["@console", 0, Vector3(0.9, _F_KIT, -3.1), true],
		["@chair", 180, Vector3(-2.5, _F_KIT, -2.2), false],
		["@chair", 180, Vector3(-0.8, _F_KIT, -2.2), false],
		["@chair", 180, Vector3(0.9, _F_KIT, -2.2), false],
		["@screen", 90, Vector3(-3.5, 1.8, -0.2), false],
		["@holo", 0, Vector3(-1.2, _F_KIT, 0.9), true],
		["@locker", -90, Vector3(3.25, _F_KIT, -1.3), true],
		["@locker", -90, Vector3(3.25, _F_KIT, -0.65), true],
		["scifi/Prop_Crate4", 0, Vector3(-3.0, _F_KIT + 0.56, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(-2.0, _F_KIT, 3.15), true],
	],
	"bunker_keep": [
		["@rack", 0, Vector3(-4.3, _F_KIT, -3.35), true],
		["@rack", 0, Vector3(-2.0, _F_KIT, -3.35), true],
		["@console", -90, Vector3(5.1, _F_KIT, -1.2), true],
		["@chair", 90, Vector3(4.3, _F_KIT, -1.2), false],
		["@holo", 0, Vector3(3.0, _F_KIT, 0.9), true],
		["@desk", 90, Vector3(-5.1, _F_KIT, -0.6), true],
		["scifi/Grenade_1", 90, Vector3(-5.05, _F_KIT + 0.89, -0.6), false],
		["scifi/Prop_Crate3", 0, Vector3(-5.0, _F_KIT + 0.5, 1.4), true],
		["scifi/Prop_Crate3", 20, Vector3(-5.0, _F_KIT + 1.5, 1.4), false],
		["scifi/Prop_Crate4", 0, Vector3(-5.0, _F_KIT + 0.56, 2.6), true],
		["scifi/Prop_Crate4", 0, Vector3(-3.9, _F_KIT + 0.56, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(4.9, _F_KIT, 3.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(4.3, _F_KIT, 3.15), true],
	],
	"bunker_tower": [
		["@console", 0, Vector3(-2.4, _F_KIT, -3.1), true],
		["@console", 0, Vector3(-0.7, _F_KIT, -3.1), true],
		["@chair", 180, Vector3(-2.4, _F_KIT, -2.2), false],
		["@chair", 180, Vector3(-0.7, _F_KIT, -2.2), false],
		["@bunk", 90, Vector3(-3.05, _F_KIT, 1.4), true],
		["@rack", -90, Vector3(3.37, _F_KIT, -0.8), true],
		["@locker", 0, Vector3(2.9, _F_KIT, -3.25), true],
		["scifi/Prop_Crate4", 0, Vector3(-1.8, _F_KIT + 0.56, 3.0), true],
	],
	"mushroom_house": [
		["@cot", 90, Vector3(-1.55, _F_HUT, -0.1), true],
		["props/Cauldron", 0, Vector3(0.6, _F_HUT, -1.5), true],
		["props/Shelf_Simple", 0, Vector3(-0.4, _F_HUT + 1.4, -2.15), false],
		["props/Potion_1", 0, Vector3(-0.7, _F_HUT + 1.51, -1.95), false],
		["props/Potion_2", 0, Vector3(-0.45, _F_HUT + 1.51, -1.95), false],
		["props/Bottle_1", 0, Vector3(-0.15, _F_HUT + 1.51, -1.95), false],
		["props/Stool", 0, Vector3(0.3, _F_HUT, -0.5), false],
		["props/Book_Stack_1", 20, Vector3(-1.4, _F_HUT + 0.55, 1.1), false],
	],
	"hab_dome": [
		["@cot", 0, Vector3(-1.0, _F_DOME, -2.75), true],
		["@cot", 90, Vector3(-2.75, _F_DOME, -0.3), true],
		["@holo", 0, Vector3(0.0, _F_DOME, 0.0), true],
		["@console", -90, Vector3(3.0, _F_DOME, -0.3), true],
		["scifi/Prop_Computer", -120, Vector3(2.6, _F_DOME, 1.5), true],
		["scifi/Prop_Crate3", 0, Vector3(-2.3, _F_DOME + 0.5, 2.0), true],
		["scifi/Prop_Barrel_Large", 0, Vector3(-1.9, _F_DOME, 2.6), true],
		["@planter", -45, Vector3(2.2, _F_DOME, 2.2), true],
	],
	"watchtower": [
		["@ladder", 0, Vector3(0.0, _F_HUT, -1.65), false],
		["props/Barrel", 0, Vector3(-1.0, _F_HUT, -0.8), true],
		["props/Crate_Wooden", 0, Vector3(-0.95, _F_HUT, 0.5), true],
		["props/Torch_Metal", 90, Vector3(-1.82, 1.9, 0.0), false],
		["props/Shield_Wooden", -90, Vector3(1.78, 1.8, -0.1), false],
	],
	"castle_tower": [
		["props/WeaponStand", 0, Vector3(-1.0, _F_KEEP, -3.19), true],
		["props/Shield_Wooden", 0, Vector3(-2.15, 1.75, -3.69), false],
		["props/Torch_Metal", 0, Vector3(0.35, 1.9, -3.69), false],
		["props/Barrel", 0, Vector3(3.1, _F_KEEP, -3.1), true],
		["props/Barrel", 0, Vector3(3.15, _F_KEEP, -2.2), true],
		["props/Crate_Wooden", 20, Vector3(-1.8, _F_KEEP, 0.2), true],
		["props/Torch_Metal", -90, Vector3(3.69, 1.9, 0.4), false],
		["props/Chandelier", 0, Vector3(0.0, 12.0, 0.0), false],
		["props/Crate_Wooden", 0, Vector3(2.6, 12.3, -2.6), true],
		["props/Barrel", 0, Vector3(1.5, 12.3, -3.0), true],
	],
	"crypt_tower": [
		["@tomb", 0, Vector3(0.6, _F_KEEP, -0.4), true],
		["props/CandleStick_Stand", 0, Vector3(-0.3, _F_KEEP, 1.25), false],
		["props/CandleStick_Stand", 0, Vector3(1.5, _F_KEEP, 1.25), false],
		["props/Vase_Rubble_Medium", 0, Vector3(3.1, _F_KEEP, -3.0), false],
		["props/Cage_Small", 30, Vector3(3.0, _F_KEEP, -1.8), true],
		["props/Chain_Coil", 0, Vector3(-1.6, _F_KEEP, -2.9), false],
		["props/Torch_Metal", 0, Vector3(0.35, 1.9, -3.69), false],
		["props/Vase_2", 0, Vector3(2.7, 12.3, -2.8), false],
	],
	"shrine": [
		["props/CandleStick_Stand", 0, Vector3(-1.2, SHRINE_FLOOR, -0.6), false],
		["props/CandleStick_Stand", 0, Vector3(1.2, SHRINE_FLOOR, -0.6), false],
		["props/Candle_2", 0, Vector3(0.45, SHRINE_FLOOR, 0.1), false],
		["props/Candle_1", 0, Vector3(-0.4, SHRINE_FLOOR, 0.3), false],
		["props/Candle_2", 0, Vector3(0.1, SHRINE_FLOOR, -0.45), false],
		["props/Vase_2", 0, Vector3(-1.3, SHRINE_FLOOR, 0.7), false],
		["props/Scroll_1", 10, Vector3(0.2, SHRINE_FLOOR + 0.96, -1.35), false],
	],
}

## Procedural pieces: size [width x, height, depth z] of their collision box, standing
## on the floor and facing +z.
const PIECES := {
	"@bunk": Vector3(2.0, 1.9, 0.95), "@cot": Vector3(2.0, 0.55, 0.9), "@locker": Vector3(0.6, 2.1, 0.55),
	"@console": Vector3(1.6, 1.25, 0.8), "@desk": Vector3(1.8, 0.78, 0.8), "@chair": Vector3(0.5, 1.0, 0.5),
	"@tank": Vector3(0.95, 2.3, 0.95), "@holo": Vector3(1.6, 1.0, 1.6), "@rack": Vector3(2.0, 2.0, 0.35),
	"@tomb": Vector3(1.0, 1.0, 2.3), "@screen": Vector3(2.6, 1.4, 0.06), "@planter": Vector3(1.2, 0.9, 0.6),
	"@ladder": Vector3(0.6, 3.0, 0.1), "@table": Vector3(1.4, 0.76, 0.9),
}

## Rugs: [material, centre, size].
const RUGS := {
	"castle_keep": ["cloth", Vector3(0.6, _F_KEEP, 0.2), Vector2(1.0, 6.0)],
	"mushroom_house": ["cloth_blue", Vector3(0.0, _F_HUT, 0.1), Vector2(1.6, 1.6)],
	"hab_block": ["cloth_blue", Vector3(-0.9, _F_KIT, 0.9), Vector2(2.4, 2.2)],
}

## Loot spots: [position on the floor, yaw (degrees)]. Village houses keep theirs where
## their chest stands.
const LOOT := {
	"cottage": [[Vector3(-1.6, KitHouse.FLOOR, 0.3), 0.0]],
	"townhouse": [[Vector3(2.25, KitHouse.FLOOR, -0.6), -90.0]],
	"longhouse": [[Vector3(-2.25, KitHouse.FLOOR, 3.0), 90.0]],
	"castle_keep": [[Vector3(-2.4, _F_KEEP, -3.15), 0.0]],
	"crypt_keep": [[Vector3(2.5, _F_KEEP, -3.15), 0.0]],
	"hab_block": [[Vector3(2.3, _F_KIT, -3.15), 0.0]],
	"lab_block": [[Vector3(4.75, _F_KIT, -3.15), 0.0]],
	"ops_tower": [[Vector3(2.7, _F_KIT, -3.15), 0.0]],
	"bunker_keep": [[Vector3(1.0, _F_KIT, -3.15), 0.0], [Vector3(3.1, _F_KIT, -3.15), 0.0]],
	"bunker_tower": [[Vector3(1.4, _F_KIT, -3.15), 0.0]],
	"mushroom_house": [[Vector3(1.55, _F_HUT, 0.3), -90.0]],
	"hab_dome": [[Vector3(1.4, _F_DOME, -2.7), 0.0]],
	"watchtower": [[Vector3(1.3, _F_HUT, -0.1), -90.0]],
	"shrine": [[Vector3(0.0, SHRINE_FLOOR, -1.35), 0.0]],
	# On the battlements, for whoever climbs up.
	"castle_tower": [[Vector3(-1.4, 12.3, -1.6), 0.0]],
	"crypt_tower": [[Vector3(-1.4, 12.3, -1.6), 0.0]],
}

## How good the loot is (ItemDB.roll_loot luck). Stronghold keeps and towers go by
## their stronghold's tier when they know it.
const LUCK := {"castle_keep": 0.5, "crypt_keep": 0.5, "bunker_keep": 0.6, "bunker_tower": 0.35, "ops_tower": 0.15,
	"lab_block": 0.15, "shrine": 0.2, "watchtower": 0.1, "castle_tower": 0.15, "crypt_tower": 0.2}

## Lights: [position, colour, energy, range].
const LIGHTS := {
	"castle_keep": [[Vector3(-0.4, 2.3, 0.2), Color(1.0, 0.66, 0.38), 1.7, 8.0]],
	"crypt_keep": [[Vector3(-0.4, 2.2, -0.5), Color(0.72, 0.55, 1.0), 1.4, 7.5], [Vector3(-0.4, 1.4, 0.6), Color(1.0, 0.65, 0.35), 0.6, 3.0]],
	"hab_block": [[Vector3(0.0, 3.4, 0.0), Color(0.85, 0.93, 1.0), 1.5, 8.5]],
	"lab_block": [[Vector3(0.0, 3.4, 0.0), Color(0.8, 0.95, 1.0), 1.6, 10.0]],
	"ops_tower": [[Vector3(0.0, 3.6, 0.0), Color(0.8, 0.92, 1.0), 1.5, 9.0]],
	"bunker_keep": [[Vector3(0.0, 3.4, 0.0), Color(1.0, 0.86, 0.8), 1.5, 10.0]],
	"bunker_tower": [[Vector3(0.0, 3.6, 0.0), Color(1.0, 0.86, 0.8), 1.4, 9.0]],
	"mushroom_house": [[Vector3(0.0, 2.4, 0.0), Color(1.0, 0.7, 0.45), 1.3, 5.5]],
	"hab_dome": [[Vector3(0.0, 2.7, 0.0), Color(0.82, 0.95, 1.0), 1.4, 7.5]],
	"watchtower": [[Vector3(0.0, 2.3, 0.0), Color(1.0, 0.64, 0.35), 1.2, 5.0]],
	"shrine": [[Vector3(0.0, 1.6, 0.0), Color(0.45, 1.0, 0.9), 1.3, 6.0]],
	"castle_tower": [[Vector3(0.0, 2.6, 0.0), Color(1.0, 0.66, 0.38), 1.5, 8.0], [Vector3(0.0, 11.2, 0.0), Color(1.0, 0.66, 0.38), 1.4, 8.0]],
	"crypt_tower": [[Vector3(0.0, 2.4, 0.0), Color(0.72, 0.55, 1.0), 1.3, 7.5], [Vector3(0.0, 10.4, 0.0), Color(0.72, 0.55, 1.0), 1.1, 7.5]],
}

## A room to walk into (KitHouse types are walkable too, but build their own).
static func has(t: String) -> bool:
	return FURNISH.has(t)

## Types whose whole mesh is built here rather than by their kit.
static func rebuilds(t: String) -> bool:
	return ROUND.has(t) or t == "hab_dome" or t == "shrine"

## Types with lamplit window panels drawn from further off (key "<type>~glow").
static func glows(t: String) -> bool:
	return t in ["hab_block", "lab_block", "ops_tower", "bunker_keep", "bunker_tower"]

static var _fires: Dictionary = {}

## Flames in the object's own space (sunk like the object): [foot, height in metres]: a
## house's hearth, and the wall torches and candles burning in its rooms.
static func fires(t: String) -> Array:
	if _fires.has(t):
		return _fires[t]
	var out: Array = []
	if KitHouse.has(t):
		out.append([KitHouse.fire_at(t), 1.0])
	for f in FireFx.prop_flames(FURNISH.get(t, KitHouse.FURNISH.get(t, []))):
		out.append([(f[0] as Vector3) - Vector3(0, SINK, 0), f[1]])
	_fires[t] = out
	return out

## The windows the sun shines in through, drawn as beams in the room's air (SunBeams), in
## the object's own space (sunk like the object): [centre of the opening on the wall's
## inner face, inward normal, half width, half height, the room's floor and ceiling
## heights, its half size across x and z]. A stone tower's arrow slits, one storey under
## its top (Stronghold._face, row 2, every other module), or a house's unshuttered
## windows (KitHouse).
static func sun_windows(t: String) -> Array:
	if KitHouse.has(t):
		var dm := KitHouse._dims(t)
		var half := Vector2(dm.x * 0.5 - 0.2, dm.z * 0.5 - 0.2)
		var wins: Array = []
		for w in KitHouse.sun_windows(t):
			wins.append([(w[0] as Vector3) - Vector3(0, SINK, 0), w[1], w[2], w[3], KitHouse.FLOOR - SINK, dm.y - 0.1 - SINK, half])
		return wins
	if not TOWER.has(t):
		return []
	var out: Array = []
	var b0: Array = BOX[t]
	for side in 4:
		var b := Basis(Vector3.UP, side * PI / 2.0)
		for x in [-1.0, 3.0]:
			out.append([b * Vector3(x, 7.775 - SINK, 3.7), b * Vector3(0, 0, -1), 0.3, 0.725, float(b0[1]) - SINK, float(b0[2]) - SINK, b0[0]])
	return out

## Lights in the object's own space (sunk like the object): [position, colour, energy, range].
static func lights(t: String) -> Array:
	if KitHouse.has(t):
		return [[KitHouse.light_at(t), Color(1.0, 0.62, 0.32), 1.5, 6.5]]
	var out: Array = []
	for l in LIGHTS.get(t, []):
		out.append([(l[0] as Vector3) - Vector3(0, SINK, 0), l[1], l[2], l[3]])
	return out

# --- Loot ------------------------------------------------------------------------

## Puts a chest, coffer or crate at each loot spot of every room in the chunk that has
## not had them yet. Deterministic per chunk and object. Returns true if it added any.
static func stock(chunk: Dictionary) -> bool:
	var objs: Array = chunk["objects"]
	var changed := false
	var n := objs.size()
	for i in n:
		var o: Dictionary = objs[i]
		var t: String = o["t"]
		var st: Dictionary = o["st"]
		if not LOOT.has(t) or st.get("stocked", false) or st.get("gone", false):
			continue
		st["stocked"] = true
		changed = true
		var era: int = o["e"]
		var r := WHash.rng(int(chunk.get("seed", 0)), int(chunk["cx"]) * 4099 + i, int(chunk["cz"]), 733)
		var origin := {"chunk": Vector2i(chunk["cx"], chunk["cz"]), "era": era, "how": "found"}
		var luck: float = 0.25 + 0.25 * float(st["tier"]) if st.has("tier") else float(LUCK.get(t, 0.0))
		var s: float = o["s"]
		var b := Basis(Vector3.UP, o["r"])
		var at: Vector3 = o["p"]
		for spot in LOOT[t]:
			var q: Vector3 = spot[0]
			var p: Vector3 = at + b * Vector3(q.x, 0, q.z) * s
			# On the room's floor as drawn: the room sinks by SINK, the cache does too.
			p.y = at.y + (q.y - SINK) * s + SINK
			objs.append({"i": objs.size(), "t": Eras.CACHE_TYPES[era], "e": era, "p": p, "r": float(o["r"]) + deg_to_rad(float(spot[1])),
				"s": 1.0, "st": {"loot": ItemDB.roll_loot(era, r, origin, luck), "opened": false, "inside": t}})
	return changed

# --- Meshes ----------------------------------------------------------------------

static func build(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var models: Array = []
	match t:
		"mushroom_house": _mushroom_house(k, models)
		"watchtower": _watchtower(k, models)
		"hab_dome": _hab_dome(k)
		"shrine": _shrine(k)
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh

## The furnished room.
static func interior(t: String) -> ArrayMesh:
	var models: Array = []
	var k := MeshKit.new(WHash.str_hash(t + "~in") & 0xFFFF)
	var I := Transform3D.IDENTITY
	for f in FURNISH[t]:
		var name: String = f[0]
		if name.begins_with("@"):
			_piece(name, k, models, Transform3D(Basis(Vector3.UP, deg_to_rad(float(f[1]))), f[2]))
		else:
			models.append([name, f[1], f[2], 0.85 if name == "scifi/Sniper_1" else 1.0])
	if RUGS.has(t):
		var rug: Array = RUGS[t]
		var rc: Vector3 = rug[1]
		var rs: Vector2 = rug[2]
		k.box(rug[0], I.translated(Vector3(rc.x, rc.y + 0.006, rc.z)), Vector3(rs.x, 0.012, rs.y))
	match t:
		"castle_keep":
			# Dressed stone flags over the boards, and a tapestry on the east wall.
			k.box("stone_floor", I.translated(Vector3(0, _F_KEEP + 0.004, 0)), Vector3(7.3, 0.008, 7.3))
			tapestry(k, Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(3.69 - 0.02, 1.8, -1.8)))
			_hall_trim(k, "castle_stone")
		"crypt_keep":
			# Stone flags over the boards, and runes glowing over the wall tombs.
			k.box("flagstone", I.translated(Vector3(0, _F_KEEP + 0.004, 0)), Vector3(7.3, 0.008, 7.3))
			_hall_trim(k, "crypt_stone")
			for z in [-2.2, 1.1]:
				k.box("glow_violet", I.translated(Vector3(-3.67, 2.15, z)), Vector3(0.02, 0.07, 1.7))
			k.box("glow_violet", I.translated(Vector3(1.2, 2.6, -3.67)), Vector3(1.4, 0.07, 0.02))
		"hab_block", "lab_block", "ops_tower", "bunker_keep", "bunker_tower":
			_painted_room(k, t)
		"mushroom_house":
			# A lamp hung from the vault and glowcaps sprouting from the walls.
			k.cylinder("iron", I.translated(Vector3(0, 2.75, 0)), 0.01, 0.01, 0.6, 4)
			k.sphere("glow_warm", I.translated(Vector3(0, 2.65, 0)), 0.16, 5, 8)
			for a in [0.4, 1.3, 2.4, 3.7, 4.6, 5.5]:
				var d := Vector3(cos(a), 0, sin(a))
				k.sphere("glow_violet", I.translated(d * 2.15 + Vector3(0, 0.6 + fmod(a, 1.0) * 1.2, 0)), 0.07, 3, 5)
		"hab_dome":
			var top: float = _F_DOME + (DOME[0] - DOME[1]) * DOME[2]
			k.cylinder("glow_white", I.translated(Vector3(0, top - 0.12, 0)), 0.6, 0.6, 0.03, 16)
		"castle_tower", "crypt_tower":
			_stair(k, t)
			# A plinth course round the foot of the walls, open at the door.
			var w := HALL - Trim.KIT_PLASTER
			Trim.room(k, "castle_stone" if t == "castle_tower" else "crypt_stone", Trim.PLINTH, -w, w, -w, w, _F_KEEP,
				[["+z", 3.0 - 0.66, 3.0 + 0.66]])
		"watchtower":
			# The hatch the ladder climbs to.
			k.box("timber", I.translated(Vector3(0, 3.18, -1.25)), Vector3(0.9, 0.04, 0.9))
			k.box("stone_dark", I.translated(Vector3(0, 3.16, -1.25)), Vector3(0.8, 0.02, 0.8))
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	# The kit's wall torches are empty iron baskets: fill each with pitch-soaked rag.
	var wads := MeshKit.new(3)
	var any := false
	for m in models:
		if m[0] == "props/Torch_Metal":
			ToolModels.torch_wad(wads, Transform3D(Basis(Vector3.UP, deg_to_rad(float(m[1]))).scaled(Vector3.ONE * float(m[3])), m[2]))
			any = true
	if any:
		wads.commit(ToolModels.mat, mesh)
	return mesh

## Sci-fi rooms are fitted out as a station or a ward is, over the kit's shell: sheet
## vinyl on the floor, a coved skirting, a suspended ceiling of acoustic tiles just over
## the door head with recessed light panels in it (lit by the room's lamp, LIGHTS), each
## type in its own paint: [floor, skirting and stripe accent].
const PAINT := {"hab_block": [Color(0.62, 0.68, 0.62), Color(0.38, 0.56, 0.36)],
	"lab_block": [Color(0.76, 0.78, 0.8), Color(0.12, 0.52, 0.52)],
	"ops_tower": [Color(0.56, 0.62, 0.7), Color(0.2, 0.4, 0.68)],
	"bunker_keep": [Color(0.6, 0.6, 0.58), Color(0.7, 0.24, 0.2)],
	"bunker_tower": [Color(0.6, 0.6, 0.58), Color(0.7, 0.24, 0.2)]}
const DROP_CEILING := 4.04

static func _painted_room(k: MeshKit, t: String) -> void:
	var b: Array = BOX[t]
	var ih: Vector2 = b[0]
	var oh: Vector2 = b[3]
	var pc: Array = PAINT[t]
	var I := Transform3D.IDENTITY
	# Floor and ceiling reach into the walls: the kit's window modules stand further
	# out than its plain ones.
	k.box("vinyl_floor", I.translated(Vector3(0, _F_KIT + 0.005, 0)), Vector3(oh.x * 2.0 - 1.2, 0.01, oh.y * 2.0 - 1.2), pc[0])
	k.box("ceiling_tile", I.translated(Vector3(0, DROP_CEILING + 0.02, 0)), Vector3(oh.x * 2.0 - 1.2, 0.04, oh.y * 2.0 - 1.2))
	# A coved vinyl skirting along each wall module's own inner face, open across the
	# doorway, and a painted angle where the ceiling grid meets the walls.
	var cove := PackedVector2Array(Trim.cove(0.12, 0.035))
	var angle := PackedVector2Array([Vector2(0, 0.03), Vector2(0.025, 0.03), Vector2(0.025, 0)])
	for run in _wall_runs(_kit_of(t)):
		var a: Vector3 = run[0]
		var e: Vector3 = run[1]
		var into: Vector3 = run[2]
		var sides := PackedVector3Array([into, into])
		k.sweep("vinyl_floor", I.translated(Vector3(0, _F_KIT, 0)), PackedVector3Array([a, e]), sides, Vector3.UP, cove, false, true, (pc[0] as Color).darkened(0.4))
		k.sweep("enamel", I.translated(Vector3(0, DROP_CEILING, 0)), PackedVector3Array([a, e]), sides, Vector3.DOWN, angle, false, true, Color(0.9, 0.9, 0.88))
	# Recessed light panels in the ceiling grid.
	var n := 3 if ih.x > 4.0 else 2
	for i in n:
		var x := -ih.x + ih.x * 2.0 * (i + 0.5) / n
		for z in [-1.2, 1.2]:
			k.box("enamel", I.translated(Vector3(x, DROP_CEILING - 0.005, z)), Vector3(1.24, 0.012, 0.64), Color(0.92, 0.92, 0.9))
			k.box("glow_white", I.translated(Vector3(x, DROP_CEILING - 0.012, z)), Vector3(1.16, 0.004, 0.56))

## The ground floor's walls as runs along their inner faces: [start, end, inward], at
## floor level 0. Each kit wall module's face stands at its own depth (a plain module is
## thicker than a window module), and the runs at a corner stop at the other wall's face.
## The doorway's module is left out.
static func _wall_runs(kit: String) -> Array:
	var p: Array = KitBase.PLANS[kit]
	var nx: int = p[0]
	var nz: int = p[1]
	var hw := nx * 2.0
	var hd := nz * 2.0
	var models: Array = []
	KitBase._building(kit, MeshKit.new(1), models, [])
	# Inner depth in from the wall's line per side and module (-1: the doorway).
	var depth := {"-x": [], "+x": [], "-z": [], "+z": []}
	for side in depth:
		var cnt := nz if side.ends_with("x") else nx
		for i in cnt:
			depth[side].append(-1.0)
	var walls: Array = KitBase.WALL.values().reduce(func(acc, v): return acc + v, [])
	for m in models:
		if not walls.has(m[0]) or (m[2] as Vector3).y > 0.5:
			continue
		var c: Vector3 = m[2]
		var d: float = KitHouse._model_box(m[0], Transform3D.IDENTITY).end.x + 2.0
		match int(m[1]):
			0: depth["-x"][int((c.z + hd) / 4.0)] = d
			180: depth["+x"][int((c.z + hd) / 4.0)] = d
			-90: depth["-z"][int((c.x + hw) / 4.0)] = d
			90: depth["+z"][int((c.x + hw) / 4.0)] = d
	var at := func(side: String, i: int) -> float: return maxf(depth[side][i], 0.0)
	var runs: Array = []
	for side in depth:
		var along_x: bool = side.ends_with("z")
		var cnt: int = depth[side].size()
		var sgn := -1.0 if side.begins_with("-") else 1.0
		var into := Vector3(0, 0, -sgn) if along_x else Vector3(-sgn, 0, 0)
		var half := hw if along_x else hd
		for i in cnt:
			var d: float = depth[side][i]
			if d < 0.0:
				continue
			var lo := -half + i * 4.0
			var hi := lo + 4.0
			# At a corner, stop at the other wall's face.
			if i == 0:
				lo += at.call(("-x" if along_x else "-z"), (0 if side in ["-z", "-x"] else (nz - 1 if along_x else nx - 1)))
			if i == cnt - 1:
				hi -= at.call(("+x" if along_x else "+z"), (0 if side in ["-z", "-x"] else (nz - 1 if along_x else nx - 1)))
			var line := sgn * ((hd if along_x else hw) - d)
			var a := Vector3(lo, 0, line) if along_x else Vector3(line, 0, lo)
			var e := Vector3(hi, 0, line) if along_x else Vector3(line, 0, hi)
			# Run each wall the way Trim.room does (clockwise from above), so it faces in.
			if (e - a).dot(Vector3.UP.cross(into)) < 0.0:
				var tmp := a
				a = e
				e = tmp
			runs.append([a, e, into])
	return runs

## Where a keep's or stone tower's kit walls stand, out from the middle (Stronghold).
const HALL := 4.0
## The keep hall's beams, along x across the hall (Stronghold): their z and underside.
const HALL_BEAMS := [-3.2, -1.6, 0.0, 1.6, 3.2]
const HALL_CEILING := 2.9

## A keep hall's finish: a stone plinth course round the foot of the walls, open at
## the doorway, which gets a dressed stone casing round its arch; a hewn timber wall
## plate round the walls under the boards; stone corbels under it where each beam's
## end rests on the wall.
static func _hall_trim(k: MeshKit, stone: String) -> void:
	var w := HALL - Trim.KIT_PLASTER
	var dx: float = BOX["castle_keep"][5][0]
	var fl := _F_KEEP + 0.008
	Trim.room(k, stone, Trim.PLINTH, -w, w, -w, w, fl, [["+z", dx - 0.66, dx + 0.66]])
	Trim.room(k, "timber", Trim.WALL_PLATE, -w, w, -w, w, HALL_CEILING, [], true)
	for side: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis(Vector3.UP, -side * PI / 2), Vector3(side * w, HALL_CEILING - 0.2, 0))
		Trim.corbels(k, stone, xf, HALL_BEAMS, 0.24, 0.34, 0.26)
	var edge := PackedVector2Array()
	for i in range(Trim.KIT_DOOR.size() - 1, -1, -1):
		var p: Vector2 = Trim.KIT_DOOR[i]
		edge.append(Vector2(-p.x, maxf(p.y, fl)))
	Trim.casing(k, stone, Transform3D(Basis(Vector3.UP, PI), Vector3(dx, 0, w)), edge,
		[Vector2(0, 0.03), Vector2(0.012, 0.04), Vector2(0.13, 0.04), Vector2(0.14, 0.03), Vector2(0.14, 0)])

## Lamplit window panels of a sci-fi block's ground floor, drawn from further off.
static func glow(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t + "~glow") & 0xFFFF)
	for xf in KitBase.window_glows(_kit_of(t)):
		k.box("glow_white", xf, Vector3(3.0, 1.4, 0.04))
	return k.commit(Materials.get_mat)

static func _kit_of(t: String) -> String:
	return {"bunker_keep": "lab_block", "bunker_tower": "ops_tower"}.get(t, t)

# --- Collision ---------------------------------------------------------------------

## Collision you can walk into: [shape, offset].
static func shape(t: String) -> Array:
	var f := PackedVector3Array()
	if BOX.has(t):
		_box_room(f, t)
	elif ROUND.has(t):
		_round_room(f, t)
	elif t == "hab_dome":
		_dome_room(f)
	elif t == "shrine":
		_shrine_shape(f)
	for e in FURNISH[t]:
		if not e[3]:
			continue
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(e[1]))), e[2])
		var name: String = e[0]
		var bx: AABB
		if name.begins_with("@"):
			var sz: Vector3 = PIECES[name]
			bx = xf * AABB(Vector3(-sz.x * 0.5, 0, -sz.z * 0.5), sz)
		else:
			bx = KitHouse._model_box(name, xf)
		_box_faces(f, bx.get_center(), bx.size)
	var cs := ConcavePolygonShape3D.new()
	cs.backface_collision = true
	cs.set_faces(f)
	return [cs, Vector3(0, -SINK, 0)]

static func _box_room(f: PackedVector3Array, t: String) -> void:
	var b: Array = BOX[t]
	var ih: Vector2 = b[0]
	var fl: float = b[1]
	var ce: float = b[2]
	var oh: Vector2 = b[3]
	var top: float = b[4]
	var door: Array = b[5]
	# The floor, reaching down into slopes, and the solid block over the ceiling (a
	# tower's roof, open over its stair, with a parapet round it and the stair below).
	_box_faces(f, Vector3(0, fl - 0.5, 0), Vector3(oh.x * 2, 1.0, oh.y * 2))
	if TOWER.has(t):
		for bx in roof_boxes(t):
			_box_faces(f, bx[0], bx[1])
		for side in [-1.0, 1.0]:
			_box_faces(f, Vector3(0, top + PARAPET * 0.5, side * (oh.y - 0.2)), Vector3(oh.x * 2, PARAPET, 0.4))
			_box_faces(f, Vector3(side * (oh.x - 0.2), top + PARAPET * 0.5, 0), Vector3(0.4, PARAPET, oh.y * 2))
		_stair_faces(f, t)
	else:
		_box_faces(f, Vector3(0, (ce + top) * 0.5, 0), Vector3(oh.x * 2, top - ce, oh.y * 2))
	var tx := oh.x - ih.x
	var tz := oh.y - ih.y
	_box_faces(f, Vector3(0, ce * 0.5, -(ih.y + tz * 0.5)), Vector3(oh.x * 2, ce, tz))
	_box_faces(f, Vector3(-(ih.x + tx * 0.5), ce * 0.5, 0), Vector3(tx, ce, oh.y * 2))
	_box_faces(f, Vector3(ih.x + tx * 0.5, ce * 0.5, 0), Vector3(tx, ce, oh.y * 2))
	# The front wall round the doorway.
	var dx: float = door[0]
	var hw: float = door[1]
	var dh: float = door[2]
	var zf := ih.y + tz * 0.5
	var left := dx - hw + oh.x
	var right := oh.x - (dx + hw)
	if left > 0.01:
		_box_faces(f, Vector3(-oh.x + left * 0.5, ce * 0.5, zf), Vector3(left, ce, tz))
	if right > 0.01:
		_box_faces(f, Vector3(dx + hw + right * 0.5, ce * 0.5, zf), Vector3(right, ce, tz))
	if ce > dh:
		_box_faces(f, Vector3(dx, (dh + ce) * 0.5, zf), Vector3(hw * 2.0, ce - dh, tz))

## A tower's flights: [foot, head, half the width toward the shaft], foot and head on
## the stair's centre line. Up the left wall, along the back, down the right side and
## across the front to the roof, each a storey higher.
static func flights(t: String) -> Array:
	var b: Array = BOX[t]
	var a: float = (b[0] as Vector2).x
	var fl: float = b[1]
	var rise: float = (float(b[4]) - fl) / 4.0
	var c := a - STAIR_W * 0.5
	var e := a - STAIR_W
	var w := STAIR_W * 0.5
	return [
		[Vector3(-c, fl, e), Vector3(-c, fl + rise, -e), Vector3(w, 0, 0)],
		[Vector3(-e, fl + rise, -c), Vector3(e, fl + rise * 2.0, -c), Vector3(0, 0, w)],
		[Vector3(c, fl + rise * 2.0, -e), Vector3(c, fl + rise * 3.0, e), Vector3(-w, 0, 0)],
		[Vector3(e, fl + rise * 3.0, c), Vector3(-e, fl + rise * 4.0, c), Vector3(0, 0, -w)],
	]

## The landings in the corners between flights: [centre of the top, thickness]. The
## first stands on the floor; the last is the roof.
static func landings(t: String) -> Array:
	var fs := flights(t)
	var fl: float = BOX[t][1]
	var c: float = (BOX[t][0] as Vector2).x - STAIR_W * 0.5
	var out: Array = []
	for i in 3:
		var hd: Vector3 = fs[i][1]
		out.append([Vector3(signf(hd.x) * c, hd.y, signf(hd.z) * c), hd.y - fl if i == 0 else 0.3])
	return out

## A tower's roof slab, open over the last flight: [centre, size] boxes.
static func roof_boxes(t: String) -> Array:
	var b: Array = BOX[t]
	var ih: Vector2 = b[0]
	var ce: float = b[2]
	var oh: Vector2 = b[3]
	var top: float = b[4]
	var e := ih.y - STAIR_W
	var y := (ce + top) * 0.5
	var h := top - ce
	return [
		[Vector3(0, y, (e - oh.y) * 0.5), Vector3(oh.x * 2.0, h, oh.y + e)],
		[Vector3((-oh.x - (ih.x - STAIR_W)) * 0.5, y, (e + ih.y) * 0.5), Vector3(oh.x - (ih.x - STAIR_W), h, ih.y - e)],
		[Vector3((HATCH_X + oh.x) * 0.5, y, (e + ih.y) * 0.5), Vector3(oh.x - HATCH_X, h, ih.y - e)],
		[Vector3(0, y, (ih.y + oh.y) * 0.5), Vector3(oh.x * 2.0, h, oh.y - ih.y)],
	]

## The stair as you walk it: each flight one slope (the first solid to the floor, the
## rest slabs), a rail along the shaft side, and the landings.
static func _stair_faces(f: PackedVector3Array, t: String) -> void:
	var fl: float = BOX[t][1]
	var up := Vector3(0, 1.0, 0)
	var fs := flights(t)
	for i in fs.size():
		var fo: Vector3 = fs[i][0]
		var hd: Vector3 = fs[i][1]
		var hw: Vector3 = fs[i][2]
		_quad_faces(f, [fo - hw, fo + hw, hd - hw, hd + hw])
		if i == 0:
			f.append_array([fo + hw, hd + hw, Vector3(hd.x, fl, hd.z) + hw])
		else:
			_quad_faces(f, [fo - hw - up * 0.3, fo + hw - up * 0.3, hd - hw - up * 0.3, hd + hw - up * 0.3])
			_quad_faces(f, [fo + hw, fo + hw - up * 0.3, hd + hw, hd + hw - up * 0.3])
		_quad_faces(f, [fo + hw, fo + hw + up, hd + hw, hd + hw + up])
	for l in landings(t):
		var top: Vector3 = l[0]
		var th: float = l[1]
		_box_faces(f, top - up * th * 0.5, Vector3(STAIR_W, th, STAIR_W))

## The stair as drawn: stone steps on the same slopes, landings, and a rail of posts and
## a handrail along the shaft side. Each step is a block under a separate tread stone
## that overhangs its riser a little, no two stones quite the same shade or quite level;
## the flights that hang in the shaft rest on a stringer along their open side.
static func _stair(k: MeshKit, t: String) -> void:
	var mat: String = TOWER[t]
	var rail := "timber" if t == "castle_tower" else "iron"
	var fl: float = BOX[t][1]
	var n := 15
	var I := Transform3D.IDENTITY
	var r := WHash.rng(WHash.str_hash(t + "~stair"), 0, 0, 7)
	var fs := flights(t)
	for i in fs.size():
		var fo: Vector3 = fs[i][0]
		var hd: Vector3 = fs[i][1]
		var hw: Vector3 = fs[i][2]
		var run := Vector3(hd.x - fo.x, 0, hd.z - fo.z)
		var fwd := run.normalized()
		var rise := hd.y - fo.y
		var tread := run.length() / n
		var along_z := absf(run.z) > absf(run.x)
		var wide := hw.length() * 2.0
		for j in n:
			# Treads straddle the slope you walk, half a step either side.
			var y := fo.y + rise * (j + 0.5) / n
			var low := fl if i == 0 else y - rise / n - 0.25
			var c := fo + run * (j + 0.5) / n
			var sz := Vector3(wide, y - low - 0.05, tread) if along_z else Vector3(tread, y - low - 0.05, wide)
			k.box(mat, I.translated(Vector3(c.x, (low + y - 0.05) * 0.5, c.z)), sz)
			var tone := r.randf_range(0.86, 1.06)
			var stone := Color(tone, tone * r.randf_range(0.97, 1.0), tone * r.randf_range(0.93, 0.99))
			var ts := Vector3(wide - 0.02, 0.06, tread + 0.04) if along_z else Vector3(tread + 0.04, 0.06, wide - 0.02)
			var tilt := Basis(fwd.cross(Vector3.UP).normalized(), r.randf_range(-0.012, 0.012)).rotated(fwd, r.randf_range(-0.012, 0.012))
			k.bevel_box(mat, Transform3D(tilt, Vector3(c.x, y - 0.03, c.z) - fwd * 0.03), ts, 0.012, stone)
		var p0 := fo + hw * 0.92 + Vector3(0, 0.95, 0)
		var p1 := hd + hw * 0.92 + Vector3(0, 0.95, 0)
		var ax := (p1 - p0).normalized()
		var ay := (Vector3.UP - ax * ax.dot(Vector3.UP)).normalized()
		var slope := Basis(ax, ay, ax.cross(ay))
		k.bevel_box(rail, Transform3D(slope, (p0 + p1) * 0.5 + ay * 0.02), Vector3(p0.distance_to(p1), 0.07, 0.08), 0.015)
		for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var pp: Vector3 = fo.lerp(hd, s) + hw * 0.92
			k.bevel_box(rail, I.translated(pp + Vector3(0, 0.48, 0)), Vector3(0.08, 0.96, 0.08), 0.012)
			# A cap on each newel, standing proud of the handrail.
			k.bevel_box(rail, I.translated(pp + Vector3(0, 1.05, 0)), Vector3(0.11, 0.05, 0.11), 0.012)
		# Balusters between the newels, from the treads' line up to the handrail.
		var bw := 0.035 if rail == "timber" else 0.022
		for b in 16:
			var s := (b + 0.5) / 16.0
			if absf(s * 4.0 - roundf(s * 4.0)) < 0.15:
				continue
			var pb: Vector3 = fo.lerp(hd, s) + hw * 0.92
			k.box(rail, I.translated(pb + Vector3(0, 0.46, 0)), Vector3(bw, 0.92, bw))
		# The wall string: a board along the wall side, closing the gap between the
		# treads' ends and the wall and following the flight up.
		var wall_side := -hw.normalized() * (hw.length() + 0.055)
		var w0 := fo + wall_side + Vector3(0, 0.03, 0)
		var w1 := hd + wall_side + Vector3(0, 0.03, 0)
		k.bevel_box(mat, Transform3D(slope, (w0 + w1) * 0.5), Vector3(w0.distance_to(w1) + 0.3, 0.32, 0.14), 0.02)
		if i > 0:
			var q0 := fo + hw * 0.96 - Vector3(0, 0.22, 0)
			var q1 := hd + hw * 0.96 - Vector3(0, 0.22, 0)
			k.bevel_box(mat, Transform3D(slope, (q0 + q1) * 0.5), Vector3(q0.distance_to(q1), 0.42, 0.14), 0.02)
	for l in landings(t):
		var top: Vector3 = l[0]
		var th: float = l[1]
		k.bevel_box(mat, I.translated(top - Vector3(0, th * 0.5, 0)), Vector3(STAIR_W, th, STAIR_W), 0.02)

static func _round_room(f: PackedVector3Array, t: String) -> void:
	var p: Array = ROUND[t]
	var door: Array = p[8]
	var fl: float = p[5]
	var ce: float = p[6]
	var rb: float = p[0]
	_prism_faces(f, rb, fl - 1.0, fl, p[9])
	_prism_faces(f, rb, ce, p[7], p[9])
	# The walls as drawn, inside and out, up to the ceiling.
	for q in _ring_quads(rb, p[1], p[2], p[3], p[4], p[9], door[2], door[1]):
		if (q[0] as Vector3).y < ce:
			_quad_faces(f, q)

static func _dome_room(f: PackedVector3Array) -> void:
	_prism_faces(f, 4.6, _F_DOME - 1.0, _F_DOME, 24)
	for q in _dome_quads():
		_quad_faces(f, q)
	# The airlock: walls, roof, and a ramp down from the floor to the ground.
	for x in [-0.95, 0.95]:
		_box_faces(f, Vector3(x, 1.475, 3.875), Vector3(0.4, 2.95, 2.25))
	_box_faces(f, Vector3(0, 2.775, 3.875), Vector3(2.3, 0.35, 2.25))
	var a := Vector3(-0.75, RAMP[1], RAMP[0])
	var b := Vector3(0.75, RAMP[1], RAMP[0])
	var c := Vector3(0.75, RAMP[3], RAMP[2])
	var d := Vector3(-0.75, RAMP[3], RAMP[2])
	f.append_array([a, b, c, a, c, d])

static func _shrine_shape(f: PackedVector3Array) -> void:
	_prism_faces(f, 2.6, SHRINE_FLOOR - 1.0, SHRINE_FLOOR, 12)
	for n in 6:
		var a := TAU * n / 6
		_box_faces(f, Vector3(cos(a) * 2.0, SHRINE_FLOOR + 1.6, sin(a) * 2.0), Vector3(0.4, 3.2, 0.4))
	_box_faces(f, Vector3(0, SHRINE_FLOOR + 1.0, 0), Vector3(0.6, 2.0, 0.6))
	_prism_faces(f, 2.5, 3.45, 4.85, 12)

static func _quad_faces(f: PackedVector3Array, q: Array) -> void:
	f.append_array([q[0], q[3], q[1], q[0], q[2], q[3]])

## A convex polygonal prism round the y axis.
static func _prism_faces(f: PackedVector3Array, r: float, y0: float, y1: float, n: int) -> void:
	for s in n:
		var a0 := TAU * s / n
		var a1 := TAU * (s + 1) / n
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var lo := Vector3(0, y0, 0)
		var hi := Vector3(0, y1, 0)
		f.append_array([p0 + lo, p1 + lo, p1 + hi, p0 + lo, p1 + hi, p0 + hi])
		f.append_array([hi, p0 + hi, p1 + hi, lo, p1 + lo, p0 + lo])

static func _box_faces(f: PackedVector3Array, c: Vector3, s: Vector3) -> void:
	KitHouse._box_faces(f, c, s)

# --- Shells ------------------------------------------------------------------------

## Quads of a round wall with its doorway facing +z: [p00, p01, p10, p11, n0, n1, inner]
## (bottom and top corners at the segment's two angles, outward normals, true for the
## inside face). The doorway opens `nd` segments up to `dh`.
static func _ring_quads(rb: float, rt: float, th: float, y0: float, y1: float, segs: int, nd: int, dh: float) -> Array:
	var out: Array = []
	var step := TAU / segs
	var a_start := PI / 2 - nd * step / 2
	var slope := (rb - rt) / (y1 - y0)
	for s in segs:
		var a0 := a_start + s * step
		var a1 := a0 + step
		var bands: Array = [[dh, y1]] if s < nd else [[y0, dh], [dh, y1]]
		for band in bands:
			for inner in [false, true]:
				var ya: float = band[0]
				var yb: float = band[1]
				var ra := lerpf(rb, rt, (ya - y0) / (y1 - y0)) - (th if inner else 0.0)
				var rr := lerpf(rb, rt, (yb - y0) / (y1 - y0)) - (th if inner else 0.0)
				var d0 := Vector3(cos(a0), 0, sin(a0))
				var d1 := Vector3(cos(a1), 0, sin(a1))
				out.append([d0 * ra + Vector3(0, ya, 0), d1 * ra + Vector3(0, ya, 0), d0 * rr + Vector3(0, yb, 0), d1 * rr + Vector3(0, yb, 0),
					Vector3(d0.x, slope, d0.z).normalized(), Vector3(d1.x, slope, d1.z).normalized(), inner])
	return out

## Quads of the hab dome, its doorway open toward +z.
static func _dome_quads() -> Array:
	var r: float = DOME[0]
	var th: float = DOME[1]
	var sq: float = DOME[2]
	var y0: float = DOME[3]
	var nd: int = DOME[4]
	var nr: int = DOME[5]
	var segs: int = DOME[6]
	var rings: int = DOME[7]
	var step := TAU / segs
	var a_start := PI / 2 - nd * step / 2
	var out: Array = []
	for j in rings:
		var pa := PI / 2 - (PI / 2) * j / rings
		var pb := PI / 2 - (PI / 2) * (j + 1) / rings
		for s in segs:
			if j < nr and s < nd:
				continue
			var a0 := a_start + s * step
			var a1 := a0 + step
			for inner in [false, true]:
				var rr: float = r - (th if inner else 0.0)
				var pts: Array = []
				var nrm: Array = []
				for ph in [pa, pb]:
					for a in [a0, a1]:
						pts.append(Vector3(sin(ph) * cos(a) * rr, y0 + cos(ph) * rr * sq, sin(ph) * sin(a) * rr))
						nrm.append(Vector3(sin(ph) * cos(a), cos(ph) / sq, sin(ph) * sin(a)).normalized())
				out.append([pts[0], pts[1], pts[2], pts[3], nrm[0], nrm[1], inner, nrm[2], nrm[3]])
	return out

## Draws wall quads: outside faces outward, inside faces inward, normals smoothed.
static func _draw_quads(k: MeshKit, outer: String, inner: String, quads: Array) -> void:
	var I := Transform3D.IDENTITY
	for q in quads:
		var n0: Vector3 = q[4]
		var n1: Vector3 = q[5]
		var n2: Vector3 = q[7] if q.size() > 7 else n0
		var n3: Vector3 = q[8] if q.size() > 7 else n1
		if not q[6]:
			k.tri(outer, I, q[0], q[3], q[1], n0, n3, n1)
			k.tri(outer, I, q[0], q[2], q[3], n0, n2, n3)
		else:
			k.tri(inner, I, q[0], q[1], q[3], -n0, -n1, -n3)
			k.tri(inner, I, q[0], q[3], q[2], -n0, -n3, -n2)

## A quad facing `want`, whatever order its corners come in.
static func _face(k: MeshKit, mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	if (b - a).cross(c - a).dot(want) < 0.0:
		k.quad(mat, Transform3D.IDENTITY, d, c, b, a)
	else:
		k.quad(mat, Transform3D.IDENTITY, a, b, c, d)

## The jambs and lintel of a round wall's doorway, a timber frame, the top of the wall,
## and the door standing open into the room.
static func _ring_trim(k: MeshKit, models: Array, wall: String, rb: float, rt: float, th: float, y0: float, y1: float, segs: int, door: Array, fl: float) -> void:
	var nd: int = door[2]
	var dh: float = door[1]
	var step := TAU / segs
	var a_start := PI / 2 - nd * step / 2
	var r_at := func(y: float) -> float: return lerpf(rb, rt, (y - y0) / (y1 - y0))
	for side: int in [0, 1]:
		var a := a_start + side * nd * step
		var d := Vector3(cos(a), 0, sin(a))
		var tang := Vector3(-sin(a), 0, cos(a)) * (1.0 if side == 0 else -1.0)
		var ro0: float = r_at.call(y0)
		var ro1: float = r_at.call(dh)
		_face(k, wall, d * (ro0 - th) + Vector3(0, y0, 0), d * ro0 + Vector3(0, y0, 0), d * ro1 + Vector3(0, dh, 0), d * (ro1 - th) + Vector3(0, dh, 0), tang)
	for s in nd:
		var a0 := a_start + s * step
		var a1 := a0 + step
		var ro: float = r_at.call(dh)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3(0, dh, 0)
		_face(k, wall, d0 * (ro - th) + y, d1 * (ro - th) + y, d1 * ro + y, d0 * ro + y, Vector3.DOWN)
	for s in segs:
		var a0 := a_start + s * step
		var a1 := a0 + step
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3(0, y1, 0)
		_face(k, wall, d0 * (rt - th) + y, d1 * (rt - th) + y, d1 * rt + y, d0 * rt + y, Vector3.UP)
	# Timber posts and a lintel framing the doorway.
	var hw: float = door[0]
	var rm: float = r_at.call(dh * 0.5) - th * 0.5
	var zc := sqrt(maxf(rm * rm - hw * hw, 0.01))
	for x in [-hw - 0.07, hw + 0.07]:
		k.box("timber", Transform3D.IDENTITY.translated(Vector3(x, (fl + dh) * 0.5, zc)), Vector3(0.14, dh - fl, th + 0.12))
	k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, dh + 0.08, zc)), Vector3(hw * 2 + 0.42, 0.16, th + 0.14))
	var zi := sqrt(maxf(pow(r_at.call(fl) - th, 2) - hw * hw, 0.01))
	models.append(["village/Door_1_Round", 100.0, Vector3(-hw + 0.05, fl - 0.03, zi - 0.06), 1.0])

## A woven hanging on a wall, on a timber rod: `xf` puts its middle on the wall, facing
## out along +Z. Its material repeats every 1.2 m in the room's own space, so a hanging
## whose middle sits on an odd multiple of 0.6 m (across and up) shows the picture once.
static func tapestry(k: MeshKit, xf: Transform3D) -> void:
	k.box("tapestry", xf, Vector3(1.2, 1.2, 0.02))
	k.cylinder("timber", xf * Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0, 0.64, 0.03)) * Transform3D.IDENTITY.translated(Vector3(0, -0.725, 0)), 0.025, 0.025, 1.45, 6)

static func _mushroom_house(k: MeshKit, models: Array) -> void:
	var p: Array = ROUND["mushroom_house"]
	var I := Transform3D.IDENTITY
	_draw_quads(k, "stem", "planks", _ring_quads(p[0], p[1], p[2], p[3], p[4], p[9], p[8][2], p[8][1]))
	_ring_trim(k, models, "stem", p[0], p[1], p[2], p[3], p[4], p[9], p[8], p[5])
	# Planked floor, and gills under the cap vaulting over the room.
	k.cylinder("wood_floor", I.translated(Vector3(0, -0.2, 0)), 2.5, 2.5, 0.2 + p[5], 20)
	var ce: float = p[6]
	for s in 20:
		var a0 := TAU * s / 20
		var a1 := TAU * (s + 1) / 20
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_face(k, "cap_teal", d0 * 4.0 + Vector3(0, 3.3, 0), d1 * 4.0 + Vector3(0, 3.3, 0), d1 * 2.3 + Vector3(0, 3.5, 0), d0 * 2.3 + Vector3(0, 3.5, 0), Vector3.DOWN)
		_face(k, "stem", d0 * 2.1 + Vector3(0, ce, 0), d1 * 2.1 + Vector3(0, ce, 0), Vector3(0, ce + 0.6, 0), Vector3(0, ce + 0.6, 0) + d1 * 0.001, Vector3.DOWN)
	k.sphere("cap_teal", I.translated(Vector3(0, 3.3, 0)), 4.0, 10, 20, 0.1, 0.55, Color.WHITE, true)
	for a in [0.9, -0.9, 2.6]:
		k.sphere("glow_warm", I.translated(Vector3(sin(a) * 2.85, 2.6, cos(a) * 2.85)), 0.22, 5, 8)
	for n in 12:
		var a := n * 0.52
		k.sphere("glow_violet", I.translated(Vector3(cos(a) * 3.4, 3.4, sin(a) * 3.4)), 0.1, 3, 5)

static func _watchtower(k: MeshKit, models: Array) -> void:
	var p: Array = ROUND["watchtower"]
	var I := Transform3D.IDENTITY
	_draw_quads(k, "cobble", "stone", _ring_quads(p[0], p[1], p[2], p[3], p[4], p[9], p[8][2], p[8][1]))
	_ring_trim(k, models, "stone", p[0], p[1], p[2], p[3], p[4], p[9], p[8], p[5])
	k.cylinder("wood_floor", I.translated(Vector3(0, -0.2, 0)), 1.95, 1.95, 0.2 + p[5], 16)
	# The boarded ceiling of the guard room.
	k.cylinder("planks", I.translated(Vector3(0, p[6], 0)), 1.95, 1.95, 0.12, 16)
	k.cylinder("stone", I.translated(Vector3(0, 12.0, 0)), 2.4, 2.4, 0.5, 16)
	for n in 8:
		var a := TAU * n / 8
		k.box("cobble", Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 2.1, 13.0, sin(a) * 2.1)), Vector3(0.6, 1.2, 0.6))
	for y in [5.0, 8.5]:
		var ro := lerpf(2.3, 1.9, (y + 0.3) / 12.3)
		k.box("glow_warm", I.translated(Vector3(0, y, ro - 0.02)), Vector3(0.3, 0.8, 0.1))
	k.cylinder("timber", I.translated(Vector3(0, 12.5, 0)), 0.06, 0.06, 4.0, 5)
	k.box("cloth", I.translated(Vector3(0.6, 15.8, 0)), Vector3(1.2, 0.7, 0.03))

static func _hab_dome(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("metal_dark", I, 4.6, 4.6, _F_DOME, 24)
	_draw_quads(k, "panel", "panel", _dome_quads())
	k.cylinder("glow_cyan", I.translated(Vector3(0, _F_DOME, 0)), 4.25, 4.25, 0.08, 24, false)
	# The airlock: walls, roof, floor and a ramp, with a lit portal at the outer end.
	for x in [-0.95, 0.95]:
		k.box("metal", I.translated(Vector3(x, 1.475, 3.875)), Vector3(0.4, 2.95, 2.25))
	k.box("metal", I.translated(Vector3(0, 2.775, 3.875)), Vector3(2.3, 0.35, 2.25))
	k.box("metal_dark", I.translated(Vector3(0, _F_DOME - 0.025, 3.675)), Vector3(1.5, 0.05, 1.85))
	var rl := Vector2(RAMP[2] - RAMP[0], RAMP[1] - RAMP[3])
	var ramp := Basis(Vector3.RIGHT, atan2(rl.y, rl.x))
	k.box("metal_dark", Transform3D(ramp, Vector3(0, (RAMP[1] + RAMP[3]) * 0.5 - 0.025, (RAMP[0] + RAMP[2]) * 0.5)), Vector3(1.5, 0.05, rl.length()))
	for x in [-0.78, 0.78]:
		k.box("glow_cyan", I.translated(Vector3(x, 1.4, 5.01)), Vector3(0.05, 2.3, 0.04))
	k.box("glow_cyan", I.translated(Vector3(0, 2.58, 5.01)), Vector3(1.6, 0.06, 0.04))
	for n in 6:
		var a := TAU * n / 6 + 0.5
		if absf(angle_difference(a, PI / 2)) < 0.5:
			continue
		k.box("glass", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * 3.55, 2.4, sin(a) * 3.55)), Vector3(1.4, 0.5, 0.05))
	k.cylinder("metal", I.translated(Vector3(1.5, 3.65, 0)), 0.08, 0.05, 2.5, 6)
	k.sphere("glow_red", I.translated(Vector3(1.5, 6.2, 0)), 0.1, 4, 6)

static func _shrine(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("rune_stone", I.translated(Vector3(0, -0.2, 0)), 2.6, 2.6, SHRINE_FLOOR + 0.2, 20)
	for n in 6:
		var a := TAU * n / 6
		k.cylinder("stem", I.translated(Vector3(cos(a) * 2.0, SHRINE_FLOOR, sin(a) * 2.0)), 0.22, 0.18, 3.35, 8)
	k.sphere("moss", I.translated(Vector3(0, 3.5, 0)), 2.5, 8, 16, 0.08, 0.55, Color.WHITE, true)
	k.crystal("crystal", I.translated(Vector3(0, SHRINE_FLOOR, 0)), 0.35, 2.0)
	k.sphere("glow_teal", I.translated(Vector3(0, 3.0, 0)), 0.25, 6, 8)

# --- Furniture pieces ----------------------------------------------------------------

## Sci-fi furniture is powder-coated, as in a station or a ward: pale grey frames and
## tops, blue-grey lockers and drawers, graphite trims, bright steel only for legs,
## rails and handles.
const PAINT_PALE := Color(0.86, 0.87, 0.87)
const PAINT_LOCKER := Color(0.6, 0.67, 0.74)

static func _piece(name: String, k: MeshKit, models: Array, xf: Transform3D) -> void:
	var I := Transform3D.IDENTITY
	var at := func(p: Vector3) -> Transform3D: return xf * I.translated(p)
	match name:
		"@bunk":
			for x in [-0.97, 0.97]:
				for z in [-0.44, 0.44]:
					k.bevel_box("metal", at.call(Vector3(x, 0.95, z)), Vector3(0.06, 1.9, 0.06))
			for y in [0.35, 1.35]:
				k.bevel_box("enamel", at.call(Vector3(0, y, 0)), Vector3(2.0, 0.08, 0.92), 0.02, PAINT_PALE)
				k.bevel_box("cloth_blue", at.call(Vector3(0, y + 0.11, 0)), Vector3(1.9, 0.14, 0.85))
				k.bevel_box("cloth", at.call(Vector3(-0.72, y + 0.23, 0)), Vector3(0.38, 0.1, 0.6))
			k.bevel_box("metal", at.call(Vector3(0, 1.62, 0.44)), Vector3(1.94, 0.05, 0.04))
		"@cot":
			k.bevel_box("enamel", at.call(Vector3(0, 0.15, 0)), Vector3(2.0, 0.3, 0.9), 0.02, PAINT_PALE)
			k.bevel_box("cloth_blue", at.call(Vector3(0, 0.38, 0)), Vector3(1.9, 0.16, 0.82))
			k.bevel_box("cloth", at.call(Vector3(-0.72, 0.5, 0)), Vector3(0.38, 0.1, 0.6))
		"@locker":
			k.bevel_box("enamel", at.call(Vector3(0, 1.05, 0)), Vector3(0.58, 2.1, 0.52), 0.02, PAINT_LOCKER)
			k.bevel_box("enamel", at.call(Vector3(0, 1.05, 0.265)), Vector3(0.5, 2.0, 0.01), 0.02, PAINT_LOCKER.lightened(0.06))
			k.bevel_box("metal", at.call(Vector3(0.18, 1.3, 0.28)), Vector3(0.03, 0.3, 0.02))
			for y in [1.75, 1.82, 1.89]:
				k.bevel_box("enamel_grey", at.call(Vector3(0, y, 0.275)), Vector3(0.36, 0.025, 0.01))
		"@console":
			k.bevel_box("enamel", at.call(Vector3(0, 0.375, -0.05)), Vector3(1.6, 0.75, 0.7), 0.02, PAINT_PALE)
			k.bevel_box("enamel_grey", Transform3D(xf.basis * Basis(Vector3.RIGHT, 0.45), xf * Vector3(0, 0.8, 0.12)), Vector3(1.5, 0.05, 0.5))
			for x in [-0.38, 0.38]:
				k.bevel_box("glow_cyan", Transform3D(xf.basis * Basis(Vector3.RIGHT, 0.45), xf * Vector3(x, 0.83, 0.12)), Vector3(0.6, 0.01, 0.32))
			k.bevel_box("enamel_grey", at.call(Vector3(0, 1.0, -0.3)), Vector3(1.5, 0.48, 0.06))
			k.bevel_box("screen", at.call(Vector3(0, 1.0, -0.265)), Vector3(1.4, 0.4, 0.01))
		"@desk":
			k.bevel_box("enamel", at.call(Vector3(0, 0.755, 0)), Vector3(1.8, 0.05, 0.8), 0.02, PAINT_PALE)
			for x in [-0.85, 0.85]:
				k.bevel_box("metal", at.call(Vector3(x, 0.365, 0)), Vector3(0.05, 0.73, 0.75))
			k.bevel_box("enamel", at.call(Vector3(0.55, 0.42, 0)), Vector3(0.5, 0.6, 0.72), 0.02, PAINT_LOCKER)
			k.bevel_box("enamel_grey", at.call(Vector3(-0.3, 0.98, -0.3)), Vector3(0.7, 0.42, 0.04))
			k.bevel_box("screen", at.call(Vector3(-0.3, 0.98, -0.275)), Vector3(0.64, 0.36, 0.01))
		"@chair":
			k.cylinder("enamel_grey", at.call(Vector3(0, 0, 0)), 0.25, 0.25, 0.03, 8)
			k.cylinder("metal", at.call(Vector3(0, 0.03, 0)), 0.04, 0.04, 0.43, 6)
			k.bevel_box("enamel_grey", at.call(Vector3(0, 0.46, 0)), Vector3(0.46, 0.06, 0.46))
			k.bevel_box("cloth_blue", at.call(Vector3(0, 0.515, 0)), Vector3(0.42, 0.05, 0.42))
			k.bevel_box("enamel_grey", at.call(Vector3(0, 0.78, -0.21)), Vector3(0.44, 0.5, 0.05))
		"@tank":
			k.cylinder("enamel", at.call(Vector3(0, 0, 0)), 0.47, 0.47, 0.25, 12, true, 0.0, 1, PAINT_PALE)
			for a in [0.0, 2.1, 4.2]:
				k.bevel_box("metal", at.call(Vector3(cos(a) * 0.4, 1.15, sin(a) * 0.4)), Vector3(0.05, 1.8, 0.05))
			k.cylinder("enamel", at.call(Vector3(0, 2.05, 0)), 0.47, 0.42, 0.25, 12, true, 0.0, 1, PAINT_PALE)
			if Eras.theme == "human":
				# Human worlds: a glass culture tank of pale green fluid, lit by the room.
				k.cylinder("bottle_glass", at.call(Vector3(0, 0.25, 0)), 0.36, 0.36, 1.8, 12)
			else:
				k.cylinder("glow_teal", at.call(Vector3(0, 0.25, 0)), 0.36, 0.36, 1.8, 12)
				k.crystal("crystal", at.call(Vector3(0, 0.8, 0)), 0.14, 0.7)
		"@holo":
			k.cylinder("enamel", at.call(Vector3(0, 0, 0)), 0.75, 0.6, 0.9, 16, true, 0.0, 1, PAINT_PALE)
			k.cylinder("metal", at.call(Vector3(0, 0.9, 0)), 0.8, 0.8, 0.05, 16)
			if Eras.theme == "human":
				# Human worlds: a map table, its top a lit display; nothing floats or glows.
				k.cylinder("screen", at.call(Vector3(0, 0.95, 0)), 0.65, 0.65, 0.02, 16)
			else:
				k.cylinder("glow_cyan", at.call(Vector3(0, 0.95, 0)), 0.65, 0.65, 0.02, 16)
				k.sphere("glow_cyan", at.call(Vector3(0, 1.4, 0)), 0.22, 6, 10)
				k.cylinder("glow_cyan", at.call(Vector3(0, 1.38, 0)), 0.45, 0.45, 0.01, 16, false)
		"@rack":
			k.bevel_box("enamel_grey", at.call(Vector3(0, 1.0, -0.14)), Vector3(2.0, 2.0, 0.06))
			for y in [0.55, 1.05, 1.55]:
				k.bevel_box("metal", at.call(Vector3(0, y, 0.0)), Vector3(1.9, 0.04, 0.3))
			for g in [["scifi/AR_1", Vector3(0, 1.75, 0)], ["scifi/SMG_1", Vector3(-0.45, 1.44, 0)], ["scifi/Pistol_1", Vector3(0.45, 1.23, 0)],
					["scifi/Sniper_1", Vector3(-0.35, 0.75, 0)], ["scifi/Pistol_2", Vector3(0.75, 0.73, 0)]]:
				models.append([g[0], rad_to_deg(xf.basis.get_euler().y), xf * (g[1] as Vector3), 0.85 if g[0] == "scifi/Sniper_1" else 1.0])
		"@tomb":
			k.bevel_box("stone_dark", at.call(Vector3(0, 0.05, 0)), Vector3(1.1, 0.1, 2.4))
			k.bevel_box("crypt_stone", at.call(Vector3(0, 0.42, 0)), Vector3(0.98, 0.66, 2.28))
			k.bevel_box("stone", at.call(Vector3(0, 0.84, 0)), Vector3(1.1, 0.18, 2.4))
			k.bevel_box("stone_dark", at.call(Vector3(0, 0.98, 0.1)), Vector3(0.42, 0.1, 1.5))
			k.sphere("stone_dark", at.call(Vector3(0, 1.0, -0.82)), 0.15, 5, 8)
			for x in [-0.5, 0.5]:
				k.bevel_box("glow_violet", at.call(Vector3(x, 0.45, 0)), Vector3(0.01, 0.05, 1.8))
		"@screen":
			k.bevel_box("enamel_grey", at.call(Vector3(0, 0.7, 0)), Vector3(2.6, 1.4, 0.06))
			# A lit display, not a white slab of light.
			k.bevel_box("screen", at.call(Vector3(0, 0.7, 0.035)), Vector3(2.45, 1.25, 0.01))
		"@planter":
			k.bevel_box("enamel", at.call(Vector3(0, 0.3, 0)), Vector3(1.2, 0.6, 0.6), 0.02, PAINT_PALE)
			k.bevel_box("moss", at.call(Vector3(0, 0.62, 0)), Vector3(1.1, 0.05, 0.5))
			for x in [-0.4, -0.13, 0.13, 0.4]:
				k.sphere("moss", at.call(Vector3(x, 0.75, 0.05 * signf(x))), 0.17, 5, 7, 0.35)
			for x in [-0.55, 0.55]:
				k.bevel_box("metal", at.call(Vector3(x, 0.75, -0.25)), Vector3(0.04, 0.9, 0.04))
			k.bevel_box("glow_white", at.call(Vector3(0, 1.2, -0.25)), Vector3(1.1, 0.03, 0.08))
		"@ladder":
			for x in [-0.22, 0.22]:
				k.bevel_box("timber", at.call(Vector3(x, 1.5, 0)), Vector3(0.06, 3.0, 0.06))
			for n in 10:
				k.bevel_box("timber", at.call(Vector3(0, 0.3 + n * 0.29, 0)), Vector3(0.44, 0.04, 0.05))
		"@table":
			k.bevel_box("enamel", at.call(Vector3(0, 0.735, 0)), Vector3(1.4, 0.05, 0.9), 0.02, PAINT_PALE)
			for x in [-0.64, 0.64]:
				for z in [-0.39, 0.39]:
					k.bevel_box("metal", at.call(Vector3(x, 0.355, z)), Vector3(0.05, 0.71, 0.05))
