class_name Outfit
## Real clothes and armour for the kit people: garments with thickness and shape, skinned
## to the same skeleton as the body so they move with every animation.
##
## Fitted pieces (shirts, trousers, boots, breastplates, greaves, helmets...) are shells
## lifted off the body surface along its normals, region by region. Loose pieces (skirts,
## robes, tunic hems, capes, belts) are built around the body and weighted to the hips and
## thighs so they swing with the legs. Everything is cached per body and style, so a whole
## town of people shares a handful of meshes.
##
## CUSTOM0 on every vertex: x = part (see PART_*), y = rest height, z = rest depth, w = rest
## side; CUSTOM1 the rest normal. The shaders map fabric onto the rest pose with them, so
## the weave stays put on a moving body. Armour also carries COLOR: rgb = the item's colour, a = style / 8.

enum {PART_SHIRT = 1, PART_PANTS, PART_BOOTS, PART_BELT, PART_SKIRT, PART_CAPE, PART_TRIM}
enum {STYLE_LEATHER, STYLE_MAIL, STYLE_PLATE, STYLE_CRYSTAL, STYLE_EXO, STYLE_CLOTH}

const ARMOR_SHADER := "res://src/npc/armor.gdshader"
const CLOTH_SHADER := "res://src/npc/cloth.gdshader"

static var _src_cache := {}
static var _cache := {}
static var _mats := {}

## Everything a garment needs to know about one body, measured once per sex.
static func _src(fem: bool, body: ArrayMesh, skin: Skin, sk: Skeleton3D) -> Dictionary:
	var key := "src_%s" % fem
	if _src_cache.has(key):
		return _src_cache[key]
	var a := body.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var custom: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var region := PackedInt32Array()
	region.resize(verts.size())
	for i in verts.size():
		region[i] = int(custom[i * 3] + 0.5)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var binds := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "":
			bn = sk.get_bone_name(skin.get_bind_bone(i))
		binds[bn] = i
	var bone_y := func(n: String) -> Vector3:
		var b := sk.find_bone(n)
		return sk.get_bone_global_rest(b).origin if b >= 0 else Vector3.ZERO
	var pelvis: Vector3 = bone_y.call("pelvis")
	var spine1: Vector3 = bone_y.call("spine_01")
	var head: Vector3 = bone_y.call("Head")
	var neck: Vector3 = bone_y.call("neck_01")
	var calf: Vector3 = bone_y.call("calf_l")
	var shoulder: Vector3 = bone_y.call("upperarm_l")
	var s := {
		"v": verts, "n": a[Mesh.ARRAY_NORMAL], "uv": a[Mesh.ARRAY_TEX_UV], "b": bones, "w": a[Mesh.ARRAY_WEIGHTS],
		"r": region, "i": idx, "per": bones.size() / verts.size(), "binds": binds,
		"waist": lerpf(pelvis.y, spine1.y, 0.55), "crotch": pelvis.y - 0.09, "knee": calf.y,
		"neck": neck.y, "head": head, "shoulder_x": absf(shoulder.x), "shoulder_y": shoulder.y,
		"fmt": body.surface_get_format(0),
	}
	_src_cache[key] = s
	return s

## The body's outline at height y: {cz, rx, rz, back} over the torso, hips and legs.
static func _measure(s: Dictionary, y: float, band := 0.02) -> Dictionary:
	var v: PackedVector3Array = s["v"]
	var r: PackedInt32Array = s["r"]
	var mx := 0.0
	var zmin := INF
	var zmax := -INF
	for i in v.size():
		var p := v[i]
		if absf(p.y - y) > band or not (r[i] == 1 or r[i] == 5 or r[i] == 6 or r[i] == 0):
			continue
		mx = maxf(mx, absf(p.x))
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	if zmin == INF:
		return {"cz": 0.0, "rx": 0.12, "rz": 0.1, "back": -0.1}
	return {"cz": (zmin + zmax) * 0.5, "rx": mx, "rz": (zmax - zmin) * 0.5, "back": zmin}

# --- Building blocks ------------------------------------------------------------------------

static func _new_out() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(),
		"w": PackedFloat32Array(), "c": PackedFloat32Array(), "rn": PackedFloat32Array(), "col": PackedColorArray(), "i": PackedInt32Array()}

