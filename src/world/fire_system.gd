class_name FireSystem
extends Node3D
## Fires in the world (plans/fire-system.md): what is burning, how it spreads, what it
## looks and sounds like, and what is left when it burns out. How a single thing burns
## is FireSim's; this runs them all.
##
## - State lives in each object's persisted `st` (FireSim), so a fire left burning is
##   still burning (or has burnt out) when its chunk loads again: the chunk catches up on
##   the time it was away.
## - Each tick every fire burns on; a fire well alight throws flame at what stands
##   close, much further downwind (Atmosphere's one wind), and rain beats it down.
## - What burns out falls in: timber buildings and wooden things go to a bed of ash and
##   charred beams (FireRuins), brick houses to broken walls and rubble, trees to a burnt
##   trunk. Collapse throws real falling beams, dust and sparks.
## - Online, the player who runs a chunk's animals runs its fires (Net.holds); the state
##   goes out with the chunk on events and every WRITE_EVERY seconds; others draw it.
## - Bounded: MAX_BURNING fires at once, flames and light only for the nearest, smoke
##   alone from far off.

static var current: FireSystem ## the world's, for players, weapons and the console

var streamer: ChunkStreamer
var atmosphere: Atmosphere
var player: Player

const TICK := 0.25
const SPREAD_EVERY := 2.0
const WRITE_EVERY := 8.0 ## offline: how often a burning chunk is saved
const WRITE_EVERY_ONLINE := 20.0
const MAX_BURNING := 48
## By the fire_fx setting (Low, Normal, High): fires drawn with flames (nearest first),
## lit, and lit with shadows, and the smoke particles over each.
const QUALITY := [
	{"flames": 6, "lights": 2, "shadows": 0, "smoke": 36},
	{"flames": 14, "lights": 4, "shadows": 1, "smoke": 72},
	{"flames": 22, "lights": 6, "shadows": 2, "smoke": 110},
]
static var quality := 1
const SOUNDS := 4
const FLAME_RANGE := 260.0
const SMOKE_RANGE := 1100.0
const RUIN_SMOKE := 240.0 ## seconds a burnt-out ruin smokes
const MAX_BEAMS := 24

## Rain to burn in, overriding the weather (console `fire rain`), or below 0 for the sky's.
var rain_override := -1.0

## key "cx,cz,i" -> {k, i, t, box (world AABB), vis, lvl, spread_t, write_t}
var _burning: Dictionary = {}
## Ruins still smoking: key -> {k, i, box, vis}
var _smoking: Dictionary = {}
## Per chunk: {data, n, list: [[i, AABB]]}, what in it can burn, for spreading.
var _flammable: Dictionary = {}
var _rebuild: Dictionary = {} ## chunk key -> true: its scorched look needs drawing again
var _tick := 0.0
var _rank_t := 0.0
var _beams: Array = [] ## [RigidBody3D, age]
var _grounds: Array = [] ## burning oil on bare ground: [Vis, life, radius, by]
var _torch := {"key": "", "t": 0.0}

func _ready() -> void:
	current = self
	add_to_group("fire")
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	if streamer != null:
		streamer.chunk_ready.connect(_on_chunk)

func _exit_tree() -> void:
	if current == self:
		current = null

static func now() -> float:
	return Time.get_unix_time_from_system()

static func key_of(k: Vector2i, i: int) -> String:
	return "%d,%d,%d" % [k.x, k.y, i]

## The weather fires burn in here (Weather when it is in the game, read by name so this
## works with or without it).
func env() -> Dictionary:
	var e := FireSim.calm()
	if atmosphere != null:
		e["wind"] = atmosphere.wind_strength
		e["wind_dir"] = atmosphere.wind_dir
		var w = atmosphere.get("weather")
		if w is Object and is_instance_valid(w):
			var precip := float(w.get("precip")) if w.get("precip") != null else 0.0
			var snow := float(w.get("snow")) if w.get("snow") != null else 0.0
			e["rain"] = precip * (1.0 - snow)
			e["snow"] = precip * snow
			e["wet"] = float(w.get("wet")) if w.get("wet") != null else 0.0
	if rain_override >= 0.0:
		e["rain"] = rain_override
		e["wet"] = maxf(float(e["wet"]), rain_override * 0.7)
	return e

## Whether this game runs the fires of chunk k (always offline; online, the holder).
func _runs(k: Vector2i) -> bool:
	if not Net.is_client():
		return true
	var h = Net.holders.get("f:%d:%d:%d" % [Game.planet, k.x, k.y])
	return h == null or int(h[0]) == multiplayer.get_unique_id()

func burning_count() -> int:
	return _burning.size()

func is_burning(k: Vector2i, i: int) -> bool:
	return _burning.has(key_of(k, i))

# --- Boxes ---------------------------------------------------------------------------

## An object's box in the world, from its mesh.
static func world_box(node: ChunkNode, o: Dictionary) -> AABB:
	var a := ObjectLibrary.get_mesh(ObjectLibrary.mesh_key(o)).get_aabb() if not Doors.is_door(o["t"]) else AABB(Vector3(-0.6, 0, -0.1), Vector3(1.2, 2.3, 0.2))
	var s: float = o.get("s", 1.0)
	var xf := Transform3D(Basis(Vector3.UP, float(o["r"])).scaled(Vector3.ONE * s), node.position + (o["p"] as Vector3))
	return xf * a

## Metres between two boxes (0 where they touch or overlap).
static func gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector3(dx, dy, dz).length()

## What can burn in chunk node, with boxes, cached until the chunk's objects change.
func _flammables(node: ChunkNode) -> Array:
	var c = _flammable.get(node.key)
	var objs: Array = node.data["objects"]
	if c is Dictionary and is_same(c["data"], node.data) and int(c["n"]) == objs.size():
		return c["list"]
	var list: Array = []
	for o in objs:
		if o["st"].get("gone", false) or not FireSim.burns(o["t"]):
			continue
		list.append([int(o["i"]), world_box(node, o)])
	_flammable[node.key] = {"data": node.data, "n": objs.size(), "list": list}
	return list

## Burnable objects whose boxes come within `reach` of box: [[node, i, box], ...].
func near(box: AABB, reach: float) -> Array:
	var out: Array = []
	if streamer == null:
		return out
	var grown := box.grow(reach)
	var c0 := ChunkStreamer.chunk_of(grown.position)
	var c1 := ChunkStreamer.chunk_of(grown.end)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var node := streamer.get_chunk(Vector2i(cx, cz))
			if node == null:
				continue
			for e in _flammables(node):
				if (e[1] as AABB).intersects(grown):
					out.append([node, e[0], e[1]])
	return out

# --- Starting fires --------------------------------------------------------------------

