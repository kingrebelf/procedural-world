class_name SpeechGate
extends RefCounted
## Finds where someone starts and stops talking in a stream of microphone audio (open
## mic): it learns how loud the room is, opens when the sound rises well above that, and
## closes after a short pause. Each finished phrase comes back as 16 kHz mono samples
## for speech to text. Pure (no audio devices), so it is unit-tested.

const RATE := 16000
const BLOCK := 320 ## 20 ms
const START_BLOCKS := 4 ## 80 ms of voice opens the gate
const END_SECONDS := 0.8 ## this much quiet ends a phrase
const PRE_SECONDS := 0.3 ## kept from before the gate opened, so first sounds aren't cut
const MIN_VOICED := 0.35 ## shorter phrases (a cough, a click) are dropped
const MAX_SECONDS := 15.0

var noise := 0.004 ## the room's loudness (RMS), learnt while nobody talks
var active := false
var _pre := PackedFloat32Array()
var _seg := PackedFloat32Array()
var _block := PackedFloat32Array()
var _loud := 0
var _quiet := 0.0
var _voiced := 0.0
var _step := 0.0 ## resampling position
var _acc := 0.0
var _n := 0

## Forgets anything half-heard (the game talked, or the mic was paused).
func reset() -> void:
	active = false
	_pre.clear()
	_seg.clear()
	_block.clear()
	_loud = 0
	_quiet = 0.0
	_voiced = 0.0

## Feeds stereo frames at `rate` Hz; returns the phrases that finished (each a
## PackedFloat32Array at 16 kHz).
func feed_stereo(frames: PackedVector2Array, rate: float) -> Array:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	return feed(mono, rate)

## Feeds mono samples at `rate` Hz (averaged down to 16 kHz).
func feed(mono: PackedFloat32Array, rate: float) -> Array:
	var out: Array = []
	var ratio := rate / RATE
	for s in mono:
		_acc += s
		_n += 1
		_step += 1.0
		if _step < ratio:
			continue
		_step -= ratio
		_block.append(_acc / _n)
		_acc = 0.0
		_n = 0
		if _block.size() >= BLOCK:
			var done := _push(_block)
			_block = PackedFloat32Array()
			if not done.is_empty():
				out.append(done)
	return out

static func rms(b: PackedFloat32Array) -> float:
	var sum := 0.0
	for s in b:
		sum += s * s
	return sqrt(sum / maxf(b.size(), 1.0))

func _push(b: PackedFloat32Array) -> PackedFloat32Array:
	var r := rms(b)
	var dt := float(b.size()) / RATE
	var on := maxf(noise * 3.0, 0.01)
	var off := maxf(noise * 2.0, 0.006)
	if not active:
		# The room: quickly down to quiet stretches, slowly up to steady hums.
		noise = lerpf(noise, r, 0.05 if r < noise else 0.004)
		noise = clampf(noise, 0.0005, 0.05)
		_pre.append_array(b)
		var keep := int(PRE_SECONDS * RATE)
		if _pre.size() > keep:
			_pre = _pre.slice(_pre.size() - keep)
		_loud = _loud + 1 if r > on else 0
		if _loud >= START_BLOCKS:
			active = true
			_seg = _pre.duplicate()
			_voiced = _loud * dt
			_quiet = 0.0
		return PackedFloat32Array()
	_seg.append_array(b)
	if r > off:
		_voiced += dt
		_quiet = 0.0
	else:
		_quiet += dt
	if _quiet < END_SECONDS and float(_seg.size()) / RATE < MAX_SECONDS:
		return PackedFloat32Array()
	var said := _seg
	_seg = PackedFloat32Array() # (said shares the old buffer, so don't clear it)
	var voiced := _voiced
	reset()
	return said if voiced >= MIN_VOICED else PackedFloat32Array()

## A phrase as WAV bytes for speech to text.
static func to_wav(samples: PackedFloat32Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return Microphone.wav_bytes(pcm, RATE)

## The loudest sample of a phrase, 0..1.
static func peak(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for s in samples:
		top = maxf(top, absf(s))
	return top
