extends Control
## Title screen: continue, new world (name + seed), load or delete worlds, settings, quit.

var _content: Control
var _bg_t := 0.0

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_home()

func _draw() -> void:
	# Animated three-era gradient backdrop.
	var s := size
	var cols := [Color(0.14, 0.2, 0.09), Color(0.05, 0.17, 0.2), Color(0.06, 0.08, 0.15)]
	var n := 48
	for i in n:
		var t := float(i) / n
		var k := fposmod(t + _bg_t * 0.02, 1.0) * 3.0
		var a: Color = cols[int(k) % 3]
		var b: Color = cols[(int(k) + 1) % 3]
		draw_rect(Rect2(s.x * t, 0, s.x / n + 1, s.y), a.lerp(b, k - floor(k)))
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.35))

func _process(d: float) -> void:
	_bg_t += d
	queue_redraw()

func _swap(c: Control) -> void:
	if _content:
		_content.queue_free()
	_content = c
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

func _home() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(440, 0)
	var t := UITheme.title("PROCEDURAL WORLD", 54)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UITheme.label("Once it exists, it exists.", 18, UITheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	var worlds := WorldStore.list_worlds()
	if not worlds.is_empty():
		var w: Dictionary = worlds[0]
		v.add_child(UITheme.button("Continue: %s" % w.get("name", "World"), func(): _play(w["id"])))
	v.add_child(UITheme.button("New World", _new_world))
	if worlds.size() > 0:
		v.add_child(UITheme.button("Load World", _load_world))
	v.add_child(UITheme.button("Settings", func():
		var m := SettingsMenu.new()
		m.closed.connect(_home)
		_swap(m)))
	v.add_child(UITheme.button("Quit", func(): get_tree().quit()))
	var ver := UITheme.label("v%s  ·  MIT licensed  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]], 13, UITheme.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	_swap(v)

func _new_world() -> void:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(480, 0)
	p.add_child(v)
	v.add_child(UITheme.title("New World"))
	v.add_child(UITheme.label("Name", 15, UITheme.DIM))
	var name_e := LineEdit.new()
	name_e.text = "My World"
	v.add_child(name_e)
	v.add_child(UITheme.label("Seed (blank for random; words work too)", 15, UITheme.DIM))
	var seed_e := LineEdit.new()
	seed_e.placeholder_text = "random"
	v.add_child(seed_e)
	var h := HBoxContainer.new()
	h.add_child(UITheme.button("Back", _home))
	var go := UITheme.button("Create and enter", func():
		Game.new_world(name_e.text, seed_e.text)
		get_tree().change_scene_to_file("res://src/world/world.tscn"))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(go)
	v.add_child(h)
	_swap(p)

func _load_world() -> void:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UITheme.title("Worlds"))
	for w in WorldStore.list_worlds():
		var h := HBoxContainer.new()
		var pt := int(w.get("play_time", 0.0))
		var l := UITheme.label("%s\nseed %d  ·  %dh %02dm played" % [w.get("name", "World"), w.get("seed", 0), pt / 3600, (pt / 60) % 60], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var id: String = w["id"]
		h.add_child(UITheme.button("Play", func(): _play(id)))
		var del := UITheme.button("Delete", func(): _confirm_delete(id, w.get("name", "World")))
		h.add_child(del)
		v.add_child(h)
	v.add_child(UITheme.button("Back", _home))
	_swap(p)

func _confirm_delete(id: String, name: String) -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = "Delete \"%s\" forever? Everything in it will be gone." % name
	d.ok_button_text = "Delete"
	d.confirmed.connect(func():
		WorldStore.delete_world(id)
		_load_world())
	add_child(d)
	d.popup_centered()

func _play(id: String) -> void:
	if Game.load_world(id):
		get_tree().change_scene_to_file("res://src/world/world.tscn")
