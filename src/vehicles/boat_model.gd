class_name BoatModel
extends RefCounted
## Boats built from code: a lofted, planked (or painted) hull with real sheer and a fine
## bow, decks and rails you can walk, masts and rigging, cabins with a door you can go
## through. Each kind also lists its crew stations: where each person stands or sits
## aboard and what they are doing there. Local space: the waterline is y = 0 and the bow
## points to -z, like the other vehicles.

## Where crew member i is and what they do: p (local position of the feet), yaw (0 faces
## +z, the stern; PI faces the bow), pose: "sit", "row", "fish", "steer", "stand",
## "lookout", "work". Seated people's feet are a seat height (SEAT) below the seat.
const SEAT := 0.47
const STATIONS := {
	"raft": [{"p": Vector3(0.82, 0.3 - SEAT, 0.5), "yaw": PI * 0.5, "pose": "sit"}],
	"rowboat": [{"p": Vector3(0, 0.345 - SEAT, 0.25), "yaw": 0.0, "pose": "row"},
		{"p": Vector3(0, 0.345 - SEAT, 1.45), "yaw": PI * 0.5, "pose": "fish", "sit": true}],
	"fishing_boat": [{"p": Vector3(0, 0.6, 2.9), "yaw": PI, "pose": "steer"},
		{"p": Vector3(0.7, 0.6, -0.4), "yaw": PI * 0.5, "pose": "fish"},
		{"p": Vector3(-0.55, 0.6, 0.9), "yaw": -PI * 0.5, "pose": "work"}],
	"cog": [{"p": Vector3(0, 4.02, 7.8), "yaw": PI, "pose": "steer"},
		{"p": Vector3(1.6, 1.6, -2.4), "yaw": PI * 0.5, "pose": "work"},
		{"p": Vector3(-1.4, 1.6, 0.6), "yaw": -PI * 0.4, "pose": "stand"},
		{"p": Vector3(0.4, 2.04 - SEAT, 6.5), "yaw": 0.0, "pose": "sit_bench"},
		{"p": Vector3(-1.9, 1.6, -1.0), "yaw": -PI * 0.5, "pose": "fish"},
		{"p": Vector3(0, 2.6, -7.6), "yaw": PI, "pose": "lookout"}],
	"life_raft": [{"p": Vector3(-0.55, 0.3 - SEAT, 0.3), "yaw": PI * 0.75, "pose": "sit"},
		{"p": Vector3(0.55, 0.3 - SEAT, -0.2), "yaw": -PI * 0.25, "pose": "sit"}],
	"launch": [{"p": Vector3(0.45, 0.52, 0.65), "yaw": PI, "pose": "steer"},
		{"p": Vector3(-0.6, 1.03 - SEAT, 3.0), "yaw": -PI * 0.5, "pose": "fish", "sit": true}],
	"research_vessel": [{"p": Vector3(0.0, 4.67, -1.35), "yaw": PI, "pose": "steer"},
		{"p": Vector3(1.4, 1.95, 7.6), "yaw": PI * 0.5, "pose": "work"},
		{"p": Vector3(-2.0, 1.95, 6.2), "yaw": -PI * 0.5, "pose": "stand"},
		{"p": Vector3(1.25, 1.95, -0.4), "yaw": PI * 0.5, "pose": "work"},
		{"p": Vector3(2.4, 1.95, 10.5), "yaw": PI * 0.5, "pose": "fish"},
		{"p": Vector3(-1.0, 1.95, -9.6), "yaw": PI, "pose": "lookout"}],
}
## Poses sat down for.
const SEATED := ["sit", "row", "sit_bench"]

## Hull shapes: L length, B beam, D draft at the keel, F freeboard amidships, rise (sheer
## at the ends), transom (stern width, 0 = pointed), deck (deck height or NAN for an open
## boat), paint (sci-fi hulls are painted, not planked).
const HULLS := {
	"rowboat": {"L": 4.4, "B": 1.45, "D": 0.32, "F": 0.42, "rise": 0.18, "transom": 0.55, "deck": NAN},
	"fishing_boat": {"L": 8.0, "B": 2.5, "D": 0.7, "F": 0.75, "rise": 0.35, "transom": 0.0, "deck": 0.6, "tumble": 0.04},
	"cog": {"L": 20.0, "B": 6.6, "D": 1.9, "F": 1.75, "rise": 0.9, "transom": 0.62, "deck": 1.6, "tumble": 0.09},
	"launch": {"L": 7.5, "B": 2.5, "D": 0.55, "F": 0.7, "rise": 0.25, "transom": 0.8, "deck": 0.52, "paint": true},
	"research_vessel": {"L": 26.0, "B": 7.0, "D": 2.4, "F": 2.1, "rise": 0.9, "transom": 0.85, "deck": 1.95, "paint": true},
}
const NU := 26
const NV := 9

static var _mats: Dictionary = {}

static func stations(kind: String) -> Array:
	return STATIONS.get(kind, [])

static func seated(st: Dictionary) -> bool:
	return SEATED.has(String(st.get("pose", ""))) or bool(st.get("sit", false))

## Height of the deck people walk on (local y), or the floor of an open boat.
static func deck_y(kind: String) -> float:
	var h: Dictionary = HULLS.get(kind, {})
	if h.is_empty():
		return 0.3
	return float(h["deck"]) if not is_nan(float(h["deck"])) else 0.12

static func get_mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"sail":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.86, 0.8, 0.68)
			var tex := Materials.photo("fabric_linen", "detail")
			if tex:
				s.albedo_texture = tex
				s.uv1_triplanar = true
				s.uv1_scale = Vector3.ONE * 0.6
			s.vertex_color_use_as_albedo = true
			s.roughness = 0.95
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			s.backlight_enabled = true
			s.backlight = Color(0.35, 0.3, 0.22)
			m = s
		"hull_paint":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color.WHITE
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.32
			s.metallic = 0.1
			s.clearcoat_enabled = true
			s.clearcoat = 0.6
			var n := Materials.photo("panels", "normal")
			if n:
				s.normal_enabled = true
				s.normal_texture = n
				s.normal_scale = 0.12
				s.uv1_triplanar = true
				s.uv1_scale = Vector3.ONE * 0.25
			m = s
		"rubber_orange":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.95, 0.38, 0.08)
			s.roughness = 0.55
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			m = s
		"window":
			# Clear glass you see the sea through, with a faint sky reflection.
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.62, 0.74, 0.78, 0.18)
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			s.roughness = 0.04
			s.metallic_specular = 0.9
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = s
		"spar":
			# Masts and yards: dressed, oiled wood with the grain along them, not bark.
			var s := (Materials.get_mat("planks") as StandardMaterial3D).duplicate() as StandardMaterial3D
			s.albedo_color = Color(0.62, 0.46, 0.3)
			s.roughness = 0.6
			m = s
		"upholstery":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color.WHITE
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.85
			var tex := Materials.photo("fabric_linen", "detail")
			if tex:
				s.albedo_texture = tex
				s.uv1_triplanar = true
				s.uv1_scale = Vector3.ONE * 2.0
			m = s
		"ceiling":
			# Plain painted ceiling panels, quiet rather than a sheet of bare metal.
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.88, 0.89, 0.9)
			s.roughness = 0.7
			m = s
		"lens":
			# Frosted glass of lamps and running lights: bright when lit, never glowing.
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.94, 0.95, 0.96)
			s.roughness = 0.25
			s.clearcoat_enabled = true
			s.clearcoat = 0.7
			m = s
		"rope":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.5, 0.42, 0.3)
			s.roughness = 0.95
			m = s
		_:
			m = Materials.get_mat(name)
	_mats[name] = m
	return m

## The whole boat: meshes under the returned node, collision shapes added to `body`.
static func build(kind: String, seed: int, body: CollisionObject3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var k := MeshKit.new(seed)
	var shapes: Array = [] # [Shape3D, Transform3D]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	match kind:
		"raft":
			_raft(k, shapes, r)
		"rowboat":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.78, 0.64, 0.5), Color(0.78, 0.64, 0.5).darkened(0.38))
			_rowboat(k, shapes, r)
		"fishing_boat":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.62, 0.52, 0.44), Color(0.62, 0.52, 0.44).darkened(0.38))
			_fishing_boat(k, shapes, r)
		"cog":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.5, 0.42, 0.36), Color(0.5, 0.42, 0.36).darkened(0.38))
			_cog(k, shapes, r, root)
		"life_raft":
			_life_raft(k, shapes)
		"launch":
			_hull(k, shapes, HULLS[kind], "hull_paint", Color(0.93, 0.94, 0.95), Color(0.16, 0.22, 0.36))
			_launch(k, shapes, r)
		"research_vessel":
			_hull(k, shapes, HULLS[kind], "hull_paint", Color(0.94, 0.94, 0.95), Color(0.55, 0.12, 0.1))
			_research_vessel(k, shapes, r, root)
	if kind == "rowboat":
		_oars(root, seed)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(get_mat)
	mi.visibility_range_end = 1300.0
	root.add_child(mi)
	for s in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = s[1]
		body.add_child(cs)
	return root

