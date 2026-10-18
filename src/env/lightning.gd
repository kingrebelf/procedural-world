class_name Lightning
## The shape of a lightning bolt: a crooked channel from the cloud base down to the
## ground, forking as it goes, made by splitting each stretch at a point pushed aside by
## a share of its length (so it is jagged at every scale, as the real thing is). The mesh
## is a set of ribbons that bolt.gdshader turns to face the camera.

## A bolt striking `ground` from `height` metres above it. r decides its shape.
static func bolt_mesh(r: RandomNumberGenerator, ground: Vector3, height: float) -> ArrayMesh:
	var top := ground + Vector3(r.randf_range(-250.0, 250.0), height, r.randf_range(-250.0, 250.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _channel(r, top, ground, 7)
	_ribbon(st, main, 1.0, 3.0)
	# Forks: from points along the upper part of the channel, angling down and away and
	# dying out in the air, dimmer and thinner than the stroke itself.
	var forks := r.randi_range(2, 5)
	for i in forks:
		var k := r.randi_range(4, maxi(5, int(main.size() * 0.65)))
		var from: Vector3 = main[k]
		var nxt: Vector3 = main[mini(k + 1, main.size() - 1)]
		var dir := (nxt - from).normalized()
		var out := Vector3(r.randf_range(-1.0, 1.0), 0.0, r.randf_range(-1.0, 1.0)).normalized()
		var reach := (from.y - ground.y) * r.randf_range(0.2, 0.5)
		var to: Vector3 = from + (dir * 0.6 + out * 0.8 + Vector3.DOWN * 0.5).normalized() * reach
		var f := _channel(r, from, to, 5)
		_ribbon(st, f, r.randf_range(0.25, 0.5), 1.4)
		# Now and then a fork forks again.
		if r.randf() < 0.4 and f.size() > 6:
			var j := r.randi_range(2, f.size() - 3)
			var fj: Vector3 = f[j]
			var g := _channel(r, fj, fj + (out.rotated(Vector3.UP, r.randf_range(-1.0, 1.0)) + Vector3.DOWN).normalized() * reach * 0.4, 4)
			_ribbon(st, g, 0.15, 0.9)
	return st.commit()

## Points from a to b, split `depth` times.
static func _channel(r: RandomNumberGenerator, a: Vector3, b: Vector3, depth: int) -> Array:
	var pts: Array = [a, b]
	var rough := 0.22
	for d in depth:
		var nxt: Array = [pts[0]]
		for i in range(1, pts.size()):
			var p: Vector3 = pts[i - 1]
			var q: Vector3 = pts[i]
			var l := p.distance_to(q)
			var m := (p + q) * 0.5 + Vector3(r.randf_range(-1.0, 1.0), r.randf_range(-0.3, 0.3), r.randf_range(-1.0, 1.0)) * l * rough
			nxt.append(m)
			nxt.append(q)
		pts = nxt
		rough *= 0.92
	return pts

## A ribbon along the points: each stretch a quad, its two sides told apart by UV.x and
## its direction carried in the normal. COLOR.a is its brightness, UV2.x its width.
static func _ribbon(st: SurfaceTool, pts: Array, bright: float, width: float) -> void:
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var dir := (b - a).normalized()
		# Thinner and dimmer toward the tip of a fork.
		var fade := 1.0 - float(i) / float(pts.size()) * 0.5
		var corners := [[a, -1.0], [a, 1.0], [b, 1.0], [a, -1.0], [b, 1.0], [b, -1.0]]
		for c in corners:
			st.set_normal(dir)
			st.set_color(Color(1, 1, 1, bright * fade))
			st.set_uv(Vector2(c[1], 0.0))
			st.set_uv2(Vector2(width * fade, 0.0))
			st.add_vertex(c[0])
