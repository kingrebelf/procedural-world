class_name DungeonNode
extends Node3D
## One dungeon near you (see Dungeon). From afar only its gatehouse over the stair's
## mouth; close by, its levels block by block: stone rooms (bulkheads in a bunker),
## passages and flights, furniture, torches, and the seals and the puzzle parts that
## open them. Blocks out of sight are hidden (every level while you're up top, other
## levels than yours down below) and only the torches nearest you give light, so a deep
## dungeon costs about what the rooms around you do.
##
## The node sits at the stronghold's middle turned by its yaw, so children are placed
## in plan space (Dungeon) with world heights.

const BLOCK := 4 ## cells per side of a built block
const SEE := 46.0 ## how far blocks on your level stay drawn
const LAMPS := 10 ## torches lit at once, nearest first
const SEAL_RISE := 0.55 ## of its height per second
const PLATE_R := 0.6

const MATS := [
	{"wall": "castle_stone", "floor": "flagstone", "ceil": "castle_stone", "trim": "stone_dark", "beam": "timber", "metal": "iron", "roof": "slate", "tint": Color(1, 1, 1)},
	{"wall": "crypt_stone", "floor": "flagstone", "ceil": "crypt_stone", "trim": "stone_dark", "beam": "stone_dark", "metal": "rust", "roof": "slate", "tint": Color(0.78, 0.76, 0.74)},
	{"wall": "scifi_panels", "floor": "scifi_floor", "ceil": "panel", "trim": "metal_dark", "beam": "metal_dark", "metal": "metal_dark", "roof": "metal_dark", "tint": Color(1, 1, 1)},
]
const FIRE := Color(1.0, 0.62, 0.32)
const LAMP := Color(0.86, 0.92, 1.0)

## What stands along a room's walls, by era and kind ("@wall" hangs on the wall).
const FURN := [
	{"guard": ["props/Barrel", "props/WeaponStand", "props/Crate_Wooden", "props/Bench", "props/Shield_Wooden@wall", "props/Barrel_Holder"],
	"store": ["props/Barrel", "props/Barrel_Apples", "props/Crate_Wooden", "props/FarmCrate_Carrot", "props/Bag", "props/Crate_Wooden", "props/Pouch_Large", "props/FarmCrate_Apple"],
	"cells": ["props/Cage_Small", "props/Chain_Coil", "props/Bucket_Wooden_1", "props/Cage_Small", "props/Stool"],
	"armory": ["props/WeaponStand", "props/Anvil", "props/Peg_Rack@wall", "props/Crate_Metal", "props/WeaponStand", "props/Whetstone", "props/Shield_Wooden@wall"],
	"library": ["props/Bookcase_2", "props/Bookcase_2", "props/BookStand", "props/Shelf_Arch", "props/Bookcase_2", "props/Book_Stack_1"],
	"crypt": ["props/Vase_2", "props/Vase_4", "props/CandleStick_Stand", "props/Vase_Rubble_Medium"],
	"hall": ["props/Banner_1@wall", "props/Barrel", "props/Banner_2@wall", "props/WeaponStand", "props/CandleStick_Stand"],
	"vault": ["props/Coin_Pile", "props/Chalice", "props/Crate_Metal", "props/Coin_Pile"],
	"entry": ["props/Barrel", "props/Crate_Wooden", "props/Bucket_Wooden_1"],
	"landing": ["props/Barrel", "props/Crate_Wooden"]},
	{"ossuary": ["props/Vase_Rubble_Medium", "props/Vase_2", "props/Pot_1", "props/Vase_4", "props/Chain_Coil"],
	"chapel": ["props/CandleStick_Stand", "props/Banner_2@wall", "props/Vase_2", "props/CandleStick_Stand"],
	"cells": ["props/Cage_Small", "props/Chain_Coil", "props/Bucket_Metal", "props/Cage_Small"],
	"library": ["props/Bookcase_2", "props/BookStand", "props/Bookcase_2", "props/Book_Stack_1"],
	"store": ["props/Vase_2", "props/Barrel", "props/Crate_Wooden", "props/Pot_1", "props/Vase_Rubble_Medium"],
	"crypt": ["props/Vase_2", "props/Vase_4", "props/CandleStick_Stand", "props/Vase_Rubble_Medium"],
	"hall": ["props/Banner_2@wall", "props/CandleStick_Stand", "props/Vase_2", "props/Banner_2@wall"],
	"vault": ["props/Coin_Pile", "props/Chalice", "props/Vase_4", "props/Coin_Pile"],
	"entry": ["props/Vase_Rubble_Medium", "props/Vase_2"],
	"landing": ["props/Vase_Rubble_Medium"]},
	{"barracks": ["@bunk", "@locker", "@locker", "@bunk", "@locker"],
	"control": ["@console", "scifi/Prop_Computer", "@console", "@screen@wall"],
	"store": ["scifi/Prop_Crate3", "scifi/Prop_Crate4", "scifi/Prop_Barrel_Large", "scifi/Prop_Crate3"],
	"lab": ["@tank", "@desk", "@tank", "scifi/Prop_Computer"],
	"armory": ["@rack", "@rack", "scifi/Prop_Crate4", "@locker"],
	"hall": ["scifi/Prop_Crate4", "@locker", "scifi/Prop_Barrel_Large"],
	"vault": ["scifi/Prop_Crate4", "scifi/Prop_Crate3", "scifi/Prop_Crate4"],
	"entry": ["scifi/Prop_Crate3", "scifi/Prop_Barrel_Large"],
	"landing": ["scifi/Prop_Crate3"]},
]
## In the middle of a room's cells.
const MIDDLE := [
	{"guard": ["props/Table_Large"], "hall": ["props/Table_Large"], "crypt": ["@tomb"], "library": ["props/Table_Large"]},
	{"ossuary": ["@tomb"], "crypt": ["@tomb"], "chapel": ["@tomb"]},
	{"barracks": ["@table"], "lab": ["@holo"], "control": ["@holo"], "hall": ["@table"]},
]
## Wall hangings' height.
const HANG := {"props/Banner_1": 2.05, "props/Banner_2": 2.05, "props/Shield_Wooden": 1.75, "props/Peg_Rack": 1.5, "@screen": 1.8}

var pl: Dictionary
var streamer: ChunkStreamer
var player: Node3D
var deep := false

var _era := 0
var _m: Dictionary
var _queue: Array = [] ## blocks still to build: [lv, bx, bz]
var _blocks: Array = [] ## {"lv", "rect": Rect2 (plan), "mi", "stair": [levels it shows from]}
var _lamps: Array = [] ## {"p": plan point, "lv", "node", "light"}
var _seals: Array = [] ## per lock: {"node", "body", "amt", "h"}
var _parts: Array = [] ## per part: {"node", "moving" (Node3D), "lamp"}
var _notes: Array = [] ## per note: plan point of its face
var _local := {} ## the state while the centre chunk isn't loaded
var _tick := 0.0
var _player_lv := -2 ## -1 up top in the gatehouse or on the entrance flight, -2 elsewhere
var _last_y := 0.0
var _cue_t := -1000.0
var _entered := false
var _chests := Vector2i.ZERO ## opened, of
var _chest_t := 0.0
var _aabbs := {}
var _flow := {}
var _flow_key := ""

func setup(p: Dictionary, s: ChunkStreamer, who: Node3D) -> void:
	pl = p
	streamer = s
	player = who
	_era = int(pl["era"])
	_m = MATS[_era]
	name = "Dungeon_" + String(pl["id"])
	position = Vector3((pl["c"] as Vector2).x, 0, (pl["c"] as Vector2).y)
	rotation.y = float(pl["yaw"])
	_build_shell()

# --- State ----------------------------------------------------------------------------

func _chunk() -> ChunkNode:
	return streamer.get_chunk(pl["chunk"]) if streamer != null else null

func state() -> Dictionary:
	var cn := _chunk()
	if cn == null:
		return _local
	var d = cn.data.get("dgn")
	if not d is Dictionary:
		d = {"id": pl["id"]}
		cn.data["dgn"] = d
	for k in _local:
		if not d.has(k):
			d[k] = _local[k]
	_local = {}
	return d

func _mark(group: String, key: int) -> void:
	var st := state()
	if not st.has(group):
		st[group] = {}
	st[group][str(key)] = true
	var cn := _chunk()
	if cn != null:
		Game.mark_chunk_dirty(cn.data)

func _is(group: String, key: int) -> bool:
	var st := state()
	return st.has(group) and (st[group] as Dictionary).has(str(key))

func seal_open(li: int) -> bool:
	return _is("open", li)

# --- Building ---------------------------------------------------------------------------

## Builds the levels: all at once (you're already down there) or a block a frame.
func set_deep(on: bool, now := false) -> void:
	if on and not deep:
		deep = true
		Dungeon.active[pl["id"]] = {"pl": pl, "node": self}
		var n: int = pl["n"]
		var nb := int(ceil(n / float(BLOCK)))
		for lv in pl["levels"].size():
			for bz in nb:
				for bx in nb:
					_queue.append([lv, bx, bz])
		_build_parts()
	elif not on and deep:
		deep = false
		Dungeon.active.erase(pl["id"])
		_queue.clear()
		for b in _blocks:
			b["mi"].queue_free()
			b["body"].queue_free()
		_blocks.clear()
		for l in _lamps.duplicate():
			if int(l["lv"]) >= 0:
				l["node"].queue_free()
				_lamps.erase(l)
		for s in _seals:
			s["node"].queue_free()
		_seals.clear()
		for p in _parts:
			p["node"].queue_free()
		_parts.clear()
		_notes.clear()
	if now:
		while not _queue.is_empty():
			var q: Array = _queue.pop_front()
			_build_block(q[0], q[1], q[2])

