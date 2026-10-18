class_name Rugs
## Rugs on the floors of the rooms (KitHouse.RUGS, Interiors.RUGS): a hand-knotted wool
## rug drawn by rug.gdshader on its own UVs (border, lattice and medallions in natural
## dyes, worn where feet go), a few millimetres of pile, and a fringe of undyed warp at
## each end of its length. Each rug's material ("rug:kind:width cm:length cm:seed",
## through Materials.get_mat) is sized to it, so the border is as wide in every room.

## Palettes, sRGB: [field, border, motif, accent, guard, style (0 knotted, 1 flatweave)].
const KINDS := {
	"red": [Color(0.40, 0.16, 0.12), Color(0.17, 0.20, 0.27), Color(0.66, 0.60, 0.48), Color(0.52, 0.41, 0.21), Color(0.18, 0.12, 0.09), 0],
	"blue": [Color(0.18, 0.22, 0.31), Color(0.39, 0.17, 0.13), Color(0.66, 0.61, 0.50), Color(0.52, 0.42, 0.23), Color(0.16, 0.12, 0.09), 0],
	"felt": [Color(0.30, 0.33, 0.37), Color(0.22, 0.24, 0.27), Color(0.55, 0.54, 0.51), Color(0.47, 0.44, 0.38), Color(0.15, 0.16, 0.17), 1],
}
const PILE := 0.012
const FRINGE := 0.075
const FRINGE_GAP := 0.02
const FRINGE_W := 0.008

## Adds a rug of `kind` lying on the floor at `at` (its middle, the floor's height), size
## in metres along x and z, its fringe on the two ends of its length.
static func add(k: MeshKit, kind: String, at: Vector3, size: Vector2, seed: int) -> void:
	var mat := "rug:%s:%d:%d:%d" % [kind, roundi(size.x * 100), roundi(size.y * 100), seed % 1000]
	k._uv_fn = func(p: Vector3, _n: Vector3) -> Vector2:
		return Vector2(clampf(p.x / size.x + 0.5, 0.0, 1.0), clampf(p.z / size.y + 0.5, 0.0, 1.0))
	k.box(mat, Transform3D(Basis.IDENTITY, at + Vector3(0, PILE * 0.5, 0)), Vector3(size.x, PILE, size.y))
	if KINDS.get(kind, KINDS["red"])[5] == 1:
		return # a flatweave is bound, not fringed
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var along_z := size.y >= size.x
	var w := size.x if along_z else size.y
	var half := (size.y if along_z else size.x) * 0.5
	var n := int((w - 0.04) / FRINGE_GAP)
	for end in [-1.0, 1.0]:
		for i in n + 1:
			var across := -w * 0.5 + 0.02 + i * (w - 0.04) / n
			var len := FRINGE * r.randf_range(0.8, 1.15)
			var dir := Vector2(r.randf_range(-0.12, 0.12), end).normalized()
			var a := Vector2(across, end * half)
			var b := a + dir * len
			var s := Vector2(-dir.y, dir.x) * FRINGE_W * 0.5
			var y := 0.0025
			var p := [a - s, a + s, b + s * 0.6, b - s * 0.6]
			var q: Array = []
			for v in p:
				var v2: Vector2 = v
				q.append(at + (Vector3(v2.x, y, v2.y) if along_z else Vector3(v2.y, y, v2.x)))
			# Up-facing, whichever way the strand runs.
			var nrm: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
			if nrm.y > 0.0:
				k.quad("rug_fringe", Transform3D.IDENTITY, q[0], q[1], q[2], q[3])
			else:
				k.quad("rug_fringe", Transform3D.IDENTITY, q[0], q[3], q[2], q[1])

## The material for a "rug:..." name, or the fringe's undyed wool.
static func material(name: String) -> Material:
	if name == "rug_fringe":
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.6, 0.55, 0.45)
		f.roughness = 1.0
		f.cull_mode = BaseMaterial3D.CULL_DISABLED
		return f
	var parts := name.split(":")
	var pal: Array = KINDS.get(parts[1], KINDS["red"])
	var m := ShaderMaterial.new()
	m.shader = load("res://src/world/shaders/rug.gdshader")
	m.resource_name = name
	m.set_shader_parameter("size_m", Vector2(float(parts[2]) / 100.0, float(parts[3]) / 100.0))
	m.set_shader_parameter("field_col", pal[0])
	m.set_shader_parameter("border_col", pal[1])
	m.set_shader_parameter("motif_col", pal[2])
	m.set_shader_parameter("accent_col", pal[3])
	m.set_shader_parameter("guard_col", pal[4])
	m.set_shader_parameter("style", pal[5])
	m.set_shader_parameter("seed", float(parts[4]) * 0.137)
	return m
