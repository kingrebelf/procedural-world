class_name WonderSite
## Wonders of the world: very rare places, far rarer than strongholds, that hold the best
## loot in the game and the hardest fights. At most one per CELL x CELL chunks, and only
## where the ground allows, so many cells have none:
##
##   Titan's Throne      (medieval)  a colossal stone king on a stepped dais
##   The Worldroot       (fantasy)   a tree the size of a tower, lanterns in its crown
##   Fallen Dreadnought  (sci-fi)    a warship that came down and never left
##   Starfall Gate       (any era)   a ring of rune stones round a door to elsewhere
##
## Each stands in a cleared plaza ringed by eight pillars, with a beam of light over it
## that can be seen from far off. Elite guards walk the plaza and a boss keeps the vault;
## the vault stays sealed until the boss is dead. A wonder sits wholly inside one chunk,
## so it is either generated with that chunk or not at all (no half wonders in old saves).

const CELL := 14 ## chunks per side of a wonder cell (about 900 m)
const CHANCE := 0.5 ## of a cell trying to hold one; the ground often says no
const GATE_CHANCE := 0.2
const PLAZA := 19.0 ## level ground radius
const EDGE := 25.0 ## where the levelled ground meets the land again
const RING := 15.5 ## pillar ring radius
const CLEAR := 27.0 ## nothing else grows or stands this close

const TYPES := ["w_throne", "w_worldroot", "w_dreadnought", "w_gate"]
const NAMES := {"w_throne": "Titan's Throne", "w_worldroot": "The Worldroot", "w_dreadnought": "Fallen Dreadnought", "w_gate": "Starfall Gate"}
const BY_ERA := ["w_throne", "w_worldroot", "w_dreadnought"]
## How far in front of each centrepiece its vault stands (the boss a little further out).
const FRONT := {"w_throne": 8.2, "w_worldroot": 6.5, "w_dreadnought": 11.0, "w_gate": 4.0}
const PILLAR := {"w_throne": "w_column", "w_worldroot": "w_crystal", "w_dreadnought": "w_pylon", "w_gate": "w_obelisk"}
const LABELS := {
	"w_throne": "Titan's Throne", "w_worldroot": "The Worldroot", "w_dreadnought": "Fallen Dreadnought", "w_gate": "Starfall Gate",
	"w_column": "Titan's Column", "w_crystal": "Root Crystal", "w_pylon": "Dreadnought Pylon", "w_obelisk": "Star Obelisk",
}
const LORE := {
	"w_throne": "A king of the old giants, still keeping court",
	"w_worldroot": "Older than every forest it seeded",
	"w_dreadnought": "Its reactor still hums somewhere inside",
	"w_gate": "The stars on the far side are not ours",
	"w_column": "Carved by hands three times the size of yours",
	"w_crystal": "The Worldroot's sap, set hard as glass",
	"w_pylon": "Still trying to raise a shield",
	"w_obelisk": "Its runes turn as you watch",
}
## Light over each wonder, also its colour on the map.
const COLORS := {"w_throne": Color(1.0, 0.78, 0.38), "w_worldroot": Color(0.4, 1.0, 0.85),
	"w_dreadnought": Color(1.0, 0.35, 0.28), "w_gate": Color(0.78, 0.5, 1.0)}

## The boss of each wonder: [name, kit model, scale, tint, glow, drops].
const BOSSES := {
	"w_throne": ["The Throne Warden", "Bull", 2.5, Color(0.3, 0.24, 0.18), false, [["gold_idol", 3], ["silver_chalice", 2], ["hide", 6]]],
	"w_worldroot": ["The Elder Hart", "Stag", 2.2, Color(0.2, 0.55, 0.5), true, [["moonpearl", 3], ["aether_crystal", 8], ["rune_tablet", 2]]],
	"w_dreadnought": ["Hive Matriarch", "Alien_Scolitex", 3.0, Color(0.6, 0.12, 0.1), true, [["data_core", 3], ["void_gem", 2], ["power_cell", 6]]],
	"w_gate": ["The Gatekeeper", "Alien_Cyclop", 2.8, Color(0.45, 0.2, 0.7), true, [["void_gem", 3], ["moonpearl", 2], ["aether_crystal", 6]]],
}
const BOSS_HP := 1500.0
const BOSS_BITE := 3.6 ## bite multiplier