## Where a guard at `from` should head to get at `to` by the passages: the middle of the
## next cell on the way (at its floor), `to` itself once in the same cell, or INF when
## there's no way through (a shut seal between you).
func toward(from: Vector3, to: Vector3) -> Vector3:
	var qt := Dungeon.to_plan(pl, to)
	var ct := Dungeon.cell_at(pl, Vector2(qt.x, qt.z))
	var at := Dungeon._walk_cell(pl, Dungeon.level_near(pl, qt.y), ct)
	if at.is_empty():
		return Vector3.INF
	var key := Dungeon._key(at[0], ct)
	if key != _flow_key:
		_flow_key = key
		_flow = Dungeon.flow(pl, at[0], ct, seal_open)
	var qf := Dungeon.to_plan(pl, from)
	var cf := Dungeon.cell_at(pl, Vector2(qf.x, qf.z))
	var af := Dungeon._walk_cell(pl, Dungeon.level_near(pl, qf.y), cf)
	if af.is_empty() or not _flow.has(Dungeon._key(af[0], cf)):
		return Vector3.INF
	if Dungeon._key(af[0], cf) == key:
		return to
	var best := Vector3.INF
	var best_s: int = _flow[Dungeon._key(af[0], cf)]
	for nx in Dungeon.links(pl, af[0], cf, seal_open):
		var s: int = _flow.get(Dungeon._key(nx[0], nx[1]), 1 << 30)
		if s < best_s:
			best_s = s
			var m := Dungeon.centre(pl, nx[1])
			best = Dungeon.to_world(pl, Vector3(m.x, qf.y, m.y))
	return best

func _exit_tree() -> void:
	if deep:
		Dungeon.active.erase(pl["id"])

## Where a plan point is in this node's space.
static func _v(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, q.y)

## A box in `k`, solid too when `boxes` is given: [transform, size].
static func _box(k: MeshKit, boxes, mat: String, xf: Transform3D, size: Vector3, col := Color.WHITE) -> void:
	k.box(mat, xf, size, col)
	if boxes != null:
		boxes.append([xf, size])

## The basis that turns a box's z along dv (x across it), plan direction.
static func _face(dv: Vector2) -> Basis:
	return Basis(Vector3(dv.y, 0, -dv.x), Vector3.UP, Vector3(dv.x, 0, dv.y))

func _body(boxes: Array) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.set_meta("dungeon", pl["id"])
	for e in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = e[1]
		cs.shape = sh
		cs.transform = e[0]
		b.add_child(cs)
	return b

