class_name HairStrands
extends RefCounted
## Turns the kit's sculpted hair (solid clumps that read as a moulded helmet) into hair:
## each mesh gets a combing direction per vertex (out and down from the crown, straight
## down for a beard) in its tangents, its rest position and how far it is toward the tips,
## and hair.gdshader draws strands along that direction with a highlight band across them.
## A few shells, the same mesh pushed out a few millimetres and cut to strands, break the
## outline into loose fibres. Old hair thins (the scalp shows through at the crown).

## Shell layers over the base mesh, and how far the outermost sits out (m).
const SHELLS := 4
const DEPTH := {"Hair_Long": 0.009, "Hair_Buns": 0.008, "Hair_SimpleParted": 0.007, "Hair_Beard": 0.005, "Hair_Buzzed": 0.0035, "Hair_BuzzedFemale": 0.0035}

## How far each style's base layer stands off the scalp (m): where the kit mesh hugs the
## skull, the head showed through as bare patches.
const LIFT := {"Hair_SimpleParted": 0.004, "Hair_Buzzed": 0.002, "Hair_BuzzedFemale": 0.002, "Hair_Long": 0.003, "Hair_Buns": 0.003}

static var _cache := {}
static var _mats := {}

## The kit mesh with combing tangents, CUSTOM0 = rest position + tip factor; cached per style.
static func mesh(style: String, src: Mesh) -> ArrayMesh:
	if _cache.has(style):
		return _cache[style]
	var a := src.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var box := src.get_aabb()
	var beard := style == "Hair_Beard"
	var brows := style.begins_with("Eyebrows")
	# The crown: the top of the head, a little behind the middle.
	var crown := Vector3(box.get_center().x, box.end.y, box.get_center().z - box.size.z * 0.12)
	var tangents := PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	var custom := PackedFloat32Array()
	custom.resize(verts.size() * 4)
	var combed := PackedFloat32Array()
	combed.resize(verts.size() * 3)
	for i in verts.size():
		var p := verts[i]
		var n := normals[i].normalized()
		var dir := Vector3.DOWN
		if brows:
			# Brow hairs run out from the middle of the face, a little upward.
			dir = Vector3(signf(p.x - box.get_center().x), 0.15, 0.0).normalized()
		elif not beard:
			var out := p - crown
			out.y = 0.0
			# Near the crown hair runs outward; lower down it falls.
			var fall := clampf((crown.y - p.y) / 0.08, 0.0, 1.0)
			dir = (out.normalized() * (1.0 - fall * 0.7) + Vector3.DOWN * (0.25 + fall)).normalized() if out.length() > 0.001 else Vector3.DOWN
		var t := dir - n * dir.dot(n)
		if t.length() < 0.05:
			t = Vector3.FORWARD - n * Vector3.FORWARD.dot(n)
		t = t.normalized()
		tangents[i * 4] = t.x
		tangents[i * 4 + 1] = t.y
		tangents[i * 4 + 2] = t.z
		tangents[i * 4 + 3] = 1.0
		combed[i * 3] = t.x
		combed[i * 3 + 1] = t.y
		combed[i * 3 + 2] = t.z
		custom[i * 4] = p.x
		custom[i * 4 + 1] = p.y
		custom[i * 4 + 2] = p.z
		# Toward the tips: 0 at the roots (crown, or the jaw for a beard), 1 at the ends.
		custom[i * 4 + 3] = clampf((box.end.y - p.y) / maxf(box.size.y, 0.01), 0.0, 1.0)
		if brows:
			custom[i * 4 + 3] = clampf(absf(p.x - box.get_center().x) / maxf(box.size.x * 0.5, 0.01), 0.0, 1.0)
	a[Mesh.ARRAY_TANGENT] = tangents
	a[Mesh.ARRAY_CUSTOM0] = custom
	a[Mesh.ARRAY_CUSTOM1] = combed
	for ch in [Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		a[ch] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	_cache[style] = m
	return m

## The hair material for the kit texture `which` (1 or 2).
static func material(which: int) -> ShaderMaterial:
	var key := "hair_%d" % which
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/npc/hair.gdshader")
		m.set_shader_parameter("tex", load(HumanModel.DIR + "hair_%d_albedo.png" % which))
		m.set_shader_parameter("nrm", load(HumanModel.DIR + "hair_%d_normal.png" % which))
		_mats[key] = m
	return _mats[key]

## Adds the shells over hair mesh `mi` (already skinned and recoloured); returns them.
static func shells(mi: MeshInstance3D, style: String) -> Array:
	var out: Array = []
	var depth: float = DEPTH.get(style, 0.006)
	for k in SHELLS:
		var s := MeshInstance3D.new()
		s.name = "%s_shell%d" % [mi.name, k]
		s.mesh = mi.mesh
		mi.get_parent().add_child(s)
		s.skin = mi.skin
		s.skeleton = mi.skeleton
		s.material_override = mi.material_override
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Far off, the shells are too fine to see.
		s.visibility_range_end = 18.0
		s.set_instance_shader_parameter("shell", float(k + 1) / float(SHELLS))
		s.set_instance_shader_parameter("shell_depth", depth)
		out.append(s)
	return out
