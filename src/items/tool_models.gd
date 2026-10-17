class_name ToolModels
## Real models for the tools and weapons that have no kit model: each one built from the
## parts the real thing is made of, at its real size, in materials that read as what they
## are (forged steel with a ground edge, cast bronze, grained ash and oak, wrapped leather,
## knapped flint, wax, glass). Handles run along +Y with the hand near the bottom (or at
## the model's "grip" meta); an axe's edge faces -Z, a pick's point and a hammer's face +X;
## spear points and daggers along +Y. (Bows and guns are Firearms.)
##
## Built on the main thread (they are shown in the hand and on shop counters).

static var _mats := {}
static var _tex := {}

## Materials of their own: the world's materials are scaled for buildings and terrain
## (their textures repeat every metre or two), which leaves a hand-sized tool one flat
## colour. These carry grain, hammer marks and wear at the scale of the thing held.
static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match name:
		"it_steel":
			# Ground and polished: bright, a little brushed along the blade.
			# Not fully metallic: with nothing bright to reflect (a cave, a capture without a
			# sky) a pure metal renders black; real steel still shows its grey there.
			m.albedo_color = Color(0.62, 0.63, 0.65)
			m.metallic = 0.72
			m.roughness = 0.3
			m.roughness_texture = _noise("brushed", 0.02, Vector2(1.0, 14.0), Color(0.55, 0.55, 0.55), Color(1, 1, 1))
			m.uv1_scale = Vector3(18.0, 3.0, 1.0)
		"it_iron":
			# Forged and blackened: dark, hammer-marked, rough where it wasn't ground.
			m.albedo_color = Color(0.45, 0.45, 0.46)
			m.metallic = 0.45
			m.roughness = 0.58
			m.albedo_texture = _noise("hammered", 0.05, Vector2.ONE, Color(0.7, 0.7, 0.7), Color(1, 1, 1), true)
			m.normal_enabled = true
			m.normal_texture = _noise("hammered", 0.05, Vector2.ONE, Color.BLACK, Color.WHITE, true, true)
			m.normal_scale = 0.5
			m.uv1_scale = Vector3(10.0, 10.0, 1.0)
		"it_bronze":
			m.albedo_color = Color(0.74, 0.5, 0.27)
			m.metallic = 0.8
			m.roughness = 0.34
			# Patches of dull green-brown patina.
			m.albedo_texture = _noise("patina", 0.04, Vector2.ONE, Color(0.62, 0.72, 0.6), Color(1, 1, 1))
			m.uv1_scale = Vector3(8.0, 8.0, 1.0)
		"it_brass":
			m.albedo_color = Color(0.8, 0.63, 0.33)
			m.metallic = 0.8
			m.roughness = 0.3
		"it_gold":
			m.albedo_color = Color(1.0, 0.78, 0.36)
			m.metallic = 0.85
			m.roughness = 0.22
		"it_wood":
			# Straight grain along the handle, darker late-wood lines.
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.62
			m.albedo_texture = _noise("grain", 0.03, Vector2(1.0, 18.0), Color(0.62, 0.62, 0.62), Color(1, 1, 1))
			m.normal_enabled = true
			m.normal_texture = _noise("grain", 0.03, Vector2(1.0, 18.0), Color.BLACK, Color.WHITE, false, true)
			m.normal_scale = 0.3
			m.uv1_scale = Vector3(30.0, 2.0, 1.0)
		"it_leather":
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.72
			m.albedo_texture = _noise("leather", 0.09, Vector2.ONE, Color(0.72, 0.72, 0.72), Color(1, 1, 1), true)
			m.normal_enabled = true
			m.normal_texture = _noise("leather", 0.09, Vector2.ONE, Color.BLACK, Color.WHITE, true, true)
			m.normal_scale = 0.35
			m.uv1_scale = Vector3(14.0, 14.0, 1.0)
		"it_cord":
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.95
			m.albedo_texture = _noise("cord", 0.08, Vector2(4.0, 1.0), Color(0.7, 0.7, 0.7), Color(1, 1, 1))
			m.uv1_scale = Vector3(40.0, 40.0, 1.0)
		"it_flint":
			# Knapped flint: glassy-dull, scalloped.
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.38
			m.albedo_texture = _noise("flint", 0.06, Vector2.ONE, Color(0.75, 0.75, 0.75), Color(1, 1, 1), true)
			m.normal_enabled = true
			m.normal_texture = _noise("flint", 0.06, Vector2.ONE, Color.BLACK, Color.WHITE, true, true)
			m.uv1_scale = Vector3(9.0, 9.0, 1.0)
		"it_stone":
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.85
			m.albedo_texture = _noise("granite", 0.15, Vector2.ONE, Color(0.7, 0.7, 0.7), Color(1, 1, 1))
			m.uv1_scale = Vector3(6.0, 6.0, 1.0)
		"it_bone":
			m.albedo_color = Color(0.9, 0.86, 0.74)
			m.roughness = 0.5
			m.albedo_texture = _noise("bone", 0.04, Vector2(1.0, 6.0), Color(0.8, 0.78, 0.72), Color(1, 1, 1))
			m.uv1_scale = Vector3(10.0, 2.0, 1.0)
		"it_wax":
			# Wax lets light into it a little; it doesn't glow.
			m.albedo_color = Color(0.94, 0.9, 0.78)
			m.roughness = 0.42
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.35
		"it_glass":
			m.albedo_color = Color(0.86, 0.92, 0.9, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.roughness = 0.04
			m.metallic_specular = 0.9
			m.rim_enabled = true
			m.rim = 0.4
			m.rim_tint = 1.0
		"it_polymer":
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.roughness = 0.62
			m.albedo_texture = _noise("polymer", 0.25, Vector2.ONE, Color(0.85, 0.85, 0.85), Color(1, 1, 1))
			m.uv1_scale = Vector3(12.0, 12.0, 1.0)
		"it_rubber":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.roughness = 0.88
		"it_paint":
			# Painted steel: the colour comes from the part, chipped to bare metal in places.
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.5
			m.metallic = 0.25
			m.albedo_texture = _noise("chips", 0.07, Vector2.ONE, Color(0.78, 0.78, 0.78), Color(1, 1, 1), true)
			m.uv1_scale = Vector3(8.0, 8.0, 1.0)
		"it_cloth":
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.96
			m.albedo_texture = _noise("weave", 0.3, Vector2.ONE, Color(0.78, 0.78, 0.78), Color(1, 1, 1))
			m.uv1_scale = Vector3(20.0, 20.0, 1.0)
		"it_pitch":
			# Rag soaked in pitch: near black, a tarry sheen, lumpy where it pooled.
			m.albedo_color = Color(0.11, 0.085, 0.06)
			m.roughness = 0.38
			m.albedo_texture = _noise("pitch", 0.12, Vector2.ONE, Color(0.55, 0.5, 0.45), Color(1, 1, 1), true)
			m.normal_enabled = true
			m.normal_texture = _noise("pitch", 0.12, Vector2.ONE, Color.BLACK, Color.WHITE, true, true)
			m.normal_scale = 0.8
			m.uv1_scale = Vector3(10.0, 10.0, 1.0)
		"it_char":
			# Burnt rag and wood: matt, grey-black, ash on the ridges.
			m.albedo_color = Color(0.09, 0.08, 0.075)
			m.roughness = 0.97
			m.albedo_texture = _noise("char", 0.2, Vector2.ONE, Color(0.6, 0.6, 0.6), Color(2.4, 2.3, 2.2), true)
			m.uv1_scale = Vector3(8.0, 8.0, 1.0)
		"it_paper":
			m.albedo_color = Color(0.93, 0.89, 0.78)
			m.roughness = 0.9
		"it_feather":
			m.albedo_color = Color(0.95, 0.94, 0.9)
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"it_chitin":
			# A creature's shell: dark, glossy, its own colour under a wet sheen.
			m.albedo_color = Color(1, 1, 1)
			m.roughness = 0.28
			m.clearcoat_enabled = true
			m.clearcoat = 0.7
			m.albedo_texture = _noise("chitin", 0.06, Vector2(1.0, 3.0), Color(0.6, 0.6, 0.6), Color(1, 1, 1), true)
			m.uv1_scale = Vector3(8.0, 4.0, 1.0)
		"it_crystal":
			# Alien crystal: only alien things shine.
			m.albedo_color = Color(0.7, 0.75, 1.0, 0.75)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.roughness = 0.08
			m.emission_enabled = true
			m.emission = Color(0.35, 0.4, 0.95)
			m.emission_energy_multiplier = 0.7
			m.rim_enabled = true
			m.rim = 0.6
		_:
			return Materials.get_mat(name)
	_mats[name] = m
	return m

## A tileable noise texture, from `lo` to `hi`; `stretch` draws it out (grain along Y).
static func _noise(key: String, freq: float, stretch: Vector2, lo: Color, hi: Color, cells := false, normal := false) -> NoiseTexture2D:
	var id := "%s|%s|%s" % [key, stretch, normal]
	if _tex.has(id):
		return _tex[id]
	var n := FastNoiseLite.new()
	n.seed = key.hash() & 0xFFFF
	n.frequency = freq
	n.fractal_octaves = 4
	if cells:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	if stretch != Vector2.ONE:
		# Stretched: sample a wide, short window of the noise.
		n.frequency = freq
		t.width = int(256 * stretch.x)
		t.height = int(256 / stretch.y * 4.0)
		t.height = maxi(t.height, 16)
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = 4.0
	else:
		var g := Gradient.new()
		g.set_color(0, lo)
		g.set_color(1, hi)
		t.color_ramp = g
	_tex[id] = t
	return t

# --- Shapes ----------------------------------------------------------------------------

## A turned shape: `prof` is (radius, y) from bottom to top, spun round Y. Normals follow
## the profile's slope, so domes and flares shade right.
static func lathe(k: MeshKit, m: String, xf: Transform3D, prof: Array, segs := 12, col := Color.WHITE, oval := 1.0) -> void:
	var n := prof.size()
	for i in n - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		if a.distance_to(b) < 1e-6:
			continue
		var na := _prof_normal(prof, i)
		var nb := _prof_normal(prof, i + 1)
		for s in segs:
			var t0 := TAU * s / segs
			var t1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(t0), 0, sin(t0) * oval)
			var d1 := Vector3(cos(t1), 0, sin(t1) * oval)
			var p00 := d0 * a.x + Vector3(0, a.y, 0)
			var p01 := d1 * a.x + Vector3(0, a.y, 0)
			var p10 := d0 * b.x + Vector3(0, b.y, 0)
			var p11 := d1 * b.x + Vector3(0, b.y, 0)
			var n00 := Vector3(cos(t0) * na.x, na.y, sin(t0) * na.x / oval).normalized()
			var n01 := Vector3(cos(t1) * na.x, na.y, sin(t1) * na.x / oval).normalized()
			var n10 := Vector3(cos(t0) * nb.x, nb.y, sin(t0) * nb.x / oval).normalized()
			var n11 := Vector3(cos(t1) * nb.x, nb.y, sin(t1) * nb.x / oval).normalized()
			k.tri(m, xf, p00, p11, p01, n00, n11, n01, col)
			k.tri(m, xf, p00, p10, p11, n00, n10, n11, col)

## The outward normal (radial, y) of a lathe profile at point i.
static func _prof_normal(prof: Array, i: int) -> Vector2:
	var p0: Vector2 = prof[maxi(i - 1, 0)]
	var p1: Vector2 = prof[mini(i + 1, prof.size() - 1)]
	var t := p1 - p0
	if t.length() < 1e-6:
		return Vector2(1, 0)
	return Vector2(t.y, -t.x).normalized()

## Sweeps closed cross-sections through stations: each {p: centre, x: and z: the
## section's axes, s: PackedVector2Array (same count every station)}. `flat` gives each
## face its own normal (ground metal facets); otherwise normals are smoothed round the
## section. The ends are capped.
static func sweep(k: MeshKit, m: String, xf: Transform3D, st: Array, flat := true, col := Color.WHITE, caps := true) -> void:
	var pts: Array = []
	for s in st:
		var ring := PackedVector3Array()
		for q in (s["s"] as PackedVector2Array):
			ring.append(Vector3(s["p"]) + Vector3(s["x"]) * q.x + Vector3(s["z"]) * q.y)
		pts.append(ring)
	var cnt: int = (st[0]["s"] as PackedVector2Array).size()
	for i in st.size() - 1:
		var c0: Vector3 = st[i]["p"]
		var c1: Vector3 = st[i + 1]["p"]
		for j in cnt:
			var j2 := (j + 1) % cnt
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j2]
			var c: Vector3 = pts[i + 1][j2]
			var d: Vector3 = pts[i + 1][j]
			var out := (a + b + c + d) * 0.25 - (c0 + c1) * 0.5
			var fn := (b - a).cross(d - a)
			if fn.length() < 1e-12:
				fn = (c - b).cross(d - b)
			if fn.dot(out) < 0.0:
				fn = -fn
			fn = fn.normalized()
			var na := fn
			var nb := fn
			var nc := fn
			var nd := fn
			if not flat:
				na = (a - c0).normalized()
				nb = (b - c0).normalized()
				nc = (c - c1).normalized()
				nd = (d - c1).normalized()
			# Front-facing order: counter-clockwise seen along -fn.
			if (b - a).cross(c - a).dot(fn) > 0.0:
				k.tri(m, xf, a, c, b, na, nc, nb, col)
				k.tri(m, xf, a, d, c, na, nd, nc, col)
			else:
				k.tri(m, xf, a, b, c, na, nb, nc, col)
				k.tri(m, xf, a, c, d, na, nc, nd, col)
	if caps:
		for e in [0, st.size() - 1]:
			var ring: PackedVector3Array = pts[e]
			var c: Vector3 = st[e]["p"]
			var other: Vector3 = st[1 if e == 0 else st.size() - 2]["p"]
			var n := (c - other).normalized()
			for j in cnt:
				var a := ring[j]
				var b := ring[(j + 1) % cnt]
				if (a - c).cross(b - c).dot(n) > 0.0:
					k.tri(m, xf, c, b, a, n, n, n, col)
				else:
					k.tri(m, xf, c, a, b, n, n, n, col)

