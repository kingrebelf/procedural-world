class_name ItemModels
## Real 3D models for materials you carry: ores, ingots, crystals, timber, bricks, hides,
## cloth, rope, bone and the like, at their real size, so a held stack of iron ingots is a
## cast iron bar and not the inventory icon on a card. Built from parts like the forged
## weapons in Viewmodel: the long axis runs along +Y and the hand grips its lower end.
##
## What each one has that makes it read as the real thing is noted where it is built:
## cast bars are tapered from the mould with a shrunken, pitted top and a stamp; logs show
## their growth rings, sapwood and bark in section; ore is rock with the mineral in seams.
## Nothing made on a human world glows; only alien (Fantasy era) matter keeps a faint light.

## Models show their best face (dial, stamp, split face) on +Z. Held in the right fist the
## eye looks at the prop from about (-0.89, 0, -0.46) in its own space (measured with the
## first-person hold, Viewmodel._aim), so the model is turned this far about +Y.
const FACE_YAW := -2.05

static var _models: Dictionary = {}
static var _mats: Dictionary = {}
static var _lock := Mutex.new()

## The model for item `t`, or null when it has none here (the caller then falls back).
static func model(t: String) -> ArrayMesh:
	_lock.lock()
	var have: bool = _models.has(t)
	var m: ArrayMesh = _models.get(t)
	_lock.unlock()
	if have:
		return m
	m = _build(t)
	_lock.lock()
	_models[t] = m
	_lock.unlock()
	return m

static func has(t: String) -> bool:
	return SHAPES.has(t) or ARMOUR_SLOTS.has(String(ItemDB.def(t).get("slot", ""))) and ItemDB.def(t).get("kind", "") == "armor"

## Armour and wearables held in the hand (worn ones are drawn on the body by Outfit).
const ARMOUR_SLOTS := ["head", "chest", "hands", "legs", "feet", "ring", "neck"]

## item -> [shape, args...]. Colours are albedo (sRGB); metals use their real reflectance.
const SHAPES := {
	# Metal: [bar, colour, roughness, patina colour, patina amount, length, form]. Every
	# ingot is the same family, a cast trapezoid bar with foundry marks, so they read as
	# ingots at a glance and differ by metal (colour, sheen, tarnish). Other forms
	# (currency bar, bun, oxhide, billet) remain available.
	"iron_ingot": ["bar", Color(0.46, 0.45, 0.44), 0.62, Color(0.45, 0.24, 0.12), 0.45, 0.15, "bar"],
	"steel_ingot": ["bar", Color(0.66, 0.67, 0.69), 0.3, Color(0.35, 0.36, 0.4), 0.15, 0.16, "bar"],
	"copper_ingot": ["bar", Color(0.95, 0.62, 0.48), 0.35, Color(0.32, 0.55, 0.45), 0.2, 0.15, "bar"],
	"bronze_ingot": ["bar", Color(0.8, 0.58, 0.34), 0.38, Color(0.3, 0.42, 0.32), 0.18, 0.15, "bar"],
	"silver_ingot": ["bar", Color(0.95, 0.94, 0.92), 0.25, Color(0.36, 0.33, 0.3), 0.22, 0.14, "bar"],
	"silver_bar": ["bar", Color(0.95, 0.94, 0.92), 0.2, Color(0.36, 0.33, 0.3), 0.12, 0.17, "bar"],
	"gold_ingot": ["bar", Color(1.0, 0.8, 0.42), 0.24, Color(0.8, 0.55, 0.25), 0.05, 0.13, "bar"],
	"mythril_ingot": ["bar", Color(0.78, 0.9, 0.98), 0.18, Color(0.55, 0.75, 0.9), 0.1, 0.15, "bar"],
	"titanium_ingot": ["bar", Color(0.62, 0.6, 0.58), 0.4, Color(0.5, 0.42, 0.6), 0.25, 0.16, "bar"],
	"voidsteel_ingot": ["bar", Color(0.52, 0.5, 0.58), 0.5, Color(0.4, 0.2, 0.6), 0.3, 0.16, "bar"],
	"starsteel_ingot": ["bar", Color(0.85, 0.86, 0.95), 0.15, Color(0.7, 0.6, 0.9), 0.2, 0.16, "bar"],
	"neutronium": ["bar", Color(0.6, 0.61, 0.64), 0.45, Color(0.2, 0.22, 0.3), 0.1, 0.07, "bar"],
	# Ore: [ore, rock colour, mineral colour, second mineral, seam width, metallic, angular]
	"stone": ["ore", Color(0.52, 0.5, 0.47), Color(0.6, 0.58, 0.55), Color(0.7, 0.68, 0.64), 0.00, 0.0, 0.5],
	"iron_ore": ["ore", Color(0.48, 0.3, 0.22), Color(0.26, 0.25, 0.26), Color(0.62, 0.3, 0.16), 0.14, 0.75, 0.45],
	"copper_ore": ["ore", Color(0.45, 0.43, 0.4), Color(0.2, 0.55, 0.4), Color(0.85, 0.5, 0.3), 0.13, 0.25, 0.45],
	"tin_ore": ["ore", Color(0.5, 0.48, 0.44), Color(0.16, 0.12, 0.1), Color(0.35, 0.28, 0.2), 0.11, 0.55, 0.5],
	"silver_ore": ["ore", Color(0.6, 0.58, 0.55), Color(0.55, 0.56, 0.6), Color(0.75, 0.76, 0.78), 0.12, 0.9, 0.5],
	"gold_ore": ["ore", Color(0.86, 0.84, 0.78), Color(1.0, 0.76, 0.3), Color(0.8, 0.55, 0.25), 0.05, 1.0, 0.4],
	"coal": ["ore", Color(0.07, 0.07, 0.075), Color(0.12, 0.12, 0.13), Color(0.2, 0.2, 0.22), 0.18, 0.35, 0.8],
	"flint": ["ore", Color(0.17, 0.17, 0.18), Color(0.85, 0.83, 0.78), Color(0.6, 0.58, 0.52), 0.16, 0.0, 0.3],
	"titanium_ore": ["ore", Color(0.5, 0.48, 0.46), Color(0.12, 0.12, 0.13), Color(0.3, 0.28, 0.27), 0.14, 0.8, 0.5],
	"uranium_ore": ["ore", Color(0.42, 0.4, 0.36), Color(0.1, 0.1, 0.09), Color(0.6, 0.6, 0.3), 0.14, 0.5, 0.5],
	"lithium_ore": ["ore", Color(0.7, 0.68, 0.66), Color(0.8, 0.66, 0.75), Color(0.92, 0.9, 0.88), 0.16, 0.1, 0.55],
	"cobalt_ore": ["ore", Color(0.5, 0.49, 0.48), Color(0.75, 0.76, 0.8), Color(0.82, 0.38, 0.55), 0.14, 0.8, 0.5],
	"rare_earth": ["ore", Color(0.42, 0.33, 0.25), Color(0.6, 0.42, 0.22), Color(0.3, 0.3, 0.32), 0.14, 0.3, 0.5],
	"voidstone_ore": ["ore", Color(0.12, 0.1, 0.16), Color(0.4, 0.22, 0.6), Color(0.6, 0.45, 0.85), 0.09, 0.6, 0.6],
	"starsteel_ore": ["ore", Color(0.25, 0.26, 0.32), Color(0.85, 0.86, 0.95), Color(0.6, 0.65, 0.85), 0.11, 1.0, 0.55],
	# Lumps: [lump, material, colour, size]
	"gold_nugget": ["nugget", Color(1.0, 0.76, 0.33), 0.035],
	"clay": ["lump", "im:clay", Color(0.55, 0.45, 0.36), 0.055],
	"animal_fat": ["lump", "im:wax", Color(0.93, 0.89, 0.74), 0.045],
	"charcoal": ["charcoal"],
	# Crystals: [crystals, colour, alpha, how many, glow]
	"salt_crystal": ["halite", Color(0.95, 0.86, 0.84)],
	"aether_crystal": ["crystals", Color(0.5, 0.78, 1.0), 0.55, 5, true],
	"silicon_crystal": ["crystals", Color(0.42, 0.44, 0.48), 1.0, 4, false],
	"psi_crystal_large": ["crystals", Color(0.75, 0.5, 1.0), 0.55, 7, true],
	"resin": ["amber"],
	# Timber
	"wood": ["log", 0.34, 0.06, Color(0.36, 0.27, 0.2)],
	"glowroot": ["log", 0.34, 0.055, Color(0.18, 0.3, 0.32)],
	"firewood": ["split"],
	"planks": ["planks"],
	# Fired and pressed blocks: [block, material, colour, size, frog]
	"brick": ["brick", "im:brick", Color(0.62, 0.3, 0.2), Vector3(0.1, 0.215, 0.065), true],
	"peat": ["brick", "im:peat", Color(0.22, 0.15, 0.1), Vector3(0.09, 0.2, 0.07), false],
	"coal_briquettes": ["briquettes"],
	"beeswax": ["cake", Color(0.88, 0.66, 0.22)],
	# Animal
	"hide": ["hide", "im:hide", Color(0.6, 0.47, 0.34), Color(0.78, 0.68, 0.56)],
	"leather": ["leather"],
	"fur_pelt": ["hide", "im:fur", Color(0.45, 0.36, 0.28), Color(0.7, 0.6, 0.5)],
	"hide_xeno": ["hide", "im:hide", Color(0.28, 0.36, 0.34), Color(0.5, 0.56, 0.5)],
	"im:bone": ["im:bone"],
	"antler": ["antler"],
	"fang_xeno": ["fang"],
	# Fibre and textiles
	"rope": ["rope", Color(0.66, 0.55, 0.38), 0.009],
	"rope_synth": ["rope", Color(0.9, 0.5, 0.12), 0.007],
	"cloth": ["cloth", Color(0.78, 0.72, 0.6)],
	"wool": ["skein", Color(0.86, 0.82, 0.74)],
	"fiber": ["bundle", Color(0.5, 0.56, 0.28), false],
	"flax": ["bundle", Color(0.72, 0.64, 0.42), false],
	"wheat": ["bundle", Color(0.82, 0.68, 0.38), true],
	# Worked metal parts
	"iron_nails": ["nails"],
	"gears": ["gears"],
	"springs": ["spring"],
	"pipe_section": ["pipe"],
	"valve": ["valve"],
	"pressure_gauge": ["gauge"],
	"piston": ["piston"],
	"copper_wire": ["spool", Color(0.95, 0.6, 0.45)],
	"steel_sheet": ["sheet", "im:metal_rolled", Color(0.6, 0.61, 0.63), 0.0015],
	"alloy_plate": ["sheet", "im:metal_rolled", Color(0.78, 0.8, 0.83), 0.004],
	"glass_pane": ["pane"],
	"rubber": ["brick", "im:rubber", Color(0.08, 0.08, 0.085), Vector3(0.09, 0.16, 0.04), false],
}

static func _build(t: String) -> ArrayMesh:
	if not SHAPES.has(t):
		if not has(t):
			return null
		var ka := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
		var ra := RandomNumberGenerator.new()
		ra.seed = WHash.str_hash(t)
		_armour(ka, ra, t)
		var am := ka.commit(mat)
		if String(ItemDB.def(t).get("slot", "")) == "chest" and Outfit.look_of({"type": t})["style"] == Outfit.STYLE_MAIL:
			# Held by the top fold of the bundle.
			am.set_meta("grip", Vector3(0, 0.11, 0))
			am.set_meta("grip_r", 0.03)
		if String(ItemDB.def(t).get("slot", "")) == "head":
			# A helm is carried crown forward, the way a hand holds one by the back of its
			# rim, so the skull and nasal show and not the lining.
			am = _transformed(am, Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3.ZERO))
		return am
	var s: Array = SHAPES[t]
	var k := MeshKit.new(WHash.str_hash(t) & 0xFFFF)
	var r := RandomNumberGenerator.new()
	r.seed = WHash.str_hash(t)
	match s[0]:
		"bar": _metal(k, r, s, t)
		"ore": _ore(k, r, t, s)
		"nugget": _nugget(k, r, s[1], s[2])
		"lump": _lump(k, r, s[1], s[2], s[3])
		"charcoal": _charcoal(k, r)
		"halite": _halite(k, r, s[1])
		"crystals": _crystals(k, r, t, s[1], s[2], s[3], s[4])
		"amber": _amber(k, r)
		"log":
			# Leaned toward the eye so a sawn end with its rings shows.
			_log(k, r, s[1], s[2], s[3])
			return _transformed(k.commit(mat), Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3.ZERO))
		"split": _split(k, r)
		"planks": _planks(k, r)
		"brick": _brick(k, r, s[1], s[2], s[3], s[4])
		"briquettes": _briquettes(k, r)
		"cake": _cake(k, s[1])
		"hide": _hide(k, r, s[1], s[2], s[3])
		"leather": _leather(k, r)
		"im:bone": _bone(k, r)
		"antler": _antler(k, r)
		"fang": _fang(k)
		"rope": _rope(k, r, s[1], s[2])
		"cloth": _cloth(k, r, s[1])
		"skein": _skein(k, r, s[1])
		"bundle": _bundle(k, r, s[1], s[2])
		"nails":
			_nails(k, r)
			var nm := k.commit(mat)
			# Pinched near the bottom, so most of the handful shows above the fingers.
			nm.set_meta("grip", Vector3(0, 0.012, 0))
			nm.set_meta("grip_r", 0.014)
			return nm
		"gears": _gears(k)
		"spring": _spring(k)
		"pipe": _pipe(k)
		"valve": _valve(k)
		"gauge": _gauge(k)
		"piston": _piston(k)
		"spool": _spool(k, s[1])
		"sheet": _sheet_item(k, r, s[1], s[2], s[3])
		"pane": _pane(k)
	return k.commit(mat)

# --- Geometry helpers -------------------------------------------------------------------

