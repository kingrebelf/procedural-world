class_name Builder
extends Node
## Placing building pieces and crafting stations. While a piece is in the selected hotbar
## slot, a see-through ghost shows where it will go: green when it fits, red when not
## (and the look-at panel says why). Pieces snap to a grid, and to the storeys of whatever
## you have already built nearby; aimed at a piece of the same kind they carry it on: the
## next wall along or on top, the next floor tile over, the next roof edge to edge (see
## BuildCatalog.candidates). Use places it; the rotate key turns it (sprint + rotate turns
## it back, or flips a wall). Raise and lower move it a storey at a time (a quarter metre
## with the grid off), and the grid can be switched off for free placement.

const REACH := 9.0
const ANCHOR_RADIUS := 10.0
## Built pieces around you are gathered this often (and right after you place one), not
## every frame: a chunk can hold hundreds of objects.
const NEAR_EVERY := 0.25
const NEAR_RADIUS := REACH + 6.0
## A floor whose top is no higher than this over your feet can go down where you stand:
## it lifts you onto it.
const STEP_UP := 0.45

var player: Player
var _ghost: MeshInstance3D
var _id := ""
var _turn := 0
var _lift := 0
var _free := false
var _target := {}
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _near: Array = []
var _near_t := 0.0
var _near_at := Vector3.INF

func _ready() -> void:
	_mat_ok = _ghost_mat(Color(0.35, 1.0, 0.45, 0.38))
	_mat_bad = _ghost_mat(Color(1.0, 0.3, 0.25, 0.38))
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)

static func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m

func active() -> bool:
	return _id != ""

func piece_id() -> String:
	return _id

## Runs before the menus see the event, so the controller buttons shared with crafting,
## the character panel and eating act on the piece while one is held.
func _input(event: InputEvent) -> void:
	if not active() or player.ui_open or Input.is_action_pressed("hotbar_pick"):
		return
	var took := true
	if event.is_action_pressed("rotate_build"):
		_turn = posmod(_turn + (-1 if Input.is_action_pressed("sprint") else 1), 24 if _free else 4)
	elif event.is_action_pressed("build_raise"):
		_lift += 1
	elif event.is_action_pressed("build_lower"):
		_lift -= 1
	elif event.is_action_pressed("build_snap"):
		if BuildCatalog.def(_id).get("snap") == "door":
			Game.toast.emit("Doors always hang in a doorway")
		elif BuildCatalog.def(_id).get("snap") == "free":
			Game.toast.emit("This piece already places freely")
		else:
			_free = not _free
			_lift = 0
			_turn = 0
			Game.toast.emit("Grid snap off: free placement" if _free else "Grid snap on")
	elif event is InputEventJoypadButton and (event.is_action("build_raise") or event.is_action("build_lower") or event.is_action("build_snap")):
		pass # swallow the release too
	else:
		took = false
	if took:
		get_viewport().set_input_as_handled()

## Called every physics frame by the player.
func update() -> void:
	var it = player.held_item()
	var id: String = it["type"] if it != null and BuildCatalog.is_piece_item(it["type"]) else ""
	if id != _id:
		_id = id
		_turn = 0
		_lift = 0
		_free = false
		_ghost.mesh = BuildCatalog.mesh(id) if id != "" else null
	if _id == "" or player.ui_open:
		_ghost.visible = false
		_target = {}
		return
	_target = _find_target()
	if _target.is_empty():
		_ghost.visible = false
		return
	_ghost.visible = true
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, _target["yaw"]), _target["pos"])
	_ghost.material_override = _mat_ok if _target["ok"] else _mat_bad

## Built pieces near you (BuildCatalog.built_near), refreshed every NEAR_EVERY seconds.
func near_pieces() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var here := player.global_position
	if now - _near_t > NEAR_EVERY or here.distance_to(_near_at) > 2.0:
		_near = BuildCatalog.built_near(player.streamer, here, NEAR_RADIUS)
		_near_t = now
		_near_at = here
	return _near

func _forget_near() -> void:
	_near_t = -1.0

