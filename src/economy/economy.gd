class_name Economy
## Trader pricing. Trader state lives in the trader object's persisted state dict:
## { era, name, stock: {type: qty}, demand: {type: float}, last_day: float }
## Optional (villagers trading their own goods, see NPCSocial.shop): pool (what they
## stock), purse (all they can pay out), charge_mult / pay_mult (their mood and greed).

const FOREIGN_MIN := 1.6
const FOREIGN_MAX := 2.4
const NATIVE := 0.7
const DEMAND_DROP := 0.92
const DEMAND_RECOVERY_PER_DAY := 0.25
const SELL_SPREAD := 1.35 ## Traders sell at this multiple of what they pay.
const RESTOCK_DAYS := 3.0

const STOCK_POOLS := [
	["bread", "iron_ingot", "planks", "pickaxe_iron", "axe_iron", "sword_iron", "wood", "iron_ore"],
	["glowberry", "aether_crystal", "glowroot", "mythril_ingot", "pickaxe_mythril", "sword_runic", "axe_mythril"],
	["ration_pack", "power_cell", "circuitry", "alloy_plate", "pulse_pistol", "pickaxe_plasma", "alloy_scrap"],
]
const TRADER_NAMES := [
	["Aldric the Fair", "Mother Wenna", "Osric Coalhand", "Bertilde"],
	["Ysolde of the Fen", "Thistlewhit", "Oracle Maelis", "Brannoch"],
	["QM-7 Vendor", "Trader Okafor", "Supply Officer Lin", "Unit KESTREL"],
]

static func new_trader(era: int, rng: RandomNumberGenerator) -> Dictionary:
	var st := {
		"era": era,
		"name": TRADER_NAMES[era][rng.randi() % 4],
		"foreign": FOREIGN_MIN + rng.randf() * (FOREIGN_MAX - FOREIGN_MIN),
		"stock": {}, "demand": {}, "last_day": 0.0, "restock_seed": rng.randi(),
	}
	_restock(st, 0)
	return st

static func _restock(st: Dictionary, cycle: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(st["restock_seed"], cycle)
	var pool: Array = st.get("pool", STOCK_POOLS[st["era"]])
	var stock := {}
	for t in pool:
		if r.randf() < 0.7:
			stock[t] = 1 if not ItemDB.is_stackable(t) else r.randi_range(2, 12)
	st["stock"] = stock

static func era_factor(trader_era: int, item_type: String, foreign: float) -> float:
	var e := ItemDB.era_of(item_type)
	if e == ItemDB.ANY:
		return 1.0
	return NATIVE if e == trader_era else foreign

## What the trader pays the player for one unit.
static func buy_price(st: Dictionary, item: Dictionary) -> int:
	var t: String = item["type"]
	var base: float = ItemDB.def(t).get("value", 1)
	var demand: float = st["demand"].get(t, 1.0)
	var rank := Rarity.of(item)
	return maxi(1, int(round(base * (1.0 + 0.6 * rank * rank) * item.get("quality", 1.0) * era_factor(st["era"], t, st["foreign"]) * demand * float(st.get("pay_mult", 1.0)))))

## What the trader charges the player for one unit of its stock.
static func sell_price(st: Dictionary, t: String) -> int:
	var base: float = ItemDB.def(t).get("value", 1)
	var f: float = 1.0 if ItemDB.era_of(t) == st["era"] else st["foreign"]
	return maxi(1, int(round(base * f * SELL_SPREAD * float(st.get("charge_mult", 1.0)))))

static func record_sale_to_trader(st: Dictionary, t: String, qty: int) -> void:
	st["demand"][t] = st["demand"].get(t, 1.0) * pow(DEMAND_DROP, qty)

## Advances trader state to `day` (in-game days). Demand recovers, stock restocks on a
## deterministic cycle so revisiting gives the same result regardless of when you look.
static func tick(st: Dictionary, day: float) -> void:
	var dt := day - float(st["last_day"])
	if dt <= 0.0:
		return
	for t in st["demand"].keys():
		st["demand"][t] = minf(1.0, st["demand"][t] + DEMAND_RECOVERY_PER_DAY * dt)
	var old_cycle := int(floor(st["last_day"] / RESTOCK_DAYS))
	var new_cycle := int(floor(day / RESTOCK_DAYS))
	if new_cycle > old_cycle:
		_restock(st, new_cycle)
	st["last_day"] = day
