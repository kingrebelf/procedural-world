class_name AmmoModels
## Ammunition and fuel as you carry it: a bundle of arrows or bolts tied with cord, a few cartridges or shells, cells and canisters, a quiver.
## Each entry is item -> builder; a builder adds parts to the kit (materials as in
## ItemModels.mat: "im:..." or a world material, or "own:<name>" for one this file's
## static mat(name) makes) and may return the grip point.
## GearModels commits the kit and caches it.
##
## Three families carry most of it: one arrow (shaft, fletching, head type) for every arrow
## and bolt, alone, fanned or tied in a sheaf; one cartridge (case, bullet, colours) for
## every round and shell, stood and laid in little piles as the icons paint them; one
## cell (a steel can with tinted windows) for the power cells. Human things never glow:
## the "lit" strips of sci-fi cells are tinted glass. Only the two alien fuels shine, faintly.

const BUILD := {
	"jet_fuel": "_jet_fuel", "arrow": "_arrow_one", "bolt": "_bolt_one", "rounds": "_rounds",
	"broadhead_arrows": "_broadhead_arrows",
	"bear_trap": "_bear_trap", "tripwire": "_tripwire", "black_powder": "_black_powder",
	"musket_balls": "_musket_balls", "shotgun_shells": "_shotgun_shells", "rifle_cartridges": "_rifle_cartridges",
	"proximity_mine": "_proximity_mine", "rocket": "_rocket", "energy_cell": "_energy_cell",
	"plasma_canister": "_plasma_canister", "gauss_slugs": "_gauss_slugs", "smart_rounds": "_smart_rounds",
	"fuel_canister": "_fuel_canister", "shells_12g": "_shells_12g",
	"arrow_fire": "_arrow_fire", "arrow_barbed": "_arrow_barbed", "arrow_steel": "_arrow_steel",
	"bolt_steel": "_bolt_steel", "bolt_explosive": "_bolt_explosive",
	"rounds_hollow": "_rounds_hollow", "rounds_ap": "_rounds_ap", "rounds_box": "_rounds_box",
	"speed_loader": "_speed_loader", "rifle_clip": "_rifle_clip", "slug_shells": "_slug_shells",
	"power_cell_small": "_power_cell_small", "power_cell_large": "_power_cell_large",
	"power_cell_spent": "_power_cell_spent", "battery_pack_rifle": "_battery_pack_rifle",
	"capacitor_bank": "_capacitor_bank", "charger_dock": "_charger_dock", "lamp_oil": "_lamp_oil",
	"hydrogen_cell": "_hydrogen_cell", "fusion_pellets": "_fusion_pellets", "rocket_fuel": "_rocket_fuel",
	"plasma_fuel": "_plasma_fuel", "void_fuel": "_void_fuel", "star_fuel": "_star_fuel",
}

const BRASS := Color(0.72, 0.53, 0.24)
const COPPER := Color(0.74, 0.4, 0.24)
const STEEL := Color(0.66, 0.67, 0.69)
const GUNMETAL := Color(0.3, 0.31, 0.33)
const IRON := Color(0.33, 0.32, 0.31)
const RUST := Color(0.45, 0.24, 0.12)
const LEAD := Color(0.34, 0.35, 0.38)
const SHAFT := Color(0.56, 0.37, 0.2)
const FEATHER := Color(0.6, 0.56, 0.5)
const ROPE := Color(0.7, 0.58, 0.38)
const OLIVE := Color(0.32, 0.34, 0.26)

const POLISHED := "im:metal@0.28"
const WORKED := "own:grime"
const FORGED := "own:pitted"
const PAINT := "own:grime_paint"

static var _mats: Dictionary = {}
static var _lock := Mutex.new()

## This family's own materials; "pv_*" are Provisions' (glass, cork, clay, burlap).
static func mat(name: String) -> Material:
	if name.begins_with("pv_"):
		return Provisions._mat(name)
	_lock.lock()
	var m: Material = _mats.get(name)
	if m == null:
		m = _make(name)
		_mats[name] = m
	_lock.unlock()
	return m

static func _make(name: String) -> Material:
	match name:
		"feather":
			# Vanes: thin, matte, a fine barbed texture.
			var m := ItemModels._base(0.85, 0.0, "cloth", 0.3, 40.0, 0.4)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"lens":
			# Tinted glass over a cell's charge: glossy colour, no light of its own.
			var m := ItemModels._base(0.28, 0.0, "", 0, 1)
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.2
			return m
		"grime":
			# Worked steel as the icons paint it: scuffed, blotched, never chrome.
			return ItemModels._base(0.42, 0.85, "ammo_grime", 0.05, 2.5, 0.1)
		"pitted":
			# Forged iron: dark, pitted, rough.
			return ItemModels._base(0.66, 0.75, "ammo_pitted", 0.08, 4.0, 0.25)
		"grime_paint":
			# Enamel paint over steel, worn and spotted.
			return ItemModels._base(0.55, 0.1, "ammo_grime", 0.05, 2.5, 0.08)
		"card":
			var m := ItemModels._base(0.95, 0.0, "cloth", 0.25, 18.0, 0.5)
			return m
		"plastic":
			var m := ItemModels._base(0.42, 0.0, "", 0, 1)
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
			return m
		"glow_violet", "glow_sun":
			# Alien charge: a faint light of its own inside the glass.
			var m := ItemModels._base(0.15, 0.0, "", 0, 1)
			m.emission_enabled = true
			m.emission = Color(0.55, 0.2, 0.95) if name == "glow_violet" else Color(1.0, 0.5, 0.08)
			m.emission_energy_multiplier = 0.3 if name == "glow_violet" else 0.5
			return m
	return ItemModels.mat(PAINT)

## Hands Provisions' material buckets (pv_*) to this family's mat(), and returns the grip.
static func _fin(k: MeshKit, grip: Variant = Vector3.ZERO) -> Variant:
	for name: String in k._st.keys():
		if name.begins_with("pv_"):
			k._st["own:" + name] = k._st[name]
			k._st.erase(name)
	return grip

# --- Small helpers -----------------------------------------------------------------------

static func _v2(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(p)
	return out

## A profile with every corner a crease (each inner point doubled): turned metal parts.
static func _crease(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in a.size():
		out.append(a[i])
		if i > 0 and i < a.size() - 1:
			out.append(a[i])
	return out

## A basis turning +Y to `d`.
static func _aim(d: Vector3) -> Basis:
	var y := d.normalized()
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))

## Lying on its side: +Y turned flat, then round by `yaw`.
static func _lay(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5), at)

## A basis whose +Z points out along radial angle `a` (lathe angles: x = cos a, z = sin a).
static func _radial(a: float) -> Basis:
	return Basis(Vector3.UP, PI * 0.5 - a)

## Noisy wear: `base` blotched toward `stain` by `amt`.
static func _worn(base: Color, stain: Color, amt: float, f := 80.0) -> Callable:
	return func(p: Vector3, _a: float, _t: float) -> Color:
		return base.lerp(stain, clampf(Provisions._nz(p, f) * amt * 2.2, 0.0, 1.0))

## A band standing proud round a lathe body of radius `r` at height `y`, `w` tall.
static func _band(k: MeshKit, m: String, xf: Transform3D, r: float, y: float, w: float, col: Color, segs := 32) -> void:
	var o := r + 0.0012
	Provisions.lathe(k, m, xf, _crease([Vector2(r * 0.99, y - w * 0.5), Vector2(o, y - w * 0.4), Vector2(o, y + w * 0.4), Vector2(r * 0.99, y + w * 0.5)]), segs, col)

