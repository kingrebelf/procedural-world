class_name LockpickUI
extends Control
## The lockpicking minigame on screen: the lock face, your pick and the tension wrench.
## Move the mouse (or A/D, or the left stick) to set the pick, hold W, Space, the left
## mouse button or A on a pad to turn the lock. Esc leaves. Each snapped pick is used up
## and makes noise someone nearby may hear.

var player: Player
var _game: LockGame
var _chunk: ChunkNode
var _obj: Dictionary
var _at: Vector3
var _status: Label
var _shake := 0.0
var _flash := 0.0 ## red flash when a pick snaps
var _done := false
var _on_open := Callable() ## a lock that isn't a chunk object's (open_custom)

const PICK_ITEM := "lockpick"
const KEY_SPEED := 1.6 ## radians a second with A/D or the stick

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("lockpick_ui")
	_status = UITheme.label("", 17)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_left = -420
	_status.offset_right = 420
	_status.offset_top = -170
	_status.offset_bottom = -90
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_constant_override("outline_size", 5)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_status)

func is_open() -> bool:
	return visible

## Starts picking the lock on a town chest or someone's door. Needs a lockpick.
func open_lock(chunk: ChunkNode, o: Dictionary, at: Vector3) -> void:
	if visible or player == null:
		return
	if Game.inventory.count(PICK_ITEM) <= 0:
		Game.toast.emit("Locked. You need a lockpick (craft them from iron, or buy them from a smith)")
		return
	_chunk = chunk
	_obj = o
	_at = at
	var tier := Player.lock_of(o)
	_game = LockGame.new(tier, int(Game.stats.skills["lock"]) + int(Game.stats._b("lock") * 100.0), absi(hash(str(o["p"]) + "sweet")))
	_done = false
	visible = true
	player.ui_open = true
	player.keep_crouch = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_text()

## Starts picking some other lock (a town's postern): `on_open` runs once it gives.
func open_custom(tier: int, seed_: int, at: Vector3, on_open: Callable) -> void:
	if visible or player == null:
		return
	if Game.inventory.count(PICK_ITEM) <= 0:
		Game.toast.emit("Locked. You need a lockpick (craft them from iron, or buy them from a smith)")
		return
	_chunk = null
	_obj = {}
	_at = at
	_on_open = on_open
	_game = LockGame.new(tier, int(Game.stats.skills["lock"]) + int(Game.stats._b("lock") * 100.0), seed_)
	_done = false
	visible = true
	player.ui_open = true
	player.keep_crouch = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_text()

func close_lock() -> void:
	if not visible:
		return
	visible = false
	_game = null
	_on_open = Callable()
	if player:
		player.ui_open = false
		player.keep_crouch = false
	Cursor.restore()

func _turning() -> bool:
	return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_A) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close_lock()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _game:
		_game.set_pick(_game.pick + event.relative.x * 0.005)
	# Everything else stays here while picking.
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible or _game == null:
		return
	# The chest gone, or you walked off: stop.
	if (not _on_open.is_valid() and not is_instance_valid(_chunk)) or player.global_position.distance_to(_at) > 4.0:
		close_lock()
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	var ax := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(ax) > 0.2:
		dir += ax
	if dir != 0.0:
		_game.set_pick(_game.pick + dir * KEY_SPEED * delta)
	var r := _game.step(delta, _turning())
	_shake = _game.strain
	_flash = maxf(0.0, _flash - delta * 2.0)
	match r:
		"open":
			_opened()
			return
		"broke":
			_broke()
	queue_redraw()

func _opened() -> void:
	if _on_open.is_valid():
		var cb := _on_open
		Game.practice("lock", 4.0 + 4.0 * _game.tier)
		Game.add_xp(3.0 * _game.tier, "Lockpicking")
		Game.toast.emit("The lock clicks open")
		close_lock()
		cb.call()
		return
	var door := Doors.is_door(_obj["t"])
	if not door:
		_obj["st"]["lock"] = 0
		Game.mark_chunk_dirty(_chunk.data)
	Game.practice("lock", 4.0 + 4.0 * _game.tier)
	Game.add_xp(3.0 * _game.tier, "Lockpicking")
	Game.toast.emit("The lock clicks open")
	var c := _chunk
	var o := _obj
	close_lock()
	# Straight on to what's inside (or through the door), as if you'd opened it.
	if door:
		player.use_door_after_lock(c, o)
	else:
		player.use_cache_after_lock(c, o)

