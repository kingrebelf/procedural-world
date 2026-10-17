class_name RealTree
## Oaks, elms, chestnuts, willows, birches, spruces, firs, larches and bushes built the way
## open-world games build trees: a bark-textured trunk and limbs, and a crown of photo
## leaf-spray cards (Ben's oak and autumn oak sprays, keyed by tools/make_foliage_cards.py)
## on the branch ends. Card normals point out of the crown, not along each card, so the
## crown shades as one soft volume and lets light through its rim (foliage.gdshader).
##
## Each tree also has a far version (a handful of big cards on a bare trunk) that
## ChunkNode merges into one mesh per chunk, so a distant forest is two draw calls a chunk
## instead of one per species per material.
##
## Pure functions of (type, species, variant): a saved tree keeps its place, size and
## chopped state, and only its look comes from here. Safe on worker threads (packed arrays
## and resource creation only, never a RenderingServer read).

const VARIANT_SALT := 500

static var _mats: Dictionary = {}
static var _far: Dictionary = {}
static var _lock := Mutex.new()

## Whether this type (and species) is drawn here: broadleaf trees and conifers.
static func handles(t: String) -> bool:
	return t == "oak" or t == "pine"

# --- Geometry buffers ----------------------------------------------------------------

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var ix := PackedInt32Array()
	## Index counts at the end of each detail stage (trunk, limbs, twigs / card halves),
	## used to make LOD index lists that drop the finest parts first.
	var marks: Array = []

	func mark() -> void:
		marks.append(ix.size())

	func arrays(tangents: bool) -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = ix
		if tangents and not v.is_empty():
			var st := SurfaceTool.new()
			st.create_from_arrays(a)
			st.generate_tangents()
			return st.commit_to_arrays()
		return a

## A tapered tube along a polyline (bark). UVs wrap the bark photo around the girth
## about once per 0.9 m of circumference and repeat along the length. `lumps` makes the
## girth uneven, ring to ring and around (no trunk is a turned pole).
static func _tube(b: Buf, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color, flare := 0.0, lumps := 0.0) -> void:
	var count := pts.size()
	if count < 2:
		return
	var base := b.v.size()
	var wraps := maxf(1.0, roundf(TAU * radii[0] / 0.9))
	var along := 0.0
	var side_ref := Vector3.RIGHT
	# Each tube its own buttresses and lumps.
	var seed := WHash.h32(base * 2654435 + int(radii[0] * 10000.0))
	var phase := WHash.to_unit(seed) * TAU
	var lobes := 4.0 + float(seed % 3)
	for i in count:
		var dir: Vector3
		if i == 0:
			dir = (pts[1] - pts[0]).normalized()
		elif i == count - 1:
			dir = (pts[i] - pts[i - 1]).normalized()
		else:
			dir = (pts[i + 1] - pts[i - 1]).normalized()
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		# Parallel-transported frame so the bark doesn't twist along a bent limb.
		var x := (side_ref - dir * side_ref.dot(dir))
		if x.length() < 0.01:
			x = dir.cross(Vector3.FORWARD)
		x = x.normalized()
		side_ref = x
		var y := dir.cross(x).normalized()
		var r := radii[i]
		if lumps > 0.0:
			r *= 1.0 + lumps * (WHash.to_unit(WHash.h32(seed + i * 131)) * 2.0 - 1.0)
		# Root flare at the foot, fading out over the first metre.
		var fl := flare * (1.0 - clampf(pts[i].distance_to(pts[0]) / 1.0, 0.0, 1.0))
		var ring_phase := phase + i * 1.3
		for s in sides + 1:
			var a := TAU * s / sides
			var nn := (x * cos(a) + y * sin(a))
			var rr := r
			if lumps > 0.0:
				rr *= 1.0 + lumps * 0.5 * sin(a * 3.0 + ring_phase)
			if fl > 0.0:
				# Buttresses, uneven in size.
				rr *= 1.0 + fl * (0.6 + 0.4 * sin(a * lobes + phase) * (0.7 + 0.3 * sin(a * 2.0 + phase * 1.7)))
			b.v.append(pts[i] + nn * rr)
			b.n.append(nn)
			b.uv.append(Vector2(float(s) / sides * wraps, along / 1.2))
			# Darker at the foot and in the crotch of a limb: cheap baked occlusion.
			b.c.append(col * (0.78 if i == 0 else 1.0))
	for i in count - 1:
		for s in sides:
			var a0 := base + i * (sides + 1) + s
			var a1 := a0 + 1
			var b0 := a0 + sides + 1
			var b1 := b0 + 1
			b.ix.append_array([a0, b0, a1, a1, b0, b1])