# --- Hull ------------------------------------------------------------------------------------

## Half-beam, keel depth and top of the hull at u (0 stern .. 1 bow).
static func _section(h: Dictionary, u: float) -> Vector3:
	var B: float = h["B"]
	var hw: float
	var dep: float = h["D"]
	if u < 0.42:
		var x := u / 0.42
		hw = B * 0.5 * lerpf(float(h["transom"]), 1.0, 1.0 - pow(1.0 - x, 2.2))
		dep *= lerpf(0.7, 1.0, x)
	else:
		var x := (u - 0.42) / 0.58
		hw = B * 0.5 * (1.0 - pow(x, 1.9))
		dep *= 1.0 - 0.3 * x * x
	var e := 2.0 * u - 1.0
	var top: float = float(h["F"]) + float(h["rise"]) * e * e * (1.3 if e > 0.0 else 1.0)
	return Vector3(maxf(hw, 0.0), dep, top)

## A point on the hull's +x side: u along (stern to bow), v around (keel to sheer).
static func _hull_pt(h: Dictionary, u: float, v: float) -> Vector3:
	var s := _section(h, u)
	var a := v * PI * 0.5
	var z: float = float(h["L"]) * (0.5 - u)
	# The bow rakes forward toward the top, the stern a little aft.
	if u > 0.85:
		z -= (u - 0.85) / 0.15 * v * float(h["L"]) * 0.05
	# Tumblehome: big wooden hulls draw in a little toward the rail.
	var tumble := 1.0 - float(h.get("tumble", 0.0)) * smoothstep(0.7, 1.0, v)
	return Vector3(s.x * pow(sin(a), 0.5) * tumble, -s.y + (s.y + s.z) * (1.0 - cos(a)), z)

## Half-width of the hull at height y and u (deck edges).
static func _width_at(h: Dictionary, u: float, y: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 18:
		var m := (lo + hi) * 0.5
		if _hull_pt(h, u, m).y < y:
			lo = m
		else:
			hi = m
	return _hull_pt(h, u, (lo + hi) * 0.5).x

## A triangle facing along `hint` (the side it is seen from).
static func _tri_out(k: MeshKit, mat: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, hint: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(hint) < 0.0:
		k.tri(mat, Transform3D.IDENTITY, a, c, b, na, nc, nb, col)
	else:
		k.tri(mat, Transform3D.IDENTITY, a, b, c, na, nb, nc, col)

## Lofted hull, both sides, with its inside and a capping rail, and a transom. `below`:
## the bottom paint (antifouling) under the waterline, for painted hulls.
static func _hull(k: MeshKit, shapes: Array, h: Dictionary, mat: String, col: Color, below := Color(0, 0, 0, 0)) -> void:
	var grid: Array = []
	for i in NU + 1:
		var row: Array = []
		for j in NV + 1:
			row.append(_hull_pt(h, float(i) / NU, float(j) / NV))
		grid.append(row)
	var faces := PackedVector3Array()
	var th := 0.06 if float(h["L"]) < 10.0 else 0.12
	for side in [1.0, -1.0]:
		var sx := Vector3(side, 1, 1)
		for i in NU:
			for j in NV:
				var p00: Vector3 = grid[i][j] * sx
				var p10: Vector3 = grid[i + 1][j] * sx
				var p11: Vector3 = grid[i + 1][j + 1] * sx
				var p01: Vector3 = grid[i][j + 1] * sx
				var hint := Vector3(side, -0.5 + float(j) / NV, 0)
				var c := col
				# Painted hulls: bottom paint to the waterline; planked ones dark and wet a
				# hand's breadth above it.
				if below.a > 0.0 and (p00.y + p11.y) * 0.5 < (0.3 if mat == "planks" else 0.12):
					c = below
				var n00 := _hull_n(h, grid, i, j, side)
				var n10 := _hull_n(h, grid, i + 1, j, side)
				var n11 := _hull_n(h, grid, i + 1, j + 1, side)
				var n01 := _hull_n(h, grid, i, j + 1, side)
				if mat == "planks":
					# Clinker: each strake's lower edge laps out over the one below, so the
					# side reads as overlapping planks, each its own shade of weathered wood.
					var hgt := maxf((p01 - p00).length(), 0.05)
					var lap := clampf(hgt * 0.09, 0.012, 0.045)
					var up := (p01 - p00) / hgt
					var b00 := p00 + n00 * lap
					var b10 := p10 + n10 * lap
					var t00 := (n00 - up * (lap / hgt)).normalized()
					var t10 := (n10 - up * (lap / hgt)).normalized()
					var t11 := (n11 - up * (lap / hgt)).normalized()
					var t01 := (n01 - up * (lap / hgt)).normalized()
					var wv := fposmod(sin(float(j) * 12.9898 + floor(float(i) / 6.0) * 78.233 + side * 3.1) * 43758.5453, 1.0)
					var sc := c.darkened(wv * 0.16) if c == col else c
					_tri_out(k, mat, b00, b10, p11, t00, t10, t11, hint, sc)
					_tri_out(k, mat, b00, p11, p01, t00, t11, t01, hint, sc)
					if j > 0:
						_tri_out(k, mat, p00, p10, b10, -up, -up, -up, -up + n00 * 0.2, sc.darkened(0.35))
						_tri_out(k, mat, p00, b10, b00, -up, -up, -up, -up + n00 * 0.2, sc.darkened(0.35))
				else:
					_tri_out(k, mat, p00, p10, p11, n00, n10, n11, hint, c)
					_tri_out(k, mat, p00, p11, p01, n00, n11, n01, hint, c)
				faces.append_array([p00, p10, p11, p00, p11, p01])
				# The inside, a plank's thickness in, seen from the deck or the bilge.
				var q := func(p: Vector3) -> Vector3: return Vector3(p.x - side * th if absf(p.x) > th else 0.0, p.y + th * 0.5, p.z)
				var i00: Vector3 = q.call(p00)
				var i10: Vector3 = q.call(p10)
				var i11: Vector3 = q.call(p11)
				var i01: Vector3 = q.call(p01)
				var ic := col.darkened(0.12) if mat == "planks" else Color(0.86, 0.87, 0.88)
				_tri_out(k, mat, i00, i10, i11, -n00, -n10, -n11, -hint, ic)
				_tri_out(k, mat, i00, i11, i01, -n00, -n11, -n01, -hint, ic)
			# The rail along the top edge.
			var t0: Vector3 = grid[i][NV] * sx
			var t1: Vector3 = grid[i + 1][NV] * sx
			var o0 := t0 - Vector3(side * th, 0, 0)
			var o1 := t1 - Vector3(side * th, 0, 0)
			var up := Vector3(0, 0.05, 0)
			var rm := "timber" if mat == "planks" else "metal_dark"
			if side > 0.0:
				k.quad(rm, Transform3D.IDENTITY, t0 + up, t1 + up, o1 + up, o0 + up)
				k.quad(rm, Transform3D.IDENTITY, t0, t1, t1 + up, t0 + up)
			else:
				k.quad(rm, Transform3D.IDENTITY, o0 + up, o1 + up, t1 + up, t0 + up)
				k.quad(rm, Transform3D.IDENTITY, t1, t0, t0 + up, t1 + up)
	# Transom: the flat stern, closing the hull.
	if float(h["transom"]) > 0.01:
		for j in NV:
			var a: Vector3 = grid[0][j]
			var b: Vector3 = grid[0][j + 1]
			var am := Vector3(-a.x, a.y, a.z)
			var bm := Vector3(-b.x, b.y, b.z)
			var c := col if (a.y + b.y) * 0.5 >= (0.3 if mat == "planks" else 0.12) or below.a <= 0.0 else below
			_tri_out(k, mat, am, a, b, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, c)
			_tri_out(k, mat, am, b, bm, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, c)
			faces.append_array([am, a, b, am, b, bm])
	# Keel and stem: a timber (or steel) strip down the centreline.
	var km := "timber" if mat == "planks" else "metal_dark"
	for i in NU:
		var a: Vector3 = grid[i][0]
		var b: Vector3 = grid[i + 1][0]
		_beam(k, km, a + Vector3(0, -0.04, 0), b + Vector3(0, -0.04, 0), 0.05 if float(h["L"]) < 10.0 else 0.12)
	var stem_a: Vector3 = grid[NU][0]
	var stem_b: Vector3 = grid[NU][NV]
	_beam(k, km, stem_a, stem_b + Vector3(0, 0.12, -0.08), 0.06 if float(h["L"]) < 10.0 else 0.13)
	var cps := ConcavePolygonShape3D.new()
	cps.backface_collision = true
	cps.set_faces(faces)
	shapes.append([cps, Transform3D.IDENTITY])

## The boat's outline where it meets the water (y = 0), as local (x, z) points going
## round the hull: where the foam laps and the bow wave starts.
static func waterline(kind: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	match kind:
		"raft":
			for i in 20:
				var a := TAU * i / 20.0
				# A rounded box round the logs.
				out.append(Vector2(signf(cos(a)) * pow(absf(cos(a)), 0.35) * 1.12, signf(sin(a)) * pow(absf(sin(a)), 0.35) * 1.66))
		"life_raft":
			for i in 20:
				var a := TAU * i / 20.0
				out.append(Vector2(cos(a), sin(a)) * 1.42)
		_:
			var h: Dictionary = HULLS[kind]
			var L: float = h["L"]
			var n := 24
			for i in n + 1:
				var u := float(i) / n
				out.append(Vector2(maxf(_width_at(h, u, 0.0), 0.02), L * (0.5 - u)))
			for i in range(n - 1, -1, -1):
				var u := float(i) / n
				out.append(Vector2(-maxf(_width_at(h, u, 0.0), 0.02), L * (0.5 - u)))
	return out

## Sternpost up the middle of the transom, and the rudder hung on it: a tapered blade,
## broad below the water and narrowing to its stock, which rises to the tiller at `head`.
static func _rudder(k: MeshKit, h: Dictionary, head: float) -> void:
	var zs := float(h["L"]) * 0.5
	var bot := -float(h["D"]) * 0.7
	var top := float(h["F"]) + float(h["rise"]) * 1.0
	_beam(k, "timber", Vector3(0, bot - 0.05, zs + 0.04), Vector3(0, top + 0.1, zs + 0.04), 0.13)
	var col := Color(0.42, 0.34, 0.27)
	var t := 0.07
	# Blade outline (z behind the post, y): broad foot, a curve up the trailing edge.
	var prof := [Vector2(0.12, bot), Vector2(1.25, bot + 0.15), Vector2(1.3, bot + 1.2), Vector2(1.05, 0.4),
		Vector2(0.6, 1.2), Vector2(0.32, top - 0.2), Vector2(0.12, top - 0.2)]
	var cz := Vector2(0.4, (bot + top) * 0.5)
	for side in [1.0, -1.0]:
		for i in prof.size():
			var a: Vector2 = prof[i]
			var b: Vector2 = prof[(i + 1) % prof.size()]
			var n := Vector3(side, 0, 0)
			_tri_out(k, "planks", Vector3(side * t, cz.y, zs + cz.x), Vector3(side * t, a.y, zs + a.x), Vector3(side * t, b.y, zs + b.x), n, n, n, n, col)
	for i in prof.size():
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % prof.size()]
		var pa := Vector3(0, a.y, zs + a.x)
		var pb := Vector3(0, b.y, zs + b.x)
		k.quad("planks", Transform3D.IDENTITY, pa + Vector3(t, 0, 0), pb + Vector3(t, 0, 0), pb - Vector3(t, 0, 0), pa - Vector3(t, 0, 0), col.darkened(0.15))
	# Iron straps (pintles) binding blade to post, and the stock up to the tiller.
	for y in [bot + 0.5, 0.2, top - 0.6]:
		k.box("iron", Transform3D(Basis.IDENTITY, Vector3(0, y, zs + 0.35)), Vector3(t * 2.0 + 0.04, 0.08, 0.6))
	_beam(k, "timber", Vector3(0, top - 0.25, zs + 0.2), Vector3(0, head, zs - 0.35), 0.09)

## Smooth normal at a grid point, pointing out of the hull.
static func _hull_n(h: Dictionary, grid: Array, i: int, j: int, side: float) -> Vector3:
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, NU)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, NV)
	var du: Vector3 = grid[i1][j] - grid[i0][j]
	var dv: Vector3 = grid[i][j1] - grid[i][j0]
	var n := du.cross(dv).normalized()
	var p: Vector3 = grid[i][j]
	var out := Vector3(1.0, p.y * 0.3 - 0.2, 0.0)
	if n.dot(out) < 0.0:
		n = -n
	if n.length() < 0.5:
		n = Vector3(1, 0, 0)
	return Vector3(n.x * side, n.y, n.z)

