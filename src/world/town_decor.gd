class_name TownDecor
extends Node3D
## What makes a settlement's shops look like shops, built while you are near: a painted
## sign over each shop's door (what it sells, its name and a picture of its wares), and
## inside a counter the keeper stands behind with goods of the trade on it and a stand
## of wares beside it. Your own houses get a sign too. Nothing here is saved: it all
## follows from TownShops' plan, so it is rebuilt the same every visit.

var gen: ChunkGenerator
var streamer: ChunkStreamer
var site: Dictionary
var data: Dictionary ## the settlement's saved record (keepers get their floor height)
var estates: Array = [] ## the traveller's houses (Game.estates)

var _pending: Array = []
var _t := 0.0

const SIGN_RANGE := 90.0

## Counter-top and stand wares per shop kind: [kit props on the counter as [model, x along
## the counter, yaw], the stand beside the keeper: "rack" (weapons from the shop's goods),
## "dummy", or a kit model]. Sci-fi shops use the "~s" entries when they exist.
const WARES := {
	"armourer": [[["props/Coin_Pile", 0.45, 0.0], ["props/CandleStick", -0.55, 0.0]], "dummy"],
	"weaponsmith": [[["props/Candle_1", 0.45, 0.0], ["props/Coin_Pile", -0.45, 0.0]], "rack"],
	"apothecary": [[["props/Potion_1", -0.5, 0.0], ["props/Potion_2", -0.3, 30.0], ["props/Bottle_1", 0.35, 0.0], ["props/Potion_1", 0.5, 70.0], ["props/Candle_1", 0.0, 0.0]], "props/Cauldron"],
	"general": [[["props/Bag", -0.4, 30.0], ["props/Coin_Pile", 0.4, 0.0], ["props/Candle_2", 0.05, 0.0]], "props/Barrel_Apples"],
	"tavern": [[["props/Mug", -0.5, 0.0], ["props/Mug", -0.25, 90.0], ["props/Bottle_1", 0.15, 0.0], ["props/Table_Plate", 0.45, 0.0]], "props/Barrel"],
	"land": [[["props/Scroll_1", -0.3, 25.0], ["props/Book_5", 0.3, 10.0], ["props/CandleStick", 0.6, 0.0]], "props/BookStand"],
	"guild": [[["props/Chalice", -0.45, 0.0], ["props/Book_Stack_1", 0.1, 15.0], ["props/Candle_1", 0.5, 0.0]], "props/Chest_Wood"],
	"armourer~s": [[], "dummy"],
	"weaponsmith~s": [[], "rack"],
	"apothecary~s": [[["props/Potion_1", -0.4, 0.0], ["props/Potion_2", -0.2, 0.0], ["props/Bottle_1", 0.4, 0.0]], "scifi/Prop_Barrel_Large"],
	"general~s": [[], "scifi/Prop_Crate3"],
	"tavern~s": [[["props/Mug", -0.4, 0.0], ["props/Bottle_1", 0.1, 0.0], ["props/Mug", 0.45, 50.0]], "scifi/Prop_Barrel_Large"],
	"land~s": [[], "scifi/Prop_Computer"],
	"guild~s": [[], "scifi/Prop_Chest"],
}

## Fighters' kind of guild: a dummy; mages': a book stand.
const GUILD_STAND := {"fighters_guild": "dummy", "rangers_lodge": "rack", "mercenary_guild": "rack",
	"mages_guild": "props/BookStand", "arcane_conclave": "props/BookStand", "engineers_guild": "scifi/Prop_Crate4"}

static var _meshes: Dictionary = {}

func setup(g: ChunkGenerator, s: ChunkStreamer, st: Dictionary, d: Dictionary, est: Array) -> void:
	gen = g
	streamer = s
	site = st
	data = d
	estates = est
	name = "Shops_" + NPCGen.settlement_id(st["sx"], st["sz"])
	refresh()