static func has(t: String) -> bool:
	return LABELS.has(t)

static func is_centre(t: String) -> bool:
	return NAMES.has(t)

static func label(t: String) -> String:
	return LABELS.get(t, t)

static func lore(t: String) -> String:
	return LORE.get(t, "")

# --- Placement ------------------------------------------------------------------------

## The chunk of a cell that may hold a wonder, and the roll that decides it, or [] if the
## cell holds none.
static func cell_pick(seed: int, wx: int, wz: int) -> Array:
	if WHash.unit2(seed, wx, wz, 950) > CHANCE:
		return []
	var r := WHash.rng(seed, wx, wz, 951)
	r.randf() # a fresh WHash.rng's first draw is always near 0
	var k := Vector2i(wx * CELL + r.randi_range(2, CELL - 3), wz * CELL + r.randi_range(2, CELL - 3))
	return [k, r]

## Puts a wonder in `chunk` if this is the chosen chunk of its cell and the ground allows.
## Levels the plaza (inside the chunk only, so neighbours still meet it) and returns a
## site dictionary for the generator to keep everything else clear, or {}.
static func place(g: ChunkGenerator, chunk: Dictionary, sites: Array) -> Dictionary:
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var pick := cell_pick(g.seed, int(floor(float(cx) / CELL)), int(floor(float(cz) / CELL)))
	if pick.is_empty() or pick[0] != Vector2i(cx, cz):
		return {}
	var r: RandomNumberGenerator = pick[1]
	const S := ChunkGenerator.SIZE
	var c := Vector2(S * 0.5 + r.randf_range(-3.0, 3.0), S * 0.5 + r.randf_range(-3.0, 3.0))
	var x0 := float(cx * S)
	var z0 := float(cz * S)
	# Dry, fairly level ground with no river, road or settlement on it.
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var n := 0
	for ring in [0.0, PLAZA * 0.5, PLAZA, EDGE - 1.0]:
		var steps := 1 if ring == 0.0 else 12
		for a in steps:
			var q: Vector2 = c + Vector2.from_angle(a * TAU / steps) * ring
			var h := ChunkGenerator.height_at(chunk, q.x, q.y)
			if ChunkGenerator.by_river(chunk, q.x, q.y) or ChunkGenerator.road_at(chunk, q.x, q.y) > 0.0:
				return {}
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if ring <= PLAZA:
				sum += h
				n += 1
	if hi - lo > 14.0 or lo < ChunkGenerator.WATER_LEVEL + 1.0:
		return {}
	var wc := Vector2(x0, z0) + c
	for s in sites:
		if wc.distance_to(s["center"]) < float(s.get("outer", s["inner"])) + CLEAR + 10.0:
			return {}
	var w := ChunkGenerator.weights_at(chunk, c.x, c.y)
	var era := WorldField.dominant(w)
	var t: String = "w_gate" if r.randf() < GATE_CHANCE else BY_ERA[era]
	var yaw := r.randf() * TAU
	_level(g, chunk, c, sum / n + 0.2)
	var put := func(type: String, q: Vector2, face: float, st := {}) -> void:
		var p: Vector2 = c + q.rotated(-yaw)
		g._add(chunk, type, era, p.x, p.y, yaw + face, 1.0, st)
	put.call(t, Vector2.ZERO, 0.0)
	for i in 8:
		var a := (i + 0.5) * TAU / 8.0
		put.call(PILLAR[t], Vector2.from_angle(a) * RING, -a + PI * 0.5)
	# The vault in front of the centrepiece, sealed by its boss; three lesser hoards.
	var boss_id := "%d_%d_wboss" % [cx, cz]
	var origin := {"chunk": Vector2i(cx, cz), "era": era, "how": "found"}
	var vault_loot := ItemDB.roll_loot(era, r, origin, 1.0)
	vault_loot.append_array(treasure(era, r, origin, Rarity.LEGENDARY, 2))
	vault_loot.append(treasure(era, r, origin, Rarity.EPIC, 1)[0])
	vault_loot.append({"type": "_marks", "qty": r.randi_range(1500, 3000)})
	var front: float = FRONT[t]
	put.call(Eras.CACHE_TYPES[era], Vector2(0, front), PI, {"loot": vault_loot, "opened": false, "wonder": t, "seal": boss_id})
	for i in 3:
		var a := PI * 0.5 + (i - 1) * 2.1 + r.randf_range(-0.2, 0.2)
		var q := Vector2.from_angle(a) * (RING - 3.0)
		var loot := ItemDB.roll_loot(era, r, origin, 0.9)
		loot.append_array(treasure(era, r, origin, Rarity.EPIC, 1))
		put.call(Eras.CACHE_TYPES[era] if r.randf() < 0.7 else Eras.CACHE_TYPES[r.randi() % Eras.COUNT], q, r.randf() * TAU, {"loot": loot, "opened": false, "wonder": t})
	# Elite guards round the ring and the boss before the vault.
	if not chunk.has("guards"):
		chunk["guards"] = []
	var guards := 4 + r.randi_range(0, 2)
	for i in guards:
		var a := i * TAU / guards + r.randf_range(-0.2, 0.2)
		var p := c + (Vector2.from_angle(a) * r.randf_range(9.0, 12.0)).rotated(-yaw)
		chunk["guards"].append({"id": "%d_%d_w%d" % [cx, cz, i], "lx": p.x, "lz": p.y, "tier": 4 + int(r.randf() < 0.4), "era": era})
	var bp := c + Vector2(0, front + 3.0).rotated(-yaw)
	chunk["guards"].append({"id": boss_id, "lx": bp.x, "lz": bp.y, "tier": 100 + TYPES.find(t), "era": era})
	chunk["wonder"] = {"t": t, "lx": c.x, "lz": c.y, "era": era, "boss": boss_id}
	return {"center": wc, "inner": CLEAR, "outer": CLEAR, "wonder": t}

