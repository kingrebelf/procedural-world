class_name WorldMap
extends RefCounted
## What the atlas and minimap know of the land: a painted map of every chunk that has
## loaded near you (2 m to the pixel: hill shading, contours, water, roads, woods and
## buildings) under a fog of war that lifts only where you have actually been and seen.
## Also the places worth a pin: settlements, strongholds, landmarks, caves and wonders.
##
## Kept per planet in <land>/map: pages of 16 x 16 chunks (colour and fog images) and an
## index of places. Old saves are painted in from their chunk snapshots, with the fog
## lifted over the chunks you visited.

const MPP := 2.0 ## metres per map pixel
const CPX := 32 ## pixels per chunk side
const PAGE := 16 ## chunks per page side
const PX := CPX * PAGE ## pixels per page side
const PAGE_M := PAGE * ChunkGenerator.SIZE ## metres per page side
const SIGHT := 90.0 ## how far you see the land around you on foot
const SIGHT_MAX := 260.0 ## from high up
const FIND := 75.0 ## how close you must come to a wonder to know it

var pois := {} ## "cx,cz" -> [{k, name, x, z, era}]
var wonders := {} ## "cx,cz" -> {t, x, z, era, cleared, found}
var ores := {} ## "cx,cz" -> [{t, x, z, n}]: each kind of ore in the chunk, at its middle
var people := {} ## npc id -> {name, job, town, x, z}: everyone you have spoken with
## What the atlas and minimap show, by category (see category()); missing means shown.
var filters := {}

## Filter categories in the order the atlas lists them: [key, label, icon].
const CATEGORIES := [["wonder", "Wonders", "wonder"], ["town", "Settlements", "village"],
	["fort", "Strongholds", "fort"], ["landmark", "Landmarks", "landmark"], ["cave", "Caves", "cave"],
	["trader", "Traders", "trader"], ["people", "People", "quest"],
	["ore_iron_vein", "Iron", "mine"], ["ore_aether_crystal", "Aether crystal", "mine"],
	["ore_alloy_scrap", "Alloy scrap", "mine"], ["marker", "Markers", "pin"]]
const ORE_COLORS := {"iron_vein": Color(0.85, 0.55, 0.4), "aether_crystal": Color(0.55, 0.85, 1.0), "alloy_scrap": Color(0.8, 0.82, 0.85)}

func shows(cat: String) -> bool:
	return filters.get(cat, true)

func set_shown(cat: String, on: bool) -> void:
	filters[cat] = on
	_index_dirty = true

## Everything known of one category as [{name, x, z, ...}], for the atlas's finder.
func known(cat: String) -> Array:
	var out: Array = []
	if cat == "people":
		for id in people:
			out.append(people[id])
	elif cat.begins_with("ore_"):
		var t := cat.trim_prefix("ore_")
		for key in ores:
			for o in ores[key]:
				if o["t"] == t and revealed(o["x"], o["z"]) >= 0.45:
					out.append({"name": "%s (%d)" % [ObjectLibrary.label(t), o["n"]], "x": o["x"], "z": o["z"]})
	elif cat == "wonder":
		for key in wonders:
			if wonders[key].get("found", false):
				out.append({"name": WonderSite.label(wonders[key]["t"]), "x": wonders[key]["x"], "z": wonders[key]["z"]})
	else:
		for key in pois:
			for poi in pois[key]:
				if poi["k"] == cat and revealed(poi["x"], poi["z"]) >= 0.45:
					out.append(poi)
	return out

## Remembers someone you have spoken with, where they work.
func note_person(rec: Dictionary, town: String) -> void:
	var w: Vector2 = rec.get("work", Vector2(rec["pos"].x, rec["pos"].z))
	people[String(rec["id"])] = {"name": rec["name"], "job": String(rec.get("job", "")), "town": town, "x": w.x, "z": w.y}
	_index_dirty = true