## One leaf card: its stem end at `at`, growing along `axis` for `length`, `width` wide
## across `side`. `uv_stem` says where the stem sits in the texture: (0.5, 1) for the oak
## sprays (stem at the bottom middle), (0, 0.5) for the spruce bough (stem at the left).
## Vertex normals are `crown_n` blended a little toward the card's own face.
static func _card(b: Buf, at: Vector3, axis: Vector3, side: Vector3, length: float, width: float,
		col: Color, centre: Vector3, radii: Vector3, stem_left: bool, face_mix := 0.3) -> void:
	var base := b.v.size()
	var hw := side * width * 0.5
	var tip := axis * length
	var corners: Array
	if stem_left:
		corners = [[at - hw, Vector2(0, 1)], [at + hw, Vector2(0, 0)], [at + tip + hw, Vector2(1, 0)], [at + tip - hw, Vector2(1, 1)]]
	else:
		corners = [[at - hw, Vector2(0, 1)], [at + hw, Vector2(1, 1)], [at + tip + hw, Vector2(1, 0)], [at + tip - hw, Vector2(0, 0)]]
	var face := axis.cross(side).normalized()
	# The spray's own random in alpha (which sprays are dry or missing on a given tree,
	# see plant_look.gdshaderinc).
	col.a = WHash.to_unit(WHash.h32(base * 7919 + int(length * 1000.0)))
	for cn in corners:
		var p: Vector3 = cn[0]
		var d := (p - centre) / radii
		var cn_n := d.normalized() if d.length() > 0.001 else Vector3.UP
		if face.dot(cn_n) < 0.0:
			face = -face
		b.v.append(p)
		b.n.append((cn_n * (1.0 - face_mix) + face * face_mix).normalized())
		b.uv.append(cn[1])
		b.c.append(col)
	b.ix.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

static func _rng(sp: int, v: int) -> RandomNumberGenerator:
	return Flora._rng(sp, VARIANT_SALT + v)

static func _orth(d: Vector3) -> Vector3:
	return (d.cross(Vector3.UP) if absf(d.y) < 0.95 else d.cross(Vector3.RIGHT)).normalized()

# --- Species look ----------------------------------------------------------------------

## The leaf texture and tint for a species: green sprays tinted toward the species' own
## green, autumn species on the autumn spray. Human worlds stay natural (Flora keeps the
## odd purple species to alien worlds), so the tint here is always gentle.
static func _leaf_look(p: Dictionary) -> Array:
	var leaf: Color = p.get("leaf", Color(0.3, 0.5, 0.2))
	var autumn: bool = p.get("autumn", leaf.h < 0.13 or leaf.h > 0.92)
	if autumn and leaf.h >= 0.09 and leaf.h < 0.5:
		# Gold and yellow: the green spray turned toward the species' yellow (the autumn
		# photo is red and orange, which no tint can make yellow).
		var gold := Color.from_hsv(leaf.h, clampf(leaf.s, 0.4, 0.75), 1.0)
		var g_ref := Color.from_hsv(0.25, 0.55, 1.0)
		var bright := clampf(leaf.v / 0.5, 0.8, 1.15)
		return ["oak", Color(clampf(gold.r / g_ref.r * bright, 0.5, 1.6), clampf(gold.g / g_ref.g * bright, 0.5, 1.4), clampf(gold.b / g_ref.b * bright, 0.3, 1.0))]
	if autumn or leaf.h < 0.06:
		# The autumn photo has its own reds and oranges; browns are it dulled and darkened.
		if leaf.s < 0.42:
			return ["autumn", Color(0.82, 0.68, 0.55)]
		return ["autumn", Color(1, 1, 1).lerp(Color(1.05, 0.95, 0.85), 0.5)]
	# The photo is a mid green (hue ~0.25); shift toward the species' hue and value.
	var want := Color.from_hsv(leaf.h, clampf(leaf.s * 0.75, 0.25, 0.7), 1.0)
	var ref := Color.from_hsv(0.25, 0.55, 1.0)
	var tint := Color(want.r / ref.r, want.g / ref.g, want.b / ref.b)
	tint = Color(1, 1, 1).lerp(tint, 0.45)
	var bright := clampf(leaf.v / 0.5, 0.75, 1.2)
	return ["oak", Color(clampf(tint.r * bright, 0.5, 1.4), clampf(tint.g * bright, 0.5, 1.4), clampf(tint.b * bright, 0.5, 1.4))]

