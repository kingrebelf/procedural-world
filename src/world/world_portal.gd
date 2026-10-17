class_name WorldPortal
## Ancient portals between worlds: a ring of rune stones on a dais round a violet light,
## found only far out in the high zones (zone level MIN_LEVEL and up), at most one per
## CELL x CELL chunks. Stepping through one takes you to any other world linked to this
## one, human or alien, arriving beside that world's portal; going back brings you out
## of the portal you left by.
##
## A portal's place is a pure function of the seed and the land's broad shape (no chunk
## needed), so the world you travel to knows where its portals stand before any of its
## land has been generated.

const TYPE := "world_portal"
const CELL := 20 ## chunks per side of a portal cell (about 1.3 km)
const CHANCE := 0.75
const MIN_LEVEL := 40 ## zone level a portal needs (Eras.zone_level)
const CLEAR := 9.0 ## nothing else grows or stands this close
const DOOR_Y := 3.6 ## height of the middle of the ring
const DOOR := 2.6 ## radius of the light in the ring
const KEEP_OFF := 70.0 ## from settlements and strongholds

## Where the portal of cell (wx, wz) stands, or Vector2.INF if that cell has none.
static func spot(g: ChunkGenerator, wx: int, wz: int) -> Vector2:
	if WHash.unit2(g.seed, wx, wz, 960) > CHANCE:
		return Vector2.INF
	var r := WHash.rng(g.seed, wx, wz, 961)
	r.randf() # a fresh WHash.rng's first draw is always near 0
	var k := Vector2i(wx * CELL + r.randi_range(2, CELL - 3), wz * CELL + r.randi_range(2, CELL - 3))
	# Never in the chunk a wonder may take.
	var wp := WonderSite.cell_pick(g.seed, int(floor(float(k.x) / WonderSite.CELL)), int(floor(float(k.y) / WonderSite.CELL)))
	if not wp.is_empty() and wp[0] == k:
		k.x += 1
	const S := ChunkGenerator.SIZE
	var p := Vector2(k.x * S + r.randf_range(20.0, S - 20.0), k.y * S + r.randf_range(20.0, S - 20.0))
	if Eras.zone_level(p.x, p.y) < MIN_LEVEL:
		return Vector2.INF
	var h := g.field.height(p.x, p.y)
	if h < ChunkGenerator.WATER_LEVEL + 1.0:
		return Vector2.INF
	if g.rivers and g.field.river_t(p.x, p.y) < WorldField.RIVER_REACH + 8.0:
		return Vector2.INF
	for s in g.settlements_near(p.x - KEEP_OFF, p.y - KEEP_OFF, p.x + KEEP_OFF, p.y + KEEP_OFF):
		if p.distance_to(s["center"]) < float(s["outer"]) + KEEP_OFF * 0.5:
			return Vector2.INF
	for f in g.forts_near(p.x - KEEP_OFF, p.y - KEEP_OFF, p.x + KEEP_OFF, p.y + KEEP_OFF):
		if p.distance_to(f["center"]) < float(f.get("outer", f["inner"])) + 20.0:
			return Vector2.INF
	return p

## Puts this chunk's portal in it, if it has one. Returns a site for the generator to
## keep everything else clear, or {}.
static func place(g: ChunkGenerator, chunk: Dictionary) -> Dictionary:
	if not Eras.themed():
		return {}
	const S := ChunkGenerator.SIZE
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var p := spot(g, int(floor(float(cx) / CELL)), int(floor(float(cz) / CELL)))
	if p == Vector2.INF or int(floor(p.x / S)) != cx or int(floor(p.y / S)) != cz:
		return {}
	var lx := p.x - cx * S
	var lz := p.y - cz * S
	var era := WorldField.dominant(ChunkGenerator.weights_at(chunk, lx, lz))
	var yaw := WHash.unit2(g.seed, cx, cz, 962) * TAU
	g._add(chunk, TYPE, era, lx, lz, yaw, 1.0)
	return {"center": p, "inner": CLEAR, "outer": CLEAR, "portal": true}

## The portal nearest `around` on the current world (searching out to `rings` cells), or
## Vector2.INF if there is none that close.
static func nearest(g: ChunkGenerator, around: Vector2, rings := 6) -> Vector2:
	var span := float(CELL * ChunkGenerator.SIZE)
	var c := Vector2i(int(floor(around.x / span)), int(floor(around.y / span)))
	var best := Vector2.INF
	for ring in rings + 1:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var p := spot(g, c.x + dx, c.y + dz)
				if p != Vector2.INF and p.distance_to(around) < best.distance_to(around):
					best = p
		# Anything a ring further out is at least ring * span away.
		if best != Vector2.INF and best.distance_to(around) < ring * span:
			break
	return best

## Where you come out on a world: beside the portal at `last` (the one you last left it
## by), or the portal nearest its high zones the first time; Vector3.INF if it has none
## within reach. Call with that world applied (Planets.apply).
static func arrival(g: ChunkGenerator, last = null) -> Vector3:
	var p := Vector2.INF
	if last is Vector2:
		p = last
	else:
		# The heart of the high zones: where the land reaches MIN_LEVEL.
		var r := maxf(0.0, (MIN_LEVEL - Eras.base_level) * Eras.LEVEL_STEP)
		p = nearest(g, Vector2(r, 0.0).rotated(WHash.unit2(g.seed, 0, 0, 963) * TAU))
	if p == Vector2.INF:
		return Vector3.INF
	var out := p + Vector2(0, 6.0).rotated(WHash.unit2(g.seed, int(p.x), int(p.y), 964) * TAU)
	return Vector3(out.x, maxf(g.field.height(out.x, out.y), ChunkGenerator.WATER_LEVEL) + 2.0, out.y)

# --- The portal itself ----------------------------------------------------------------

static func build() -> ArrayMesh:
	var k := MeshKit.new(9601)
	var I := Transform3D.IDENTITY
	# A stepped dais reaching well into the ground, so it sits on a slope too.
	k.cylinder("cobble", I.translated(Vector3(0, -2.6, 0)), 4.6, 4.4, 3.0, 16)
	k.cylinder("rune_stone", I.translated(Vector3(0, 0.4, 0)), 3.8, 3.6, 0.35, 16)
	# The ring: rune blocks stood on edge round a door of light.
	const R := 2.9
	const Y := DOOR_Y
	for n in 28:
		var a := TAU * n / 28.0
		k.box("rune_stone", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(cos(a) * R, Y + sin(a) * R, 0)), Vector3(0.62, 0.9, 0.8))
		if n % 4 == 0:
			k.box("glow_violet", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(cos(a) * (R - 0.32), Y + sin(a) * (R - 0.32), 0)), Vector3(0.16, 0.36, 0.84))
	k.cylinder("glow_violet", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, Y, 0)), R - 0.35, R - 0.35, 0.06, 32)
	# Feet of the ring and two leaning guardian stones with crystal caps.
	for sx in [-1.0, 1.0]:
		k.box("rune_stone", I.translated(Vector3(sx * 1.9, 0.9, 0)), Vector3(1.0, 1.1, 1.0))
		var b := Basis(Vector3(0, 0, 1), -sx * 0.12)
		k.cylinder("rune_stone", Transform3D(b, Vector3(sx * 4.1, 0.45, 1.6)), 0.5, 0.32, 3.4, 6)
		k.crystal("glow_cyan", Transform3D(b, Vector3(sx * 4.1 - sx * 0.41, 3.85, 1.6)), 0.22, 0.8)
	return k.commit(Materials.get_mat)
