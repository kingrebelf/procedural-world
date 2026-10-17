class_name Stronghold
## Walled strongholds out in the wilds: a medieval castle, a ruined fantasy crypt or a
## sci-fi bunker. Towers at the corners, curtain walls with a gate, a keep at the back
## and guards in the courtyard. The harder the stronghold (tier 1 to 3), the more and
## the better the loot in its chests, coffers and supply crates.
##
## Strongholds sit one per CELL x CELL chunks at most, away from settlements and roads,
## on ground flattened like a settlement's.

const CELL := 5
const CHANCE := 0.4
const HALF := 16.0 ## tower centres from the middle
const INNER := 30.0 ## flat ground radius
const OUTER := 42.0

## Piece types per era: [wall, tower, gate, keep].
const PIECES := [
	["castle_wall", "castle_tower", "castle_gate", "castle_keep"],
	["crypt_wall", "crypt_tower", "crypt_gate", "crypt_keep"],
	["bunker_wall", "bunker_tower", "bunker_gate", "bunker_keep"],
]
const NAMES := ["Castle", "Ruined Crypt", "Bunker"]
const LABELS := {
	"castle_wall": "Castle Wall", "castle_tower": "Castle Tower", "castle_gate": "Castle Gate", "castle_keep": "Castle Keep",
	"crypt_wall": "Crypt Wall", "crypt_tower": "Crypt Tower", "crypt_gate": "Crypt Gate", "crypt_keep": "Mausoleum",
	"bunker_wall": "Bunker Wall", "bunker_tower": "Bunker Tower", "bunker_gate": "Bunker Gate", "bunker_keep": "Command Block",
}

static func has(t: String) -> bool:
	return LABELS.has(t)

## Castle walls and towers come in a few builds (mesh key "<type>~var<n>"), picked by
## where each stands, so a curtain wall is not one section and one tower over and over.
const VAR := "~var"
const VARIANTS := {"castle_wall": 3, "castle_tower": 4}

static func variant_key(o: Dictionary) -> String:
	if not o.has("p"):
		return o["t"] # a type alone (a footprint lookup): the plain build
	var p: Vector3 = o["p"]
	var h := absi(WHash.combine(int(round(p.x * 4.0)), int(round(p.z * 4.0))))
	return "%s%s%d" % [o["t"], VAR, h % int(VARIANTS[o["t"]])]

# --- Placement ---------------------------------------------------------------

## The stronghold of a cell, or {} if it has none. `g` supplies terrain, settlements
## and roads.
static func at_cell(g: ChunkGenerator, cx: int, cz: int) -> Dictionary:
	var r := WHash.rng(g.seed, cx, cz, 901)
	if r.randf() > CHANCE:
		return {}
	var span := CELL * ChunkGenerator.SIZE
	var c := Vector2((cx + r.randf_range(0.25, 0.75)) * span, (cz + r.randf_range(0.25, 0.75)) * span)
	var yaw := r.randf() * TAU
	var tier := 1 + int(r.randf() * 2.999)
	var w := g.field.era_weights(c.x, c.y)
	var era := WorldField.dominant(w)
	if w[era] < 0.8:
		return {}
	# Level enough ground, above water, clear of settlements and roads.
	var sites := g.settlements_near(c.x - 140, c.y - 140, c.x + 140, c.y + 140)
	for s in sites:
		if c.distance_to(s["center"]) < float(s["outer"]) + OUTER + 30.0:
			return {}
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for k in 9:
		var p := c + Vector2.from_angle(k * TAU / 8.0) * (INNER if k < 8 else 0.0)
		var h := g.field.height(p.x, p.y, g.field.era_weights(p.x, p.y))
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	if hi - lo > 9.0 or lo < ChunkGenerator.WATER_LEVEL + 1.5:
		return {}
	if g.towns:
		for rd in g.roads_near(c.x - OUTER - 10, c.y - OUTER - 10, c.x + OUTER + 10, c.y + OUTER + 10):
			var pts: PackedVector2Array = rd["pts"]
			for p in pts:
				if p.distance_to(c) < OUTER + 8.0:
					return {}
	return {"center": c, "yaw": yaw, "tier": tier, "era": era, "target_h": sum / 9.0 + 0.3,
		"inner": INNER, "outer": OUTER, "cx": cx, "cz": cz, "fort": true}