var _pages := {} ## Vector2i -> Page
var _dir := ""
var _store: WorldStore
var _queue: Array = [] ## chunk dicts waiting to be painted
var _migrate: Array = [] ## visited chunk keys from before the map existed
var _last := Vector2(INF, INF)
var _reveal_t := 0.0
var _save_t := 0.0
var _index_dirty := false
var _gen: ChunkGenerator
var _gen_seed := -1
static var _brushes := {}
var _missing := {} ## pages known not to exist
var _clock := 0.0
const MAX_PAGES := 40

class Page:
	var color: Image
	var fog: Image
	var painted := PackedByteArray() ## one byte per chunk
	var color_tex: ImageTexture
	var fog_tex: ImageTexture
	var color_dirty := true
	var fog_dirty := true
	var unsaved := false
	var used := 0.0 ## when it was last asked for

	func _init() -> void:
		color = Image.create_empty(PX, PX, false, Image.FORMAT_RGB8)
		color.fill(Color(0, 0, 0))
		fog = Image.create_empty(PX, PX, false, Image.FORMAT_RGBA8)
		fog.fill(Color(1, 1, 1, 0))
		painted.resize(PAGE * PAGE)

# --- Lifecycle ------------------------------------------------------------------------

## Opens the map of the store's current planet. `visited` is the discovery list of chunks
## you have stood in (older saves have only that).
func open(store: WorldStore, visited: Dictionary) -> void:
	close()
	_store = store
	_dir = store.map_dir() if store else ""
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
		var idx = WorldStore.read_var(_dir.path_join("index.dat"), true)
		if idx is Dictionary:
			pois = idx.get("pois", {})
			wonders = idx.get("wonders", {})
			ores = idx.get("ores", {})
			people = idx.get("people", {})
			filters = idx.get("filters", {})
	for key in visited:
		var p: PackedStringArray = String(key).split(",")
		var k := Vector2i(p[0].to_int(), p[1].to_int())
		if not _is_painted(k):
			_migrate.append(k)

func close() -> void:
	_wait_save()
	for t in _paint_tasks:
		WorkerThreadPool.wait_for_task_completion(t[0])
	_paint_tasks.clear()
	_pages.clear()
	_missing.clear()
	pois = {}
	wonders = {}
	ores = {}
	people = {}
	filters = {}
	_queue.clear()
	_migrate.clear()
	_last = Vector2(INF, INF)
	_dir = ""
	_store = null

## `background`: the files are compressed and written on a worker (the copy of the data is
## taken now), so the save every 20 s no longer freezes the game for 30-50 ms.
func save(background := false) -> void:
	if _dir == "":
		return
	var files: Array = []
	for k in _pages:
		var pg: Page = _pages[k]
		if pg.unsaved:
			files.append([_page_path(k), {"c": pg.color.get_data(), "f": pg.fog.get_data(), "p": pg.painted.duplicate()}])
			pg.unsaved = false
	if _index_dirty:
		files.append([_dir.path_join("index.dat"), {"pois": pois.duplicate(true), "wonders": wonders.duplicate(true), "ores": ores.duplicate(true),
			"people": people.duplicate(true), "filters": filters.duplicate(true)}])
		_index_dirty = false
	_wait_save()
	if files.is_empty():
		return
	if background:
		_save_task = WorkerThreadPool.add_task(_write_files.bind(files), false, "map save")
	else:
		_write_files(files)

var _save_task := -1

static func _write_files(files: Array) -> void:
	for f in files:
		WorldStore.write_var(f[0], f[1], true)

## Lets a background save finish (before anything else reads or writes the map's files).
func _wait_save() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1

func _page_path(k: Vector2i) -> String:
	return _dir.path_join("p%d_%d.dat" % [k.x, k.y])

# --- Pages ----------------------------------------------------------------------------

static func page_of_chunk(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / PAGE), floori(float(c.y) / PAGE))

