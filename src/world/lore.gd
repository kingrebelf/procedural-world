class_name Lore
## The things in rooms you can read or use with Interact: sci-fi terminals, wall screens
## and holo-tables, bookcases, lecterns, books, letters and scrolls, and the tombs of a
## crypt. Each says something about the place it stands in (the settlement or stronghold,
## the region, the people who live there, what is going around), rolled from the world
## seed and the object so it reads the same every visit. Some do something as well: a
## terminal downloads its survey onto your atlas and lets you charge your gear from the
## grid, a holo-table marks the nearest settlement, a shrine's rite restores you.
##
## The spots come straight from the rooms' furniture (Furnish.settled: Interiors.FURNISH and
## KitHouse.FURNISH), so they follow the props wherever those are placed. What you have
## read and done is kept in the room's state in the chunk snapshot: "lore" holds the
## spots read, "lore_act" the one-off and daily actions.

## Furniture that can be read or used, by model, and what kind of thing it is.
const KINDS := {
	"@console": "terminal", "scifi/Prop_Computer": "terminal", "@screen": "screen", "@holo": "holo",
	"props/Bookcase_2": "shelf", "props/BookStand": "lectern", "props/Book_5": "journal",
	"props/Book_Stack_1": "book", "props/BookGroup_Small_1": "book", "props/Scroll_1": "scroll",
	"@tomb": "tomb",
}

## How far above the model's origin the prompt sits, and so where you look to use it.
const ANCHOR := {"terminal": 1.05, "screen": 0.0, "holo": 1.0, "shelf": 1.2, "lectern": 1.1,
	"journal": 0.08, "book": 0.12, "scroll": 0.06, "tomb": 1.0}

## XP for the first read of each spot.
const XP := {"terminal": 12.0, "screen": 4.0, "holo": 10.0, "shelf": 15.0, "lectern": 15.0,
	"journal": 8.0, "book": 8.0, "scroll": 8.0, "tomb": 6.0}

const SURVEY_XP := 25.0
const LOOK := 1600.0 ## how far a terminal's survey reaches
const SIZES := ["hamlet", "village", "town"]

static var _spots: Dictionary = {}
static var _gen: ChunkGenerator
static var _gen_seed := -1

# --- Spots --------------------------------------------------------------------------

## Readable spots of room type `t`: [[kind, position in the object's space, model]].
static func spots(t: String) -> Array:
	if _spots.has(t):
		return _spots[t]
	var src: Array = Furnish.settled(t)
	var out: Array = []
	for f in src:
		var kind: String = KINDS.get(String(f[0]), "")
		if kind == "":
			continue
		var p: Vector3 = f[2]
		var near := false
		for s in out:
			if (s[1] as Vector3).distance_to(p) < 0.5:
				near = true
		if not near:
			out.append([kind, p, f[0]])
	_spots[t] = out
	return out

static func has(t: String) -> bool:
	return not spots(t).is_empty()

## Where spot `idx` of room `o` is in the chunk's space (the prompt's anchor).
static func anchor(o: Dictionary, idx: int) -> Vector3:
	var sp: Array = spots(o["t"])[idx]
	var q: Vector3 = sp[1]
	var s: float = o["s"]
	var at: Vector3 = o["p"]
	var p: Vector3 = at + Basis(Vector3.UP, o["r"]) * Vector3(q.x, 0, q.z) * s
	# Rooms sink into the ground by SINK and so do their props.
	p.y = at.y + (q.y - Interiors.SINK + float(ANCHOR[sp[0]])) * s + Interiors.SINK
	return p

## The prompt for spot `idx`.
static func verb(o: Dictionary, idx: int) -> String:
	var kind: String = spots(o["t"])[idx][0]
	var t: String = o["t"]
	var read := _was_read(o, idx)
	match kind:
		"terminal": return "Use the terminal"
		"screen": return "Read the bulletin screen"
		"holo": return "Study the holo-map"
		"shelf": return "Browse the shelves"
		"lectern": return "Read the town chronicle"
		"journal": return "Read the open journal"
		"book": return "Leaf through the books" if not read else "Read the books again"
		"scroll":
			if t == "shrine":
				return "Recite the rite"
			return "Read the scroll" if t.begins_with("crypt") else "Read the letter"
		"tomb": return "Read the epitaph"
	return "Look closer"

