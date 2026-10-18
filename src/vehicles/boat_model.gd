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
	"canoe": [{"p": Vector3(0, 0.09 - SEAT, 1.45), "yaw": PI, "pose": "sit"},
		{"p": Vector3(0, 0.09 - SEAT, -1.35), "yaw": PI, "pose": "sit"}],
	"sloop": [{"p": Vector3(0.75, 0.7 + 0.4 - SEAT, 3.0), "yaw": PI, "pose": "sit"},
		{"p": Vector3(-0.8, 0.7 + 0.4 - SEAT, 2.2), "yaw": PI * 0.5, "pose": "sit"}],
	"kayak": [{"p": Vector3(0, -0.06 - SEAT, 0.3), "yaw": PI, "pose": "sit"}],
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
## boat), paint (sci-fi hulls are painted, not planked), rake (how far the stern leans aft
## toward the top, a share of L), round (how far the transom bulges aft at its middle, a
## share of its half-width), double (pointed at both ends, like a canoe), boot (height the
## bottom colour comes up to).
const HULLS := {
	"canoe": {"L": 4.8, "B": 0.86, "D": 0.2, "F": 0.16, "rise": 0.3, "transom": 0.0, "deck": NAN, "double": true},
	"kayak": {"L": 4.0, "B": 0.6, "D": 0.15, "F": 0.13, "rise": 0.07, "transom": 0.0, "deck": NAN, "double": true},
	"rowboat": {"L": 4.4, "B": 1.45, "D": 0.32, "F": 0.42, "rise": 0.18, "transom": 0.55, "deck": NAN},
	"sloop": {"L": 9.0, "B": 2.6, "D": 0.75, "F": 0.8, "rise": 0.38, "transom": 0.55, "deck": 0.7},
	"fishing_boat": {"L": 8.0, "B": 2.5, "D": 0.7, "F": 0.75, "rise": 0.35, "transom": 0.0, "deck": 0.6, "tumble": 0.04},
	"cog": {"L": 20.0, "B": 6.6, "D": 1.9, "F": 1.75, "rise": 0.9, "transom": 0.34, "deck": 1.6, "tumble": 0.09, "rake": 0.03, "round": 0.35},
	"launch": {"L": 7.5, "B": 2.5, "D": 0.55, "F": 0.7, "rise": 0.25, "transom": 0.8, "deck": 0.52, "paint": true},
	"research_vessel": {"L": 26.0, "B": 7.0, "D": 2.4, "F": 2.1, "rise": 0.9, "transom": 0.85, "deck": 1.95, "paint": true, "boot": 0.75},
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
			# Plain cloth: a woven texture this fine only shimmers into rings and grids at
			# any distance; the panels BoatRig sews it from carry the detail instead.
			s.albedo_color = Color(0.86, 0.8, 0.68)
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
		"painted_planks":
			# White lead paint over planking: the seams still show through it.
			var s := StandardMaterial3D.new()
			s.albedo_color = Color.WHITE
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.5
			var n := Materials.photo("planks", "normal")
			if n:
				s.normal_enabled = true
				s.normal_texture = n
				s.normal_scale = 0.6
				s.uv1_triplanar = true
				s.uv1_scale = Vector3.ONE * 0.5
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
			m = Materials.get_mat("timber")
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
		"screen":
			# Instrument screens: dark glass showing a dim chart, lit no brighter than the
			# room (human worlds: nothing glows).
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.08, 0.13, 0.16)
			s.roughness = 0.12
			s.metallic_specular = 0.7
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
			_raft(k, shapes, r, root)
		"rowboat":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.78, 0.64, 0.5), Color(0.78, 0.64, 0.5).darkened(0.38))
			_rowboat(k, shapes, r)
		"canoe":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.78, 0.5, 0.3))
			_canoe(k, shapes)
		"kayak":
			_hull(k, shapes, HULLS[kind], "hull_paint", Color(0.72, 0.09, 0.07))
			_kayak(k, shapes)
		"sloop":
			_hull(k, shapes, HULLS[kind], "painted_planks", Color(0.9, 0.88, 0.83), Color(0.42, 0.26, 0.16))
			_sloop(k, shapes, r, root)
		"fishing_boat":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.62, 0.52, 0.44), Color(0.62, 0.52, 0.44).darkened(0.38))
			_fishing_boat(k, shapes, r, root)
		"cog":
			_hull(k, shapes, HULLS[kind], "planks", Color(0.5, 0.42, 0.36), Color(0.5, 0.42, 0.36).darkened(0.38))
			_cog(k, shapes, r, root)
		"life_raft":
			_life_raft(k, shapes)
		"launch":
			_hull(k, shapes, HULLS[kind], "hull_paint", Color(0.93, 0.94, 0.95), Color(0.16, 0.22, 0.36))
			_launch(k, shapes, r)
			_weather_steel(k, HULLS[kind], r, 4, 3, root)
		"research_vessel":
			_hull(k, shapes, HULLS[kind], "hull_paint", Color(0.94, 0.94, 0.95), Color(0.55, 0.12, 0.1))
			_research_vessel(k, shapes, r, root)
			_weather_steel(k, HULLS[kind], r, 8, 5, root)
	if kind == "rowboat":
		_oars(root, seed)
	var mi := MeshInstance3D.new()
	mi.name = "Hull"
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
	if h.get("double", false):
		# Double-ended: the same fine entry fore and aft, the ends sweeping up.
		var x := absf(2.0 * u - 1.0)
		hw = B * 0.5 * (1.0 - pow(x, 2.1))
		dep *= 1.0 - 0.35 * x * x
		return Vector3(maxf(hw, 0.0), dep, float(h["F"]) + float(h["rise"]) * pow(x, 3.0))
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
	elif u < 0.15:
		z += (0.15 - u) / 0.15 * v * float(h["L"]) * (0.05 if h.get("double", false) else float(h.get("rake", 0.0)))
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

