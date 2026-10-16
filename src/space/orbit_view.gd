class_name OrbitView
extends Node3D
## In orbit: your ship above the planet you left, the other worlds of the system hanging
## in space, and a panel to land or warp. Warping makes another planet current
## (Game.set_planet); landing drops you back in the world, flying your ship.

const R := 60.0 ## the current planet's radius in this scene
const LAND_ALT := 120.0 ## metres above the ground you arrive at when you land

var _planet: MeshInstance3D
var _rim: MeshInstance3D
var _planet_mat: ShaderMaterial
var _rim_mat: ShaderMaterial
var _others: Node3D
var _ship: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _panel: VBoxContainer
var _title: Label
var _sub: Label
var _warp_rect: ColorRect
var _warp_mat: ShaderMaterial
var _busy := false
var _t := 0.0
var _spin := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://src/space/space_sky.gdshader")
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.28, 0.35)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(-0.35, 0.9, 0)
	_sun.light_energy = 1.6
	add_child(_sun)

	_planet = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = R
	sp.height = R * 2.0
	sp.radial_segments = 128
	sp.rings = 64
	_planet.mesh = sp
	_planet_mat = ShaderMaterial.new()
	_planet_mat.shader = load("res://src/space/planet.gdshader")
	_planet.material_override = _planet_mat
	add_child(_planet)
	_rim = MeshInstance3D.new()
	var rs := SphereMesh.new()
	rs.radius = R * 1.035
	rs.height = R * 2.07
	rs.radial_segments = 96
	rs.rings = 48
	_rim.mesh = rs
	_rim_mat = ShaderMaterial.new()
	_rim_mat.shader = load("res://src/space/atmosphere_rim.gdshader")
	_rim.material_override = _rim_mat
	add_child(_rim)
	_rim_mat.set_shader_parameter("sun_dir", -_sun.global_transform.basis.z)
	_others = Node3D.new()
	add_child(_others)

	_cam = Camera3D.new()
	_cam.far = 20000.0
	_cam.fov = 60.0
	add_child(_cam)
	_cam.position = Vector3(0, R * 0.55, R * 2.3)
	_cam.look_at(Vector3(0, R * 0.25, 0))
	_ship = Vehicle.make_model("ship")
	_cam.add_child(_ship)
	_ship.position = Vector3(0, -3.2, -13.0)
	_ship.rotation = Vector3(0.12, 0, 0)

	_build_ui()
	_show_planet()

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	ui.add_child(root)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.sb(Color(0.05, 0.06, 0.09, 0.82), Color(1, 1, 1, 0.1), 8, 1, 16))
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -380
	box.offset_right = -28
	box.offset_top = 28
	root.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	_title = UITheme.title("", 28)
	v.add_child(_title)
	_sub = UITheme.label("", 16, UITheme.DIM)
	v.add_child(_sub)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	v.add_child(_panel)
	_warp_rect = ColorRect.new()
	_warp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = load("res://src/space/warp.gdshader")
	_warp_rect.material = _warp_mat
	_warp_rect.visible = false
	root.add_child(_warp_rect)

