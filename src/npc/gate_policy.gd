class_name GatePolicy
## Who a walled town lets in, worked out from the people who live there. Brave guards
## and townsfolk who fear bandits make a strict town; friendly folk make an easy-going
## one; the more dangerous the land around it (its zone level) and the more trouble the
## traveller has caused there lately, the stricter it gets. From that strictness come the
## standing needed to be waved through the gate, the toll, how long a paid pass lasts and
## whether the gates shut to strangers at night. Each guard is their own person too: a
## greedy one takes a bribe, an honest one is insulted by it.
##
## Pure functions of the town's saved people, so it is the same for every player and
## needs nothing new saved.

## Words for how strict a town is: [from strictness, label].
const TEMPERS := [[0.0, "Easy-going"], [0.35, "Watchful"], [0.55, "Strict"], [0.75, "Suspicious of strangers"]]
## The night watch's hours, when strict towns shut their gates to strangers.
const NIGHT_FROM := 21.5
const NIGHT_TO := 6.0
## How much a guild seal lowers the standing a gate asks of you.
const GUILD_SEAL := 15
## Extra standing a shut gate asks of you at night.
const NIGHT_EXTRA := 25
## Residents who like you this much will vouch for you.
const VOUCH_REL := 40
## A guard who knows you this well won't ask you for a pass inside.
const KNOWS_REL := 30
## Tolls aren't taken from the Distrusted and Outcast: they bribe or break in.
const TOLL_FLOOR := -25
## A fine on top of the toll for someone found inside without one.
const LATE_FINE := 0.5

## What a town's shops charge and pay you, by your standing there: [charge x, pay x].
const PRICES := {"Distrusted": [1.25, 0.8], "Stranger": [1.0, 1.0], "Known": [0.97, 1.02], "Respected": [0.92, 1.06],
	"Honoured": [0.86, 1.1], "Citizen": [0.86, 1.1]}

## A trader state with its prices leaning on your standing (tier) there.
static func priced(st: Dictionary, tier: String) -> Dictionary:
	var m: Array = PRICES.get(tier, [1.0, 1.0])
	st["charge_mult"] = float(st.get("charge_mult", 1.0)) * float(m[0])
	st["pay_mult"] = float(st.get("pay_mult", 1.0)) * float(m[1])
	return st

static func is_walled(site: Dictionary) -> bool:
	return bool(site.get("walled", false))

## The town's temper from its people: {strict 0..1, need (standing to be waved in),
## toll (Marks), days (a pass lasts), night_shut, label, level}.
static func temper(site: Dictionary, data: Dictionary) -> Dictionary:
	var c: Vector2 = site.get("center", data.get("center", Vector2.ZERO))
	var lvl := Eras.zone_level(c.x, c.y)
	var brave := 0.0
	var greed := 0.0
	var guards := 0
	var friendly := 0.0
	var worried := 0
	var folk := 0
	for rec in data.get("npcs", []):
		if rec.get("dead", false) or rec.get("child", false):
			continue
		var t: Dictionary = rec.get("traits", {})
		if NPCGen.GUARD_JOBS.has(String(rec.get("job", ""))):
			guards += 1
			brave += float(t.get("brave", 0.5))
			greed += float(t.get("greedy", 0.5))
		else:
			folk += 1
			friendly += float(t.get("friendly", 0.5))
			var w := String(rec.get("worry", ""))
			if w.contains("bandit") or w.contains("raider") or w.contains("lost travellers"):
				worried += 1
	brave = brave / guards if guards > 0 else 0.5
	greed = greed / guards if guards > 0 else 0.5
	friendly = friendly / folk if folk > 0 else 0.5
	var worry := float(worried) / folk if folk > 0 else 0.0
	var strict := 0.3 + minf(float(lvl) / 55.0, 1.0) * 0.3 + (brave - 0.5) * 0.35 + worry * 0.3 - (friendly - 0.5) * 0.45 + trouble(data) * 0.08
	strict = clampf(strict, 0.05, 0.95)
	var label: String = TEMPERS[0][1]
	for t in TEMPERS:
		if strict >= float(t[0]):
			label = t[1]
	return {"strict": strict, "need": int(round(lerpf(-15.0, 45.0, strict))),
		"toll": maxi(3, int(round((4.0 + lvl * 1.5) * (0.6 + strict * 0.8) * (0.8 + greed * 0.4)))),
		"days": snappedf(3.0 - strict * 2.0, 0.25), "night_shut": strict >= 0.4, "label": label, "level": lvl}