## The page at `k`, loaded from disk, or created when `make`; null when there is none.
func page(k: Vector2i, make := false) -> Page:
	var pg: Page = _pages.get(k)
	if pg != null:
		pg.used = _clock
		return pg
	if not make and _missing.has(k):
		return null
	if _dir != "" and _save_task >= 0:
		_wait_save()
	if _dir != "" and FileAccess.file_exists(_page_path(k)):
		var d = WorldStore.read_var(_page_path(k), true)
		if d is Dictionary and (d.get("c") as PackedByteArray).size() == PX * PX * 3:
			pg = Page.new()
			pg.color = Image.create_from_data(PX, PX, false, Image.FORMAT_RGB8, d["c"])
			pg.fog = Image.create_from_data(PX, PX, false, Image.FORMAT_RGBA8, d["f"])
			pg.painted = d["p"]
	if pg == null and make:
		pg = Page.new()
	if pg == null:
		# Remember that there is nothing here, so drawing doesn't ask the disk every frame.
		_missing[k] = true
		return null
	_missing.erase(k)
	pg.used = _clock
	_pages[k] = pg
	return pg

## Keeps memory bounded on long journeys: saves and drops pages not used for a while.
func _evict() -> void:
	if _pages.size() <= MAX_PAGES:
		return
	for k in _pages.keys():
		var pg: Page = _pages[k]
		if _clock - pg.used > 10.0:
			if pg.unsaved and _dir != "":
				WorldStore.write_var(_page_path(k), {"c": pg.color.get_data(), "f": pg.fog.get_data(), "p": pg.painted}, true)
			if _dir != "":
				_pages.erase(k)

## [colour, fog] textures of page `k`, or [] if nothing of it is known. Main thread.
func textures(k: Vector2i) -> Array:
	var pg := page(k)
	if pg == null:
		return []
	if pg.color_dirty or pg.color_tex == null:
		var img := pg.color.duplicate() as Image
		img.generate_mipmaps()
		if pg.color_tex == null:
			pg.color_tex = ImageTexture.create_from_image(img)
		else:
			pg.color_tex.update(img)
		pg.color_dirty = false
	if pg.fog_dirty or pg.fog_tex == null:
		var img := pg.fog.duplicate() as Image
		img.generate_mipmaps()
		if pg.fog_tex == null:
			pg.fog_tex = ImageTexture.create_from_image(img)
		else:
			pg.fog_tex.update(img)
		pg.fog_dirty = false
	return [pg.color_tex, pg.fog_tex]

func _is_painted(c: Vector2i) -> bool:
	var pg := page(page_of_chunk(c))
	if pg == null:
		return false
	var lc := c - page_of_chunk(c) * PAGE
	return pg.painted[lc.y * PAGE + lc.x] != 0

## How much of the fog has lifted at world x, z (0 to 1).
func revealed(x: float, z: float) -> float:
	var k := Vector2i(floori(x / PAGE_M), floori(z / PAGE_M))
	var pg := page(k)
	if pg == null:
		return 0.0
	var px := clampi(int((x - k.x * PAGE_M) / MPP), 0, PX - 1)
	var py := clampi(int((z - k.y * PAGE_M) / MPP), 0, PX - 1)
	return pg.fog.get_pixel(px, py).a

# --- Chunks ---------------------------------------------------------------------------

## A chunk has loaded or changed: paint it if it's new to the map, and note its places.
func note_chunk(chunk: Dictionary) -> void:
	var c := Vector2i(int(chunk["cx"]), int(chunk["cz"]))
	if not _is_painted(c):
		_queue.append(chunk)
	_note_places(chunk)

