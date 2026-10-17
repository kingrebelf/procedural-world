class_name Firearms
## Real models for the ranged weapons that have no kit model: black-powder guns, the
## western guns, modern firearms, human sci-fi energy weapons, bows and the alien
## weapons. Each is built from parts at its real size and in its real materials (walnut,
## blued, case-hardened or worn steel, brass, polymer, rubber, glass). Like GunLook's
## guns they point along -Z; the mesh's "grip" meta is where the right fist closes (the
## pistol grip or the wrist of the stock), "grip_r" how thick that is, "fore" where a
## second hand would hold the fore-end of a long gun, "butt" where its stock sits in the
## shoulder, and "sight" the point the eye looks along the sights from (rear notch or
## an optic's eyepiece).
##
## Nothing made by people glows: lenses are dark glass, energy cells are metal. Only the
## alien (Fantasy era) weapons keep a faint light in their glands and crystals.

## The builder for each item, and whether it is alien work.
const BUILD := {
	"flintlock_pistol": "_flintlock_pistol", "musket": "_musket", "blunderbuss": "_blunderbuss",
	"revolver_six": "_six_shooter", "lever_rifle": "_lever_rifle", "double_shotgun": "_double_shotgun",
	"bolt_rifle": "_bolt_rifle", "derringer": "_derringer", "flare_gun": "_flare_gun",
	"harpoon_gun": "_harpoon_gun", "gatling": "_gatling", "elephant_gun": "_elephant_gun",
	"laser_pistol": "_laser_pistol", "plasma_rifle": "_plasma_rifle", "gauss_rifle": "_gauss_rifle",
	"smart_pistol": "_smart_pistol", "auto_shotgun": "_auto_shotgun", "sniper_rail": "_sniper_rail",
	"minigun": "_minigun", "flamethrower": "_flamethrower", "rocket_launcher": "_rocket_launcher",
	"grenade_launcher": "_grenade_launcher", "needle_gun": "_needle_gun", "carbine_combat": "_carbine",
	"star_pistol": "_star_pistol", "singularity_orb": "_singularity_orb", "precursor_rifle": "_precursor_rifle",
	"nova_staff": "_nova_staff", "bio_rifle": "_bio_rifle", "hive_cannon": "_hive_cannon",
	"spore_launcher": "_spore_launcher", "shard_gauntlet": "_shard_gauntlet", "crystal_bow": "_crystal_bow",
	"eclipse_bow": "_eclipse_bow", "longbow": "_longbow", "shortbow": "_shortbow",
	"composite_bow": "_composite_bow", "royal_bow": "_royal_bow", "heavy_crossbow": "_heavy_crossbow",
	"sling": "_sling",
}

static func has(t: String) -> bool:
	return BUILD.has(t)

static func model(t: String) -> ArrayMesh:
	if not BUILD.has(t):
		return null
	var k := MeshKit.new(13)
	var grip: Vector3 = Callable(Firearms, BUILD[t]).call(k)
	var out := k.commit(Firearms.mat)
	out.set_meta("grip", grip)
	out.set_meta("grip_r", _grip_r)
	if _fore != Vector3.INF:
		out.set_meta("fore", _fore)
		var butt := _butt_point(out)
		if butt != Vector3.INF:
			out.set_meta("butt", butt)
	# A front sight alone (open-sighted guns aimed down the barrel): the eye looks along
	# its height from just over the grip.
	if _sight == Vector3.INF and _front != Vector3.INF:
		_sight = Vector3(0, _front.y, grip.z - 0.04)
	if _sight != Vector3.INF:
		out.set_meta("sight", _sight)
	_front = Vector3.INF
	_fore = Vector3.INF
	_sight = Vector3.INF
	_optic = false
	_grip_r = WRIST_R
	return out

## Where a shouldered gun's stock meets the shoulder: the middle of its rear face (the
## last 1.5 cm of the mesh). INF when the back end is not a stock (a crank, a pistol).
static func _butt_point(mesh: ArrayMesh) -> Vector3:
	var back := mesh.get_aabb().end.z
	var lo := INF
	var hi := -INF
	for i in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			if v.z > back - 0.015:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
	if hi - lo < 0.06:
		return Vector3.INF
	return Vector3(0, (lo + hi) * 0.5, back)

## Where the second hand goes on the gun being built (set by the builder).
static var _fore := Vector3.INF
## The radius of what the fist closes round on the gun being built (the "grip_r" meta):
## a stock's wrist unless the builder made a pistol grip, a riser or a bar.
const WRIST_R := 0.016
static var _grip_r := WRIST_R
## The eye's line along the gun ("sight" meta): the notch of the rear sight, or the
## middle of an optic's eyepiece; set by the sight builders, optics winning.
static var _sight := Vector3.INF
static var _optic := false
static var _front := Vector3.INF ## the front sight's tip, when there is no rear sight

# --- Materials -----------------------------------------------------------------------

## Stock woods beyond GunLook's walnut, so no two guns share one: [dark grain, light
## grain, roughness]. Each also comes as "_y" and "_x" (grain along those axes).
const SPECIES := {
	"gun_burl": [Color(0.09, 0.045, 0.025), Color(0.42, 0.24, 0.12), 0.36], # figured walnut, high contrast
	"gun_oiled": [Color(0.13, 0.07, 0.04), Color(0.32, 0.19, 0.1), 0.5], # old oiled walnut, dark
	"gun_honey": [Color(0.3, 0.17, 0.07), Color(0.62, 0.42, 0.22), 0.4], # straight-grained light walnut
	"gun_beech": [Color(0.3, 0.15, 0.08), Color(0.55, 0.33, 0.2), 0.55], # military beech, pinkish
	"gun_oak": [Color(0.3, 0.2, 0.11), Color(0.58, 0.44, 0.27), 0.6], # coarse oak
	"gun_rosewood": [Color(0.12, 0.04, 0.03), Color(0.36, 0.14, 0.08), 0.32],
}

static var _mats: Dictionary = {}

## Gun materials beyond GunLook's: finishes of steel, rubber, glass, ceramics, paints and
## the alien chitin and crystal.
static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: StandardMaterial3D
	match name:
		"gun_bore": m = GunLook._base(Color(0.012, 0.012, 0.013), 0.6, 0.6)
		"gun_bright": m = GunLook._base(Color(0.62, 0.62, 0.64), 0.22, 1.0)
		"gun_nickel": m = GunLook.finish(Color(0.62, 0.6, 0.56), 0.22, 1.0, Color(0.4, 0.38, 0.34), 0.12, 0.12)
		"gun_worn": m = GunLook.finish(Color(0.34, 0.34, 0.35), 0.4, 0.9, Color(0.6, 0.6, 0.6), 0.15, 0.2)
		"gun_parker": m = GunLook.finish(Color(0.12, 0.13, 0.12), 0.62, 0.6, Color(0.4, 0.4, 0.41), 0.05, 0.5)
		"gun_alloy": m = GunLook.finish(Color(0.11, 0.11, 0.12), 0.42, 0.7, Color(0.62, 0.62, 0.64), 0.06, 0.15)
		"gun_rubber": m = GunLook._base(Color(0.035, 0.035, 0.037), 0.88, 0.0)
		"gun_copper": m = GunLook._base(Color(0.85, 0.5, 0.33), 0.32, 1.0)
		"gun_gold": m = GunLook._base(Color(1.0, 0.77, 0.36), 0.2, 1.0)
		"gun_ceramic": m = GunLook.finish(Color(0.3, 0.31, 0.3), 0.5, 0.0, Color(0.22, 0.22, 0.21), 0.12, 0.25)
		"gun_od":
			m = GunLook._base(Color(0.24, 0.26, 0.18), 0.62, 0.15)
		"gun_tan": m = GunLook._base(Color(0.52, 0.45, 0.33), 0.7, 0.0)
		"gun_orange": m = GunLook._base(Color(0.85, 0.32, 0.06), 0.5, 0.0)
		"gun_red": m = GunLook._base(Color(0.45, 0.06, 0.05), 0.45, 0.0)
		"gun_horn": m = GunLook._base(Color(0.18, 0.13, 0.09), 0.35, 0.0)
		"gun_sinew": m = GunLook._base(Color(0.56, 0.45, 0.3), 0.6, 0.0)
		"gun_pearl":
			m = GunLook._base(Color(0.6, 0.58, 0.55), 0.32, 0.0)
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
		"gun_glass":
			# A coated lens: almost black, a faint blue-violet sheen, mirror-smooth.
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.02, 0.025, 0.035)
			m.roughness = 0.04
			m.metallic = 0.2
			m.metallic_specular = 0.9
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
		"gun_window":
			# A gauge or sight window: smoky, glossy, not lit.
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.08, 0.12, 0.13)
			m.roughness = 0.08
			m.metallic = 0.1
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
		"gun_case":
			m = _case_hardened()
		"gun_flint": m = GunLook._base(Color(0.2, 0.18, 0.16), 0.3, 0.0)
		_ when SPECIES.has(name.trim_suffix("_y").trim_suffix("_x")):
			m = GunLook._wood(name, SPECIES[name.trim_suffix("_y").trim_suffix("_x")], name.right(2))
		"gun_teak", "gun_teak_y":
			m = GunLook._wood(name, [Color(0.3, 0.17, 0.08), Color(0.58, 0.38, 0.2), 0.5], name.right(2))
		"gun_maple_x":
			m = GunLook._wood(name, [Color(0.5, 0.36, 0.2), Color(0.8, 0.64, 0.42), 0.45], "_x")
		"gun_yew_y":
			m = GunLook._wood(name, [Color(0.36, 0.15, 0.07), Color(0.7, 0.4, 0.2), 0.5], "_y")
		"gun_maple_y":
			m = GunLook._wood(name, [Color(0.62, 0.5, 0.34), Color(0.88, 0.76, 0.56), 0.5], "_y")
		"gun_ash_y":
			m = GunLook._wood(name, [Color(0.44, 0.32, 0.2), Color(0.7, 0.57, 0.4), 0.55], "_y")
		"gun_chitin":
			m = GunLook._base(Color(0.16, 0.13, 0.2), 0.3, 0.0)
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.25
			m.normal_scale = 0.35
		"gun_flesh":
			m = GunLook._base(Color(0.36, 0.2, 0.24), 0.45, 0.0)
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.5
		"gun_precursor":
			# Dark stone-like ceramic of a vanished people, polished by handling.
			m = GunLook._base(Color(0.11, 0.115, 0.12), 0.28, 0.0)
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
		"gun_void":
			m = GunLook._base(Color(0.005, 0.005, 0.008), 0.02, 0.9)
		"gun_crystal":
			# Clear quartz-like crystal (human worlds): no light of its own.
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.75, 0.82, 0.9, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.roughness = 0.05
			m.metallic_specular = 0.9
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
		_:
			if name.begins_with("alien_"):
				return _alien_glow(name.substr(6))
			# "<material>_chk": that material cut with fine diamond checkering (a grip,
			# the wrist of a stock); "<material>_stip": stippled (a moulded grip).
			for sfx in ["_chk", "_stip"]:
				if name.ends_with(sfx):
					m = (mat(name.trim_suffix(sfx)) as StandardMaterial3D).duplicate()
					_texture_detail(m, sfx == "_chk")
					if sfx == "_chk":
						# The grooves hold oil and grime and scatter the light: the
						# panel reads darker and matt against the polished wood.
						m.albedo_color = Color(0.72, 0.7, 0.68)
						m.roughness = minf(m.roughness + 0.25, 1.0)
						m.clearcoat = 0.05
					_mats[name] = m
					return m
			return GunLook.mat(name)
	_mats[name] = m
	return m

static var _detail: Dictionary = {}

## Lays a fine relief over `m` in its detail slot, on its own triplanar mapping so the
## material's grain stretch does not distort it: diamond checkering (about 13 lines to
## the inch, coarse enough to read in the hand) or a moulded stipple.
static func _texture_detail(m: StandardMaterial3D, checker: bool) -> void:
	var key := "chk" if checker else "stip"
	if not _detail.has(key):
		var n := 256
		var img := Image.create(n, n, false, Image.FORMAT_RF)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var bumps: Array = []
		for i in 900:
			bumps.append(Vector3(rng.randf() * n, rng.randf() * n, 2.0 + rng.randf() * 2.5))
		for y in n:
			for x in n:
				var h := 0.0
				if checker:
					# Two sets of V-grooves crossing at about 60 degrees leave sharp
					# pyramids between them; 16 diamonds each way across the tile.
					var a := fposmod((x + y * 0.58) / n * 16.0, 1.0)
					var b := fposmod((x - y * 0.58) / n * 16.0, 1.0)
					h = minf(1.0 - absf(a * 2.0 - 1.0), 1.0 - absf(b * 2.0 - 1.0))
				img.set_pixel(x, y, Color(h, 0, 0))
		if not checker:
			# Stipple: a scatter of small round dimples pressed into the mould.
			for bp in bumps:
				var b: Vector3 = bp
				for dy in range(-6, 7):
					for dx in range(-6, 7):
						var d := Vector2(dx, dy).length() / b.z
						if d < 1.0:
							var px := posmod(int(b.x) + dx, n)
							var py := posmod(int(b.y) + dy, n)
							img.set_pixel(px, py, Color(maxf(img.get_pixel(px, py).r, 1.0 - d * d), 0, 0))
		img.convert(Image.FORMAT_RGBA8)
		img.bump_map_to_normal_map(6.0 if checker else 3.0)
		img.generate_mipmaps()
		_detail[key] = ImageTexture.create_from_image(img)
	m.detail_enabled = true
	m.detail_normal = _detail[key]
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.uv2_triplanar = true
	m.uv2_triplanar_sharpness = 4.0
	# A tile 3.2 cm across: diamonds 2 mm; stipple dimples under a millimetre.
	m.uv2_scale = Vector3.ONE * (1.0 / 0.032)

## Case-hardened steel: the mottled straw, blue and grey of a bone-charcoal quench.
static func _case_hardened() -> StandardMaterial3D:
	var m := GunLook._base(Color.WHITE, 0.26, 0.92)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 5
	n.fractal_gain = 0.6
	n.domain_warp_enabled = true
	n.domain_warp_amplitude = 40.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.45, 0.6, 0.78, 1.0])
	g.colors = PackedColorArray([Color(0.15, 0.17, 0.26), Color(0.32, 0.33, 0.36), Color(0.5, 0.42, 0.3),
		Color(0.28, 0.3, 0.42), Color(0.4, 0.4, 0.42), Color(0.55, 0.47, 0.33)])
	var t := NoiseTexture2D.new()
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	m.albedo_texture = t
	# Colour in small swirls a few millimetres across, as the quench leaves it.
	m.uv1_scale = Vector3.ONE * 7.0
	return m

## A faint inner light for alien matter: glands, crystals, eye-like lenses.
static func _alien_glow(name: String) -> Material:
	var c: Color = GunLook.GLOW.get("glow_" + name, Color(0.4, 1.0, 0.8))
	var m := GunLook._base(c * 0.45, 0.25, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.45
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	_mats["alien_" + name] = m
	return m

# --- Parts ---------------------------------------------------------------------------

## A round barrel along -Z from z0, `len` long, radius r0 at the breech to r1 at the
## muzzle, with a crowned muzzle and a dark bore.
static func _barrel(k: MeshKit, m: String, at: Vector3, len: float, r0: float, r1: float, bore: float, segs := 18) -> void:
	k.cylinder(m, GunLook._z(at), r0, r1, len, segs)
	_bore(k, at - Vector3(0, 0, len), bore)

## The dark hole at a muzzle face at `at` (the face looks along -Z).
static func _bore(k: MeshKit, at: Vector3, r: float) -> void:
	k.cylinder("gun_bore", GunLook._z(at + Vector3(0, 0, 0.0004)), r, r, 0.0012, 14)

## A tube along -Z (no bore): bands, sleeves, housings, scope tubes.
static func _tube(k: MeshKit, m: String, at: Vector3, len: float, r0: float, r1 := -1.0, segs := 16) -> void:
	k.cylinder(m, GunLook._z(at), r0, r0 if r1 < 0.0 else r1, len, segs)

## A box centred at `at`, its edges and corners rounded off a little as a machined or
## moulded part's are, so they catch a thin highlight instead of meeting in a hard line.
static func _box(k: MeshKit, m: String, at: Vector3, size: Vector3, tilt := 0.0) -> void:
	var r := clampf(minf(size.x, minf(size.y, size.z)) * 0.18, 0.0002, 0.0015)
	_rounded_box(k, m, Transform3D(Basis(Vector3.RIGHT, tilt), at), size * 0.5, r)

## Each face of a box of half size `h` sampled across, then pulled onto the rounded box
## of edge radius r: a point's nearest point on the inner box (half size h - r), pushed
## out by r along the way to it. Four steps round each edge.
static func _rounded_box(k: MeshKit, m: String, xf: Transform3D, h: Vector3, r: float) -> void:
	var a := h - Vector3.ONE * r
	# Samples along each axis: the rounded band at each end, the flat face between.
	var ax: Array = []
	for i in 3:
		ax.append([-a[i] - r, -a[i] - r * 0.5, -a[i], a[i], a[i] + r * 0.5, a[i] + r])
	for f in 6:
		var n := f / 2 # the axis the face looks along
		var sg := 1.0 if f % 2 == 0 else -1.0
		var u := (n + 1) % 3
		var v := (n + 2) % 3
		var grid: Array = []
		for i in 6:
			var row: Array = []
			for j in 6:
				var q := Vector3.ZERO
				q[n] = sg * (a[n] + r)
				q[u] = ax[u][i]
				q[v] = ax[v][j]
				var c := q.clamp(-a, a)
				var d := (q - c).normalized()
				row.append([c + d * r, d])
			grid.append(row)
		for i in 5:
			for j in 5:
				var p0: Array = grid[i][j]
				var p1: Array = grid[i + 1][j]
				var p2: Array = grid[i + 1][j + 1]
				var p3: Array = grid[i][j + 1]
				var out := Vector3.ZERO
				out[n] = sg
				if (p1[0] - p0[0]).cross(p2[0] - p0[0]).dot(out) > 0.0:
					k.tri(m, xf, p0[0], p1[0], p2[0], p0[1], p1[1], p2[1])
					k.tri(m, xf, p0[0], p2[0], p3[0], p0[1], p2[1], p3[1])
				else:
					k.tri(m, xf, p0[0], p2[0], p1[0], p0[1], p2[1], p1[1])
					k.tri(m, xf, p0[0], p3[0], p2[0], p0[1], p3[1], p2[1])

## A small pin or screw head across the gun (along X), centred at `at`.
static func _pin(k: MeshKit, m: String, at: Vector3, r: float, len: float) -> void:
	k.cylinder(m, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), at + Vector3(len * 0.5, 0, 0)), r, r, len, 8)

## A strap through `pts` in the YZ plane: trigger guards, triggers, levers, hammers.
static func _strap(k: MeshKit, m: String, pts: Array, width: float, thick: float) -> void:
	var ws: Array = []
	var hs: Array = []
	for p in pts:
		ws.append(thick * 0.5)
		hs.append(width * 0.5)
	GunLook._loft(k, m, pts, ws, hs, Vector3.RIGHT, 8)

## A trigger guard from the frame at z_front back to z_back, hanging `depth` below y.
static func _guard(k: MeshKit, m: String, y: float, z_front: float, z_back: float, depth: float, width := 0.008) -> void:
	var l := z_back - z_front
	_strap(k, m, [Vector3(0, y + 0.002, z_front - 0.004), Vector3(0, y - depth * 0.6, z_front), Vector3(0, y - depth, z_front + l * 0.3),
		Vector3(0, y - depth, z_front + l * 0.65), Vector3(0, y - depth * 0.75, z_back - 0.004), Vector3(0, y - depth * 0.15, z_back + 0.006),
		Vector3(0, y + 0.002, z_back + 0.014)], width, 0.0032)

## A curved trigger blade hanging from `at`.
static func _trigger(k: MeshKit, m: String, at: Vector3, len := 0.02) -> void:
	_strap(k, m, [at + Vector3(0, 0.003, -0.002), at + Vector3(0, -len * 0.5, 0.0), at + Vector3(0, -len * 0.85, 0.004), at + Vector3(0, -len, 0.009)], 0.0055, 0.003)