## A flat quad facing along `hint`, flat-shaded.
static func _quad_out(k: MeshKit, mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(hint) < 0.0:
		n = -n
	_tri_out(k, mat, a, b, c, n, n, n, hint, col)
	_tri_out(k, mat, a, c, d, n, n, n, hint, col)

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
				var my := (p00.y + p11.y) * 0.5
				if below.a > 0.0 and my < float(h.get("boot", 0.3 if mat == "planks" else 0.12)):
					c = below
				elif mat != "planks" and my < 0.6:
					# Waterline scum on painted hulls: greenish brown, fading up the side.
					c = c.lerp(Color(0.42, 0.42, 0.33), 0.45 * (1.0 - smoothstep(0.12, 0.6, my)))
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
	# Transom: the stern, closing the hull; flat, or bulging aft at the middle ("round").
	if float(h["transom"]) > 0.01:
		var rd := float(h.get("round", 0.0))
		for j in NV:
			var a: Vector3 = grid[0][j]
			var b: Vector3 = grid[0][j + 1]
			var am := Vector3(-a.x, a.y, a.z)
			var bm := Vector3(-b.x, b.y, b.z)
			var ca := Vector3(0, a.y, a.z + a.x * rd)
			var cb := Vector3(0, b.y, b.z + b.x * rd)
			var c := col if (a.y + b.y) * 0.5 >= float(h.get("boot", 0.3 if mat == "planks" else 0.12)) or below.a <= 0.0 else below
			for sd in [1.0, -1.0]:
				var e0 := a if sd > 0.0 else am
				var e1 := b if sd > 0.0 else bm
				var n := Vector3(sd * rd, 0, 1).normalized()
				_tri_out(k, mat, ca, e0, e1, Vector3.BACK, n, n, Vector3.BACK, c)
				_tri_out(k, mat, ca, e1, cb, Vector3.BACK, n, Vector3.BACK, Vector3.BACK, c)
				faces.append_array([ca, e0, e1, ca, e1, cb])
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
	# The sternpost follows the raked, rounded stern: the transom's middle at each height.
	var rd := float(h.get("round", 0.0))
	var aft := func(y: float) -> float:
		var q := _hull_pt(h, 0.0, acos(clampf(1.0 - (y - bot) / (top - bot), -1.0, 1.0)) * 2.0 / PI)
		return q.z + q.x * rd
	_beam(k, "timber", Vector3(0, bot - 0.05, aft.call(bot) + 0.04), Vector3(0, top + 0.1, aft.call(top) + 0.04), 0.13)
	var col := Color(0.47, 0.38, 0.3)
	var t := 0.07
	# Blade outline (z behind the post, y): broad foot, a curve up the trailing edge.
	var prof := [Vector2(0.12, bot), Vector2(1.25, bot + 0.15), Vector2(1.3, bot + 1.2), Vector2(1.05, 0.4),
		Vector2(0.6, 1.2), Vector2(0.32, top - 0.2), Vector2(0.12, top - 0.2)]
	var cz := Vector2(0.4, (bot + top) * 0.5)
	var at := func(q: Vector2, x: float) -> Vector3: return Vector3(x, q.y, aft.call(q.y) + q.x)
	for side in [1.0, -1.0]:
		for i in prof.size():
			var a: Vector2 = prof[i]
			var b: Vector2 = prof[(i + 1) % prof.size()]
			var n := Vector3(side, 0, 0)
			_tri_out(k, "planks", at.call(cz, side * t), at.call(a, side * t), at.call(b, side * t), n, n, n, n, col)
	for i in prof.size():
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % prof.size()]
		k.quad("planks", Transform3D.IDENTITY, at.call(a, t), at.call(b, t), at.call(b, -t), at.call(a, -t), col.darkened(0.15))
	# Iron straps (pintles) binding blade to post, and the stock up to the tiller.
	for y in [bot + 0.5, 0.2, top - 0.6]:
		k.box("iron", Transform3D(Basis.IDENTITY, Vector3(0, y, aft.call(y) + 0.35)), Vector3(t * 2.0 + 0.04, 0.08, 0.6))
	_beam(k, "timber", Vector3(0, top - 0.25, aft.call(top - 0.25) + 0.2), Vector3(0, head, aft.call(top) - 0.35), 0.09)

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
static func _beam(k: MeshKit, mat: String, a: Vector3, b: Vector3, r: float, segs := 6, col := Color.WHITE) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	k.cylinder(mat, Transform3D(Basis(x, y, z), a), r, r, l, segs, true, 0.0, 1, col)

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

## A working steel hull's wear: rust weeping down from scuppers and hawse holes in
## tapering streaks, and fenders hung over the side on lines from the rail.
static func _weather_steel(k: MeshKit, h: Dictionary, r: RandomNumberGenerator, streaks: int, fenders: int, root: Node3D) -> void:
	# Fenders are their own node ("Fenders"): BoatNode shows them only while she lies
	# still, as a crew would haul them in before getting under way.
	var fk := MeshKit.new(9)
	for side in [1.0, -1.0]:
		for si in streaks:
			var u := r.randf_range(0.08, 0.9)
			var v0 := r.randf_range(0.95, 0.99)
			var v1 := v0 - r.randf_range(0.06, 0.16)
			var w0 := r.randf_range(0.05, 0.1) * (1.0 if float(h["L"]) > 10.0 else 0.6)
			# Weathered brown, never red: a bright streak on white paint reads as blood.
			var col := Color(0.55, 0.42, 0.3).lerp(Color(0.62, 0.52, 0.4), r.randf())
			# The scupper it weeps from.
			var sp := _skin(h, u, v0 + 0.004, side)
			k.box("metal_dark", Transform3D(Basis.IDENTITY, sp), Vector3(0.03, 0.06, w0 * 2.4))
			var segs := 5
			for i in segs:
				var t0 := float(i) / segs
				var t1 := float(i + 1) / segs
				var a := _skin(h, u, lerpf(v0, v1, t0), side)
				var b := _skin(h, u, lerpf(v0, v1, t1), side)
				var wa := w0 * (1.0 - t0 * 0.85)
				var wb := w0 * (1.0 - t1 * 0.85)
				var along := Vector3(0, 0, wa)
				var along_b := Vector3(0, 0, wb)
				var n := Vector3(side, 0, 0)
				# Fading out into the paint as it runs down.
				var c := col.lerp(Color(0.9, 0.88, 0.84), 0.25 + t1 * 0.7)
				_tri_out(k, "rust", a - along, a + along, b + along_b, n, n, n, n, c)
				_tri_out(k, "rust", a - along, b + along_b, b - along_b, n, n, n, n, c)
		for fi in fenders:
			var u := lerpf(0.25, 0.7, (float(fi) + 0.5) / fenders)
			var z := float(h["L"]) * (0.5 - u)
			var top := float(h["F"]) + float(h["rise"]) * pow(2.0 * u - 1.0, 2.0)
			var x: float = side * (_width_at(h, u, top - 0.6) + 0.17)
			var R := 0.12 if float(h["L"]) < 10.0 else 0.2
			fk.cylinder("rubber", Transform3D(Basis.IDENTITY, Vector3(x, top - 0.75, z)), R, R, R * 3.2, 12, true, 0.0, 1, Color(0.12, 0.13, 0.15))
			_line(fk, Vector3(x, top - 0.75 + R * 1.6, z), Vector3(x - side * 0.15, top + 0.05, z), 0.01)
	if fenders > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Fenders"
		mi.mesh = fk.commit(get_mat)
		mi.visibility_range_end = 400.0
		root.add_child(mi)

## A point just off the outside of the hull's skin on side s (decals sit on it).
static func _skin(h: Dictionary, u: float, v: float, s: float) -> Vector3:
	var p := _hull_pt(h, u, v)
	return Vector3(s * (p.x + 0.015), p.y, p.z)

