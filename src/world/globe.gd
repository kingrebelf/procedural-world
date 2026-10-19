class_name Globe
## A finite world (v22): a grid of tiles (the 64 m chunks, ChunkGenerator.SIZE) laid out
## as a map of a globe, x the longitude and z the latitude (north is -z). Going far enough
## east brings you back from the west: the seam opposite the origin runs through an ocean
## generation forces there, so the land never straddles it and the switch can't be seen.
## The north and south rims are polar sea ending in pack ice you can't pass.
##
## Worlds from before v22 have no globe (on() is false) and stay endless. Set per planet
## by Planets.apply (from the world's "globe" meta); read on worker threads.

const V := 22 ## the GEN_VERSION that brings globes
const SIZES := {"small": Vector2i(128, 64), "medium": Vector2i(256, 128), "large": Vector2i(512, 256)}
const DEFAULT := "medium"
const SIZE_NAMES := ["small", "medium", "large"]
## Latitude of the origin, where you arrive: temperate, the equator to the south.
const HOME_LAT := 35.0
## Open sea either side of the seam, then the shelf over which the land comes down to
## it, as shares of the tiles round the world; the same at the poles, as shares of the
## tiles from pole to pole, measured in from the rim.
const SEAM_SEA := 0.06
const SEAM_SHELF := 0.04
const POLE_SEA := 0.06
const POLE_SHELF := 0.06
## Sea floor the forced ocean sinks to (metres; the sea is at Water.LEVEL, 0).
const DEEP := -16.0

## Tiles round the equator and pole to pole on the current planet; zero when endless.
static var tiles := Vector2i.ZERO

static func on() -> bool:
	return tiles.x > 0

## Tiles of a planet `scale` times the size of a home world of `size` (Planets' "size").
static func tiles_for(size: String, scale := 1.0) -> Vector2i:
	var t: Vector2i = SIZES.get(size, SIZES[DEFAULT])
	var h := maxi(8, int(round(t.y * scale / 8.0)) * 8)
	return Vector2i(h * 2, h)

## Metres round the equator (one turn east-west) and from pole to pole.
static func span() -> Vector2:
	return Vector2(tiles) * ChunkGenerator.SIZE

## The world's x range is [-span.x / 2, span.x / 2): the origin sits mid-way.
static func west() -> float:
	return -span().x * 0.5

## z of the north and south rims. The origin is at HOME_LAT north.
static func north() -> float:
	return -span().y * (90.0 - HOME_LAT) / 180.0

static func south() -> float:
	return north() + span().y

## Latitude at z in degrees, +90 at the north rim, -90 at the south one (0 off a globe:
## everywhere is like the home latitude then, see WorldField.climate_at).
static func latitude(z: float) -> float:
	if not on():
		return HOME_LAT
	return 90.0 - (z - north()) / span().y * 180.0

## x brought into [west, -west): the same place, the way it is stored and generated.
static func wrap_x(x: float) -> float:
	if not on():
		return x
	var w := span().x
	return fposmod(x - west(), w) + west()

## The tile key of a tile, brought round to its place inside the world.
static func wrap_tile(k: Vector2i) -> Vector2i:
	if not on():
		return k
	return Vector2i(posmod(k.x + tiles.x / 2, tiles.x) - tiles.x / 2, k.y)

## Whether tile k is one of the world's (in x after wrapping; in z between the rims).
static func contains(k: Vector2i) -> bool:
	if not on():
		return true
	var z0 := int(floor(north() / ChunkGenerator.SIZE))
	return k.y >= z0 and k.y < z0 + tiles.y

## The shortest step from a to b, going round the world east or west if that is shorter.
static func offset(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	if on():
		var w := span().x
		d.x = fposmod(d.x + w * 0.5, w) - w * 0.5
	return d

## How much of the land at (x, z) is forced down into ocean: 1 out at the seam and near
## the rims, 0 over the world's land, shelving between (so coasts stay gentle).
static func sea(x: float, z: float) -> float:
	if not on():
		return 0.0
	var sp := span()
	var from_seam := absf(wrap_x(x - west()))
	var to_rim := minf(z - north(), south() - z)
	var a := 1.0 - smoothstep(SEAM_SEA * sp.x, (SEAM_SEA + SEAM_SHELF) * sp.x, from_seam)
	var b := 1.0 - smoothstep(POLE_SEA * sp.y, (POLE_SEA + POLE_SHELF) * sp.y, to_rim)
	return maxf(a, b)

## Land shape (WorldField.shape's base, holes, relief) sunk under the forced ocean.
static func sink(sh: Vector3, x: float, z: float) -> Vector3:
	var m := sea(x, z)
	if m <= 0.0:
		return sh
	var base := minf(sh.x, lerpf(sh.x, DEEP, m))
	return Vector3(base, sh.y * (1.0 - m), sh.z * (1.0 - m))

## Where something at p may be: brought round the seam, and held inside the rims.
## Returns [new position, whether it hit a rim].
static func confine(p: Vector3) -> Array:
	if not on():
		return [p, false]
	var q := p
	q.x = wrap_x(p.x)
	var pad := 2.0
	var hit := false
	if q.z < north() + pad:
		q.z = north() + pad
		hit = true
	elif q.z > south() - pad:
		q.z = south() - pad
		hit = true
	return [q, hit]
