class_name Byproducts
## The odd extra you turn up while working: flint, coal and copper in plain rock, tin,
## silver and gold beside iron, resin from pines, clay where you dig, herbs in the
## undergrowth. Pure functions, so tests can call them.

## Per item mined or chopped from these objects: [[item, chance, least zone level]].
const FROM := {
	"rock": [["flint", 0.12, 1], ["coal", 0.08, 1], ["copper_ore", 0.06, 1], ["tin_ore", 0.04, 1], ["clay", 0.05, 1], ["salt_crystal", 0.03, 1]],
	"iron_vein": [["coal", 0.12, 1], ["copper_ore", 0.1, 1], ["tin_ore", 0.08, 1], ["silver_ore", 0.05, 3], ["gold_ore", 0.025, 5]],
	"cave_crystal": [["silver_ore", 0.15, 1], ["gold_ore", 0.08, 1], ["coal", 0.1, 1]],
	"standing_stone": [["flint", 0.1, 1]],
	"pine": [["resin", 0.15, 1]],
	"oak": [["honey", 0.025, 1], ["beeswax", 0.025, 1], ["egg", 0.02, 1]],
}
## Each spadeful of earth: [[item, chance]], scaled by how good the tool is at digging.
const DIG := [["clay", 0.3], ["flint", 0.08], ["potato", 0.02]]

## Extras for `units` items taken from an object of type `t`. `zone`: the zone level.
static func of_object(t: String, units: int, zone: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e in FROM.get(t, []):
		if zone < int(e[2]):
			continue
		var n := 0
		for i in units:
			if rng.randf() < float(e[1]):
				n += 1
		if n > 0:
			out.append([e[0], n])
	return out

## Extras for one dig with a tool whose "dig" is `dig`.
static func of_digging(dig: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e in DIG:
		if rng.randf() < float(e[1]) * clampf(dig, 0.3, 1.5):
			out.append([e[0], 1])
	return out

## Herbs per undergrowth species (Flora.under_yield), on medieval and human land.
const HERBS := ["herb_red", "herb_blue", "herb_yellow", "herb_mint", "herb_root"]

## What one medieval plant gives beyond its fiber and berries. `roll` 0..1 per pick.
static func of_plant(form: String, sp: int, roll: float) -> Array:
	match form:
		"flowers":
			if roll < 0.5:
				return [[HERBS[absi(sp) % HERBS.size()], 1]]
		"fern":
			if roll < 0.3:
				return [["mushroom", 1 + int(roll * 10.0) % 2]]
			if roll < 0.38:
				return [["herb_nightshade", 1]]
			if roll < 0.5:
				return [["herb_root", 1]]
		"reeds":
			if roll < 0.6:
				return [["flax", 1 + int(roll * 10.0) % 2]]
		"bush":
			if roll > 0.9:
				return [["herb_mint", 1]]
	return []
