class_name Creature
extends Node3D
## A wild animal. Its species (body plan, size, colours, temperament, drops) is rolled
## from a seed by the region's biome, so each region has its own wildlife. Herds are
## derived from the chunk they live in; a creature that is killed is recorded in that
## chunk's snapshot and never comes back.

var sp: int
var era: int
var p: Dictionary
var id: String
var home: Vector3
var manager: Node
var hp := 30.0

var state := "wander"
var _target := Vector3.ZERO
var _think := 0.0
var _phase := 0.0
var _speed := 0.0
var _legs: Array = []
var _wings: Array = []
var _model: Node3D
var _body: AnimatableBody3D
var _bite_cd := 0.0
var _flash := 0.0

const NAMES := [
	{"quad": ["Red Deer", "Elk", "Wild Boar", "Grey Wolf", "Hare", "Aurochs", "Red Fox", "Wild Horse", "Wild Donkey"], "bird": ["Crow", "Kestrel", "Swallow"]},
	{"quad": ["Mossback", "Glimmerhart", "Thornhound", "Fae Hare", "Woolly Lumen"], "hexa": ["Lantern Strider"], "bird": ["Glowmoth", "Wisp Finch"]},
	{"quad": ["Dune Runner"], "hexa": ["Rust Crawler", "Hexapod"], "bird": ["Drift Jelly", "Scout Drone"]},
]

## Species drawn with a rigged kit animal (AnimalModel) instead of the procedural body.
const KIT_OF := {"Red Deer": "Deer", "Elk": "Stag", "Grey Wolf": "Wolf", "Aurochs": "Bull", "Red Fox": "Fox",
	"Wild Horse": "Horse", "Wild Donkey": "Donkey", "Mossback": "Bull", "Glimmerhart": "Stag",
	"Thornhound": "Wolf", "Woolly Lumen": "Alpaca", "Dune Runner": "Horse"}

