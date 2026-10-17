class_name ObjectLibrary
## Procedural meshes and collision for every world object type. Meshes are built once
## and shared through MultiMesh instancing.

static var _meshes: Dictionary = {}
static var _shapes: Dictionary = {}

const KIND := {
	"oak": "tree", "pine": "tree", "glowcap": "tree", "crystal_tree": "tree", "solar_mast": "tree",
	"rock": "rock", "iron_vein": "ore", "aether_crystal": "ore", "alloy_scrap": "ore",
	"chest": "cache", "rune_coffer": "cache", "supply_pod": "cache",
	"standing_stone": "marker", "crystal_shard": "marker", "beacon": "marker",
	"cottage": "structure", "watchtower": "structure", "well": "structure",
	"townhouse": "structure", "longhouse": "structure",
	"market_stall": "structure", "fruit_cart": "structure", "wagon": "structure", "barrels": "structure",
	"shrine": "structure", "mushroom_house": "structure", "spire": "structure",
	"hab_dome": "structure", "comms_spire": "structure", "cargo_stack": "structure",
	"hab_block": "structure", "lab_block": "structure", "ops_tower": "structure",
	"solar_farm": "structure", "depot": "structure", "outpost_light": "structure",
	"castle_wall": "structure", "castle_tower": "structure", "castle_gate": "structure", "castle_keep": "structure",
	"crypt_wall": "structure", "crypt_tower": "structure", "crypt_gate": "structure", "crypt_keep": "structure",
	"bunker_wall": "structure", "bunker_tower": "structure", "bunker_gate": "structure", "bunker_keep": "structure",
	"trader": "trader", "alien_ruin": "structure",
	"signpost": "marker", "bridge": "structure", "cave": "structure", "cave_glow": "marker", "cave_crystal": "marker",
	"summit_shrine": "structure", "eyrie": "structure", "sunken_altar": "structure", "fallen_star": "structure",
	"star_wreck": "structure", "titan_bones": "structure", "dolmen": "structure",
	"w_throne": "structure", "w_worldroot": "structure", "w_dreadnought": "structure", "w_gate": "structure",
	"w_column": "structure", "w_crystal": "structure", "w_pylon": "structure", "w_obelisk": "structure",
	"pad_bob": "structure", "pad_challenger": "structure", "pad_dispatcher": "structure", "pad_executioner": "structure",
	"pad_imperial": "structure", "pad_insurgent": "structure", "pad_omen": "structure", "pad_pancake": "structure",
	"pad_spitfire": "structure", "pad_zenith": "structure",
	"world_portal": "structure",
}

## Market and street props in villages and towns, from the kits.
const TOWN_PROPS := {
	"market_stall": [["props/Stall_Empty", 0, Vector3.ZERO, 1.2], ["props/FarmCrate_Apple", 0, Vector3(-0.5, 0.95, 0.1), 1.2],
		["props/FarmCrate_Apple", 10, Vector3(0.45, 0.95, 0.05), 1.2], ["props/Barrel_Apples", 0, Vector3(1.6, 0, 0.3), 1.0]],
	"fruit_cart": [["props/Stall_Cart_Empty", 0, Vector3(0.6, 0, 0), 1.0], ["props/FarmCrate_Apple", 0, Vector3(-0.2, 0.8, 0), 1.0],
		["props/FarmCrate_Apple", -8, Vector3(0.65, 0.8, 0.05), 1.0]],
	"wagon": [["village/Prop_Wagon", 0, Vector3(0, 0, 1.15), 1.0]],
	"barrels": [["props/Barrel", 0, Vector3(-0.4, 0, 0), 1.0], ["props/Barrel", 30, Vector3(0.35, 0, -0.2), 1.0],
		["props/Barrel_Apples", 0, Vector3(0.1, 0, 0.55), 1.0], ["props/Crate_Wooden", 15, Vector3(1.3, 0, 0.1), 1.0]],
}
const TOWN_PROP_SIZE := {"market_stall": Vector3(2.6, 2.7, 1.2), "fruit_cart": Vector3(3.1, 2.7, 1.2),
	"wagon": Vector3(2.0, 1.6, 4.1), "barrels": Vector3(2.6, 1.0, 1.6)}

## What a gatherable object yields.
const YIELD := {
	"oak": "wood", "pine": "wood", "glowcap": "glowberry", "crystal_tree": "glowroot", "solar_mast": "circuitry",
	"rock": "stone", "iron_vein": "iron_ore", "aether_crystal": "aether_crystal", "alloy_scrap": "alloy_scrap",
}

