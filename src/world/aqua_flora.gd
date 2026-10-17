class_name AquaFlora
## What grows in and on the water of a chunk: lily pads and reeds on lakes and their
## shores, kelp forests and coral reefs in the open sea, starfish and urchins on its bed.
## Like the grass, a pure function of the world seed and the chunk, built on the streaming
## thread and never saved, so every world (old ones too) has it.
##
## Lakes and the sea are told apart by the continental swell of the land (the same noise
## WorldField raises the land with): where the whole region lies below the sea it is open
## sea, anywhere else standing water is a lake or pond.

const SIZE := ChunkGenerator.SIZE
const WATER := 0.0 ## Water.LEVEL (not referenced: Water needs the running game)

## The two noises the water's life is laid out by (each caller keeps its own: noise
## objects are cheap, and nothing is shared between streaming threads).
class Field:
	var cont := FastNoiseLite.new()
	var patches := FastNoiseLite.new()

	func _init(seed: int) -> void:
		seed &= WHash.MASK
		cont.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		cont.seed = WHash.hash2(seed, 1, 0, 1) & 0x7FFFFFFF
		cont.frequency = 0.0014
		cont.fractal_type = FastNoiseLite.FRACTAL_FBM
		cont.fractal_octaves = 4
		patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patches.seed = WHash.hash2(seed, 61, 0, 1) & 0x7FFFFFFF
		patches.frequency = 0.006
		patches.fractal_octaves = 2

	## 0 for a lake or pond, 1 out in the open sea, in between along a coast.
	func sea_t(x: float, z: float) -> float:
		var c := cont.get_noise_2d(x, z) * 38.0 + 12.0
		return smoothstep(-2.0, -10.0, c)

	## A broad patch pattern (-1..1): where reefs grow, where kelp, which lilies flower.
	func patch(x: float, z: float) -> float:
		return patches.get_noise_2d(x, z)

## Instance buffers (as build_grass_buffers: 12 floats of transform, then tint rgb and
## sway) added into `out`, keyed "<species>@0".
static func build(chunk: Dictionary, density: float, out: Dictionary) -> void:
	if density <= 0.0 or not chunk.has("heights"):
		return
	var lowest := INF
	for h in (chunk["heights"] as PackedFloat32Array):
		lowest = minf(lowest, h)
	# Dry land (a hollow must reach below the shore line for reeds to stand in it).
	if lowest > 0.2:
		return
	var seed := int(chunk.get("seed", 0))
	var f := Field.new(seed)
	var x0 := float(chunk["cx"]) * SIZE
	var z0 := float(chunk["cz"]) * SIZE
	var alien := Eras.theme == "alien"
	var plans := ChunkGenerator.keep_out(chunk)
	var has_cave := chunk.has("hole")
	var sea_mid := f.sea_t(x0 + SIZE * 0.5, z0 + SIZE * 0.5)
	var colony := FastNoiseLite.new()
	colony.seed = (seed ^ 0x11A9) & 0x7FFFFFFF
	colony.frequency = 0.05
	colony.fractal_octaves = 2
	var r := WHash.rng(seed, chunk["cx"], chunk["cz"], 931)
	var spot := func(lx: float, lz: float, slope: float, margin: float) -> bool:
		if ChunkGenerator.slope_at(chunk, lx, lz) > slope or ChunkGenerator.under_river(chunk, lx, lz):
			return false
		if ChunkGenerator.kept_out(plans, lx, lz, margin):
			return false
		return not (has_cave and ChunkGenerator.in_cave(chunk, lx, lz))
	# --- Lakes: lily pads on still shallows, reeds along the shore ---
	if sea_mid < 0.7:
		for n in int(520 * density):
			var lx := r.randf() * SIZE
			var lz := r.randf() * SIZE
			var roll := r.randf()
			var yaw := r.randf() * TAU
			var size := r.randf()
			var y := ChunkGenerator.height_at(chunk, lx, lz)
			if y > -0.25 or y < -2.4:
				continue
			var wx := x0 + lx
			var wz := z0 + lz
			if f.sea_t(wx, wz) > 0.35:
				continue
			if roll > smoothstep(0.1, 0.45, colony.get_noise_2d(wx, wz)) * smoothstep(-2.4, -1.6, y) * 1.6:
				continue
			if not spot.call(lx, lz, 0.3, 0.5):
				continue
			# Whole stretches of a lake share their lilies: white, pink, or none in flower.
			var kind := clampi(int(WHash.unit2(seed, floori(wx / 150.0), floori(wz / 150.0), 77) * 3.0), 0, 2)
			var sc := lerpf(0.8, 1.7, size)
			var tint := Color(0.2, 0.34, 0.1).lerp(Color(0.3, 0.42, 0.14), r.randf())
			if r.randf() < 0.15:
				tint = Color(0.38, 0.28, 0.14) # young pads come up bronze
			_put(out, "aq_pad_%d" % kind, Basis(Vector3.UP, yaw).scaled(Vector3(sc, 1.0, sc)), lx, WATER + 0.012, lz, tint, AquaKit.STILL)
		for n in int(800 * density):
			var lx := r.randf() * SIZE
			var lz := r.randf() * SIZE
			var roll := r.randf()
			var yaw := r.randf() * TAU
			var size := r.randf()
			var y := ChunkGenerator.height_at(chunk, lx, lz)
			if y > 0.25 or y < -0.6:
				continue
			var wx := x0 + lx
			var wz := z0 + lz
			if f.sea_t(wx, wz) > 0.6:
				continue
			if roll > smoothstep(-0.15, 0.3, colony.get_noise_2d(wx * 0.8 + 90.0, wz * 0.8)) * 1.3:
				continue
			if not spot.call(lx, lz, 0.45, 0.4):
				continue
			var sc := lerpf(0.75, 1.35, size)
			var tint := Color(0.34, 0.45, 0.17).lerp(Color(0.47, 0.48, 0.22), r.randf())
			_put(out, "aq_reed", Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.85, 1.15), sc)), lx, y, lz, tint, AquaKit.SWAY_WIND)
	# --- The sea: coral reefs in its shallows, kelp forests deeper, life on the bed ---
	if sea_mid > 0.25:
		_sea(chunk, r, density, out, spot, x0, z0, f, alien)

