extends Node
## Automated screenshot tour used to check visuals without a human at the keyboard:
##   godot --path . res://src/world/world.tscn -- --capture [--out=DIR] [--seed=N]
## Finds a medieval town, a fantasy wildwood, a sci-fi outpost and an era border,
## frames each, waits for lighting to settle, and writes PNGs.

var world: Node3D
var out_dir := "user://captures"
var settle_frames := 150
var only: PackedStringArray = [] ## --shots=01,07 limits the tour to those shots

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--frames="):
			settle_frames = a.substr(9).to_int()
		if a.begins_with("--shots="):
			only = a.substr(8).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_loaded(p: Player, streamer: ChunkStreamer) -> void:
	for i in 3000:
		await get_tree().process_frame
		var c := ChunkStreamer.chunk_of(p.global_position)
		var ok := streamer._jobs.is_empty() and streamer._results.is_empty()
		for dz in range(-streamer.view_radius, streamer.view_radius + 1):
			for dx in range(-streamer.view_radius, streamer.view_radius + 1):
				if not streamer.chunks.has(c + Vector2i(dx, dz)):
					ok = false
		if ok:
			return

func _find_settlement(g: ChunkGenerator, era: int, min_size := 0) -> Dictionary:
	for r in 40:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if maxi(absi(sx), absi(sz)) != r:
					continue
				var s := g.settlement_at(sx, sz)
				if not s.is_empty() and s["era"] == era and int(s["size"]) >= min_size:
					return s
	return {}

func _find_era(g: ChunkGenerator, era: int, min_w: float) -> Vector2:
	for i in 4000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (40.0 + i * 6.0)
		if g.field.era_weights(p.x, p.y)[era] >= min_w:
			return p
	return Vector2.ZERO

func _find_border(g: ChunkGenerator) -> Vector2:
	for i in 4000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 5.0)
		var w := g.field.era_weights(p.x, p.y)
		var sorted := Array(w)
		sorted.sort()
		if sorted[2] < 0.55 and sorted[1] > 0.4:
			return p
	return Vector2.ZERO

func _find_shore(g: ChunkGenerator) -> Vector2:
	for i in 6000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 5.0)
		if g.field.height(p.x, p.y) < Water.LEVEL - 4.0:
			# Walk back toward the origin until we reach dry land a little above the water.
			var dir := -p.normalized()
			for k in 80:
				var q := p + dir * (k * 3.0)
				if g.field.height(q.x, q.y) > Water.LEVEL + 0.6:
					return q
	return Vector2.ZERO

## A spot on a river bank, with a point mid-river to look at (Vector4: at.xy, look.zw).
func _find_river(g: ChunkGenerator) -> Vector4:
	var cache := {}
	for i in 6000:
		var a := i * 0.37
		var p := Vector2(cos(a), sin(a)) * (60.0 + i * 4.0)
		if g.field.river_t(p.x, p.y) > 0.15 or g.field.era_weights(p.x, p.y)[Eras.MEDIEVAL] < 0.8:
			continue
		var lv := g.field.river_level(p.x, p.y, cache)
		if WorldField.river_strength(g.field.height(p.x, p.y), lv) < 0.8:
			continue
		for k in 16:
			var d := Vector2.from_angle(k * TAU / 16.0)
			var q := p + d * 26.0
			var t := g.field.river_t(q.x, q.y)
			if t > 1.8 and t < 3.5:
				return Vector4(q.x, q.y, p.x - d.x * 20.0 - d.y * 25.0, p.y - d.y * 20.0 + d.x * 25.0)
	return Vector4.ZERO

