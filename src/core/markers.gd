class_name Markers
extends RefCounted
## Places you have marked on the map, per planet: pins you drop, the teleporters you
## build (which register themselves so any teleporter can send you to another), and the
## beds you have made or slept in (where you can choose to wake after a fall).

const COLORS := [Color(0.95, 0.78, 0.42), Color(0.45, 0.85, 0.95), Color(0.95, 0.4, 0.35), Color(0.55, 0.9, 0.45), Color(0.8, 0.55, 0.95),
	Color(1.0, 0.55, 0.2), Color(1.0, 0.5, 0.75), Color(0.95, 0.95, 0.95), Color(0.35, 0.5, 1.0), Color(0.6, 0.45, 0.3)]
## Icons a pin can wear, from the map marker sheet (MapCanvas.ICON).
const ICONS := ["pin", "quest", "chest", "danger", "death", "campfire", "mine", "cave", "dungeon",
	"well", "inn", "smithy", "trader", "horse", "vehicle", "ship", "beacon", "teleporter"]

var list: Array = [] ## {"id", "name", "x", "z", "planet", "kind": "pin"|"teleporter"|"bed", "color", "icon", "key", "i"}
## (Beds also keep "y", the height they stand at, and "slept", the day you last used them.)
var next_id := 1

func add(name: String, x: float, z: float, planet: int, kind := "pin", extra := {}) -> Dictionary:
	var m := {"id": next_id, "name": name, "x": x, "z": z, "planet": planet, "kind": kind,
		"color": next_id % COLORS.size()}
	m.merge(extra)
	next_id += 1
	list.append(m)
	return m

func get_by_id(id: int) -> Dictionary:
	for m in list:
		if int(m["id"]) == id:
			return m
	return {}

## Changes a marker's name, colour or icon (only the fields given).
func edit(id: int, fields: Dictionary) -> void:
	var m := get_by_id(id)
	if m.is_empty():
		return
	if fields.has("name"):
		var n := String(fields["name"]).strip_edges().left(40)
		if n != "":
			m["name"] = n
	if fields.has("color"):
		m["color"] = posmod(int(fields["color"]), COLORS.size())
	if fields.has("icon") and ICONS.has(fields["icon"]):
		m["icon"] = fields["icon"]

func remove(id: int) -> void:
	for i in list.size():
		if int(list[i]["id"]) == id:
			list.remove_at(i)
			return

## Forgets the teleporter or bed built at chunk `key`, object `i` (it was taken down).
func remove_object(key: Vector2i, i: int) -> void:
	for m in list.duplicate():
		if m["kind"] in ["teleporter", "bed"] and str(m.get("key", "")) == str(key) and int(m.get("i", -1)) == i:
			list.erase(m)

## The marker of the teleporter or bed built at chunk `key`, object `i`, or {}.
func of_object(key: Vector2i, i: int) -> Dictionary:
	for m in list:
		if m["kind"] in ["teleporter", "bed"] and str(m.get("key", "")) == str(key) and int(m.get("i", -1)) == i:
			return m
	return {}

## Registers the bed at world position `at` (chunk `key`, object `i`) as a place to wake
## after a fall. Returns its marker (the one it already had, if any).
func add_bed(at: Vector3, planet: int, key: Vector2i, i: int) -> Dictionary:
	var m := of_object(key, i)
	if not m.is_empty():
		return m
	var n := 1
	var names := list.map(func(b): return b["name"])
	while names.has("Bed %d" % n):
		n += 1
	return add("Bed %d" % n, at.x, at.z, planet, "bed", {"icon": "inn", "color": 0, "y": snappedf(at.y, 0.01), "key": str(key), "i": i})

func on_planet(planet: int, kind := "") -> Array:
	return list.filter(func(m): return int(m["planet"]) == planet and (kind == "" or m["kind"] == kind))

func count_kind(kind: String) -> int:
	return list.filter(func(m): return m["kind"] == kind).size()

static func color_of(m: Dictionary) -> Color:
	return COLORS[int(m.get("color", 0)) % COLORS.size()]

func to_data() -> Dictionary:
	return {"list": list.duplicate(true), "next_id": next_id}

static func from_data(d) -> Markers:
	var mk := Markers.new()
	if d is Dictionary:
		mk.list = (d.get("list", []) as Array).duplicate(true)
		mk.next_id = int(d.get("next_id", 1))
	return mk