## A rounded block centred at `c` (rounded-square sections along Z): receivers, slides,
## housings, so their edges catch the light like machined or moulded parts.
static func _block(k: MeshKit, m: String, c: Vector3, size: Vector3, segs := 16) -> void:
	GunLook._loft(k, m, [c + Vector3(0, 0, size.z * 0.5), c - Vector3(0, 0, size.z * 0.5)], [size.x * 0.5, size.x * 0.5], [size.y * 0.5, size.y * 0.5], Vector3.UP, segs)

## A box magazine hanging from `top`, `len` long, `depth` front to back, curving forward
## by `curve`, with a base plate.
static func _mag(k: MeshKit, m: String, top: Vector3, len: float, depth: float, w: float, curve := 0.0, base := "") -> void:
	var pts: Array = []
	var ws: Array = []
	var hs: Array = []
	for i in 5:
		var f := i / 4.0
		pts.append(top + Vector3(0, -len * f, -curve * len * f * f))
		ws.append(w * 0.5)
		hs.append(depth * 0.5)
	GunLook._loft(k, m, pts, ws, hs, Vector3.FORWARD, 12)
	var end: Vector3 = pts[4]
	var dir := (end - (pts[3] as Vector3)).normalized()
	GunLook._loft(k, base if base != "" else m, [end - dir * 0.002, end + dir * 0.006], [w * 0.56, w * 0.6], [depth * 0.56, depth * 0.58], Vector3.FORWARD, 12)

## A pistol grip from `top` raked back by `rake`, `len` long, swelling to a palm swell.
## Returns the point the fist closes round.
static func _grip(k: MeshKit, m: String, top: Vector3, rake: float, len: float, w: float, d: float, cap := "", curl := 0.0) -> Vector3:
	var dir := Vector3(0, -1, rake).normalized()
	var pts: Array = []
	var ws: Array = []
	var hs: Array = []
	for i in 6:
		var f := i / 5.0
		pts.append(top + dir * len * f + Vector3(0, 0, curl * len * f * f))
		var swell := 1.0 + 0.12 * sin(f * PI)
		ws.append(w * swell * (0.9 if i == 5 else 1.0))
		hs.append(d * swell * (0.92 if i == 5 else 1.0))
	GunLook._loft(k, m, pts, ws, hs, Vector3.FORWARD, 16)
	_grip_r = (w + d) * 0.5 * 1.06
	if cap != "":
		var end: Vector3 = pts[5]
		GunLook._loft(k, cap, [end - dir * 0.004, end + dir * 0.003], [w * 0.92, w * 0.85], [d * 0.94, d * 0.86], Vector3.FORWARD, 16)
	return top + dir * len * 0.45

## Finger grooves down the front strap of a grip made by _grip (same top, rake, len, depth).
static func _grooves(k: MeshKit, m: String, top: Vector3, rake: float, len: float, w: float, d: float) -> void:
	var dir := Vector3(0, -1, rake).normalized()
	for f in [0.32, 0.56, 0.8]:
		var p: Vector3 = top + dir * len * f - Vector3(0, 0, d * 0.93)
		k.sphere(m, Transform3D(Basis.from_scale(Vector3(w * 0.95, 0.009, 0.0065)), p), 1.0, 6, 12)

## Side panels on a grip made by _grip: inset slabs of another material on both faces.
static func _grip_panels(k: MeshKit, m: String, top: Vector3, rake: float, len: float, w: float, d: float) -> void:
	var dir := Vector3(0, -1, rake).normalized()
	for sd in [-1.0, 1.0]:
		GunLook._loft(k, m, [top + dir * len * 0.12 + Vector3(sd * w * 0.92, 0, 0), top + dir * len * 0.88 + Vector3(sd * w * 0.92, 0, 0)],
			[d * 0.62, d * 0.62], [w * 0.2, w * 0.2], Vector3.RIGHT, 12)

## Checkered panels on both sides of a stock's wrist or a fore-end: pointed ovals of the
## wood cut with checkering, set flush into the side at half width `w`, centred on `c`,
## `len` long and `h` tall, tilted by `tilt` (radians, nose down).
static func _checkering(k: MeshKit, m: String, c: Vector3, w: float, len: float, h: float, tilt := 0.0) -> void:
	var dir := Vector3(0, sin(tilt), -cos(tilt))
	for sd in [-1.0, 1.0]:
		var o := c + Vector3(sd * (w - 0.0003), 0, 0)
		var pts: Array = []
		var ws: Array = []
		var hs: Array = []
		for i in 9:
			var f := i / 8.0
			pts.append(o + dir * len * (f - 0.5))
			ws.append(h * 0.5 * maxf(pow(sin(f * PI), 0.7), 0.08))
			hs.append(0.0006)
		GunLook._loft(k, m, pts, ws, hs, Vector3.RIGHT, 10)

## A stock or fore-end along -Z through stations z with top and bottom lines and half
## widths; smooth, rounded-square sections.
static func _stock(k: MeshKit, m: String, zs: Array, tops: Array, bots: Array, ws: Array, segs := 18) -> void:
	var pts: Array = []
	var hs: Array = []
	for i in zs.size():
		pts.append(Vector3(0, (tops[i] + bots[i]) * 0.5, zs[i]))
		hs.append((tops[i] - bots[i]) * 0.5)
	GunLook._loft(k, m, pts, ws, hs, Vector3.UP, segs)

## A butt plate or recoil pad on the back of a stock at z, from y_top to y_bot.
static func _butt(k: MeshKit, m: String, z: float, y_top: float, y_bot: float, w: float, thick: float) -> void:
	var c := (y_top + y_bot) * 0.5
	var h := (y_top - y_bot) * 0.5
	GunLook._loft(k, m, [Vector3(0, c, z + thick), Vector3(0, c, z - 0.001)], [w * 0.98, w], [h * 0.99, h], Vector3.UP, 18)

## Front sight: a blade on a ramp.
static func _front_sight(k: MeshKit, m: String, at: Vector3, h := 0.008) -> void:
	_front = at + Vector3(0, h, 0)
	_box(k, m, at + Vector3(0, h * 0.25, 0), Vector3(0.006, h * 0.5, 0.014))
	_box(k, m, at + Vector3(0, h * 0.7, 0), Vector3(0.0022, h * 0.6, 0.005))

## Rear sight: a notched leaf.
static func _rear_sight(k: MeshKit, m: String, at: Vector3, w := 0.014, h := 0.007) -> void:
	if not _optic:
		_sight = at + Vector3(0, h * 0.6, 0)
	_box(k, m, at + Vector3(0, h * 0.2, 0), Vector3(w, h * 0.4, 0.01))
	for s in [-1.0, 1.0]:
		_box(k, m, at + Vector3(s * w * 0.3, h * 0.7, 0.002), Vector3(w * 0.38, h * 0.6, 0.003))

## A rail with cross slots, from z0 forward to z1, its top at y.
static func _rail(k: MeshKit, m: String, y: float, z0: float, z1: float, w := 0.021) -> void:
	_box(k, m, Vector3(0, y - 0.004, (z0 + z1) * 0.5), Vector3(w * 0.75, 0.006, z0 - z1))
	var z := z0 - 0.003
	while z > z1 + 0.004:
		_box(k, m, Vector3(0, y - 0.0015, z - 0.0026), Vector3(w, 0.003, 0.0052))
		z -= 0.01

## A telescopic sight over the gun: tube, objective and ocular bells, turrets, rings
## down to `base_y`, lenses at both ends.
static func _scope(k: MeshKit, y: float, z_eye: float, z_obj: float, r: float, obj_r: float, base_y: float, rings_z: Array) -> void:
	var m := "gun_alloy"
	var len := z_eye - z_obj
	_sight = Vector3(0, y, z_eye)
	_optic = true
	# Ocular: eyepiece housing and rubber ring.
	_tube(k, "gun_rubber", Vector3(0, y, z_eye + 0.008), 0.008, r * 1.55, r * 1.6)
	_tube(k, m, Vector3(0, y, z_eye), 0.05, r * 1.6, r * 1.35)
	_tube(k, m, Vector3(0, y, z_eye - 0.05), 0.025, r * 1.35, r)
	# Main tube, with the power ring knurl.
	_tube(k, m, Vector3(0, y, z_eye - 0.075), len - 0.075 - 0.08, r, r, 20)
	_tube(k, "gun_polymer", Vector3(0, y, z_eye - 0.03), 0.012, r * 1.62, r * 1.62, 24)
	# Objective bell.
	_tube(k, m, Vector3(0, y, z_obj + 0.08), 0.035, r, obj_r, 22)
	_tube(k, m, Vector3(0, y, z_obj + 0.045), 0.045, obj_r, obj_r, 22)
	k.cylinder("gun_glass", GunLook._z(Vector3(0, y, z_obj + 0.0035)), obj_r * 0.88, obj_r * 0.88, 0.004, 22)
	k.cylinder("gun_glass", GunLook._z(Vector3(0, y, z_eye + 0.0085)), r * 1.2, r * 1.2, 0.002, 18)
	# Turrets: elevation on top, windage on the right, with caps.
	var tz := z_eye - 0.075 - (len - 0.155) * 0.5
	k.cylinder(m, Transform3D(Basis(), Vector3(0, y, tz)), r * 0.75, r * 0.75, r + 0.012, 14)
	k.cylinder("gun_polymer", Transform3D(Basis(), Vector3(0, y + r + 0.004, tz)), r * 0.8, r * 0.8, 0.009, 18)
	k.cylinder(m, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0, y, tz)), r * 0.75, r * 0.75, r + 0.012, 14)
	k.cylinder("gun_polymer", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(r + 0.004, y, tz)), r * 0.8, r * 0.8, 0.009, 18)
	# Rings and their bases.
	for z in rings_z:
		_tube(k, m, Vector3(0, y, z + 0.008), 0.016, r * 1.18, r * 1.18, 18)
		_box(k, m, Vector3(0, (y - r + base_y) * 0.5, z), Vector3(r * 1.1, y - r - base_y + 0.004, 0.016))
		_pin(k, m, Vector3(-r * 1.25, y - r * 0.5, z), 0.0025, r * 2.5)

## A reflex sight on `base`. Rifles get a tube sight (a short sealed tube on a riser,
## caps on the turrets); pistols a small open hood. The lens is dark glass, unlit.
static func _red_dot(k: MeshKit, base: Vector3, tube := false) -> void:
	_sight = base + (Vector3(0, 0.032, 0.03) if tube else Vector3(0, 0.0115, 0.0))
	_optic = true
	if tube:
		_box(k, "gun_alloy", base + Vector3(0, 0.008, 0), Vector3(0.022, 0.016, 0.03))
		var c := base + Vector3(0, 0.032, 0.03)
		_tube(k, "gun_alloy", c, 0.06, 0.0165, 0.0165, 22)
		_tube(k, "gun_alloy", c + Vector3(0, 0, -0.06), 0.008, 0.0185, 0.0185, 22)
		_tube(k, "gun_rubber", c + Vector3(0, 0, 0.004), 0.004, 0.0175, 0.0175, 22)
		k.cylinder("gun_glass", GunLook._z(c + Vector3(0, 0, -0.067)), 0.014, 0.014, 0.002, 18)
		k.cylinder("gun_alloy", Transform3D(Basis(), c + Vector3(0, 0.01, -0.03)), 0.008, 0.008, 0.012, 14)
		k.cylinder("gun_alloy", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), c + Vector3(0.01, 0, -0.03)), 0.008, 0.008, 0.012, 14)
		return
	_block(k, "gun_alloy", base + Vector3(0, 0.003, 0), Vector3(0.022, 0.006, 0.034))
	GunLook._loft(k, "gun_alloy", [base + Vector3(-0.0095, 0.004, -0.014), base + Vector3(0, 0.02, -0.014), base + Vector3(0.0095, 0.004, -0.014)],
		[0.0025, 0.0025, 0.0025], [0.0035, 0.0035, 0.0035], Vector3.FORWARD, 8)
	k.cylinder("gun_glass", GunLook._z(base + Vector3(0, 0.0115, -0.012)), 0.0075, 0.0075, 0.0015, 16)
	_box(k, "gun_alloy", base + Vector3(0, 0.0075, 0.012), Vector3(0.018, 0.006, 0.008))

## A sling swivel: a small loop under the gun at `at`.
static func _swivel(k: MeshKit, m: String, at: Vector3) -> void:
	_box(k, m, at + Vector3(0, 0.003, 0), Vector3(0.006, 0.006, 0.008))
	GunLook._rod(k, m, [at + Vector3(0, -0.001, 0.008), at + Vector3(0, -0.012, 0.01), at + Vector3(0, -0.016, 0),
		at + Vector3(0, -0.012, -0.01), at + Vector3(0, -0.001, -0.008)], 0.0016, 6)

## A flintlock: lock plate on the right of the breech, the cock gripping its flint, the
## frizzen standing over the pan, and the frizzen spring. `at` is the pan; `sc` scales
## the lock (a pistol's is smaller than a musket's).
static func _flintlock(k: MeshKit, at: Vector3, sc := 1.0, plate := "gun_worn", brass := false) -> void:
	var x := at.x
	var v := func(y: float, z: float) -> Vector3: return at + Vector3(0, y * sc, z * sc)
	# Lock plate: a long banana-shaped plate let into the side of the stock.
	GunLook._loft(k, plate, [Vector3(x - 0.002, v.call(-0.011, -0.04).y, v.call(0, -0.04).z), Vector3(x - 0.002, v.call(-0.008, 0).y, at.z),
		Vector3(x - 0.002, v.call(-0.009, 0.045).y, v.call(0, 0.045).z), Vector3(x - 0.002, v.call(-0.013, 0.08).y, v.call(0, 0.08).z)],
		[0.006 * sc, 0.0115 * sc, 0.0105 * sc, 0.005 * sc], [0.0016, 0.0016, 0.0016, 0.0016], Vector3.RIGHT, 10)
	# Pan with its fence, and the frizzen: a steel face standing over the pan on its foot.
	_box(k, plate, v.call(0.0, 0.0) + Vector3(0.001, 0, 0), Vector3(0.012, 0.005, 0.016) * sc)
	_box(k, plate, v.call(0.004, 0.009) + Vector3(-0.002, 0, 0), Vector3(0.008, 0.006, 0.003) * sc)
	_box(k, "gun_worn", v.call(0.0045, -0.002) + Vector3(0.002, 0, 0), Vector3(0.012, 0.003, 0.018) * sc)
	_box(k, "gun_worn", v.call(0.019, -0.007) + Vector3(0.002, 0, 0), Vector3(0.011, 0.028, 0.0045) * sc, -0.22)
	_box(k, "gun_worn", v.call(0.032, -0.0045) + Vector3(0.002, 0, 0), Vector3(0.006, 0.004, 0.009) * sc, -0.22) # its toe
	# Frizzen spring under the pan, its screw.
	_strap(k, "gun_worn", [v.call(-0.005, -0.003) + Vector3(0.003, 0, 0), v.call(-0.008, -0.018) + Vector3(0.003, 0, 0), v.call(-0.005, -0.032) + Vector3(0.003, 0, 0)], 0.0045 * sc, 0.003)
	_pin(k, "gun_worn", v.call(-0.004, -0.02) + Vector3(0.002, 0, 0), 0.0024 * sc, 0.002)
	# Cock: a swan neck rising from the tumbler behind the pan, its jaws (top and bottom,
	# a screw through both) clamping the flint in a leather patch.
	var piv: Vector3 = v.call(-0.004, 0.038) + Vector3(0.004, 0, 0)
	k.cylinder(plate, Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), piv - Vector3(0.003, 0, 0)), 0.006 * sc, 0.006 * sc, 0.005, 12)
	var c := func(y: float, z: float) -> Vector3: return piv + Vector3(0.001, y * sc, z * sc)
	_strap(k, "gun_worn", [c.call(-0.004, 0.006), c.call(0.006, 0.006), c.call(0.016, 0.002), c.call(0.022, -0.008), c.call(0.022, -0.02)], 0.0085 * sc, 0.0055 * sc)
	_box(k, "gun_worn", c.call(0.0235, -0.026), Vector3(0.0065, 0.004, 0.016) * sc)
	_box(k, "gun_worn", c.call(0.0355, -0.026), Vector3(0.0065, 0.004, 0.016) * sc)
	k.cylinder("gun_worn", Transform3D(Basis(), c.call(0.02, -0.021)), 0.0022 * sc, 0.0022 * sc, 0.026 * sc, 8)
	k.cylinder("gun_worn", Transform3D(Basis(), c.call(0.046, -0.021)), 0.004 * sc, 0.004 * sc, 0.003 * sc, 10)
	_box(k, "gun_leather", c.call(0.0295, -0.031), Vector3(0.011, 0.008, 0.012) * sc)
	_box(k, "gun_flint", c.call(0.0295, -0.04), Vector3(0.012, 0.007, 0.01) * sc, 0.15)
	# Lock screws through the stock, and brass side washers when the gun has them.
	_pin(k, "gun_brass" if brass else "gun_worn", v.call(-0.006, 0.062) + Vector3(-0.001, 0, 0), 0.0026 * sc, 0.002)
	_pin(k, "gun_worn", v.call(-0.008, -0.028) + Vector3(-0.001, 0, 0), 0.0026 * sc, 0.002)

## A percussion or cartridge hammer standing at `at` (its pivot), the spur raked back.
static func _hammer(k: MeshKit, m: String, at: Vector3, h := 0.026) -> void:
	_strap(k, m, [at, at + Vector3(0, h * 0.5, -0.002), at + Vector3(0, h * 0.85, 0.002), at + Vector3(0, h, 0.012)], 0.009, 0.0065)
	_box(k, m, at + Vector3(0, h * 1.02, 0.016), Vector3(0.009, 0.004, 0.012), 0.35)

## A ramrod under a barrel at y from z0 forward `len`, with a cupped brass or steel tip.
static func _ramrod(k: MeshKit, at: Vector3, len: float, tip := "gun_brass") -> void:
	_tube(k, "gun_worn", at, len, 0.0035, 0.0035, 8)
	_tube(k, tip, at - Vector3(0, 0, len - 0.012), 0.014, 0.0048, 0.0048, 10)

## The six-shot cylinder of a revolver: chambers, flutes, ratchet. Centre at `at`
## (the cylinder runs from at.z back along +Z by len).
static func _cylinder(k: MeshKit, m: String, at: Vector3, len: float, r: float, fluted := true, shots := 6) -> void:
	_tube(k, m, at + Vector3(0, 0, len), len, r, r, 24)
	for c in shots:
		var a := TAU * c / shots + PI * 0.5
		var off := Vector3(cos(a) * r * 0.58, sin(a) * r * 0.58, 0)
		k.cylinder("gun_bore", GunLook._z(at + off + Vector3(0, 0, 0.0006)), r * 0.24, r * 0.24, 0.0014, 10)
		k.cylinder("gun_brass", GunLook._z(at + off + Vector3(0, 0, len + 0.0012)), r * 0.25, r * 0.25, 0.0016, 10)
		if fluted:
			var fa := a + PI / shots
			k.box("gun_bore", Transform3D(Basis(Vector3(0, 0, 1), fa), at + Vector3(cos(fa) * r * 0.97, sin(fa) * r * 0.97, len * 0.5)),
				Vector3(0.0035, r * 0.3, len * 0.62))

# --- Black powder --------------------------------------------------------------------

