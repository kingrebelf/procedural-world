class_name ChunkGenerator
extends RefCounted
## Turns (seed, cx, cz) into a complete chunk snapshot. Pure and deterministic: no
## globals, no clock (except the `created` stamp). Safe to run on worker threads as long
## as each thread uses its own generator instance.

const GEN_VERSION := 1
const FORMAT := 1
const SIZE := 64
const RES := SIZE + 1
const SETTLEMENT_CELL := 256.0
const SETTLEMENT_CHANCE := 0.35
const FLAT_INNER := 30.0
const FLAT_OUTER := 54.0

var field: WorldField
var seed: int

func _init(world_seed: int) -> void:
	seed = world_seed & WHash.MASK
	field = WorldField.new(seed)

# --- Settlements -------------------------------------------------------------

## Returns { center: Vector2, era: int, target_h: float, sx, sz } or {} if no settlement.
func settlement_at(sx: int, sz: int) -> Dictionary:
	if WHash.unit2(seed, sx, sz, 201) >= SETTLEMENT_CHANCE:
		return {}
	var c := Vector2((sx + 0.3 + 0.4 * WHash.unit2(seed, sx, sz, 202)) * SETTLEMENT_CELL,
		(sz + 0.3 + 0.4 * WHash.unit2(seed, sx, sz, 203)) * SETTLEMENT_CELL)
	var w := field.era_weights(c.x, c.y)
	var era := WorldField.dominant(w)
	if w[era] < 0.92:
		return {}
	return {"center": c, "era": era, "target_h": field.height(c.x, c.y, w), "sx": sx, "sz": sz}

func settlements_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out: Array = []
	var m := FLAT_OUTER + 4.0
	for sz in range(int(floor((z0 - m) / SETTLEMENT_CELL)), int(floor((z1 + m) / SETTLEMENT_CELL)) + 1):
		for sx in range(int(floor((x0 - m) / SETTLEMENT_CELL)), int(floor((x1 + m) / SETTLEMENT_CELL)) + 1):
			var s := settlement_at(sx, sz)
			if s.is_empty():
				continue
			var c: Vector2 = s["center"]
			if c.x + m >= x0 and c.x - m <= x1 and c.y + m >= z0 and c.y - m <= z1:
				out.append(s)
	return out

## Final terrain height including settlement flattening.
func sample_height(x: float, z: float, w: PackedFloat32Array, sites: Array) -> float:
	var h := field.height(x, z, w)
	for s in sites:
		var d := Vector2(x, z).distance_to(s["center"])
		if d < FLAT_OUTER:
			h = lerpf(h, s["target_h"], 1.0 - smoothstep(FLAT_INNER, FLAT_OUTER, d))
	return h

# --- Chunk -------------------------------------------------------------------

func generate(cx: int, cz: int) -> Dictionary:
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var sites := settlements_near(x0, z0, x0 + SIZE, z0 + SIZE)
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	var weights := PackedByteArray()
	weights.resize(RES * RES * Eras.COUNT)
	# Era weights vary over tens of metres, so sample them every 4 m and interpolate.
	var coarse: Array = []
	const STEP := 4
	const CN := SIZE / STEP + 1
	for j in CN:
		for i in CN:
			coarse.append(field.era_weights(x0 + i * STEP, z0 + j * STEP))
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
	for j in RES:
		for i in RES:
			var x := x0 + i
			var z := z0 + j
			var gi := mini(i / STEP, CN - 2)
			var gj := mini(j / STEP, CN - 2)
			var fx := (i - gi * STEP) / float(STEP)
			var fz := (j - gj * STEP) / float(STEP)
			var w00: PackedFloat32Array = coarse[gj * CN + gi]
			var w10: PackedFloat32Array = coarse[gj * CN + gi + 1]
			var w01: PackedFloat32Array = coarse[(gj + 1) * CN + gi]
			var w11: PackedFloat32Array = coarse[(gj + 1) * CN + gi + 1]
			for e in Eras.COUNT:
				w[e] = lerpf(lerpf(w00[e], w10[e], fx), lerpf(w01[e], w11[e], fx), fz)
			var k := j * RES + i
			heights[k] = sample_height(x, z, w, sites)
			for e in Eras.COUNT:
				weights[k * Eras.COUNT + e] = int(round(w[e] * 255.0))
	var center_w := field.era_weights(x0 + SIZE * 0.5, z0 + SIZE * 0.5)
	var chunk := {
		"format": FORMAT, "gen_version": GEN_VERSION, "seed": seed,
		"cx": cx, "cz": cz,
		"heights": heights, "weights": weights,
		"era": WorldField.dominant(center_w),
		"region": field.region_name_at(x0 + SIZE * 0.5, z0 + SIZE * 0.5),
		"objects": [],
	}
	_place_objects(chunk, sites)
	return chunk