## Everything the stronghold contains, in world coordinates.
static func layout(g: ChunkGenerator, f: Dictionary) -> Array:
	var c: Vector2 = f["center"]
	var yaw: float = f["yaw"]
	var era: int = f["era"]
	var tier: int = f["tier"]
	var pc: Array = PIECES[era]
	var r := WHash.rng(g.seed, f["cx"], f["cz"], 902)
	var items: Array = []
	var put := func(t: String, q: Vector2, face: float, st := {}) -> void:
		items.append({"t": t, "p": c + q.rotated(-yaw), "yaw": yaw + face, "st": st})
	for sx: float in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# Turned so the door, near one corner of the tower's front, opens on the courtyard.
			var turn := (PI / 2.0 if sz > 0.0 else 0.0) if sx < 0.0 else (PI if sz > 0.0 else -PI / 2.0)
			put.call(pc[1], Vector2(sx, sz) * HALF, turn, {"tier": tier})
	# Walls: three 8 m sections per side, the gate in the middle of the front (+z).
	for side in 4:
		var face := side * PI / 2.0
		for k in [-1, 0, 1]:
			var q := Vector2(k * 8.0, HALF).rotated(-face)
			put.call(pc[2] if side == 0 and k == 0 else pc[0], q, face)
	put.call(pc[3], Vector2(0, -6.0), 0.0, {"tier": tier})
	# Loot in the courtyard and the keep's doorway: more and better with the tier.
	var caches := ["chest", "rune_coffer", "supply_pod"]
	var luck := 0.25 + 0.25 * tier
	for n in 1 + tier * 2:
		var t: String = caches[era] if r.randf() < 0.7 else caches[r.randi() % 3]
		var q := Vector2(r.randf_range(-9, 9), r.randf_range(2, 10))
		if n == 0:
			q = Vector2(0, 0.5)
		var o := {"chunk": Vector2i(int(floor((c + q.rotated(-yaw)).x / ChunkGenerator.SIZE)), int(floor((c + q.rotated(-yaw)).y / ChunkGenerator.SIZE))), "era": era, "how": "looted"}
		put.call(t, q, r.randf() * TAU, {"loot": ItemDB.roll_loot(era, r, o, luck), "opened": false})
	return items

## The curtain wall round a big medieval town, just outside its flat ground: 8 m
## sections on a circle, a gate wherever a road crosses it, towers flanking each gate
## and every few sections between. Appended to `items` in world coordinates.
static func town_wall(g: ChunkGenerator, s: Dictionary, items: Array) -> void:
	var c: Vector2 = s["center"]
	var rad := float(s["inner"]) + 2.5
	var half := asin(4.0 / rad) ## angular half-width of one section
	var gates: Array = []
	for a in g.road_crossings(s, rad):
		var dup := false
		for b in gates:
			if absf(angle_difference(a, b)) < half * 3.0:
				dup = true
		if not dup:
			gates.append(a)
	if gates.is_empty():
		gates.append(WHash.rng(g.seed, s["sx"], s["sz"], 405).randf() * TAU)
	gates.sort()
	var mid := rad * cos(half) ## chord midpoints sit slightly inside the circle
	var put := func(t: String, ang: float, r: float) -> void:
		var d := Vector2(cos(ang), sin(ang))
		# Local +z (the outer face) points away from the town; a tower turns its door in.
		items.append({"t": t, "p": c + d * r, "yaw": atan2(d.x, d.y) + (PI if t == "castle_tower" else 0.0), "st": {}})
	for i in gates.size():
		var g0: float = gates[i]
		var g1: float = gates[(i + 1) % gates.size()]
		var span := fposmod(g1 - g0, TAU)
		if gates.size() == 1:
			span = TAU
		put.call("castle_gate", g0, mid)
		put.call("castle_tower", g0 - half * 2.0, rad + 2.0)
		put.call("castle_tower", g0 + half * 2.0, rad + 2.0)
		# Walls fill the arc between this gate's tower and the next gate's.
		var from := g0 + half * 3.0
		var arc := span - half * 6.0
		if arc <= 0.0:
			continue
		var n := int(ceil(arc / (half * 2.0)))
		for k in n:
			var ang := from + arc * (k + 0.5) / n
			if k > 0 and k % 6 == 0 and n - k > 2:
				put.call("castle_tower", ang, rad + 2.0)
			else:
				put.call("castle_wall", ang, mid)

