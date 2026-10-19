extends Node
## Audio autoload ("Audio"): buses, one-shot effects, the ambience beds and the music.
##
## Effects are banks of variants under res://assets/audio/sfx ("hit/wood" plays one of
## hit/wood_0.ogg, hit/wood_1.ogg, ...), picked at random with a little pitch jitter so
## repeats never sound mechanical. Ambience is a set of looping layers (wind, birds,
## crickets, water, surf, fantasy shimmer, sci-fi hum, caves) whose volumes follow where
## the player is: era, biome, altitude, time of day, shelter and nearby water. Music
## plays now and then with silence between tracks, picked by mood, and a fight brings
## in battle music until things calm down.
##
## Buses: Master > Music, Effects, Ambience. Effects and Ambience go muffled when you are
## underwater; Ambience also when you are indoors. Volumes come from Settings.

const ROOT := "res://assets/audio/"
const BUSES := ["Music", "Effects", "Ambience"]

## Ambience layers: file under ambience/, and the loudest it gets (linear).
const LAYERS := {
	"wind": ["wind", 0.55], "wind_strong": ["wind_strong", 0.6], "birds": ["birds", 0.5],
	"crickets": ["crickets", 0.45], "water": ["water", 0.6], "surf": ["surf", 0.6],
	"fantasy": ["fantasy", 0.4], "scifi": ["scifi", 0.35], "cave": ["dungeon", 0.7],
	"rain": ["rain", 0.65], "rain_roof": ["rain_roof", 0.7], "hail": ["hail", 0.75],
}

## Music by mood; a mood picks one of its tracks each time it plays.
const MOODS := {
	"menu": ["exploration"],
	"day": ["exploration", "safe_space"],
	"night": ["safe_space"],
	"scifi": ["safe_space", "captains_log"],
	"dungeon": ["horror"],
	"space": ["safe_space", "captains_log"],
	"combat": ["war_march"], ## our own orchestral march (tools/compose_battle.py)
}
const MUSIC_GAP := Vector2(70.0, 200.0) ## seconds of silence between tracks
const COMBAT_HOLD := 9.0 ## seconds after the last blow before battle music lets go

var world: Node = null ## the World scene while you are on a planet (set by World)

var _banks: Dictionary = {} ## "hit/wood" -> Array[AudioStream]
var _last_pick: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _layers: Dictionary = {} ## layer -> AudioStreamPlayer
var _layer_target: Dictionary = {} ## layer -> 0..1
var _loops: Dictionary = {} ## loop name -> AudioStreamPlayer (engines, jetpack)
var _loop_want: Dictionary = {} ## loop name -> [volume 0..1, pitch]

var _music: AudioStreamPlayer
var _music_fade: Tween
var _mood := ""
var _music_gap := 6.0 ## silence left before the next track
var _combat_t := -100.0
var _env_t := 0.0
var _hover_t := 0.0
var _muffle_amb: AudioEffectLowPassFilter
var _muffle_fx: AudioEffectLowPassFilter
var _last_health := -1.0

## What the ambience sampler found last (read by tests and the console).
var env: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_pool.append(p)
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Effects"
		p3.unit_size = 6.0
		p3.max_distance = 60.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	for id in LAYERS:
		var lp := AudioStreamPlayer.new()
		lp.bus = "Ambience"
		lp.stream = _loop_stream("ambience/%s.ogg" % LAYERS[id][0])
		lp.volume_db = -80.0
		add_child(lp)
		_layers[id] = lp
		_layer_target[id] = 0.0
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	Settings.changed.connect(apply_settings)
	apply_settings()
	get_tree().node_added.connect(_on_node_added)
	Game.leveled_up.connect(func(_l): play("jingle/level_up", -4.0, 0.0))
	Game.discovered.connect(func(_t, _s, _c): play("jingle/discovery", -4.0, 0.0))
	Game.died.connect(func(_c): play("jingle/death", -3.0, 0.0))
	Game.money_changed.connect(_on_money)
	Game.item_gained.connect(_on_item)
	Game.equipment_changed.connect(func(): if world != null: play("item/equip", -6.0))
	Game.health_changed.connect(_on_health)

