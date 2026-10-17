class_name Water
extends MeshInstance3D
## A single large water surface that follows the player, so every hollow below sea level
## becomes a lake or sea. Waves are driven by the world wind and grow with depth (open,
## deep water gets big swells; shallows stay calm). The same wave function runs here on
## the CPU so swimming and buoyancy match what is drawn.

const LEVEL := 0.0
const SIZE := 1600.0
## How far the water sheet reaches from its middle (past the distant land's edge).
const REACH := 5400.0
const DEPTH_RES := 128
const MURK_RES := 32
const MAX_CURRENT := 1.9 ## m/s, fast mid-stream; you can still swim against it

var target: Node3D
var atmosphere: Atmosphere
var streamer: ChunkStreamer
var _mat: ShaderMaterial
var _depth_img: Image
var _murk_img: Image
var _murk_tex: ImageTexture
var _depth_tex: ImageTexture
var _depth_origin := Vector2.ZERO
var _depth_timer := 0.0
var _ssr_steps := 20
static var _wind := 0.3
static var _dir := Vector2(0.8, 0.6)
static var _depth_lookup: Callable
static var _river_lookup: Callable
static var _current_lookup: Callable
static var _murk_lookup: Callable

func _ready() -> void:
	mesh = _sheet()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/env/water.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = LEVEL
	_depth_img = Image.create(DEPTH_RES, DEPTH_RES, false, Image.FORMAT_RF)
	_depth_img.fill(Color(20, 0, 0))
	_depth_tex = ImageTexture.create_from_image(_depth_img)
	_murk_img = Image.create(MURK_RES, MURK_RES, false, Image.FORMAT_RF)
	_murk_tex = ImageTexture.create_from_image(_murk_img)
	_mat.set_shader_parameter("murk_map", _murk_tex)
	_mat.set_shader_parameter("depth_map", _depth_tex)
	_depth_lookup = depth_at
	_river_lookup = river_at
	_current_lookup = current_at
	_murk_lookup = murk_at
	add_child(Splashes.new())
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(_apply_settings)
		_apply_settings()

## Reflections of shores and banks on the water (water_ssr.gdshaderinc) follow the
## "Screen-space reflections" setting. (The autoload is looked up rather than named, so
## Water and everything that asks it about the water still compile without autoloads,
## as in the unit tests.)
func _apply_settings() -> void:
	_ssr_steps = 20 if bool(get_node("/root/Settings").get_value("ssr")) else 0
	_mat.set_shader_parameter("ssr_steps", _ssr_steps)

func _process(delta: float) -> void:
	if target:
		var p := target.global_position
		position = Vector3(snappedf(p.x, 32.0), LEVEL, snappedf(p.z, 32.0))
	if atmosphere:
		var w := atmosphere.current_weights()
		_mat.set_shader_parameter("shallow", Color(0.16, 0.36, 0.38) * w[0] + Color(0.1, 0.45, 0.5) * w[1] + Color(0.12, 0.28, 0.36) * w[2])
		_mat.set_shader_parameter("glow_amount", w[1] * 0.12)
		if ChunkNode.river_material:
			ChunkNode.river_material.set_shader_parameter("shallow", Color(0.26, 0.38, 0.28) * w[0] + Color(0.12, 0.5, 0.52) * w[1] + Color(0.2, 0.32, 0.3) * w[2])
			ChunkNode.river_material.set_shader_parameter("glow_amount", w[1] * 0.12)
			ChunkNode.river_material.set_shader_parameter("ssr_steps", _ssr_steps)
		_wind = atmosphere.wind_strength
		_dir = atmosphere.wind_dir
	_depth_timer -= delta
	if _depth_timer <= 0.0 and streamer != null and _depth_row < 0:
		_depth_timer = 1.5
		# Only when the sheet moved or ground came or went (a dig is caught within 15 s).
		var sig := "%s %d %d" % [position, streamer.chunks.size(), Time.get_ticks_msec() / 15000]
		if sig != _depth_sig:
			_depth_sig = sig
			_depth_row = 0
			_depth_next_origin = Vector2(position.x, position.z) - Vector2(SIZE, SIZE) * 0.5
	if _depth_row >= 0 and streamer != null:
		_update_depth()

