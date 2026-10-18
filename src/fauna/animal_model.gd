class_name AnimalModel
extends Node3D
## A rigged, animated animal from the CC0 Ultimate Animated Animal Pack (Quaternius),
## scaled to a real size and re-coloured per species: the kit's coat materials are
## tinted, and fantasy and sci-fi species can glow.
## Gaits follow how fast the animal really moves: each kind's walk and gallop are measured
## once (how fast the hooves or paws slide back while on the ground) and played at the
## rate that keeps them planted, from an amble to a flat-out run. The body tilts to the
## slope it stands on, the spine bends into turns with the tail trailing and the ears
## flicking (BodyFlex), the head turns toward what it watches (LookIK) and, with nothing
## to watch, looks about on its own, and far or unseen animals animate less often.
## A change of gait (walk to gallop and back) carries on from the same point in the
## stride instead of starting the new one from the top.

const DIR := "res://assets/models/animals/"
## Kit model -> height in metres (to the top of the head or antlers).
const HEIGHT := {"Wolf": 0.9, "Stag": 2.1, "Deer": 1.5, "Fox": 0.5, "Bull": 1.8, "Horse": 1.75,
	"Alpaca": 1.8, "Donkey": 1.35, "Cow": 1.5, "Horse_White": 1.75, "Husky": 0.72, "ShibaInu": 0.6,
	"Alien_Scolitex": 1.3, "Alien_Oculichrysalis": 0.9, "Alien_Cyclop": 1.1,
	"Boar": 0.95, "Hare": 0.42}
## Animals the kit has no model for, built from the nearest rig and reshaped: base kit,
## whole-body shape (width, height, length), bone scales (BoneShaper), materials hidden,
## coat colour, and tusks. A boar is a cow's frame, low, broad and short, with a heavy
## head, no horns and a stub tail; a hare is a fox's, with long ears and a scut for a tail.
const VARIANTS := {
	"Boar": {"base": "Cow", "shape": Vector3(1.15, 0.82, 0.92), "hide": ["Horns"], "tusks": true,
		"coat": Color(0.2, 0.15, 0.11), "bones": {"Head": Vector3(1.25, 1.2, 1.3), "Neck2": Vector3(1.15, 0.7, 1.15), "Tail1": Vector3(0.6, 0.35, 0.6)}},
	"Hare": {"base": "Fox", "shape": Vector3(0.95, 1.0, 0.72), "coat": Color(0.42, 0.33, 0.24),
		"bones": {"Ear1.L": Vector3(1.3, 2.6, 1.3), "Ear1.R": Vector3(1.3, 2.6, 1.3), "Tail1": Vector3(0.28, 0.28, 0.28),
			"Neck3": Vector3(0.75, 0.75, 0.75), "Head": Vector3(1.25, 1.25, 1.1)}},
}
## The sci-fi kit's aliens: rigged, but with an idle loop only, so Creature moves them
## procedurally (see procedural()).
const ALIEN_DIR := "res://assets/models/scifi/"
const LOOPS := ["Idle", "Idle_2", "Idle_Headlow", "Idle_2_HeadLow", "Walk", "Gallop", "Eating"]
## The kit's coat materials; everything else (eyes, hooves, horns) keeps its colour.
const COAT := ["Main", "Main_Light", "Main_Dark", "Material", "Material.003", "Material.010",
	"M_Alien_Orange", "M_Alien_Body_Blue"]
## Materials that glow on glowing species.
const GLOWS := ["Light", "Cyan", "Eyes"]

var anim: AnimationPlayer
var look: LookIK
var _sk: Skeleton3D ## the kit's skeleton, its bone fixes stepped with the animation
var flex: BodyFlex
var feet: QuadFeet
## Ground height under a point, Callable(x, z) -> float: tilts the body to the slope.
var ground := Callable()
var lod := true
var _current := ""
var _busy := false
var _scene: Node3D
var _box := AABB() ## the model's bounds at rest, in its own units
var _kind := ""
var _nat := {} ## clip -> metres per second at speed 1, in the model's own units
var _len := 1.0 ## body length (model units), for the slope
var _wid := 0.5
var _speed := 0.0
var _yaw_rate := 0.0
var _last := Vector3.INF
var _last_yaw := 0.0
var _accum := 0.0
var _tick := 0
var _far := false ## on the Movers layer
var _tilt := Vector2.ZERO
static var _gait_cache := {}
static var _warp_cache := {}
static var _stance_cache := {}
var _rate_base := 1.0 ## the gait's play rate before pacing it through the stride
## This animal's own habits, so a herd doesn't move in lockstep: the idle it prefers
## (head up or head low) and how briskly it idles and grazes.
var _idle := "Idle"
var _rate := 1.0

