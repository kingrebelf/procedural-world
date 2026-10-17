class_name WorldField
extends RefCounted
## Pure, deterministic description of the world: era weights and terrain height at any
## point. Holds its own noise instances, so create one per thread.

const ERA_CELL := 512.0
const ERA_TAU := 22.0
const WARP_AMP := 70.0

var seed: int
var _cont: FastNoiseLite
var _warp: FastNoiseLite
var _hills: FastNoiseLite
var _river: FastNoiseLite
var _spires: FastNoiseLite
var _moss: FastNoiseLite
var _plate: FastNoiseLite
var _detail: FastNoiseLite
var _rivers: FastNoiseLite
var _rwarp: FastNoiseLite
var _mtn_mask: FastNoiseLite
var _ridge: FastNoiseLite
var _mesa: FastNoiseLite

## Terrain generation in force. Worlds created before v4 keep the older shapes, so chunks
## generated later still meet the ones already saved. Set when a world opens (Game).
static var terrain_v := 5

func _init(world_seed: int) -> void:
	seed = world_seed & WHash.MASK
	_cont = _noise(1, 0.0014, 4, FastNoiseLite.FRACTAL_FBM)
	_warp = _noise(2, 0.0033, 2, FastNoiseLite.FRACTAL_FBM)
	_hills = _noise(3, 0.0065, 4, FastNoiseLite.FRACTAL_FBM)
	_river = _noise(4, 0.0022, 2, FastNoiseLite.FRACTAL_FBM)
	_spires = _noise(5, 0.0085, 4, FastNoiseLite.FRACTAL_RIDGED)
	_moss = _noise(6, 0.02, 3, FastNoiseLite.FRACTAL_FBM)
	_plate = _noise(7, 0.0045, 3, FastNoiseLite.FRACTAL_FBM)
	_detail = _noise(8, 0.08, 2, FastNoiseLite.FRACTAL_FBM)
	_rivers = _noise(9, 0.0011, 3, FastNoiseLite.FRACTAL_FBM)
	_rwarp = _noise(10, 0.004, 2, FastNoiseLite.FRACTAL_FBM)
	_mtn_mask = _noise(11, 0.0007, 2, FastNoiseLite.FRACTAL_FBM)
	_ridge = _noise(12, 0.0032, 5, FastNoiseLite.FRACTAL_RIDGED)
	_ridge.fractal_gain = 0.45
	_mesa = _noise(13, 0.0055, 3, FastNoiseLite.FRACTAL_FBM)

