class_name Wiring
extends Node
## Stringing cables with Copper Wire in hand: Use on a powered piece starts a cable there,
## Use on another strings it across (one Copper Wire per Power.WIRE_PER metres, at most
## Power.MAX_CABLE). Until then a loose cable hangs from the first piece to where you aim.
## Use on the first piece again lets it go; crouch and Use on a piece takes down all its
## cables and gives the wire back.

const REACH := 10.0

var player: Player
var _from := "" ## piece id the cable starts at
var _target := {} ## {chunk, o, id} of the powered piece under the crosshair
var _aim := Vector3.ZERO
var _ghost: MeshInstance3D
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D

func _ready() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_mat_ok = Builder._ghost_mat(Color(0.35, 1.0, 0.45, 0.7))
	_mat_bad = Builder._ghost_mat(Color(1.0, 0.3, 0.25, 0.7))

func active() -> bool:
	var it = player.held_item()
	return it != null and it["type"] == Power.WIRE

## Called every physics frame by the player.
func update() -> void:
	if not active() or player.ui_open or PowerGrid.current == null:
		_ghost.visible = false
		if not active():
			_from = ""
		_target = {}
		return
	_target = _find()
	var g := PowerGrid.current
	if _from == "" or g.piece(_from).is_empty():
		_from = ""
		_ghost.visible = false
		return
	var a := g.terminal_of(_from)
	var b: Vector3 = _aim
	if not _target.is_empty():
		b = Power.terminal(_target["o"], (_target["chunk"] as ChunkNode).position)
	var ok := a.distance_to(b) <= Power.MAX_CABLE
	_ghost.mesh = PowerGrid.cable_mesh(a, b, 0.018)
	_ghost.material_override = _mat_ok if ok else _mat_bad
	_ghost.visible = true

func _find() -> Dictionary:
	var cam := player.camera
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_aim = to
		return {}
	_aim = hit["position"]
	var col: Object = hit.get("collider")
	if col == null or not col.has_meta("obj"):
		return {}
	var c: ChunkNode = col.get_meta("chunk")
	var o: Dictionary = c.get_object(col.get_meta("obj"))
	if not Power.is_power(o["t"]) or o["st"].get("gone", false):
		return {}
	return {"chunk": c, "o": o, "id": PowerGrid.id_of(c, o)}

static func _mine(o: Dictionary) -> bool:
	return Doors.may_access(String(o["st"].get("owner", "")))

## Use with Copper Wire in hand.
func use() -> void:
	var g := PowerGrid.current
	if g == null:
		return
	if _target.is_empty():
		if _from != "":
			_from = ""
			Game.toast.emit("Let the cable go")
		else:
			Game.toast.emit("Aim at a generator, battery, pole, switch or lamp to start a cable")
		return
	var o: Dictionary = _target["o"]
	var c: ChunkNode = _target["chunk"]
	if not _mine(o):
		Game.toast.emit("That isn't yours to wire")
		return
	if player.sneaking():
		var back := g.unhook(c, o)
		_from = ""
		if back > 0:
			Game.give(ItemDB.make(Power.WIRE, back, 1.0, Game.origin_here("salvaged", -1, c.key)))
			Game.toast.emit("Took down its cables: %d Copper Wire back" % back)
		else:
			Game.toast.emit("It has no cables")
		return
	if _from == "":
		if Power.links(o).size() >= Power.max_links(o):
			Game.toast.emit("Every terminal on it is taken")
			return
		_from = _target["id"]
		Game.toast.emit("Cable started: Use on the piece to join it to")
		return
	if _from == _target["id"]:
		_from = ""
		Game.toast.emit("Let the cable go")
		return
	var a := g.piece(_from)
	var ca := g.chunk_of_id(_from)
	if a.is_empty() or ca == null:
		_from = ""
		return
	var why := g.connect_pieces(ca, a, c, o)
	if why != "":
		Game.toast.emit(why)
		return
	Audio.play_at("hit/plank", Power.terminal(o, c.position), -10.0)
	Game.add_xp(2.0, "Wiring")
	# Carry on from here, so a run of poles goes up one after another.
	_from = _target["id"]
	Game.toast.emit("Joined. The cable carries on from here: Use on the next piece, or on this one to stop")

## Look-at panel contents while holding Copper Wire.
func info() -> Dictionary:
	var k := func(a: String) -> String: return "[%s]" % Player._key(a)
	var lines: Array = []
	if _from == "":
		lines.append("%s on a powered piece starts a cable; %s on the next strings it across." % [k.call("use"), k.call("use")])
	else:
		var a := PowerGrid.current.terminal_of(_from) if PowerGrid.current != null else Vector3.ZERO
		var b: Vector3 = _aim if _target.is_empty() else Power.terminal(_target["o"], (_target["chunk"] as ChunkNode).position)
		var d := a.distance_to(b)
		lines.append("Cable %d m: %s" % [int(d), ("needs %d Copper Wire" % Power.wire_for(d)) if d <= Power.MAX_CABLE else "too long (at most %d m)" % int(Power.MAX_CABLE)])
		lines.append("%s on the piece it starts from lets it go." % k.call("use"))
	lines.append("Crouch and %s on a piece to take its cables down." % k.call("use"))
	lines.append("%d Copper Wire in your pack: %d m of cable" % [Game.inventory.count(Power.WIRE), int(Game.inventory.count(Power.WIRE) * Power.WIRE_PER)])
	var title := "Copper Wire"
	if not _target.is_empty():
		var nm := String(BuildCatalog.def(BuildCatalog.id_of(_target["o"]["t"])).get("name", ""))
		title = "Copper Wire  ·  %s" % nm
		lines.append_array(PowerGrid.current.describe(_target["chunk"], _target["o"], false) if PowerGrid.current != null else [])
	return {"title": title, "sub": "Wiring  ·  %s %s" % [k.call("use"), "join" if _from != "" else "start a cable"], "lines": lines, "icon": Power.WIRE}
