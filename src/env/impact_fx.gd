class_name ImpactFx
extends Node3D
## What a blow leaves where it lands: chips and flakes thrown off the surface, a puff of
## dust or sawdust, sparks when steel meets stone or metal, and a mark on the surface that
## fades after a while. Each material looks its own: bark and pale wood chips from trees,
## grit and stone chips from rock, rusty grit and glints from ore, glassy shards from
## crystal. Pooled, so steady chopping never makes new nodes. The player creates the one
## instance; the static calls are safe (and do nothing) before it exists, e.g. in tests.
## Nothing here glows except hot sparks, which are physical: crystal shards stay plain
## glass on human worlds and only shine on alien ones.

const BURSTS := 8
const MARKS := 24
## Seconds a mark stays before fading, and how long the fade takes.
const MARK_LIFE := 7.0
const MARK_FADE := 2.0

static var _fx: ImpactFx

## Per material: chip colours (a random pick between them), dust colour, chip shape
## (box size before scaling), chip count, dust amount, whether a steel edge sparks on it,
## and the mark it leaves.
const LOOK := {
	"wood": {"chips": [Color(0.27, 0.18, 0.11), Color(0.36, 0.25, 0.15), Color(0.86, 0.74, 0.52), Color(0.93, 0.83, 0.62)],
		"dust": Color(0.82, 0.7, 0.52), "chip": Vector3(1.0, 0.18, 0.55), "n": 18, "puff": 6, "spark": false, "mark": "gash"},
	"fungus": {"chips": [Color(0.78, 0.72, 0.62), Color(0.6, 0.5, 0.42), Color(0.9, 0.86, 0.78)],
		"dust": Color(0.85, 0.82, 0.72), "chip": Vector3(0.8, 0.35, 0.6), "n": 14, "puff": 9, "spark": false, "mark": "gash"},
	"stone": {"chips": [Color(0.42, 0.41, 0.39), Color(0.55, 0.53, 0.5), Color(0.33, 0.31, 0.3)],
		"dust": Color(0.66, 0.64, 0.6), "chip": Vector3(0.8, 0.55, 0.7), "n": 14, "puff": 8, "spark": true, "mark": "chip"},
	"ore": {"chips": [Color(0.45, 0.26, 0.16), Color(0.32, 0.27, 0.24), Color(0.58, 0.36, 0.22), Color(0.6, 0.58, 0.55)],
		"dust": Color(0.6, 0.47, 0.38), "chip": Vector3(0.8, 0.55, 0.7), "n": 16, "puff": 7, "spark": true, "mark": "chip", "glint": true},
	"metal": {"chips": [Color(0.5, 0.5, 0.52), Color(0.36, 0.37, 0.4)],
		"dust": Color(0.55, 0.55, 0.55), "chip": Vector3(0.9, 0.12, 0.6), "n": 5, "puff": 3, "spark": true, "mark": "scratch", "glint": true},
	"crystal": {"chips": [Color(0.78, 0.86, 0.96, 0.75), Color(0.66, 0.74, 0.95, 0.7), Color(0.92, 0.94, 1.0, 0.8)],
		"dust": Color(0.85, 0.9, 1.0), "chip": Vector3(0.35, 1.0, 0.35), "n": 16, "puff": 3, "spark": true, "mark": "chip", "glass": true},
	"dirt": {"chips": [Color(0.3, 0.23, 0.16), Color(0.38, 0.3, 0.2), Color(0.45, 0.42, 0.38)],
		"dust": Color(0.52, 0.44, 0.34), "chip": Vector3(0.7, 0.6, 0.7), "n": 12, "puff": 8, "spark": false, "mark": ""},
}

var _chips: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _next := 0
var _marks: Array[Decal] = []
var _mark_age: PackedFloat32Array
var _next_mark := 0
var _mats := {}
var _mark_tex := {}

## A blow landing at `pos` on a surface facing `normal`. `mat` is a Durability material
## ("wood", "stone", "ore", "metal", "crystal", "fungus") or "dirt"; `strength` ~1 for a
## full swing, less for a tired one or a fist; `steel` when the striking edge is metal
## (sparks on stone, ore, metal and crystal). `along` is the direction the blow travels,
## for which way the mark lies (zero: any). `mark`: false leaves no mark (the thing hit
## is already gone).
static func strike(pos: Vector3, normal: Vector3, mat: String, strength := 1.0, steel := true, along := Vector3.ZERO, mark := true) -> void:
	if is_instance_valid(_fx):
		_fx._strike(pos, normal, mat, strength, steel, along, mark)

## Takes away the marks within `radius` of pos (the thing they were on is gone).
static func clear_near(pos: Vector3, radius: float) -> void:
	if is_instance_valid(_fx):
		_fx._clear_near(pos, radius)