func _note_places(chunk: Dictionary) -> void:
	var key := "%d,%d" % [chunk["cx"], chunk["cz"]]
	var w := WonderSite.of_chunk(chunk)
	if not w.is_empty():
		var old: Dictionary = wonders.get(key, {})
		w["found"] = old.get("found", false)
		if old.is_empty() or old.get("cleared", false) != w["cleared"]:
			wonders[key] = w
			_index_dirty = true
	var x0 := float(chunk["cx"]) * ChunkGenerator.SIZE
	var z0 := float(chunk["cz"]) * ChunkGenerator.SIZE
	_note_ores(chunk, key, x0, z0)
	if pois.has(key):
		return
	var out: Array = []
	var g := _generator()
	if g != null:
		for s in g.settlements_near(x0, z0, x0 + ChunkGenerator.SIZE, z0 + ChunkGenerator.SIZE):
			var sc: Vector2 = s["center"]
			if sc.x >= x0 and sc.x < x0 + ChunkGenerator.SIZE and sc.y >= z0 and sc.y < z0 + ChunkGenerator.SIZE:
				out.append({"k": "town", "name": g.field.region_name_at(sc.x, sc.y), "x": sc.x, "z": sc.y, "era": s["era"], "size": s["size"]})
	for o in chunk["objects"]:
		var t: String = o["t"]
		var p := Vector2(x0 + o["p"].x, z0 + o["p"].z)
		if t.ends_with("_keep") and Stronghold.has(t):
			out.append({"k": "fort", "name": Stronghold.NAMES[clampi(int(o["e"]), 0, 2)], "x": p.x, "z": p.y, "era": o["e"]})
		elif Landmark.has(t):
			out.append({"k": "landmark", "name": Landmark.LABELS[t], "x": p.x, "z": p.y, "era": o["e"]})
		elif t == "cave":
			out.append({"k": "cave", "name": "Cave", "x": p.x, "z": p.y, "era": o["e"]})
		elif t == "trader":
			out.append({"k": "trader", "name": String(o["st"].get("name", "Trader")), "x": p.x, "z": p.y, "era": o["e"]})
	pois[key] = out
	_index_dirty = true

## The ore left standing in a chunk, one entry per kind at the middle of its deposits.
## Redone whenever the chunk loads or a vein is mined out.
func _note_ores(chunk: Dictionary, key: String, x0: float, z0: float) -> void:
	var by := {}
	for o in chunk["objects"]:
		if ObjectLibrary.kind(o["t"]) != "ore" or o["st"].get("gone", false):
			continue
		var e: Array = by.get(o["t"], [Vector2.ZERO, 0])
		e[0] += Vector2(o["p"].x, o["p"].z)
		e[1] += 1
		by[o["t"]] = e
	var out: Array = []
	for t in by:
		var c: Vector2 = by[t][0] / by[t][1]
		out.append({"t": t, "x": x0 + c.x, "z": z0 + c.y, "n": by[t][1]})
	if out.is_empty():
		if ores.erase(key):
			_index_dirty = true
	elif ores.get(key, []) != out:
		ores[key] = out
		_index_dirty = true

func _generator() -> ChunkGenerator:
	if Game.store == null:
		return null
	if _gen == null or _gen_seed != Game.seed:
		_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers())
		_gen_seed = Game.seed
	return _gen

# --- Per frame ------------------------------------------------------------------------