static func _was_read(o: Dictionary, idx: int) -> bool:
	for i in o["st"].get("lore", []):
		if int(i) == idx:
			return true
	return false

# --- Context ------------------------------------------------------------------------

static func gen() -> ChunkGenerator:
	if _gen == null or _gen_seed != Game.seed:
		_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers() if Game.store else true)
		_gen_seed = Game.seed
	return _gen

static var _site_names: Dictionary = {}

## The name a sci-fi room of type `t` at world point `wp` shows in its screens' headers:
## its stronghold's, settlement's or region's, as the terminal inside names its site.
static func site_name(t: String, wp: Vector3) -> String:
	var key := Vector3i(wp.snapped(Vector3.ONE))
	if _site_names.has(key):
		return _site_names[key]
	var g := gen()
	var name := g.field.region_name_at(wp.x, wp.z)
	if Stronghold.has(t):
		name = "%s of %s" % [Stronghold.NAMES[Eras.SCIFI], name]
	else:
		for s in g.settlements_near(wp.x - 1, wp.z - 1, wp.x + 1, wp.z + 1):
			var sc: Vector2 = s["center"]
			if sc.distance_to(Vector2(wp.x, wp.z)) <= float(s["outer"]):
				name = g.field.region_name_at(sc.x, sc.y)
				break
	_site_names[key] = name
	return name

## Everything the texts can name, as strings for String.format.
static func context(o: Dictionary, chunk: ChunkNode, idx: int, npcs: NPCManager) -> Dictionary:
	var g := gen()
	var wp: Vector3 = chunk.position + o["p"]
	var here := Vector2(wp.x, wp.z)
	var era := clampi(int(o["e"]), 0, Eras.COUNT - 1)
	var t: String = o["t"]
	var r := WHash.rng(Game.seed, chunk.key.x * 4099 + int(o["i"]), chunk.key.y, 4400 + idx)
	var region := g.field.region_name_at(wp.x, wp.z)
	var c := {"era": era, "region": region, "place": ObjectLibrary.label(t), "site": region, "site_kind": "",
		"rumors": [], "people": [], "resident": {}, "here": here, "rng_seed": r.seed}
	var first: Array = NPCGen.FIRST[era]
	var last: Array = NPCGen.LAST[era]
	var name := func() -> String: return "%s %s" % [first[r.randi() % first.size()], last[r.randi() % last.size()]]
	c["founder"] = name.call()
	c["author"] = name.call()
	c["other"] = name.call()
	c["dead"] = name.call()
	c["year"] = str([r.randi_range(310, 890), r.randi_range(12, 99), r.randi_range(2390, 2690)][era])
	c["age"] = str(r.randi_range(9, 140) if era != Eras.SCIFI else r.randi_range(4, 40))
	c["count"] = str(r.randi_range(3, 40))
	c["code"] = "%s-%d" % ["ABCDEFGHKMNPRSTVXZ"[r.randi() % 18], r.randi_range(100, 999)]
	c["day"] = str(NPCMind.day_num())
	c["time"] = NPCMind.time_words(NPCMind.hour_now())
	# The settlement around the room, and who lives in it.
	for s in g.settlements_near(here.x - 1, here.y - 1, here.x + 1, here.y + 1):
		var sc: Vector2 = s["center"]
		if sc.distance_to(here) <= float(s["outer"]):
			c["site"] = g.field.region_name_at(sc.x, sc.y)
			c["site_kind"] = SIZES[clampi(int(s.get("size", 0)), 0, 2)] if era != Eras.SCIFI else "outpost"
			if npcs:
				var rec: Dictionary = npcs.settlements.get(NPCGen.settlement_id(s["sx"], s["sz"]), {})
				if not rec.is_empty():
					var data: Dictionary = rec["data"]
					c["rumors"] = data.get("rumors", [])
					c["people"] = data.get("npcs", [])
			break
	if Stronghold.has(t):
		c["site"] = "the %s of %s" % [Stronghold.NAMES[era].to_lower(), region]
		c["site_kind"] = "stronghold"
	elif c["site_kind"] == "":
		c["site_kind"] = "outpost" if era == Eras.SCIFI else "steading"
	# Whoever's home this is: the door is about four metres towards the square.
	var best := 7.0
	for p in c["people"]:
		if p.get("dead", false) or not (p.get("home") is Vector2):
			continue
		var d: float = (p["home"] as Vector2).distance_to(here)
		if d < best:
			best = d
			c["resident"] = p
	var res: Dictionary = c["resident"]
	if not res.is_empty():
		c["author"] = res["name"]
	c["author_first"] = String(c["author"]).split(" ")[0]
	c["job"] = String(res.get("job", NPCGen.JOBS[era][r.randi() % 8]))
	c["likes"] = String(res.get("likes", NPCGen.LIKES[era][r.randi() % NPCGen.LIKES[era].size()]))
	c["worry"] = String(res.get("worry", NPCGen.WORRIES[era][r.randi() % NPCGen.WORRIES[era].size()]))
	c["crew"] = str((c["people"] as Array).size())
	# The nearest other settlements, for directions.
	var near: Array = []
	for s in g.settlements_near(here.x - LOOK, here.y - LOOK, here.x + LOOK, here.y + LOOK):
		var sc: Vector2 = s["center"]
		var d := sc.distance_to(here)
		if d > float(s["outer"]):
			near.append({"name": g.field.region_name_at(sc.x, sc.y), "d": d, "dir": Wonders.compass(here, sc), "c": sc,
				"era": int(s["era"]), "size": int(s.get("size", 0))})
	near.sort_custom(func(a, b): return a["d"] < b["d"])
	c["near_list"] = near
	if near.is_empty():
		c["near"] = "the far settlements"
		c["near_dir"] = ["east", "west", "north", "south"][r.randi() % 4]
		c["near_dist"] = "many days"
	else:
		c["near"] = near[0]["name"]
		c["near_dir"] = near[0]["dir"]
		c["near_dist"] = "%d m" % (int(round(near[0]["d"] / 10.0)) * 10)
	c["r"] = r
	return c