## The mesh with every surface moved by `xf` (positions, normals, tangents).
static func _transformed(src: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for j in v.size():
			v[j] = xf * v[j]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for j in n.size():
				n[j] = xf.basis * n[j]
			arr[Mesh.ARRAY_NORMAL] = n
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for j in range(0, tg.size(), 4):
				var tv := xf.basis * Vector3(tg[j], tg[j + 1], tg[j + 2])
				tg[j] = tv.x
				tg[j + 1] = tv.y
				tg[j + 2] = tv.z
			arr[Mesh.ARRAY_TANGENT] = tg
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(i, src.surface_get_material(i))
	return out

## A triangle facing whichever way its vertex normals point (so callers need not track
## winding).
static func _tri(k: MeshKit, m: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) < 0.0:
		k.tri(m, xf, a, c, b, na, nc, nb, col)
	else:
		k.tri(m, xf, a, b, c, na, nb, nc, col)

## A flat quad facing `out`.
static func _quad(k: MeshKit, m: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 1e-9:
		n = (c - a).cross(d - a)
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
	_tri(k, m, xf, a, b, c, n, n, n, col)
	_tri(k, m, xf, a, c, d, n, n, n, col)

## Rings of equal point count, stacked bottom to top, skinned with flat quads and capped:
## chamfered blocks, bars, boards.
static func _loft(k: MeshKit, m: String, xf: Transform3D, rings: Array, col: Color, cap_m := "", cap_col := Color.WHITE) -> void:
	var n: int = (rings[0] as PackedVector3Array).size()
	var cm := m if cap_m == "" else cap_m
	var cc := col if cap_m == "" else cap_col
	for i in rings.size() - 1:
		var lo: PackedVector3Array = rings[i]
		var hi: PackedVector3Array = rings[i + 1]
		var mid := (_centroid(lo) + _centroid(hi)) * 0.5
		for j in n:
			var j2 := (j + 1) % n
			var face := (lo[j] + lo[j2] + hi[j] + hi[j2]) * 0.25
			_quad(k, m, xf, lo[j], lo[j2], hi[j2], hi[j], face - mid, col)
	for e: int in [0, rings.size() - 1]:
		var ring: PackedVector3Array = rings[e]
		var c := _centroid(ring)
		var out := Vector3.DOWN if e == 0 else Vector3.UP
		for j in n:
			_tri(k, cm, xf, c, ring[j], ring[(j + 1) % n], out, out, out, cc)

static func _centroid(p: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in p:
		c += v
	return c / maxf(p.size(), 1)

## A rectangle (half sizes hx, hz) at height y with its corners cut by e: 8 points.
static func _rect(hx: float, hz: float, y: float, e: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(hx, y, hz - e), Vector3(hx - e, y, hz), Vector3(-hx + e, y, hz), Vector3(-hx, y, hz - e),
		Vector3(-hx, y, -hz + e), Vector3(-hx + e, y, -hz), Vector3(hx - e, y, -hz), Vector3(hx, y, -hz + e)])

## A box with bevelled edges (size along x, y, z), centred on xf's origin.
static func _block(k: MeshKit, m: String, xf: Transform3D, size: Vector3, bevel: float, col: Color, taper := 1.0) -> void:
	var h := size * 0.5
	var e := minf(bevel, minf(h.x, h.z) * 0.5)
	var b := minf(bevel, h.y * 0.5)
	_loft(k, m, xf, [_rect(h.x - b, h.z - b, -h.y, e), _rect(h.x, h.z, -h.y + b, e),
		_rect(h.x * taper, h.z * taper, h.y - b, e), _rect(h.x * taper - b, h.z * taper - b, h.y, e)], col)

## A tube along `path` with radius per point (`radii`), smooth shaded, ends capped.
static func _tube(k: MeshKit, m: String, xf: Transform3D, path: PackedVector3Array, radii: PackedFloat32Array, segs: int, col: Color, caps := true) -> void:
	var n := path.size()
	if n < 2:
		return
	var rings: Array = []
	var norms: Array = []
	var side := Vector3.ZERO
	for i in n:
		var t: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		if side == Vector3.ZERO or absf(side.dot(t)) > 0.95:
			side = (Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).cross(t).normalized()
		# Carry the frame along (parallel transport) so the tube doesn't twist.
		side = (side - t * side.dot(t)).normalized()
		var up := t.cross(side)
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for s in segs:
			var a := TAU * s / segs
			var d := side * cos(a) + up * sin(a)
			ring.append(path[i] + d * radii[i])
			nr.append(d)
		rings.append(ring)
		norms.append(nr)
	for i in n - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][s2]
			var c: Vector3 = rings[i + 1][s2]
			var d: Vector3 = rings[i + 1][s]
			_tri(k, m, xf, a, b, c, norms[i][s], norms[i][s2], norms[i + 1][s2], col)
			_tri(k, m, xf, a, c, d, norms[i][s], norms[i + 1][s2], norms[i + 1][s], col)
	if caps:
		for e: int in [0, n - 1]:
			var out := (path[0] - path[1]).normalized() if e == 0 else (path[n - 1] - path[n - 2]).normalized()
			if radii[e] < 0.0005:
				continue
			for s in segs:
				_tri(k, m, xf, path[e], rings[e][s], rings[e][(s + 1) % segs], out, out, out, col)

## A sheet with thickness: `f(u, v)` (u, v in 0..1) gives the mid-surface; the top is
## coloured `top`, the underside `under`, the cut rim `under` too. Smooth shaded.
static func _sheet(k: MeshKit, m: String, xf: Transform3D, f: Callable, nu: int, nv: int, thick: float, top: Color, under: Color, m_under := "") -> void:
	var mu := m if m_under == "" else m_under
	var pts: Array = []
	var nrm: Array = []
	for i in nu + 1:
		var row: Array = []
		for j in nv + 1:
			row.append(f.call(float(i) / nu, float(j) / nv))
		pts.append(row)
	for i in nu + 1:
		var row: Array = []
		for j in nv + 1:
			var du: Vector3 = pts[mini(i + 1, nu)][j] - pts[maxi(i - 1, 0)][j]
			var dv: Vector3 = pts[i][mini(j + 1, nv)] - pts[i][maxi(j - 1, 0)]
			row.append(du.cross(dv).normalized())
		nrm.append(row)
	var h := thick * 0.5
	for side: float in [1.0, -1.0]:
		var mm: String = m if side > 0.0 else mu
		var col: Color = top if side > 0.0 else under
		for i in nu:
			for j in nv:
				var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				var p: Array = []
				var n: Array = []
				for c in q:
					var nn: Vector3 = nrm[c[0]][c[1]] * side
					p.append(pts[c[0]][c[1]] + nn * h)
					n.append(nn)
				_tri(k, mm, xf, p[0], p[1], p[2], n[0], n[1], n[2], col)
				_tri(k, mm, xf, p[0], p[2], p[3], n[0], n[2], n[3], col)
	# The rim, all round.
	var edge: Array = []
	for i in nu:
		edge.append([i, 0])
	for j in nv:
		edge.append([nu, j])
	for i in range(nu, 0, -1):
		edge.append([i, nv])
	for j in range(nv, 0, -1):
		edge.append([0, j])
	var mid: Vector3 = pts[nu / 2][nv / 2]
	for e in edge.size():
		var c0: Array = edge[e]
		var c1: Array = edge[(e + 1) % edge.size()]
		var p0: Vector3 = pts[c0[0]][c0[1]]
		var p1: Vector3 = pts[c1[0]][c1[1]]
		var n0: Vector3 = nrm[c0[0]][c0[1]] * h
		var n1: Vector3 = nrm[c1[0]][c1[1]] * h
		var out := ((p0 + p1) * 0.5 - mid).normalized()
		_quad(k, mu, xf, p0 - n0, p1 - n1, p1 + n1, p0 + n0, out, under)

## A disc (or annulus from r0) facing `n` about centre c, as a fan.
static func _disc(k: MeshKit, m: String, xf: Transform3D, c: Vector3, n: Vector3, r1: float, segs: int, col: Color, r0 := 0.0) -> void:
	var a := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
	var b := n.cross(a)
	for s in segs:
		var t0 := TAU * s / segs
		var t1 := TAU * (s + 1) / segs
		var d0 := a * cos(t0) + b * sin(t0)
		var d1 := a * cos(t1) + b * sin(t1)
		if r0 <= 0.0:
			_tri(k, m, xf, c, c + d0 * r1, c + d1 * r1, n, n, n, col)
		else:
			_quad(k, m, xf, c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0, n, col)

## A torus about +Y (major radius R, tube radius rt) at xf.
static func _torus(k: MeshKit, m: String, xf: Transform3D, R: float, rt: float, segs: int, tsegs: int, col: Color) -> void:
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in segs + 1:
		var a := TAU * i / segs
		path.append(Vector3(cos(a) * R, 0, sin(a) * R))
		radii.append(rt)
	_tube(k, m, xf, path, radii, tsegs, col, false)

static func _rot(axis: Vector3, angle: float, at := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis(axis.normalized(), angle), at)

# --- Metal ------------------------------------------------------------------------------

## A cast bar. Real ones taper from the mould (narrow face up), their edges are rounded
## by the mould's draft, the poured top dips and pits where the metal shrank as it
## cooled, and the smith's stamp sits sunk in it. Base metals tarnish in patches.
static func _metal(k: MeshKit, r: RandomNumberGenerator, s: Array, t: String) -> void:
	match String(s[6]):
		"currency": _currency_bar(k, r, s[1], s[2], s[3], s[4])
		"billet": _billet(k, r, s[1], s[2], s[5], t)
		"bun": _bun(k, r, s[1], s[2], s[3], s[4])
		"oxhide": _oxhide(k, r, s[1], s[2], s[3], s[4])
		_: _bar(k, r, s[1], s[2], s[3], s[4], s[5], t)

## Tarnish: dull, discoloured patches dotted over a surface given by `at(u, v)` -> [p, n].
static func _patina(k: MeshKit, r: RandomNumberGenerator, xf: Transform3D, col: Color, patina: Color, amount: float, at: Callable) -> void:
	for i in int(amount * 12.0):
		var pn: Array = at.call(r.randf(), r.randf())
		_disc(k, "im:metal@0.7", xf, pn[0] + pn[1] * 0.0004, pn[1], r.randf_range(0.004, 0.012), 9, col.lerp(patina, r.randf_range(0.25, 0.5)))

static func _currency_bar(k: MeshKit, r: RandomNumberGenerator, col: Color, rough: float, patina: Color, amount: float) -> void:
	# A smith's iron currency bar: long, flat and hammered, tapering to a point at one end
	# and a pinched socket at the other, uneven along its length, scale and rust on it.
	var path := PackedVector3Array()
	var rings: Array = []
	var n := 12
	for i in n + 1:
		var t := float(i) / n
		var y := -0.05 + t * 0.32
		var w := 0.02 * (0.55 + 0.45 * sin(clampf(t * 1.25, 0.0, 1.0) * PI * 0.5)) * (1.0 - smoothstep(0.82, 1.0, t) * 0.85)
		var th := 0.006 * (1.0 - smoothstep(0.85, 1.0, t) * 0.6) + r.randf_range(-0.0006, 0.0006)
		rings.append(_rect(w, th, y, minf(th, w) * 0.45))
	var m := "im:metal@%.2f" % rough
	# _rect lays rings in xz at height y; the bar runs up y, so _loft them as stacked.
	_loft(k, m, Transform3D.IDENTITY, rings, col)
	_patina(k, r, Transform3D.IDENTITY, col, patina, amount, func(u: float, v: float) -> Array:
		var side := 1.0 if u < 0.5 else -1.0
		return [Vector3((v - 0.5) * 0.02, -0.04 + u * 0.24, 0.0062 * side), Vector3(0, 0, side)])
	# Hammer facets across it.
	for i in 6:
		var y := -0.03 + i * 0.045 + r.randf_range(-0.01, 0.01)
		_disc(k, m, Transform3D.IDENTITY, Vector3(r.randf_range(-0.006, 0.006), y, 0.0066), Vector3(0, 0.15, 1).normalized(), 0.008, 8, col.darkened(0.12))

static func _billet(k: MeshKit, r: RandomNumberGenerator, col: Color, rough: float, length: float, t: String) -> void:
	# A machined billet: square section, crisp chamfers, saw-cut ends with fine arcs of
	# the blade, and the heat/grade number laser-etched along one face.
	var m := "im:metal@%.2f" % rough
	var w := length * 0.22
	_block(k, m, Transform3D(Basis.IDENTITY, Vector3(0, length * 0.5 - 0.04, 0)), Vector3(w, length, w), 0.0025, col)
	for end: float in [-0.04 - 0.0002, length - 0.04 + 0.0002]:
		var n := Vector3.DOWN if end < 0.0 else Vector3.UP
		for a in 5:
			var rr := 0.02 + a * 0.012
			var segs := 8
			for sgi in segs:
				var a0 := lerpf(-0.5, 0.5, float(sgi) / segs)
				var a1 := lerpf(-0.5, 0.5, float(sgi + 1) / segs)
				var c := Vector3(-0.06, end, 0)
				var p0 := c + Vector3(cos(a0), 0, sin(a0)) * rr
				var p1 := c + Vector3(cos(a1), 0, sin(a1)) * rr
				if absf(p0.x) > w * 0.48 or absf(p0.z) > w * 0.48 or absf(p1.x) > w * 0.48 or absf(p1.z) > w * 0.48:
					continue
				_quad(k, m, Transform3D.IDENTITY, p0, p1, p1 + Vector3(0.0006, 0, 0), p0 + Vector3(0.0006, 0, 0), n, col.darkened(0.25))
	# The etched code: short marks of different lengths in a line, like characters.
	var x := -length * 0.3
	var h := WHash.str_hash(t)
	for i in 7:
		var cw := 0.003 + 0.002 * float((h >> i) & 1)
		_quad(k, m, Transform3D.IDENTITY, Vector3(-w * 0.5 - 0.0003, x, -0.004), Vector3(-w * 0.5 - 0.0003, x + cw, -0.004),
			Vector3(-w * 0.5 - 0.0003, x + cw, 0.004), Vector3(-w * 0.5 - 0.0003, x, 0.004), Vector3.LEFT, col.darkened(0.6))
		x += cw + 0.003

static func _bun(k: MeshKit, r: RandomNumberGenerator, col: Color, rough: float, patina: Color, amount: float) -> void:
	# A plano-convex copper ingot: the metal pooled in the furnace bottom, so a domed,
	# rough underside and a flat, blistered, wrinkled top, held on edge.
	var m := "im:metal@%.2f" % rough
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.05, 0))
	var R := 0.065
	k.sphere(m, xf, R, 8, 22, 0.08, 0.32, col, true)
	k.cylinder(m, xf, R * 0.98, R * 0.98, 0.002, 22, true, 0.06, 1, col.darkened(0.08))
	for i in 14:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * R * 0.8
		_disc(k, m, xf, Vector3(cos(a) * d, 0.0024, sin(a) * d), Vector3.UP, r.randf_range(0.002, 0.007), 7, col.darkened(r.randf_range(0.15, 0.4)))
	_patina(k, r, xf, col, patina, amount, func(u: float, v: float) -> Array:
		var a := u * TAU
		var d := sqrt(v) * R * 0.85
		return [Vector3(cos(a) * d, 0.0026, sin(a) * d), Vector3.UP])

