class_name BoatRig
extends Node3D
## A boat's sails as live parts, not baked into the hull: each sail turns on its mast to
## the wind, fills on the lee side or flaps when the wind is too far ahead to draw, and is
## taken in to its yard while she lies at anchor. Square sails (raft, cog) brace their yard
## round, the windward yardarm going aft; a lugsail (fishing boat) swings out to leeward
## like a door, belly away from the wind, and comes across when she turns through the wind.
## Sheets and braces run from the sail's corners to the deck and follow it.
##
## Local space is the boat's (bow toward -z, starboard +x). BoatNode feeds trim() the wind
## as the boat feels it every frame; tools can call it once for a still picture.

const SQUARE := "square"
const LUG := "lug"
const FURL_RATE := 0.3 ## share of a full set/furl per second
const LINES_EVERY := 0.2 ## seconds between rebuilding the sheets while the sail moves

## Per sail: {type, pivot (Node3D on the mast), cloth (Node3D the sail hangs from, scaled
## to fill and furl), bundle (furled cloth), lines (MeshInstance3D), ropes ([space, local
## point, deck point]), swing (current turn on the mast), fill, side (+1 / -1: which side
## the cloth is out on), max_turn}
var sails: Array = []
var furl := 0.0 ## 0 set .. 1 furled
var _t := 0.0
var _lines_t := 0.0
var _flap := 0.0

func _init() -> void:
	name = "Rig"

## A square sail on a yard across the mast at `mast` (deck foot), hung `ahead` metres
## forward of it: cloth from `top` down to `foot` (heights above the foot), `half_w` each
## side, bellied forward by `belly`. `ropes`: [[clew/yardarm id, deck point]], ids "clew_l",
## "clew_r", "arm_l", "arm_r".
func add_square(mast: Vector3, top: float, foot: float, half_w: float, ahead: float, belly: float, col: Color, ropes: Array, max_turn := 0.65) -> void:
	var pivot := Node3D.new()
	pivot.position = mast
	add_child(pivot)
	var z := -ahead
	# The yard, its lifts and the halyard turn with the sail.
	var yk := MeshKit.new(3)
	BoatModel._beam(yk, "spar", Vector3(-half_w - 0.25, top, z), Vector3(half_w + 0.25, top, z), clampf(half_w * 0.017, 0.035, 0.1))
	for s in [-1.0, 1.0]:
		BoatModel._line(yk, Vector3(0, top + half_w * 0.6, 0), Vector3(s * (half_w + 0.2), top, z), clampf(half_w * 0.002, 0.006, 0.012))
	_mesh(pivot, "Yard", yk)
	# The cloth hangs from the yard: its node sits on the yard so taking it in (scaling y)
	# gathers it up to the yard, and flattening it (scaling z) spills the wind.
	var cloth := Node3D.new()
	cloth.position = Vector3(0, top, z)
	pivot.add_child(cloth)
	var ck := MeshKit.new(4)
	_cloth(ck, [Vector3(-half_w, 0, 0), Vector3(half_w, 0, 0), Vector3(half_w * 0.94, foot - top, 0), Vector3(-half_w * 0.94, foot - top, 0)],
		Vector3(0, 0, -1), belly, col, 0.7)
	_mesh(cloth, "Cloth", ck)
	var bk := MeshKit.new(5)
	BoatModel._beam(bk, "sail", Vector3(-half_w, top - 0.1, z + 0.04), Vector3(half_w, top - 0.1, z + 0.04), clampf(half_w * 0.035, 0.07, 0.2), 8)
	for i in 5:
		var x := lerpf(-half_w * 0.9, half_w * 0.9, float(i) / 4.0)
		bk.cylinder("rope", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, top - 0.1, z + 0.04)), half_w * 0.04, half_w * 0.04, 0.04, 8)
	var bundle := _mesh(pivot, "Furled", bk)
	var pts := {"clew_l": ["cloth", Vector3(-half_w * 0.94, foot - top, 0)], "clew_r": ["cloth", Vector3(half_w * 0.94, foot - top, 0)],
		"arm_l": ["pivot", Vector3(-half_w - 0.2, top, z)], "arm_r": ["pivot", Vector3(half_w + 0.2, top, z)]}
	_add(SQUARE, pivot, cloth, bundle, ropes, pts, max_turn)