## Rebuilds everything (after you buy a house, say).
func refresh() -> void:
	for ch in get_children():
		ch.queue_free()
	_pending.clear()
	for h in TownShops.plan(gen, site):
		if h["kind"] != "" or TownShops.owned(h, estates):
			_pending.append(h)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or _pending.is_empty():
		return
	_t = 0.5
	for h in _pending.duplicate():
		var o := _object(h)
		if o.is_empty():
			continue
		_pending.erase(h)
		if o.get("gone", false):
			continue
		_build(h, o)

## The building's chunk object as {y, r, s, gone}, or {} while its chunk isn't loaded.
func _object(h: Dictionary) -> Dictionary:
	var p: Vector2 = h["p"]
	var k := ChunkStreamer.chunk_of(Vector3(p.x, 0, p.y))
	var c := streamer.get_chunk(k)
	if c == null or c.data.is_empty():
		return {}
	for o in c.data["objects"]:
		if o["t"] != h["t"]:
			continue
		var wp := Vector2(o["p"].x + k.x * ChunkGenerator.SIZE, o["p"].z + k.y * ChunkGenerator.SIZE)
		if wp.distance_to(p) < 0.6:
			return {"y": float(o["p"].y), "r": float(o["r"]), "s": float(o["s"]), "gone": o["st"].get("gone", false)}
	return {"gone": true}

func _build(h: Dictionary, o: Dictionary) -> void:
	var p: Vector2 = h["p"]
	var s: float = o["s"]
	var root := Node3D.new()
	# The room's own space, sunk like the building is drawn.
	root.transform = Transform3D(Basis(Vector3.UP, o["r"]).scaled(Vector3.ONE * s), Vector3(p.x, o["y"] - Interiors.SINK * s, p.y))
	add_child(root)
	var era := int(h["era"])
	var rm := TownShops.room(h["t"])
	var kind: String = h["kind"]
	if kind == "":
		_sign(root, rm["sign"], era, "Your House", "Home of the traveller", "")
		return
	_sign(root, rm["sign"], era, h["label"], h["title"], TownShops.icon_of(kind, era))
	var ft := TownShops.fit(h["t"])
	if ft.has("counter"):
		_counter(root, h, ft, rm)
	elif not ft.get("props", []).is_empty():
		_small_shop(root, h, ft, rm)
	# The keeper stands on the floor, not the ground under it.
	for rec in data.get("npcs", []):
		if rec.has("room") and int(rec.get("shop_i", -1)) == int(h["i"]):
			rec["room"]["y"] = float(o["y"]) + (float(rm["floor"]) - Interiors.SINK) * s

# --- Signs -----------------------------------------------------------------------------------

