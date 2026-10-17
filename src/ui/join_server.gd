class_name JoinServerMenu
extends PanelContainer
## Title screen: join a dedicated server by address, with your name and the server's
## password; servers you joined before are listed to join again in one click.

signal closed

const RECENT := "user://servers.cfg"
const KEEP := 8

var _name: LineEdit
var _addr: LineEdit
var _pass: LineEdit
var _status: Label
var _go: Button
var _busy := false

func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	add_child(v)
	v.add_child(UITheme.title("Join Server"))
	v.add_child(UITheme.label("Your name", 15, UITheme.DIM))
	_name = LineEdit.new()
	_name.max_length = 20
	_name.placeholder_text = "2 to 20 letters"
	_name.text = Identity.load_or_make()["name"]
	v.add_child(_name)
	v.add_child(UITheme.label("Server address (name or IP, optionally :port)", 15, UITheme.DIM))
	_addr = LineEdit.new()
	_addr.placeholder_text = "127.0.0.1:%d" % Net.DEFAULT_PORT
	v.add_child(_addr)
	v.add_child(UITheme.label("Password (if the server has one)", 15, UITheme.DIM))
	_pass = LineEdit.new()
	_pass.secret = true
	v.add_child(_pass)
	var recent := _recent()
	if not recent.is_empty():
		_addr.text = recent[0]["address"]
		v.add_child(UITheme.label("Recent servers", 15, UITheme.DIM))
		for r in recent:
			var b := UITheme.button("%s  ·  %s" % [r.get("name", "Server"), r["address"]], func():
				_addr.text = r["address"]
				_join())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(b)
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
	_busy = true
	_go.disabled = true
	_status.text = "Connecting to %s:%d..." % [a[0], a[1]]
	_pending = "%s:%d" % [a[0], a[1]]
	Net.join(a[0], a[1], nm, _pass.text)

var _pending := ""

func _on_failed(reason: String) -> void:
	_busy = false
	_go.disabled = false
	_status.text = reason

func _on_joined() -> void:
	_remember(_pending, String(Net.info.get("name", "Server")))
	_status.text = "Joined %s. Loading the world..." % Net.info.get("name", "the server")
	get_tree().change_scene_to_file("res://src/world/world.tscn")

static func _recent() -> Array:
	var cf := ConfigFile.new()
	if cf.load(RECENT) != OK:
		return []
	var out: Array = cf.get_value("servers", "recent", [])
	return out.filter(func(r): return r is Dictionary and r.has("address"))

static func _remember(address: String, server_name: String) -> void:
	var list := _recent().filter(func(r): return r["address"] != address)
	list.push_front({"address": address, "name": server_name})
	var cf := ConfigFile.new()
	cf.set_value("servers", "recent", list.slice(0, KEEP))
	cf.save(RECENT)