func _shot(name: String, at: Vector2, look_at: Vector2, day: float, height := 1.7, look_y := NAN, before := Callable()) -> void:
	if not only.is_empty() and not only.has(name.substr(0, 2)):
		return
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	Game.day = day
	var g := ChunkGenerator.new(Game.seed)
	var y := g.field.height(at.x, at.y) + height
	p.set_physics_process(false)
	p.global_position = Vector3(at.x, y, at.y)
	await _wait_loaded(p, streamer)
	# Use the real (snapshotted, flattened) height once the chunk exists.
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(p.global_position))
	if c:
		y = ChunkGenerator.height_at(c.data, at.x - c.key.x * 64.0, at.y - c.key.y * 64.0) + height
		p.global_position.y = y
	var tgt_h := y
	var tc: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(Vector3(look_at.x, 0, look_at.y)))
	if tc:
		tgt_h = ChunkGenerator.height_at(tc.data, look_at.x - tc.key.x * 64.0, look_at.y - tc.key.y * 64.0) + 3.0
	if not is_nan(look_y):
		tgt_h = look_y
	var d := Vector3(look_at.x - at.x, tgt_h - y, look_at.y - at.y)
	p.set_state({"pos": p.global_position, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5), "slot": 0})
	world.atmosphere._target_w = world.atmosphere.field.era_weights(at.x, at.y)
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	await _wait(settle_frames)
	if before.is_valid():
		await before.call()
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name, " at ", at, " weights ", world.atmosphere._w)

func _run() -> void:
	await _wait(5)
	var g := ChunkGenerator.new(Game.seed)
	if g.deep_caves and (only.is_empty() or only.has("40") or only.has("41") or only.has("42")):
		# Caves are planned on the land rivers carve: plan with the world's own rivers flag.
		await _cave_shots(ChunkGenerator.new(Game.seed, Game.store.has_rivers()))
	var med := _find_settlement(g, Eras.MEDIEVAL)
	var fan := _find_settlement(g, Eras.FANTASY)
	var sci := _find_settlement(g, Eras.SCIFI)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		# The biggest town nearby, seen from the road into it.
		var town := _find_settlement(g, Eras.MEDIEVAL, 2) if g.towns else {}
		var ways: Array = g.road_angles(town) if not town.is_empty() else []
		if not ways.is_empty():
			var tc: Vector2 = town["center"]
			# High enough to see over the trees along the road and the wall beyond.
			await _shot("01_medieval_town", tc + Vector2.from_angle(ways[0]) * 100.0, tc, 0.40, 18.0, float(town["target_h"]) + 4.0)
		else:
			await _shot("01_medieval_town", c + Vector2(44, 30), c, 0.40)
	var f := _find_era(g, Eras.FANTASY, 0.995)
	await _shot("02_fantasy_wildwood", f, f + Vector2(60, 30), 0.36)
	if not sci.is_empty():
		var c: Vector2 = sci["center"]
		var big := _find_settlement(g, Eras.SCIFI, 1) if g.outposts else {}
		if not big.is_empty():
			var bc: Vector2 = big["center"]
			var a := g.outpost_angle(big) + 0.6
			await _shot("03_scifi_outpost", bc + Vector2.from_angle(a) * 62.0, bc, 0.55, 14.0)
		else:
			await _shot("03_scifi_outpost", c + Vector2(-42, 38), c, 0.55, 2.5)
	if g.outposts and (only.is_empty() or only.has("11")):
		# The nearest stronghold, from outside its gate.
		var best := {}
		for r in 8:
			for cz in range(-r, r + 1):
				for cx in range(-r, r + 1):
					if best.is_empty() and maxi(absi(cx), absi(cz)) == r:
						best = Stronghold.at_cell(g, cx, cz)
		if not best.is_empty():
			var fc: Vector2 = best["center"]
			var out := Vector2(0, 46).rotated(-float(best["yaw"]))
			await _shot("11_stronghold", fc + out + out.orthogonal() * 0.5, fc, 0.45, 9.0)
	if g.outposts and (only.is_empty() or only.has("16")):
		# The nearest viaduct, from the side.
		var best_d := INF
		var vm := Vector2.ZERO
		var vd := Vector2.ZERO
		var deck := 0.0
		for rd in g.roads_near(-900.0, -900.0, 900.0, 900.0):
			var pts: PackedVector2Array = rd["pts"]
			var ar: PackedByteArray = rd["air"]
			var lv: PackedFloat32Array = rd["level"]
			for i in range(2, pts.size() - 2):
				if ar[i] == 1 and ar[i - 1] == 1 and ar[i + 1] == 1 and pts[i].length() < best_d:
					best_d = pts[i].length()
					vm = pts[i]
					vd = (pts[i + 1] - pts[i - 1]).normalized()
					deck = lv[i]
		if best_d < INF:
			# Stand on whichever side the ground falls away, level with the deck.
			var cam := vm + vd.orthogonal() * 48.0
			var low := INF
			for side in [-1.0, 1.0]:
				for dist in [40.0, 55.0, 70.0]:
					var c: Vector2 = vm + vd.orthogonal() * dist * side + vd * 14.0
					var h := g.field.height(c.x, c.y)
					if h < low:
						low = h
						cam = c
			await _shot("16_viaduct", cam, vm, 0.4, clampf(deck - low + 2.0, 2.0, 30.0), deck - 4.0)
	if g.outposts and (only.is_empty() or only.has("27") or only.has("28") or only.has("29") or only.has("33") or only.has("34")):
		await _room_shots(g)
	if only.is_empty() or only.has("30") or only.has("31") or only.has("32"):
		await _wonder_shots()
	if only.is_empty() or only.has("35") or only.has("36") or only.has("37") or only.has("38"):
		await _wonder_types()
	if g.landforms:
		await _landform_shots(g)
	var b := _find_border(g)
	await _shot("04_era_border", b + Vector2(-25, -25), b + Vector2(40, 40), 0.45, 6.0)
	if not fan.is_empty():
		var c: Vector2 = fan["center"]
		await _shot("05_fantasy_village_night", c + Vector2(40, -34), c, 0.93)
	if not med.is_empty():
		var c: Vector2 = med["center"]
		await _shot("06_medieval_sunset", c + Vector2(-50, 14), c, 0.735)
	var shore := _find_shore(g)
	if shore != Vector2.ZERO:
		await _shot("07_lake_day", shore, shore + shore.normalized() * 60.0, 0.42, 2.5)
	var rv := _find_river(ChunkGenerator.new(Game.seed, Game.store.has_rivers()))
	if rv != Vector4.ZERO:
		await _shot("08_river", Vector2(rv.x, rv.y), Vector2(rv.z, rv.w), 0.4, 7.0)
	if shore != Vector2.ZERO and (only.is_empty() or only.has("35") or only.has("36")):
		await _water_shots(g, shore)
	if only.is_empty() or only.has("09") or only.has("10"):
		await _vehicles()
	if only.is_empty() or only.has("11") or only.has("12"):
		await _starship()
	if only.is_empty() or only.has("13") or only.has("14") or only.has("15"):
		await _space()
		return
	Game.close_world()
	get_tree().quit()

