class_name KitBase
## Sci-fi outpost buildings and yard facilities assembled from the Modular SciFi kit:
## 4 m wall modules, 3 m walls under a 2 m trim band. The door faces +z (the street).

## [width modules, depth modules, storeys, wall style]
const PLANS := {
	"hab_block": [2, 2, 1, "astra"],
	"lab_block": [3, 2, 1, "band"],
	"ops_tower": [2, 2, 2, "astra"],
}

const WALL := {
	"astra": ["scifi/WallAstra_Straight", "scifi/WallAstra_Straight_Window"],
	"band": ["scifi/WallBand_Straight", "scifi/WallAstra_Straight_Flat_Window"],
}
const TOP := {"astra": "scifi/TopAstra_Straight", "band": "scifi/TopCables_Straight"}
const STOREY := 5.0
## Ground floor height, a step above the ground (world objects sink 0.15 m into it).
const FLOOR := 0.2

## Blocks come in a few looks, picked by where they stand (key "<type>~var<n>", as
## castles do, Stronghold.VAR): each with its own livery stripe round the trim band and
## its own plant on the roof and at the walls, so a street of them reads as buildings
## put up for different jobs, not one block stamped out. Footprint, rooms and windows
## stay the type's own (Interiors furnishes and lights them by type).
const VARIANTS := {"hab_block": 4, "lab_block": 3}
const LIVERY := [Color(0.13, 0.4, 0.44), Color(0.72, 0.5, 0.13), Color(0.48, 0.16, 0.12), Color(0.16, 0.22, 0.42), Color(0.28, 0.4, 0.24), Color(0.62, 0.62, 0.6)]

static func variant_key(o: Dictionary) -> String:
	if not o.has("p"):
		return o["t"]
	var p: Vector3 = o["p"]
	var h := absi(WHash.combine(int(round(p.x * 4.0)) + 17, int(round(p.z * 4.0))))
	return "%s%s%d" % [o["t"], Stronghold.VAR, h % int(VARIANTS[o["t"]])]

## Yard facilities: fenced, so their parts read as one installation.
const YARDS := {"solar_farm": Vector3(16, 2.2, 12), "depot": Vector3(12, 5.0, 12), "outpost_light": Vector3(0.9, 5.4, 0.9)}

static func has(t: String) -> bool:
	return PLANS.has(t) or YARDS.has(t)

## Collision box size for a building or yard.
static func size_of(t: String) -> Vector3:
	if YARDS.has(t):
		return YARDS[t]
	var p: Array = PLANS[t]
	return Vector3(p[0] * 4.0 + 1.6, p[2] * STOREY + 0.6, p[1] * 4.0 + 1.6)

static func build(key: String) -> ArrayMesh:
	var t := key.get_slice(Stronghold.VAR, 0)
	var v := int(key.get_slice(Stronghold.VAR, 1)) if key.contains(Stronghold.VAR) else -1
	var k := MeshKit.new(WHash.str_hash(key) & 0xFFFF)
	var models: Array = []
	match t:
		"solar_farm": _solar_farm(k, models)
		"depot": _depot(k, models)
		"outpost_light": _light(k, models)
		_: _building(t, k, models, [], v)
	var mesh := BuildCatalog.merge_models(models)
	k.commit(Materials.get_mat, mesh)
	return mesh

## Where the ground floor's lamplit window panels go (drawn from further off, so you
## can see into the room up close).
static func window_glows(t: String) -> Array:
	var glows: Array = []
	_building(t, MeshKit.new(1), [], glows)
	return glows