static func species(sp: int, era: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = WHash.combine(sp, 31)
	var plans: Array = [["quad", "quad", "quad", "bird"], ["quad", "hexa", "bird", "bird"], ["hexa", "hexa", "quad", "bird"]][era]
	var plan: String = plans[r.randi() % plans.size()]
	var names: Array = NAMES[era][plan]
	var name: String = names[r.randi() % names.size()]
	var temper := "skittish"
	var tr := r.randf()
	if tr < 0.2:
		temper = "aggressive"
	elif tr < 0.5:
		temper = "neutral"
	if name in ["Grey Wolf", "Thornhound"]:
		temper = "aggressive"
	if name in ["Hare", "Fae Hare", "Red Deer", "Glimmerhart", "Red Fox", "Wild Horse", "Wild Donkey", "Woolly Lumen"]:
		temper = "skittish"
	var size := r.randf_range(0.5, 1.6)
	if name.contains("Hare"):
		size = r.randf_range(0.25, 0.4)
	elif name in ["Elk", "Aurochs", "Mossback"]:
		size = r.randf_range(1.4, 2.2)
	var hue := r.randf()
	var col: Color
	match era:
		Eras.MEDIEVAL: col = Color.from_hsv(r.randf_range(0.04, 0.1), r.randf_range(0.3, 0.7), r.randf_range(0.2, 0.55))
		Eras.FANTASY: col = Color.from_hsv(hue, r.randf_range(0.3, 0.7), r.randf_range(0.3, 0.7))
		_: col = Color.from_hsv(r.randf_range(0.0, 0.15), r.randf_range(0.0, 0.3), r.randf_range(0.3, 0.6))
	var drops: Array = [["raw_meat", r.randi_range(1, 3)], ["hide", 1]]
	if era == Eras.SCIFI and plan != "quad":
		drops = [["alloy_scrap", r.randi_range(1, 3)], ["circuitry", 1]]
	elif era == Eras.FANTASY and plan == "bird":
		drops = [["glowberry", 1], ["aether_crystal", 1]]
	var kit: String = KIT_OF.get(name, "")
	var kit_scale := r.randf_range(0.88, 1.12)
	if kit != "":
		# Body size (bite reach, health) follows the real animal.
		size = AnimalModel.HEIGHT[kit] / 1.2 * kit_scale
	return {
		"kit": kit, "kit_scale": kit_scale,
		"plan": plan, "name": name, "temper": temper, "size": size, "col": col,
		"col2": col.lightened(r.randf_range(0.1, 0.4)), "glow": r.randi() % 12,
		"has_glow": era != Eras.MEDIEVAL and r.randf() < 0.7, "horns": plan == "quad" and r.randf() < 0.4,
		"speed": r.randf_range(1.5, 3.0) * (1.6 if temper == "skittish" else 1.0),
		"hp": 18.0 + size * 30.0, "drops": drops, "herd": r.randi_range(1, 5) if temper != "aggressive" else r.randi_range(1, 3),
		"leg": r.randf_range(0.7, 1.3), "neck": r.randf_range(0.2, 0.9), "alt": r.randf_range(3.0, 14.0),
	}

func setup(_id: String, _sp: int, _era: int, at: Vector3, m: Node) -> void:
	id = _id
	sp = _sp
	era = _era
	p = species(sp, era)
	home = at
	manager = m
	hp = p["hp"]
	name = "Creature_" + id

func _ready() -> void:
	_build()
	_body = AnimatableBody3D.new()
	_body.collision_layer = 2
	_body.collision_mask = 0
	_body.set_meta("creature", self)
	# Hit box fitted to the whole model (head, body and legs), so a big animal can be hit
	# wherever you swing at it, not only in a small ball at its middle.
	var box := _model_bounds()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = box.size.max(Vector3(0.3, 0.3, 0.3))
	cs.shape = sh
	cs.position = box.get_center()
	_body.add_child(cs)
	add_child(_body)
	global_position = home
	_pick_wander()

func label() -> String:
	return p["name"]

## Danger rating shown over the animal: grows with its health and bite.
func level() -> int:
	return Creature.level_of(p)

static func level_of(sp_p: Dictionary) -> int:
	var lv := 1.0 + (float(sp_p["hp"]) - 18.0) / 8.0
	if sp_p["temper"] == "aggressive":
		lv += 2.0
	return clampi(int(round(lv)), 1, 60)

func bite_damage() -> float:
	return 4.0 + float(p["size"]) * 6.0

# --- Floating tag: level, name and health -----------------------------------------
var _tag: Node3D
var _tag_label: Label3D
var _tag_bar: MeshInstance3D

## Shows the tag (within `range` metres of the viewer), coloured by danger relative to
## the player's level, with a health bar.
func update_tag(show: bool, player_level: int) -> void:
	if not show:
		if _tag:
			_tag.visible = false
		return
	if _tag == null:
		_build_tag()
	_tag.visible = true
	var lv := level()
	var c := Color(0.75, 1.0, 0.7)
	if p["temper"] == "aggressive":
		c = Color(1.0, 0.45, 0.35) if lv > player_level + 2 else Color(1.0, 0.8, 0.4)
	_tag_label.modulate = c
	_tag_label.text = "Lv %d  %s" % [lv, label()]
	var f := clampf(hp / float(p["hp"]), 0.0, 1.0)
	_tag_bar.scale = Vector3(maxf(f, 0.001), 1, 1)
	_tag_bar.position.x = -(1.0 - f) * 0.45

func _build_tag() -> void:
	_tag = Node3D.new()
	var top := _model_bounds().end.y
	_tag.position = Vector3(0, top + 0.45, 0)
	add_child(_tag)
	# The tag ignores the animal's turning: it is a billboard child.
	_tag_label = Label3D.new()
	_tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_label.fixed_size = true
	_tag_label.pixel_size = 0.0011
	_tag_label.font_size = 26
	_tag_label.outline_size = 8
	_tag_label.no_depth_test = true
	_tag_label.position = Vector3(0, 0.12, 0)
	_tag.add_child(_tag_label)
	var holder := Node3D.new()
	_tag.add_child(holder)
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.07)
	back.mesh = q
	back.material_override = _bar_mat(Color(0, 0, 0, 0.6))
	holder.add_child(back)
	_tag_bar = MeshInstance3D.new()
	_tag_bar.mesh = q
	_tag_bar.material_override = _bar_mat(Color(0.9, 0.2, 0.15))
	_tag_bar.position.z = 0.001
	back.add_child(_tag_bar)

static func _bar_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = 1 if c.a >= 1.0 else 0
	return m

func _pick_wander() -> void:
	var a := randf() * TAU
	_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 22.0)

