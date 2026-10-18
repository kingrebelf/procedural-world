class_name WearModels
## Wearables held in the hand, each the shape its icon shows rather than one shape per
## material: a great helm is a flat-topped barrel with eye slits, a cowboy hat has its
## pinched crown and curled brim, a gas mask has its eyepieces and filter, a pocket watch
## is a watch and not a cord with a speck on it. ItemModels._armour asks here first and
## falls back to its own shapes (dome, cuirass, gauntlet, greave, boot) for the rest.
##
## Same conventions as ItemModels: held by the rim or the strap, front (the face the icon
## shows) on +Z, up +Y; `m` and `c` are the piece's material and colour from its look.

const BUILD := {
	# Head.
	"helm_iron": "_great_helm", "helm_steel": "_great_helm",
	"helm_bronze": "_cheek_helm", "helm_elven": "_leaf_helm",
	"cap_cloth": "_tied_cap", "cap_hide": "_fur_cap", "helm_studded": "_studded_hood",
	"hat_cowboy": "_cowboy_hat", "hardhat_lamp": "_hard_hat", "welding_mask": "_welding_mask",
	"gasmask": "_gas_mask", "helm_brass": "_diving_helmet",
	"helm_visor": "_tac_helmet", "helm_recon": "_tac_helmet", "helm_combat": "_tac_helmet",
	"helm_power": "_tac_helmet", "helm_void": "_tac_helmet", "helm_star": "_tac_helmet",
	"helm_precursor": "_tac_helmet", "helm_eva": "_eva_helmet", "helm_stealth": "_stealth_hood",
	"helm_chitin": "_chitin_helm", "helm_crystal": "_crystal_tiara",
	# Neck: the thing itself, with only a short fold of its cord or chain.
	"lucky_coin": "_coin_pendant", "amulet_bone": "_tooth_pendant", "amulet_silver": "_locket",
	"amulet_saint": "_medallion", "amulet_hive": "_medallion", "amulet_precursor": "_medallion",
	"bandana": "_bandana", "pocket_watch": "_pocket_watch", "compass": "_compass",
	"compass_void": "_compass", "sheriff_star": "_star_badge", "spectacles": "_spectacles",
	"dog_tags": "_dog_tags", "medal": "_medal", "headset": "_headset",
	"hack_tablet": "_tablet", "motion_tracker": "_tracker", "earring_nebula": "_earring",
	# Rings.
	"ring_ruby": "_signet", "ring_void": "_signet", "ring_star": "_gem_band",
	"bracelet_crystal": "_crystal_bracelet", "lucky_charm_dice": "_fuzzy_dice",
}

static func has(t: String) -> bool:
	return BUILD.has(t)

static func build(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	Callable(WearModels, BUILD[t]).call(k, r, t, m, c, style)

const BRASS := Color(0.78, 0.6, 0.3)
const GOLD := Color(0.95, 0.76, 0.38)
const DARK := Color(0.04, 0.04, 0.045)

static func _dot(k: MeshKit, m: String, p: Vector3, r: float, col: Color) -> void:
	k.sphere(m, Transform3D(Basis.IDENTITY, p), r, 4, 6, 0.0, 1.0, col)

static func _ring_pts(r: float, y: float, n: int, a0 := 0.0, a1 := TAU, z_scale := 1.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(Vector3(sin(a) * r, y, cos(a) * r * z_scale))
	return out

static func _line(k: MeshKit, m: String, pts: PackedVector3Array, rad: float, col: Color, segs := 5) -> void:
	var radii := PackedFloat32Array()
	radii.resize(pts.size())
	radii.fill(rad)
	ItemModels._tube(k, m, Transform3D.IDENTITY, pts, radii, segs, col)

# --- Head -------------------------------------------------------------------------------

## A great helm: a flat-topped barrel of plate closed all round, a slit for the eyes split
## by a reinforcing cross, breaths pierced low on the right, rivets round the crown. The
## steel one is trimmed in gilt with crosses on the cheeks.
static func _great_helm(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var R := 0.106
	var y0 := -0.12
	var H := 0.3
	# Plate steel reads mid grey in the icons, darker than the worn look's tint.
	c = c.darkened(0.3)
	var shell := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		# Flattened a little at the face, swelling slightly over the brow.
		# The crown rolls in to the top plate, so the top edge is a rounded shoulder.
		var sh := 1.0 - 0.12 * pow(maxf(v - 0.82, 0.0) / 0.18, 2.0)
		var rr := R * (1.0 - 0.06 * pow(maxf(cos(a), 0.0), 3.0)) * (1.0 + 0.03 * sin(v * PI)) * sh
		return Vector3(sin(a) * rr, y0 + v * H, cos(a) * rr * 1.08)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, shell, 32, 8, 0.004, c, Color(0.1, 0.09, 0.08), "im:linen")
	# The crown: a low dome riveted on.
	var top := y0 + H
	var dome := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var rr := R * 0.88 * (1.0 - v * v)
		return Vector3(sin(a) * rr, top + v * 0.03, cos(a) * rr * 1.08)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, dome, 32, 4, 0.004, c.lightened(0.04), c.darkened(0.4))
	for i in 18:
		var a := TAU * i / 18.0
		_dot(k, m, Vector3(sin(a) * (R + 0.003), top - 0.008, cos(a) * (R + 0.003) * 1.08), 0.0028, c.lightened(0.12))
	var trim := GOLD if t == "helm_steel" else BRASS
	var trim_m := "im:metal@0.3"
	# Eye slits: dark recesses either side of the upright of the cross.
	var ey := 0.075
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var a := side * lerpf(0.13, 0.6, i / 4.0)
			var rr := R * (1.0 - 0.06 * pow(maxf(cos(a), 0.0), 3.0)) * 1.03 + 0.009
			ItemModels._block(k, "im:linen", Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * rr, ey, cos(a) * rr * 1.08)), Vector3(0.022, 0.016, 0.004), 0.0, DARK)
	# (Everything laid on the shell stands proud of its outer face, R + its thickness.)
	# The cross: an upright strap from the crown to the chin, and a bar along the slits.
	var up := func(u: float, v: float) -> Vector3:
		var a := (u - 0.5) * 0.16
		var rr := R * 1.03 + 0.008
		return Vector3(sin(a) * rr, y0 + 0.01 + v * (H - 0.03), cos(a) * rr * 1.08 + 0.002)
	ItemModels._sheet(k, trim_m, Transform3D.IDENTITY, up, 2, 8, 0.004, trim, trim.darkened(0.4))
	for row: float in [ey + 0.016, ey - 0.016]:
		var bar := func(u: float, v: float) -> Vector3:
			var a := lerpf(-0.75, 0.75, u)
			var rr := R * (1.0 - 0.06 * pow(maxf(cos(a), 0.0), 3.0)) * 1.03 + 0.011
			return Vector3(sin(a) * rr, row + (v - 0.5) * 0.012, cos(a) * rr * 1.08)
		ItemModels._sheet(k, trim_m, Transform3D.IDENTITY, bar, 10, 1, 0.003, trim, trim.darkened(0.4))
	if t == "helm_steel":
		# Gilt edging round the face plate and a dark cross on each cheek.
		for side: float in [-1.0, 1.0]:
			var a := side * 0.55
			var p := Vector3(sin(a) * (R + 0.006), -0.01, cos(a) * (R + 0.006) * 1.08)
			var bs := Basis(Vector3.UP, a)
			ItemModels._block(k, "im:paint", Transform3D(bs, p), Vector3(0.008, 0.04, 0.002), 0.0, DARK)
			ItemModels._block(k, "im:paint", Transform3D(bs, p + Vector3(0, 0.006, 0)), Vector3(0.03, 0.008, 0.002), 0.0, DARK)
		ItemModels._torus(k, trim_m, Transform3D(Basis.from_scale(Vector3(1, 1, 1.08)), Vector3(0, y0 + 0.004, 0)), R + 0.002, 0.003, 32, 5, trim)
	else:
		# Breaths: a cluster of holes low on the right cheek.
		for i in 9:
			var a := 0.45 + (i % 3) * 0.12
			var y := 0.0 - (i / 3) * 0.022
			var p := Vector3(sin(a) * (R * 1.03 + 0.0075), y, cos(a) * (R * 1.03 + 0.0075) * 1.08)
			ItemModels._disc(k, "im:linen", Transform3D.IDENTITY, p, Vector3(sin(a), 0, cos(a)), 0.004, 8, DARK)