## Whether an item's striking edge is metal: tools and blades but not fists, clubs,
## staves or stone tools.
static func steel_edge(t: String) -> bool:
	if t == "" or t.contains("wood") or t.contains("stone") or t.contains("bone") or t.contains("flint") or t.contains("club") or t.contains("staff"):
		return false
	return t.begins_with("axe_") or t.begins_with("pickaxe_") or t.begins_with("sword") or t.ends_with("_sword") \
		or t in ["battle_axe", "hammer", "dagger", "mace", "spear", "machete", "sickle", "scythe", "halberd"] \
		or t.contains("iron") or t.contains("steel") or t.contains("mythril") or t.contains("bronze")

func _ready() -> void:
	_fx = self
	top_level = true
	_mats["rough"] = _chip_mat(0.85, 0.0, false)
	_mats["glint"] = _chip_mat(0.35, 0.75, false)
	_mats["glass"] = _chip_mat(0.04, 0.0, true)
	var dot := _soft_dot()
	for i in BURSTS:
		_chips.append(_make_chips())
		_dust.append(_make_dust(dot))
		_sparks.append(_make_sparks())
	_mark_age.resize(MARKS)
	for i in MARKS:
		var d := Decal.new()
		d.size = Vector3(0.18, 0.14, 0.18)
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.normal_fade = 0.5
		add_child(d)
		_marks.append(d)
		_mark_age[i] = MARK_LIFE + MARK_FADE

func _process(delta: float) -> void:
	for i in MARKS:
		var d := _marks[i]
		if not d.visible:
			continue
		_mark_age[i] += delta
		var a := _mark_age[i]
		# Shows once the blade has come back out, then fades away.
		var k := smoothstep(0.08, 0.2, a) * (1.0 - smoothstep(MARK_LIFE, MARK_LIFE + MARK_FADE, a))
		d.modulate.a = k
		if a > MARK_LIFE + MARK_FADE:
			d.visible = false

func _strike(pos: Vector3, normal: Vector3, mat: String, strength: float, steel: bool, along: Vector3, mark: bool) -> void:
	var look: Dictionary = LOOK.get(mat, LOOK["stone"])
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var s := clampf(strength, 0.2, 1.5)
	var i := _next
	_next = (_next + 1) % BURSTS
	var at := pos + n * 0.02
	# Thrown out of the surface, falling back under gravity.
	var chips := _chips[i]
	var pm := chips.process_material as ParticleProcessMaterial
	pm.direction = n
	pm.color_initial_ramp = _ramp(look["chips"])
	var box := chips.draw_pass_1 as BoxMesh
	box.size = look["chip"]
	box.material = _mats["glass" if look.get("glass", false) else ("glint" if look.get("glint", false) else "rough")]
	chips.amount_ratio = clampf(s, 0.3, 1.0) * float(look["n"]) / float(chips.amount)
	_fire(chips, at)
	var dust := _dust[i]
	pm = dust.process_material as ParticleProcessMaterial
	pm.direction = n
	var dc: Color = look["dust"]
	pm.color = Color(dc.r, dc.g, dc.b, 0.5)
	dust.amount_ratio = clampf(s, 0.3, 1.0) * float(look["puff"]) / float(dust.amount)
	_fire(dust, at)
	if steel and look["spark"]:
		var sp := _sparks[i]
		pm = sp.process_material as ParticleProcessMaterial
		pm.direction = n
		# Hard rock and metal throw more than crumbly ore or brittle crystal.
		sp.amount_ratio = clampf(s, 0.3, 1.0) * (1.0 if mat == "metal" or mat == "stone" else 0.6)
		_fire(sp, at)
	if mark and look["mark"] != "":
		_mark(pos, n, look, along)

func _fire(p: GPUParticles3D, at: Vector3) -> void:
	p.global_position = at
	p.restart()
	p.emitting = true

func _mark(pos: Vector3, n: Vector3, look: Dictionary, along: Vector3) -> void:
	var i := _next_mark
	_next_mark = (_next_mark + 1) % MARKS
	var d := _marks[i]
	var kind: String = look["mark"]
	d.texture_albedo = _tex(kind)
	var c: Color = look["chips"][2] if kind == "gash" else look["dust"]
	d.modulate = Color(c.r, c.g, c.b, 0.0)
	# The decal projects down its own -Y: point +Y out of the surface. Its long side
	# (local X) lies across the blow: level on an upright trunk, along it on a flat top.
	var x := along.cross(n) if along.length() > 0.01 else Vector3.UP.cross(n)
	if x.length() < 0.05:
		x = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	x = x.normalized().rotated(n, randf_range(-0.25, 0.25))
	var z := x.cross(n).normalized()
	d.global_transform = Transform3D(Basis(x, n, z), pos)
	var sz := randf_range(0.85, 1.2)
	d.size = Vector3(0.2 * sz, 0.16, 0.1 * sz) if kind != "chip" else Vector3(0.15 * sz, 0.16, 0.15 * sz)
	d.visible = true
	_mark_age[i] = 0.0

func _clear_near(pos: Vector3, radius: float) -> void:
	for i in MARKS:
		if _marks[i].visible and _marks[i].global_position.distance_to(pos) < radius:
			_marks[i].visible = false

# --- Building the pool ------------------------------------------------------------

