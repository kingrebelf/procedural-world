class_name NPCRoles
## What each person's job means hour by hour. Every trade has a routine: a farmer works
## a plot out past the houses, hauls the crop to the stall in the afternoon and eats at
## noon; guards walk rounds between the gates, the towers and the square (some keep the
## night watch and sleep by day); a hunter goes out into the wilds at dawn and comes back
## with meat; the priest prays at dawn and preaches in the square; the lamplighter does
## the rounds with a torch at dusk. Routines are data (ROUTINES, DUTIES), each person
## keeps theirs a little early or late by temperament, and the places come from the
## town's own layout (Places), so nothing new is saved: it is all rebuilt the same on
## every visit.
##
## The decision engine still has the last word: fear, anger, the player, a bounty, an
## instruction from a conversation or the model all win over the routine.

## Duties. where: the kind of place it is done at (see places()); anims: what the body
## does once there, cycled stop by stop; hop: seconds at each stop before the next;
## upper: what the arms do while walking there (carrying a load, a torch); perform: a
## full-body action (NPCMind.PERFORM) done on arrival; gesture: a gesture now and then
## at the stop; shift: done in the hours others sleep; label: what they are doing, in
## words (told to the language model, and the duty's name in the decision snapshot).
const DUTIES := {
	"till": {"where": "field", "anims": ["plant", "water", "harvest"], "hop": 40.0, "label": "working your plot in the fields",
		"lines": ["These rows won't weed themselves.", "Ground's hard this year.", "Rain'd be welcome.", "Mind the furrows."]},
	"harvest": {"where": "field", "anims": ["harvest", "harvest", "pickup"], "hop": 35.0, "label": "bringing in the harvest",
		"lines": ["Good crop, this.", "Back's aching already.", "Another basket full."]},
	"haul": {"where": "stall", "anims": ["interact"], "upper": "carry", "hop": 60.0, "label": "hauling your goods to the market stall",
		"lines": ["Make way, heavy load!", "Fresh from the fields.", "Mind your toes."]},
	"livestock": {"where": "yard", "anims": ["water", "pickup"], "hop": 30.0, "label": "seeing to the animals",
		"lines": ["Easy, girl, easy.", "Feeding time."]},
	"lunch": {"where": "square", "perform": "sit", "hop": 300.0, "label": "having your midday meal",
		"lines": ["Bread and cheese, best part of the day.", "Can't work on an empty belly."]},
	"smithy": {"where": "shopyard", "anims": ["fix", "fix", "interact"], "hop": 45.0, "prop": "forge", "label": "at the forge outside your shop, making the wares you sell",
		"lines": ["Come in when I'm done, I'll find you something.", "Hot iron waits for no one.", "Stand back from the sparks."]},
	"forge": {"where": "post", "anims": ["fix", "fix", "interact"], "hop": 45.0, "prop": "anvil", "label": "working at your anvil",
		"lines": ["Hot iron waits for no one.", "Stand back from the sparks.", "Good steel, this."]},
	"weave": {"where": "post", "anims": ["interact", "pickup"], "hop": 50.0, "prop": "crates", "label": "working at your craft outside your house",
		"lines": ["Fine thread, this.", "Almost done with this bolt."]},
	"mill": {"where": "field_stall", "anims": ["pickup", "interact"], "upper": "carry", "hop": 55.0, "label": "carrying sacks of grain between the fields and the market",
		"lines": ["Flour for the bakers.", "Heavy sacks today."]},
	"patrol": {"where": "rounds", "anims": ["sword_idle", "fold_arms", "lean"], "hop": 22.0, "gesture": "look", "label": "walking your rounds of the town",
		"lines": ["All quiet.", "Keep out of trouble.", "Move along.", "Eyes open, stranger."]},
	"night_watch": {"where": "rounds", "anims": ["lantern", "fold_arms"], "upper": "lantern", "hop": 30.0, "shift": true, "label": "keeping the night watch",
		"lines": ["Late to be about.", "Quiet night. Keep it that way.", "Who goes there?"]},
	"gate": {"where": "gates", "anims": ["fold_arms", "sword_idle"], "hop": 120.0, "label": "standing watch at the road into town",
		"lines": ["State your business.", "Roads are safe enough by day.", "Keep to the road after dark."]},
	"hunt": {"where": "wilds", "anims": ["crouch", "idle", "crouch"], "hop": 45.0, "label": "out in the wilds, tracking game",
		"lines": ["Shh. You'll scare it off.", "Fresh tracks here.", "Deer came through at dawn."]},
	"bring_game": {"where": "stall", "anims": ["interact"], "upper": "carry", "hop": 60.0, "label": "bringing your kill back to sell",
		"lines": ["Venison tonight!", "Good hunt today."]},
	"pray": {"where": "holy", "anims": ["fold_arms"], "hop": 90.0, "gesture": "pray", "label": "at your morning prayers",
		"lines": ["Blessings on you.", "Peace be with you."]},
	"preach": {"where": "square", "anims": ["talk"], "hop": 70.0, "gesture": "point", "label": "preaching to whoever will listen in the square",
		"lines": ["Mend your ways while there's time!", "Charity, friends, charity!", "The gods see all that you do."]},
	"visit": {"where": "homes", "anims": ["interact", "talk"], "hop": 45.0, "label": "visiting folk at their doors",
		"lines": ["Just checking in on everyone.", "How's the family?"]},
	"serve": {"where": "tavern", "anims": ["interact", "talk"], "hop": 80.0, "label": "keeping the tavern",
		"lines": ["First drink's not free, mind.", "Pull up a stool."]},
	"supplies": {"where": "stall", "anims": ["interact"], "upper": "carry", "hop": 50.0, "label": "fetching supplies from the market",
		"lines": ["Need more barrels.", "Running low again."]},
	"gather": {"where": "outskirts", "anims": ["harvest", "pickup", "crouch"], "hop": 35.0, "label": "gathering herbs at the edge of town",
		"lines": ["Feverfew, if I'm not mistaken.", "Careful where you step."]},
	"brew": {"where": "post", "anims": ["interact", "fix"], "hop": 60.0, "prop": "cauldron", "label": "brewing remedies",
		"lines": ["Smells foul, works wonders.", "Not ready yet."]},
	"play": {"where": "square", "perform": "dance", "hop": 120.0, "label": "playing for coins in the square",
		"lines": ["A song for a Mark!", "Requests welcome!", "Clap along, then!"]},
	"rehearse": {"where": "tavern", "anims": ["talk", "dance"], "hop": 90.0, "label": "rehearsing at the tavern",
		"lines": ["La la... no, too high.", "New verse, listen."]},
	"lamps": {"where": "lamps", "anims": ["torch"], "upper": "torch", "hop": 18.0, "label": "lighting the lamps along the streets",
		"lines": ["Light's coming.", "Can't have folk tripping in the dark."]},
	"douse": {"where": "lamps", "anims": ["interact"], "hop": 18.0, "label": "putting out last night's lamps",
		"lines": ["Morning already.", "Another night done."]},
	"bees": {"where": "field", "anims": ["water", "plant"], "hop": 45.0, "prop": "hive", "label": "tending the hives",
		"lines": ["Gently now, they're cross today.", "Good honey this year."]},
	"carve": {"where": "post", "anims": ["fix", "interact"], "hop": 60.0, "prop": "anvil_log", "label": "carving at your bench",
		"lines": ["Steady hands.", "Don't jog my elbow."]},
	"scribe": {"where": "post", "anims": ["interact"], "hop": 80.0, "prop": "desk", "label": "copying out letters and accounts",
		"lines": ["Ink's nearly dry.", "Can you read? No matter."]},
	"notices": {"where": "gates", "anims": ["interact"], "upper": "carry", "hop": 40.0, "label": "pinning up notices at the signposts",
		"lines": ["New notices posted.", "Read it yourself, it's all there."]},
	"ward": {"where": "outskirts", "anims": ["fold_arms", "sword_idle"], "hop": 40.0, "gesture": "look", "label": "watching the woods at the edge of town",
		"lines": ["Something's moving out there.", "Keep to the paths."]},
	"ritual": {"where": "holy", "anims": ["spell"], "hop": 70.0, "label": "at your rites",
		"lines": ["Hush. Can you feel it?", "The old powers stir."]},
	"repair": {"where": "homes", "anims": ["fix", "interact"], "hop": 50.0, "label": "fixing things around the settlement",
		"lines": ["Coupling's shot again.", "Hand me that spanner. No? Fine."]},
	"rounds_medic": {"where": "homes", "anims": ["interact", "talk"], "hop": 50.0, "label": "making your rounds of the sick",
		"lines": ["Keep that bandage clean.", "Drink plenty of water."]},
	"salvage": {"where": "wilds", "anims": ["pickup", "fix", "crouch"], "hop": 40.0, "label": "out salvaging scrap",
		"lines": ["Good scrap out here.", "Mind the sharp edges."]},
	"sell_scrap": {"where": "stall", "anims": ["interact"], "upper": "carry", "hop": 60.0, "label": "bringing salvage in to sell",
		"lines": ["Haul's good today.", "Who's buying?"]},
	"preflight": {"where": "post", "anims": ["fix", "interact"], "hop": 60.0, "prop": "crates", "label": "checking over your gear before a flight",
		"lines": ["Systems green.", "Weather's flyable."]},
	"deals": {"where": "square", "anims": ["phone", "fold_arms"], "hop": 60.0, "label": "making deals on your comms",
		"lines": ["Got what you need, for a price.", "Talk later. Busy."]},
	"grow": {"where": "field", "anims": ["water", "plant", "harvest"], "hop": 40.0, "label": "tending the hydroponic beds",
		"lines": ["Nutrient mix is off again.", "Lettuce is coming along."]},
	"deliver": {"where": "homes_gates", "anims": ["interact"], "upper": "carry", "hop": 30.0, "label": "running deliveries",
		"lines": ["Package for... not you.", "Coming through!"]},
	# Visitors' day out (MarketCrowd).
	"browse": {"where": "browse", "anims": ["interact", "idle", "talk", "fold_arms"], "hop": 40.0, "gesture": "think", "label": "in town for market day, looking over the stalls",
		"lines": ["How much for that?", "Robbery, at that price.", "I'll take two... no, one.", "Fresher last week.", "Just looking, thanks."]},
	"loiter": {"where": "knot", "anims": ["talk", "fold_arms", "idle", "talk", "lean"], "hop": 110.0, "gesture": "nod", "label": "in town for the day, passing the time in the square with friends",
		"lines": ["Busy today.", "Never seen the square so full.", "Have you heard the news?", "Nice day for it."]},
	"tavern_night": {"where": "tavern", "anims": ["talk", "idle", "lean"], "hop": 120.0, "gesture": "clap", "label": "in town for an evening at the tavern",
		"lines": ["One more and I'm off.", "Long walk home after this.", "Your round, I think."]},
	"head_home": {"where": "home", "anims": ["idle"], "hop": 300.0, "label": "heading home for the night",
		"lines": ["Long walk ahead.", "Home before dark, if I'm lucky."]},
}