const LABEL := {
	"oak": "Oak", "pine": "Pine", "glowcap": "Glowcap", "crystal_tree": "Crystalbark Tree", "solar_mast": "Xeno Plant",
	"rock": "Boulder", "iron_vein": "Iron Vein", "aether_crystal": "Aether Crystal Cluster", "alloy_scrap": "Alloy Scrap Pile",
	"hab_block": "Hab Block", "lab_block": "Lab Block", "ops_tower": "Ops Tower", "solar_farm": "Solar Farm",
	"depot": "Cargo Depot", "outpost_light": "Floodlight",
	"townhouse": "Town House", "longhouse": "Longhouse", "signpost": "Signpost", "bridge": "Stone Bridge", "cave": "Cave",
	"market_stall": "Market Stall", "fruit_cart": "Fruit Cart", "wagon": "Wagon", "barrels": "Barrels",
	"cave_glow": "Glowing Crystals", "cave_crystal": "Crystals", "chest": "Chest", "rune_coffer": "Rune Coffer", "supply_pod": "Supply Pod", "trader": "Trader", "alien_ruin": "Alien Ruin",
	"world_portal": "Ancient Portal",
}

static func kind(t: String) -> String:
	if BuildCatalog.is_built(t):
		return "built"
	if EasterEggs.has(t) or ZoneBorder.has(t) or t == WonderSite.DEBRIS:
		return "structure"
	return KIND.get(t, "marker")

static func label(t: String) -> String:
	if BuildCatalog.is_built(t):
		return BuildCatalog.label(t)
	if Stronghold.has(t):
		return Stronghold.LABELS[t]
	if Landmark.has(t):
		return Landmark.LABELS[t]
	if EasterEggs.has(t):
		return EasterEggs.label(t)
	if WonderSite.has(t):
		return WonderSite.label(t)
	if ShipPad.has(t):
		return ShipPad.label(t)
	if ZoneBorder.has(t):
		return ZoneBorder.LABELS[t]
	if t == WonderSite.DEBRIS:
		return "Dreadnought Wreckage"
	return LABEL.get(t, t.capitalize())

static var _lock := Mutex.new()
const MAX_MESHES := 400

## The mesh key of a placed object: its type, species and variant. Objects from older
## snapshots have no species and use the classic mesh for their type.
static func mesh_key(o: Dictionary) -> String:
	var sp: int = o.get("sp", 0)
	if EasterEggs.has(o["t"]):
		return EasterEggs.mesh_key(o)
	if sp == 0:
		if WonderSite.has(o["t"]):
			return WonderSite.mesh_key(o)
		return o["t"]
	return "%s#%d#%d" % [o["t"], sp, int(o.get("v", 0))]

static func label_of(o: Dictionary) -> String:
	return Flora.species_name(o["t"], int(o.get("sp", 0)))

## Thread-safe; meshes are built on chunk worker threads. Unused species meshes are
## evicted when the cache grows, so endless exploration does not grow memory forever.
static func get_mesh(key: String) -> ArrayMesh:
	_lock.lock()
	var m = _meshes.get(key)
	_lock.unlock()
	if m != null:
		return m
	var mesh := _build_mesh(key)
	_lock.lock()
	if _meshes.size() > MAX_MESHES:
		for k2 in _meshes.keys():
			if k2.contains("#") and (_meshes[k2] as ArrayMesh).get_reference_count() <= 1:
				_meshes.erase(k2)
	if _meshes.has(key):
		mesh = _meshes[key]
	else:
		_meshes[key] = mesh
	_lock.unlock()
	return mesh