func _broke() -> void:
	_flash = 1.0
	Game.inventory.remove_type(PICK_ITEM, 1)
	Game.practice("lock", 1.0 + _game.tier)
	if player.npcs:
		player.npcs.report_crime(_at, "lockpick", 0, "")
	var left := Game.inventory.count(PICK_ITEM)
	Game.toast.emit("Your lockpick snapped%s" % ("" if left > 0 else ". That was your last one"))
	if left <= 0:
		close_lock()
		return
	_update_text()

func _update_text() -> void:
	var keys := "Move the mouse or A/D to set the pick, hold W, Space or the left button to turn the lock. Esc to stop."
	_status.text = "%s lock   ·   Lockpicks: %d   ·   Lockpicking %d\n%s" % [LockGame.TIERS[_game.tier], Game.inventory.count(PICK_ITEM), int(Game.stats.skills["lock"]), keys]

func _draw() -> void:
	if _game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.72))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.1, 0.05, 0.25 * _flash))
	var c := size * 0.5 + Vector2(0, -30)
	if _shake > 0.0:
		c += Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
	var R := minf(size.x, size.y) * 0.24
	# The lock's plate and its turning core.
	draw_circle(c, R * 1.18, Color(0.16, 0.13, 0.1))
	draw_circle(c, R * 1.1, Color(0.55, 0.42, 0.22))
	draw_arc(c, R * 1.1, 0, TAU, 64, Color(0.3, 0.22, 0.12), 4.0, true)
	for i in 8:
		var a := i * TAU / 8.0
		draw_circle(c + Vector2(cos(a), sin(a)) * R * 0.98, R * 0.04, Color(0.32, 0.24, 0.13))
	var rot := _game.turn * PI * 0.5
	draw_circle(c, R * 0.72, Color(0.68, 0.53, 0.28))
	draw_arc(c, R * 0.72, 0, TAU, 64, Color(0.36, 0.27, 0.14), 3.0, true)
	# The keyway, turning with the core.
	var kd := Vector2(0, 1).rotated(rot)
	var kp := kd.orthogonal()
	var key := PackedVector2Array([c - kd * R * 0.12 - kp * R * 0.06, c - kd * R * 0.12 + kp * R * 0.06,
		c + kd * R * 0.42 + kp * R * 0.03, c + kd * R * 0.42 - kp * R * 0.03])
	draw_colored_polygon(key, Color(0.06, 0.05, 0.04))
	draw_circle(c - kd * R * 0.14, R * 0.11, Color(0.06, 0.05, 0.04))
	# The tension wrench, turning with the lock.
	var w0 := c + kd * R * 0.3
	var w1 := w0 + Vector2(1, 0.35).rotated(rot).normalized() * R * 0.9
	draw_line(w0, w1, Color(0.35, 0.36, 0.38), R * 0.06, true)
	draw_line(w1, w1 + Vector2(0, 1).rotated(rot) * R * 0.25, Color(0.35, 0.36, 0.38), R * 0.06, true)
	# The pick, from the keyway up, at its angle.
	var pd := Vector2(sin(_game.pick), -cos(_game.pick))
	var tip := c - kd * R * 0.1 + pd * R * 0.15
	var tail := tip + pd * R * 1.5
	var steel := Color(0.78, 0.8, 0.84).lerp(Color(1.0, 0.5, 0.4), (1.0 - _game.pick_hp) * 0.8)
	draw_line(tip, tail, steel, R * 0.035, true)
	draw_line(tail, tail + pd * R * 0.35, Color(0.3, 0.2, 0.12), R * 0.09, true)
	draw_line(tip, tip - pd.orthogonal() * R * 0.07 + pd * R * 0.03, steel, R * 0.03, true)
	# The pick's wear.
	var bw := R * 1.2
	var bp := c + Vector2(-bw * 0.5, R * 1.4)
	draw_rect(Rect2(bp, Vector2(bw, 6)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bp, Vector2(bw * _game.pick_hp, 6)), Color(0.85, 0.82, 0.75))