static func _oxhide(k: MeshKit, r: RandomNumberGenerator, col: Color, rough: float, patina: Color, amount: float) -> void:
	# A Bronze Age oxhide ingot: a thick slab whose four corners are drawn out into
	# handles (the shape of a stretched hide), the cast top rough and slightly dished.
	var m := "im:metal@%.2f" % rough
	var ring := PackedVector3Array()
	var pts := 32
	for i in pts:
		var a := TAU * i / pts
		var c := Vector2(cos(a), sin(a))
		# A rounded rectangle pinched in at the middle of each side (the concave edges).
		var rr := 1.0 + 0.32 * pow(absf(sin(a * 2.0)), 6.0) - 0.12 * pow(absf(cos(a * 2.0)), 2.0)
		ring.append(Vector3(c.x * 0.055 * rr, 0, c.y * 0.085 * rr))
	var th := 0.012
	var rings: Array = []
	for y: float in [-th * 0.5, th * 0.5]:
		var q := PackedVector3Array()
		for p in ring:
			q.append(Vector3(p.x, y, p.z))
		rings.append(q)
	# Stood on edge in the hand: slab's y becomes z.
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.05, 0))
	_loft(k, m, xf, rings, col)
	_patina(k, r, xf, col, patina, amount, func(u: float, v: float) -> Array:
		return [Vector3((u - 0.5) * 0.08, th * 0.5, (v - 0.5) * 0.13), Vector3.UP])
	for i in 10:
		_disc(k, m, xf, Vector3(r.randf_range(-0.04, 0.04), th * 0.5 + 0.0003, r.randf_range(-0.07, 0.07)), Vector3.UP, r.randf_range(0.0015, 0.004), 7, col.darkened(0.15))

static func _bar(k: MeshKit, r: RandomNumberGenerator, col: Color, rough: float, _patina_col: Color, _amount: float, length: float, _t: String) -> void:
	var m := "im:metal@%.2f" % rough
	var hw := length * 0.27
	var ht := length * 0.17
	var e := 0.0045
	# Built lying down (length along x, the stamped face up, +y) and turned so that face
	# looks at the viewer (+Z) with the length across: a low, wide bar held by its lower
	# edge, as you would hold an ingot up to look at it.
	var xf := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), Vector3(0, hw, 0))
	var c := col
	_loft(k, m, xf, [_rect(length * 0.5 - e, hw - e, -ht * 0.5, e), _rect(length * 0.5, hw, -ht * 0.5 + e, e),
		_rect(length * 0.45, hw * 0.78, ht * 0.5 - e, e), _rect(length * 0.45 - e, hw * 0.78 - e, ht * 0.5, e)], c)
	# The poured face (the wide underside): shrink pits and wrinkles.
	for i in 9:
		var p := Vector3(r.randf_range(-0.38, 0.38) * length, -ht * 0.5 - 0.0004, r.randf_range(-0.7, 0.7) * hw)
		_disc(k, m, xf, p, Vector3.DOWN, r.randf_range(0.003, 0.008), 7, c.darkened(0.35))
	# Foundry marks struck straight into the metal near one end: a short line of maker's
	# letters and a serial, each stroke a shallow dark nick, slightly uneven in spacing
	# and depth, with no panel round them.
	var top_y := ht * 0.5 + 0.0003
	var cx := -length * 0.22
	for line in 2:
		var lx := cx + line * length * 0.07
		var count := 4 if line == 0 else 5
		var span := hw * (0.9 if line == 0 else 0.7)
		for i in count:
			var lz := lerpf(-span * 0.5, span * 0.5, (i + 0.5) / count) + r.randf_range(-0.001, 0.001)
			var cell := span / count * 0.32
			for st in 2 + r.randi() % 2:
				var a0 := Vector3(lx + r.randf_range(-1, 1) * cell * 1.4, top_y, lz + r.randf_range(-1, 1) * cell)
				var a1 := Vector3(lx + r.randf_range(-1, 1) * cell * 1.4, top_y, lz + r.randf_range(-1, 1) * cell)
				var w := (a1 - a0).cross(Vector3.UP).normalized() * 0.0005
				_quad(k, m, xf, a0 - w, a1 - w, a1 + w, a0 + w, Vector3.UP, c.darkened(r.randf_range(0.3, 0.45)))
	# Tarnish rides in the material's roughness; spotted patches read as stickers here.

static func _nugget(k: MeshKit, r: RandomNumberGenerator, col: Color, size: float) -> void:
	# Water-worn gold: one irregular, flattened lump with softened, folded edges and a
	# smaller lobe grown onto its side, quartz grit caught in the hollows.
	_rock(k, "im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1.0, 0.65, 0.8)), Vector3(0, size * 0.6, 0)), size, 0.18, r, col)
	_rock(k, "im:metal@0.3", Transform3D(Basis.from_scale(Vector3(0.8, 0.6, 0.7)), Vector3(size * 0.75, size * 0.45, size * 0.15)), size * 0.5, 0.2, r, col.darkened(0.05))
	for i in 5:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.4, 0.6), r.randf_range(-1, 1)).normalized()
		k.sphere("im:stone", Transform3D(Basis.IDENTITY, Vector3(0, size * 0.6, 0) + d * Vector3(size, size * 0.6, size * 0.8) * 0.82), size * 0.08, 4, 5, 0.4, 1.0, Color(0.85, 0.83, 0.78))

# --- Rock and mineral -------------------------------------------------------------------

## Ore as it comes off the face: a broken, angular piece of host rock with the mineral in
## seams and crusts through it, not a smooth pebble.
static func _ore(k: MeshKit, r: RandomNumberGenerator, t: String, s: Array) -> void:
	var m := "im:ore:" + t
	var size := 0.05
	var pieces := 1 if t == "stone" else 2
	for i in pieces:
		var sc := size * (1.0 if i == 0 else 0.6)
		var at := Vector3(r.randf_range(-0.2, 0.2) * size, sc * 0.6 + i * size * 0.9, 0)
		var xf := Transform3D(Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU)), at)
		_rock(k, m, xf, sc, s[6], r, s[1])
		if s[4] <= 0.0:
			continue
		# The mineral as grains and crystals set into the rock and broken open with it:
		# metallic ores glint as bright cubes and plates, others as glassy crystals.
		var metallic: bool = s[5] > 0.45
		for g in 9:
			var d := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()
			var gp := d * sc * r.randf_range(0.55, 0.72)
			var gs := sc * r.randf_range(0.07, 0.16)
			var gc: Color = (s[2] as Color).lerp(s[3], r.randf() * 0.5)
			var gb := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, r.randf() * TAU))
			if metallic:
				_block(k, "im:metal@0.25", xf * Transform3D(gb, gp), Vector3(gs, gs * r.randf_range(0.4, 1.0), gs), gs * 0.08, gc)
			else:
				k.crystal("im:crystal:" + t, xf * Transform3D(Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d)) if d.cross(Vector3.UP).length() > 0.01 else Basis.IDENTITY, gp - d * gs * 0.5), gs * 0.35, gs * 1.6, 6, 0.3, Color(gc.r, gc.g, gc.b, 0.9))

## A broken rock: a lump cut by a few flat fracture planes (the angular faces that make
## rock read as broken stone rather than clay).
static func _rock(k: MeshKit, m: String, xf: Transform3D, size: float, angular: float, r: RandomNumberGenerator, col: Color) -> void:
	var rings := 7
	var segs := 10
	var noise := FastNoiseLite.new()
	noise.seed = r.randi()
	noise.frequency = 2.2
	var planes: Array = []
	for i in 3 + int(angular * 4.0):
		var n := Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()
		planes.append([n, size * r.randf_range(0.55, 0.8)])
	var grid: Array = []
	for ri in rings + 1:
		var phi := PI * ri / rings
		var row: Array = []
		for si in segs:
			var th := TAU * si / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi) * 0.8, sin(phi) * sin(th) * 0.85)
			var p := d * size * (1.0 + 0.3 * noise.get_noise_3dv(d))
			for pl in planes:
				var over: float = p.dot(pl[0]) - pl[1]
				if over > 0.0:
					p -= pl[0] * over * angular * 1.5
			row.append(p)
		grid.append(row)
	for ri in rings:
		for si in segs:
			var s2 := (si + 1) % segs
			var a: Vector3 = grid[ri][si]
			var b: Vector3 = grid[ri][s2]
			var c: Vector3 = grid[ri + 1][s2]
			var d: Vector3 = grid[ri + 1][si]
			# Faceted: each quad its own flat normal, like fractured rock.
			var ctr := (a + b + c + d) * 0.25
			_quad(k, m, xf, a, b, c, d, ctr, col)

static func _lump(k: MeshKit, r: RandomNumberGenerator, m: String, col: Color, size: float) -> void:
	# A lump torn or wire-cut off a block: flat cut faces meeting rounded, pinched sides,
	# thumb dents pressed in, a few crumbs stuck on.
	_rock(k, m, Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(0, size * 0.75, 0)), size, 0.55, r, col)
	for i in 3:
		var a := r.randf() * TAU
		var d := Vector3(cos(a), r.randf_range(-0.2, 0.4), sin(a)).normalized()
		_disc(k, m, Transform3D.IDENTITY, Vector3(0, size * 0.75, 0) + d * size * 0.78, d, size * 0.18, 10, col.darkened(0.12))
	for i in 4:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.6, 0.8), r.randf_range(-1, 1)).normalized()
		k.sphere(m, Transform3D(Basis.IDENTITY, Vector3(0, size * 0.75, 0) + d * size * 0.85), size * 0.07, 4, 5, 0.4, 1.0, col.darkened(0.05))

static func _charcoal(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A handful of lump charcoal: broken, angular pieces of charred wood of different
	# sizes, black with a faint silvery sheen, grain lines still showing.
	for i in 5:
		var sz := r.randf_range(0.018, 0.034)
		var at := Vector3(r.randf_range(-0.025, 0.025), 0.02 + i * 0.012 + r.randf() * 0.01, r.randf_range(-0.02, 0.02))
		var xf := Transform3D(Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, 0)) * Basis.from_scale(Vector3(1.0, 1.5, 0.8)), at)
		_rock(k, "im:charcoal", xf, sz, 0.9, r, Color(0.06, 0.055, 0.05))

static func _halite(k: MeshKit, r: RandomNumberGenerator, col: Color) -> void:
	# Rock salt: a crust of cubic crystals all grown in the same orientation, of many
	# sizes, interpenetrating, with stepped (hopper) hollows in their faces, on a broken
	# lump of cloudy massive salt.
	_rock(k, "im:salt", Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), 0.035, 0.85, r, col.darkened(0.08))
	var b := Basis.from_euler(Vector3(0.2, 0.5, 0.1))
	for i in 14:
		var sz := 0.03 * pow(r.randf(), 1.6) + 0.006
		var p := Vector3(r.randf_range(-0.03, 0.03), 0.03 + r.randf_range(0.0, 0.04), r.randf_range(-0.025, 0.025))
		var xf := Transform3D(b, p)
		_block(k, "im:salt", xf, Vector3.ONE * sz, sz * 0.04, col.darkened(r.randf() * 0.12))
		if sz > 0.015:
			# The hopper step: a smaller, darker square set into the face looking out.
			_quad(k, "im:salt", xf, Vector3(-sz * 0.3, -sz * 0.3, sz * 0.501), Vector3(sz * 0.3, -sz * 0.3, sz * 0.501), Vector3(sz * 0.3, sz * 0.3, sz * 0.501), Vector3(-sz * 0.3, sz * 0.3, sz * 0.501), Vector3.BACK, col.darkened(0.25))

static func _crystals(k: MeshKit, r: RandomNumberGenerator, t: String, col: Color, alpha: float, count: int, glow: bool) -> void:
	# A cluster on its matrix rock: hexagonal points of different sizes leaning out from a
	# shared root, each with flat faces that catch the light.
	var m := ("im:crystal_glow:" if glow else "im:crystal:") + t
	_rock(k, "im:stone", Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0)), 0.03, 0.6, r, Color(0.4, 0.38, 0.36))
	for i in count:
		var lean := r.randf_range(0.35, 0.9) if i > 0 else 0.08
		var a := r.randf() * TAU
		var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), lean) * Basis(Vector3.UP, r.randf() * TAU)
		var h := r.randf_range(0.05, 0.11) * (1.3 if i == 0 else 1.0)
		var cxf := Transform3D(b, Vector3(cos(a) * 0.018, 0.022, sin(a) * 0.014) * (0.0 if i == 0 else 1.0) + Vector3(0, 0.02 if i == 0 else 0.0, 0))
		var cr := h * r.randf_range(0.12, 0.2)
		k.crystal(m, cxf, cr, h, 6, 0.22, Color(col.r, col.g, col.b, alpha))
		if alpha < 0.95:
			# Flaws: a couple of pale, half-clear fracture veils caught inside the body,
			# which break up the flat facets the way real quartz does.
			for f in 2:
				var fy := h * r.randf_range(0.2, 0.6)
				var fa := r.randf() * TAU
				var fd := Vector3(cos(fa), 0, sin(fa)) * cr * 0.55
				var up := Vector3(0, h * r.randf_range(0.12, 0.25), 0)
				var side := fd.cross(Vector3.UP).normalized() * cr * 0.3
				_quad(k, "im:crystal:" + t, cxf, Vector3(0, fy, 0) - fd - side, Vector3(0, fy, 0) + fd - side, Vector3(0, fy, 0) + fd + side + up, Vector3(0, fy, 0) - fd + side + up,
					side.cross(up).normalized(), Color(1, 1, 1, 0.35))
			# A cloudy core and a veil of flaws inside, as real crystals have.
			k.crystal("im:crystal:" + t, cxf.translated_local(Vector3(0, h * 0.05, 0)), cr * 0.45, h * 0.6, 6, 0.3, Color(col.lightened(0.5).r, col.lightened(0.5).g, col.lightened(0.5).b, 0.5))

static func _amber(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A lump of resin as it is gathered from bark: one irregular, glassy piece with a
	# fleck of bark caught inside.
	_rock(k, "im:resin", Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 0.8)), Vector3(0, 0.035, 0)), 0.03, 0.25, r, Color(0.85, 0.5, 0.12, 0.8))
	_block(k, "bark", Transform3D(Basis.from_euler(Vector3(0.3, 0.7, 0.2)), Vector3(-0.004, 0.04, 0.004)), Vector3(0.008, 0.004, 0.006), 0.0, Color(0.25, 0.16, 0.08))

# --- Timber -----------------------------------------------------------------------------

