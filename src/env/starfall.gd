class_name Starfall
extends Node3D
## Starfall nights (plans/story.md): on about one night in ten, the wreckage of the fleet
## that brought people to this world comes down out of orbit. Falling stars streak across
## a clear sky from one point in it, as a real meteor shower's do, and now and then one
## comes down nearby: a fireball, a boom and a smoking crater with a scorched fragment of
## hull in it that you can pry loose (Landmark "star_iron", WonderEffects).
##
## Like the weather it is a pure function of the seed and the clock, so everyone on a
## server sees the same falls. A fragment only lands where a chunk is loaded to keep it:
## you see it come down, or it never existed.

const NIGHT := Climate.STARFALL_NIGHT
const SKY := 1600.0 ## how far off the streaks are drawn (in front of the hills)
const POOL := 6

const FALL_CELL := 1500.0 ## metres; each cell may take one fragment a starfall night
const FALL_CHANCE := 0.45
const FALL_REACH := 1100.0 ## falls further off than this are not seen to land
const FALL_TIME := 3.2 ## seconds from first sight to impact
const SMOKE_TIME := 90.0

var weather: Weather
var forced := false ## a starfall tonight whatever the dice say (console, capture)
var land_now := false ## bring one down in front of the camera (console, capture)

var _streaks: Array = [] ## [MeshInstance3D, age, life, from, travel, speed, length, bright]
var _next := 0.0
var _falls: Array = [] ## [MeshInstance3D, OmniLight3D, age, from, to, fall id, hash]
var _prev_day := -1.0
var _smoke_tex: Texture2D
var _pix := 0.004

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_smoke_tex = t

func _process(delta: float) -> void:
	var atm := weather.atmosphere
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(atm.target):
		return
	var p := atm.target.global_position
	var day := Game.day
	var on := Climate.starfall(Game.seed, day)
	if forced:
		on = 1.0
	# Cloud, mist and rain hide them; and they are a night thing.
	var night := 1.0 - smoothstep(NIGHT - 0.04, NIGHT + 0.02, absf(day - Climate.starfall_night_of(day)))
	var seen := on * night * (1.0 - smoothstep(0.4, 0.75, weather.cover)) * (1.0 - weather.mist) * (1.0 - weather.precip)
	# Radians a pixel spans, for the streaks' pixel floor.
	var vh := float(get_viewport().get_visible_rect().size.y)
	_pix = 2.0 / (cam.get_camera_projection().y.y * maxf(vh, 1.0))
	_sky(delta, cam.global_position, seen)
	_landings(p, day, on)
	_update_falls(delta, cam.global_position)
	_prev_day = day

# --- Streaks across the sky -----------------------------------------------------------

func _sky(delta: float, cam: Vector3, seen: float) -> void:
	_next -= delta
	if seen > 0.02 and _next <= 0.0:
		_next = randf_range(0.5, 3.5) / maxf(seen, 0.25)
		_spawn_streak(seen)
	for s in _streaks:
		var mi: MeshInstance3D = s[0]
		if not mi.visible:
			continue
		s[1] += delta
		var age: float = s[1]
		var life: float = s[2]
		if age >= life:
			mi.visible = false
			continue
		var from: Vector3 = s[3]
		var travel: Vector3 = s[4]
		var head := from + travel * (float(s[5]) * age)
		var dir := head.normalized()
		var tail := head - travel * minf(float(s[6]), float(s[5]) * age)
		var m := mi.material_override as ShaderMaterial
		m.set_shader_parameter("head", cam + dir * SKY)
		m.set_shader_parameter("tail", cam + tail.normalized() * SKY)
		# Flares up and burns out.
		m.set_shader_parameter("energy", float(s[7]) * sin(PI * age / life) * seen)
		m.set_shader_parameter("pix", _pix)
		mi.global_position = cam

