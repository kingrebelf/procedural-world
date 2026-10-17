class_name AnimalModel
extends Node3D
## A rigged, animated animal from the CC0 Ultimate Animated Animal Pack (Quaternius),
## scaled to a real size and re-coloured per species: the kit's coat materials are
## tinted, and fantasy and sci-fi species can glow.
## Gaits follow how fast the animal really moves: each kind's walk and gallop are measured
## once (how fast the hooves or paws slide back while on the ground) and played at the
## rate that keeps them planted, from an amble to a flat-out run. The body tilts to the
## slope it stands on, the head turns toward what it watches (LookIK), and far or unseen
## animals animate less often.

const DIR := "res://assets/models/animals/"
## Kit model -> height in metres (to the top of the head or antlers).
const HEIGHT := {"Wolf": 0.9, "Stag": 2.1, "Deer": 1.5, "Fox": 0.5, "Bull": 1.8, "Horse": 1.75,
	"Alpaca": 1.8, "Donkey": 1.35, "Cow": 1.5, "Horse_White": 1.75, "Husky": 0.72, "ShibaInu": 0.6,
	"Alien_Scolitex": 1.3, "Alien_Oculichrysalis": 0.9, "Alien_Cyclop": 1.1}
## The sci-fi kit's aliens: rigged, but with an idle loop only, so Creature moves them
## procedurally (see procedural()).
const ALIEN_DIR := "res://assets/models/scifi/"
const LOOPS := ["Idle", "Idle_2", "Walk", "Gallop", "Eating"]
## The kit's coat materials; everything else (eyes, hooves, horns) keeps its colour.
const COAT := ["Main", "Main_Light", "Main_Dark", "Material", "Material.003", "Material.010",
	"M_Alien_Orange", "M_Alien_Body_Blue"]
## Materials that glow on glowing species.
const GLOWS := ["Light", "Cyan", "Eyes"]

var anim: AnimationPlayer
var look: LookIK
## Ground height under a point, Callable(x, z) -> float: tilts the body to the slope.
var ground := Callable()
var lod := true
var _current := ""
var _busy := false
var _scene: Node3D
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
var _tilt := Vector2.ZERO
static var _gait_cache := {}

static func path_of(kind: String) -> String:
	return (ALIEN_DIR if kind.begins_with("Alien_") else DIR) + kind + ".gltf"

static func available(kind: String) -> bool:
	return kind != "" and ResourceLoader.exists(path_of(kind))

## True for models without walk cycles: the creature bobs and sways them itself.
func procedural() -> bool:
	return not anim.has_animation("Walk")

## tint: null keeps the kit's colours. glow: emission colour for the light coat, or null.
func build(kind: String, size_mult := 1.0, tint = null, glow = null) -> AnimalModel:
	var scene: Node3D = (load(path_of(kind)) as PackedScene).instantiate()
	add_child(scene)
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = m.transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if tint != null or glow != null:
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				var glows := false
				for g in GLOWS:
					glows = glows or String(mat.resource_name).contains(g) and kind.begins_with("Alien_")
				if mat is BaseMaterial3D and (String(mat.resource_name) in COAT or glows):
					m.set_surface_override_material(s, _recolour(mat, tint, glow))
	var k: float = HEIGHT.get(kind, 1.0) / maxf(box.size.y, 0.01) * size_mult
	scene.scale = Vector3.ONE * k
	_scene = scene
	_kind = kind
	_len = box.size.z * k
	_wid = box.size.x * k
	anim = scene.find_children("*", "AnimationPlayer", true, false)[0]
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tick = randi() % 8
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_nat = gaits(kind, anim, sks[0])
		look = LookIK.new()
		look.chain = LookIK.chain_for(sks[0])
		sks[0].add_child(look)
	for n in LOOPS + ["Alien_Idle"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_finished)
	play("Idle")
	return self

static var _mats := {}

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
## from the clips: the speed at which the lowest hoof or paw slides back.
static func gaits(kind: String, ap: AnimationPlayer, sk: Skeleton3D) -> Dictionary:
	if _gait_cache.has(kind):
		return _gait_cache[kind]
	var out := {}
	var feet := []
	var tips := []
	for b in ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		feet.append(i)
		# The hoof: as far down the leaf bone as the bone stands off the ground at rest.
		tips.append(Vector3(0, sk.get_bone_global_rest(i).origin.y, 0))
	if feet.size() == 4:
		for clip in ["Walk", "Gallop"]:
			if ap.has_animation(clip):
				var v := AnimMath.planted_speed(ap.get_animation(clip), sk, feet, Vector3(0, 0, 1), 60, tips)
				if v > 0.05:
					out[clip] = v
	_gait_cache[kind] = out
	return out

## World speed at which `clip` plays at its own rate, NAN if unknown.
func natural_speed(clip: String) -> float:
	if not _nat.has(clip) or _scene == null or not _scene.is_inside_tree():
		return NAN
	return float(_nat[clip]) * _scene.global_basis.get_scale().y

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
			speed = clampf(_speed / g, 0.55, 2.4) if gallop else clampf(maxf(_speed, absf(_yaw_rate) * _wid * 0.5) / w, 0.35, 1.9)
	if not anim.has_animation(state) and anim.has_animation("Alien_Idle"):
		state = "Alien_Idle"
		speed = clampf(speed, 0.8, 2.0)
	anim.speed_scale = speed
	if state == _current or not anim.has_animation(state):
		return
	_current = state
	anim.play(state, 0.3)

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
	_accum += delta
	_tick += 1
	var every := _lod_every() if lod else 1
	if _tick % every != 0:
		return
	anim.advance(_accum)
	_slope(_accum)
	_accum = 0.0

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

## The kit's skeleton, or null for a procedural animal.
func skeleton() -> Skeleton3D:
	if _scene == null:
		return null
	var all := _scene.find_children("*", "Skeleton3D", true, false)
	return all[0] if not all.is_empty() else null

## Turns the head toward world point `p` (INF to stop), `amount` 0..1.
func look_at_target(p: Vector3, amount := 1.0) -> void:
	if look:
		look.target = p
		look.weight = amount if p != Vector3.INF else 0.0

## Settles the animation `dt` seconds on at once (a carcass found already lying there).
func advance(dt: float) -> void:
	if anim:
		anim.advance(dt)

func _on_finished(_n: StringName) -> void:
	if _current == "Death":
		return
	_busy = false
	_current = ""