## The cut end of a log: pith, heartwood, pale sapwood, growth rings, a couple of radial
## checks where it dried, then the bark round it.
static func _end_grain(k: MeshKit, xf: Transform3D, c: Vector3, n: Vector3, rad: float, rings: int, heart: Color, r: RandomNumberGenerator) -> void:
	var sap := heart.lightened(0.35)
	for i in rings:
		var r0 := rad * i / rings
		var r1 := rad * (i + 1) / rings
		var f := float(i) / rings
		var col := heart.lerp(sap, smoothstep(0.55, 0.75, f))
		col = col.darkened(0.12 if i % 2 == 0 else 0.0)
		_disc(k, "im:endgrain", xf, c + n * 0.0001 * i, n, r1, 16, col, r0)
	var a := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
	var b := n.cross(a)
	for i in 2:
		var ang := r.randf() * TAU
		var d := a * cos(ang) + b * sin(ang)
		var w := d.cross(n) * 0.0012
		_quad(k, "im:endgrain", xf, c + n * 0.002 + d * rad * 0.15 - w, c + n * 0.002 + d * rad * 0.92 - w * 0.2, c + n * 0.002 + d * rad * 0.92 + w * 0.2, c + n * 0.002 + d * rad * 0.15 + w, n, Color(0.05, 0.03, 0.02))

static func _log(k: MeshKit, r: RandomNumberGenerator, length: float, rad: float, heart: Color) -> void:
	# A bucked log: ridged bark (wobbled), a knot where a branch was, sawn ends.
	k.cylinder("bark", Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), rad, rad * 0.94, length, 14, false, 0.08, 6)
	var y0 := -0.04
	_end_grain(k, Transform3D.IDENTITY, Vector3(0, y0 - 0.0005, 0), Vector3.DOWN, rad * 0.93, 9, heart, r)
	_end_grain(k, Transform3D.IDENTITY, Vector3(0, y0 + length + 0.0005, 0), Vector3.UP, rad * 0.88, 9, heart, r)
	var a := r.randf() * TAU
	var kp := Vector3(cos(a) * rad * 0.95, y0 + length * 0.62, sin(a) * rad * 0.95)
	k.cylinder("bark", Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -PI * 0.5), kp), rad * 0.22, rad * 0.16, rad * 0.12, 8)

static func _split(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A split of firewood: a quarter round, bark on the outside, rough torn faces where the
	# axe split it along the grain, sawn ends with rings.
	for i in 1:
		var rad := 0.085
		var l := 0.3
		# Turned so a split face and the bark both show on +Z.
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.75), Vector3(0.03, -0.04, 0.03))
		var arc := 8
		var a0 := 0.0
		var a1 := PI * 0.5
		var heart := Color(0.6, 0.45, 0.3)
		for e: float in [0.0, l]:
			var ring := PackedVector3Array([Vector3(0, e, 0)])
			for s in arc + 1:
				var a := lerpf(a0, a1, float(s) / arc)
				ring.append(Vector3(cos(a) * rad, e, sin(a) * rad))
			var n := Vector3.DOWN if e == 0.0 else Vector3.UP
			for s in arc:
				var f := float(s) / arc
				_tri(k, "im:endgrain", xf, ring[0], ring[s + 1], ring[s + 2], n, n, n, heart.lerp(heart.lightened(0.3), f * 0.3))
			# Growth rings as arcs.
			for g in 5:
				var gr := rad * (g + 1) / 6.0
				for s in arc:
					var p0 := Vector3(cos(lerpf(a0, a1, float(s) / arc)), 0, sin(lerpf(a0, a1, float(s) / arc))) * gr
					var p1 := Vector3(cos(lerpf(a0, a1, float(s + 1) / arc)), 0, sin(lerpf(a0, a1, float(s + 1) / arc))) * gr
					var off := Vector3(0, e + n.y * 0.0004, 0)
					var w0 := p0.normalized() * 0.0007
					var w1 := p1.normalized() * 0.0007
					_quad(k, "im:endgrain", xf, p0 - w0 + off, p1 - w1 + off, p1 + w1 + off, p0 + w0 + off, n, heart.darkened(0.3))
		for s in arc:
			var a := lerpf(a0, a1, float(s) / arc)
			var b := lerpf(a0, a1, float(s + 1) / arc)
			var p0 := Vector3(cos(a) * rad, 0, sin(a) * rad)
			var p1 := Vector3(cos(b) * rad, 0, sin(b) * rad)
			_quad(k, "bark", xf, p0, p1, p1 + Vector3(0, l, 0), p0 + Vector3(0, l, 0), (p0 + p1) * 0.5, Color.WHITE)
		# Split faces: torn, fibrous, not sawn flat.
		for face: Vector3 in [Vector3(rad, 0, 0), Vector3(0, 0, rad)]:
			var out := Vector3(0, 0, -1) if face.x > 0.0 else Vector3(-1, 0, 0)
			var strips := 5
			for g in strips:
				var t0 := float(g) / strips
				var t1 := float(g + 1) / strips
				var bump := Vector3(out) * -r.randf_range(-0.002, 0.003)
				_quad(k, "im:splitwood", xf, face * t0 + bump, face * t1 + bump, face * t1 + bump + Vector3(0, l, 0), face * t0 + bump + Vector3(0, l, 0), out, heart.lightened(r.randf_range(0.1, 0.25)))

static func _planks(k: MeshKit, r: RandomNumberGenerator) -> void:
	# Sawn boards: a few stacked, slightly different in colour and cut, saw-marked ends
	# showing the arcs of the rings, nail holes from reuse.
	# Two boards carried together, fanned apart so each reads as a thin board.
	for i in 2:
		var w := r.randf_range(0.1, 0.13)
		var l := r.randf_range(0.4, 0.46)
		var th := 0.016
		var col := Color(1, 1, 1).darkened(r.randf_range(0.0, 0.18))
		var xf := Transform3D(Basis(Vector3.FORWARD, (i - 0.5) * 0.35) * Basis(Vector3.UP, (i - 0.5) * 0.5), Vector3((i - 0.5) * 0.05, l * 0.5 - 0.06, (i - 0.5) * th * 2.5))
		var h := Vector3(w * 0.5, l * 0.5, th * 0.5)
		var e := 0.0015
		var rings := [_rect(h.x - e, h.z - e, -h.y, e * 0.5), _rect(h.x, h.z, -h.y + e, e * 0.5), _rect(h.x, h.z, h.y - e, e * 0.5), _rect(h.x - e, h.z - e, h.y, e * 0.5)]
		_loft(k, "planks", xf, rings, col, "im:endgrain", Color(0.62, 0.47, 0.32).darkened(r.randf() * 0.15))
		for g in 4:
			var gr := w * (0.4 + g * 0.15)
			for end: float in [-1.0, 1.0]:
				var y := h.y * end + end * 0.0003
				var c := Vector3(r.randf_range(-0.2, 0.2) * w, y, -gr * 0.9)
				var segs := 6
				for s in segs:
					var a0 := lerpf(PI * 0.35, PI * 0.65, float(s) / segs)
					var a1 := lerpf(PI * 0.35, PI * 0.65, float(s + 1) / segs)
					var p0 := c + Vector3(cos(a0), 0, sin(a0)) * gr
					var p1 := c + Vector3(cos(a1), 0, sin(a1)) * gr
					if absf(p0.z) > h.z or absf(p1.z) > h.z or absf(p0.x) > h.x or absf(p1.x) > h.x:
						continue
					_quad(k, "im:endgrain", xf, p0 - Vector3(0, 0, 0.0006), p1 - Vector3(0, 0, 0.0006), p1 + Vector3(0, 0, 0.0006), p0 + Vector3(0, 0, 0.0006), Vector3(0, end, 0), Color(0.3, 0.2, 0.12))
		if i == 1:
			for n in 2:
				_disc(k, "im:endgrain", xf, Vector3((n - 0.5) * w * 0.6, h.y * 0.7, h.z + 0.0003), Vector3.BACK, 0.0018, 6, Color(0.08, 0.06, 0.05))

# --- Blocks -----------------------------------------------------------------------------

static func _brick(k: MeshKit, r: RandomNumberGenerator, m: String, col: Color, size: Vector3, frog: bool) -> void:
	# A fired brick is never a perfect box: slightly warped and rounded at the arrises,
	# the sanded faces darker where the kiln flashed them, and a frog pressed in the bed.
	var xf := Transform3D(Basis(Vector3.UP, r.randf_range(-0.05, 0.05)), Vector3(0, size.y * 0.5 - 0.05, 0))
	_block(k, m, xf, Vector3(size.z, size.y, size.x), 0.004, col)
	if frog:
		var f := Vector3(size.z * 0.5 + 0.0003, 0, 0)
		var fw := size.x * 0.25
		var fl := size.y * 0.3
		_quad(k, m, xf, f + Vector3(0, -fl, -fw), f + Vector3(0, fl, -fw), f + Vector3(0, fl, fw), f + Vector3(0, -fl, fw), Vector3.RIGHT, col.darkened(0.35))
	for i in 5:
		var p := Vector3(-size.z * 0.5 - 0.0003, r.randf_range(-0.4, 0.4) * size.y, r.randf_range(-0.35, 0.35) * size.x)
		_disc(k, m, xf, p, Vector3.LEFT, r.randf_range(0.006, 0.014), 7, col.darkened(r.randf_range(0.15, 0.35)))

static func _briquettes(k: MeshKit, r: RandomNumberGenerator) -> void:
	# Pressed coal briquettes: pillow-shaped, matte black-brown, with a pressed seam.
	for i in 5:
		var xf := Transform3D(Basis.from_euler(Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))), Vector3(r.randf_range(-0.025, 0.025), 0.02 + i * 0.022, r.randf_range(-0.015, 0.015)))
		k.sphere("im:charcoal", xf, 0.022, 7, 10, 0.05, 0.6, Color(0.08, 0.075, 0.07))

static func _cake(k: MeshKit, col: Color) -> void:
	# A cake of beeswax as poured into a bowl: domed underside, flat top with a skin of
	# bloom, translucent at the edges.
	k.cylinder("im:wax", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.015)), 0.045, 0.05, 0.03, 20, true)
	_disc(k, "im:wax", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.015)), Vector3(0, 0.0303, 0), Vector3.UP, 0.044, 20, col.lightened(0.15))
	k.sphere("im:wax", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.015)), 0.045, 8, 20, 0.0, 0.35, col, true)

# --- Animal -----------------------------------------------------------------------------

## A skin rolled up for carrying, hair outward and tied: the roll is lumpy and uneven, the
## pale flesh side shows in the spiral at the ends, and a leg of the skin hangs loose.
static func _hide(k: MeshKit, r: RandomNumberGenerator, m: String, hair: Color, flesh: Color) -> void:
	_roll(k, r, m, hair, flesh, 0.04, 0.24, 0.12, "im:hide", Color(0.3, 0.2, 0.12))
	# The hair: tufts lying along the roll, one way, longer and darker at their roots.
	var long := 0.02 if m == "im:fur" else 0.011
	for i in 420:
		var a := r.randf() * TAU
		var y := r.randf_range(-0.035, 0.195)
		var base := Vector3(cos(a) * 0.043, y, sin(a) * 0.043)
		var out := Vector3(cos(a), 0, sin(a))
		var tip := base + out * long * 0.35 + Vector3(0, -long, 0) + Vector3(-sin(a), 0, cos(a)) * long * r.randf_range(-0.3, 0.3)
		_tube(k, "im:fur", Transform3D.IDENTITY, PackedVector3Array([base, (base + tip) * 0.5 + out * long * 0.15, tip]), PackedFloat32Array([0.0034, 0.0024, 0.0004]), 4, hair.darkened(r.randf_range(-0.1, 0.3)), false)

static func _roll(k: MeshKit, r: RandomNumberGenerator, m: String, outer: Color, inner: Color, rad: float, l: float, lump: float, tie_m: String, tie: Color) -> void:
	k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), rad, rad * 0.95, l, 18, false, lump, 5, outer)
	for e: float in [-0.04, -0.04 + l]:
		var n := Vector3.DOWN if e < 0.0 else Vector3.UP
		var turns := 4
		var segs := 48
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for s in segs:
			var t := float(s) / segs
			var rr := lerpf(rad * 0.15, rad * (0.97 - lump * 0.5), t)
			var a := t * TAU * turns
			path.append(Vector3(cos(a) * rr, e + n.y * 0.0005, sin(a) * rr))
			radii.append(0.0011)
		_tube(k, m, Transform3D.IDENTITY, path, radii, 4, outer.darkened(0.3))
		_disc(k, "im:flesh", Transform3D.IDENTITY, Vector3(0, e + n.y * 0.0002, 0), n, rad * (1.0 - lump * 0.5), 18, inner)
	for y: float in [0.02, l - 0.11]:
		_torus(k, tie_m, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), rad * (1.0 + lump * 0.4) + 0.0015, 0.0018, 18, 5, tie)

static func _leather(k: MeshKit, r: RandomNumberGenerator) -> void:
	# Tanned leather, rolled and tied with a thong: smooth grain side outward, the suede
	# flesh side showing in the spiral at the ends.
	_roll(k, r, "leather", Color.WHITE, Color(0.5, 0.36, 0.24), 0.032, 0.22, 0.03, "im:hide", Color(0.3, 0.2, 0.12))

static func _bone(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A long bone: a slightly bowed, waisted shaft flaring to knobbed ends (two condyles
	# at one, a rounded head at the other), ivory with a dull, porous surface.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var t := i / 8.0
		path.append(Vector3(sin(t * PI) * 0.008, -0.04 + t * 0.22, 0))
		radii.append(0.011 + 0.008 * pow(absf(t - 0.5) * 2.0, 3.0))
	_tube(k, "im:bone", Transform3D.IDENTITY, path, radii, 10, Color(0.88, 0.84, 0.74))
	k.sphere("im:bone", Transform3D(Basis.IDENTITY, Vector3(-0.008, -0.045, 0.006)), 0.016, 6, 8, 0.15, 1.0, Color(0.86, 0.82, 0.72))
	k.sphere("im:bone", Transform3D(Basis.IDENTITY, Vector3(0.008, -0.045, -0.006)), 0.015, 6, 8, 0.15, 1.0, Color(0.86, 0.82, 0.72))
	k.sphere("im:bone", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.185, 0)), 0.02, 7, 10, 0.12, 0.9, Color(0.9, 0.86, 0.76))

