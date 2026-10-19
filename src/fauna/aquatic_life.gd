class_name AquaticLife
extends Node3D
## Fish, crabs and crayfish in the water around the player. Like the herds on land, what
## lives in each chunk's water is a pure function of the world seed and the chunk (what
## kind of water it is: pond, lake, river, reef or open sea), so it needs no saving and
## every world has it, old ones too. Nothing here can be hunted yet; they are there to be
## seen: schools turning together, scattering when you swim at them, trout holding still
## against a river's current, crabs sidling over the bed, and now and then a fish leaping
## clear of a lake.

const RADIUS := 1 ## chunks around the player whose water is alive
const DRAW := 90.0 ## metres: fish further away are not drawn or moved
const FLEE := 4.5 ## metres: closer than this and a school bolts

## Fish species: mesh kind, marking pattern (fish.gdshader), length range (m), school size,
## cruising speed (m/s), school spread (m), where they swim (bottom, mid, reef, hold: on
## station in a current), least depth (m), tail beats a second at a cruise.
const FISH := {
	"minnow": ["slim", 5, Vector2(0.05, 0.08), Vector2i(15, 40), 0.5, 0.8, "mid", 0.4, 4.0],
	"perch": ["deep", 2, Vector2(0.15, 0.3), Vector2i(6, 16), 0.45, 1.4, "mid", 1.2, 2.5],
	"trout": ["slim", 3, Vector2(0.25, 0.5), Vector2i(1, 3), 0.6, 2.5, "mid", 1.0, 2.0],
	"carp": ["deep", 4, Vector2(0.4, 0.75), Vector2i(1, 3), 0.3, 2.5, "bottom", 1.5, 1.3],
	"pike": ["long", 12, Vector2(0.5, 0.9), Vector2i(1, 1), 0.25, 0.0, "mid", 1.5, 1.2],
	"river_trout": ["slim", 3, Vector2(0.22, 0.45), Vector2i(1, 4), 0.0, 1.5, "hold", 0.6, 2.2],
	"sardine": ["slim", 0, Vector2(0.14, 0.22), Vector2i(40, 90), 1.0, 2.4, "mid", 3.0, 4.0],
	"mackerel": ["slim", 1, Vector2(0.25, 0.4), Vector2i(12, 30), 1.3, 2.6, "mid", 3.0, 3.2],
	"bream": ["deep", 6, Vector2(0.25, 0.4), Vector2i(4, 9), 0.55, 2.0, "bottom", 2.0, 2.2],
	"tang": ["disc", 7, Vector2(0.12, 0.22), Vector2i(3, 8), 0.45, 1.5, "reef", 1.0, 2.6],
	"damsel": ["deep", 8, Vector2(0.06, 0.1), Vector2i(6, 14), 0.35, 1.0, "reef", 0.8, 3.5],
	"clown": ["deep", 9, Vector2(0.07, 0.1), Vector2i(2, 4), 0.2, 0.5, "reef", 1.0, 3.5],
	"parrot": ["deep", 10, Vector2(0.3, 0.5), Vector2i(1, 4), 0.45, 2.5, "reef", 1.5, 1.8],
}
## Which fish live where, with weights.
const WATERS := {
	"lake": [["minnow", 3.0], ["perch", 3.0], ["trout", 1.5], ["carp", 1.5], ["pike", 0.7]],
	"river": [["river_trout", 3.0], ["minnow", 1.0]],
	"sea": [["sardine", 2.0], ["mackerel", 2.0], ["bream", 1.5]],
	"reef": [["tang", 2.0], ["damsel", 2.5], ["clown", 1.2], ["parrot", 1.2], ["bream", 0.6]],
}
## Shell colours (sRGB): green shore crabs, red-brown and sandy crabs; crayfish olive-brown.
const CRAB_TINTS := [Color(0.3, 0.36, 0.16), Color(0.5, 0.25, 0.14), Color(0.62, 0.48, 0.3), Color(0.42, 0.22, 0.2)]
const CRAYFISH_TINTS := [Color(0.3, 0.26, 0.15), Color(0.36, 0.24, 0.16), Color(0.24, 0.24, 0.18)]