## Each trade's day: [from hour, to hour, duty]. Hours outside these blocks are the
## person's own (eating, socialising, dancing, going home, sleeping: DecisionEngine).
## "sleep" in a block means sleeping then (the night watch sleeps by day).
const ROUTINES := {
	"farmer": [[6.0, 7.0, "livestock"], [7.0, 11.8, "till"], [11.8, 12.8, "lunch"], [12.8, 16.0, "harvest"], [16.0, 17.5, "haul"]],
	"smith": [[7.5, 12.0, "forge"], [12.0, 13.0, "lunch"], [13.0, 17.0, "forge"], [17.0, 18.0, "haul"]],
	"guard": [[7.0, 12.0, "patrol"], [12.0, 15.0, "gate"], [15.0, 19.0, "patrol"]],
	"innkeeper": [[8.0, 10.0, "supplies"], [10.0, 23.0, "serve"]],
	"hunter": [[5.5, 15.5, "hunt"], [15.5, 17.0, "bring_game"]],
	"priest": [[6.0, 8.0, "pray"], [8.0, 11.0, "visit"], [11.0, 14.0, "preach"], [16.0, 18.0, "pray"]],
	"weaver": [[8.0, 12.0, "weave"], [12.0, 13.0, "lunch"], [13.0, 16.5, "weave"], [16.5, 17.5, "haul"]],
	"miller": [[6.5, 12.0, "mill"], [12.0, 13.0, "lunch"], [13.0, 17.0, "mill"]],
	"herbalist": [[7.0, 11.0, "gather"], [11.0, 16.0, "brew"], [16.0, 17.0, "haul"]],
	"warden": [[7.0, 13.0, "ward"], [13.0, 19.0, "patrol"]],
	"runecarver": [[8.0, 12.0, "carve"], [12.0, 13.0, "lunch"], [13.0, 17.0, "carve"]],
	"bard": [[12.0, 14.0, "rehearse"], [14.0, 17.0, "play"], [19.0, 22.0, "play"]],
	"mystic": [[5.0, 7.0, "ritual"], [9.0, 16.0, "brew"], [21.0, 23.0, "ritual"]],
	"beekeeper": [[8.0, 12.0, "bees"], [12.0, 13.0, "lunch"], [13.0, 16.0, "bees"], [16.0, 17.0, "haul"]],
	"lamplighter": [[5.5, 6.5, "douse"], [8.0, 14.0, "sleep"], [18.5, 20.0, "lamps"]],
	"scribe": [[8.0, 10.0, "notices"], [10.0, 12.0, "scribe"], [12.0, 13.0, "lunch"], [13.0, 17.0, "scribe"]],
	"engineer": [[7.0, 12.0, "repair"], [12.0, 13.0, "lunch"], [13.0, 18.0, "repair"]],
	"medic": [[8.0, 12.0, "rounds_medic"], [12.0, 13.0, "lunch"], [13.0, 17.0, "brew"]],
	"scavenger": [[6.0, 15.0, "salvage"], [15.0, 16.5, "sell_scrap"]],
	"pilot": [[8.0, 16.0, "preflight"]],
	"security officer": [[7.0, 13.0, "patrol"], [13.0, 16.0, "gate"], [16.0, 19.0, "patrol"]],
	"data broker": [[10.0, 18.0, "deals"]],
	"hydroponics tech": [[7.0, 12.0, "grow"], [12.0, 13.0, "lunch"], [13.0, 17.0, "grow"]],
	"courier": [[8.0, 12.0, "deliver"], [12.0, 13.0, "lunch"], [13.0, 17.0, "deliver"]],
}
## Shopkeepers who make what they sell work at it outside their door for part of the
## day, and keep the counter the rest.
const SHOP_ROUTINES := {
	"weaponsmith": [[9.0, 12.0, "smithy"], [13.5, 16.0, "smithy"]],
	"armourer": [[8.5, 11.5, "smithy"], [14.0, 16.5, "smithy"]],
	"apothecary": [[7.5, 9.5, "gather"]],
}
## Guards who keep the night watch instead (about one in three; never the only guard,
## who is always the first person hired after the trader).
const NIGHT_WATCH := [[21.0, 24.0, "night_watch"], [0.0, 5.5, "night_watch"], [8.0, 15.0, "sleep"], [15.0, 19.0, "gate"]]

