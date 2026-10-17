class_name Inventory
extends RefCounted
## Slot-based inventory. Slots 0..HOTBAR-1 are the hotbar. Every item is a Dictionary
## (see ItemDB.make) and carries its provenance forever.

signal changed

const HOTBAR := 10
const SIZE := 50

var slots: Array = []
var next_uid := 1
var capacity := SIZE ## slot count: your pack has SIZE, a storage chest its own

func _init(n: int = SIZE) -> void:
	capacity = n
	slots.resize(n)

const STACK_MAX := 9999
const MAX_SOURCES := 8

## Stackable items merge by type alone. Each stack keeps its quality as a weighted average
## and lists where its parts came from in `sources` ([origin, qty] pairs), so provenance
## survives stacking. Tools, weapons and anything with wear never stack.
static func stacks(item: Dictionary) -> bool:
	return ItemDB.is_stackable(item["type"]) and not item.has("wear")

static func _same_origin(a: Dictionary, b: Dictionary) -> bool:
	return a.get("how") == b.get("how") and a.get("chunk") == b.get("chunk") and a.get("era") == b.get("era")

static func sources_of(item: Dictionary) -> Array:
	if item.has("sources"):
		return item["sources"]
	return [[item.get("origin", {}), item.get("qty", 1)]]

## Merges `src` into the stack `dst` (both stackable, same type).
static func merge_into(dst: Dictionary, src: Dictionary, qty: int) -> void:
	var total: int = dst["qty"] + qty
	dst["quality"] = snappedf((dst.get("quality", 1.0) * dst["qty"] + src.get("quality", 1.0) * qty) / maxf(1, total), 0.01)
	var srcs: Array = sources_of(dst).duplicate(true)
	var add: Array = sources_of(src)
	var left := qty
	for pair in add:
		var n: int = mini(pair[1], left)
		if n <= 0:
			break
		left -= n
		var found := false
		for e in srcs:
			if _same_origin(e[0], pair[0]):
				e[1] += n
				found = true
				break
		if not found:
			if srcs.size() < MAX_SOURCES:
				srcs.append([pair[0], n])
			else:
				srcs[srcs.size() - 1][1] += n
	dst["sources"] = srcs
	dst["qty"] = total

## Takes `qty` off a stack's source list, newest first, and returns the removed pairs.
static func _take_sources(item: Dictionary, qty: int) -> Array:
	var srcs: Array = sources_of(item).duplicate(true)
	var taken: Array = []
	var left := qty
	while left > 0 and not srcs.is_empty():
		var e: Array = srcs[srcs.size() - 1]
		var n: int = mini(e[1], left)
		e[1] -= n
		left -= n
		taken.push_front([e[0], n])
		if e[1] <= 0:
			srcs.pop_back()
	if item.has("sources") or taken.size() > 0:
		item["sources"] = srcs
		if not srcs.is_empty():
			item["origin"] = srcs[0][0]
	return taken

## Adds an item; returns the quantity that did not fit (0 when everything fit).
func add(item: Dictionary) -> int:
	item = item.duplicate(true)
	if stacks(item):
		for i in capacity:
			var s = slots[i]
			if s != null and s["type"] == item["type"] and stacks(s) and s["qty"] < STACK_MAX:
				var n: int = mini(item["qty"], STACK_MAX - s["qty"])
				merge_into(s, item, n)
				if n < item["qty"]:
					var rest := item.duplicate(true)
					rest["qty"] = item["qty"] - n
					rest["sources"] = _take_sources(item.duplicate(true), rest["qty"])
					changed.emit()
					return add(rest)
				changed.emit()
				return 0
	else:
		item["qty"] = 1
	for i in capacity:
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

## Everything carried, in kg.
func weight() -> float:
	var w := 0.0
	for s in slots:
		if s != null:
			w += ItemDB.weight(s["type"]) * s["qty"] * (0.1 if Rarity.has_affix(s, "featherweight") else 1.0)
	return w

func free_slots() -> int:
	var n := 0
	for s in slots:
		if s == null:
			n += 1
	return n

func slots_of(type: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["type"] == type:
			n += 1
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
	for i in capacity:
		var s = slots[i]
		if s == null or s["type"] != type:
			continue
		var take: int = mini(qty - removed, s["qty"])
		s["qty"] -= take
		removed += take
		if s["qty"] > 0 and s.has("sources"):
			_take_sources(s, take)
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
	if s.has("sources"):
		var taken := _take_sources(s, qty)
		part["sources"] = taken
		if not taken.is_empty():
			part["origin"] = taken[0][0]
	changed.emit()
	return part

## Moves slot a onto slot b. Two stacks of the same stackable type merge.
func swap(a: int, b: int) -> void:
	if a == b:
		return
	var sa = slots[a]
	var sb = slots[b]
	if sa != null and sb != null and sa["type"] == sb["type"] and stacks(sa) and stacks(sb):
		var n: int = mini(sa["qty"], STACK_MAX - sb["qty"])
		if n > 0:
			merge_into(sb, sa, n)
			if n >= sa["qty"]:
				slots[a] = null
			else:
				sa["qty"] -= n
			changed.emit()
			return
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
	slots.resize(capacity)
	next_uid = d.get("next_uid", 1)
	_compact()
	changed.emit()

## Merges stacks of the same type (saves from before v0.2.5 kept one stack per quality).
func _compact() -> void:
	for i in capacity:
		var s = slots[i]
		if s == null or not stacks(s):
			continue
		for j in range(i + 1, capacity):
			var o = slots[j]
			if o != null and o["type"] == s["type"] and stacks(o) and s["qty"] + o["qty"] <= STACK_MAX:
				merge_into(s, o, o["qty"])
				slots[j] = null