# --- Reading ------------------------------------------------------------------------

## What spot `idx` shows: {"look": "screen"|"page", "title", "sub", "pages": [{"tab",
## "text", "actions": [[id, label]]}], "note"}. The first read of each spot gives XP
## (the note says so) and is remembered in the room's state.
static func read(o: Dictionary, chunk: ChunkNode, idx: int, npcs: NPCManager) -> Dictionary:
	var kind: String = spots(o["t"])[idx][0]
	var c := context(o, chunk, idx, npcs)
	var out: Dictionary
	match kind:
		"terminal": out = _terminal(o, idx, c)
		"screen": out = _screen(c)
		"holo": out = _holo(o, idx, c)
		"shelf": out = _shelf(o, c)
		"lectern": out = _chronicle(c)
		"journal", "book": out = _journal(o, kind, c)
		"scroll": out = _scroll(o, idx, c)
		"tomb": out = _tomb(c)
		_: out = {"look": "page", "title": "Nothing", "sub": "", "pages": [{"tab": "", "text": ""}]}
	out["note"] = ""
	if not _was_read(o, idx):
		if not o["st"].has("lore"):
			o["st"]["lore"] = []
		(o["st"]["lore"] as Array).append(idx)
		Game.add_xp(float(XP[kind]), "Lore")
		Game.mark_chunk_dirty(chunk.data)
		out["note"] = "+%d XP for what you learned here" % int(XP[kind])
	return out

