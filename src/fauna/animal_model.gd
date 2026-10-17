class_name AnimalModel
extends Node3D
## A rigged, animated animal from the CC0 Ultimate Animated Animal Pack (Quaternius),
## scaled to a real size and re-coloured per species: the kit's coat materials are
## tinted, and fantasy and sci-fi species can glow.

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
var _current := ""
var _busy := false

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
	anim = scene.find_children("*", "AnimationPlayer", true, false)[0]
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

## A looping state (Idle, Walk, Gallop, Eating), cross-faded; ignored during a one-shot.
func play(state: String, speed := 1.0) -> void:
	if _busy:
		return
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

func _on_finished(_n: StringName) -> void:
	if _current == "Death":
		return
	_busy = false
	_current = ""
