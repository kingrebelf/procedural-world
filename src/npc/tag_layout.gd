class_name TagLayout
extends CanvasLayer
## Draws villagers' floating tags (name tags and speech lines) and decides which show.
##
## They used to be Label3D tags in the world: depth-tested, but kept at one size on screen
## at any distance, so a crowd shouting behind a castle wall came through every gap as a
## pile of half-cut, overlapping text, and the held item in your hands cut through them.
## Now they're flat text over the 3D view, under the HUD: crisp at any resolution, never
## sliced by a wall edge or a held pickaxe, and untouched by the upscaler's smearing. A
## tag is drawn only when:
##  - the speaker is near enough (speech within SPEECH_RANGE; names are already limited
##    to a few metres by NPCManager),
##  - nothing solid (terrain, walls, roofs: physics layer 1) is between the camera and
##    the speaker's head, checked with a few cached raycasts a frame,
##  - it is among the nearest MAX_SPEECH speech lines, and
##  - it doesn't overlap a nearer tag; a tag that would is lifted above the one in its
##    way (up to LIFTS times), and hidden if it still doesn't fit.
## Whoever you're in a conversation with always shows.

const SPEECH_RANGE := 30.0
const SPEECH_KEEP := 33.0 ## a line already up stays until here, so it doesn't blink at the edge
const MAX_SPEECH := 4
const RAYS_PER_FRAME := 6
const RECHECK := 0.25 ## seconds a line-of-sight answer is trusted
const LIFTS := 2
const GAP := 4.0 ## screen pixels kept between tags
const FONT_FRAC := 0.018 ## text height as a share of the screen's (26 px at 1440p)
const WRAP_EMS := 16.0 ## speech wraps at this many font sizes wide

var _seen: Dictionary = {} ## npc instance id -> [visible: bool, checked_at: float, from: Vector3, to: Vector3]
var _shown: Dictionary = {} ## npc instance id -> true, the tags drawn last frame
var _wanted: Dictionary = {} ## npc instance id -> true, the tags that wanted to be up last frame
var _sizes: Dictionary = {} ## font size|text -> its wrapped size in pixels
var _pool: Array[Label] = []
var _settings: Dictionary = {} ## colour -> LabelSettings
var _font: Font
var _font_px := 0

func _init() -> void:
	layer = -1 # over the 3D view, under the HUD and menus
	_font = ThemeDB.fallback_font

## `nodes`: every NPC whose tag wants to be up this frame.
func update(nodes: Array, cam: Camera3D, space: PhysicsDirectSpaceState3D) -> void:
	var used := 0
	if cam == null:
		_hide_from(0)
		for n in nodes:
			n.tag_clear = false
		return
	var now := Time.get_ticks_msec() / 1000.0
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var vh := float(cam.get_viewport().get_visible_rect().size.y)
	var px := maxi(14, int(round(vh * FONT_FRAC)))
	if px != _font_px:
		_font_px = px
		_settings.clear()
		_sizes.clear()

	# Whoever you talk to first, then speech lines before name tags, nearest first; what was
	# already up keeps its place against a slightly nearer newcomer.
	var cands: Array = []
	var wanted := {}
	for n in nodes:
		var at: Vector3 = n.tag_point()
		var d := eye.distance_to(at)
		var id: int = n.get_instance_id()
		var was: bool = _shown.has(id)
		wanted[id] = true
		if (n.speaking() and not n.talking and d > (SPEECH_KEEP if was else SPEECH_RANGE)) \
				or fwd.dot(at - eye) < 0.1 or not cam.is_position_in_frustum(at):
			n.tag_clear = false
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
		var r := Rect2()
		if ok:
			var sz := _size_px(n.tag_text)
			# The bottom of the tag sits on the point over their head.
			var foot: Vector2 = cam.unproject_position(c[2])
			r = Rect2(foot - Vector2(sz.x * 0.5, sz.y), sz).grow(GAP * 0.5)
			var hit := _blocker(r, placed)
			var tries := 0
			while hit.has_area() and tries < LIFTS:
				tries += 1
				r.position.y -= r.end.y - hit.position.y
				hit = _blocker(r, placed)
			if hit.has_area() and not n.talking:
				ok = false
		n.tag_clear = ok
		if not ok:
			continue
		placed.append(r)
		shown[id] = true
		if n.speaking() and not n.talking:
			speech += 1
		var lab := _label(used)
		used += 1
		lab.text = n.tag_text
		lab.label_settings = _style(n.tag_color)
		lab.size = r.grow(-GAP * 0.5).size
		lab.position = r.grow(-GAP * 0.5).position.round()
		lab.visible = true
	_hide_from(used)
	_shown = shown
	_wanted = wanted
	if _seen.size() > 4 * maxi(cands.size(), 16):
		for id in _seen.keys():
			if now - float(_seen[id][1]) > 5.0:
				_seen.erase(id)

func _label(i: int) -> Label:
	while _pool.size() <= i:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_pool.append(l)
	return _pool[i]

func _hide_from(i: int) -> void:
	for k in range(i, _pool.size()):
		_pool[k].visible = false

func _style(c: Color) -> LabelSettings:
	if not _settings.has(c):
		var st := LabelSettings.new()
		st.font = _font
		st.font_size = _font_px
		st.font_color = c
		st.outline_size = maxi(4, int(round(_font_px * 0.25)))
		st.outline_color = Color(0, 0, 0, 0.85)
		_settings[c] = st
	return _settings[c]

## The text block in pixels, wrapped the way the Label wraps it (a little slack so the
## Label never breaks a line the measure didn't).
func _size_px(text: String) -> Vector2:
	if _sizes.has(text):
		return _sizes[text]
	if _sizes.size() > 256:
		_sizes.clear()
	var sz := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, _font_px * WRAP_EMS, _font_px)
	var o := maxf(4.0, round(_font_px * 0.25))
	sz += Vector2(o + 4.0, o)
	_sizes[text] = sz
	return sz

func _blocker(r: Rect2, placed: Array[Rect2]) -> Rect2:
	for p in placed:
		if p.intersects(r):
			return p
	return Rect2()
