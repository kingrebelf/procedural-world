class_name Flora
## Parametric plants and rocks. A species is a seed: it fixes form, proportions and
## palette; a variant (0..VARIANTS-1) re-rolls the fine detail, so a forest of one species
## still has no two identical silhouettes. Per-instance tint and non-uniform scale (set in
## ChunkNode) add more on top.

const VARIANTS := 3

const ADJ := ["Red", "Silver", "Black", "Golden", "Weeping", "Giant", "Dwarf", "Twisted", "Pale", "Ember", "Frost", "Hollow",
	"Ash", "Copper", "Ghost", "Iron", "Moon", "Sun", "Storm", "Velvet", "Thorn", "Dusk", "Blood", "Amber"]

static func _rng(sp: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(sp, salt)
	return r

static func species_name(t: String, sp: int) -> String:
	var base := ObjectLibrary.LABEL.get(t, t.capitalize()) as String
	if sp == 0:
		return base
	var r := _rng(sp, 77)
	var p := species(t, sp)
	var noun := String(p.get("noun", base))
	return "%s %s" % [ADJ[r.randi() % ADJ.size()], noun]

## Species parameters. Pure function of (t, sp).
static func species(t: String, sp: int) -> Dictionary:
	var r := _rng(sp, 1)
	match t:
		"oak":
			var forms := ["round", "oval", "spreading", "weeping", "column", "shrub", "dead"]
			var form: String = forms[r.randi() % (forms.size() - 1) if r.randf() > 0.06 else forms.size() - 1]
			var autumn := r.randf() < 0.22
			var hue := r.randf_range(0.0, 0.12) if autumn else r.randf_range(0.17, 0.32)
			if r.randf() < 0.05:
				hue = r.randf_range(0.75, 0.95)
			var nouns := {"round": "Oak", "oval": "Elm", "spreading": "Chestnut", "weeping": "Willow", "column": "Birch", "shrub": "Thornbush", "dead": "Deadwood"}
			return {
				"form": form, "noun": nouns[form],
				"height": r.randf_range(2.6, 6.5) * (0.45 if form == "shrub" else 1.0),
				"girth": r.randf_range(0.22, 0.5) * (0.6 if form == "column" else 1.0),
				"crown": r.randf_range(1.3, 2.6) * (0.6 if form == "column" else 1.0) * (0.7 if form == "shrub" else 1.0),
				"blobs": r.randi_range(3, 8), "branches": r.randi_range(2, 6),
				"leaf": Color.from_hsv(hue, r.randf_range(0.45, 0.8), r.randf_range(0.35, 0.65)),
				"bark": Color(0.92, 0.9, 0.86) if form == "column" else Color.from_hsv(r.randf_range(0.05, 0.1), r.randf_range(0.25, 0.5), r.randf_range(0.25, 0.45)),
				"card": r.randf_range(0.9, 1.5), "lean": r.randf_range(0.0, 0.12),
			}
		"pine":
			var forms := ["spruce", "fir", "cypress", "larch", "snag"]
			var form: String = forms[r.randi() % 4 if r.randf() > 0.08 else 4]
			var nouns := {"spruce": "Spruce", "fir": "Fir", "cypress": "Cypress", "larch": "Larch", "snag": "Snag"}
			return {
				"form": form, "noun": nouns[form],
				"height": r.randf_range(6.0, 15.0), "width": r.randf_range(1.6, 3.4) * (0.45 if form == "cypress" else 1.0),
				"tiers": r.randi_range(4, 9), "droop": r.randf_range(0.2, 0.9),
				"leaf": Color.from_hsv(r.randf_range(0.28, 0.42) if form != "larch" else r.randf_range(0.14, 0.2), r.randf_range(0.35, 0.6), r.randf_range(0.18, 0.34)),
				"bark": Color.from_hsv(r.randf_range(0.03, 0.09), r.randf_range(0.3, 0.55), r.randf_range(0.2, 0.38)),
			}
		"glowcap":
			var caps := ["dome", "flat", "cone", "bell", "funnel", "shelf"]
			var cap: String = caps[r.randi() % caps.size()]
			var hue := r.randf()
			return {
				"cap": cap, "noun": {"dome": "Glowcap", "flat": "Parasol", "cone": "Witchcap", "bell": "Bellshroom", "funnel": "Chalice", "shelf": "Shelfcap"}[cap],
				"height": r.randf_range(1.8, 7.5), "stem_r": r.randf_range(0.2, 0.7), "cap_r": r.randf_range(1.2, 4.0),
				"bend": r.randf_range(-0.35, 0.35), "heads": r.randi_range(1, 4) if r.randf() < 0.4 else 1,
				"cap_col": Color.from_hsv(hue, r.randf_range(0.4, 0.85), r.randf_range(0.35, 0.8)),
				"stem_col": Color.from_hsv(fposmod(hue + r.randf_range(-0.1, 0.1), 1.0), r.randf_range(0.05, 0.3), r.randf_range(0.6, 0.9)),
				"glow": r.randi() % 12, "spots": r.randi_range(0, 16),
			}
		"crystal_tree":
			return {
				"noun": ["Crystalbark", "Prismwood", "Shardtree", "Geodewood"][r.randi() % 4],
				"height": r.randf_range(3.0, 7.5), "twist": r.randf_range(-0.6, 0.6), "girth": r.randf_range(0.2, 0.45),
				"spikes": r.randi_range(4, 14), "spike_len": r.randf_range(0.8, 2.6), "glow": r.randi() % 12,
				"moss": r.randf() < 0.6, "moss_col": Color.from_hsv(r.randf_range(0.4, 0.9), r.randf_range(0.3, 0.7), r.randf_range(0.3, 0.6)),
				"bark": Color.from_hsv(r.randf_range(0.6, 0.85), r.randf_range(0.1, 0.4), r.randf_range(0.2, 0.45)),
			}
		"solar_mast":
			var forms := ["panel", "turbine", "antenna", "pylon", "xeno"]
			var form: String = forms[r.randi() % forms.size()]
			return {
				"form": form, "noun": {"panel": "Solar Mast", "turbine": "Wind Turbine", "antenna": "Relay Antenna", "pylon": "Power Pylon", "xeno": "Xeno Bloom"}[form],
				"height": r.randf_range(4.0, 11.0), "glow": r.randi() % 12,
				"paint": Color.from_hsv(r.randf(), r.randf_range(0.0, 0.5), r.randf_range(0.35, 0.85)),
				"blades": r.randi_range(2, 5), "tilt": r.randf_range(-0.7, -0.2),
			}
		"alien_ruin":
			var forms := ["monoliths", "hull", "obelisk", "arch", "pods"]
			var form: String = forms[r.randi() % forms.size()]
			return {
				"form": form, "noun": {"monoliths": "Xenolith Circle", "hull": "Derelict Hull", "obelisk": "Singing Obelisk", "arch": "Glyph Arch", "pods": "Seed Pods"}[form],
				"stone": Color.from_hsv(r.randf_range(0.55, 0.85), r.randf_range(0.05, 0.3), r.randf_range(0.12, 0.3)),
				"glow": r.randi() % 12, "size": r.randf_range(0.8, 1.6), "count": r.randi_range(4, 9),
			}
		"rock", "iron_vein", "aether_crystal", "alloy_scrap":
			var shapes := ["boulder", "slab", "spire", "cluster", "flat"]
			var stone_hue: float = [0.08, 0.05, 0.6, 0.12, 0.0, 0.3][r.randi() % 6]
			return {
				"shape": shapes[r.randi() % shapes.size()], "noun": "",
				"stone": Color.from_hsv(stone_hue, r.randf_range(0.02, 0.3), r.randf_range(0.3, 0.75)),
				"squash": r.randf_range(0.45, 1.1), "rough": r.randf_range(0.2, 0.5),
				"moss": r.randf() < 0.35, "glow": r.randi() % 12,
			}
	return {}

## Builds the mesh for (t, sp, v) into k. Returns false if the type is not parametric.
static func build(k: MeshKit, t: String, sp: int, v: int) -> bool:
	var p := species(t, sp)
	if p.is_empty():
		return false
	var r := _rng(sp, 100 + v)
	match t:
		"oak": _broadleaf(k, p, r)
		"pine": _conifer(k, p, r)
		"glowcap": _mushroom(k, p, r)
		"crystal_tree": _crystal_tree(k, p, r)
		"solar_mast": _mast(k, p, r)
		"alien_ruin": _alien(k, p, r)
		"rock", "iron_vein", "aether_crystal", "alloy_scrap": _rock(k, t, p, r)
		_: return false
	return true

## Undergrowth (ferns, bushes, flowers, reeds, glow-bulbs, xeno tendrils). No collision,
## no gameplay state: drawn near the player only. The era is passed as the variant.
static func build_under(k: MeshKit, sp: int, era: int) -> void:
	var r := _rng(sp, 5)
	var forms: Array = [["fern", "bush", "flowers", "reeds"], ["fern", "bush", "glowbulbs", "fronds"], ["tendrils", "bush", "glowbulbs", "reeds"]][era]
	var form: String = forms[r.randi() % forms.size()]
	var hue := r.randf()
	var leaf := Color.from_hsv(r.randf_range(0.17, 0.33), r.randf_range(0.4, 0.75), r.randf_range(0.3, 0.55))
	if era == Eras.FANTASY:
		leaf = Color.from_hsv(fposmod(0.45 + r.randf_range(-0.15, 0.4), 1.0), r.randf_range(0.4, 0.7), r.randf_range(0.35, 0.6))
	elif era == Eras.SCIFI:
		leaf = Color.from_hsv(r.randf_range(0.0, 0.12), r.randf_range(0.2, 0.6), r.randf_range(0.25, 0.45))
	var I := Transform3D.IDENTITY
	match form:
		"fern", "fronds":
			var n := r.randi_range(6, 11)
			var len := r.randf_range(0.5, 1.1)
			for i in n:
				var a := TAU * i / n + r.randf() * 0.3
				var out := Vector3(cos(a), 0, sin(a))
				var b := Basis.looking_at(out, Vector3.UP).rotated(out.cross(Vector3.UP).normalized(), r.randf_range(0.5, 1.0))
				k.card("leaf_card_w", I, out * len * 0.45 + Vector3(0, len * 0.35, 0), b, len * 0.45, len, Vector3.UP * 0.6, _jit(leaf, r, 0.12))
		"bush":
			var rad := r.randf_range(0.4, 0.9)
			for i in r.randi_range(1, 3):
				var c := Vector3(r.randf_range(-0.4, 0.4), rad * 0.7, r.randf_range(-0.4, 0.4))
				k.sphere("leaf_core_w", I.translated(c), rad * 0.7, 5, 8, 0.4, 0.8, leaf * 0.7)
				_cards(k, "leaf_card_w", c, rad, int(14 * rad + 6), r, 0.55, leaf)
			if r.randf() < 0.4:
				var berry := "glow@%d" % (r.randi() % 12) if era == Eras.FANTASY else "petal_w"
				for i in 8:
					var d := Vector3(r.randf_range(-1, 1), r.randf_range(0.2, 1), r.randf_range(-1, 1)).normalized()
					k.sphere(berry, I.translated(Vector3(0, rad * 0.7, 0) + d * rad * 0.9), 0.04, 3, 5, 0.0, 1.0, Color.from_hsv(hue, 0.8, 0.8))
		"flowers":
			for i in r.randi_range(5, 12):
				var pos := Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.6, 0.6))
				var h := r.randf_range(0.2, 0.55)
				k.cylinder("leaf_core_w", I.translated(pos), 0.01, 0.008, h, 4, false, 0.0, 1, leaf)
				k.sphere("petal_w", I.translated(pos + Vector3(0, h, 0)), r.randf_range(0.03, 0.06), 3, 6, 0.0, 0.45, Color.from_hsv(fposmod(hue + r.randf_range(-0.05, 0.05), 1.0), r.randf_range(0.5, 0.9), 0.95))
		"reeds", "tendrils":
			for i in r.randi_range(6, 14):
				var pos := Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4))
				var h := r.randf_range(0.6, 1.6)
				_limb(k, "leaf_core_w", pos, Vector3(r.randf_range(-0.2, 0.2), 1, r.randf_range(-0.2, 0.2)), h, 0.025, 0.006, _jit(leaf, r, 0.15), 4)
				if form == "tendrils" and r.randf() < 0.4:
					k.sphere("glow@%d" % (r.randi() % 12), I.translated(pos + Vector3(0, h, 0)), 0.04, 3, 5)
		"glowbulbs":
			for i in r.randi_range(3, 7):
				var pos := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
				var h := r.randf_range(0.15, 0.6)
				_limb(k, "leaf_core_w", pos, Vector3(0, 1, 0), h, 0.03, 0.02, leaf, 5)
				k.sphere("glow@%d" % (r.randi() % 12), I.translated(pos + Vector3(0, h + 0.05, 0)), r.randf_range(0.05, 0.12), 4, 7, 0.1, 1.2)