## A station for sweep.
static func _at(p: Vector3, x: Vector3, z: Vector3, s: PackedVector2Array) -> Dictionary:
	return {"p": p, "x": x, "z": z, "s": s}

## Cross-sections. A double-edged blade: a flat ground bevel either side of a ridge.
static func sec_blade2(w: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(w, 0), Vector2(w * 0.35, t * 0.5), Vector2(-w * 0.35, t * 0.5), Vector2(-w, 0), Vector2(-w * 0.35, -t * 0.5), Vector2(w * 0.35, -t * 0.5)])

## A single edge (+x) with a flat spine (-x).
static func sec_blade1(w: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(w, 0), Vector2(-w * 0.1, t * 0.5), Vector2(-w, t * 0.45), Vector2(-w, -t * 0.45), Vector2(-w * 0.1, -t * 0.5)])

## A chamfered rectangle, half sizes a × b.
static func sec_rect(a: float, b: float, ch := 0.25) -> PackedVector2Array:
	var ca := a * ch
	var cb := b * ch
	return PackedVector2Array([Vector2(a, b - cb), Vector2(a - ca, b), Vector2(-a + ca, b), Vector2(-a, b - cb), Vector2(-a, -b + cb), Vector2(-a + ca, -b), Vector2(a - ca, -b), Vector2(a, -b + cb)])

## A rounded (n-gon) section, half sizes a × b.
static func sec_round(a: float, b: float, n := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * i / n
		out.append(Vector2(cos(t) * a, sin(t) * b))
	return out

# --- Parts -----------------------------------------------------------------------------

## A wooden handle from y0 to y1, thicker toward the hand end, with a swelled knob at the
## butt so it doesn't slip, a little oval like a real one.
static func haft(k: MeshKit, y0: float, y1: float, r0: float, r1: float, col: Color, knob := true, m := "it_wood") -> void:
	var prof := []
	if knob:
		prof.append(Vector2(0.0, y0))
		prof.append(Vector2(r0 * 0.9, y0 + 0.002))
		prof.append(Vector2(r0 * 1.22, y0 + 0.012))
		prof.append(Vector2(r0 * 1.05, y0 + 0.03))
	else:
		prof.append(Vector2(0.0, y0))
		prof.append(Vector2(r0 * 0.92, y0))
		prof.append(Vector2(r0, y0 + 0.006))
	var n := 8
	for i in range(1, n + 1):
		var f := float(i) / n
		var y := lerpf(y0 + 0.04, y1, f)
		prof.append(Vector2(lerpf(r0, r1, f), y))
	prof.append(Vector2(r1 * 0.85, y1 + 0.003))
	prof.append(Vector2(0.0, y1 + 0.004))
	lathe(k, m, Transform3D.IDENTITY, prof, 10, col, 0.8)

## A long straight pole (spears, staffs), round.
static func pole(k: MeshKit, y0: float, y1: float, r0: float, r1: float, col: Color, m := "it_wood") -> void:
	lathe(k, m, Transform3D.IDENTITY, [Vector2(0, y0), Vector2(r0 * 0.9, y0), Vector2(r0, y0 + 0.005), Vector2(lerpf(r0, r1, 0.5), (y0 + y1) * 0.5), Vector2(r1, y1 - 0.005), Vector2(r1 * 0.9, y1), Vector2(0, y1)], 10, col)

## A strip of leather (or cord) wound round a handle of radius r from y0 to y1.
static func wrap_grip(k: MeshKit, y0: float, y1: float, r: float, col: Color, m := "it_leather", width := 0.014, thick := 0.0022) -> void:
	var turns := (y1 - y0) / (width * 0.92)
	var steps := int(turns * 14.0)
	var st := []
	for i in steps + 1:
		var f := float(i) / steps
		var a := f * turns * TAU
		var y := lerpf(y0, y1, f)
		var out := Vector3(cos(a), 0, sin(a) * 0.82)
		var tang := Vector3(-sin(a), 0, cos(a)).normalized()
		var p := out * (r + thick * 0.5) + Vector3(0, y, 0)
		var up := Vector3(0, 1, 0)
		# The strip lies along the handle's surface, leaning with the winding.
		var across := (up - tang * up.dot(tang)).normalized()
		st.append(_at(p, across, out.normalized(), sec_rect(width * 0.5, thick * 0.5, 0.35)))
	sweep(k, m, Transform3D.IDENTITY, st, false, col, true)

## Turns of cord lashed round a joint (a stone head bound to its haft).
static func lash(k: MeshKit, c: Vector3, r: float, turns: int, spread: float, col: Color, axis := Vector3.UP) -> void:
	var b := Basis(Vector3.UP.cross(axis).normalized(), Vector3.UP.angle_to(axis)) if absf(axis.normalized().y) < 0.999 else Basis.IDENTITY
	for i in turns:
		var y := (float(i) / maxf(turns - 1, 1) - 0.5) * spread
		var tilt := Basis(Vector3.RIGHT, 0.25 * (1.0 if i % 2 == 0 else -1.0))
		var ring := []
		for s in 13:
			var a := TAU * s / 12.0
			ring.append(_at(Vector3(cos(a) * r, 0, sin(a) * r), Vector3.UP, Vector3(cos(a), 0, sin(a)), sec_round(0.0025, 0.0025, 5)))
		sweep(k, "it_cord", Transform3D(b * tilt, c + b * Vector3(0, y, 0)), ring, false, col, false)

## A blade along +Y from y0, `len` long: `w` half-width at the base, narrowing to the point
## over the last `tip` of its length; `curve` bends it toward +X (a sabre), `belly` widens
## the middle (a leaf spear), `single` grinds one edge only (edge at +X).
static func blade(k: MeshKit, m: String, y0: float, len: float, w: float, t: float, tip := 0.18, curve := 0.0, single := false, belly := 0.0, col := Color.WHITE, z_flat := false) -> void:
	var st := []
	var n := 16
	for i in n + 1:
		var f := float(i) / n
		var hw := w * (1.0 + belly * sin(f * PI) - 0.15 * f)
		if f > 1.0 - tip:
			var g := (f - (1.0 - tip)) / tip
			hw *= sqrt(maxf(0.0, 1.0 - g * g)) if not single else (1.0 - g)
		hw = maxf(hw, 0.0004)
		var th := t * lerpf(1.0, 0.45, f)
		var x := curve * f * f * len
		var p := Vector3(x, y0 + f * len, 0)
		var dir := Vector3(curve * 2.0 * f * len, len, 0).normalized()
		var side := Vector3(dir.y, -dir.x, 0)
		var s := sec_blade1(hw, th) if single else sec_blade2(hw, th)
		if single:
			# A single-edged blade's spine runs straight to the point: shift the section so
			# the spine stays put while the edge sweeps up to meet it.
			var shifted := PackedVector2Array()
			for q in s:
				shifted.append(q + Vector2(hw - w * 0.85, 0) * (1.0 if f > 1.0 - tip else 0.0))
			s = shifted
		st.append(_at(p, side, Vector3(0, 0, 1) if not z_flat else Vector3(0, 0, 1), s))
	sweep(k, m, Transform3D.IDENTITY, st, true, col)

## A sword's cross-guard: a bar `half` long each side at y, its ends flaring.
static func guard(k: MeshKit, m: String, y: float, half: float, h: float, t: float, col := Color.WHITE, droop := 0.0) -> void:
	var st := []
	for i in 9:
		var f := float(i) / 8.0 * 2.0 - 1.0
		var x := f * half
		var flare := 1.0 + 0.5 * pow(absf(f), 4.0)
		st.append(_at(Vector3(x, y - droop * f * f, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), sec_rect(h * 0.5 * flare, t * 0.5, 0.3)))
	# Sweep along X: rotate stations so the path runs along x.
	var fixed := []
	for s in st:
		fixed.append(_at(s["p"], Vector3(0, 1, 0), Vector3(0, 0, 1), s["s"]))
	sweep(k, m, Transform3D.IDENTITY, fixed, true, col)

## A round pommel (a wheel or a ball) at y.
static func pommel(k: MeshKit, m: String, y: float, r: float, col := Color.WHITE, wheel := true) -> void:
	if wheel:
		lathe(k, m, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, y, 0)), [Vector2(0, -r * 0.45), Vector2(r * 0.75, -r * 0.45), Vector2(r, -r * 0.2), Vector2(r, r * 0.2), Vector2(r * 0.75, r * 0.45), Vector2(0, r * 0.45)], 14, col)
	else:
		var prof := []
		for i in 9:
			var a := -PI * 0.5 + PI * i / 8.0
			prof.append(Vector2(cos(a) * r, y + sin(a) * r))
		lathe(k, m, Transform3D.IDENTITY, prof, 12, col)

## A sword, dagger or knife: blade, guard, wrapped grip and pommel. Grip from y=0.
static func sword(k: MeshKit, o: Dictionary) -> void:
	var grip: float = o.get("grip", 0.11)
	var metal: String = o.get("metal", "it_steel")
	var gc: Color = o.get("guard_col", Color.WHITE)
	var gm: String = o.get("guard", metal)
	var r: float = o.get("grip_r", 0.014)
	# The tang's grip: wood under a leather or cord wrap.
	haft(k, -0.005, grip, r, r * 0.92, o.get("wood", Color(0.35, 0.22, 0.13)), false)
	if o.get("wrap", true):
		wrap_grip(k, 0.004, grip - 0.006, r, o.get("wrap_col", Color(0.32, 0.2, 0.12)), o.get("wrap_m", "it_leather"), 0.012)
	pommel(k, gm, -0.012, o.get("pommel", r * 1.6), gc, o.get("wheel", true))
	if o.get("cross", 0.0) > 0.0:
		guard(k, gm, grip + 0.008, o["cross"], 0.016, 0.022, gc, o.get("droop", 0.0))
	blade(k, metal, grip + 0.014, o["len"], o["w"], o.get("t", 0.006), o.get("tip", 0.16), o.get("curve", 0.0), o.get("single", false), o.get("belly", 0.0), o.get("col", Color.WHITE))

## An axe head on a haft at y, its edge toward -Z: the eye round the haft, the cheeks
## thinning to a ground edge that flares up and (with a beard) down.
static func axe_head(k: MeshKit, m: String, y: float, len: float, h: float, beard: float, t: float, col := Color.WHITE, hr := 0.018) -> void:
	var st := []
	var n := 12
	for i in n + 1:
		var f := float(i) / n
		# From the poll behind the haft (z = +hr*1.6) to the edge.
		var z := lerpf(hr * 1.6, -len, f)
		var top := lerpf(h * 0.32, h * 0.55, f * f)
		var bot := -lerpf(h * 0.32, h * 0.45 + beard, pow(f, 1.6))
		var th := lerpf(t, 0.0012, pow(f, 0.7)) if f > 0.25 else t
		if f > 0.92:
			th = 0.0008
		var c := (top + bot) * 0.5
		var hh := (top - bot) * 0.5
		var s := PackedVector2Array([Vector2(0, hh), Vector2(th * 0.5, hh * 0.85), Vector2(th * 0.5, -hh * 0.85), Vector2(0, -hh), Vector2(-th * 0.5, -hh * 0.85), Vector2(-th * 0.5, hh * 0.85)])
		st.append(_at(Vector3(0, y + c, z), Vector3(1, 0, 0), Vector3(0, 1, 0), s))
	sweep(k, m, Transform3D.IDENTITY, st, true, col)
	# A brighter strip where the edge was ground and kept sharp.
	if m != "it_flint" and m != "it_stone":
		var e := []
		for i in 7:
			var f := float(i) / 6.0
			var top := h * 0.55
			var bot := -(h * 0.45 + beard)
			var yy := lerpf(bot, top, f)
			e.append(_at(Vector3(0, y + yy, -len + 0.004), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_rect(0.0016, 0.006, 0.4)))
		sweep(k, "it_steel", Transform3D.IDENTITY, e, true, Color.WHITE)

## A pick's head at y: a long point toward +X curving down, a shorter one (or an adze
## blade) toward -X, a socket round the haft.
static func pick_head(k: MeshKit, m: String, y: float, len_a: float, len_b: float, r: float, col := Color.WHITE, adze := false) -> void:
	for side in [1.0, -1.0]:
		var L: float = len_a if side > 0 else len_b
		if L <= 0.0:
			continue
		var st := []
		for i in 9:
			var f := float(i) / 8.0
			var x: float = side * f * L
			var dy := -0.35 * L * f * f
			var rr := r * (1.0 - f * 0.92)
			var s := sec_rect(rr, rr * 0.8, 0.3)
			if adze and side < 0:
				s = sec_rect(rr * 0.35, r * (0.8 + f * 0.6), 0.2)
			st.append(_at(Vector3(x, y + dy, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), s))
		var fixed := []
		for s in st:
			fixed.append(_at(s["p"], Vector3(0, 1, 0), Vector3(0, 0, 1), s["s"]))
		sweep(k, m, Transform3D.IDENTITY, fixed, true, col)
	lathe(k, m, Transform3D.IDENTITY, [Vector2(0, y - r * 1.5), Vector2(r * 1.15, y - r * 1.5), Vector2(r * 1.25, y), Vector2(r * 1.15, y + r * 1.5), Vector2(0, y + r * 1.5)], 8, col)