static func _needle_tint(p: Dictionary) -> Color:
	var leaf: Color = p.get("leaf", Color(0.2, 0.35, 0.2))
	# The needle card is near grey: the tint is the colour. Spruce and fir are dark: a
	# bright tint turned their sunlit tops mint green.
	return Color.from_hsv(leaf.h, clampf(leaf.s * 0.85, 0.3, 0.65), clampf(leaf.v * 1.6, 0.3, 0.48))

static func _jit(c: Color, r: RandomNumberGenerator, amt: float) -> Color:
	var f := r.randf_range(1.0 - amt, 1.0 + amt)
	var g := r.randf_range(1.0 - amt * 0.5, 1.0 + amt * 0.5)
	return Color(c.r * f, c.g * f * g, c.b * f, 1.0)

# --- Public builders -------------------------------------------------------------------

## The near mesh for a tree, with LODs, or null for types drawn elsewhere.
static func build(t: String, sp: int, v: int) -> ArrayMesh:
	if not handles(t):
		return null
	var p := Flora.species(t, sp)
	if p.is_empty():
		return null
	var bark := Buf.new()
	var leaves := Buf.new()
	var look := _make(t, p, _rng(sp, v), bark, leaves, false)
	return _commit(bark, leaves, look, true)

## A bush of leaf sprays about `height` metres tall (undergrowth and thornbushes).
static func build_bush(sp: int, height: float, autumn := false) -> ArrayMesh:
	var r := Flora._rng(sp, 6100)
	var bark := Buf.new()
	var leaves := Buf.new()
	# Autumn bushes turn red, orange, gold or brown by species, never one bright orange.
	var hue := r.randf_range(0.2, 0.3)
	var sat := r.randf_range(0.45, 0.65)
	if autumn:
		hue = lerpf(0.02, 0.15, (hue - 0.2) * 10.0)
		sat *= 0.75
	var p := {"autumn": autumn, "leaf": Color.from_hsv(hue, sat, r.randf_range(0.42, 0.55)),
		"bark": Color.from_hsv(0.07, 0.35, 0.3)}
	var look := _leaf_look(p)
	_bush(r, height, look[1], bark, leaves, false)
	return _commit(bark, leaves, [look[0], "bark_oak"], true)

## Far version of a tree as raw surface arrays {"bark": Array, "leaf": Array, "look": [leaf
## texture, bark texture]}, cached per (type, species, variant). Empty for other types.
static func far_parts(t: String, sp: int, v: int) -> Dictionary:
	if not handles(t):
		return {}
	var key := "%s#%d#%d" % [t, sp, v]
	_lock.lock()
	var have = _far.get(key)
	_lock.unlock()
	if have != null:
		return have
	var p := Flora.species(t, sp)
	var out := {}
	if not p.is_empty():
		var bark := Buf.new()
		var leaves := Buf.new()
		var look := _make(t, p, _rng(sp, v), bark, leaves, true)
		out = {"bark": bark.arrays(false), "leaf": leaves.arrays(false), "look": look}
	_lock.lock()
	if _far.size() > 600:
		_far.clear()
	_far[key] = out
	_lock.unlock()
	return out

## Materials for a look: the leaf material for its card texture and the bark material.
## `far` ones are for the merged far mesh, where each tree's own look is baked in.
static func leaf_material(kind: String, far := false) -> Material:
	return _material("leaf:" + kind + (":far" if far else ""))

static func bark_material(kind: String, far := false) -> Material:
	return _material("bark:" + kind + (":far" if far else ""))

# --- Each plant its own ----------------------------------------------------------------

## plant_look.gdshaderinc's plant_look() on the CPU, for the plant standing at world (wx,
## wz): (leaf shade, share of dry sprays, thinning, thin side angle).
static func plant_look(wx: float, wz: float) -> Vector4:
	var cx := (int(floor(wx * 2.0)) + 1048576) & WHash.MASK
	var cz := (int(floor(wz * 2.0)) + 1048576) & WHash.MASK
	var h := WHash.h32(cx ^ WHash.h32(cz))
	var g := WHash.h32(h)
	var r := Vector4(h & 0xFFFF, h >> 16, g & 0xFFFF, g >> 16) / 65536.0
	var dry := r.y * 0.12 if r.y < 0.6 else 0.07 + (r.y - 0.6) * 0.8
	var thin := r.z * 0.15 if r.z < 0.6 else 0.09 + (r.z - 0.6) * 0.6
	return Vector4(r.x * 2.0 - 1.0, dry, thin, r.w * TAU)