## A deck of planks (or plating) at height y, filling the hull from u0 to u1, with its
## collision: one convex slab, so you can walk the whole of it.
static func _deck(k: MeshKit, shapes: Array, h: Dictionary, y: float, mat: String, u0 := 0.0, u1 := 1.0, col := Color.WHITE) -> void:
	var pts: Array = []
	var steps := 18
	for i in steps + 1:
		var u := lerpf(u0, u1, float(i) / steps)
		var w := maxf(_width_at(h, u, y) - 0.04, 0.02)
		pts.append(Vector2(w, float(h["L"]) * (0.5 - u)))
	var hull := PackedVector3Array()
	for i in steps:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		k.quad(mat, Transform3D.IDENTITY, Vector3(-a.x, y, a.y), Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(-b.x, y, b.y), col)
	for p in pts:
		hull.append(Vector3(p.x, y, p.y))
		hull.append(Vector3(-p.x, y, p.y))
		hull.append(Vector3(p.x * 0.9, y - 0.35, p.y))
		hull.append(Vector3(-p.x * 0.9, y - 0.35, p.y))
	var cs := ConvexPolygonShape3D.new()
	cs.points = hull
	shapes.append([cs, Transform3D.IDENTITY])

## Rails (or a planked bulwark) round a deck at y, leaving a gap on the starboard (+x)
## side at u_gap for boarding.
static func _rails(k: MeshKit, shapes: Array, h: Dictionary, y: float, height: float, bulwark: bool, u0 := 0.02, u1 := 0.98, u_gap := -1.0) -> void:
	var steps := 16
	for side in [1.0, -1.0]:
		var prev := Vector3.INF
		for i in steps + 1:
			var u := lerpf(u0, u1, float(i) / steps)
			var w := _width_at(h, u, y) - 0.06
			var p := Vector3(w * side, y, float(h["L"]) * (0.5 - u))
			if prev != Vector3.INF:
				var gap: bool = side > 0.0 and u_gap >= 0.0 and absf(lerpf(u0, u1, (float(i) - 0.5) / steps) - u_gap) < (u1 - u0) / steps * 0.6
				if not gap:
					if bulwark:
						var up := Vector3(0, height, 0)
						if side > 0.0:
							k.quad("planks", Transform3D.IDENTITY, prev, p, p + up, prev + up, Color(0.6, 0.5, 0.42))
							k.quad("planks", Transform3D.IDENTITY, p, prev, prev + up, p + up, Color(0.66, 0.56, 0.46))
						else:
							k.quad("planks", Transform3D.IDENTITY, p, prev, prev + up, p + up, Color(0.6, 0.5, 0.42))
							k.quad("planks", Transform3D.IDENTITY, prev, p, p + up, prev + up, Color(0.66, 0.56, 0.46))
						_beam(k, "timber", prev + up, p + up, 0.07)
					else:
						_beam(k, "metal", prev + Vector3(0, height, 0), p + Vector3(0, height, 0), 0.025)
						_beam(k, "metal", prev + Vector3(0, height * 0.5, 0), p + Vector3(0, height * 0.5, 0), 0.015)
					var mid := (prev + p) * 0.5 + Vector3(0, height * 0.5 + 0.1, 0)
					var len := prev.distance_to(p)
					var bs := BoxShape3D.new()
					bs.size = Vector3(0.12, height + 0.2, len + 0.05)
					var dir := (p - prev).normalized()
					var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
					shapes.append([bs, xf])
				if not bulwark or not gap:
					_beam(k, "timber" if bulwark else "metal", p, p + Vector3(0, height + 0.05, 0), 0.04 if bulwark else 0.02)
			prev = p

## A straight round spar or line from a to b.
static func _beam(k: MeshKit, mat: String, a: Vector3, b: Vector3, r: float, segs := 6) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	k.cylinder(mat, Transform3D(Basis(x, y, z), a), r, r, l, segs, true)

static func _line(k: MeshKit, a: Vector3, b: Vector3, r := 0.012) -> void:
	_beam(k, "rope", a, b, r, 4)