## Inside walk-in rooms, from just within the door: an outpost block, the nearest
## stronghold's keep, and a mushroom house at night. Then up a stone tower's stairwell
## and out from its battlements over the courtyard.
func _room_shots(g: ChunkGenerator) -> void:
	var picks: Array = [] ## [name, type, centre, yaw, ground height, day]
	var sci := _find_settlement(g, Eras.SCIFI, 1)
	if not sci.is_empty():
		for it in g.settlement_layout(sci):
			if it["t"] in ["lab_block", "hab_block", "ops_tower"]:
				picks.append(["27_outpost_room", it["t"], it["p"], it["yaw"], float(sci["target_h"]), 0.45])
				break
	var fort := {}
	for r in 8:
		for cz in range(-r, r + 1):
			for cx in range(-r, r + 1):
				if fort.is_empty() and maxi(absi(cx), absi(cz)) == r:
					fort = Stronghold.at_cell(g, cx, cz)
	if not fort.is_empty():
		for it in Stronghold.layout(g, fort):
			if String(it["t"]).ends_with("_keep"):
				picks.append(["28_keep_hall", it["t"], it["p"], it["yaw"], float(fort["target_h"]), 0.45])
	var fan := _find_settlement(g, Eras.FANTASY)
	if not fan.is_empty():
		for it in g.settlement_layout(fan):
			if it["t"] == "mushroom_house":
				picks.append(["29_mushroom_night", it["t"], it["p"], it["yaw"], float(fan["target_h"]), 0.93])
				break
	for pk in picks:
		var t: String = pk[1]
		var c: Vector2 = pk[2]
		var yaw: float = pk[3]
		var fl := 0.2
		var cam := Vector2.ZERO
		var look := Vector2.ZERO
		if Interiors.BOX.has(t):
			var b: Array = Interiors.BOX[t]
			fl = b[1]
			cam = Vector2(float(b[5][0]), (b[0] as Vector2).y - 0.5)
			look = Vector2(float(b[5][0]) * 0.3 - 1.0, -(b[0] as Vector2).y)
		elif Interiors.ROUND.has(t):
			var p: Array = Interiors.ROUND[t]
			fl = p[5]
			cam = Vector2(0, float(p[0]) - float(p[2]) - 0.45)
			look = Vector2(-0.3, -2.0)
		var to_w := func(l: Vector2) -> Vector2: return c + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))
		await _shot(pk[0], to_w.call(cam), to_w.call(look), pk[5], fl - 0.1, float(pk[4]) + fl + 0.7)
	if fort.is_empty() or int(fort["era"]) == 2:
		return
	for it in Stronghold.layout(g, fort):
		if String(it["t"]).ends_with("_tower"):
			var c: Vector2 = it["p"]
			var yaw: float = it["yaw"]
			var gh: float = fort["target_h"]
			var b: Array = Interiors.BOX[it["t"]]
			var to_w := func(l: Vector2) -> Vector2: return c + Vector2(l.x * cos(yaw) + l.y * sin(yaw), -l.x * sin(yaw) + l.y * cos(yaw))
			await _shot("33_tower_stair", to_w.call(Vector2(1.6, 2.2)), to_w.call(Vector2(-3.0, -3.0)), 0.45, float(b[1]) - 0.1, gh + 7.0)
			await _shot("34_tower_roof", to_w.call(Vector2(-2.2, -0.6)), fort["center"], 0.45, float(b[4]) - 0.1, gh + 2.0)
			break