static func _limb(k: MeshKit, mat: String, from: Vector3, dir: Vector3, length: float, r0: float, r1: float, col: Color, segs := 7) -> Vector3:
	dir = dir.normalized()
	var b := Basis.IDENTITY
	if dir.distance_to(Vector3.UP) > 0.001:
		var axis := Vector3.UP.cross(dir)
		if axis.length() < 0.001:
			axis = Vector3.RIGHT
		b = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	k.cylinder(mat, Transform3D(b, from), r0, r1, length, segs, false, 0.08, 2, col)
	return from + dir * length

static func _jit(c: Color, r: RandomNumberGenerator, amt: float) -> Color:
	var f := r.randf_range(1.0 - amt, 1.0 + amt)
	return Color(c.r * f, c.g * f * r.randf_range(0.95, 1.05), c.b * f, 1.0)

static func _broadleaf(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var h: float = p["height"] * r.randf_range(0.85, 1.15)
	var g: float = p["girth"]
	var bark: Color = p["bark"]
	var lean := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * float(p["lean"])
	var form: String = p["form"]
	var bm := "birch_w" if form == "column" else "bark_w"
	var top := _limb(k, bm, Vector3.ZERO, Vector3.UP + lean, h, g, g * 0.55, bark, 10)
	var tips: Array = [top]
	for b in int(p["branches"]):
		var a := r.randf() * TAU
		var up := r.randf_range(0.5, 1.4) if form != "spreading" else r.randf_range(0.2, 0.6)
		var from := Vector3.UP * h * r.randf_range(0.55, 0.95) + lean * h * 0.7
		var len := float(p["crown"]) * r.randf_range(0.6, 1.2)
		tips.append(_limb(k, bm, from, Vector3(cos(a), up, sin(a)), len, g * 0.4, g * 0.12, bark, 6))
	if form == "dead":
		for b in 4:
			var a := r.randf() * TAU
			_limb(k, "bark_w", top, Vector3(cos(a), r.randf_range(0.2, 1.0), sin(a)), r.randf_range(0.6, 1.6), g * 0.2, 0.02, bark, 5)
		return
	var leaf: Color = p["leaf"]
	var crown: float = p["crown"]
	for n in int(p["blobs"]):
		var base: Vector3 = tips[n % tips.size()]
		var c := base + Vector3(r.randf_range(-0.6, 0.6), r.randf_range(-0.3, 0.7), r.randf_range(-0.6, 0.6)) * crown
		var rad := crown * r.randf_range(0.65, 1.05)
		var squash := 1.0
		match form:
			"oval", "column": squash = 1.5
			"spreading": squash = 0.6
			"weeping": c.y -= crown * 0.4
		var lc := _jit(leaf, r, 0.12)
		k.sphere("leaf_core_w", Transform3D.IDENTITY.translated(c), rad * 0.7, 6, 9, 0.4, squash * 0.85, lc * 0.75)
		_cards(k, "leaf_card_w", c, rad, int(26 * rad), r, float(p["card"]), lc, squash, form == "weeping")

static func _cards(k: MeshKit, mat: String, center: Vector3, radius: float, count: int, r: RandomNumberGenerator, size: float, col: Color, squash := 1.0, droop := false) -> void:
	for c in count:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.6, 1), r.randf_range(-1, 1)).normalized()
		var p := center + Vector3(d.x, d.y * squash, d.z) * radius * r.randf_range(0.6, 1.0)
		var b := Basis.looking_at(-d if absf(d.y) < 0.95 else Vector3(0.01, -d.y, 0.0), Vector3.UP).rotated(d, r.randf() * TAU)
		var sz := size * r.randf_range(0.8, 1.3)
		if droop:
			k.card(mat, Transform3D.IDENTITY, p + Vector3.DOWN * sz * 0.6, Basis(), sz * 0.6, sz * 2.2, d * 0.8, _jit(col, r, 0.15))
		else:
			k.card(mat, Transform3D.IDENTITY, p, b, sz, sz, d * 0.8, _jit(col, r, 0.15))