func _mesh_node(k: MeshKit, models: Array, range_end := 0.0) -> MeshInstance3D:
	var mesh := BuildCatalog.merge_models(models) if not models.is_empty() else ArrayMesh.new()
	k.commit(Materials.get_mat, mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	return mi

func _build_block(lv: int, bx: int, bz: int) -> void:
	var n: int = pl["n"]
	var k := MeshKit.new(WHash.combine(WHash.str_hash(pl["id"]), lv * 4099 + bx * 61 + bz) & 0xFFFF)
	var models: Array = []
	var boxes: Array = []
	var any := false
	var shows := [lv]
	for j in range(bz * BLOCK, mini((bz + 1) * BLOCK, n)):
		for i in range(bx * BLOCK, mini((bx + 1) * BLOCK, n)):
			var c := Vector2i(i, j)
			match Dungeon.kind(pl, lv, c):
				Dungeon.ROOM:
					_room_cell(lv, c, k, models, boxes)
					any = true
				Dungeon.CORR:
					_corr_cell(lv, c, k, models, boxes)
					any = true
				Dungeon.STAIR:
					var d := Dungeon.stair_dir(pl, lv, c)
					if Dungeon.kind(pl, lv, c - Dungeon.DIRS[d]) != Dungeon.STAIR:
						_flight(c, d, Dungeon.floor_y(pl, lv), Dungeon.floor_y(pl, lv + 1), false, k, boxes)
					shows = [lv, lv + 1]
					any = true
				Dungeon.ENTRY:
					if Dungeon.kind(pl, lv, c - Dungeon.DIRS[3]) != Dungeon.ENTRY:
						_flight(c, 3, float(pl["y0"]), Dungeon.floor_y(pl, 0), true, k, boxes)
					shows = [-1, 0]
					any = true
	if not any:
		return
	_furnish_block(lv, Rect2i(bx * BLOCK, bz * BLOCK, BLOCK, BLOCK), k, models, boxes)
	var mi := _mesh_node(k, models)
	mi.name = "Block_%d_%d_%d" % [lv, bx, bz]
	mi.visible = false
	add_child(mi)
	var body := _body(boxes)
	add_child(body)
	var lo := Dungeon.centre(pl, Vector2i(bx * BLOCK, bz * BLOCK)) - Vector2.ONE * Dungeon.CELL * 0.5
	_blocks.append({"lv": lv, "rect": Rect2(lo, Vector2.ONE * Dungeon.CELL * BLOCK), "mi": mi, "body": body, "shows": shows})

## One cell of a room: floor, ceiling, walls where the room ends (doorways where a way
## leads out), a plinth along their feet, beams under the ceiling and, in a great hall,
## pillars where four cells meet.
func _room_cell(lv: int, c: Vector2i, k: MeshKit, models: Array, boxes: Array) -> void:
	var ri := Dungeon.room_of(pl, lv, c)
	var rm: Dictionary = pl["rooms"][ri]
	var h: float = rm["h"]
	var fy := Dungeon.floor_y(pl, lv)
	var cc := Dungeon.centre(pl, c)
	var I := Basis.IDENTITY
	var cell := Dungeon.CELL
	var tint: Color = _m["tint"]
	_box(k, boxes, _m["floor"], Transform3D(I, _v(cc, fy - 0.15)), Vector3(cell, 0.3, cell), tint)
	_box(k, boxes, _m["ceil"], Transform3D(I, _v(cc, fy + h + 0.15)), Vector3(cell, 0.3, cell), tint)
	var long_x := int(rm["w"]) >= int(rm["d"])
	for d in 4:
		var dv := Vector2(Dungeon.DIRS[d])
		var b := _face(dv)
		var e := cc + dv * cell * 0.5
		if Dungeon.room_of(pl, lv, c + Dungeon.DIRS[d]) == ri:
			# Inside the room: a beam across the ceiling at the cell's edge, along the short way.
			if (d == 0 and long_x) or (d == 1 and not long_x):
				_box(k, null, _m["beam"], Transform3D(b, _v(e, fy + h - 0.2)), Vector3(cell, 0.34, 0.3), tint)
			continue
		var top := fy + h + 0.3
		var di := Dungeon.door_at(pl, lv, c, d)
		if di >= 0:
			var hw := Dungeon.STAIR_W * 0.5 if pl["doors"][di]["stair"] else Dungeon.DOOR_HALF
			_doorway(k, boxes, e, dv, fy, top, hw, Dungeon.WALL)
		else:
			_box(k, boxes, _m["wall"], Transform3D(b, _v(e, (fy + top) * 0.5)), Vector3(cell + Dungeon.WALL, top - fy, Dungeon.WALL), tint)
			_wall_dress(k, e - dv * Dungeon.WALL * 0.5, dv, cell - Dungeon.WALL, fy, h)
	# Pillars where four of a great room's cells meet (only the cell to their -x, -z
	# side builds each).
	if rm["w"] >= 3 and rm["d"] >= 3:
		var q := c + Vector2i(1, 1)
		if Dungeon.room_of(pl, lv, c + Vector2i(1, 0)) == ri and Dungeon.room_of(pl, lv, c + Vector2i(0, 1)) == ri and Dungeon.room_of(pl, lv, q) == ri:
			var at := cc + Vector2.ONE * cell * 0.5
			_box(k, boxes, _m["wall"], Transform3D(I, _v(at, fy + h * 0.5)), Vector3(0.62, h, 0.62), tint)
			_box(k, null, _m["trim"], Transform3D(I, _v(at, fy + 0.15)), Vector3(0.82, 0.3, 0.82))
			_box(k, null, _m["trim"], Transform3D(I, _v(at, fy + h - 0.14)), Vector3(0.8, 0.28, 0.8))

## A wall's foot: a plinth, and damp and moss creeping up stone walls.
func _wall_dress(k: MeshKit, face: Vector2, dv: Vector2, w: float, fy: float, h: float) -> void:
	var b := _face(dv)
	_box(k, null, _m["trim"], Transform3D(b, _v(face - dv * 0.04, fy + 0.09)), Vector3(w, 0.18, 0.08))
	if _era != Eras.SCIFI:
		var inward := Basis(Vector3.UP, atan2(-dv.x, -dv.y))
		k.card("weathering", Transform3D.IDENTITY, _v(face - dv * 0.02, fy + 0.9), inward, w, 1.8, Vector3.ZERO, Color(1, 1, 1, 1))
	else:
		_box(k, null, "hazard", Transform3D(b, _v(face - dv * 0.03, fy + 0.25)), Vector3(w, 0.1, 0.04))
		_box(k, null, "metal_dark", Transform3D(b, _v(face - dv * 0.05, fy + h - 0.35)), Vector3(w, 0.12, 0.1))

## A wall with a doorway `hw` half wide through it at edge point e, its face toward -dv
## inside: jambs, a lintel, a round head filled in above (stone) or a frame (bunker).
func _doorway(k: MeshKit, boxes: Array, e: Vector2, dv: Vector2, fy: float, top: float, hw: float, thick: float) -> void:
	var b := _face(dv)
	var across := Vector2(dv.y, -dv.x)
	var cell := Dungeon.CELL
	var jl := (cell + Dungeon.WALL) * 0.5 - hw
	var tint: Color = _m["tint"]
	for s: float in [-1.0, 1.0]:
		_box(k, boxes, _m["wall"], Transform3D(b, _v(e + across * s * (hw + jl * 0.5), (fy + top) * 0.5)), Vector3(jl, top - fy, thick), tint)
	var dh := Dungeon.DOOR_H
	_box(k, boxes, _m["wall"], Transform3D(b, _v(e, (fy + dh + top) * 0.5)), Vector3(hw * 2.0 + 0.02, top - fy - dh, thick), tint)
	if _era == Eras.SCIFI:
		for s: float in [-1.0, 1.0]:
			for f: float in [-1.0, 1.0]:
				_box(k, null, "metal_dark", Transform3D(b, _v(e + across * s * (hw + 0.08) + dv * f * (thick * 0.5 + 0.03), fy + dh * 0.5)), Vector3(0.16, dh, 0.06))
				_box(k, null, "hazard", Transform3D(b, _v(e + across * s * (hw + 0.08) + dv * f * (thick * 0.5 + 0.065), fy + 0.6)), Vector3(0.16, 1.0, 0.01))
		for f: float in [-1.0, 1.0]:
			_box(k, null, "metal_dark", Transform3D(b, _v(e + dv * f * (thick * 0.5 + 0.03), fy + dh + 0.06)), Vector3(hw * 2.0 + 0.32, 0.14, 0.06))
		return
	# The round head: the opening's top corners filled in down to a half circle, and a
	# ring of voussoirs proud of both faces.
	var spring := dh - hw
	var slices := 10
	for i in slices:
		var xm := -hw + hw * 2.0 * (i + 0.5) / slices
		var ya := spring + sqrt(maxf(0.0, hw * hw - xm * xm))
		if dh - ya > 0.01:
			_box(k, null, _m["wall"], Transform3D(b, _v(e + across * xm, fy + (ya + dh) * 0.5)), Vector3(hw * 2.0 / slices + 0.012, dh - ya, thick), tint)
	for f: float in [-1.0, 1.0]:
		for i in 9:
			var a := PI * (i + 0.5) / 9.0
			var at := e + across * cos(a) * (hw + 0.13) + dv * f * (thick * 0.5 + 0.03)
			var vb := b * Basis(Vector3(0, 0, 1), a - PI * 0.5)
			k.box(_m["trim"], Transform3D(vb, _v(at, fy + spring + sin(a) * (hw + 0.13))), Vector3(0.34, 0.26, 0.06))
		for s: float in [-1.0, 1.0]:
			_box(k, null, _m["trim"], Transform3D(b, _v(e + across * s * (hw + 0.12) + dv * f * (thick * 0.5 + 0.03), fy + spring * 0.5)), Vector3(0.24, spring, 0.06))

## One passage cell: 2.4 m wide from its middle out to each way it opens, walled in,
## with a rib (two pilasters and a lintel) where it passes into the next cell.
func _corr_cell(lv: int, c: Vector2i, k: MeshKit, models: Array, boxes: Array) -> void:
	var fy := Dungeon.floor_y(pl, lv)
	var cc := Dungeon.centre(pl, c)
	var cell := Dungeon.CELL
	var ch := Dungeon.CORR_H
	var hw := Dungeon.CORR_HALF
	var tint: Color = _m["tint"]
	_box(k, boxes, _m["floor"], Transform3D(Basis.IDENTITY, _v(cc, fy - 0.15)), Vector3(cell, 0.3, cell), tint)
	_box(k, boxes, _m["ceil"], Transform3D(Basis.IDENTITY, _v(cc, fy + ch + 0.15)), Vector3(cell, 0.3, cell), tint)
	for d in 4:
		var dv := Vector2(Dungeon.DIRS[d])
		var across := Vector2(dv.y, -dv.x)
		var b := _face(dv)
		if Dungeon.is_open(pl, lv, c, d):
			var mid := (hw + cell * 0.5) * 0.5
			for s: float in [-1.0, 1.0]:
				_box(k, boxes, _m["wall"], Transform3D(b, _v(cc + dv * mid + across * s * (hw + 0.15), fy + (ch + 0.3) * 0.5)), Vector3(0.3, ch + 0.3, cell * 0.5 - hw), tint)
				var inner := cc + dv * mid + across * s * hw
				_box(k, null, _m["trim"], Transform3D(_face(-across * s), _v(inner, fy + 0.09)), Vector3(cell * 0.5 - hw, 0.18, 0.08))
			var nk := Dungeon.kind(pl, lv, c + Dungeon.DIRS[d])
			if nk == Dungeon.CORR and d < 2:
				var at := cc + dv * cell * 0.5
				for s: float in [-1.0, 1.0]:
					_box(k, null, _m["trim"], Transform3D(b, _v(at + across * s * (hw - 0.1), fy + ch * 0.5)), Vector3(0.22, ch, 0.3))
				_box(k, null, _m["beam"], Transform3D(b, _v(at, fy + ch - 0.14)), Vector3(hw * 2.0, 0.28, 0.32), tint)
		else:
			_box(k, boxes, _m["wall"], Transform3D(b, _v(cc + dv * (hw + 0.15), fy + (ch + 0.3) * 0.5)), Vector3(hw * 2.0 + 0.6, ch + 0.3, 0.3), tint)
			_wall_dress(k, cc + dv * hw, dv, hw * 2.0, fy, ch)

## A flight of stairs from cell c heading d, from height hi at its top edge down to lo
## RUN cells on: treads (and a smooth ramp to walk on), walls each side and a sloping
## ceiling. The entrance flight is open to the gatehouse over its top part.
func _flight(c: Vector2i, d: int, hi: float, lo: float, entrance: bool, k: MeshKit, boxes: Array) -> void:
	var dv := Vector2(Dungeon.DIRS[d])
	var across := Vector2(dv.y, -dv.x)
	var b := _face(dv)
	var L := Dungeon.RUN * Dungeon.CELL
	var start := Dungeon.centre(pl, c) - dv * Dungeon.CELL * 0.5
	var drop := hi - lo
	var steps := maxi(4, roundi(drop / 0.25))
	var run := L / steps
	var rise := drop / steps
	var w := Dungeon.STAIR_W
	var tint: Color = _m["tint"]
	for j in steps:
		var ty := hi - (j + 0.5) * rise
		_box(k, null, _m["floor"] if _era == Eras.SCIFI else _m["trim"], Transform3D(b, _v(start + dv * (j + 0.5) * run, ty - 0.2)), Vector3(w, 0.4, run + 0.01), tint)
		if _era == Eras.SCIFI:
			_box(k, null, "hazard", Transform3D(b, _v(start + dv * ((j + 1) * run - 0.04), ty + 0.005)), Vector3(w - 0.1, 0.012, 0.06))
	# Walk on a ramp along the nosings, not the treads' edges.
	var slope := Vector3(dv.x * L, -drop, dv.y * L)
	var z := slope.normalized()
	var x := Vector3(across.x, 0, across.y)
	var y := z.cross(x)
	var rb := Basis(x, y, z)
	var mid := _v(start + dv * L * 0.5, (hi + lo) * 0.5)
	boxes.append([Transform3D(rb, mid - y * 0.1), Vector3(w, 0.2, slope.length())])
	var wall_top := float(pl["y0"]) if entrance else hi + 3.3
	for s: float in [-1.0, 1.0]:
		_box(k, boxes, _m["wall"], Transform3D(b, _v(start + dv * L * 0.5 + across * s * (w * 0.5 + 0.15), (lo - 0.4 + wall_top) * 0.5)), Vector3(0.3, wall_top - lo + 0.4, L + 0.3), tint)
		_box(k, null, _m["trim"], Transform3D(rb, mid + Vector3(across.x, 0, across.y) * s * (w * 0.5 - 0.06) + y * 0.95), Vector3(0.1, 0.07, slope.length()))
	var a0 := 0.0
	if entrance:
		# The ceiling starts where the flight has gone under the courtyard.
		a0 = (hi + 3.3 - float(pl["y0"])) / (drop / L)
		var ya := hi - drop * a0 / L + 3.0
		_box(k, boxes, _m["wall"], Transform3D(b, _v(start + dv * (a0 - 0.15), (ya + float(pl["y0"])) * 0.5)), Vector3(w + 0.6, float(pl["y0"]) + 0.05 - ya, 0.3), tint)
	var cl := L - a0
	var cmid := _v(start + dv * (a0 + cl * 0.5), hi - drop * (a0 + cl * 0.5) / L + 3.0)
	_box(k, boxes, _m["ceil"], Transform3D(rb, cmid + y * 0.15), Vector3(w + 0.6, 0.3, cl * slope.length() / L), tint)
	var ribs := 3
	for i in ribs:
		var t := a0 + cl * (i + 0.5) / ribs
		_box(k, null, _m["beam"], Transform3D(b, _v(start + dv * t, hi - drop * t / L + 2.86)), Vector3(w, 0.28, 0.3), tint)

## Furniture along the walls and in the middle of the rooms whose spots fall in this
## block, and the torches on its walls.
func _furnish_block(lv: int, cells: Rect2i, k: MeshKit, models: Array, boxes: Array) -> void:
	var lo := Dungeon.centre(pl, cells.position) - Vector2.ONE * Dungeon.CELL * 0.5
	var area := Rect2(lo, Vector2(cells.size) * Dungeon.CELL)
	var taken: Array = [] # plan points other things already stand at
	for p in pl["parts"]:
		taken.append(Vector2(p["p"].x, p["p"].z))
	for it in pl["loot"]:
		taken.append(Vector2(it["p"].x, it["p"].z))
	for ri in pl["rooms"].size():
		var rm: Dictionary = pl["rooms"][ri]
		if int(rm["lv"]) != lv or rm["kind"] == "gone":
			continue
		var r := WHash.rng(WHash.str_hash(pl["id"]), ri, lv, 953)
		var list: Array = FURN[_era].get(rm["kind"], [])
		var ss := Dungeon.slots(pl, ri)
		var used: Dictionary = rm["used"]
		var pick := r.randi()
		for si in ss.size():
			var s: Dictionary = ss[si]
			var on := r.randf() < 0.62
			if used.has(si) or list.is_empty() or not on:
				continue
			var p: Vector3 = s["w"]
			if not area.has_point(Vector2(p.x, p.z)):
				continue
			var name: String = list[pick % list.size()]
			pick += 1
			_place(name, s, k, models, boxes)
		var mids: Array = MIDDLE[_era].get(rm["kind"], [])
		if mids.is_empty():
			continue
		var cs := Dungeon._cells(rm)
		for ci in cs.size():
			var q: Vector2i = cs[ci]
			var at := Dungeon.centre(pl, q)
			if not area.has_point(at) or (ci + ri) % 2 == 1:
				continue
			var clear := true
			for t in taken:
				if (t as Vector2).distance_to(at) < 1.8:
					clear = false
			if not clear:
				continue
			var name: String = mids[ci % mids.size()]
			var yaw := 90.0 if int(rm["w"]) >= int(rm["d"]) else 0.0
			_place_at(name, Vector3(at.x, Dungeon.floor_y(pl, lv), at.y), yaw, k, models, boxes)
			if name == "props/Table_Large":
				for sgn: float in [-1.0, 1.0]:
					var off := Vector2(0, sgn) if yaw == 90.0 else Vector2(sgn, 0)
					_place_at("props/Bench", Vector3(at.x + off.x, Dungeon.floor_y(pl, lv), at.y + off.y), yaw, k, models, null)
				if rm["kind"] == "hall":
					models.append(["props/Chandelier", 0, Vector3(at.x, Dungeon.floor_y(pl, lv) + float(rm["h"]), at.y), 1.0])
				else:
					models.append(["props/CandleStick_Triple", 0, Vector3(at.x, Dungeon.floor_y(pl, lv) + 0.818, at.y), 1.0])
	for l in pl["lights"]:
		if int(l["lv"]) != lv:
			continue
		var p: Vector3 = l["p"]
		if not area.has_point(Vector2(p.x, p.z)):
			continue
		var yaw := float(l["yaw"])
		if _era == Eras.SCIFI:
			var dv := Vector2(-sin(yaw), -cos(yaw)) # back toward the wall
			var at := Vector2(p.x, p.z) - dv * 0.06
			k.box("metal_dark", Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, p.y + 2.55, at.y)), Vector3(0.9, 0.1, 0.12))
			k.box("glow_white", Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, p.y + 2.49, at.y)), Vector3(0.8, 0.03, 0.08))
		else:
			models.append(["props/Torch_Metal", rad_to_deg(yaw), p + Vector3(0, 1.9, 0), 1.0])