## v7 landforms, each from the heart of the nearest region that has it: towers and
## needles from the valley floor, holes (craters, gorges, sinkholes) from the rim.
const LANDFORM_SHOTS := {
	"17_karst": WorldField.LF_KARST, "18_needles": WorldField.LF_NEEDLES, "19_dunes": WorldField.LF_DUNES,
	"20_craters": WorldField.LF_CRATERS, "21_gorge": WorldField.LF_GORGE, "22_badlands": WorldField.LF_BADLANDS,
	"23_crags": WorldField.LF_CRAGS, "24_sinkholes": WorldField.LF_SINKHOLES, "25_lakes": WorldField.LF_LAKES,
	"26_terraces": WorldField.LF_TERRACES,
}

func _landform_shots(g: ChunkGenerator) -> void:
	for shot in LANDFORM_SHOTS:
		if not only.is_empty() and not only.has(String(shot).substr(0, 2)):
			continue
		var lf: int = LANDFORM_SHOTS[shot]
		var best := Vector2.INF
		for r in 14:
			for iz in range(-r, r + 1):
				for ix in range(-r, r + 1):
					if best != Vector2.INF or maxi(absi(ix), absi(iz)) != r:
						continue
					var p := g.field.site_pos(ix, iz)
					if g.field.site_landform(ix, iz) == lf and g.field.landform_weights(p.x, p.y)[lf] > 0.95:
						best = p
		if best == Vector2.INF:
			print("no region with landform ", lf)
			continue
		var looking_down := lf in [WorldField.LF_CRATERS, WorldField.LF_GORGE, WorldField.LF_SINKHOLES, WorldField.LF_LAKES, WorldField.LF_TERRACES]
		var cam := best
		var pick := INF if not looking_down else -INF
		for k in 12:
			var c := best + Vector2.from_angle(k * TAU / 12.0) * 70.0
			var h := g.field.height(c.x, c.y)
			if h < WATER_SAFE:
				continue
			if (h < pick) != looking_down:
				pick = h
				cam = c
		var tgt := g.field.height(best.x, best.y)
		await _shot(shot, cam, best, 0.42, 9.0 if looking_down else 2.5, tgt + (2.0 if looking_down else 14.0))

const WATER_SAFE := 1.0

