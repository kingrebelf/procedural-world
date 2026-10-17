class_name BoatWater
extends MeshInstance3D
## The water's answer to a boat (BoatNode): foam lapping round the hull where it meets the
## water, piling up into a white cushion at the bow under way. Lies flat on the swell (the
## shader follows the waves), turning only with the boat's heading, so it never tips up
## out of the water when the hull pitches. The track she leaves behind is BoatWake.

static var _mat: ShaderMaterial

## The lapping foam (COLOR.r 0) round the waterline.
static func build(kind: String) -> BoatWater:
	var bw := BoatWater.new()
	bw.name = "BoatWater"
	bw.top_level = true
	bw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bw.visibility_range_end = 700.0
	var d: Dictionary = Boats.KINDS[kind]
	var L: float = d["len"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Lapping foam: a band round the waterline, a little under the hull and out onto the water.
	var line := BoatModel.waterline(kind)
	var wide := 0.28 + L * 0.025
	var n := line.size()
	for i in n:
		var a := line[i]
		var b := line[(i + 1) % n]
		var na := _out(line, i)
		var nb := _out(line, (i + 1) % n)
		var ua := clampf(-a.y / (L * 0.5), 0.0, 1.0)
		var ub := clampf(-b.y / (L * 0.5), 0.0, 1.0)
		_quad(st, Color(0, 1, 0), [a - na * 0.08, b - nb * 0.08, b + nb * wide, a + na * wide], [Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, 1), Vector2(ua, 1)])
	bw.mesh = st.commit()
	bw.material_override = material()
	return bw

## The one material for a boat's foam and her wake (BoatWake).
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/vehicles/boat_water.gdshader")
		_mat.render_priority = 1
	return _mat

## Puts the foam under a boat at `p` (water plane) heading `yaw`, `speed` 0..1.
func follow(p: Vector2, yaw: float, speed: float) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)) # the shader lays it on the swell
	set_instance_shader_parameter("speed", speed)

static func _out(line: PackedVector2Array, i: int) -> Vector2:
	var n := line.size()
	var t := line[(i + 1) % n] - line[(i - 1 + n) % n]
	var o := Vector2(t.y, -t.x).normalized()
	# Outward: away from the outline's middle.
	return -o if o.dot(line[i]) < 0.0 else o

static func _quad(st: SurfaceTool, c: Color, q: Array, uv: Array) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		var p: Vector2 = q[k]
		st.set_color(c)
		st.set_uv(uv[k])
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, 0.0, p.y))
