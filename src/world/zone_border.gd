class_name ZoneBorder
## The edges of a human world's zones, made visible in the land (v16 worlds). Where the
## Medieval lands give way to the Borderlands (zone level 10), the Borderlands to the
## Human frontier (20) and that to the High frontier (40) (ZoneInfo.HUMAN), a line of
## boundary markers runs round the ring, and every road that crosses it passes a
## checkpoint: a signpost, a toll bar and a watchtower at the first line, a boom barrier
## and a guard booth at the later ones, where the outposts are. The road surface changes
## there too (packed earth, then setts, then tarmac: the terrain shader, from rings()),
## and the minimap names the zone you have crossed into (Minimap, ZoneInfo.band).
## Nothing here glows: a human world's lights are lamps and fires.

## Zone levels whose lower edge is marked (ZoneInfo.HUMAN's band edges).
const BANDS := [10, 20, 40]
const GAP := 24.0 ## metres of ring between boundary markers
const NEAR_ROAD := 4.5 ## markers stop this far from a road's edge

const LABELS := {
	"border_stone": "Boundary Stone", "border_post": "Boundary Post",
	"border_sign": "Border Signpost", "border_bar": "Toll Bar",
	"border_barrier": "Checkpoint Barrier", "border_booth": "Guard Booth",
}
## Collision boxes for the solid pieces (the bars and barriers collide as built, so the
## road through them stays open).
const SIZE := {
	"border_stone": Vector3(0.7, 1.5, 0.5), "border_post": Vector3(0.5, 1.3, 0.5),
	"border_sign": Vector3(0.5, 2.8, 0.5), "border_booth": Vector3(3.4, 3.2, 3.0),
}

static func has(t: String) -> bool:
	return LABELS.has(t)

## Pieces that collide with their real geometry (you drive between the posts).
static func open(t: String) -> bool:
	return t == "border_bar" or t == "border_barrier"

## Radii of the marked zone edges on the current world, nearest first; empty off human
## worlds (alien worlds' zones follow their eras, older worlds have none).
static func rings() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if Eras.theme != "human":
		return out
	for lv in BANDS:
		if lv > Eras.base_level and lv <= Eras.max_level():
			out.append((lv - Eras.base_level) * Eras.LEVEL_STEP)
	return out

## The first two rings for the terrain shader's road surfaces (-1 where none).
static func road_rings() -> Vector2:
	var rs := rings()
	return Vector2(rs[0] if rs.size() > 0 else -1.0, rs[1] if rs.size() > 1 else -1.0)

## Which line (index into BANDS) a ring radius belongs to.
static func _band(radius: float) -> int:
	return BANDS.find(Eras.base_level + int(round(radius / Eras.LEVEL_STEP)))

# --- Placement ------------------------------------------------------------------------

## Puts this chunk's share of every zone line through it: markers round the ring and the
## checkpoints where roads cross it (pieces of a neighbour's checkpoint that reach in are
## kept clear). Call before the wilds are placed, so nothing grows through them.
static func place(g: ChunkGenerator, chunk: Dictionary, sites: Array) -> void:
	var rs := rings()
	if rs.is_empty():
		return
	const S := ChunkGenerator.SIZE
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	var mid := Vector2(x0 + S * 0.5, z0 + S * 0.5)
	for R in rs:
		if absf(mid.length() - R) > S * 0.75 + 20.0:
			continue
		var band := _band(R)
		var pieces := checkpoints(g, R, band, Rect2(x0 - 24.0, z0 - 24.0, S + 48.0, S + 48.0))
		for it in pieces:
			var p: Vector2 = it["p"]
			if ChunkGenerator._inside(p, x0, z0):
				var era := Eras.MEDIEVAL if band == 0 else Eras.SCIFI
				g._add(chunk, it["t"], era, p.x - x0, p.y - z0, it["yaw"], 1.0, {})
			else:
				g._reach_in(chunk, it["t"], p, it["yaw"], x0, z0)
		_markers(g, chunk, R, band, sites, pieces)