## Props set out where a trade is plied: kit models placed in front of the worker.
const PROPS := {
	"anvil": [["props/Anvil", 0, Vector3.ZERO, 1.0]],
	"forge": [["props/Anvil", 0, Vector3.ZERO, 1.0], ["props/Anvil_Log", 30, Vector3(1.1, 0, -0.3), 1.0], ["props/Barrel", 0, Vector3(-1.0, 0, -0.4), 0.9]],
	"anvil_log": [["props/Anvil_Log", 0, Vector3.ZERO, 1.0]],
	"crates": [["props/FarmCrate_Empty", 0, Vector3(-0.35, 0, 0), 1.0], ["props/FarmCrate_Carrot", 25, Vector3(0.4, 0, 0.1), 1.0]],
	"cauldron": [["props/Cauldron", 0, Vector3.ZERO, 0.9]],
	"hive": [["props/Barrel", 0, Vector3.ZERO, 0.8]],
	"desk": [["props/Crate_Wooden", 0, Vector3.ZERO, 1.0], ["props/Candle_1", 0, Vector3(0.15, 0.95, 0), 1.0]],
	"field": [["props/FarmCrate_Carrot", 0, Vector3.ZERO, 1.0], ["props/FarmCrate_Empty", 40, Vector3(0.9, 0, 0.5), 1.0]],
}

