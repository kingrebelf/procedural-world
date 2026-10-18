extends SceneTree
## Renders the terminal window (TerminalUI) for each kind of screen with sample pages,
## after it has booted and run a while:
##   godot --path . --script res://tools/preview_terminal_ui.gd -- --out=<dir> [--kinds=terminal,map]
##     [--size=1600x900] [--wait=2.5]

const SITES := [["Kestrel Reach", 420.0, -610.0, 740.0], ["Ashfall Gate", -900.0, 300.0, 950.0],
	["Coldwater", 200.0, 1100.0, 1120.0], ["Bastion of Vire", -300.0, -280.0, 410.0]]

func _entries() -> Dictionary:
	var logs := "[b]LOG 2512.07[/b]  //  Ida Marsh\nPerimeter sweep done. Sensors keep pinging something north of Kestrel Reach. Probably fauna. Probably.\n\n[b]LOG 2512.16[/b]  //  Oren Vale\nSwapped the filters on the water still. Found a lizard in it. The lizard is fine. The filter is not."
	return {
		"terminal": {"look": "screen", "title": "Kestrel Reach Terminal", "sub": "Ops Tower  ·  user Ida Marsh", "note": "+12 XP for what you learned here",
			"pages": [{"tab": "Logs", "text": logs}, {"tab": "Comms", "text": "[relay] Market prices at Ashfall Gate: circuitry up."},
				{"tab": "Status", "text": "Power: 74%", "actions": [["power", "Charge my gear from the grid"]]},
				{"tab": "Survey", "text": "Long-range survey on file.", "actions": [["survey", "Download survey to atlas"]]}],
			"screen": {"kind": "terminal", "room": "ops_tower", "site": "Kestrel Reach", "os": "OPS/CTL", "user": "Ida Marsh", "code": "K-412", "power": 74, "sites": SITES}},
		"bunker": {"look": "screen", "title": "Bastion of Vire Terminal", "sub": "Bunker Keep  ·  user Oren Vale",
			"pages": [{"tab": "Logs", "text": logs}, {"tab": "Status", "text": "Power: 43%   Fence: OFFLINE", "actions": [["power", "Charge my gear from the grid"]]}],
			"screen": {"kind": "terminal", "room": "bunker_keep", "site": "Bastion of Vire", "os": "MILNET", "user": "Oren Vale", "code": "V-220", "power": 43, "sites": SITES}},
		"map": {"look": "screen", "title": "Holo-map", "sub": "Lab Block  ·  Greyfen",
			"pages": [{"tab": "", "text": "The table throws up the land around Kestrel Reach.\n\n  Bastion of Vire  410 m northwest", "actions": [["mark", "Mark the nearest settlement"]]}],
			"screen": {"kind": "map", "room": "lab_block", "site": "Kestrel Reach", "os": "LABNET", "user": "Ida Marsh", "power": -1, "sites": SITES}},
		"bulletin": {"look": "screen", "title": "Bulletin Screen", "sub": "Ops Tower",
			"pages": [{"tab": "", "text": "[b]KESTREL REACH OUTPOST BULLETIN[/b]   evening, day 12\n\n> Hydroponics bay closed for cleaning. Again.\n> Curfew at dark until the fence is fixed."}],
			"screen": {"kind": "bulletin", "room": "ops_tower", "site": "Kestrel Reach", "os": "OPS/CTL", "user": "guest", "power": -1, "sites": SITES,
				"ticker": ["Raiders seen on the road to Ashfall Gate", "A starship wreck in the hills", "Next convoy to Coldwater: delayed"]}},
		"notice": {"look": "screen", "title": "Containment Breach", "sub": "Bastion of Vire",
			"pages": [{"tab": "Notice", "text": "Sublevel 2 sealed. Do not open the lab doors without a keycard and a very good reason."}],
			"screen": {"kind": "notice", "room": "bunker", "site": "Bastion of Vire", "os": "MILNET", "user": "guest"}},
	}

func _initialize() -> void:
	var out := "user://terminal_ui"
	var size := Vector2i(1600, 900)
	var want: Array = []
	var wait := 2.5
	Eras.theme = "human"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--kinds="):
			want = Array(a.substr(8).split(","))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--wait="):
			wait = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	root.size = size
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.18, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	await process_frame
	var entries := _entries()
	for k: String in entries:
		if not want.is_empty() and not want.has(k):
			continue
		var term := TerminalUI.new()
		term.setup(entries[k], func(id: String) -> String: return "Done: " + id, func(): pass)
		root.add_child(term)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < int(wait * 1000.0):
			await process_frame
		var path: String = out + "/terminal_ui_%s.png" % k
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		term.queue_free()
		await process_frame
	quit()