func _sign(root: Node3D, sg: Array, era: int, label: String, title: String, icon: String) -> void:
	var at: Vector3 = sg[0]
	var size: Vector2 = sg[1]
	var post: bool = sg[2] == "post"
	var node := Node3D.new()
	node.position = at
	root.add_child(node)
	var k := MeshKit.new(17)
	var I := Transform3D.IDENTITY
	var board := Color(0.2, 0.13, 0.08) if era == Eras.MEDIEVAL else (Color(0.12, 0.2, 0.16) if era == Eras.FANTASY else Color(0.06, 0.08, 0.1))
	var frame := "timber" if era != Eras.SCIFI else "metal_dark"
	k.box(frame, I.translated(Vector3(0, 0, 0.02)), Vector3(size.x + 0.1, size.y + 0.1, 0.05))
	k.box("painted", I.translated(Vector3(0, 0, 0.05)), Vector3(size.x, size.y, 0.02), board)
	match era:
		Eras.MEDIEVAL:
			# Iron straps at the corners.
			for sx in [-1.0, 1.0]:
				k.box("iron", I.translated(Vector3(sx * (size.x * 0.5 - 0.06), 0, 0.065)), Vector3(0.05, size.y + 0.12, 0.012))
		Eras.FANTASY:
			k.box("moss", I.translated(Vector3(0, size.y * 0.5 + 0.06, 0.03)), Vector3(size.x + 0.16, 0.05, 0.08))
			k.box("glow_teal", I.translated(Vector3(0, -size.y * 0.5 - 0.035, 0.05)), Vector3(size.x * 0.8, 0.012, 0.01))
		Eras.SCIFI:
			k.box("glow_cyan", I.translated(Vector3(0, size.y * 0.5 + 0.03, 0.05)), Vector3(size.x + 0.06, 0.018, 0.012))
			k.box("glow_cyan", I.translated(Vector3(0, -size.y * 0.5 - 0.03, 0.05)), Vector3(size.x + 0.06, 0.018, 0.012))
	if post:
		k.cylinder("metal" if era == Eras.SCIFI else "timber", I.translated(Vector3(-size.x * 0.5 - 0.1, -at.y - 0.3, -0.02)), 0.05, 0.05, at.y + size.y * 0.5 + 0.3, 8)
		k.cylinder("metal" if era == Eras.SCIFI else "timber", I.translated(Vector3(size.x * 0.5 + 0.1, -at.y - 0.3, -0.02)), 0.05, 0.05, at.y + size.y * 0.5 + 0.3, 8)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Materials.get_mat)
	mi.visibility_range_end = SIGN_RANGE
	node.add_child(mi)
	var text_w := size.x - 0.16
	var left := -size.x * 0.5 + 0.08
	if icon != "":
		var tex := Icons.get_icon(icon)
		if tex:
			var sp := Sprite3D.new()
			sp.texture = tex
			var ih := size.y * 0.8
			sp.pixel_size = ih / float(tex.get_height())
			sp.position = Vector3(left + ih * 0.5, 0, 0.068)
			sp.shaded = false
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp.visibility_range_end = SIGN_RANGE
			node.add_child(sp)
			left += ih + 0.04
			text_w -= ih + 0.04
	var ink := Color(0.98, 0.82, 0.45) if era == Eras.MEDIEVAL else (Color(0.6, 1.0, 0.9) if era == Eras.FANTASY else Color(0.55, 0.92, 1.0))
	var big := _text(label.to_upper(), "title", ink, text_w, size.y * 0.42)
	big.position = Vector3(left + text_w * 0.5, size.y * 0.13, 0.07)
	node.add_child(big)
	if title != "":
		var small := _text(title, "bold", Color(0.95, 0.92, 0.85), text_w, size.y * 0.24)
		small.position = Vector3(left + text_w * 0.5, -size.y * 0.24, 0.07)
		node.add_child(small)

## Text that fits in width w (metres) and is at most h tall.
func _text(s: String, font: String, c: Color, w: float, h: float) -> Label3D:
	var l := Label3D.new()
	l.text = s
	var f := UITheme.font(font)
	if f:
		l.font = f
	l.font_size = 64
	l.outline_size = 0
	l.modulate = c
	l.double_sided = false
	l.shaded = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	var px := 0.0
	if f:
		px = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var ps := h / 64.0
	if px > 0.0:
		ps = minf(ps, w / px)
	l.pixel_size = ps
	l.visibility_range_end = SIGN_RANGE
	return l

# --- Counter and wares ---------------------------------------------------------------------

