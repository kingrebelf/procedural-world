class_name Dungeons
extends Node
## Keeps the dungeons under nearby strongholds standing: the gatehouse once you're in
## sight of a fort, the levels below once you're close, and a small tracker on screen
## while you're down there (what you've seen, opened and looted, of how much).

const SHELL := 320.0 ## gatehouses this near are built
const DEEP := 110.0 ## levels built this near
const DROP := 380.0 ## freed beyond this

var streamer: ChunkStreamer
var player: Node3D

var _nodes := {} ## id -> DungeonNode
var _gen: ChunkGenerator ## our own: plans are made off the main thread
var _task := -1
var _want: Array = [] ## forts waiting for a plan
var _made: Array = [] ## plans made, waiting for a node
var _mx := Mutex.new()
var _tick := 0.0
var _panel: PanelContainer
var _title: Label
var _line: Label

func _ready() -> void:
	_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers() if Game.store else true)

## The on-screen tracker, under `ui` (a CanvasLayer's control).
func make_tracker(ui: Control) -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.035, 0.04, 0.05, 0.72), Color(1, 1, 1, 0.08), 6, 1, 10))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(32, 96)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_title = UITheme.heading("", 15)
	v.add_child(_title)
	_line = UITheme.label("", 15, UITheme.DIM)
	v.add_child(_line)
	_panel.visible = false
	ui.add_child(_panel)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_mx.lock()
	var made := _made
	_made = []
	_mx.unlock()
	for pl in made:
		_spawn(pl)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var p := player.global_position
	if _task < 0 or WorkerThreadPool.is_task_completed(_task):
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		var forts := Lore.gen().forts_near(p.x - SHELL, p.z - SHELL, p.x + SHELL, p.z + SHELL)
		var want: Array = []
		for f in forts:
			var id := "%d_%d" % [f["cx"], f["cz"]]
			if not _nodes.has(id) and (f["center"] as Vector2).distance_to(Vector2(p.x, p.z)) < SHELL:
				want.append(f)
		if not want.is_empty():
			_want = want
			_task = WorkerThreadPool.add_task(_plan_all)
	for id in _nodes.keys():
		var node: DungeonNode = _nodes[id]
		var d := (node.pl["c"] as Vector2).distance_to(Vector2(p.x, p.z))
		if d > DROP:
			node.queue_free()
			_nodes.erase(id)
		else:
			node.set_deep(d < DEEP)
	_track(p)

func _plan_all() -> void:
	var out: Array = []
	for f in _want:
		var pl := Dungeon.plan(_gen, f)
		if not pl["levels"].is_empty():
			out.append(pl)
	_mx.lock()
	_made.append_array(out)
	_mx.unlock()

func _spawn(pl: Dictionary) -> void:
	if _nodes.has(pl["id"]):
		return
	var node := DungeonNode.new()
	node.setup(pl, streamer, player)
	add_child(node)
	_nodes[pl["id"]] = node
	# Loaded (or arrived) down there: build it all now, before you fall.
	var q := Dungeon.to_plan(pl, player.global_position)
	var ext := float(pl["n"]) * Dungeon.CELL * 0.5
	if absf(q.x) <= ext and absf(q.z) <= ext and q.y < float(pl["y0"]) - 1.0:
		node.set_deep(true, true)

## The dungeon node you're in, or null.
func current() -> DungeonNode:
	var a := Dungeon.around(player.global_position)
	return a.get("node") if not a.is_empty() else null

## The levers, notes and the like within reach of `at`, over every dungeon built.
func usables(at: Vector3) -> Array:
	var out: Array = []
	for id in _nodes:
		var node: DungeonNode = _nodes[id]
		if node.deep:
			for u in node.usables(at):
				u["node"] = node
				out.append(u)
	return out

func _track(p: Vector3) -> void:
	var node := current()
	if node == null:
		# Fell through somewhere: back to the stair hall rather than the void.
		for id in _nodes:
			var n: DungeonNode = _nodes[id]
			var q := Dungeon.to_plan(n.pl, p)
			var ext := float(n.pl["n"]) * Dungeon.CELL * 0.5
			if n.deep and absf(q.x) <= ext and absf(q.z) <= ext and q.y < Dungeon.floor_y(n.pl, n.pl["levels"].size() - 1) - 6.0:
				var c := Dungeon.centre(n.pl, n.pl["entry"]["land"])
				var land := Dungeon.to_world(n.pl, Vector3(c.x, Dungeon.floor_y(n.pl, 0) + 0.3, c.y))
				player.global_position = land
				if "velocity" in player:
					player.velocity = Vector3.ZERO
		if _panel != null:
			_panel.visible = false
		return
	if _panel == null:
		return
	var pr := node.progress()
	var lv := Dungeon.level_near(node.pl, Dungeon.to_plan(node.pl, p).y)
	_title.text = String(node.pl["name"])
	_title.add_theme_color_override("font_color", UITheme.ERA_COLORS[int(node.pl["era"])])
	var bits := ["Level %d of %d" % [lv + 1, node.pl["levels"].size()], "Rooms %d/%d" % [pr["rooms"].x, pr["rooms"].y]]
	if pr["seals"].y > 0:
		bits.append("%s %d/%d" % [String(Dungeon.WORDS[int(node.pl["era"])][0]).capitalize() + "s", pr["seals"].x, pr["seals"].y])
	if pr["chests"].y > 0:
		bits.append("Chests %d/%d" % [pr["chests"].x, pr["chests"].y])
	_line.text = "  ·  ".join(bits)
	_panel.visible = true

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
