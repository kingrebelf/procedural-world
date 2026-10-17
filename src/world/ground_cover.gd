class_name GroundCover
## What covers the ground at each metre of a chunk, besides grass: scree and stony ground
## (at the feet of cliffs and in rocky patches), gravel (river banks, shores, dry beds),
## leaf litter and needles (under trees) and snow. One RGBA byte per terrain vertex:
##   r scree, g gravel, b litter, a snow.
## The terrain shader paints the matching ground textures from it, and the grass and
## stone scatter read it, so stones lie where the ground turns stony and no grass pokes
## through thick snow. It is worked out from the chunk's heights and objects every time
## the chunk is built (never stored), so it applies to every world, old and new.

const SIZE := ChunkGenerator.SIZE
const RES := ChunkGenerator.RES
const CLIFF := 6 ## metres scree spreads out from the foot of a steep face

## The cover grid of a chunk: RES * RES * 4 bytes (see above).
static func build(chunk: Dictionary) -> PackedByteArray:
	var hs: PackedFloat32Array = chunk["heights"]
	var cx := int(chunk["cx"])
	var cz := int(chunk["cz"])
	var seed := int(chunk.get("seed", 0))
	var big := FastNoiseLite.new()
	big.seed = seed ^ 0x5C3EE
	big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	big.frequency = 0.018
	big.fractal_type = FastNoiseLite.FRACTAL_FBM
	big.fractal_octaves = 3
	var small := FastNoiseLite.new()
	small.seed = seed ^ 0x9A11
	small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	small.frequency = 0.16
	small.fractal_octaves = 2
	var x0 := cx * SIZE
	var z0 := cz * SIZE
	var n := RES * RES
	# Steepness per vertex (1 on a cliff face), from the height gradient.
	var steep := PackedFloat32Array()
	steep.resize(n)
	var grad := PackedFloat32Array()
	grad.resize(n)
	for j in RES:
		for i in RES:
			var k := j * RES + i
			var dx := (hs[j * RES + mini(i + 1, RES - 1)] - hs[j * RES + maxi(i - 1, 0)]) / float(mini(i + 1, RES - 1) - maxi(i - 1, 0))
			var dz := (hs[mini(j + 1, RES - 1) * RES + i] - hs[maxi(j - 1, 0) * RES + i]) / float(mini(j + 1, RES - 1) - maxi(j - 1, 0))
			grad[k] = Vector2(dx, dz).length()
			steep[k] = smoothstep(0.7, 1.25, grad[k])
	# Spread it out over the ground around (a falloff max filter, rows then columns):
	# that is where rock falling from the face comes to rest.
	var row := PackedFloat32Array()
	row.resize(n)
	for j in RES:
		for i in RES:
			var m := 0.0
			for d in range(-CLIFF, CLIFF + 1):
				var ii := i + d
				if ii >= 0 and ii < RES:
					m = maxf(m, steep[j * RES + ii] * (1.0 - absf(d) / float(CLIFF + 1)))
			row[j * RES + i] = m
	var foot := PackedFloat32Array()
	foot.resize(n)
	for j in RES:
		for i in RES:
			var m := 0.0
			for d in range(-CLIFF, CLIFF + 1):
				var jj := j + d
				if jj >= 0 and jj < RES:
					m = maxf(m, row[jj * RES + i] * (1.0 - absf(d) / float(CLIFF + 1)))
			foot[j * RES + i] = m
	# Leaf litter and needles under the crowns of trees.
	var litter := PackedFloat32Array()
	litter.resize(n)
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) != "tree" or o["st"].get("gone", false):
			continue
		var p: Vector3 = o["p"]
		var r := 2.5 + 1.6 * float(o["s"])
		var ri := int(ceil(r))
		for j in range(maxi(int(p.z) - ri, 0), mini(int(p.z) + ri + 1, RES)):
			for i in range(maxi(int(p.x) - ri, 0), mini(int(p.x) + ri + 1, RES)):
				var d := Vector2(i - p.x, j - p.z).length() / r
				if d < 1.0:
					var k := j * RES + i
					litter[k] = minf(litter[k] + (1.0 - d * d) * 0.8, 1.0)
	# Settled ground: around buildings and on roads people have cleared the stones.
	var settled := PackedFloat32Array()
	settled.resize(n)
	for q: PackedFloat32Array in ChunkGenerator.keep_out(chunk):
		var reach := q[8] + 24.0
		var ri := int(ceil(reach))
		for j in range(maxi(int(q[1]) - ri, 0), mini(int(q[1]) + ri + 1, RES)):
			for i in range(maxi(int(q[0]) - ri, 0), mini(int(q[0]) + ri + 1, RES)):
				var d := Vector2(i - q[0], j - q[1]).length() - q[8]
				var k := j * RES + i
				settled[k] = maxf(settled[k], 1.0 - smoothstep(8.0, 24.0, d))
	var road: PackedByteArray = chunk.get("road", PackedByteArray())
	if road.size() == n:
		for k in n:
			settled[k] = maxf(settled[k], minf(road[k] / 255.0 * 2.0, 1.0))
	# (v16) Old craters on human worlds are grassed over: bare and stony only along their
	# crumbling inner lip (look byte 11), and there in clumps.
	var grassed: PackedByteArray = chunk.get("grassed", PackedByteArray())
	var lb: PackedByteArray = chunk.get("look", PackedByteArray())
	var rv: PackedFloat32Array = chunk.get("river", PackedFloat32Array())
	var rn := ChunkGenerator.RIVER_N
	var snow_line := Planets.snow_line
	var lows := _lows(hs)
	var out := PackedByteArray()
	out.resize(n * 4)
	var sn := PackedFloat32Array()
	sn.resize(n)
	for j in RES:
		for i in RES:
			var k := j * RES + i
			var wx := float(x0 + i)
			var wz := float(z0 + j)
			var h := hs[k]
			var nb := big.get_noise_2d(wx, wz)
			var ns := small.get_noise_2d(wx, wz)
			var flat := 1.0 - steep[k]
			# Loose dune sand buries stones and gravel.
			var bare := 1.0 - ChunkGenerator.sand_at(chunk, i, j)
			# Scree below cliffs, broken into tongues and gaps; rocky patches in the open,
			# on rising and high ground rather than flat meadow, and never in a village or
			# on a road.
			var scree := clampf(foot[k] * 1.4 * (0.55 + 0.6 * (ns * 0.5 + 0.5)), 0.0, 1.0)
			var rise := clampf(smoothstep(0.12, 0.45, grad[k]) + clampf((h - 18.0) * 0.01, 0.0, 0.5), 0.0, 1.0)
			var patch := smoothstep(0.4, 0.55, nb + clampf((h - 18.0) * 0.006, 0.0, 0.12) + ns * 0.08) * lerpf(0.25, 1.0, rise)
			scree = maxf(scree * (1.0 - 0.85 * settled[k]), patch * (1.0 - settled[k])) * flat
			# Steep banks short of a cliff: the turf slips and tears in places, showing
			# stony soil in torn patches, more of them toward the foot of a rock
			# cut (a bank green right up to the face read as a carpet laid over it).
			var bank := smoothstep(0.42, 0.9, grad[k]) * smoothstep(0.05, 0.4, ns * 0.65 + nb * 0.45 + 0.1 + 0.35 * foot[k])
			scree = maxf(scree, bank * (1.0 - settled[k]) * (0.45 + 0.55 * flat))
			if not grassed.is_empty() and not lb.is_empty():
				var gw := _look_cell(grassed, i, j, 1, 0)
				if gw > 0.0:
					var lip := clampf(_look_cell(lb, i, j, ChunkGenerator.LOOK_BYTES, 11) * 1.8, 0.0, 1.0)
					var clump := smoothstep(-0.1, 0.45, nb + ns * 0.35)
					scree *= lerpf(1.0, lip * clump, gw)
			# Gravel on river banks and lake shores, in patches; the odd dry gravel bed.
			var gravel := 0.0
			if not rv.is_empty():
				var rk := (clampi(int(round(j * 0.5)), 0, rn - 1) * rn + clampi(int(round(i * 0.5)), 0, rn - 1)) * 3
				if rv[rk + 2] > 0.2:
					# Gravel bars here and there along the bank, of varying width, with grass,
					# mud and reeds coming down to the water between them (an even grey strip
					# both sides read as a concrete channel).
					var reach := 1.1 + 1.2 * (nb * 0.5 + 0.5) + 0.3 * ns
					gravel = (1.0 - smoothstep(1.05, reach, rv[rk + 1])) * rv[rk + 2] * smoothstep(-0.05, 0.35, nb * 0.8 + ns * 0.6)
			var shore := 1.0 - smoothstep(0.5, 1.6, h - ChunkGenerator.WATER_LEVEL)
			gravel = maxf(gravel, shore * smoothstep(-0.15, 0.2, nb + ns * 0.3))
			gravel = maxf(gravel, smoothstep(0.5, 0.62, -nb + ns * 0.1) * 0.9 * (1.0 - settled[k]))
			gravel *= flat * bare
			scree *= bare
			# Snow lies on high ground, in drifts, and slides off steep faces. What counts
			# is how high the land around stands: a tor or crag rising out of a green
			# valley stays bare, it does not wear a cap of its own.
			var lo := _low_at(lows, i, j)
			var hs_ := minf(h, lo + 3.0 + maxf(h - lo - 3.0, 0.0) * 0.25)
			var snow := smoothstep(snow_line - 6.0, snow_line + 8.0, hs_ + nb * 9.0 + ns * 2.0) * (1.0 - smoothstep(0.55, 0.9, steep[k] * 0.5 + 0.4 * (1.0 - flat)))
			out[k * 4] = int(scree * 255.0)
			out[k * 4 + 1] = int(gravel * 255.0)
			out[k * 4 + 2] = int(litter[k] * (1.0 - scree * 0.7) * 255.0)
			sn[k] = clampf(snow, 0.0, 1.0)
	# Snow softened over the metre around (inside the chunk; its edge stays as worked out,
	# to meet the next chunk's), so one snowy point among bare ones is a soft patch, not a
	# white triangle.
	for j in RES:
		for i in RES:
			var k := j * RES + i
			var v := sn[k]
			if i > 0 and j > 0 and i < RES - 1 and j < RES - 1:
				v = v * 0.4 + (sn[k - 1] + sn[k + 1] + sn[k - RES] + sn[k + RES]) * 0.1 \
					+ (sn[k - RES - 1] + sn[k - RES + 1] + sn[k + RES - 1] + sn[k + RES + 1]) * 0.05
			out[k * 4 + 3] = int(v * 255.0)
	return out