## Walls go on each outer tile edge; a kit wall sits on its tile's -x edge, so the yaw
## turns -x to face outwards. The doors stand slid open and the floor sits a step
## above the ground, so the room can be walked into (Interiors furnishes it). Ground
## floor window panels go to `glows` rather than the mesh.
static func _building(t: String, k: MeshKit, models: Array, glows: Array, v := -1) -> void:
	var p: Array = PLANS[t]
	var nx: int = p[0]
	var nz: int = p[1]
	var storeys: int = p[2]
	var style: String = p[3]
	var w := nx * 4.0
	var d := nz * 4.0
	var r := WHash.rng(WHash.str_hash(t), 0, 0, 1)
	var door_i := nx / 2
	for s in storeys:
		var y := s * STOREY
		for i in nx:
			for j in nz:
				var c := Vector3(-w / 2 + 2 + i * 4, y, -d / 2 + 2 + j * 4)
				var edges: Array = []
				if i == 0: edges.append([0.0, Vector3(-1, 0, 0)])
				if i == nx - 1: edges.append([180.0, Vector3(1, 0, 0)])
				if j == 0: edges.append([-90.0, Vector3(0, 0, -1)])
				if j == nz - 1: edges.append([90.0, Vector3(0, 0, 1)])
				for e in edges:
					var yaw: float = e[0]
					var out: Vector3 = e[1]
					if s == 0 and yaw == 90.0 and i == door_i:
						var at := c + out * 2.0
						models.append(["scifi/Door_Frame_Square", 0, at, 1.0])
						# Both leaves slide into the wall beside them; at the corner tile there
						# is no wall to the right, so both go left, one behind the other.
						models.append(["scifi/Door_Metal", 0, at + Vector3(-1.95, 0, -0.05), 1.0])
						models.append(["scifi/Door_Metal", 180, at + Vector3(1.95 if door_i < nx - 1 else -4.06, 0, -0.05), 1.0])
						k.box("glow_white", Transform3D.IDENTITY.translated(at + Vector3(0, 4.35, 0.3)), Vector3(2.6, 0.07, 0.06))
						continue
					var window := (i + j + s) % 2 == 0 or yaw == 90.0 or r.randf() < 0.3
					models.append([WALL[style][1 if window else 0], yaw, c, 1.0])
					models.append([TOP[style], yaw, c, 1.0])
					if window:
						var gx := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw + 90.0)), c + out * 1.55 + Vector3(0, 1.6, 0))
						if s == 0:
							glows.append(gx)
						else:
							k.box("glow_white", gx, Vector3(3.0, 1.4, 0.04))
				if s == 0:
					models.append(["scifi/Platform_Simple", 0, c + Vector3(0, FLOOR, 0), 1.0])
		for cx in [-w / 2, w / 2]:
			for cz in [-d / 2, d / 2]:
				models.append(["scifi/Column_Pipes", 0, Vector3(cx, y, cz), 1.0])
		# Slabs stand a little proud of the wall and column tops under them, and the
		# foundation a little below the floor tiles on it: faces at one height flicker.
		if s > 0:
			k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, y - 0.08, 0)), Vector3(w - 0.4, 0.2, d - 0.4))
	var top := storeys * STOREY
	# Roof: a slab capped by plate tiles, with vents and fans on top.
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, top - 0.23, 0)), Vector3(w + 0.6, 0.5, d + 0.6))
	for i in nx:
		for j in nz:
			models.append(["scifi/Platform_Squares", 0, Vector3(-w / 2 + 2 + i * 4, top + 0.04, -d / 2 + 2 + j * 4), 1.0])
	models.append(["scifi/Prop_Fan_Small", 0, Vector3(-w / 2 + 2, top + 0.04, -d / 2 + 2), 1.0])
	models.append(["scifi/Prop_Vent_Big", 90, Vector3(w / 2 - 1.6, top + 0.1, 0.5), 1.0])
	_roof_kit(t, k, models, w, d, top, v)
	if v >= 0:
		_livery(t, k, models, w, d, top, style, v)
	if storeys > 1:
		var b := Basis(Vector3(1, 0, 0), -0.9)
		k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(w / 2 - 1.2, top, -d / 2 + 1.2)), 0.08, 0.05, 4.0, 6)
		k.sphere("panel", Transform3D(b, Vector3(w / 2 - 1.2, top + 2.6, -d / 2 + 1.5)), 1.1, 6, 14, 0.0, 0.35, Color.WHITE, true)
		k.sphere("glow_red", Transform3D.IDENTITY.translated(Vector3(w / 2 - 1.2, top + 4.1, -d / 2 + 1.2)), 0.12, 4, 6)
	# Foundation pad, and a lit step out of the door.
	k.box("scifi_floor", Transform3D.IDENTITY.translated(Vector3(0, FLOOR - 0.62, 0)), Vector3(w + 1.4, 1.2, d + 1.4))
	models.append(["scifi/Platform_DarkPlates", 0, Vector3(-w / 2 + 2 + door_i * 4, 0.03, d / 2 + 2.0), Vector3(1, 1, 0.5)])
	models.append(["scifi/Prop_Light_Floor", 0, Vector3(-w / 2 + 2 + door_i * 4, 0.04, d / 2 + 2.9), 1.0])