func _find_target() -> Dictionary:
	var cam := player.camera
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if Doors.is_door_piece(_id):
		return _door_target(from, p)
	if BuildCatalog.def(_id).has("mount"):
		return _mount_target(from, p, n)
	var near := near_pieces()
	var col: Object = hit.get("collider")
	var anchor = null
	var ctx := {"lift": _lift, "free": _free, "normal": n, "eye": from, "near": near}
	var on_ground := not (col != null and col.has_meta("obj"))
	if col != null and col.has_meta("obj"):
		var c: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = c.get_object(col.get_meta("obj"))
		if BuildCatalog.is_built(o["t"]):
			var hid := BuildCatalog.id_of(o["t"])
			ctx["hit_mode"] = String(BuildCatalog.def(hid).get("snap", "free"))
			if ctx["hit_mode"] != "free":
				anchor = c.position + o["p"]
				ctx["hit_pos"] = anchor
				ctx["hit_yaw"] = float(o["r"])
				ctx["hit_id"] = hid
	if anchor == null:
		anchor = BuildCatalog.nearest_in(near, p, ANCHOR_RADIUS)
	# Nudge off the surface we hit, so the cell is the one we are looking from.
	var probe := p + n * 0.05
	var list := BuildCatalog.candidates(_id, probe, player.yaw(), _turn, anchor, on_ground, ctx)
	var s: Dictionary = list[0]
	var why := "occupied"
	for e in list:
		if not BuildCatalog.occupied_in(near, _id, e["pos"], e["yaw"]):
			s = e
			why = ""
			break
	var pos: Vector3 = s["pos"]
	if anchor == null and _id == "foundation" and not _free:
		pos.y = p.y + 0.12 + _lift * float(BuildCatalog.def(_id)["storey"])
	if why == "" and pos.distance_to(from) > REACH + 2.0:
		why = "reach"
	if why == "" and player.streamer and player.streamer.get_chunk(ChunkStreamer.chunk_of(pos)) == null:
		why = "unloaded"
	if why == "" and _in_the_way(pos, s["yaw"]):
		why = "player"
	if why == "" and Game.stats.level < Recipes.unlock_level(_id):
		why = "level"
	return {"pos": pos, "yaw": s["yaw"], "ok": why == "", "why": why}

## Your own body box, feet to head.
func _body_box() -> AABB:
	var f := player.global_position
	return AABB(f + Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.8, 0.7))

## True when the piece would close round you. A floor low enough to step onto doesn't
## count: placing it lifts you on top.
func _in_the_way(pos: Vector3, yaw: float) -> bool:
	var box := BuildCatalog.world_aabb(_id, pos, yaw).grow(-0.05)
	var body := _body_box()
	if not box.intersects(body):
		return false
	return box.end.y > body.position.y + STEP_UP or BuildCatalog.def(_id).get("snap") == "free"

## A door hangs in the doorway you aim at (or through), at its spot and facing; the
## rotate key hangs it the other way round. Red, at the aim, when there's no doorway.
func _door_target(from: Vector3, p: Vector3) -> Dictionary:
	var dw := Doors.doorway_near(player.streamer, _id, from, p)
	if dw.is_empty():
		return {"pos": p, "yaw": player.yaw() + PI, "ok": false, "why": "doorway"}
	var pos: Vector3 = dw["pos"]
	var yaw: float = dw["yaw"] + (PI if _turn % 2 else 0.0)
	var why := ""
	if pos.distance_to(from) > REACH + 2.0:
		why = "reach"
	elif BuildCatalog.occupied_in(near_pieces(), _id, pos, yaw):
		why = "door_there"
	elif Game.stats.level < Recipes.unlock_level(_id):
		why = "level"
	return {"pos": pos, "yaw": yaw, "ok": why == "", "why": why}