## Where a town's work gets done, from its layout: the square, the gates (where roads
## leave), the market, towers and wells, the tavern door, the doors of homes, fields just
## past the last houses, and the wilds beyond.
static func places(gen: ChunkGenerator, site: Dictionary, data: Dictionary) -> Dictionary:
	var c: Vector2 = site["center"]
	var outer := float(site.get("outer", 60.0))
	var inner := float(site.get("inner", 30.0))
	var out := {"center": c, "inner": inner, "outer": outer, "gates": [], "market": [], "towers": [], "wells": [],
		"holy": [], "homes": [], "tavern": [], "stall": [], "lamps": [], "roads": gen.road_angles(site)}
	for it in gen.settlement_layout(site):
		var t: String = it["t"]
		var p: Vector2 = it["p"]
		match t:
			"signpost":
				out["gates"].append(p)
				out["lamps"].append(p)
			"market_stall", "fruit_cart", "barrels", "wagon":
				out["market"].append(p + (c - p).normalized() * 2.2)
				out["lamps"].append(p + (c - p).normalized() * 2.2)
			"watchtower", "comms_spire", "ops_tower":
				out["towers"].append(p + (c - p).normalized() * 4.0)
			"well":
				out["wells"].append(p + (c - p).normalized() * 1.6)
			"shrine", "spire":
				out["holy"].append(p + (c - p).normalized() * 4.0)
			"outpost_light":
				out["lamps"].append(p)
			"trader":
				out["stall"].append(p + Vector2(sin(float(it["yaw"])), cos(float(it["yaw"]))) * 1.6)
	# The village's own fields (medieval villages and towns), for the farmers.
	out["fields"] = TownLife.plan(gen, site)["fields"] if TownLife.applies(gen, site) else []
	# Benches by the doors, for anyone sitting down: [spot, yaw it faces out along].
	out["benches"] = []
	if TownLife.applies(gen, site):
		for pc in TownLife.plan(gen, site)["pieces"]:
			if pc["k"] == "bench":
				out["benches"].append([pc["p"], float(pc["yaw"])])
	# Beside each shop's door, a yard where its keeper works at their trade.
	out["shop_yards"] = {}
	for h in TownShops.shops_of(gen, site):
		var door := TownShops.door_point(h)
		if h["kind"] == "tavern":
			out["tavern"].append(door)
		var outward := (door - (h["p"] as Vector2)).normalized()
		out["shop_yards"][int(h["i"])] = [door + outward * 0.8 + outward.orthogonal() * 2.8, atan2(outward.x, outward.y)]
	for rec in data.get("npcs", []):
		if not rec.get("dead", false):
			out["homes"].append(rec["home"])
	# Where roads leave town with no signpost (old towns, outposts): their edge.
	if (out["gates"] as Array).is_empty():
		for w in out["roads"]:
			out["gates"].append(c + Vector2.from_angle(w) * (inner + 2.0))
	if (out["gates"] as Array).is_empty():
		for k in 4:
			out["gates"].append(c + Vector2.from_angle(TAU * k / 4.0 + 0.4) * inner)
	if (out["holy"] as Array).is_empty():
		out["holy"] = (out["wells"] as Array).duplicate() if not (out["wells"] as Array).is_empty() else [c + Vector2(2.5, 1.5)]
	if (out["tavern"] as Array).is_empty():
		out["tavern"].append(c + Vector2(-3.0, 2.0))
	if (out["stall"] as Array).is_empty():
		out["stall"].append(c)
	if (out["lamps"] as Array).is_empty():
		out["lamps"] = (out["gates"] as Array).duplicate()
	# A guard's round: the gates, towers, wells and the square, in order round the town.
	var rounds: Array = (out["gates"] as Array) + (out["towers"] as Array) + (out["wells"] as Array) + [c + Vector2(3, 0)]
	rounds.sort_custom(func(a, b): return (a - c).angle() < (b - c).angle())
	out["rounds"] = rounds
	(out["lamps"] as Array).sort_custom(func(a, b): return (a - c).angle() < (b - c).angle())
	return out