## A ship's wheel: rim, eight spokes with turned handles past the rim, a hub on a column
## rising from the console.
static func _helm_wheel(k: MeshKit, c: Vector3) -> void:
	var b := Basis(Vector3.RIGHT, -0.35)
	var R := 0.23
	var segs := 16
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		_beam(k, "metal_dark", c + b * Vector3(cos(a0) * R, sin(a0) * R, 0), c + b * Vector3(cos(a1) * R, sin(a1) * R, 0), 0.016, 6)
	for i in 8:
		var a := TAU * i / 8.0
		var d := b * Vector3(cos(a), sin(a), 0)
		_beam(k, "metal", c, c + d * (R + 0.08), 0.009, 5)
		# Handle along the spoke (a cylinder's axis is its local y).
		k.cylinder("rubber", Transform3D(b * Basis(Vector3.BACK, a - PI * 0.5), c + d * (R + 0.06)), 0.014, 0.014, 0.07, 6)
	k.cylinder("metal", Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), c + b * Vector3(0, 0, 0.03)), 0.045, 0.045, 0.08, 10)
	_beam(k, "metal_dark", c + b * Vector3(0, 0, 0.07), c + Vector3(0, -0.22, 0.25), 0.04)

## The wheelhouse's walls under its windows: a dado rail all round, instrument panels
## with gauges and small screens to the sides, a chart table, a radio rack and a fire
## extinguisher by the door.
static func _bridge_walls(k: MeshKit, shapes: Array, c: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5 - 0.1
	var z0 := c.z - size.z * 0.5 + 0.1
	var z1 := c.z + size.z * 0.5 - 0.1
	var f := c.y
	var grey := Color(0.55, 0.58, 0.62)
	for s in [-1.0, 1.0]:
		k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(s * hx, f + 0.95, c.z)), Vector3(0.04, 0.05, size.z - 0.2), grey)
		k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(s * hx, f + 0.08, c.z)), Vector3(0.03, 0.16, size.z - 0.2), Color(0.3, 0.32, 0.35))
		# Instrument panel: a dark plate with gauges and one small screen.
		var pz := c.z - 0.5
		k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(s * (hx - 0.02), f + 0.6, pz)), Vector3(0.04, 0.5, 1.1))
		for i in 3:
			var g := Vector3(s * (hx - 0.05), f + 0.68, pz - 0.35 + i * 0.35)
			k.cylinder("metal", Transform3D(Basis(Vector3.BACK, PI * 0.5), g), 0.07, 0.07, 0.025, 14, true, 0.0, 1, Color(0.85, 0.86, 0.84))
		ScreenLook.face(k, Transform3D(Basis(Vector3.UP, -s * PI / 2), Vector3(s * (hx - 0.041), f + 0.47, pz)), 0.3, 0.16, "nav", "boat")
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(0, f + 0.95, z0)), Vector3(size.x - 0.2, 0.05, 0.04), grey)
	# Chart table (port, aft) with a chart and dividers; radio rack (starboard, aft).
	_solid(k, shapes, "hull_paint", Vector3(-hx + 0.45, f + 0.45, z1 - 0.7), Vector3(0.8, 0.9, 0.9), Color(0.7, 0.72, 0.75))
	k.box("pitch_cloth", Transform3D(Basis(Vector3.UP, 0.1), Vector3(-hx + 0.45, f + 0.905, z1 - 0.7)), Vector3(0.6, 0.005, 0.5), Color(0.92, 0.9, 0.82))
	_solid(k, shapes, "metal_dark", Vector3(hx - 0.3, f + 0.75, z1 - 0.9), Vector3(0.5, 1.5, 0.5))
	for i in 3:
		k.box("metal", Transform3D(Basis.IDENTITY, Vector3(hx - 0.56, f + 0.45 + i * 0.4, z1 - 0.9)), Vector3(0.02, 0.3, 0.44))
	ScreenLook.face(k, Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(hx - 0.552, f + 1.25, z1 - 0.9)), 0.25, 0.1, "monitor", "boat")
	k.cylinder("painted", Transform3D(Basis.IDENTITY, Vector3(-0.7, f + 0.3, z1 - 0.02)), 0.08, 0.08, 0.55, 10, true, 0.0, 1, Color(0.75, 0.08, 0.06))

## A helm screen leaning back towards whoever stands at it (aft, +z) by `tilt` from
## flat: a dark housing w x d with the instruments on it (ScreenLook).
static func _nav_screen(k: MeshKit, at: Vector3, tilt: float, w: float, d: float) -> void:
	var b := Basis(Vector3.RIGHT, tilt)
	k.box("metal_dark", Transform3D(b, at), Vector3(w + 0.04, 0.03, d + 0.04))
	ScreenLook.face(k, Transform3D(b * Basis(Vector3.RIGHT, -PI / 2), at + b.y * 0.016), w, d, "nav", "boat")

## A bridge chair facing the bow: pedestal on a foot plate, padded seat and back with
## piping, and armrests.
static func _helm_chair(k: MeshKit, p: Vector3) -> void:
	var cloth := Color(0.36, 0.42, 0.5)
	# A five-legged star base bolted to the deck.
	for i in 5:
		var a := TAU * i / 5.0
		_beam(k, "metal_dark", p + Vector3(0, 0.05, 0), p + Vector3(cos(a) * 0.3, 0.02, sin(a) * 0.3), 0.025)
		k.cylinder("rubber", Transform3D(Basis.IDENTITY, p + Vector3(cos(a) * 0.3, 0.02, sin(a) * 0.3)), 0.035, 0.035, 0.04, 8)
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

## The boat's live sails (BoatRig), made on first use.
static func _rig(root: Node3D) -> BoatRig:
	var rig: BoatRig = root.get_node_or_null("Rig")
	if rig == null:
		rig = BoatRig.new()
		root.add_child(rig)
	return rig

# --- Kinds ---------------------------------------------------------------------------------

static func _raft(k: MeshKit, shapes: Array, r: RandomNumberGenerator, root: Node3D) -> void:
	# Logs lashed side by side, a short mast with a small square sail on a yard, a bundle
	# and a water skin.
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
	var mast := Vector3(0, 0.25, -0.75)
	_beam(k, "timber", mast, mast + Vector3(0, 2.7, 0), 0.055)
	# Stays to the raft's corners hold the mast up.
	for c in [Vector3(-1.0, 0.27, -1.5), Vector3(1.0, 0.27, -1.5), Vector3(-1.0, 0.27, 1.2), Vector3(1.0, 0.27, 1.2)]:
		_line(k, mast + Vector3(0, 2.55, 0), c, 0.01)
	var rig := _rig(root)
	rig.add_square(mast, 2.45, 0.75, 0.85, 0.1, 0.35, Color(0.8, 0.74, 0.64),
		[["clew_l", Vector3(-1.05, 0.28, 0.2)], ["clew_r", Vector3(1.05, 0.28, 0.2)]], 0.8)
	# A crate lashed down aft, and the long steering oar over the stern in its crutch.
	_crate(k, shapes, Vector3(-0.45, 0.25, 0.95), 0.5, 0.1)
	_beam(k, "timber", Vector3(-0.3, 0.27, 1.45), Vector3(-0.3, 0.75, 1.45), 0.04)
	_beam(k, "timber", Vector3(-0.15, 1.05, 0.75), Vector3(-0.55, -0.15, 2.9), 0.04)
	k.box("planks", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-0.53, -0.08, 2.85)), Vector3(0.05, 0.22, 0.6), Color(0.7, 0.56, 0.4))
	k.sphere("leather", Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.38, -1.2)), 0.22, 6, 8, 0.2, 0.7)
	k.sphere("cloth", Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.36, 0.95)), 0.26, 6, 8, 0.25, 0.6)