func _spawn_streak(seen: float) -> void:
	var s: Array = []
	for e in _streaks:
		if not (e[0] as MeshInstance3D).visible:
			s = e
			break
	if s.is_empty():
		if _streaks.size() >= POOL:
			return
		s = [_streak_mesh(), 0.0, 0.0, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, 0.0]
		_streaks.append(s)
	# Somewhere up in the sky, travelling away from the radiant along a great circle.
	var rad := Climate.starfall_radiant(Game.seed, Climate.starfall_night_of(Game.day))
	var dir := Vector3.ZERO
	for tries in 6:
		var a := randf() * TAU
		var el := randf_range(0.25, 1.3)
		dir = Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
		if dir.dot(rad) < 0.97:
			break
	var travel := (dir - rad * dir.dot(rad)).normalized()
	s[1] = 0.0
	s[2] = randf_range(0.35, 1.1)
	s[3] = dir
	s[4] = travel
	s[5] = randf_range(0.12, 0.28) # sky radians a second
	s[6] = randf_range(0.03, 0.09) # train length in sky radians
	s[7] = randf_range(0.6, 2.2) * (2.5 if randf() < 0.08 else 1.0) # now and then a bright one
	(s[0] as MeshInstance3D).visible = true

func _streak_mesh() -> MeshInstance3D:
	var q := QuadMesh.new()
	q.custom_aabb = AABB(Vector3(-4000, -4000, -4000), Vector3(8000, 8000, 8000))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/env/meteor.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

# --- Fragments that come down -----------------------------------------------------------

## Each starfall night every cell may take one fragment, at its own moment and spot.
func _landings(p: Vector3, day: float, on: float) -> void:
	if land_now:
		land_now = false
		var cam := get_viewport().get_camera_3d()
		var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
		var a := atan2(fwd.z, fwd.x) + randf_range(-0.3, 0.3)
		_fall(p + Vector3(cos(a), 0.0, sin(a)) * randf_range(120.0, 260.0), randi(), true)
	# A long jump in time (sleeping, loading) skips what fell meanwhile.
	if _prev_day < 0.0 or day < _prev_day or day - _prev_day > 0.002 or (on <= 0.0 and not forced):
		return
	var n := Climate.starfall_night_of(day)
	var cx := int(floor(p.x / FALL_CELL))
	var cz := int(floor(p.z / FALL_CELL))
	for i in 9:
		var gx := cx + i % 3 - 1
		var gz := cz + floori(i / 3.0) - 1
		var h := WHash.hash2(Game.seed ^ (n * 7919), gx, gz, 612)
		if WHash.to_unit(h) > FALL_CHANCE:
			continue
		var t := n + (WHash.unit2(h, 1, 0, 613) - 0.5) * NIGHT * 1.6
		if not (_prev_day < t and t <= day):
			continue
		var at := Vector3((gx + WHash.unit2(h, 2, 0, 613)) * FALL_CELL, 0.0, (gz + WHash.unit2(h, 3, 0, 613)) * FALL_CELL)
		if Vector2(at.x - p.x, at.z - p.z).length() < FALL_REACH:
			_fall(at, h, false)

## Starts a fragment's fall toward `at`, nudged off roads, rivers, water and buildings.
func _fall(at: Vector3, h: int, shown: bool) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = h
	var spot := _clear_spot(at, r)
	if spot == Vector3.INF:
		if not shown:
			return
		spot = at
		spot.y = weather.atmosphere.field.height(at.x, at.z)
	var rad := Climate.starfall_radiant(Game.seed, Climate.starfall_night_of(Game.day))
	var flat := Vector3(rad.x, 0.0, rad.z).normalized() if Vector2(rad.x, rad.z).length() > 0.01 else Vector3.RIGHT
	var from := spot + (flat * cos(0.6) + Vector3.UP * sin(0.6)) * 2600.0
	var mi := _streak_mesh()
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("tint", Color(1.0, 0.9, 0.75))
	m.set_shader_parameter("px", 3.0)
	mi.visible = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.65)
	light.omni_range = 500.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	_falls.append([mi, light, 0.0, from, spot, h, r.randi()])

