class_name RiverMesh
## Builds river water meshes from a chunk's river grid. No scene or game state, so it
## runs on worker threads and in tests.

## River water surface for this chunk (worker thread): the cells of the 2 m river grid
## that hold water, at the river's level, coloured with the downhill flow direction, its
## steepness and an edge fade. Empty when the chunk has no river.
static func build_river_arrays(chunk: Dictionary) -> Array:
	if not chunk.has("river"):
		return []
	var rv: PackedFloat32Array = chunk["river"]
	var N := ChunkGenerator.RIVER_N
	var wet := func(i: int, j: int) -> bool:
		var k := (j * N + i) * 3
		return rv[k + 1] < 1.15 and rv[k + 2] > 0.25 and rv[k] > ChunkGenerator.WATER_LEVEL + 0.2
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var vid := {}
	for j in N - 1:
		for i in N - 1:
			if not (wet.call(i, j) or wet.call(i + 1, j) or wet.call(i, j + 1) or wet.call(i + 1, j + 1)):
				continue
			# Not down the face of a waterfall (Waterfalls): its own sheet pours there.
			if chunk.has("falls"):
				var l00 := rv[(j * N + i) * 3]
				var l11 := rv[((j + 1) * N + i + 1) * 3]
				var l10 := rv[(j * N + i + 1) * 3]
				var l01 := rv[((j + 1) * N + i) * 3]
				if maxf(maxf(l00, l11), maxf(l10, l01)) - minf(minf(l00, l11), minf(l10, l01)) > 1.2:
					continue
			var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]
			var ids := []
			for c in corners:
				if not vid.has(c):
					var k: int = (c.y * N + c.x) * 3
					var lv := rv[k]
					# Downhill along the river's level.
					var ax := mini(c.x + 1, N - 1)
					var bx := maxi(c.x - 1, 0)
					var az := mini(c.y + 1, N - 1)
					var bz := maxi(c.y - 1, 0)
					var g := Vector2(rv[(c.y * N + ax) * 3] - rv[(c.y * N + bx) * 3], rv[(az * N + c.x) * 3] - rv[(bz * N + c.x) * 3])
					var f := -g.normalized() * clampf(g.length() * 6.0, 0.15, 1.0) if g.length() > 0.0001 else Vector2(0.0, 0.15)
					# How steeply the water itself falls, from wet neighbours only: the grid's
					# level climbs the banks, which is no rapid.
					var fall := Vector2(_fall(rv, N, c.x, c.y, Vector2i(1, 0), wet), _fall(rv, N, c.x, c.y, Vector2i(0, 1), wet))
					var a := (1.0 - smoothstep(0.85, 1.15, rv[k + 1])) * clampf(rv[k + 2] * 1.5, 0.0, 1.0)
					vid[c] = verts.size()
					verts.append(Vector3(c.x * 2.0, lv, c.y * 2.0))
					# b: how steeply the river falls here, per 4 m (rapids where it is high).
					cols.append(Color(f.x * 0.5 + 0.5, f.y * 0.5 + 0.5, clampf(fall.length() * 4.0, 0.0, 1.0), a))
				ids.append(vid[c])
			idx.append_array([ids[0], ids[1], ids[2], ids[1], ids[3], ids[2]])
	if idx.is_empty():
		return []
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

## The fall of the river's level per 2 m cell at (i, j) along axis d, from the wet cells
## either side (0 where neither side holds water).
static func _fall(rv: PackedFloat32Array, n: int, i: int, j: int, d: Vector2i, wet: Callable) -> float:
	var ai := mini(i + d.x, n - 1)
	var aj := mini(j + d.y, n - 1)
	var bi := maxi(i - d.x, 0)
	var bj := maxi(j - d.y, 0)
	var a_wet: bool = wet.call(ai, aj)
	var b_wet: bool = wet.call(bi, bj)
	var here := rv[(j * n + i) * 3]
	if a_wet and b_wet:
		return (rv[(aj * n + ai) * 3] - rv[(bj * n + bi) * 3]) * 0.5
	if a_wet:
		return rv[(aj * n + ai) * 3] - here
	if b_wet:
		return here - rv[(bj * n + bi) * 3]
	return 0.0