static func _conifer(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var h: float = p["height"] * r.randf_range(0.85, 1.15)
	var w: float = p["width"]
	var bark: Color = p["bark"]
	k.cylinder("bark_w", Transform3D.IDENTITY, w * 0.12 + 0.12, 0.06, h, 8, false, 0.08, 3, bark)
	if p["form"] == "snag":
		for n in 6:
			var a := r.randf() * TAU
			_limb(k, "bark_w", Vector3.UP * h * r.randf_range(0.3, 0.9), Vector3(cos(a), r.randf_range(-0.3, 0.3), sin(a)), r.randf_range(0.5, 1.4), 0.06, 0.01, bark, 4)
		return
	var tiers: int = p["tiers"]
	var leaf: Color = p["leaf"]
	for n in tiers:
		var t := float(n) / tiers
		var y := h * (0.18 + t * 0.75)
		var rad := w * (1.0 - t * 0.85) * r.randf_range(0.85, 1.1)
		var lc := _jit(leaf, r, 0.1)
		k.cylinder("leaf_core_w", Transform3D.IDENTITY.translated(Vector3(0, y, 0)), rad * 0.55, 0.05, h / tiers * 1.6, 10, true, 0.25, 2, lc * 0.55)
		var cards := int(10 + rad * 5)
		for c in cards:
			var a := TAU * c / cards + r.randf() * 0.3
			var out := Vector3(cos(a), 0, sin(a))
			var pos := Vector3(0, y + r.randf_range(0.0, 0.6), 0) + out * rad * r.randf_range(0.35, 0.8)
			var b := Basis.looking_at(out, Vector3.UP).rotated(out.cross(Vector3.UP).normalized(), float(p["droop"]) + r.randf() * 0.4)
			k.card("needle_card_w", Transform3D.IDENTITY, pos, b, rad * 0.9, 1.4, Vector3.UP * 0.5, _jit(lc, r, 0.12))
	k.card("needle_card_w", Transform3D.IDENTITY, Vector3(0, h + 0.6, 0), Basis(), 0.8, 1.6, Vector3.ZERO, leaf)
	k.card("needle_card_w", Transform3D.IDENTITY, Vector3(0, h + 0.6, 0), Basis(Vector3.UP, PI * 0.5), 0.8, 1.6, Vector3.ZERO, leaf)

static func _mushroom(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var heads: int = p["heads"]
	for hd in heads:
		var scale := 1.0 if hd == 0 else r.randf_range(0.35, 0.7)
		var off := Vector3.ZERO if hd == 0 else Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * float(p["cap_r"]) * r.randf_range(0.6, 1.1)
		var h: float = p["height"] * scale * r.randf_range(0.85, 1.15)
		var sr: float = p["stem_r"] * scale
		var bend := Vector3(float(p["bend"]) * r.randf_range(0.6, 1.4), 1, float(p["bend"]) * r.randf_range(-0.5, 0.5))
		var top := _limb(k, "cap_w", off, bend, h, sr * 1.25, sr * 0.8, p["stem_col"], 12)
		var cr: float = p["cap_r"] * scale * r.randf_range(0.85, 1.15)
		var cc := _jit(p["cap_col"], r, 0.1)
		var xf := Transform3D.IDENTITY.translated(top - Vector3(0, cr * 0.12, 0))
		match String(p["cap"]):
			"dome": k.sphere("cap_w", xf, cr, 10, 18, 0.1, 0.55, cc, true)
			"flat": k.sphere("cap_w", xf, cr, 10, 18, 0.06, 0.22, cc, true)
			"bell": k.sphere("cap_w", xf, cr * 0.75, 10, 16, 0.08, 1.2, cc, true)
			"cone": k.cylinder("cap_w", xf, cr * 0.8, 0.02, cr * 1.4, 16, true, 0.06, 3, cc)
			"funnel": k.cylinder("cap_w", xf, cr * 0.25, cr, cr * 0.5, 16, true, 0.08, 2, cc)
			"shelf":
				for s in 3:
					k.sphere("cap_w", Transform3D.IDENTITY.translated(top * (0.45 + s * 0.27) + Vector3(sr, 0, 0)), cr * (0.6 - s * 0.12), 6, 12, 0.1, 0.3, cc, true)
		# Gills ring and glowing spots.
		k.cylinder("cap_w", Transform3D.IDENTITY.translated(top - Vector3(0, cr * 0.14, 0)), cr * 0.85, sr, 0.05, 16, true, 0.0, 1, cc.darkened(0.5))
		var glow := "glow@%d" % int(p["glow"])
		for s in int(p["spots"] * scale):
			var a := r.randf() * TAU
			var rr := cr * r.randf_range(0.3, 0.85)
			k.sphere(glow, Transform3D.IDENTITY.translated(top + Vector3(cos(a) * rr, cr * 0.1, sin(a) * rr)), cr * 0.04 + 0.04, 3, 5)
	# Little ones at the base.
	for n in r.randi_range(0, 4):
		var a := r.randf() * TAU
		var pos := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.8, 2.0)
		k.cylinder("cap_w", Transform3D.IDENTITY.translated(pos), 0.08, 0.06, 0.35, 6, false, 0.0, 1, p["stem_col"])
		k.sphere("cap_w", Transform3D.IDENTITY.translated(pos + Vector3(0, 0.33, 0)), 0.22, 5, 8, 0.1, 0.6, p["cap_col"], true)

static func _crystal_tree(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var h: float = p["height"] * r.randf_range(0.85, 1.15)
	var g: float = p["girth"]
	var seg := 4
	var pos := Vector3.ZERO
	var dir := Vector3.UP
	for s in seg:
		dir = dir.rotated(Vector3.UP, float(p["twist"])).lerp(Vector3(r.randf_range(-0.3, 0.3), 1, r.randf_range(-0.3, 0.3)), 0.4).normalized()
		pos = _limb(k, "bark_w", pos, dir, h / seg, g * (1.0 - s * 0.18), g * (1.0 - (s + 1) * 0.18), p["bark"], 8)
	var mat := "crystal@%d" % int(p["glow"])
	for n in int(p["spikes"]):
		var a := r.randf() * TAU
		var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -r.randf_range(0.3, 1.1))
		k.crystal(mat, Transform3D(b, pos + Vector3(cos(a), 0, sin(a)) * r.randf_range(0.2, 0.9) - Vector3(0, r.randf() * 0.8, 0)), r.randf_range(0.08, 0.2), float(p["spike_len"]) * r.randf_range(0.6, 1.3))
	if p["moss"]:
		k.sphere("leaf_core_w", Transform3D.IDENTITY.translated(pos), 1.2, 7, 10, 0.5, 0.6, p["moss_col"])
		_cards(k, "leaf_card_w", pos, 1.6, 34, r, 1.0, p["moss_col"])

static func _mast(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var h: float = p["height"] * r.randf_range(0.85, 1.15)
	var paint: Color = p["paint"]
	var glow := "glow@%d" % int(p["glow"])
	var I := Transform3D.IDENTITY
	match String(p["form"]):
		"panel":
			k.box("metal_dark", I.translated(Vector3(0, 0.2, 0)), Vector3(1.6, 0.4, 1.6))
			k.cylinder("metal_w", I, 0.16, 0.12, h, 8, true, 0.0, 1, paint)
			var tilt := Basis(Vector3(1, 0, 0), float(p["tilt"]))
			var n := r.randi_range(1, 3)
			for i in n:
				var y := h - i * 1.4
				k.box("metal_dark", Transform3D(tilt, Vector3(0, y, 0)), Vector3(3.2, 0.08, 1.9))
				k.box("glass", Transform3D(tilt, Vector3(0, y + 0.05, 0)), Vector3(3.0, 0.04, 1.75))
			k.sphere(glow, I.translated(Vector3(0, h + 0.8, 0)), 0.09, 4, 6)
		"turbine":
			k.cylinder("metal_w", I, 0.35, 0.18, h, 10, true, 0.0, 1, paint)
			k.box("metal_w", I.translated(Vector3(0, h, 0.2)), Vector3(0.5, 0.5, 1.0), paint)
			var blades: int = p["blades"]
			var spin := r.randf() * TAU
			for b in blades:
				var a := spin + TAU * b / blades
				k.box("metal_w", Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(0, h, 0.75)).translated_local(Vector3(0, h * 0.18, 0)), Vector3(0.25, h * 0.36, 0.05), paint.lightened(0.2))
			k.sphere(glow, I.translated(Vector3(0, h + 0.3, 0.2)), 0.08, 4, 6)
		"antenna":
			for leg in 3:
				var a := TAU * leg / 3.0
				_limb(k, "metal_w", Vector3(cos(a), 0, sin(a)) * 1.2, Vector3(-cos(a) * 1.2, h, -sin(a) * 1.2), Vector3(cos(a) * 1.2, h, sin(a) * 1.2).length(), 0.06, 0.04, paint, 5)
			for d in r.randi_range(1, 3):
				k.cylinder("metal_dark", Transform3D(Basis(Vector3(1, 0, 0), -0.6 - d * 0.3).rotated(Vector3.UP, r.randf() * TAU), Vector3(0, h * (0.6 + d * 0.12), 0)), 0.9 - d * 0.2, 0.05, 0.4, 14)
			k.sphere(glow, I.translated(Vector3(0, h + 0.2, 0)), 0.1, 4, 6)
		"pylon":
			k.box("metal_w", I.translated(Vector3(0, h * 0.5, 0)), Vector3(0.6, h, 0.6), paint)
			for c in 2:
				k.box("metal_w", I.translated(Vector3(0, h * (0.6 + c * 0.3), 0)), Vector3(3.0 - c, 0.15, 0.3), paint)
				for x in [-1.0, 1.0]:
					k.cylinder(glow, I.translated(Vector3(x * (1.3 - c * 0.5), h * (0.6 + c * 0.3) - 0.45, 0)), 0.06, 0.06, 0.4, 6)
		"xeno":
			# Alien flora: bulbous stalks with luminous tips.
			var col := paint.lerp(Color.from_hsv(float(p["glow"]) / 12.0, 0.6, 0.5), 0.6)
			for s in r.randi_range(3, 7):
				var a := r.randf() * TAU
				var tip := _limb(k, "cap_w", Vector3(cos(a), 0, sin(a)) * r.randf_range(0, 0.6), Vector3(cos(a) * 0.3, 1, sin(a) * 0.3), h * r.randf_range(0.3, 0.7), 0.18, 0.08, col, 8)
				k.sphere("cap_w", I.translated(tip), r.randf_range(0.25, 0.5), 6, 10, 0.2, 1.3, col.lightened(0.2))
				k.sphere(glow, I.translated(tip + Vector3(0, 0.35, 0)), 0.1, 4, 6)

static func _rock(k: MeshKit, t: String, p: Dictionary, r: RandomNumberGenerator) -> void:
	var col := _jit(p["stone"], r, 0.08)
	var I := Transform3D.IDENTITY
	var sq: float = p["squash"]
	var rough: float = p["rough"]
	var shape: String = p["shape"]
	match shape:
		"slab":
			k.sphere("stone_w", Transform3D(Basis(Vector3(1, 0, 0), r.randf_range(-0.3, 0.3)), Vector3(0, 0.3, 0)), 1.1, 8, 12, rough, 0.35, col)
		"spire":
			k.sphere("stone_w", I.translated(Vector3(0, 0.9, 0)), 0.8, 9, 12, rough, 2.2, col)
		"cluster":
			for n in 3:
				var a := TAU * n / 3.0 + r.randf()
				k.sphere("stone_w", I.translated(Vector3(cos(a) * 0.7, 0.25, sin(a) * 0.7)), r.randf_range(0.45, 0.8), 7, 10, rough, sq, _jit(col, r, 0.1))
		"flat":
			k.sphere("stone_w", I.translated(Vector3(0, 0.1, 0)), 1.2, 7, 12, rough * 0.6, 0.3, col)
		_:
			k.sphere("stone_w", I.translated(Vector3(0, 0.35, 0)), 1.0, 9, 14, rough, sq, col)
	if p["moss"] and t == "rock":
		k.sphere("leaf_w", I.translated(Vector3(0, 0.55 * sq + 0.2, 0)), 0.75, 6, 9, 0.4, 0.3, Color(0.25, 0.42, 0.18))
	match t:
		"iron_vein":
			for n in 7:
				var a := n * 2.4 + r.randf()
				k.sphere("rust", I.translated(Vector3(cos(a) * 0.7, 0.4 + r.randf() * 0.4, sin(a) * 0.7)), 0.28, 5, 7, 0.4)
		"aether_crystal":
			var mat := "crystal@%d" % int(p["glow"])
			for n in r.randi_range(4, 9):
				var a := r.randf() * TAU
				var b := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), r.randf_range(0.1, 0.6))
				k.crystal(mat, Transform3D(b, Vector3(cos(a) * 0.35, 0.2, sin(a) * 0.35)), r.randf_range(0.12, 0.26), r.randf_range(0.8, 2.4))
		"alloy_scrap":
			for n in 7:
				var b := Basis.from_euler(Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6)))
				var pos := Vector3(r.randf_range(-0.9, 0.9), r.randf_range(0.3, 0.9), r.randf_range(-0.9, 0.9))
				k.box("metal_w", Transform3D(b, pos), Vector3(r.randf_range(0.3, 1.2), r.randf_range(0.05, 0.3), r.randf_range(0.3, 1.0)), Color.from_hsv(r.randf(), r.randf_range(0, 0.5), r.randf_range(0.4, 0.8)))
			k.box("glow@%d" % int(p["glow"]), Transform3D(Basis(Vector3.UP, r.randf()), Vector3(0.2, 0.95, 0.1)), Vector3(0.4, 0.05, 0.05))

