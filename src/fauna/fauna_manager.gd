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
var field: WorldField
var _herds: Dictionary = {} ## Vector2i chunk -> Array[Creature]
var _scan := 0.0

func _ready() -> void:
	field = WorldField.new(Game.seed)

func _ground(x: float, z: float) -> float:
	return npcs.ground(x, z) if npcs else NAN

func _process(delta: float) -> void:
	if player == null or streamer == null or Game.store == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 1.0
		_refresh()
	var pp := player.global_position
	var g := Callable(self, "_ground")
	for k in _herds:
		for c in _herds[k]:
			if is_instance_valid(c):
				c.step(delta, g, pp)

func _refresh() -> void:
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
	var r := WHash.rng(seed, cx, cz, 701)
	if r.randf() > HERD_CHANCE:
		return out
	var era: int = chunk.get("era", 0)
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
		var y := ChunkGenerator.height_at(cn.data, h["lx"], h["lz"])
		if y < Water.LEVEL - 0.5:
			continue
		var c := Creature.new()
		c.setup(h["id"], h["sp"], h["era"], cn.position + Vector3(h["lx"], y, h["lz"]), self)
		add_child(c)
		list.append(c)
	return list

func creature_bites(c: Creature) -> void:
	var dmg := 4.0 + float(c.p["size"]) * 6.0
	Game.set_health(Game.health - dmg)
	Game.toast.emit("%s bites you (-%d)" % [c.label(), int(dmg)])

## The player hit an animal. Kills are permanent and pay out the species' drops.
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
	for d in c.p["drops"]:
		Game.give(ItemDB.make(d[0], d[1], randf_range(0.85, 1.15), Game.origin_here("hunted", c.era, k)))
	Game.toast.emit("Killed %s" % c.label())
	if _herds.has(k):
		_herds[k].erase(c)
	c.queue_free()
