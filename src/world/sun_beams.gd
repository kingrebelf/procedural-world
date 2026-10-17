class_name SunBeams
extends RefCounted
## Sunbeams through a room's windows (Interiors.sun_windows): each window's opening drawn
## out along the sun's rays across the room as a soft shaft of lit dust. The volumetric
## fog's cells are far coarser than an arrow slit, so it shows no beam there. The shader
## (sun_beams.gdshader) turns each window's box along the sun as it moves, lights it only
## while the sun is on that side, and measures how much of the shaft you look through.

static var _meshes := {}
static var _mat: ShaderMaterial

## The beams of a room type, as a node for its object's body, or null if it has none.
static func node(t: String) -> MeshInstance3D:
	var m := mesh(t)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The boxes stretch out along the sun in the shader, anywhere in the room below.
	mi.custom_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 16, 16))
	# Seen from further, a beam is only ever glimpsed through a window.
	mi.visibility_range_end = 60.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi

## The beams' material, shared by every room (tools scale its "strength").
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/world/sun_beams.gdshader")
	return _mat

## One box per window, its corners on the window (UV the corner across and up, UV2.x 0
## at the window and 1 where the beam ends); CUSTOM0 the window's centre and the floor's
## height, CUSTOM1 its inward normal (x, z) and half width and height, CUSTOM2 the room's
## half size across x and z and its ceiling height (the beam stays inside).
static func mesh(t: String) -> ArrayMesh:
	if _meshes.has(t):
		return _meshes[t]
	var wins := Interiors.sun_windows(t)
	var out: ArrayMesh = null
	if not wins.is_empty():
		var verts := PackedVector3Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		var c2 := PackedFloat32Array()
		var idx := PackedInt32Array()
		for w in wins:
			var v0 := verts.size()
			for k in 8:
				var corner := Vector3(-1.0 if k & 1 == 0 else 1.0, -1.0 if k & 2 == 0 else 1.0, float(k >> 2))
				verts.append(w[0])
				uv.append(Vector2(corner.x, corner.y))
				uv2.append(Vector2(corner.z, 0.0))
				var c: Vector3 = w[0]
				var n: Vector3 = w[1]
				c0.append_array([c.x, c.y, c.z, float(w[4])])
				c1.append_array([n.x, n.z, float(w[2]), float(w[3])])
				var half: Vector2 = w[6]
				c2.append_array([half.x, half.y, float(w[5]), 0.0])
			# The six faces (both sides are drawn; the shader keeps the far one).
			for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
				idx.append_array([v0 + f[0], v0 + f[1], v0 + f[2], v0 + f[0], v0 + f[2], v0 + f[3]])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_CUSTOM0] = c0
		arr[Mesh.ARRAY_CUSTOM1] = c1
		arr[Mesh.ARRAY_CUSTOM2] = c2
		arr[Mesh.ARRAY_INDEX] = idx
		var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
		out = ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	_meshes[t] = out
	return out
