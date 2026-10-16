extends Node
## Global game state (autoload "Game"): the open world, the player's inventory and money,
## the in-game clock, and all saving. Every mutation of persistent state goes through here
## so it is saved promptly.

signal world_loaded
signal money_changed(money: int)
signal health_changed(health: float)
signal toast(text: String)
signal region_entered(name: String, era: int)

const DAY_SECONDS := 1440.0 ## One in-game day = 24 real minutes.
const AUTOSAVE_INTERVAL := 10.0
const DIRTY_FLUSH_DELAY := 0.75

var store: WorldStore
var seed: int = 0
var inventory := Inventory.new()
var money := 0
var health := 100.0
var day := 0.3
var discovery: Dictionary = {"visited": {}, "regions": {}}
var player: Node3D ## Set by the player when it spawns.
var pending_player_state = null

var _dirty_chunks: Dictionary = {} ## Vector2i -> chunk dict
var _dirty_timer := 0.0
var _player_dirty := false
var _autosave_timer := 0.0
var _current_region := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	inventory.changed.connect(func(): _player_dirty = true)

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
	store = WorldStore.create_world(name if name.strip_edges() != "" else "New World", sd)
	_begin(true)

func load_world(id: String) -> bool:
	var s := WorldStore.open_world(id)
	if s == null:
		return false
	store = s
	_begin(false)
	return true

func _begin(fresh: bool) -> void:
	seed = store.meta["seed"]
	day = store.meta.get("day", 0.3)
	inventory = Inventory.new()
	inventory.changed.connect(func(): _player_dirty = true)
	discovery = store.load_discovery()
	_dirty_chunks.clear()
	_current_region = ""
	pending_player_state = null
	var p = store.load_player()
	if p is Dictionary:
		inventory.from_data(p.get("inventory", {}))
		money = p.get("money", 0)
		health = p.get("health", 100.0)
		pending_player_state = p
	else:
		money = 50
		health = 100.0
		var o := {"how": "starter", "era": -1, "chunk": Vector2i.ZERO}
		inventory.add(ItemDB.make("pickaxe_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("axe_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("sword_iron", 1, 1.0, o))
		inventory.add(ItemDB.make("bread", 4, 1.0, o))
	store.meta["last_played"] = Time.get_unix_time_from_system()
	store.save_meta()
	save_player()
	world_loaded.emit()

func close_world() -> void:
	if store == null:
		return
	save_all()
	store = null
	player = null

func save_all() -> void:
	if store == null:
		return
	flush_chunks()
	save_player()
	store.meta["day"] = day
	store.meta["last_played"] = Time.get_unix_time_from_system()
	store.save_meta()
	store.save_discovery(discovery)

func save_player() -> void:
	if store == null:
		return
	var d := {"inventory": inventory.to_data(), "money": money, "health": health}
	if player != null and player.has_method("get_state"):
		d.merge(player.get_state(), true)
	elif pending_player_state is Dictionary:
		for k in ["pos", "yaw", "pitch", "slot"]:
			if pending_player_state.has(k):
				d[k] = pending_player_state[k]
	store.save_player(d)
	_player_dirty = false

func _process(delta: float) -> void:
	if store == null:
		return
	if not get_tree().paused:
		day += delta / DAY_SECONDS
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
		region_entered.emit(region, chunk["era"])

# --- Player economy -------------------------------------------------------------

func add_money(n: int) -> void:
	money += n
	_player_dirty = true
	money_changed.emit(money)

func give(item: Dictionary) -> bool:
	if item["type"] == "_marks":
		add_money(item["qty"])
		toast.emit("+%d Marks" % item["qty"])
		return true
	var left := inventory.add(item)
	if left > 0:
		toast.emit("Inventory full")
		return false
	toast.emit("+%d %s" % [item["qty"], ItemDB.display_name(item)])
	return true

func set_health(h: float) -> void:
	health = clampf(h, 0.0, 100.0)
	_player_dirty = true
	health_changed.emit(health)

func origin_here(how: String, era: int, chunk: Vector2i) -> Dictionary:
	return {"how": how, "era": era, "chunk": chunk, "day": snappedf(day, 0.01)}

# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E], "inventory": [KEY_TAB, KEY_I], "craft": [KEY_R],
		"pause": [KEY_ESCAPE], "eat": [KEY_F], "map": [KEY_M],
		"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3],
		"slot_4": [KEY_4], "slot_5": [KEY_5], "slot_6": [KEY_6],
		"debug_overlay": [KEY_F3], "screenshot": [KEY_F12],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	if not InputMap.has_action("use"):
		InputMap.add_action("use")
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use", m)
