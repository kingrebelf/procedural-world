class_name MapLayers
extends RefCounted
## Overlays the minimap and atlas can paint over the land, picked with the map overlay
## key or in the atlas: the level of the creatures and people that live there, how
## dangerous that is for you, the technology era of what is built, the named zones and
## the landforms. One is shown at a time (WorldMap.layer, kept with the map).
##
## Each layer sorts the land into a few categories (a colour and a name each). The map is
## sampled into small tiles, a few per frame and cached, at a spacing that suits the zoom;
## each tile remembers which categories it holds, so a legend lists only what is in view.
## Level layers follow distance from spawn (Eras.zone_level) and are no secret, so they
## show over the fog of war; eras and landforms only show where you have uncovered.

enum { OFF, LEVELS, DANGER, ERA, ZONES, LAND }
const COUNT := 6
const NAMES := ["Off", "Creature levels", "Danger to you", "Technology era", "Zones", "Landforms"]
## Short names for the toast and the minimap legend.
const SHORT := ["Off", "Levels", "Danger", "Era", "Zones", "Land"]

const N := 32 ## samples per tile side (plus a border of one for seamless filtering)
const SPACINGS := [8.0, 32.0, 128.0] ## metres between samples, finest first
const BUDGET_USEC := 2500 ## time per frame spent sampling new tiles
const MAX_TILES := 700

const LEVEL_ALPHA := 0.4
const REGION_ALPHA := 0.48

## Danger bands against your level: [levels above you at most, colour, name].
const DANGER_BANDS := [[-5, Color(0.55, 0.62, 0.7), "Trivial"], [-1, Color(0.4, 0.82, 0.4), "Easy"],
	[3, Color(0.98, 0.86, 0.3), "Even"], [7, Color(1.0, 0.52, 0.2), "Hard"], [9999, Color(0.95, 0.2, 0.2), "Deadly"]]
## Colours of the ten-level bands (Lv 1-9, 10-19, ... 80), each clearly apart.
const LEVEL_COLORS := [Color(0.3, 0.8, 0.4), Color(0.95, 0.88, 0.3), Color(1.0, 0.6, 0.2), Color(0.95, 0.28, 0.22),
	Color(0.88, 0.25, 0.6), Color(0.62, 0.28, 0.9), Color(0.4, 0.32, 0.98), Color(0.25, 0.55, 1.0), Color(0.92, 0.92, 0.98)]
const ZONE_COLORS := [Color(0.45, 0.8, 0.38), Color(0.95, 0.78, 0.3), Color(1.0, 0.48, 0.22), Color(0.72, 0.3, 0.85)]
## Colours per landform (WorldField.LF_*); the first is rolling land with none.
const LAND_COLORS := [Color(0.5, 0.68, 0.42, 0.0), Color(0.86, 0.8, 0.6), Color(0.95, 0.62, 0.42), Color(0.5, 0.42, 0.72),
	Color(0.62, 0.64, 0.7), Color(0.78, 0.36, 0.3), Color(0.82, 0.68, 0.38), Color(0.3, 0.6, 0.95),
	Color(0.98, 0.86, 0.5), Color(0.6, 0.5, 0.45), Color(0.85, 0.48, 0.62)]
const LAND_NAMES := ["Rolling land", "Pillars", "Needles", "Sinkholes", "Crags", "Gorges", "Terraces", "Lakes", "Dunes", "Craters", "Badlands"]

static var _tiles := {} ## key -> [ImageTexture, category bitmask]
static var _queue: Array = [] ## [key, layer, spacing, tile x, tile z]
static var _queued := {}
static var _world := "" ## what the cache was made for (seed, theme, base level)

## The layer shown now.
static func current() -> int:
	return Game.map.layer if Game.map else OFF

## Whether the layer can show over the fog of war (it gives nothing away).
static func over_fog(layer: int) -> bool:
	return layer == LEVELS or layer == DANGER or (layer == ZONES and Eras.theme == "human")

# --- Categories -----------------------------------------------------------------------

## [colour, name] of category i of a layer.
static func category(layer: int, i: int) -> Array:
	match layer:
		LEVELS:
			var lo := maxi(maxi(i * 10, Eras.base_level), 1)
			var hi := mini(i * 10 + 9, Eras.max_level())
			return [LEVEL_COLORS[clampi(i, 0, LEVEL_COLORS.size() - 1)], "Lv %d" % lo if hi <= lo else "Lv %d-%d" % [lo, hi]]
		DANGER:
			return [DANGER_BANDS[i][1], DANGER_BANDS[i][2]]
		ERA:
			return [UITheme.ERA_COLORS[i], era_name(i)]
		ZONES:
			if Eras.theme == "human":
				return [ZONE_COLORS[i], ZoneInfo.HUMAN[i][1]]
			var kind: String = ZoneInfo.ALIEN.get(i, ZoneInfo.ALIEN[1])[0] if Eras.theme == "alien" else ZoneInfo.MIXED[i][0]
			return [UITheme.ERA_COLORS[i], kind]
		LAND:
			return [LAND_COLORS[i], LAND_NAMES[i]]
	return [Color.TRANSPARENT, ""]