## An open cedar canoe: ribs inside, two cane seats on rails, a thwart amidships, the
## gunwales capped.
static func _canoe(k: MeshKit, shapes: Array) -> void:
	var h: Dictionary = HULLS["canoe"]
	var L: float = h["L"]
	var wood := Color(0.82, 0.55, 0.32)
	# Ribs: thin bent frames following the inside of the hull, every 30 cm.
	var n := 13
	for i in n:
		var u := lerpf(0.14, 0.86, float(i) / (n - 1))
		var prev := Vector3.ZERO
		for j in 7:
			var q := _hull_pt(h, u, float(j) / 6.0)
			var p := Vector3(q.x - 0.03, q.y + 0.02, q.z)
			if j > 0:
				_beam(k, "timber", prev, p, 0.012, 4)
				_beam(k, "timber", Vector3(-prev.x, prev.y, prev.z), Vector3(-p.x, p.y, p.z), 0.012, 4)
			prev = p
	# Floor planks (and the floor you'd stand on).
	_deck(k, shapes, h, -0.1, "planks", 0.22, 0.78, wood.darkened(0.1))
	# Two cane seats and the carrying thwart.
	for z in [1.45, -1.35]:
		var u: float = 0.5 - z / L
		var w := _width_at(h, u, 0.08) - 0.02
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, z - 0.16)), Vector3(w * 2.0, 0.03, 0.03), wood)
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, 0.07, z + 0.16)), Vector3(w * 2.0, 0.03, 0.03), wood)
		k.box("pitch_cloth", Transform3D(Basis.IDENTITY, Vector3(0, 0.08, z)), Vector3(w * 1.6, 0.012, 0.3), Color(0.86, 0.74, 0.5))
	var tw := _width_at(h, 0.5, 0.12)
	k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0.0)), Vector3(tw * 2.0, 0.025, 0.07), wood)
	# Deck caps at both ends.
	for sgn in [-1.0, 1.0]:
		var z0: float = sgn * L * 0.5 * 0.86
		var u0: float = 0.5 - z0 / L
		var w0 := _width_at(h, u0, 0.2)
		var tip: Vector3 = _hull_pt(h, 0.0 if sgn > 0.0 else 1.0, 1.0)
		k.tri("timber", Transform3D.IDENTITY, Vector3(-w0, 0.22, z0), Vector3(w0, 0.22, z0), Vector3(0, tip.y, tip.z),
			Vector3.UP, Vector3.UP, Vector3.UP, wood.darkened(0.2))

## A sea kayak: a closed deck over the hull, one cockpit with a black coaming, a pale
## stripe down the deck and bungee cords across the foredeck.
static func _kayak(k: MeshKit, shapes: Array) -> void:
	var h: Dictionary = HULLS["kayak"]
	var L: float = h["L"]
	var red := Color(0.72, 0.09, 0.07)
	# The deck: a low ridge from end to end over the hull's sheer.
	var n := 16
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var a := _hull_pt(h, u0, 1.0)
		var b := _hull_pt(h, u1, 1.0)
		var ra := a.y + 0.09 * (1.0 - pow(absf(2.0 * u0 - 1.0), 2.0))
		var rb := b.y + 0.09 * (1.0 - pow(absf(2.0 * u1 - 1.0), 2.0))
		for sgn in [-1.0, 1.0]:
			_quad_out(k, "hull_paint", Vector3(sgn * a.x, a.y, a.z), Vector3(sgn * b.x, b.y, b.z), Vector3(0, rb, b.z), Vector3(0, ra, a.z), Vector3.UP, red)
		# A pale wood-look stripe along the ridge.
		k.quad("hull_paint", Transform3D.IDENTITY, Vector3(-0.045, ra + 0.004, a.z), Vector3(0.045, ra + 0.004, a.z),
			Vector3(0.045, rb + 0.004, b.z), Vector3(-0.045, rb + 0.004, b.z), Color(0.86, 0.72, 0.5))
	var dk := BoxShape3D.new()
	dk.size = Vector3(0.5, 0.2, L * 0.8)
	shapes.append([dk, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0))])
	# Cockpit: a black coaming ring round a dark well.
	var c := Vector3(0, 0.25, 0.25)
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		_beam(k, "rubber", c + Vector3(cos(a0) * 0.24, 0, sin(a0) * 0.42), c + Vector3(cos(a1) * 0.24, 0, sin(a1) * 0.42), 0.022, 5)
	k.cylinder("rubber", Transform3D(Basis(Vector3.RIGHT, 0.0).scaled(Vector3(1.0, 1.0, 1.75)), c - Vector3(0, 0.12, 0)), 0.23, 0.23, 0.02, 16, true, 0.0, 1, Color(0.06, 0.06, 0.07))
	# Bungee cords criss-crossing the foredeck.
	for z in [-0.75, -1.2]:
		var y := 0.19
		_line(k, Vector3(-0.2, y, z - 0.2), Vector3(0.2, y, z + 0.2), 0.008)
		_line(k, Vector3(0.2, y, z - 0.2), Vector3(-0.2, y, z + 0.2), 0.008)

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

## The anchor cable as its own node ("Anchor"), so BoatNode can hide it while she sails.
static func _anchor_cable(root: Node3D, mat: String, a: Vector3, b: Vector3, r: float) -> void:
	var k := MeshKit.new(7)
	_beam(k, mat, a, b, r, 6)
	var mi := MeshInstance3D.new()
	mi.name = "Anchor"
	mi.mesh = k.commit(get_mat)
	mi.visibility_range_end = 400.0
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
## way back; at rest they trail aft alongside the hull, blades flat on the water.
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
	return oar_basis(s, lerpf(-1.15, sweep, e), lerpf(0.12, dip, e), lerpf(1.0, feather, e))

