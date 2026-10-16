class_name Recipes

const LIST := [
	{"out": "planks", "qty": 2, "in": {"wood": 1}},
	{"out": "planks", "qty": 3, "in": {"glowroot": 1}},
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
	for t in recipe["in"]:
		if inv.count(t) < recipe["in"][t]:
			return false
	return true

## Consumes inputs and adds the output. Output quality is the average input quality.
static func craft(inv: Inventory, recipe: Dictionary, origin: Dictionary) -> bool:
	if not can_craft(inv, recipe):
		return false
	var q_sum := 0.0
	var q_n := 0
	for t in recipe["in"]:
		q_sum += inv.average_quality(t) * recipe["in"][t]
		q_n += recipe["in"][t]
	for t in recipe["in"]:
		inv.remove_type(t, recipe["in"][t])
	var o := origin.duplicate()
	o["how"] = "crafted"
	inv.add(ItemDB.make(recipe["out"], recipe["qty"], q_sum / maxf(1, q_n), o))
	return true
