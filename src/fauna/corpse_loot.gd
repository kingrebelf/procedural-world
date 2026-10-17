class_name CorpseLoot
## What a body gives up. Animals are butchered: meat, hide or fur, bone, fat and their
## species' extras, more with a proper blade and less once the carcass has turned.
## People are searched: what they wore and carried, and their purse.
## Pure functions (no scene or autoload), so tests can call them.

## Days after death a carcass's meat and fat have spoiled, and when a body is gone.
const ROT_DAYS := 1.0
const ANIMAL_GONE_DAYS := 2.0
const PERSON_GONE_DAYS := 4.0
## Slots in a body's own little inventory.
const SLOTS := 20

## Species whose skin comes off as a fur pelt rather than a plain hide.
const FURRED := ["Grey Wolf", "Red Fox", "Thornhound", "Woolly Lumen", "Castle Hound", "Patrol Hound",
	"Village Dog", "Hearth Hound", "Shiba", "Ember Pup", "Wild Donkey"]
## Species with antlers worth taking: [name, how many].
const ANTLERED := {"Elk": 2, "Glimmerhart": 2, "Red Deer": 1}

## How good the held item is for skinning: 0 bare-handed, 0.7 for a blade or axe, more
## for a dagger and most for a skinning knife ("skin" in ItemDB).
static func blade_of(item) -> float:
	if not item is Dictionary:
		return 0.0
	var d := ItemDB.def(item["type"])
	if d.has("skin"):
		return float(d["skin"])
	var t: String = item["type"]
	if d.get("kind", "") in ["weapon", "tool"] and not d.get("ranged", false):
		for k in ["sword", "axe", "dagger", "spear", "blade"]:
			if t.contains(k):
				return 0.7
	return 0.0

## Seconds of work to butcher an animal of species params `p` with this blade.
static func butcher_time(p: Dictionary, blade: float) -> float:
	return (1.0 + float(p.get("size", 1.0)) * 0.8) / (0.6 + blade * 0.5)

## True for machines and crawlers you strip for parts instead of skinning.
static func is_machine(p: Dictionary) -> bool:
	for d in p.get("drops", []):
		if d[0] == "alloy_scrap" or d[0] == "circuitry":
			return true
	return false

static func verb(p: Dictionary) -> String:
	return "Salvage" if is_machine(p) else "Butcher"

## [type, qty] pairs from butchering. `blade` from blade_of; `age` is days since death.
static func animal_yields(p: Dictionary, blade: float, age: float, rng: RandomNumberGenerator) -> Array:
	var out := {}
	var order: Array = []
	var add := func(t: String, n: int) -> void:
		if n <= 0:
			return
		if not out.has(t):
			order.append(t)
			out[t] = 0
		out[t] += n
	var size: float = p.get("size", 1.0)
	var name: String = p.get("name", "")
	var machine := is_machine(p)
	var bird: bool = p.get("plan", "") == "bird"
	var rotten := age >= ROT_DAYS
	for d in p.get("drops", []):
		var t: String = d[0]
		var n: int = d[1]
		match t:
			"raw_meat":
				n += int(size * 1.2)
				if blade <= 0.0:
					n -= 1
				elif blade >= 1.5:
					n += 1
				if rotten:
					n = 0
				add.call(t, maxi(n, 0 if rotten else 1))
			"hide":
				if bird:
					continue # feathers and down, nothing worth tanning
				if blade <= 0.0:
					n -= 1 # torn off by hand
				elif blade >= 1.5:
					n += 1
				if rotten:
					n /= 2
				add.call("fur_pelt" if name in FURRED else "hide", n)
			_:
				add.call(t, n)
	if not machine:
		add.call("bone", 1 + int(size * 1.5))
		if size >= 1.0 and not rotten and not bird:
			add.call("animal_fat", 1 + int(size * 0.5))
		if ANTLERED.has(name) or p.get("horns", false) and String(p.get("kit", "")) == "":
			var a: int = ANTLERED.get(name, 1)
			if name == "Red Deer" and rng.randf() < 0.5:
				a = 0
			add.call("antler", a)
	var list: Array = []
	for t in order:
		if out[t] > 0:
			list.append([t, out[t]])
	return list

## What a dead person had on them, as items: worn gear, what was in their hand and their
## pockets. `pockets` comes from NPCSocial.pockets (passed in so this stays pure).
static func person_items(rec: Dictionary, pockets: Array, origin: Dictionary) -> Array:
	var out: Array = []
	for slot in rec.get("gear", {}):
		var g = rec["gear"][slot]
		if g is Dictionary and ItemDB.has(String(g.get("type", ""))):
			out.append(_full(g, origin))
	var held = rec.get("held", null)
	if held is Dictionary and ItemDB.has(String(held.get("type", ""))):
		out.append(_full(held, origin))
	for it in pockets:
		if it is Dictionary and ItemDB.has(String(it.get("type", ""))):
			out.append(_full(it, origin))
	return out

## A complete item record from the short ones people carry ({type, qty, quality}).
static func _full(g: Dictionary, origin: Dictionary) -> Dictionary:
	var it: Dictionary = g.duplicate(true)
	it["uid"] = 0
	if not it.has("qty"):
		it["qty"] = 1
	if not it.has("quality"):
		it["quality"] = 1.0
	if not it.has("name"):
		it["name"] = ""
	if not it.has("origin"):
		it["origin"] = origin
	return it

## Days after which this body is gone.
static func gone_after(c: Dictionary) -> float:
	return PERSON_GONE_DAYS if c.get("kind", "") == "person" else ANIMAL_GONE_DAYS

static func expired(c: Dictionary, day: float) -> bool:
	return day - float(c.get("day", day)) >= gone_after(c)

## True while there is something left to take (or, for a carcass, to butcher).
static func has_any(c: Dictionary) -> bool:
	if c.get("kind", "") == "animal" and not c.get("butchered", false):
		return true
	if int(c.get("purse", 0)) > 0:
		return true
	var d = c.get("items")
	if d is Dictionary:
		for s in d.get("slots", []):
			if s != null:
				return true
	return false
