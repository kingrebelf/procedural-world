class_name FaunaManager
extends Node3D
## Wildlife around the player. Each chunk's herds are a pure function of the world seed,
## the chunk and its region's biome, so they need no storage of their own; the only state
## is which animals the player has killed, kept in the chunk snapshot ("fauna_dead").

const RADIUS := 2 ## chunks around the player that have live animals
const HERD_CHANCE := 0.3

var streamer: ChunkStreamer
var player: Node3D
var npcs: NPCManager
var corpses: Corpses
var field: WorldField
var _herds: Dictionary = {} ## Vector2i chunk -> Array[Creature]
var _scan := 0.0

var _mob_t := 0.0

func _ready() -> void:
	field = WorldField.new(Game.seed)
	Net.mob_hit.connect(_on_mob_hit)
	# Smooth and muscle the kit animals' meshes before the first herd shows up.
	AnimalSkin.warm(AnimalModel.HEIGHT.keys())

func _ground(x: float, z: float) -> float:
	return npcs.ground(x, z) if npcs else NAN

const TAG_RANGE := 25.0
## Off for pictures without a HUD (the capture tool's --hud=none).
var show_tags := true
const SPAWN_BUDGET_USEC := 4000

func _process(delta: float) -> void:
	if player == null or streamer == null or Game.store == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 1.0
		_refresh()
	var pp := player.global_position
	var g := Callable(self, "_ground")
	var lv: int = Game.stats.level if Game.stats else 1
	# Tags show for ground animals within TAG_RANGE, for any animal fighting you or hurt,
	# and for the one under the crosshair or in the binoculars; birds overhead go untagged.
	var spotted: Creature = player.spotted if player.get("spotted") != null else null
	if spotted == null and player.get("looking_at") != null and is_instance_valid(player.looking_at):
		spotted = player.looking_at
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else pp + Vector3(0, 1.6, 0)
	var shown := []
	_mob_t -= delta
	var send := _mob_t <= 0.0
	if send:
		_mob_t = 1.0 / Net.MOB_HZ
	var out: Array = []
	for k in _herds:
		# On a server one player runs each chunk's animals; the others see them (Net.holds).
		var held := Net.holds("f", k)
		var shared := send and held and Net.shared("f", k)
		for c in _herds[k]:
			if is_instance_valid(c):
				if held:
					# Out of sight and calm, an animal thinks and moves a quarter as often
					# (with the time it skipped): nothing on screen changes.
					c.lod_dt += delta
					c.lod_tick += 1
					if c.lod_tick % _step_every(c, eye, cam) == 0:
						# They notice, chase and flee from whichever player is nearest.
						c.step(c.lod_dt, g, Net.nearest_player(c.global_position, pp)[1])
						c.lod_dt = 0.0
					if shared:
						out.append(c.net_state())
				else:
					c.follow(delta, g, Net.mob_state("f", c.id))
				var fighting: bool = c.state == "chase" or c.hp < float(c.p["hp"])
				var near: bool = show_tags and c._body != null and (c == spotted or (c.global_position.distance_to(pp) < TAG_RANGE and (fighting or c.p["plan"] != "bird")))
				# Only for animals you can actually see: not over a hill or behind a house
				# (the walls hide the tag itself; this keeps a tag from peeking over them).
				if near and c != spotted:
					near = _in_sight(c, eye, delta)
				if near:
					shown.append(c)
				else:
					c.update_tag(false, lv)
	if not out.is_empty():
		Net.send_mobs("f", out)
	_declutter(shown, cam, spotted, lv)

## How many frames apart an animal steps: every frame on screen, near you or when it is
## chasing or fleeing; every fourth frame otherwise.
static func _step_every(c: Creature, eye: Vector3, cam: Camera3D) -> int:
	if cam == null or c.state == "chase" or c.state == "flee":
		return 1
	var p := c.global_position
	if eye.distance_squared_to(p) < 144.0 or cam.is_position_in_frustum(p + Vector3.UP * 0.5):
		return 1
	return 4

## Shows the tags of these animals, nearest (and the one you are spotting) first, but not
## one that would land on another's on screen: a flock shows a tag or two, not a pile.
func _declutter(shown: Array, cam: Camera3D, spotted: Creature, lv: int) -> void:
	if cam == null:
		for c in shown:
			c.update_tag(true, lv)
		return
	var eye := cam.global_position
	shown.sort_custom(func(a, b): return a == spotted or (b != spotted and a.global_position.distance_squared_to(eye) < b.global_position.distance_squared_to(eye)))
	var h := get_viewport().get_visible_rect().size.y
	var placed := []
	for c in shown:
		var at: Vector3 = c._tag.global_position if c._tag else c.global_position + Vector3(0, 1.0, 0)
		var free := true
		if not cam.is_position_behind(at):
			var sp := cam.unproject_position(at)
			for o in placed:
				if absf(sp.x - o.x) < h * 0.13 and absf(sp.y - o.y) < h * 0.04:
					free = false
					break
			if free:
				placed.append(sp)
		c.update_tag(free, lv)

