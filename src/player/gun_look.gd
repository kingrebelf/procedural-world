class_name GunLook
## How the ranged weapons look: the sci-fi kit guns re-skinned with proper materials
## (gunmetal, matte polymer, a painted body and glowing energy strips in place of the
## kit's flat white and orange), and the period weapons (revolver, crossbows) forged from
## parts in wood, iron and brass. Guns point along -Z with the grip at the origin.

## Item type -> [kit model, scale, body paint, accent]. The accent names a colour from GLOW
## (shown as anodised metal on these human guns) or is a paint colour.
const KIT := {
	"pulse_pistol": ["scifi/Pistol_1", 0.3, Color(0.78, 0.8, 0.83), "glow_cyan"],
	"pulse_smg": ["scifi/SMG_2", 0.3, Color(0.2, 0.23, 0.26), "glow_teal"],
	"pulse_rifle": ["scifi/AR_3", 0.3, Color(0.3, 0.33, 0.25), "glow_cyan"],
	"rail_rifle": ["scifi/Sniper_2", 0.3, Color(0.14, 0.17, 0.25), "glow_white"],
	"arc_launcher": ["scifi/Grenade_3", 0.3, Color(0.5, 0.44, 0.33), "glow_violet"],
}

## Sights from the kit's modular parts, set on top of the gun (model, nudge, scale).
const OPTICS := {
	"rail_rifle": ["scifi/Scope_2", Vector3(0, -0.005, 0.04), 0.3],
	"pulse_rifle": ["scifi/Sight_1", Vector3(0, -0.003, 0.02), 0.3],
}

const GRIP_AT := Vector3(0, -0.03, 0.0)

static func has(t: String) -> bool:
	return KIT.has(t) or t in ["scrap_pistol", "crossbow", "crossbow_runic"] or Firearms.has(t)

static var _mats: Dictionary = {}
static var _grain: NoiseTexture2D
static var _scuff: NoiseTexture2D

static func model(t: String) -> ArrayMesh:
	if KIT.has(t):
		return _kit_gun(t)
	match t:
		"scrap_pistol":
			return _revolver()
		"crossbow":
			return _crossbow(false)
		"crossbow_runic":
			return _crossbow(true)
	return Firearms.model(t)

static func _kit_gun(t: String) -> ArrayMesh:
	var e: Array = KIT[t]
	if not ResourceLoader.exists("res://assets/models/%s.gltf" % e[0]):
		return null
	# The kit's guns point along +X with the grip at the origin.
	var turn := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var out := Viewmodel.kit_mesh(e[0], turn * Transform3D.IDENTITY.scaled(Vector3.ONE * e[1]))
	if OPTICS.has(t) and ResourceLoader.exists("res://assets/models/%s.gltf" % OPTICS[t][0]):
		var o: Array = OPTICS[t]
		# Seated on the gun's top, over its middle.
		var box := out.get_aabb()
		var at: Vector3 = Vector3(0, box.end.y, box.get_center().z) + o[1]
		var part := Viewmodel.kit_mesh(o[0], Transform3D(Basis(), at) * turn * Transform3D.IDENTITY.scaled(Vector3.ONE * o[2]))
		for i in part.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(i))
			out.surface_set_material(out.get_surface_count() - 1, part.surface_get_material(i))
	for i in out.get_surface_count():
		out.surface_set_material(i, _skin(out.surface_get_material(i), e[2], e[3]))
	# The fist closes round the pistol grip just under the frame.
	out.set_meta("grip", GRIP_AT)
	return out

## The kit paints every gun from four flat colours: Black, Grey, White and Main (orange).
## Black becomes matte polymer, Grey gunmetal, White the gun's body paint and Main its
## accent strips.
static func _skin(m: Material, body: Color, accent) -> Material:
	var slot := _slot(m)
	match slot:
		"Black":
			return mat("gun_polymer")
		"Grey":
			return mat("gun_metal")
		"White":
			return _paint(body)
		"Main":
			# Human sci-fi: the energy strips are anodised metal, not lit (nothing made by
			# people glows).
			return _anodised(accent) if accent is String else _paint(accent)
	return m

