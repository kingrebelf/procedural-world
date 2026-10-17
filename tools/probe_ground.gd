extends SceneTree
## Top-down maps of what lies on the ground, no GPU needed: for a few spots of a human
## world (a meadow, dunes, snowy ground, a town green, or X/Z given) it generates 3x3
## chunks and draws the ground cover, grass, undergrowth (by form), loose stones, trees,
## boulders and markers, plus a count per kind. Before/after checks for placement work.
##   godot --headless --path . --script res://tools/probe_ground.gd -- [--seed=4242]
##     [--at=x,z] [--out=user://ground] [--spots=meadow,dunes,snow,town,craters,terraces]
## Writes <out>/<spot>.png and prints the counts. (The work is in ground_map.gd: the
## world's scripts need the Game autoload, which exists only once the tree runs.)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	load("res://tools/ground_map.gd").run()
	quit()