## Guards in the courtyard, by world position: [{p, tier, id}].
static func guards(f: Dictionary) -> Array:
	var c: Vector2 = f["center"]
	var out: Array = []
	var n := 1 + int(f["tier"]) * 2
	for i in n:
		var a := TAU * i / n
		var q := Vector2(cos(a) * 6.0, 4.0 + sin(a) * 5.0)
		out.append({"p": c + q.rotated(-float(f["yaw"])), "tier": f["tier"], "id": "g%d_%d_%d" % [f["cx"], f["cz"], i]})
	return out

# --- Meshes ------------------------------------------------------------------

static func build(t: String) -> ArrayMesh:
	if t == "bunker_keep":
		return KitBase.build("lab_block")
	if t == "bunker_tower":
		return KitBase.build("ops_tower")
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var models: Array = []
	var v := int(t.get_slice(VAR, 1)) if t.contains(VAR) else 0
	t = t.get_slice(VAR, 0)
	var era := 0 if t.begins_with("castle") else (1 if t.begins_with("crypt") else 2)
	var part := t.split("_")[1]
	if era == 2:
		_bunker(part, k, models)
	else:
		_stone(part, era == 1, k, models, v)
		# Castle masonry is stone through: the village walls' rubble faces, wooden bands
		# and corner quoins become the castle's own stone (pale trim stone read as paint,
		# and the kit's tan rubble met the parapets' grey coursing on every wall top), and
		# a tower is bare dressed stone inside, not plaster.
		var swap := {"MI_WoodTrim": Materials.get_mat("crypt_stone" if era == 1 else "castle_stone")}
		swap["MI_UnevenBrick"] = swap["MI_WoodTrim"]
		if part == "tower":
			# Inside, dressed stone: the kit's rubble brick, lit close by the torches, read
			# as big cartoon stones.
			swap["MI_Plaster"] = Materials.get_mat("crypt_stone" if era == 1 else "castle_stone")
		var quoins := {"MI_RockTrim": swap["MI_WoodTrim"]}
		for e in models:
			if String(e[0]).begins_with("village/Wall_UnevenBrick") and not swap.values().has(null):
				e.append(swap)
			elif String(e[0]) == "village/Corner_Exterior_Brick":
				e.append(quoins)
	if era == 2:
		var plain := BuildCatalog.merge_models(models)
		k.commit(Materials.get_mat, plain)
		return plain
	var stone := face_stone_of(era)
	var noise := FastNoiseLite.new()
	noise.seed = WHash.str_hash(t) + v
	noise.frequency = 0.25
	noise.fractal_octaves = 3
	var stone_mat := Materials.get_mat(stone)
	var on_kit := func(mat: Material, arrays: Array) -> void:
		if mat == stone_mat:
			_patches(arrays, noise)
	var on_boxes := func(name: String, arrays: Array) -> void:
		if name == stone:
			_patches(arrays, noise)
	var mesh := BuildCatalog.merge_models(models, on_kit)
	k.commit(Materials.get_mat, mesh, on_boxes)
	return mesh

## The castle's stone in its vertex colours: broad patches a few metres across where the
## blocks run a shade lighter or darker, as quarry beds and weather leave them (one even
## tone end to end read as a flat grey slab). The damp foot and rain streaks are _weather's.
static func _patches(arrays: Array, noise: FastNoiseLite) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var old = arrays[Mesh.ARRAY_COLOR]
	var has_old: bool = old != null and (old as PackedColorArray).size() == v.size()
	var col := PackedColorArray()
	col.resize(v.size())
	for i in v.size():
		var c: Color = old[i] if has_old else Color.WHITE
		var tone := lerpf(0.84, 1.0, clampf(0.5 + noise.get_noise_3dv(v[i]) * 0.9, 0.0, 1.0))
		col[i] = Color(c.r * tone, c.g * tone, c.b * tone, c.a)
	arrays[Mesh.ARRAY_COLOR] = col

static func face_stone_of(era: int) -> String:
	return "crypt_stone" if era == 1 else "castle_stone"

const BRICK := "village/Wall_UnevenBrick_Straight"
const BRICK_WIN := "village/Wall_UnevenBrick_Window_Thin_Round"