## Flattens the plaza to `h`, easing back into the land by EDGE.
static func _level(g: ChunkGenerator, chunk: Dictionary, c: Vector2, h: float) -> void:
	const R := ChunkGenerator.RES
	var hs: PackedFloat32Array = chunk["heights"]
	for j in range(maxi(1, int(c.y - EDGE) - 1), mini(R - 1, int(c.y + EDGE) + 2)):
		for i in range(maxi(1, int(c.x - EDGE) - 1), mini(R - 1, int(c.x + EDGE) + 2)):
			var d := Vector2(i, j).distance_to(c)
			if d < EDGE:
				var k := j * R + i
				hs[k] = lerpf(hs[k], h, 1.0 - smoothstep(PLAZA, EDGE, d))
	chunk["heights"] = hs
	# The plaza is paved (v4 worlds keep a road surface mask).
	if g.towns and not chunk.has("road"):
		var empty := PackedByteArray()
		empty.resize(R * R)
		chunk["road"] = empty
	if chunk.has("road"):
		var rb: PackedByteArray = chunk["road"]
		for j in R:
			for i in R:
				var d := Vector2(i, j).distance_to(c)
				if d < PLAZA:
					rb[j * R + i] = maxi(rb[j * R + i], int(255.0 * (1.0 - smoothstep(PLAZA - 6.0, PLAZA - 1.0, d))))
		chunk["road"] = rb

## `n` pieces of gear of at least rank `floor`, from everything the era has.
static func treasure(era: int, r: RandomNumberGenerator, origin: Dictionary, floor_rank: int, n: int) -> Array:
	var out: Array = []
	# Wonders keep only gear worth the trip: no cloth caps or stone axes.
	var pool: Array = ItemDB.GEAR_LOOT[era].filter(func(t): return int(ItemDB.def(t).get("value", 0)) >= 40)
	for i in n:
		var it := ItemDB.make(pool[r.randi() % pool.size()], 1, r.randf_range(1.2, 1.5), origin)
		var rank := maxi(floor_rank, Rarity.roll(r, 1.0))
		if floor_rank >= Rarity.LEGENDARY and r.randf() < 0.3:
			rank = Rarity.MYTHIC
		Rarity.apply(it, rank, r)
		out.append(it)
	return out

