class_name WorldBounds
## A finite world (v22): a square of tiles (the 64 m chunks, ChunkGenerator.SIZE) with
## you starting at its centre. Its edge is a barrier you can't cross, seen as a force
## field only when you are right up against it (EdgeField). The land goes on a few tiles
## past it (MARGIN) so the world doesn't stop at a cliff, but nothing past that is built.
## Zone levels rise from the centre to MAX_LEVEL at the edge (Eras.zone_level).
##
## Worlds from before v22 have no "tiles" meta (on() is false) and stay endless. Set per
## planet by Planets.apply; read on worker threads.

const V := 22 ## the GEN_VERSION that brings finite worlds
const TILES := 1200 ## tiles along each side of a new world (76.8 km)
const MARGIN := 5 ## tiles built beyond the barrier, out of reach
const MAX_LEVEL := 1000 ## zone level at the edge
## Zone levels rise as they always did (Eras.LEVEL_STEP) out to the old cap, NEAR_LEVEL,
## then climb ever faster to MAX_LEVEL at the edge.
const NEAR_LEVEL := 55
const CLIMB := 1.6

## Tiles along a side on the current planet; zero when the world is endless.
static var tiles := 0

static func on() -> bool:
	return tiles > 0

## Tiles of a planet `scale` times the size of the home world (Planets' "size").
static func tiles_for(home_tiles: int, scale := 1.0) -> int:
	if home_tiles <= 0:
		return 0
	return maxi(16, int(round(home_tiles * scale / 8.0)) * 8)

## Metres from the centre to the barrier along x or z.
static func half() -> float:
	return tiles * ChunkGenerator.SIZE * 0.5

## Whether tile k lies inside the barrier.
static func inside(k: Vector2i) -> bool:
	if not on():
		return true
	var h := tiles / 2
	return k.x >= -h and k.x < tiles - h and k.y >= -h and k.y < tiles - h

## Whether tile k may be generated and kept: inside, or within MARGIN tiles past the edge.
static func buildable(k: Vector2i) -> bool:
	if not on():
		return true
	var h := tiles / 2
	return k.x >= -h - MARGIN and k.x < tiles - h + MARGIN and k.y >= -h - MARGIN and k.y < tiles - h + MARGIN

## Metres from (x, z) out to the nearest point of the barrier (negative past it).
static func to_edge(x: float, z: float) -> float:
	if not on():
		return INF
	return half() - maxf(absf(x), absf(z))

## Where something at p may be: held inside the barrier. Returns [new position, whether
## it touched the barrier].
static func confine(p: Vector3) -> Array:
	if not on():
		return [p, false]
	var lim := half() - 0.5
	var q := Vector3(clampf(p.x, -lim, lim), p.y, clampf(p.z, -lim, lim))
	return [q, q != p]

## Zone level `d` metres from the centre (see NEAR_LEVEL, CLIMB).
static func zone_level(d: float, base: int, step: float) -> int:
	var nl := maxi(NEAR_LEVEL, base)
	var near_d := (nl - base) * step
	if d <= near_d:
		return base + int(d / step)
	var t := clampf((d - near_d) / maxf(half() - near_d, 1.0), 0.0, 1.0)
	return mini(nl + int(round((MAX_LEVEL - nl) * pow(t, CLIMB))), MAX_LEVEL)

## How far from the centre zone level lv begins (the inverse of zone_level).
static func level_radius(lv: int, base: int, step: float) -> float:
	var nl := maxi(NEAR_LEVEL, base)
	var near_d := (nl - base) * step
	if lv <= nl:
		return (lv - base) * step
	var t := pow(float(lv - nl) / float(MAX_LEVEL - nl), 1.0 / CLIMB)
	return near_d + t * (half() - near_d)
