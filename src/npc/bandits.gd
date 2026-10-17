class_name Bandits
## Bands of outlaws roaming the wilds between towns, now and then. Each big cell of land
## (CELL) rolls once per in-game day whether a band is passing through it; most days
## most cells have none, nothing comes within SAFE_R of where you arrive, and no band
## camps near a town. Like everything else in the world it is a pure function of the
## seed (and the day), so the same band is in the same place for everyone; only who of
## them you have killed is kept, in their camp's chunk.
##
## By day a band walks a loop of the country round its camp; by night it sits round a
## fire at the camp with one of them keeping watch. Spot them first and you can go round;
## let them spot you and they demand your purse, then fight. Near spawn they are poor
## medieval cutthroats with clubs and knives; out in higher zones they are tougher and
## better armed, and in the frontier lands they are raiders with guns. Hurt badly, the
## cowards among them run.

const CELL := 640.0
const CHANCE := 0.35
const SAFE_R := 320.0 ## no bandits this near where you arrive
const TOWN_CLEAR := 90.0 ## metres a camp keeps from the edge of any town
const ROAM := [45.0, 140.0] ## how far their day's walk takes them from camp
const SPOT := 24.0 ## how far off they notice you by day (half by night, less if you sneak)
const DEMAND_SECS := 6.0 ## how long they give you to pay up or back off before they attack
const LEAVE_R := 32.0 ## back off this far while they demand and they let you go

## Kit by tier (zone level under 8, under 20, above) and era: [weapons, worst first;
## gear]. The chief carries one of the best two.
const KIT := {
	"low": [["stone_knife", "wooden_club", "sling", "quarterstaff", "hunting_spear", "hand_axe"], {"chest": "vest_hide"}],
	"mid": [["cudgel", "shortbow", "bronze_sword", "mace", "falchion", "bronze_axe"], {"head": "helm_studded", "chest": "jerkin_studded"}],
	"high": [["crossbow", "steel_sword", "flail", "halberd", "battle_axe", "morning_star"], {"head": "helm_iron", "chest": "mail_iron"}],
	"raider": [["dagger", "scrap_pistol", "pulse_pistol", "pulse_smg", "pulse_rifle"], {"head": "helm_recon", "chest": "vest_plated"}],
}
const EPITHETS := ["the Red", "Blackhand", "One-Eye", "the Knife", "Crowbait", "the Wolf", "Ashjaw", "Quickfingers", "the Hound", "Scar"]
const RAIDER_EPITHETS := ["Static", "Burnout", "Chrome", "Deadline", "Wrench", "Glitch", "Rust", "Flatline"]
const CLOTH := [Color(0.18, 0.15, 0.12), Color(0.3, 0.22, 0.15), Color(0.35, 0.12, 0.1), Color(0.22, 0.24, 0.2), Color(0.12, 0.12, 0.13)]
const DEMANDS := [
	["Your purse or your life, traveller!", "That's a fine purse. Hand it over.", "Toll road, friend. Pay up.", "Well, well. What have we here?"],
	["Hands where we can see them!", "Credits. All of them. Now.", "Wrong road, drifter. Pay the toll."],
]
const ATTACK_LINES := [["Cut them down!", "Get them!", "Should've paid!"], ["Light them up!", "Open fire!", "Should've paid!"]]
const FLEE_LINES := ["Run for it!", "Not worth dying for!", "I'm out!"]
const PAID_LINES := ["Pleasure doing business.", "Off with you, then.", "Smart choice."]

## The day a band's roll is for (bands move on each day).
static func period(day: float) -> int:
	return int(floor(day))

## Bands whose camps are within `radius` of `p` on day `day`.
static func near(gen: ChunkGenerator, p: Vector2, radius: float, day: float) -> Array:
	var out: Array = []
	if Eras.theme == "alien":
		return out # the endgame worlds have their own dangers
	var per := period(day)
	for cz in range(int(floor((p.y - radius) / CELL)), int(floor((p.y + radius) / CELL)) + 1):
		for cx in range(int(floor((p.x - radius) / CELL)), int(floor((p.x + radius) / CELL)) + 1):
			var b := band_at(gen, cx, cz, per)
			if not b.is_empty() and (b["camp"] as Vector2).distance_to(p) <= radius:
				out.append(b)
	return out

