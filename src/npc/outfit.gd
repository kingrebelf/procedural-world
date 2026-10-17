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
## `slack` smooths the shell that many times (cloth bridging the hollows between muscles
## and under the bust instead of painted on), never letting it come closer to the skin
## than `pick` asked for.
static func _shell(s: Dictionary, o: Dictionary, part: int, col: Color, pick: Callable, slack := 0, rim := 0.0) -> void:
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
	if slack > 0 and remap.size() > 0:
		_slacken(s, o, base, remap, off, slack, rim)

## Lets a shell hang loose: Laplacian smoothing over its surface (vertices split at UV seams
## move together), each pass pushed back out to at least its distance off the skin.
static func _slacken(s: Dictionary, o: Dictionary, base: int, remap: Dictionary, off: PackedFloat32Array, passes: int, rim := 0.0) -> void:
	var v: PackedVector3Array = s["v"]
	var nr: PackedVector3Array = s["n"]
	var n := remap.size()
	var src := PackedInt32Array()
	src.resize(n)
	for k in remap:
		src[int(remap[k]) - base] = k
	# Weld: one group per rest position.
	var group := PackedInt32Array()
	group.resize(n)
	var key_of := {}
	for i in n:
		var p := v[src[i]]
		var key := Vector3i(roundi(p.x * 20000.0), roundi(p.y * 20000.0), roundi(p.z * 20000.0))
		if not key_of.has(key):
			key_of[key] = key_of.size()
		group[i] = key_of[key]
	var g := key_of.size()
	var nbrs: Array = []
	nbrs.resize(g)
	for i in g:
		nbrs[i] = {}
	var tris: PackedInt32Array = o["i"]
	var edges := {}
	for t in range(0, tris.size(), 3):
		if tris[t] < base:
			continue
		for e in 3:
			var a := group[tris[t + e] - base]
			var b := group[tris[t + (e + 1) % 3] - base]
			if a != b:
				nbrs[a][b] = true
				nbrs[b][a] = true
				var ek := Vector2i(mini(a, b), maxi(a, b))
				edges[ek] = int(edges.get(ek, 0)) + 1
	# The cut edges (hems, cuffs, necklines) stay snug on the body, as if hemmed or tucked.
	var pinned := PackedByteArray()
	pinned.resize(g)
	var along: Array = [] # each cut-edge vertex's neighbours along the cut
	along.resize(g)
	for ek in edges:
		if int(edges[ek]) == 1:
			pinned[ek.x] = 1
			pinned[ek.y] = 1
			for e in [[ek.x, ek.y], [ek.y, ek.x]]:
				if along[e[0]] == null:
					along[e[0]] = []
				along[e[0]].append(e[1])
	var pos := PackedVector3Array()
	pos.resize(g)
	var rest := PackedVector3Array()
	rest.resize(g)
	var nrm := PackedVector3Array()
	nrm.resize(g)
	var dmin := PackedFloat32Array()
	dmin.resize(g)
	var ov: PackedVector3Array = o["v"]
	for i in n:
		pos[group[i]] = ov[base + i]
		rest[group[i]] = v[src[i]]
		nrm[group[i]] = nr[src[i]]
		dmin[group[i]] = off[src[i]]
	for it in passes:
		var nxt := pos.duplicate()
		for i in g:
			var ns: Dictionary = nbrs[i]
			var avg := Vector3.ZERO
			if pinned[i] == 1:
				# A cut edge is smoothed only along itself (a few passes), so the sawtooth of
				# whole triangles becomes a clean hem line without the hem riding up.
				var al = along[i]
				if it >= 30 or al == null or al.size() != 2:
					continue
				avg = (pos[al[0]] + pos[al[1]]) * 0.5
			elif ns.size() < 3:
				continue
			else:
				for j in ns:
					avg += pos[j]
				avg /= ns.size()
			var p := pos[i].lerp(avg, 0.55)
			var d := (p - rest[i]).dot(nrm[i])
			if d < dmin[i]:
				p += nrm[i] * (dmin[i] - d)
			nxt[i] = p
		pos = nxt
	# Shade the cloth by its own (smoothed) surface, not the body's: the body's normals
	# carry every sculpted muscle, which made shirts read as painted on.
	var fn := PackedVector3Array()
	fn.resize(g)
	for t in range(0, tris.size(), 3):
		if tris[t] < base:
			continue
		var a := group[tris[t] - base]
		var b := group[tris[t + 1] - base]
		var d := group[tris[t + 2] - base]
		var f := (pos[d] - pos[a]).cross(pos[b] - pos[a])
		fn[a] += f
		fn[b] += f
		fn[d] += f
	for i in g:
		fn[i] = fn[i].normalized() if fn[i].dot(nrm[i]) > 0.0 else (fn[i] * -1.0).normalized()
		if fn[i] == Vector3.ZERO:
			fn[i] = nrm[i]
	for it in 10:
		var nxt := fn.duplicate()
		for i in g:
			var sum := fn[i]
			for j in nbrs[i]:
				sum += fn[j]
			nxt[i] = sum.normalized()
		fn = nxt
	var c: PackedFloat32Array = o["c"]
	var on: PackedVector3Array = o["n"]
	var orn: PackedFloat32Array = o["rn"]
	for i in n:
		var p := pos[group[i]]
		ov[base + i] = p
		c[(base + i) * 4 + 1] = p.y
		c[(base + i) * 4 + 2] = p.z
		c[(base + i) * 4 + 3] = p.x
		var q := fn[group[i]]
		on[base + i] = q
		orn[(base + i) * 3] = q.x
		orn[(base + i) * 3 + 1] = q.y
		orn[(base + i) * 3 + 2] = q.z
	o["v"] = ov
	o["c"] = c
	o["n"] = on
	o["rn"] = orn
	if rim <= 0.0:
		return
	# The garment's thickness: a band turned in along every cut edge, so a jerkin or
	# bodice reads as leather or wool laid over the shirt rather than paint on it.
	var rep := PackedInt32Array()
	rep.resize(g)
	for i in n:
		rep[group[i]] = base + i
	var per: int = s["per"]
	var part := int(c[rep[0] * 4])
	var col: Color = o["col"][rep[0]]
	for ek in edges:
		if int(edges[ek]) != 1:
			continue
		var b0: int = o["v"].size()
		for gi in [ek.x, ek.y]:
			for depth in [0.0, rim]:
				var q: Vector3 = pos[gi] - fn[gi] * depth
				var src_i: int = rep[gi]
				o["v"].append(q)
				o["n"].append(fn[gi])
				o["uv"].append(o["uv"][src_i])
				for j in per:
					o["b"].append(o["b"][src_i * per + j])
					o["w"].append(o["w"][src_i * per + j])
				o["c"].append_array([float(part), q.y, q.z, q.x])
				o["rn"].append_array([fn[gi].x, fn[gi].y, fn[gi].z])
				o["col"].append(col)
		o["i"].append_array([b0, b0 + 2, b0 + 1, b0 + 1, b0 + 2, b0 + 3])

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
		# Snug at the waistband, easing out to clear the hips below it.
		var ease := lerpf(0.008, 0.016, smoothstep(0.0, 0.08, top - y))
		rx = maxf(rx, float(m["rx"]) * 1.03 + ease)
		front = maxf(front, float(m["cz"]) + float(m["rz"]) * 1.06 + ease + 0.002)
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
	var segs := 56 if arc >= 1.0 else maxi(8, int(56 * arc))
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
		# Gathered at the waist: soft pleats that open out toward the hem, so the cloth
		# reads as fabric falling in folds rather than a drum.
		var amp := lerpf(0.003, 0.016, sqrt(k))
		for si in segs + 1:
			var ang := lerpf(-PI * arc, PI * arc, float(si) / segs) + (PI if behind else 0.0)
			var pleat := 1.0 + amp * sin(ang * 14.0) / maxf(rx, 0.05)
			var p := Vector3(sin(ang) * rx * pleat, y, float(h["cz"]) + cos(ang) * rz * pleat)
			var n := Vector3(sin(ang) / rx, 0.12 * k, cos(ang) / rz).rotated(Vector3.UP, -atan(amp * 14.0 * cos(ang * 14.0) / maxf(rx, 0.05)))
			_vert(s, o, p, n, Vector2(float(si) / segs * 3.0 * arc, k * 2.0), _leg_weights(s, p, top), part, col)
		rows += 1
	for ri in rows - 1:
		for si in segs:
			var a := base + ri * (segs + 1) + si
			var b := a + segs + 1
			o["i"].append_array([a, b, a + 1, a + 1, b, b + 1])