const REEF := [["aq_coral_branch", 3.0, 0.6, 1.6], ["aq_coral_brain", 2.0, 0.4, 1.5], ["aq_coral_table", 1.4, 0.6, 1.8],
	["aq_coral_fan", 1.3, 0.5, 1.3], ["aq_sponge", 1.2, 0.6, 1.4], ["aq_anemone", 1.0, 0.6, 1.3]]
## Natural reef colours (sRGB): staghorn tans and lilac tips, brain coral ochres, sea
## fans purple, red and gold, sponges orange and violet...
const REEF_TINTS := {
	"aq_coral_branch": [Color(0.72, 0.62, 0.45), Color(0.63, 0.56, 0.5), Color(0.56, 0.6, 0.68), Color(0.74, 0.56, 0.55)],
	"aq_coral_brain": [Color(0.62, 0.55, 0.32), Color(0.5, 0.52, 0.3), Color(0.7, 0.58, 0.4), Color(0.58, 0.48, 0.38)],
	"aq_coral_table": [Color(0.5, 0.45, 0.3), Color(0.45, 0.5, 0.36), Color(0.6, 0.5, 0.45)],
	"aq_coral_fan": [Color(0.5, 0.28, 0.48), Color(0.72, 0.32, 0.2), Color(0.78, 0.64, 0.26)],
	"aq_sponge": [Color(0.8, 0.45, 0.18), Color(0.48, 0.3, 0.5), Color(0.76, 0.66, 0.3), Color(0.52, 0.38, 0.25)],
	"aq_anemone": [Color(0.76, 0.5, 0.55), Color(0.55, 0.68, 0.45), Color(0.8, 0.65, 0.45)],
	"aq_star": [Color(0.85, 0.42, 0.15), Color(0.7, 0.2, 0.18), Color(0.52, 0.3, 0.55), Color(0.82, 0.6, 0.3)],
	"aq_urchin": [Color(0.17, 0.11, 0.17), Color(0.25, 0.12, 0.12), Color(0.2, 0.18, 0.12)],
}