## What is built in land of `era` on this kind of world.
static func era_name(era: int) -> String:
	match Eras.theme:
		"human":
			return "Human sci-fi outposts" if era == Eras.SCIFI else "Medieval kingdoms"
		"alien":
			return "Vex tech" if era == Eras.SCIFI else "Fey wilds"
	return Eras.NAMES[era]

static func _player_level() -> int:
	return Game.stats.level if Game.stats else 1

static func _danger(lv: int) -> int:
	var d := lv - _player_level()
	for i in DANGER_BANDS.size():
		if d <= DANGER_BANDS[i][0]:
			return i
	return DANGER_BANDS.size() - 1

static func _band(lv: int) -> int:
	for i in ZoneInfo.HUMAN.size():
		if lv < ZoneInfo.HUMAN[i][0]:
			return i
	return ZoneInfo.HUMAN.size() - 1

## The category of a layer at world point (x, z), -1 for none.
static func sample(layer: int, x: float, z: float) -> int:
	match layer:
		LEVELS:
			return Eras.zone_level(x, z) / 10
		DANGER:
			return _danger(Eras.zone_level(x, z))
		ZONES:
			if Eras.theme == "human":
				return _band(Eras.zone_level(x, z))
			return _era_at(x, z)
		ERA:
			return _era_at(x, z)
		LAND:
			var f := ZoneInfo._field_for(Game.seed)
			var s := f.region_site_at(x, z)
			return f.site_landform(s.x, s.y)
	return -1

static func _era_at(x: float, z: float) -> int:
	var f := ZoneInfo._field_for(Game.seed)
	var s := f.region_site_at(x, z)
	return f.site_era(s.x, s.y)

## One line on what a layer says about world point (x, z), for the atlas's hover.
static func describe(layer: int, x: float, z: float) -> String:
	var i := sample(layer, x, z)
	if i < 0:
		return ""
	match layer:
		LEVELS:
			return "Creatures Lv %d" % Eras.zone_level(x, z)
		DANGER:
			var lv := Eras.zone_level(x, z)
			return "%s  ·  Lv %d (you are %d)" % [category(layer, i)[1], lv, _player_level()]
		ZONES:
			if Eras.theme == "human":
				return "%s  ·  Lv %d" % [category(layer, i)[1], Eras.zone_level(x, z)]
	return category(layer, i)[1]

## A line under the legend: what the layer means for you.
static func note(layer: int) -> String:
	match layer:
		LEVELS:
			return "Creatures, bandits and loot match the land's level" if Eras.themed() else "This older world has no zone levels"
		DANGER:
			return "Against your level %d" % _player_level()
		ERA:
			return "Advanced gear unlocks at level %d" % Eras.UNLOCK_LEVEL if Eras.themed() else ""
		ZONES:
			return "Portals stand in level %d+ land" % WorldPortal.MIN_LEVEL if Eras.theme == "human" else ""
	return ""

## Circles of equal level round spawn worth drawing on this layer, as [radius m, label].
static func rings(layer: int) -> Array:
	var out: Array = []
	if not Eras.themed():
		return out
	var levels: Array = []
	match layer:
		LEVELS:
			for lv in range(10, Eras.max_level() + 1, 10):
				levels.append([lv, "Lv %d" % lv])
			if Eras.max_level() % 10 != 0:
				levels.append([Eras.max_level(), "Lv %d max" % Eras.max_level()])
		DANGER:
			var pl := _player_level()
			for i in DANGER_BANDS.size() - 1:
				levels.append([pl + int(DANGER_BANDS[i][0]) + 1, "%s from Lv %d" % [DANGER_BANDS[i + 1][2], pl + int(DANGER_BANDS[i][0]) + 1]])
		ZONES:
			if Eras.theme == "human":
				for i in range(1, ZoneInfo.HUMAN.size()):
					var lv: int = ZoneInfo.HUMAN[i - 1][0]
					levels.append([lv, "%s  ·  Lv %d" % [ZoneInfo.HUMAN[i][1], lv]])
	for e in levels:
		var lv: int = e[0]
		if lv > Eras.base_level and lv <= Eras.max_level():
			out.append([(lv - Eras.base_level) * Eras.LEVEL_STEP, e[1]])
	return out