## Battlements along a wall top from x0 to x1 at height y, z offset zo: a breast-high
## parapet with a coping along it, and merlons standing on it, each capped with a coping
## stone that overhangs a little, no two quite the same height. `w`, `step` and `mh` set
## the merlons' width, spacing and height (tower crowns vary them).
static func _merlons(k: MeshKit, mat: String, x0: float, x1: float, y: float, zo: float, yaw: float, broken: bool, r: RandomNumberGenerator, w := 0.8, step := 1.4, mh := 0.86) -> void:
	var b := Basis(Vector3.UP, yaw)
	const WALL := 0.6
	var len := x1 - x0
	var mid := (x0 + x1) * 0.5
	k.box(mat, Transform3D(b, b * Vector3(mid, y + WALL * 0.5, zo)), Vector3(len, WALL, 0.5))
	k.box(mat, Transform3D(b, b * Vector3(mid, y + WALL + 0.04, zo)), Vector3(len + 0.04, 0.08, 0.6))
	var x := x0 + 0.5
	while x < x1 - 0.2:
		if not broken or r.randf() > 0.35:
			var h := r.randf_range(mh - 0.04, mh + 0.04) if not broken else r.randf_range(0.25, 0.8)
			var mw := r.randf_range(w - 0.04, w + 0.04)
			var y0 := y + WALL + 0.08
			k.box(mat, Transform3D(b, b * Vector3(x, y0 + h * 0.5, zo)), Vector3(mw, h, 0.5))
			if not broken:
				k.box(mat, Transform3D(b, b * Vector3(x, y0 + h + 0.05, zo)), Vector3(mw + 0.08, 0.1, 0.58))
		x += step

## Where the kit walls' outer faces lie (local z) on a curtain wall and on a tower.
const WALL_FACE := 0.9
const TOWER_FACE := 4.15

## A castle gateway's works: a round arch in the outer face, the portcullis drawn up
## into its slot behind it with its teeth showing, and two plank gate leaves standing
## open against the passage walls (wide enough between them for a cart).
static func _gateway(k: MeshKit, mat: String) -> void:
	var I := Transform3D.IDENTITY
	var arch := func(x: float) -> float:
		return 2.0 + sqrt(maxf(0.0, 4.0 - x * x))
	# The arch: the outer 0.8 m of the passage filled down to a half circle (the passage
	# behind stays full height), with a ring of voussoirs proud of the face.
	var n := 16
	for i in n:
		var xm := -2.0 + 4.0 * (i + 0.5) / n
		var ya: float = arch.call(xm)
		k.box(mat, I.translated(Vector3(xm, (ya + 4.05) * 0.5, 0.6)), Vector3(4.0 / n + 0.01, 4.05 - ya, 0.8))
	for i in 11:
		var a := PI * (i + 0.5) / 11.0
		k.box(mat, Transform3D(Basis(Vector3(0, 0, 1), a - PI * 0.5), Vector3(cos(a) * 2.17, 2.0 + sin(a) * 2.17, 1.03)), Vector3(0.52, 0.36, 0.08), Color(1.08, 1.06, 1.02))
	# The portcullis, drawn up: bars and cross-bars, iron teeth hanging below.
	var x := -1.8
	while x <= 1.81:
		var bot := 3.1
		k.box("iron", I.translated(Vector3(x, (bot + 4.0) * 0.5, 0.12)), Vector3(0.07, 4.0 - bot, 0.07))
		k.cylinder("iron", I.translated(Vector3(x, bot - 0.2, 0.12)), 0.006, 0.045, 0.2, 5)
		x += 0.3
	for y: float in [3.35, 3.75]:
		k.box("iron", I.translated(Vector3(0, y, 0.12)), Vector3(3.75, 0.06, 0.06))
	# The leaves: planks with a curved head (they close against the arch), three iron
	# straps and a brace, each swung back on its hinges against a passage wall.
	for sx: float in [-1.0, 1.0]:
		var hinge := Vector3(sx * 1.92, 0.0, 0.1)
		var open := 1.49 # radians: nearly flat to the wall, pointing into the town
		var dir := Vector3(-sx * sin(PI * 0.5 - open), 0, -cos(PI * 0.5 - open)).normalized()
		var b := Basis(Vector3.UP, atan2(-dir.z, dir.x))
		var face := -sx * b.z # the leaf's face toward the passage
		var planks := 7
		for j in planks:
			var u := 2.0 * (j + 0.5) / planks # out from the hinge
			var top: float = arch.call(sx * (2.0 - u)) - 0.06
			var tone := 0.88 + 0.2 * fposmod(float(j) * 0.618 + sx * 0.3, 1.0)
			k.box("planks", Transform3D(b, hinge + dir * u + Vector3(0, top * 0.5, 0)), Vector3(2.0 / planks - 0.015, top, 0.09), Color(tone, tone * 0.97, tone * 0.93))
		for y: float in [0.45, 1.5, 2.4]:
			var reach := 2.0 if y < 2.2 else 1.9
			k.box("iron", Transform3D(b, hinge + dir * (reach * 0.5) + Vector3(0, y, 0) + face * 0.055), Vector3(reach, 0.09, 0.025))
		var brace := Basis(b.z, atan2(1.9, 1.7)) * b
		k.box("timber", Transform3D(brace, hinge + dir * 1.0 + Vector3(0, 0.98, 0) + face * 0.07), Vector3(2.4, 0.13, 0.05))

