class_name Corpses
extends Node3D
## The bodies of animals and people the player kills. Each lies where it fell, kept in
## its chunk's snapshot ("corpses": id -> record) like every other change to the world,
## until it is emptied or rots away (CorpseLoot.gone_after). Carcasses are butchered
## (hold Interact) for meat, hide or fur, bone and the like; people's bodies are searched
## for what they wore and carried, and taking from one in town is theft if anyone sees.
##
## Record: kind ("animal" | "person"), p (chunk-local Vector3), yaw, day (of death),
## name, era; animals: sp, butchered, items (once butchered, what is left on it);
## people: who (NPC id), body, job, gear (what they wore), items, purse.
## The player's own body leaves no corpse but a bag (kind "bag", see DeathBag), kept the
## same way and opened the same way, marked on its owner's map.

## A dropped bag changed: dropped, taken from, or gone (rec is then {}). For a multiplayer
## server to pass on to the other players.
signal bag_changed(chunk: Vector2i, id: String, rec: Dictionary)

const RADIUS := 2 ## chunks around the player whose bodies are drawn

var streamer: ChunkStreamer
var player: Node3D
var npcs: NPCManager
var _shown: Dictionary = {} ## key -> {node, cn, id}
var _fresh: Dictionary = {} ## ids that should play their fall when first drawn
var _scan := 0.0
var _crime_t := -99.0

static func key_of(k: Vector2i, id: String) -> String:
	return "%d,%d|%s" % [k.x, k.y, id]

# --- Recording deaths ------------------------------------------------------------------

## The animal `c` was just killed: its carcass stays where it fell.
func add_animal(c: Creature) -> void:
	var at := c.global_position
	var rec := {"kind": "animal", "sp": c.sp, "era": c.era, "yaw": c.rotation.y, "name": c.label(), "butchered": false}
	if c.p["plan"] == "bird":
		# Fliers drop to the ground.
		var g: float = npcs.ground(at.x, at.z) if npcs else NAN
		if not is_nan(g):
			at.y = maxf(g, Water.LEVEL - 0.6)
	_put(at, "a" + c.id, rec)

## Person `n` was just killed: their body keeps everything they had on them.
func add_person(n: NPC) -> void:
	var rec := n.rec
	NPCSocial.ensure(rec)
	var at := n.global_position
	var k := ChunkStreamer.chunk_of(at)
	var inv := Inventory.new(CorpseLoot.SLOTS)
	for it in CorpseLoot.person_items(rec, NPCSocial.pockets(rec), Game.origin_here("looted", int(rec["era"]), k)):
		inv.add(it)
	if randf() < Treasure.PERSON_CHANCE:
		inv.add(Treasure.make_map(maxi(int(rec["era"]), 0), Game.origin_here("looted", int(rec["era"]), k)))
	var body := {"kind": "person", "era": int(rec["era"]), "yaw": n.rotation.y, "name": rec["name"],
		"who": rec["id"], "body": (rec["body"] as Dictionary).duplicate(true), "job": rec["job"],
		"gear": (rec.get("gear", {}) as Dictionary).duplicate(true), "items": inv.to_data(), "purse": int(rec.get("purse", 0))}
	# It is all on the body now, not with the record of who they were.
	NPCSocial.lift_marks(rec, int(rec.get("purse", 0)))
	rec["gear"] = {}
	rec["held"] = null
	rec["pockets"] = []
	_put(at, "p" + String(rec["id"]), body)

## You died at `at`: everything on you goes into a bag there (on dry ground, if you went
## down in the water), and your map marks the spot. Returns the bag's key, "" if its
## ground had not loaded.
func drop_bag(at: Vector3, rec: Dictionary) -> String:
	var spot := bag_spot(at)
	var k := ChunkStreamer.chunk_of(spot)
	var id := "b%s_%d" % [String(rec.get("owner", "")), int(rec.get("unix", 0.0) * 1000.0) % 1000000000]
	rec["yaw"] = randf() * TAU
	if not _put(spot, id, rec):
		spot = at
		k = ChunkStreamer.chunk_of(spot)
		if not _put(spot, id, rec):
			return ""
	if DeathBag.is_mine(rec, Game.my_id()):
		for m in Game.markers.list.duplicate():
			if m["kind"] == "death" and m.get("name", "") == "Last death":
				m["name"] = "Your bag, day %d" % (int(m.get("dday", 0)) + 1)
		Game.markers.add("Last death", spot.x, spot.z, Game.planet, "death",
			{"icon": "death", "color": 2, "bag": id, "cx": k.x, "cz": k.y, "dday": int(Game.day)})
		Game.touch_player()
	bag_changed.emit(k, id, rec)
	return key_of(k, id)

