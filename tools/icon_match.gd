extends SceneTree
## Icon vs model: the painted icon is the standard each item's 3D model should match. For
## every icon sheet this draws a comparison sheet in the same 6x5 layout, each cell the
## icon on the left and the model on the right, posed the way icons are painted (long
## things diagonal with the grip bottom-left, guns side-on pointing right, everything else
## a three-quarter view from a little above), plus a CSV of where each model comes from.
## Run windowed with Forward+ (xvfb + lavapipe is fine, about 30 s a sheet):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --rendering-driver vulkan --script res://tools/icon_match.gd -- --out=DIR [--sheets=items5,items10] [--items=a,b] [--size=192]
## A cell tagged CARD has no model (the hand holds its icon on a card), BLOCK is a painted
## placeholder block; both are listed in models.csv so they can be modelled.
func _initialize() -> void:
	_run.call_deferred()

var _cam: Camera3D
var _holder: Node3D
var _vp: SubViewport

func _sheets() -> Array:
	var out: Array = [[Icons.SHEET_PATH, Icons.SHEET_ORDER], [Icons.SHEET2_PATH, Icons.SHEET2_ORDER]]
	out.append_array(Icons.MORE_SHEETS)
	return out

## Which mesh the hand holds for `t`, following Viewmodel.prop_for, and where it comes from.
static func source(t: String) -> Array:
	var d := ItemDB.def(t)
	if d.get("kind", "") in ["tool", "weapon", "light"] and Viewmodel.model(t) != null:
		var m: ArrayMesh = Viewmodel.model(t)
		if m.has_meta("placeholder"):
			return [m, "BLOCK"]
		var from := "ToolModels"
		if GunLook.has(t):
			from = "GunLook"
		elif Viewmodel.KIT.has(t):
			from = "Viewmodel.KIT"
		elif t == "torch":
			from = "HandLight"
		elif Viewmodel._forged(t) != null:
			from = "Viewmodel._forged"
		return [m, from]
	if ItemModels.has(t):
		return [ItemModels.model(t), "ItemModels"]
	if Provisions.has(t):
		return [Provisions.model(t), "Provisions"]
	if GearModels.has(t):
		return [GearModels.model(t), "GearModels"]
	return [null, "CARD"]

func _run() -> void:
	var out := "user://icon_match"
	var size := 192
	var only_sheets: Array = []
	var only_items: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--size="):
			size = a.substr(7).to_int()
		elif a.begins_with("--sheets="):
			only_sheets = Array(a.substr(9).split(","))
		elif a.begins_with("--items="):
			only_items = Array(a.substr(8).split(","))
	DirAccess.make_dir_recursive_absolute(out)
	_vp = SubViewport.new()
	_vp.size = Vector2i(size, size) * 2
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_vp)
	_stage()
	var csv := FileAccess.open(out.path_join("models.csv"), FileAccess.WRITE)
	csv.store_line("sheet,cell,id,kind,source,size_m,icon_rgb,model_rgb,colour_diff")
	for sh in _sheets():
		var path: String = sh[0]
		var order: Array = sh[1]
		var name := path.get_file().get_basename()
		if not only_sheets.is_empty() and not only_sheets.has(name):
			continue
		var sheet := (load(path) as Texture2D).get_image() if ResourceLoader.exists(path) else null
		if sheet == null:
			continue
		sheet.convert(Image.FORMAT_RGBA8)
		var rows := ceili(order.size() / float(Icons.SHEET_COLS))
		var cw := sheet.get_width() / Icons.SHEET_COLS
		var ch := sheet.get_height() / rows
		var page := Image.create(Icons.SHEET_COLS * size * 2, rows * size, false, Image.FORMAT_RGBA8)
		page.fill(Color(0.23, 0.23, 0.24))
		var any := false
		for i in order.size():
			var t: String = order[i]
			if t == "" or (not only_items.is_empty() and not only_items.has(t)):
				continue
			any = true
			var ox := (i % Icons.SHEET_COLS) * size * 2
			var oy := (i / Icons.SHEET_COLS) * size
			var icon := sheet.get_region(Rect2i((i % Icons.SHEET_COLS) * cw, (i / Icons.SHEET_COLS) * ch, cw, ch))
			icon.resize(size, size, Image.INTERPOLATE_LANCZOS)
			page.blend_rect(icon, Rect2i(0, 0, size, size), Vector2i(ox, oy))
			var src := source(t)
			var mesh: Mesh = src[0]
			var tag: String = src[1]
			var span := 0.0
			var ic := mean_colour(icon)
			var mc := Color(0, 0, 0, 0)
			if mesh != null:
				span = _longest(mesh.get_aabb())
				var shot := await _shoot(mesh, tag)
				shot.resize(size, size, Image.INTERPOLATE_LANCZOS)
				mc = mean_colour(shot)
				page.blend_rect(shot, Rect2i(0, 0, size, size), Vector2i(ox + size, oy))
			if tag in ["CARD", "BLOCK"]:
				# Mark it: a red corner where the model should be.
				page.fill_rect(Rect2i(ox + size, oy, size / 6, size / 6), Color(0.8, 0.15, 0.1))
			page.fill_rect(Rect2i(ox + size * 2 - 1, oy, 1, size), Color(0.12, 0.12, 0.12))
			var diff := colour_diff(ic, mc) if mc.a > 0.0 else -1.0
			csv.store_line("%s,%d,%s,%s,%s,%.2f,%s,%s,%.0f" % [name, i, t, ItemDB.def(t).get("kind", ""), tag, span, ic.to_html(false), mc.to_html(false) if mc.a > 0.0 else "", diff])
		if any:
			page.save_png(out.path_join("match_%s.png" % name))
			print("sheet ", name)
	csv.close()
	quit()