func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	_muffle_amb = AudioEffectLowPassFilter.new()
	_muffle_amb.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), _muffle_amb)
	_muffle_fx = AudioEffectLowPassFilter.new()
	_muffle_fx.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Effects"), _muffle_fx)

func apply_settings() -> void:
	_set_bus("Master", float(Settings.get_value("master_volume")))
	_set_bus("Music", float(Settings.get_value("music_volume")))
	_set_bus("Effects", float(Settings.get_value("sfx_volume")))
	_set_bus("Ambience", float(Settings.get_value("ambience_volume")))

func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)

# --- Banks and one-shots -------------------------------------------------------------

## All variants of an effect ("hit/wood" -> hit/wood_0.ogg, hit/wood_1.ogg, ...).
func bank(sound: String) -> Array:
	if _banks.has(sound):
		return _banks[sound]
	var out: Array = []
	var i := 0
	while true:
		var path := ROOT + "sfx/%s_%d.ogg" % [sound, i]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
		i += 1
	if out.is_empty():
		var single := ROOT + "sfx/%s.ogg" % sound
		if ResourceLoader.exists(single):
			out.append(load(single))
	_banks[sound] = out
	return out

func _pick(sound: String) -> AudioStream:
	var b := bank(sound)
	if b.is_empty():
		return null
	var i := randi() % b.size()
	if b.size() > 1 and i == int(_last_pick.get(sound, -1)):
		i = (i + 1) % b.size()
	_last_pick[sound] = i
	return b[i]

## Plays an effect that has no place in the world (your own footsteps, UI, jingles).
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0, bus := "Effects") -> void:
	var s := _pick(sound)
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()

## Plays an effect at a point in the world.
func play_at(sound: String, at: Vector3, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not is_inside_tree() or get_viewport().get_camera_3d() == null:
		play(sound, volume_db, pitch_jitter)
		return
	var s := _pick(sound)
	if s == null:
		return
	var best: AudioStreamPlayer3D = _pool3d[0]
	for p in _pool3d:
		if not p.playing:
			best = p
			break
		if p.get_playback_position() > best.get_playback_position():
			best = p
	best.stream = s
	best.volume_db = volume_db
	best.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	best.global_position = at
	best.play()

func _free_player() -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = _pool[0]
	for p in _pool:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest

func _loop_stream(rel: String) -> AudioStream:
	var path := ROOT + rel
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true
	return s

## A looping sound that runs while something keeps asking for it (jetpack, engines).
## Call every frame with the wanted volume (0..1); it fades out when calls stop.
func hold_loop(sound: String, volume := 1.0, pitch := 1.0) -> void:
	if not _loops.has(sound):
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		p.stream = _loop_stream("sfx/loop/%s.ogg" % sound)
		p.volume_db = -80.0
		add_child(p)
		_loops[sound] = p
	_loop_want[sound] = [clampf(volume, 0.0, 1.0), pitch, _now()]

func _update_loops(delta: float) -> void:
	for id in _loops:
		var p: AudioStreamPlayer = _loops[id]
		var w: Array = _loop_want.get(id, [0.0, 1.0, 0.0])
		if _now() - float(w[2]) > 0.15:
			w = [0.0, w[1], 0.0]
		var cur := db_to_linear(p.volume_db) if p.playing else 0.0
		var v := move_toward(cur, w[0], delta * 3.0)
		if v <= 0.001:
			if p.playing:
				p.stop()
			p.volume_db = -80.0
		else:
			if not p.playing and p.stream != null:
				p.play()
			p.volume_db = linear_to_db(v)
			p.pitch_scale = lerpf(p.pitch_scale, w[1], clampf(delta * 4.0, 0.0, 1.0))

# --- Game sounds ---------------------------------------------------------------------

## The sound bank for hitting something of this material (Durability materials).
static func hit_bank(material: String) -> String:
	match material:
		"wood":
			return "hit/wood"
		"stone", "ore":
			return "hit/stone"
		"metal":
			return "hit/metal"
		"crystal":
			return "hit/crystal"
		"fungus":
			return "hit/soft"
	return "hit/stone"

## A fight is on: battle music comes in and stays a while after the last blow.
func combat() -> void:
	_combat_t = _now()

func in_combat() -> bool:
	return _now() - _combat_t < COMBAT_HOLD

func _on_money(m: int) -> void:
	if world != null:
		play("item/coins", -8.0)

var _item_t := 0.0
func _on_item(_type: String, _qty: int) -> void:
	if world == null or _now() - _item_t < 0.15:
		return
	_item_t = _now()
	play("item/pickup", -12.0, 0.1)

func _on_health(h: float) -> void:
	if _last_health >= 0.0 and h < _last_health - 0.5 and world != null and Game.health > 0.0:
		play("hit/heavy", -6.0)
		combat()
	_last_health = h

# --- UI ------------------------------------------------------------------------------

## Every button, tab bar and slider in the game clicks, without each screen wiring it.
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		if b.toggle_mode or b is CheckBox or b is CheckButton:
			b.toggled.connect(func(_on): if _by_user(): ui("ui/toggle"))
		elif b is OptionButton:
			b.pressed.connect(func(): ui("ui/click"))
			(b as OptionButton).item_selected.connect(func(_i): ui("ui/tick"))
		else:
			b.pressed.connect(func(): ui("ui/click"))
		b.mouse_entered.connect(_hover.bind(b))
	elif n is TabBar:
		(n as TabBar).tab_changed.connect(func(_t): if _by_user(): ui("ui/tab"))
	elif n is Slider:
		(n as Slider).value_changed.connect(func(_v): _tick())

func _hover(b: BaseButton) -> void:
	if b.disabled or _now() - _hover_t < 0.06:
		return
	_hover_t = _now()
	ui("ui/hover", -14.0)

var _tick_t := 0.0
func _tick() -> void:
	if not _by_user() or _now() - _tick_t < 0.07:
		return
	_tick_t = _now()
	ui("ui/tick", -10.0)

var _input_t := -10.0

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseMotion) \
			and (event.is_pressed() or (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))):
		_input_t = _now()