## A hammer head at y, faces toward ±X: an octagonal block, its striking faces chamfered.
static func hammer_head(k: MeshKit, m: String, y: float, half: float, r: float, col := Color.WHITE, peen := 0.0) -> void:
	var st := []
	var xs := [-half, -half + r * 0.2, half - r * 0.2, half]
	var rs := [r * 0.8, r, r, r * 0.8]
	if peen > 0.0:
		xs = [-half - peen, -half, -half + r * 0.2, half - r * 0.2, half]
		rs = [r * 0.15, r * 0.7, r, r, r * 0.85]
	for i in xs.size():
		st.append(_at(Vector3(xs[i], y, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), sec_round(rs[i], rs[i], 8)))
	sweep(k, m, Transform3D.IDENTITY, st, true, col)

## A leaf-shaped spear point on a socket, from y.
static func spear_head(k: MeshKit, m: String, y: float, len: float, w: float, col := Color.WHITE, r := 0.016) -> void:
	lathe(k, m, Transform3D.IDENTITY, [Vector2(r * 1.15, y), Vector2(r * 1.2, y + 0.008), Vector2(r * 0.95, y + 0.06), Vector2(r * 0.6, y + 0.08)], 10, col)
	blade(k, m, y + 0.07, len, w, 0.008, 0.45, 0.0, false, 0.35, col)

## A thin plate shaped by `f(u, v) -> Vector3` (u, v in 0..1), `t` thick, with its edges
## closed: shovel blades, saws, sickles.
static func plate(k: MeshKit, m: String, nu: int, nv: int, f: Callable, t: float, col := Color.WHITE) -> void:
	var grid := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			row.append(f.call(float(i) / nu, float(j) / nv))
		grid.append(row)
	var norm := func(i: int, j: int) -> Vector3:
		var a: Vector3 = grid[j][mini(i + 1, nu)] - grid[j][maxi(i - 1, 0)]
		var b: Vector3 = grid[mini(j + 1, nv)][i] - grid[maxi(j - 1, 0)][i]
		return a.cross(b).normalized()
	var I := Transform3D.IDENTITY
	for j in nv:
		for i in nu:
			var p := [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
			var n := [norm.call(i, j), norm.call(i + 1, j), norm.call(i + 1, j + 1), norm.call(i, j + 1)]
			for side in [1.0, -1.0]:
				var q := []
				for c in 4:
					q.append(p[c] + n[c] * t * 0.5 * side)
				var nn := []
				for c in 4:
					nn.append(n[c] * side)
				if side > 0:
					k.tri(m, I, q[0], q[2], q[1], nn[0], nn[2], nn[1], col)
					k.tri(m, I, q[0], q[3], q[2], nn[0], nn[3], nn[2], col)
				else:
					k.tri(m, I, q[0], q[1], q[2], nn[0], nn[1], nn[2], col)
					k.tri(m, I, q[0], q[2], q[3], nn[0], nn[2], nn[3], col)
	# The rim.
	var edge := []
	for i in nu:
		edge.append([Vector2i(i, 0), Vector2i(i + 1, 0)])
		edge.append([Vector2i(i + 1, nv), Vector2i(i, nv)])
	for j in nv:
		edge.append([Vector2i(nu, j), Vector2i(nu, j + 1)])
		edge.append([Vector2i(0, j + 1), Vector2i(0, j)])
	for e in edge:
		var a: Vector2i = e[0]
		var b: Vector2i = e[1]
		var pa: Vector3 = grid[a.y][a.x]
		var pb: Vector3 = grid[b.y][b.x]
		var na: Vector3 = norm.call(a.x, a.y)
		var nb: Vector3 = norm.call(b.x, b.y)
		var out := (pb - pa).cross(na).normalized()
		k.quad(m, I, pa - na * t * 0.5, pb - nb * t * 0.5, pb + nb * t * 0.5, pa + na * t * 0.5, col)

## Iron studs or rivets at points.
static func studs(k: MeshKit, m: String, pts: Array, r: float, col := Color.WHITE) -> void:
	for p in pts:
		k.sphere(m, Transform3D(Basis(), p), r, 3, 6, 0.0, 0.7, col, true)

## A ring of chain links from a to b.
static func chain(k: MeshKit, a: Vector3, b: Vector3, links: int, r: float) -> void:
	for i in links:
		var f := (i + 0.5) / links
		var c := a.lerp(b, f)
		var d := (b - a).normalized()
		var side := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
		if i % 2 == 1:
			side = d.cross(side).normalized()
		var L := (b - a).length() / links * 0.62
		var ring := []
		for s in 13:
			var t := TAU * s / 12.0
			var p := c + d * cos(t) * L + side * sin(t) * L * 0.55
			var tan := (-d * sin(t) * L + side * cos(t) * L * 0.55).normalized()
			var nrm := d.cross(side).normalized()
			ring.append(_at(p, nrm, tan.cross(nrm).normalized(), sec_round(r, r, 5)))
		sweep(k, "it_iron", Transform3D.IDENTITY, ring, false, Color.WHITE, false)

# --- The catalogue ---------------------------------------------------------------------

## Colours of the woods and finishes the catalogue uses.
const ASH := Color(0.58, 0.42, 0.27)
const OAK := Color(0.45, 0.31, 0.19)
const WALNUT := Color(0.3, 0.2, 0.13)
const HICKORY := Color(0.66, 0.5, 0.33)
const BIRCH := Color(0.74, 0.62, 0.45)
const LEATHER := Color(0.36, 0.22, 0.12)
const LEATHER_DARK := Color(0.18, 0.12, 0.08)
const CORD := Color(0.72, 0.64, 0.48)
const FLINT := Color(0.32, 0.29, 0.27)

static func has(t: String) -> bool:
	return BUILD.has(t)

static func build(t: String) -> ArrayMesh:
	if not BUILD.has(t):
		return null
	var k := MeshKit.new(t.hash() & 0xFF)
	var grip = (Callable(ToolModels, BUILD[t])).call(k)
	var out := k.commit(mat)
	if grip is Vector3:
		out.set_meta("grip", grip)
	return out

## A burning torch: a rough branch with a leather-bound grip, its head rag soaked in
## pitch, wound round and round in lumpy turns, charred black on top where it burns. The
## flame (HandLight.TORCH_FLAME) stands at y 0.4.
static func torch(k: MeshKit) -> void:
	# A split branch, not turned: it wanders a little and thickens toward the head.
	var prof := [Vector2(0, 0.0), Vector2(0.017, 0.002), Vector2(0.019, 0.01)]
	for i in 9:
		var y := 0.03 + i * 0.03
		prof.append(Vector2(0.019 + 0.0035 * float(i) / 8.0 + 0.0012 * sin(i * 2.7), y))
	prof.append(Vector2(0.0, 0.29))
	lathe(k, "it_wood", Transform3D.IDENTITY, prof, 9, Color(0.36, 0.26, 0.17), 0.86)
	wrap_grip(k, 0.03, 0.15, 0.0205, Color(0.3, 0.19, 0.11), "it_leather", 0.016, 0.0025)
	# The wad of rag under the windings: fat in the middle, tucked in at the bottom.
	lathe(k, "it_pitch", Transform3D.IDENTITY, [Vector2(0.0, 0.255), Vector2(0.024, 0.258), Vector2(0.033, 0.285),
		Vector2(0.037, 0.33), Vector2(0.034, 0.37), Vector2(0.028, 0.392), Vector2(0.0, 0.4)], 12)
	# Strips of rag wound over it, each turn at its own slope and a little loose.
	for s in 3:
		var turns := 2.2 + s * 0.4
		var steps := int(turns * 16.0)
		var y0 := 0.262 + s * 0.035
		var y1 := y0 + 0.07 + s * 0.012
		var st := []
		for i in steps + 1:
			var f := float(i) / steps
			var a := f * turns * TAU + s * 2.1
			var y := lerpf(y0, y1, f) + 0.004 * sin(a * 3.0 + s)
			var bulge := 0.034 + 0.005 * sin(PI * clampf((y - 0.255) / 0.15, 0.0, 1.0)) + 0.0025 * sin(a * 2.0 + s * 1.7)
			var out := Vector3(cos(a), 0, sin(a))
			var tang := Vector3(-sin(a), 0, cos(a))
			var across := (Vector3.UP - tang * Vector3.UP.dot(tang)).normalized()
			st.append(_at(out * bulge + Vector3(0, y, 0), across, out, sec_rect(0.012 - 0.003 * f, 0.0035, 0.5)))
		sweep(k, "it_pitch", Transform3D.IDENTITY, st, false, Color(1, 1, 1).darkened(0.12 * s), true)
	# A ragged end hanging loose from the last turn.
	plate(k, "it_pitch", 3, 4, func(u, v):
		return Vector3(0.034 - 0.008 * v, 0.266 - v * 0.026, (u - 0.5) * 0.02 + 0.003 * sin(v * 5.0)), 0.0025)
	# Burnt crown: charred rag split open on top.
	lathe(k, "it_char", Transform3D.IDENTITY, [Vector2(0.03, 0.375), Vector2(0.032, 0.388), Vector2(0.026, 0.402),
		Vector2(0.012, 0.408), Vector2(0.0, 0.405)], 12)
	for i in 6:
		var a := i * TAU / 6.0 + 0.4
		var c := Vector3(cos(a) * 0.022, 0.398, sin(a) * 0.022)
		k.sphere("it_char", Transform3D(Basis(Vector3.UP, a), c), 0.007 + 0.002 * (i % 2), 3, 5, 0.5, 0.7)
	# Coals glowing between the charred folds; the flame is FireFx (torch_fire).
	for i in 4:
		var a := i * TAU / 4.0
		k.sphere("glow_red", Transform3D.IDENTITY.translated(Vector3(cos(a) * 0.012, 0.404, sin(a) * 0.012)), 0.006, 4, 6, 0.3, 0.6)

## The rag wad burning in a wall torch's iron basket (the kit's props/Torch_Metal, whose
## flame stands at (0, 0.34, 0.27)): lumpy, tarry below, charred on top.
static func torch_wad(k: MeshKit, xf: Transform3D) -> void:
	var c := Vector3(0, 0.285, 0.275)
	k.sphere("it_pitch", xf * Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.15, 1.0)), c), 0.062, 6, 10, 0.3, 1.0)
	for i in 5:
		var a := i * TAU / 5.0 + 0.3
		k.sphere("it_pitch", xf * Transform3D(Basis(Vector3.UP, a), c + Vector3(cos(a) * 0.045, -0.02 + 0.012 * (i % 2), sin(a) * 0.045)), 0.03, 4, 6, 0.4, 0.7)
	k.sphere("it_char", xf * Transform3D(Basis.IDENTITY, c + Vector3(0, 0.045, 0)), 0.05, 4, 8, 0.45, 0.5)
	for i in 4:
		var a := i * TAU / 4.0
		k.sphere("glow_red", xf * Transform3D(Basis.IDENTITY, c + Vector3(cos(a) * 0.02, 0.066, sin(a) * 0.02)), 0.009, 4, 6, 0.3, 0.6)

## Item -> the static function that builds it (returns the grip point, or null for the
## default: a hand's width up from the bottom).
const BUILD := {
	"wooden_club": "_wooden_club", "cudgel": "_cudgel", "quarterstaff": "_quarterstaff",
	"stone_knife": "_stone_knife", "hand_axe": "_hand_axe", "axe_stone": "_axe_stone",
	"pickaxe_stone": "_pickaxe_stone", "hunting_spear": "_hunting_spear", "bronze_spear": "_bronze_spear",
	"javelin": "_javelin", "bronze_sword": "_bronze_sword", "bronze_axe": "_bronze_axe",
	"pickaxe_bronze": "_pickaxe_bronze", "pickaxe_steel": "_pickaxe_steel", "axe_steel": "_axe_steel",
	"steel_sword": "_steel_sword", "knight_sword": "_knight_sword", "falchion": "_falchion",
	"rapier": "_rapier", "zweihander": "_zweihander", "halberd": "_halberd", "glaive": "_glaive",
	"morning_star": "_morning_star", "kings_mace": "_kings_mace", "flail": "_flail",
	"warpick": "_warpick", "executioner_axe": "_executioner_axe", "dragonbone_dagger": "_dragonbone_dagger",
	"throwing_knives": "_throwing_knives", 	"shovel": "_shovel", "hoe": "_hoe", "sickle": "_sickle",
	"fishing_rod": "_fishing_rod", "saw": "_saw", "tongs": "_tongs", "bucket": "_bucket",
	"hand_lantern": "_hand_lantern", "candle": "_candle", "tinderbox": "_tinderbox",
	"quill_ink": "_quill_ink", "mortar_pestle": "_mortar_pestle", "cauldron_small": "_cauldron_small",
	"sabre": "_sabre", "machete": "_machete", "tomahawk": "_tomahawk", "bowie_knife": "_bowie_knife",
	"bayonet": "_bayonet", "sledgehammer": "_sledgehammer", "wrench": "_wrench", "crowbar": "_crowbar",
	"hand_drill": "_hand_drill", "pickaxe_miner": "_pickaxe_miner", "axe_lumber": "_axe_lumber",
	"lamp_kerosene": "_lamp_kerosene", "dynamite": "_dynamite", "frag_grenade": "_frag_grenade",
	"powder_keg": "_powder_keg", "fire_bottle": "_fire_bottle", "fire_pot": "_fire_pot", "survival_knife": "_survival_knife",
	"vibro_knife": "_vibro_knife", "combat_machete": "_combat_machete", "stun_baton": "_stun_baton",
	"mono_katana": "_mono_katana", "power_hammer": "_power_hammer", "chain_axe": "_chain_axe",
	"frag_grenade_mk2": "_frag_mk2", "emp_grenade": "_emp_grenade", "smoke_grenade": "_smoke_grenade",
	"breach_charge": "_breach_charge", "multitool": "_multitool", "laser_cutter": "_laser_cutter",
	"welder": "_welder", "mining_laser": "_mining_laser", "grapple": "_grapple", "repair_kit": "_repair_kit",
	"binoculars_digital": "_binoculars_digital", "toolbox_tech": "_toolbox_tech", "flare_chem": "_flare_chem",
	"chitin_sword": "_chitin_sword", "psi_blade": "_psi_blade", "void_lance": "_void_lance",
	"grav_hammer": "_grav_hammer", "ion_scythe": "_ion_scythe", "worldbreaker": "_worldbreaker",
	"phase_daggers": "_phase_daggers", "plasma_whip": "_plasma_whip", 	"void_grenade": "_void_grenade",
	"pickaxe_iron": "_pickaxe_iron", "pickaxe_mythril": "_pickaxe_mythril", "axe_iron": "_axe_iron",
	"axe_mythril": "_axe_mythril", "battle_axe": "_battle_axe", "hammer": "_hammer", "sword_iron": "_sword_iron",
	"sword_runic": "_sword_runic", "dagger": "_dagger", "skinning_knife": "_skinning_knife",
	"acid_pod": "_acid_pod", "star_charge": "_star_charge", "gravity_well": "_gravity_well",
	"singularity_orb": "_singularity_orb", "swarm_hive": "_swarm_hive", "shard_gauntlet": "_shard_gauntlet",
}