## Paints the current planet, places the others, and lists where you can go.
func _show_planet() -> void:
	var here := Game.planet_info()
	var k := Planets.kind_of(here)
	_paint(_planet_mat, here)
	_rim_mat.set_shader_parameter("air", k["air"])
	for c in _others.get_children():
		c.queue_free()
	for p in Planets.system(Game.home_seed):
		if p["n"] == Game.planet:
			continue
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := 10.0 * float(p["size"])
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 48
		s.rings = 24
		m.mesh = s
		var mat := ShaderMaterial.new()
		mat.shader = _planet_mat.shader
		_paint(mat, p)
		m.material_override = mat
		var a := float(p["orbit"]) * 1.9 + 0.6
		m.position = Vector3(cos(a) * 520.0, 60.0 + sin(a * 1.7) * 90.0, -300.0 - absf(sin(a)) * 600.0)
		_others.add_child(m)
		var l := Label3D.new()
		l.text = "%s\n%s" % [p["name"], Planets.kind_of(p)["label"]]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.03 * maxf(1.0, m.position.length() / 400.0)
		l.position = m.position + Vector3(0, r + 8.0, 0)
		l.modulate = Color(0.9, 0.95, 1.0, 0.85)
		l.outline_size = 8
		_others.add_child(l)
	_title.text = here["name"]
	_sub.text = "In orbit  ·  %s" % k["label"]
	for c in _panel.get_children():
		c.queue_free()
	_panel.add_child(UITheme.button("Land on %s" % here["name"], _land))
	_panel.add_child(UITheme.label("Warp to", 16, UITheme.ACCENT))
	for p in Planets.system(Game.home_seed):
		if p["n"] == Game.planet:
			continue
		var n: int = p["n"]
		_panel.add_child(UITheme.button("%s  ·  %s" % [p["name"], Planets.kind_of(p)["label"]], func(): _warp(n)))
	_panel.add_child(HSeparator.new())
	_panel.add_child(UITheme.button("Save and quit to title", _quit))
	UITheme.focus_first(_panel)

static func _paint(mat: ShaderMaterial, p: Dictionary) -> void:
	var k := Planets.kind_of(p)
	mat.set_shader_parameter("sea_col", k["sea"])
	mat.set_shader_parameter("land_col", k["land"])
	mat.set_shader_parameter("land2_col", k["land2"])
	mat.set_shader_parameter("ice", k["ice"])
	var sd: int = p["seed"]
	mat.set_shader_parameter("seed_off", Vector3((sd & 1023) * 0.37, ((sd >> 10) & 1023) * 0.29, ((sd >> 20) & 1023) * 0.31))
	mat.set_shader_parameter("land_level", 0.47 if p["kind"] == "frozen" else 0.5)

func _process(delta: float) -> void:
	_t += delta
	_spin += delta * 0.01
	_planet.rotation.y = _spin
	_planet_mat.set_shader_parameter("time_s", _t)
	_ship.position.y = -3.2 + sin(_t * 0.8) * 0.12
	_ship.rotation.z = sin(_t * 0.5) * 0.03
	if _warp_rect.visible:
		_warp_mat.set_shader_parameter("time_s", _t)

func _warp(n: int) -> void:
	if _busy:
		return
	_busy = true
	_panel.visible = false
	_warp_rect.visible = true
	var tw := create_tween()
	tw.tween_method(_set_warp, 0.0, 1.0, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_cam, "fov", 115.0, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_arrive(n)
	_show_planet()
	_cam.fov = 60.0
	var back := create_tween()
	back.tween_method(_set_warp, 1.0, 0.0, 1.2)
	await back.finished
	_warp_rect.visible = false
	_panel.visible = true
	_busy = false

func _set_warp(a: float) -> void:
	_warp_mat.set_shader_parameter("amount", a)

## Makes planet `n` current and moves your ship's record there, ready to land.
static func _arrive(n: int) -> void:
	Game.set_planet(n)
	var spot := landing_spot()
	var st = Game.pending_player_state
	if st is Dictionary:
		st["pos"] = spot
		var id := int(st.get("riding", -1))
		for r in Game.vehicles:
			if int(r["id"]) == id:
				r["planet"] = Game.planet
				r["pos"] = spot
	Game.save_player()

## Where you come down on the current planet: above where you last left it, or above a
## gentle spot near its origin the first time.
static func landing_spot() -> Vector3:
	var last = Game.landings.get(Game.planet)
	var p: Vector3
	if last is Vector2:
		var g := ChunkGenerator.new(Game.seed, Game.store.has_rivers())
		p = Vector3(last.x, g.field.height(last.x, last.y), last.y)
	else:
		p = Planets.spawn_point(Game.seed, Game.store.has_rivers())
	return Vector3(p.x, maxf(p.y, Water.LEVEL) + LAND_ALT, p.z)

func _land() -> void:
	if _busy:
		return
	_busy = true
	get_tree().change_scene_to_file("res://src/world/world.tscn")

func _quit() -> void:
	Game.close_world()
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