## A leaf vertex colour (sRGB) given that look, as plant_leaf() shades it.
static func plant_leaf(c: Color, look: Vector4) -> Color:
	var f := Vector3.ONE.lerp(Vector3(1.35, 1.1, 0.45), look.x) if look.x > 0.0 else Vector3.ONE.lerp(Vector3(0.68, 0.9, 1.2), -look.x)
	f *= 0.65 + 0.63 * fposmod(look.w * 4.7, 1.0)
	# The shader works in linear light; vertex colours are sRGB.
	var out := Color(c.r * pow(f.x, 1.0 / 2.2), c.g * pow(f.y, 1.0 / 2.2), c.b * pow(f.z, 1.0 / 2.2), c.a)
	var grey := out.r * 0.3 + out.g * 0.59 + out.b * 0.11
	out = Color(grey, grey, grey, c.a).lerp(out, 0.7 + 0.55 * fposmod(look.w * 2.3, 1.0))
	if fposmod(c.a * 7.31, 1.0) >= 1.0 - look.y:
		var lum := out.r * 0.3 + out.g * 0.59 + out.b * 0.11
		out = out.lerp(Color(lum * 1.165, lum * 1.018, lum * 0.716, c.a), 0.85)
	return out

## Whether a spray centred at `p` (tree space) with random `card` is missing on that tree.
static func plant_gap(p: Vector3, look: Vector4, card: float) -> bool:
	var d := Vector2(p.x, p.z) + Vector2(0.0001, 0.0001)
	var lop := d.normalized().dot(Vector2(cos(look.w), sin(look.w))) * 0.5 + 0.5
	return card < look.z * (0.35 + 0.65 * lop)

# --- Tree forms ------------------------------------------------------------------------

## Builds the tree into the buffers and returns its look [leaf texture, bark texture].
static func _make(t: String, p: Dictionary, r: RandomNumberGenerator, bark: Buf, leaves: Buf, far: bool) -> Array:
	var form := String(p.get("form", ""))
	if t == "pine":
		var tint := _needle_tint(p)
		if form == "snag":
			_dead(r, p, float(p["height"]), float(p["width"]) * 0.12 + 0.12, bark, far, true)
		else:
			_conifer(r, p, tint, bark, leaves, far)
		return ["needle", "bark_pine"]
	var look := _leaf_look(p)
	var bark_tex := "bark_birch" if form == "column" else "bark_oak"
	match form:
		"dead": _dead(r, p, float(p["height"]), float(p["girth"]), bark, far, false)
		"shrub": _bush(r, float(p["height"]), look[1], bark, leaves, far)
		_: _broadleaf(r, p, look[1], bark, leaves, far)
	return [look[0], bark_tex]

## A limb's polyline from `from` along `dir`, curving by `bend` per segment (up for oaks,
## down for willows) with random wander and, on long limbs, the odd kink.
static func _limb_pts(r: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, segs: int, bend: Vector3, wander: float) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	var d := dir.normalized()
	var p := from
	var step := length / segs
	for i in segs:
		d = (d + bend + Vector3(r.randf_range(-1, 1), r.randf_range(-0.5, 0.5), r.randf_range(-1, 1)) * wander).normalized()
		if segs >= 4 and i > 0 and r.randf() < 0.18:
			# Now and then a kink, where a limb lost its lead and a side shoot took over.
			d = (d + Vector3(r.randf_range(-1, 1), r.randf_range(-0.3, 0.6), r.randf_range(-1, 1)) * 0.6).normalized()
		p += d * step
		pts.append(p)
	return pts

## A trunk's gentle S-bends: [first bend direction, second, phase, phase, amplitude (m)].
static func _bow(r: RandomNumberGenerator, amp: float) -> Array:
	var a := r.randf() * TAU
	var b := a + r.randf_range(1.2, 2.4)
	return [Vector3(cos(a), 0, sin(a)), Vector3(cos(b), 0, sin(b)), r.randf() * TAU, r.randf() * TAU, amp * r.randf_range(0.5, 1.2)]

## Where the trunk has bowed to at fraction `f` of its height (0 at the foot).
static func _bow_at(bw: Array, f: float) -> Vector3:
	var amp: float = bw[4]
	return ((bw[0] as Vector3) * sin(f * PI * 1.1 + float(bw[2])) + (bw[1] as Vector3) * sin(f * PI * 2.6 + float(bw[3])) * 0.5 - (bw[0] as Vector3) * sin(float(bw[2])) - (bw[1] as Vector3) * sin(float(bw[3])) * 0.5) * amp