## Where a bag dropped at `at` comes to rest: on whatever floor is under it (a cave's, a
## room's), or the nearest dry ground if that floor is under water.
func bag_spot(at: Vector3) -> Vector3:
	var floor_at := at
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.8, 0), at - Vector3(0, 80, 0))
		if player is CollisionObject3D:
			q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			floor_at = hit["position"]
		elif npcs and not is_nan(npcs.ground(at.x, at.z)):
			floor_at.y = npcs.ground(at.x, at.z)
	var ground := func(x: float, z: float) -> float: return npcs.ground(x, z) if npcs else NAN
	return DeathBag.rest_spot(floor_at, ground, func(x: float, z: float) -> float: return Water.surface_height(x, z, 0.0))

func _put(at: Vector3, id: String, rec: Dictionary) -> bool:
	if streamer == null:
		return false
	var k := ChunkStreamer.chunk_of(at)
	var cn := streamer.get_chunk(k)
	if cn == null:
		return false
	rec["p"] = at - cn.position
	rec["day"] = Game.day
	if not cn.data.has("corpses"):
		cn.data["corpses"] = {}
	cn.data["corpses"][id] = rec
	Game.mark_chunk_dirty(cn.data)
	_fresh[id] = true
	_scan = 0.0
	return true

# --- Drawing and decay -----------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or streamer == null or Game.store == null:
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	var pc := ChunkStreamer.chunk_of(player.global_position)
	var seen := {}
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := pc + Vector2i(dx, dz)
			var cn := streamer.get_chunk(k)
			if cn == null or not cn.data.has("corpses"):
				continue
			var all: Dictionary = cn.data["corpses"]
			for id in all.keys():
				var c: Dictionary = all[id]
				if DeathBag.is_bag(c):
					if not CorpseLoot.has_any(c) or DeathBag.expired(c, Time.get_unix_time_from_system()):
						# Emptied (by you, if it was yours: its marker goes with it).
						all.erase(id)
						Game.mark_chunk_dirty(cn.data)
						_forget_bag(id, "")
						bag_changed.emit(k, id, {})
						continue
				elif CorpseLoot.expired(c, Game.day) or not CorpseLoot.has_any(c) and c["kind"] == "animal":
					# Rotted away, or picked clean.
					all.erase(id)
					Game.mark_chunk_dirty(cn.data)
					continue
				var key := key_of(k, id)
				seen[key] = true
				if not _shown.has(key) or not is_instance_valid(_shown[key]["cn"]) or _shown[key]["cn"] != cn:
					_hide(key)
					_show(key, cn, id, c)
	for key in _shown.keys():
		if not seen.has(key):
			_hide(key)
	_check_marked_bags()

## Your marked bags whose ground is loaded but which are no longer there: someone else
## emptied them, or they lay out too long.
func _check_marked_bags() -> void:
	for m in Game.markers.on_planet(Game.planet, "death"):
		var cn := streamer.get_chunk(Vector2i(int(m.get("cx", 0)), int(m.get("cz", 0))))
		if cn != null and not cn.data.get("corpses", {}).has(String(m.get("bag", ""))):
			_forget_bag(String(m.get("bag", "")), "Your bag from day %d is gone. Someone got to it first." % (int(m.get("dday", 0)) + 1))

## Takes a bag of yours off the map (saying `why`, if anything).
func _forget_bag(id: String, why: String) -> void:
	for m in Game.markers.list.duplicate():
		if m["kind"] == "death" and String(m.get("bag", "")) == id:
			Game.markers.remove(int(m["id"]))
			Game.touch_player()
			if why != "":
				Game.toast.emit(why)

func _hide(key: String) -> void:
	if not _shown.has(key):
		return
	var n = _shown[key]["node"]
	if is_instance_valid(n):
		n.queue_free()
	_shown.erase(key)

