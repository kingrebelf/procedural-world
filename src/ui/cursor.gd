class_name Cursor
## Mouse lock. Locked: the mouse steers your view and your hands. Free: the pointer shows
## so you can click on things, while you can still walk. The "mouse_toggle" key flips it;
## menus always free the pointer and put it back the way you had it when they close.

static var free := false

## Puts the pointer back the way the player chose (after a menu or dialogue closes).
static func restore() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED

static func toggle() -> void:
	free = not free
	restore()

## True while the mouse is steering the view.
static func locked() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