## Changes the code makes itself (settings screens syncing their controls) stay quiet.
func _by_user() -> bool:
	return _now() - _input_t < 0.4

## A UI sound (never muffled by water or walls).
func ui(sound: String, volume_db := -6.0) -> void:
	play(sound, volume_db, 0.03, 1.0, "Master")

# --- Ambience and music --------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	_update_loops(delta)
	_env_t -= delta
	if _env_t <= 0.0:
		_env_t = 0.4
		env = _sample_env()
		_set_targets(env)
	var muffle_a := 20000.0
	var muffle_f := 20000.0
	if env.get("underwater", false):
		muffle_a = 500.0
		muffle_f = 700.0
	elif env.get("indoors", false):
		muffle_a = 2200.0
	_muffle_amb.cutoff_hz = lerpf(_muffle_amb.cutoff_hz, muffle_a, clampf(delta * 5.0, 0.0, 1.0))
	_muffle_fx.cutoff_hz = lerpf(_muffle_fx.cutoff_hz, muffle_f, clampf(delta * 5.0, 0.0, 1.0))
	for id in _layers:
		var lp: AudioStreamPlayer = _layers[id]
		var want: float = _layer_target[id] * float(LAYERS[id][1])
		var cur := db_to_linear(lp.volume_db) if lp.playing else 0.0
		var v := move_toward(cur, want, delta * 0.25)
		if v <= 0.002:
			if lp.playing:
				lp.stop()
			lp.volume_db = -80.0
		else:
			if not lp.playing and lp.stream != null:
				# Start each bed somewhere new, so two visits never sound the same.
				lp.play(randf() * lp.stream.get_length())
			lp.volume_db = linear_to_db(v)
	_update_music(delta)

