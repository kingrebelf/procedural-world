class_name MenuBackdrop
extends Node3D
## The title screen's background: a slow flight over a real generated world, with its
## sky, day/night light and water. The world is kept in memory only, so nothing is
## written to disk and no saved world is touched.

const SEED := 20261016
const SPEED := 9.0
const HEIGHT := 26.0 ## metres above the ground ahead

signal ready_to_show

var streamer: ChunkStreamer
var atmosphere: Atmosphere
var cam: Camera3D
var _rig: Node3D
var _gen: ChunkGenerator
var _yaw := 0.6
var _alt := 0.0
var _t := 0.0
var _shown := false
var _noise := FastNoiseLite.new()

func _ready() -> void:
	# Atmosphere reads the world seed and time of day from Game; borrow them while the
	# menu is up (opening a world sets both).
	Game.seed = SEED
	Game.day = 0.31
	_gen = ChunkGenerator.new(SEED)
	_noise.seed = SEED
	_rig = Node3D.new()
	add_child(_rig)
	var start := Vector3(40, 0, 40)
	_alt = _ground(start) + HEIGHT
	_rig.position = Vector3(start.x, _alt, start.z)
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.target = _rig
	streamer = ChunkStreamer.new()
	streamer.store = WorldStore.memory()
	streamer.seed = SEED
	streamer.preview = true
	add_child(streamer)
	streamer.apply_settings(mini(int(Settings.get_value("view_distance")), 6), 0.0)
	streamer.set_target(_rig)
	var water := Water.new()
	water.target = _rig
	water.atmosphere = atmosphere
	water.streamer = streamer
	add_child(water)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 2000.0
	_rig.add_child(cam)
	cam.current = true

## Terrain height straight from the generator, so the flight can look ahead of what
## has streamed in.
func _ground(p: Vector3) -> float:
	var w := _gen.field.era_weights(p.x, p.z)
	return maxf(_gen.field.height(p.x, p.z, w), Water.LEVEL)

func _process(delta: float) -> void:
	_t += delta
	# Wander: the heading drifts on slow noise, the height follows the land ahead.
	_yaw += _noise.get_noise_1d(_t * 4.0) * delta * 0.25
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var p := _rig.position + fwd * SPEED * delta
	var ahead := maxf(_ground(p + fwd * 30.0), maxf(_ground(p + fwd * 60.0) - 6.0, _ground(p)))
	_alt = lerpf(_alt, ahead + HEIGHT, clampf(delta * 0.4, 0.0, 1.0))
	p.y = _alt
	_rig.position = p
	_rig.rotation = Vector3(-0.2 + sin(_t * 0.07) * 0.05, _yaw + PI, 0)
	Game.day = 0.42 + sin(_t * 0.012) * 0.12 # mid-morning to mid-afternoon
	if not _shown and streamer.is_ready_at(p) and streamer.chunks.size() >= 9:
		_shown = true
		ready_to_show.emit()