## The nearest wonder by day and by night, then the atlas and minimap around it.
func _wonder_shots() -> void:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var ch := {}
	for r in 6:
		for wz in range(-r, r + 1):
			for wx in range(-r, r + 1):
				if not ch.is_empty() or maxi(absi(wx), absi(wz)) != r:
					continue
				var pick := WonderSite.cell_pick(g.seed, wx, wz)
				if pick.is_empty():
					continue
				var k: Vector2i = pick[0]
				var c := g.generate(k.x, k.y)
				if c.has("wonder"):
					ch = c
	if ch.is_empty():
		print("no wonder near the origin")
		return
	var w: Dictionary = ch["wonder"]
	var wc := Vector2(ch["cx"] * 64.0 + float(w["lx"]), ch["cz"] * 64.0 + float(w["lz"]))
	var yaw := 0.0
	for o in ch["objects"]:
		if o["t"] == w["t"]:
			yaw = o["r"]
	var front := Vector2(0, 1).rotated(-yaw)
	var cam := wc + front * 40.0 + front.orthogonal() * 14.0
	print("wonder ", w["t"], " at ", wc)
	await _shot("30_wonder", cam, wc, 0.42, 6.0, ChunkGenerator.height_at(ch, w["lx"], w["lz"]) + 8.0)
	await _shot("31_wonder_night", wc + front * 140.0, wc, 0.9, 12.0, ChunkGenerator.height_at(ch, w["lx"], w["lz"]) + 40.0)
	if only.is_empty() or only.has("32"):
		world.player.global_position = Vector3(wc.x + front.x * 60.0, world.player.global_position.y, wc.y + front.y * 60.0)
		await _wait(120)
		var mk := Game.markers.add("Dreadnought crash", wc.x + 30.0, wc.y + 20.0, Game.planet, "pin", {"icon": "danger", "color": 2})
		AtlasView.selected = int(mk["id"])
		world.menus.open("map")
		await _wait(30)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("32_atlas.png"))
		print("captured 32_atlas")
		world.menus.close()
		await _wait(5)

## The nearest wonder of each kind, close up by day: 35 throne, 36 worldroot,
## 37 dreadnought, 38 gate.
func _wonder_types() -> void:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var found := {}
	for r in 16:
		for wz in range(-r, r + 1):
			for wx in range(-r, r + 1):
				if found.size() == WonderSite.TYPES.size() or maxi(absi(wx), absi(wz)) != r:
					continue
				var pick := WonderSite.cell_pick(g.seed, wx, wz)
				if pick.is_empty():
					continue
				var k: Vector2i = pick[0]
				var c := g.generate(k.x, k.y)
				if c.has("wonder") and not found.has(c["wonder"]["t"]):
					found[c["wonder"]["t"]] = c
	for i in WonderSite.TYPES.size():
		var t: String = WonderSite.TYPES[i]
		if not found.has(t):
			print("no ", t, " found")
			continue
		var ch: Dictionary = found[t]
		var w: Dictionary = ch["wonder"]
		var wc := Vector2(ch["cx"] * 64.0 + float(w["lx"]), ch["cz"] * 64.0 + float(w["lz"]))
		var yaw := 0.0
		for o in ch["objects"]:
			if o["t"] == t:
				yaw = o["r"]
		var front := Vector2(0, 1).rotated(-yaw)
		var h := ChunkGenerator.height_at(ch, w["lx"], w["lz"])
		print("wonder ", t, " at ", wc)
		await _shot("%d_%s" % [35 + i, t], wc + front * 24.0 + front.orthogonal() * 8.0, wc, 0.4, 3.0, h + 6.0)