## The band in cell (cx, cz) on day `per`, or {}.
static func band_at(gen: ChunkGenerator, cx: int, cz: int, per: int) -> Dictionary:
	if WHash.unit2(gen.seed, cx, cz, 9100 + per) >= CHANCE:
		return {}
	var r := WHash.rng(gen.seed, cx, cz, 9200 + per)
	var camp := Vector2((cx + 0.2 + 0.6 * r.randf()) * CELL, (cz + 0.2 + 0.6 * r.randf()) * CELL)
	if camp.length() < SAFE_R or not _dry(gen, camp):
		return {}
	if not _clear_of_towns(gen, camp, TOWN_CLEAR + ROAM[0]):
		return {}
	# Raiders only out in the frontier's tech lands; medieval outlaws everywhere nearer.
	var era := WorldField.dominant(gen.field.era_weights(camp.x, camp.y))
	era = Eras.SCIFI if era == Eras.SCIFI and (not Eras.themed() or camp.length() > Eras.FRONTIER) else Eras.MEDIEVAL
	var zone := Eras.zone_level(camp.x, camp.y)
	var id := "b%d_%d_%d" % [cx, cz, per]
	var route: Array = []
	var a0 := r.randf() * TAU
	for i in 5:
		var a := a0 + TAU * i / 5.0 + r.randf_range(-0.3, 0.3)
		var at := camp + Vector2.from_angle(a) * r.randf_range(ROAM[0], ROAM[1])
		if _dry(gen, at) and _clear_of_towns(gen, at, 20.0):
			route.append(at)
	if route.is_empty():
		route.append(camp)
	var count := clampi(2 + zone / 12 + r.randi_range(0, 1), 2, 5)
	var members: Array = []
	for i in count:
		members.append(_member(r, era, zone, i, id, camp, cx, cz))
	return {"id": id, "cell": Vector2i(cx, cz), "camp": camp, "era": era, "zone": zone, "route": route,
		"members": members, "name": ("Raider" if era == Eras.SCIFI else "Bandit") + " band"}

static func _dry(gen: ChunkGenerator, p: Vector2) -> bool:
	return gen.field.height(p.x, p.y) > ChunkGenerator.WATER_LEVEL + 1.5

static func _clear_of_towns(gen: ChunkGenerator, p: Vector2, margin: float) -> bool:
	for s in gen.settlements_near(p.x - margin - 80.0, p.y - margin - 80.0, p.x + margin + 80.0, p.y + margin + 80.0):
		if (s["center"] as Vector2).distance_to(p) < float(s["outer"]) + margin:
			return false
	return true

static func tier(era: int, zone: int) -> String:
	if era == Eras.SCIFI:
		return "raider"
	return "low" if zone < 8 else ("mid" if zone < 20 else "high")

static func _member(r: RandomNumberGenerator, era: int, zone: int, i: int, band: String, camp: Vector2, cx: int, cz: int) -> Dictionary:
	var p := NPCGen.person(r, era, i, cx, cz)
	var leader := i == 0
	var raider := era == Eras.SCIFI
	p["id"] = "%s_%d" % [band, i]
	p["band"] = band
	p["job"] = ("raider boss" if raider else "bandit chief") if leader else ("raider" if raider else "bandit")
	var ep: Array = RAIDER_EPITHETS if raider else EPITHETS
	p["name"] = "%s %s" % [String(p["name"]).split(" ")[0], ep[r.randi() % ep.size()]]
	p["body"]["cloth"] = CLOTH[r.randi() % CLOTH.size()]
	p["body"]["cloth2"] = CLOTH[r.randi() % CLOTH.size()]
	p["traits"]["friendly"] = snappedf(r.randf() * 0.25, 0.01)
	p["traits"]["greedy"] = snappedf(0.6 + r.randf() * 0.4, 0.01)
	p["traits"]["brave"] = snappedf((0.75 if leader else 0.35) + r.randf() * 0.4, 0.01)
	p["likes"] = "easy coin" if not raider else "an unguarded convoy"
	p["worry"] = "the town guard" if not raider else "security patrols"
	p["speech"] = "rough, mocking and threatening" if not raider else "clipped, cocky frontier slang"
	p["rel"] = -50
	var a := TAU * i / 5.0
	p["home"] = camp + Vector2.from_angle(a) * 2.4
	p["work"] = camp
	p["pos"] = Vector3(p["home"].x, 0.0, p["home"].y)
	var kit: Array = KIT[tier(era, zone)]
	var weapons: Array = kit[0]
	var w: String = weapons[r.randi() % weapons.size()]
	if leader:
		w = weapons[(weapons.size() - 1 - r.randi() % 2)] # the best of the band's arms
	p["held"] = {"type": w, "qty": 1, "quality": 1.0}
	var gear := {}
	for slot in kit[1]:
		if leader or r.randf() < 0.6:
			gear[slot] = {"type": kit[1][slot], "qty": 1, "quality": 1.0}
	p["gear"] = gear
	p["level"] = clampi(zone - 1 + r.randi_range(0, 2) + (2 if leader else 0), 1, 99)
	p["hp"] = NPCSocial.max_hp(p)
	p["purse"] = r.randi_range(5, 25) * (1 + zone / 5) * (3 if leader else 1)
	p["debt"] = 0
	p["debt_due"] = 0.0
	return p

