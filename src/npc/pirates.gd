class_name Pirates
## Pirates on big water, now and then. While you are on or beside open water (a big lake
## or the sea), a pirate boat may put out and come for you: rarely, never near where you
## arrive, never on alien worlds, and never again for a good while after the last.
## They hail you and demand a toll; pay them (talk to them), get away out of reach, or
## fight. They fight from their deck: crossbows, slings and thrown knives near spawn,
## guns on the frontier. Their boats come from the boats code (BoatManager.spawn, faction
## "pirate"); this decides when they come and how they fight. Spawned boats are not
## saved: a pirate encounter is a passing thing.

const CHECK_EVERY := 25.0 ## seconds between rolls while you are by big water
const CHANCE := 0.2 ## per roll
const COOLDOWN := [700.0, 1300.0] ## seconds after one before another can come
const SAFE_R := 400.0
const MIN_OPEN := 110.0 ## how wide the water must be (no pirates on ponds)
const SPAWN := [160.0, 320.0] ## how far off they put out
const DEMAND_SECS := 12.0
const LEAVE_R := 45.0 ## get this far off while they demand and they let you go
const SHOT_RANGE := 26.0

const WEAPONS := {
	"low": ["sling", "throwing_knives", "javelin", "shortbow"],
	"mid": ["shortbow", "crossbow", "javelin", "throwing_knives"],
	"high": ["crossbow", "heavy_crossbow", "composite_bow"],
	"raider": ["scrap_pistol", "pulse_pistol", "pulse_smg", "pulse_rifle"],
}
const EPITHETS := ["Saltbeard", "the Eel", "Bilge", "Hookhand", "Barnacle", "the Gull", "Redtide", "Driftwood", "Keelhaul", "Squall"]
const HAILS := [
	["Heave to and hand over your purse!", "Ahoy, landlubber! Pay the toll or swim with the fishes!", "These are our waters. Pay up!"],
	["Cut your engine and hand over the credits!", "Toll water, drifter. Pay up or sink.", "Hold it right there. Credits, now."],
]
const FIGHT_LINES := [["Loose! Loose!", "Board 'em... well, shoot 'em!", "Should've paid!"], ["Light 'em up!", "Open fire!", "Should've paid!"]]
const PAID_LINES := ["A pleasure, matey.", "Off you go, then.", "Fair winds. For now."]

## The boat they come in, by era and zone.
static func boat_kind(era: int, zone: int) -> String:
	if era == Eras.SCIFI:
		return "launch"
	return "cog" if zone >= 22 else "fishing_boat"

## A pirate crew: [crew recs] for the boat's stations, armed for range.
static func crew(era: int, zone: int, stations: int, at: Vector2) -> Array:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var t := Bandits.tier(era, zone)
	var n := clampi(2 + zone / 14, 2, maxi(stations, 1))
	var out: Array = []
	for i in n:
		var p := NPCGen.person(r, era, i, 0, 0)
		for _try in 8: # never a child
			if not p.get("child", false):
				break
			p = NPCGen.person(r, era, i, 0, 0)
		var leader := i == 0
		p["id"] = "pirate_%d_%d" % [r.randi() % 1000000, i]
		p["job"] = "pirate captain" if leader else "pirate"
		p["faction"] = "pirate"
		p["name"] = "%s %s" % [String(p["name"]).split(" ")[0], EPITHETS[r.randi() % EPITHETS.size()]]
		p["body"]["cloth"] = Bandits.CLOTH[r.randi() % Bandits.CLOTH.size()]
		p["body"]["cloth2"] = Bandits.CLOTH[r.randi() % Bandits.CLOTH.size()]
		p["traits"]["friendly"] = snappedf(r.randf() * 0.25, 0.01)
		p["traits"]["greedy"] = snappedf(0.6 + r.randf() * 0.4, 0.01)
		p["traits"]["brave"] = snappedf((0.75 if leader else 0.4) + r.randf() * 0.4, 0.01)
		p["likes"] = "rum and plunder"
		p["worry"] = "the harbour watch"
		p["speech"] = "salty, swaggering sea-dog talk" if era != Eras.SCIFI else "clipped, cocky smuggler slang"
		p["rel"] = -60
		var weapons: Array = WEAPONS[t]
		var w: String = weapons[weapons.size() - 1 - r.randi() % 2] if leader else weapons[r.randi() % weapons.size()]
		p["held"] = {"type": w, "qty": 1, "quality": 1.0}
		var gear := {}
		var kit: Dictionary = Bandits.KIT[t][1]
		for slot in kit:
			if slot != "head" and (leader or r.randf() < 0.5):
				gear[slot] = {"type": kit[slot], "qty": 1, "quality": 1.0}
		p["gear"] = gear
		p["pos"] = Vector3(at.x, 0.0, at.y)
		p["level"] = clampi(zone - 1 + r.randi_range(0, 2) + (2 if leader else 0), 1, 99)
		p["hp"] = NPCSocial.max_hp(p)
		p["purse"] = r.randi_range(10, 40) * (1 + zone / 5) * (3 if leader else 1)
		p["debt"] = 0
		p["debt_due"] = 0.0
		out.append(p)
	return out

## Whether pirates may come for someone at `p` at all (the world, the place).
static func allowed(p: Vector2) -> bool:
	return Eras.theme != "alien" and p.length() >= SAFE_R

## What it costs to make them go away: a share of your Marks.
static func toll(money: int, zone: int) -> int:
	return Bandits.toll(money, zone + 4)
