class_name Inventory
extends RefCounted
## Slot-based inventory. Slots 0..HOTBAR-1 are the hotbar. Every item is a Dictionary
## (see ItemDB.make) and carries its provenance forever.

signal changed

const HOTBAR := 6
const SIZE := 42

var slots: Array = []
var next_uid := 1

func _init() -> void:
	slots.resize(SIZE)

func _stack_key(item: Dictionary) -> String:
	return "%s@%.1f" % [item["type"], snappedf(item.get("quality", 1.0), 0.1)]

## Adds an item; returns the quantity that did not fit (0 when everything fit).
func add(item: Dictionary) -> int:
	item = item.duplicate(true)
	if ItemDB.is_stackable(item["type"]):
		var key := _stack_key(item)
		for i in SIZE:
			var s = slots[i]
			if s != null and _stack_key(s) == key:
				s["qty"] += item["qty"]
				changed.emit()
				return 0
	else:
		item["qty"] = 1
	for i in SIZE:
		if slots[i] == null:
			if item.get("uid", 0) == 0:
				item["uid"] = next_uid
				next_uid += 1
			slots[i] = item
			changed.emit()
			return 0
	return item["qty"]

func count(type: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["type"] == type:
			n += s["qty"]
	return n

func average_quality(type: String) -> float:
	var q := 0.0
	var n := 0
	for s in slots:
		if s != null and s["type"] == type:
			q += s.get("quality", 1.0) * s["qty"]
			n += s["qty"]
	return q / n if n > 0 else 1.0

func remove_type(type: String, qty: int) -> int:
	var removed := 0
	for i in SIZE:
		var s = slots[i]
		if s == null or s["type"] != type:
			continue
		var take: int = mini(qty - removed, s["qty"])
		s["qty"] -= take
		removed += take
		if s["qty"] <= 0:
			slots[i] = null
		if removed >= qty:
			break
	if removed > 0:
		changed.emit()
	return removed

func remove_at(index: int, qty: int = -1) -> Dictionary:
	var s = slots[index]
	if s == null:
		return {}
	if qty < 0 or qty >= s["qty"]:
		slots[index] = null
		changed.emit()
		return s
	s["qty"] -= qty
	var part: Dictionary = s.duplicate(true)
	part["qty"] = qty
	changed.emit()
	return part

func swap(a: int, b: int) -> void:
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	changed.emit()

func get_slot(i: int):
	return slots[i]

func to_data() -> Dictionary:
	return {"slots": slots.duplicate(true), "next_uid": next_uid}

func from_data(d: Dictionary) -> void:
	slots = d.get("slots", []).duplicate(true)
	slots.resize(SIZE)
	next_uid = d.get("next_uid", 1)
	changed.emit()