## A box with collision.
static func _solid(k: MeshKit, shapes: Array, mat: String, c: Vector3, size: Vector3, col := Color.WHITE, yaw := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	k.box(mat, xf, size, col)
	var bs := BoxShape3D.new()
	bs.size = size
	shapes.append([bs, xf])

## A walk-in room: four walls with a doorway in the `door` wall ("+z", "-z", "+x", "-x"),
## a floor and a roof (the roof walkable too) lined underneath with `ceil` if given.
## c: floor centre; size: outside size.
static func _room(k: MeshKit, shapes: Array, c: Vector3, size: Vector3, door: String, wall: String, floor: String, roof: String,
		col := Color.WHITE, windows := false, ceil := "") -> void:
	var t := 0.1
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var hy := size.y
	var dw := 1.0
	var dh := 2.05
	_solid(k, shapes, floor, c + Vector3(0, -0.05, 0), Vector3(size.x, 0.1, size.z))
	_solid(k, shapes, roof, c + Vector3(0, hy + 0.06, 0), Vector3(size.x + 0.2, 0.12, size.z + 0.2), col)
	if ceil != "":
		k.box(ceil, Transform3D(Basis.IDENTITY, c + Vector3(0, hy - 0.01, 0)), Vector3(size.x - 0.22, 0.02, size.z - 0.22))
	for wname in ["+z", "-z", "+x", "-x"]:
		var along_x: bool = wname.ends_with("z")
		var sgn := 1.0 if wname.begins_with("+") else -1.0
		var wl: float = size.x if along_x else size.z
		var wc := c + (Vector3(0, 0, sgn * (hz - t * 0.5)) if along_x else Vector3(sgn * (hx - t * 0.5), 0, 0))
		var thick := Vector3(wl, 0, t) if along_x else Vector3(t, 0, wl)
		var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		if wname == door:
			# Two side pieces and a lintel round the doorway.
			var side_l := (wl - dw) * 0.5
			for s in [-1.0, 1.0]:
				var pc: Vector3 = wc + axis * s * (dw * 0.5 + side_l * 0.5) + Vector3(0, hy * 0.5, 0)
				var sz: Vector3 = (Vector3(side_l, hy, t) if along_x else Vector3(t, hy, side_l))
				_solid(k, shapes, wall, pc, sz, col)
			var lin: Vector3 = (Vector3(dw, hy - dh, t) if along_x else Vector3(t, hy - dh, dw))
			_solid(k, shapes, wall, wc + Vector3(0, dh + (hy - dh) * 0.5, 0), lin, col)
			continue
		if windows and wl > 2.6:
			# A band of windows: wall below and above, glass between.
			var sill := 1.0
			var head := hy - 0.35
			_solid(k, shapes, wall, wc + Vector3(0, sill * 0.5, 0), thick + Vector3(0, sill, 0), col)
			_solid(k, shapes, wall, wc + Vector3(0, head + (hy - head) * 0.5, 0), thick + Vector3(0, hy - head, 0), col)
			k.box("window", Transform3D(Basis.IDENTITY, wc + Vector3(0, (sill + head) * 0.5, 0)), (Vector3(wl - 0.2, head - sill, 0.03) if along_x else Vector3(0.03, head - sill, wl - 0.2)))
			var gs := BoxShape3D.new()
			gs.size = thick + Vector3(0, head - sill, 0)
			shapes.append([gs, Transform3D(Basis.IDENTITY, wc + Vector3(0, (sill + head) * 0.5, 0))])
			# Mullions.
			var n := int(wl / 1.4)
			for m in range(1, n):
				var off := -wl * 0.5 + wl * float(m) / n
				k.box(wall, Transform3D(Basis.IDENTITY, wc + axis * off + Vector3(0, (sill + head) * 0.5, 0)), (Vector3(0.08, head - sill, t) if along_x else Vector3(t, head - sill, 0.08)), col)
			continue
		_solid(k, shapes, wall, wc + Vector3(0, hy * 0.5, 0), thick + Vector3(0, hy, 0), col)

## Steps (a sloped ramp you can walk, drawn as treads) from a to b, `w` wide.
static func _stairs(k: MeshKit, shapes: Array, a: Vector3, b: Vector3, w: float, mat: String, col := Color.WHITE) -> void:
	var d := b - a
	var n := maxi(int(ceil(absf(d.y) / 0.24)), 2)
	var flat := Vector3(d.x, 0, d.z)
	var yaw := atan2(flat.x, flat.z)
	var bs := Basis(Vector3.UP, yaw)
	for i in n:
		var t := (float(i) + 0.5) / n
		var p := a + d * t
		k.box(mat, Transform3D(bs, p - Vector3(0, 0.03, 0)), Vector3(w, 0.06, flat.length() / n + 0.04), col)
	# Stringers.
	for s in [-1.0, 1.0]:
		var off: Vector3 = bs.x * s * (w * 0.5 + 0.03)
		_beam(k, mat, a + off - Vector3(0, 0.08, 0), b + off - Vector3(0, 0.08, 0), 0.035, 4)
	var ramp := BoxShape3D.new()
	var len := d.length()
	ramp.size = Vector3(w, 0.1, len)
	var fwd := d.normalized()
	var right := bs.x
	var up := fwd.cross(right).normalized()
	if up.y < 0.0:
		up = -up
	var xf := Transform3D(Basis(right, up, fwd), (a + b) * 0.5 - up * 0.06)
	shapes.append([ramp, xf])

## Square sail hung from a yard, bellied forward by the wind (or furled on the yard).
static func _square_sail(k: MeshKit, top_y: float, bot_y: float, half_w: float, z: float, belly: float, furled: bool, col := Color.WHITE) -> void:
	_beam(k, "spar", Vector3(-half_w - 0.3, top_y, z), Vector3(half_w + 0.3, top_y, z), 0.09)
	if furled:
		_beam(k, "sail", Vector3(-half_w, top_y - 0.12, z + 0.05), Vector3(half_w, top_y - 0.12, z + 0.05), 0.2, 8)
		for i in 5:
			var x := lerpf(-half_w * 0.9, half_w * 0.9, float(i) / 4.0)
			k.cylinder("rope", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x - 0.02, top_y - 0.12, z + 0.05)), 0.215, 0.215, 0.04, 8)
		return
	var nx := 8
	var ny := 8
	var pts: Array = []
	for j in ny + 1:
		var row: Array = []
		var v := float(j) / ny
		for i in nx + 1:
			var u := float(i) / nx
			var x := lerpf(-half_w, half_w, u) * (1.0 - v * 0.06)
			var y := lerpf(top_y, bot_y, v)
			var b := belly * sin(u * PI) * sin(clampf(v * 1.1, 0.0, 1.0) * PI * 0.85 + 0.15)
			row.append(Vector3(x, y, z - b))
		pts.append(row)
	# Smooth normals, so the cloth shades as one curved sheet, not a quilt of facets.
	var nrm := func(j: int, i: int) -> Vector3:
		var du: Vector3 = pts[j][mini(i + 1, nx)] - pts[j][maxi(i - 1, 0)]
		var dv: Vector3 = pts[mini(j + 1, ny)][i] - pts[maxi(j - 1, 0)][i]
		return du.cross(dv).normalized()
	for j in ny:
		for i in nx:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			var na: Vector3 = nrm.call(j, i)
			var nb: Vector3 = nrm.call(j, i + 1)
			var nc: Vector3 = nrm.call(j + 1, i + 1)
			var nd: Vector3 = nrm.call(j + 1, i)
			k.tri("sail", Transform3D.IDENTITY, a, b, c, na, nb, nc, col)
			k.tri("sail", Transform3D.IDENTITY, a, c, d, na, nc, nd, col)

## Something to sit on, crates and barrels: the clutter of a working deck.
static func _barrel(k: MeshKit, p: Vector3, r := 0.3, h := 0.85) -> void:
	k.cylinder("planks", Transform3D(Basis.IDENTITY, p), r * 0.88, r * 0.88, h, 12, true, 0.0, 1, Color(0.7, 0.55, 0.4))
	k.cylinder("planks", Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.2, 0)), r, r, h * 0.6, 12, false, 0.0, 1, Color(0.75, 0.6, 0.45))
	for f in [0.08, 0.5, 0.9]:
		k.cylinder("iron", Transform3D(Basis.IDENTITY, p + Vector3(0, h * f - 0.03, 0)), r * 0.98 if f == 0.5 else r * 0.92, r * 0.98 if f == 0.5 else r * 0.92, 0.06, 12, false)

static func _crate(k: MeshKit, shapes: Array, p: Vector3, s: float, yaw := 0.0) -> void:
	_solid(k, shapes, "planks", p + Vector3(0, s * 0.5, 0), Vector3(s, s, s), Color(0.8, 0.68, 0.52), yaw)
	var bs := Basis(Vector3.UP, yaw)
	for e in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		k.box("timber", Transform3D(bs, p + bs * (e * s * 0.48) + Vector3(0, s * 0.5, 0)), Vector3(0.05, s + 0.01, 0.05))

static func _coil(k: MeshKit, p: Vector3, r := 0.3) -> void:
	for i in 4:
		k.cylinder("rope", Transform3D(Basis.IDENTITY, p + Vector3(0, i * 0.035, 0)), r - i * 0.03, r - i * 0.03, 0.035, 12, true)

## A heap of fishing net.
static func _net(k: MeshKit, p: Vector3) -> void:
	k.sphere("rope", Transform3D(Basis.IDENTITY, p), 0.55, 5, 8, 0.35, 0.45, Color(0.55, 0.6, 0.55), true)