## Paints waiting chunks, lifts the fog around the player and notices wonders.
func process(delta: float, player: Node3D) -> void:
	_clock += delta
	# New chunks are painted on workers (about 5 ms each) and blitted in here.
	var budget := 3
	for t in _paint_tasks.duplicate():
		if WorkerThreadPool.is_task_completed(t[0]):
			WorkerThreadPool.wait_for_task_completion(t[0])
			_paint_tasks.erase(t)
			var ch: Dictionary = t[1]
			if not _is_painted(Vector2i(int(ch["cx"]), int(ch["cz"]))) and not (t[2] as Array).is_empty():
				_blit(ch, t[2][0])
				budget -= 1
	while _paint_tasks.size() < 2 and not _queue.is_empty():
		var ch: Dictionary = _queue.pop_front()
		if not _is_painted(Vector2i(int(ch["cx"]), int(ch["cz"]))):
			var out: Array = []
			var task := WorkerThreadPool.add_task(func(): out.append(paint_tile(ch)), false, "map paint")
			_paint_tasks.append([task, ch, out])
	if budget > 0 and not _migrate.is_empty() and _store != null:
		var k: Vector2i = _migrate.pop_back()
		if not _is_painted(k) and _store.has_chunk(k.x, k.y):
			var ch = _store.load_chunk(k.x, k.y)
			if ch is Dictionary:
				paint(ch)
				_note_places(ch)
				var mid := (Vector2(k) + Vector2(0.5, 0.5)) * ChunkGenerator.SIZE
				reveal(mid, SIGHT)
	if player == null or not is_instance_valid(player):
		return
	var pos := Vector2(player.global_position.x, player.global_position.z)
	_reveal_t -= delta
	if _reveal_t <= 0.0 and pos.distance_to(_last) > 5.0:
		_reveal_t = 0.2
		_last = pos
		var ground := player.global_position.y
		var s = player.get("streamer")
		if s is ChunkStreamer:
			var cn: ChunkNode = s.get_chunk(ChunkStreamer.chunk_of(player.global_position))
			if cn != null:
				ground = ChunkGenerator.height_at(cn.data, player.global_position.x - cn.position.x, player.global_position.z - cn.position.z)
				_find_cave(cn.data, pos)
		reveal(pos, clampf(SIGHT + maxf(0.0, player.global_position.y - ground) * 1.5, SIGHT, SIGHT_MAX))
		_find_wonders(pos)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 20.0
		save(true)
		_evict()

## A cave mouth (v10) goes on the map only once you have stood by it: they are hidden.
func _find_cave(chunk: Dictionary, pos: Vector2) -> void:
	if not chunk.has("hole"):
		return
	var key := "%d,%d" % [int(chunk["cx"]), int(chunk["cz"])]
	var list: Array = pois.get(key, [])
	for poi in list:
		if poi["k"] == "cave":
			return
	var hb: PackedByteArray = chunk["hole"]
	var sum := Vector2.ZERO
	var n := 0
	for k in hb.size():
		if hb[k] != 0:
			sum += Vector2(k % ChunkGenerator.RES, k / ChunkGenerator.RES)
			n += 1
	var at := Vector2(float(chunk["cx"]), float(chunk["cz"])) * ChunkGenerator.SIZE + sum / maxi(n, 1)
	if n == 0 or pos.distance_to(at) > 16.0:
		return
	list.append({"k": "cave", "name": "Cave", "x": at.x, "z": at.y, "era": chunk.get("era", 0)})
	pois[key] = list
	_index_dirty = true
	Game.add_xp(60.0, "Found a cave")
	Game.discovered.emit("Cave", "Cave entrance found", Color(0.62, 0.58, 0.52))

func _find_wonders(pos: Vector2) -> void:
	for key in wonders:
		var w: Dictionary = wonders[key]
		if w.get("found", false):
			continue
		if pos.distance_to(Vector2(w["x"], w["z"])) < FIND:
			w["found"] = true
			_index_dirty = true
			Game.add_xp(250.0, "Found " + WonderSite.label(w["t"]))
			Game.discovered.emit(WonderSite.label(w["t"]), "Wonder discovered", WonderSite.COLORS[w["t"]])

## Lifts the fog in a soft-edged circle.
func reveal(at: Vector2, radius: float) -> void:
	var rp := int(ceil(radius / MPP))
	var brush := _brush(rp)
	var x0 := int(floor(at.x / MPP)) - rp
	var y0 := int(floor(at.y / MPP)) - rp
	var span := rp * 2 + 1
	for pz in range(floori(float(y0) / PX), floori(float(y0 + span) / PX) + 1):
		for px in range(floori(float(x0) / PX), floori(float(x0 + span) / PX) + 1):
			var k := Vector2i(px, pz)
			var pg := page(k, true)
			if pg == null:
				continue
			# Clip the brush to this page.
			var dx := x0 - px * PX
			var dy := y0 - pz * PX
			var sx := maxi(0, -dx)
			var sy := maxi(0, -dy)
			var w := mini(span, PX - dx) - sx
			var h := mini(span, PX - dy) - sy
			if w <= 0 or h <= 0:
				continue
			pg.fog.blend_rect(brush, Rect2i(sx, sy, w, h), Vector2i(dx + sx, dy + sy))
			pg.fog_dirty = true
			pg.unsaved = true

