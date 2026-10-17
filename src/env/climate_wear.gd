class_name ClimateWear
extends Node3D
## What each place's climate does to the things that stand in it over the years: moss on
## walls, roofs, rocks and bark where it is wet, snow lying on roofs and ledges and hoar
## frost on cold mornings where it is cold, dust settling where it is dry. A pure function
## of where you are (WorldField.climate_at and the landform), so every player sees the
## same, a save needs nothing, and multiplayer sends nothing. Pieces the player builds
## start clean and weather toward their place's level over game days (maturity()).
##
## The levels reach the shaders as a coarse map round the camera (climate_wear_map_g,
## read in climate_wear.gdshaderinc), with the clock in climate_wear_now_g. A ShelterMap
## beside it says where the open sky is, so nothing grows or settles indoors.

## Map of levels round the camera: RES texels over SPAN metres (64 m a texel; the
## climate changes over kilometres), rebuilt on a worker when the camera has gone RECENTER
## from its middle.
const RES := 64
const SPAN := 4096.0
const RECENTER := 1024.0
## What a place with no climate (worlds made before climates, off the map) wears:
## middling damp, a little moss at the foot of walls, no snow or dust.
const TEMPERATE := Color(0.45, 0.0, 0.0, 0.0)
## Game days a newly built piece takes to weather to its place's level.
const MATURE_DAYS := 20.0
## How much dust the wind leaves on each landform (WorldField.LF_*): dunes and badlands
## are deserts, the old craters' spoil is dusty too.
const LF_DUST := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.35, 0.8]

var target: Node3D
var _tex: ImageTexture
var _origin := Vector2(INF, INF)
var _task := -1
var _next_origin := Vector2.ZERO
var _next: PackedByteArray
var _field: WorldField ## the worker's own (noise instances are not shared across threads)
var shelter: ShelterMap

func _ready() -> void:
	_field = WorldField.new(Game.seed)
	_tex = ImageTexture.create_from_image(Image.create(RES, RES, false, Image.FORMAT_RGBA8))
	shelter = ShelterMap.new()
	shelter.name = "Shelter"
	shelter.target = target
	add_child(shelter)

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("climate_wear_now_g", Vector4(frost_now(Game.day), Game.day, 0.0, 0.0))
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_origin = _next_origin
		_tex.update(Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _next))
		RenderingServer.global_shader_parameter_set("climate_wear_map_g", _tex)
		RenderingServer.global_shader_parameter_set("climate_wear_rect_g", Vector4(_origin.x, _origin.y, SPAN, 0.0))
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = cam.global_position if cam != null else (target.global_position if target != null else Vector3.ZERO)
	var mid := _origin + Vector2.ONE * SPAN * 0.5
	if absf(at.x - mid.x) > RECENTER or absf(at.z - mid.y) > RECENTER or not _origin.is_finite():
		_next_origin = (Vector2(at.x, at.z) / 64.0).floor() * 64.0 - Vector2.ONE * SPAN * 0.5
		_task = WorkerThreadPool.add_task(_build)

func _build() -> void:
	_next = map_bytes(_field, _next_origin, SPAN, RES)

## The levels over a square (origin x/z, side in metres) as RGBA8 texels, row by row from
## the origin: moss, cold, dust, bog (see levels()).
static func map_bytes(f: WorldField, origin: Vector2, span: float, res: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(res * res * 4)
	var step := span / res
	for j in res:
		for i in res:
			var c := levels(f, origin.x + (i + 0.5) * step, origin.y + (j + 0.5) * step)
			var k := (j * res + i) * 4
			out[k] = int(round(c.r * 255.0))
			out[k + 1] = int(round(c.g * 255.0))
			out[k + 2] = int(round(c.b * 255.0))
			out[k + 3] = int(round(c.a * 255.0))
	return out

## How a place weathers, each 0..1: r moss (how wet and mild: 0.45 temperate, 1 rain
## forest and fen, 0 desert), g cold (snow lies and frost forms: 0.5 at the edge of the
## cold belt, 1 deep in it; the shaders add the cold of height toward the snow line),
## b dust (dry, warm deserts), a bog (wet, low ground where fog lies).
static func levels(f: WorldField, x: float, z: float) -> Color:
	var c := f.climate_at(x, z)
	var lf := clampi(f.landform_at(x, z), 0, LF_DUST.size() - 1)
	var wet := clampf(c.y + WorldField.LF_WET[lf], 0.0, 1.0)
	var warm := c.x
	var cold := 1.0 - smoothstep(0.08, 0.32, warm)
	# Moss wants wet and mild: thinner where it freezes hard.
	var moss := smoothstep(0.18, 0.85, wet) * lerpf(0.45, 1.0, 1.0 - cold)
	var dust := maxf(smoothstep(0.38, 0.1, wet) * smoothstep(0.3, 0.55, warm), LF_DUST[lf] * smoothstep(0.55, 0.3, wet))
	return Color(moss, cold, dust, bog_with(f, x, z, wet, lf))

## How much of a swamp or bog (x, z) is, 0..1: wet ground lying low near the water, or
## among the lake landform's meres. The weather can lay fog there more often.
static func bog(f: WorldField, x: float, z: float) -> float:
	var lf := clampi(f.landform_at(x, z), 0, LF_DUST.size() - 1)
	return bog_with(f, x, z, clampf(f.climate_at(x, z).y + WorldField.LF_WET[lf], 0.0, 1.0), lf)

static func bog_with(f: WorldField, x: float, z: float, wet: float, lf: int) -> float:
	var damp := smoothstep(0.6, 0.85, wet)
	if damp <= 0.0:
		return 0.0
	var low := 1.0 - smoothstep(2.0, 16.0, f.height(x, z) - Water.LEVEL)
	return clampf(damp * maxf(low, 0.7 if lf == WorldField.LF_LAKES else 0.0), 0.0, 1.0)

## How far a piece built on game day `built` has weathered by `now`: 0 new, 1 as old as
## the village round it (pieces with no build day are old).
static func maturity(built: float, now: float) -> float:
	if built < 0.0:
		return 1.0
	return clampf((now - built) / MATURE_DAYS, 0.0, 1.0)

## How much hoar frost the time of day allows, 0..1: it grows through a still night, is
## thickest at dawn and is gone a couple of hours after sunrise. (Where it is cold enough
## is the place's, in the shader.)
static func frost_now(day: float) -> float:
	var u := fposmod(fposmod(day, 1.0) - 0.8, 1.0) # 0 at dusk, 0.45 at sunrise
	return smoothstep(0.0, 0.4, u) * (1.0 - smoothstep(0.48, 0.58, u))