## A spot near `at` with room for a crater: dry land, off roads and rivers, nothing built
## or growing within a few metres, and not in a town. Vector3.INF when there is none.
func _clear_spot(at: Vector3, r: RandomNumberGenerator) -> Vector3:
	var s: ChunkStreamer = weather.atmosphere.streamer
	if s == null:
		return Vector3.INF
	var npcs = Game.player.get("npcs") if Game.player != null and is_instance_valid(Game.player) else null
	for tries in 10:
		var q := at
		if tries > 0:
			var a := r.randf() * TAU
			q += Vector3(cos(a), 0.0, sin(a)) * r.randf_range(20.0, 160.0)
		var node: ChunkNode = s.get_chunk(ChunkStreamer.chunk_of(q))
		if node == null:
			continue
		var lx := q.x - node.position.x
		var lz := q.z - node.position.z
		if lx < 6.0 or lz < 6.0 or lx > ChunkGenerator.SIZE - 6.0 or lz > ChunkGenerator.SIZE - 6.0:
			continue
		var y := ChunkGenerator.height_at(node.data, lx, lz)
		if y < ChunkGenerator.WATER_LEVEL + 1.5 or ChunkGenerator.by_river(node.data, lx, lz) or ChunkGenerator.road_at(node.data, lx, lz) > 0.0:
			continue
		var crowded := false
		for o in node.data["objects"]:
			if Vector2(float(o["p"].x) - lx, float(o["p"].z) - lz).length() < 9.0:
				crowded = true
				break
		if crowded:
			continue
		q.y = y
		if npcs != null and not (npcs.town_at(q) as Dictionary).is_empty():
			continue
		return q
	return Vector3.INF

func _update_falls(delta: float, cam: Vector3) -> void:
	for f in _falls.duplicate():
		f[2] += delta
		var age: float = f[2]
		var mi: MeshInstance3D = f[0]
		var light: OmniLight3D = f[1]
		var from: Vector3 = f[3]
		var to: Vector3 = f[4]
		if age < FALL_TIME:
			# It brightens as it comes down the sky and the air thickens.
			var k := age / FALL_TIME
			var head := from.lerp(to, k * k * 0.3 + k * 0.7)
			var tail := head + (from - to).normalized() * minf(450.0, head.distance_to(from))
			var m := mi.material_override as ShaderMaterial
			m.set_shader_parameter("head", head)
			m.set_shader_parameter("tail", tail)
			m.set_shader_parameter("width", 3.0 + 4.0 * k)
			m.set_shader_parameter("energy", 2.0 + 6.0 * k)
			m.set_shader_parameter("pix", _pix)
			mi.global_position = cam
			light.global_position = head
			light.light_energy = 2.0 + 10.0 * k
			continue
		if mi.visible:
			mi.visible = false
			_impact(to, int(f[5]), int(f[6]), cam)
		# The glow of the impact dies away.
		light.global_position = to + Vector3.UP * 3.0
		light.omni_range = 60.0
		light.light_energy = 8.0 * exp(-(age - FALL_TIME) * 2.5)
		if age > FALL_TIME + 3.0:
			mi.queue_free()
			light.queue_free()
			_falls.erase(f)

func _impact(at: Vector3, fall_id: int, roll: int, cam: Vector3) -> void:
	var d := at.distance_to(cam)
	var vol := linear_to_db(clampf(1.6 / (1.0 + d / 600.0), 0.08, 1.0))
	get_tree().create_timer(d / 343.0).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			Audio.play("weather/thunder_near", vol, 0.15, 0.8, "Ambience"))
	_smoke(at)
	var s: ChunkStreamer = weather.atmosphere.streamer
	if s == null:
		return
	var node: ChunkNode = s.get_chunk(ChunkStreamer.chunk_of(at))
	if node == null:
		return
	for o in node.data["objects"]:
		if int((o["st"] as Dictionary).get("fall", 0)) == fall_id:
			return # another player already has it in this chunk
	s.dig(at, 4.5, 1.4)
	var lp := at - node.position
	lp.y = ChunkGenerator.height_at(node.data, lp.x, lp.z) - 0.25
	node.add_object("star_iron", lp, float(roll % 628) * 0.01, int(node.data.get("era", 0)),
		{"fall": fall_id, "ship": roll % Climate.SHIPS.size(), "day": -1})
	if d < 700.0 and Game.player != null:
		var here := Vector2(Game.player.global_position.x, Game.player.global_position.z)
		Game.toast.emit("A star fell %d m to the %s" % [int(round(d / 10.0)) * 10, Wonders.compass(here, Vector2(at.x, at.z))])

## Smoke rising from the crater for a minute and a half.
func _smoke(at: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 48
	gp.lifetime = 7.0
	gp.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 40, 30))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.scale_min = 1.5
	pm.scale_max = 2.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.15, 0.14, 0.5))
	g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _smoke_tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gp)
	gp.global_position = at
	get_tree().create_timer(SMOKE_TIME).timeout.connect(func():
		if is_instance_valid(gp):
			gp.emitting = false)
	get_tree().create_timer(SMOKE_TIME + 8.0).timeout.connect(func():
		if is_instance_valid(gp):
			gp.queue_free())