## The pieces of every checkpoint on ring R whose crossing lies in `area`, as
## {t, p (world), yaw}. Pure function of the world, so each chunk finds the same ones.
static func checkpoints(g: ChunkGenerator, R: float, band: int, area: Rect2) -> Array:
	var out: Array = []
	for rd in g.roads_near(area.position.x, area.position.y, area.end.x, area.end.y):
		var pts := ChunkGenerator.road_pts(rd)
		for i in pts.size() - 1:
			var a := pts[i].length() - R
			var b := pts[i + 1].length() - R
			if (a < 0.0) == (b < 0.0):
				continue
			var x := pts[i].lerp(pts[i + 1], a / (a - b))
			# A crossing in a village moves out along the road to the village's edge (the
			# checkpoint stands at its gate), if that is near enough the line.
			var dir := 1 if b > a else -1
			var at := i if dir > 0 else i + 1
			var moved := 0.0
			while _in_town(g, x) and moved < 90.0:
				var nx := at + dir
				if nx < 0 or nx >= pts.size():
					break
				moved += x.distance_to(pts[nx])
				x = pts[nx]
				at = nx
			if moved >= 90.0 or _in_town(g, x) or at + dir < 0 or at + dir >= pts.size():
				continue
			if not area.has_point(x):
				continue
			# Not on a bridge or a viaduct.
			var ground := g.field.height(x.x, x.y)
			if ground < ChunkGenerator.WATER_LEVEL + 0.6 or g._road_height(rd, x) - ground > ChunkGenerator.ROAD_FILL:
				continue
			if g.rivers and g.field.river_t(x.x, x.y) < WorldField.RIVER_REACH + 1.0:
				continue
			# Outward along the road, and across it.
			var f := (pts[at + dir] - pts[at]).normalized()
			var s := f.orthogonal()
			var yaw := atan2(f.x, f.y) # local +z runs outward
			var hs := WHash.unit2(g.seed, int(x.x), int(x.y), 611) < 0.5
			var side := 1.0 if hs else -1.0
			var w := ChunkGenerator.ROAD_HALF
			if band == 0:
				out.append({"t": "border_bar", "p": x, "yaw": yaw})
				out.append({"t": "border_sign", "p": x - f * 3.5 - s * side * (w + 1.5), "yaw": yaw})
				out.append({"t": "watchtower", "p": x + f * 2.0 + s * side * (w + 8.5), "yaw": yaw - side * PI * 0.5})
			else:
				out.append({"t": "border_barrier", "p": x, "yaw": yaw})
				out.append({"t": "border_sign", "p": x - f * 4.0 - s * side * (w + 1.6), "yaw": yaw})
				out.append({"t": "border_booth", "p": x + f * 1.0 + s * side * (w + 3.4), "yaw": yaw - side * PI * 0.5})
	return out

static func _in_town(g: ChunkGenerator, p: Vector2) -> bool:
	for s in g.settlements_near(p.x - 1.0, p.y - 1.0, p.x + 1.0, p.y + 1.0):
		if p.distance_to(s["center"]) < float(s["outer"]) + 12.0:
			return true
	return false

## Markers every GAP metres of ring R inside the chunk, on dry, open ground off the roads,
## out of villages and buildings. They wander a little off the line, as old ones do.
static func _markers(g: ChunkGenerator, chunk: Dictionary, R: float, band: int, sites: Array, pieces: Array) -> void:
	const S := ChunkGenerator.SIZE
	var x0 := float(int(chunk["cx"]) * S)
	var z0 := float(int(chunk["cz"]) * S)
	var n := maxi(8, int(round(TAU * R / GAP)))
	var step := TAU / n
	var ac := atan2(z0 + S * 0.5, x0 + S * 0.5)
	var span := (S * 0.75 + 4.0) / R
	var plans := ChunkGenerator.keep_out(chunk)
	var t := "border_stone" if band == 0 else "border_post"
	for k in range(int(floor((ac - span) / step)), int(ceil((ac + span) / step)) + 1):
		var i := posmod(k, n)
		var a := (i + 0.5 + (WHash.unit2(g.seed, i, int(R), 612) - 0.5) * 0.3) * step
		var r := R + (WHash.unit2(g.seed, i, int(R), 613) - 0.5) * 1.6
		var p := Vector2(cos(a), sin(a)) * r
		if not ChunkGenerator._inside(p, x0, z0):
			continue
		var lx := p.x - x0
		var lz := p.y - z0
		if ChunkGenerator.height_at(chunk, lx, lz) < ChunkGenerator.WATER_LEVEL + 0.4 or ChunkGenerator.by_river(chunk, lx, lz):
			continue
		if ChunkGenerator.slope_at(chunk, lx, lz) > 0.55 or ChunkGenerator.in_cave(chunk, lx, lz):
			continue
		if g._near_settlement(p.x, p.y, sites, 4.0) or ChunkGenerator.kept_out(plans, lx, lz, 1.0):
			continue
		var off_road := true
		for d in [Vector2.ZERO, Vector2(NEAR_ROAD, 0), Vector2(-NEAR_ROAD, 0), Vector2(0, NEAR_ROAD), Vector2(0, -NEAR_ROAD)]:
			off_road = off_road and ChunkGenerator.road_at(chunk, lx + d.x, lz + d.y) <= 0.0
		for it in pieces:
			off_road = off_road and p.distance_to(it["p"]) > 7.0
		if not off_road:
			continue
		# Facing out across the line, leaning a touch.
		var yaw := PI * 0.5 - a + (WHash.unit2(g.seed, i, int(R), 614) - 0.5) * 0.3
		var era := WorldField.dominant(ChunkGenerator.weights_at(chunk, lx, lz))
		g._add(chunk, t, era, lx, lz, yaw, 0.9 + WHash.unit2(g.seed, i, int(R), 615) * 0.25, {})