## Copies the body triangles whose three corners `pick` accepts, pushed out along their
## normals. pick(i: vertex, p: rest position, region) -> thickness, or < 0 to leave out.
static func _shell(s: Dictionary, o: Dictionary, part: int, col: Color, pick: Callable) -> void:
	var v: PackedVector3Array = s["v"]
	var nr: PackedVector3Array = s["n"]
	var uv: PackedVector2Array = s["uv"]
	var bones: PackedInt32Array = s["b"]
	var wts: PackedFloat32Array = s["w"]
	var reg: PackedInt32Array = s["r"]
	var idx: PackedInt32Array = s["i"]
	var per: int = s["per"]
	var off := PackedFloat32Array()
	off.resize(v.size())
	for i in v.size():
		off[i] = pick.call(i, v[i], reg[i])
	var remap := {}
	var ov: PackedVector3Array = o["v"]
	var base := ov.size()
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		if off[a] < 0.0 or off[b] < 0.0 or off[c] < 0.0:
			continue
		for k in [a, b, c]:
			if not remap.has(k):
				remap[k] = base + remap.size()
				var rp := v[k] + nr[k] * off[k]
				o["v"].append(rp)
				o["n"].append(nr[k])
				o["uv"].append(uv[k] if uv.size() > k else Vector2.ZERO)
				for j in per:
					o["b"].append(bones[k * per + j])
					o["w"].append(wts[k * per + j])
				o["c"].append_array([float(part), rp.y, rp.z, rp.x])
				o["rn"].append_array([nr[k].x, nr[k].y, nr[k].z])
				o["col"].append(col)
			o["i"].append(remap[k])

## Appends one vertex with explicit skinning: wb = {bind name: weight}.
static func _vert(s: Dictionary, o: Dictionary, p: Vector3, n: Vector3, uv: Vector2, wb: Dictionary, part: int, col: Color) -> void:
	var per: int = s["per"]
	o["v"].append(p)
	o["n"].append(n.normalized())
	o["uv"].append(uv)
	var names := wb.keys()
	var total := 0.0
	for k in names:
		total += float(wb[k])
	for j in per:
		if j < names.size() and s["binds"].has(names[j]):
			o["b"].append(int(s["binds"][names[j]]))
			o["w"].append(float(wb[names[j]]) / maxf(total, 1e-5))
		else:
			o["b"].append(0)
			o["w"].append(0.0)
	o["c"].append_array([float(part), p.y, p.z, p.x])
	var rn := n.normalized()
	o["rn"].append_array([rn.x, rn.y, rn.z])
	o["col"].append(col)

## A loose skirt, robe or tunic hem from the waist down to `hem` (rest height), flaring
## out by `flare`, swinging with the thighs.
static func _skirt(s: Dictionary, o: Dictionary, top: float, hem: float, flare: float, part: int, col: Color) -> void:
	var segs := 22
	var rings := maxi(2, int((top - hem) / 0.045) + 1)
	var base: int = o["v"].size()
	var prev_rx := 0.0
	var prev_rz := 0.0
	for ri in rings + 1:
		var k := float(ri) / rings
		var y := lerpf(top, hem, k)
		var m := _measure(s, y)
		var below := clampf((top - y) / 0.15, 0.0, 1.0) # room for the thighs to move under it
		var rx := maxf(float(m["rx"]) * 1.04 + 0.022 + 0.045 * below, prev_rx) + flare * k * k * 0.1
		var rz := maxf(float(m["rz"]) * 1.08 + 0.03 + 0.04 * below, prev_rz) + flare * k * k * 0.08
		prev_rx = rx
		prev_rz = rz
		var cz: float = m["cz"]
		var swing := clampf((y - top) / (hem - top - 0.001), 0.0, 1.0)
		for si in segs + 1:
			var ang := TAU * si / segs
			var p := Vector3(sin(ang) * rx, y, cz + cos(ang) * rz)
			# Mostly carried by the hips; the side over each leg follows that thigh a little,
			# so walking moves the hem without the whole skirt swinging out.
			var side := smoothstep(-0.55 * rx, 0.55 * rx, p.x)
			var legs := 0.55 * pow(swing, 1.5)
			var wb := {"pelvis": 1.0 - legs, "thigh_l": legs * side, "thigh_r": legs * (1.0 - side)}
			_vert(s, o, p, Vector3(sin(ang) / rx, 0.15 * k, cos(ang) / rz), Vector2(float(si) / segs * 3.0, k * 2.0), wb, part, col)
	for ri in rings:
		for si in segs:
			var a := base + ri * (segs + 1) + si
			var b := a + segs + 1
			o["i"].append_array([a, b, a + 1, a + 1, b, b + 1])

