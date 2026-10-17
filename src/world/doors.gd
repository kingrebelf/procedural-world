class_name Doors
## Doors you build and hang in a doorway you built: a plank door, an iron-bound door and a
## sci-fi bulkhead. A door is a built piece like any other ("b:door_wood"), so everything
## about it lives in its chunk object's `st` and is saved with the chunk snapshot (and
## saved through Game.mark_chunk_dirty, which is also how it will reach other players):
##   open (bool), side (+1 / -1: which way it swung, away from whoever opened it),
##   locked (bool), owner (player id), owner_name, access (player ids let in while locked).
## Who may open a locked door is decided in one place, may_access(): its owner and, once
## multiplayer lands, the owner's alliance (Net.may_access). Anyone on the door's access
## list also gets in. Anyone else has to pick the lock or break the door down.

## Who you are, until multiplayer's Net.my_id() lands ("solo" offline there too).
const SOLO := "solo"
## How far a hinged door swings open, and how far a bulkhead leaf slides aside.
const SWING_DEG := 100.0
const SLIDE := 2.0
## Of the full travel per second.
const SPEED := 2.2
## How close to a doorway's middle you have to aim to hang a door in it.
const HANG_REACH := 1.8

static func my_id() -> String:
	return SOLO

static func my_name() -> String:
	return "You"

## True when `owner` lets you in: no owner, you, or (multiplayer) your alliance. The one
## line to swap for Net.may_access(owner).
static func may_access(owner: String) -> bool:
	return owner == "" or owner == my_id()

static func is_door(t: String) -> bool:
	return BuildCatalog.is_built(t) and BuildCatalog.def(BuildCatalog.id_of(t)).has("door")

static func is_door_piece(id: String) -> bool:
	return BuildCatalog.def(id).has("door")

## The door pieces that hang in this doorway piece (empty when it isn't a doorway).
static func fits(doorway_id: String) -> Array:
	var out: Array = []
	for id in BuildCatalog.PIECES:
		if (BuildCatalog.PIECES[id].get("door", {}) as Dictionary).get("fits", []).has(doorway_id):
			out.append(id)
	return out

static func spec(o: Dictionary) -> Dictionary:
	return BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("door", {})

## 1 (plank) .. 3 (bulkhead): how hard its lock is to pick (LockGame tiers).
static func tier(o: Dictionary) -> int:
	return int(spec(o).get("tier", 1))

# --- State -------------------------------------------------------------------------

## A newly hung door: shut, unlocked, yours.
static func init_state(st: Dictionary) -> void:
	st["open"] = false
	st["side"] = 1.0
	st["locked"] = false
	st["owner"] = my_id()
	st["owner_name"] = my_name()
	st["access"] = []

static func owner_of(o: Dictionary) -> String:
	return String(o["st"].get("owner", ""))

static func is_open(o: Dictionary) -> bool:
	return bool(o["st"].get("open", false))

static func is_locked(o: Dictionary) -> bool:
	return bool(o["st"].get("locked", false))

## Yours to lock, unlock and hand keys out for.
static func is_mine(o: Dictionary) -> bool:
	return owner_of(o) == my_id()

## Lets `who` (you, by default) through even when it is locked: its owner, anyone it
## has been given to, and (for you) your alliance.
static func has_access(o: Dictionary, who := "") -> bool:
	if who == "" or who == my_id():
		return may_access(owner_of(o)) or (o["st"].get("access", []) as Array).has(my_id())
	return who == owner_of(o) or (o["st"].get("access", []) as Array).has(who)

static func can_open(o: Dictionary) -> bool:
	return not is_locked(o) or has_access(o)

## Opens or shuts the door. `side` is which side of it the one opening it stands on
## (+1 in front, along the door's local +z), so it swings away from them.
## Returns "opened", "closed" or "locked" (it stayed shut).
static func toggle(o: Dictionary, side: float) -> String:
	if is_open(o):
		o["st"]["open"] = false
		return "closed"
	if not can_open(o):
		return "locked"
	o["st"]["open"] = true
	o["st"]["side"] = 1.0 if side >= 0.0 else -1.0
	return "opened"

## Locks or unlocks it; only for those who may (owner or alliance). Returns false if not.
static func set_locked(o: Dictionary, on: bool) -> bool:
	if not may_access(owner_of(o)):
		return false
	o["st"]["locked"] = on
	return true

## Lets a player through the lock (the owner's choice).
static func grant(o: Dictionary, who: String) -> bool:
	if not is_mine(o) or who == "":
		return false
	var a: Array = o["st"].get("access", [])
	if not a.has(who):
		a.append(who)
	o["st"]["access"] = a
	return true

static func revoke(o: Dictionary, who: String) -> bool:
	if not is_mine(o):
		return false
	(o["st"].get("access", []) as Array).erase(who)
	return true

## The lock gave to a pick: it stays unlocked (until its owner locks it again) and opens.
static func picked(o: Dictionary, side: float) -> void:
	o["st"]["locked"] = false
	o["st"]["open"] = true
	o["st"]["side"] = 1.0 if side >= 0.0 else -1.0