## A direction out of town clear of the roads, for a person's own field or hunting
## ground (stable per person and kind).
static func _clear_angle(places: Dictionary, id: String, salt: int) -> float:
	var a := float(absi(hash(id + str(salt))) % 6283) / 1000.0
	for _i in 8:
		var ok := true
		for w in places["roads"]:
			if absf(angle_difference(a, w)) < 0.35:
				ok = false
		if ok:
			return a
		a += 0.6
	return a

## This person's own spot by the side of their door (smiths, weavers, scribes...), and
## the way they face while working there.
static func post(rec: Dictionary, places: Dictionary) -> Array:
	var home: Vector2 = rec["home"]
	var c: Vector2 = places["center"]
	var to_c := (c - home).normalized() if home.distance_to(c) > 0.5 else Vector2(1, 0)
	var side := 1.0 if absi(hash(String(rec["id"]))) % 2 == 0 else -1.0
	var at := home + to_c * 1.6 + to_c.orthogonal() * side * 2.4
	return [at, atan2(to_c.x, to_c.y)]

static func _field(rec: Dictionary, places: Dictionary, stop: int) -> Vector2:
	var f := _own_field(rec, places)
	if not f.is_empty():
		# Down a row of the village's own field (TownLife), a few steps further each stop.
		var h := absi(hash(String(rec["id"])))
		var rows_x := int(f["rows"]) == 0
		var a_len := float(f["hx"] if rows_x else f["hz"]) - 1.2
		var b_len := float(f["hz"] if rows_x else f["hx"]) - 1.2
		var row := lerpf(-b_len, b_len, float(h % 101) / 100.0)
		var along := -a_len + fposmod(float(stop) * 2.6 + float(h % 17), 2.0 * a_len)
		return TownLife.frame_to_world(f["p"], float(f["yaw"]), Vector2(along, row) if rows_x else Vector2(row, along))
	var a := _clear_angle(places, String(rec["id"]), 11)
	var c: Vector2 = places["center"]
	var base: Vector2 = c + Vector2.from_angle(a) * (float(places["outer"]) + 8.0 + float(absi(hash(String(rec["id"]))) % 8))
	# Working along the rows.
	return base + Vector2.from_angle(a + PI / 2) * float((stop % 4) - 1.5) * 2.2

