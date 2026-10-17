class_name AquaFlora
## What grows in and on the water of a chunk: lily pads and reeds on lakes and their
## shores, kelp forests and coral reefs in the open sea, starfish and urchins on its bed.
## Like the grass, a pure function of the world seed and the chunk, built on the streaming
## thread and never saved, so every world (old ones too) has it.
##
## Lakes and the sea are told apart by how much open water lies round a place: these
## worlds have no ocean, but their widest low-lying waters (open water most of the way
## out to a few hundred metres, no mountains over them) are seas, with kelp, and reefs
## where they are warm; anywhere else standing water is a lake or pond.

const SIZE := ChunkGenerator.SIZE
const WATER := 0.0 ## Water.LEVEL (not referenced: Water needs the running game)
const WET := -1.2 ## below this the bed counts as open water (as Boats does)

## What the water's life is laid out by (each caller keeps its own: nothing is shared
## between streaming threads). How open and how warm the water is gets worked out on a
## 64 m lattice and blended between its corners, so it changes smoothly across chunks.
class Field:
	var world: WorldField
	var patches := FastNoiseLite.new()
	var _corners := {}

	func _init(seed: int) -> void:
		seed &= WHash.MASK
		world = WorldField.new(seed)
		patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patches.seed = WHash.hash2(seed, 61, 0, 1) & 0x7FFFFFFF
		patches.frequency = 0.006
		patches.fractal_octaves = 2

	## A lattice corner: x the share of open water out to 400 m round it, y the highest
	## ground within 700 m (snowy peaks make cold water).
	func _corner(i: int, j: int) -> Vector2:
		var key := Vector2i(i, j)
		if _corners.has(key):
			return _corners[key]
		var x := i * SIZE
		var z := j * SIZE
		var wet := 0
		var peak := -INF
		for rad: float in [120.0, 250.0, 400.0, 700.0]:
			for k in 8:
				var a := TAU * k / 8.0 + rad * 0.01
				var h := world.height(x + cos(a) * rad, z + sin(a) * rad)
				if rad < 500.0 and h < WET:
					wet += 1
				peak = maxf(peak, h)
		var v := Vector2(wet / 24.0, peak)
		_corners[key] = v
		return v

	func _at(x: float, z: float) -> Vector2:
		var fx := x / SIZE
		var fz := z / SIZE
		var i := floori(fx)
		var j := floori(fz)
		var tx := fx - i
		var tz := fz - j
		return _corner(i, j).lerp(_corner(i + 1, j), tx).lerp(_corner(i, j + 1).lerp(_corner(i + 1, j + 1), tx), tz)

	## 0 for a lake or pond, 1 out on the widest waters, in between as a lake opens out.
	## Water ringed by high mountains is a lake however wide (a sea lies low).
	func sea_t(x: float, z: float) -> float:
		var v := _at(x, z)
		return smoothstep(0.22, 0.38, v.x) * (1.0 - smoothstep(34.0, 46.0, v.y))

	## 1 where the water is warm enough for coral, 0 under snowy peaks.
	func warm(x: float, z: float) -> float:
		return 1.0 - smoothstep(30.0, 42.0, _at(x, z).y)

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

const REEF := [["aq_coral_branch", 3.0, 0.6, 1.6], ["aq_coral_brain", 2.0, 0.35, 1.1], ["aq_coral_table", 1.4, 0.6, 1.8],
	["aq_coral_fan", 1.3, 0.5, 1.3], ["aq_sponge", 1.2, 0.6, 1.4], ["aq_anemone", 1.0, 0.6, 1.3]]
## Natural reef colours (sRGB): staghorn tans and lilac tips, brain coral ochres, sea
## fans purple, red and gold, sponges orange and violet...
const REEF_TINTS := {
	"aq_coral_branch": [Color(0.72, 0.62, 0.45), Color(0.63, 0.56, 0.5), Color(0.56, 0.6, 0.68), Color(0.74, 0.56, 0.55)],
	"aq_coral_brain": [Color(0.62, 0.55, 0.32), Color(0.56, 0.5, 0.36), Color(0.7, 0.58, 0.4), Color(0.58, 0.48, 0.38)],
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
	var mounds := bommies(chunk, f)
	for n in int((900 + 160 * mounds.size()) * density):
		var lx := r.randf() * SIZE
		var lz := r.randf() * SIZE
		var roll := r.randf()
		var pick := r.randf() * total
		var yaw := r.randf() * TAU
		var size := r.randf()
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		# The first tries cover the bommies (the rock under them hidden in coral), the
		# rest are strewn over the reef flat between them.
		var on := -1
		if n < 160 * mounds.size():
			on = n % mounds.size()
			var m: Array = mounds[on]
			var d := sqrt(roll) * float(m[2]) * 0.95
			lx = clampf(float(m[0]) + cos(yaw * 1.7) * d, 0.0, SIZE - 0.01)
			lz = clampf(float(m[1]) + sin(yaw * 1.7) * d, 0.0, SIZE - 0.01)
			y = mound_top(m, lx, lz)
		else:
			var wx := x0 + lx
			var wz := z0 + lz
			var clump := smoothstep(-0.5, 0.3, sin(wx * 0.21 + sin(wz * 0.13) * 2.0) * cos(wz * 0.17 + sin(wx * 0.11) * 2.0))
			if roll > reef_at(f, wx, wz, y) * (0.35 + 0.65 * clump):
				continue
		if on < 0 and not spot.call(lx, lz, 0.7, 0.3):
			continue
		var e: Array = REEF[0]
		for c in REEF:
			pick -= float(c[1])
			if pick <= 0.0:
				e = c
				break
		var sp: String = e[0]
		var sc := lerpf(float(e[2]), float(e[3]), size * size)
		if sp == "aq_coral_brain" and r.randf() < 0.08:
			sc *= 1.35 # now and then a great old dome
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * r.randf_range(0.85, 1.15), sc))
		_put(out, sp, b, lx, y - (0.12 if on >= 0 else 0.03) * sc, lz, _reef_tint(sp, r, alien), AquaKit.sway_of(sp), _glow(sp, alien))
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