var _sight := {} ## creature instance id -> [seconds until checked again, could see it]

func _in_sight(c: Creature, eye: Vector3, delta: float) -> bool:
	var id := c.get_instance_id()
	var e: Array = _sight.get(id, [0.0, false])
	e[0] -= delta
	if e[0] <= 0.0:
		e[0] = randf_range(0.2, 0.3)
		var to: Vector3 = c._tag.global_position if c._tag else c.global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, to)
		q.collision_mask = 0xFFFFFFFF & ~2 # other animals don't block the view
		if player is CollisionObject3D:
			q.exclude = [(player as CollisionObject3D).get_rid()]
		e[1] = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	_sight[id] = e
	return e[1]

func _refresh() -> void:
	for id in _sight.keys():
		if not is_instance_id_valid(id):
			_sight.erase(id)
	var pc := ChunkStreamer.chunk_of(player.global_position)
	var gone: Array = []
	var added: Array = []
	for k in _herds.keys():
		if absi(k.x - pc.x) > RADIUS + 1 or absi(k.y - pc.y) > RADIUS + 1:
			for c in _herds[k]:
				if is_instance_valid(c):
					c.queue_free()
			_herds.erase(k)
			gone.append(k)
			continue
		# Killed by another player (their kill reached this chunk's data).
		var cn := streamer.get_chunk(k)
		var dead: Dictionary = cn.data.get("fauna_dead", {}) if cn != null else {}
		if not dead.is_empty():
			for c in _herds[k].duplicate():
				if is_instance_valid(c) and dead.has(c.id):
					_herds[k].erase(c)
					c.die()
	# A few chunks' herds per call (each animal takes a few ms to dress), nearest first;
	# the rest come on the next calls, soon after.
	var t0 := Time.get_ticks_usec()
	for r in RADIUS + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := pc + Vector2i(dx, dz)
				if _herds.has(k):
					continue
				var cn := streamer.get_chunk(k)
				if cn == null:
					continue
				if Time.get_ticks_usec() - t0 > SPAWN_BUDGET_USEC:
					_scan = minf(_scan, 0.05)
					continue
				_herds[k] = _spawn(cn)
				added.append([k, Vector2((k.x + 0.5) * ChunkGenerator.SIZE, (k.y + 0.5) * ChunkGenerator.SIZE)])
	if not gone.is_empty() or not added.is_empty():
		Net.watch("f", added, gone)

## Herd composition for a chunk. Deterministic, so the same animals are always here.
static func herds_for(seed: int, chunk: Dictionary, field: WorldField) -> Array:
	var out: Array = []
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	# Stronghold guards (see Stronghold.guards), stored in the chunk.
	for g in chunk.get("guards", []):
		var h := {"id": g["id"], "sp": -int(g["tier"]), "era": int(g["era"]), "lx": g["lx"], "lz": g["lz"]}
		if g.has("ly"):
			h["ly"] = g["ly"] # a cave dweller, on the cave floor
		out.append(h)
	out.append_array(Creature.livestock_for(seed, chunk))
	var r := WHash.rng(seed, cx, cz, 701)
	if r.randf() > HERD_CHANCE:
		return out
	var era: int = Eras.nature(chunk.get("era", 0)) # real animals in a human world's outposts too
	var bh: int = chunk.get("biome", field.region_hash_at(cx * 64.0 + 32.0, cz * 64.0 + 32.0))
	var bp := Biome.params(bh, era)
	var fauna: Array = bp.get("fauna", [])
	if fauna.is_empty():
		return out
	var sp: int = fauna[r.randi() % fauna.size()]
	var p := Creature.species(sp, era)
	var lx := r.randf_range(8, 56)
	var lz := r.randf_range(8, 56)
	for i in int(p["herd"]):
		out.append({"id": "%d_%d_%d" % [cx, cz, i], "sp": sp, "era": era,
			"lx": clampf(lx + r.randf_range(-5, 5), 0, 63.9), "lz": clampf(lz + r.randf_range(-5, 5), 0, 63.9)})
	return out

func _spawn(cn: ChunkNode) -> Array:
	var list: Array = []
	var dead: Dictionary = cn.data.get("fauna_dead", {})
	for h in herds_for(Game.seed, cn.data, field):
		if dead.has(h["id"]):
			continue
		var y: float = h.get("ly", ChunkGenerator.height_at(cn.data, h["lx"], h["lz"]))
		if y < Water.LEVEL - 0.5:
			continue
		var c := Creature.new()
		c.setup(h["id"], h["sp"], h["era"], cn.position + Vector3(h["lx"], y, h["lz"]), self)
		c.chunk = Vector2i(int(cn.data["cx"]), int(cn.data["cz"]))
		if h.has("ly"):
			c.underground = true
			c.p["roam"] = 6.0
		add_child(c)
		list.append(c)
	return list

