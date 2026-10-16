class_name Builder
extends Node
## Placing building pieces and crafting stations. While a piece is in the selected hotbar
## slot, a see-through ghost shows where it will go: green when it fits, red when not.
## Pieces snap to a grid, and to the storeys of whatever you have already built nearby.
## Use places it; the rotate key turns it (or flips a wall). Raise and lower move it a
## storey at a time (a quarter metre with the grid off), and the grid can be switched off
## for free placement. Floors and roofs aimed at a wall sit on top of it.

const REACH := 9.0
const ANCHOR_RADIUS := 10.0

var player: Player
var _ghost: MeshInstance3D
var _id := ""
var _turn := 0
var _lift := 0
var _free := false
var _target := {}
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D

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
		_turn = (_turn + 1) % (24 if _free else 4)
	elif event.is_action_pressed("build_raise"):
		_lift += 1
	elif event.is_action_pressed("build_lower"):
		_lift -= 1
	elif event.is_action_pressed("build_snap"):
		if BuildCatalog.def(_id).get("snap") == "free":
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
	var col: Object = hit.get("collider")
	var anchor = null
	var hit_mode := ""
	var on_ground := not (col != null and col.has_meta("obj"))
	if col != null and col.has_meta("obj"):
		var c: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = c.get_object(col.get_meta("obj"))
		if BuildCatalog.is_built(o["t"]):
			hit_mode = String(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("snap", "free"))
			if hit_mode != "free":
				anchor = c.position + o["p"]
	if anchor == null:
		anchor = BuildCatalog.nearest_piece(player.streamer, p, ANCHOR_RADIUS)
	# Nudge off the surface we hit, so the cell is the one we are looking from.
	var probe := p + n * 0.05
	var s := BuildCatalog.snap(_id, probe, player.yaw(), _turn, anchor, on_ground, {"hit_mode": hit_mode, "lift": _lift, "free": _free})
	var pos: Vector3 = s["pos"]
	if anchor == null and _id == "foundation" and not _free:
		pos.y = p.y + 0.12 + _lift * float(BuildCatalog.def(_id)["storey"])
	var ok := pos.distance_to(from) <= REACH + 2.0
	if ok and BuildCatalog.occupied(player.streamer, _id, pos, s["yaw"]):
		ok = false
	if ok and BuildCatalog.def(_id).get("snap") == "free" and Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z).length() < 0.7:
		ok = false
	if ok and player.streamer and player.streamer.get_chunk(ChunkStreamer.chunk_of(pos)) == null:
		ok = false
	return {"pos": pos, "yaw": s["yaw"], "ok": ok}

## Places the held piece at the ghost. Returns true when something was built.
func place() -> bool:
	if _id == "" or _target.is_empty():
		return false
	if not _target["ok"]:
		Game.toast.emit("Can't build there")
		return false
	var pos: Vector3 = _target["pos"]
	var chunk: ChunkNode = player.streamer.get_chunk(ChunkStreamer.chunk_of(pos))
	if chunk == null:
		return false
	var it = player.held_item()
	if it == null or it["type"] != _id:
		return false
	Game.inventory.remove_at(player.selected, 1)
	var o := chunk.add_built(_id, pos - chunk.position, _target["yaw"], {"by": "you", "day": snappedf(Game.day, 0.01)})
	if BuildCatalog.def(_id).get("teleporter", false):
		var n := Game.markers.count_kind("teleporter") + 1
		var nm := "%s %d" % [String(BuildCatalog.def(_id)["name"]), n]
		o["st"]["name"] = nm
		Game.markers.add(nm, pos.x, pos.z, Game.planet, "teleporter", {"key": str(chunk.key), "i": o["i"]})
		Game.touch_player()
		Game.toast.emit("%s linked. Mark it on the Atlas, travel from any other one." % nm)
	# Clear grass and flowers growing through the new piece.
	player.streamer.refresh_grass(chunk.key)
	return true

## Look-at panel contents while holding a piece.
func info() -> Dictionary:
	var d := BuildCatalog.def(_id)
	var lines: Array = []
	var k := func(a: String) -> String: return "[%s]" % Player._key(a)
	var mode := String(d.get("snap", "free"))
	if _free:
		lines.append("Grid off: places exactly where you aim. %s turns it 15 degrees." % k.call("rotate_build"))
	else:
		match mode:
			"free": lines.append("Place anywhere. %s turns it." % k.call("rotate_build"))
			"wall": lines.append("Snaps to cell edges (%d m grid). %s flips it." % [int(d["grid"]), k.call("rotate_build")])
			_: lines.append("Snaps to a %d m grid and to storeys you've built; aim at a wall to sit on top of it. %s turns it." % [int(d["grid"]), k.call("rotate_build")])
	if mode != "free":
		var by := ("%+.2f m" % (_lift * 0.25)) if _free else ("%+d storey" % _lift)
		lines.append("%s raise  %s lower (%s)   %s grid %s" % [k.call("build_raise"), k.call("build_lower"), by, k.call("build_snap"), "on" if _free else "off"])
	if d.has("station"):
		lines.append("Crafting station: recipes that need a %s work within %d m." % [d["name"], int(BuildCatalog.STATION_RANGE)])
	if not _target.is_empty() and not _target["ok"]:
		lines.append("Something is already there, or it's out of reach.")
	return {"title": d.get("name", _id), "sub": "Building  ·  [%s] place" % Player._key("use"), "lines": lines, "icon": _id}
