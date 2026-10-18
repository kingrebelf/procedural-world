class_name Microphone
extends Node
## Push-to-talk capture: records the default microphone while held, then hands back a
## small 16 kHz mono WAV for speech-to-text (AI.transcribe). Open mic (listen): keeps the
## microphone on and emits `heard` with each phrase you say (SpeechGate finds where you
## start and stop), pausing while the game's own voices speak so it never hears them.
## Needs audio/driver/enable_input in project.godot; on macOS the system asks once for
## permission to use the microphone.

const BUS := "VoiceIn"
const RATE := 16000
const MAX_SECONDS := 30.0

var _player: AudioStreamPlayer
var _rec: AudioEffectRecord
var _meter: AudioEffectSpectrumAnalyzerInstance
var _cap: AudioEffectCapture
var _gate := SpeechGate.new()
var _hush_t := 0.0
var _t := 0.0
var recording := false
## Open mic: listening for phrases (see listen()).
var listening := false
## Whether open mic should pause right now (the dialogue sets it to Voice.sounding, so it
## pauses while the game's voices speak).
var paused_by: Callable = func() -> bool: return false

## A phrase heard on the open mic: 16 kHz WAV bytes and its loudest sample (0..1).
signal heard(wav: PackedByteArray, peak: float)
## Loudest sample of the last recording, 0..1 (near 0 means the microphone sent silence).
var last_peak := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _setup() -> bool:
	if _rec:
		return true
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return false
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.add_bus_effect(bus, AudioEffectRecord.new())
		AudioServer.add_bus_effect(bus, AudioEffectSpectrumAnalyzer.new())
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(bus, cap)
		AudioServer.set_bus_mute(bus, true) # never play your own voice back
	_rec = AudioServer.get_bus_effect(bus, 0) as AudioEffectRecord
	if AudioServer.get_bus_effect_count(bus) > 1:
		_meter = AudioServer.get_bus_effect_instance(bus, 1) as AudioEffectSpectrumAnalyzerInstance
	if AudioServer.get_bus_effect_count(bus) > 2:
		_cap = AudioServer.get_bus_effect(bus, 2) as AudioEffectCapture
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	return _rec != null

func start() -> bool:
	if recording or not _setup():
		return false
	if not _player.playing:
		_player.play()
	_rec.set_recording_active(true)
	recording = true
	_t = 0.0
	return true

## Turns the open mic on or off. False when there is no microphone input.
func listen(on: bool) -> bool:
	if not on:
		listening = false
		_gate.reset()
		if not recording and _player:
			_player.stop()
		return true
	if not _setup() or _cap == null:
		return false
	if not _player.playing:
		_player.play()
	_cap.clear_buffer()
	_gate.reset()
	listening = true
	return true

func _process(delta: float) -> void:
	if recording:
		_t += delta
		if _t > MAX_SECONDS:
			stop()
	if not listening or _cap == null:
		return
	var n := _cap.get_frames_available()
	if n <= 0:
		return
	var frames := _cap.get_buffer(n)
	# Holding the talk key, or the game is talking: don't listen (and a little after, for
	# the echo of the room).
	if recording or paused_by.call():
		_hush_t = 0.4
		_gate.reset()
		return
	if _hush_t > 0.0:
		_hush_t -= delta
		return
	for said in _gate.feed_stereo(frames, AudioServer.get_mix_rate()):
		heard.emit(SpeechGate.to_wav(said), SpeechGate.peak(said))

## How loud the microphone is right now, 0..1, for a level meter.
func level() -> float:
	if not (recording or listening) or _meter == null:
		return 0.0
	var m := _meter.get_magnitude_for_frequency_range(80.0, 4000.0)
	return clampf((linear_to_db(maxf(m.x, m.y) + 1e-7) + 70.0) / 55.0, 0.0, 1.0)

## The input device in use (for messages when nothing is heard).
static func device() -> String:
	return AudioServer.input_device

## Stops and returns the recording as WAV bytes (empty if too short or nothing heard).
func stop() -> PackedByteArray:
	if not recording:
		return PackedByteArray()
	recording = false
	_rec.set_recording_active(false)
	var w := _rec.get_recording()
	if not listening:
		_player.stop()
	if w == null or _t < 0.3:
		last_peak = 0.0
		return PackedByteArray()
	last_peak = peak(w.data)
	return to_wav16k(w)

## Loudest 16-bit sample, 0..1.
static func peak(data: PackedByteArray) -> float:
	var top := 0
	for i in range(0, data.size() - 1, 8):
		top = maxi(top, absi(data.decode_s16(i)))
	return float(top) / 32768.0

## Downmixes a 16-bit recording to mono and resamples it to 16 kHz.
static func to_wav16k(w: AudioStreamWAV) -> PackedByteArray:
	var src := w.data
	var ch := 2 if w.stereo else 1
	var frames := src.size() / (2 * ch)
	var step := float(w.mix_rate) / RATE
	var n := int(frames / step)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var f := int(i * step) * 2 * ch
		var s := src.decode_s16(f)
		if ch == 2:
			s = (s + src.decode_s16(f + 2)) / 2
		pcm.encode_s16(i * 2, s)
	return wav_bytes(pcm, RATE)

static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952) # "RIFF"
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157) # "WAVE"
	h.encode_u32(12, 0x20746d66) # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164) # "data"
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h