## `prof` with each span cut in `n` (creases kept), so vertex colours can draw fine bands.
static func _dense(prof: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in prof.size() - 1:
		if prof[i].is_equal_approx(prof[i + 1]):
			out.append(prof[i])
			continue
		for j in n:
			out.append(prof[i].lerp(prof[i + 1], float(j) / n))
	out.append(prof[prof.size() - 1])
	return out

## A wisp of plasma seen through tinted glass: a thin wavering streak up the window at
## lathe angle `a`, radius `r`, from y0 to y1 (lighter glass, still no light of its own).
static func _wisp(k: MeshKit, xf: Transform3D, a: float, r: float, y0: float, y1: float, spread: float, col: Color) -> void:
	for strand in 2:
		var pts := PackedVector3Array()
		var rad := PackedFloat32Array()
		for i in 17:
			var t := i / 16.0
			var aa := a + spread * sin(t * TAU * 1.5 + strand * 2.2) * (0.6 + 0.4 * strand)
			pts.append(Vector3(cos(aa) * r, lerpf(y0, y1, t), sin(aa) * r))
			rad.append(0.0012 + 0.0008 * sin(t * PI))
		Provisions.tube(k, "own:lens", xf, pts, rad, 5, col)

## A flat plate cut to polygon `poly` (in x, y), `thick` deep along z: blades, fins, teeth.
static func _slab(k: MeshKit, m: String, xf: Transform3D, poly: PackedVector2Array, thick: float, col: Color) -> void:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var p := poly
	if area < 0.0:
		p = poly.duplicate()
		p.reverse()
	var h := thick * 0.5
	var tris := Geometry2D.triangulate_polygon(p)
	for i in range(0, tris.size(), 3):
		for s: float in [1.0, -1.0]:
			var n := Vector3(0, 0, s)
			ItemModels._tri(k, m, xf, Vector3(p[tris[i]].x, p[tris[i]].y, h * s), Vector3(p[tris[i + 1]].x, p[tris[i + 1]].y, h * s), Vector3(p[tris[i + 2]].x, p[tris[i + 2]].y, h * s), n, n, n, col)
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		var e := b - a
		ItemModels._quad(k, m, xf, Vector3(a.x, a.y, -h), Vector3(b.x, b.y, -h), Vector3(b.x, b.y, h), Vector3(a.x, a.y, h), Vector3(e.y, -e.x, 0.0), col)

## A few turns of cord round a waist of radius `r` at height `y` (along xf's +Y).
static func _cord(k: MeshKit, xf: Transform3D, r: float, y: float, turns: int, rt := 0.0024, col := ROPE) -> void:
	for i in turns:
		var yy := y + (i - (turns - 1) * 0.5) * rt * 1.9
		ItemModels._torus(k, "im:rope", xf * Transform3D(Basis(Vector3.RIGHT, 0.04 * sin(i * 2.1)), Vector3(0, yy, 0)), r + rt, rt, 18, 5, col.darkened(0.06 * (i % 2)))

# --- Arrows and bolts ----------------------------------------------------------------------

## One arrow along +Y: nock at y = 0, point at y = `L`. A turned wooden shaft with a
## darker nock, three shield-cut vanes at the back and the head (`head`: bodkin, needle,
## broad, barbed, tri, pyramid, fire, explosive) at the front.
static func _arrow(k: MeshKit, xf: Transform3D, L: float, sr: float, head: String, fl: float, fh: float, fcol: Color, fmat := "own:feather", shaft := SHAFT) -> void:
	var hl := ({"bodkin": 0.05, "needle": 0.075, "broad": 0.055, "barbed": 0.06, "tri": 0.06, "pyramid": 0.045, "fire": 0.05, "explosive": 0.05}.get(head, 0.05) as float) * sr / 0.0045
	var top := L - hl
	Provisions.tube(k, "pv_wood", xf, PackedVector3Array([Vector3(0, 0.006, 0), Vector3(0, top * 0.5, 0), Vector3(0, top + 0.004, 0)]), PackedFloat32Array([sr * 0.95, sr, sr * 0.97]), 7, _worn(shaft, shaft.darkened(0.25), 0.4, 60.0))
	# The nock: a darker swelling with the string slot.
	Provisions.lathe(k, "pv_wood", xf, _v2([Vector2(0, 0.0), Vector2(sr * 0.9, 0.0), Vector2(sr * 1.15, 0.004), Vector2(sr * 1.0, 0.009), Vector2(0, 0.009)]), 8, shaft.darkened(0.45))
	# Three vanes, the cock feather turned out.
	for i in 3:
		var a := TAU * i / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		var y0 := 0.014
		var f := func(u: float, v: float) -> Vector3:
			var hh := fh * pow(clampf(1.0 - u, 0.0, 1.0), 0.7) * smoothstep(0.0, 0.12, u)
			var curl := Vector3(-d.z, 0, d.x) * 0.0015 * sin(PI * u) * v
			return d * (sr + v * maxf(hh, 0.0004)) + Vector3(0, y0 + u * fl + v * fh * 0.12, 0) + curl
		ItemModels._sheet(k, fmat, xf, f, 7, 2, 0.0007, fcol, fcol.darkened(0.08))
		# The quill along the shaft.
		Provisions.tube(k, "pv_wood", xf, PackedVector3Array([d * sr + Vector3(0, y0, 0), d * sr + Vector3(0, y0 + fl, 0)]), PackedFloat32Array([0.0008, 0.0006]), 4, fcol.darkened(0.3), false)
	_head(k, xf * Transform3D(Basis.IDENTITY, Vector3(0, top, 0)), head, sr, hl)

## The head of an arrow or bolt, its socket at the origin, point at +Y `hl`.
static func _head(k: MeshKit, xf: Transform3D, head: String, sr: float, hl: float) -> void:
	var steel := Color(0.6, 0.61, 0.63)
	var sock := sr * 1.25
	match head:
		"bodkin", "needle":
			var slim := 1.0 if head == "bodkin" else 0.85
			Provisions.lathe(k, WORKED, xf, Provisions._curve([Vector2(0, -0.004), Vector2(sock, -0.004), Vector2(sock, -0.004), Vector2(sock * 1.05, hl * 0.25), Vector2(sock * 1.25 * slim, hl * 0.45), Vector2(sock * 0.7, hl * 0.8), Vector2(0.0002, hl)], 3), 10, steel)
		"pyramid", "explosive":
			Provisions.lathe(k, WORKED, xf, _crease([Vector2(0, -0.006), Vector2(sock, -0.006), Vector2(sock, hl * 0.22), Vector2(sr * 2.6, hl * 0.42), Vector2(0.0, hl)]), 4, steel)
			if head == "explosive":
				# The blasting charge: a black can bound in brass behind the head.
				var cx := xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.075, 0))
				Provisions.lathe(k, PAINT, cx, _crease([Vector2(0, 0.0), Vector2(sr * 2.2, 0.0), Vector2(sr * 2.4, 0.004), Vector2(sr * 2.4, 0.044), Vector2(sr * 2.2, 0.048), Vector2(0, 0.048)]), 12, Color(0.07, 0.07, 0.08))
				for y: float in [0.004, 0.024, 0.044]:
					Provisions.lathe(k, POLISHED, cx, _crease([Vector2(sr * 2.45, y - 0.003), Vector2(sr * 2.7, y - 0.002), Vector2(sr * 2.7, y + 0.002), Vector2(sr * 2.45, y + 0.003)]), 12, BRASS)
		"fire":
			# A small point, and behind it a wad of pitch-soaked rag bound with wire.
			Provisions.lathe(k, WORKED, xf, Provisions._curve([Vector2(0, hl * 0.6), Vector2(sock, hl * 0.6), Vector2(sock, hl * 0.6), Vector2(sock * 1.2, hl * 0.75), Vector2(0.0002, hl)], 2), 8, steel.darkened(0.2))
			var rag := Color(0.24, 0.19, 0.15)
			Provisions.lathe(k, "im:linen", xf, Provisions._curve([Vector2(0, -0.012), Vector2(sr * 1.2, -0.012), Vector2(sr * 3.0, hl * 0.12), Vector2(sr * 3.4, hl * 0.35), Vector2(sr * 2.4, hl * 0.6), Vector2(sock, hl * 0.66), Vector2(0, hl * 0.66)], 3), 9, _worn(rag, rag.lightened(0.25), 0.6, 300.0),
				func(a: float, t: float, p: Vector3) -> float: return 1.0 + 0.14 * sin(a * 3.0 + t * 9.0) + 0.1 * Provisions._nz(p, 400.0))
			for y: float in [hl * 0.05, hl * 0.4]:
				Provisions.lathe(k, FORGED, xf, _crease([Vector2(sr * 2.4, y - 0.0012), Vector2(sr * 2.9, y), Vector2(sr * 2.4, y + 0.0012)]), 9, GUNMETAL)
		_:
			# Flat blades: a socket, then one blade (broad), a barbed one, or two across (tri).
			Provisions.lathe(k, WORKED, xf, _crease([Vector2(0, -0.006), Vector2(sock, -0.006), Vector2(sock, hl * 0.3), Vector2(sr * 0.6, hl * 0.4), Vector2(0, hl * 0.4)]), 8, steel.darkened(0.15))
			var w := sr * (6.5 if head == "broad" else 7.5)
			var back := hl * (0.12 if head == "broad" else -0.06)
			var half := [Vector2(0, hl), Vector2(w * 0.5, hl * 0.34), Vector2(w * 0.46, back), Vector2(w * 0.16, hl * 0.26), Vector2(sock * 0.8, hl * 0.18)]
			var poly := PackedVector2Array()
			for p: Vector2 in half:
				poly.append(p)
			for i in range(half.size() - 1, 0, -1):
				poly.append(Vector2(-(half[i] as Vector2).x, (half[i] as Vector2).y))
			_slab(k, WORKED, xf, poly, 0.0016, steel)
			if head == "tri":
				_slab(k, WORKED, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), poly, 0.0016, steel.darkened(0.1))

## A sheaf of `n` arrows crossing at a cord tie round y = 0 (an hourglass: each leans
## round the bundle, so both ends splay), heads down at -Y or up.
static func _sheaf(k: MeshKit, r: RandomNumberGenerator, n: int, L: float, sr: float, head: String, heads_down: bool, fl: float, fh: float, fcol: Color, splay: float, tie := true, fmat := "own:feather", shaft := SHAFT) -> Vector3:
	var waist := sr * 1.15 * sqrt(float(n))
	for i in n:
		var rho := waist * sqrt((i + 0.5) / n)
		var a := i * 2.39996 + r.randf() * 0.2
		var p := Vector3(cos(a) * rho, 0, sin(a) * rho)
		var tang := Vector3(-sin(a), 0, cos(a))
		var d := (Vector3.UP + tang * splay * rho / waist + p.normalized() * splay * 0.25).normalized()
		var dir := -d if heads_down else d
		var off := r.randf_range(-0.012, 0.012)
		var xf := Transform3D(_aim(dir) * Basis(Vector3.UP, r.randf() * TAU), p - dir * (L * 0.5 + off))
		_arrow(k, xf, L, sr, head, fl, fh, fcol.darkened(r.randf() * 0.12), fmat, shaft.darkened(r.randf() * 0.2))
	if tie:
		_cord(k, Transform3D.IDENTITY, waist + sr, 0.0, 5, 0.0032)
	return Vector3.ZERO

