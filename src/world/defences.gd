class_name Defences
## The powered defences (stage 3 of the power system): turrets, an electric fence, spike
## and flame traps, an alarm bell and a searchlight. They are ordinary powered consumers
## (Power role "use", prio 2: the last to brown out) with a "defence" spec; PowerGrid runs
## them each tick once the network has shared out its power:
##   turret:  {range, damage, every (s between shots), barrels, ammo: {item: rounds each}}
##   fence:   {reach (m from the wire), damage, every}
##   spikes:  {damage, hold (s it pins an animal)}
##   flame:   {range, cone (cos of half the cone), dps}; burns its fuel store while on
##   bell:    {}  (rings while on)
##   search:  {range}  (a floodlight that follows what it sees)
## What they go for: animals that attack (an aggressive temper, or chasing someone now),
## bandits and pirates. Never you, other players, villagers or tame animals.
## A signal wire into one arms it (no wire: armed while powered). On a server only the
## game running the defence's chunk's animals ("f") shoots, so each shot lands once;
## damage goes through FaunaManager.player_hit / NPCManager.player_hit, which pass it on
## to whoever runs the target.

const AMMO_CAP := 400 ## rounds a turret holds
const FUEL_CAP := 600.0 ## seconds of burning a flame trap holds

static func spec(o: Dictionary) -> Dictionary:
	return Power.spec(o).get("defence", {})

static func kind(o: Dictionary) -> String:
	return String(spec(o).get("kind", ""))

static func is_defence(o: Dictionary) -> bool:
	return not spec(o).is_empty()

## Whether a creature is something to shoot at: it attacks people.
static func hostile_creature(c: Object) -> bool:
	if c == null or not is_instance_valid(c) or c.get("_body") == null:
		return false
	var p: Dictionary = c.get("p")
	var temper := String(p.get("temper", ""))
	if temper == "tame":
		return false
	return temper == "aggressive" or String(c.get("state")) == "chase" or p.has("boss")

## Whether a person is something to shoot at: a grown bandit or pirate.
static func hostile_npc(n: Object) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var rec: Dictionary = n.get("rec")
	if rec == null or bool(rec.get("child", false)) or float(rec.get("hp", 1.0)) <= 0.0:
		return false
	var s: Dictionary = n.get("settlement")
	return (s != null and s.has("band")) or String(rec.get("faction", "")) == "pirate"

## Ammo in your pack a turret loads: [[type, rounds each], ...].
static func ammo_in_pack(o: Dictionary) -> Array:
	var out: Array = []
	if Game.inventory == null:
		return out
	var am: Dictionary = spec(o).get("ammo", {})
	for t in am:
		if Game.inventory.count(t) > 0:
			out.append([t, int(am[t])])
	return out

## Loads a turret from your pack. Returns how many rounds went in.
static func load_ammo(o: Dictionary) -> int:
	var have := int(o["st"].get("ammo", 0))
	var put := 0
	for a in ammo_in_pack(o):
		while have + int(a[1]) <= AMMO_CAP and Game.inventory.count(a[0]) > 0:
			Game.inventory.remove_type(a[0], 1)
			have += int(a[1])
			put += int(a[1])
	o["st"]["ammo"] = have
	return put

## The fuel a flame trap burns, from its spec's "fuel" list.
static func fuel_in_pack(o: Dictionary) -> Array:
	var out: Array = []
	if Game.inventory == null:
		return out
	var fuels: Dictionary = Power.spec(o).get("fuel", {})
	for t in fuels:
		if Game.inventory.count(t) > 0:
			out.append([t, float(fuels[t])])
	return out

static func load_fuel(o: Dictionary) -> String:
	var fuel := float(o["st"].get("fuel", 0.0))
	var used := {}
	for f in fuel_in_pack(o):
		while fuel + float(f[1]) <= FUEL_CAP + float(f[1]) * 0.5 and Game.inventory.count(f[0]) > 0:
			Game.inventory.remove_type(f[0], 1)
			fuel += float(f[1])
			used[f[0]] = int(used.get(f[0], 0)) + 1
	o["st"]["fuel"] = minf(fuel, FUEL_CAP)
	var words: Array = []
	for t in used:
		words.append("%d %s" % [used[t], String(ItemDB.def(t).get("name", t)).to_lower()])
	return ", ".join(words)

## Distance from p to the segment a-b.
static func to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Whether `to` is in a cone from `at` along `fwd` (cos of half the angle) within `r`.
static func in_cone(at: Vector3, fwd: Vector3, to: Vector3, r: float, cone: float) -> bool:
	var d := to - at
	var l := d.length()
	return l <= r and l > 0.05 and (d / l).dot(fwd) >= cone

## The look-at lines of a defence.
static func lines(o: Dictionary, armed: bool) -> Array:
	var s := spec(o)
	var out: Array = []
	match kind(o):
		"turret":
			out.append("Ammo: %d rounds%s" % [int(o["st"].get("ammo", 0)), "" if int(o["st"].get("ammo", 0)) > 0 else ": load cartridges or revolver rounds"])
			out.append("Reach %d m  ·  goes for attacking animals, bandits and pirates" % int(s.get("range", 20)))
		"flame":
			out.append("Fuel: %d s of burning" % int(o["st"].get("fuel", 0.0)))
		"fence":
			out.append("Shocks any animal or outlaw touching the wire to the next fence post")
		"spikes":
			out.append("Punches up under animals and outlaws; a signal wired in fires it instead")
		"bell":
			out.append("Rings while its signal is on")
		"search":
			out.append("Follows what it sees within %d m, sweeps when there's nothing" % int(s.get("range", 60)))
	if not armed:
		out.append("Not armed: its signal is off")
	return out