static func _lantern(root: Node3D, k: MeshKit, p: Vector3, tech := false) -> void:
	if tech:
		# A flush ceiling fitting: brushed frame round a frosted diffuser (lit by the light
		# below it, not glowing itself).
		k.box("metal", Transform3D(Basis.IDENTITY, p), Vector3(0.62, 0.04, 0.26))
		k.box("lens", Transform3D(Basis.IDENTITY, p - Vector3(0, 0.022, 0)), Vector3(0.56, 0.01, 0.2))
	else:
		k.cylinder("iron", Transform3D(Basis.IDENTITY, p - Vector3(0, 0.14, 0)), 0.08, 0.06, 0.24, 6, true)
		k.cylinder("glow_warm", Transform3D(Basis.IDENTITY, p - Vector3(0, 0.1, 0)), 0.045, 0.045, 0.14, 6, true)
	var l := OmniLight3D.new()
	l.position = p - Vector3(0, 0.15, 0)
	l.light_color = Color(0.95, 0.97, 1.0) if tech else Color(1.0, 0.72, 0.42)
	l.light_energy = 1.3 if tech else 1.1
	l.omni_range = 5.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 50.0
	l.distance_fade_length = 20.0
	root.add_child(l)

## A bridge chair facing the bow: pedestal on a foot plate, padded seat and back with
## piping, and armrests.
static func _helm_chair(k: MeshKit, p: Vector3) -> void:
	var cloth := Color(0.36, 0.42, 0.5)
	k.cylinder("metal", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.015, 0)), 0.24, 0.26, 0.03, 16, true)
	k.cylinder("metal", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.26, 0)), 0.045, 0.055, 0.46, 10, true)
	k.box("metal_dark", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.5, 0)), Vector3(0.44, 0.03, 0.42))
	k.box("upholstery", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.55, 0.02)), Vector3(0.5, 0.08, 0.48), cloth)
	k.box("upholstery", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6, 0.02)), Vector3(0.44, 0.03, 0.42), cloth.lightened(0.06))
	var back := Transform3D(Basis(Vector3.RIGHT, -0.18), p + Vector3(0, 0.93, 0.26))
	k.box("upholstery", back, Vector3(0.48, 0.62, 0.09), cloth)
	k.box("metal_dark", back.translated_local(Vector3(0, 0, 0.05)), Vector3(0.44, 0.58, 0.02))
	for s in [-1.0, 1.0]:
		k.box("metal_dark", Transform3D(Basis.IDENTITY, p + Vector3(s * 0.27, 0.68, 0.05)), Vector3(0.04, 0.16, 0.04))
		k.box("upholstery", Transform3D(Basis.IDENTITY, p + Vector3(s * 0.27, 0.77, 0.02)), Vector3(0.07, 0.05, 0.36), cloth.darkened(0.25))

# --- Kinds ---------------------------------------------------------------------------------

static func _raft(k: MeshKit, shapes: Array, r: RandomNumberGenerator) -> void:
	# Logs lashed side by side, a pole with a rag of sail, a bundle and a water skin.
	var n := 6
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * 0.36
		var l := 3.2 + r.randf_range(-0.25, 0.25)
		var zo := r.randf_range(-0.15, 0.15)
		k.cylinder("bark", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.08, -l * 0.5 + zo)), 0.17, 0.15, l, 9, true, 0.08, 3)
	for z in [-1.0, 0.0, 1.0]:
		_beam(k, "rope", Vector3(-1.15, 0.27, z), Vector3(1.15, 0.27, z), 0.03, 5)
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.15, 0.3, 3.2)
	shapes.append([bs, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0))])
	var mast := Vector3(-0.3, 0.25, -0.6)
	_beam(k, "timber", mast, mast + Vector3(0.05, 2.4, 0), 0.05)
	var rag := [mast + Vector3(0.05, 2.3, 0), mast + Vector3(0.06, 1.0, 0.02), mast + Vector3(0.9, 1.1, 0.35)]
	var r0: Vector3 = rag[0]
	var nn := ((rag[1] as Vector3) - r0).cross((rag[2] as Vector3) - r0).normalized()
	k.tri("sail", Transform3D.IDENTITY, rag[0], rag[1], rag[2], nn, nn, nn, Color(0.7, 0.62, 0.5))
	k.sphere("leather", Transform3D(Basis.IDENTITY, Vector3(0.6, 0.38, 0.9)), 0.22, 6, 8, 0.2, 0.7)
	k.sphere("cloth", Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.36, 0.95)), 0.26, 6, 8, 0.25, 0.6)

static func _rowboat(k: MeshKit, shapes: Array, r: RandomNumberGenerator) -> void:
	var h: Dictionary = HULLS["rowboat"]
	# Floorboards and thwarts.
	_deck(k, shapes, h, 0.02, "planks", 0.12, 0.8, Color(0.7, 0.58, 0.45))
	for z in [-0.9, 0.25, 1.45]:
		var u: float = 0.5 - z / float(h["L"])
		var w := _width_at(h, u, 0.32) - 0.03
		k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, 0.32, z)), Vector3(w * 2.0, 0.05, 0.26), Color(0.8, 0.66, 0.5))
	# Rowlocks (the oars are their own nodes, so they can row: oars()).
	for s in [-1.0, 1.0]:
		k.cylinder("iron", Transform3D(Basis.IDENTITY, oar_lock(s) - Vector3(0, 0.05, 0)), 0.02, 0.02, 0.1, 5)
	if r.randf() < 0.7:
		_coil(k, Vector3(0, 0.05, -1.4), 0.18)
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0.3, 0.12, 1.75)), Vector3(0.4, 0.2, 0.3), Color(0.65, 0.5, 0.36))

## The rowboat's rowlock on side s (+1 starboard, -1 port), just aft of the rower, who
## sits facing the stern.
static func oar_lock(s: float) -> Vector3:
	var h: Dictionary = HULLS["rowboat"]
	return Vector3(s * (_width_at(h, 0.5 - 0.72 / float(h["L"]), 0.42) + 0.02), 0.47, 0.72)

const OAR_IN := 0.62 ## loom inboard of the rowlock (to the handle)
const OAR_OUT := 1.75 ## outboard, to the blade's tip

## Two oars, "Oar_r" and "Oar_l", each pivoting at its rowlock with the shaft along its
## local +x (outboard); BoatNode swings them through the stroke.
static func _oars(root: Node3D, seed: int) -> void:
	for s in [1.0, -1.0]:
		var k := MeshKit.new(seed + int(s))
		_beam(k, "timber", Vector3(-OAR_IN, 0, 0), Vector3(OAR_OUT - 0.45, 0, 0), 0.026)
		k.cylinder("timber", Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-OAR_IN + 0.08, 0, 0)), 0.03, 0.03, 0.16, 6)
		k.box("planks", Transform3D(Basis.IDENTITY, Vector3(OAR_OUT - 0.25, 0, 0)), Vector3(0.5, 0.15, 0.022), Color(0.85, 0.72, 0.55))
		var mi := MeshInstance3D.new()
		mi.name = "Oar_r" if s > 0.0 else "Oar_l"
		mi.mesh = k.commit(get_mat)
		mi.visibility_range_end = 400.0
		mi.position = oar_lock(s)
		mi.basis = oar_stroke(s, 0.0, 0.0)
		root.add_child(mi)

## An oar's pose at the rowlock on side s: `sweep` swings the blade toward the bow (+) or
## the stern (-), `dip` tips the blade down toward the water, `feather` turns it flat (1)
## or square to the stroke (0).
static func oar_basis(s: float, sweep: float, dip: float, feather: float) -> Basis:
	var dir := Vector3(s * cos(sweep) * cos(dip), -sin(dip), -sin(sweep) * cos(dip))
	var y := (Vector3.UP - dir * Vector3.UP.dot(dir)).normalized()
	var basis := Basis(dir, y, dir.cross(y))
	return basis * Basis(Vector3.RIGHT, feather * PI * 0.5 * s)

## An oar at stroke phase `ph` (BodyLanguage.row_phase) while rowing with effort `w`
## (0 at rest): blades squared and buried on the drive, feathered and lifted clear on the
## way back; at rest they trail flat on the water.
static func oar_stroke(s: float, ph: float, w: float) -> Basis:
	var sweep: float
	var dip := 0.36
	var feather := 0.0
	if ph < 0.4:
		sweep = lerpf(0.6, -0.35, smoothstep(0.0, 0.4, ph))
	else:
		sweep = lerpf(-0.35, 0.6, smoothstep(0.4, 1.0, ph))
		dip -= 0.24 * sin(PI * clampf((ph - 0.4) / 0.56, 0.0, 1.0))
		feather = smoothstep(0.4, 0.5, ph) * (1.0 - smoothstep(0.88, 0.97, ph))
	var e := smoothstep(0.0, 1.0, w)
	return oar_basis(s, lerpf(-0.25, sweep, e), lerpf(0.3, dip, e), lerpf(1.0, feather, e))

