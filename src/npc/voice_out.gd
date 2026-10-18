class_name VoiceOut
extends Node
## Plays natural voices from the voice server (see Voice): fetches each line once (a
## small cache keeps repeated lines instant), plays it from the speaker's position, and
## keeps the conversation's lines in order.

const CACHE := 96
## Passers-by may only send this many lines a minute to the voice server.
const BARKS_PER_MIN := 8

var _cache := {} ## key -> AudioStream
var _order: Array = []
var _pending := {} ## key -> true while being fetched
var _queue: Array = [] ## conversation lines waiting: {key, node, dist}
var _now: Node ## the conversation player that is talking
var _gen := 0 ## bumped by every interruption; stale fetches are dropped
var _barks: Array = []
var _live := 0 ## voices playing right now, passers-by included (open mic pauses for them)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _key(rec: Dictionary, text: String) -> Array:
	var o := Voice.natural_for(rec)
	return [str(hash([o, text])), o]

## Whether any voice is playing (a conversation line or a passer-by).
func sounding() -> bool:
	return _live > 0 or busy()

func busy() -> bool:
	return (_now != null and is_instance_valid(_now) and _now.playing) or not _queue.is_empty()

## Gets a line's audio from the server into the cache (once).
func fetch(rec: Dictionary, text: String) -> void:
	var k := _key(rec, text)
	if _cache.has(k[0]) or _pending.has(k[0]):
		return
	_pending[k[0]] = true
	var r: Dictionary = await AI.speech(text, k[1])
	_pending.erase(k[0])
	if r["ok"]:
		_cache[k[0]] = r["audio"]
		_order.append(k[0])
		while _order.size() > CACHE:
			_cache.erase(_order.pop_front())

func say(rec: Dictionary, text: String, dist: float, interrupt: bool, node: Node3D, after: bool) -> void:
	var ko := _key(rec, text)
	var k: String = ko[0]
	var pitch := float(ko[1].get("pitch", 1.0))
	if not interrupt and not after:
		# A passer-by: only when nobody is talking, and within the budget.
		if busy():
			return
		var t := Time.get_ticks_msec() / 1000.0
		while not _barks.is_empty() and t - float(_barks[0]) > 60.0:
			_barks.pop_front()
		if not _cache.has(k):
			if _barks.size() >= BARKS_PER_MIN:
				return
			_barks.append(t)
		var g := _gen
		if not _cache.has(k):
			await fetch(rec, text)
		if g == _gen and _cache.has(k) and not busy():
			_play(_cache[k], node, dist, pitch)
		return
	if interrupt and not after:
		stop_all()
	var item := {"key": k, "node": node, "dist": dist, "pitch": pitch}
	_queue.append(item)
	var g2 := _gen
	if not _cache.has(k):
		await fetch(rec, text)
		if g2 != _gen:
			return
		if not _cache.has(k):
			_queue.erase(item) # the server failed; say nothing rather than stall the queue
	_pump()

func _pump() -> void:
	if _now != null and is_instance_valid(_now) and _now.playing:
		return
	while not _queue.is_empty():
		var it: Dictionary = _queue[0]
		if not _cache.has(it["key"]):
			return # still being fetched; it plays when it arrives
		_queue.pop_front()
		_now = _play(_cache[it["key"]], it["node"], it["dist"], it["pitch"])
		if _now:
			_now.finished.connect(_pump)
			return

## `pitch` plays the line back lighter (above 1) or deeper; the voice was made slower or
## faster to match, so the pace is right (see Voice.builtin_for).
func _play(stream: AudioStream, node: Node3D, dist: float, pitch := 1.0) -> Node:
	var vol := float(AI.get_value("voice_volume")) / 100.0
	if vol <= 0.0:
		return null
	var p: Node
	if node != null and is_instance_valid(node) and node.is_inside_tree():
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 4.0
		p3.max_distance = 32.0
		p3.volume_db = linear_to_db(vol)
		p3.position = Vector3(0, 1.6, 0)
		p3.pitch_scale = pitch
		node.add_child(p3)
		p3.stream = stream
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = linear_to_db(vol * clampf(1.0 - dist / 30.0, 0.15, 1.0))
		p2.pitch_scale = pitch
		add_child(p2)
		p2.stream = stream
		p2.play()
		p = p2
	p.finished.connect(p.queue_free)
	_live += 1
	p.tree_exiting.connect(func(): _live -= 1) # finished, cut off, or the speaker left
	return p

func stop_all() -> void:
	_gen += 1
	_queue.clear()
	if _now != null and is_instance_valid(_now):
		_now.stop()
		_now.queue_free()
	_now = null