## Furniture at a wall spot: standing against the wall, or hung on it.
func _place(name: String, s: Dictionary, k: MeshKit, models: Array, boxes: Array) -> void:
	var yaw: float = s["yaw"]
	var into := Vector3(sin(yaw), 0, cos(yaw))
	var w: Vector3 = s["w"]
	if name.ends_with("@wall"):
		var m := name.trim_suffix("@wall")
		var at := w + into * 0.03 + Vector3(0, float(HANG.get(m, 1.6)), 0)
		if m.begins_with("@"):
			Interiors._piece(m, k, models, Transform3D(Basis(Vector3.UP, yaw), at))
		else:
			models.append([m, rad_to_deg(yaw), at, 1.0])
		return
	var depth := _depth_of(name)
	_place_at(name, w + into * (depth * 0.5 + 0.04), rad_to_deg(yaw), k, models, boxes)

func _place_at(name: String, at: Vector3, yaw_deg: float, k: MeshKit, models: Array, boxes) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	if name.begins_with("@"):
		Interiors._piece(name, k, models, Transform3D(b, at))
		var sz: Vector3 = Interiors.PIECES.get(name, Vector3(1, 1, 1))
		if boxes != null:
			boxes.append([Transform3D(b, at + Vector3(0, sz.y * 0.5, 0)), sz])
		return
	models.append([name, yaw_deg, at, 1.0])
	var bb := _aabb_of(name)
	if boxes != null and bb.size.y > 0.5 and bb.size.x * bb.size.z > 0.12:
		boxes.append([Transform3D(b, at + b * bb.get_center()), bb.size])

func _depth_of(name: String) -> float:
	if name.begins_with("@"):
		return float((Interiors.PIECES.get(name, Vector3(1, 1, 0.6)) as Vector3).z)
	return clampf(_aabb_of(name).size.z, 0.2, 1.4)

## A kit model's bounds in its own space.
func _aabb_of(name: String) -> AABB:
	if _aabbs.has(name):
		return _aabbs[name]
	var box := AABB()
	var first := true
	for part in BuildCatalog.model_parts(name):
		var arr: Array = part[1]
		var xf: Transform3D = part[2] if part.size() > 2 and part[2] is Transform3D else Transform3D.IDENTITY
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in vs:
			var p := xf * v
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	_aabbs[name] = box
	return box

# --- The gatehouse --------------------------------------------------------------------