static func _build_mesh(key: String) -> ArrayMesh:
	if BuildCatalog.is_built(key):
		return BuildCatalog.mesh(BuildCatalog.id_of(key))
	if EasterEggs.owns_key(key):
		return EasterEggs.build(key)
	if key.ends_with("~in"):
		var room := key.trim_suffix("~in")
		return KitHouse.interior(room) if KitHouse.has(room) else Interiors.interior(room)
	if key.ends_with("~glow"):
		var room := key.trim_suffix("~glow")
		return KitHouse.glow(room) if KitHouse.has(room) else Interiors.glow(room)
	if KitHouse.has(key):
		return KitHouse.build(key)
	if Interiors.rebuilds(key):
		return Interiors.build(key)
	if KitBase.has(key):
		return KitBase.build(key)
	if Stronghold.has(key):
		return Stronghold.build(key)
	if Landmark.has(key):
		return Landmark.build(key)
	if ZoneBorder.has(key):
		return ZoneBorder.build(key)
	if WonderSite.owns_key(key):
		return WonderSite.build_key(key)
	if ShipPad.has(key):
		return ShipPad.build(key)
	if key == WorldPortal.TYPE:
		return WorldPortal.build()
	if TOWN_PROPS.has(key):
		return BuildCatalog.merge_models(TOWN_PROPS[key])
	if key.contains("#"):
		var parts := key.split("#")
		if parts[0] == "bridge":
			return Bridge.build(int(parts[1]))
		if parts[0] == "cave":
			return Cave.build(int(parts[1]))
		if parts[0] == "cave_glow" or parts[0] == "cave_crystal":
			return Caves.build_glow(int(parts[1]), int(parts[2]), parts[0] == "cave_glow")
		if parts[0] == WonderSite.DEBRIS:
			return WonderSite.debris(int(parts[1]), int(parts[2]))
		var kit := MeshKit.new(int(parts[1]) & 0xFFFF)
		if parts[0] == "under":
			var ku := KitFlora.build_under(int(parts[1]), int(parts[2]))
			if ku != null:
				return ku
			var hu := HiFlora.under(int(parts[1]), int(parts[2]))
			if hu != null:
				return hu
			Flora.build_under(kit, int(parts[1]), int(parts[2]))
			return kit.commit(Materials.get_mat)
		var rt := RealTree.build(parts[0], int(parts[1]), int(parts[2]))
		if rt != null:
			return rt
		var hm := HiFlora.build(parts[0], int(parts[1]), int(parts[2]))
		if hm != null:
			return hm
		var km := KitFlora.build(parts[0], int(parts[1]), int(parts[2]))
		if km != null:
			return km
		if Flora.build(kit, parts[0], int(parts[1]), int(parts[2])):
			return kit.commit(Materials.get_mat)
		key = parts[0]
	var t := key
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var I := Transform3D.IDENTITY
	match t:
		"oak": _oak(k)
		"pine": _pine(k)
		"glowcap": _glowcap(k)
		"crystal_tree": _crystal_tree(k)
		"solar_mast": _solar_mast(k)
		"rock": k.sphere("stone", I.translated(Vector3(0, 0.35, 0)), 1.0, 9, 14, 0.35, 0.7)
		"iron_vein":
			k.sphere("stone_dark", I.translated(Vector3(0, 0.4, 0)), 1.1, 9, 14, 0.3, 0.75)
			for n in 7:
				var a := n * 2.4
				k.sphere("rust", Transform3D(Basis(), Vector3(cos(a) * 0.7, 0.5 + (n % 3) * 0.2, sin(a) * 0.7)), 0.28, 5, 7, 0.4)
		"aether_crystal":
			k.sphere("stone_dark", I.translated(Vector3(0, 0.15, 0)), 0.9, 7, 12, 0.3, 0.45)
			for n in 7:
				var a := n * 0.9
				var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.15 + (n % 3) * 0.2)
				k.crystal("crystal", Transform3D(b, Vector3(cos(a) * 0.3, 0.2, sin(a) * 0.3)), 0.16 + (n % 2) * 0.08, 0.9 + (n % 4) * 0.45)
		"alloy_scrap": _alloy_scrap(k)
		"chest": return BuildCatalog.merge_models([["props/Chest_Wood", 0, Vector3.ZERO, 1.0]])
		"rune_coffer":
			k.box("rune_stone", I.translated(Vector3(0, 0.4, 0)), Vector3(1.3, 0.8, 0.8))
			k.box("rune_stone", I.translated(Vector3(0, 0.88, 0)), Vector3(1.4, 0.16, 0.9))
			for n in 3:
				k.box("glow_teal", I.translated(Vector3(-0.4 + n * 0.4, 0.45, 0.41)), Vector3(0.18, 0.3, 0.02))
		"supply_pod": return BuildCatalog.merge_models([["scifi/Prop_Chest", 0, Vector3.ZERO, 1.0]])
		"standing_stone": return HiFlora.build("standing_stone", 1, 0)
		"crystal_shard": return HiFlora.build("crystal_shard", 1, 0)
		"beacon":
			# A navigation pylon: a pipe column on a plated plinth, a light at the top.
			var bm := BuildCatalog.merge_models([["scifi/Column_Pipes", 0, Vector3(0, 0.3, 0), 1.0],
				["scifi/Prop_AccessPoint", 0, Vector3(0.62, 0.0, 0), 1.0], ["scifi/Prop_Light_Floor", 0, Vector3(0, 0.3, 0.85), 0.8],
				["scifi/Prop_Light_Floor", 180, Vector3(0, 0.3, -0.85), 0.8], ["scifi/Prop_Crate3", 20, Vector3(0.75, 0.6, 0.75), 0.55]])
			k.box("metal_dark", I, Vector3(2.4, 0.6, 2.4))
			k.box("metal", I.translated(Vector3(0, 0.31, 0)), Vector3(2.2, 0.02, 2.2))
			k.cylinder("metal_dark", I.translated(Vector3(0, 5.25, 0)), 0.52, 0.3, 0.3, 10)
			k.sphere("glow_red", I.translated(Vector3(0, 5.75, 0)), 0.22, 5, 8)
			k.box("glow_cyan", I.translated(Vector3(0, 3.6, 0)), Vector3(0.96, 0.06, 0.96))
			return k.commit(Materials.get_mat, bm)
		"signpost":
			# A weathered post with an arrow pointing down the road (local -z) and one back.
			k.cylinder("timber", I, 0.09, 0.08, 2.6, 6)
			k.box("timber", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 2.2, -0.45)), Vector3(1.1, 0.24, 0.05))
			k.box("timber", Transform3D(Basis(Vector3.UP, PI / 2).rotated(Vector3.UP, 0.25), Vector3(0, 1.85, 0.4)), Vector3(0.9, 0.22, 0.05))
			k.box("stone", I.translated(Vector3(0, 0.12, 0)), Vector3(0.5, 0.25, 0.5))
		"cottage": _cottage(k)
		"well": _well(k)
		"spire": _spire(k)
		"comms_spire": _comms_spire(k)
		"cargo_stack": _cargo_stack(k)
		"trader": _trader(k)
		"clutter_0", "clutter_1", "clutter_2":
			# Kit pebbles, flowers and fungi; the procedural patch only if the kit is missing.
			var era := int(key.substr(8))
			var km := KitFlora.build_clutter(era)
			if km.get_surface_count() > 0:
				if era == Eras.SCIFI:
					var b := Basis.from_euler(Vector3(0.15, 2.1, -0.1))
					k.box("rust", Transform3D(b, Vector3(0.25, 0.015, -0.2)), Vector3(0.22, 0.02, 0.12))
					return k.commit(Materials.get_mat, km)
				if era == Eras.FANTASY:
					k.crystal("crystal", I.translated(Vector3(0.3, -0.02, -0.25)), 0.025, 0.16, 5)
					return k.commit(Materials.get_mat, km)
				return km
			[_clutter_medieval, _clutter_fantasy, _clutter_scifi][era].call(k)
		_:
			k.box("stone", I.translated(Vector3(0, 0.5, 0)), Vector3.ONE)
	return k.commit(Materials.get_mat)