## What makes a block read as a working building and not a box: a railing round the
## roof, plant on it (air handlers, a water tank, panels, masts), and service pipes
## climbing the back wall to it.
static func _roof_kit(t: String, k: MeshKit, models: Array, w: float, d: float, top: float, v := -1) -> void:
	var I := Transform3D.IDENTITY
	var y := top + 0.04
	# Railing a step in from the slab edge, in 4 m sections (a section runs along its -z).
	var ex := w / 2 + 0.05
	var ez := d / 2 + 0.05
	for i in int(w / 4.0):
		models.append(["scifi/Prop_Rail_4", -90, Vector3(-w / 2 + i * 4, y, -ez), 1.0])
		models.append(["scifi/Prop_Rail_4", -90, Vector3(-w / 2 + i * 4, y, ez), 1.0])
	for j in int(d / 4.0):
		models.append(["scifi/Prop_Rail_4", 180, Vector3(-ex, y, -d / 2 + j * 4), 1.0])
		models.append(["scifi/Prop_Rail_4", 180, Vector3(ex, y, -d / 2 + j * 4), 1.0])
	# Air handlers: a housing with a fan on top.
	var units: Array = [Vector3(-w / 2 + 1.6, 0, d / 2 - 1.4)]
	if w >= 12.0:
		units.append(Vector3(0.6, 0, d / 2 - 1.4))
	for u in units:
		k.box("metal_dark", I.translated(u + Vector3(0, top + 0.55, 0)), Vector3(1.9, 1.0, 1.4))
		k.box("metal", I.translated(u + Vector3(0, top + 0.08, 0)), Vector3(2.1, 0.12, 1.6))
		models.append(["scifi/Prop_Fan_Small", 0, u + Vector3(0, top + 1.05, 0), 0.75])
	# Which plant: the plain block's, or the variant's own.
	var plant := t
	if t == "hab_block" and v >= 0:
		plant = ["hab_block", "lab_block", "mast", "hab_block"][v]
	elif t == "lab_block" and v >= 0:
		plant = ["lab_block", "mast", "hab_block"][v]
	match plant:
		"mast":
			# A lattice mast with a dish and a whip aerial, stayed to the roof.
			var mc := Vector3(w / 2 - 1.8, top, -d / 2 + 1.8)
			for a in 3:
				var ang := a * TAU / 3.0
				var foot := mc + Vector3(cos(ang), 0, sin(ang)) * 0.35
				k.cylinder("metal", Transform3D(Basis(Vector3(-sin(ang), 0, cos(ang)), 0.06), foot), 0.035, 0.03, 6.0, 5)
			for n in 6:
				k.box("metal", I.translated(mc + Vector3(0, 0.8 + n, 0)), Vector3(0.62, 0.04, 0.62))
			k.sphere("panel", Transform3D(Basis(Vector3(1, 0, 0), -0.6), mc + Vector3(0, 4.2, 0.45)), 0.8, 6, 12, 0.0, 0.35, Color.WHITE, true)
			k.cylinder("metal", I.translated(mc + Vector3(0, 6.0, 0)), 0.02, 0.01, 2.2, 4)
			k.sphere("glow_red", I.translated(mc + Vector3(0, 8.2, 0)), 0.09, 4, 6)
		"hab_block":
			# A water tank on short legs.
			var tc := Vector3(w / 2 - 1.5, top, -d / 2 + 1.6)
			for lg in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.6, 0.6)]:
				k.cylinder("metal_dark", I.translated(tc + Vector3(lg.x, 0, lg.y)), 0.06, 0.06, 0.6, 6)
			k.cylinder("painted", I.translated(tc + Vector3(0, 0.6, 0)), 0.95, 0.95, 1.7, 14, true, 0.0, 1, Color(0.72, 0.74, 0.72))
			k.cylinder("painted", I.translated(tc + Vector3(0, 2.3, 0)), 0.95, 0.3, 0.35, 14, true, 0.0, 1, Color(0.6, 0.62, 0.6))
		"lab_block":
			# A bank of tilted panels and a short mast with a dish.
			var tilt := Basis(Vector3(1, 0, 0), -0.5)
			for n in 3:
				var pc := Vector3(-w / 2 + 2.4 + n * 2.3, top + 0.7, -d / 2 + 1.8)
				k.box("metal_dark", Transform3D(tilt, pc), Vector3(2.1, 0.06, 1.5))
				k.box("solar_cell", Transform3D(tilt, pc + Vector3(0, 0.04, 0)), Vector3(2.0, 0.02, 1.4))
				k.cylinder("metal", I.translated(Vector3(pc.x, top, pc.z + 0.3)), 0.04, 0.04, 0.55, 6)
				k.cylinder("metal", I.translated(Vector3(pc.x, top, pc.z - 0.35)), 0.04, 0.04, 0.95, 6)
			var mc := Vector3(w / 2 - 1.3, top, d / 2 - 1.3)
			k.cylinder("metal", I.translated(mc), 0.07, 0.05, 3.0, 6)
			k.sphere("panel", Transform3D(Basis(Vector3(1, 0, 0), -0.7), mc + Vector3(0, 2.4, 0.2)), 0.7, 6, 12, 0.0, 0.35, Color.WHITE, true)
	if v == 3 and t == "hab_block":
		# A second tank's worth of solar panels along the front edge too.
		var tilt := Basis(Vector3(1, 0, 0), 0.45)
		for n in 2:
			var pc := Vector3(-0.6 + n * 2.3, top + 0.6, d / 2 - 1.3)
			k.box("metal_dark", Transform3D(tilt, pc), Vector3(2.1, 0.06, 1.3))
			k.box("solar_cell", Transform3D(tilt, pc + Vector3(0, 0.04, 0)), Vector3(2.0, 0.02, 1.2))
			k.cylinder("metal", I.translated(Vector3(pc.x, top, pc.z)), 0.04, 0.04, 0.6, 6)
	# Service pipes up the back wall, bent over the parapet onto the roof.
	for px in [-w / 2 + 1.0, -w / 2 + 1.35]:
		k.cylinder("metal", I.translated(Vector3(px, 0.0, -d / 2 - 0.95)), 0.09, 0.09, top + 0.4, 8)
		k.box("metal", I.translated(Vector3(px, top + 0.4, -d / 2 - 0.3)), Vector3(0.18, 0.18, 1.5))
	for bh in range(1, int(top / 2.0) + 1):
		k.box("metal_dark", I.translated(Vector3(-w / 2 + 1.18, bh * 2.0, -d / 2 - 0.88)), Vector3(0.7, 0.08, 0.2))

