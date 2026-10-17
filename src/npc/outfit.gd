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

enum {PART_SHIRT = 1, PART_PANTS, PART_BOOTS, PART_BELT, PART_SKIRT, PART_CAPE, PART_TRIM, PART_APRON}
## What a garment is made of: the cloth shader reads it from the alpha of that part's colour
## (fabric / 8), so one mesh serves people in different cloths.
enum {FAB_LINEN, FAB_WOOL, FAB_VELVET, FAB_LEATHER, FAB_QUILT, FAB_CANVAS}
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
	var thigh_l: Vector3 = bone_y.call("thigh_l")
	var s := {
		"v": verts, "n": a[Mesh.ARRAY_NORMAL], "uv": a[Mesh.ARRAY_TEX_UV], "b": bones, "w": a[Mesh.ARRAY_WEIGHTS],
		"r": region, "i": idx, "per": bones.size() / verts.size(), "binds": binds,
		"waist": lerpf(pelvis.y, spine1.y, 0.55), "crotch": pelvis.y - 0.09, "knee": calf.y,
		"neck": neck.y, "head": head, "shoulder_x": absf(shoulder.x), "shoulder_y": shoulder.y,
		"lx": 1.0 if thigh_l.x >= 0.0 else -1.0,
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
				var dir := nr[k]
				if part == PART_BOOTS and reg[k] == 7:
					# A boot is pushed out from the middle of the foot as well as along the
					# skin, so it closes over the toes instead of showing each one.
					var mid := Vector3(signf(v[k].x) * 0.11, 0.05, 0.0)
					dir = (nr[k] + (v[k] - mid).normalized() * 1.2).normalized()
				var rp := v[k] + dir * off[k]
				o["v"].append(rp)
				o["n"].append(dir)
				o["uv"].append(uv[k] if uv.size() > k else Vector2.ZERO)
				for j in per:
					o["b"].append(bones[k * per + j])
					o["w"].append(wts[k * per + j])
				o["c"].append_array([float(part), rp.y, rp.z, rp.x])
				o["rn"].append_array([nr[k].x, nr[k].y, nr[k].z])
				o["col"].append(col)
			o["i"].append(remap[k])

## Appends one vertex with explicit skinning: wb = {bind name: weight}. Only the heaviest
## `per` bones are kept (renormalised), so a blend over many bones still skins right.
static func _vert(s: Dictionary, o: Dictionary, p: Vector3, n: Vector3, uv: Vector2, wb: Dictionary, part: int, col: Color) -> void:
	var per: int = s["per"]
	o["v"].append(p)
	o["n"].append(n.normalized())
	o["uv"].append(uv)
	var names: Array = []
	for k in wb:
		if float(wb[k]) > 0.001 and s["binds"].has(k):
			names.append(k)
	names.sort_custom(func(x, y) -> bool: return float(wb[x]) > float(wb[y]))
	names.resize(mini(names.size(), per))
	var total := 0.0
	for k in names:
		total += float(wb[k])
	for j in per:
		if j < names.size():
			o["b"].append(int(s["binds"][names[j]]))
			o["w"].append(float(wb[names[j]]) / maxf(total, 1e-5))
		else:
			o["b"].append(0)
			o["w"].append(0.0)
	o["c"].append_array([float(part), p.y, p.z, p.x])
	var rn := n.normalized()
	o["rn"].append_array([rn.x, rn.y, rn.z])
	o["col"].append(col)

## How cloth hanging below the waist at `p` follows the body: carried by the hips near the
## waist, then by the thigh on its own side (the calf too, below the knee), so a stride or
## a seat takes the cloth over that leg along with it instead of the leg passing through.
## Only a narrow strip down the middle blends the two legs.
static func _leg_weights(s: Dictionary, p: Vector3, top: float) -> Dictionary:
	var legs := smoothstep(0.0, top - float(s["crotch"]) + 0.03, top - p.y)
	var side := smoothstep(-0.05, 0.05, p.x * float(s["lx"]))
	var calf := clampf((float(s["knee"]) + 0.04 - p.y) / 0.3, 0.0, 1.0) * 0.7
	return {"pelvis": 1.0 - legs,
		"thigh_l": legs * side * (1.0 - calf), "calf_l": legs * side * calf,
		"thigh_r": legs * (1.0 - side) * (1.0 - calf), "calf_r": legs * (1.0 - side) * calf}

## How far a skirt hanging from `top` stands off the body at height y, as {cz, rx, rz}:
## it falls from the widest point of the hips (never tucks in under them) and widens by
## `flare` per metre below the waist. `extra` lays one garment over another.
static func _hang(s: Dictionary, top: float, hem: float, flare: float, extra: float) -> Array:
	var rings := maxi(2, int((top - hem) / 0.045) + 1)
	var out: Array = []
	var rx := 0.0
	var rz := 0.0
	var front := -INF
	var back := INF
	for ri in rings + 1:
		var y := lerpf(top, hem, float(ri) / rings)
		var m := _measure(s, y)
		rx = maxf(rx, float(m["rx"]) * 1.03 + 0.016)
		front = maxf(front, float(m["cz"]) + float(m["rz"]) * 1.06 + 0.018)
		back = minf(back, float(m["back"]) - 0.02)
		rz = maxf(rz, (front - back) * 0.5)
		var drop := top - y
		# More room over the hip joints, where the thighs turn under cloth still held by the hips.
		var hips := 0.016 * smoothstep(0.0, 0.06, drop) * (1.0 - smoothstep(top - float(s["crotch"]), top - float(s["crotch"]) + 0.12, drop))
		out.append({"y": y, "cz": front - rz, "rx": rx + flare * drop + extra + hips, "rz": rz + flare * 0.8 * drop + extra + hips})
	return out

## A loose skirt, robe, tunic hem or apron from `top` down to `hem` (rest heights). `arc`
## is how much of the way round it goes, centred on the front (1 = all the way), or on the
## back for an open coat (`behind`).
static func _skirt(s: Dictionary, o: Dictionary, top: float, hem: float, flare: float, part: int, col: Color, arc := 1.0, extra := 0.0, ring_top := -1.0, behind := false) -> void:
	var segs := 28 if arc >= 1.0 else maxi(6, int(28 * arc))
	var hang := _hang(s, ring_top if ring_top > 0.0 else top, hem, flare, extra)
	var base: int = o["v"].size()
	var rows := 0
	for h in hang:
		var y: float = h["y"]
		if y > top + 0.001:
			continue
		var k := clampf((top - y) / maxf(top - hem, 0.01), 0.0, 1.0)
		var rx: float = h["rx"]
		var rz: float = h["rz"]
		for si in segs + 1:
			var ang := lerpf(-PI * arc, PI * arc, float(si) / segs) + (PI if behind else 0.0)
			var p := Vector3(sin(ang) * rx, y, float(h["cz"]) + cos(ang) * rz)
			_vert(s, o, p, Vector3(sin(ang) / rx, 0.12 * k, cos(ang) / rz), Vector2(float(si) / segs * 3.0 * arc, k * 2.0), _leg_weights(s, p, top), part, col)
		rows += 1
	for ri in rows - 1:
		for si in segs:
			var a := base + ri * (segs + 1) + si
			var b := a + segs + 1
			o["i"].append_array([a, b, a + 1, a + 1, b, b + 1])

## A cape from the shoulders to `hem`, hanging clear of the back and the legs.
static func _cape(s: Dictionary, o: Dictionary, hem: float, col: Color) -> void:
	var top: float = s["shoulder_y"] + 0.02
	var waist: float = s["waist"]
	var cols := 11
	var rows := maxi(3, int((top - hem) / 0.06))
	var base: int = o["v"].size()
	var zback := INF
	for ri in rows + 1:
		var k := float(ri) / rows
		var y := lerpf(top, hem, k)
		var m := _measure(s, y, 0.03)
		zback = minf(zback, float(m["back"]) - 0.05)
		var half: float = lerpf(float(s["shoulder_x"]) * 1.0, float(s["shoulder_x"]) * 1.45, k)
		for ci in cols + 1:
			var u2 := float(ci) / cols
			var x := lerpf(-half, half, u2)
			var curve := (1.0 - pow(2.0 * u2 - 1.0, 2.0)) * 0.035
			var p := Vector3(x, y, zback - curve - 0.03 * k)
			var wb := {}
			if y > waist:
				var u := clampf((y - waist) / (top - waist), 0.0, 1.0)
				wb = {"spine_03": u, "spine_01": 1.0 - u}
			else:
				wb = _leg_weights(s, p, waist)
			_vert(s, o, p, Vector3(0, 0.05, -1), Vector2(u2 * 2.0, k * 3.0), wb, PART_CAPE, col)
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

## Dyes people could get: undyed linen and wool, earth colours, plant dyes, and the costly
## deep colours only the well-off wear. Every pick is shifted a little (wardrobe()), so no
## two people wear quite the same shade.
const UNDYED := [Color(0.8, 0.75, 0.64), Color(0.7, 0.65, 0.54), Color(0.6, 0.55, 0.46), Color(0.86, 0.83, 0.76)]
const EARTH := [Color(0.45, 0.29, 0.19), Color(0.36, 0.26, 0.18), Color(0.55, 0.47, 0.34), Color(0.64, 0.51, 0.29),
	Color(0.38, 0.41, 0.25), Color(0.45, 0.44, 0.28), Color(0.46, 0.45, 0.42), Color(0.33, 0.35, 0.37), Color(0.23, 0.22, 0.21)]
const DYED := [Color(0.58, 0.22, 0.16), Color(0.66, 0.4, 0.36), Color(0.27, 0.36, 0.52), Color(0.46, 0.55, 0.64),
	Color(0.73, 0.63, 0.32), Color(0.27, 0.42, 0.27), Color(0.5, 0.56, 0.42), Color(0.42, 0.24, 0.32), Color(0.62, 0.37, 0.2), Color(0.24, 0.4, 0.42)]
const RICH := [Color(0.5, 0.09, 0.12), Color(0.15, 0.19, 0.42), Color(0.13, 0.29, 0.17), Color(0.32, 0.17, 0.4), Color(0.1, 0.1, 0.11), Color(0.37, 0.11, 0.15)]
const CLERIC := [Color(0.1, 0.1, 0.11), Color(0.29, 0.24, 0.2), Color(0.5, 0.5, 0.48), Color(0.84, 0.83, 0.79)]
const HIDE := [Color(0.38, 0.25, 0.15), Color(0.29, 0.19, 0.12), Color(0.46, 0.33, 0.2), Color(0.21, 0.16, 0.12)]
const BOOTS := [Color(0.3, 0.2, 0.13), Color(0.24, 0.17, 0.11), Color(0.18, 0.13, 0.1), Color(0.34, 0.23, 0.14), Color(0.14, 0.12, 0.11)]
## Hose and trousers: dull, dark wool.
const LEGWEAR := [Color(0.36, 0.26, 0.18), Color(0.3, 0.24, 0.18), Color(0.46, 0.4, 0.3), Color(0.32, 0.34, 0.24),
	Color(0.38, 0.37, 0.34), Color(0.27, 0.28, 0.3), Color(0.2, 0.19, 0.18), Color(0.3, 0.3, 0.36)]
const FOREST := [Color(0.3, 0.36, 0.22), Color(0.38, 0.41, 0.25), Color(0.36, 0.28, 0.18), Color(0.45, 0.44, 0.3), Color(0.22, 0.3, 0.22)]
const FAIR := [Color(0.2, 0.42, 0.38), Color(0.35, 0.25, 0.5), Color(0.55, 0.6, 0.35), Color(0.15, 0.3, 0.45), Color(0.6, 0.45, 0.6), Color(0.66, 0.55, 0.3)]
const UTILITY := [Color(0.26, 0.28, 0.31), Color(0.2, 0.25, 0.34), Color(0.36, 0.38, 0.3), Color(0.5, 0.46, 0.38), Color(0.45, 0.46, 0.48), Color(0.17, 0.18, 0.2)]
const HIVIS := [Color(0.82, 0.43, 0.12), Color(0.85, 0.7, 0.15), Color(0.7, 0.22, 0.14)]
const MEDIC := [Color(0.86, 0.87, 0.88), Color(0.3, 0.55, 0.58), Color(0.62, 0.74, 0.8)]

## Which wardrobe a job dresses from, in any era.
const ROLE := {
	"farmer": "worker", "miller": "worker", "beekeeper": "worker", "hydroponics tech": "worker", "herbalist": "worker",
	"smith": "smith", "runecarver": "smith", "engineer": "smith",
	"guard": "guard", "warden": "guard", "security officer": "guard",
	"innkeeper": "host", "hunter": "hunter", "scavenger": "hunter",
	"priest": "cleric", "mystic": "cleric", "scribe": "cleric", "medic": "medic",
	"weaver": "artisan", "bard": "artisan", "lamplighter": "civil",
	"trader": "merchant", "data broker": "merchant", "pilot": "pilot", "courier": "pilot",
	# Shopkeepers and guild masters (TownShops).
	"armourer": "smith", "weaponsmith": "smith", "bladewright": "smith", "armorer": "smith", "armour tech": "smith", "wardweaver": "artisan",
	"apothecary": "host", "alchemist": "cleric", "shopkeeper": "host", "provisioner": "host", "quartermaster": "merchant",
	"meadwarden": "host", "bartender": "host", "steward": "merchant", "grove elder": "cleric", "registry clerk": "civil",
	"guildmaster": "guard", "archmage": "cleric", "fence": "hunter", "guild factor": "merchant", "ranger captain": "hunter",
	"archdruid": "cleric", "contract broker": "merchant", "chief engineer": "smith", "flight master": "pilot",
	"bandit": "hunter", "pirate": "hunter",
	# Boat crews.
	"captain": "merchant", "skipper": "merchant", "sailor": "worker", "deckhand": "worker", "fisher": "worker",
	"fisherman": "worker", "castaway": "hunter", "researcher": "civil", "scientist": "civil", "crew": "worker",
}

## A stable number for one person, from their saved looks (rounded, so a save and load
## never turns it into someone else).
static func _seed(b: Dictionary, job: String) -> int:
	var parts: Array = [job, bool(b.get("female", false)), int(b.get("hair_style", 0))]
	for k in ["height", "build"]:
		parts.append(snappedf(float(b.get(k, 1.0)), 0.001))
	for k in ["skin", "hair", "cloth", "cloth2"]:
		var c: Color = b.get(k, Color.GRAY)
		parts.append_array([snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)])
	return hash(str(parts))