## The average colour of what is drawn (alpha-weighted), or alpha 0 when nothing is.
static func mean_colour(img: Image) -> Color:
	var sum := Vector3.ZERO
	var w := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			sum += Vector3(c.r, c.g, c.b)
			w += 1.0
	if w == 0.0:
		return Color(0, 0, 0, 0)
	sum /= w
	return Color(sum.x, sum.y, sum.z, 1.0)

## How far apart two colours look (CIE76 delta E in Lab; above about 25 reads as a
## different colour, which for an item means a different material or paint).
static func colour_diff(a: Color, b: Color) -> float:
	return _lab(a).distance_to(_lab(b))

static func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.9505
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.089
	var f := func(t: float) -> float:
		return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))

static func _longest(b: AABB) -> float:
	return maxf(b.size.x, maxf(b.size.y, b.size.z))

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# A light studio sky, so polished metal reflects grey-white as it does in the paintings
	# (a blue sky top turns every blade navy in the compatibility renderer).
	sm.sky_top_color = Color(0.78, 0.8, 0.82)
	sm.sky_horizon_color = Color(0.9, 0.9, 0.9)
	sm.ground_bottom_color = Color(0.35, 0.33, 0.31)
	sm.ground_horizon_color = Color(0.7, 0.68, 0.65)
	sky.sky_material = sm
	e.sky = sky
	# Metal needs a sky to reflect (Forward+; the compatibility renderer leaves polished
	# steel near black, so use Vulkan, lavapipe is fine). The viewport is transparent, so
	# the sky itself isn't drawn and the shot lays over the sheet's grey.
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	env.environment = e
	_vp.add_child(env)
	# Icons are lit from the upper left, like a painting.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, -0.6, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.4, 0)
	fill.light_energy = 0.45
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_cam.make_current()
	_holder = Node3D.new()
	_vp.add_child(_holder)

## The model posed like its icon: handle-along-+Y things lie diagonally with the grip at the
## bottom left, guns (barrel along -Z) are seen side-on pointing right, the rest from the
## front and a little above (ItemModels and Provisions show their best face on +Z).
func _shoot(mesh: Mesh, tag: String) -> Image:
	for c in _holder.get_children():
		c.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var pivot := Node3D.new()
	pivot.add_child(mi)
	_holder.add_child(pivot)
	var b := mesh.get_aabb()
	mi.position = -b.get_center()
	var s := b.size
	if s.z > s.y * 1.6 and s.z > s.x * 1.6:
		# Barrel along -Z: turn so it points along +X (screen right), tip it up a touch.
		pivot.basis = Basis(Vector3.UP, PI * 0.5).rotated(Vector3(0, 0, 1), 0.12)
		_frame(pivot, Vector3(0.05, 0.12, 1.0))
	elif s.y > maxf(s.x, s.z) * 1.8:
		# Long along +Y: grip bottom-left, tip top-right; the broad side (axe or pick head,
		# blade flat) faces the camera.
		var turn := 0.0 if s.x >= s.z else PI * 0.5
		pivot.basis = Basis(Vector3(0, 0, 1), -PI * 0.25) * Basis(Vector3.UP, turn)
		_frame(pivot, Vector3(0.0, 0.1, 1.0))
	else:
		pivot.basis = Basis.IDENTITY
		_frame(pivot, Vector3(0.45, 0.55, 1.0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img

func _frame(pivot: Node3D, dir: Vector3) -> void:
	var mi: MeshInstance3D = pivot.get_child(0)
	var box: AABB = pivot.transform * (mi.transform * mi.mesh.get_aabb())
	var rad := box.size.length() * 0.5
	var dist := rad / tan(deg_to_rad(_cam.fov * 0.5)) * 1.02
	_cam.position = box.get_center() + dir.normalized() * dist
	_cam.look_at(box.get_center())
	_cam.near = maxf(dist * 0.02, 0.005)
	_cam.far = dist * 4.0
