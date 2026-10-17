extends Node
## Global game state (autoload "Game"): the open world, the player's inventory and money,
## the in-game clock, and all saving. Every mutation of persistent state goes through here
## so it is saved promptly.

signal world_loaded
signal money_changed(money: int)
signal health_changed(health: float)
signal stats_changed
signal died(cause: String)
signal revived
signal leveled_up(level: int)
signal xp_gained(amount: int, why: String)
signal toast(text: String)
signal region_entered(name: String, era: int)
signal item_gained(type: String, qty: int)
signal saving ## Emitted before everything is written, so other systems can save too.
signal discovered(title: String, sub: String, color: Color) ## a wonder found or conquered

const DAY_SECONDS := 1440.0 ## One in-game day = 24 real minutes.
var day_seconds := DAY_SECONDS ## a server may set its own day length
var time_lock := -1.0 ## a server's always-day (0.5) or always-night (0.0); -1 = the clock runs
const AUTOSAVE_INTERVAL := 10.0
const DIRTY_FLUSH_DELAY := 0.75

var store: WorldStore
var seed: int = 0 ## the current planet's terrain seed
var home_seed: int = 0 ## the world's own seed; every planet of its system derives from it
var planet := 0 ## which planet of the system you are on (0 = home)
var inventory := Inventory.new()
var money := 0
var health := 100.0
var stamina := 100.0
var stats := Stats.new()
var crime := Crime.new() ## bounties and wanted level, per settlement
var day := 0.3
var discovery: Dictionary = {"visited": {}, "regions": {}}
var player: Node3D ## Set by the player when it spawns.
var pending_player_state = null
## Armour you are wearing, by slot (ARMOR_SLOTS); saved with the player.
var equipment: Dictionary = {}
const ARMOR_SLOTS := ["head", "chest", "hands", "legs", "feet", "shield", "back", "ring", "neck"]
signal equipment_changed
## Timed effects from food, potions and scrolls: id -> seconds left (Effects.BUFFS).
var buffs: Dictionary = {}
## Health still to come back from a meal or a salve, a little each second.
var regen_left := 0.0
signal buffs_changed

## Your vehicles out in the world (VehicleManager); saved with the player.
var vehicles: Array = []
## Where you last left each planet for orbit (planet -> Vector2), to land there again.
var landings: Dictionary = {}
var markers := Markers.new() ## map pins and teleporters
var guilds: Dictionary = {} ## guild (TownShops.GUILDS key) -> {day, town}
var estates: Array = [] ## houses you bought: TownShops.estate records
var map := WorldMap.new() ## the painted atlas under its fog of war
## Treasure hunts from maps you picked up: Treasure.new_hunt records, kept found or not.
var treasure: Array = []
signal treasure_started(hunt: Dictionary)
signal treasure_found(hunt: Dictionary)

var _dirty_chunks: Dictionary = {} ## Vector2i -> chunk dict
var _dirty_timer := 0.0
var _player_dirty := false
var _autosave_timer := 0.0
var _current_region := ""

func _ready() -> void:
	equipment_changed.connect(refresh_bonus)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	inventory.changed.connect(_on_inventory_changed)

func is_playing() -> bool:
	return store != null

# --- World lifecycle -----------------------------------------------------------

func new_world(name: String, seed_text: String) -> void:
	var s := seed_text.strip_edges()
	var sd: int
	if s == "":
		sd = randi()
	elif s.is_valid_int():
		sd = s.to_int()
	else:
		sd = WHash.str_hash(s)
	store = WorldStore.create_world(name if name.strip_edges() != "" else "New World", sd, "human")
	_begin(true)

func load_world(id: String) -> bool:
	var s := WorldStore.open_world(id)
	if s == null:
		return false
	store = s
	_begin(false)
	return true

## Plays on a server: `s` (a RemoteStore) already holds the world's meta and your save.
func join_remote(s: WorldStore) -> void:
	store = s
	_begin(false)