## Arrow: a single shaft, brown barred fletching, a small barbed steel head.
static func _arrow_one(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_arrow(k, Transform3D(Basis.IDENTITY, Vector3(0, -0.36, 0)), 0.74, 0.0062, "barbed", 0.17, 0.045, Color(0.5, 0.4, 0.32))
	return _fin(k)

## Crossbow bolt: short and stout, a steel kite head, stiff grey vanes.
static func _bolt_one(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_arrow(k, Transform3D(Basis.IDENTITY, Vector3(0, -0.19, 0)), 0.38, 0.0072, "pyramid", 0.075, 0.03, Color(0.55, 0.56, 0.58), WORKED)
	return _fin(k)

## Broadhead arrows: six fanned out flat, heads up, three-bladed hunting points, big pale
## feathers crowded together at the bottom where the shafts meet.
static func _broadhead_arrows(k: MeshKit, r: RandomNumberGenerator, _t: String):
	for i in 6:
		var a := lerpf(0.3, -0.3, i / 5.0)
		var xf := Transform3D(Basis(Vector3.BACK, a), Vector3(lerpf(-0.05, 0.05, i / 5.0), -0.36, 0.008 * (i % 2)))
		_arrow(k, xf, 0.74, 0.0068, "tri", 0.2, 0.045, FEATHER.darkened(r.randf() * 0.1), "own:feather", SHAFT.darkened(0.1))
	return _fin(k, Vector3(0, -0.25, 0))

## Fire arrows: a stubby sheaf, every head wrapped in a dark pitch-soaked rag.
static func _arrow_fire(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _fin(k, _sheaf(k, r, 17, 0.48, 0.0065, "fire", false, 0.1, 0.03, Color(0.3, 0.25, 0.2), 0.42))

## Barbed arrows: a tied sheaf, barbed steel heads down, white fletching up.
static func _arrow_barbed(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _fin(k, _sheaf(k, r, 19, 0.5, 0.0062, "barbed", true, 0.13, 0.034, FEATHER, 0.44))

## Steel arrows: long polished needle points down, a cord tie, grey-white fletching.
static func _arrow_steel(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _fin(k, _sheaf(k, r, 18, 0.5, 0.006, "needle", true, 0.13, 0.032, Color(0.7, 0.68, 0.64), 0.42))

## Steel bolts: short thick bolts, broad pyramid heads down, cream vanes.
static func _bolt_steel(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _fin(k, _sheaf(k, r, 11, 0.42, 0.0078, "pyramid", true, 0.1, 0.032, FEATHER, 0.42))

## Blasting bolts: each bolt carries a brass-banded black charge behind its head.
static func _bolt_explosive(k: MeshKit, r: RandomNumberGenerator, _t: String):
	return _fin(k, _sheaf(k, r, 8, 0.42, 0.0078, "explosive", true, 0.1, 0.032, FEATHER, 0.42, false))

# --- Cartridges and shells -------------------------------------------------------------------

## The kinds of round: [case radius, case length, neck radius (0 = straight), bullet length,
## bullet style, case colour, bullet colour, tip colour].
const ROUNDS := {
	"revolver": [0.0066, 0.03, 0.0, 0.016, "ogive", BRASS, COPPER, COPPER],
	"hollow": [0.007, 0.022, 0.0, 0.011, "hollow", BRASS, COPPER, COPPER],
	"ap": [0.007, 0.022, 0.0, 0.011, "hollow", BRASS, Color(0.38, 0.39, 0.41), Color(0.38, 0.39, 0.41)],
	"rifle": [0.0076, 0.05, 0.0048, 0.022, "spitzer", BRASS, COPPER, LEAD],
	"clip": [0.0072, 0.05, 0.0046, 0.022, "spitzer", BRASS, COPPER, COPPER],
	"gauss": [0.0115, 0.05, 0.0, 0.036, "cone", Color(0.5, 0.51, 0.53), Color(0.55, 0.56, 0.58), Color(0.55, 0.56, 0.58)],
	"smart": [0.0092, 0.042, 0.0062, 0.024, "spitzer", Color(0.52, 0.53, 0.55), Color(0.55, 0.56, 0.58), Color(0.12, 0.35, 0.85)],
}

## One cartridge standing on its base at xf: a drawn case (rim, extractor groove, a
## bottleneck for rifles) and the bullet seated in its mouth.
static func _cart(k: MeshKit, xf: Transform3D, kind: String) -> void:
	var s: Array = ROUNDS[kind]
	var r: float = s[0]
	var h: float = s[1]
	var neck: float = s[2]
	var bl: float = s[3]
	var case_col: Color = s[5]
	var prof := [Vector2(0, 0), Vector2(r * 1.02, 0), Vector2(r * 1.02, 0.0016), Vector2(r * 0.84, 0.0022), Vector2(r * 0.84, 0.0034), Vector2(r, 0.0042)]
	var rb := r * 0.93
	if neck > 0.0:
		prof.append_array([Vector2(r * 0.97, h * 0.74), Vector2(neck, h * 0.84), Vector2(neck, h), Vector2(neck * 0.9, h)])
		rb = neck * 0.92
	else:
		prof.append_array([Vector2(r, h), Vector2(r * 0.92, h)])
	var cm := "im:metal@0.5" if kind in ["gauss", "smart"] else POLISHED
	Provisions.lathe(k, cm, xf, _crease(prof), 16, _worn(case_col, case_col.darkened(0.3), 0.25, 300.0))
	if kind == "gauss":
		# Copper drive bands round the slug's sabot.
		for y: float in [h * 0.62, h * 0.82]:
			Provisions.lathe(k, POLISHED, xf, _crease([Vector2(r * 1.0, y - 0.003), Vector2(r * 1.04, y - 0.0025), Vector2(r * 1.04, y + 0.0025), Vector2(r * 1.0, y + 0.003)]), 16, COPPER)
	if kind == "smart":
		Provisions.lathe(k, POLISHED, xf, _crease([Vector2(r * 0.98, h * 0.6), Vector2(r * 1.02, h * 0.61), Vector2(r * 1.02, h * 0.7), Vector2(r * 0.98, h * 0.71)]), 16, COPPER)
	_bullet(k, xf * Transform3D(Basis.IDENTITY, Vector3(0, h - 0.003, 0)), rb, bl + 0.003, s[4], s[6], s[7])

## A bullet from its base (at the origin) to its nose `l` up: round-nosed (ogive), hollow
## point (a pit in a flat nose), pointed (spitzer) or a long cone; `tip` colours the nose.
static func _bullet(k: MeshKit, xf: Transform3D, rb: float, l: float, style: String, col: Color, tip: Color) -> void:
	var pts: Array
	match style:
		"hollow":
			pts = [Vector2(0, 0), Vector2(rb, 0), Vector2(rb, 0), Vector2(rb, l * 0.3), Vector2(rb * 0.86, l * 0.7), Vector2(rb * 0.56, l), Vector2(rb * 0.56, l), Vector2(rb * 0.34, l - 0.0006), Vector2(rb * 0.34, l - 0.0006), Vector2(rb * 0.28, l - 0.0035), Vector2(0, l - 0.0035)]
		"spitzer":
			pts = [Vector2(0, 0), Vector2(rb, 0), Vector2(rb, 0), Vector2(rb, l * 0.3), Vector2(rb * 0.78, l * 0.64), Vector2(rb * 0.38, l * 0.9), Vector2(0.0003, l)]
		"cone":
			pts = [Vector2(0, 0), Vector2(rb, 0), Vector2(rb, 0), Vector2(rb, l * 0.25), Vector2(rb, l * 0.25), Vector2(rb * 0.55, l * 0.72), Vector2(rb * 0.2, l * 0.95), Vector2(0, l)]
		_:
			pts = [Vector2(0, 0), Vector2(rb, 0), Vector2(rb, 0), Vector2(rb, l * 0.36), Vector2(rb * 0.88, l * 0.64), Vector2(rb * 0.58, l * 0.88), Vector2(rb * 0.2, l * 0.995), Vector2(0, l)]
	var m := "im:metal@0.35"
	Provisions.lathe(k, m, xf, Provisions._curve(pts, 3), 16, func(p: Vector3, _a: float, _t: float) -> Color:
		if style == "hollow" and p.y > l - 0.0034 and Vector2(p.x, p.z).length() < rb * 0.36:
			return Color(0.08, 0.06, 0.05)
		return tip if p.y > l * 0.5 else col)

## A shotgun shell standing at xf: a tall brass head with its rim, a ribbed paper/plastic
## hull in `hull`, the crimp folded into a star on top.
static func _shell(k: MeshKit, xf: Transform3D, hull: Color, head_h := 0.016, r := 0.0105, h := 0.066) -> void:
	Provisions.lathe(k, POLISHED, xf, _crease([Vector2(0, 0), Vector2(r * 1.07, 0), Vector2(r * 1.07, 0.0019), Vector2(r * 1.0, 0.0024), Vector2(r * 1.0, head_h), Vector2(r * 0.97, head_h)]), 20, _worn(BRASS, BRASS.darkened(0.35), 0.3, 250.0))
	var ribbed := func(a: float, _t: float, _p: Vector3) -> float: return 1.0 - 0.012 * pow(absf(cos(a * 9.0)), 6.0)
	Provisions.lathe(k, "im:paint", xf, _crease([Vector2(r * 0.985, head_h - 0.001), Vector2(r * 0.985, h - 0.0025), Vector2(r * 0.93, h), Vector2(r * 0.55, h - 0.0016), Vector2(0, h - 0.0026)]), 24, _worn(hull, hull.darkened(0.3), 0.3, 200.0), ribbed)
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		k.box("im:paint", xf * Transform3D(Basis(Vector3.UP, -a), Vector3(0, h - 0.0018, 0) + d * r * 0.45), Vector3(r * 0.8, 0.0007, 0.0007), hull.darkened(0.55))

# --- Ammunition items --------------------------------------------------------------------------

## Revolver rounds: nine stood in a cluster, one laid in front; brass cases, copper noses.
static func _rounds(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var spots := [Vector2(-0.015, -0.013), Vector2(0.0, -0.018), Vector2(0.015, -0.012), Vector2(-0.019, 0.002), Vector2(-0.004, 0.0), Vector2(0.012, 0.002), Vector2(-0.01, 0.015), Vector2(0.005, 0.016), Vector2(0.02, 0.013)]
	for p: Vector2 in spots:
		_cart(k, Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(p.x, 0, p.y)), "revolver")
	_cart(k, _lay(Vector3(-0.006, 0.0068, 0.032), -0.35), "revolver")
	return _fin(k)

## Rifle cartridges: two stood up, one laid in front; bottlenecked brass, grey-tipped bullets.
static func _rifle_cartridges(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_cart(k, Transform3D(Basis.IDENTITY, Vector3(-0.01, 0, -0.012)), "rifle")
	_cart(k, Transform3D(Basis.IDENTITY, Vector3(0.01, 0, -0.016)), "rifle")
	_cart(k, _lay(Vector3(-0.03, 0.0078, 0.01), -0.2), "rifle")
	return _fin(k)

## Hollow points: one stood up, four tumbled on their sides, copper noses with the pit.
static func _rounds_hollow(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var y := 0.0072
	_cart(k, Transform3D(Basis.IDENTITY, Vector3(0.02, 0, -0.012)), "hollow")
	_cart(k, _lay(Vector3(-0.024, y, 0.008), -1.3), "hollow")
	_cart(k, _lay(Vector3(-0.006, y, 0.02), 2.7), "hollow")
	_cart(k, _lay(Vector3(-0.012, y, -0.006), 2.75), "hollow")
	_cart(k, _lay(Vector3(-0.002, y * 2.6, -0.014), 2.85), "hollow")
	return _fin(k)

## Steel-core rounds: dark steel hollow-point noses in brass, two up and four down.
static func _rounds_ap(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var y := 0.0072
	_cart(k, Transform3D(Basis.IDENTITY, Vector3(-0.004, 0, -0.006)), "ap")
	_cart(k, Transform3D(Basis.IDENTITY, Vector3(0.018, 0, -0.016)), "ap")
	_cart(k, _lay(Vector3(-0.03, y, 0.004), -1.1), "ap")
	_cart(k, _lay(Vector3(-0.014, y, -0.02), 0.1), "ap")
	_cart(k, _lay(Vector3(0.012, y, 0.022), 2.5), "ap")
	_cart(k, _lay(Vector3(-0.016, y, 0.024), 1.9), "ap")
	return _fin(k)

## Gauss slugs: big grey steel slugs with copper drive bands, four up, two laid down.
static func _gauss_slugs(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	for i in 4:
		_cart(k, Transform3D(Basis.IDENTITY, Vector3(-0.036 + i * 0.024, 0, -0.014 + 0.005 * (i % 2))), "gauss")
	_cart(k, _lay(Vector3(-0.05, 0.0118, 0.014), -0.12), "gauss")
	_cart(k, _lay(Vector3(-0.04, 0.0118, 0.038), -0.18), "gauss")
	return _fin(k)

## Smart rounds: grey cases with a copper band, the guided bullets painted blue at the tip.
static func _smart_rounds(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	for i in 4:
		_cart(k, Transform3D(Basis.IDENTITY, Vector3(-0.03 + i * 0.02, 0, -0.014 - 0.004 * (i % 2))), "smart")
	_cart(k, _lay(Vector3(0.036, 0.0094, 0.016), PI - 0.2), "smart")
	return _fin(k)

## Shotgun shells: two dark red hulls stood up, one laid in front, deep brass heads.
static func _shotgun_shells(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var red := Color(0.34, 0.08, 0.05)
	_shell(k, Transform3D(Basis.IDENTITY, Vector3(-0.013, 0, -0.014)), red, 0.03)
	_shell(k, Transform3D(Basis.IDENTITY, Vector3(0.011, 0, -0.018)), red, 0.03)
	_shell(k, _lay(Vector3(-0.012, 0.0112, 0.014), 2.9), red, 0.03)
	return _fin(k)

## 12-gauge shells: six red hulls stood in a block, one laid down showing its crimp.
static func _shells_12g(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var red := Color(0.52, 0.07, 0.07)
	for i in 6:
		_shell(k, Transform3D(Basis.IDENTITY, Vector3(-0.022 + (i % 3) * 0.022, 0, -0.02 + (i / 3) * 0.022)), red, 0.016)
	_shell(k, _lay(Vector3(0.012, 0.0112, 0.034), PI + 0.5), red, 0.016)
	return _fin(k)

## Slug shells: green hulls, three stood up and one laid across them.
static func _slug_shells(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var green := Color(0.07, 0.24, 0.13)
	_shell(k, Transform3D(Basis.IDENTITY, Vector3(-0.023, 0, -0.004)), green, 0.022)
	_shell(k, Transform3D(Basis.IDENTITY, Vector3(0.0, 0, -0.02)), green, 0.022)
	_shell(k, Transform3D(Basis.IDENTITY, Vector3(0.023, 0, -0.008)), green, 0.022)
	_shell(k, _lay(Vector3(-0.002, 0.0112, 0.016), PI + 0.7), green, 0.022)
	return _fin(k)

## Musket balls: a heap of cast lead balls, dull grey with a soft sheen.
static func _musket_balls(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var rr := 0.0085
	var spots := [Vector3(-0.026, 0, -0.006), Vector3(-0.009, 0, -0.016), Vector3(0.009, 0, -0.018), Vector3(0.027, 0, -0.01),
		Vector3(-0.022, 0, 0.012), Vector3(-0.004, 0, 0.004), Vector3(0.015, 0, 0.002), Vector3(0.03, 0, 0.012), Vector3(-0.008, 0, 0.022), Vector3(0.011, 0, 0.02),
		Vector3(-0.012, 0.014, -0.006), Vector3(0.006, 0.014, -0.008), Vector3(0.0, 0.013, 0.01)]
	for p: Vector3 in spots:
		k.sphere(FORGED, Transform3D(Basis.IDENTITY, p + Vector3(0, rr, 0)), rr, 10, 14, 0.015, 1.0, Color(0.3, 0.3, 0.32).darkened(r.randf() * 0.15))
	return _fin(k)

## Box of rounds: an open brown cardboard box, flaps folded out, copper noses packed in rows.
static func _rounds_box(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.085
	var d := 0.066
	var h := 0.058
	var card := Color(0.46, 0.33, 0.2)
	var th := 0.0018
	k.box("own:card", Transform3D(Basis.IDENTITY, Vector3(0, th * 0.5, 0)), Vector3(w, th, d), card.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		k.box("own:card", Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, s * (d - th) * 0.5)), Vector3(w, h, th), card)
		k.box("own:card", Transform3D(Basis.IDENTITY, Vector3(s * (w - th) * 0.5, h * 0.5, 0)), Vector3(th, h, d), card.darkened(0.05))
	# The flaps: the back one stands up, the others fold out and down.
	k.box("own:card", Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, h + d * 0.48, -d * 0.5 - 0.004)), Vector3(w, d * 0.95, th), card.lightened(0.04))
	k.box("own:card", Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0, h + 0.012, d * 0.5 + 0.018)), Vector3(w, 0.045, th), card.darkened(0.08))
	for s: float in [-1.0, 1.0]:
		k.box("own:card", Transform3D(Basis(Vector3.BACK, -s * 0.75), Vector3(s * (w * 0.5 + 0.015), h + 0.014, 0)), Vector3(th, 0.042, d * 0.95), card.darkened(0.02))
	# A floor of shadow inside, then the rounds nose up in rows.
	k.box("own:card", Transform3D(Basis.IDENTITY, Vector3(0, h - 0.016, 0)), Vector3(w - 0.004, 0.002, d - 0.004), Color(0.2, 0.15, 0.1))
	for ix in 5:
		for iz in 4:
			var at := Vector3(-0.032 + ix * 0.016, h - 0.026, -0.024 + iz * 0.016)
			_bullet(k, Transform3D(Basis.IDENTITY, at), 0.0066, 0.022, "hollow", COPPER, COPPER)
	return _fin(k)

## Speed loader: a black six-round cylinder with a knurled steel knob on top, the rounds
## hanging beneath it bullets down.
static func _speed_loader(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.0155
	Provisions.lathe(k, "own:plastic", Transform3D.IDENTITY, _crease([Vector2(0, 0.0), Vector2(0.0245, 0.0), Vector2(0.0255, 0.002), Vector2(0.0255, 0.018), Vector2(0.0235, 0.02), Vector2(0, 0.02)]), 36, Color(0.06, 0.06, 0.07),
		func(a: float, _t2: float, _p: Vector3) -> float: return 1.0 - 0.12 * pow(maxf(0.0, cos(a * 6.0 + PI / 6.0)), 18.0))
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0, 0.018), Vector2(0.006, 0.018), Vector2(0.006, 0.024), Vector2(0.008, 0.026), Vector2(0.008, 0.03), Vector2(0.0045, 0.031), Vector2(0.0045, 0.034)]), 16, GUNMETAL)
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0.0045, 0.034), Vector2(0.0155, 0.034), Vector2(0.0165, 0.036), Vector2(0.0165, 0.042), Vector2(0.015, 0.044), Vector2(0, 0.044)]), 48, Color(0.36, 0.37, 0.39),
		func(a: float, t: float, _p: Vector3) -> float: return 1.0 - 0.04 * absf(sin(a * 30.0)) * float(t > 0.2 and t < 0.7))
	for i in 6:
		var a := TAU * i / 6.0
		var at := Vector3(cos(a) * R, 0.004, sin(a) * R)
		_cart(k, Transform3D(Basis(Vector3.RIGHT, PI), at), "revolver")
	return _fin(k, Vector3(0, 0.03, 0))

## Stripper clip: five rifle cartridges stood in a pressed-steel strip.
static func _rifle_clip(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var steel := Color(0.42, 0.43, 0.45)
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.0008, 0)), Vector3(0.068, 0.0016, 0.016), steel)
	for s: float in [-1.0, 1.0]:
		k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.003, s * 0.0075)), Vector3(0.068, 0.006, 0.0012), steel)
		k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.0058, s * 0.0058)), Vector3(0.068, 0.0012, 0.004), steel)
	for i in 5:
		_cart(k, Transform3D(Basis.IDENTITY, Vector3(-0.026 + i * 0.013, 0.0016, 0)), "clip")
	return _fin(k)