# --- Tiles ----------------------------------------------------------------------------

## Draws the layer's tiles over `canvas` into `ci` and returns the categories in view (a
## bitmask). Tiles not made yet are queued and fill in over the next frames.
static func draw_tiles(ci: CanvasItem, canvas: MapCanvas, layer: int) -> int:
	_check_world()
	var spacing: float = SPACINGS[SPACINGS.size() - 1]
	for s in SPACINGS:
		if s * canvas.scale_ppm >= 2.5:
			spacing = s
			break
	var tm := spacing * N
	var a := canvas.to_world(Vector2.ZERO)
	var b := canvas.to_world(canvas.size)
	var mask := 0
	var extra := _player_level() if layer == DANGER else 0
	var added := false
	var hidden := not over_fog(layer) ## the legend counts only uncovered land
	for tz in range(floori(a.y / tm), floori(b.y / tm) + 1):
		for tx in range(floori(a.x / tm), floori(b.x / tm) + 1):
			var key := "%d:%d:%d:%d:%d" % [layer, int(spacing), tx, tz, extra]
			var t = _tiles.get(key)
			if t == null:
				if not _queued.has(key):
					_queued[key] = true
					_queue.append([key, layer, spacing, tx, tz])
					added = true
				continue
			var tl := canvas.to_local_px(tx * tm, tz * tm)
			ci.draw_texture_rect_region(t[0], Rect2(tl, Vector2(tm, tm) * canvas.scale_ppm), Rect2(1, 1, N, N))
			if hidden:
				mask |= _seen_mask(t[2], tx * tm, tz * tm, spacing, a, b)
			else:
				mask |= int(t[1])
	if added:
		# Nearest the middle of the view first (taken from the back); tiles for a view
		# long gone drop off the front.
		var mid := canvas.center
		_queue.sort_custom(func(p, q): return Vector2((p[3] + 0.5) * p[2] * N, (p[4] + 0.5) * p[2] * N).distance_squared_to(mid) \
			> Vector2((q[3] + 0.5) * q[2] * N, (q[4] + 0.5) * q[2] * N).distance_squared_to(mid))
		while _queue.size() > 200:
			_queued.erase(_queue.pop_front()[0])
	return mask

## Samples queued tiles until this frame's time is spent.
static func pump() -> void:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < BUDGET_USEC:
		var q: Array = _queue.pop_back()
		_queued.erase(q[0])
		if q[1] != current():
			continue
		_tiles[q[0]] = _make(q[1], q[2], q[3], q[4])
	if _tiles.size() > MAX_TILES:
		_tiles.clear()

static func _make(layer: int, spacing: float, tx: int, tz: int) -> Array:
	const W := N + 2
	var img := Image.create_empty(W, W, false, Image.FORMAT_RGBA8)
	var ox := tx * spacing * N - 0.5 * spacing
	var oz := tz * spacing * N - 0.5 * spacing
	# Sampled every BLOCK points first; a block whose corners agree is filled without
	# sampling inside it (regions are hundreds of metres across, so most are), the rest
	# point by point. Cuts the region layers' cost about tenfold.
	var cats := PackedByteArray()
	cats.resize(W * W)
	cats.fill(UNSET)
	var grid: Array[int] = []
	for g in range(0, W, BLOCK):
		grid.append(g)
	if grid[-1] != W - 1:
		grid.append(W - 1)
	for j in grid:
		for i in grid:
			cats[j * W + i] = _cat(layer, ox + i * spacing, oz + j * spacing)
	for gj in grid.size() - 1:
		for gi in grid.size() - 1:
			var i0 := grid[gi]
			var i1 := grid[gi + 1]
			var j0 := grid[gj]
			var j1 := grid[gj + 1]
			var c := cats[j0 * W + i0]
			var same := c == cats[j0 * W + i1] and c == cats[j1 * W + i0] and c == cats[j1 * W + i1]
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					if cats[j * W + i] == UNSET:
						cats[j * W + i] = c if same else _cat(layer, ox + i * spacing, oz + j * spacing)
	var cols := {}
	var mask := 0
	var alpha := LEVEL_ALPHA if over_fog(layer) else REGION_ALPHA
	for j in W:
		for i in W:
			var c := cats[j * W + i]
			if c == NONE:
				img.set_pixel(i, j, Color.TRANSPARENT)
				continue
			if i > 0 and j > 0 and i <= N and j <= N:
				mask |= 1 << c
			if not cols.has(c):
				var col: Color = category(layer, c)[0]
				cols[c] = Color(col.r, col.g, col.b, col.a * alpha)
			img.set_pixel(i, j, cols[c])
	return [ImageTexture.create_from_image(img), mask, cats]