## A sea-service flintlock pistol (c. 1760): a round barrel full-stocked in walnut to near
## the muzzle, a swelling bird's-head butt under a brass cap, the lock on the right, a
## brass trigger guard and side plate, and a ramrod held in brass pipes.
static func _flintlock_pistol(k: MeshKit) -> Vector3:
	var y := 0.03
	var muzzle := -0.24
	_barrel(k, "gun_worn", Vector3(0, y, 0.0), -muzzle, 0.0105, 0.0085, 0.0062)
	_tube(k, "gun_worn", Vector3(0, y, 0.0), 0.06, 0.0115, 0.011, 8) # octagonal breech
	_tube(k, "gun_brass", Vector3(0, y, muzzle + 0.012), 0.006, 0.0098, 0.0098)
	_front_sight(k, "gun_brass", Vector3(0, y + 0.008, muzzle + 0.02), 0.004)
	# Stock: fore-end under the barrel to near the muzzle, the wrist, and the butt sweeping
	# down and back to a swollen pommel.
	_stock(k, "gun_burl", [-0.215, -0.15, -0.05, -0.0, 0.03],
		[y - 0.002, y - 0.002, y - 0.001, y + 0.006, y + 0.006], [y - 0.022, y - 0.024, y - 0.028, y - 0.034, y - 0.032],
		[0.0105, 0.0115, 0.0125, 0.0145, 0.0145])
	var pts := [Vector3(0, y - 0.012, 0.02), Vector3(0, y - 0.016, 0.05), Vector3(0, y - 0.03, 0.08), Vector3(0, y - 0.058, 0.104),
		Vector3(0, y - 0.09, 0.122), Vector3(0, y - 0.112, 0.13), Vector3(0, y - 0.122, 0.13)]
	GunLook._loft(k, "gun_burl_y", pts, [0.0145, 0.0125, 0.012, 0.0135, 0.0165, 0.0175, 0.012], [0.018, 0.016, 0.016, 0.017, 0.02, 0.019, 0.012], Vector3.FORWARD, 16)
	# Brass butt cap with its spurs up the sides.
	k.sphere("gun_brass", Transform3D(Basis.from_scale(Vector3(0.0175, 0.012, 0.019)), Vector3(0, y - 0.117, 0.13)), 1.0, 6, 14)
	# Its long spur runs up the back of the grip, tapering to a point.
	_strap(k, "gun_brass", [Vector3(0, y - 0.116, 0.1495), Vector3(0, y - 0.1, 0.1455), Vector3(0, y - 0.084, 0.137), Vector3(0, y - 0.07, 0.127)],
		0.011, 0.0022)
	GunLook._loft(k, "gun_brass", [Vector3(0, y - 0.07, 0.127), Vector3(0, y - 0.062, 0.12)], [0.0011, 0.0008], [0.0055, 0.0015], Vector3.RIGHT, 8)
	# Brass furniture: trigger guard, side plate opposite the lock, ramrod pipes.
	_guard(k, "gun_brass", y - 0.03, -0.02, 0.03, 0.022, 0.009)
	_trigger(k, "gun_worn", Vector3(0, y - 0.03, 0.002), 0.018)
	_box(k, "gun_brass", Vector3(-0.0148, y - 0.014, 0.02), Vector3(0.0015, 0.008, 0.05))
	_flintlock(k, Vector3(0.0146, y - 0.002, -0.004), 0.8)
	_ramrod(k, Vector3(0, y - 0.017, -0.02), 0.205, "gun_horn")
	for z in [-0.06, -0.17]:
		_tube(k, "gun_brass", Vector3(0, y - 0.017, z), 0.014, 0.0058, 0.0058, 10)
	# Barrel pin and tang screw.
	_pin(k, "gun_brass", Vector3(-0.012, y - 0.01, -0.12), 0.0018, 0.024)
	_pin(k, "gun_worn", Vector3(0, y + 0.007, 0.022), 0.0025, 0.002)
	return Vector3(0, y - 0.07, 0.11)

## A Brown Bess style musket: a 42-inch round barrel in bright steel, full walnut stock
## with a long butt, brass butt plate, trigger guard and ramrod pipes, a flintlock, sling
## swivels and a bayonet stud.
static func _musket(k: MeshKit) -> Vector3:
	var y := 0.04
	var muzzle := -1.07
	_barrel(k, "gun_worn", Vector3(0, y, 0.0), -muzzle, 0.0135, 0.0105, 0.0095, 18)
	_box(k, "gun_worn", Vector3(0, y + 0.01, muzzle + 0.04), Vector3(0.006, 0.006, 0.01)) # bayonet stud
	_front_sight(k, "gun_brass", Vector3(0, y + 0.009, muzzle + 0.06), 0.004)
	_stock(k, "gun_oiled", [-1.0, -0.6, -0.2, -0.03, 0.0],
		[y - 0.003, y - 0.002, y - 0.001, y + 0.004, y + 0.006], [y - 0.022, y - 0.026, y - 0.03, y - 0.036, y - 0.04],
		[0.0125, 0.0135, 0.0145, 0.0165, 0.017])
	# Wrist and butt: the comb drops toward the heel, a long toe line.
	_stock(k, "gun_oiled", [-0.01, 0.04, 0.09, 0.2, 0.33, 0.36],
		[y + 0.004, y - 0.004, y - 0.012, y - 0.022, y - 0.032, y - 0.034], [y - 0.04, y - 0.05, y - 0.075, y - 0.105, y - 0.14, y - 0.145],
		[0.017, 0.0145, 0.016, 0.019, 0.021, 0.021])
	_butt(k, "gun_brass", 0.36, y - 0.032, y - 0.147, 0.0212, 0.006)
	_box(k, "gun_brass", Vector3(0, y - 0.031, 0.33), Vector3(0.014, 0.003, 0.06), -0.08) # tang over the comb
	_guard(k, "gun_brass", y - 0.04, -0.03, 0.04, 0.026, 0.01)
	_box(k, "gun_brass", Vector3(0, y - 0.07, 0.07), Vector3(0.008, 0.003, 0.05), -0.4)
	_trigger(k, "gun_worn", Vector3(0, y - 0.04, 0.002), 0.02)
	_flintlock(k, Vector3(0.017, y, -0.006), 1.0, "gun_worn", true)
	_box(k, "gun_brass", Vector3(-0.0168, y - 0.018, 0.01), Vector3(0.0015, 0.012, 0.075))
	_ramrod(k, Vector3(0, y - 0.019, -0.03), 1.03, "gun_worn")
	for z in [-0.2, -0.55, -0.92]:
		_tube(k, "gun_brass", Vector3(0, y - 0.019, z), 0.028, 0.0062, 0.0062, 10)
	_tube(k, "gun_brass", Vector3(0, y - 0.012, -0.985), 0.018, 0.016, 0.0155) # nose cap
	_swivel(k, "gun_worn", Vector3(0, y - 0.03, -0.62))
	_swivel(k, "gun_worn", Vector3(0, y - 0.13, 0.22))
	_fore = Vector3(0, y - 0.016, -0.3)
	return Vector3(0, y - 0.035, 0.06)

## A brass blunderbuss: a short barrel flaring to a bell mouth, walnut stock, flintlock.
static func _blunderbuss(k: MeshKit) -> Vector3:
	var y := 0.04
	# The barrel flares over its last third: a stack of widening rings.
	var prof := [[0.0, 0.016], [-0.08, 0.0145], [-0.22, 0.0145], [-0.3, 0.017], [-0.36, 0.022], [-0.4, 0.03], [-0.415, 0.032]]
	for i in prof.size() - 1:
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		k.cylinder("gun_brass", GunLook._z(Vector3(0, y, a[0])), a[1], b[1], a[0] - b[0], 22, i == 0)
	# The open bell, dark down its throat.
	k.cylinder("gun_bore", GunLook._z(Vector3(0, y, -0.395)), 0.026, 0.026, 0.002, 22)
	_tube(k, "gun_brass", Vector3(0, y, -0.4), 0.012, 0.0315, 0.033, 22)
	for z in [0.0, -0.08, -0.22]:
		_tube(k, "gun_brass", Vector3(0, y, z + 0.004), 0.008, 0.0175, 0.0175, 22)
	_stock(k, "gun_oak", [-0.24, -0.15, -0.04, 0.0],
		[y - 0.008, y - 0.008, y - 0.006, y + 0.006], [y - 0.03, y - 0.033, y - 0.036, y - 0.042],
		[0.0145, 0.015, 0.016, 0.018])
	_stock(k, "gun_oak", [-0.01, 0.04, 0.09, 0.2, 0.3, 0.32],
		[y + 0.006, y - 0.004, y - 0.012, y - 0.022, y - 0.03, y - 0.032], [y - 0.042, y - 0.05, y - 0.07, y - 0.1, y - 0.13, y - 0.134],
		[0.018, 0.0145, 0.016, 0.019, 0.0205, 0.0205])
	_butt(k, "gun_brass", 0.32, y - 0.03, y - 0.136, 0.021, 0.006)
	_guard(k, "gun_brass", y - 0.042, -0.03, 0.04, 0.026, 0.01)
	_trigger(k, "gun_worn", Vector3(0, y - 0.042, 0.002), 0.02)
	_flintlock(k, Vector3(0.0185, y - 0.002, -0.006), 0.95, "gun_brass", true)
	_ramrod(k, Vector3(0, y - 0.026, -0.03), 0.22, "gun_brass")
	_tube(k, "gun_brass", Vector3(0, y - 0.026, -0.18), 0.02, 0.0062, 0.0062, 10)
	_fore = Vector3(0, y - 0.02, -0.16)
	return Vector3(0, y - 0.035, 0.06)

# --- Western guns --------------------------------------------------------------------

## A single-action army revolver: case-hardened frame, blued 7.5-inch barrel with its
## ejector housing, fluted cylinder, loading gate, hammer with a checkered spur, brass
## guard and a one-piece walnut grip.
static func _six_shooter(k: MeshKit) -> Vector3:
	return _revolver_build(k, 0.19, "gun_case", "gun_blued", "gun_burl_y", "gun_brass", true)

static func _revolver_build(k: MeshKit, barrel: float, frame: String, steel: String, grip: String, guard: String, ejector: bool) -> Vector3:
	var y := 0.032 # the bore: the barrel lines up with the top chamber
	var yc := y - 0.0113 # the cylinder's axis
	var r := 0.0195
	# Cylinder between the recoil shield and the frame's front, on its base pin.
	_cylinder(k, steel, Vector3(0, yc, -0.052), 0.046, r)
	_tube(k, steel, Vector3(0, yc, -0.052), 0.004, 0.0062, 0.0062, 14) # base pin bushing
	# Frame: the recoil shield behind the cylinder (a round boss over the rims), the
	# front where the barrel screws in, the water table under the cylinder, and the top
	# strap over it with the sighting groove down its back end.
	_tube(k, frame, Vector3(0, yc, 0.011), 0.0045, 0.0212, 0.0212, 28)
	_block(k, frame, Vector3(0, (yc - 0.027 + y + 0.012) * 0.5, 0.0095), Vector3(0.0205, y + 0.012 - (yc - 0.027), 0.015), 20)
	_block(k, frame, Vector3(0, y - 0.004, -0.061), Vector3(0.0205, 0.032, 0.016), 20)
	_block(k, frame, Vector3(0, yc - 0.021, -0.026), Vector3(0.019, 0.01, 0.07), 16)
	_block(k, frame, Vector3(0, y + 0.0118, -0.025), Vector3(0.013, 0.0055, 0.084), 16)
	_box(k, "gun_bore", Vector3(0, y + 0.0147, 0.006), Vector3(0.0025, 0.0012, 0.02)) # rear sight groove
	_pin(k, steel, Vector3(-0.0105, y + 0.004, -0.061), 0.0018, 0.021) # base pin latch
	# Loading gate on the right of the shield, hinged at its foot.
	_block(k, frame, Vector3(0.0102, yc + 0.006, 0.009), Vector3(0.0035, 0.013, 0.011), 12)
	# Barrel: a round barrel with a crowned muzzle and a blade front sight.
	_barrel(k, steel, Vector3(0, y, -0.069), barrel, 0.0089, 0.0082, 0.0057, 24)
	_front_sight(k, steel, Vector3(0, y + 0.0079, -0.069 - barrel + 0.008), 0.006)
	if ejector:
		# Ejector housing along the right of the barrel, its thumb button and screw.
		_tube(k, steel, Vector3(0.0085, y - 0.0085, -0.07), barrel * 0.66, 0.0048, 0.0048, 14)
		_block(k, steel, Vector3(0.0085, y - 0.0085, -0.07 - barrel * 0.665), Vector3(0.0096, 0.0096, 0.004), 14)
		_block(k, steel, Vector3(0.0128, y - 0.0085, -0.09), Vector3(0.003, 0.004, 0.009), 10)
		_pin(k, steel, Vector3(0.012, y - 0.0085, -0.07 - barrel * 0.6), 0.0016, 0.002)
	# Hammer: rising from the slot behind the shield, its spur curling back over the
	# grip, knurled where the thumb draws it.
	var hz := 0.018
	_strap(k, steel, [Vector3(0, yc - 0.004, hz), Vector3(0, y + 0.008, hz - 0.001), Vector3(0, y + 0.017, hz + 0.004), Vector3(0, y + 0.022, hz + 0.013),
		Vector3(0, y + 0.0215, hz + 0.021)], 0.0075, 0.0068)
	GunLook._loft(k, steel + "_chk" if steel == "gun_blued" else steel, [Vector3(0, y + 0.0235, hz + 0.01), Vector3(0, y + 0.024, hz + 0.016), Vector3(0, y + 0.0222, hz + 0.022)],
		[0.0046, 0.0052, 0.0046], [0.0012, 0.0012, 0.0012], Vector3.RIGHT, 10)
	# Grip frame in brass: the trigger guard and the backstrap, which runs down the back of
	# the grip from the hammer to the butt.
	_guard(k, guard, yc - 0.026, -0.032, 0.006, 0.021, 0.0085)
	_trigger(k, steel, Vector3(0, yc - 0.026, -0.016), 0.017)
	# The plow-handle grip, between the front strap (down from behind the guard) and the
	# backstrap (down from the hammer), raked some 20 degrees and swelling back into the
	# heel at the bottom. Each line is [y, z] at f = 0..1 down the grip.
	var front := func(f: float) -> Vector3: return Vector3(0, lerpf(yc - 0.026, y - 0.106, f), 0.003 + 0.022 * f + 0.004 * pow(f, 4.0))
	var back_l := func(f: float) -> Vector3: return Vector3(0, lerpf(yc - 0.006, y - 0.1, f), 0.026 + 0.012 * f + 0.026 * pow(f, 2.5))
	var gp: Array = []
	var gws: Array = []
	var ghs: Array = []
	var bk: Array = [Vector3(0, yc + 0.006, hz + 0.006)]
	var bw: Array = [0.0021]
	var bh: Array = [0.0045]
	for i in 7:
		var f := i / 6.0
		var fr: Vector3 = front.call(f)
		var bc: Vector3 = back_l.call(f)
		gp.append((fr + bc) * 0.5)
		ghs.append((bc.z - fr.z) * 0.5)
		gws.append(0.0118 * (1.0 + 0.1 * sin(f * PI)) * (0.88 if i == 6 else 1.0))
		bk.append(bc - Vector3(0, 0, 0.0008))
		bw.append(0.0021)
		bh.append(0.0062 + 0.0016 * sin(f * PI))
	# The heel rounds off under the hand.
	gp.append(gp[6] + Vector3(0, -0.005, 0.002))
	gws.append(gws[6] * 0.7)
	ghs.append(ghs[6] * 0.6)
	GunLook._loft(k, grip, gp, gws, ghs, Vector3.FORWARD, 22)
	GunLook._loft(k, guard, bk, bw, bh, Vector3.RIGHT, 12)
	_grip_r = (0.0118 + (back_l.call(0.45).z - front.call(0.45).z) * 0.5) * 0.5 * 1.06
	var g: Vector3 = gp[3] - Vector3(0, 0, 0.002)
	# Frame screws on the left (the right carries the gate and ejector).
	for p in [Vector3(-0.0106, yc - 0.015, -0.006), Vector3(-0.0106, yc - 0.014, -0.045), Vector3(-0.0106, yc + 0.004, 0.009)]:
		_pin(k, steel, p, 0.0021, 0.0215)
	_pin(k, steel, Vector3(-0.0125, g.y - 0.006, g.z), 0.0028, 0.025) # grip screw
	return g

## A Winchester '73 lever-action: octagonal barrel with the tube magazine under it, a
## case-hardened receiver with loading gate, exposed hammer, the lever loop under a
## straight walnut wrist, a crescent butt plate, buckhorn rear and blade front sights.
static func _lever_rifle(k: MeshKit) -> Vector3:
	var y := 0.03
	var muzzle := -0.68
	_box(k, "gun_case", Vector3(0, y - 0.012, -0.045), Vector3(0.026, 0.058, 0.13))
	_box(k, "gun_case", Vector3(0, y + 0.012, 0.025), Vector3(0.02, 0.016, 0.02))
	_box(k, "gun_bore", Vector3(0.013, y + 0.0, -0.05), Vector3(0.002, 0.014, 0.034)) # ejection gap
	_box(k, "gun_blued", Vector3(0.0132, y - 0.018, -0.07), Vector3(0.0015, 0.012, 0.03)) # loading gate
	_barrel(k, "gun_blued", Vector3(0, y + 0.004, -0.11), -muzzle - 0.11, 0.0125, 0.0118, 0.0058, 8)
	_tube(k, "gun_blued", Vector3(0, y - 0.019, -0.11), -muzzle - 0.13, 0.0085, 0.0085, 14)
	_tube(k, "gun_blued", Vector3(0, y - 0.019, muzzle + 0.02), 0.01, 0.0087, 0.0087, 14)
	_tube(k, "gun_blued", Vector3(0, y - 0.007, muzzle + 0.06), 0.012, 0.022, 0.022, 8) # magazine band
	_front_sight(k, "gun_brass", Vector3(0, y + 0.0165, muzzle + 0.02), 0.007)
	# Buckhorn rear sight with its elevator.
	_box(k, "gun_blued", Vector3(0, y + 0.018, -0.24), Vector3(0.012, 0.004, 0.03))
	for s in [-1.0, 1.0]:
		_box(k, "gun_blued", Vector3(s * 0.009, y + 0.025, -0.25), Vector3(0.008, 0.012, 0.003), 0.0)
	# Fore-end: walnut round the barrel and magazine to its steel cap.
	_stock(k, "gun_walnut", [-0.11, -0.2, -0.33, -0.35],
		[y + 0.004, y + 0.004, y + 0.004, y + 0.004], [y - 0.03, y - 0.03, y - 0.029, y - 0.028],
		[0.0145, 0.0145, 0.014, 0.013])
	_tube(k, "gun_blued", Vector3(0, y - 0.0125, -0.345), 0.012, 0.0152, 0.0152, 16)
	# Butt stock: straight wrist, the comb dropping to a crescent butt.
	_stock(k, "gun_walnut", [0.02, 0.06, 0.12, 0.22, 0.32, 0.345],
		[y + 0.012, y + 0.004, y - 0.002, y - 0.012, y - 0.024, y - 0.026], [y - 0.04, y - 0.04, y - 0.06, y - 0.088, y - 0.12, y - 0.124],
		[0.013, 0.0125, 0.0145, 0.0175, 0.019, 0.019])
	_butt(k, "gun_blued", 0.345, y - 0.026, y - 0.126, 0.0195, 0.008)
	_box(k, "gun_blued", Vector3(0, y - 0.13, 0.336), Vector3(0.016, 0.01, 0.02), 0.5) # crescent toe
	# The lever: a loop for the fingers behind the trigger, running along under the receiver.
	_strap(k, "gun_case", [Vector3(0, y - 0.04, -0.09), Vector3(0, y - 0.044, -0.03), Vector3(0, y - 0.046, 0.0), Vector3(0, y - 0.05, 0.01),
		Vector3(0, y - 0.07, 0.02), Vector3(0, y - 0.085, 0.045), Vector3(0, y - 0.08, 0.085), Vector3(0, y - 0.06, 0.1),
		Vector3(0, y - 0.044, 0.085), Vector3(0, y - 0.041, 0.06)], 0.009, 0.005)
	_trigger(k, "gun_blued", Vector3(0, y - 0.041, 0.006), 0.016)
	_hammer(k, "gun_case", Vector3(0, y + 0.012, 0.026), 0.026)
	for p in [Vector3(-0.0135, y - 0.02, -0.02), Vector3(-0.0135, y - 0.02, -0.09), Vector3(-0.0135, y + 0.0, -0.1)]:
		_pin(k, "gun_blued", p, 0.0024, 0.027)
	_fore = Vector3(0, y - 0.012, -0.24)
	return Vector3(0, y - 0.018, 0.06)