static func _antler(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A shed antler: the burr at the base, a beam that sweeps back and up, ridged and
	# furrowed brown, with tines whose polished tips are paler.
	var beam := PackedVector3Array()
	var br := PackedFloat32Array()
	for i in 10:
		var t := i / 9.0
		beam.append(Vector3(-0.06 * t * t, -0.03 + t * 0.32, 0.03 * sin(t * PI)))
		br.append(lerpf(0.016, 0.006, t))
	_tube(k, "im:antler", Transform3D.IDENTITY, beam, br, 8, Color(0.5, 0.38, 0.26))
	_torus(k, "im:antler", Transform3D(Basis.IDENTITY, Vector3(0, -0.028, 0)), 0.017, 0.006, 12, 5, Color(0.42, 0.32, 0.22))
	for tine: Array in [[2, 0.1, 0.4], [5, 0.08, -0.3], [7, 0.06, 0.5]]:
		var at: Vector3 = beam[tine[0]]
		var p := PackedVector3Array()
		var pr := PackedFloat32Array()
		for i in 6:
			var t := i / 5.0
			p.append(at + Vector3(t * tine[1] * 0.8, t * tine[1] * 0.6 + t * t * 0.02, t * tine[1] * float(tine[2])))
			pr.append(lerpf(br[tine[0]] * 0.8, 0.0015, t))
		_tube(k, "im:antler", Transform3D.IDENTITY, p, pr, 6, Color(0.55, 0.43, 0.3).lerp(Color(0.88, 0.82, 0.7), 0.3))

static func _fang(k: MeshKit) -> void:
	# A great curved tooth: the enamelled crown polished and pointed, the root rough and
	# stained where it sat in the jaw.
	var p := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in 10:
		var t := i / 9.0
		p.append(Vector3(0.04 * t * t, -0.03 + t * 0.15, 0))
		rr.append(lerpf(0.016, 0.0008, pow(t, 1.3)))
	_tube(k, "im:enamel", Transform3D.IDENTITY, p, rr, 10, Color(0.92, 0.9, 0.82))
	k.cylinder("im:bone", Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0)), 0.011, 0.0155, 0.032, 10, true, 0.15, 2, Color(0.62, 0.5, 0.36))

# --- Fibre and textiles -----------------------------------------------------------------

static func _rope(k: MeshKit, r: RandomNumberGenerator, col: Color, rad: float) -> void:
	# A coil of laid rope: loops stacked into a hank, each strand twisting (three strands
	# laid together show as a spiral of ridges), the hank bound round the middle.
	var loops := 6
	var segs := 20
	for l in loops:
		var R := 0.07 + r.randf_range(-0.004, 0.004)
		var tilt := Basis(Vector3.FORWARD, r.randf_range(-0.12, 0.12)) * Basis(Vector3.UP, r.randf_range(-0.08, 0.08))
		var c := Vector3(0, 0.07, (l - loops * 0.5) * rad * 1.7)
		for strand in 3:
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for s in segs * 3 + 1:
				var a := TAU * s / (segs * 3)
				var tw := a * 18.0 + strand * TAU / 3.0
				var base := Vector3(cos(a) * R, sin(a) * R * 1.1, 0)
				var radial := base.normalized()
				var off := radial * cos(tw) * rad * 0.45 + Vector3(0, 0, 1) * sin(tw) * rad * 0.45
				path.append(c + tilt * (base + off) - tilt * Vector3.ZERO)
				radii.append(rad * 0.58)
			_tube(k, "im:rope", Transform3D.IDENTITY, path, radii, 5, col.darkened(strand * 0.06), false)
	# The binding: a few turns of the rope's end round the hank where it is held.
	# Turns go round the bottom of the hank (across the loops' stack, along z).
	var zc := -rad * 0.85
	var half := loops * 0.5 * rad * 1.7
	for i in 4:
		var x := -0.012 + i * rad * 1.5
		var y := 0.07 - 0.07 * 1.1
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for sgi in 17:
			var a := TAU * sgi / 16.0
			path.append(Vector3(x, y + sin(a) * rad * 1.3, zc + cos(a) * (half + rad * 0.4)))
			radii.append(rad * 0.55)
		_tube(k, "im:rope", Transform3D.IDENTITY, path, radii, 5, col.darkened(0.1), false)

static func _cloth(k: MeshKit, r: RandomNumberGenerator, col: Color) -> void:
	# A bolt of woven cloth folded into a stack: soft rounded folds at the front, the
	# layers slightly out of line, the selvedge edge showing a band.
	var w := 0.2
	var d := 0.12
	var th := 0.014
	for i in 4:
		var xf := Transform3D(Basis(Vector3.UP, r.randf_range(-0.04, 0.04)), Vector3(r.randf_range(-0.004, 0.004), -0.03 + i * th, 0))
		var h := Vector3(w * 0.5, th * 0.48, d * 0.5)
		var top := func(u: float, v: float) -> Vector3:
			return Vector3((u - 0.5) * w, h.y + sin(u * PI * 7.0) * 0.0006, (v - 0.5) * d)
		_sheet(k, "im:linen", xf, top, 8, 4, 0.004, col.darkened(i * 0.02), col.darkened(0.08))
		_sheet(k, "im:linen", xf, func(u: float, v: float) -> Vector3:
			var a := v * PI
			return Vector3((u - 0.5) * w, cos(a) * h.y, d * 0.5 + sin(a) * h.y), 8, 6, 0.004, col.darkened(i * 0.02), col.darkened(0.08))
		_quad(k, "im:linen", xf, Vector3(-w * 0.5, h.y - 0.0005, -d * 0.5 - 0.0005), Vector3(w * 0.5, h.y - 0.0005, -d * 0.5 - 0.0005),
			Vector3(w * 0.5, h.y - 0.0035, -d * 0.5 - 0.0005), Vector3(-w * 0.5, h.y - 0.0035, -d * 0.5 - 0.0005), Vector3.FORWARD, col.darkened(0.25))

static func _skein(k: MeshKit, r: RandomNumberGenerator, col: Color) -> void:
	# Spun wool in a twisted skein: many yarn loops wound round each other, fuzzy and
	# matte, with the off-white of undyed fleece.
	var segs := 40
	for strand in 10:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		var ph := strand * TAU / 10.0
		for s in segs + 1:
			var t := float(s) / segs
			var a := t * TAU
			# A long loop twisted on itself twice along its length.
			var y := sin(a) * 0.1 + 0.07
			var x := cos(a) * 0.02
			var tw := t * TAU * 2.0 + ph
			path.append(Vector3(x + cos(tw) * 0.012, y, sin(tw) * 0.012))
			radii.append(0.0055)
		_tube(k, "im:wool", Transform3D.IDENTITY, path, radii, 6, col.darkened(r.randf() * 0.08), false)

static func _bundle(k: MeshKit, r: RandomNumberGenerator, col: Color, heads: bool) -> void:
	# A sheaf of stalks tied in the middle with a twist of the same, the cut ends showing
	# as hollow straws, ears of grain nodding at the top.
	var n := 22
	for i in n:
		var a := r.randf() * TAU
		var rr := sqrt(r.randf()) * 0.018
		var top := Vector3(cos(a) * rr * 2.2, 0.26 + r.randf() * 0.03, sin(a) * rr * 2.2)
		var bot := Vector3(cos(a) * rr * 1.6, -0.06, sin(a) * rr * 1.6)
		var mid := Vector3(cos(a) * rr, 0.09, sin(a) * rr)
		var path := PackedVector3Array([bot, mid, top])
		var c := col.darkened(r.randf() * 0.15)
		_tube(k, "im:straw", Transform3D.IDENTITY, path, PackedFloat32Array([0.0018, 0.0016, 0.0012]), 4, c, false)
		if heads:
			var dir := (top - mid).normalized()
			k.sphere("im:straw", Transform3D(Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir.cross(Vector3.UP).length() > 0.001 else Basis.IDENTITY, top + dir * 0.02), 0.006, 5, 6, 0.1, 4.0, c.lightened(0.05))
	_torus(k, "im:straw", Transform3D(Basis.IDENTITY, Vector3(0, 0.09, 0)), 0.02, 0.0035, 14, 5, col.darkened(0.25))

# --- Worked metal -----------------------------------------------------------------------

static func _nails(k: MeshKit, r: RandomNumberGenerator) -> void:
	# A small handful of hand-forged nails held together: square shanks tapering to a
	# chisel point, flat hammered heads, dark iron with rust towards the points.
	for i in 12:
		var lay := Basis(Vector3.UP, r.randf_range(-0.6, 0.6)) * Basis(Vector3.FORWARD, r.randf_range(-0.4, 0.4))
		var at := Vector3(r.randf_range(-0.012, 0.012), 0.045, r.randf_range(-0.01, 0.01))
		var xf := Transform3D(lay, at)
		var l := r.randf_range(0.075, 0.095)
		var rust := Color(0.42, 0.4, 0.38).lerp(Color(0.45, 0.24, 0.12), r.randf_range(0.0, 0.5))
		var flip := 1.0 if i % 3 != 0 else -1.0
		var fb := Basis(Vector3.RIGHT, 0.0 if flip > 0.0 else PI)
		k.cylinder("im:metal@0.7", xf * Transform3D(fb, Vector3.ZERO).translated_local(Vector3(0, -l * 0.5, 0)), 0.003, 0.0006, l, 4, false, 0.0, 1, rust)
		k.cylinder("im:metal@0.6", xf * Transform3D(fb, Vector3.ZERO).translated_local(Vector3(0, -l * 0.5 - 0.0018, 0)), 0.006, 0.0055, 0.0022, 7, true, 0.0, 1, Color(0.36, 0.34, 0.32))

static func _gear(k: MeshKit, xf: Transform3D, rad: float, th: float, teeth: int, col: Color) -> void:
	k.cylinder("im:metal@0.35", xf, rad, rad, th, 32, true, 0.0, 1, col)
	for i in teeth:
		var a := TAU * i / teeth
		var b := Basis(Vector3.UP, -a)
		_block(k, "im:metal@0.35", xf * Transform3D(b, b * Vector3(rad + 0.003, th * 0.5, 0)), Vector3(0.007, th, rad * TAU / teeth * 0.45), 0.0008, col)
	k.cylinder("im:metal@0.3", xf.translated_local(Vector3(0, -0.001, 0)), rad * 0.25, rad * 0.25, th + 0.002, 16, true, 0.0, 1, col.darkened(0.2))
	# Spokes cut out: dark windows on both faces.
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		for face: float in [th + 0.0003, -0.0003]:
			_disc(k, "im:metal@0.6", xf, Vector3(cos(a) * rad * 0.6, face, sin(a) * rad * 0.6), Vector3.UP if face > 0.0 else Vector3.DOWN, rad * 0.22, 10, Color(0.04, 0.04, 0.04))

static func _gears(k: MeshKit) -> void:
	# Two machined gears meshed together on a pin: cut teeth, a hub, lightening holes,
	# oily steel and a brass one.
	_gear(k, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.006)), 0.04, 0.01, 18, Color(0.62, 0.62, 0.64))
	_gear(k, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.1, 0.006)), 0.025, 0.01, 12, Color(0.8, 0.62, 0.34))

static func _spring(k: MeshKit) -> void:
	# A coil spring: round wire wound in a helix, the ends ground flat.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var turns := 9.0
	var segs := 160
	for s in segs + 1:
		var t := float(s) / segs
		var a := t * TAU * turns
		var y := -0.03 + t * 0.12
		if t < 0.06:
			y = -0.03 + 0.0
		elif t > 0.94:
			y = 0.09
		path.append(Vector3(cos(a) * 0.016, y, sin(a) * 0.016))
		radii.append(0.0022)
	_tube(k, "im:metal@0.3", Transform3D.IDENTITY, path, radii, 6, Color(0.55, 0.56, 0.6))

static func _pipe(k: MeshKit) -> void:
	# A length of pipe with a bolted flange at each end: hollow (you see in), the bore
	# dark and rusty, the outside painted and chipped.
	var l := 0.24
	var ro := 0.024
	var ri := 0.02
	var col := Color(0.32, 0.36, 0.32)
	k.cylinder("im:metal@0.6", Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), ro, ro, l, 18, false, 0.0, 1, col)
	k.cylinder("im:bore", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.04 + l, 0)), ri, ri, l, 18, false, 0.0, 1, Color(0.3, 0.18, 0.1))
	for e: float in [-0.04, -0.04 + l - 0.008]:
		k.cylinder("im:metal@0.5", Transform3D(Basis.IDENTITY, Vector3(0, e, 0)), 0.04, 0.04, 0.008, 22, false, 0.0, 1, col.darkened(0.1))
		for face: float in [e, e + 0.008]:
			var n := Vector3.DOWN if face == e else Vector3.UP
			_disc(k, "im:metal@0.5", Transform3D.IDENTITY, Vector3(0, face, 0), n, 0.04, 22, col.darkened(0.1), ri)
		for b in 6:
			var a := TAU * b / 6.0
			k.cylinder("im:metal@0.45", Transform3D(Basis.IDENTITY, Vector3(cos(a) * 0.032, e - 0.003, sin(a) * 0.032)), 0.004, 0.004, 0.014, 6, true, 0.0, 1, Color(0.5, 0.5, 0.52))