## Collision for one placed object, fitted to its own species: a trunk-sized cylinder for
## trees and a hull of the actual mesh for rocks and ore. A loose generic shape let a
## boulder's collider swallow the trunk of a tree beside it, so swinging at the tree
## mined the rock instead.
static func shape_of(o: Dictionary) -> Array:
	var t: String = o["t"]
	var sp: int = o.get("sp", 0)
	var k := kind(t)
	if t == "bridge" and sp != 0:
		return Bridge.shape(sp)
	if Interiors.has(t):
		# A keep or bunker you walk into: its rooms collide as Interiors builds them.
		_lock.lock()
		var rs = _shapes.get(t)
		_lock.unlock()
		if rs == null:
			rs = Interiors.shape(t)
			_lock.lock()
			_shapes[t] = rs
			_lock.unlock()
		return rs
	if Stronghold.has(t) or WonderSite.has(t) or ZoneBorder.open(t):
		# Walk through gates and doorways: collide with the real geometry (a wonder's
		# without its beam of light, a crashed dreadnought's as it lies).
		var sk := WonderSite.solid_key(o) if WonderSite.has(t) else t
		_lock.lock()
		var fs = _shapes.get(sk)
		_lock.unlock()
		if fs == null:
			fs = [get_mesh(sk).create_trimesh_shape(), Vector3.ZERO]
			_lock.lock()
			_shapes[sk] = fs
			_lock.unlock()
		return fs
	if t == WorldPortal.TYPE:
		_lock.lock()
		var ps = _shapes.get(t)
		_lock.unlock()
		if ps == null:
			ps = [get_mesh(t).create_trimesh_shape(), Vector3.ZERO]
			_lock.lock()
			_shapes[t] = ps
			_lock.unlock()
		return ps
	if (t == "alien_ruin" or t == WonderSite.DEBRIS) and sp != 0:
		# Collide with the relic itself: walk between a xenolith circle's blades, up to its
		# core, instead of into a box around the whole thing.
		var rk := mesh_key(o)
		_lock.lock()
		var rs = _shapes.get(rk)
		_lock.unlock()
		if rs == null:
			rs = [get_mesh(rk).create_trimesh_shape(), Vector3.ZERO]
			_lock.lock()
			_shapes[rk] = rs
			_lock.unlock()
		return rs
	if t == "cave" and sp != 0:
		var key := mesh_key(o)
		_lock.lock()
		var have = _shapes.get(key)
		_lock.unlock()
		if have == null:
			have = Cave.shape(sp)
			_lock.lock()
			_shapes[key] = have
			_lock.unlock()
		return have
	if sp == 0 or not (k == "tree" or k == "rock" or k == "ore"):
		return get_shape(t)
	var key := mesh_key(o)
	_lock.lock()
	var cached = _shapes.get(key)
	_lock.unlock()
	if cached != null:
		return cached
	var out: Array
	if k == "tree":
		var p := Flora.species(t, sp)
		var r := 0.45
		var h := 6.0
		match t:
			"oak": r = float(p["girth"]) * 1.1; h = float(p["height"]) * 0.8
			"pine": r = float(p["width"]) * 0.12 + 0.14; h = float(p["height"]) * 0.7
			"glowcap": r = float(p["stem_r"]) * 1.1; h = float(p["height"]) * 0.8
			"crystal_tree": r = float(p["girth"]) * 1.2; h = float(p["height"]) * 0.8
		var c := CylinderShape3D.new()
		c.radius = clampf(r, 0.22, 0.9)
		c.height = clampf(h, 1.2, 9.0)
		out = [c, Vector3(0, c.height * 0.5, 0)]
	else:
		var m := get_mesh(key)
		var hull: Shape3D = m.create_convex_shape(true, true) if m else null
		out = [hull, Vector3.ZERO] if hull else get_shape(t)
	_lock.lock()
	_shapes[key] = out
	_lock.unlock()
	return out