func _counter(root: Node3D, h: Dictionary, ft: Dictionary, rm: Dictionary) -> void:
	var kind: String = h["kind"]
	var era := int(h["era"])
	var key := "%s|%s|%d" % [h["t"], kind, era]
	if not _meshes.has(key):
		_meshes[key] = _counter_mesh(h["t"], kind, era, ft, rm)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.visibility_range_end = 60.0
	root.add_child(mi)
	# You bump into the counter and the stand.
	var floor_y: float = rm["floor"]
	var face: Vector2 = ft["face"]
	var yaw := atan2(face.x, face.y)
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(ft["width"]), 1.0, 0.55)
	cs.shape = bs
	var cp: Vector2 = ft["counter"]
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(cp.x, floor_y + 0.5, cp.y))
	body.add_child(cs)
	if ft["display"] != Vector2.INF:
		var ds := CollisionShape3D.new()
		var db := BoxShape3D.new()
		db.size = Vector3(0.7, 1.4, 0.5)
		ds.shape = db
		var dp: Vector2 = ft["display"]
		ds.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(dp.x, floor_y + 0.7, dp.y))
		body.add_child(ds)

## The counter, what lies on it and the stand of wares, in room space.
static func _counter_mesh(t: String, kind: String, era: int, ft: Dictionary, rm: Dictionary) -> ArrayMesh:
	var floor_y: float = rm["floor"]
	var face: Vector2 = ft["face"]
	var yaw := atan2(face.x, face.y)
	var cp: Vector2 = ft["counter"]
	var w: float = ft["width"]
	var b := Basis(Vector3.UP, yaw)
	var cx := Transform3D(b, Vector3(cp.x, floor_y, cp.y))
	var k := MeshKit.new(23)
	var I := Transform3D.IDENTITY
	match era:
		Eras.SCIFI:
			k.box("metal_dark", cx * I.translated(Vector3(0, 0.47, 0)), Vector3(w, 0.94, 0.5))
			k.box("metal", cx * I.translated(Vector3(0, 0.965, 0)), Vector3(w + 0.06, 0.05, 0.58))
			k.box("glow_cyan", cx * I.translated(Vector3(0, 0.8, 0.255)), Vector3(w - 0.1, 0.03, 0.01))
		Eras.FANTASY:
			k.box("timber", cx * I.translated(Vector3(0, 0.47, 0)), Vector3(w, 0.94, 0.5))
			k.box("planks", cx * I.translated(Vector3(0, 0.965, 0)), Vector3(w + 0.1, 0.05, 0.6))
			k.box("moss", cx * I.translated(Vector3(0, 0.08, 0.26)), Vector3(w, 0.16, 0.03))
			k.box("glow_teal", cx * I.translated(Vector3(0, 0.75, 0.255)), Vector3(w * 0.7, 0.02, 0.01))
		_:
			k.box("planks", cx * I.translated(Vector3(0, 0.47, 0)), Vector3(w, 0.94, 0.5))
			k.box("timber", cx * I.translated(Vector3(0, 0.965, 0)), Vector3(w + 0.1, 0.05, 0.6))
			for sx in [-1.0, 1.0]:
				k.box("timber", cx * I.translated(Vector3(sx * (w * 0.5 - 0.04), 0.47, 0.255)), Vector3(0.08, 0.94, 0.03))
	var wk := kind if not TownShops.is_guild(kind) else "guild"
	var wares: Array = WARES.get(wk + "~s", WARES[wk]) if era == Eras.SCIFI else WARES[wk]
	var models: Array = []
	var top := floor_y + 0.99
	for e in wares[0]:
		var x: float = float(e[1]) * w / 1.5
		var at := cx * Vector3(x, 0.99, -0.05)
		if ResourceLoader.exists("res://assets/models/%s.gltf" % e[0]):
			models.append([e[0], rad_to_deg(yaw) + float(e[2]), Vector3(at.x, top, at.z), 1.0])
	var stand: String = wares[1]
	if TownShops.is_guild(kind):
		stand = GUILD_STAND.get(kind, stand)
	if ft["display"] != Vector2.INF:
		var dp: Vector2 = ft["display"]
		var dxf := Transform3D(b, Vector3(dp.x, floor_y, dp.y))
		match stand:
			"rack":
				_rack(k, dxf, kind, era)
			"dummy":
				_mannequin(k, dxf, era)
			_:
				if ResourceLoader.exists("res://assets/models/%s.gltf" % stand):
					models.append([stand, rad_to_deg(yaw), dxf.origin, 1.0])
	if kind == "armourer" and era != Eras.SCIFI and ResourceLoader.exists("res://assets/models/props/Shield_Wooden.gltf"):
		# A shield hung on the front of the counter.
		var sp := cx * Vector3(0, 0.0, 0.28)
		models.append(["props/Shield_Wooden", rad_to_deg(yaw), Vector3(sp.x, floor_y + 0.25, sp.z), 0.9])
	var mesh := BuildCatalog.merge_models(models) if not models.is_empty() else ArrayMesh.new()
	k.commit(Materials.get_mat, mesh)
	if stand == "rack" and ft["display"] != Vector2.INF:
		_rack_weapons(mesh, Transform3D(b, Vector3((ft["display"] as Vector2).x, floor_y, (ft["display"] as Vector2).y)), kind, era)
	return mesh