# Medieval: wood, stone, bronze, then iron and steel.

static func _wooden_club(k: MeshKit):
	# A length of hardwood, the bark stripped, thickening to a knotted head.
	var prof := [Vector2(0, -0.02), Vector2(0.016, -0.018), Vector2(0.018, 0.0), Vector2(0.017, 0.12), Vector2(0.022, 0.25), Vector2(0.034, 0.38), Vector2(0.042, 0.47), Vector2(0.04, 0.52), Vector2(0.028, 0.545), Vector2(0, 0.55)]
	lathe(k, "it_wood", Transform3D.IDENTITY, prof, 12, OAK)
	for p in [Vector3(0.036, 0.42, 0.012), Vector3(-0.03, 0.36, -0.02), Vector3(0.01, 0.47, 0.038)]:
		k.sphere("it_wood", Transform3D(Basis(), p), 0.012, 4, 6, 0.3, 0.6, OAK.darkened(0.25))

static func _cudgel(k: MeshKit):
	_wooden_club(k)
	for y in [0.33, 0.45]:
		lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.036 + (y - 0.33) * 0.07, y - 0.012), Vector2(0.041 + (y - 0.33) * 0.07, y - 0.008), Vector2(0.041 + (y - 0.33) * 0.07, y + 0.008), Vector2(0.036 + (y - 0.33) * 0.07, y + 0.012)], 12)
	var pts := []
	for i in 8:
		var a := TAU * i / 8.0
		pts.append(Vector3(cos(a) * 0.043, 0.39 + 0.04 * (i % 2), sin(a) * 0.043))
	studs(k, "it_iron", pts, 0.008)

static func _quarterstaff(k: MeshKit):
	pole(k, -0.9, 0.9, 0.017, 0.017, ASH)
	for y in [-0.9, 0.86]:
		lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, y), Vector2(0.018, y), Vector2(0.019, y + 0.04), Vector2(0.0175, y + 0.042)], 10)
	wrap_grip(k, -0.12, 0.12, 0.017, LEATHER)
	return Vector3(0, 0.0, 0)

static func _stone_knife(k: MeshKit):
	haft(k, -0.01, 0.09, 0.013, 0.012, BIRCH, false)
	lash(k, Vector3(0, 0.085, 0), 0.0145, 5, 0.02, CORD)
	blade(k, "it_flint", 0.09, 0.11, 0.017, 0.008, 0.4, 0.0, false, 0.2, FLINT)

static func _hand_axe(k: MeshKit):
	haft(k, -0.02, 0.36, 0.015, 0.013, HICKORY)
	axe_head(k, "it_iron", 0.31, 0.085, 0.06, 0.012, 0.022)

static func _axe_stone(k: MeshKit):
	haft(k, -0.02, 0.5, 0.017, 0.016, OAK)
	# A ground stone head set through a split haft and bound.
	axe_head(k, "it_stone", 0.42, 0.1, 0.07, 0.0, 0.03, Color(0.42, 0.42, 0.4))
	lash(k, Vector3(0, 0.42, 0.0), 0.022, 6, 0.07, CORD)

static func _pickaxe_stone(k: MeshKit):
	haft(k, -0.02, 0.6, 0.017, 0.016, OAK)
	pick_head(k, "it_flint", 0.55, 0.15, 0.08, 0.018, FLINT)
	lash(k, Vector3(0, 0.55, 0), 0.024, 6, 0.06, CORD)

static func _hunting_spear(k: MeshKit):
	pole(k, -0.6, 1.0, 0.015, 0.014, ASH)
	spear_head(k, "it_iron", 0.98, 0.17, 0.024, Color.WHITE, 0.015)
	lash(k, Vector3(0, 1.0, 0), 0.016, 4, 0.02, LEATHER)
	return Vector3(0, 0.1, 0)

static func _bronze_spear(k: MeshKit):
	pole(k, -0.65, 1.05, 0.016, 0.015, ASH)
	spear_head(k, "it_bronze", 1.03, 0.22, 0.028, Color.WHITE, 0.016)
	lathe(k, "it_bronze", Transform3D.IDENTITY, [Vector2(0, -0.69), Vector2(0.012, -0.69), Vector2(0.017, -0.65), Vector2(0.017, -0.62)], 10)
	return Vector3(0, 0.1, 0)

static func _javelin(k: MeshKit):
	pole(k, -0.45, 0.75, 0.011, 0.01, BIRCH)
	spear_head(k, "it_iron", 0.74, 0.1, 0.012, Color.WHITE, 0.011)
	wrap_grip(k, -0.03, 0.06, 0.011, CORD, "it_cord", 0.008, 0.0016)
	return Vector3(0, 0.0, 0)

static func _bronze_sword(k: MeshKit):
	# A cast leaf-bladed sword with a hilt cast in one piece.
	sword(k, {"metal": "it_bronze", "guard": "it_bronze", "len": 0.5, "w": 0.02, "t": 0.007, "tip": 0.22, "belly": 0.28, "cross": 0.038, "wrap": false, "wood": WALNUT, "grip": 0.095, "pommel": 0.02, "wheel": false})

static func _bronze_axe(k: MeshKit):
	haft(k, -0.02, 0.48, 0.016, 0.015, ASH)
	axe_head(k, "it_bronze", 0.42, 0.1, 0.06, 0.0, 0.026)

static func _pickaxe_bronze(k: MeshKit):
	haft(k, -0.02, 0.65, 0.017, 0.016, ASH)
	pick_head(k, "it_bronze", 0.6, 0.2, 0.12, 0.016, Color.WHITE, true)

## Mythril reads as a pale, faintly blue steel: polished, never glowing.
const MYTHRIL := Color(0.8, 0.88, 1.0)

static func _pickaxe_iron(k: MeshKit):
	haft(k, -0.02, 0.66, 0.017, 0.016, HICKORY)
	pick_head(k, "it_iron", 0.61, 0.23, 0.21, 0.017)
	_wedge(k, 0.61, 0.017)

static func _pickaxe_mythril(k: MeshKit):
	haft(k, -0.02, 0.68, 0.017, 0.016, WALNUT)
	wrap_grip(k, 0.02, 0.2, 0.017, Color(0.22, 0.16, 0.12))
	pick_head(k, "it_steel", 0.63, 0.25, 0.22, 0.017, MYTHRIL)
	_wedge(k, 0.63, 0.017)

static func _axe_iron(k: MeshKit):
	haft(k, -0.02, 0.6, 0.017, 0.015, HICKORY)
	axe_head(k, "it_iron", 0.54, 0.12, 0.085, 0.02, 0.026)
	_wedge(k, 0.54, 0.015)

static func _axe_mythril(k: MeshKit):
	haft(k, -0.02, 0.62, 0.017, 0.015, WALNUT)
	wrap_grip(k, 0.02, 0.18, 0.017, Color(0.22, 0.16, 0.12))
	axe_head(k, "it_steel", 0.56, 0.13, 0.09, 0.03, 0.024, MYTHRIL)
	_wedge(k, 0.56, 0.015)

static func _battle_axe(k: MeshKit):
	# A long bearded war axe: an ash haft with a leather grip, a spike behind the head and
	# iron straps (langets) running down the haft from it.
	haft(k, -0.02, 0.86, 0.019, 0.017, ASH)
	wrap_grip(k, 0.02, 0.26, 0.019, Color(0.3, 0.19, 0.11))
	axe_head(k, "it_steel", 0.78, 0.17, 0.11, 0.07, 0.024, Color.WHITE, 0.019)
	k.cylinder("it_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.79, 0.055)), 0.011, 0.001, 0.07, 6)
	for x in [-1.0, 1.0]:
		k.box("it_iron", Transform3D.IDENTITY.translated(Vector3(x * 0.018, 0.69, 0)), Vector3(0.003, 0.12, 0.012))
		for y in [0.65, 0.72]:
			k.cylinder("it_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x * 0.02, y, 0)), 0.003, 0.003, 0.003, 6)
	return Vector3(0, 0.12, 0)

static func _hammer(k: MeshKit):
	# A claw hammer: a hickory handle with a swelling at the butt, a round steel face to +X
	# and a split claw curving down to -X.
	haft(k, -0.02, 0.33, 0.016, 0.013, HICKORY)
	hammer_head(k, "it_iron", 0.315, 0.035, 0.015)
	lathe(k, "it_steel", Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(0.035, 0.315, 0)), [Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.015, 0.012), Vector2(0.0, 0.013)], 12)
	for z in [-1.0, 1.0]:
		var st := []
		for i in 7:
			var f := float(i) / 6.0
			var a := f * 0.9
			var w := lerpf(0.011, 0.004, f)
			st.append(_at(Vector3(-0.035 - sin(a) * 0.07, 0.315 - (1.0 - cos(a)) * 0.07, z * 0.0055), Vector3(0, 0, 1), Vector3(-cos(a), sin(a), 0), sec_rect(0.0045, w, 0.3)))
		sweep(k, "it_iron", Transform3D.IDENTITY, st, true)
	_wedge(k, 0.315, 0.013)
	return Vector3(0, 0.07, 0)

static func _sword_iron(k: MeshKit):
	sword(k, {"len": 0.72, "w": 0.024, "t": 0.006, "cross": 0.1, "grip": 0.12, "guard": "it_iron", "pommel": 0.024})

static func _sword_runic(k: MeshKit):
	sword(k, {"len": 0.78, "w": 0.024, "t": 0.006, "cross": 0.11, "droop": 0.01, "grip": 0.13, "col": MYTHRIL, "guard": "it_brass", "pommel": 0.025, "wrap_col": Color(0.12, 0.14, 0.24), "wrap_m": "it_cloth"})

static func _dagger(k: MeshKit):
	sword(k, {"len": 0.24, "w": 0.018, "t": 0.005, "tip": 0.35, "cross": 0.05, "grip": 0.095, "pommel": 0.017})

static func _skinning_knife(k: MeshKit):
	sword(k, {"len": 0.13, "w": 0.018, "t": 0.004, "single": true, "belly": 0.45, "tip": 0.3, "grip": 0.1, "wrap": false, "wood": Color(0.42, 0.3, 0.2), "pommel": 0.013, "wheel": false})

## A steel wedge driven into the top of a haft through the head's eye.
static func _wedge(k: MeshKit, y: float, r: float) -> void:
	k.box("it_steel", Transform3D.IDENTITY.translated(Vector3(0, y + r * 1.5 + 0.004, 0)), Vector3(0.003, 0.008, r * 1.9))

static func _pickaxe_steel(k: MeshKit):
	haft(k, -0.02, 0.68, 0.017, 0.016, HICKORY)
	pick_head(k, "it_iron", 0.63, 0.24, 0.2, 0.017)

static func _axe_steel(k: MeshKit):
	haft(k, -0.02, 0.62, 0.017, 0.015, HICKORY)
	axe_head(k, "it_iron", 0.56, 0.12, 0.08, 0.02, 0.026)

static func _steel_sword(k: MeshKit):
	sword(k, {"len": 0.78, "w": 0.022, "t": 0.006, "cross": 0.1, "grip": 0.2, "pommel": 0.022})

static func _knight_sword(k: MeshKit):
	sword(k, {"len": 0.8, "w": 0.025, "t": 0.006, "cross": 0.11, "droop": 0.015, "grip": 0.13, "guard": "it_brass", "pommel": 0.026, "wrap_col": Color(0.42, 0.08, 0.06), "wrap_m": "it_cloth"})

static func _falchion(k: MeshKit):
	sword(k, {"len": 0.6, "w": 0.026, "t": 0.006, "single": true, "belly": 0.25, "tip": 0.3, "cross": 0.07, "grip": 0.11})

static func _rapier(k: MeshKit):
	sword(k, {"len": 0.95, "w": 0.0085, "t": 0.006, "tip": 0.08, "cross": 0.09, "grip": 0.1, "guard": "it_brass", "pommel": 0.022, "wheel": false, "wrap_m": "it_cord", "wrap_col": Color(0.7, 0.6, 0.4)})
	# A swept hilt: a knuckle bow from the guard to the pommel and a cup over the hand.
	var pts := []
	for i in 13:
		var f := float(i) / 12.0
		pts.append(_at(Vector3(sin(f * PI) * 0.055, lerpf(0.116, -0.012, f), 0), Vector3(0, 0, 1), Vector3(1, 0, 0), sec_round(0.003, 0.003, 6)))
	sweep(k, "it_brass", Transform3D.IDENTITY, pts, false)
	lathe(k, "it_brass", Transform3D.IDENTITY, [Vector2(0.008, 0.118), Vector2(0.03, 0.124), Vector2(0.034, 0.13), Vector2(0.008, 0.132)], 14)

static func _zweihander(k: MeshKit):
	sword(k, {"len": 1.15, "w": 0.026, "t": 0.007, "cross": 0.16, "grip": 0.3, "pommel": 0.03})
	# The ricasso's parrying lugs.
	guard(k, "it_iron", 0.3 + 0.14, 0.04, 0.01, 0.012)
	return Vector3(0, 0.08, 0)