static var _foot: Dictionary = {}

## A building's ground plan (local x/z, unscaled): the box its mesh fills, so grass,
## flowers and trees keep out of it. Thread-safe like get_mesh.
static func footprint(o: Dictionary) -> Rect2:
	var key := mesh_key(o)
	_lock.lock()
	var f = _foot.get(key)
	_lock.unlock()
	if f == null:
		var a := get_mesh(key).get_aabb()
		f = Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		_lock.lock()
		_foot[key] = f
		_lock.unlock()
	return f

## Whether nothing should grow inside type t: buildings, stalls, traders and anything
## the player built, but not bridges (the ground under them is open) or caves.
static func keeps_out(t: String) -> bool:
	var k := kind(t)
	return (k == "structure" or k == "trader" or k == "built") and t != "bridge" and t != "cave"

## Collision: [shape, local offset].
static func get_shape(t: String) -> Array:
	if _shapes.has(t):
		return _shapes[t]
	if KitHouse.has(t):
		_shapes[t] = KitHouse.shape(t)
		return _shapes[t]
	if Interiors.has(t):
		_shapes[t] = Interiors.shape(t)
		return _shapes[t]
	if ShipPad.has(t):
		_shapes[t] = ShipPad.shape(t)
		return _shapes[t]
	var s: Shape3D
	var off := Vector3.ZERO
	match kind(t):
		"tree":
			var c := CylinderShape3D.new()
			c.radius = 0.45
			c.height = 6.0
			s = c
			off = Vector3(0, 3.0, 0)
		"rock", "ore":
			var sp := SphereShape3D.new()
			sp.radius = 1.0
			s = sp
			off = Vector3(0, 0.4, 0)
		"cache":
			var b := BoxShape3D.new()
			b.size = Vector3(1.4, 1.0, 1.0)
			s = b
			off = Vector3(0, 0.5, 0)
		"trader":
			var b := BoxShape3D.new()
			b.size = Vector3(3.0, 2.6, 2.2)
			s = b
			off = Vector3(0, 1.3, 0)
		"structure":
			var b := BoxShape3D.new()
			var sz: Vector3 = KitHouse.size_of(t) if KitHouse.has(t) else KitBase.size_of(t) if KitBase.has(t) else Landmark.SIZE[t] if Landmark.has(t) else ZoneBorder.SIZE[t] if ZoneBorder.SIZE.has(t) else EasterEggs.SIZE[t] if EasterEggs.has(t) else TOWN_PROP_SIZE.get(t, Vector3(7, 6, 6))
			match t:
				"spire", "comms_spire": sz = Vector3(4.5, 16, 4.5)
				"well": sz = Vector3(2.4, 2.5, 2.4)
				"cargo_stack": sz = Vector3(6.2, 5.2, 2.6)
				"alien_ruin": sz = Vector3(6, 7, 6)
			b.size = sz
			s = b
			off = Vector3(0, sz.y * 0.5, 0)
		_:
			var c := CylinderShape3D.new()
			c.radius = 0.45
			c.height = 3.5
			s = c
			off = Vector3(0, 1.75, 0)
	_shapes[t] = [s, off]
	return _shapes[t]

# --- Builders ------------------------------------------------------------------

static func _oak(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("bark", I, 0.42, 0.26, 4.2, 10, false, 0.12, 4)
	for b in 3:
		var a := b * 2.1
		var dir := Vector3(cos(a), 0.9, sin(a)).normalized()
		var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))
		k.cylinder("bark", Transform3D(basis, Vector3(0, 3.2, 0)), 0.18, 0.08, 2.2, 6, false)
	var blobs := [Vector3(0, 5.6, 0), Vector3(1.4, 5.0, 0.4), Vector3(-1.2, 5.2, -0.6), Vector3(0.2, 5.0, 1.4), Vector3(-0.3, 6.6, 0.2), Vector3(0.6, 4.7, -1.3)]
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for n in blobs.size():
		var rad := 1.9 - n * 0.12
		# Dense inner core so the canopy reads as solid, then leaf cards for the silhouette.
		k.sphere("leaf", I.translated(blobs[n]), rad * 0.72, 6, 9, 0.4, 0.85, Color(0.55, 0.6, 0.5))
		_leaf_cards(k, "leaf_card", blobs[n], rad, 34, r, 1.25)

