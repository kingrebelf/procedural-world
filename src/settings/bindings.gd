class_name Bindings
## Input actions with keyboard/mouse and controller defaults, player rebinding, and
## persistence in user://input.cfg. Godot maps Xbox, PlayStation, Switch and generic
## controllers to the same SDL layout, so one set of controller bindings covers them all.

const PATH := "user://input.cfg"
const DEADZONE := 0.2

## action -> [label, keyboard/mouse default, controller default]
## The controller layout follows ARK: A jump, B inventory, Y use, left/right stick clicks
## sprint and crouch, RT use the held item, D-pad left/right cycle the hotbar, and holding
## LB turns A/B/X/Y and the D-pad into direct hotbar picks.
## Keyboard default: KEY_* int, or "mouse:<button>". Controller default: "btn:<JoyButton>"
## or "axis:<JoyAxis>:<+1|-1>".
const ACTIONS := {
	"move_forward": ["Move forward", KEY_W, "axis:1:-1"],
	"move_back": ["Move back", KEY_S, "axis:1:1"],
	"move_left": ["Move left", KEY_A, "axis:0:-1"],
	"move_right": ["Move right", KEY_D, "axis:0:1"],
	"look_up": ["Look up", -1, "axis:3:-1"],
	"look_down": ["Look down", -1, "axis:3:1"],
	"look_left": ["Look left", -1, "axis:2:-1"],
	"look_right": ["Look right", -1, "axis:2:1"],
	"jump": ["Jump", KEY_SPACE, "btn:0"],
	"sprint": ["Sprint", KEY_SHIFT, "btn:7"],
	"crouch": ["Crouch / dive", KEY_CTRL, "btn:8"],
	"use": ["Use tool / weapon", "mouse:1", "axis:5:1"],
	"interact": ["Interact / talk / trade", KEY_E, "btn:3"],
	"eat": ["Eat", KEY_F, "btn:2"],
	"inventory": ["Inventory", KEY_TAB, "btn:1"],
	"craft": ["Crafting", KEY_R, "btn:11"],
	"map": ["Atlas", KEY_M, "btn:4"],
	"character": ["Character and attributes", KEY_K, "btn:12"],
	"rotate_build": ["Rotate building piece", KEY_Q, "btn:10"],
	"hotbar_prev": ["Previous hotbar slot", -1, "btn:13"],
	"hotbar_next": ["Next hotbar slot", -1, "btn:14"],
	"hotbar_pick": ["Hold to pick a hotbar slot with A/B/X/Y and the D-pad", -1, "btn:9"],
	"pause": ["Pause", KEY_ESCAPE, "btn:6"],
	"slot_1": ["Hotbar 1", KEY_1, ""],
	"slot_2": ["Hotbar 2", KEY_2, ""],
	"slot_3": ["Hotbar 3", KEY_3, ""],
	"slot_4": ["Hotbar 4", KEY_4, ""],
	"slot_5": ["Hotbar 5", KEY_5, ""],
	"slot_6": ["Hotbar 6", KEY_6, ""],
	"slot_7": ["Hotbar 7", KEY_7, ""],
	"slot_8": ["Hotbar 8", KEY_8, ""],
	"slot_9": ["Hotbar 9", KEY_9, ""],
	"slot_10": ["Hotbar 10", KEY_0, ""],
	"debug_overlay": ["FPS counter", KEY_F3, ""],
	"console": ["Console (cheats)", KEY_QUOTELEFT, ""],
	"screenshot": ["Screenshot", KEY_F12, ""],
}

## Secondary keyboard keys that are always added (arrow keys, C for crouch, I for bag).
const EXTRA_KEYS := {"move_forward": KEY_UP, "move_back": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT,
	"crouch": KEY_C, "inventory": KEY_I}

static var custom: Dictionary = {} ## action -> {"kb": spec, "pad": spec}

static func load_and_apply() -> void:
	custom.clear()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for a in ACTIONS:
			if cf.has_section_key("kb", a) or cf.has_section_key("pad", a):
				custom[a] = {"kb": cf.get_value("kb", a, ACTIONS[a][1]), "pad": cf.get_value("pad", a, ACTIONS[a][2])}
	apply()