static func _taper(count: int, r0: float, r1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		out.append(lerpf(r0, r1, float(i) / maxf(count - 1, 1)))
	return out

static func _broadleaf(r: RandomNumberGenerator, p: Dictionary, tint: Color, bark: Buf, leaves: Buf, far: bool) -> void:
	var form := String(p["form"])
	var h: float = float(p["height"]) * r.randf_range(0.92, 1.08)
	var g: float = p["girth"]
	var crown: float = float(p["crown"]) * 1.7
	var bark_col: Color = Color(1, 1, 1) if form == "column" else Color(1, 1, 1).lerp((p["bark"] as Color) * 2.0, 0.3)
	# Proportions per form: how much of the height is bare trunk, how wide the crown is.
	var trunk_frac := 0.36
	var rx := crown
	var elev := Vector2(0.45, 0.95) # limb elevation range (radians)
	var bend := Vector3(0, 0.12, 0)
	match form:
		"oval": trunk_frac = 0.32; rx = crown * 0.85
		"spreading": trunk_frac = 0.32; rx = crown * 1.35; elev = Vector2(0.2, 0.6); bend = Vector3(0, 0.05, 0)
		"weeping": trunk_frac = 0.4; rx = crown * 1.1; elev = Vector2(0.35, 0.8); bend = Vector3(0, -0.22, 0)
		"column": trunk_frac = 0.3; rx = crown * 0.7; elev = Vector2(0.9, 1.25); bend = Vector3(0, 0.1, 0)
	var ht := h * trunk_frac
	var ry := (h - ht) * 0.55
	var centre := Vector3(0, ht + ry, 0)
	var lean := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * float(p.get("lean", 0.0)) * h * 0.4
	centre += lean
	var radii := Vector3(rx, ry, rx)
	# Trunk: rises through the crown and fades out near its top.
	var tpts := PackedVector3Array()
	var bow := _bow(r, h * (0.022 if form == "column" else 0.045))
	var top := ht + ry * 1.2
	var segs := 3 if far else 9
	for i in segs + 1:
		var f := float(i) / segs
		# A short first step so the root flare can fade out over it.
		var y := 0.0 if i == 0 else lerpf(0.45, top, float(i - 1) / (segs - 1))
		tpts.append(Vector3(0, y, 0) + lean * (y / top) + _bow_at(bow, y / h))
	bark.mark()
	_tube(bark, tpts, _taper(tpts.size(), g * 0.85, g * 0.25), 4 if far else 9, bark_col, 0.0 if far else 0.4, 0.0 if far else 0.08)
	bark.mark()
	# Limbs from the upper trunk out toward the crown's shell; twigs from the limbs.
	var tips: Array = [] # [point, outward direction]
	var limbs := int(p.get("branches", 4)) + 3
	var twigs_at: Array = []
	for i in limbs:
		var a := i * 2.39996 + r.randf_range(-0.3, 0.3)
		var e := r.randf_range(elev.x, elev.y)
		var dir := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
		var y0 := lerpf(ht * 0.95, ht + ry * 1.1, float(i) / limbs) + r.randf_range(-0.3, 0.3)
		var from := Vector3(0, y0, 0) + lean * (y0 / top) + _bow_at(bow, y0 / h)
		# Reach: most of the way to the crown shell along that direction.
		var rel := from - centre
		var reach := _shell_reach(rel, dir, radii) * r.randf_range(0.7, 0.92)
		if reach < 0.4:
			continue
		if not far:
			var pts := _limb_pts(r, from, dir, reach, 6, bend * 0.5, 0.3)
			_tube(bark, pts, _taper(pts.size(), g * lerpf(0.55, 0.35, float(i) / limbs), g * 0.08), 5, bark_col, 0.0, 0.06)
			twigs_at.append([pts, dir])
			tips.append([pts[pts.size() - 1], dir])
		else:
			tips.append([from + dir * reach, dir])
	bark.mark()
	if not far:
		for tw in twigs_at:
			var pts: PackedVector3Array = tw[0]
			for k in r.randi_range(2, 3):
				var at := pts[1 + r.randi() % (pts.size() - 1)]
				var dir: Vector3 = (tw[1] as Vector3) + Vector3(r.randf_range(-0.8, 0.8), r.randf_range(-0.2, 0.5) + bend.y, r.randf_range(-0.8, 0.8))
				var reach := _shell_reach(at - centre, dir.normalized(), radii) * r.randf_range(0.6, 0.9)
				if reach < 0.3:
					continue
				var tp := _limb_pts(r, at, dir, reach, 3, bend * 0.67, 0.3)
				_tube(bark, tp, _taper(tp.size(), g * 0.12, g * 0.03), 4, bark_col)
				tips.append([tp[tp.size() - 1], dir.normalized()])
	bark.mark()
	# Leaf sprays fill the crown's shell, more of them on the outside; a few deeper and
	# darker ones keep the crown from looking hollow.
	var size: float = float(p.get("card", 1.2)) * clampf(h / 9.0, 0.85, 1.2) * 0.72
	# Sprays per square metre of crown surface: enough overlap that the crown reads solid
	# from outside while light still breaks through at the rim.
	var area := 4.0 * PI * pow((rx * rx + ry * rx + rx * ry) / 3.0, 1.0)
	var count := clampi(int(area * 3.4 / (size * size)), 140, 340)
	if far:
		count = clampi(count / 8, 16, 40)
		size *= 2.4
	var weep := form == "weeping"
	for i in count:
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-0.75, 1), r.randf_range(-1, 1)).normalized()
		var depth := r.randf_range(0.62, 1.0) if r.randf() > 0.18 else r.randf_range(0.3, 0.6)
		if far:
			depth = r.randf_range(0.55, 0.85)
		var at := centre + dir * radii * depth
		var out := (at - centre) / radii
		out = out.normalized()
		var axis := (out + Vector3(r.randf_range(-0.5, 0.5), 0.35, r.randf_range(-0.5, 0.5))).normalized()
		var len := size * r.randf_range(0.8, 1.2)
		var wid := len
		if weep:
			# Hanging curtains: long sprays pointing down from the crown's outer half.
			axis = (Vector3.DOWN * 2.0 + out * 0.35).normalized()
			len *= 1.9
			wid *= 0.75
			at += Vector3.UP * len * 0.35
		var side := _orth(axis).rotated(axis, r.randf_range(-0.9, 0.9))
		# Stem end sits a little inside the shell so the spray grows outward.
		at -= axis * len * 0.3
		var shade := lerpf(0.68, 1.0, clampf((depth - 0.3) / 0.7, 0.0, 1.0)) * lerpf(0.9, 1.08, clampf((at.y - ht) / (2.0 * ry), 0.0, 1.0)) * 1.12
		_card(leaves, at, axis, side, len, wid, _jit(tint, r, 0.1) * shade, centre, radii, false)

