class_name TagLayout
extends RefCounted
## Decides which villagers' floating tags (name tags and speech lines) are drawn each frame.
##
## Label3D tags are depth-tested, but they keep their size on screen at any distance, so a
## crowd shouting behind a castle wall came through every gap as a pile of half-cut,
## overlapping text. Here a tag is drawn only when:
##  - the speaker is near enough (speech within SPEECH_RANGE; names are already limited
##    to a few metres by NPCManager),
##  - nothing solid (terrain, walls, roofs: physics layer 1) is between the camera and
##    the speaker's head, checked with a few cached raycasts a frame,
##  - it is among the nearest MAX_SPEECH speech lines, and
##  - it doesn't overlap a nearer tag on screen; a tag that would is lifted once above
##    the one in its way, and hidden if it still doesn't fit.
## Whoever you're in a conversation with always shows.

const SPEECH_RANGE := 30.0
const SPEECH_KEEP := 33.0 ## a line already up stays until here, so it doesn't blink at the edge
const MAX_SPEECH := 4
const RAYS_PER_FRAME := 6
const RECHECK := 0.25 ## seconds a line-of-sight answer is trusted
const LIFTS := 2
const GAP := 4.0 ## screen pixels kept between tags

var _seen: Dictionary = {} ## npc instance id -> [visible: bool, checked_at: float, from: Vector3, to: Vector3]
var _shown: Dictionary = {} ## npc instance id -> true, the tags drawn last frame
var _sizes: Dictionary = {} ## tag text -> its size in the label's own pixels
var _wanted: Dictionary = {} ## npc instance id -> true, the tags that wanted to be up last frame

## `nodes`: every NPC whose tag wants to be up this frame.
func update(nodes: Array, cam: Camera3D, space: PhysicsDirectSpaceState3D) -> void:
	if cam == null:
		for n in nodes:
			n.set_tag_clear(true, 0.0)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	# Screen pixels per world metre at one metre's depth: a fixed-size label is scaled by
	# its depth, so this turns its local size straight into pixels (FOV and resolution in).
	var c1 := eye + fwd
	var k := cam.unproject_position(c1 + right).distance_to(cam.unproject_position(c1))

	# Whoever you talk to first, then speech lines before name tags, nearest first; what was
	# already up keeps its place against a slightly nearer newcomer.
	var cands: Array = []
	var wanted := {}
	for n in nodes:
		var lab: Label3D = n.label_node()
		var at := lab.global_position
		var d := eye.distance_to(at)
		var id: int = n.get_instance_id()
		var was: bool = _shown.has(id)
		wanted[id] = true
		if not n.talking:
			if (n.speaking() and d > (SPEECH_KEEP if was else SPEECH_RANGE)) \
					or fwd.dot(at - eye) < 0.1 or not cam.is_position_in_frustum(at):
				n.set_tag_clear(false, 0.0)
				continue
		var score := d - (3.0 if was else 0.0) - (100.0 if n.speaking() else 0.0) - (1000.0 if n.talking else 0.0)
		cands.append([score, n, at, d, id])
	cands.sort_custom(func(a, b): return a[0] < b[0])

	# Line of sight: answers are cached, the stalest few re-asked each frame. A tag that
	# has just come up, or whose speaker or the camera has moved off, is asked first.
	var rays := RAYS_PER_FRAME
	var ask: Array = []
	for c in cands:
		var s: Array = _seen.get(c[4], [])
		if s.is_empty() or not _wanted.has(c[4]) or eye.distance_squared_to(s[2]) > 2.25 or c[2].distance_squared_to(s[3]) > 2.25:
			ask.append([-1.0, c])
		elif now - float(s[1]) > RECHECK:
			ask.append([float(s[1]), c])
	ask.sort_custom(func(a, b): return a[0] < b[0])
	for a in ask:
		if rays <= 0:
			break
		rays -= 1
		var c: Array = a[1]
		var q := PhysicsRayQueryParameters3D.create(eye, c[2] - Vector3(0, 0.25, 0), 1)
		_seen[c[4]] = [space.intersect_ray(q).is_empty(), now, eye, c[2]]

	var placed: Array[Rect2] = []
	var speech := 0
	var shown := {}
	for c in cands:
		var n = c[1]
		var id: int = c[4]
		var s: Array = _seen.get(id, [])
		var ok: bool = n.talking or (not s.is_empty() and bool(s[0]))
		if ok and n.speaking() and not n.talking:
			ok = speech < MAX_SPEECH
		var lift := 0.0
		if ok:
			var lab: Label3D = n.label_node()
			var px := _size_px(lab) * lab.pixel_size * k
			var w := px.x
			var h := px.y
			var mid: Vector2 = cam.unproject_position(c[2])
			var r := Rect2(mid - Vector2(w, h) * 0.5, Vector2(w, h)).grow(GAP * 0.5)
			# In the way of a tag already placed: sit just above it, up to LIFTS times.
			var hit := _blocker(r, placed)
			var tries := 0
			while hit.has_area() and tries < LIFTS:
				tries += 1
				var up := r.end.y - hit.position.y
				lift += up
				r.position.y -= up
				hit = _blocker(r, placed)
			if hit.has_area() and not n.talking:
				ok = false
			if ok:
				placed.append(r)
				# Label3D.offset is in the label's own pixels, before pixel_size.
				lift /= maxf(lab.pixel_size * k, 0.0001)
		if ok:
			shown[id] = true
			if n.speaking() and not n.talking:
				speech += 1
		n.set_tag_clear(ok, lift)
	_shown = shown
	_wanted = wanted
	if _seen.size() > 4 * maxi(cands.size(), 16):
		for id in _seen.keys():
			if now - float(_seen[id][1]) > 5.0:
				_seen.erase(id)

## The tag's text block in label pixels, measured the way Label3D wraps it (its own
## mesh bounds move with the lift, so they can't be used).
func _size_px(lab: Label3D) -> Vector2:
	var key := "%d|%d|%s" % [lab.font_size, lab.width, lab.text]
	if _sizes.has(key):
		return _sizes[key]
	if _sizes.size() > 256:
		_sizes.clear()
	var f: Font = lab.font if lab.font else ThemeDB.fallback_font
	var sz := f.get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_CENTER, lab.width, lab.font_size)
	sz += Vector2(lab.outline_size, lab.outline_size)
	_sizes[key] = sz
	return sz

func _blocker(r: Rect2, placed: Array[Rect2]) -> Rect2:
	for p in placed:
		if p.intersects(r):
			return p
	return Rect2()