## A side-by-side boxlock shotgun: twin barrels with a matted rib and brass bead, a
## case-hardened action with top lever, two triggers, splinter fore-end, English stock.
static func _double_shotgun(k: MeshKit) -> Vector3:
	var y := 0.032
	var len := 0.71
	for s in [-1.0, 1.0]:
		_barrel(k, "gun_blued", Vector3(s * 0.0106, y, -0.06), len, 0.0118, 0.0102, 0.0091, 20)
	_box(k, "gun_blued", Vector3(0, y + 0.009, -0.06 - len * 0.5), Vector3(0.007, 0.006, len))
	_box(k, "gun_blued", Vector3(0, y - 0.008, -0.06 - len * 0.5), Vector3(0.007, 0.006, len))
	k.sphere("gun_brass", Transform3D(Basis(), Vector3(0, y + 0.0135, -0.06 - len + 0.012)), 0.0022, 5, 8)
	# Action: the bar under the breech, the fences, the top lever.
	_box(k, "gun_case", Vector3(0, y - 0.006, -0.025), Vector3(0.042, 0.042, 0.075))
	for s in [-1.0, 1.0]:
		k.sphere("gun_case", Transform3D(Basis.from_scale(Vector3(1, 1, 0.6)), Vector3(s * 0.0106, y, -0.058)), 0.0145, 7, 14)
	_box(k, "gun_case", Vector3(0, y + 0.017, 0.022), Vector3(0.022, 0.006, 0.03))
	_box(k, "gun_blued", Vector3(0.008, y + 0.022, 0.02), Vector3(0.026, 0.004, 0.012), 0.0)
	_box(k, "gun_blued", Vector3(0, y + 0.0215, 0.05), Vector3(0.007, 0.002, 0.03)) # safety on the tang
	# Splinter fore-end.
	_stock(k, "gun_honey", [-0.07, -0.13, -0.24, -0.27],
		[y - 0.008, y - 0.008, y - 0.008, y - 0.01], [y - 0.03, y - 0.03, y - 0.028, y - 0.02], [0.016, 0.016, 0.015, 0.012])
	_box(k, "gun_case", Vector3(0, y - 0.03, -0.12), Vector3(0.008, 0.002, 0.06))
	# English stock: a straight slim wrist.
	_stock(k, "gun_honey", [0.01, 0.06, 0.12, 0.22, 0.34, 0.37],
		[y + 0.016, y + 0.012, y + 0.006, y - 0.006, y - 0.02, y - 0.022], [y - 0.028, y - 0.03, y - 0.05, y - 0.085, y - 0.12, y - 0.124],
		[0.021, 0.0135, 0.015, 0.018, 0.0195, 0.0195])
	_butt(k, "gun_rubber", 0.37, y - 0.022, y - 0.126, 0.0198, 0.014)
	_guard(k, "gun_case", y - 0.027, -0.03, 0.035, 0.026, 0.01)
	_trigger(k, "gun_blued", Vector3(0, y - 0.027, -0.012), 0.017)
	_trigger(k, "gun_blued", Vector3(0, y - 0.027, 0.008), 0.017)
	for p in [Vector3(-0.0215, y - 0.01, -0.035), Vector3(-0.0215, y + 0.004, -0.01)]:
		_pin(k, "gun_case", p, 0.0028, 0.043)
	_checkering(k, "gun_honey_chk", Vector3(0, y - 0.008, 0.07), 0.0142, 0.06, 0.03, 0.1)
	_checkering(k, "gun_honey_chk", Vector3(0, y - 0.019, -0.17), 0.016, 0.08, 0.016)
	_fore = Vector3(0, y - 0.02, -0.17)
	return Vector3(0, y - 0.012, 0.065)

## A Mauser-pattern bolt-action rifle: a slim tapered barrel, a full walnut stock with a
## semi-pistol grip, the bolt with its turned-down knob, a hooded front sight, a tangent
## rear sight, a barrel band, sling swivels and a steel butt plate.
static func _bolt_rifle(k: MeshKit) -> Vector3:
	var y := 0.032
	var muzzle := -0.74
	_tube(k, "gun_blued", Vector3(0, y, 0.04), 0.17, 0.0145, 0.0145, 20) # receiver
	_box(k, "gun_bore", Vector3(0.0, y + 0.0128, -0.04), Vector3(0.011, 0.002, 0.06)) # loading port
	_barrel(k, "gun_blued", Vector3(0, y, -0.13), -muzzle - 0.13, 0.0135, 0.0092, 0.004, 18)
	_tube(k, "gun_blued", Vector3(0, y, -0.13), 0.06, 0.0145, 0.0135, 18) # chamber reinforce
	# Bolt: body behind the receiver, the root and the turned-down handle with a pear knob.
	_tube(k, "gun_bright", Vector3(0, y, 0.085), 0.06, 0.009, 0.009, 14)
	_tube(k, "gun_blued", Vector3(0, y, 0.105), 0.022, 0.0115, 0.0105, 14) # shroud
	_box(k, "gun_blued", Vector3(0, y + 0.012, 0.1), Vector3(0.004, 0.008, 0.01)) # safety flag
	GunLook._rod(k, "gun_bright", [Vector3(0.008, y, 0.05), Vector3(0.03, y - 0.012, 0.055), Vector3(0.036, y - 0.026, 0.06)], 0.004, 10)
	k.sphere("gun_bright", Transform3D(Basis.from_scale(Vector3(1, 1.1, 1)), Vector3(0.037, y - 0.032, 0.061)), 0.008, 7, 12)
	# Sights: the tangent leaf on its base over the chamber, a hooded front blade.
	_box(k, "gun_blued", Vector3(0, y + 0.016, -0.17), Vector3(0.018, 0.006, 0.05))
	_box(k, "gun_blued", Vector3(0, y + 0.02, -0.165), Vector3(0.014, 0.0025, 0.055), -0.05)
	_rear_sight(k, "gun_blued", Vector3(0, y + 0.022, -0.14), 0.012, 0.005)
	_front_sight(k, "gun_blued", Vector3(0, y + 0.009, muzzle + 0.012), 0.008)
	GunLook._loft(k, "gun_blued", [Vector3(0, y + 0.014, muzzle + 0.002), Vector3(0, y + 0.014, muzzle + 0.026)], [0.008, 0.008], [0.009, 0.009], Vector3.UP, 12)
	# Stock: fore-end to a nose cap, the band, the semi-pistol grip and butt.
	_stock(k, "gun_beech", [-0.6, -0.4, -0.15, -0.0, 0.08],
		[y - 0.002, y - 0.0, y + 0.003, y + 0.003, y + 0.003], [y - 0.024, y - 0.028, y - 0.034, y - 0.04, y - 0.045],
		[0.0115, 0.013, 0.0145, 0.0155, 0.0155])
	_tube(k, "gun_blued", Vector3(0, y - 0.01, -0.59), 0.02, 0.0145, 0.014, 16)
	_tube(k, "gun_blued", Vector3(0, y - 0.01, -0.4), 0.014, 0.017, 0.017, 16)
	_stock(k, "gun_beech", [0.07, 0.11, 0.15, 0.25, 0.4, 0.43],
		[y + 0.004, y - 0.003, y - 0.006, y - 0.012, y - 0.024, y - 0.026], [y - 0.05, y - 0.075, y - 0.07, y - 0.1, y - 0.135, y - 0.138],
		[0.0155, 0.015, 0.0155, 0.018, 0.0195, 0.0195])
	_butt(k, "gun_blued", 0.43, y - 0.026, y - 0.14, 0.0198, 0.006)
	_box(k, "gun_blued", Vector3(0, y - 0.0455, -0.03), Vector3(0.016, 0.003, 0.09)) # floorplate
	_guard(k, "gun_blued", y - 0.046, 0.02, 0.07, 0.024, 0.009)
	_trigger(k, "gun_blued", Vector3(0, y - 0.046, 0.044), 0.018)
	_swivel(k, "gun_blued", Vector3(0, y - 0.03, -0.4))
	_swivel(k, "gun_blued", Vector3(0, y - 0.13, 0.33))
	_checkering(k, "gun_beech_chk", Vector3(0, y - 0.034, 0.11), 0.0153, 0.06, 0.032, 0.35)
	_checkering(k, "gun_beech_chk", Vector3(0, y - 0.016, -0.26), 0.0137, 0.1, 0.014)
	_fore = Vector3(0, y - 0.014, -0.25)
	return Vector3(0, y - 0.04, 0.1)

## A double derringer: blued over-and-under barrels on a case-hardened frame, a spur
## trigger and a bird's-head walnut grip. Palm-sized.
static func _derringer(k: MeshKit) -> Vector3:
	var y := 0.022
	for s in [0.0, 1.0]:
		_barrel(k, "gun_blued", Vector3(0, y - s * 0.0112, -0.012), 0.076, 0.0058, 0.0056, 0.0042, 16)
	_box(k, "gun_blued", Vector3(0, y - 0.0056, -0.05), Vector3(0.0035, 0.014, 0.076))
	_box(k, "gun_blued", Vector3(0, y + 0.0062, -0.05), Vector3(0.003, 0.0016, 0.07)) # rib
	_block(k, "gun_case", Vector3(0, y - 0.005, 0.002), Vector3(0.016, 0.03, 0.028))
	_pin(k, "gun_blued", Vector3(-0.0085, y - 0.014, -0.008), 0.003, 0.017)
	_pin(k, "gun_blued", Vector3(0.0035, y + 0.006, -0.004), 0.0035, 0.006) # barrel latch
	_hammer(k, "gun_blued", Vector3(0, y + 0.006, 0.01), 0.018)
	# Spur trigger: a blade hanging free under the frame, no guard.
	_strap(k, "gun_blued", [Vector3(0, y - 0.018, -0.002), Vector3(0, y - 0.03, 0.0), Vector3(0, y - 0.036, 0.004)], 0.0045, 0.003)
	_box(k, "gun_case", Vector3(0, y - 0.022, 0.0), Vector3(0.007, 0.01, 0.01))
	var pts := [Vector3(0, y - 0.006, 0.012), Vector3(0, y - 0.02, 0.022), Vector3(0, y - 0.04, 0.032), Vector3(0, y - 0.056, 0.036), Vector3(0, y - 0.06, 0.03)]
	GunLook._loft(k, "gun_rosewood_y", pts, [0.0105, 0.011, 0.012, 0.0125, 0.009], [0.012, 0.0115, 0.011, 0.012, 0.009], Vector3.FORWARD, 14)
	GunLook._loft(k, "gun_case", [pts[0] + Vector3(0, 0, 0.012), pts[2] + Vector3(0, 0, 0.012), pts[3] + Vector3(0, 0, 0.012)], [0.004, 0.004, 0.004], [0.002, 0.002, 0.002], Vector3.FORWARD, 8)
	_pin(k, "gun_brass", Vector3(-0.0125, y - 0.034, 0.03), 0.0025, 0.025)
	return Vector3(0, y - 0.034, 0.028)

## A Webley-pattern signal pistol: a wide brass-framed break-open barrel, walnut grip
## with a lanyard ring, no sights.
static func _flare_gun(k: MeshKit) -> Vector3:
	var y := 0.032
	_barrel(k, "gun_blued", Vector3(0, y, -0.03), 0.16, 0.0185, 0.0185, 0.0145, 22)
	_tube(k, "gun_blued", Vector3(0, y, -0.18), 0.012, 0.0195, 0.0195, 22)
	_box(k, "gun_brass", Vector3(0, y - 0.008, -0.004), Vector3(0.026, 0.05, 0.06))
	_box(k, "gun_brass", Vector3(0, y - 0.022, -0.06), Vector3(0.018, 0.012, 0.06))
	_pin(k, "gun_blued", Vector3(-0.014, y - 0.022, -0.075), 0.004, 0.028)
	_box(k, "gun_brass", Vector3(0, y + 0.02, 0.018), Vector3(0.014, 0.008, 0.02))
	_hammer(k, "gun_blued", Vector3(0, y + 0.012, 0.024), 0.022)
	_guard(k, "gun_brass", y - 0.033, -0.04, 0.01, 0.022, 0.009)
	_trigger(k, "gun_blued", Vector3(0, y - 0.033, -0.016), 0.016)
	var g := _grip(k, "gun_walnut_y", Vector3(0, y - 0.022, 0.018), 0.18, 0.09, 0.016, 0.021, "gun_brass", -0.1)
	GunLook._rod(k, "gun_worn", [Vector3(0, y - 0.114, 0.038), Vector3(0, y - 0.124, 0.036), Vector3(0, y - 0.127, 0.026), Vector3(0, y - 0.118, 0.022), Vector3(0, y - 0.114, 0.028)], 0.0018, 6)
	for d in [0.03, 0.065]:
		_pin(k, "gun_brass", Vector3(-0.0175, y - 0.022 - d, 0.018 + d * 0.18), 0.003, 0.035)
	return g

## A band-powered speargun: a teak beam, a stainless shaft with a barbed tip, two rubber
## bands looped from the muzzle to notches in the shaft, a polymer grip and a line reel.
static func _harpoon_gun(k: MeshKit) -> Vector3:
	var y := 0.03
	_stock(k, "gun_teak", [0.12, 0.05, -0.2, -0.6, -0.78],
		[y + 0.006, y + 0.014, y + 0.014, y + 0.012, y + 0.012], [y - 0.016, y - 0.026, y - 0.036, y - 0.032, y - 0.026],
		[0.015, 0.0165, 0.0175, 0.0165, 0.0155])
	_box(k, "gun_bore", Vector3(0, y + 0.0125, -0.33), Vector3(0.005, 0.002, 0.88)) # shaft groove
	# Muzzle: a polymer head with the band holes.
	_block(k, "gun_polymer", Vector3(0, y - 0.004, -0.79), Vector3(0.06, 0.04, 0.034))
	# Shaft and barbed tip, well past the muzzle.
	_tube(k, "gun_bright", Vector3(0, y + 0.019, 0.06), 1.0, 0.0045, 0.0045, 10)
	k.cylinder("gun_bright", GunLook._z(Vector3(0, y + 0.019, -0.94)), 0.006, 0.0, 0.05, 8)
	for s in [-1.0, 1.0]:
		_strap(k, "gun_bright", [Vector3(0, y + 0.019, -0.955), Vector3(0, y + 0.019 + s * 0.016, -0.915)], 0.005, 0.0022)
	# Bands: thick rubber from each side of the muzzle back to a wishbone in a shaft notch.
	for n in 2:
		var bz := -0.36 - n * 0.06
		for s in [-1.0, 1.0]:
			GunLook._rod(k, "gun_rubber", [Vector3(s * 0.026, y, -0.785), Vector3(s * 0.02, y + 0.01, (bz - 0.785) * 0.5), Vector3(s * 0.005, y + 0.021, bz)], 0.0075 - n * 0.0007, 10)
		GunLook._rod(k, "gun_bright", [Vector3(-0.005, y + 0.018, bz), Vector3(0, y + 0.022, bz - 0.002), Vector3(0.005, y + 0.018, bz)], 0.0016, 6)
	# Trigger mechanism and grip, reel under the beam, line running to the shaft.
	_box(k, "gun_polymer", Vector3(0, y - 0.018, 0.06), Vector3(0.02, 0.02, 0.1))
	_guard(k, "gun_polymer", y - 0.026, 0.0, 0.05, 0.026, 0.009)
	_trigger(k, "gun_bright", Vector3(0, y - 0.028, 0.02), 0.018)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.026, 0.06), 0.3, 0.1, 0.0145, 0.019)
	k.cylinder("gun_polymer", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.012, y - 0.04, -0.2)), 0.03, 0.03, 0.024, 22)
	k.cylinder("gun_bright", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.0125, y - 0.04, -0.2)), 0.0045, 0.0045, 0.025, 10)
	k.cylinder("gun_string", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.009, y - 0.04, -0.2)), 0.022, 0.022, 0.018, 22)
	GunLook._rod(k, "gun_string", [Vector3(0, y - 0.012, -0.2), Vector3(0, y + 0.0, -0.5), Vector3(0, y + 0.014, -0.9)], 0.001, 4)
	_fore = Vector3(0, y - 0.01, -0.3)
	return g

## A Gatling for one man: six brass-jacketed barrels round a central rod between two
## brass plates, a case of steel at the breech with a gravity hopper on top, the crank on
## the right, a walnut pistol grip under the breech and a carrying handle.
static func _gatling(k: MeshKit) -> Vector3:
	var y := 0.06
	_tube(k, "gun_brass", Vector3(0, y, 0.13), 0.17, 0.05, 0.05, 28) # breech casing
	_tube(k, "gun_blued", Vector3(0, y, 0.14), 0.012, 0.042, 0.042, 24) # cascabel plate
	k.sphere("gun_brass", Transform3D(Basis(), Vector3(0, y, 0.16)), 0.016, 6, 12)
	for c in 6:
		var a := TAU * c / 6.0
		var off := Vector3(cos(a) * 0.022, sin(a) * 0.022, 0)
		_barrel(k, "gun_blued", Vector3(0, y, -0.04) + off, 0.5, 0.0085, 0.0075, 0.0045, 12)
	_tube(k, "gun_blued", Vector3(0, y, -0.04), 0.5, 0.008, 0.008, 10) # centre rod
	for z in [-0.06, -0.25, -0.52]:
		_tube(k, "gun_brass", Vector3(0, y, z), 0.014, 0.034, 0.034, 24)
	# The hopper: a sheet-steel box standing on the casing.
	_block(k, "gun_blued", Vector3(0, y + 0.075, 0.05), Vector3(0.03, 0.06, 0.06))
	_block(k, "gun_brass", Vector3(0, y + 0.107, 0.05), Vector3(0.034, 0.006, 0.064))
	_box(k, "gun_bore", Vector3(0.0151, y + 0.075, 0.05), Vector3(0.001, 0.04, 0.03)) # its window
	# Crank on the right: arm and wooden handle.
	_pin(k, "gun_blued", Vector3(0.05, y, 0.06), 0.008, 0.018)
	_box(k, "gun_blued", Vector3(0.07, y - 0.025, 0.06), Vector3(0.006, 0.06, 0.012))
	k.cylinder("gun_walnut_x", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.072, y - 0.052, 0.06)), 0.009, 0.009, 0.045, 10)
	# Grip and carrying handle.
	_box(k, "gun_blued", Vector3(0, y - 0.052, 0.08), Vector3(0.02, 0.02, 0.06))
	_guard(k, "gun_blued", y - 0.062, 0.05, 0.1, 0.024, 0.009)
	_trigger(k, "gun_blued", Vector3(0, y - 0.062, 0.074), 0.017)
	var g := _grip(k, "gun_oak_y_chk", Vector3(0, y - 0.062, 0.11), 0.35, 0.1, 0.0145, 0.019, "gun_brass")
	_strap(k, "gun_blued", [Vector3(0, y + 0.04, -0.12), Vector3(0, y + 0.075, -0.1), Vector3(0, y + 0.08, -0.03), Vector3(0, y + 0.05, -0.0)], 0.014, 0.006)
	_fore = Vector3(0, y + 0.075, -0.07)
	return g