static func path_of(kind: String) -> String:
	if VARIANTS.has(kind):
		kind = VARIANTS[kind]["base"]
	return (ALIEN_DIR if kind.begins_with("Alien_") else DIR) + kind + ".gltf"

static func available(kind: String) -> bool:
	return kind != "" and ResourceLoader.exists(path_of(kind))

## True for models without walk cycles: the creature bobs and sways them itself.
func procedural() -> bool:
	return not anim.has_animation("Walk")

## tint: null keeps the kit's colours. glow: emission colour for the light coat, or null.
## seed: this animal's own markings (AnimalSkin), stable for the same seed.
func build(kind: String, size_mult := 1.0, tint = null, glow = null, seed := -1) -> AnimalModel:
	var scene: Node3D = (load(path_of(kind)) as PackedScene).instantiate()
	add_child(scene)
	var v: Dictionary = VARIANTS.get(kind, {})
	if v.has("coat") and tint == null:
		tint = v["coat"]
	var kit := String(v.get("base", kind))
	var alien := kind.begins_with("Alien_")
	var sks0 := scene.find_children("*", "Skeleton3D", true, false)
	var box := AABB()
	var first := true
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	for mi in meshes:
		var m := mi as MeshInstance3D
		var b: AABB = m.transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var k: float = HEIGHT.get(kind, 1.0) / maxf(box.size.y, 0.01) * size_mult
	if seed < 0:
		seed = randi()
	for mi in meshes:
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if not alien and AnimalSkin.enabled:
			_skin(m, kind, kit, tint, glow, box, k / size_mult, v, sks0[0] if not sks0.is_empty() else null, seed)
			continue
		for s in m.mesh.get_surface_count():
			var hm := m.get_active_material(s)
			if hm and String(hm.resource_name) in v.get("hide", []):
				m.set_surface_override_material(s, _hidden())
		if tint != null or glow != null:
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				var glows := false
				for g in GLOWS:
					glows = glows or String(mat.resource_name).contains(g) and kind.begins_with("Alien_")
				if mat is BaseMaterial3D and (String(mat.resource_name) in COAT or glows):
					m.set_surface_override_material(s, _recolour(mat, tint, glow))
	scene.scale = Vector3.ONE * k * (v["shape"] as Vector3 if v.has("shape") else Vector3.ONE)
	# Some kits (the cow, the bull) model their hooves a little below the ground line.
	scene.position.y = maxf(-box.position.y, 0.0) * scene.scale.y
	_scene = scene
	_box = box
	_kind = kind
	_len = box.size.z * k
	_wid = box.size.x * k
	anim = scene.find_children("*", "AnimationPlayer", true, false)[0]
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tick = randi() % 8
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_nat = gaits(kind, anim, sks[0])
		# The bone fixes after the animation (flex, feet, looking) run when it does, so a
		# distant or unseen animal's level of detail spares them too: run every frame for
		# every animal about, they were most of what a town's livestock cost.
		_sk = sks[0]
		_sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		flex = BodyFlex.new()
		sks[0].add_child(flex)
		feet = QuadFeet.new()
		sks[0].add_child(feet)
		look = LookIK.new()
		look.chain = LookIK.chain_for(sks[0])
		look.riders = LookIK.riders_for(sks[0], look.chain)
		sks[0].add_child(look)
		if v.has("bones"):
			_shape_bones(sks[0], v)
	for n in LOOPS + ["Alien_Idle"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_finished)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	_rate = r.randf_range(0.85, 1.15)
	for low in ["Idle_Headlow", "Idle_2_HeadLow"]:
		if anim.has_animation(low) and r.randf() < 0.35:
			_idle = low
	play("Idle")
	return self

static var _mats := {}
static var _hidden_mat: StandardMaterial3D