## The water sheet: 2 m squares round the middle, so the swell's shorter waves are drawn
## in the surface itself (not just shaded on it), easing out to 8 m squares across the
## middle SIZE metres, then squares growing outwards to REACH, so the sea runs on to the
## horizon under the distant land (FarLand) instead of ending in a square edge.
const FINE := 120.0 ## metres either side of the middle in 2 m squares
static func _sheet() -> ArrayMesh:
	var half := PackedFloat32Array() # 0 and the lines out from the middle, one side
	var x := 0.0
	var step := 2.0
	half.append(0.0)
	while x < SIZE * 0.5:
		if x >= FINE:
			step = minf(step * 1.06, SIZE / 200.0)
		x = minf(x + step, SIZE * 0.5)
		half.append(x)
	while x < REACH:
		step *= 1.12
		x = minf(x + step, REACH)
		half.append(x)
	var cs := PackedFloat32Array()
	for i in range(half.size() - 1, 0, -1):
		cs.append(-half[i])
	cs.append_array(half)
	var n := cs.size()
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for j in n:
		for i in n:
			verts[j * n + i] = Vector3(cs[i], 0.0, cs[j])
			norms[j * n + i] = Vector3.UP
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## Water depth map around the player (metres below sea level, 0 on land), so the shader
## can grow waves over deep water and calm them in the shallows. A coarser map beside it
## says how murky the water is (see _murk).
## The depth map is built a few rows a frame into a second buffer and swapped in whole:
## all 16k samples at once froze the game for 30-40 ms every 1.5 s.
const DEPTH_ROWS_PER_FRAME := 6
var _depth_row := -1 ## next row of the map being built, -1 while idle
var _depth_next := PackedFloat32Array()
var _depth_next_origin := Vector2.ZERO
var _depth_sig := ""

func _update_depth() -> void:
	if _depth_next.size() != DEPTH_RES * DEPTH_RES:
		_depth_next.resize(DEPTH_RES * DEPTH_RES)
	var step := SIZE / DEPTH_RES
	var last := Vector2i(1 << 30, 0)
	var c: ChunkNode = null
	for j in range(_depth_row, mini(_depth_row + DEPTH_ROWS_PER_FRAME, DEPTH_RES)):
		for i in DEPTH_RES:
			var x := _depth_next_origin.x + (i + 0.5) * step
			var z := _depth_next_origin.y + (j + 0.5) * step
			var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
			if k != last:
				last = k
				c = streamer.get_chunk(k)
			var d := 12.0
			if c != null:
				d = clampf(LEVEL - ChunkGenerator.height_at(c.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE), 0.0, 40.0)
			_depth_next[j * DEPTH_RES + i] = d
	_depth_row += DEPTH_ROWS_PER_FRAME
	if _depth_row < DEPTH_RES:
		return
	_depth_row = -1
	_depth_img = Image.create_from_data(DEPTH_RES, DEPTH_RES, false, Image.FORMAT_RF, _depth_next.to_byte_array())
	_depth_origin = _depth_next_origin
	_depth_tex.update(_depth_img)
	_murk_img = Image.create_from_data(MURK_RES, MURK_RES, false, Image.FORMAT_RF, _murk(_depth_next).to_byte_array())
	_murk_tex.update(_murk_img)
	_mat.set_shader_parameter("depth_origin", _depth_origin)
	_mat.set_shader_parameter("depth_size", SIZE)
	# The terrain reads it too, so beaches on sheltered ponds barely get a wash.
	RenderingServer.global_shader_parameter_set("water_map", _depth_tex)
	RenderingServer.global_shader_parameter_set("water_murk", _murk_tex)
	RenderingServer.global_shader_parameter_set("water_map_rect", Vector4(_depth_origin.x, _depth_origin.y, SIZE, 0.0))

