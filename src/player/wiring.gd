class_name Wiring
extends Node
## Stringing cables with Copper Wire in hand: Use on a powered piece starts a cable there,
## Use on another strings it across (one Copper Wire per Power.WIRE_PER metres, at most
## Power.MAX_CABLE). Until then a loose cable hangs from the first piece to where you aim.
## Use on the first piece again lets it go; crouch and Use on a piece takes down all its
## cables and gives the wire back.
## Signal Wire in hand works the same way for the logic layer (Signals), one way only:
## from the piece that makes the signal to the one it should work.

const REACH := 10.0

var player: Player
var _from := "" ## piece id the cable starts at
var _mode := "" ## "power" (Copper Wire) or "signal" (Signal Wire) in hand
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
	return held_mode() != ""

## "power", "signal" or "" for what is in hand.
func held_mode() -> String:
	var it = player.held_item()
	if it == null:
		return ""
	if it["type"] == Power.WIRE:
		return "power"
	if it["type"] == Signals.WIRE:
		return "signal"
	return ""

func _signal() -> bool:
	return _mode == "signal"

func _end(id: String, o: Dictionary, c: ChunkNode) -> Vector3:
	return Power.signal_terminal(o, c.position) if _signal() else Power.terminal(o, c.position)

## Called every physics frame by the player.
func update() -> void:
	var m := held_mode()
	if m != _mode:
		_mode = m
		_from = ""
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
	var a := g.signal_terminal_of(_from) if _signal() else g.terminal_of(_from)
	var b: Vector3 = _aim
	if not _target.is_empty():
		b = _end(_target["id"], _target["o"], _target["chunk"])
	var ok := a.distance_to(b) <= (Signals.MAX_SPAN if _signal() else Power.MAX_CABLE)
	_ghost.mesh = PowerGrid.cable_mesh(a, b, 0.01 if _signal() else 0.018)
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
		elif _signal():
			Game.toast.emit("Aim at a lever, button, sensor, timer or gate to start a signal wire")
		else:
			Game.toast.emit("Aim at a generator, battery, pole, switch or lamp to start a cable")
		return
	var o: Dictionary = _target["o"]
	var c: ChunkNode = _target["chunk"]
	if not _mine(o):
		Game.toast.emit("That isn't yours to wire")
		return
	if _signal():
		_use_signal(g, c, o)
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
		if Power.max_links(o) == 0:
			Game.toast.emit("It takes no power: wire it with Signal Wire")
			return
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

## Use with Signal Wire in hand: start at a piece that makes a signal, end at one that
## takes it; crouched, take every signal wire on a piece down.
func _use_signal(g: PowerGrid, c: ChunkNode, o: Dictionary) -> void:
	if player.sneaking():
		var back := g.unhook_signals(c, o)
		_from = ""
		if back > 0:
			Game.give(ItemDB.make(Signals.WIRE, back, 1.0, Game.origin_here("salvaged", -1, c.key)))
			Game.toast.emit("Took down its signal wires: %d Signal Wire back" % back)
		else:
			Game.toast.emit("It has no signal wires")
		return
	if _from == "":
		if not Signals.has_out(o):
			Game.toast.emit("It makes no signal: start at a lever, button, sensor, timer or gate" if Signals.max_in(o) == 0 else "Start the wire at what makes the signal, then Use on this")
			return
		_from = _target["id"]
		Game.toast.emit("Signal wire started: Use on what it should work")
		return
	if _from == _target["id"]:
		_from = ""
		Game.toast.emit("Let the signal wire go")
		return
	var a := g.piece(_from)
	var ca := g.chunk_of_id(_from)
	if a.is_empty() or ca == null:
		_from = ""
		return
	var why := g.connect_signal(ca, a, c, o)
	if why != "":
		Game.toast.emit(why)
		return
	Audio.play_at("hit/plank", Power.signal_terminal(o, c.position), -14.0)
	Game.add_xp(2.0, "Wiring")
	# A gate or sensor wired on carries on from here; anything else ends the run.
	if Signals.has_out(o):
		_from = _target["id"]
		Game.toast.emit("Wired. It carries on from here: Use on the next piece, or on this one to stop")
	else:
		_from = ""
		Game.toast.emit("Wired: it now follows that signal")

## Look-at panel contents while holding Copper Wire.
func info() -> Dictionary:
	var k := func(a: String) -> String: return "[%s]" % Player._key(a)
	var sig := _signal()
	var item := "Signal Wire" if sig else "Copper Wire"
	var item_id := Signals.WIRE if sig else Power.WIRE
	var what := "signal wire" if sig else "cable"
	var span := Signals.MAX_SPAN if sig else Power.MAX_CABLE
	var lines: Array = []
	if _from == "":
		if sig:
			lines.append("%s on what makes the signal (lever, sensor, timer, gate), then %s on what it should work." % [k.call("use"), k.call("use")])
		else:
			lines.append("%s on a powered piece starts a cable; %s on the next strings it across." % [k.call("use"), k.call("use")])
	elif PowerGrid.current != null:
		var g := PowerGrid.current
		var a := g.signal_terminal_of(_from) if sig else g.terminal_of(_from)
		var b: Vector3 = _aim if _target.is_empty() else _end(_target["id"], _target["o"], _target["chunk"])
		var d := a.distance_to(b)
		var need := Signals.wire_for(d) if sig else Power.wire_for(d)
		lines.append("%s %d m: %s" % [what.capitalize(), int(d), ("needs %d %s" % [need, item]) if d <= span else "too long (at most %d m)" % int(span)])
		lines.append("%s on the piece it starts from lets it go." % k.call("use"))
	lines.append("Crouch and %s on a piece to take its %ss down." % [k.call("use"), what])
	var per := Signals.WIRE_PER if sig else Power.WIRE_PER
	lines.append("%d %s in your pack: %d m of %s" % [Game.inventory.count(item_id), item, int(Game.inventory.count(item_id) * per), what])
	var title := item
	if not _target.is_empty():
		var nm := String(BuildCatalog.def(BuildCatalog.id_of(_target["o"]["t"])).get("name", ""))
		title = "%s  ·  %s" % [item, nm]
		lines.append_array(PowerGrid.current.describe(_target["chunk"], _target["o"], false) if PowerGrid.current != null else [])
	return {"title": title, "sub": "Wiring  ·  %s %s" % [k.call("use"), "join" if _from != "" else "start a " + what], "lines": lines, "icon": item_id}