const LOW_STEP := 16 ## metres between the points of the low-ground lattice
const LOW_REACH := 8 ## how far each looks for the lowest ground round it
const LOW_N := SIZE / LOW_STEP + 1

## The lowest ground near each point of a 16 m lattice over the chunk, so snow can follow
## the lie of the land rather than every bump. Points on the chunk's edge look only along
## the edge (heights both chunks share), so neighbours agree where they meet.
static func _lows(hs: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LOW_N * LOW_N)
	for J in LOW_N:
		for I in LOW_N:
			var ci := I * LOW_STEP
			var cj := J * LOW_STEP
			var edge_i := I == 0 or I == LOW_N - 1
			var edge_j := J == 0 or J == LOW_N - 1
			var m := INF
			for dj in range(-LOW_REACH, LOW_REACH + 1, 2):
				var jj := cj + (0 if edge_j else dj)
				if jj < 0 or jj >= RES:
					continue
				for di in range(-LOW_REACH, LOW_REACH + 1, 2):
					var ii := ci + (0 if edge_i else di)
					if ii < 0 or ii >= RES:
						continue
					m = minf(m, hs[jj * RES + ii])
			out[J * LOW_N + I] = m
	return out

static func _low_at(lows: PackedFloat32Array, i: int, j: int) -> float:
	var I := mini(i / LOW_STEP, LOW_N - 2)
	var J := mini(j / LOW_STEP, LOW_N - 2)
	var fx := (i - I * LOW_STEP) / float(LOW_STEP)
	var fz := (j - J * LOW_STEP) / float(LOW_STEP)
	return lerpf(lerpf(lows[J * LOW_N + I], lows[J * LOW_N + I + 1], fx), lerpf(lows[(J + 1) * LOW_N + I], lows[(J + 1) * LOW_N + I + 1], fx), fz)