# --- Cells and canisters ----------------------------------------------------------------------

## The angle (in lathe terms) the icons are painted from: front, turned a little right.
const VIEW := PI * 0.5 - 0.42

## A cylindrical power cell standing on y = 0: a scuffed steel can with collars top and
## bottom, a socket in the top, two tall windows of tinted glass (`strip`) either side of
## the front. `large` adds brass bands and steel ribs over a dark body.
static func _cell(k: MeshKit, xf: Transform3D, r: float, h: float, body: Color, strip: Color, large := false, rust := 0.35) -> void:
	var c := r * 0.08
	Provisions.lathe(k, WORKED, xf, _crease([Vector2(0, 0), Vector2(r * 0.94, 0), Vector2(r * 1.04, c), Vector2(r * 1.04, h * 0.12), Vector2(r, h * 0.13), Vector2(r, h * 0.87), Vector2(r * 1.04, h * 0.88), Vector2(r * 1.04, h - c), Vector2(r * 0.9, h), Vector2(r * 0.55, h), Vector2(r * 0.5, h - c), Vector2(r * 0.5, h - r * 0.4), Vector2(0, h - r * 0.4)]), 32,
		func(p: Vector3, _a: float, _t: float) -> Color:
			var base := body.darkened(0.25) if p.y < h * 0.125 or p.y > h * 0.875 else body
			return base.lerp(RUST, clampf((Provisions._nz(p, 90.0) - 0.25) * rust * 4.0, 0.0, 0.8)))
	if large:
		for y: float in [h * 0.1, h * 0.5, h * 0.9]:
			var bw := h * 0.05
			Provisions.lathe(k, POLISHED, xf, _crease([Vector2(r * 1.04, y - bw), Vector2(r * 1.08, y - bw * 0.8), Vector2(r * 1.08, y + bw * 0.8), Vector2(r * 1.04, y + bw)]), 32, _worn(BRASS, BRASS.darkened(0.4), 0.3, 120.0))
		for i in 4:
			var a := VIEW + PI * 0.25 + PI * 0.5 * i
			k.box(WORKED, xf * Transform3D(_radial(a), Vector3(cos(a), 0, sin(a)) * (r + 0.002) + Vector3(0, h * 0.5, 0)), Vector3(r * 0.22, h * 0.84, 0.004), STEEL.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		var a := VIEW + s * 0.8
		var n := Vector3(cos(a), 0, sin(a))
		# A dark recessed frame, the tinted strip inside it.
		k.box(WORKED, xf * Transform3D(_radial(a), n * (r - 0.0005) + Vector3(0, h * 0.5, 0)), Vector3(r * 0.32, h * 0.56, 0.003), GUNMETAL.darkened(0.4))
		k.box("own:lens", xf * Transform3D(_radial(a), n * (r + 0.0008) + Vector3(0, h * 0.5, 0)), Vector3(r * 0.16, h * 0.48, 0.0025), strip)

## Small power cell: a scuffed steel can with two pale tinted windows.
static func _power_cell_small(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_cell(k, Transform3D.IDENTITY, 0.03, 0.104, Color(0.62, 0.62, 0.63), Color(0.78, 0.86, 0.92))
	return _fin(k)

## Heavy power cell: dark steel, banded in brass, ribbed, tinted windows.
static func _power_cell_large(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_cell(k, Transform3D.IDENTITY, 0.038, 0.11, Color(0.36, 0.37, 0.39), Color(0.8, 0.86, 0.92), true, 0.25)
	return _fin(k)

## Spent power cell: the same can, rustier, its windows gone dark.
static func _power_cell_spent(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	_cell(k, Transform3D.IDENTITY, 0.03, 0.104, Color(0.6, 0.59, 0.58), Color(0.16, 0.17, 0.19), false, 0.7)
	return _fin(k)

## Cell charger: a squat steel cradle with a cell stood upright in its well.
static func _charger_dock(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var g := Color(0.34, 0.35, 0.37)
	ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.008, 0)), Vector3(0.13, 0.016, 0.11), 0.004, g.darkened(0.15))
	for s: float in [-1.0, 1.0]:
		# Sloped cheeks either side, the well between.
		var poly := _v2([Vector2(-0.055, 0), Vector2(0.055, 0), Vector2(0.03, 0.04), Vector2(-0.03, 0.04)])
		_slab(k, WORKED, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s * 0.05, 0.016, 0)), poly, 0.024, g)
	ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.028, -0.04)), Vector3(0.08, 0.024, 0.02), 0.003, g.darkened(0.05))
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0, 0.016), Vector2(0.026, 0.016), Vector2(0.026, 0.03), Vector2(0.022, 0.032), Vector2(0, 0.032)]), 24, GUNMETAL)
	k.box(POLISHED, Transform3D(Basis.IDENTITY, Vector3(0.042, 0.03, 0.045)), Vector3(0.012, 0.01, 0.004), BRASS)
	_cell(k, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), 0.017, 0.1, Color(0.55, 0.56, 0.58), Color(0.42, 0.6, 0.95))
	return _fin(k)