## A starship on its launch pad, then in flight over the land.
func _starship() -> void:
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	var vm: VehicleManager = world.vehicles
	if p.vehicle:
		p.dismount(true)
	var g0 := ChunkGenerator.new(Game.seed)
	var s2 := _find_era(g0, Eras.SCIFI, 0.9)
	var at := _flat_spot(vm, Vector3(s2.x, 0, s2.y))
	print("starship: pad at ", at)
	p.fly = true
	p.global_position = at + Vector3(0, 3, 0)
	await _wait_loaded(p, streamer)
	var pad := Vector3(at.x, vm.ground(at.x, at.z), at.z)
	_clear_around(streamer, pad, 26.0)
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(at))
	c.add_built("launch_pad", pad - c.position, 0.0, {"by": "you", "day": 0.0})
	var ship := vm.deploy(ItemDB.make("ship", 1, 1.0, {}), pad, 0.6)
	ship.global_position.y = pad.y + 0.6
	Game.day = 0.62
	var eye := pad + Vector3(12, 8, 14)
	var d := pad + Vector3(0, 1.5, 0) - eye
	p.set_state({"pos": eye, "yaw": atan2(-d.x, -d.z), "pitch": atan2(d.y, Vector2(d.x, d.z).length()), "slot": 0})
	await _wait(settle_frames)
	if only.is_empty() or only.has("11"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("11_starship.png"))
		print("captured 11_starship")
	p.fly = false
	p.mount(ship)
	if not p.third_person:
		p.toggle_view()
	p.set_state({"pos": p.global_position, "yaw": ship.rotation.y, "pitch": 0.25, "slot": 0, "view": 3})
	Input.action_press("jump")
	await _wait(60)
	Input.action_press("move_forward")
	await _wait(60)
	Input.action_release("jump")
	await _wait(40)
	Input.action_release("move_forward")
	# Hover while the land below streams in, then look down over the nose.
	await _wait_loaded(p, streamer)
	p.set_state({"pos": p.global_position, "yaw": ship.rotation.y, "pitch": -0.35, "slot": 0, "view": 3})
	Input.action_press("move_forward")
	await _wait(30)
	if only.is_empty() or only.has("12"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("12_flight.png"))
		print("captured 12_flight")
	Input.action_release("move_forward")

## Under the lake looking back up the shelf to the shore, and a splash just off the beach.
func _water_shots(g: ChunkGenerator, shore: Vector2) -> void:
	var out := shore.normalized()
	var deep := shore
	for k in 60:
		deep = shore + out * (k * 3.0)
		if g.field.height(deep.x, deep.y) < Water.LEVEL - 9.0:
			break
	var p: Player = world.player
	p.underwater = true
	await _shot("35_underwater", deep, shore, 0.45, 4.0, Water.LEVEL + 1.0)
	p.underwater = false
	var spot := shore + out * 9.0
	var burst := func() -> void:
		for i in 3:
			Splashes.splash(Vector3(spot.x, Water.surface_height(spot.x, spot.y, 0.0), spot.y), 1.2)
			Splashes.ring(Vector3(spot.x + 2.0, 0.0, spot.y + 1.0), 1.6)
			await _wait(4)
	await _shot("36_splash", shore - out * 2.0, spot, 0.42, 2.2, Water.LEVEL + 0.6, burst)

## Clears trees, rocks and ruins near `at` so a staged shot has a clear view.
func _clear_around(streamer: ChunkStreamer, at: Vector3, r: float) -> void:
	for k in streamer.chunks:
		var c: ChunkNode = streamer.chunks[k]
		for o in c.data["objects"]:
			if not o["st"].get("gone", false) and (c.position + o["p"]).distance_to(at) < r:
				c.remove_object(o["i"])

func _snap(name: String) -> void:
	if only.is_empty() or only.has(name.substr(0, 2)):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
		print("captured ", name)

