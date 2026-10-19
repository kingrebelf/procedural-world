class_name Planets
## The one world: how its land is set up for generation (the eras it allows, its snow
## line, its theme and the zone level at its origin). Worlds made since world themes
## exist are human homelands; older ones keep their mixed eras.
##
## Worlds once linked other planets reached by starship or portal. Those are gone: every
## save plays on the home world, and records still carry "planet": 0.

## eras: allowed eras (empty = all). snow: height of the snow line in metres.
const KINDS := {
	"home": {"label": "Homeworld", "eras": [], "snow": 50.0},
	"homeland": {"label": "Homeworld", "eras": [Eras.MEDIEVAL, Eras.SCIFI], "snow": 50.0, "theme": "human", "base": 1},
}

## The current world's snow line, for the terrain material (Atmosphere applies it).
static var snow_line := 50.0

## The world of seed `seed`: {n, kind, seed, theme, base, eras}. `theme` is the world's
## theme ("" for worlds from before themes).
static func home(seed: int, theme := "") -> Dictionary:
	var kind := "homeland" if theme != "" else "home"
	var k: Dictionary = KINDS[kind]
	return {"n": 0, "kind": kind, "seed": seed, "theme": String(k.get("theme", "")) if theme != "" else "",
		"base": int(k.get("base", 1)), "eras": k["eras"]}

static func kind_of(p: Dictionary) -> Dictionary:
	return KINDS.get(p.get("kind", "home"), KINDS["home"])

## Makes generation follow world `p`: its eras and snow line. Call before any world
## field, generator or chunk is made.
static func apply(p: Dictionary) -> void:
	var k := kind_of(p)
	WorldField.allowed_eras = p.get("eras", k["eras"])
	snow_line = k["snow"] # the terrain material picks it up (Atmosphere)
	Biome.snow_line = snow_line
	WorldField.snow_line = snow_line
	Eras.theme = String(p.get("theme", ""))
	Eras.base_level = int(p.get("base", 1))

## A pleasant place to arrive: gentle, dry ground near `around` (searching outward if it
## is all sea). Deterministic per seed.
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