## A bronze helm with a nasal and hinged cheek guards hanging either side of the face,
## riveted bands over the skull.
static func _cheek_helm(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	ItemModels._helm(k, m, c, style, m)
	var R := 0.105
	for side: float in [-1.0, 1.0]:
		var guard := func(u: float, v: float) -> Vector3:
			var a := side * lerpf(0.45, 1.25, u)
			var rr := R + 0.006 - v * 0.012
			return Vector3(sin(a) * rr, 0.05 - v * 0.12, cos(a) * rr)
		ItemModels._sheet(k, m, Transform3D.IDENTITY, guard, 6, 6, 0.004, c, c.darkened(0.45))
		for v: float in [0.25, 0.7]:
			var a := side * 0.85
			_dot(k, m, Vector3(sin(a) * (R + 0.006 - v * 0.012 + 0.003), 0.05 - v * 0.12, cos(a) * (R + 0.006 - v * 0.012 + 0.003)), 0.003, c.lightened(0.15))
	# Riveted bands over the crown, front to back and side to side.
	for rot: float in [0.0, PI * 0.5]:
		var band := PackedVector3Array()
		for i in 13:
			var ph := lerpf(-PI * 0.5, PI * 0.5, i / 12.0)
			band.append(Basis(Vector3.UP, rot) * Vector3(0, 0.06 + cos(ph) * R * 1.05 * 1.03, sin(ph) * R * 1.03))
		_line(k, m, band, 0.005, c.darkened(0.08))

## An elven helm: a close silver skull with leaves rising from the brow and sweeping back
## at the temples, a green stone set over the nose.
static func _leaf_helm(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var silver := Color(0.66, 0.68, 0.66)
	ItemModels._helm(k, "im:metal@0.3", silver, Outfit.STYLE_CRYSTAL, "im:metal@0.3")
	var leaf_c := Color(0.32, 0.55, 0.38)
	for i in 7:
		var a := lerpf(-1.3, 1.3, i / 6.0)
		var tilt := absf(a) * 0.9
		var base := Vector3(sin(a) * 0.105, 0.075, cos(a) * 0.105)
		var out := Vector3(sin(a), 0, cos(a))
		var leaf := func(u: float, v: float) -> Vector3:
			var w := sin(v * PI) * 0.016 * (1.0 - 0.3 * v)
			var dir := (Vector3.UP * cos(tilt) - Vector3(0, 0, 1).rotated(Vector3.UP, a) * sin(tilt) * 0.6).normalized()
			var side := dir.cross(out).normalized()
			return base + dir * v * (0.09 - absf(a) * 0.012) + side * (u - 0.5) * 2.0 * w + out * v * v * 0.02
		ItemModels._sheet(k, "im:metal@0.35", Transform3D.IDENTITY, leaf, 2, 6, 0.002, leaf_c, leaf_c.darkened(0.3))
	k.crystal("im:crystal:helm_elven", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.06, 0.112)), 0.01, 0.012, 6, 0.4, Color(0.2, 0.75, 0.45, 0.9))

## A linen coif tied over the head: soft panels down over the ears, a hem, and a knot at
## the back with its two tails hanging.
static func _tied_cap(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var R := 0.1
	var cap := func(u: float, v: float) -> Vector3:
		var a := (1.0 - u) * TAU
		var ph := v * PI * 0.62
		var sag := 1.0 + 0.03 * sin(a * 5.0) * v
		return Vector3(sin(a) * sin(ph) * R * sag, 0.04 + cos(ph) * R * 0.95, cos(a) * sin(ph) * R * sag)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, cap, 24, 8, 0.004, c, c.darkened(0.25))
	var hem_y := 0.04 + cos(PI * 0.62) * R * 0.95
	ItemModels._torus(k, m, Transform3D(Basis.IDENTITY, Vector3(0, hem_y, 0)), R * sin(PI * 0.62) + 0.002, 0.005, 24, 6, c.darkened(0.08))
	# The knot at the back, its tails falling to one side.
	var kn := Vector3(R * 0.85, hem_y + 0.012, R * 0.3)
	k.sphere(m, Transform3D(Basis.IDENTITY, kn), 0.016, 6, 8, 0.1, 0.8, c.darkened(0.1))
	for i in 2:
		var tail := func(u: float, v: float) -> Vector3:
			var w := lerpf(0.022, 0.012, v)
			return kn + Vector3(0.008 + v * 0.01, -v * 0.085, -0.012 + i * 0.024 + (u - 0.5) * w + sin(v * 3.0) * 0.006)
		ItemModels._sheet(k, m, Transform3D.IDENTITY, tail, 2, 5, 0.003, c, c.darkened(0.25))

## A hide cap: stitched panels over the crown and a deep roll of fur round the brow,
## turned up all round.
static func _fur_cap(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	ItemModels._helm(k, m, c, Outfit.STYLE_LEATHER, "im:hide")
	var fur := Color(0.24, 0.17, 0.12)
	ItemModels._torus(k, "im:fur", Transform3D(Basis.from_scale(Vector3(1, 1.25, 1)), Vector3(0, 0.07, 0)), 0.106, 0.022, 28, 8, fur)
	# Ear flaps, fur-lined, hanging at the sides.
	for side: float in [-1.0, 1.0]:
		var flap := func(u: float, v: float) -> Vector3:
			var a := side * lerpf(1.15, 1.95, u)
			var rr := 0.112 - v * 0.004
			return Vector3(sin(a) * rr, 0.05 - v * 0.075, cos(a) * rr)
		ItemModels._sheet(k, m, Transform3D.IDENTITY, flap, 4, 4, 0.01, c, fur, "im:fur")

## A studded leather hood: it covers the crown, the sides and the nape and falls onto the
## shoulders, open at the face, with rows of iron studs.
static func _studded_hood(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	_hood(k, m, c, 0.0)
	for row in 5:
		for i in 9:
			var v := 0.15 + row * 0.17
			var a := PI + lerpf(-2.2, 2.2, i / 8.0)
			var p := _hood_pt(a, v, 0.0)
			_dot(k, "im:metal@0.45", p * 1.03 + Vector3(0, -0.002, 0), 0.0035, Color(0.42, 0.4, 0.38))

## A point on a hood: `a` round from the face (0 = +Z), `v` from the crown down.
static func _hood_pt(a: float, v: float, peak: float) -> Vector3:
	var R := 0.11
	var ph := v * PI * 0.95
	var rr := R * sin(ph) + maxf(v - 0.55, 0.0) * 0.12
	var y := 0.07 + cos(ph) * R * 1.05 - maxf(v - 0.55, 0.0) * 0.1 + peak * pow(1.0 - v, 4.0) * 0.05
	return Vector3(sin(a) * rr, y, cos(a) * rr - peak * pow(1.0 - v, 3.0) * 0.02)

static func _hood(k: MeshKit, m: String, c: Color, peak: float) -> void:
	# Open at the face: the sides run round the back from one cheek to the other.
	var f := func(u: float, v: float) -> Vector3:
		var open := lerpf(0.0, 0.85, smoothstep(0.15, 0.4, v))
		var a := PI + lerpf(PI - open, -(PI - open), u)
		return _hood_pt(a, v, peak)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, f, 26, 10, 0.006, c, c.darkened(0.45))

## A cowboy hat: a tall crown pinched at the front and creased along the top, a dark band
## round it, and a wide brim curled up at the sides and dipping front and back.
static func _cowboy_hat(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var base := 0.0
	var crown := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var rx := 0.078 * (1.0 - 0.12 * v)
		var rz := 0.092 * (1.0 - 0.12 * v)
		var p := Vector3(sin(a) * rx, base + v * 0.11, cos(a) * rz)
		# The pinch at the front and the crease along the top.
		p.x *= 1.0 - 0.35 * v * v * pow(maxf(cos(a), 0.0), 4.0)
		p.y -= 0.025 * pow(v, 6.0) * (1.0 - absf(sin(a)) * 0.6)
		return p
	ItemModels._sheet(k, m, Transform3D.IDENTITY, crown, 28, 8, 0.004, c, c.darkened(0.4))
	ItemModels._disc(k, m, Transform3D.IDENTITY, Vector3(0, base + 0.085, 0), Vector3.UP, 0.07, 20, c.darkened(0.05))
	k.cylinder("leather", Transform3D(Basis.from_scale(Vector3(1, 1, 1.18)), Vector3(0, base + 0.005, 0)), 0.08, 0.079, 0.02, 28, false, 0.0, 1, Color(0.35, 0.25, 0.18))
	var brim := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var rr := lerpf(0.078, 0.175, v)
		var curl := 0.06 * pow(v, 2.2) * pow(absf(sin(a)), 2.0) - 0.012 * v * pow(absf(cos(a)), 2.0)
		return Vector3(sin(a) * rr, base + curl, cos(a) * rr * 1.12)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, brim, 36, 5, 0.005, c, c.darkened(0.25))
	# A row of studs on the band, and its buckle.
	for i in 7:
		var a := lerpf(-0.9, 0.9, i / 6.0)
		_dot(k, "im:metal@0.35", Vector3(sin(a) * 0.081, base + 0.005, cos(a) * 0.081 * 1.18), 0.0035, Color(0.7, 0.66, 0.6))

## A miner's hard hat: a ridged shell with a short brim, a lamp bracket on the front with
## its lamp, and a leather band.
static func _hard_hat(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var shell := func(u: float, v: float) -> Vector3:
		var a := (1.0 - u) * TAU
		var ph := v * PI * 0.5
		return Vector3(sin(a) * sin(ph) * 0.1, 0.02 + cos(ph) * 0.1, cos(a) * sin(ph) * 0.118)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, shell, 28, 8, 0.005, c, Color(0.12, 0.1, 0.08))
	# The ridge over the crown.
	var ridge := PackedVector3Array()
	for i in 11:
		var ph := lerpf(-PI * 0.42, PI * 0.42, i / 10.0)
		ridge.append(Vector3(0, 0.02 + cos(ph) * 0.104, sin(ph) * 0.122))
	_line(k, m, ridge, 0.008, c.darkened(0.05), 6)
	var brim := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var rr := lerpf(0.1, 0.12 + 0.025 * maxf(cos(a), 0.0), v)
		return Vector3(sin(a) * rr, 0.02 - v * 0.008, cos(a) * rr * 1.18)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, brim, 28, 2, 0.005, c, c.darkened(0.3))
	k.cylinder("leather", Transform3D(Basis.from_scale(Vector3(1, 1, 1.18)), Vector3(0, 0.025, 0)), 0.101, 0.1, 0.018, 24, false, 0.0, 1, Color(0.36, 0.26, 0.17))
	# The lamp: a brass housing with a lens (an oil lamp of the era: no glow when carried).
	var lamp := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.075, 0.125))
	ItemModels._block(k, "im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0.112)), Vector3(0.03, 0.04, 0.012), 0.003, BRASS)
	k.cylinder("im:metal@0.35", lamp, 0.022, 0.018, 0.035, 16, true, 0.0, 1, BRASS)
	ItemModels._disc(k, "im:glass", Transform3D.IDENTITY, Vector3(0, 0.075, 0.143), Vector3.BACK, 0.017, 16, Color(1.0, 0.9, 0.7, 0.6))
	ItemModels._torus(k, "im:metal@0.35", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.075, 0.143)), 0.019, 0.0025, 16, 4, BRASS)

