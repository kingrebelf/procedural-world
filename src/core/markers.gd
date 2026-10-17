class_name Markers
extends RefCounted
## Places you have marked on the map, per planet: pins you drop, and the teleporters you
## build (which register themselves so any teleporter can send you to another).

const COLORS := [Color(0.95, 0.78, 0.42), Color(0.45, 0.85, 0.95), Color(0.95, 0.4, 0.35), Color(0.55, 0.9, 0.45), Color(0.8, 0.55, 0.95),
	Color(1.0, 0.55, 0.2), Color(1.0, 0.5, 0.75), Color(0.95, 0.95, 0.95), Color(0.35, 0.5, 1.0), Color(0.6, 0.45, 0.3)]
## Icons a pin can wear, from the map marker sheet (MapCanvas.ICON).
const ICONS := ["pin", "quest", "chest", "danger", "death", "campfire", "mine", "cave", "dungeon",
	"well", "inn", "smithy", "trader", "horse", "vehicle", "ship", "beacon", "teleporter"]

var list: Array = [] ## {"id", "name", "x", "z", "planet", "kind": "pin"|"teleporter", "color", "icon", "key", "i"}
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

## Forgets the teleporter built at chunk `key`, object `i` (it was taken down).
func remove_object(key: Vector2i, i: int) -> void:
	for m in list.duplicate():
		if m["kind"] == "teleporter" and str(m.get("key", "")) == str(key) and int(m.get("i", -1)) == i:
			list.erase(m)

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
