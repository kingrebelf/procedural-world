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
	var rv: PackedFloat32Array = chunk.get("river", PackedFloat32Array())
	var rn := ChunkGenerator.RIVER_N
	var snow_line := Planets.snow_line
	var out := PackedByteArray()
	out.resize(n * 4)
	for j in RES:
		for i in RES:
			var k := j * RES + i
			var wx := float(x0 + i)
			var wz := float(z0 + j)
			var h := hs[k]
			var nb := big.get_noise_2d(wx, wz)
			var ns := small.get_noise_2d(wx, wz)
			var flat := 1.0 - steep[k]
			# Scree below cliffs, broken into tongues and gaps; rocky patches in the open,
			# on rising and high ground rather than flat meadow, and never in a village or
			# on a road.
			var scree := clampf(foot[k] * 1.4 * (0.55 + 0.6 * (ns * 0.5 + 0.5)), 0.0, 1.0)
			var rise := clampf(smoothstep(0.12, 0.45, grad[k]) + clampf((h - 18.0) * 0.01, 0.0, 0.5), 0.0, 1.0)
			var patch := smoothstep(0.4, 0.55, nb + clampf((h - 18.0) * 0.006, 0.0, 0.12) + ns * 0.08) * lerpf(0.25, 1.0, rise)
			scree = maxf(scree * (1.0 - 0.85 * settled[k]), patch * (1.0 - settled[k])) * flat
			# Gravel on river banks and lake shores, in patches; the odd dry gravel bed.
			var gravel := 0.0
			if not rv.is_empty():
				var rk := (clampi(int(round(j * 0.5)), 0, rn - 1) * rn + clampi(int(round(i * 0.5)), 0, rn - 1)) * 3
				if rv[rk + 2] > 0.2:
					gravel = (1.0 - smoothstep(1.2, 2.6, rv[rk + 1])) * rv[rk + 2]
			var shore := 1.0 - smoothstep(0.5, 1.6, h - ChunkGenerator.WATER_LEVEL)
			gravel = maxf(gravel, shore * smoothstep(-0.15, 0.2, nb + ns * 0.3))
			gravel = maxf(gravel, smoothstep(0.5, 0.62, -nb + ns * 0.1) * 0.9 * (1.0 - settled[k]))
			gravel *= flat
			# Snow lies on high ground, in drifts, and slides off steep faces.
			var snow := smoothstep(snow_line - 6.0, snow_line + 8.0, h + nb * 9.0 + ns * 2.0) * (1.0 - smoothstep(0.55, 0.9, steep[k] * 0.5 + 0.4 * (1.0 - flat)))
			out[k * 4] = int(scree * 255.0)
			out[k * 4 + 1] = int(gravel * 255.0)
			out[k * 4 + 2] = int(litter[k] * (1.0 - scree * 0.7) * 255.0)
			out[k * 4 + 3] = int(clampf(snow, 0.0, 1.0) * 255.0)
	return out

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