## An apron's bib: a straight-sided panel laid over the front of the torso from `bottom`
## to the neck, `off` clear of the skin, with its edges turned in so it has thickness.
static func _bib(s: Dictionary, o: Dictionary, bottom: float, off: float, col: Color) -> void:
	var neck: float = s["neck"]
	var sy: float = s["shoulder_y"]
	var v: PackedVector3Array = s["v"]
	var reg: PackedInt32Array = s["r"]
	var cols := 8
	var rows := maxi(4, int((neck - bottom) / 0.035))
	var front := PackedVector3Array()
	for i in v.size():
		if (reg[i] == 1 or reg[i] == 5 or reg[i] == 0) and v[i].z > 0.0 and v[i].y > bottom - 0.03 and v[i].y < neck + 0.03 and absf(v[i].x) < 0.17:
			front.append(v[i])
	var grid: Array = []
	for ri in rows + 1:
		var y := lerpf(bottom, neck - 0.01, float(ri) / rows)
		var half := lerpf(0.13, 0.07, smoothstep(sy - 0.16, neck, y))
		var row: Array = []
		for ci in cols + 1:
			var x := lerpf(-half, half, float(ci) / cols)
			# The body's front at (x, y): the furthest-forward skin near that point.
			var z := -INF
			for q in front:
				if absf(q.x - x) < 0.035 and absf(q.y - y) < 0.035:
					z = maxf(z, q.z)
			row.append(Vector3(x, y, (z if z > -INF else 0.1) + off))
		grid.append(row)
	# Bridge the hollow under the chest: each column hangs no further back than the line
	# between the rows above and below it.
	for it in 4:
		for ri in range(1, rows):
			for ci in cols + 1:
				var p: Vector3 = grid[ri][ci]
				p.z = maxf(p.z, (grid[ri - 1][ci].z + grid[ri + 1][ci].z) * 0.5)
				grid[ri][ci] = p
	var base: int = o["v"].size()
	for ri in rows + 1:
		for ci in cols + 1:
			var p: Vector3 = grid[ri][ci]
			var u := clampf((p.y - float(s["waist"])) / (sy - float(s["waist"])), 0.0, 1.0)
			var wb := {"spine_03": u, "spine_02": 1.0 - absf(u - 0.5) * 2.0, "spine_01": 1.0 - u}
			_vert(s, o, p, Vector3(0, 0, 1), Vector2(float(ci) / cols, float(ri) / rows), wb, PART_APRON, col)
	for ri in rows:
		for ci in cols:
			var a := base + ri * (cols + 1) + ci
			var b := a + cols + 1
			o["i"].append_array([a, a + 1, b, a + 1, b + 1, b])
	# The turned edge down each side and along the top.
	var edge: Array = []
	for ri in rows + 1:
		edge.append([ri, 0])
	for ci in range(1, cols + 1):
		edge.append([rows, ci])
	for ri in range(rows - 1, -1, -1):
		edge.append([ri, cols])
	for e in edge.size() - 1:
		var b0: int = o["v"].size()
		for pr in [edge[e], edge[e + 1]]:
			var src: int = base + int(pr[0]) * (cols + 1) + int(pr[1])
			var p: Vector3 = o["v"][src]
			for d in [0.0, off - 0.008]:
				var q := p - Vector3(0, 0, d)
				o["v"].append(q)
				o["n"].append(Vector3(signf(p.x), 0, 0.2).normalized())
				o["uv"].append(o["uv"][src])
				var per: int = s["per"]
				for j in per:
					o["b"].append(o["b"][src * per + j])
					o["w"].append(o["w"][src * per + j])
				o["c"].append_array([float(PART_APRON), q.y, q.z, q.x])
				o["rn"].append_array([0.0, 0.0, 1.0])
				o["col"].append(col)
		o["i"].append_array([b0, b0 + 2, b0 + 1, b0 + 1, b0 + 2, b0 + 3])

