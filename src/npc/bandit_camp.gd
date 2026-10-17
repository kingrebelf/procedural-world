class_name BanditCamp
extends Node3D
## Where a band of outlaws sleeps (Bandits): a fire in a ring of stones with stools,
## their bags and a crate or two round it. Built once the ground under it has loaded;
## nothing is saved.

var _band: Dictionary
var _ground: Callable
static var _gear: ArrayMesh

func setup(band: Dictionary, ground: Callable) -> void:
	_band = band
	_ground = ground
	name = "Camp_" + String(band["id"])

func _process(_delta: float) -> void:
	var c: Vector2 = _band["camp"]
	var h: float = _ground.call(c.x, c.y)
	if is_nan(h):
		return
	set_process(false)
	position = Vector3(c.x, h, c.y)
	var fire := MeshInstance3D.new()
	fire.mesh = BuildCatalog.mesh("campfire")
	add_child(fire)
	var fl := FireFx.flame(0.95)
	fl.add_child(FireFx.embers(0.95))
	add_child(fl)
	var l := FlickerLight.new()
	l.light_color = Color(1.0, 0.55, 0.25)
	l.light_energy = 1.6
	l.omni_range = 9.0
	l.position = Vector3(0, 1.0, 0)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 45.0
	l.distance_fade_length = 15.0
	add_child(l)
	if _gear == null:
		var models: Array = []
		for i in 5:
			var a := TAU * i / 5.0
			models.append(["props/Stool", rad_to_deg(-a), Vector3(cos(a), 0, sin(a)) * 1.7, 1.0])
		models.append(["props/Bag", 20, Vector3(3.2, 0, 1.0), 1.0])
		models.append(["props/Bag", -40, Vector3(2.8, 0, 1.8), 1.0])
		models.append(["props/Crate_Wooden", 15, Vector3(-3.0, 0, 1.4), 1.0])
		models.append(["props/Barrel", 0, Vector3(-3.2, 0, 0.2), 1.0])
		_gear = BuildCatalog.merge_models(models)
	var g := MeshInstance3D.new()
	g.mesh = _gear
	# Stools and bags sit on the slope as best they can: the camp is on the ground at its fire.
	add_child(g)