## A welding mask: a curved shield over the face with a dark glass window at the eyes, a
## head harness behind and pivot knobs at the sides.
static func _welding_mask(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var shield := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.2, 1.2, u)
		var rr := 0.12 * (1.0 - 0.25 * pow(1.0 - v, 2.0) * absf(sin(a)))
		return Vector3(sin(a) * rr, -0.09 + v * 0.23, cos(a) * rr * (1.0 + 0.25 * (1.0 - v)))
	ItemModels._sheet(k, m, Transform3D.IDENTITY, shield, 16, 8, 0.004, c, c.darkened(0.4))
	# The window and its frame.
	ItemModels._block(k, "im:metal@0.5", Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.125)), Vector3(0.1, 0.04, 0.008), 0.002, c.darkened(0.2))
	ItemModels._block(k, "im:visor", Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.13)), Vector3(0.082, 0.026, 0.004), 0.0, Color(0.02, 0.03, 0.025))
	# Rivets round the edge.
	for i in 12:
		var a := lerpf(-1.1, 1.1, i / 11.0)
		_dot(k, m, Vector3(sin(a) * 0.123, 0.13, cos(a) * 0.123), 0.003, c.lightened(0.1))
	# Harness: a band round the head and one over the crown, knobs at the pivots.
	_line(k, "leather", _ring_pts(0.1, 0.05, 20, PI * 0.55, PI * 1.45), 0.006, Color.WHITE)
	var over := PackedVector3Array()
	for i in 9:
		var ph := lerpf(0.0, PI * 0.5, i / 8.0)
		over.append(Vector3(0, 0.05 + sin(ph) * 0.1, -cos(ph) * 0.1))
	_line(k, "leather", over, 0.006, Color.WHITE)
	for side: float in [-1.0, 1.0]:
		k.cylinder("im:metal@0.5", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.118, 0.05, 0.01)), 0.012, 0.012, 0.012, 12, true, 0.0, 1, c.darkened(0.3))

## A gas mask: a moulded rubber face piece with two round glass eyepieces in brass rims, a
## round filter canister on the snout, straps behind.
static func _gas_mask(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var rub := Color(0.2, 0.17, 0.15)
	var face := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.5, 1.5, u)
		var y := -0.08 + v * 0.2
		var rr := 0.085 * (0.75 + 0.25 * sin(v * PI)) + 0.012 * exp(-pow((v - 0.25) / 0.2, 2.0)) * cos(a)
		return Vector3(sin(a) * rr, y, cos(a) * rr * 1.15)
	ItemModels._sheet(k, "im:rubber", Transform3D.IDENTITY, face, 18, 10, 0.006, rub, rub.darkened(0.4))
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 0.04, 0.05, 0.093)
		var n := Vector3(side * 0.35, 0.05, 1.0).normalized()
		var bs := Basis(Vector3.UP.cross(n).normalized(), n.cross(Vector3.UP.cross(n).normalized()), n) if absf(n.y) < 0.99 else Basis.IDENTITY
		k.cylinder("im:metal@0.35", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), p - n * 0.007), 0.026, 0.026, 0.014, 18, true, 0.0, 1, BRASS.darkened(0.25))
		# Dark glass eyes in a raised brass ring, as the icon paints them.
		ItemModels._disc(k, "im:visor", Transform3D.IDENTITY, p + n * 0.0075, n, 0.021, 18, Color(0.06, 0.07, 0.08))
		ItemModels._torus(k, "im:metal@0.3", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), p + n * 0.0075), 0.022, 0.003, 20, 5, BRASS)
	# The filter: a ribbed canister on the snout, pointing down and forward.
	var fx := Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.6), Vector3(0, -0.04, 0.11))
	# A brass canister, its face a dark grille of rings.
	k.cylinder("im:metal@0.4", fx * Transform3D(Basis.IDENTITY, Vector3(0, -0.025, 0)), 0.036, 0.036, 0.05, 20, true, 0.0, 1, BRASS.darkened(0.2))
	for i in 4:
		ItemModels._torus(k, "im:metal@0.4", fx * Transform3D(Basis.IDENTITY, Vector3(0, -0.02 + i * 0.013, 0)), 0.0365, 0.0025, 20, 4, BRASS.darkened(0.35))
	ItemModels._disc(k, "im:metal@0.6", fx, Vector3(0, 0.0255, 0), Vector3.UP, 0.032, 18, Color(0.08, 0.07, 0.06))
	for rr: float in [0.01, 0.019, 0.028]:
		ItemModels._torus(k, "im:metal@0.35", fx * Transform3D(Basis.IDENTITY, Vector3(0, 0.026, 0)), rr, 0.0018, 18, 4, BRASS)
	for y: float in [0.06, -0.02]:
		_line(k, "im:rubber", _ring_pts(0.088, y, 16, PI * 0.5, PI * 1.5, 1.1), 0.006, rub.darkened(0.2))