func _show(key: String, cn: ChunkNode, id: String, c: Dictionary) -> void:
	var fresh: bool = _fresh.has(id)
	_fresh.erase(id)
	var node: Node3D
	if c["kind"] == "animal":
		var cr := Creature.new()
		cr.as_corpse = true
		cr.fresh = fresh
		cr.sp = int(c["sp"])
		cr.era = int(c["era"])
		cr.p = Creature.species(cr.sp, cr.era)
		cr.id = id
		node = cr
	else:
		node = Node3D.new()
		if DeathBag.is_bag(c):
			node.add_child(_bag_model())
	add_child(node)
	node.global_position = cn.position + (c["p"] as Vector3)
	node.rotation.y = float(c.get("yaw", 0.0))
	_shown[key] = {"node": node, "cn": cn, "id": id}
	if c["kind"] == "person":
		_dress(key, fresh)

## A sack on the ground, with a pouch tied to it.
static func _bag_model() -> Node3D:
	var root := Node3D.new()
	for e in [["props/Bag", Vector3.ZERO, 0.0, 0.9], ["props/Pouch_Large", Vector3(0.42, 0, 0.12), 40.0, 1.5]]:
		var path := "res://assets/models/%s.gltf" % e[0]
		if not ResourceLoader.exists(path):
			continue
		var m: Node3D = (load(path) as PackedScene).instantiate()
		m.position = e[1]
		m.rotation_degrees.y = e[2]
		m.scale = Vector3.ONE * float(e[3])
		root.add_child(m)
	if root.get_child_count() == 0:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.45
		mi.mesh = sm
		mi.position.y = 0.2
		root.add_child(mi)
	return root

## Slots in this body's or bag's own inventory.
static func slots_of(c: Dictionary) -> int:
	return DeathBag.SLOTS if DeathBag.is_bag(c) else CorpseLoot.SLOTS

## Builds (or re-dresses) a person's body: who they were, in what they still wear.
func _dress(key: String, fresh := false) -> void:
	var e: Dictionary = _shown.get(key, {})
	var c := record(key)
	if e.is_empty() or c.is_empty() or not HumanModel.available():
		return
	var node: Node3D = e["node"]
	var h: HumanModel = node.get_meta("human") if node.has_meta("human") else null
	if h == null:
		h = HumanModel.new()
		h.build(c["body"], int(c["era"]), String(c["job"]))
		var s := float(c["body"].get("height", 1.0))
		h.scale = Vector3(s, s, s)
		node.add_child(h)
		node.set_meta("human", h)
		h.pose("death")
		if not fresh and h.anim.current_animation != "":
			h.anim.seek(h.anim.current_animation_length, true)
	h.wear(still_worn(c))

## The gear a body still wears: what it died in, less whatever has been taken.
static func still_worn(c: Dictionary) -> Dictionary:
	var left := {}
	var d = c.get("items")
	if d is Dictionary:
		for s in d.get("slots", []):
			if s is Dictionary:
				left[s["type"]] = int(left.get(s["type"], 0)) + 1
	var out := {}
	for slot in c.get("gear", {}):
		var g = c["gear"][slot]
		if g is Dictionary and int(left.get(g["type"], 0)) > 0:
			left[g["type"]] -= 1
			out[slot] = g
	return out

# --- Using bodies ----------------------------------------------------------------------

## The record behind a drawn body, or {} if it is gone.
func record(key: String) -> Dictionary:
	var e: Dictionary = _shown.get(key, {})
	if e.is_empty() or not is_instance_valid(e["cn"]):
		return {}
	return e["cn"].data.get("corpses", {}).get(e["id"], {})

func world_pos(key: String) -> Vector3:
	var e: Dictionary = _shown.get(key, {})
	if e.is_empty() or not is_instance_valid(e["node"]):
		return Vector3.INF
	return (e["node"] as Node3D).global_position

## Bodies within `radius` of `at` that still hold something: [{key, rec, pos}].
func near(at: Vector3, radius: float) -> Array:
	var out := []
	for key in _shown:
		var n = _shown[key]["node"]
		if not is_instance_valid(n) or (n as Node3D).global_position.distance_to(at) > radius:
			continue
		var c := record(key)
		if not c.is_empty() and CorpseLoot.has_any(c):
			out.append({"key": key, "rec": c, "pos": (n as Node3D).global_position})
	return out

## What Interact on this body does: [kind, verb]. kind "carcass" is held to butcher;
## "corpse" opens it.
static func use_of(c: Dictionary) -> Array:
	if DeathBag.is_bag(c):
		var t := DeathBag.title(c, Game.my_id())
		return ["corpse", "Open %s" % (t.to_lower() if t.begins_with("Your") else t)]
	var what := String(c["name"])
	if c["kind"] == "person":
		return ["corpse", "Search %s's body" % what.split(" ")[0]]
	var p := Creature.species(int(c["sp"]), int(c["era"]))
	if not c.get("butchered", false):
		return ["carcass", "%s the %s   (hold)" % [CorpseLoot.verb(p), what.to_lower()]]
	return ["corpse", "Take from the %s carcass" % what.to_lower()]