## The cave floor under a creature at world point p, or NAN inside rock or off the map.
func cave_floor(p: Vector3) -> float:
	var k := ChunkStreamer.chunk_of(p)
	var cn := streamer.get_chunk(k)
	if cn == null or not cn.data.has("cave"):
		return NAN
	return Caves.floor_below(cn.data["cave"], p + Vector3(0, 0.8, 0), 2.6)

## Melee aim help: the nearest live animal within reach and roughly in front of you.
## Animals are short and close when they attack, so a swing aimed level would pass over
## a wolf at your feet; this lets a swing at it land as it looks like it should.
## Live animals within `radius` of a point.
func creatures_near(at: Vector3, radius: float) -> Array:
	var out := []
	for k in _herds:
		for c in _herds[k]:
			if is_instance_valid(c) and c._body != null and c.global_position.distance_to(at) <= radius + float(c.p["size"]) * 0.5:
				out.append(c)
	return out

func melee_target(eye: Vector3, fwd: Vector3, reach: float) -> Creature:
	var f := Vector2(fwd.x, fwd.z).normalized()
	var best: Creature = null
	var best_d := INF
	for k in _herds:
		for c in _herds[k]:
			if not is_instance_valid(c) or c._body == null:
				continue
			var to := Vector2(c.global_position.x - eye.x, c.global_position.z - eye.z)
			var d := to.length()
			if d > reach + float(c.p["size"]) * 0.6 or eye.y - c.global_position.y > reach + 1.0:
				continue
			if d > 0.3 and f.dot(to / d) < 0.75: # within about 40 degrees
				continue
			if d < best_d:
				best_d = d
				best = c
	return best

func creature_bites(c: Creature) -> void:
	var dmg := c.bite_damage()
	var tg: Array = Net.nearest_player(c.global_position, player.global_position)
	if int(tg[0]) != 0:
		Net.hurt_player(int(tg[0]), dmg, "Killed by a %s" % c.label(), false)
		return
	var took := Game.hurt(dmg, "Killed by a %s" % c.label(), func(back: float): player_hit(c, back))
	Game.toast.emit("%s bites you (-%d)" % [c.label(), int(ceilf(took))])

## The player hit an animal. Kills are permanent and leave a carcass to butcher.
func player_hit(c: Creature, dmg: float) -> void:
	var held := Net.holds("f", c.chunk)
	if not held:
		# Someone else runs it: they feel the blow; a killing blow is yours (the kill,
		# the carcass and the XP), and they let it go.
		Net.hit_mob("f", c.chunk, c.id, dmg, c.hp - dmg <= 0.0)
	if not c.hurt(dmg):
		return
	var k := c.chunk
	var cn := streamer.get_chunk(k)
	if cn != null:
		if not cn.data.has("fauna_dead"):
			cn.data["fauna_dead"] = {}
		cn.data["fauna_dead"][c.id] = Game.day
		Game.mark_chunk_dirty(cn.data)
	if corpses:
		corpses.add_animal(c)
		Game.toast.emit("Killed %s. Hold [%s] on it to %s it" % [c.label(), Bindings.key_name("interact", Game.using_pad), CorpseLoot.verb(c.p).to_lower()])
	else:
		for d in c.p["drops"]:
			Game.give_loot(ItemDB.make(d[0], d[1], randf_range(0.85, 1.15), Game.origin_here("hunted", c.era, k)))
		Game.toast.emit("Killed %s" % c.label())
	if c.p.has("boss"):
		# A wonder's keeper: its vault opens, and that is worth a great deal.
		Game.add_xp(600.0, "Slew " + c.label())
		Game.discovered.emit(c.label() + " has fallen", "The vault of %s is unsealed" % WonderSite.label(c.p["boss"]), WonderSite.COLORS[c.p["boss"]])
		if cn != null:
			Game.map.note_chunk(cn.data)
	else:
		Game.add_xp(clampf(float(c.p["hp"]) / 3.0, 5.0, 80.0), "Hunting")
	if _herds.has(k):
		_herds[k].erase(c)
	c.die()

## Another player hit one of the animals you run (killed: their blow killed it, and
## their game keeps the kill and the carcass).
func _on_mob_hit(kind: String, id: String, dmg: float, killed: bool, _from: int) -> void:
	if kind != "f":
		return
	for k in _herds:
		for c in _herds[k]:
			if is_instance_valid(c) and c.id == id:
				if killed:
					_herds[k].erase(c)
					c.die()
				else:
					c.hurt(dmg)
					c.hp = maxf(c.hp, 1.0)
				return