## Sets object i of chunk node alight with a flame of `strength` (see FireSim.catch_chance;
## `sure` skips the roll). `oil` pours that many seconds of oil on first. Returns true
## if it caught.
func ignite(node: ChunkNode, i: int, strength: float, by_player := false, sure := false, oil := 0.0) -> bool:
	if node == null or i < 0 or i >= (node.data["objects"] as Array).size():
		return false
	var o: Dictionary = node.get_object(i)
	var st: Dictionary = o["st"]
	var t: String = o["t"]
	if st.get("gone", false):
		return false
	if oil > 0.0 and FireSim.burns(t):
		FireSim.feed(st, oil)
	if st.has("fire"):
		# Already burning: more fire on it makes it fiercer.
		var f: Dictionary = st["fire"]
		f["h"] = minf(1.0, float(f.get("h", 0.0)) + strength * 0.12)
		_register(node, o)
		return true
	if not FireSim.burns(t):
		# Stone and metal: the oil burns off and leaves it scorched.
		if oil > 0.0 or strength >= 0.8:
			var before := FireSim.char_step(st)
			FireSim.scorch(st, 0.3 * strength)
			if FireSim.char_step(st) != before:
				_rebuild[node.key] = true
			Game.mark_chunk_dirty(node.data)
		return false
	if _burning.size() >= MAX_BURNING:
		return false
	var chance := FireSim.catch_chance(t, st, strength, env(), now())
	if not sure and randf() >= chance:
		if oil > 0.0:
			Game.mark_chunk_dirty(node.data)
		return false
	if not FireSim.ignite(t, st, strength, now(), by_player):
		return false
	_register(node, o)
	Game.mark_chunk_dirty(node.data)
	var wp: Vector3 = node.position + (o["p"] as Vector3)
	Audio.play_at("fire/catch", wp, -4.0)
	if by_player:
		_arson(node, o, wp)
	return true