## Weathering on one face (facing `yaw`, `face` out from the middle, `w` wide): damp,
## moss and splashed earth up from the foot, and rain streaks down from the parapet at
## `top` (weathering.gdshader; the pattern follows the world, so sections differ).
static func _weather(k: MeshKit, yaw: float, face: float, w: float, top: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var foot := Color(1, 1, 1, 1)
	var rain := Color(0, 1, 1, 1)
	k.card("weathering", Transform3D.IDENTITY, b * Vector3(0, 0.6, face + 0.03), b, w + 0.1, 3.6, Vector3.ZERO, foot)
	k.card("weathering", Transform3D.IDENTITY, b * Vector3(0, top - 2.2, face + 0.035), b, w + 0.1, 4.4, Vector3.ZERO, rain)

## A tower's crown, one of four builds: plain battlements; a corbelled parapet standing
## out on brackets (machicolations); round bartizans hung on the outer corners; or a
## stair turret rising above the roof at one corner under a slate cone.
static func _tower_top(k: MeshKit, v: int, mat: String, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var mw: float = [0.8, 0.95, 0.7, 0.85][v]
	var step: float = [1.4, 1.6, 1.25, 1.5][v]
	var mh: float = [0.9, 1.05, 0.8, 0.95][v]
	var flag := Vector3(0, 12.3, 0)
	if v == 1:
		for side in 4:
			var b := Basis(Vector3.UP, side * PI / 2.0)
			k.box(mat, Transform3D(b, b * Vector3(0, 12.15, 4.35)), Vector3(9.2, 0.3, 0.7))
			var x := -4.1
			while x <= 4.15:
				k.box(mat, Transform3D(b, b * Vector3(x, 11.7, 4.3)), Vector3(0.32, 0.6, 0.5))
				k.box(mat, Transform3D(b, b * Vector3(x, 11.3, 4.22)), Vector3(0.28, 0.3, 0.34))
				x += 0.82
			_merlons(k, mat, -4.6, 4.6, 12.3, 4.45, side * PI / 2.0, false, r, mw, step, mh)
		flag = Vector3(-3.4, 12.3, 3.4)
	else:
		for side in 4:
			_merlons(k, mat, -4.2, 4.2, 12.3, 4.05, side * PI / 2.0, false, r, mw, step, mh)
	if v == 2:
		# The outer corners (local -z faces away from the town).
		for sx: float in [-1.0, 1.0]:
			var c := Vector3(sx * 4.45, 0, -4.45)
			k.cylinder(mat, I.translated(c + Vector3(0, 8.6, 0)), 0.15, 1.05, 1.4, 12)
			k.cylinder(mat, I.translated(c + Vector3(0, 10.0, 0)), 1.05, 1.05, 2.9, 12, false)
			k.cylinder("slate", I.translated(c + Vector3(0, 12.9, 0)), 1.3, 0.03, 2.4, 12)
			for a in 4:
				var d := Vector3(cos(a * PI * 0.5 + 0.8), 0, sin(a * PI * 0.5 + 0.8))
				k.box("stone_dark", Transform3D(Basis(Vector3.UP, -(a * PI * 0.5 + 0.8) + PI * 0.5), c + d * 1.04 + Vector3(0, 11.0, 0)), Vector3(0.12, 0.6, 0.06))
	elif v == 3:
		var c := Vector3(-4.5, 0, -4.5)
		k.cylinder(mat, I.translated(c + Vector3(0, 6.4, 0)), 0.2, 1.6, 1.8, 14)
		k.cylinder(mat, I.translated(c + Vector3(0, 8.2, 0)), 1.6, 1.55, 7.4, 14, false, 0.02, 3)
		k.cylinder("slate", I.translated(c + Vector3(0, 15.6, 0)), 1.9, 0.04, 3.4, 14)
		for hgt: float in [10.0, 13.2]:
			var a := r.randf() * TAU
			k.box("stone_dark", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), c + Vector3(cos(a), 0, sin(a)) * 1.58 + Vector3(0, hgt, 0)), Vector3(0.14, 0.7, 0.06))
		flag = c + Vector3(0, 18.9, 0)
	k.cylinder("timber", I.translated(flag), 0.06, 0.05, 4.5 if v != 3 else 2.4, 6)
	var top := flag.y + (4.5 if v != 3 else 2.4)
	k.box("cloth", I.translated(flag + Vector3(0.75, top - flag.y - 0.6, 0)), Vector3(1.4, 0.9, 0.03))