## Distance from `rel` (relative to the crown centre) along `dir` to the crown ellipsoid.
static func _shell_reach(rel: Vector3, dir: Vector3, radii: Vector3) -> float:
	var o := rel / radii
	var d := dir / radii
	var a := d.dot(d)
	var b := 2.0 * o.dot(d)
	var c := o.dot(o) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return 0.0
	return maxf((-b + sqrt(disc)) / (2.0 * a), 0.0)

static func _conifer(r: RandomNumberGenerator, p: Dictionary, tint: Color, bark: Buf, leaves: Buf, far: bool) -> void:
	var form := String(p["form"])
	var h: float = float(p["height"]) * r.randf_range(0.92, 1.08)
	var w: float = float(p["width"]) * 0.62
	var rb: float = float(p["width"]) * 0.12 + 0.12
	var base_frac := 0.14
	var spacing := 0.37
	var per := 7
	var droop: float = float(p.get("droop", 0.5))
	match form:
		"cypress": base_frac = 0.06; spacing = 0.32; per = 7
		"larch": base_frac = 0.25; spacing = 0.6; per = 5
		"fir": droop *= 0.6
	var bark_col := Color(1, 1, 1).lerp((p["bark"] as Color) * 2.2, 0.3)
	var tpts := PackedVector3Array()
	var trad := PackedFloat32Array()
	var bow := _bow(r, h * 0.03 + 0.15)
	var steps: Array = [0.0, 0.035, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0]
	for f in steps:
		tpts.append(Vector3(0, h * f, 0) + _bow_at(bow, f))
		# The trunk thins fast up inside the crown, where the boughs hide it.
		trad.append(lerpf(rb, rb * 0.5, f * 3.0) if f < 0.34 else (lerpf(rb * 0.5, rb * 0.22, (f - 0.33) * 3.0) if f < 0.67 else lerpf(rb * 0.22, 0.03, (f - 0.67) * 3.0)))
	bark.mark()
	_tube(bark, tpts, trad, 4 if far else 8, bark_col, 0.0 if far else 0.35, 0.0 if far else 0.07)
	bark.mark()
	bark.mark()
	bark.mark()
	var yb := h * base_frac
	var centre := Vector3(0, (yb + h) * 0.5, 0)
	var radii := Vector3(w, (h - yb) * 0.6, w)
	if far:
		spacing *= 2.6
		per = 4
	var whorls := maxi(int((h - yb) / spacing), 3)
	var rot := r.randf() * TAU
	for i in whorls:
		var t := float(i) / whorls
		var y := yb + (h - yb - 0.6) * t + r.randf_range(-0.08, 0.08)
		# Classic spruce taper: widest low down, a slight belly, a narrow spire.
		var rad := (w * pow(1.0 - t, 0.85) + 0.3) * r.randf_range(0.88, 1.1)
		rot += 2.39996
		var dr := droop * lerpf(0.75, 0.25, t) + 0.12
		for k in per:
			var a := rot + TAU * k / per + r.randf_range(-0.25, 0.25)
			var out := Vector3(cos(a), 0, sin(a))
			var axis := (out - Vector3(0, dr, 0)).normalized()
			var len := rad * r.randf_range(0.9, 1.12) * (1.15 if far else 1.0)
			var wid := clampf(len * 0.62, 0.45, 1.6) * (1.5 if far else 1.0)
			var shade := lerpf(0.8, 1.08, t) * r.randf_range(0.92, 1.05)
			var col := _jit(tint, r, 0.07) * shade
			var at := Vector3(0, y, 0) + _bow_at(bow, y / h) + out * 0.05
			# The bough droops: flat card plus a steeper one across it, for depth.
			var flat := axis.cross(Vector3.UP).normalized()
			if flat.length() < 0.01:
				flat = Vector3.RIGHT
			var side := flat.rotated(axis, r.randf_range(-0.25, 0.25))
			_card(leaves, at, axis, side, len, wid, col, centre, radii, true, 0.35)
			if not far:
				_card(leaves, at + Vector3.UP * 0.05, axis, side.rotated(axis, 1.25), len * 0.85, wid * 0.8, col * 0.92, centre, radii, true, 0.35)
	# Leader: the spire above the last whorl.
	for k in 2:
		var side := Vector3(cos(k * PI * 0.5 + rot), 0, sin(k * PI * 0.5 + rot))
		_card(leaves, Vector3(0, h - 1.4, 0) + _bow_at(bow, (h - 1.4) / h), Vector3.UP, side, 1.6, 0.7, tint, centre, radii, true, 0.4)