## Hold time for butchering this carcass with `item` in hand.
func butcher_time(key: String, item) -> float:
	var c := record(key)
	if c.is_empty() or c["kind"] != "animal":
		return 1.0
	return CorpseLoot.butcher_time(Creature.species(int(c["sp"]), int(c["era"])), CorpseLoot.blade_of(item))

## Butchers a carcass with `item` in hand: what fits goes in your pack, the rest stays on it.
func butcher(key: String, item) -> void:
	var c := record(key)
	if c.is_empty() or c["kind"] != "animal" or c.get("butchered", false):
		return
	var e: Dictionary = _shown[key]
	var cn: ChunkNode = e["cn"]
	var k := Vector2i(int(cn.data["cx"]), int(cn.data["cz"]))
	var p := Creature.species(int(c["sp"]), int(c["era"]))
	var blade := CorpseLoot.blade_of(item)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var age := Game.day - float(c["day"])
	var origin := Game.origin_here("hunted", int(c["era"]), k)
	var left := Inventory.new(CorpseLoot.SLOTS)
	var got: Array = []
	for y in CorpseLoot.animal_yields(p, blade, age, rng):
		var it := ItemDB.make(y[0], y[1], rng.randf_range(0.85, 1.15) * (1.1 if blade >= 1.5 else 1.0), origin)
		var rest := Game.inventory.add(it)
		if rest < int(y[1]):
			Game.item_gained.emit(y[0], int(y[1]) - rest)
			got.append(("%d %s" % [int(y[1]) - rest, ItemDB.def(y[0])["name"]]) if int(y[1]) - rest > 1 else ItemDB.def(y[0])["name"])
		if rest > 0:
			it["qty"] = rest
			left.add(it)
	c["butchered"] = true
	c["items"] = left.to_data()
	Game.mark_chunk_dirty(cn.data)
	Game.add_xp(clampf(3.0 + float(p.get("size", 1.0)) * 3.0, 3.0, 20.0), CorpseLoot.verb(p) + "ing")
	var msg := "%s the %s: %s" % ["Salvaged" if CorpseLoot.is_machine(p) else "Butchered", String(c["name"]).to_lower(), ", ".join(got) if not got.is_empty() else "nothing fit in your pack"]
	if age >= CorpseLoot.ROT_DAYS and not CorpseLoot.is_machine(p):
		msg += " (the meat had spoiled)"
	elif blade <= 0.0 and not CorpseLoot.is_machine(p):
		msg += ". A blade would get more from it"
	if CorpseLoot.has_any(c):
		msg += ". The rest is still on it"
	Game.toast.emit(msg)
	_scan = 0.0

## Something worth `worth` Marks was taken off this body. On a townsperson in their own
## town that is theft, if anyone sees.
func took_from(key: String, worth: int) -> void:
	var c := record(key)
	if c.is_empty():
		return
	var e: Dictionary = _shown[key]
	Game.mark_chunk_dirty(e["cn"].data)
	if DeathBag.is_bag(c):
		bag_changed.emit(Vector2i(int(e["cn"].data["cx"]), int(e["cn"].data["cz"])), String(e["id"]), c)
	# Someone else's things: a townsperson's body, or another player's bag.
	var theirs: bool = c["kind"] == "person" or DeathBag.is_bag(c) and not DeathBag.is_mine(c, Game.my_id())
	if theirs:
		if c["kind"] == "person":
			_dress(key)
		var at := world_pos(key)
		var whose := ("from %s" % DeathBag.title(c, Game.my_id())) if DeathBag.is_bag(c) else "from %s's body" % String(c["name"]).split(" ")[0]
		if worth > 0 and npcs and at != Vector3.INF and not npcs.town_at(at).is_empty():
			var t := Time.get_ticks_msec() / 1000.0
			if t - _crime_t > 4.0:
				_crime_t = t
				if not npcs.report_crime(at, "theft", worth, whose):
					Game.toast.emit("Looted unseen (%d Marks' worth)" % worth)
					Game.practice("sneak", 1.0)
	_scan = 0.0