## Whether this person fights from range (bow, sling, crossbow, gun).
static func ranged(rec: Dictionary) -> bool:
	var held = rec.get("held", null)
	return held is Dictionary and bool(ItemDB.def(String(held.get("type", ""))).get("ranged", false))

## A band member's next move. per: hour, pos, player_dist, player_pos, now, band (the
## band's live state: alert, demand_until, paid, leader position, camp, route), hp share.
static func decide(rec: Dictionary, per: Dictionary) -> Dictionary:
	var b: Dictionary = per["band"]
	var pos: Vector2 = per["pos"]
	var pd := float(per.get("player_dist", INF))
	var now := float(per.get("now", 0.0))
	var hp_share := float(rec.get("hp", 100.0)) / maxf(1.0, NPCSocial.max_hp(rec))
	var camp: Vector2 = b["camp"]
	var out := {"action": "idle", "target": pos}
	# Badly hurt, the faint-hearted run for it (and keep running).
	if rec.get("routed", false) or (hp_share < 0.3 and float(rec["traits"]["brave"]) < 0.85):
		rec["routed"] = true
		var pp: Vector2 = per.get("player_pos", pos)
		var away := (pos - pp).normalized() if pos.distance_to(pp) > 0.1 else Vector2(1, 0)
		return {"action": "flee", "target": pos + away * 30.0}
	if b.get("alert", false) and pd < 60.0:
		return {"action": "attack", "target_player": true}
	if float(b.get("demand_until", 0.0)) > now and pd < LEAVE_R + 10.0:
		return {"action": "confront", "target_player": true}
	var hour := float(per["hour"])
	var night := hour >= 20.5 or hour < 6.0
	var i := int(String(rec["id"]).get_slice("_", 3))
	if night:
		# Round the fire, one keeping watch a little way off.
		if i == 1:
			return {"action": "idle", "target": camp + Vector2(0, 7.0).rotated(float(b["cell"].x)), "watch": true}
		return {"action": "sit", "target": rec["home"], "camp": true}
	# By day the band walks its loop together, the chief leading.
	var route: Array = b["route"]
	var stop := int(floor((now + float(absi(hash(String(b["id"]))) % 500)) / 75.0))
	var goal: Vector2 = route[stop % route.size()]
	if i != 0 and b.has("leader"):
		var lp: Vector2 = b["leader"]
		goal = lp + Vector2.from_angle(TAU * i / 5.0 + 1.0) * 2.6
		if pos.distance_to(lp) < 4.0 and pos.distance_to(goal) < 2.0:
			return {"action": "idle", "target": pos}
	return {"action": "wander", "target": goal}

## How far off this member notices you right now (metres).
static func spot_range(hour: float, sneaking: bool) -> float:
	var r := SPOT * (0.5 if hour >= 20.5 or hour < 5.5 else 1.0)
	return r * (0.45 if sneaking else 1.0)

## What a band might take as a toll: a share of your Marks, at least something.
static func toll(money: int, zone: int) -> int:
	return clampi(int(money * 0.3), mini(money, 10 + zone * 3), money)