## A lamp, switch or box fixed to what you aim at: a wall (standing out of it along its
## local +z) or a ceiling (hanging down from it). Red when the surface faces the wrong way.
func _mount_target(from: Vector3, p: Vector3, n: Vector3) -> Dictionary:
	var mount := String(BuildCatalog.def(_id)["mount"])
	var why := ""
	var yaw := 0.0
	if mount == "ceiling":
		yaw = snappedf(player.yaw() + PI, PI / 12.0) + _turn * PI * 0.5
		if n.y > -0.6:
			why = "ceiling"
	else:
		yaw = atan2(n.x, n.z)
		if absf(n.y) > 0.45:
			why = "wall"
	if why == "" and p.distance_to(from) > REACH + 2.0:
		why = "reach"
	elif why == "" and player.streamer and player.streamer.get_chunk(ChunkStreamer.chunk_of(p)) == null:
		why = "unloaded"
	elif why == "" and BuildCatalog.occupied_in(near_pieces(), _id, p, yaw):
		why = "occupied"
	elif why == "" and Game.stats.level < Recipes.unlock_level(_id):
		why = "level"
	return {"pos": p, "yaw": yaw, "ok": why == "", "why": why}

## Places the held piece at the ghost. Returns true when something was built.
func place() -> bool:
	if _id == "" or _target.is_empty():
		return false
	if not bool(Game.server_option("building", true)):
		Game.toast.emit("Building is turned off on this server")
		return false
	if not _target["ok"]:
		Game.toast.emit(why_text(String(_target.get("why", ""))))
		return false
	var pos: Vector3 = _target["pos"]
	var chunk: ChunkNode = player.streamer.get_chunk(ChunkStreamer.chunk_of(pos))
	if chunk == null:
		return false
	var it = player.held_item()
	if it == null or it["type"] != _id:
		return false
	var need := Recipes.unlock_level(_id)
	if Game.stats.level < need:
		Game.toast.emit("You can build a %s from level %d" % [String(BuildCatalog.def(_id)["name"]).to_lower(), need])
		return false
	Game.inventory.remove_at(player.selected, 1)
	# Whose it is: only they (and, on a server, their allies) may take it down.
	var st := {"by": "you", "day": snappedf(Game.day, 0.01), "owner": Doors.my_id(), "owner_name": Doors.my_name()}
	if Doors.is_door_piece(_id):
		Doors.init_state(st)
	Power.init_state(_id, st)
	var o := chunk.add_built(_id, pos - chunk.position, _target["yaw"], st)
	_forget_near()
	# A low floor put down where you stand lifts you onto it.
	var box := BuildCatalog.world_aabb(_id, pos, _target["yaw"])
	if BuildCatalog.def(_id).get("snap") == "floor" and not BuildCatalog.def(_id).get("ramp", false) and box.grow(-0.05).intersects(_body_box()):
		player.global_position.y = box.end.y + 0.02
	if BuildCatalog.def(_id).get("teleporter", false):
		var n := Game.markers.count_kind("teleporter") + 1
		var nm := "%s %d" % [String(BuildCatalog.def(_id)["name"]), n]
		o["st"]["name"] = nm
		Game.markers.add(nm, pos.x, pos.z, Game.planet, "teleporter", {"key": str(chunk.key), "i": o["i"]})
		Game.touch_player()
		Game.toast.emit("%s linked. Mark it on the Atlas, travel from any other one." % nm)
	# (ChunkNode.add_object clears the grass and flowers under the new piece.)
	return true