## A variant's own paint and fittings: a livery stripe along the trim band on every
## side, and one of air-conditioning units hung high on a side wall, an awning over the
## door, a plant room on the roof, or a caged ladder up the back.
static func _livery(t: String, k: MeshKit, models: Array, w: float, d: float, top: float, style: String, v: int) -> void:
	var I := Transform3D.IDENTITY
	var col: Color = LIVERY[(v * 2 + (1 if t == "lab_block" else 0)) % LIVERY.size()]
	# The trim band's face: flush at the tile edge on Astra tops, proud of it on cable
	# tops; the walls under it stand out further on Astra blocks (pilasters, window bays).
	var off := 0.03 if style == "astra" else 0.2
	var face := 0.55 if style == "astra" else 0.2
	for side in 4:
		var along := w if side % 2 == 0 else d
		var out := Vector3(0, 0, 1).rotated(Vector3.UP, side * PI / 2.0)
		var reach := (d if side % 2 == 0 else w) / 2 + off
		var xf := Transform3D(Basis(Vector3.UP, side * PI / 2.0), out * reach + Vector3(0, 4.35, 0))
		k.box("painted", xf, Vector3(along - 1.0, 0.32, 0.05), col)
		k.box("painted", xf.translated(Vector3(0, -0.24, 0)), Vector3(along - 1.0, 0.06, 0.05), col.darkened(0.2))
	match v % 4:
		0:
			# Air-conditioning units hung high on the left wall, above head height.
			for n in 2:
				var at := Vector3(-w / 2 - face - 0.25, 2.5, -d / 2 + 1.5 + n * 2.6)
				k.box("metal_dark", I.translated(at), Vector3(0.5, 0.7, 0.95))
				k.box("metal", I.translated(at + Vector3(-0.26, 0, 0)), Vector3(0.02, 0.56, 0.8))
				k.cylinder("metal_dark", Transform3D(Basis(Vector3(0, 0, 1), PI / 2), at + Vector3(-0.27, 0, 0)), 0.28, 0.28, 0.02, 12)
				k.box("metal", I.translated(at + Vector3(0.05, -0.4, 0)), Vector3(0.45, 0.04, 0.9))
		1:
			# An awning over the door in the livery colour, on two struts from the wall.
			var dx := -w / 2 + 2 + (int(w / 4.0) / 2) * 4
			k.box("painted", Transform3D(Basis(Vector3(1, 0, 0), 0.18), Vector3(dx, 3.25, d / 2 + face + 1.0)), Vector3(4.2, 0.08, 1.9), col)
			for sx in [-1.9, 1.9]:
				k.cylinder("metal", Transform3D(Basis(Vector3(1, 0, 0), 1.1), Vector3(dx + sx, 2.3, d / 2 + face)), 0.03, 0.03, 1.9, 5)
		2:
			# A plant room on the roof: a louvred housing with an exhaust stack.
			var at := Vector3(-w / 2 + 2.2, top + 1.0, 0.0)
			k.box("painted", I.translated(at), Vector3(2.4, 2.0, 2.0), col.lerp(Color(0.5, 0.5, 0.5), 0.55))
			k.box("metal_dark", I.translated(at + Vector3(0, 1.05, 0)), Vector3(2.6, 0.1, 2.2))
			for n in 5:
				k.box("metal_dark", I.translated(at + Vector3(0, -0.6 + n * 0.25, 1.01)), Vector3(1.6, 0.06, 0.03))
			k.cylinder("metal", I.translated(at + Vector3(0.7, 1.1, -0.5)), 0.14, 0.14, 1.8, 8)
			k.cylinder("metal_dark", I.translated(at + Vector3(0.7, 2.9, -0.5)), 0.18, 0.18, 0.12, 8)
		3:
			# A caged ladder up the back wall to the roof.
			var lx := w / 2 - 1.2
			var lz := -d / 2 - face - 0.45
			for sx in [-0.25, 0.25]:
				k.cylinder("metal", I.translated(Vector3(lx + sx, 0.0, lz)), 0.025, 0.025, top + 1.0, 5)
			for n in int((top + 0.8) / 0.3):
				k.box("metal", I.translated(Vector3(lx, 0.3 + n * 0.3, lz)), Vector3(0.5, 0.025, 0.025))
			for n in int((top - 2.2) / 0.9) + 1:
				k.cylinder("metal", I.translated(Vector3(lx, 2.4 + n * 0.9, lz - 0.3)), 0.38, 0.38, 0.04, 12, false)