## A brass diving helmet: a great round dome with a barred front port and two side ports,
## sat on a broad bolted collar.
static func _diving_helmet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var brass := Color(0.8, 0.58, 0.3)
	var cu := Color(0.82, 0.5, 0.35)
	k.sphere("im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)), 0.13, 12, 24, 0.0, 1.0, cu)
	# The corselet: a wide collar under it, its rim bolted all round.
	k.cylinder("im:metal@0.35", Transform3D(Basis.IDENTITY, Vector3(0, -0.09, 0)), 0.17, 0.11, 0.06, 28, true, 0.0, 1, brass)
	for i in 12:
		var a := TAU * i / 12.0
		k.cylinder("im:metal@0.4", Transform3D(Basis.IDENTITY, Vector3(sin(a) * 0.155, -0.058, cos(a) * 0.155)), 0.008, 0.008, 0.012, 6, true, 0.0, 1, brass.darkened(0.2))
	for port: Array in [[Vector3(0, 0.06, 1), 0.06], [Vector3(-1, 0.05, 0.1), 0.04], [Vector3(1, 0.05, 0.1), 0.04]]:
		var n: Vector3 = (port[0] as Vector3).normalized()
		var rr: float = port[1]
		var p := Vector3(0, 0.06, 0) + n * 0.13
		var bs := Basis(n.cross(Vector3.UP).normalized(), Vector3.UP, n) if absf(n.y) < 0.9 else Basis.IDENTITY
		k.cylinder("im:metal@0.3", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), p), rr + 0.012, rr + 0.01, 0.02, 20, false, 0.0, 1, brass)
		ItemModels._torus(k, "im:metal@0.3", Transform3D(bs * Basis(Vector3.RIGHT, PI * 0.5), p + n * 0.01), rr + 0.006, 0.006, 20, 5, brass)
		ItemModels._disc(k, "im:glass", Transform3D.IDENTITY, p + n * 0.005, n, rr, 20, Color(0.25, 0.3, 0.3, 0.7))
		for b in 3:
			var off := (b - 1) * rr * 0.55
			ItemModels._block(k, "im:metal@0.4", Transform3D(bs, p + n * 0.012 + bs.x * off), Vector3(0.005, rr * 2.0, 0.005), 0.0, brass.darkened(0.15))

## A closed sci-fi helmet: shell over the skull and jaw, a wide dark visor, a brow ridge,
## ear pods and a chin guard. Recon helmets carry an optic on a mount; alien ones (void,
## star, precursor) add crests and swept fins.
static func _tac_helmet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var R := 0.11
	var shell := func(u: float, v: float) -> Vector3:
		var a := (1.0 - u) * TAU
		var ph := v * PI * 0.78
		var jaw := 1.0 - 0.18 * smoothstep(0.55, 1.0, v) * pow(maxf(cos(a), 0.0), 2.0)
		return Vector3(sin(a) * sin(ph) * R * jaw, 0.06 + cos(ph) * R * 1.05, cos(a) * sin(ph) * R * 1.1 * jaw)
	ItemModels._sheet(k, m, Transform3D.IDENTITY, shell, 30, 10, 0.005, c, Color(0.08, 0.08, 0.09))
	var alien := t in ["helm_void", "helm_star", "helm_precursor"]
	var vis_m := "im:crystal_glow:7a40e0" if t == "helm_void" else "im:visor"
	var vis_c := Color(0.45, 0.25, 0.85, 0.9) if t == "helm_void" else (Color(0.12, 0.25, 0.55, 0.9) if alien else Color(0.05, 0.08, 0.09))
	var visor := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.05, 1.05, u)
		var y := 0.045 + (v - 0.5) * (0.06 if t != "helm_eva" else 0.1) * (1.0 - 0.3 * absf(a))
		var rr := R * 1.035
		return Vector3(sin(a) * rr, y, cos(a) * rr * 1.1)
	ItemModels._sheet(k, vis_m, Transform3D.IDENTITY, visor, 14, 2, 0.004, vis_c, vis_c)
	# Brow ridge over the visor and the chin guard below it.
	var brow := PackedVector3Array()
	for i in 13:
		var a := lerpf(-1.15, 1.15, i / 12.0)
		brow.append(Vector3(sin(a) * R * 1.06, 0.078 - 0.01 * absf(a), cos(a) * R * 1.06 * 1.1))
	_line(k, m, brow, 0.007, c.darkened(0.12), 6)
	for side: float in [-1.0, 1.0]:
		k.cylinder(m, Transform3D(Basis(Vector3.BACK, side * PI * 0.5), Vector3(side * R * 1.0, 0.02, 0.0)), 0.03, 0.026, 0.02, 16, true, 0.0, 1, c.darkened(0.2))
	if t in ["helm_recon", "helm_combat", "helm_power"]:
		# The jaw guard: a faceted plate wrapping the lower face below the visor, with a
		# vent in front.
		var jawf := func(u: float, v: float) -> Vector3:
			var a := lerpf(1.25, -1.25, u)
			var rr := R * (1.08 - 0.22 * v)
			var y := lerpf(0.016, -0.045, v)
			return Vector3(sin(a) * rr, y, cos(a) * rr * (1.12 + 0.12 * v * cos(a)))
		ItemModels._sheet(k, m, Transform3D.IDENTITY, jawf, 16, 4, 0.006, c.darkened(0.08), Color(0.08, 0.08, 0.09))
		for i in 3:
			ItemModels._block(k, "im:composite", Transform3D(Basis.IDENTITY, Vector3(0, -0.005 - i * 0.01, R * 1.17)), Vector3(0.03, 0.003, 0.004), 0.0, Color(0.1, 0.1, 0.1))
	if t == "helm_recon" or t == "helm_combat":
		# A mount on the brow with a folded-up optic.
		ItemModels._block(k, "im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0.085)), Vector3(0.03, 0.02, 0.025), 0.004, Color(0.12, 0.12, 0.12))
		k.cylinder("im:composite", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, 0.1)), 0.012, 0.012, 0.04, 12, true, 0.0, 1, Color(0.1, 0.1, 0.1))
	if alien:
		var trim := GOLD if t != "helm_void" else Color(0.22, 0.2, 0.26)
		for side: float in [-1.0, 1.0]:
			var fin := PackedVector3Array()
			var radii := PackedFloat32Array()
			for i in 9:
				var s := i / 8.0
				fin.append(Vector3(side * (R * 0.95 + s * 0.04), 0.06 + s * 0.09 + (0.06 * s * s if t == "helm_precursor" else 0.0), 0.02 - s * 0.08))
				radii.append(lerpf(0.009, 0.0015, s))
			ItemModels._tube(k, "im:metal@0.25", Transform3D.IDENTITY, fin, radii, 6, trim)
		_line(k, "im:metal@0.25", brow, 0.008, trim, 6)
		k.crystal("im:crystal_glow:" + ("8a50f0" if t == "helm_void" else "4f78ff"), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.1, 0.12)), 0.012, 0.016, 6, 0.4, Color(0.3, 0.45, 1.0, 0.9) if t != "helm_void" else Color(0.55, 0.3, 0.95, 0.9))

## An EVA helmet: a white shell with a big tinted bubble visor across the whole face, a neck
## ring and lamps at the temples.
static func _eva_helmet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var R := 0.13
	k.sphere("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, 0.06, -0.01)), R, 12, 24, 0.0, 1.0, c)
	var bubble := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.0, 1.0, u)
		var ph := lerpf(0.6, 1.9, v)
		return Vector3(sin(a) * sin(ph) * R * 1.02, 0.06 + cos(ph) * R * 1.02, cos(a) * sin(ph) * R * 1.02 - 0.01)
	ItemModels._sheet(k, "im:visor", Transform3D.IDENTITY, bubble, 16, 10, 0.004, Color(0.03, 0.04, 0.06), Color(0.03, 0.04, 0.06))
	k.cylinder("im:composite", Transform3D(Basis.IDENTITY, Vector3(0, -0.09, -0.01)), 0.1, 0.095, 0.04, 24, true, 0.0, 1, Color(0.55, 0.55, 0.56))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, -0.07, -0.01)), 0.1, 0.008, 24, 6, Color(0.6, 0.6, 0.62))
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 0.11, 0.1, 0.05)
		ItemModels._block(k, "im:composite", Transform3D(Basis(Vector3.UP, side * 0.9), p), Vector3(0.03, 0.022, 0.03), 0.004, Color(0.4, 0.4, 0.42))
		ItemModels._disc(k, "im:glass", Transform3D.IDENTITY, p + Vector3(side * 0.01, 0, 0.015), Vector3(side * 0.6, 0, 0.8).normalized(), 0.008, 10, Color(0.85, 0.85, 0.8, 0.6))

## A stealth hood: soft dark cloth over the head and shoulders with a peak at the brow, and
## a close black mask over the lower face.
static func _stealth_hood(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	_hood(k, m, c, 1.0)
	var mask := func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.3, 1.3, u)
		var rr := 0.09 - 0.012 * v
		return Vector3(sin(a) * rr, 0.035 - v * 0.09, cos(a) * rr * 1.1)
	ItemModels._sheet(k, "im:composite", Transform3D.IDENTITY, mask, 14, 5, 0.004, Color(0.05, 0.05, 0.06), Color(0.03, 0.03, 0.03))
	# Inside the opening, shadow where the face would be.
	ItemModels._sheet(k, "im:linen", Transform3D.IDENTITY, func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.0, 1.0, u)
		return Vector3(sin(a) * 0.07, 0.05 + (v - 0.5) * 0.06, cos(a) * 0.07), 8, 2, 0.002, DARK, DARK)