static func _dead(r: RandomNumberGenerator, p: Dictionary, h: float, g: float, bark: Buf, far: bool, conifer: bool) -> void:
	var col := Color(0.82, 0.8, 0.78)
	var tpts := PackedVector3Array()
	var hh := h * (0.75 if conifer else 0.7) * r.randf_range(0.9, 1.1)
	for i in 5:
		var f := i / 4.0
		tpts.append(Vector3(sin(f * 4.0 + r.randf()) * 0.12 * f, hh * f, cos(f * 3.0) * 0.12 * f))
	bark.mark()
	_tube(bark, tpts, _taper(5, g, g * 0.2), 4 if far else 8, col, 0.0 if far else 0.4)
	bark.mark()
	if far:
		bark.mark()
		bark.mark()
		return
	for i in r.randi_range(4, 7):
		var a := i * 2.39996 + r.randf()
		var y := hh * r.randf_range(0.35, 0.92)
		var dir := Vector3(cos(a), r.randf_range(0.1, 0.9) if not conifer else r.randf_range(-0.3, 0.2), sin(a))
		var pts := _limb_pts(r, Vector3(0, y, 0), dir, r.randf_range(1.0, 2.6) * (0.6 if conifer else 1.0), 3, Vector3(0, 0.08, 0), 0.25)
		_tube(bark, pts, _taper(pts.size(), g * 0.35, 0.015), 5, col)
	bark.mark()
	bark.mark()

## A bush: a few stems and a rounded mass of leaf sprays, `height` metres tall.
static func _bush(r: RandomNumberGenerator, height: float, tint: Color, bark: Buf, leaves: Buf, far: bool) -> void:
	var ry := height * 0.5
	var rx := height * r.randf_range(0.55, 0.75)
	var centre := Vector3(0, ry * 0.95, 0)
	var radii := Vector3(rx, ry, rx * r.randf_range(0.85, 1.1))
	bark.mark()
	if not far:
		for i in 3:
			var a := i * 2.1 + r.randf()
			var pts := _limb_pts(r, Vector3(cos(a), 0, sin(a)) * 0.05, Vector3(cos(a) * 0.4, 1, sin(a) * 0.4), height * 0.55, 2, Vector3.ZERO, 0.2)
			_tube(bark, pts, _taper(pts.size(), 0.03 + height * 0.01, 0.01), 4, Color(0.9, 0.85, 0.8))
	bark.mark()
	bark.mark()
	bark.mark()
	var count := clampi(int(rx * ry * rx * 30.0), 24, 70)
	var size := clampf(height * 0.55, 0.35, 1.1)
	if far:
		count = maxi(count / 5, 5)
		size *= 1.8
	for i in count:
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-0.35, 1), r.randf_range(-1, 1)).normalized()
		var depth := r.randf_range(0.55, 1.0)
		var at := centre + dir * radii * depth
		var out := ((at - centre) / radii).normalized()
		var axis := (out + Vector3(0, 0.45, 0)).normalized()
		var len := size * r.randf_range(0.8, 1.2)
		var side := _orth(axis).rotated(axis, r.randf_range(-1.0, 1.0))
		at -= axis * len * 0.35
		at.y = maxf(at.y, 0.02)
		var shade := lerpf(0.7, 1.0, depth) * lerpf(0.88, 1.06, clampf(at.y / height, 0.0, 1.0)) * 1.1
		_card(leaves, at, axis, side, len, len, _jit(tint, r, 0.1) * shade, centre, radii, false)