## How murky the water is across the depth map (on a coarser 50 m grid): 0 for open sea
## (clear and blue), 1 for ponds and small lakes (green-brown with silt). Judged by how
## much of the 400 m round each point is water and how deep that water runs on average,
## from summed-area tables. About a thousand cells, so it costs nothing next to the map.
static func _murk(depths: PackedFloat32Array) -> PackedFloat32Array:
	var n := MURK_RES + 1
	var f := DEPTH_RES / MURK_RES
	var wet := PackedFloat32Array()
	var deep := PackedFloat32Array()
	wet.resize(n * n)
	deep.resize(n * n)
	for j in MURK_RES:
		for i in MURK_RES:
			var d := depths[(j * f + f / 2) * DEPTH_RES + i * f + f / 2]
			var k := (j + 1) * n + i + 1
			wet[k] = (1.0 if d > 0.3 else 0.0) + wet[k - 1] + wet[k - n] - wet[k - n - 1]
			deep[k] = d + deep[k - 1] + deep[k - n] - deep[k - n - 1]
	var r := int(200.0 / (SIZE / MURK_RES))
	var out := PackedFloat32Array()
	out.resize(MURK_RES * MURK_RES)
	for j in MURK_RES:
		for i in MURK_RES:
			var x0 := maxi(i - r, 0)
			var x1 := mini(i + r + 1, MURK_RES)
			var z0 := maxi(j - r, 0)
			var z1 := mini(j + r + 1, MURK_RES)
			var area := float((x1 - x0) * (z1 - z0))
			var w := wet[z1 * n + x1] - wet[z0 * n + x1] - wet[z1 * n + x0] + wet[z0 * n + x0]
			var dsum := deep[z1 * n + x1] - deep[z0 * n + x1] - deep[z1 * n + x0] + deep[z0 * n + x0]
			var mean_depth := dsum / maxf(w, 1.0)
			# A straight sea shore is still half water; a pond is a few hundredths of the window.
			out[j * MURK_RES + i] = 1.0 - smoothstep(0.15, 0.45, w / area) * smoothstep(2.5, 9.0, mean_depth)
	return out

## How murky the lake or sea at (x, z) is: 0 clear open sea, 1 a silty pond.
static func turbidity(x: float, z: float) -> float:
	return _murk_lookup.call(x, z) if _murk_lookup.is_valid() else 0.0

func murk_at(x: float, z: float) -> float:
	var u := (x - _depth_origin.x) / SIZE * DEPTH_RES
	var v := (z - _depth_origin.y) / SIZE * DEPTH_RES
	if u < 0 or v < 0 or u >= DEPTH_RES or v >= DEPTH_RES:
		return 0.0
	return _murk_img.get_pixel(int(u * MURK_RES / DEPTH_RES), int(v * MURK_RES / DEPTH_RES)).r

func depth_at(x: float, z: float) -> float:
	var u := (x - _depth_origin.x) / SIZE * DEPTH_RES
	var v := (z - _depth_origin.y) / SIZE * DEPTH_RES
	if u < 0 or v < 0 or u >= DEPTH_RES or v >= DEPTH_RES:
		return 12.0
	return _depth_img.get_pixel(int(u), int(v)).r

## Wave amplitude scale: a light swell even in a calm, rising with the wind squared, times
## an open-water factor (ponds and shallows stay low). Must match swell_amp() in
## water_swell.gdshaderinc.
static func amplitude(depth: float) -> float:
	var open := smoothstep(0.5, 14.0, depth)
	return (0.18 + _wind * _wind * 1.2) * (0.15 + 0.85 * open)

## The swell's waves (as water_swell.gdshaderinc): lengths, heights (times amplitude())
## and how far each turns from the wind.
const SWELL_LENS: Array[float] = [64.0, 38.0, 21.0, 13.0, 7.0]
const SWELL_AMPS: Array[float] = [0.5, 0.45, 0.35, 0.25, 0.14]
const SWELL_TURN: Array[float] = [-0.2, 0.0, 0.6, -0.45, 1.3]
const SWELL_PEAK := 1.69 ## the sum of SWELL_AMPS: the highest crest, in amplitudes
## The most a wake may lift the water (what boats write into the wake map stays under it).
const WAKE_MAX := 0.6

## Wakes boats leave, as height above the swell: `tex` (an RF texture, metres) covers the
## square from `origin` (x, z), `size` metres across, and `lookup(x, z)` answers the same
## heights for things that float. The water and the boat foam rise and fall with it.
## set_wakes(null, ...) clears them.
static var _wake_lookup: Callable

static func set_wakes(tex: Texture2D, origin: Vector2, size: float, lookup: Callable) -> void:
	_wake_lookup = lookup if tex != null else Callable()
	RenderingServer.global_shader_parameter_set("water_wake_map", tex)
	RenderingServer.global_shader_parameter_set("water_wake_rect", Vector4(origin.x, origin.y, size if tex != null else 0.0, 0.0))

## A river's water level at (x, z), or NAN where there is no river. Blended between the
## 2 m river cells, so swimming down a river doesn't step from cell to cell.
func river_at(x: float, z: float) -> float:
	if is_nan(_river_cell(x, z).x):
		return NAN
	var gx := x * 0.5
	var gz := z * 0.5
	var ix := floorf(gx)
	var iz := floorf(gz)
	var fx := gx - ix
	var fz := gz - iz
	var sum := 0.0
	var wsum := 0.0
	for c in 4:
		var ox := float(c & 1)
		var oz := float(c >> 1)
		var lv := _river_cell((ix + ox) * 2.0, (iz + oz) * 2.0).x
		if is_nan(lv):
			continue
		var w := (fx if ox > 0.0 else 1.0 - fx) * (fz if oz > 0.0 else 1.0 - fz)
		sum += lv * w
		wsum += w
	return sum / wsum if wsum > 0.0001 else _river_cell(x, z).x