## Energy cell: a squared pack in a steel frame with corner brackets and orange bands,
## a blue-tinted glass front showing the charge tubes inside.
static func _energy_cell(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.07
	var h := 0.1
	var d := 0.045
	k.box("own:lens", Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w * 0.9, h * 0.8, d * 0.9), Color(0.03, 0.12, 0.3))
	# Charge tubes of tinted glass standing in rows behind the front and side faces.
	for i in 3:
		Provisions.lathe(k, "own:lens", Transform3D(Basis.IDENTITY, Vector3(-0.021 + i * 0.021, h * 0.1, d * 0.45 - 0.008)), _v2([Vector2(0, 0), Vector2(0.0095, 0), Vector2(0.0095, h * 0.8), Vector2(0, h * 0.8)]), 14, Color(0.2, 0.55, 0.95))
	for i in 2:
		Provisions.lathe(k, "own:lens", Transform3D(Basis.IDENTITY, Vector3(w * 0.45 - 0.008, h * 0.1, -0.009 + i * 0.016)), _v2([Vector2(0, 0), Vector2(0.0085, 0), Vector2(0.0085, h * 0.8), Vector2(0, h * 0.8)]), 14, Color(0.16, 0.48, 0.9))
	var frame := Color(0.48, 0.49, 0.5)
	for y: float in [0.006, h - 0.006]:
		ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), Vector3(w, 0.012, d), 0.002, frame.darkened(0.1))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.003), h * 0.5, sz * (d * 0.5 - 0.003))), Vector3(0.008, h, 0.008), frame)
			for y: float in [0.018, h - 0.018]:
				k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.002), y, sz * (d * 0.5 - 0.002))), Vector3(0.013, 0.014, 0.013), frame.lightened(0.1))
		for y: float in [0.016, h - 0.016]:
			k.box(PAINT, Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, y, 0)), Vector3(0.003, 0.008, d * 0.6), Color(0.85, 0.48, 0.12))
	for y: float in [0.016, h - 0.016]:
		k.box(PAINT, Transform3D(Basis.IDENTITY, Vector3(0, y, d * 0.5)), Vector3(w * 0.6, 0.008, 0.003), Color(0.85, 0.48, 0.12))
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, h + 0.002, 0)), Vector3(0.024, 0.004, 0.012), Color(0.45, 0.46, 0.48))
	return _fin(k)

## Plasma canister: a rounded steel can with a socket ring on top, bolted lugs either side
## and a window of violet-tinted glass in the front; an orange tag above it.
static func _plasma_canister(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var r := 0.045
	var h := 0.12
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, Provisions._curve([Vector2(0, 0), Vector2(r * 0.85, 0), Vector2(r * 0.85, 0), Vector2(r, h * 0.1), Vector2(r, h * 0.85), Vector2(r * 0.8, h * 0.95), Vector2(r * 0.5, h), Vector2(r * 0.5, h), Vector2(0, h)], 3), 32, _worn(Color(0.55, 0.55, 0.57), RUST, 0.25, 70.0))
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(r * 0.3, h + 0.012), Vector2(r * 0.55, h + 0.012), Vector2(r * 0.55, h - 0.002)]), 24, GUNMETAL)
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _v2([Vector2(r * 0.3, h + 0.012), Vector2(r * 0.3, h + 0.002), Vector2(0, h + 0.002)]), 24, Color(0.08, 0.08, 0.09))
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(r * 1.03, h * 0.28), Vector2(r * 1.03, h * 0.78)]), 32, GUNMETAL.darkened(0.3), null, Vector2((VIEW - 0.75) / TAU, (VIEW + 0.75) / TAU))
	Provisions.lathe(k, "own:lens", Transform3D.IDENTITY, _crease([Vector2(r * 1.045, h * 0.31), Vector2(r * 1.045, h * 0.75)]), 24, Color(0.24, 0.1, 0.48), null, Vector2((VIEW - 0.6) / TAU, (VIEW + 0.6) / TAU))
	_wisp(k, Transform3D.IDENTITY, VIEW, r * 1.05, h * 0.34, h * 0.72, 0.25, Color(0.58, 0.4, 0.88))
	for s: float in [-1.0, 1.0]:
		var a := VIEW + s * 1.45
		var n := Vector3(cos(a), 0, sin(a))
		for y: float in [h * 0.2, h * 0.82]:
			ItemModels._block(k, WORKED, Transform3D(_radial(a), n * (r + 0.004) + Vector3(0, y, 0)), Vector3(0.016, 0.018, 0.01), 0.002, GUNMETAL)
			Provisions.lathe(k, WORKED, Transform3D(_radial(a) * Basis(Vector3.RIGHT, PI * 0.5), n * (r + 0.009) + Vector3(0, y, 0)), _crease([Vector2(0.004, 0), Vector2(0.004, 0.002), Vector2(0, 0.002)]), 8, STEEL)
		k.box(WORKED, Transform3D(_radial(a), n * (r + 0.005) + Vector3(0, h * 0.5, 0)), Vector3(0.006, h * 0.6, 0.006), GUNMETAL.darkened(0.2))
	var ta := VIEW - 0.35
	k.box(PAINT, Transform3D(_radial(ta), Vector3(cos(ta), 0, sin(ta)) * (r + 0.001) + Vector3(0, h * 0.86, 0)), Vector3(0.012, 0.006, 0.002), Color(0.88, 0.45, 0.12))
	return _fin(k)

## Rifle battery: a slab of dark ribbed steel like a magazine, brass contacts along the top.
static func _battery_pack_rifle(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.075
	var h := 0.12
	var d := 0.03
	var g := Color(0.38, 0.39, 0.36)
	ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), 0.003, g)
	# Pressed panels and ribs on the face, a grip block on the left.
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 - 0.003, h * 0.48, 0)), Vector3(0.008, h * 0.42, d * 1.1), g.lightened(0.08))
	for i in 3:
		k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(-0.012 + i * 0.014, h * 0.5, d * 0.5 + 0.0015)), Vector3(0.004, h * 0.86, 0.003), g.lightened(0.06))
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0.028, h * 0.45, d * 0.5 + 0.0015)), Vector3(0.012, h * 0.3, 0.003), g.darkened(0.25))
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.004, 0)), Vector3(w + 0.004, 0.008, d + 0.004), g.darkened(0.2))
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, h - 0.002, 0)), Vector3(w * 0.8, 0.006, d * 0.7), Color(0.12, 0.12, 0.12))
	for i in 4:
		k.box(POLISHED, Transform3D(Basis.IDENTITY, Vector3(-0.02 + i * 0.013, h + 0.002, 0)), Vector3(0.008, 0.004, d * 0.5), BRASS)
	return _fin(k)

## Capacitor bank: three big capacitors (one brass, two steel) clamped in a dark frame,
## brass manifolds across the top, red and black cables looping round the side.
static func _capacitor_bank(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var frame := Color(0.12, 0.12, 0.13)
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.006, 0)), Vector3(0.15, 0.012, 0.05), frame)
	for x: float in [-0.072, 0.072]:
		k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(x, 0.065, -0.018)), Vector3(0.008, 0.12, 0.012), frame)
	k.box(WORKED, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -0.02)), Vector3(0.14, 0.07, 0.004), Color(0.2, 0.16, 0.12))
	for i in 3:
		var x := -0.04 + i * 0.035
		var col := BRASS if i == 0 else Color(0.6, 0.6, 0.61)
		Provisions.lathe(k, POLISHED if i == 0 else WORKED, Transform3D(Basis.IDENTITY, Vector3(x, 0.012, 0)), _crease([Vector2(0, 0), Vector2(0.015, 0), Vector2(0.015, 0.09), Vector2(0.012, 0.094), Vector2(0, 0.094)]), 20, _worn(col, RUST, 0.2, 90.0))
		for y: float in [0.02, 0.09]:
			Provisions.lathe(k, POLISHED, Transform3D(Basis.IDENTITY, Vector3(x, y, 0)), _crease([Vector2(0.0158, -0.005), Vector2(0.0165, -0.004), Vector2(0.0165, 0.004), Vector2(0.0158, 0.005)]), 20, BRASS)
		Provisions.lathe(k, POLISHED, Transform3D(Basis.IDENTITY, Vector3(x, 0.106, 0)), _crease([Vector2(0, 0), Vector2(0.006, 0), Vector2(0.006, 0.012), Vector2(0, 0.012)]), 12, BRASS)
	Provisions.tube(k, POLISHED, Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.065, 0.12, 0), Vector3(0.065, 0.12, 0)]), PackedFloat32Array([0.006, 0.006]), 12, BRASS)
	for x: float in [-0.065, 0.065]:
		ItemModels._block(k, POLISHED, Transform3D(Basis.IDENTITY, Vector3(x, 0.12, 0)), Vector3(0.016, 0.016, 0.016), 0.002, BRASS.darkened(0.1))
		ItemModels._block(k, POLISHED, Transform3D(Basis.IDENTITY, Vector3(x, 0.06, 0.004)), Vector3(0.016, 0.03, 0.02), 0.002, BRASS.darkened(0.15))
	# Cables: two red, three black, looping out round the left side.
	for i in 5:
		var red := i < 2
		var zo := -0.012 + i * 0.006
		var path := PackedVector3Array([Vector3(-0.06, 0.12, zo), Vector3(-0.08 - i * 0.003, 0.11, zo), Vector3(-0.088 - i * 0.003, 0.07, zo), Vector3(-0.082 - i * 0.003, 0.02, zo), Vector3(-0.06, 0.012, zo)])
		var smooth := PackedVector3Array()
		for j in path.size() - 1:
			for s in 4:
				smooth.append(path[j].lerp(path[j + 1], s / 4.0) + Vector3(-0.006 * sin(PI * (j * 4 + s) / 16.0), 0, 0))
		smooth.append(path[path.size() - 1])
		var rad := PackedFloat32Array()
		rad.resize(smooth.size())
		rad.fill(0.0035)
		Provisions.tube(k, "im:rubber", Transform3D.IDENTITY, smooth, rad, 7, Color(0.6, 0.08, 0.06) if red else Color(0.06, 0.06, 0.06))
	return _fin(k)

## Hydrogen cell: a white pressure capsule with bronze bands, a brass valve wheel on the neck
## and a brass nozzle at the base.
static func _hydrogen_cell(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var r := 0.042
	var L := 0.22
	Provisions.lathe(k, PAINT, Transform3D.IDENTITY, Provisions._curve([Vector2(0, -L * 0.5), Vector2(r * 0.6, -L * 0.48), Vector2(r * 0.95, -L * 0.4), Vector2(r, -L * 0.3), Vector2(r, L * 0.28), Vector2(r * 0.9, L * 0.4), Vector2(r * 0.4, L * 0.5), Vector2(0, L * 0.5)], 4), 32, _worn(Color(0.72, 0.72, 0.7), Color(0.5, 0.36, 0.22), 0.45, 60.0))
	for y: float in [-L * 0.24, L * 0.22]:
		Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(r * 1.0, y - 0.006), Vector2(r * 1.04, y - 0.005), Vector2(r * 1.04, y + 0.005), Vector2(r * 1.0, y + 0.006)]), 32, Color(0.5, 0.36, 0.22))
	Provisions.lathe(k, POLISHED, Transform3D.IDENTITY, _crease([Vector2(0, L * 0.49), Vector2(0.01, L * 0.49), Vector2(0.01, L * 0.5 + 0.01), Vector2(0.006, L * 0.5 + 0.012), Vector2(0.006, L * 0.5 + 0.024), Vector2(0, L * 0.5 + 0.024)]), 14, BRASS)
	Provisions.lathe(k, POLISHED, Transform3D(Basis.IDENTITY, Vector3(0, L * 0.5 + 0.024, 0)), _crease([Vector2(0, 0), Vector2(0.016, 0), Vector2(0.016, 0.009), Vector2(0, 0.009)]), 24, BRASS,
		func(a: float, _t: float, _p: Vector3) -> float: return 1.0 - 0.1 * pow(absf(cos(a * 6.0)), 8.0))
	Provisions.lathe(k, POLISHED, Transform3D.IDENTITY, _crease([Vector2(0, -L * 0.49), Vector2(0.011, -L * 0.49), Vector2(0.011, -L * 0.5 - 0.012), Vector2(0.006, -L * 0.5 - 0.012), Vector2(0.006, -L * 0.5 - 0.008), Vector2(0, -L * 0.5 - 0.008)]), 14, BRASS)
	return _fin(k)