## A chitin helm: plates of dark shell drawn up into a crown of hooked spikes, red-brown
## where they are thin.
static func _chitin_helm(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var shell := Color(0.55, 0.42, 0.3)
	ItemModels._helm(k, "im:enamel", shell, Outfit.STYLE_PLATE, "im:enamel")
	for i in 9:
		var a := lerpf(-1.6, 1.6, i / 8.0)
		var base := Vector3(sin(a) * 0.1, 0.12 - absf(a) * 0.02, cos(a) * 0.1)
		var spike := PackedVector3Array()
		var radii := PackedFloat32Array()
		var h := 0.08 - absf(a) * 0.02
		for j in 7:
			var s := j / 6.0
			spike.append(base + Vector3(sin(a) * s * 0.02, s * h, cos(a) * s * 0.02 - s * s * 0.02))
			radii.append(lerpf(0.012, 0.001, s))
		ItemModels._tube(k, "im:enamel", Transform3D.IDENTITY, spike, radii, 6, shell.lerp(Color(0.5, 0.18, 0.15), 0.4))

## A crystal tiara: a fine silver band with a fan of tall blue and violet crystals at the
## front, the middle one tallest, and a drop hanging over the brow.
static func _crystal_tiara(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	var silver := Color(0.75, 0.76, 0.8)
	ItemModels._torus(k, "im:metal@0.2", Transform3D(Basis.from_scale(Vector3(1, 1, 1.15)), Vector3(0, 0.0, 0)), 0.09, 0.004, 32, 6, silver)
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		var h := 0.075 * (1.0 - absf(a) / 1.6) + 0.015
		var p := Vector3(sin(a) * 0.092, 0.004, cos(a) * 0.092 * 1.15)
		var tilt := Basis(Vector3(cos(a), 0, -sin(a)), -0.15)
		k.crystal("im:crystal_glow:7a6cff", Transform3D(tilt, p), 0.009 + h * 0.06, h, 6, 0.35, Color(0.45, 0.45, 0.95, 0.85).lerp(Color(0.6, 0.35, 0.9, 0.85), absf(a) / 1.2))
		_dot(k, "im:metal@0.2", p, 0.005, silver)
	k.crystal("im:crystal_glow:7a6cff", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.006, 0.106)), 0.006, 0.022, 6, 0.5, Color(0.5, 0.45, 0.95, 0.85))

# --- Neck -------------------------------------------------------------------------------

## A short fold of cord or chain behind a pendant hung at `top`, as one holds it.
static func _cord(k: MeshKit, top: Vector3, chain: bool, col: Color, span := 0.02) -> void:
	var pts := PackedVector3Array()
	for i in 13:
		var a := lerpf(-PI * 0.75, PI * 0.75, i / 12.0)
		pts.append(top + Vector3(sin(a) * span, (1.0 - cos(a)) * span * 0.6, -0.006 - 0.004 * cos(a)))
	_line(k, "im:metal@0.3" if chain else "im:rope", pts, 0.0011 if chain else 0.0014, col, 4)
	if chain:
		for i in range(0, 13, 2):
			ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * (i % 4)), pts[i]), 0.0022, 0.0006, 8, 3, col)

## A coin: a raised rim, a struck face with a relief, a reeded edge.
static func _coin(k: MeshKit, p: Vector3, rad: float, th: float, col: Color, relief: String) -> void:
	var face := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p)
	k.cylinder("im:metal@0.3", face, rad, rad, th, 28, true, 0.0, 1, col)
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0, th * 0.5)), rad * 0.92, th * 0.18, 28, 4, col.lightened(0.08))
	match relief:
		"shamrock":
			for i in 3:
				var a := PI * 0.5 + TAU * i / 3.0
				k.sphere("im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1, 1, 0.25)), p + Vector3(cos(a), sin(a), 0) * rad * 0.28 + Vector3(0, 0, th * 0.5)), rad * 0.28, 5, 8, 0.0, 1.0, col.darkened(0.1))
			ItemModels._block(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, 0.4), p + Vector3(0.0, -rad * 0.4, th * 0.5)), Vector3(rad * 0.08, rad * 0.5, th * 0.2), 0.0, col.darkened(0.1))
		"saint":
			k.sphere("im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1, 1.2, 0.3)), p + Vector3(0, rad * 0.25, th * 0.5)), rad * 0.2, 5, 8, 0.0, 1.0, col.lightened(0.05))
			k.sphere("im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1.2, 1.3, 0.25)), p + Vector3(0, -rad * 0.3, th * 0.5)), rad * 0.36, 5, 8, 0.0, 1.0, col.lightened(0.05))
		"star":
			k.crystal("im:crystal_glow:5a73f2", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0, th * 0.5)), rad * 0.3, rad * 0.25, 6, 0.5, Color(0.35, 0.45, 0.95, 0.9))
			for i in 8:
				var a := TAU * i / 8.0
				ItemModels._block(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, a), p + Vector3(cos(a), sin(a), 0) * rad * 0.62 + Vector3(0, 0, th * 0.5)), Vector3(rad * 0.08, rad * 0.4, th * 0.3), 0.0, col.lightened(0.1))

static func _coin_pendant(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# The lucky coin: a big copper coin with a shamrock struck on it, a short cord.
	var cu := Color(0.78, 0.45, 0.3)
	_coin(k, Vector3.ZERO, 0.02, 0.003, cu, "shamrock")
	_cord(k, Vector3(0, 0.02, 0), false, Color(0.35, 0.25, 0.16))

static func _tooth_pendant(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A boar's tusk carved with knotwork, bound with cord at the root.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 10:
		var s := i / 9.0
		path.append(Vector3(sin(s * 1.2) * 0.02, 0.02 - s * 0.065, 0.0))
		radii.append(lerpf(0.009, 0.0006, pow(s, 1.3)))
	ItemModels._tube(k, "im:bone", Transform3D.IDENTITY, path, radii, 10, Color(0.88, 0.83, 0.72))
	for i in 3:
		ItemModels._torus(k, "im:rope", Transform3D(Basis.IDENTITY, Vector3(0, 0.018 - i * 0.004, 0)), 0.0095, 0.0014, 12, 4, Color(0.35, 0.24, 0.15))
	for i in 4:
		var s := 0.25 + i * 0.13
		ItemModels._torus(k, "im:bone", Transform3D(Basis(Vector3.BACK, 0.5), Vector3(sin(s * 1.2) * 0.02, 0.02 - s * 0.065, 0)), lerpf(0.009, 0.0006, s) + 0.0004, 0.0007, 10, 3, Color(0.55, 0.45, 0.32))
	_cord(k, Vector3(0, 0.024, 0), false, Color(0.35, 0.25, 0.16), 0.018)

static func _locket(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A silver locket: an oval of two domed halves hinged at the top, engraved, on a chain.
	var silver := Color(0.75, 0.75, 0.76)
	k.sphere("im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1.0, 1.25, 0.35)), Vector3.ZERO), 0.02, 8, 18, 0.0, 1.0, silver)
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1.25, 1)), Vector3.ZERO), 0.0195, 0.0012, 24, 4, silver.darkened(0.15))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1.25, 1)), Vector3(0, 0, 0.006)), 0.011, 0.0008, 20, 3, silver.darkened(0.25))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.028, 0)), 0.004, 0.0012, 10, 4, silver)
	_cord(k, Vector3(0, 0.032, 0), true, silver)

static func _medallion(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A medallion: a round of struck metal with a figure in relief and a beaded rim; the
	# alien ones are gilt with a gem at the heart.
	var col := Color(0.7, 0.68, 0.64) if t == "amulet_saint" else GOLD
	_coin(k, Vector3.ZERO, 0.024, 0.004, col, "saint" if t == "amulet_saint" else "star")
	for i in 24:
		var a := TAU * i / 24.0
		_dot(k, "im:metal@0.3", Vector3(cos(a), sin(a), 0) * 0.0255 + Vector3(0, 0, 0.0015), 0.0014, col.lightened(0.1))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.03, 0)), 0.0045, 0.0013, 10, 4, col)
	_cord(k, Vector3(0, 0.034, 0), true, col)