static func height_at(chunk: Dictionary, lx: float, lz: float) -> float:
	var hs: PackedFloat32Array = chunk["heights"]
	lx = clampf(lx, 0.0, SIZE - 0.001)
	lz = clampf(lz, 0.0, SIZE - 0.001)
	var i := int(lx)
	var j := int(lz)
	var fx := lx - i
	var fz := lz - j
	var h00 := hs[j * RES + i]
	var h10 := hs[j * RES + i + 1]
	var h01 := hs[(j + 1) * RES + i]
	var h11 := hs[(j + 1) * RES + i + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

static func slope_at(chunk: Dictionary, lx: float, lz: float) -> float:
	var dx := height_at(chunk, lx + 1.0, lz) - height_at(chunk, lx - 1.0, lz)
	var dz := height_at(chunk, lx, lz + 1.0) - height_at(chunk, lx, lz - 1.0)
	return Vector2(dx, dz).length() * 0.5

static func weights_at(chunk: Dictionary, lx: float, lz: float) -> PackedFloat32Array:
	var i := clampi(int(round(lx)), 0, RES - 1)
	var j := clampi(int(round(lz)), 0, RES - 1)
	var k := (j * RES + i) * Eras.COUNT
	var wb: PackedByteArray = chunk["weights"]
	var w := PackedFloat32Array()
	w.resize(Eras.COUNT)
	for e in Eras.COUNT:
		w[e] = wb[k + e] / 255.0
	return w

func _pick_era(w: PackedFloat32Array, r: float) -> int:
	var acc := 0.0
	for e in Eras.COUNT:
		acc += w[e]
		if r <= acc:
			return e
	return Eras.COUNT - 1

func _add(chunk: Dictionary, type: String, era: int, lx: float, lz: float, yaw: float, scale: float, st: Dictionary = {}) -> void:
	var objs: Array = chunk["objects"]
	objs.append({
		"i": objs.size(), "t": type, "e": era,
		"p": Vector3(lx, height_at(chunk, lx, lz), lz),
		"r": yaw, "s": scale, "st": st,
	})

func _near_settlement(x: float, z: float, sites: Array, radius: float) -> bool:
	for s in sites:
		if Vector2(x, z).distance_to(s["center"]) < radius:
			return true
	return false

func _place_objects(chunk: Dictionary, sites: Array) -> void:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var x0 := float(cx * SIZE)
	var z0 := float(cz * SIZE)
	var origin := {"chunk": Vector2i(cx, cz)}

	# Settlements first so they claim their space.
	for s in sites:
		_place_settlement(chunk, s, x0, z0)

	# Vegetation: jittered candidates, era picked by sampling local weights so
	# transition bands get a natural, dithered mix of both sides.
	var r := WHash.rng(seed, cx, cz, 301)
	var candidates := 48
	for n in candidates:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var era := _pick_era(w, r.randf())
		var forest := clampf((field._moss.get_noise_2d((x0 + lx) * 0.15, (z0 + lz) * 0.15) + 0.35) * 1.5, 0.0, 1.0)
		var p: float = Eras.TREE_DENSITY[era] / candidates * (0.25 + forest * 1.6)
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.75, 1.35)
		var hp := r.randi_range(3, 5)
		var yield_ := r.randi_range(3, 6)
		if roll >= p or slope_at(chunk, lx, lz) > 0.75 or _near_settlement(x0 + lx, z0 + lz, sites, FLAT_INNER + 6.0):
			continue
		var types: Array = Eras.TREE_TYPES[era]
		_add(chunk, types[int(roll / p * types.size()) % types.size()], era, lx, lz, yaw, sc, {"hp": hp, "yield": yield_})

	# Rocks and ore.
	r = WHash.rng(seed, cx, cz, 302)
	for n in 16:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var era := _pick_era(w, r.randf())
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.6, 1.8)
		var left := r.randi_range(3, 7)
		if _near_settlement(x0 + lx, z0 + lz, sites, FLAT_INNER):
			continue
		if roll < Eras.ROCK_DENSITY[era] / 16.0:
			_add(chunk, "rock", era, lx, lz, yaw, sc, {"left": left, "progress": 0.0})
		elif roll < (Eras.ROCK_DENSITY[era] + Eras.ORE_DENSITY[era]) / 16.0:
			_add(chunk, Eras.ORE_TYPES[era], era, lx, lz, yaw, sc * 0.8, {"left": left + 2, "progress": 0.0})

	# Caches: rare, contents rolled now and frozen forever.
	r = WHash.rng(seed, cx, cz, 303)
	if r.randf() < 0.22:
		var lx := r.randf_range(4, SIZE - 4)
		var lz := r.randf_range(4, SIZE - 4)
		var era := WorldField.dominant(weights_at(chunk, lx, lz))
		var o := origin.duplicate()
		o["era"] = era
		o["how"] = "found"
		var loot := ItemDB.roll_loot(era, r, o)
		_add(chunk, Eras.CACHE_TYPES[era], era, lx, lz, r.randf() * TAU, 1.0, {"loot": loot, "opened": false})

	# Threshold markers inside transition bands make crossings read as intentional.
	r = WHash.rng(seed, cx, cz, 304)
	for n in 10:
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var w := weights_at(chunk, lx, lz)
		var top := w[WorldField.dominant(w)]
		var era := _pick_era(w, r.randf())
		var yaw := r.randf() * TAU
		var sc := r.randf_range(0.8, 1.4)
		if top < 0.72 and r.randf() < 0.55 and slope_at(chunk, lx, lz) < 0.5:
			_add(chunk, Eras.MARKER_TYPES[era], era, lx, lz, yaw, sc)