## Which side of the door (+1 / -1 along its local z) a world point is on.
static func side_of(o: Dictionary, door_world: Vector3, at: Vector3) -> float:
	var local := Basis(Vector3.UP, -float(o["r"])) * (at - door_world)
	return 1.0 if local.z >= 0.0 else -1.0

## What Interact does on it, for the prompt.
static func verb(o: Dictionary, sneaking: bool) -> String:
	var nm := String(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("name", "door")).to_lower()
	if sneaking and may_access(owner_of(o)):
		return "%s the %s" % ["Unlock" if is_locked(o) else "Lock", nm]
	if is_open(o):
		return "Close the %s" % nm
	if can_open(o):
		return "Open the %s%s" % [nm, "   (locked: you have the key)" if is_locked(o) else ""]
	return "Pick the %s lock on the %s" % [LockGame.TIERS[tier(o)].to_lower(), nm]

## Lines for the look-at panel.
static func describe(o: Dictionary) -> Array:
	var lines: Array = []
	var who := String(o["st"].get("owner_name", ""))
	lines.append(("Locked" if is_locked(o) else "Unlocked") + ("" if who == "" else "  ·  Owner: %s" % who))
	var n := (o["st"].get("access", []) as Array).size()
	if n > 0:
		lines.append("%d other %s can open it" % [n, "player" if n == 1 else "players"])
	if not can_open(o):
		lines.append("%s lock: pick it with a lockpick, or break the door down" % LockGame.TIERS[tier(o)])
	return lines

# --- Placement ---------------------------------------------------------------------

## The doorway this door piece would hang in when aimed along the line `from` -> `to`
## (the eye to what the crosshair hit, so aiming through the open doorway counts):
## {pos, yaw} in world space (the doorway's own spot and facing), or {} when none is
## near. Walks the loaded chunks around `to`, like BuildCatalog's placement helpers.
static func doorway_near(streamer, id: String, from: Vector3, to: Vector3) -> Dictionary:
	if streamer == null:
		return {}
	var ok_ids: Array = BuildCatalog.def(id).get("door", {}).get("fits", [])
	var ck := BuildCatalog._chunk_of(to)
	var best := {}
	var best_d := HANG_REACH
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if not BuildCatalog.is_built(o["t"]) or o["st"].get("gone", false) or not ok_ids.has(BuildCatalog.id_of(o["t"])):
					continue
				var wp: Vector3 = origin + o["p"]
				var storey := float(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("storey", 3.0))
				var mid := wp + Vector3(0, storey * 0.4, 0)
				var d := Geometry3D.get_closest_point_to_segment(mid, from, to).distance_to(mid)
				if d < best_d:
					best_d = d
					best = {"pos": wp, "yaw": float(o["r"])}
	return best

## The door hanging in the doorway at world point `at`, as {chunk, obj}, or {}.
static func door_at(streamer, at: Vector3) -> Dictionary:
	if streamer == null:
		return {}
	var ck := BuildCatalog._chunk_of(at)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c = streamer.get_chunk(ck + Vector2i(dx, dz))
			if c == null:
				continue
			var origin := Vector3((ck.x + dx) * ChunkGenerator.SIZE, 0, (ck.y + dz) * ChunkGenerator.SIZE)
			for o in c.data["objects"]:
				if is_door(o["t"]) and not o["st"].get("gone", false) and (origin + o["p"]).distance_to(at) < 0.2:
					return {"chunk": c, "obj": o}
	return {}

# --- Leaves ------------------------------------------------------------------------

static var _leaf_meshes := {}

## One leaf's mesh (a kit model on its own), cached. Main thread only, like the rest of
## the kit meshes (BuildCatalog.model_parts).
static func leaf_mesh(model: String) -> ArrayMesh:
	if not _leaf_meshes.has(model):
		_leaf_meshes[model] = BuildCatalog.merge_models([[model, 0, Vector3.ZERO, 1.0]])
	return _leaf_meshes[model]

## Where a leaf sits, `amount` of the way open (0 shut .. 1 open), in the door's space.
## `entry` is the leaf's model entry in the piece ([model, yaw, offset, scale]); its
## origin is the hinge (the kit doors are modelled that way). A hinged leaf turns about
## it, away from the side it was opened from; a sliding leaf slides back along itself.
static func leaf_xf(entry: Array, slide: bool, amount: float, side: float) -> Transform3D:
	var closed := BuildCatalog._xf(entry)
	if amount <= 0.0:
		return closed
	if slide:
		return Transform3D(closed.basis, closed.origin - closed.basis.x.normalized() * SLIDE * amount)
	# The free edge points along the leaf's +x; turning by +a moves it toward -z. Swing
	# the free edge away from the opener (who stands on `side`).
	var dir := signf(closed.basis.x.x) if absf(closed.basis.x.x) > 0.01 else 1.0
	var a := deg_to_rad(SWING_DEG) * amount * side * dir
	return Transform3D(Basis(Vector3.UP, a) * closed.basis, closed.origin)