static func _slot(m: Material) -> String:
	if m == null:
		return ""
	if m.resource_name in ["Black", "Grey", "White", "Main"]:
		return m.resource_name
	if not (m is BaseMaterial3D):
		return ""
	var c := (m as BaseMaterial3D).albedo_color
	if c.r - c.b > 0.25:
		return "Main"
	if c.r < 0.05:
		return "Black"
	return "Grey" if c.r < 0.2 else "White"

## Energy strips: lit from within, but held close to the eye, so far softer than the
## world's glow materials (those bloom across half the screen at this distance).
const GLOW := {"glow_cyan": Color(0.2, 0.85, 1.0), "glow_teal": Color(0.2, 1.0, 0.8), "glow_red": Color(1.0, 0.25, 0.2),
	"glow_violet": Color(0.7, 0.4, 1.0), "glow_white": Color(0.8, 0.9, 1.0), "glow_warm": Color(1.0, 0.65, 0.3)}

static func _glow(name: String) -> Material:
	var key := "gun_" + name
	if not _mats.has(key):
		var c: Color = GLOW.get(name, Color.WHITE)
		var m := _base(c * 0.6, 0.3, 0.0)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.9
		_mats[key] = m
	return _mats[key]

static func _anodised(name: String) -> Material:
	var key := "gun_anod_" + name
	if not _mats.has(key):
		var c: Color = GLOW.get(name, Color.WHITE)
		_mats[key] = _base(c * 0.42, 0.3, 0.75)
	return _mats[key]

static func _paint(c: Color) -> StandardMaterial3D:
	var key := "gun_paint_" + c.to_html()
	if not _mats.has(key):
		var m := _base(c, 0.42, 0.25)
		m.clearcoat_enabled = true
		m.clearcoat = 0.35
		m.clearcoat_roughness = 0.4
		_mats[key] = m
	return _mats[key]

## Gun materials: a fine grain in the normals and scuffed roughness, so light breaks up
## across the surfaces instead of sliding over flat plastic.
static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: StandardMaterial3D
	match name:
		"gun_metal": m = finish(Color(0.24, 0.25, 0.27), 0.32, 0.85, Color(0.55, 0.55, 0.56), 0.1, 0.18)
		# Blued steel: deep blue-black with a sheen, handling wear rubbed through to
		# the bright steel in places.
		"gun_blued": m = finish(Color(0.1, 0.12, 0.17), 0.24, 0.92, Color(0.5, 0.5, 0.52), 0.07, 0.15)
		# Moulded polymer: dark grey, stippled, satin where hands have polished it.
		"gun_polymer": m = finish(Color(0.075, 0.077, 0.08), 0.62, 0.0, Color(0.11, 0.11, 0.115), 0.25, 0.45)
		"gun_brass": m = _base(Color(0.78, 0.6, 0.3), 0.3, 1.0)
		"gun_iron": m = _base(Color(0.32, 0.31, 0.3), 0.5, 0.8)
		"gun_bone": m = _base(Color(0.86, 0.8, 0.66), 0.45, 0.0)
		"gun_fletch": m = _base(Color(0.82, 0.8, 0.76), 0.85, 0.0)
		"gun_string": m = _base(Color(0.78, 0.72, 0.58), 0.9, 0.0)
		"gun_leather": m = Materials._pbr(Color(0.3, 0.18, 0.1), 0.75, 0.0, "cloth", 0.15, 1.0, 0.6)
		_:
			var wood := name.trim_suffix("_x").trim_suffix("_y")
			if WOOD.has(wood):
				return _wood(name, WOOD[wood], name.right(2))
			return _glow(name) if GLOW.has(name) else Materials.get_mat(name)
	_mats[name] = m
	return m