## A .470 double rifle: heavy side-by-side barrels on a raised rib with express sights,
## a bright engraved sidelock action, a walnut stock with a cheek piece and pistol grip
## cap, a recoil pad, a barrel-band swivel.
static func _elephant_gun(k: MeshKit) -> Vector3:
	var y := 0.032
	var len := 0.61
	for s in [-1.0, 1.0]:
		_barrel(k, "gun_blued", Vector3(s * 0.0125, y, -0.06), len, 0.0145, 0.0122, 0.0058, 20)
	_box(k, "gun_blued", Vector3(0, y + 0.0135, -0.06 - len * 0.5), Vector3(0.01, 0.007, len))
	_box(k, "gun_blued", Vector3(0, y - 0.01, -0.06 - len * 0.5), Vector3(0.01, 0.008, len))
	_tube(k, "gun_blued", Vector3(0, y - 0.003, -0.5), 0.014, 0.0285, 0.0285, 20)
	_swivel(k, "gun_blued", Vector3(0, y - 0.032, -0.493))
	# Express sights: a fixed standard and two folding leaves, an ivory bead up front.
	_box(k, "gun_blued", Vector3(0, y + 0.019, -0.12), Vector3(0.012, 0.004, 0.04))
	_rear_sight(k, "gun_blued", Vector3(0, y + 0.021, -0.11), 0.016, 0.007)
	_box(k, "gun_blued", Vector3(0, y + 0.023, -0.128), Vector3(0.014, 0.003, 0.002), -1.2)
	_box(k, "gun_blued", Vector3(0, y + 0.019, -0.06 - len + 0.02), Vector3(0.008, 0.008, 0.022))
	k.sphere("gun_bone", Transform3D(Basis(), Vector3(0, y + 0.026, -0.06 - len + 0.016)), 0.0026, 5, 8)
	# Action body, the fences, and the sidelock plates with their hammers inside.
	_block(k, "gun_bright", Vector3(0, y - 0.006, -0.025), Vector3(0.05, 0.046, 0.075))
	for s in [-1.0, 1.0]:
		k.sphere("gun_bright", Transform3D(Basis.from_scale(Vector3(1, 1, 0.6)), Vector3(s * 0.0125, y, -0.058)), 0.017, 7, 14)
		GunLook._loft(k, "gun_bright", [Vector3(s * 0.0185, y - 0.008, -0.05), Vector3(s * 0.0185, y - 0.006, 0.0), Vector3(s * 0.0185, y - 0.01, 0.05)],
			[0.014, 0.017, 0.009], [0.006, 0.006, 0.006], Vector3.RIGHT, 12)
		_pin(k, "gun_gold", Vector3(s * 0.025 - 0.001, y - 0.006, -0.01), 0.0028, 0.002)
		_pin(k, "gun_bright", Vector3(s * 0.025 - 0.001, y - 0.004, 0.02), 0.0024, 0.002)
	_box(k, "gun_bright", Vector3(0, y + 0.019, 0.022), Vector3(0.024, 0.006, 0.03))
	_box(k, "gun_blued", Vector3(0.009, y + 0.024, 0.02), Vector3(0.028, 0.004, 0.012))
	# Splinter fore-end and the stock.
	_stock(k, "gun_burl", [-0.07, -0.13, -0.26, -0.29],
		[y - 0.01, y - 0.01, y - 0.01, y - 0.012], [y - 0.034, y - 0.034, y - 0.032, y - 0.024], [0.019, 0.019, 0.018, 0.014])
	_stock(k, "gun_burl", [0.01, 0.05, 0.09, 0.2, 0.33, 0.35],
		[y + 0.018, y + 0.014, y + 0.008, y - 0.002, y - 0.014, y - 0.016], [y - 0.03, y - 0.075, y - 0.07, y - 0.1, y - 0.13, y - 0.132],
		[0.023, 0.0155, 0.017, 0.02, 0.0205, 0.0205])
	# Cheek piece on the left of the butt.
	GunLook._loft(k, "gun_burl", [Vector3(-0.012, y - 0.03, 0.16), Vector3(-0.014, y - 0.03, 0.22), Vector3(-0.013, y - 0.034, 0.3)],
		[0.012, 0.014, 0.012], [0.02, 0.024, 0.022], Vector3.UP, 14)
	_butt(k, "gun_rubber", 0.35, y - 0.016, y - 0.134, 0.0208, 0.022)
	_guard(k, "gun_blued", y - 0.028, -0.03, 0.035, 0.026, 0.01)
	_trigger(k, "gun_bright", Vector3(0, y - 0.028, -0.012), 0.017)
	_trigger(k, "gun_bright", Vector3(0, y - 0.028, 0.008), 0.017)
	_swivel(k, "gun_blued", Vector3(0, y - 0.125, 0.26))
	_checkering(k, "gun_burl_chk", Vector3(0, y - 0.026, 0.065), 0.0158, 0.055, 0.034, 0.3)
	_checkering(k, "gun_burl_chk", Vector3(0, y - 0.022, -0.18), 0.019, 0.09, 0.016)
	_fore = Vector3(0, y - 0.022, -0.18)
	return Vector3(0, y - 0.04, 0.07)

# --- Modern firearms -----------------------------------------------------------------

## A polymer-framed pistol with a smart sight: a steel slide with cocking serrations and
## a mini reflex optic, an accessory rail with a sensor block under the dust cover, a
## textured grip, a magazine base plate.
static func _smart_pistol(k: MeshKit) -> Vector3:
	var y := 0.03
	_block(k, "gun_parker", Vector3(0, y + 0.004, -0.06), Vector3(0.024, 0.028, 0.19))
	_bore(k, Vector3(0, y + 0.002, -0.155), 0.0052)
	for n in 7:
		for s in [-1.0, 1.0]:
			_box(k, "gun_bore", Vector3(s * 0.0121, y + 0.006, 0.006 - n * 0.0055), Vector3(0.001, 0.016, 0.002))
	_box(k, "gun_bore", Vector3(0.0121, y + 0.008, -0.06), Vector3(0.001, 0.012, 0.036)) # ejection port
	# Frame: dust cover with rail, trigger guard, beavertail.
	_block(k, "gun_polymer", Vector3(0, y - 0.017, -0.055), Vector3(0.022, 0.016, 0.17))
	_rail(k, "gun_polymer", y - 0.026, -0.08, -0.13, 0.02)
	_guard(k, "gun_polymer", y - 0.024, -0.05, 0.0, 0.026, 0.01)
	_trigger(k, "gun_parker", Vector3(0, y - 0.024, -0.026), 0.018)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.022, 0.0), 0.3, 0.1, 0.0145, 0.021, "gun_parker")
	_grooves(k, "gun_polymer", Vector3(0, y - 0.022, 0.0), 0.3, 0.1, 0.0145, 0.021)
	_box(k, "gun_polymer", Vector3(0, y - 0.01, 0.028), Vector3(0.02, 0.006, 0.026), 0.2)
	# Smart optic and sensor: dark lenses, nothing lit.
	_red_dot(k, Vector3(0, y + 0.018, -0.0))
	_block(k, "gun_alloy", Vector3(0, y - 0.036, -0.105), Vector3(0.026, 0.02, 0.05))
	k.cylinder("gun_glass", GunLook._z(Vector3(0, y - 0.036, -0.13)), 0.007, 0.007, 0.002, 16)
	_front_sight(k, "gun_parker", Vector3(0, y + 0.018, -0.145), 0.004)
	return g

## A self-loading combat shotgun: a squared receiver, a drum magazine, a straight-line
## stock with a rubber pad, a carry handle with ghost-ring sights, a vented barrel shroud.
static func _auto_shotgun(k: MeshKit) -> Vector3:
	var y := 0.04
	_block(k, "gun_parker", Vector3(0, y - 0.004, -0.03), Vector3(0.034, 0.07, 0.3))
	_block(k, "gun_polymer", Vector3(0, y + 0.0, 0.2), Vector3(0.03, 0.06, 0.18))
	_butt(k, "gun_rubber", 0.29, y + 0.03, y - 0.03, 0.016, 0.02)
	# Barrel in a vented shroud, a muzzle brake.
	_barrel(k, "gun_parker", Vector3(0, y + 0.006, -0.18), 0.26, 0.012, 0.012, 0.0095, 18)
	_tube(k, "gun_polymer", Vector3(0, y + 0.006, -0.18), 0.17, 0.02, 0.02, 12)
	for n in 6:
		_box(k, "gun_bore", Vector3(0.0, y + 0.026, -0.2 - n * 0.025), Vector3(0.012, 0.002, 0.012))
	_tube(k, "gun_parker", Vector3(0, y + 0.006, -0.42), 0.025, 0.016, 0.016, 14)
	# Carry handle with its ghost ring and front post.
	_strap(k, "gun_parker", [Vector3(0, y + 0.03, 0.08), Vector3(0, y + 0.07, 0.06), Vector3(0, y + 0.07, -0.12), Vector3(0, y + 0.03, -0.14)], 0.014, 0.006)
	GunLook._rod(k, "gun_parker", [Vector3(-0.008, y + 0.075, 0.05), Vector3(0, y + 0.085, 0.05), Vector3(0.008, y + 0.075, 0.05), Vector3(-0.008, y + 0.075, 0.05)], 0.0022, 6)
	_front_sight(k, "gun_parker", Vector3(0, y + 0.026, -0.4), 0.014)
	# Drum magazine across the gun ahead of the grip, and the grip.
	k.cylinder("gun_polymer", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.022, y - 0.09, -0.07)), 0.065, 0.065, 0.044, 28)
	k.cylinder("gun_parker", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.024, y - 0.09, -0.07)), 0.02, 0.02, 0.048, 16)
	_block(k, "gun_polymer", Vector3(0, y - 0.034, -0.07), Vector3(0.028, 0.02, 0.06))
	_guard(k, "gun_polymer", y - 0.038, 0.0, 0.05, 0.028, 0.012)
	_trigger(k, "gun_parker", Vector3(0, y - 0.038, 0.022), 0.018)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.038, 0.06), 0.25, 0.1, 0.015, 0.022)
	_fore = Vector3(0, y - 0.01, -0.2)
	return g

## A short assault carbine: an anodised upper with a flat-top rail and a reflex sight, a
## lower with a curved 30-round magazine, a free-float rail handguard, a fixed front
## post, a birdcage flash hider, a buffer tube and adjustable stock.
static func _carbine(k: MeshKit) -> Vector3:
	var y := 0.032
	_block(k, "gun_alloy", Vector3(0, y + 0.008, -0.005), Vector3(0.025, 0.03, 0.19))
	_rail(k, "gun_alloy", y + 0.028, 0.085, -0.1)
	_box(k, "gun_bore", Vector3(0.0128, y + 0.006, -0.0), Vector3(0.001, 0.012, 0.05)) # ejection port
	_box(k, "gun_alloy", Vector3(0.0135, y + 0.006, 0.0), Vector3(0.002, 0.014, 0.055)) # dust cover
	k.cylinder("gun_alloy", GunLook._z(Vector3(0.014, y + 0.016, 0.06)), 0.005, 0.005, 0.02, 10) # forward assist
	_box(k, "gun_alloy", Vector3(0, y + 0.024, 0.094), Vector3(0.022, 0.006, 0.016)) # charging handle
	_block(k, "gun_alloy", Vector3(0, y - 0.016, 0.005), Vector3(0.022, 0.024, 0.16))
	_block(k, "gun_alloy", Vector3(0, y - 0.035, -0.04), Vector3(0.026, 0.026, 0.06)) # mag well
	_pin(k, "gun_alloy", Vector3(0.011, y - 0.02, -0.06), 0.004, 0.003) # mag release
	_box(k, "gun_alloy", Vector3(-0.0115, y - 0.006, 0.03), Vector3(0.002, 0.004, 0.014), 0.4) # selector
	_mag(k, "gun_alloy", Vector3(0, y - 0.045, -0.04), 0.17, 0.058, 0.022, 0.25, "gun_polymer")
	# Handguard: a round tube with rails at twelve o'clock and sides.
	_tube(k, "gun_alloy", Vector3(0, y + 0.006, -0.1), 0.24, 0.02, 0.02, 12)
	_rail(k, "gun_alloy", y + 0.028, -0.1, -0.34)
	for n in 8:
		for s in [-1.0, 1.0]:
			_box(k, "gun_bore", Vector3(s * 0.0185, y + 0.006, -0.13 - n * 0.026), Vector3(0.004, 0.008, 0.012))
	_barrel(k, "gun_parker", Vector3(0, y + 0.006, -0.34), 0.12, 0.0095, 0.0095, 0.0029, 14)
	# Front post on its A-frame.
	_box(k, "gun_parker", Vector3(0, y + 0.02, -0.375), Vector3(0.012, 0.03, 0.014))
	_box(k, "gun_parker", Vector3(0, y + 0.04, -0.375), Vector3(0.003, 0.012, 0.003))
	_tube(k, "gun_parker", Vector3(0, y + 0.006, -0.36), 0.028, 0.012, 0.012, 14)
	# Flash hider: prongs round the muzzle.
	_tube(k, "gun_parker", Vector3(0, y + 0.006, -0.46), 0.012, 0.011, 0.011, 14)
	for n in 5:
		var a := TAU * n / 5.0
		_tube(k, "gun_parker", Vector3(cos(a) * 0.0085, y + 0.006 + sin(a) * 0.0085, -0.472), 0.04, 0.003, 0.003, 6)
	_bore(k, Vector3(0, y + 0.006, -0.472), 0.007)
	_red_dot(k, Vector3(0, y + 0.03, 0.02), true)
	# Grip, guard, buffer tube and stock.
	_guard(k, "gun_alloy", y - 0.028, -0.005, 0.045, 0.02, 0.012)
	_trigger(k, "gun_parker", Vector3(0, y - 0.028, 0.016), 0.016)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.028, 0.06), 0.4, 0.1, 0.0145, 0.02)
	_tube(k, "gun_alloy", Vector3(0, y + 0.004, 0.27), 0.19, 0.015, 0.015, 16)
	_block(k, "gun_polymer", Vector3(0, y - 0.012, 0.25), Vector3(0.026, 0.05, 0.12))
	_block(k, "gun_polymer", Vector3(0, y - 0.03, 0.29), Vector3(0.028, 0.11, 0.04))
	_butt(k, "gun_rubber", 0.31, y + 0.024, y - 0.084, 0.0142, 0.01)
	_fore = Vector3(0, y - 0.01, -0.22)
	return g

## A light machine gun of six rotating barrels: barrel cluster in clamps, a drive motor
## housing at the back, a flexible feed chute from the box underneath, a pistol grip,
## a top carrying handle and a front grip.
static func _minigun(k: MeshKit) -> Vector3:
	var y := 0.05
	for c in 6:
		var a := TAU * c / 6.0
		var off := Vector3(cos(a) * 0.024, sin(a) * 0.024, 0)
		_barrel(k, "gun_parker", Vector3(0, y, -0.08) + off, 0.56, 0.0085, 0.0075, 0.0038, 12)
	for z in [-0.1, -0.35, -0.6]:
		_tube(k, "gun_parker", Vector3(0, y, z), 0.016, 0.036, 0.036, 24)
	_tube(k, "gun_alloy", Vector3(0, y, 0.18), 0.26, 0.05, 0.05, 26)
	_tube(k, "gun_parker", Vector3(0, y, -0.0), 0.06, 0.05, 0.04, 26)
	_tube(k, "gun_alloy", Vector3(0.04, y + 0.03, 0.17), 0.12, 0.022, 0.022, 16) # drive motor
	# Feed: an ammunition box under the housing and a flexible chute into the left side.
	_block(k, "gun_od", Vector3(0, y - 0.12, 0.08), Vector3(0.09, 0.1, 0.16))
	_block(k, "gun_parker", Vector3(0, y - 0.069, 0.08), Vector3(0.094, 0.008, 0.164))
	var prev := Vector3(-0.04, y - 0.07, 0.04)
	for n in range(1, 7):
		var f := n / 6.0
		var p := Vector3(-0.05 - 0.02 * sin(f * PI), y - 0.07 + 0.08 * f, 0.04 - 0.02 * f)
		_block(k, "gun_parker", (prev + p) * 0.5, Vector3(0.02, 0.016, 0.05))
		prev = p
	_guard(k, "gun_parker", y - 0.05, 0.13, 0.18, 0.024, 0.01)
	_trigger(k, "gun_parker", Vector3(0, y - 0.05, 0.154), 0.016)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.05, 0.2), 0.3, 0.1, 0.015, 0.021)
	_strap(k, "gun_parker", [Vector3(0, y + 0.05, 0.12), Vector3(0, y + 0.1, 0.1), Vector3(0, y + 0.1, -0.02), Vector3(0, y + 0.05, -0.04)], 0.018, 0.008)
	GunLook._loft(k, "gun_polymer", [Vector3(0, y - 0.04, -0.12), Vector3(0, y - 0.13, -0.11)], [0.014, 0.015], [0.016, 0.017], Vector3.FORWARD, 14)
	_fore = Vector3(0, y - 0.09, -0.115)
	return g

## A flamethrower wand with its own fuel bottle: a steel tube with a fuel valve, a rear
## grip with the trigger, a nozzle with the igniter cartridge beside it, a pressure
## gauge, and a hose from the bottle slung underneath.
static func _flamethrower(k: MeshKit) -> Vector3:
	var y := 0.05
	_tube(k, "gun_worn", Vector3(0, y, 0.12), 0.62, 0.016, 0.016, 16)
	_tube(k, "gun_worn", Vector3(0, y, -0.5), 0.07, 0.022, 0.03, 18)
	_tube(k, "gun_bore", Vector3(0, y, -0.56), 0.012, 0.016, 0.016, 14)
	_barrel(k, "gun_bright", Vector3(0, y, -0.555), 0.03, 0.013, 0.012, 0.005, 14)
	k.cylinder("gun_worn", GunLook._z(Vector3(0, y - 0.035, -0.5)), 0.012, 0.012, 0.06, 12) # igniter cylinder
	_box(k, "gun_worn", Vector3(0, y - 0.02, -0.52), Vector3(0.01, 0.03, 0.012))
	# Fuel bottle under the wand, its straps and hose.
	_tube(k, "gun_od", Vector3(0, y - 0.11, 0.2), 0.36, 0.055, 0.055, 26)
	k.sphere("gun_od", Transform3D(Basis.from_scale(Vector3(1, 1, 0.5)), Vector3(0, y - 0.11, -0.16)), 0.055, 8, 26)
	k.sphere("gun_od", Transform3D(Basis.from_scale(Vector3(1, 1, 0.5)), Vector3(0, y - 0.11, 0.2)), 0.055, 8, 26)
	for z in [0.12, -0.08]:
		_tube(k, "gun_leather", Vector3(0, y - 0.11, z + 0.012), 0.024, 0.0565, 0.0565, 26)
		_box(k, "gun_worn", Vector3(0, y - 0.04, z), Vector3(0.012, 0.03, 0.02))
	_tube(k, "gun_bright", Vector3(0, y - 0.11, 0.26), 0.05, 0.012, 0.012, 12) # valve
	k.cylinder("gun_bright", Transform3D(Basis(), Vector3(0, y - 0.11, 0.255)), 0.004, 0.004, 0.08, 8)
	k.cylinder("gun_red", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, y - 0.03, 0.255)), 0.016, 0.016, 0.006, 16)
	GunLook._rod(k, "gun_rubber", [Vector3(0, y - 0.11, 0.27), Vector3(0.03, y - 0.13, 0.32), Vector3(0.05, y - 0.06, 0.34),
		Vector3(0.035, y + 0.0, 0.2), Vector3(0.012, y, 0.13)], 0.009, 10)
	# Pressure gauge on the wand.
	k.cylinder("gun_bright", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.016, y + 0.016, 0.06)), 0.016, 0.016, 0.01, 18)
	k.cylinder("gun_window", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.026, y + 0.016, 0.06)), 0.013, 0.013, 0.001, 18)
	# Grips: a valve grip ahead, a pistol grip with the trigger behind.
	GunLook._loft(k, "gun_beech_y", [Vector3(0, y - 0.016, -0.25), Vector3(0, y - 0.11, -0.24)], [0.014, 0.015], [0.016, 0.017], Vector3.FORWARD, 14)
	_guard(k, "gun_worn", y - 0.016, 0.04, 0.09, 0.024, 0.01)
	_trigger(k, "gun_worn", Vector3(0, y - 0.016, 0.064), 0.017)
	var g := _grip(k, "gun_beech_y_chk", Vector3(0, y - 0.016, 0.1), 0.3, 0.1, 0.0145, 0.019)
	_fore = Vector3(0, y - 0.07, -0.245)
	return g

