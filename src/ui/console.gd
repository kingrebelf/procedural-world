class_name DevConsole
extends Control
## Cheat console, opened with ` (rebindable). Cheats last for this session only.

const HELP := """Commands:
  fly            toggle flying (Space up, Ctrl down, Shift fast)
  noclip         toggle flying through everything
  god            toggle no damage
  speed <x>      movement speed multiplier (1 = normal)
  heal           full health and stamina
  xp <n>         gain experience
  level <n>      jump to a level (points included)
  give <item> [n] [rank]  e.g. give iron_ingot 20, give sword_iron 1 5 (rank 0 Common .. 5 Mythic)
  money <n>      add Marks
  time <hour>    set the time of day (0-24)
  tp <x> <z>     teleport
  weather [kind] show the weather, or force one: clear, fair, cloudy, overcast, mist, drizzle,
                 rain, storm, snow, blizzard, dust, starfall; auto follows the climate again; strike = lightning;
                 fall = a star comes down in front of you
  fire           set what you look at alight (fire rain <0-1|auto>, fire out, fire count)
  items          list item ids
  bench          performance test: what each graphics feature costs on this PC
  server <cmd>   on a server: run a server command (admins)
  clear          clear this log"""

const SERVER_CHEATS := ["fly", "noclip", "god", "speed", "heal", "give", "xp", "level", "money", "time", "tp", "fire"]

var player: Player
var _log: RichTextLabel
var _input: LineEdit
var _history: Array = []
var _hist_i := 0

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(Color(0.03, 0.035, 0.04, 0.88), Color(1, 1, 1, 0.08), 0, 1, 10))
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = 340
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "Type a command (help)"
	_input.text_submitted.connect(_submit)
	_input.gui_input.connect(_on_key)
	v.add_child(_input)
	visible = false
	_print("[color=#9ab]Console ready. Type help.[/color]")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("console"):
		toggle()
		get_viewport().set_input_as_handled()

func _on_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if e.is_action("console"):
		toggle()
		get_viewport().set_input_as_handled()
	elif e.keycode == KEY_UP and not _history.is_empty():
		_hist_i = maxi(0, _hist_i - 1)
		_input.text = _history[_hist_i]
		_input.caret_column = _input.text.length()
	elif e.keycode == KEY_DOWN and not _history.is_empty():
		_hist_i = mini(_history.size(), _hist_i + 1)
		_input.text = _history[_hist_i] if _hist_i < _history.size() else ""
	elif e.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	if player:
		player.ui_open = visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_input.clear()
		_input.grab_focus.call_deferred()
	else:
		_input.release_focus()
		Cursor.restore()

func _print(t: String) -> void:
	_log.append_text(t + "\n")

func _submit(text: String) -> void:
	text = text.strip_edges().replace("`", "")
	_input.clear()
	if text == "":
		return
	_history.append(text)
	_hist_i = _history.size()
	_print("[color=#e8c26a]> %s[/color]" % text)
	_print(run(text))

