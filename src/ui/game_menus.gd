class_name GameMenus
extends Control
## Inventory, crafting, trading, map and pause screens. Owns mouse capture and pausing.

var player: Player
var streamer: ChunkStreamer
var _panel: Control
var _mode := ""
var _swap_from := -1
var _trader: Dictionary
var _trader_chunk: ChunkNode
var _store_obj: Dictionary ## the storage chest that is open
var _store_chunk: ChunkNode
var _store: Inventory

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("trade_ui")
	Game.inventory.changed.connect(_refresh)
	Game.money_changed.connect(func(_m): _refresh())
	Game.stats_changed.connect(func(): if _mode == "character": _refresh())

func is_open() -> bool:
	return _mode != ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _mode == "":
			open("pause")
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _mode != "" and event is InputEventJoypadButton:
		if _mode == "settings":
			open("pause")
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_toggle("inventory")
	elif event.is_action_pressed("craft"):
		_toggle("craft")
	elif event.is_action_pressed("map"):
		_toggle("map")
	elif event.is_action_pressed("character"):
		_toggle("character")
	elif event is InputEventMouseButton and event.pressed and _mode == "" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle(m: String) -> void:
	if _mode == m:
		close()
	elif _mode == "" or _mode != "pause":
		open(m)
	get_viewport().set_input_as_handled()

func open(m: String) -> void:
	_mode = m
	_swap_from = -1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.ui_open = true
	get_tree().paused = m == "pause" or m == "settings"
	if m == "pause" or m == "settings":
		Game.save_all()
	_refresh()

func close() -> void:
	_mode = ""
	if _panel:
		_panel.queue_free()
		_panel = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player:
		player.ui_open = false
	get_tree().paused = false

func open_trader(st: Dictionary, chunk: ChunkNode) -> void:
	_trader = st
	_trader_chunk = chunk
	open("trade")

func open_storage(o: Dictionary, chunk: ChunkNode) -> void:
	_store_obj = o
	_store_chunk = chunk
	_store = Storage.open(o)
	open("storage")

## Writes the open chest back into its chunk, to be saved.
func open_travel(o: Dictionary, chunk: ChunkNode) -> void:
	_store_obj = o
	_store_chunk = chunk
	open("travel")

func _store_changed() -> void:
	Storage.save(_store_obj, _store)
	if _store_chunk and is_instance_valid(_store_chunk):
		Game.mark_chunk_dirty(_store_chunk.data)
	_refresh()

func _refresh() -> void:
	if _mode == "":
		return
	if _panel:
		_panel.queue_free()
	match _mode:
		"pause": _panel = _pause_panel()
		"settings": _panel = _settings_panel()
		"inventory": _panel = _inventory_panel()
		"craft": _panel = _craft_panel()
		"trade": _panel = _trade_panel()
		"storage": _panel = _storage_panel()
		"travel": _panel = _travel_panel()
		"map": _panel = _map_panel()
		"character": _panel = _character_panel()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_panel.reset_size()
	_panel.position = (get_viewport_rect().size - _panel.get_combined_minimum_size()) * 0.5
	if Game.using_pad:
		UITheme.focus_first.call_deferred(_panel)

func _shell(title: String, subtitle: String = "") -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var h := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_child(UITheme.title(title))
	if subtitle != "":
		tv.add_child(UITheme.label(subtitle, 15, UITheme.DIM))
	h.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UITheme.label("%d Marks" % Game.money, 22, UITheme.ACCENT))
	h.add_child(UITheme.button("Close", close))
	v.add_child(h)
	return [p, v]

# --- Character -------------------------------------------------------------------