static func _brush(rp: int) -> Image:
	rp = maxi(4, int(round(rp / 4.0)) * 4)
	if _brushes.has(rp):
		return _brushes[rp]
	var n := rp * 2 + 1
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - rp, y - rp).length() / rp
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.55, 1.0, d)))
	_brushes[rp] = img
	return img

# --- Painting -------------------------------------------------------------------------

const LAND := [Color(0.47, 0.57, 0.31), Color(0.27, 0.52, 0.5), Color(0.57, 0.5, 0.41)]
const ROCK := Color(0.56, 0.53, 0.49)
const SAND := Color(0.8, 0.74, 0.56)
const SNOW := Color(0.93, 0.94, 0.96)
const SHALLOW := Color(0.42, 0.66, 0.72)
const DEEP := Color(0.12, 0.25, 0.4)
const RIVER := Color(0.3, 0.56, 0.72)
const ROAD := Color(0.87, 0.79, 0.6)
const ROOF := [Color(0.58, 0.3, 0.22), Color(0.55, 0.36, 0.62), Color(0.78, 0.8, 0.84)]
const LIGHT := Vector3(-0.55, 0.75, -0.4)

## Paints one chunk onto its page.
func paint(chunk: Dictionary) -> void:
	_blit(chunk, paint_tile(chunk))

var _paint_tasks: Array = [] ## [task id, chunk, [tile once done]]

## Puts a chunk's painted tile (paint_tile) on its page.
func _blit(chunk: Dictionary, px: PackedByteArray) -> void:
	var c := Vector2i(int(chunk["cx"]), int(chunk["cz"]))
	var pk := page_of_chunk(c)
	var pg := page(pk, true)
	if pg == null:
		return
	var tile := Image.create_from_data(CPX, CPX, false, Image.FORMAT_RGB8, px)
	var lc := c - pk * PAGE
	pg.color.blit_rect(tile, Rect2i(0, 0, CPX, CPX), lc * CPX)
	pg.painted[lc.y * PAGE + lc.x] = 1
	pg.color_dirty = true
	pg.unsaved = true