## The house over the stair's mouth in the courtyard: walls, an arched way in toward the
## gate, a floor round the opening with a parapet along it, a roof with crow-stepped
## gables (a flat one with a railing on a bunker), torches by the door.
func _build_shell() -> void:
	var k := MeshKit.new(WHash.str_hash(pl["id"] + "gate") & 0xFFFF)
	var models: Array = []
	var boxes: Array = []
	var g := Dungeon.gatehouse(pl)
	var m := Dungeon.mouth(pl)
	var y0: float = pl["y0"]
	var t := 0.45
	var H := 3.6
	var base := y0 - 1.2
	var I := Basis.IDENTITY
	var wall: String = _m["wall"]
	var tint: Color = _m["tint"]
	# Side and back walls.
	for sx: float in [g.position.x + t * 0.5, g.end.x - t * 0.5]:
		_box(k, boxes, wall, Transform3D(I, Vector3(sx, (base + y0 + H) * 0.5, g.get_center().y)), Vector3(t, y0 + H - base, g.size.y), tint)
	_box(k, boxes, wall, Transform3D(I, Vector3(g.get_center().x, (base + y0 + H) * 0.5, g.position.y + t * 0.5)), Vector3(g.size.x, y0 + H - base, t), tint)
	# The front, with the way in.
	var fz := g.end.y - t * 0.5
	var ow := 1.3
	var oh := 2.9
	var jl := (g.size.x * 0.5 - ow)
	for s: float in [-1.0, 1.0]:
		_box(k, boxes, wall, Transform3D(I, Vector3(m.x + s * (ow + jl * 0.5), (base + y0 + H) * 0.5, fz)), Vector3(jl, y0 + H - base, t), tint)
	_box(k, boxes, wall, Transform3D(I, Vector3(m.x, (y0 + oh + y0 + H) * 0.5, fz)), Vector3(ow * 2.0 + 0.02, H - oh, t), tint)
	var fb := _face(Vector2(0, 1))
	if _era != Eras.SCIFI:
		var spring := oh - ow
		for i in 12:
			var xm := -ow + ow * 2.0 * (i + 0.5) / 12.0
			var ya := spring + sqrt(maxf(0.0, ow * ow - xm * xm))
			if oh - ya > 0.01:
				k.box(wall, Transform3D(I, Vector3(m.x + xm, y0 + (ya + oh) * 0.5, fz)), Vector3(ow * 2.0 / 12.0 + 0.012, oh - ya, t), tint)
		for i in 11:
			var a := PI * (i + 0.5) / 11.0
			k.box(_m["trim"], Transform3D(Basis(Vector3(0, 0, 1), a - PI * 0.5), Vector3(m.x + cos(a) * (ow + 0.15), y0 + spring + sin(a) * (ow + 0.15), fz + t * 0.5 + 0.04)), Vector3(0.38, 0.3, 0.08))
		k.box(_m["trim"], Transform3D(I, Vector3(m.x, y0 + H - 0.2, fz + t * 0.5 + 0.05)), Vector3(g.size.x + 0.1, 0.18, 0.1))
	else:
		for s: float in [-1.0, 1.0]:
			k.box("metal_dark", Transform3D(I, Vector3(m.x + s * (ow + 0.1), y0 + oh * 0.5, fz + t * 0.5 + 0.04)), Vector3(0.2, oh, 0.08))
			k.box("hazard", Transform3D(I, Vector3(m.x + s * (ow + 0.1), y0 + 0.7, fz + t * 0.5 + 0.085)), Vector3(0.2, 1.2, 0.01))
		k.box("metal_dark", Transform3D(I, Vector3(m.x, y0 + oh + 0.1, fz + t * 0.5 + 0.04)), Vector3(ow * 2.0 + 0.4, 0.2, 0.08))
		k.box("hazard", Transform3D(I, Vector3(m.x, y0 + oh + 0.1, fz + t * 0.5 + 0.085)), Vector3(ow * 2.0 + 0.3, 0.12, 0.01))
	# Floor round the opening (the flight's walls rise to meet it), and the parapet.
	var ix0 := g.position.x + t
	var ix1 := g.end.x - t
	var iz0 := g.position.y + t
	var iz1 := g.end.y - t
	var ox0 := m.x - Dungeon.STAIR_W * 0.5 - 0.3
	var ox1 := m.x + Dungeon.STAIR_W * 0.5 + 0.3
	var oz0 := m.y - 4.4
	var floor_mat: String = _m["floor"]
	for r: Rect2 in [Rect2(ix0, iz0, ox0 - ix0, iz1 - iz0), Rect2(ox1, iz0, ix1 - ox1, iz1 - iz0),
			Rect2(ox0, m.y, ox1 - ox0, iz1 - m.y), Rect2(ox0, iz0, ox1 - ox0, oz0 - iz0)]:
		if r.size.x > 0.01 and r.size.y > 0.01:
			_box(k, boxes, floor_mat, Transform3D(I, Vector3(r.get_center().x, y0 - 0.18, r.get_center().y)), Vector3(r.size.x, 0.4, r.size.y), tint)
	var pm: String = _m["trim"]
	for s: float in [-1.0, 1.0]:
		var px := m.x + s * (Dungeon.STAIR_W * 0.5 + 0.15)
		_box(k, boxes, wall, Transform3D(I, Vector3(px, y0 + 0.45, (oz0 + m.y - 0.3) * 0.5)), Vector3(0.3, 0.9, m.y - 0.3 - oz0), tint)
		k.box(pm, Transform3D(I, Vector3(px, y0 + 0.94, (oz0 + m.y - 0.3) * 0.5)), Vector3(0.38, 0.08, m.y - 0.3 - oz0 + 0.06))
	_box(k, boxes, wall, Transform3D(I, Vector3(m.x, y0 + 0.45, oz0 - 0.15)), Vector3(Dungeon.STAIR_W + 0.6, 0.9, 0.3), tint)
	k.box(pm, Transform3D(I, Vector3(m.x, y0 + 0.94, oz0 - 0.15)), Vector3(Dungeon.STAIR_W + 0.66, 0.08, 0.38))
	# The roof.
	var gc := g.get_center()
	if _era != Eras.SCIFI:
		var span := g.size.x * 0.5 + 0.35
		var pitch := deg_to_rad(38.0)
		var rise := tan(pitch) * span
		for s: float in [-1.0, 1.0]:
			var rb := Basis(Vector3(0, 0, 1), -s * pitch)
			_box(k, boxes, _m["roof"], Transform3D(rb, Vector3(gc.x + s * span * 0.5, y0 + H + rise * 0.5 + 0.1, gc.y)), Vector3(span / cos(pitch) + 0.1, 0.14, g.size.y + 0.6))
		k.box(_m["trim"], Transform3D(I, Vector3(gc.x, y0 + H + rise + 0.12, gc.y)), Vector3(0.26, 0.2, g.size.y + 0.66))
		# Crow-stepped gables, front and back.
		var stepn := 5
		for gz: float in [g.position.y + t * 0.5, g.end.y - t * 0.5]:
			for i in stepn:
				var wv := g.size.x * (1.0 - float(i) / stepn) - 0.2
				var hv := rise / stepn
				_box(k, null, wall, Transform3D(I, Vector3(gc.x, y0 + H + hv * (i + 0.5), gz)), Vector3(wv, hv + 0.02, t), tint)
				k.box(_m["trim"], Transform3D(I, Vector3(gc.x + wv * 0.5 - 0.15, y0 + H + hv * (i + 1) + 0.04, gz)), Vector3(0.36, 0.08, t + 0.08))
				k.box(_m["trim"], Transform3D(I, Vector3(gc.x - wv * 0.5 + 0.15, y0 + H + hv * (i + 1) + 0.04, gz)), Vector3(0.36, 0.08, t + 0.08))
		if _era == Eras.FANTASY:
			models.append(["village/Prop_Vine2", 0, Vector3(g.position.x + 1.8, y0 + 1.6, g.end.y + 0.02), 1.4])
			models.append(["village/Prop_Vine5", 90, Vector3(g.end.x + 0.02, y0 + 1.2, gc.y - 1.0), 1.3])
		for s: float in [-1.0, 1.0]:
			models.append(["props/Torch_Metal", 0, Vector3(m.x + s * (ow + 0.75), y0 + 2.0, g.end.y + 0.01), 1.0])
	else:
		_box(k, boxes, "metal_dark", Transform3D(I, Vector3(gc.x, y0 + H + 0.12, gc.y)), Vector3(g.size.x + 0.3, 0.24, g.size.y + 0.3))
		for s: float in [-1.0, 1.0]:
			k.box("metal", Transform3D(I, Vector3(gc.x + s * (g.size.x * 0.5 + 0.05), y0 + H + 0.75, gc.y)), Vector3(0.05, 0.05, g.size.y + 0.2))
			for zi in 5:
				k.box("metal", Transform3D(I, Vector3(gc.x + s * (g.size.x * 0.5 + 0.05), y0 + H + 0.5, g.position.y + g.size.y * zi / 4.0)), Vector3(0.05, 0.55, 0.05))
		k.box("glow_white", Transform3D(I, Vector3(m.x, y0 + oh + 0.35, g.end.y + 0.06)), Vector3(0.7, 0.08, 0.06))
	var mi := _mesh_node(k, models, 700.0)
	mi.name = "Gatehouse"
	add_child(mi)
	add_child(_body(boxes))
	# Torches by the door and a light over the stairhead.
	if _era != Eras.SCIFI:
		for s: float in [-1.0, 1.0]:
			_add_lamp(-1, FireFx.prop_flames([["props/Torch_Metal", 0, Vector3(m.x + s * (ow + 0.75), y0 + 2.0, g.end.y + 0.01), 1.0]])[0][0], 1.3, true)
		_add_lamp(-1, Vector3(m.x, y0 + 2.6, m.y - 1.0), 1.2, false)
	else:
		_add_lamp(-1, Vector3(m.x, y0 + oh + 0.25, g.end.y + 0.4), 1.4, false)
		_add_lamp(-1, Vector3(m.x, y0 + 2.8, m.y - 1.0), 1.2, false)

## A light at plan point p (a flame there too if `flame`), off until it's among the
## nearest.
func _add_lamp(lv: int, p: Vector3, energy: float, flame: bool) -> void:
	var holder := Node3D.new()
	holder.position = p
	var l: OmniLight3D
	if _era != Eras.SCIFI:
		l = FlickerLight.new()
		l.light_color = FIRE
		if flame:
			holder.add_child(FireFx.flame(0.42))
		l.position = Vector3(0, 0.3, 0) if flame else Vector3.ZERO
	else:
		l = OmniLight3D.new()
		l.light_color = LAMP
	# Strip lamps on dark steel: brighter and further than a torch on pale stone.
	l.light_energy = energy * (1.7 if _era == Eras.SCIFI else 1.0)
	l.omni_range = 11.0 if _era == Eras.SCIFI else 9.0
	l.omni_attenuation = 1.3
	ChunkNode._cast_shadows(l)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 36.0
	l.distance_fade_length = 10.0
	holder.add_child(l)
	holder.visible = false
	add_child(holder)
	_lamps.append({"p": p, "lv": lv, "node": holder, "light": l})

# --- Seals and puzzle parts -----------------------------------------------------------