## A fenced array: three rows of tilted panels facing the same way, an inverter and
## battery bank at the gate end, cable runs between them.
static func _solar_farm(k: MeshKit, models: Array) -> void:
	var sz: Vector3 = YARDS["solar_farm"]
	_fence(models, sz.x, sz.z, 1)
	var tilt := Basis(Vector3(1, 0, 0), -0.45)
	for row in 3:
		var z := -sz.z / 2 + 2.4 + row * 3.0
		for n in 4:
			var x := -sz.x / 2 + 2.2 + n * 3.1
			for lx in [-1.2, 1.2]:
				k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(x + lx, 0, z + 0.3)), 0.05, 0.05, 1.6, 6)
				k.cylinder("metal", Transform3D.IDENTITY.translated(Vector3(x + lx, 0, z - 0.4)), 0.05, 0.05, 1.2, 6)
			k.box("metal_dark", Transform3D(tilt, Vector3(x, 1.45, z)), Vector3(2.9, 0.06, 1.9))
			k.box("solar_cell", Transform3D(tilt, Vector3(x, 1.49, z)), Vector3(2.8, 0.02, 1.8))
	# Inverter and batteries by the gate (gate is on +z).
	var bz := sz.z / 2 - 2.0
	models.append(["scifi/Prop_PipeHolder", 0, Vector3(3.5, 0, bz), 1.0])
	for n in 4:
		k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(-5.2 + n * 1.0, 0.75, bz)), Vector3(0.8, 1.5, 0.9))
		k.box("glow_cyan", Transform3D.IDENTITY.translated(Vector3(-5.2 + n * 1.0, 1.2, bz + 0.46)), Vector3(0.4, 0.05, 0.02))
	models.append(["scifi/Prop_Computer", 180, Vector3(0.6, 0, bz + 0.2), 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -0.15, 0)), Vector3(sz.x, 0.35, sz.z))