## Fire landing at a point (a fire bottle's burst, a flamethrower's tongue, a burning
## arrow, a powder blast): sets what is within `radius` alight, each by its own chance;
## with `oil`, burning oil splashes round and burns on bare ground for a while.
func ignite_at(at: Vector3, radius: float, strength: float, by_player := true, oil := 0.0) -> int:
	var lit := 0
	var box := AABB(at - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var touched := {}
	for e in near(box, 0.0):
		var node: ChunkNode = e[0]
		var k := key_of(node.key, int(e[1]))
		if touched.has(k):
			continue
		touched[k] = true
		var falloff := 1.0 - clampf(gap(e[2], AABB(at, Vector3.ZERO)) / maxf(radius, 0.1), 0.0, 1.0) * 0.6
		if ignite(node, int(e[1]), strength * falloff, by_player, false, oil * falloff):
			lit += 1
	if oil > 0.0:
		# Burning oil on the ground round where it burst (and under what it lit).
		_ground_fire(at, radius, oil, by_player)
	return lit

## The fire a powder blast may start (dynamite, kegs, grenades): less sure than oil.
func blast(at: Vector3, radius: float) -> void:
	ignite_at(at, radius * 0.6, 0.55, true, 0.0)

func _apply_settings() -> void:
	var q := clampi(int(Settings.get_value("fire_fx")), 0, QUALITY.size() - 1)
	if q != quality:
		quality = q
		_rank_t = 0.0 # re-rank, so the change shows at once

func _register(node: ChunkNode, o: Dictionary) -> void:
	var k := key_of(node.key, int(o["i"]))
	if _burning.has(k):
		return
	_burning[k] = {"k": node.key, "i": int(o["i"]), "t": String(o["t"]), "box": world_box(node, o), "vis": null,
		"lvl": FireSim.char_step(o["st"]), "spread_t": randf() * SPREAD_EVERY, "write_t": 0.0, "data": node.data}
	_rank_t = 0.0

## Setting fire to what belongs to a town is arson, if anyone sees.
func _arson(node: ChunkNode, o: Dictionary, wp: Vector3) -> void:
	if player == null or player.npcs == null:
		return
	var kind := ObjectLibrary.kind(o["t"])
	if kind == "built" and Player.is_own_piece(o):
		return
	if Game.may_use_house_at(wp):
		return
	if kind in ["structure", "trader", "built", "cache"]:
		player.npcs.report_crime(wp, "arson", 0, ObjectLibrary.label_of(o).to_lower())

# --- Chunks coming and going -------------------------------------------------------------

## A chunk was loaded or swapped for a newer copy: take up its fires (catching up on the
## time it was away) and its smoking ruins.
func _on_chunk(node: ChunkNode) -> void:
	_flammable.erase(node.key)
	var t := now()
	var e := env()
	var objs: Array = node.data["objects"]
	for idx in objs.size():
		var o: Dictionary = objs[idx]
		var st: Dictionary = o["st"]
		if st.get("gone", false):
			continue
		if st.has("fire"):
			var away := t - float((st["fire"] as Dictionary).get("w", t))
			if away > 5.0 and _runs(node.key):
				var r := FireSim.catch_up(o["t"], st, away, e, t)
				if r == "burnt":
					_burn_down(node, o, false)
					continue
				Game.mark_chunk_dirty(node.data)
			if st.has("fire"):
				_register(node, o)
		elif float(st.get("smoke", 0.0)) > t:
			var k := key_of(node.key, idx)
			if not _smoking.has(k):
				_smoking[k] = {"k": node.key, "i": idx, "box": world_box(node, o), "vis": null}

# --- Running ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick += delta
	_rank_t -= delta
	_update_beams(delta)
	_update_grounds(delta)
	if _tick < TICK:
		return
	var dt := _tick
	_tick = 0.0
	var e := env()
	var t := now()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	for key in _burning.keys():
		_burn_one(key, dt, e, t, eye)
	for key in _smoking.keys():
		_smoke_one(key, t, eye)
	if _rank_t <= 0.0:
		_rank_t = 1.0
		_rank(eye, e)
		_scare_animals()
	# One chunk a tick redraws its scorched look.
	for k in _rebuild.keys():
		_rebuild.erase(k)
		var node := streamer.get_chunk(k) if streamer != null else null
		if node != null:
			node.set_objects(ChunkNode.build_object_buffers(node.data, false), true)
		break
	_hurt_player(dt)

func _burn_one(key: String, dt: float, e: Dictionary, t: float, eye: Vector3) -> void:
	var b: Dictionary = _burning[key]
	var node := streamer.get_chunk(b["k"]) if streamer != null else null
	if node == null or int(b["i"]) >= (node.data["objects"] as Array).size():
		# Walked away from: what it burnt to so far is kept, and it catches up when the
		# chunk comes back.
		if _runs(b["k"]):
			Game.mark_chunk_dirty(b["data"])
		_drop(key)
		return
	var o: Dictionary = node.get_object(b["i"])
	var st: Dictionary = o["st"]
	if st.get("gone", false) or not st.has("fire"):
		_drop(key)
		return
	var runs := _runs(node.key)
	var r := FireSim.step(o["t"], st, dt, e, t)
	if st.has("fire"):
		(st["fire"] as Dictionary)["w"] = snappedf(t, 0.1)
	var lvl := FireSim.char_step(st)
	if lvl != float(b["lvl"]):
		b["lvl"] = lvl
		_rebuild[node.key] = true
	if r == "burnt" and runs:
		_burn_down(node, o, true)
		_drop(key)
		return
	if r != "":
		if runs:
			Game.mark_chunk_dirty(node.data)
		if r == "out":
			Audio.play_at("fire/hiss", (b["box"] as AABB).get_center(), -6.0)
		_drop(key)
		return
	if not runs:
		_show(b, st)
		return
	var h := FireSim.heat(st)
	b["spread_t"] = float(b["spread_t"]) - dt
	if float(b["spread_t"]) <= 0.0:
		b["spread_t"] = SPREAD_EVERY
		_spread(node, o, b, h, e, t)
	b["write_t"] = float(b["write_t"]) - dt
	if float(b["write_t"]) <= 0.0:
		b["write_t"] = WRITE_EVERY_ONLINE if Net.is_client() else WRITE_EVERY
		Game.mark_chunk_dirty(node.data)
	_show(b, st)

## Throws flame from one fire at what stands round it.
func _spread(node: ChunkNode, o: Dictionary, b: Dictionary, h: float, e: Dictionary, t: float) -> void:
	if h < 0.35 or _burning.size() >= MAX_BURNING:
		return
	var box: AABB = b["box"]
	var reach := (0.8 + 3.2 * h) * clampf(box.size.y / 5.0, 0.6, 2.0) * (1.0 + 2.2 * float(e.get("wind", 0.3)))
	var by := int((o["st"]["fire"] as Dictionary).get("by", 0)) == 1
	var c := box.get_center()
	for n in near(box, reach):
		var nn: ChunkNode = n[0]
		var ni: int = n[1]
		if nn == node and ni == int(o["i"]):
			continue
		var other: Dictionary = nn.get_object(ni)
		if other["st"].has("fire"):
			continue
		var ob: AABB = n[2]
		var along := Vector2(ob.get_center().x - c.x, ob.get_center().z - c.z)
		along = along.normalized() if along.length() > 0.01 else Vector2.ZERO
		var rate := FireSim.spread_rate(h, gap(box, ob), along, box.size.y, other["t"], other["st"], e, t)
		if rate > 0.0 and randf() < rate * SPREAD_EVERY:
			if ignite(nn, ni, 0.8, false, true):
				if by:
					(other["st"]["fire"] as Dictionary)["by"] = 1
				# Sparks carried across on the wind.
				_spark_burst(ob.get_center() + Vector3(0, ob.size.y * 0.3, 0), 0.6)

func _drop(key: String) -> void:
	var b: Dictionary = _burning.get(key, {})
	_burning.erase(key)
	if b.get("vis") != null and is_instance_valid(b["vis"]):
		(b["vis"] as FireVis).die()
	_rank_t = 0.0

func _smoke_one(key: String, t: float, eye: Vector3) -> void:
	var s: Dictionary = _smoking[key]
	var node := streamer.get_chunk(s["k"]) if streamer != null else null
	var o: Dictionary = node.get_object(s["i"]) if node != null and int(s["i"]) < (node.data["objects"] as Array).size() else {}
	var left := float(o["st"].get("smoke", 0.0)) - t if not o.is_empty() else 0.0
	if o.is_empty() or o["st"].get("gone", false) or left <= 0.0:
		if s.get("vis") != null and is_instance_valid(s["vis"]):
			(s["vis"] as FireVis).die()
		_smoking.erase(key)
		return
	if s.get("vis") == null and (s["box"] as AABB).get_center().distance_to(eye) < SMOKE_RANGE:
		var v := FireVis.new()
		add_child(v)
		v.setup(s["box"], true)
		s["vis"] = v
	if s.get("vis") != null:
		# A thin smoke that thins away over its last minutes.
		(s["vis"] as FireVis).set_heat(0.0, clampf(left / RUIN_SMOKE, 0.0, 1.0) * 0.6 + 0.1, env())

## Brings the drawing of one fire up to its state.
func _show(b: Dictionary, st: Dictionary) -> void:
	var v = b.get("vis")
	if v == null or not is_instance_valid(v):
		return
	(v as FireVis).set_heat(FireSim.heat(st), 0.0, env())

## Every second: who gets flames, light and sound (the nearest), who only smoke.
func _rank(eye: Vector3, e: Dictionary) -> void:
	var order: Array = []
	for key in _burning:
		var b: Dictionary = _burning[key]
		order.append([(b["box"] as AABB).get_center().distance_to(eye), key])
	order.sort_custom(func(a, c): return a[0] < c[0])
	var n := 0
	for pair in order:
		var b: Dictionary = _burning[pair[1]]
		var d: float = pair[0]
		var v = b.get("vis")
		if d > SMOKE_RANGE:
			if v != null and is_instance_valid(v):
				(v as FireVis).die()
			b["vis"] = null
			continue
		if v == null or not is_instance_valid(v):
			var nv := FireVis.new()
			add_child(nv)
			var tree := ObjectLibrary.kind(b["t"]) == "tree"
			nv.setup(b["box"], false, tree, false, {} if tree else _spots_of(b))
			b["vis"] = nv
			v = nv
		var fv := v as FireVis
		var q: Dictionary = QUALITY[quality]
		fv.set_lod(n < int(q["flames"]) and d < FLAME_RANGE, n < int(q["lights"]) and d < 90.0, n < int(q["shadows"]) and d < 40.0, n < SOUNDS and d < 70.0, d)
		n += 1

# --- Where the flames stand ---------------------------------------------------------------

static var _spot_cache: Dictionary = {}

## Where flames can stand on a burning thing, in the world: up through its roof and out of
## its walls, on its own surfaces rather than on the box round it (a house turned on its
## plot, or a roof that overhangs, has corners of that box out in the air).
func _spots_of(b: Dictionary) -> Dictionary:
	var node: ChunkNode = streamer.get_chunk(b["k"]) if streamer != null else null
	if node == null:
		return {}
	var o: Dictionary = node.get_object(int(b["i"]))
	if o.is_empty():
		return {}
	var key := ObjectLibrary.mesh_key(o)
	var local: Dictionary = surface_spots(ObjectLibrary.get_mesh(key), key)
	if local.is_empty():
		return {}
	var xf := Transform3D(Basis(Vector3.UP, float(o["r"])).scaled(Vector3.ONE * float(o.get("s", 1.0))), node.position + (o["p"] as Vector3))
	var roof: Array = []
	for q in local["roof"]:
		roof.append(xf * (q as Vector3))
	var wall: Array = []
	for w in local["wall"]:
		wall.append([xf * (w[0] as Vector3), (xf.basis * (w[1] as Vector3)).normalized()])
	return {"roof": roof, "wall": wall}

## Flame spots on a mesh, in its own space: the highest upward faces (the roof, never a
## floor under it), one per 0.75 m cell, and the outermost wall faces at window height, one
## per slice of the compass round it, each with its outward normal. Cached per mesh.
static func surface_spots(mesh: Mesh, key: String) -> Dictionary:
	if _spot_cache.has(key):
		return _spot_cache[key]
	var out := {}
	if mesh != null:
		var faces := mesh.get_faces()
		var aabb := mesh.get_aabb()
		var c := aabb.get_center()
		var y0 := aabb.position.y
		var h := maxf(aabb.size.y, 0.1)
		const CELL := 0.75
		const SLICES := 24
		var top := {} # cell -> highest y of anything there
		var up := {} # cell -> highest upward-facing point there
		var side := {} # slice -> [distance out, point, normal]
		for t in range(0, faces.size() - 2, 3):
			var a := faces[t]
			var n := (faces[t + 1] - a).cross(faces[t + 2] - a)
			var area := n.length() * 0.5
			if area < 0.005:
				continue
			n /= area * 2.0
			var m := (a + faces[t + 1] + faces[t + 2]) / 3.0
			var cell := Vector2i(floori(m.x / CELL), floori(m.z / CELL))
			var hi := maxf(a.y, maxf(faces[t + 1].y, faces[t + 2].y))
			top[cell] = maxf(float(top.get(cell, -INF)), hi)
			if n.y > 0.35 and m.y > y0 + h * 0.3 and (not up.has(cell) or (up[cell] as Vector3).y < m.y):
				up[cell] = m
			elif absf(n.y) < 0.3 and m.y > y0 + h * 0.15 and m.y < y0 + h * 0.6:
				var d := Vector2(m.x - c.x, m.z - c.z)
				if d.length() < 0.2 or Vector2(n.x, n.z).normalized().dot(d.normalized()) < 0.3:
					continue
				var sl := int(fposmod(d.angle(), TAU) / TAU * SLICES) % SLICES
				if not side.has(sl) or float(side[sl][0]) < d.length():
					side[sl] = [d.length(), m, Vector3(n.x, 0.0, n.z).normalized()]
		var roof: Array = []
		for cell in up:
			var p: Vector3 = up[cell]
			if p.y >= float(top[cell]) - 0.35:
				roof.append(p)
		var wall: Array = []
		for sl in side:
			wall.append([side[sl][1], side[sl][2]])
		if not roof.is_empty() or not wall.is_empty():
			out = {"roof": roof, "wall": wall}
	_spot_cache[key] = out
	return out

# --- Burning down ------------------------------------------------------------------------

## Nothing left to burn: it falls in. `seen` plays the collapse (not when catching up on
## a chunk that was away).
func _burn_down(node: ChunkNode, o: Dictionary, seen: bool) -> void:
	var t: String = o["t"]
	var prof := FireSim.profile(t)
	var leaves: String = prof["leaves"]
	var lp: Vector3 = o["p"]
	var yaw: float = o["r"]
	var era: int = o.get("e", -1)
	var s: float = o.get("s", 1.0)
	var box := world_box(node, o)
	var wp := node.position + lp
	var mesh_key := ObjectLibrary.mesh_key(o)
	var foot := ObjectLibrary.footprint(o) if not Doors.is_door(t) else Rect2(-0.6, -0.1, 1.2, 0.2)
	var by: bool = int((o["st"].get("fire", {}) as Dictionary).get("by", 0)) == 1 or int(o["st"].get("lit_by", 0)) == 1
	var label := ObjectLibrary.label_of(o)
	var kind := ObjectLibrary.kind(t)
	# What was inside burnt with it.
	o["st"]["loot"] = []
	o["st"].erase("items")
	if kind == "built" and BuildCatalog.def(BuildCatalog.id_of(t)).has("teleporter"):
		Game.markers.remove_object(node.key, o["i"])
	if kind == "built" and not Doors.fits(BuildCatalog.id_of(t)).is_empty():
		var hit := Doors.door_at(streamer, wp)
		if not hit.is_empty():
			(hit["chunk"] as ChunkNode).remove_object(hit["obj"]["i"])
	node.remove_object(o["i"])
	ImpactFx.clear_near(wp, 3.0 * s)
	match leaves:
		"tree":
			node.add_object(WonderSite.TRUNK, lp, yaw, era, {"char": 1.0, "fl": 0.0, "smoke": snappedf(now() + 90.0, 0.1)},
				{"sp": 1 + randi() % 60, "v": 1 if t == "pine" else 0, "s": s})
		"timber", "masonry", "shell", "ash":
			var c := foot.get_center() * s
			var at := lp + Vector3(c.x, 0, c.y).rotated(Vector3.UP, yaw)
			var w := maxf(foot.size.x * s, 0.8)
			var d := maxf(foot.size.y * s, 0.8)
			node.add_object(FireSim.RUIN, at, yaw, era, {"smoke": snappedf(now() + RUIN_SMOKE * (1.0 if leaves != "ash" else 0.4), 0.1)},
				{"sp": FireRuins.encode(w, d, randi()), "v": FireRuins.variant(leaves, box.size.y)})
	_flammable.erase(node.key)
	_on_chunk(node) # take up the new ruin's smoke
	if by and player != null and player.npcs != null and kind in ["structure", "trader"]:
		player.npcs.player_vandalised(wp, label)
	if seen:
		_collapse(box, mesh_key, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), wp), leaves)