## Wood: [dark grain, light grain, roughness]. "gun_walnut" runs its grain along Z (a
## stock); "gun_walnut_y" and "_x" along those axes (a grip, a bow limb).
const WOOD := {"gun_walnut": [Color(0.2, 0.1, 0.05), Color(0.46, 0.27, 0.14), 0.42],
	"gun_ash": [Color(0.44, 0.32, 0.2), Color(0.7, 0.57, 0.4), 0.55],
	"gun_ebony": [Color(0.05, 0.04, 0.045), Color(0.17, 0.13, 0.13), 0.35]}
static var _wood_noise: FastNoiseLite
static var _wood_normal: NoiseTexture2D
static var _wood_albedo: Dictionary = {}

## Fine wood grain: noise stretched many times along the grain, so it reads as long
## streaks and flecks across it, never as boards. Varnished, a soft clearcoat.
static func _wood(key: String, spec: Array, axis: String) -> StandardMaterial3D:
	if _wood_noise == null:
		_wood_noise = FastNoiseLite.new()
		_wood_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_wood_noise.frequency = 0.03
		_wood_noise.fractal_octaves = 4
		_wood_noise.fractal_lacunarity = 2.6
		_wood_normal = NoiseTexture2D.new()
		_wood_normal.seamless = true
		_wood_normal.noise = _wood_noise
		_wood_normal.as_normal_map = true
		_wood_normal.bump_strength = 1.5
	var dark: Color = spec[0]
	var light: Color = spec[1]
	if not _wood_albedo.has(dark):
		# Mostly mid-tone wood with darker grain lines and lighter flecks.
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])
		g.colors = PackedColorArray([dark, dark.lerp(light, 0.55), light.lerp(dark, 0.2), dark.lerp(light, 0.45), light])
		var alb := NoiseTexture2D.new()
		alb.seamless = true
		alb.noise = _wood_noise
		alb.color_ramp = g
		_wood_albedo[dark] = alb
	var m := StandardMaterial3D.new()
	m.albedo_texture = _wood_albedo[dark]
	m.roughness = spec[2]
	m.normal_enabled = true
	m.normal_texture = _wood_normal
	m.normal_scale = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.35
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	# Grain lines a few millimetres apart across, stretched some 15x along.
	var across := 14.0
	var along := 0.9
	m.uv1_scale = Vector3(along if axis == "_x" else across, along if axis == "_y" else across, across if axis in ["_x", "_y"] else along)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

static var _wear_noise: FastNoiseLite

## A worn finish: colour `c`, with patches of `wear_c` (bare metal showing through,
## polished spots) over `wear` of the surface, roughness drifting a good deal more than
## _base's, and a grain of strength `bump` in the normals.
static func finish(c: Color, rough: float, metal: float, wear_c: Color, wear: float, bump: float) -> StandardMaterial3D:
	var m := _base(Color.WHITE, rough, metal)
	if _wear_noise == null:
		_wear_noise = FastNoiseLite.new()
		_wear_noise.frequency = 0.02
		_wear_noise.fractal_octaves = 5
		_wear_noise.fractal_gain = 0.6
	var g := Gradient.new()
	var edge := clampf(1.0 - wear, 0.05, 0.98)
	g.offsets = PackedFloat32Array([0.0, 0.45, edge - 0.03, edge, 1.0])
	g.colors = PackedColorArray([c * 0.8, c, c * 1.12, wear_c, wear_c])
	var t := NoiseTexture2D.new()
	t.seamless = true
	t.noise = _wear_noise
	t.color_ramp = g
	m.albedo_texture = t
	var r := NoiseTexture2D.new()
	r.seamless = true
	r.noise = _wear_noise
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1))
	rg.set_color(1, Color(0.5, 0.5, 0.5))
	r.color_ramp = rg
	m.roughness_texture = r
	m.roughness = minf(rough * 1.3, 1.0)
	m.normal_scale = bump
	return m