## An RPG-7: a steel tube with wooden heat guards, a flared venturi at the back, two
## grips, an optical sight on the left and the round loaded at the muzzle.
static func _rocket_launcher(k: MeshKit) -> Vector3:
	var y := 0.07
	_tube(k, "gun_parker", Vector3(0, y, 0.38), 0.86, 0.021, 0.021, 20)
	_tube(k, "gun_parker", Vector3(0, y, 0.38), 0.03, 0.026, 0.026, 20)
	k.cylinder("gun_parker", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, y, 0.39)), 0.026, 0.05, 0.18, 22, false)
	_tube(k, "gun_parker", Vector3(0, y, 0.58), 0.012, 0.052, 0.05, 22)
	_tube(k, "gun_bore", Vector3(0, y, 0.582), 0.003, 0.046, 0.046, 22)
	# Heat guards: two wooden sleeves, with bands.
	_tube(k, "gun_beech", Vector3(0, y, 0.2), 0.27, 0.031, 0.031, 20)
	for z in [0.2, -0.06]:
		_tube(k, "gun_parker", Vector3(0, y, z + 0.006), 0.012, 0.033, 0.033, 20)
	# The round: warhead body, ogive, nose fuze, and the stabiliser tube into the muzzle.
	_tube(k, "gun_od", Vector3(0, y, -0.48), 0.04, 0.022, 0.03, 18)
	_tube(k, "gun_od", Vector3(0, y, -0.52), 0.14, 0.042, 0.042, 26)
	k.cylinder("gun_od", GunLook._z(Vector3(0, y, -0.66)), 0.042, 0.012, 0.09, 26)
	k.cylinder("gun_bright", GunLook._z(Vector3(0, y, -0.75)), 0.012, 0.004, 0.025, 12)
	_tube(k, "gun_tan", Vector3(0, y, -0.58), 0.008, 0.0425, 0.0425, 26)
	# Grips and trigger, the sight bracket on the left.
	_box(k, "gun_parker", Vector3(0, y - 0.03, 0.0), Vector3(0.016, 0.02, 0.07))
	_guard(k, "gun_parker", y - 0.04, -0.03, 0.02, 0.024, 0.01)
	_trigger(k, "gun_parker", Vector3(0, y - 0.04, -0.006), 0.016)
	var g := _grip(k, "gun_beech_y_chk", Vector3(0, y - 0.04, 0.03), 0.3, 0.1, 0.0145, 0.019)
	GunLook._loft(k, "gun_beech_y", [Vector3(0, y - 0.025, 0.16), Vector3(0, y - 0.12, 0.17)], [0.014, 0.015], [0.016, 0.017], Vector3.FORWARD, 14)
	_box(k, "gun_parker", Vector3(-0.035, y + 0.018, 0.02), Vector3(0.03, 0.01, 0.04))
	_block(k, "gun_parker", Vector3(-0.05, y + 0.035, 0.04), Vector3(0.024, 0.034, 0.1))
	k.cylinder("gun_rubber", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(-0.05, y + 0.035, 0.09)), 0.014, 0.016, 0.03, 16)
	k.cylinder("gun_glass", GunLook._z(Vector3(-0.05, y + 0.035, -0.009)), 0.011, 0.011, 0.002, 14)
	_fore = Vector3(0, y - 0.07, 0.165)
	return g

## A break-open 40 mm launcher (M79 pattern): a fat, short parkerised barrel that
## dominates the gun, a flat-sided receiver with its latch, a tall ladder sight standing
## over the barrel, a short walnut fore-end and a walnut butt with a thick rubber pad.
static func _grenade_launcher(k: MeshKit) -> Vector3:
	var y := 0.045
	_barrel(k, "gun_parker", Vector3(0, y, -0.05), 0.33, 0.031, 0.031, 0.021, 28)
	_tube(k, "gun_parker", Vector3(0, y, -0.05), 0.02, 0.033, 0.033, 28)
	_tube(k, "gun_parker", Vector3(0, y, -0.365), 0.015, 0.032, 0.032, 28)
	_block(k, "gun_parker", Vector3(0, y - 0.006, 0.0), Vector3(0.044, 0.07, 0.1))
	_box(k, "gun_parker", Vector3(0, y + 0.033, 0.03), Vector3(0.012, 0.008, 0.036)) # latch
	_pin(k, "gun_parker", Vector3(-0.023, y - 0.026, -0.04), 0.006, 0.046) # hinge
	_box(k, "gun_parker", Vector3(0, y + 0.036, -0.36), Vector3(0.004, 0.012, 0.012))
	# Ladder sight: a tall frame with a slider, standing on its base over the barrel.
	_box(k, "gun_parker", Vector3(0, y + 0.034, -0.11), Vector3(0.034, 0.006, 0.026))
	for sd in [-1.0, 1.0]:
		_box(k, "gun_parker", Vector3(sd * 0.014, y + 0.07, -0.11), Vector3(0.004, 0.07, 0.006), 0.08)
	for n in 4:
		_box(k, "gun_parker", Vector3(0, y + 0.05 + n * 0.016, -0.11 + n * 0.0013), Vector3(0.028, 0.002, 0.004), 0.08)
	_box(k, "gun_parker", Vector3(0, y + 0.08, -0.108), Vector3(0.032, 0.007, 0.009), 0.08)
	# Fore-end under the breech half, the stock.
	_stock(k, "gun_oak", [-0.07, -0.12, -0.2, -0.22],
		[y - 0.026, y - 0.026, y - 0.026, y - 0.028], [y - 0.05, y - 0.052, y - 0.05, y - 0.043], [0.022, 0.023, 0.022, 0.018])
	_stock(k, "gun_oak", [0.045, 0.08, 0.12, 0.2, 0.29, 0.3],
		[y + 0.014, y + 0.008, y + 0.0, y - 0.01, y - 0.02, y - 0.022], [y - 0.04, y - 0.045, y - 0.07, y - 0.095, y - 0.12, y - 0.122],
		[0.021, 0.017, 0.018, 0.02, 0.021, 0.021])
	_butt(k, "gun_rubber", 0.3, y - 0.022, y - 0.124, 0.0215, 0.03)
	_guard(k, "gun_parker", y - 0.04, -0.02, 0.04, 0.028, 0.012)
	_trigger(k, "gun_parker", Vector3(0, y - 0.04, 0.01), 0.018)
	_swivel(k, "gun_parker", Vector3(0, y - 0.034, -0.17))
	_fore = Vector3(0, y - 0.04, -0.15)
	return Vector3(0, y - 0.05, 0.07)

# --- Human sci-fi (no glow on any of them) -------------------------------------------

## A laser pistol: a gunmetal frame under a sculpted shroud of grey ceramic with its
## panel seams, a cut-out window showing the copper heat-sink fins, a muzzle shroud with
## a recessed focusing lens, an energy cell seated in the base of the grip, and iron
## sights. The lens is dark glass: nothing lights up.
static func _laser_pistol(k: MeshKit) -> Vector3:
	var y := 0.03
	# Shroud: swells over the breech and tapers into the muzzle.
	GunLook._loft(k, "gun_ceramic", [Vector3(0, y + 0.004, 0.03), Vector3(0, y + 0.006, 0.0), Vector3(0, y + 0.006, -0.08), Vector3(0, y + 0.004, -0.15), Vector3(0, y + 0.003, -0.175)],
		[0.0125, 0.0135, 0.0135, 0.0118, 0.011], [0.013, 0.0145, 0.014, 0.0125, 0.0115], Vector3.UP, 18)
	_block(k, "gun_metal", Vector3(0, y - 0.014, -0.05), Vector3(0.022, 0.014, 0.15))
	# Panel seams and the heat-sink window on each side.
	for sd in [-1.0, 1.0]:
		_box(k, "gun_bore", Vector3(sd * 0.0136, y + 0.006, -0.03), Vector3(0.001, 0.02, 0.0015))
		_box(k, "gun_bore", Vector3(sd * 0.0128, y + 0.006, -0.125), Vector3(0.001, 0.018, 0.0015))
		_box(k, "gun_bore", Vector3(sd * 0.0133, y + 0.0, -0.078), Vector3(0.001, 0.012, 0.07))
		for n in 8:
			_box(k, "gun_copper", Vector3(sd * 0.0128, y + 0.0, -0.05 - n * 0.008), Vector3(0.002, 0.011, 0.0022))
		_box(k, "gun_metal", Vector3(sd * 0.0128, y - 0.012, 0.005), Vector3(0.002, 0.004, 0.01))
	# Muzzle: a metal shroud with a recessed lens.
	_tube(k, "gun_metal", Vector3(0, y + 0.004, -0.17), 0.026, 0.0125, 0.0135, 20)
	_tube(k, "gun_bore", Vector3(0, y + 0.004, -0.1945), 0.002, 0.0095, 0.0095, 18)
	k.cylinder("gun_glass", GunLook._z(Vector3(0, y + 0.004, -0.19)), 0.0085, 0.0085, 0.0015, 18)
	_front_sight(k, "gun_metal", Vector3(0, y + 0.017, -0.17), 0.005)
	_rear_sight(k, "gun_metal", Vector3(0, y + 0.019, 0.02), 0.014, 0.006)
	_guard(k, "gun_metal", y - 0.021, -0.06, -0.008, 0.026, 0.01)
	_trigger(k, "gun_metal", Vector3(0, y - 0.021, -0.034), 0.017)
	var g := _grip(k, "gun_metal", Vector3(0, y - 0.02, 0.0), 0.28, 0.076, 0.0125, 0.019)
	_grip_panels(k, "gun_rubber_stip", Vector3(0, y - 0.02, 0.0), 0.28, 0.076, 0.0125, 0.019)
	# The energy cell: a ribbed metal canister in the base of the grip.
	var end := Vector3(0, y - 0.02, 0.0) + Vector3(0, -1, 0.28).normalized() * 0.076
	GunLook._loft(k, "gun_metal", [end + Vector3(0, 0.004, -0.001), end + Vector3(0, -0.007, 0.002)], [0.0132, 0.0132], [0.0188, 0.0188], Vector3.FORWARD, 14)
	for n in 2:
		_box(k, "gun_bore", end + Vector3(0.0135, -0.0005 - n * 0.004, 0.001), Vector3(0.001, 0.0015, 0.03), 0.28)
	return g

## A plasma rifle (bullpup): a moulded body with the plasma canister seated behind the
## grip, a magnetic accelerator of copper coils showing through slots in the barrel
## shroud, vents at the muzzle, a carry rail with an optic, a canister gauge window.
static func _plasma_rifle(k: MeshKit) -> Vector3:
	var y := 0.04
	_block(k, "gun_od", Vector3(0, y, 0.05), Vector3(0.04, 0.07, 0.42))
	_block(k, "gun_polymer", Vector3(0, y - 0.044, 0.15), Vector3(0.036, 0.022, 0.2))
	_butt(k, "gun_rubber", 0.26, y + 0.034, y - 0.054, 0.019, 0.014)
	# Canister behind the grip, its gauge window and cap.
	k.cylinder("gun_metal", Transform3D(Basis(), Vector3(0, y - 0.11, 0.15)), 0.022, 0.022, 0.06, 20)
	k.cylinder("gun_window", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.0205, y - 0.085, 0.15)), 0.007, 0.007, 0.0025, 14)
	k.cylinder("gun_metal", Transform3D(Basis(), Vector3(0, y - 0.116, 0.15)), 0.024, 0.024, 0.008, 20)
	# Accelerator: copper coils in a slotted shroud.
	_tube(k, "gun_metal", Vector3(0, y + 0.004, -0.16), 0.32, 0.009, 0.009, 14)
	for n in 10:
		_tube(k, "gun_copper", Vector3(0, y + 0.004, -0.18 - n * 0.028), 0.018, 0.019, 0.019, 20)
	for n in 4:
		var a := TAU * n / 4.0 + PI * 0.25
		_box(k, "gun_od", Vector3(cos(a) * 0.024, y + 0.004 + sin(a) * 0.024, -0.32), Vector3(0.012, 0.012, 0.31))
	_tube(k, "gun_od", Vector3(0, y + 0.004, -0.16), 0.03, 0.027, 0.027, 20)
	_tube(k, "gun_od", Vector3(0, y + 0.004, -0.46), 0.04, 0.027, 0.024, 20)
	_tube(k, "gun_metal", Vector3(0, y + 0.004, -0.5), 0.015, 0.02, 0.02, 20)
	_bore(k, Vector3(0, y + 0.004, -0.515), 0.011)
	for s in [-1.0, 1.0]:
		for n in 3:
			_box(k, "gun_bore", Vector3(s * 0.0242, y + 0.004, -0.47 - n * 0.01), Vector3(0.001, 0.016, 0.005))
	# Rail, optic, grip ahead of the canister.
	_rail(k, "gun_metal", y + 0.04, 0.12, -0.12)
	_scope(k, y + 0.075, 0.08, -0.1, 0.014, 0.02, y + 0.04, [0.03, -0.05])
	_guard(k, "gun_polymer", y - 0.035, 0.0, 0.07, 0.03, 0.012)
	_trigger(k, "gun_metal", Vector3(0, y - 0.035, 0.024), 0.018)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.035, 0.08), 0.32, 0.1, 0.015, 0.021)
	_fore = Vector3(0, y - 0.03, -0.12)
	return g

## A gauss rifle: a run of copper drive coils in steel collars along twin rails, a
## capacitor bank under the receiver, a skeleton stock, a long scope.
static func _gauss_rifle(k: MeshKit) -> Vector3:
	var y := 0.04
	_block(k, "gun_metal", Vector3(0, y, 0.0), Vector3(0.036, 0.05, 0.22))
	for s in [-1.0, 1.0]:
		_block(k, "gun_metal", Vector3(s * 0.011, y + 0.004, -0.42), Vector3(0.008, 0.02, 0.62))
	_tube(k, "gun_window", Vector3(0, y + 0.004, -0.1), 0.62, 0.006, 0.006, 10)
	for n in 12:
		var z := -0.13 - n * 0.048
		_tube(k, "gun_copper", Vector3(0, y + 0.004, z), 0.03, 0.024, 0.024, 22)
		_tube(k, "gun_metal", Vector3(0, y + 0.004, z + 0.004), 0.004, 0.026, 0.026, 22)
		_tube(k, "gun_metal", Vector3(0, y + 0.004, z - 0.026), 0.004, 0.026, 0.026, 22)
	_tube(k, "gun_metal", Vector3(0, y + 0.004, -0.71), 0.03, 0.02, 0.022, 20)
	_bore(k, Vector3(0, y + 0.004, -0.74), 0.006)
	# Capacitors: three cans under the receiver, banded.
	for n in 3:
		_tube(k, "gun_metal", Vector3((n - 1) * 0.016, y - 0.045, 0.05), 0.15, 0.009, 0.009, 14)
		_tube(k, "gun_od", Vector3((n - 1) * 0.016, y - 0.045, 0.04), 0.13, 0.0095, 0.0095, 14)
	_scope(k, y + 0.06, 0.1, -0.16, 0.015, 0.024, y + 0.025, [0.06, -0.06])
	# Skeleton stock.
	_strap(k, "gun_metal", [Vector3(0, y + 0.01, 0.11), Vector3(0, y + 0.012, 0.36)], 0.012, 0.016)
	_strap(k, "gun_metal", [Vector3(0, y - 0.03, 0.15), Vector3(0, y - 0.08, 0.36)], 0.012, 0.016)
	_block(k, "gun_polymer", Vector3(0, y - 0.035, 0.37), Vector3(0.026, 0.12, 0.03))
	_butt(k, "gun_rubber", 0.385, y + 0.024, y - 0.094, 0.0132, 0.012)
	_guard(k, "gun_metal", y - 0.025, 0.04, 0.1, 0.026, 0.012)
	_trigger(k, "gun_metal", Vector3(0, y - 0.025, 0.066), 0.017)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.025, 0.11), 0.36, 0.1, 0.015, 0.021)
	_fore = Vector3(0, y - 0.03, -0.18)
	return g

## A rail sniper: two long conductor rails with a gap between, held in insulating yokes,
## a heavy receiver over a capacitor block, a big scope, a folded bipod, a skeleton stock
## with a cheek riser.
static func _sniper_rail(k: MeshKit) -> Vector3:
	var y := 0.04
	_block(k, "gun_alloy", Vector3(0, y, 0.0), Vector3(0.042, 0.062, 0.26))
	_block(k, "gun_metal", Vector3(0, y - 0.05, 0.02), Vector3(0.05, 0.04, 0.16))
	for s in [-1.0, 1.0]:
		_block(k, "gun_bright", Vector3(0, y + s * 0.012, -0.58), Vector3(0.022, 0.012, 0.92))
		_block(k, "gun_metal", Vector3(0, y + s * 0.019, -0.58), Vector3(0.026, 0.004, 0.92))
	for n in 7:
		var z := -0.17 - n * 0.13
		_block(k, "gun_polymer", Vector3(0, y, z), Vector3(0.034, 0.05, 0.022))
	_block(k, "gun_alloy", Vector3(0, y, -1.05), Vector3(0.04, 0.05, 0.03))
	_box(k, "gun_bore", Vector3(0, y, -1.066), Vector3(0.018, 0.012, 0.002))
	_rail(k, "gun_alloy", y + 0.034, 0.12, -0.12)
	_scope(k, y + 0.08, 0.14, -0.22, 0.017, 0.028, y + 0.034, [0.08, -0.08])
	_tube(k, "gun_alloy", Vector3(0, y + 0.08, -0.215), 0.09, 0.0295, 0.0295, 22) # sunshade
	_box(k, "gun_bore", Vector3(0, y, -0.58), Vector3(0.016, 0.009, 0.9)) # the gap between the rails
	# Bipod legs folded under the rails.
	_block(k, "gun_alloy", Vector3(0, y - 0.03, -0.32), Vector3(0.03, 0.016, 0.03))
	for s in [-1.0, 1.0]:
		_tube(k, "gun_alloy", Vector3(s * 0.012, y - 0.04, -0.32), 0.22, 0.006, 0.006, 10)
		k.sphere("gun_rubber", Transform3D(Basis(), Vector3(s * 0.012, y - 0.04, -0.545)), 0.008, 5, 10)
	# Stock with a cheek riser and a monopod.
	_strap(k, "gun_alloy", [Vector3(0, y + 0.015, 0.13), Vector3(0, y + 0.015, 0.42)], 0.014, 0.018)
	_strap(k, "gun_alloy", [Vector3(0, y - 0.04, 0.13), Vector3(0, y - 0.09, 0.42)], 0.014, 0.018)
	_block(k, "gun_polymer", Vector3(0, y + 0.03, 0.3), Vector3(0.024, 0.016, 0.14))
	_block(k, "gun_polymer", Vector3(0, y - 0.04, 0.43), Vector3(0.03, 0.14, 0.03))
	_butt(k, "gun_rubber", 0.445, y + 0.03, y - 0.11, 0.015, 0.014)
	k.cylinder("gun_alloy", Transform3D(Basis(), Vector3(0, y - 0.15, 0.38)), 0.005, 0.005, 0.06, 10)
	_guard(k, "gun_alloy", y - 0.031, 0.06, 0.12, 0.026, 0.012)
	_trigger(k, "gun_metal", Vector3(0, y - 0.031, 0.086), 0.017)
	var g := _grip(k, "gun_polymer_stip", Vector3(0, y - 0.031, 0.13), 0.36, 0.1, 0.015, 0.021)
	_fore = Vector3(0, y - 0.03, -0.2)
	return g

