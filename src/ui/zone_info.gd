class_name ZoneInfo
extends RefCounted
## What the minimap says about where you stand: the region's name, its kind of land, the
## level range of what lives there and a line on what can be found.
##
## Levels rise with distance from spawn (about one per 150 m), the same rule the human
## and alien worlds work uses for its level zones; when that lands, at() reads its zones.

const PER_LEVEL := 150.0 ## metres from spawn per zone level
const BAND := 5 ## levels per band shown, e.g. 6-10

## What each era's land offers, by level band (low, mid, high).
const FINDS := [
	["Oak and pine woods, wild animals and iron veins in the rocks. Villages trade and sell food.",
		"Bandit-held castles with veteran guards, and richer iron in the hills.",
		"Dread castle garrisons and wolf packs. Keeps hold the best medieval gear."],
	["Glowcap groves, aether crystals and mushroom villages. Wisps and moths drift at night.",
		"Crypts guarded by stalkers; aether clusters grow larger in the deep woods.",
		"Elite crypt guards and old fey ruins with rare enchanted loot."],
	["Alloy scrap fields, xeno plants and outposts with traders and terminals.",
		"Bunkers held by sentry crawlers; scrap piles hide circuitry and power cells.",
		"Elite sentries, wrecks and alien ruins with the best tech in the land."],
]
const KIND := ["Medieval lands", "Fey wilds", "Frontier tech"]

static var _field: WorldField
static var _seed := -1

static func _field_for(seed: int) -> WorldField:
	if _field == null or _seed != seed:
		_field = ChunkGenerator.new(seed).field
		_seed = seed
	return _field

## {name, kind, era, level_lo, level_hi, finds, color} for world point (x, z).
static func at(seed: int, x: float, z: float) -> Dictionary:
	var f := _field_for(seed)
	var era := WorldField.dominant(f.era_weights(x, z))
	var lv := 1 + int(Vector2(x, z).length() / PER_LEVEL)
	var lo := (lv - 1) / BAND * BAND + 1
	var band := clampi((lo - 1) / 10, 0, 2)
	return {"name": f.region_name_at(x, z), "kind": KIND[era], "era": era,
		"level_lo": lo, "level_hi": lo + BAND - 1, "finds": FINDS[era][band],
		"color": UITheme.ERA_COLORS[era]}