static func _halberd(k: MeshKit):
	pole(k, -0.9, 1.0, 0.018, 0.017, ASH)
	# Iron langets riveted down the shaft below the head.
	for s in [-1.0, 1.0]:
		k.box("it_iron", Transform3D(Basis(), Vector3(s * 0.019, 0.8, 0)), Vector3(0.004, 0.2, 0.012))
	spear_head(k, "it_steel", 1.0, 0.26, 0.018, Color.WHITE, 0.018)
	# A broad, slightly hooked axe blade on one side...
	axe_head(k, "it_steel", 0.9, 0.25, 0.3, 0.06, 0.014, Color.WHITE, 0.018)
	# ...and a long back fluke curving down on the other.
	var st := []
	for i in 9:
		var f := float(i) / 8.0
		st.append(_at(Vector3(0, 0.93 - f * f * 0.07, 0.025 + f * 0.15), Vector3(1, 0, 0), Vector3(0, 1, 0),
			sec_rect(0.005 * (1.0 - f * 0.7), 0.016 * (1.0 - f * 0.92))))
	sweep(k, "it_steel", Transform3D.IDENTITY, st)
	return Vector3(0, 0.1, 0)

static func _glaive(k: MeshKit):
	pole(k, -0.9, 0.95, 0.017, 0.016, ASH)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.018, 0.9), Vector2(0.02, 0.92), Vector2(0.018, 0.99), Vector2(0.012, 1.0)], 10)
	blade(k, "it_steel", 0.98, 0.42, 0.032, 0.007, 0.35, 0.18, true)
	return Vector3(0, 0.1, 0)

static func _mace_handle(k: MeshKit, y1: float):
	haft(k, -0.01, y1, 0.015, 0.016, WALNUT, false)
	wrap_grip(k, 0.0, 0.13, 0.015, LEATHER)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, -0.025), Vector2(0.02, -0.02), Vector2(0.021, -0.008), Vector2(0.016, 0.0)], 10)

static func _morning_star(k: MeshKit):
	_mace_handle(k, 0.5)
	k.sphere("it_iron", Transform3D(Basis(), Vector3(0, 0.55, 0)), 0.06, 8, 12)
	var dirs := [Vector3.UP, Vector3(1, 0.3, 0), Vector3(-1, 0.3, 0), Vector3(0, 0.3, 1), Vector3(0, 0.3, -1), Vector3(0.7, -0.4, 0.7), Vector3(-0.7, -0.4, 0.7), Vector3(0.7, -0.4, -0.7), Vector3(-0.7, -0.4, -0.7), Vector3(0.7, 0.7, 0.7), Vector3(-0.7, 0.7, -0.7), Vector3(0.7, 0.7, -0.7), Vector3(-0.7, 0.7, 0.7)]
	for d in dirs:
		var n: Vector3 = d.normalized()
		var b := Basis(Vector3.UP.cross(n).normalized(), Vector3.UP.angle_to(n)) if absf(n.y) < 0.999 else Basis.IDENTITY
		k.cylinder("it_iron", Transform3D(b, Vector3(0, 0.55, 0) + n * 0.052), 0.012, 0.0, 0.05, 6)

static func _kings_mace(k: MeshKit):
	_mace_handle(k, 0.48)
	# A flanged head: seven blades round a gilded core.
	lathe(k, "it_gold", Transform3D.IDENTITY, [Vector2(0.018, 0.46), Vector2(0.026, 0.48), Vector2(0.024, 0.6), Vector2(0.012, 0.63), Vector2(0, 0.64)], 12)
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(cos(a), 0, sin(a))
		plate(k, "it_steel", 4, 6, func(u, v):
			var y := lerpf(0.48, 0.62, v)
			var reach: float = 0.022 + 0.035 * sin(v * PI) * (0.6 + 0.4 * v) * u
			return d * (0.018 + reach * u) + Vector3(0, y, 0), 0.005)
	k.sphere("it_gold", Transform3D(Basis(), Vector3(0, 0.655, 0)), 0.016, 5, 8)

static func _flail(k: MeshKit):
	_mace_handle(k, 0.36)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.016, 0.35), Vector2(0.018, 0.36), Vector2(0.01, 0.385), Vector2(0, 0.39)], 10)
	var top := Vector3(0, 0.39, 0)
	var ball := Vector3(0.07, 0.28, -0.02)
	chain(k, top, ball + Vector3(0, 0.05, 0), 6, 0.0025)
	k.sphere("it_iron", Transform3D(Basis(), ball), 0.045, 8, 10)
	for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var b := Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d)) if absf(d.y) < 0.999 else (Basis.IDENTITY if d.y > 0 else Basis(Vector3.RIGHT, PI))
		k.cylinder("it_iron", Transform3D(b, ball + d * 0.04), 0.01, 0.0, 0.035, 6)

static func _warpick(k: MeshKit):
	haft(k, -0.02, 0.56, 0.016, 0.015, WALNUT)
	wrap_grip(k, 0.0, 0.14, 0.016, LEATHER)
	pick_head(k, "it_iron", 0.52, 0.17, 0.05, 0.014)
	hammer_head(k, "it_iron", 0.52, 0.0, 0.0)

static func _executioner_axe(k: MeshKit):
	haft(k, -0.02, 0.95, 0.019, 0.017, WALNUT)
	axe_head(k, "it_iron", 0.82, 0.24, 0.24, 0.05, 0.03)
	return Vector3(0, 0.08, 0)

static func _dragonbone_dagger(k: MeshKit):
	lathe(k, "it_bone", Transform3D.IDENTITY, [Vector2(0, -0.02), Vector2(0.014, -0.018), Vector2(0.016, 0.0), Vector2(0.013, 0.05), Vector2(0.015, 0.1), Vector2(0.018, 0.11)], 10)
	blade(k, "it_bone", 0.11, 0.2, 0.017, 0.008, 0.3, 0.06, true, 0.1, Color(0.95, 0.92, 0.82))

static func _throwing_knives(k: MeshKit):
	# Three in a fan, as you'd hold them ready.
	for i in 3:
		var sub := MeshKit.new(i)
		blade(sub, "it_steel", 0.0, 0.14, 0.012, 0.004, 0.3)
		lathe(sub, "it_iron", Transform3D.IDENTITY, [Vector2(0, -0.08), Vector2(0.008, -0.08), Vector2(0.009, 0.0), Vector2(0, 0.0)], 6)
		wrap_grip(sub, -0.075, -0.005, 0.009, CORD, "it_cord", 0.007, 0.0014)
		var xf := Transform3D(Basis(Vector3(0, 0, 1), (i - 1) * 0.18), Vector3((i - 1) * 0.006, 0.08, (i - 1) * 0.004))
		_merge_into(k, sub, xf)

## Copies another kit's geometry into k, moved by xf.
static func _merge_into(k: MeshKit, sub: MeshKit, xf: Transform3D) -> void:
	var m := sub.commit(func(_n): return null)
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var name := m.surface_get_name(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_i := idx if not idx.is_empty() else PackedInt32Array(range(v.size()))
		for t in range(0, tri_i.size(), 3):
			var i0 := tri_i[t]
			var i1 := tri_i[t + 1]
			var i2 := tri_i[t + 2]
			# MeshKit.tri takes counter-clockwise order; committed triangles are clockwise.
			k.tri(name, xf, v[i0], v[i2], v[i1], n[i0], n[i2], n[i1], c[i0])

static func _shovel(k: MeshKit):
	pole(k, -0.15, 0.85, 0.017, 0.016, ASH)
	# A D-handle at the top, and a dished iron blade with a socket.
	var st := []
	for i in 13:
		var a := PI * i / 12.0
		st.append(_at(Vector3(cos(a) * 0.055, 0.88 + sin(a) * 0.07, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.011, 0.011, 8)))
	sweep(k, "it_wood", Transform3D.IDENTITY, st, false, ASH)
	k.cylinder("it_wood", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.06, 0.885, 0)), 0.013, 0.013, 0.12, 8, true, 0.0, 1, ASH)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.02, -0.08), Vector2(0.019, -0.15), Vector2(0.03, -0.2)], 10)
	plate(k, "it_iron", 6, 8, func(u, v):
		var x: float = (u - 0.5) * 0.22 * (1.0 - 0.25 * v * v)
		var y: float = -0.2 - v * 0.27 - 0.03 * (1.0 - pow(2.0 * u - 1.0, 2.0)) * v
		var z := 0.02 * pow(2.0 * u - 1.0, 2.0) - 0.01
		return Vector3(x, y, z), 0.003)
	# Held by the shaft a hand's width above the socket; Viewmodel holds it blade up.
	return Vector3(0, 0.12, 0)

static func _hoe(k: MeshKit):
	pole(k, -0.2, 1.05, 0.016, 0.015, ASH)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.018, 0.98), Vector2(0.02, 1.0), Vector2(0.02, 1.04), Vector2(0, 1.05)], 10)
	plate(k, "it_iron", 4, 4, func(u, v):
		return Vector3((u - 0.5) * 0.16, 1.02 - v * 0.02, -0.02 - v * 0.12 - 0.01 * v * v), 0.004)
	return Vector3(0, 0.0, 0)

static func _sickle(k: MeshKit):
	haft(k, -0.01, 0.12, 0.014, 0.013, BIRCH, false)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.014, 0.115), Vector2(0.016, 0.12), Vector2(0.016, 0.14), Vector2(0.01, 0.145)], 10)
	# A crescent: the blade sweeps out and round, thin at its inner (cutting) edge.
	plate(k, "it_steel", 18, 3, func(u, v):
		var a := lerpf(-0.3, 2.9, u)
		var r := 0.14
		var w: float = 0.022 * (1.0 - u * 0.85)
		var c := Vector3(-0.12, 0.17, 0)
		var rr: float = r - w * v
		return c + Vector3(cos(a) * rr, sin(a) * rr, 0), 0.003)

static func _fishing_rod(k: MeshKit):
	pole(k, -0.05, 1.7, 0.013, 0.004, BIRCH)
	wrap_grip(k, 0.0, 0.18, 0.013, CORD, "it_cord", 0.008, 0.0016)
	for y in [0.6, 1.0, 1.35, 1.65]:
		lathe(k, "it_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.008, y, 0)), [Vector2(0.004, -0.0015), Vector2(0.005, 0.0), Vector2(0.004, 0.0015)], 6)
	# The line hanging from the tip with a cork float.
	k.cylinder("it_cord", Transform3D(Basis(), Vector3(0, 1.4, 0)), 0.0008, 0.0008, 0.3, 4, false, 0.0, 1, Color(0.9, 0.9, 0.85))
	k.sphere("it_paint", Transform3D(Basis.from_scale(Vector3(1, 1.6, 1)), Vector3(0, 1.38, 0)), 0.012, 4, 6, 0.0, 1.0, Color(0.85, 0.2, 0.15))
	return Vector3(0, 0.06, 0)

static func _saw(k: MeshKit):
	# A wooden grip and a taper-ground blade with a row of teeth.
	var st := []
	for i in 9:
		var f := float(i) / 8.0
		st.append(_at(Vector3(0, -0.01 + f * 0.12, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_rect(0.02 - 0.004 * sin(f * PI), 0.013, 0.45)))
	sweep(k, "it_wood", Transform3D.IDENTITY, st, false, WALNUT)
	studs(k, "it_brass", [Vector3(0, 0.1, 0.014), Vector3(0, 0.07, 0.014)], 0.004)
	plate(k, "it_steel", 2, 10, func(u, v):
		var y: float = 0.1 + v * 0.42
		var w := lerpf(0.05, 0.028, v)
		return Vector3(lerpf(-0.012, w, u), y, 0), 0.0012)
	for i in 26:
		var y := 0.11 + i * 0.016
		var w := lerpf(0.05, 0.028, (y - 0.1) / 0.42)
		k.tri("it_steel", Transform3D.IDENTITY, Vector3(w, y, 0), Vector3(w, y + 0.016, 0), Vector3(w + 0.006, y + 0.004, 0), Vector3.BACK, Vector3.BACK, Vector3.BACK)
		k.tri("it_steel", Transform3D.IDENTITY, Vector3(w, y, 0), Vector3(w + 0.006, y + 0.004, 0), Vector3(w, y + 0.016, 0), Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD)

static func _tongs(k: MeshKit):
	# Two forged arms riveted where they cross: long handles below, short curved jaws above
	# that meet at their tips.
	var pivot := 0.27
	for s in [-1.0, 1.0]:
		var st := []
		for i in 17:
			var f := float(i) / 16.0
			var y := -0.02 + f * 0.36
			var x: float
			if y < pivot:
				x = s * 0.024 * (pivot - y) / (pivot + 0.02)
			else:
				var g := (y - pivot) / (0.34 - pivot)
				x = -s * 0.016 * sin(g * PI * 0.85)
			var r := 0.0055 if y < pivot - 0.02 else 0.0065
			st.append(_at(Vector3(x, y, s * 0.004), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_round(r, r * 0.8, 6)))
		sweep(k, "it_iron", Transform3D.IDENTITY, st, false)
		# The jaw's flat bit, turned in to grip.
		k.box("it_iron", Transform3D(Basis(Vector3(0, 0, 1), s * 0.3), Vector3(-s * 0.004, 0.345, s * 0.004)), Vector3(0.006, 0.022, 0.018))
	k.cylinder("it_iron", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, pivot, 0)), 0.008, 0.008, 0.02, 10)
	return Vector3(0, 0.05, 0)