## True while the boss that seals this vault still lives.
static func sealed(chunk: Dictionary, o: Dictionary) -> bool:
	var id := String(o["st"].get("seal", ""))
	return id != "" and not chunk.get("fauna_dead", {}).has(id)

## What the map knows of a chunk's wonder: {t, x, z, era, cleared} in world space, or {}.
static func of_chunk(chunk: Dictionary) -> Dictionary:
	if not chunk.has("wonder"):
		return {}
	var w: Dictionary = chunk["wonder"]
	var cleared: bool = chunk.get("fauna_dead", {}).has(w["boss"])
	if cleared:
		for o in chunk["objects"]:
			if String(o["st"].get("seal", "")) != "" and not o["st"].get("opened", false):
				cleared = false
	return {"t": w["t"], "x": chunk["cx"] * ChunkGenerator.SIZE + float(w["lx"]), "z": chunk["cz"] * ChunkGenerator.SIZE + float(w["lz"]),
		"era": w["era"], "cleared": cleared}

# --- Meshes ---------------------------------------------------------------------------

static var _beams := {}
static var _portal: Material

## The mesh of a wonder piece. `solid` leaves out the light (for collision).
static func build(t: String, solid := false) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(t)
	var I := Transform3D.IDENTITY
	var out: ArrayMesh = null
	match t:
		"w_throne": _throne(k, r)
		"w_worldroot": _worldroot(k, r)
		"w_dreadnought": out = _dreadnought(k, r)
		"w_gate": _gate(k, r, solid)
		"w_column":
			k.box("titan_glow", I.translated(Vector3(0, 0.3, 0)), Vector3(2.0, 0.6, 2.0))
			k.box("titan_stone", I.translated(Vector3(0, -1.5, 0)), Vector3(2.0, 3.0, 2.0))
			k.cylinder("titan_stone", I.translated(Vector3(0, 0.6, 0)), 0.62, 0.52, 6.2, 10, false, 0.03, 3)
			k.cylinder("gold", I.translated(Vector3(0, 2.4, 0)), 0.66, 0.66, 0.18, 10, false)
			k.box("titan_stone", I.translated(Vector3(0, 6.95, 0)), Vector3(1.6, 0.5, 1.6))
			k.cylinder("iron", I.translated(Vector3(0, 7.2, 0)), 0.5, 0.65, 0.5, 8)
			k.sphere("glow_warm", I.translated(Vector3(0, 7.75, 0)), 0.36, 5, 8, 0.25)
			k.sphere("moss", I.translated(Vector3(0.5, 0.65, 0.4)), 0.5, 4, 7, 0.25, 0.4)
		"w_crystal":
			k.sphere("root_bark", I.translated(Vector3(0, 0.1, 0)), 1.3, 5, 9, 0.3, 0.45)
			k.crystal("crystal_violet", I, 0.6, 5.0, 6, 0.3)
			for i in 4:
				var a := i * TAU / 4.0 + 0.4
				var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.45)
				k.crystal("crystal", Transform3D(b, Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.7)), 0.28, r.randf_range(1.6, 2.6))
			k.sphere("glow_teal", I.translated(Vector3(0, 0.5, 0)), 0.32, 4, 6)
		"w_pylon":
			k.box("starfall_glass", I.translated(Vector3(0, -1.0, 0)), Vector3(2.2, 2.6, 2.2))
			k.box("panel", I.translated(Vector3(0, 0.3, 0)), Vector3(2.0, 0.6, 2.0))
			k.box("metal_dark", I.translated(Vector3(0, 3.6, 0)), Vector3(1.0, 6.0, 1.0))
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				k.box("glow_cyan", Transform3D(b, b * Vector3(0, 3.6, 0.51)), Vector3(0.12, 5.0, 0.03))
			k.box("panel", I.translated(Vector3(0, 6.75, 0)), Vector3(1.6, 0.3, 1.6))
			k.sphere("glow_red", I.translated(Vector3(0, 7.15, 0)), 0.22, 4, 6)
		"w_obelisk":
			k.box("void_stone", I.translated(Vector3(0, -1.0, 0)), Vector3(1.8, 2.4, 1.8))
			k.box("rune_stone", I.translated(Vector3(0, 0.25, 0)), Vector3(1.6, 0.5, 1.6))
			k.cylinder("void_stone", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.5, 0)), 0.8, 0.45, 6.0, 4, false)
			k.cylinder("void_stone", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 6.5, 0)), 0.45, 0.0, 1.0, 4, false)
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				for row in 4:
					k.box("glow_violet", Transform3D(b, b * Vector3(0, 1.3 + row * 1.25, 0.58 - row * 0.045)), Vector3(0.3, 0.5, 0.03))
	if is_centre(t):
		_vault_floor(k, FRONT[t])
	if not solid and is_centre(t):
		_beam(k, t)
	return k.commit(_mat, out)

