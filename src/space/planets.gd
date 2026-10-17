class_name Planets
## The star system around a world: the home planet plus a few others to warp to, all a
## pure function of the world's seed. Each planet has its own terrain seed, the eras it
## allows, a snow line, and colours for how it looks from orbit.

const COUNT := 5 ## the home world and four others

## Planet kinds. eras: allowed eras (empty = all). snow: height of the snow line in metres.
## sea / land / land2 / ice / air: colours from orbit.
const KINDS := {
	"home": {"label": "Homeworld", "eras": [], "snow": 50.0,
		"sea": Color(0.08, 0.22, 0.38), "land": Color(0.28, 0.42, 0.2), "land2": Color(0.45, 0.38, 0.28), "ice": 0.12, "air": Color(0.45, 0.65, 1.0)},
	"verdant": {"label": "Verdant world", "eras": [Eras.MEDIEVAL], "snow": 46.0,
		"sea": Color(0.07, 0.25, 0.35), "land": Color(0.22, 0.45, 0.16), "land2": Color(0.34, 0.5, 0.22), "ice": 0.08, "air": Color(0.5, 0.75, 1.0)},
	"fey": {"label": "Fey moon", "eras": [Eras.FANTASY], "snow": 44.0,
		"sea": Color(0.06, 0.28, 0.32), "land": Color(0.18, 0.45, 0.42), "land2": Color(0.42, 0.3, 0.55), "ice": 0.05, "air": Color(0.55, 1.0, 0.9)},
	"rust": {"label": "Rust world", "eras": [Eras.SCIFI], "snow": 60.0,
		"sea": Color(0.1, 0.16, 0.22), "land": Color(0.6, 0.3, 0.16), "land2": Color(0.45, 0.24, 0.16), "ice": 0.04, "air": Color(1.0, 0.7, 0.5)},
	"frozen": {"label": "Frozen world", "eras": [Eras.MEDIEVAL, Eras.SCIFI], "snow": 6.0,
		"sea": Color(0.12, 0.25, 0.35), "land": Color(0.78, 0.82, 0.86), "land2": Color(0.5, 0.55, 0.6), "ice": 0.45, "air": Color(0.7, 0.85, 1.0)},
}
const OTHERS := ["verdant", "fey", "rust", "frozen"]
const SYLLABLES := ["Ae", "Bel", "Cor", "Dra", "Eri", "Fal", "Gal", "Hes", "Ion", "Kel", "Lum", "Mar", "Ny", "Or", "Pyr", "Qua", "Rho", "Syl", "Tor", "Ul", "Vex", "Zan"]

## The current planet's snow line, for the terrain material (Atmosphere applies it).
static var snow_line := 50.0

static func seed_of(home_seed: int, n: int) -> int:
	return home_seed if n == 0 else WHash.hash2(home_seed, n, 77, 5) & WHash.MASK

## Every planet of the system, home first: {n, name, kind, seed, size, orbit}.
static func system(home_seed: int) -> Array:
	var out: Array = []
	var kinds := OTHERS.duplicate()
	# Shuffle the other kinds by the seed, so each world's sky is different.
	for i in range(kinds.size() - 1, 0, -1):
		var j := WHash.hash2(home_seed, i, 0, 81) % (i + 1)
		var t = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	for n in COUNT:
		var kind: String = "home" if n == 0 else kinds[n - 1]
		out.append({"n": n, "name": _name(home_seed, n), "kind": kind, "seed": seed_of(home_seed, n),
			"size": 1.0 if n == 0 else 0.6 + 0.8 * WHash.unit2(home_seed, n, 0, 82),
			"orbit": n * 1.0 + WHash.unit2(home_seed, n, 0, 83) * 0.5})
	return out

static func _name(home_seed: int, n: int) -> String:
	var a := WHash.hash2(home_seed, n, 1, 84)
	var b := WHash.hash2(home_seed, n, 2, 84)
	var s: String = SYLLABLES[a % SYLLABLES.size()] + String(SYLLABLES[b % SYLLABLES.size()]).to_lower()
	if WHash.unit2(home_seed, n, 3, 84) < 0.4:
		s += " " + ["Prime", "Minor", "IV", "VII", "Major"][WHash.hash2(home_seed, n, 4, 84) % 5]
	return s

static func get_planet(home_seed: int, n: int) -> Dictionary:
	return system(home_seed)[clampi(n, 0, COUNT - 1)]

static func kind_of(p: Dictionary) -> Dictionary:
	return KINDS[p["kind"]]

## Makes generation follow planet `p`: its eras and snow line. Call before any world
## field, generator or chunk of that planet is made.
static func apply(p: Dictionary) -> void:
	var k := kind_of(p)
	WorldField.allowed_eras = k["eras"]
	snow_line = k["snow"] # the terrain material picks it up (Atmosphere)

## A pleasant place to arrive: gentle, dry ground near `around` (searching outward if it
## is all sea). Deterministic per planet seed.
static func spawn_point(seed: int, rivers: bool, around := Vector2(8, 8)) -> Vector3:
	var g := ChunkGenerator.new(seed)
	for ring in 12:
		var best := Vector3.INF
		var best_slope := 100.0
		var o := around + Vector2.from_angle(ring * 2.4) * ring * 260.0
		for n in 24:
			var x := o.x + (n % 6) * 9.0
			var z := o.y + int(n / 6) * 12.0
			var w := g.field.era_weights(x, z)
			var h0 := g.field.height(x, z, w)
			var s := absf(g.field.height(x + 2, z) - h0) + absf(g.field.height(x, z + 2) - h0)
			if h0 < Water.LEVEL + 1.0 or (rivers and g.field.river_t(x, z) < 3.0):
				continue
			if s < best_slope:
				best_slope = s
				best = Vector3(x, h0 + 1.0, z)
		if best != Vector3.INF:
			return best
	return Vector3(around.x, g.field.height(around.x, around.y) + 1.0, around.y)