## A per-look-cell byte (stride bytes a cell, at offset) at vertex (i, j), 0..1, blended
## between the four cells round it.
static func _look_cell(b: PackedByteArray, i: int, j: int, stride: int, at: int) -> float:
	const N := ChunkGenerator.LOOK_N
	var gx := minf(float(i) / ChunkGenerator.LOOK_STEP, N - 1.001)
	var gz := minf(float(j) / ChunkGenerator.LOOK_STEP, N - 1.001)
	var ci := int(gx)
	var cj := int(gz)
	var fx := gx - ci
	var fz := gz - cj
	var v00 := b[(cj * N + ci) * stride + at]
	var v10 := b[(cj * N + ci + 1) * stride + at]
	var v01 := b[((cj + 1) * N + ci) * stride + at]
	var v11 := b[((cj + 1) * N + ci + 1) * stride + at]
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fz) / 255.0

## The cover at a point of the chunk, interpolated: Color(scree, gravel, litter, snow).
static func at(cover: PackedByteArray, lx: float, lz: float) -> Color:
	if cover.is_empty():
		return Color(0, 0, 0, 0)
	lx = clampf(lx, 0.0, SIZE - 0.001)
	lz = clampf(lz, 0.0, SIZE - 0.001)
	var i := int(lx)
	var j := int(lz)
	var fx := lx - i
	var fz := lz - j
	var k00 := (j * RES + i) * 4
	var k10 := k00 + 4
	var k01 := k00 + RES * 4
	var k11 := k01 + 4
	var c := Color()
	for b in 4:
		c[b] = lerpf(lerpf(cover[k00 + b], cover[k10 + b], fx), lerpf(cover[k01 + b], cover[k11 + b], fx), fz) / 255.0
	return c