static func _valve(k: MeshKit) -> void:
	# A brass gate valve: cast body between two threaded stubs, a bonnet, a spindle and a
	# red-painted iron handwheel with spokes.
	var brass := Color(0.82, 0.62, 0.32)
	k.sphere("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), 0.026, 8, 14, 0.0, 1.0, brass)
	k.cylinder("im:metal@0.4", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.05, 0.03, 0)), 0.014, 0.014, 0.1, 14, true, 0.0, 1, brass.darkened(0.08))
	k.cylinder("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, 0.045, 0)), 0.014, 0.011, 0.035, 12, true, 0.0, 1, brass)
	k.cylinder("im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)), 0.003, 0.003, 0.03, 8, true, 0.0, 1, Color(0.6, 0.6, 0.62))
	var wheel := Color(0.55, 0.1, 0.08)
	_torus(k, "im:paint", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 0.03, 0.0035, 22, 6, wheel)
	for i in 4:
		var a := TAU * i / 4.0
		var p := PackedVector3Array([Vector3(0, 0.1, 0), Vector3(cos(a) * 0.03, 0.1, sin(a) * 0.03)])
		_tube(k, "im:paint", Transform3D.IDENTITY, p, PackedFloat32Array([0.0025, 0.0025]), 5, wheel)
	k.cylinder("im:paint", Transform3D(Basis.IDENTITY, Vector3(0, 0.096, 0)), 0.006, 0.006, 0.008, 8, true, 0.0, 1, wheel)

static func _gauge(k: MeshKit) -> void:
	# A pressure gauge: a brass case, a domed glass over a white dial with tick marks and a
	# black needle, a threaded stem below.
	var brass := Color(0.82, 0.62, 0.32)
	var face := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.07, 0))
	k.cylinder("im:metal@0.35", face.translated_local(Vector3(0, -0.012, 0)), 0.04, 0.04, 0.018, 28, true, 0.0, 1, brass)
	_torus(k, "im:metal@0.3", face.translated_local(Vector3(0, 0.006, 0)), 0.04, 0.003, 28, 6, brass.lightened(0.1))
	_disc(k, "im:dial", face, Vector3(0, 0.0065, 0), Vector3.UP, 0.037, 28, Color(0.93, 0.92, 0.88))
	for i in 11:
		var a := lerpf(-PI * 0.75, PI * 0.75, i / 10.0) - PI * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		var w := Vector3(-d.z, 0, d.x) * 0.0006
		var y := 0.0068
		var r0 := 0.026 if i % 5 else 0.022
		_quad(k, "im:dial", face, d * r0 - w + Vector3(0, y, 0), d * 0.033 - w + Vector3(0, y, 0), d * 0.033 + w + Vector3(0, y, 0), d * r0 + w + Vector3(0, y, 0), Vector3.UP, Color(0.05, 0.05, 0.05))
	var na := -PI * 0.2 - PI * 0.5
	var nd := Vector3(cos(na), 0, sin(na))
	var nw := Vector3(-nd.z, 0, nd.x) * 0.0012
	_quad(k, "im:dial", face, -nd * 0.006 - nw + Vector3(0, 0.0072, 0), nd * 0.03 + Vector3(0, 0.0072, 0), nd * 0.03 + Vector3(0, 0.0072, 0) + nw * 0.1, -nd * 0.006 + nw + Vector3(0, 0.0072, 0), Vector3.UP, Color(0.02, 0.02, 0.02))
	_disc(k, "im:dial", face, Vector3(0, 0.0074, 0), Vector3.UP, 0.003, 8, Color(0.05, 0.05, 0.05))
	k.sphere("im:glass", face.translated_local(Vector3(0, 0.006, 0)), 0.037, 6, 24, 0.0, 0.18, Color(0.9, 0.95, 1.0, 0.18), true)
	k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.007, 0.007, 0.05, 6, true, 0.0, 1, brass.darkened(0.1))
	_block(k, "im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), Vector3(0.018, 0.012, 0.018), 0.001, brass)

static func _piston(k: MeshKit) -> void:
	# A piston: a turned crown with ring grooves, a skirt, the gudgeon pin through it and
	# a connecting rod, machined steel darkened with old oil.
	var steel := Color(0.6, 0.6, 0.62)
	var y := 0.06
	k.cylinder("im:metal@0.25", Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), 0.035, 0.035, 0.06, 24, true, 0.0, 1, steel)
	for g in 3:
		_torus(k, "im:metal@0.6", Transform3D(Basis.IDENTITY, Vector3(0, y + 0.05 - g * 0.007, 0)), 0.035, 0.0012, 24, 4, Color(0.12, 0.11, 0.1))
	_disc(k, "im:metal@0.5", Transform3D.IDENTITY, Vector3(0, y + 0.0602, 0), Vector3.UP, 0.034, 24, Color(0.25, 0.22, 0.2))
	k.cylinder("im:metal@0.3", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.037, y + 0.018, 0)), 0.008, 0.008, 0.074, 10, true, 0.0, 1, steel.lightened(0.1))
	_block(k, "im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, y - 0.035, 0)), Vector3(0.016, 0.11, 0.01), 0.002, steel.darkened(0.15))
	_torus(k, "im:metal@0.4", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, y - 0.09, 0)), 0.018, 0.006, 18, 6, steel.darkened(0.15))

static func _spool(k: MeshKit, col: Color) -> void:
	# Wire on a wooden reel: two turned flanges, the core hidden under neat turns of
	# bright copper, the loose end trailing off.
	var w := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.035, 0.04, 0))
	for f: float in [0.0, 0.064]:
		k.cylinder("planks", w.translated_local(Vector3(0, f, 0)), 0.045, 0.045, 0.006, 20, true, 0.0, 1, Color(0.85, 0.75, 0.6))
	k.cylinder("planks", w, 0.015, 0.015, 0.07, 12, true, 0.0, 1, Color(0.8, 0.7, 0.55))
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var layers := 5
	var per := 26
	var segs := 10
	for l in layers:
		var rr := 0.018 + l * 0.0045
		for t in per * segs:
			var a := TAU * t / segs
			var x := 0.006 + (float(t) / (per * segs)) * 0.058
			if l % 2 == 1:
				x = 0.064 - (x - 0.006)
			path.append(Vector3(cos(a) * rr, x, sin(a) * rr))
			radii.append(0.0021)
	_tube(k, "im:metal@0.25", w, path, radii, 4, col, false)

static func _sheet_item(k: MeshKit, r: RandomNumberGenerator, m: String, col: Color, th: float) -> void:
	# Rolled sheet: a flat plate (a slight bow from being carried), crisp sheared edges,
	# mill scale on the faces and a stencilled grade mark.
	var w := 0.2
	var l := 0.28
	var f := func(u: float, v: float) -> Vector3:
		var bend := smoothstep(0.75, 1.0, u) * smoothstep(0.75, 1.0, v)
		return Vector3((u - 0.5) * w, v * l - 0.05, sin(u * PI) * 0.006 + bend * 0.03)
	_sheet(k, m, Transform3D.IDENTITY, f, 10, 10, th, col, col.darkened(0.12))
	# The edges rolled over into a bead, so the plate shows its thickness and is safe to
	# carry, slightly darker where oxide gathers.
	var rim := PackedVector3Array()
	var rr := PackedFloat32Array()
	for e in 41:
		var t := e / 40.0
		var u := 0.0
		var v := 0.0
		if t < 0.25:
			u = t * 4.0
		elif t < 0.5:
			u = 1.0
			v = (t - 0.25) * 4.0
		elif t < 0.75:
			u = 1.0 - (t - 0.5) * 4.0
			v = 1.0
		else:
			v = 1.0 - (t - 0.75) * 4.0
		rim.append(f.call(u, v))
		rr.append(th * 1.6 + 0.0015)
	_tube(k, m, Transform3D.IDENTITY, rim, rr, 6, col.darkened(0.18), false)

static func _pane(k: MeshKit) -> void:
	# A pane of glass: clear with a faint green cast seen through its edge, reflections on
	# its faces, the cut edges ground.
	var w := 0.2
	var l := 0.28
	var th := 0.006
	_block(k, "im:glass", Transform3D(Basis.IDENTITY, Vector3(0, l * 0.5 - 0.05, 0)), Vector3(w, l, th), 0.0008, Color(0.86, 0.95, 0.9, 0.16))
	# Every cut edge seen end on is deep green (the iron in the glass), ground matte.
	for e: float in [-1.0, 1.0]:
		_block(k, "im:glass_edge", Transform3D(Basis.IDENTITY, Vector3(e * (w * 0.5 + 0.0006), l * 0.5 - 0.05, 0)), Vector3(0.0014, l, th * 1.02), 0.0, Color(0.3, 0.6, 0.45, 0.85))
		_block(k, "im:glass_edge", Transform3D(Basis.IDENTITY, Vector3(0, l * 0.5 - 0.05 + e * (l * 0.5 + 0.0006), 0)), Vector3(w, 0.0014, th * 1.02), 0.0, Color(0.3, 0.6, 0.45, 0.85))

# --- Armour -----------------------------------------------------------------------------

## The material and colour a piece of armour is made of, by its look (Outfit.look_of).
static func _armour_mat(style: int, col: Color) -> Array:
	match style:
		Outfit.STYLE_LEATHER:
			return ["im:leather_armour", col]
		Outfit.STYLE_MAIL:
			return ["im:mail", Color(col.r, col.g, col.b).darkened(0.1)]
		Outfit.STYLE_CLOTH:
			return ["im:linen", col]
		Outfit.STYLE_EXO:
			return ["im:composite", col]
		Outfit.STYLE_CRYSTAL:
			return ["im:metal@0.18", col]
	# Steel reflects about 55-60%: near-white item colours would read as chrome. Worn
	# plate is brushed and dulled by handling, never mirror-polished.
	return ["im:metal@0.6", Color(minf(col.r, 0.68), minf(col.g, 0.68), minf(col.b, 0.68))]

static func _armour(k: MeshKit, r: RandomNumberGenerator, t: String) -> void:
	var d := ItemDB.def(t)
	var lk := Outfit.look_of({"type": t})
	var style: int = lk["style"]
	var mc := _armour_mat(style, lk["color"])
	var m: String = mc[0]
	var c: Color = mc[1]
	if style == Outfit.STYLE_PLATE and t.contains("iron"):
		# Iron is darker and duller than steel, with a forge-black skin left on it.
		m = "im:metal@0.74"
		c = c.darkened(0.3)
	var soft := style == Outfit.STYLE_LEATHER or style == Outfit.STYLE_CLOTH
	var trim := "im:hide" if soft else ("im:composite" if style == Outfit.STYLE_EXO else m)
	match String(d.get("slot", "")):
		"head": _helm(k, m, c, style, trim)
		"chest": _hauberk(k, r, m, c) if style == Outfit.STYLE_MAIL else _cuirass(k, r, m, c, style, soft)
		"hands": _gauntlet(k, m, c, style, soft)
		"legs": _greave(k, m, c, style, soft)
		"feet": _boot(k, m, c, style, soft)
		"ring": _ring(k, t, c)
		"neck": _amulet(k, t, c)

static func _helm(k: MeshKit, m: String, c: Color, style: int, trim: String) -> void:
	# Held by its rim, crown up. Metal helms are a raised skull (a nasal helm: a ridge over
	# the crown, a riveted brow band, the nasal hammered out of the band itself), with a
	# quilted liner inside and leather chin straps hanging. Mail adds a coif; soft caps
	# are stitched panels; sci-fi helmets are closed with a tinted visor.
	var y := 0.06
	var R := 0.105
	var tall := 1.05 if style != Outfit.STYLE_CLOTH else 0.8
	var peak := 0.08 if style == Outfit.STYLE_PLATE or style == Outfit.STYLE_CRYSTAL else 0.0
	var dome := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var ph := v * PI * 0.5
		# A slight point at the crown, the way a raised skull is drawn up.
		var lift := 1.0 + peak * pow(cos(ph), 6.0)
		# Raised by hammer: shallow, uneven facets over the skull, not a turned sphere.
		var dent := 1.0 + 0.012 * sin(a * 11.0 + ph * 3.0) * sin(ph * 9.0) + 0.006 * sin(a * 23.0 - ph * 13.0)
		return Vector3(cos(a) * sin(ph) * R * dent, y + cos(ph) * R * tall * lift * dent, sin(a) * sin(ph) * R * dent)
	_sheet(k, m, Transform3D.IDENTITY, dome, 28, 10, 0.004, c, Color(0.2, 0.17, 0.13), "im:linen")
	var metal := style == Outfit.STYLE_PLATE or style == Outfit.STYLE_CRYSTAL or style == Outfit.STYLE_MAIL
	if metal:
		# The brow band: a flat strip round the rim, standing proud, riveted on.
		k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, y - 0.004, 0)), R + 0.003, R + 0.0035, 0.024, 32, false, 0.0, 1, c.darkened(0.08))
		_torus(k, m, Transform3D(Basis.IDENTITY, Vector3(0, y - 0.004, 0)), R + 0.002, 0.0025, 32, 5, c.darkened(0.1))
		for i in 14:
			var a := TAU * i / 14.0
			k.sphere(m, Transform3D(Basis.IDENTITY, Vector3(cos(a) * (R + 0.0038), y + 0.008, sin(a) * (R + 0.0038))), 0.0028, 4, 6, 0.0, 1.0, c.lightened(0.12))
		# The nasal: continuous with the band at the front (+z), tapering down over the nose.
		var f := func(u: float, v: float) -> Vector3:
			var w := lerpf(0.022, 0.014, v)
			var a := (u - 0.5) * w / R
			var rr := R + 0.0035 + v * 0.004
			return Vector3(sin(a) * rr, y + 0.008 - v * 0.075, cos(a) * rr)
		_sheet(k, m, Transform3D.IDENTITY, f, 2, 6, 0.003, c, c.darkened(0.3))
		# Chin straps: leather, riveted inside the band at each side, hanging down.
		for side: float in [-1.0, 1.0]:
			var path := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 7:
				var t := i / 6.0
				path.append(Vector3(side * (R - 0.004 - t * 0.012), y - 0.01 - t * 0.09, -0.01 + t * 0.02))
				radii.append(0.0035)
			_tube(k, "leather", Transform3D.IDENTITY, path, radii, 4, Color.WHITE)
		k.sphere("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(-R + 0.006, y - 0.098, 0.01)), 0.006, 4, 8, 0.0, 1.0, Color(0.55, 0.45, 0.28))
	if peak > 0.0:
		# The comb: a low ridge raised front to back over the crown.
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 15:
			var v := lerpf(-1.0, 1.0, i / 14.0)
			var p: Vector3 = dome.call(0.25 if v > 0.0 else 0.75, absf(v))
			path.append(p + Vector3(0, 0.0025, 0))
			radii.append(0.0035)
		_tube(k, m, Transform3D.IDENTITY, path, radii, 6, c)
	match style:
		Outfit.STYLE_MAIL:
			var f := func(u: float, v: float) -> Vector3:
				var a := lerpf(-PI * 0.8, PI * 0.8, u) + PI
				var rr := R * (1.0 + v * 0.25)
				return Vector3(sin(a) * rr, y - 0.02 - v * 0.13, cos(a) * rr)
			_sheet(k, "im:mail", Transform3D.IDENTITY, f, 16, 4, 0.004, c.darkened(0.15), c.darkened(0.4))
		Outfit.STYLE_EXO:
			var f := func(u: float, v: float) -> Vector3:
				var a := lerpf(-0.9, 0.9, u)
				return Vector3(sin(a) * (R + 0.004), y + 0.01 - v * 0.05, cos(a) * (R + 0.004))
			_sheet(k, "im:visor", Transform3D.IDENTITY, f, 10, 2, 0.003, Color(0.04, 0.05, 0.06), Color(0.04, 0.05, 0.06))
			k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, y - 0.1, 0)), R * 0.92, R, 0.1, 20, false, 0.0, 1, c)
		Outfit.STYLE_LEATHER, Outfit.STYLE_CLOTH:
			_torus(k, trim, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), R, 0.005, 24, 6, c.darkened(0.15))
			for i in 4:
				var a := TAU * i / 4.0
				var path := PackedVector3Array()
				var radii := PackedFloat32Array()
				for j in 9:
					var ph := lerpf(0.0, PI * 0.5, j / 8.0)
					path.append(Vector3(cos(a) * sin(ph), cos(ph) * tall, sin(a) * sin(ph)) * (R + 0.001) + Vector3(0, y, 0))
					radii.append(0.0018)
				_tube(k, "im:hide", Transform3D.IDENTITY, path, radii, 4, c.darkened(0.3), false)

