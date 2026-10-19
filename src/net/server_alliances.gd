class_name ServerAlliances
extends RefCounted
## The server's alliances (stage 4, plans/multiplayer.md). Allies can't hurt each other,
## open each other's locked doors and see each other on the map, and have their own chat.
## Anyone can found one; its members invite others (up to the server's max_alliance);
## the leader can remove members, and leadership passes on when the leader leaves.
## Kept in alliances.dat beside the world; invitations last until the server restarts.

var host: Object ## ServerHost (or tests/fake_host.gd): online, option(), peer_of(), tell_alliance(), ally_note(), ally_chat()
var path := ""
var list: Dictionary = {} ## id -> {name, leader: pid, members: {pid: name}}
var _of: Dictionary = {} ## pid -> id
var invites: Dictionary = {} ## pid -> {id: inviter's name}
var homes: Dictionary = {} ## pid -> [[planet, x, z], ...]: houses they bought, shared with allies
var _next := 1
## pid -> {planet: {Vector2i: true}}: the tiles each player has stood in, kept whether or
## not they are in an alliance (joining one later shares what they found before).
var explored: Dictionary = {}
var _explored_dirty := false
const EXPLORED_BATCH := 256 ## most tiles one message may add

func _init(h: Object, file := "") -> void:
	host = h
	path = file
	if path != "":
		var d = WorldStore.read_var(path)
		if d is Dictionary:
			list = d.get("list", {})
			homes = d.get("homes", {})
			_next = int(d.get("next", 1))
	for id in list:
		for pid in list[id]["members"]:
			_of[pid] = id
	if path != "":
		var e = WorldStore.read_var(_explored_path(), true)
		if e is Dictionary:
			explored = e

func save() -> void:
	if path != "":
		WorldStore.write_var(path, {"list": list, "next": _next, "homes": homes})

func of(pid: String) -> String:
	return String(_of.get(pid, ""))

func allied(a: String, b: String) -> bool:
	return a != b and _of.has(a) and _of.get(a) == _of.get(b) and bool(host.option("alliances"))

## What one player is told: [their alliance ({} if none), [{id, name, from}, ...]].
func view(pid: String) -> Array:
	var mine := {}
	var id := of(pid)
	if id != "":
		var a: Dictionary = list[id]
		var hs := {}
		for q in a["members"]:
			if q != pid and not (homes.get(q, []) as Array).is_empty():
				hs[q] = homes[q]
		mine = {"id": id, "name": a["name"], "leader": a["leader"], "members": a["members"].duplicate(), "homes": hs}
	var inv: Array = []
	for i in invites.get(pid, {}):
		if list.has(i):
			inv.append({"id": i, "name": list[i]["name"], "from": invites[pid][i]})
	return [mine, inv]

static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and not ch in "[]<>\\":
			out += ch
	return out.substr(0, 24).strip_edges()

## A player's alliance command. Returns "" when done, else why not (also told to them).
func command(pid: String, nm: String, cmd: String, arg: String) -> String:
	var why := _command(pid, nm, cmd, arg)
	if why != "":
		host.ally_note(pid, why)
	return why

func _command(pid: String, nm: String, cmd: String, arg: String) -> String:
	if not bool(host.option("alliances")):
		return "Alliances are turned off on this server."
	var mine := of(pid)
	var cap := maxi(2, int(host.option("max_alliance")))
	match cmd:
		"create":
			if mine != "":
				return "Leave %s first." % list[mine]["name"]
			var an := clean_name(arg)
			if an.length() < 2:
				return "Give your alliance a name of at least 2 letters."
			for id in list:
				if String(list[id]["name"]).to_lower() == an.to_lower():
					return "There is already an alliance called %s." % an
			var id := "a%d" % _next
			_next += 1
			list[id] = {"name": an, "leader": pid, "members": {pid: nm}}
			_of[pid] = id
			invites.erase(pid)
			save()
			_tell([pid])
			host.ally_note(pid, "You founded %s. Invite players from the Players screen." % an)
		"invite":
			if mine == "":
				return "Found or join an alliance first."
			if arg == pid or not host.peer_of(arg):
				return "That player isn't here."
			if of(arg) == mine:
				return "They are already in %s." % list[mine]["name"]
			if of(arg) != "":
				return "They are already in another alliance."
			if list[mine]["members"].size() >= cap:
				return "%s is full (%d members on this server)." % [list[mine]["name"], cap]
			var inv: Dictionary = invites.get(arg, {})
			inv[mine] = nm
			invites[arg] = inv
			_tell([arg])
			host.ally_note(arg, "%s invites you to join %s. Accept on the Players screen." % [nm, list[mine]["name"]])
			host.ally_note(pid, "Invited them to %s." % list[mine]["name"])
		"accept":
			if not invites.get(pid, {}).has(arg) or not list.has(arg):
				return "That invitation is gone."
			if mine != "":
				return "Leave %s first." % list[mine]["name"]
			var a: Dictionary = list[arg]
			if a["members"].size() >= cap:
				return "%s is full." % a["name"]
			a["members"][pid] = nm
			_of[pid] = arg
			invites.erase(pid)
			save()
			_tell(a["members"].keys())
			_say_to(arg, "%s joined %s." % [nm, a["name"]])
		"decline":
			var inv: Dictionary = invites.get(pid, {})
			inv.erase(arg)
			if inv.is_empty():
				invites.erase(pid)
			_tell([pid])
		"leave":
			if mine == "":
				return "You aren't in an alliance."
			var a: Dictionary = list[mine]
			_remove(pid, mine)
			_say_to(mine, "%s left %s." % [nm, a["name"]])
			host.ally_note(pid, "You left %s." % a["name"])
		"kick":
			if mine == "" or list[mine]["leader"] != pid:
				return "Only the alliance's leader can remove members."
			if arg == pid or of(arg) != mine:
				return "They aren't in your alliance."
			var a: Dictionary = list[mine]
			var who := String(a["members"][arg])
			_remove(arg, mine)
			_say_to(mine, "%s was removed from %s." % [who, a["name"]])
			host.ally_note(arg, "You were removed from %s." % a["name"])
		"lead":
			if mine == "" or list[mine]["leader"] != pid:
				return "Only the alliance's leader can hand over leadership."
			if arg == pid or of(arg) != mine:
				return "They aren't in your alliance."
			list[mine]["leader"] = arg
			save()
			_tell(list[mine]["members"].keys())
			_say_to(mine, "%s now leads %s." % [list[mine]["members"][arg], list[mine]["name"]])
		"chat":
			if mine == "":
				return "You aren't in an alliance."
			var text := arg.strip_edges().substr(0, 240)
			if text != "":
				for q in list[mine]["members"]:
					host.ally_chat(q, nm, text)
		_:
			return "Unknown alliance command."
	return ""