static func _bucket(k: MeshKit):
	# Staves bound with two iron hoops, a rope bail to carry it by.
	var by := -0.33
	lathe(k, "it_wood", Transform3D.IDENTITY, [Vector2(0, by), Vector2(0.11, by), Vector2(0.115, by + 0.004), Vector2(0.135, by + 0.24), Vector2(0.128, by + 0.24), Vector2(0.11, by + 0.012), Vector2(0, by + 0.012)], 16, OAK)
	for y in [by + 0.04, by + 0.2]:
		var r := lerpf(0.115, 0.135, (y - by) / 0.24) + 0.002
		lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(r - 0.002, y - 0.009), Vector2(r, y - 0.008), Vector2(r, y + 0.008), Vector2(r - 0.002, y + 0.009)], 16)
	var st := []
	for i in 13:
		var a := PI * i / 12.0
		st.append(_at(Vector3(cos(a) * 0.138, by + 0.22 + sin(a) * 0.11, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.005, 0.005, 6)))
	sweep(k, "it_cord", Transform3D.IDENTITY, st, false, CORD)
	return Vector3(0, by + 0.33, 0)

static func _hand_lantern(k: MeshKit):
	# A tin lantern: base, four posts, a glass chimney with a candle in it, a vented
	# cone roof and the ring you carry it by.
	var by := -0.2
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, by), Vector2(0.055, by), Vector2(0.058, by + 0.012), Vector2(0.05, by + 0.02), Vector2(0, by + 0.02)], 12)
	lathe(k, "it_glass", Transform3D.IDENTITY, [Vector2(0.042, by + 0.02), Vector2(0.046, by + 0.06), Vector2(0.046, by + 0.12), Vector2(0.042, by + 0.15)], 14)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		k.cylinder("it_iron", Transform3D(Basis(), Vector3(cos(a) * 0.05, by + 0.02, sin(a) * 0.05)), 0.003, 0.003, 0.13, 5)
	lathe(k, "it_wax", Transform3D.IDENTITY, [Vector2(0, by + 0.02), Vector2(0.012, by + 0.02), Vector2(0.012, by + 0.08), Vector2(0.009, by + 0.083), Vector2(0, by + 0.083)], 10)
	k.cylinder("it_polymer", Transform3D(Basis(), Vector3(0, by + 0.083, 0)), 0.0012, 0.0008, 0.008, 4)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, by + 0.15), Vector2(0.056, by + 0.15), Vector2(0.03, by + 0.19), Vector2(0.012, by + 0.2), Vector2(0, by + 0.2)], 12)
	var st := []
	for i in 13:
		var a := TAU * i / 12.0
		st.append(_at(Vector3(cos(a) * 0.025, by + 0.235 + sin(a) * 0.028, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.003, 0.003, 6)))
	sweep(k, "it_iron", Transform3D.IDENTITY, st, false, Color.WHITE, false)
	return Vector3(0, by + 0.255, 0)

static func _candle(k: MeshKit):
	# A brass chamberstick: a dish with a finger ring, the candle with drips down it.
	lathe(k, "it_brass", Transform3D.IDENTITY, [Vector2(0, -0.01), Vector2(0.05, -0.01), Vector2(0.055, 0.0), Vector2(0.05, 0.004), Vector2(0.014, 0.0), Vector2(0.013, 0.025), Vector2(0.016, 0.03), Vector2(0, 0.03)], 14)
	lathe(k, "it_wax", Transform3D.IDENTITY, [Vector2(0, 0.03), Vector2(0.011, 0.03), Vector2(0.0105, 0.15), Vector2(0.008, 0.155), Vector2(0, 0.152)], 12)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		k.cylinder("it_wax", Transform3D(Basis(), Vector3(cos(a) * 0.0105, 0.12 - i * 0.02, sin(a) * 0.0105)), 0.003, 0.0018, 0.03 + i * 0.008, 5)
	k.cylinder("it_polymer", Transform3D(Basis(), Vector3(0, 0.152, 0)), 0.0012, 0.0006, 0.01, 4)
	var st := []
	for i in 13:
		var a := TAU * i / 12.0
		st.append(_at(Vector3(0.058 + cos(a) * 0.014, 0.0, sin(a) * 0.014), Vector3(0, 1, 0), Vector3(cos(a), 0, sin(a)), sec_round(0.003, 0.0022, 6)))
	sweep(k, "it_brass", Transform3D.IDENTITY, st, false, Color.WHITE, false)
	return Vector3(0.0, 0.0, 0)

static func _tinderbox(k: MeshKit):
	# A small flat wooden box with a brass-hinged lid; the C-shaped steel striker and a
	# flint lie on top.
	k.box("it_wood", Transform3D(Basis(), Vector3(0, 0.014, 0)), Vector3(0.085, 0.024, 0.055), Color(0.5, 0.34, 0.2))
	k.box("it_wood", Transform3D(Basis(), Vector3(0, 0.029, 0)), Vector3(0.088, 0.007, 0.058), Color(0.44, 0.29, 0.17))
	for x in [-0.025, 0.025]:
		k.box("it_brass", Transform3D(Basis(), Vector3(x, 0.024, 0.0295)), Vector3(0.012, 0.012, 0.002))
	var st := []
	for i in 11:
		var a := lerpf(0.5, TAU - 0.5, float(i) / 10.0)
		st.append(_at(Vector3(cos(a) * 0.022 - 0.01, 0.0355, sin(a) * 0.013), Vector3(0, 1, 0), Vector3(cos(a), 0, sin(a)), sec_rect(0.004, 0.0025)))
	sweep(k, "it_steel", Transform3D.IDENTITY, st, true)
	k.sphere("it_flint", Transform3D(Basis(), Vector3(0.026, 0.039, 0.008)), 0.01, 3, 5, 0.4, 0.7, FLINT)

static func _quill_ink(k: MeshKit):
	lathe(k, "it_glass", Transform3D.IDENTITY, [Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.032, 0.03), Vector2(0.015, 0.045), Vector2(0.012, 0.055), Vector2(0, 0.055)], 12)
	lathe(k, "it_polymer", Transform3D.IDENTITY, [Vector2(0, 0.0015), Vector2(0.029, 0.0015), Vector2(0.03, 0.022), Vector2(0, 0.022)], 12)
	# A goose feather standing in the pot.
	var xf := Transform3D(Basis(Vector3(0, 0, 1), -0.2), Vector3(0, 0.03, 0))
	k.cylinder("it_bone", xf, 0.002, 0.0012, 0.22, 5, false, 0.0, 1, Color(0.9, 0.86, 0.75))
	plate(k, "it_feather", 2, 10, func(u, v):
		var y: float = 0.07 + v * 0.15
		var w := 0.016 * sin(v * PI * 0.95) * (1.0 if u > 0.0 else 0.0)
		return xf * Vector3(lerpf(-w * 0.6, w, u), y, 0), 0.0008)

static func _mortar_pestle(k: MeshKit):
	# A stone bowl, thick-walled and hollow, and a club-ended pestle leaning in it.
	lathe(k, "it_stone", Transform3D.IDENTITY, [Vector2(0, 0.0), Vector2(0.05, 0.0), Vector2(0.066, 0.012),
		Vector2(0.074, 0.04), Vector2(0.073, 0.066), Vector2(0.067, 0.072), Vector2(0.056, 0.07),
		Vector2(0.05, 0.045), Vector2(0.032, 0.024), Vector2(0.0, 0.019)], 18, Color(0.66, 0.63, 0.58))
	lathe(k, "it_stone", Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(0.012, 0.024, 0)), [Vector2(0, 0.0),
		Vector2(0.015, 0.004), Vector2(0.018, 0.022), Vector2(0.011, 0.055), Vector2(0.009, 0.12),
		Vector2(0.012, 0.135), Vector2(0.0, 0.142)], 10, Color(0.6, 0.57, 0.53))
	return Vector3(0, 0.035, 0)

static func _cauldron_small(k: MeshKit):
	# A cast-iron pot: round belly, rolled lip, two lugs and a wire bail to carry it by.
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, -0.015), Vector2(0.05, -0.012), Vector2(0.09, 0.02),
		Vector2(0.1, 0.055), Vector2(0.09, 0.1), Vector2(0.084, 0.108), Vector2(0.09, 0.114), Vector2(0.082, 0.118),
		Vector2(0.077, 0.108), Vector2(0.085, 0.06), Vector2(0.06, 0.0), Vector2(0, -0.005)], 18, Color(0.55, 0.55, 0.56))
	for s in [-1.0, 1.0]:
		k.box("it_iron", Transform3D(Basis(), Vector3(s * 0.092, 0.1, 0)), Vector3(0.012, 0.018, 0.012), Color(0.55, 0.55, 0.56))
	var st := []
	for i in 13:
		var a := PI * i / 12.0
		st.append(_at(Vector3(cos(a) * 0.094, 0.105 + sin(a) * 0.09, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.0028, 0.0028, 6)))
	sweep(k, "it_iron", Transform3D.IDENTITY, st, false)
	return Vector3(0, 0.19, 0)

# Frontier (the old west on the way out): steel, brass, walnut.

static func _sabre(k: MeshKit):
	sword(k, {"len": 0.82, "w": 0.016, "t": 0.006, "single": true, "curve": 0.06, "tip": 0.14, "cross": 0.0, "grip": 0.12, "guard": "it_brass", "pommel": 0.016, "wheel": false, "wrap_col": LEATHER_DARK})
	var pts := []
	for i in 13:
		var f := float(i) / 12.0
		pts.append(_at(Vector3(0.014 + sin(f * PI) * 0.04, lerpf(0.13, -0.012, f), 0), Vector3(0, 0, 1), Vector3(1, 0, 0), sec_rect(0.003, 0.006)))
	sweep(k, "it_brass", Transform3D.IDENTITY, pts, true)
	lathe(k, "it_brass", Transform3D.IDENTITY, [Vector2(0.006, 0.125), Vector2(0.03, 0.13), Vector2(0.006, 0.136)], 12, Color.WHITE, 0.6)

static func _machete(k: MeshKit):
	sword(k, {"len": 0.42, "w": 0.026, "t": 0.004, "single": true, "belly": 0.2, "tip": 0.22, "cross": 0.0, "grip": 0.12, "wrap": false, "wood": WALNUT, "pommel": 0.014, "wheel": false})
	studs(k, "it_brass", [Vector3(0, 0.03, 0.015), Vector3(0, 0.08, 0.015), Vector3(0, 0.03, -0.015), Vector3(0, 0.08, -0.015)], 0.0035)

static func _tomahawk(k: MeshKit):
	haft(k, -0.02, 0.45, 0.014, 0.013, HICKORY)
	wrap_grip(k, 0.0, 0.08, 0.014, LEATHER)
	axe_head(k, "it_iron", 0.4, 0.09, 0.05, 0.0, 0.02, Color.WHITE, 0.014)
	pick_head(k, "it_iron", 0.4, 0.0, 0.05, 0.01)

static func _bowie_knife(k: MeshKit):
	sword(k, {"len": 0.22, "w": 0.02, "t": 0.006, "single": true, "tip": 0.3, "cross": 0.035, "grip": 0.11, "guard": "it_brass", "wrap": false, "wood": Color(0.3, 0.17, 0.1), "pommel": 0.016, "wheel": false})

static func _bayonet(k: MeshKit):
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.011, -0.02), Vector2(0.012, 0.06), Vector2(0.008, 0.07)], 10)
	k.cylinder("it_iron", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.024, 0.055, 0)), 0.005, 0.005, 0.016, 6)
	blade(k, "it_steel", 0.065, 0.36, 0.008, 0.008, 0.12)

static func _sledgehammer(k: MeshKit):
	haft(k, -0.02, 0.85, 0.019, 0.018, HICKORY)
	hammer_head(k, "it_iron", 0.83, 0.1, 0.042)
	return Vector3(0, 0.08, 0)

static func _wrench(k: MeshKit):
	var st := []
	for i in 9:
		var f := float(i) / 8.0
		st.append(_at(Vector3(0, -0.02 + f * 0.24, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_rect(0.012 + 0.004 * f, 0.006, 0.4)))
	sweep(k, "it_steel", Transform3D.IDENTITY, st, true, Color(0.85, 0.85, 0.85))
	k.box("it_steel", Transform3D(Basis(), Vector3(0.008, 0.235, 0)), Vector3(0.05, 0.03, 0.013))
	k.box("it_steel", Transform3D(Basis(), Vector3(0.024, 0.262, 0)), Vector3(0.016, 0.03, 0.012))
	k.box("it_steel", Transform3D(Basis(), Vector3(-0.012, 0.262, 0)), Vector3(0.014, 0.028, 0.012))
	k.cylinder("it_steel", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.018, 0.212, 0)), 0.006, 0.006, 0.036, 10)

static func _crowbar(k: MeshKit):
	var st := []
	for i in 21:
		var f := float(i) / 20.0
		var p: Vector3
		var tng: Vector3
		if f < 0.8:
			p = Vector3(0, -0.05 + f / 0.8 * 0.55, 0)
			tng = Vector3.UP
		else:
			var a := (f - 0.8) / 0.2 * PI * 0.95
			p = Vector3(-0.03 + cos(a) * 0.03, 0.5 + sin(a) * 0.03, 0)
			tng = Vector3(-sin(a), cos(a), 0)
		var x := Vector3(tng.y, -tng.x, 0)
		var r := 0.009 if f > 0.02 and f < 0.97 else 0.006
		st.append(_at(p, x, Vector3(0, 0, 1), sec_round(r, r, 6)))
	sweep(k, "it_paint", Transform3D.IDENTITY, st, false, Color(0.55, 0.1, 0.08))

