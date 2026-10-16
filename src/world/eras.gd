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