static func _leaf_cards(k: MeshKit, mat: String, center: Vector3, radius: float, count: int, r: RandomNumberGenerator, size: float) -> void:
	for c in count:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.6, 1), r.randf_range(-1, 1)).normalized()
		var p := center + d * radius * r.randf_range(0.6, 1.0)
		var b := Basis.looking_at(-d if absf(d.y) < 0.95 else Vector3(0.01, -d.y, 0.0), Vector3.UP).rotated(d, r.randf() * TAU)
		var shade := r.randf_range(0.8, 1.1)
		k.card(mat, Transform3D.IDENTITY, p, b, size * r.randf_range(0.8, 1.3), size * r.randf_range(0.8, 1.3), d * 0.8, Color(shade, shade, shade))

static func _pine(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("bark_pine", I, 0.32, 0.12, 8.0, 8, false, 0.08, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for n in 6:
		var y := 2.0 + n * 1.15
		var r := 2.5 - n * 0.38
		k.cylinder("needle", I.translated(Vector3(0, y, 0)), r * 0.75, 0.05, 2.2, 10, true, 0.25, 2, Color(0.6, 0.65, 0.6))
		# Drooping needle cards around each tier.
		for c in 18:
			var a := TAU * c / 18 + rng.randf() * 0.3
			var out := Vector3(cos(a), 0, sin(a))
			var p := Vector3(0, y + 0.5, 0) + out * r * rng.randf_range(0.45, 0.8)
			var b := Basis.looking_at(out, Vector3.UP).rotated(out.cross(Vector3.UP).normalized(), 0.5 + rng.randf() * 0.4)
			k.card("needle_card", I, p, b, r * 0.9, 1.5, Vector3.UP * 0.5)
	k.card("needle_card", I, Vector3(0, 9.1, 0), Basis(), 0.9, 1.6)
	k.card("needle_card", I, Vector3(0, 9.1, 0), Basis(Vector3.UP, PI * 0.5), 0.9, 1.6)

static func _glowcap(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("stem", I, 0.55, 0.38, 5.0, 12, false, 0.1, 4)
	k.sphere("cap_violet", I.translated(Vector3(0, 4.9, 0)), 3.2, 10, 18, 0.12, 0.45, Color.WHITE, true)
	for n in 9:
		var a := n * 0.7
		k.sphere("glow_violet", I.translated(Vector3(cos(a) * 2.6, 4.75, sin(a) * 2.6)), 0.12, 4, 6)
	for n in 4:
		var a := n * 1.6 + 0.3
		k.sphere("cap_teal", I.translated(Vector3(cos(a) * 1.2, 0.3, sin(a) * 1.2)), 0.45, 6, 8, 0.1, 0.5, Color.WHITE, true)

static func _crystal_tree(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("bark_pine", I, 0.36, 0.16, 5.0, 8, false, 0.25, 5)
	k.sphere("moss", I.translated(Vector3(0, 5.6, 0)), 1.4, 7, 10, 0.5, 0.7)
	var r := RandomNumberGenerator.new()
	r.seed = 13
	_leaf_cards(k, "moss_card", Vector3(0, 5.6, 0), 1.9, 40, r, 1.1)
	for n in 8:
		var a := n * 0.785
		var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.6 - (n % 2) * 0.3)
		k.crystal("crystal", Transform3D(b, Vector3(cos(a) * 0.9, 5.2 + (n % 3) * 0.4, sin(a) * 0.9)), 0.12, 1.2 + (n % 3) * 0.4)

static func _solar_mast(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.box("metal_dark", I.translated(Vector3(0, 0.2, 0)), Vector3(1.6, 0.4, 1.6))
	k.cylinder("metal", I, 0.16, 0.12, 6.0, 8)
	var tilt := Basis(Vector3(1, 0, 0), -0.5)
	k.box("metal_dark", Transform3D(tilt, Vector3(0, 6.1, 0)), Vector3(3.4, 0.08, 2.0))
	k.box("glass", Transform3D(tilt, Vector3(0, 6.15, 0)), Vector3(3.2, 0.04, 1.85))
	k.sphere("glow_red", I.translated(Vector3(0, 6.9, 0)), 0.09, 4, 6)
	k.box("glow_cyan", I.translated(Vector3(0, 2.0, 0.17)), Vector3(0.06, 1.2, 0.02))

static func _alloy_scrap(k: MeshKit) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for n in 9:
		var b := Basis.from_euler(Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6)))
		var p := Vector3(r.randf_range(-0.9, 0.9), r.randf_range(0.1, 0.7), r.randf_range(-0.9, 0.9))
		var sz := Vector3(r.randf_range(0.3, 1.2), r.randf_range(0.05, 0.3), r.randf_range(0.3, 1.0))
		k.box("metal" if n % 3 else "painted", Transform3D(b, p), sz, Color(0.8, 0.5, 0.2) if n % 3 == 0 else Color.WHITE)
	k.box("glow_cyan", Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.2, 0.75, 0.1)), Vector3(0.4, 0.05, 0.05))