## The village field this person works ({} where the town has none): one per person,
## stable, spread over the fields.
static func _own_field(rec: Dictionary, places: Dictionary) -> Dictionary:
	var fs: Array = places.get("fields", [])
	if fs.is_empty():
		return {}
	return fs[absi(hash(String(rec["id"]) + "field")) % fs.size()]

static func _wilds(rec: Dictionary, places: Dictionary, stop: int) -> Vector2:
	var a := _clear_angle(places, String(rec["id"]), 23) + sin(float(stop) * 1.7) * 0.5
	var r := float(places["outer"]) + 25.0 + float(absi(hash(String(rec["id"]) + str(stop))) % 35)
	return (places["center"] as Vector2) + Vector2.from_angle(a) * r

static func _pick(list: Array, rec: Dictionary, stop: int) -> Vector2:
	if list.is_empty():
		return Vector2.INF
	return list[absi(hash(String(rec["id"]) + "|" + str(stop))) % list.size()]

## The duty block this person is in at `hour`: [from, to, duty] or [] (their own time).
static func block(rec: Dictionary, hour: float) -> Array:
	var job: String = rec["job"]
	if job == "trader" or rec.get("child", false): # children have no duties
		return []
	if rec.has("visit"):
		return MarketCrowd.block(rec, hour)
	var plan: Array = SHOP_ROUTINES.get(String(rec["shop_kind"]), []) if rec.has("shop_kind") else ROUTINES.get(job, [])
	if NPCGen.GUARD_JOBS.has(job) and night_watch(rec):
		plan = NIGHT_WATCH
	# Early birds and late starters: up to forty minutes either way, by diligence.
	var early := (float(rec["traits"]["diligent"]) - 0.5) * 1.3
	for b in plan:
		var from := float(b[0]) - (early if float(b[0]) > 0.0 else 0.0)
		var to := float(b[1]) - (early * 0.5 if float(b[1]) < 24.0 else 0.0)
		if hour >= from and hour < to:
			return b
	return []

## Whether this guard keeps the night watch (about a third of the guards, never the first).
static func night_watch(rec: Dictionary) -> bool:
	var id := String(rec["id"])
	return not id.ends_with("_1") and absi(hash(id + "nw")) % 3 == 0