func _place_settlement(chunk: Dictionary, s: Dictionary, x0: float, z0: float) -> void:
	var c: Vector2 = s["center"]
	var era: int = s["era"]
	var r := WHash.rng(seed, s["sx"], s["sz"], 401)
	var items: Array = []
	items.append({"t": "trader", "p": c + Vector2(r.randf_range(-3, 3), r.randf_range(-3, 3)), "yaw": r.randf() * TAU,
		"st": Economy.new_trader(era, r)})
	var kit: Array = Eras.STRUCTURE_TYPES[era]
	var count := r.randi_range(3, 7)
	var a0 := r.randf() * TAU
	for k in count:
		var ang := a0 + TAU * k / count + r.randf_range(-0.25, 0.25)
		var rad := r.randf_range(14.0, 26.0)
		var p := c + Vector2(cos(ang), sin(ang)) * rad
		var t: String = kit[r.randi() % kit.size()]
		# Face the square.
		items.append({"t": t, "p": p, "yaw": atan2(c.x - p.x, c.y - p.y), "st": {}})
	if r.randf() < 0.6:
		var o := {"chunk": Vector2i(int(chunk["cx"]), int(chunk["cz"])), "era": era, "how": "found"}
		items.append({"t": Eras.CACHE_TYPES[era], "p": c + Vector2(r.randf_range(-9, 9), r.randf_range(-9, 9)),
			"yaw": r.randf() * TAU, "st": {"loot": ItemDB.roll_loot(era, r, o), "opened": false}})
	for it in items:
		var p: Vector2 = it["p"]
		if p.x >= x0 and p.x < x0 + SIZE and p.y >= z0 and p.y < z0 + SIZE:
			_add(chunk, it["t"], era, p.x - x0, p.y - z0, it["yaw"], 1.0, it["st"])