static func save() -> void:
	var cf := ConfigFile.new()
	for a in custom:
		cf.set_value("kb", a, custom[a]["kb"])
		cf.set_value("pad", a, custom[a]["pad"])
	cf.save(PATH)

static func spec(action: String, slot: String):
	if custom.has(action):
		return custom[action][slot]
	return ACTIONS[action][1 if slot == "kb" else 2]

static func apply() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, DEADZONE)
		InputMap.action_erase_events(a)
		var kb = spec(a, "kb")
		var ev := event_from_spec(kb)
		if ev:
			InputMap.action_add_event(a, ev)
		if EXTRA_KEYS.has(a) and not custom.has(a):
			var e := InputEventKey.new()
			e.physical_keycode = EXTRA_KEYS[a]
			InputMap.action_add_event(a, e)
		var pad = spec(a, "pad")
		ev = event_from_spec(pad)
		if ev:
			InputMap.action_add_event(a, ev)

static func event_from_spec(s) -> InputEvent:
	if s is int:
		if s < 0:
			return null
		var e := InputEventKey.new()
		e.physical_keycode = s
		return e
	var t := String(s)
	if t.begins_with("mouse:"):
		var m := InputEventMouseButton.new()
		m.button_index = t.get_slice(":", 1).to_int()
		return m
	if t.begins_with("btn:"):
		var b := InputEventJoypadButton.new()
		b.button_index = t.get_slice(":", 1).to_int()
		b.device = -1
		return b
	if t.begins_with("axis:"):
		var x := InputEventJoypadMotion.new()
		x.axis = t.get_slice(":", 1).to_int()
		x.axis_value = float(t.get_slice(":", 2).to_int())
		x.device = -1
		return x
	return null

## Turns a captured event into a spec, or null if it is not bindable in that slot.
static func spec_from_event(e: InputEvent, slot: String):
	if slot == "kb":
		if e is InputEventKey and e.pressed:
			return int(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
		if e is InputEventMouseButton and e.pressed:
			return "mouse:%d" % e.button_index
	else:
		if e is InputEventJoypadButton and e.pressed:
			return "btn:%d" % e.button_index
		if e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
			return "axis:%d:%d" % [e.axis, 1 if e.axis_value > 0 else -1]
	return null

static func rebind(action: String, slot: String, s) -> void:
	if not custom.has(action):
		custom[action] = {"kb": ACTIONS[action][1], "pad": ACTIONS[action][2]}
	custom[action][slot] = s
	apply()
	save()

static func reset() -> void:
	custom.clear()
	apply()
	save()

const PAD_NAMES := {0: "A / Cross", 1: "B / Circle", 2: "X / Square", 3: "Y / Triangle", 4: "View / Share", 6: "Menu / Options",
	7: "Left stick click", 8: "Right stick click", 9: "LB / L1", 10: "RB / R1", 11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}
const AXIS_NAMES := {0: "Left stick X", 1: "Left stick Y", 2: "Right stick X", 3: "Right stick Y", 4: "LT / L2", 5: "RT / R2"}

## The key (or button, when playing on a controller) for an action, for on-screen hints.
static func key_name(action: String, pad := false) -> String:
	return describe(spec(action, "pad" if pad else "kb"))

static func describe(s) -> String:
	if s is int:
		return "-" if s < 0 else OS.get_keycode_string(s)
	var t := String(s)
	if t == "":
		return "-"
	if t.begins_with("mouse:"):
		return ["", "Left mouse", "Right mouse", "Middle mouse", "Wheel up", "Wheel down"][clampi(t.get_slice(":", 1).to_int(), 0, 5)] if t.get_slice(":", 1).to_int() <= 5 else "Mouse %s" % t.get_slice(":", 1)
	if t.begins_with("btn:"):
		return PAD_NAMES.get(t.get_slice(":", 1).to_int(), "Button %s" % t.get_slice(":", 1))
	if t.begins_with("axis:"):
		var ax := t.get_slice(":", 1).to_int()
		var dir := t.get_slice(":", 2).to_int()
		var n: String = AXIS_NAMES.get(ax, "Axis %d" % ax)
		if ax >= 4:
			return n
		return "%s %s" % [n, "+" if dir > 0 else "-"]
	return t