## Brick walls on one face of a run of 2 m modules: `n` modules centred on the origin
## along local x, facing `yaw`, `rows` storeys high.
static func _face(models: Array, n: int, rows: int, yaw: float, out: float, win_row: int, broken: bool, r: RandomNumberGenerator, door := -1) -> void:
	var b := Basis(Vector3.UP, yaw)
	for row in rows:
		for m in n:
			if broken and row == rows - 1 and r.randf() < 0.35:
				continue
			if row == 0 and m == door:
				continue
			var x := -n + 1.0 + m * 2.0
			var piece := BRICK_WIN if row == win_row and m % 2 == 1 else BRICK
			models.append([piece, rad_to_deg(yaw), b * Vector3(x, row * 3.0, out), 1.0])

static func _stone(part: String, ruined: bool, k: MeshKit, models: Array, v := 0) -> void:
	var r := WHash.rng(WHash.str_hash(part), 1 if ruined else 0, v, 7)
	var face_stone := "crypt_stone" if ruined else "castle_stone"
	match part:
		"wall":
			# 8 m of curtain wall, 6 m high, with a walkway and merlons on the outer edge.
			_face(models, 4, 2, 0.0, 0.8, -1, ruined, r)
			_face(models, 4, 2, PI, 0.8, -1, ruined, r)
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, 2.9, 0)), Vector3(8.0, 5.8, 1.5))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, 6.05, 0)), Vector3(8.0, 0.3, 2.0))
			_merlons(k, face_stone, -4.0, 4.0, 6.2, 0.75, 0.0, ruined, r)
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, -2.0, 0)), Vector3(8.2, 4.0, 2.0))
			for face in [0.0, PI]:
				_weather(k, face, WALL_FACE, 8.0, 6.2)
			# Ivy up one face or the other on some sections.
			if v > 0:
				var side := 0.0 if v == 1 else PI
				models.append(["village/Prop_Vine2" if v == 1 else "village/Prop_Vine5", rad_to_deg(side), Basis(Vector3.UP, side) * Vector3(r.randf_range(-2.5, 2.5), r.randf_range(3.5, 4.5), WALL_FACE + 0.05), 1.7])
		"tower":
			# 8 m square, four storeys, arrow slits, a crenellated top. A door at the foot of
			# the front opens on a stair up the walls to a hatch onto the roof (Interiors).
			for side in 4:
				var yaw := side * PI / 2.0
				_face(models, 4, 4, yaw, 4.0, 2, ruined, r, 3 if side == 0 else -1)
			for c in [Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4)]:
				for row in 4:
					models.append(["village/Corner_Exterior_Brick", 0, c + Vector3(0, row * 3.0, 0), 1.0])
			models.append(["village/Wall_UnevenBrick_Door_Round", 0, Vector3(3, 0, 4.0), 1.0])
			models.append(["village/Door_1_Round", 100, Vector3(3 - 0.53, 0, 4.0 - 0.18), 1.0])
			var fl: float = Interiors.BOX["castle_tower"][1]
			k.box("flagstone", Transform3D.IDENTITY.translated(Vector3(0, fl * 0.5, 0)), Vector3(7.6, fl, 7.6))
			for bx in Interiors.roof_boxes("castle_tower"):
				k.box(face_stone, Transform3D.IDENTITY.translated(bx[0]), bx[1])
				# Flagstones underfoot on the roof (the walls' coursed stone, seen from
				# above, read as tiles with holes in them), weathered down to the walls'
				# own grey so the two read as one stone.
				var top: Vector3 = bx[0] + Vector3(0, (bx[1] as Vector3).y * 0.5 + 0.01, 0)
				k.box("flagstone", Transform3D.IDENTITY.translated(top), Vector3((bx[1] as Vector3).x, 0.02, (bx[1] as Vector3).z), Color(0.8, 0.78, 0.74))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, -2.0, 0)), Vector3(8.6, 4.0, 8.6))
			if not ruined:
				_tower_top(k, v, face_stone, r)
				for side in 4:
					_weather(k, side * PI / 2.0, TOWER_FACE, 8.0, 12.3)
			else:
				for side in 4:
					_merlons(k, face_stone, -4.2, 4.2, 12.3, 4.05, side * PI / 2.0, ruined, r)
				for n in 3:
					models.append(["village/Prop_Vine5" if n % 2 else "village/Prop_Vine2", n * 90, Basis(Vector3.UP, n * PI / 2) * Vector3(r.randf_range(-2, 2), 6.0, 4.1), 1.0])
				k.box("glow_violet", Transform3D.IDENTITY.translated(Vector3(0, 7.5, 4.05)), Vector3(0.5, 0.9, 0.04))
		"gate":
			# An arch 4 m wide through 8 m of wall, the portcullis drawn up.
			var b0 := Basis.IDENTITY
			for face in [0.0, PI]:
				var b := Basis(Vector3.UP, face)
				for x in [-3.0, 3.0]:
					for row in 2:
						models.append([BRICK, rad_to_deg(face), b * Vector3(x, row * 3.0, 0.8), 1.0])
			for x in [-3.0, 3.0]:
				k.box(face_stone, Transform3D(b0, Vector3(x, 2.9, 0)), Vector3(2.0, 5.8, 1.5))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, 5.0, 0)), Vector3(4.0, 2.0, 2.0))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, 6.05, 0)), Vector3(8.0, 0.3, 2.0))
			_merlons(k, face_stone, -4.0, 4.0, 6.2, 0.75, 0.0, ruined, r)
			if ruined:
				for x in [-1.5, -0.75, 0.0, 0.75, 1.5]:
					k.box("iron", Transform3D.IDENTITY.translated(Vector3(x, 3.6, 0.0)), Vector3(0.08, 0.9, 0.08))
				k.box("iron", Transform3D.IDENTITY.translated(Vector3(0, 3.2, 0.0)), Vector3(3.9, 0.08, 0.08))
			else:
				_gateway(k, face_stone)
				for face: float in [0.0, PI]:
					for x: float in [-3.0, 3.0]:
						var b := Basis(Vector3.UP, face)
						k.card("weathering", Transform3D.IDENTITY, b * Vector3(x, 0.6, WALL_FACE + 0.03), b, 2.1, 3.6, Vector3.ZERO, Color(1, 1, 1, 1))
						k.card("weathering", Transform3D.IDENTITY, b * Vector3(x, 4.0, WALL_FACE + 0.035), b, 2.1, 4.4, Vector3.ZERO, Color(0, 1, 1, 1))
					var b2 := Basis(Vector3.UP, face)
					k.card("weathering", Transform3D.IDENTITY, b2 * Vector3(0, 5.1, WALL_FACE + 0.035), b2, 4.0, 2.2, Vector3.ZERO, Color(0, 1, 1, 1))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(-3.0, -2.0, 0)), Vector3(2.2, 4.0, 2.0))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(3.0, -2.0, 0)), Vector3(2.2, 4.0, 2.0))
			k.box("flagstone", Transform3D.IDENTITY.translated(Vector3(0, -0.45, 0)), Vector3(4.0, 0.9, 2.2))
			if ruined:
				k.box("glow_violet", Transform3D.IDENTITY.translated(Vector3(0, 5.2, 1.02)), Vector3(1.2, 0.25, 0.04))
		"keep":
			# 8 by 8 m, three storeys, a door to the courtyard standing open into a hall you
			# can walk into (Interiors furnishes it), crenellated roof.
			for side in 4:
				var yaw := side * PI / 2.0
				_face(models, 4, 3, yaw, 4.0, 1, ruined, r, 2 if side == 0 else -1)
			for c in [Vector3(-4, 0, -4), Vector3(4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4)]:
				for row in 3:
					models.append(["village/Corner_Exterior_Brick", 0, c + Vector3(0, row * 3.0, 0), 1.0])
			# Doorway: the front wall's ground row middle module, the door swung inwards.
			models.append(["village/Wall_UnevenBrick_Door_Round", 0, Vector3(1, 0, 4.0), 1.0])
			models.append(["village/Door_1_Round", 100, Vector3(1 - 0.53, 0, 4.0 - 0.18), 1.0])
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, 9.15, 0)), Vector3(8.6, 0.3, 8.6))
			for side in 4:
				_merlons(k, face_stone, -4.2, 4.2, 9.3, 4.05, side * PI / 2.0, ruined, r)
			var fl: float = Interiors.BOX["castle_keep"][1]
			k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, fl * 0.5, 0)), Vector3(7.6, fl, 7.6))
			# The hall's ceiling: boards on five hewn beams (rough bark across the whole
			# ceiling read as a tree trunk).
			k.box("wood_floor", Transform3D.IDENTITY.translated(Vector3(0, 2.95, 0)), Vector3(7.6, 0.1, 7.6))
			for j in 5:
				k.box("timber", Transform3D.IDENTITY.translated(Vector3(0, 2.79, -3.2 + j * 1.6)), Vector3(7.4, 0.22, 0.22))
			k.box(face_stone, Transform3D.IDENTITY.translated(Vector3(0, -2.0, 0)), Vector3(8.6, 4.0, 8.6))
			if ruined:
				for n in 2:
					models.append(["village/Prop_Vine2", 180 * n, Basis(Vector3.UP, n * PI) * Vector3(-2.0, 4.0, 4.1), 1.0])
				k.box("glow_violet", Transform3D.IDENTITY.translated(Vector3(1, 3.4, 4.12)), Vector3(1.0, 0.3, 0.04))
			else:
				# Lamplight behind the hall's upper windows after dark (a dark pane by day).
				for wx: float in [-1.0, 3.0]:
					k.box("window_warm", Transform3D.IDENTITY.translated(Vector3(wx, 4.6, 3.9)), Vector3(0.6, 1.4, 0.04))