## Where the player is, as far as sound cares.
func _sample_env() -> Dictionary:
	var e := {"where": "menu"}
	var scene := get_tree().current_scene
	if world == null or not is_instance_valid(world):
		world = null
		if scene != null and scene.get_script() != null and String(scene.get_script().resource_path).contains("orbit"):
			e["where"] = "space"
		return e
	var pl: Node3D = world.get("player")
	var atm = world.get("atmosphere")
	var streamer = world.get("streamer")
	if pl == null or atm == null or streamer == null:
		return e
	e["where"] = "world"
	var p := pl.global_position
	var t := fposmod(Game.day, 1.0)
	e["daylight"] = smoothstep(-0.12, 0.25, sin((t - 0.25) * TAU))
	var w: PackedFloat32Array = atm.current_weights()
	e["medieval"] = w[0]
	e["fantasy"] = w[1] if w.size() > 1 else 0.0
	e["scifi"] = w[2] if w.size() > 2 else 0.0
	e["wind"] = float(atm.wind_strength)
	var wx: Weather = atm.get("weather")
	e["rain"] = wx.precip * (1.0 - wx.snow) if wx != null else 0.0
	e["hail"] = wx.hail if wx != null else 0.0
	e["underwater"] = bool(pl.get("underwater"))
	e["swimming"] = bool(pl.get("swimming"))
	var era := WorldField.dominant(w)
	var field: WorldField = atm.field
	var bp := Biome.params(field.region_hash_at(p.x, p.z), era)
	e["trees"] = clampf(float(bp["tree_density"]) / 1.5, 0.0, 1.0)
	e["lush"] = float(bp["lush"])
	var ck := ChunkStreamer.chunk_of(p)
	var c: ChunkNode = streamer.get_chunk(ck)
	var ground := p.y
	var water := 0.0
	var sea := 0.0
	if c != null:
		var lx := p.x - ck.x * ChunkGenerator.SIZE
		var lz := p.z - ck.y * ChunkGenerator.SIZE
		ground = ChunkGenerator.height_at(c.data, lx, lz)
		e["cover"] = ChunkGenerator.cover_at(c.data, lx, lz)
		# Water around you: river samples and sea level in a ring.
		for i in 9:
			var q := Vector2(p.x, p.z) + (Vector2.ZERO if i == 0 else Vector2.from_angle(i * TAU / 8.0) * 16.0)
			var qk := Vector2i(floori(q.x / ChunkGenerator.SIZE), floori(q.y / ChunkGenerator.SIZE))
			var qc: ChunkNode = c if qk == ck else streamer.get_chunk(qk)
			if qc == null:
				continue
			var qx := q.x - qk.x * ChunkGenerator.SIZE
			var qz := q.y - qk.y * ChunkGenerator.SIZE
			if ChunkGenerator.by_river(qc.data, qx, qz):
				water += 1.0 / 9.0
			if ChunkGenerator.height_at(qc.data, qx, qz) < Water.LEVEL:
				sea += 1.0 / 9.0
	e["altitude"] = ground
	e["water"] = water
	e["sea"] = sea
	# Shelter: something solid over your head (a roof, a cave, a crypt).
	var roof := _roof_over(pl)
	e["indoors"] = not roof.is_empty()
	e["dungeon"] = false
	if not roof.is_empty():
		var tt: String = roof.get("t", "")
		e["dungeon"] = tt == "cave" or tt.contains("crypt") or tt.contains("bunker") or tt.contains("keep")
	e["riding"] = pl.get("vehicle") != null
	return e