static func _cuirass(k: MeshKit, r: RandomNumberGenerator, m: String, c: Color, style: int, soft: bool) -> void:
	# A body piece held by its lower edge. Plate: a breastplate shaped over chest and
	# belly with a central ridge, the neck and arm openings cut out with rolled edges,
	# a fauld of riveted lames below the waist, a flatter backplate behind, shoulder
	# straps lying over to it and buckled side straps. Mail and padded cloth hang soft;
	# leather is cut panels with stitched seams.
	var W := 0.19
	var H := 0.36
	var openings := func(u: float) -> float:
		# How far the top edge is cut down at this point across: the neck in the
		# middle, an arm hole at each side.
		# A shallow round neck scoop and rounded armholes, not a deep V.
		var dn := clampf(absf(u - 0.5) / 0.17, 0.0, 1.0)
		var neck := sqrt(1.0 - dn * dn) * 0.055
		var da := clampf(minf(u, 1.0 - u) / 0.16, 0.0, 1.0)
		var arms := sqrt(1.0 - da * da) * 0.13
		return neck + arms
	var front := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.5, 1.5, u)
		var top: float = H - openings.call(u)
		var y := v * top - 0.04
		var t := y / H
		# Swelling over the chest, drawn in at the waist.
		var depth := 0.075 + 0.03 * sin(clampf(t, 0.0, 1.0) * PI * 0.85 + 0.25) + 0.018 * exp(-pow((t - 0.62) / 0.22, 2.0))
		var ridge: float = 0.012 * exp(-pow((u - 0.5) / 0.04, 2.0)) * (0.3 + 0.7 * t) if not soft else 0.0
		var wide := W * (0.85 + 0.15 * smoothstep(0.5, 0.85, t))
		var p := Vector3(sin(a) * wide, y, cos(a) * depth + ridge)
		if soft:
			p.z += 0.004 * sin(u * 30.0) * (1.0 - t)
		return p
	var th := 0.004 if not soft else 0.008
	_sheet(k, m, Transform3D.IDENTITY, front, 18, 12, th, c, c.darkened(0.45))
	if soft:
		if style == Outfit.STYLE_LEATHER:
			for u: float in [0.3, 0.7]:
				var path := PackedVector3Array()
				var radii := PackedFloat32Array()
				for j in 12:
					var p: Vector3 = front.call(u, j / 11.0)
					path.append(p + Vector3(0, 0, 0.0045))
					radii.append(0.0012)
				_tube(k, "im:hide", Transform3D.IDENTITY, path, radii, 4, c.lightened(0.25), false)
		return
	# Rolled edges round the neck and arm openings (a thickened, turned-over rim).
	var rim := PackedVector3Array()
	var rr := PackedFloat32Array()
	for j in 25:
		var u := j / 24.0
		var p: Vector3 = front.call(u, 1.0)
		rim.append(p)
		rr.append(0.0045)
	_tube(k, m, Transform3D.IDENTITY, rim, rr, 6, c.lightened(0.05))
	# The backplate behind it: flatter, with the same openings.
	var back := func(u: float, v: float) -> Vector3:
		var p: Vector3 = front.call(u, v)
		# Closing the shell: it meets the breastplate at the sides.
		return Vector3(p.x, p.y, -absf(p.z) * 0.75)
	_sheet(k, m, Transform3D.IDENTITY, back, 14, 8, th, c.darkened(0.12), c.darkened(0.45))
	# Fauld: three lames below the waist, each lapping over the next, riveted at the sides.
	for i in 3:
		var y0 := -0.04 - i * 0.032
		var lame := func(u: float, v: float) -> Vector3:
			var a := lerpf(-1.25, 1.25, u)
			var flare := 1.0 + (i + v) * 0.04
			return Vector3(sin(a) * W * 0.86 * flare, y0 - v * 0.04, cos(a) * 0.08 * flare + 0.004 * (1.0 - v))
		_sheet(k, m, Transform3D.IDENTITY, lame, 14, 2, th, c.darkened(0.04 * i), c.darkened(0.45))
		for side: float in [0.08, 0.92]:
			var p: Vector3 = lame.call(side, 0.4)
			var a := lerpf(-1.25, 1.25, side)
			k.sphere(m, Transform3D(Basis.IDENTITY, p + Vector3(sin(a), 0, cos(a)) * 0.003), 0.0035, 4, 6, 0.0, 1.0, c.lightened(0.12))
	# Shoulder straps: leather, lying over the shoulders from the breast to the back,
	# buckled on the breastplate.
	for side: float in [-1.0, 1.0]:
		var u := 0.5 + side * 0.31
		var p0: Vector3 = front.call(u, 1.0)
		var p1: Vector3 = back.call(u, 1.0)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 9:
			var t := i / 8.0
			path.append(p0.lerp(p1, t) + Vector3(0, sin(t * PI) * 0.035 + 0.004, 0))
			radii.append(0.006)
		_tube(k, "leather", Transform3D.IDENTITY, path, radii, 4, Color.WHITE)
		var bp := p0 + Vector3(0, -0.03, 0.006)
		_torus(k, "im:metal@0.4", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), bp), 0.008, 0.0016, 10, 4, Color(0.6, 0.5, 0.3))
		k.sphere(m, Transform3D(Basis.IDENTITY, bp + Vector3(0, -0.015, -0.002)), 0.004, 4, 6, 0.0, 1.0, c.lightened(0.1))
		# Side strap round to the back at the waist.
		var s0: Vector3 = front.call(0.5 + side * 0.5, 0.35)
		var s1: Vector3 = back.call(0.5 + side * 0.5, 0.35)
		_tube(k, "leather", Transform3D.IDENTITY, PackedVector3Array([s0, (s0 + s1) * 0.5 + Vector3(side * 0.01, 0, 0), s1]), PackedFloat32Array([0.006, 0.006, 0.006]), 4, Color.WHITE)
		_torus(k, "im:metal@0.4", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), s0 + Vector3(side * 0.004, 0, 0)), 0.007, 0.0015, 10, 4, Color(0.6, 0.5, 0.3))

static func _hauberk(k: MeshKit, r: RandomNumberGenerator, m: String, c: Color) -> void:
	# A mail shirt as it is carried: folded into a heavy, sagging bundle about the size
	# of a loaf (a real hauberk is 8-10 kg of rings), the rows of rings showing at the
	# folds, a sleeve end and the hem hanging loose from the bottom.
	var W := 0.1
	var H := 0.13
	var D := 0.03
	for layer in 4:
		var z := D - layer * D * 0.6
		var f := func(u: float, v: float) -> Vector3:
			var x := (u - 0.5) * 2.0 * W * (1.0 - 0.05 * layer)
			var y := v * H * (1.0 - 0.03 * layer)
			# Folds bulge out between the creases and sag in the middle.
			var bulge := 0.012 * sin(v * PI) * sin(u * PI) + 0.004 * sin(u * PI * 5.0 + layer)
			return Vector3(x, y - 0.01 * sin(u * PI) * v, z + bulge * (1.0 if layer == 0 else 0.4))
		_sheet(k, m, Transform3D.IDENTITY, f, 12, 8, 0.006, c.darkened(0.05 * layer), c.darkened(0.4), m)
	# Rounded folded edges along the top and sides, where the mail turns over.
	for e in 3:
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 9:
			var t := i / 8.0
			match e:
				0: path.append(Vector3(lerpf(-W, W, t), H - 0.01 * sin(t * PI) + 0.004, -D * 0.4))
				1: path.append(Vector3(-W - 0.004, t * H, -D * 0.4))
				2: path.append(Vector3(W + 0.004, t * H, -D * 0.4))
			radii.append(D * 0.85)
		_tube(k, m, Transform3D.IDENTITY, path, radii, 8, c.darkened(0.1), true)
	# A sleeve end hanging out of the bottom, and a fold of the hem.
	var sleeve := PackedVector3Array([Vector3(W * 0.5, 0.02, 0.0), Vector3(W * 0.62, -0.03, 0.012), Vector3(W * 0.7, -0.07, 0.02)])
	_tube(k, m, Transform3D.IDENTITY, sleeve, PackedFloat32Array([0.03, 0.028, 0.026]), 10, c, false)
	var hem := func(u: float, v: float) -> Vector3:
		return Vector3(lerpf(-W * 0.9, W * 0.1, u), -v * 0.045 + 0.01, D * 0.6 + 0.006 * sin(u * PI * 4.0) + v * 0.01)
	_sheet(k, m, Transform3D.IDENTITY, hem, 8, 3, 0.005, c, c.darkened(0.4), m)

static func _gauntlet(k: MeshKit, m: String, c: Color, style: int, soft: bool) -> void:
	# A gauntlet as a hand just left it: a leather glove underneath, fingers half curled,
	# the thumb apart. Plate adds a flared hourglass cuff with a rolled rim, a domed plate
	# over the back of the hand and small overlapping scales along each finger.
	var glove := "leather" if not soft else m
	var gc := Color.WHITE if glove == "leather" else c
	# Palm and back of the hand: a flattened, slightly cupped body.
	k.sphere(glove, Transform3D(Basis.from_scale(Vector3(1.05, 1.2, 0.38)), Vector3(0, 0.075, 0.0)), 0.04, 8, 14, 0.04, 1.0, gc)
	# The cuff.
	if soft:
		k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), 0.042, 0.036, 0.085, 16, false, 0.05, 3, c)
	else:
		var cuff := func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var rr := lerpf(0.055, 0.037, pow(v, 0.7))
			return Vector3(cos(a) * rr, -0.045 + v * 0.085, sin(a) * rr * 0.85)
		_sheet(k, m, Transform3D.IDENTITY, cuff, 22, 5, 0.003, c, Color(0.12, 0.1, 0.08), "im:linen")
		_torus(k, m, Transform3D(Basis.from_scale(Vector3(1, 1, 0.85)), Vector3(0, -0.045, 0)), 0.055, 0.003, 24, 5, c.lightened(0.05))
		# The back-of-hand plate, domed over the knuckles, with a rivet at each corner.
		var plate := func(u: float, v: float) -> Vector3:
			var x := (u - 0.5) * 0.085
			return Vector3(x, 0.045 + v * 0.07, 0.022 + 0.01 * cos((u - 0.5) * PI) + 0.004 * sin(v * PI))
		_sheet(k, m, Transform3D.IDENTITY, plate, 6, 6, 0.003, c, c.darkened(0.4))
		for p: Vector3 in [Vector3(-0.035, 0.05, 0.029), Vector3(0.035, 0.05, 0.029), Vector3(-0.035, 0.108, 0.029), Vector3(0.035, 0.108, 0.029)]:
			k.sphere(m, Transform3D(Basis.IDENTITY, p), 0.003, 4, 6, 0.0, 1.0, c.lightened(0.1))
	for i in 4:
		var x := -0.03 + i * 0.02
		var l: float = [0.07, 0.078, 0.074, 0.058][i]
		var base := Vector3(x, 0.118, 0.0)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		# Three joints, each bent a little more towards the palm (-z).
		var dir := Vector3.UP
		var p := base
		for j in 4:
			path.append(p)
			radii.append(0.0088 - j * 0.0008)
			dir = dir.rotated(Vector3.RIGHT, -0.35)
			p += dir * l / 3.0
		_tube(k, glove, Transform3D.IDENTITY, path, radii, 8, gc)
		if not soft and style != Outfit.STYLE_EXO:
			for j in 3:
				var a: Vector3 = path[j]
				var b: Vector3 = path[j + 1]
				var mid := (a + b) * 0.5
				var d := (b - a).normalized()
				var bb := Basis(Vector3.RIGHT, Vector3.UP.signed_angle_to(d, Vector3.RIGHT))
				var f := func(u: float, v: float) -> Vector3:
					var ang := lerpf(-1.1, 1.1, u)
					return Vector3(sin(ang) * 0.0098, (v - 0.5) * l / 3.0 * 0.85, cos(ang) * 0.0098)
				_sheet(k, m, Transform3D(bb, mid), f, 5, 1, 0.0015, c.darkened(0.08), c.darkened(0.4))
	var thumb := PackedVector3Array([Vector3(0.04, 0.06, 0.008), Vector3(0.058, 0.09, 0.018), Vector3(0.062, 0.115, 0.03), Vector3(0.058, 0.135, 0.04)])
	_tube(k, glove, Transform3D.IDENTITY, thumb, PackedFloat32Array([0.011, 0.01, 0.009, 0.008]), 8, gc)

static func _greave(k: MeshKit, m: String, c: Color, style: int, soft: bool) -> void:
	# A leg piece: plate greaves are a shaped shell from ankle to knee with a domed knee
	# cop and side wings; soft legwear is folded in half.
	if soft or style == Outfit.STYLE_MAIL:
		var f := func(u: float, v: float) -> Vector3:
			return Vector3((u - 0.5) * lerpf(0.16, 0.2, v), v * 0.36 - 0.05, 0.01 * sin(u * PI) + 0.004 * sin(v * 40.0))
		_sheet(k, m, Transform3D.IDENTITY, f, 6, 10, 0.012, c, c.darkened(0.2))
		_block(k, "leather", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.012)), Vector3(0.2, 0.025, 0.006), 0.002, Color.WHITE)
		return
	var f := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.4, 1.4, u)
		# Calf swell, narrow ankle.
		var rr := 0.045 + 0.018 * sin(clampf(v * 1.4, 0.0, PI)) + 0.015 * smoothstep(0.75, 1.0, v)
		return Vector3(sin(a) * rr, v * 0.38 - 0.06, cos(a) * rr * 0.85)
	_sheet(k, m, Transform3D.IDENTITY, f, 12, 12, 0.004, c, c.darkened(0.45))
	k.sphere(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.33, 0.05)), 0.045, 8, 14, 0.0, 1.0, c, true)
	for v: float in [0.2, 0.5]:
		_block(k, "leather", Transform3D(Basis.IDENTITY, Vector3(0, v * 0.38 - 0.06, -0.045)), Vector3(0.1, 0.02, 0.006), 0.002, Color.WHITE)