func _base(amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	p.process_material = pm
	add_child(p)
	return p

## Chips and flakes: small tumbling solids, lit like the world.
func _make_chips() -> GPUParticles3D:
	var p := _base(24, 1.1)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := p.process_material as ParticleProcessMaterial
	pm.spread = 55.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 4.2
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.015
	pm.scale_max = 0.055
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(0.75, 1))
	shrink.add_point(Vector2(1, 0))
	var st := CurveTexture.new()
	st.curve = shrink
	pm.scale_curve = st
	p.draw_pass_1 = BoxMesh.new()
	return p

## A puff of dust or sawdust that billows out of the blow and settles.
func _make_dust(dot: Texture2D) -> GPUParticles3D:
	var p := _base(10, 1.4)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.explosiveness = 0.85
	var pm := p.process_material as ParticleProcessMaterial
	pm.gravity = Vector3(0, -0.25, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 1.1
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.25))
	grow.add_point(Vector2(1, 1.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.08, Color(1, 1, 1, 0.8))
	fade.add_point(0.4, Color(1, 1, 1, 0.45))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	_near_fade(mat, false)
	q.material = mat
	p.draw_pass_1 = q
	return p

## Sparks: hot streaks that fly fast, drop and die out quickly.
func _make_sparks() -> GPUParticles3D:
	var p := _base(18, 0.45)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.explosiveness = 1.0
	var pm := p.process_material as ParticleProcessMaterial
	pm.spread = 65.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.5
	pm.particle_flag_align_y = true
	pm.lifetime_randomness = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var cool := Gradient.new()
	cool.set_color(0, Color(1.0, 0.95, 0.8))
	cool.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	cool.add_point(0.35, Color(1.0, 0.7, 0.3))
	var ct := GradientTexture1D.new()
	ct.gradient = cool
	pm.color_ramp = ct
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(4.0, 3.0, 2.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_near_fade(mat, false)
	var m := _streak_mesh(0.007, 0.07)
	m.surface_set_material(0, mat)
	p.draw_pass_1 = m
	return p

## Two crossed thin quads along +Y, so a streak reads from any side.
func _streak_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
		var c := [-a + Vector3(0, -h * 0.5, 0), a + Vector3(0, -h * 0.5, 0), a + Vector3(0, h * 0.5, 0), -a + Vector3(0, h * 0.5, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.add_vertex(c[k])
	return st.commit()

## Bits that fly right up to the eye fade out instead of filling the view.
static func _near_fade(m: StandardMaterial3D, dither: bool) -> void:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER if dither else BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.12
	m.distance_fade_max_distance = 0.45

func _chip_mat(rough: float, metal: float, glass: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	_near_fade(m, not glass)
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if glass:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic_specular = 0.9
		if Eras.theme == "alien":
			# Alien crystal keeps its inner light; on human worlds it is plain glass.
			m.emission_enabled = true
			m.emission = Color(0.35, 0.45, 0.9)
			m.emission_energy_multiplier = 0.6
	return m

func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for k in cols.size():
		g.add_point(float(k) / cols.size(), cols[k])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _soft_dot() -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.5))
	dot.gradient = g
	dot.width = 64
	dot.height = 64
	return dot

## The mark a blow leaves, drawn once: a "gash" (an axe's bite: a lens of bright fresh
## wood with a dark torn rim), a "chip" (a pale ragged scar on rock) or a "scratch"
## (bright streaks on metal). White where it shows, tinted per material by the decal.
func _tex(kind: String) -> Texture2D:
	if _mark_tex.has(kind):
		return _mark_tex[kind]
	const N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.seed = kind.hash()
	for y in N:
		for x in N:
			var u := (x + 0.5) / N * 2.0 - 1.0
			var v := (y + 0.5) / N * 2.0 - 1.0
			var r := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0, 0, 0, 0)
			match kind:
				"gash":
					# A lens wide along u, its edge torn by noise; darker toward the rim.
					var e := absf(v) / maxf(0.001, 0.62 * (1.0 - u * u)) + (r - 0.5) * 0.35
					if e < 1.0:
						var rim := smoothstep(0.55, 1.0, e)
						var lit := lerpf(1.0, 0.25, rim) * lerpf(0.85, 1.0, r)
						c = Color(lit, lit, lit, smoothstep(1.0, 0.85, e))
				"chip":
					var e := Vector2(u, v).length() + (r - 0.5) * 0.55
					if e < 0.8:
						var lit := lerpf(1.25, 0.8, smoothstep(0.2, 0.8, e)) * lerpf(0.85, 1.05, r)
						c = Color(minf(lit, 1.0), minf(lit, 1.0), minf(lit, 1.0), smoothstep(0.8, 0.6, e) * 0.9)
				"scratch":
					var lines := absf(sin((v + u * 0.15) * 26.0 + r * 3.0))
					var e := absf(u) + (r - 0.5) * 0.3
					if e < 0.9 and lines > 0.82:
						c = Color(1, 1, 1, smoothstep(0.9, 0.6, e) * 0.85)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_mark_tex[kind] = t
	return t