static func _base(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	if _grain == null:
		_grain = NoiseTexture2D.new()
		_grain.seamless = true
		_grain.as_normal_map = true
		_grain.bump_strength = 0.6
		var n := FastNoiseLite.new()
		n.frequency = 0.12
		_grain.noise = n
		_scuff = NoiseTexture2D.new()
		_scuff.seamless = true
		var s := FastNoiseLite.new()
		s.frequency = 0.03
		s.fractal_octaves = 4
		_scuff.noise = s
		# Roughness only drifts a little (worn spots a touch shinier), never to a mirror.
		var g := Gradient.new()
		g.set_color(0, Color(0.8, 0.8, 0.8))
		g.set_color(1, Color(1, 1, 1))
		_scuff.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.6
	m.normal_enabled = true
	m.normal_texture = _grain
	m.normal_scale = 0.12
	m.roughness_texture = _scuff
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m

static func _commit(k: MeshKit) -> ArrayMesh:
	return k.commit(GunLook.mat)

## Along -Z (the way guns point) for the kit's cylinders, which run up +Y.
static func _z(at: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), at)

## Turns the kit's +Y cylinders to run along `d`.
static func _along(d: Vector3) -> Basis:
	var n := d.normalized()
	var ax := Vector3.UP.cross(n)
	return Basis(ax.normalized(), Vector3.UP.angle_to(n)) if ax.length() > 0.001 else (Basis() if n.y > 0 else Basis(Vector3.RIGHT, PI))

## A six-shot revolver: blued frame and barrel with an underlug, a fluted cylinder, brass
## pins, a curved walnut grip, hammer, trigger and guard.
static func _revolver() -> ArrayMesh:
	var k := MeshKit.new(7)
	var I := Transform3D.IDENTITY
	# Grip: an oval section swept down and back in a gentle curve, with brass escutcheons.
	var prev := Vector3(0, 0.0, 0.018)
	for n in range(1, 7):
		var f := n / 6.0
		var p := Vector3(0, -0.085 * f, 0.018 + 0.026 * f + 0.02 * f * f)
		var d := p - prev
		var b := _along(d) * Basis.from_scale(Vector3(0.75, 1, 1))
		k.cylinder("gun_walnut_y", Transform3D(b, prev), 0.017 + 0.003 * sin(f * PI), 0.017 + 0.003 * sin(f * PI), d.length() * 1.2, 12)
		prev = p
	k.cylinder("gun_brass", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.0145, -0.05, 0.032)), 0.004, 0.004, 0.029, 8)
	k.box("gun_blued", Transform3D(Basis(Vector3(1, 0, 0), 0.45), Vector3(0, -0.102, 0.06)), Vector3(0.03, 0.008, 0.04))
	# Frame: the backstrap over the grip, the body around the cylinder, the top strap.
	k.box("gun_blued", I.translated(Vector3(0, 0.012, 0.012)), Vector3(0.022, 0.03, 0.03))
	k.box("gun_blued", I.translated(Vector3(0, 0.02, -0.032)), Vector3(0.02, 0.046, 0.062))
	k.box("gun_blued", I.translated(Vector3(0, 0.054, -0.03)), Vector3(0.016, 0.008, 0.074))
	# Cylinder with six chambers and flutes.
	k.cylinder("gun_metal", _z(Vector3(0, 0.032, -0.012)), 0.0205, 0.0205, 0.042, 18)
	for c in 6:
		var a := TAU * c / 6.0
		var off := Vector3(cos(a) * 0.012, 0.032 + sin(a) * 0.012, -0.0545)
		k.cylinder("gun_polymer", _z(off), 0.0042, 0.0042, 0.002, 8)
		var fa := a + PI / 6.0
		k.box("gun_blued", Transform3D(Basis(Vector3(0, 0, 1), fa), Vector3(cos(fa) * 0.0195, 0.032 + sin(fa) * 0.0195, -0.033)), Vector3(0.004, 0.006, 0.028))
	k.cylinder("gun_brass", _z(Vector3(0, 0.032, -0.055)), 0.003, 0.003, 0.004, 8)
	# Barrel with its underlug and ejector rod, a blade sight at the muzzle.
	k.cylinder("gun_blued", _z(Vector3(0, 0.044, -0.06)), 0.0085, 0.0078, 0.135, 14)
	k.box("gun_blued", I.translated(Vector3(0, 0.032, -0.115)), Vector3(0.011, 0.013, 0.11))
	k.cylinder("gun_metal", _z(Vector3(0, 0.024, -0.064)), 0.003, 0.003, 0.11, 8)
	k.box("gun_blued", I.translated(Vector3(0, 0.055, -0.188)), Vector3(0.003, 0.008, 0.012))
	k.cylinder("gun_polymer", _z(Vector3(0, 0.044, -0.1955)), 0.004, 0.004, 0.001, 10)
	# Rear notch, hammer and spur.
	k.box("gun_blued", I.translated(Vector3(0, 0.06, 0.004)), Vector3(0.012, 0.005, 0.006))
	k.box("gun_metal", Transform3D(Basis(Vector3(1, 0, 0), -0.5), Vector3(0, 0.05, 0.022)), Vector3(0.008, 0.03, 0.01))
	k.box("gun_metal", Transform3D(Basis(Vector3(1, 0, 0), 0.4), Vector3(0, 0.066, 0.03)), Vector3(0.01, 0.006, 0.014))
	# Trigger and guard.
	k.box("gun_metal", Transform3D(Basis(Vector3(1, 0, 0), 0.35), Vector3(0, -0.012, -0.014)), Vector3(0.005, 0.022, 0.006))
	k.box("gun_blued", I.translated(Vector3(0, -0.028, -0.02)), Vector3(0.008, 0.004, 0.04))
	k.box("gun_blued", Transform3D(Basis(Vector3(1, 0, 0), 0.4), Vector3(0, -0.016, -0.04)), Vector3(0.008, 0.026, 0.004))
	var out := _commit(k)
	out.set_meta("grip", Vector3(0, -0.04, 0.034))
	return out