## The fall: the burnt shell sinks and tips over in its own dust, beams tumble out of it,
## sparks go up.
func _collapse(box: AABB, mesh_key: String, xf: Transform3D, leaves: String) -> void:
	var eye := get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() != null else box.get_center()
	if box.get_center().distance_to(eye) > 400.0:
		return
	var big := box.size.y > 3.0
	Audio.play_at("fire/collapse" if big else "hit/heavy", box.get_center(), 6.0 if big else 0.0)
	var mesh := ObjectLibrary.get_mesh(mesh_key)
	if mesh != null and leaves != "tree":
		var ghost := MeshInstance3D.new()
		ghost.mesh = mesh
		ghost.material_overlay = ChunkNode.soot_material()
		ghost.set_instance_shader_parameter("soot", 1.0)
		add_child(ghost)
		ghost.global_transform = xf
		var tip := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if atmosphere != null:
			tip = Vector3(atmosphere.wind_dir.x, 0, atmosphere.wind_dir.y).cross(Vector3.UP).normalized()
		var to := xf.rotated_local(tip, deg_to_rad(randf_range(6.0, 14.0)))
		to = Transform3D(to.basis.scaled(Vector3(1.0, 0.18, 1.0)), xf.origin - Vector3(0, box.size.y * 0.05, 0))
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "global_transform", to, 2.4 if big else 1.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(ghost.queue_free)
	# Beams falling out of it.
	var n := clampi(int(box.size.x * box.size.z / 18.0), 2, 8) if leaves != "tree" else 2
	for i in n:
		if _beams.size() >= MAX_BEAMS:
			var old: Array = _beams.pop_front()
			if is_instance_valid(old[0]):
				old[0].queue_free()
		var at := Vector3(randf_range(box.position.x, box.end.x), lerpf(box.position.y, box.end.y, randf_range(0.5, 0.9)), randf_range(box.position.z, box.end.z))
		_beams.append([_beam(at, randf_range(1.5, maxf(2.0, minf(box.size.x, box.size.z) * 0.8)), i < 2), 0.0])
	# Dust and ash billow out; sparks fly.
	var dust := FireVis.new()
	add_child(dust)
	dust.burst(box)
	_spark_burst(box.get_center() + Vector3(0, box.size.y * 0.2, 0), clampf(box.size.y / 3.0, 0.6, 3.0))