## What this person's routine has them doing right now: {} in their own time, else
## {duty, action ("work" or "sleep"), target, face (yaw or INF), anim, upper, perform,
## gesture, label, shift}. `t` is a running clock in seconds (which stop they are at).
static func duty_at(rec: Dictionary, places: Dictionary, hour: float, t: float) -> Dictionary:
	if places.is_empty():
		return {}
	var b := block(rec, hour)
	if b.is_empty():
		return {}
	var key: String = b[2]
	if key == "sleep":
		return {"duty": "sleep", "action": "sleep", "target": rec["home"], "label": "asleep after your night's work"}
	var d: Dictionary = DUTIES[key]
	var hop := float(d.get("hop", 40.0)) * (0.8 + float(absi(hash(String(rec["id"]))) % 40) / 100.0)
	var stop := int(floor((t + float(absi(hash(String(rec["id"]) + key)) % 997)) / hop))
	var c: Vector2 = places["center"]
	var target := Vector2.INF
	var face := INF
	match String(d["where"]):
		"post":
			var pp := post(rec, places)
			target = pp[0]
			face = pp[1]
		"shopyard":
			var y = (places.get("shop_yards", {}) as Dictionary).get(int(rec.get("shop_i", -1)))
			if y != null:
				target = y[0]
				face = y[1]
		"field":
			target = _field(rec, places, stop)
			var of := _own_field(rec, places)
			if of.is_empty():
				face = atan2(c.x - target.x, c.y - target.y) + PI * 0.5 * float(stop % 2)
			else:
				# Facing down the row.
				var fy := float(of["yaw"])
				face = atan2(cos(fy), -sin(fy)) if int(of["rows"]) == 0 else fy
		"field_stall":
			target = _field(rec, places, stop) if stop % 2 == 0 else _pick(places["stall"], rec, 0)
		"yard":
			target = (rec["home"] as Vector2) + Vector2.from_angle(float(stop) * 2.1 + float(absi(hash(String(rec["id"]))) % 6)) * 4.0
		"wilds":
			target = _wilds(rec, places, stop)
		"outskirts":
			var a := _clear_angle(places, String(rec["id"]), 37) + float(stop % 5) * 0.45
			target = c + Vector2.from_angle(a) * (float(places["outer"]) + 2.0 + float(stop % 3) * 3.0)
		"rounds":
			var r: Array = places["rounds"]
			var i0 := absi(hash(String(rec["id"]))) % maxi(1, r.size())
			target = r[(i0 + stop) % r.size()] if not r.is_empty() else c
		"gates":
			target = _pick(places["gates"], rec, stop / 3 if key == "gate" else stop)
			face = atan2(target.x - c.x, target.y - c.y) # looking out along the road
		"lamps":
			var l: Array = places["lamps"]
			target = l[stop % l.size()] if not l.is_empty() else c
		"homes":
			target = _pick(places["homes"], rec, stop)
		"home":
			target = rec["home"]
		"browse":
			var spots := MarketCrowd.browse_spots(places)
			var at = _pick(spots, rec, stop)
			if at != Vector2.INF:
				# Stood before it, looking it over, not on top of it.
				var off := Vector2.from_angle(float(absi(hash(String(rec["id"]) + str(stop))) % 628) / 100.0)
				target = (at as Vector2) + off * 1.4
				face = atan2(at.x - target.x, at.y - target.y)
		"knot":
			var ks := MarketCrowd.knots(places)
			var k: Vector2 = ks[absi(hash(String(rec["id"]) + str(stop / 2))) % ks.size()]
			# Round the knot, facing in.
			var a3 := float(absi(hash(String(rec["id"]) + "k")) % 628) / 100.0
			target = k + Vector2.from_angle(a3) * 1.0
			face = atan2(k.x - target.x, k.y - target.y)
		"homes_gates":
			target = _pick(places["homes"] if stop % 2 == 0 else places["gates"], rec, stop)
		"square":
			var a2 := float(absi(hash(String(rec["id"]) + "sq")) % 628) / 100.0
			target = c + Vector2.from_angle(a2) * (3.0 + float(absi(hash(String(rec["id"]))) % 30) / 10.0)
		"stall", "tavern", "holy":
			target = _pick(places[String(d["where"])], rec, 0)
			if target != Vector2.INF:
				# Not all on the same spot.
				target += Vector2.from_angle(float(absi(hash(String(rec["id"]))) % 628) / 100.0) * 1.3
	if target == Vector2.INF:
		target = rec.get("work", c)
	var anims: Array = d.get("anims", [])
	return {
		"duty": key, "action": "work", "target": target, "face": face,
		"anim": anims[stop % anims.size()] if not anims.is_empty() else "",
		"upper": d.get("upper", ""), "perform": d.get("perform", ""), "gesture": d.get("gesture", ""),
		"label": d.get("label", "at work"), "shift": d.get("shift", false), "stop": stop,
	}

## A line about what they are doing, said to a passer-by ("" if the duty has none).
static func line(duty: Dictionary, h: int) -> String:
	var d: Dictionary = DUTIES.get(duty.get("duty", ""), {})
	var l: Array = d.get("lines", [])
	return l[h % l.size()] if not l.is_empty() else ""