static func _fishing_boat(k: MeshKit, shapes: Array, r: RandomNumberGenerator) -> void:
	var h: Dictionary = HULLS["fishing_boat"]
	var dy: float = h["deck"]
	_deck(k, shapes, h, dy, "planks", 0.03, 0.93, Color(0.72, 0.6, 0.48))
	# Mast with a lug sail drawing, a tiller at the stern.
	var mast := Vector3(0, dy, -1.3)
	_beam(k, "spar", mast, mast + Vector3(0, 6.2, 0), 0.09)
	_square_sail(k, dy + 5.8, dy + 1.5, 1.7, -1.15, 0.55, false, Color(0.82, 0.7, 0.58))
	for s in [-1.0, 1.0]:
		_line(k, mast + Vector3(0, 5.9, 0), Vector3(s * (_width_at(h, 0.6, dy) - 0.05), dy + 0.2, -1.0))
	_line(k, mast + Vector3(0, 6.0, 0), Vector3(0, float(h["F"]) + 0.4, -float(h["L"]) * 0.5 + 0.1))
	_line(k, Vector3(-1.6, dy + 1.5, -1.15), Vector3(-0.9, dy + 0.1, 1.8))
	_line(k, Vector3(1.6, dy + 1.5, -1.15), Vector3(0.9, dy + 0.1, 1.8))
	_beam(k, "timber", Vector3(0, dy + 0.5, 3.75), Vector3(0, dy + 0.75, 2.6), 0.04)
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, dy - 0.6, 4.05)), Vector3(0.06, 1.4, 0.5), Color(0.6, 0.5, 0.4))
	# Catch: baskets, a heap of net, barrels, a coil of line.
	_net(k, Vector3(-0.4, dy, 1.6))
	_barrel(k, Vector3(0.75, dy, 1.4), 0.25, 0.65)
	_barrel(k, Vector3(0.7, dy, 2.0), 0.25, 0.65)
	_crate(k, shapes, Vector3(-0.7, dy, -0.2), 0.5, 0.2)
	_coil(k, Vector3(0.5, dy, -2.4), 0.24)
	_rails(k, shapes, h, dy, 0.35, true, 0.03, 0.93, 0.5)

static func _cog(k: MeshKit, shapes: Array, r: RandomNumberGenerator, root: Node3D) -> void:
	var h: Dictionary = HULLS["cog"]
	var dy: float = h["deck"]
	_deck(k, shapes, h, dy, "planks", 0.02, 0.97, Color(0.74, 0.62, 0.5))
	_rails(k, shapes, h, dy, 1.0, true, 0.27, 0.78, 0.55)
	# Sterncastle: the captain's cabin under a raised deck with a rail and the tiller.
	# As wide as the hull is at its after end, so it doesn't hang out over the water.
	var hx := minf(_width_at(h, 0.5 - 9.1 / float(h["L"]), dy) - 0.08, 2.5)
	var cab_c := Vector3(0, dy, 7.0)
	var cab := Vector3(hx * 2.0, 2.3, 4.2)
	_room(k, shapes, cab_c, cab, "-z", "planks", "wood_floor", "planks", Color(0.66, 0.54, 0.42))
	var top := dy + cab.y + 0.12
	# Framing on the castle's plain walls: corner posts, wales along its sides, a moulded
	# cap under the rail and a pair of shuttered stern windows.
	for s in [-1.0, 1.0]:
		for z in [4.9, 9.1]:
			_beam(k, "timber", Vector3(s * (hx + 0.04), dy - 0.2, z), Vector3(s * (hx + 0.04), top + 0.05, z), 0.09)
		for y in [dy + 0.9, dy + 1.8]:
			k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * (hx + 0.05), y, 7.0)), Vector3(0.08, 0.12, 4.25))
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * (hx + 0.07), top - 0.02, 7.0)), Vector3(0.14, 0.18, 4.35))
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * 0.8, dy + 1.5, 9.14)), Vector3(0.6, 0.55, 0.06), Color(0.3, 0.22, 0.16))
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * 0.8, dy + 1.5, 9.17)), Vector3(0.7, 0.07, 0.04))
	k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, top - 0.02, 9.16)), Vector3(hx * 2.0 + 0.2, 0.18, 0.14))
	for s in [-1.0, 1.0]:
		_beam(k, "timber", Vector3(s * hx, top, 4.9), Vector3(s * hx, top, 9.1), 0.06)
		_beam(k, "timber", Vector3(s * hx, top + 0.9, 4.9), Vector3(s * hx, top + 0.9, 9.1), 0.06)
		for z in [4.9, 6.3, 7.7, 9.1]:
			_beam(k, "timber", Vector3(s * hx, top, z), Vector3(s * hx, top + 0.9, z), 0.05)
		var rs := BoxShape3D.new()
		rs.size = Vector3(0.1, 1.0, 4.2)
		shapes.append([rs, Transform3D(Basis.IDENTITY, Vector3(s * hx, top + 0.5, 7.0))])
	_beam(k, "timber", Vector3(-hx, top + 0.9, 9.1), Vector3(hx, top + 0.9, 9.1), 0.06)
	var back := BoxShape3D.new()
	back.size = Vector3(hx * 2.0, 1.0, 0.1)
	shapes.append([back, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.5, 9.1))])
	_beam(k, "timber", Vector3(0, top + 0.85, 8.1), Vector3(0, top + 0.5, 9.6), 0.06)
	_rudder(k, h, top + 0.5)
	# Stairs from the waist up to the sterncastle, port side.
	_stairs(k, shapes, Vector3(-hx + 0.6, dy, 2.75), Vector3(-hx + 0.6, top, 4.9), 0.9, "planks", Color(0.7, 0.58, 0.46))
	# Inside: table and benches, the captain's chest, a bunk, a lantern, charts.
	var f := dy
	_solid(k, shapes, "planks", Vector3(0, f + 0.75, 7.2), Vector3(1.6, 0.06, 0.9), Color(0.6, 0.45, 0.32))
	for x in [-0.6, 0.6]:
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(x, f + 0.37, 7.2)), Vector3(0.08, 0.74, 0.7))
	for z in [6.55, 7.85]:
		_solid(k, shapes, "planks", Vector3(0, f + 0.22, z), Vector3(1.5, 0.44, 0.3), Color(0.62, 0.48, 0.34))
	k.box("pitch_cloth", Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.2, f + 0.79, 7.1)), Vector3(0.6, 0.01, 0.42), Color(0.9, 0.85, 0.7))
	_solid(k, shapes, "planks", Vector3(hx - 0.5, f + 0.45, 7.8), Vector3(0.8, 0.9, 2.0), Color(0.55, 0.42, 0.3))
	k.box("cloth_blue", Transform3D(Basis.IDENTITY, Vector3(hx - 0.5, f + 0.95, 7.8)), Vector3(0.75, 0.12, 1.9))
	_crate(k, shapes, Vector3(-hx + 0.5, f, 8.3), 0.6, 0.1)
	k.box("iron", Transform3D(Basis.IDENTITY, Vector3(-hx + 0.5, f + 0.6, 8.3)), Vector3(0.62, 0.05, 0.62))
	_lantern(root, k, Vector3(0, f + cab.y - 0.05, 7.0))
	_lantern(root, k, Vector3(0, top + 1.5, 9.25))
	# Forecastle: a little raised deck at the bow with a rail.
	var fc := dy + 1.0
	_solid(k, shapes, "planks", Vector3(0, fc - 0.05, -7.6), Vector3(3.2, 0.1, 2.2), Color(0.72, 0.6, 0.48))
	_solid(k, shapes, "planks", Vector3(0, dy + 0.5, -6.55), Vector3(3.2, 1.0, 0.1), Color(0.6, 0.5, 0.4))
	_stairs(k, shapes, Vector3(1.2, dy, -4.6), Vector3(1.2, fc, -6.45), 0.7, "planks")
	_beam(k, "timber", Vector3(0, float(h["F"]) + float(h["rise"]) * 1.3 + 0.1, -10.0), Vector3(0, float(h["F"]) + 2.6, -13.2), 0.14)
	# Mainmast, furled square sail on its yard, shrouds and stays; a crow's nest.
	var mast := Vector3(0, dy, -0.8)
	_beam(k, "spar", mast - Vector3(0, 1.5, 0), mast + Vector3(0, 16.5, 0), 0.24, 10)
	k.cylinder("planks", Transform3D(Basis.IDENTITY, mast + Vector3(0, 13.4, 0)), 0.8, 0.9, 0.9, 12, true, 0.0, 1, Color(0.65, 0.52, 0.4))
	_square_sail(k, dy + 12.6, dy + 4.2, 5.2, -0.5, 1.9, false, Color(0.9, 0.84, 0.72))
	for s in [-1.0, 1.0]:
		for z in [-2.2, -0.9, 0.4]:
			var u: float = 0.5 - z / float(h["L"])
			_line(k, mast + Vector3(0, 13.2, 0), Vector3(s * (_width_at(h, u, dy + 0.9) + 0.05), dy + 1.0, z), 0.02)
		_line(k, mast + Vector3(s * 5.0, 4.2, 0.3), Vector3(s * 2.2, dy + 1.0, 3.8), 0.012)
	_line(k, mast + Vector3(0, 16.2, 0), Vector3(0, float(h["F"]) + 2.5, -13.1), 0.025)
	_line(k, mast + Vector3(0, 15.8, 0), Vector3(0, top + 0.9, 9.1), 0.02)
	# Anchor cable running from the bow down into the water.
	_beam(k, "rope", Vector3(1.0, float(h["F"]) + 1.2, -9.4), Vector3(2.4, -3.0, -15.5), 0.06, 6)
	# Cargo in the waist.
	for i in r.randi_range(3, 6):
		var p := Vector3(r.randf_range(-2.0, 2.0), dy, r.randf_range(-4.0, 3.5))
		if absf(p.z - mast.z) < 0.9 and absf(p.x) < 0.9:
			continue
		if p.x < -1.2 and p.z > 1.8:
			continue # keep the stairs clear
		if r.randf() < 0.5:
			_barrel(k, p, 0.32, 0.9)
			var bs := CylinderShape3D.new()
			bs.radius = 0.32
			bs.height = 0.9
			shapes.append([bs, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.45, 0))])
		else:
			_crate(k, shapes, p, r.randf_range(0.5, 0.8), r.randf() * 0.6)
	_coil(k, Vector3(2.0, dy, -3.4), 0.3)
	_coil(k, Vector3(-2.1, dy, -2.6), 0.25)
	# Boarding steps up the starboard side to the gap in the bulwark.
	var gap_z := float(h["L"]) * (0.5 - 0.55)
	var hw := _width_at(h, 0.55, dy)
	_stairs(k, shapes, Vector3(hw + 1.25, -0.45, gap_z + 2.6), Vector3(hw + 0.15, dy, gap_z), 0.8, "planks", Color(0.66, 0.55, 0.44))

