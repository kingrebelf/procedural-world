class_name BoatWake
extends MeshInstance3D
## The track a boat leaves on the water (BoatNode): laid in world space, so it curves with
## her course and stays where she was rather than swinging round with the hull. A Kelvin
## wake: two arms spreading back from the bow at 19.5 degrees either side of her track,
## made of short feathered crests; the curved transverse waves between them, as far apart
## as her speed sets (2 pi v^2 / g); and a churned wash straight down the middle that
## widens and settles. All of it fades over a minute or so. Drawn by boat_water.gdshader
## on the swell: COLOR.r 0.5 the arms, 0.75 the transverse waves, 1 the wash; COLOR.g how
## strong it still is. UV.y runs across each strip; UV2 is metres back along the track
## (x) and the transverse waves' phase (y).

const STEP := 1.5 ## metres of track between kept points
const MAX := 80 ## points kept (STEP * MAX metres of track at most)
const LIFE := 75.0 ## seconds a stretch of wake takes to settle
const KELVIN := 0.354 ## tan(19.47 degrees)

var length := 4.0 ## hull length
var beam := 1.0 ## half-beam at the waterline
var churn := 0.6 ## how hard the wash is churned (a propeller's is strongest)

var _pts: Array = [] ## newest first: [Vector2 at, Vector2 heading, float strength, float speed, float born]
var _head: Array = []
var _rebuild := 0.0
var _mesh := ArrayMesh.new()

static func make(kind: String) -> BoatWake:
	var w := BoatWake.new()
	w.name = "BoatWake"
	w.top_level = true
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.visibility_range_end = 900.0
	var d: Dictionary = Boats.KINDS[kind]
	w.length = d["len"]
	var h: Dictionary = BoatModel.HULLS.get(kind, {})
	w.beam = BoatModel._width_at(h, 0.45, 0.0) if not h.is_empty() else w.length * 0.2
	w.churn = 1.0 if int(d["era"]) == Eras.SCIFI else (0.35 if kind in ["raft", "life_raft"] else 0.6)
	w.mesh = w._mesh
	w.material_override = BoatWater.material()
	return w

## Called every physics frame with where her stern is, which way she heads, her speed in
## m/s and `strength` 0..1 (how much wake that speed makes for her).
func feed(stern: Vector2, heading: Vector2, speed: float, strength: float, delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var now := Time.get_ticks_msec() / 1000.0
	# A jump (put back on her loop, or teleported) starts a fresh track.
	if not _pts.is_empty() and (_pts[0][0] as Vector2).distance_to(stern) > STEP * 8.0:
		_pts.clear()
	_head = [stern, heading, strength, speed, now]
	if speed > 0.05 and (_pts.is_empty() or (_pts[0][0] as Vector2).distance_to(stern) >= STEP):
		_pts.push_front(_head.duplicate())
		if _pts.size() > MAX:
			_pts.resize(MAX)
	while not _pts.is_empty() and now - float(_pts[-1][4]) > LIFE:
		_pts.pop_back()
	_rebuild -= delta
	if _rebuild <= 0.0:
		_rebuild = 0.05
		_build(now)

func _build(now: float) -> void:
	_mesh.clear_surfaces()
	if _head.is_empty():
		return
	# The wake starts at her bow: two rows ahead of the stern along her heading.
	var hd0: Vector2 = _head[1]
	var track: Array = []
	for k in [0.9, 0.45]:
		var r: Array = _head.duplicate()
		r[0] = (_head[0] as Vector2) + hd0 * length * k
		track.append(r)
	track.append(_head)
	track.append_array(_pts)
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	# Metres back along the track from the bow, and the transverse waves' phase there.
	var s := 0.0
	var ph := 0.0
	var rows: Array = [] # per point: [centre, side, back, phase, fade]
	for i in track.size():
		var p: Array = track[i]
		if i > 0:
			var ds := (p[0] as Vector2).distance_to(track[i - 1][0])
			s += ds
			ph += ds / maxf(TAU * pow(float(p[3]), 2.0) / 9.8, 1.2)
		var hd: Vector2 = p[1]
		var side := Vector2(-hd.y, hd.x)
		var age := now - float(p[4])
		var fade := float(p[2]) * pow(clampf(1.0 - age / LIFE, 0.0, 1.0), 1.6)
		rows.append([p[0], side, s, ph, fade])
	# Arms: either side of the track, further out the further back.
	for sd in [1.0, -1.0]:
		_strip(v, c, uv, uv2, idx, rows, 0.5, func(r: Array) -> Array:
			var off := beam * 0.35 + float(r[2]) * KELVIN
			var w := 0.5 + length * 0.05 + float(r[2]) * 0.07
			return [(r[0] as Vector2) + (r[1] as Vector2) * sd * off, w])
	# Transverse waves: spanning between the arms.
	_strip(v, c, uv, uv2, idx, rows.slice(1), 0.75, func(r: Array) -> Array:
		return [r[0], (beam * 0.35 + float(r[2]) * KELVIN) * 2.0])
	# The wash: straight down the track from her stern, spreading as it settles.
	_strip(v, c, uv, uv2, idx, rows.slice(2), 1.0, func(r: Array) -> Array:
		return [r[0], beam * 1.6 + (float(r[2]) - length * 0.9) * 0.1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var n := PackedVector3Array()
	n.resize(v.size())
	n.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = n
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

## One strip along the track: `at` gives [centre, width] for a row. The wash's strength
## fades faster than the arms', the transverse waves only show close behind her.
func _strip(v: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array,
		idx: PackedInt32Array, rows: Array, part: float, at: Callable) -> void:
	var base := v.size()
	for r in rows:
		var cw: Array = at.call(r)
		var ctr: Vector2 = cw[0]
		var half := float(cw[1]) * 0.5
		var side: Vector2 = r[1]
		var f := float(r[4])
		if part > 0.9:
			f *= churn * clampf(1.0 - (float(r[2]) - length) / 90.0, 0.0, 1.0)
		elif part > 0.6:
			f *= clampf(1.0 - (float(r[2]) - length) / 45.0, 0.0, 1.0)
		for k in 2:
			var e := ctr + side * half * (1.0 if k == 0 else -1.0)
			v.append(Vector3(e.x, 0.0, e.y))
			c.append(Color(part, f, 0.0))
			uv.append(Vector2(0.0, float(k)))
			uv2.append(Vector2(float(r[2]), float(r[3])))
	for i in rows.size() - 1:
		var a := base + i * 2
		idx.append_array([a, a + 2, a + 3, a, a + 3, a + 1])
