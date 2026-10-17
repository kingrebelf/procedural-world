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

func _ready() -> void:
	field = WorldField.new(Game.seed)

func _ground(x: float, z: float) -> float:
	return npcs.ground(x, z) if npcs else NAN

const TAG_RANGE := 28.0

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
	# Tags show within TAG_RANGE, or far out for the one you are looking at through
	# binoculars.
	var spotted: Creature = player.spotted if player.get("spotted") != null else null
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else pp + Vector3(0, 1.6, 0)
	for k in _herds:
		for c in _herds[k]:
			if is_instance_valid(c):
				c.step(delta, g, pp)
				var near: bool = c._body != null and (c.global_position.distance_to(pp) < TAG_RANGE or c == spotted)
				# Tags draw over everything (so grass doesn't hide them), so they only show
				# for animals you can actually see: not through a wall or a hill.
				if near and c != spotted:
					near = _in_sight(c, eye, delta)
				c.update_tag(near, lv)

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
	for k in _herds.keys():
		if absi(k.x - pc.x) > RADIUS + 1 or absi(k.y - pc.y) > RADIUS + 1:
			for c in _herds[k]:
				if is_instance_valid(c):
					c.queue_free()
			_herds.erase(k)
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := pc + Vector2i(dx, dz)
			if _herds.has(k):
				continue
			var cn := streamer.get_chunk(k)
			if cn == null:
				continue
			_herds[k] = _spawn(cn)

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
	var took := Game.hurt(dmg, "Killed by a %s" % c.label(), func(back: float): player_hit(c, back))
	Game.toast.emit("%s bites you (-%d)" % [c.label(), int(ceilf(took))])

## The player hit an animal. Kills are permanent and leave a carcass to butcher.
func player_hit(c: Creature, dmg: float) -> void:
	if not c.hurt(dmg):
		return
	var parts := c.id.split("_")
	var k := Vector2i(parts[0].to_int(), parts[1].to_int())
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
			Game.give(ItemDB.make(d[0], d[1], randf_range(0.85, 1.15), Game.origin_here("hunted", c.era, k)))
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
