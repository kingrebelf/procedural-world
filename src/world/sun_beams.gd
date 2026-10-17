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
	var mi := Shafts.new()
	mi.wins = Interiors.sun_windows(t)
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

## The most windows a room's beams follow the sun at (Shafts, the shader's lit0..lit5).
const MAX_WINDOWS := 24

## A room's beams. Each window's shines only while the sun reaches it from outside: rays
## toward the sun from just outside its two ends, past animals, people and carts (anything
## but the ground and buildings), every half second near you, fading as it changes.
class Shafts extends MeshInstance3D:
	var wins: Array = []
	var _want := PackedFloat32Array()
	var _shown := PackedFloat32Array()
	var _t := 0.0

	func _ready() -> void:
		_want.resize(mini(wins.size(), MAX_WINDOWS))
		_shown.resize(_want.size())
		_t = randf() * 0.5

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or cam.global_position.distance_to(global_position) > visibility_range_end + 10.0:
			return
		_t -= delta
		if _t <= 0.0:
			_t = 0.5
			_aim()
		var moved := false
		for i in _shown.size():
			var v := move_toward(_shown[i], _want[i], delta * 1.5)
			if v != _shown[i]:
				_shown[i] = v
				moved = true
		if moved:
			for j in MAX_WINDOWS / 4:
				var v := Vector4.ZERO
				for c in 4:
					if j * 4 + c < _shown.size():
						v[c] = _shown[j * 4 + c]
				set_instance_shader_parameter("lit%d" % j, v)

	func _aim() -> void:
		var s := Atmosphere.sun_dir
		var space := get_world_3d().direct_space_state
		var xf := global_transform
		for i in _want.size():
			var w: Array = wins[i]
			var n := (xf.basis * (w[1] as Vector3)).normalized()
			_want[i] = 0.0
			if s.y < 0.03 or s.dot(n) > -0.05:
				continue
			# Just outside the wall, at the window's top and bottom.
			var out := xf * ((w[0] as Vector3) - (w[1] as Vector3) * 0.45)
			for dy in [-0.6, 0.6]:
				var from := out + xf.basis * Vector3(0, float(w[3]) * dy, 0)
				if _clear(space, from, from + s * 120.0):
					_want[i] += 0.5

	static func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
		for k in 4:
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				return true
			if hit["collider"] is StaticBody3D:
				return false
			q.exclude = q.exclude + [hit["rid"]]
		return true

## The beams' material, shared by every room (tools scale its "strength").
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/world/sun_beams.gdshader")
	return _mat

## One box per window, its corners on the window (UV the corner across and up, UV2.x 0
## at the window and 1 where the beam ends); CUSTOM0 the window's centre and the floor's
## height, CUSTOM1 its inward normal (x, z) and half width and height, CUSTOM2 the room's
## half size across x and z and its ceiling height (the beam stays inside) and the
## window's number (how much sun reaches it: Shafts).
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
				c2.append_array([half.x, half.y, float(w[5]), float(wins.find(w))])
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