## Fusion pellets: a glass tube packed with steel pellets, banded steel-and-brass end caps.
static func _fusion_pellets(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var R := 0.026
	var L := 0.2
	Provisions.lathe(k, "pv_glass", Transform3D.IDENTITY, _v2([Vector2(R, -L * 0.4), Vector2(R, L * 0.4)]), 28, Color(0.85, 0.92, 0.95, 0.12))
	var n := 0
	var y := -L * 0.39
	while y < L * 0.38:
		for i in 5:
			var a := i * TAU / 5.0 + n * 0.6
			var p := Vector3(cos(a) * R * 0.6, y, sin(a) * R * 0.6)
			k.sphere("im:metal@0.4", Transform3D(Basis.IDENTITY, p), 0.0072, 6, 8, 0.0, 1.0, Color(0.42, 0.43, 0.45).darkened(r.randf() * 0.2))
		k.sphere("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, y + 0.004, 0)), 0.0072, 6, 8, 0.0, 1.0, Color(0.38, 0.39, 0.41))
		y += 0.0105
		n += 1
	for s: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis(Vector3.RIGHT, 0.0 if s > 0.0 else PI), Vector3(0, s * L * 0.38, 0))
		Provisions.lathe(k, WORKED, xf, _crease([Vector2(R * 0.9, 0), Vector2(R * 1.15, 0), Vector2(R * 1.15, L * 0.11), Vector2(R * 1.05, L * 0.12), Vector2(R * 0.5, L * 0.12), Vector2(R * 0.5, L * 0.115), Vector2(0, L * 0.115)]), 28, _worn(Color(0.42, 0.45, 0.52), RUST, 0.25, 80.0))
		Provisions.lathe(k, POLISHED, xf, _crease([Vector2(R * 1.15, 0.002), Vector2(R * 1.2, 0.003), Vector2(R * 1.2, 0.008), Vector2(R * 1.15, 0.009)]), 28, BRASS)
		for i in 2:
			var a := VIEW + (i - 0.5) * 1.6
			k.box(POLISHED, xf * Transform3D(_radial(a), Vector3(cos(a), 0, sin(a)) * R * 1.17 + Vector3(0, 0.012, 0)), Vector3(0.008, 0.012, 0.003), BRASS.darkened(0.2))
	return _fin(k)

## Rocket propellant: a blue steel drum, ribbed round its waist, a brass screw cap between
## two lifting lugs, framed handles on the sides.
static func _rocket_fuel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var r := 0.07
	var h := 0.19
	var blue := Color(0.12, 0.17, 0.34)
	Provisions.lathe(k, PAINT, Transform3D.IDENTITY, _crease([Vector2(0, 0), Vector2(r * 0.92, 0), Vector2(r * 0.95, 0.008), Vector2(r, 0.012), Vector2(r, h * 0.16), Vector2(r * 0.97, h * 0.17), Vector2(r * 0.97, h * 0.19), Vector2(r, h * 0.2), Vector2(r, h * 0.82), Vector2(r * 0.92, h * 0.9), Vector2(r * 0.45, h * 0.96), Vector2(0, h * 0.96)]), 36, _worn(blue, Color(0.5, 0.36, 0.22), 0.35, 60.0))
	Provisions.lathe(k, POLISHED, Transform3D.IDENTITY, _crease([Vector2(0, h * 0.95), Vector2(0.02, h * 0.95), Vector2(0.02, h + 0.002), Vector2(0.018, h + 0.006), Vector2(0, h + 0.006)]), 24, BRASS,
		func(a: float, t: float, _p: Vector3) -> float: return 1.0 - 0.06 * absf(sin(a * 16.0)) * float(t < 0.5))
	for s: float in [-1.0, 1.0]:
		var poly := _v2([Vector2(-0.012, 0), Vector2(0.012, 0), Vector2(0.012, 0.03), Vector2(0.006, 0.03), Vector2(0.006, 0.008), Vector2(-0.006, 0.008), Vector2(-0.006, 0.03), Vector2(-0.012, 0.03)])
		_slab(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(s * 0.036, h * 0.88, 0)), poly, 0.006, STEEL.darkened(0.15))
		# Side handles: a steel frame standing off the drum.
		var a := VIEW + s * 1.3
		var n := Vector3(cos(a), 0, sin(a))
		var fr := _v2([Vector2(-0.01, 0), Vector2(0.01, 0), Vector2(0.01, 0.06), Vector2(-0.01, 0.06), Vector2(-0.01, 0), Vector2(-0.005, 0.005), Vector2(-0.005, 0.055), Vector2(0.005, 0.055), Vector2(0.005, 0.005), Vector2(-0.005, 0.005)])
		_slab(k, WORKED, Transform3D(_radial(a) * Basis(Vector3.UP, PI * 0.5), n * (r + 0.006) + Vector3(0, h * 0.35, 0)), fr, 0.012, BRASS.darkened(0.3))
	return _fin(k)

## Plasma fuel: a dark steel canister caged by brass bars, violet-tinted glass panels round
## its middle and a violet lens in its cap.
static func _plasma_fuel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var r := 0.045
	var h := 0.15
	var dark := Color(0.3, 0.3, 0.33)
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0, 0), Vector2(r * 1.1, 0), Vector2(r * 1.1, h * 0.2), Vector2(r * 0.9, h * 0.22), Vector2(r * 0.9, h * 0.78), Vector2(r * 1.1, h * 0.8), Vector2(r * 1.1, h * 0.9), Vector2(r * 0.8, h * 0.93), Vector2(r * 0.8, h), Vector2(r * 0.45, h), Vector2(0, h)]), 32, _worn(dark, RUST, 0.2, 80.0))
	Provisions.lathe(k, "own:lens", Transform3D.IDENTITY, _v2([Vector2(r * 0.94, h * 0.22), Vector2(r * 0.94, h * 0.78)]), 32, Color(0.26, 0.1, 0.48))
	Provisions.lathe(k, "own:lens", Transform3D.IDENTITY, _v2([Vector2(r * 0.4, h + 0.001), Vector2(0, h + 0.001)]), 16, Color(0.4, 0.18, 0.7))
	for i in 3:
		_wisp(k, Transform3D.IDENTITY, VIEW - 0.9 + i * 0.9, r * 0.95, h * 0.25, h * 0.75, 0.18, Color(0.62, 0.42, 0.9))
	for i in 4:
		var a := VIEW + PI * 0.25 + PI * 0.5 * i
		var n := Vector3(cos(a), 0, sin(a))
		k.box(POLISHED, Transform3D(_radial(a), n * (r * 1.12) + Vector3(0, h * 0.5, 0)), Vector3(0.008, h * 0.96, 0.005), BRASS.darkened(0.2))
		for y: float in [h * 0.12, h * 0.85]:
			ItemModels._block(k, POLISHED, Transform3D(_radial(a), n * (r * 1.16) + Vector3(0, y, 0)), Vector3(0.012, 0.014, 0.006), 0.0015, BRASS)
	return _fin(k)

## Fuel canister: a red pressure bottle with dark bands, a steel valve with a brass nozzle
## and a wire carrying loop over the top.
static func _fuel_canister(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var r := 0.058
	var h := 0.15
	var red := Color(0.55, 0.08, 0.07)
	Provisions.lathe(k, PAINT, Transform3D.IDENTITY, Provisions._curve([Vector2(0, 0), Vector2(r * 0.85, 0), Vector2(r * 0.85, 0), Vector2(r, h * 0.06), Vector2(r, h * 0.8), Vector2(r * 0.8, h * 0.93), Vector2(r * 0.3, h), Vector2(0, h)], 3), 32, _worn(red, red.darkened(0.45), 0.4, 70.0))
	for y: float in [h * 0.2, h * 0.7]:
		_band(k, PAINT, Transform3D.IDENTITY, r, y, 0.012, Color(0.1, 0.1, 0.11))
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0, h - 0.004), Vector2(0.016, h - 0.004), Vector2(0.016, h + 0.008), Vector2(0.01, h + 0.012), Vector2(0.01, h + 0.03), Vector2(0.014, h + 0.032), Vector2(0.014, h + 0.042), Vector2(0, h + 0.042)]), 16, GUNMETAL)
	Provisions.lathe(k, POLISHED, Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.008, h + 0.024, 0)), _crease([Vector2(0, 0), Vector2(0.0045, 0), Vector2(0.0045, 0.02), Vector2(0.007, 0.022), Vector2(0.007, 0.03), Vector2(0, 0.03)]), 12, BRASS)
	var loop := PackedVector3Array()
	for i in 13:
		var a := PI * i / 12.0
		loop.append(Vector3(-cos(a) * 0.024 - 0.014, h + 0.002 + sin(a) * 0.04, 0))
	var rad := PackedFloat32Array()
	rad.resize(loop.size())
	rad.fill(0.0024)
	Provisions.tube(k, WORKED, Transform3D.IDENTITY, loop, rad, 6, Color(0.15, 0.15, 0.16))
	return _fin(k)