## Sci-fi bunker pieces from the outpost kit.
static func _bunker(part: String, k: MeshKit, models: Array) -> void:
	match part:
		"wall":
			for face in [0.0, 180.0]:
				var b := Basis(Vector3.UP, deg_to_rad(face))
				for x in [-2.0, 2.0]:
					# A kit wall sits on its tile's -x edge: turn it to face out along z.
					var at := b * Vector3(x, 0, -0.4)
					models.append(["scifi/WallBand_Straight", face + 90.0, at, 1.0])
					models.append(["scifi/TopCables_Straight", face + 90.0, at, 1.0])
			k.box("scifi_panels", Transform3D.IDENTITY.translated(Vector3(0, 2.5, 0)), Vector3(8.0, 5.0, 2.4))
			k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 5.05, 0)), Vector3(8.0, 0.1, 3.4))
			k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -2.0, 0)), Vector3(8.2, 4.0, 3.4))
			k.box("glow_red", Transform3D.IDENTITY.translated(Vector3(0, 4.6, 1.75)), Vector3(6.0, 0.06, 0.04))
		"tower":
			models.append(["scifi/Column_Large_Straight", 0, Vector3(0, 0, 0), 1.2])
			k.box("scifi_lights", Transform3D.IDENTITY.translated(Vector3(0, 6.0, 0)), Vector3(6.0, 12.0, 6.0))
			k.box("panel", Transform3D.IDENTITY.translated(Vector3(0, 12.3, 0)), Vector3(7.0, 0.6, 7.0))
			k.box("glass", Transform3D.IDENTITY.translated(Vector3(0, 10.5, 3.02)), Vector3(4.0, 1.0, 0.04))
			k.box("glow_red", Transform3D.IDENTITY.translated(Vector3(0, 13.0, 0)), Vector3(0.3, 0.3, 0.3))
			k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -2.0, 0)), Vector3(6.4, 4.0, 6.4))
			for side in 4:
				var b := Basis(Vector3.UP, side * PI / 2.0)
				k.box("glow_cyan", Transform3D(b, b * Vector3(0, 6.0, 3.02)), Vector3(0.1, 8.0, 0.04))
		"gate":
			for x in [-3.0, 3.0]:
				models.append(["scifi/Column_Pipes", 0, Vector3(x, 0, 0), 1.0])
				k.box("scifi_panels", Transform3D.IDENTITY.translated(Vector3(x, 2.52, 0)), Vector3(2.0, 5.04, 3.2))
				k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(x, -2.0, 0)), Vector3(2.2, 4.0, 3.4))
			models.append(["scifi/Door_Frame_Square", 0, Vector3(0, 0, 1.0), 0.85])
			k.box("hazard", Transform3D.IDENTITY.translated(Vector3(0, 4.7, 0)), Vector3(4.0, 0.6, 3.2))
			k.box("glow_red", Transform3D.IDENTITY.translated(Vector3(0, 4.5, 1.62)), Vector3(3.0, 0.08, 0.04))