var streamer: ChunkStreamer
var player: Node3D
## Nothing takes fright (staged screenshots, where the camera is the player).
var calm := false
var _field: AquaFlora.Field
var _groups: Dictionary = {} ## Vector2i chunk -> Array of School / Crawlers
var _scan := 0.0
var _leap_t := 6.0
var _leaps: Array = []
var _rng := RandomNumberGenerator.new()

static var _fish_mat: ShaderMaterial
static var _crab_mat: ShaderMaterial

func _ready() -> void:
	_field = AquaFlora.Field.new(Game.seed)
	_rng.randomize()
	if _fish_mat == null:
		_fish_mat = ShaderMaterial.new()
		_fish_mat.shader = load("res://src/fauna/fish.gdshader")
		_crab_mat = ShaderMaterial.new()
		_crab_mat.shader = load("res://src/fauna/crab.gdshader")

func _process(delta: float) -> void:
	if player == null or streamer == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 1.0
		_refresh()
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else player.global_position
	var threat := player.global_position + Vector3(0, 0.9, 0)
	if calm:
		threat = Vector3(0, -10000, 0)
	for k in _groups:
		for g in _groups[k]:
			g.step(self, minf(delta, 0.1), eye, threat)
	_step_leaps(delta, eye)

## Spawns the water life of chunks that came near and frees the ones left behind.
func _refresh() -> void:
	var pk := ChunkStreamer.chunk_of(player.global_position)
	for k in _groups.keys():
		if absi(k.x - pk.x) > RADIUS + 1 or absi(k.y - pk.y) > RADIUS + 1:
			for g in _groups[k]:
				g.free_node()
			_groups.erase(k)
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := pk + Vector2i(dx, dz)
			if _groups.has(k):
				continue
			var c := streamer.get_chunk(k)
			if c == null:
				continue
			_groups[k] = _spawn(k, c.data)

# --- What lives where -------------------------------------------------------------

func _spawn(k: Vector2i, d: Dictionary) -> Array:
	var out: Array = []
	var lowest := INF
	for h in (d["heights"] as PackedFloat32Array):
		lowest = minf(lowest, h)
	var wet_river := d.has("river")
	if lowest > -0.4 and not wet_river:
		return out
	var r := WHash.rng(Game.seed, k.x, k.y, 951)
	var x0 := float(k.x) * ChunkGenerator.SIZE
	var z0 := float(k.y) * ChunkGenerator.SIZE
	for attempt in 6:
		var lx := r.randf() * ChunkGenerator.SIZE
		var lz := r.randf() * ChunkGenerator.SIZE
		var roll := r.randf()
		var y := ChunkGenerator.height_at(d, lx, lz)
		var river := ChunkGenerator.under_river(d, lx, lz)
		var top := ChunkGenerator.river_surface(d, lx, lz) if river else Water.LEVEL
		if is_nan(top) or top - y < 0.45 or roll > 0.8:
			continue
		var wx := x0 + lx
		var wz := z0 + lz
		var sea := _field.sea_t(wx, wz)
		var water := "lake"
		if river and top > Water.LEVEL + 0.2:
			water = "river"
		elif sea > 0.5:
			water = "reef" if _field.patch(wx, wz) > -0.1 and _field.warm(wx, wz) > 0.5 and top - y < 14.0 else "sea"
		var sp := _pick(water, top - y, r)
		if sp == "":
			continue
		out.append(School.new(self, sp, Vector3(wx, lerpf(y, top, 0.5), wz), top, r))
	# Crabs over the sea bed and in the shallows, crayfish under lake stones.
	for attempt in 2:
		var lx := r.randf() * ChunkGenerator.SIZE
		var lz := r.randf() * ChunkGenerator.SIZE
		var roll := r.randf()
		var y := ChunkGenerator.height_at(d, lx, lz)
		if ChunkGenerator.under_river(d, lx, lz) or y > -0.25 or y < -6.0:
			continue
		var sea := _field.sea_t(x0 + lx, z0 + lz)
		if sea > 0.4 and roll < 0.55:
			out.append(Crawlers.new(self, "crab", Vector3(x0 + lx, y, z0 + lz), r.randi_range(2, 5), r))
		elif sea < 0.3 and roll < 0.35 and y > -3.0:
			out.append(Crawlers.new(self, "crayfish", Vector3(x0 + lx, y, z0 + lz), r.randi_range(1, 3), r))
	return out

