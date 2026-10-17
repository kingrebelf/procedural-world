class_name Microphone
extends Node
## Push-to-talk capture: records the default microphone while held, then hands back a
## small 16 kHz mono WAV for speech-to-text (AI.transcribe). Needs
## audio/driver/enable_input in project.godot; on macOS the system asks once for
## permission to use the microphone.

const BUS := "VoiceIn"
const RATE := 16000
const MAX_SECONDS := 30.0

var _player: AudioStreamPlayer
var _rec: AudioEffectRecord
var _t := 0.0
var recording := false

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
		AudioServer.set_bus_mute(bus, true) # never play your own voice back
	_rec = AudioServer.get_bus_effect(bus, 0) as AudioEffectRecord
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	return _rec != null

func start() -> bool:
	if recording or not _setup():
		return false
	_player.play()
	_rec.set_recording_active(true)
	recording = true
	_t = 0.0
	return true

func _process(delta: float) -> void:
	if recording:
		_t += delta
		if _t > MAX_SECONDS:
			stop()

## Stops and returns the recording as WAV bytes (empty if too short or nothing heard).
func stop() -> PackedByteArray:
	if not recording:
		return PackedByteArray()
	recording = false
	_rec.set_recording_active(false)
	var w := _rec.get_recording()
	_player.stop()
	if w == null or _t < 0.3:
		return PackedByteArray()
	return to_wav16k(w)

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