## What someone wears, from their era, job and body: {spec: the cut (clothes()), cols:
## {part: colour with alpha = fabric / 8}, knit, trim}. Deterministic per person. Dresses,
## tunics, aprons, bodices, jerkins and capes follow the role and the person's sex, and
## the colours come from dyes that fit the role, each shade nudged a little.
static func wardrobe(b: Dictionary, era: int, job: String) -> Dictionary:
	var fem: bool = b.get("female", false)
	var r := RandomNumberGenerator.new()
	r.seed = _seed(b, job)
	var pick := func(pal: Array) -> Color:
		var c: Color = pal[r.randi() % pal.size()]
		var h := fposmod(c.h + r.randf_range(-0.02, 0.02), 1.0)
		return Color.from_hsv(h, clampf(c.s * r.randf_range(0.82, 1.12), 0.0, 1.0), clampf(c.v * r.randf_range(0.86, 1.1), 0.03, 0.95))
	var fab := func(c: Color, f: int) -> Color:
		return Color(c.r, c.g, c.b, float(f) / 8.0)
	var chance := func(p: float) -> bool:
		return r.randf() < p
	var sp := {"sleeves": 2, "hem": 0.0, "flare": 0.0, "vest": 0, "apron": 0.0, "bib": false, "cape": 0.0, "belt": true, "boot_h": 0.38}
	var role: String = ROLE.get(job, "civil")
	var cols := {}
	var trim := false
	var knit := false
	if job == "":
		# The player: practical travelling clothes in their chosen colours.
		cols[PART_SHIRT] = fab.call(b.get("cloth", Color(0.5, 0.4, 0.3)), FAB_LINEN)
		cols[PART_PANTS] = fab.call(b.get("cloth2", Color(0.3, 0.28, 0.25)), FAB_WOOL)
		sp["vest"] = 1
		cols[PART_TRIM] = fab.call(pick.call(HIDE), FAB_LEATHER)
	elif era == Eras.SCIFI:
		_scifi(sp, cols, role, fem, pick, fab, chance)
	else:
		var fairy := era == Eras.FANTASY
		var everyday: Array = FAIR + EARTH if fairy else DYED + EARTH
		var shirt: Color = pick.call(UNDYED) if chance.call(0.7) else pick.call(everyday)
		var pants: Color = pick.call(LEGWEAR)
		var top: Color = pick.call(everyday)
		var pal_top := everyday
		match role:
			"worker":
				pal_top = EARTH + UNDYED + (FAIR if fairy else DYED.slice(0, 6))
				if job == "miller":
					pal_top = UNDYED
			"smith":
				pal_top = EARTH
			"host":
				pal_top = everyday
			"hunter":
				pal_top = FOREST
			"cleric":
				pal_top = CLERIC if not fairy else FAIR + CLERIC
			"artisan":
				pal_top = (FAIR if fairy else DYED) + RICH.slice(0, 3)
			"merchant":
				pal_top = RICH + (FAIR if fairy else DYED)
		top = pick.call(pal_top)
		var dress := (fem and role not in ["guard", "hunter", "smith"]) or role == "cleric"
		if fem and role in ["hunter", "smith"] and chance.call(0.3):
			dress = true
		var rolled: bool = role in ["worker", "smith"] and chance.call(0.6)
		sp["sleeves"] = 1 if rolled or (role == "host" and chance.call(0.4)) else 2
		knit = role in ["worker", "hunter"] and chance.call(0.5)
		var wool := FAB_WOOL if knit else FAB_LINEN
		if role == "guard":
			# A padded gambeson (armour goes over it) with a short quilted skirt.
			var gam: Color = pick.call(UNDYED + EARTH.slice(0, 4))
			cols[PART_SHIRT] = fab.call(gam, FAB_QUILT)
			sp["vest"] = 3
			cols[PART_TRIM] = fab.call(gam, FAB_QUILT)
			sp["hem"] = 0.72
			sp["flare"] = 0.08
			cols[PART_SKIRT] = fab.call(gam, FAB_QUILT)
			if chance.call(0.45):
				sp["cape"] = 0.5
				cols[PART_CAPE] = fab.call(pick.call([Color(0.27, 0.36, 0.52), Color(0.5, 0.12, 0.12)] if not fairy else FOREST), FAB_WOOL)
		elif dress:
			# A kirtle: long skirt and bodice over a linen shift, or one dress all of a colour.
			var robe := role == "cleric"
			sp["hem"] = 0.1 if robe else ([0.1, 0.14, 0.2, 0.26][r.randi() % 4] if role in ["worker", "host", "smith", "hunter"] else [0.1, 0.12, 0.16][r.randi() % 3])
			sp["flare"] = 0.05 if robe else [0.06, 0.09, 0.12][r.randi() % 3]
			var skirt_fab: int = FAB_WOOL if robe or chance.call(0.5) else FAB_LINEN
			trim = (robe and chance.call(0.3)) or (role == "merchant" and chance.call(0.4))
			if trim:
				skirt_fab = FAB_VELVET
			cols[PART_SKIRT] = fab.call(top, skirt_fab)
			if robe or chance.call(0.45):
				cols[PART_SHIRT] = fab.call(top, skirt_fab if skirt_fab != FAB_VELVET else FAB_WOOL)
			else:
				cols[PART_SHIRT] = fab.call(shirt, FAB_LINEN)
				sp["vest"] = 1
				var bodice: Color = top if chance.call(0.6) else pick.call(pal_top)
				cols[PART_TRIM] = fab.call(bodice, FAB_VELVET if trim else FAB_WOOL)
			if robe:
				sp["belt"] = chance.call(0.7)
				sp["boot_h"] = 0.24
				if chance.call(0.4):
					sp["cape"] = 0.3
					cols[PART_CAPE] = fab.call(top if chance.call(0.5) else pick.call(CLERIC), FAB_VELVET if trim else FAB_WOOL)
			elif fem:
				sp["boot_h"] = [0.26, 0.32][r.randi() % 2]
		else:
			# Men's tunic over hose, or a shirt and trousers with a jerkin.
			if role != "smith" and chance.call(0.6 if role in ["artisan", "merchant", "worker"] else 0.45):
				var tunic: Color = top
				cols[PART_SHIRT] = fab.call(tunic, wool)
				sp["hem"] = [0.6, 0.66, 0.74][r.randi() % 3]
				sp["flare"] = 0.1
				cols[PART_SKIRT] = fab.call(tunic, FAB_WOOL if knit or chance.call(0.5) else FAB_LINEN)
				if role in ["artisan", "merchant"]:
					pants = pick.call(LEGWEAR + (FAIR if fairy else DYED).slice(0, 4)).darkened(0.15)
			else:
				cols[PART_SHIRT] = fab.call(shirt, wool)
				if role != "smith" and chance.call(0.65):
					sp["vest"] = 1
					var leather: bool = role == "hunter" or chance.call(0.5)
					cols[PART_TRIM] = fab.call(pick.call(HIDE) if leather else top, FAB_LEATHER if leather else (FAB_VELVET if role == "merchant" else FAB_WOOL))
		cols[PART_PANTS] = fab.call(pants, FAB_WOOL)
		# Aprons: leather for the forge, linen for the kitchen, the mill and the field.
		if role == "smith":
			sp["apron"] = 0.42
			sp["bib"] = true
			cols[PART_APRON] = fab.call(pick.call(HIDE), FAB_LEATHER)
		elif role in ["host", "worker"] and (fem or role == "host" or job == "miller") and chance.call(0.65):
			sp["apron"] = maxf(float(sp["hem"]) + 0.16, 0.36) if sp["hem"] > 0.0 else 0.45
			sp["bib"] = chance.call(0.35)
			cols[PART_APRON] = fab.call(pick.call(UNDYED), FAB_LINEN)
		if role == "hunter" and chance.call(0.35):
			sp["cape"] = 0.7
			cols[PART_CAPE] = fab.call(pick.call(FOREST), FAB_WOOL)
		elif role in ["merchant", "artisan"] and not dress and chance.call(0.25):
			sp["cape"] = 0.45
			cols[PART_CAPE] = fab.call(pick.call(RICH), FAB_WOOL)
	# Nobody may look naked: a shirt or dress too near their own skin tone is dyed darker.
	var skin: Color = b.get("skin", Color(0.8, 0.6, 0.5))
	for part in [PART_SHIRT, PART_PANTS, PART_SKIRT, PART_TRIM]:
		if cols.has(part) and _near(cols[part], skin):
			var c: Color = cols[part]
			var d: Color = c.darkened(0.45) if skin.v > 0.45 else c.lerp(Color(0.25, 0.33, 0.45), 0.7)
			cols[part] = Color(d.r, d.g, d.b, c.a)
	for part in [PART_SKIRT, PART_TRIM, PART_APRON, PART_CAPE]:
		if not cols.has(part):
			cols[part] = cols.get(PART_SHIRT, Color(0.5, 0.4, 0.3, 0.0))
	cols[PART_BOOTS] = fab.call(pick.call(BOOTS) if era != Eras.SCIFI else pick.call([Color(0.14, 0.15, 0.17), Color(0.3, 0.24, 0.17)]), FAB_LEATHER)
	return {"spec": sp, "cols": cols, "knit": knit, "trim": trim}