static func _hand_drill(k: MeshKit):
	# A carpenter's brace: a cranked iron bow, a turning grip in the middle, a bit below.
	var st := []
	var pts := [Vector3(0, 0.0, 0), Vector3(0, 0.06, 0), Vector3(0.08, 0.09, 0), Vector3(0.08, 0.2, 0), Vector3(0, 0.23, 0), Vector3(0, 0.29, 0)]
	for i in pts.size():
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var tng := (b - a).normalized()
		st.append(_at(pts[i], Vector3(tng.y, -tng.x, 0), Vector3(0, 0, 1), sec_round(0.006, 0.006, 6)))
	sweep(k, "it_iron", Transform3D.IDENTITY, st, false)
	lathe(k, "it_wood", Transform3D(Basis(), Vector3(0.08, 0.11, 0)), [Vector2(0, 0), Vector2(0.014, 0.0), Vector2(0.017, 0.035), Vector2(0.014, 0.07), Vector2(0, 0.07)], 10, WALNUT)
	lathe(k, "it_wood", Transform3D(Basis(), Vector3(0, 0.29, 0)), [Vector2(0, 0), Vector2(0.03, 0.005), Vector2(0.032, 0.025), Vector2(0, 0.035)], 12, WALNUT)
	k.cylinder("it_steel", Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3(0, 0.0, 0)), 0.004, 0.001, 0.09, 6)
	return Vector3(0.08, 0.13, 0)

static func _pickaxe_miner(k: MeshKit):
	haft(k, -0.02, 0.72, 0.018, 0.017, HICKORY)
	pick_head(k, "it_iron", 0.67, 0.26, 0.26, 0.019, Color(0.8, 0.8, 0.8))

static func _axe_lumber(k: MeshKit):
	haft(k, -0.02, 0.78, 0.018, 0.016, HICKORY)
	axe_head(k, "it_paint", 0.72, 0.13, 0.1, 0.0, 0.03, Color(0.6, 0.12, 0.08))
	return Vector3(0, 0.06, 0)

static func _lamp_kerosene(k: MeshKit):
	# A hurricane lamp: brass fuel font, burner collar with its wick-winder, a tall bulging
	# glass chimney with the flat wick inside, a wire guard and a bail on top.
	var by := -0.22
	lathe(k, "it_brass", Transform3D.IDENTITY, [Vector2(0, by), Vector2(0.058, by), Vector2(0.066, by + 0.02),
		Vector2(0.062, by + 0.05), Vector2(0.04, by + 0.066), Vector2(0.024, by + 0.07), Vector2(0, by + 0.07)], 16)
	lathe(k, "it_brass", Transform3D.IDENTITY, [Vector2(0.024, by + 0.068), Vector2(0.03, by + 0.075), Vector2(0.03, by + 0.088), Vector2(0.026, by + 0.09)], 12)
	k.cylinder("it_brass", Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, by + 0.08, 0.034)), 0.006, 0.006, 0.01, 8)
	lathe(k, "it_glass", Transform3D.IDENTITY, [Vector2(0.026, by + 0.09), Vector2(0.044, by + 0.12), Vector2(0.046, by + 0.15),
		Vector2(0.03, by + 0.19), Vector2(0.022, by + 0.22)], 16)
	k.box("it_cloth", Transform3D(Basis(), Vector3(0, by + 0.1, 0)), Vector3(0.012, 0.012, 0.002), Color(0.2, 0.17, 0.14))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		k.cylinder("it_iron", Transform3D(Basis(), Vector3(cos(a) * 0.05, by + 0.155, sin(a) * 0.05)), 0.0022, 0.0022, 0.13, 5)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.024, by + 0.22), Vector2(0.034, by + 0.225), Vector2(0.03, by + 0.235), Vector2(0, by + 0.238)], 12)
	var st := []
	for i in 13:
		var a := PI * i / 12.0
		st.append(_at(Vector3(cos(a) * 0.045, by + 0.238 + sin(a) * 0.045, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.0028, 0.0028, 6)))
	sweep(k, "it_iron", Transform3D.IDENTITY, st, false)
	return Vector3(0, by + 0.28, 0)

static func _dynamite(k: MeshKit):
	for i in 3:
		var p: Vector3 = [Vector3(-0.015, 0, 0), Vector3(0.015, 0, 0), Vector3(0, 0, 0.026)][i]
		lathe(k, "it_paper", Transform3D(Basis(), p), [Vector2(0, 0), Vector2(0.015, 0.0), Vector2(0.015, 0.2), Vector2(0, 0.2)], 10, Color(0.72, 0.16, 0.12))
	for y in [0.04, 0.16]:
		lathe(k, "it_cloth", Transform3D(Basis(), Vector3(0, 0, 0.009)), [Vector2(0.034, y - 0.008), Vector2(0.036, y), Vector2(0.034, y + 0.008)], 12, Color(0.75, 0.72, 0.65))
	var st := []
	for i in 9:
		var f := float(i) / 8.0
		st.append(_at(Vector3(sin(f * 3.0) * 0.02, 0.2 + f * 0.08, 0.009), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_round(0.0018, 0.0018, 5)))
	sweep(k, "it_cord", Transform3D.IDENTITY, st, false, Color(0.25, 0.22, 0.18))

static func _frag_grenade(k: MeshKit):
	# The cast-iron "pineapple": a segmented body, a fuse head, the lever and ring pin.
	for row in 5:
		for col in 8:
			var a := TAU * col / 8.0
			var e := lerpf(-1.0, 1.0, row / 4.0)
			var r := 0.028 * sqrt(1.0 - e * e * 0.7)
			k.box("it_paint", Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r, 0.04 + e * 0.032, sin(a) * r)), Vector3(0.006, 0.012, 0.014), Color(0.3, 0.33, 0.22))
	k.sphere("it_paint", Transform3D(Basis.from_scale(Vector3(1, 1.25, 1)), Vector3(0, 0.04, 0)), 0.026, 8, 10, 0.0, 1.0, Color(0.27, 0.3, 0.2))
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.01, 0.07), Vector2(0.011, 0.09), Vector2(0, 0.092)], 8)
	k.box("it_iron", Transform3D(Basis(Vector3(0, 0, 1), -0.25), Vector3(0.016, 0.06, 0)), Vector3(0.006, 0.06, 0.012))
	_ring(k, Vector3(-0.016, 0.085, 0), 0.01)

static func _ring(k: MeshKit, c: Vector3, r: float) -> void:
	var st := []
	for i in 13:
		var a := TAU * i / 12.0
		st.append(_at(c + Vector3(cos(a) * r, sin(a) * r, 0), Vector3(0, 0, 1), Vector3(cos(a), sin(a), 0), sec_round(0.0015, 0.0015, 5)))
	sweep(k, "it_steel", Transform3D.IDENTITY, st, false, Color.WHITE, false)

static func _powder_keg(k: MeshKit):
	lathe(k, "it_wood", Transform3D.IDENTITY, [Vector2(0, -0.1), Vector2(0.07, -0.1), Vector2(0.085, 0.0), Vector2(0.07, 0.1), Vector2(0, 0.1)], 16, OAK)
	for y in [-0.075, 0.075]:
		lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.075 + 0.002, y - 0.008), Vector2(0.079 + 0.002, y), Vector2(0.075 + 0.002, y + 0.008)], 16)
	k.cylinder("it_cord", Transform3D(Basis(Vector3(0, 0, 1), 0.3), Vector3(0, 0.1, 0)), 0.002, 0.002, 0.07, 5, false, 0.0, 1, Color(0.25, 0.22, 0.18))
	return Vector3(0, -0.04, 0)

static func _fire_bottle(k: MeshKit):
	lathe(k, "it_glass", Transform3D.IDENTITY, [Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.032, 0.005), Vector2(0.032, 0.11), Vector2(0.015, 0.14), Vector2(0.012, 0.18), Vector2(0.013, 0.185), Vector2(0, 0.185)], 14)
	# Lamp oil inside, a rag stuffed in the neck.
	lathe(k, "it_paint", Transform3D.IDENTITY, [Vector2(0, 0.004), Vector2(0.029, 0.004), Vector2(0.029, 0.08), Vector2(0, 0.08)], 14, Color(0.55, 0.38, 0.12))
	k.sphere("it_cloth", Transform3D(Basis.from_scale(Vector3(0.8, 2.2, 0.8)), Vector3(0.004, 0.2, 0)), 0.014, 4, 6, 0.4, 1.0, Color(0.75, 0.68, 0.55))

## A round clay pot of pitch, its mouth tied over with a rag to be lit.
static func _fire_pot(k: MeshKit):
	lathe(k, "it_stone", Transform3D.IDENTITY, [Vector2(0, 0.0), Vector2(0.03, 0.0), Vector2(0.052, 0.03), Vector2(0.058, 0.065), Vector2(0.05, 0.1), Vector2(0.026, 0.122), Vector2(0.024, 0.132), Vector2(0.03, 0.138), Vector2(0, 0.138)], 16, Color(0.62, 0.38, 0.24))
	lathe(k, "it_pitch", Transform3D.IDENTITY, [Vector2(0, 0.131), Vector2(0.025, 0.131), Vector2(0, 0.136)], 12)
	k.sphere("it_cloth", Transform3D(Basis.from_scale(Vector3(1.2, 0.6, 1.2)), Vector3(0, 0.142, 0)), 0.03, 5, 8, 0.4, 1.0, Color(0.72, 0.64, 0.5))
	k.cylinder("it_cord", Transform3D(Basis(), Vector3(0, 0.124, 0)), 0.027, 0.027, 0.008, 12)

static func _survival_knife(k: MeshKit):
	sword(k, {"len": 0.17, "w": 0.016, "t": 0.006, "single": true, "tip": 0.3, "cross": 0.028, "grip": 0.11, "guard": "it_steel", "wrap_m": "it_cord", "wrap_col": Color(0.25, 0.27, 0.2), "pommel": 0.014, "wheel": false})

# Sci-fi, human: polymer, steel and paint, no glow.

static func _vibro_knife(k: MeshKit):
	sword(k, {"len": 0.2, "w": 0.016, "t": 0.005, "single": true, "tip": 0.3, "cross": 0.022, "grip": 0.11, "guard": "it_polymer", "wrap": false, "wood": Color(0.12, 0.12, 0.13), "pommel": 0.013, "wheel": false, "metal": "it_iron"})
	k.box("it_paint", Transform3D(Basis(), Vector3(0, 0.06, 0.012)), Vector3(0.01, 0.05, 0.004), Color(0.75, 0.55, 0.1))

static func _combat_machete(k: MeshKit):
	sword(k, {"len": 0.44, "w": 0.024, "t": 0.005, "single": true, "tip": 0.25, "belly": 0.15, "cross": 0.0, "grip": 0.12, "wrap": false, "wood": Color(0.15, 0.15, 0.14), "metal": "it_iron", "pommel": 0.014, "wheel": false})

static func _stun_baton(k: MeshKit):
	lathe(k, "it_rubber", Transform3D.IDENTITY, [Vector2(0, -0.01), Vector2(0.016, -0.01), Vector2(0.017, 0.14), Vector2(0.013, 0.15)], 10)
	lathe(k, "it_steel", Transform3D.IDENTITY, [Vector2(0.013, 0.15), Vector2(0.012, 0.42), Vector2(0.0, 0.43)], 10, Color(0.4, 0.4, 0.42))
	for s in [-1.0, 1.0]:
		k.cylinder("it_steel", Transform3D(Basis(), Vector3(s * 0.006, 0.425, 0)), 0.0018, 0.0018, 0.018, 5)
	k.box("it_paint", Transform3D(Basis(), Vector3(0, 0.12, 0.016)), Vector3(0.008, 0.012, 0.004), Color(0.8, 0.65, 0.1))

static func _mono_katana(k: MeshKit):
	sword(k, {"len": 0.7, "w": 0.015, "t": 0.006, "single": true, "curve": 0.05, "tip": 0.08, "cross": 0.0, "grip": 0.26, "wrap_m": "it_cord", "wrap_col": Color(0.12, 0.12, 0.14), "pommel": 0.014, "wheel": false, "wood": Color(0.85, 0.82, 0.75)})
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0, 0.262), Vector2(0.036, 0.262), Vector2(0.036, 0.27), Vector2(0, 0.27)], 16, Color.WHITE, 0.75)
	return Vector3(0, 0.07, 0)

static func _power_hammer(k: MeshKit):
	haft(k, -0.02, 0.6, 0.018, 0.017, Color.WHITE, false, "it_polymer")
	hammer_head(k, "it_paint", 0.6, 0.09, 0.045, Color(0.75, 0.55, 0.12))
	for s in [-1.0, 1.0]:
		k.cylinder("it_steel", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(s * 0.02, 0.6, 0.05)), 0.008, 0.008, 0.06, 8)
	k.box("it_iron", Transform3D(Basis(), Vector3(0, 0.6, 0.05)), Vector3(0.05, 0.03, 0.02))

static func _chain_axe(k: MeshKit):
	haft(k, -0.02, 0.6, 0.018, 0.017, Color.WHITE, false, "it_polymer")
	axe_head(k, "it_paint", 0.54, 0.14, 0.1, 0.02, 0.03, Color(0.35, 0.38, 0.4))
	# The chain of teeth round the edge.
	for i in 14:
		var f := float(i) / 13.0
		var y := lerpf(0.54 - 0.07, 0.54 + 0.055, f)
		k.box("it_steel", Transform3D(Basis(Vector3(1, 0, 0), 0.3), Vector3(0, y, -0.142)), Vector3(0.004, 0.006, 0.012))

static func _frag_mk2(k: MeshKit):
	k.sphere("it_paint", Transform3D(Basis.from_scale(Vector3(1, 1.2, 1)), Vector3(0, 0.035, 0)), 0.026, 10, 12, 0.0, 1.0, Color(0.22, 0.26, 0.2))
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.009, 0.06), Vector2(0.01, 0.075), Vector2(0, 0.078)], 8)
	k.box("it_steel", Transform3D(Basis(Vector3(0, 0, 1), -0.15), Vector3(0.015, 0.048, 0)), Vector3(0.005, 0.05, 0.012))
	_ring(k, Vector3(-0.014, 0.07, 0), 0.009)