## The river cell at (x, z): x = its water level (NAN where dry), y = how far across the
## river it lies (0 mid-stream, 1 at the bank).
func _river_cell(x: float, z: float) -> Vector2:
	if streamer == null:
		return Vector2(NAN, 1.0)
	var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
	var c := streamer.get_chunk(k)
	if c == null or not c.data.has("river"):
		return Vector2(NAN, 1.0)
	var lx := x - k.x * ChunkGenerator.SIZE
	var lz := z - k.y * ChunkGenerator.SIZE
	var lv := ChunkGenerator.river_surface(c.data, lx, lz)
	if is_nan(lv):
		return Vector2(NAN, 1.0)
	var rv: PackedFloat32Array = c.data["river"]
	var N := ChunkGenerator.RIVER_N
	var i := clampi(int(round(lx * 0.5)), 0, N - 1)
	var j := clampi(int(round(lz * 0.5)), 0, N - 1)
	return Vector2(lv, rv[(j * N + i) * 3 + 1])

## How the water moves at (x, z), in metres per second across the ground: rivers run
## downhill, fastest mid-stream and slack at the banks; lakes and the sea drift a little
## with the wind.
static func current(x: float, z: float) -> Vector2:
	if _current_lookup.is_valid():
		var c: Vector2 = _current_lookup.call(x, z)
		if not is_nan(c.x):
			return c
	return _dir.normalized() * _wind * 0.25

func current_at(x: float, z: float) -> Vector2:
	var here := _river_cell(x, z)
	if is_nan(here.x) or here.x <= LEVEL:
		return Vector2(NAN, NAN)
	var g := Vector2.ZERO
	for a in [Vector2(2, 0), Vector2(0, 2)]:
		var hi := _river_cell(x + a.x, z + a.y).x
		var lo := _river_cell(x - a.x, z - a.y).x
		var d := 0.0
		if not is_nan(hi) and not is_nan(lo):
			d = (hi - lo) * 0.25
		elif not is_nan(hi):
			d = (hi - here.x) * 0.5
		elif not is_nan(lo):
			d = (here.x - lo) * 0.5
		if a.x > 0.0:
			g.x = d
		else:
			g.y = d
	if g.length() < 0.0005:
		return Vector2.ZERO
	var speed := clampf(0.6 + g.length() * 30.0, 0.6, MAX_CURRENT) * (1.0 - smoothstep(0.35, 1.05, here.y) * 0.85)
	return -g.normalized() * speed

## The highest the sea's waves reach right now (surface_height never goes above it,
## rivers aside).
static func wave_top() -> float:
	return LEVEL + amplitude(14.0) * SWELL_PEAK + (WAKE_MAX if _wake_lookup.is_valid() else 0.0)

## A river's surface at (x, z) where it runs above the sea, else NAN.
static func river_surface(x: float, z: float) -> float:
	if _river_lookup.is_valid():
		var r: float = _river_lookup.call(x, z)
		if not is_nan(r) and r > LEVEL:
			return r
	return NAN

## Height of the water surface at (x, z) and time t: a river where there is one, else the
## sea (whose waves must match water_swell.gdshaderinc, which the water and boat foam use).
static func surface_height(x: float, z: float, t: float) -> float:
	if _river_lookup.is_valid():
		var r: float = _river_lookup.call(x, z)
		if not is_nan(r) and r > LEVEL:
			return r
	var depth: float = _depth_lookup.call(x, z) if _depth_lookup.is_valid() else 12.0
	var a := amplitude(depth)
	var d := _dir.normalized()
	var p := Vector2(x, z)
	var h := 0.0
	for i in SWELL_LENS.size():
		var k := TAU / SWELL_LENS[i]
		var c := sqrt(9.8 / k)
		h += SWELL_AMPS[i] * sin(k * (p.dot(d.rotated(SWELL_TURN[i])) - c * t))
	var w := 0.0
	if _wake_lookup.is_valid():
		w = clampf(float(_wake_lookup.call(x, z)), -WAKE_MAX, WAKE_MAX)
	return LEVEL + h * a + w
