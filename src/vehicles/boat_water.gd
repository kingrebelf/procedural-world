class_name BoatWater
extends MeshInstance3D
## The water's answer to a boat (BoatNode): foam lapping round the hull where it meets the
## water, and under way the bow waves spreading back in a V and the wash behind the stern.
## Lies flat on the swell (the shader follows the waves), turning only with the boat's
## heading, so it never tips up out of the water when the hull pitches.

static var _mat: ShaderMaterial

## Parts: the lapping foam (COLOR.r 0), two bow waves (0.5) and the stern wash (1).
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
	if float(d["moves"]) > 0.0 and kind != "raft":
		var h: Dictionary = BoatModel.HULLS.get(kind, {})
		var hw: float = BoatModel._width_at(h, 0.8, 0.0) if not h.is_empty() else 0.6
		var beam: float = BoatModel._width_at(h, 0.45, 0.0) if not h.is_empty() else 0.8
		var reach := clampf(L * (1.2 + float(d["moves"]) * 0.55), 6.0, 70.0) # longer the faster she goes
		var motor: bool = Eras.SCIFI == int(d["era"])
		# Bow waves: from the bow's shoulders back and out at the Kelvin angle.
		for s in [1.0, -1.0]:
			var from := Vector2(s * hw * 0.8, -L * 0.3)
			var dir := Vector2(s * sin(deg_to_rad(21.0)), cos(deg_to_rad(21.0)))
			_strip(st, Color(0.5, 1.0, 0), from, dir, reach, 0.25 + L * 0.02, reach * 0.2)
		# Wash: churned water straight back from the stern (a propeller's is stronger).
		_strip(st, Color(1, 1.0 if motor else 0.55, 0), Vector2(0, L * 0.5 - 0.3), Vector2(0, 1), clampf(L * 2.2, 6.0, 55.0), beam * 1.2, beam * 2.6)
	bw.mesh = st.commit()
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/vehicles/boat_water.gdshader")
		_mat.render_priority = 1
	bw.material_override = _mat
	return bw

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

static func _strip(st: SurfaceTool, c: Color, from: Vector2, dir: Vector2, length: float, w0: float, w1: float) -> void:
	var segs := 14
	var side := Vector2(dir.y, -dir.x)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := from + dir * length * t0
		var p1 := from + dir * length * t1
		var h0 := lerpf(w0, w1, t0) * 0.5
		var h1 := lerpf(w0, w1, t1) * 0.5
		_quad(st, c, [p0 - side * h0, p1 - side * h1, p1 + side * h1, p0 + side * h0], [Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1)])

static func _quad(st: SurfaceTool, c: Color, q: Array, uv: Array) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		var p: Vector2 = q[k]
		st.set_color(c)
		st.set_uv(uv[k])
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, 0.0, p.y))
