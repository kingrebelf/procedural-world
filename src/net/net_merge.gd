class_name NetMerge
extends RefCounted
## Three-way merge of saved world data (chunks, settlements) on a server: two players
## edited copies of the same `base`; `mine` is the save arriving now, `theirs` what the
## server already has. What only one side changed is kept from that side, so one
## player's save no longer undoes another's (a bag taken, a door locked, a deer killed).
##   - Dictionaries merge key by key.
##   - Arrays of records that all have an "id" (a town's people, a chunk's guards) merge
##     by id: in theirs' order, with records only mine added at the end.
##   - Other arrays that only grew on both sides (a chunk's objects: never removed, only
##     marked gone) merge item by item, and keep what both sides appended.
##   - Anything else that both sides changed takes mine, the newer save.

const _NONE := "\u0001none" ## a key one side doesn't have

static func merge3(base, mine, theirs):
	if typeof(mine) == typeof(base) and mine == base:
		return theirs
	if typeof(theirs) == typeof(base) and theirs == base:
		return mine
	if typeof(mine) == typeof(theirs) and mine == theirs:
		return mine
	if base is Dictionary and mine is Dictionary and theirs is Dictionary:
		return _dicts(base, mine, theirs)
	if base is Array and mine is Array and theirs is Array:
		if _by_id(base) and _by_id(mine) and _by_id(theirs):
			return _records(base, mine, theirs)
		if mine.size() >= base.size() and theirs.size() >= base.size():
			return _grown(base, mine, theirs)
	return mine

static func _dicts(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = theirs.keys()
	for k in mine:
		if not theirs.has(k):
			keys.append(k)
	for k in base:
		if not theirs.has(k) and not mine.has(k):
			keys.append(k)
	for k in keys:
		var v = merge3(base.get(k, _NONE), mine.get(k, _NONE), theirs.get(k, _NONE))
		if not (v is String and v == _NONE):
			out[k] = v
	return out

static func _by_id(a: Array) -> bool:
	for r in a:
		if not (r is Dictionary and r.has("id")):
			return false
	return true

static func _index(a: Array) -> Dictionary:
	var out := {}
	for r in a:
		out[r["id"]] = r
	return out

static func _records(base: Array, mine: Array, theirs: Array) -> Array:
	var b := _index(base)
	var m := _index(mine)
	var t := _index(theirs)
	var out: Array = []
	for r in theirs:
		var v = merge3(b.get(r["id"], _NONE), m.get(r["id"], _NONE), r)
		if v is Dictionary:
			out.append(v)
	for r in mine:
		if t.has(r["id"]):
			continue
		var v = merge3(b.get(r["id"], _NONE), r, _NONE)
		if v is Dictionary:
			out.append(v)
	return out

static func _grown(base: Array, mine: Array, theirs: Array) -> Array:
	var out: Array = []
	for i in base.size():
		out.append(merge3(base[i], mine[i], theirs[i]))
	var mt := mine.slice(base.size())
	var tt := theirs.slice(base.size())
	out.append_array(tt)
	if mt != tt:
		out.append_array(mt)
	return out

## Merges `theirs` into `live` in place (live = base plus your unsaved edits), keeping
## the dictionaries inside it (and records in id-keyed arrays) as the same objects, so
## nodes holding them see the change. Returns `live`.
static func merge_into(live: Dictionary, base: Dictionary, theirs: Dictionary) -> Dictionary:
	var keys: Array = theirs.keys()
	for k in live:
		if not theirs.has(k):
			keys.append(k)
	for k in keys:
		var bv = base.get(k, _NONE)
		var lv = live.get(k, _NONE)
		var tv = theirs.get(k, _NONE)
		if lv is Dictionary and tv is Dictionary and not (typeof(lv) == typeof(bv) and lv == bv):
			merge_into(lv, bv if bv is Dictionary else {}, tv)
			continue
		if lv is Dictionary and tv is Dictionary:
			# Unchanged here: take theirs, still in place.
			merge_into(lv, lv.duplicate(true), tv)
			continue
		if lv is Array and tv is Array and _by_id(lv) and _by_id(tv) and (bv is Array and _by_id(bv) or not bv is Array):
			_records_into(lv, bv if bv is Array else [], tv)
			continue
		var v = merge3(bv, lv, tv)
		if v is String and v == _NONE:
			live.erase(k)
		else:
			live[k] = v
	return live

static func _records_into(live: Array, base: Array, theirs: Array) -> void:
	var b := _index(base)
	var l := _index(live)
	var t := _index(theirs)
	var out: Array = []
	for r in theirs:
		var id = r["id"]
		if l.has(id):
			out.append(merge_into(l[id], b.get(id, {}), r))
		elif not b.has(id):
			out.append(r) # new over there
		# else: you removed it; it stays removed
	for r in live:
		if not t.has(r["id"]) and not b.has(r["id"]):
			out.append(r) # new here
	live.clear()
	live.append_array(out)