## A shop too small for a counter: the trade's stand, then crates with wares on them,
## each in a spot by the wall (TownShops.fit "props"), turned to face into the room.
func _small_shop(root: Node3D, h: Dictionary, ft: Dictionary, rm: Dictionary) -> void:
	var kind: String = h["kind"]
	var era := int(h["era"])
	var key := "%s|%s|%d|small" % [h["t"], kind, era]
	if not _meshes.has(key):
		_meshes[key] = _small_shop_mesh(kind, era, ft, rm)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.visibility_range_end = 60.0
	root.add_child(mi)
	var floor_y: float = rm["floor"]
	var body := StaticBody3D.new()
	root.add_child(body)
	for sp: Vector2 in ft["props"]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.62, 1.2, 0.62)
		cs.shape = bs
		cs.position = Vector3(sp.x, floor_y + 0.6, sp.y)
		body.add_child(cs)

## How tall a kit model stands (its highest point above its origin).
static func _model_top(model: String) -> float:
	var top := 0.0
	for part in BuildCatalog.model_parts(model):
		var v: PackedVector3Array = (part[1] as Array)[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = part[2]
		for p in v:
			top = maxf(top, (xf * p).y)
	return top

static func _small_shop_mesh(kind: String, era: int, ft: Dictionary, rm: Dictionary) -> ArrayMesh:
	var floor_y: float = rm["floor"]
	var k := MeshKit.new(29)
	var models: Array = []
	var wk := kind if not TownShops.is_guild(kind) else "guild"
	var wares: Array = WARES.get(wk + "~s", WARES[wk]) if era == Eras.SCIFI else WARES[wk]
	var stand: String = wares[1]
	if TownShops.is_guild(kind):
		stand = GUILD_STAND.get(kind, stand)
	var crate := "scifi/Prop_Crate3" if era == Eras.SCIFI else "props/Crate_Wooden"
	var spots: Array = ft["props"]
	var rack_at := Transform3D()
	for i in spots.size():
		var sp: Vector2 = spots[i]
		# Faces the middle of the room.
		var yaw := atan2(-sp.x, -sp.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(sp.x, floor_y, sp.y))
		if i == 0:
			match stand:
				"rack":
					_rack(k, xf, kind, era)
					rack_at = xf
				"dummy":
					_mannequin(k, xf, era)
				_:
					if ResourceLoader.exists("res://assets/models/%s.gltf" % stand):
						models.append([stand, rad_to_deg(yaw), xf.origin, 1.0])
			continue
		if not ResourceLoader.exists("res://assets/models/%s.gltf" % crate):
			continue
		models.append([crate, rad_to_deg(yaw) + 8.0 * i, xf.origin, 1.0])
		# The counter's wares, shared out over the crates.
		var top := floor_y + _model_top(crate)
		var share: Array = wares[0].slice((i - 1) * 2, (i - 1) * 2 + 2)
		for j in share.size():
			var e: Array = share[j]
			var at := xf * Vector3((j - 0.5 * (share.size() - 1)) * 0.28, 0.0, 0.0)
			if ResourceLoader.exists("res://assets/models/%s.gltf" % e[0]):
				models.append([e[0], rad_to_deg(yaw) + float(e[2]), Vector3(at.x, top, at.z), 1.0])
	var mesh := BuildCatalog.merge_models(models) if not models.is_empty() else ArrayMesh.new()
	k.commit(Materials.get_mat, mesh)
	if stand == "rack" and not spots.is_empty():
		_rack_weapons(mesh, rack_at, kind, era)
	return mesh

## A weapon rack: two posts, a bar and a base; the shop's weapons stand in it.
static func _rack(k: MeshKit, xf: Transform3D, kind: String, era: int) -> void:
	var I := Transform3D.IDENTITY
	var mat := "metal_dark" if era == Eras.SCIFI else "timber"
	k.box(mat, xf * I.translated(Vector3(0, 0.06, 0)), Vector3(0.8, 0.12, 0.3))
	for sx in [-1.0, 1.0]:
		k.box(mat, xf * I.translated(Vector3(sx * 0.37, 0.65, -0.08)), Vector3(0.06, 1.3, 0.06))
	k.box(mat, xf * I.translated(Vector3(0, 1.05, -0.08)), Vector3(0.8, 0.05, 0.06))

static func _rack_weapons(mesh: ArrayMesh, xf: Transform3D, kind: String, era: int) -> void:
	var goods: Array = TownShops.goods_of(kind, era).filter(func(t): return ItemDB.def(t).get("kind", "") == "weapon")
	var n := mini(goods.size(), 4)
	for i in n:
		var t: String = goods[i]
		var m := Viewmodel.model(t)
		if m == null:
			continue
		var x := -0.27 + 0.54 * (i / maxf(1.0, n - 1.0))
		var b := Basis.IDENTITY
		if Viewmodel.pointed(t):
			b = Basis(Vector3(1, 0, 0), PI * 0.5) # muzzle up
		var wxf := xf * Transform3D(b, Vector3(x, 0.14, 0.0))
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for vi in v.size():
				v[vi] = wxf * v[vi]
			if nrm.size() == v.size():
				for vi in nrm.size():
					nrm[vi] = (wxf.basis * nrm[vi]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nrm
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_TANGENT] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m.surface_get_material(si))