static func _bandana(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A bandana folded into a triangle and knotted, the point hanging, its print in pale
	# speckles over red.
	var red := Color(0.6, 0.16, 0.12)
	var tri := func(u: float, v: float) -> Vector3:
		var w := (1.0 - v) * 0.14
		return Vector3((u - 0.5) * 2.0 * w, -v * 0.12, 0.01 * sin(u * PI * 3.0) + 0.012 * v)
	ItemModels._sheet(k, "im:linen", Transform3D.IDENTITY, tri, 10, 8, 0.004, red, red.darkened(0.3))
	for i in 18:
		var u := r.randf()
		var v := r.randf() * 0.9
		_dot(k, "im:linen", Vector3((u - 0.5) * 2.0 * (1.0 - v) * 0.13, -v * 0.12, 0.012 * v + 0.004), 0.0025, Color(0.85, 0.8, 0.7))
	# The knotted ends at the top.
	for side: float in [-1.0, 1.0]:
		var end := PackedVector3Array([Vector3(side * 0.14, 0.0, 0.0), Vector3(side * 0.07, 0.015, 0.01), Vector3(0.0, 0.01, 0.012)])
		_line(k, "im:linen", end, 0.01, red.darkened(0.05), 8)
	k.sphere("im:linen", Transform3D(Basis.IDENTITY, Vector3(0, 0.01, 0.014)), 0.014, 6, 8, 0.15, 0.8, red.darkened(0.1))

static func _pocket_watch(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A gold hunter watch: engraved case, crown and bow at the top, a fob chain falling away.
	var gold := Color(0.86, 0.64, 0.32)
	var face := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.006))
	k.cylinder("im:metal@0.3", face, 0.024, 0.024, 0.012, 28, true, 0.0, 1, gold.darkened(0.1))
	# The lid domes up from a milled bezel.
	k.sphere("im:metal@0.25", Transform3D(Basis.from_scale(Vector3(1, 1, 0.28)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.004)), 0.0225, 8, 28, 0.0, 1.0, gold, true)
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0055)), 0.0235, 0.0022, 28, 5, gold.lightened(0.1))
	# The lid's engraving: a scroll border of raised arcs round a rosette, dark in the cuts.
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a), sin(a), 0) * 0.016
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0, 0.0095)), 0.0035, 0.0007, 10, 3, gold.darkened(0.35))
	for i in 8:
		var a := TAU * i / 8.0
		k.sphere("im:metal@0.3", Transform3D(Basis.from_scale(Vector3(1, 0.45, 0.4)).rotated(Vector3.BACK, a), Vector3(cos(a), sin(a), 0) * 0.006 + Vector3(0, 0, 0.0108)), 0.004, 4, 8, 0.0, 1.0, gold.darkened(0.25))
	_dot(k, "im:metal@0.3", Vector3(0, 0, 0.0112), 0.0025, gold.lightened(0.1))
	k.cylinder("im:metal@0.3", Transform3D.IDENTITY.translated(Vector3(0, 0.026, 0)), 0.004, 0.004, 0.006, 10, true, 0.0, 1, gold)
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.034, 0)), 0.006, 0.0013, 12, 4, gold)
	var chain := PackedVector3Array()
	for i in 10:
		var s := i / 9.0
		chain.append(Vector3(0.006 + s * 0.035, 0.038 + sin(s * PI) * 0.01 - s * 0.05, -0.003))
	_line(k, "im:metal@0.3", chain, 0.0015, gold, 4)
	for p in chain:
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, 0.6), p), 0.0026, 0.0007, 8, 3, gold)

static func _compass(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A brass pocket compass with its lid open behind it: a white card with a red and black
	# needle under glass, a ring at the bottom. The void compass has no lid: a dark iron case
	# with a thorny rim, a deep blue star-chart face, a gilt star and two small orbs, hung
	# from a ring at the top.
	var alien := t == "compass_void"
	var case_c := Color(0.22, 0.2, 0.2) if alien else Color(0.78, 0.58, 0.3)
	var face := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.005))
	k.cylinder("im:metal@0.3", face, 0.026, 0.026, 0.01, 28, true, 0.0, 1, case_c)
	ItemModels._disc(k, "im:paint" if alien else "im:dial", Transform3D.IDENTITY, Vector3(0, 0, 0.0052), Vector3.BACK, 0.022, 28, Color(0.1, 0.2, 0.42) if alien else Color(0.92, 0.88, 0.76))
	if alien:
		var gilt := Color(0.86, 0.64, 0.34)
		for i in 8:
			var a := TAU * i / 8.0
			var long := 0.016 if i % 2 == 0 else 0.009
			ItemModels._tri(k, "im:metal@0.3", Transform3D.IDENTITY, Vector3(0, 0, 0.0064), Vector3(cos(a + 0.35), sin(a + 0.35), 0) * 0.004 + Vector3(0, 0, 0.0058), Vector3(cos(a), sin(a), 0) * long + Vector3(0, 0, 0.0058), Vector3.BACK, Vector3.BACK, Vector3.BACK, gilt)
			ItemModels._tri(k, "im:metal@0.3", Transform3D.IDENTITY, Vector3(0, 0, 0.0064), Vector3(cos(a), sin(a), 0) * long + Vector3(0, 0, 0.0058), Vector3(cos(a - 0.35), sin(a - 0.35), 0) * 0.004 + Vector3(0, 0, 0.0058), Vector3.BACK, Vector3.BACK, Vector3.BACK, gilt.darkened(0.25))
		for i in 30:
			var a := r.randf() * TAU
			var rr := 0.006 + r.randf() * 0.014
			_dot(k, "im:paint", Vector3(cos(a), sin(a), 0) * rr + Vector3(0, 0, 0.0054), 0.0005, gilt.lightened(0.2))
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0056)), 0.0185, 0.0005, 28, 3, gilt)
		_dot(k, "im:metal@0.2", Vector3(0.013, 0.004, 0.0062), 0.0028, Color(0.75, 0.45, 0.4))
		_dot(k, "im:metal@0.2", Vector3(-0.014, -0.009, 0.0062), 0.0024, Color(0.6, 0.45, 0.75))
		for i in 12:
			var a := TAU * i / 12.0
			var d := Vector3(cos(a), sin(a), 0)
			ItemModels._tri(k, "im:metal@0.3", Transform3D.IDENTITY, d.rotated(Vector3.BACK, 0.12) * 0.026, d * 0.032 + Vector3(0, 0, 0.002), d.rotated(Vector3.BACK, -0.12) * 0.026 + Vector3(0, 0, 0.004), Vector3.BACK, Vector3.BACK, Vector3.BACK, case_c.lightened(0.1))
	else:
		for i in 4:
			var a := TAU * i / 4.0
			ItemModels._block(k, "im:paint", Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a + PI * 0.5), sin(a + PI * 0.5), 0) * 0.011 + Vector3(0, 0, 0.0056)), Vector3(0.003, 0.016, 0.0005), 0.0, Color(0.15, 0.12, 0.1))
		ItemModels._block(k, "im:paint", Transform3D(Basis(Vector3.BACK, 0.4), Vector3(0, 0, 0.0062)), Vector3(0.003, 0.03, 0.001), 0.0, Color(0.7, 0.12, 0.1))
	if not alien:
		ItemModels._disc(k, "im:glass", Transform3D.IDENTITY, Vector3(0, 0, 0.0068), Vector3.BACK, 0.023, 24, Color(0.9, 0.95, 1.0, 0.15))
	ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.006)), 0.0245, 0.002, 28, 4, case_c.lightened(0.15))
	if alien:
		k.cylinder("im:metal@0.3", Transform3D.IDENTITY.translated(Vector3(0, 0.026, 0)), 0.0035, 0.0035, 0.005, 10, true, 0.0, 1, case_c)
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.037, 0)), 0.006, 0.0014, 12, 4, Color(0.6, 0.48, 0.3))
	else:
		# The lid, swung open on its hinge at the top and leaning back, its inside to the eye.
		var lid := Basis(Vector3.RIGHT, PI * 0.5 - 0.4)
		var lid_at := Vector3(0, 0.026, -0.004) + lid * Vector3(0, 0, -0.026)
		k.cylinder("im:metal@0.3", Transform3D(lid, lid_at), 0.026, 0.026, 0.004, 28, true, 0.0, 1, case_c)
		# Its inside, a shade darker, and the hinge knuckle joining it to the case.
		ItemModels._torus(k, "im:metal@0.3", Transform3D(lid, lid_at + lid * Vector3(0, 0.0042, 0)), 0.022, 0.0015, 28, 4, case_c.darkened(0.2))
		k.cylinder("im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.007, 0.0265, -0.004)), 0.0028, 0.0028, 0.014, 10, true, 0.0, 1, case_c.darkened(0.1))
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, -0.03, 0)), 0.005, 0.0013, 10, 4, case_c)