## Does action `id` on spot `idx`; returns the line to show.
static func act(o: Dictionary, chunk: ChunkNode, idx: int, id: String, player: Player) -> String:
	var st: Dictionary = o["st"]
	if not st.has("lore_act"):
		st["lore_act"] = {}
	var done: Dictionary = st["lore_act"]
	var key := "%d:%s" % [idx, id]
	var today := int(floor(Game.day))
	var wp: Vector3 = chunk.position + o["p"]
	var msg := ""
	match id:
		"survey":
			if done.has(key):
				return "This terminal's survey is already on your atlas."
			done[key] = true
			Game.add_xp(SURVEY_XP, "Discovery")
			var fort := _mark_fort(wp, int(o["e"]))
			var way := WonderEffects._mark_settlement(wp)
			var bits: Array = []
			if fort != "":
				bits.append(fort)
			if way != "":
				bits.append(way)
			msg = "Survey downloaded. " + ("; ".join(bits) if not bits.is_empty() else "Every site it knows is already on your atlas.")
		"power":
			if int(done.get(key, -1)) >= today:
				return "The grid allowance on this terminal is spent until tomorrow."
			var charged := WonderEffects._charge_lights(player)
			if not charged:
				return "You have nothing that takes a charge. (Flashlights do.)"
			done[key] = today
			msg = "The grid tops up your gear: every flashlight you carry is fully charged."
		"mark":
			var way := WonderEffects._mark_settlement(wp)
			if way == "":
				return "Every settlement the table shows is already on your atlas."
			Game.add_xp(10.0, "Discovery")
			msg = "Marked: " + way
		"rite":
			if int(done.get(key, -1)) >= today:
				return "You have spoken the rite today. The words rest until tomorrow."
			done[key] = today
			Game.set_stamina(Game.stats.max_stamina())
			Game.set_health(lerpf(Game.health, Game.stats.max_health(), 0.25))
			msg = "The candles gutter as you speak the old words. Calm fills you: stamina restored."
	Game.mark_chunk_dirty(chunk.data)
	return msg

## Marks the nearest stronghold not on the atlas yet; returns "Castle of X, 600 m to the
## north (marked on your atlas)" or "".
static func _mark_fort(wp: Vector3, era: int) -> String:
	var g := gen()
	var here := Vector2(wp.x, wp.z)
	var marked := {}
	for m in Game.markers.on_planet(Game.planet):
		marked[String(m["name"])] = true
	var best := {}
	var bd := INF
	for f in g.forts_near(here.x - LOOK, here.y - LOOK, here.x + LOOK, here.y + LOOK):
		var c: Vector2 = f["center"]
		var d := c.distance_to(here)
		var name := "%s of %s" % [Stronghold.NAMES[int(f["era"])], g.field.region_name_at(c.x, c.y)]
		if d < bd and d > 60.0 and not marked.has(name):
			bd = d
			best = {"name": name, "c": c}
	if best.is_empty():
		return ""
	var c: Vector2 = best["c"]
	Game.markers.add(best["name"], c.x, c.y, Game.planet)
	Game.touch_player()
	return "%s, %d m to the %s (marked on your atlas)" % [best["name"], int(round(bd / 10.0)) * 10, Wonders.compass(here, c)]

static func _pick(r: RandomNumberGenerator, a: Array) -> String:
	return a[r.randi() % a.size()]

## n different entries of `a`, in a seeded order.
static func _some(r: RandomNumberGenerator, a: Array, n: int) -> Array:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var tmp = b[i]
		b[i] = b[j]
		b[j] = tmp
	return b.slice(0, mini(n, b.size()))

static func _fmt(s: String, c: Dictionary) -> String:
	return s.format(c)

static func _rumor_lines(c: Dictionary, n: int) -> Array:
	var rum: Array = c["rumors"]
	var out: Array = []
	for i in range(rum.size() - 1, maxi(-1, rum.size() - 1 - n), -1):
		out.append(String(rum[i]))
	return out

# --- Sci-fi -------------------------------------------------------------------------