func _build_parts() -> void:
	var w: Array = Dungeon.WORDS[_era]
	# Every torch below, unlit until near.
	for l in pl["lights"]:
		var p: Vector3 = l["p"]
		var yaw := float(l["yaw"])
		if _era == Eras.SCIFI:
			var dv := Vector2(-sin(yaw), -cos(yaw))
			_add_lamp(l["lv"], Vector3(p.x - dv.x * 0.3, p.y + 2.35, p.z - dv.y * 0.3), 1.3, false)
		else:
			var f: Array = FireFx.prop_flames([["props/Torch_Metal", rad_to_deg(yaw), p + Vector3(0, 1.9, 0), 1.0]])
			_add_lamp(l["lv"], f[0][0] if not f.is_empty() else p + Vector3(0, 2.2, 0), 1.6, true)
	for li in pl["locks"].size():
		_seals.append(_make_seal(li))
	for pi in pl["parts"].size():
		_parts.append(_make_part(pi))
	for ni in pl["notes"].size():
		var nt: Dictionary = pl["notes"][ni]
		var k := MeshKit.new(ni + 11)
		var b := Basis(Vector3.UP, float(nt["yaw"]))
		if _era == Eras.SCIFI:
			k.box("metal_dark", Transform3D(b, Vector3(0, 0, 0.03)), Vector3(0.6, 0.44, 0.06))
			k.box("screen", Transform3D(b, Vector3(0, 0.01, 0.065)), Vector3(0.5, 0.32, 0.01))
		else:
			k.box("planks", Transform3D(b, Vector3(0, 0, 0.025)), Vector3(0.62, 0.48, 0.05))
			k.box("linen", Transform3D(b, Vector3(0, -0.01, 0.055)), Vector3(0.44, 0.34, 0.01), Color(0.95, 0.9, 0.78))
			k.box("iron", Transform3D(b, Vector3(0, 0.14, 0.064)), Vector3(0.04, 0.04, 0.01))
		var mi := _mesh_node(k, [])
		mi.position = nt["p"]
		add_child(mi)
		_notes.append(mi)

## The gate over a sealed doorway: an iron portcullis (a blast door in a bunker) that
## rises into the lintel when its seal opens.
func _make_seal(li: int) -> Dictionary:
	var lk: Dictionary = pl["locks"][li]
	var dr: Dictionary = pl["doors"][lk["door"]]
	var lv: int = dr["lv"]
	var dv := Vector2(Dungeon.DIRS[dr["d"]])
	var e := Dungeon.centre(pl, dr["a"]) + dv * Dungeon.CELL * 0.5
	var hw := Dungeon.STAIR_W * 0.5 if dr["stair"] else Dungeon.DOOR_HALF
	var h := Dungeon.DOOR_H if not dr["stair"] or _era == Eras.SCIFI else Dungeon.DOOR_H
	var holder := Node3D.new()
	holder.position = _v(e, Dungeon.floor_y(pl, lv))
	holder.basis = _face(dv)
	var k := MeshKit.new(li + 101)
	var I := Basis.IDENTITY
	if _era == Eras.SCIFI:
		k.box("metal_dark", Transform3D(I, Vector3(0, h * 0.5, 0)), Vector3(hw * 2.0, h, 0.12))
		k.box("scifi_panels", Transform3D(I, Vector3(0, h * 0.5, 0.065)), Vector3(hw * 2.0 - 0.2, h - 0.2, 0.02))
		k.box("scifi_panels", Transform3D(I, Vector3(0, h * 0.5, -0.065)), Vector3(hw * 2.0 - 0.2, h - 0.2, 0.02))
		for f: float in [-1.0, 1.0]:
			k.box("hazard", Transform3D(I, Vector3(0, 0.25, f * 0.08)), Vector3(hw * 2.0, 0.3, 0.01))
	else:
		var metal: String = _m["metal"]
		var x := -hw + 0.08
		while x <= hw - 0.07:
			k.box(metal, Transform3D(I, Vector3(x, h * 0.5 + 0.05, 0)), Vector3(0.05, h - 0.1, 0.05))
			k.cylinder(metal, Transform3D(I, Vector3(x, -0.12, 0)), 0.005, 0.035, 0.18, 5)
			x += 0.19
		for y: float in [0.5, 1.3, 2.1]:
			k.box(metal, Transform3D(I, Vector3(0, y, 0)), Vector3(hw * 2.0 - 0.04, 0.06, 0.07))
	var mi := _mesh_node(k, [])
	holder.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("dungeon", pl["id"])
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(hw * 2.0, h, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	holder.add_child(body)
	add_child(holder)
	var open := seal_open(li)
	var amt := 1.0 if open else 0.0
	mi.position.y = amt * (h - 0.25)
	if open:
		body.process_mode = Node.PROCESS_MODE_DISABLED
		cs.disabled = true
	return {"node": holder, "mi": mi, "body": body, "shape": cs, "amt": amt, "h": h, "lv": lv}

func _make_part(pi: int) -> Dictionary:
	var p: Dictionary = pl["parts"][pi]
	var holder := Node3D.new()
	holder.position = p["p"]
	holder.rotation.y = float(p["yaw"])
	var k := MeshKit.new(pi + 201)
	var I := Basis.IDENTITY
	var moving: Node3D = null
	var metal: String = _m["metal"]
	var on := _is("on", pi)
	var out := {"node": holder}
	match p["kind"]:
		"lever":
			holder.position.y += 1.15
			if _era == Eras.SCIFI:
				k.box("metal_dark", Transform3D(I, Vector3(0, 0, 0.06)), Vector3(0.36, 0.5, 0.12))
				k.box("hazard", Transform3D(I, Vector3(0, -0.21, 0.121)), Vector3(0.34, 0.06, 0.01))
			else:
				k.box(metal, Transform3D(I, Vector3(0, 0, 0.03)), Vector3(0.24, 0.42, 0.06))
				for y: float in [-0.15, 0.15]:
					k.box(metal, Transform3D(I, Vector3(0, y, 0.07)), Vector3(0.05, 0.05, 0.04))
			var hk := MeshKit.new(pi + 301)
			hk.cylinder(metal if _era != Eras.SCIFI else "metal", Transform3D(I, Vector3(0, 0, 0)), 0.022, 0.018, 0.4, 6)
			hk.sphere("timber" if _era != Eras.SCIFI else "rubber", Transform3D(I, Vector3(0, 0.42, 0)), 0.045, 5, 8)
			moving = Node3D.new()
			moving.position = Vector3(0, 0, 0.1)
			moving.add_child(_mesh_node(hk, []))
			holder.add_child(moving)
			moving.rotation.x = deg_to_rad(-40.0 if not on else 130.0)
		"key":
			if _era == Eras.SCIFI:
				k.box("metal_dark", Transform3D(I, Vector3(0, 0.4, 0)), Vector3(0.5, 0.8, 0.4))
				k.box("panel", Transform3D(I, Vector3(0, 0.81, 0)), Vector3(0.56, 0.03, 0.46))
			else:
				k.box(_m["trim"], Transform3D(I, Vector3(0, 0.45, 0)), Vector3(0.42, 0.9, 0.42))
				k.box(_m["wall"], Transform3D(I, Vector3(0, 0.93, 0)), Vector3(0.56, 0.08, 0.56))
				k.box(_m["wall"], Transform3D(I, Vector3(0, 0.06, 0)), Vector3(0.56, 0.12, 0.56))
			var kk := MeshKit.new(pi + 401)
			if _era == Eras.SCIFI:
				kk.box("panel", Transform3D(I, Vector3(0, 0.005, 0)), Vector3(0.09, 0.006, 0.056))
				kk.box("hazard", Transform3D(I, Vector3(0, 0.009, -0.016)), Vector3(0.09, 0.002, 0.012))
			else:
				kk.cylinder("gold" if _era == Eras.MEDIEVAL else "bone", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(-0.08, 0.012, 0)), 0.035, 0.035, 0.012, 10)
				kk.box("gold" if _era == Eras.MEDIEVAL else "bone", Transform3D(I, Vector3(0.03, 0.012, 0)), Vector3(0.16, 0.016, 0.016))
				kk.box("gold" if _era == Eras.MEDIEVAL else "bone", Transform3D(I, Vector3(0.09, 0.012, 0.022)), Vector3(0.03, 0.014, 0.03))
			moving = Node3D.new()
			moving.position = Vector3(0, 0.97 if _era != Eras.SCIFI else 0.825, 0)
			moving.add_child(_mesh_node(kk, []))
			holder.add_child(moving)
			moving.visible = not _key_taken(int(p["lock"]))
		"plate":
			moving = Node3D.new()
			var pk := MeshKit.new(pi + 501)
			if _era == Eras.SCIFI:
				pk.box("metal_dark", Transform3D(I, Vector3(0, 0.03, 0)), Vector3(0.95, 0.06, 0.95))
				pk.box("hazard", Transform3D(I, Vector3(0, 0.061, 0)), Vector3(0.75, 0.004, 0.75))
			else:
				pk.box("river_stone", Transform3D(I, Vector3(0, 0.03, 0)), Vector3(0.95, 0.07, 0.95), Color(0.85, 0.82, 0.76))
				pk.box(_m["trim"], Transform3D(I, Vector3(0, 0.068, 0)), Vector3(0.5, 0.01, 0.5))
			moving.add_child(_mesh_node(pk, []))
			holder.add_child(moving)
			moving.position.y = -0.055 if on else 0.0
		"brazier":
			if _era == Eras.SCIFI:
				k.box("metal_dark", Transform3D(I, Vector3(0, 0.6, 0)), Vector3(0.5, 1.2, 0.34))
				k.box("panel", Transform3D(I, Vector3(0, 0.75, 0.175)), Vector3(0.36, 0.42, 0.01))
				k.cylinder("metal", Transform3D(I, Vector3(0, 1.2, 0)), 0.06, 0.06, 0.5, 8)
			else:
				for i in 3:
					var a := TAU * i / 3.0
					var leg := Basis(Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)), 0.22)
					k.cylinder(metal, Transform3D(leg, Vector3(cos(a) * 0.2, 0, sin(a) * 0.2)), 0.025, 0.02, 0.82, 5)
				k.cylinder(metal, Transform3D(I, Vector3(0, 0.78, 0)), 0.12, 0.34, 0.2, 12)
				k.cylinder("char", Transform3D(I, Vector3(0, 0.9, 0)), 0.3, 0.26, 0.06, 10)
			moving = Node3D.new()
			if _era == Eras.SCIFI:
				var ik := MeshKit.new(pi + 601)
				ik.box("glow_white", Transform3D(I, Vector3(0, 0, 0)), Vector3(0.24, 0.24, 0.012)) # a lit lamp, as electric lamps are
				moving.add_child(_mesh_node(ik, []))
				moving.position = Vector3(0, 0.75, 0.182)
				var off := MeshKit.new(pi + 651)
				off.box("glass", Transform3D(I, Vector3(0, 0, 0)), Vector3(0.24, 0.24, 0.012))
				var offm := _mesh_node(off, [])
				offm.position = Vector3(0, 0.75, 0.182)
				holder.add_child(offm)
				out["off"] = offm
			else:
				moving.add_child(FireFx.flame(0.55))
				moving.position = Vector3(0, 0.92, 0)
			holder.add_child(moving)
			var l: OmniLight3D = FlickerLight.new() if _era != Eras.SCIFI else OmniLight3D.new()
			l.light_color = FIRE if _era != Eras.SCIFI else LAMP
			l.light_energy = 1.5
			l.omni_range = 7.5
			l.omni_attenuation = 1.3
			ChunkNode._cast_shadows(l)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 30.0
			l.distance_fade_length = 10.0
			l.position = Vector3(0, 1.35, 0)
			holder.add_child(l)
			out["lamp"] = l
	var mi := _mesh_node(k, [])
	holder.add_child(mi)
	add_child(holder)
	out["moving"] = moving
	_show_part(pi, out)
	return out

