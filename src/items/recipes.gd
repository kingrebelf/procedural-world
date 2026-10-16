class_name Recipes

const LIST := [
	{"out": "planks", "qty": 2, "in": {"wood": 1}},
	{"out": "planks", "qty": 3, "in": {"glowroot": 1}},
	{"out": "cooked_meat", "qty": 1, "in": {"raw_meat": 1, "wood": 1}},
	{"out": "iron_ingot", "qty": 1, "in": {"iron_ore": 2}},
	{"out": "mythril_ingot", "qty": 1, "in": {"iron_ingot": 1, "aether_crystal": 2}},
	{"out": "alloy_plate", "qty": 1, "in": {"alloy_scrap": 3}},
	{"out": "power_cell", "qty": 1, "in": {"aether_crystal": 1, "circuitry": 2}},
	{"out": "pickaxe_iron", "qty": 1, "in": {"iron_ingot": 2, "planks": 2}},
	{"out": "axe_iron", "qty": 1, "in": {"iron_ingot": 2, "planks": 2}},
	{"out": "sword_iron", "qty": 1, "in": {"iron_ingot": 3, "planks": 1}},
	{"out": "pickaxe_mythril", "qty": 1, "in": {"mythril_ingot": 2, "planks": 2}},
	{"out": "axe_mythril", "qty": 1, "in": {"mythril_ingot": 2, "planks": 2}},
	{"out": "sword_runic", "qty": 1, "in": {"mythril_ingot": 3, "aether_crystal": 2}},
	{"out": "pickaxe_plasma", "qty": 1, "in": {"alloy_plate": 2, "power_cell": 1, "mythril_ingot": 1}},
	{"out": "pulse_pistol", "qty": 1, "in": {"alloy_plate": 2, "circuitry": 2, "power_cell": 1}},
]

static func can_craft(inv: Inventory, recipe: Dictionary) -> bool:
	return max_crafts(inv, recipe) > 0

## How many times the recipe can be made from what is in the pack (and still fit).
static func max_crafts(inv: Inventory, recipe: Dictionary) -> int:
	var n := 1 << 30
	for t in recipe["in"]:
		n = mini(n, inv.count(t) / int(recipe["in"][t]))
	if n <= 0:
		return 0
	if not ItemDB.is_stackable(recipe["out"]):
		# Each tool needs its own slot; consuming inputs may free some.
		n = mini(n, inv.free_slots() + _slots_freed(inv, recipe, n))
	elif inv.count(recipe["out"]) == 0 and inv.free_slots() + _slots_freed(inv, recipe, n) <= 0:
		return 0
	return maxi(n, 0)

static func _slots_freed(inv: Inventory, recipe: Dictionary, times: int) -> int:
	var freed := 0
	for t in recipe["in"]:
		if inv.count(t) == recipe["in"][t] * times:
			freed += inv.slots_of(t)
	return freed

## Consumes inputs and adds the output. Output quality is the average input quality.
static func craft(inv: Inventory, recipe: Dictionary, origin: Dictionary) -> bool:
	return craft_many(inv, recipe, origin, 1) == 1

## Crafts up to `times` in one go (-1 = as many as possible); returns how many were made.
static func craft_many(inv: Inventory, recipe: Dictionary, origin: Dictionary, times: int) -> int:
	var most := max_crafts(inv, recipe)
	var n := most if times < 0 else mini(times, most)
	if n <= 0:
		return 0
	var q_sum := 0.0
	var q_n := 0
	for t in recipe["in"]:
		q_sum += inv.average_quality(t) * recipe["in"][t]
		q_n += recipe["in"][t]
	for t in recipe["in"]:
		inv.remove_type(t, recipe["in"][t] * n)
	var o := origin.duplicate()
	o["how"] = "crafted"
	var q := q_sum / maxf(1, q_n)
	if ItemDB.is_stackable(recipe["out"]):
		inv.add(ItemDB.make(recipe["out"], recipe["qty"] * n, q, o))
	else:
		for k in n * int(recipe["qty"]):
			inv.add(ItemDB.make(recipe["out"], 1, q, o))
	return n
