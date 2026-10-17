class_name WonderEffects
## What using a wonder (see Wonders) does for you. Every gift is rolled from the world
## seed and the object, so a relic gives the same thing whoever wakes it.

const WAKE_XP := 80.0
const BEACON_XP := 30.0
const RUNES_XP := 25.0
const LOOK := 1600.0 ## how far a beacon or runestone knows the way to a settlement

static var _gen: ChunkGenerator
static var _gen_seed := 0

## Uses wonder `o` in `chunk`; returns the line to show. Call only when Wonders.use_of(o)
## offers something.
static func apply(o: Dictionary, chunk: ChunkNode, player: Player) -> String:
	var st: Dictionary = o["st"]
	var today := int(floor(Game.day))
	var wp: Vector3 = chunk.position + o["p"]
	var rng := WHash.rng(Game.seed, chunk.key.x * 4099 + int(o["i"]), chunk.key.y, 9311 + today)
	var origin := Game.origin_here("found", o["e"], chunk.key)
	var msg := ""
	match String(o["t"]):
		"alien_ruin":
			var noun := ObjectLibrary.label_of(o)
			_restore(1.0)
			if not st.get("woke", false):
				st["woke"] = true
				var got := _give_all(ItemDB.roll_loot(clampi(int(o["e"]), 0, Eras.COUNT - 1), rng, origin, 0.8))
				Game.add_xp(WAKE_XP, "Discovery")
				msg = "The %s wakes. Light pours from its core and restores you%s" % [noun, ", and it gives up %s" % got if got != "" else ""]
			else:
				msg = "You draw strength from the %s: health and stamina restored" % noun
				if rng.randf() < 0.35:
					var gift := _give_all([ItemDB.make("aether_crystal" if rng.randf() < 0.7 else "data_core", 1, rng.randf_range(0.9, 1.2), origin)])
					if gift != "":
						msg += ", and a %s falls from the core" % gift
		"beacon":
			if not st.get("lit", false):
				st["lit"] = true
				var pod := _drop_pod(o, chunk, rng, origin)
				Game.add_xp(BEACON_XP, "Discovery")
				msg = "The beacon blazes up and calls down a supply pod" if pod else "The beacon blazes up"
				var way := _mark_settlement(wp)
				if way != "":
					msg += ". It shows the way to %s" % way
			else:
				var way := _mark_settlement(wp)
				msg = ("The beacon points you to %s" % way) if way != "" else "The beacon has nothing new to show you"
		"standing_stone":
			st["read"] = true
			Game.add_xp(RUNES_XP, "Discovery")
			var way := _mark_settlement(wp)
			msg = ("The runes name %s" % way) if way != "" else "The runes tell of the old roads, long gone"
		"crystal_shard":
			_restore(0.0)
			var charged := _charge_lights(player)
			var gift := _give_all([ItemDB.make("aether_crystal", rng.randi_range(1, 2), rng.randf_range(0.9, 1.2), origin)])
			msg = "The crystal hums: stamina restored%s%s" % [", your flashlight recharged" if charged else "", ", and it sheds %s" % gift if gift != "" else ""]
		"well":
			Game.set_stamina(Game.stats.max_stamina())
			Game.set_health(Game.health + 10.0)
			msg = "Cool, clear water: stamina restored"
	st["day"] = today
	Game.mark_chunk_dirty(chunk.data)
	return msg

## Full stamina, and `health` of the way to full health (0 leaves health as it is).
static func _restore(health: float) -> void:
	Game.set_stamina(Game.stats.max_stamina())
	if health > 0.0:
		Game.set_health(lerpf(Game.health, Game.stats.max_health(), health))

## Gives every item; returns what was received, as words ("" if nothing fit).
static func _give_all(items: Array) -> String:
	var got := {} ## name -> how many
	for it in items:
		var qty := int(it.get("qty", 1))
		var nm := "marks" if it["type"] == "_marks" else ItemDB.display_name(it).to_lower()
		if Game.give(it):
			got[nm] = int(got.get(nm, 0)) + qty
	var names: Array = []
	for nm in got:
		var n: int = got[nm]
		names.append(nm if n <= 1 else "%d %s%s" % [n, nm, "" if nm.ends_with("s") else "s"])
	if names.size() > 1:
		return ", ".join(names.slice(0, names.size() - 1)) + " and " + String(names[-1])
	return names[0] if names.size() == 1 else ""

## Recharges every flashlight you carry, dead ones too. True if any were.
static func _charge_lights(player: Player) -> bool:
	var any := false
	for i in Inventory.SIZE:
		var s = Game.inventory.get_slot(i)
		if s != null and (s["type"] == "flashlight" or s["type"] == "flashlight_dead"):
			s["type"] = "flashlight"
			s["charge"] = HandLight.FLASH_CHARGE
			any = true
	if any:
		Game.inventory.changed.emit()
	return any

## A supply pod lands beside the beacon, on the beacon's chunk. True if there was room.
static func _drop_pod(o: Dictionary, chunk: ChunkNode, rng: RandomNumberGenerator, origin: Dictionary) -> bool:
	for tries in 8:
		var a := rng.randf() * TAU
		var lp: Vector3 = o["p"] + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.5, 5.5)
		if lp.x < 1.0 or lp.z < 1.0 or lp.x > ChunkGenerator.SIZE - 1.0 or lp.z > ChunkGenerator.SIZE - 1.0:
			continue
		lp.y = ChunkGenerator.height_at(chunk.data, lp.x, lp.z)
		var era := clampi(int(o["e"]), 0, Eras.COUNT - 1)
		chunk.add_object("supply_pod", lp, a + PI, era, {"loot": ItemDB.roll_loot(era, rng, origin, 0.5)})
		return true
	return false

## Puts the nearest settlement you haven't marked on the atlas. Returns "Name, 640 m to
## the northeast" or "" when every one in reach is already marked.
static func _mark_settlement(wp: Vector3) -> String:
	if _gen == null or _gen_seed != Game.seed:
		_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers() if Game.store else true)
		_gen_seed = Game.seed
	var here := Vector2(wp.x, wp.z)
	var marked := {}
	for m in Game.markers.on_planet(Game.planet):
		marked[String(m["name"])] = true
	var best := {}
	var bd := INF
	for s in _gen.settlements_near(here.x - LOOK, here.y - LOOK, here.x + LOOK, here.y + LOOK):
		var c: Vector2 = s["center"]
		var name := _gen.field.region_name_at(c.x, c.y)
		var d := c.distance_to(here)
		if d < bd and d > 40.0 and not marked.has(name):
			bd = d
			best = {"name": name, "c": c}
	if best.is_empty():
		return ""
	var c: Vector2 = best["c"]
	Game.markers.add(best["name"], c.x, c.y, Game.planet)
	Game.touch_player()
	return "%s, %d m to the %s (marked on your atlas)" % [best["name"], int(round(bd / 10.0)) * 10, Wonders.compass(here, c)]