static func _star_badge(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A sheriff's star: six points each ending in a ball, a raised ring in the middle.
	var brass := Color(0.78, 0.6, 0.32)
	var pts := PackedVector3Array()
	for i in 12:
		var a := PI * 0.5 + TAU * i / 12.0
		var rr := 0.035 if i % 2 == 0 else 0.017
		pts.append(Vector3(cos(a) * rr, sin(a) * rr, 0))
	for i in 12:
		var a0 := pts[i]
		var a1 := pts[(i + 1) % 12]
		ItemModels._tri(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(0, 0, 0.003), a0 + Vector3(0, 0, 0.0015), a1 + Vector3(0, 0, 0.0015), Vector3.BACK, Vector3.BACK, Vector3.BACK, brass)
		ItemModels._tri(k, "im:metal@0.35", Transform3D.IDENTITY, Vector3(0, 0, -0.001), a1, a0, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, brass.darkened(0.3))
		ItemModels._quad(k, "im:metal@0.35", Transform3D.IDENTITY, a0, a1, a1 + Vector3(0, 0, 0.0015), a0 + Vector3(0, 0, 0.0015), ((a0 + a1) * 0.5).normalized(), brass.darkened(0.15))
		if i % 2 == 0:
			_dot(k, "im:metal@0.35", a0 * 1.08 + Vector3(0, 0, 0.001), 0.0045, brass)
	ItemModels._torus(k, "im:metal@0.35", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0035)), 0.011, 0.0018, 20, 4, brass.lightened(0.1))

static func _spectacles(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# Round wire spectacles: two thin brass rims with lenses, a bridge, the arms folded back.
	var wire := Color(0.6, 0.48, 0.32)
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 0.03, 0, 0)
		ItemModels._torus(k, "im:metal@0.3", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), 0.021, 0.0013, 24, 4, wire)
		ItemModels._disc(k, "im:glass", Transform3D.IDENTITY, p, Vector3.BACK, 0.02, 20, Color(0.9, 0.95, 1.0, 0.18))
		_line(k, "im:metal@0.3", PackedVector3Array([p + Vector3(side * 0.021, 0.004, 0), p + Vector3(side * 0.026, 0.004, -0.01), p + Vector3(-side * 0.02, 0.002, -0.016)]), 0.0011, wire, 4)
	var bridge := PackedVector3Array()
	for i in 7:
		var a := lerpf(-PI * 0.5, PI * 0.5, i / 6.0)
		bridge.append(Vector3(sin(a) * 0.009, 0.006 + cos(a) * 0.005, 0))
	_line(k, "im:metal@0.3", bridge, 0.0012, wire, 4)

static func _dog_tags(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# Two stamped steel tags overlapping on a ball chain.
	var steel := Color(0.66, 0.66, 0.67)
	for i in 2:
		var p := Vector3(i * 0.008, -i * 0.006, i * 0.002)
		var bs := Basis(Vector3.BACK, i * 0.25)
		ItemModels._block(k, "im:metal@0.35", Transform3D(bs, p), Vector3(0.028, 0.05, 0.0015), 0.006, steel)
		for row in 4:
			ItemModels._block(k, "im:metal@0.35", Transform3D(bs, p + bs * Vector3(-0.002, 0.012 - row * 0.008, 0.0009)), Vector3(0.016 - (row % 2) * 0.004, 0.003, 0.0004), 0.0, steel.darkened(0.3))
		ItemModels._disc(k, "im:linen", Transform3D.IDENTITY, p + bs * Vector3(0, 0.02, 0.0009), Vector3.BACK, 0.0018, 8, DARK)
	var chain := PackedVector3Array()
	for i in 22:
		var a := lerpf(-PI * 0.85, PI * 0.85, i / 21.0)
		chain.append(Vector3(sin(a) * 0.028, 0.022 + (1.0 - cos(a)) * 0.035, -0.004))
	for p in chain:
		_dot(k, "im:metal@0.35", p, 0.0016, steel)

static func _medal(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A service medal: a striped ribbon (blue, white, blue) folded at a bar, and a bronze
	# star in a round below it.
	var ribbon := func(u: float, v: float) -> Vector3:
		return Vector3((u - 0.5) * 0.03, 0.03 + v * 0.045, 0.002 * sin(v * PI))
	ItemModels._sheet(k, "im:linen", Transform3D.IDENTITY, ribbon, 1, 3, 0.002, Color(0.12, 0.18, 0.38), Color(0.1, 0.12, 0.25))
	ItemModels._block(k, "im:linen", Transform3D(Basis.IDENTITY, Vector3(0, 0.052, 0.0016)), Vector3(0.008, 0.045, 0.0008), 0.0, Color(0.85, 0.85, 0.82))
	ItemModels._block(k, "im:metal@0.3", Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0.001)), Vector3(0.034, 0.006, 0.004), 0.001, BRASS)
	var bronze := Color(0.66, 0.48, 0.3)
	k.cylinder("im:metal@0.35", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.0, 0)), 0.022, 0.022, 0.004, 6, true, 0.0, 1, bronze)
	k.crystal("im:metal@0.35", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.002)), 0.014, 0.006, 5, 0.9, bronze.lightened(0.15))

static func _headset(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A comms headset: padded band over the top, two big ear cups, a boom mic.
	var dark := Color(0.15, 0.16, 0.15)
	var band := PackedVector3Array()
	for i in 15:
		var a := lerpf(-PI * 0.5, PI * 0.5, i / 14.0)
		band.append(Vector3(sin(a) * 0.085, cos(a) * 0.09, 0))
	_line(k, "im:composite", band, 0.009, dark, 8)
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 0.09, -0.01, 0)
		k.cylinder("im:composite", Transform3D(Basis(Vector3.BACK, side * PI * 0.5), p), 0.042, 0.04, 0.035, 20, true, 0.0, 1, Color(0.25, 0.27, 0.22))
		k.cylinder("im:rubber", Transform3D(Basis(Vector3.BACK, side * PI * 0.5), p - Vector3(side * 0.02, 0, 0)), 0.038, 0.036, 0.012, 20, true, 0.0, 1, dark)
	var boom := PackedVector3Array([Vector3(-0.1, -0.02, 0.01), Vector3(-0.09, -0.06, 0.05), Vector3(-0.05, -0.075, 0.075), Vector3(-0.02, -0.075, 0.08)])
	_line(k, "im:composite", boom, 0.003, dark, 6)
	k.sphere("im:rubber", Transform3D(Basis.IDENTITY, Vector3(-0.015, -0.075, 0.08)), 0.008, 6, 8, 0.0, 1.0, dark)

static func _tablet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A rugged tablet: a dark glass screen in a thick rubber-cornered frame, orange trim.
	ItemModels._block(k, "im:composite", Transform3D.IDENTITY, Vector3(0.14, 0.2, 0.016), 0.008, Color(0.16, 0.16, 0.17))
	ItemModels._block(k, "im:visor", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0085)), Vector3(0.115, 0.17, 0.002), 0.0, Color(0.03, 0.035, 0.04))
	for p: Vector3 in [Vector3(0.068, 0.098, 0), Vector3(-0.068, 0.098, 0), Vector3(0.068, -0.098, 0), Vector3(-0.068, -0.098, 0)]:
		ItemModels._block(k, "im:rubber", Transform3D(Basis.IDENTITY, p), Vector3(0.02, 0.02, 0.02), 0.005, Color(0.85, 0.5, 0.15))

static func _tracker(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A handheld motion tracker: chunky grey-green body, a dark round screen, buttons and a
	# stub aerial.
	var body := Color(0.32, 0.33, 0.28)
	ItemModels._block(k, "im:composite", Transform3D.IDENTITY, Vector3(0.085, 0.13, 0.03), 0.01, body)
	ItemModels._block(k, "im:visor", Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0.0155)), Vector3(0.062, 0.06, 0.002), 0.004, Color(0.03, 0.04, 0.04))
	for i in 3:
		k.cylinder("im:rubber", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.02 + i * 0.02, -0.04, 0.016)), 0.006, 0.006, 0.004, 10, true, 0.0, 1, [Color(0.75, 0.2, 0.15), Color(0.2, 0.2, 0.2), Color(0.85, 0.55, 0.15)][i])
	k.cylinder("im:rubber", Transform3D.IDENTITY.translated(Vector3(0.03, 0.09, 0)), 0.005, 0.004, 0.05, 8, true, 0.0, 1, Color(0.1, 0.1, 0.1))