func step(delta: float, ground: Callable, player_pos: Vector3) -> void:
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_think -= delta
	var d := global_position.distance_to(player_pos)
	if _think <= 0.0:
		_think = randf_range(0.4, 1.0)
		var t: String = p["temper"]
		if t == "skittish" and d < 14.0:
			state = "flee"
		elif t == "aggressive" and d < 16.0:
			state = "chase"
		elif state == "flee" and d > 26.0 or state == "chase" and d > 30.0:
			state = "wander"
			_pick_wander()
		elif state == "wander" and randf() < 0.15:
			state = "graze"
		elif state == "graze" and randf() < 0.3:
			state = "wander"
			_pick_wander()
	var goal := _target
	var want := 0.0
	match state:
		"wander":
			want = float(p["speed"]) * 0.35
			if Vector2(global_position.x, global_position.z).distance_to(Vector2(_target.x, _target.z)) < 1.0:
				_pick_wander()
		"flee":
			want = float(p["speed"]) * 2.0
			goal = global_position + (global_position - player_pos).normalized() * 10.0
		"chase":
			want = float(p["speed"]) * 1.6
			goal = player_pos
			if d < 1.2 + float(p["size"]) * 0.5:
				want = 0.0
				if _bite_cd <= 0.0:
					_bite_cd = 1.3
					if _kit:
						_kit.play_once("Attack" if _kit.anim.has_animation("Attack") else "Attack_Headbutt")
					manager.creature_bites(self)
	_speed = move_toward(_speed, want, delta * 6.0)
	var pos := global_position
	var dir := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
	if dir.length() > 0.05 and _speed > 0.01:
		dir = dir.normalized()
		pos += dir * _speed * delta
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * 5.0, 0.0, 1.0))
	var h: float = ground.call(pos.x, pos.z)
	if is_nan(h):
		return
	if p["plan"] == "bird":
		var alt: float = p["alt"] * (0.4 if state == "flee" else 1.0)
		pos.y = lerpf(pos.y, maxf(h, Water.LEVEL) + alt + sin(Time.get_ticks_msec() * 0.001 + float(sp % 100)) * 0.6, clampf(delta * 1.5, 0.0, 1.0))
		if state == "wander":
			_speed = maxf(_speed, 2.5)
	else:
		pos.y = maxf(h, Water.LEVEL - 0.6)
	global_position = pos
	_animate(delta)

func _animate(delta: float) -> void:
	if _kit:
		if _speed < 0.15:
			_kit.play("Eating" if state == "graze" else "Idle")
		elif _speed < 3.2:
			_kit.play("Walk", clampf(_speed / 1.4, 0.5, 1.8))
		else:
			_kit.play("Gallop", clampf(_speed / 6.0, 0.6, 1.6))
		if _flash > 0.0:
			_flash -= delta
		return
	var sz: float = p["size"]
	_phase += delta * (_speed * 4.0 / maxf(sz, 0.3) + (8.0 if p["plan"] == "bird" else 0.0))
	var amt := clampf(_speed / 2.0, 0.0, 1.2)
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		leg.rotation.x = sin(_phase + (PI if i % 2 == 1 else 0.0) + (PI * 0.5 if i >= 2 else 0.0)) * 0.6 * amt
	for i in _wings.size():
		(_wings[i] as Node3D).rotation.z = (1.0 if i == 0 else -1.0) * sin(_phase) * 0.7
	if state == "graze" and _model.get_child_count() > 0:
		_model.rotation.x = lerpf(_model.rotation.x, 0.25, delta * 2.0)
	else:
		_model.rotation.x = lerpf(_model.rotation.x, 0.0, delta * 4.0)
	if _flash > 0.0:
		_flash -= delta
		_model.position.x = sin(_flash * 80.0) * 0.05

func hurt(dmg: float) -> bool:
	hp -= dmg
	_flash = 0.25
	if _kit and hp > 0.0:
		_kit.play_once("Idle_HitReact1")
	if p["temper"] != "aggressive":
		state = "flee"
	else:
		state = "chase"
	_think = 2.0
	return hp <= 0.0

## Killed: kit animals play their death and lie there a moment; others vanish.
func die() -> void:
	if _body:
		_body.queue_free()
		_body = null
	if _kit == null:
		queue_free()
		return
	_kit.play_once("Death")
	get_tree().create_timer(4.0, false).timeout.connect(queue_free)

# --- Model ----------------------------------------------------------------------------