## Up to orbit, warp to the fey moon, and land there.
func _space() -> void:
	var p: Player = world.player
	var vm: VehicleManager = world.vehicles
	if p.vehicle:
		p.dismount(true)
	p.set_physics_process(true)
	p.fly = false
	var ship := vm.deploy(ItemDB.make("ship", 1, 1.0, {}), p.global_position + Vector3(0, 0, -10), p.yaw())
	await _wait(10)
	p.mount(ship)
	ship.leaving = Vehicle.LEAVE_TIME
	ship.at_ceiling = true
	# The world (and this node's parent) goes away; keep the tour running from the root.
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	for i in 600:
		await tree.process_frame
		if tree.current_scene is OrbitView:
			break
	var orbit: OrbitView = tree.current_scene
	await _wait(settle_frames)
	await _snap("13_orbit")
	var fey := 1
	for pl in Game.worlds():
		if pl["kind"] == "fey":
			fey = pl["n"]
	# Slow time so the streaks are mid-flight when the (slow) software renderer shoots.
	Engine.time_scale = 0.05
	orbit._warp(fey)
	for i in 400:
		await tree.process_frame
		if float(orbit._warp_mat.get_shader_parameter("amount")) > 0.75:
			break
	await _snap("14_warp")
	Engine.time_scale = 1.0
	while orbit._busy:
		await tree.process_frame
	await _wait(30)
	orbit._land()
	for i in 600:
		await tree.process_frame
		if tree.current_scene != orbit and tree.current_scene != null and tree.current_scene.get("player") != null:
			break
	world = tree.current_scene
	p = world.player
	for i in 3000:
		await tree.process_frame
		if p.vehicle != null:
			break
	if not p.third_person:
		p.toggle_view()
	Input.action_press("crouch")
	await _wait(150)
	Input.action_release("crouch")
	p.dismount(true)
	# Look away from the parked ship, over the alien landscape.
	p.set_state({"pos": p.global_position + Vector3(0, 0, 6), "yaw": p.yaw() + 2.4, "pitch": -0.15, "slot": 0, "view": 3, "riding": -1})
	await _wait_loaded(p, world.streamer)
	Game.day = 0.42
	await _wait(settle_frames)
	await _snap("15_fey_moon")
	Game.close_world()
	get_tree().quit()

## The flattest dry 24 m square near `from` (for setting things out to photograph).
func _flat_spot(vm: VehicleManager, from: Vector3) -> Vector3:
	var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
	var best := from
	var best_s := INF
	for i in 400:
		var a := i * 0.61
		var q := Vector2(from.x, from.z) + Vector2(cos(a), sin(a)) * (i * 0.8)
		var lo := INF
		var hi := -INF
		var wet := false
		for dz in [-12.0, 0.0, 12.0]:
			for dx in [-12.0, 0.0, 12.0]:
				var h := g.field.height(q.x + dx, q.y + dz)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				if h < Water.LEVEL + 1.0 or g.field.river_t(q.x + dx, q.y + dz) < 3.0:
					wet = true
		if not wet and hi - lo < best_s:
			best_s = hi - lo
			best = Vector3(q.x, g.field.height(q.x, q.y) + 1.0, q.y)
	return best

## The vehicle bay and stable with a speeder, a rover and a horse in front, then riding.
func _vehicles() -> void:
	var p: Player = world.player
	var streamer: ChunkStreamer = world.streamer
	var g0 := ChunkGenerator.new(Game.seed)
	var m2 := _find_era(g0, Eras.MEDIEVAL, 0.95)
	var at := Vector3(m2.x, 0, m2.y)
	p.set_physics_process(false)
	p.global_position = at
	await _wait_loaded(p, streamer)
	var vm: VehicleManager = world.vehicles
	at = _flat_spot(vm, at)
	print("vehicles: showcase at ", at)
	p.global_position = at
	await _wait_loaded(p, streamer)
	print("vehicles: ground loaded")
	var c: ChunkNode = streamer.get_chunk(ChunkStreamer.chunk_of(at))
	var g := func(x: float, z: float) -> Vector3:
		return Vector3(x, vm.ground(x, z), z)
	var bay: Vector3 = g.call(at.x - 6, at.z - 10)
	c.add_built("vehicle_bay", bay - c.position, 0.0, {"by": "you", "day": 0.0})
	var st: Vector3 = g.call(at.x + 6, at.z - 10)
	c.add_built("stable", st - c.position, 0.0, {"by": "you", "day": 0.0})
	vm.deploy(ItemDB.make("speeder", 1, 1.0, {}), at + Vector3(-7.5, 0, -5), 0.5)
	vm.deploy(ItemDB.make("rover", 1, 1.0, {}), at + Vector3(-2, 0, -5), 0.2)
	vm.deploy(ItemDB.make("horse", 1, 1.0, {}), at + Vector3(5, 0, -5), -0.4)
	Game.day = 0.4
	p.set_physics_process(true)
	p.set_state({"pos": at + Vector3(0, 0.2, 7), "yaw": 0.0, "pitch": -0.22, "slot": 0})
	p.fly = true # hold the camera a little above the ground
	p.global_position.y += 2.5
	await _wait(settle_frames)
	if only.is_empty() or only.has("09"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("09_vehicles.png"))
		print("captured 09_vehicles")
	var sp: Vehicle = vm.all_nodes()[0]
	for v in vm.all_nodes():
		if v.kind == "speeder":
			sp = v
	p.fly = false
	p.mount(sp)
	if not p.third_person:
		p.toggle_view()
	Input.action_press("move_forward")
	await _wait(150)
	if only.is_empty() or only.has("10"):
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("10_riding.png"))
		print("captured 10_riding")
	Input.action_release("move_forward")