const BLOCK := 4
const NONE := 255 ## no category at a sample
const UNSET := 254

static func _cat(layer: int, x: float, z: float) -> int:
	var c := sample(layer, x, z)
	return NONE if c < 0 else c

const SEEN_GRID := 6 ## points per tile side the legend checks for uncovered land

## Categories of a tile on land you have uncovered and that lies in view (a to b).
static func _seen_mask(cats: PackedByteArray, ox: float, oz: float, spacing: float, a: Vector2, b: Vector2) -> int:
	var m := 0
	for gj in SEEN_GRID:
		for gi in SEEN_GRID:
			var i := 1 + int((gi + 0.5) * N / SEEN_GRID)
			var j := 1 + int((gj + 0.5) * N / SEEN_GRID)
			var x := ox + (i - 0.5) * spacing
			var z := oz + (j - 0.5) * spacing
			if x < a.x or z < a.y or x > b.x or z > b.y:
				continue
			var c := cats[j * (N + 2) + i]
			if c != NONE and Game.map.revealed(x, z) >= 0.45:
				m |= 1 << c
	return m

## Drops the cache when another world or planet is open.
static func _check_world() -> void:
	var w := "%d/%s/%d" % [Game.seed, Eras.theme, Eras.base_level]
	if w != _world:
		_world = w
		_tiles.clear()
		_queue.clear()
		_queued.clear()

# --- Drawing helpers shared by the minimap and atlas ------------------------------------

## The parts of each ring that cross the view, as polylines in screen space. `to_px`
## maps world (x, z) to the screen; `view_c`/`reach` bound the world area in view.
static func ring_lines(layer: int, view_c: Vector2, reach: float, to_px: Callable) -> Array:
	var out: Array = []
	var d := view_c.length()
	for r in rings(layer):
		var rad: float = r[0]
		if absf(d - rad) > reach:
			continue
		var a0 := 0.0
		var span := PI
		if d > 1.0 and d > reach:
			a0 = atan2(view_c.y, view_c.x)
			span = acos(clampf((d * d + rad * rad - reach * reach) / (2.0 * d * rad), -1.0, 1.0))
		var steps := 64
		var pts := PackedVector2Array()
		var mid := Vector2.ZERO
		for k in steps + 1:
			var ang := a0 - span + 2.0 * span * k / steps
			var p: Vector2 = to_px.call(cos(ang) * rad, sin(ang) * rad)
			pts.append(p)
		# With spawn in view, each ring is named a little further round from the top, so
		# the names of close rings don't sit on one another.
		var am := a0 if span < PI else -PI * 0.5 + 0.45 * out.size()
		mid = to_px.call(cos(am) * rad, sin(am) * rad)
		out.append([pts, r[1], mid])
	return out

## A legend box: the layer's name, a swatch per category in `mask` and the layer's note.
## `right` puts the box's right edge at `p` (for the minimap, which sits on the right).
static func draw_legend(ci: CanvasItem, font: Font, p: Vector2, layer: int, mask: int, right := false, fs := 12) -> void:
	var rows: Array = []
	for i in 16:
		if mask & (1 << i):
			var c: Array = category(layer, i)
			if (c[0] as Color).a > 0.0:
				rows.append(c)
	var title: String = NAMES[layer]
	var nt := note(layer)
	var lh := fs + 6.0
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1).x
	for c in rows:
		w = maxf(w, font.get_string_size(c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0)
	var nfs := fs - 1
	if nt != "":
		w = maxf(w, font.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x)
	w += 16.0
	var h := 10.0 + lh + rows.size() * lh + (lh if nt != "" else 0.0) + 2.0
	var o := p - Vector2(w, 0) if right else p
	var box := Rect2(o, Vector2(w, h))
	ci.draw_rect(box, Color(0.04, 0.05, 0.06, 0.82))
	ci.draw_rect(box, UITheme.ACCENT * Color(1, 1, 1, 0.55), false, 1.0)
	var y := o.y + 6.0 + fs
	ci.draw_string(font, Vector2(o.x + 8, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, UITheme.ACCENT)
	for c in rows:
		y += lh
		var col: Color = c[0]
		ci.draw_rect(Rect2(o.x + 8, y - fs * 0.8, 11, 11), Color(col.r, col.g, col.b, 0.9))
		ci.draw_rect(Rect2(o.x + 8, y - fs * 0.8, 11, 11), Color(0, 0, 0, 0.6), false, 1.0)
		ci.draw_string(font, Vector2(o.x + 26, y), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT)
	if nt != "":
		y += lh
		ci.draw_string(font, Vector2(o.x + 8, y), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, UITheme.DIM)