static func _life_raft(k: MeshKit, shapes: Array) -> void:
	# An inflatable ring of orange tubes with a canopy half up, a grab line round it.
	var R := 1.25
	var segs := 16
	for ring in [0, 1]:
		var y: float = 0.12 + ring * 0.3
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := Vector3(cos(a0) * R, y, sin(a0) * R)
			var p1 := Vector3(cos(a1) * R, y, sin(a1) * R)
			_beam(k, "rubber_orange", p0, p1, 0.17, 10)
			k.sphere("rubber_orange", Transform3D(Basis.IDENTITY, p1), 0.17, 6, 10)
			if ring == 1 and i % 2 == 0:
				_line(k, p0 + Vector3(0, 0.12, 0) + p0.normalized() * 0.14, p1 + Vector3(0, 0.12, 0) + p1.normalized() * 0.14, 0.012)
	k.cylinder("rubber", Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), R, R, 0.06, 16, true)
	# Canopy: half a dome over one end, on an arch tube.
	var arch := 12
	for i in arch:
		var a0 := PI * i / arch
		var a1 := PI * (i + 1) / arch
		_beam(k, "rubber_orange", Vector3(cos(a0) * R, 0.45 + sin(a0) * 1.0, 0.0), Vector3(cos(a1) * R, 0.45 + sin(a1) * 1.0, 0.0), 0.07, 8)
	var cn := 10
	for i in cn:
		for j in 6:
			var a0 := PI * i / cn
			var a1 := PI * (i + 1) / cn
			var z0 := float(j) / 6.0 * 0.9
			var z1 := float(j + 1) / 6.0 * 0.9
			var f0 := sqrt(maxf(1.0 - pow(z0 / 1.0, 2.0), 0.0))
			var f1 := sqrt(maxf(1.0 - pow(z1 / 1.0, 2.0), 0.0))
			var p00 := Vector3(cos(a0) * R * f0, 0.45 + sin(a0) * f0, -z0)
			var p10 := Vector3(cos(a1) * R * f0, 0.45 + sin(a1) * f0, -z0)
			var p11 := Vector3(cos(a1) * R * f1, 0.45 + sin(a1) * f1, -z1)
			var p01 := Vector3(cos(a0) * R * f1, 0.45 + sin(a0) * f1, -z1)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			k.tri("sail", Transform3D.IDENTITY, p00, p10, p11, n, n, n, Color(1.0, 0.48, 0.16))
			k.tri("sail", Transform3D.IDENTITY, p00, p11, p01, n, n, n, Color(1.0, 0.48, 0.16))
	k.box("rubber", Transform3D(Basis.IDENTITY, Vector3(0.5, 0.13, 0.5)), Vector3(0.4, 0.18, 0.28))
	var cs := CylinderShape3D.new()
	cs.radius = R + 0.15
	cs.height = 0.3
	shapes.append([cs, Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0))])

static func _launch(k: MeshKit, shapes: Array, r: RandomNumberGenerator) -> void:
	var h: Dictionary = HULLS["launch"]
	var dy: float = h["deck"]
	_deck(k, shapes, h, dy, "scifi_floor", 0.02, 0.9)
	_rails(k, shapes, h, dy, 0.7, false, 0.55, 0.92)
	# Console with a curved windscreen, a T-top roof on struts.
	_solid(k, shapes, "hull_paint", Vector3(0.45, dy + 0.5, -0.1), Vector3(1.0, 1.0, 0.8), Color(0.9, 0.91, 0.93))
	k.box("screen", Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.45, dy + 1.04, 0.15)), Vector3(0.7, 0.03, 0.32))
	k.box("window", Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0.45, dy + 1.3, -0.45)), Vector3(1.1, 0.55, 0.02))
	k.cylinder("metal_dark", Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(0.45, dy + 1.05, 0.25)), 0.16, 0.16, 0.04, 14)
	for e in [Vector3(-0.35, 0, -0.5), Vector3(1.25, 0, -0.5), Vector3(-0.35, 0, 1.0), Vector3(1.25, 0, 1.0)]:
		_beam(k, "metal", Vector3(e.x, dy, e.z), Vector3(e.x, dy + 2.15, e.z), 0.03)
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(0.45, dy + 2.2, 0.25)), Vector3(1.9, 0.08, 1.8), Color(0.2, 0.26, 0.38))
	_beam(k, "metal", Vector3(0.45, dy + 2.25, 0.6), Vector3(0.45, dy + 3.1, 0.6), 0.02)
	k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0.45, dy + 2.35, -0.1)), Vector3(0.6, 0.08, 0.1))
	# Bench seat aft, an outboard motor on the transom, a cooler and rod holders.
	_solid(k, shapes, "hull_paint", Vector3(0, dy + 0.22, 3.0), Vector3(2.0, 0.44, 0.55), Color(0.85, 0.86, 0.88))
	k.box("leather", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.47, 3.0)), Vector3(1.9, 0.08, 0.5), Color(0.4, 0.42, 0.45))
	var stern := float(h["L"]) * 0.5
	k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.45, stern + 0.25)), Vector3(0.45, 0.7, 0.5))
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.85, stern + 0.25)), Vector3(0.5, 0.18, 0.62), Color(0.15, 0.17, 0.2))
	k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0, -0.3, stern + 0.3)), Vector3(0.16, 1.1, 0.2))
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(-0.6, dy + 0.25, 1.7)), Vector3(0.7, 0.45, 0.45), Color(0.2, 0.45, 0.75))
	for s in [-1.0, 1.0]:
		_beam(k, "metal", Vector3(s * 0.95, dy + 0.4, 3.4), Vector3(s * 1.2, dy + 2.6, 4.2), 0.012)
	# Navigation lights.
	k.box("glow_red", Transform3D(Basis.IDENTITY, Vector3(-0.9, dy + 0.75, -1.8)), Vector3(0.04, 0.05, 0.1))
	k.box("lens", Transform3D(Basis.IDENTITY, Vector3(0.45, dy + 3.12, 0.6)), Vector3(0.06, 0.06, 0.06))
	if r.randf() < 0.6:
		_coil(k, Vector3(-0.6, dy, -1.6), 0.2)

