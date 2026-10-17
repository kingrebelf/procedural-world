class_name GunLook
## How the ranged weapons look: the sci-fi kit guns re-skinned with proper materials
## (gunmetal, matte polymer, a painted body and glowing energy strips in place of the
## kit's flat white and orange), and the period weapons (revolver, crossbows) forged from
## parts in wood, iron and brass. Guns point along -Z with the grip at the origin.

## Item type -> [kit model, scale, body paint, accent]. The accent is a glow material
## name (energy weapons) or a paint colour.
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

static func has(t: String) -> bool:
	return KIT.has(t) or t in ["scrap_pistol", "crossbow", "crossbow_runic"]

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
	return null

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
			return _glow(accent) if accent is String else _paint(accent)
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
const GLOW := {"glow_cyan": Color(0.2, 0.85, 1.0), "glow_teal": Color(0.2, 1.0, 0.8),
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
		"gun_metal": m = _base(Color(0.2, 0.21, 0.23), 0.34, 0.85)
		"gun_blued": m = _base(Color(0.11, 0.12, 0.15), 0.3, 0.9)
		"gun_polymer": m = _base(Color(0.045, 0.047, 0.05), 0.68, 0.0)
		"gun_brass": m = _base(Color(0.78, 0.6, 0.3), 0.3, 1.0)
		"gun_iron": m = _base(Color(0.32, 0.31, 0.3), 0.5, 0.8)
		"gun_walnut":
			m = Materials._pbr(Color(0.36, 0.2, 0.11), 0.5, 0.0, "planks", 0.03, 0.5, 0.6)
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
			m.uv1_scale *= 4.0
		"gun_ash":
			m = Materials._pbr(Color(0.58, 0.45, 0.3), 0.6, 0.0, "planks", 0.03, 0.5, 0.6)
			m.uv1_scale *= 4.0
		"gun_ebony":
			m = Materials._pbr(Color(0.12, 0.09, 0.1), 0.45, 0.0, "planks", 0.03, 0.5, 0.6)
			m.uv1_scale *= 4.0
		"gun_string": m = _base(Color(0.78, 0.72, 0.58), 0.9, 0.0)
		"gun_leather": m = Materials._pbr(Color(0.3, 0.18, 0.1), 0.75, 0.0, "cloth", 0.15, 1.0, 0.6)
		_:
			return _glow(name) if GLOW.has(name) else Materials.get_mat(name)
	_mats[name] = m
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
		k.cylinder("gun_walnut", Transform3D(b, prev), 0.017 + 0.003 * sin(f * PI), 0.017 + 0.003 * sin(f * PI), d.length() * 1.2, 12)
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
	return _commit(k)

## A crossbow: a wooden tiller with the bolt groove, a steel (or rune-carved) prod with
## its string drawn back to the nut, a stirrup at the nose and an iron trigger lever. The
## runic repeater adds a bolt magazine on top and glowing runes along the stock.
static func _crossbow(runic: bool) -> ArrayMesh:
	var k := MeshKit.new(11)
	var I := Transform3D.IDENTITY
	var wood := "gun_ebony" if runic else "gun_walnut"
	var metal := "gun_blued" if runic else "gun_iron"
	# Stock: the butt under the cheek, the grip, and the long tiller ahead of it.
	k.box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.18), Vector3(0, -0.01, 0.13)), Vector3(0.04, 0.07, 0.16))
	k.box(wood, Transform3D(Basis(Vector3(1, 0, 0), 0.3), Vector3(0, -0.035, 0.02)), Vector3(0.032, 0.07, 0.04))
	k.box(wood, I.translated(Vector3(0, 0.012, -0.17)), Vector3(0.04, 0.034, 0.42))
	k.box(metal, I.translated(Vector3(0, 0.03, -0.17)), Vector3(0.012, 0.003, 0.4))
	# Iron bands round the tiller.
	for z in [-0.05, -0.27, -0.36]:
		k.box(metal, I.translated(Vector3(0, 0.012, z)), Vector3(0.044, 0.038, 0.012))
	# Trigger lever along the underside, and the nut that holds the string.
	k.box(metal, Transform3D(Basis(Vector3(1, 0, 0), -0.12), Vector3(0, -0.012, -0.03)), Vector3(0.008, 0.008, 0.12))
	k.cylinder(metal, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.022, 0.03, -0.06)), 0.012, 0.012, 0.044, 10)
	# Prod: a recurve bent forward from the nose, tips swept back.
	var nose := Vector3(0, 0.022, -0.37)
	var tip_half := 0.3
	var prev := Vector3.ZERO
	var prod := "gun_iron" if not runic else "gun_ebony"
	for side in [-1.0, 1.0]:
		prev = nose
		for n in range(1, 9):
			var f := n / 8.0
			var p := nose + Vector3(side * f * tip_half, 0, 0.06 * f * f - 0.02 * sin(f * PI))
			var d := p - prev
			var b := _along(d)
			var r := lerpf(0.011, 0.006, f)
			k.cylinder(prod, Transform3D(b, prev), r, r * 0.9, d.length(), 8)
			prev = p
		# The string, from the tip back to the nut.
		var tip: Vector3 = prev
		var nut := Vector3(0, 0.03, -0.065)
		var sd := nut - tip
		k.cylinder("gun_string", Transform3D(_along(sd), tip), 0.0018, 0.0018, sd.length(), 4)
		if runic:
			k.sphere("glow_violet", I.translated(tip), 0.009, 4, 6)
	# Stirrup at the nose, to brace it with a foot while spanning.
	k.box(metal, I.translated(Vector3(0, -0.02, -0.405)), Vector3(0.07, 0.008, 0.01))
	k.box(metal, I.translated(Vector3(0.033, 0.0, -0.405)), Vector3(0.006, 0.05, 0.01))
	k.box(metal, I.translated(Vector3(-0.033, 0.0, -0.405)), Vector3(0.006, 0.05, 0.01))
	# A loaded bolt in the groove.
	k.cylinder("gun_ash", _z(Vector3(0, 0.038, -0.07)), 0.004, 0.004, 0.27, 6)
	k.cylinder(metal, _z(Vector3(0, 0.038, -0.34)), 0.006, 0.0, 0.03, 6)
	if runic:
		# Repeater magazine over the groove, and runes glowing along both cheeks.
		k.box("gun_ebony", I.translated(Vector3(0, 0.07, -0.12)), Vector3(0.03, 0.06, 0.14))
		k.box(metal, I.translated(Vector3(0, 0.102, -0.12)), Vector3(0.034, 0.006, 0.146))
		for n in 5:
			for side in [-1.0, 1.0]:
				k.box("glow_violet", I.translated(Vector3(side * 0.0205, 0.012, -0.1 - n * 0.05)), Vector3(0.002, 0.012 if n % 2 == 0 else 0.006, 0.014))
	else:
		k.box("gun_leather", Transform3D(Basis(Vector3(1, 0, 0), 0.18), Vector3(0, 0.026, 0.13)), Vector3(0.042, 0.004, 0.12))
	return _commit(k)
