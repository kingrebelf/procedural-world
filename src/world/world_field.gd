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

func site_era(ix: int, iz: int) -> int:
	return WHash.hash2(seed, ix, iz, 101) % Eras.COUNT

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
	if w[Eras.MEDIEVAL] > 0.001:
		h += w[Eras.MEDIEVAL] * _medieval(x, z)
	if w[Eras.FANTASY] > 0.001:
		h += w[Eras.FANTASY] * _fantasy(x, z, w[Eras.FANTASY])
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

func _scifi(x: float, z: float) -> float:
	var base := _plate.get_noise_2d(x, z) * 34.0
	var step := 7.0
	var t := base / step
	var fl := floorf(t)
	var f := t - fl
	f = smoothstep(0.7, 1.0, f)
	return (fl + f) * step + _detail.get_noise_2d(x, z) * 0.08