## A lugsail on a slanted yard hung on the mast at `mast`: four corners in mast-local space
## (tack forward and low, throat at the yard's fore end, peak at its aft end, clew aft and
## low). The cloth lies along the boat and bellies out to leeward. `ropes` as add_square,
## ids "clew", "tack".
func add_lug(mast: Vector3, tack: Vector3, throat: Vector3, peak: Vector3, clew: Vector3, belly: float, col: Color, ropes: Array, max_turn := 1.25) -> void:
	var pivot := Node3D.new()
	pivot.position = mast
	add_child(pivot)
	var yk := MeshKit.new(3)
	var ext := (peak - throat).normalized() * 0.2
	BoatModel._beam(yk, "spar", throat - ext, peak + ext, 0.045)
	BoatModel._line(yk, Vector3(0, peak.y + 0.1, 0.08), throat.lerp(peak, 0.35), 0.01)
	_mesh(pivot, "Yard", yk)
	var cloth := Node3D.new()
	pivot.add_child(cloth)
	var ck := MeshKit.new(4)
	_cloth(ck, [throat, peak, clew, tack], Vector3(1, 0, 0), belly, col, 0.65)
	_mesh(cloth, "Cloth", ck)
	var bk := MeshKit.new(5)
	BoatModel._beam(bk, "sail", throat + Vector3(0, -0.12, 0), peak + Vector3(0, -0.12, 0), 0.13, 8)
	var bundle := _mesh(pivot, "Furled", bk)
	var pts := {"clew": ["cloth", clew], "tack": ["cloth", tack]}
	_add(LUG, pivot, cloth, bundle, ropes, pts, max_turn)
	# A lug's cloth is gathered toward its yard, not up a vertical: hang the node on the
	# yard's middle so the scaling shrinks the sail toward it.
	var mid := throat.lerp(peak, 0.5)
	cloth.position = mid
	(cloth.get_child(0) as Node3D).position = -mid
	sails[-1]["pts"]["clew"] = ["cloth", clew - mid]
	sails[-1]["pts"]["tack"] = ["cloth", tack - mid]

func _add(type: String, pivot: Node3D, cloth: Node3D, bundle: Node3D, ropes: Array, pts: Dictionary, max_turn: float) -> void:
	var lines := MeshInstance3D.new()
	lines.name = "Lines"
	lines.visibility_range_end = 500.0
	add_child(lines)
	sails.append({"type": type, "pivot": pivot, "cloth": cloth, "bundle": bundle, "lines": lines, "ropes": ropes, "pts": pts,
		"swing": 0.0, "fill": 1.0, "side": 1.0, "max_turn": max_turn, "drawn": Vector3.INF})
	bundle.visible = false

func _mesh(parent: Node3D, n: String, k: MeshKit) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = k.commit(BoatModel.get_mat)
	mi.visibility_range_end = 1300.0
	parent.add_child(mi)
	return mi

## Sail cloth over four corners (top-left, top-right, bottom-right, bottom-left), bellied
## along `out`: deepest a little below the middle, the edges held flat. Sewn from vertical
## cloths about `panel` metres wide, each a shade different, with a darker seam between.
static func _cloth(k: MeshKit, c: Array, out: Vector3, belly: float, col: Color, panel: float) -> void:
	var chord := ((c[1] as Vector3) - (c[0] as Vector3)).length()
	var nx := clampi(roundi(chord / panel), 6, 18)
	var ny := 9
	var pts: Array = []
	for j in ny + 1:
		var row: Array = []
		var v := float(j) / ny
		for i in nx + 1:
			var u := float(i) / nx
			var top: Vector3 = (c[0] as Vector3).lerp(c[1], u)
			var bot: Vector3 = (c[3] as Vector3).lerp(c[2], u)
			var b := belly * pow(sin(u * PI), 0.8) * sin(clampf(v * 1.05, 0.0, 1.0) * PI * 0.8 + 0.2)
			var p := top.lerp(bot, v) + out * b
			# The foot sags a little between its corners.
			p.y += (bot.y - top.y) * 0.05 * sin(u * PI) * v * v * v
			row.append(p)
		pts.append(row)
	var nrm := func(j: int, i: int) -> Vector3:
		var du: Vector3 = pts[j][mini(i + 1, nx)] - pts[j][maxi(i - 1, 0)]
		var dv: Vector3 = pts[mini(j + 1, ny)][i] - pts[maxi(j - 1, 0)][i]
		return du.cross(dv).normalized()
	for j in ny:
		for i in nx:
			var shade := col.darkened(0.035 * float(i % 2)) if i > 0 and i < nx - 1 else col.darkened(0.08)
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var cc: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			k.tri("sail", Transform3D.IDENTITY, a, b, cc, nrm.call(j, i), nrm.call(j, i + 1), nrm.call(j + 1, i + 1), shade)
			k.tri("sail", Transform3D.IDENTITY, a, cc, d, nrm.call(j, i), nrm.call(j + 1, i + 1), nrm.call(j + 1, i), shade)
	# Tabling: a doubled hem round the edge.
	for e in 4:
		BoatModel._beam(k, "sail", c[e], c[(e + 1) % 4], 0.025, 5)