func _character_panel() -> Control:
	var st := Game.stats
	var nxt := Stats.xp_to_next(st.level)
	var s := _shell("Character", "Level %d  ·  %d / %d XP to the next level" % [st.level, st.xp, nxt] if st.level < Stats.MAX_LEVEL else "Level %d (max)" % st.level)
	var v: VBoxContainer = s[1]
	s[0].custom_minimum_size = Vector2(720, 0)
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(0, 10)
	xp.show_percentage = false
	xp.max_value = nxt
	xp.value = st.xp
	xp.add_theme_stylebox_override("fill", UITheme.sb(Color(0.92, 0.72, 0.28), Color(0, 0, 0, 0), 4, 0, 0))
	v.add_child(xp)
	v.add_child(UITheme.label("Points to spend: %d" % st.points if st.points > 0 else "No points to spend. Gather, craft, build, hunt and explore to level up.",
		18, UITheme.ACCENT if st.points > 0 else UITheme.DIM))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 10)
	for a in Stats.ATTRS:
		var attr: String = a
		g.add_child(UITheme.label(Stats.NAMES[attr], 20))
		var val := UITheme.label(str(st.attrs[attr]), 22, UITheme.ACCENT)
		val.custom_minimum_size = Vector2(40, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_child(val)
		var b := UITheme.button("+", func(): Game.spend_point(attr))
		b.disabled = st.points <= 0
		b.custom_minimum_size = Vector2(44, 0)
		g.add_child(b)
		g.add_child(UITheme.label(Stats.BLURBS[attr], 15, UITheme.DIM))
	v.add_child(g)
	v.add_child(HSeparator.new())
	var d := GridContainer.new()
	d.columns = 2
	d.add_theme_constant_override("h_separation", 24)
	for row in [["Health", "%d" % int(st.max_health())], ["Stamina", "%d" % int(st.max_stamina())],
			["Damage and harvesting", "x%.2f" % st.damage_mult()], ["Move speed", "x%.2f" % st.speed_mult()],
			["Swing speed", "x%.2f" % st.swing_mult()], ["Carry weight", "%.1f / %d kg" % [Game.inventory.weight(), int(st.carry_capacity())]],
			["Breath", "%d s" % int(st.max_breath())], ["Experience gain", "x%.2f" % st.xp_mult()],
			["Crafted quality", "x%.2f" % st.craft_quality_mult()]]:
		d.add_child(UITheme.label(row[0], 16, UITheme.DIM))
		d.add_child(UITheme.label(row[1], 16))
	v.add_child(d)
	return s[0]

# --- Pause -----------------------------------------------------------------------

func _pause_panel() -> Control:
	var s := _shell("Paused", Game.store.meta.get("name", "") if Game.store else "")
	var v: VBoxContainer = s[1]
	s[0].custom_minimum_size = Vector2(460, 0)
	v.add_child(UITheme.button("Resume", close))
	v.add_child(UITheme.button("Character", func(): open("character")))
	v.add_child(UITheme.button("Map", func(): open("map")))
	v.add_child(UITheme.button("Settings", func(): open("settings")))
	v.add_child(UITheme.button("Save and quit to menu", func():
		get_tree().paused = false
		Game.close_world()
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")))
	v.add_child(UITheme.button("Save and exit to desktop", func():
		Game.close_world()
		get_tree().quit()))
	var meta := Game.store.meta if Game.store else {}
	var pt := int(meta.get("play_time", 0.0))
	v.add_child(UITheme.label("Seed %d    Played %dh %02dm    %d places discovered" % [Game.seed, pt / 3600, (pt / 60) % 60, Game.discovery["visited"].size()], 14, UITheme.DIM))
	v.add_child(UITheme.label("Everything you see is saved the moment it first exists.", 14, UITheme.DIM))
	return s[0]

func _settings_panel() -> Control:
	var m := SettingsMenu.new()
	m.closed.connect(func(): open("pause"))
	return m

# --- Inventory ----------------------------------------------------------------------

func _slot_button(i: int) -> Button:
	var it = Game.inventory.get_slot(i)
	var b := Button.new()
	b.custom_minimum_size = Vector2(76, 76)
	b.add_theme_font_size_override("font_size", 12)
	if it != null:
		b.text = ("%d" % it["qty"]) if ItemDB.is_stackable(it["type"]) else ""
		b.icon = Icons.get_icon(it["type"])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.tooltip_text = UITheme.describe_item(it)
		var era: int = ItemDB.era_of(it["type"])
		var c: Color = UITheme.ERA_COLORS[era] if era >= 0 else Color(0.7, 0.7, 0.7)
		b.add_theme_stylebox_override("normal", UITheme.sb(Color(0.1, 0.11, 0.12, 0.9), c * Color(1, 1, 1, 0.5), 6, 1, 6))
	if i == _swap_from:
		b.add_theme_stylebox_override("normal", UITheme.sb(Color(0.25, 0.2, 0.1, 0.95), UITheme.ACCENT, 6, 2, 6))
	if i < Inventory.HOTBAR:
		b.add_theme_color_override("font_color", UITheme.ACCENT)
	b.pressed.connect(func():
		if _swap_from < 0:
			if Game.inventory.get_slot(i) != null:
				_swap_from = i
				_refresh()
		else:
			Game.inventory.swap(_swap_from, i)
			_swap_from = -1)
	# Drag and drop: drag any item onto another slot (or onto the hotbar row) to move,
	# swap or merge it.
	b.set_drag_forwarding(func(_at):
		if Game.inventory.get_slot(i) == null:
			return null
		var prev := TextureRect.new()
		prev.texture = Icons.get_icon(Game.inventory.get_slot(i)["type"])
		prev.custom_minimum_size = Vector2(56, 56)
		prev.size = Vector2(56, 56)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.set_drag_preview(prev)
		return {"inv_slot": i},
		func(_at, d): return d is Dictionary and d.has("inv_slot"),
		func(_at, d):
			_swap_from = -1
			if d["inv_slot"] != i:
				Game.inventory.swap(d["inv_slot"], i))
	return b

func _inventory_panel() -> Control:
	var s := _shell("Inventory", "Drag items between slots, or click one and then another. Hover for where things came from.")
	var v: VBoxContainer = s[1]
	var g := GridContainer.new()
	g.columns = Inventory.HOTBAR
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		g.add_child(_slot_button(i))
	v.add_child(g)
	v.add_child(UITheme.label("HOTBAR  ·  keys 1 to 0, or hold LB on a controller", 13, UITheme.ACCENT))
	var hb := GridContainer.new()
	hb.columns = Inventory.HOTBAR
	hb.add_theme_constant_override("h_separation", 6)
	for i in Inventory.HOTBAR:
		hb.add_child(_slot_button(i))
	v.add_child(hb)
	return s[0]

# --- Crafting ------------------------------------------------------------------------

const CRAFT_AMOUNTS := [1, 5, 10, 100]
const CRAFT_TABS := ["All", "Materials", "Tools", "Stations", "Building"]
var _craft_scroll := 0
var _craft_tab := "All"

static func _recipe_tab(r: Dictionary) -> String:
	match String(ItemDB.def(r["out"]).get("kind", "")):
		"tool", "weapon", "light": return "Tools"
		"station": return "Stations"
		"placeable": return "Building"
	return "Materials"

static func _icon_rect(type: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Icons.get_icon(type)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.tooltip_text = ItemDB.def(type).get("name", type)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

func _do_craft(r: Dictionary, times: int, stations: Dictionary) -> void:
	if not Recipes.station_ok(r, stations):
		return
	var pos := player.global_position if player else Vector3.ZERO
	var ck := ChunkStreamer.chunk_of(pos)
	var made := Recipes.craft_many(Game.inventory, r, Game.origin_here("crafted", -1, ck), times, Game.stats.craft_quality_mult())
	if made > 0:
		Game.item_gained.emit(r["out"], made * int(r["qty"]))
		# Experience grows with what the thing is worth, a little less for each in a batch.
		var each := 2.0 + sqrt(float(ItemDB.def(r["out"]).get("value", 1)) * int(r["qty"]))
		Game.add_xp(each * pow(made, 0.8), "Crafting")

func _craft_panel() -> Control:
	var s := _shell("Crafting", "Pick an amount, or Craft all. Some recipes need a station nearby; build them from the Stations tab.")
	var v: VBoxContainer = s[1]
	var here := player.global_position if player else Vector3.ZERO
	var stations := BuildCatalog.stations_near(streamer, here)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in CRAFT_TABS:
		var tab: String = t
		var tb := UITheme.button(tab, func():
			_craft_tab = tab
			_craft_scroll = 0
			_refresh())
		tb.toggle_mode = true
		tb.button_pressed = tab == _craft_tab
		tabs.add_child(tb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	var names: Array = []
	for st in stations:
		names.append(Recipes.STATION_NAMES.get(st, st))
	tabs.add_child(UITheme.label("Nearby: " + (", ".join(names) if not names.is_empty() else "no stations"), 15, UITheme.ACCENT if not names.is_empty() else UITheme.DIM))
	v.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(980, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	# Recipes you can make first, then the rest in their usual order.
	var order: Array = Recipes.LIST.filter(func(r): return _craft_tab == "All" or _recipe_tab(r) == _craft_tab)
	var ready := func(r): return Recipes.station_ok(r, stations) and Recipes.max_crafts(Game.inventory, r) > 0
	order.sort_custom(func(x, y): return ready.call(x) and not ready.call(y))
	for r in order:
		var at_ok := Recipes.station_ok(r, stations)
		var most := Recipes.max_crafts(Game.inventory, r) if at_ok else 0
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UITheme.sb(Color(0.1, 0.11, 0.12, 0.85 if most > 0 else 0.5), Color(1, 1, 1, 0.08), 6, 1, 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(_icon_rect(r["out"], 52))
		var name_box := VBoxContainer.new()
		name_box.custom_minimum_size = Vector2(210, 0)
		name_box.add_child(UITheme.label("%s%s" % [ItemDB.def(r["out"])["name"], (" x%d" % r["qty"]) if r["qty"] > 1 else ""], 17, UITheme.TEXT if most > 0 else UITheme.DIM))
		var status := ("Can make %d" % most) if most > 0 else "Missing materials"
		if not at_ok:
			status = "Needs a %s nearby" % Recipes.STATION_NAMES.get(r["at"], r["at"])
		name_box.add_child(UITheme.label(status, 13, UITheme.ACCENT if most > 0 else (Color(0.9, 0.55, 0.4) if not at_ok else UITheme.DIM)))
		row.add_child(name_box)
		var ins := HBoxContainer.new()
		ins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ins.add_theme_constant_override("separation", 12)
		for t in r["in"]:
			var have: int = Game.inventory.count(t)
			var need: int = r["in"][t]
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			chip.add_child(_icon_rect(t, 30))
			chip.add_child(UITheme.label("%d/%d" % [have, need], 15, UITheme.TEXT if have >= need else Color(0.9, 0.45, 0.4)))
			chip.tooltip_text = ItemDB.def(t)["name"]
			ins.add_child(chip)
		row.add_child(ins)
		for n in CRAFT_AMOUNTS:
			var amount: int = n
			var b := UITheme.button("x%d" % amount, func(): _do_craft(r, amount, stations))
			b.custom_minimum_size = Vector2(54, 0)
			b.disabled = most < amount
			row.add_child(b)
		var all := UITheme.button("All", func(): _do_craft(r, -1, stations))
		all.custom_minimum_size = Vector2(60, 0)
		all.disabled = most <= 0
		row.add_child(all)
		list.add_child(card)
	sc.get_v_scroll_bar().value_changed.connect(func(val): _craft_scroll = int(val))
	(func(): sc.scroll_vertical = _craft_scroll).call_deferred()
	v.add_child(sc)
	return s[0]

# --- Storage -------------------------------------------------------------------------

func _storage_panel() -> Control:
	var cname := String(BuildCatalog.def(BuildCatalog.id_of(_store_obj["t"])).get("name", "Chest"))
	var kg := Game.inventory.weight()
	var s := _shell(cname, "Click an item to move it across. Your pack: %.0f / %d kg." % [kg, int(Game.stats.carry_capacity())])
	var v: VBoxContainer = s[1]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.add_child(UITheme.label("IN THE %s  (%d / %d slots)" % [cname.to_upper(), _store.capacity - _store.free_slots(), _store.capacity], 15, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	bar.add_child(UITheme.button("Take all", func():
		Storage.transfer_all(_store, Game.inventory)
		_store_changed()))
	bar.add_child(UITheme.button("Store all (not the hotbar)", func():
		Storage.transfer_all(Game.inventory, _store, true)
		_store_changed()))
	v.add_child(bar)
	var g := GridContainer.new()
	g.columns = 10
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for i in _store.capacity:
		g.add_child(_move_button(_store, i, Game.inventory))
	v.add_child(g)
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label("YOUR PACK", 15, UITheme.ACCENT))
	var pg := GridContainer.new()
	pg.columns = 10
	pg.add_theme_constant_override("h_separation", 6)
	pg.add_theme_constant_override("v_separation", 6)
	for i in Inventory.SIZE:
		pg.add_child(_move_button(Game.inventory, i, _store))
	v.add_child(pg)
	return s[0]

## A slot that sends its whole stack to the other side when clicked.
func _move_button(from: Inventory, i: int, to: Inventory) -> Button:
	var it = from.get_slot(i)
	var b := Button.new()
	b.custom_minimum_size = Vector2(60, 60)
	b.add_theme_font_size_override("font_size", 12)
	if it != null:
		b.text = ("%d" % it["qty"]) if ItemDB.is_stackable(it["type"]) else ""
		b.icon = Icons.get_icon(it["type"])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.tooltip_text = UITheme.describe_item(it) + "\n%.1f kg" % (ItemDB.weight(it["type"]) * it["qty"])
		b.pressed.connect(func():
			if Storage.transfer(from, i, to) == 0:
				Game.toast.emit("No room")
			_store_changed())
	else:
		b.disabled = true
	return b

# --- Teleporters ----------------------------------------------------------------------

func _travel_panel() -> Control:
	var here := String(_store_obj.get("st", {}).get("name", "This teleporter"))
	var s := _shell(here, "Every teleporter and waystone you build on this world links to the others.")
	var v: VBoxContainer = s[1]
	var me := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	var any := false
	for m in Game.markers.on_planet(Game.planet, "teleporter"):
		var d := Vector2(m["x"], m["z"]).distance_to(me)
		if d < 6.0:
			continue
		any = true
		var row := HBoxContainer.new()
		var l := UITheme.label("%s   ·   %s away" % [m["name"], _dist(d)], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(420, 0)
		row.add_child(l)
		var mx: float = m["x"]
		var mz: float = m["z"]
		row.add_child(UITheme.button("Travel", func():
			close()
			if player:
				player.teleport_to(mx + 2.5, mz + 2.5)
			Game.toast.emit("Travelling to %s" % m["name"])))
		v.add_child(row)
	if not any:
		v.add_child(UITheme.label("No other teleporters yet. Build another one somewhere else to link them.", 16, UITheme.DIM))
	return s[0]

static func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

# --- Trading -------------------------------------------------------------------------

func _trade_panel() -> Control:
	var st := _trader
	var s := _shell(st["name"], "%s trader. Goods from other eras fetch a premium here; selling floods demand." % Eras.NAMES[st["era"]])
	var v: VBoxContainer = s[1]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	# Buy column.
	var buy := VBoxContainer.new()
	buy.custom_minimum_size = Vector2(420, 480)
	buy.add_child(UITheme.label("Buy", 20, UITheme.ACCENT))
	for t in st["stock"]:
		var qty: int = st["stock"][t]
		if qty <= 0:
			continue
		var price := Economy.sell_price(st, t)
		var row := HBoxContainer.new()
		var l := UITheme.label("%s  (%d)" % [ItemDB.def(t)["name"], qty], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := UITheme.button("%d" % price, func():
			if Game.money < price:
				Game.toast.emit("Not enough Marks")
				return
			var ck := _trader_chunk.key if _trader_chunk else Vector2i.ZERO
			var o := Game.origin_here("bought", st["era"], ck)
			if Game.give(ItemDB.make(t, 1, 1.0, o)):
				Game.add_money(-price)
				st["stock"][t] -= 1
				if _trader_chunk:
					Game.mark_chunk_dirty(_trader_chunk.data)
				_refresh())
		b.disabled = Game.money < price
		row.add_child(b)
		buy.add_child(row)
	h.add_child(buy)
	# Sell column.
	var sell_sc := ScrollContainer.new()
	sell_sc.custom_minimum_size = Vector2(460, 480)
	var sell := VBoxContainer.new()
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_sc.add_child(sell)
	sell.add_child(UITheme.label("Sell", 20, UITheme.ACCENT))
	for i in Inventory.SIZE:
		var it = Game.inventory.get_slot(i)
		if it == null:
			continue
		var unit := Economy.buy_price(st, it)
		var row := HBoxContainer.new()
		var l := UITheme.label("%s%s" % [ItemDB.display_name(it), ("  x%d" % it["qty"]) if ItemDB.is_stackable(it["type"]) else ""], 16)
		l.tooltip_text = UITheme.describe_item(it)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var idx := i
		row.add_child(UITheme.button("%d" % unit, func(): _sell(idx, 1)))
		if ItemDB.is_stackable(it["type"]) and it["qty"] > 1:
			row.add_child(UITheme.button("All", func(): _sell(idx, -1)))
		sell.add_child(row)
	h.add_child(sell_sc)
	return s[0]

func _sell(idx: int, qty: int) -> void:
	var it = Game.inventory.get_slot(idx)
	if it == null:
		return
	var n: int = it["qty"] if qty < 0 else qty
	var total := 0
	for k in n:
		total += Economy.buy_price(_trader, it)
		Economy.record_sale_to_trader(_trader, it["type"], 1)
	Game.inventory.remove_at(idx, n)
	Game.add_money(total)
	Game.toast.emit("Sold for %d Marks" % total)
	if _trader_chunk:
		Game.mark_chunk_dirty(_trader_chunk.data)
	_refresh()

# --- Map ------------------------------------------------------------------------------

func _map_panel() -> Control:
	var s := _shell("Atlas", "Every chunk you have seen, kept forever. %d chunks, %d regions." % [Game.discovery["visited"].size(), Game.discovery["regions"].size()])
	var v: VBoxContainer = s[1]
	var h := HBoxContainer.new()
	v.add_child(h)
	var m := MapView.new()
	m.player = player
	m.custom_minimum_size = Vector2(620, 560)
	m.changed.connect(_refresh)
	h.add_child(m)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_child(UITheme.label("Markers", 18, UITheme.ACCENT))
	side.add_child(UITheme.button("Mark where I stand", func():
		if player:
			var n := Game.markers.count_kind("pin") + 1
			Game.markers.add("Marker %d" % n, player.global_position.x, player.global_position.z, Game.planet)
			Game.touch_player()
			_refresh()))
	var me := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	for mk in Game.markers.on_planet(Game.planet):
		var row := HBoxContainer.new()
		var l := UITheme.label("%s  ·  %s" % [mk["name"], _dist(Vector2(mk["x"], mk["z"]).distance_to(me))], 14, Markers.color_of(mk))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if mk["kind"] == "pin":
			var id: int = mk["id"]
			row.add_child(UITheme.button("Remove", func():
				Game.markers.remove(id)
				Game.touch_player()
				_refresh()))
		side.add_child(row)
	side.add_child(HSeparator.new())
	side.add_child(UITheme.label("Regions discovered", 18, UITheme.ACCENT))
	var regions: Dictionary = Game.discovery["regions"]
	var names := regions.keys()
	names.sort_custom(func(a, b): return regions[a]["day"] < regions[b]["day"])
	for n in names.slice(maxi(0, names.size() - 10)):
		side.add_child(UITheme.label("%s  ·  day %d" % [n, int(regions[n]["day"]) + 1], 14, UITheme.ERA_COLORS[regions[n]["era"]]))
	h.add_child(side)
	return s[0]


class MapView extends Control:
	signal changed
	var player: Node3D
	var zoom := 6.0

	## Map pixel -> world x, z.
	func _world(p: Vector2) -> Vector2:
		var pc := Vector2.ZERO
		if player:
			pc = Vector2(player.global_position.x, player.global_position.z) / ChunkGenerator.SIZE
		return (pc + (p - size * 0.5) / zoom) * ChunkGenerator.SIZE

	func _screen(x: float, z: float) -> Vector2:
		var pc := Vector2.ZERO
		if player:
			pc = Vector2(player.global_position.x, player.global_position.z) / ChunkGenerator.SIZE
		return size * 0.5 + (Vector2(x, z) / ChunkGenerator.SIZE - pc) * zoom

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				# Click to drop a marker there.
				var w := _world(e.position)
				Game.markers.add("Marker %d" % (Game.markers.count_kind("pin") + 1), w.x, w.y, Game.planet)
				Game.touch_player()
				changed.emit()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				# Right-click a marker to remove it.
				for mk in Game.markers.on_planet(Game.planet, "pin"):
					if _screen(mk["x"], mk["z"]).distance_to(e.position) < 10.0:
						Game.markers.remove(mk["id"])
						Game.touch_player()
						changed.emit()
						break
			elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = minf(zoom * 1.2, 30.0)
				queue_redraw()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = maxf(zoom / 1.2, 1.5)
				queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.04, 0.9))
		var center := size * 0.5
		var pc := Vector2.ZERO
		if player:
			pc = Vector2(player.global_position.x, player.global_position.z) / ChunkGenerator.SIZE
		for key in Game.discovery["visited"]:
			var parts: PackedStringArray = key.split(",")
			var c := Vector2(parts[0].to_int(), parts[1].to_int())
			var p := center + (c - pc) * zoom
			if p.x < -zoom or p.y < -zoom or p.x > size.x or p.y > size.y:
				continue
			var era: int = Game.discovery["visited"][key]["era"]
			draw_rect(Rect2(p, Vector2(zoom, zoom) - Vector2.ONE * 0.5), UITheme.ERA_COLORS[era] * Color(0.8, 0.8, 0.8, 0.85))
		if player:
			var fwd := -player.global_transform.basis.z
			var d := Vector2(fwd.x, fwd.z).normalized()
			var tip := center + d * 12
			draw_colored_polygon(PackedVector2Array([tip, center + d.rotated(2.5) * 7, center + d.rotated(-2.5) * 7]), Color.WHITE)
		var font := get_theme_default_font()
		for mk in Game.markers.on_planet(Game.planet):
			var p := _screen(mk["x"], mk["z"])
			if p.x < 0 or p.y < 0 or p.x > size.x or p.y > size.y:
				continue
			var c := Markers.color_of(mk)
			if mk["kind"] == "teleporter":
				draw_circle(p, 7.0, Color(0, 0, 0, 0.6))
				draw_arc(p, 6.0, 0.0, TAU, 16, Color(0.45, 0.9, 1.0), 2.0)
			else:
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(6, 0), p + Vector2(0, 8), p + Vector2(-6, 0)]), c)
			draw_string(font, p + Vector2(9, 5), mk["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
		draw_string(get_theme_default_font(), Vector2(10, size.y - 10), "Scroll to zoom   ·   click to mark   ·   right-click a marker to remove   ·   1 square = 64 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