const LOGS := [
	"Perimeter sweep done. Sensors keep pinging something {near_dir} of {site}. Probably fauna. Probably.",
	"Supply drop came in short again. {other} says the convoy lost a crawler on the road to {near}. Rationing until it's sorted.",
	"Logged a power dip at 0300. Third this cycle. I've asked for a new cell bank; I've been asking since cycle {year}.",
	"Med check: everyone fit except {other}, who will not stop eating the hydroponics peppers. Noted for the record.",
	"Picked up an old-world beacon on the long scan. Dead carrier, but the frame ID predates the colony. Who put it there?",
	"Recalibrated the atmosphere scrubbers. Air tastes of metal for a day after; it always does. Don't drink the condensate.",
	"Night shift heard singing out past the fence. {other} swears it was the wind through the masts. Nobody believes {other}.",
	"Trade run to {near} ({near_dist} {near_dir}) went fine. They want circuitry and they pay in Marks. Good people, odd food.",
	"Reminder to all crew: the crates by the door are not seats. One of them is full of grenades.",
	"Raider sign by the dead zone. Fence charged, doors sealed after dark. Report anything moving without a transponder.",
	"Anniversary today: {age} cycles since {founder} set the first pylon here. We had cake. It was mostly protein paste.",
	"Long-range survey finished. I've loaded the plots into this terminal. Anyone passing can pull them to their atlas.",
	"The holo-table keeps drawing a road that isn't there. Either the map's wrong or the road's been eaten by the hills.",
	"Swapped the filters on the water still. Found a lizard in it. The lizard is fine. The filter is not.",
]
const COMMS := [
	"[{code}] ...repeat, convoy holding at the ridge, weather inbound...",
	"[relay] Market prices at {near}: circuitry up, rations down. Sell high.",
	"[{code}] Anyone near grid {code}? Lost a drone, reward offered, ask for {other}.",
	"[auto] Storm front moving {near_dir} at forty klicks. Secure loose cargo.",
	"[relay] Medical: wash your hands. That is the whole message. Wash them.",
	"[{code}] Spotted a starship wreck in the hills. Salvage crews, mind the reactor.",
	"[auto] Beacon network: lit beacons share their way to the nearest settlement. Light yours.",
]