static func _boot(k: MeshKit, m: String, c: Color, style: int, soft: bool) -> void:
	# A boot stood on its sole and held by the shaft: the foot lofted from heel to toe
	# (a high instep falling to a rounded toe), creases at the ankle, a stitched sole
	# welt standing just proud of the upper, a stacked heel, the opening dark inside.
	# Plate sabatons add overlapping lames over the toes.
	var L := 0.26
	var heel_y := -0.04
	var rings: Array = []
	var sole: Array = []
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		var w := 0.043 * (0.78 + 0.22 * sin(minf(t * 1.3, 1.0) * PI * 0.5)) * sqrt(maxf(1.0 - pow(maxf(t - 0.8, 0.0) / 0.2, 2.0) * 0.85, 0.05))
		var h := lerpf(0.085, 0.032, pow(t, 1.1)) * sqrt(maxf(1.0 - pow(maxf(t - 0.86, 0.0) / 0.14, 2.0) * 0.8, 0.05))
		if t < 0.05:
			w *= 0.85 + t * 3.0
		var ring := PackedVector3Array()
		var sr := PackedVector3Array()
		for j in 12:
			var a := PI * j / 11.0
			ring.append(Vector3(cos(a) * w, t * L, sin(a) * h))
			sr.append(Vector3(cos(a) * (w + 0.003), t * L, 0.0 if j > 0 and j < 11 else 0.0))
		# Flat underneath: the ring closes back along the bottom.
		ring.append(Vector3(-w * 0.5, t * L, 0.0))
		ring.append(Vector3(0.0, t * L, 0.0))
		ring.append(Vector3(w * 0.5, t * L, 0.0))
		rings.append(ring)
		var flat := PackedVector3Array()
		for j in 8:
			var a := TAU * j / 8.0
			flat.append(Vector3(cos(a) * (w + 0.003), t * L, -0.006 + sin(a) * 0.006))
		sole.append(flat)
	# Built along +y (length) with z up; turned so the toe points +z and up is +y.
	var xf := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), Vector3(0, heel_y, -0.05))
	# Plate sabatons are lames over a leather shoe, not a solid metal foot.
	var plate := not soft and style != Outfit.STYLE_MAIL
	_loft(k, "leather" if plate else m, xf, rings, Color(0.42, 0.32, 0.24) if plate else c)
	_loft(k, "leather", xf, sole, Color(0.3, 0.24, 0.2))
	# Stacked heel.
	_block(k, "leather", Transform3D(Basis.IDENTITY, Vector3(0, heel_y - 0.022, -0.02)), Vector3(0.07, 0.022, 0.065), 0.004, Color(0.26, 0.2, 0.16))
	# The shaft, rising from the back of the foot, creased at the ankle.
	var shaft := 0.17 if style != Outfit.STYLE_CLOTH else 0.06
	k.cylinder(m, Transform3D(Basis.IDENTITY, Vector3(0, heel_y + 0.03, -0.015)), 0.044, 0.048, shaft, 18, false, 0.05 if soft else 0.0, 6, c)
	_disc(k, "im:linen", Transform3D.IDENTITY, Vector3(0, heel_y + 0.03 + shaft - 0.003, -0.015), Vector3.UP, 0.046, 18, Color(0.08, 0.06, 0.05))
	_torus(k, m, Transform3D(Basis.IDENTITY, Vector3(0, heel_y + 0.03 + shaft, -0.015)), 0.048, 0.004, 18, 5, c.darkened(0.15))
	if soft:
		for i in 3:
			_torus(k, m, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, heel_y + 0.07 + i * 0.012, -0.012)), 0.0455, 0.0016, 18, 4, c.darkened(0.3))
		# Laces up the front of the shaft.
		for i in 5:
			var y := heel_y + 0.07 + i * 0.022
			_block(k, "im:rope", Transform3D(Basis(Vector3.BACK, 0.4 if i % 2 else -0.4), Vector3(0, y, 0.031)), Vector3(0.026, 0.003, 0.003), 0.0, Color(0.25, 0.18, 0.12))
	elif style != Outfit.STYLE_MAIL:
		# Sabaton lames over the toes, each lapping the one in front.
		for i in 5:
			var t := 0.3 + i * 0.12
			var lame := func(u: float, v: float) -> Vector3:
				var a := PI * u
				var w := 0.047 - i * 0.003
				var h := lerpf(0.075, 0.034, t) + 0.004
				return Vector3(cos(a) * w, (t + v * 0.13) * L, sin(a) * (h + 0.002 * (1.0 - v)))
			_sheet(k, m, xf, lame, 8, 1, 0.002, c.lightened(0.04), c.darkened(0.4))

static func _ring(k: MeshKit, t: String, c: Color) -> void:
	# A finger ring: a polished band with a bezel; a cut stone if it has one.
	var metal := Color(0.95, 0.78, 0.4) if t.contains("gold") or t.contains("ruby") else c
	_torus(k, "im:metal@0.15", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.0, 0)), 0.011, 0.0022, 24, 8, metal)
	if t.contains("ruby") or t.contains("gem") or t.contains("emerald") or t.contains("sapphire"):
		k.cylinder("im:metal@0.15", Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0)), 0.0045, 0.005, 0.003, 10, true, 0.0, 1, metal)
		k.crystal("im:crystal:" + t, Transform3D(Basis.IDENTITY, Vector3(0, 0.0145, 0)), 0.0045, 0.004, 8, 0.6, Color(c.r, c.g, c.b, 0.85))

static func _amulet(k: MeshKit, t: String, c: Color) -> void:
	# A pendant on a cord or chain: the cord hangs in a loop above the pendant.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 25:
		var a := lerpf(-PI * 0.9, PI * 0.9, i / 24.0)
		path.append(Vector3(sin(a) * 0.05, 0.04 + (1.0 - cos(a)) * 0.08, 0.0))
		radii.append(0.0012)
	var cord_m := "im:metal@0.3" if t.contains("silver") or t.contains("saint") else "im:rope"
	_tube(k, cord_m, Transform3D.IDENTITY, path, radii, 4, Color(0.75, 0.75, 0.78) if cord_m != "im:rope" else Color(0.3, 0.22, 0.15), false)
	if t.contains("bone"):
		_tube(k, "im:bone", Transform3D.IDENTITY, PackedVector3Array([Vector3(0, 0.035, 0), Vector3(0.004, 0.01, 0), Vector3(0.012, -0.01, 0)]), PackedFloat32Array([0.005, 0.0045, 0.0008]), 8, c)
	elif t.contains("coin"):
		k.cylinder("im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, -0.0012)), 0.012, 0.012, 0.0024, 20, true, 0.0, 1, Color(0.95, 0.78, 0.4))
	else:
		k.cylinder("im:metal@0.25", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, -0.002)), 0.014, 0.014, 0.004, 20, true, 0.0, 1, c)
		_torus(k, "im:metal@0.25", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.02, 0.0021)), 0.01, 0.0012, 20, 4, c.lightened(0.1))

# --- Materials --------------------------------------------------------------------------

static func mat(name: String) -> Material:
	if not name.begins_with("im:"):
		return Materials.get_mat(name)
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name.substr(3))
		_mats[name] = m
	_lock.unlock()
	return m

static func _base(rough: float, metal: float, tex: String, freq: float, scale: float, nscale := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		var lift := 1.0 / 0.86
		m.albedo_color = Color(lift, lift, lift)
		m.albedo_texture = Materials._noise_tex(tex, freq, false)
		m.normal_enabled = true
		m.normal_texture = Materials._noise_tex(tex, freq, true)
		m.normal_scale = nscale
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func _photo_detail(m: StandardMaterial3D, ph: String, scale: float) -> void:
	var t := Materials.photo(ph, "detail")
	if t == null:
		return
	m.albedo_texture = t
	m.albedo_color = Color(1.0 / 0.72, 1.0 / 0.72, 1.0 / 0.72)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	var n := Materials.photo(ph, "normal")
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n

static func _make(n: String) -> Material:
	if n.begins_with("metal@"):
		# Cast and worked metal: fine hammered/cast unevenness in the normal, a little
		# roughness variation; colour (and so the metal) from the vertices.
		var m := _base(n.substr(6).to_float(), 1.0, "forged", 0.04, 6.0, 0.06)
		m.albedo_color = Color.WHITE
		m.albedo_texture = null
		return m
	if n.begins_with("ore:"):
		var t := n.substr(4)
		var s: Array = SHAPES[t]
		var sm := ShaderMaterial.new()
		sm.shader = load("res://src/world/ore.gdshader")
		var alb := Materials.photo("rock", "albedo")
		if alb == null:
			alb = Materials.photo("rock", "detail")
		sm.set_shader_parameter("stone_tex", alb)
		sm.set_shader_parameter("stone_nrm", Materials.photo("rock", "normal"))
		sm.set_shader_parameter("tri_scale", 5.0)
		sm.set_shader_parameter("ore_col", s[2])
		sm.set_shader_parameter("ore_col2", s[3])
		sm.set_shader_parameter("vein_width", s[4] * 0.6)
		sm.set_shader_parameter("vein_freq", 45.0)
		sm.set_shader_parameter("grain_freq", 420.0)
		sm.set_shader_parameter("ore_metal", s[5])
		return sm
	if n.begins_with("crystal:") or n.begins_with("crystal_glow:"):
		# Clear, hard and glassy: sharp highlights, light through the body.
		var m := _base(0.04, 0.0, "", 0, 1)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.metallic_specular = 1.0
		m.rim_enabled = true
		m.rim = 0.4
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		# Light bends through the body (the background shifts behind it).
		m.refraction_enabled = true
		m.refraction_scale = 0.04
		if n.begins_with("crystal_glow:"):
			var s: Array = SHAPES[n.substr(13)]
			m.emission_enabled = true
			m.emission = s[1]
			m.emission_energy_multiplier = 0.35
		return m
	match n:
		"stone":
			var m := _base(0.88, 0.0, "stone", 0.02, 4.0, 1.2)
			_photo_detail(m, "rock", 3.0)
			return m
		"clay":
			var m := _base(0.45, 0.0, "stone", 0.05, 12.0, 0.5)
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
			return m
		"wax":
			var m := _base(0.5, 0.0, "cap", 0.06, 10.0, 0.3)
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.6
			return m
		"resin":
			var m := _base(0.08, 0.0, "", 0, 1)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			return m
		"charcoal":
			var m := _base(0.7, 0.25, "grain", 0.06, 14.0, 1.2)
			m.uv1_scale = Vector3(40.0, 4.0, 40.0)
			return m
		"salt":
			var m := _base(0.3, 0.0, "stone", 0.05, 20.0, 0.4)
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.8
			return m
		"endgrain":
			return _base(0.85, 0.0, "stone", 0.08, 30.0, 0.8)
		"splitwood":
			var m := _base(0.9, 0.0, "grain", 0.06, 14.0, 1.4)
			m.uv1_scale = Vector3(30.0, 2.0, 30.0)
			return m
		"brick":
			return _base(0.92, 0.0, "stone", 0.05, 14.0, 1.0)
		"peat":
			var m := _base(0.95, 0.0, "grain", 0.08, 18.0, 1.6)
			return m
		"rubber":
			return _base(0.75, 0.0, "cloth", 0.15, 8.0, 0.2)
		"leather_armour":
			# Hardened (boiled) leather: firmer and a little glossier than soft hide.
			var m := _base(0.55, 0.0, "cloth", 0.15, 10.0, 0.7)
			_photo_detail(m, "leather_worn", 6.0)
			return m
		"mail":
			var m := _base(0.4, 0.85, "", 0, 1)
			var t := load("res://assets/textures/chainmail_detail.jpg") as Texture2D
			if t != null:
				m.albedo_texture = t
				m.albedo_color = Color(1.0 / 0.72, 1.0 / 0.72, 1.0 / 0.72)
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 8.0
			return m
		"composite":
			# Painted composite armour plate: satin paint, faint orange-peel texture.
			var m := _base(0.45, 0.15, "stone", 0.08, 14.0, 0.15)
			m.albedo_texture = null
			m.albedo_color = Color.WHITE
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
			return m
		"visor":
			var m := _base(0.04, 0.1, "", 0, 1)
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			return m
		"hide":
			var m := _base(0.8, 0.0, "cloth", 0.15, 10.0, 0.8)
			_photo_detail(m, "leather_worn", 6.0)
			return m
		"flesh":
			# The flesh side of a skin or the suede of leather: pale, soft, napped.
			var m := _base(0.95, 0.0, "cloth", 0.2, 14.0, 0.4)
			_photo_detail(m, "fabric_wool", 10.0)
			return m
		"fur":
			var m := _base(1.0, 0.0, "grain", 0.08, 20.0, 1.6)
			m.uv1_scale = Vector3(60.0, 8.0, 60.0)
			return m
		"antler":
			var m := _base(0.7, 0.0, "grain", 0.08, 18.0, 1.4)
			m.uv1_scale = Vector3(40.0, 4.0, 40.0)
			return m
		"bone":
			# Dry bone: ivory, matte, finely porous, a little light through the thin parts.
			var m := _base(0.75, 0.0, "cap", 0.06, 25.0, 0.5)
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.3
			return m
		"enamel":
			var m := _base(0.25, 0.0, "", 0, 1)
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.4
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			return m
		"rope":
			var m := _base(0.95, 0.0, "grain", 0.08, 30.0, 1.0)
			_photo_detail(m, "fabric_linen", 30.0)
			return m
		"linen":
			var m := _base(0.95, 0.0, "cloth", 0.15, 10.0, 0.6)
			_photo_detail(m, "fabric_linen", 14.0)
			return m
		"wool":
			var m := _base(1.0, 0.0, "cloth", 0.2, 16.0, 0.8)
			_photo_detail(m, "fabric_wool", 20.0)
			return m
		"straw":
			var m := _base(0.7, 0.0, "grain", 0.06, 10.0, 0.6)
			m.uv1_scale = Vector3(60.0, 4.0, 60.0)
			return m
		"bore":
			return _base(0.85, 0.3, "rust", 0.06, 12.0, 0.8)
		"paint":
			return _base(0.55, 0.1, "stone", 0.05, 14.0, 0.3)
		"dial":
			return _base(0.6, 0.0, "", 0, 1)
		"metal_rolled":
			var m := _base(0.38, 0.9, "forged", 0.04, 3.0, 0.04)
			m.albedo_color = Color.WHITE
			m.albedo_texture = null
			m.anisotropy_enabled = true
			m.anisotropy = 0.5
			return m
		"glass", "glass_edge":
			var m := _base(0.02, 0.0, "", 0, 1)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.metallic_specular = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
	return Materials.get_mat("painted")