## Bounds of every mesh in the model, in this node's space.
func _model_bounds() -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [_model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh:
			var xf: Transform3D = global_transform.affine_inverse() * (n as MeshInstance3D).global_transform
			var b: AABB = xf * n.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out

func _mesh(parent: Node3D, m: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, emit := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(c, emit)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static var _mats: Dictionary = {}
static func _mat(c: Color, emit: bool) -> StandardMaterial3D:
	var k := c.to_html() + str(emit)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		if emit:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5
		_mats[k] = m
	return _mats[k]

var _kit: AnimalModel

func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	if AnimalModel.available(p.get("kit", "")):
		# Medieval animals keep the kit's natural coats; others take the species' colours.
		var tint = null if era == Eras.MEDIEVAL else p["col"]
		var glow = Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0) if p["has_glow"] else null
		_kit = AnimalModel.new().build(p["kit"], p["kit_scale"], tint, glow)
		_model.add_child(_kit)
		return
	var sz: float = p["size"]
	_model.scale = Vector3(sz, sz, sz)
	var c: Color = p["col"]
	var c2: Color = p["col2"]
	var glow := Color.from_hsv(float(p["glow"]) / 12.0, 0.7, 1.0)
	var cap := func(r: float, h: float) -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 10
		m.rings = 3
		return m
	var sph := func(r: float) -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 10
		m.rings = 6
		return m
	match String(p["plan"]):
		"bird":
			_mesh(_model, sph.call(0.18), c, Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 0.7, 1.4), p["has_glow"] and era != Eras.SCIFI)
			_mesh(_model, sph.call(0.1), c2, Vector3(0, 0.06, 0.24))
			for side in [-1.0, 1.0]:
				var w := Node3D.new()
				w.position = Vector3(side * 0.12, 0.05, 0)
				_model.add_child(w)
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.02, 0.22)
				_mesh(w, bm, c2 if not p["has_glow"] else glow, Vector3(side * 0.26, 0, 0), Vector3.ZERO, Vector3.ONE, p["has_glow"])
				_wings.append(w)
		_:
			var leg_l: float = 0.55 * float(p["leg"])
			var body_y := leg_l + 0.2
			var hexa: bool = p["plan"] == "hexa"
			_mesh(_model, cap.call(0.28, 1.1), c, Vector3(0, body_y, 0), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.9))
			# Neck and head.
			var nl: float = p["neck"]
			_mesh(_model, cap.call(0.1, nl + 0.2), c, Vector3(0, body_y + nl * 0.4, 0.5), Vector3(-0.6, 0, 0))
			var head := Vector3(0, body_y + nl * 0.75 + 0.05, 0.55 + nl * 0.35)
			_mesh(_model, cap.call(0.12, 0.42), c2, head, Vector3(PI * 0.5 - 0.3, 0, 0))
			for side in [-1.0, 1.0]:
				_mesh(_model, sph.call(0.03), Color(0.05, 0.05, 0.05) if not p["has_glow"] else glow, head + Vector3(side * 0.09, 0.06, 0.08), Vector3.ZERO, Vector3.ONE, p["has_glow"])
				if p["horns"]:
					_mesh(_model, cap.call(0.025, 0.4), Color(0.85, 0.8, 0.7), head + Vector3(side * 0.08, 0.2, -0.05), Vector3(-0.4, 0, side * 0.5))
				else:
					_mesh(_model, cap.call(0.03, 0.14), c, head + Vector3(side * 0.07, 0.14, -0.08), Vector3(-0.3, 0, side * 0.3))
			_mesh(_model, cap.call(0.04, 0.35), c2, Vector3(0, body_y + 0.05, -0.6), Vector3(-2.3, 0, 0))
			var zs: Array = [-0.38, 0.38] if not hexa else [-0.42, 0.0, 0.42]
			for z in zs:
				for side in [-1.0, 1.0]:
					var hip := Node3D.new()
					hip.position = Vector3(side * 0.16 * (1.6 if hexa else 1.0), body_y - 0.05, z)
					_model.add_child(hip)
					var lm: Mesh = cap.call(0.055, leg_l + 0.1)
					_mesh(hip, lm, c.darkened(0.15), Vector3(side * (0.12 if hexa else 0.0), -leg_l * 0.5, 0), Vector3(0, 0, side * (0.45 if hexa else 0.0)))
					_legs.append(hip)
			if p["has_glow"]:
				for i in 4:
					_mesh(_model, sph.call(0.05), glow, Vector3(0.0, body_y + 0.27, -0.3 + i * 0.2), Vector3.ZERO, Vector3.ONE, true)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