## Trouble the traveller has made there lately: rumours of their crimes, the last few.
static func trouble(data: Dictionary) -> int:
	var n := 0
	var rumors: Array = data.get("rumors", [])
	for i in range(maxi(0, rumors.size() - 6), rumors.size()):
		var r := String(rumors[i])
		if r.begins_with("The traveller") and (r.contains("seen") or r.contains("attacked") or r.contains("destroyed") or r.contains("killed") or r.contains("sneak")):
			n += 1
		elif r.contains("killed by the traveller"):
			n += 2
	return n

static func is_night(hour: float) -> bool:
	return hour >= NIGHT_FROM or hour < NIGHT_TO

## Whether the gate lets you through, and why: {ok, why} where why is one of "wanted",
## "citizen", "pass", "standing", "stranger", "night", "outcast".
## score: your Standing there; stars: wanted there.
static func admit(tp: Dictionary, score: int, citizen: bool, guild: bool, stars: int, has_pass: bool, hour: float) -> Dictionary:
	if stars > 0:
		return {"ok": false, "why": "wanted"}
	if citizen:
		return {"ok": true, "why": "citizen"}
	if has_pass:
		return {"ok": true, "why": "pass"}
	var night := bool(tp["night_shut"]) and is_night(hour)
	if score >= need(tp, guild, night):
		return {"ok": true, "why": "standing"}
	if score <= -60:
		return {"ok": false, "why": "outcast"}
	return {"ok": false, "why": "night" if night else "stranger"}

## The standing the gate asks of you.
static func need(tp: Dictionary, guild: bool, night: bool) -> int:
	return int(tp["need"]) - (GUILD_SEAL if guild else 0) + (NIGHT_EXTRA if night else 0)

## Whether they'll sell you a pass at all (not to the Distrusted or Outcast, nor anyone wanted).
static func sells_pass(score: int, stars: int) -> bool:
	return stars == 0 and score > TOLL_FLOOR

## The toll at night (when strict towns shut their gates) is doubled.
static func toll(tp: Dictionary, hour: float) -> int:
	return int(tp["toll"]) * (2 if bool(tp["night_shut"]) and is_night(hour) else 1)

## What this guard would take to look the other way, and the odds they take it (0..1).
static func bribe(tp: Dictionary, guard: Dictionary, hour: float) -> Dictionary:
	var t: Dictionary = guard.get("traits", {})
	var greedy := float(t.get("greedy", 0.5))
	var rel := float(guard.get("rel", 0)) / 100.0
	var price := maxi(2, int(round(toll(tp, hour) * 0.6 * (1.3 - greedy * 0.5))))
	var odds := clampf(greedy * 1.15 - 0.2 + rel * 0.5 - (float(tp["strict"]) - 0.5) * 0.3, 0.03, 0.95)
	return {"price": price, "odds": odds}

## Residents who like you enough to vouch for you at the gate (living, grown, not guards).
static func vouchers(data: Dictionary) -> Array:
	var out: Array = []
	for rec in data.get("npcs", []):
		if rec.get("dead", false) or rec.get("child", false) or NPCGen.GUARD_JOBS.has(String(rec.get("job", ""))):
			continue
		if int(rec.get("rel", 0)) >= VOUCH_REL:
			out.append(rec)
	return out

## The townsfolk's mean regard for you (living, grown residents).
static func folk_regard(data: Dictionary) -> float:
	var sum := 0.0
	var n := 0
	for rec in data.get("npcs", []):
		if rec.get("dead", false) or rec.get("child", false):
			continue
		sum += float(rec.get("rel", 0))
		n += 1
	return sum / n if n > 0 else 0.0

## What a guard at the gate says when they stop you, by the reason.
static func halt_line(why: String, town: String, toll_marks: int) -> String:
	match why:
		"wanted":
			return "Not one step further. You're wanted in %s. Settle your bounty first." % town
		"outcast":
			return "Your kind isn't welcome in %s. Turn around." % town
		"night":
			return "Gates are shut till dawn. Unless you've the night toll, %d Marks." % toll_marks
	return ["Halt! State your business in %s. Toll's %d Marks." % [town, toll_marks],
		"Hold there, stranger. Nobody comes into %s without paying the toll: %d Marks." % [town, toll_marks],
		"I don't know your face. %d Marks to come through, or someone in town to speak for you." % toll_marks][absi(hash(town + str(toll_marks))) % 3]

## What the guard says waving you through, by the reason.
static func welcome_line(why: String, tier: String) -> String:
	match why:
		"citizen":
			return "Welcome home."
		"pass":
			return "Pass is good. On you go."
	return {"Known": "I know you. Go on through.", "Respected": "Good to see you again. Go on in.", "Honoured": "Make way! Welcome back to town."}.get(tier, "Go on through.")

## Whether the night portcullis mesh builds (for the tests: GateWatch needs the scene).
static func port_mesh_ok() -> bool:
	var m := GateWatch.port_mesh()
	return m != null and m.get_surface_count() > 0 and m.get_aabb().size.y > 3.0