## The chunk as CPX x CPX RGB8 pixels. Static and pure, so it can be tested.
static func paint_tile(chunk: Dictionary) -> PackedByteArray:
	const R := ChunkGenerator.RES
	var hs: PackedFloat32Array = chunk["heights"]
	var wb: PackedByteArray = chunk["weights"]
	var rb: PackedByteArray = chunk.get("road", PackedByteArray())
	var out := PackedByteArray()
	out.resize(CPX * CPX * 3)
	var cols: Array = []
	cols.resize(CPX * CPX)
	var L := LIGHT.normalized()
	var step := int(MPP)
	for j in CPX:
		for i in CPX:
			var gi := i * step + 1
			var gj := j * step + 1
			var k := gj * R + gi
			var h := hs[k]
			var hl := hs[k - 1]
			var hr := hs[k + 1]
			var hd := hs[k - R]
			var hu := hs[k + R]
			var col: Color
			var river := ChunkGenerator.under_river(chunk, gi, gj)
			if h < ChunkGenerator.WATER_LEVEL:
				col = SHALLOW.lerp(DEEP, clampf(-h / 14.0, 0.0, 1.0))
			elif river:
				col = RIVER
			else:
				var w0 := wb[k * Eras.COUNT] / 255.0
				var w1 := wb[k * Eras.COUNT + 1] / 255.0
				var w2 := wb[k * Eras.COUNT + 2] / 255.0
				col = (LAND[0] * w0 + LAND[1] * w1 + LAND[2] * w2) / maxf(0.001, w0 + w1 + w2)
				col = col.lightened(clampf(h / 160.0, 0.0, 0.25))
				var stone := ChunkGenerator.stone_at(chunk, gi, gj)
				var slope := Vector2(hr - hl, hu - hd).length() * 0.5
				var rock := smoothstep(0.55, 1.0, slope)
				if stone.a > 0.0:
					rock = maxf(rock, stone.a * 0.6)
					col = col.lerp(Color(stone.r, stone.g, stone.b), stone.a * 0.5)
				col = col.lerp(ROCK if stone.a <= 0.0 else Color(stone.r, stone.g, stone.b).lerp(ROCK, 0.4), rock)
				col = col.lerp(SAND, 1.0 - smoothstep(0.4, 1.6, h))
				col = col.lerp(SNOW, smoothstep(62.0, 82.0, h) * (1.0 - rock * 0.5))
				if not rb.is_empty():
					col = col.lerp(ROAD, rb[k] / 255.0 * 0.9)
				# Hill shading, then a contour every 10 m.
				var n := Vector3(-(hr - hl) * 0.5, 1.0, -(hu - hd) * 0.5).normalized()
				col = col * (0.62 + 0.55 * clampf(n.dot(L), 0.0, 1.0))
				col.a = 1.0
				if floori(h / 10.0) != floori(hr / 10.0) or floori(h / 10.0) != floori(hu / 10.0):
					col = col.darkened(0.14)
			cols[j * CPX + i] = col
	# Coastlines and riverbanks get a dark edge.
	for j in CPX:
		for i in CPX:
			var a := hs[(j * step + 1) * R + i * step + 1] < ChunkGenerator.WATER_LEVEL
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var ni := clampi(i + d.x, 0, CPX - 1)
				var nj := clampi(j + d.y, 0, CPX - 1)
				if (hs[(nj * step + 1) * R + ni * step + 1] < ChunkGenerator.WATER_LEVEL) != a:
					edge = true
			if edge and not a:
				cols[j * CPX + i] = (cols[j * CPX + i] as Color).darkened(0.35)
	# Woods, buildings and the wonders themselves.
	for o in chunk["objects"]:
		if o["st"].get("gone", false):
			continue
		var t: String = o["t"]
		var kind := ObjectLibrary.kind(t)
		var pi := int(o["p"].x / MPP)
		var pj := int(o["p"].z / MPP)
		if kind == "tree":
			_dab(cols, pi, pj, 1, Color(0.12, 0.24, 0.12), 0.35)
		elif WonderSite.is_centre(t):
			_dab(cols, pi, pj, 4, WonderSite.COLORS[t].darkened(0.2), 0.9)
			_dab(cols, pi, pj, 2, WonderSite.COLORS[t].lightened(0.3), 0.9)
		elif WonderSite.has(t):
			_dab(cols, pi, pj, 0, Color(0.2, 0.2, 0.22), 0.8)
		elif kind == "structure" and t != "bridge" and t != "cave":
			var e := clampi(int(o["e"]), 0, 2)
			var r := 1
			if Stronghold.has(t):
				_dab(cols, pi, pj, 2, Color(0.35, 0.34, 0.33), 0.9)
				continue
			_dab(cols, pi, pj, r, ROOF[e], 0.85)
	for idx in CPX * CPX:
		var col: Color = cols[idx]
		out[idx * 3] = clampi(int(col.r * 255.0), 0, 255)
		out[idx * 3 + 1] = clampi(int(col.g * 255.0), 0, 255)
		out[idx * 3 + 2] = clampi(int(col.b * 255.0), 0, 255)
	return out

static func _dab(cols: Array, ci: int, cj: int, r: int, c: Color, a: float) -> void:
	for j in range(cj - r, cj + r + 1):
		for i in range(ci - r, ci + r + 1):
			if i < 0 or j < 0 or i >= CPX or j >= CPX:
				continue
			if r > 1 and Vector2(i - ci, j - cj).length() > r + 0.5:
				continue
			cols[j * CPX + i] = (cols[j * CPX + i] as Color).lerp(c, a)
