class_name Eras
## Data-driven era definitions. Adding an era means adding an entry here plus
## shapes in WorldField and a structure kit in ObjectBuilder.

enum { MEDIEVAL, FANTASY, SCIFI }
const COUNT := 3

const NAMES := ["Medieval", "Fantasy", "Sci-Fi"]
const REGION_NAMES := [
	["Vale", "Shire", "March", "Downs", "Hollow", "Reach"],
	["Wildwood", "Glimmerfen", "Aetherglade", "Moonmere", "Thornveil", "Spiregrove"],
	["Sector", "Frontier", "Array", "Outpost", "Grid", "Expanse"],
]
const REGION_PREFIX := [
	["Ashford", "Brennan", "Coldwater", "Dunmere", "Elmstead", "Harrow", "Kingsbridge", "Wexley"],
	["Sylvar", "Eloun", "Nymeth", "Aurel", "Ithrae", "Vael", "Oriel", "Faen"],
	["Kepler", "Tycho", "Halcyon", "Vega", "Orion", "Cygnus", "Helix", "Nadir"],
]

## Ground palette per era: [grass, soil, rock, accent_emissive]
const GROUND := [
	[Color(0.24, 0.36, 0.12), Color(0.36, 0.28, 0.18), Color(0.55, 0.53, 0.49), Color(0, 0, 0)],
	[Color(0.10, 0.34, 0.33), Color(0.22, 0.14, 0.28), Color(0.36, 0.33, 0.45), Color(0.35, 0.9, 0.8)],
	[Color(0.20, 0.21, 0.22), Color(0.13, 0.13, 0.15), Color(0.42, 0.44, 0.47), Color(0.2, 0.8, 1.0)],
]

## Atmosphere per era.
const FOG_COLOR := [Color(0.72, 0.78, 0.86), Color(0.45, 0.62, 0.72), Color(0.55, 0.62, 0.70)]
const FOG_DENSITY := [0.004, 0.0075, 0.005]
const SKY_TINT := [Color(0.38, 0.56, 0.86), Color(0.30, 0.52, 0.70), Color(0.42, 0.50, 0.66)]
const SUN_TINT := [Color(1.0, 0.96, 0.88), Color(0.95, 0.92, 1.0), Color(0.92, 0.97, 1.0)]

## How dense vegetation is (trees per chunk at full weight).
const TREE_DENSITY := [26.0, 30.0, 6.0]
const ROCK_DENSITY := [6.0, 5.0, 8.0]
const ORE_DENSITY := [2.5, 2.5, 3.0]
const GRASS_DENSITY := [1.0, 0.8, 0.12]

const TREE_TYPES := [["oak", "pine"], ["glowcap", "crystal_tree"], ["solar_mast"]]
const ORE_TYPES := ["iron_vein", "aether_crystal", "alloy_scrap"]
const CACHE_TYPES := ["chest", "rune_coffer", "supply_pod"]
const MARKER_TYPES := ["standing_stone", "crystal_shard", "beacon"]
const STRUCTURE_TYPES := [
	["cottage", "cottage", "watchtower", "well"],
	["shrine", "mushroom_house", "spire"],
	["hab_dome", "comms_spire", "cargo_stack"],
]
## Villages and towns (v4 worlds) have more kinds of house.
const TOWN_TYPES := [
	["cottage", "cottage", "townhouse", "townhouse", "longhouse", "watchtower", "well"],
	["shrine", "mushroom_house", "mushroom_house", "spire"],
	["hab_dome", "hab_dome", "comms_spire", "cargo_stack"],
]

static func region_name(era: int, h: int) -> String:
	var p: Array = REGION_PREFIX[era]
	var s: Array = REGION_NAMES[era]
	return "%s %s" % [p[h % p.size()], s[(h >> 8) % s.size()]]

# --- World themes and zone levels -------------------------------------------------
## Worlds made since themes exist are "human" (medieval kingdoms near where you arrive,
## human sci-fi outposts far out, natural plants and animals everywhere) or "alien"
## (fey glowcap wilds, then xeno tech land; strange plants, alien creatures and people).
## Older worlds have no theme and keep their mix of all three eras. Set by Planets.apply
## before any field, generator or chunk of a planet is made; read on worker threads.
static var theme := ""
## Zone level where a planet's land starts (at its origin). Levels rise with distance.
static var base_level := 1

const LEVEL_STEP := 150.0 ## metres outward per zone level
const UNLOCK_LEVEL := 10 ## advanced gear and recipes open up from this player level
## The advanced era starts showing up past FRONTIER metres from the origin and is most of
## the land past HEARTLAND.
const FRONTIER := 1350.0
const HEARTLAND := 3000.0

static func themed() -> bool:
	return theme != ""

## The era whose nature (plants, animals, ground, sky) a region of `era` wears: human
## worlds keep sci-fi regions green and wild, with only the outposts showing the tech.
static func nature(era: int) -> int:
	return MEDIEVAL if theme == "human" and era == SCIFI else era

## Era weights for how the land looks (terrain, grass, sky and fog), from the weights
## that decide what is built there.
static func look(w: PackedFloat32Array) -> PackedFloat32Array:
	if theme != "human" or w.size() < COUNT:
		return w
	var o := w.duplicate()
	o[MEDIEVAL] += o[SCIFI]
	o[SCIFI] = 0.0
	return o

## How dangerous and rewarding the land at (x, z) is: base_level at the origin, one level
## more every LEVEL_STEP metres. Older worlds are level 1 everywhere.
static func zone_level(x: float, z: float) -> int:
	if theme == "":
		return 1
	return base_level + int(Vector2(x, z).length() / LEVEL_STEP)

## Extra loot luck for caches out in higher zones (0 near the start).
static func zone_luck(x: float, z: float) -> float:
	if theme == "":
		return 0.0
	return clampf(float(zone_level(x, z) - 1) / 160.0, 0.0, 0.45)

## 0 for gear of a world's starting era (and anything era-less), 1 for advanced gear,
## which unlocks at UNLOCK_LEVEL. Older worlds gate nothing.
static func tier(era: int) -> int:
	match theme:
		"human":
			return 0 if era == MEDIEVAL or era < 0 else 1
		"alien":
			return 1 if era == SCIFI else 0
	return 0