static func _mat(name: String) -> Material:
	if name.begins_with("beam_"):
		return _beam_mat(name.trim_prefix("beam_"))
	if name == "portal":
		return _portal_mat()
	return Materials.get_mat(name)

## The void-stone floor the vault and its keeper stand on, ringed with light.
static func _vault_floor(k: MeshKit, front: float) -> void:
	var at := Transform3D.IDENTITY.translated(Vector3(0, -0.4, front + 1.5))
	k.cylinder("void_stone", at, 4.4, 4.2, 0.5, 24)
	k.cylinder("glow_violet", at.translated(Vector3(0, 0.5, 0)), 4.22, 4.22, 0.03, 24)
	k.cylinder("void_stone", at.translated(Vector3(0, 0.5, 0)), 4.0, 4.0, 0.04, 24)

## A tall, soft column of light, brightest low down, so the wonder can be found from afar.
static func _beam(k: MeshKit, t: String) -> void:
	var I := Transform3D.IDENTITY
	var top: float = {"w_throne": 14.0, "w_worldroot": 30.0, "w_dreadnought": 10.0, "w_gate": 16.0}[t]
	k.cylinder("beam_" + t, I.translated(Vector3(0, top, 0)), 1.1, 0.5, 220.0, 10, false)
	k.cylinder("beam_" + t, I.translated(Vector3(0, top, 0)), 2.4, 1.4, 60.0, 12, false)

static func _beam_mat(t: String) -> Material:
	if _beams.has(t):
		return _beams[t]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	var c: Color = COLORS.get(t, Color.WHITE)
	m.albedo_color = Color(c.r, c.g, c.b, 0.16)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 6.0
	m.distance_fade_max_distance = 30.0
	_beams[t] = m
	return m

