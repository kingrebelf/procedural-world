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
var _cell_d: FastNoiseLite
var _cell_v: FastNoiseLite
var _cell_e: FastNoiseLite
var _wind := Vector2.RIGHT

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
	# One Voronoi pattern, scaled per landform: distance to the nearest point, that
	# point's random value, and the distance to the edge of its cell.
	_cell_d = _cellular(14, FastNoiseLite.RETURN_DISTANCE)
	_cell_v = _cellular(14, FastNoiseLite.RETURN_CELL_VALUE)
	_cell_e = _cellular(14, FastNoiseLite.RETURN_DISTANCE2_SUB)
	_wind = Vector2.RIGHT.rotated(WHash.unit2(seed, 0, 0, 106) * TAU)

func _noise(salt: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = WHash.hash2(seed, salt, 0, 1) & 0x7FFFFFFF
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n

func _cellular(salt: int, ret: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.seed = WHash.hash2(seed, salt, 0, 1) & 0x7FFFFFFF
	n.frequency = 1.0 / CELL
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_jitter = 0.85
	n.cellular_return_type = ret
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
	if Eras.themed() and allowed_eras.size() == 2:
		# Themed worlds progress outward: the first era all round the origin, the second
		# appearing past the frontier and taking over most of the far land.
		var d := site_pos(ix, iz).length()
		var far := smoothstep(Eras.FRONTIER, Eras.HEARTLAND, d) * 0.8
		return int(allowed_eras[1 if WHash.unit2(seed, ix, iz, 107) < far else 0])
	return int(allowed_eras[h % allowed_eras.size()])

## Cached [position, era] for a Voronoi site (hashing in GDScript is the hot path).
func _site(ix: int, iz: int) -> Array:
	var k := Vector2i(ix, iz)
	var s = _site_cache.get(k)
	if s == null:
		if _site_cache.size() > 4096:
			_site_cache.clear()
		s = [site_pos(ix, iz), site_era(ix, iz), site_landform(ix, iz)]
		_site_cache[k] = s
	return s

func site_pos(ix: int, iz: int) -> Vector2:
	var jx := 0.15 + 0.7 * WHash.unit2(seed, ix, iz, 102)
	var jz := 0.15 + 0.7 * WHash.unit2(seed, ix, iz, 103)
	return Vector2((ix + jx) * ERA_CELL, (iz + jz) * ERA_CELL)

## Era weights at (x, z), summing to 1. Continuous everywhere.
func era_weights(x: float, z: float) -> PackedFloat32Array:
	return _mix(x, z, 1, Eras.COUNT)

## How much of each landform shapes the land at (x, z) (v7; all zero before). Same
## blend as the eras, so a landform fades out over the last few tens of metres.
func landform_weights(x: float, z: float) -> PackedFloat32Array:
	if terrain_v < 7:
		var none := PackedFloat32Array()
		none.resize(LF_COUNT)
		return none
	return _mix(x, z, 2, LF_COUNT)

## Weights of a per-site property (1: era, 2: landform) from the nearest sites.
func _mix(x: float, z: float, field_i: int, count: int) -> PackedFloat32Array:
	var px := x + _warp.get_noise_2d(x, z) * WARP_AMP
	var pz := z + _warp.get_noise_2d(z + 913.0, x - 377.0) * WARP_AMP
	var cx := int(floor(px / ERA_CELL))
	var cz := int(floor(pz / ERA_CELL))
	var dists: Array[float] = []
	var kinds: Array[int] = []
	var dmin := INF
	var p := Vector2(px, pz)
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var s := _site(cx + ox, cz + oz)
			var d := p.distance_to(s[0])
			dists.append(d)
			kinds.append(s[field_i])
			dmin = minf(dmin, d)
	var w := PackedFloat32Array()
	w.resize(count)
	var total := 0.0
	for i in dists.size():
		var k := exp(-(dists[i] - dmin) / ERA_TAU)
		w[kinds[i]] += k
		total += k
	for e in count:
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
	var h := WHash.hash2(seed, best.x, best.y, 104)
	var era := site_era(best.x, best.y)
	var lf: int = _site(best.x, best.y)[2]
	if lf != LF_NONE:
		var p: Array = Eras.REGION_PREFIX[era]
		return "%s %s" % [p[h % p.size()], LANDFORM_NOUNS[lf]]
	return Eras.region_name(era, h)

# --- Terrain ----------------------------------------------------------------

func height(x: float, z: float, w: PackedFloat32Array = PackedFloat32Array(), lw: PackedFloat32Array = PackedFloat32Array()) -> float:
	var s := shape(x, z, w, lw)
	return s.x + s.y + s.z

## The land at (x, z) in three parts: x the smooth base that roads, rivers and
## settlements plan on, y the holes in it (craters, sinkholes, gorges; roads bridge
## them) and z the rough relief on it (towers, tors, dunes; roads cut through). Before
## v7 there is only the base.
func shape(x: float, z: float, w: PackedFloat32Array = PackedFloat32Array(), lw: PackedFloat32Array = PackedFloat32Array()) -> Vector3:
	if w.is_empty():
		w = era_weights(x, z)
	var c := _cont.get_noise_2d(x, z) * 38.0 + 12.0
	var h := c
	var v4 := terrain_v >= 4
	if w[Eras.MEDIEVAL] > 0.001:
		h += w[Eras.MEDIEVAL] * (_medieval4(x, z, w[Eras.MEDIEVAL]) if v4 else _medieval(x, z))
	if w[Eras.FANTASY] > 0.001:
		h += w[Eras.FANTASY] * (_fantasy4(x, z, w[Eras.FANTASY]) if v4 else _fantasy(x, z, w[Eras.FANTASY]))
	if w[Eras.SCIFI] > 0.001:
		h += w[Eras.SCIFI] * _scifi(x, z)
	if terrain_v < 7:
		return Vector3(h, 0.0, 0.0)
	if lw.is_empty():
		lw = landform_weights(x, z)
	var keep := 1.0
	var out := Vector3.ZERO
	for lf in range(1, LF_COUNT):
		if lw[lf] <= LF_FADE.x:
			continue
		var a := smoothstep(LF_FADE.x, LF_FADE.y, lw[lf])
		keep -= a
		out += _landform(lf, x, z, c, h) * a
	out.x += h * maxf(keep, 0.0)
	return out

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

# --- Landforms (v7) -----------------------------------------------------------
## In v7 worlds every region also has a landform of its own, so two regions of one era
## can be rolling farmland and a forest of limestone towers. Each landform gives a
## smooth base, holes and rough relief (see shape()).

enum { LF_NONE, LF_KARST, LF_NEEDLES, LF_SINKHOLES, LF_CRAGS, LF_GORGE, LF_TERRACES, LF_LAKES, LF_DUNES, LF_CRATERS, LF_BADLANDS }
const LF_COUNT := 11
const LANDFORM_NAMES := ["Rolling", "Karst Towers", "Needles", "Sinkholes", "Crags", "Gorges", "Terraces", "Lakes", "Dunes", "Craters", "Badlands"]
## What a region with the landform is called ("Vael Pillars").
const LANDFORM_NOUNS := ["", "Pillars", "Needles", "Sinks", "Crags", "Gorge", "Terraces", "Lakes", "Dunes", "Craters", "Badlands"]
## [landform, chance weight] by era.
const LANDFORM_ODDS := [
	[[LF_NONE, 4.0], [LF_CRAGS, 2.0], [LF_GORGE, 1.0], [LF_TERRACES, 1.0], [LF_LAKES, 1.2], [LF_SINKHOLES, 0.5], [LF_KARST, 0.5], [LF_BADLANDS, 0.4]],
	[[LF_NONE, 3.0], [LF_KARST, 2.2], [LF_NEEDLES, 1.3], [LF_SINKHOLES, 1.0], [LF_TERRACES, 0.8], [LF_LAKES, 1.0]],
	[[LF_NONE, 3.0], [LF_DUNES, 2.0], [LF_CRATERS, 2.0], [LF_BADLANDS, 1.5], [LF_GORGE, 1.0], [LF_NEEDLES, 0.4]],
]
## How each landform looks: [rock colour, how much of it, ground colour, how much of
## it, soft (sand: no bare rock on its slopes), strata (banded layers in the rock)].
const LANDFORM_LOOK := [
	[Color(0, 0, 0), 0.0, Color(0, 0, 0), 0.0, 0.0, 0.0],
	[Color(0.66, 0.64, 0.58), 0.85, Color(0, 0, 0), 0.0, 0.0, 0.45], # karst: pale limestone
	[Color(0.33, 0.32, 0.34), 0.9, Color(0, 0, 0), 0.0, 0.0, 0.45], # needles: basalt (real basalt is about 0.1 albedo, so it still shows in shade), faintly banded
	[Color(0.6, 0.58, 0.52), 0.8, Color(0, 0, 0), 0.0, 0.0, 0.6], # sinkholes: limestone
	[Color(0.55, 0.5, 0.48), 0.75, Color(0, 0, 0), 0.0, 0.0, 0.0], # crags: granite
	[Color(0.68, 0.4, 0.25), 0.9, Color(0.62, 0.45, 0.3), 0.35, 0.0, 1.0], # gorges: red sandstone
	[Color(0, 0, 0), 0.0, Color(0, 0, 0), 0.0, 0.0, 0.0], # terraces
	[Color(0.42, 0.42, 0.4), 0.4, Color(0, 0, 0), 0.0, 0.0, 0.0], # lakes: grey shore stone
	[Color(0.72, 0.58, 0.42), 0.8, Color(0.8, 0.66, 0.46), 1.0, 1.0, 0.3], # dunes: pale yellow sand (not orange clay)
	[Color(0.37, 0.355, 0.345), 0.8, Color(0.46, 0.43, 0.4), 0.75, 0.0, 0.0], # craters: grey dust
	[Color(0.7, 0.44, 0.32), 0.9, Color(0.64, 0.46, 0.34), 0.6, 0.0, 1.0], # badlands: banded clay
]

## The look of the land for landform weights `lw` as 12 bytes: rock rgb + amount,
## ground rgb + amount, soft, strata, 0, 0 (vertex data for the terrain shader).
static func look_bytes(lw: PackedFloat32Array, out: PackedByteArray, at: int) -> void:
	var stone := Color(0, 0, 0, 0)
	var ground := Color(0, 0, 0, 0)
	var sk := 0.0
	var gk := 0.0
	var soft := 0.0
	var strata := 0.0
	for lf in range(1, LF_COUNT):
		if lw[lf] <= LF_FADE.x:
			continue
		var a := smoothstep(LF_FADE.x, LF_FADE.y, lw[lf])
		var lk: Array = LANDFORM_LOOK[lf]
		var gamt := float(lk[3])
		if lf == LF_CRATERS and Eras.theme == "human":
			# A human world's craters are old and grassed over, bare dust only in patches.
			gamt *= 0.35
		stone += (lk[0] as Color) * a * float(lk[1])
		sk += a * float(lk[1])
		ground += (lk[2] as Color) * a * gamt
		gk += a * gamt
		soft += a * float(lk[4])
		strata += a * float(lk[5])
	if sk > 0.0:
		stone /= sk
	if gk > 0.0:
		ground /= gk
	var v := [stone.r, stone.g, stone.b, sk, ground.r, ground.g, ground.b, gk, soft, strata, 0.0, 0.0]
	for i in 12:
		out[at + i] = int(round(clampf(v[i], 0.0, 1.0) * 255.0))

## Tree and boulder density multipliers by landform (lush karst valleys, bare dunes).
const LANDFORM_TREES := [1.0, 1.4, 0.8, 1.0, 0.7, 0.6, 0.8, 1.0, 0.08, 0.5, 0.35]
const LANDFORM_ROCKS := [1.0, 1.5, 1.6, 1.2, 2.6, 1.3, 0.6, 0.8, 0.15, 1.4, 1.5]

## A landform's weight fades its shape in between these (it is 1 deep in its region).
const LF_FADE := Vector2(0.3, 0.85)
const CELL := 40.0

func site_landform(ix: int, iz: int) -> int:
	if terrain_v < 7:
		return LF_NONE
	var odds: Array = LANDFORM_ODDS[site_era(ix, iz)]
	var total := 0.0
	for o in odds:
		total += o[1]
	var pick := WHash.unit2(seed, ix, iz, 105) * total
	for o in odds:
		pick -= o[1]
		if pick <= 0.0:
			return o[0]
	return LF_NONE

## The landform of the region containing (x, z).
func landform_at(x: float, z: float) -> int:
	var s := region_site_at(x, z)
	return _site(s.x, s.y)[2]

## Voronoi cells `size` metres across: (distance to the cell's point, the cell's random
## value 0..1, distance to the cell's edge), all in metres.
func _cell(x: float, z: float, size: float, off: float) -> Vector3:
	var k := CELL / size
	var px := x * k + off
	var pz := z * k - off * 0.61
	return Vector3((_cell_d.get_noise_2d(px, pz) + 1.0) * size,
		(_cell_v.get_noise_2d(px, pz) + 1.0) * 0.5,
		(_cell_e.get_noise_2d(px, pz) + 1.0) * size * 0.5)

## Terraces `step` metres high with short risers (rice paddies, strata, stacked tors).
static func _steps(h: float, step: float, riser := 0.25) -> float:
	var t := h / step
	var f := floorf(t)
	return (f + smoothstep(1.0 - riser, 1.0, t - f)) * step

## (base, holes, rough) of one landform; c is the continental height, h the land the
## era alone would have.
func _landform(lf: int, x: float, z: float, c: float, h: float) -> Vector3:
	match lf:
		LF_KARST:
			# Limestone towers with sheer sides and rounded, wooded tops over flat green
			# valley floors (Guilin, Zhangjiajie).
			var base := c * 0.55 + 3.0 + _moss.get_noise_2d(x, z) * 2.5
			var cl := _cell(x, z, 42.0, 0.0)
			if cl.y < 0.42:
				return Vector3(base, 0.0, 0.0)
			var t := (cl.y - 0.42) / 0.58
			var r := 9.0 + 8.0 * t
			var q := clampf((cl.x + _detail.get_noise_2d(x * 0.5, z * 0.5) * 3.0) / r, 0.0, 2.0)
			var tall := 20.0 + 44.0 * t
			var tower := tall * (1.0 - pow(minf(q, 1.0), 5.0)) + 3.0 * maxf(0.0, 1.0 - q * q)
			tower += 4.0 * t * (1.0 - smoothstep(0.85, 1.6, q))
			if terrain_v >= 15:
				# v15: weathered limestone, not smooth bullets. Vertical joints flute the
				# walls (sharp creases where a noise crosses zero), bedding planes step them
				# in ledges every few metres (each tower its own spacing), the crown is
				# broken and uneven, and no tower stands quite straight.
				var lean := _moss.get_noise_2d(x * 0.7 + 300.0, z * 0.7) * 2.5
				var joints := (absf(_detail.get_noise_2d(x * 1.3 + 70.0, z * 1.3)) - 0.25) * 3.0
				var qf := clampf((cl.x + _detail.get_noise_2d(x * 0.5, z * 0.5) * 3.0 + lean + joints) / r, 0.0, 2.0)
				var body := tall * (1.0 - pow(minf(qf, 1.0), 3.2))
				var tier := 6.0 + 5.0 * fposmod(cl.y * 53.0, 1.0)
				var crown := _detail.get_noise_2d(x * 0.35 + 11.0, z * 0.35) * 4.0 * t
				var stepped := _steps(body + crown + _detail.get_noise_2d(x * 0.8 + 5.0, z * 0.8) * 1.5, tier, 0.35)
				tower = lerpf(body, stepped, 0.8) + 1.5 * maxf(0.0, 1.0 - qf * qf) + 4.0 * t * (1.0 - smoothstep(0.85, 1.6, qf))
			return Vector3(base, 0.0, tower * smoothstep(0.0, 4.0, cl.z))
		LF_NEEDLES:
			# Thin pointed rock needles.
			var base := c * 0.7 + _moss.get_noise_2d(x, z) * 3.0 - 3.0
			var cl := _cell(x, z, 34.0, 517.0)
			if cl.y < 0.5:
				return Vector3(base, 0.0, 0.0)
			var t := (cl.y - 0.5) / 0.5
			var r := 7.0 + 5.0 * t
			var bumps := _detail.get_noise_2d(x, z) * 1.2
			if terrain_v >= 12:
				# v12: no two alike and none a perfect cone: leaning, lopsided, with
				# weathered grooves running down their sides.
				bumps += _moss.get_noise_2d(x * 0.7, z * 0.7) * 3.0 + _detail.get_noise_2d(x * 3.2 + 91.0, z * 3.2) * 0.8
			var q := clampf((cl.x + bumps) / r, 0.0, 2.0)
			var spike := (26.0 + 50.0 * t) * pow(maxf(0.0, 1.0 - q), 1.7) + 3.0 * (1.0 - smoothstep(0.7, 1.6, q))
			if terrain_v >= 14:
				# v14: broken rock, not cones. Fluted sides (sharp creases where a noise
				# crosses zero), a fuller body that narrows in tilted, ledged tiers (each
				# needle its own tier height), and lesser spires crowding round the feet
				# of the big ones.
				var qf := clampf(q + (absf(_detail.get_noise_2d(x * 1.6 + 40.0, z * 1.6)) - 0.3) * 4.0 / r, 0.0, 2.0)
				var body := (26.0 + 50.0 * t) * pow(maxf(0.0, 1.0 - qf), 1.3)
				var tier := 5.0 + 4.0 * fposmod(cl.y * 37.0, 1.0)
				var warped := body + _detail.get_noise_2d(x * 0.9 + 17.0, z * 0.9) * 2.5
				spike = lerpf(body, _steps(warped, tier, 0.4), 0.85) + 3.0 * (1.0 - smoothstep(0.7, 1.6, q))
				var c2 := _cell(x, z, 15.0, 2203.0)
				if c2.y > 0.45:
					var t2 := (c2.y - 0.45) / 0.55
					var q2 := clampf((c2.x + bumps * 0.6) / (3.5 + 2.5 * t2), 0.0, 1.0)
					var near := 1.0 - smoothstep(r * 1.2, r * 2.6, cl.x)
					spike = maxf(spike, (8.0 + 20.0 * t2) * near * pow(1.0 - q2, 1.5) * smoothstep(0.0, 2.0, c2.z))
			return Vector3(base, 0.0, spike * smoothstep(0.0, 3.0, cl.z))
		LF_SINKHOLES:
			# A raised plain pocked with round, sheer-sided sinkholes; the deepest hold water.
			var base := h + 6.0
			var cl := _cell(x, z, 56.0, 1031.0)
			if cl.y < 0.5:
				return Vector3(base, 0.0, 0.0)
			var t := (cl.y - 0.5) / 0.5
			var r := 8.0 + 9.0 * t
			var q := (cl.x + _detail.get_noise_2d(x * 0.6, z * 0.6) * 2.0) / r
			var hole := -(12.0 + 16.0 * t) * (1.0 - smoothstep(0.82, 1.0, q)) * (1.0 - 0.15 * minf(q * q, 1.0))
			return Vector3(base, hole * smoothstep(0.0, 4.0, cl.z), 0.0)
		LF_CRAGS:
			# Rugged ridges with ribs of bare rock and stacked granite tors.
			var r2 := (_ridge.get_noise_2d(x, z) + 1.0) * 0.5
			var base := h + pow(r2, 1.6) * 30.0
			var n := (_spires.get_noise_2d(x * 2.2 + 731.0, z * 2.2) + 1.0) * 0.5
			var m := smoothstep(0.62, 0.72, n)
			if m <= 0.0:
				return Vector3(base, 0.0, 0.0)
			var tor := m * (4.0 + 9.0 * (_detail.get_noise_2d(x * 0.2, z * 0.2) + 1.0) * 0.5)
			return Vector3(base, 0.0, _steps(tor, 1.5, 0.3))
		LF_GORGE:
			# A high plain split by winding, stepped canyons.
			var base := c + 14.0 + _hills.get_noise_2d(x, z) * 5.0
			var g := absf(_river.get_noise_2d(x * 1.3 + 5000.0, z * 1.3))
			var cw := 1.0 - smoothstep(0.025, 0.075, g)
			if cw <= 0.0:
				return Vector3(base, 0.0, 0.0)
			return Vector3(base, -_steps(cw * 4.0, 1.0, 0.4) * 7.5, 0.0)
		LF_TERRACES:
			# Hillsides stepped into flat terraces.
			var base := h * 1.2 + 3.0
			if terrain_v >= 13:
				# v13: deeper steps with wider banks between them, so a terrace edge spans a
				# few metres of ground and reads as a bank, not a saw-tooth on the 1 m grid.
				return Vector3(base, 0.0, _steps(base, 3.0, 0.42) - base)
			return Vector3(base, 0.0, _steps(base, 2.4, 0.22) - base)
		LF_LAKES:
			# Low country with as much water as land: lakes, islands and long peninsulas.
			var base := 0.5 + _hills.get_noise_2d(x, z) * 11.0 + _moss.get_noise_2d(x, z) * 1.5 + (c - 12.0) * 0.12
			return Vector3(base, 0.0, 0.0)
		LF_DUNES:
			# Crescent dunes marching downwind: long gentle backs, steep slip faces.
			var base := c * 0.4 + 5.0 + _plate.get_noise_2d(x, z) * 5.0
			var u := (x * _wind.x + z * _wind.y) / 36.0 + _rwarp.get_noise_2d(x * 0.7, z * 0.7) * 1.4 + _hills.get_noise_2d(z, x) * 0.9
			var f := u - floorf(u)
			var prof := sin(f / 0.72 * PI * 0.5) if f < 0.72 else cos((f - 0.72) / 0.28 * PI * 0.5)
			var along := (z * _wind.x - x * _wind.y) / 70.0 + _rwarp.get_noise_2d(z * 0.5, x * 0.5) * 1.2
			var amp := (3.0 + 4.0 * (0.5 + 0.5 * sin(along * TAU))) * (0.6 + 0.4 * (_mesa.get_noise_2d(x, z) + 1.0) * 0.5)
			return Vector3(base, 0.0, (prof - 0.45) * amp)
		LF_CRATERS:
			# Plains scarred by impact craters with raised rims, big ones with central peaks.
			var base := c * 0.5 + 6.0 + _plate.get_noise_2d(x, z) * 7.0
			if terrain_v >= 16:
				var hr := _craters_v16(x, z)
				return Vector3(base, hr.x, hr.y)
			var holes := 0.0
			var rough := 0.0
			var cl := _cell(x, z, 120.0, 2203.0)
			if cl.y >= 0.35:
				var t := (cl.y - 0.35) / 0.65
				var r := 14.0 + 34.0 * t
				var q := cl.x / r
				var fade := smoothstep(0.0, 8.0, cl.z)
				holes = -0.22 * r * maxf(0.0, 1.0 - q * q) * fade
				rough = (0.07 * r + 1.0) * exp(-pow((q - 1.0) / 0.2, 2.0)) * fade
				if q > 1.0:
					rough += 0.03 * r * exp(-(q - 1.0) * 2.5) * fade
				if r > 34.0:
					rough += 0.11 * r * exp(-pow(q / 0.16, 2.0)) * fade
			var sm := _cell(x, z, 30.0, 3301.0)
			if sm.y >= 0.6:
				var r := 3.0 + 6.0 * (sm.y - 0.6) / 0.4
				var q := sm.x / r
				var fade := smoothstep(0.0, 2.0, sm.z)
				holes -= 0.25 * r * maxf(0.0, 1.0 - q * q) * fade
				rough += 0.06 * r * exp(-pow((q - 1.0) / 0.25, 2.0)) * fade
			return Vector3(base, holes, rough)
		LF_BADLANDS:
			# Eroded ridges and gullies in banded layers.
			var base := c * 0.6 + 8.0
			var n := (_spires.get_noise_2d(x * 1.4 - 911.0, z * 1.4) + 1.0) * 0.5
			return Vector3(base, 0.0, _steps(pow(n, 1.8) * 30.0, 3.5, 0.45))
	return Vector3(h, 0.0, 0.0)

# --- Craters (v16) --------------------------------------------------------------------
## Impact craters as they are: a bowl whose walls steepen up to a sharp, raised crest
## (higher in places, never a perfect circle), a steep outer flank, then the ejecta
## blanket thrown out round it, lumpy and thinning with distance; the big ones
## flat-floored with a central peak. Small fresh pits pock the plain between them.

const CRATER_CELL := 120.0
const CRATER_SALT := 2203.0

## [bowl radius, how round (rim wobble), rim height, cell fade, blanket fade, q (distance
## over radius)] of the big crater whose cell holds (x, z), or [] if that cell has none.
func _crater_at(x: float, z: float) -> Array:
	var cl := _cell(x, z, CRATER_CELL, CRATER_SALT)
	if cl.y < 0.35:
		return []
	var t := (cl.y - 0.35) / 0.65
	var r := 14.0 + 34.0 * t
	var q := (cl.x + _detail.get_noise_2d(x * 0.25, z * 0.25) * r * 0.09) / r
	var rim := (0.09 * r + 1.2) * (0.75 + 0.5 * (_moss.get_noise_2d(x * 0.08 + 40.0, z * 0.08) + 1.0) * 0.5)
	return [r, cl.y, rim, smoothstep(0.0, 8.0, cl.z), smoothstep(0.0, 28.0, cl.z), q]

## (holes, rough) of the v16 crater field at (x, z).
func _craters_v16(x: float, z: float) -> Vector2:
	var holes := 0.0
	var rough := 0.0
	var cr := _crater_at(x, z)
	if not cr.is_empty():
		var r: float = cr[0]
		var h: float = cr[2]
		var fade: float = cr[3]
		var q: float = cr[5]
		if q < 1.0:
			# The bowl: walls steepening to the crest, the big ones flat-floored.
			var fq := 0.4 * smoothstep(28.0, 46.0, r)
			var bq := clampf((q - fq) / (1.0 - fq), 0.0, 1.0)
			holes = -0.25 * r * (1.0 - pow(bq, 2.2))
			rough = h * pow(q, 8.0)
		else:
			# The outer flank (gentler than the inner wall, so it grasses over rather than
			# showing bare rock), then the blanket of ejecta, lumpy and thinning.
			var o := q - 1.0
			var hum := lerpf(1.0, 0.55 + 0.9 * (_detail.get_noise_2d(x * 0.32 + 7.0, z * 0.32) + 1.0) * 0.5, smoothstep(0.0, 0.2, o))
			rough = h * (0.5 * exp(-o / 0.2) + 0.5 * pow(1.0 + o / 0.55, -2.0) * hum * lerpf(1.0, float(cr[4]), smoothstep(0.0, 0.3, o)))
		if r > 34.0:
			rough += 0.11 * r * exp(-pow(q / 0.16, 2.0))
		holes *= fade
		rough *= fade
	var sm := _cell(x, z, 30.0, 3301.0)
	if sm.y >= 0.6:
		var r := 3.0 + 6.0 * (sm.y - 0.6) / 0.4
		var q := (sm.x + _detail.get_noise_2d(x * 0.9, z * 0.9) * r * 0.08) / r
		var fade := smoothstep(0.0, 2.0, sm.z)
		var h := 0.1 * r + 0.25
		holes -= 0.28 * r * maxf(0.0, 1.0 - pow(q, 2.2)) * fade
		rough += (h * pow(minf(q, 1.0), 6.0) if q < 1.0 else h * (0.6 * exp(-(q - 1.0) / 0.12) + 0.4 * pow(1.0 + (q - 1.0) / 0.5, -2.0))) * fade
	return Vector2(holes, rough)

## How much fresh crater spoil shows at (x, z), 0..1 (v16): broken rock along the crests
## and the upper walls, and the ejecta blanket in rays of paler spoil round each crater.
## The look's byte 11 (scaled by the landform's weight).
## `grassed`: an old crater on a human world, long grown over, bare only where its steep
## inner lip keeps crumbling.
func crater_spoil(x: float, z: float, grassed := false) -> float:
	if terrain_v < 16:
		return 0.0
	var cr := _crater_at(x, z)
	if cr.is_empty():
		return 0.0
	var q: float = cr[5]
	if grassed:
		var lip := exp(-pow((q - 0.94) / 0.06, 2.0))
		return clampf(lip * (0.55 + 0.6 * (_detail.get_noise_2d(x * 0.15 + 33.0, z * 0.15) + 1.0) * 0.5) * float(cr[4]), 0.0, 1.0)
	var crest := exp(-pow((q - 1.0) / 0.13, 2.0))
	# Rays: the direction out from the crater's middle, from the slope of the distance.
	var d0 := _cell(x, z, CRATER_CELL, CRATER_SALT).x
	var a := atan2(_cell(x, z + 0.5, CRATER_CELL, CRATER_SALT).x - d0, _cell(x + 0.5, z, CRATER_CELL, CRATER_SALT).x - d0)
	var ray := smoothstep(0.4, 0.85, (_detail.get_noise_2d(cos(a) * 6.0 + float(cr[1]) * 400.0, sin(a) * 6.0) + 1.0) * 0.5)
	var o := maxf(q - 1.0, 0.0)
	var blanket := (pow(1.0 + o / 0.7, -2.0) if q >= 1.0 else smoothstep(0.7, 1.0, q)) * (0.35 + 0.65 * ray)
	return clampf(maxf(crest, blanket * 0.85) * float(cr[4]), 0.0, 1.0)

## (v16) How many loose boulders lie here in a crater field, as a factor on the rock
## density: few on the swept floor, most heaped on the inner wall and crest, then thinning
## over the blanket, always in clumps rather than an even sprinkle.
func crater_rocks(x: float, z: float) -> float:
	var cr := _crater_at(x, z)
	var clump := smoothstep(0.42, 0.72, (_detail.get_noise_2d(x * 0.06 + 91.0, z * 0.06) + 1.0) * 0.5)
	var k := 0.5
	if not cr.is_empty():
		var q: float = cr[5]
		k = lerpf(0.1, 2.6, smoothstep(0.7, 0.95, q)) * (1.0 - smoothstep(1.1, 1.6, q)) + 0.6 * smoothstep(1.1, 1.6, q)
	return k * (0.15 + 1.7 * clump)

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
		lo = minf(lo, shape(x + o.x, z + o.y).x)
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
