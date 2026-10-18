class_name GearModels
## Models for the things that had none and were held as their icon on a card: shields,
## ammunition, paper and keys, keepsakes and instruments, sci-fi parts and kit, alien
## relics. Each one is its icon made solid (the icon is the standard: same shape, colour
## and material), at its real size. Built from parts like ItemModels, in the families
## below; Viewmodel.prop_for asks here after ItemModels and Provisions.
##
## OWED lists the items with an icon and still no model (tests/run_tests.gd fails when one
## gains a model, so the list only shrinks); tools/icon_match.gd draws every icon beside
## its model to check the match.

## Items with an icon and no model yet (the hand holds the icon on a card).
const OWED := {"light_bulb": true, "electric_motor": true, "multimeter": true, "treasure_chip": true,
	"battery_cell": true, "signal_wire": true, "insulator": true, "cannon": true}

## Every item that has an icon on a sheet.
static func icon_items() -> Array:
	var out: Array = []
	var sheets: Array = [Icons.SHEET_ORDER, Icons.SHEET2_ORDER]
	for sh in Icons.MORE_SHEETS:
		sheets.append(sh[1])
	for order: Array in sheets:
		for t: String in order:
			if t != "" and not out.has(t):
				out.append(t)
	return out

static func families() -> Array:
	return [ShieldModels, AmmoModels, KeepsakeModels, TechModels, AlienModels, AlienMatter]

static var _models: Dictionary = {}
static var _lock := Mutex.new()

static func has(t: String) -> bool:
	for f in families():
		if f.BUILD.has(t):
			return true
	return false

## The model for item `t`, or null when no family builds it.
static func model(t: String) -> ArrayMesh:
	_lock.lock()
	var have: bool = _models.has(t)
	var m: ArrayMesh = _models.get(t)
	_lock.unlock()
	if have:
		return m
	for f in families():
		if f.BUILD.has(t):
			var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
			var r := RandomNumberGenerator.new()
			r.seed = WHash.str_hash(t)
			var grip = f.call(f.BUILD[t], k, r, t)
			m = k.commit(func(name: String) -> Material:
				# "own:<name>" is a material the family makes itself (its static mat(name)).
				return f.call("mat", name.substr(4)) if name.begins_with("own:") else ItemModels.mat(name))
			if grip is Vector3:
				m.set_meta("grip", grip)
			break
	_lock.lock()
	_models[t] = m
	_lock.unlock()
	return m