func _show_part(pi: int, rec: Dictionary) -> void:
	var p: Dictionary = pl["parts"][pi]
	var on := _is("on", pi)
	if p["kind"] == "brazier":
		rec["moving"].visible = on
		rec["lamp"].visible = on
		if rec.has("off"):
			rec["off"].visible = not on

func _key_taken(li: int) -> bool:
	return _is("keys", li)

# --- Using things --------------------------------------------------------------------

## Things you can use within reach of world point at: [{at (world), verb, n}]; n is
## "kind:index".
func usables(at: Vector3) -> Array:
	var out: Array = []
	if not deep:
		return out
	var q := Dungeon.to_plan(pl, at)
	var w: Array = Dungeon.WORDS[_era]
	for pi in pl["parts"].size():
		var p: Dictionary = pl["parts"][pi]
		var pp: Vector3 = p["p"]
		if absf(pp.y - q.y) > 3.0 or Vector2(pp.x - q.x, pp.z - q.z).length() > 5.0:
			continue
		var on := _is("on", pi)
		var verb := ""
		var h := 0.6
		match p["kind"]:
			"lever":
				verb = "" if on else ("Throw the %s" % w[1] if _era == Eras.SCIFI else "Pull the lever")
				h = 1.2
			"key":
				verb = "" if _key_taken(int(p["lock"])) else "Take the %s" % w[2]
				h = 1.0
			"brazier":
				verb = "" if on else ("Restore the %s" % w[4] if _era == Eras.SCIFI else "Light the brazier")
				h = 0.95
			"plate":
				verb = "" if on else "Step on the %s" % ("pad" if _era == Eras.SCIFI else "worn flagstone")
				h = 0.1
		if verb != "":
			out.append({"at": Dungeon.to_world(pl, pp + Vector3(0, h, 0)), "verb": verb, "n": "part:%d" % pi})
	for li in pl["locks"].size():
		if seal_open(li):
			continue
		var s: Dictionary = _seals[li]
		var sp: Vector3 = Dungeon.to_plan(pl, (s["node"] as Node3D).global_position)
		if absf(sp.y - q.y) > 3.0 or Vector2(sp.x - q.x, sp.z - q.z).length() > 5.0:
			continue
		var lk: Dictionary = pl["locks"][li]
		var verb: String = lk["sealed"]
		if lk["kind"] == "key" and _key_taken(li):
			verb = "Unlock the %s with the %s" % [w[0], w[2]]
		out.append({"at": (s["node"] as Node3D).global_position + Vector3(0, 1.3, 0), "verb": verb, "n": "seal:%d" % li})
	for ni in pl["notes"].size():
		var nt: Dictionary = pl["notes"][ni]
		var np: Vector3 = nt["p"]
		if absf(np.y - q.y - 1.5) > 2.5 or Vector2(np.x - q.x, np.z - q.z).length() > 5.0:
			continue
		out.append({"at": Dungeon.to_world(pl, np), "verb": "Read the %s" % ("notice" if _era != Eras.SCIFI else "terminal"), "n": "note:%d" % ni})
	return out

func use(n: String, who: Node) -> void:
	var kind := n.get_slice(":", 0)
	var i := int(n.get_slice(":", 1))
	var w: Array = Dungeon.WORDS[_era]
	match kind:
		"part":
			var p: Dictionary = pl["parts"][i]
			var at := Dungeon.to_world(pl, p["p"])
			match p["kind"]:
				"lever":
					if _is("on", i):
						return
					_mark("on", i)
					Audio.play_at("hit/metal", at + Vector3(0, 1.2, 0), -2.0)
					Audio.play_at("door/lock", at + Vector3(0, 1.2, 0), -4.0)
				"key":
					if _key_taken(int(p["lock"])):
						return
					_mark("keys", int(p["lock"]))
					(_parts[i]["moving"] as Node3D).visible = false
					Audio.play("item/pickup", -4.0)
					Game.toast.emit("You take the %s. It must open something down here." % w[2])
					return
				"brazier":
					if _is("on", i):
						return
					_mark("on", i)
					Audio.play_at("harvest/rustle" if _era != Eras.SCIFI else "hit/metal", at + Vector3(0, 1.0, 0), -2.0)
				"plate":
					Game.toast.emit("Stand on it.")
					return
			_show_part(i, _parts[i])
			_check(int(p["lock"]))
		"seal":
			var lk: Dictionary = pl["locks"][i]
			if lk["kind"] == "key" and _key_taken(i):
				_open_seal(i)
				return
			Audio.play_at("door/lock", (_seals[i]["node"] as Node3D).global_position + Vector3(0, 1.0, 0), -6.0)
			Game.toast.emit(String(lk["sealed"]) + ".")
		"note":
			var nt: Dictionary = pl["notes"][i]
			var entry := {"title": nt["title"], "sub": pl["name"], "look": "screen" if _era == Eras.SCIFI else "paper",
				"pages": [{"tab": "Notice", "text": nt["text"]}]}
			who.get_tree().call_group("lore_ui", "open_entry", entry, Dungeon.to_world(pl, nt["p"]))
			if not _is("read", i):
				_mark("read", i)
				Game.add_xp(4.0, "Read a notice")

## Opens seal li when all its parts are done.
func _check(li: int) -> void:
	var lk: Dictionary = pl["locks"][li]
	if seal_open(li) or lk["kind"] == "key":
		return
	var left := 0
	for pi in lk["parts"]:
		if not _is("on", int(pi)):
			left += 1
	if left > 0:
		if lk["kind"] in ["plates", "braziers"]:
			Game.toast.emit("%d more to go." % left)
		return
	_open_seal(li)

func _open_seal(li: int) -> void:
	if seal_open(li):
		return
	_mark("open", li)
	var lk: Dictionary = pl["locks"][li]
	var s: Dictionary = _seals[li]
	(s["shape"] as CollisionShape3D).set_deferred("disabled", true)
	var at: Vector3 = (s["node"] as Node3D).global_position + Vector3(0, 1.2, 0)
	Audio.play_at("door/slide_open", at, 2.0)
	var what := "treasury" if lk["what"] == "vault" else "stair down"
	var gate: String = Dungeon.WORDS[_era][0]
	var near := player != null and player.global_position.distance_to(at) < 14.0
	Game.toast.emit(("The %s to the %s rises." if near else "Somewhere, a %s grinds open: the way to the %s is clear.") % [gate, what])
	Game.add_xp(15.0 + 10.0 * int(pl["tier"]), "Opened a seal")

# --- Each frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not deep:
		_update_lamps()
		return
	for i in mini(2, _queue.size()):
		var q: Array = _queue.pop_front()
		_build_block(q[0], q[1], q[2])
	# Seals rising.
	for li in _seals.size():
		var s: Dictionary = _seals[li]
		var want := 1.0 if seal_open(li) else 0.0
		if not is_equal_approx(float(s["amt"]), want):
			s["amt"] = move_toward(float(s["amt"]), want, delta * SEAL_RISE)
			(s["mi"] as Node3D).position.y = smoothstep(0.0, 1.0, float(s["amt"])) * (float(s["h"]) - 0.25)
			(s["shape"] as CollisionShape3D).disabled = want > 0.5
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	_refresh_from_state()
	var p := player.global_position if player != null else Vector3.INF
	var q := Dungeon.to_plan(pl, p)
	_player_lv = _level_of(q)
	_update_blocks(q)
	_update_lamps()
	if _player_lv >= 0:
		_step_on_plates(q)
		_note_room(q)
	_watch_exit(q, delta)

