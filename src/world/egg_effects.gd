class_name EggEffects
## What finding one of the hidden finds (see EasterEggs) does. Rewards are rolled from the
## world seed and the object, so a find gives the same whoever gets there first; who that
## was is written into the object's state, and that state lives in the chunk snapshot, so
## a find taken in multiplayer is taken for everyone.

const JOURNAL_REACH := 1400.0 ## how far an explorer's journal knows of another secret
const GNOME_LUCK := 1.0

const SWORD_NAMES := ["Stonedrawn", "Oathkeeper", "Hillheart", "Kingsmark", "the Patient Blade", "Rootcleaver", "Last Light of %s"]
const EXPLORERS := ["Aldous Fenwick", "Maud Thistlewood", "Corin Hale", "Ysolde Marr", "Benedikt Crane", "Wren Osgood", "Tamsin Holloway", "Edric Vane"]
const LETTERS := [
	"To whoever finds this: I buried what I could carry before the ship went down. The map is true. Spend it well.",
	"My dearest, if this reaches you, I am alive and I am rich. If it reaches anyone else: finders keepers.",
	"I have hidden my share where the others will never look. If I don't come back for it, it's yours.",
	"Third bottle I've thrown. Nobody ever writes back. Here's the map anyway.",
]
const KNOCKS := [
	"A tiny voice calls \"Not today, thank you!\" and the door stays shut",
	"You hear a kettle whistle, very small, and then nothing",
	"Something the size of a mouse peers through the letterbox and snaps it shut",
	"Snoring. Very small snoring",
]

static var _gen: ChunkGenerator
static var _gen_seed := 0

## Uses find `o` in `chunk`; returns the line to show. Call only when EasterEggs.use_of(o)
## offers something.
static func apply(o: Dictionary, chunk: ChunkNode, player: Player) -> String:
	var st: Dictionary = o["st"]
	var t := String(o["t"])
	var today := int(floor(Game.day))
	var rng := WHash.rng(Game.seed, chunk.key.x * 4099 + int(o["i"]), chunk.key.y, 1210)
	rng.randf()
	var era := clampi(int(o["e"]), 0, Eras.COUNT - 1)
	var origin := Game.origin_here("found", era, chunk.key)
	var wp: Vector3 = chunk.position + o["p"]
	var first: bool = not st.get("used", false)
	var msg := ""
	match t:
		"sword_stone":
			var arm := int(Game.stats.attrs.get("str", 0)) + (2 if Game.buffs.has("strength") else 0)
			if arm < EasterEggs.SWORD_STR:
				return "You heave until your arms shake, but the sword won't move. It wants a stronger arm (Strength %d, you have %d)" % [EasterEggs.SWORD_STR, arm]
			var it := ItemDB.make("sword_runic" if era == Eras.FANTASY else "sword_iron", 1, 1.35, origin)
			Rarity.apply(it, 4, rng)
			var nm: String = SWORD_NAMES[rng.randi() % SWORD_NAMES.size()]
			if nm.contains("%s"):
				nm = nm % _gen_of().field.region_name_at(wp.x, wp.z)
			it["name"] = nm[0].to_upper() + nm.substr(1)
			if not Game.give(it):
				return "The sword slides free, but you have no room to carry it. Make room and try again"
			st["drawn"] = true
			msg = "With a grinding of stone the sword slides free. You hold %s" % it["name"]
		"gnome_ring":
			var t_day := fposmod(Game.day, 1.0)
			if t_day > 0.22 and t_day < 0.8:
				return "You stand in the ring. The gnome stares. Nothing happens, not while the sun is up"
			Game.add_buff("inspired", 1200.0)
			Game.add_buff("swift", 600.0)
			var got := WonderEffects._give_all(ItemDB.roll_loot(era, rng, origin, GNOME_LUCK))
			msg = "The toadstools stir and the gnome winks. You feel quick and clever" + (", and there is %s at your feet" % got if got != "" else "")
		"msg_bottle":
			var letter: String = LETTERS[rng.randi() % LETTERS.size()]
			var got := WonderEffects._give_all([Treasure.make_map(era, origin)])
			if got == "":
				return "A rolled-up map is inside, but you have no room for it"
			msg = "\"%s\" A treasure map is rolled up with the letter" % letter
		"lost_camp":
			var who: String = EXPLORERS[rng.randi() % EXPLORERS.size()]
			var got := WonderEffects._give_all(ItemDB.roll_loot(era, rng, origin, 0.6))
			msg = "The journal of %s: the last pages tell of %s" % [who, _rumour(wp)]
			if got != "":
				msg += ". In the pack you find %s" % got
		"tiny_door":
			if first:
				var loot := ItemDB.roll_loot(era, rng, origin, 0.3)
				loot.append({"type": "_marks", "qty": rng.randi_range(20, 60)})
				var got := WonderEffects._give_all(loot)
				msg = "The door opens a crack and a tiny hand pushes out a pouch" + (": %s" % got if got != "" else "")
			else:
				msg = KNOCKS[(today + int(o["i"])) % KNOCKS.size()]
	if first:
		st["used"] = true
		st["by"] = Net.my_id()
		st["by_name"] = Net.player_name(Net.my_id()) if Net.online() else ""
		Game.add_xp(EasterEggs.XP.get(t, 50.0), "Secret found")
		_tally(chunk, o)
	st["day"] = today
	if t == "msg_bottle":
		chunk.remove_object(int(o["i"]))
	elif t == "sword_stone":
		chunk.set_objects(ChunkNode.build_object_buffers(chunk.data, false), true)
	Game.mark_chunk_dirty(chunk.data)
	return msg

## Counts the secrets this world has given you up.
static func _tally(chunk: ChunkNode, o: Dictionary) -> void:
	var found: Dictionary = Game.discovery.get("secrets", {})
	found["%d:%d,%d:%d" % [Game.planet, chunk.key.x, chunk.key.y, int(o["i"])]] = {"t": o["t"], "day": Game.day}
	Game.discovery["secrets"] = found
	if Game.store:
		Game.store.save_discovery(Game.discovery)

## What the journal says of the nearest other secret, and the rough spot it puts on your
## atlas (an explorer's guess, not a pin on the spot).
static func _rumour(wp: Vector3) -> String:
	var g := _gen_of()
	var here := Vector2(wp.x, wp.z)
	var e := EasterEggs.nearest(g, here, JOURNAL_REACH, here)
	if e.is_empty():
		return "nothing you can make sense of, only the cold and the dark"
	var p: Vector2 = e["p"]
	var r := WHash.rng(Game.seed, int(p.x), int(p.y), 1211)
	r.randf()
	var guess := p + Vector2.from_angle(r.randf() * TAU) * r.randf_range(10.0, 35.0)
	Game.markers.add("Rumour: %s" % EasterEggs.label(e["t"]), guess.x, guess.y, Game.planet)
	Game.touch_player()
	return "%s, %d m to the %s (marked on your atlas)" % [EasterEggs.WHERE[e["t"]], int(round(p.distance_to(here) / 50.0)) * 50, Wonders.compass(here, p)]

static func _gen_of() -> ChunkGenerator:
	if _gen == null or _gen_seed != Game.seed:
		_gen = ChunkGenerator.new(Game.seed, Game.store.has_rivers() if Game.store else true)
		_gen_seed = Game.seed
	return _gen