func _noise(salt: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = WHash.hash2(seed, salt, 0, 1) & 0x7FFFFFFF
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n

# --- Eras -------------------------------------------------------------------

var _site_cache: Dictionary = {}

## Eras a planet allows (empty = all three). Set by Planets.apply before any field of
## that planet is built; read on worker threads, never changed while a world is open.
static var allowed_eras: Array = []

func site_era(ix: int, iz: int) -> int:
	var h := WHash.hash2(seed, ix, iz, 101)
	if allowed_eras.is_empty():
		return h % Eras.COUNT
	return int(allowed_eras[h % allowed_eras.size()])

## Cached [position, era] for a Voronoi site (hashing in GDScript is the hot path).
func _site(ix: int, iz: int) -> Array:
	var k := Vector2i(ix, iz)
	var s = _site_cache.get(k)
	if s == null:
		if _site_cache.size() > 4096:
			_site_cache.clear()
		s = [site_pos(ix, iz), site_era(ix, iz)]
		_site_cache[k] = s
	return s

func site_pos(ix: int, iz: int) -> Vector2:
	var jx := 0.15 + 0.7 * WHash.unit2(seed, ix, iz, 102)
	var jz := 0.15 + 0.7 * WHash.unit2(seed, ix, iz, 103)
	return Vector2((ix + jx) * ERA_CELL, (iz + jz) * ERA_CELL)

## Era weights at (x, z), summing to 1. Continuous everywhere.
func era_weights(x: float, z: float) -> PackedFloat32Array:
	var px := x + _warp.get_noise_2d(x, z) * WARP_AMP
	var pz := z + _warp.get_noise_2d(z + 913.0, x - 377.0) * WARP_AMP
	var cx := int(floor(px / ERA_CELL))
	var cz := int(floor(pz / ERA_CELL))
	var dists: Array[float] = []
	var eras: Array[int] = []
	var dmin := INF
	var p := Vector2(px, pz)
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var s := _site(cx + ox, cz + oz)
			var d := p.distance_to(s[0])
			dists.append(d)
			eras.append(s[1])
			dmin = minf(dmin, d)
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
	var total := 0.0
	for i in dists.size():
		var k := exp(-(dists[i] - dmin) / ERA_TAU)
		w[eras[i]] += k
		total += k
	for e in Eras.COUNT:
		w[e] /= total
	return w

static func dominant(w: PackedFloat32Array) -> int:
	var best := 0
	for e in w.size():
		if w[e] > w[best]:
			best = e
	return best

## Voronoi site of the region containing (x, z).
func region_site_at(x: float, z: float) -> Vector2i:
	var px := x + _warp.get_noise_2d(x, z) * WARP_AMP
	var pz := z + _warp.get_noise_2d(z + 913.0, x - 377.0) * WARP_AMP
	var cx := int(floor(px / ERA_CELL))
	var cz := int(floor(pz / ERA_CELL))
	var best := Vector2i.ZERO
	var dmin := INF
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var d := Vector2(px, pz).distance_to(_site(cx + ox, cz + oz)[0])
			if d < dmin:
				dmin = d
				best = Vector2i(cx + ox, cz + oz)
	return best

## Stable hash of the region containing (x, z); seeds its biome (see Biome).
func region_hash_at(x: float, z: float) -> int:
	var s := region_site_at(x, z)
	return WHash.hash2(seed, s.x, s.y, 104)

## Name of the region containing (x, z): stable per Voronoi site.
func region_name_at(x: float, z: float) -> String:
	var best := region_site_at(x, z)
	return Eras.region_name(site_era(best.x, best.y), WHash.hash2(seed, best.x, best.y, 104))

# --- Terrain ----------------------------------------------------------------

func height(x: float, z: float, w: PackedFloat32Array = PackedFloat32Array()) -> float:
	if w.is_empty():
		w = era_weights(x, z)
	var h := _cont.get_noise_2d(x, z) * 38.0 + 12.0
	var v4 := terrain_v >= 4
	if w[Eras.MEDIEVAL] > 0.001:
		h += w[Eras.MEDIEVAL] * (_medieval4(x, z, w[Eras.MEDIEVAL]) if v4 else _medieval(x, z))
	if w[Eras.FANTASY] > 0.001:
		h += w[Eras.FANTASY] * (_fantasy4(x, z, w[Eras.FANTASY]) if v4 else _fantasy(x, z, w[Eras.FANTASY]))
	if w[Eras.SCIFI] > 0.001:
		h += w[Eras.SCIFI] * _scifi(x, z)
	return h

func _medieval(x: float, z: float) -> float:
	var hills := _hills.get_noise_2d(x, z) * 13.0
	var r := 1.0 - absf(_river.get_noise_2d(x, z))
	var valley := pow(r, 8.0) * 9.0
	return hills - valley + _detail.get_noise_2d(x, z) * 0.35

## Spires only rise deep inside fantasy regions, so borders stay gentle and the
## landscape grows stranger the further in you walk.
func _fantasy(x: float, z: float, wf: float = 1.0) -> float:
	var s := (_spires.get_noise_2d(x, z) + 1.0) * 0.5
	var spires := pow(s, 2.4) * 44.0 * smoothstep(0.65, 0.98, wf)
	return spires + _moss.get_noise_2d(x, z) * 3.5 - 6.0

## v4: the same farmland hills, but some regions rise into rocky highlands: ridged,
## weathered mountains whose crests are rounded by the gain falloff, not knife edges.
func _medieval4(x: float, z: float, wm: float) -> float:
	var h := _medieval(x, z)
	var m := smoothstep(0.05, 0.45, _mtn_mask.get_noise_2d(x, z)) * smoothstep(0.6, 0.95, wm)
	if m <= 0.0:
		return h
	var r := (_ridge.get_noise_2d(x, z) + 1.0) * 0.5
	# Soften the very crest so peaks are worn rather than spiked.
	r = r - 0.35 * smoothstep(0.82, 1.0, r) * (r - 0.82)
	return h + pow(r, 1.7) * 62.0 * m

## v4: instead of needle spires, the fey lands lift into flat-topped mesas and stepped
## tablelands with steep rock faces, rising in two tiers deep inside fantasy regions.
func _fantasy4(x: float, z: float, wf: float) -> float:
	var s := (_mesa.get_noise_2d(x, z) + 1.0) * 0.5
	var deep := smoothstep(0.6, 0.95, wf)
	var mesa := smoothstep(0.54, 0.66, s) * 16.0 + smoothstep(0.68, 0.77, s) * 12.0
	return mesa * deep + _moss.get_noise_2d(x, z) * 3.5 + _detail.get_noise_2d(x, z) * 0.3 - 6.0

func _scifi(x: float, z: float) -> float:
	var base := _plate.get_noise_2d(x, z) * 34.0
	var step := 7.0
	var t := base / step
	var fl := floorf(t)
	var f := t - fl
	f = smoothstep(0.7, 1.0, f)
	return (fl + f) * step + _detail.get_noise_2d(x, z) * 0.08

# --- Rivers -----------------------------------------------------------------
## Rivers follow the zero line of a low-frequency noise, so they wind for kilometres and
## never end abruptly. Their water sits at a smoothed copy of the land (the valley level
## they would have cut over time), so a river runs between banks instead of hanging on
## a hillside, and it fades out where the land rises far above it (high peaks) or sinks
## below the sea (where it becomes an estuary).

const RIVER_W := 0.02 ## half-width, in noise units (about 10-16 m on the ground)
const RIVER_CELL := 8.0 ## the smoothed water level is sampled on this global grid
const RIVER_REACH := 6.0 ## channel half-widths over which the valley sides fade out
const RIVER_DEPTH := 2.4

## Distance from the river's centre in half-widths (0 = centre, 1 = the water's edge).
func river_t(x: float, z: float) -> float:
	var wx := x + _rwarp.get_noise_2d(x, z) * 60.0
	var wz := z + _rwarp.get_noise_2d(x + 917.0, z - 433.0) * 60.0
	return absf(_rivers.get_noise_2d(wx, wz)) / RIVER_W

## Water level at a river grid node: just below the lowest ground within ~40 m, so the
## river always sits in the bottom of its valley (never up on an embankment).
func _river_node(ix: int, iz: int) -> float:
	var x := ix * RIVER_CELL
	var z := iz * RIVER_CELL
	var lo := INF
	for o in [Vector2(0, 0), Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40),
			Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20),
			Vector2(28, 28), Vector2(-28, 28), Vector2(28, -28), Vector2(-28, -28)]:
		lo = minf(lo, height(x + o.x, z + o.y))
	return lo - 0.4