## A kit animal's living skin (AnimalSkin): the smoothed, muscled mesh and the fur
## shader in the kit's colours (or the species' tint), with this animal's own markings.
func _skin(m: MeshInstance3D, kind: String, kit: String, tint, glow, box: AABB, unit: float, v: Dictionary, sk: Skeleton3D, seed: int) -> void:
	m.mesh = AnimalSkin.mesh_for(kit, m.mesh as ArrayMesh, sk)
	var cols := []
	for s in m.mesh.get_surface_count():
		var src := m.mesh.surface_get_material(s)
		var mn := String(src.resource_name) if src else ""
		var c: Color = (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color(0.4, 0.3, 0.2)
		if tint != null and mn in COAT:
			c = (tint as Color) * clampf(c.get_luminance() / 0.3, 0.2, 1.3)
		cols.append(c)
	# Coats that meet blend into each other instead of changing along a polygon edge.
	var with: PackedInt32Array = m.mesh.get_meta("blend_with", PackedInt32Array())
	for s in m.mesh.get_surface_count():
		var src := m.mesh.surface_get_material(s)
		var mn := String(src.resource_name) if src else ""
		if mn in v.get("hide", []):
			m.set_surface_override_material(s, _hidden())
			continue
		var g = glow if glow != null and mn.contains("Light") else null
		if m.mesh.surface_get_name(s) == AnimalSkin.LOCKS:
			m.set_surface_override_material(s, AnimalSkin.lock_material(kind, cols[s]))
			continue
		var other = cols[with[s]] if s < with.size() and with[s] >= 0 else null
		m.set_surface_override_material(s, AnimalSkin.material(kind, mn, cols[s], g, box, unit, other))
	m.set_instance_shader_parameter("seed", float(absi(seed) % 65521))

## A material that draws nothing (horns a variant doesn't have).
static func _hidden() -> StandardMaterial3D:
	if _hidden_mat == null:
		_hidden_mat = StandardMaterial3D.new()
		_hidden_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hidden_mat.albedo_color = Color(0, 0, 0, 0)
	return _hidden_mat

## A variant's bone scales, and its tusks on the head.
func _shape_bones(sk: Skeleton3D, v: Dictionary) -> void:
	var shaper := BoneShaper.new()
	for n in v["bones"]:
		var b := sk.find_bone(n)
		if b >= 0:
			shaper.scales[b] = v["bones"][n]
	sk.add_child(shaper)
	if not v.get("tusks", false):
		return
	var head := sk.find_bone("Head")
	if head < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Head"
	sk.add_child(ba)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.84, 0.72)
	mat.roughness = 0.45
	# Where the snout is: the front of the model, a little below the head bone, taken
	# into the head bone's space. Sizes in metres, turned into the model's own units.
	var to_sk := Transform3D.IDENTITY
	var n: Node = sk
	while n != _scene and n is Node3D:
		to_sk = (n as Node3D).transform * to_sk
		n = n.get_parent()
	var rest := sk.get_bone_global_rest(head)
	var front := to_sk.affine_inverse() * Vector3(0, 0, _box.end.z)
	var tip := rest.affine_inverse() * Vector3(0, rest.origin.y - (rest.origin.y - front.y) * 0.0 - _box.size.y * 0.05, front.z * 0.96)
	var u := 1.0 / maxf(_scene.scale.y, 0.0001)
	var fwd := (rest.basis.inverse() * Vector3(0, 0, 1)).normalized()
	var up := (rest.basis.inverse() * Vector3.UP).normalized()
	var side := up.cross(fwd).normalized()
	for sgn in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.022 * u
		cm.height = 0.1 * u
		cm.radial_segments = 6
		cm.rings = 1
		t.mesh = cm
		t.material_override = mat
		# Curving up and out from the lower jaw, either side of the snout.
		var dir: Vector3 = (up * 0.75 + side * sgn * 0.4 + fwd * 0.3).normalized()
		t.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), tip - fwd * 0.02 * u - up * 0.03 * u + side * sgn * 0.06 * u + dir * 0.04 * u)
		ba.add_child(t)