## Jet fuel: a steel jerrycan burnished orange on its faces, the pressed X and frame ribs,
## a three-bar handle on top and the spout cap at the corner.
static func _jet_fuel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var w := 0.24
	var h := 0.32
	var d := 0.12
	var grey := Color(0.62, 0.6, 0.58)
	ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), 0.022, grey)
	var orange := Color(0.85, 0.42, 0.13)
	for s: float in [-1.0, 1.0]:
		var face := Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(0, h * 0.48, s * d * 0.5))
		# The burnished panel, then the pressed ribs over it.
		k.box(WORKED, face * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0005)), Vector3(w * 0.84, h * 0.84, 0.002), grey.lerp(orange, 0.25))
		k.box(WORKED, face * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0012)), Vector3(w * 0.62, h * 0.62, 0.002), grey.lerp(orange, 0.6))
		k.box(WORKED, face * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0019)), Vector3(w * 0.4, h * 0.4, 0.002), orange)
		var rib := grey.lerp(orange, 0.3)
		for e: Array in [[Vector3(0, h * 0.36, 0), Vector3(w * 0.72, 0.014, 0.008)], [Vector3(0, -h * 0.36, 0), Vector3(w * 0.72, 0.014, 0.008)], [Vector3(w * 0.36, 0, 0), Vector3(0.014, h * 0.72, 0.008)], [Vector3(-w * 0.36, 0, 0), Vector3(0.014, h * 0.72, 0.008)]]:
			k.box("im:metal@0.4", face * Transform3D(Basis.IDENTITY, (e[0] as Vector3) + Vector3(0, 0, 0.003)), e[1], rib)
		var diag := atan2(h * 0.66, w * 0.62)
		for sg: float in [-1.0, 1.0]:
			k.box("im:metal@0.4", face * Transform3D(Basis(Vector3.BACK, sg * diag), Vector3(0, 0, 0.004)), Vector3(sqrt(pow(w * 0.62, 2) + pow(h * 0.66, 2)), 0.016, 0.008), rib)
		k.box("im:metal@0.4", face * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.006)), Vector3(w * 0.24, h * 0.2, 0.006), rib)
		k.box("im:metal@0.4", face * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0075)), Vector3(w * 0.16, h * 0.13, 0.004), orange.darkened(0.1))
	# Handles: three bars across the top, a grip over them.
	for i in 3:
		var x := -w * 0.04 + i * w * 0.13
		ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(x, h + 0.015, 0)), Vector3(0.016, 0.03, 0.022), 0.004, grey.darkened(0.1))
	ItemModels._block(k, WORKED, Transform3D(Basis.IDENTITY, Vector3(w * 0.09, h + 0.034, 0)), Vector3(w * 0.36, 0.014, 0.026), 0.005, grey.darkened(0.15))
	Provisions.lathe(k, WORKED, Transform3D(Basis(Vector3.BACK, 0.5), Vector3(-w * 0.36, h - 0.012, 0)), _crease([Vector2(0, 0), Vector2(0.03, 0), Vector2(0.03, 0.03), Vector2(0.027, 0.036), Vector2(0, 0.036)]), 18, grey.darkened(0.3),
		func(a: float, t: float, _p: Vector3) -> float: return 1.0 - 0.08 * pow(absf(cos(a * 6.0)), 6.0) * float(t > 0.1))
	return _fin(k, Vector3(w * 0.09, h + 0.03, 0))

## Lamp oil: a round brown earthenware flask, a band of incised zigzag round its belly,
## a cork in the neck and a carrying cord knotted round it.
static func _lamp_oil(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.065
	var clay := Color(0.36, 0.18, 0.1)
	var prof := Provisions._curve([Vector2(0, 0), Vector2(R * 0.5, 0.002), Vector2(R * 0.9, R * 0.35), Vector2(R, R * 0.95), Vector2(R * 0.85, R * 1.55), Vector2(R * 0.4, R * 1.9), Vector2(0.018, R * 2.0), Vector2(0.018, R * 2.0), Vector2(0.018, R * 2.15), Vector2(0.024, R * 2.17), Vector2(0.024, R * 2.17), Vector2(0.024, R * 2.25), Vector2(0.015, R * 2.25)], 4)
	prof = _dense(prof, 4)
	Provisions.lathe(k, "pv_clay", Transform3D.IDENTITY, prof, 36, func(p: Vector3, a: float, _t: float) -> Color:
		var zig := absf(p.y - (R * 0.83 + 0.007 * (absf(fposmod(a * 12.0 / PI, 2.0) - 1.0) * 2.0 - 1.0))) < 0.0022
		var groove := absf(p.y - R * 0.68) < 0.0016 or absf(p.y - R * 0.98) < 0.0016
		var c := clay.darkened(0.06 * Provisions._nz(p, 40.0))
		return c.darkened(0.45) if zig or groove else c)
	Provisions.cork(k, Transform3D.IDENTITY, 0.016, R * 2.25, 0.018, 0.02)
	Provisions.twine(k, Transform3D.IDENTITY, 0.019, R * 2.04, 2, ROPE)
	var cord := PackedVector3Array([Vector3(-0.018, R * 2.05, 0.004), Vector3(-0.04, R * 1.8, 0.03), Vector3(-0.06, R * 1.3, 0.035), Vector3(-0.068, R * 0.8, 0.03), Vector3(-0.072, R * 0.45, 0.025)])
	Provisions.tube(k, "pv_twine", Transform3D.IDENTITY, cord, PackedFloat32Array([0.0026, 0.0026, 0.0026, 0.0026, 0.002]), 6, ROPE)
	Provisions.lathe(k, "pv_twine", Transform3D(Basis.IDENTITY, Vector3(-0.072, R * 0.42, 0.025)), Provisions._sphere(0.006, 6, 1.3), 8, ROPE.darkened(0.1))
	return _fin(k, Vector3(0, R * 2.1, 0))

## Black powder: a drab cloth sack gathered and tied at the neck, the cord's end hanging.
static func _black_powder(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var cloth := Color(0.33, 0.28, 0.21)
	Provisions.sack(k, Transform3D.IDENTITY, 0.07, 0.17, false, cloth)
	# The gathered cloth above the tie flares out in a ruffle.
	Provisions.lathe(k, "pv_burlap", Transform3D.IDENTITY, Provisions._curve([Vector2(0.012, 0.15), Vector2(0.02, 0.165), Vector2(0.034, 0.182), Vector2(0.04, 0.192), Vector2(0.036, 0.194)], 3), 36, cloth.darkened(0.05),
		func(a: float, t: float, _p: Vector3) -> float: return 1.0 + 0.22 * sin(a * 9.0) * t)
	var tail := PackedVector3Array([Vector3(0.012, 0.142, 0.008), Vector3(0.035, 0.13, 0.02), Vector3(0.05, 0.11, 0.024), Vector3(0.058, 0.085, 0.02)])
	Provisions.tube(k, "pv_twine", Transform3D.IDENTITY, tail, PackedFloat32Array([0.0022, 0.0022, 0.0022, 0.0018]), 6, ROPE)
	return _fin(k, Vector3(0, 0.15, 0))

# --- Traps and heavy ordnance ------------------------------------------------------------------

## Bear trap: two forged half-ring jaws laid open, a row of teeth standing up round them,
## the threaded cross bar with its springs, the pan plate in the middle, a chain off one side.
static func _bear_trap(k: MeshKit, r: RandomNumberGenerator, _t: String):
	var R := 0.12
	var jh := 0.04
	var jaw := _worn(IRON, RUST, 0.3, 50.0)
	for s in 2:
		Provisions.lathe(k, FORGED, Transform3D.IDENTITY, _crease([Vector2(R - 0.008, 0.0), Vector2(R, 0.0), Vector2(R, jh), Vector2(R - 0.008, jh), Vector2(R - 0.008, 0.0)]), 40, jaw, null, Vector2(s * 0.5 + 0.02, s * 0.5 + 0.48))
	var n := 22
	for i in n:
		var a := TAU * (i + 0.5) / n
		if absf(sin(a)) < 0.12:
			continue
		var tooth := _v2([Vector2(-0.011, 0), Vector2(0.011, 0), Vector2(0.0006, 0.028 + r.randf() * 0.005), Vector2(-0.0006, 0.028)])
		_slab(k, FORGED, Transform3D(_radial(a) * Basis(Vector3.RIGHT, -0.2), Vector3(cos(a), 0, sin(a)) * (R - 0.003) + Vector3(0, jh - 0.003, 0)), tooth, 0.004, IRON.lerp(RUST, r.randf() * 0.2))
	# The base bar across the hinges, threaded, with a coil spring each side.
	Provisions.tube(k, FORGED, Transform3D.IDENTITY, PackedVector3Array([Vector3(-R - 0.014, 0.01, 0), Vector3(R + 0.014, 0.01, 0)]), PackedFloat32Array([0.008, 0.008]), 8, IRON.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		var coil := PackedVector3Array()
		for i in 41:
			var a := TAU * i / 8.0
			coil.append(Vector3(s * (0.035 + i * 0.0019), 0.012 + sin(a) * 0.012, cos(a) * 0.012))
		var rad := PackedFloat32Array()
		rad.resize(coil.size())
		rad.fill(0.0028)
		Provisions.tube(k, FORGED, Transform3D.IDENTITY, coil, rad, 6, IRON.lightened(0.08))
		ItemModels._block(k, FORGED, Transform3D(Basis.IDENTITY, Vector3(s * (R + 0.006), 0.016, 0)), Vector3(0.02, 0.032, 0.03), 0.003, IRON.darkened(0.1))
	ItemModels._block(k, FORGED, Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(0, 0.026, 0)), Vector3(0.07, 0.006, 0.06), 0.002, Color(0.38, 0.35, 0.33))
	Provisions.lathe(k, FORGED, Transform3D(Basis.IDENTITY, Vector3(0, 0.026, 0)), _crease([Vector2(0, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.006), Vector2(0, 0.006)]), 8, IRON.darkened(0.3))
	for i in 4:
		var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * (i % 2)) * Basis(Vector3.BACK, PI * 0.5 - 0.5), Vector3(R + 0.024 + i * 0.02, 0.016 + i * 0.013, -0.004 * i))
		ItemModels._torus(k, FORGED, xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.5)), Vector3.ZERO), 0.011, 0.0035, 12, 6, IRON.lerp(RUST, 0.2))
	return _fin(k, Vector3(R + 0.06, 0.03, -0.012))