## Takes `pid` out of alliance `id`: the alliance ends with its last member, and its
## leadership passes to the member who joined next.
func _remove(pid: String, id: String) -> void:
	var a: Dictionary = list[id]
	a["members"].erase(pid)
	_of.erase(pid)
	if a["members"].is_empty():
		list.erase(id)
		for q in invites.keys():
			invites[q].erase(id)
			if invites[q].is_empty():
				invites.erase(q)
	elif a["leader"] == pid:
		a["leader"] = a["members"].keys()[0]
	save()
	_tell([pid] + (a["members"].keys() as Array))

## The houses `pid` owns (from their save): their allies may use what is inside.
func set_homes(pid: String, list_: Array) -> void:
	if homes.get(pid, []) == list_:
		return
	if list_.is_empty():
		homes.erase(pid)
	else:
		homes[pid] = list_
	save()
	var id := of(pid)
	if id != "":
		_tell((list[id]["members"].keys() as Array).filter(func(q): return q != pid))

## A member's name changed (they joined under a new one).
func rename(pid: String, nm: String) -> void:
	var id := of(pid)
	if id != "" and list[id]["members"].get(pid) != nm:
		list[id]["members"][pid] = nm
		save()
		_tell(list[id]["members"].keys())

## Where each alliance's members are, for their map: pid -> [[pid, planet, pos], ...] of
## their allies online.
func positions() -> Dictionary:
	var out := {}
	if not bool(host.option("alliances")):
		return out
	for id in list:
		var here: Array = []
		for pid in list[id]["members"]:
			var q: int = host.peer_of(pid)
			if q != 0:
				var o: Dictionary = host.online[q]
				here.append([pid, int(o["planet"]), o["pos"]])
		if here.size() < 2:
			continue
		for e in here:
			out[e[0]] = here.filter(func(f): return f[0] != e[0])
	return out

func _tell(pids: Array) -> void:
	for pid in pids:
		host.tell_alliance(pid, view(pid))

func _say_to(id: String, text: String) -> void:
	if list.has(id):
		for q in list[id]["members"]:
			host.ally_note(q, text)

# --- Explored tiles ------------------------------------------------------------------

func _explored_path() -> String:
	return path.get_basename() + "_explored.dat"

## Saves the explored tiles if they changed (the host's autosave calls this).
func save_explored() -> void:
	if _explored_dirty and path != "":
		WorldStore.write_var(_explored_path(), explored, true)
	_explored_dirty = false

## A player stood in new tiles on `planet`: kept, and passed on to their allies online.
func explore(pid: String, planet: int, keys: Array) -> void:
	if planet < 0 or planet >= Planets.COUNT:
		return
	var mine: Dictionary = explored.get(pid, {})
	var tiles: Dictionary = mine.get(planet, {})
	var fresh: Array = []
	for k in keys.slice(0, EXPLORED_BATCH):
		if k is Vector2i and not tiles.has(k):
			tiles[k] = true
			fresh.append(k)
	if fresh.is_empty():
		return
	mine[planet] = tiles
	explored[pid] = mine
	_explored_dirty = true
	var id := of(pid)
	if id == "" or not bool(host.option("alliances")):
		return
	for q in list[id]["members"]:
		if q != pid:
			host.tell_explored(q, planet, fresh)

## Every tile `pid`'s allies have explored on `planet` (none outside an alliance).
func ally_map(pid: String, planet: int) -> Array:
	var id := of(pid)
	if id == "" or not bool(host.option("alliances")):
		return []
	var seen := {}
	for q in list[id]["members"]:
		if q != pid:
			for k in (explored.get(q, {}) as Dictionary).get(planet, {}):
				seen[k] = true
	return seen.keys()