static func _recolour(src: BaseMaterial3D, tint, glow) -> BaseMaterial3D:
	var key := "%s|%s|%s" % [src.get_instance_id(), tint, glow]
	if _mats.has(key):
		return _mats[key]
	var m := src.duplicate() as BaseMaterial3D
	if tint != null and String(src.resource_name) in COAT:
		# Keep the kit's light/dark coat pattern, in the species' colour.
		var l := src.albedo_color.get_luminance()
		m.albedo_color = (tint as Color) * clampf(l / 0.3, 0.2, 1.3)
	var lit := String(src.resource_name).contains("Light") or String(src.resource_name).contains("Cyan") or String(src.resource_name).contains("Eyes")
	if glow != null and lit:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 1.6
	_mats[key] = m
	return m

## How fast each kind's Walk and Gallop carry it (model units a second), measured once
## from the clips: the mean speed at which the planted hooves or paws slide back, and how
## to pace each through its stride so they stay planted (AnimMath.stance_warp: the kit's
## clips ease every hoof onto and off the ground, so at an even rate they skate). The
## rigs plant their feet with free IK controller bones, which the hoof is skinned to, so
## those are measured where they exist; the lower leg bones only stand in without them.
static func gaits(kind: String, ap: AnimationPlayer, sk: Skeleton3D) -> Dictionary:
	if _gait_cache.has(kind):
		return _gait_cache[kind]
	var out := {}
	var warps := {}
	var stances := {}
	var ik := []
	for b in ["IKFrontLeg.L", "IKFrontLeg.R", "IKBackLeg.L", "IKBackLeg.R"]:
		var i := sk.find_bone(b)
		if i >= 0:
			ik.append(i)
	var feet := []
	var tips := []
	for b in ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		feet.append(i)
		# The hoof: as far down the leaf bone as the bone stands off the ground at rest.
		tips.append(Vector3(0, sk.get_bone_global_rest(i).origin.y, 0))
	for clip in ["Walk", "Gallop"]:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		var m := {}
		if ik.size() == 4 and AnimMath.track_map(a).has(sk.get_bone_name(ik[0])):
			m = AnimMath.stance_warp(a, sk, ik, Vector3(0, 0, 1), 48, [], false)
			stances[clip] = AnimMath.stance_weights(a, sk, ik, 48, [], false)
		elif feet.size() == 4:
			m = AnimMath.stance_warp(a, sk, feet, Vector3(0, 0, 1), 48, tips)
		if float(m.get("speed", 0.0)) > 0.05:
			out[clip] = float(m["speed"])
			# Pacing evens a gallop's planted feet; a walk has three down at once at
			# different speeds, so it keeps the clip's timing and QuadFeet pins them.
			if clip == "Gallop":
				warps[clip] = m["warp"]
	_gait_cache[kind] = out
	_warp_cache[kind] = warps
	_stance_cache[kind] = stances
	return out

## World speed at which `clip` plays at its own rate, NAN if unknown.
func natural_speed(clip: String) -> float:
	if not _nat.has(clip) or _scene == null or not _scene.is_inside_tree():
		return NAN
	return float(_nat[clip]) * _scene.global_basis.get_scale().z

## A looping state (Idle, Walk, Gallop, Eating), cross-faded; ignored during a one-shot.
## Walk and Gallop mean "on the move": which one, and how fast it plays, follows how fast
## the body really moves over the ground.
func play(state: String, speed := 1.0) -> void:
	if _busy:
		return
	# Turning on the spot steps round rather than spinning on planted hooves.
	if state.begins_with("Idle") and absf(_yaw_rate) > 0.9 and _speed < 0.3 and _nat.has("Walk"):
		state = "Walk"
	if (state == "Walk" or state == "Gallop") and not _nat.is_empty():
		var w := natural_speed("Walk")
		var g := natural_speed("Gallop")
		if not is_nan(w):
			# Break into a gallop past a brisk walk; drop back a little below it.
			var gallop := not is_nan(g) and _speed > w * (1.45 if _current == "Gallop" else 1.75)
			state = "Gallop" if gallop else "Walk"
			speed = clampf(_speed / g, 0.55, 3.2) if gallop else clampf(maxf(_speed, absf(_yaw_rate) * _wid * 0.5) / w, 0.35, 1.9)
	var resting := state == "Idle" or state == "Eating"
	if state == "Idle":
		state = _idle
	if resting:
		speed *= _rate
	if not anim.has_animation(state) and anim.has_animation("Alien_Idle"):
		state = "Alien_Idle"
		speed = clampf(speed, 0.8, 2.0)
	anim.speed_scale = speed
	_rate_base = speed
	if state == _current or not anim.has_animation(state):
		return
	# Walk to gallop and back: the new gait picks up where the stride had got to.
	var stride := -1.0
	if _current in ["Walk", "Gallop"] and state in ["Walk", "Gallop"] and anim.current_animation_length > 0.0:
		stride = anim.current_animation_position / anim.current_animation_length
	_current = state
	anim.play(state, 0.3)
	if stride >= 0.0:
		anim.seek(stride * anim.current_animation_length)
	# Each one picks up its idle or grazing loop at its own point in the cycle.
	if resting:
		anim.seek(randf() * anim.current_animation_length)