## Remote players' doing (multiplayer) or a reload: parts and seals follow the state.
func _refresh_from_state() -> void:
	for pi in _parts.size():
		var rec: Dictionary = _parts[pi]
		var p: Dictionary = pl["parts"][pi]
		var on := _is("on", pi)
		match p["kind"]:
			"lever":
				var want := deg_to_rad(130.0 if on else -40.0)
				var mv: Node3D = rec["moving"]
				mv.rotation.x = lerp_angle(mv.rotation.x, want, 0.6)
			"key":
				(rec["moving"] as Node3D).visible = not _key_taken(int(p["lock"]))
			"plate":
				(rec["moving"] as Node3D).position.y = -0.055 if on else 0.0
			"brazier":
				_show_part(pi, rec)
	for li in pl["locks"].size():
		if not seal_open(li) and pl["locks"][li]["kind"] != "key":
			var all := true
			for pi in pl["locks"][li]["parts"]:
				all = all and _is("on", int(pi))
			if all and not pl["locks"][li]["parts"].is_empty():
				_open_seal(li)

## -1 in the gatehouse or on the entrance flight, a level's index down below, -2 elsewhere.
func _level_of(q: Vector3) -> int:
	var ext := float(pl["n"]) * Dungeon.CELL * 0.5
	if absf(q.x) > ext + 4.0 or absf(q.z) > ext + 4.0:
		return -2
	var g := Dungeon.gatehouse(pl)
	if g.has_point(Vector2(q.x, q.z)) and q.y > float(pl["y0"]) - 2.0 and q.y < float(pl["y0"]) + 5.0:
		return -1
	if q.y > float(pl["y0"]) - 1.0 or q.y < Dungeon.floor_y(pl, pl["levels"].size() - 1) - 4.0:
		return -2
	var c := Dungeon.cell_at(pl, Vector2(q.x, q.z))
	var lv := Dungeon.level_near(pl, q.y)
	if Dungeon.kind(pl, 0, c) == Dungeon.ENTRY and q.y > Dungeon.floor_y(pl, 0) + 1.0:
		return -1
	return lv

func _update_blocks(q: Vector3) -> void:
	var pp := Vector2(q.x, q.z)
	for b in _blocks:
		var on := false
		var lv: int = b["lv"]
		var shows: Array = b["shows"]
		if _player_lv >= 0 and (lv == _player_lv or shows.has(_player_lv)):
			on = _dist(b["rect"], pp) < SEE
		elif _player_lv == -1:
			# Up top: only what you can see down the entrance flight.
			on = (shows.has(-1) or lv == 0) and _dist(b["rect"], Dungeon.centre(pl, pl["entry"]["land"])) < 10.0
		elif _player_lv >= 0 and shows.size() > 1:
			on = _dist(b["rect"], pp) < 14.0
		(b["mi"] as Node3D).visible = on
	for s in _seals:
		(s["node"] as Node3D).visible = _player_lv >= 0 and absi(int(s["lv"]) - _player_lv) <= 1
	for i in _parts.size():
		(_parts[i]["node"] as Node3D).visible = _player_lv >= 0 and absi(int(pl["parts"][i]["lv"]) - _player_lv) <= 1
	for i in _notes.size():
		(_notes[i] as Node3D).visible = _player_lv >= 0 and absi(int(pl["notes"][i]["lv"]) - _player_lv) <= 1

static func _dist(r: Rect2, p: Vector2) -> float:
	var cx := clampf(p.x, r.position.x, r.end.x)
	var cy := clampf(p.y, r.position.y, r.end.y)
	return p.distance_to(Vector2(cx, cy))

## Only the nearest torches on the levels you can see burn and give light.
func _update_lamps() -> void:
	var p := player.global_position if player != null else Vector3.INF
	var q := Dungeon.to_plan(pl, p)
	var ranked: Array = []
	for i in _lamps.size():
		var l: Dictionary = _lamps[i]
		var lv: int = l["lv"]
		var ok := false
		if lv < 0:
			ok = _player_lv < 0 or _player_lv == 0
		else:
			ok = _player_lv >= 0 and absi(lv - _player_lv) <= (0 if _player_lv != lv else 0)
			ok = ok or (_player_lv >= 0 and absf(Dungeon.floor_y(pl, lv) - q.y) < 4.0)
		var d := (l["p"] as Vector3).distance_to(q)
		if ok and d < 40.0:
			ranked.append([d, i])
		else:
			(l["node"] as Node3D).visible = false
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for k in ranked.size():
		(_lamps[ranked[k][1]]["node"] as Node3D).visible = k < LAMPS

func _step_on_plates(q: Vector3) -> void:
	for pi in pl["parts"].size():
		var p: Dictionary = pl["parts"][pi]
		if p["kind"] != "plate" or _is("on", pi):
			continue
		var pp: Vector3 = p["p"]
		if absf(q.y - pp.y) < 0.6 and Vector2(q.x - pp.x, q.z - pp.z).length() < PLATE_R:
			_mark("on", pi)
			(_parts[pi]["moving"] as Node3D).position.y = -0.055
			Audio.play_at("hit/stone", player.global_position, -2.0)
			_check(int(p["lock"]))

func _note_room(q: Vector3) -> void:
	if not _entered:
		_entered = true
		Game.discovered.emit(pl["name"], "%d level%s deep" % [pl["levels"].size(), "s" if pl["levels"].size() > 1 else ""], UITheme.ERA_COLORS[_era])
	var c := Dungeon.cell_at(pl, Vector2(q.x, q.z))
	var ri := Dungeon.room_of(pl, _player_lv, c)
	if ri >= 0 and not _is("seen", ri):
		_mark("seen", ri)
		var pr := progress()
		if pr["rooms"].x >= pr["rooms"].y and pr["seals"].x >= pr["seals"].y and not state().get("done", false):
			state()["done"] = true
			Game.add_xp(40.0 * int(pl["tier"]) * pl["levels"].size(), "Explored the %s" % pl["name"])
			Game.toast.emit("You've been through every room of the %s." % pl["name"])

## Heading back up the entrance flight with things left undone: say so, once a while.
func _watch_exit(q: Vector3, _delta: float) -> void:
	var climbing := _player_lv == -1 and q.y > _last_y + 0.15 and q.y < float(pl["y0"]) - 1.0
	_last_y = q.y
	if not climbing or Time.get_ticks_msec() - _cue_t < 90000.0:
		return
	var why := unfinished()
	if why == "":
		return
	_cue_t = Time.get_ticks_msec()
	Game.toast.emit(why)

## How far along you are here: Vector2i(done, of) for rooms, seals and chests.
func progress() -> Dictionary:
	var rooms := 0
	var seen := 0
	for ri in pl["rooms"].size():
		if pl["rooms"][ri]["kind"] == "gone":
			continue
		rooms += 1
		if _is("seen", ri):
			seen += 1
	var seals := 0
	for li in pl["locks"].size():
		if seal_open(li):
			seals += 1
	if Time.get_ticks_msec() - _chest_t > 2000.0:
		_chest_t = Time.get_ticks_msec()
		_chests = _count_chests()
	return {"rooms": Vector2i(seen, rooms), "seals": Vector2i(seals, pl["locks"].size()), "chests": _chests}

func _count_chests() -> Vector2i:
	var opened := 0
	var of := 0
	if streamer == null:
		return Vector2i.ZERO
	var c: Vector2 = pl["c"]
	var ext := float(pl["n"]) * Dungeon.CELL * 0.5 + 2.0
	var k0 := ChunkStreamer.chunk_of(Vector3(c.x - ext, 0, c.y - ext))
	var k1 := ChunkStreamer.chunk_of(Vector3(c.x + ext, 0, c.y + ext))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var cn := streamer.get_chunk(Vector2i(kx, kz))
			if cn == null:
				continue
			for o in cn.data["objects"]:
				if String(o["st"].get("dg", "")) == String(pl["id"]):
					of += 1
					if o["st"].get("opened", false):
						opened += 1
	return Vector2i(opened, of)

## What's left to do, said as a thought ("" when nothing).
func unfinished() -> String:
	var pr := progress()
	var bits: Array = []
	var gate: String = Dungeon.WORDS[_era][0]
	for li in pl["locks"].size():
		if seal_open(li):
			continue
		var lk: Dictionary = pl["locks"][li]
		var lvn: String = Dungeon.ORDINALS[mini(int(lk["lv"]), 3)]
		var what := "treasury" if lk["what"] == "vault" else "stair down"
		bits.append("the %s to the %s on the %s level is still shut (the notice beside it says how to open it)" % [gate, what, lvn])
		break
	var left: Vector2i = pr["rooms"]
	if left.x < left.y:
		var lvs := {}
		for ri in pl["rooms"].size():
			if pl["rooms"][ri]["kind"] != "gone" and not _is("seen", ri):
				lvs[int(pl["rooms"][ri]["lv"])] = true
		var first: int = lvs.keys().min()
		bits.append("there %s %d room%s you haven't seen, some on the %s level" % ["is" if left.y - left.x == 1 else "are", left.y - left.x, "" if left.y - left.x == 1 else "s", Dungeon.ORDINALS[mini(first, 3)]])
	var ch: Vector2i = pr["chests"]
	if ch.y > 0 and ch.x < ch.y and bits.size() < 2:
		bits.append("%d chest%s down here still unopened" % [ch.y - ch.x, "" if ch.y - ch.x == 1 else "s"])
	if bits.is_empty():
		return ""
	return "Not done yet... " + " and ".join(bits) + "."