func _pick(water: String, depth: float, r: RandomNumberGenerator) -> String:
	var opts: Array = []
	var total := 0.0
	for o in WATERS[water]:
		if depth >= float(FISH[o[0]][7]):
			opts.append(o)
			total += float(o[1])
	var u := r.randf() * total
	for o in opts:
		u -= float(o[1])
		if u <= 0.0:
			return o[0]
	return ""

## The bed under (x, z), or NAN where no chunk is loaded.
func bed(x: float, z: float) -> float:
	var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
	var c := streamer.get_chunk(k)
	if c == null:
		return NAN
	return ChunkGenerator.height_at(c.data, x - k.x * ChunkGenerator.SIZE, z - k.y * ChunkGenerator.SIZE)

## The water surface over (x, z): a river's own level, or the lake and sea level.
func surface(x: float, z: float) -> float:
	var k := ChunkStreamer.chunk_of(Vector3(x, 0, z))
	var c := streamer.get_chunk(k)
	if c != null and c.data.has("river"):
		var lx := x - k.x * ChunkGenerator.SIZE
		var lz := z - k.y * ChunkGenerator.SIZE
		if ChunkGenerator.under_river(c.data, lx, lz):
			var lv := ChunkGenerator.river_surface(c.data, lx, lz)
			if not is_nan(lv):
				return lv
	return Water.LEVEL