## Runs one command and returns what to print. Public so tests can drive it.
func run(text: String) -> String:
	var a := text.split(" ", false)
	var cmd := a[0].to_lower()
	if Net.is_client():
		# On a server, cheats are for its admins (signed in with /admin <password> in chat).
		if cmd in SERVER_CHEATS and not Net.is_admin:
			return "Cheats are off on servers. Admins: type /admin <password> in chat first."
		if cmd == "server":
			Net.admin(text.substr(a[0].length()).strip_edges())
			return "Sent to the server (replies show in chat)"
	match cmd:
		"help", "?":
			return HELP
		"clear":
			_log.clear()
			return ""
		"fire":
			return _fire_cmd(a)
		"fly":
			player.fly = not player.fly
			if not player.fly:
				player.noclip = false
				player._shape.disabled = false
			return "Fly %s" % _on(player.fly)
		"noclip":
			player.noclip = not player.noclip
			player.fly = player.fly or player.noclip
			player._shape.disabled = player.noclip
			return "Noclip %s" % _on(player.noclip)
		"god":
			Game.cheats["god"] = not Game.cheats["god"]
			if Game.cheats["god"]:
				Game.set_health(Game.max_health())
			return "God mode %s" % _on(Game.cheats["god"])
		"speed":
			if a.size() < 2 or not a[1].is_valid_float():
				return "Usage: speed <multiplier>   (now %.1f)" % player.speed_mult
			player.speed_mult = clampf(a[1].to_float(), 0.1, 20.0)
			return "Speed x%.1f" % player.speed_mult
		"bench":
			if get_tree().current_scene.has_node("Benchmark"):
				return "A performance test is already running"
			var b := Benchmark.new()
			b.name = "Benchmark"
			b.world = get_tree().current_scene
			get_tree().current_scene.add_child(b)
			toggle()
			return "Performance test started: stand still for about a minute"
		"heal":
			Game.set_health(Game.max_health())
			Game.set_stamina(Game.max_stamina())
			return "Healed"
		"give":
			if a.size() < 2 or not ItemDB.has(a[1]):
				return "Unknown item. Type items for the list."
			var n := a[2].to_int() if a.size() > 2 else 1
			var ck := ChunkStreamer.chunk_of(player.global_position)
			var made := 0
			# give <item> [count] [rank 0-5]: gear of a chosen rank, with random abilities.
			var rank := a[3].to_int() if a.size() > 3 else -1
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			for i in (1 if ItemDB.is_stackable(a[1]) else clampi(n, 1, 40)):
				var it := ItemDB.make(a[1], n if ItemDB.is_stackable(a[1]) else 1, 1.0, Game.origin_here("conjured", -1, ck))
				if rank >= 0:
					Rarity.apply(it, clampi(rank, 0, Rarity.MYTHIC), rng)
				if Game.give(it):
					made += n if ItemDB.is_stackable(a[1]) else 1
			return "Gave %d %s" % [made, ItemDB.def(a[1])["name"]]
		"xp":
			Game.add_xp(a[1].to_float() if a.size() > 1 else 100.0, "Console")
			return "Level %d, %d/%d XP" % [Game.stats.level, Game.stats.xp, Stats.xp_to_next(Game.stats.level)]
		"level":
			var target := clampi(a[1].to_int() if a.size() > 1 else Game.stats.level + 1, 1, Stats.MAX_LEVEL)
			while Game.stats.level < target:
				Game.add_xp(ceilf((Stats.xp_to_next(Game.stats.level) - Game.stats.xp) / Game.stats.xp_mult()) + 1.0, "Console")
			return "Level %d, %d points to spend (K)" % [Game.stats.level, Game.stats.points]
		"money":
			Game.add_money(a[1].to_int() if a.size() > 1 else 1000)
			return "%d Marks" % Game.money
		"time":
			if a.size() < 2 or not a[1].is_valid_float():
				return "Usage: time <hour 0-24>"
			Game.day = floorf(Game.day) + clampf(a[1].to_float(), 0.0, 23.99) / 24.0
			return "Time set"
		"weather":
			var wx := Weather.current
			if wx == null:
				return "No weather here"
			if a.size() > 1 and a[1] == "strike":
				wx.strike_now = true
				return "Lightning"
			if a.size() > 1 and a[1] == "fall":
				wx.starfall.land_now = true
				return "A star falls"
			if a.size() > 1 and not wx.force(a[1]):
				return "Unknown weather. Try: " + ", ".join(Weather.KEYS) + ", starfall, auto"
			return "%s, %d°C, wind %d%%, ground wet %d%%, snow %d%%%s" % [wx.describe(), roundi(wx.temp), roundi(wx.wind * 100.0),
				roundi(wx.wet * 100.0), roundi(wx.snow_cover * 100.0), " (forced)" if wx.forced >= 0 else ""]
		"tp":
			if a.size() < 3:
				return "Usage: tp <x> <z>"
			var x := a[1].to_float()
			var z := a[2].to_float()
			player.global_position = Vector3(x, 200.0, z)
			player.velocity = Vector3.ZERO
			player.frozen = true
			player.snap_down = not player.fly
			return "Teleported to %d, %d" % [x, z]
		"items":
			var ids: Array = ItemDB.ITEMS.keys() + BuildCatalog.PIECES.keys()
			return ", ".join(ids)
	return "Unknown command. Type help."

static func _on(b: bool) -> String:
	return "on" if b else "off"

## `fire`: sets what you look at alight; `fire rain <0-1|auto>` burns in that rain;
## `fire out` douses every fire; `fire count` says how many are burning.
func _fire_cmd(a: PackedStringArray) -> String:
	var fs := FireSystem.current
	if fs == null:
		return "No fires in this world"
	var sub := a[1].to_lower() if a.size() > 1 else ""
	match sub:
		"rain":
			if a.size() < 3 or (a[2] != "auto" and not a[2].is_valid_float()):
				return "Usage: fire rain <0-1|auto>"
			fs.rain_override = -1.0 if a[2] == "auto" else clampf(a[2].to_float(), 0.0, 1.0)
			return "Fires burn in %s" % ("the sky's rain" if fs.rain_override < 0.0 else "rain %.2f" % fs.rain_override)
		"out":
			var n := fs.burning_count()
			fs.douse_all()
			return "Put out %d fires" % n
		"count":
			return "%d burning" % fs.burning_count()
	var h: Dictionary = player._hit_object()
	if not h.has("obj"):
		return "Look at something to set alight"
	var node: ChunkNode = h["chunk"]
	if fs.ignite(node, int(h["obj"]), 1.0, false, true, 20.0):
		return "Set the %s alight" % ObjectLibrary.label_of(node.get_object(h["obj"])).to_lower()
	return "The %s will not burn" % ObjectLibrary.label_of(node.get_object(h["obj"])).to_lower()
