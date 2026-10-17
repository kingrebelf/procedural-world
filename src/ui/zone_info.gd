class_name ZoneInfo
extends RefCounted
## What the minimap says about where you stand: the region's name, its kind of land, the
## level range of what lives there and a line on what can be found.
##
## Levels rise with distance from spawn (one per 150 m): on themed worlds these are the
## real zone levels (Eras.zone_level, which also knows a world's base level).

const PER_LEVEL := 150.0 ## metres from spawn per zone level (Eras.LEVEL_STEP)

## Human worlds by level band: medieval below 10, outposts from 10, portals from 40.
const HUMAN := [[10, "Medieval lands", "Natural woods and wild animals, iron in the rocks, villages and castles. Medieval gear only."],
	[20, "Borderlands", "Tougher castle garrisons, and the first human outposts with sci-fi gear."],
	[40, "Human frontier", "Outposts hold most of the land: bunkers, alloy scrap and the best human tech."],
	[9999, "High frontier", "Elite foes everywhere, and ancient portals to other worlds stand out here."]]
## Alien worlds by era of the land: fey wilds near the origin, Vex tech further out.
const ALIEN := {1: ["Fey wilds", "Glowcap groves, aether crystals and alien villages. Wisps drift at night."],
	2: ["Vex tech lands", "Vex tech cities, xeno plants and alien creatures guarding the best tech."]}
## Older, mixed worlds: one line per era.
const MIXED := [["Medieval lands", "Oak and pine woods, wild animals, iron veins, villages and castles."],
	["Fey wilds", "Glowcap groves, aether crystals, mushroom villages and crypts."],
	["Frontier tech", "Alloy scrap fields, xeno plants, outposts with traders and bunkers."]]

static var _field: WorldField
static var _seed := -1

static func _field_for(seed: int) -> WorldField:
	if _field == null or _seed != seed:
		_field = ChunkGenerator.new(seed).field
		_seed = seed
	return _field

static func level_at(x: float, z: float) -> int:
	return Eras.zone_level(x, z) if Eras.themed() else mini(1 + int(Vector2(x, z).length() / PER_LEVEL), Eras.HUMAN_MAX_LEVEL)

## {name, kind, era, level, level_lo, level_hi, finds, color} for world point (x, z).
static func at(seed: int, x: float, z: float) -> Dictionary:
	var f := _field_for(seed)
	var era := WorldField.dominant(f.era_weights(x, z))
	var lv := level_at(x, z)
	var lo := lv / 10 * 10
	var kind: String
	var finds: String
	match Eras.theme:
		"human":
			for b in HUMAN:
				if lv < b[0]:
					kind = b[1]
					finds = b[2]
					break
		"alien":
			var a: Array = ALIEN.get(era, ALIEN[1])
			kind = a[0]
			finds = a[1]
		_:
			kind = MIXED[era][0]
			finds = MIXED[era][1]
	var band := band_range(lv)
	return {"name": f.region_name_at(x, z), "kind": kind, "era": era, "level": lv, "band_lo": band.x, "band_hi": band.y,
		"level_lo": maxi(lo, 1), "level_hi": maxi(mini(lo + 9, maxi(Eras.max_level(), lv)), lv), "finds": finds, "color": UITheme.ERA_COLORS[era]}

## The levels of the zone that level lv lies in: on human worlds a band of HUMAN (the
## Borderlands are 10-19), elsewhere the ten levels round it.
static func band_range(lv: int) -> Vector2i:
	if Eras.theme == "human":
		var lo := 1
		for b in HUMAN:
			if lv < b[0]:
				return Vector2i(maxi(lo, Eras.base_level), mini(int(b[0]) - 1, Eras.max_level()))
			lo = b[0]
	var l0 := maxi(lv / 10 * 10, 1)
	return Vector2i(l0, maxi(mini(l0 + 9, Eras.max_level()), lv))

## The toast for walking into another zone: "Entering the Borderlands  ·  Lv 10-19".
static func entering(z: Dictionary) -> String:
	var kind := String(z["kind"])
	var the := "" if kind.begins_with("The ") else "the "
	return "Entering %s%s  ·  Lv %d-%d" % [the, kind, int(z["band_lo"]), int(z["band_hi"])]