## Whether cloth of colour `c` could pass for bare skin of tone `skin`.
static func _near(c: Color, skin: Color) -> bool:
	return Vector3(c.r - skin.r, c.g - skin.g, c.b - skin.b).length() < 0.16

## Human sci-fi folk: jumpsuits and work shirts, padded vests, a long coat for the dealers.
static func _scifi(sp: Dictionary, cols: Dictionary, role: String, fem: bool, pick: Callable, fab: Callable, chance: Callable) -> void:
	sp["boot_h"] = 0.4
	sp["fit"] = 2.0
	var main: Color = pick.call(UTILITY)
	match role:
		"medic":
			main = pick.call(MEDIC)
		"pilot":
			main = pick.call([Color(0.36, 0.38, 0.3), Color(0.2, 0.25, 0.34), Color(0.5, 0.46, 0.38)])
		"merchant":
			main = pick.call(RICH)
	var suit: bool = chance.call(0.5) or role == "pilot"
	cols[PART_SHIRT] = fab.call(main if suit else pick.call(UTILITY + MEDIC.slice(0, 1)), FAB_CANVAS)
	cols[PART_PANTS] = fab.call(main if suit else pick.call(UTILITY), FAB_CANVAS)
	sp["sleeves"] = 1 if role in ["smith", "worker"] and chance.call(0.5) else 2
	sp["belt"] = role != "pilot"
	if role in ["smith", "guard", "hunter", "worker"] or chance.call(0.4):
		sp["vest"] = 2
		var v: Color = pick.call(HIVIS) if role == "smith" or (role == "pilot" and chance.call(0.5)) else pick.call(UTILITY)
		cols[PART_TRIM] = fab.call(v, FAB_QUILT)
	if role == "merchant" or (role == "civil" and chance.call(0.3)):
		# A long coat, open over the legs.
		sp["hem"] = 0.5
		sp["flare"] = 0.08
		sp["open"] = true
		cols[PART_SKIRT] = fab.call(main.darkened(0.15), FAB_CANVAS)
		cols[PART_SHIRT] = fab.call(main.darkened(0.15), FAB_CANVAS)
	if role == "worker" and chance.call(0.5):
		sp["apron"] = 0.45
		cols[PART_APRON] = fab.call(pick.call([Color(0.3, 0.45, 0.3), Color(0.45, 0.46, 0.48)]), FAB_CANVAS)