## A MultiMeshInstance for `count` instances of `mesh` around `at`.
func _batch(mesh: Mesh, mat: Material, count: int, at: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	# They roam a few tens of metres from home; a fixed box saves working it out each frame.
	mm.custom_aabb = AABB(Vector3(-45, -30, -45), Vector3(90, 60, 90))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	mmi.global_position = at
	return mmi

## Instance `i` of a multimesh buffer (transform rows, then the custom data).
static func _write(buf: PackedFloat32Array, i: int, b: Basis, o: Vector3, c: Color) -> void:
	var v := [b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z, c.r, c.g, c.b, c.a]
	for j in 16:
		buf[i * 16 + j] = v[j]

# --- Leaping fish -----------------------------------------------------------------

## Now and then a fish jumps clear of a lake or the sea within sight of the shore.
func _step_leaps(delta: float, eye: Vector3) -> void:
	_leap_t -= delta
	if _leap_t <= 0.0:
		_leap_t = _rng.randf_range(5.0, 15.0)
		if not (player.get("underwater") == true):
			_try_leap(eye)
	for i in range(_leaps.size() - 1, -1, -1):
		var l: Dictionary = _leaps[i]
		l["t"] += delta
		var s: float = l["t"] / l["dur"]
		var mmi: MultiMeshInstance3D = l["node"]
		if s >= 1.0:
			Splashes.splash(l["p1"], 0.3)
			Splashes.ring(l["p1"], 0.7)
			mmi.queue_free()
			_leaps.remove_at(i)
			continue
		var p0: Vector3 = l["p0"]
		var p1: Vector3 = l["p1"]
		var h: float = l["h"]
		var p := p0.lerp(p1, s) + Vector3(0, 4.0 * h * s * (1.0 - s), 0)
		var dir := (p1 - p0).normalized() + Vector3(0, 4.0 * h * (1.0 - 2.0 * s) / maxf(p0.distance_to(p1), 0.1), 0)
		var b := Basis.looking_at(dir.normalized(), Vector3.UP, true).scaled(Vector3.ONE * float(l["size"]))
		mmi.multimesh.set_instance_transform(0, Transform3D(b, p - mmi.global_position))
		mmi.multimesh.set_instance_custom_data(0, Color(l["pat"], fmod(l["t"] * 5.0, 1.0), 1.0, 0.3))

func _try_leap(eye: Vector3) -> void:
	for tries in 6:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(10.0, 45.0)
		var x := eye.x + cos(a) * d
		var z := eye.z + sin(a) * d
		var b := bed(x, z)
		if is_nan(b) or Water.LEVEL - b < 1.2 or surface(x, z) > Water.LEVEL + 0.1:
			continue
		var sea := _field.sea_t(x, z)
		var sp := "mackerel" if sea > 0.5 else ("trout" if _rng.randf() < 0.6 else "perch")
		var f: Array = FISH[sp]
		var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
		var size := _rng.randf_range(f[2].x, f[2].y)
		var p0 := Vector3(x, Water.LEVEL, z)
		var p1 := p0 + dir * _rng.randf_range(0.6, 1.4) * (size / 0.3)
		var mmi := _batch(FishKit.mesh(f[0]), _fish_mat, 1, p0)
		mmi.multimesh.custom_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
		var pat := float(int(f[1])) + _rng.randf() * 0.99
		_leaps.append({"node": mmi, "p0": p0, "p1": p1, "h": _rng.randf_range(0.35, 0.8), "t": 0.0, "dur": _rng.randf_range(0.55, 0.8), "size": size, "pat": pat})
		Splashes.splash(p0, 0.25)
		return

# --- A school of fish ---------------------------------------------------------------

class School:
	var mmi: MultiMeshInstance3D
	var f: Array
	var home: Vector3
	var center: Vector3
	var vel := Vector3.ZERO
	var target: Vector3
	var retarget := 0.0
	var top: float
	var fear := 0.0
	var pos := PackedVector3Array()
	var fvel := PackedVector3Array()
	var facing := PackedVector3Array()
	var offs := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var phase := PackedFloat32Array()
	var marks := PackedFloat32Array()
	var seeds := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var hold: bool

	func _init(life: AquaticLife, sp: String, at: Vector3, water_top: float, r: RandomNumberGenerator) -> void:
		f = FISH[sp]
		home = at
		center = at
		target = at
		top = water_top
		hold = f[6] == "hold"
		rng.seed = r.randi()
		var n := rng.randi_range(f[3].x, f[3].y)
		var base := rng.randf_range(f[2].x, f[2].y)
		var spread: float = f[5]
		mmi = life._batch(FishKit.mesh(f[0]), AquaticLife._fish_mat, n, at)
		var pattern := int(f[1])
		var heading := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		for i in n:
			# A school is a loose ellipsoid, longer than it is wide, flatter than either.
			var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 0.35), rng.randf_range(-1.4, 1.4)) * spread * 0.5
			if hold:
				o = Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * spread
			offs.append(o)
			pos.append(at + o)
			fvel.append(Vector3.ZERO)
			facing.append(heading)
			sizes.append(base * rng.randf_range(0.82, 1.18))
			phase.append(rng.randf())
			marks.append(float(pattern) + rng.randf() * 0.99)
			seeds.append(rng.randf())

	func free_node() -> void:
		if is_instance_valid(mmi):
			mmi.queue_free()

	func _pick_target(life: AquaticLife) -> void:
		retarget = rng.randf_range(4.0, 12.0)
		if hold:
			target = home
			return
		for tries in 6:
			var a := rng.randf() * TAU
			var d := rng.randf_range(3.0, 22.0)
			var x := home.x + cos(a) * d
			var z := home.z + sin(a) * d
			var b := life.bed(x, z)
			if is_nan(b) or top - b < float(f[7]) * 0.8:
				continue
			var y := 0.0
			match f[6]:
				"bottom":
					y = b + rng.randf_range(0.3, 0.9)
				"reef":
					y = b + rng.randf_range(0.4, 1.8)
				_:
					y = lerpf(b + 0.5, top - 0.5, rng.randf())
			target = Vector3(x, clampf(y, b + 0.3, top - 0.35), z)
			return
		target = home

	func step(life: AquaticLife, dt: float, eye: Vector3, threat: Vector3) -> void:
		# From above the surface only the near ones show through the water.
		var near := center.distance_to(eye) < (DRAW if eye.y < top + 0.3 else DRAW * 0.5)
		mmi.visible = near
		if not near:
			return
		var speed: float = f[4]
		var to_threat := center - threat
		if to_threat.length() < FLEE + float(f[5]):
			fear = 1.0
		fear = maxf(fear - dt * 0.35, 0.0)
		retarget -= dt
		if retarget <= 0.0 or (not hold and center.distance_to(target) < 1.5):
			_pick_target(life)
		var desired := (target - center).limit_length(1.0) * maxf(speed, 0.3)
		if fear > 0.0:
			var away := Vector3(to_threat.x, to_threat.y * 0.3, to_threat.z).normalized()
			desired = desired.lerp(away * maxf(speed, 0.5) * 3.5, fear)
		vel = vel.lerp(desired, 1.0 - exp(-dt * (3.0 if fear > 0.5 else 1.2)))
		var next := center + vel * dt
		var b := life.bed(next.x, next.z)
		if is_nan(b) or top - b < 0.35:
			# The shore: turn back toward home.
			vel = (home - center).normalized() * maxf(speed, 0.3) * 0.5
			retarget = 0.0
		else:
			center = next
			center.y = clampf(center.y, b + 0.25, top - 0.3)
		# Which way the school as a whole faces (rivers: up into the current).
		var fwd := vel
		if hold and fear < 0.3:
			var c := Water.current(center.x, center.z)
			if c.length() > 0.05:
				fwd = -Vector3(c.x, 0.0, c.y)
		if fwd.length() < 0.02:
			fwd = facing[0]
		fwd.y = clampf(fwd.y, -0.4 * fwd.length(), 0.4 * fwd.length())
		var turn := Basis.looking_at(fwd.normalized(), Vector3.UP, true)
		var spread := 1.0 + fear * 1.5
		var origin := mmi.global_position
		var buf := PackedFloat32Array()
		buf.resize(pos.size() * 16)
		var floor_y := (b if not is_nan(b) else center.y - 1.0) + 0.12
		for i in pos.size():
			var goal := center + turn * offs[i] * spread
			var fv := fvel[i]
			var acc := (goal - pos[i]) * (2.2 + fear * 3.0) - fv * 1.4
			# A little wander of its own, so the school never moves as one block.
			acc += Vector3(sin(phase[i] * 7.0 + seeds[i] * 20.0), sin(phase[i] * 3.0 + seeds[i] * 9.0) * 0.3, cos(phase[i] * 5.0 + seeds[i] * 13.0)) * 0.25
			fv += acc * dt
			fv = fv.limit_length(maxf(speed, 0.5) * (2.0 + fear * 3.0))
			var p := pos[i] + fv * dt
			p.y = clampf(p.y, floor_y, top - 0.12)
			pos[i] = p
			fvel[i] = fv
			var face := fv if fv.length() > 0.08 else fwd
			if hold and fear < 0.3:
				face = fwd
			face.y = clampf(face.y, -0.5 * face.length(), 0.5 * face.length())
			var fd := facing[i].slerp(face.normalized(), 1.0 - exp(-dt * 4.0)) if face.length() > 0.001 else facing[i]
			if not fd.is_normalized():
				fd = fd.normalized() if fd.length() > 0.001 else Vector3.FORWARD
			facing[i] = fd
			var effort := clampf(fv.length() / maxf(speed, 0.4) * 0.5, 0.0, 1.0)
			phase[i] = fmod(phase[i] + dt * float(f[8]) * (0.5 + effort * 1.8), 1000.0)
			var basis := Basis.looking_at(fd, Vector3.UP, true).scaled(Vector3.ONE * sizes[i])
			AquaticLife._write(buf, i, basis, p - origin, Color(marks[i], fmod(phase[i], 1.0), effort, seeds[i]))
		# One upload for the whole school.
		mmi.multimesh.buffer = buf