# --- Mesh assembly ---------------------------------------------------------------------

## Builds the ArrayMesh: bark (with LODs that drop twigs, then limbs) and leaves (with LODs
## that keep a half, then a quarter of the sprays).
static func _commit(bark: Buf, leaves: Buf, look: Array, lods: bool) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not bark.v.is_empty():
		var bl := {}
		if lods and bark.marks.size() >= 4:
			# marks: [start, trunk end, limbs end, twigs end]
			if int(bark.marks[2]) < bark.ix.size():
				bl[0.1] = bark.ix.slice(0, bark.marks[2])
			if int(bark.marks[1]) < int(bark.marks[2]) or int(bark.marks[1]) < bark.ix.size():
				bl[0.25] = bark.ix.slice(0, bark.marks[1])
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.arrays(true), [], bl)
		m.surface_set_material(m.get_surface_count() - 1, bark_material(look[1]))
	if not leaves.v.is_empty():
		var ll := {}
		if lods:
			# Every second, then every fourth spray: thinner everywhere, never a bald top.
			var half := PackedInt32Array()
			var quarter := PackedInt32Array()
			for q in leaves.ix.size() / 6:
				if q % 2 == 0:
					half.append_array(leaves.ix.slice(q * 6, q * 6 + 6))
				if q % 4 == 0:
					quarter.append_array(leaves.ix.slice(q * 6, q * 6 + 6))
			if quarter.size() >= 12:
				ll[0.12] = half
				ll[0.3] = quarter
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.arrays(false), [], ll)
		m.surface_set_material(m.get_surface_count() - 1, leaf_material(look[0]))
	return m

const LEAF_TEX := {"oak": "oak_twig_card", "autumn": "autumn_twig_card", "needle": "needles_card"}

static func _material(key: String) -> Material:
	_lock.lock()
	var m = _mats.get(key)
	_lock.unlock()
	if m != null:
		return m
	var kind := key.get_slice(":", 1)
	var near := not key.ends_with(":far")
	if key.begins_with("leaf:"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://src/world/foliage.gdshader")
		var path := "res://assets/textures/%s.png" % LEAF_TEX.get(kind, "oak_twig_card")
		sm.set_shader_parameter("albedo_tex", load(path) if ResourceLoader.exists(path) else Materials.get_mat("leaf_card_w").get_shader_parameter("albedo_tex"))
		sm.set_shader_parameter("crown_normals", true)
		sm.set_shader_parameter("individual", near)
		sm.set_shader_parameter("back", Color(0.42, 0.5, 0.16) if kind != "autumn" else Color(0.55, 0.32, 0.08))
		# Gentle: crowns lean and leaves tremble, never thrash.
		sm.set_shader_parameter("sway", 0.5 if kind == "needle" else 0.8)
		sm.set_shader_parameter("alpha_cut", 0.4 if kind == "needle" else 0.5)
		# Boughs are deep in shade where they leave the trunk, lit out at their tips.
		sm.set_shader_parameter("stem_shade", 0.35 if kind == "needle" else 0.0)
		sm.set_shader_parameter("crown_up", 0.45 if kind == "needle" else 0.2)
		m = sm
	else:
		var bm := ShaderMaterial.new()
		bm.shader = load("res://src/world/bark.gdshader")
		var tex := "bark_birch" if kind == "bark_birch" else "bark_oak"
		var alb := Materials.photo(tex, "albedo")
		bm.set_shader_parameter("albedo_tex", alb if alb != null else Materials.photo(tex, "detail"))
		var nrm := Materials.photo(tex, "normal")
		if nrm != null:
			bm.set_shader_parameter("has_normal", true)
			bm.set_shader_parameter("normal_tex", nrm)
		if kind == "bark_pine":
			bm.set_shader_parameter("albedo", Color(0.8, 0.68, 0.6))
		bm.set_shader_parameter("individual", near)
		bm.set_shader_parameter("moss_scale", 0.4 if kind == "bark_birch" else 1.0)
		m = bm
	_lock.lock()
	if _mats.has(key):
		m = _mats[key]
	else:
		_mats[key] = m
	_lock.unlock()
	return m
