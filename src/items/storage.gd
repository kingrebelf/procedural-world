class_name Storage
## Storage chests: a built piece whose state ("st") holds an inventory of its own, saved
## with the chunk like everything else you build.

## Slot count of a storage piece, or 0 if the object is not one.
static func capacity(o: Dictionary) -> int:
	if ObjectLibrary.kind(o.get("t", "")) != "built":
		return 0
	return int(BuildCatalog.def(BuildCatalog.id_of(o["t"])).get("storage", 0))

## The chest's contents as a live Inventory; write back with save().
static func open(o: Dictionary) -> Inventory:
	var inv := Inventory.new(maxi(1, capacity(o)))
	var d = o["st"].get("items")
	if d is Dictionary:
		inv.from_data(d)
	return inv

static func save(o: Dictionary, inv: Inventory) -> void:
	o["st"]["items"] = inv.to_data()

static func is_empty(o: Dictionary) -> bool:
	var d = o.get("st", {}).get("items")
	if not d is Dictionary:
		return true
	for s in d.get("slots", []):
		if s != null:
			return false
	return true

## Moves the whole stack in slot i of `from` into `to`. Returns how many moved.
static func transfer(from: Inventory, i: int, to: Inventory) -> int:
	var it = from.get_slot(i)
	if it == null:
		return 0
	var n: int = it["qty"]
	var part := from.remove_at(i)
	var left := to.add(part)
	if left > 0:
		part["qty"] = left
		from.add(part)
	return n - left

## Moves everything it can; returns the number of items moved.
static func transfer_all(from: Inventory, to: Inventory, skip_hotbar := false) -> int:
	var moved := 0
	for i in range(Inventory.HOTBAR if skip_hotbar else 0, from.capacity):
		moved += transfer(from, i, to)
	return moved

## Takes everything out of a chest that is being destroyed.
static func spill(o: Dictionary) -> Array:
	var out := []
	if is_empty(o):
		return out
	var inv := open(o)
	for i in inv.capacity:
		if inv.get_slot(i) != null:
			out.append(inv.get_slot(i))
	o["st"].erase("items")
	return out