## A cape from the shoulders to `hem`, hanging clear of the back and the legs.
static func _cape(s: Dictionary, o: Dictionary, hem: float, col: Color, clear := 0.0) -> void:
	var top: float = s["shoulder_y"] + 0.02
	var waist: float = s["waist"]
	var cols := 14
	var rows := maxi(3, int((top - hem) / 0.06))
	var base: int = o["v"].size()
	# It wraps the back as a curve (the upper back's own depth), draping a little fuller
	# toward the hem, instead of standing behind the body as a flat board.
	var chest := _measure(s, float(s["shoulder_y"]) - 0.12, 0.03)
	var cz: float = chest["cz"]
	var rz_back := INF
	for ri in rows + 1:
		var k := float(ri) / rows
		var y := lerpf(top, hem, k)
		var m := _measure(s, y, 0.03)
		rz_back = minf(rz_back, float(m["back"]))
		# Below the waist it also clears a tunic or skirt hanging under it.
		var depth := maxf(cz - rz_back, 0.1) + 0.035 + 0.05 * k + clear * smoothstep(waist + 0.05, waist - 0.1, y)
		var wide := float(s["shoulder_x"]) * lerpf(1.02, 1.35, k) + 0.02
		var arc := deg_to_rad(lerpf(88.0, 74.0, k))
		for ci in cols + 1:
			var u2 := float(ci) / cols
			var t := lerpf(-arc, arc, u2)
			# Soft vertical folds down the cape.
			var fold := sin(u2 * TAU * 3.0) * 0.012 * k
			var out := Vector3(sin(t) * wide, 0.0, -cos(t) * depth)
			var nrm := Vector3(sin(t) / wide, 0.0, -cos(t) / depth).normalized()
			var p := Vector3(out.x, y, cz + out.z) + nrm * fold
			var wb := {}
			if y > waist:
				var u := clampf((y - waist) / (top - waist), 0.0, 1.0)
				wb = {"spine_03": u, "spine_01": 1.0 - u}
			else:
				wb = _leg_weights(s, p, waist)
			_vert(s, o, p, nrm + Vector3(0, 0.05, 0), Vector2(u2 * 2.0, k * 3.0), wb, PART_CAPE, col)
	for ri in rows:
		for ci in cols:
			var a := base + ri * (cols + 1) + ci
			var b := a + cols + 1
			o["i"].append_array([a, a + 1, b, a + 1, b + 1, b])