## A charred beam, falling.
func _beam(at: Vector3, length: float, lit: bool) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1 | 2
	rb.mass = 30.0 * length
	var th := randf_range(0.16, 0.24)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(th, th * 1.2, length)
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = Materials.get_mat("timber")
	mi.material_overlay = ChunkNode.soot_material()
	mi.set_instance_shader_parameter("soot", 0.9)
	rb.add_child(mi)
	if lit:
		var f := FireFx.flame(0.55)
		f.name = "Flame"
		rb.add_child(f)
		var tw := f.create_tween()
		tw.tween_interval(randf_range(6.0, 12.0))
		tw.tween_property(f, "scale", Vector3.ONE * 0.05, 3.0)
		tw.tween_callback(f.queue_free)
	add_child(rb)
	rb.global_position = at
	rb.rotation = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6))
	rb.linear_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(0.0, 2.0), randf_range(-2.0, 2.0))
	rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	return rb

## Fallen beams lie a while (until you walk off or a minute and a half has gone), then
## crumble to ash: the ruin keeps its own beams for good.
func _update_beams(delta: float) -> void:
	var eye := player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
	for i in range(_beams.size() - 1, -1, -1):
		var e: Array = _beams[i]
		var rb: RigidBody3D = e[0]
		if not is_instance_valid(rb):
			_beams.remove_at(i)
			continue
		e[1] = float(e[1]) + delta
		if float(e[1]) > 8.0 and not rb.freeze:
			rb.freeze = true
		if float(e[1]) > 90.0 or rb.global_position.distance_to(eye) > 160.0:
			var tw := rb.create_tween()
			tw.tween_property(rb, "scale", Vector3(1, 0.05, 1), 2.0)
			tw.tween_callback(rb.queue_free)
			_beams.remove_at(i)

func _spark_burst(at: Vector3, size: float) -> void:
	var em := FireFx.embers(size, false)
	add_child(em)
	em.global_position = at
	for c in em.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).one_shot = true
			(c as CPUParticles3D).explosiveness = 0.8
			(c as CPUParticles3D).emitting = true
	var tw := em.create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(em.queue_free)

# --- Oil burning on the ground -----------------------------------------------------------

func _ground_fire(at: Vector3, radius: float, oil: float, by_player: bool) -> void:
	if _grounds.size() >= 8:
		var old: Array = _grounds.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as FireVis).die()
	var v := FireVis.new()
	add_child(v)
	var r := clampf(radius * 0.7, 0.6, 3.0)
	v.setup(AABB(at - Vector3(r, 0.05, r), Vector3(r * 2.0, 0.3, r * 2.0)), false, false, true)
	v.set_lod(true, _grounds.size() < 2, false, _grounds.size() < 2, 0.0)
	_grounds.append([v, clampf(oil * 0.35, 6.0, 16.0), r, by_player])
	Audio.play_at("fire/catch", at, 0.0)

func _update_grounds(delta: float) -> void:
	var e := env()
	for i in range(_grounds.size() - 1, -1, -1):
		var g: Array = _grounds[i]
		if not is_instance_valid(g[0]):
			_grounds.remove_at(i)
			continue
		g[1] = float(g[1]) - delta * (1.0 + float(e["rain"]) * 3.0)
		var v: FireVis = g[0]
		v.set_heat(clampf(float(g[1]) / 6.0, 0.0, 1.0) * 0.8, 0.0, e)
		if float(g[1]) <= 0.0:
			v.die()
			_grounds.remove_at(i)
			continue
		if player != null and is_instance_valid(player):
			var c := v.global_position
			if Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length() < float(g[2]) and absf(player.global_position.y - c.y) < 1.5:
				Game.hurt(9.0 * delta, "fire")

# --- People in it -------------------------------------------------------------------------