static func _cottage(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	var w := 6.0
	var d := 5.0
	k.box("stone", I.translated(Vector3(0, 0.4, 0)), Vector3(w + 0.3, 0.8, d + 0.3))
	k.box("plaster", I.translated(Vector3(0, 2.2, 0)), Vector3(w, 2.8, d))
	# Timber framing.
	for x in [-w / 2, -w / 6, w / 6, w / 2]:
		for z in [-d / 2 - 0.02, d / 2 + 0.02]:
			k.box("timber", I.translated(Vector3(x, 2.2, z)), Vector3(0.22, 2.8, 0.08))
	for z in [-d / 2 - 0.02, d / 2 + 0.02]:
		k.box("timber", I.translated(Vector3(0, 3.55, z)), Vector3(w, 0.2, 0.08))
		k.box("timber", I.translated(Vector3(0, 0.9, z)), Vector3(w, 0.2, 0.08))
	# Pitched thatch roof (two slabs) and gables.
	var pitch := 0.62
	for s in [-1, 1]:
		var b := Basis(Vector3(1, 0, 0), s * pitch)
		k.box("thatch", Transform3D(b, Vector3(0, 4.45, s * d * 0.27)), Vector3(w + 0.9, 0.35, d * 0.68))
	for x in [-w / 2, w / 2]:
		var g := 1.0 if x > 0 else -1.0
		k.quad("plaster", I, Vector3(x, 3.6, d / 2 * g), Vector3(x, 3.6, -d / 2 * g), Vector3(x, 5.3, 0), Vector3(x, 5.3, 0))
	# Door, windows (warm glow at night), chimney.
	k.box("timber", I.translated(Vector3(0.8, 1.7, d / 2 + 0.05)), Vector3(1.1, 2.0, 0.1))
	for x in [-1.8, 2.3]:
		k.box("glow_warm", I.translated(Vector3(x, 2.4, d / 2 + 0.04)), Vector3(0.8, 0.8, 0.04))
	k.box("glow_warm", I.translated(Vector3(-1.5, 2.4, -d / 2 - 0.04)), Vector3(0.8, 0.8, 0.04))
	k.box("cobble", I.translated(Vector3(-w / 2 + 0.8, 4.4, -0.8)), Vector3(0.8, 3.0, 0.8))

static func _well(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("cobble", I, 1.1, 1.1, 0.9, 14, false, 0.02)
	k.cylinder("stone_dark", I.translated(Vector3(0, 0.85, 0)), 0.9, 0.9, 0.02, 14)
	for x in [-0.95, 0.95]:
		k.box("timber", I.translated(Vector3(x, 1.4, 0)), Vector3(0.15, 2.0, 0.15))
	k.box("timber", I.translated(Vector3(0, 2.35, 0)), Vector3(2.2, 0.15, 0.15))
	for s in [-1, 1]:
		k.box("slate", Transform3D(Basis(Vector3(1, 0, 0), s * 0.7), Vector3(0, 2.7, s * 0.45)), Vector3(2.4, 0.08, 1.3))

static func _spire(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	for n in 5:
		var b := Basis(Vector3.UP, n * 0.35)
		k.cylinder("rune_stone", Transform3D(b, Vector3(0, n * 3.0, 0)), 1.8 - n * 0.3, 1.5 - n * 0.3, 3.0, 6)
	k.crystal("crystal_violet", I.translated(Vector3(0, 15.0, 0)), 0.6, 3.5)
	for n in 3:
		k.box("glow_violet", Transform3D(Basis(Vector3.UP, n * 2.1), Vector3(0, 4 + n * 3.0, 0)).translated_local(Vector3(0, 0, 1.55 - n * 0.3)), Vector3(0.25, 1.2, 0.05))

static func _comms_spire(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	k.box("metal_dark", I.translated(Vector3(0, 0.3, 0)), Vector3(4, 0.6, 4))
	for c in [Vector3(-1.2, 0, -1.2), Vector3(1.2, 0, -1.2), Vector3(1.2, 0, 1.2), Vector3(-1.2, 0, 1.2)]:
		var top := Vector3(c.x * 0.2, 16.0, c.z * 0.2)
		var dir: Vector3 = top - c
		var b := Basis(Vector3.UP.cross(dir.normalized()).normalized(), Vector3.UP.angle_to(dir))
		k.cylinder("metal", Transform3D(b, c + Vector3(0, 0.6, 0)), 0.12, 0.08, dir.length(), 6)
	for y in [4.0, 8.0, 12.0]:
		var hw: float = 1.2 * (1.0 - y / 20.0)
		k.box("glow_cyan", I.translated(Vector3(0, y, 0)), Vector3(hw * 2, 0.08, hw * 2))
	var dish := Transform3D(Basis(Vector3(1, 0, 0), -1.0), Vector3(0, 12.5, 0.6))
	k.sphere("panel", dish, 1.4, 6, 14, 0.0, 0.35, Color.WHITE, true)
	k.sphere("glow_red", I.translated(Vector3(0, 16.4, 0)), 0.18, 4, 6)

static func _cargo_stack(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	var cols := [Color(0.75, 0.32, 0.15), Color(0.15, 0.35, 0.6), Color(0.8, 0.7, 0.2), Color(0.3, 0.5, 0.35)]
	var placements := [Vector3(-1.55, 1.25, 0), Vector3(1.55, 1.25, 0), Vector3(0, 3.75, 0)]
	for n in placements.size():
		var p: Vector3 = placements[n]
		k.box("painted", I.translated(p), Vector3(3.0, 2.5, 2.4), cols[n % cols.size()])
		for x in [-1.2, -0.6, 0.0, 0.6, 1.2]:
			k.box("painted", I.translated(p + Vector3(x, 0, 1.22)), Vector3(0.1, 2.3, 0.04), cols[n % cols.size()].darkened(0.2))
		k.box("glow_white", I.translated(p + Vector3(0, 1.0, 1.23)), Vector3(0.5, 0.06, 0.03))

static func _trader(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	# Market stall: counter, posts, canvas.
	k.box("planks", I.translated(Vector3(0, 0.55, 0.6)), Vector3(2.6, 1.1, 0.7))
	for c in [Vector3(-1.3, 0, -0.9), Vector3(1.3, 0, -0.9), Vector3(-1.3, 0, 0.95), Vector3(1.3, 0, 0.95)]:
		k.box("timber", I.translated(c + Vector3(0, 1.25, 0)), Vector3(0.12, 2.5, 0.12))
	k.box("cloth", Transform3D(Basis(Vector3(1, 0, 0), 0.25), Vector3(0, 2.6, 0.05)), Vector3(3.0, 0.05, 2.4))
	# The trader is a living NPC standing behind the counter (see NPCGen).
	# Wares on the counter.
	for n in 5:
		k.box("gold" if n % 2 else "glow_warm", I.translated(Vector3(-1.0 + n * 0.5, 1.18, 0.6)), Vector3(0.2, 0.16, 0.2))

# --- Ground clutter (small, many, near the player only) -------------------------------

static func _clutter_medieval(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = 21
	for n in 3:
		k.sphere("stone", I.translated(Vector3(r.randf_range(-0.4, 0.4), 0.02, r.randf_range(-0.4, 0.4))), r.randf_range(0.06, 0.16), 4, 6, 0.4, 0.6)
	var petals := [Color(0.95, 0.92, 0.85), Color(0.95, 0.8, 0.2), Color(0.75, 0.35, 0.8), Color(0.9, 0.25, 0.2)]
	for n in 5:
		var p := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
		var h := r.randf_range(0.18, 0.35)
		k.cylinder("leaf", I.translated(p), 0.008, 0.006, h, 4, false)
		k.sphere("petal_w", I.translated(p + Vector3(0, h, 0)), 0.035, 3, 5, 0.0, 0.5, petals[n % petals.size()])

static func _clutter_fantasy(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = 22
	for n in 4:
		var p := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
		var h := r.randf_range(0.08, 0.22)
		k.cylinder("stem", I.translated(p), 0.012, 0.01, h, 5, false)
		k.sphere("glow_teal" if n % 2 else "glow_violet", I.translated(p + Vector3(0, h, 0)), r.randf_range(0.03, 0.06), 4, 7, 0.0, 0.5, Color.WHITE, true)
	for n in 2:
		k.crystal("crystal", I.translated(Vector3(r.randf_range(-0.4, 0.4), -0.02, r.randf_range(-0.4, 0.4))), 0.03, r.randf_range(0.1, 0.25), 5)

## Sci-fi ground: weathered grit and the odd dull fragment, no glowing specks.
static func _clutter_scifi(k: MeshKit) -> void:
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = 23
	for n in 4:
		k.sphere("stone_dark", I.translated(Vector3(r.randf_range(-0.45, 0.45), 0.01, r.randf_range(-0.45, 0.45))), r.randf_range(0.05, 0.13), 4, 6, 0.4, 0.6)
	var b := Basis.from_euler(Vector3(0.15, r.randf() * TAU, -0.1))
	k.box("rust", Transform3D(b, Vector3(0.25, 0.015, -0.2)), Vector3(0.22, 0.02, 0.12))