## A smooth, rounded-rectangle tube through `pts`: half-widths `ws` and half-heights `hs`
## at each point (heights measured toward `up`). Ends capped. Stocks, grips and limbs.
static func _loft(k: MeshKit, m: String, pts: Array, ws: Array, hs: Array, up := Vector3.UP, segs := 16) -> void:
	var I := Transform3D.IDENTITY
	var rings: Array = []
	var norms: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var x := up.cross(t).normalized()
		var y := t.cross(x).normalized()
		var ring: Array = []
		var nr: Array = []
		var w: float = ws[i]
		var h: float = hs[i]
		for j in segs:
			var a := TAU * j / segs
			var c := cos(a)
			var sn := sin(a)
			# Superellipse (power 4): flat sides, rounded corners.
			var px := w * signf(c) * pow(absf(c), 0.5)
			var py := h * signf(sn) * pow(absf(sn), 0.5)
			ring.append(p + x * px + y * py)
			var nx := signf(px) * pow(absf(px / w), 3.0) / w
			var ny := signf(py) * pow(absf(py / h), 3.0) / h
			nr.append((x * nx + y * ny).normalized())
		rings.append(ring)
		norms.append(nr)
	for i in pts.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][j2]
			var c: Vector3 = rings[i + 1][j2]
			var d: Vector3 = rings[i + 1][j]
			var na: Vector3 = norms[i][j]
			var nb: Vector3 = norms[i][j2]
			var nc: Vector3 = norms[i + 1][j2]
			var nd: Vector3 = norms[i + 1][j]
			if (b - a).cross(c - a).dot(na + nc) > 0.0:
				k.tri(m, I, a, b, c, na, nb, nc)
				k.tri(m, I, a, c, d, na, nc, nd)
			else:
				k.tri(m, I, a, c, b, na, nc, nb)
				k.tri(m, I, a, d, c, na, nd, nc)
	for e in [0, pts.size() - 1]:
		var n: Vector3 = ((pts[e] - pts[1]) if e == 0 else (pts[e] - pts[e - 1])).normalized()
		for j in segs:
			var a: Vector3 = pts[e]
			var b: Vector3 = rings[e][j]
			var c: Vector3 = rings[e][(j + 1) % segs]
			if (b - a).cross(c - a).dot(n) > 0.0:
				k.tri(m, I, a, b, c, n, n, n)
			else:
				k.tri(m, I, a, c, b, n, n, n)