static func _canister(k: MeshKit, body: Color, band: Color):
	lathe(k, "it_paint", Transform3D.IDENTITY, [Vector2(0, 0), Vector2(0.024, 0), Vector2(0.025, 0.005), Vector2(0.025, 0.11), Vector2(0.02, 0.115), Vector2(0, 0.115)], 14, body)
	lathe(k, "it_paint", Transform3D.IDENTITY, [Vector2(0.0255, 0.07), Vector2(0.0255, 0.085)], 14, band)
	lathe(k, "it_iron", Transform3D.IDENTITY, [Vector2(0.01, 0.115), Vector2(0.011, 0.13), Vector2(0, 0.132)], 8)
	k.box("it_steel", Transform3D(Basis(), Vector3(0.022, 0.09, 0)), Vector3(0.005, 0.06, 0.012))
	_ring(k, Vector3(-0.012, 0.128, 0), 0.009)

static func _emp_grenade(k: MeshKit):
	_canister(k, Color(0.2, 0.22, 0.26), Color(0.15, 0.4, 0.75))

static func _smoke_grenade(k: MeshKit):
	_canister(k, Color(0.35, 0.37, 0.3), Color(0.85, 0.85, 0.82))

static func _breach_charge(k: MeshKit):
	k.box("it_paint", Transform3D(Basis(), Vector3(0, 0.04, 0)), Vector3(0.12, 0.08, 0.03), Color(0.3, 0.32, 0.25))
	k.box("it_polymer", Transform3D(Basis(), Vector3(0, 0.05, 0.017)), Vector3(0.04, 0.025, 0.006))
	k.box("it_paint", Transform3D(Basis(), Vector3(0, 0.05, 0.0205)), Vector3(0.03, 0.015, 0.001), Color(0.15, 0.3, 0.12))

static func _multitool(k: MeshKit):
	for s in [-1.0, 1.0]:
		k.box("it_steel", Transform3D(Basis(Vector3(0, 0, 1), s * 0.04), Vector3(s * 0.009, 0.05, 0)), Vector3(0.014, 0.11, 0.012))
	k.box("it_steel", Transform3D(Basis(), Vector3(0, 0.12, 0)), Vector3(0.012, 0.035, 0.008))
	k.box("it_steel", Transform3D(Basis(Vector3(0, 0, 1), 0.2), Vector3(0.004, 0.145, 0)), Vector3(0.004, 0.025, 0.006))

static func _tool_gun(k: MeshKit, nozzle: float, body: Color):
	# A tool you point: a polymer pistol grip, a painted body, a steel nozzle ahead.
	var st := []
	for i in 7:
		var f := float(i) / 6.0
		st.append(_at(Vector3(0, -0.02 + f * 0.11, 0.01 - f * 0.012), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_rect(0.013, 0.02, 0.5)))
	sweep(k, "it_polymer", Transform3D.IDENTITY, st, false)
	k.box("it_paint", Transform3D(Basis(), Vector3(0, 0.11, -0.04)), Vector3(0.04, 0.05, 0.16), body)
	k.cylinder("it_steel", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(0, 0.11, -0.12)), 0.012, 0.007, nozzle, 10)

static func _laser_cutter(k: MeshKit):
	_tool_gun(k, 0.06, Color(0.75, 0.55, 0.12))

static func _welder(k: MeshKit):
	_tool_gun(k, 0.09, Color(0.2, 0.35, 0.6))

static func _mining_laser(k: MeshKit):
	_tool_gun(k, 0.12, Color(0.65, 0.6, 0.55))
	k.box("it_iron", Transform3D(Basis(), Vector3(0, 0.145, -0.02)), Vector3(0.03, 0.02, 0.08))

static func _grapple(k: MeshKit):
	_tool_gun(k, 0.03, Color(0.3, 0.32, 0.35))
	for i in 3:
		var a := TAU * i / 3.0
		k.cylinder("it_steel", Transform3D(Basis(Vector3(cos(a), sin(a), 0).cross(Vector3.FORWARD).normalized(), 2.4), Vector3(0, 0.11, -0.16)), 0.003, 0.002, 0.035, 5)

static func _repair_kit(k: MeshKit):
	k.box("it_paint", Transform3D(Basis(), Vector3(0, -0.07, 0)), Vector3(0.2, 0.12, 0.06), Color(0.75, 0.55, 0.1))
	k.box("it_polymer", Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(0.08, 0.012, 0.016))
	return Vector3(0, 0.0, 0)

static func _toolbox_tech(k: MeshKit):
	k.box("it_paint", Transform3D(Basis(), Vector3(0, -0.09, 0)), Vector3(0.3, 0.14, 0.12), Color(0.55, 0.12, 0.1))
	k.box("it_iron", Transform3D(Basis(), Vector3(0, -0.015, 0)), Vector3(0.31, 0.012, 0.125))
	k.box("it_polymer", Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(0.12, 0.014, 0.018))
	return Vector3(0, 0.0, 0)

static func _binoculars_digital(k: MeshKit):
	k.box("it_polymer", Transform3D(Basis(), Vector3(-0.04, 0.0, 0.0)), Vector3(0.13, 0.05, 0.11))
	for s in [-1.0, 1.0]:
		k.cylinder("it_glass", Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(-0.04 + s * 0.033, 0.0, -0.056)), 0.018, 0.018, 0.003, 12)
	k.box("it_rubber", Transform3D(Basis(), Vector3(-0.04, 0.0, 0.06)), Vector3(0.12, 0.04, 0.012))

static func _flare_chem(k: MeshKit):
	for i in 3:
		var c: Color = [Color(0.5, 0.95, 0.4, 0.8), Color(0.95, 0.85, 0.3, 0.8), Color(0.4, 0.7, 0.95, 0.8)][i]
		lathe(k, "it_glass", Transform3D(Basis(Vector3(0, 0, 1), (i - 1) * 0.15), Vector3((i - 1) * 0.012, 0, 0)), [Vector2(0, 0), Vector2(0.006, 0.0), Vector2(0.0065, 0.14), Vector2(0, 0.145)], 8, c)
		k.cylinder("it_polymer", Transform3D(Basis(), Vector3((i - 1) * 0.012 + (i - 1) * 0.02, 0.14, 0)), 0.002, 0.002, 0.01, 5)

# Alien (endgame): shell, crystal, and the strange metal of the ruins. Only these shine.

static func _chitin_sword(k: MeshKit):
	sword(k, {"len": 0.7, "w": 0.024, "t": 0.008, "single": true, "curve": 0.03, "tip": 0.3, "belly": 0.2, "cross": 0.0, "grip": 0.13, "metal": "it_chitin", "guard": "it_chitin", "wrap": false, "wood": Color(0.28, 0.2, 0.25), "pommel": 0.02, "wheel": false, "col": Color(0.42, 0.3, 0.4)})

static func _psi_blade(k: MeshKit):
	haft(k, -0.01, 0.12, 0.014, 0.013, Color(0.3, 0.3, 0.35), false, "it_chitin")
	blade(k, "it_crystal", 0.13, 0.45, 0.012, 0.004, 0.25, 0.0, false, 0.0, Color(0.85, 0.75, 1.0, 0.7))

static func _void_lance(k: MeshKit):
	pole(k, -0.8, 1.1, 0.016, 0.014, Color(0.2, 0.18, 0.24), "it_chitin")
	blade(k, "it_crystal", 1.1, 0.35, 0.02, 0.008, 0.6, 0.0, false, 0.2, Color(0.55, 0.45, 0.95, 0.8))
	return Vector3(0, 0.1, 0)

static func _grav_hammer(k: MeshKit):
	haft(k, -0.02, 0.62, 0.018, 0.017, Color(0.25, 0.22, 0.3), false, "it_chitin")
	hammer_head(k, "alien_hull", 0.62, 0.11, 0.05)
	k.sphere("it_crystal", Transform3D(Basis(), Vector3(0, 0.62, 0.05)), 0.02, 6, 8, 0.0, 1.0, Color(0.6, 0.55, 1.0, 0.8))

static func _ion_scythe(k: MeshKit):
	pole(k, -0.5, 1.1, 0.016, 0.015, Color(0.2, 0.2, 0.25), "it_chitin")
	plate(k, "it_crystal", 16, 3, func(u, v):
		var a := lerpf(0.1, 1.5, u)
		var rr: float = 0.5 - 0.06 * v * (1.0 - u)
		return Vector3(0, 1.1 + sin(a) * 0.1 - 0.1, -cos(a) * rr + 0.05) + Vector3(0, 0, 0), 0.004, Color(0.6, 0.8, 1.0, 0.75))
	return Vector3(0, 0.1, 0)

static func _worldbreaker(k: MeshKit):
	haft(k, -0.02, 0.85, 0.02, 0.019, Color(0.22, 0.2, 0.26), false, "it_chitin")
	hammer_head(k, "alien_hull", 0.84, 0.13, 0.065, Color.WHITE, 0.05)
	for i in 6:
		var a := TAU * i / 6.0
		k.crystal("it_crystal", Transform3D(Basis(Vector3(cos(a), 0, sin(a)), 0.9), Vector3(0, 0.84, 0) + Vector3(cos(a), 0, sin(a)) * 0.04), 0.012, 0.06, 5, 0.35, Color(0.7, 0.55, 1.0, 0.8))
	return Vector3(0, 0.08, 0)

static func _phase_daggers(k: MeshKit):
	haft(k, -0.01, 0.1, 0.012, 0.011, Color(0.25, 0.25, 0.3), false, "it_chitin")
	blade(k, "it_crystal", 0.1, 0.2, 0.014, 0.005, 0.35, 0.05, true, 0.0, Color(0.5, 0.9, 0.95, 0.7))

static func _plasma_whip(k: MeshKit):
	haft(k, -0.01, 0.16, 0.014, 0.013, Color(0.25, 0.25, 0.3), false, "it_chitin")
	var st := []
	for i in 31:
		var f := float(i) / 30.0
		st.append(_at(Vector3(sin(f * 7.0) * 0.06 * f, 0.16 - f * 0.55, cos(f * 5.0) * 0.04 * f), Vector3(1, 0, 0), Vector3(0, 0, 1), sec_round(0.006 * (1.0 - f * 0.7), 0.006 * (1.0 - f * 0.7), 6)))
	sweep(k, "glow_violet", Transform3D.IDENTITY, st, false)

static func _orb(k: MeshKit, c: Color, shell: String):
	# A grown shell in segments, the light of its charge showing through the seams, a
	# capped stalk on top with the trigger ring through it.
	k.sphere(shell, Transform3D(Basis(), Vector3(0, 0.04, 0)), 0.035, 8, 12, 0.15, 1.0, Color(0.3, 0.28, 0.34))
	for i in 4:
		var a := PI * i / 4.0
		var st := []
		for j in 17:
			var b := PI * 2.0 * j / 16.0
			var p := Vector3(cos(b) * 0.0362, sin(b) * 0.0362, 0)
			st.append(_at(Basis(Vector3.UP, a) * p + Vector3(0, 0.04, 0), Basis(Vector3.UP, a) * Vector3(0, 0, 1), Basis(Vector3.UP, a) * p.normalized(), sec_round(0.0016, 0.0012, 5)))
		sweep(k, "it_crystal", Transform3D.IDENTITY, st, false, c, false)
	lathe(k, shell, Transform3D.IDENTITY, [Vector2(0.016, 0.07), Vector2(0.014, 0.08), Vector2(0.009, 0.088), Vector2(0, 0.09)], 10, Color(0.24, 0.22, 0.27))
	_ring(k, Vector3(0.014, 0.084, 0), 0.008)

static func _void_grenade(k: MeshKit):
	_orb(k, Color(0.5, 0.35, 0.9, 0.85), "it_chitin")

static func _acid_pod(k: MeshKit):
	k.sphere("it_chitin", Transform3D(Basis.from_scale(Vector3(1, 1.3, 1)), Vector3(0, 0.04, 0)), 0.032, 8, 10, 0.25, 1.0, Color(0.45, 0.55, 0.2))

static func _star_charge(k: MeshKit):
	_orb(k, Color(1.0, 0.85, 0.5, 0.85), "alien_hull")

static func _gravity_well(k: MeshKit):
	_orb(k, Color(0.4, 0.6, 1.0, 0.85), "alien_hull")
	lathe(k, "alien_hull", Transform3D(Basis(), Vector3(0, 0.04, 0)), [Vector2(0.04, -0.004), Vector2(0.05, 0.0), Vector2(0.04, 0.004)], 16)

static func _singularity_orb(k: MeshKit):
	k.sphere("it_polymer", Transform3D(Basis(), Vector3(0, 0.04, 0)), 0.03, 10, 12, 0.0, 1.0)
	for i in 3:
		lathe(k, "it_crystal", Transform3D(Basis(Vector3(1, 0, 0), i * PI / 3.0), Vector3(0, 0.04, 0)), [Vector2(0.042, -0.002), Vector2(0.045, 0.0), Vector2(0.042, 0.002)], 18, Color(0.6, 0.5, 1.0, 0.8))

static func _swarm_hive(k: MeshKit):
	k.sphere("it_chitin", Transform3D(Basis.from_scale(Vector3(1, 1.2, 1)), Vector3(0, 0.05, 0)), 0.045, 8, 10, 0.3, 1.0, Color(0.55, 0.45, 0.28))
	for i in 6:
		var a := TAU * i / 6.0
		k.sphere("it_polymer", Transform3D(Basis(), Vector3(cos(a) * 0.04, 0.05 + 0.02 * (i % 2), sin(a) * 0.04)), 0.008, 3, 5, 0.0, 1.0)

static func _shard_gauntlet(k: MeshKit):
	k.box("it_chitin", Transform3D(Basis(), Vector3(0, 0.03, 0)), Vector3(0.09, 0.1, 0.05), Color(0.3, 0.26, 0.34))
	for i in 4:
		k.crystal("it_crystal", Transform3D(Basis(Vector3(1, 0, 0), -0.3), Vector3(-0.03 + i * 0.02, 0.08, -0.01)), 0.008, 0.05, 5, 0.4, Color(0.7, 0.6, 1.0, 0.8))