## Where people's work props stand (anvils, crates, hives): [[kit model list, Vector2,
## yaw], ...], derived from who lives here.
static func props(places: Dictionary, data: Dictionary) -> Array:
	var out: Array = []
	if places.is_empty():
		return out
	for rec in data.get("npcs", []):
		if rec.get("dead", false):
			continue
		var plan: Array = SHOP_ROUTINES.get(String(rec["shop_kind"]), []) if rec.has("shop_kind") else ROUTINES.get(String(rec["job"]), [])
		var kinds := {}
		for b in plan:
			var d: Dictionary = DUTIES.get(String(b[2]), {})
			if d.has("prop"):
				kinds[d["prop"]] = d["where"]
			elif String(d.get("where", "")) == "field" and int(rec["era"]) != Eras.SCIFI and (places.get("fields", []) as Array).is_empty():
				kinds["field"] = "field" # a crate of the crop, where the village has no fields of its own
		for k in kinds:
			if kinds[k] == "shopyard":
				var y = (places.get("shop_yards", {}) as Dictionary).get(int(rec.get("shop_i", -1)))
				if y != null:
					out.append([PROPS[k], (y[0] as Vector2) + Vector2(sin(float(y[1])), cos(float(y[1]))) * 0.9, float(y[1])])
			elif kinds[k] == "post":
				var pp := post(rec, places)
				var at: Vector2 = pp[0] + Vector2(sin(float(pp[1])), cos(float(pp[1]))) * 0.9
				out.append([PROPS[k], at, float(pp[1])])
			else:
				var at2 := _field(rec, places, 0) + Vector2.from_angle(_clear_angle(places, String(rec["id"]), 11)) * 2.5
				out.append([PROPS[k], at2, _clear_angle(places, String(rec["id"]), 11)])
	return out

## Small talk between neighbours, by era: [opening, answer].
const CHATTER := [
	[["Did you see the price of salt this week?", "Robbery, I call it."], ["Think it'll rain?", "My knee says so."],
	["Heard a wolf howling last night.", "Keep your door barred, then."], ["How's the little one?", "Growing like a weed."],
	["The ale's gone sour again.", "Don't tell the innkeeper I said so."], ["Bandits on the east road, they say.", "Then I'll not be going east."]],
	[["The grove was singing last night.", "It always does before a storm."], ["Have you seen the moonmoths?", "Thick as fog by the mere."],
	["My bees are restless.", "So are mine. Something's coming."], ["Dreamt of the old ones again.", "Best not speak of it."]],
	[["Generator's running rough.", "Engineer's on it. Supposedly."], ["Supply drop's late.", "Third time this month."],
	["Picked up raider chatter on the band.", "Keep the gate sealed tonight."], ["Rations taste like cardboard.", "Cardboard would be an upgrade."]],
]

## What two people chatting say: the latest town news if there is any, else small talk
## or a word about their trades.
static func chatter(a: Dictionary, b: Dictionary, town: Dictionary, h: int) -> Array:
	var rum: Array = town.get("rumors", [])
	if not rum.is_empty() and h % 3 == 0:
		var news := String(rum[h % rum.size()]).split(": ", true, 1)[-1]
		return ["Did you hear? %s" % news, ["No! Truly?", "I heard the same.", "Gods help us.", "Can't say I'm surprised."][h % 4]]
	if h % 3 == 1 and b["job"] != a["job"]:
		return ["How's the %s trade, %s?" % [b["job"], String(b["name"]).split(" ")[0]], ["Busy as ever.", "Slow. Too slow.", "Can't complain. Well, I could.", "Don't ask."][h % 4]]
	var era := clampi(int(a.get("era", 0)), 0, CHATTER.size() - 1)
	var pool: Array = CHATTER[era]
	return pool[h % pool.size()]

## This person's routine in words, for the language model ("" for none).
static func day_words(rec: Dictionary) -> String:
	if rec["job"] == "trader":
		return ""
	if rec.has("visit"):
		var v: Array = rec["visit"]
		return "you don't live here; you came in from the countryside for the day, arriving about %s and setting off home about %s" % [_clock(v[0]), _clock(float(v[1]) - MarketCrowd.LEAVE)]
	var plan: Array = SHOP_ROUTINES.get(String(rec["shop_kind"]), []) if rec.has("shop_kind") else ROUTINES.get(String(rec["job"]), [])
	if NPCGen.GUARD_JOBS.has(rec["job"]) and night_watch(rec):
		plan = NIGHT_WATCH
	var parts := PackedStringArray()
	for b in plan:
		var what: String = "sleeping" if b[2] == "sleep" else String(DUTIES[b[2]]["label"])
		parts.append("%s to %s %s" % [_clock(b[0]), _clock(b[1]), what])
	return "; ".join(parts)

static func _clock(h: float) -> String:
	return "%d:%02d" % [int(h) % 24, int(round(fposmod(h, 1.0) * 60.0)) % 60]