## A whole outfit as one skinned mesh for the cloth shader (sp: wardrobe()["spec"]).
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
	var hem: float = sp["hem"]
	# Work clothes (sci-fi) are cut roomier than linen and wool, with pockets.
	var fit: float = sp.get("fit", 1.0)
	var vest_kind: int = sp["vest"]
	var t_shirt := 0.009 * fit
	var t_pants := 0.007 * fit * fit # work trousers hang loose round the legs
	# Shirt: the torso down to the hips, sleeves to the elbow or the wrist with a cuff.
	_shell(s, o, PART_SHIRT, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if r == 1:
			return t_shirt
		if r == 5 and p.y > waist - 0.06:
			return t_shirt
		if r == 2 and sleeves >= 1:
			return t_shirt + (0.006 if sleeves == 1 and absf(p.x) > shoulder_x + 0.2 else 0.0)
		if r == 3 and sleeves >= 2:
			return t_shirt + (0.006 if absf(p.x) > shoulder_x + 0.42 else 0.0)
		if r == 0 and p.y < s["neck"] + 0.02:
			return 0.006
		return -1.0)
	# Trousers down into the boots; under a long skirt, hose on the shins (a lifted hem).
	_shell(s, o, PART_PANTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if hem > 0.0 and hem < 0.45 and p.y > float(s["knee"]) - 0.06:
			return -1.0 # under a long skirt, hose only on the shins
		if r == 5 and p.y <= waist - 0.03:
			return t_pants
		if r == 6 and p.y > boot_h - 0.03:
			return t_pants
		return -1.0)
	if fit > 1.0:
		# A stand-up jacket collar.
		var neck_y: float = float(s["neck"]) - 0.035
		var nb: int = o["v"].size()
		for ri in 2:
			var yy := neck_y + ri * 0.045
			var m := _measure(s, neck_y - 0.02, 0.02)
			var rr := maxf(float(m["rx"]) * 0.42, 0.065) + t_shirt + 0.008 - ri * 0.004
			for si in 25:
				var ang := TAU * si / 24
				var p := Vector3(sin(ang) * rr, yy, float(m["cz"]) - 0.01 + cos(ang) * rr * 0.95)
				_vert(s, o, p, Vector3(sin(ang), 0, cos(ang)), Vector2(float(si) / 24.0 * 4.0, ri * 0.2), {"spine_03": 1.0 - ri * 0.5, "neck_01": ri * 0.5}, PART_SHIRT, Color.WHITE)
		for si in 24:
			o["i"].append_array([nb + si, nb + si + 1, nb + 25 + si, nb + si + 1, nb + 26 + si, nb + 25 + si])
		# Cargo pockets on the outside of each thigh and two on the chest.
		var knee: float = s["knee"]
		var crotch: float = s["crotch"]
		_shell(s, o, PART_PANTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if r == 5 and p.y > knee + 0.1 and p.y < crotch - 0.06 and absf(p.x) > 0.13 and absf(p.z + 0.03) < 0.06:
				return t_pants + 0.012
			return -1.0)
		_shell(s, o, PART_TRIM if vest_kind > 0 else PART_SHIRT, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if r == 1 and p.y > float(s["shoulder_y"]) - 0.2 and p.y < float(s["shoulder_y"]) - 0.09 and absf(p.x) > 0.04 and absf(p.x) < 0.13 and p.z > 0.0:
				return t_shirt + (0.03 if vest_kind > 0 else 0.01)
			return -1.0)
	# Boots (or low shoes) with a thicker turned-over top, and a roomy toe so they read
	# as boots rather than feet.
	_shell(s, o, PART_BOOTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if r == 7:
			return 0.016 + 0.01 * clampf(p.z / 0.1, 0.0, 1.0)
		if r == 6 and p.y < boot_h:
			return 0.016 if p.y > boot_h - 0.03 else 0.013
		return -1.0)
	var vest: int = vest_kind
	if vest > 0:
		# A bodice or jerkin (1), a padded sci-fi vest (2) or a gambeson (3) over the shirt.
		var vt := 0.016 if vest == 1 else 0.02
		var low := waist - (0.08 if vest == 3 else 0.02)
		_shell(s, o, PART_TRIM, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if (r == 1 or (r == 5 and vest == 3)) and p.y > low and p.y < (float(s["shoulder_y"]) - 0.04 if fem and vest == 1 else float(s["neck"])):
				return vt
			return -1.0)
	var top := waist - 0.02
	if hem > 0.0:
		if sp.get("open", false):
			_skirt(s, o, top, hem, sp["flare"], PART_SKIRT, Color.WHITE, 0.86, 0.0, -1.0, true)
		else:
			_skirt(s, o, top, hem, sp["flare"], PART_SKIRT, Color.WHITE)
	var apron: float = sp["apron"]
	if apron > 0.0:
		# Over the skirt it hangs from the same waist a little further out; over trousers
		# it falls from the hips like a skirt of its own.
		_skirt(s, o, top, apron, sp["flare"] if hem > 0.0 else 0.04, PART_APRON, Color.WHITE, 0.36, 0.012 if hem > 0.0 else 0.006)
		if sp["bib"]:
			# The bib: the front of the chest and belly, skinned like the shirt under it.
			var bib_top: float = float(s["shoulder_y"]) - 0.1
			_shell(s, o, PART_APRON, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
				if (r == 1 or r == 5) and p.y > waist - 0.05 and p.y < bib_top and p.z > -0.02 and absf(p.x) < 0.13:
					return 0.03 if vest > 0 else 0.02
				return -1.0)
	if sp["belt"]:
		var loose := hem > 0.0 or apron > 0.0 or vest == 3
		_belt(s, o, waist - 0.035, Color.WHITE, PART_BELT, 0.04 if fit <= 1.0 else 0.05, 0.034 if loose else maxf(0.014, maxf(t_pants, t_shirt) + 0.008))
	if sp["cape"] > 0.0:
		_cape(s, o, sp["cape"], Color.WHITE)
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
	var looks := {"cloth": STYLE_CLOTH, "leather": STYLE_LEATHER, "mail": STYLE_MAIL, "plate": STYLE_PLATE}
	if looks.has(String(d.get("look", ""))):
		style = looks[d["look"]]
	elif t.contains("leather") or t.contains("elven") and t.contains("boots"):
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
	var thick := 0.022 if style != STYLE_LEATHER and style != STYLE_CLOTH else 0.014
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