static func _alien(k: MeshKit, p: Dictionary, r: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var col: Color = p["stone"]
	var glow := "glow@%d" % int(p["glow"])
	var sz: float = p["size"]
	match String(p["form"]):
		"monoliths":
			var n: int = p["count"]
			for i in n:
				var a := TAU * i / n
				var pos := Vector3(cos(a), 0, sin(a)) * 5.0 * sz
				var h := r.randf_range(3.0, 6.5) * sz
				var b := Basis(Vector3.UP, -a).rotated(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), r.randf_range(-0.12, 0.12))
				k.box("metal_w", Transform3D(b, pos + Vector3(0, h * 0.45, 0)), Vector3(0.9, h, 0.5) * Vector3(sz, 1, sz), col)
				k.box(glow, Transform3D(b, pos + Vector3(0, h * 0.6, 0)), Vector3(0.12, h * 0.5, 0.52) * Vector3(sz, 1, sz))
			k.cylinder("metal_w", I, 1.6 * sz, 1.4 * sz, 0.3, 24, true, 0.0, 1, col.lightened(0.1))
			k.sphere(glow, I.translated(Vector3(0, 1.4 * sz, 0)), 0.35 * sz, 6, 10)
		"hull":
			var b := Basis.from_euler(Vector3(r.randf_range(-0.35, -0.15), r.randf() * TAU, r.randf_range(-0.3, 0.3)))
			k.sphere("metal_w", Transform3D(b, Vector3(0, 0.8, 0)), 3.0 * sz, 8, 16, 0.08, 0.45, col)
			k.cylinder("metal_w", Transform3D(b * Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, 0.6, -2.5 * sz)), 1.2 * sz, 0.5 * sz, 3.5 * sz, 12, true, 0.0, 1, col.darkened(0.2))
			for i in 5:
				k.box(glow, Transform3D(b, Vector3(r.randf_range(-2, 2), 1.4 + r.randf() * 0.6, r.randf_range(-2, 2)) * sz), Vector3(0.6, 0.06, 0.06))
			for i in 4:
				var a := r.randf() * TAU
				k.box("metal_w", Transform3D(Basis.from_euler(Vector3(r.randf(), a, r.randf())), Vector3(cos(a), 0.2, sin(a)) * 4.5 * sz), Vector3(1.4, 0.1, 0.8) * sz, col)
		"obelisk":
			var h := 9.0 * sz
			k.cylinder("metal_w", I, 1.1 * sz, 0.3 * sz, h, 4, true, 0.0, 1, col)
			for i in 6:
				k.box(glow, I.translated(Vector3(0, 1.2 + i * h / 7.5, 0)), Vector3(1.7 - i * 0.2, 0.1, 1.7 - i * 0.2) * sz)
			k.crystal("crystal@%d" % int(p["glow"]), I.translated(Vector3(0, h, 0)), 0.3 * sz, 1.4 * sz)
			for i in 3:
				var a := TAU * i / 3.0
				k.box("metal_w", Transform3D(Basis(Vector3.UP, a), Vector3(cos(a), 0.4, sin(a)) * 2.2 * sz), Vector3(1.2, 0.8, 0.6) * sz, col.darkened(0.2))
		"arch":
			var w := 4.0 * sz
			var h := 6.0 * sz
			for side in [-1.0, 1.0]:
				_limb(k, "metal_w", Vector3(side * w, 0, 0), Vector3(-side * 0.25, 1, 0), h, 0.7 * sz, 0.5 * sz, col, 6)
			_limb(k, "metal_w", Vector3(-w - 0.5, h * 0.95, 0), Vector3(1, 0.05, 0), w * 2.0 + 1.0, 0.55 * sz, 0.55 * sz, col, 6)
			for i in 9:
				k.box(glow, I.translated(Vector3(-w + i * w / 4.0, h * 0.95, 0.56 * sz)), Vector3(0.25, 0.25, 0.02) * sz)
		"pods":
			var n: int = p["count"]
			for i in n:
				var a := r.randf() * TAU
				var pos := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 4.0) * sz
				var ps := r.randf_range(0.6, 1.5) * sz
				k.sphere("cap_w", I.translated(pos + Vector3(0, ps * 0.8, 0)), ps, 8, 12, 0.15, 1.3, col.lightened(0.3))
				k.sphere(glow, I.translated(pos + Vector3(0, ps * 1.6, 0)), ps * 0.18, 4, 7)
