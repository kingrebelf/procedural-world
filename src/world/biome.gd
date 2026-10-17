class_name Biome
## Every region of the world (one Voronoi cell, about half a kilometre across) gets its
## own ecology, rolled from its hash: which plant species grow there and how densely,
## what its rocks look like, and how its grass and soil are tinted. Two regions of the
## same era can look nothing alike, and no two worlds share a species list.
##
## From v18 the region's climate (WorldField.region_climate, carried in the hash) decides
## which kinds of tree it grows: spruce and birch where it is cold, oak and pine in the
## temperate middle, acacia savanna and date palms where it is hot and dry, palms, bananas
## and jungle giants where it is hot and wet.

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
	var clim := WorldField.region_climate(h) if era == Eras.MEDIEVAL else Vector2i(-1, -1)
	if clim.x >= 0:
		families = CLIMATE_TREES[clim.x][clim.y]
		dens *= CLIMATE_DENSITY[clim.x][clim.y]
	var flora: Array = []
	var n := r.randi_range(2, 5)
	for i in n:
		var t: String = families[r.randi() % families.size()]
		flora.append({"t": t, "sp": r.randi() & 0x7FFFFFFF, "w": r.randf_range(0.2, 1.0)})
	# One species usually dominates, as in real forests.
	flora[0]["w"] = r.randf_range(1.5, 3.0)
	if clim.x >= 0:
		_fit_climate(flora, clim, r)
	# Dead trees and snags are the odd single, never a region's main tree: bare trunks
	# all over green hills need a fire or a blight to explain them.
	var total := 0.0
	for f in flora:
		total += float(f["w"])
	for f in flora:
		if Flora.species(f["t"], f["sp"]).get("form", "") in ["dead", "snag"]:
			f["w"] = minf(float(f["w"]), total * 0.04)
	var rocks: Array = []
	for i in r.randi_range(1, 3):
		rocks.append(r.randi() & 0x7FFFFFFF)
	var under: Array = []
	for i in r.randi_range(2, 4):
		under.append(r.randi() & 0x7FFFFFFF)
	if clim.x == 3 and clim.y >= 2:
		for i in under.size():
			under[i] = int(under[i]) | Flora.TROPIC_UNDER
	var fauna: Array = []
	for i in r.randi_range(1, 3):
		fauna.append(r.randi() & 0x7FFFFFFF)
	var lush := r.randf_range(-1.0, 1.0)
	if clim.x >= 0:
		# Wet climates are lush, dry ones golden (a little of the region's own roll stays).
		lush = clampf(lerpf(lush, float(clim.y) / 1.5 - 1.0, 0.65), -1.0, 1.0)
	var grass := _grass_tint(era, r, lush)
	if clim.x >= 0:
		grass = _climate_grass(grass, clim)
	var out := {
		"tree_density": dens, "flora": flora, "rocks": rocks,
		"rock_density": r.randf_range(0.4, 2.2),
		"ore_species": r.randi() & 0x7FFFFFFF,
		"under": under, ## undergrowth species
		"fauna": fauna, ## animal species
		"under_density": r.randf_range(0.3, 1.6),
		"lush": lush, ## -1 dry and golden ... +1 lush and deep green
		"grass_tint": grass,
		# Dry regions grow golden grass, not bare earth: dryness shows in the colour and
		# the mix of species, and thins the sward only a little.
		"grass_density": clampf(r.randf_range(0.75, 1.2) + lush * 0.2, 0.7, 1.4),
		"lumen": _lumen(h, era), ## how much its grass glows at night (0 in most places)
	}
	out["climate"] = clim
	_stand(h, era, out)
	return out

## Kinds of tree by [warmth][wetness] level (WorldField.region_climate), as a bag to draw
## from: cold uplands of spruce and birch, the temperate middle as it always was, then
## savanna, desert palms and rainforest when hot.
const CLIMATE_TREES := [
	[["pine", "pine", "pine", "oak"], ["pine", "pine", "oak"], ["pine", "pine", "oak"], ["pine", "pine", "pine", "oak"]],
	[["pine", "oak", "oak"], ["oak", "pine"], ["oak", "pine"], ["pine", "oak", "pine"]],
	[["oak", "oak", "pine"], ["oak", "pine"], ["oak", "pine"], ["oak", "oak", "pine"]],
	[["palm", "tropic"], ["tropic", "tropic", "palm", "oak"], ["palm", "tropic", "tropic", "palm"], ["palm", "palm", "tropic", "tropic"]],
]
## Tree density by climate: thin desert and open savanna, close rainforest.
const CLIMATE_DENSITY := [
	[0.8, 0.95, 1.0, 1.05], [0.9, 1.0, 1.05, 1.1], [0.8, 1.0, 1.05, 1.15], [0.28, 0.5, 1.1, 1.4],
]
## Which forms of palm and tropical tree suit each wetness level (0 desert .. 3 rainforest).
const PALM_FORMS := [["date"], ["date", "palmetto"], ["coconut", "royal", "banana", "palmetto"], ["coconut", "royal", "banana"]]
const TROPIC_FORMS := [["umbrella"], ["umbrella", "umbrella", "fig"], ["fig", "emergent", "umbrella"], ["emergent", "fig", "emergent"]]