func _begin(fresh: bool) -> void:
	home_seed = store.meta["seed"]
	seed = home_seed
	day = store.meta.get("day", 0.3)
	inventory = Inventory.new()
	inventory.changed.connect(_on_inventory_changed)
	_dirty_chunks.clear()
	_current_region = ""
	pending_player_state = null
	vehicles = []
	equipment = {}
	landings = {}
	markers = Markers.new()
	crime = Crime.new()
	guilds = {}
	estates = []
	treasure = []
	buffs = {}
	regen_left = 0.0
	var p = store.load_player()
	_enter_planet(int(p.get("planet", 0)) if p is Dictionary else 0)
	if p is Dictionary:
		inventory.from_data(p.get("inventory", {}))
		money = p.get("money", 0)
		stats = Stats.from_data(p.get("stats"))
		health = clampf(p.get("health", 100.0), 0.0, stats.max_health())
		if health <= 0.0:
			# Saved while dead (before death existed, or mid-respawn): wake up healed.
			health = stats.max_health()
		dead = false
		stamina = stats.max_stamina()
		vehicles = p.get("vehicles", []).duplicate(true)
		equipment = p.get("equipment", {}).duplicate(true)
		landings = p.get("landings", {}).duplicate()
		markers = Markers.from_data(p.get("markers"))
		crime = Crime.from_data(p.get("crime"))
		guilds = (p.get("guilds", {}) as Dictionary).duplicate(true)
		estates = (p.get("estates", []) as Array).duplicate(true)
		treasure = (p.get("treasure", []) as Array).duplicate(true)
		var bf = p.get("buffs", {})
		if bf is Dictionary:
			for id in bf:
				if Effects.BUFFS.has(id):
					buffs[id] = float(bf[id])
		regen_left = float(p.get("regen", 0.0))
		refresh_bonus()
		pending_player_state = p
	else:
		money = 50
		stats = Stats.new()
		health = stats.max_health()
		stamina = stats.max_stamina()
		var o := {"how": "starter", "era": -1, "chunk": Vector2i.ZERO}
		inventory.add(ItemDB.make("pickaxe_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("axe_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("sword_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("binoculars", 1, 1.0, o))
		inventory.add(ItemDB.make("bread", 4, 1.0, o))
		inventory.add(ItemDB.make("crossbow", 1, 1.0, o))
		inventory.add(ItemDB.make("bolt", 24, 1.0, o))
		inventory.add(ItemDB.make("torch", 2, 1.0, o))
		inventory.add(ItemDB.make("lockpick", 5, 1.0, o))
	store.meta["last_played"] = Time.get_unix_time_from_system()
	store.save_meta()
	save_player()
	world_loaded.emit()

func close_world() -> void:
	if store == null:
		return
	save_all()
	map.close()
	store = null
	player = null
	day_seconds = DAY_SECONDS
	time_lock = -1.0
	Planets.apply(Planets.get_planet(0, 0)) # back to an ordinary world for the title screen
	WorldField.terrain_v = ChunkGenerator.GEN_VERSION

## Travel: saves this planet's land and map, then makes `n` the planet that streams in.
func set_planet(n: int) -> void:
	if store == null or n == planet:
		return
	flush_chunks()
	store.save_discovery(discovery)
	map.save()
	_enter_planet(n)
	_player_dirty = true

## Joins a guild (TownShops.GUILDS key); membership counts in every hall of it.
func join_guild(kind: String, town: String) -> void:
	guilds[kind] = {"day": day, "town": town}
	_player_dirty = true

## Takes the deed to a house (TownShops.estate) and marks it on the map.
func buy_house(e: Dictionary) -> void:
	estates.append(e)
	markers.add("Your house, %s" % e.get("town", ""), float(e["x"]), float(e["z"]), int(e.get("planet", planet)))
	_player_dirty = true

## Where you wake after falling: the door of your nearest house on this planet, if any.
func home_near(at: Vector3) -> Variant:
	var best = null
	var bd := INF
	for e in estates:
		if int(e.get("planet", 0)) != planet:
			continue
		var p := Vector2(float(e["dx"]), float(e["dz"]))
		var d := p.distance_to(Vector2(at.x, at.z))
		if d < bd:
			bd = d
			best = p
	return best

## True when `at` is inside a house you own (what's in it is yours to take).
func owns_house_at(at: Vector3) -> bool:
	for e in estates:
		if int(e.get("planet", 0)) == planet and Vector2(float(e["x"]), float(e["z"])).distance_to(Vector2(at.x, at.z)) < 7.0:
			return true
	return false

## Steps through the world portal at `from` (on this world) to world `n`: you come out
## beside a portal there (WorldPortal.arrival), and the portal you used is where you
## come back out on this world.
func travel_portal(who: Node3D, n: int, from: Vector2) -> void:
	if n == planet or store == null:
		return
	landings[planet] = from
	var st: Dictionary = who.get_state() if who != null and who.has_method("get_state") else {}
	if who != null:
		who.set_physics_process(false)
	player = null
	set_planet(n)
	var g := ChunkGenerator.new(seed, store.has_rivers())
	var at := WorldPortal.arrival(g, landings.get(n))
	st["pos"] = at if at != Vector3.INF else Planets.spawn_point(seed, store.has_rivers())
	st["drop"] = true
	st["riding"] = -1
	pending_player_state = st
	save_player()
	var info := planet_info()
	toast.emit("You step out on %s, %s" % [info["name"], Planets.theme_label(info).to_lower()])
	get_tree().change_scene_to_file.call_deferred("res://src/world/world.tscn")

# --- Treasure maps ---------------------------------------------------------------

func _on_inventory_changed() -> void:
	_player_dirty = true
	if player == null or store == null:
		return
	# However a map reached your pack (a cache, a body, a trade), picking it up starts its hunt.
	for i in inventory.slots.size():
		var it = inventory.get_slot(i)
		if it != null and Treasure.is_map(it["type"]) and not it.has("hunt"):
			start_treasure(it)

## Reads map `it` for the first time: buries its chest out there and marks the spot.
func start_treasure(it: Dictionary) -> Dictionary:
	var id := 1
	for h in treasure:
		id = maxi(id, int(h["id"]) + 1)
	it["hunt"] = id
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, id, Time.get_ticks_usec(), it.get("uid", 0)])
	var at: Vector3 = player.global_position
	var h := Treasure.new_hunt(id, ChunkGenerator.new(seed, store.has_rivers()), Vector2(at.x, at.z), planet, rng)
	treasure.append(h)
	var m := markers.add(Treasure.marker_name(h), float(h["x"]), float(h["z"]), planet, "treasure", {"hunt": id, "color": 2})
	h["marker"] = m["id"]
	_player_dirty = true
	toast.emit("%s! %s" % [ItemDB.display_name(it), Treasure.hint(h, at)])
	treasure_started.emit(h)
	return h

func hunt(id: int) -> Dictionary:
	for h in treasure:
		if int(h["id"]) == id:
			return h
	return {}

## The chest of a hunt was opened or broken: the hunt is over, its map and marker go.
func finish_treasure(id: int) -> void:
	var h := hunt(id)
	if h.is_empty() or h.get("found", false):
		return
	h["found"] = true
	markers.remove(int(h.get("marker", -1)))
	for i in inventory.slots.size():
		var it = inventory.get_slot(i)
		if it != null and int(it.get("hunt", -1)) == id:
			inventory.remove_at(i, 1)
			break
	_player_dirty = true
	add_xp(Treasure.XP, "Treasure found")
	discovered.emit("Treasure found", "Zone level %d" % int(h.get("level", 1)), Color(0.95, 0.78, 0.42))
	treasure_found.emit(h)

## Something saved with the player changed (markers, for one).
func touch_player() -> void:
	_player_dirty = true

func _enter_planet(n: int) -> void:
	planet = clampi(n, 0, Planets.COUNT - 1)
	store.set_planet(planet)
	seed = Planets.seed_of(home_seed, planet)
	WorldField.terrain_v = store.terrain_version()
	Planets.apply(planet_info())
	discovery = store.load_discovery()
	map.open(store, discovery["visited"])
	_current_region = ""

func planet_info() -> Dictionary:
	return Planets.get_planet(home_seed, planet, world_theme())

## Every world linked to this one (Planets.system), home first.
func worlds() -> Array:
	return Planets.system(home_seed, world_theme())

## "human" for worlds made since world themes exist; "" for older, mixed worlds.
func world_theme() -> String:
	return String(store.meta.get("theme", "")) if store != null else ""

func save_all() -> void:
	if store == null:
		return
	saving.emit()
	flush_chunks()
	save_player()
	store.meta["day"] = day
	store.meta["last_played"] = Time.get_unix_time_from_system()
	store.save_meta()
	store.save_discovery(discovery)
	map.save()

func save_player() -> void:
	if store == null:
		return
	var d := {"inventory": inventory.to_data(), "money": money, "health": health, "stats": stats.to_data(), "vehicles": vehicles, "equipment": equipment, "planet": planet, "landings": landings, "markers": markers.to_data(), "guilds": guilds, "estates": estates, "crime": crime.to_data(), "treasure": treasure, "buffs": buffs, "regen": regen_left}
	if player != null and player.has_method("get_state"):
		d.merge(player.get_state(), true)
	elif pending_player_state is Dictionary:
		for k in ["pos", "yaw", "pitch", "slot", "riding"]:
			if pending_player_state.has(k):
				d[k] = pending_player_state[k]
	store.save_player(d)
	_player_dirty = false

func _process(delta: float) -> void:
	if store == null:
		return
	if not get_tree().paused:
		if time_lock >= 0.0:
			day = floorf(day) + time_lock
		else:
			day += delta / day_seconds
		_tick_effects(delta)
		map.process(delta, player)
		store.meta["play_time"] = store.meta.get("play_time", 0.0) + delta
	if not _dirty_chunks.is_empty():
		_dirty_timer -= delta
		if _dirty_timer <= 0.0:
			flush_chunks()
	_autosave_timer += delta
	if _player_dirty or _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_player()
		store.meta["day"] = day
		store.save_meta()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_all()

# --- Chunks --------------------------------------------------------------------

func mark_chunk_dirty(chunk: Dictionary) -> void:
	_dirty_chunks[Vector2i(chunk["cx"], chunk["cz"])] = chunk
	_dirty_timer = DIRTY_FLUSH_DELAY

func flush_chunks() -> void:
	if store == null:
		return
	for k in _dirty_chunks:
		store.save_chunk(_dirty_chunks[k])
	_dirty_chunks.clear()

func visit_chunk(chunk: Dictionary) -> void:
	var key := "%d,%d" % [chunk["cx"], chunk["cz"]]
	if not discovery["visited"].has(key):
		discovery["visited"][key] = {"day": day, "era": chunk["era"], "region": chunk["region"]}
		store.save_discovery(discovery)
	var region: String = chunk["region"]
	if region != _current_region:
		_current_region = region
		var first: bool = not discovery["regions"].has(region)
		if first:
			discovery["regions"][region] = {"day": day, "era": chunk["era"], "at": key}
			store.save_discovery(discovery)
			if discovery["regions"].size() > 1:
				add_xp(40.0, "Discovered " + region)
		region_entered.emit(region, chunk["era"])

# --- Player economy -------------------------------------------------------------

func add_money(n: int) -> void:
	money += n
	_player_dirty = true
	money_changed.emit(money)

func mark_player_dirty() -> void:
	_player_dirty = true

func give(item: Dictionary) -> bool:
	if item["type"] == "_marks":
		add_money(item["qty"])
		item_gained.emit("_marks", item["qty"])
		return true
	var left := inventory.add(item)
	if left > 0:
		toast.emit("Inventory full")
		return false
	item_gained.emit(item["type"], item["qty"])
	return true

## Console cheats for this session (not saved): god = no damage.
var cheats := {"god": false}

var dead := false

func set_health(h: float, cause: String = "") -> void:
	if (cheats["god"] or dead) and h < health:
		return
	health = clampf(h, 0.0, stats.max_health())
	_player_dirty = true
	health_changed.emit(health)
	if health <= 0.0 and not dead:
		dead = true
		died.emit(cause if cause != "" else "You died")

## Who you are: the owner id on what you leave in the world, such as the bag you drop
## when you die. Net's (the multiplayer layer) once it is there, "solo" offline.
func my_id() -> String:
	var net := get_node_or_null("/root/Net")
	return String(net.my_id()) if net and net.has_method("my_id") else "solo"

## Your name as other players see it ("" offline).
func my_name() -> String:
	var net := get_node_or_null("/root/Net")
	return String(net.player_name(my_id())) if net and net.has_method("player_name") and net.has_method("online") and net.online() else ""

## A server option (Net.option), or `fallback` offline or before Net exists.
func server_option(key: String, fallback):
	var net := get_node_or_null("/root/Net")
	if net and net.has_method("option"):
		var v = net.option(key)
		return fallback if v == null else v
	return fallback

## Everything you carry, wear and have in your purse, packed into a bag record
## (DeathBag.make) and taken off you: you have just died.
func pack_death_bag() -> Dictionary:
	var bag := DeathBag.make(my_id(), my_name(), inventory, equipment, money, Time.get_unix_time_from_system())
	for i in inventory.capacity:
		inventory.slots[i] = null
	inventory.changed.emit()
	equipment = {}
	equipment_changed.emit()
	money = 0
	money_changed.emit(money)
	_player_dirty = true
	return bag

## Puts armour from your dropped bag back on: `worn` is slot -> the uid of the piece worn
## there, and entries are dropped once that piece is on again (or the slot is taken).
func rewear(worn: Dictionary) -> void:
	var on := 0
	for slot in worn.keys():
		if equipment.has(slot):
			worn.erase(slot)
			continue
		for i in inventory.capacity:
			var it = inventory.get_slot(i)
			if it is Dictionary and int(it.get("uid", 0)) == int(worn[slot]) and armor_slot_of(it) == slot:
				equipment[slot] = inventory.remove_at(i, 1)
				worn.erase(slot)
				on += 1
				break
	if on > 0:
		_player_dirty = true
		equipment_changed.emit()
		toast.emit("You put your armour back on")

## Back on your feet after dying: full health and stamina. You keep your pack.
func revive() -> void:
	dead = false
	buffs = {}
	regen_left = 0.0
	stats.bonus = Effects.bonus(equipment, buffs)
	health = stats.max_health()
	stamina = stats.max_stamina()
	_player_dirty = true
	health_changed.emit(health)
	revived.emit()

## Puts on armour from an inventory slot, swapping out whatever was in its place.
func equip(slot_index: int) -> bool:
	var it = inventory.get_slot(slot_index)
	if it == null or ItemDB.def(it["type"]).get("kind", "") != "armor":
		return false
	var where: String = ItemDB.def(it["type"])["slot"]
	inventory.remove_at(slot_index, 1)
	if equipment.has(where):
		# Whatever was worn there goes back into the slot the new piece came from.
		if inventory.get_slot(slot_index) == null:
			inventory.set_slot(slot_index, equipment[where])
		else:
			inventory.add(equipment[where])
	equipment[where] = it
	_player_dirty = true
	equipment_changed.emit()
	toast.emit("Wearing %s" % ItemDB.display_name(it))
	return true

func unequip(where: String) -> bool:
	if not equipment.has(where):
		return false
	if inventory.add(equipment[where]) != 0:
		toast.emit("No room to take it off")
		return false
	equipment.erase(where)
	_player_dirty = true
	equipment_changed.emit()
	return true

## Takes armour off into a chosen pack slot. If that slot holds armour for the same
## place, the two swap; if it holds something else, the armour goes to any free slot.
func unequip_to(where: String, slot_index: int) -> bool:
	if not equipment.has(where):
		return false
	var there = inventory.get_slot(slot_index)
	if there == null:
		var it: Dictionary = equipment[where]
		equipment.erase(where)
		inventory.set_slot(slot_index, it)
		_player_dirty = true
		equipment_changed.emit()
		return true
	if armor_slot_of(there) == where:
		return equip(slot_index)
	return unequip(where)

## Where a piece of armour is worn ("head", "chest", ...), or "" if it isn't armour.
static func armor_slot_of(it) -> String:
	if it == null or ItemDB.def(it["type"]).get("kind", "") != "armor":
		return ""
	return String(ItemDB.def(it["type"]).get("slot", ""))

## Total armour worn (and any warding).
func armor() -> float:
	var a := float(stats.bonus.get("armor", 0.0))
	for k in equipment:
		var it: Dictionary = equipment[k]
		a += float(ItemDB.stats(it).get("armor", 0.0)) * float(it.get("quality", 1.0))
	return a

## Recomputes what worn trinkets and timed effects add to your stats.
func refresh_bonus() -> void:
	stats.bonus = Effects.bonus(equipment, buffs)
	health = minf(health, stats.max_health())
	stamina = minf(stamina, stats.max_stamina())
	stats_changed.emit()
	buffs_changed.emit()

## Starts (or renews, never shortens) a timed effect.
func add_buff(id: String, secs: float) -> void:
	if id == "poison" and buffs.has("immune"):
		return
	buffs[id] = maxf(float(buffs.get(id, 0.0)), secs)
	_player_dirty = true
	refresh_bonus()

func has_buff(id: String) -> bool:
	return buffs.has(id)

## Clears every harmful effect (poison).
func cure() -> void:
	for id in buffs.keys():
		if Effects.BUFFS.get(id, {}).get("bad", false):
			buffs.erase(id)
	refresh_bonus()

func _tick_effects(delta: float) -> void:
	if player == null or dead:
		return
	if not buffs.is_empty():
		var hurt_by := Effects.damage_per_sec(buffs)
		if hurt_by > 0.0:
			set_health(health - hurt_by * delta, "Poison took you")
		var gone := Effects.tick(buffs, delta)
		if not gone.is_empty():
			_player_dirty = true
			refresh_bonus()
			for id in gone:
				if not Effects.BUFFS[id].get("hidden", false):
					toast.emit("%s wore off" % Effects.BUFFS[id]["name"])
	var heal := 0.0
	if regen_left > 0.0:
		heal = minf(regen_left, Effects.REGEN_RATE * delta)
		regen_left -= heal
	heal += float(stats.bonus.get("regen", 0.0)) * delta
	if heal > 0.0 and health < stats.max_health():
		set_health(health + heal)

func wearing_affix(id: String) -> bool:
	for k in equipment:
		if Rarity.has_affix(equipment[k], id):
			return true
	return false

## Damage from an attack after armour (each 100 armour halves it). Thorned armour hurts
## the attacker back: `reflect` gets the amount to return.
func hurt(dmg: float, cause: String, reflect: Callable = Callable()) -> float:
	var taken := dmg * 100.0 / (100.0 + armor())
	set_health(health - taken, cause)
	if reflect.is_valid() and wearing_affix("thorns"):
		reflect.call(dmg * 0.25)
	return taken

func max_health() -> float:
	return stats.max_health()

func max_stamina() -> float:
	return stats.max_stamina()

## Spends stamina for an action. Returns false (and spends nothing) if there is not
## enough; god mode never tires.
func use_stamina(n: float) -> bool:
	if cheats["god"]:
		return true
	if stamina < n:
		return false
	stamina -= n
	return true

func set_stamina(v: float) -> void:
	stamina = clampf(v, 0.0, stats.max_stamina())

## Experience for doing things in the world: gathering, crafting, building, hunting and
## discovering. Levels grant attribute points (spent on the Character screen).
func add_xp(amount: float, why: String = "") -> void:
	var before := stats.xp
	var lv := stats.level
	var gained := stats.add_xp(amount)
	_player_dirty = true
	xp_gained.emit(stats.xp - before if gained == 0 else int(amount * stats.xp_mult()), why)
	if gained > 0:
		# Levelling up restores you, and new Endurance may have raised the caps.
		set_health(stats.max_health())
		stamina = stats.max_stamina()
		for i in gained:
			leveled_up.emit(lv + i + 1)
	stats_changed.emit()

func spend_point(attr: String) -> bool:
	if not stats.spend(attr):
		return false
	if attr == "end":
		set_health(health + 10.0)
		stamina = minf(stamina + 8.0, stats.max_stamina())
	_player_dirty = true
	stats_changed.emit()
	return true

func spend_skill_point(sk: String) -> bool:
	if not stats.spend_skill(sk):
		return false
	_player_dirty = true
	stats_changed.emit()
	return true

## Practice at a skill from doing it; tells you when it goes up.
func practice(sk: String, amount: float) -> void:
	var gained := stats.practice(sk, amount)
	_player_dirty = true
	if gained > 0:
		toast.emit("%s rose to %d" % [Stats.SKILL_NAMES[sk], stats.skills[sk]])
		stats_changed.emit()

## A crime someone saw: adds to the bounty in that settlement and says what it came to.
signal wanted_changed
func add_bounty(sid: String, town: String, amount: int, why: String) -> void:
	var before := crime.stars(sid, day)
	var b := crime.add(sid, town, amount, day)
	var now_stars := Crime.stars_for(b)
	_player_dirty = true
	if now_stars > before:
		toast.emit("%s! Wanted in %s: %d star%s" % [why, town, now_stars, "" if now_stars == 1 else "s"])
	else:
		toast.emit("%s: bounty in %s is now %d Marks" % [why, town, b])
	wanted_changed.emit()

func clear_bounty(sid: String) -> void:
	crime.clear(sid)
	_player_dirty = true
	wanted_changed.emit()

func origin_here(how: String, era: int, chunk: Vector2i) -> Dictionary:
	return {"how": how, "era": era, "chunk": chunk, "day": snappedf(day, 0.01)}

# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	Bindings.load_and_apply()

## True after the last input came from a controller (menus then show focus highlights).
var using_pad := false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false