## Tripwire kit: a fat coil of rope, three whittled stakes lashed in a bundle beside it, and
## the iron trigger hanging on the rope's end.
static func _tripwire(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var rope := Color(0.26, 0.18, 0.1)
	var coil := PackedVector3Array()
	var turns := 9
	for i in turns * 16 + 1:
		var a := TAU * i / 16.0
		var f := float(i) / (turns * 16)
		var rr := 0.05 + 0.028 * fposmod(f * 3.0, 1.0) + 0.003 * sin(a * 0.7 + i * 0.05)
		coil.append(Vector3(-0.035 + cos(a) * rr, 0.02 + sin(a) * rr * 0.95, -0.012 * floorf(f * 3.0) - 0.004 * sin(a)))
	var rad := PackedFloat32Array()
	rad.resize(coil.size())
	rad.fill(0.0055)
	Provisions.tube(k, "im:rope", Transform3D.IDENTITY, coil, rad, 6, rope)
	var wood := Color(0.38, 0.22, 0.12)
	for i in 3:
		var xf := Transform3D(Basis(Vector3.BACK, -0.1 + i * 0.05), Vector3(0.045 + i * 0.026, 0.0, 0.012 - i * 0.006))
		Provisions.lathe(k, "pv_wood", xf, _crease([Vector2(0, -0.14), Vector2(0.016, -0.05), Vector2(0.017, 0.13), Vector2(0.012, 0.14), Vector2(0, 0.143)]), 4, _worn(wood, wood.darkened(0.35), 0.5, 40.0))
	for y: float in [0.055, 0.067, 0.079]:
		ItemModels._torus(k, "im:rope", Transform3D(Basis(Vector3.BACK, -0.05) * Basis.from_scale(Vector3(1.0, 1.0, 0.48)), Vector3(0.072, y, 0.004)), 0.046, 0.0035, 18, 5, rope)
	# The trigger on the rope's end: a slotted plate with a pin.
	var trig := Vector3(-0.08, -0.08, 0.03)
	Provisions.tube(k, "im:rope", Transform3D.IDENTITY, PackedVector3Array([Vector3(-0.06, -0.035, 0.0), Vector3(-0.075, -0.045, 0.02), trig + Vector3(0, 0.03, 0)]), PackedFloat32Array([0.003, 0.003, 0.003]), 5, rope)
	ItemModels._block(k, FORGED, Transform3D(Basis.IDENTITY, trig), Vector3(0.022, 0.055, 0.009), 0.002, Color(0.3, 0.3, 0.32))
	k.box(FORGED, Transform3D(Basis.IDENTITY, trig + Vector3(0.007, 0.0, 0.006)), Vector3(0.012, 0.02, 0.004), Color(0.42, 0.42, 0.44))
	Provisions.tube(k, "im:rope", Transform3D.IDENTITY, PackedVector3Array([trig + Vector3(0, -0.02, 0.004), Vector3(-0.06, -0.13, 0.035), Vector3(-0.01, -0.135, 0.035), Vector3(0.02, -0.11, 0.035)]), PackedFloat32Array([0.0028, 0.0028, 0.0028, 0.0028]), 5, rope)
	return _fin(k, Vector3(-0.035, 0.02, 0.0))

## Proximity mine: a squat olive disc with a stepped fuse cap, a dashed yellow ring on top,
## a sensor block with two red lenses at the front and four feet.
static func _proximity_mine(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.11
	var olive := Color(0.24, 0.25, 0.19)
	Provisions.lathe(k, PAINT, Transform3D.IDENTITY, _crease([Vector2(0, 0.012), Vector2(R * 0.95, 0.012), Vector2(R, 0.02), Vector2(R, 0.048), Vector2(R * 0.9, 0.058), Vector2(R * 0.62, 0.061), Vector2(R * 0.6, 0.066), Vector2(R * 0.3, 0.067), Vector2(0, 0.067)]), 40, _worn(olive, Color(0.14, 0.13, 0.1), 0.5, 50.0))
	_band(k, PAINT, Transform3D.IDENTITY, R, 0.033, 0.005, Color(0.12, 0.12, 0.1), 40)
	Provisions.lathe(k, WORKED, Transform3D.IDENTITY, _crease([Vector2(0, 0.066), Vector2(0.024, 0.066), Vector2(0.024, 0.075), Vector2(0.015, 0.078), Vector2(0.015, 0.088), Vector2(0.008, 0.09), Vector2(0, 0.09)]), 20, Color(0.26, 0.27, 0.25))
	for i in 12:
		var a0 := TAU * i / 12.0
		Provisions.lathe(k, PAINT, Transform3D.IDENTITY, _v2([Vector2(R * 0.5, 0.0675), Vector2(R * 0.4, 0.0675)]), 4, Color(0.8, 0.58, 0.1), null, Vector2(a0 / TAU, (a0 + 0.32) / TAU))
	# Hatch panels round the rim.
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		k.box(PAINT, Transform3D(_radial(a), Vector3(cos(a), 0, sin(a)) * (R + 0.0008) + Vector3(0, 0.04, 0)), Vector3(0.03, 0.012, 0.002), olive.darkened(0.2))
	var front := Vector3(cos(VIEW), 0, sin(VIEW))
	var b := _radial(VIEW)
	ItemModels._block(k, PAINT, Transform3D(b, front * (R - 0.002) + Vector3(0, 0.03, 0)), Vector3(0.056, 0.034, 0.026), 0.004, olive.darkened(0.3))
	for s: float in [-1.0, 1.0]:
		var at := front * (R + 0.011) + Vector3(0, 0.03, 0) + b.x * s * 0.013
		Provisions.lathe(k, WORKED, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at - front * 0.001), _crease([Vector2(0.0095, 0.0), Vector2(0.0095, 0.002), Vector2(0.0075, 0.002)]), 14, Color(0.15, 0.15, 0.15))
		Provisions.lathe(k, "own:lens", Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at), Provisions._curve([Vector2(0, 0.0), Vector2(0.0075, 0.0), Vector2(0.0075, 0.0), Vector2(0.006, 0.003), Vector2(0, 0.0038)], 2), 14, Color(0.55, 0.06, 0.05))
	for i in 4:
		var a := VIEW + PI * 0.25 + PI * 0.5 * i
		var n := Vector3(cos(a), 0, sin(a))
		ItemModels._block(k, PAINT, Transform3D(_radial(a), n * (R * 0.85) + Vector3(0, 0.009, 0)), Vector3(0.04, 0.018, 0.05), 0.004, Color(0.16, 0.16, 0.15))
		ItemModels._block(k, PAINT, Transform3D(_radial(a + 0.5), Vector3(cos(a + 0.5), 0, sin(a + 0.5)) * (R + 0.004) + Vector3(0, 0.036, 0)), Vector3(0.022, 0.02, 0.012), 0.003, olive.darkened(0.25))
	return _fin(k)

## Rocket: a fat olive-drab warhead tapering to a point, yellow bands, a slim motor tube
## and four swept fins round the nozzle.
static func _rocket(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.058
	var L := 0.62
	var body := Color(0.24, 0.26, 0.19)
	var prof := Provisions._curve([Vector2(0, 0), Vector2(0.018, 0), Vector2(0.018, 0), Vector2(0.026, 0.02), Vector2(0.026, 0.02), Vector2(0.028, 0.025), Vector2(0.028, L * 0.36), Vector2(R * 0.82, L * 0.45), Vector2(R, L * 0.56), Vector2(R * 0.96, L * 0.7), Vector2(R * 0.7, L * 0.84), Vector2(R * 0.3, L * 0.96), Vector2(0, L)], 4)
	Provisions.lathe(k, PAINT, Transform3D.IDENTITY, prof, 28, _worn(body, body.darkened(0.4), 0.5, 40.0))
	var yellow := Color(0.78, 0.55, 0.12)
	for y: float in [L * 0.37, L * 0.515, L * 0.675]:
		_band(k, PAINT, Transform3D.IDENTITY, Provisions._radius_at(prof, y), y, 0.014, yellow, 28)
	Provisions.lathe(k, FORGED, Transform3D.IDENTITY, _crease([Vector2(0.008, 0.006), Vector2(0.016, -0.006), Vector2(0.018, -0.006), Vector2(0.018, 0.002)]), 16, GUNMETAL.darkened(0.3))
	var fin := _v2([Vector2(0.024, 0.0), Vector2(0.095, -0.02), Vector2(0.09, 0.03), Vector2(0.024, 0.15)])
	for i in 4:
		_slab(k, PAINT, Transform3D(Basis(Vector3.UP, -VIEW + PI * 0.25 + PI * 0.5 * i), Vector3(0, 0.02, 0)), fin, 0.003, body.darkened(0.2))
	return _fin(k, Vector3(0, L * 0.3, 0))

# --- Alien fuels --------------------------------------------------------------------------------

## Void fuel (alien): a six-sided crystal vial in a dark metal cage with gold catches,
## pointed crystal ends, and a violet swirl inside that gives off a faint light.
static func _void_fuel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var R := 0.04
	var h := 0.1
	var dark := Color(0.16, 0.15, 0.19)
	Provisions.lathe(k, "own:glow_violet", Transform3D.IDENTITY, _v2([Vector2(0, 0.012), Vector2(R * 0.8, 0.014), Vector2(R * 0.8, h - 0.014), Vector2(0, h - 0.012)]), 6, Color(0.36, 0.14, 0.62),
		func(a: float, t: float, _p: Vector3) -> float: return 1.0 - 0.25 * pow(absf(sin(a * 1.5 + t * 9.0)), 4.0))
	Provisions.lathe(k, "pv_glass", Transform3D.IDENTITY, _crease([Vector2(R * 0.6, 0.0), Vector2(R, 0.012), Vector2(R, h - 0.012), Vector2(R * 0.6, h)]), 6, Color(0.35, 0.18, 0.55, 0.3))
	for i in 6:
		var a := TAU * i / 6.0
		var n := Vector3(cos(a), 0, sin(a))
		k.box(WORKED, Transform3D(_radial(a + PI / 6.0), n * R + Vector3(0, h * 0.5, 0)), Vector3(0.007, h * 0.8, 0.007), dark)
	for s: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis(Vector3.RIGHT, 0.0 if s > 0.0 else PI), Vector3(0, h * 0.5 + s * h * 0.5, 0))
		Provisions.lathe(k, WORKED, xf, _crease([Vector2(R * 0.5, -0.014), Vector2(R * 1.12, -0.005), Vector2(R * 1.0, 0.004), Vector2(R * 0.45, 0.008)]), 6, dark)
		k.crystal("im:crystal:void", xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.004, 0)), R * 0.45, 0.026, 6, 0.5, Color(0.22, 0.13, 0.32))
		for i in 3:
			var a := TAU * i / 3.0 + 0.3
			k.box(POLISHED, xf * Transform3D(_radial(a), Vector3(cos(a), 0, sin(a)) * R * 1.06 + Vector3(0, -0.004, 0)), Vector3(0.014, 0.012, 0.004), Color(0.7, 0.55, 0.28))
	return _fin(k, Vector3(0, h * 0.5, 0))

## Star fuel (alien): a golden egg of a flask, gold ribs curling round smoky glass, and in
## it a little sun that shines softly; a gold foot and a violet gem in the stopper.
static func _star_fuel(k: MeshKit, _r: RandomNumberGenerator, _t: String):
	var gold := Color(0.85, 0.62, 0.22)
	var prof := Provisions._curve([Vector2(0, 0.02), Vector2(0.034, 0.022), Vector2(0.058, 0.048), Vector2(0.06, 0.08), Vector2(0.046, 0.115), Vector2(0.022, 0.14), Vector2(0.013, 0.148)], 4)
	Provisions.lathe(k, "own:glow_sun", Transform3D(Basis.IDENTITY, Vector3(0, 0.074, 0)), Provisions._sphere(0.032, 12), 20, Color(1.0, 0.5, 0.06))
	Provisions.lathe(k, "pv_glass", Transform3D.IDENTITY, prof, 32, Color(0.25, 0.18, 0.2, 0.15))
	Provisions.lathe(k, POLISHED, Transform3D.IDENTITY, _crease([Vector2(0, 0), Vector2(0.04, 0), Vector2(0.042, 0.007), Vector2(0.034, 0.011), Vector2(0.02, 0.015), Vector2(0.024, 0.023), Vector2(0, 0.023)]), 32, gold)
	Provisions.lathe(k, POLISHED, Transform3D.IDENTITY, _crease([Vector2(0, 0.143), Vector2(0.018, 0.143), Vector2(0.018, 0.155), Vector2(0.013, 0.158), Vector2(0.013, 0.165), Vector2(0.017, 0.168), Vector2(0.009, 0.176), Vector2(0, 0.176)]), 20, gold)
	Provisions.lathe(k, "pv_glass", Transform3D(Basis.IDENTITY, Vector3(0, 0.175, 0)), Provisions._sphere(0.007, 6), 10, Color(0.45, 0.25, 0.7, 0.8))
	for i in 5:
		var a0 := TAU * i / 5.0
		var path := PackedVector3Array()
		var rad := PackedFloat32Array()
		for j in 13:
			var t := j / 12.0
			var y := lerpf(0.018, 0.146, t)
			var rr := Provisions._radius_at(prof, clampf(y, 0.021, 0.147)) + 0.004
			var a := a0 + 0.8 * sin(t * PI)
			path.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			rad.append(0.004 + 0.005 * sin(t * PI))
		Provisions.tube(k, POLISHED, Transform3D.IDENTITY, path, rad, 6, gold.darkened(0.08 * (i % 2)))
	return _fin(k, Vector3(0, 0.08, 0))