## The nearest cave network: its mouth from down the hill, the entry passage by torch,
## and its biggest chamber.
func _cave_shots(g: ChunkGenerator) -> void:
	var net := {}
	for r in 8:
		for sz in range(-r, r + 1):
			for sx in range(-r, r + 1):
				if net.is_empty() and maxi(absi(sx), absi(sz)) == r:
					net = Caves.network(g, sx, sz)
	if net.is_empty():
		print("no cave network found")
		return
	var mo: Vector3 = net["mouth"]
	var up: Vector2 = net["dir"]
	var m2 := Vector2(mo.x, mo.z)
	print("cave mouth at ", mo)
	await _shot("40_cave_mouth", m2 - up * 13.0 + up.orthogonal() * 3.0, m2 + up * 3.0, 0.42, 1.8, mo.y + 1.0)
	var ps := Caves.prims_near(g, mo.x - 200.0, mo.z - 200.0, mo.x + 200.0, mo.z + 200.0)
	var e := m2 + up * 9.0
	var ey := _cave_floor(ps, e, mo.y + 3.0)
	if not is_nan(ey):
		var deep := m2 + up * 30.0
		await _abs_shot("41_cave_entry", Vector3(e.x, ey + 1.7, e.y), Vector3(deep.x, ey - 3.0, deep.y), 0.42, true)
	var best := {}
	for ch in net["chambers"]:
		if best.is_empty() or float(ch["rx"]) > float(best["rx"]):
			best = ch
	var cc: Vector3 = best["p"]
	var at := Vector2(cc.x, cc.z) - up * float(best["rx"]) * 0.55
	var ay := _cave_floor(ps, at, cc.y)
	if is_nan(ay):
		at = Vector2(cc.x, cc.z)
		ay = _cave_floor(ps, at, cc.y)
	if not is_nan(ay):
		await _abs_shot("42_cave_chamber", Vector3(at.x, ay + 1.7, at.y), Vector3(cc.x, cc.y - 1.0, cc.z) + Vector3(up.x, 0, up.y) * 6.0, 0.42, true)

func _cave_floor(ps: PackedFloat32Array, p: Vector2, top: float) -> float:
	var y := top
	while y > top - 20.0:
		if Caves.sdf(ps, Vector3(p.x, y, p.y)) < -0.6:
			return Caves.floor_below(ps, Vector3(p.x, y, p.y), 20.0)
		y -= 0.25
	return NAN

func _abs_shot(name: String, at: Vector3, look: Vector3, day: float, torch: bool) -> void:
	if not only.is_empty() and not only.has(name.substr(0, 2)):
		return
	var p: Player = world.player
	Game.day = day
	p.set_physics_process(false)
	p.global_position = at
	await _wait_loaded(p, world.streamer)
	var d := look - at
	p.set_state({"pos": at, "yaw": atan2(-d.x, -d.z), "pitch": clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5), "slot": 9})
	if torch:
		p.hand_light.from_data({"kind": "torch", "torch_left": 300.0})
	world.atmosphere._target_w = world.atmosphere.field.era_weights(at.x, at.z)
	world.atmosphere._w = world.atmosphere._target_w.duplicate()
	await _wait(settle_frames)
	world.atmosphere.underground = world.atmosphere._under_target
	await _wait(20)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name, " at ", at, " underground ", world.atmosphere.underground)
	if torch:
		p.hand_light.from_data({"kind": "", "torch_left": 0.0})