## The wind as she feels it, `from` the direction it blows from in boat space (x, z) and
## `strength` 0..1, and whether she's under way (sails set) or lying at anchor (taken in).
## dt <= 0 snaps everything straight to where it ends up (for pictures). `set_turn` and
## `set_fill` (Sailing.sail_turn, how well she draws) override the trim it would choose.
func trim(from: Vector2, strength: float, under_way: bool, dt: float, set_turn := NAN, set_fill := NAN) -> void:
	var snap := dt <= 0.0
	_t += maxf(dt, 0.0)
	furl = (0.0 if under_way else 1.0) if snap else move_toward(furl, 0.0 if under_way else 1.0, dt * FURL_RATE)
	# Wind angle off the bow: 0 dead ahead, PI dead astern, + from starboard.
	var off := atan2(from.x, -from.y) if from.length() > 0.001 else PI
	var a := absf(off)
	_flap = 0.5 + 0.5 * sin(_t * (7.0 + strength * 9.0))
	for s in sails:
		var want_side: float = -signf(off) if absf(off) > 0.01 else float(s["side"])
		var turn := 0.0
		var fill := 1.0
		if s["type"] == SQUARE:
			# Braced round as the wind comes forward of the beam: the windward arm goes aft.
			turn = -signf(off) * clampf((PI - a) * 0.55, 0.0, float(s["max_turn"]))
			fill = clampf((a - 0.95) / 0.6, 0.0, 1.0)
		else:
			# Eased right out on a run, sheeted in close on the wind; it comes across
			# (gybes) only once the wind is clearly on the other quarter.
			if a < PI - 0.2 or snap:
				s["side"] = want_side
			turn = float(s["side"]) * clampf((a - 0.45) * 0.55, 0.08, float(s["max_turn"]))
			fill = clampf((a - 0.5) / 0.35, 0.0, 1.0)
		if not is_nan(set_turn):
			# Someone is working the sheet (a player's boat, Sailing): hold it where they set it.
			turn = clampf(set_turn, -float(s["max_turn"]), float(s["max_turn"]))
			fill = set_fill
			if s["type"] != SQUARE and absf(set_turn) > 0.01:
				s["side"] = signf(set_turn)
		fill *= clampf(0.35 + strength * 1.6, 0.0, 1.0)
		var k := 1.0 if snap else clampf(dt * 0.8, 0.0, 1.0)
		s["swing"] = lerp_angle(float(s["swing"]), turn, k)
		s["fill"] = lerpf(float(s["fill"]), fill, 1.0 if snap else clampf(dt * 1.5, 0.0, 1.0))
		var pivot: Node3D = s["pivot"]
		pivot.rotation.y = float(s["swing"])
		var cloth: Node3D = s["cloth"]
		# Not drawing: the cloth hangs nearly flat and shivers.
		var f := float(s["fill"])
		var depth := lerpf(0.12 + 0.1 * _flap * strength, 1.0, f)
		var gather := lerpf(1.0, 0.06, smoothstep(0.0, 1.0, furl))
		if s["type"] == SQUARE:
			cloth.scale = Vector3(1.0, gather, depth)
		else:
			# The lug's belly is along local +x: flip it to whichever side the wind fills.
			var sx := float(s["side"]) * depth
			cloth.scale = Vector3(sx if absf(sx) > 0.02 else 0.02, gather, 1.0)
		cloth.visible = furl < 0.97
		(s["bundle"] as Node3D).visible = furl > 0.6
		_lines(s, dt)

## Rebuilds the sheets and braces when the sail has moved (not every frame).
func _lines(s: Dictionary, dt: float) -> void:
	var key := Vector3(float(s["swing"]), float(s["fill"]), furl)
	var drawn: Vector3 = s["drawn"]
	if dt > 0.0:
		_lines_t -= dt
		if drawn != Vector3.INF and (_lines_t > 0.0 or key.distance_to(drawn) < 0.01):
			return
		_lines_t = LINES_EVERY
	s["drawn"] = key
	var k := MeshKit.new(6)
	var pivot: Node3D = s["pivot"]
	var cloth: Node3D = s["cloth"]
	for r in s["ropes"]:
		var at: Array = s["pts"][r[0]]
		var local: Vector3 = at[1]
		var p: Vector3
		if at[0] == "cloth":
			if furl > 0.6:
				continue # taken in: the sheets hang slack along the yard
			p = pivot.transform * (cloth.transform * local)
		else:
			p = pivot.transform * local
		BoatModel._line(k, p, r[1], 0.012)
	(s["lines"] as MeshInstance3D).mesh = k.commit(BoatModel.get_mat)