## A needle gun: a compact flechette carbine, its clear needle magazine along the top
## showing the steel darts inside, a fine barrel in a perforated shroud, an angled fore
## grip, a folded stock. Gunmetal and polymer.
static func _needle_gun(k: MeshKit) -> Vector3:
	var y := 0.035
	GunLook._loft(k, "gun_metal", [Vector3(0, y + 0.004, 0.08), Vector3(0, y + 0.006, 0.04), Vector3(0, y + 0.006, -0.08), Vector3(0, y + 0.003, -0.11)],
		[0.0125, 0.0135, 0.0135, 0.012], [0.014, 0.016, 0.016, 0.013], Vector3.UP, 16)
	_block(k, "gun_polymer", Vector3(0, y - 0.018, -0.01), Vector3(0.024, 0.018, 0.16))
	for sd in [-1.0, 1.0]:
		_box(k, "gun_bore", Vector3(sd * 0.0136, y + 0.006, -0.02), Vector3(0.001, 0.012, 0.04)) # ejection slot
		_box(k, "gun_bore", Vector3(sd * 0.0136, y + 0.0, 0.05), Vector3(0.001, 0.0015, 0.05))
	# The magazine: a clear tube with darts packed inside, metal end caps.
	_tube(k, "gun_crystal", Vector3(0, y + 0.03, 0.06), 0.16, 0.0095, 0.0095, 18)
	for n in 6:
		var a := TAU * n / 6.0
		_tube(k, "gun_bright", Vector3(cos(a) * 0.0045, y + 0.03 + sin(a) * 0.0045, 0.055), 0.15, 0.0011, 0.0011, 5)
	_tube(k, "gun_metal", Vector3(0, y + 0.03, 0.07), 0.012, 0.011, 0.011, 18)
	_tube(k, "gun_metal", Vector3(0, y + 0.03, -0.098), 0.012, 0.011, 0.011, 18)
	_box(k, "gun_metal", Vector3(0, y + 0.02, -0.015), Vector3(0.008, 0.006, 0.15))
	# Barrel in a perforated shroud.
	_tube(k, "gun_metal", Vector3(0, y + 0.002, -0.11), 0.11, 0.011, 0.011, 16)
	for n in 5:
		for c in 4:
			var a := TAU * c / 4.0 + PI * 0.25
			_box(k, "gun_bore", Vector3(cos(a) * 0.0108, y + 0.002 + sin(a) * 0.0108, -0.125 - n * 0.018), Vector3(0.004, 0.004, 0.008))
	_tube(k, "gun_metal", Vector3(0, y + 0.002, -0.22), 0.035, 0.0045, 0.0045, 12)
	_tube(k, "gun_metal", Vector3(0, y + 0.002, -0.245), 0.012, 0.007, 0.0065, 12)
	_bore(k, Vector3(0, y + 0.002, -0.257), 0.0022)
	_front_sight(k, "gun_metal", Vector3(0, y + 0.013, -0.2), 0.006)
	GunLook._loft(k, "gun_polymer", [Vector3(0, y - 0.024, -0.075), Vector3(0, y - 0.07, -0.085)], [0.011, 0.012], [0.013, 0.014], Vector3.FORWARD, 12)
	_guard(k, "gun_polymer", y - 0.027, -0.02, 0.03, 0.026, 0.01)
	_trigger(k, "gun_metal", Vector3(0, y - 0.027, 0.004), 0.017)
	var g := _grip(k, "gun_rubber_stip", Vector3(0, y - 0.027, 0.05), 0.45, 0.085, 0.013, 0.018)
	_grooves(k, "gun_rubber", Vector3(0, y - 0.027, 0.05), 0.45, 0.085, 0.013, 0.018)
	# Folded stock lying along the right side.
	_strap(k, "gun_metal", [Vector3(0.017, y + 0.004, 0.09), Vector3(0.017, y + 0.004, -0.07)], 0.007, 0.004)
	_strap(k, "gun_metal", [Vector3(0.017, y - 0.016, 0.09), Vector3(0.017, y - 0.016, -0.07)], 0.007, 0.004)
	_block(k, "gun_rubber", Vector3(0.017, y - 0.006, -0.072), Vector3(0.007, 0.034, 0.01))
	_fore = Vector3(0, y - 0.05, -0.08)
	return g

## A star pistol: a gentleman's piece of black lacquer and chased gold, the star shard it
## fires seated in a claw cradle over the breech (clear crystal, unlit), a long fluted
## barrel with gold collars.
static func _star_pistol(k: MeshKit) -> Vector3:
	var y := 0.03
	_block(k, "gun_polymer", Vector3(0, y - 0.004, -0.02), Vector3(0.024, 0.036, 0.09))
	_block(k, "gun_gold", Vector3(0, y - 0.004, -0.02), Vector3(0.0245, 0.012, 0.092))
	_barrel(k, "gun_blued", Vector3(0, y + 0.002, -0.065), 0.15, 0.0095, 0.0075, 0.0045, 16)
	for z in [-0.065, -0.13, -0.2]:
		_tube(k, "gun_gold", Vector3(0, y + 0.002, z), 0.008, 0.011, 0.011, 18)
	for n in 4:
		var a := TAU * n / 4.0 + PI * 0.25
		_strap(k, "gun_gold", [Vector3(cos(a) * 0.01, y + 0.016, -0.04), Vector3(cos(a) * 0.016, y + 0.03 + sin(a) * 0.004, -0.02 + sin(a) * 0.01),
			Vector3(cos(a) * 0.008, y + 0.045, -0.02 + sin(a) * 0.006)], 0.004, 0.0025)
	k.crystal("gun_crystal", Transform3D(Basis(), Vector3(0, y + 0.018, -0.02)), 0.01, 0.04, 6, 0.4)
	k.crystal("gun_crystal", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, y + 0.034, -0.02)), 0.01, 0.014, 6, 0.6)
	_hammer(k, "gun_gold", Vector3(0, y + 0.012, 0.02), 0.02)
	_guard(k, "gun_gold", y - 0.022, -0.05, 0.0, 0.022, 0.008)
	_trigger(k, "gun_gold", Vector3(0, y - 0.022, -0.026), 0.016)
	var g := _grip(k, "gun_ebony_y_chk", Vector3(0, y - 0.016, 0.012), 0.6, 0.095, 0.0135, 0.017, "gun_gold", -0.35)
	return g

## A singularity projector: a sphere of black glass in a gimbal of two steel rings, on a
## fork over a pistol grip. A light-swallowing mirror, not a glowing ball.
static func _singularity_orb(k: MeshKit) -> Vector3:
	var y := 0.09
	var c := Vector3(0, y, -0.06)
	k.sphere("gun_void", Transform3D(Basis(), c), 0.05, 14, 24)
	for n in 2:
		var ring: Array = []
		for i in 41:
			var a := TAU * i / 40.0
			ring.append(c + (Vector3(0, cos(a), sin(a)) if n == 0 else Vector3(cos(a), sin(a), 0)) * (0.064 - n * 0.008))
		GunLook._rod(k, "gun_metal", ring, 0.005, 8)
	for s in [-1.0, 1.0]:
		_pin(k, "gun_gold", c + Vector3(s * 0.071 - 0.004, 0, 0), 0.006, 0.008)
		_strap(k, "gun_metal", [c + Vector3(s * 0.072, 0, 0), c + Vector3(s * 0.074, -0.05, 0.02), c + Vector3(s * 0.02, -0.075, 0.05)], 0.012, 0.006)
	_block(k, "gun_metal", Vector3(0, y - 0.075, 0.02), Vector3(0.05, 0.016, 0.1))
	_guard(k, "gun_metal", y - 0.083, -0.02, 0.03, 0.024, 0.01)
	_trigger(k, "gun_metal", Vector3(0, y - 0.083, 0.004), 0.017)
	return _grip(k, "gun_rosewood_y_chk", Vector3(0, y - 0.083, 0.04), 0.2, 0.095, 0.015, 0.019, "gun_brass", 0.2)

## A precursor rifle: one flowing body of polished dark ceramic, swelling over the breech
## and parting into two long splayed prongs at the muzzle, a fin crest along its spine,
## a free-standing ring round the barrel, deep gold lines inlaid along it and a faceted
## dark lens for a sight. Old work of a vanished people: nothing glows.
static func _precursor_rifle(k: MeshKit) -> Vector3:
	var y := 0.04
	var zs := [0.36, 0.3, 0.18, 0.06, -0.06, -0.2, -0.32, -0.4]
	var ys := [y - 0.035, y - 0.025, y - 0.01, y + 0.004, y + 0.008, y + 0.004, y + 0.004, y + 0.004]
	var ws := [0.016, 0.02, 0.022, 0.03, 0.03, 0.022, 0.017, 0.015]
	var hs := [0.06, 0.05, 0.034, 0.04, 0.038, 0.024, 0.018, 0.015]
	var pts: Array = []
	for i in zs.size():
		pts.append(Vector3(0, ys[i], zs[i]))
	GunLook._loft(k, "gun_precursor", pts, ws, hs, Vector3.UP, 24)
	# Fin crest along the spine, tallest over the breech.
	for n in 9:
		var z := 0.16 - n * 0.055
		var h := 0.022 * (1.0 - absf(n - 3) / 6.0)
		GunLook._loft(k, "gun_precursor", [Vector3(0, y + 0.03, z + 0.02), Vector3(0, y + 0.03 + h, z - 0.01), Vector3(0, y + 0.03 + h * 0.6, z - 0.03)],
			[0.0025, 0.0018, 0.001], [0.004, 0.003, 0.002], Vector3.RIGHT, 8)
	# Prongs: two long splayed blades past the body, a dark gap between.
	for sd in [-1.0, 1.0]:
		GunLook._loft(k, "gun_precursor", [Vector3(sd * 0.007, y + 0.004, -0.38), Vector3(sd * 0.018, y + 0.006, -0.5), Vector3(sd * 0.022, y + 0.004, -0.62), Vector3(sd * 0.012, y + 0.002, -0.72)],
			[0.007, 0.007, 0.005, 0.0015], [0.016, 0.015, 0.011, 0.003], Vector3.UP, 14)
		GunLook._loft(k, "gun_gold", [Vector3(sd * 0.0072, y + 0.018, -0.41), Vector3(sd * 0.025, y + 0.017, -0.52), Vector3(sd * 0.027, y + 0.012, -0.62)],
			[0.0015, 0.0015, 0.001], [0.0016, 0.0016, 0.0012], Vector3.UP, 6)
		# Gold lines inlaid along both flanks, following the body.
		var line: Array = []
		for i in range(1, zs.size() - 1):
			line.append(Vector3(sd * (ws[i] + 0.0003), ys[i] + hs[i] * 0.25, zs[i]))
		GunLook._rod(k, "gun_gold", line, 0.0018, 6)
		var low: Array = []
		for i in range(2, zs.size() - 2):
			low.append(Vector3(sd * (ws[i] * 0.95 + 0.0003), ys[i] - hs[i] * 0.45, zs[i]))
		GunLook._rod(k, "gun_gold", low, 0.0012, 6)
	_bore(k, Vector3(0, y + 0.004, -0.4), 0.008)
	# A free-standing ring round the fore-body, on two struts.
	var ring: Array = []
	for i in 33:
		var a := TAU * i / 32.0
		ring.append(Vector3(cos(a) * 0.04, y + 0.004 + sin(a) * 0.04, -0.26))
	GunLook._rod(k, "gun_precursor", ring, 0.006, 10)
	GunLook._rod(k, "gun_gold", ring.map(func(p): return p + Vector3(0, 0, -0.007)), 0.0025, 6)
	for sd in [-1.0, 1.0]:
		_box(k, "gun_precursor", Vector3(sd * 0.026, y + 0.004, -0.26), Vector3(0.022, 0.008, 0.01))
	# Sight: a faceted dark lens in a cowl.
	_block(k, "gun_precursor", Vector3(0, y + 0.048, 0.02), Vector3(0.022, 0.02, 0.07))
	k.crystal("gun_glass", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, y + 0.048, -0.014)), 0.0085, 0.012, 6, 0.6)
	_guard(k, "gun_precursor", y - 0.032, 0.02, 0.08, 0.028, 0.012)
	_trigger(k, "gun_gold", Vector3(0, y - 0.032, 0.046), 0.017)
	var g := _grip(k, "gun_precursor", Vector3(0, y - 0.032, 0.09), 0.34, 0.09, 0.015, 0.021)
	_fore = Vector3(0, y - 0.025, -0.2)
	return g

## A nova staff, carried pointing ahead: a long shaft of dark iron bound in gold, a
## leather grip, and a claw of four prongs holding a clear star shard at the head.
static func _nova_staff(k: MeshKit) -> Vector3:
	var y := 0.0
	_tube(k, "gun_iron", Vector3(0, y, 0.55), 1.4, 0.013, 0.014, 14)
	k.sphere("gun_gold", Transform3D(Basis(), Vector3(0, y, 0.555)), 0.018, 6, 12)
	_tube(k, "gun_leather", Vector3(0, y, 0.09), 0.2, 0.0155, 0.0155, 14)
	for z in [0.11, -0.12, -0.4, -0.7]:
		_tube(k, "gun_gold", Vector3(0, y, z), 0.016, 0.0175, 0.0175, 16)
	_tube(k, "gun_gold", Vector3(0, y, -0.84), 0.03, 0.016, 0.024, 18)
	var head := Vector3(0, y, -0.93)
	for n in 4:
		var a := TAU * n / 4.0
		var d := Vector3(cos(a), sin(a), 0)
		_strap(k, "gun_gold", [Vector3(0, y, -0.86) + d * 0.02, head + d * 0.04 + Vector3(0, 0, 0.03), head + d * 0.03 + Vector3(0, 0, -0.02), head + d * 0.012 + Vector3(0, 0, -0.04)], 0.007, 0.004)
	k.crystal("gun_crystal", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), head + Vector3(0, 0, 0.02)), 0.022, 0.07, 7, 0.4)
	k.crystal("gun_crystal", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), head + Vector3(0, 0, 0.02)), 0.022, 0.03, 7, 0.6)
	return Vector3(0, y, 0.0)

# --- Bows and slings -------------------------------------------------------------------

## Bow limbs from the ends of the riser (at ±riser) out to the tips at ±half, bending back
## toward the archer by `brace` and, for a recurve, flicking forward at the tips. The
## limbs run in the YZ plane; width is across (X), thickness front to back. Returns the
## two tips (top, bottom).
static func _limbs(k: MeshKit, m: String, half: float, riser: float, brace: float, w0: float, w1: float, t0: float, t1: float, recurve := 0.0, back := "") -> Array:
	var tips: Array = []
	for s in [1.0, -1.0]:
		var pts: Array = []
		var ws: Array = []
		var hs: Array = []
		for i in 13:
			var f := i / 12.0
			var z := brace * f * f
			if recurve > 0.0 and f > 0.7:
				z -= recurve * pow((f - 0.7) / 0.3, 2.0)
			pts.append(Vector3(0, s * (riser + (half - riser) * f), z))
			ws.append(lerpf(t0, t1, f) * 0.5)
			hs.append(lerpf(w0, w1, f) * 0.5)
		GunLook._loft(k, m, pts, ws, hs, Vector3.RIGHT, 12)
		if back != "":
			# A backing strip (sinew, rawhide) along the face away from the archer.
			var bp: Array = []
			var bw: Array = []
			var bh: Array = []
			for i in 13:
				bp.append(pts[i] - Vector3(0, 0, ws[i] + 0.0008))
				bw.append(0.0009)
				bh.append(hs[i] * 0.9)
			GunLook._loft(k, back, bp, bw, bh, Vector3.RIGHT, 8)
		tips.append(pts[12])
	return tips

## The riser: the thick middle of the bow from -h to +h, a wrapped grip, an arrow shelf
## on the left.
static func _riser(k: MeshKit, m: String, h: float, w: float, t: float, wrap := "gun_leather") -> void:
	var pts: Array = []
	var ws: Array = []
	var hs: Array = []
	for i in 7:
		var f := i / 6.0 * 2.0 - 1.0
		pts.append(Vector3(0, f * h, -0.004 * (1.0 - f * f)))
		var thick := 1.0 + 0.25 * (1.0 - absf(f))
		ws.append(t * 0.5 * thick)
		hs.append(w * 0.5)
	GunLook._loft(k, m, pts, ws, hs, Vector3.RIGHT, 14)
	_grip_r = (w + t) * 0.25 * 1.2
	GunLook._loft(k, wrap, [Vector3(0, -0.05, -0.002), Vector3(0, 0.0, -0.004), Vector3(0, 0.045, -0.002)],
		[t * 0.66, t * 0.68, t * 0.66], [w * 0.56, w * 0.58, w * 0.56], Vector3.RIGHT, 14)
	_box(k, m, Vector3(-w * 0.5 - 0.003, 0.054, -0.004), Vector3(0.008, 0.004, t * 0.9))

## A nocked arrow resting on the shelf: ash shaft, three fletchings, a horn nock and a
## steel head. Its nock sits on the string at z.
static func _arrow(k: MeshKit, string_z: float, len := 0.76, head := "gun_worn", fletch := "gun_fletch") -> void:
	var at := Vector3(-0.01, 0.058, string_z)
	_tube(k, "gun_ash", at, len, 0.0042, 0.0042, 8)
	_tube(k, "gun_horn", at + Vector3(0, 0, 0.002), 0.012, 0.0046, 0.0046, 8)
	for n in 3:
		var a := TAU * n / 3.0 + PI * 0.5
		var d := Vector3(cos(a), sin(a), 0)
		GunLook._loft(k, fletch, [at + d * 0.005 - Vector3(0, 0, 0.02), at + d * 0.013 - Vector3(0, 0, 0.05), at + d * 0.0075 - Vector3(0, 0, 0.11)],
			[0.0005, 0.0005, 0.0005], [0.002, 0.007, 0.003], d.cross(Vector3.FORWARD).normalized(), 6)
	var tip := at - Vector3(0, 0, len)
	_tube(k, head, tip + Vector3(0, 0, 0.012), 0.014, 0.0052, 0.0048, 8)
	GunLook._loft(k, head, [tip, tip - Vector3(0, 0, 0.022), tip - Vector3(0, 0, 0.045)], [0.0016, 0.0013, 0.0003], [0.011, 0.008, 0.0006], Vector3.UP, 8)

## The string from tip to tip, with a serving wrapped where the arrow nocks.
static func _bow_string(k: MeshKit, tips: Array, mat := "gun_string") -> float:
	var a: Vector3 = tips[0]
	var b: Vector3 = tips[1]
	GunLook._rod(k, mat, [a, b], 0.0015, 6)
	var z := (a.z + b.z) * 0.5
	k.cylinder("gun_horn", Transform3D(Basis(), Vector3(0, 0.03, z)), 0.0022, 0.0022, 0.07, 6)
	return z

## Horn nocks on the tips.
static func _nocks(k: MeshKit, tips: Array, m := "gun_horn") -> void:
	for i in 2:
		var t: Vector3 = tips[i]
		var s := 1.0 if i == 0 else -1.0
		k.cylinder(m, Transform3D(Basis(Vector3.RIGHT, 0.0 if s > 0 else PI), t - Vector3(0, s * 0.03, 0)), 0.0085, 0.004, 0.045, 10)

## An English longbow of yew: 1.8 m, the pale sapwood back and dark heartwood belly,
## horn nocks, a leather grip, an arrow on the string.
static func _longbow(k: MeshKit) -> Vector3:
	_riser(k, "gun_yew_y", 0.07, 0.036, 0.044)
	var tips := _limbs(k, "gun_yew_y", 0.9, 0.07, 0.16, 0.042, 0.019, 0.05, 0.024, 0.0, "gun_maple_y")
	_nocks(k, tips)
	_arrow(k, _bow_string(k, tips), 0.78, "gun_worn")
	return Vector3.ZERO

## A hunter's shortbow of ash: 1.2 m, a plain leather grip.
static func _shortbow(k: MeshKit) -> Vector3:
	_riser(k, "gun_ash_y", 0.06, 0.034, 0.038)
	var tips := _limbs(k, "gun_ash_y", 0.6, 0.06, 0.13, 0.042, 0.019, 0.04, 0.02)
	for t in tips:
		k.sphere("gun_ash", Transform3D(Basis(), t), 0.007, 5, 8)
	_arrow(k, _bow_string(k, tips), 0.66, "gun_worn")
	return Vector3.ZERO