# --- Crabs and crayfish -------------------------------------------------------------

class Crawlers:
	var mmi: MultiMeshInstance3D
	var kind: String
	var home: Vector3
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var go := PackedFloat32Array() ## current walk speed (crabs: sideways, signed)
	var wait := PackedFloat32Array() ## seconds until it changes its mind
	var phase := PackedFloat32Array()
	var sizes := PackedFloat32Array()
	var tints: Array = []
	var rng := RandomNumberGenerator.new()

	func _init(life: AquaticLife, k: String, at: Vector3, n: int, r: RandomNumberGenerator) -> void:
		kind = k
		home = at
		rng.seed = r.randi()
		mmi = life._batch(FishKit.mesh(k), AquaticLife._crab_mat, n, at)
		var opts: Array = AquaticLife.CRAB_TINTS if k == "crab" else AquaticLife.CRAYFISH_TINTS
		var tint: Color = opts[rng.randi() % opts.size()]
		for i in n:
			var p := at + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
			var b := life.bed(p.x, p.z)
			if is_nan(b) or b > life.surface(p.x, p.z) - 0.12:
				p = at
			else:
				p.y = b
			pos.append(p)
			yaw.append(rng.randf() * TAU)
			go.append(0.0)
			wait.append(rng.randf_range(0.0, 3.0))
			phase.append(rng.randf())
			sizes.append(rng.randf_range(0.07, 0.16) if k == "crab" else rng.randf_range(0.08, 0.13))
			tints.append(Color(tint.r * rng.randf_range(0.85, 1.15), tint.g * rng.randf_range(0.85, 1.15), tint.b * rng.randf_range(0.85, 1.15)))

	func free_node() -> void:
		if is_instance_valid(mmi):
			mmi.queue_free()

	func step(life: AquaticLife, dt: float, eye: Vector3, threat: Vector3) -> void:
		var near := home.distance_to(eye) < DRAW * 0.6
		mmi.visible = near
		if not near:
			return
		var origin := mmi.global_position
		var buf := PackedFloat32Array()
		buf.resize(pos.size() * 16)
		for i in pos.size():
			var p := pos[i]
			var side := Vector3(cos(yaw[i]), 0, -sin(yaw[i])) # the crab's own +X
			var fwd := Vector3(sin(yaw[i]), 0, cos(yaw[i]))
			wait[i] -= dt
			var scared := Vector2(p.x - threat.x, p.z - threat.z).length() < 2.5 and absf(p.y - threat.y) < 2.5
			if scared and absf(go[i]) < 0.5:
				# Bolt away: crabs sideways, crayfish backward with a flick of the tail.
				var away := Vector3(p.x - threat.x, 0, p.z - threat.z).normalized()
				if kind == "crab":
					go[i] = 0.9 * (1.0 if away.dot(side) >= 0.0 else -1.0)
				else:
					go[i] = -1.4 if away.dot(fwd) < 0.0 else 0.7
				wait[i] = rng.randf_range(1.0, 1.8)
			elif wait[i] <= 0.0:
				wait[i] = rng.randf_range(1.0, 5.0)
				if rng.randf() < 0.45:
					go[i] = 0.0
				else:
					go[i] = rng.randf_range(0.08, 0.2) * (1.0 if rng.randf() < 0.5 else -1.0)
					yaw[i] += rng.randf_range(-0.8, 0.8)
				# Never stray far from home.
				if p.distance_to(home) > 5.0:
					var back := (home - p).normalized()
					yaw[i] = atan2(back.x, back.z) - (PI * 0.5 if kind == "crab" else 0.0)
					go[i] = 0.15 if kind == "crab" else 0.15
			var dir := side if kind == "crab" else fwd
			var next := p + dir * go[i] * dt
			var b := life.bed(next.x, next.z)
			if is_nan(b) or b > life.surface(next.x, next.z) - 0.12:
				go[i] = -go[i]
			else:
				p = Vector3(next.x, b, next.z)
			pos[i] = p
			phase[i] = fmod(phase[i] + absf(go[i]) * dt * (9.0 if kind == "crab" else 6.0), 1000.0)
			var basis := Basis(Vector3.UP, yaw[i]).scaled(Vector3.ONE * sizes[i])
			var t: Color = tints[i]
			AquaticLife._write(buf, i, basis, p - origin, Color(t.r, t.g, t.b, fmod(phase[i], 1.0)))
		mmi.multimesh.buffer = buf