## A straight loft along -Z from z0 to z1 (a band, a strip): a short tube.
static func _sleeve(k: MeshKit, m: String, at: Vector3, len: float, w: float, h: float) -> void:
	_loft(k, m, [at + Vector3(0, 0, len * 0.5), at - Vector3(0, 0, len * 0.5)], [w, w], [h, h])

## A thin rod through `pts` (a stirrup, a string, a lever).
static func _rod(k: MeshKit, m: String, pts: Array, r: float, segs := 6) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var d: Vector3 = pts[i + 1] - a
		k.cylinder(m, Transform3D(_along(d), a), r, r, d.length(), segs, i == 0 or i == pts.size() - 2)

## A medieval crossbow held like a pistol: a shaped walnut tiller with bone inlays and a
## short butt, a raked grip, a laminated recurve prod lashed to the nose with cord, the
## string spanned back to a horn nut, a bolt in the groove, an iron trigger and a stirrup.
## The runic repeater is ebony and blued steel with a bolt magazine and glowing runes.
static func _crossbow(runic: bool) -> ArrayMesh:
	var k := MeshKit.new(11)
	var I := Transform3D.IDENTITY
	var wood := "gun_ebony" if runic else "gun_walnut"
	var metal := "gun_blued" if runic else "gun_iron"
	var trim := "glow_violet" if runic else "gun_bone"
	# Tiller: a short butt behind the grip, the wrist, and the long fore-end to the nose.
	var tz := [0.15, 0.12, 0.08, 0.03, -0.04, -0.16, -0.3, -0.36, -0.4, -0.42]
	var ty := [-0.022, -0.016, -0.004, 0.004, 0.008, 0.01, 0.011, 0.011, 0.011, 0.011]
	var tw := [0.017, 0.019, 0.016, 0.017, 0.019, 0.018, 0.017, 0.02, 0.02, 0.016]
	var th := [0.034, 0.036, 0.024, 0.02, 0.019, 0.017, 0.016, 0.019, 0.019, 0.015]
	var pts: Array = []
	for i in tz.size():
		pts.append(Vector3(0, ty[i], tz[i]))
	_loft(k, wood, pts, tw, th)
	# Inlaid strips along both sides of the butt and fore-end.
	for side in [-1.0, 1.0]:
		k.box(trim, I.translated(Vector3(side * 0.0185, -0.014, 0.12)), Vector3(0.0015, 0.006, 0.05))
		k.box(trim, I.translated(Vector3(side * 0.0175, 0.012, -0.2)), Vector3(0.0015, 0.004, 0.16 if not runic else 0.2))
	# Iron bands at the wrist and behind the prod.
	_sleeve(k, metal, Vector3(0, 0.007, 0.055), 0.012, 0.0185, 0.0235)
	_sleeve(k, metal, Vector3(0, 0.011, -0.325), 0.012, 0.0185, 0.018)
	# The bolt groove on top, from the nut to the nose.
	k.box("gun_polymer", I.translated(Vector3(0, 0.0272, -0.21)), Vector3(0.005, 0.002, 0.36))
	# Raked grip under the wrist, swelling to a pommel.
	var gd := Vector3(0, -1, 0.3).normalized()
	var g0 := Vector3(0, -0.004, 0.035)
	_loft(k, wood + "_y", [g0, g0 + gd * 0.03, g0 + gd * 0.07, g0 + gd * 0.098, g0 + gd * 0.108],
		[0.0135, 0.0135, 0.0145, 0.016, 0.012], [0.018, 0.019, 0.02, 0.022, 0.016], Vector3.FORWARD)
	# Trigger: a curved iron blade ahead of the grip.
	_rod(k, metal, [Vector3(0, -0.008, 0.0), Vector3(0, -0.02, 0.006), Vector3(0, -0.034, 0.016), Vector3(0, -0.04, 0.03)], 0.0035)
	# Horn nut that holds the string, set into the tiller.
	k.cylinder("gun_bone", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.016, 0.027, -0.035)), 0.011, 0.011, 0.032, 14)
	# Prod: tapering laminated limbs bent back by the spanned string, tips flicked forward.
	var nose := Vector3(0, 0.011, -0.375)
	var span := 0.3
	var nut := Vector3(0, 0.035, -0.036)
	for side in [-1.0, 1.0]:
		var lp: Array = []
		var lw: Array = []
		var lh: Array = []
		for n in 11:
			var f := n / 10.0
			var bend := 0.085 * pow(f, 1.6)
			if f > 0.8:
				bend -= 0.05 * pow((f - 0.8) / 0.2, 2.0)
			lp.append(nose + Vector3(side * (f * span), 0.0, bend))
			lw.append(lerpf(0.009, 0.0045, f)) # thickness, front to back
			lh.append(lerpf(0.022, 0.009, f)) # depth, top to bottom
		lp[0] = nose + Vector3(-side * 0.012, 0, 0)
		_loft(k, (wood if runic else "gun_ash") + "_x", lp, lh, lw, Vector3.BACK, 12)
		var tip: Vector3 = lp[-1]
		# Horn nocks on the tips.
		k.sphere(trim, I.translated(tip), 0.007, 5, 8)
		# The string: from the tip back to the nut.
		_rod(k, "gun_string", [tip, nut + Vector3(side * 0.004, 0, 0)], 0.0016, 5)
		# Leather wrapping where the limb leaves the tiller.
		k.cylinder("gun_leather", Transform3D(Basis(Vector3(0, 0, 1), -side * PI * 0.5), nose + Vector3(side * 0.02, 0, 0.0)), 0.014, 0.012, 0.03, 10)
	# Cord lashing the prod to the nose, crossing over and under.
	for n in 4:
		var z := -0.36 - n * 0.006
		_sleeve(k, "gun_string", Vector3(0, 0.011, z), 0.004, 0.0215, 0.0205)
	# Stirrup: an iron loop ahead of the nose, to brace with a foot while spanning.
	_rod(k, metal, [Vector3(-0.016, 0.011, -0.41), Vector3(-0.032, 0.008, -0.45), Vector3(-0.026, 0.005, -0.485),
		Vector3(0.026, 0.005, -0.485), Vector3(0.032, 0.008, -0.45), Vector3(0.016, 0.011, -0.41)], 0.0032)
	# A loaded bolt in the groove: ash shaft, two vanes, an iron bodkin head.
	k.cylinder("gun_ash", _z(Vector3(0, 0.033, -0.045)), 0.0042, 0.0042, 0.3, 8)
	k.cylinder(metal, _z(Vector3(0, 0.033, -0.345)), 0.0055, 0.0, 0.035, 8)
	for side in [-1.0, 1.0]:
		k.box("gun_leather" if runic else "gun_fletch", Transform3D(Basis(Vector3(0, 0, 1), side * 0.6), Vector3(side * 0.006, 0.037, -0.08)), Vector3(0.0012, 0.011, 0.05))
	if runic:
		# Repeater magazine over the groove, and runes glowing along both cheeks.
		_loft(k, "gun_ebony", [Vector3(0, 0.068, -0.05), Vector3(0, 0.068, -0.19)], [0.015, 0.015], [0.028, 0.028])
		_sleeve(k, metal, Vector3(0, 0.068, -0.06), 0.006, 0.0165, 0.0295)
		_sleeve(k, metal, Vector3(0, 0.068, -0.18), 0.006, 0.0165, 0.0295)
		for n in 6:
			for side in [-1.0, 1.0]:
				k.box("glow_violet", I.translated(Vector3(side * 0.0172, 0.004, -0.1 - n * 0.035)), Vector3(0.0015, 0.01 if n % 2 == 0 else 0.005, 0.01))
	var out := _commit(k)
	out.set_meta("grip", g0 + gd * 0.05)
	return out