## A cape from the shoulders to `hem`, hanging clear of the back.
static func _cape(s: Dictionary, o: Dictionary, hem: float, col: Color) -> void:
	var top: float = s["shoulder_y"] + 0.02
	var cols := 9
	var rows := maxi(3, int((top - hem) / 0.06))
	var base: int = o["v"].size()
	var zback := INF
	for ri in rows + 1:
		var k := float(ri) / rows
		var y := lerpf(top, hem, k)
		var m := _measure(s, y, 0.03)
		zback = minf(zback, float(m["back"]) - 0.035)
		var half: float = lerpf(float(s["shoulder_x"]) * 0.95, float(s["shoulder_x"]) * 1.35, k)
		var wb := {}
		if y > s["waist"]:
			var u := clampf((y - s["waist"]) / (top - float(s["waist"])), 0.0, 1.0)
			wb = {"spine_03": u, "spine_01": 1.0 - u}
		else:
			var legs := clampf((s["waist"] - y) / 0.6, 0.0, 0.6)
			wb = {"pelvis": 1.0 - legs, "thigh_l": legs * 0.5, "thigh_r": legs * 0.5}
		for ci in cols + 1:
			var u2 := float(ci) / cols
			var x := lerpf(-half, half, u2)
			var curve := (1.0 - pow(2.0 * u2 - 1.0, 2.0)) * 0.03
			_vert(s, o, Vector3(x, y, zback - curve), Vector3(0, 0.05, -1), Vector2(u2 * 2.0, k * 3.0), wb, PART_CAPE, col)
	for ri in rows:
		for ci in cols:
			var a := base + ri * (cols + 1) + ci
			var b := a + cols + 1
			o["i"].append_array([a, a + 1, b, a + 1, b + 1, b])

## A belt: a short band around the waist.
static func _belt(s: Dictionary, o: Dictionary, y: float, col: Color, part := PART_BELT, width := 0.045, out := 0.012) -> void:
	var segs := 24
	var base: int = o["v"].size()
	for ri in 2:
		var yy := y + (0.5 - ri) * width
		var m := _measure(s, yy, 0.012)
		for si in segs + 1:
			var ang := TAU * si / segs
			var rx: float = float(m["rx"]) + out
			var rz: float = float(m["rz"]) + out
			var p := Vector3(sin(ang) * rx, yy, float(m["cz"]) + cos(ang) * rz)
			_vert(s, o, p, Vector3(sin(ang), 0, cos(ang)), Vector2(float(si) / segs * 6.0, ri * 0.2), {"pelvis": 0.6, "spine_01": 0.4}, part, col)
	for si in segs:
		var a := base + si
		var b := a + segs + 1
		o["i"].append_array([a, a + 1, b, a + 1, b + 1, b])

static func _commit(s: Dictionary, o: Dictionary) -> ArrayMesh:
	var m := ArrayMesh.new()
	if o["i"].is_empty():
		return m
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = o["v"]
	a[Mesh.ARRAY_NORMAL] = o["n"]
	a[Mesh.ARRAY_TEX_UV] = o["uv"]
	a[Mesh.ARRAY_BONES] = o["b"]
	a[Mesh.ARRAY_WEIGHTS] = o["w"]
	a[Mesh.ARRAY_CUSTOM0] = o["c"]
	a[Mesh.ARRAY_CUSTOM1] = o["rn"]
	a[Mesh.ARRAY_COLOR] = o["col"]
	a[Mesh.ARRAY_INDEX] = o["i"]
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	if int(s["per"]) == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
	return m

# --- Clothes ------------------------------------------------------------------------------------

## What someone wears, from their era, job and body (the same choices the body shader
## paints underneath). Returns a spec for clothes().
static func spec_for(b: Dictionary, era: int, job: String) -> Dictionary:
	var fem: bool = b["female"]
	var sp := {"sleeves": 2, "hem": 0.0, "tunic": false, "cape": false, "belt": true, "vest": false, "boot_h": 0.38}
	match era:
		Eras.MEDIEVAL:
			sp["sleeves"] = 1 if job in ["farmer", "smith", "miller", "hunter"] else 2
			if fem or job == "priest":
				sp["hem"] = 0.12
			elif job not in ["smith"]:
				sp["tunic"] = true
			sp["cape"] = job in ["guard", "priest"]
		Eras.FANTASY:
			sp["boot_h"] = 0.2
			sp["hem"] = 0.45 if job in ["mystic", "scribe", "runecarver", "herbalist"] else 0.0
			if fem:
				sp["hem"] = maxf(sp["hem"], 0.3)
			elif sp["hem"] == 0.0:
				sp["tunic"] = true
			sp["cape"] = job in ["warden", "mystic", "bard"]
		Eras.SCIFI:
			sp["vest"] = true
			sp["belt"] = job not in ["pilot"]
	return sp