# --- Meshes ---------------------------------------------------------------------------

## Meshes face local +z (outward, toward the next zone); they stand on y = 0.
static func build(t: String) -> ArrayMesh:
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var I := Transform3D.IDENTITY
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(t)
	var red := Color(0.55, 0.1, 0.08)
	var white := Color(0.86, 0.84, 0.78)
	var out: ArrayMesh = null
	match t:
		"border_stone":
			# A dressed boundary stone sunk in the turf: a rounded head, a cut line down
			# each face, a painted band and field stones heaped at its foot.
			k.box("castle_stone", Transform3D(Basis(Vector3.FORWARD, r.randf_range(-0.05, 0.05)), Vector3(0, 0.45, 0)), Vector3(0.62, 1.2, 0.36))
			k.cylinder("castle_stone", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.05, -0.18)), 0.31, 0.31, 0.36, 12, true)
			k.box("stone_dark", I.translated(Vector3(0, 0.95, 0.181)), Vector3(0.05, 0.42, 0.01))
			k.box("stone_dark", I.translated(Vector3(0, 0.95, -0.181)), Vector3(0.05, 0.42, 0.01))
			k.box("painted", I.translated(Vector3(0, 0.55, 0)), Vector3(0.64, 0.12, 0.38), red)
			k.sphere("stone", I.translated(Vector3(0.22, -0.04, 0.16)), 0.26, 4, 7, 0.3, 0.5)
			k.sphere("stone", I.translated(Vector3(-0.3, -0.05, -0.15)), 0.22, 4, 6, 0.3, 0.5)
		"border_post":
			# A concrete boundary bollard banded red and white.
			k.cylinder("panel", I.translated(Vector3(0, -0.3, 0)), 0.2, 0.17, 1.55, 10, true, 0.0, 1, Color(0.72, 0.71, 0.68))
			for b in 2:
				k.cylinder("painted", I.translated(Vector3(0, 0.75 + b * 0.24, 0)), 0.185, 0.18, 0.12, 10, false, 0.0, 1, red)
			k.cylinder("panel", I.translated(Vector3(0, -0.3, 0)), 0.42, 0.38, 0.38, 10, true, 0.0, 1, Color(0.62, 0.61, 0.58))
		"border_sign":
			# A tall signpost: one long board pointing on into the next zone, one back the
			# way you came, a lantern hook and a crest board between them.
			k.cylinder("timber", I.translated(Vector3(0, -0.3, 0)), 0.11, 0.09, 3.4, 7)
			k.box("timber", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2.55, 0.62)), Vector3(1.35, 0.3, 0.06))
			k.box("timber", Transform3D(Basis(Vector3.UP, PI * 0.5).rotated(Vector3.UP, PI), Vector3(0, 2.15, -0.55)), Vector3(1.15, 0.26, 0.06))
			k.box("painted", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2.55, 1.18)), Vector3(0.22, 0.3, 0.07), red)
			k.box("painted", I.translated(Vector3(0, 1.55, 0.1)), Vector3(0.5, 0.62, 0.05), white)
			k.box("painted", I.translated(Vector3(0, 1.55, 0.13)), Vector3(0.36, 0.08, 0.01), red)
			k.box("painted", I.translated(Vector3(0, 1.55, 0.13)), Vector3(0.08, 0.46, 0.01), red)
			k.box("iron", I.translated(Vector3(0, 3.0, 0.2)), Vector3(0.04, 0.04, 0.4))
			k.box("stone", I.translated(Vector3(0, 0.1, 0)), Vector3(0.55, 0.3, 0.55))
		"border_bar":
			# A toll bar across the road: stone gateposts either side and a long pole,
			# painted in bands, swung up on its pivot (counterweight end down).
			var w := ChunkGenerator.ROAD_HALF + 1.0
			for x in [-w, w]:
				k.box("castle_stone", I.translated(Vector3(x, 0.55, 0)), Vector3(0.7, 1.7, 0.7))
				k.box("castle_stone", I.translated(Vector3(x, 1.45, 0)), Vector3(0.85, 0.18, 0.85))
				k.sphere("castle_stone", I.translated(Vector3(x, 1.68, 0)), 0.22, 5, 8)
			# The pole: pivot on the left post, raised at 70 degrees.
			var piv := Vector3(-w + 0.55, 1.2, 0)
			var up := Basis(Vector3.BACK, 1.22)
			for b in 8:
				var col := red if b % 2 == 0 else white
				k.box("painted", Transform3D(up, piv + up * Vector3(0.45 + b * 0.82, 0, 0)), Vector3(0.82, 0.14, 0.14), col)
			k.box("iron", Transform3D(up, piv + up * Vector3(-0.55, 0, 0)), Vector3(0.7, 0.3, 0.3))
			k.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), piv + Vector3(0, 0, -0.25)), 0.07, 0.07, 0.5, 6)
			# The rest the pole drops onto, and a crest on the far post.
			k.box("timber", I.translated(Vector3(w - 0.55, 1.0, 0)), Vector3(0.12, 0.5, 0.18))
			k.box("painted", I.translated(Vector3(w, 1.15, 0.36)), Vector3(0.5, 0.6, 0.04), white)
			k.box("painted", I.translated(Vector3(w, 1.15, 0.385)), Vector3(0.1, 0.48, 0.01), red)
		"border_barrier":
			# A steel boom on a concrete pier, raised, with jersey blocks either side and a
			# stop sign facing the road out.
			var w := ChunkGenerator.ROAD_HALF + 1.0
			for x in [-w - 0.7, w + 0.7]:
				for z in [-1.5, 1.5]:
					k.box("panel", I.translated(Vector3(x, 0.4, z)), Vector3(0.6, 0.85, 1.9), Color(0.7, 0.69, 0.66))
					k.box("panel", I.translated(Vector3(x, 0.9, z)), Vector3(0.3, 0.2, 1.9), Color(0.7, 0.69, 0.66))
			k.box("panel", I.translated(Vector3(-w, 0.6, 0)), Vector3(0.7, 1.4, 0.7), Color(0.5, 0.5, 0.48))
			var piv := Vector3(-w + 0.2, 1.4, 0)
			var up := Basis(Vector3.BACK, 1.3)
			for b in 10:
				var col := Color(0.82, 0.62, 0.08) if b % 2 == 0 else Color(0.08, 0.08, 0.08)
				k.box("painted", Transform3D(up, piv + up * Vector3(0.35 + b * 0.7, 0, 0)), Vector3(0.7, 0.12, 0.12), col)
			k.box("metal_dark", Transform3D(up, piv + up * Vector3(-0.4, 0, 0)), Vector3(0.6, 0.35, 0.35))
			k.cylinder("metal_dark", I.translated(Vector3(w + 0.1, 0.0, -0.6)), 0.05, 0.05, 2.4, 6)
			k.cylinder("painted", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(w + 0.1, 2.15, -0.55)), 0.38, 0.38, 0.04, 8, true, 0.0, 1, Color(0.62, 0.06, 0.05))
			k.box("painted", Transform3D(Basis.IDENTITY, Vector3(w + 0.1, 2.15, -0.5)), Vector3(0.5, 0.1, 0.02), white)
		"border_booth":
			# A prefab guard booth on a slab (kit walls, a 4 m cell at 0.75): windows on the
			# road (+z) and down it, a flat roof, an unlit lamp on a pole, sandbags.
			k.box("panel", I.translated(Vector3(0, 0.08, 0)), Vector3(3.6, 0.3, 3.4), Color(0.66, 0.65, 0.62))
			out = BuildCatalog.merge_models([
				["scifi/WallAstra_Straight_Window", 90, Vector3(0, 0.23, 0), 0.75],
				["scifi/WallAstra_Straight", -90, Vector3(0, 0.23, 0), 0.75],
				["scifi/WallAstra_Straight", 0, Vector3(0, 0.23, 0), 0.75],
				["scifi/WallAstra_Straight_Flat_Window", 180, Vector3(0, 0.23, 0), 0.75],
				["scifi/Prop_Computer", 180, Vector3(0.3, 0.23, 0.9), 0.8],
			])
			k.box("metal_dark", I.translated(Vector3(0, 2.52, 0)), Vector3(3.3, 0.14, 3.3))
			k.cylinder("metal_dark", I.translated(Vector3(1.5, 0.2, -1.3)), 0.06, 0.05, 4.2, 6)
			k.box("metal_dark", I.translated(Vector3(1.5, 4.35, -1.05)), Vector3(0.3, 0.18, 0.5))
			k.box("glass", I.translated(Vector3(1.5, 4.25, -0.86)), Vector3(0.24, 0.02, 0.12))
			for i in 6:
				k.sphere("plaster", I.translated(Vector3(-1.9 - (i % 2) * 0.05, 0.38 + (i / 2) * 0.22, -1.0 + (i % 3) * 0.7)), 0.3, 4, 7, 0.1, 0.42)
	return k.commit(Materials.get_mat, out)