## The river's water level at (x, z); `cache` (Vector2i -> float) avoids recomputing nodes.
func river_level(x: float, z: float, cache: Dictionary) -> float:
	var gx := floorf(x / RIVER_CELL)
	var gz := floorf(z / RIVER_CELL)
	var fx := x / RIVER_CELL - gx
	var fz := z / RIVER_CELL - gz
	var v := [0.0, 0.0, 0.0, 0.0]
	for n in 4:
		var k := Vector2i(int(gx) + n % 2, int(gz) + n / 2)
		if not cache.has(k):
			cache[k] = _river_node(k.x, k.y)
		v[n] = cache[k]
	return lerpf(lerpf(v[0], v[1], fx), lerpf(v[2], v[3], fx), fz)

## How strongly a river is present (0..1) given the land's height and the water level:
## none where the land towers over it, none below the sea.
static func river_strength(land: float, level: float) -> float:
	return (1.0 - smoothstep(12.0, 22.0, land - level)) * smoothstep(0.2, 1.2, level)

## Carves the river channel and banks into a terrain height.
static func carve_river(h: float, t: float, level: float, m: float) -> float:
	if m <= 0.0 or t >= RIVER_REACH:
		return h
	# Fully cut wherever the water shows (strength 0.3 and up), fading below that.
	m = smoothstep(0.05, 0.3, m)
	var target: float
	if t < 1.0:
		target = level - RIVER_DEPTH * (1.0 - t * t)
		return lerpf(h, minf(h, target), m)
	# Banks: a broad valley whose sides rise gently from just above the water, so the
	# river sits in a vale instead of a cut with cliff walls.
	var u := t - 1.0
	var bank := level + 0.3 + u * 0.8 + u * u * 0.3
	if h > bank:
		return lerpf(h, bank, m * (1.0 - smoothstep(1.5, RIVER_REACH, t)))
	return h