static func _portal_mat() -> Material:
	if _portal != null:
		return _portal
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.7, 0.45, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + r * 9.0 - TIME * 1.6) * 0.5 + 0.5;
	float rim = smoothstep(0.75, 1.0, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float core = (1.0 - r) * 0.5;
	float v = (swirl * 0.45 + core) * (1.0 - smoothstep(0.96, 1.0, r)) + rim * 1.5;
	ALBEDO = tint.rgb * v * 1.6;
	ALPHA = clamp(v, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_portal = m
	return m

## A cylinder from a to b (MeshKit cylinders run up local y).
static func _limb(k: MeshKit, mat: String, a: Vector3, b: Vector3, ra: float, rb: float, segs := 8) -> void:
	var d := b - a
	var up := d.normalized()
	var basis := Basis.IDENTITY
	if absf(up.y) < 0.999:
		basis = Basis(Vector3.UP.cross(up).normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	k.cylinder(mat, Transform3D(basis, a), ra, rb, d.length(), segs, true)

static func _throne(k: MeshKit, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	# The dais: three broad steps on a deep footing.
	k.box("void_stone", I.translated(Vector3(0, -2.0, 0)), Vector3(13.0, 4.0, 13.0))
	k.box("titan_stone", I.translated(Vector3(0, 0.3, 0)), Vector3(12.6, 0.6, 12.6))
	k.box("titan_stone", I.translated(Vector3(0, 0.9, -0.6)), Vector3(10.4, 0.6, 10.4))
	k.box("titan_glow", I.translated(Vector3(0, 1.5, -1.2)), Vector3(8.4, 0.6, 8.2))
	# The throne itself.
	k.box("titan_stone", I.translated(Vector3(0, 3.0, -1.8)), Vector3(6.4, 2.4, 4.0))
	k.box("titan_glow", I.translated(Vector3(0, 7.6, -4.2)), Vector3(7.0, 11.0, 1.4))
	k.cylinder("gold", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 12.0, -3.45)), 1.4, 1.4, 0.2, 16)
	for x in [-3.6, 3.6]:
		k.box("titan_stone", I.translated(Vector3(x, 4.8, -1.8)), Vector3(1.2, 1.2, 4.2))
		k.box("titan_stone", I.translated(Vector3(x, 3.0, -0.2)), Vector3(1.2, 2.4, 1.0))
		k.sphere("gold", I.translated(Vector3(x, 5.6, 0.2)), 0.45, 5, 8)
		k.cylinder("titan_stone", I.translated(Vector3(x * 0.95, 13.1, -4.2)), 0.55, 0.0, 2.0, 6)
	# The king: legs, a broad body, arms on a sword planted before him.
	for s in [-1.0, 1.0]:
		_limb(k, "titan_stone", Vector3(s * 1.2, 4.6, -2.2), Vector3(s * 1.25, 4.6, 1.2), 0.95, 0.85)
		_limb(k, "titan_stone", Vector3(s * 1.25, 4.4, 1.3), Vector3(s * 1.3, 1.8, 1.6), 0.8, 0.7)
		k.box("titan_stone", I.translated(Vector3(s * 1.3, 2.15, 2.2)), Vector3(1.3, 0.7, 2.2))
	k.box("titan_stone", I.translated(Vector3(0, 7.4, -2.4)), Vector3(4.6, 5.2, 2.6))
	k.box("cloth", I.translated(Vector3(0, 6.4, -1.05)), Vector3(4.2, 3.4, 0.08))
	k.box("gold", I.translated(Vector3(0, 5.0, -1.05)), Vector3(4.7, 0.4, 2.8))
	for s in [-1.0, 1.0]:
		k.sphere("titan_stone", I.translated(Vector3(s * 2.75, 9.6, -2.4)), 1.25, 6, 9)
		_limb(k, "titan_stone", Vector3(s * 2.9, 9.4, -2.2), Vector3(s * 2.4, 7.0, 0.4), 0.7, 0.6)
		_limb(k, "titan_stone", Vector3(s * 2.4, 7.0, 0.4), Vector3(s * 0.6, 8.0, 2.9), 0.6, 0.5)
		k.sphere("titan_stone", I.translated(Vector3(s * 0.55, 8.0, 3.0)), 0.55, 5, 7)
	k.cylinder("titan_stone", I.translated(Vector3(0, 9.9, -2.4)), 0.8, 0.75, 0.9, 10)
	k.sphere("titan_stone", I.translated(Vector3(0, 11.6, -2.3)), 1.35, 8, 10, 0.04, 1.1)
	k.box("titan_stone", Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 10.6, -1.25)), Vector3(1.3, 1.5, 0.6))
	k.cylinder("gold", I.translated(Vector3(0, 12.55, -2.3)), 1.15, 1.25, 0.6, 12, false)
	for i in 8:
		var a := i * TAU / 8.0
		k.cylinder("gold", I.translated(Vector3(cos(a) * 1.2, 13.1, -2.3 + sin(a) * 1.2)), 0.16, 0.0, 0.7, 4)
	k.sphere("glow_red", I.translated(Vector3(0, 12.9, -1.1)), 0.18, 4, 6)
	# The sword, point in the dais.
	k.box("iron", I.translated(Vector3(0, 4.9, 3.0)), Vector3(0.7, 6.2, 0.16))
	k.box("gold", I.translated(Vector3(0, 8.1, 3.0)), Vector3(2.8, 0.35, 0.45))
	k.cylinder("timber", I.translated(Vector3(0, 8.25, 3.0)), 0.18, 0.18, 1.3, 8)
	k.sphere("gold", I.translated(Vector3(0, 9.7, 3.0)), 0.32, 5, 8)
	# Braziers and moss of ages.
	for x in [-5.2, 5.2]:
		k.cylinder("iron", I.translated(Vector3(x, 0.6, 4.6)), 0.18, 0.18, 2.0, 6)
		k.cylinder("iron", I.translated(Vector3(x, 2.6, 4.6)), 0.3, 0.75, 0.5, 10)
		k.sphere("glow_warm", I.translated(Vector3(x, 3.15, 4.6)), 0.55, 5, 8, 0.3)
	for i in 9:
		var p := Vector3(r.randf_range(-3.5, 3.5), r.randf_range(2.0, 11.0), r.randf_range(-4.8, -1.5))
		k.sphere("moss", I.translated(p), r.randf_range(0.3, 0.7), 4, 7, 0.3, 0.35)