## The burning thing nearest `at` within `reach` (ground distance to its box), hot enough to
## see: {"k", "i", "box", "heat"}, or empty. Townsfolk ask this to run from it or fight it.
func fire_near(at: Vector3, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for key in _burning:
		var b: Dictionary = _burning[key]
		var box: AABB = b["box"]
		var c := box.get_center()
		var d := maxf(0.0, Vector2(at.x - c.x, at.z - c.z).length() - maxf(box.size.x, box.size.z) * 0.5)
		if d >= bd:
			continue
		var node := streamer.get_chunk(b["k"]) if streamer != null else null
		if node == null:
			continue
		var h := FireSim.heat(node.get_object(b["i"])["st"])
		if h < 0.15:
			continue
		bd = d
		best = {"k": b["k"], "i": b["i"], "box": box, "heat": h}
	return best

## Animals near a fire bolt away from it (once a second, for the fires that are going well).
func _scare_animals() -> void:
	var fauna: FaunaManager = player.fauna if player != null and is_instance_valid(player) else null
	if fauna == null:
		return
	for key in _burning:
		var b: Dictionary = _burning[key]
		var node := streamer.get_chunk(b["k"])
		if node == null:
			continue
		var h := FireSim.heat(node.get_object(b["i"])["st"])
		if h < 0.3:
			continue
		var box: AABB = b["box"]
		var c := box.get_center()
		for cr in fauna.creatures_near(c, 14.0 + 22.0 * h + maxf(box.size.x, box.size.z) * 0.5):
			cr.scare(c, 4.0 + 4.0 * h)

func _hurt_player(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p := player.global_position + Vector3(0, 0.9, 0)
	for key in _burning:
		var b: Dictionary = _burning[key]
		var box: AABB = b["box"]
		if not box.grow(0.5).has_point(p):
			continue
		var node := streamer.get_chunk(b["k"])
		if node == null:
			continue
		var h := FireSim.heat(node.get_object(b["i"])["st"])
		if h > 0.25:
			Game.hurt(14.0 * h * dt, "fire")
			return

# --- The player at a fire -----------------------------------------------------------------

## What the held item does at a fire (Player.use_held asks first): a torch lights what
## it is held to, a bucket fills at water and is thrown on a fire, oil or pitch is poured
## on, and anything swung at a burning thing beats at the flames. True if it acted.
func player_use(pl: Player, it, d: Dictionary, h: Dictionary) -> bool:
	var type: String = it["type"] if it != null else ""
	if type == "bucket":
		return _bucket(pl, it, h)
	if d.get("ranged", false) or d.get("beam", false):
		return false
	if not h.has("obj"):
		_torch["key"] = ""
		return false
	var node: ChunkNode = h["chunk"]
	var o: Dictionary = node.get_object(h["obj"])
	var st: Dictionary = o["st"]
	var label := ObjectLibrary.label_of(o).to_lower()
	if type == "torch":
		if st.has("fire") or not FireSim.burns(o["t"]):
			return false
		# Held to it for a moment before it takes.
		var k := key_of(node.key, int(o["i"]))
		if _torch["key"] != k or now() - float(_torch["t"]) > 3.0:
			_torch = {"key": k, "t": now(), "held": 0.0}
		_torch["held"] = float(_torch.get("held", 0.0)) + 0.3
		pl._cooldown = 0.3
		if float(_torch["held"]) < 1.2:
			Game.toast.emit("Holding the torch to the %s..." % label)
			return true
		_torch["key"] = ""
		if ignite(node, int(o["i"]), 0.55, true):
			Game.toast.emit("The %s catches." % label)
		else:
			Game.toast.emit("The %s won't catch%s." % [label, " (it's soaked)" if FireSim.soak(st, now()) > 0.1 else ""])
		return true
	if type in ["lamp_oil", "resin", "fuel_canister"]:
		if not FireSim.burns(o["t"]):
			return false
		pl._cooldown = 0.6
		Game.inventory.remove_at(pl.selected, 1)
		FireSim.feed(st, {"lamp_oil": 60.0, "resin": 35.0, "fuel_canister": 90.0}[type])
		Game.mark_chunk_dirty(node.data)
		if st.has("fire"):
			Audio.play_at("fire/catch", h.get("point", node.position + (o["p"] as Vector3)), 0.0)
			Game.toast.emit("The %s flares up!" % label)
		else:
			Game.toast.emit("You douse the %s in %s." % [label, ItemDB.def(type)["name"].to_lower()])
		return true
	if st.has("fire"):
		# Beating at the flames instead of breaking it.
		pl._cooldown = 0.5
		var power := clampf(float(d.get("damage", 2.0)) / 10.0, 0.3, 1.5)
		var r := FireSim.beat(st, power, now())
		Audio.play_at("hit/soft", h.get("point", node.position + (o["p"] as Vector3)), -3.0)
		_spark_burst(h.get("point", node.position + (o["p"] as Vector3)), 0.5)
		if r == "out":
			Game.toast.emit("You beat out the fire.")
			_drop(key_of(node.key, int(o["i"])))
			Audio.play_at("fire/hiss", h.get("point", node.position + (o["p"] as Vector3)), -10.0)
		elif FireSim.heat(st) > 0.6:
			Game.toast.emit("It's too far gone to beat out: get water!")
		Game.mark_chunk_dirty(node.data)
		pl.used_tool.emit("hit")
		return true
	return false

## Fills a bucket at water (or a well), throws a full one where you look.
func _bucket(pl: Player, it: Dictionary, h: Dictionary) -> bool:
	pl._cooldown = 0.7
	if not it.get("water", false):
		if _water_at(pl, h):
			it["water"] = true
			Game.inventory.changed.emit()
			Audio.play_at("water/splash", pl.global_position, -10.0)
			Game.toast.emit("You fill the bucket with water.")
			return true
		return false
	it["water"] = false
	Game.inventory.changed.emit()
	var fwd := -pl.camera.global_transform.basis.z
	var at: Vector3 = h["point"] if h.has("point") and (h["point"] as Vector3).distance_to(pl.camera.global_position) < 7.0 else pl.camera.global_position + fwd * 4.0
	douse(at, 2.2, 0.55)
	Audio.play_at("water/splash", at, -2.0)
	Splashes.splash(at, 0.5)
	Game.toast.emit("You throw the water.")
	return true

## Water landing at a point: knocks heat off every fire in reach and soaks what it wets.
func douse(at: Vector3, radius: float, amount: float) -> int:
	var out := 0
	var t := now()
	for e in near(AABB(at - Vector3.ONE * radius, Vector3.ONE * radius * 2.0), 0.0):
		var node: ChunkNode = e[0]
		var st: Dictionary = node.get_object(e[1])["st"]
		var was := st.has("fire")
		if FireSim.quench(st, amount, t) == "out":
			out += 1
			_drop(key_of(node.key, int(e[1])))
		Game.mark_chunk_dirty(node.data)
		if was:
			_steam(at)
	for g in _grounds:
		if is_instance_valid(g[0]) and (g[0] as FireVis).global_position.distance_to(at) < radius + float(g[2]):
			g[1] = float(g[1]) * 0.2
			_steam(at)
	return out

## Puts out every fire at once (console `fire out`).
func douse_all() -> void:
	var t := now()
	for key in _burning.keys():
		var b: Dictionary = _burning[key]
		var node := streamer.get_chunk(b["k"]) if streamer != null else null
		if node != null:
			FireSim.quench(node.get_object(b["i"])["st"], 2.0, t)
			Game.mark_chunk_dirty(node.data)
		_drop(key)

func _steam(at: Vector3) -> void:
	Audio.play_at("fire/hiss", at, -2.0)
	var v := FireVis.new()
	add_child(v)
	v.steam(at)

func _water_at(pl: Player, h: Dictionary) -> bool:
	var feet := pl.global_position
	var t := fmod(GameClock.sec(), 3600.0)
	if Water.surface_height(feet.x, feet.z, t) > feet.y + 0.05:
		return true
	if h.has("point"):
		var p: Vector3 = h["point"]
		if p.distance_to(pl.camera.global_position) < 4.0 and Water.surface_height(p.x, p.z, t) > p.y - 0.05:
			return true
	if h.has("obj"):
		var o: Dictionary = (h["chunk"] as ChunkNode).get_object(h["obj"])
		if o["t"] == "well" or (BuildCatalog.is_built(o["t"]) and BuildCatalog.id_of(o["t"]).contains("well")):
			return true
	return false

## The look of one fire: flames across what is burning, sparks, a column of smoke
## leaning with the wind, firelight and its sound. Kept to its LOD (set_lod) by the
## FireSystem.
class FireVis extends Node3D:
	var box: AABB
	var _flames: Array = [] ## Node3D, nearest first in size order
	var _smoke: GPUParticles3D
	var _smoke_mat: ParticleProcessMaterial
	var _light: FlickerLight
	var _sound: AudioStreamPlayer3D
	var _roar: AudioStreamPlayer3D
	var _embers: Node3D
	var _near := false
	var _lit := false
	var _shadow := false
	var _loud := false
	var _heat := 0.0
	var _smoulder := 0.0
	var _dying := false
	var _ruin := false
	var _tree := false
	var _ground := false
	var _base := 1.0
	var _far := 1.0

	static var _smoke_draw: StandardMaterial3D
	static var _steam_draw: StandardMaterial3D

	## `spots` (FireSystem._spots_of): world points on its roof and walls for the flames.
	func setup(b: AABB, ruin: bool, tree := false, ground := false, spots := {}) -> void:
		box = b
		_ruin = ruin
		_tree = tree
		_ground = ground
		global_position = Vector3(b.get_center().x, b.position.y, b.get_center().z)
		var area := b.size.x * b.size.z
		_base = clampf(minf(b.size.x, b.size.z) * 0.45, 0.6, 3.0) if not ground else clampf(b.size.x * 0.4, 0.5, 1.4)
		if tree:
			_base = clampf(b.size.x * 0.35, 0.8, 2.6)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(absf(b.position.x * 13.0 + b.position.z * 7.0))
		if not ruin:
			var count := clampi(int(area / 6.0) + 1, 1, 8) if not tree else 4
			for i in count:
				var p: Vector3
				if ground:
					p = Vector3(rng.randf_range(-0.4, 0.4) * b.size.x, 0.0, rng.randf_range(-0.4, 0.4) * b.size.z)
				elif tree:
					p = Vector3(rng.randf_range(-0.3, 0.3) * b.size.x, b.size.y * rng.randf_range(0.35, 0.75), rng.randf_range(-0.3, 0.3) * b.size.z)
				elif not spots.is_empty() and (i % 3 == 2 or (spots["roof"] as Array).is_empty()) and not (spots["wall"] as Array).is_empty():
					# Out of a wall, standing just off its face.
					var w: Array = spots["wall"][rng.randi() % (spots["wall"] as Array).size()]
					p = (w[0] as Vector3) + (w[1] as Vector3) * 0.12 - global_position
				elif not spots.is_empty() and not (spots["roof"] as Array).is_empty():
					# Up through the roof, from a spot on it.
					p = (spots["roof"][rng.randi() % (spots["roof"] as Array).size()] as Vector3) - global_position
				elif i % 3 == 2:
					# Out of the walls, at a window's height.
					var side := rng.randi() % 4
					var u := rng.randf_range(-0.4, 0.4)
					p = Vector3(u * b.size.x if side < 2 else (0.48 if side == 2 else -0.48) * b.size.x, b.size.y * rng.randf_range(0.25, 0.5),
						(0.48 if side == 0 else -0.48) * b.size.z if side < 2 else u * b.size.z)
				else:
					# Up through the roof.
					p = Vector3(rng.randf_range(-0.35, 0.35) * b.size.x, b.size.y * rng.randf_range(0.6, 0.95), rng.randf_range(-0.35, 0.35) * b.size.z)
				var size := _base * rng.randf_range(0.7, 1.25) * (1.0 if i == 0 else 0.85)
				var f := FireFx.flame(size)
				f.position = p
				f.visible = false
				for c in f.get_children():
					if c is GeometryInstance3D:
						(c as GeometryInstance3D).visibility_range_end = 300.0
				add_child(f)
				_flames.append(f)
			_embers = FireFx.embers(_base, false)
			if not _flames.is_empty():
				_embers.position = (_flames[0] as Node3D).position
			_embers.visible = false
			add_child(_embers)
		_make_smoke(rng)

	func _make_smoke(rng: RandomNumberGenerator) -> void:
		if _smoke_draw == null:
			_smoke_draw = StandardMaterial3D.new()
			_smoke_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_smoke_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			_smoke_draw.billboard_keep_scale = true
			_smoke_draw.particles_anim_h_frames = 4
			_smoke_draw.particles_anim_v_frames = 4
			_smoke_draw.particles_anim_loop = false
			_smoke_draw.vertex_color_use_as_albedo = true
			_smoke_draw.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			_smoke_draw.roughness = 1.0
			_smoke_draw.proximity_fade_enabled = true
			_smoke_draw.proximity_fade_distance = 1.2
			var sheet := "res://assets/textures/fx/smoke_flipbook.png"
			if ResourceLoader.exists(sheet):
				_smoke_draw.albedo_texture = load(sheet)
		_smoke = GPUParticles3D.new()
		_smoke.name = "Smoke"
		var big := maxf(box.size.x, box.size.z)
		_smoke.amount = int(FireSystem.QUALITY[FireSystem.quality]["smoke"]) if not _ground else 24
		_smoke.lifetime = 13.0 if not _ground else 5.0
		_smoke.local_coords = false
		_smoke.preprocess = 0.0
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke.visibility_aabb = AABB(Vector3(-60, -4, -60), Vector3(120, 110, 120))
		_smoke.visibility_range_end = 1200.0
		_smoke.position = Vector3(0, box.size.y * (0.85 if not _tree else 0.8), 0)
		_smoke_mat = ParticleProcessMaterial.new()
		_smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_smoke_mat.emission_box_extents = Vector3(box.size.x * 0.3, 0.3, box.size.z * 0.3)
		_smoke_mat.direction = Vector3.UP
		_smoke_mat.spread = 14.0
		_smoke_mat.initial_velocity_min = 1.4
		_smoke_mat.initial_velocity_max = 3.2
		_smoke_mat.gravity = Vector3(0, 0.3, 0)
		_smoke_mat.damping_min = 0.15
		_smoke_mat.damping_max = 0.4
		_smoke_mat.angle_min = -180.0
		_smoke_mat.angle_max = 180.0
		_smoke_mat.angular_velocity_min = -12.0
		_smoke_mat.angular_velocity_max = 12.0
		_smoke_mat.anim_offset_max = 1.0
		_smoke_mat.scale_min = 0.8
		_smoke_mat.scale_max = 1.4
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 0.35))
		sc.add_point(Vector2(0.25, 1.0))
		sc.add_point(Vector2(1.0, 3.2))
		var sct := CurveTexture.new()
		sct.curve = sc
		_smoke_mat.scale_curve = sct
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.06, Color(0.8, 0.8, 0.8, 0.85))
		g.add_point(0.5, Color(1, 1, 1, 0.5))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		_smoke_mat.color_ramp = gt
		_smoke_mat.turbulence_enabled = true
		_smoke_mat.turbulence_noise_strength = 1.2
		_smoke_mat.turbulence_noise_scale = 6.0
		_smoke_mat.turbulence_influence_min = 0.05
		_smoke_mat.turbulence_influence_max = 0.15
		_smoke.process_material = _smoke_mat
		var q := QuadMesh.new()
		q.size = Vector2.ONE * clampf(big * 0.35, 1.2, 4.0) * (0.6 if _ground else 1.0)
		q.material = _smoke_draw
		_smoke.draw_pass_1 = q
		_smoke.emitting = true
		add_child(_smoke)

	## Where the firelight hangs: a little out from the flame furthest out from the middle
	## (one out of a wall, else one on the roof), lifted into the flames.
	func _light_spot() -> Vector3:
		var best := Vector3(0, box.size.y * 0.7, 0)
		var bd := -1.0
		for f in _flames:
			var q := (f as Node3D).position
			var d := Vector2(q.x, q.z).length()
			if d > bd:
				bd = d
				best = q
		if bd < 0.0:
			return best
		var out := Vector3(best.x, 0, best.z).normalized() if bd > 0.1 else Vector3.ZERO
		return best + out * 0.8 + Vector3(0, _base * 0.6, 0)

	## Which parts are drawn: flames and sparks, the firelight (with shadows?), the sound.
	func set_lod(flames: bool, lit: bool, shadow: bool, loud: bool, dist: float) -> void:
		_near = flames
		if lit != _lit or shadow != _shadow:
			_lit = lit
			_shadow = shadow
			if lit and _light == null:
				_light = FlickerLight.new()
				_light.light_color = Color(1.0, 0.56, 0.26)
				_light.light_energy = 2.0
				_light.omni_range = clampf(maxf(box.size.x, box.size.z) * 1.8 + 8.0, 10.0, 32.0)
				_light.omni_attenuation = 1.2
				_light.distance_fade_enabled = true
				_light.distance_fade_begin = 70.0
				_light.distance_fade_length = 20.0
				# Out where the flames are, not inside the walls: a light in the middle of a
				# house lights only its insides, never the walls, yard and smoke round it.
				_light.position = _light_spot()
				if not _flames.is_empty():
					_light.seed = float((_flames[0] as Node3D).get_meta("fire_seed", 0.5))
				add_child(_light)
			if _light != null:
				_light.visible = lit
				_light.shadow_enabled = shadow
				_light.light_size = 0.5
				_light.shadow_bias = 0.05
				_light.distance_fade_shadow = 30.0
		if loud != _loud:
			_loud = loud
			if loud and _sound == null and not _ruin:
				_sound = _loop("res://assets/audio/sfx/fire/crackle.ogg", -6.0)
				_roar = _loop("res://assets/audio/sfx/fire/roar.ogg", -80.0)
			for p in [_sound, _roar]:
				if p != null:
					(p as AudioStreamPlayer3D).stream_paused = not loud
		# Far off, fewer puffs.
		_far = 1.0 if dist < 250.0 else 0.5
		_apply()

	func _loop(path: String, db: float) -> AudioStreamPlayer3D:
		if not ResourceLoader.exists(path):
			return null
		var p := AudioStreamPlayer3D.new()
		var s = load(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
		p.volume_db = db
		p.unit_size = clampf(maxf(box.size.x, box.size.z), 3.0, 14.0)
		p.max_distance = 90.0
		p.bus = "Effects"
		p.position = Vector3(0, box.size.y * 0.5, 0)
		add_child(p)
		p.play(randf() * 4.0)
		return p

	## heat 0..1 of the fire; smoulder 0..1 for a ruin's thin smoke.
	func set_heat(h: float, smoulder: float, env: Dictionary) -> void:
		if _dying:
			return
		_heat = h
		_smoulder = smoulder
		var ws: float = env.get("wind", 0.3)
		var wd: Vector2 = env.get("wind_dir", Vector2(0.8, 0.6))
		var rain: float = env.get("rain", 0.0)
		_smoke_mat.gravity = Vector3(wd.x * ws * 2.6, 0.25 + h * 0.45, wd.y * ws * 2.6)
		# Thick dark smoke off a fire well alight; pale off a smoulder; whiter in rain
		# (steam).
		var tone := lerpf(0.55, 0.13, smoothstep(0.2, 0.8, h)) if not _ruin else 0.5
		tone = lerpf(tone, 0.75, rain * 0.6)
		_smoke_mat.color = Color(tone, tone * 0.97, tone * 0.94, clampf(0.25 + h * 0.75 + smoulder, 0.0, 1.0))
		_smoke_mat.initial_velocity_max = 1.6 + h * 3.0
		_apply()

	func _apply() -> void:
		_smoke.amount_ratio = clampf(maxf(_heat * 1.2, _smoulder) + 0.1, 0.1, 1.0) * _far
		var shown := ceili(_flames.size() * clampf(_heat * 1.15, 0.0, 1.0)) if _near else 0
		for i in _flames.size():
			var f: Node3D = _flames[i]
			f.visible = i < shown
			if f.visible:
				f.scale = Vector3.ONE * (0.45 + 0.75 * _heat)
		if _embers != null:
			_embers.visible = _near and _heat > 0.3
		if _light != null:
			_light.base = 0.8 + 6.0 * _heat # bright enough to show by day
			_light.visible = _lit and _heat > 0.05
		if _sound != null:
			_sound.volume_db = linear_to_db(clampf(_heat * 1.4, 0.02, 1.0)) - 4.0
		if _roar != null:
			_roar.volume_db = linear_to_db(clampf((_heat - 0.45) * 1.6, 0.001, 1.0)) - 2.0

	## Goes out: flames sink, the smoke stops and drifts off, then it is gone.
	func die() -> void:
		if _dying:
			return
		_dying = true
		_smoke.emitting = false
		var tw := create_tween().set_parallel()
		for f in _flames:
			tw.tween_property(f, "scale", Vector3.ONE * 0.02, 1.5)
		if _light != null:
			tw.tween_property(_light, "base", 0.0, 1.5)
		for p in [_sound, _roar]:
			if p != null:
				tw.tween_property(p, "volume_db", -60.0, 1.5)
		tw.chain().tween_interval(_smoke.lifetime)
		tw.chain().tween_callback(queue_free)

	## A billow of dust and ash where something fell in.
	func burst(b: AABB) -> void:
		box = b
		global_position = Vector3(b.get_center().x, b.position.y, b.get_center().z)
		_make_smoke(RandomNumberGenerator.new())
		_smoke.one_shot = true
		_smoke.explosiveness = 0.85
		_smoke.lifetime = 6.0
		_smoke.position = Vector3(0, 0.6, 0)
		_smoke_mat.emission_box_extents = Vector3(b.size.x * 0.5, 0.5, b.size.z * 0.5)
		_smoke_mat.direction = Vector3(0, 0.3, 0)
		_smoke_mat.spread = 90.0
		_smoke_mat.initial_velocity_min = 2.0
		_smoke_mat.initial_velocity_max = 5.0
		_smoke_mat.gravity = Vector3(0, -0.2, 0)
		_smoke_mat.damping_min = 1.5
		_smoke_mat.damping_max = 2.5
		_smoke_mat.color = Color(0.42, 0.38, 0.34, 0.9)
		_smoke.restart()
		var tw := create_tween()
		tw.tween_interval(7.0)
		tw.tween_callback(queue_free)

	## A puff of steam where water hit a fire.
	func steam(at: Vector3) -> void:
		box = AABB(at - Vector3(1, 0, 1), Vector3(2, 1, 2))
		global_position = at
		_make_smoke(RandomNumberGenerator.new())
		_smoke.position = Vector3.ZERO
		_smoke.one_shot = true
		_smoke.explosiveness = 0.9
		_smoke.amount = 16
		_smoke.lifetime = 3.0
		_smoke_mat.initial_velocity_min = 1.5
		_smoke_mat.initial_velocity_max = 3.5
		_smoke_mat.color = Color(0.92, 0.92, 0.94, 0.6)
		_smoke.restart()
		var tw := create_tween()
		tw.tween_interval(4.0)
		tw.tween_callback(queue_free)