## A whole outfit as one skinned mesh for the cloth shader.
static func clothes(fem: bool, body: ArrayMesh, skin: Skin, sk: Skeleton3D, sp: Dictionary) -> ArrayMesh:
	var key := "cl_%s_%s" % [fem, JSON.stringify(sp)]
	if _cache.has(key):
		return _cache[key]
	var s := _src(fem, body, skin, sk)
	var o := _new_out()
	var waist: float = s["waist"]
	var sleeves: int = sp["sleeves"]
	var boot_h: float = sp["boot_h"]
	var shoulder_x: float = s["shoulder_x"]
	# Shirt: the torso down to the hips, sleeves to the elbow or the wrist with a cuff.
	_shell(s, o, PART_SHIRT, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if r == 1:
			return 0.009
		if r == 5 and p.y > waist - 0.06:
			return 0.009
		if r == 2 and sleeves >= 1:
			return 0.009 + (0.006 if sleeves == 1 and absf(p.x) > shoulder_x + 0.2 else 0.0)
		if r == 3 and sleeves >= 2:
			return 0.009 + (0.006 if absf(p.x) > shoulder_x + 0.42 else 0.0)
		if r == 0 and p.y < s["neck"] + 0.02:
			return 0.006
		return -1.0)
	# Trousers down into the boots (under a robe, only what shows below its hem).
	var robe_hem: float = sp["hem"]
	_shell(s, o, PART_PANTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if robe_hem > 0.0 and p.y > robe_hem + 0.06:
			return -1.0
		if r == 5 and p.y <= waist - 0.03:
			return 0.007
		if r == 6 and p.y > boot_h - 0.03:
			return 0.007
		return -1.0)
	# Boots with a thicker turned-over top.
	_shell(s, o, PART_BOOTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if r == 7:
			return 0.013
		if r == 6 and p.y < boot_h:
			return 0.016 if p.y > boot_h - 0.03 else 0.013
		return -1.0)
	if sp["belt"]:
		var loose: bool = sp["hem"] > 0.0 or sp["tunic"]
		_belt(s, o, waist - 0.035, Color.WHITE, PART_BELT, 0.045, 0.04 if loose else 0.012)
	var hem: float = sp["hem"]
	if hem > 0.0:
		_skirt(s, o, waist - 0.02, hem, 0.6 if hem < 0.2 else 0.35, PART_SKIRT, Color.WHITE)
	elif sp["tunic"]:
		_skirt(s, o, waist - 0.02, float(s["crotch"]) - 0.16, 0.25, PART_SKIRT, Color.WHITE)
	if sp["cape"]:
		_cape(s, o, hem + 0.1 if hem > 0.0 else 0.35, Color.WHITE)
	if sp["vest"]:
		# Sci-fi: a padded utility vest over the jumpsuit.
		_shell(s, o, PART_TRIM, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if r == 1 and p.y > waist + 0.02 and p.y < s["shoulder_y"] - 0.02:
				return 0.018
			return -1.0)
	var m := _commit(s, o)
	_cache[key] = m
	return m

static func cloth_material() -> ShaderMaterial:
	if not _mats.has("cloth"):
		var m := ShaderMaterial.new()
		m.shader = load(CLOTH_SHADER)
		for k in ["linen", "wool", "velvet"]:
			m.set_shader_parameter(k, load("res://assets/textures/fabric_%s_detail.jpg" % k))
		m.set_shader_parameter("leather", load("res://assets/textures/leather_worn_detail.jpg"))
		m.set_shader_parameter("gold_trim", load("res://assets/textures/embroidered_trim_albedo.jpg"))
		_mats["cloth"] = m
	return _mats["cloth"]

static func armor_material() -> ShaderMaterial:
	if not _mats.has("armor"):
		var m := ShaderMaterial.new()
		m.shader = load(ARMOR_SHADER)
		m.set_shader_parameter("chainmail", load("res://assets/textures/chainmail_detail.jpg"))
		m.set_shader_parameter("leather", load("res://assets/textures/leather_worn_detail.jpg"))
		_mats["armor"] = m
	return _mats["armor"]

