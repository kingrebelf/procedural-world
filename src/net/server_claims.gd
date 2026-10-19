class_name ServerClaims
extends RefCounted
## The server's land claims (LandClaims on each player's side): which player holds each
## tile, so no tile has two owners. A player asks for a tile and is told yes or no; their
## saves then keep the days they have paid up to, and a claim left unpaid past its grace
## (with a day's slack, for a save still on its way) is freed even while they are away.
## Everyone online is sent the whole list when it changes. Kept in claims.dat.

var path := ""
var list: Dictionary = {} ## key (LandClaims.tile_key) -> {pid, name, paid}

func _init(file := "") -> void:
	path = file
	if path != "":
		var d = WorldStore.read_var(path)
		if d is Dictionary and d.get("list") is Dictionary:
			list = d["list"]

func save() -> void:
	if path != "":
		WorldStore.write_var(path, {"list": list})

static func key_of(rec: Dictionary) -> String:
	return LandClaims.tile_key(int(rec.get("planet", 0)), Vector2i(int(rec.get("cx", 0)), int(rec.get("cz", 0))))

func count_of(pid: String) -> int:
	var n := 0
	for k in list:
		if list[k]["pid"] == pid:
			n += 1
	return n

## A player asks for a tile: "" when it is theirs now, else why not.
func ask(pid: String, nm: String, rec: Dictionary, limit: int) -> String:
	var k := key_of(rec)
	var o = list.get(k)
	if o is Dictionary and o["pid"] != pid:
		return "This land is claimed by %s" % o["name"]
	if o == null and count_of(pid) >= limit:
		return "You hold as much land as you may (%d tiles)" % limit
	list[k] = {"pid": pid, "name": nm, "paid": int(rec.get("paid", 0))}
	save()
	return ""

## A player gives a tile up (or it lapsed on their side).
func drop(pid: String, rec: Dictionary) -> bool:
	var k := key_of(rec)
	if list.has(k) and list[k]["pid"] == pid:
		list.erase(k)
		save()
		return true
	return false

## A player's save: the days paid on the claims the server gave them, and any claim of
## theirs it no longer has (lapsed while they were away) taken back if still free. (What
## they gave up comes as a drop: a save sent while a claim is being asked for lacks it.)
## Returns whether the list changed.
func sync_player(pid: String, nm: String, claims) -> bool:
	if not (claims is Array):
		return false
	var changed := false
	var dirty := false
	for rec in claims:
		if not (rec is Dictionary):
			continue
		var k := key_of(rec)
		var o = list.get(k)
		if o == null:
			list[k] = {"pid": pid, "name": nm, "paid": int(rec.get("paid", 0))}
			changed = true
		elif o["pid"] == pid:
			dirty = dirty or int(o["paid"]) != int(rec.get("paid", o["paid"])) or o["name"] != nm
			o["paid"] = int(rec.get("paid", o["paid"]))
			o["name"] = nm
	if changed or dirty:
		save()
	return changed

## Frees claims unpaid for more than LandClaims.GRACE days and one more. Returns whether any were.
func sweep(day: float) -> bool:
	var now := LandClaims.today(day)
	var freed := false
	for k in list.keys():
		if now - int(list[k]["paid"]) > LandClaims.GRACE + 1:
			list.erase(k)
			freed = true
	if freed:
		save()
	return freed

## What every client is sent: [[key, pid, name], ...].
func view() -> Array:
	var out: Array = []
	for k in list:
		out.append([k, list[k]["pid"], list[k]["name"]])
	return out
