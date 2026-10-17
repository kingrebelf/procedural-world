extends SceneTree
## Fails (exit 1) if any script given after -- does not parse, e.g. the capture tour,
## which the tests never load:
##   godot --headless --path . --script res://tools/parse_check.gd -- res://tools/capture.gd ...
func _initialize() -> void:
	var bad := 0
	for p in OS.get_cmdline_user_args():
		var s := load(p) as GDScript
		if s == null or not s.can_instantiate():
			print("PARSE FAIL ", p)
			bad += 1
	print("parse check: %d failed" % bad)
	quit(1 if bad > 0 else 0)