## Attack, hit reaction or death, then back to the loop (death holds its last frame).
func play_once(state: String) -> void:
	if not anim.has_animation(state) or _current == "Death":
		return
	_busy = true
	_current = state
	anim.speed_scale = 1.0
	anim.play(state, 0.1)

func _process(delta: float) -> void:
	if anim == null:
		return
	_measure(delta)
	_glances(delta)
	_accum += delta
	_tick += 1
	var every := _lod_every() if lod else 1
	if _tick % every != 0:
		return
	if flex:
		flex.yaw_rate = _yaw_rate if _current != "Death" else 0.0
		flex.moving = clampf(_speed / maxf(_len * 1.5, 0.3), 0.0, 1.0)
	_plant_feet()
	_pace_stride()
	anim.advance(_accum)
	_slope(_accum)
	if _sk:
		_sk.advance(_accum)
	_accum = 0.0

## Which feet bear weight now, for QuadFeet to pin (none unless walking or galloping).
func _plant_feet() -> void:
	if feet == null:
		return
	var tab: Dictionary = _stance_cache.get(_kind, {})
	var len := anim.current_animation_length
	if _busy or not tab.has(_current) or len <= 0.0 or anim.current_animation != StringName(_current):
		feet.stance = [0.0, 0.0, 0.0, 0.0]
		return
	var ph := anim.current_animation_position / len
	var ws: Array = tab[_current]
	feet.stance = [AnimMath.cyclic_at(ws[0], ph), AnimMath.cyclic_at(ws[1], ph), AnimMath.cyclic_at(ws[2], ph), AnimMath.cyclic_at(ws[3], ph)]

## On the move, the gait plays quicker where its planted feet move slowly and slower
## where they move fast, so they keep pace with the ground (see gaits()).
func _pace_stride() -> void:
	if _busy or not (_current == "Walk" or _current == "Gallop"):
		return
	var w: Dictionary = _warp_cache.get(_kind, {})
	var len := anim.current_animation_length
	if not w.has(_current) or len <= 0.0:
		return
	anim.speed_scale = _rate_base * AnimMath.cyclic_at(w[_current], anim.current_animation_position / len)

func _lod_every() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var p := global_position
	var d := cam.global_position.distance_to(p)
	var every := 1 if d < 25.0 else (2 if d < 50.0 else (4 if d < 100.0 else 8))
	if d > 6.0 and not cam.is_position_in_frustum(p + Vector3.UP * 0.5):
		every = maxi(every, 6)
	if look:
		look.active = d < 45.0
	if flex:
		flex.active = d < 45.0
	if feet:
		feet.active = d < 30.0 and every <= 2
	if Movers.is_far(d, _far) != _far:
		_far = not _far
		Movers.set_far(self, _far)
	return every

func _measure(delta: float) -> void:
	if delta <= 0.0:
		return
	var p := global_position
	var f := global_basis.z
	var yaw := atan2(f.x, f.z)
	if _last != Vector3.INF:
		var raw := Vector2(p.x - _last.x, p.z - _last.z).length() / delta
		if raw > 40.0:
			raw = 0.0
		var k := clampf(delta * 8.0, 0.0, 1.0)
		_speed = lerpf(_speed, raw, k)
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, k)
	_last = p
	_last_yaw = yaw

