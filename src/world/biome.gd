class_name Biome
## Every region of the world (one Voronoi cell, about half a kilometre across) gets its
## own ecology, rolled from its hash: which plant species grow there and how densely,
## what its rocks look like, and how its grass and soil are tinted. Two regions of the
## same era can look nothing alike, and no two worlds share a species list.

const MAX_CACHE := 512

static var _cache: Dictionary = {}
static var _lock := Mutex.new()

## h: region hash (WorldField.region_hash_at). Returns an immutable parameter dict.
static func params(h: int, era: int) -> Dictionary:
	# Human worlds grow natural plants in their sci-fi regions too (Eras.nature).
	era = Eras.nature(era)
	var key := (h & 0xFFFFFFF) * 4 + era
	_lock.lock()
	var p = _cache.get(key)
	_lock.unlock()
	if p != null:
		return p
	p = _roll(h, era)
	_lock.lock()
	if _cache.size() > MAX_CACHE:
		_cache.clear()
	_cache[key] = p
	_lock.unlock()
	return p

static func _roll(h: int, era: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(h, era * 7919 + 13)
	# Density: mostly moderate, sometimes barren clearings or near-impenetrable forest.
	var dens := r.randf_range(0.45, 1.5)
	var roll := r.randf()
	if roll < 0.12:
		dens = r.randf_range(0.05, 0.3)
	elif roll > 0.88:
		dens = r.randf_range(1.6, 2.6)
	var families: Array = Eras.TREE_TYPES[era]
	var flora: Array = []
	var n := r.randi_range(2, 5)
	for i in n:
		var t: String = families[r.randi() % families.size()]
		flora.append({"t": t, "sp": r.randi() & 0x7FFFFFFF, "w": r.randf_range(0.2, 1.0)})
	# One species usually dominates, as in real forests.
	flora[0]["w"] = r.randf_range(1.5, 3.0)
	var rocks: Array = []
	for i in r.randi_range(1, 3):
		rocks.append(r.randi() & 0x7FFFFFFF)
	var under: Array = []
	for i in r.randi_range(2, 4):
		under.append(r.randi() & 0x7FFFFFFF)
	var fauna: Array = []
	for i in r.randi_range(1, 3):
		fauna.append(r.randi() & 0x7FFFFFFF)
	var lush := r.randf_range(-1.0, 1.0)
	var grass := _grass_tint(era, r, lush)
	return {
		"tree_density": dens, "flora": flora, "rocks": rocks,
		"rock_density": r.randf_range(0.4, 2.2),
		"ore_species": r.randi() & 0x7FFFFFFF,
		"under": under, ## undergrowth species
		"fauna": fauna, ## animal species
		"under_density": r.randf_range(0.3, 1.6),
		"lush": lush, ## -1 dry and golden ... +1 lush and deep green
		"grass_tint": grass,
		"grass_density": clampf(r.randf_range(0.5, 1.4) + lush * 0.3, 0.2, 1.6),
		"lumen": _lumen(h, era), ## how much its grass glows at night (0 in most places)
	}

## Bioluminescence is a feature of a few regions, not of a whole era: about a third of
## fantasy regions glow, a few sci-fi ones, no medieval ones. (Its own hash, so the rest
## of a region's roll is unchanged.)
static func _lumen(h: int, era: int) -> float:
	if Eras.theme == "human":
		return 0.0 # nothing glows on a human world
	var u := WHash.unit2(h & 0xFFFFFFF, era, 0, 77)
	var chance: float = [0.0, 0.33, 0.1][era]
	if u >= chance:
		return 0.0
	return 0.25 + 0.5 * u / chance

static func _grass_tint(era: int, r: RandomNumberGenerator, lush: float) -> Color:
	match era:
		Eras.MEDIEVAL:
			var dry := Color(0.55, 0.5, 0.24)
			var wet := Color(0.2, 0.45, 0.14)
			return dry.lerp(wet, lush * 0.5 + 0.5).lerp(Color.from_hsv(r.randf_range(0.15, 0.3), 0.6, 0.45), 0.2)
		Eras.FANTASY:
			var hues := [0.42, 0.48, 0.53, 0.72, 0.8, 0.9, 0.13, 0.33]
			return Color.from_hsv(fposmod(hues[r.randi() % hues.size()] + r.randf_range(-0.03, 0.03), 1.0), r.randf_range(0.35, 0.65), r.randf_range(0.35, 0.55))
	return Color.from_hsv(r.randf_range(0.0, 0.15), r.randf_range(0.1, 0.35), r.randf_range(0.28, 0.42))

## Picks a species from a biome's flora list using a uniform random number.
static func pick_flora(p: Dictionary, u: float) -> Dictionary:
	var total := 0.0
	for f in p["flora"]:
		total += f["w"]
	var acc := 0.0
	for f in p["flora"]:
		acc += f["w"] / total
		if u <= acc:
			return f
	return p["flora"][-1]
