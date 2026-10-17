class_name ForestFloor
## What lies on the floor of a wood besides its litter colour (GroundCover's litter, which
## the terrain shader paints): fallen branches, cones under conifers, cushions of moss and
## drifts of shed needles. A few low-poly meshes, instanced as ground clutter around the
## trees of each chunk (ChunkNode.build_clutter_buffers), so every world gets them.

const KINDS := ["branch", "cones", "moss", "duff"]

static func has(key: String) -> bool:
	return key.begins_with("floor:") and key.substr(6) in KINDS

## The mesh for "floor:<kind>".
static func build(key: String) -> ArrayMesh:
	var kind := key.substr(6)
	var k := MeshKit.new(WHash.str_hash(key) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(key)
	match kind:
		"branch": _branch(k, r)
		"cones": _cones(k, r)
		"moss": _moss(k, r)
		"duff": _duff(k, r)
	return k.commit(Materials.get_mat)

## A dead branch lying on the ground, bowed, with a couple of side twigs: grey-brown,
## the bark weathered paler than a living tree's.
static func _branch(k: MeshKit, r: RandomNumberGenerator) -> void:
	var col := Color(0.4, 0.34, 0.27)
	var len := 1.6
	var segs := 4
	var p := Vector3(-len * 0.5, 0.035, 0)
	var dir := Vector3(1, 0, 0)
	for i in segs:
		var l := len / segs
		dir = dir.rotated(Vector3.UP, r.randf_range(-0.25, 0.25)).normalized()
		var rad := lerpf(0.04, 0.018, float(i) / segs)
		# The cylinder runs up +Y: lay it along dir.
		var xf := Transform3D(_along(dir), p)
		k.cylinder("bark_w", xf, rad, rad * 0.85, l * 1.04, 6, true, 0.15, 1, col.lerp(Color(0.5, 0.47, 0.42), r.randf() * 0.4))
		if i > 0 and i < segs - 1:
			var side := dir.rotated(Vector3.UP, (0.7 if i % 2 == 0 else -0.7) + r.randf_range(-0.2, 0.2))
			var tl := r.randf_range(0.3, 0.5)
			k.cylinder("bark_w", Transform3D(_along(side), p + Vector3(0, 0.005, 0)), rad * 0.45, rad * 0.25, tl, 5, false, 0.1, 1, col)
		p += dir * l

## A Basis whose +Y runs along `d`.
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.FORWARD).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

## A few fallen cones and a scrap of twig.
static func _cones(k: MeshKit, r: RandomNumberGenerator) -> void:
	for i in 5:
		var at := Vector3(r.randf_range(-0.4, 0.4), 0.03, r.randf_range(-0.4, 0.4))
		var d := Vector3(cos(i * 2.4), r.randf_range(-0.15, 0.1), sin(i * 2.4))
		var s := r.randf_range(0.8, 1.2)
		k.sphere("bark_w", Transform3D(_along(d).scaled(Vector3(s, s, s)), at), 0.045, 5, 7, 0.35, 0.5,
			Color(0.38, 0.27, 0.17).lerp(Color(0.5, 0.42, 0.32), r.randf() * 0.5))
	k.cylinder("bark_w", Transform3D(_along(Vector3(1, 0, 0.3)), Vector3(-0.1, 0.012, -0.26)), 0.01, 0.006, 0.4, 4, false, 0.0, 1, Color(0.36, 0.3, 0.24))

## A low cushion of moss over a buried stone or root.
static func _moss(k: MeshKit, r: RandomNumberGenerator) -> void:
	for i in 3:
		var at := Vector3(r.randf_range(-0.3, 0.3), 0.0, r.randf_range(-0.3, 0.3))
		var rad := r.randf_range(0.18, 0.4)
		k.sphere("leaf_w", Transform3D(Basis(), at), rad, 4, 9, 0.35, 0.32,
			Color.from_hsv(r.randf_range(0.2, 0.26), 0.55, r.randf_range(0.32, 0.42)), true)

## A drift of shed needles and old leaves, a hand deep in the hollows: a flat, ragged mat
## that breaks up the smooth ground under the trees.
static func _duff(k: MeshKit, r: RandomNumberGenerator) -> void:
	for i in 4:
		var at := Vector3(r.randf_range(-0.5, 0.5), -0.01, r.randf_range(-0.5, 0.5))
		k.sphere("leaf_w", Transform3D(Basis(Vector3.UP, r.randf() * TAU), at), r.randf_range(0.3, 0.55), 3, 9, 0.5, 0.08,
			Color(0.36, 0.25, 0.15).lerp(Color(0.48, 0.36, 0.22), r.randf()), true)