static func _worldroot(k: MeshKit, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("root_bark", I.translated(Vector3(0, -3.0, 0)), 3.8, 3.4, 3.0, 16, false, 0.12, 2)
	k.cylinder("root_bark", I, 3.4, 1.5, 26.0, 16, false, 0.18, 8)
	# Buttress roots arch out and dive into the plaza.
	for i in 9:
		var a := i * TAU / 9.0 + r.randf_range(-0.15, 0.15)
		var d := Vector3(cos(a), 0, sin(a))
		var reach := r.randf_range(7.5, 10.0)
		var prev := d * 2.6 + Vector3(0, 3.2, 0)
		for s in 6:
			var u := (s + 1) / 6.0
			var q := d * (2.6 + u * reach) + Vector3(0, 3.2 * (1.0 - u) + sin(u * PI) * 1.4 - u * 0.8, 0)
			_limb(k, "root_bark", prev, q, 1.1 - u * 0.5, 1.0 - u * 0.55, 7)
			prev = q
		k.sphere("glow_violet", I.translated(d * (3.5 + reach * 0.5) + Vector3(r.randf_range(-0.8, 0.8), 0.15, r.randf_range(-0.8, 0.8))), 0.25, 4, 6)
		k.sphere("cap_violet", I.translated(d * (3.2 + reach * 0.4) + Vector3(0.6, 0.3, 0.6)), 0.55, 5, 8, 0.1, 0.4, Color.WHITE, true)
	# Boughs and the crown, hung with lantern fruit.
	var crowns: Array = []
	for i in 7:
		var a := i * TAU / 7.0 + 0.3
		var y := 17.0 + (i % 3) * 3.0
		var end := Vector3(cos(a) * 9.5, y + 4.5, sin(a) * 9.5)
		_limb(k, "root_bark", Vector3(cos(a) * 1.2, y, sin(a) * 1.2), end, 1.0, 0.45, 7)
		crowns.append(end)
	crowns.append(Vector3(0, 29.0, 0))
	for c in crowns:
		var rad := r.randf_range(5.0, 6.5)
		k.sphere("leaf", I.translated(c), rad * 0.75, 6, 10, 0.35, 0.7, Color(0.55, 0.75, 0.7))
		ObjectLibrary._leaf_cards(k, "leaf_card", c, rad, 40, r, 2.4)
		for n in 4:
			var p: Vector3 = c + Vector3(r.randf_range(-rad, rad) * 0.7, -rad * 0.55 - r.randf_range(0.5, 2.0), r.randf_range(-rad, rad) * 0.7)
			k.cylinder("stem", I.translated(p), 0.03, 0.03, c.y - p.y - rad * 0.4, 4, false)
			k.sphere("glow_teal", I.translated(p), 0.35, 5, 7)
	for i in 6:
		var a := r.randf() * TAU
		k.crystal("crystal_violet", Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.4), Vector3(cos(a) * 4.0, 0, sin(a) * 4.0)), 0.4, r.randf_range(1.8, 3.2))
	k.box("glow_teal", Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 3.35)), Vector3(1.4, 2.6, 0.05))

