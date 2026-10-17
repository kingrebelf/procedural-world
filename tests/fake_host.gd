extends Node
## Stands in for ServerHost in tests/run_tests.gd: ServerSync reads `online` and tells
## players who holds what through tell_hold.

var online: Dictionary = {}
var told: Array = []

func tell_hold(q: int, kind: String, p: int, k: Vector2i, holder: int, count: int) -> void:
	told.append([q, kind, p, k, holder, count])