static func _fishing_boat(k: MeshKit, shapes: Array, r: RandomNumberGenerator, root: Node3D) -> void:
	var h: Dictionary = HULLS["fishing_boat"]
	var dy: float = h["deck"]
	_deck(k, shapes, h, dy, "planks", 0.03, 0.93, Color(0.72, 0.6, 0.48))
	# Mast with a lugsail on a slanted yard (BoatRig swings it to the wind), a tiller at
	# the stern.
	var mast := Vector3(0, dy, -1.3)
	_beam(k, "spar", mast, mast + Vector3(0, 6.2, 0), 0.09)
	var rig := _rig(root)
	rig.add_lug(mast, Vector3(0, 1.75, -1.2), Vector3(0, 4.3, -1.4), Vector3(0, 6.5, 2.3), Vector3(0, 2.0, 3.0), 0.75, Color(0.84, 0.77, 0.66),
		[["clew", Vector3(0, dy + 0.35, 3.7)], ["tack", Vector3(0, dy + 0.1, -2.6)]])
	for s in [-1.0, 1.0]:
		_line(k, mast + Vector3(0, 5.9, 0), Vector3(s * (_width_at(h, 0.6, dy) - 0.05), dy + 0.2, -1.0))
	_line(k, mast + Vector3(0, 6.0, 0), Vector3(0, float(h["F"]) + 0.4, -float(h["L"]) * 0.5 + 0.1))
	_beam(k, "timber", Vector3(0, dy + 0.5, 3.75), Vector3(0, dy + 0.75, 2.6), 0.04)
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, dy - 0.6, 4.05)), Vector3(0.06, 1.4, 0.5), Color(0.6, 0.5, 0.4))
	# Catch: baskets, a heap of net, barrels, a coil of line.
	_net(k, Vector3(-0.4, dy, 1.6))
	_barrel(k, Vector3(0.75, dy, 1.4), 0.25, 0.65)
	_barrel(k, Vector3(0.7, dy, 2.0), 0.25, 0.65)
	_crate(k, shapes, Vector3(-0.7, dy, -0.2), 0.5, 0.2)
	_coil(k, Vector3(0.5, dy, -2.4), 0.24)
	_rails(k, shapes, h, dy, 0.35, true, 0.03, 0.93, 0.5)

