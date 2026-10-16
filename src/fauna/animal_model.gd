class_name AnimalModel
extends Node3D
## A rigged, animated animal from the CC0 Ultimate Animated Animal Pack (Quaternius),
## scaled to a real size and re-coloured per species: the kit's coat materials are
## tinted, and fantasy and sci-fi species can glow.

const DIR := "res://assets/models/animals/"
## Kit model -> height in metres (to the top of the head or antlers).
const HEIGHT := {"Wolf": 0.9, "Stag": 2.1, "Deer": 1.5, "Fox": 0.5, "Bull": 1.8, "Horse": 1.75,
	"Alpaca": 1.8, "Donkey": 1.35}
const LOOPS := ["Idle", "Idle_2", "Walk", "Gallop", "Eating"]
## The kit's coat materials; everything else (eyes, hooves, horns) keeps its colour.
const COAT := ["Main", "Main_Light", "Main_Dark", "Material", "Material.003", "Material.010"]

var anim: AnimationPlayer
var _current := ""
var _busy := false

static func available(kind: String) -> bool:
	return kind != "" and ResourceLoader.exists(DIR + kind + ".gltf")

## tint: null keeps the kit's colours. glow: emission colour for the light coat, or null.
func build(kind: String, size_mult := 1.0, tint = null, glow = null) -> AnimalModel:
	var scene: Node3D = (load(DIR + kind + ".gltf") as PackedScene).instantiate()
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
				if mat is BaseMaterial3D and String(mat.resource_name) in COAT:
					m.set_surface_override_material(s, _recolour(mat, tint, glow))
	var k: float = HEIGHT.get(kind, 1.0) / maxf(box.size.y, 0.01) * size_mult
	scene.scale = Vector3.ONE * k
	anim = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for n in LOOPS:
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
	if tint != null:
		# Keep the kit's light/dark coat pattern, in the species' colour.
		var l := src.albedo_color.get_luminance()
		m.albedo_color = (tint as Color) * clampf(l / 0.3, 0.2, 1.3)
	if glow != null and String(src.resource_name).contains("Light"):
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 1.6
	_mats[key] = m
	return m

## A looping state (Idle, Walk, Gallop, Eating), cross-faded; ignored during a one-shot.
func play(state: String, speed := 1.0) -> void:
	if _busy:
		return
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