## Swaps palm and tropical species whose form doesn't suit the climate (date palms in the
## desert, coconuts and bananas in the wet; acacia on the dry plains, jungle giants in
## the rainforest) for ones that do.
static func _fit_climate(flora: Array, clim: Vector2i, r: RandomNumberGenerator) -> void:
	for f in flora:
		var want: Array
		match String(f["t"]):
			"palm": want = PALM_FORMS[clim.y]
			"tropic": want = TROPIC_FORMS[clim.y]
			_: continue
		for i in 32:
			if String(Flora.species(f["t"], f["sp"]).get("form", "")) in want:
				break
			f["sp"] = r.randi() & 0x7FFFFFFF

## Grass by climate: a deep, saturated green in the wet tropics, sun-bleached gold in the
## dry heat, a cool grey-green in the cold.
static func _climate_grass(g: Color, clim: Vector2i) -> Color:
	if clim.x == 3:
		return g.lerp(Color(0.24, 0.48, 0.12), 0.45) if clim.y >= 2 else g.lerp(Color(0.62, 0.55, 0.28), 0.45)
	if clim.x == 0:
		return g.lerp(Color(0.32, 0.4, 0.26), 0.35)
	return g

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

## Autumn comes by the stand, not tree by tree: about one region in five has turned (most
## of its broadleaf species in autumn colour, reds, golds and browns together, a few still
## green), the rest are green. Swaps species that don't fit for ones that do (its own hash, so the rest of the
## region's roll is unchanged).
static func _stand(h: int, era: int, out: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(h, era * 31 + 977)
	var turned := r.randf() < 0.2
	var clim: Vector2i = out.get("climate", Vector2i(-1, -1))
	if clim.x == 3:
		turned = false # no autumn in the tropics
	out["autumn"] = turned
	for f in out["flora"]:
		if f["t"] != "oak":
			continue
		# In a turned stand, a minor species may still be green (never the dominant one).
		var want: bool = turned and (f == out["flora"][0] or r.randf() < 0.7)
		for i in 24:
			if bool(Flora.species("oak", f["sp"]).get("autumn", false)) == want:
				break
			f["sp"] = r.randi() & 0x7FFFFFFF

## A species for a tree high up toward the snow, where leaves have long fallen or never
## turned: the region's first conifer, else its first green broadleaf, else {} (no tree).
static func hardy_flora(p: Dictionary) -> Dictionary:
	for t in ["pine", "oak"]:
		for f in p["flora"]:
			if f["t"] == t and not bool(Flora.species(t, f["sp"]).get("autumn", false)):
				return f
	return {}

## The world's snow line (Planets sets it on landing; read here, not from Planets, which
## the world generator must not load).
static var snow_line := 50.0

## No autumn leaves up toward the snow: a turned broadleaf picked at height `y` near the
## snow line becomes the region's hardier tree (hardy_flora), or none ({}).
static func fit_flora(p: Dictionary, f: Dictionary, y: float) -> Dictionary:
	if f["t"] != "oak" or not bool(p.get("autumn", false)) or y < snow_line - 30.0:
		return f
	return hardy_flora(p)

## Broadleaf trees give way to conifers on the way up to the snow: `f` (a pick_flora
## result) for a tree rooted at height h, swapped for the region's own pine (or a pine of
## its own) above a ragged line some way under the snow line. `u` jitters the line. In
## the hottest climates (v18) the line sits higher, so tropical hills keep their palms.
static func by_altitude(p: Dictionary, f: Dictionary, h: float, u: float) -> Dictionary:
	var lift := 10.0 if (p.get("climate", Vector2i(-1, -1)) as Vector2i).x == 3 else 0.0
	if not (f["t"] in ["oak", "palm", "tropic"]) or h < WorldField.snow_line - 26.0 + lift + 14.0 * fposmod(u * 7.31, 1.0):
		return f
	for g in p["flora"]:
		if g["t"] == "pine":
			return g
	return {"t": "pine", "sp": f["sp"], "w": f["w"]}

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
