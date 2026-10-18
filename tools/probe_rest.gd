extends SceneTree
class_name ProbeRest
## Where free pieces you build (tables, chests, crates) come to rest: BuildCatalog.rest_free
## against a small room of real colliders, a floor over the ground with a wall and a step.
##   godot --headless --path . --script res://tools/probe_rest.gd
## The integration test runs it too: run() returns {"lines", "bad"}.
func _init() -> void:
	var r: Dictionary = await run(self, Vector3.ZERO)
	for l in r["lines"]:
		print(l)
	quit(1 if r["bad"] > 0 else 0)

static func _box(parent: Node, pos: Vector3, size: Vector3, layer: int) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	parent.add_child(b)

## Its real corners (its mesh bounds turned with it, not their square box).
static func _corners(id: String, pos: Vector3, yaw: float) -> Array:
	var a := BuildCatalog.mesh(id).get_aabb()
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var out := []
	for i in 8:
		out.append(xf * Vector3(a.end.x if i & 1 else a.position.x, a.end.y if i & 2 else a.position.y, a.end.z if i & 4 else a.position.z))
	return out

static func run(tree: SceneTree, at: Vector3) -> Dictionary:
	var room := Node3D.new()
	room.position = at
	tree.root.add_child(room)
	_box(room, Vector3(0, -0.5, 0), Vector3(20, 1, 20), 1) # the ground, top 0
	_box(room, Vector3(0, 0.1, 0), Vector3(6, 0.2, 6), 2) # a floor, top 0.2
	_box(room, Vector3(3.1, 1.5, 0), Vector3(0.2, 3, 6), 2) # a wall, inner face x 3
	_box(room, Vector3(-2, 0.35, -2), Vector3(1, 0.3, 1), 2) # a step, top 0.5
	_box(room, Vector3(0, 0.6, -2.2), Vector3(0.8, 0.8, 0.8), 2) # a crate already built
	await tree.physics_frame
	await tree.physics_frame
	var sp := room.get_world_3d().direct_space_state
	var eye := at + Vector3(0, 1.6, 0)
	var lines := []
	var bad := 0
	# [what, id, aimed at, yaw, expected: foot height, or false (can't fit), or "keep"]
	for t in [["table aimed 5 cm over the floor", "table", Vector3(0, 0.25, 0), 0.3, 0.2],
			["crate aimed at the wall", "metal_crate", Vector3(3.0, 1.4, 1), 0.3, 0.2],
			["crate half on the step", "metal_crate", Vector3(-1.6, 0.25, -2), 0.3, 0.5],
			["chest into the built crate", "storage_chest", Vector3(0.2, 0.2, -1.9), 0.0, 0.2],
			["table across the wall", "table", Vector3(2.9, 0.25, 0), 0.3, false],
			["banner on the wall", "banner_red", Vector3(2.95, 1.6, 0), 0.3, "keep"]]:
		var r := BuildCatalog.rest_free(sp, t[1], at + t[2], t[3], [], eye)
		var p: Vector3 = r["pos"] - at
		var ok := true
		var why := ""
		if t[4] is bool:
			ok = not r["ok"]
			why = "fits" if r["ok"] else ""
		elif t[4] is String:
			ok = r["ok"] and p.distance_to(t[2]) < 0.001
			why = "moved" if not ok else ""
		else:
			var cs := _corners(t[1], p, t[3])
			var foot := INF
			var far := -INF
			for c in cs:
				foot = minf(foot, c.y)
				far = maxf(far, c.x)
			if not r["ok"] or absf(foot - float(t[4])) > 0.005:
				ok = false
				why = "foot %.3f" % foot
			elif far > 3.005:
				ok = false
				why = "into the wall %.3f" % (far - 3.0)
			elif t[1] == "storage_chest":
				var q := PhysicsShapeQueryParameters3D.new()
				var a := BuildCatalog.mesh(t[1]).get_aabb()
				var sh := BoxShape3D.new()
				sh.size = a.size - Vector3(0.01, 0.06, 0.01)
				q.shape = sh
				q.collision_mask = 2
				q.transform = Transform3D(Basis(Vector3.UP, t[3]), at + p + a.get_center() + Vector3(0, 0.03, 0))
				if not sp.intersect_shape(q, 1).is_empty():
					ok = false
					why = "inside the crate"
		bad += 0 if ok else 1
		lines.append("%s %s: %s %s" % ["ok  " if ok else "BAD ", t[0], r, why])
	room.queue_free()
	lines.append("%d problems" % bad)
	return {"lines": lines, "bad": bad}