## Stands the body along the slope: nose up going uphill, leaning into a side slope.
func _slope(dt: float) -> void:
	if not ground.is_valid() or _scene == null or _current == "Death":
		return
	var p := global_position
	var fwd := global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var side := Vector3.UP.cross(fwd)
	var hl := _len * 0.45
	var hw := maxf(_wid * 0.45, 0.15)
	var hf: float = ground.call(p.x + fwd.x * hl, p.z + fwd.z * hl)
	var hb: float = ground.call(p.x - fwd.x * hl, p.z - fwd.z * hl)
	var hlft: float = ground.call(p.x + side.x * hw, p.z + side.z * hw)
	var hr: float = ground.call(p.x - side.x * hw, p.z - side.z * hw)
	var want := Vector2.ZERO
	if not (is_nan(hf) or is_nan(hb) or is_nan(hlft) or is_nan(hr)):
		want = Vector2(-atan((hf - hb) / (hl * 2.0)), atan((hlft - hr) / (hw * 2.0)) * 0.6)
		want = want.clamp(Vector2(-0.5, -0.3), Vector2(0.5, 0.3))
	_tilt = _tilt.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	_scene.rotation = Vector3(_tilt.x, _scene.rotation.y, _tilt.y)

## Stops animating and holds the pose it is in, for a ragdoll (or a saved pose).
func freeze_for_ragdoll() -> void:
	set_process(false)
	_busy = true
	_current = "Death"
	if look:
		look.active = false
	if flex:
		flex.active = false
	if feet:
		feet.active = false

## The kit's skeleton, or null for a procedural animal.
func skeleton() -> Skeleton3D:
	if _scene == null:
		return null
	var all := _scene.find_children("*", "Skeleton3D", true, false)
	return all[0] if not all.is_empty() else null

## Turns the head toward world point `p` (INF to stop), `amount` 0..1. With nothing to
## watch, it looks about on its own now and then (_glances).
func look_at_target(p: Vector3, amount := 1.0) -> void:
	_watch = p
	_watch_w = amount if p != Vector3.INF else 0.0
	_apply_look()

var _watch := Vector3.INF
var _watch_w := 0.0
var _glance := Vector3.INF
var _glance_t := 0.0
var _glance_in := -1.0

func _apply_look() -> void:
	if look == null:
		return
	if _watch_w > 0.0:
		look.target = _watch
		look.weight = _watch_w
	elif _glance != Vector3.INF:
		look.target = _glance
		look.weight = 0.7
	else:
		look.target = Vector3.INF
		look.weight = 0.0

## A look round every few seconds, at the ground nearby or off to one side, now and then
## back over a shoulder; none while busy, dead or grazing with its head down.
func _glances(dt: float) -> void:
	if look == null:
		return
	if _glance_in < 0.0:
		_glance_in = randf_range(1.0, 8.0)
	if _glance != Vector3.INF:
		_glance_t -= dt
		if _glance_t <= 0.0 or _busy or _current in ["Death", "Eating", "Idle_Headlow", "Idle_2_HeadLow"]:
			_glance = Vector3.INF
			_apply_look()
		return
	_glance_in -= dt
	if _glance_in > 0.0:
		return
	_glance_in = randf_range(3.0, 10.0)
	if _busy or _current in ["Death", "Eating", "Idle_Headlow", "Idle_2_HeadLow"] or _watch_w > 0.0 or _current == "Gallop":
		return
	var fwd := global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	var a := randf_range(0.4, 1.0) * (1.0 if randf() < 0.5 else -1.0)
	if randf() < 0.2:
		a *= 1.5 # over its shoulder
	var far := randf_range(3.0, 14.0) * maxf(_len, 0.5)
	_glance = global_position + fwd.normalized().rotated(Vector3.UP, a) * far + Vector3.UP * randf_range(-0.3, 1.2) * maxf(_len, 0.5)
	_glance_t = randf_range(1.0, 3.0)
	_apply_look()

## Settles the animation `dt` seconds on at once (a carcass found already lying there).
func advance(dt: float) -> void:
	if anim:
		anim.advance(dt)
		if _sk:
			_sk.advance(dt)

func _on_finished(_n: StringName) -> void:
	if _current == "Death":
		return
	_busy = false
	_current = ""