## Look-at panel contents while holding a piece.
func info() -> Dictionary:
	var d := BuildCatalog.def(_id)
	var lines: Array = []
	var k := func(a: String) -> String: return "[%s]" % Player._key(a)
	var mode := String(d.get("snap", "free"))
	if mode == "door":
		var fit: Array = []
		for f in d["door"]["fits"]:
			fit.append(String(BuildCatalog.def(f)["name"]).to_lower())
		lines.append("Hangs in a %s you've built. %s hangs it the other way round." % [" or ".join(fit), k.call("rotate_build")])
		lines.append("Once it's up: [%s] opens it, crouch and [%s] locks it." % [Player._key("interact"), Player._key("interact")])
		if not _target.is_empty() and not _target["ok"]:
			lines.append("No free doorway there." if _target.get("why", "") == "doorway" else "A door already hangs there, or it's out of reach.")
		return {"title": d.get("name", _id), "sub": "Building  ·  [%s] place" % Player._key("use"), "lines": lines, "icon": _id}
	if d.has("mount"):
		lines.append("Hangs from a ceiling you aim at. %s turns it." % k.call("rotate_build") if d["mount"] == "ceiling" else "Fixes to a wall you aim at.")
	elif _free:
		lines.append("Grid off: places exactly where you aim. %s turns it 15 degrees." % k.call("rotate_build"))
	else:
		match mode:
			"free": lines.append("Place anywhere. %s turns it." % k.call("rotate_build"))
			"wall": lines.append("Snaps to cell edges (%d m grid). Aim at a wall's end for the next one along, its middle to stack one on top. %s flips it." % [int(d["grid"]), k.call("rotate_build")])
			"post": lines.append("Stands on the grid corner nearest your aim, where two walls meet. %s turns it." % k.call("rotate_build"))
			"roof_v", "roof_c": lines.append("Aim at a wall top to roof the rooms beside it, or at a roof for the next one along. %s turns it." % k.call("rotate_build"))
			_:
				if d.get("ramp", false):
					lines.append("Climbs away from you from the cell you aim at, up one storey. %s turns it." % k.call("rotate_build"))
				else:
					lines.append("Snaps to a %d m grid. Aim at a floor's edge for the next tile over, at a wall for the floor above. %s turns it." % [int(d["grid"]), k.call("rotate_build")])
	if mode != "free":
		var by := ("%+.2f m" % (_lift * 0.25)) if _free else ("%+d storey" % _lift)
		lines.append("%s raise  %s lower (%s)   %s grid %s" % [k.call("build_raise"), k.call("build_lower"), by, k.call("build_snap"), "on" if _free else "off"])
	if d.has("power"):
		lines.append_array(power_lines(d["power"]))
	if d.has("station"):
		lines.append("Crafting station: recipes that need a %s work within %d m." % [d["name"], int(BuildCatalog.STATION_RANGE)])
	if not _target.is_empty() and not _target["ok"]:
		lines.append(why_text(String(_target.get("why", ""))))
	return {"title": d.get("name", _id), "sub": "Building  ·  [%s] place" % Player._key("use"), "lines": lines, "icon": _id}

## Why the ghost is red, in words.
func why_text(why: String) -> String:
	var nm := String(BuildCatalog.def(_id).get("name", _id)).to_lower()
	match why:
		"doorway": return "Hang a %s in a doorway you've built" % nm
		"ceiling": return "Aim at a ceiling to hang the %s from" % nm
		"wall": return "Aim at a wall to fix the %s to" % nm
		"door_there": return "A door already hangs there"
		"occupied": return "Something already fills that spot"
		"reach": return "Too far away: move closer"
		"unloaded": return "Can't build out there yet"
		"player": return "You're standing where it would go"
		"level": return "You can build a %s from level %d" % [nm, Recipes.unlock_level(_id)]
	return "Can't build there"

## What a powered piece does, for the look-at panel while you hold it.
static func power_lines(s: Dictionary) -> Array:
	var out: Array = []
	match String(s.get("role", "")):
		"gen":
			match String(s.get("source", "")):
				"fuel":
					var names: Array = []
					for t in (s.get("fuel", {}) as Dictionary).keys().slice(0, 4):
						names.append(String(ItemDB.def(t).get("name", t)).to_lower())
					out.append("Makes up to %s, burning %s" % [Power.watts(float(s["watts"])), ", ".join(names)])
				"wind": out.append("Makes up to %s in a fresh wind; more on high, open ground" % Power.watts(float(s["watts"])))
				"sun": out.append("Makes up to %s facing the sun (its face is the side away from you as you place it)" % Power.watts(float(s["watts"])))
		"store": out.append("Stores %s, charging or giving up to %s" % [Power.energy(float(s["store"])), Power.watts(float(s.get("rate", s["store"])))])
		"use": out.append("Draws %s" % Power.watts(float(s["watts"])))
		"switch": out.append("Cuts or joins the line through it")
		"node": out.append("Joins up to %d cables; poles carry them far" % int(s.get("links", 4)))
	out.append("String Copper Wire to it to join it to the rest (%d m a cable at most)" % int(Power.MAX_CABLE))
	return out