static func _sea(chunk: Dictionary, r: RandomNumberGenerator, density: float, out: Dictionary, spot: Callable,
		x0: float, z0: float, f: Field, alien: bool) -> void:
	var total := 0.0
	for e in REEF:
		total += float(e[1])
	for n in int(900 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var roll := r.randf()
		var pick := r.randf() * total
		var yaw := r.randf() * TAU
		var size := r.randf()
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y > -0.6 or y < -16.0:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		var reef := smoothstep(-0.2, 0.15, f.patch(wx, wz)) * smoothstep(0.55, 0.85, f.sea_t(wx, wz))
		var depth := smoothstep(-0.6, -2.0, y) * (1.0 - smoothstep(-10.0, -16.0, y))
		# Reefs grow in clumps (bommies) with sand between them.
		var clump := smoothstep(-0.5, 0.3, sin(wx * 0.21 + sin(wz * 0.13) * 2.0) * cos(wz * 0.17 + sin(wx * 0.11) * 2.0))
		if roll > reef * depth * (0.35 + 0.65 * clump):
			continue
		if not spot.call(lx, lz, 0.7, 0.3):
			continue
		var e: Array = REEF[0]
		for c in REEF:
			pick -= float(c[1])
			if pick <= 0.0:
				e = c
				break
		var sp: String = e[0]
		var sc := lerpf(float(e[2]), float(e[3]), size * size)
		if sp == "aq_coral_brain" and r.randf() < 0.1:
			sc *= 1.8 # now and then a great old dome
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.85, 1.15), sc))
		_put(out, sp, b, lx, y - 0.03 * sc, lz, _reef_tint(sp, r, alien), AquaKit.sway_of(sp), _glow(sp, alien))
	# Kelp where there is no reef and the water is deep enough to stand in.
	for n in int(380 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var size := r.randf()
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y > -3.5 or y < -24.0:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		var kelp := (1.0 - smoothstep(-0.1, 0.2, f.patch(wx, wz))) * smoothstep(0.5, 0.8, f.sea_t(wx, wz))
		# Kelp grows in stands: thick where it grows at all.
		var stand := smoothstep(-0.3, 0.4, sin(wx * 0.09 + sin(wz * 0.07) * 2.0) * cos(wz * 0.08 + sin(wx * 0.05) * 2.0))
		if roll > kelp * smoothstep(-3.5, -6.0, y) * (0.25 + 0.75 * stand):
			continue
		if not spot.call(lx, lz, 0.6, 0.3):
			continue
		var depth := -y
		var sc := lerpf(0.8, 1.4, size)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, depth * r.randf_range(0.7, 0.95), sc))
		var tint := Color(0.55, 0.45, 0.18).lerp(Color(0.44, 0.4, 0.16), r.randf())
		if alien:
			tint = Color(0.3, 0.16, 0.42).lerp(Color(0.12, 0.4, 0.38), r.randf())
		_put(out, "aq_kelp", b, lx, y - 0.05, lz, tint, AquaKit.SWAY_CURRENT, 0.4 if alien else 0.0)
	# Starfish and urchins dotted over the bed, reef or sand.
	for n in int(140 * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var roll := r.randf()
		var yaw := r.randf() * TAU
		var size := r.randf()
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if y > -0.4 or y < -14.0 or roll > 0.35 * smoothstep(0.3, 0.6, f.sea_t(x0 + lx, z0 + lz)):
			continue
		if not spot.call(lx, lz, 0.6, 0.2):
			continue
		var sp := "aq_star" if r.randf() < 0.55 else "aq_urchin"
		# (The meshes are a metre across: a starfish is a hand or two wide.)
		var sc := lerpf(0.14, 0.28, size) if sp == "aq_star" else lerpf(0.25, 0.45, size)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
		_put(out, sp, b, lx, y - 0.01, lz, _reef_tint(sp, r, alien), AquaKit.STILL, _glow(sp, alien))

static func _reef_tint(sp: String, r: RandomNumberGenerator, alien: bool) -> Color:
	var opts: Array = REEF_TINTS[sp]
	var c: Color = opts[r.randi() % opts.size()]
	# Each one a little different from its neighbours.
	c = Color(c.r * r.randf_range(0.88, 1.1), c.g * r.randf_range(0.88, 1.1), c.b * r.randf_range(0.88, 1.1))
	if alien:
		# Stranger seas: the same forms in colours no earthly reef has.
		c = Color.from_hsv(fposmod(c.h + 0.45 + r.randf_range(-0.1, 0.1), 1.0), minf(c.s * 1.5 + 0.2, 1.0), c.v)
	return c

## Only alien reefs glow (fans, anemones and sponges most).
static func _glow(sp: String, alien: bool) -> float:
	if not alien:
		return 0.0
	return 0.6 if sp in ["aq_coral_fan", "aq_anemone", "aq_sponge"] else 0.15

static func _put(out: Dictionary, sp: String, b: Basis, lx: float, y: float, lz: float, tint: Color, sway: int, glow := 0.0) -> void:
	var key := sp + "@0"
	var buf: PackedFloat32Array = out.get(key, PackedFloat32Array())
	buf.append_array([b.x.x, b.y.x, b.z.x, lx, b.x.y, b.y.y, b.z.y, y, b.x.z, b.y.z, b.z.z, lz,
		tint.r, tint.g, tint.b, float(sway) + clampf(glow, 0.0, 0.95)])
	out[key] = buf