## A leather pouch hanging off the belt on one side (side = +1 or -1 along x).
static func _pouch(s: Dictionary, o: Dictionary, y: float, side: float) -> void:
	var m := _measure(s, y, 0.015)
	var ang := deg_to_rad(55.0) * side
	var rx: float = float(m["rx"]) + 0.03
	var rz: float = float(m["rz"]) + 0.03
	var c := Vector3(sin(ang) * rx, y - 0.06, float(m["cz"]) + cos(ang) * rz)
	var out := Vector3(sin(ang), 0, cos(ang)).normalized()
	var across := Vector3.UP.cross(out).normalized()
	var half := Vector3(0.05, 0.055, 0.022) # across, up, out
	var wb := {"pelvis": 0.75, "thigh_l" if c.x * float(s["lx"]) > 0.0 else "thigh_r": 0.25}
	var faces := [[out, across, Vector3.UP], [-out, -across, Vector3.UP], [across, -out, Vector3.UP], [-across, out, Vector3.UP], [Vector3.UP, across, -out], [-Vector3.UP, across, out]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var nh := absf(n.dot(out)) * half.z + absf(n.dot(across)) * half.x + absf(n.y) * half.y
		var uh := absf(u.dot(out)) * half.z + absf(u.dot(across)) * half.x + absf(u.y) * half.y
		var wh := absf(w.dot(out)) * half.z + absf(w.dot(across)) * half.x + absf(w.y) * half.y
		var b: int = o["v"].size()
		for k in 4:
			var su := -1.0 if k == 0 or k == 3 else 1.0
			var sw := -1.0 if k < 2 else 1.0
			_vert(s, o, c + n * nh + u * uh * su + w * wh * sw, n, Vector2(su * 0.5 + 0.5, sw * 0.5 + 0.5), wb, PART_BELT, Color.WHITE)
		o["i"].append_array([b, b + 1, b + 2, b, b + 2, b + 3])

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
const BOOTS := [Color(0.3, 0.2, 0.13), Color(0.24, 0.17, 0.11), Color(0.18, 0.13, 0.1), Color(0.34, 0.23, 0.14), Color(0.14, 0.12, 0.11),
	Color(0.08, 0.075, 0.07), Color(0.42, 0.31, 0.2), Color(0.3, 0.12, 0.1), Color(0.28, 0.27, 0.25)]
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
	"ship's cook": "host", "lookout": "worker", "boat pilot": "pilot", "marine biologist": "civil", "ship engineer": "smith",
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
			sp["apron"] = maxf(float(sp["hem"]) + 0.16, 0.36) if sp["hem"] > 0.0 else 0.56
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
	if sp["belt"] and job != "" and role != "cleric" and chance.call(0.55):
		sp["pouch"] = 1 if chance.call(0.5) else -1
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
	# Coveralls for pilots and some trades; otherwise a shirt or jacket over separate
	# trousers, so a crowd mixes colours and cuts.
	var suit: bool = role == "pilot" or (role in ["worker", "smith", "medic"] and chance.call(0.35))
	var top: Color = main if suit else pick.call(UTILITY + MEDIC.slice(0, 1) + EARTH.slice(0, 6) + DYED.slice(2, 4))
	var bottom: Color = main if suit else pick.call(UTILITY + EARTH.slice(6, 9) + [Color(0.24, 0.26, 0.3)])
	if not suit and _near(top, bottom):
		top = top.lightened(0.3) if top.get_luminance() < 0.4 else top.darkened(0.35)
	cols[PART_SHIRT] = fab.call(top, FAB_CANVAS if suit or chance.call(0.5) else FAB_LINEN)
	cols[PART_PANTS] = fab.call(bottom, FAB_CANVAS)
	sp["sleeves"] = 1 if role in ["smith", "worker", "artisan"] and chance.call(0.5) else 2
	sp["belt"] = role != "pilot"
	if role in ["smith", "guard", "hunter"] or chance.call(0.35):
		sp["vest"] = 2
		var v: Color = pick.call(HIVIS) if role == "smith" or (role == "pilot" and chance.call(0.5)) else pick.call(UTILITY + EARTH.slice(0, 4))
		if _near(v, top):
			v = v.darkened(0.3)
		cols[PART_TRIM] = fab.call(v, FAB_QUILT if chance.call(0.6) else FAB_LEATHER)
	if role == "merchant" or (role in ["civil", "medic"] and chance.call(0.35)):
		# A long coat, open over the legs (white for medics: a lab coat).
		var coat: Color = Color(0.86, 0.87, 0.86) if role == "medic" else pick.call(RICH + UTILITY.slice(0, 2) + EARTH.slice(0, 3))
		sp["hem"] = 0.5
		sp["flare"] = 0.08
		sp["open"] = true
		cols[PART_SKIRT] = fab.call(coat, FAB_CANVAS if role == "medic" else FAB_WOOL)
		cols[PART_SHIRT] = fab.call(coat, FAB_CANVAS if role == "medic" else FAB_WOOL)
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
	var t_shirt := 0.012 * fit
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
		return -1.0, 60, 0.005)
	# Trousers down into the boots; under a long skirt, hose on the shins (a lifted hem).
	_shell(s, o, PART_PANTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
		if hem > 0.0 and hem < 0.45 and p.y > float(s["knee"]) - 0.06:
			return -1.0 # under a long skirt, hose only on the shins
		if (r == 5 and p.y <= waist - 0.03) or (r == 6 and p.y > boot_h - 0.03):
			if fit <= 1.0:
				return t_pants
			# Work trousers hang straight from the seat: close over the thigh's bulk,
			# roomier from the knee down, rather than ballooning like jodhpurs.
			return lerpf(0.01, 0.022, clampf((float(s["knee"]) + 0.12 - p.y) / 0.25, 0.0, 1.0))
		return -1.0, 30)
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
		# Cargo pockets on the outside of each thigh, and two on a man's chest.
		var knee: float = s["knee"]
		var crotch: float = s["crotch"]
		_shell(s, o, PART_PANTS, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if r == 5 and p.y > knee + 0.1 and p.y < crotch - 0.06 and absf(p.x) > 0.13 and absf(p.z + 0.03) < 0.06:
				return 0.024
			return -1.0, 8, 0.012)
		_shell(s, o, PART_TRIM if vest_kind > 0 else PART_SHIRT, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if not fem and r == 1 and p.y > float(s["shoulder_y"]) - 0.2 and p.y < float(s["shoulder_y"]) - 0.09 and absf(p.x) > 0.04 and absf(p.x) < 0.13 and p.z > 0.0:
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
		var vt := t_shirt + (0.012 if vest == 1 else 0.014)
		var low := waist - (0.08 if vest == 3 else 0.02)
		_shell(s, o, PART_TRIM, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if vest == 1 and not fem and p.z > 0.0 and absf(p.x) < 0.035 + 0.25 * maxf(0.0, p.y - float(s["shoulder_y"]) + 0.12):
				return -1.0 # a jerkin hangs open down the front, wider at the neck
			if (r == 1 or r == 5) and p.y > low and p.y < (float(s["shoulder_y"]) - 0.04 if fem and vest == 1 else float(s["neck"])):
				return vt
			return -1.0, 60, vt - t_shirt * 0.5)
	var top := waist - 0.02
	if hem > 0.0:
		if vest == 3:
			# A guard's quilted skirt hangs clear of leg armour worn under it.
			_skirt(s, o, top, hem, sp["flare"], PART_SKIRT, Color.WHITE, 1.0, 0.03)
		elif sp.get("open", false):
			_skirt(s, o, top, hem, sp["flare"], PART_SKIRT, Color.WHITE, 0.86, 0.0, -1.0, true)
		else:
			_skirt(s, o, top, hem, sp["flare"], PART_SKIRT, Color.WHITE)
	var apron: float = sp["apron"]
	if apron > 0.0:
		# Over the skirt it hangs from the same waist a little further out; over trousers
		# it falls from the hips like a skirt of its own.
		_skirt(s, o, top, apron, sp["flare"] if hem > 0.0 else 0.0, PART_APRON, Color.WHITE, 0.3 if hem > 0.0 else 0.25, 0.012 if hem > 0.0 else 0.006)
		if sp["bib"]:
			# The bib: a panel up the front of the belly and chest, narrowing to where it ties
			# at the neck.
			_bib(s, o, waist - 0.05, (0.036 if vest > 0 else 0.028) + t_shirt, Color.WHITE)
	if sp["belt"]:
		var loose := hem > 0.0 or apron > 0.0 or vest == 3
		_belt(s, o, waist - 0.035, Color.WHITE, PART_BELT, 0.04 if fit <= 1.0 else 0.05, 0.026 if loose else maxf(0.014, maxf(t_pants, t_shirt) + 0.008))
		if sp.get("pouch", 0) != 0:
			_pouch(s, o, waist - 0.035, float(sp["pouch"]))
	if sp["cape"] > 0.0:
		_cape(s, o, sp["cape"], Color.WHITE, (0.03 + float(sp["flare"]) * 0.5) if hem > 0.0 or apron > 0.0 else 0.0)
		# A mantle over the shoulders that the cape hangs from, so it wraps the shoulder
		# line instead of starting at a straight edge behind them.
		var sy: float = s["shoulder_y"]
		var neck_y: float = s["neck"]
		_shell(s, o, PART_CAPE, Color.WHITE, func(_i, p: Vector3, r: int) -> float:
			if (r == 1 and p.y > sy - 0.1 and p.y < neck_y + 0.01) or (r == 2 and p.y > sy - 0.05 and absf(p.x) < shoulder_x + 0.09):
				return 0.03 if vest_kind > 0 else 0.024
			return -1.0, 30, 0.01)
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
				# The opening reaches a little round the cheeks and up the brow, so the
				# helm's thick rim never cuts across the face.
				var face := p.z > head.z + 0.015 and p.y < head.y + 0.125
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
