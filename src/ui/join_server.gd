class_name JoinServerMenu
extends PanelContainer
## Title screen: the server browser. Servers on your local network turn up by themselves;
## your favourites and the servers you joined before are listed too, each with its name,
## description, players, ping and whether it needs a password, asked fresh each time
## the screen opens (Refresh asks again). Pick one, or type an address, and join.

signal closed

const SAVED := "user://servers.cfg"
const KEEP := 8

var _name: LineEdit
var _addr: LineEdit
var _pass: LineEdit
var _status: Label
var _go: Button
var _list: VBoxContainer
var _busy := false
var _query: ServerQuery
## "host:port" -> {address, name, info (the server's answer, or {}), lan, fav, recent}
var _rows: Dictionary = {}

func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(720, 0)
	add_child(v)
	v.add_child(UITheme.title("Join Server"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var c1 := VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(c1)
	c1.add_child(UITheme.label("Your name", 15, UITheme.DIM))
	_name = LineEdit.new()
	_name.max_length = 20
	_name.placeholder_text = "2 to 20 letters"
	_name.text = Identity.load_or_make()["name"]
	c1.add_child(_name)
	var c2 := VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(c2)
	c2.add_child(UITheme.label("Password (if the server has one)", 15, UITheme.DIM))
	_pass = LineEdit.new()
	_pass.secret = true
	c2.add_child(_pass)
	v.add_child(UITheme.label("Server address (name or IP, optionally :port)", 15, UITheme.DIM))
	var ah := HBoxContainer.new()
	v.add_child(ah)
	_addr = LineEdit.new()
	_addr.placeholder_text = "127.0.0.1:%d" % Net.DEFAULT_PORT
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(_addr)
	ah.add_child(UITheme.button("☆ Favourite", _favourite_typed))
	var head := HBoxContainer.new()
	head.add_child(UITheme.label("Servers", 15, UITheme.DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.button("Refresh", _refresh))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = UITheme.label("", 15, UITheme.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var h := HBoxContainer.new()
	h.add_child(UITheme.button("Back", func():
		Net.leave("")
		closed.emit()))
	_go = UITheme.button("Join", _join)
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_go)
	v.add_child(h)
	_addr.text_submitted.connect(func(_t): _join())
	_pass.text_submitted.connect(func(_t): _join())
	Net.join_failed.connect(_on_failed)
	Net.joined.connect(_on_joined)
	_query = ServerQuery.new()
	add_child(_query)
	_query.answered.connect(_on_answer)
	var recent := saved("recent")
	if not recent.is_empty():
		_addr.text = recent[0]["address"]
	_refresh()

## "host", "host:port" or "[v6]:port" -> [host, port].
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	var port := Net.DEFAULT_PORT
	if t.begins_with("["):
		var e := t.find("]")
		if e > 0:
			var rest := t.substr(e + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				port = rest.substr(1).to_int()
			return [t.substr(1, e - 1), port]
	var c := t.rfind(":")
	if c > 0 and t.count(":") == 1 and t.substr(c + 1).is_valid_int():
		port = t.substr(c + 1).to_int()
		t = t.substr(0, c)
	return [t, port]

static func _key(address: String) -> String:
	var a := parse_address(address)
	return "%s:%d" % [a[0], a[1]]

# --- The list -------------------------------------------------------------------------

## Asks every saved server and the local network again.
func _refresh() -> void:
	for k in _rows.keys():
		if _rows[k]["lan"] and not _rows[k]["fav"] and not _rows[k]["recent"]:
			_rows.erase(k)
	var favs := saved("favourites")
	var rec := saved("recent")
	for r in favs + rec:
		var k := _key(r["address"])
		if not _rows.has(k):
			_rows[k] = {"address": k, "name": String(r.get("name", "Server")), "info": {}, "lan": false, "fav": false, "recent": false}
		_rows[k]["info"] = {}
	for k in _rows:
		_rows[k]["fav"] = favs.any(func(r): return _key(r["address"]) == k)
		_rows[k]["recent"] = rec.any(func(r): return _key(r["address"]) == k)
	for k in _rows:
		var a := parse_address(k)
		_query.ask(a[0], a[1])
	_query.scan()
	_draw()

func _on_answer(key: String, info: Dictionary) -> void:
	if key.begins_with("lan:"):
		key = "%s:%d" % [info["host"], int(info["port"])]
		if not _rows.has(key):
			_rows[key] = {"address": key, "name": String(info.get("name", "Server")), "info": {}, "lan": true, "fav": false, "recent": false}
		_rows[key]["lan"] = true
	if not _rows.has(key):
		return
	_rows[key]["info"] = info
	if info.has("name"):
		_rows[key]["name"] = String(info["name"])
	_draw()

func _draw() -> void:
	for c in _list.get_children():
		c.queue_free()
	var groups := [["On your network", func(r): return r["lan"]],
		["Favourites", func(r): return r["fav"] and not r["lan"]],
		["Recent", func(r): return r["recent"] and not r["fav"] and not r["lan"]]]
	var any := false
	for g in groups:
		var rows: Array = _rows.values().filter(g[1])
		if rows.is_empty():
			continue
		any = true
		_list.add_child(UITheme.heading(g[0]))
		for r in rows:
			_list.add_child(_row(r))
	if not any:
		_list.add_child(UITheme.label("No servers found on your network yet. Type an address above, or Refresh.", 15, UITheme.DIM))

func _row(r: Dictionary) -> Control:
	var info: Dictionary = r["info"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.sb(UITheme.SLOT_BG, Color(1, 1, 1, 0.08), 6, 1, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var star := UITheme.button("★" if r["fav"] else "☆", func(): _toggle_favourite(r))
	star.tooltip_text = "Remove from favourites" if r["fav"] else "Add to favourites"
	h.add_child(star)
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	t.add_child(UITheme.label(String(r["name"]), 18, UITheme.ACCENT if r["lan"] else UITheme.TEXT))
	var sub := String(info.get("description", "")) if not info.has("error") else String(info["error"])
	var d := UITheme.label("%s%s" % [sub if sub != "" else "Asking...", "" if info.is_empty() else "   ·   " + String(r["address"])], 13, UITheme.BAD if info.has("error") else UITheme.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_child(d)
	if info.has("players"):
		h.add_child(UITheme.label("%d/%d" % [int(info["players"]), int(info.get("max_players", 0))], 15))
		h.add_child(UITheme.label("%d ms" % int(info.get("ping", 0)), 15, UITheme.DIM))
		if bool(info.get("password", false)):
			h.add_child(UITheme.label("Password", 13, UITheme.ACCENT))
		if int(info.get("protocol", ServerConfig.PROTOCOL)) != ServerConfig.PROTOCOL:
			h.add_child(UITheme.label("v%s" % info.get("version", "?"), 13, UITheme.BAD))
	h.add_child(UITheme.button("Join", func():
		_addr.text = r["address"]
		_join()))
	return p

# --- Favourites and recent servers ------------------------------------------------------

## A saved list ("favourites" or "recent") of {address, name}.
static func saved(which: String) -> Array:
	var cf := ConfigFile.new()
	if cf.load(SAVED) != OK:
		return []
	var out: Array = cf.get_value("servers", which, [])
	return out.filter(func(r): return r is Dictionary and r.has("address"))

static func _save(which: String, list: Array) -> void:
	var cf := ConfigFile.new()
	cf.load(SAVED)
	cf.set_value("servers", which, list)
	cf.save(SAVED)

static func remember(address: String, server_name: String) -> void:
	var k := _key(address)
	var list := saved("recent").filter(func(r): return _key(r["address"]) != k)
	list.push_front({"address": k, "name": server_name})
	_save("recent", list.slice(0, KEEP))

static func set_favourite(address: String, server_name: String, on: bool) -> void:
	var k := _key(address)
	var list := saved("favourites").filter(func(r): return _key(r["address"]) != k)
	if on:
		list.append({"address": k, "name": server_name})
	_save("favourites", list)

func _toggle_favourite(r: Dictionary) -> void:
	r["fav"] = not r["fav"]
	set_favourite(r["address"], r["name"], r["fav"])
	_draw()

func _favourite_typed() -> void:
	if _addr.text.strip_edges() == "":
		_status.text = "Type the server's address first."
		return
	var k := _key(_addr.text)
	set_favourite(k, String(_rows.get(k, {}).get("name", k)), true)
	_refresh()

# --- Joining ----------------------------------------------------------------------------

func _join() -> void:
	if _busy:
		return
	var nm := Identity.clean_name(_name.text)
	if nm.length() < 2:
		_status.text = "Pick a name of at least 2 letters."
		return
	var a := parse_address(_addr.text if _addr.text.strip_edges() != "" else _addr.placeholder_text)
	if String(a[0]) == "":
		_status.text = "Type the server's address."
		return
	var k := "%s:%d" % [a[0], a[1]]
	var info: Dictionary = _rows.get(k, {}).get("info", {})
	if bool(info.get("password", false)) and _pass.text == "":
		_status.text = "%s needs a password. Type it above, then Join." % info.get("name", "This server")
		_pass.grab_focus()
		return
	_busy = true
	_go.disabled = true
	_status.text = "Connecting to %s..." % k
	_pending = k
	Net.join(a[0], a[1], nm, _pass.text)

var _pending := ""

func _on_failed(reason: String) -> void:
	_busy = false
	_go.disabled = false
	_status.text = reason
	if reason.to_lower().contains("password"):
		_pass.grab_focus()

func _on_joined() -> void:
	remember(_pending, String(Net.info.get("name", "Server")))
	_status.text = "Joined %s. Loading the world..." % Net.info.get("name", "the server")
	get_tree().change_scene_to_file("res://src/world/world.tscn")