## A horse archer's composite bow: horn belly, sinew back under birch bark, a sharply
## recurved profile with stiff bone-tipped ears and string bridges. Short and powerful.
static func _composite_bow(k: MeshKit) -> Vector3:
	_riser(k, "gun_walnut_y", 0.065, 0.032, 0.036, "gun_red")
	var tips := _limbs(k, "gun_horn", 0.46, 0.065, 0.1, 0.046, 0.032, 0.036, 0.026, 0.0, "gun_sinew")
	var ears: Array = []
	for i in 2:
		var t: Vector3 = tips[i]
		var s := 1.0 if i == 0 else -1.0
		# The ear (siyah): a stiff lath angled forward, a bone string bridge at its root.
		var e := t + Vector3(0, s * 0.15, -0.12)
		GunLook._loft(k, "gun_walnut_y", [t - Vector3(0, s * 0.01, 0), t + Vector3(0, s * 0.07, -0.05), e], [0.009, 0.0085, 0.006], [0.012, 0.011, 0.008], Vector3.RIGHT, 10)
		_box(k, "gun_bone", t + Vector3(0, s * 0.006, 0.01), Vector3(0.016, 0.01, 0.012))
		k.cylinder("gun_bone", Transform3D(Basis(Vector3.RIGHT, -0.75 * s), e - Vector3(0, s * 0.02, -0.016)), 0.0075, 0.005, 0.03, 10)
		ears.append(e)
	_arrow(k, _bow_string(k, ears), 0.72, "gun_worn")
	return Vector3.ZERO

## The royal longbow: dark yew with gilt bands, a red velvet grip and gilded horn nocks,
## a fine bodkin arrow.
static func _royal_bow(k: MeshKit) -> Vector3:
	_riser(k, "gun_yew_y", 0.075, 0.032, 0.036, "gun_red")
	var tips := _limbs(k, "gun_yew_y", 0.92, 0.075, 0.17, 0.044, 0.019, 0.052, 0.024, 0.0, "gun_maple_y")
	for s in [1.0, -1.0]:
		for y in [0.08, 0.24, 0.5]:
			var f: float = (y - 0.075) / (0.92 - 0.075)
			var z: float = 0.17 * f * f
			GunLook._loft(k, "gun_gold", [Vector3(0, s * y - 0.004, z), Vector3(0, s * y + 0.004, z)],
				[lerpf(0.052, 0.024, f) * 0.56, lerpf(0.052, 0.024, f) * 0.56], [lerpf(0.044, 0.019, f) * 0.56, lerpf(0.044, 0.019, f) * 0.56], Vector3.RIGHT, 12)
	_nocks(k, tips, "gun_gold")
	_arrow(k, _bow_string(k, tips), 0.8, "gun_bright", "gun_red")
	return Vector3.ZERO

## A heavy crossbow: a steel prod spanned by a windlass, a thick walnut tiller with an iron
## stirrup, a quarrel in the groove. The windlass and its cranks sit at the butt.
static func _heavy_crossbow(k: MeshKit) -> Vector3:
	var tz := [0.22, 0.16, 0.1, 0.04, -0.04, -0.2, -0.36, -0.44, -0.47]
	var ty := [-0.026, -0.02, -0.006, 0.004, 0.009, 0.012, 0.012, 0.012, 0.012]
	var tw := [0.021, 0.023, 0.02, 0.021, 0.023, 0.022, 0.021, 0.024, 0.019]
	var th := [0.04, 0.042, 0.03, 0.025, 0.024, 0.021, 0.02, 0.023, 0.018]
	var pts: Array = []
	for i in tz.size():
		pts.append(Vector3(0, ty[i], tz[i]))
	GunLook._loft(k, "gun_walnut", pts, tw, th)
	_box(k, "gun_polymer", Vector3(0, 0.033, -0.24), Vector3(0.006, 0.002, 0.42))
	for z in [0.07, -0.38]:
		GunLook._sleeve(k, "gun_iron", Vector3(0, 0.01, z), 0.016, 0.0235, 0.026)
	# Steel prod: thick, short, barely curved, lashed to the nose with cord and iron.
	var nose := Vector3(0, 0.012, -0.43)
	for s in [-1.0, 1.0]:
		var lp: Array = []
		var lw: Array = []
		var lh: Array = []
		for n in 9:
			var f := n / 8.0
			lp.append(nose + Vector3(s * f * 0.33, 0, 0.05 * pow(f, 1.4)))
			lw.append(lerpf(0.009, 0.005, f))
			lh.append(lerpf(0.02, 0.011, f))
		lp[0] = nose + Vector3(-s * 0.014, 0, 0)
		GunLook._loft(k, "gun_bright", lp, lh, lw, Vector3.BACK, 12)
		var tip: Vector3 = lp[-1]
		_rod_ring(k, tip)
		GunLook._rod(k, "gun_string", [tip, Vector3(s * 0.005, 0.04, -0.04)], 0.0022, 5)
	for n in 5:
		GunLook._sleeve(k, "gun_string", Vector3(0, 0.012, -0.415 - n * 0.006), 0.004, 0.0255, 0.025)
	GunLook._rod(k, "gun_iron", [Vector3(-0.02, 0.012, -0.46), Vector3(-0.04, 0.008, -0.5), Vector3(-0.032, 0.004, -0.54),
		Vector3(0.032, 0.004, -0.54), Vector3(0.04, 0.008, -0.5), Vector3(0.02, 0.012, -0.46)], 0.004)
	# The nut, the quarrel, the trigger lever under the tiller.
	k.cylinder("gun_bone", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.019, 0.032, -0.04)), 0.013, 0.013, 0.038, 14)
	_tube(k, "gun_ash", Vector3(0, 0.038, -0.05), 0.33, 0.0055, 0.0055, 8)
	k.cylinder("gun_iron", GunLook._z(Vector3(0, 0.038, -0.38)), 0.008, 0.0, 0.04, 4)
	for s in [-1.0, 1.0]:
		_box(k, "gun_leather", Vector3(s * 0.007, 0.042, -0.09), Vector3(0.0012, 0.012, 0.05), s * 0.6)
	_strap(k, "gun_iron", [Vector3(0, -0.012, 0.0), Vector3(0, -0.04, 0.03), Vector3(0, -0.05, 0.12)], 0.007, 0.005)
	# Windlass at the butt: a drum across the stock with crank arms each side.
	k.cylinder("gun_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.03, -0.01, 0.2)), 0.014, 0.014, 0.06, 14)
	for s in [-1.0, 1.0]:
		_box(k, "gun_iron", Vector3(s * 0.034, -0.03, 0.2), Vector3(0.005, 0.05, 0.01))
		k.cylinder("gun_walnut_x", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5 * s), Vector3(s * 0.036, -0.052, 0.2)), 0.008, 0.008, 0.04, 10)
	_fore = Vector3(0, 0.0, -0.2)
	return Vector3(0, -0.02, 0.06)

static func _rod_ring(k: MeshKit, at: Vector3) -> void:
	k.sphere("gun_iron", Transform3D(Basis(), at), 0.008, 5, 8)

## A shepherd's sling: a finger loop, two braided cords hanging apart from the hand to a
## broad leather pouch cradling a stone. One cord ends in a knot for the release.
static func _sling(k: MeshKit) -> Vector3:
	var loop: Array = []
	for i in 13:
		var a := TAU * i / 12.0
		loop.append(Vector3(cos(a) * 0.013, sin(a) * 0.013, 0.0))
	GunLook._rod(k, "gun_string", loop, 0.0028, 6)
	_grip_r = 0.008
	var pouch := Vector3(0, -0.4, -0.02)
	for s in [-1.0, 1.0]:
		var c: Array = []
		for i in 9:
			var f := i / 8.0
			var bow := sin(f * PI) * 0.03
			c.append(Vector3(s * (0.006 + 0.05 * f + bow * 0.5), -0.012 - 0.37 * f, -0.02 * f + s * (0.045 * f + bow * 0.4)))
		GunLook._rod(k, "gun_string", c, 0.0036, 6)
	k.sphere("gun_string", Transform3D(Basis(), Vector3(0.008, -0.004, 0.0)), 0.007, 5, 8, 0.2)
	# The pouch: a dished oval of leather with the stone in it, open toward the hand.
	k.sphere("gun_leather", Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 0.75)), pouch), 0.075, 8, 16, 0.08, 1.0, Color.WHITE, true)
	k.sphere("gun_leather", Transform3D(Basis.from_scale(Vector3(1.0, -0.3, 0.75)), pouch), 0.075, 8, 16, 0.08, 1.0, Color.WHITE, true)
	k.sphere("gun_flint", Transform3D(Basis(), pouch + Vector3(0, 0.02, 0)), 0.034, 8, 12, 0.14)
	# Holes punched through the pouch where each cord is tied off.
	for s in [-1.0, 1.0]:
		k.sphere("gun_string", Transform3D(Basis(), pouch + Vector3(s * 0.07, 0.006, 0)), 0.008, 5, 8, 0.2)
	return Vector3.ZERO

# --- Alien weapons (faint inner light allowed) ---------------------------------------

## A bio rifle: a living weapon of overlapping chitin plates over pale flesh, a row of
## spines along the back, glowing glands in the flanks, a mandible muzzle.
static func _bio_rifle(k: MeshKit) -> Vector3:
	var y := 0.04
	for n in 9:
		var z := 0.28 - n * 0.085
		var f := n / 8.0
		var r := 0.032 - 0.012 * f + 0.008 * sin(f * PI)
		GunLook._loft(k, "gun_chitin", [Vector3(0, y + 0.004 * sin(f * 3.0), z + 0.05), Vector3(0, y + 0.002, z), Vector3(0, y, z - 0.03)],
			[r * 0.82, r * 0.9, r * 0.8], [r * 1.0, r * 1.06, r * 0.94], Vector3.UP, 14)
		k.cylinder("gun_bone", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, y + r * 1.0, z)), 0.005, 0.0, 0.03 - f * 0.012, 6)
	_tube(k, "gun_flesh", Vector3(0, y, 0.33), 0.79, 0.022, 0.014, 14)
	for s in [-1.0, 1.0]:
		k.sphere("alien_teal", Transform3D(Basis.from_scale(Vector3(0.6, 0.8, 1.4)), Vector3(s * 0.024, y - 0.004, 0.05)), 0.016, 7, 12)
		k.sphere("alien_teal", Transform3D(Basis.from_scale(Vector3(0.6, 0.8, 1.2)), Vector3(s * 0.02, y - 0.002, -0.14)), 0.012, 7, 12)
		_strap(k, "gun_chitin", [Vector3(s * 0.012, y - 0.004, -0.46), Vector3(s * 0.022, y + 0.004, -0.53), Vector3(s * 0.008, y + 0.0, -0.6)], 0.012, 0.006)
	_bore(k, Vector3(0, y, -0.47), 0.008)
	_strap(k, "gun_chitin", [Vector3(0, y - 0.028, -0.02), Vector3(0, y - 0.05, 0.0), Vector3(0, y - 0.05, 0.04), Vector3(0, y - 0.03, 0.06)], 0.01, 0.005)
	_strap(k, "gun_bone", [Vector3(0, y - 0.028, 0.012), Vector3(0, y - 0.042, 0.016), Vector3(0, y - 0.046, 0.022)], 0.005, 0.003)
	var g := _grip(k, "gun_chitin", Vector3(0, y - 0.028, 0.07), 0.4, 0.1, 0.0145, 0.02)
	_fore = Vector3(0, y - 0.02, -0.2)
	return g

## A hive cannon: a heavy chitin tube ending in a comb of hexagonal cells, brood sacs
## glowing faintly along its belly, a ribbed grip of bone.
static func _hive_cannon(k: MeshKit) -> Vector3:
	var y := 0.06
	GunLook._loft(k, "gun_chitin", [Vector3(0, y - 0.01, 0.28), Vector3(0, y, 0.12), Vector3(0, y + 0.004, -0.1), Vector3(0, y, -0.3), Vector3(0, y, -0.42)],
		[0.03, 0.046, 0.05, 0.054, 0.058], [0.04, 0.05, 0.054, 0.058, 0.06], Vector3.UP, 20)
	for n in 5:
		_tube(k, "gun_bone", Vector3(0, y, 0.1 - n * 0.11), 0.014, 0.055 + n * 0.0015, 0.056 + n * 0.0015, 20)
	# The comb: hexagonal cells packed in the mouth, dark inside.
	for c in 7:
		var off := Vector3.ZERO if c == 0 else Vector3(cos(TAU * c / 6.0), sin(TAU * c / 6.0), 0) * 0.033
		k.crystal("gun_sinew", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, y, -0.4) + off), 0.019, 0.03, 6, 0.0)
		_bore(k, Vector3(0, y, -0.43) + off, 0.012)
	for n in 3:
		k.sphere("alien_teal", Transform3D(Basis.from_scale(Vector3(1, 0.7, 1.3)), Vector3(0, y - 0.05, -0.05 - n * 0.09)), 0.02, 7, 12, 0.15)
	_strap(k, "gun_bone", [Vector3(0, y - 0.045, 0.05), Vector3(0, y - 0.07, 0.07), Vector3(0, y - 0.07, 0.11), Vector3(0, y - 0.045, 0.13)], 0.01, 0.005)
	_strap(k, "gun_bone", [Vector3(0, y - 0.045, 0.085), Vector3(0, y - 0.058, 0.09), Vector3(0, y - 0.062, 0.096)], 0.005, 0.003)
	var g := _grip(k, "gun_bone", Vector3(0, y - 0.045, 0.14), 0.35, 0.1, 0.015, 0.021)
	GunLook._loft(k, "gun_chitin", [Vector3(0, y - 0.05, -0.2), Vector3(0, y - 0.15, -0.19)], [0.015, 0.016], [0.018, 0.019], Vector3.FORWARD, 14)
	_fore = Vector3(0, y - 0.1, -0.195)
	return g

## A spore launcher: a fungal stalk of a weapon, bulbous spore pods clustered along it,
## a frilled cap round the muzzle, a gill-lined throat with a faint glow.
static func _spore_launcher(k: MeshKit) -> Vector3:
	var y := 0.05
	GunLook._loft(k, "gun_flesh", [Vector3(0, y - 0.01, 0.25), Vector3(0, y, 0.05), Vector3(0, y + 0.004, -0.2), Vector3(0, y, -0.36)],
		[0.026, 0.034, 0.03, 0.028], [0.03, 0.038, 0.034, 0.03], Vector3.UP, 18)
	var pods := [Vector3(0.03, 0.03, 0.02), Vector3(-0.032, 0.026, -0.04), Vector3(0.026, 0.036, -0.12), Vector3(-0.02, 0.04, -0.2), Vector3(0.01, 0.045, 0.1)]
	for i in pods.size():
		var p: Vector3 = pods[i]
		k.sphere("gun_chitin", Transform3D(Basis(), Vector3(p.x, y + p.y, p.z)), 0.024 - i * 0.002, 8, 12, 0.18)
		k.sphere("alien_teal", Transform3D(Basis(), Vector3(p.x * 1.2, y + p.y * 1.25, p.z)), 0.007, 5, 8)
	for n in 12:
		var a := TAU * n / 12.0
		var d := Vector3(cos(a), sin(a), 0)
		_strap(k, "gun_chitin", [Vector3(0, y, -0.34) + d * 0.026, Vector3(0, y, -0.38) + d * 0.05, Vector3(0, y, -0.4) + d * 0.058], 0.016, 0.003)
	k.cylinder("alien_teal", GunLook._z(Vector3(0, y, -0.355)), 0.02, 0.02, 0.002, 18)
	_strap(k, "gun_bone", [Vector3(0, y - 0.03, 0.04), Vector3(0, y - 0.056, 0.06), Vector3(0, y - 0.056, 0.1), Vector3(0, y - 0.032, 0.12)], 0.01, 0.005)
	_strap(k, "gun_bone", [Vector3(0, y - 0.03, 0.075), Vector3(0, y - 0.044, 0.08), Vector3(0, y - 0.048, 0.086)], 0.005, 0.003)
	var g := _grip(k, "gun_chitin", Vector3(0, y - 0.03, 0.13), 0.35, 0.1, 0.015, 0.021)
	_fore = Vector3(0, y - 0.03, -0.18)
	return g

## A shard gauntlet: a chitin-plated bracer over the forearm and a fist plate over the
## knuckles, crystal shards standing along the back of the hand with a faint light.
static func _shard_gauntlet(k: MeshKit) -> Vector3:
	# The fist closes inside round a grip bar at the origin; the bracer runs back up the arm.
	k.cylinder("gun_bone", Transform3D(Basis(), Vector3(0, -0.04, 0)), 0.011, 0.011, 0.08, 10)
	_grip_r = 0.011
	# One shell from the knuckles back up the forearm: the fist's glove swelling into the
	# bracer, so the two read as a single piece.
	GunLook._loft(k, "gun_chitin", [Vector3(0, 0.0, -0.058), Vector3(0, -0.004, -0.03), Vector3(0, -0.006, 0.02), Vector3(0, -0.004, 0.07),
		Vector3(0, 0.0, 0.14), Vector3(0, 0.0, 0.24)], [0.032, 0.042, 0.046, 0.045, 0.048, 0.044], [0.04, 0.048, 0.05, 0.047, 0.05, 0.046], Vector3.UP, 20)
	for n in 3:
		_tube(k, "gun_bone", Vector3(0, 0.0, 0.08 + n * 0.07), 0.01, 0.05, 0.05, 20)
	# Plates over the back of the hand and knuckles.
	for n in 3:
		_block(k, "gun_chitin", Vector3(0.028 - n * 0.002, 0.0, 0.03 - n * 0.032), Vector3(0.022, 0.07 - n * 0.006, 0.034))
	_block(k, "gun_chitin", Vector3(0, 0.0, -0.06), Vector3(0.05, 0.08, 0.016))
	for n in 4:
		_block(k, "gun_bone", Vector3(-0.004, 0.03 - n * 0.02, -0.07), Vector3(0.03, 0.016, 0.012))
	# Shards: a crown of crystals along the back of the hand, pointing ahead.
	for n in 5:
		var yy := 0.03 - n * 0.015
		var b := Basis(Vector3.FORWARD, 0.0) * Basis(Vector3(0, 0, 1), -PI * 0.5 + (n - 2) * 0.12) * Basis(Vector3.RIGHT, -0.5)
		k.crystal("alien_violet", Transform3D(b, Vector3(0.04, yy, 0.0 - absf(n - 2) * 0.01)), 0.008, 0.06 - absf(n - 2) * 0.012, 5, 0.35)
	return Vector3(0, 0.0, 0.0)

## A crystal bow: pale alloy limbs grown through with crystal, shards along the limbs with
## a faint violet light, a crystal arrow.
static func _crystal_bow(k: MeshKit) -> Vector3:
	_riser(k, "gun_bright", 0.07, 0.032, 0.034, "gun_chitin")
	var tips := _limbs(k, "gun_bright", 0.62, 0.07, 0.12, 0.042, 0.018, 0.038, 0.02, 0.06)
	for s in [1.0, -1.0]:
		for n in 4:
			var f := 0.15 + n * 0.22
			var yy: float = s * (0.07 + (0.62 - 0.07) * f)
			var z := 0.12 * f * f
			k.crystal("alien_violet", Transform3D(Basis(Vector3.RIGHT, -0.4 - s * 0.6), Vector3(0, yy, z - 0.008)), 0.006, 0.04 - n * 0.006, 5, 0.4)
	_nocks(k, tips, "alien_violet")
	var z := _bow_string(k, tips)
	_arrow(k, z, 0.7, "alien_violet", "gun_chitin")
	return Vector3.ZERO

## The eclipse bow: a black recurve with a ring of dark metal round the grip, the ring's
## rim lit faintly like the corona round an eclipsed sun.
static func _eclipse_bow(k: MeshKit) -> Vector3:
	_riser(k, "gun_ebony_y", 0.08, 0.034, 0.036, "gun_leather")
	var tips := _limbs(k, "gun_ebony_y", 0.66, 0.08, 0.13, 0.046, 0.018, 0.04, 0.02, 0.07, "gun_gold")
	var c := Vector3(0, 0.0, -0.03)
	var ring: Array = []
	for n in 33:
		var a := TAU * n / 32.0
		ring.append(c + Vector3(sin(a) * 0.09, cos(a) * 0.09, 0))
	GunLook._rod(k, "gun_void", ring, 0.008, 8)
	var rim: Array = []
	for n in 33:
		var a := TAU * n / 32.0
		rim.append(c + Vector3(sin(a) * 0.0985, cos(a) * 0.0985, 0))
	GunLook._rod(k, "alien_warm", rim, 0.0022, 6)
	_nocks(k, tips, "gun_gold")
	_arrow(k, _bow_string(k, tips), 0.74, "gun_void", "gun_red")
	return Vector3.ZERO
