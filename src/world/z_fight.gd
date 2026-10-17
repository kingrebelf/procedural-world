class_name ZFight
## Finds floors drawn twice at the same height: upward faces of different surfaces of a
## building (or of the building and its furniture) that lie in one plane and overlap.
## The depth buffer cannot tell them apart, so they flicker as the camera moves.

## Every type with a mesh of its own that you walk on or into.
static func building_types() -> Array:
	var out: Array = []
	out.append_array(KitHouse.PLANS.keys())
	out.append_array(KitBase.PLANS.keys())
	out.append_array(KitBase.YARDS.keys())
	out.append_array(Interiors.BOX.keys())
	out.append_array(Interiors.ROUND.keys())
	out.append_array(["hab_dome", "shrine"])
	out.append_array(ShipPad.SHIPS.keys())
	out.append_array(Landmark.SIZE.keys())
	for p in Stronghold.PIECES:
		out.append_array(p)
	var seen := {}
	var uniq: Array = []
	for t in out:
		if not seen.has(t):
			seen[t] = true
			uniq.append(t)
	return uniq

## [description] of each overlapping pair found in type t (its shell and furniture).
static func find(t: String) -> Array:
	var tris: Array = []
	_collect(ObjectLibrary.get_mesh(t), "", tris)
	if KitHouse.has(t) or Interiors.has(t):
		_collect(ObjectLibrary.get_mesh(t + "~in"), "in:", tris)
	tris.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	var seen := {}
	for i in tris.size():
		var a: Array = tris[i]
		for j in range(i + 1, tris.size()):
			var b: Array = tris[j]
			if b[0] - a[0] > 0.002:
				break
			if a[1] == b[1]:
				continue
			var pair := "%s|%s|%.2f" % [a[1], b[1], a[0]] if a[1] < b[1] else "%s|%s|%.2f" % [b[1], a[1], a[0]]
			if seen.has(pair):
				continue
			if _overlap(a, b):
				seen[pair] = true
				out.append("%s over %s at y %.3f near (%.1f, %.1f)" % [a[1], b[1], a[0], a[2].x, a[2].y])
	return out

## Upward, level triangles: [y, surface name, a, b, c (x/z)].
static func _collect(m: ArrayMesh, prefix: String, tris: Array) -> void:
	if m == null:
		return
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var mat := m.surface_get_material(s)
		var name := prefix + ("%d" % s) + (":" + mat.resource_name if mat and mat.resource_name != "" else "")
		var n := idx.size() if not idx.is_empty() else v.size()
		for i in range(0, n, 3):
			var p0 := v[idx[i] if not idx.is_empty() else i]
			var p1 := v[idx[i + 1] if not idx.is_empty() else i + 1]
			var p2 := v[idx[i + 2] if not idx.is_empty() else i + 2]
			# Level, facing up (by its normals), and above the ground it sinks into.
			if absf(p0.y - p1.y) > 0.001 or absf(p0.y - p2.y) > 0.001 or p0.y < 0.05:
				continue
			if (p1 - p0).cross(p2 - p0).length() < 1e-6:
				continue
			var ni: int = idx[i] if not idx.is_empty() else i
			if nv[ni].y < 0.99:
				continue
			tris.append([p0.y, name, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z), 1.0])

## Whether two level triangles facing the same way share more than a sliver of area.
static func _overlap(a: Array, b: Array) -> bool:
	if signf(a[5]) != signf(b[5]):
		return false
	for t in [[a, b], [b, a]]:
		var p: Array = t[0]
		var q: Array = t[1]
		for w in [Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6), Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)]:
			var pt: Vector2 = p[2] * w.x + p[3] * w.y + p[4] * w.z
			if Geometry2D.point_is_inside_triangle(pt, q[2], q[3], q[4]):
				return true
	return false

## The same, item by item among a room's furniture: [description] naming both items.
static func items(t: String) -> Array:
	var list: Array = KitHouse.FURNISH[t] if KitHouse.has(t) else Interiors.FURNISH.get(t, [])
	var per: Array = []
	for f in list:
		var name: String = f[0]
		var tris: Array = []
		if not name.begins_with("@"):
			var base := BuildCatalog._xf([name, f[1], f[2], 1.0])
			for part in BuildCatalog.model_parts(name):
				var xf: Transform3D = base * (part[2] as Transform3D)
				var arr: Array = part[1].duplicate()
				var v: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
				for i in v.size():
					v[i] = xf * v[i]
				arr[Mesh.ARRAY_VERTEX] = v
				var nv: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
				for i in nv.size():
					nv[i] = (xf.basis * nv[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nv
				var m2 := ArrayMesh.new()
				m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				_collect(m2, "", tris)
		per.append(tris)
	var out: Array = []
	for i in per.size():
		for j in range(i + 1, per.size()):
			var hit := false
			for a in per[i]:
				for b in per[j]:
					if absf(a[0] - b[0]) < 0.002 and _overlap(a, b):
						out.append("%s and %s at y %.3f" % [list[i][0], list[j][0], a[0]])
						hit = true
						break
				if hit:
					break
	return out
