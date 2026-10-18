class_name FireCrew
## Townsfolk and a fire in their town (FireSystem): the able-bodied form a bucket line,
## running between the well and the fire, filling a bucket and throwing it on; children and
## the timid get clear of it, shouting the alarm. Asked by NPCManager._decide each time a
## person decides; true when the fire took over what they do.

const NOTICE := 60.0 ## how far from a fire people notice it (metres, ground distance)
const CREW := 6 ## people on one fire's bucket line at once
const THROW_AT := 2.4 ## how near the flames they go to throw
const BUCKET := 0.32 ## one villager's bucket, as FireSystem.douse amount (a player's is 0.55)

static func decide(m: NPCManager, n: NPC, e: Dictionary) -> bool:
	var fs := FireSystem.current
	var rec := n.rec
	var f: Dictionary = fs.fire_near(n.global_position, NOTICE) if fs != null else {}
	if f.is_empty():
		if rec.has("_fire"):
			_stand_down(n)
		return false
	var box: AABB = f["box"]
	var c := box.get_center()
	var fkey := FireSystem.key_of(f["k"], int(f["i"]))
	var p2 := Vector2(n.global_position.x, n.global_position.z)
	var c2 := Vector2(c.x, c.z)
	var away := (p2 - c2).normalized() if p2.distance_to(c2) > 0.1 else Vector2(1, 0)
	var crew: Dictionary = e.get("fire_crew", {})
	e["fire_crew"] = crew
	var on := crew.get(fkey, []) as Array
	on = on.filter(func(id): return m._by_id.has(id) and is_instance_valid(m._by_id[id]) and m._by_id[id].rec.get("_fire", "") == fkey)
	crew[fkey] = on
	var dist: float = m.player.global_position.distance_to(n.global_position) if m.player != null else 99.0
	var able: bool = not rec.get("child", false) and (float(rec["traits"].get("brave", 0.5)) > 0.3 or NPCGen.GUARD_JOBS.has(rec["job"]))
	if not on.has(rec["id"]) and (not able or on.size() >= CREW):
		# Out of the way, and the word goes round.
		var first := not rec.has("_fire")
		rec["_fire"] = "away"
		n.stop_perform()
		n.action = "flee"
		n.target_player = false
		n.target = c2 + away * (maxf(box.size.x, box.size.z) * 0.5 + 22.0)
		if first:
			m._bark(n, ["Fire! Fire!", "Fire! Get out!", "The %s's alight!" % _what(f), "Help! Fire!"][randi() % 4], dist)
		return true
	if not on.has(rec["id"]):
		on.append(rec["id"])
		rec["_fire"] = fkey
		rec["_fire_leg"] = "fetch"
		if rec.has("held"):
			rec["_fire_held"] = rec["held"]
		rec["held"] = {"type": "bucket"}
		n.refresh_gear()
		n.stop_perform()
		m._bark(n, ["Water! Get water!", "Buckets, quick!", "Form a line, to the well!", "Fire! Fetch the buckets!"][randi() % 4], dist)
	n.action = "fight_fire"
	n.target_player = false
	n.face_to = Vector2.INF
	if n.is_performing():
		return true
	var leg := String(rec.get("_fire_leg", "fetch"))
	if leg == "fetch":
		var well := _well(e, c2)
		n.target = well
		if p2.distance_to(well) < 1.8:
			n.act("pick_up")
			rec["_fire_leg"] = "carry"
	else:
		# To the edge of the flames on their side, a step back from the heat.
		var edge := c2 + away * (maxf(box.size.x, box.size.z) * 0.5 + THROW_AT)
		n.target = edge
		n.face_to = c2
		if p2.distance_to(edge) < 1.6:
			n.rotation.y = atan2(c2.x - p2.x, c2.y - p2.y)
			n.act("throw")
			var hit := Vector3(clampf(n.global_position.x, box.position.x, box.end.x), clampf(n.global_position.y + 1.2, box.position.y, box.end.y), clampf(n.global_position.z, box.position.z, box.end.z))
			fs.douse(hit, 1.6, BUCKET)
			Audio.play_at("water/splash", hit, -6.0)
			Splashes.splash(hit, 0.35)
			rec["_fire_leg"] = "fetch"
	return true

## Where the water comes from: the town's well nearest the fire, else the trough in the square.
static func _well(e: Dictionary, near: Vector2) -> Vector2:
	var places: Dictionary = e.get("places", {})
	var best: Vector2 = places.get("center", e["data"]["center"]) + Vector2(2.0, 2.0)
	var bd := INF
	for w in places.get("wells", []):
		var d := (w as Vector2).distance_to(near)
		if d < bd:
			bd = d
			best = w
	return best

## The fire is out (or gone): back to what they were doing, the bucket put away.
static func _stand_down(n: NPC) -> void:
	var rec := n.rec
	if String(rec.get("_fire", "")) != "away":
		if rec.has("_fire_held"):
			rec["held"] = rec["_fire_held"]
		else:
			rec.erase("held")
		rec.erase("_fire_held")
		n.refresh_gear()
	rec.erase("_fire")
	rec.erase("_fire_leg")

static func _what(f: Dictionary) -> String:
	var node := FireSystem.current.streamer.get_chunk(f["k"])
	return ObjectLibrary.label_of(node.get_object(f["i"])).to_lower() if node != null else "house"