## An armour stand: a post on a foot with a padded torso, a helm and pauldrons.
static func _mannequin(k: MeshKit, xf: Transform3D, era: int) -> void:
	var I := Transform3D.IDENTITY
	var metal := "metal" if era != Eras.FANTASY else "crystal"
	k.cylinder("timber", xf * I.translated(Vector3(0, 0.0, 0)), 0.22, 0.22, 0.06, 12)
	k.cylinder("timber", xf * I.translated(Vector3(0, 0.06, 0)), 0.03, 0.03, 0.85, 6)
	k.cylinder(metal, xf * I.translated(Vector3(0, 0.9, 0)), 0.17, 0.22, 0.55, 12)
	k.cylinder("cloth" if era != Eras.SCIFI else "metal_dark", xf * I.translated(Vector3(0, 0.82, 0)), 0.2, 0.19, 0.14, 12)
	for sx in [-1.0, 1.0]:
		k.sphere(metal, xf * I.translated(Vector3(sx * 0.24, 1.38, 0)), 0.09, 4, 8, 0.0, 0.7)
	k.sphere(metal, xf * I.translated(Vector3(0, 1.6, 0)), 0.13, 6, 10, 0.0, 1.1)
	if era == Eras.SCIFI:
		k.box("glow_cyan", xf * I.translated(Vector3(0, 1.62, 0.12)), Vector3(0.16, 0.04, 0.02))
	else:
		k.box("metal_dark", xf * I.translated(Vector3(0, 1.6, 0.125)), Vector3(0.12, 0.025, 0.02))
