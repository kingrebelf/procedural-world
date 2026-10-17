extends SceneTree
## Lists every item a person can hold with its size in metres as modelled (x across,
## y along the handle, z front to back) and the scale the hand holds it at, so it can
## be read against real sizes. NPC work tools are listed as "npc:<job>".
##   godot --headless --path . --script res://tools/probe_held_scale.gd

func _initialize() -> void:
	var h := HumanModel.new()
	root.add_child(h)
	h.build({"height": 1.0, "build": 1.0, "female": false, "skin": Color(0.8, 0.6, 0.5), "hair": Color(0.2, 0.1, 0.05), "hair_style": 1, "cloth": Color(0.5, 0.3, 0.2), "cloth2": Color(0.3, 0.3, 0.4)}, Eras.MEDIEVAL, "")
	for t in ItemDB.ITEMS.keys():
		var d := ItemDB.def(t)
		if d.get("kind", "") in ["armor", "ammo", "resource", "vehicle", "station", "camp", "crop"]:
			continue
		var prop := Viewmodel.prop_for(t)
		h.hold(prop)
		_row(t, d.get("kind", ""), prop)
		h.hold(null)
	for job in HumanModel.WORK_TOOLS:
		h._tool(job)
		if h._held:
			_row("npc:" + job, "npc", h._held.get_child(0))
			h.hold(null)
	quit()

static func _row(t: String, kind: String, prop: Node3D) -> void:
	var k := prop.transform.basis.get_scale().x
	var s := HeldScale.size(prop) * k
	var card := HeldScale.unmodelled(prop)
	var bad := "" if card else HeldScale.problem(String(prop.get_meta("item", t)), prop)
	print("%-24s %-9s %5.2f x %5.2f x %5.2f  hand x%.2f%s%s" % [t, kind, s.x, s.y, s.z, k, "  (no model)" if card else "", "  TOO " + bad if bad != "" else ""])