# --- Armour -------------------------------------------------------------------------------------

## How an armour item is drawn: {style, color, glow}.
static func look_of(item: Dictionary) -> Dictionary:
	var t: String = item.get("type", "")
	var d := ItemDB.def(t)
	var col: Color = d.get("color", Color(0.55, 0.55, 0.58))
	var style := STYLE_PLATE
	if t.contains("leather") or t.contains("elven") and t.contains("boots"):
		style = STYLE_LEATHER
	elif t.contains("mail"):
		style = STYLE_MAIL
	elif t.contains("mythril") or t.contains("elven") or t.contains("crystal") or t.contains("rune"):
		style = STYLE_CRYSTAL
	elif t.contains("exo") or t.contains("mag_") or t.contains("power") or t.contains("visor") or t.contains("emitter"):
		style = STYLE_EXO
	elif d.get("era", 0) == Eras.SCIFI:
		style = STYLE_EXO
	return {"style": style, "color": col}

## One armour piece for a slot, as shells and bands added to `o`.
static func _piece(s: Dictionary, o: Dictionary, slot: String, style: int, col: Color) -> void:
	var c := Color(col.r, col.g, col.b, float(style) / 8.0)
	var waist: float = s["waist"]
	var sx: float = s["shoulder_x"]
	var head: Vector3 = s["head"]
	var thick := 0.022 if style != STYLE_LEATHER else 0.014
	match slot:
		"chest":
			_shell(s, o, 1, c, func(_i, p: Vector3, r: int) -> float:
				if r == 1 and p.y > waist - 0.02:
					return thick + (0.01 if p.z > 0.0 and style != STYLE_MAIL else 0.0)
				if r == 2 and absf(p.x) < sx + 0.13:
					return thick + 0.016 # pauldrons
				if style == STYLE_MAIL and r == 5 and p.y > s["crotch"] - 0.1:
					return 0.015 # the hauberk's skirt
				if style == STYLE_MAIL and r == 2:
					return 0.012
				return -1.0)
			if style != STYLE_MAIL:
				_belt(s, o, waist - 0.01, c.darkened(0.2), 1, 0.05, thick + 0.012)
		"legs":
			_shell(s, o, 2, c, func(_i, p: Vector3, r: int) -> float:
				if r == 5 and p.y < waist - 0.08:
					return thick * 0.8 + (0.006 if p.z > -0.03 else 0.0)
				if r == 6 and p.y > 0.3:
					return thick * 0.8 + (0.008 if p.z > -0.03 else 0.0)
				return -1.0)
		"feet":
			_shell(s, o, 3, c, func(_i, p: Vector3, r: int) -> float:
				if r == 7:
					return thick
				if r == 6 and p.y < 0.42:
					return thick + (0.008 if p.y > 0.38 else 0.0)
				return -1.0)
		"hands":
			_shell(s, o, 4, c, func(_i, p: Vector3, r: int) -> float:
				if r == 4:
					return 0.007 if style != STYLE_EXO else 0.011
				if r == 3 and absf(p.x) > sx + 0.32:
					return thick * 0.8
				return -1.0)
		"head":
			var face_open := style != STYLE_EXO
			_shell(s, o, 5, c, func(_i, p: Vector3, r: int) -> float:
				if r != 0 or p.y < s["neck"] + 0.03:
					return -1.0
				var face := p.z > head.z + 0.035 and p.y < head.y + 0.115
				if face and face_open:
					return -1.0
				return thick + 0.006 + (0.01 if p.y > head.y + 0.12 else 0.0))

static func armour(fem: bool, body: ArrayMesh, skin: Skin, sk: Skeleton3D, worn: Dictionary) -> ArrayMesh:
	var s := _src(fem, body, skin, sk)
	var parts: Array = []
	for slot in ["chest", "legs", "feet", "hands", "head"]:
		if worn.has(slot) and worn[slot] is Dictionary:
			var lk := look_of(worn[slot])
			parts.append([slot, lk["style"], lk["color"]])
	var key := "ar_%s_%s" % [fem, str(parts)]
	if _cache.has(key):
		return _cache[key]
	var o := _new_out()
	for p in parts:
		_piece(s, o, p[0], p[1], p[2])
	var m := _commit(s, o)
	_cache[key] = m
	return m