## A small gaff sloop, as her icon: a white planked hull with a varnished sheer strake and
## a brown bottom, a deep keel, a cuddy cabin with round ports and a hatch, a gaff
## mainsail on a boom over the cockpit, a jib to the stem, a tiller on a transom rudder.
static func _sloop(k: MeshKit, shapes: Array, r: RandomNumberGenerator, root: Node3D) -> void:
	var h: Dictionary = HULLS["sloop"]
	var L: float = h["L"]
	var dy: float = h["deck"]
	var wood := Color(0.62, 0.4, 0.22)
	var white := Color(0.93, 0.91, 0.86)
	_deck(k, shapes, h, dy, "planks", 0.03, 0.96, Color(0.78, 0.66, 0.5))
	# Varnished sheer strake and toe rail along each side.
	for side in [1.0, -1.0]:
		var prev := Vector3.INF
		for i in 25:
			var u := lerpf(0.02, 0.985, float(i) / 24.0)
			var q := _hull_pt(h, u, 1.0)
			var p := Vector3(q.x * side, q.y - 0.02, q.z)
			if prev != Vector3.INF:
				_beam(k, "timber", prev, p, 0.045, 6)
				_beam(k, "timber", prev + Vector3(-side * 0.06, 0.07, 0), p + Vector3(-side * 0.06, 0.07, 0), 0.025, 5)
			prev = p
	# The keel: a deep fin under the middle, ballast at its foot.
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, -float(h["D"]) - 0.25, 0.3)), Vector3(0.14, 0.6, 3.6), wood.darkened(0.3))
	k.box("iron", Transform3D(Basis.IDENTITY, Vector3(0, -float(h["D"]) - 0.5, 0.3)), Vector3(0.2, 0.16, 3.2), Color(0.3, 0.29, 0.28))
	# Cuddy cabin forward of the cockpit: white sides, round ports, a varnished hatch.
	var cz := -0.6
	var cl := 2.2
	var cw := _width_at(h, 0.5 - cz / L, dy) * 1.25
	_solid(k, shapes, "painted_planks", Vector3(0, dy + 0.3, cz), Vector3(cw, 0.6, cl), white)
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.63, cz)), Vector3(cw + 0.08, 0.06, cl + 0.08), wood)
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.69, cz - 0.3)), Vector3(0.6, 0.08, 0.6), wood)
	for side in [1.0, -1.0]:
		for z in [cz - 0.55, cz + 0.45]:
			var at := Vector3(side * (cw * 0.5 + 0.005), dy + 0.33, z)
			k.cylinder("iron", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at), 0.085, 0.085, 0.03, 12, true, 0.0, 1, Color(0.72, 0.55, 0.3))
			k.cylinder("screen", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(side * 0.012, 0, 0)), 0.06, 0.06, 0.02, 12)
	# Cabin door in the aft end (into the cuddy), and cockpit benches either side.
	k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, dy + 0.27, cz + cl * 0.5 + 0.01)), Vector3(0.55, 0.5, 0.03), wood)
	for side in [1.0, -1.0]:
		var bw := _width_at(h, 0.5 - 2.4 / L, dy) - 0.3
		_solid(k, shapes, "planks", Vector3(side * bw, dy + 0.2, 2.4), Vector3(0.38, 0.4, 2.2), wood.lightened(0.15))
	# Mast through the cabin top, shrouds to the rail, forestay and backstay.
	var mast := Vector3(0, dy, -1.2)
	var top := 8.4
	_beam(k, "spar", mast, mast + Vector3(0, top, 0), 0.08)
	k.cylinder("spar", Transform3D(Basis.IDENTITY, mast + Vector3(0, top + 0.05, 0)), 0.06, 0.04, 0.12, 8)
	for side in [1.0, -1.0]:
		var foot := _hull_pt(h, 0.5 - (mast.z + 0.25) / L, 1.0)
		_line(k, mast + Vector3(0, top - 0.6, 0), Vector3(side * (foot.x - 0.05), foot.y + 0.05, mast.z + 0.25), 0.012)
	var stem := _hull_pt(h, 0.995, 1.0) + Vector3(0, 0.05, 0.05)
	var transom := _hull_pt(h, 0.0, 1.0)
	var head := mast + Vector3(0, top - 0.5, 0)
	_line(k, head, stem, 0.012)
	_line(k, mast + Vector3(0, top, 0), Vector3(0, transom.y + 0.1, transom.z - 0.05), 0.01)
	var rig := _rig(root)
	var cream := Color(0.88, 0.83, 0.72)
	var boom_y := 1.15
	var aft := transom.z - mast.z - 0.2
	rig.add_gaff(mast, Vector3(0, boom_y, 0.08), Vector3(0, top - 2.2, 0.08), Vector3(0, top + 0.2, aft * 0.62), Vector3(0, boom_y + 0.1, aft),
		0.55, cream, [["clew", Vector3(0, dy + 0.15, transom.z - 0.35)]])
	rig.add_jib(stem + Vector3(0, 0.1, 0.1), head + Vector3(0, -0.15, 0.1), Vector3(0, dy + 1.05, mast.z + 0.9), 0.4, cream,
		[["clew", Vector3(0.55, dy + 0.1, mast.z + 1.6)]])
	# Rudder on the transom and its tiller across the cockpit.
	var rz := transom.z + 0.08
	k.box("planks", Transform3D(Basis.IDENTITY, Vector3(0, -0.15, rz + 0.22)), Vector3(0.07, 1.3, 0.45), wood.darkened(0.15))
	_beam(k, "timber", Vector3(0, dy + 0.45, rz + 0.05), Vector3(0, dy + 0.62, rz - 1.25), 0.035)
	# A coil of line and a bucket in the cockpit.
	_coil(k, Vector3(-0.3, dy, 3.4), 0.18)
	if r.randf() < 0.6:
		_barrel(k, Vector3(0.35, dy, 3.3), 0.16, 0.3)

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
	# The poop runs on aft over the stern as an overhanging gallery (z 9.1 to `ze`),
	# narrowing toward its end and flaring out a little toward the top, on knees.
	var ze := 11.5
	var zt := float(h["L"]) * (0.5 + float(h.get("rake", 0.0))) # the stern's top edge
	var yb := float(h["F"]) + float(h["rise"]) - 0.15 # the gallery's underside
	var gw := func(z: float, y: float) -> float: return lerpf(hx, hx * 0.72, (z - 9.1) / (ze - 9.1)) + (y - yb) / (top - yb) * 0.12
	var gc := Color(0.6, 0.48, 0.37)
	for s in [-1.0, 1.0]:
		var a := Vector3(s * gw.call(9.1, yb), yb, 9.1)
		var b := Vector3(s * gw.call(ze, yb), yb, ze)
		var c := Vector3(s * gw.call(ze, top), top, ze)
		var d := Vector3(s * gw.call(9.1, top), top, 9.1)
		_quad_out(k, "planks", a, b, c, d, Vector3(s, 0, 0), gc)
		# A wale along the gallery and its corner post.
		_beam(k, "timber", Vector3(s * (gw.call(9.1, yb + 0.9) + 0.03), yb + 0.9, 9.1), Vector3(s * (gw.call(ze, yb + 0.9) + 0.03), yb + 0.9, ze), 0.06)
		_beam(k, "timber", b + Vector3(0, -0.08, 0.03), c + Vector3(0, 0.05, 0.03), 0.08)
		# Knees: curved brackets from the stern up under the overhang, three timbers each.
		var kx: float = s * 0.95
		var pts := [Vector3(kx, yb - 1.0, zt - 0.3), Vector3(kx, yb - 0.55, zt + 0.25), Vector3(kx, yb - 0.2, ze - 0.55), Vector3(kx, yb, ze - 0.1)]
		for i in 3:
			_beam(k, "timber", pts[i], pts[i + 1], 0.07)
	var hb: float = gw.call(ze, yb)
	var ht: float = gw.call(ze, top)
	_quad_out(k, "planks", Vector3(-hb, yb, ze), Vector3(hb, yb, ze), Vector3(ht, top, ze), Vector3(-ht, top, ze), Vector3.BACK, gc)
	_quad_out(k, "planks", Vector3(-hx, yb, 9.1), Vector3(hx, yb, 9.1), Vector3(hb, yb, ze), Vector3(-hb, yb, ze), Vector3.DOWN, gc.darkened(0.25))
	_quad_out(k, "wood_floor", Vector3(-hx, top, 9.1), Vector3(hx, top, 9.1), Vector3(ht, top, ze), Vector3(-ht, top, ze), Vector3.UP, Color(0.74, 0.62, 0.5))
	var slab := BoxShape3D.new()
	slab.size = Vector3(hx + ht, 0.12, ze - 9.1)
	shapes.append([slab, Transform3D(Basis.IDENTITY, Vector3(0, top - 0.06, (9.1 + ze) * 0.5))])
	# Shuttered stern windows and a moulded cap across the gallery's end.
	for s in [-1.0, 1.0]:
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * 0.7, yb + 0.75, ze + 0.03)), Vector3(0.55, 0.5, 0.06), Color(0.3, 0.22, 0.16))
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * 0.7, yb + 0.75, ze + 0.06)), Vector3(0.65, 0.07, 0.04))
	k.box("timber", Transform3D(Basis.IDENTITY, Vector3(0, top - 0.02, ze + 0.06)), Vector3(ht * 2.0 + 0.2, 0.18, 0.14))
	# Framing on the castle's plain walls: corner posts, wales along its sides, a moulded
	# cap under the rail.
	for s in [-1.0, 1.0]:
		for z in [4.9, 9.1]:
			_beam(k, "timber", Vector3(s * (hx + 0.04), dy - 0.2, z), Vector3(s * (hx + 0.04), top + 0.05, z), 0.09)
		for y in [dy + 0.9, dy + 1.8]:
			k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * (hx + 0.05), y, 7.0)), Vector3(0.08, 0.12, 4.25))
		k.box("timber", Transform3D(Basis.IDENTITY, Vector3(s * (hx + 0.07), top - 0.02, 7.0)), Vector3(0.14, 0.18, 4.35))
	# The poop rail, round the castle and out along the gallery to its end.
	for s in [-1.0, 1.0]:
		var rail := [Vector3(s * hx, top, 4.9), Vector3(s * hx, top, 9.1), Vector3(s * ht, top, ze)]
		for i in 2:
			_beam(k, "timber", rail[i], rail[i + 1], 0.06)
			_beam(k, "timber", rail[i] + Vector3(0, 0.9, 0), rail[i + 1] + Vector3(0, 0.9, 0), 0.06)
		for z in [4.9, 6.3, 7.7, 9.1, (9.1 + ze) * 0.5, ze]:
			var x: float = s * (hx if z <= 9.1 else lerpf(hx, ht, (z - 9.1) / (ze - 9.1)))
			_beam(k, "timber", Vector3(x, top, z), Vector3(x, top + 0.9, z), 0.05)
		var rs := BoxShape3D.new()
		rs.size = Vector3(0.1, 1.0, ze - 4.9)
		var mid := Vector3(s * (hx + ht) * 0.5, top + 0.5, (4.9 + ze) * 0.5)
		shapes.append([rs, Transform3D(Basis.IDENTITY, mid)])
	_beam(k, "timber", Vector3(-ht, top + 0.9, ze), Vector3(ht, top + 0.9, ze), 0.06)
	var back := BoxShape3D.new()
	back.size = Vector3(ht * 2.0, 1.0, 0.1)
	shapes.append([back, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.5, ze))])
	# The tiller, from the helm to the rudder's head.
	_beam(k, "timber", Vector3(0, top + 0.85, 8.1), Vector3(0, top + 0.5, zt - 0.35), 0.06)
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
	# Its rail: posts and a top rail down both sides, open at the after end for the stair.
	for s in [-1.0, 1.0]:
		var x: float = s * 1.52
		_beam(k, "timber", Vector3(x, fc + 0.85, -8.6), Vector3(x, fc + 0.85, -6.6), 0.05)
		for z in [-8.6, -7.6, -6.6]:
			_beam(k, "timber", Vector3(x, fc, z), Vector3(x, fc + 0.88, z), 0.045)
		var rs := BoxShape3D.new()
		rs.size = Vector3(0.1, 0.9, 2.0)
		shapes.append([rs, Transform3D(Basis.IDENTITY, Vector3(x, fc + 0.45, -7.6))])
	_beam(k, "timber", Vector3(0, float(h["F"]) + float(h["rise"]) * 1.3 + 0.1, -10.0), Vector3(0, float(h["F"]) + 2.6, -13.2), 0.14)
	# Mainmast, square sail on its yard (BoatRig), shrouds and stays; a crow's nest.
	var mast := Vector3(0, dy, -0.8)
	_beam(k, "spar", mast - Vector3(0, 1.5, 0), mast + Vector3(0, 16.5, 0), 0.24, 10)
	k.cylinder("planks", Transform3D(Basis.IDENTITY, mast + Vector3(0, 13.4, 0)), 0.8, 0.9, 0.9, 12, true, 0.0, 1, Color(0.65, 0.52, 0.4))
	var rig := _rig(root)
	rig.add_square(mast, 12.6, 4.2, 5.2, 0.4, 2.7, Color(0.9, 0.84, 0.72),
		[["clew_l", Vector3(-2.2, dy + 1.0, 3.8)], ["clew_r", Vector3(2.2, dy + 1.0, 3.8)],
		["arm_l", Vector3(-(hx - 0.1), top + 0.9, 8.6)], ["arm_r", Vector3(hx - 0.1, top + 0.9, 8.6)],
		["clew_l", Vector3(-1.4, dy + 1.0, -6.0)], ["clew_r", Vector3(1.4, dy + 1.0, -6.0)]])
	for s in [-1.0, 1.0]:
		# Shrouds to deadeyes on the rail, with ratlines across them to climb to the top.
		var feet: Array = []
		for z in [-2.2, -1.3, -0.4, 0.5]:
			var u: float = 0.5 - z / float(h["L"])
			var foot := Vector3(s * (_width_at(h, u, dy + 0.9) + 0.05), dy + 1.0, z)
			feet.append(foot)
			_line(k, mast + Vector3(0, 13.2, 0), foot, 0.02)
			k.cylinder("timber", Transform3D(Basis(Vector3.BACK, PI * 0.5), foot + Vector3(0, 0.1, 0)), 0.08, 0.08, 0.06, 8, true)
		var head := mast + Vector3(0, 13.2, 0)
		for n in range(1, 24):
			var t := float(n) / 24.0
			var a: Vector3 = (feet[0] as Vector3).lerp(head, t)
			var b: Vector3 = (feet[3] as Vector3).lerp(head, t)
			_line(k, a, b, 0.008)
		# (Sheets, braces and the yard's lifts are BoatRig's: they move with the sail.)
	# Halyard down the mast to a cleat.
	_line(k, mast + Vector3(0.28, 16.0, 0.1), mast + Vector3(0.28, 1.2, 0.1), 0.014)
	_line(k, mast + Vector3(0, 16.2, 0), Vector3(0, float(h["F"]) + 2.5, -13.1), 0.025)
	_line(k, mast + Vector3(0, 15.8, 0), Vector3(0, top + 0.9, 9.1), 0.02)
	# Anchor cable running from the bow down into the water (only while she lies at anchor).
	_anchor_cable(root, "rope", Vector3(1.0, float(h["F"]) + 1.2, -9.4), Vector3(2.4, -3.0, -15.5), 0.06)
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
	_nav_screen(k, Vector3(0.45, dy + 1.04, 0.15), 0.6, 0.7, 0.32)
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
	# A white cool box with a grey lid and rope handles.
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(-0.6, dy + 0.22, 1.7)), Vector3(0.7, 0.4, 0.45), Color(0.9, 0.9, 0.88))
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(-0.6, dy + 0.445, 1.7)), Vector3(0.72, 0.05, 0.47), Color(0.55, 0.57, 0.6))
	for s in [-1.0, 1.0]:
		_line(k, Vector3(-0.6 + s * 0.36, dy + 0.3, 1.6), Vector3(-0.6 + s * 0.36, dy + 0.3, 1.8), 0.012)
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
	# A painted steel deck, as working boats have (not bare plate).
	_deck(k, shapes, h, dy, "painted", 0.02, 0.96, Color(0.42, 0.47, 0.45))
	_rails(k, shapes, h, dy, 1.05, false, 0.02, 0.97, 0.62)
	# Portholes along both sides of the hull, between the boot top and the deck.
	for side in [-1.0, 1.0]:
		for i in 7:
			var u := lerpf(0.3, 0.82, float(i) / 6.0)
			var y := 1.25
			var p := Vector3(side * (_width_at(h, u, y) + 0.01), y, L * (0.5 - u))
			k.cylinder("metal", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p), 0.17, 0.17, 0.04, 14, true, 0.0, 1, Color(0.8, 0.8, 0.8))
			k.cylinder("screen", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), p + Vector3(side * 0.02, 0, 0)), 0.12, 0.12, 0.02, 14)
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
		_nav_screen(k, Vector3(x, bf + 1.05, -1.85), 0.5, 1.0, 0.4)
	_helm_wheel(k, Vector3(0.0, bf + 1.12, -1.6))
	# Twin throttles on the console's starboard side, a radio handset to port.
	for x in [0.62, 0.78]:
		var lever := Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(x, bf + 1.06, -1.85))
		k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(0.7, bf + 1.02, -1.85)), Vector3(0.36, 0.06, 0.24))
		_beam(k, "metal", lever.origin, lever.origin + lever.basis.y * 0.22, 0.012)
		k.sphere("rubber", Transform3D(Basis.IDENTITY, lever.origin + lever.basis.y * 0.24), 0.035, 5, 8, 0.0, 1.0, Color(0.6, 0.1, 0.08) if x < 0.7 else Color(0.1, 0.3, 0.6))
	k.box("metal_dark", Transform3D(Basis.IDENTITY, Vector3(-0.8, bf + 1.05, -1.88)), Vector3(0.18, 0.08, 0.1))
	_bridge_walls(k, shapes, br_c, br)
	for x in [-0.9, 0.9]:
		_helm_chair(k, Vector3(x, bf, -0.9))
	_lantern(root, k, Vector3(0, bf + br.y - 0.06, -0.6), true)
	# Lab below: benches with sample tanks, a terminal, bunks along the side, a locker.
	var lf := dy
	_solid(k, shapes, "hull_paint", Vector3(2.0, lf + 0.45, 0.0), Vector3(0.9, 0.9, 4.0), Color(0.75, 0.77, 0.8))
	k.box("metal_dark", Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(2.3, lf + 1.35, -1.0)), Vector3(0.03, 0.5, 0.8))
	var lab_b := Basis(Vector3.FORWARD, 0.25)
	ScreenLook.face(k, Transform3D(lab_b * Basis(Vector3.UP, -PI / 2), Vector3(2.3, lf + 1.35, -1.0) + lab_b * Vector3(-0.017, 0, 0)), 0.76, 0.46, "monitor", "boat")
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
	# Radar mast, dome and antennas on the wheelhouse roof, which has a rail round it
	# (the "monkey island"); the funnel stands on the bridge deck behind the wheelhouse.
	var roof := bdeck + br.y + 0.12
	var rx := br.x * 0.5 - 0.1
	var rz0 := br_c.z - br.z * 0.5 + 0.1
	var rz1 := br_c.z + br.z * 0.5 - 0.1
	var corners := [Vector3(-rx, roof, rz0), Vector3(rx, roof, rz0), Vector3(rx, roof, rz1), Vector3(-rx, roof, rz1)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		for hgt in [0.5, 1.0]:
			_beam(k, "metal", a + Vector3(0, hgt, 0), b + Vector3(0, hgt, 0), 0.022)
		var n := ceili(a.distance_to(b) / 1.2)
		for j in n + 1:
			var q := a.lerp(b, float(j) / n)
			_beam(k, "metal", q, q + Vector3(0, 1.0, 0), 0.02)
	k.box("hull_paint", Transform3D(Basis.IDENTITY, Vector3(0, roof - 0.04, br_c.z - br.z * 0.5 - 0.25)), Vector3(br.x + 0.2, 0.08, 0.6), Color(0.94, 0.94, 0.95))
	var fun := Vector3(1.4, bdeck, 3.9)
	k.cylinder("hull_paint", Transform3D(Basis.IDENTITY, fun + Vector3(0, 1.2, 0)), 0.42, 0.36, 2.4, 14, true, 0.0, 1, Color(0.94, 0.94, 0.95))
	k.cylinder("metal_dark", Transform3D(Basis.IDENTITY, fun + Vector3(0, 2.65, 0)), 0.36, 0.34, 0.5, 14)
	var fs := CylinderShape3D.new()
	fs.radius = 0.45
	fs.height = 2.9
	shapes.append([fs, Transform3D(Basis.IDENTITY, fun + Vector3(0, 1.45, 0))])
	_beam(k, "metal", Vector3(0, roof, -0.2), Vector3(0, roof + 3.8, -0.2), 0.1, 8)
	_beam(k, "metal", Vector3(-1.2, roof + 2.6, -0.2), Vector3(1.2, roof + 2.6, -0.2), 0.05)
	k.box("metal_dark", Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(0, roof + 3.95, -0.2)), Vector3(2.0, 0.12, 0.25))
	k.sphere("hull_paint", Transform3D(Basis.IDENTITY, Vector3(1.6, roof + 0.4, 0.6)), 0.45, 8, 12, 0.0, 1.0, Color(0.95, 0.95, 0.96))
	for x in [-1.8, -1.3]:
		_beam(k, "metal", Vector3(x, roof, 0.9), Vector3(x, roof + 2.6, 0.9), 0.015)
	k.box("glow_red", Transform3D(Basis.IDENTITY, Vector3(0, roof + 3.85, -0.2)), Vector3(0.08, 0.08, 0.08))
	var yellow := Color(0.95, 0.72, 0.08)
	# Aft working deck: an A-frame crane over the stern with a sampling cage, winch drum,
	# boxes of gear, a rescue boat in its cradle.
	var stern := L * 0.5
	for s in [-1.0, 1.0]:
		_beam(k, "painted", Vector3(s * 2.5, dy, stern - 1.2), Vector3(s * 1.2, dy + 4.6, stern + 0.4), 0.13, 8, yellow)
	_beam(k, "painted", Vector3(-1.3, dy + 4.55, stern + 0.4), Vector3(1.3, dy + 4.55, stern + 0.4), 0.13, 8, yellow)
	k.box("painted", Transform3D(Basis.IDENTITY, Vector3(0, dy + 4.3, stern + 0.4)), Vector3(0.4, 0.3, 0.3), Color(0.2, 0.22, 0.25))
	_line(k, Vector3(0, dy + 4.5, stern + 0.4), Vector3(0, dy + 1.4, stern + 0.6), 0.015)
	# The sampling rosette hung under it: a ring of grey sampling bottles in an open
	# steel frame round the instrument.
	var ro := Vector3(0, dy + 0.75, stern + 0.6)
	for y in [0.0, 0.85]:
		k.cylinder("metal", Transform3D(Basis.IDENTITY, ro + Vector3(0, y, 0)), 0.45, 0.45, 0.04, 16, false)
	for i in 8:
		var a := TAU * i / 8.0
		var q := ro + Vector3(cos(a) * 0.36, 0.42, sin(a) * 0.36)
		k.cylinder("hull_paint", Transform3D(Basis.IDENTITY, q), 0.07, 0.07, 0.62, 10, true, 0.0, 1, Color(0.7, 0.72, 0.74))
		if i % 2 == 0:
			_beam(k, "metal", ro + Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), ro + Vector3(cos(a) * 0.45, 0.85, sin(a) * 0.45), 0.012)
	k.cylinder("metal_dark", Transform3D(Basis.IDENTITY, ro + Vector3(0, 0.35, 0)), 0.1, 0.1, 0.6, 10)
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
	_anchor_cable(root, "metal_dark", Vector3(0.9, float(h["F"]) + 1.0, -11.2), Vector3(2.7, -3.2, -18.0), 0.05)
	_beam(k, "metal", Vector3(0, dy, -9.5), Vector3(0, dy + 6.0, -9.5), 0.08, 8)
	k.box("lens", Transform3D(Basis.IDENTITY, Vector3(0, dy + 6.05, -9.5)), Vector3(0.1, 0.1, 0.1))
	k.box("glow_red", Transform3D(Basis.IDENTITY, Vector3(-2.85, bdeck + 1.1, -1.0)), Vector3(0.05, 0.1, 0.18))
	k.box("lens", Transform3D(Basis.IDENTITY, Vector3(2.85, bdeck + 1.1, -1.0)), Vector3(0.05, 0.1, 0.18))
	# Boarding: a stair down the starboard side to a platform at the water.
	var gap_z := L * (0.5 - 0.62)
	var hw2 := _width_at(h, 0.62, dy)
	_solid(k, shapes, "metal", Vector3(hw2 + 1.0, -0.2, gap_z + 3.4), Vector3(1.2, 0.12, 1.2))
	_stairs(k, shapes, Vector3(hw2 + 0.9, -0.15, gap_z + 2.8), Vector3(hw2 + 0.25, dy, gap_z), 0.9, "metal")