static func _earring(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A gold hook with a blue bead and a long curved drop of iridescent crystal.
	_line(k, "im:metal@0.25", PackedVector3Array([Vector3(0, 0.02, 0), Vector3(0.01, 0.035, 0), Vector3(0.0, 0.045, 0), Vector3(-0.008, 0.035, 0)]), 0.0009, GOLD, 4)
	_dot(k, "im:crystal_glow:8a6cf0", Vector3(0, 0.016, 0), 0.0045, Color(0.3, 0.45, 0.95))
	var drop := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var s := i / 8.0
		drop.append(Vector3(sin(s * 1.6) * 0.012, 0.01 - s * 0.06, 0))
		radii.append(sin(minf(s * 1.3, 1.0) * PI) * 0.007 + 0.0005)
	ItemModels._tube(k, "im:crystal_glow:8a6cf0", Transform3D.IDENTITY, drop, radii, 6, Color(0.6, 0.45, 0.9, 0.85))

# --- Rings ------------------------------------------------------------------------------

static func _band(k: MeshKit, col: Color, w := 0.0022) -> void:
	ItemModels._torus(k, "im:metal@0.2", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.011, w, 24, 8, col)

static func _signet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A carved band rising to a raised bezel: the ruby ring in copper with scrollwork and a
	# cut red stone; the void ring in dark iron with a black-violet stone.
	var metal := Color(0.78, 0.45, 0.3) if t == "ring_ruby" else Color(0.3, 0.29, 0.32)
	var stone := Color(0.8, 0.08, 0.1, 0.9) if t == "ring_ruby" else Color(0.25, 0.1, 0.4, 0.95)
	_band(k, metal, 0.0028)
	for i in 10:
		var a := lerpf(0.4, TAU - 0.4, i / 9.0)
		ItemModels._torus(k, "im:metal@0.2", Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0) * 0.0135), 0.0018, 0.0005, 8, 3, metal.darkened(0.25))
	k.cylinder("im:metal@0.2", Transform3D(Basis.IDENTITY, Vector3(0, 0.012, 0)), 0.0065, 0.0075, 0.004, 12, true, 0.0, 1, metal)
	k.crystal("im:crystal:" + t if t == "ring_ruby" else "im:crystal_glow:7a6cff", Transform3D(Basis.IDENTITY, Vector3(0, 0.0145, 0)), 0.0058, 0.005, 8, 0.6, stone)

static func _gem_band(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A wide gold band set with a row of blue and violet stones in raised collets.
	_band(k, GOLD, 0.0032)
	for i in 3:
		var a := (i - 1) * 0.55
		var p := Vector3(-sin(a), cos(a), 0) * 0.0142
		k.crystal("im:crystal_glow:7a6cff", Transform3D(Basis(Vector3.BACK, a), p), 0.0035 if i != 1 else 0.0045, 0.004, 8, 0.6, [Color(0.35, 0.4, 0.95, 0.9), Color(0.4, 0.6, 1.0, 0.9), Color(0.6, 0.4, 0.95, 0.9)][i])

static func _crystal_bracelet(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# A bracelet of faceted crystal blocks in iridescent pinks and blues, linked by silver.
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a), sin(a), 0) * 0.034
		var col := Color(0.6, 0.55, 0.95, 0.85).lerp(Color(0.95, 0.6, 0.8, 0.85), 0.5 + 0.5 * sin(a * 3.0))
		ItemModels._block(k, "im:crystal_glow:7a6cff", Transform3D(Basis(Vector3.BACK, a), p), Vector3(0.012, 0.016, 0.014), 0.003, col)
		_dot(k, "im:metal@0.2", Vector3(cos(a + PI / 12.0), sin(a + PI / 12.0), 0) * 0.034, 0.003, Color(0.8, 0.8, 0.84))

static func _fuzzy_dice(k: MeshKit, r: RandomNumberGenerator, t: String, m: String, c: Color, style: int) -> void:
	# Two plush red dice with white pips, hung from a cord.
	for i in 2:
		var p := Vector3(-0.022 + i * 0.044, -0.03 - i * 0.012, 0)
		var bs := Basis(Vector3(0.3, 1, 0.2).normalized(), 0.4 + i * 0.6)
		ItemModels._block(k, "im:wool", Transform3D(bs, p), Vector3(0.038, 0.038, 0.038), 0.01, Color(0.68, 0.1, 0.1))
		for pip: Vector3 in [Vector3(0, 0, 1), Vector3(0.4, 0.4, 1), Vector3(-0.4, -0.4, 1), Vector3(1, 0.4, -0.4), Vector3(1, -0.4, 0.4)]:
			var q := Vector3(pip.x * 0.019 if absf(pip.x) == 1.0 else pip.x * 0.019, pip.y * 0.019, pip.z * 0.019)
			_dot(k, "im:wool", p + bs * q, 0.0035, Color(0.92, 0.9, 0.86))
		_line(k, "im:rope", PackedVector3Array([p + bs * Vector3(0, 0.019, 0), Vector3(0, 0.02, 0)]), 0.0012, Color(0.4, 0.3, 0.22), 4)

# --- Legs and pairs ---------------------------------------------------------------------

## Trousers laid flat as the icon shows them: a waistband with belt loops, two legs
## tapering to the hem and parted at the crotch, a fly seam and creases at the knees.
static func trousers(k: MeshKit, m: String, c: Color) -> void:
	var waist := 0.22
	var L := 0.42
	for side: float in [-1.0, 1.0]:
		var leg := func(u: float, v: float) -> Vector3:
			# v from the waist (0) to the hem (1); the inner edge runs to the crotch.
			# The seat is whole down to the crotch, then the legs part a little, each
			# narrowing to its hem.
			var outer := waist * 0.5 + 0.01 * sin(v * PI * 0.5) - 0.012 * v
			var inner := 0.006 + (v - 0.3) * 0.03 if v > 0.3 else 0.0
			var x := lerpf(inner, outer, u)
			var bulge := 0.012 * sin(u * PI) + 0.004 * sin(v * 40.0 + u * 3.0) * smoothstep(0.4, 0.6, v) * (1.0 - smoothstep(0.6, 0.7, v))
			return Vector3(side * x, -v * L + L * 0.5, bulge)
		ItemModels._sheet(k, m, Transform3D.IDENTITY, leg, 5, 14, 0.008, c, c.darkened(0.3))
	k.cylinder(m, Transform3D(Basis.from_scale(Vector3(1, 1, 0.2)), Vector3(0, L * 0.5 + 0.01, 0)), waist * 0.52, waist * 0.52, 0.03, 20, true, 0.0, 1, c.darkened(0.1))
	_line(k, m, PackedVector3Array([Vector3(0.005, L * 0.5, 0.012), Vector3(0.008, L * 0.5 - 0.1, 0.014)]), 0.002, c.darkened(0.25), 4)
	for x: float in [-0.06, -0.02, 0.02, 0.06]:
		ItemModels._block(k, m, Transform3D(Basis.IDENTITY, Vector3(x, L * 0.5 + 0.01, 0.009)), Vector3(0.008, 0.03, 0.004), 0.0, c.darkened(0.2))

## Two of a piece side by side, the left one mirrored from the right, the way gloves,
## boots and greaves come (and are painted) in pairs.
static func paired(src: ArrayMesh, gap: float) -> ArrayMesh:
	var box := src.get_aabb()
	var off := box.size.x * 0.5 + gap * 0.5 - box.get_center().x
	var out := ArrayMesh.new()
	for side: float in [1.0, -1.0]:
		for i in src.get_surface_count():
			var arr := src.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for j in v.size():
				v[j] = Vector3(v[j].x * side + off * side, v[j].y, v[j].z - (0.02 if side < 0.0 else 0.0))
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for j in n.size():
					n[j].x *= side
				arr[Mesh.ARRAY_NORMAL] = n
			if arr[Mesh.ARRAY_TANGENT] != null:
				var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for j in range(0, tg.size(), 4):
					tg[j] *= side
				arr[Mesh.ARRAY_TANGENT] = tg
			if side < 0.0:
				# Mirroring turns the faces inside out: wind every triangle the other way.
				if arr[Mesh.ARRAY_INDEX] != null:
					var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					for j in range(0, ix.size(), 3):
						var s := ix[j + 1]
						ix[j + 1] = ix[j + 2]
						ix[j + 2] = s
					arr[Mesh.ARRAY_INDEX] = ix
				else:
					for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
						if arr[key] == null:
							continue
						var a = arr[key]
						var per := 4 if key == Mesh.ARRAY_TANGENT else 1
						var count: int = a.size() / per
						for j in range(0, count, 3):
							for q in per:
								var s = a[(j + 1) * per + q]
								a[(j + 1) * per + q] = a[(j + 2) * per + q]
								a[(j + 2) * per + q] = s
						arr[key] = a
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	for key in src.get_meta_list():
		out.set_meta(key, src.get_meta(key))
	# Held by the right one.
	out.set_meta("grip", Vector3(off, 0, 0) + (src.get_meta("grip", Vector3.ZERO) as Vector3))
	return out