## How much a reef grows at a place on the bed `y` deep: warm open water, in its
## patches, from just under the surface down to where the light fades.
static func reef_at(f: Field, wx: float, wz: float, y: float) -> float:
	if y > -0.6 or y < -16.0:
		return 0.0
	var depth := smoothstep(-0.6, -2.0, y) * (1.0 - smoothstep(-10.0, -16.0, y))
	return smoothstep(-0.2, 0.15, f.patch(wx, wz)) * smoothstep(0.55, 0.85, f.sea_t(wx, wz)) * f.warm(wx, wz) * depth

## The rock bommies a chunk's reef is built on: [lx, lz, radius, height, bed y] each.
## Their rocks are laid by reef_rocks (with the other stones), the coral on top of them
## here, so both work them out the same way.
static func bommies(chunk: Dictionary, f: Field = null) -> Array:
	var out: Array = []
	if not chunk.has("heights"):
		return out
	if f == null:
		f = Field.new(int(chunk.get("seed", 0)))
	var x0 := float(chunk["cx"]) * SIZE
	var z0 := float(chunk["cz"]) * SIZE
	if f.sea_t(x0 + SIZE * 0.5, z0 + SIZE * 0.5) < 0.3:
		return out
	var plans := ChunkGenerator.keep_out(chunk)
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 933)
	for n in 14:
		var lx := r.randf_range(3.0, SIZE - 3.0)
		var lz := r.randf_range(3.0, SIZE - 3.0)
		var roll := r.randf()
		var rad := r.randf_range(1.4, 3.4)
		var h := rad * r.randf_range(0.3, 0.5)
		var y := ChunkGenerator.height_at(chunk, lx, lz)
		if roll > reef_at(f, x0 + lx, z0 + lz, y) * 1.4 or y + h > -0.9:
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.6 or ChunkGenerator.under_river(chunk, lx, lz) or ChunkGenerator.kept_out(plans, lx, lz, rad):
			continue
		var clear := true
		for m in out:
			if Vector2(lx - float(m[0]), lz - float(m[1])).length() < rad + float(m[2]) + 1.5:
				clear = false
				break
		if clear:
			out.append([lx, lz, rad, h, y])
	return out

## The top of bommie `m` at (lx, lz): a low dome over the bed.
static func mound_top(m: Array, lx: float, lz: float) -> float:
	var d := Vector2(lx - float(m[0]), lz - float(m[1])).length() / float(m[2])
	return float(m[4]) + float(m[3]) * sqrt(maxf(0.0, 1.0 - d * d))

## The bommies' rocks, as stone instances (StoneKit, shared with ChunkNode's stones):
## a big flat-topped rock with smaller ones heaped round it, crusted pink and ochre
## with coralline algae. Appended into `out` and `solid` the way ChunkNode lays stones.
static func reef_rocks(chunk: Dictionary, out: Dictionary, solid: PackedFloat32Array) -> void:
	var mounds := bommies(chunk)
	if mounds.is_empty():
		return
	var r := WHash.rng(int(chunk.get("seed", 0)), chunk["cx"], chunk["cz"], 934)
	var crusts := [Color(0.52, 0.42, 0.4), Color(0.5, 0.46, 0.38), Color(0.44, 0.42, 0.4), Color(0.56, 0.45, 0.44)]
	for m in mounds:
		var rad := float(m[2])
		var h := float(m[3])
		for k in r.randi_range(3, 5):
			var big := k == 0
			var a := r.randf() * TAU
			var d := 0.0 if big else r.randf_range(0.35, 0.75) * rad
			var lx := float(m[0]) + cos(a) * d
			var lz := float(m[1]) + sin(a) * d
			var w := (rad * 1.7 if big else rad * r.randf_range(0.6, 0.95))
			var tall := (h * 1.6 if big else mound_top(m, lx, lz) - float(m[4]) + 0.3)
			var kind := "rock_a" if r.randf() < 0.5 else "rock_b"
			var b := Basis(Vector3.UP, r.randf() * TAU) * Basis.from_euler(Vector3(r.randf_range(-0.15, 0.15), 0, r.randf_range(-0.15, 0.15)))
			b = b.scaled_local(Vector3(w, maxf(tall, 0.3), w * r.randf_range(0.75, 1.0)))
			var y := ChunkGenerator.height_at(chunk, clampf(lx, 0.0, SIZE - 0.01), clampf(lz, 0.0, SIZE - 0.01))
			var p := Vector3(lx, minf(y, float(m[4])) - 0.15 * tall, lz)
			var c: Color = crusts[r.randi() % crusts.size()]
			var v := r.randf_range(0.85, 1.1)
			var tint := Color(c.r * v, c.g * v, c.b * v, r.randf_range(0.15, 0.4))
			var buf: PackedFloat32Array = out.get("stone:" + kind, PackedFloat32Array())
			buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint.r, tint.g, tint.b, tint.a])
			out["stone:" + kind] = buf
			solid.append_array([StoneKit.KINDS.find(kind), b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z])

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