func _roof_over(pl: Node3D) -> Dictionary:
	var space := pl.get_world_3d().direct_space_state
	var from := pl.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 14.0, 0), 1, [pl.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var col: Object = hit["collider"]
	if col.has_meta("dungeon"):
		return {"t": "cave"}
	if col.has_meta("obj") and col.has_meta("chunk"):
		var chunk: ChunkNode = col.get_meta("chunk")
		var o: Dictionary = chunk.get_object(col.get_meta("obj"))
		if not o.is_empty():
			return {"t": String(o["t"])}
	return {"t": ""}

func _set_targets(e: Dictionary) -> void:
	for id in _layer_target:
		_layer_target[id] = 0.0
	match e["where"]:
		"space":
			_layer_target["scifi"] = 0.5
			return
		"menu":
			return
	var day: float = e["daylight"]
	var inside: bool = e["indoors"]
	var open := 0.35 if inside else 1.0
	if e["dungeon"]:
		_layer_target["cave"] = 1.0
		_layer_target["wind"] = 0.1
		return
	var alt: float = e["altitude"]
	var high := smoothstep(Planets.snow_line - 25.0, Planets.snow_line + 5.0, alt)
	var bare := clampf(-float(e["lush"]), 0.0, 1.0) * (1.0 - float(e["trees"]))
	var wind: float = e["wind"]
	_layer_target["wind"] = open * clampf(0.35 + wind * 0.6 + bare * 0.3, 0.0, 1.0) * (1.0 - high * 0.7)
	_layer_target["wind_strong"] = open * clampf(high + wind * 0.4 * bare, 0.0, 1.0)
	var natural := clampf(1.0 - float(e["scifi"]), 0.0, 1.0) * (1.0 - high) * clampf(float(e.get("cover", 1.0)) * 1.3, 0.0, 1.0)
	var green := clampf(0.3 + float(e["trees"]) * 0.8 + float(e["lush"]) * 0.3, 0.0, 1.0)
	_layer_target["birds"] = open * natural * green * smoothstep(0.3, 0.8, day)
	_layer_target["crickets"] = open * natural * clampf(green + 0.3, 0.0, 1.0) * (1.0 - smoothstep(0.1, 0.5, day))
	_layer_target["water"] = open * clampf(float(e["water"]) * 2.5, 0.0, 1.0)
	_layer_target["surf"] = open * clampf(float(e["sea"]) * 2.2, 0.0, 1.0) * (1.0 - clampf(float(e["water"]) * 2.0, 0.0, 1.0) * 0.5)
	_layer_target["fantasy"] = open * smoothstep(0.3, 0.9, float(e["fantasy"])) * (0.5 + 0.5 * (1.0 - day))
	_layer_target["scifi"] = smoothstep(0.3, 0.9, float(e["scifi"])) * (1.0 if inside else 0.7)
	# Rain (Weather): all round you outdoors; indoors, drumming on the roof over you and
	# muffled through the walls. Birds and crickets go quiet in it.
	var rain := clampf(float(e.get("rain", 0.0)) * 1.2, 0.0, 1.0)
	_layer_target["rain"] = rain * (0.35 if inside else 1.0)
	_layer_target["rain_roof"] = rain if inside else 0.0
	# Hail rattles all round you, muffled a little indoors.
	_layer_target["hail"] = clampf(float(e.get("hail", 0.0)) * 1.3, 0.0, 1.0) * (0.6 if inside else 1.0)
	_layer_target["birds"] *= 1.0 - smoothstep(0.1, 0.4, rain)
	_layer_target["crickets"] *= 1.0 - smoothstep(0.1, 0.4, rain)
	if e["underwater"]:
		for id in _layer_target:
			_layer_target[id] *= 0.4
		_layer_target["water"] = 1.0

func _want_mood() -> String:
	var where: String = env.get("where", "menu")
	if where == "menu":
		return "menu"
	if where == "space":
		return "space"
	if in_combat():
		return "combat"
	if env.get("dungeon", false):
		return "dungeon"
	if float(env.get("scifi", 0.0)) > 0.6:
		return "scifi"
	return "day" if float(env.get("daylight", 1.0)) > 0.4 else "night"

func _update_music(delta: float) -> void:
	var mood := _want_mood()
	if mood != _mood:
		var was := _mood
		_mood = mood
		if mood == "combat" or was == "combat" or was == "menu" or mood == "menu" or mood == "dungeon":
			# Fights, menus and dungeons change the music at once; the rest waits for
			# the current track to end.
			_fade_out(1.5 if mood == "combat" else 3.0)
			_music_gap = 0.5 if mood in ["combat", "menu"] else randf_range(4.0, 12.0)
	if not _music.playing:
		_music_gap -= delta
		if _music_gap <= 0.0:
			_start_track(mood)

func _start_track(mood: String) -> void:
	var names: Array = MOODS.get(mood, [])
	if names.is_empty():
		return
	var s := _loop_stream("music/%s.ogg" % names[randi() % names.size()])
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		# Battle music loops for as long as the fight lasts; the rest plays once.
		s.loop = mood == "combat"
	if _music_fade:
		_music_fade.kill()
	_music.stream = s
	_music.volume_db = -30.0
	_music.play()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", -4.0 if mood != "dungeon" else -8.0, 3.0)

func _fade_out(sec: float) -> void:
	if not _music.playing:
		return
	if _music_fade:
		_music_fade.kill()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", -40.0, sec)
	_music_fade.tween_callback(_music.stop)

func _on_music_finished() -> void:
	_music_gap = randf_range(MUSIC_GAP.x, MUSIC_GAP.y) if _mood != "menu" else 20.0