static func _research_vessel(k: MeshKit, shapes: Array, r: RandomNumberGenerator, root: Node3D) -> void:
	var h: Dictionary = HULLS["research_vessel"]
	var dy: float = h["deck"]
	var L: float = h["L"]
	_deck(k, shapes, h, dy, "scifi_floor", 0.02, 0.96)
	_rails(k, shapes, h, dy, 1.05, false, 0.02, 0.97, 0.62)
	# Superstructure: a lab/mess deck with a door aft, the bridge above it with a band
	# of windows all round, a stair up the side and a radar mast on top.
	var lab_c := Vector3(0, dy, 1.6)
	var lab := Vector3(5.2, 2.6, 8.0)
	_room(k, shapes, lab_c, lab, "+z", "hull_paint", "scifi_floor", "scifi_floor", Color(0.92, 0.93, 0.95), true, "ceiling")
	var bdeck := dy + lab.y + 0.12
	var br_c := Vector3(0, bdeck, -0.6)
	var br := Vector3(5.6, 2.4, 3.6)
	_room(k, shapes, br_c, br, "+z", "hull_paint", "scifi_floor", "hull_paint", Color(0.93, 0.94, 0.96), true, "ceiling")
	_stairs(k, shapes, Vector3(-2.15, dy, 8.2), Vector3(-2.15, bdeck, 5.4), 0.85, "metal")
	# The bridge deck's open part behind the wheelhouse, with rails.
	for s in [-1.0, 1.0]:
		_beam(k, "metal", Vector3(s * 2.55, bdeck + 1.0, 1.2), Vector3(s * 2.55, bdeck + 1.0, 5.6), 0.025)
		var rs := BoxShape3D.new()
		rs.size = Vector3(0.08, 1.1, 4.4)
		shapes.append([rs, Transform3D(Basis.IDENTITY, Vector3(s * 2.55, bdeck + 0.55, 3.4))])
	_beam(k, "metal", Vector3(-2.55, bdeck + 1.0, 5.6), Vector3(-1.6, bdeck + 1.0, 5.6), 0.025)
	_beam(k, "metal", Vector3(2.55, bdeck + 1.0, 5.6), Vector3(-0.0, bdeck + 1.0, 5.6), 0.025)
	# Bridge: helm console, screens, chairs.
	var bf := bdeck
	_solid(k, shapes, "hull_paint", Vector3(0, bf + 0.5, -2.0), Vector3(4.2, 1.0, 0.6), Color(0.25, 0.28, 0.32))
	for x in [-1.4, 0.0, 1.4]:
		k.box("screen", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(x, bf + 1.05, -1.85)), Vector3(1.0, 0.03, 0.4))
	k.cylinder("metal_dark", Transform3D(Basis(Vector3.RIGHT, -1.1), Vector3(0.0, bf + 1.1, -1.65)), 0.22, 0.22, 0.05, 16)
	for x in [-0.9, 0.9]:
		_helm_chair(k, Vector3(x, bf, -0.9))
	_lantern(root, k, Vector3(0, bf + br.y - 0.06, -0.6), true)
	# Lab below: benches with sample tanks, a terminal, bunks along the side, a locker.
	var lf := dy
	_solid(k, shapes, "hull_paint", Vector3(2.0, lf + 0.45, 0.0), Vector3(0.9, 0.9, 4.0), Color(0.75, 0.77, 0.8))
	k.box("screen", Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(2.3, lf + 1.35, -1.0)), Vector3(0.03, 0.5, 0.8))
	for z in [-0.8, 0.6]:
		k.box("glass", Transform3D(Basis.IDENTITY, Vector3(2.0, lf + 1.15, z)), Vector3(0.6, 0.5, 0.9))
		k.box("metal", Transform3D(Basis.IDENTITY, Vector3(2.0, lf + 0.93, z)), Vector3(0.62, 0.04, 0.92))
	for y in [0.35, 1.25]:
		_solid(k, shapes, "metal", Vector3(-2.05, lf + y, 0.6), Vector3(0.85, 0.08, 2.0))
		k.box("cloth_blue", Transform3D(Basis.IDENTITY, Vector3(-2.05, lf + y + 0.08, 0.6)), Vector3(0.8, 0.1, 1.9))
	_beam(k, "metal", Vector3(-1.62, lf, -0.4), Vector3(-1.62, lf + 1.7, -0.4), 0.025)
	_beam(k, "metal", Vector3(-1.62, lf, 1.6), Vector3(-1.62, lf + 1.7, 1.6), 0.025)
	_solid(k, shapes, "metal_dark", Vector3(-2.2, lf + 1.0, -2.7), Vector3(0.6, 2.0, 1.4))
	_solid(k, shapes, "hull_paint", Vector3(0.0, lf + 0.45, 4.6), Vector3(1.6, 0.9, 0.8), Color(0.8, 0.82, 0.85))
	_lantern(root, k, Vector3(0, lf + lab.y - 0.06, 1.6), true)
	# Radar mast, dome and antennas on the wheelhouse roof.
	var roof := bdeck + br.y + 0.12
	_beam(k, "metal", Vector3(0, roof, -0.2), Vector3(0, roof + 3.8, -0.2), 0.1, 8)
	_beam(k, "metal", Vector3(-1.2, roof + 2.6, -0.2), Vector3(1.2, roof + 2.6, -0.2), 0.05)
	k.box("metal_dark", Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(0, roof + 3.95, -0.2)), Vector3(2.0, 0.12, 0.25))
	k.sphere("hull_paint", Transform3D(Basis.IDENTITY, Vector3(1.6, roof + 0.4, 0.6)), 0.45, 8, 12, 0.0, 1.0, Color(0.95, 0.95, 0.96))
	for x in [-1.8, -1.3]:
		_beam(k, "metal", Vector3(x, roof, 0.9), Vector3(x, roof + 2.6, 0.9), 0.015)
	k.box("glow_red", Transform3D(Basis.IDENTITY, Vector3(0, roof + 3.85, -0.2)), Vector3(0.08, 0.08, 0.08))
	# Aft working deck: an A-frame crane over the stern with a sampling cage, winch drum,
	# boxes of gear, a rescue boat in its cradle.
	var stern := L * 0.5
	for s in [-1.0, 1.0]:
		_beam(k, "hazard", Vector3(s * 2.5, dy, stern - 1.2), Vector3(s * 1.2, dy + 4.6, stern + 0.4), 0.13, 8)
	_beam(k, "hazard", Vector3(-1.3, dy + 4.55, stern + 0.4), Vector3(1.3, dy + 4.55, stern + 0.4), 0.13, 8)
	_line(k, Vector3(0, dy + 4.5, stern + 0.4), Vector3(0, dy + 1.4, stern + 0.6), 0.015)
	k.box("metal", Transform3D(Basis.IDENTITY, Vector3(0, dy + 1.0, stern + 0.6)), Vector3(0.8, 0.8, 0.8))
	k.cylinder("metal_dark", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.6, dy + 0.55, stern - 3.4)), 0.45, 0.45, 1.2, 14)
	var bs := CylinderShape3D.new()
	bs.radius = 0.5
	bs.height = 1.3
	shapes.append([bs, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, dy + 0.55, stern - 3.4))])
	for i in r.randi_range(2, 4):
		var p := Vector3(r.randf_range(-2.2, 2.2), dy, stern - r.randf_range(4.8, 7.2))
		if p.x < -1.5:
			continue
		_solid(k, shapes, "hull_paint", p + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.6), [Color(0.2, 0.45, 0.75), Color(0.9, 0.55, 0.12), Color(0.75, 0.77, 0.8)][i % 3], r.randf() * 0.4)
	# Rescue boat on the port side of the bridge deck, in its davit.
	var rb := Vector3(-3.3, bdeck + 0.2, 2.6)
	k.sphere("rubber_orange", Transform3D(Basis.IDENTITY, rb), 1.0, 6, 12, 0.0, 0.35, Color.WHITE)
	k.box("rubber", Transform3D(Basis.IDENTITY, rb + Vector3(0, -0.15, 0)), Vector3(1.0, 0.1, 2.4))
	_beam(k, "metal", Vector3(-2.6, bdeck, 2.6), Vector3(-2.6, bdeck + 1.8, 2.6), 0.06)
	_beam(k, "metal", Vector3(-2.6, bdeck + 1.8, 2.6), Vector3(-3.3, bdeck + 1.8, 2.6), 0.05)
	# Life-raft canisters on the rails, a bow anchor windlass and a mast with lights.
	for z in [-4.5, -3.6]:
		k.cylinder("hull_paint", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-2.75, dy + 0.75, z)), 0.3, 0.3, 0.9, 12, true, 0.0, 1, Color(0.95, 0.95, 0.96))
	k.cylinder("metal_dark", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.6, dy + 0.35, -8.6)), 0.3, 0.3, 1.2, 12)
	_beam(k, "metal_dark", Vector3(0.9, float(h["F"]) + 1.0, -11.2), Vector3(2.7, -3.2, -18.0), 0.05, 6)
	_beam(k, "metal", Vector3(0, dy, -9.5), Vector3(0, dy + 6.0, -9.5), 0.08, 8)
	k.box("lens", Transform3D(Basis.IDENTITY, Vector3(0, dy + 6.05, -9.5)), Vector3(0.1, 0.1, 0.1))
	k.box("glow_red", Transform3D(Basis.IDENTITY, Vector3(-2.85, bdeck + 1.1, -1.0)), Vector3(0.05, 0.1, 0.18))
	k.box("lens", Transform3D(Basis.IDENTITY, Vector3(2.85, bdeck + 1.1, -1.0)), Vector3(0.05, 0.1, 0.18))
	# Name boards and a hull stripe.
	for s in [-1.0, 1.0]:
		var hw := _width_at(h, 0.12, 1.0)
		k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(s * (hw + 0.02), 1.15, L * 0.5 - 0.12 * L - 6.0)), Vector3(0.02, 0.22, L * 0.62), Color(0.12, 0.3, 0.55))
	# Boarding: a stair down the starboard side to a platform at the water.
	var gap_z := L * (0.5 - 0.62)
	var hw2 := _width_at(h, 0.62, dy)
	_solid(k, shapes, "metal", Vector3(hw2 + 1.0, -0.2, gap_z + 3.4), Vector3(1.2, 0.12, 1.2))
	_stairs(k, shapes, Vector3(hw2 + 0.9, -0.15, gap_z + 2.8), Vector3(hw2 + 0.25, dy, gap_z), 0.9, "metal")