## A fenced cargo yard: containers in rows, crates and drums stacked on pallets.
static func _depot(k: MeshKit, models: Array) -> void:
	var sz: Vector3 = YARDS["depot"]
	_fence(models, sz.x, sz.z, 1)
	var cols := [Color(0.62, 0.3, 0.16), Color(0.16, 0.3, 0.5), Color(0.62, 0.55, 0.22), Color(0.28, 0.42, 0.32)]
	for n in 3:
		var p := Vector3(-3.4 + n * 3.3, 1.25, -3.0)
		var c: Color = cols[n % cols.size()]
		k.box("painted", Transform3D.IDENTITY.translated(p), Vector3(2.6, 2.5, 5.0), c)
		for z in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			k.box("painted", Transform3D.IDENTITY.translated(p + Vector3(1.32, 0, z)), Vector3(0.04, 2.3, 0.1), c.darkened(0.25))
			k.box("painted", Transform3D.IDENTITY.translated(p + Vector3(-1.32, 0, z)), Vector3(0.04, 2.3, 0.1), c.darkened(0.25))
	k.box("painted", Transform3D.IDENTITY.translated(Vector3(-1.75, 3.75, -3.0)), Vector3(2.6, 2.5, 5.0), cols[3])
	for n in 3:
		var x := -3.6 + n * 1.3
		models.append(["scifi/Prop_Crate4", 0, Vector3(x, 0.56, 2.6), 1.0])
		if n != 1:
			models.append(["scifi/Prop_Crate3", 0, Vector3(x, 1.62, 2.6), 1.0])
	for n in 5:
		models.append(["scifi/Prop_Barrel_Large", 0, Vector3(2.0 + (n % 3) * 0.6, 0, 2.2 + (n / 3) * 0.6), 1.0])
	models.append(["scifi/Prop_Computer", 180, Vector3(3.8, 0, 4.6), 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, -0.15, 0)), Vector3(sz.x, 0.35, sz.z))

## A street lamp: a pipe column with a light bar under a cap.
static func _light(k: MeshKit, models: Array) -> void:
	models.append(["scifi/Column_Pipes", 0, Vector3.ZERO, 1.0])
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 5.1, 0.5)), Vector3(0.5, 0.15, 1.6))
	k.box("glow_white", Transform3D.IDENTITY.translated(Vector3(0, 5.0, 0.9)), Vector3(0.3, 0.05, 1.0))
	k.box("metal_dark", Transform3D.IDENTITY.translated(Vector3(0, 0.1, 0)), Vector3(1.1, 0.2, 1.1))

## A railing round a w by d yard, with a gap of `gates` sections at mid +z. A rail
## section runs 4 m along its -z from where it is placed.
static func _fence(models: Array, w: float, d: float, gates: int) -> void:
	var nx := int(w / 4.0)
	var nz := int(d / 4.0)
	for i in nx:
		var x := -w / 2 + i * 4
		models.append(["scifi/Prop_Rail_4", -90, Vector3(x, 0, -d / 2), 1.0])
		if absi(i * 2 - (nx - 1)) >= gates:
			models.append(["scifi/Prop_Rail_4", -90, Vector3(x, 0, d / 2), 1.0])
	for j in nz:
		var z := -d / 2 + j * 4
		models.append(["scifi/Prop_Rail_4", 180, Vector3(-w / 2, 0, z), 1.0])
		models.append(["scifi/Prop_Rail_4", 180, Vector3(w / 2, 0, z), 1.0])
	for c in [Vector2(-w / 2, -d / 2), Vector2(w / 2, -d / 2), Vector2(-w / 2, d / 2), Vector2(w / 2, d / 2)]:
		models.append(["scifi/Column_Simple", 0, Vector3(c.x, 0, c.y), 0.5])
