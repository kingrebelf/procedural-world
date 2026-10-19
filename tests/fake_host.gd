extends Node
## Stands in for ServerHost in tests/run_tests.gd: ServerSync reads `online` and tells
## players who holds what through tell_hold.

var online: Dictionary = {}
var told: Array = []

func tell_hold(q: int, kind: String, p: int, k: Vector2i, holder: int, count: int) -> void:
	told.append([q, kind, p, k, holder, count])

# For ServerAlliances: players by pid (peer = index + 1), options and what was said.
var opts: Dictionary = {"alliances": true, "max_alliance": 3}
var pids: Array = []
var views: Dictionary = {} ## pid -> the last view told
var notes: Array = [] ## [pid, text]
var chats: Array = [] ## [pid, from, text]
var explored_told: Array = [] ## [pid, planet, keys]

func option(k: String):
	return opts.get(k)

func peer_of(pid: String) -> int:
	return pids.find(pid) + 1

func tell_alliance(pid: String, v: Array) -> void:
	views[pid] = v

func ally_note(pid: String, text: String) -> void:
	notes.append([pid, text])

func ally_chat(pid: String, from: String, text: String) -> void:
	chats.append([pid, from, text])

func tell_explored(pid: String, p: int, keys: Array) -> void:
	explored_told.append([pid, p, keys])
