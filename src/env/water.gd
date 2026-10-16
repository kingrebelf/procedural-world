class_name Water
extends MeshInstance3D
## A single large water surface that follows the player, so every hollow below sea level
## becomes a lake or sea. Waves are driven by the world wind and grow with depth (open,
## deep water gets big swells; shallows stay calm). The same wave function runs here on
## the CPU so swimming and buoyancy match what is drawn.

const LEVEL := 0.0
const SIZE := 1600.0
const DEPTH_RES := 128

var target: Node3D
var atmosphere: Atmosphere
var streamer: ChunkStreamer
var _mat: ShaderMaterial
var _depth_img: Image
var _depth_tex: ImageTexture
var _depth_origin := Vector2.ZERO
var _depth_timer := 0.0
static var _wind := 0.3
static var _dir := Vector2(0.8, 0.6)
static var _depth_lookup: Callable

func _ready() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.subdivide_width = 200
	pm.subdivide_depth = 200
	mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/env/water.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = LEVEL
	_depth_img = Image.create(DEPTH_RES, DEPTH_RES, false, Image.FORMAT_RF)
	_depth_img.fill(Color(20, 0, 0))
	_depth_tex = ImageTexture.create_from_image(_depth_img)
	_mat.set_shader_parameter("depth_map", _depth_tex)
	_depth_lookup = depth_at

func _process(delta: float) -> void:
	if target:
		var p := target.global_position
		position = Vector3(snappedf(p.x, 32.0), LEVEL, snappedf(p.z, 32.0))
	if atmosphere:
		var w := atmosphere.current_weights()
		_mat.set_shader_parameter("shallow", Color(0.16, 0.36, 0.38) * w[0] + Color(0.1, 0.45, 0.5) * w[1] + Color(0.12, 0.28, 0.36) * w[2])
		_mat.set_shader_parameter("glow_amount", w[1] * 0.8)
		_wind = atmosphere.wind_strength
		_dir = atmosphere.wind_dir
	_depth_timer -= delta
	if _depth_timer <= 0.0 and streamer != null:
		_depth_timer = 1.5
		_update_depth()

## Water depth map around the player (metres below sea level, 0 on land), so the shader
## can grow waves over deep water and calm them in the shallows.
func _update_depth() -> void:
	_depth_origin = Vector2(position.x, position.z) - Vector2(SIZE, SIZE) * 0.5
	var step := SIZE / DEPTH_RES
	for j in DEPTH_RES:
		for i in DEPTH_RES:
			var x := _depth_origin.x + (i + 0.5) * step
			var z := _depth_origin.y + (j + 0.5) * step
			var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
			var c := streamer.get_chunk(k)
			var d := 12.0
			if c != null:
				d = clampf(LEVEL - ChunkGenerator.height_at(c.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE), 0.0, 40.0)
			_depth_img.set_pixel(i, j, Color(d, 0, 0))
	_depth_tex.update(_depth_img)
	_mat.set_shader_parameter("depth_origin", _depth_origin)
	_mat.set_shader_parameter("depth_size", SIZE)

func depth_at(x: float, z: float) -> float:
	var u := (x - _depth_origin.x) / SIZE * DEPTH_RES
	var v := (z - _depth_origin.y) / SIZE * DEPTH_RES
	if u < 0 or v < 0 or u >= DEPTH_RES or v >= DEPTH_RES:
		return 12.0
	return _depth_img.get_pixel(int(u), int(v)).r

## Wave amplitude scale: wind cubed-ish (calm water is glassy) times an open-water factor.
static func amplitude(depth: float) -> float:
	var open := smoothstep(0.5, 14.0, depth)
	return (0.04 + _wind * _wind * 1.1) * (0.15 + 0.85 * open)

## Height of the surface at (x, z) and time t. Must match water.gdshader.
static func surface_height(x: float, z: float, t: float) -> float:
	var depth: float = _depth_lookup.call(x, z) if _depth_lookup.is_valid() else 12.0
	var a := amplitude(depth)
	var d := _dir.normalized()
	var p := Vector2(x, z)
	var h := 0.0
	var dirs := [d, d.rotated(0.6), d.rotated(-0.45), d.rotated(1.3)]
	var lens := [38.0, 21.0, 13.0, 7.0]
	var amps := [0.5, 0.28, 0.15, 0.07]
	for i in 4:
		var L: float = lens[i]
		var k := TAU / L
		var c := sqrt(9.8 / k)
		h += amps[i] * sin(k * (p.dot(dirs[i]) - c * t))
	return LEVEL + h * a