static func _terminal(o: Dictionary, idx: int, c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	var logs: Array = []
	var n := 1
	for l in _some(r, LOGS, 3):
		logs.append("[b]LOG %s.%02d[/b]  //  %s\n%s" % [c["year"], n * 7 + r.randi_range(0, 6), c["author"] if n == 1 else c["other"], _fmt(l, c)])
		n += 1
	var comms: Array = []
	for line in _rumor_lines(c, 3):
		comms.append("[relay] " + line)
	for l in _some(r, COMMS, 4 - mini(2, comms.size())):
		comms.append(_fmt(l, c))
	var status := PackedStringArray([
		"%s %s  ·  %s" % [String(c["site"]).to_upper(), String(c["site_kind"]).to_upper(), String(c["place"]).to_upper()],
		"Local time: %s, day %s" % [c["time"], c["day"]],
		"Power: %d%%   Air: nominal   Fence: %s" % [r.randi_range(41, 97), "charged" if r.randf() < 0.7 else "OFFLINE"],
		"Crew registered: %s" % (c["crew"] if c["crew"] != "0" else "none logged in for %s days" % c["count"]),
		"Last user: %s (%s)" % [c["author"], c["job"]],
		"Nearest settlement: %s, %s to the %s" % [c["near"], c["near_dist"], c["near_dir"]],
	])
	var done: Dictionary = o["st"].get("lore_act", {})
	var survey := "Long-range survey on file: settlement plots and stronghold coordinates.\nDownloading it puts the nearest ones you haven't marked onto your atlas."
	if done.has("%d:survey" % idx):
		survey = "Survey on your atlas. Known sites in range:\n" + "\n".join(_site_lines(c, 5))
	return {"look": "screen", "title": "%s Terminal" % c["site"], "sub": "%s  ·  user %s" % [c["place"], c["author"]],
		"pages": [
			{"tab": "Logs", "text": "\n\n".join(logs)},
			{"tab": "Comms", "text": "\n".join(comms)},
			{"tab": "Status", "text": "\n".join(status), "actions": [["power", "Charge my gear from the grid"]]},
			{"tab": "Survey", "text": survey, "actions": [["survey", "Download survey to atlas"]]},
		]}

static func _site_lines(c: Dictionary, n: int) -> Array:
	var out: Array = []
	for s in (c["near_list"] as Array).slice(0, n):
		out.append("  %s  (%s %s)  %d m %s" % [s["name"], Eras.NAMES[s["era"]].to_lower(), "outpost" if s["era"] == Eras.SCIFI else SIZES[s["size"]], int(round(s["d"] / 10.0)) * 10, s["dir"]])
	return out if not out.is_empty() else ["  No settlements within range."]

const NOTICES := [
	"Hydroponics bay closed for cleaning. Again. Thank {other}.",
	"Lost: one multitool, red grip. Found: three multitools, none red.",
	"Curfew at dark until the fence is fixed.",
	"Shuttle schedule: whenever the pilot wakes up.",
	"Reminder: report all wildlife bites to medical, even the small ones. Especially the small ones.",
	"Movie night cancelled. The projector is now part of the comms array.",
	"Wanted: anyone who can fix a scrubber. Pay in Marks or rations.",
	"Do not feed the creatures by the gate. They are not pets. They are not friends.",
]

static func _screen(c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	var lines: Array = ["[b]%s %s BULLETIN[/b]   %s, day %s" % [String(c["site"]).to_upper(), String(c["site_kind"]).to_upper(), c["time"], c["day"]], ""]
	for l in _some(r, NOTICES, 3):
		lines.append("> " + _fmt(l, c))
	var rum := _rumor_lines(c, 3)
	if not rum.is_empty():
		lines.append("")
		lines.append("[b]NEWS[/b]")
		for l in rum:
			lines.append("> " + l)
	lines.append("")
	lines.append("Weather: %s. Next convoy to %s: %s." % [_pick(r, ["clear", "dust haze", "rain bands", "high winds", "cold snap"]), c["near"], _pick(r, ["tomorrow", "delayed", "on time", "cancelled"])])
	return {"look": "screen", "title": "Bulletin Screen", "sub": c["place"], "pages": [{"tab": "", "text": "\n".join(lines)}]}

static func _holo(o: Dictionary, idx: int, c: Dictionary) -> Dictionary:
	var lines: Array = ["The table throws up the land around %s in drifting blue light." % c["site"], ""]
	lines.append_array(_site_lines(c, 6))
	lines.append("")
	lines.append("Region: %s. A faint road traces off to the %s." % [c["region"], c["near_dir"]])
	return {"look": "screen", "title": "Holo-map", "sub": "%s  ·  %s" % [c["place"], c["region"]],
		"pages": [{"tab": "", "text": "\n".join(lines), "actions": [["mark", "Mark the nearest settlement"]]}]}

# --- Books ----------------------------------------------------------------------------

## Titles and pages per era: [title, page].
const BOOKS := [
	[
		["A Chronicle of {region}", "In the year {year} {founder} raised the first hall here, and the folk of {region} came for its fire. Of the wars that followed, the less written the better."],
		["The Wool Ledger", "Fleeces taken: {count}. Fleeces sold at {near}: fewer. Fleeces lost to the river: we do not speak of the river."],
		["Of Wolves and Their Ways", "The wolf of these parts hunts in threes and fears fire more than steel. Carry a torch on the road after dusk, and keep it lit."],
		["Psalter of the Road", "Bless the road that runs {near_dir}, for it leads to {near}; and bless the bridge, for it has not fallen yet."],
		["Herbal of the Hedgerows", "Feverfew for the head, yarrow for the wound, and for the heart that will not mend, ale and good company."],
		["On the Raising of Walls", "Set the footings deep, the stones close, and the gate facing the morning. A wall facing the evening invites thieves and poets."],
		["The Lay of {founder}", "Who rode alone to {near} through the snow, and came back with a bride, a cart of salt and no feeling in either foot."],
		["The Tally of Tithes", "Owed to the lord of {region}: {count} sacks of barley, two pigs, and an apology for last year."],
	],
	[
		["The Moon-Wheel Almanac", "In the {year}th turning the glowcaps sang for three nights, and {founder} wrote the songs down. Few could read them after."],
		["Spores and Their Speech", "The caps along the {near_dir} path answer to touch. Hum low and they brighten; shout and they sulk for a week."],
		["Of the Wildwood Folk", "They came to {region} following the light in the soil, and stayed because the light stayed. When it fades, they say, so will they."],
		["Riddles of the Thornveil", "What grows without roots, drinks without water and dies when named? (The answer is written on the last page, which is missing.)"],
		["A Grammar of Runes", "Each rune is a door, and each door wants a key: a word, a breath or a little blood. Most prefer the word."],
		["The Drowned Spire", "Some say the spire by {near} once stood in a lake, and the lake walked away one spring. The fish, they say, were furious."],
		["Notes on Aether", "Aether pools where the land is old. Crystals drink it up and give it back when struck, which is rude of them but useful."],
	],
	[
		["Colony Charter", "Article 3: every settler is owed air, water and one fair hearing. Article 4: the air ration is not negotiable."],
		["Field Manual, Rev. {count}", "When in doubt, seal the door. When not in doubt, seal it anyway and then think about it."],
		["The Long Haul", "We came down in cycle {year} with three ships and a map that was wrong in every way that mattered."],
	],
]

static func _shelf(_o: Dictionary, c: Dictionary) -> Dictionary:
	var era: int = c["era"]
	var day_r := WHash.rng(int(c["rng_seed"]), int(floor(Game.day)), 0, 17)
	var pages: Array = []
	for b in _some(day_r, BOOKS[era], 3):
		pages.append({"tab": _fmt(b[0], c), "text": "[i]%s[/i]\n\n%s" % [_fmt(b[0], c), _fmt(b[1], c)]})
	var place := "These shelves belong to %s, by the bookplates. " % c["author"] if not (c["resident"] as Dictionary).is_empty() else ""
	pages[0]["text"] = place + "You pull down a few volumes. The shelves turn up different ones each day.\n\n" + pages[0]["text"]
	return {"look": "page", "title": "Bookcase", "sub": "%s  ·  %s" % [c["place"], c["site"]], "pages": pages}

static func _chronicle(c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	var lines: Array = []
	var era: int = c["era"]
	lines.append(_fmt(["[b]The Chronicle of {site}[/b], kept on this stand by order of the council.",
		"[b]The Book of {site}[/b], written in many hands.",
		"[b]{site} Colony Record[/b]"][era], c))
	lines.append("")
	lines.append(_fmt(_pick(r, [
		"Founded in the year {year} by {founder}, who found good water and better stone, and would not stop talking about either.",
		"{founder} set the first beam here in {year}, they say on a dare, and the {site_kind} grew up around the joke.",
		"In {year}, {founder} led {count} families out of the hills to this place. Not all of them wanted to come.",
	]), c))
	lines.append(_fmt(_pick(r, [
		"The road {near_dir} to {near} was cut in {founder}'s grandchildren's time, and trade has never quite stopped since.",
		"A bad winter took a third of the herds. The well never froze, which is why the well is in every painting of this place.",
		"There was a quarrel with {near} over a boundary stone. The stone was moved back, and forth, and back again.",
	]), c))
	var people: Array = c["people"]
	if not people.is_empty():
		var names: Array = []
		for p in _some(r, people, 4):
			names.append("%s the %s" % [p["name"], p["job"]])
		lines.append("")
		lines.append("[b]Folk of this %s:[/b] %s, among others." % [c["site_kind"], ", ".join(names)])
	var rum := _rumor_lines(c, 4)
	if not rum.is_empty():
		lines.append("")
		lines.append("[b]Recent entries[/b]")
		for l in rum:
			lines.append("- " + l)
	return {"look": "page", "title": "Town Chronicle", "sub": "%s  ·  %s" % [c["site"], c["region"]], "pages": [{"tab": "", "text": "\n".join(lines)}]}

const JOURNAL := [
	"Couldn't sleep again. Worrying about {worry}. Told {other}, who laughed, which helped less than {other} thinks.",
	"A good day as a {job} goes. Nothing broke that I couldn't mend. Treated myself: {likes}.",
	"Saw a traveller on the road {near_dir} today. Armed, dusty, looking at everything. I hope they're the friendly sort.",
	"Note to self: owe {other} three Marks. Or they owe me. Ask before they remember.",
	"Walked to {near} and back, {near_dist} each way. My feet have filed a complaint.",
	"Nobody in {site} appreciates {likes} like I do. That's fine. More for me.",
	"Dreamed of {founder}, who built this place. In the dream they were angry about the roof. The roof does leak.",
	"If anyone reads this: put it back where you found it. Yes, you.",
]

static func _journal(o: Dictionary, kind: String, c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	if kind == "book" and (c["resident"] as Dictionary).is_empty() and String(o["t"]) != "cottage":
		return _shelf(o, c)
	var lines: Array = []
	var d := int(c["day"])
	var entries := _some(r, JOURNAL, 3)
	for i in entries.size():
		lines.append("[b]Day %d[/b]  %s" % [maxi(1, d - (entries.size() - i) * r.randi_range(1, 4)), _fmt(entries[i], c)])
	var who := "%s, %s of %s" % [c["author"], c["job"], c["site"]]
	return {"look": "page", "title": "%s's Journal" % c["author_first"], "sub": who, "pages": [{"tab": "", "text": "\n\n".join(lines)}]}

const LETTERS := [
	"Dear {author_first},\nThe roads from {near} are bad this season, so this may reach you late. Mother asks after your {worry}. I said you never mention it, which she took to mean it's worse. Write back.\n{other}",
	"{author_first},\nYou still have my good knife. I know you have it. Everyone knows. Return it by the market day or I tell the whole {site_kind} about the goose.\n{other}",
	"To whoever keeps this house,\nI passed through {site} on my way {near_dir} and you left the door open and the hearth warm. I took nothing but the warmth. Thank you.\nA traveller",
]
const RITES := [
	"[i]Rite of the Quiet Flame[/i]\nSpeak to the candle as to a friend. Ask it nothing. Let it ask you. Then breathe out slowly, and it will answer with stillness.",
	"[i]Rite of the Root[/i]\nPlace a palm on the stone. Name the dead of {region}, all you know. When you run out of names, the ground names the rest.",
]
const BURIAL := [
	"[i]For the Interred[/i]\nHere lie the keepers of {site}. They kept it {age} years. Disturb them only with good reason and a better excuse.",
	"[i]Inventory of Grave Goods[/i]\nOne sword, notched. One cup, silver. One small dog, carved in bone. Item: the dog is missing. Who took the dog?",
]

static func _scroll(o: Dictionary, idx: int, c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	var t: String = o["t"]
	if t == "shrine":
		return {"look": "page", "title": "Shrine Scroll", "sub": "%s  ·  %s" % [c["place"], c["region"]],
			"pages": [{"tab": "", "text": _fmt(_pick(r, RITES), c) + "\n\nSpeaking the rite once a day restores you.", "actions": [["rite", "Speak the rite"]]}]}
	if t.begins_with("crypt"):
		return {"look": "page", "title": "Crypt Scroll", "sub": c["site"], "pages": [{"tab": "", "text": _fmt(_pick(r, BURIAL), c)}]}
	return {"look": "page", "title": "A Letter", "sub": "to %s, %s" % [c["author"], c["site"]], "pages": [{"tab": "", "text": _fmt(_pick(r, LETTERS), c)}]}

const EPITAPHS := [
	"Here lies {dead}, who held {site} for {age} years and never once opened the gate to a stranger. Mostly.",
	"{dead}. Warden of {region}. Brave, stubborn, and right more often than was comfortable.",
	"{dead}, beloved of no one in particular, but missed by the dogs.",
	"Rest, {dead}. The wars are over. We are not sure who won.",
	"{dead}, last of the old keepers. Their lamp is still lit. Do not put it out.",
	"Sealed in the {year}th year: {dead}, keeper of the runes. If you hear tapping, it is the wind.",
]

static func _tomb(c: Dictionary) -> Dictionary:
	var r: RandomNumberGenerator = c["r"]
	return {"look": "page", "title": "Epitaph", "sub": "%s  ·  %s" % [c["place"], c["site"]],
		"pages": [{"tab": "", "text": "Letters cut deep in the lid, worn smooth by hands:\n\n[i]%s[/i]" % _fmt(_pick(r, EPITAPHS), c)}]}