static func _dreadnought(k: MeshKit, r: RandomNumberGenerator) -> ArrayMesh:
	var I := Transform3D.IDENTITY
	var hull := Transform3D(Basis.from_euler(Vector3(0.18, 0.0, 0.22)).scaled(Vector3.ONE * 3.4), Vector3(0, 1.0, -1.0))
	var out := Landmark._merge(["ships/Striker"], [hull])
	# The furrow it ploughed, scattered plating, fires and a broken mast.
	for i in 10:
		var a := r.randf() * TAU
		var d := r.randf_range(7.0, 14.0)
		k.sphere("starfall_glass", I.translated(Vector3(cos(a) * d, -0.4, sin(a) * d)), r.randf_range(1.2, 2.4), 5, 8, 0.3, 0.4)
	for i in 14:
		var a := r.randf() * TAU
		var d := r.randf_range(6.0, 14.0)
		var b := Basis.from_euler(Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5)))
		k.box("metal_dark" if i % 3 else "rust", Transform3D(b, Vector3(cos(a) * d, 0.2, sin(a) * d)), Vector3(r.randf_range(1.0, 3.0), 0.1, r.randf_range(0.8, 2.0)))
	for i in 5:
		var p := Vector3(r.randf_range(-6, 6), 0.3, r.randf_range(-10, 8))
		k.sphere("glow_red", I.translated(p), r.randf_range(0.3, 0.6), 4, 6, 0.4)
		k.sphere("glow_warm", I.translated(p + Vector3(0, 0.4, 0)), 0.25, 4, 6, 0.4)
	_limb(k, "metal_dark", Vector3(2.5, 0.0, 6.0), Vector3(6.5, 9.0, 4.0), 0.25, 0.15)
	k.sphere("glow_red", I.translated(Vector3(6.5, 9.2, 4.0)), 0.3, 4, 6)
	k.box("glow_cyan", Transform3D(Basis.from_euler(Vector3(0.18, 0.0, 0.22)), Vector3(0, 2.6, 6.5)), Vector3(3.0, 0.4, 0.05))
	return out

static func _gate(k: MeshKit, r: RandomNumberGenerator, solid: bool) -> void:
	var I := Transform3D.IDENTITY
	k.cylinder("flagstone", I.translated(Vector3(0, -3.0, 0)), 9.2, 9.0, 3.6, 24)
	k.cylinder("void_stone", I.translated(Vector3(0, 0.6, 0)), 7.5, 7.0, 0.4, 24)
	for x in [-5.8, 5.8]:
		k.box("gate_metal", I.translated(Vector3(x, 1.5, 0)), Vector3(2.6, 3.0, 3.0))
	# The ring: twenty rune stones on a circle standing across z, the keystone in gold.
	const RAD := 7.0
	const CY := 8.2
	for i in 20:
		var a := i * TAU / 20.0
		var p := Vector3(cos(a) * RAD, CY + sin(a) * RAD, 0)
		var b := Basis(Vector3.BACK, a)
		k.box("gold" if i == 5 else "gate_metal", Transform3D(b, p), Vector3(1.5, 2.5, 1.8))
		k.box("glow_violet", Transform3D(b, p + Vector3(0, 0, 0.92)), Vector3(0.3, 1.2, 0.04))
		k.box("glow_violet", Transform3D(b, p - Vector3(0, 0, 0.92)), Vector3(0.3, 1.2, 0.04))
	if not solid:
		k.card("portal", I, Vector3(0, CY, 0), Basis.IDENTITY, 12.6, 12.6)
	for i in 6:
		var a := r.randf() * TAU
		k.crystal("crystal_violet", Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.5), Vector3(cos(a) * 8.5, 0.6, sin(a) * 8.5)), 0.35, r.randf_range(1.2, 2.4))
	for i in 5:
		var p := Vector3(r.randf_range(-6, 6), CY + RAD + r.randf_range(2.0, 5.0), r.randf_range(-3, 3))
		k.sphere("stone_dark", Transform3D(Basis.from_euler(Vector3(r.randf(), r.randf(), r.randf())), p), r.randf_range(0.4, 0.9), 4, 6, 0.4)
